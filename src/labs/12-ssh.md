# Module 12 — SSH : accès, automatisation et tunnels

## 12.0 Objectifs et compétences

::: objectif
À la fin de ce module, je sais :

* décrire les trois phases d'une connexion SSH (négociation et échange de clés,
  vérification de la clé d'hôte, authentification) et dire à quelle phase un
  incident se produit à la lecture d'un `ssh -v` ;
* générer, protéger et déployer une paire de clés `ed25519`, justifier ce choix
  face à RSA 4096, et corriger les permissions exigées sur `~/.ssh` des deux
  côtés de la connexion ;
* charger mes clés dans un agent (Linux **et** Windows), énoncer le risque exact
  du transfert d'agent et le remplacer par `ProxyJump` ;
* écrire un `~/.ssh/config` complet pour un parc avec bastion : alias,
  `ProxyJump`, `IdentitiesOnly`, `Match`, `Include`, et multiplexage de
  connexions (`ControlMaster`) dont je sais mesurer le gain ;
* diagnostiquer un `REMOTE HOST IDENTIFICATION HAS CHANGED` sans le contourner
  aveuglément, et provisionner `known_hosts` de façon sûre en CI ;
* durcir un serveur `sshd` (authentification, comptes autorisés, délais,
  algorithmes), valider la configuration avec `sshd -t` et `sshd -T` avant
  rechargement, et ne jamais me verrouiller dehors ;
* monter un tunnel `-L`, `-R` ou `-D` selon le besoin, expliquer le sens des flux
  et fermer proprement le tunnel ;
* exécuter des commandes à distance en récupérant le code de retour, savoir quand
  forcer un TTY avec `-t`, et exécuter un script local sur une machine distante ;
* restreindre une clé de service dans `authorized_keys` (`command=`, `from=`,
  `restrict`) et expliquer ce qu'apporte un certificat SSH à grande échelle ;
* lire `journalctl -u ssh` et associer chaque message serveur à l'erreur vue côté
  client.

Temps estimé : 6 h
Prérequis : modules 01 (shell), 03 (permissions), 04 (utilisateurs et sudo),
06 (archives, `rsync`), 08 (services systemd).
:::

---

## 12.1 Mise en place

Toutes les VM du lab sont concernées. `lab-adm` est le poste de travail et le
futur bastion ; `lab-web`, `lab-db`, `lab-rhel` et `lab-ops` sont les cibles.

```bash
# depuis le shell Proxmox, avant de commencer
for id in 9001 9002 9003 9004 9005; do qm snapshot $id avant-lab12; done
```

Paquets, sur **chaque** VM Ubuntu :

```bash
sudo apt update
sudo apt install -y openssh-server openssh-client ssh-audit netcat-openbsd \
  curl socat
```

::: rhel
Sous Rocky 9 : `sudo dnf install -y openssh-server openssh-clients nmap-ncat
curl socat`. Le paquet `ssh-audit` n'existe pas dans Rocky 9 ni EPEL 9 :
`python3 -m pip install --user ssh-audit`, ou lance l'audit depuis `lab-adm`
contre `lab-rhel`, ce qui est de toute façon le mode normal d'utilisation.
:::

Script de préparation, à lancer **sur chaque VM** (il détecte le nom d'hôte et
n'applique que la partie qui le concerne, il est idempotent) :

```bash
sudo bash ~/workbook/scripts/setup/setup_M12.sh
```

Il crée `~/lab12/{bin,conf,rapports}`, une vieille clé RSA 2048 à faire tourner,
un faux service de base de données sur `lab-db:5432`, une fausse application
locale sur `lab-adm:3000`, le compte de service `sauvegarde` sur `lab-web`, et
sauvegarde `/etc/ssh` dans `/root/.m12-backup/`.

::: attention
Ce module modifie la configuration du serveur SSH. **Règle d'or absolue** :
avant toute modification de `sshd_config`, garde une session SSH déjà
authentifiée ouverte dans un autre terminal, et ne la ferme pas tant que tu n'as
pas ouvert **une nouvelle** session avec la configuration modifiée. Un
`systemctl reload ssh` ne coupe pas les sessions en cours : c'est exactement ce
filet-là qui te sauve. Deuxième filet : la console de la VM dans l'interface
Proxmox, qui ne passe pas par le réseau.
:::

---

## 12.2 Rappel express

### Les trois phases d'une connexion

```text
1. TRANSPORT   négociation des algorithmes, échange de clés (KEX) ->
               clé de session symétrique. Le serveur signe l'échange avec
               sa clé d'hôte privée.
   -> échec ici : "Unable to negotiate ... no matching cipher/kex/host key"
2. IDENTITE    le client compare l'empreinte de la clé d'hôte reçue avec
   DE L'HOTE   ~/.ssh/known_hosts (TOFU : confiance à la première vue).
   -> échec ici : "Host key verification failed"
3. AUTHENTIF.  le client prouve son identité. En publickey, il SIGNE avec sa
               clé privée un blob contenant l'identifiant de session ; le
               serveur vérifie avec la clé publique d'authorized_keys.
   -> échec ici : "Permission denied (publickey)"
```

La clé privée ne quitte **jamais** le poste client : ni en publickey (on envoie
une signature), ni ailleurs. Le mot de passe, lui, traverse le tunnel chiffré et
arrive en clair sur le serveur.

### Clés

| Commande | Effet |
|---|---|
| `ssh-keygen -t ed25519 -C "mathieu@pc-win"` | paire moderne, taille fixe |
| `ssh-keygen -t rsa -b 4096 -a 100` | RSA 4096, KDF renforcé |
| `ssh-keygen -l -f cle.pub` | empreinte SHA256 |
| `ssh-keygen -p -f ~/.ssh/id_ed25519` | change la passphrase |
| `ssh-keygen -y -f ~/.ssh/id_ed25519` | régénère la publique depuis la privée |
| `ssh-copy-id -i ~/.ssh/id_ed25519.pub h` | dépose la clé, crée les bons droits |

`ed25519` : 68 octets de clé publique, signature plus rapide, sécurité
équivalente à RSA 3072, aucun paramètre à choisir (donc aucun moyen de se
tromper), et pas de dépendance à la qualité du générateur aléatoire au moment de
la signature. RSA 4096 ne sert que face à un équipement qui ne connaît pas
`ed25519` (matériel réseau ancien, OpenSSH < 6.5, certains HSM).

### Permissions exigées

| Chemin | Mode | Sanction |
|---|---|---|
| `~` (le home) | pas d'écriture pour groupe/autres | refus serveur |
| `~/.ssh` | `700` | refus serveur |
| `~/.ssh/authorized_keys` | `600` (`644` toléré) | refus serveur |
| `~/.ssh/id_ed25519` | `600` | clé ignorée côté client |

Côté serveur, c'est `StrictModes yes` qui impose la règle. Le client, lui, ne
voit qu'un `Permission denied (publickey)` : la cause n'est lisible que dans
`journalctl -u ssh` sur le serveur.

### Agent

```bash
eval "$(ssh-agent -s)"          # démarre l'agent, exporte SSH_AUTH_SOCK
ssh-add -t 3600 ~/.ssh/id_ed25519   # charge la clé pour 1 h
ssh-add -l                      # empreintes chargées ; -L : clés publiques
ssh-add -D                      # purge l'agent
ssh-add -c ~/.ssh/id_deploy     # confirmation graphique à chaque usage
```

`ForwardAgent yes` expose ta socket d'agent sur la machine distante : tout
compte root de cette machine peut alors s'authentifier **en ton nom** partout où
ta clé est déployée, pendant toute la durée de ta session. `ProxyJump` fait le
même travail sans ce risque : la connexion finale est tunnelée à travers le
rebond, mais l'authentification a lieu sur ton poste.

### `~/.ssh/config`

Premier mot-clé rencontré gagne : les blocs **du plus précis au plus général**,
`Host *` en dernier. Mots-clés utiles : `HostName`, `User`, `Port`,
`IdentityFile`, `IdentitiesOnly`, `ProxyJump`, `ForwardAgent`,
`ServerAliveInterval`, `ControlMaster`/`ControlPath`/`ControlPersist`,
`StrictHostKeyChecking`, `Include`, `Match`.

```bash
ssh -G lab-db     # configuration effective, sans se connecter : l'arbitre
```

### Multiplexage

`ControlMaster auto` + `ControlPath ~/.ssh/cm/%C` + `ControlPersist 10m` : la
première connexion crée une socket, les suivantes la réutilisent — plus de
poignée de main TCP, plus d'échange de clés, plus d'authentification. Sur une
boucle de 20 machines, on passe de ~0,4 s à ~0,02 s par commande.
`%C` est un condensat de (hôte local, hôte distant, port, utilisateur) : il
évite de dépasser la longueur maximale d'un chemin de socket UNIX.

```bash
ssh -O check lab-web     # le maître est-il vivant ?
ssh -O exit  lab-web     # ferme le maître (et toutes les sessions filles)
```

### `known_hosts`

```bash
ssh-keygen -F lab-web                 # cherche l'entrée (même hachée)
ssh-keygen -R lab-web                 # supprime l'entrée
ssh-keyscan -t ed25519 10.10.10.11    # récupère la clé publique d'hôte
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub   # empreinte, sur le serveur
```

`StrictHostKeyChecking` : `accept-new` (accepte un hôte inconnu, refuse un
changement) en CI raisonnable, `yes` en CI sérieuse avec un `known_hosts`
provisionné, `no` jamais.

### Serveur

| Fichier / commande | Rôle |
|---|---|
| `/etc/ssh/sshd_config` | configuration principale |
| `/etc/ssh/sshd_config.d/*.conf` | fragments, **inclus en tête** du fichier |
| `sshd -t` | valide la syntaxe, à faire avant tout reload |
| `sshd -T` | configuration effective, valeurs résolues |
| `sshd -T -C user=x,host=y,addr=z` | idem, en évaluant les blocs `Match` |
| `systemctl reload ssh` | relit la conf sans couper les sessions |

Comme pour le client, **la première valeur rencontrée gagne**. Sur une image
cloud Ubuntu, `/etc/ssh/sshd_config.d/50-cloud-init.conf` contient souvent
`PasswordAuthentication yes` : il écrase tout ce que tu écris plus bas dans le
fichier principal.

### Tunnels

```text
-L 15432:10.10.10.12:5432  bastion   # j'ouvre 15432 CHEZ MOI
   client:15432 -> [bastion] -> 10.10.10.12:5432
-R 8080:127.0.0.1:3000     lab-ops   # j'ouvre 8080 SUR LE SERVEUR
   lab-ops:8080 -> [tunnel] -> mon poste:3000
-D 1080                    bastion   # proxy SOCKS5 sur mon poste
   navigateur -> 127.0.0.1:1080 -> [bastion] -> n'importe où
```

`-N` : pas de commande distante. `-f` : passe en arrière-plan.
`-o ExitOnForwardFailure=yes` : indispensable, sinon un port déjà pris donne un
tunnel silencieusement inexistant. Côté serveur, `AllowTcpForwarding` autorise
`-L`/`-D`, `GatewayPorts` décide si un `-R` peut écouter ailleurs que sur la
boucle locale.

### Exécution distante

```bash
ssh lab-web 'systemctl is-active nginx'   # code de retour = celui du distant
ssh -t lab-web 'sudo journalctl -u nginx' # TTY forcé : sudo, pagers, couleurs
ssh lab-web 'bash -s' -- --dry-run < deploy.sh   # script local, à distance
ssh -n lab-web 'uptime'                   # stdin fermé : obligatoire en boucle
```

Le code 255 est réservé aux erreurs de `ssh` lui-même — il est donc ambigu si la
commande distante peut aussi sortir en 255.

---

## 12.3 Quiz — QCM

**Q12.1** — Tu crées une clé pour un compte de déploiement.
**Deux réponses correctes.**

a) `ed25519` a une taille de clé fixe : il n'y a pas de paramètre à régler, donc
   pas de mauvais choix possible
b) `ed25519` est plus sûr que RSA 4096 parce qu'il utilise une clé plus longue
c) RSA 4096 reste utile pour dialoguer avec un équipement qui ne connaît pas
   `ed25519`
d) `ed25519` n'accepte pas de passphrase sur la clé privée

**Q12.2** — Tu te connectes et tu obtiens :

```console
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: UNPROTECTED PRIVATE KEY FILE!             @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Permissions 0644 for '/home/mathieu/.ssh/id_ed25519' are too open.
```

Que fait `ssh` ensuite ?

a) il refuse de démarrer et sort en 255
b) il ignore cette clé et continue avec les autres méthodes disponibles
c) il corrige automatiquement les permissions en 600
d) il utilise la clé quand même, l'avertissement est purement informatif

**Q12.3** — Sur `lab-web`, `journalctl -u ssh` affiche :

```console
sshd[2143]: Authentication refused: bad ownership or modes for directory
            /home/mathieu/.ssh
```

Que voit l'utilisateur côté client ?

a) `Bad owner or permissions on /home/mathieu/.ssh`
b) `Permission denied (publickey)`
c) `Host key verification failed`
d) `Connection closed by remote host`

**Q12.4** — Tu obtiens `REMOTE HOST IDENTIFICATION HAS CHANGED!` sur `lab-db`.
Quelle est la **première** action correcte ?

a) `ssh-keygen -R lab-db` puis reconnexion
b) ajouter `StrictHostKeyChecking=no` pour cette machine
c) lire l'empreinte de la clé d'hôte depuis la console Proxmox de `lab-db` et la
   comparer à celle affichée par le message
d) supprimer `~/.ssh/known_hosts` entièrement, il se reconstruira

**Q12.5** — À quoi sert `ssh -G lab-db` ?

a) à se connecter en mode debug
b) à afficher la configuration effective pour cet alias, sans se connecter
c) à générer une clé d'hôte
d) à afficher la configuration du serveur distant

**Q12.6** — Ton `~/.ssh/config` contient, dans cet ordre :

```text
Host *
    User root
Host lab-web
    User mathieu
    HostName 10.10.10.11
```

Avec quel utilisateur part `ssh lab-web` ?

a) `mathieu`, le bloc le plus précis gagne
b) `root`, la première valeur rencontrée gagne
c) une erreur : `User` est défini deux fois
d) l'utilisateur local courant

**Q12.7** — Tu ajoutes `ControlMaster auto`, `ControlPath ~/.ssh/cm/%C` et
`ControlPersist 10m`. Qu'est-ce qui est vrai ?

a) chaque nouvelle session réutilise la connexion TCP et l'authentification de la
   première
b) `%C` est remplacé par le nom d'hôte en clair
c) fermer la première session ferme immédiatement toutes les autres
d) le multiplexage chiffre une deuxième fois le trafic

**Q12.8** — À propos de `ForwardAgent yes` sur le bastion `lab-adm`.
**Deux réponses correctes.**

a) ta clé privée est copiée sur `lab-adm` pendant la session
b) root sur `lab-adm` peut utiliser ta socket d'agent pour s'authentifier en ton
   nom sur toutes tes machines
c) `ProxyJump lab-adm` rend le transfert d'agent inutile pour atteindre `lab-db`
d) le transfert d'agent est sans risque si le bastion est à jour

**Q12.9** — Sur `lab-adm`, tu tapes :

```bash
ssh lab-web "echo $HOSTNAME"
```

Qu'affiche la commande ?

a) `lab-web`
b) `lab-adm`
c) une chaîne vide
d) `$HOSTNAME`

**Q12.10** — Dans un script sur `lab-adm` :

```bash
ssh lab-web 'sudo systemctl restart nginx'
```

Le message `sudo: a terminal is required to read the password` apparaît.
Quelle correction est la plus adaptée **dans un script non interactif** ?

a) ajouter `-t`
b) ajouter `-tt`
c) configurer une règle `NOPASSWD` ciblée pour cette commande dans `sudoers`
d) exécuter la commande en tant que root via `PermitRootLogin yes`

**Q12.11** — Depuis ton poste, tu veux interroger la base de `lab-db`
(10.10.10.12:5432), joignable uniquement depuis le réseau de lab via le bastion
`lab-adm` (10.10.10.10). Quelle commande ?

a) `ssh -L 15432:127.0.0.1:5432 mathieu@10.10.10.10`
b) `ssh -L 15432:10.10.10.12:5432 mathieu@10.10.10.10`
c) `ssh -R 15432:10.10.10.12:5432 mathieu@10.10.10.10`
d) `ssh -D 15432 mathieu@10.10.10.12`

**Q12.12** — Tu lances sur ton poste :

```bash
ssh -R 8080:127.0.0.1:3000 mathieu@lab-ops
```

Un collègue sur `10.10.10.20` tente `curl http://10.10.10.14:8080/` et obtient
`Connection refused`. Pourquoi ?

a) le tunnel `-R` est interdit par défaut par `AllowTcpForwarding no`
b) le port distant n'écoute que sur la boucle locale de `lab-ops` tant que
   `GatewayPorts` n'est pas activé
c) il faut utiliser `-L` et non `-R`
d) le port 8080 est réservé

**Q12.13** — Tu obtiens `Received disconnect from 10.10.10.11 port 22:2: Too many
authentication failures`. Ton agent contient 8 clés.
**Deux réponses corrigent le problème.**

a) `ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 lab-web`
b) augmenter `MaxAuthTries` à 20 sur le serveur
c) `ssh-add -D` puis recharger uniquement la clé nécessaire
d) ajouter `PubkeyAuthentication no` côté client

**Q12.14** — Deux tentatives de connexion :

```console
$ ssh lab-web
ssh: connect to host lab-web port 22: Connection refused
$ ssh lab-db
ssh: connect to host lab-db port 22: Connection timed out
```

Qu'en déduis-tu ?

a) les deux machines sont éteintes
b) `lab-web` répond mais rien n'écoute sur 22 ; `lab-db` ne répond pas du tout
c) `lab-web` a un pare-feu en DROP ; `lab-db` a un `sshd` arrêté
d) les deux messages sont équivalents, seul le délai change

**Q12.15** — Tu as mis `PasswordAuthentication no` dans `/etc/ssh/sshd_config`,
tu as rechargé le service, et le serveur demande toujours un mot de passe.
Quelle commande te donne la réponse le plus vite ?

a) `grep -r PasswordAuthentication /etc/ssh/`
b) `sshd -T | grep -i passwordauthentication`
c) `systemctl status ssh`
d) `ssh -v localhost`

**Q12.16** — Avant `systemctl reload ssh`, laquelle de ces commandes valide la
configuration ?

a) `sshd -T`
b) `sshd -t`
c) `systemctl reload ssh --dry-run`
d) `ssh -G localhost`

**Q12.17** — Sur `lab-web` (Ubuntu 24.04), tu changes `Port 2222` dans
`sshd_config`, `sshd -t` ne dit rien, tu recharges, et `sshd` écoute toujours
sur 22. Cause la plus probable ?

a) il faut `restart` et non `reload`
b) `sshd` est démarré par activation de socket (`ssh.socket`) : c'est l'unité
   socket qui décide du port d'écoute
c) `Port` est ignoré quand `ListenAddress` est absent
d) SELinux bloque le port 2222

**Q12.18** — Dans `/home/sauvegarde/.ssh/authorized_keys` :

```text
restrict,from="10.10.10.14",command="/usr/local/bin/recevoir-sauvegarde"
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... ci@lab-ops
```

Le client lance `ssh sauvegarde@lab-web 'rm -rf /srv/sauvegarde'`. Que se
passe-t-il ?

a) la commande est exécutée, `command=` n'est qu'un défaut
b) `recevoir-sauvegarde` est exécuté à la place, et reçoit la commande demandée
   dans `$SSH_ORIGINAL_COMMAND`
c) la connexion est refusée avec `Permission denied (publickey)`
d) `rm` est exécuté puis `recevoir-sauvegarde`

---

## 12.4 Quiz — questions ouvertes

**QO12.1** — Décris, dans l'ordre, ce qui se passe entre le moment où tu tapes
`ssh lab-web` et le moment où le prompt distant s'affiche. Nomme les trois
phases, dis à quel moment la clé de session est établie, à quel moment la clé
d'hôte intervient, et à quel moment ta clé privée est sollicitée. Précise ce qui
circule réellement sur le réseau lors de l'authentification par clé.

::: repondre
lignes: 12
:::

**QO12.2** — *On te demande en entretien* : « L'authentification par clé, c'est
plus sûr qu'un mot de passe. Pourquoi, concrètement ? Est-ce que ma clé privée
part sur le serveur ? Et si quelqu'un vole mon `authorized_keys` ? »

::: repondre
lignes: 8
:::

**QO12.3** — *On te demande en entretien* : « Sur nos bastions, on active
`ForwardAgent` pour que les admins puissent rebondir. Tu en penses quoi ? »
Explique le risque de façon opérationnelle (qui peut faire quoi, pendant combien
de temps), propose l'alternative et décris ce qu'elle change dans le chemin de la
connexion.

::: repondre
lignes: 10
:::

**QO12.4** — Cite **trois** causes parfaitement légitimes d'un changement de clé
d'hôte, et décris la procédure que tu appliques pour trancher entre « incident
normal » et « attaque » — en précisant par quel canal tu vérifies.

::: repondre
lignes: 10
:::

**QO12.5** — Un développeur n'arrive plus à se connecter à `lab-ops` :
`Permission denied (publickey)`. Décris ta démarche de diagnostic complète, dans
l'ordre, en séparant ce que tu regardes côté client et côté serveur, et en
donnant pour chaque étape la commande et ce que tu cherches dans sa sortie.

::: repondre
lignes: 12
:::

**QO12.6** — Explique le mécanisme du multiplexage de connexions
(`ControlMaster`). Quels gains mesurables apporte-t-il, et quels sont ses trois
inconvénients ou pièges en exploitation réelle ?

::: repondre
lignes: 10
:::

**QO12.7** — Compare `-L`, `-R` et `-D`. Pour chacun : le sens du flux (qui
écoute où, qui initie la connexion TCP finale), un cas d'usage réel, et la
directive serveur qui peut l'empêcher.

::: repondre
lignes: 10
:::

**QO12.8** — Tu as écrit une boucle `for h in lab-web lab-db lab-ops; do ssh
"$h" '...'; done` pour appliquer un changement sur le parc. Cite **cinq**
limites qui font qu'on bascule vers un outil de gestion de configuration dès que
le parc grandit, en expliquant pour chacune ce qui casse concrètement.

::: repondre
lignes: 10
:::

**QO12.9** — Les certificats SSH : quel problème résolvent-ils que `known_hosts`
et `authorized_keys` ne savent pas résoudre ? Distingue certificat d'hôte et
certificat d'utilisateur, et dis ce que chacun remplace dans les fichiers
habituels.

::: repondre
lignes: 10
:::

---

## 12.5 Exercices guidés ★

**E12.1** — Sur `lab-adm`, crée une paire de clés moderne pour l'utilisateur
`mathieu`, identifiable par un commentaire explicite (utilisateur + poste
d'origine), protégée par une passphrase, et avec un nombre de tours de dérivation
supérieur au défaut. Vérifie ensuite que la clé privée est bien chiffrée.

**E12.2** — Affiche l'empreinte SHA256 de ta clé publique, puis la même empreinte
sous forme de dessin ASCII. Affiche enfin l'empreinte de la clé d'hôte `ed25519`
de `lab-adm` lui-même.

**E12.3** — Déploie ta clé publique sur `lab-web` **sans utiliser `ssh-copy-id`**,
en une seule commande, en garantissant que `~/.ssh` et `authorized_keys` ont les
bons droits même s'ils n'existaient pas.

**E12.4** — Écris une commande qui liste, sous `~/.ssh`, tous les fichiers dont
les permissions sont trop larges (accessibles au groupe ou aux autres), puis une
seconde qui les corrige en une passe.

**E12.5** — Démarre un agent, charge ta clé pour une durée de vie d'une heure,
affiche les empreintes chargées, puis les clés publiques complètes. Vérifie
ensuite ce que devient la clé au bout de la durée impartie.

**E12.6** — Sur ton PC Windows, active l'agent OpenSSH natif pour qu'il démarre
automatiquement, charge ta clé, et vérifie depuis PowerShell que l'agent la
propose. Indique aussi où se trouve le fichier de configuration client.

**E12.7** — Sans te connecter, affiche quel utilisateur, quel port, quelle clé et
quel rebond seront effectivement utilisés par `ssh lab-db`. Puis montre la ligne
qui prouve que `IdentitiesOnly` est actif.

**E12.8** — Mesure le gain du multiplexage : chronomètre cinq connexions
successives à `lab-web` exécutant `true`, d'abord sans multiplexage, puis avec.
Donne le rapport entre les deux.

**E12.9** — Récupère la clé d'hôte `ed25519` de `lab-rhel` avec `ssh-keyscan`,
calcule son empreinte, et compare-la à celle affichée sur `lab-rhel` lui-même.
Supprime ensuite proprement l'entrée correspondante de ton `known_hosts`, sachant
que le fichier est haché.

**E12.10** — Sur `lab-web`, affiche la valeur **effective** de
`PermitRootLogin`, `PasswordAuthentication`, `MaxAuthTries`, `LoginGraceTime` et
`AllowTcpForwarding`. Puis affiche ce que serait `PasswordAuthentication` pour
une connexion de l'utilisateur `sauvegarde` venant de `10.10.10.14`.

**E12.11** — Écris une boucle qui affiche, pour `lab-web`, `lab-db`, `lab-rhel`
et `lab-ops`, le nom d'hôte et la charge moyenne, qui ne bloque pas plus de 5
secondes par machine, et qui sort en 1 si au moins une machine a échoué.
Attention à ce que la boucle ne consomme pas son propre flux d'entrée.

**E12.12** — Tu as un script local `~/lab12/bin/etat.sh` qui prend un argument
`--court` ou `--long`. Exécute-le sur `lab-ops` **sans le copier** sur la machine
distante, en lui passant `--court`.

**E12.13** — Ouvre un tunnel en arrière-plan qui rend le service de `lab-db`
(port 5432) accessible sur le port 15432 de `lab-adm`, en passant par le bastion.
Le tunnel doit échouer bruyamment si le port local est déjà pris. Vérifie qu'il
fonctionne, puis ferme-le proprement.

**E12.14** — Ouvre un proxy SOCKS5 sur le port 1080 via `lab-adm`, puis prouve
avec `curl` que la requête sort bien depuis le réseau de lab (et non depuis ton
poste), en veillant à ce que la résolution DNS se fasse aussi à distance.

**E12.15** — Sur `lab-web`, restreins la clé du compte `sauvegarde` pour qu'elle
ne puisse être utilisée que depuis `10.10.10.10`, sans allocation de terminal ni
redirection de ports, et qu'elle exécute toujours `/usr/local/bin/lab12-rsync`
quoi que demande le client. Montre ensuite comment ce script récupère la commande
réellement demandée.

**E12.16** — Voici un extrait de `ssh -v` :

```console
debug1: Server host key: ssh-ed25519 SHA256:2Zr4h... 
debug1: Host '10.10.10.13' is known and matches the ED25519 host key.
debug1: Will attempt key: /home/mathieu/.ssh/id_ed25519
        ED25519 SHA256:8kQ3vN1... agent
debug1: Authentications that can continue: publickey
debug1: Offering public key: /home/mathieu/.ssh/id_ed25519
        ED25519 SHA256:8kQ3vN1... agent
debug1: Authentications that can continue: publickey
debug1: No more authentication methods to try.
mathieu@10.10.10.13: Permission denied (publickey).
```

Dis à quelle phase de la connexion on est, ce qui est déjà validé, et cite les
trois hypothèses à vérifier dans l'ordre, côté serveur.

---

## 12.6 Labs ★★

### **L12.1** — Poser l'accès par clé sur tout le parc

::: contexte
Le lab a été monté à la va-vite : on se connecte au mot de passe sur les cinq
machines, le même mot de passe partout, et une vieille clé RSA 2048 sans
passphrase traîne dans `~/.ssh` depuis l'installation. On te demande de passer
l'ensemble du parc à l'authentification par clé, de faire tourner la vieille clé,
et de couper l'authentification par mot de passe — sans perdre l'accès.
:::

Travaille depuis `lab-adm`.

1. Inventorie les clés présentes dans `~/.ssh` : pour chacune, type, taille,
   empreinte, commentaire, et si elle est protégée par une passphrase. Écris le
   résultat dans `~/lab12/rapports/cles-avant.md`.
2. Crée une nouvelle paire `ed25519` nommée `~/.ssh/id_ed25519`, avec passphrase
   et un commentaire de la forme `mathieu@lab-adm-2026-09`.
3. Déploie la clé publique sur les quatre autres VM pour l'utilisateur `mathieu`.
   Vérifie ensuite que la connexion par clé fonctionne sur les quatre sans jamais
   saisir de mot de passe de compte.
4. Charge la clé dans un agent avec une durée de vie de 8 heures, et vérifie que
   `ssh lab-web` ne demande plus la passphrase.
5. Supprime la vieille clé RSA des `authorized_keys` des quatre machines, puis du
   poste. Prouve qu'elle n'ouvre plus rien.
6. Sur `lab-web` uniquement, désactive l'authentification par mot de passe.
   Applique la règle d'or : session de secours ouverte, `sshd -t`, `reload`,
   nouvelle session testée **avant** de fermer l'ancienne. Vérifie avec
   `sshd -T`, pas avec `grep`.
7. Note dans `~/lab12/rapports/cles-apres.md` ce qui a changé et ce qui reste à
   faire sur les trois autres machines.

::: attention
Étape 6 : si tu fermes ta session de secours avant d'avoir testé, et que la clé
n'est pas correctement déployée, la seule porte d'entrée restante est la console
Proxmox. C'est précisément l'accident que ce module t'apprend à ne pas avoir.
:::

::: check
Critère de succès : `ssh lab-web true` fonctionne sans mot de passe ni
passphrase, `sshd -T` sur `lab-web` renvoie `passwordauthentication no`, et la
clé RSA n'est présente dans aucun `authorized_keys`.

```bash
bash check_M12_01.sh
```
:::

---

### **L12.2** — Le fichier de configuration client de référence

::: contexte
Chaque membre de l'équipe tape des adresses IP à la main, avec des options
différentes, et personne ne se souvient de la commande pour rebondir vers
`lab-db`. On te demande un `~/.ssh/config` de référence, documenté, qui sera
distribué à toute l'équipe et adapté sur le PC Windows de chacun.
:::

1. Écris `~/.ssh/config` sur `lab-adm` avec :
   * un alias `bastion` (et `lab-adm`) vers `10.10.10.10`, utilisateur `mathieu`,
     clé explicite, et `IdentitiesOnly` actif ;
   * les alias `lab-web`, `lab-db`, `lab-rhel`, `lab-ops` vers leurs IP
     respectives, tous atteints **via le bastion** ;
   * un bloc générique `lab-*` qui factorise l'utilisateur, la clé et
     l'interdiction du transfert d'agent ;
   * un bloc `Host *` final qui active les sondes de session
     (`ServerAliveInterval`), le multiplexage et l'ajout automatique des clés à
     l'agent.
2. Crée le répertoire des sockets de contrôle avec les bons droits.
3. Prouve avec `ssh -G` que `ssh lab-db` utilisera bien l'utilisateur `mathieu`,
   l'IP `10.10.10.12`, la bonne clé et le rebond par `10.10.10.10`.
4. Déplace les blocs `lab-*` et `Host *` en **tête** de fichier, relance
   `ssh -G lab-db`, constate la différence, explique-la en une phrase dans
   `~/lab12/rapports/config-ordre.md`, puis remets l'ordre correct.
5. Sors les définitions de machines dans `~/.ssh/config.d/lab.conf` et charge-les
   par un `Include`. Vérifie que `ssh -G` donne toujours le même résultat.
6. Mesure le gain du multiplexage : dix exécutions de `ssh lab-web true` avec et
   sans, et note le rapport dans le rapport.
7. Adapte le fichier pour le PC Windows (chemins, emplacement) et note les deux
   différences notables dans le rapport.

::: check
Critère de succès : `ssh lab-db` fonctionne en une frappe depuis `lab-adm`,
`ssh -G lab-db` montre le bon utilisateur, la bonne IP, `proxyjump 10.10.10.10`
et `identitiesonly yes`, et une socket de contrôle existe après une connexion.

```bash
bash check_M12_02.sh
```
:::

---

### **L12.3** — Durcir le serveur SSH de `lab-web`

::: contexte
Audit de sécurité dans trois semaines. Le rapport préliminaire reproche à
`lab-web` : root autorisé, mot de passe accepté, aucune restriction de comptes,
un délai de grâce d'authentification de deux minutes, des algorithmes obsolètes
acceptés, et un journal trop pauvre pour savoir quelle clé a servi. On te demande
de corriger, proprement, sans te verrouiller dehors.
:::

1. Ouvre **deux** sessions sur `lab-web`. La première ne servira à rien d'autre
   qu'à rester ouverte.
2. Photographie l'existant : `sshd -T > ~/lab12/rapports/sshd-avant.txt` et un
   audit distant depuis `lab-adm` avec `ssh-audit 10.10.10.11`, sauvegardé dans
   `~/lab12/rapports/ssh-audit-avant.txt`.
3. Crée `/etc/ssh/sshd_config.d/60-durcissement.conf` (ne modifie pas le fichier
   principal) qui impose :
   * pas de connexion root, pas de mot de passe, pas d'authentification
     interactive clavier, pas de mot de passe vide ;
   * accès réservé aux membres du groupe `ssh-users` ;
   * trois tentatives d'authentification maximum, 20 secondes de délai de grâce ;
   * déconnexion automatique après 10 minutes d'inactivité ;
   * pas de transfert X11, pas de transfert d'agent ;
   * journalisation verbeuse (l'empreinte de la clé utilisée doit apparaître).
4. Crée le groupe `ssh-users` et mets-y `mathieu`. Réfléchis à l'ordre des
   opérations : que se passe-t-il si tu recharges `sshd` avant de créer le
   groupe ?
5. Vérifie qu'un fragment plus prioritaire ne t'écrase pas : liste les fichiers
   de `/etc/ssh/sshd_config.d/` et explique qui gagne.
6. Valide avec `sshd -t`, recharge, ouvre une **troisième** session pour tester,
   et seulement ensuite ferme les deux premières.
7. Restreins les algorithmes : ne conserve que les échanges de clés, chiffrements
   et MAC modernes. Relance `ssh-audit` et compare avec l'état initial.
8. Prouve dans le journal qu'on voit désormais l'empreinte de la clé qui a servi
   à ta dernière connexion.

::: astuce
`sshd -T -C user=mathieu,host=lab-web,addr=10.10.10.10` évalue aussi les blocs
`Match`. C'est le seul moyen fiable de savoir ce qui s'appliquera réellement à un
utilisateur donné.
:::

::: check
Critère de succès : `sshd -T` sur `lab-web` renvoie `permitrootlogin no`,
`passwordauthentication no`, `maxauthtries 3`, `logingracetime 20`,
`allowgroups ssh-users`, `loglevel VERBOSE`, et `ssh-audit` ne signale plus
d'algorithme faible.

```bash
sudo bash check_M12_03.sh     # à lancer sur lab-web
```
:::

---

### **L12.4** — Trois tunnels pour trois demandes

::: contexte
Trois tickets dans la journée. (1) Une développeuse veut brancher son client SQL
sur la base de `lab-db`, qui n'est joignable que depuis le réseau de lab.
(2) Un prestataire doit voir la maquette qui tourne sur ton poste, port 3000,
depuis `lab-ops`. (3) Tu dois consulter une interface d'administration interne
qui ne répond qu'aux requêtes venant du réseau de lab.
:::

1. **Ticket 1** : depuis `lab-adm`, ouvre un tunnel local qui expose
   `10.10.10.12:5432` sur `127.0.0.1:15432` en passant par le bastion. Le tunnel
   tourne en arrière-plan, sans shell distant, et échoue explicitement si le port
   local est déjà occupé. Prouve qu'il fonctionne.
2. Explique pourquoi `-L 15432:127.0.0.1:5432` donnerait un résultat différent, et
   à quelle machine se rapporte `127.0.0.1` dans cette écriture.
3. **Ticket 2** : depuis `lab-adm`, expose le service local du port 3000 sur le
   port 8080 de `lab-ops`. Vérifie depuis `lab-ops` que ça répond.
4. Depuis `lab-web`, tente `curl http://10.10.10.14:8080/`. Ça échoue. Explique
   pourquoi, puis fais le nécessaire côté serveur **et** côté client pour que ça
   marche, et dis pourquoi cette configuration ne doit pas rester en place.
5. **Ticket 3** : ouvre un proxy SOCKS5 sur `127.0.0.1:1080` via le bastion.
   Utilise-le avec `curl` pour joindre `http://10.10.10.11/` et prouve que la
   résolution de nom se fait elle aussi côté distant.
6. Ferme les trois tunnels proprement, sans `kill -9`, et vérifie qu'aucun port
   n'est resté ouvert.
7. Rédige `~/lab12/rapports/tunnels.md` : pour chacun des trois tickets, la
   commande, un schéma du flux en texte, la directive serveur qui pourrait
   l'interdire, et le risque de sécurité associé.

::: check
Critère de succès : les trois tunnels ont fonctionné, `~/lab12/rapports/tunnels.md`
décrit les trois flux, et après fermeture aucun des ports 15432, 8080, 1080 n'est
en écoute.

```bash
bash check_M12_04.sh
```
:::

---

### **L12.5** — Une clé de service qui ne peut faire qu'une seule chose

::: contexte
La CI de `lab-ops` doit déposer chaque nuit une archive de sauvegarde sur
`lab-web`, dans `/srv/sauvegarde`. Le premier jet de l'équipe : un compte
`sauvegarde` avec une clé sans passphrase et un shell complet. L'audit refuse.
On te demande une clé qui ne permet **que** le dépôt d'archive, depuis **une
seule** adresse, et rien d'autre.
:::

1. Sur `lab-ops`, génère une paire dédiée `~/.ssh/id_ci_sauvegarde`, sans
   passphrase (c'est une clé de service : justifie ce choix en une ligne dans le
   rapport, et dis ce qui le compense).
2. Sur `lab-web`, écris `/usr/local/bin/lab12-recevoir` : un script qui lit la
   commande réellement demandée par le client, n'accepte que deux formes
   (`depot <nom-archive>` et `liste`), rejette tout le reste avec un code de
   retour non nul et une trace dans `/var/log/lab12-recevoir.log`.
3. Installe la clé publique dans `/home/sauvegarde/.ssh/authorized_keys` avec les
   restrictions : origine limitée à `10.10.10.14`, aucune allocation de terminal,
   aucune redirection de port, aucun transfert d'agent, et commande forcée.
4. Depuis `lab-ops`, prouve que :
   * `ssh -i ~/.ssh/id_ci_sauvegarde sauvegarde@10.10.10.11 liste` fonctionne ;
   * `... 'rm -rf /srv/sauvegarde'` est refusé et journalisé ;
   * `... -L 9999:127.0.0.1:22 ...` ne monte aucun tunnel ;
   * une tentative depuis `lab-adm` avec la même clé est refusée.
5. Fais réellement une sauvegarde : envoie une archive depuis `lab-ops` vers
   `/srv/sauvegarde` en passant par ta commande forcée.
6. Rédige `~/lab12/rapports/cle-service.md` : le contenu exact de la ligne
   `authorized_keys` commentée mot à mot, ce que chaque restriction empêche, la
   procédure de rotation de cette clé, et ce qu'un certificat SSH à durée de vie
   courte apporterait de plus.

::: astuce
`restrict` (OpenSSH ≥ 7.2) coupe tout d'un coup : terminal, redirections, agent,
X11, `~/.ssh/rc`. On rouvre ensuite ce dont on a besoin (`pty`,
`port-forwarding`). C'est plus sûr que d'énumérer les `no-*` un par un : une
option ajoutée dans une future version sera interdite par défaut.
:::

::: check
Critère de succès : la clé de CI ne permet que `liste` et `depot`, refuse toute
autre commande avec un code non nul, ne monte pas de tunnel, et n'est acceptée
que depuis `10.10.10.14`.

```bash
sudo bash check_M12_05.sh     # à lancer sur lab-web
```
:::

---

## 12.7 Break & Fix ★★★

::: attention
Avant chaque Break & Fix : `qm snapshot <vmid> avant-bf12`. Le snapshot de
secours reste `snap-clean`, mais l'utiliser vaut échec : l'objectif est de
réparer. Et pour ce module en particulier : **garde une session ouverte** ou
prépare la console Proxmox avant de lancer le script. Une partie des pannes
coupe l'accès SSH.
:::

### **BF12.1** — « Ma clé ne marche plus sur `lab-web`, et je n'ai pas de mot de passe »

```bash
sudo bash break_M12_01.sh     # à lancer sur lab-web
```

**Symptôme utilisateur** : depuis `lab-adm`, `ssh lab-web` répond
`mathieu@10.10.10.11: Permission denied (publickey).` La clé n'a pas changé, elle
fonctionne toujours sur `lab-db` et `lab-ops`. L'authentification par mot de
passe est désactivée sur `lab-web` : on ne peut plus entrer par SSH du tout.

**Interdit** : réactiver l'authentification par mot de passe, redéployer la clé
avec `ssh-copy-id`, rollback de snapshot.

**Objectif** : retrouver l'accès (la console Proxmox est autorisée, c'est son
métier), identifier la cause exacte avec une preuve tirée du journal du serveur,
corriger, et énoncer la règle de permissions en une phrase vérifiable par un
script.

::: repondre
lignes: 10
:::

### **BF12.2** — « Depuis la maintenance de cette nuit, seul root peut entrer »

```bash
sudo bash break_M12_02.sh     # à lancer sur lab-web
```

**Symptôme utilisateur** : `ssh mathieu@lab-web` répond
`Permission denied (publickey)` immédiatement, pour tous les utilisateurs du
service. La clé est bonne, les permissions sont bonnes, `sshd` est `active
(running)`, et le fichier `/etc/ssh/sshd_config` a été relu ligne par ligne :
il ne contient rien d'anormal.

**Interdit** : modifier `/etc/ssh/sshd_config`, réinstaller `openssh-server`.

**Objectif** : trouver d'où vient réellement la directive fautive, expliquer la
règle de précédence qui l'a rendue prioritaire, rétablir l'accès pour le groupe
d'exploitation sans rouvrir la machine à tout le monde, et donner la commande qui
aurait permis de voir le problème en 5 secondes.

::: repondre
lignes: 10
:::

### **BF12.3** — « SSH crie à l'attaque sur `lab-web` »

```bash
sudo bash break_M12_03.sh     # à lancer sur lab-web
```

**Symptôme utilisateur** : depuis `lab-adm`, toute connexion vers `lab-web`
affiche un pavé `@@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@@` et
refuse de continuer. `lab-db` et `lab-ops` répondent normalement. Personne dans
l'équipe ne reconnaît avoir réinstallé la machine.

**Interdit** : lancer `ssh-keygen -R` ou éditer `known_hosts` **avant** d'avoir
établi l'origine du changement, et bien sûr `StrictHostKeyChecking=no`.

**Objectif** : établir par un canal indépendant de SSH quelle est la vraie clé
d'hôte de `lab-web` aujourd'hui, déterminer si le changement est légitime,
rétablir l'accès de la bonne façon, et proposer une mesure qui supprime
définitivement cette classe d'incident sur un parc.

::: repondre
lignes: 12
:::

### **BF12.4** — « Ça marchait ce matin, maintenant je suis éjecté avant d'avoir tapé quoi que ce soit »

```bash
sudo bash break_M12_04.sh     # à lancer sur lab-adm
```

**Symptôme utilisateur** : depuis `lab-adm`, `ssh lab-web` affiche après quelques
secondes `Received disconnect from 10.10.10.11 port 22:2: Too many
authentication failures`. La même commande avec `-i ~/.ssh/id_ed25519` échoue
pareillement. `ssh lab-db` fonctionne encore, mais plus lentement qu'avant.

**Interdit** : augmenter `MaxAuthTries` sur les serveurs, supprimer le compte et
le recréer.

**Objectif** : expliquer précisément ce que compte le serveur, montrer la sortie
qui prouve le nombre de tentatives émises, corriger côté client de deux façons
(une immédiate en ligne de commande, une durable dans la configuration), et dire
pourquoi `-i` seul n'a pas suffi.

::: repondre
lignes: 10
:::

---

## 12.8 Défi du module ★★★

**D12 — Faire de `lab-adm` un vrai bastion**

::: contexte
La direction impose : plus aucun accès SSH direct aux serveurs depuis les postes
de travail. Tout passe par `lab-adm`. On te confie la mise en œuvre complète,
avec un livrable exploitable par l'équipe : configuration, outillage, procédure.
:::

Cahier des charges :

1. **Configuration client de référence** : `~/lab12/conf/ssh_config.reference`,
   utilisable tel quel sur un poste Linux et adaptable en trois lignes sur le PC
   Windows. Elle doit couvrir les cinq machines, le rebond, le multiplexage, les
   sondes de session, `IdentitiesOnly`, et un bloc `Match` qui désactive le
   multiplexage pour les connexions destinées à une commande `rsync`
   (indice : `Match exec`). Chaque bloc porte un commentaire d'une ligne.
2. **Durcissement du bastion** : `~/lab12/conf/60-bastion.conf`, destiné à
   `/etc/ssh/sshd_config.d/` de `lab-adm`. Il impose l'accès au seul groupe
   `ssh-users`, interdit root et le mot de passe, limite les tentatives et le
   délai de grâce, active la journalisation verbeuse, et autorise explicitement
   la redirection TCP (un bastion en a besoin) tout en interdisant le transfert
   d'agent. Applique-le réellement, en respectant la règle d'or.
3. **Provisionnement des empreintes** : `~/lab12/bin/known-hosts-parc.sh` qui
   construit un `known_hosts` de référence pour les quatre serveurs à partir de
   `ssh-keyscan`, **et** vérifie chaque empreinte obtenue contre une liste de
   référence `~/lab12/conf/empreintes.txt` que tu auras constituée en lisant les
   clés sur chaque machine. Le script refuse d'écrire si une empreinte diverge et
   sort en 2 dans ce cas.
4. **Outil de parc** : `~/lab12/bin/parc.sh`, en bash, `set -euo pipefail`, qui
   prend une commande en argument et l'exécute sur les quatre serveurs. Exigences :
   * n'utilise que les alias du fichier de configuration, aucune IP en dur ;
   * délai de connexion plafonné, aucune interaction possible
     (`BatchMode`) ;
   * sortie en tableau `hôte | code | première ligne de sortie` ;
   * code de retour global : 0 si tout va bien, 1 si au moins une machine a
     échoué, 2 si une machine est injoignable ;
   * une option `-s FICHIER` qui exécute un **script local** sur chaque machine
     sans le copier ;
   * une option `-p N` qui parallélise sur N machines à la fois.
5. **Rapport** : `~/lab12/rapports/bastion.md` (30 lignes minimum) contenant le
   schéma du chemin d'accès, la procédure d'ajout d'un nouvel administrateur (de
   la génération de clé à la vérification), la procédure de révocation d'un
   départ, la conduite à tenir en cas de `REMOTE HOST IDENTIFICATION HAS
   CHANGED`, et un paragraphe expliquant à quel moment il faudra passer aux
   certificats SSH et ce que ça changera.

Temps visé : 60 à 90 minutes.

::: check
```bash
bash check_M12_06.sh
```
:::

---

## 12.9 Auto-évaluation

| Compétence | Acquis | À revoir |
|---|---|---|
| Nommer les 3 phases d'une connexion et situer une panne | ☐ | ☐ |
| Générer et déployer une clé `ed25519`, justifier le choix | ☐ | ☐ |
| Corriger les permissions `~/.ssh` des deux côtés | ☐ | ☐ |
| Utiliser un agent, sous Linux et sous Windows | ☐ | ☐ |
| Expliquer le risque de `ForwardAgent` et le remplacer | ☐ | ☐ |
| Écrire un `~/.ssh/config` avec bastion et multiplexage | ☐ | ☐ |
| Traiter un changement de clé d'hôte sans le contourner | ☐ | ☐ |
| Durcir `sshd` et valider avant rechargement | ☐ | ☐ |
| Monter et fermer un tunnel `-L`, `-R` ou `-D` | ☐ | ☐ |
| Exécuter à distance en récupérant le code de retour | ☐ | ☐ |
| Restreindre une clé de service dans `authorized_keys` | ☐ | ☐ |
| Lire un `ssh -v` et le journal `sshd` en parallèle | ☐ | ☐ |

Pour aller plus loin :

* Monte une autorité de certification SSH de lab : une clé de CA, un certificat
  d'hôte pour chaque VM, `@cert-authority` dans un `known_hosts` unique, et des
  certificats utilisateur valables 8 heures. Tu verras `known_hosts` cesser
  d'être un problème.
* Essaie une clé matérielle : `ssh-keygen -t ed25519-sk` avec un jeton FIDO2. La
  clé privée ne peut plus être copiée, et chaque authentification demande une
  présence physique.
* Compare `ssh -Q kex`, `ssh -Q cipher` et `ssh -Q key` avec la sortie de
  `ssh-audit` sur une machine non durcie : tu verras exactement ce que tu
  acceptes sans le savoir.
