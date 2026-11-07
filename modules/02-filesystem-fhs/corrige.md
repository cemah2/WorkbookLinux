<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Partie I — Fondamentaux du shell et du système de fichiers › **Module 02** · corrigé  
[← Module 01](../01-shell-bases/corrige.md) · [Énoncé](README.md) · [Module 03 →](../03-permissions/corrige.md)

> [!TIP]
> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, pas avant. Chaque identifiant renvoie à son énoncé.
<!-- nav:fin -->

# Module 02 — Corrigé

## 2.3 Quiz — QCM

<a id="q2-1"></a>**[Q2.1](README.md#q2-1)** — *Où ranger les binaires d'une appli tierce auto-contenue et les CSV
qu'elle publie aux clients ?*

**Réponse : b)** binaires dans `/opt/factura/bin`, CSV dans `/srv/factura/exports`.

> [!NOTE]
> **Pourquoi**
>
> Le FHS répartit selon **qui écrit** et **pour qui**, pas selon le confort du moment.
>
> * `/opt` est réservé aux « paquets logiciels additionnels », c'est-à-dire aux
>   produits tiers livrés en bloc, avec leur propre arborescence interne. Un éditeur
>   qui livre un tar auto-contenu est exactement ce cas : un répertoire par produit,
>   `/opt/factura/`, et l'OS n'y touchera jamais.
> * `/srv` contient les **données servies par cet hôte à des tiers** : pages web,
>   dépôts, exports téléchargeables. C'est précisément le rôle des CSV publiés via
>   nginx. Le FHS a créé `/srv` pour éviter que chacun invente son `/var/www`, son
>   `/home/www` ou son `/data`.
>
> `/usr/bin` est la propriété du gestionnaire de paquets : y déposer un fichier
> t'expose à ce qu'un `apt install` l'écrase ou à ce qu'un `dpkg --verify` hurle.
> `/var/lib/factura` est le bon endroit pour l'**état interne** (base, index), pas
> pour des fichiers destinés à des clients externes.

> [!WARNING]
> **Piège**
>
> La réponse d) est séduisante : « c'est auto-contenu, tout dans `/opt` ». Elle casse
> deux choses. D'abord les exports finissent hors de `/srv`, donc hors du périmètre
> de sauvegarde et de la politique de rétention des données servies. Ensuite les
> journaux et la base se retrouvent dans `/opt`, qui est souvent monté en lecture
> seule ou sur un volume non sauvegardé. Le compromis réel en production : binaires
> et bibliothèques dans `/opt`, **tout ce qui varie** ailleurs, avec des liens
> symboliques depuis `/opt` si le produit exige une arborescence rigide.

---

<a id="q2-2"></a>**[Q2.2](README.md#q2-2)** — *Quelle information n'est pas dans l'inode ?*

**Réponse : b) le nom du fichier**

> [!NOTE]
> **Pourquoi**
>
> L'inode est la fiche d'identité du fichier : type, permissions, UID, GID, taille,
> compteur de liens, les trois horodatages (`atime`, `mtime`, `ctime`) et les
> pointeurs vers les blocs de données. Il ne porte **aucun nom**.
>
> Le nom vit dans le **répertoire**, qui n'est qu'un fichier particulier contenant
> des paires `(nom, numéro d'inode)`. C'est ce découplage qui explique tout le reste
> du module :
>
> * un même inode peut avoir plusieurs noms — ce sont les liens physiques ;
> * renommer un fichier (`mv` dans le même système de fichiers) ne touche pas au
>   contenu ni à l'inode : on réécrit une entrée de répertoire ;
> * supprimer un nom n'est pas supprimer un fichier, d'où `unlink()` comme nom de
>   l'appel système ;
> * les permissions sur un fichier sont dans son inode, mais le droit de le
>   **supprimer** dépend des permissions du répertoire, pas du fichier.
>
> Vérification immédiate : `stat fichier` affiche tout sauf le nom… qu'il n'affiche
> que parce que tu le lui as fourni en argument.

---

<a id="q2-3"></a>**[Q2.3](README.md#q2-3)** — *`ln rapport.txt copie.txt` puis `rm rapport.txt`, puis `cat copie.txt`.*

**Réponse : b)** le contenu s'affiche normalement.

> [!NOTE]
> **Pourquoi**
>
> `ln` crée un deuxième nom pour le **même inode** : le compteur de liens passe de
> 1 à 2. `rm` appelle `unlink()`, qui retire l'entrée `rapport.txt` du répertoire et
> décrémente le compteur, qui tombe à 1. Comme il n'est pas à 0, le noyau ne libère
> ni l'inode ni les blocs : `copie.txt` désigne toujours le même contenu.
>
> ```console
> $ ln rapport.txt copie.txt
> $ stat -c '%i %h %n' rapport.txt copie.txt
> 794716 2 rapport.txt
> 794716 2 copie.txt
> $ rm rapport.txt
> $ stat -c '%i %h %n' copie.txt
> 794716 1 copie.txt
> ```
>
> Les deux noms sont strictement équivalents : il n'y a pas d'« original » et de
> « lien ». Rien dans le système de fichiers ne dit lequel a été créé en premier.

> [!WARNING]
> **Piège**
>
> Corollaire de sécurité : donner un lien physique vers un fichier sensible, c'est
> en donner une copie permanente. Retirer le fichier « original » ne retire rien du
> tout tant que l'autre nom existe, et le propriétaire du répertoire d'origine ne
> voit plus rien. C'est pour cette raison que les
> liens physiques vers des fichiers qu'on ne possède pas (et qu'on ne peut pas modifier) sont refusés par
> `fs.protected_hardlinks=1`, actif par défaut sur Ubuntu comme sur Rocky.

---

<a id="q2-4"></a>**[Q2.4](README.md#q2-4)** — *Lien physique entre `/var/lib/factura/factura.db` et `/srv/appdata`,
qui est un système de fichiers distinct.*

**Réponse : b)** `ln: failed to create hard link: Invalid cross-device link`

> [!NOTE]
> **Pourquoi**
>
> Un lien physique est une entrée de répertoire qui pointe vers un **numéro
> d'inode**. Ce numéro n'a de sens qu'à l'intérieur d'un seul système de fichiers :
> l'inode 794716 de `/dev/vda1` et l'inode 794716 de `/dev/loop0` sont deux objets
> sans aucun rapport. Il n'existe aucun moyen d'exprimer « l'inode 794716 de
> l'autre volume » dans une entrée de répertoire. Le noyau refuse donc l'opération
> avec `EXDEV` (errno 18), affiché `Invalid cross-device link`.
>
> ```console
> $ ln arbo/uploads/photo1.jpg /srv/appdata/incoming/photo1.jpg
> ln: failed to create hard link '/srv/appdata/incoming/photo1.jpg'
>  => 'arbo/uploads/photo1.jpg': Invalid cross-device link
> ```
>
> C'est la même erreur qui explique pourquoi `mv` est instantané dans un système de
> fichiers (simple renommage) et lent entre deux (copie réelle puis suppression).
>
> Le lien symbolique, lui, ne contient qu'un **chemin** : une chaîne de caractères
> résolue à chaque accès par le noyau. Un chemin traverse tous les montages, donc
> `ln -s` fonctionne toujours.

---

<a id="q2-5"></a>**[Q2.5](README.md#q2-5)** — *`df` dit 98 %, `du` dit 2,1 Go sur une partition de 20 Go. Deux causes
plausibles.*

**Réponses : a) et c)**

> [!NOTE]
> **Pourquoi**
>
> `df` interroge le **superbloc** du système de fichiers : il lit un compteur de
> blocs libres tenu par le noyau. `du` parcourt l'**arborescence** et additionne ce
> qu'il trouve en suivant les noms. Tout ce qui occupe des blocs sans être
> atteignable par un nom crée un écart.
>
> a) Un fichier supprimé qu'un processus tient encore ouvert : plus d'entrée de
> répertoire (donc invisible pour `du`), mais compteur de liens à 0 avec un
> descripteur vivant, donc blocs non libérés (donc compté par `df`). C'est le cas
> le plus fréquent, et de très loin, sur un serveur d'applications.
>
> b) Un montage qui masque des fichiers : si des données ont été écrites dans
> `/var/log` **avant** qu'un volume ne soit monté dessus, elles existent toujours
> sur le système de fichiers parent, cachées sous le point de montage. `du /var`
> ne les voit pas puisqu'il parcourt ce qui est monté ; `df /``var` les compte. On les
> révèle en montant la partition parente ailleurs, ou avec un bind mount de `/``var`.
>
> c) est faux : `du` compte les fichiers cachés, il ne fait aucun tri sur le nom.
> d) est faux et inversé : c'est `du --apparent-size` qui gonfle les fichiers creux ;
> `df` et `du` par défaut comptent des **blocs réellement alloués**.

> [!WARNING]
> **Piège**
>
> Troisième cause à connaître, hors QCM : les blocs réservés à root. Par défaut,
> `mkfs.ext4` met 5 % de côté (`-m 5`) pour que root puisse encore intervenir sur un
> disque plein et pour limiter la fragmentation. Sur un volume de données de 4 To, ce
> sont 200 Go invisibles pour les utilisateurs. `tune2fs -m 1 /dev/sdb1` ajuste la
> réserve à chaud, sans démontage.

---

<a id="q2-6"></a>**[Q2.6](README.md#q2-6)** — *Que liste `lsof +L1` ?*

**Réponse : b)** les fichiers ouverts dont le nombre de liens est inférieur à 1,
donc supprimés.

> [!NOTE]
> **Pourquoi**
>
> `+L` filtre sur le **compteur de liens** (`nlink`) des fichiers ouverts. `+L1`
> signifie « montre-moi les fichiers ouverts dont nlink est inférieur à 1 », donc à
> 0 : plus aucun nom ne les désigne, mais un processus les tient ouverts.
>
> ```console
> # lsof -nP +L1 /srv/appdata
> COMMAND   PID USER FD TYPE DEVICE  SIZE/OFF NLINK NODE NAME
> facturad 8600 root  3w  REG    7,0 228589605     0   13 /srv/appdata/
>                                                  ingest.dat (deleted)
> ```
>
> Les colonnes utiles : `PID` (qui tient le fichier), `FD` (quel descripteur, ici 3
> en écriture), `SIZE/OFF` (combien d'octets sont immobilisés), `NLINK` à 0, et le
> chemin d'origine suivi de `(deleted)`.
>
> Sans argument de chemin, `lsof +L1` balaie tout le système, ce qui est lent mais
> exhaustif. Avec un point de montage en argument, on cible le système de fichiers
> qui pose problème. L'équivalent sans `lsof` :
> `ls -l /proc/*/fd 2>/dev/null | grep deleted`.

---

<a id="q2-7"></a>**[Q2.7](README.md#q2-7)** — *`find /var/log -type f -mtime +7` le 18 septembre à 14 h.*

**Réponse : b)** ceux modifiés avant le 10 septembre 14 h.

> [!NOTE]
> **Pourquoi**
>
> `-mtime n` travaille en tranches de 24 heures **entières**, en partant de l'instant
> courant, et la partie fractionnaire est **tronquée**. Un fichier est dans la
> tranche `n` si son âge est compris entre `n × 24 h` et `(n+1) × 24 h`.
>
> `-mtime +7` signifie donc « tranche strictement supérieure à 7 », soit un âge d'au
> moins 8 × 24 h = 192 heures. Le 18 septembre à 14 h, cela vise tout ce qui n'a pas
> été modifié depuis le **10 septembre 14 h**, et non le 11.
>
> ```text
> maintenant ------ -24h ------ -48h ... ------ -168h ------ -192h ------>
>              tranche 0     tranche 1        tranche 6    tranche 7
> -mtime +7 = tranches 8, 9, 10...  donc plus vieux que 192 h
> ```
>
> Retiens la règle de survie : `+7` = plus vieux que 8 jours, pas 7. Quand la
> précision compte, préfère une référence explicite :
>
> ```bash
> touch -d '2026-09-11 14:00' /tmp/repere
> find /var/log -type f ! -newer /tmp/repere
> ```
>
> `-mmin` fonctionne pareil, en minutes. Et `-mtime 7` (sans signe) ne remonte que
> la tranche exacte : rarement ce qu'on veut.

---

<a id="q2-8"></a>**[Q2.8](README.md#q2-8)** — *`-exec gzip {} \;` contre `-exec gzip {} +` sur 40 000 fichiers.*

**Réponse : b)** la première lance 40 000 processus, la seconde quelques-uns.

> [!NOTE]
> **Pourquoi**
>
> `\;` demande à `find` d'exécuter la commande **une fois par fichier trouvé**, en
> remplaçant `{}` par ce seul fichier. 40 000 `fork()` + `exec()`, chacun avec le
> coût de chargement du binaire et de son édition de liens dynamique.
>
> `+` demande à `find` d'**accumuler** les chemins et de les passer en une seule
> ligne de commande, jusqu'à la limite `ARG_MAX` du système (souvent ~2 Mo), puis de
> recommencer. On passe de 40 000 exécutions à une poignée. C'est le même mécanisme
> que `xargs`, intégré à `find`, et sans le problème de découpage des noms puisque
> `find` passe les arguments directement, sans passer par un shell.
>
> Ordre de grandeur mesurable sur `lab-web` : compresser 10 000 petits fichiers prend
> une trentaine de secondes avec `\;` et deux ou trois secondes avec `+`.
>
> Quand `\;` reste obligatoire : quand la commande n'accepte qu'un seul argument,
> quand `{}` doit apparaître deux fois (`-exec mv {} {}.bak \;` — qui ne marche
> d'ailleurs pas avec `+`), ou quand tu veux le code retour fichier par fichier.

> [!WARNING]
> **Piège**
>
> `-exec ... {} +` impose que `{}` soit le **dernier** élément avant le `+`. Écrire
> `-exec cp {} /sauvegarde +` est refusé par `find` : dans ce cas on utilise
> `-exec cp -t /sauvegarde {} +`, avec l'option `-t` de `cp` qui place la destination
> en premier. Même astuce pour `mv -t`.

---

<a id="q2-9"></a>**[Q2.9](README.md#q2-9)** — *`find /var/log -name *.log` sans quotes.*

**Réponse : b)** le shell développe `*.log` avant que `find` ne le voie.

> [!NOTE]
> **Pourquoi**
>
> Le globbing est fait par le **shell**, avant l'exécution de `find`, et il porte sur
> le **répertoire courant**, pas sur `/var/log`. Trois scénarios :
>
> 1. le répertoire courant ne contient aucun `.log` : le motif n'ayant pas de
>    correspondance est passé littéralement, `find` reçoit `-name *.log` et tout
>    fonctionne — par accident ;
> 2. il contient exactement un `.log`, disons `app.log` : `find` reçoit
>    `-name app.log` et ne remonte que les fichiers portant ce nom précis. Aucune
>    erreur, un résultat faux, silencieusement ;
> 3. il en contient plusieurs : `find` reçoit `-name app.log error.log` et échoue
>    avec `find: paths must precede expression: 'error.log'`.
>
> C'est le cas 2 qui fait des dégâts, parce qu'il ne se remarque pas. La règle est
> simple et absolue : **tout motif destiné à `find` se met entre guillemets simples**,
> `find /var/log -name '*.log'`.

---

<a id="q2-10"></a>**[Q2.10](README.md#q2-10)** — *Tous les `.js` sauf ceux de `node_modules`.*

**Réponse : a)** `find . -name node_modules -prune -o -name '*.js' -print`

> [!NOTE]
> **Pourquoi**
>
> `find` évalue une **expression booléenne** de gauche à droite pour chaque fichier
> rencontré, avec un `-a` (et) implicite entre deux tests consécutifs, et
> court-circuit comme en C.
>
> `-prune` est une action qui renvoie vrai et qui dit à `find` : « ne descends pas
> dans ce répertoire ». La structure canonique est donc :
>
> ```text
> find . -name node_modules -prune -o -name '*.js' -print
>        \______ vrai pour node_modules _____/  \___ le reste ___/
> ```
>
> Pour `node_modules` : le premier test est vrai, `-prune` s'exécute (répertoire non
> parcouru) et renvoie vrai, donc le `-o` court-circuite : le second membre n'est
> jamais évalué. Pour tout autre fichier : le premier test est faux, `-o` évalue le
> second membre, `-name '*.js'` puis `-print`.
>
> Le `-print` explicite est **obligatoire** ici : dès qu'une action apparaît dans
> l'expression, `find` n'ajoute plus son `-print` implicite. Sans lui, la commande
> n'affiche rien.
>
> L'alternative moins efficace est `! -path '*/node_modules/*'` : elle donne le bon
> résultat mais `find` descend quand même dans l'arborescence et la filtre après
> coup. Sur un `node_modules` de 200 000 fichiers, l'écart se compte en secondes.

---

<a id="q2-11"></a>**[Q2.11](README.md#q2-11)** — *`ls -lh` dit 2,0G, `du -h` dit 4,0M.*

**Réponse : b)** c'est un fichier creux (*sparse file*).

> [!NOTE]
> **Pourquoi**
>
> La taille affichée par `ls` est celle déclarée dans l'inode : la position du
> dernier octet écrit. `du` additionne les **blocs réellement alloués**, que l'inode
> compte aussi (champ `%b` de `stat`).
>
> Un fichier creux naît quand on écrit à une position éloignée sans avoir rempli
> l'intervalle, typiquement avec `truncate -s 2G` ou un `lseek()` suivi d'une
> écriture. Le système de fichiers n'alloue alors aucun bloc pour les « trous » ; à
> la lecture, il renvoie des zéros fabriqués à la volée.
>
> ```console
> $ stat -c 'taille=%s blocs512=%b' disque-vm.img
> taille=2147483648 blocs512=8192
> $ du -h --apparent-size disque-vm.img ; du -h disque-vm.img
> 2,0G	disque-vm.img
> 4,0M	disque-vm.img
> ```
>
> Cas courants : images de disques de machines virtuelles (`qcow2` en mode preallocation
> `off`, images raw créées par `truncate`), fichiers de base de données
> pré-dimensionnés, `/var/log/lastlog` — qui annonce couramment plusieurs gigaoctets
> pour quelques dizaines de kilo-octets réels.

> [!WARNING]
> **Piège**
>
> Ce qui casse en production : `cp` sans option détecte les trous depuis coreutils 8
> (`--sparse=auto`) mais **pas dans tous les cas** ; `tar` sans `-S` matérialise les
> zéros et fabrique une archive de 2 Go ; `rsync` sans `-S` fait pareil sur la
> destination, et `cat fichier > copie` remplit toujours les trous. Résultat
> classique : une sauvegarde qui échoue par manque de place alors que la source
> « ne fait que 4 Mo ». Retiens `tar -S`, `rsync -S`, `cp --sparse=always`.

---

<a id="q2-12"></a>**[Q2.12](README.md#q2-12)** — *`/proc/meminfo` fait 0 octet mais `cat` affiche 50 lignes.*

**Réponse : b)** `/proc` est virtuel, le contenu est généré à la lecture.

> [!NOTE]
> **Pourquoi**
>
> `procfs` n'est pas un système de fichiers de stockage : c'est une interface. Chaque
> « fichier » est une paire de fonctions noyau appelées à l'ouverture et à la
> lecture. Comme rien n'est stocké, le noyau ne peut pas annoncer de taille à
> l'avance : il renvoie 0, et c'est parfaitement légal — une lecture peut retourner
> des octets même quand `stat` annonce 0.
>
> Conséquences pratiques :
>
> * `/proc` et `/sys` n'occupent **aucun** espace disque et n'apparaissent pas dans
>   un `du` utile (on les exclut avec `-xdev` ou `du -x`) ;
> * le contenu est un instantané cohérent au moment de la lecture : deux `cat`
>   successifs de `/proc/loadavg` donnent des valeurs différentes ;
> * certains fichiers sont écrivables et déclenchent une action du noyau
>   (`/proc/sys/vm/drop_caches`, `/sys/block/sda/device/rescan`) ;
> * copier `/proc` avec `cp -a` ou l'inclure dans un `tar` n'a aucun sens et peut
>   bloquer indéfiniment sur des fichiers qui ne renvoient jamais EOF.
>
> Le même mécanisme vaut pour `/sys` (sysfs), `/dev` (devtmpfs) et les cgroups.

---

<a id="q2-13"></a>**[Q2.13](README.md#q2-13)** — *Où va le fichier de pid ? Deux réponses correctes.*

**Réponses : a) et b)**

> [!NOTE]
> **Pourquoi**
>
> `/run` est un `tmpfs` monté très tôt au démarrage et destiné à l'**état
> d'exécution** : pid, sockets unix, verrous, fichiers de travail des démons. Il est
> en RAM, donc vidé à chaque redémarrage — ce qui est exactement ce qu'on veut d'un
> pid : un pid survivant à un reboot est un mensonge qui fait échouer les scripts de
> démarrage.
>
> `/var/run` est aujourd'hui un **lien symbolique** vers `/run` sur toutes les
> distributions modernes (Debian depuis Wheezy, Ubuntu depuis 11.10, RHEL depuis 7). Écrire dans
> `/var/run/factura/` revient donc physiquement au même endroit ; la réponse b) est
> vraie. Mais le chemin canonique à écrire dans les scripts neufs est `/run`.
>
> En pratique, on ne crée pas ce répertoire à la main : `/run` étant vidé au
> démarrage, un `mkdir` posé une fois disparaît au reboot suivant. On délègue à
> systemd :
>
> ```ini
> [Service]
> RuntimeDirectory=factura
> RuntimeDirectoryMode=0755
> ```
>
> systemd crée `/run/factura` avant le démarrage, avec le bon propriétaire, et le
> supprime à l'arrêt du service. L'alternative hors systemd est un fichier
> `/usr/lib/tmpfiles.d/factura.conf` traité par `systemd-tmpfiles`.
>
> c) est faux : `/tmp` est mondialement inscriptible, donc sujet aux attaques par
> lien symbolique, et souvent nettoyé en cours de fonctionnement. d) est faux :
> faire survivre un pid au redémarrage est un bug, pas une fonctionnalité.

---

<a id="q2-14"></a>**[Q2.14](README.md#q2-14)** — *Ligne `ls -l` commençant par `s`.*

**Réponse : c)** une socket unix.

> [!NOTE]
> **Pourquoi**
>
> Le premier caractère de `ls -l` donne le type :
>
> ```text
> -  fichier ordinaire      d  répertoire        l  lien symbolique
> s  socket unix            p  tube nommé (FIFO) b  périphérique bloc
> c  périphérique caractère
> ```
>
> `.s.PGSQL.5432` est la socket de domaine unix de PostgreSQL : c'est par elle que
> `psql` se connecte en local, sans passer par TCP. Sa taille est toujours 0 car
> aucune donnée n'y est stockée : c'est un point de rendez-vous entre processus,
> identifié par un chemin dans le système de fichiers.
>
> La distinction avec le FIFO (`p`) mérite d'être sue en entretien : un FIFO est un
> canal unidirectionnel entre deux processus, créé par `mkfifo`, qui se lit et
> s'écrit comme un fichier. Une socket unix est bidirectionnelle, supporte plusieurs
> clients simultanés, gère des messages et permet même de transmettre des
> descripteurs de fichiers entre processus. Un FIFO s'ouvre avec `open()`, une socket
> avec `connect()` : c'est pour cela que `cat .s.PGSQL.5432` échoue avec
> `No such device or address`.

---

<a id="q2-15"></a>**[Q2.15](README.md#q2-15)** — *Lien relatif `conf -> ../conf-prod` déplacé de `/opt/app` vers
`/etc/app`.*

**Réponse : b)** le lien pointe désormais vers `/etc/conf-prod`, qui n'existe pas.

> [!NOTE]
> **Pourquoi**
>
> Un lien symbolique ne contient qu'une **chaîne de caractères**. Le noyau la résout
> au moment de l'accès, et un chemin relatif est résolu par rapport au **répertoire
> qui contient le lien**, jamais par rapport au répertoire courant de l'utilisateur
> ni par rapport à l'endroit où le lien a été créé.
>
> ```console
> $ readlink /etc/app/conf
> ../conf-prod
> $ readlink -f /etc/app/conf
> /etc/conf-prod
> $ ls -l /etc/app/conf/
> ls: cannot access '/etc/app/conf/': No such file or directory
> ```
>
> D'où la règle de choix :
>
> * **relatif** quand le lien et sa cible font partie de la même arborescence
>   déplaçable ensemble (`current -> releases/2026-09-18` à l'intérieur de
>   `/srv/www`, un `chroot`, une image de conteneur) ;
> * **absolu** quand la cible est un point fixe du système et que le lien peut
>   bouger, ou quand le lien traverse un point de montage.
>
> `readlink` donne la chaîne brute, `readlink -f` la résolution complète : les deux
> ensemble diagnostiquent n'importe quel lien en dix secondes.

---

<a id="q2-16"></a>**[Q2.16](README.md#q2-16)** — *`No space left on device` mais `df -h` affiche 52 %.*

**Réponse : b)** les inodes sont épuisés, confirmé par `df -i`.

> [!NOTE]
> **Pourquoi**
>
> Un système de fichiers ext4 a deux ressources finies et indépendantes : les blocs
> de données et les **inodes**, dont le nombre est fixé définitivement au formatage
> (un inode par fichier, répertoire, lien symbolique ou socket). `mkfs.ext4` en
> alloue un pour environ 16 Kio de volume par défaut. Un volume rempli de très petits
> fichiers — spool de mails, cache de vignettes, sessions PHP, journaux applicatifs
> en JSON — épuise ses inodes bien avant ses blocs.
>
> Le noyau renvoie alors `ENOSPC`, le même code que pour un disque plein, d'où le
> message trompeur. `touch` et `mkdir` échouent, alors qu'écrire **dans un fichier
> existant** continue de fonctionner : c'est la signature du problème.
>
> ```console
> $ df -h /srv/appdata
> /dev/loop0  224M  110M  103M  52% /srv/appdata
> $ df -i /srv/appdata
> /dev/loop0  65536  65536  0  100% /srv/appdata
> ```
>
> Prévention : `mkfs.ext4 -i 8192` (ou `-N <nombre>`) au formatage pour les volumes à
> petits fichiers, ou XFS, qui alloue ses inodes dynamiquement et ne connaît pas ce
> plafond. Après coup, sur ext4, on ne peut **pas** augmenter le nombre d'inodes :
> il faut sauvegarder, reformater, restaurer.
>
> a) est plausible dans l'absolu, mais les quotas sont rarement activés et
> donneraient `EDQUOT` / `Disk quota exceeded`. c) donnerait `Read-only file
> system`. d) ne s'applique qu'à root et se verrait dans `df`.

---

<a id="q2-17"></a>**[Q2.17](README.md#q2-17)** — *`locate` ne trouve pas un fichier créé il y a dix minutes.*

**Réponse : b)** `locate` lit une base indexée, mise à jour périodiquement.

> [!NOTE]
> **Pourquoi**
>
> `locate` (aujourd'hui `plocate` sur Ubuntu 24.04) ne parcourt pas le disque : il
> interroge une base construite par `updatedb`, déclenchée une fois par jour par
> `plocate-updatedb.timer`. Un fichier créé après le dernier passage est invisible.
>
> C'est le compromis assumé : une réponse en quelques millisecondes sur des millions
> de chemins, contre une vision décalée de quelques heures.
>
> ```bash
> locate -b '\factura.conf'   # -b : sur le nom de base, \ : motif exact
> sudo updatedb               # réindexe maintenant
> find / -name factura.conf 2>/dev/null   # la vérité, mais lent
> ```
>
> Ce qu'il faut savoir en plus : `updatedb` respecte `/etc/updatedb.conf`, qui exclut
> par défaut `/tmp`, `/var/spool`, les montages réseau et les `.git` sur certaines
> distributions. Un fichier peut donc être absent **définitivement** de la base sans
> que ce soit un problème de fraîcheur. Enfin, la base est construite par root mais `plocate` (comme `mlocate` avant lui) ne montre que les chemins dont l'utilisateur courant peut parcourir les répertoires parents.

> [!WARNING]
> **Piège**
>
> Ne pas confondre les trois outils de localisation de commandes :
> `which` cherche un exécutable dans `PATH` (et ignore alias, fonctions et builtins) ;
> `whereis` cherche binaire, source et page de manuel dans une liste de répertoires
> standards ; `type -a` est le seul qui dise ce que le shell va **réellement**
> exécuter. `locate`, lui, ne concerne pas les commandes mais tous les fichiers.

---

<a id="q2-18"></a>**[Q2.18](README.md#q2-18)** — *`/tmp` est un `tmpfs` de 1 004 856 Kio. Deux conséquences.*

**Réponses : b) et c)**

> [!NOTE]
> **Pourquoi**
>
> Un `tmpfs` vit en mémoire virtuelle : pages de RAM, avec débordement possible dans
> le swap. Deux conséquences directes et vraies :
>
> * b) le contenu occupe de la RAM. Un fichier de 800 Mio dans `/tmp` sur une VM de
>   2 Go de RAM, c'est 800 Mio de moins pour les applications — et sur une machine
>   sans swap, le `tmpfs` peut déclencher l'OOM killer ;
> * c) il est reconstruit vide à chaque démarrage, puisque rien n'est écrit sur un
>   support persistant.
>
> a) est fausse : un `tmpfs` ne « déborde » jamais sur le disque. La taille annoncée, ici environ 980 Mio,
> **est** une limite dure : écrire 2 Gio échoue avec `No space left on
> device`, exactement comme sur une partition pleine. Seul le swap peut accueillir des pages de `tmpfs`, et ça ne change pas la limite. Retiens surtout que `size=` est
> ajustable à chaud : `mount -o remount,size=2G /tmp`.
>
> b) est fausse : `/tmp` étant un système de fichiers distinct, son occupation
> n'apparaît jamais dans la ligne de `/` de `df`, et `du -x /` ne la compte pas.

---

## 2.4 Quiz — questions ouvertes

<a id="qo2-1"></a>**[QO2.1](README.md#qo2-1)** — *Qu'est-ce qu'un inode, que contient-il, que fait `rm` ?*

**Réponse attendue**

Un inode est la structure de données qui **est** le fichier, du point de vue du
système de fichiers. Il contient :

| Dans l'inode | Pas dans l'inode |
|---|---|
| type, permissions, UID, GID | le nom |
| taille, nombre de blocs alloués | le chemin |
| compteur de liens (`nlink`) | le contenu lui-même |
| `atime`, `mtime`, `ctime` | — |
| pointeurs / extents vers les blocs | — |

Le nom est stocké dans le répertoire, qui est une table `(nom, numéro d'inode)`.

`rm` n'efface rien : il appelle `unlink()`, qui retire une entrée de répertoire et
décrémente `nlink`. Les blocs sont rendus au système de fichiers quand **deux**
conditions sont réunies simultanément :

1. `nlink == 0` — plus aucun nom ne désigne l'inode ;
2. plus aucun processus n'a de descripteur ouvert dessus.

Tant que l'une des deux manque, l'espace reste consommé. C'est ce second point qui
produit le cas « `df` plein, `du` vide » : le noyau maintient un compteur de
références interne (les descripteurs ouverts) en plus du compteur de liens du
disque.

> [!NOTE]
> **Pourquoi**
>
> Ce modèle explique d'un coup une série de comportements qui semblent sans rapport :
>
> * `mv` dans un même système de fichiers est instantané quelle que soit la taille
>   du fichier : on réécrit une entrée de répertoire, on ne bouge pas un octet de
>   données ;
> * on peut supprimer un fichier en cours d'utilisation sans faire planter le
>   programme qui l'utilise — sous Windows, l'appel échoue ;
> * les mises à jour de paquets remplacent `/usr/bin/nginx` pendant que l'ancien
>   binaire tourne encore, d'où le redémarrage nécessaire (un `reload` relit la configuration mais garde l'ancien binaire en mémoire) ;
> * `ctime` change quand on modifie l'inode (permissions, propriétaire, nombre de
>   liens), pas seulement le contenu : ce n'est **pas** une date de création. La date
>   de création (`crtime`, `btime`) existe en ext4 mais n'est pas exposée par `stat`
>   sur tous les noyaux : `stat -c %w` affiche souvent `-`.

---

<a id="qo2-2"></a>**[QO2.2](README.md#qo2-2)** — *Entretien : `df` dit 100 % sur `/var`, `du -sh /var` dit 3 Go.*

**Réponse attendue**

Diagnostic en trois temps.

1. **Confirmer l'écart et le localiser.**

```bash
df -h /var                  # 20G utilisés sur 20G
du -sh -x /var              # 3,0G  -> écart de 17 Go
```

2. **Chercher les fichiers supprimés encore ouverts**, cause numéro un :

```bash
sudo lsof -nP +L1 /var
sudo lsof -nP +L1 | awk '$8 == 0 { s += $7 } END { print s/1024/1024 " Mio" }'
```

On obtient le processus, son pid, le descripteur et la taille immobilisée. À
défaut de `lsof` : `ls -l /proc/*/fd 2>/dev/null | grep '(deleted)'`.

3. **Libérer sans redémarrer** : vider le fichier à travers son descripteur.

```bash
sudo truncate -s 0 /proc/12345/fd/3
# ou :  sudo sh -c ': > /proc/12345/fd/3'
```

L'espace est rendu immédiatement, le processus continue d'écrire, aucune coupure.
Si l'application relit ce qu'elle a écrit, préférer un `systemctl reload` qui lui
fait rouvrir ses fichiers.

Si l'écart persiste, deuxième cause : un montage qui masque des fichiers.

```bash
findmnt -T /var/log
# bind non récursif de /var : les sous-montages (/var/log) n'y sont pas repris
sudo mkdir -p /mnt/verif && sudo mount --bind /var /mnt/verif
sudo du -sh /mnt/verif/log          # ce qui est caché sous le point de montage
sudo umount /mnt/verif
```

> [!NOTE]
> **Pourquoi**
>
> Le point à faire passer en entretien est la distinction de source d'information :
> `df` lit le superbloc (compteurs du système de fichiers), `du` parcourt les entrées
> de répertoire. Tout ce qui a des blocs mais pas de nom est invisible pour l'un et
> compté par l'autre.
>
> La finesse qui fait la différence, c'est le correctif : beaucoup répondent
> « redémarrer le service », ce qui marche mais coupe. La bonne réponse est
> d'intervenir via `/proc/<pid>/fd/<n>`, qui est un lien vers l'inode lui-même : le
> tronquer libère les blocs sans toucher au descripteur du processus.

> [!WARNING]
> **Piège**
>
> Le piège classique en intervention : `rm` sur le gros fichier de log avant d'avoir
> compris. On perd la journalisation en cours, on ne récupère rien, et on transforme
> un problème diagnosticable en problème invisible. L'ordre est toujours :
> `lsof` d'abord, action ensuite.

---

<a id="qo2-3"></a>**[QO2.3](README.md#qo2-3)** — *Lien physique contre lien symbolique, et le cas `current -> releases/…`.*

**Réponse attendue**

| Critère | Lien physique | Lien symbolique |
|---|---|---|
| Ce qui est stocké | un numéro d'inode | un chemin, en texte |
| Cible supprimée | contenu intact | lien cassé, `ENOENT` |
| Traverse un montage | non (`EXDEV`) | oui |
| Sur un répertoire | interdit | autorisé |
| Coût | aucun bloc de données | un inode (parfois inline) |
| Visible dans `ls -l` | indistinguable d'un fichier | `l` et `-> cible` |

Pour un déploiement `releases/` + `current`, c'est le **lien symbolique**, et il
n'y a pas de débat : on ne peut pas faire de lien physique sur un répertoire, et
on veut pouvoir basculer de version de façon atomique.

```bash
cd /srv/www
ln -sfn releases/2026-09-18 current     # relatif, depuis /srv/www
```

Lien **relatif**, parce que `current` et `releases/` font partie de la même
arborescence : on peut déplacer ou monter `/srv/www` ailleurs, copier l'ensemble
dans une image, ou le servir depuis un chroot, sans rien casser.

> [!NOTE]
> **Pourquoi**
>
> Les trois options de `ln` à connaître pour ce cas :
>
> * `-s` : symbolique ;
> * `-f` : remplace la cible existante ;
> * `-n` : **ne suit pas** le lien existant. Sans `-n`, si `current` est déjà un lien
>   vers un répertoire, `ln -sf releases/X current` crée
>   `current/X -> releases/X` **dans** l'ancienne release au lieu de remplacer le
>   lien. C'est l'un des bugs de script de déploiement les plus répandus.
>
> L'atomicité du remplacement dépend de l'outil : le `ln` de GNU coreutils 9.4 (Ubuntu 24.04) crée un lien temporaire puis le renomme, mais d'autres implémentations (BusyBox, anciens coreutils) font `unlink()`
> puis `symlink()`, avec une fenêtre pendant
> laquelle `current` n'existe pas. La méthode explicite, atomique partout :
>
> ```bash
> ln -sfn releases/2026-09-18 /srv/www/.current-tmp
> mv -T /srv/www/.current-tmp /srv/www/current    # rename(2), atomique
> ```

---

<a id="qo2-4"></a>**[QO2.4](README.md#qo2-4)** — *Entretien : 3 h du matin, `/` à 97 % en production.*

**Réponse attendue**

Démarche, dans l'ordre, sans jamais supprimer avant d'avoir compris.

```bash
# 1. cadrer : quel système de fichiers, combien de place manque
df -hT -x tmpfs -x devtmpfs -x squashfs
df -i                       # ne jamais oublier les inodes

# 2. écart df/du : y a-t-il des fichiers supprimés encore ouverts ?
sudo lsof -nP +L1 / | head

# 3. descendre par paliers, sans franchir de montage
sudo du -xh --max-depth=1 / | sort -h | tail
sudo du -xh --max-depth=1 /var | sort -h | tail
sudo ncdu -x /var           # si le temps le permet

# 4. les suspects habituels
journalctl --disk-usage
du -sh /var/cache/apt /var/lib/docker /var/log
find /var/log -type f -size +100M -printf '%s\t%p\n' | sort -rn | head
```

Actions, de la moins risquée à la plus risquée :

```bash
sudo journalctl --vacuum-size=200M         # réversible, sans impact service
sudo apt clean                             # cache re-téléchargeable
sudo truncate -s 0 /proc/<pid>/fd/<n>      # fichier supprimé encore ouvert
sudo truncate -s 0 /var/log/gros.log       # log ouvert : tronquer, pas rm
docker system prune -a                     # seulement si on sait ce qu'on jette
```

Ce que je m'interdis : `rm -rf` sur un chemin que je n'ai pas lu deux fois ;
supprimer un fichier de log qu'un processus tient ouvert ; toucher à
`/var/lib/mysql`, `/var/lib/postgresql` ou `/var/lib/docker/volumes` ; supprimer
un fichier creux « énorme » sans vérifier son occupation réelle ; agrandir le
volume avant d'avoir identifié la cause. Et je documente tout dans le ticket au
fur et à mesure, parce qu'à 3 h du matin la mémoire ment.

> [!NOTE]
> **Pourquoi**
>
> Ce qu'un recruteur écoute vraiment dans cette réponse : est-ce que le candidat
> **mesure avant d'agir**, est-ce qu'il pense aux inodes et pas seulement aux
> octets, est-ce qu'il connaît la différence entre `rm` et `truncate` sur un fichier
> ouvert, et est-ce qu'il sépare les actions réversibles des actions destructrices.
> Le `-x` de `du` est un détail qui compte : sans lui, on passe dix minutes à
> compter `/proc`, `/sys` et les volumes NFS montés ailleurs.

---

<a id="qo2-5"></a>**[QO2.5](README.md#qo2-5)** — *`-exec \;` contre `-exec +` contre `xargs -0`.*

**Réponse attendue**

| Forme | Processus lancés | Quand l'utiliser |
|---|---|---|
| `-exec cmd {} \;` | un par fichier | commande à un seul argument, `{}` répété, code retour par fichier |
| `-exec cmd {} +` | un par lot d'ARG_MAX | cas général, le plus simple et le plus sûr |
| `-print0 \| xargs -0 cmd` | un par lot, parallélisable | parallélisme (`-P`), pipeline complexe, commande construite dynamiquement |

```bash
find . -name '*.log' -exec gzip {} +                 # rapide, sûr
find . -name '*.log' -print0 | xargs -0 -P4 gzip     # 4 en parallèle
find . -name '*.conf' -exec cp {} {}.bak \;   # {} deux fois : \; requis
```

`find | xargs` sans `-print0` est un bug en attente : `xargs` découpe son entrée
sur les espaces, tabulations et sauts de ligne, et interprète les guillemets. Un
fichier nommé `audit ancien.log` devient deux arguments, `audit` et `ancien.log`.
Avec `gzip`, on obtient deux erreurs ; avec `rm`, on supprime un fichier
homonyme ailleurs. `-print0` sépare par l'octet nul, seul caractère interdit dans
un nom de fichier Unix, et `-0` dit à `xargs` de ne découper que là-dessus.

> [!NOTE]
> **Pourquoi**
>
> Détail qui fait la différence à l'usage : le **code de retour**. Avec `\;`, `find`
> ignore l'échec de chaque commande et sort en 0. Avec `+`, `find` sort en 1 si l'une
> des exécutions a échoué. `xargs` sort en 123 si l'une des commandes a échoué (code 1 à 125), 124
> si l'une est sortie en 255, 125 si l'une a été tuée par un signal. Dans un script avec `set -e`, ces codes
> changent complètement le comportement ; il faut les connaître avant de mettre un
> `find` dans une chaîne CI.
>
> Autre différence : avec `-exec`, `find` appelle `execve()` directement, sans shell.
> Aucun globbing, aucune expansion, aucune injection possible depuis un nom de
> fichier. Avec `xargs`, on passe par `xargs` qui, lui non plus, n'appelle pas de
> shell — sauf si on écrit `xargs sh -c '...'`, et là tout redevient possible, y
> compris l'injection depuis un nom de fichier hostile.

---

<a id="qo2-6"></a>**[QO2.6](README.md#qo2-6)** — *`/proc` et `/sys` : nature, différence, diagnostics.*

**Réponse attendue**

Ce sont deux systèmes de fichiers **virtuels** : aucun bloc sur disque, le contenu
est produit par le noyau à chaque lecture.

* `/proc` (procfs) : historiquement l'interface **processus**. Un répertoire par
  pid, plus un ensemble de fichiers globaux hérités (`meminfo`, `cpuinfo`,
  `loadavg`, `mounts`, `net/`), et `/proc/sys` pour les paramètres réglables du
  noyau (ce que manipule `sysctl`).
* `/sys` (sysfs) : l'interface **matériel et pilotes**, structurée et typée, une
  valeur par fichier. Périphériques bloc, réseau, alimentation, cgroups v2,
  modules.

Trois diagnostics qui n'existent que là :

```bash
ls -l /proc/1234/fd                  # quels fichiers ce processus tient ouverts
readlink /proc/1234/cwd              # depuis quel répertoire il tourne
tr '\0' ' ' < /proc/1234/cmdline     # sa vraie ligne de commande, non tronquée
cat /proc/1234/status | grep -i vm   # sa consommation mémoire détaillée
cat /proc/mounts                     # les montages vus par le noyau, sans mtab
cat /proc/meminfo                    # mémoire disponible réelle, pas "free"
```

Écriture dans `/sys`, cas concret : après ajout à chaud d'un disque sur une VM
Proxmox, le noyau ne le voit pas tant qu'on ne relance pas l'analyse du bus.

```bash
echo '- - -' | sudo tee /sys/class/scsi_host/host0/scan
cat /sys/block/sda/queue/rotational      # 0 = SSD, 1 = disque mécanique
echo 1 | sudo tee /sys/block/sdb/device/rescan
```

> [!NOTE]
> **Pourquoi**
>
> La raison d'être de `/proc/<pid>/fd` mérite d'être comprise : ce ne sont pas des
> copies, ce sont de vrais liens vers les inodes ouverts. On peut donc lire un
> fichier supprimé dont on n'a plus le nom :
>
> ```bash
> cp /proc/1234/fd/3 /var/tmp/recupere.log    # récupère un log effacé par erreur
> truncate -s 0 /proc/1234/fd/3               # ou le vide pour rendre l'espace
> ```
>
> C'est le seul moyen de récupérer un fichier supprimé sans outil de forensic, et ça
> ne marche que tant que le processus vit.

---

<a id="qo2-7"></a>**[QO2.7](README.md#qo2-7)** — *Pourquoi ne pas installer dans `/usr/bin` ?*

**Réponse attendue**

`/usr` appartient au gestionnaire de paquets. Sur Ubuntu, `dpkg` tient la liste
exacte du contenu de `/usr/bin` ; sur Rocky, `rpm` fait de même. Y déposer un
fichier à la main a trois conséquences concrètes :

1. une mise à jour du paquet qui porte le même nom écrase silencieusement le
   fichier — l'application « redevient » l'ancienne version sans prévenir ;
2. `dpkg -S /usr/bin/facturad` répond « no path found », donc plus personne ne sait
   d'où vient le binaire, ni comment le mettre à jour, ni s'il est encore utilisé ;
3. en cas de migration `/usr` fusionné, de passage en lecture seule ou d'image
   immuable, l'installation disparaît ou devient impossible.

Le bon emplacement dépend de l'origine :

| Origine du logiciel | Emplacement |
|---|---|
| paquet `.deb` / `.rpm` officiel | `/usr` (fait par le paquet, pas par toi) |
| compilé à la main (`make install`) | `/usr/local` |
| livré par un éditeur, auto-contenu | `/opt/<produit>` |
| données servies à des clients | `/srv/<service>` |

`/usr/local` est explicitement réservé par le FHS à l'administrateur local et
n'est jamais touché par le gestionnaire de paquets. Il respecte la même structure
interne (`bin`, `lib`, `share`, `etc`) et figure dans le `PATH` par défaut, ce qui
en fait l'endroit naturel pour un lien symbolique vers un binaire de `/opt`.

> [!NOTE]
> **Pourquoi**
>
> La combinaison qui marche en production : le produit reste groupé dans
> `/opt/factura/`, sa configuration part dans `/etc/factura/` (parce que c'est là que
> la regardent les outils de conformité, les sauvegardes et les collègues), son état
> dans `/var/lib/factura/`, ses logs dans `/var/log/factura/`, et un unique lien
> `/usr/local/bin/facturactl -> /opt/factura/bin/facturactl` rend la commande
> disponible pour tout le monde sans toucher au `PATH` de qui que ce soit.

---

<a id="qo2-8"></a>**[QO2.8](README.md#qo2-8)** — *Fichiers creux.*

**Réponse attendue**

Un fichier creux a une taille déclarée supérieure au nombre de blocs qui lui sont
réellement alloués. Les zones jamais écrites — les « trous » — ne consomment aucun
bloc ; à la lecture, le noyau renvoie des zéros.

* `ls -l` et `du --apparent-size` montrent la taille **déclarée** (champ `%s` de
  l'inode) ;
* `du` et `df` comptent les **blocs alloués** (champ `%b`).

On en produit sans le vouloir :

* `truncate -s 10G image.img` ou `dd seek=...` pour pré-dimensionner une image ;
* une base de données ou un hyperviseur qui pré-alloue en mode « lazy »
  (`qemu-img create -f raw`, `qcow2` sans preallocation) ;
* `/var/log/lastlog`, indexé par UID : avec un UID à 1 000 000 issu d'un annuaire
  LDAP, le fichier annonce plusieurs gigaoctets pour quelques kilo-octets réels ;
* un téléchargement repris par plages (`curl -C`, torrent) interrompu.

Comportement à la copie :

| Outil | Sans option | Avec option |
|---|---|---|
| `cp` | `--sparse=auto` : détecte souvent, pas toujours | `cp --sparse=always` |
| `tar` | remplit les trous : archive énorme | `tar -S` |
| `rsync` | recrée un fichier plein | `rsync -S` |
| `cat`, `dd` | remplissent toujours | `dd conv=sparse` |

> [!WARNING]
> **Piège**
>
> Le scénario classique : une VM de 40 Go dont le fichier disque n'occupe que 6 Go
> réels. La sauvegarde nocturne par `tar` sans `-S` produit 40 Go, remplit le volume
> de sauvegarde et échoue. Personne ne comprend, parce que `du -sh` sur la source
> affichait bien 6 Go. Vérification immédiate avant toute copie :
>
> ```bash
> du -h --apparent-size disque.img ; du -h disque.img
> filefrag -v disque.img | head       # montre les extents et les trous
> ```

---

## 2.5 Exercices guidés

<a id="e2-1"></a>**[E2.1](README.md#e2-1)** — *Inode, liens, taille, blocs de `rapport.txt`, sur une ligne, sans `ls`.*

```bash
stat -c 'inode=%i liens=%h taille=%s blocs512=%b' \
  ~/lab02/liens/source/rapport.txt
```

```console
inode=794716 liens=2 taille=23 blocs512=8
```

> [!NOTE]
> **Pourquoi**
>
> `%b` compte des blocs de **512 octets**, quelle que soit la taille de bloc du
> système de fichiers (4 Kio en général). Un fichier de 23 octets occupe donc 8
> blocs de 512, soit 4 Kio : la granularité minimale d'allocation. C'est ce qui
> explique qu'un répertoire de 10 000 fichiers de 100 octets consomme 40 Mio et pas
> 1 Mio. Le format `%B` donne la taille d'unité utilisée par `%b`.

---

<a id="e2-2"></a>**[E2.2](README.md#e2-2)** — *Qui partage le même contenu physique dans `liens/source` ?*

```bash
ls -li ~/lab02/liens/source/
```

```console
794718 lrwxrwxrwx 1 mathieu 44 absolu.txt -> /home/mathieu/lab02/
                                             liens/source/rapport.txt
794716 -rw-r--r-- 2 mathieu 23 dur.txt
794717 lrwxrwxrwx 1 mathieu 11 mou.txt -> rapport.txt
794716 -rw-r--r-- 2 mathieu 23 rapport.txt
```

`dur.txt` et `rapport.txt` partagent l'inode **794716** : un seul contenu, deux
noms. `mou.txt` et `absolu.txt` ont leur propre inode et le type `l`.

> [!NOTE]
> **Pourquoi**
>
> La colonne qui tranche est la **première** (numéro d'inode), pas la taille ni la
> date. Deux fichiers de même taille et même date peuvent être deux copies
> indépendantes ; deux entrées de même inode sont forcément le même objet.
>
> La seconde colonne utile est le compteur de liens, ici `2` pour les deux noms
> physiques. Un fichier ordinaire avec `nlink > 1` est toujours le signe d'un lien
> physique quelque part. Pour retrouver l'autre nom :
> `find / -xdev -inum 794716 2>/dev/null`.

---

<a id="e2-3"></a>**[E2.3](README.md#e2-3)** — *Lien relatif déplacé, puis réparé.*

```bash
cd ~/lab02/liens/deplace
ln -s ../source/rapport.txt lien-relatif.txt
cat lien-relatif.txt              # fonctionne
mv lien-relatif.txt ../
cat ../lien-relatif.txt           # No such file or directory
readlink ../lien-relatif.txt      # ../source/rapport.txt
readlink -m ../lien-relatif.txt   # /home/mathieu/lab02/source/rapport.txt
```

Réparation, deux options :

```bash
# 1. corriger le chemin relatif depuis le nouvel emplacement
ln -sfn source/rapport.txt ~/lab02/liens/lien-relatif.txt
# 2. ou basculer en absolu, insensible au déplacement du lien
ln -sfn ~/lab02/liens/source/rapport.txt ~/lab02/liens/lien-relatif.txt
```

> [!NOTE]
> **Pourquoi**
>
> Depuis `~/lab02/liens`, la chaîne `../source/rapport.txt` désigne
> `~/lab02/source/rapport.txt`, qui n'existe pas. Note qu'un déplacement vers un
> répertoire frère (`liens/copie`) n'aurait rien cassé : `../source` y mène au
> même endroit. Le chemin est résolu depuis le **répertoire contenant le lien**.
> `readlink` montre la chaîne brute, `readlink -f` la résolution ; l'écart entre les
> deux est le diagnostic complet. Ici `-f` ne répondrait rien, car le répertoire `~/lab02/source` lui-même manque : `-m` résout sans exiger que le chemin existe.
>
> `ln -sfn` plutôt que `ln -sf` : sans `-n`, si la destination est déjà un lien vers
> un répertoire, `ln` écrit **dans** ce répertoire au lieu de remplacer le lien.

---

<a id="e2-4"></a>**[E2.4](README.md#e2-4)** — *Lien physique impossible vers un autre système de fichiers.*

```bash
ln ~/lab02/liens/source/rapport.txt /srv/appdata/incoming/rapport.txt
```

```console
ln: failed to create hard link '/srv/appdata/incoming/rapport.txt'
 => '/home/mathieu/lab02/liens/source/rapport.txt': Invalid cross-device link
```

Le code d'erreur est `EXDEV`, numéro **18** (`errno EXDEV`, commande du paquet `moreutils`, ou `grep -w EXDEV /usr/include/asm-generic/errno-base.h`).

> [!NOTE]
> **Pourquoi**
>
> Preuve indépendante que les deux chemins sont sur deux systèmes de fichiers, par
> le numéro de périphérique de l'inode :
>
> ```bash
> stat -c '%d %n' ~/lab02/liens/source /srv/appdata/incoming
> ```
>
> `%d` est le *device id*. Deux valeurs différentes, donc deux systèmes de fichiers,
> donc deux espaces de numérotation d'inodes indépendants, donc pas de lien physique
> possible. C'est exactement le test que fait `find -xdev` pour ne pas franchir les
> montages.

---

<a id="e2-5"></a>**[E2.5](README.md#e2-5)** — *Types non ordinaires dans `liens`, puis identification par le contenu.*

```bash
find ~/lab02/liens -maxdepth 1 ! -type f ! -type d -printf '%y %p\n'
```

```console
c /home/mathieu/lab02/liens/faux-null
l /home/mathieu/lab02/liens/casse.txt
s /home/mathieu/lab02/liens/app.sock
p /home/mathieu/lab02/liens/file-attente
```

```bash
cd ~/lab02
file -- arbo/archives/disque-vm.img liens/app.sock /etc/os-release
```

```console
arbo/archives/disque-vm.img: data
liens/app.sock:              socket
/etc/os-release:             symbolic link to ../usr/lib/os-release
```

> [!NOTE]
> **Pourquoi**
>
> `%y` de `find` donne la lettre de type, la même que la première colonne de
> `ls -l`. `find` teste le type **sans suivre** les liens symboliques par défaut ;
> `-xtype` fait l'inverse et teste le type de la cible.
>
> `file` ne regarde pas l'extension : il applique les règles de `/usr/share/misc/magic`
> au contenu (nombres magiques en tête de fichier), avec repli sur une analyse
> statistique pour distinguer texte et binaire. C'est l'outil à dégainer devant un
> fichier nommé `.jpg` qui est en réalité une archive, ou devant une pièce jointe
> suspecte. Le `--` protège des noms commençant par un tiret.

---

<a id="e2-6"></a>**[E2.6](README.md#e2-6)** — *Tous les liens symboliques cassés sous `~/lab02`.*

```bash
find ~/lab02 -xtype l
```

```console
/home/mathieu/lab02/liens/casse.txt
```

> [!NOTE]
> **Pourquoi**
>
> `-xtype l` est vrai quand, **après résolution du lien**, la cible est elle-même de
> type `l` — ce qui ne peut arriver que si la résolution échoue. C'est le test
> canonique du lien cassé, en une seule option.
>
> L'écriture équivalente, utile quand on veut aussi la cible :
>
> ```bash
> find ~/lab02 -type l ! -exec test -e {} \; -printf '%p -> %l\n'
> ```
>
> Elle est plus lisible mais lance un processus `test` par lien. Sur une
> arborescence de production, `-xtype l` est sans concurrence. Sur un `/` complet, on
> ajoute `-xdev` pour ne pas partir dans les montages réseau.

---

<a id="e2-7"></a>**[E2.7](README.md#e2-7)** — *Les cinq plus gros répertoires de `/var`.*

```bash
sudo du -h --max-depth=1 -x /var 2>/dev/null | sort -rh | head -6
```

> [!NOTE]
> **Pourquoi**
>
> Trois options qui comptent :
>
> * `--max-depth=1` : un seul niveau, sinon la sortie est illisible ;
> * `-x` : ne franchit pas les points de montage, donc `/var/log/factura` monté à
>   part n'est pas compté dans `/var` — on cherche ce qui remplit **ce** système de
>   fichiers ;
> * `sort -rh` : tri décroissant par taille lisible (`2,0G` avant `1,5G`, et `1,5G` avant `900M`),
>   ce que `sort -rn` ferait faux.
>
> `head -6` parce que la première ligne est le total de `/var` lui-même. Le `2>/dev/null`
> masque les répertoires non lisibles quand on n'est pas root.

---

<a id="e2-8"></a>**[E2.8](README.md#e2-8)** — *Taille apparente contre occupation réelle du fichier creux.*

```bash
du -h --apparent-size ~/lab02/arbo/archives/disque-vm.img
du -h ~/lab02/arbo/archives/disque-vm.img
stat -c 'declaree=%s allouee=%b*512' ~/lab02/arbo/archives/disque-vm.img
```

```console
2,0G	disque-vm.img
4,0M	disque-vm.img
```

Écart : 4 Mio réels pour 2 048 Mio annoncés, soit **0,2 %** d'occupation réelle.

> [!NOTE]
> **Pourquoi**
>
> Aucun des deux chiffres n'est faux : ils répondent à deux questions différentes.
> « Combien d'octets ce fichier contient-il logiquement ? » → 2 Gio. « Combien
> d'espace disque libère sa suppression ? » → 4 Mio. Pour une opération de
> récupération d'espace, seule la seconde question compte, et c'est `du` sans option
> qui y répond.

---

<a id="e2-9"></a>**[E2.9](README.md#e2-9)** — *Fichiers de plus de 5 Mio, triés par taille décroissante.*

```bash
find ~/lab02/arbo -type f -size +5M -printf '%s\t%p\n' \
  | sort -rn \
  | numfmt --to=iec --field=1
```

```console
2,0G	/home/mathieu/lab02/arbo/archives/disque-vm.img
18M	/home/mathieu/lab02/arbo/logs/debug.log
14M	/home/mathieu/lab02/arbo/logs/access.log
11M	/home/mathieu/lab02/arbo/logs/access.log.1
9,3M	/home/mathieu/lab02/arbo/archives/dump-2026-08.sql
8,8M	/home/mathieu/lab02/arbo/archives/dump-2025-11.sql
```

> [!WARNING]
> **Piège**
>
> `-size` travaille sur la taille **apparente** : le fichier creux `disque-vm.img`
> arrive donc en tête avec ses 2 Gio annoncés, alors qu'il n'occupe que 4 Mio. Pour
> classer par occupation réelle, il faut `%b` :
>
> ```bash
> find ~/lab02/arbo -type f -printf '%b\t%p\n' | sort -rn | head -5
> ```
>
> C'est la différence entre « quels fichiers sont gros » et « quels fichiers me
> coûtent de la place ». En intervention disque plein, c'est la seconde qui compte.

---

<a id="e2-10"></a>**[E2.10](README.md#e2-10)** — *Modifiés il y a moins de 24 h, puis moins de 30 minutes.*

```bash
find ~/lab02/arbo -type f -mtime -1
find ~/lab02/arbo -type f -mmin -30
```

> [!NOTE]
> **Pourquoi**
>
> La seconde liste est vide si rien n'a été touché dans la demi-heure : le terrain de
> jeu a été créé par le script de setup avec des dates forcées par `touch -d`, qui
> appartiennent toutes au passé. Elle se remplit dès que tu modifies un fichier.
>
> `-mtime -1` signifie « âge strictement inférieur à 1 × 24 h », donc bien « depuis
> 24 heures » — le signe `-` est intuitif, contrairement au `+`. Et `-mtime 0`
> désigne la même chose que `-mtime -1`. Trois horodatages existent, et le choix
> compte :
>
> | Option | Horodatage | Change quand |
> |---|---|---|
> | `-mtime` | `mtime` | le **contenu** est modifié |
> | `-ctime` | `ctime` | l'**inode** change (droits, propriétaire, liens) |
> | `-atime` | `atime` | le fichier est **lu** |
>
> `atime` est peu fiable : la plupart des montages utilisent `relatime`, qui ne le
> met à jour qu'une fois par jour ou après une écriture.

---

<a id="e2-11"></a>**[E2.11](README.md#e2-11)** — *Fichiers de `www-data`, puis ceux qui ne sont pas à `mathieu`.*

```bash
find ~/lab02/arbo -user www-data -printf '%u %p\n'
find ~/lab02/arbo ! -user mathieu -printf '%u %p\n'
```

Les deux listes ne sont **pas** forcément identiques : la seconde remonte aussi les
fichiers appartenant à root ou à tout autre utilisateur. Sur cette arborescence
elles coïncident, parce que `www-data` est le seul autre propriétaire — c'est un
hasard de contenu, pas une équivalence logique.

> [!NOTE]
> **Pourquoi**
>
> `-user` accepte un nom ou un UID numérique. Avec un UID sans entrée dans
> `/etc/passwd` — cas fréquent après une migration ou dans un conteneur — seul le
> numérique fonctionne, et `%u` affiche alors l'UID brut. L'option `-nouser` remonte
> justement tous les fichiers dont l'UID n'existe plus dans la base :
>
> ```bash
> sudo find /srv -xdev \( -nouser -o -nogroup \) -printf '%u:%g %p\n'
> ```
>
> C'est un contrôle d'audit standard après une reprise de serveur.

---

<a id="e2-12"></a>**[E2.12](README.md#e2-12)** — *Tout `app`, sauf `node_modules` et `.git`, non parcourus.*

```bash
find ~/lab02/arbo/app \( -name node_modules -o -name .git \) -prune \
  -o -type f -print
```

```console
/home/mathieu/lab02/arbo/app/src/main.py
/home/mathieu/lab02/arbo/app/src/utils.py
```

> [!NOTE]
> **Pourquoi**
>
> Les parenthèses regroupent les deux noms à élaguer ; elles doivent être protégées
> du shell (`\(` et `\)` ou `'('` et `')'`), sinon bash les interprète comme un
> sous-shell. Le `-o` qui suit `-prune` est indispensable : sans lui, l'expression
> devient `... -prune -type f -print` et rien ne s'affiche.
>
> Le `-print` final est obligatoire dès qu'une action figure dans l'expression :
> `find` désactive alors son `-print` implicite.
>
> Différence de coût avec `! -path '*/node_modules/*'` : `-prune` empêche la
> **descente** dans le répertoire, l'autre forme le parcourt entièrement avant de
> filtrer. Sur un vrai `node_modules`, c'est un facteur 100 sur le temps
> d'exécution.

---

<a id="e2-13"></a>**[E2.13](README.md#e2-13)** — *SHA-256 de tous les `.log`, noms à espaces compris.*

```bash
# forme 1 : find fait tout
find ~/lab02/arbo -type f -name '*.log' -exec sha256sum {} +

# forme 2 : xargs, avec séparateur nul obligatoire
find ~/lab02/arbo -type f -name '*.log' -print0 | xargs -0 -r sha256sum
```

> [!WARNING]
> **Piège**
>
> Sans `-print0`/`-0`, `audit ancien.log` devient deux arguments et `sha256sum`
> répond `No such file or directory` deux fois. L'option `-r` de `xargs`
> (`--no-run-if-empty`) évite d'exécuter `sha256sum` sans argument quand `find` ne
> trouve rien — sinon la commande lit son entrée standard et **attend indéfiniment**,
> ce qui bloque un job CI sans message d'erreur.
>
> Détail de comptage : `*.log` ne remonte pas `access.log.1`. Pour les rotations, il
> faut `-name '*.log*'` ou une expression régulière `-regextype posix-extended -regex '.*\.log(\.[0-9]+)?'` (le type par défaut, `emacs`, ne connaît pas les parenthèses de groupe nues).

---

<a id="e2-14"></a>**[E2.14](README.md#e2-14)** — *Supprimer les `.tmp` de plus de 3 jours.*

```bash
# 1. toujours regarder d'abord
find ~/lab02/arbo -type f -name '*.tmp' -mtime +3 -print

# 2. puis supprimer
find ~/lab02/arbo -type f -name '*.tmp' -mtime +3 -delete
```

> [!WARNING]
> **Piège**
>
> `-delete` implique `-depth` (parcours des feuilles vers la racine) et doit être le
> **dernier** test de l'expression. `find . -delete -name '*.tmp'` supprime tout le
> contenu du répertoire courant : `-delete` est évalué en premier, il renvoie vrai,
> et `-name` n'est plus qu'un filtre d'affichage sur des fichiers déjà détruits.
>
> `-delete` refuse les répertoires non vides (`Directory not empty`) — c'est voulu — et
> n'a pas besoin de `-exec rm`, donc pas de processus par fichier. Si `-delete` n'est
> pas disponible (vieux `find`), l'équivalent sûr est
> `-print0 | xargs -0 -r rm --`.

---

<a id="e2-15"></a>**[E2.15](README.md#e2-15)** — *Le processus 1 vu par `/proc`, et le type de disque par `/sys`.*

```bash
sudo readlink /proc/1/exe          # /usr/lib/systemd/systemd
sudo readlink /proc/1/cwd          # /
sudo tr '\0' ' ' < /proc/1/cmdline ; echo
cat /sys/block/sda/queue/rotational   # 0 = SSD/NVMe, 1 = plateaux
```

> [!NOTE]
> **Pourquoi**
>
> `cmdline` sépare les arguments par des octets nuls pour qu'un argument contenant
> une espace reste identifiable : d'où le `tr '\0' ' '`. C'est la ligne de commande
> **réelle**, non tronquée, contrairement à `ps` qui coupe selon la largeur du
> terminal.
>
> `exe` est un lien vers l'inode du binaire en cours d'exécution. Après une mise à
> jour de paquet, il affiche `/usr/bin/nginx (deleted)` : le processus tourne encore
> sur l'ancien binaire, supprimé du système de fichiers. C'est le signal qu'un
> redémarrage de service est nécessaire, et `needrestart` sur Ubuntu ne fait rien
> d'autre que lire ça.
>
> Pour trouver le bon disque quand il n'y a pas de `sda` :
> `lsblk -no PKNAME "$(findmnt -no SOURCE /)"`.

---

<a id="e2-16"></a>**[E2.16](README.md#e2-16)** — *Les `tmpfs` et leur taille, puis le montage d'un fichier donné.*

```bash
findmnt -t tmpfs -o TARGET,SIZE,USE%
findmnt -T /var/log/factura/factura.log -o TARGET,SOURCE,FSTYPE,OPTIONS
```

```console
TARGET           SOURCE     FSTYPE OPTIONS
/var/log/factura /dev/loop1 ext4   rw,relatime
```

> [!NOTE]
> **Pourquoi**
>
> `-T` (`--target`) accepte un **fichier** et remonte le point de montage qui le
> porte : c'est la question à se poser avant toute suppression (« je libère de
> l'espace où, exactement ? »). `findmnt` lit `/proc/self/mountinfo`, donc la vérité
> du noyau, contrairement au vieux `mount` sans argument qui lisait `/etc/mtab`.
>
> Sur une Ubuntu 24.04 par défaut, les `tmpfs` visibles sont `/run` (10 % de la RAM),
> `/dev/shm` (50 %), `/run/lock` (5 Mio) et les `/run/user/<uid>` créés par
> `pam_systemd` à chaque connexion. `/tmp` n'est un `tmpfs` que si
> l'unité `tmp.mount` est activée — ce n'est pas le défaut sur Ubuntu Server, où
> `/tmp` fait partie de `/`.

---

## 2.6 Labs

### <a id="l2-1"></a>**[L2.1](README.md#l2-1)** — Ranger la livraison `factura` selon le FHS

*Déployer une archive à plat en respectant le FHS, avec service systemd et
`/run` géré automatiquement.*

**1. Extraction et inventaire**

```bash
mkdir -p /tmp/factura-install
tar -xzf ~/lab02/livraison/factura-2.4.tar.gz -C /tmp/factura-install
ls -l /tmp/factura-install/factura-2.4/
```

| Fichier livré | Destination | Pourquoi |
|---|---|---|
| `facturad`, `facturactl` | `/opt/factura/bin/` | produit tiers auto-contenu |
| `factura.conf` | `/etc/factura/` | configuration statique de l'hôte |
| `factura.db` | `/var/lib/factura/` | état persistant, varie en fonctionnement |
| `factura.service` | `/etc/systemd/system/` | unité locale, non fournie par un paquet |
| `exports-exemple.csv` | `/srv/factura/exports/` | donnée servie à des clients |
| `README.md` | `/opt/factura/` (ou jeté) | documentation du produit |

**2 à 5. Installation**

```bash
S=/tmp/factura-install/factura-2.4
sudo install -d /opt/factura/bin
sudo install -m 755 "$S/facturad" "$S/facturactl" /opt/factura/bin/

sudo ln -sfn /opt/factura/bin/facturactl /usr/local/bin/facturactl

sudo install -d /etc/factura
sudo install -m 644 "$S/factura.conf" /etc/factura/factura.conf

sudo install -d /var/lib/factura
sudo install -m 640 "$S/factura.db" /var/lib/factura/factura.db

sudo install -d /var/log/factura

sudo install -d -o www-data -g www-data /srv/factura/exports
sudo install -m 644 -o www-data -g www-data \
  "$S/exports-exemple.csv" /srv/factura/exports/
```

**6 et 7. Service et `/run`**

```bash
sudo install -m 644 "$S/factura.service" /etc/systemd/system/factura.service
sudo systemctl daemon-reload
sudo systemctl enable --now factura.service
systemctl is-active factura
ls -l /run/factura/
sudo systemctl restart factura
ls -l /run/factura/          # recréé, pid différent
```

**8. Rapport** : `~/lab02/rapports/fhs-factura.md`, le tableau ci-dessus complété
de l'état constaté.

```bash
bash check_M02_01.sh
```

> [!NOTE]
> **Pourquoi**
>
> Deux points méritent d'être détaillés.
>
> **`install` plutôt que `cp` + `chmod` + `chown`** : une seule commande atomique
> qui crée le répertoire (`-d`), pose le mode (`-m`), le propriétaire (`-o`) et le
> groupe (`-g`). C'est l'outil utilisé par tous les `Makefile` et toutes les
> recettes de paquets. `install` écrase aussi proprement un binaire en cours
> d'exécution (il délie et recrée, il n'écrit pas dans l'inode existant), là où
> `cp` sur un binaire en cours d'exécution renvoie `Text file busy`.
>
> **`RuntimeDirectory=factura`** : systemd crée `/run/factura` avant `ExecStart`,
> avec le propriétaire du service, et le supprime à l'arrêt. Il exporte au passage
> la variable `$RUNTIME_DIRECTORY` au processus. C'est la seule méthode correcte :
> un `mkdir /run/factura` posé à la main disparaît au prochain redémarrage puisque
> `/run` est un `tmpfs`, et le service échoue au boot avec un message obscur sur un
> fichier de pid impossible à écrire.

> [!WARNING]
> **Piège**
>
> Le lien `/usr/local/bin/facturactl` est fait en **absolu**. Un lien relatif
> (`../../opt/factura/bin/facturactl`) fonctionnerait aussi, mais `/usr/local` et
> `/opt` sont fréquemment des points de montage distincts, et rien ne garantit leur
> position relative sur une autre machine. Règle : lien relatif à l'intérieur d'une
> arborescence cohérente, lien absolu dès qu'on relie deux zones indépendantes du
> système.

---

### <a id="l2-2"></a>**[L2.2](README.md#l2-2)** — Ticket INC-3187 : partition de logs à 99 %

*Repasser `/var/log/factura` sous 50 % sans arrêter le service ni redémarrer.*

**1. État des lieux**

```bash
df -hT -x tmpfs -x devtmpfs -x proc -x sysfs -x squashfs
```

```console
Filesystem     Type  Size  Used Avail Use% Mounted on
/dev/vda1      ext4   20G  6,2G   13G  33% /
/dev/loop0     ext4  224M   32K  206M   1% /srv/appdata
/dev/loop1     ext4  265M  253M  3,9M  99% /var/log/factura
```

Trois systèmes de fichiers réels ; c'est `/var/log/factura` qui est en cause.

**2 et 3. Descente par paliers**

```bash
sudo du -xh --max-depth=1 /var | sort -h | tail
sudo du -xh --max-depth=1 /var/log | sort -h | tail
sudo du -h --max-depth=1 /var/log/factura | sort -h
sudo ncdu -x /var/log/factura
```

`du -x` ne franchit pas les points de montage : sans lui, `du /var` inclut les
253 Mio de `/var/log/factura` et fausse le classement du système de fichiers
racine. Ici, il faut justement interroger le montage séparément.

**4. Le journal ouvert en écriture**

```bash
sudo lsof /var/log/factura/factura.log
# COMMAND   PID USER FD TYPE  SIZE/OFF NODE NAME
# lab-colle 812 root  3w  REG 188743680   12 /var/log/factura/
#                                            factura.log

df -h /var/log/factura
sudo truncate -s 0 /var/log/factura/factura.log
df -h /var/log/factura              # l'espace est rendu immédiatement
```

Le fichier garde son inode, ses permissions et son propriétaire ; le processus
continue d'écrire à la suite sans rien remarquer.

**5. Archives : garder les deux plus récentes**

```bash
find /var/log/factura -maxdepth 1 -name 'factura.log.*.gz' \
     -printf '%T@\t%p\0' \
  | sort -zrn | tail -zn +3 | cut -zf2- | xargs -0 -r sudo rm -f
ls -l /var/log/factura/
```

**6. journald**

```bash
journalctl --disk-usage
# un drop-in plutôt que d'éditer journald.conf (le check accepte les deux)
sudo mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nSystemMaxUse=50M\n' \
  | sudo tee /etc/systemd/journald.conf.d/50-limite.conf
sudo systemctl restart systemd-journald
sudo journalctl --vacuum-size=50M
journalctl --disk-usage
```

**7. Caches**

```bash
find /var/cache/factura/thumbs -type f | wc -l     # 400
sudo find /var/cache/factura/thumbs -type f -delete
sudo apt clean
df -i /                                            # 400 inodes récupérés
```

**8 et 9.** Le fichier `disque-vm.img` est creux : 2 Gio annoncés, 4 Mio alloués.
Le supprimer ne rendrait que 4 Mio. Rapport dans `~/lab02/rapports/inc-3187.md`.

```bash
bash check_M02_02.sh
```

> [!NOTE]
> **Pourquoi**
>
> Le cœur du lab est l'étape 4. `truncate -s 0` appelle `ftruncate()` sur l'inode :
> tous les blocs au-delà de la nouvelle taille sont rendus au système de fichiers
> **immédiatement**, sans toucher au descripteur ouvert par le processus. Comme le
> collecteur a ouvert son fichier en mode `O_APPEND`, sa prochaine écriture repart de
> l'offset 0 et le fichier grossit normalement.
>
> Si l'application avait ouvert sans `O_APPEND`, elle conserverait son offset interne
> — disons 180 000 000 — et écrirait à cette position, recréant instantanément un
> fichier de 180 Mo… **creux** : `ls -l` afficherait 180 Mo, `du` quelques kilo-octets.
> C'est un comportement déroutant qu'on observe en vrai, et c'est la raison pour
> laquelle `logrotate` propose `copytruncate` **avec prudence** et préfère, quand
> c'est possible, envoyer un signal à l'application pour qu'elle rouvre ses fichiers
> (directive `postrotate` + `systemctl kill -s USR1`).

> [!WARNING]
> **Piège**
>
> Erreurs classiques sur ce ticket :
>
> * `rm factura.log` : l'espace n'est rendu que quand le processus meurt, et la
>   journalisation est perdue pour toujours (le processus écrit dans un inode sans
>   nom). Le check le détecte en comparant le numéro d'inode.
> * `> /var/log/factura/factura.log` lancé avec `sudo` : la redirection est faite par
>   le shell **non privilégié** avant que `sudo` ne s'exécute, donc `Permission
>   denied`. Il faut `sudo truncate -s 0 fichier` ou
>   `sudo sh -c ': > fichier'`.
> * Supprimer les `.gz` avec `ls -t | tail -n +3 | xargs rm` : fonctionne ici, casse dès
>   qu'un nom contient une espace, et repose sur le tri de `ls` plutôt que sur les
>   dates réelles.

---

### <a id="l2-3"></a>**[L2.3](README.md#l2-3)** — Audit d'arborescence avant migration

*Six inventaires produits avec `find`, plus le ménage des temporaires.*

```bash
cd ~/lab02
INV=~/lab02/inventaire

# 1. gros fichiers
find arbo -type f -size +5M -printf '%s\t%p\n' | sort -rn > "$INV/gros.txt"

# 2. fichiers dormants depuis plus de 90 jours
find arbo -type f -mtime +90 -printf '%TY-%Tm-%Td\t%p\n' | sort \
  > "$INV/anciens.txt"

# 3. propriétaires autres que mathieu
find arbo ! -user mathieu -printf '%u\t%p\n' | sort \
  > "$INV/par-proprietaire.txt"

# 4. code, sans descendre dans node_modules ni .git
time find arbo/app \( -name node_modules -o -name .git \) -prune \
  -o -type f -print > "$INV/code.txt"
time find arbo/app -type f ! -path '*/node_modules/*' ! -path '*/.git/*' \
  > /dev/null

# 5. empreintes des journaux
find arbo -type f -name '*.log' -print0 | xargs -0 -r sha256sum \
  > "$INV/sommes.txt"

# 6. ménage des temporaires
find arbo -type f -name '*.tmp' -mtime +3 -print
find arbo -type f -name '*.tmp' -mtime +3 -delete

# 7. synthèse
{ printf 'fichiers      : %s\n' "$(find arbo -type f | wc -l)"
  printf 'repertoires   : %s\n' "$(find arbo -type d | wc -l)"
  printf 'inodes        : %s\n' "$(find arbo | wc -l)"
  printf 'taille reelle : %s\n' "$(du -sh arbo | cut -f1)"
  printf 'taille apparente : %s\n' \
    "$(du -sh --apparent-size arbo | cut -f1)"
} > "$INV/resume.txt"
```

```bash
bash check_M02_03.sh
```

> [!NOTE]
> **Pourquoi**
>
> Résultat de l'étape 7 sur l'arborescence fournie : 18 fichiers, 12 répertoires, 30
> inodes, 71 Mio réels contre 2,1 Gio apparents. L'écart vient entièrement du fichier
> creux, et c'est précisément le genre de chiffre qu'il faut porter dans un dossier
> de migration : dimensionner la cible sur 2,1 Gio serait une erreur, mais copier
> naïvement avec `tar` sans `-S` la produirait pour de bon.
>
> Sur l'étape 4, le `time` montre l'intérêt de `-prune` : sur ce jeu miniature
> l'écart est de quelques millisecondes, sur un `node_modules` réel (100 000 à
> 300 000 fichiers) il se compte en dizaines de secondes, et le filtrage `-path`
> génère en plus des entrées/sorties disque inutiles qui polluent le cache du
> système de fichiers.
>
> `%T@` (époque avec fraction) sert au tri, `%TY-%Tm-%Td` à l'affichage : `find`
> sait formater les dates sans passer par `stat` ou `date`, ce qui évite un
> processus par fichier.

> [!WARNING]
> **Piège**
>
> Trois noms contiennent une espace dans cette arborescence : `logs/audit ancien.log`, `uploads/CV Dupont.pdf`
> et `uploads/scan provisoire.tmp`. Toute écriture du type
> `for f in $(find ...)` ou `find ... | xargs cmd` les découpe. Le `-printf` avec
> tabulation en séparateur et le `-print0 | xargs -0` sont les deux formes sûres.
> Vérification rapide sur l'inventaire produit :
> `grep -c 'audit ancien.log' ~/lab02/inventaire/sommes.txt` doit renvoyer 1.

---

### <a id="l2-4"></a>**[L2.4](README.md#l2-4)** — Dédoublonner sans casser

*Liens physiques à l'intérieur d'un système de fichiers, symbolique absolu pour
franchir un montage.*

```bash
U=~/lab02/arbo/uploads ; L=~/lab02/liens

# 1. état initial : trois copies du même contenu
cp "$U/photo1.jpg" "$U/photo2.jpg" "$L/copie/"
cp "$U/photo1.jpg" "$U/photo2.jpg" /srv/appdata/incoming/
du -sh ~/lab02            # 76M
df -h /srv/appdata

# 2. deux systèmes de fichiers, deux preuves
stat -c '%d %n' "$L/copie" /srv/appdata/incoming
findmnt -T "$L/copie" -o TARGET,SOURCE
findmnt -T /srv/appdata/incoming -o TARGET,SOURCE

# 3. dédoublonnage local par lien physique
for p in photo1.jpg photo2.jpg; do ln -f "$U/$p" "$L/copie/$p"; done
du -sh ~/lab02            # 71M : 5 Mio rendus
stat -c '%i %h %n' "$U/photo1.jpg" "$L/copie/photo1.jpg"
```

**4.** Modifier `copie/photo1.jpg` modifie **aussi** `uploads/photo1.jpg` : un seul
inode, un seul contenu, deux noms. Il n'y a pas de copie à synchroniser.

**5.** Supprimer `uploads/photo1.jpg` ne détruit rien : `copie/photo1.jpg` reste
lisible et son compteur de liens retombe à 1. On restaure avec
`ln "$L/copie/photo1.jpg" "$U/photo1.jpg"`.

```bash
# 6. l'autre système de fichiers : lien symbolique absolu
rm /srv/appdata/incoming/photo2.jpg
ln -s "$U/photo2.jpg" /srv/appdata/incoming/photo2.jpg
ls -l /srv/appdata/incoming/

# 7. renommage du répertoire de doublons
mv "$L/copie" "$L/copie-v2"
find ~/lab02 /srv/appdata -xtype l
```

**Bilan de l'étape 7** : les liens **physiques** survivent sans exception — ils ne
dépendent d'aucun chemin. Le lien symbolique de `/srv/appdata/incoming` survit
aussi, parce qu'il pointe vers `uploads/`, qui n'a pas bougé. En revanche, tout
lien symbolique qui aurait pointé vers `liens/copie/...` serait cassé.

```bash
bash check_M02_04.sh
```

> [!NOTE]
> **Pourquoi**
>
> Pourquoi **absolu** à l'étape 6 : le lien vit sur `/srv/appdata`, un montage
> indépendant. Un lien relatif devrait remonter hors du montage
> (`../../../home/mathieu/...`), ce qui suppose que `/srv/appdata` soit monté à cet
> endroit précis. Démonte le volume et remonte-le ailleurs, et le lien relatif pointe
> dans le vide, tandis que l'absolu continue de résoudre.
>
> Pourquoi `du -sh ~/lab02/liens/copie` ne bouge pas à l'étape 3 : `du` ne compte un
> inode qu'**une fois par exécution**, en mémorisant les paires (device, inode) déjà
> vues. Quand on ne lui donne que `copie/`, il ne voit qu'un seul nom par inode et
> compte le contenu en entier. Quand on lui donne `~/lab02`, il rencontre les deux
> noms, n'en compte qu'un, et le total baisse de 5 Mio. C'est le comportement
> correct — mais il explique pourquoi `du` sur un répertoire isolé peut surestimer
> l'espace qu'on récupérerait en le supprimant.

> [!WARNING]
> **Piège**
>
> Les liens physiques et les sauvegardes forment un piège classique. `rsync` sans
> `-H` recrée des copies indépendantes sur la destination : une arborescence de
> 100 Gio dédoublonnée à 40 Gio redevient 100 Gio après sauvegarde. 
> `tar`, lui, préserve les liens physiques par défaut (sauf `--hard-dereference`); `cp` `-r` sans `-a` ni `--preserve=links` recrée des copies indépendantes. Vérifie toujours le compteur de liens après une
> restauration.

---

## 2.7 Break & Fix

### <a id="bf2-1"></a>**[BF2.1](README.md#bf2-1)** — « Le disque est plein, mais il n'y a rien dessus »

**Démarche de diagnostic**

```bash
# 1. confirmer l'écart
df -h /srv/appdata
#   /dev/loop0  224M  219M     0  100% /srv/appdata
du -sh /srv/appdata
#   28K   /srv/appdata
```

L'écart est de 219 Mio pour 28 Kio visibles : il y a des blocs alloués sans nom.

```bash
# 2. chercher les fichiers supprimés encore ouverts
sudo lsof -nP +L1 /srv/appdata
```

```console
COMMAND   PID USER FD TYPE  SIZE/OFF NLINK NODE NAME
lab-inges 812 root  3w  REG 228589605     0   13 /srv/appdata/incoming/
                                                ingest.dat (deleted)
```

```bash
# 3. confirmer par /proc, sans lsof
sudo ls -l /proc/812/fd | grep deleted
# l-wx------ 1 root root 64 3 -> /srv/appdata/incoming/ingest.dat (deleted)
```

**Cause racine** : le processus `lab-ingest` (pid 812) a ouvert
`/srv/appdata/incoming/ingest.dat` en écriture et le tient toujours ouvert sur son
descripteur 3. Quelqu'un — un script de purge, un collègue — a supprimé le fichier.
Son entrée de répertoire a disparu, donc `du` et `ls` ne le voient plus, mais son
compteur de liens à 0 associé à un descripteur ouvert interdit au noyau de libérer
les 219 Mio de blocs.

**Correctif immédiat, sans démonter ni redémarrer**

```bash
sudo truncate -s 0 /proc/812/fd/3
df -h /srv/appdata        # 32K utilisés, 206M disponibles
```

Variante acceptable si le service tolère une coupure d'une seconde :
`sudo systemctl restart lab-ingest` — la fermeture du descripteur libère
l'espace (dans ce lab, le simulacre recrée aussitôt son fichier et resature le volume : la troncature est la seule remise en service qui tienne). Variante **inacceptable** : `reboot`.

**Prévention**

* Côté application : ne jamais garder un descripteur ouvert indéfiniment sur un
  fichier de travail. Rouvrir sur signal (`SIGHUP`/`SIGUSR1`), ou utiliser
  `logrotate` avec `postrotate` qui envoie ce signal.
* Côté exploitation : interdire `rm` sur les fichiers de travail d'un service ;
  superviser l'écart `df`/`du` (une sonde qui calcule la somme de `lsof +L1` et
  alerte au-delà de 100 Mio), et documenter la procédure `/proc/<pid>/fd`.

> [!NOTE]
> **Pourquoi**
>
> Le mécanisme en une phrase : **un fichier n'est réellement supprimé que lorsque son
> compteur de liens est à 0 et qu'aucun descripteur n'est plus ouvert dessus** ;
> entre les deux, il occupe des blocs sans avoir de nom.
>
> `/proc/<pid>/fd/3` n'est pas une copie du fichier : c'est un lien vers l'inode
> lui-même. Le tronquer agit donc directement sur les blocs, et le processus continue
> d'écrire sans même savoir ce qui s'est passé. On peut aussi s'en servir pour
> **récupérer** le contenu avant de le vider :
>
> ```bash
> sudo cp /proc/812/fd/3 /var/tmp/ingest-recupere.dat
> ```
>
> C'est la seule méthode de récupération d'un fichier supprimé qui ne demande aucun
> outil de forensic — et elle disparaît à la seconde où le processus se termine.

> [!WARNING]
> **Piège**
>
> Deux fausses pistes coûteuses dans cette panne :
>
> * `sync` : ne sert à rien, les blocs ne sont pas « en attente d'écriture », ils sont
>   bel et bien alloués ;
> * `umount` puis `mount` : le démontage échouerait avec `target is busy` tant que le
>   processus tient le descripteur, et l'énoncé l'interdit de toute façon. Si le
>   démontage passait, il tuerait effectivement le problème — en tuant aussi
>   l'application.
>
> Et un réflexe à ne pas avoir : chercher le gros fichier avec
> `find /srv/appdata -size +100M`. Il n'a plus de nom, `find` ne le trouvera jamais.

---

### <a id="bf2-2"></a>**[BF2.2](README.md#bf2-2)** — « `No space left on device` alors qu'il reste 40 % »

**Démarche de diagnostic**

```bash
df -h /srv/archives
#   /dev/loop2  92M  44M  42M  52% /srv/archives
df -i /srv/archives
#   /dev/loop2  1024  1024  0  100% /srv/archives
```

Une seule commande tranche : `df -i`. Les **inodes** sont à 100 %.

```bash
# où sont-ils passés ?
sudo du --inodes -x --max-depth=1 /srv/archives | sort -n
#   1     /srv/archives/lost+found
#   11    /srv/archives/lots
#   1002  /srv/archives/spool
#   1015  /srv/archives
find /srv/archives/spool -type f | wc -l      # 1001 fichiers d'une dizaine
                                           # d'octets
```

**Cause racine** : le système de fichiers a été formaté avec seulement 1 024
inodes (`mkfs.ext4 -N 1024`) alors qu'il sert de spool à des milliers de petits
fichiers JSON jamais purgés. Le quota d'inodes est atteint bien avant le quota de
blocs : le noyau renvoie `ENOSPC`, d'où le message trompeur. Écrire dans un
fichier **existant** fonctionne toujours, seules les créations échouent — c'est la
signature.

**Remise en service**

```bash
sudo find /srv/archives/spool -type f -name '*.json' -mtime +0 -delete
# ou, pour tout le spool :
sudo find /srv/archives/spool -type f -delete
df -i /srv/archives      # 23/1024 utilisés
touch /srv/archives/spool/test && echo "écriture rétablie"
```

**Pourquoi `df -h` ne montre rien** : les deux ressources sont comptées séparément.
1 000 fichiers de 10 octets consomment 1 000 inodes et 1 000 blocs de 4 Kio, soit
4 Mio : invisible sur un volume de 92 Mio, mais fatal côté inodes.

**Ce qu'il fallait faire au formatage**

```bash
sudo mkfs.ext4 -i 8192 /dev/sdX    # un inode tous les 8 Kio
sudo mkfs.ext4 -N 200000 /dev/sdX  # ou un nombre explicite
# ou XFS, dont les inodes sont alloués dynamiquement
sudo tune2fs -l /dev/loop2 | grep -i 'inode count'
```

> [!NOTE]
> **Pourquoi**
>
> Sur ext2/3/4, la table d'inodes est allouée **au formatage** et sa taille est
> définitive : `resize2fs` agrandit les blocs, jamais le nombre d'inodes. Le seul
> remède après coup est sauvegarde, reformatage, restauration. C'est une décision
> d'architecture, pas un réglage d'exploitation.
>
> Ordres de grandeur utiles : le défaut de `mkfs.ext4` est un inode par 16 Kio de
> volume, soit environ 65 000 inodes pour 1 Gio. Un spool de mails, un cache de
> vignettes ou un répertoire de sessions PHP dépasse ça sans effort. XFS, Btrfs et
> ZFS allouent dynamiquement et n'ont pas ce plafond — c'est l'une des raisons pour
> lesquelles RHEL utilise XFS par défaut depuis la version 7.

> [!WARNING]
> **Piège**
>
> Le faux diagnostic fréquent est « quota utilisateur ». Un quota dépassé renvoie
> `EDQUOT`, affiché `Disk quota exceeded`, pas `No space left on device`, et il ne
> frappe que l'utilisateur concerné — ici même root échoue. Deuxième fausse piste :
> un système de fichiers passé en lecture seule après une erreur d'entrée/sortie ;
> il donnerait `Read-only file system` et une trace dans `dmesg`. Vérifier
> `dmesg -T | tail` fait partie du réflexe, mais `df -i` passe en premier.

---

### <a id="bf2-3"></a>**[BF2.3](README.md#bf2-3)** — « Le site sert la mauvaise version depuis la livraison »

**Démarche de diagnostic**

```bash
ls -l /srv/www/
# lrwxrwxrwx 1 root root   10 current -> 2026-09-18
# drwxr-xr-x 5 root root 4096 releases

readlink /srv/www/current
# 2026-09-18
readlink -f /srv/www/current
# /srv/www/2026-09-18          <- n'existe pas
namei -l /srv/www/current | tail -2
# lrwxrwxrwx root root current -> 2026-09-18
#                       2026-09-18 - No such file or directory
```

**Pourquoi `ls -l` et `ls …/` se contredisent** : `ls -l /srv/www` fait un
`lstat()` sur chaque entrée, qui décrit le **lien lui-même** — il existe bel et
bien, avec sa taille de 10 octets, celle de la chaîne `2026-09-18`. `ls
/srv/www/current/` fait un `stat()`, qui **résout** le lien : la cible n'existant
pas, l'appel échoue avec `ENOENT`. Un lien symbolique cassé est un objet
parfaitement valide qui pointe vers rien.

**Cause racine** : le script de livraison a fait `cd /srv/www/releases` avant son
`ln -sfn 2026-09-18 ../current`. Le lien contient donc la chaîne `2026-09-18`, qui
est résolue relativement au répertoire **contenant le lien** (`/srv/www`), et non
au répertoire courant du script (`/srv/www/releases`). Le lien cherche
`/srv/www/2026-09-18` au lieu de `/srv/www/releases/2026-09-18`.

**Remise en service**

```bash
DERNIERE=$(ls -1 /srv/www/releases | sort | tail -1)
sudo ln -sfn "releases/$DERNIERE" /srv/www/current
ls /srv/www/current/
cat /srv/www/current/VERSION
```

**Correction de la procédure de livraison**

```bash
# bascule atomique, chemin relatif correct, depuis /srv/www
cd /srv/www
ln -sfn "releases/$DERNIERE" .current-tmp
mv -T .current-tmp current
```

Lien **relatif** parce que `current` et `releases/` appartiennent à la même
arborescence : on peut déplacer, copier ou monter `/srv/www` ailleurs sans rien
casser. Le chemin est écrit depuis le répertoire du lien, pas depuis le répertoire
de travail du script.

> [!NOTE]
> **Pourquoi**
>
> Trois pièges de `ln` se recoupent dans cette panne, et il faut les connaître tous
> les trois.
>
> 1. **La résolution relative** se fait depuis le répertoire du lien. Un
>    `cd` avant le `ln` n'y change rien : `ln -s` ne vérifie même pas que la cible
>    existe, il se contente d'écrire la chaîne qu'on lui donne.
> 2. **`-n` (`--no-dereference`)** : sans lui, `ln -sf cible current` quand `current`
>    est déjà un lien vers un répertoire crée `current/cible` **à l'intérieur** de
>    l'ancienne release. Le site continue alors de servir l'ancienne version, sans
>    erreur visible — encore plus difficile à diagnostiquer que cette panne-ci.
> 3. **L'atomicité** : selon l'implémentation, `ln -sfn` fait `unlink()` puis `symlink()` (BusyBox, anciens coreutils); entre les deux,
>    `current` n'existe pas, et une requête qui tombe pile là reçoit un 404. Le `ln` de coreutils 9.4 passe déjà par un nom temporaire, mais
>    `mv -T` rend la chose explicite et portable : il utilise `rename(2)`, qui remplace l'entrée de répertoire en une seule
>    opération atomique.

> [!WARNING]
> **Piège**
>
> Le réflexe de faire `cp -r releases/2026-09-18 current` « pour que ça marche tout
> de suite » résout le symptôme et détruit le mécanisme : on perd la bascule
> instantanée, on double l'espace occupé, et le prochain déploiement écrasera un
> répertoire au lieu de repointer un lien. Un `nginx -t && systemctl reload nginx`
> n'est pas non plus nécessaire : nginx résout le lien à chaque requête quand la
> racine est un chemin contenant un lien, et rien n'a changé dans sa configuration.

---

## 2.8 Défi du module

<a id="d2"></a>**[D2](README.md#d2) — `audit-fs.sh`**

Un corrigé possible, testé sur Ubuntu 24.04 et Rocky 9.

```bash
#!/usr/bin/env bash
# audit-fs.sh — audit des systèmes de fichiers
# Rapport Markdown sur stdout, trace sur stderr. Retour : 0 sain, 1 anomalies.
set -euo pipefail

SEUIL=85
ECRIRE=1
JOURNAL=/var/log/audit-fs.log

usage() { echo "usage: ${0##*/} [-n] [chemin]" >&2; exit 2; }
while getopts ':nh' opt; do
  case "$opt" in
    n) ECRIRE=0 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
CIBLE="${1:-/}"
[ -d "$CIBLE" ] || { echo "chemin invalide : $CIBLE" >&2; exit 2; }

trace() { printf '[audit] %s\n' "$*" >&2; }
ANOM=()
anomalie() { ANOM+=("$1"); }
ROOT=0; [ "$(id -u)" -eq 0 ] && ROOT=1
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

printf '# Audit systèmes de fichiers — %s\n\n' "$(hostname)"
printf '%s — chemin analysé : `%s`\n\n' "$(date -Is)" "$CIBLE"
[ "$ROOT" -eq 1 ] || \
  printf '> Sans privilèges : section des fichiers supprimés incomplète.\n\n'

# --- montages -----------------------------------------------------------
trace "inventaire des montages"
printf '## Montages\n\n'
printf '| Point de montage | Type | Blocs | Inodes |\n|---|---|---|---|\n'
mapfile -t POINTS < <(df --output=target -x tmpfs -x devtmpfs \
  -x squashfs -x overlay -x proc -x sysfs 2>/dev/null | tail -n +2 | sort -u)
for p in "${POINTS[@]}"; do
  [ -d "$p" ] || continue
  pb=$(df --output=pcent "$p" 2>/dev/null | tail -1 | tr -dc '0-9') || true
  pi=$(df --output=ipcent "$p" 2>/dev/null | tail -1 | tr -dc '0-9') || true
  ty=$(findmnt -no FSTYPE --target "$p" 2>/dev/null | head -1) || true
  printf '| `%s` | %s | %s%% | %s%% |\n' "$p" "${ty:-?}" "${pb:-?}" "${pi:-?}"
  if [ -n "${pb:-}" ] && [ "$pb" -gt "$SEUIL" ]; then
    anomalie "blocs : $p à ${pb}%"
  fi
  if [ -n "${pi:-}" ] && [ "$pi" -gt "$SEUIL" ]; then
    anomalie "inodes : $p à ${pi}%"
  fi
done
printf '\n'
for v in /run /tmp; do
  pv=$(df --output=pcent "$v" 2>/dev/null | tail -1 | tr -dc '0-9') || true
  if [ -n "${pv:-}" ] && [ "$pv" -gt 50 ]; then anomalie "$v à ${pv}%"; fi
done

# --- répertoires et fichiers --------------------------------------------
printf '## Top 10 des répertoires\n\n```text\n'
du -x -h --max-depth=3 "$CIBLE" 2>/dev/null | sort -h | tail -10 || true
printf '```\n\n## Top 10 des fichiers\n\n```text\n'
find "$CIBLE" -xdev -type f -printf '%s\t%p\n' 2>/dev/null \
  | sort -rn | head -10 \
  | while IFS=$'\t' read -r t n; do
      printf '%8s  %s\n' "$(numfmt --to=iec "$t")" "$n"
    done || true
printf '```\n\n'

# --- fichiers supprimés encore ouverts ----------------------------------
trace "fichiers supprimés encore ouverts"
printf '## Fichiers supprimés encore ouverts\n\n'
lsof -nP +L1 2>/dev/null | awk 'NR > 1 && $8 == 0' > "$TMPD/del" || true
if [ -s "$TMPD/del" ]; then
  printf '| Commande | PID | Octets | Chemin |\n|---|---|---|---|\n'
  awk '{ n = ""; for (i = 10; i <= NF; i++) n = n (i > 10 ? " " : "") $i;
         printf "| %s | %s | %s | %s |\n", $1, $2, $7, n }' "$TMPD/del"
  TOT=$(awk '{ s += $7 } END { print s + 0 }' "$TMPD/del")
  printf '\nEspace immobilisé : **%s**\n\n' "$(numfmt --to=iec "$TOT")"
  if [ "$TOT" -gt $((100 * 1024 * 1024)) ]; then
    anomalie "$(numfmt --to=iec "$TOT") immobilisés par des fichiers \
supprimés"
  fi
else
  printf 'Aucun.\n\n'
fi

# --- liens cassés et fichiers creux -------------------------------------
printf '## Liens symboliques cassés\n\n'
find "$CIBLE" -xdev -xtype l -printf '* `%p` -> `%l`\n' 2>/dev/null \
  > "$TMPD/liens" || true
if [ -s "$TMPD/liens" ]; then
  cat "$TMPD/liens"
  anomalie "$(grep -c . "$TMPD/liens") lien(s) cassé(s)"
else
  printf 'Aucun.\n'
fi
printf '\n## Fichiers creux\n\n'
find "$CIBLE" -xdev -type f -size +1M -printf '%s\t%b\t%p\n' 2>/dev/null \
  | awk -F'\t' '$1 > 4 * $2 * 512 {
      printf "* `%s` : %d o annoncés, %d o alloués\n", $3, $1, $2 * 512
    }' > "$TMPD/creux" || true
if [ -s "$TMPD/creux" ]; then cat "$TMPD/creux"; else printf 'Aucun.\n'; fi

# --- journaux -----------------------------------------------------------
printf '\n## Journaux\n\n'
command -v journalctl >/dev/null 2>&1 && \
  printf '* journald : %s\n' "$(journalctl --disk-usage 2>/dev/null)"
printf '* cinq plus gros fichiers de /var/log :\n\n```text\n'
find /var/log -xdev -type f -printf '%s\t%p\n' 2>/dev/null \
  | sort -rn | head -5 \
  | while IFS=$'\t' read -r t n; do
      printf '%8s  %s\n' "$(numfmt --to=iec "$t")" "$n"
    done || true
printf '```\n\n## Anomalies\n\n'

if [ "${#ANOM[@]}" -eq 0 ]; then
  printf 'Aucune anomalie détectée.\n'; RC=0
else
  for a in "${ANOM[@]}"; do printf '* %s\n' "$a"; done; RC=1
fi
if [ "$ECRIRE" -eq 1 ] && [ "$ROOT" -eq 1 ]; then
  printf '%s %s anomalies=%d\n' "$(date -Is)" "$CIBLE" "${#ANOM[@]}" \
    >> "$JOURNAL" 2>/dev/null || true
fi
trace "terminé, ${#ANOM[@]} anomalie(s)"
exit "$RC"
```

Installation et production du livrable :

```bash
sudo install -m 755 audit-fs.sh /usr/local/bin/audit-fs.sh
sudo audit-fs.sh / > ~/lab02/rapports/audit-lab-ops.md
echo $?
bash check_M02_05.sh
```

> [!NOTE]
> **Pourquoi**
>
> Les cinq difficultés techniques de ce défi, et leur traitement.
>
> **1. `set -euo pipefail` contre les pipelines qui échouent normalement.**
> `find | head -10` reçoit un `SIGPIPE` dès que `head` a ses dix lignes : avec
> `pipefail`, le pipeline sort en échec et `set -e` tue le script au milieu du
> rapport. D'où les `|| true` en fin de pipeline. Même problème pour `df` sur un
> montage réseau bloqué, d'où les `|| true` sur les substitutions de commande.
>
> **2. Les tests en fin de boucle.** Écrire
> `[ "$pb" -gt "$SEUIL" ] && anomalie "..."` comme dernière commande d'un corps de
> boucle est un piège mortel avec `set -e` : quand la condition est fausse,
> l'expression renvoie 1 et le script s'arrête sans le moindre message. Il faut un
> `if … fi` complet, ou un `|| true`.
>
> **3. Les noms de fichiers à espaces.** `-printf '%s\t%p\n'` avec une tabulation en
> séparateur, puis `while IFS=$'\t' read -r t n` : le nom peut contenir n'importe
> quoi sauf une tabulation et un saut de ligne. `mapfile -t` pour les points de
> montage, jamais `for p in $(df …)`.
>
> **4. Le mode dégradé sans `sudo`.** `lsof +L1` ne voit que les processus de
> l'utilisateur courant, et `find /` génère des milliers de `Permission denied`. Le
> `2>/dev/null` sur les `find` et l'avertissement en tête de rapport rendent le
> comportement explicite au lieu de le masquer.
>
> **5. Séparation stdout / stderr.** Tout le rapport passe par `printf` sans
> redirection ; toute la trace passe par la fonction `trace()` qui écrit sur `>&2`.
> C'est ce qui permet `audit-fs.sh > rapport.md` sans polluer le Markdown, et
> `audit-fs.sh > /dev/null` pour ne voir que la progression.

> [!WARNING]
> **Piège**
>
> Trois détails de portabilité Ubuntu / Rocky 9 :
>
> * `df -P` et `df --output` sont **mutuellement exclusifs** : on choisit
>   `--output`, qui est plus précis et présent dans les deux distributions.
> * `df --output=ipcent` donne le pourcentage d'inodes ; il ne faut **pas** y ajouter
>   `-i`, qui provoque la même erreur d'exclusivité.
> * `lsof` n'est pas installé par défaut sur Rocky 9 minimal. Le repli sans `lsof` :
>   `ls -l /proc/*/fd 2>/dev/null | grep '(deleted)'`, moins précis car il ne donne
>   ni la taille ni le pid de façon exploitable.

<!-- nav:début -->
---

[← Module 01](../01-shell-bases/corrige.md) · [Énoncé](README.md) · [Module 03 →](../03-permissions/corrige.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
