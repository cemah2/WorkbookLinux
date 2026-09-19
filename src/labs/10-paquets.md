# Module 10 — Gestion des paquets et des dépôts

## 10.0 Objectifs et compétences

::: objectif
À la fin de ce module, je sais :

* situer chaque couche de la chaîne Debian (`dpkg`, `apt-get`, `apt`, `aptitude`)
  et dire laquelle résout les dépendances, laquelle télécharge, laquelle déballe ;
* distinguer `upgrade`, `full-upgrade` et `dist-upgrade`, et prédire quand une
  mise à jour va supprimer un paquet ;
* interroger la base locale (`dpkg -l/-L/-S/-s`, `dpkg -V`) pour répondre à
  « d'où vient ce fichier ? » et « qui a modifié cette conf ? » sans accès réseau ;
* réparer une base dpkg laissée en état incohérent (`iU`, `iF`, `rc`,
  `dpkg --configure -a`) sans réinstaller la machine ;
* déclarer un dépôt tiers proprement : format deb822, clé dans
  `/etc/apt/keyrings`, `Signed-By`, et expliquer pourquoi `apt-key` est mort ;
* écrire un épinglage (`/etc/apt/preferences.d`) qui vise ce qu'il doit viser,
  lire `apt-cache policy` et diagnostiquer un épinglage qui déborde ;
* piloter le prompt de conffile de dpkg (`--force-confold`, `--force-confdef`,
  `.dpkg-dist`, `.dpkg-old`) et régler `unattended-upgrades` pour un serveur ;
* faire la même chose sous RHEL/Rocky : `dnf`, `rpm -q*`, `dnf history` et son
  `undo`, modules et flux, `/etc/yum.repos.d`, EPEL, `dnf-automatic` ;
* compiler depuis les sources sans polluer le système, et savoir dire quand
  c'est légitime et quand c'est une faute professionnelle ;
* arbitrer entre paquet distribution, snap/flatpak, `pip`/`npm`, et justifier
  pourquoi on n'installe pas en global sur un serveur.

Temps estimé : 6 h
Prérequis : modules 01 à 03 (shell, FHS, permissions). Le module 08 aide pour
la partie `systemd` du défi, mais n'est pas indispensable.
:::

---

## 10.1 Mise en place

VM principales : **`lab-adm` (10.10.10.10)** pour toute la partie Debian/Ubuntu,
**`lab-rhel` (10.10.10.13)** pour L10.5 et les blocs `::: rhel`.

```bash
# depuis le shell Proxmox, avant de commencer
qm snapshot 9001 avant-lab10
qm snapshot 9004 avant-lab10
```

Paquets nécessaires sur `lab-adm` :

```bash
sudo apt update
sudo apt install -y dpkg-dev gnupg build-essential aptitude apt-file \
     unattended-upgrades apt-transport-https ca-certificates python3
sudo apt-file update
```

::: rhel
Sur `lab-rhel` (Rocky 9) :

```bash
sudo dnf install -y rpm-build rpm-sign createrepo_c gnupg2 \
     dnf-automatic dnf-utils gcc make python3
```

`dnf-utils` fournit `repoquery`, `needs-restarting` et `package-cleanup`.
EPEL n'est **pas** requis pour le module : on l'installera en L10.5 pour
comprendre ce qu'un dépôt tiers change.
:::

Préparation du terrain (idempotent, à lancer sur **chacune** des deux VM) :

```bash
sudo bash ~/workbook/scripts/setup/setup_M10.sh
```

Il fabrique une paire de clés GPG « Depot Lab Interne », construit quatre
paquets locaux, publie un dépôt signé dans `/srv/depot-lab` (servi aussi en
HTTP sur le port 8099) et dépose une archive de sources à compiler dans
`~/lab10/sources/`.

Ce qu'il ne fait **pas**, et qui est ton travail : déclarer le dépôt, installer
la clé, écrire le moindre épinglage.

::: attention
Ce module écrit dans `/etc/apt`, `/etc/yum.repos.d`, `/usr/local` et la base
dpkg. Les Break & Fix cassent volontairement l'installation de paquets. Prends
les snapshots ci-dessus : sur une machine où `apt` ne fonctionne plus, on ne
répare pas avec `apt`.
:::

---

## 10.2 Rappel express

### Les quatre couches, et qui fait quoi

```text
aptitude          résolveur alternatif + interface texte, propose des
                  solutions quand apt se bloque
   |
apt / apt-get     dépôts, téléchargement, résolution de dépendances,
                  ordre des opérations ; ne déballe rien lui-même
   |
dpkg              déballe, configure, tient la base /var/lib/dpkg ;
                  ne sait PAS résoudre une dépendance, il constate
   |
.deb              ar(1) : debian-binary + control.tar.* + data.tar.*
```

`apt` (2014) est la surface *humaine* : couleurs, barre de progression, sortie
qui change entre versions. `apt-get`/`apt-cache` ont une interface **stable**,
garantie scriptable. En script, `apt-get` ; au clavier, `apt`. `apt` le dit
lui-même dans un pipe : `WARNING: apt does not have a stable CLI interface.`

### apt au quotidien

| Commande | Ce qu'elle fait vraiment |
|---|---|
| `apt update` | rafraîchit les **index**, n'installe rien |
| `apt upgrade` | met à jour, **n'enlève jamais** un paquet installé |
| `apt full-upgrade` | met à jour, **et supprime** si c'est le seul chemin |
| `apt dist-upgrade` | synonyme de `full-upgrade` côté `apt-get` |
| `apt install p=1.2` | version précise ; `-t noble-backports` pour une suite |
| `apt remove` / `purge` | retire les fichiers / retire **aussi** les conffiles |
| `apt autoremove` | retire les dépendances automatiques devenues orphelines |
| `apt-mark hold/unhold` | pose/retire un marqueur dpkg de gel |
| `apt list --upgradable` | ce qui monterait ; `--installed`, `--all-versions` |
| `apt download p` | récupère le `.deb` sans l'installer |

`upgrade` vs `full-upgrade` : la règle est « ai-je le droit de supprimer ? ».
Une montée de version de bibliothèque qui change de nom de paquet
(`libfoo5` → `libfoo6`) exige une suppression : `upgrade` la refuse et laisse le
paquet **kept back**, `full-upgrade` l'accepte. Sur un serveur, `upgrade` est le
comportement voulu par défaut ; `full-upgrade` se fait les yeux ouverts.

### dpkg, la couche du dessous

| Commande | Usage |
|---|---|
| `dpkg -i fichier.deb` | installe un fichier, **sans** résoudre les dépendances |
| `dpkg -l [motif]` | liste + colonnes d'état |
| `dpkg -L paquet` | fichiers **livrés** par un paquet installé |
| `dpkg -S /chemin` | quel paquet fournit ce fichier **déjà installé** |
| `dpkg -s paquet` | fiche complète : état, dépendances, conffiles |
| `dpkg -V [paquet]` | vérifie les empreintes des fichiers livrés |
| `dpkg --configure -a` | reprend toutes les configurations en attente |
| `dpkg-query -W -f '...'` | la forme scriptable, à préférer à `dpkg -l` |

Les trois caractères de `dpkg -l` : **désiré** / **état** / **erreur**.

```text
ii   installé, tout va bien
iU   désiré installé, déballé mais PAS configuré  -> dpkg --configure -a
iF   désiré installé, configuration à moitié faite (postinst en échec)
rc   supprimé, conffiles conservés                -> dpkg --purge pour finir
iH   retenu (hold)
```

`/var/lib/dpkg/status` **est** la base : un fichier texte. `status-old` en est
la copie précédente, `/var/lib/dpkg/info/*.list` liste les fichiers de chaque
paquet, `/var/lib/dpkg/updates/` contient le journal d'une transaction en cours.
Un fichier numérique laissé là suffit à faire dire à apt :
`E: dpkg was interrupted, you must manually run 'dpkg --configure -a' to correct the problem.`

### Sources : deb822, le format d'Ubuntu 24.04

Depuis 24.04, `/etc/apt/sources.list` ne contient plus qu'un commentaire ; tout
est dans `/etc/apt/sources.list.d/ubuntu.sources` :

```ini
Types: deb
URIs: https://archive.ubuntu.com/ubuntu/
Suites: noble noble-updates noble-backports
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
```

| Élément | Sens |
|---|---|
| `main` | supporté par Canonical, libre |
| `universe` | communautaire (support étendu avec Ubuntu Pro) |
| `restricted` | non libre, supporté (pilotes, micrologiciels) |
| `multiverse` | non libre, non supporté |
| `noble-security` | correctifs de sécurité, **URI séparée** |
| `noble-updates` | correctifs de bogues post-release |
| `noble-backports` | versions récentes rétroportées, priorité 100 |

Les deux écritures sont équivalentes ; deb822 permet plusieurs URI, plusieurs
suites et un `Signed-By` lisible :

```text
deb [signed-by=/etc/apt/keyrings/docker.asc] \
    https://download.docker.com/linux/ubuntu noble stable
```

### Clés de dépôt : la seule méthode correcte

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
```

puis `Signed-By: /etc/apt/keyrings/docker.gpg` dans la source.

`apt-key add` est **supprimé** depuis Ubuntu 22.04 (`Command apt-key is
deprecated`), pour une raison de fond : une clé posée dans le trousseau global
(`/etc/apt/trusted.gpg`, `/etc/apt/trusted.gpg.d/`) authentifie **tous** les
dépôts de la machine. La clé de Docker pouvait signer un faux `libc6`.
`Signed-By` restreint une clé à un dépôt : c'est le principe du moindre privilège
appliqué à la distribution logicielle.

### Épinglage

```ini
# /etc/apt/preferences.d/50-nginx.pref
Package: nginx nginx-common
Pin: release o=nginx,c=stable
Pin-Priority: 600
```

| Priorité | Effet |
|---|---|
| `< 0` | jamais installé |
| `1` | installé seulement si rien d'autre, jamais en mise à jour |
| `100` | version installée ; suites `-backports` |
| `500` | défaut d'un dépôt actif |
| `990` | défaut de la suite ciblée par `-t` / `APT::Default-Release` |
| `> 1000` | autorise la **rétrogradation** |

Formes de `Pin:` : `version 1.2.*`, `release a=noble-security`,
`release o=Docker`, `origin download.docker.com` (le nom d'hôte, pas `o=`).
`apt-cache policy` sans argument liste les priorités réelles, dépôt par dépôt :
c'est la commande qui tranche.

### Fichiers de configuration pendant une mise à jour

Un **conffile** est un fichier déclaré par le paquet (`dpkg -s p` → `Conffiles:`).
Si tu l'as modifié et que le mainteneur en livre une nouvelle version, dpkg
demande :

```text
Configuration file '/etc/outil-lab/outil.conf'
 ==> Modified (by you or by a script) since installation.
 ==> Package distributor has shipped an updated version.
   What would you like to do about it ?  Your options are:
    Y or I  : install the package maintainer's version
    N or O  : keep your currently-installed version
      D     : show the differences between the versions
      Z     : start a shell to examine the situation
 The default action is to keep your current version.
*** outil.conf (Y/I/N/O/D/Z) [default=N] ?
```

| Réponse / option | Résultat sur disque |
|---|---|
| `N` (défaut) | ton fichier reste ; le neuf est écrit en `.dpkg-dist` |
| `Y` | le neuf s'installe ; le tien part en `.dpkg-old` |
| `--force-confold` | force `N` sans poser la question |
| `--force-confnew` | force `Y` sans poser la question |
| `--force-confdef` | accepte le défaut *quand il y en a un* |

La combinaison de production est `--force-confdef --force-confold` : on ne
casse jamais une conf locale sans décision humaine, et on relit les `.dpkg-dist`
après coup. `ucf` (Update Configuration File) fait le même travail pour des
fichiers **générés** par les scripts du mainteneur, avec ses propres sauvegardes
dans `/var/lib/ucf/`.

```bash
sudo find /etc -name '*.dpkg-dist' -o -name '*.dpkg-old' -o -name '*.ucf-dist'
```

### RHEL / Rocky : le même problème, d'autres outils

| Debian | RHEL/Rocky | Remarque |
|---|---|---|
| `dpkg -i` | `rpm -i` / `rpm -U` | `-U` met à jour ou installe |
| `dpkg -l` | `rpm -qa` | |
| `dpkg -L` | `rpm -ql` | |
| `dpkg -S` | `rpm -qf` | |
| `dpkg -s` | `rpm -qi` | |
| `dpkg -V` | `rpm -V` | mêmes colonnes `S.5....T.` |
| `apt update` | (implicite) | dnf rafraîchit selon `metadata_expire` |
| `apt upgrade` | `dnf upgrade` | pas d'équivalent de `kept back` |
| `apt-cache policy` | `dnf repoquery --info` | |
| `apt-mark hold` | `dnf versionlock` | paquet `python3-dnf-plugin-versionlock` |
| — | `dnf history undo` | **aucun équivalent Debian** |

`dnf history` est la vraie différence culturelle : chaque transaction est
numérotée, consultable (`dnf history info 42`) et annulable
(`dnf history undo 42`, `dnf history rollback 41`). C'est l'argument qu'on
oppose en entretien à « Debian ou RHEL, c'est pareil ».

Sortie de `rpm -V` : neuf colonnes, `.` = conforme.

```text
S.5....T.  c /etc/httpd/conf/httpd.conf
| |    |   `- type : c = conffile, d = doc, (vide) = fichier normal
| |    `----- T : mtime
| `---------- 5 : somme MD5 du contenu
`------------ S : taille
```

**Modules et flux** (dnf 4, RHEL 8/9) : plusieurs versions majeures d'un même
logiciel cohabitent dans le dépôt.

```bash
dnf module list nodejs
sudo dnf module enable nodejs:20
sudo dnf module reset nodejs        # annule le choix de flux
```

Un flux activé masque les autres : c'est la cause n°1 des
`No match for argument: nodejs` incompréhensibles sur RHEL 8/9.

### Langages, snap, alternatives

```bash
update-alternatives --display editor      # état d'un groupe
sudo update-alternatives --config editor  # choix interactif
sudo update-alternatives --set editor /usr/bin/vim.basic
```

`pip install` en root casse les paquets système : sur Ubuntu 24.04, `pip` refuse
désormais d'écrire hors environnement virtuel
(`error: externally-managed-environment`). Les trois réponses correctes sont
`apt install python3-<lib>` si le paquet existe, `python3 -m venv` pour une
application, `pipx` pour un outil en ligne de commande. Idem côté Node :
`npm install -g` sur un serveur partagé est une dette, pas une installation.

---

## 10.3 Quiz — QCM

**Q10.1** — Sur `lab-web`, `sudo apt upgrade` affiche :

```text
The following packages have been kept back:
  linux-generic linux-headers-generic
```

Que s'est-il passé ?

a) les paquets sont retenus par `apt-mark hold`
b) leur mise à jour exigerait d'installer ou de supprimer d'autres paquets, ce
   qu'`upgrade` s'interdit
c) le dépôt `noble-updates` est injoignable
d) leur signature GPG n'a pas pu être vérifiée

**Q10.2** — Quelle est la différence réelle entre `apt-get dist-upgrade` et
`apt full-upgrade` sur Ubuntu 24.04 ?

a) `dist-upgrade` change de version d'Ubuntu, `full-upgrade` non
b) aucune : ce sont deux noms de la même opération
c) `full-upgrade` supprime les paquets orphelins, `dist-upgrade` non
d) `dist-upgrade` ignore l'épinglage

**Q10.3** — `dpkg -l nginx` affiche :

```text
||/ Name   Version           Architecture Description
+++-======-=================-============-===================
rc  nginx  1.24.0-2ubuntu7.1 amd64        small, powerful...
```

Que signifie `rc` et que reste-t-il sur le disque ?

a) le paquet est installé mais cassé ; tous ses fichiers sont là
b) le paquet est supprimé, mais ses fichiers de configuration sont conservés
c) le paquet est en attente de reconfiguration ; il faut `dpkg-reconfigure`
d) le paquet est retenu (`hold`) et ne sera plus mis à jour

**Q10.4** — Tu veux savoir quel paquet fournit `/usr/sbin/nginx` sur une machine
où **nginx n'est pas installé**. Quelle commande ?

a) `dpkg -S /usr/sbin/nginx`
b) `dpkg -L nginx`
c) `apt-file search /usr/sbin/nginx`
d) `apt show nginx`

**Q10.5** — Sur un serveur, `sudo apt update` se termine par :

```text
W: GPG error: https://apt.exemple.fr noble InRelease: The following
   signatures couldn't be verified because the public key is not
   available: NO_PUBKEY 7EA0A9C3F273FCD8
E: The repository 'https://apt.exemple.fr noble InRelease' is not signed.
```

Quelle est la bonne conduite ? **Deux réponses correctes.**

a) ajouter `[trusted=yes]` à la ligne du dépôt
b) récupérer la clé publique du dépôt auprès de l'éditeur, la placer dans
   `/etc/apt/keyrings/` et la référencer avec `signed-by=`
c) vérifier l'empreinte de la clé obtenue avant de l'installer
d) lancer `sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 7EA0A9C3F273FCD8`

**Q10.6** — Pourquoi la méthode `apt-key add` a-t-elle été abandonnée ?

a) parce que GPG ne sait plus lire les clés RSA
b) parce qu'une clé ajoutée ainsi vaut pour **tous** les dépôts de la machine
c) parce que le trousseau global n'est pas sauvegardé
d) parce qu'`apt-key` ne fonctionne pas derrière un proxy

**Q10.7** — `apt-cache policy outil-lab` répond :

```text
outil-lab:
  Installed: 1.2.0
  Candidate: 1.0.0
  Version table:
 *** 1.2.0 100
        100 /var/lib/dpkg/status
     1.0.0 1001
        500 file:/srv/depot-lab ./ Packages
```

Que va faire `sudo apt install outil-lab` ?

a) rien, le paquet est déjà installé dans une version plus récente
b) rétrograder le paquet en 1.0.0
c) échouer avec `E: Version '1.0.0' for 'outil-lab' was not found`
d) installer 1.2.0 depuis le dépôt

**Q10.8** — Un `/etc/apt/preferences.d/00-socle.pref` contient :

```ini
Package: *
Pin: release a=noble
Pin-Priority: 1001
```

Quelle est la conséquence sur `sudo apt upgrade` ?

a) aucune, c'est la configuration par défaut
b) apt propose de rétrograder tout ce qui a été installé depuis
   `noble-updates` ou `noble-security`
c) apt refuse de démarrer avec `E: Malformed preferences file`
d) seules les mises à jour de sécurité sont retenues

**Q10.9** — `apt install` d'un paquet applicatif propose de supprimer 40 paquets,
dont `ubuntu-server`. Quelle est la cause la plus probable ?

a) le disque est plein
b) un conflit de dépendances avec un dépôt tiers qui fournit une bibliothèque
   système dans une version incompatible
c) la base dpkg est corrompue
d) `autoremove` a été lancé dans la même transaction

**Q10.10** — Pendant une mise à jour, dpkg affiche le prompt de conffile pour
`/etc/ssh/sshd_config`. Tu réponds `N`. Que trouve-t-on ensuite sur le disque ?

a) `/etc/ssh/sshd_config` (ta version) et `/etc/ssh/sshd_config.dpkg-dist`
   (celle du paquet)
b) `/etc/ssh/sshd_config` (celle du paquet) et `/etc/ssh/sshd_config.dpkg-old`
c) uniquement ta version, la nouvelle est perdue
d) `/etc/ssh/sshd_config.ucf-dist`

**Q10.11** — Dans un playbook de mise à jour non interactive d'un parc de
serveurs, quelle option passes-tu à dpkg ? **Deux réponses correctes.**

a) `--force-confnew`
b) `--force-confold`
c) `--force-confdef`
d) `--force-all`

**Q10.12** — `sudo apt install tree` répond immédiatement :

```text
E: dpkg was interrupted, you must manually run 'dpkg --configure -a' to
   correct the problem.
```

Quelle affirmation est exacte ?

a) apt a détecté un paquet en état `iU` ou une transaction dpkg non terminée,
   et refuse de lancer une nouvelle transaction par-dessus
b) le verrou `/var/lib/dpkg/lock` est tenu par un autre processus
c) l'index des paquets est trop ancien, il faut `apt update`
d) le disque est plein

**Q10.13** — Sur Rocky 9, tu as installé un paquet hier et l'application est
tombée depuis. Quelle séquence te permet de revenir en arrière ?

a) `dnf downgrade <paquet>` uniquement
b) `dnf history list`, puis `dnf history undo <id>`
c) `rpm -e --rollback yesterday`
d) `dnf clean all && dnf reinstall <paquet>`

**Q10.14** — `rpm -V httpd` affiche :

```text
S.5....T.  c /etc/httpd/conf/httpd.conf
missing     /var/log/httpd/error_log
```

Comment interprètes-tu ces deux lignes ?

a) le paquet est corrompu, il faut le réinstaller
b) la configuration a été modifiée (taille, MD5, mtime), ce qui est normal ; le
   journal a disparu, ce qui l'est aussi (logrotate)
c) une intrusion a modifié les binaires
d) `rpm -V` compare au dépôt, il faut donc être connecté

**Q10.15** — Sur Rocky 9, `sudo dnf install nodejs` installe la version 16 alors
que le dépôt AppStream contient aussi la 20. Pourquoi ?

a) la 20 est dans EPEL, pas dans AppStream
b) un flux de module (`nodejs:16`) est activé et masque les autres
c) `dnf` installe toujours la plus ancienne version disponible
d) il manque `--allowerasing`

**Q10.16** — Un développeur te demande d'installer un outil en faisant
`sudo ./configure && sudo make && sudo make install` dans `/usr` sur le serveur
de production. Quelles objections sont fondées ? **Trois réponses correctes.**

a) rien ne trace les fichiers déposés : `dpkg -S` ne les retrouvera jamais
b) une mise à jour du paquet distribution écrasera ou entrera en conflit avec
   ces fichiers
c) `make install` ne fonctionne pas en root
d) la désinstallation dépend d'une cible `uninstall` que rien n'oblige le
   projet à fournir

**Q10.17** — Sur Ubuntu 24.04, `sudo pip install requests` répond
`error: externally-managed-environment`. Quelle est la bonne réponse ?

a) ajouter `--break-system-packages`
b) installer `python3-requests` avec apt, ou travailler dans un venv, ou passer
   par `pipx` pour un outil
c) supprimer `/usr/lib/python3.12/EXTERNALLY-MANAGED`
d) lancer la commande sans `sudo`

**Q10.18** — Tu dois garantir qu'un déploiement fait aujourd'hui et le même
déploiement refait dans six mois installent **exactement** les mêmes versions.
Quelles mesures y contribuent réellement ? **Trois réponses correctes.**

a) épingler les versions exactes des paquets applicatifs dans
   `/etc/apt/preferences.d`
b) figer le dépôt : miroir local daté, ou snapshot type `snapshot.ubuntu.com`
c) ajouter `apt upgrade -y` au démarrage de la machine
d) enregistrer la sortie de `dpkg-query -W -f '${Package}=${Version}\n'` comme
   manifeste du déploiement

---

## 10.4 Quiz — questions ouvertes

**QO10.1** — Décris la chaîne complète de ce qui se passe entre le moment où tu
tapes `sudo apt install nginx` et le moment où le service tourne : qui lit quoi,
qui télécharge, qui vérifie la signature, qui déballe, qui configure, et où
chaque étape laisse une trace sur le disque.

::: repondre
lignes: 12
:::

**QO10.2** — *On te demande en entretien* : « Quelle est la différence entre
`apt upgrade` et `apt full-upgrade` ? Laquelle mets-tu dans le cron d'un serveur
de production, et pourquoi ? » Réponds en cinq phrases maximum, avec un exemple
concret de ce que `full-upgrade` accepterait et qu'`upgrade` refuse.

::: repondre
lignes: 8
:::

**QO10.3** — *On te demande en entretien* : « Explique-moi pourquoi on ne fait
plus `apt-key add`, et montre-moi comment tu ajoutes le dépôt Docker
correctement sur Ubuntu 24.04. » Donne les commandes exactes et dis ce que tu
vérifies avant de faire confiance à la clé.

::: repondre
lignes: 10
:::

**QO10.4** — Un collègue a écrit ceci pour empêcher une montée de version de
PostgreSQL :

```ini
Package: *
Pin: version 16*
Pin-Priority: 1001
```

Explique, mécanisme à l'appui, ce que ce fichier fait réellement au système,
comment tu le détectes, et comment tu l'écrirais.

::: repondre
lignes: 8
:::

**QO10.5** — Compare `apt-mark hold` et un épinglage dans
`/etc/apt/preferences.d` : où chaque information est stockée, ce que chacun
empêche exactement, ce que chacun laisse passer, et lequel survit à une
réinstallation du paquet. Conclus par le critère de choix.

::: repondre
lignes: 10
:::

**QO10.6** — Sur un parc de 200 serveurs, décris ta politique de mise à jour :
ce que tu automatises, ce que tu n'automatises jamais, comment tu traites le
redémarrage, et comment tu sais, le lendemain matin, ce qui a bougé sur quelle
machine.

::: repondre
lignes: 12
:::

**QO10.7** — Un dev te dit : « ton paquet Debian de `redis` est trop vieux, je
compile la version amont et je fais `make install` ». Formule ta réponse
professionnelle : dans quels cas il a raison, dans quels cas c'est une faute, et
quelle solution intermédiaire tu proposes.

::: repondre
lignes: 10
:::

**QO10.8** — Décris ta démarche de diagnostic, commande par commande, face à ce
symptôme : « depuis ce matin, `apt install` n'importe quoi propose de supprimer
`ubuntu-server` et 40 autres paquets ». Dis ce que tu cherches dans chaque
sortie.

::: repondre
lignes: 10
:::

**QO10.9** — Explique ce qu'apporte `dnf history` par rapport à l'écosystème
Debian, ce que son `undo` sait faire et ce qu'il **ne sait pas** faire, et
comment tu obtiens une garantie équivalente sur une machine Ubuntu.

::: repondre
lignes: 8
:::

---

## 10.5 Exercices guidés ★

**E10.1** — Affiche le nombre exact de paquets installés sur `lab-adm`, sans
compter les lignes d'en-tête ni les paquets en état `rc`.

**E10.2** — Trouve quel paquet fournit le fichier `/usr/bin/ss`, puis liste tous
les fichiers de configuration (sous `/etc`) que ce paquet livre.

**E10.3** — Le binaire `/usr/sbin/nft` n'existe pas sur la machine. Trouve quand
même le nom du paquet qui le fournirait.

**E10.4** — Affiche la liste des paquets que **tu** as demandés explicitement,
par opposition à ceux tirés comme dépendances. Compte les deux populations.

**E10.5** — Liste les paquets dont l'état n'est pas `ii`, en une seule commande
scriptable (pas de `dpkg -l` suivi de `grep -v` sur l'affichage humain).

**E10.6** — Trouve tous les fichiers de `/etc` que dpkg considère comme modifiés
par rapport au paquet qui les a livrés.

**E10.7** — Pour le paquet `openssh-server`, affiche uniquement la liste de ses
conffiles telle que dpkg l'enregistre, avec leur empreinte d'origine.

**E10.8** — Affiche toutes les versions de `curl` disponibles dans les dépôts
configurés, avec le dépôt d'origine de chacune, puis la priorité effective de
chaque dépôt de la machine.

**E10.9** — Télécharge le `.deb` du paquet `tree` dans `~/lab10/paquets/` sans
l'installer, puis affiche sa liste de fichiers et son champ `Depends` **sans**
l'extraire ailleurs.

**E10.10** — Depuis `~/lab10/paquets/`, installe `agent-lab_2.0.0_all.deb` avec
`dpkg -i`. Note le message exact et l'état du paquet, puis remets la machine
dans un état propre.

**E10.11** — Simule (sans rien exécuter) ce que ferait `apt autoremove`, et
explique ligne par ligne pourquoi chaque paquet listé est candidat.

**E10.12** — Ajoute le dépôt `noble-backports` à la liste des sources s'il n'y
est pas, puis installe un paquet **uniquement** depuis cette suite, sans changer
la priorité par défaut des autres paquets.

**E10.13** — Retiens `openssh-server` contre toute mise à jour, vérifie la
retenue de deux façons différentes, puis libère-le.

**E10.14** — Fais en sorte que `editor` pointe sur `vim` pour toute la machine,
en mode manuel, puis affiche la preuve que le choix est bien manuel et non
automatique. Reviens ensuite en mode automatique.

**E10.15** — Compile `horodate` depuis `~/lab10/sources/horodate-1.4.tar.gz` avec
un préfixe `/opt/horodate-1.4`, **sans rien installer sur le système** : montre
le contenu de l'arborescence qui serait installée.

**E10.16** — Crée un environnement virtuel Python dans `~/lab10/venv-outil`,
installe-y un module, et prouve que l'interpréteur système n'a pas été touché.
Puis fais la même chose avec `pipx` pour un outil en ligne de commande.

::: rhel
Sur `lab-rhel`, refais les exercices **E10.1, E10.2, E10.5, E10.6, E10.8 et E10.13**
avec `rpm` et `dnf`. Note à chaque fois la commande équivalente : c'est cette
table de correspondance qu'on te demandera en entretien.
:::

---

## 10.6 Labs ★★

### **L10.1** — Inventaire logiciel avant migration

::: contexte
La direction technique veut migrer `lab-adm` vers une nouvelle version d'Ubuntu
dans trois mois. On te demande un état des lieux : ce qui est installé, ce qui
a été installé à la main, ce qui ne vient d'aucun dépôt (donc ce que personne
ne remettra automatiquement après migration), et ce qui a été modifié en local.
Livrable : un rapport + le script qui le produit, pour pouvoir le rejouer sur
les cinq VM.
:::

1. Écris `~/lab10/bin/inventaire.sh`. Il n'installe rien, ne modifie rien, et
   écrit son rapport Markdown sur la sortie standard.
2. Le rapport comporte exactement ces cinq sections, avec ces titres :
   `## Paquets installés`, `## Installés manuellement`, `## États anormaux`,
   `## Hors dépôt officiel`, `## Conffiles modifiés`.
3. « Paquets installés » donne le nombre exact, calculé avec `dpkg-query`, pas
   avec `dpkg -l | wc -l`.
4. « Hors dépôt officiel » liste les paquets installés dont `apt-cache policy`
   ne rattache la version installée à **aucun** dépôt : paquets posés par
   `dpkg -i`, paquets retirés du dépôt depuis, paquets d'un dépôt tiers
   désactivé. C'est la section qui sauve la migration.
5. « Conffiles modifiés » s'appuie sur `dpkg -V` et ne retient que les fichiers
   sous `/etc` marqués comme conffiles.
6. Génère `~/lab10/rapports/inventaire.md` et relis-le : chaque section doit
   être exploitable telle quelle par un collègue, pas un copier-coller de sortie
   brute.

::: astuce
`dpkg-query -W -f '${db:Status-Abbrev} ${binary:Package} ${Version}\n'` donne
une ligne par paquet, état compris, sans en-tête. C'est la base de tout le
script. `dpkg -V` sort en code 1 quand il trouve des écarts : pense à `|| true`
avec `set -e`.
:::

::: check
Critère de succès : `~/lab10/rapports/inventaire.md` contient les cinq sections,
le nombre de paquets correspond au système, et le script est rejouable.

```bash
bash check_M10_01.sh
```
:::

---

### **L10.2** — Publier le dépôt interne de l'équipe, proprement

::: contexte
L'équipe socle distribue ses outils maison par un dépôt APT interne. Jusqu'ici,
chacun installait les `.deb` à la main avec `scp` + `dpkg -i`, et personne ne
savait quelle machine avait quelle version. Le dépôt existe désormais
(`/srv/depot-lab`, servi sur `http://127.0.0.1:8099`), signé par la clé
« Depot Lab Interne ». On te demande de l'intégrer sur `lab-adm` selon les
règles de sécurité de la boîte : aucune clé ne doit être ajoutée au trousseau
global.
:::

1. Récupère la clé publique du dépôt (`/srv/depot-lab/depot-lab.asc` ou
   `http://127.0.0.1:8099/depot-lab.asc`). Avant toute chose, affiche son
   empreinte et son identité : on ne fait pas confiance à un fichier parce qu'il
   s'appelle « la clé ».
2. Installe-la dans `/etc/apt/keyrings/depot-lab.gpg`, au format binaire
   dé-armuré, avec des permissions qui laissent l'utilisateur `_apt` la lire.
3. Déclare le dépôt dans `/etc/apt/sources.list.d/depot-lab.sources`, **au
   format deb822**, en le restreignant à cette seule clé. Le dépôt est plat
   (pas de `dists/`) : la suite s'écrit `./` et il n'y a pas de composant.
4. Lance `apt update` : aucune ligne `W:` ni `E:` ne doit concerner ton dépôt.
5. Installe `outil-lab` **par apt** et prouve, avec `apt-cache policy`, que la
   version installée est rattachée au dépôt et non posée à la main.
6. Vérification par la négative : renomme temporairement le trousseau, relance
   `apt update`, note **le message exact**, puis remets tout en place. Consigne
   ce message : c'est celui que tu reverras en production.
7. Explique dans deux lignes de commentaire, en tête de ton fichier `.sources`,
   pourquoi `Signed-By` est indispensable ici.

::: attention
Tentation à éviter absolument : `[trusted=yes]` ou une clé posée dans
`/etc/apt/trusted.gpg.d/`. Les deux « font marcher » `apt update` et les deux
sont des fautes. Le script de vérification les détecte.
:::

::: check
Critère de succès : `apt update` est silencieux, `outil-lab` est installé depuis
le dépôt, la clé est dans `/etc/apt/keyrings` et n'est utilisable que pour ce
dépôt.

```bash
sudo bash check_M10_02.sh
```
:::

---

### **L10.3** — Ticket INC-3390 : « la 1.2.0 casse la facturation »

::: contexte
`outil-lab` 1.2.0 a été déployé ce matin sur `lab-adm` et l'équipe applicative
constate des erreurs. Décision du responsable d'exploitation : revenir en 1.0.0
et **y rester** jusqu'à validation de la 1.2.1, sans bloquer les mises à jour
des autres paquets. On te demande la manœuvre et la procédure écrite qui va
avec, parce que la prochaine fois, ce sera l'astreinte qui l'appliquera.
:::

1. Constate l'état : version installée, version candidate, versions disponibles
   dans le dépôt, et le dépôt d'origine de chacune.
2. Reviens en 1.0.0. `apt` refuse par défaut de descendre une version : trouve
   l'option, et note pourquoi elle existe.
3. Empêche toute remontée automatique **par épinglage**, dans un fichier dédié
   de `/etc/apt/preferences.d/`. L'épinglage ne doit viser que `outil-lab`.
4. Prouve que ça tient : `apt-cache policy outil-lab` doit annoncer `Candidate:
   1.0.0`, et `apt-get -s upgrade` ne doit plus proposer ce paquet, **sans**
   proposer la moindre rétrogradation collatérale.
5. Fais la même chose avec `apt-mark hold` sur une autre machine (ou après avoir
   retiré ton épinglage) et compare les deux symptômes : que dit
   `apt list --upgradable` dans chaque cas ? que dit `apt install outil-lab` ?
   où est stockée l'information ?
6. Rédige `~/lab10/rapports/figer.md` : la procédure de gel, la procédure de
   dégel, la commande de contrôle à passer en revue mensuelle pour détecter les
   gels oubliés, et le tableau comparatif `hold` / épinglage.

::: astuce
Une priorité d'épinglage doit **dépasser 1000** pour autoriser une
rétrogradation. À 999, apt accepte de garder la 1.0.0 si elle est installée,
mais refuse de redescendre depuis la 1.2.0 : c'est l'erreur classique, et elle
ne se voit qu'au moment où on en a besoin.
:::

::: check
Critère de succès : 1.0.0 installée, 1.0.0 candidate, épinglage ciblé, aucun
`hold`, rapport rédigé.

```bash
sudo bash check_M10_03.sh
```
:::

---

### **L10.4** — L'outil qui n'existe dans aucun dépôt

::: contexte
L'équipe a besoin de `horodate`, un utilitaire maison livré en tarball par un
prestataire. Aucun paquet n'existe. Le réflexe de la moitié de l'équipe serait
`sudo make install` ; on te demande de faire mieux, et d'écrire pourquoi, parce
que cette décision se rejouera cinq fois par an.
:::

Travaille dans `~/lab10/sources/`.

1. Déballe l'archive et lis le `README`. Configure la compilation pour un
   préfixe `/usr/local` — et sache dire pourquoi `/usr/local` et pas `/usr`.
2. Compile. Vérifie le binaire produit **sans l'installer** :
   `./horodate --version` doit répondre `horodate 1.4`.
3. Installe dans une racine factice avec `DESTDIR`, et affiche l'arborescence
   obtenue. C'est l'étape que saute tout le monde, et c'est celle qui prouve ce
   que le projet va réellement écrire sur le système.
4. Transforme cette racine factice en paquet Debian : ajoute un répertoire
   `DEBIAN/` avec un fichier `control` correct (`Package`, `Version`,
   `Architecture`, `Maintainer`, `Description`), construis le `.deb` avec
   `dpkg-deb --build --root-owner-group`, et dépose-le dans `~/lab10/paquets/`.
   Le numéro de version doit refléter la version amont (1.4) et la révision de
   paquet.
5. Installe ton paquet avec `dpkg -i`, puis prouve que le système le connaît :
   `dpkg -S /usr/local/bin/horodate` doit nommer ton paquet, et `dpkg -L` doit
   lister ses fichiers.
6. Désinstalle-le proprement et montre qu'il ne reste rien dans `/usr/local`.
   Réinstalle-le ensuite pour laisser la machine en état.
7. Rédige `~/lab10/rapports/compilation.md` : rôle de `--prefix`, rôle de
   `DESTDIR`, pourquoi `/usr/local` est réservé à l'administrateur local (FHS),
   ce que `checkinstall` fait et pourquoi on ne s'y fie plus, la procédure de
   désinstallation, et les trois cas où compiler depuis les sources reste
   légitime en production.

::: attention
Aucun `sudo make install` dans ce lab. Si tu en fais un par réflexe, note la
liste des fichiers déposés : tu devras les retrouver à la main, et c'est
précisément la démonstration.
:::

::: check
Critère de succès : un `.deb` construit par tes soins, installé, avec
`/usr/local/bin/horodate` attribué à un paquet et aucun fichier orphelin.

```bash
sudo bash check_M10_04.sh
```
:::

---

### **L10.5** — Le même travail sous Rocky 9

::: contexte
La moitié du parc de l'entreprise est sous RHEL. Ton responsable veut être sûr
que tu ne sais pas faire qu'avec `apt`. Tout ce lab se passe sur **`lab-rhel`
(10.10.10.13)**, où `setup_M10.sh` a publié le même dépôt interne au format
RPM.
:::

1. Inventaire : nombre de paquets installés, quel paquet fournit
   `/usr/sbin/sshd`, quels fichiers livre `chrony`, et quels fichiers de
   `/etc` ont été modifiés depuis l'installation. Une commande par question.
2. Déclare le dépôt interne dans `/etc/yum.repos.d/depot-lab.repo` avec
   `gpgcheck=1` et un `gpgkey=` pointant sur la clé publiée. Importe la clé et
   prouve qu'elle est dans la base RPM.
3. Installe `outil-lab` **avec `dnf`**, et prouve avec `dnf repoquery
   --installed --qf '%{from_repo}'` qu'il vient bien du dépôt et pas d'un
   `rpm -i`.
4. Regarde ce que `dnf` a enregistré : `dnf history list`, puis
   `dnf history info <id>` sur ta transaction. Note ce qu'on y trouve et qui
   n'existe nulle part côté Debian.
5. Annule ta transaction avec `dnf history undo <id>`, vérifie que le paquet a
   disparu, puis réinstalle-le. Note le nouvel identifiant de transaction.
6. Modules : affiche les flux disponibles pour `nodejs`, active
   explicitement un flux, constate ce que devient l'autre version, puis remets
   le module à zéro.
7. Ajoute EPEL (`epel-release`), et **avant** d'installer quoi que ce soit,
   regarde ce que ça change : combien de paquets deviennent disponibles, et
   quels paquets déjà installés ont maintenant une version plus récente dans
   EPEL. Conclus sur le risque.
8. Configure `dnf-automatic` pour qu'il **télécharge et applique uniquement les
   correctifs de sécurité**, sans redémarrage, et active son timer.
9. Rédige `~/lab10/rapports/rhel.md` : le tableau de correspondance
   `dpkg`/`rpm` et `apt`/`dnf` que tu as établi, ce que `dnf history` apporte,
   ce que `rpm -qf` t'a appris, et le risque EPEL en une phrase défendable.

::: rhel
`dnf repoquery` remplace `apt-cache` : `dnf repoquery --available`,
`--installed`, `--requires`, `--whatrequires`, `--list`. Et `rpm -qf` ne
fonctionne que sur un fichier **déjà installé** ; l'équivalent d'`apt-file` est
`dnf provides /usr/sbin/nft`.
:::

::: check
Critère de succès : dépôt déclaré avec `gpgcheck=1`, clé importée, `outil-lab`
installé par dnf, une transaction annulée dans l'historique, `dnf-automatic`
en mode sécurité.

```bash
sudo bash check_M10_05.sh
```
:::

---

## 10.7 Break & Fix ★★★

::: attention
Avant chaque Break & Fix : `qm snapshot 9001 avant-bf09`. Le snapshot de secours
reste `snap-clean` (`qm rollback 9001 snap-clean`), mais l'utiliser vaut échec de
l'exercice. Sur une machine où `apt` ne fonctionne plus, on ne répare pas avec
`apt` : c'est tout l'intérêt de ces pannes.
:::

### **BF10.1** — « Plus rien ne s'installe sur cette machine »

```bash
sudo bash break_M10_01.sh
```

**Symptôme utilisateur** : `sudo apt install <n'importe quoi>` refuse de
démarrer avec un message d'erreur unique, sans rien télécharger ni installer.
`apt update` fonctionne. `dpkg -l outil-lab` n'affiche pas `ii` en première
colonne.

**Interdit** : purger `outil-lab`, supprimer `/var/lib/dpkg/status`, rollback de
snapshot.

**Objectif** : remettre `apt` en état de fonctionner, ramener tous les paquets
en état `ii`, et expliquer les **deux** causes distinctes présentes sur la
machine — l'une visible dans `dpkg -l`, l'autre dans `/var/lib/dpkg`.

::: repondre
lignes: 10
:::

### **BF10.2** — « Le dépôt de l'équipe ne marche plus »

```bash
sudo bash break_M10_02.sh
```

**Symptôme utilisateur** : `sudo apt update` se termine par un `W:` puis un `E:`
concernant `http://127.0.0.1:8099`, et `sudo apt install outil-lab` répond
`E: Unable to locate package outil-lab`. Pourtant le dépôt répond :
`curl http://127.0.0.1:8099/Packages` renvoie bien le contenu attendu.

**Interdit** : `[trusted=yes]`, `--allow-unauthenticated`, `apt-key`, poser la
clé dans `/etc/apt/trusted.gpg.d/`.

**Objectif** : rétablir l'installation depuis ce dépôt avec une vérification de
signature réelle, expliquer précisément ce que le message d'erreur signifie
(ce qui a échoué, à quelle étape), et dire ce qui aurait changé si le collègue
d'astreinte avait mis `[trusted=yes]`.

::: repondre
lignes: 10
:::

### **BF10.3** — « La mise à jour de sécurité ne passe pas sur ce serveur »

```bash
sudo bash break_M10_03.sh
```

**Symptôme utilisateur** : le dépôt publie `outil-lab` 1.2.0, la machine est en
1.0.0, et pourtant `apt list --upgradable` ne le propose pas et `sudo apt
upgrade` ne fait rien pour ce paquet. La commande de déploiement de l'équipe,
`sudo apt install -y outil-lab=1.2.0`, s'arrête sur un `E:` au lieu d'installer.
Le responsable sécurité exige la montée sous deux heures.

**Interdit** : `dpkg -i` du paquet, `--force-yes`, suppression puis
réinstallation du paquet.

**Objectif** : identifier **les deux** mécanismes de gel présents (ils ne sont
pas au même endroit et ne se voient pas avec la même commande), les lever
proprement, faire passer la mise à jour, et écrire la commande d'audit qui
aurait détecté ces gels avant l'incident.

::: repondre
lignes: 10
:::

### **BF10.4** — « apt veut désinstaller la moitié du serveur »

```bash
sudo bash break_M10_04.sh
```

**Symptôme utilisateur** : `sudo apt upgrade` annonce plusieurs centaines de
paquets sous un intitulé qui n'est pas `will be upgraded`, et propose de
remplacer les versions installées par des versions plus anciennes — dont `apt`,
`dpkg` et `libc6`. Plus aucune mise à jour de sécurité n'apparaît.

**Interdit** : répondre `y` pour voir, réinstaller les paquets un par un.

**Objectif** : trouver le fichier responsable sans le connaître d'avance,
expliquer avec `apt-cache policy` pourquoi le système en est arrivé là, corriger
en conservant l'intention initiale de son auteur, et vérifier qu'aucune
rétrogradation n'a eu lieu.

::: repondre
lignes: 10
:::

---

## 10.8 Défi du module ★★★

**D10 — Politique de mise à jour du parc**

::: contexte
Trois incidents en six mois : un serveur rétrogradé par un épinglage sauvage,
une faille non corrigée pendant onze semaines sur une machine dont personne ne
savait qu'un `hold` traînait, et un redémarrage automatique en pleine journée.
On te demande d'établir la politique de mise à jour, de l'appliquer sur
`lab-adm`, et de fournir l'outil qui détecte les dérives.
:::

Cahier des charges :

1. Écris `~/lab10/bin/etat-paquets.sh` : bash, `#!/usr/bin/env bash`,
   `set -euo pipefail`, idempotent, exécutable sans `sudo` (il peut afficher une
   section réduite s'il manque des droits), sans dépendance hors distribution.
2. Le script produit un rapport **Markdown sur stdout** et ne met que sa trace
   de diagnostic sur stderr, de sorte que `etat-paquets.sh > rapport.md` donne
   un fichier propre. Il contient au minimum :
   * nombre de paquets installés, et combien viennent de `-security` ;
   * les mises à jour en attente, en séparant **sécurité** et reste ;
   * les paquets retenus (`apt-mark hold`) avec, pour chacun, depuis quand le
     dépôt propose une version supérieure ;
   * tous les épinglages actifs, fichier par fichier, avec la portée réelle
     (nombre de paquets concernés — attention à `Package: *`) ;
   * les paquets en état anormal et les conffiles modifiés ;
   * les fichiers `.dpkg-dist` / `.dpkg-old` / `.ucf-dist` laissés dans `/etc` ;
   * un redémarrage requis ou non (`/var/run/reboot-required`).
3. Le script sort en **0** si tout est conforme, en **1** s'il détecte au moins
   une dérive. Définis « dérive » explicitement dans le rapport, pas dans ta
   tête.
4. Applique la politique sur `lab-adm` avec `unattended-upgrades` :
   * mises à jour de **sécurité uniquement**, appliquées automatiquement ;
   * jamais de redémarrage automatique ;
   * une liste d'exclusion documentée, même vide, pour les paquets applicatifs ;
   * les réglages locaux dans **ton** fichier de `/etc/apt/apt.conf.d/`, pas
     dans `50unattended-upgrades` qui est un conffile du paquet — explique
     pourquoi dans un commentaire ;
   * valide la configuration avec `unattended-upgrade --dry-run --debug` et
     garde la sortie.
5. Rédige `~/lab10/rapports/politique-maj.md` : la politique en une page, ce qui
   est automatisé et ce qui ne l'est jamais, le traitement du **redémarrage**,
   la procédure d'**exclusion** temporaire d'un paquet avec sa date de revue, la
   stratégie de **rollback** quand une mise à jour casse (et honnêtement : ce
   qu'on peut et ne peut pas faire côté Debian), et la revue mensuelle des gels.

Temps visé : 60 à 90 minutes.

::: check
```bash
sudo bash check_M10_06.sh
```
:::

---

## 10.9 Auto-évaluation

| Compétence | Acquis | À revoir |
|---|---|---|
| Situer dpkg, apt-get, apt, aptitude et leur rôle | ☐ | ☐ |
| Distinguer upgrade / full-upgrade et anticiper les suppressions | ☐ | ☐ |
| Interroger la base dpkg (`-l -L -S -s -V`) sans réseau | ☐ | ☐ |
| Réparer une base dpkg en `iU` / `iF` / `rc` | ☐ | ☐ |
| Ajouter un dépôt tiers avec keyring et `Signed-By` | ☐ | ☐ |
| Lire `apt-cache policy` et écrire un épinglage qui vise juste | ☐ | ☐ |
| Gérer le prompt de conffile et les `.dpkg-dist` | ☐ | ☐ |
| Configurer `unattended-upgrades` pour un serveur | ☐ | ☐ |
| Faire l'équivalent sous Rocky : dnf, rpm, history, modules | ☐ | ☐ |
| Diagnostiquer un conflit de dépendances majeur | ☐ | ☐ |
| Compiler et empaqueter sans polluer le système | ☐ | ☐ |
| Arbitrer paquet / snap / pip / npm sur un serveur | ☐ | ☐ |

Pour aller plus loin :

* Ouvre `/var/lib/dpkg/status` et lis l'entrée d'un paquet en entier. Compare-la
  avec `dpkg -s <paquet>` : c'est le même texte. Comprendre que la « base
  dpkg » est un fichier plat change la façon dont on diagnostique.
* Monte un miroir partiel avec `apt-mirror` ou `aptly`, et refais L10.3 en
  figeant non plus un paquet mais **le dépôt entier** à une date. C'est la seule
  méthode qui rend un déploiement vraiment reproductible.
* Lis `man 5 apt_preferences` en entier, en particulier la section
  « How APT Interprets Priorities ». Six pages, et elles suppriment 90 % des
  incidents d'épinglage.
* Compare `dnf history undo` avec ce que permet un système à générations
  (NixOS, ou `rpm-ostree` sur Fedora CoreOS) : c'est la direction que prend
  l'industrie sur la reproductibilité.
