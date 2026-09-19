# Module 15 — Sécurité et durcissement

## 15.0 Objectifs et compétences

::: objectif
À la fin de ce module, je sais :

* décrire le chemin d'un paquet dans **netfilter** (hooks, tables, chaînes) et dire
  ce que `ufw`, `firewalld` et `iptables` fabriquent réellement dans `nft list ruleset` ;
* écrire, relire et corriger une politique de pare-feu complète sur une infra
  multi-machines, en raisonnant sur l'**ordre des règles** et sur le trafic *establi* ;
* traduire la même politique en `ufw` (Ubuntu) et en `firewalld` (Rocky), zones et
  rich rules comprises, sans perdre mes règles au premier `--reload` ;
* installer et régler **fail2ban** (jail, filtre, action, `bantime`/`findtime`/
  `maxretry`), écrire un filtre maison pour nginx, le tester avec `fail2ban-regex`,
  et énoncer ce que fail2ban **ne protège pas** ;
* diagnostiquer un refus **SELinux** de bout en bout : contexte attendu, AVC dans
  `audit.log`, `restorecon`, `semanage fcontext`, `semanage port`, booléens — et
  expliquer pourquoi « passer en `disabled` » n'est jamais un correctif ;
* lire un profil **AppArmor**, basculer un profil en `complain` le temps d'un
  diagnostic, et comparer honnêtement AppArmor et SELinux ;
* durcir un système : mises à jour de sécurité automatiques, surface d'écoute
  (`ss -tulpn`), `sysctl` de sécurité, `/tmp` en `noexec`, modules noyau interdits,
  politique de mots de passe, `umask`, bannière ;
* gérer des **secrets** sans les faire fuir : `.env` et ses droits, ce qui ne va
  jamais dans Git ni dans une variable de CI, `ansible-vault`, rotation ;
* produire un certificat TLS (mini-PKI de lab ou Let's Encrypt), le vérifier avec
  `openssl x509` et `openssl s_client`, configurer nginx en HTTPS correct (HSTS,
  chaîne complète) et surveiller l'expiration ;
* poser des règles **auditd** utiles, lancer un audit **lynis**, et reconnaître les
  signaux d'une intrusion (SUID nouveau, cron suspect, processus sans binaire) ainsi
  que la conduite à tenir.

Temps estimé : 8 h (module copieux, prévois deux sessions)
Prérequis : modules 03 (permissions), 04 (utilisateurs et sudo), 08 (systemd),
11 (réseau), 12 (SSH), 13 (nginx). Le module 12 couvre le durcissement SSH lui-même :
ici on ne refait pas `sshd_config`, on protège ce qu'il y a autour.
:::

---

## 15.1 Mise en place

VM concernées : **toutes**. Le gros du module se joue sur `lab-web` (10.10.10.11) et
`lab-db` (10.10.10.12) pour ufw/TLS/fail2ban, sur `lab-rhel` (10.10.10.13) pour
firewalld et SELinux, avec `lab-adm` (10.10.10.10) comme poste de pilotage.

::: attention
Ce module coupe du réseau. Un ordre de règles mal pensé sur `lab-web` te sort de ta
propre session SSH. **Prends les snapshots avant de commencer**, et garde la console
Proxmox (`qm terminal <vmid>` ou la console web) ouverte : c'est ton seul accès quand
le pare-feu te ferme la porte.

```bash
# depuis le shell Proxmox
for id in 9001 9002 9003 9004 9005; do qm snapshot $id avant-lab15; done
```
:::

Paquets, côté Ubuntu (`lab-adm`, `lab-web`, `lab-db`, `lab-ops`) :

```bash
sudo apt update
sudo apt install -y ufw fail2ban nftables nginx openssl \
     apparmor-utils auditd audispd-plugins lynis unattended-upgrades \
     libpam-pwquality
```

::: rhel
Sur `lab-rhel` (Rocky 9) :

```bash
sudo dnf install -y firewalld fail2ban nftables nginx openssl \
     policycoreutils-python-utils setroubleshoot-server audit lynis \
     dnf-automatic
```

`policycoreutils-python-utils` fournit `semanage` et `audit2allow` : sans lui, la
moitié du travail SELinux est impossible. `lynis` vient d'EPEL
(`sudo dnf install -y epel-release` d'abord).
:::

Terrain de jeu (idempotent) :

```bash
sudo bash ~/workbook/scripts/setup/setup_M15.sh
```

Il crée `~/lab15/`, une application web factice servie par nginx sur `lab-web`, un
journal nginx d'attaque à analyser, une base de référence SUID, quelques traces
d'intrusion à découvrir, et les répertoires de la mini-PKI. Il **n'active aucun
pare-feu** et **ne touche à aucune règle** : c'est ton travail.

---

## 15.2 Rappel express

### Netfilter : qui fait quoi

```text
                 paquet entrant
                       |
      [prerouting] --- décision de routage ---> [forward] --> [postrouting]
                       |                                          ^
                    [input]                                       |
                       |                                       [output]
                 processus local -----------------------------------
```

Un seul moteur dans le noyau : **netfilter**. Au-dessus, plusieurs frontaux qui
écrivent dans le même endroit :

| Frontal | Écrit via | Visible avec |
|---|---|---|
| `nft` | nftables (natif) | `nft list ruleset` |
| `iptables` (Ubuntu 24.04, Rocky 9) | `iptables-nft`, traduit en nftables | `nft list ruleset` |
| `ufw` | `iptables-nft` | `ufw status` **et** `nft list ruleset` |
| `firewalld` | nftables (backend par défaut) | `firewall-cmd --list-all` |

Conséquence pratique : `ufw status` te montre ce que **ufw** croit, `nft list ruleset`
te montre ce que **le noyau** applique. Quand les deux divergent, le noyau a raison.

### ufw (Ubuntu)

| Commande | Effet |
|---|---|
| `ufw default deny incoming` | politique par défaut de la chaîne input |
| `ufw allow from 10.10.10.10 to any port 22 proto tcp` | règle sourcée |
| `ufw status numbered` | règles **avec leur numéro** (indispensable) |
| `ufw insert 1 deny from 10.0.0.0/8` | insère en tête |
| `ufw delete 4` / `ufw delete allow 80/tcp` | supprime par numéro / par règle |
| `ufw limit 22/tcp` | 6 connexions / 30 s par IP, puis DROP |
| `ufw app list` / `ufw allow 'Nginx Full'` | profils de `/etc/ufw/applications.d/` |
| `ufw logging medium` | journalise dans `/var/log/ufw.log` |
| `ufw reset` | tout efface (et désactive) |

Premier match gagnant, de haut en bas. Une nouvelle règle est **ajoutée à la fin** :
si un `deny` général est déjà passé, ton `allow` ne sera jamais atteint. Les fichiers
`/etc/ufw/before.rules` et `after.rules` encadrent tes règles et ne sont **pas**
affichés par `ufw status`.

### firewalld (Rocky)

| Commande | Effet |
|---|---|
| `firewall-cmd --get-active-zones` | zones actives et interfaces/sources associées |
| `firewall-cmd --list-all [--zone=Z]` | contenu complet d'une zone |
| `firewall-cmd --permanent --add-service=https` | écrit la conf, **sans effet immédiat** |
| `firewall-cmd --reload` | charge le permanent, **jette le runtime** |
| `firewall-cmd --runtime-to-permanent` | fige les essais réussis |
| `firewall-cmd --permanent --zone=internal --add-source=10.10.10.11/32` | range une IP dans une zone |
| `--add-rich-rule='rule family="ipv4" source address="10.10.10.11/32" port port="5432" protocol="tcp" accept'` | règle fine |

Une règle sans `--permanent` disparaît au `--reload` ou au reboot. Une règle avec
`--permanent` **et sans `--reload`** n'est pas active. Les deux erreurs sont
symétriques et coûtent chacune une demi-heure.

### fail2ban

```text
/etc/fail2ban/jail.local    <- ta configuration (jamais jail.conf)
/etc/fail2ban/jail.d/*.conf <- fragments
/etc/fail2ban/filter.d/*.conf <- les failregex, avec <HOST>
/etc/fail2ban/action.d/*.conf <- comment bannir (iptables, ufw, nftables...)
```

| Réglage | Sens |
|---|---|
| `maxretry` | nombre d'échecs avant bannissement |
| `findtime` | fenêtre glissante dans laquelle on les compte |
| `bantime` | durée du bannissement (`-1` = définitif) |
| `ignoreip` | IP jamais bannies (**mets-y ton bastion**) |
| `backend` | `auto`, `systemd` (journal) ou `polling` (fichier) |

`fail2ban-client status`, `fail2ban-client status sshd`,
`fail2ban-client set sshd unbanip 10.10.10.10`,
`fail2ban-regex /var/log/nginx/access.log /etc/fail2ban/filter.d/mon-filtre.conf`.

### SELinux (Rocky)

```text
contexte = utilisateur:rôle:TYPE:niveau
           system_u:object_r:httpd_sys_content_t:s0
                              ^^^^^^^^^^^^^^^^^^  99 % des problèmes sont là
```

| Commande | Usage |
|---|---|
| `getenforce` / `setenforce 0` | mode courant / permissive **temporaire** |
| `ls -Z`, `ps -Z`, `id -Z` | contextes fichiers, processus, session |
| `restorecon -Rv /var/www` | réapplique le contexte **attendu par la politique** |
| `semanage fcontext -a -t httpd_sys_content_t "/srv/web(/.*)?"` | change l'attendu |
| `semanage port -a -t http_port_t -p tcp 8088` | autorise un port à un service |
| `getsebool -a` / `setsebool -P httpd_can_network_connect on` | booléens |
| `ausearch -m AVC -ts recent` / `audit2why` / `audit2allow` | lire et traduire les refus |

`cp` prend le contexte du **répertoire de destination**. `mv` **conserve** celui de
la source : c'est la panne SELinux la plus fréquente au monde.

### AppArmor (Ubuntu)

| Commande | Usage |
|---|---|
| `aa-status` | profils chargés, en enforce / en complain, processus confinés |
| `aa-complain /etc/apparmor.d/usr.sbin.nginx` | passe un profil en observation |
| `aa-enforce ...` / `apparmor_parser -r <profil>` | réapplique |
| `aa-logprof` | propose des règles à partir des refus journalisés |
| `journalctl -k \| grep apparmor=\"DENIED\"` | les refus |

AppArmor confine **par chemin**, SELinux **par étiquette**. AppArmor n'a d'effet que
sur les binaires qui ont un profil ; SELinux étiquette tout le système.

### Durcissement — le minimum vital

```bash
ss -tulpn                       # qui écoute, sur quoi, lancé par qui
systemctl list-units --type=service --state=running
find / -xdev -perm -4000 -type f 2>/dev/null   # SUID
awk -F: '($2==""){print $1}' /etc/shadow       # mots de passe vides
awk -F: '($3==0){print $1}' /etc/passwd        # comptes UID 0
```

```ini
# /etc/sysctl.d/99-durcissement.conf
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.tcp_syncookies = 1
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.randomize_va_space = 2
kernel.yama.ptrace_scope = 1
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
```

`sudo sysctl --system` applique, `sysctl -a | grep <clé>` vérifie.

### TLS en six commandes

```bash
openssl x509 -in srv.crt -noout -subject -issuer -dates
openssl x509 -in srv.crt -noout -ext subjectAltName
openssl x509 -in srv.crt -noout -checkend 2592000   # expire sous 30 j ?
openssl verify -CAfile ca.crt srv.crt
openssl s_client -connect 10.10.10.11:443 -servername app.lab.local </dev/null
openssl rsa -in srv.key -noout -modulus | openssl sha256   # clé = cert ?
```

Le `ssl_certificate` de nginx doit contenir **le certificat serveur suivi de la
chaîne intermédiaire**, dans cet ordre. Un navigateur pardonne parfois une chaîne
incomplète (il la reconstruit), `curl` et les clients mobiles non.

### Pièges classiques

* `ufw allow 22` ajouté **après** un `deny` large : jamais atteint.
* `firewall-cmd --add-port=8080/tcp` sans `--permanent` : ça marche jusqu'au reboot.
* `fail2ban` sans `ignoreip` : tu te bannis en testant.
* `setenforce 0` « pour voir » puis oublié : la prod tourne sans MAC pendant six mois.
* Certificat régénéré, nginx pas rechargé : `openssl s_client` sert l'ancien.
* Un secret poussé puis supprimé dans un commit suivant : **il est toujours dans
  l'historique Git**. Le seul correctif est la rotation.

---

## 15.3 Quiz — QCM

**Q15.1** — Sur `lab-web` (Ubuntu 24.04), tu as tout configuré avec `ufw`.
`sudo iptables -S` affiche les chaînes `ufw-before-input`, `ufw-user-input`… et
`sudo nft list ruleset` affiche exactement les mêmes règles dans une table
`ip filter`. Pourquoi les deux outils montrent-ils la même chose ?

a) `nft` sait lire les règles iptables et les convertit à l'affichage
b) `iptables` sur Ubuntu 24.04 est en réalité `iptables-nft` : les règles sont
   stockées dans nftables, les deux commandes interrogent le même moteur
c) ufw écrit deux fois, une fois dans chaque sous-système, pour la compatibilité
d) le noyau maintient une synchronisation permanente entre iptables et nftables

**Q15.2** — Tu veux que `lab-db` n'accepte PostgreSQL que depuis `lab-web`. Tu tapes,
dans cet ordre :

```bash
sudo ufw default deny incoming
sudo ufw allow 5432/tcp
sudo ufw allow from 10.10.10.11 to any port 5432 proto tcp
sudo ufw enable
```

Quel est le résultat réel ?

a) seul `lab-web` peut se connecter au port 5432
b) tout le monde peut se connecter au port 5432
c) personne ne peut se connecter, les deux règles se neutralisent
d) `ufw` refuse la troisième règle comme redondante

**Q15.3** — `sudo ufw status numbered` sur `lab-web` :

```console
     To                         Action      From
     --                         ------      ----
[ 1] 22/tcp                     DENY IN     Anywhere
[ 2] 80,443/tcp (Nginx Full)    ALLOW IN    Anywhere
[ 3] 22/tcp                     ALLOW IN    10.10.10.10
```

Tu es sur `lab-adm` (10.10.10.10) et tu tentes `ssh 10.10.10.11`. Que se passe-t-il ?

a) la connexion aboutit, la règle 3 est plus spécifique
b) la connexion est refusée, la règle 1 gagne parce qu'elle vient avant
c) la connexion aboutit, ufw trie automatiquement par spécificité
d) ufw refuse d'appliquer un jeu de règles contradictoire

**Q15.4** — Sur `lab-rhel`, tu ouvres le port de ton API :

```bash
sudo firewall-cmd --add-port=8080/tcp
```

Le dev confirme que ça marche. Trois jours plus tard, après un reboot, ça ne marche
plus. Pourquoi, et quelle commande aurait évité ça ? **Deux réponses correctes.**

a) la règle était en runtime uniquement, perdue au redémarrage
b) `firewall-cmd --permanent --add-port=8080/tcp` puis `--reload`
c) `firewall-cmd --runtime-to-permanent` juste après le test réussi
d) il fallait `systemctl enable firewalld`, la règle aurait survécu

**Q15.5** — Sur `lab-rhel`, `firewall-cmd --get-active-zones` renvoie :

```console
public
  interfaces: ens18
```

Tu ajoutes `firewall-cmd --permanent --zone=internal --add-service=http` puis
`--reload`. Le port 80 est-il ouvert ?

a) oui, les services ajoutés à une zone sont globaux
b) non : aucune interface ni source n'est rattachée à `internal`, la zone n'est
   jamais évaluée
c) oui, mais seulement depuis le réseau local
d) non, `http` n'est pas un service firewalld valide

**Q15.6** — Ta jail `nginx-scan` est active, et
`fail2ban-regex /var/log/nginx/access.log /etc/fail2ban/filter.d/nginx-scan.conf`
annonce **312 correspondances** provenant de 10.10.10.50. Pourtant
`fail2ban-client status nginx-scan` affiche `Currently failed: 0` et
`Total failed: 0`, et personne n'est banni. La jail a `findtime = 10m`,
`maxretry = 6`. Cause la plus probable ?

a) les 312 lignes datent d'hier : fail2ban les lit, mais ne compte que les échecs
   tombant dans la fenêtre `findtime` par rapport à l'heure courante
b) `maxretry = 6` est trop élevé pour 312 échecs
c) `fail2ban-regex` et le démon n'utilisent pas le même moteur d'expressions
d) il manque `enabled = true`, mais la jail apparaît quand même dans `status`

**Q15.7** — `fail2ban-client status sshd` affiche `Currently banned: 1`, ton IP.
Quelle commande te débannit **sans redémarrer le service ni vider la jail** ?

a) `sudo fail2ban-client reload sshd`
b) `sudo fail2ban-client set sshd unbanip 10.10.10.10`
c) `sudo iptables -F`
d) `sudo fail2ban-client stop sshd`

**Q15.8** — Sur `lab-rhel`, un développeur a déposé son site ainsi :

```bash
sudo mv /home/mathieu/site/index.html /var/www/html/index.html
```

nginx renvoie `403 Forbidden` pour ce fichier uniquement. `ls -l` montre
`-rw-r--r-- root root`. Quelle est la cause ?

a) les droits Unix, il faut `chmod 644` (déjà le cas) puis `chown nginx`
b) le fichier a gardé le contexte SELinux `user_home_t`, que nginx n'a pas le droit
   de lire
c) nginx ne sert pas les fichiers appartenant à root
d) le fichier a un attribut immuable posé par `mv`

**Q15.9** — Pour corriger la situation de Q15.8 **durablement et proprement** :

a) `sudo setenforce 0`
b) `sudo restorecon -v /var/www/html/index.html`
c) `sudo chcon -t httpd_sys_content_t /var/www/html/index.html`
d) `sudo semanage fcontext -a -t httpd_sys_content_t "/var/www/html(/.*)?"`

**Q15.10** — Ton application PHP sur `lab-rhel` doit appeler une API externe en
HTTPS. SELinux est en enforcing, l'appel échoue, `audit.log` contient un AVC
`denied { name_connect }` pour `httpd_t`. Le correctif recommandé ?

a) `setsebool -P httpd_can_network_connect on`
b) `audit2allow -a -M monmodule && semodule -i monmodule.pp`
c) passer SELinux en permissive
d) `semanage port -a -t http_port_t -p tcp 443`

**Q15.11** — Sur Rocky, `/etc/selinux/config` contient `SELINUX=disabled` depuis six
mois. Tu remets `SELINUX=enforcing` et tu redémarres. Que se passe-t-il ?

a) rien de particulier, SELinux redémarre en enforcing
b) tous les fichiers créés pendant la période `disabled` n'ont pas d'étiquette : la
   machine risque de ne plus démarrer correctement sans un réétiquetage complet
c) SELinux repasse automatiquement en permissive au premier refus
d) le noyau refuse de démarrer avec un contexte manquant

**Q15.12** — `aa-status` sur `lab-web` affiche :

```console
32 profiles are loaded.
30 profiles are in enforce mode.
2 profiles are in complain mode.
   /usr/sbin/nginx
```

Que signifie exactement le mode `complain` pour nginx ?

a) nginx est bloqué mais les refus sont journalisés
b) le profil n'est pas appliqué : les violations sont journalisées mais autorisées
c) nginx ne démarrera pas tant que le profil est en complain
d) complain est l'ancien nom de enforce

**Q15.13** — Tu lis dans `/etc/fstab` de `lab-web` :

```text
tmpfs /tmp tmpfs defaults,noexec,nosuid,nodev 0 0
```

Quelle conséquence concrète dois-tu anticiper ?

a) aucune, c'est transparent
b) certains installeurs (`apt`, scripts `.run`, compilations) qui extraient un
   binaire dans `/tmp` et l'exécutent échoueront ; il faut leur donner un `TMPDIR`
c) les fichiers de `/tmp` ne seront plus effacés au reboot
d) `/tmp` deviendra accessible en lecture seule

**Q15.14** — `kernel.kptr_restrict = 2` sert à :

a) empêcher le chargement de modules noyau
b) masquer les adresses mémoire du noyau dans `/proc/kallsyms` et les traces, pour
   tous les utilisateurs y compris root
c) restreindre `dmesg` aux utilisateurs privilégiés
d) activer l'ASLR du noyau

**Q15.15** — Un dev a poussé `.env` contenant le mot de passe de production, puis a
fait `git rm .env && git commit -m "oups"` et poussé. **Deux réponses correctes.**

a) le secret est toujours lisible dans l'historique du dépôt
b) le `git rm` suffit, l'objet est supprimé du dépôt distant
c) il faut considérer le secret comme compromis et le **changer**
d) `.gitignore` ajouté après coup supprime le fichier de l'historique

**Q15.16** — Tu génères un certificat auto-signé pour `app.lab.local` ainsi :

```bash
openssl req -x509 -newkey rsa:2048 -nodes -keyout srv.key \
  -out srv.crt -days 365 -subj "/CN=app.lab.local"
```

`curl https://app.lab.local` (avec le CA importé) échoue quand même. Pourquoi ?

a) `rsa:2048` est refusé depuis OpenSSL 3
b) le certificat n'a pas de `subjectAltName` : les clients modernes ignorent le `CN`
c) `-nodes` produit une clé illisible par nginx
d) il manque `-sha256`, la signature est en SHA-1

**Q15.17** — `openssl s_client -connect 10.10.10.11:443 </dev/null` affiche
`Verify return code: 21 (unable to verify the first certificate)`, alors que le
navigateur, lui, affiche un cadenas vert. Que faut-il en conclure ?

a) le navigateur se trompe
b) il manque le certificat intermédiaire dans le fichier servi par nginx ; le
   navigateur l'a complété depuis son propre cache, pas les autres clients
c) le certificat est expiré
d) `s_client` ne sait pas valider les certificats Let's Encrypt

**Q15.18** — Sur une machine suspecte, `ls -l /proc/2481/exe` affiche :

```console
lrwxrwxrwx 1 root root 0 Sep 18 03:12 /proc/2481/exe -> /tmp/.x (deleted)
```

Qu'est-ce que cela indique, et quelle est la première action ? **Deux réponses.**

a) un processus tourne à partir d'un binaire effacé du disque : signal fort de
   compromission
b) c'est normal après une mise à jour de paquet
c) récupérer le binaire avec `cp /proc/2481/exe /preuves/binaire.bin` avant de tuer
   quoi que ce soit
d) tuer immédiatement le processus pour arrêter l'attaque

---

## 15.4 Quiz — questions ouvertes

**QO15.1** — Explique, en suivant le chemin d'un paquet TCP entrant, pourquoi une
politique `default deny incoming` ne casse **pas** les réponses aux requêtes que ta
machine a elle-même initiées. Nomme le mécanisme noyau et l'endroit exact où ufw le
met en œuvre.

::: repondre
lignes: 8
:::

**QO15.2** — *On te demande en entretien* : « Quelle différence entre `ufw` et
`firewalld` ? Lequel choisirais-tu pour un parc de 200 serveurs, et pourquoi ? »
Réponds en distinguant le modèle de données (règles à plat contre zones), la gestion
du permanent/runtime, et l'automatisation.

::: repondre
lignes: 10
:::

**QO15.3** — Décris ta démarche complète quand un collègue te dit : « le pare-feu a
l'air bon, `ufw status` montre bien la règle, mais le trafic ne passe pas ». Donne
les commandes dans l'ordre et ce que tu cherches dans chaque sortie.

::: repondre
lignes: 10
:::

**QO15.4** — Un service tourne correctement quand SELinux est en `permissive` et
échoue en `enforcing`. Décris la méthode complète pour transformer ce constat en
correctif propre, de la collecte des AVC jusqu'au module de politique. Précise à
quel moment `audit2allow` est une bonne idée et à quel moment c'en est une mauvaise.

::: repondre
lignes: 12
:::

**QO15.5** — *On te demande en entretien* : « fail2ban protège-t-il contre le
bruteforce SSH ? » Réponds en nuançant : ce que ça bloque réellement, quatre
situations où ça ne sert à rien, et ce que tu mets en place à la place ou en
complément.

::: repondre
lignes: 10
:::

**QO15.6** — Compare AppArmor et SELinux sur cinq axes : modèle (chemin/étiquette),
couverture par défaut, coût d'exploitation, diagnostic d'un refus, et ce qui se passe
quand un fichier est déplacé. Conclus sur le choix que tu ferais pour un serveur
applicatif maison.

::: repondre
lignes: 10
:::

**QO15.7** — Une équipe de dev te demande de stocker le mot de passe de la base dans
une variable d'environnement du runner CI, « c'est masqué dans l'interface ». Liste
au moins cinq façons dont ce secret peut fuir malgré le masquage, puis propose une
architecture de gestion des secrets réaliste pour cette équipe.

::: repondre
lignes: 10
:::

**QO15.8** — Explique la chaîne de confiance TLS : ce que contient un certificat, ce
que le client vérifie exactement, dans quel ordre, et ce que nginx doit servir.
Explique ensuite pourquoi une erreur de chaîne se voit sur `curl` mais parfois pas
dans le navigateur.

::: repondre
lignes: 10
:::

**QO15.9** — Tu prends l'astreinte et tu reçois cette alerte : « connexion SSH
réussie pour le compte `postgres` à 03h14 depuis une IP publique ». Détaille ta
conduite à tenir dans les 30 premières minutes : ce que tu regardes, dans quel ordre,
ce que tu **ne fais pas**, et comment tu préserves les preuves.

::: repondre
lignes: 12
:::

**QO15.10** — Qu'est-ce qu'un CIS Benchmark ? Explique la différence entre niveau 1
et niveau 2, ce que « scored » signifie, et pourquoi appliquer un benchmark à 100 %
sur un serveur applicatif existant est généralement une mauvaise idée.

::: repondre
lignes: 8
:::

---

## 15.5 Exercices guidés ★

**E15.1** — Sur `lab-web`, affiche l'intégralité des règles réellement chargées dans
le noyau, avec les compteurs de paquets, sans passer par `ufw` ni `iptables`. Repère
la chaîne qui reçoit les paquets destinés à la machine elle-même.

**E15.2** — Prouve que la commande `iptables` de `lab-web` n'est pas l'implémentation
historique : donne la commande qui affiche le backend utilisé, et celle qui liste les
alternatives disponibles sur le système.

**E15.3** — Active ufw sur `lab-web` **sans perdre ta session SSH**. Décris dans ton
compte rendu l'ordre exact des commandes et pourquoi cet ordre évite la coupure.

**E15.4** — Ouvre 80 et 443 sur `lab-web` en utilisant un profil d'application plutôt
qu'une liste de ports. Affiche la liste des profils disponibles et le contenu de
celui que tu as choisi.

**E15.5** — Sur `lab-web`, autorise SSH uniquement depuis `lab-adm`, et vérifie avec
`ufw status numbered` que la règle est bien placée **avant** toute règle de refus.
Donne la commande qui déplacerait une règle mal placée en position 1.

**E15.6** — Limite les tentatives de connexion SSH à 6 par 30 secondes et par IP, en
une seule commande ufw. Affiche ensuite dans `nft list ruleset` la structure qui
implémente ce comptage.

**E15.7** — Active la journalisation ufw en niveau `medium`, provoque un paquet
refusé depuis `lab-adm`, et extrais du journal la ligne correspondante en affichant
uniquement l'IP source et le port de destination.

**E15.8** — Sur `lab-rhel`, affiche la zone active, la liste des services ouverts, et
le contenu complet de la zone en une seule commande. Puis ouvre HTTPS de façon
permanente et rends-le actif immédiatement, en deux commandes.

**E15.9** — Sur `lab-rhel`, écris une rich rule qui autorise le port 5432/tcp
uniquement depuis 10.10.10.11, de façon permanente, et vérifie qu'elle apparaît bien
dans `--list-all`.

**E15.10** — Sur `lab-web`, écris `/etc/fail2ban/jail.local` avec : bannissement de
1 h, fenêtre de 10 minutes, 4 échecs, `lab-adm` jamais banni, et la jail `sshd`
activée. Recharge fail2ban et prouve que la jail est active.

**E15.11** — Utilise `fail2ban-regex` pour tester le filtre `sshd` fourni contre
`~/lab15/logs/auth-attaque.log` et indique combien de lignes correspondent, combien
sont ignorées, et quelles IP seraient bannies.

**E15.12** — Sur `lab-rhel`, affiche le contexte SELinux de `/var/www/html`, celui du
processus nginx, et l'état du booléen `httpd_can_network_connect`, en trois commandes.

**E15.13** — Sur `lab-rhel`, fais écouter nginx sur le port 8088 avec SELinux en
enforcing. Donne les deux commandes nécessaires (une pour nginx, une pour SELinux) et
la commande qui prouve que 8088 est désormais un port HTTP autorisé.

**E15.14** — Sur `lab-web`, liste tous les ports en écoute avec le processus et
l'utilisateur associés, puis produis la liste des services qui écoutent sur autre
chose que `127.0.0.1` — c'est ta surface d'exposition.

**E15.15** — Applique les `sysctl` de durcissement du rappel express via un fichier
dans `/etc/sysctl.d/`, active-les sans reboot, et prouve que `rp_filter` et
`kptr_restrict` ont bien les valeurs attendues.

**E15.16** — Génère une autorité de certification de lab (clé 4096 bits, certificat
valable 10 ans, `CN=Lab Local CA`) dans `~/lab15/pki/`, avec des droits interdisant
la lecture de la clé privée à quiconque sauf son propriétaire. Affiche le sujet et
les dates du certificat obtenu.

**E15.17** — Toujours dans `~/lab15/pki/`, produis un certificat serveur pour
`app.lab.local` signé par ta CA, avec un `subjectAltName` contenant
`DNS:app.lab.local` et `IP:10.10.10.11`. Vérifie la chaîne avec `openssl verify`.

**E15.18** — Écris la commande qui répond par oui ou non (code retour) à la question
« ce certificat expire-t-il dans moins de 30 jours ? », utilisable telle quelle dans
un script de supervision.

**E15.19** — Pose une règle auditd qui trace toute modification de `/etc/passwd` et
`/etc/shadow` avec la clé `identite`, charge-la sans redémarrer auditd, déclenche-la,
et retrouve l'événement.

**E15.20** — Lance un audit `lynis` sur `lab-web`, récupère l'indice de durcissement
et les cinq premières suggestions, et dis où se trouve le rapport machine exploitable.

---

## 15.6 Labs ★★

### **L15.1** — Politique de pare-feu de l'infrastructure

::: contexte
Audit de sécurité dans trois semaines. L'auditeur a demandé le « schéma des flux
autorisés ». Il n'existe pas : aucune machine du lab n'a de pare-feu actif. On te
demande d'écrire et d'appliquer la politique, machine par machine, et de produire la
matrice des flux qui servira de référence.
:::

Politique cible :

| Depuis → vers | Flux autorisés |
|---|---|
| Internet / LAN → `lab-web` | 80/tcp, 443/tcp |
| `lab-adm` → toutes | 22/tcp |
| `lab-web` → `lab-db` | 5432/tcp |
| toute autre combinaison | refusée |

1. Sur `lab-web` : politique par défaut refus en entrée, autorisation en sortie,
   ouverture de 80 et 443 depuis n'importe où, et de 22 depuis 10.10.10.10 seulement.
   Active ufw sans te couper — et vérifie depuis `lab-adm` que tu peux te reconnecter
   **avant** de fermer ta session en cours.
2. Sur `lab-db` : même base, mais 5432/tcp uniquement depuis 10.10.10.11, et 22/tcp
   uniquement depuis 10.10.10.10. Rien d'autre.
3. Sur `lab-adm` : 22/tcp depuis le réseau 10.10.10.0/24 uniquement, rien d'autre en
   entrée.
4. Sur `lab-rhel`, la même politique que `lab-web` mais avec firewalld : zone par
   défaut `public` avec http/https, et une source 10.10.10.10 rangée dans une zone
   qui autorise SSH. Tout doit survivre à un `firewall-cmd --reload` **et** à un
   reboot.
5. Depuis `lab-adm`, écris `~/lab15/matrice-flux.md` : un tableau des flux testés
   (source, destination, port, résultat attendu, résultat observé). Teste au moins
   six flux, dont trois qui doivent échouer. Utilise `nc -zv` ou
   `timeout 3 bash -c '</dev/tcp/10.10.10.12/5432'`.
6. Sur `lab-web`, active la journalisation ufw et montre une ligne de refus
   correspondant à un de tes tests négatifs.

::: astuce
Pour ne pas te couper : ajoute d'abord la règle qui autorise SSH depuis `lab-adm`,
**puis** `ufw enable`. Et garde la console Proxmox ouverte. Si tu te coupes quand
même, `ufw disable` depuis la console te rend la main.
:::

::: check
Critère de succès : chaque machine applique sa politique, les six flux de la matrice
donnent le résultat attendu, et rien ne casse après un reboot.

```bash
bash check_M15_01.sh     # à lancer sur chaque VM concernée
```
:::

---

### **L15.2** — fail2ban : jail SSH et filtre nginx maison

::: contexte
Le journal nginx de `lab-web` montre depuis deux jours un scan permanent :
quelqu'un parcourt `/wp-login.php`, `/.env`, `/admin.php`, `/phpmyadmin/` à raison de
plusieurs centaines de requêtes par heure. Ça ne casse rien, mais ça pollue les
métriques et ça finira par trouver quelque chose. On te demande de bannir ces
sources, sans jamais bannir le bastion ni le monitoring.
:::

Le setup a déposé un journal d'attaque réaliste dans `~/lab15/logs/acces-scan.log`.

1. Écris `/etc/fail2ban/jail.local` avec des valeurs par défaut explicites :
   `bantime = 1h`, `findtime = 10m`, `maxretry = 4`, `ignoreip` contenant
   `127.0.0.1/8`, `::1` et `10.10.10.10`. Active la jail `sshd`.
2. Vérifie le `logpath` réellement utilisé par la jail `sshd` sur Ubuntu 24.04. Si
   `/var/log/auth.log` n'existe pas sur ta machine, bascule la jail en
   `backend = systemd` et explique dans ton compte rendu ce que ça change.
3. Écris un filtre `/etc/fail2ban/filter.d/nginx-scan.conf` qui détecte, dans le
   format de log `combined`, toute requête aboutissant à un code 404 ou 403 sur l'un
   des chemins suivants : `/wp-login.php`, `/.env`, `/admin.php`, `/phpmyadmin/`,
   `/.git/config`.
4. Teste-le **sur le fichier fourni** avec `fail2ban-regex`, jusqu'à obtenir au moins
   20 correspondances. Vérifie ensuite, avec `--print-all-matched`, qu'aucune
   requête légitime n'est attrapée : un faux positif ici, c'est un client banni.
5. Crée la jail `nginx-scan` correspondante : `maxretry = 6`, `findtime = 5m`,
   `bantime = 2h`, `logpath = /var/log/nginx/access.log`, `port = http,https`.
6. Provoque un vrai bannissement depuis `lab-db` (six requêtes vers `/.env` avec
   `curl`), constate le bannissement avec `fail2ban-client status nginx-scan`, puis
   retrouve dans `nft list ruleset` la structure où l'IP a été ajoutée.
7. Débannis `lab-db` sans redémarrer fail2ban.
8. Écris dans `~/lab15/fail2ban-limites.md` trois attaques que ta configuration ne
   verra pas, avec une phrase d'explication chacune.

::: check
Critère de succès : `fail2ban-client status` liste les deux jails, `fail2ban-regex`
sur `~/lab15/logs/acces-scan.log` renvoie au moins 20 correspondances avec ton filtre,
et une IP de test est bannie puis débannie.

```bash
bash check_M15_02.sh
```
:::

---

### **L15.3** — SELinux : mettre une application en production sans le désactiver

::: contexte
Sur `lab-rhel`, l'équipe applicative livre une API qui doit être servie par nginx
depuis `/srv/api/public`, écouter sur le port 8088, et appeler un service distant en
HTTP. Leur procédure d'installation commence par `setenforce 0`. Ta mission : faire
tourner exactement la même chose en `enforcing`, et leur rendre une procédure propre.
:::

1. Vérifie le mode SELinux courant et celui configuré au démarrage. Note la
   différence entre les deux commandes qui répondent à ces questions.
2. Crée `/srv/api/public/index.html` et configure nginx pour le servir sur le port
   8088. Démarre nginx : il échoue. Lis l'erreur, puis trouve l'AVC correspondant
   dans le journal d'audit.
3. Corrige le problème de **port** avec `semanage`, sans toucher au mode SELinux.
4. nginx démarre, mais renvoie 403. Compare `ls -Zd /srv/api/public` avec
   `ls -Zd /usr/share/nginx/html`. Déduis-en le type attendu.
5. Déclare le contexte attendu pour `/srv/api(/.*)?` avec `semanage fcontext`, puis
   applique-le. Explique pourquoi `chcon` seul aurait été une mauvaise réponse.
6. L'application doit maintenant faire un appel sortant vers `http://10.10.10.11/`.
   Ajoute dans la conf nginx un `location /api/` avec `proxy_pass`. Ça échoue.
   Trouve le booléen qui débloque, active-le de façon persistante, et explique la
   différence entre `setsebool` et `setsebool -P`.
7. Produis `~/lab15/procedure-selinux.md` : la procédure d'installation corrigée à
   rendre à l'équipe applicative, sans aucun `setenforce`.
8. Bonus diagnostic : relance `ausearch -m AVC -ts today` et montre qu'il n'y a plus
   de refus pour `httpd_t`.

::: attention
`audit2allow -a -M tout` suivi de `semodule -i tout.pp` « marcherait » aussi. C'est
exactement ce qu'on te demande de ne pas faire ici : un module généré sans lecture
accorde tout ce qui a été refusé, y compris ce qui n'aurait jamais dû l'être. Le
corrigé explique où est la limite.
:::

::: check
Critère de succès : `getenforce` renvoie `Enforcing`, `curl http://10.10.10.13:8088/`
répond 200, `curl http://10.10.10.13:8088/api/` atteint `lab-web`, et
`ausearch -m AVC -ts recent` ne remonte plus de refus `httpd_t`.

```bash
bash check_M15_03.sh
```
:::

---

### **L15.4** — Mini-PKI et HTTPS correct sur `lab-web`

::: contexte
Le lab n'a pas d'accès Let's Encrypt (pas de DNS public). On te demande de monter une
autorité de certification interne, d'émettre le certificat de `app.lab.local`, de
configurer nginx en HTTPS conforme, de distribuer le CA sur `lab-adm`, et de mettre
en place une surveillance d'expiration — parce que le vrai incident TLS, c'est
toujours l'expiration.
:::

Travaille dans `~/lab15/pki/` sur `lab-adm`, puis déploie sur `lab-web`.

1. Crée la CA : clé RSA 4096 protégée en 0600, certificat auto-signé valable
   3650 jours, `CN=Lab Local CA`. La clé de la CA ne doit **jamais** quitter
   `lab-adm`.
2. Crée la clé serveur et une CSR pour `app.lab.local`, puis signe-la avec ta CA en
   incluant un `subjectAltName` avec `DNS:app.lab.local`, `DNS:lab-web.lab.local` et
   `IP:10.10.10.11`, et une validité de 397 jours maximum.
3. Vérifie ton travail avant de déployer : sujet, émetteur, dates, SAN, et
   correspondance clé/certificat (les empreintes des modules doivent être égales).
4. Déploie sur `lab-web` : certificat dans `/etc/ssl/certs/`, clé dans
   `/etc/ssl/private/` avec les droits qui vont bien (qui doit pouvoir lire la clé ?).
5. Configure nginx : écoute 443 en TLS, `ssl_protocols TLSv1.2 TLSv1.3`, redirection
   permanente de 80 vers 443, en-tête HSTS avec `max-age` d'au moins deux ans, et
   `ssl_session_tickets off`. Teste la configuration avant de recharger.
6. Ajoute `app.lab.local` dans `/etc/hosts` de `lab-adm`, installe le CA dans le
   magasin système d'Ubuntu, et prouve que `curl https://app.lab.local` réussit
   **sans `-k`**.
7. Inspecte ce que sert réellement nginx avec `openssl s_client` : version TLS
   négociée, chaîne présentée, et code de vérification.
8. Écris `~/lab15/bin/verif-certs.sh` : prend une liste `hôte:port`, se connecte à
   chacun, affiche le nom, la date d'expiration et le nombre de jours restants, et
   sort en code 2 si un certificat expire dans moins de 15 jours, 1 si moins de 30.

::: rhel
Sur Rocky, le magasin d'autorités est `/etc/pki/ca-trust/source/anchors/` et la
commande de mise à jour est `update-ca-trust extract`. Sur Ubuntu :
`/usr/local/share/ca-certificates/` et `update-ca-certificates`.
:::

::: check
Critère de succès : `curl -sI https://app.lab.local` depuis `lab-adm` renvoie 200 sans
`-k`, l'en-tête `Strict-Transport-Security` est présent, `openssl s_client` affiche
`Verify return code: 0 (ok)`, et `verif-certs.sh` fonctionne sur au moins deux hôtes.

```bash
bash check_M15_04.sh
```
:::

---

### **L15.5** — Durcissement et audit de `lab-ops`

::: contexte
`lab-ops` a été montée à l'arrache il y a six mois pour « tester Docker », et elle
est devenue la machine de CI. Personne ne sait ce qui tourne dessus. On te demande un
état des lieux, un durcissement, et un avant/après chiffré.
:::

1. État des lieux, à consigner dans `~/lab15/etat-initial.md` : ports en écoute avec
   processus et utilisateur, services actifs, comptes pouvant se connecter (shell
   valide), comptes sans mot de passe, comptes UID 0, binaires SUID/SGID, tâches cron
   de tous les utilisateurs.
2. Lance `lynis audit system`, note l'indice de durcissement initial et archive le
   rapport.
3. Applique le durcissement :
   * mises à jour de sécurité automatiques (`unattended-upgrades` configuré pour
     installer les mises à jour de sécurité, avec journalisation) ;
   * `sysctl` de sécurité dans `/etc/sysctl.d/99-durcissement.conf` ;
   * `/tmp` en `noexec,nosuid,nodev` — décide entre `fstab` et l'unité `tmp.mount`
     de systemd et justifie ton choix ;
   * blocage des modules noyau inutiles : `usb-storage`, `firewire-core`, `cramfs`,
     `dccp`, `sctp` ;
   * `umask` par défaut à `027` pour les nouvelles sessions ;
   * politique de mots de passe : 12 caractères minimum, expiration à 365 jours,
     avertissement 14 jours avant ;
   * bannière légale affichée avant authentification.
4. Ferme la surface : pour chaque service qui écoute sur `0.0.0.0` et n'a pas de
   raison de le faire, soit tu le restreins à `127.0.0.1`, soit tu l'arrêtes et le
   désactives. Documente chaque décision en une ligne.
5. Pose des règles auditd durables dans `/etc/audit/rules.d/99-lab.rules` :
   modifications de `/etc/passwd`, `/etc/shadow`, `/etc/sudoers`, `/etc/ssh/sshd_config`,
   et toute exécution de `/usr/bin/passwd`. Recharge les règles et vérifie.
6. Relance `lynis` et consigne l'avant/après : indice, et trois suggestions que tu as
   décidé de **ne pas** appliquer, avec la justification.

::: attention
`/tmp` en `noexec` casse certains installeurs et certaines compilations. Fais le test
avant de considérer l'étape terminée : crée un script dans `/tmp`, rends-le
exécutable, lance-le. Il doit échouer — et tu dois savoir donner à un outil légitime
un `TMPDIR` de remplacement.
:::

::: check
Critère de succès : `~/lab15/etat-initial.md` et `~/lab15/etat-final.md` existent,
l'indice lynis a progressé, les sysctl sont actifs, `/tmp` refuse l'exécution, et les
règles auditd sont chargées.

```bash
bash check_M15_05.sh
```
:::

---

## 15.7 Break & Fix ★★★

::: attention
Avant chaque Break & Fix : `qm snapshot <vmid> avant-bf15`. Le snapshot `snap-clean`
reste le filet de sécurité (`qm rollback <vmid> snap-clean`), mais l'utiliser vaut
échec : l'objectif est de diagnostiquer, pas de rembobiner. Pour BF15.1 et BF15.4,
garde la **console Proxmox** ouverte : tu risques de perdre SSH.
:::

### **BF15.1** — « Le pare-feu est bon, pourtant la base est injoignable »

À lancer sur `lab-db` :

```bash
sudo bash break_M15_01.sh
```

**Symptôme utilisateur** : l'application sur `lab-web` ne parvient plus à joindre
PostgreSQL sur `lab-db` (`connection timed out` au bout de deux minutes). Sur
`lab-db`, `sudo ufw status numbered` affiche pourtant très clairement
`5432/tcp ALLOW IN 10.10.10.11`. Le service PostgreSQL est démarré et
`ss -tlnp | grep 5432` montre qu'il écoute bien sur `0.0.0.0:5432`. SSH depuis
`lab-adm` fonctionne normalement. `ping` entre les deux machines passe.

**Interdit** : `ufw reset`, `ufw disable`, redémarrer la machine, réinstaller ufw.

**Objectif** : trouver pourquoi le trafic est bloqué alors que la règle existe,
restaurer le flux, expliquer le mécanisme en une phrase, et dire quelle commande tu
aurais lancée **en premier** pour gagner vingt minutes.

::: repondre
lignes: 10
:::

### **BF15.2** — « Le site renvoie 403 sur une seule page »

À lancer sur `lab-rhel` :

```bash
sudo bash break_M15_02.sh
```

**Symptôme utilisateur** : le site servi par nginx sur `lab-rhel` fonctionne, sauf
`/rapport.html` qui renvoie systématiquement `403 Forbidden`. Le fichier existe, il
est lisible par tout le monde (`-rw-r--r--`), il est au même endroit que les autres,
et `curl` en local depuis la machine donne le même 403. Le journal d'erreur nginx dit
`Permission denied`. Le collègue qui a déposé le fichier jure qu'il n'a « fait qu'un
`mv` depuis son home ».

**Interdit** : `setenforce 0`, modifier `/etc/selinux/config`, recréer le fichier
depuis zéro, `chmod 777`.

**Objectif** : identifier le mécanisme exact, corriger ce fichier, puis rendre la
correction **robuste** : si un collègue refait la même manipulation demain, le
problème ne doit plus se poser sur ce répertoire. Explique la différence entre les
deux niveaux de correction.

::: repondre
lignes: 10
:::

### **BF15.3** — « HTTPS ne marche plus depuis ce matin »

À lancer sur `lab-web` :

```bash
sudo bash break_M15_03.sh
```

**Symptôme utilisateur** : `curl https://app.lab.local` échoue avec
`SSL certificate problem: certificate has expired`, aussi bien depuis `lab-adm` que
depuis `lab-web` elle-même. Le navigateur affiche un avertissement plein écran.
nginx est démarré, `systemctl status nginx` est vert, le port 443 écoute, et le
fichier de configuration n'a pas été modifié depuis trois mois.

**Interdit** : `curl -k`, désactiver HTTPS, revenir en HTTP.

**Objectif** : confirmer le diagnostic avec `openssl` (deux commandes suffisent :
l'une depuis le fichier, l'autre depuis le service en écoute), réémettre ce qu'il faut
sans toucher à la CA, remettre le service en état, et proposer le mécanisme qui aurait
déclenché une alerte quinze jours avant. Livre ce mécanisme sous forme de commande
utilisable en supervision.

::: repondre
lignes: 10
:::

### **BF15.4** — « Je n'arrive plus à me connecter en SSH, mais seulement depuis le bastion »

À lancer sur `lab-web` :

```bash
sudo bash break_M15_04.sh
```

**Symptôme utilisateur** : depuis `lab-adm`, `ssh 10.10.10.11` reste bloqué puis
sort en `Connection timed out`. Depuis `lab-db`, la même commande fonctionne
immédiatement. `ping 10.10.10.11` depuis `lab-adm` répond. `ufw status` sur `lab-web`
montre bien `22/tcp ALLOW IN 10.10.10.10`. Le service `ssh` est actif et n'a pas été
modifié.

**Interdit** : `systemctl stop fail2ban` comme solution finale (tu peux l'arrêter
pour confirmer un diagnostic, mais la remise en service doit se faire avec fail2ban
actif), redémarrer la VM, modifier `sshd_config`.

**Objectif** : identifier ce qui bloque, débloquer `lab-adm` immédiatement, puis
corriger la configuration pour que ça ne puisse plus se reproduire. Explique pourquoi
`ufw status` ne montrait rien d'anormal, et où se trouvait réellement le blocage dans
le noyau.

::: repondre
lignes: 10
:::

---

## 15.8 Défi du module ★★★

**D15 — Rapport de conformité et durcissement de l'infrastructure**

::: contexte
La direction a signé un contrat qui impose une « revue de sécurité trimestrielle
documentée ». Tu es seul sur le sujet. On te demande un outil qui produit le rapport
tout seul, applicable aux cinq VM du lab, Ubuntu comme Rocky, et le rapport de la
première campagne.
:::

Cahier des charges :

1. Écris `~/lab15/bin/audit-securite.sh` : `#!/usr/bin/env bash`, `set -euo pipefail`,
   exécutable sur `lab-adm`, `lab-web`, `lab-db`, `lab-rhel` et `lab-ops` sans
   modification, sans dépendance hors paquets de base. Il détecte la distribution et
   adapte ses contrôles (ufw/firewalld, AppArmor/SELinux, apt/dnf).
2. Le script produit un rapport Markdown sur **stdout**, la trace de diagnostic sur
   **stderr**, et comporte au minimum les sections suivantes :
   * identité de la machine (nom, distribution, noyau, uptime) ;
   * **pare-feu** : moteur détecté, actif ou non, politique par défaut, nombre de
     règles, ports ouverts au monde ;
   * **surface d'écoute** : tous les sockets en écoute non limités à la boucle
     locale, avec le processus ;
   * **MAC** : SELinux (mode courant et configuré) ou AppArmor (profils chargés,
     nombre en complain) ;
   * **comptes** : UID 0 multiples, mots de passe vides, comptes avec shell valide et
     sans expiration, dernières connexions ;
   * **mises à jour** : mises à jour de sécurité en attente, automatisation active
     ou non, date du dernier `apt/dnf update` ;
   * **sysctl** : valeurs constatées contre valeurs attendues pour les dix clés du
     rappel express ;
   * **SUID/SGID** : différence avec la base de référence
     `~/lab15/baseline-suid.txt` produite par le setup ;
   * **TLS** : pour chaque certificat trouvé dans `/etc/ssl/certs/*.crt` et
     `/etc/pki/tls/certs/*.crt` non issu du magasin système, le sujet et le nombre de
     jours avant expiration ;
   * **fail2ban** : jails actives, nombre d'IP bannies.
3. Chaque contrôle produit un verdict `OK`, `AVERTISSEMENT` ou `CRITIQUE`, avec une
   ligne d'explication actionnable. Le script se termine par un tableau de synthèse et
   un **score sur 100**.
4. Code retour : 0 si aucun `CRITIQUE`, 1 s'il y a des avertissements seulement,
   2 s'il y a au moins un `CRITIQUE`. Utilisable en tâche planifiée et en CI.
5. Le script ne modifie **rien**. Un audit qui répare est un audit auquel on ne peut
   plus faire confiance.
6. Livrables : le script, plus `~/lab15/rapport-T3.md` contenant le rapport des cinq
   machines concaténé et, en tête, une synthèse de dix lignes maximum listant les
   trois actions prioritaires avec leur justification.
7. Bonus (facultatif) : ajoute une option `--json` qui produit la même information en
   JSON exploitable par un collecteur, sans dépendre de `jq` pour la produire.

Temps visé : 60 à 90 minutes.

::: check
```bash
bash check_M15_06.sh
```
:::

---

## 15.9 Auto-évaluation

| Compétence | Acquis | À revoir |
|---|---|---|
| Expliquer le chemin d'un paquet dans netfilter | ☐ | ☐ |
| Lire `nft list ruleset` et le rapprocher de `ufw status` | ☐ | ☐ |
| Écrire une politique ufw correcte du premier coup, ordre compris | ☐ | ☐ |
| Manier firewalld : zones, permanent/runtime, rich rules | ☐ | ☐ |
| Configurer fail2ban, écrire un filtre, énoncer ses limites | ☐ | ☐ |
| Diagnostiquer un refus SELinux et le corriger proprement | ☐ | ☐ |
| Utiliser `semanage fcontext`, `semanage port`, les booléens | ☐ | ☐ |
| Lire et modifier un profil AppArmor, complain vs enforce | ☐ | ☐ |
| Durcir un système (sysctl, /tmp, modules, comptes, umask) | ☐ | ☐ |
| Monter une mini-PKI, vérifier et surveiller un certificat | ☐ | ☐ |
| Gérer des secrets sans les faire fuir | ☐ | ☐ |
| Reconnaître les signaux d'une intrusion et réagir | ☐ | ☐ |

Pour aller plus loin :

* Lis le **guide d'hygiène informatique** et la note technique **ANSSI-BP-028**
  (recommandations de configuration d'un système GNU/Linux). C'est gratuit, en
  français, et c'est le référentiel qu'on te citera en audit.
* Installe `openscap-scanner` et `scap-security-guide` sur `lab-rhel`, puis lance
  `oscap xccdf eval --profile cis_server_l1` : tu obtiens un rapport CIS complet et,
  surtout, les scripts de remédiation générés. Compare-les à ton propre script D15.
* Rejoue L15.1 en Ansible : les modules `ufw`, `firewalld`, `sysctl` et `seboolean`
  existent. Une politique de pare-feu qui n'est pas dans un dépôt Git n'existe pas.
* Monte `gitleaks` en hook pre-commit sur un dépôt de test et fais-lui trouver une
  clé AWS que tu auras plantée. Puis mesure combien de temps il faut pour la retirer
  de l'historique — et pourquoi tu la changeras quand même.
