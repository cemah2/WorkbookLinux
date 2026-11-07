<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Partie II — Administration système › **Module 11** · corrigé  
[← Module 10](../10-paquets/corrige.md) · [Énoncé](README.md) · [Module 12 →](../12-reseau/corrige.md)

> [!TIP]
> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, pas avant. Chaque identifiant renvoie à son énoncé.
<!-- nav:fin -->

# Module 11 — Corrigé

## 11.3 Quiz — QCM

<a id="q11-1"></a>**[Q11.1](README.md#q11-1)** — *Après remplacement d'un contrôleur, `sdb` et `sdc` ont échangé. Quelles lignes de `fstab` montent encore le bon volume ?*

**Réponses : b) et c)**

> [!NOTE]
> **Pourquoi**
>
> Il faut se demander, pour chaque identifiant, **où l'information est écrite** et
> **qui la fabrique**.
>
> `/dev/sdb1` (a) est fabriqué par le noyau au moment où il énumère les
> périphériques. C'est un compteur, pas une propriété du disque : premier disque SCSI
> détecté = `sda`, deuxième = `sdb`. Changer le contrôleur change l'ordre des
> réponses, donc les lettres. La ligne monte alors le mauvais volume — et si les deux
> sont formatés pareil, elle le monte **sans erreur**, ce qui est le pire des cas.
>
> `UUID=` (b) est un identifiant de 128 bits écrit par `mkfs` **dans la superblock du
> système de fichiers**. Il voyage avec les données : change le disque de port, de
> machine, de contrôleur, l'UUID suit. C'est le choix par défaut, et celui que
> l'installeur d'Ubuntu écrit tout seul.
>
> `/dev/vg_data/lv_sauv` (c) est un chemin de device-mapper construit par LVM à partir
> de **ses propres métadonnées**, écrites dans l'en-tête de chaque PV. Au démarrage,
> `lvm` scanne tous les périphériques bloc, retrouve ses PV par leur UUID LVM et
> réassemble les VG. Que le PV soit sur `sdb1` ou `sdc1` ne change rien au nom du LV.

> [!WARNING]
> **Piège**
>
> (d) `by-path` est le seul lien de `/dev/disk/` qui **ne** soit **pas** stable ici :
> il encode justement le chemin matériel (`pci-0000:00:10.0-scsi-0:0:1:0`). Changer la
> carte, c'est changer l'adresse PCI, donc le lien. `by-path` sert à identifier un
> **emplacement** (« le disque de la baie 3 »), ce qui est utile en datacenter, pas à
> identifier un contenu. Pour un identifiant matériel stable, c'est `by-id` qu'on
> utilise : il contient le numéro de série du disque.

---

<a id="q11-2"></a>**[Q11.2](README.md#q11-2)** — *Deux UUID dans la sortie de `lsblk -f` : lequel dans `fstab` ?*

**Réponse : b)** `UUID=8f3c1a2b-...`

> [!NOTE]
> **Pourquoi**
>
> La sortie contient deux UUID parce qu'il y a deux couches empilées, et chacune a le
> sien :
>
> * `sdb1` porte `FSTYPE=LVM2_member` et `UUID=kXd9Fe-...` : c'est l'**UUID de
>   PV LVM**, écrit dans l'en-tête du volume physique. Il ne désigne pas un système de
>   fichiers, il sert à LVM pour retrouver ses morceaux. On le reconnaît à son format
>   différent (groupes de 6 caractères séparés par des tirets) ;
> * `vg_data-lv_pgdata` porte `FSTYPE=ext4` et `UUID=8f3c1a2b-...` : c'est l'**UUID du
>   système de fichiers**, celui que `mount` sait résoudre.
>
> `fstab` monte un système de fichiers : c'est donc le second.
>
> Cela dit, pour un LV, le chemin `/dev/vg_data/lv_pgdata` est tout aussi valable et
> plus lisible : il est stable par construction, puisque c'est LVM qui le fabrique. La
> convention courante est UUID pour les partitions brutes, chemin `/dev/vg/lv` pour
> les volumes logiques.

---

<a id="q11-3"></a>**[Q11.3](README.md#q11-3)** — *Table de partitions pour un disque de 4 Tio.*

**Réponse : b)** GPT.

> [!NOTE]
> **Pourquoi**
>
> MBR stocke l'adresse de départ et la longueur de chaque partition sur **4 octets, en
> secteurs de 512 octets**. Le plafond arithmétique est donc
> 2³² × 512 = 2 Tio, adresse de départ comprise. Au-delà, les champs débordent
> silencieusement : la partition existe, elle est simplement fausse, et on perd les
> données au premier dépassement.
>
> GPT utilise des adresses sur 8 octets (LBA 64 bits), soit 8 Zio en secteurs de
> 512 o. Il apporte en prime deux choses qui comptent en exploitation :
> une **table de secours** recopiée en fin de disque (un secteur 0 abîmé ne détruit
> plus le partitionnement), et un **CRC32** sur les en-têtes et sur le tableau des
> entrées, qui permet de détecter une corruption au lieu de la subir.
>
> Petit détail à connaître : GPT conserve un « MBR de protection » au secteur 0, une
> fausse partition de type `0xEE` couvrant tout le disque, dont le seul rôle est
> d'empêcher un vieil outil MBR de croire que le disque est vierge.

---

<a id="q11-4"></a>**[Q11.4](README.md#q11-4)** — *`pvcreate /dev/sdb1` → `Device /dev/sdb1 not found`.*

**Réponse : b)** `sudo partprobe /dev/sdb`

> [!NOTE]
> **Pourquoi**
>
> Écrire une table de partitions, c'est écrire quelques octets au début d'un disque.
> Ça ne crée aucun fichier de périphérique. Les nœuds `/dev/sdb1`, `/dev/sdb2` sont
> créés par `udev` **quand le noyau annonce** une nouvelle partition, et le noyau ne
> relit la table que si on le lui demande (ou au démarrage).
>
> `partprobe` appelle l'ioctl `BLKRRPART` sur le disque : « relis ta table ». Le noyau
> émet alors les événements `udev` qui créent les nœuds. Les variantes :
>
> * `sudo partx -u /dev/sdb` — met à jour partition par partition, plus fin ;
> * `sudo blockdev --rereadpt /dev/sdb` — le même ioctl, sans dépendance à parted ;
> * `sudo udevadm settle` — attend que `udev` ait fini de créer les nœuds, utile dans
>   un script qui enchaîne `partprobe` et `mkfs`.
>
> En pratique, `parted` et `sgdisk` appellent déjà `BLKRRPART` eux-mêmes ; ça échoue
> silencieusement quand **une partition du disque est déjà utilisée** (montée, PV,
> membre RAID), car le noyau refuse alors de relire la table en entier.

> [!WARNING]
> **Piège**
>
> (d) est faux mais pas absurde : on **peut** faire `pvcreate /dev/sdb` sur le disque
> entier, sans table de partitions, et LVM fonctionnera. C'est même courant sur des
> LUN SAN. L'inconvénient : un disque sans table de partitions ressemble à un disque
> vierge pour tout outil qui ne connaît pas LVM, et on finit par se le faire écraser
> par un installeur trop serviable. La partition unique de type `8e00` est un panneau
> « occupé » lisible par tout le monde.

---

<a id="q11-5"></a>**[Q11.5](README.md#q11-5)** — *Réduire un XFS de 500 Go.*

**Réponse : c)** il n'y a pas de procédure : XFS ne se réduit pas.

> [!NOTE]
> **Pourquoi**
>
> Ce n'est pas un oubli des développeurs, c'est une conséquence de l'architecture.
> XFS découpe le volume en **groupes d'allocation** (AG) indépendants, chacun avec ses
> propres arbres B+ d'espace libre et d'inodes. Les numéros d'inodes encodent le
> numéro d'AG et le décalage à l'intérieur. Réduire le volume voudrait dire supprimer
> des AG, donc déplacer des inodes, donc **changer leur numéro** — ce qui casse tous
> les répertoires qui les référencent, les descripteurs ouverts, les handles NFS.
> Personne n'a jamais implémenté ça, et `xfs_growfs` n'a volontairement pas d'option
> de réduction.
>
> Conséquence pratique : sur un LV en XFS, `lvreduce` est une opération **à sens
> unique vers la destruction**. La seule procédure est : sauvegarder (`xfsdump` ou
> `tar`), `lvreduce`, `mkfs.xfs`, restaurer. Avec interruption de service.
>
> C'est le principal argument en faveur d'ext4 quand on ne sait pas encore comment le
> volume va évoluer, et l'argument pour **ne jamais surdimensionner un LV XFS** : on
> crée petit, on étend au besoin. Avec LVM, l'espace non alloué ne coûte rien.

> [!WARNING]
> **Piège**
>
> (b) `lvreduce -r` accepte la commande, appelle `fsadm`, qui détecte XFS et **refuse**
> proprement. Mais si tu passes `-f` pour forcer, `lvreduce` coupe le volume logique
> sans toucher au système de fichiers : XFS croit toujours avoir la taille d'avant et
> écrira au-delà de la fin du LV. Corruption garantie, souvent silencieuse pendant
> plusieurs jours.

---

<a id="q11-6"></a>**[Q11.6](README.md#q11-6)** — *Sixième champ de `fstab`.*

**Réponse : b)** l'ordre de passage de `fsck` au démarrage.

> [!NOTE]
> **Pourquoi**
>
> Les six champs, dans l'ordre : source, point de montage, type, options, `dump`,
> `pass`.
>
> Le cinquième (`dump`) est un vestige : il servait à l'utilitaire `dump` des années
> 80 pour savoir quels systèmes de fichiers sauvegarder. Plus personne ne l'utilise,
> on écrit `0`.
>
> Le sixième (`pass`) est bien vivant. `fsck` au démarrage le lit pour ordonner son
> travail :
>
> * `1` : vérifié en premier, **seul**. Réservé à `/` ;
> * `2` : vérifié après, et tous les `2` **en parallèle** s'ils sont sur des disques
>   différents ;
> * `0` : jamais vérifié au démarrage.
>
> On met `0` pour XFS et btrfs (ils n'ont pas de `fsck` au démarrage, ils rejouent leur
> journal au montage), pour les montages réseau, et pour tout volume de données qu'on
> ne veut pas voir bloquer un boot pendant vingt minutes. Un `2` sur un volume de
> 4 To d'archives, c'est une machine indisponible le jour où le compteur de montages
> déclenche une vérification complète.

---

<a id="q11-7"></a>**[Q11.7](README.md#q11-7)** — *Un NAS parfois éteint, et la VM doit démarrer quand même.*

**Réponses : a) et c)**

> [!NOTE]
> **Pourquoi**
>
> Deux mécanismes différents, complémentaires.
>
> `nofail` dit à systemd : si ce montage échoue, **ne fais pas échouer
> `local-fs.target`**. Sans lui, un montage en panne entraîne `local-fs.target` en
> échec, donc `multi-user.target` aussi, donc le basculement en `emergency.target` :
> la machine s'arrête au prompt de maintenance, sans réseau ni SSH. C'est exactement
> le scénario de BF11.1.
>
> `x-systemd.automount` change de stratégie : systemd ne monte plus le volume au
> démarrage, il installe un **point de montage automatique** (`autofs`). Le montage
> réel est déclenché par le premier accès au répertoire. Résultat : le boot ne dépend
> plus du tout du NAS, et si personne n'ouvre le répertoire, le montage n'est jamais
> tenté. On l'accompagne en général de
> `x-systemd.idle-timeout=600` pour démonter après dix minutes d'inactivité.
>
> En pratique on écrit les deux :
> `noauto,x-systemd.automount,x-systemd.idle-timeout=600,_netdev,nofail`.

> [!WARNING]
> **Piège**
>
> (b) `noauto` seul fonctionne… mais le volume n'est **jamais** monté, même quand le
> NAS est là. Il faut alors un `mount /point` manuel. C'est un piège classique en
> entretien : `noauto` et `x-systemd.automount` se ressemblent, l'un désactive, l'autre
> diffère.

---

<a id="q11-8"></a>**[Q11.8](README.md#q11-8)** — *`target is busy` : qui bloque ?*

**Réponse : b)** `sudo fuser -vm /srv/factura/db`

> [!NOTE]
> **Pourquoi**
>
> `fuser -m` prend un **point de montage** (ou n'importe quel chemin dessus) et liste
> tous les processus qui l'utilisent, quelle que soit la façon :
>
> ```console
> $ sudo fuser -vm /srv/factura/db
>                      UTIL.       PID ACCÈS  COMMANDE
> /srv/factura/db:     postgres   1842 ..c..  postgres
>                      factura    2311 F....  python3
>                      root       2450 ...e.  bash
> ```
>
> La colonne d'accès est la partie intéressante : `c` = le répertoire courant du
> processus est dedans, `f`/`F` = un fichier est ouvert (`F` en écriture), `e` = un
> exécutable en cours d'exécution est sur ce volume, `r` = c'est sa racine, `m` = un
> fichier est projeté en mémoire (`mmap`).
>
> `lsof /srv/factura/db` donne le même diagnostic avec les noms de fichiers, ce qui
> aide davantage. Attention à ne pas écrire `lsof +D /srv/factura/db` sur un gros
> volume : `+D` parcourt récursivement toute l'arborescence et peut prendre des
> minutes.

> [!WARNING]
> **Piège**
>
> `fuser` et `lsof` ne voient **que les processus**. Si le démontage échoue alors
> qu'aucun des deux ne renvoie rien, cherche ailleurs : un **montage imbriqué** ou un
> **bind mount** du même volume ailleurs dans l'arbre (`findmnt -R /srv/factura/db`,
> `grep factura /proc/self/mountinfo`), un fichier de swap actif dessus
> (`swapon --show`), un *loop device* dont le fichier de secours s'y trouve
> (`losetup -a`), ou un espace de noms de montage d'un conteneur. C'est le cœur de
> BF11.4.

---

<a id="q11-9"></a>**[Q11.9](README.md#q11-9)** — *`lvextend` a réussi, `df -h` n'a pas bougé.*

**Réponse : b)** le LV est plus grand, le système de fichiers ne l'est pas.

> [!NOTE]
> **Pourquoi**
>
> Ce sont deux couches indépendantes, et c'est tout l'intérêt de LVM. `lvextend`
> modifie les métadonnées du VG pour attribuer des extents supplémentaires au LV : le
> périphérique bloc `/dev/vg_data/lv_pgdata` devient plus grand, immédiatement,
> `lsblk` le confirme. Mais le système de fichiers posé dessus a sa propre idée de sa
> taille, écrite dans sa superblock : tant que personne ne la met à jour, il continue
> d'ignorer les blocs du bout.
>
> La mise à jour se fait avec `sudo resize2fs /dev/vg_data/lv_pgdata` pour ext4 (à
> chaud, sans démonter — l'agrandissement en ligne est supporté depuis longtemps) ou
> `sudo xfs_growfs /srv/factura/db` pour XFS (qui prend le **point de montage**, pas le
> périphérique, et exige que le volume soit monté).
>
> L'option `-r` (ou `--resizefs`) de `lvextend` fait exactement ça pour toi : elle
> appelle `fsadm`, qui identifie le système de fichiers et lance le bon outil. Prends
> l'habitude de toujours écrire `-r` : c'est une frappe de moins et un incident de
> moins.

> [!WARNING]
> **Piège**
>
> Sans `-r`, on croit souvent que « ça n'a pas marché » et on relance `lvextend`. Au
> bout de trois essais, le LV fait trois fois la taille prévue et on a mangé tout le
> VG. Vérifie toujours avec `lvs` avant de relancer une commande d'extension.

---

<a id="q11-10"></a>**[Q11.10](README.md#q11-10)** — *Snapshot en `swi-I-s---`.*

**Réponse : b)** le snapshot a débordé, il est invalide ; l'origine n'a rien.

> [!NOTE]
> **Pourquoi**
>
> Les attributs de `lvs` se lisent position par position. Pour un snapshot :
>
> ```text
> s w i - I - s - - -
> │ │ │   │   └── type de cible : (s)napshot
> │ │ │   └────── état : (a)ctif, (I)nvalide
> │ │ └────────── allocation : (i)nherited
> │ └──────────── permissions : (w)ritable
> └────────────── type de volume : (s)napshot
> ```
>
> Le `I` majuscule en cinquième position (état du volume) signale un snapshot
> **invalidé**. Cause unique : l'espace réservé à la table de copie sur écriture a été
> entièrement consommé. Le noyau ne peut plus sauvegarder les blocs modifiés, donc il
> ne peut plus garantir la vue figée qu'il promettait : il coupe le volume.
>
> Le point rassurant, et la question piège en entretien : **l'origine n'est jamais
> affectée**. Le snapshot stocke les *anciennes* versions des blocs modifiés ; s'il ne
> peut plus les stocker, on perd le snapshot, pas les données courantes. La base
> continue de tourner sans rien remarquer.
>
> Il n'y a rien à réparer : un snapshot invalide se supprime (`lvremove`) et se
> recrée, plus grand.

> [!WARNING]
> **Piège**
>
> Ne confonds pas avec `swi---s--p`, où le `p` final signale un volume **partiel**
> (un PV manquant), ni avec l'attribut `S` majuscule en première position qui désigne
> un snapshot fusionnant (`lvconvert --merge` en attente). Et surveille `data_percent`
> via `lvs`, pas `df` : `df` sur le snapshot monté te montre l'occupation du système
> de fichiers copié, pas le remplissage de la zone de copie sur écriture.

---

<a id="q11-11"></a>**[Q11.11](README.md#q11-11)** — *42 % d'utilisation et `No space left on device`.*

**Réponse : b)** les inodes sont épuisés.

> [!NOTE]
> **Pourquoi**
>
> Un système de fichiers ext4 gère deux ressources distinctes et **indépendamment
> épuisables** : les blocs de données et les inodes. Le nombre d'inodes est fixé
> définitivement par `mkfs`, à raison d'un inode pour 16 Ko par défaut sur Ubuntu.
> Un volume de 5 Gio reçoit donc environ 327 000 inodes. Le jour où une application
> crée 327 000 fichiers de 200 octets, elle a consommé 1,5 % de l'espace et 100 % des
> inodes.
>
> Le noyau renvoie `ENOSPC` dans les deux cas — d'où le message identique et la
> confusion. `df -i` tranche en deux secondes :
>
> ```console
> $ df -i /srv/factura/archives
> Sys. de fichiers Inodes   IUtil. ILibre IUti% Monté sur
> /dev/sdb1        327680   327680      0  100% /srv/factura/archives
> ```
>
> Trouver le coupable : `sudo find /srv/factura/archives -xdev -printf '%h\n' |
> sort | uniq -c | sort -rn | head` donne les répertoires par nombre d'entrées.

> [!WARNING]
> **Piège**
>
> (c) — un fichier supprimé mais tenu ouvert — produit le symptôme **inverse** :
> `df` dit plein, `du` dit vide. C'est un autre incident, traité au module 02.
> (d) un volume en lecture seule renvoie `EROFS` : `Read-only file system`, pas
> `ENOSPC`. (d) un quota dépassé renvoie `EDQUOT` : `Disk quota exceeded`. Le message
> d'erreur exact désigne toujours la bonne piste — encore faut-il le lire au lieu de
> lire « disque plein ».

---

<a id="q11-12"></a>**[Q11.12](README.md#q11-12)** — *Disque Proxmox agrandi de 30 à 60 Go, `/` toujours à 28 Go.*

**Réponse : b)** `growpart` → `pvresize` → `lvextend` → `resize2fs`

> [!NOTE]
> **Pourquoi**
>
> Chaque couche connaît sa taille et ignore celle des autres. Il faut les pousser
> **de bas en haut**, dans l'ordre de l'empilement :
>
> ```text
> disque virtuel /dev/sda   60 Go  <- qm resize (hyperviseur)
>  └─ partition /dev/sda3   28 Go  <- growpart
>      └─ PV LVM            28 Go  <- pvresize
>          └─ VG ubuntu-vg          (l'espace libre apparaît ici)
>              └─ LV ubuntu-lv      <- lvextend
>                  └─ ext4          <- resize2fs (ou lvextend -r)
> ```
>
> Sauter une étape ne casse rien, ça ne fait simplement rien : l'espace reste
> invisible une couche plus haut. C'est pourquoi la panne « j'ai agrandi le disque et
> il ne se passe rien » est si fréquente — la personne a fait une étape sur quatre.
>
> L'ordre inverse (a) est impossible : `resize2fs` refuserait d'agrandir au-delà du LV,
> `lvextend` n'aurait pas d'extents libres, etc. Chaque commande échoue proprement,
> sans dégât.

> [!WARNING]
> **Piège**
>
> (d) `systemd-growfs` existe bel et bien (`x-systemd.growfs` dans les options de
> `fstab`), mais il n'agrandit que le **système de fichiers**, à la dernière étape. Il
> ne touche ni à la partition, ni au PV, ni au LV. Sur les images cloud, ce qui fait
> le travail complet est `cloud-init` avec son module `growpart`, et seulement sur la
> partition racine, au premier démarrage.

---

<a id="q11-13"></a>**[Q11.13](README.md#q11-13)** — *RAID1 disparu ou renommé `/dev/md127` après redémarrage.*

**Réponses : a) et b)**

> [!NOTE]
> **Pourquoi**
>
> `mdadm --create` fait deux choses : il écrit une **superblock** sur chaque membre
> (en version 1.2 par défaut, à 4 Ko du début) et il assemble le tableau tout de suite.
> Il n'écrit **rien** dans la configuration du système.
>
> Au démarrage suivant, `udev` détecte les superblocks mdadm et lance un assemblage
> automatique « incrémental ». Faute de configuration lui indiquant le nom voulu, il
> utilise un nom anonyme en partant du haut : `/dev/md127`, puis `md126`, etc. Le
> tableau fonctionne, mais son nom a changé — et toute ligne de `fstab` ou de LVM qui
> référençait `/dev/md0` est cassée.
>
> La correction tient en deux commandes :
>
> ```bash
> sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
> sudo update-initramfs -u
> ```
>
> La première inscrit `ARRAY /dev/md0 metadata=1.2 name=lab-db:0 UUID=...`.
> La seconde est indispensable : l'assemblage a lieu **dans l'initramfs**, bien avant
> que `/etc/mdadm/mdadm.conf` du disque ne soit lisible. Sans regénération, l'initramfs
> contient l'ancienne configuration, et le problème persiste malgré un `mdadm.conf`
> parfaitement correct. C'est l'erreur numéro un sur ce sujet.

> [!WARNING]
> **Piège**
>
> (d) Le type de partition `fd00` (« Linux RAID ») est une bonne pratique
> documentaire, pas une obligation : mdadm identifie ses membres par leur superblock,
> pas par le type de partition. Sur un disque entier sans table de partitions, il n'y a
> d'ailleurs pas de type du tout et ça fonctionne très bien.

---

<a id="q11-14"></a>**[Q11.14](README.md#q11-14)** — *`iostat -xz` sur NVMe : 8200 r/s, `r_await` 0,28 ms, `%util` 99,8 %.*

**Réponse : b)** `%util` n'a pas de sens ici ; `await` sous 0,5 ms indique un disque à l'aise.

> [!NOTE]
> **Pourquoi**
>
> `%util` est défini comme « pourcentage de temps pendant lequel au moins une requête
> était en cours sur le périphérique ». Cette définition date des disques à plateaux,
> qui n'ont qu'une tête : une requête en cours = la tête occupée = saturation.
>
> Un NVMe a jusqu'à 64 000 files d'attente matérielles, un SSD SATA en a 32 (NCQ).
> « Au moins une requête en cours » peut signifier une requête sur soixante-quatre
> mille : `%util` sature à 100 % alors que le périphérique est utilisé à 2 % de sa
> capacité. La métrique n'est pas fausse, elle mesure simplement autre chose que ce
> qu'on croit.
>
> Ce qu'on regarde à la place, dans cet ordre :
>
> 1. `r_await` / `w_await` : latence de service moyenne, **en millisecondes**, file
>    d'attente comprise. Repères : NVMe sain < 1 ms, SSD SATA < 3 ms, disque 7200 tr/mn
>    ~10 ms, au-delà de 20 ms l'application souffre.
> 2. `r/s + w/s` : les IOPS réelles, à comparer à la fiche technique du matériel.
> 3. `aqu-sz` : profondeur de file moyenne. 2,45 est faible ; c'est quand elle grimpe
>    **et** que `await` grimpe avec elle qu'on est réellement en file d'attente.
> 4. `rkB/s` / `wkB/s` : le débit, pour distinguer une charge séquentielle d'une charge
>    aléatoire (ici 32,8 Mo/s pour 8200 IOPS = 4 Ko par requête, donc aléatoire pure).

---

<a id="q11-15"></a>**[Q11.15](README.md#q11-15)** — *Le fichier de swap disparaît après redémarrage.*

**Réponse : b)** il manque la ligne dans `/etc/fstab`.

> [!NOTE]
> **Pourquoi**
>
> `swapon` est une action ponctuelle, comme `mount` : elle déclare au noyau une zone
> d'échange et n'a aucun effet persistant. Au démarrage,
> `swapon --all` est exécuté (par `systemd`, via les unités `.swap` générées à partir
> de `fstab`) et n'active que ce qui y est déclaré.
>
> La ligne, avec sa syntaxe particulière — pas de point de montage, d'où le `none` :
>
> ```text
> /swapfile   none   swap   sw   0   0
> ```
>
> Pour une partition de swap, on écrit son UUID (`mkswap` en écrit un, `blkid` le
> montre), exactement comme pour un système de fichiers :
>
> ```text
> UUID=4f2b-...  none  swap  sw  0  0
> ```
>
> Vérification sans redémarrer : `sudo swapoff -a && sudo swapon -a && swapon --show`.

> [!WARNING]
> **Piège**
>
> Deux pièges classiques sur les fichiers de swap. Les droits : `chmod 600` est
> obligatoire, sinon `swapon` refuse — et pour cause, le fichier contient des pages
> mémoire de tous les processus. Et le système de fichiers hôte : sur **btrfs**, un
> fichier de swap ordinaire est rejeté (copie sur écriture) ; il
> faut le créer avec `btrfs filesystem mkswapfile`, ou poser `chattr +C` sur un fichier vide avant de le remplir — `dd` seul ne change rien. Sur ext4 et XFS,
> `fallocate` convient.

---

<a id="q11-16"></a>**[Q11.16](README.md#q11-16)** — *Troisième champ de `crypttab` à `none`.*

**Réponse : b)** aucune clé fournie, la phrase de passe est demandée au démarrage.

> [!NOTE]
> **Pourquoi**
>
> `/etc/crypttab` a quatre champs :
>
> ```text
> coffre  UUID=1a2b3c4d-...  none  luks,discard,x-systemd.device-timeout=30
>   1            2            3                     4
> ```
>
> 1. le nom du périphérique déchiffré → produit `/dev/mapper/coffre` ;
> 2. le **conteneur chiffré**, de préférence par son UUID LUKS
>    (`cryptsetup luksUUID /dev/sdc1`) ;
> 3. le fichier de clé, ou `none` ;
> 4. les options.
>
> Avec `none`, `systemd-cryptsetup` demande la phrase de passe sur la console au
> démarrage, via `systemd-ask-password`. La machine attend, indéfiniment par défaut :
> un serveur chiffré ne redémarre donc pas tout seul, ce qui est une décision
> d'architecture à assumer.
>
> Les alternatives : un fichier de clé sur un support amovible ou sur une partition
> racine déjà déchiffrée (`/etc/luks-keys/coffre.key`, en `chmod 400 root:root`), un
> déverrouillage par TPM (`systemd-cryptenroll --tpm2-device=auto`), ou un
> déverrouillage réseau par `dracut-sshd` / `dropbear-initramfs`.

---

<a id="q11-17"></a>**[Q11.17](README.md#q11-17)** — *Un ext4 sur disque iSCSI dans `fstab`, sans `_netdev` ni `nofail`.*

**Réponse : b)** le montage échoue au démarrage, le boot part en maintenance.

> [!NOTE]
> **Pourquoi**
>
> Sans `_netdev`, systemd classe le montage parmi les systèmes de fichiers locaux :
> l'unité `.mount` générée est ordonnée avant `local-fs.target`, qui est atteint bien
> avant que le réseau et `iscsid` ne soient prêts. Le périphérique n'existe pas encore, l'unité `.device` attend 90 s, le montage
> échoue et fait échouer `local-fs.target`, donc `multi-user.target`, donc
> `emergency.target`. Le symptôme est celui de BF11.1, avec une cause différente.
>
> `_netdev` déplace l'unité dans `remote-fs.target`, qui est ordonné après
> `network-online.target` (et `remote-fs-pre.target`, que `open-iscsi.service` précède). Pour les types reconnus comme réseau — `nfs`, `nfs4`,
> `cifs`, `glusterfs` — systemd le déduit du type et l'ajoute tout seul : un montage NFS sans `_netdev` ne produit **pas** ce symptôme. L'écrire reste la bonne pratique pour NFS aussi ( ça documente l'intention),
> et c'est **indispensable** dès que le type ne trahit pas le réseau : ext4 ou XFS sur iSCSI, sur un disque `rbd`,
> sur un `nbd`.
>
> La ligne complète d'un montage NFS de production :
>
> ```text
> 10.10.10.10:/srv/exports/archives  /mnt/archives-adm  nfs4
>   ro,_netdev,nofail,hard,timeo=600,retrans=2,noatime,nconnect=4  0  0
> ```

---

<a id="q11-18"></a>**[Q11.18](README.md#q11-18)** — *Des millions de petits fichiers : quelle option `mkfs.ext4` ?*

**Réponse : c)** `mkfs.ext4 -i 8192` (ou `-N <nombre>`)

> [!NOTE]
> **Pourquoi**
>
> `-i` fixe le **ratio octets par inode**. La valeur par défaut d'Ubuntu est 16384 :
> un inode pour 16 Ko d'espace. `-i 8192` double le nombre d'inodes, `-i 4096` le
> quadruple. `-N` permet de donner directement le nombre voulu, ce qui est plus lisible
> quand on connaît la cible : `mkfs.ext4 -N 4000000 /dev/vg_data/lv_sauv`.
>
> Le coût est réel et il faut le mesurer : un inode ext4 pèse 256 octets. Quatre
> millions d'inodes, c'est 1 Gio d'espace consommé avant même le premier fichier. On ne
> met donc pas `-i 4096` partout « au cas où ».
>
> Les raccourcis `-T` donnent des profils tout faits, définis dans
> `/etc/mke2fs.conf` : `-T small`, `-T news` (un inode pour 4 Ko), `-T largefile`
> (un pour 1 Mio), `-T largefile4` (un pour 4 Mio).
>
> Et le point le plus important : **ce paramètre n'est pas modifiable après coup**.
> Aucune commande n'ajoute d'inodes à un ext4 existant. La seule échappatoire est
> `resize2fs` en **agrandissement**, qui ajoute des groupes de blocs, donc des inodes,
> au même ratio. Si le ratio initial était mauvais, il faudra agrandir énormément pour
> s'en sortir. XFS, lui, alloue ses inodes dynamiquement et ne connaît pas ce problème
> (dans la limite d'`imaxpct`, 25 % par défaut).

> [!WARNING]
> **Piège**
>
> (b) `-T largefile` fait exactement l'inverse de ce qu'on demande : un inode par
> Mio, soit 5 120 inodes sur 5 Gio. C'est le réglage idéal pour un dépôt d'images
> disque ou de vidéos, et le meilleur moyen de se retrouver en pénurie d'inodes au
> bout de trois jours sur un cache applicatif. (a) `-m 0` libère les 5 % réservés à
> root, ce qui donne de l'espace, pas des inodes. (d) désactiver le journal améliore
> les performances d'écriture et supprime la résistance aux coupures : mauvaise idée
> sur un volume de production, et sans rapport avec les inodes.

---

<a id="q11-19"></a>**[Q11.19](README.md#q11-19)** — *`md0 : active raid1 sdc1[1] sdb1[0](F)`, `[2/1] [_U]`.*

**Réponse : b)**

> [!NOTE]
> **Pourquoi**
>
> Trois informations dans deux lignes. `(F)` derrière `sdb1` : *faulty*, le noyau a
> sorti ce membre du tableau après une erreur d'E/S (ou un `mdadm --fail`). `[2/1]` :
> deux membres attendus, un seul actif. `[_U]` : la position 0 (`sdb1`) est vide, la
> position 1 (`sdc1`) est à jour. Le miroir fonctionne, mais il n'y a **plus aucune
> redondance** : la prochaine erreur sur `sdc1` est une perte de données.
>
> La première commande est `mdadm --detail /dev/md0`, parce qu'elle donne ce que
> `/proc/mdstat` ne dit pas : `State : clean, degraded`, `Failed Devices : 1`, la date
> de mise à jour du tableau, et l'`Events` count. Croisée avec
> `journalctl -k | grep md0` (`md/raid1:md0: Disk failure on sdb1, disabling device`),
> elle date la panne. Ensuite seulement on décide : disque réellement mort (SMART,
> `dmesg` plein d'erreurs `I/O error`) → remplacer ; fausse alerte (câble, contrôleur,
> `--fail` manuel) → `--remove` puis `--re-add`.

> [!WARNING]
> **Piège**
>
> (d) `mdadm --create` sur des membres existants **écrase les superblocks** et
> déclenche une synchronisation dans un sens choisi par mdadm, pas par toi. C'est la
> commande qui transforme un tableau dégradé en tableau vide. On ne recrée jamais un
> tableau pour le réparer ; on l'assemble (`--assemble`) ou on lui ajoute un membre
> (`--add`).

---

<a id="q11-20"></a>**[Q11.20](README.md#q11-20)** — *`root` du client crée un fichier, il appartient à `nobody:nogroup`.*

**Réponse : b)**

> [!NOTE]
> **Pourquoi**
>
> `root_squash` est le comportement **par défaut** d'un export NFS, qu'on l'écrive ou
> non dans `/etc/exports` (`exportfs -v` l'affiche parmi les options ajoutées). Toute
> requête arrivant avec l'UID 0 est réécrite côté serveur avec `anonuid`/`anongid`,
> 65534 par défaut, soit `nobody:nogroup` sur Ubuntu. L'objectif est simple : root
> d'une machine cliente compromise ne doit pas pouvoir devenir root sur le serveur de
> fichiers via le partage. Les utilisateurs ordinaires, eux, passent avec leur UID
> numérique : un fichier créé par `mathieu` (UID 1000) sur `lab-db` appartient à l'UID
> 1000 côté serveur, quel que soit le nom qui porte cet UID là-bas.

> [!WARNING]
> **Piège**
>
> (c) Le domaine `idmapd` ne joue que pour la **traduction des noms** en NFSv4 : si
> les domaines diffèrent, c'est *tous* les fichiers qui apparaissent en `nobody` côté
> client, pas seulement ceux créés par root — et les permissions restent calculées
> avec les UID numériques (`sec=sys`). Sur des systèmes récents,
> `nfs4_disable_idmapping=1` est la valeur par défaut : les UID circulent en clair et
> `idmapd` n'intervient qu'avec Kerberos. (a) NFSv3 ou v4 ne change rien à
> `root_squash`.

---

<a id="q11-21"></a>**[Q11.21](README.md#q11-21)** — *`iSCSI login failed due to authorization failure`.*

**Réponses : a) et c)**

> [!NOTE]
> **Pourquoi**
>
> Le message vient de la cible, donc le réseau et le port passent : on a réussi à
> parler à LIO et il a **refusé** la session. Deux vérifications côté cible expliquent
> 99 % des cas : l'ACL (`ls /iscsi/<iqn>/tpg1/acls` dans `targetcli`) ne contient pas
> exactement l'IQN annoncé par l'initiateur — une faute de frappe dans
> `/etc/iscsi/initiatorname.iscsi`, ou un `iscsid` pas redémarré après modification —
> ou les identifiants CHAP du nœud côté client ne correspondent pas à ceux posés sur
> l'ACL (`node.session.auth.username`, `.password`). Un `journalctl -u
> rtslib-fb-targetctl` ou `dmesg` côté cible montre `iSCSI Initiator Node:
> iqn.... is not authorized to access iSCSI target portal group: 1`.

> [!WARNING]
> **Piège**
>
> (b) Un port filtré donne `iscsiadm: cannot make connection to 10.10.10.14: No
> route to host` ou un délai d'attente, et la découverte aurait déjà échoué. (d) Un
> backstore plein produit des erreurs d'E/S une fois connecté, jamais un refus
> d'ouverture de session.

---

<a id="q11-22"></a>**[Q11.22](README.md#q11-22)** — `fio` *: 7 980 IOPS, `clat` moyen 4 005 μs, `iostat` : `r_await` 4 ms, `aqu`*`-sz` *31,8.*

**Réponse : b)**

> [!NOTE]
> **Pourquoi**
>
> Loi de Little : *requêtes en vol = débit × temps de séjour*. 7 980 IOPS × 4,0 ms =
> 31,9 ≈ la profondeur de file demandée (32). Les trois outils racontent la même
> histoire : `fio` maintient 32 requêtes en permanence, le périphérique en sert ~8 000
> par seconde, chacune attend donc en moyenne 4 ms **dans la file**. La latence du
> support lui-même est bien plus faible : à `iodepth=1` on mesurerait quelques
> centaines de μs sur un SSD. C'est pour ça qu'un test de latence se fait à
> `iodepth=1` et un test de débit à `iodepth` élevé, et qu'on ne compare jamais les
> deux.

> [!WARNING]
> **Piège**
>
> (d) Augmenter `iodepth` **augmente** la latence par requête tant que le périphérique
> est saturé : le débit plafonne, les requêtes attendent plus longtemps. (a) 4 ms
> n'est ni bon ni mauvais sans la profondeur de file : c'est la valeur attendue pour
> 8 000 IOPS à 32 en vol.

---

## 11.4 Quiz — questions ouvertes

<a id="qo11-1"></a>**[QO11.1](README.md#qo11-1)** — *La chaîne complète du disque physique au répertoire utilisable.*

**Réponse attendue**

```text
1. Disque physique / virtuel      /dev/sdb        (rien à faire, ou qm resize)
2. Table de partitions            GPT             parted / sgdisk / fdisk
3. Partition                      /dev/sdb1       + partprobe
4. (option) RAID logiciel         /dev/md0        mdadm --create
5. (option) Chiffrement           /dev/mapper/x   cryptsetup luksFormat/luksOpen
6. Volume physique LVM            PV              pvcreate
7. Groupe de volumes              vg_data         vgcreate / vgextend
8. Volume logique                 lv_pgdata       lvcreate
9. Système de fichiers            ext4 / XFS      mkfs.ext4 / mkfs.xfs
10. Montage                       /srv/factura/db mount + /etc/fstab
11. Permissions                   chown / chmod   (module 03)
```

> [!NOTE]
> **Pourquoi**
>
> L'intérêt de la question n'est pas la liste, c'est de savoir **ce qu'on paie en
> sautant une couche**. Réponses attendues :
>
> * **Sauter la table de partitions** (PV ou FS directement sur `/dev/sdb`) : ça
>   marche, c'est même courant sur les LUN SAN, mais le disque ressemble à un disque
>   vierge pour tout outil qui ne connaît pas LVM. Risque d'écrasement par un
>   installeur ou un collègue.
> * **Sauter LVM** (FS directement sur la partition) : on gagne une couche de
>   complexité en moins et un chemin d'E/S marginalement plus court. On perd
>   l'extension à chaud, les snapshots, le `pvmove`, et la possibilité d'agréger
>   plusieurs disques. Sur un serveur, LVM se justifie presque toujours ; sur un
>   conteneur ou une VM jetable recréée par Terraform, non.
> * **Sauter le RAID** : on accepte de perdre le volume à la première panne de disque.
>   Acceptable si la couche du dessous est déjà redondante (SAN, stockage Ceph de
>   Proxmox), inacceptable sur des disques locaux.
> * **Sauter le chiffrement** : question de conformité, pas de technique. LUKS coûte
>   quelques pour cent de CPU avec AES-NI, ce qui est négligeable ; ce qu'il coûte
>   vraiment, c'est l'impossibilité de redémarrer sans intervention humaine.
>
> L'ordre des couches 5 et 6 mérite une phrase : chiffrer **au-dessus** de LVM (un LV
> par conteneur LUKS) permet de ne chiffrer que ce qui doit l'être et de conserver
> `lvextend` ; chiffrer **en dessous** (un PV posé sur un LUKS) chiffre tout le VG
> avec une seule phrase de passe. Les deux se défendent ; c'est la question finale du
> défi D11.

---

<a id="qo11-2"></a>**[QO11.2](README.md#qo11-2)** — *Pourquoi jamais `/dev/sdb1` dans `fstab` ; UUID vs PARTUUID vs LABEL.*

**Réponse attendue**

Le mécanisme : les noms `sdX` sont attribués par le pilote `sd` du noyau **dans
l'ordre où les périphériques sont découverts**, pas selon une propriété du matériel.
La découverte est asynchrone : plusieurs contrôleurs sondent en parallèle, le
premier à répondre prend la première lettre. Ajouter un disque, changer un câble,
brancher une clé USB au démarrage, ou simplement redémarrer sur un noyau qui sonde
plus vite, suffit à permuter `sdb` et `sdc`. Le noyau ne garantit rien à ce sujet et
ne l'a jamais garanti.

| Identifiant | Écrit dans | Cas d'usage |
|---|---|---|
| `UUID=` | superblock du FS | le cas général, tout ce qui est formaté |
| `PARTUUID=` | entrée GPT | partition brute, swap, volume non formaté |
| `LABEL=` | superblock du FS | lisible, pratique, mais se duplique |

Pour une **partition de swap**, `mkswap` écrit un UUID dans son en-tête, on peut donc
utiliser `UUID=`. Si le volume n'a aucun contenu identifiable (partition brute passée
à une application, LUN transmis à une VM), `PARTUUID=` est le seul recours, et il
n'existe que sur GPT.

> [!NOTE]
> **Pourquoi**
>
> Le point que peu de gens savent expliquer : `LABEL` et `UUID` sont **tous les deux**
> dans la superblock, donc tous les deux perdus par un `mkfs`. La différence est
> l'unicité. Un UUID est tiré aléatoirement sur 122 bits utiles : la collision est
> inatteignable. Un `LABEL` est choisi par un humain, et le jour où tu clones une VM,
> tu as deux volumes `donnees` sur la même machine. `mount LABEL=donnees` en choisit un
> — lequel ? Celui que `blkid` a vu en dernier. C'est non déterministe, et ça se
> manifeste une fois sur dix au redémarrage. D'où la règle : `LABEL` pour l'humain qui
> lit `lsblk -f`, `UUID` pour la machine qui lit `fstab`.
>
> À noter : cloner un disque avec `dd` copie aussi l'UUID. Deux volumes de même UUID
> sur une machine produisent exactement le même non-déterminisme. `tune2fs -U random
> /dev/sdX1` (ext4) ou `xfs_admin -U generate` (XFS) règle le problème.

---

<a id="qo11-3"></a>**[QO11.3](README.md#qo11-3)** — *Copie sur écriture d'un snapshot, bloc par bloc.*

**Réponse attendue**

À la création du snapshot, **aucune donnée n'est copiée**. LVM alloue une zone
d'exception vide (les 2 Go demandés) et une table de correspondance, puis fait
pointer le nouveau périphérique `/dev/vg/snap` sur l'origine.

Ensuite, à chaque écriture sur l'origine :

1. le device-mapper intercepte l'écriture ;
2. il regarde si le *chunk* concerné (4 Kio par défaut, `lvcreate -c`) a déjà été copié ;
3. si non : il **lit l'ancien contenu du chunk sur l'origine, l'écrit dans la zone
   d'exception du snapshot**, note la correspondance dans la table, puis laisse
   l'écriture se faire sur l'origine ;
4. si oui : il laisse simplement l'écriture se faire.

Une lecture depuis le snapshot consulte la table : si le chunk a été copié, elle lit
la copie ; sinon elle lit l'origine, qui n'a pas changé pour ce chunk.

**Dimensionnement** : la taille du snapshot doit couvrir le volume de **données
modifiées pendant sa durée de vie**, pas la taille de l'origine. Pour une sauvegarde
de 20 minutes sur une base qui écrit 5 Mo/s, 20 × 60 × 5 = 6 Go suffisent largement,
quelle que soit la taille de la base. En pratique on prend 10 à 20 % de l'origine, et
surtout on le **supprime dès que la sauvegarde est finie**.

**Débordement** : la zone d'exception est pleine, le device-mapper ne peut plus
copier l'ancien contenu, donc il ne peut plus garantir la vue figée. Il invalide le
snapshot (`swi-I-s---`), toute lecture échoue (`can't read superblock`).
**L'origine n'est pas touchée** : elle n'a jamais cessé d'être la version courante.

> [!NOTE]
> **Pourquoi**
>
> Deux conséquences qui tombent souvent en entretien.
>
> La **pénalité d'écriture** : tant qu'un snapshot existe, chaque première écriture sur
> un chunk coûte une lecture + deux écritures au lieu d'une. Sur une base de données
> active, la latence d'écriture peut doubler. C'est la vraie raison pour laquelle on ne
> laisse pas traîner un snapshot LVM classique : ce n'est pas l'espace, c'est le coût
> en E/S. Le thin provisioning règle ce point (la copie sur écriture y est native et ne
> paie pas la recopie).
>
> Le **sens de la copie** : beaucoup de gens croient que le snapshot contient la copie
> des données au moment T. C'est faux, et c'est ce qui explique tout le reste. Il
> contient les **anciennes versions des blocs modifiés depuis T**. Un snapshot d'un
> volume inactif reste vide indéfiniment.

---

<a id="qo11-4"></a>**[QO11.4](README.md#qo11-4)** — *Ajouter 100 Go à `/var` sans arrêter le service.*

**Réponse attendue**

```bash
# 1. le disque est branché, on le voit
lsblk
# 2. partition de type LVM
sudo sgdisk -n 1:0:0 -t 1:8e00 /dev/sdd && sudo partprobe /dev/sdd
# 3. volume physique
sudo pvcreate /dev/sdd1
# 4. on l'ajoute au groupe existant
sudo vgextend vg_system /dev/sdd1
# 5. on étend le LV ET le système de fichiers, en une commande, à chaud
sudo lvextend -L +100G -r /dev/vg_system/lv_var
# 6. contrôle
df -h /var
```

Zéro démontage, zéro redémarrage, zéro arrêt de service. Les écritures en cours ne
sont pas interrompues : `lvextend` modifie des métadonnées, `resize2fs` en ligne
ajoute des groupes de blocs à la fin du volume sans toucher aux existants.

> [!NOTE]
> **Pourquoi**
>
> La réponse à « où aurait été la coupure sans LVM » est le cœur de la question.
>
> Sans LVM, `/var` est une partition. Une partition est une **plage contiguë de
> secteurs** définie par un début et une longueur. Pour l'agrandir, il faut de l'espace
> libre **immédiatement après elle** sur le même disque. Or la partition suivante est
> occupée. Il faudrait donc :
>
> 1. démonter `/var` — impossible à chaud, tous les services écrivent dedans, il faut
>    au minimum passer en mode mono-utilisateur ;
> 2. déplacer la partition suivante (`parted` sait le faire, lentement et
>    dangereusement), ou sauvegarder `/var`, supprimer la partition, la recréer plus
>    grande, restaurer.
>
> Dans les deux cas : **arrêt complet du service, une fenêtre de maintenance, un
> risque de perte de données**. Sur une base de 500 Go, ça se compte en heures.
>
> L'innovation de LVM tient en une phrase : un volume logique est une **liste
> d'extents**, pas une plage contiguë. Les extents peuvent venir de n'importe quel PV
> du groupe, dans n'importe quel ordre. « Agrandir » revient à ajouter des entrées dans
> une liste — une écriture de quelques kilo-octets de métadonnées. Le reste (le
> système de fichiers qui découvre les nouveaux blocs) est de la comptabilité.

---

<a id="qo11-5"></a>**[QO11.5](README.md#qo11-5)** — *ext4 vs XFS sur cinq critères, et trois cas concrets.*

**Réponse attendue**

| Critère | ext4 | XFS |
|---|---|---|
| Agrandir | en ligne, `resize2fs` | en ligne, `xfs_growfs` |
| Réduire | oui, hors ligne | **impossible** |
| Gros fichiers, gros volumes | correct | conçu pour, extents + AG parallèles |
| Réparation | `e2fsck`, robuste, bien documenté | `xfs_repair`, exige de la RAM, dernier recours |
| Coût d'un `fsck` | linéaire avec le nombre d'inodes : long sur gros volume | pas de `fsck` périodique, rejeu du journal au montage |

* **Volume de logs** : ext4. Beaucoup de petits fichiers, rotation permanente,
  volume modeste, et on peut vouloir le réduire un jour. Avec `-i 8192` si la
  rotation produit des millions de fichiers.
* **Datastore PostgreSQL de 4 To** : XFS, c'est d'ailleurs le défaut de Red Hat et la
  recommandation de la plupart des éditeurs de SGBD. Les groupes d'allocation
  permettent à plusieurs processus d'allouer en parallèle sans se marcher dessus,
  l'allocation différée réduit la fragmentation, et un `e2fsck` sur 4 To d'ext4 se
  compte en heures pendant lesquelles la base est indisponible.
* **`/` de 20 Go sur une VM** : ext4. Petit, réparable facilement depuis un live CD,
  outillage universel, et c'est ce que tout le monde connaît dans l'équipe à 3 h du
  matin. Le gain de performance de XFS est nul à cette taille.

> [!NOTE]
> **Pourquoi**
>
> Le critère qu'on oublie toujours est le dernier : **ce que l'équipe sait réparer**.
> Un système de fichiers exotique qui va 8 % plus vite et que personne ne sait
> diagnostiquer est un mauvais choix d'exploitation.
>
> Le second critère sous-estimé est la réductibilité, parce qu'on croit toujours qu'on
> ne réduira jamais. En pratique, on réduit : pour libérer des extents qui manquent
> ailleurs dans le VG, pour rendre de l'espace au VG avant un `pvmove`, pour corriger
> un LV créé trois fois trop grand par erreur. Avec XFS, chacun de ces cas devient une
> opération de sauvegarde-restauration.
>
> À propos de btrfs : il apporte les snapshots natifs, les sous-volumes et les sommes
> de contrôle de données (détection de corruption silencieuse), ce qu'aucun des deux
> autres n'offre. Son `df` est trompeur (utilise `btrfs filesystem usage`), ses modes
> RAID 5 et 6 sont toujours déconseillés en production, et Red Hat l'a retiré de RHEL.
> Il est solide sur du poste de travail et chez SUSE ; sur un serveur d'entreprise, on
> reste sur ext4 ou XFS.

---

<a id="qo11-6"></a>**[QO11.6](README.md#qo11-6)** — *Démarche face à un `target is busy` ; `umount -l` vs `umount -f`.*

**Réponse attendue**

```bash
# 1. qui utilise le point de montage, et comment
sudo fuser -vm /srv/sauvegardes
# 2. quels fichiers exactement (plus lisible pour décider)
sudo lsof /srv/sauvegardes
# 3. si les deux ne renvoient rien : chercher un montage imbriqué ou un bind
findmnt -R /srv/sauvegardes
grep sauvegardes /proc/self/mountinfo
# 4. un swap actif sur le volume ?
swapon --show
# 5. un loop device dont le fichier support est dedans ?
losetup -a
# 6. on traite la cause : arrêt du service, démontage du bind, swapoff...
sudo systemctl stop factura.service
sudo umount /srv/sauvegardes
```

**`umount -l` (lazy)** : détache immédiatement le point de montage de l'arborescence
— plus personne ne peut y accéder par son chemin — mais le système de fichiers reste
monté tant qu'un descripteur est ouvert dessus. Le démontage réel a lieu à la
fermeture du dernier. Risque : on croit avoir démonté, on lance un `mkfs` ou un
`lvremove` sur le volume, et on détruit un système de fichiers encore actif. Un
`findmnt` ne le montre plus ; `cat /proc/mounts` ou `lsof` si.

**`umount -f` (force)** : interrompt les E/S en cours et démonte. Prévu pour les
montages **réseau** dont le serveur ne répond plus (NFS surtout). Sur un système de
fichiers local, il ne sert quasiment à rien (le noyau refuse toujours si le volume
est occupé) et provoque au mieux des erreurs d'E/S dans les applications, au pire
une perte des écritures non encore vidées.

> [!NOTE]
> **Pourquoi**
>
> Règle d'exploitation : `-l` et `-f` traitent le symptôme, pas la cause. Le bon
> réflexe est d'arrêter proprement ce qui utilise le volume. Les deux options se
> justifient dans deux cas précis : `-f` sur un NFS dont le serveur est mort et qui
> bloque des processus en état `D` ; `-l` pour détacher un volume avant un arrêt
> planifié quand on sait que les processus vont se terminer seuls dans les secondes
> qui suivent.
>
> Le piège de `fuser -km` : il envoie `SIGKILL` à tout ce qui touche le volume. Si le
> volume est `/srv` et qu'un processus critique y a son répertoire courant, tu viens de
> tuer la production pour démonter un volume de sauvegarde. Toujours lancer
> `fuser -vm` **avant** pour lire la liste, et `fuser -km` seulement en connaissance de
> cause.

---

<a id="qo11-7"></a>**[QO11.7](README.md#qo11-7)** — *Faut-il du swap sur un serveur avec 128 Go de RAM ?*

**Réponse attendue**

**Contre le swap** : quand une machine se met à swapper activement, les latences
explosent (une page sur disque, même NVMe, c'est 10 000 fois plus lent que la RAM).
L'application ne plante pas, elle devient inutilisable — ce qui est souvent pire
qu'un plantage franc pour un système supervisé, parce que les sondes de santé
répondent encore et qu'aucun basculement automatique ne se déclenche.

**Pour le swap** : il ne sert pas seulement de « RAM d'urgence ». Le noyau s'en sert
pour **évacuer les pages anonymes froides** — l'initialisation d'un démon lancé il y
a six mois et jamais rappelée — et rendre cette RAM au cache de pages, qui lui est
utile. Sans swap, ces pages restent en mémoire pour rien. Sans swap, aussi, le noyau
n'a qu'un seul levier en cas de pression mémoire : l'OOM killer, qui tue un processus
choisi par heuristique, souvent le plus gros, c'est-à-dire la base de données.

`vm.swappiness` (0 à 200, 60 par défaut) règle l'arbitrage entre évacuer des pages
anonymes et libérer du cache de fichiers. Contrairement à une idée reçue ce **n'est
pas** un pourcentage de RAM libre déclencheur : c'est un poids relatif dans le calcul
de récupération du noyau. `0` ne désactive pas le swap, il dit « n'évacue des pages
anonymes qu'en tout dernier recours ».

**Recommandation** : garder du swap, dimensionné petit (2 à 8 Go sur une machine de
128 Go — il ne sert pas à absorber une fuite mémoire), avec `vm.swappiness=10`, et
**surveiller `si`/`so` de `vmstat 1`**, pas la quantité de swap utilisée. Du swap
occupé n'est pas un problème ; du swap qui entre et sort en permanence l'est.

> [!NOTE]
> **Pourquoi**
>
> Le point technique qui fait la différence en entretien : distinguer « du swap est
> utilisé » de « la machine swappe ». La première mesure est statique et bénigne, la
> seconde est dynamique et pathologique. `vmstat 1` colonnes `si` (swap in) et `so`
> (swap out) : si elles restent à 0 alors que 3 Go de swap sont occupés, tout va bien,
> ce sont des pages froides bien rangées.
>
> Cas particulier à citer : **Kubernetes** a longtemps exigé `swapoff -a`, parce que le
> swap rend les limites mémoire des cgroups ininterprétables et fausse l'éviction des
> pods. Le support du swap est revenu en bêta à partir de la 1.28 sur cgroup v2, mais
> la plupart des clusters en production tournent encore sans swap. C'est le seul cas
> où « pas de swap du tout » est la bonne réponse — et c'est une contrainte de
> l'orchestrateur, pas une vérité générale.

---

<a id="qo11-8"></a>**[QO11.8](README.md#qo11-8)** — *Récupérer une machine bloquée par un `fstab` fautif, console Proxmox uniquement.*

**Réponse attendue**

**Ce qu'on voit** : le démarrage s'arrête sur un `A start job is running for
/dev/disk/by-uuid/...` qui compte jusqu'à 1 min 30 s, puis
`Dependency failed for Local File Systems`, puis le prompt
`Give root password for maintenance (or press Control-D to continue)`.

**Obtenir un shell — cas 1, un mot de passe root existe** : le saisir. On obtient un
shell root en `emergency.target`.

**Cas 2, Ubuntu par défaut, le compte root est verrouillé** : aucun mot de passe ne
marche. Il faut passer par GRUB.

1. Redémarrer, maintenir `Shift` (BIOS) ou `Échap` (UEFI) pour afficher le menu GRUB.
2. Sur l'entrée Ubuntu, appuyer sur `e`.
3. Sur la ligne commençant par `linux`, remplacer `ro` par `rw` et ajouter à la fin :
   `init=/bin/bash`
4. `Ctrl-X` pour démarrer. On obtient un shell root sans authentification, avec
   `/` accessible en écriture.

**Réparation** :

```bash
mount -o remount,rw /          # si l'on n'a pas mis rw sur la ligne GRUB
findmnt --verify --verbose     # dit quelle ligne est fautive
vi /etc/fstab                  # corriger ou commenter la ligne
blkid                          # relever le vrai UUID
mount -a                       # valider : plus aucune erreur
sync
exec /sbin/init                # ou : reboot -f
```

**Pourquoi `/` est en lecture seule** : le noyau monte la racine en lecture seule à
la fin de l'initramfs, volontairement, pour qu'un `fsck` puisse encore la réparer.
C'est `systemd-remount-fs.service` qui la repasse en lecture-écriture, très tôt dans
la séquence. Avec `init=/bin/bash`, systemd n'est jamais démarré : personne ne fait
ce remontage, d'où le `mount -o remount,rw /`. En `emergency.target` en revanche,
`systemd-remount-fs` a déjà tourné et `/` est généralement déjà accessible en
écriture — mais on vérifie toujours avec `findmnt /` avant d'éditer.

**Les deux options qui évitent l'incident** :

* `nofail` — le montage peut échouer sans faire échouer `local-fs.target` ;
* `x-systemd.device-timeout=10s` — ramène l'attente de 1 min 30 s à 10 s.
  (Le timeout par défaut de 90 s vient de `DefaultDeviceTimeoutSec` appliqué à l'unité
  `.device` que systemd génère pour attendre l'apparition de l'UUID.)

> [!NOTE]
> **Pourquoi**
>
> La véritable compétence testée ici est la discipline de vérification. `findmnt
> --verify` et `mount -a` prennent dix secondes et détectent l'erreur avant le
> redémarrage. Dans les équipes sérieuses, éditer `fstab` sans les lancer est considéré
> comme une faute au même titre que modifier une conf nginx sans `nginx -t`.
>
> Bonus qui impressionne en entretien : on n'est même pas obligé d'aller jusqu'au
> `init=/bin/bash`. Ajouter `systemd.unit=emergency.target` à la ligne noyau donne le
> même prompt de maintenance mais plus tôt ; et sur une machine dont on sait que seul
> un montage secondaire pose problème, `systemd.mask=srv-factura-archives.mount`
> (le nom de l'unité, avec les `-` à la place des `/`) permet de démarrer normalement
> en ignorant ce seul montage. C'est la solution la plus chirurgicale.

---

<a id="qo11-9"></a>**[QO11.9](README.md#qo11-9)** — *Lire un `iostat -xz 2`.*

**Réponse attendue**

Ordre de lecture, et ce que chaque métrique apporte :

1. **`r_await` / `w_await`** (ms) — latence de service moyenne, file d'attente
   comprise. C'est la métrique reine : c'est ce que l'application ressent.
   Repères : NVMe < 1 ms, SSD SATA < 3 ms, disque 7200 tr/mn ~10 ms. Au-delà de
   20 ms sur un SSD, il y a un problème réel.
2. **`r/s` + `w/s`** — les IOPS. À comparer à ce que le matériel sait faire
   (~150 IOPS pour un disque 7200, ~80 000 pour un SSD SATA, plusieurs centaines de
   milliers pour un NVMe).
3. **`rkB/s` / `wkB/s`** — le débit. Divisé par les IOPS, il donne la taille moyenne
   des requêtes, ce qui dit si la charge est séquentielle (centaines de Ko) ou
   aléatoire (4 à 16 Ko). Les deux n'ont pas du tout le même coût.
4. **`aqu-sz`** — profondeur de file moyenne. Utile seulement corrélée à `await` :
   file qui monte **et** latence qui monte = saturation réelle.
5. **`%util`** — en dernier, et avec méfiance.

**Pourquoi `%util` est trompeur** : il mesure le pourcentage de temps où **au moins
une** requête était en vol. Sur un disque à une seule tête, c'est effectivement la
saturation. Sur un SSD SATA (32 commandes en parallèle via NCQ) ou un NVMe (jusqu'à
64 000 files), une seule requête en vol sature le compteur alors que le périphérique
est loin de sa limite. On le remplace par le couple `await` + IOPS, et on regarde
`%util` uniquement sur du stockage rotatif.

> [!NOTE]
> **Pourquoi**
>
> Deux compléments qui font la différence entre lire `iostat` et savoir diagnostiquer.
>
> Le `-x` est indispensable (colonnes étendues) et le `-z` masque les périphériques
> inactifs, ce qui rend la sortie lisible sur une machine avec vingt volumes. Le
> premier échantillon affiché par `iostat` est une **moyenne depuis le démarrage** de
> la machine : on l'ignore toujours et on ne lit qu'à partir du second. D'où le
> `iostat -xz 2` qui rafraîchit toutes les deux secondes.
>
> Sur du LVM, les compteurs apparaissent **deux fois** : une fois sur le périphérique
> physique (`sda`), une fois sur le device-mapper (`dm-0`). Ce ne sont pas des E/S
> supplémentaires, c'est la même charge vue à deux étages. `lsblk` permet de relier
> `dm-0` à son LV. Et pour savoir **quel processus** génère les E/S, `iostat` ne suffit
> pas : c'est `iotop -o` ou `pidstat -d 2`.

---

<a id="qo11-10"></a>**[QO11.10](README.md#qo11-10)** — *`crypttab` et `fstab` pour un volume LUKS au démarrage.*

**Réponse attendue**

`/etc/crypttab` décrit le **déverrouillage** : il fait passer d'un conteneur chiffré
à un périphérique en clair.

```text
coffre  UUID=1a2b3c4d-...  none  luks,x-systemd.device-timeout=30
```

`/etc/fstab` décrit le **montage** du périphérique en clair produit ci-dessus :

```text
/dev/mapper/coffre  /srv/coffre  ext4  defaults,nodev,nosuid,noexec  0  2
```

**Ordre de traitement** : `systemd-cryptsetup-generator` lit `crypttab` au tout début
du démarrage et génère une unité `systemd-cryptsetup@coffre.service`, rattachée à
`cryptsetup.target`. `systemd-fstab-generator` lit `fstab` et génère
`srv-coffre.mount`, avec une dépendance `After=` et `Requires=` sur le périphérique
`/dev/mapper/coffre`, donc indirectement sur l'unité de déchiffrement. systemd
déverrouille, puis monte. On n'a rien à ordonner soi-même.

**Deux UUID différents, et c'est là que tout le monde se trompe** :

```bash
# UUID du CONTENEUR -> crypttab :
sudo cryptsetup luksUUID /dev/vg_data/lv_coffre
# UUID du SYSTÈME DE FICHIERS -> nulle part :
sudo blkid /dev/mapper/coffre
```

Mettre l'UUID du système de fichiers dans `crypttab` produit une erreur au
démarrage : le périphérique désigné n'existe pas encore (il n'existera qu'**après**
le déchiffrement), l'unité `.device` attend son timeout, puis échoue. Le montage
échoue à son tour, et sans `nofail` on repart en mode maintenance.

> [!NOTE]
> **Pourquoi**
>
> Le champ 4 de `crypttab` mérite d'être connu :
>
> * `luks` — force le format, évite une détection ambiguë ;
> * `discard` — propage le TRIM au périphérique sous-jacent. Gain de performance sur
>   SSD, mais il révèle à un observateur du disque brut **quels blocs sont utilisés**,
>   ce qui affaiblit marginalement la confidentialité. Décision consciente ;
> * `noauto` — ne pas déverrouiller au démarrage ;
> * `nofail` — ne pas bloquer le démarrage si le conteneur est absent ;
> * `keyfile-timeout=5s` — abandonne la lecture du fichier de clé (clé USB absente)
>   et bascule sur la demande interactive.
>
> Pour un serveur qui doit redémarrer sans humain, la vraie réponse n'est aucune de
> ces options mais `systemd-cryptenroll --tpm2-device=auto /dev/vg_data/lv_coffre` :
> la clé est scellée dans le TPM et libérée automatiquement si l'état de démarrage
> mesuré n'a pas changé. Le disque volé reste illisible, le serveur redémarre seul.

---

<a id="qo11-11"></a>**[QO11.11](README.md#qo11-11)** — *« Le RAID, c'est de la sauvegarde ? » ; vie et mort d'un disque de
RAID1 ; pourquoi LVM au-dessus du RAID.*

**Non.** Un RAID1 protège contre **une panne matérielle d'un disque** : le service
continue, on remplace, on reconstruit. Il ne protège contre rien d'autre :
un `rm -rf`, un rançongiciel, un bug applicatif, un `mkfs` sur le mauvais
périphérique ou une corruption de système de fichiers sont **fidèlement recopiés
sur les deux disques** en quelques millisecondes. Une sauvegarde, c'est une copie
**dans le temps** (on peut revenir en arrière) et **ailleurs** (un autre système,
idéalement un autre site). Le RAID sert la disponibilité, la sauvegarde sert la
récupération. On a besoin des deux.

Ce qui se passe quand un disque meurt :

1. le pilote SCSI/SATA renvoie des erreurs d'E/S ; le noyau les journalise
   (`blk_update_request: I/O error, dev sdb`) ;
2. la couche `md` marque le membre *faulty* et cesse de lui parler :
   `md/raid1:md0: Disk failure on sdb1, disabling device` puis
   `Operation continuing on 1 devices` ;
3. `/proc/mdstat` passe à `[2/1] [_U]` avec `sdb1[0](F)` ; `mdadm --detail`
   affiche `State : clean, degraded` ;
4. `mdmonitor.service` (qui fait `mdadm --monitor --scan`) voit l'événement `Fail`
   et envoie un courriel à `MAILADDR` — à condition que l'unité tourne et qu'un
   agent de courrier existe ;
5. les applications ne voient **rien** : les lectures sont servies par `sdc1`, les
   écritures n'attendent plus qu'un disque. C'est tout l'intérêt, et tout le danger.

Remplacement, dans l'ordre :

```bash
sudo mdadm /dev/md0 --fail /dev/sdb1        # si le noyau ne l'a pas déjà fait
sudo mdadm /dev/md0 --remove /dev/sdb1
# changement physique ; on recopie la table de sdc sur le disque neuf :
sudo sgdisk -R /dev/sdb /dev/sdc && sudo sgdisk -G /dev/sdb
sudo mdadm /dev/md0 --add /dev/sdb1
watch cat /proc/mdstat                      # recovery = 12.5% ... [UU]
```

LVM **au-dessus** du RAID : le PV est `/dev/md0`, un périphérique qui ne change pas
quand un disque meurt. LVM ne voit jamais la panne, les LV restent actifs, les
snapshots et extensions continuent. Dans l'autre sens (deux LV en miroir mdadm),
la perte d'un disque physique casse un PV, donc un VG entier passe en partiel, et
c'est LVM qui doit être réparé en premier — sans outil de reconstruction propre.
(LVM sait faire du RAID lui-même, `lvcreate --type raid1`, mais on mélange
rarement les deux.)

> [!NOTE]
> **Pourquoi**
>
> L'erreur d'exploitation la plus fréquente n'est pas technique : c'est de **ne pas
> savoir** qu'un tableau est dégradé. Rien ne ralentit, rien ne casse, les
> utilisateurs sont contents — pendant des mois. Le second disque meurt à son tour,
> et ce jour-là il n'y a plus de RAID. D'où trois réflexes : `MAILADDR` renseigné et
> testé (`mdadm --monitor --scan --oneshot --test`), une sonde de supervision qui lit
> `/proc/mdstat` (module 16), et un regard sur `mdadm --detail` à chaque intervention
> sur la machine.

---

<a id="qo11-12"></a>**[QO11.12](README.md#qo11-12)** — *NFS vs iSCSI ; pourquoi un montage `hard` sans serveur produit des
processus en `D`.*

| | NFS | iSCSI |
|---|---|---|
| Le client voit | des **fichiers** (`/mnt/p/x.txt`) | un **disque** (`/dev/sdd`) |
| Le FS est tenu par | le serveur (ext4/XFS sur `lab-ops`) | le client (il fait son `mkfs`) |
| Deux clients en écriture | normal, verrous NFS, un seul FS | **corruption** sauf FS en grappe (GFS2, OCFS2) |
| `fstab` | `_netdev,nofail,hard,x-systemd.automount` | `_netdev,nofail` (LV sur le disque) |

NFS est le bon choix quand plusieurs machines doivent voir les **mêmes fichiers**
(dépôt partagé, `/home`, artefacts de CI) ; iSCSI quand une machine a besoin d'un
**disque de plus** qu'elle gère entièrement (datastore de base de données, volume
LVM à étendre, VM), avec un seul initiateur connecté à la fois.

Les processus en `D` : un accès à un fichier NFS est un appel système (`stat`,
`read`) qui attend une réponse RPC du serveur. Le processus est mis en sommeil
**non interruptible** (`TASK_UNINTERRUPTIBLE`, état `D`) : le noyau est au milieu
d'une opération qu'il ne sait pas abandonner sans laisser le cache et le FS dans un
état incohérent. Un signal, y compris `SIGKILL`, n'est délivré qu'au **retour** de
l'appel système — qui n'arrive jamais tant que le serveur ne répond pas. Avec
`hard`, le client réessaie indéfiniment ; avec `soft`, il abandonne après
`timeo × retrans` et renvoie `EIO` à l'application. Chaque processus en `D` compte
dans la charge moyenne, d'où un *load* qui monte à CPU nul. Les sorties : le serveur
revient (tout reprend sans perte), ou `umount -f -l` sur le point de montage, qui
fait échouer les RPC en attente et libère les processus — c'est destructif pour les
écritures en cours, mais c'est la seule issue sans reboot. L'option `intr` qui
permettait autrefois d'interrompre n'existe plus (depuis le noyau 2.6.25, seul
`SIGKILL` est honoré, et uniquement entre deux RPC).

> [!NOTE]
> **Pourquoi**
>
> On garde `hard` parce que `soft` échange un blocage **visible** contre une
> corruption **silencieuse** : une application qui reçoit `EIO` au milieu d'une
> écriture ne sait généralement pas quoi en faire, et la moitié du fichier est
> partie. Le blocage, lui, se voit, se diagnostique et se résout sans rien perdre si
> le serveur revient. La bonne réponse en production est `hard` + supervision du
> serveur NFS + `x-systemd.automount` pour ne pas bloquer le démarrage.

---

## 11.5 Exercices guidés

Les commandes utilisent `/dev/sdb` et `/dev/sdc`. Si le setup a basculé en mode
simulé, remplace par `$DISQUE1` / `$DISQUE2` après `. /etc/lab11.env`.

<a id="e11-1"></a>**[E11.1](README.md#e11-1)** — *Vue unique de tous les périphériques bloc.*

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS
```

> [!NOTE]
> **Pourquoi**
>
> `lsblk` lit `/sys/block` et interroge `libblkid` : il n'ouvre pas les périphériques
> en écriture et ne fait aucune hypothèse. C'est la commande de premier réflexe sur une
> machine inconnue, avant `df`, avant `mount`, avant tout le reste, parce qu'elle
> montre **l'empilement** : disque, partition, RAID, LVM, chiffrement, avec
> l'indentation qui matérialise les couches.
>
> `lsblk -f` est le raccourci qu'on tape vraiment au quotidien : il affiche
> NAME, FSTYPE, LABEL, UUID, FSAVAIL, FSUSE% et MOUNTPOINTS. Les autres à connaître :
> `lsblk -p` (chemins complets, utile pour copier-coller), `lsblk -t` (topologie :
> taille de secteur physique et logique, alignement, file d'attente), `lsblk -J`
> (sortie JSON, pour un script).

> [!WARNING]
> **Piège**
>
> `lsblk` ne montre **pas** les périphériques sans nœud dans `/sys/block`, notamment
> les *loop devices* détachés et les volumes LVM inactifs. Un LV désactivé
> (`lvchange -an`) disparaît de `lsblk` alors que `lvs` le voit. Sur un système où « le
> volume a disparu », vérifie toujours les deux.

---

<a id="e11-2"></a>**[E11.2](README.md#e11-2)** — *Numéro de série de `/dev/sdb` via `/dev/disk/`.*

```bash
ls -l /dev/disk/by-id/ | grep 'sdb$'
```

```console
lrwxrwxrwx 1 root root 9 sept. 18 14:02 scsi-0QEMU_QEMU_HARDDISK_drive-scsi1
  -> ../../sdb

Sur une VM Proxmox, le « numéro de série » est celui que QEMU présente : drive-scsi1 par défaut (on peut
en fixer un dans les options du disque). Sur un disque physique, on lit ici le modèle et le vrai numéro de série,
et souvent un lien wwn-0x... en plus.
```

> [!NOTE]
> **Pourquoi**
>
> `udev` crée quatre familles de liens dans `/dev/disk/`, et il faut savoir à quoi
> chacune sert :
>
> | Répertoire | Contenu | Stable si… |
> |---|---|---|
> | `by-id/` | modèle + numéro de série, ou WWN | toujours (propriété du disque) |
> | `by-uuid/` | UUID du système de fichiers | toujours (sauf `mkfs`) |
> | `by-partuuid/` | UUID de partition GPT | toujours (sauf repartitionnement) |
> | `by-path/` | chemin matériel PCI/SCSI | tant qu'on ne rebranche rien |
>
> `by-id` est **le** bon identifiant pour désigner un disque physique : dans une
> configuration ZFS, dans un `mdadm.conf`, dans une procédure de remplacement (« retire
> le disque dont le numéro de série finit par 7F3K »). `by-uuid` désigne un contenu,
> `by-id` désigne un objet matériel.

---

<a id="e11-3"></a>**[E11.3](README.md#e11-3)** — *UUID ↔ device, dans les deux sens.*

```bash
# UUID -> périphérique
sudo blkid -U 8f3c1a2b-4d5e-6f70-8192-a3b4c5d6e7f8
findmnt -no SOURCE /

# périphérique -> UUID (la source de /, un LV sur Ubuntu)
sudo blkid -s UUID -o value "$(findmnt -no SOURCE /)"
lsblk -no UUID "$(findmnt -no SOURCE /)"
```

> [!NOTE]
> **Pourquoi**
>
> `blkid` maintient un cache dans `/run/blkid/blkid.tab`. Avec `-U` (ou `-L` pour une
> étiquette), il résout et renvoie le chemin du périphérique — c'est exactement ce que
> fait `mount` en interne quand il rencontre `UUID=` dans `fstab`.
>
> `-s UUID -o value` est la forme scriptable : une seule valeur, sans décoration, sans
> guillemets, directement utilisable dans une substitution de commande :
>
> ```bash
> echo "UUID=$(sudo blkid -s UUID -o value /dev/sdb1)  /srv/archives  ext4 \
>   defaults,nofail  0  0" | sudo tee -a /etc/fstab
> ```
>
> Si `blkid` ne renvoie rien alors que le volume existe, c'est que le cache est
> périmé : `sudo blkid -p /dev/sdb1` force la relecture directe de la superblock en
> contournant le cache.

---

<a id="e11-4"></a>**[E11.4](README.md#e11-4)** — *Table GPT et partition unique alignée sur `/dev/sdb`.*

```bash
sudo parted -s /dev/sdb mklabel gpt
sudo parted -s -a optimal /dev/sdb mkpart donnees 1MiB 100%
sudo parted -s /dev/sdb set 1 lvm on
sudo partprobe /dev/sdb
lsblk /dev/sdb
```

Équivalent `sgdisk`, plus court et plus scriptable :

```bash
sudo sgdisk -Z /dev/sdb                          # efface les tables existantes
sudo sgdisk -n 1:0:0 -t 1:8e00 -c 1:donnees /dev/sdb
sudo partprobe /dev/sdb
```

> [!NOTE]
> **Pourquoi**
>
> `-n 1:0:0` se lit « partition 1, début = premier secteur disponible, fin = dernier
> secteur disponible ». Le `0` de départ n'est pas le secteur 0 : `sgdisk` applique sa
> règle d'alignement (2048 secteurs, soit 1 MiB) et démarre là.
>
> L'alignement sur 1 MiB n'est pas une coquetterie. Un SSD efface par blocs de 128 Ko à
> 4 Mo ; une bande RAID fait typiquement 64 ou 256 Ko. Si une partition commence au
> secteur 63 (la convention MBR héritée du CHS des années 80), chaque écriture de 4 Ko
> chevauche deux blocs physiques : le contrôleur doit lire-modifier-écrire deux blocs
> au lieu d'un. Le débit en écriture aléatoire est divisé par deux, et l'usure du SSD
> doublée. 1 MiB est un multiple de toutes les valeurs rencontrées en pratique, d'où ce
> choix universel.
>
> Vérifier l'alignement après coup :
> `sudo parted /dev/sdb align-check optimal 1` doit répondre `1 aligned`.

---

<a id="e11-5"></a>**[E11.5](README.md#e11-5)** — *Formatage ext4 avec réserve root à 1 %.*

```bash
sudo mkfs.ext4 -L donnees -m 1 /dev/sdb1
```

Sur 5 Gio, passer de 5 % à 1 % récupère 4 % de 5 368 709 120 octets, soit
**214 748 364 octets ≈ 205 Mio**.

> [!NOTE]
> **Pourquoi**
>
> Les blocs réservés existent pour deux raisons, souvent mal comprises.
>
> La première est opérationnelle : quand un volume arrive à 100 %, même `root` ne peut
> plus écrire. Or les démons système (syslog, le SGBD, sshd) ont besoin d'écrire ne
> serait-ce que pour journaliser l'incident, et l'administrateur a besoin de pouvoir se
> connecter et faire du ménage. La réserve garantit cette marge.
>
> La seconde est technique : un ext4 rempli à plus de ~95 % se **fragmente** fortement,
> l'allocateur ne trouvant plus de plages contiguës. Les performances s'effondrent et
> la fragmentation reste même après avoir fait de la place.
>
> 5 % est un chiffre calibré pour une partition racine de quelques gigaoctets. Sur un
> volume de données de 4 To, 5 % représentent 200 Go inutilisables pour rien : on
> descend à 1 %, voire 0 sur un volume purement applicatif qui n'héberge ni logs
> système ni bases. Modifiable à tout moment, à chaud :
> `sudo tune2fs -m 1 /dev/sdb1`.

> [!WARNING]
> **Piège**
>
> `-m 0` sur le volume qui porte `/var/log` est une fausse bonne idée : le jour où le
> volume se remplit, `journald` ne peut plus écrire, `sshd` ne peut plus journaliser, et
> sur certaines configurations tu ne peux littéralement plus te connecter pour réparer.
> La réserve, c'est la ceinture de sécurité : on la retire sur les volumes de données
> pures, jamais sur ceux qui portent le système.

---

<a id="e11-6"></a>**[E11.6](README.md#e11-6)** — *Dernier `fsck`, compteur de montages, inodes libres.*

```bash
sudo tune2fs -l /dev/sdb1 \
  | grep -E 'Last checked|Mount count|Maximum mount|Free inodes'
```

```console
Mount count:              7
Maximum mount count:      -1
Last checked:             Thu Sep 18 14:02:11 2026
Free inodes:              327669
```

> [!NOTE]
> **Pourquoi**
>
> `tune2fs -l` affiche l'intégralité de la superblock : taille de bloc, nombre
> d'inodes, fonctionnalités activées (`Filesystem features`), UUID, étiquette,
> comportement en cas d'erreur. C'est la fiche d'identité complète d'un ext4, et
> `dumpe2fs -h` donne la même chose.
>
> Les deux déclencheurs de vérification automatique :
>
> * `Maximum mount count` (`-c`) : à `-1`, désactivé — c'est le défaut d'Ubuntu ;
> * `Check interval` (`-i`) : à 0, désactivé.
>
> Ubuntu les désactive tous les deux parce qu'un `fsck` surprise de vingt minutes sur
> un serveur qui redémarre en pleine nuit est jugé plus nuisible qu'utile. Le
> mécanisme qui reste actif, et qui est le vrai filet de sécurité, est le **drapeau
> « sale »** : si le système de fichiers n'a pas été démonté proprement, il est marqué
> non-propre et `fsck` s'exécute au montage suivant, quelles que soient les valeurs de
> `-c` et `-i`.
>
> Pour forcer une vérification au prochain démarrage sans toucher à la superblock :
> `sudo touch /forcefsck`, ou `fsck.mode=force` ajouté à la ligne de commande noyau.

---

<a id="e11-7"></a>**[E11.7](README.md#e11-7)** — *Montage durci, et preuve que `noexec` fonctionne.*

```bash
sudo mkdir -p /srv/factura/archives
sudo mount -o noatime,nodev,nosuid,noexec /dev/sdb1 /srv/factura/archives
findmnt /srv/factura/archives
```

```console
CIBLE                  SOURCE    FS-TYPE OPTIONS
/srv/factura/archives  /dev/sdb1 ext4    rw,noatime,nosuid,nodev,noexec
```

Preuve :

```bash
sudo cp /bin/true /srv/factura/archives/
sudo chmod +x /srv/factura/archives/true
/srv/factura/archives/true
```

```console
bash: /srv/factura/archives/true: Permission denied
```

> [!NOTE]
> **Pourquoi**
>
> Les quatre options, et ce qu'elles bloquent réellement :
>
> * **`noexec`** : `execve()` échoue avec `EACCES` sur tout fichier du volume. C'est
>   une vérification du noyau au moment de l'exécution, indépendante des permissions
>   Unix — d'où le `Permission denied` alors que le bit `x` est bien là.
> * **`nosuid`** : les bits setuid/setgid sont ignorés. Un binaire `root`-setuid déposé
>   là s'exécute avec les droits de l'appelant. C'est **la** protection critique sur un
>   volume où un utilisateur non fiable peut écrire.
> * **`nodev`** : les fichiers spéciaux de périphérique sont ignorés. Sans elle, un
>   attaquant crée un `mknod disque b 8 0` pointant sur `/dev/sda` et lit le disque
>   entier en contournant toutes les permissions du système de fichiers.
> * **`noatime`** : supprime l'écriture de la date d'accès à chaque lecture. Ubuntu
>   monte en `relatime` par défaut (mise à jour seulement si l'atime est plus vieux que
>   le mtime ou vieux de 24 h), ce qui suffit presque toujours. `noatime` va plus loin
>   et gagne quelques pour cent sur un volume à lecture intensive.
>
> Le trio `nodev,nosuid,noexec` est la configuration standard pour `/tmp`, `/var/tmp`,
> `/dev/shm` et tout volume alimenté de l'extérieur. C'est un point de contrôle CIS.

> [!WARNING]
> **Piège**
>
> `noexec` se contourne trivialement pour un interpréteur : `bash /srv/.../script.sh`
> et `python3 /srv/.../script.py` fonctionnent, parce que c'est `bash` ou `python3`
> qu'on exécute, pas le fichier. `noexec` empêche l'exécution de **binaires**, pas de
> scripts passés en argument. Ce n'est pas une barrière de sécurité complète, c'est une
> couche de plus.

---

<a id="e11-8"></a>**[E11.8](README.md#e11-8)** — *Ligne `fstab` par UUID, vérifiée sans redémarrer.*

```bash
UUID=$(sudo blkid -s UUID -o value /dev/sdb1)
echo "UUID=$UUID  /srv/factura/archives  ext4 \
  noatime,nodev,nosuid,noexec,nofail  0  0" | sudo tee -a /etc/fstab

findmnt --verify --verbose
sudo mount -a --fake -v
sudo systemctl daemon-reload
```

> [!NOTE]
> **Pourquoi**
>
> Trois vérifications complémentaires, et il faut savoir ce que chacune couvre :
>
> * `findmnt --verify` analyse la syntaxe de `fstab`, contrôle que chaque source
>   existe, que chaque point de montage est un répertoire, et signale les options
>   douteuses. C'est le `nginx -t` de `fstab`.
> * `mount -a --fake -v` rejoue tout le fichier **sans monter** : il détecte les
>   options refusées par le type de système de fichiers, ce que `findmnt --verify` ne
>   voit pas. Sans `--fake`, `mount -a` monte réellement tout ce qui manque, en
>   ignorant ce qui est déjà monté — c'est le test final.
> * `systemctl daemon-reload` force `systemd-fstab-generator` à régénérer les unités
>   `.mount`. Sans lui, systemd travaille encore sur l'ancien `fstab` et un
>   `systemctl status srv-factura-archives.mount` montre des informations périmées.
>
> L'ordre des options n'a pas d'importance, mais leur **cohérence** avec la réalité, si.
> Le sixième champ à `0` : ce volume de données n'a aucune raison de bloquer un boot
> pour un `fsck`.

---

<a id="e11-9"></a>**[E11.9](README.md#e11-9)** — *tmpfs de 256 Mio pour le groupe `factura`.*

```bash
sudo mkdir -p /srv/factura/tmp
echo "tmpfs  /srv/factura/tmp  tmpfs \
  size=256M,mode=1770,gid=factura,noexec,nosuid,nodev  0  0" \
  | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /srv/factura/tmp
findmnt /srv/factura/tmp
```

Les fichiers écrits là ne sont **nulle part sur le disque** : ils vivent dans le cache
de pages du noyau, donc en RAM, et peuvent être évacués vers le swap sous pression
mémoire.

> [!NOTE]
> **Pourquoi**
>
> tmpfs n'alloue rien à la création : `size=256M` est un **plafond**, pas une
> réservation. Un tmpfs vide consomme quelques kilo-octets. C'est ce qui permet à
> Ubuntu de monter `/dev/shm` à la moitié de la RAM sans conséquence.
>
> Le `mode=1770` combine trois choses : `1` = *sticky bit*, chacun ne peut supprimer
> que ses propres fichiers (comme `/tmp`) ; `770` = le propriétaire et le groupe en
> écriture, rien pour les autres. Avec `gid=factura`, le répertoire appartient au groupe
> au montage, sans avoir à faire un `chown` après coup — ce qui serait perdu au
> remontage suivant.
>
> Redimensionner à chaud, sans démonter et sans perdre le contenu :
> `sudo mount -o remount,size=512M /srv/factura/tmp`.
>
> Attention au point qui mord : un tmpfs plein **compte comme de la mémoire occupée**.
> Un processus qui écrit 20 Go dans un tmpfs sur une machine de 16 Go de RAM déclenche
> le swap, puis l'OOM killer. `size=` est une protection, pas une option esthétique.

---

<a id="e11-10"></a>**[E11.10](README.md#e11-10)** — *Reproduire un `target is busy` et trouver le coupable.*

```bash
# on crée le blocage
sudo sh -c 'sleep 600 > /srv/factura/archives/verrou.log &'
sudo umount /srv/factura/archives
```

```console
umount: /srv/factura/archives: target is busy.
```

```bash
sudo fuser -vm /srv/factura/archives
sudo lsof /srv/factura/archives
```

```console
                     UTIL.       PID ACCÈS  COMMANDE
/srv/factura/archives: root     4711 F....  sleep

COMMAND  PID USER   FD   TYPE DEVICE SIZE/OFF   NODE NAME
sleep  4711 root  1w  REG  8,17  0  12 /srv/factura/archives/verrou.log
```

> [!NOTE]
> **Pourquoi**
>
> La différence entre les deux outils : `fuser` répond « qui », `lsof` répond « quoi ».
> En exploitation, on lance `fuser -vm` d'abord (rapide, une ligne par processus), puis
> `lsof` sur le point de montage quand on a besoin de savoir **quel fichier** est tenu,
> pour décider si on peut tuer ou s'il faut attendre.
>
> La colonne `ACCÈS` de `fuser` est riche : `c` répertoire courant, `e` exécutable en
> cours, `f` fichier ouvert, `F` fichier ouvert en écriture, `r` racine, `m` fichier
> projeté en mémoire. Un `c` tout seul est le cas le plus sournois : un collègue avec un
> shell dont le `cwd` est dans le volume bloque le démontage sans avoir aucun fichier
> ouvert, et il ne s'en doute pas.
>
> Troisième outil, utile quand le volume est un LV :
> `sudo lsof /dev/mapper/vg_data-lv_pgdata` attrape aussi les processus qui ouvrent le
> **périphérique bloc** directement — une sauvegarde par `dd`, un `e2image`, un SGBD en
> mode raw device — que `lsof` sur le point de montage ne voit pas.

---

<a id="e11-11"></a>**[E11.11](README.md#e11-11)** — *Pile LVM complète.*

```bash
sudo pvcreate /dev/sdb1
sudo vgcreate vg_data /dev/sdb1
sudo lvcreate -L 2G -n lv_pgdata vg_data
sudo mkfs.ext4 -L pgdata /dev/vg_data/lv_pgdata
sudo mkdir -p /srv/factura/db
sudo mount /dev/vg_data/lv_pgdata /srv/factura/db

sudo pvs ; sudo vgs ; sudo lvs
```

```console
  PV         VG      Fmt  Attr PSize  PFree
  /dev/sdb1  vg_data lvm2 a--  <5,00g <3,00g

  VG      #PV #LV #SN Attr   VSize  VFree
  vg_data   1   1   0 wz--n- <5,00g <3,00g

  LV        VG      Attr       LSize Pool Origin Data%
  lv_pgdata vg_data -wi-ao---- 2,00g
```

> [!NOTE]
> **Pourquoi**
>
> Trois noms de périphérique désignent le même LV, et il faut savoir pourquoi :
>
> * `/dev/vg_data/lv_pgdata` — lien symbolique créé par LVM, le plus lisible ;
> * `/dev/mapper/vg_data-lv_pgdata` — nom du device-mapper (les `-` du nom d'origine
>   sont doublés en `--`, ce qui surprend toujours la première fois) ;
> * `/dev/dm-0` — le vrai nœud, dont le numéro change d'un démarrage à l'autre.
>
> Dans `fstab`, on écrit la première forme. Dans un script, les deux premières sont
> sûres ; `dm-N` jamais.
>
> L'attribut `-wi-ao----` se lit : volume linéaire (`-`), inscriptible (`w`),
> allocation héritée (`i`), **actif**, **ouvert** (monté). Un LV `-wi-a-----` est actif
> mais non monté ; un `-wi-------` n'est même pas activé, ce qui explique pourquoi il
> n'apparaît pas dans `lsblk`.

---

<a id="e11-12"></a>**[E11.12](README.md#e11-12)** — *Extension à chaud de 1 Go, système de fichiers compris.*

```bash
df -h /srv/factura/db
sudo lvextend -L +1G -r /dev/vg_data/lv_pgdata
df -h /srv/factura/db
```

```console
  Size of logical volume vg_data/lv_pgdata changed from 2,00 GiB to 3,00 GiB.
  Logical volume vg_data/lv_pgdata successfully resized.
resize2fs 1.47.0 (5-Feb-2023)
Filesystem at /dev/mapper/vg_data-lv_pgdata is mounted on /srv/factura/db;
on-line resizing required
The filesystem on /dev/mapper/vg_data-lv_pgdata is now 786432 (4k) blocks long.
```

> [!NOTE]
> **Pourquoi**
>
> `-r` appelle `fsadm resize`, qui identifie le système de fichiers et lance
> `resize2fs` (ext2/3/4) ou `xfs_growfs` (XFS). L'agrandissement se fait **volume
> monté, applications en cours d'écriture**, sans aucune interruption : ext4 ajoute des
> groupes de blocs à la fin du volume, ce qui ne touche à aucune structure existante.
> La seule contrainte est que le système de fichiers doit être monté pour XFS, et peut
> être monté ou non pour ext4.
>
> Les formes acceptées par `-L` : `-L 3G` (taille absolue), `-L +1G` (ajout). Le `+` est
> la nuance qui compte le plus : `-L 1G` sur un LV de 2 Go est une **réduction**, et
> `lvextend` refusera — mais `lvresize -L 1G` l'accepterait avec confirmation.
> Utilise toujours `lvextend` quand tu veux agrandir : la commande refuse par
> construction de réduire, ce qui est un garde-fou gratuit.

---

<a id="e11-13"></a>**[E11.13](README.md#e11-13)** — *Ajouter `/dev/sdc1` au VG, puis un LV sur tout le libre.*

```bash
sudo sgdisk -n 1:0:0 -t 1:8e00 /dev/sdc && sudo partprobe /dev/sdc
sudo pvcreate /dev/sdc1
sudo vgextend vg_data /dev/sdc1
sudo lvcreate -l 100%FREE -n lv_sauv vg_data
sudo vgs
```

> [!NOTE]
> **Pourquoi**
>
> La distinction `-l 100%FREE` / `-l +100%FREE` est la source d'erreur numéro un
> sur LVM :
>
> * **à la création** (`lvcreate`), `-l 100%FREE` signifie « prends tout l'espace libre
>   du VG ». C'est ce qu'on veut ici ;
> * **à l'extension** (`lvextend`), `-l 100%FREE` signifie « fais que ce LV **pèse**
>   100 % de l'espace libre ». Comme le LV existant est déjà plus gros que l'espace
>   libre restant, la commande échoue avec
>   `New size given (12 extents) not larger than existing size (512 extents)`.
>   La bonne écriture à l'extension est `-l +100%FREE`.
>
> Les autres suffixes de `-l` valent le détour : `100%VG` (pourcentage de la taille
> totale du groupe), `100%PVS` (des PV cités en argument), `100%ORIGIN` (pour un
> snapshot, en pourcentage de l'origine — c'est celui qu'on utilise pour dimensionner
> un snapshot proprement : `-l 15%ORIGIN`).

---

<a id="e11-14"></a>**[E11.14](README.md#e11-14)** — *Localiser les extents, puis les déplacer à chaud.*

```bash
sudo lvs -o +devices
# lv_sauv (E11.13) occupe tout sdc1 : pvmove n'aurait aucun extent libre
# où déplacer lv_pgdata. On le réduit (il n'est pas formaté) :
sudo lvreduce -y -L 1G vg_data/lv_sauv
sudo pvmove /dev/sdb1
sudo lvs -o +devices
```

```console
  LV        VG      Attr       LSize Devices
  lv_pgdata vg_data -wi-ao---- 3,00g /dev/sdb1(0)
  lv_sauv   vg_data -wi-a----- 1,00g /dev/sdb1(768)

  /dev/sdb1: Moved: 12,50%
  /dev/sdb1: Moved: 41,67%
  /dev/sdb1: Moved: 100,00%
```

> [!NOTE]
> **Pourquoi**
>
> `pvmove` déplace les extents d'un PV vers les autres PV du groupe, **pendant que les
> volumes sont montés et utilisés**. Le mécanisme : LVM crée temporairement une cible
> device-mapper de type *mirror* pour chaque segment déplacé. Les écritures vont aux
> deux copies, les lectures à l'ancienne, puis le basculement est atomique et l'ancien
> segment est libéré. Aucun risque de perte : si la machine s'arrête en plein
> `pvmove`, l'opération reprend au démarrage suivant (`pvmove` sans argument la
> relance, `pvmove --abort` l'annule).
>
> C'est **le** geste qui justifie LVM à lui seul en exploitation : remplacer un disque
> qui commence à remonter des erreurs SMART, migrer d'un stockage local vers un SAN,
> vider un PV avant de rendre un LUN — le tout sans fenêtre de maintenance. Prérequis évident mais souvent oublié : il faut **de la place libre sur les PV de destination**, sinon `pvmove` répond `No extents available for allocation`.
>
> Ce que ça coûte : c'est lent (le débit du plus lent des deux PV) et ça consomme des
> E/S. Sur une production sensible, on lance avec `ionice -c3` et on surveille
> `await`. Pour cibler une destination précise : `sudo pvmove /dev/sdb1 /dev/sdc1`.
> Pour ne déplacer qu'un LV : `sudo pvmove -n lv_pgdata /dev/sdb1`.

---

<a id="e11-15"></a>**[E11.15](README.md#e11-15)** — *Snapshot de 512 Mio monté en lecture seule.*

```bash
sudo lvcreate -s -L 512M -n snap_pg /dev/vg_data/lv_pgdata
sudo mkdir -p /mnt/snap
sudo mount -o ro /dev/vg_data/snap_pg /mnt/snap

sudo touch /srv/factura/db/apres-snapshot.txt
ls /srv/factura/db/apres-snapshot.txt      # existe
ls /mnt/snap/apres-snapshot.txt            # No such file or directory
```

> [!NOTE]
> **Pourquoi**
>
> Le snapshot présente la vue du volume **à l'instant exact de sa création**. Le fichier
> créé après n'y figure pas : ce n'est pas une copie décalée dans le temps, c'est une
> photographie.
>
> Pour un snapshot **XFS**, il faut ajouter `-o nouuid` :
>
> ```bash
> sudo mount -o ro,nouuid /dev/vg_data/snap_pg /mnt/snap
> ```
>
> XFS refuse de monter deux systèmes de fichiers portant le même UUID, et le snapshot
> est par définition une copie bit à bit de l'origine, UUID compris. `nouuid` demande
> au pilote de ne pas vérifier. Sur ext4, le noyau tolère le doublon et le monte sans
> rien dire.
>
> Monter en `ro` n'est pas obligatoire — un snapshot LVM est inscriptible par défaut, à
> la différence des snapshots de beaucoup d'autres systèmes — mais c'est la bonne
> pratique pour une sauvegarde : ça garantit qu'aucun outil ne modifiera la source
> pendant l'archivage, et ça évite de consommer de l'espace d'exception pour rien.

---

<a id="e11-16"></a>**[E11.16](README.md#e11-16)** — *Remplissage de tous les snapshots en une commande.*

```bash
sudo lvs -o lv_name,origin,data_percent -S 'origin!=""'
```

```console
  LV      Origin    Data%
  snap_pg lv_pgdata 3,44
```

> [!NOTE]
> **Pourquoi**
>
> `-S` (`--select`) est un langage de filtrage complet intégré à toutes les commandes
> de rapport LVM, et très peu connu. `origin!=""` ne garde que les LV qui ont une
> origine, c'est-à-dire les snapshots. Autres filtres utiles au quotidien :
>
> ```bash
> sudo lvs -S 'data_percent>70'                 # snapshots/thin en danger
> sudo lvs -S 'lv_attr=~^s.*I'                  # snapshots invalidés
> sudo vgs -S 'vg_free_count<100'               # groupes qui se remplissent
> sudo pvs -S 'pv_used>0' -o pv_name,vg_name,pv_used
> ```
>
> `data_percent` est **la** métrique à surveiller. Attention à ne pas la confondre avec
> un `df` sur le snapshot monté : `df` montre le remplissage du système de fichiers
> photographié (identique à celui de l'origine au moment T), `data_percent` montre le
> remplissage de la zone de copie sur écriture. Ce sont deux chiffres sans rapport, et
> c'est le second qui décide de la survie du snapshot.

---

<a id="e11-17"></a>**[E11.17](README.md#e11-17)** — *Fichier de swap de 1 Gio, permanent, `swappiness` à 10.*

```bash
sudo fallocate -l 1G /swapfile        # ou dd if=/dev/zero of=/swapfile \
                                      #      bs=1M count=1024
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile  none  swap  sw  0  0' | sudo tee -a /etc/fstab

echo 'vm.swappiness = 10' | sudo tee /etc/sysctl.d/99-swappiness.conf
sudo sysctl --system
cat /proc/sys/vm/swappiness
swapon --show
```

```console
NAME      TYPE SIZE USED PRIO
/swapfile file   1G   0B   -2
```

> [!NOTE]
> **Pourquoi**
>
> `chmod 600` n'est pas une précaution de style : `swapon` **refuse** un fichier dont
> les permissions sont plus larges, et il a raison. Le fichier de swap contient des
> pages mémoire de tous les processus de la machine — clés de session, mots de passe en
> clair, contenu de bases. Le rendre lisible par tous équivaut à publier la mémoire du
> serveur.
>
> `/etc/sysctl.d/99-swappiness.conf` plutôt qu'une modification de `/etc/sysctl.conf` :
> c'est le mécanisme de fragments, qui survit aux mises à jour du paquet `procps` et
> rend la configuration lisible et versionnable. Le préfixe numérique donne l'ordre de
> lecture, `99-` passe en dernier et gagne sur les réglages du système.
>
> `sysctl --system` relit tous les répertoires (`/etc/sysctl.d/`, `/run/sysctl.d/`,
> `/usr/lib/sysctl.d/`) dans l'ordre et applique. `sysctl -p` seul ne lit que
> `/etc/sysctl.conf` et raterait le fragment.
>
> La priorité `-2` affichée par `swapon --show` est attribuée automatiquement. Avec
> plusieurs zones de swap, celle de priorité la plus haute est utilisée en premier ; à
> priorité égale, le noyau répartit en round-robin, ce qui permet d'agréger le débit de
> plusieurs disques (`pri=10` dans les options de `fstab`).

---

<a id="e11-18"></a>**[E11.18](README.md#e11-18)** — *Débit séquentiel avec `dd`, IOPS aléatoires avec `fio`.*

```bash
sudo dd if=/dev/zero of=/srv/factura/db/test.dd bs=1M count=1024 \
  oflag=direct conv=fdatasync
```

```console
1073741824 octets (1,1 GB, 1,0 GiB) copiés, 3,71431 s, 289 MB/s
```

```bash
sudo fio --name=rr --filename=/srv/factura/db/test.fio --size=1G --bs=4k \
  --rw=randread --ioengine=libaio --direct=1 --iodepth=32 \
  --runtime=30 --time_based --group_reporting
sudo rm -f /srv/factura/db/test.dd /srv/factura/db/test.fio
```

> [!NOTE]
> **Pourquoi**
>
> Les deux mesures n'ont presque rien en commun.
>
> `dd` avec `bs=1M` mesure le **débit séquentiel** : de gros blocs contigus, une
> requête à la fois, aucun parallélisme. C'est le chiffre marketing des fiches
> techniques, et c'est la charge d'une copie de fichier ou d'une restauration de
> sauvegarde. `oflag=direct` contourne le cache de page (sinon on mesure la vitesse de
> la RAM, avec des résultats délirants à 3 Go/s) et `conv=fdatasync` force un
> `fdatasync()` final pour ne pas s'arrêter avant que les données soient réellement sur
> le support.
>
> `fio` en `randread --bs=4k --iodepth=32` mesure les **IOPS aléatoires** : des petits
> blocs, dispersés, 32 requêtes en vol simultanément. C'est la charge d'une base de
> données, et c'est le seul chiffre qui compte pour un SGBD. Un disque rotatif fait
> 150 IOPS et 200 Mo/s séquentiels ; un NVMe fait 500 000 IOPS et 3 Go/s. Le rapport
> entre les deux est de 1 à 15 en séquentiel et de 1 à 3 000 en aléatoire — d'où
> l'inutilité totale du `dd` pour qualifier un stockage de base de données.

> [!WARNING]
> **Piège**
>
> `fio` écrit réellement sur le volume et le remplit à hauteur de `--size`. Ne le lance
> jamais sur un volume de production sans vérifier l'espace libre, et **jamais avec
> `--filename=/dev/sdX`** en mode `write` : ça écrase le disque. Sur un volume monté,
> utilise toujours un chemin de fichier. Et pense à supprimer le fichier de test après,
> sinon tu découvriras dans trois mois un `test.fio` de 50 Go sur ton datastore.

---

<a id="e11-19"></a>**[E11.19](README.md#e11-19)** — *Relever `r/s`, `r_await` et `%util` pendant le `fio`.*

```bash
iostat -xz 2 /dev/mapper/vg_data-lv_pgdata
```

```console
Device            r/s     rkB/s   r_await  aqu-sz  %util
dm-0           7412,00  29648,00     4,31   31,95   99,90
```

Lecture : **7 412 IOPS** en lecture, latence moyenne **4,31 ms**, profondeur de file
de 32 (exactement l'`iodepth` demandé à `fio`).

> [!NOTE]
> **Pourquoi**
>
> La cohérence des trois chiffres est ce qu'on vérifie. La loi de Little donne
> `aqu-sz ≈ IOPS × await` : 7412 × 0,00431 s ≈ 31,9. Les compteurs sont cohérents, la
> mesure est fiable. Quand la relation ne tient pas, c'est qu'on lit le premier
> échantillon d'`iostat` (moyenne depuis le démarrage) — celui qu'on ignore toujours.
>
> `rkB/s / r/s` = 29648 / 7412 = 4 Ko : la taille de bloc demandée à `fio`. Autre
> confirmation que la charge mesurée est bien celle qu'on a lancée.
>
> `%util` à 99,9 % avec une file de 32 : le périphérique n'a jamais eu zéro requête en
> vol, ce qui est normal puisque `fio` en maintient 32 en permanence. Ça ne dit
> absolument rien sur la saturation. La question à se poser est : « la latence
> augmente-t-elle quand j'augmente `iodepth` ? » Si `await` reste stable de 1 à 32, il
> reste de la marge ; si elle croît linéairement, on est à la limite.
>
> Sur LVM, relever les chiffres sur `dm-0` **et** sur le disque physique sous-jacent :
> un écart important entre les deux trahit une fragmentation du LV sur plusieurs PV ou
> un problème d'alignement.

---

<a id="e11-20"></a>**[E11.20](README.md#e11-20)** — *LUKS2 sur `/dev/sdc1`.*

```bash
sudo cryptsetup luksFormat --type luks2 /dev/sdc1
```

```console
WARNING!
========
This will overwrite data on /dev/sdc1 irrevocably.

Are you sure? (Type 'yes' in capital letters): YES
Enter passphrase for /dev/sdc1:
Verify passphrase:
```

```bash
sudo cryptsetup luksOpen /dev/sdc1 coffre       # ou : cryptsetup open
sudo mkfs.ext4 -L coffre /dev/mapper/coffre
sudo mkdir -p /srv/coffre
sudo mount /dev/mapper/coffre /srv/coffre

sudo cryptsetup luksDump /dev/sdc1
sudo cryptsetup luksUUID /dev/sdc1
```

> [!NOTE]
> **Pourquoi**
>
> La confirmation `YES` en majuscules est volontaire : `luksFormat` écrit un nouvel
> en-tête avec une nouvelle clé maîtresse, ce qui rend **définitivement illisible**
> tout ce qui était sur le volume, même avec l'ancienne phrase de passe. Il n'y a pas
> d'annulation.
>
> L'architecture LUKS, indispensable à comprendre :
>
> * une **clé maîtresse** aléatoire chiffre réellement les données. Elle ne sort jamais
>   en clair du noyau ;
> * jusqu'à 32 **emplacements de clé** (LUKS2) contiennent chacun une copie de cette clé
>   maîtresse, chiffrée par une phrase de passe dérivée. LUKS2 utilise Argon2id comme
>   fonction de dérivation, résistante au calcul GPU, là où LUKS1 utilisait PBKDF2.
>
> Deux conséquences pratiques. D'abord, on peut avoir plusieurs phrases de passe (une
> par administrateur, une de secours dans le coffre-fort) et en révoquer une sans
> rechiffrer un seul octet : `cryptsetup luksKillSlot`. Ensuite, **l'en-tête est le
> point de défaillance unique absolu** : 16 Mio au début du volume, et s'il est perdu,
> les données sont irrécupérables quelle que soit la phrase de passe.
> `sudo cryptsetup luksHeaderBackup /dev/sdc1 --header-backup-file /root/coffre.hdr`
> est la première chose à faire après un `luksFormat`, et ce fichier doit être protégé
> comme la phrase de passe elle-même.

> [!WARNING]
> **Piège**
>
> `luksDump` affiche les emplacements occupés et les paramètres, jamais les clés. Mais
> `luksUUID` et `blkid` sur `/dev/sdc1` donnent l'UUID **du conteneur** ; `blkid` sur
> `/dev/mapper/coffre` donne celui **du système de fichiers**. Le premier va dans
> `crypttab`, le second nulle part (on utilise `/dev/mapper/coffre` dans `fstab`).
> Inverser les deux est l'erreur classique, et elle ne se manifeste qu'au redémarrage
> suivant, en mode maintenance.

---

<a id="e11-21"></a>**[E11.21](README.md#e11-21)** — *RAID1 `/dev/md0` persistant, nommé `md0` et pas `md127`.*

```bash
. /etc/lab11.env
sudo sgdisk -Z "$DISQUE1" && sudo sgdisk -n 1:0:0 -t 1:fd00 "$DISQUE1"
sudo sgdisk -Z "$DISQUE2" && sudo sgdisk -n 1:0:0 -t 1:fd00 "$DISQUE2"
sudo partprobe "$DISQUE1" "$DISQUE2"
sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 \
  "${DISQUE1}1" "${DISQUE2}1"        # loop : ${DISQUE1}p1
watch -n1 cat /proc/mdstat
```

```console
md0 : active raid1 sdc1[1] sdb1[0]
      5237760 blocks super 1.2 [2/2] [UU]
      [=====>...............]  resync = 27.4% (1436544/5237760) finish=0.5min
      speed=126976K/sec
```

Persistance :

```bash
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
sudo update-initramfs -u
grep ARRAY /etc/mdadm/mdadm.conf
# ARRAY /dev/md0 metadata=1.2 name=lab-db:0 UUID=6d2f...:...
sudo mdadm --detail /dev/md0 | grep -E 'Name|UUID|State'
```

> [!NOTE]
> **Pourquoi**
>
> Le nom `md0` est décidé à l'assemblage, pas à la création. Ce qui est écrit dans le
> superblock, c'est `name=lab-db:0` : *hôte:numéro*. Au démarrage, `mdadm` dans
> l'initramfs compare cet hôte à celui de la machine et aux lignes `ARRAY` de
> `mdadm.conf`. Si le tableau est reconnu comme « local » (hôte identique ou ligne
> `ARRAY` présente), il reçoit le numéro demandé ; sinon il est considéré étranger et
> reçoit un numéro à partir de 127. C'est pourquoi un disque déplacé d'une machine à
> une autre arrive toujours en `md127` : ce n'est pas un bug, c'est une protection
> contre les collisions de noms.
>
> `update-initramfs -u` recopie `/etc/mdadm/mdadm.conf` **dans** l'initramfs. Sans
> lui, le fichier sur disque est correct mais inutile : au moment où il faudrait le
> lire, la racine n'est pas encore montée. La création avec `mdadm --create` sur des
> partitions pleines de zéros affiche aussi `mdadm: Note: this array has metadata at
> the start and may not be suitable as a boot device` : normal pour un volume de
> données, et c'est le rappel que les superblocks 1.2 occupent les premiers 4 Ko.

> [!WARNING]
> **Piège**
>
> Relancer `mdadm --detail --scan » mdadm.conf` plusieurs fois empile des lignes
> `ARRAY` identiques ; mdadm s'en accommode mais c'est illisible. Avant chaque ajout :
> `grep -c ARRAY /etc/mdadm/mdadm.conf`. Et la synchronisation initiale n'est pas
> optionnelle : le tableau est utilisable immédiatement, mais il n'est **redondant**
> qu'à la fin du `resync`.

---

<a id="e11-22"></a>**[E11.22](README.md#e11-22)** — *RAID5 sur trois membres, capacité utile, UUID par `--examine`.*

```bash
sudo bash ~/workbook/scripts/setup/setup_M11.sh --raid5
. /etc/lab11.env ; echo "$DISQUE3"
sudo sgdisk -n 1:0:0 -t 1:fd00 "$DISQUE3" && sudo partprobe "$DISQUE3"
# les deux premiers membres viennent de E11.21 (après --stop et
# --zero-superblock de /dev/md0), ou de deux partitions libres.
sudo mdadm --create /dev/md1 --level=5 --raid-devices=3 \
  "${DISQUE1}1" "${DISQUE2}1" "${DISQUE3}p1"     # DISQUE3 est toujours un loop
sudo mdadm --detail /dev/md1 | grep -E 'Array Size|Used Dev Size|Layout|Chunk'
```

```console
     Array Size : 10475520 (9.99 GiB 10.73 GB)
  Used Dev Size : 5237760 (4.99 GiB 5.36 GB)
         Layout : left-symmetric
     Chunk Size : 512K
```

Trois disques de 5 Go, 10 Go utiles : la capacité d'**un** disque est consommée
par la parité, répartie sur les trois membres (`left-symmetric`). Un RAID5 à *n*
disques offre *(n-1)* × taille du plus petit membre et tolère **une** panne.

```bash
sudo mdadm --examine "${DISQUE1}1" | grep -E 'Array UUID|Device Role|Events'
sudo mdadm --detail /dev/md1 | grep UUID          # même valeur
```

> [!NOTE]
> **Pourquoi**
>
> `--examine` lit le **superblock d'un membre** ; `--detail` interroge le **tableau
> assemblé**. Les deux montrent le même `Array UUID`, mais `--examine` fonctionne
> sans que le tableau soit actif — c'est l'outil du diagnostic à froid : « ce disque
> récupéré, il appartenait à quoi ? ». On y lit aussi `Device Role : Active device 0`
> (sa place), et `Events`, un compteur incrémenté à chaque changement d'état. Deux
> membres dont les `Events` diffèrent beaucoup ne sont pas synchrones ; c'est ce que
> `--assemble` vérifie avant d'accepter un disque.
>
> Sur le RAID5, la reconstruction lit **tous** les disques survivants pour recalculer
> chaque bande : sur des disques de plusieurs Tio, elle dure des heures ou des jours,
> pendant lesquels une seconde panne est fatale, et la charge de lecture accrue rend
> justement cette panne plus probable. C'est l'argument qui a fait migrer les gros
> volumes vers le RAID6 (deux parités) ou le RAID10.

---

<a id="e11-23"></a>**[E11.23](README.md#e11-23)** — *XFS avec quota de projet, puis extension par `xfs_growfs`.*

```bash
sudo lvcreate -L 1G -n lv_journaux vg_data
sudo mkfs.xfs -L journaux /dev/vg_data/lv_journaux
sudo mkdir -p /srv/factura/journaux
sudo mount -o prjquota /dev/vg_data/lv_journaux /srv/factura/journaux
sudo mkdir /srv/factura/journaux/app1
echo '10:/srv/factura/journaux/app1' | sudo tee -a /etc/projects
echo 'app1:10' | sudo tee -a /etc/projid
sudo xfs_quota -x -c 'project -s app1' /srv/factura/journaux
sudo xfs_quota -x -c 'limit -p bhard=200m app1' /srv/factura/journaux
sudo dd if=/dev/zero of=/srv/factura/journaux/app1/gros bs=1M count=300
# dd: erreur d'écriture : Aucun espace disponible sur le périphérique
sudo xfs_quota -x -c 'report -p -h' /srv/factura/journaux
```

```console
Project quota on /srv/factura/journaux (/dev/mapper/vg_data-lv_journaux)
                        Blocks
Project ID   Used   Soft   Hard Warn/Grace
---------- ---------------------------------
app1         200M      0   200M  00 [------]
```

Extension :

```bash
df -h /srv/factura/journaux                       # 1,0G
sudo lvextend -L +512M /dev/vg_data/lv_journaux
sudo xfs_growfs /srv/factura/journaux             # sur le POINT DE MONTAGE
df -h /srv/factura/journaux                       # 1,5G
# ou en une fois : sudo lvextend -L +512M -r /dev/vg_data/lv_journaux
```

> [!NOTE]
> **Pourquoi**
>
> Le quota de projet est la fonctionnalité qui distingue XFS : on borne un
> **répertoire**, pas un utilisateur. Le drapeau `project -s` marque récursivement les
> inodes du répertoire avec l'ID de projet et rend l'attribut héritable : tout
> nouveau fichier créé dessous compte pour `app1`, quel que soit son propriétaire.
> `/etc/projects` associe un ID à un chemin, `/etc/projid` un nom à l'ID ; les deux
> fichiers ne servent qu'à `xfs_quota`, le noyau ne connaît que l'ID stocké dans
> l'inode. C'est le mécanisme qu'utilisent Docker (`--storage-opt size=`) et
> Kubernetes (`ephemeral-storage`) pour limiter un conteneur sur XFS.
>
> `xfs_growfs` prend un point de montage parce qu'il travaille **à chaud, via le
> noyau** : il ajoute des groupes d'allocation à la fin du volume et met à jour le
> superblock, sans jamais toucher le périphérique directement. Il n'existe pas de
> `xfs_growfs` hors ligne, ni de `xfs_shrinkfs` du tout.

> [!WARNING]
> **Piège**
>
> `prjquota` doit être dans les options **de montage** (donc dans `fstab`) ; on ne
> l'active pas après coup. Et `bhard` seul suffit ici : un `bsoft` sans délai de grâce
> n'est qu'un avertissement dans le rapport. Sur ext4, les quotas de projet existent
> depuis e2fsprogs 1.43 (`tune2fs -O project`, `-o prjquota`), mais l'outillage reste
> celui de `quota` et non `xfs_quota`.

---

<a id="e11-24"></a>**[E11.24](README.md#e11-24)** — *Export NFS sur `lab-ops`, vérification depuis `lab-db`.*

Sur `lab-ops` :

```bash
sudo mkdir -p /srv/nfs/partage
echo '/srv/nfs/partage 10.10.10.0/24(rw,sync,no_subtree_check,root_squash)' \
  | sudo tee -a /etc/exports
sudo exportfs -ra
sudo exportfs -v
# /srv/nfs/partage  10.10.10.0/24(sync,wdelay,hide,no_subtree_check,sec=sys,
#   rw,secure,root_squash,no_all_squash)
```

Depuis `lab-db` :

```bash
showmount -e 10.10.10.14
# Export list for 10.10.10.14:
# /srv/nfs/partage 10.10.10.0/24
sudo mkdir -p /mnt/partage-ops
sudo mount -t nfs 10.10.10.14:/srv/nfs/partage /mnt/partage-ops
nfsstat -m
# /mnt/partage-ops from 10.10.10.14:/srv/nfs/partage
#  Flags: rw,relatime,vers=4.2,rsize=1048576,wsize=1048576,namlen=255,hard,
#  proto=tcp,timeo=600,retrans=2,sec=sys,clientaddr=10.10.10.12,local_lock=none
```

> [!NOTE]
> **Pourquoi**
>
> `exportfs -ra` relit `/etc/exports` (`-r`) et réexporte tout (`-a`) sans
> redémarrer `nfs-server.service` : les clients déjà montés ne sont pas
> interrompus. `exportfs -v` montre les options **effectives**, c'est-à-dire ce que
> tu as écrit plus les défauts : `root_squash`, `sync`, `secure` (port source < 1024
> obligatoire), `wdelay`, `sec=sys`. Les écrire explicitement dans `exports`, comme
> `root_squash` ici, documente l'intention pour le collègue qui lira le fichier.
>
> `showmount -e` interroge `mountd` en RPC (port 111 puis un port dynamique) : il
> montre ce que le serveur exporte **sans négocier de montage**, et il fonctionne
> même quand le montage v4 échouerait. Un client `mount -t nfs` sans `nfsvers`
> tente v4.2, puis v4.1, v4.0, v3 : `nfsstat -m` (ou `findmnt -o OPTIONS`) dit ce qui
> a été retenu. `no_subtree_check` est la valeur recommandée : `subtree_check`
> vérifiait, à chaque requête, que le fichier était bien sous le répertoire exporté
> quand l'export n'est pas une racine de FS, au prix de handles instables lors des
> renommages.

---

<a id="e11-25"></a>**[E11.25](README.md#e11-25)** — *Ordonnanceur d'E/S : lecture, bascule à chaud, règle udev.*

```bash
cat /sys/block/sdb/queue/scheduler
# [none] mq-deadline
echo mq-deadline | sudo tee /sys/block/sdb/queue/scheduler
cat /sys/block/sdb/queue/scheduler
# none [mq-deadline]
cat /sys/block/sdb/queue/rotational        # 0 = SSD (ou disque virtuel)
```

`bfq` et `kyber` n'apparaissent que si leurs modules sont chargés :
`sudo modprobe bfq` les ajoute à la liste.

```bash
sudo tee /etc/udev/rules.d/60-ordonnanceur.rules <<'EOF'
# SSD, NVMe et disques virtuels : pas d'ordonnancement, l'hôte s'en charge
ACTION=="add|change", KERNEL=="sd[a-z]*|vd[a-z]*|nvme[0-9]n[0-9]", \
  ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
# disques rotatifs : latence bornée
ACTION=="add|change", KERNEL=="sd[a-z]*", \
  ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="mq-deadline"
EOF
sudo udevadm control --reload
sudo udevadm test /sys/block/sdb 2>&1 | grep -E 'scheduler|60-ordonnanceur'
sudo udevadm trigger --action=change /sys/block/sdb   # applique tout de suite
cat /sys/block/sdb/queue/scheduler
```

> [!NOTE]
> **Pourquoi**
>
> Depuis le noyau 5.0, seuls les ordonnanceurs *multi-queue* existent. `none` ne
> réordonne rien : chaque requête part dans une des files matérielles du
> périphérique. C'est le bon choix pour un NVMe (des dizaines de files, des
> milliers de requêtes en vol) et pour un **disque de VM** : l'hyperviseur a son
> propre ordonnanceur sur le disque physique, empiler le nôtre dessus n'apporte que
> de la latence. `mq-deadline` garantit qu'une requête n'attend pas plus de 500 ms
> en lecture (5 s en écriture) et favorise les lectures : le choix sûr pour un
> disque rotatif de serveur. `bfq` répartit le temps de disque équitablement entre
> processus, précieux sur un poste de travail, coûteux en CPU sur un serveur à
> forte charge.
>
> Le réglage par `/sys` ne survit pas au redémarrage. La règle udev, elle, est
> rejouée à chaque apparition du disque, et le test `ATTR{queue/rotational}`
> sélectionne par nature du support au lieu d'un nom `sdb` qui peut changer.
> `udevadm test` simule l'événement et affiche les règles qui s'appliqueraient,
> sans rien modifier — c'est la façon de valider une règle avant de compter dessus.

---

<a id="e11-26"></a>**[E11.26](README.md#e11-26)** — *Un `fio` en lecture aléatoire lu correctement.*

```bash
sudo fio --name=lect-alea --filename=/srv/factura/db/t.fio --size=1G \
  --bs=4k --rw=randread --ioengine=libaio --direct=1 --iodepth=32 \
  --runtime=30 --time_based --group_reporting
sudo rm /srv/factura/db/t.fio
```

Extrait commenté d'une sortie plausible (disque virtio sur SSD) :

```console
lect-alea: (groupid=0, jobs=1): err= 0: pid=4211
  read: IOPS=7986, BW=31.2MiB/s (32.7MB/s)(936MiB/30001msec)
    slat (usec): min=2, max=210, avg=4.12, stdev=1.90
    clat (usec): min=180, max=41230, avg=4001.53, stdev=2210.40
     lat (usec): min=185, max=41240, avg=4005.80, stdev=2210.50
    clat percentiles (usec):
     |  1.00th=[  914],  5.00th=[ 1516], 50.00th=[ 3720], 90.00th=[ 6521],
     | 99.00th=[12387], 99.90th=[24511], 99.99th=[38536]
```

Les trois nombres : **IOPS = 7 986**, **clat moyen = 4,0 ms**, **99e percentile =
12,4 ms**. Loi de Little : 7 986 × 0,004 = 31,9 ≈ 32 requêtes en vol, cohérent.

> [!NOTE]
> **Pourquoi**
>
> `slat` est le temps de soumission (CPU, négligeable avec `libaio`), `clat` le temps
> d'achèvement — la latence qui compte —, `lat` la somme. Avec `--direct=1`, le cache
> de pages est contourné : on mesure le périphérique et non la RAM. Sans lui, un
> fichier de 1 Go tient en cache et on lit 500 000 IOPS de mémoire. `--time_based`
> fait tourner 30 s même si le fichier est parcouru plusieurs fois ; `--group_reporting`
> agrège si `--numjobs` > 1.
>
> Un 99e percentile à 3× la moyenne est normal sur un support partagé. À **10×** la
> moyenne, une requête sur cent attend très longtemps : c'est la signature d'un
> voisin bruyant (autre VM sur le même datastore), d'une collecte de déchets du SSD,
> ou d'un ordonnanceur qui privilégie un autre flux. Pour une base de données, c'est
> ce percentile qui fait les requêtes lentes, pas la moyenne.
>
> Dans une seconde session, `iostat -xz 2` sur le même disque doit montrer `r/s`
> proche des IOPS, `r_await` proche de `clat` et `aqu-sz` proche de `iodepth`. Si
> `r_await` est bien plus bas que `clat`, le temps se perd **au-dessus** du bloc
> (LVM, chiffrement, FS), pas dans le disque.

> [!WARNING]
> **Piège**
>
> Sur un setup en *loop device*, ces chiffres mesurent le disque système à travers
> un fichier : ils ne veulent rien dire. Et un `fio` avec `--rw=randwrite` sur un
> volume de production est une charge réelle : il fait ce qu'il dit.

---

## 11.6 Labs

### <a id="l11-1"></a>**[L11.1](README.md#l11-1)** — *Deux disques neufs à mettre en service proprement*

**Étapes 1 à 3 — état des lieux, partition, formatage**

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS

sudo sgdisk -Z /dev/sdb
sudo sgdisk -n 1:0:0 -t 1:8300 -c 1:archives /dev/sdb
sudo partprobe /dev/sdb
sudo mkfs.ext4 -L archives -m 1 /dev/sdb1
```

Ce qui distingue `sdb` et `sdc` du disque système : ils n'ont aucune partition
(`TYPE=disk` sans enfant), aucun `FSTYPE`, aucun point de montage. `sda` porte
au minimum une partition EFI, une `/boot` et le PV du système.

**Étapes 4 et 5 — montage durci et preuve du `noexec`**

```bash
sudo mkdir -p /srv/factura/archives
sudo mount -o noatime,nodev,nosuid,noexec /dev/sdb1 /srv/factura/archives
findmnt /srv/factura/archives

sudo cp /bin/true /srv/factura/archives/
sudo chmod +x /srv/factura/archives/true
/srv/factura/archives/true
# bash: /srv/factura/archives/true: Permission denied
```

**Étapes 6 et 7 — `fstab` et vérification sans redémarrer**

```bash
UUID_A=$(sudo blkid -s UUID -o value /dev/sdb1)
echo "UUID=$UUID_A  /srv/factura/archives  ext4 \
  noatime,nodev,nosuid,noexec,nofail  0  0" | sudo tee -a /etc/fstab

findmnt --verify --verbose
sudo umount /srv/factura/archives
sudo mount -a
sudo systemctl daemon-reload
findmnt /srv/factura/archives
```

**Étape 8 — le second disque en XFS**

```bash
sudo sgdisk -Z /dev/sdc
sudo sgdisk -n 1:0:0 -t 1:8300 -c 1:journaux /dev/sdc
sudo partprobe /dev/sdc
sudo mkfs.xfs -L journaux /dev/sdc1
sudo mkdir -p /srv/factura/journaux
UUID_J=$(sudo blkid -s UUID -o value /dev/sdc1)
echo "UUID=$UUID_J  /srv/factura/journaux  xfs  defaults,noatime,nofail  0  0" \
  | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount -a
sudo xfs_info /srv/factura/journaux
```

Trois différences structurelles attendues entre les deux sorties :

1. **ext4 pré-alloue ses inodes** (`Inode count: 327680` dans `tune2fs -l`), XFS n'a
   pas de nombre fixe : `xfs_info` affiche `imaxpct=25`, un plafond en pourcentage
   d'espace, les inodes étant alloués dynamiquement à la demande.
2. **ext4 organise le volume en groupes de blocs** de taille fixe
   (`Blocks per group: 32768`), XFS en **groupes d'allocation** (`agcount=4,
   agsize=327680 blks`) qui sont des unités d'allocation **indépendantes et
   parallélisables**.
3. **Le journal** : ext4 le décrit comme une fonctionnalité (`has_journal` dans
   `Filesystem features`), XFS l'expose comme une section dimensionnée à part
   (`log =internal log bsize=4096 blocks=16384`), et il peut être placé sur un
   périphérique séparé.

> [!NOTE]
> **Pourquoi**
>
> Le point pédagogique du lab est le couple `nofail` + `pass 0`. Ces deux valeurs
> transforment un incident bloquant en incident bénin.
>
> Sans `nofail` : le montage échoue → l'unité `.mount` échoue → `local-fs.target`
> échoue → `emergency.target`. La machine ne démarre pas, et il faut une console.
> C'est BF11.1.
>
> Avec `nofail` : le montage échoue, systemd le note dans le journal, `local-fs.target`
> est atteint quand même, la machine démarre, SSH répond, tu répares à distance,
> tranquillement. Le seul coût est qu'il faut **superviser** l'absence du montage,
> puisqu'elle ne se manifeste plus au démarrage. D'où le contrôle de `findmnt --verify`
> dans le script de supervision du défi D11.
>
> Le sixième champ à `0` complète le dispositif : ce volume de données n'a aucune
> raison de provoquer un `fsck` de vingt minutes au démarrage. `1` est réservé à `/`,
> `2` aux systèmes de fichiers système qu'on veut vérifier, `0` à tout le reste.

> [!WARNING]
> **Piège**
>
> L'ordre des lignes dans `fstab` compte quand les points de montage sont imbriqués :
> `/srv/factura` doit être monté avant `/srv/factura/archives`. `mount -a` traite le
> fichier séquentiellement, et systemd, lui, calcule les dépendances tout seul à partir
> des chemins — ce qui crée une différence de comportement entre `mount -a` et un
> redémarrage. En cas de doute sur une pile de montages imbriqués, la vérité est
> `systemctl list-units --type=mount`, pas `mount -a`.

---

### <a id="l11-2"></a>**[L11.2](README.md#l11-2)** — *Mettre la base sous LVM et l'étendre à chaud*

**Étapes 1 et 2 — PV et VG**

```bash
# on commente les lignes de fstab posées en L11.1 :
sudo sed -i 's|^UUID=.*/srv/factura|# &|' /etc/fstab
sudo umount /srv/factura/archives /srv/factura/journaux
sudo wipefs -a /dev/sdb1 /dev/sdc1
sudo sgdisk -t 1:8e00 /dev/sdb && sudo sgdisk -t 1:8e00 /dev/sdc
sudo partprobe /dev/sdb /dev/sdc

sudo pvcreate /dev/sdb1 /dev/sdc1
sudo pvs -o pv_name,dev_size,pv_size,pv_free
sudo vgcreate vg_data /dev/sdb1
sudo vgdisplay vg_data | grep 'PE Size'
```

```console
  PV         DevSize  PSize   PFree
  /dev/sdb1    5,00g  <5,00g  <5,00g
  PE Size               4,00 MiB
```

Les quelques Mio manquants entre `DevSize` et `PSize` sont l'**en-tête de métadonnées
LVM** : une étiquette au secteur 1 et une zone de métadonnées de 1 Mio par défaut, qui
contient la description complète du VG (tous les PV, tous les LV, tous les segments).
Chaque PV en porte une copie : perdre un disque ne perd pas la description du groupe.
Le reste de l'écart vient de l'arrondi à un nombre entier d'extents de 4 Mio.

**Étapes 3 et 4 — LV, système de fichiers, générateur**

```bash
sudo lvcreate -L 2G -n lv_pgdata vg_data
sudo mkfs.ext4 -L pgdata /dev/vg_data/lv_pgdata
sudo mkdir -p /srv/factura/db
echo "/dev/vg_data/lv_pgdata  /srv/factura/db  ext4 \
  defaults,noatime  0  2" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /srv/factura/db

sudo /opt/factura/bin/factura-ecritures.sh /srv/factura/db &
```

Pourquoi pas d'UUID ici : `/dev/vg_data/lv_pgdata` est déjà un nom stable, fabriqué
par LVM à partir de ses métadonnées. Il ne dépend d'aucun ordre d'énumération du
noyau. Il a de plus l'avantage d'être lisible : dans six mois, `UUID=8f3c1a2b` ne dit
rien à personne, `lv_pgdata` dit tout.

**Étapes 5 et 6 — extension à chaud**

```bash
df -h /srv/factura/db
sudo lvextend -L 2.5G -r /dev/vg_data/lv_pgdata
df -h /srv/factura/db

sudo vgextend vg_data /dev/sdc1
# le PV cité en fin de commande restreint l'allocation à ce PV :
sudo lvextend -L +512M -r /dev/vg_data/lv_pgdata /dev/sdc1
sudo lvs -o +devices vg_data/lv_pgdata   # sdb1(0) puis sdc1(0) : 3 Go
sudo vgs
```

Le générateur continue d'écrire sans une seule erreur : c'est le résultat à observer.

**Étape 7 — retrait de `sdb` à chaud**

```bash
sudo pvmove /dev/sdb1
sudo vgreduce vg_data /dev/sdb1
sudo pvremove /dev/sdb1
sudo lvs -o +devices
df -h /srv/factura/db          # toujours monté, toujours accessible
```

**Étape 8 — réduction, dans le bon ordre**

```bash
sudo lvcreate -L 1.5G -n lv_test vg_data
sudo mkfs.ext4 /dev/vg_data/lv_test
sudo mkdir -p /mnt/test && sudo mount /dev/vg_data/lv_test /mnt/test
sudo dd if=/dev/urandom of=/mnt/test/donnees.bin bs=1M count=200

sudo umount /mnt/test                             # 1. démonter : obligatoire
sudo e2fsck -f /dev/vg_data/lv_test           # 2. vérifier : resize2fs l'exige
sudo resize2fs /dev/vg_data/lv_test 1G            # 3. RÉDUIRE LE FS d'abord
sudo lvreduce -L 1G /dev/vg_data/lv_test          # 4. réduire le LV ensuite
sudo mount /dev/vg_data/lv_test /mnt/test
ls -l /mnt/test/donnees.bin                       # intact
```

> [!NOTE]
> **Pourquoi**
>
> L'ordre des étapes 3 et 4 est la seule chose à retenir de ce lab, et elle se déduit
> d'un raisonnement simple : **le système de fichiers doit toujours être plus petit ou
> égal au volume qui le porte**.
>
> Si tu fais `lvreduce` d'abord, le LV passe à 1 Go pendant que le système de fichiers
> croit encore faire 1,5 Go. Ses structures de fin — la sauvegarde de superblock, une
> partie de la table d'inodes, et les données qui s'y trouvaient — sont désormais hors
> du périphérique. Toute lecture de ces blocs renvoie une erreur d'E/S, toute écriture
> part dans le vide. `e2fsck` peut parfois rattraper la structure ; les données, non.
>
> `e2fsck -f` avant `resize2fs` n'est pas une précaution facultative : `resize2fs`
> **refuse** de réduire un système de fichiers qui n'a pas été vérifié depuis sa
> dernière modification. Il a besoin d'une carte d'occupation fiable pour déplacer les
> blocs situés au-delà de la nouvelle limite vers le début du volume.
>
> La méthode courte existe et fait les quatre étapes : `sudo lvreduce -r -L 1G
> /dev/vg_data/lv_test`. `fsadm` démonte, vérifie, réduit le FS, puis `lvreduce` réduit
> le LV. Elle est fiable sur ext4. Elle refuse sur XFS, comme prévu.

> [!WARNING]
> **Piège**
>
> Le piège d'arrondi : `resize2fs ... 1G` produit un système de fichiers de
> 1 073 741 824 octets exactement, et `lvreduce -L 1G` produit un LV de 1 GiB — mais
> LVM arrondit à l'extent inférieur si la taille ne tombe pas juste. Le LV peut alors
> faire quelques Mio de **moins** que le système de fichiers, et on retombe dans le
> scénario de corruption. Parade professionnelle : réduire le système de fichiers
> **légèrement plus** que la cible (ici `resize2fs ... 900M`), réduire le LV à 1G, puis
> faire `resize2fs` sans taille pour que le système de fichiers reprenne exactement la
> place disponible. Trois commandes, zéro risque.

---

### <a id="l11-3"></a>**[L11.3](README.md#l11-3)** — *Une sauvegarde cohérente par snapshot LVM*

**Étape 1 — la sauvegarde naïve et son défaut**

```bash
sudo tar czf /tmp/naif.tar.gz -C /srv/factura/db .
```

```console
tar: ./journal.wal: file changed as we read it
tar: ./travail-3.tmp: File shrank by 4096 bytes; padding with zeros
```

`tar` sort en code 1. Le résultat est une archive dans laquelle `travail-3.tmp` a été
lu à 14 h 03 min 12 s et `journal.wal` à 14 h 03 min 19 s : deux instants différents,
donc un état qui n'a jamais existé. Pour une base de données, l'archive est
inutilisable.

**Étapes 2 à 4 — snapshot et sauvegarde cohérente**

```bash
sudo lvcreate -s -L 512M -n snap_pg /dev/vg_data/lv_pgdata
sudo mkdir -p /mnt/snap
sudo mount -o ro /dev/vg_data/snap_pg /mnt/snap

sudo touch /srv/factura/db/apres.txt
ls /mnt/snap/apres.txt            # absent : la photo est bien figée

sudo mkdir -p /srv/sauvegardes
sudo tar czf /srv/sauvegardes/factura-db-$(date +%F).tar.gz -C /mnt/snap .
echo "code retour : $?"           # 0, aucun avertissement
```

512 Mio suffisent parce que le snapshot ne stocke **pas** les données de l'origine : il
stocke les anciennes versions des blocs modifiés pendant sa durée de vie. Une
sauvegarde qui dure cinq minutes sur une base qui écrit 1 Mo/s produit 300 Mo de
changements au maximum. La taille de l'origine — 3 Go ou 3 To — n'entre pas dans
le calcul.

**Étape 5 — surveiller le remplissage**

```bash
watch -n 2 "sudo lvs -o lv_name,origin,data_percent -S 'origin!=\"\"'"
```

À 3 % après deux minutes de sauvegarde, avec un générateur qui écrit en continu, le
snapshot tiendrait environ une heure. C'est le calcul qu'on fait pour dimensionner en
production : mesurer `data_percent` sur une sauvegarde réelle, puis prendre trois fois
la marge.

**Étape 6 — nettoyage**

```bash
sudo umount /mnt/snap
sudo lvremove -y /dev/vg_data/snap_pg
```

Un snapshot oublié trois semaines fait deux dégâts : il finit par déborder et devenir
invalide (inutile mais inoffensif), et surtout il **impose la pénalité de copie sur
écriture à toutes les écritures de l'origine pendant trois semaines**. Chaque première
écriture sur un chunk coûte une lecture plus deux écritures. Sur une base active, la
latence d'écriture double. C'est la vraie raison de supprimer un snapshot dès qu'il a
servi — pas l'espace disque.

**Étape 7 — restauration par fusion**

```bash
sudo rm /srv/factura/db/comptes.dat
# (en conditions réelles, le snapshot existe AVANT la suppression)
sudo lvcreate -s -L 512M -n snap_pg /dev/vg_data/lv_pgdata
sudo lvconvert --merge /dev/vg_data/snap_pg
```

```console
  Delaying merge since origin is open.
  Merging of snapshot vg_data/snap_pg will occur on next activation
  of vg_data/lv_pgdata.
```

La fusion ne peut pas avoir lieu tant que l'origine est montée : elle réécrit des
blocs sous les pieds du système de fichiers monté. LVM inscrit donc l'intention dans
les métadonnées (l'attribut du LV passe à `Owi-a-s---`, le `O` signalant une origine
en cours de fusion) et exécute au prochain cycle de désactivation-activation :

```bash
sudo umount /srv/factura/db
sudo lvchange -an /dev/vg_data/lv_pgdata
sudo lvchange -ay /dev/vg_data/lv_pgdata
sudo mount /srv/factura/db
ls -l /srv/factura/db/comptes.dat      # revenu
sudo lvs                            # snap_pg a disparu : consommé par la fusion
```

**Étape 8 — le script**

```bash
#!/usr/bin/env bash
# sauvegarde-snapshot.sh — sauvegarde cohérente de lv_pgdata par snapshot LVM
set -euo pipefail

VG=vg_data
LV=lv_pgdata
SNAP=snap_pg
TAILLE=512M
MNT=/mnt/snap
DEST=/srv/sauvegardes

[ "$(id -u)" -eq 0 ] || { echo "root requis (sudo)" >&2; exit 1; }
if lvs "$VG/$SNAP" >/dev/null 2>&1; then
  echo "ERREUR : le snapshot $VG/$SNAP existe déjà." >&2
  echo "Une sauvegarde est en cours, ou la précédente a mal fini." >&2
  exit 1
fi

nettoyer() {
  mountpoint -q "$MNT" && umount "$MNT" || true
  lvs "$VG/$SNAP" >/dev/null 2>&1 && lvremove -y "$VG/$SNAP" || true
}
trap nettoyer EXIT

mkdir -p "$MNT" "$DEST"
lvcreate -s -L "$TAILLE" -n "$SNAP" "/dev/$VG/$LV"
mount -o ro "/dev/$VG/$SNAP" "$MNT"
tar czf "$DEST/factura-db-$(date +%F_%H%M).tar.gz" -C "$MNT" .
echo "Sauvegarde terminée : $(ls -lh "$DEST" | tail -1)"
```

> [!NOTE]
> **Pourquoi**
>
> Le `trap nettoyer EXIT` est le cœur du script, pas un détail de style. Sans lui, une
> interruption (`Ctrl-C`, une erreur de `tar`, un `OOM killer`, un `set -e` déclenché)
> laisse un snapshot monté et actif. Le lendemain, la sauvegarde échoue parce que le
> snapshot existe déjà ; la semaine d'après, le VG est plein. C'est le scénario exact de
> BF11.4.
>
> `trap ... EXIT` se déclenche sur **toutes** les sorties : normale, `exit` explicite,
> erreur sous `set -e`, et signal intercepté. C'est pour cette raison qu'on l'installe
> sur `EXIT` plutôt que sur `INT TERM`, qui rateraient l'échec d'une commande.
>
> Le `|| true` après chaque commande de nettoyage est indispensable : la fonction
> s'exécute sous `set -e`, et un `umount` qui échoue parce que le volume n'était pas
> monté ferait sortir la fonction avant d'avoir supprimé le snapshot.
>
> Le contrôle d'existence en tête (avant le `trap`) est volontairement placé là : si un
> snapshot existe déjà, on **ne veut surtout pas** que le nettoyage le supprime — c'est
> peut-être une sauvegarde en cours lancée par quelqu'un d'autre. On sort, on alerte, et
> un humain décide.

---

### <a id="l11-4"></a>**[L11.4](README.md#l11-4)** — *Croissance d'un disque de VM, de bout en bout*

**Étape 1 — la photo avant**

```bash
lsblk ; df -h / ; sudo pvs ; sudo vgs ; sudo lvs
findmnt -no SOURCE /            # /dev/mapper/ubuntu--vg-ubuntu--lv
sudo pvs -o pv_name,vg_name     # /dev/sda3  ubuntu-vg
```

**Étapes 2 et 3 — hyperviseur puis relecture par le noyau**

```bash
# shell Proxmox
qm resize 9003 scsi0 +20G
```

```bash
# dans la VM
lsblk /dev/sda                  # si sda fait toujours 30G :
echo 1 | sudo tee /sys/class/block/sda/device/rescan
lsblk /dev/sda                  # 50G
```

Avec virtio-scsi, Proxmox notifie la VM et le noyau voit la nouvelle taille tout
seul. Avec certains contrôleurs, il faut forcer la relecture de la géométrie par le
`rescan` ci-dessus — c'est l'équivalent de `partprobe`, mais un étage plus bas, sur le
disque lui-même.

**Étapes 4 à 6 — les trois couches**

```bash
sudo growpart /dev/sda 3        # espace entre le nom du disque et le NUMÉRO
sudo pvresize /dev/sda3
sudo vgs                        # VFree est passé à ~20g
sudo lvextend -l +100%FREE -r /dev/ubuntu-vg/ubuntu-lv
df -h /
```

```console
CHANGED: partition=3 start=4198400 old: size=58714112 end=62912511
                                   new: size=100659167 end=104857566
  Physical volume "/dev/sda3" changed
  1 physical volume(s) resized
  Size of logical volume ubuntu-vg/ubuntu-lv changed from 28,00 to 48,00 GiB.
```

`fdisk` seul ne suffit pas parce qu'agrandir une partition en place signifie
supprimer l'entrée de la table et la recréer avec le **même secteur de départ** et une
fin plus lointaine. À la main, c'est possible mais une erreur d'un secteur sur le
départ rend la partition illisible. `growpart` fait exactement cette opération, en
calculant le départ à partir de la table existante, et en refusant si quoi que ce soit
l'empêche. C'est du travail de mécanique de précision confié à un outil dont c'est le
seul métier.

**Étape 7 — récapitulatif des couches**

| Couche | Commande | Si on la saute |
|---|---|---|
| Disque virtuel | `qm resize` | rien de plus n'est possible |
| Partition | `growpart /dev/sda 3` | `pvresize` ne trouve pas de place |
| PV LVM | `pvresize /dev/sda3` | `VFree` reste à 0, `lvextend` échoue |
| LV | `lvextend -l +100%FREE` | `df` ne bouge pas |
| Système de fichiers | `-r` / `resize2fs` | `df` ne bouge pas non plus |

**Étape 8 — le swap**

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile  none  swap  sw  0  0' | sudo tee -a /etc/fstab
echo 'vm.swappiness = 10' | sudo tee /etc/sysctl.d/99-swappiness.conf
sudo sysctl --system
swapon --show ; cat /proc/sys/vm/swappiness
```

`swappiness=10` plutôt que 60 sur une base de données : le SGBD gère lui-même son
cache (`shared_buffers` pour PostgreSQL) et sait mieux que le noyau quelles pages sont
utiles. Laisser le noyau évacuer des pages de ce cache vers le disque revient à mettre
du cache disque sur du disque — avec une latence multipliée par plusieurs milliers au
prochain accès. On garde une valeur non nulle pour que les pages anonymes réellement
froides puissent partir, mais on rend le noyau très réticent.

**Étape 9 — vérification après redémarrage**

```bash
findmnt --verify --verbose
sudo reboot
# puis :
df -h / ; swapon --show ; sysctl vm.swappiness
```

> [!NOTE]
> **Pourquoi**
>
> Ce lab est le geste le plus fréquent du métier, et sa valeur pédagogique tient en une
> phrase : **chaque couche a sa propre notion de taille et aucune ne prévient les
> autres**. La séquence des quatre commandes se déduit de l'empilement, elle ne
> s'apprend pas par cœur. Le jour où tu tombes sur un volume sans LVM, tu enlèves les
> deux commandes du milieu et tu gardes `growpart` + `resize2fs`. Le jour où il y a du
> LUKS en plus, tu intercales `cryptsetup resize coffre` entre le PV et le LV.
>
> Le fait que tout se fasse **à chaud, volume monté** mérite d'être souligné auprès des
> équipes applicatives : sur du stockage moderne avec LVM, « agrandir un disque » n'est
> plus une opération qui demande une fenêtre de maintenance. C'est un argument qui fait
> gagner des nuits blanches.

> [!WARNING]
> **Piège**
>
> Deux pièges de `growpart` à connaître :
>
> * `growpart /dev/sda3` (sans espace) est une **erreur** : la syntaxe attend le disque
>   et le numéro séparément, `growpart /dev/sda 3`. Avec la mauvaise forme, l'outil
>   refuse, heureusement ;
> * `NOCHANGE: partition 3 is size ... it cannot be grown` signifie qu'il y a une
>   partition **après** celle qu'on veut agrandir. Sur une installation manuelle avec
>   une partition de swap en fin de disque, il faut d'abord `swapoff`, supprimer la
>   partition de swap, agrandir, puis recréer le swap dans le nouvel espace — ou, plus
>   simplement, ajouter un **second disque** et l'intégrer au VG avec `vgextend`, ce qui
>   ne touche à aucune table de partitions existante. En VM, la seconde méthode est
>   presque toujours la bonne.

---

### <a id="l11-5"></a>**[L11.5](README.md#l11-5)** — *Coffre chiffré LUKS et partage NFS*

**Partie A — LUKS**

```bash
sudo lvcreate -L 512M -n lv_coffre vg_data
sudo cryptsetup luksFormat --type luks2 /dev/vg_data/lv_coffre   # YES + phrase
sudo cryptsetup luksOpen /dev/vg_data/lv_coffre coffre             # phrase
ls -l /dev/mapper/coffre
lsblk /dev/vg_data/lv_coffre

sudo mkfs.ext4 -L coffre /dev/mapper/coffre
sudo mkdir -p /srv/coffre
sudo mount /dev/mapper/coffre /srv/coffre
echo "donnees personnelles" | sudo tee /srv/coffre/temoin.txt
```

Preuve que les données ne sont plus lisibles une fois fermé :

```bash
sudo umount /srv/coffre
sudo cryptsetup luksClose coffre
sudo blkid /dev/vg_data/lv_coffre
# /dev/vg_data/lv_coffre: UUID="1a2b..." TYPE="crypto_LUKS"
sudo mount /dev/vg_data/lv_coffre /mnt
# mount: /mnt: type de système de fichiers « crypto_LUKS » inconnu.
```

Le volume n'expose plus qu'un en-tête LUKS. Le reste est du bruit indistinguable
d'aléa : `sudo hexdump -C -n 512 -s 20M /dev/vg_data/lv_coffre` le montre bien.

**Étape 5 — `crypttab` et `fstab`**

```bash
UUID_LUKS=$(sudo cryptsetup luksUUID /dev/vg_data/lv_coffre)
echo "coffre  UUID=$UUID_LUKS  none  luks,x-systemd.device-timeout=30" \
  | sudo tee -a /etc/crypttab
echo "/dev/mapper/coffre  /srv/coffre  ext4 \
  defaults,nodev,nosuid,noexec,nofail  0  0" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
```

Ordre de traitement par systemd : `systemd-cryptsetup-generator` lit `crypttab` et
produit `systemd-cryptsetup@coffre.service` ; `systemd-fstab-generator` lit `fstab` et
produit `srv-coffre.mount`, qui dépend de `dev-mapper-coffre.device`, lequel n'apparaît
qu'une fois le service de déchiffrement terminé. La chaîne de dépendances est calculée
automatiquement, on n'écrit aucun `After=`.

**Étape 6 — seconde phrase de passe**

```bash
# phrase existante, puis la nouvelle :
sudo cryptsetup luksAddKey /dev/vg_data/lv_coffre
sudo cryptsetup luksDump /dev/vg_data/lv_coffre | grep -A2 '^Keyslots'
```

En exploitation réelle : un emplacement par administrateur (révocation individuelle
avec `luksKillSlot` quand quelqu'un quitte l'équipe, sans rechiffrer le volume), plus
un emplacement pour une clé de secours conservée dans le coffre-fort de l'entreprise,
plus éventuellement un emplacement TPM pour le démarrage automatique.

**Étape 7 — redémarrage**

Au démarrage, la console affiche
`Please enter passphrase for disk coffre (coffre):`. Si personne ne répond, le
démarrage attend — indéfiniment sans options, ou 30 secondes avec le
`x-systemd.device-timeout=30` posé plus haut, après quoi l'unité échoue. C'est le
`nofail` du `fstab` qui évite alors le basculement en mode maintenance.

**Partie B — NFS côté client**

```bash
showmount -e 10.10.10.10
# Export list for 10.10.10.10:
# /srv/exports/archives 10.10.10.0/24

sudo mkdir -p /mnt/archives-adm
sudo mount -t nfs4 -o ro,hard,timeo=600,retrans=2 \
  10.10.10.10:/srv/exports/archives /mnt/archives-adm
findmnt /mnt/archives-adm
```

```bash
echo "10.10.10.10:/srv/exports/archives  /mnt/archives-adm  nfs4 \
  ro,_netdev,nofail,hard,timeo=600,retrans=2,x-systemd.automount  0  0" \
  | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
```

**Étape 11 — comportement en cas de panne du serveur**

Avec `hard` : `ls /mnt/archives-adm` **se bloque indéfiniment**. Le processus passe en
état `D` (`ps -o stat,cmd -p <pid>` affiche `D+`), insensible même à `SIGKILL`, et la
charge moyenne de la machine grimpe alors que le CPU est à 0 %. Le journal affiche
`nfs: server 10.10.10.10 not responding, still trying`. Dès que le serveur revient,
l'opération reprend exactement où elle en était, sans perte.

Avec `soft,timeo=50` : après 5 secondes (`timeo` est en dixièmes de seconde) et
`retrans` tentatives, l'appel système renvoie `EIO`. Le processus n'est pas bloqué, il
reçoit une erreur — et c'est précisément le problème.

> [!NOTE]
> **Pourquoi**
>
> `hard` contre `soft` est une des questions les plus mal comprises de NFS, et la
> réponse est contre-intuitive : **on garde `hard` en production**, malgré le blocage.
>
> Raison : avec `soft`, une écriture peut renvoyer une erreur alors que le serveur l'a
> en réalité reçue et traitée, ou l'inverse. L'application reçoit `EIO` au milieu d'une
> transaction et, dans l'immense majorité des cas, gère mal cette situation — on obtient
> une **corruption silencieuse de données**. Avec `hard`, l'application attend, ce qui
> est visible, diagnosticable, et ne corrompt rien.
>
> La bonne combinaison de production est `hard,timeo=600,retrans=2` accompagnée de
> `x-systemd.automount` : le blocage ne survient que si quelqu'un accède réellement au
> partage, jamais au démarrage. Et quand il faut se sortir d'un serveur mort,
> `sudo umount -f -l /mnt/archives-adm` libère les processus bloqués.
>
> `soft` ne se justifie que pour du contenu strictement en lecture seule dont la perte
> est sans conséquence — un partage de médias, un miroir de paquets.

---

### <a id="l11-6"></a>**[L11.6](README.md#l11-6)** — *Miroir mdadm sous LVM : perdre un disque et survivre*

**Étapes 1 à 3 — le miroir et sa persistance**

```bash
. /etc/lab11.env
for d in "$DISQUE1" "$DISQUE2"; do
  sudo sgdisk -Z "$d"
  sudo sgdisk -n 1:0:0 -t 1:fd00 -c 1:raid "$d"
done
sudo partprobe "$DISQUE1" "$DISQUE2"
sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 \
  "${DISQUE1}1" "${DISQUE2}1"
watch -n1 cat /proc/mdstat
cat /proc/sys/dev/raid/speed_limit_min      # 1000 (Ko/s)
cat /proc/sys/dev/raid/speed_limit_max      # 200000
```

`speed_limit_min` est le débit **garanti** à la resynchronisation quand le tableau
est par ailleurs sollicité : 1 Mo/s, pour que les applications gardent la
priorité. Quand le tableau est inactif, la resync monte jusqu'à
`speed_limit_max`. Sur un serveur qu'on veut voir reconstruit vite pendant une
nuit calme, on relève temporairement le minimum
(`sudo sysctl dev.raid.speed_limit_min=50000`).

```bash
grep -q '^ARRAY /dev/md0' /etc/mdadm/mdadm.conf || \
  sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
sudo update-initramfs -u
```

Sans la ligne `ARRAY`, le tableau serait assemblé au boot sous un nom anonyme
(`md127`) ; sans `update-initramfs`, la ligne serait invisible au moment de
l'assemblage, qui a lieu dans l'initramfs. Dans les deux cas, `/dev/md0` n'existe
pas au boot et la ligne `fstab` de l'étape 5 échoue — avec `nofail`, on démarre
sans le volume ; sans, mode maintenance.

**Étape 4 — l'alerte**

```bash
grep -q '^MAILADDR' /etc/mdadm/mdadm.conf || \
  echo 'MAILADDR root' | sudo tee -a /etc/mdadm/mdadm.conf
sudo systemctl enable --now mdmonitor.service
sudo mdadm --monitor --scan --oneshot --test
sudo journalctl -u mdmonitor --since '5 min ago'
```

`--test` génère un événement `TestMessage` pour chaque tableau : s'il n'arrive
nulle part, la vraie alerte n'arrivera pas non plus. Sur Ubuntu, `mdmonitor` a
besoin d'un agent de courrier local (`postfix` ou `msmtp`) pour que `MAILADDR`
serve à quelque chose ; à défaut, `PROGRAM /usr/local/sbin/alerte-raid.sh` dans
`mdadm.conf` appelle un script (module 16 : envoi vers la supervision).

**Étape 5 — LVM par-dessus**

```bash
sudo pvcreate /dev/md0
sudo vgcreate vg_raid /dev/md0
sudo lvcreate -L 2G -n lv_partage vg_raid
sudo mkfs.ext4 -L partage /dev/vg_raid/lv_partage
sudo mkdir -p /srv/factura/partage
echo '/dev/vg_raid/lv_partage /srv/factura/partage ext4 defaults,nofail 0 2' \
  | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount -a
sudo chown factura:factura /srv/factura/partage
sudo /opt/factura/bin/factura-ecritures.sh /srv/factura/partage &
```

**Étape 6 — la panne**

```bash
sudo mdadm /dev/md0 --fail "${DISQUE1}1"
cat /proc/mdstat
# md0 : active raid1 sdc1[1] sdb1[0](F)
#       5237760 blocks super 1.2 [2/1] [_U]
sudo mdadm --detail /dev/md0 | grep -E 'State|Failed|Working'
#           State : clean, degraded
#  Working Devices : 1
#   Failed Devices : 1
sudo dmesg | tail -3
# md/raid1:md0: Disk failure on sdb1, disabling device.
# md/raid1:md0: Operation continuing on 1 devices.
sudo journalctl -u mdmonitor -n 3
# mdadm[...]: Fail event detected on md device /dev/md0, component device
#   /dev/sdb1
sudo mdadm /dev/md0 --remove "${DISQUE1}1"
```

Le générateur continue d'écrire sans une ligne d'erreur : rien, au-dessus de
`md`, n'a vu la panne.

**Étape 7 — le remplacement**

```bash
sudo mdadm --zero-superblock "${DISQUE1}1"    # le disque « neuf »
sudo mdadm --examine "${DISQUE1}1"             # No md superblock detected
date +%T ; sudo mdadm /dev/md0 --add "${DISQUE1}1"
cat /sys/block/md0/md/sync_action              # recovery
watch -n1 cat /proc/mdstat
#       [======>..............]  recovery = 33.1% (1734400/5237760) ...
cat /sys/block/md0/md/sync_action              # idle, à la fin
date +%T
```

Sans `--zero-superblock`, `--add` sur un ancien membre est traité comme un
`--re-add` : mdadm reconnaît le superblock, compare les `Events` et, si un
*write-intent bitmap* existe, ne resynchronise que les blocs modifiés. Avec un
disque réellement neuf, il n'y a pas de superblock : reconstruction complète.

**Étape 8 — vérification**

```bash
sudo mdadm --detail /dev/md0 | grep -E 'State|Active|Working'
#           State : clean
#  Active Devices : 2
sudo lvs -o lv_name,vg_name,devices vg_raid
#  lv_partage vg_raid /dev/md0(0)
```

**Étape 9 — la question sur `Events`**

`Events` est un compteur dans le superblock de **chaque** membre, incrémenté à
chaque changement d'état du tableau (panne, ajout, début et fin de resync, passage
*clean/active*). Juste après `--add`, le nouveau membre reçoit un superblock avec
le compteur courant, mais le noyau ne le met à jour que lorsque la reconstruction
progresse ; le membre survivant, lui, a enregistré la panne, le retrait et l'ajout.
La différence se résorbe à la fin de la reconstruction. `--assemble` refuse un
membre dont les `Events` sont en retard de plus d'un point sur les autres : c'est
ce qui empêche un vieux disque réinséré d'écraser des données récentes.

> [!NOTE]
> **Pourquoi**
>
> Toute la valeur de ce lab tient dans l'étape 8 : `lvs -o devices` affiche
> `/dev/md0(0)` avant, pendant et après la panne. LVM ne travaille qu'avec des
> périphériques bloc, et `/dev/md0` est resté le même périphérique bloc pendant
> toute l'opération. C'est la raison de l'ordre des couches : la redondance
> **en dessous**, la souplesse **au-dessus**. Si on inversait (LVM sur `sdb1` et
> `sdc1`, puis un miroir logiciel des LV), la perte de `sdb` casserait un PV, le
> VG passerait en mode partiel, `vgchange -ay - -activationmode partial` deviendrait
> nécessaire, et plus rien ne serait « transparent ».
>
> Le second enseignement est le coût de la transparence : entre les étapes 6 et 7,
> le service tournait sur un seul disque et **personne** ne l'aurait su sans
> `mdmonitor`. La supervision d'un RAID n'est pas une option, c'est la moitié du
> RAID.

> [!WARNING]
> **Piège**
>
> `mdadm --fail` puis `--add` **sans** `--remove` entre les deux échoue : un membre
> *faulty* est encore listé dans le tableau, il faut le retirer avant de réinsérer
> un disque au même emplacement. Et `--zero-superblock` sur le mauvais périphérique
> (le survivant) détruit le tableau : relis `cat /proc/mdstat` avant, le membre
> survivant est celui sans `(F)`.

---

### <a id="l11-7"></a>**[L11.7](README.md#l11-7)** — *Un serveur NFS pour deux clients*

**Étapes 1 à 3, sur `lab-ops`**

```bash
sudo apt install -y nfs-kernel-server
getent group factura || sudo groupadd -g 2000 factura
sudo mkdir -p /srv/nfs/partage /srv/nfs/depots
sudo chown root:factura /srv/nfs/partage && sudo chmod 2777 /srv/nfs/partage
sudo chmod 755 /srv/nfs/depots
echo "partage ouvert depuis $(hostname)" | sudo tee /srv/nfs/partage/LISEZMOI
echo "artefact 1.0.0" | sudo tee /srv/nfs/depots/factura-1.0.0.txt
```

```text
# /etc/exports
/srv/nfs/partage  10.10.10.0/24(rw,sync,no_subtree_check,root_squash)
/srv/nfs/depots   10.10.10.11(ro,sync,no_subtree_check)
```

```bash
sudo exportfs -ra && sudo exportfs -v
# /srv/nfs/partage 10.10.10.0/24(sync,wdelay,hide,no_subtree_check,sec=sys,
#                  rw,secure,root_squash,no_all_squash)
# /srv/nfs/depots  10.10.10.11(sync,wdelay,hide,no_subtree_check,sec=sys,
#                  ro,secure,root_squash,no_all_squash)
cat /proc/fs/nfsd/versions        # -2 +3 +4 +4.1 +4.2
sudo ss -tlnp | grep -E ':(2049|111) '
sudo ufw status | grep -q active && \
  sudo ufw allow from 10.10.10.0/24 to any port 2049 proto tcp
```

Options ajoutées par le serveur : `wdelay` (regroupe les écritures voisines),
`hide` (un FS monté sous l'export n'est pas traversé), `sec=sys` (authentification
par UID), `secure` (port source client < 1024), `no_all_squash`.

**Étapes 4 à 7, sur `lab-db`**

```bash
showmount -e 10.10.10.14
# Export list for 10.10.10.14:
# /srv/nfs/partage 10.10.10.0/24
# /srv/nfs/depots  10.10.10.11
sudo mkdir -p /mnt/depots-ops /mnt/partage-ops
sudo mount -t nfs4 10.10.10.14:/srv/nfs/depots /mnt/depots-ops
# mount.nfs4: access denied by server while mounting 10.10.10.14:/srv/nfs/depots
```

`access denied by server` : le serveur a bien l'export, mais **pas pour cette
adresse** — `10.10.10.12` n'est pas `10.10.10.11`. C'est le message à connaître :
il ne dit ni « introuvable » ni « refusé par les permissions », il dit que la liste
d'exports ne contient pas ce client.

```bash
sudo mount -t nfs4 -o hard 10.10.10.14:/srv/nfs/partage /mnt/partage-ops
nfsstat -m | grep -o 'vers=[0-9.]*'          # vers=4.2
sudo touch /mnt/partage-ops/par-root
touch /mnt/partage-ops/par-mathieu
ls -ln /mnt/partage-ops
# -rw-r--r-- 1 65534  2000 0 ... par-root
# -rw-r--r-- 1  1000  2000 0 ... par-mathieu
```

`par-root` appartient à 65534 : `root_squash` (le GID 2000 vient du setgid du répertoire; c'est aussi pour que cet UID 65534 puisse écrire que le répertoire est en `2777` et non `2775`). `par-mathieu` appartient à l'UID
1000 et au GID 2000 : les UID circulent **en numérique**,
le serveur ne sait pas qui est « mathieu », il stocke 1000. Si l'UID 1000 est
quelqu'un d'autre sur `lab-web`, cette personne est propriétaire du fichier
là-bas. C'est la raison d'être d'un annuaire commun (LDAP) dès qu'on partage en
NFS entre plusieurs machines.

```bash
echo '10.10.10.14:/srv/nfs/partage /mnt/partage-ops nfs4 \
  _netdev,nofail,hard,timeo=600,retrans=2,x-systemd.automount 0 0' \
  | sudo tee -a /etc/fstab
sudo umount /mnt/partage-ops
findmnt --verify && sudo systemctl daemon-reload && sudo mount -a
ls /mnt/partage-ops           # déclenche l'automount
```

**Étape 8 — `Stale file handle`**

Sur `lab-db`, `cd /mnt/partage-ops` dans un shell. Sur `lab-ops` :

```bash
sudo mv /srv/nfs/partage /srv/nfs/partage.old
sudo mkdir -m 2777 /srv/nfs/partage && sudo chown root:factura /srv/nfs/partage
sudo exportfs -ra
```

Sur `lab-db`, dans le shell resté dans le répertoire :

```bash
ls
# ls: impossible d'ouvrir le répertoire '.': Descripteur de fichier obsolète
cd / ; ls /mnt/partage-ops       # peut fonctionner : nouveau handle du sommet
sudo umount -l /mnt/partage-ops  # -l si un processus y est encore
sudo mount /mnt/partage-ops
# avec automount : systemctl restart 'mnt-partage\x2dops.automount'
```

Un *file handle* NFS identifie un inode côté serveur (numéro d'inode + génération +
+ FS). Le client en garde un pour chaque fichier ou répertoire ouvert. Quand
l'objet est supprimé côté serveur, le handle ne correspond plus à rien : `ESTALE`.
Le client ne peut pas « rafraîchir » tout seul : il faut re-résoudre le chemin
depuis la racine du montage, donc quitter le répertoire, ou remonter.

**Étape 9, sur `lab-web`** : mêmes commandes qu'aux étapes 5 et 7, plus :

```bash
sudo mkdir -p /mnt/depots-ops
echo '10.10.10.14:/srv/nfs/depots /mnt/depots-ops nfs4 \
  ro,_netdev,nofail,hard,x-systemd.automount 0 0' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount -a && ls /mnt/depots-ops
ls -l /mnt/partage-ops/par-mathieu      # créé depuis lab-db, visible ici
```

> [!NOTE]
> **Pourquoi**
>
> NFSv4 change trois choses par rapport à v3, et elles expliquent presque tous les
> comportements observés. **Un seul port**, 2049 en TCP : plus de `rpcbind` (111) ni
> de `mountd` à port aléatoire à ouvrir sur le pare-feu — `showmount` reste un outil
> v3 et a besoin de 111, c'est pour ça qu'on l'ouvre parfois « juste pour lui ».
> **Un protocole à état** : le serveur sait quels clients ont quels fichiers
> ouverts, ce qui permet les délégations (cache agressif côté client) et les
> verrous intégrés, là où v3 dépendait de `lockd`/`statd`. **Une identité par
> nom** : v4 transporte `utilisateur@domaine` et non des UID, traduit par
> `rpc.idmapd` avec le `Domain` de `/etc/idmapd.conf` — mais en `sec=sys`, les
> noyaux récents court-circuitent cette traduction (`nfs4_disable_idmapping=1`)
> et repassent aux UID numériques, ce qui est exactement ce que montre `ls -ln`.
> Le jour où tous les fichiers apparaissent en `nobody`, le premier réflexe est
> de comparer `Domain` des deux côtés ; le second est de vérifier `sec=`.

> [!WARNING]
> **Piège**
>
> `x-systemd.automount` avec `hard` est la combinaison qui protège le boot **et**
> les données. Mais l'automount masque une erreur classique : `mount -a` ne monte
> rien (il installe juste le point d'automontage), et `check`/`findmnt` disent
> `autofs` tant que personne n'a touché au répertoire. Fais un `ls` dedans avant
> de conclure que « ça ne monte pas ».

---

### <a id="l11-8"></a>**[L11.8](README.md#l11-8)** — *Un disque réseau iSCSI, avec LVM et retour au démarrage*

**Étapes 1 à 3, sur `lab-ops` (cible)**

```bash
sudo apt install -y targetcli-fb
sudo systemctl enable --now rtslib-fb-targetctl.service
sudo mkdir -p /var/lib/iscsi
sudo targetcli
```

```text
/> /backstores/fileio create disque0 /var/lib/iscsi/disque0.img 2G
Created fileio disque0 with size 2147483648
/> /iscsi create iqn.2026-09.local.lab:ops.disque0
Created target iqn.2026-09.local.lab:ops.disque0.
Created TPG 1.
Global pref auto_add_default_portal=true
Created default portal listening on all IPs (0.0.0.0), port 3260.
/> cd /iscsi/iqn.2026-09.local.lab:ops.disque0/tpg1
/iscsi/iqn.20...disque0/tpg1> portals/ delete 0.0.0.0 3260
/iscsi/iqn.20...disque0/tpg1> portals/ create 10.10.10.14 3260
/iscsi/iqn.20...disque0/tpg1> luns/ create /backstores/fileio/disque0
/iscsi/iqn.20...disque0/tpg1> acls/ create iqn.2026-09.local.lab:db
Created Node ACL for iqn.2026-09.local.lab:db
Created mapped LUN 0.
/iscsi/iqn.20...disque0/tpg1> cd acls/iqn.2026-09.local.lab:db
/iscsi/iqn.20...local.lab:db> set auth userid=lab-db password=Secr3tISCSI
/iscsi/iqn.20...local.lab:db> cd ../..
/iscsi/iqn.20...disque0/tpg1> set attribute authentication=1
/iscsi/iqn.20...disque0/tpg1> cd /
/> ls
/> saveconfig
/> exit
```

```bash
sudo grep -E '"(name|node_wwn|userid|authentication)"' \
  /etc/rtslib-fb-target/saveconfig.json
sudo ss -tlnp | grep 3260              # 10.10.10.14:3260
sudo ufw status | grep -q active && \
  sudo ufw allow from 10.10.10.12 to any port 3260 proto tcp
```

Le portail par défaut écoute sur `0.0.0.0` : toutes les interfaces, y compris
celle qu'on ne veut pas exposer. Le remplacer par `10.10.10.14` limite la surface ;
c'est le pendant réseau de l'ACL (qui limite par identité).

**Étapes 4 à 6, sur `lab-db` (initiateur)**

```bash
sudo apt install -y open-iscsi
echo 'InitiatorName=iqn.2026-09.local.lab:db' \
  | sudo tee /etc/iscsi/initiatorname.iscsi
sudo systemctl restart iscsid
sudo iscsiadm -m discovery -t sendtargets -p 10.10.10.14
# 10.10.10.14:3260,1 iqn.2026-09.local.lab:ops.disque0
sudo iscsiadm -m node -T iqn.2026-09.local.lab:ops.disque0 \
  -p 10.10.10.14 --login
# iscsiadm: Could not login to [iface: default, target: iqn...:ops.disque0,
#   portal: 10.10.10.14,3260].
# iscsiadm: initiator reported error (24 - iSCSI login failed due to
#   authorization failure)
```

```bash
T=iqn.2026-09.local.lab:ops.disque0 ; P=10.10.10.14
sudo iscsiadm -m node -T $T -p $P --op update \
  -n node.session.auth.authmethod -v CHAP
sudo iscsiadm -m node -T $T -p $P --op update \
  -n node.session.auth.username -v lab-db
sudo iscsiadm -m node -T $T -p $P --op update \
  -n node.session.auth.password -v Secr3tISCSI
sudo iscsiadm -m node -T $T -p $P --login
# Login to [iface: default, target: iqn...:ops.disque0, portal: ...] successful.
sudo iscsiadm -m session -P 3 | grep -E 'Target:|Attached scsi disk|State'
lsblk -o NAME,SIZE,TYPE,VENDOR,MODEL | grep -E 'NAME|LIO'
# sdd     2G disk LIO-ORG  disque0
ls -l /dev/disk/by-path/ | grep iscsi
# ip-10.10.10.14:3260-iscsi-iqn.2026-09.local.lab:ops.disque0-lun-0 -> ../../sdd
```

`sdd` est le prochain nom libre au moment où le disque est apparu ; après un
redémarrage où un disque USB traînerait, ce serait `sde`. Le lien `by-path`
encode portail + IQN + LUN, il est stable. LVM, lui, retrouve son PV par la
signature écrite sur le disque, quel que soit son nom.

**Étape 7 — LVM et `fstab`**

```bash
ISCSI=/dev/disk/by-path/ip-10.10.10.14:3260-iscsi-$T-lun-0
sudo pvcreate "$ISCSI"
sudo vgcreate vg_iscsi "$ISCSI"
sudo lvcreate -l 100%FREE -n lv_depots vg_iscsi
sudo mkfs.ext4 -L depots /dev/vg_iscsi/lv_depots
sudo mkdir -p /srv/factura/depots
echo '/dev/vg_iscsi/lv_depots /srv/factura/depots ext4 \
  defaults,_netdev,nofail 0 2' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount -a && df -h /srv/factura/depots
```

**Étape 8 — retour au démarrage**

```bash
sudo iscsiadm -m node -T $T -p $P --op update -n node.startup -v automatic
grep startup "/etc/iscsi/nodes/$T/$P,3260,1/default"
# node.startup = automatic
sudo systemctl enable iscsid.service open-iscsi.service
sudo reboot
# au retour :
sudo iscsiadm -m session ; findmnt /srv/factura/depots
journalctl -b -u open-iscsi | tail -3
```

Chaîne au démarrage : `network-online.target` → `iscsid` → `open-iscsi.service`
(qui fait `iscsiadm -m node --loginall=automatic`) → le disque apparaît → udev
déclenche `lvm2-pvscan@` qui active `vg_iscsi` → `srv-factura-depots.mount`,
que `_netdev` avait fait attendre après `remote-fs-pre.target`. Sans `_netdev`,
systemd classe le montage dans `local-fs.target` et le tente avant le réseau :
échec, puis `nofail` évite le mode maintenance, mais le volume n'est pas monté.

**Étape 9 — cible coupée pendant l'écriture**

Sur `lab-ops` : `sudo systemctl stop rtslib-fb-targetctl`. Sur `lab-db`, les
écritures se figent, puis après `node.session.timeo.replacement_timeout`
(120 s par défaut) :

```console
 connection1:0: detected conn error (1020)
 session1: session recovery timed out after 120 secs
 sd 3:0:0:0: rejecting I/O to offline device
 EXT4-fs error (device dm-3): ... I/O error
 EXT4-fs (dm-3): Remounting filesystem read-only
```

Le montage passe en lecture seule (`errors=remount-ro` d'ext4). Au retour de la
cible, `iscsid` rétablit la session (`connection1:0 is operational after
recovery`), mais le FS reste en `ro` : `umount`, `e2fsck -f`, `mount` pour
revenir. Pendant les 120 s, les processus qui écrivent sont en état `D`, comme
sur NFS `hard`. Réduire `replacement_timeout` rend les erreurs plus rapides, pas
les données plus sûres : la bonne valeur dépend du temps de bascule de la baie.

> [!NOTE]
> **Pourquoi**
>
> L'ordre de la configuration côté cible n'est pas arbitraire. **Backstore** : ce
> qu'on expose (un fichier, un disque, un LV). **Target** (IQN) : le nom que les
> initiateurs cherchent. **TPG** : un groupe de portails, c'est-à-dire des
> couples IP:port et une politique d'accès. **LUN** : l'association d'un backstore
> à ce TPG, numérotée depuis 0. **ACL** : la liste des IQN d'initiateurs admis, avec
> pour chacun ses LUN mappées et ses secrets CHAP. Un initiateur non listé est
> refusé avant même de voir une LUN, et `authentication=1` sur le TPG impose CHAP à
> tous ceux qui sont listés. `generate_node_acls=1` (mode « démo ») supprime les
> ACL : à ne jamais laisser en production.
>
> Le fichier `saveconfig.json` est la seule persistance : `targetcli` modifie le
> noyau en direct via `configfs` (`/sys/kernel/config/target/`), et sans
> `saveconfig` tout disparaît au redémarrage. `rtslib-fb-targetctl.service` ne fait
> que recharger ce JSON au boot.

> [!WARNING]
> **Piège**
>
> Le mot de passe CHAP a des contraintes : 12 à 16 caractères chez la plupart des
> initiateurs (Windows et VMware les imposent ; Linux tolère plus court mais pas
> tous les caractères spéciaux). Et le CHAP posé sur l'ACL ne sert **qu'à la
> session** : la découverte (`sendtargets`) reste ouverte à qui atteint le port
> — on la protège par le pare-feu ou par un CHAP de découverte
> (`/iscsi set discovery_auth enable=1 userid=... password=...`).

---

## 11.7 Break & Fix

### <a id="bf11-1"></a>**[BF11.1](README.md#bf11-1)** — *La VM ne démarre plus : `fstab` fautif*

**Cause racine** : `break_M11_01.sh` a ajouté dans `/etc/fstab` une ligne dont l'UUID
ne correspond à aucun volume présent, sans `nofail` :

```text
UUID=9c1f7a30-2b4e-...-7e0f3b9d1234  /srv/factura/archives  ext4  defaults  0  2
```

**Démarche de diagnostic**

1. **Lire l'écran.** Les trois lignes disent tout :
   * `A start job is running for /dev/disk/by-uuid/9c1f...` → systemd attend
     l'apparition d'un périphérique. Il n'existe pas ;
   * `Dependency failed for /srv/factura/archives` → le montage qui en dépend échoue ;
   * `Dependency failed for Local File Systems` → `local-fs.target` échoue, donc tout
     le reste. L'UUID est affiché à l'écran : c'est déjà la moitié du diagnostic.

2. **Obtenir un shell.** Le prompt `Give root password for maintenance` n'est
   utilisable que si un mot de passe root existe. Sur Ubuntu Server par défaut, le
   compte root est **verrouillé** (`!` dans `/etc/shadow`) : aucun mot de passe ne
   fonctionne, il faut passer par GRUB.

   * Redémarrer, maintenir `Shift` (BIOS) ou `Échap` (UEFI) pour le menu GRUB ;
   * touche `e` sur l'entrée Ubuntu ;
   * sur la ligne `linux`, remplacer `ro` par `rw` et ajouter `init=/bin/bash` ;
   * `Ctrl-X`.

3. **Identifier la ligne fautive.**

```bash
mount -o remount,rw /           # si on n'a pas mis rw à l'étape 2
findmnt --verify --verbose
```

```console
/srv/factura/archives
   [ ] target exists
   [E] unreachable on boot required source: UUID=9c1f7a30-2b4e-...-7e0f3b9d1234
```

```bash
blkid                           # aucun volume ne porte cet UUID
mount -a                        # confirme :
# mount: /srv/factura/archives: can't find UUID=9c1f7a30-2b4e-...-3b9d1234.
```

**Correctif**

```bash
vi /etc/fstab                   # corriger l'UUID, ou commenter la ligne
blkid -s UUID -o value /dev/sdb1        # le vrai UUID, si le volume existe
mount -a                        # doit se terminer sans une seule erreur
findmnt --verify --verbose      # doit dire "Success, no errors"
sync
exec /sbin/init                 # ou : reboot -f
```

**Durcissement** — la ligne corrigée :

```text
UUID=<le bon>  /srv/factura/archives  ext4
  defaults,nofail,x-systemd.device-timeout=10s  0  0
```

> [!NOTE]
> **Pourquoi**
>
> Trois mécanismes à savoir expliquer, et c'est exactement ce qu'on demande en entretien.
>
> **Pourquoi `/` est en lecture seule.** L'initramfs monte la racine en lecture seule,
> volontairement : tant que `fsck` n'a pas eu l'occasion de tourner, écrire sur un
> système de fichiers potentiellement sale est dangereux. C'est
> `systemd-remount-fs.service` qui la repasse en lecture-écriture, très tôt dans la
> séquence de démarrage. Avec `init=/bin/bash`, systemd n'est **jamais lancé** :
> personne ne fait ce remontage, d'où le `mount -o remount,rw /` obligatoire avant
> d'éditer. En `emergency.target` en revanche, systemd a tourné et la racine est
> généralement déjà en écriture — mais on vérifie toujours avec `findmnt /`.
>
> **D'où viennent les 90 secondes.** `systemd-fstab-generator` crée, pour chaque source
> en `UUID=`, une unité `.device` représentant l'attente de
> `/dev/disk/by-uuid/9c1f...`. Cette unité hérite de `DefaultDeviceTimeoutSec` (`/etc/systemd/system.conf`), soit 90 s
> sur Ubuntu. systemd attend donc qu'`udev` annonce le périphérique, ce qui n'arrive
> jamais, puis abandonne. `x-systemd.device-timeout=10s` dans les options de `fstab`
> remplace cette valeur pour ce montage précis.
>
> **Pourquoi ça bloque tout le démarrage.** L'unité `srv-factura-archives.mount` est
> rattachée à `local-fs.target` par une relation `Before=` et `RequiredBy=`. Une unité
> requise qui échoue fait échouer la cible, et `local-fs.target` est une dépendance de
> `sysinit.target`, donc de `multi-user.target`. systemd bascule alors sur
> `emergency.target` : aucun réseau, aucun SSH, juste une console. `nofail` transforme le
> `RequiredBy=` en `WantedBy=` : l'échec est journalisé et la séquence continue.

> [!WARNING]
> **Piège**
>
> Le réflexe dangereux est de **vider `/etc/fstab`** pour « débloquer le boot ». Sans
> la ligne de `/`, la machine démarre encore (la racine est montée depuis la ligne de
> commande noyau), mais `/boot`, `/boot/efi` et le swap ne sont plus montés. Le
> prochain `apt upgrade` installe un noyau dans un `/boot` qui n'est pas le bon, et
> la machine ne redémarrera plus du tout. On corrige la ligne fautive, on ne supprime
> jamais le fichier.
>
> Deuxième réflexe dangereux : éditer `fstab` puis redémarrer directement pour
> « voir si ça marche ». `findmnt --verify` et `mount -a` prennent dix secondes et te
> disent la vérité tout de suite. Sur une machine distante sans console, c'est la
> différence entre un incident de dix secondes et un déplacement au datacenter.

---

### <a id="bf11-2"></a>**[BF11.2](README.md#bf11-2)** — *`No space left on device` avec 47 % d’occupation*

**Cause racine** : les **inodes** du système de fichiers monté sur
`/srv/factura/archives` sont épuisés. Le volume a été créé avec un nombre d'inodes
très faible, et un répertoire `sessions/` contient des milliers de fichiers de taille
nulle.

**Démarche de diagnostic**

```bash
df -h /srv/factura/archives       # 47 % — ce n'est pas l'espace
df -i /srv/factura/archives       # 100 % — c'est ça
```

```console
Sys. de fichiers Inodes IUtil. ILibre IUti% Monté sur
/dev/loop7         2560   2560      0  100% /srv/factura/archives
```

Trouver le coupable :

```bash
sudo find /srv/factura/archives -xdev -printf '%h\n' \
  | sort | uniq -c | sort -rn | head
```

```console
   2301 /srv/factura/archives/sessions
     41 /srv/factura/archives/depots
      7 /srv/factura/archives
```

```bash
ls -l /srv/factura/archives/sessions | head -3       # des fichiers de 0 octet
```

**Correctif immédiat** — libérer des inodes sans perdre de données :

```bash
sudo find /srv/factura/archives/sessions -type f -mtime +1 -delete
df -i /srv/factura/archives
sudo touch /srv/factura/archives/test && echo "écriture rétablie"
```

**Correctif durable** — le bon formatage, au moment de (re)créer le volume qui porte `/srv/factura/archives` (le `/ dev/sdb1` de L11.1, ou un LV dédié) :

```bash
sudo mkfs.ext4 -N 2000000 /dev/sdb1
# ou, en ratio :
sudo mkfs.ext4 -i 4096 /dev/sdb1
```

> [!NOTE]
> **Pourquoi**
>
> La question posée — « `lvextend -r` résout-il le problème ? » — a une réponse en deux
> temps, et c'est tout l'intérêt du Break & Fix.
>
> **Pour ext4 : oui, partiellement.** `resize2fs` en agrandissement ajoute des groupes
> de blocs, et chaque groupe de blocs contient un nombre fixe d'inodes déterminé par le
> ratio choisi à la création. Agrandir de 50 % ajoute donc environ 50 % d'inodes. Mais
> si le volume a été créé avec un ratio catastrophique (`-T largefile`, un inode par
> Mio), il faudrait multiplier la taille par vingt pour récupérer vingt fois plus
> d'inodes. Économiquement absurde.
>
> **Pour XFS : la question ne se pose pas.** XFS alloue ses inodes dynamiquement, à la
> demande, dans n'importe quel groupe d'allocation. Il ne connaît pas la pénurie
> d'inodes, sauf à atteindre `imaxpct` (25 % de l'espace par défaut, réglable avec
> `xfs_growfs -m`). C'est un argument réel en faveur de XFS pour un volume dont on ne
> sait pas prévoir le profil de fichiers.
>
> **Et le nombre d'inodes d'un ext4 n'est jamais réductible ni augmentable en place.**
> Aucune option de `tune2fs` ne le change. La seule voie est `mkfs`, donc
> sauvegarde-reformatage-restauration. C'est pour cette raison qu'on réfléchit au
> `-i` / `-N` **au moment de la création**, en se demandant : combien de fichiers, de
> quelle taille moyenne ?

> [!WARNING]
> **Piège**
>
> Le message `No space left on device` (`ENOSPC`) est renvoyé pour les deux pénuries,
> et c'est la source de l'incident : tout le monde regarde `df -h`, voit de la place, et
> part sur une fausse piste pendant une heure. Réflexe à ancrer : devant un `ENOSPC`,
> **toujours les deux commandes**, `df -h` puis `df -i`.
>
> Les deux autres causes d'`ENOSPC` avec de la place apparente, pour compléter le
> tableau : un fichier supprimé mais tenu ouvert par un processus (`lsof +L1`, traité au
> module 02), et l'épuisement de la **réserve root** sur un volume où le processus
> écrivain n'est pas root (`df` affiche 100 % alors que `tune2fs -l | grep Reserved`
> montre encore des blocs libres, inaccessibles à l'utilisateur).

---

### <a id="bf11-3"></a>**[BF11.3](README.md#bf11-3)** — *Le snapshot a débordé*

**Cause racine** : `break_M11_03.sh` a créé un snapshot volontairement sous-dimensionné
(32 Mio) puis a généré sur l'origine un volume d'écritures supérieur
à sa capacité. La zone de copie sur écriture est pleine, le device-mapper a invalidé
le snapshot.

**Démarche de diagnostic**

```bash
sudo lvs -o lv_name,vg_name,attr,size,origin,data_percent
```

```console
  LV        VG      Attr       LSize  Origin    Data%
  lv_pgdata vg_data owi-aos--- 3,00g
  snap_pg   vg_data swi-I-s---  32,00m lv_pgdata 100,00
```

L'attribut `swi-I-s---` est la signature. Position par position :

```text
s w i - I - s - - -
│ │ │   │   └── cible : (s)napshot
│ │ │   └────── ÉTAT : (I)nvalide  <- c'est lui
│ │ └────────── allocation héritée
│ └──────────── inscriptible
└────────────── (s)napshot
```

Confirmation dans le journal noyau :

```bash
sudo dmesg -T | grep -i snapshot
# device-mapper: snapshots: Invalidating snapshot: Unable to allocate
# exception.
```

**Correctif**

```bash
sudo umount /mnt/snap 2>/dev/null || true
sudo lvremove -y /dev/vg_data/snap_pg
sudo vgs                                 # vérifier l'espace libre du groupe
sudo lvcreate -s -l 15%ORIGIN -n snap_pg /dev/vg_data/lv_pgdata
sudo mount -o ro /dev/vg_data/snap_pg /mnt/snap
sudo tar czf /srv/sauvegardes/factura-db-$(date +%F).tar.gz -C /mnt/snap .
sudo umount /mnt/snap && sudo lvremove -y /dev/vg_data/snap_pg
```

**Les deux protections demandées**

1. **Dimensionnement** — `-l 15%ORIGIN` au lieu d'une taille en dur : le snapshot
   suit automatiquement la croissance de l'origine. Et surtout, mesurer une fois en
   conditions réelles : lancer la sauvegarde, relever `data_percent` à la fin,
   multiplier par trois.
2. **Surveillance** — `lvs -S 'data_percent>70'` dans le script de supervision, avec
   alerte. Et le filet de sécurité de LVM (`dmeventd`) :

```ini
# /etc/lvm/lvm.conf, section activation { ... }
snapshot_autoextend_threshold = 70
snapshot_autoextend_percent = 20
```

Avec ces deux valeurs et `dmeventd` actif (`sudo systemctl enable --now
lvm2-monitor.service`), LVM agrandit automatiquement le snapshot de 20 % dès qu'il
atteint 70 % — tant qu'il reste de l'espace dans le VG. C'est la raison pour laquelle
on laisse toujours de l'espace non alloué dans un groupe de volumes.

> [!NOTE]
> **Pourquoi**
>
> Le mécanisme, à raconter dans l'ordre :
>
> 1. à la création, LVM alloue une zone d'exception vide et une table de correspondance.
>    **Aucune donnée n'est copiée** ;
> 2. à chaque écriture sur l'origine, le device-mapper vérifie si le *chunk* concerné
>    (4 Kio par défaut) a déjà été sauvegardé. Si non, il lit l'ancien contenu, l'écrit
>    dans la zone d'exception, note la correspondance, puis laisse l'écriture se faire ;
> 3. quand la zone d'exception est pleine, il ne peut plus sauvegarder l'ancien
>    contenu. Il ne peut donc plus garantir la vue figée qu'il promettait. Plutôt que
>    de servir des données incohérentes, il **invalide** le volume : toute lecture
>    échoue.
>
> Le point qui rassure et qu'il faut savoir énoncer sans hésiter : **l'origine n'est
> jamais affectée**. Le snapshot stocke les *anciennes* versions ; s'il ne peut plus les
> stocker, on perd la photo, pas le sujet. La base a continué de tourner sans rien
> remarquer pendant toute la durée de l'incident — ce que confirme d'ailleurs l'énoncé.
>
> Rien n'est réparable dans un snapshot invalidé : il n'y a pas de `snapshot_repair`,
> pas de récupération partielle. On supprime, on recrée, on refait la sauvegarde.

> [!WARNING]
> **Piège**
>
> Le piège de diagnostic est `df`. Sur un snapshot **monté**, `df` affiche le
> remplissage du système de fichiers photographié — identique à celui de l'origine au
> moment T, souvent 30 ou 40 %. On en conclut que le snapshot a de la place, alors que
> sa zone de copie sur écriture est à 100 %. Les deux chiffres n'ont aucun rapport. La
> seule métrique valable est `data_percent` de `lvs`.
>
> Piège d'exploitation : si le VG n'a plus d'espace libre, l'auto-extension ne peut pas
> fonctionner, même configurée. Un VG rempli à 100 % par des LV est un VG où les
> snapshots ne sont plus possibles — et donc où les sauvegardes cohérentes ne sont plus
> possibles. Garder 15 à 20 % de marge dans un VG n'est pas du gaspillage, c'est une
> capacité opérationnelle.

---

### <a id="bf11-4"></a>**[BF11.4](README.md#bf11-4)** — *Démontage impossible et extension refusée*

**Deux causes distinctes, qui n'ont rien à voir l'une avec l'autre.**

**Cause A — le démontage : un `bind mount` et un processus**

```bash
sudo umount /srv/factura/archives
# umount: /srv/factura/archives: target is busy.

sudo fuser -vm /srv/factura/archives
```

```console
                     UTIL.       PID ACCÈS  COMMANDE
/srv/factura/archives: root     3182 ..c..  sleep
```

Le `c` indique un processus dont le **répertoire courant** est dans le volume — il n'a
aucun fichier ouvert, `lsof` seul l'aurait presque manqué. On le traite :

```bash
sudo kill 3182
sudo umount /srv/factura/archives
# umount: /srv/factura/archives: target is busy.     <- toujours !
```

`fuser` et `lsof` ne renvoient plus rien, et pourtant le volume reste occupé. C'est le
signe d'un **montage**, pas d'un processus :

```bash
findmnt -R /srv/factura/archives
grep archives /proc/self/mountinfo
```

```console
TARGET                     SOURCE      FSTYPE OPTIONS
/srv/factura/archives      /dev/loop7  ext4   rw,relatime
/srv/backup-tmp            /dev/loop7[/depots] ext4 rw,relatime
```

Un `bind mount` de `/srv/factura/archives/depots` a été monté sur `/srv/backup-tmp`.
Le système de fichiers est donc utilisé ailleurs dans l'arborescence.

```bash
sudo umount /srv/backup-tmp
sudo umount /srv/factura/archives        # cette fois, ça passe
```

**Cause B — l'extension : le VG est plein à cause d'un snapshot oublié**

```bash
sudo lvextend -L +512M -r /dev/vg_data/lv_pgdata
# Insufficient free space: 128 extents needed, but only 0 available

sudo vgs
```

```console
  VG      #PV #LV #SN Attr   VSize VFree
  vg_data   1   3   1 wz--n- <5,00g    0
```

`#SN 1` : il y a un **snapshot**. `VFree 0` : il a mangé tout le reste.

```bash
sudo lvs -o lv_name,attr,size,origin,data_percent,lv_time
```

```console
  LV        Attr       LSize  Origin    Data%  Time
  lv_pgdata owi-aos--- 3,00g
  lv_test   -wi-a-----  1,00g
  snap_pg   swi-a-s---  <1,00g lv_pgdata  2,10  2026-08-24 02:30:11 +0200
```

Un snapshot créé le 24 août, rempli à 2 %, qui immobilise ~ 1 Go depuis trois
semaines : la sauvegarde du 24 août s'est interrompue sans nettoyer. (Dans le lab, `lv_time` affiche l'heure réelle du `break` ; en production, c'est cette colonne qui date l'oubli.)

```bash
sudo lvremove -y /dev/vg_data/snap_pg
sudo vgs                                  # VFree est revenu
sudo lvextend -L +512M -r /dev/vg_data/lv_pgdata
```

**Règle d'exploitation à retenir (les trois lignes demandées)**

> Un snapshot LVM est un objet **temporaire** : il se crée, il sert, il se supprime
> dans la même exécution. Tout script qui en crée un installe un `trap ... EXIT` qui
> le supprime, quelle que soit la façon dont il se termine. Un snapshot vieux de plus
> de 24 heures est un incident à alerter, pas un état normal.

> [!NOTE]
> **Pourquoi**
>
> Les deux causes se ressemblent sur un point : `fuser`, `lsof` et `lvextend` disent la
> vérité, mais pas toute la vérité. Il faut savoir où regarder ensuite.
>
> Pour le `target is busy`, la liste complète des raisons possibles, dans l'ordre où on
> les teste :
>
> 1. un processus (fichier ouvert, `cwd`, exécutable, `mmap`) → `fuser -vm`, `lsof` ;
> 2. un **montage imbriqué ou un bind mount** → `findmnt -R`, `/proc/self/mountinfo` ;
> 3. un fichier de **swap** actif sur le volume → `swapon --show` ;
> 4. un **loop device** dont le fichier support est dessus → `losetup -a` ;
> 5. un **espace de noms de montage** distinct (conteneur Docker, service systemd avec
>    `PrivateMounts=`) → `sudo grep -l archives /proc/*/mountinfo` ;
> 6. un export **NFS** actif sur le volume → `exportfs -v`.
>
> Les points 2 et 5 sont ceux qui font perdre le plus de temps, parce que les deux
> outils réflexes ne les voient pas — par construction : ce ne sont pas des processus.
>
> Pour le VG plein, la leçon est ailleurs : `vgs` affiche `#SN`, le nombre de snapshots,
> dans une colonne que personne ne regarde jamais. Prends l'habitude de lire cette
> colonne, elle t'évitera un diagnostic de vingt minutes. Et `lvs -o +lv_time` donne la
> date de création de chaque volume : c'est ce qui permet de dire « ce snapshot date du
> 24 août » et de remonter à l'exécution de sauvegarde qui a mal fini.

---

### <a id="bf11-5"></a>**[BF11.5](README.md#bf11-5)** — *Le miroir dégradé que personne n'a vu*

**Cause racine** : `break_M11_05.sh` a marqué un membre de `/dev/md0` *faulty*
(`mdadm --fail`), puis a rendu l'alerte muette : `mdmonitor.service` arrêté et
désactivé, `MAILADDR` mis en commentaire dans `/etc/mdadm/mdadm.conf`. Le
tableau tourne sur un seul disque depuis, sans que rien ne l'ait signalé.

**Démarche de diagnostic**

1. **L'état réel, en deux commandes.**

   ```bash
   cat /proc/mdstat
   sudo mdadm --detail /dev/md0
   ```

   ```console
   md0 : active raid1 sdc1[1] sdb1[0](F)
         5237760 blocks super 1.2 [2/1] [_U]
   ```

   ```console
              State : clean, degraded
     Active Devices : 1
    Working Devices : 1
     Failed Devices : 1
        Update Time : Thu Sep 17 22:41:08 2026
   Number   Major   Minor   RaidDevice State
      -       0        0        0      removed
      1       8       33        1      active sync   /dev/sdc1
      0       8       17        -      faulty   /dev/sdb1
   ```

   `(F)`, `[2/1]`, `[_U]`, `degraded`, `faulty` : cinq façons de dire la même
   chose. `Update Time` donne un premier indice de date.

2. **Dater la panne.** Le noyau a journalisé l'événement :

   ```bash
   sudo journalctl -k --grep 'md0|md/raid1' --no-pager | tail -5
   # sept. 17 22:41:08 lab-db kernel: md/raid1:md0: Disk failure on sdb1,
   #   disabling device.
   # sept. 17 22:41:08 lab-db kernel: md/raid1:md0: Operation continuing on
   #   1 devices.
   sudo mdadm --examine /dev/sdb1 | grep -E 'Update Time|Events|State'
   sudo mdadm --examine /dev/sdc1 | grep -E 'Update Time|Events|State'
   ```

   Le membre *faulty* a cessé d'être mis à jour à l'instant de la panne : son
   `Update Time` est figé et son compteur `Events` est en retard sur celui du
   survivant. C'est la datation la plus fiable, elle survit à une rotation des
   journaux.

3. **Pourquoi personne n'a rien vu.**

   ```bash
   systemctl status mdmonitor.service
   # ○ mdmonitor.service - MD array monitor
   #      Loaded: loaded (...; disabled; preset: enabled)
   #      Active: inactive (dead)
   grep -E '^#?MAILADDR|^#?PROGRAM' /etc/mdadm/mdadm.conf
   # #MAILADDR root
   sudo journalctl -u mdmonitor --no-pager | tail -3
   ```

   Le moniteur est arrêté **et** désactivé, et son destinataire est commenté :
   même relancé, il n'aurait envoyé à personne. Deux défaillances indépendantes
   de la supervision, qui expliquent un silence total.

4. **Est-ce que le disque est réellement mort ?** Avant de réintégrer un membre,
   on vérifie qu'il n'est pas en train de mourir :

   ```bash
   sudo journalctl -k --grep 'sdb' | grep -iE 'I/O error|medium|reset' | tail
   sudo smartctl -H /dev/sdb 2>/dev/null || echo "pas de SMART (disque virtuel)"
   ```

   Ici, aucune erreur d'E/S : la mise en défaut est administrative (`--fail`),
   le disque est sain. Sur un vrai serveur, un disque avec des erreurs `medium`
   ou un SMART `FAILED` se remplace, il ne se réintègre pas.

**Correctif, sans arrêter le service**

```bash
sudo mdadm /dev/md0 --remove /dev/sdb1
sudo mdadm /dev/md0 --re-add /dev/sdb1    # rapide si bitmap, sinon refusé
# si --re-add refuse (« not possible ») : --add, reconstruction complète
watch -n1 cat /proc/mdstat
sudo mdadm --detail /dev/md0 | grep -E 'State|Active'
#           State : clean
#  Active Devices : 2
```

`/srv/factura/partage` est resté monté et le générateur d'écritures n'a pas vu
passer l'opération : `lvs -o +devices` montre toujours `/dev/md0(0)`.

**Rétablir l'alerte et la prouver**

```bash
sudo sed -i 's/^#MAILADDR/MAILADDR/' /etc/mdadm/mdadm.conf
grep -q '^MAILADDR' /etc/mdadm/mdadm.conf || \
  echo 'MAILADDR root' | sudo tee -a /etc/mdadm/mdadm.conf
sudo systemctl enable --now mdmonitor.service
sudo mdadm --monitor --scan --oneshot --test
sudo journalctl -u mdmonitor --since '2 min ago' --no-pager
# ... mdadm[...]: TestMessage event detected on md device /dev/md0
```

Si aucun agent de courrier n'est installé, le message `TestMessage` reste dans
le journal et rien ne part : c'est le moment de brancher `PROGRAM` sur un script
qui pousse vers la supervision, ou d'installer un relais (`msmtp-mta`).

**Prévention**

* une sonde qui lit `/proc/mdstat` et alerte sur `_` dans les crochets ou sur
  `(F)` — le script `verif-stockage.sh` du défi D11 le fait, un exporter
  Prometheus (`node_md_disks{state="failed"}`) aussi ;
* `mdmonitor.service` **activé** et testé après chaque installation (`--test`) ;
* un `mdadm --detail` à chaque intervention sur une machine avec RAID, comme on
  regarde `df -h` : dix secondes qui évitent le second disque perdu.

> [!NOTE]
> **Pourquoi**
>
> Un RAID dégradé est le type même de l'incident **silencieux** : aucune métrique
> applicative ne bouge, la latence est même parfois meilleure (une écriture de
> moins). Le tableau peut rester dans cet état des mois, jusqu'à la panne du
> survivant, et la perte de données est alors totale — c'est à ce moment-là que la
> direction découvre que « il y avait du RAID ». La règle : un système redondant
> qui a perdu sa redondance est **en panne**, pas « encore en marche ». Il doit
> remonter dans la supervision avec la même sévérité qu'un service arrêté.
>
> `--re-add` est possible parce que le superblock du membre *faulty* est intact et
> que mdadm crée par défaut un *write-intent bitmap* sur les tableaux de plus de
> 100 Go (ici, il n'y en a pas : `--re-add` est refusé et c'est `--add`, avec une reconstruction complète, courte sur 5 Go, qui s'applique).
> Sur un vrai volume avec bitmap, `--re-add` après un faux positif (câble, reset
> de contrôleur) ne resynchronise que les bandes modifiées : quelques minutes au
> lieu d'une journée.

> [!WARNING]
> **Piège**
>
> Deux erreurs classiques. `mdadm --add` sans `--remove` préalable : `mdadm: Cannot
> open /dev/sdb1: Device or resource busy`, parce que le membre *faulty* occupe
> toujours son emplacement. Et `mdadm --assemble --force` ou `- -create` pour
> « réparer » : le premier n'a de sens que sur un tableau arrêté, le second
> détruit. Un tableau **actif et dégradé** se répare avec `--remove` / `--add`,
> rien d'autre.

---

### <a id="bf11-6"></a>**[BF11.6](README.md#bf11-6)** — *`ls` bloqué sur un montage NFS `hard`*

**Cause racine** : `break_M11_06.sh` a posé une règle de pare-feu locale sur
`lab-db` qui **jette** les paquets sortants vers `10.10.10.14` port 2049 (table
`nft` `inet lab11bf`). Le serveur répond au `ping` — ICMP n'est pas filtré —
mais plus une seule requête NFS ne lui parvient. Le montage est en `hard` : le
client réessaie indéfiniment, et le script a lancé un processus (`factura-rapport`)
qui écrit dans le partage et qui s'est figé.

**Démarche de diagnostic**

1. **Qui est bloqué, et dans quel état.** Ne pas relancer un `ls` sur le
   partage : chaque nouvel accès crée un processus bloqué de plus.

   ```bash
   ps -eo pid,stat,wchan:24,etime,cmd | awk '$2 ~ /^D/'
   #  4517 D+   rpc_wait_bit_killable  02:14 factura-rapport
   #  4602 D+   rpc_wait_bit_killable  00:41 ls --color=auto /mnt/partage-ops
   uptime
   #  ... load average: 2,03, 1,41, 0,66     (CPU à 0 %)
   ```

   `D` : sommeil non interruptible. `wchan` = `rpc_wait_bit_killable` : le
   processus attend une **réponse RPC** — c'est la signature NFS, un disque
   local donnerait `io_schedule` ou `blk_mq_get_tag`. Chaque processus en `D`
   compte 1 dans la charge moyenne, d'où le *load* qui grimpe sans CPU.

2. **Confirmer que c'est NFS.**

   ```bash
   sudo dmesg | tail -3
   # nfs: server 10.10.10.14 not responding, still trying
   findmnt -t nfs4,nfs
   cat /proc/self/mountstats | grep -A3 'partage-ops'   # RPC en attente
   ```

   `still trying` (et non `timed out`) : c'est le vocabulaire d'un montage `hard`.

3. **Pourquoi le serveur est-il injoignable pour NFS et pas pour `ping` ?**

   ```bash
   ping -c1 10.10.10.14                       # OK
   timeout 3 nc -vz 10.10.10.14 2049          # ... rien, expiration
   rpcinfo -p 10.10.10.14 | grep nfs          # peut répondre : port 111 passe
   sudo nft list ruleset
   ```

   ```console
   table inet lab11bf {
       chain sortie {
           type filter hook output priority filter; policy accept;
           ip daddr 10.10.10.14 tcp dport 2049 drop
       }
   }
   ```

   Le port 2049 est jeté **en sortie, localement**. Le serveur n'a rien : c'est
   le client qui s'interdit de lui parler. (Vérifier aussi côté serveur, par
   acquit de conscience : `systemctl status nfs-server` et `exportfs -v` sur
   `lab-ops` sont normaux.)

**Correctif**

Deux voies, selon qu'on peut ou non rétablir le chemin vers le serveur.

*Voie 1 — rétablir le réseau* (ici, c'est possible et c'est la bonne) :

```bash
sudo nft delete table inet lab11bf
ps -eo pid,stat,cmd | awk '$2 ~ /^D/'       # plus rien après quelques secondes
sudo dmesg | tail -1
# nfs: server 10.10.10.14 OK
```

Les processus bloqués **reprennent exactement où ils en étaient** : le
`factura-rapport` termine son écriture, le `ls` affiche sa liste. Aucune donnée
perdue : c'est ce que `hard` achète.

*Voie 2 — le serveur ne reviendra pas* (baie morte, machine décommissionnée) :

```bash
sudo umount -f -l /mnt/partage-ops
```

`-f` fait échouer les RPC en attente (le noyau renvoie `EIO` aux processus, qui
sortent enfin de `D`), `-l` détache le point de montage même s'il reste occupé.
Les écritures en vol sont perdues. Si le point est géré par un automount :
`sudo systemctl stop 'mnt-partage\x2dops.automount'` d'abord, sinon le prochain
accès le remonte.

**Remise en service et vérification**

```bash
ls /mnt/partage-ops
nfsstat -m | grep -A1 partage-ops
bash check_M11_08.sh
```

**Pourquoi `kill -9` était sans effet, et pourquoi on garde `hard`**

Un processus en `D` est dans le noyau, au milieu d'un appel système qui attend
une réponse. Les signaux ne sont traités qu'au retour vers l'espace utilisateur,
et ce retour n'arrive pas tant que la RPC n'a pas de réponse. `SIGKILL` est bien
**enregistré** (le processus mourra dès que la RPC se termine — le `wchan`
`rpc_wait_bit_killable` dit exactement cela : « tuable, entre deux RPC »), mais il
n'est pas **délivré** tant que le serveur se tait. Avec `soft`, la RPC aurait
échoué après `timeo × retrans` (60 s × 2 par défaut en TCP) et le processus aurait
reçu `EIO` : libre, mais avec un fichier à moitié écrit dont personne ne saura
jamais quelle moitié est arrivée. On garde `hard` parce qu'un blocage se voit et
se résout ; une corruption silencieuse ne se voit pas et ne se résout pas.

**Prévention**

* `x-systemd.automount` dans `fstab`, pour que le boot et les services qui
  n'utilisent pas le partage ne dépendent jamais du serveur NFS ;
* une sonde réseau sur `10.10.10.14:2049` (module 16), avant que les
  utilisateurs ne remontent le symptôme ;
* toute règle de pare-feu posée sur un client NFS s'accompagne d'un test de
  `nc -vz serveur 2049` — les règles « juste pour un test » qui restent sont la
  cause numéro un de ce ticket ;
* jamais de `soft` sur un partage en écriture ; `soft` se réserve aux montages
  en lecture seule dont la disparition est acceptable.

> [!NOTE]
> **Pourquoi**
>
> Le point délicat de cet incident est le **faux indice** : « le serveur répond au
> ping ». ICMP, le port 111 et le port 2049 sont trois chemins différents, et un
> pare-feu — local ou intermédiaire — peut n'en filtrer qu'un. Le diagnostic réseau
> d'un service ne se fait jamais au `ping`, mais sur **le port du service** :
> `nc -vz`, `ss -tn state established '( dport = :2049 )'` pour voir si la session
> TCP existe encore, et `nft list ruleset` / `iptables -S` sur le client **avant**
> d'aller accuser le serveur. La même logique vaut pour iSCSI (3260), PostgreSQL
> (5432) ou n'importe quel service : un `ping` qui passe ne prouve rien.

> [!WARNING]
> **Piège**
>
> `umount -l` seul (sans `-f`) sur un montage NFS mort ne libère **pas** les
> processus en `D` : il retire le point de montage de l'arborescence, mais les
> processus continuent d'attendre leurs RPC sur un système de fichiers devenu
> invisible. On se retrouve avec un montage fantôme (visible dans
> `/proc/self/mountinfo`, absent de `findmnt`) et des processus toujours bloqués.
> C'est `-f` qui fait échouer les RPC ; `-l` ne fait que détacher. Les deux
> ensemble, dans cet ordre.

---

## 11.8 Défi du module

<a id="d11"></a>**[D11](README.md#d11) — Un volume de sauvegarde redondant, chiffré et surveillé**

### 1 à 3 — la pile complète

```bash
# --- partitions de type RAID ------------------------------------------
sudo sgdisk -Z /dev/sdb && sudo sgdisk -n 1:0:0 -t 1:fd00 /dev/sdb
sudo sgdisk -Z /dev/sdc && sudo sgdisk -n 1:0:0 -t 1:fd00 /dev/sdc
sudo partprobe /dev/sdb /dev/sdc

# --- RAID1 ------------------------------------------------------------
sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdb1 /dev/sdc1
cat /proc/mdstat
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
sudo update-initramfs -u

# --- LVM par-dessus ---------------------------------------------------
sudo pvcreate /dev/md0
sudo vgcreate vg_sauv /dev/md0
sudo lvcreate -l 60%VG -n lv_coffre vg_sauv
# la base à sauvegarder vit désormais dans le même groupe :
sudo lvcreate -L 1G -n lv_pgdata vg_sauv
sudo mkfs.ext4 -L pgdata /dev/vg_sauv/lv_pgdata
sudo mount /dev/vg_sauv/lv_pgdata /mnt              # recopie du jeu de données
sudo cp -a /srv/factura/db/. /mnt/ && sudo umount /mnt
sudo mount /dev/vg_sauv/lv_pgdata /srv/factura/db    # + ligne fstab
sudo vgs                          # ~20 % libres, volontairement

# --- LUKS par-dessus --------------------------------------------------
sudo cryptsetup luksFormat --type luks2 /dev/vg_sauv/lv_coffre
sudo cryptsetup luksOpen /dev/vg_sauv/lv_coffre coffre
sudo cryptsetup luksHeaderBackup /dev/vg_sauv/lv_coffre \
  --header-backup-file /root/coffre-luks.hdr
sudo chmod 400 /root/coffre-luks.hdr

sudo mkfs.ext4 -L sauvegardes /dev/mapper/coffre
sudo mkdir -p /srv/sauvegardes
```

```bash
UUID_LUKS=$(sudo cryptsetup luksUUID /dev/vg_sauv/lv_coffre)
echo "coffre  UUID=$UUID_LUKS  none  luks,x-systemd.device-timeout=30" \
  | sudo tee -a /etc/crypttab
echo "/dev/mapper/coffre  /srv/sauvegardes  ext4 \
  defaults,nodev,nosuid,noexec,nofail  0  0" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /srv/sauvegardes
```

**Pourquoi laisser du libre dans le VG** (les 40 % hors `lv_coffre`, dont 20 % restent non alloués une fois `lv_pgdata` posé) : c'est la réserve qui permet (a) de créer les
snapshots de sauvegarde, (b) de laisser l'auto-extension de `lvm.conf` faire son
travail quand un snapshot approche du seuil, (c) d'étendre `lv_coffre` le jour où il
se remplit, sans commander de matériel. Un VG alloué à 100 % est un VG où l'on a perdu
toute capacité de manœuvre.

### 4 — script de sauvegarde

```bash
#!/usr/bin/env bash
# /opt/factura/bin/sauvegarde.sh — sauvegarde cohérente par snapshot LVM
set -euo pipefail

VG=vg_sauv
LV=lv_pgdata
SNAP=snap_sauv
MNT=/mnt/snap-sauvegarde
DEST=/srv/sauvegardes
RETENTION=7
JOURNAL=/var/log/factura/sauvegarde.log

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$JOURNAL" >&2; }

[ "$(id -u)" -eq 0 ] || { log "ERREUR : root requis"; exit 1; }
mkdir -p "$(dirname "$JOURNAL")" "$MNT" "$DEST"

# --- 1. refus si un snapshot du même nom traîne déjà -------------------
if lvs "$VG/$SNAP" >/dev/null 2>&1; then
  log "ERREUR : $VG/$SNAP existe déjà (en cours, ou échec précédent)"
  exit 1
fi

# --- 2. refus si le VG n'a pas la place pour le snapshot ---------------
export LC_ALL=C          # tailles LVM avec un point décimal, pas une virgule
TAILLE_LV_K=$(lvs --noheadings --units k --nosuffix -o lv_size "$VG/$LV" \
  | tr -d ' ')
BESOIN_K=$(awk -v t="$TAILLE_LV_K" 'BEGIN{printf "%d", t*0.10}')
LIBRE_K=$(vgs --noheadings --units k --nosuffix -o vg_free "$VG" | tr -d ' ')
if awk -v b="$BESOIN_K" -v l="$LIBRE_K" 'BEGIN{exit !(b>l)}'; then
  log "ERREUR : besoin ${BESOIN_K}K, ${LIBRE_K}K libres dans $VG"
  exit 1
fi

# --- 3. nettoyage garanti ---------------------------------------------
nettoyer() {
  local c=$?
  mountpoint -q "$MNT" && umount "$MNT" || true
  lvs "$VG/$SNAP" >/dev/null 2>&1 && lvremove -y "$VG/$SNAP" >/dev/null || true
  [ "$c" -ne 0 ] && log "sortie en erreur (code $c), nettoyage effectué"
  return "$c"
}
trap nettoyer EXIT

# --- 4. snapshot, archivage -------------------------------------------
log "création du snapshot ($((BESOIN_K/1024)) Mio)"
lvcreate -s -L "${BESOIN_K}k" -n "$SNAP" "/dev/$VG/$LV" >/dev/null
mount -o ro "/dev/$VG/$SNAP" "$MNT"

ARCHIVE="$DEST/factura-db-$(date +%F).tar.gz"
log "archivage vers $ARCHIVE"
tar czf "$ARCHIVE" -C "$MNT" .
log "archive terminée : $(du -h "$ARCHIVE" | cut -f1)"

# --- 5. rétention ------------------------------------------------------
mapfile -t VIEILLES < <(ls -1t "$DEST"/factura-db-*.tar.gz 2>/dev/null \
  | tail -n +$((RETENTION+1)))
for f in "${VIEILLES[@]:-}"; do
  [ -n "$f" ] || continue
  log "suppression (rétention $RETENTION) : $f"
  rm -f -- "$f"
done

log "succès"
```

### 5 — script de supervision

```bash
#!/usr/bin/env bash
# /opt/factura/bin/verif-stockage.sh — 0 si tout va bien, 1 sinon
set -uo pipefail
ALERTES=0
ko() { printf '[ALERTE] %s\n' "$1"; ALERTES=$((ALERTES+1)); }
ok() { printf '[  ok  ] %s\n' "$1"; }

# --- 1. RAID dégradé ---------------------------------------------------
if [ -f /proc/mdstat ] && grep -q '^md' /proc/mdstat; then
  if grep -qE '\[[U_]*_[U_]*\]' /proc/mdstat; then
    ko "RAID dégradé : $(grep -E '\[[U_]+\]' /proc/mdstat | tr -s ' ')"
  else
    ok "tableaux mdadm sains"
  fi
fi

# --- 2. remplissage espace ET inodes ----------------------------------
while read -r src pct ipct cible; do
  [ "${pct%\%}" -ge 85 ] 2>/dev/null && ko "$cible : ${pct} d'espace ($src)"
  [ "${ipct%\%}" -ge 85 ] 2>/dev/null && ko "$cible : ${ipct} d'inodes ($src)"
done < <(df --output=source,pcent,ipcent,target -x tmpfs -x devtmpfs \
           -x squashfs 2>/dev/null | tail -n +2)

# --- 3. snapshots vieux ou pleins -------------------------------------
if command -v lvs >/dev/null 2>&1; then
  while read -r nom pct jour heure tz; do
    [ -z "${nom:-}" ] && continue
    awk -v p="$pct" 'BEGIN{exit !(p>70)}' && ko "snapshot $nom à ${pct} %"
    AGE=$(( ( $(date +%s) - $(date -d "$jour $heure $tz" +%s) ) / 3600 ))
    [ "$AGE" -gt 24 ] && ko "snapshot $nom créé il y a ${AGE} h (limite 24 h)"
  done < <(LC_ALL=C lvs --noheadings -o lv_name,data_percent,lv_time \
             -S 'origin!=""' 2>/dev/null)
fi

# --- 4. VG sous les 10 % de libre --------------------------------------
if command -v vgs >/dev/null 2>&1; then
  while read -r vg taille libre; do
    [ -z "${vg:-}" ] && continue
    awk -v l="$libre" -v t="$taille" 'BEGIN{exit !(t>0 && l/t*100<10)}' \
      && ko "VG $vg : moins de 10 % libres"
  done < <(vgs --noheadings --units b --nosuffix \
             -o vg_name,vg_size,vg_free 2>/dev/null)
fi

# --- 5. cohérence de fstab ---------------------------------------------
if ! findmnt --verify >/dev/null 2>&1; then
  ko "findmnt --verify signale une anomalie dans /etc/fstab"
else
  ok "/etc/fstab cohérent"
fi

echo "---"
[ "$ALERTES" -eq 0 ] && { echo "Aucune alerte."; exit 0; }
echo "$ALERTES alerte(s)."
exit 1
```

### 6 — unités systemd

```ini
# /etc/systemd/system/factura-sauvegarde.service
[Unit]
Description=Sauvegarde cohérente de factura-db par snapshot LVM
After=srv-sauvegardes.mount
Requires=srv-sauvegardes.mount

[Service]
Type=oneshot
ExecStart=/opt/factura/bin/sauvegarde.sh
```

```ini
# /etc/systemd/system/factura-sauvegarde.timer
[Unit]
Description=Sauvegarde factura-db chaque nuit a 02h30

[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
```

```ini
# /etc/systemd/system/verif-stockage.service
[Unit]
Description=Supervision du stockage factura

[Service]
Type=oneshot
ExecStart=/opt/factura/bin/verif-stockage.sh


# /etc/systemd/system/verif-stockage.timer
[Unit]
Description=Supervision du stockage toutes les 15 minutes
[Timer]
OnBootSec=5min
OnUnitActiveSec=15min
[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now factura-sauvegarde.timer verif-stockage.timer
systemctl list-timers --all | grep -E 'factura|verif'
```

### 7 — test de panne

```bash
sudo mdadm /dev/md0 --fail /dev/sdc1
cat /proc/mdstat
```

```console
md0 : active raid1 sdb1[0] sdc1[1](F)
      5237760 blocks super 1.2 [2/1] [U_]
```

`[2/1]` : deux membres attendus, un seul opérationnel. `[U_]` : le second est tombé.
`/srv/sauvegardes` reste parfaitement accessible — c'est tout l'intérêt du miroir.

```bash
sudo /opt/factura/bin/verif-stockage.sh
# [ALERTE] RAID dégradé : md0 : active raid1 sdb1[0] sdc1[1](F)

sudo mdadm /dev/md0 --remove /dev/sdc1
sudo mdadm /dev/md0 --add /dev/sdc1
watch -n 2 cat /proc/mdstat
```

```console
md0 : active raid1 sdc1[2] sdb1[0]
      5237760 blocks super 1.2 [2/1] [U_]
      [=========>...........]  recovery = 47.3% (2478912/5237760)
      finish=0.3min speed=137717K/sec
```

### 8 — le rapport

```text
/dev/sdb1 ─┐
           ├─ /dev/md0 (RAID1) ─ PV ─ VG vg_sauv ─┬─ LV lv_coffre
/dev/sdc1 ─┘                                      │      │
                                                  │      └─ LUKS2
                                                  │          │
                                                  │          └─ ext4
                                                  │              │
                                                  │              ▼
                                                  │     /srv/sauvegardes
                                                  ├─ LV lv_pgdata ─ ext4
                                                  │     ─ /srv/factura/db
                                                  └─ ~20 % libres (snapshots)
```

**Pourquoi LUKS au-dessus de LVM et pas en dessous** — la réponse argumentée attendue :

| | LUKS **au-dessus** (ici) | LUKS **en dessous** |
|---|---|---|
| Granularité | on chiffre le LV qui le mérite | tout le VG, indistinctement |
| `lvextend` | fonctionne, + `cryptsetup resize` | fonctionne directement |
| Phrases de passe | une par volume sensible | une seule pour tout |
| Coût CPU | seulement sur le volume chiffré | sur toutes les E/S du groupe |

Au-dessus de LVM, on chiffre uniquement le volume de sauvegarde ; les autres LV du
groupe (données applicatives non sensibles, journaux) restent en clair et ne paient
ni le CPU ni la contrainte de déverrouillage au démarrage. On peut aussi révoquer une
clé sur un volume sans toucher aux autres.

En dessous de LVM (LUKS sur `/dev/md0`, puis PV sur `/dev/mapper/md0_crypt`), tout le
groupe est chiffré avec une seule clé : c'est le schéma de l'installeur Ubuntu pour un
poste de travail, où l'on veut que le disque entier soit illisible. Sur un serveur avec
des volumes de sensibilités différentes, c'est trop grossier.

> [!NOTE]
> **Pourquoi**
>
> L'ordre RAID → LVM → LUKS n'est pas arbitraire non plus, et c'est la question
> subsidiaire du défi. Le RAID est en bas parce qu'il doit voir les **disques
> physiques** : c'est lui qui détecte qu'un disque ne répond plus, et il ne peut le
> faire que s'il leur parle directement. Mettre LVM en dessous du RAID (un RAID1 sur
> deux LV) fonctionne techniquement mais rend la panne de disque illisible : mdadm
> verrait deux volumes logiques tomber en même temps sans savoir pourquoi.
>
> LUKS en haut parce que le chiffrement doit être le plus près possible des données :
> tout ce qui est en dessous de lui est chiffré, donc protégé si un disque part en
> garantie ou à la benne. Et parce qu'un `pvmove` ou un remplacement de disque se fait
> alors **sans jamais déverrouiller quoi que ce soit** : les blocs chiffrés sont copiés
> tels quels.
>
> La contrainte à assumer : avec LUKS dans la chaîne, aucun redémarrage automatique
> n'est possible sans intervention humaine ou sans TPM. C'est une décision
> d'architecture, à documenter dans le rapport, pas un détail technique.

> [!WARNING]
> **Piège**
>
> Le piège numéro un du défi est l'oubli d'`update-initramfs -u` après avoir écrit
> `mdadm.conf` : tout fonctionne parfaitement jusqu'au redémarrage suivant, où
> `/dev/md0` devient `/dev/md127`, le PV n'est plus trouvé, le VG n'est pas activé,
> `/dev/mapper/coffre` n'existe pas, et le montage échoue. Quatre couches en cascade
> depuis une seule commande oubliée — et deux semaines plus tard, personne ne fait le
> lien.
>
> Piège numéro deux : tester le script de sauvegarde une seule fois. Il faut le lancer
> **deux fois de suite**, et une troisième en l'interrompant par `Ctrl-C` au milieu du
> `tar`. Un `trap` qui ne nettoie pas correctement ne se voit qu'à la troisième
> exécution — celle qui échoue avec « le snapshot existe déjà », en pleine nuit, sans
> personne pour la relancer.

<!-- nav:début -->
---

[← Module 10](../10-paquets/corrige.md) · [Énoncé](README.md) · [Module 12 →](../12-reseau/corrige.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
