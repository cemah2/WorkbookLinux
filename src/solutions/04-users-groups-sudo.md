# Module 04 — Corrigé

## 4.3 Quiz — QCM

**Q4.1** — *`facturasvc:x:998:998::/var/lib/facturasvc:/usr/sbin/nologin` : que
signifie le `x` ?*

**Réponse : b) le hachage se trouve dans `/etc/shadow`.**

::: pourquoi
Historiquement, le hachage du mot de passe était stocké dans le deuxième champ de
`/etc/passwd`. Problème : ce fichier doit être **lisible par tous** (n'importe quel
programme doit pouvoir traduire un UID en nom pour afficher `ls -l`), donc tout le
monde pouvait aspirer les hachages et les casser hors ligne. La séparation
« shadow » a déplacé les hachages dans `/etc/shadow`, en mode `640 root:shadow`, et
laissé dans `/etc/passwd` un marqueur `x` qui signifie « va voir ailleurs ».

```console
$ ls -l /etc/passwd /etc/shadow
-rw-r--r-- 1 root root   1842 Sep 18 09:12 /etc/passwd
-rw-r----- 1 root shadow 1104 Sep 18 09:12 /etc/shadow
```

Un compte dont ce champ vaut autre chose que `x` (par exemple un hachage
directement dans `passwd`) est une anomalie : `pwconv` remet les choses en ordre.
:::

::: piege
Le `x` de `/etc/passwd` n'a **aucun rapport** avec l'état de verrouillage. Un
compte peut avoir `x` dans `passwd` et `!` dans `shadow` : il est verrouillé.
Pour connaître l'état réel, `passwd -S <login>`, jamais `/etc/passwd`.
:::

---

**Q4.2** — *`sophie:!$y$j9T$Kp2...:20714:0:90:14:7:20989:` — deux réponses.*

**Réponses : a) le mot de passe est verrouillé — c) l'algorithme est yescrypt.**

::: pourquoi
Deux informations se lisent dans le deuxième champ. Le `!` en tête est le
marqueur de verrouillage posé par `passwd -l` ou `usermod -L` : il préfixe le
hachage existant, qui reste intact dessous. Aucun mot de passe saisi ne pourra
produire ce hachage-là, puisque le `!` rend la chaîne non conforme au format
`crypt` — l'authentification échoue systématiquement. Déverrouiller
(`passwd -u`) consiste simplement à retirer ce caractère.

Le préfixe `$y$` identifie l'algorithme : **yescrypt**, le défaut d'Ubuntu 24.04
(`pam_unix.so obscure yescrypt` dans `/etc/pam.d/common-password`). `$6$` serait
SHA-512, `$5$` SHA-256, `$1$` MD5. Pour les autres champs :
`20714` = jour du dernier changement, `0` = âge minimum, `90` = âge **maximum du
mot de passe**, `14` = jours d'avertissement, `7` = jours d'inactivité tolérée
après expiration, `20989` = date d'expiration du **compte**.
:::

::: piege
b) confond l'âge maximum du mot de passe (champ 5) avec l'expiration du compte
(champ 8) : ce sont deux mécanismes distincts, le premier oblige à changer, le
second interdit toute connexion. d) confond avertissement (champ 6) et expiration.
:::

---

**Q4.3** — *`usermod -G docker karim` alors qu'il était dans `karim`, `sudo`, `deploy`.*

**Réponse : b) `karim`, `docker`.**

::: pourquoi
`-G` (`--groups`) **remplace** la totalité de la liste des groupes secondaires par
celle qui est fournie. Ce n'est pas un ajout : c'est une affectation. Les groupes
`sudo` et `deploy` disparaissent de son identité. Le groupe `karim` subsiste
uniquement parce que c'est son groupe **primaire**, stocké dans le 4ᵉ champ de
`/etc/passwd` et que `-G` ne touche pas (c'est `-g` qui le modifie).

```console
$ id -nG karim
karim sudo deploy
$ sudo usermod -G docker karim
$ id -nG karim
karim docker
```

La forme correcte est `usermod -aG docker karim`, où `-a` (`--append`) transforme
l'affectation en ajout. `-a` n'a de sens qu'avec `-G`.
:::

::: piege
C'est **la** faute d'exploitation du module, et elle se paie cher : si tu te
l'appliques à toi-même, tu sors du groupe `sudo` et tu perds la capacité de te
corriger. Alternative sans danger : `gpasswd -a karim docker`, qui n'agit que sur
un groupe et ne peut pas en retirer d'autres. `usermod -G` sans `-a` devrait être
banni des runbooks.
:::

---

**Q4.4** — *Après `usermod -aG deploy sophie`, sa session ouverte ne voit pas le groupe.*

**Réponse : b) les groupes sont attachés au processus à l'ouverture de session.**

::: pourquoi
Au moment où une session s'ouvre, le processus de login (via `initgroups()`)
interroge NSS, construit la liste des groupes de l'utilisateur et l'attache aux
**credentials du processus** dans le noyau. Cette liste est ensuite héritée par
tous les processus fils. Le noyau ne relit jamais `/etc/group` : il consulte les
credentials du processus courant. Modifier le fichier n'a donc aucun effet
rétroactif sur les processus déjà lancés.

```console
$ id -nG           # dans la session en cours : liste figée
sophie factura
$ getent group deploy    # le fichier, lui, est bien à jour
deploy:x:1003:karim,sophie
```

Pour obtenir la nouvelle liste : se déconnecter/reconnecter (le plus fiable),
`newgrp deploy` (ouvre un sous-shell avec les credentials recalculés), ou
`exec su - "$USER"` (remplace le shell par une session neuve).
:::

::: piege
Le cas classique : on ajoute un dev au groupe `docker`, il retente `docker ps`
dans le même terminal, ça échoue toujours, et on conclut que « l'ajout n'a pas
marché ». Vérifie toujours avec `getent group docker` (le fichier) **et**
`id -nG` (la session) : quand les deux divergent, c'est la reconnexion qu'il faut.
:::

---

**Q4.5** — *`sudo useradd nadia` sur Ubuntu 24.04.*

**Réponse : b) le compte existe, shell `/bin/sh`, `/home/nadia` n'existe pas.**

::: pourquoi
`useradd` est un outil **bas niveau** : il fait exactement ce qu'on lui dit, rien
de plus. Sans `-m`, il n'y a **pas** de création de home ni de copie de
`/etc/skel` — le chemin est bien inscrit dans `/etc/passwd`, mais le répertoire
n'existe pas. Sur Debian et Ubuntu, `/etc/login.defs` ne contient pas
`CREATE_HOME yes`, contrairement à Rocky. Et le shell par défaut vient de
`/etc/default/useradd`, où `SHELL=/bin/sh`.

```console
$ sudo useradd nadia
$ getent passwd nadia
nadia:x:1003:1005::/home/nadia:/bin/sh
$ ls -d /home/nadia
ls: cannot access '/home/nadia': No such file or directory
```

Résultat : l'utilisateur se connecte, atterrit dans un répertoire inexistant,
avec un shell `dash` sans complétion ni historique. C'est précisément le genre de
compte à moitié créé qu'on retrouve en audit.
:::

::: piege
La commande complète et sûre est `useradd -m -s /bin/bash nadia`, ou mieux sur
Debian/Ubuntu `adduser nadia` : le script Perl `adduser` applique
`/etc/adduser.conf`, crée le home, copie skel, crée le groupe éponyme et demande
le mot de passe. En scripting non interactif, on garde `useradd` avec toutes les
options explicites, parce qu'il est identique partout et qu'il ne pose pas de
question.
:::

---

**Q4.6** — *Où est défini l'UID le plus bas pour un humain ?*

**Réponse : b) `/etc/login.defs`.**

::: pourquoi
`/etc/login.defs` porte `UID_MIN`, `UID_MAX`, `SYS_UID_MIN`, `SYS_UID_MAX` et
leurs équivalents GID. C'est ce fichier que consultent `useradd`, `groupadd` et
`usermod` pour choisir le prochain identifiant libre :

```console
$ grep -E '^(SYS_)?(UID|GID)_(MIN|MAX)' /etc/login.defs
UID_MIN                  1000
UID_MAX                 60000
GID_MIN                  1000
GID_MAX                 60000
```

Quand `SYS_UID_MIN`/`SYS_UID_MAX` ne sont pas explicites, les valeurs compilées
s'appliquent (100–999 sur Debian/Ubuntu). `useradd --system` pioche dans la plage
système, `useradd` sans option dans la plage humaine.

`/etc/default/useradd` est un autre fichier, complémentaire : il porte les
**valeurs par défaut** de `useradd` (shell, base des homes, squelette, inactivité),
pas les plages d'UID. `/etc/adduser.conf` ne concerne que le script `adduser`.
:::

::: piege
`login.defs` est lu **à la création**. Modifier `UID_MIN` ou `PASS_MAX_DAYS`
n'affecte aucun compte existant : ce sont des valeurs par défaut, pas une
politique appliquée en continu. Pour changer les comptes existants, il faut une
boucle sur `chage`.
:::

---

**Q4.7** — *`%deploy ALL=(www-data) NOPASSWD: /usr/bin/systemctl restart nginx`,
puis `sudo systemctl restart nginx`.*

**Réponse : b) `sudo` refuse.**

::: pourquoi
La partie entre parenthèses est la spécification **runas** : elle dit en tant que
qui la commande peut être exécutée. Ici, seul `www-data` est autorisé. Or `sudo`
sans `-u` demande implicitement **root**. La demande (`root`) ne correspond à
aucune règle, donc refus :

```console
$ sudo systemctl restart nginx
Sorry, user karim is not allowed to execute '/usr/bin/systemctl restart nginx'
as root on lab-web.
```

La commande qui matche la règle est `sudo -u www-data systemctl restart nginx` —
qui échouera ensuite pour une **autre** raison : `www-data` n'a pas le droit de
piloter systemd. La règle est donc doublement inutile. La forme correcte pour ce
besoin est `(root)` ou `(ALL)`.
:::

::: piege
La spécification runas peut aussi porter un groupe : `(root:adm)` autorise
`sudo -u root -g adm`. Et `(ALL:ALL)` — la forme du `%sudo ALL=(ALL:ALL) ALL`
d'Ubuntu — signifie « n'importe quel utilisateur, n'importe quel groupe » : c'est
un accès root complet, pas une restriction.
:::

---

**Q4.8** — *Quelles autorisations `sudo` donnent en pratique un shell root ?*

**Réponses : a) `vim`, b) `find`, d) `less`.**

::: pourquoi
La question n'est jamais « que fait ce programme ? » mais « ce programme
peut-il en lancer un autre ? ». Trois exemples, exécutés avec les privilèges root
hérités de `sudo` :

```console
$ sudo vim /etc/hosts
:!/bin/bash                      # shell root depuis vim
$ sudo find /etc -name hosts -exec /bin/bash \;
# root
$ sudo less /var/log/syslog
!/bin/bash                       # le pager less lance un shell
```

`find` est le pire du lot : `-exec` est une fonctionnalité documentée, elle
n'exige aucune astuce. `vim` et `less` embarquent un échappement shell historique.
Restreindre les **arguments** dans `sudoers` (`vim /etc/hosts`) ne change rien :
une fois `vim` lancé en root, il fait ce qu'il veut. Seul `id` (c) ne peut lancer
aucun processus fils : c'est une délégation sans danger.

Le catalogue de référence de ces évasions est le projet **GTFOBins** : avant
d'accorder une commande dans `sudoers`, on l'y cherche.
:::

::: piege
Le piège insidieux, c'est `systemctl` : sa sortie longue passe par un pager
(`less`), et `!sh` dans ce pager donne root. Neutralise-le avec
`SYSTEMD_PAGER=` / `--no-pager`, ou en n'autorisant que les sous-commandes
sans sortie paginée. Même logique pour `journalctl`, `man`, `git`, `tar`
(`--to-command`), `awk` (`system()`), `python3`, `perl`.
:::

---

**Q4.9** — *`sudo -i` vs `sudo -s`.*

**Réponse : b)** `-i` = shell de **login** root ; `-s` = shell root qui garde ton
environnement et ton répertoire.

::: pourquoi
`sudo -i` simule une connexion complète en root : il lit `/root/.profile` (et
`/root/.bashrc` par ricochet), positionne `HOME=/root`, `USER=root`,
`SHELL=/bin/bash` (celui de root dans `/etc/passwd`), et fait un `cd /root`.
C'est l'équivalent moderne de `su -`.

`sudo -s` lance ton shell (`$SHELL`) avec les privilèges root, **sans** faire de
login : tu restes dans ton répertoire courant, `HOME` reste le tien, tes variables
survivent dans les limites d'`env_reset`.

```console
$ pwd ; echo $HOME
/home/karim
/home/karim
$ sudo -i -- sh -c 'pwd; echo $HOME'
/root
/root
$ sudo -s -- sh -c 'pwd; echo $HOME'
/home/karim
/home/karim
```

Conséquence pratique : avec `sudo -s`, un fichier créé sans chemin absolu atterrit
dans **ton** home, appartenant à root — cause fréquente de « je ne peux plus
écrire dans mon propre répertoire ».
:::

::: piege
`sudo -s` conserve `HOME`, donc `sudo -s` puis `vim` chargera **ton** `.vimrc` en
root. Si ton `.vimrc` source un plugin, tu exécutes du code non maîtrisé en root.
C'est la raison pour laquelle `env_reset` et `sudo -i` sont la combinaison
recommandée pour toute session d'administration.
:::

---

**Q4.10** — *`Defaults timestamp_timeout=0`.*

**Réponse : b) le mot de passe est demandé à chaque invocation.**

::: pourquoi
Après une authentification réussie, `sudo` pose un « ticket » (un fichier
horodaté dans `/run/sudo/ts/<user>`) valable `timestamp_timeout` minutes, 15 par
défaut sur Ubuntu — d'où l'impression que `sudo` « se souvient ». Mettre `0`
réduit cette fenêtre à néant : chaque `sudo` redemande le mot de passe. Une valeur
**négative** (`-1`) fait l'inverse : le ticket ne périme jamais dans la session.

```bash
sudo -k          # invalide le ticket tout de suite, sans changer la conf
sudo -K          # supprime complètement le fichier d'horodatage
sudo -v          # rafraîchit le ticket sans lancer de commande
```

Un `timestamp_timeout` à 0 est la bonne valeur pour les comptes à privilèges
élevés (bastion, comptes d'astreinte) : il empêche qu'un terminal laissé ouvert
serve à quelqu'un d'autre.
:::

::: piege
Ne pas confondre avec `!authenticate` ou `NOPASSWD`, qui suppriment la demande de
mot de passe. `timestamp_timeout` ne change pas **si** on demande, seulement
**pendant combien de temps** on ne redemande pas.
:::

---

**Q4.11** — *`sudo purge.sh` → `command not found` alors que le script existe.*

**Réponse : b) `secure_path` remplace le `PATH`.**

::: pourquoi
Ubuntu active par défaut :

```text
Defaults  secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:\
                       /usr/bin:/sbin:/bin:/snap/bin"
```

Quand `secure_path` est défini, `sudo` **ignore** le `PATH` de l'utilisateur et
impose celui-ci pour résoudre la commande. `/opt/factura/bin` n'y figure pas :
`purge.sh` est introuvable, d'où `command not found` — message trompeur, car le
fichier existe et est exécutable.

Trois façons de s'en sortir, par ordre de préférence :

```bash
sudo /opt/factura/bin/purge.sh        # chemin absolu : toujours correct
# ou, dans sudoers, pour ce groupe seulement :
Defaults:%deploy secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:\
/usr/bin:/sbin:/bin:/opt/factura/bin"
# ou un lien symbolique dans /usr/local/sbin
```

Dans `sudoers`, les commandes doivent **toujours** être écrites en chemin absolu :
c'est ce qui garantit que la règle désigne bien le binaire attendu et pas un
homonyme placé plus tôt dans un `PATH` manipulé.
:::

::: piege
`secure_path` est une protection, pas une gêne : sans lui, un utilisateur pourrait
placer un faux `systemctl` dans son `~/bin`, et une règle `sudo systemctl ...`
exécuterait son script en root. Ne le désactive jamais pour « faire marcher » un
script : corrige le chemin.
:::

---

**Q4.12** — *Bloquer immédiatement toute connexion de `pcontrat`, clé SSH comprise.*

**Réponse : c) `sudo chage -E 0 pcontrat`.**

::: pourquoi
Il faut distinguer les trois niveaux de blocage, qui n'agissent pas au même
endroit de la chaîne :

| Action | Champ modifié | Bloque |
|---|---|---|
| `passwd -l` | shadow champ 2 (`!`) | l'authentification par **mot de passe** |
| `usermod -s /usr/sbin/nologin` | passwd champ 7 | l'ouverture d'un **shell** |
| `chage -E 0` | shadow champ 8 | **toute** la session, au niveau `account` |

Une clé SSH ne passe pas par le mot de passe : `passwd -l` ne la gêne donc
absolument pas (a est faux). Un shell `nologin` bloque le shell interactif, mais
`ssh user@host 'commande'` peut encore aboutir selon la configuration, et le compte
reste utilisable par `sudo -u` (b insuffisant). Retirer du groupe `sudo` ne bloque
que l'élévation, pas la connexion (d hors sujet).

`chage -E 0` inscrit une date d'expiration au 1ᵉʳ janvier 1970 : la phase
`account` de PAM (`pam_unix.so`) constate que le compte est expiré et refuse la
session, quelle que soit la méthode d'authentification.

```console
$ sudo chage -E 0 pcontrat
$ sudo chage -l pcontrat | grep Account
Account expires                                         : Jan 01, 1970
```
:::

::: piege
`chage -E -1` **retire** l'expiration (c'est la valeur « jamais »), `chage -E 0`
l'impose immédiatement. L'inversion de ces deux valeurs est une erreur classique
en script. Et attention : l'expiration ne tue pas les sessions **déjà ouvertes**
ni les processus en cours — ajoute un `pkill -u pcontrat` si l'urgence l'exige.
:::

---

**Q4.13** — *`chage -d 0 hugo`.*

**Réponse : b) `hugo` doit changer son mot de passe à la prochaine connexion.**

::: pourquoi
Le champ 3 de `/etc/shadow` est la date du dernier changement de mot de passe, en
jours depuis le 1ᵉʳ janvier 1970. La valeur `0` est traitée spécialement : elle
signifie « ce mot de passe doit être changé avant toute utilisation ». À la
connexion, la phase `account` de PAM renvoie `new_authtok_reqd`, et la pile
`password` est déclenchée immédiatement :

```console
hugo@lab-adm's password:
You are required to change your password immediately (administrator enforced).
Current password:
New password:
```

C'est le mécanisme standard de la remise de compte : l'administrateur pose un mot
de passe initial, `chage -d 0`, et il ne le connaîtra plus dès la première
connexion de l'utilisateur.
:::

::: piege
`chage -d 0` ne fonctionne que si un mot de passe **existe**. Sur un compte dont
le champ vaut `!` ou `*`, l'utilisateur ne pourra tout simplement pas
s'authentifier, donc jamais atteindre l'invite de changement. Ordre correct :
poser le mot de passe (`chpasswd`), **puis** `chage -d 0`.
:::

---

**Q4.14** — *`*` contre `!` dans le champ mot de passe de `/etc/shadow`.*

**Réponse : b)** `*` = aucun mot de passe jamais défini ; `!` = verrouillage.

::: pourquoi
Aucune des deux chaînes n'est un hachage valide, donc aucune saisie ne peut
réussir — l'effet pratique est le même. Mais l'**intention** et la réversibilité
diffèrent :

* `*` : la convention pour « ce compte n'est pas destiné à s'authentifier par mot
  de passe ». C'est ce que portent les comptes système (`daemon`, `www-data`,
  `root` sur Ubuntu).
* `!` : le verrou posé par `passwd -l` / `usermod -L`. Il **préfixe** le hachage
  existant, qui reste stocké dessous, et `passwd -u` le retire pour restaurer
  l'état antérieur.
* `!!` : créé par `useradd` sur RHEL ou par `adduser --disabled-password` — aucun
  mot de passe n'a encore été défini, mais la case est réservée.
* **vide** : le compte se connecte **sans** mot de passe. Toujours une anomalie.

```console
$ sudo getent shadow root | cut -d: -f1,2
root:*
$ sudo passwd -l sophie ; sudo getent shadow sophie | cut -d: -f2 | cut -c1-6
!$y$j9
```
:::

::: piege
`passwd -u` sur un compte dont le champ est réduit à `!` échoue :

```console
$ sudo passwd -u nadia
passwd: unlocking the password would result in a passwordless account.
You should set a password with usermod -p to unlock the password of
this account.
```

`passwd` protège contre la création accidentelle d'un compte sans mot de passe.
La bonne réponse n'est pas `passwd -u -f` (qui, lui, produit ce compte
dangereux) mais `passwd nadia` pour en poser un.
:::

---

**Q4.15** — *`getent group factura` ne liste pas `sophie`, mais `id sophie` affiche `gid=1002(factura)`.*

**Réponse : b) `factura` est son groupe primaire.**

::: pourquoi
L'appartenance d'un utilisateur à un groupe est stockée à **deux endroits
différents** selon sa nature :

* groupe **primaire** : dans le 4ᵉ champ de sa ligne `/etc/passwd` (un GID) ;
* groupes **secondaires** : dans la liste des membres du groupe, dans `/etc/group`.

Un utilisateur n'apparaît donc jamais comme membre de son propre groupe primaire
dans `/etc/group`. La seule vue complète est `id` (ou `groups`), qui réunit les
deux sources :

```console
$ getent passwd sophie
sophie:x:1001:1002:Sophie Perrin:/home/sophie:/bin/bash
                     ^^^^ GID primaire = 1002 = factura
$ getent group factura
factura:x:1002:karim
$ id sophie
uid=1001(sophie) gid=1002(factura) groups=1002(factura),1003(deploy)
```
:::

::: piege
Conséquence en exploitation : un script qui liste « qui est dans le groupe
`factura` » avec `getent group factura | cut -d: -f4` **rate** tous les comptes
dont c'est le groupe primaire. La méthode correcte :
`getent passwd | while IFS=: read -r u _ _ g _; do ... ; done` en croisant le GID,
ou plus simplement une boucle sur `id -nG`.
:::

---

**Q4.16** — *`getent passwd jdupont` répond, `grep` dans `/etc/passwd` non.*

**Réponse : b) le compte vient d'une autre source NSS.**

::: pourquoi
`getent` interroge la **Name Service Switch** : la bibliothèque C consulte les
sources déclarées dans `/etc/nsswitch.conf`, dans l'ordre, jusqu'à ce que l'une
réponde.

```console
$ grep ^passwd /etc/nsswitch.conf
passwd:         files systemd sss
$ getent passwd jdupont
jdupont:*:1523400513:1523400513:Jean Dupont:/home/jdupont:/bin/bash
$ grep jdupont /etc/passwd
$ 
```

Ici, `files` n'a rien trouvé et `sss` (SSSD, donc LDAP ou Active Directory) a
répondu. C'est exactement le comportement attendu sur une machine jointe à un
annuaire : les comptes du domaine n'existent **pas** dans `/etc/passwd`, et tout
script qui `grep` le fichier au lieu d'appeler `getent` est faux sur ces machines.
:::

::: piege
Corollaire de sécurité : un audit qui lit `/etc/passwd` et `/etc/shadow` ne voit
que les comptes locaux. Sur un serveur joint au domaine, l'inventaire réel des
identités pouvant ouvrir une session se fait avec `getent passwd` **plus** la
configuration SSSD (`access_provider`, `simple_allow_groups`), qui restreint quels
comptes du domaine ont le droit de se connecter sur cette machine-là.
:::

---

**Q4.17** — *Débloquer `karim` verrouillé par `pam_faillock` (5 échecs).*

**Réponse : b) `sudo faillock --user karim --reset`.**

::: pourquoi
`pam_faillock` ne touche ni `/etc/shadow` ni `/etc/passwd` : il tient un compteur
d'échecs **hors des fichiers de comptes**, dans `/var/run/faillock/<user>`. Tant
que le compteur dépasse `deny=`, le module renvoie un échec dans la phase `auth`,
avec le message `Account locked due to N failed logins`.

```console
$ sudo faillock --user karim
karim:
When                Type  Source     Valid
2026-09-18 14:02:11 TTY   ssh:notty      V
2026-09-18 14:02:14 TTY   ssh:notty      V
...
$ sudo faillock --user karim --reset
$ sudo faillock --user karim
karim:
When                Type  Source     Valid
```

Les autres réponses agissent ailleurs : `passwd -u` / `usermod -U` retirent le `!`
de `/etc/shadow` — or le mot de passe n'a jamais été verrouillé là ; `chage -d 0`
force un changement de mot de passe, sans toucher au compteur.
:::

::: piege
Diagnostic à retenir : quand `passwd -S` dit `P` (mot de passe valide), que
`chage -l` ne montre aucune expiration, et que la connexion échoue quand même,
c'est presque toujours `pam_faillock` (ou son ancêtre `pam_tally2`). Le vrai
indice est dans `/var/log/auth.log` : `pam_faillock(sshd:auth): Consecutive login
failures for user karim account temporarily locked`.
:::

---

**Q4.18** — *`/etc/sudoers.d/60-deploy.conf` valide mais sans effet.*

**Réponse : b) les fichiers dont le nom contient un `.` sont ignorés.**

::: pourquoi
`sudo` traite `/etc/sudoers.d/` avec les mêmes règles que `run-parts` : il ignore
délibérément tout fichier dont le nom contient un point (`.`) ou se termine par un
tilde (`~`). L'intention est d'éviter qu'un `60-deploy.bak`, `60-deploy.rpmnew` ou
`60-deploy.dpkg-dist` laissé par une mise à jour n'accorde par surprise des droits
qu'on croyait supprimés.

```console
$ ls /etc/sudoers.d/
60-deploy.conf   README
$ sudo -l -U karim
User karim is not allowed to run sudo on lab-adm.
$ sudo mv /etc/sudoers.d/60-deploy.conf /etc/sudoers.d/60-deploy
$ sudo -l -U karim
User karim may run the following commands on lab-adm:
    (root) NOPASSWD: /usr/bin/systemctl restart nginx
```

Le pire de ce comportement, c'est le silence : aucun avertissement, aucune erreur.
Convention à adopter : nom en `NN-sujet`, sans extension, et toujours vérifier
avec `sudo -l -U <user>` après dépôt.
:::

::: piege
Les autres causes de « fichier ignoré ou refusé » à connaître : mode différent de
`0440` (world-writable = refus pur et simple, avec message), propriétaire autre que
root, et `@includedir /etc/sudoers.d` absent de `/etc/sudoers`. Le contrôle qui les
couvre toutes : `sudo visudo -c`, qui liste chaque fichier lu avec son verdict.
:::

---

## 4.4 Quiz — questions ouvertes

**QO4.1** — *Décoder `pcontrat:$6$rEkP2x$8Zq...:20700:7:60:14:10:20790:`*

**Réponse attendue :**

| # | Valeur | Signification |
|---|---|---|
| 1 | `pcontrat` | login |
| 2 | `$6$rEkP2x$8Zq...` | hachage **SHA-512** (`$6$`), sel `rEkP2x` |
| 3 | `20700` | dernier changement : 20700 jours après 1970-01-01 = **2026-09-04** |
| 4 | `7` | âge minimum : pas de nouveau changement avant 7 jours |
| 5 | `60` | âge maximum : renouvellement obligatoire au bout de 60 jours |
| 6 | `14` | avertissement 14 jours avant échéance |
| 7 | `10` | inactivité : 10 jours de tolérance après expiration |
| 8 | `20790` | expiration du **compte** : 20790 jours = **2026-12-03** |
| 9 | (vide) | champ réservé |

Renouvellement obligatoire à partir du 2026-09-04 + 60 j = **2026-11-03**.
Avertissement à partir du 2026-10-20. Après le 2026-11-03, il reste **10 jours**
(jusqu'au 2026-11-13) pour changer le mot de passe à la connexion ; ensuite le
compte devient inutilisable même avec le bon mot de passe. Et le 2026-12-03, le
compte expire de toute façon.

```bash
sudo chage -l pcontrat            # tout en clair, sans calcul
date -d "1970-01-01 +20700 days" +%F
```

::: pourquoi
Le point qui fait la différence en entretien, c'est de distinguer les champs 5+7
(cycle de vie du **mot de passe**) du champ 8 (cycle de vie du **compte**).
Le champ 7 (« inactive ») est le moins connu : il définit une période de grâce
pendant laquelle l'utilisateur peut encore se connecter **uniquement pour changer
son mot de passe expiré**. Sans lui (champ vide), un mot de passe expiré donne
lieu à un changement forcé sans limite de temps. Avec `-I 10`, passé 10 jours, la
phase `account` de PAM refuse la session : l'utilisateur doit appeler le support.

Toutes ces dates sont en **jours depuis l'epoch**, pas en secondes : c'est la
source d'erreur classique quand on écrit un script d'audit (`$(( $(date +%s)
/ 86400 ))` donne le jour courant dans la même unité).
:::

---

**QO4.2** — *`su` vs `sudo`, et pourquoi root est désactivé sur Ubuntu.*

**Réponse attendue :**

`su` demande le mot de passe **du compte cible** et ouvre une session complète
sous cette identité : c'est un tout-ou-rien, et il faut partager le mot de passe
root entre tous ceux qui en ont besoin. `sudo` demande le mot de passe **de
l'appelant**, vérifie dans `/etc/sudoers` ce qu'il a précisément le droit de
faire, exécute une seule commande et journalise l'appel nominativement.

Sur Ubuntu, root a `*` dans le champ mot de passe de `/etc/shadow` : aucun mot de
passe ne peut être saisi, donc `su -` et une connexion directe en root sont
impossibles. Ce n'est pas une suppression du compte (UID 0 existe toujours, les
processus tournent en root), c'est une désactivation de l'**authentification**.

Ce que ça change en exploitation : plus de secret partagé à faire tourner quand
quelqu'un quitte l'équipe (il suffit de le sortir du groupe `sudo`) ; une trace
nominative dans `/var/log/auth.log` et `journalctl` (`karim : TTY=pts/1 ;
PWD=/home/karim ; USER=root ; COMMAND=/usr/bin/systemctl restart nginx`) au lieu
d'un anonyme « root a fait ça » ; et la possibilité de déléguer une commande
précise plutôt que tout. En contrepartie, il faut une procédure de récupération
hors sudo (console + mode de récupération), puisque plus personne ne peut faire
`su -`.

::: pourquoi
La question sous-jacente en entretien est celle de l'**imputabilité**. Un
serveur où trois personnes connaissent le mot de passe root est un serveur où
aucune action n'est attribuable. Le modèle `sudo` transforme « qui connaît le
secret ? » en « qui est autorisé, et qu'a-t-il fait ? ». C'est aussi ce qui rend
possible l'audit : la liste des privilèges est un fichier versionnable
(`/etc/sudoers.d/`), pas un mot de passe dans un coffre.
:::

::: piege
Attention à la demi-réponse « root est supprimé sur Ubuntu » : c'est faux et ça se
voit tout de suite. Root existe, il est propriétaire de la moitié du système, et
`sudo -i` l'ouvre. Ce qui est désactivé, c'est la connexion **par mot de passe**.
Un `sudo passwd root` le réactive — ce que l'on évite précisément de faire.
:::

---

**QO4.3** — *Un dev demande `sudo` sur `/usr/bin/find`.*

**Réponse attendue :** non.

`find` embarque `-exec`, qui lance un programme arbitraire en héritant des
privilèges du processus `find` — donc root :

```bash
sudo find /tmp -maxdepth 0 -exec /bin/bash \;
# root@lab-web:/tmp#
```

Aucune restriction d'arguments dans `sudoers` n'y change quoi que ce soit : même
`sudo find /var/tmp -name '*.tmp' -delete` autorisé tel quel laisse la porte
ouverte dès que l'utilisateur peut ajouter un argument, et interdire les
arguments supplémentaires n'est pas fiable (`sudoers` compare des motifs, pas une
sémantique).

Deux réponses au besoin réel :

1. **Un script sous contrôle** : écrire `/usr/local/sbin/purge-tmp-factura`,
   propriété `root:root` en `0755`, qui fait exactement la purge voulue (chemins
   en dur, `-xdev`, pas d'argument accepté), puis
   `%dev ALL=(root) NOPASSWD: /usr/local/sbin/purge-tmp-factura`. La surface
   d'attaque devient le contenu du script, que tu maîtrises et versionnes.
2. **Pas de sudo du tout** : donner au répertoire un groupe `dev` avec SGID
   (`chgrp dev /var/tmp/factura ; chmod 2770`), ou programmer la purge en
   `systemd-tmpfiles` / timer systemd tournant en root. Le besoin « nettoyer des
   fichiers » n'exige presque jamais une élévation interactive.

::: pourquoi
Le raisonnement général se formule en une phrase : **déléguer un interpréteur,
c'est déléguer root**. Sont des interpréteurs, même sans en avoir l'air : les
éditeurs (`vim`, `nano`), les pagers (`less`, `more`, `man`), les outils à `-exec`
ou `--to-command` (`find`, `tar`, `rsync`), les langages (`python3`, `perl`,
`awk`), et tout ce qui pagine sa sortie (`systemctl`, `journalctl`, `git`).
La bonne pratique est d'interposer systématiquement un **script à toi**, root,
non modifiable par l'appelant, dont les paramètres sont fixes ou validés.
:::

::: piege
Piège dans le piège : si le script délégué est modifiable par le demandeur
(par exemple posé dans `/home/dev/bin` ou en `775 root:dev`), la délégation est
équivalente à root. Le script doit appartenir à `root:root`, être en `0755` au
plus permissif, et se trouver dans un répertoire lui aussi non modifiable
(`/usr/local/sbin`).
:::

---

**QO4.4** — *Pourquoi `usermod -aG docker sophie` ne change rien dans sa session.*

**Réponse attendue :** au moment du login, PAM appelle `initgroups()`, qui
interroge NSS, construit la liste complète des GID de l'utilisateur et l'attache
aux **credentials du processus** dans le noyau. Ces credentials sont hérités par
fork/exec et ne sont jamais réévalués : le noyau ne relit pas `/etc/group` à
chaque appel système, il compare aux GID stockés dans la structure du processus.
`usermod` modifie le fichier ; la session, elle, travaille sur une photo prise à
l'ouverture.

Trois façons d'obtenir les nouveaux droits :

| Méthode | Portée | Limite |
|---|---|---|
| se déconnecter/reconnecter | toute la nouvelle session | la plus fiable, mais il faut fermer son travail |
| `newgrp docker` | sous-shell, `docker` devient groupe **primaire** | les fichiers créés prennent `docker` comme groupe ; on empile des shells |
| `exec su - "$USER"` | remplace le shell courant | redemande le mot de passe, et perd les variables de la session |

`sg docker -c 'docker ps'` est la variante « une seule commande ». En revanche,
les **processus déjà lancés** (un `tmux` détaché, un service utilisateur systemd)
gardent leurs anciens groupes jusqu'à leur redémarrage.

::: pourquoi
Le même mécanisme explique un cas plus perturbant : retirer quelqu'un d'un groupe
ne lui retire pas l'accès tant qu'il a une session ouverte. Pour une révocation
d'urgence, changer l'appartenance ne suffit **pas** — il faut tuer les sessions
(`pkill -u sophie`) ou expirer le compte (`chage -E 0`). C'est la différence entre
modifier une base d'identités et modifier l'état du système.
:::

---

**QO4.5** — *Six caractéristiques d'un compte de service `factura`.*

**Réponse attendue :**

| Caractéristique | Valeur | Ce que ça empêche |
|---|---|---|
| UID système | < 1000 (`useradd --system`) | d'apparaître dans les listes d'humains, d'être traité comme un compte nominatif par les outils d'audit et les annuaires |
| Shell | `/usr/sbin/nologin` | l'ouverture d'un shell interactif si le mot de passe ou une clé fuit |
| Mot de passe | `*` dans shadow | toute authentification par mot de passe, y compris `su` |
| Groupe | groupe dédié `factura`, jamais `sudo`/`adm`/`docker` | l'élévation de privilèges et l'accès aux journaux d'autres services |
| Home | `/var/lib/factura`, `0750`, ou `/nonexistent` | l'écriture dans `/home` et la présence de fichiers de démarrage (`.bashrc`, `.ssh/authorized_keys`) détournables |
| Propriété des fichiers | le service **ne possède pas** son propre code | la modification du code exécuté par le service depuis le service lui-même |

On ajoute volontiers : pas de `crontab` personnelle, pas de `.ssh/`, et une
`systemd` unit avec `User=factura`, `ProtectSystem=strict`, `NoNewPrivileges=yes`.

::: pourquoi
La logique commune à ces six points : en cas de compromission de l'application
(RCE dans un endpoint web, par exemple), l'attaquant obtient l'exécution de code
**sous l'identité du service**. Chaque caractéristique ferme une voie de
persistance ou d'escalade. Le shell `nologin` l'empêche de revenir par SSH ; le
home hors `/home` et sans `.ssh` l'empêche d'y déposer une clé ; le mot de passe
`*` l'empêche de passer par `su` ; le fait que le service ne possède pas son code
l'empêche de se greffer un backdoor persistant qui sera exécuté au prochain
redémarrage, en root si le service est lancé par root avant de descendre.
:::

::: piege
Le point le plus souvent raté : le compte de service **propriétaire de son propre
répertoire d'installation**. `chown -R factura:factura /opt/factura` a l'air
propre, mais donne à l'application le droit de réécrire ses propres binaires et
scripts. La règle est `root:factura` avec `0640`/`0750` : le service **lit** sa
configuration et son code, il n'écrit que dans ses répertoires de données et de
journaux.
:::

---

**QO4.6** — *« Je ne peux plus me connecter » : démarche de diagnostic.*

**Réponse attendue :** on remonte la chaîne, du plus grossier au plus subtil.

```bash
# 1. le compte existe-t-il, et pour quelle source ?
getent passwd karim            # rien -> compte absent ou NSS HS
grep ^passwd /etc/nsswitch.conf

# 2. shell et home
getent passwd karim | awk -F: '{print $6, $7}'
ls -ld /home/karim             # home absent = session qui échoue ou tombe en /

# 3. état du mot de passe
sudo passwd -S karim           # P = ok, L = verrouillé, NP = vide

# 4. expiration du mot de passe ET du compte
sudo chage -l karim            # "Account expires" dans le passé = blocage total

# 5. verrouillage PAM par échecs
sudo faillock --user karim

# 6. la vérité est dans le journal, côté serveur
sudo journalctl -u ssh -n 50 --no-pager
sudo tail -50 /var/log/auth.log
```

Cas « ça marche en clé mais pas en mot de passe » : `passwd -l` ou
`PasswordAuthentication no` côté SSH — l'authentification par clé ne consulte pas
le champ mot de passe. Cas inverse « ça marche en mot de passe mais pas en clé » :
droits de `~/.ssh` (relève du module 12). Cas « authentification OK mais session
qui se ferme aussitôt » : shell `nologin`/`false`, ou home inexistant.

::: pourquoi
L'ordre n'est pas arbitraire : il suit les **phases PAM**. `auth` (le mot de passe
est-il bon ? le compteur d'échecs est-il dépassé ?), puis `account` (le compte
est-il expiré, le mot de passe est-il périmé au-delà de la tolérance ?), puis
`session` (limites, home, shell). Un message `Permission denied` côté client est
volontairement peu bavard — c'est une protection. La vraie information est
toujours côté serveur, dans `auth.log` : `Failed password`, `User karim not
allowed because account is locked`, `Account locked due to 5 failed logins`,
`User karim not allowed because shell /usr/sbin/nologin does not exist`.
:::

::: piege
Erreur fréquente : conclure trop vite sur `passwd -S`. Un compte peut afficher
`P` (mot de passe valide) et rester inaccessible pour trois autres raisons — date
d'expiration passée, `faillock`, shell `nologin`. Il faut dérouler **toute** la
liste avant de conclure, ce qui est justement l'objet de BF4.2.
:::

---

**QO4.7** — *Serveurs joints à l'Active Directory via SSSD : qu'est-ce qui change ?*

**Réponse attendue :**

**Ce qui change** : les comptes n'existent plus dans `/etc/passwd` ; la
résolution passe par SSSD (`passwd: files sss` dans `/etc/nsswitch.conf`) ;
l'authentification passe par `pam_sss.so` dans la pile `auth` ; les UID/GID sont
attribués par l'annuaire (souvent dérivés du SID Windows, donc dans les millions)
et sont **identiques sur tous les serveurs**, ce qui rend enfin cohérents les
partages NFS ; la politique de mot de passe (complexité, expiration) est celle du
domaine, plus celle de `login.defs` ; SSSD met en cache les identités, ce qui
permet de se connecter même si l'annuaire est injoignable, et introduit une classe
de bugs propre (« j'ai changé le groupe dans l'AD, le serveur ne le voit pas »,
résolue par `sss_cache -E`).

**Ce qui ne change pas** : le modèle de droits UNIX (les fichiers portent toujours
un UID/GID numérique, `chmod` et `chown` fonctionnent à l'identique) ;
`/etc/sudoers` reste local par défaut — il faut le déclarer explicitement dans
l'annuaire (`sudoers: files sss`) pour le centraliser ; les comptes **système**
restent locaux ; `id`, `groups`, `getent` fonctionnent pareil.

Les deux fichiers à regarder en premier : `/etc/nsswitch.conf` (quelles sources,
dans quel ordre) et `/etc/sssd/sssd.conf` (domaine, `access_provider`,
`simple_allow_groups`, `override_homedir`, `use_fully_qualified_names`).

La commande qui tranche :

```bash
getent passwd jdupont           # répond ? -> résolu, mais par qui ?
grep jdupont /etc/passwd        # rien -> ça vient de l'annuaire
id jdupont                      # UID à 7 chiffres = mappage SID
```

::: pourquoi
Le message à faire passer en entretien : joindre un annuaire ne change **pas** le
modèle de sécurité Linux, il change seulement la **source** des identités. Tout ce
qu'on a appris sur les UID, les groupes, les permissions et `sudo` reste vrai
mot pour mot. Ce qui devient critique, c'est de ne plus jamais coder en dur
`/etc/passwd` dans les scripts, et de réfléchir à ce qui se passe quand l'annuaire
est indisponible (cache SSSD, comptes de secours locaux — on garde toujours un
compte local d'urgence sur chaque serveur, dans le groupe `sudo`).
:::

::: piege
Piège d'entretien classique : « et si l'AD tombe ? ». Mauvaise réponse : « on ne
peut plus se connecter ». Bonne réponse : SSSD sert les identités depuis son cache
(`cache_credentials = true`) pendant `offline_credentials_expiration`, et de toute
façon on maintient sur chaque machine un compte local de secours, avec un mot de
passe au coffre, membre de `sudo` — sinon un incident d'annuaire devient un
incident de production sans porte d'entrée.
:::

---

**QO4.8** — *La pile PAM : types, contrôles, et où se placent trois modules.*

**Réponse attendue :**

Les quatre **types** (ou « piles »), chacun consulté à un moment précis :

| Type | Question posée | Exemples |
|---|---|---|
| `auth` | l'utilisateur prouve-t-il son identité ? | `pam_unix`, `pam_faillock`, `pam_sss` |
| `account` | ce compte a-t-il **le droit** d'ouvrir une session maintenant ? | `pam_unix` (expiration), `pam_time`, `pam_access` |
| `password` | comment change-t-on le secret ? | `pam_pwquality`, `pam_unix`, `pam_pwhistory` |
| `session` | que met-on en place autour de la session ? | `pam_limits`, `pam_mkhomedir`, `pam_systemd` |

Les **contrôles** :

* `required` : un échec fait échouer la pile, mais **les modules suivants sont
  quand même exécutés** (on ne révèle pas lequel a échoué) ;
* `requisite` : un échec interrompt immédiatement et retourne l'erreur ;
* `sufficient` : un succès termine la pile avec succès (si aucun `required`
  précédent n'a échoué) ; un échec est ignoré ;
* `optional` : n'influe sur le résultat que si c'est le seul module de la pile ;
* la forme `[success=1 default=ignore]` est la syntaxe étendue : elle décrit saut
  par saut quoi faire pour chaque code retour — c'est celle qu'utilise Debian dans
  `common-auth`.

Placement des trois modules :

* `pam_pwquality` → **`password`**, et nulle part ailleurs : il n'intervient que
  lors d'un **changement** de secret, pour juger le nouveau mot de passe avant que
  `pam_unix` ne le hache. Il doit précéder `pam_unix` dans la pile.
* `pam_faillock` → **`auth`** (comptage des échecs et refus) **et** `account`
  (vérification du verrou), en deux lignes `preauth`/`authfail` : c'est une
  décision d'authentification, il lui faut le résultat de la tentative.
* `pam_limits` → **`session`** : il applique `setrlimit()` sur le processus de la
  session **après** que l'identité est établie. Avant, il n'y aurait rien à
  limiter.

::: pourquoi
La clé pour ne plus jamais se tromper : chaque type correspond à un moment du
cycle de vie d'une session. `auth` = « qui es-tu », `account` = « as-tu le droit
d'entrer », `password` = « change ton secret », `session` = « je t'installe ».
Un module placé dans la mauvaise pile n'est simplement jamais appelé — sans
erreur, sans avertissement. C'est pourquoi une conf PAM se teste toujours dans un
second terminal, la première session root restant ouverte.

Sur Debian/Ubuntu, les fragments communs sont dans `common-auth`,
`common-account`, `common-password`, `common-session`, inclus par chaque service
via `@include`. `pam_limits`, lui, n'est pas dans `common-session` : il est appelé
explicitement dans `/etc/pam.d/login`, `/etc/pam.d/sshd`, `/etc/pam.d/su` et
`/etc/pam.d/sudo`.
:::

::: piege
Sous Rocky/RHEL, ne jamais éditer `/etc/pam.d/system-auth` ni `password-auth` à la
main : ils sont régénérés par `authselect`, et ta modification disparaît à la
prochaine mise à jour. On passe par `authselect enable-feature with-faillock` puis
`authselect apply-changes`, ou par un profil personnalisé
(`authselect create-profile`).
:::

---

## 4.5 Exercices guidés

**E4.1** — *UID, GID primaire et groupes secondaires de `sophie`.*

```bash
id -u sophie          # 1001
id -gn sophie         # factura  (groupe primaire)
id -Gn sophie | tr ' ' '\n' | grep -vx "$(id -gn sophie)"
```

::: pourquoi
`id -G` renvoie **tous** les groupes, primaire compris : il n'existe pas d'option
« secondaires seulement ». On retire donc le primaire explicitement. L'alternative
`getent group | awk -F: -v u=sophie '$4 ~ u {print $1}'` fonctionne aussi, mais
elle se fait piéger par les sous-chaînes (`sophie` matcherait `sophieb`) : il
faudrait un test exact sur la liste éclatée.
:::

---

**E4.2** — *Comptes humains, triés par UID, au format `UID login shell`.*

```bash
umin=$(awk '$1=="UID_MIN"{print $2}' /etc/login.defs)
getent passwd | awk -F: -v m="$umin" \
  '$3>=m && $3!=65534 {printf "%s %s %s\n", $3, $1, $7}' | sort -n
```

::: pourquoi
Trois décisions comptent ici. `getent passwd` plutôt que `cat /etc/passwd` :
seul `getent` voit les comptes d'annuaire, et l'exercice doit rester juste sur une
machine jointe à un domaine. La lecture de `UID_MIN` dans `login.defs` plutôt
qu'un `1000` en dur : la valeur diffère selon les distributions et les
installations. L'exclusion de `65534` : `nobody` a un UID très élevé et n'est pas
un humain.
:::

::: piege
`sort` sans `-n` trie en lexicographique : `1000` arriverait avant `999`. Et
`awk -F:` sur `/etc/passwd` échoue si un champ GECOS contient un `:` — ce qui est
interdit par le format, mais qu'on trouve quand même dans la vraie vie.
:::

---

**E4.3** — *Comptes dont le shell figure dans `/etc/shells`.*

```bash
getent passwd | awk -F: '
  NR==FNR { if ($0 !~ /^#/ && NF) shells[$0]; next }
  $7 in shells { printf "%-12s %s\n", $1, $7 }
' /etc/shells -
```

::: pourquoi
`/etc/shells` est la liste des shells considérés comme « de connexion » par le
système : `chsh` refuse ce qui n'y figure pas, et certains démons (FTP, SMTP)
s'en servent pour décider si un compte est légitime. Le motif awk `NR==FNR` est
l'idiome classique « charger le premier fichier dans un tableau, puis traiter le
second » ; le `-` final indique à awk de lire ensuite l'entrée standard.

L'intérêt opérationnel : tout compte **système** apparaissant dans cette liste est
une anomalie à justifier. C'est un des contrôles du Défi D4.
:::

---

**E4.4** — *Comptes à mot de passe vide ou à UID 0.*

```bash
sudo awk -F: '$2=="" {print "MOT DE PASSE VIDE : " $1}' /etc/shadow
awk -F: '$3==0 && $1!="root" {print "UID 0 : " $1}' /etc/passwd
```

::: pourquoi
Ce sont les deux compromissions les plus grossières, et les plus rapides à
vérifier. Un champ de mot de passe vide dans `/etc/shadow` autorise la connexion
sans aucune saisie (`pam_unix` avec l'option `nullok`, présente par défaut dans
`common-auth` sur Ubuntu). Un second compte d'UID 0 est un **root déguisé** : le
noyau ne raisonne que sur l'UID numérique, le nom n'a aucune importance. Un
attaquant qui ajoute `support:x:0:0::/root:/bin/bash` dans `/etc/passwd` obtient
un root complet qui n'apparaît dans aucune liste de membres du groupe `sudo`.
:::

::: piege
Ne pas oublier `getent shadow` sur une machine à annuaire, et ne pas confondre
« UID 0 » avec « membre de `sudo` » : le premier **est** root, le second peut le
devenir. Un audit sérieux vérifie les deux, plus les binaires SUID root (module 03).
:::

---

**E4.5** — *Créer `nadia` en une seule commande.*

```bash
sudo useradd -m -U -s /bin/bash -G factura,deploy \
     -c "Nadia Belkacem - SRE" nadia
```

::: pourquoi
`-m` crée le home **et** y copie `/etc/skel` ; sans lui, rien. `-U` force la
création d'un groupe éponyme comme groupe primaire (c'est déjà le défaut sur
Ubuntu grâce à `USERGROUPS_ENAB yes` dans `login.defs`, mais l'expliciter rend le
script portable vers des distributions où ce n'est pas le cas). `-G` pose les
secondaires — ici c'est une création, la liste est donc vide avant, et l'absence
de `-a` ne pose aucun problème. `-c` remplit le champ GECOS.
:::

::: piege
Le compte est créé **sans mot de passe utilisable** (`!` dans shadow) : `nadia` ne
peut pas encore se connecter. Il faut enchaîner `chpasswd` puis `chage -d 0`.
C'est un oubli fréquent qui se solde par un ticket « mon compte ne marche pas ».
:::

---

**E4.6** — *Ajouter `astreinte` sans perdre les autres groupes.*

```bash
id -nG nadia                      # avant
sudo usermod -aG astreinte nadia  # ou : sudo gpasswd -a nadia astreinte
id -nG nadia                      # après
```

::: pourquoi
`-a` (`--append`) est ce qui distingue l'ajout du remplacement. `gpasswd -a` est
encore plus sûr : il travaille **groupe par groupe** et est structurellement
incapable de retirer une autre appartenance. Dans un runbook destiné à des
opérateurs, c'est la forme à privilégier.
:::

---

**E4.7** — *Alias et `umask` pour les futurs comptes.*

```bash
sudo tee -a /etc/skel/.bashrc >/dev/null <<'EOF'

# --- politique interne ---
alias ll='ls -alF'
umask 027
EOF

sudo useradd -m -s /bin/bash jetable
grep -E 'umask|alias ll' /home/jetable/.bashrc
sudo userdel -r jetable
```

::: pourquoi
`/etc/skel` est un **squelette copié à la création** du home, uniquement avec
`-m`. Il n'y a aucun lien vivant : modifier `/etc/skel` après coup ne touche
aucun compte existant, et modifier le `.bashrc` d'un utilisateur ne remonte pas
dans skel. C'est un mécanisme de gabarit, pas de configuration centrale.

Pour agir sur **tous** les comptes, y compris existants, il faut le fichier
système : `/etc/bash.bashrc` (interactif) ou `/etc/profile.d/politique.sh`
(login). Et pour le `umask` en particulier, le bon endroit côté système est
`/etc/login.defs` (`UMASK 027`) ou `pam_umask`.
:::

::: piege
`userdel` sans `-r` laisse le home derrière lui, avec des fichiers appartenant à
un UID désormais libre : le prochain compte créé héritera silencieusement de ces
fichiers. `userdel -r` supprime le home et le spool mail ; on complète par
`find / -xdev -nouser` pour le reste.
:::

---

**E4.8** — *Compte de service `factura-api`.*

```bash
sudo groupadd --system factura-api
sudo useradd --system -g factura-api -M -d /nonexistent \
     -s /usr/sbin/nologin -c "API factura" factura-api
sudo usermod -p '*' factura-api          # mot de passe inutilisable

getent passwd factura-api
# factura-api:x:998:998:API factura:/nonexistent:/usr/sbin/nologin
sudo getent shadow factura-api | cut -d: -f2      # *
su - factura-api
# This account is currently not available.
```

::: pourquoi
Le message `This account is currently not available.` vient de `/usr/sbin/nologin`
lui-même : ce n'est pas une erreur de `su`, c'est le programme `nologin` qui
s'exécute, affiche le contenu de `/etc/nologin.txt` s'il existe, et sort en 1.
La session a donc bien été ouverte puis immédiatement refermée — d'où la nuance :
`nologin` empêche le **shell interactif**, pas l'existence du compte.

`usermod -p '*'` est préférable à `passwd -l` ici : `-l` poserait `!` devant un
hachage inexistant, tandis que `*` exprime clairement « ce compte n'a jamais
vocation à s'authentifier ». `-M` garantit qu'aucun home n'est créé, et
`/nonexistent` est la convention Debian pour le signaler.
:::

::: piege
`su -s /bin/bash - factura-api` contourne le shell `nologin` — mais seulement
depuis root, qui de toute façon peut tout. Le shell `nologin` protège contre une
connexion **entrante** (SSH, console), pas contre root. La protection qui manque
encore : `DenyUsers` côté SSH, ou plus simplement le fait qu'il n'y ait pas de
`~/.ssh/authorized_keys` puisqu'il n'y a pas de home.
:::

---

**E4.9** — *Politique de mot de passe pour `sophie`.*

```bash
sudo chage -M 90 -m 1 -W 14 -I 7 sophie
sudo chage -d 0 sophie
sudo chage -l sophie
```

::: pourquoi
Un seul `chage` suffit pour les quatre paramètres, mais `-d 0` se pose à part :
combiné aux autres dans la même commande, il fonctionne, mais on le sépare par
lisibilité — c'est une action ponctuelle (« force le changement maintenant »),
pas un paramètre de politique. Ordre important : si le compte n'a pas encore de
mot de passe, poser `-d 0` avant `chpasswd` sera annulé, car `chpasswd` réécrit le
champ 3 à la date du jour.
:::

---

**E4.10** — *Verrouiller, prouver, déverrouiller `pcontrat`.*

```bash
sudo passwd -l pcontrat
sudo passwd -S pcontrat                      # pcontrat L 2026-09-04 1 60 14 10
sudo getent shadow pcontrat | cut -d: -f2 | cut -c1-6   # !$6$rE
sudo passwd -u pcontrat
sudo passwd -S pcontrat                      # pcontrat P ...
```

Sur un compte sans mot de passe :

```console
$ sudo passwd -u nadia
passwd: unlocking the password would result in a passwordless account.
You should set a password with usermod -p to unlock the password of
this account.
```

::: pourquoi
Les deux preuves sont complémentaires : `passwd -S` donne l'interprétation
(`L`/`P`/`NP`), la lecture directe de `/etc/shadow` montre le **mécanisme** — le
`!` ajouté devant un hachage laissé intact. C'est ce qui rend l'opération
parfaitement réversible : `passwd -u` retire un caractère, le hachage d'origine
reprend du service.
:::

::: piege
`passwd -l` ne bloque **que** le mot de passe. Un compte verrouillé ainsi reste
accessible par clé SSH, par `sudo -u`, et ses tâches cron continuent de tourner.
Pour une suspension réelle : `chage -E 0` (bloque la session) + `pkill -u`
(tue les sessions en cours) + retrait des clés dans `~/.ssh/authorized_keys`.
:::

---

**E4.11** — *Quel algorithme de hachage ?*

```bash
echo 'sophie:MotDePasseTemporaire!42' | sudo chpasswd
sudo getent shadow sophie | cut -d: -f2 | cut -c1-4      # $y$j  -> yescrypt

echo 'sophie:MotDePasseTemporaire!42' | sudo chpasswd -c SHA512
sudo getent shadow sophie | cut -d: -f2 | cut -c1-4      # $6$D  -> SHA-512
```

::: pourquoi
Deux configurations pilotent ce choix, et elles ne s'appliquent pas aux mêmes
outils.

* Les changements qui passent par **PAM** (`passwd`, et `chpasswd` sur
  Debian/Ubuntu, compilé avec le support PAM) suivent
  `/etc/pam.d/common-password` : `password [success=1 default=ignore]
  pam_unix.so obscure yescrypt`. D'où `$y$` sur Ubuntu 24.04.
* Les outils qui hachent **eux-mêmes** (`chpasswd -c`, `useradd -p`, `newusers`)
  suivent `ENCRYPT_METHOD` dans `/etc/login.defs`, ou l'option `-c` qui la
  surcharge.

Yescrypt (`$y$`) est le défaut de Debian 12 et Ubuntu 24.04 : il est à coût
mémoire réglable, donc bien plus résistant au cassage sur GPU que SHA-512, qui
reste le défaut sur Rocky 9 (`$6$`). Les deux coexistent sans problème :
`libxcrypt` reconnaît le préfixe et choisit l'implémentation.
:::

::: piege
Conséquence concrète : un `/etc/shadow` copié d'une Rocky 9 vers une Ubuntu 24.04
continue de fonctionner (les `$6$` sont toujours vérifiables), mais le prochain
changement de mot de passe produira du `$y$`. Ne **jamais** copier `/etc/shadow`
entre machines pour « migrer des comptes » : les UID diffèrent, et on emporte au
passage les verrous et les dates d'expiration.
:::

---

**E4.12** — *Créer trois comptes depuis le CSV avec mots de passe aléatoires.*

```bash
mkdir -p ~/lab04/rapports
: > ~/lab04/rapports/motsdepasse.txt
chmod 600 ~/lab04/rapports/motsdepasse.txt

while IFS=';' read -r login gecos grp; do
    [ -n "$login" ] || continue
    getent passwd "$login" >/dev/null && continue
    sudo useradd -m -U -s /bin/bash -G "$grp" -c "$gecos" "$login"
    mdp=$(tr -dc 'A-Za-z0-9!@#%+=' </dev/urandom | head -c 16)
    echo "$login:$mdp" | sudo chpasswd
    sudo chage -d 0 "$login"
    printf '%s;%s\n' "$login" "$mdp" >> ~/lab04/rapports/motsdepasse.txt
done < ~/lab04/arrivees.csv
```

::: pourquoi
Quatre points méritent attention. `IFS=';' read -r a b c` découpe proprement le
CSV sans sous-shell ni `cut` répété — et `-r` empêche l'interprétation des `\`.
Le `getent passwd "$login" && continue` rend le script **idempotent** : relancé,
il saute les comptes existants au lieu d'échouer ou, pire, de réinitialiser leur
mot de passe. Le `chmod 600` est posé **avant** la première écriture, pas après :
sinon le fichier existe une fraction de seconde en `644`, et sur un système
multi-utilisateurs cette fraction suffit. Enfin l'ordre `chpasswd` puis
`chage -d 0` est impératif : l'inverse serait écrasé.
:::

::: piege
`tr -dc ... </dev/urandom | head -c 16` provoque un `SIGPIPE` sur `tr` quand
`head` a fini : sous `set -o pipefail`, le script échouerait. Dans un script
`set -euo pipefail`, encadre la génération (`mdp=$( ... ) || true`) ou utilise
`openssl rand -base64 16`.
:::

---

**E4.13** — *Autoriser `deploy` sur nginx, sur `lab-web` uniquement.*

```bash
sudo visudo -f /etc/sudoers.d/60-deploy
```

```text
Cmnd_Alias NGINX_OPS = /usr/bin/systemctl restart nginx, \
                       /usr/bin/systemctl status nginx

%deploy lab-web = (root) NOPASSWD: NGINX_OPS
```

```bash
sudo visudo -c                      # tous les fichiers, verdict par verdict
ls -l /etc/sudoers.d/60-deploy      # -r--r----- 1 root root
```

::: pourquoi
`visudo -f` fait trois choses qu'un `vim` direct ne fait pas : il pose un verrou
(deux admins ne peuvent pas éditer simultanément), il **valide la syntaxe avant
d'enregistrer** (et propose de ré-éditer en cas d'erreur), et il crée le fichier
avec le mode `0440 root:root` attendu. C'est le seul moyen sûr d'écrire dans
`/etc/sudoers.d/`.

Le champ hôte (`lab-web`) est comparé au nom d'hôte de la machine où `sudo`
s'exécute : le même fichier peut être déployé partout par Ansible, il ne
s'appliquera que sur `lab-web`. C'est ce qui rend `sudoers` distribuable.
:::

::: piege
Deux erreurs mortelles ici. D'abord le chemin : `systemctl` est en
`/usr/bin/systemctl` sur Ubuntu 24.04 (et `/bin/systemctl` est un lien) — une
règle écrite avec le mauvais chemin ne matche pas, `sudo` compare des chaînes
après résolution. Ensuite le nom du fichier : `60-deploy.conf` serait
**silencieusement ignoré**, car `sudo` écarte tout nom contenant un point.
:::

---

**E4.14** — *Ce que `karim` a le droit de faire.*

```bash
sudo -l -U karim
```

```console
Matching Defaults entries for karim on lab-web:
    env_reset, mail_badpass, secure_path=..., use_pty

User karim may run the following commands on lab-web:
    (root) NOPASSWD: /usr/bin/systemctl restart nginx
    (root) NOPASSWD: /usr/bin/systemctl status nginx
```

::: pourquoi
`sudo -l -U <user>` évalue les règles **telles que sudo les appliquerait** pour
cet utilisateur sur cet hôte : alias résolus, `Defaults` par utilisateur inclus,
fichiers de `sudoers.d` fusionnés dans l'ordre. C'est infiniment plus fiable que
lire les fichiers à la main, où l'on rate les priorités (la **dernière** règle
qui matche l'emporte) et les fichiers ignorés pour cause de nom ou de mode.

C'est aussi l'outil d'audit : dans une boucle sur tous les comptes humains, il
produit la cartographie complète des privilèges de la machine.
:::

---

**E4.15** — *Mot de passe à chaque commande + journal dédié.*

```bash
sudo visudo -f /etc/sudoers.d/10-politique
```

```text
Defaults  timestamp_timeout=0
Defaults  logfile=/var/log/sudo.log
Defaults  log_input, log_output
```

```bash
sudo ls /root
sudo tail -2 /var/log/sudo.log
# Sep 18 15:04:11 : karim : TTY=pts/1 ; PWD=/home/karim ; USER=root ;
#     COMMAND=/usr/bin/ls /root
```

::: pourquoi
`logfile` ajoute un journal **dédié** à `sudo`, en plus de ce qui part déjà dans
syslog (`/var/log/auth.log` sur Ubuntu, `journalctl _COMM=sudo`). Son intérêt :
il est plus facile à extraire et à conserver longtemps pour un audit, et il ne se
noie pas dans le reste des messages d'authentification.

`log_input`/`log_output` vont plus loin : ils enregistrent la **session complète**
(frappes et sortie) dans `/var/log/sudo-io/`, rejouable avec `sudoreplay`. À
réserver aux commandes sensibles (via un `Defaults!` ciblé sur un `Cmnd_Alias`),
car le volume grossit vite et les frappes peuvent contenir des secrets.
:::

::: piege
`timestamp_timeout=0` améliore la sécurité mais dégrade sérieusement le confort
sur une machine où l'on enchaîne les commandes. Le compromis courant : garder 15
minutes pour les admins, et `timestamp_timeout=0` uniquement pour les règles
sensibles via `Defaults!SENSIBLE timestamp_timeout=0`.
:::

---

**E4.16** — *Démontrer la faille de `NOPASSWD: /usr/bin/vim <fichier>`, puis corriger.*

```bash
sudo vim /etc/factura/factura.conf
# dans vim :
:!/bin/bash
# root@lab-adm:/home/karim# id
# uid=0(root) gid=0(root) groups=0(root)
```

Réécriture correcte :

```text
Defaults:%factura  editor=/usr/bin/vim, !env_editor
%factura ALL=(root) sudoedit /etc/factura/factura.conf
```

::: pourquoi
`sudoedit` (aussi écrit `sudo -e`) applique une mécanique complètement
différente : il **copie** le fichier dans un temporaire appartenant à
l'utilisateur, lance l'éditeur avec les privilèges **de l'utilisateur** (pas
root), puis recopie le résultat en place avec les privilèges root. L'éditeur ne
tourne jamais en root : un `:!sh` depuis cet éditeur donne un shell… sous
l'identité de l'utilisateur, donc sans intérêt pour l'attaquant.

`Defaults:%factura editor=... , !env_editor` est indispensable : sans lui, un
utilisateur peut positionner `SUDO_EDITOR=/bin/bash` et obtenir un shell root par
`sudoedit`. On fige l'éditeur et on interdit la lecture de la variable
d'environnement.
:::

::: piege
Dans `sudoers`, `sudoedit` s'écrit **sans chemin absolu** — c'est une
pseudo-commande interne de sudo, pas un binaire à résoudre. Écrire
`/usr/bin/sudoedit` dans la règle ne fonctionne pas comme attendu. Et restreindre
les arguments de `vim` (`/usr/bin/vim /etc/factura/factura.conf`) ne protège de
rien : le problème n'est pas le fichier ouvert, c'est que vim tourne en root.
:::

---

**E4.17** — *Limites `nofile` et `nproc` pour le groupe `factura`.*

```bash
sudo tee /etc/security/limits.d/50-factura.conf >/dev/null <<'EOF'
@factura  soft  nofile  4096
@factura  hard  nofile  8192
@factura  soft  nproc   200
@factura  hard  nproc   200
EOF

sudo su - sophie -c 'ulimit -Sn; ulimit -Hn; ulimit -u'
# 4096
# 8192
# 200
```

::: pourquoi
`limits.conf` (et les fichiers de `limits.d/`) est lu par **`pam_limits.so`**, qui
appelle `setrlimit()` sur le processus de session. D'où deux conséquences
essentielles :

* la limite ne s'applique qu'aux sessions **ouvertes après** la modification :
  les processus existants gardent les leurs (`cat /proc/<pid>/limits` le montre) ;
* elle ne s'applique qu'aux services dont la pile PAM appelle `pam_limits` — sur
  Debian/Ubuntu, c'est `login`, `sshd`, `su` et `sudo`, **pas** `common-session`.
  Un service lancé par **systemd** ignore complètement `limits.conf` : sa limite
  se pose avec `LimitNOFILE=` dans l'unité.

`soft` est la valeur courante (l'utilisateur peut la monter jusqu'au `hard`),
`hard` est le plafond absolu que seul root peut relever.
:::

::: piege
Le grand classique : « j'ai mis `nofile 65536` dans `limits.conf` et PostgreSQL
ouvre toujours 1024 descripteurs ». Normal — PostgreSQL est démarré par systemd,
qui n'utilise pas PAM. Il faut
`systemctl edit postgresql@16-main.service` et `LimitNOFILE=65536`.
:::

---

**E4.18** — *Source de résolution du compte `sophie`.*

```bash
grep ^passwd /etc/nsswitch.conf      # passwd: files systemd
getent passwd sophie                 # la ligne, quelle que soit la source
grep ^sophie: /etc/passwd            # présent -> compte local
```

::: pourquoi
La comparaison des deux dernières commandes **est** la réponse : si `getent`
répond et que le fichier ne contient rien, l'identité vient d'une autre source
NSS (`systemd` pour les utilisateurs dynamiques, `sss` pour un annuaire). Sur
`lab-adm`, `passwd: files systemd` signifie « fichiers locaux, puis utilisateurs
dynamiques créés par systemd (`DynamicUser=yes`) » : `sophie` est bien locale.
:::

---

## 4.6 Labs

### **L4.1** — *Créer trois comptes d'arrivants avec politique et skel.*

**Étape 1 — squelette**

```bash
sudo tee /etc/skel/BIENVENUE.txt >/dev/null <<EOF
Bienvenue sur $(hostname -f).
Support : support@lab.local — extension 4242.
Ton mot de passe doit être changé à la première connexion.
EOF

sudo tee -a /etc/skel/.bashrc >/dev/null <<'EOF'

# --- politique interne ---
umask 027
EOF
```

Vérification que les comptes existants ne bougent pas :

```bash
ls /home/sophie/BIENVENUE.txt   # No such file or directory : c'est normal
```

**Étape 2 — valeurs par défaut de la machine**

```bash
sudo sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t90/;
             s/^PASS_MIN_DAYS.*/PASS_MIN_DAYS\t1/;
             s/^PASS_WARN_AGE.*/PASS_WARN_AGE\t14/' /etc/login.defs
grep -E '^PASS_(MAX|MIN|WARN)' /etc/login.defs
```

**Étape 3 à 5 — le script**

```bash
#!/usr/bin/env bash
# creer-arrivants.sh — crée les comptes listés dans arrivees.csv
set -euo pipefail

CSV="${1:-$HOME/lab04/arrivees.csv}"
RAP="$HOME/lab04/rapports/motsdepasse.txt"

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
[ -r "$CSV" ]        || { echo "CSV illisible : $CSV" >&2; exit 1; }

install -d -m 700 "$(dirname "$RAP")"
touch "$RAP"; chmod 600 "$RAP"

while IFS=';' read -r login gecos grp; do
    [ -n "${login:-}" ] || continue
    case "$login" in \#*) continue ;; esac

    if getent passwd "$login" >/dev/null; then
        echo "  = $login existe déjà, ignoré" >&2
        continue
    fi

    getent group "$grp" >/dev/null || groupadd "$grp"

    useradd -m -U -s /bin/bash -G "$grp" -c "$gecos" "$login"

    mdp=$(tr -dc 'A-Za-z0-9!@#%+=' </dev/urandom | head -c 16) || true
    printf '%s:%s\n' "$login" "$mdp" | chpasswd
    chage -M 90 -m 1 -W 14 -d 0 "$login"

    printf '%s;%s\n' "$login" "$mdp" >> "$RAP"
    echo "  + $login créé (groupes : $(id -nG "$login" | tr ' ' ','))" >&2
done < "$CSV"

chmod 600 "$RAP"
echo "Mots de passe : $RAP (à transmettre hors bande, puis à détruire)" >&2
```

**Étape 6 — vérification**

```bash
sudo chage -l lucie | head -5
sudo getent shadow lucie | cut -d: -f3      # 0
id -nG hugo                                  # hugo factura
ls -l ~/lab04/rapports/motsdepasse.txt       # -rw------- 1 mathieu mathieu
sudo bash check_M04_01.sh
```

::: pourquoi
Le cœur pédagogique du lab est l'**ordre des opérations**. `useradd -m` copie skel
— donc skel doit être prêt **avant**. `chpasswd` réécrit le champ 3 de shadow à la
date du jour — donc `chage -d 0` doit venir **après**. Et `chage -M 90` posé
explicitement plutôt que compté sur `login.defs` : `login.defs` n'est lu que par
`useradd`, et seulement pour `PASS_MAX_DAYS`/`PASS_MIN_DAYS`/`PASS_WARN_AGE` au
moment de la création — poser la politique explicitement rend le script
indépendant de l'état de la machine.

L'idempotence se joue sur une seule ligne, le `getent passwd && continue`. Sans
elle, une relance réinitialiserait les mots de passe de comptes déjà en service :
c'est le genre de script qui fait tomber une équipe entière un lundi matin.
:::

::: piege
Le fichier de mots de passe est le point faible du lab. Trois règles : créé en
`600` **avant** d'écrire, jamais dans un répertoire partagé, détruit après
transmission (`shred -u`). La bonne pratique au-delà de l'exercice est de ne pas
générer de mot de passe du tout — on crée le compte verrouillé, et l'utilisateur
l'active par un lien à usage unique ou dépose sa clé SSH.
:::

---

### **L4.2** — *Remettre en conformité le compte de service `facturasvc`.*

**Étape 1 — constat**

```bash
{
  echo "== $(date -Is) — état de facturasvc"
  getent passwd facturasvc
  id facturasvc
  sudo passwd -S facturasvc
  sudo chage -l facturasvc
  ls -ld "$(getent passwd facturasvc | cut -d: -f6)"
} | tee ~/lab04/rapports/facturasvc-avant.txt
```

**Étape 2 — les trois vecteurs**

1. Shell `/bin/bash` + mot de passe défini : une fuite du mot de passe (wiki !)
   donne une **session interactive** par SSH ou console.
2. Appartenance au groupe `sudo` : cette session devient root en une commande.
3. Home dans `/home/facturasvc`, inscriptible par le service : l'application
   compromise peut y déposer `.ssh/authorized_keys` (persistance) ou un
   `.bashrc` piégé.

**Étape 3 — ce qui se corrige à chaud**

```bash
pgrep -a -u facturasvc                   # le service tourne : on le note

sudo usermod -s /usr/sbin/nologin facturasvc
sudo gpasswd -d facturasvc sudo
sudo usermod -p '*' facturasvc           # ni ! ni hachage : inutilisable
sudo chage -E -1 -M 99999 facturasvc     # un compte de service n'expire pas
```

Ces quatre opérations n'écrivent que dans `/etc/passwd`, `/etc/shadow` et
`/etc/group` : aucun processus n'est concerné, le service continue.

**Étape 4 — le refus, et la fenêtre d'interruption**

```console
$ sudo usermod -u 103 facturasvc
usermod: user facturasvc is currently used by process 21916
$ sudo usermod -d /var/lib/facturasvc facturasvc
usermod: user facturasvc is currently used by process 21916
```

`usermod` refuse de changer l'UID, le home ou le nom d'un compte qui a des
processus vivants. Il n'existe **aucune option pour forcer** : il faut donc une
fenêtre d'arrêt. La séquence qui la réduit au minimum consiste à tout préparer
avant, et à n'arrêter le service que pour les trois commandes qui l'exigent.

```bash
# --- préparation (service toujours en marche) ---
ancien=$(id -u facturasvc)
# un identifiant libre à la fois côté passwd ET côté group :
nouveau=$( { getent passwd | cut -d: -f3; getent group | cut -d: -f3; } | \
           sort -n -u | awk 'BEGIN{n=100} {if($1==n) n++} END{print n}')
sudo install -d -o facturasvc -g facturasvc -m 750 /var/lib/facturasvc
sudo rsync -a /home/facturasvc/ /var/lib/facturasvc/ 2>/dev/null || true

# --- début de la fenêtre d'interruption ---
sudo systemctl stop factura      # ou : sudo pkill -u facturasvc
sudo usermod -u "$nouveau" facturasvc
sudo groupmod -g "$nouveau" facturasvc
sudo usermod -d /var/lib/facturasvc facturasvc
sudo find / -xdev -uid "$ancien"  -exec chown facturasvc {} +
sudo find / -xdev -gid "$ancien"  -exec chgrp facturasvc {} +
sudo systemctl start factura
# --- fin de la fenêtre : quelques secondes ---

sudo rm -rf /home/facturasvc
```

**Étape 5 à 7 — preuves**

```bash
su - facturasvc                    # This account is currently not available.
sudo su -s /bin/bash - facturasvc  # possible depuis root : voir plus bas
sudo find / -xdev \( -nouser -o -nogroup \)    # aucune sortie
pgrep -a -u facturasvc             # le service est reparti
id facturasvc                      # uid < 1000
sudo bash check_M04_02.sh
```

::: pourquoi
Le point qui fait la valeur de ce lab, c'est le **changement d'UID**. `usermod -u`
modifie l'entrée dans `/etc/passwd` et réécrit la propriété des fichiers situés
**sous le home** du compte — rien d'autre. Tous les fichiers ailleurs
(`/opt/factura`, `/var/log/factura`, `/srv`) restent associés à l'**ancien
numéro**, qui n'est plus attribué à personne : `ls -l` affiche alors le nombre brut
au lieu d'un nom, et `find -nouser` les remonte. Pire : si un futur compte reçoit
cet UID libéré, il héritera silencieusement de tous ces fichiers. La séquence
« noter l'ancien UID → changer → `find -uid <ancien> -exec chown` » est le geste
obligatoire, et c'est exactement ce qu'on fait lors d'une migration vers un
annuaire où les UID changent.

Détail qui coûte cinq minutes si on le découvre en pleine fenêtre d'arrêt : le
numéro choisi doit être libre **dans `/etc/passwd` et dans `/etc/group`**. Prendre
le premier UID libre sans vérifier les GID donne
`groupmod: GID '103' already exists`, et on se retrouve avec un compte dont l'UID
et le GID divergent — ce qui fonctionne, mais brouille toutes les lectures
ultérieures de `ls -l`.

Deuxième mécanisme : `usermod -p '*'` plutôt que `passwd -l`. `passwd -l` poserait
`!` **devant le hachage existant** — le mot de passe du wiki resterait stocké, et
un `passwd -u` malencontreux le réactiverait. `-p '*'` l'écrase définitivement.
:::

::: piege
`su -s /bin/bash - facturasvc` fonctionne toujours **depuis root** : c'est normal
et ce n'est pas une faille. Root peut tout, y compris ignorer le shell déclaré.
Le shell `nologin` protège contre une connexion entrante et contre un `su` depuis
un compte non privilégié. Confondre les deux mène à des « durcissements »
inutiles.

Deuxième piège : croire qu'on peut tout faire à chaud. `usermod` **refuse**
(`user facturasvc is currently used by process NNNN`) de toucher à l'UID, au
home ou au nom d'un compte dont un processus tourne, et il n'y a pas d'option
`--force`. Même si on contournait en éditant `/etc/passwd` à la main, les
processus vivants garderaient l'ancien UID dans leurs credentials et perdraient
l'accès à leurs fichiers juste après le `chown`. La fenêtre d'arrêt n'est pas une
faiblesse de la procédure : c'est la procédure.
:::

---

### **L4.3** — *Déléguer l'exploitation de nginx sans donner root.*

**Étapes 1 et 2 — groupe et règle**

```bash
sudo groupadd -f deploy
sudo gpasswd -a karim deploy          # sûr : ne touche pas ses autres groupes
sudo visudo -f /etc/sudoers.d/60-deploy
```

```text
# --- qui ---
User_Alias  EXPLOIT     = %deploy
Host_Alias  FRONTAUX    = lab-web

# --- quoi ---
Cmnd_Alias  NGINX_CTL   = /usr/bin/systemctl restart nginx, \
                          /usr/bin/systemctl reload  nginx, \
                          /usr/bin/systemctl status  nginx
Cmnd_Alias  NGINX_TEST  = /usr/sbin/nginx -t
Cmnd_Alias  NGINX_LOGS  = /usr/bin/journalctl -u nginx --no-pager, \
                          /usr/bin/cat /var/log/nginx/error.log, \
                          /usr/bin/cat /var/log/nginx/access.log

# --- comment ---
Defaults:EXPLOIT  timestamp_timeout=5, logfile=/var/log/sudo.log
Defaults!NGINX_CTL  !env_keep

EXPLOIT FRONTAUX = (root) NOPASSWD: NGINX_CTL, NGINX_TEST
EXPLOIT FRONTAUX = (root) PASSWD:   NGINX_LOGS
```

```bash
sudo visudo -c
sudo -l -U karim
```

**Étape 4 — l'évasion, et sa fermeture**

```console
$ sudo less /var/log/nginx/error.log     # si on l'avait autorisé
!/bin/bash
root@lab-web:/#                          <- shell root : règle inacceptable
```

`cat` n'a pas d'échappement shell : c'est le bon outil ici. `journalctl` en a un
(son pager), neutralisé par `--no-pager` **inscrit dans la règle** — l'utilisateur
ne peut pas l'omettre, puisque `sudoers` compare la ligne de commande complète.
`systemctl status` pagine aussi : `sudo` le lance sans terminal de contrôle
interactif grâce à `use_pty`, et on peut verrouiller davantage avec
`Defaults:EXPLOIT env_keep -= "SYSTEMD_PAGER PAGER"`.

**Étape 5 — traçabilité**

```bash
sudo touch /var/log/sudo.log && sudo chmod 600 /var/log/sudo.log
sudo -u karim -i -- sudo systemctl restart nginx     # simulation
sudo tail -3 /var/log/sudo.log
# Sep 18 16:22:04 : karim : TTY=pts/2 ; PWD=/home/karim ; USER=root ;
#     COMMAND=/usr/bin/systemctl restart nginx
```

**Étape 6 — la commande refusée**

```console
$ sudo systemctl restart ssh
Sorry, user karim is not allowed to execute '/usr/bin/systemctl restart ssh'
as root on lab-web.
```

```bash
sudo grep karim /var/log/auth.log | tail -2
# sudo: karim : command not allowed ; TTY=pts/2 ; PWD=/home/karim ;
#     USER=root ; COMMAND=/usr/bin/systemctl restart ssh
```

::: pourquoi
Trois mécanismes se combinent dans cette règle.

`sudoers` fait une comparaison **textuelle** de la ligne de commande après
résolution du chemin : `/usr/bin/systemctl restart nginx` n'autorise **que** cette
chaîne exacte, avec ces arguments-là. Ajouter `ssh` derrière ne matche plus.
C'est aussi pourquoi le chemin absolu est obligatoire : sans lui, il n'y aurait
rien à comparer de fiable.

Les **alias** ne changent rien à la sécurité, ils changent la maintenabilité :
`Cmnd_Alias NGINX_CTL` se relit en six mois, et ajouter un hôte au `Host_Alias`
propage la règle sans la dupliquer. Le champ hôte permet de déployer le **même**
fichier sur toutes les machines par Ansible.

`NOPASSWD` et `PASSWD` se posent **par bloc de commandes**, pas par utilisateur :
on peut donc exiger une authentification pour lire des journaux (qui contiennent
des données) tout en dispensant du mot de passe le redémarrage de service (qui
doit pouvoir se faire depuis un script d'astreinte).
:::

::: piege
Le piège central : **tout outil qui pagine ou qui édite est une porte de sortie**.
`less`, `more`, `man`, `vim`, `systemctl` sans `--no-pager`, `journalctl` sans
`--no-pager`, `git`, `tail -f` (pas d'échappement, celui-là, mais il maintient un
processus root vivant). Le réflexe : pour chaque binaire qu'on s'apprête à
autoriser, se demander « peut-il lancer un processus fils ? », et vérifier sur
GTFOBins.

Second piège : `%deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart *`.
Le joker paraît pratique — il autorise en réalité
`systemctl restart ssh`, `systemctl restart --user ...`, et tout
`systemctl restart` d'une unité que l'utilisateur pourrait créer. Jamais de `*`
dans une commande `sudoers`.
:::

---

### **L4.4** — *Durcir l'authentification de `lab-adm`.*

**1 — Qualité des mots de passe**

```bash
sudo apt install -y libpam-pwquality
sudo tee /etc/security/pwquality.conf >/dev/null <<'EOF'
minlen = 12
minclass = 3
maxrepeat = 3
usercheck = 1
enforcing = 1
EOF
```

`/etc/pam.d/common-password`, ligne ajoutée **avant** `pam_unix` :

```text
password requisite pam_pwquality.so retry=3
password required  pam_pwhistory.so remember=3 use_authtok
password [success=1 default=ignore] pam_unix.so obscure yescrypt use_authtok
```

Démonstration :

```console
$ sudo passwd sophie
New password: sophie2026
BAD PASSWORD: The password contains the user name in some form
```

**2 — Verrouillage après échecs**

`/etc/pam.d/common-auth` :

```text
auth  required  pam_faillock.so preauth silent deny=5 unlock_time=900
auth  [success=1 default=ignore]  pam_unix.so nullok
auth  [default=die]  pam_faillock.so authfail deny=5 unlock_time=900
auth  sufficient  pam_faillock.so authsucc
auth  requisite  pam_deny.so
auth  required   pam_permit.so
```

`/etc/pam.d/common-account` :

```text
account  required  pam_faillock.so
```

Root est protégé par l'absence de l'option `even_deny_root` (comportement par
défaut : root n'est pas verrouillé).

La démonstration doit se faire **depuis un compte non privilégié** : un `su`
lancé par root ne traverse pas la pile `auth`, donc il n'incrémente aucun
compteur.

```console
mathieu@lab-adm:~$ for i in 1 2 3 4 5; do su - pcontrat; done
Password:
su: Authentication failure
...
mathieu@lab-adm:~$ su - pcontrat        # 6e tentative, avec le BON mot de passe
Password:
su: Authentication failure               <- verrouillé, pas "mot de passe faux"

mathieu@lab-adm:~$ sudo faillock --user pcontrat
pcontrat:
When                Type  Source   Valid
2026-09-18 19:16:17 SVC   su-l         V
2026-09-18 19:16:20 SVC   su-l         V
2026-09-18 19:16:24 SVC   su-l         V
2026-09-18 19:16:26 SVC   su-l         V
2026-09-18 19:16:30 SVC   su-l         V

mathieu@lab-adm:~$ sudo faillock --user pcontrat --reset
mathieu@lab-adm:~$ su - pcontrat         # ça repasse immédiatement
Password:
pcontrat@lab-adm:~$
```

**3 — Expiration des comptes existants**

```bash
umin=$(awk '$1=="UID_MIN"{print $2}' /etc/login.defs)
getent passwd | awk -F: -v m="$umin" '$3>=m && $3!=65534 {print $1}' |
while read -r u; do
    case "$(getent passwd "$u" | cut -d: -f7)" in
        */nologin|*/false) continue ;;      # comptes de service : on saute
    esac
    sudo chage -M 90 -W 14 -I 7 "$u"
    echo "  politique appliquée à $u"
done
```

**4 — Limites de ressources**

```bash
sudo tee /etc/security/limits.d/50-factura.conf >/dev/null <<'EOF'
@factura  soft  nproc   200
@factura  hard  nproc   200
@factura  soft  nofile  4096
@factura  hard  nofile  8192
EOF
sudo su - sophie -c 'ulimit -Sn; ulimit -Hn; ulimit -u'
```

**5 — Rapport**

`~/lab04/rapports/politique-auth.md`, une section par point, chacune avec :
fichier modifié, ligne exacte, commande de preuve, sortie obtenue.

```bash
sudo bash check_M04_04.sh
```

::: pourquoi
Chaque exigence tombe dans une pile PAM différente, et c'est le fil conducteur du
lab. La qualité du mot de passe se juge **au moment du changement** → pile
`password`, et `pam_pwquality` doit précéder `pam_unix`, sinon le mot de passe
serait déjà haché et écrit. L'option `use_authtok` sur `pam_unix` lui dit
d'utiliser le mot de passe déjà validé par le module précédent au lieu de le
redemander.

Le verrouillage après échecs se joue **au moment de l'authentification** → pile
`auth`, en trois temps : `preauth` (vérifier le compteur avant), `authfail`
(incrémenter après un échec), `authsucc` (remettre à zéro après un succès). La
ligne `account required pam_faillock.so` complète le dispositif en refusant la
session d'un compte verrouillé même si l'authentification vient d'ailleurs.

Les limites de ressources se posent **une fois la session accordée** → pile
`session`, via `pam_limits`.

Et l'expiration, elle, n'est pas du PAM du tout : c'est de la donnée dans
`/etc/shadow`, que `pam_unix` consulte en phase `account`. D'où la boucle `chage`
plutôt qu'une ligne de configuration — `login.defs` ne s'applique qu'aux comptes
**créés ensuite**.
:::

::: piege
Le danger réel de ce lab est l'ordre des lignes dans `common-auth`. Une pile PAM
mal ordonnée ne renvoie pas d'erreur de syntaxe : elle **laisse passer** ou
**bloque tout**, y compris ta prochaine connexion SSH. Deux protections :

1. garder une session root ouverte pendant toute la manipulation, et tester la
   connexion dans un **second** terminal avant de fermer le premier ;
2. sauvegarder (`cp -a /etc/pam.d /root/pam.d.bak`) avant de toucher quoi que ce
   soit.

Piège secondaire : `enforcing = 1` dans `pwquality.conf` ne s'applique **pas à
root**. Un `sudo passwd sophie` avec un mot de passe faible affiche
`BAD PASSWORD:` puis… demande confirmation et accepte. Pour tester réellement la
politique, il faut changer le mot de passe **en tant que l'utilisateur**.
:::

---

## 4.7 Break & Fix

### **BF4.1** — *`sudo: /etc/sudoers is world writable`.*

**Cause racine :** le mode de `/etc/sudoers` a été changé (typiquement par un
`chmod 777` ou par une édition avec `cp`/`mv` d'un fichier venu d'ailleurs).
`sudo` **refuse de lire** un fichier de politique modifiable par n'importe qui :
c'est une protection élémentaire, puisqu'un fichier world-writable permettrait à
tout utilisateur de s'accorder root. Ce n'est donc **pas** une erreur de syntaxe —
le contenu du fichier est parfaitement valide.

**Diagnostic pas à pas :**

```bash
# 1. lire le message en entier, il nomme le fichier et la raison
sudo id
# sudo: /etc/sudoers is world writable
# sudo: error initializing audit plugin sudoers_audit

# 2. depuis la session root encore ouverte (ou après récupération) :
ls -l /etc/sudoers /etc/sudoers.d/
# -rwxrwxrwx 1 root root 1671 Sep 18 16:40 /etc/sudoers   <- le coupable

# 3. confirmer que le contenu, lui, est sain
visudo -c
```

**Correctif :**

```bash
chown root:root /etc/sudoers
chmod 0440 /etc/sudoers
chmod 0440 /etc/sudoers.d/*
visudo -c
sudo -l -U mathieu        # la politique est de nouveau lue
```

**Procédure de récupération sans session privilégiée** — c'est le vrai sujet de ce
Break & Fix. Deux voies, par ordre de préférence :

1. **Polkit**, si `policykit-1` est installé et que le compte est administrateur :

   ```bash
   pkexec chmod 0440 /etc/sudoers
   ```

   `pkexec` n'utilise **pas** `sudoers` : il s'appuie sur polkit, donc il survit
   à une politique sudo cassée.

2. **Console Proxmox + mode de récupération**, qui marche toujours :

   * `qm terminal 9001` ou la console noVNC de l'interface Proxmox ;
   * redémarrer la VM, maintenir `Shift` (ou `Esc`) au démarrage pour afficher
     GRUB ;
   * *Advanced options for Ubuntu* → une entrée `(recovery mode)` ;
   * menu de récupération → **root** (« Drop to root shell prompt ») ;
   * le système de fichiers est monté en lecture seule :
     `mount -o remount,rw /` ;
   * `chmod 0440 /etc/sudoers`, `visudo -c`, puis `reboot`.

   Variante si le menu de récupération est absent : éditer la ligne `linux` de
   GRUB (touche `e`), ajouter `init=/bin/bash` à la fin, `Ctrl-X`, puis
   `mount -o remount,rw /` et corriger.

::: pourquoi
Le message d'erreur dit exactement ce qui se passe, à condition de le lire jusqu'au
bout. `sudo` valide, **avant** d'appliquer la moindre règle : le propriétaire
(`root`), le groupe, et surtout l'absence du bit `w` pour `other`. Si l'un des
contrôles échoue, le plugin `sudoers` ne se charge pas — d'où la seconde ligne,
`error initializing audit plugin sudoers_audit`, qui n'est pas un problème
supplémentaire mais la conséquence du premier refus.

Détail que peu de gens connaissent et qui change la façon de diagnostiquer :
depuis sudo 1.9.15, une **erreur de syntaxe** dans un fichier `sudoers` n'empêche
plus le reste de fonctionner. sudo affiche l'erreur, ignore la ligne fautive et
applique les autres. Autrement dit, un `NOPASWD` mal orthographié ne casse pas
`sudo` : il **retire silencieusement** un privilège. C'est plus insidieux qu'une
panne franche, et c'est pourquoi `visudo -c` doit tourner dans la CI qui déploie
vos fichiers `sudoers.d`.
:::

::: piege
Trois erreurs à éviter pendant la réparation :

* `chmod 644` : mieux que `777`, mais pas conforme. Le mode attendu est `0440`
  (`0400` fonctionne aussi). `sudo` tolère que le groupe lise, pas qu'il écrive.
* réparer `/etc/sudoers` en oubliant `/etc/sudoers.d/` : le même contrôle
  s'applique à chaque fichier inclus.
* éditer `/etc/sudoers` avec `vim` en mode de récupération : possible, mais on
  perd le filet de `visudo`. Utilise `visudo`, ou à défaut `visudo -c` juste
  après.

**Prévention** : ne jamais toucher `/etc/sudoers` autrement qu'avec `visudo` ;
déployer les règles par fichiers dans `/etc/sudoers.d/` avec un mode explicite
(Ansible : `mode: '0440'`, `validate: 'visudo -cf %s'`) ; et garder sur chaque
machine un accès de secours qui ne dépend pas de sudo (console, polkit).
:::

---

### **BF4.2** — *`karim` ne peut plus ouvrir de session.*

**Cause racine :** trois blocages **cumulés**, chacun à un endroit différent —
c'est tout l'intérêt de la panne. Corriger le premier ne suffit pas, et c'est le
piège dans lequel tombe une réparation pressée.

1. mot de passe **verrouillé** : `!` en tête du champ 2 de `/etc/shadow` ;
2. compte **expiré** : champ 8 de `/etc/shadow` positionné à une date passée ;
3. shell de connexion remplacé par `/usr/sbin/nologin` : champ 7 de `/etc/passwd`.

**Diagnostic pas à pas :**

```bash
# 1. le compte existe-t-il toujours, et avec quel shell ?
getent passwd karim
# karim:x:1002:1002:Karim Aziz:/home/karim:/usr/sbin/nologin
#                                           ^^^^^^^^^^^^^^^^ blocage 3

# 2. état du mot de passe
sudo passwd -S karim
# karim L 2026-09-18 1 90 14 7          <- L = Locked, blocage 1

# 3. dates
sudo chage -l karim
# Account expires : Sep 01, 2026        <- passée, blocage 2

# 4. la lecture brute confirme tout en une ligne
sudo getent shadow karim
# karim:!$y$j9T$...:20714:1:90:14:7:20693:

# 5. et le journal donne le motif exact vu par PAM
sudo tail -20 /var/log/auth.log | grep karim
# sshd: User karim not allowed because account is locked
# su: pam_unix(su:account): account karim has expired (account expired)
```

**Le message change à chaque couche levée** — c'est le fil d'Ariane du
diagnostic :

| État | `su - karim` depuis root |
|---|---|
| expiration + verrou + nologin | `su: Authentication failure` |
| après `chage -E -1` | `This account is currently not available.` |
| après `usermod -s /bin/bash` | la session s'ouvre |

Le verrou du mot de passe, lui, ne se voit **pas** depuis root : `su` lancé par
root saute la phase `auth`. Il ne se manifeste que pour l'utilisateur, en SSH.

**Correctif, blocage par blocage :**

```bash
sudo usermod -s /bin/bash karim          # champ 7 de /etc/passwd
sudo passwd -u karim                     # retire le ! du champ 2 de shadow
sudo chage -E -1 karim                   # champ 8 : plus d'expiration
sudo chage -M 90 -W 14 -I 7 karim        # conformité à la politique

# vérification finale
sudo passwd -S karim                     # karim P 2026-09-18 1 90 14 7
sudo chage -l karim | grep -i 'account expires'   # never
su - karim -c 'id'                       # une session s'ouvre
```

::: pourquoi
Les trois blocages agissent à trois étapes distinctes de l'ouverture de session,
ce qui explique les messages différents selon la méthode de connexion :

* le **verrou du mot de passe** (`!`) est un échec de la phase `auth` : en SSH par
  mot de passe on obtient `Permission denied, please try again.`, mais une
  connexion par **clé SSH** passerait quand même — d'où l'importance de tester les
  deux ;
* l'**expiration du compte** est un refus de la phase `account` : elle bloque
  toutes les méthodes d'authentification, clé comprise ;
* le **shell `nologin`** n'est pas un refus du tout : l'authentification réussit,
  la session s'ouvre, puis le programme `/usr/sbin/nologin` s'exécute, affiche
  `This account is currently not available.` et sort. C'est pour cela que,
  **une fois l'expiration levée**, `su - karim` donne ce message précis depuis
  root, alors que root n'a jamais eu à s'authentifier.

Savoir **lire les symptômes à l'envers** est la vraie compétence : le message
`This account is currently not available.` désigne le shell, `Permission denied`
désigne l'authentification, et `Your account has expired` désigne le champ 8.
:::

::: piege
Piège numéro un : s'arrêter au premier blocage trouvé. Un `passwd -u` seul
« répare » le symptôme visible et laisse deux verrous en place ; l'utilisateur
rappelle une heure plus tard. Déroule **toute** la liste de QO4.6 avant de
déclarer résolu.

Piège numéro deux : `passwd -u` échoue avec
`unlocking the password would result in a passwordless account` si le compte n'a
jamais eu de mot de passe. Dans ce cas, poser un mot de passe (`passwd karim`)
plutôt que forcer avec `-f`, qui créerait un compte sans mot de passe.

Piège numéro trois : `chage -E 0` et `chage -E -1` sont à une lettre l'un de
l'autre et font l'inverse. `-1` = plus jamais d'expiration, `0` = expiré depuis
le 1ᵉʳ janvier 1970.

**Prévention** : automatiser les suspensions (un seul script qui fait les trois
gestes et les journalise) et les réactivations, plutôt que des commandes tapées à
la main dont on oublie la moitié.
:::

---

### **BF4.3** — *`karim` a perdu tous ses groupes.*

**Cause racine :** la commande `usermod -G docker karim` a été utilisée à la
place de `usermod -aG docker karim`. Sans `-a`, `-G` **remplace** l'intégralité
des groupes secondaires : `sudo`, `deploy` et `factura` ont été écrasés d'un coup.

**Diagnostic pas à pas :**

```bash
# 1. état actuel
id -nG karim
# karim docker

# 2. le fichier confirme : karim n'est plus membre de rien d'autre
getent group | grep -E ':.*\bkarim\b'
# docker:x:988:karim

# 3. retrouver l'état d'avant — /etc/group- est la sauvegarde automatique
#    écrite par les outils shadow avant chaque modification
sudo grep karim /etc/group-
# sudo:x:27:mathieu,karim
# factura:x:1002:karim
# deploy:x:1003:karim

# 4. corroborer avec les traces : qui a fait quoi, et quand
sudo grep -E 'usermod|groupmod' /var/log/auth.log | tail -5
# usermod[2841]: change user 'karim' groups from
#                'sudo,deploy,factura' to 'docker'
```

**Correctif :**

```bash
sudo usermod -aG sudo,deploy,factura karim     # -a : on AJOUTE
id -nG karim
# karim docker sudo deploy factura
sudo -l -U karim                                # les règles reviennent
```

**Règle d'équipe (une phrase) :** « Pour ajouter quelqu'un à un groupe, on
utilise `gpasswd -a <user> <groupe>` ; `usermod -G` est interdit dans les
runbooks. »

::: pourquoi
Trois mécanismes se rencontrent dans cette panne.

D'abord la sémantique de `-G` : c'est une **affectation**, pas un ajout. Les
outils shadow sont anciens et cohérents avec leur époque — `usermod` reflète
l'idée « voici la liste complète des groupes de cet utilisateur ». `-a` a été
ajouté plus tard pour le cas courant. `gpasswd -a` est immunisé par construction :
il ne manipule qu'un seul groupe à la fois.

Ensuite la **source fiable de reconstruction** : les outils shadow (`usermod`,
`groupadd`, `passwd`…) écrivent systématiquement une copie de l'ancien fichier
avant modification, avec un tiret final — `/etc/group-`, `/etc/passwd-`,
`/etc/shadow-`, `/etc/gshadow-`. C'est un filet de sécurité que peu de gens
connaissent et qui sauve exactement ce genre de situation. Ces fichiers ne
contiennent que **l'état immédiatement précédent** : une deuxième modification
les écrase, d'où l'urgence de les consulter.

Enfin la **persistance de la session** : `karim` continuait de travailler
normalement parce que ses groupes étaient figés dans les credentials de son
processus depuis son login (voir Q4.4). Le noyau ne relit jamais `/etc/group`.
Ses droits ne se sont écroulés qu'à sa reconnexion suivante — décalage temporel
qui brouille le diagnostic, puisque l'incident semble sans rapport avec une
commande tapée une heure plus tôt.
:::

::: piege
Piège de réparation : recréer les appartenances **de mémoire**. On oublie
toujours un groupe, et le manque ne se voit que des semaines plus tard sur un
partage précis. Les sources fiables, par ordre : `/etc/group-`, le journal
(`auth.log`, qui trace le `change user groups from ... to ...`), la sauvegarde de
configuration, le playbook Ansible qui gère les comptes.

Piège aggravant : si tu t'appliques la commande à **toi-même** et que tu sors du
groupe `sudo`, tu ne peux plus rien réparer. Récupération identique à BF4.1 :
console + mode de récupération, ou `pkexec`.

**Prévention** : gérer les appartenances en infrastructure-as-code (module
Ansible `ansible.builtin.user` avec `append: yes`), ce qui rend l'état
reproductible et l'écart détectable.
:::

---

## 4.8 Défi du module

**D4 — Audit des comptes et des délégations**

Une implémentation possible de `~/lab04/bin/audit-comptes.sh` :

```bash
#!/usr/bin/env bash
# audit-comptes.sh — inventaire des identités et privilèges (lecture seule)
set -euo pipefail

ECARTS=0
log()    { printf '[audit] %s\n' "$*" >&2; }
ecart()  { printf '* **%s**\n' "$*"; ECARTS=$((ECARTS+1)); }

UID_MIN=$(awk '$1=="UID_MIN"{print $2}' /etc/login.defs)
: "${UID_MIN:=1000}"
AUJ=$(( $(date +%s) / 86400 ))

HOTE=$(hostname -f 2>/dev/null || hostname)
printf '# Audit des comptes — %s — %s\n\n' "$HOTE" "$(date -Is)"

# ---------------------------------------------------------------- humains
printf '## Comptes humains (UID >= %s)\n\n' "$UID_MIN"
printf '| Login | UID | Groupes | Shell | Mdp |\n|---|---|---|---|---|\n'
while IFS=: read -r u _ uid _ _ _ sh; do
    [ "$uid" -ge "$UID_MIN" ] && [ "$uid" -ne 65534 ] || continue
    etat=$(passwd -S "$u" 2>/dev/null | awk '{print $2}')
    printf '| %s | %s | %s | %s | %s |\n' \
           "$u" "$uid" "$(id -nG "$u" | tr ' ' ',')" "$sh" "${etat:-?}"
done < <(getent passwd)

# ------------------------------------------------- comptes système à shell
printf '\n## Comptes système avec un shell de connexion\n\n'
while IFS=: read -r u _ uid _ _ _ sh; do
    [ "$uid" -lt "$UID_MIN" ] && [ "$uid" -ne 0 ] || continue
    grep -qxF "$sh" <(grep -v '^#' /etc/shells) || continue
    printf -- '- %s (UID %s, %s)\n' "$u" "$uid" "$sh"
done < <(getent passwd)

# --------------------------------------------------------- administrateurs
printf '\n## Groupes d administration\n\n'
for g in sudo wheel adm; do
    getent group "$g" >/dev/null || continue
    printf -- '- %s : %s\n' "$g" "$(getent group "$g" | cut -d: -f4)"
done

# ------------------------------------------------------------ règles sudo
printf '\n## Règles sudo\n\n```text\n'
for f in /etc/sudoers /etc/sudoers.d/*; do
    [ -f "$f" ] || continue
    printf -- '--- %s (%s %s)\n' "$f" \
           "$(stat -c '%a' "$f")" "$(stat -c '%U:%G' "$f")"
    grep -vE '^\s*(#|$)' "$f" || true
done
printf '```\n'

# ------------------------------------------------------------------ écarts
printf '\n## Écarts\n\n'

awk -F: '$3==0 && $1!="root" {print $1}' /etc/passwd |
    while read -r u; do ecart "UID 0 non-root : $u"; done

awk -F: '$2=="" {print $1}' /etc/shadow 2>/dev/null |
    while read -r u; do ecart "mot de passe vide : $u"; done

while IFS=: read -r u _ uid _ _ _ sh; do
    if [ "$uid" -ge "$UID_MIN" ] && [ "$uid" -ne 65534 ]; then
        max=$(getent shadow "$u" | cut -d: -f5)
        [ "${max:-99999}" -ge 99999 ] && ecart "mdp sans expiration : $u"
        lst=$(getent shadow "$u" | cut -d: -f3)
        if [ -n "${lst:-}" ] && [ "$lst" -gt 0 ] \
           && [ $(( AUJ - lst )) -gt 90 ]; then
            ecart "mdp inchangé depuis $(( AUJ - lst )) jours : $u"
        fi
    elif [ "$uid" -ne 0 ] && grep -qxF "$sh" <(grep -v '^#' /etc/shells)
    then
        ecart "compte de service avec shell de connexion : $u ($sh)"
    fi
done < <(getent passwd)

for f in /etc/sudoers.d/*; do
    [ -f "$f" ] || continue
    [ "$(stat -c '%a' "$f")" = "440" ] || ecart "mode != 0440 : $f"
    [ "$(stat -c '%U' "$f")" = "root" ] || ecart "propriétaire != root : $f"
done

DANGER='vim|vi|nano|less|more|find|awk|sed|tar|python3|perl|bash|sh'
for f in /etc/sudoers /etc/sudoers.d/*; do
    [ -f "$f" ] || continue
    grep -vE '^\s*(#|$)' "$f" | grep -q 'NOPASSWD:[[:space:]]*ALL' && \
        ecart "NOPASSWD: ALL dans $f"
    grep -vE '^\s*(#|$)' "$f" | grep -qE '=.*/[^ ]*\*' && \
        ecart "joker dans un chemin de commande : $f"
    grep -vE '^\s*(#|Defaults|$)' "$f" | grep -qE "/($DANGER)( |,|$)" && \
        ecart "binaire à échappement shell délégué : $f"
done

[ "$ECARTS" -eq 0 ] && printf 'Aucun écart.\n'
log "$ECARTS écart(s)"
[ "$ECARTS" -eq 0 ]
```

Usage et remédiation :

```bash
chmod +x ~/lab04/bin/audit-comptes.sh
sudo ~/lab04/bin/audit-comptes.sh > ~/lab04/rapports/audit-lab-adm.md
echo $?      # 1 tant qu'il reste des écarts
```

L'anomalie plantée par le setup est dans `/etc/sudoers.d/50-legacy` :

```text
%factura ALL=(ALL) NOPASSWD: /usr/bin/vim /opt/factura/etc/factura.conf
```

Remédiation qui **répond au besoin** (éditer la configuration) sans donner root :

```bash
sudo visudo -f /etc/sudoers.d/50-legacy
```

```text
Defaults:%factura  editor=/usr/bin/vim, !env_editor
%factura ALL=(root) sudoedit /opt/factura/etc/factura.conf
```

::: pourquoi
Trois techniques de script méritent d'être relevées.

`while ... done < <(getent passwd)` — la **substitution de processus** — plutôt
que `getent passwd | while ...`. Dans un pipeline, bash exécute la boucle dans un
sous-shell : la variable `ECARTS` incrémentée dedans serait perdue à la sortie.
C'est le bug classique des scripts de comptage. La substitution de processus
garde la boucle dans le shell courant.

La séparation **stdout / stderr** : le rapport Markdown part sur stdout, toute la
trace de diagnostic sur stderr via `log()`. C'est ce qui rend
`audit-comptes.sh > rapport.md` propre, et permet de voir la progression à
l'écran pendant que le fichier se remplit.

Le calcul de l'âge du mot de passe : `$(( $(date +%s) / 86400 ))` convertit
l'heure courante dans la même unité que le champ 3 de `/etc/shadow` (jours depuis
l'epoch). Comparer les deux donne l'âge en jours sans manipulation de dates.

Enfin le script est **strictement en lecture seule**. Un outil d'audit qui
corrige est un outil qu'on n'ose pas lancer en production ; la remédiation est
une décision humaine, tracée séparément.
:::

::: piege
Deux limites à connaître et à assumer dans le rapport :

* la détection des binaires dangereux par `grep` est **heuristique**. Elle rate
  les alias (`Cmnd_Alias EDITEURS = /usr/bin/vim`) et les scripts maison qui
  appellent eux-mêmes un interpréteur. Le vrai contrôle est la revue humaine de
  la sortie de `sudo -l -U <user>` pour chaque compte.
* `getent shadow` n'est lisible que par root : lancé sans `sudo`, le script
  produit un rapport incomplet **sans le dire**. Une version finalisée doit
  vérifier `id -u` en tête et refuser de tourner autrement, plutôt que de rendre
  un rapport faussement rassurant.
:::
