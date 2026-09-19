# Module 02 — Système de fichiers et navigation experte

## 2.0 Objectifs et compétences

::: objectif
À la fin de ce module, je sais :

* dire à quoi sert réellement chaque répertoire de premier niveau (`/etc`, `/var`,
  `/usr`, `/opt`, `/srv`, `/run`, `/tmp`, `/proc`, `/sys`, `/dev`, `/boot`) et
  ranger une application maison à sa place sans hésiter ;
* énumérer ce que contient un inode et ce qu'il ne contient **pas**, lire une
  sortie de `stat` et en déduire l'état réel d'un fichier ;
* choisir entre lien physique et lien symbolique, prédire ce qui casse en cas de
  déplacement, de suppression ou de changement de système de fichiers ;
* expliquer et résoudre le cas « `df` dit plein, `du` ne voit rien », en
  retrouvant le processus fautif avec `lsof +L1` ou `/proc/PID/fd` ;
* mesurer l'occupation disque juste : `df` contre `du`, blocs contre taille
  apparente, fichiers creux, quota d'inodes ;
* écrire un `find` de production : filtres combinés, `-prune`, `-exec {} +`,
  `-print0 | xargs -0`, et savoir pourquoi `-delete` se place en dernier ;
* lire `/proc` et `/sys` comme des sources d'information de diagnostic, et
  modifier un paramètre noyau par `/sys` ;
* reconnaître les six types de fichiers d'Unix et identifier un contenu avec
  `file` sans se fier à l'extension ;
* lire une table de montage avec `findmnt`, repérer un `tmpfs` ou un bind mount,
  et comprendre ce que ça implique au redémarrage ;
* mener une opération de récupération d'espace disque en production sans couper
  le service ni perdre de données.

Temps estimé : 5 h
Prérequis : module 01 (shell, quoting, redirections). Les permissions et les ACL
sont traitées au module 03, LVM et `/etc/fstab` au module 11 : ici on regarde ce
qui est déjà monté, on ne partitionne pas.
:::

---

## 2.1 Mise en place

VM concernées : **`lab-web` (10.10.10.11)** pour l'essentiel, et **`lab-ops`
(10.10.10.14)** pour le défi final. Le module écrit dans `/opt`, `/etc`, `/srv`
et `/var` : il demande `sudo`.

```bash
# depuis le shell Proxmox, avant de commencer
qm snapshot 9002 avant-lab02
```

Paquets nécessaires sur `lab-web` :

```bash
sudo apt update
sudo apt install -y lsof ncdu plocate tree file findutils psmisc
```

::: rhel
Sous Rocky 9 : `sudo dnf install -y lsof ncdu plocate tree file findutils psmisc`.
`ncdu` vient d'EPEL : `sudo dnf install -y epel-release` d'abord.
Sous Rocky, `/etc/system-release` remplace `/etc/os-release` pour l'affichage,
mais `/etc/os-release` existe aussi et reste le fichier à parser.
:::

Préparation du terrain (idempotent, à relancer sans crainte) :

```bash
sudo bash ~/workbook/scripts/setup/setup_M02.sh
```

Il crée `~/lab02/` (arborescence à fouiller, liens, livraison à ranger), monte un
système de fichiers dédié de 256 Mio sur `/srv/appdata` et un autre de 300 Mio sur
`/var/log/factura`, puis remplit `/var/log` et `/var/cache` de consommateurs
d'espace réalistes. Compte deux à trois minutes : il écrit près de 300 Mio de
données aléatoires.

::: attention
Le script monte deux images disque en boucle, via
`mount -o loop /var/lib/lab02/appdata.img /srv/appdata` et son équivalent pour
`/var/log/factura`. Ces montages ne survivent pas au redémarrage : relance le
script de setup après un reboot. Ne touche pas à `/etc/fstab` dans ce module,
c'est le sujet du module 11.
:::

---

## 2.2 Rappel express

### FHS — qui range quoi

| Chemin | Contenu | Survit au reboot |
|---|---|---|
| `/etc` | configuration **statique**, propre à cet hôte, éditable | oui |
| `/usr` | code et données installés par le gestionnaire de paquets | oui, lecture seule en principe |
| `/usr/local` | ce que **tu** compiles/installes à la main | oui |
| `/opt` | logiciels tiers auto-contenus, un répertoire par produit | oui |
| `/var` | données **variables** : logs, bases, files d'attente, caches | oui |
| `/srv` | données **servies** par cet hôte (web, ftp, exports) | oui |
| `/run` | état d'exécution : pid, sockets, verrous (`tmpfs`) | **non**, vidé au boot |
| `/tmp` | temporaire, souvent `tmpfs`, nettoyé régulièrement | **non** |
| `/proc` | interface noyau : processus et paramètres (virtuel) | n/a |
| `/sys` | interface noyau : périphériques et pilotes (virtuel) | n/a |
| `/dev` | fichiers de périphériques (`devtmpfs`, peuplé par udev) | n/a |
| `/boot` | noyaux, initramfs, GRUB — souvent une petite partition | oui |

@fig(fs-fhs): L'arbre FHS en un coup d'œil : ce qui survit au reboot, ce qui est vidé au boot, ce qui n'est qu'une vue du noyau.

Règle de décision pour une appli maison `factura` :

```text
binaires livrés en tar par l'éditeur   -> /opt/factura/bin/
binaires que tu compiles toi-même      -> /usr/local/bin/
configuration                          -> /etc/factura/
état persistant (base, index, cache)   -> /var/lib/factura/
journaux                               -> /var/log/factura/
pid, socket unix, verrou               -> /run/factura/  (RuntimeDirectory=)
fichiers servis aux clients            -> /srv/factura/
```

`/var/run` et `/var/lock` ne sont plus que des liens symboliques vers `/run` et
`/run/lock` : écris `/run`.

### Inode

Un inode contient : type, permissions, UID/GID, taille, nombre de liens,
horodatages (atime/mtime/ctime), pointeurs vers les blocs de données.
Il **ne contient pas** le nom du fichier. Le nom vit dans l'entrée de répertoire,
qui associe `nom -> numéro d'inode`. Un répertoire n'est qu'une table de ce type.

```bash
stat fichier.txt          # inode, liens, blocs, dates
stat -c '%i %h %s %b' f   # inode, nb liens, taille, blocs de 512 o
ls -li                    # numéro d'inode en première colonne
df -i /var                # inodes utilisés / libres du système de fichiers
```

Conséquence : `rm` ne supprime pas des données, il décrémente le compteur de
liens. Les blocs ne sont libérés que quand **le compteur de liens tombe à 0
ET qu'aucun processus n'a le fichier ouvert**.

### Liens

| | Lien physique (`ln`) | Lien symbolique (`ln -s`) |
|---|---|---|
| Nature | 2e nom pour le même inode | fichier contenant un chemin |
| Cible supprimée | contenu toujours accessible | lien cassé (dangling) |
| Traverse un montage | **non** (`EXDEV`) | oui |
| Sur un répertoire | interdit | autorisé |

Un lien symbolique **relatif** est résolu par rapport au répertoire qui contient
le lien, pas par rapport au répertoire courant : il survit à un déplacement de
l'arborescence entière, et casse si on déplace seulement le lien.

@fig(fs-inodes-liens): Entrée de répertoire, inode et blocs : un lien dur est un second nom pour le même inode, un lien symbolique est un inode à part qui contient un chemin.

### Espace disque

| Commande | Ce qu'elle mesure |
|---|---|
| `df -h` | l'occupation vue par le **système de fichiers** |
| `df -i` | les inodes : on peut être plein sans occuper d'octets |
| `du -sh rép` | la somme des **blocs réellement alloués** aux fichiers atteignables |
| `du -sh --apparent-size` | la somme des tailles déclarées (creux inclus) |
| `du -h --max-depth=1 /var \| sort -h` | le classement des sous-répertoires |
| `ncdu -x /` | exploration interactive, `-x` reste sur le même montage |
| `lsof +L1` | fichiers supprimés encore ouverts (nlink = 0) |

::: rhel
Sous Rocky 9, le système de fichiers par défaut est **XFS**, pas ext4. Deux
conséquences : le nombre d'inodes est alloué dynamiquement, donc la saturation
d'inodes y est beaucoup plus rare ; et `tune2fs` ne fonctionne pas — les
informations du système de fichiers se lisent avec `xfs_info /point/de/montage`,
et l'agrandissement se fait avec `xfs_growfs` (jamais de réduction).
:::

Écart `df` / `du` : le coupable habituel est un fichier supprimé qu'un processus
tient encore ouvert. `du` ne le voit plus (plus de nom), `df` le compte toujours
(blocs non libérés). Autres causes : un montage qui masque des fichiers, ou des
blocs réservés à root (5 % par défaut en ext4).

### find — l'essentiel

```bash
find /var/log -type f -name '*.log' -size +100M
find . -iname '*.JPG' -mtime -1        # modifié il y a moins de 24 h
find . -mmin -15                        # moins de 15 minutes
find . -newer /tmp/repere               # plus récent que ce fichier
find /home -user mathieu -group www-data
find . -maxdepth 2 -type d
find . -path '*/node_modules' -prune -o -type f -print
find . -name '*.tmp' -delete
find . -type f -name '*.log' -exec gzip {} +
find . -type f -print0 | xargs -0 -r sha256sum
```

| Élément | Sens |
|---|---|
| `-mtime +7` / `-7` | plus de 7 jours / moins de 7 jours (tranches de 24 h) |
| `-size +100M` / `-100k` | plus de 100 Mio / moins de 100 Kio |
| `-exec cmd {} \;` | une exécution **par fichier** |
| `-exec cmd {} +` | regroupe les fichiers, comme `xargs` : bien plus rapide |
| `-a` `-o` `!` `\( \)` | et, ou, non, groupement (les parenthèses se protègent) |
| `-prune` | ne descend pas dans ce répertoire, s'emploie avec `-o` |
| `-print0` | sépare les noms par un octet nul : seul format sûr |

`-delete` implique `-depth` et doit être le **dernier** test : `find . -delete
-name '*.tmp'` efface tout. Teste toujours avec `-print` avant.

### /proc et /sys

```bash
cat /proc/meminfo /proc/cpuinfo /proc/loadavg
cat /proc/mounts                 # ce que le noyau a réellement monté
ls -l /proc/1234/fd              # descripteurs ouverts du pid 1234
readlink /proc/1234/cwd /proc/1234/exe
cat /proc/1234/cmdline | tr '\0' ' '
cat /sys/block/sda/queue/rotational        # 1 = disque mécanique
echo 1 | sudo tee /sys/block/sda/device/rescan
```

Ces fichiers ont une taille de 0 et ne consomment aucun disque : ils sont générés
à la lecture par le noyau.

### Types de fichiers et montages

| Lettre (`ls -l`) | Type | Test `find` |
|---|---|---|
| `-` / `d` | fichier ordinaire / répertoire | `-type f` / `-type d` |
| `l` / `s` | lien symbolique / socket unix | `-type l` / `-type s` |
| `p` / `b` / `c` | tube nommé / bloc / caractère | `-type p` / `b` / `c` |

```bash
file -- rapport.pdf            # identifie par le contenu, pas l'extension
findmnt                        # arbre des montages, lisible
findmnt -t tmpfs               # uniquement les tmpfs
findmnt -T /var/log/factura    # quel montage porte ce chemin
mount --bind /srv/data /var/www/html/data   # le même contenu à deux endroits
```

---

## 2.3 Quiz — QCM

**Q2.1** — Tu déploies `factura`, une application livrée par un éditeur sous forme
d'archive auto-contenue, qui publie des exports CSV téléchargés par les clients via
nginx. Où ranges-tu les binaires et où ranges-tu les CSV ?

a) binaires dans `/usr/bin`, CSV dans `/var/www`
b) binaires dans `/opt/factura/bin`, CSV dans `/srv/factura/exports`
c) binaires dans `/usr/local/sbin`, CSV dans `/var/lib/factura`
d) tout dans `/opt/factura`, c'est auto-contenu

**Q2.2** — Parmi ces informations, laquelle n'est **pas** stockée dans l'inode ?

a) le nombre de liens physiques
b) le nom du fichier
c) l'UID du propriétaire
d) la date de dernière modification du contenu

**Q2.3** — Voici une session sur `lab-web` :

```console
$ ln rapport.txt copie.txt
$ rm rapport.txt
$ cat copie.txt
```

Que se passe-t-il ?

a) `cat: copie.txt: No such file or directory`
b) le contenu s'affiche normalement
c) `copie.txt` existe mais est vide
d) `rm` aurait refusé de supprimer un fichier ayant deux liens

**Q2.4** — `/srv/appdata` est un système de fichiers distinct. Tu lances :

```bash
ln /var/lib/factura/factura.db /srv/appdata/factura.db
```

Résultat ?

a) le lien est créé, les deux chemins partagent l'inode
b) `ln: failed to create hard link: Invalid cross-device link`
c) `ln` bascule automatiquement en lien symbolique
d) le fichier est copié

**Q2.5** — Sur `lab-web`, `df -h /var` affiche `98%` alors que
`du -sh /var` répond `2,1G` pour une partition de 20 Go. **Deux réponses
plausibles.**

a) un processus tient ouvert un gros fichier qui a été supprimé
b) `du` ne compte pas les fichiers cachés
c) un montage sur `/var/log` masque des fichiers écrits avant qu'il soit monté
d) `df` compte les fichiers creux à leur taille apparente

**Q2.6** — Que liste exactement `sudo lsof +L1` ?

a) les fichiers ouverts par plus d'un processus
b) les fichiers ouverts dont le nombre de liens est inférieur à 1, donc supprimés
c) les fichiers verrouillés (`flock`)
d) les liens symboliques ouverts

**Q2.7** — On est le 18 septembre à 14 h. Quels fichiers remonte
`find /var/log -type f -mtime +7` ?

a) ceux modifiés depuis le 11 septembre 14 h
b) ceux modifiés avant le 10 septembre 14 h
c) ceux modifiés exactement le 11 septembre
d) ceux créés il y a plus de 7 jours, quelle que soit la date de modification

**Q2.8** — Tu dois compresser 40 000 fichiers de log. Quelle différence entre ces
deux lignes ?

```bash
find /var/log -name '*.log' -exec gzip {} \;
find /var/log -name '*.log' -exec gzip {} +
```

a) aucune, `+` est une écriture moderne de `\;`
b) la première lance 40 000 processus `gzip`, la seconde en lance quelques-uns
c) la seconde ne traite que le premier fichier trouvé
d) la première est plus sûre avec les noms contenant des espaces

**Q2.9** — Dans `/var/log`, qui contient des `.log`, tu tapes :

```bash
find /var/log -name *.log
```

Pourquoi est-ce dangereux ?

a) `find` ne comprend pas les jokers
b) le shell développe `*.log` avant `find`, qui reçoit alors plusieurs arguments
   `-name` et échoue ou cherche autre chose
c) il faut `-iname` pour que les jokers fonctionnent
d) `find` va supprimer les fichiers trouvés

**Q2.10** — Tu veux tous les `.js` d'un projet **sauf** ceux de `node_modules`.
Quelle commande ?

a) `find . -name node_modules -prune -o -name '*.js' -print`
b) `find . -name '*.js' -prune node_modules`
c) `find . ! -path node_modules -name '*.js'`
d) `find . -name '*.js' -o -name node_modules -prune`

**Q2.11** — `ls -lh disque-vm.img` affiche `2,0G`, `du -h disque-vm.img` affiche
`4,0M`. Que sais-tu de ce fichier ?

a) `du` est en erreur, il faut `du --apparent-size`
b) c'est un fichier creux : sa taille déclarée dépasse largement les blocs alloués
c) le fichier est compressé par le système de fichiers
d) le fichier est un lien symbolique vers un fichier de 4 Mio

**Q2.12** — `ls -l /proc/meminfo` affiche une taille de 0 octet, pourtant
`cat /proc/meminfo` produit une cinquantaine de lignes. Pourquoi ?

a) le fichier est creux
b) `/proc` est un système de fichiers virtuel : le contenu est généré par le noyau
   au moment de la lecture, rien n'est stocké
c) le fichier est un lien vers `/sys/kernel/mm`
d) la taille n'est mise à jour qu'au redémarrage

**Q2.13** — Ton application écrit son fichier de pid. Où le place-t-elle, et que
devient-il au redémarrage ? **Deux réponses correctes.**

a) dans `/run/factura/`, qui est un `tmpfs` vidé à chaque démarrage
b) dans `/var/run/factura/`, qui est aujourd'hui un lien symbolique vers `/run`
c) dans `/tmp/`, seul emplacement garanti inscriptible
d) dans `/var/lib/factura/`, pour qu'il survive au redémarrage

**Q2.14** — `ls -l` affiche cette ligne :

```console
srwxr-xr-x 1 postgres postgres 0 Sep 18 09:12 .s.PGSQL.5432
```

De quel type de fichier s'agit-il ?

a) un fichier ordinaire de 0 octet
b) un tube nommé (FIFO)
c) une socket unix
d) un lien symbolique cassé

**Q2.15** — Dans `/opt/app`, tu as créé `conf -> ../conf-prod`. Tu déplaces ensuite
le lien seul dans `/etc/app/`. Que se passe-t-il ?

a) rien, le lien continue de pointer vers `/opt/conf-prod`
b) le lien pointe désormais vers `/etc/conf-prod`, qui n'existe pas
c) le lien devient absolu automatiquement
d) `mv` refuse de déplacer un lien symbolique relatif

**Q2.16** — Un script échoue avec `No space left on device` sur `/srv/appdata`,
mais `df -h /srv/appdata` affiche `52% used`. Quelle est la cause la plus probable
et la commande qui le confirme ?

a) un quota utilisateur, confirmé par `quota -v`
b) les inodes sont épuisés, confirmé par `df -i /srv/appdata`
c) le système de fichiers est monté en lecture seule, confirmé par `mount`
d) les 5 % réservés à root, confirmés par `tune2fs -l`

**Q2.17** — `locate factura.conf` ne trouve rien alors que le fichier existe depuis
dix minutes. Pourquoi, et que fais-tu ?

a) `locate` ne cherche que dans `/usr` ; utilise `find /`
b) `locate` interroge une base indexée mise à jour périodiquement ; lance
   `sudo updatedb` ou utilise `find`
c) le fichier est dans `/etc`, exclu par défaut de l'index
d) `locate` ne fonctionne que sur les fichiers exécutables

**Q2.18** — `findmnt -T /tmp` affiche :

```console
TARGET SOURCE FSTYPE OPTIONS
/tmp   tmpfs  tmpfs  rw,nosuid,nodev,size=1004856k
```

Quelles conséquences en tires-tu ? **Deux réponses correctes.**

a) écrire 2 Gio dans `/tmp` échouera avec `No space left on device`
b) le contenu de `/tmp` occupe de la RAM, pas le disque
c) `/tmp` sera vidé au redémarrage
d) `du -sh /tmp` remontera dans `df -h /` sur la ligne du système de fichiers racine

---

## 2.4 Quiz — questions ouvertes

**QO2.1** — Explique ce qu'est un inode, ce qu'il contient et ce qu'il ne contient
pas. Déduis-en, en raisonnant sur le compteur de liens, ce que fait réellement `rm`
et à quel moment précis les blocs d'un fichier sont rendus au système de fichiers.

::: repondre
lignes: 10
:::

**QO2.2** — *On te demande en entretien* : « `df -h` annonce 100 % sur `/var`,
`du -sh /var` répond 3 Go alors que la partition fait 20 Go. Explique-moi ce qui se
passe, comment tu le prouves, et comment tu récupères l'espace sans redémarrer le
serveur ni couper le service. »

::: repondre
lignes: 12
:::

**QO2.3** — Compare lien physique et lien symbolique sur quatre critères au moins,
puis explique lequel tu choisis pour un déploiement de type `releases/` +
`current -> releases/2026-09-18`, et pourquoi. Précise si tu fais le lien relatif
ou absolu, avec l'argument correspondant.

::: repondre
lignes: 10
:::

**QO2.4** — *On te demande en entretien* : « Il est 3 h du matin, l'alerte dit
`/` à 97 % sur le serveur de production. Déroule ta démarche, commande par
commande, jusqu'à la remise sous seuil. Dis-moi ce que tu t'interdis de faire. »

::: repondre
lignes: 12
:::

**QO2.5** — Explique la différence de fonctionnement entre `-exec cmd {} \;`,
`-exec cmd {} +` et `find -print0 | xargs -0 cmd`. Donne pour chacun un cas où
c'est le bon choix, et explique pourquoi `find | xargs` sans `-print0` est un bug
en attente.

::: repondre
lignes: 10
:::

**QO2.6** — `/proc` et `/sys` ne consomment aucun espace disque. Explique ce qu'ils
sont, la différence de vocation entre les deux, et donne trois diagnostics concrets
que tu ne peux mener qu'en les lisant. Cite un cas où tu **écris** dans `/sys`.

::: repondre
lignes: 8
:::

**QO2.7** — Un développeur veut installer son application dans `/usr/bin` « comme
les vraies commandes ». Argumente, en te référant au FHS, pour la placer ailleurs.
Distingue les cas `/opt`, `/usr/local` et `/srv`, et explique ce qui se passe
concrètement lors d'une mise à jour de paquet si on s'installe dans `/usr/bin`.

::: repondre
lignes: 8
:::

**QO2.8** — Qu'est-ce qu'un fichier creux ? Explique l'écart entre `ls -l` et
`du`, cite deux cas où on en produit sans le vouloir, et décris ce qui arrive à
ces fichiers quand on les copie avec `cp` sans option, avec `tar`, et via `rsync`.

::: repondre
lignes: 8
:::

---

## 2.5 Exercices guidés ★

**E2.1** — Affiche, pour `~/lab02/liens/source/rapport.txt`, son numéro d'inode,
son nombre de liens, sa taille en octets et le nombre de blocs de 512 octets
réellement alloués — le tout sur une seule ligne, sans passer par `ls`.

**E2.2** — Dans `~/lab02/liens/source`, détermine sans ouvrir les fichiers lesquels
partagent le même contenu physique et lesquels sont de simples liens symboliques.
Donne la commande et explique la colonne qui tranche.

**E2.3** — Crée dans `~/lab02/liens/deplace` un lien symbolique **relatif** vers
`../source/rapport.txt`, puis déplace le lien dans `~/lab02/liens/copie`.
Montre qu'il est cassé, puis répare-le sans changer de répertoire de destination.

**E2.4** — Prouve qu'on ne peut pas créer de lien physique entre
`~/lab02/liens/source/rapport.txt` et `/srv/appdata/incoming/`. Note le message
d'erreur exact et le numéro d'erreur système correspondant.

**E2.5** — Liste les entrées de `~/lab02/liens` qui ne sont ni des fichiers
ordinaires ni des répertoires, en affichant pour chacune son type avec `find`.
Identifie ensuite le type réel de `~/lab02/arbo/archives/disque-vm.img`,
`~/lab02/liens/app.sock` et `/etc/os-release` sans les ouvrir.

**E2.6** — `~/lab02/liens/casse.txt` est un lien cassé. Trouve tous les liens
symboliques cassés sous `~/lab02` avec une seule commande `find`.

**E2.7** — Affiche les cinq répertoires les plus volumineux directement sous
`/var`, triés du plus gros au plus petit, en unités lisibles.

**E2.8** — Compare la taille apparente et l'occupation réelle de
`~/lab02/arbo/archives/disque-vm.img`. Donne les deux commandes et l'écart en
pourcentage.

**E2.9** — Trouve tous les fichiers de plus de 5 Mio sous `~/lab02/arbo`, affiche-les
triés par taille décroissante avec leur taille lisible, sans utiliser `ls -lS`.

**E2.10** — Dans `~/lab02/arbo`, liste les fichiers modifiés il y a moins de 24
heures, puis ceux modifiés il y a moins de 30 minutes. Explique pourquoi la seconde
liste peut être vide.

**E2.11** — Liste tous les fichiers de `~/lab02/arbo` appartenant à `www-data`,
puis tous ceux qui n'appartiennent **pas** à `mathieu`. Les deux listes
doivent-elles être identiques ?

**E2.12** — Sous `~/lab02/arbo/app`, liste tous les fichiers en ignorant totalement
`node_modules` et `.git` (ces répertoires ne doivent même pas être parcourus).

**E2.13** — Calcule la somme SHA-256 de tous les fichiers `.log` de
`~/lab02/arbo`, y compris `audit ancien.log`, sans qu'aucun nom ne soit découpé.
Fais-le d'abord avec `-exec ... +`, puis avec `xargs`.

**E2.14** — Supprime les fichiers `.tmp` de `~/lab02/arbo` vieux de plus de 3
jours. Montre d'abord la liste, puis supprime, en une seule commande `find` pour
chaque étape.

**E2.15** — Pour le processus `1` (`systemd`), affiche son exécutable réel, son
répertoire courant et sa ligne de commande en lisant uniquement `/proc`. Puis
détermine, en lisant `/sys`, si le disque qui porte `/` est un SSD ou un disque
mécanique.

**E2.16** — Affiche uniquement les points de montage de type `tmpfs` de ta VM avec
leur taille, puis indique quel montage porte le fichier
`/var/log/factura/factura.log` et quel est son type.

---

## 2.6 Labs ★★

### **L2.1** — Ranger la livraison `factura` selon le FHS

::: contexte
L'éditeur livre `factura-2.4.tar.gz` : une archive à plat contenant un démon, un
client d'administration, une configuration, une unité systemd, une base initiale et
un exemple d'export CSV. Le développeur propose de « tout mettre dans
`/home/mathieu/factura` et de lancer ça avec `nohup` ». On te demande un
déploiement conforme, qui survivra à la prochaine mise à jour de l'OS et au
prochain audit.
:::

Travaille sur `lab-web`. L'archive est dans `~/lab02/livraison/`.

1. Extrais l'archive dans un répertoire temporaire et inventorie son contenu :
   pour chaque fichier, dis en une ligne où il doit aller et pourquoi.
2. Installe les binaires dans `/opt/factura/bin/`, en conservant le bit
   d'exécution.
3. Rends `facturactl` appelable sans chemin par tous les utilisateurs, **sans
   copier le binaire** et sans toucher au `PATH` de qui que ce soit.
4. Place la configuration dans `/etc/factura/factura.conf`.
5. Crée `/var/lib/factura/` (avec `factura.db`), `/var/log/factura/` et
   `/srv/factura/exports/` (avec l'exemple CSV). Les exports appartiennent à
   `www-data`, c'est nginx qui les sert.
6. Installe l'unité systemd dans `/etc/systemd/system/factura.service`, démarre
   le service et vérifie que `/run/factura/` est créé automatiquement, avec le
   fichier de pid dedans. N'écris pas `/run/factura` à la main.
7. Redémarre le service et prouve que `/run/factura/` a été recréé de zéro.
8. Rédige `~/lab02/rapports/fhs-factura.md` : un tableau à trois colonnes
   (chemin, contenu, justification FHS).

::: astuce
Pour l'étape 3, `ln -s` dans `/usr/local/bin` est l'usage. Demande-toi si tu fais
le lien relatif ou absolu, et ce qui se passerait si `/opt` était un montage séparé.
:::

::: check
Critère de succès : `systemctl is-active factura` répond `active`,
`/run/factura/facturad.pid` existe, `facturactl` répond depuis `/tmp`, et aucun
fichier de l'application ne traîne dans `/usr/bin` ni dans le home.

```bash
bash check_M02_01.sh
```
:::

---

### **L2.2** — Ticket INC-3187 : « partition de logs à 99 % sur lab-web »

::: contexte
Supervision a levé une alerte à 23 h 40 : `/var/log/factura`, qui est une partition
dédiée de 300 Mio, est à 99 %. L'application tourne encore mais ne journalise
presque plus. On te demande de repasser sous 50 %, sans redémarrer la machine,
sans arrêter `factura`, et de livrer un rapport expliquant où l'espace était parti.
Profites-en pour faire le ménage général sur `/`.
:::

1. Établis l'état des lieux : occupation par système de fichiers, en excluant les
   montages virtuels (`tmpfs`, `proc`, `sysfs`, `devtmpfs`). Combien de systèmes de
   fichiers réels cette VM porte-t-elle, et lequel est en cause ?
2. Descends dans l'arborescence par paliers, sans jamais franchir de point de
   montage : classe les sous-répertoires de `/var`, puis ceux du plus gros, et
   ainsi de suite. Note ce que `du -x` change par rapport à `du` tout court ici.
3. Refais la même exploration avec `ncdu -x` et note ce que l'outil interactif
   apporte par rapport à la boucle `du | sort -h`.
4. Traite `/var/log/factura/factura.log` (180 Mio) : il est **ouvert en écriture
   par un processus**. Récupère son espace sans le supprimer et sans redémarrer le
   service. Vérifie avec `df` avant et après, et explique dans le rapport pourquoi
   `rm` aurait été le mauvais réflexe.
5. Traite les journaux archivés `factura.log.*.gz` : garde les deux plus récents,
   supprime les autres, en une seule commande `find`.
6. Mesure l'espace occupé par le journal systemd (`journalctl --disk-usage`),
   ramène-le à 50 Mio au maximum, et rends la limite permanente dans
   `/etc/systemd/journald.conf`.
7. Vide le cache APT et le cache applicatif `/var/cache/factura/thumbs`. Compte
   combien de fichiers ce dernier contenait et combien d'inodes tu viens de libérer
   sur `/`.

::: rhel
Sous Rocky 9, l'équivalent de `sudo apt clean` est `sudo dnf clean all`, et le
cache vidé est `/var/cache/dnf`, qui atteint facilement 1 Gio sur une machine
ayant plusieurs dépôts actifs. `journalctl --vacuum-size` est identique.
:::
8. `~/lab02/arbo/archives/disque-vm.img` semble peser 2 Gio. **Ne le supprime
   pas** : explique dans le rapport pourquoi il ne pèse pas ce qu'il annonce.
9. Livre `~/lab02/rapports/inc-3187.md` : état initial (sortie de `df -h`), les
   trois causes, les actions menées, l'état final, et deux recommandations de
   prévention (une sur la rotation, une sur la supervision).

::: attention
Interdiction absolue de `rm` sur un fichier de log qu'un processus tient ouvert :
tu ne récupérerais rien tant que le processus vit, et tu perdrais la journalisation
en cours. C'est exactement le sujet de BF2.1.
:::

::: check
Critère de succès : `/var/log/factura` est repassé sous 50 %, `factura.log` existe
toujours avec le même inode mais pèse moins de 1 Mio, il ne reste que deux archives
`.gz`, `/var/cache/factura/thumbs` est vide, la limite `SystemMaxUse` est posée, et
le rapport existe.

```bash
bash check_M02_02.sh
```
:::

---

### **L2.3** — Audit d'arborescence avant migration

::: contexte
L'équipe applicative veut migrer `~/lab02/arbo` vers un nouveau stockage. Avant de
copier 40 Go inutiles, on te demande un inventaire : ce qui est gros, ce qui est
mort, ce qui ne doit pas être migré, et le ménage des fichiers temporaires. Les
noms de fichiers viennent d'un import Windows, certains contiennent des espaces.
:::

Tous les livrables vont dans `~/lab02/inventaire/`.

1. `gros.txt` : tous les fichiers de plus de 5 Mio, avec leur taille en octets et
   leur chemin, triés du plus gros au plus petit.
2. `anciens.txt` : tous les fichiers non modifiés depuis plus de 90 jours, avec
   leur date de modification. Ces fichiers seront archivés, pas migrés.
3. `par-proprietaire.txt` : la liste des fichiers n'appartenant pas à `mathieu`,
   avec le nom du propriétaire.
4. `code.txt` : tous les fichiers sous `arbo/app`, en excluant du parcours
   `node_modules` et `.git` — ces répertoires ne doivent pas être descendus, pas
   seulement filtrés à l'affichage. Compare le temps d'exécution avec et sans
   `-prune` (`time`).
5. `sommes.txt` : la somme SHA-256 de tous les `.log`, y compris ceux dont le nom
   contient une espace. Le fichier doit contenir autant de lignes qu'il y a de
   `.log` dans l'arborescence.
6. Ménage : supprime tous les `.tmp` de plus de 3 jours, en montrant d'abord la
   liste. Le fichier `uploads/scan provisoire.tmp` fait partie du lot.
7. `resume.txt` : nombre total de fichiers, nombre de répertoires, nombre
   d'inodes consommés par l'arborescence, et taille réelle contre taille apparente.
8. Vérifie qu'aucun de tes fichiers d'inventaire ne contient de chemin tronqué par
   une espace : ouvre `sommes.txt` et regarde la ligne de `audit ancien.log`,
   puis `anciens.txt` et celle de `audit ancien.log` également.

::: check
Critère de succès : les six fichiers d'inventaire existent et sont cohérents, les
`.tmp` anciens ont disparu, `.git` et `node_modules` sont intacts, et les noms à
espaces apparaissent entiers.

```bash
bash check_M02_03.sh
```
:::

---

### **L2.4** — Dédoublonner sans casser : liens physiques et symboliques

::: contexte
L'équipe média a copié trois fois le même jeu de photos sur `lab-web` : une fois
dans le répertoire de travail, une fois dans un « backup » et une fois dans le
répertoire servi par nginx. Deux de ces emplacements sont sur le système de
fichiers racine, le troisième est sur `/srv/appdata`, un montage distinct. On te
demande de ne garder qu'une seule copie physique par fichier, sans qu'aucun chemin
existant ne cesse de fonctionner.
:::

1. Prépare le terrain : copie `~/lab02/arbo/uploads/photo1.jpg` et `photo2.jpg`
   dans `~/lab02/liens/copie/` et dans `/srv/appdata/incoming/`. Note l'occupation
   de `~/lab02` (`du -sh`) et celle de `/srv/appdata` (`df -h`) : tu viens de payer
   trois fois le même contenu.
2. Prouve que `~/lab02/liens/copie` et `/srv/appdata/incoming` sont sur deux
   systèmes de fichiers différents, de deux façons : par les inodes et par
   `findmnt`.
3. Dédoublonne `~/lab02/arbo/uploads` et `~/lab02/liens/copie` avec des liens
   **physiques**. Prouve que l'espace a été rendu en comparant `du -sh ~/lab02`
   avant et après, vérifie que les deux chemins portent le même inode, et explique
   pourquoi `du -sh ~/lab02/liens/copie` seul, lui, n'a pas bougé d'un octet.
4. Modifie le contenu de `~/lab02/liens/copie/photo1.jpg` (ajoute une ligne).
   Que vaut désormais `~/lab02/arbo/uploads/photo1.jpg` ? Explique.
5. Supprime `~/lab02/arbo/uploads/photo1.jpg`. Le fichier de `copie/` est-il
   toujours lisible ? Que vaut son compteur de liens ? Restaure un lien physique
   pour revenir à l'état de l'étape 3.
6. Pour `/srv/appdata/incoming`, le lien physique est impossible. Mets en place un
   lien symbolique **absolu** depuis `/srv/appdata/incoming/photo2.jpg` vers le
   fichier de `~/lab02/arbo/uploads/`, et explique pourquoi l'absolu s'impose ici.
7. Déplace `~/lab02/liens/copie` en `~/lab02/liens/copie-v2` et dresse le bilan :
   quels liens ont survécu, lesquels sont cassés, pourquoi. Répare.
8. Écris dans `~/lab02/rapports/liens.md` une règle de décision en trois lignes :
   quand physique, quand symbolique, quand ni l'un ni l'autre (copie).

::: check
Critère de succès : `photo1.jpg` et `photo2.jpg` de `uploads` ont un compteur de
liens supérieur à 1 avec le même inode que leurs doublons locaux, le lien de
`/srv/appdata/incoming` est un symbolique absolu qui résout, et aucun lien cassé ne
subsiste sous `~/lab02`.

```bash
bash check_M02_04.sh
```
:::

---

## 2.7 Break & Fix ★★★

::: attention
Avant chaque Break & Fix : `qm snapshot 9002 avant-bf02`. Le snapshot de secours
reste `snap-clean` (`qm rollback 9002 snap-clean`), mais l'utiliser vaut échec de
l'exercice : l'objectif est de réparer, pas de rembobiner.
Ces trois pannes supposent que `setup_M02.sh` a été passé.
:::

### **BF2.1** — « Le disque est plein, mais il n'y a rien dessus »

```bash
sudo bash break_M02_01.sh
```

**Symptôme utilisateur** : l'application de collecte ne peut plus écrire sur
`/srv/appdata`. `df -h /srv/appdata` affiche `100%`. Mais `du -sh /srv/appdata`
répond `28K`, et `ls -laR /srv/appdata` ne montre aucun gros fichier. Un `sync` ne
change rien.

**Interdit** : démonter ou remonter `/srv/appdata`, redémarrer la machine,
agrandir le système de fichiers.

**Objectif** : retrouver l'espace, identifier le processus responsable **et** le
fichier concerné (nom d'origine, taille), expliquer le mécanisme en une phrase, et
proposer deux corrections durables — une côté application, une côté exploitation.

::: repondre
lignes: 12
:::

### **BF2.2** — « `No space left on device` alors qu'il reste 40 % »

```bash
sudo bash break_M02_02.sh
```

**Symptôme utilisateur** : un script d'import échoue avec
`touch: cannot touch '/srv/archives/lots/lot-042.tar': No space left on device`.
Pourtant `df -h /srv/archives` affiche environ `52%`, et il reste plus de 40 Mio
libres. Même `mkdir` échoue.

**Interdit** : reformater le système de fichiers, supprimer aveuglément
`/srv/archives/*` sans avoir compris.

**Objectif** : poser le bon diagnostic en une commande, dire quel paramètre du
système de fichiers est en cause, remettre le service en état, expliquer pourquoi
le problème n'apparaît pas dans `df -h`, et dire ce qu'il aurait fallu faire au
formatage pour l'éviter.

::: repondre
lignes: 10
:::

### **BF2.3** — « Le site sert la mauvaise version depuis la livraison »

```bash
sudo bash break_M02_03.sh
```

**Symptôme utilisateur** : après la dernière livraison, le site renvoie des 404.
`ls /srv/www/current/` répond
`ls: cannot access '/srv/www/current/': No such file or directory`, et
`cat /srv/www/current/index.html` aussi, alors que `ls -l /srv/www/` montre bien
une entrée `current`. Les répertoires de releases sont toujours là et lisibles.

**Interdit** : recopier une release à la main dans `/srv/www/current`, supprimer
l'arborescence `releases/`.

**Objectif** : expliquer pourquoi `ls -l /srv/www` affiche une entrée que
`ls /srv/www/current/` ne trouve pas, identifier précisément pourquoi le lien ne
résout pas (donne la commande qui le montre sans ambiguïté), rétablir le service
sur la release la plus récente, et corriger la procédure de livraison pour que la
panne ne puisse plus se reproduire (dis explicitement quel type de lien tu poses
et pourquoi).

::: repondre
lignes: 10
:::

---

## 2.8 Défi du module ★★★

**D2 — `audit-fs.sh` : l'outil d'audit de systèmes de fichiers**

::: contexte
Tu prends l'astreinte. Tu veux un script unique, déposable sur n'importe quelle VM
du lab, qui répond en moins d'une minute à la question « où est passé l'espace, et
qu'est-ce qui cloche sur ce stockage ? ». Livrable : le script plus un rapport
généré sur `lab-ops`.
:::

Cahier des charges :

1. Écris `/usr/local/bin/audit-fs.sh`, en bash, commençant par
   `#!/usr/bin/env bash` et `set -euo pipefail`, idempotent, fonctionnant sur
   `lab-web` (Ubuntu 24.04) et `lab-rhel` (Rocky 9) sans modification. Il accepte
   un chemin en argument (`/` par défaut) et l'option `-n` pour ne rien écrire.
2. Le rapport part sur **stdout** au format Markdown, la trace de diagnostic sur
   **stderr**. `audit-fs.sh > rapport.md` doit produire un Markdown propre.
3. Sections obligatoires du rapport :
   * **Montages** : pour chaque système de fichiers réel (les virtuels exclus),
     source, point de montage, type, usage en % de blocs **et** en % d'inodes ;
   * **Top 10 des répertoires** sous le chemin analysé, sans franchir de montage ;
   * **Top 10 des fichiers** les plus gros, avec taille lisible ;
   * **Fichiers supprimés encore ouverts** : processus, pid, taille, chemin
     d'origine, et l'espace total ainsi immobilisé ;
   * **Liens symboliques cassés** trouvés sous le chemin analysé ;
   * **Fichiers creux** : ceux dont la taille apparente dépasse d'au moins un
     facteur 4 l'occupation réelle ;
   * **Journaux** : taille de `journalctl --disk-usage` et les cinq plus gros
     fichiers de `/var/log`.
4. Section **Anomalies**, avec au moins ces cinq déclencheurs :
   * un système de fichiers à plus de 85 % de blocs ;
   * un système de fichiers à plus de 85 % d'inodes ;
   * plus de 100 Mio immobilisés par des fichiers supprimés encore ouverts ;
   * au moins un lien symbolique cassé ;
   * `/run` ou `/tmp` à plus de 50 %.
5. Code de retour : 0 si aucune anomalie, 1 sinon. Le script ne doit jamais écrire
   dans l'arborescence auditée, et doit rester correct sur des noms de fichiers
   contenant des espaces.
6. Le script doit fonctionner sans `sudo` en mode dégradé (il signale alors que la
   section « fichiers supprimés ouverts » est incomplète) et complet avec `sudo`.
7. Livre `~/lab02/rapports/audit-lab-ops.md`, généré sur `lab-ops`, et corrige la
   machine jusqu'à ce que le script sorte en 0.

Temps visé : 60 à 90 minutes.

::: check
```bash
bash check_M02_05.sh
```
:::

---

## 2.9 Auto-évaluation

| Compétence | Acquis | À revoir |
|---|---|---|
| Ranger une application selon le FHS et le justifier | ☐ | ☐ |
| Dire ce que contient un inode, lire `stat` | ☐ | ☐ |
| Choisir entre lien physique et symbolique | ☐ | ☐ |
| Prédire ce qui casse au déplacement d'un lien relatif | ☐ | ☐ |
| Diagnostiquer un écart `df` / `du` | ☐ | ☐ |
| Retrouver un fichier supprimé encore ouvert | ☐ | ☐ |
| Diagnostiquer une saturation d'inodes | ☐ | ☐ |
| Écrire un `find` combiné avec `-prune` et `-exec +` | ☐ | ☐ |
| Traiter sans risque des noms contenant des espaces | ☐ | ☐ |
| Lire `/proc` et `/sys` pour un diagnostic | ☐ | ☐ |
| Identifier les six types de fichiers, utiliser `file` | ☐ | ☐ |
| Lire `findmnt`, repérer un `tmpfs` | ☐ | ☐ |
| Récupérer de l'espace en production sans coupure | ☐ | ☐ |

Pour aller plus loin :

* Lis la norme FHS 3.0 (`https://refspecs.linuxfoundation.org/fhs.shtml`), au moins
  les chapitres 3 et 5. C'est court et ça tranche la moitié des débats d'équipe.
* Compare `du -sh /var` et `ncdu -x /var` sur une vraie machine de production :
  mesure le temps de chacun et regarde ce que `-x` change.
* Explore `/proc/self/` : `ls -l /proc/self/fd` depuis un shell, puis depuis un
  processus qui a des redirections. `man 5 proc` fait 3 000 lignes, elles valent
  toutes la peine.
* Regarde `filefrag -v` sur le fichier creux du lab : tu verras concrètement les
  extents alloués et les trous.
