# Module 10 — Stockage, partitions et LVM

## 10.0 Objectifs et compétences

::: objectif
À la fin de ce module, je sais :

* nommer et identifier un périphérique bloc (`sda`, `nvme0n1`, `vda`, `dm-0`) avec
  `lsblk`, `blkid` et `/dev/disk/by-*`, et expliquer pourquoi on monte par UUID
  et jamais par `/dev/sdX` ;
* choisir entre MBR et GPT, partitionner avec `fdisk`, `parted` ou `sgdisk`, poser
  le bon type de partition et faire relire la table au noyau sans redémarrer ;
* choisir entre ext4, XFS, btrfs et tmpfs sur des critères techniques, formater
  avec les bonnes options, et savoir quoi faire quand un `fsck` se déclenche ;
* écrire une ligne d'`/etc/fstab` champ par champ, justifier chaque option
  (`noatime`, `nodev`, `nosuid`, `noexec`, `ro`, `nofail`, `x-systemd.automount`),
  et **vérifier avant de redémarrer** ;
* diagnostiquer un `target is busy` avec `fuser -vm` et `lsof`, et choisir entre
  démontage normal, paresseux et forcé ;
* construire une pile LVM complète (PV → VG → LV), l'étendre **à chaud**, déplacer
  des extents avec `pvmove`, réduire un volume sans le détruire ;
* prendre un snapshot LVM pour une sauvegarde cohérente, le monter, le fusionner,
  et expliquer ce qui se passe exactement quand il déborde ;
* faire croître un disque de VM Proxmox de bout en bout :
  `growpart` → `pvresize` → `lvextend` → `resize2fs`, sans interruption de service ;
* monter un RAID1 logiciel avec `mdadm`, le surveiller, et chiffrer un volume avec
  LUKS + `/etc/crypttab` ;
* monter un partage NFS proprement (`_netdev`, `hard`, `nfsvers`) et lire un
  `iostat -xz` pour dire si le stockage est le goulot d'étranglement.

Temps estimé : 8 h (le module est long, il se découpe bien en deux séances)
Prérequis : module 02 (FHS, inodes, `du`/`df`), module 03 (permissions),
module 08 (unités systemd). `du` et `df` ne sont pas réexpliqués ici.
:::

---

## 10.1 Mise en place

VM concernée : **`lab-db` (10.10.10.12)**, VMID **9003**. Elle possède deux disques
supplémentaires **vierges** de 5 Go : `/dev/sdb` et `/dev/sdc`. C'est le terrain de
jeu du module. Le disque système reste `/dev/sda`, on n'y touche qu'au lab L10.4.

Le lab L10.5 et le défi utilisent aussi `lab-adm` (10.10.10.10) comme serveur NFS.

::: attention
Ce module écrit dans des tables de partitions et formate des volumes. Une faute de
frappe sur le nom du disque détruit le système. **Snapshot obligatoire avant de
commencer**, et un nouveau snapshot avant chaque Break & Fix :

```bash
# depuis le shell Proxmox
qm snapshot 9003 avant-lab10
```

Pour repartir propre : `qm rollback 9003 snap-clean`.
Règle de survie : avant chaque commande destructrice, relis le nom du périphérique
à voix haute et compare-le avec la sortie de `lsblk`.
:::

Paquets nécessaires sur `lab-db` :

```bash
sudo apt update
sudo apt install -y lvm2 xfsprogs btrfs-progs mdadm cryptsetup-bin \
  gdisk parted nfs-common sysstat fio cloud-guest-utils quota
```

::: rhel
Sous Rocky 9 : `sudo dnf install -y lvm2 xfsprogs mdadm cryptsetup gdisk parted
nfs-utils sysstat fio cloud-utils-growpart quota`. `btrfs-progs` n'est pas fourni
par Rocky 9 (Red Hat a retiré btrfs de RHEL) : la section btrfs se lit, ne se
pratique pas. Sous Rocky, le système est déjà sur LVM par défaut et le VG s'appelle
`rl` — adapte les noms dans les labs.
:::

Préparation du terrain (idempotent, relançable) :

```bash
sudo bash ~/workbook/scripts/setup/setup_M10.sh
```

Il crée l'arborescence `/srv/factura`, un jeu de données à migrer, les scripts
d'écriture utilisés pour les tests de cohérence, et **il vérifie que `/dev/sdb` et
`/dev/sdc` existent**. S'ils sont absents (VM créée sans disques supplémentaires,
conteneur, machine de test), il fabrique deux images de 5 Go attachées en
*loop device* et te le dit clairement : tu travailleras alors sur `/dev/loopN`
et non sur `/dev/sdb`. Toutes les commandes du module restent identiques, seul
le nom du périphérique change. Le couple retenu est écrit dans `/etc/lab10.env` :

```bash
. /etc/lab10.env      # définit DISQUE1 et DISQUE2
echo "$DISQUE1 $DISQUE2"
```

Sur `lab-adm`, pour le lab L10.5 (NFS) :

```bash
sudo bash ~/workbook/scripts/setup/setup_M10.sh --nfs
```

---

## 10.2 Rappel express

### Nommer un disque

| Nom | Origine |
|---|---|
| `sda`, `sdb` | pilote SCSI/SATA/USB — l'ordre dépend de l'ordre de détection |
| `nvme0n1`, `nvme0n1p2` | NVMe : contrôleur 0, namespace 1, partition 2 |
| `vda`, `xvda` | virtio (KVM/Proxmox), Xen |
| `dm-0`, `/dev/mapper/vg-lv` | device-mapper : LVM, LUKS, multipath |
| `md0` | RAID logiciel mdadm |

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,UUID
blkid /dev/sdb1                 # UUID + TYPE, lit la superblock
ls -l /dev/disk/by-uuid/        # liens symboliques maintenus par udev
ls -l /dev/disk/by-id/          # nom stable incluant le numéro de série
lsblk -f                        # vue synthétique la plus utile au quotidien
```

**Pourquoi jamais `/dev/sdX` dans `fstab`** : `sdb` n'est pas une propriété du
disque, c'est un **ordre d'énumération** attribué au démarrage. Un disque ajouté,
un port changé, un contrôleur plus rapide à répondre, et `sdb` devient `sdc`. Le
système monte alors le mauvais volume, ou refuse de booter. L'UUID est écrit
**dans le système de fichiers** par `mkfs` : il suit le volume partout.

| Identifiant | Écrit où | Survit à |
|---|---|---|
| `UUID=` | superblock du FS | déplacement, changement de contrôleur |
| `PARTUUID=` | table GPT | reformatage du FS |
| `LABEL=` | superblock du FS | tout, mais se duplique facilement |
| `/dev/mapper/vg-lv` | métadonnées LVM | tout — stable par construction |

### Partitionner

| MBR (msdos) | GPT |
|---|---|
| 4 primaires max (+ étendue) | 128 partitions par défaut |
| 2 Tio maximum | 8 Zio |
| une seule copie de la table | copie primaire + copie de secours en fin de disque |
| type sur 1 octet (`83`, `8e`) | type sur un GUID (`8300`, `8e00`) |

```bash
sudo parted -s /dev/sdb mklabel gpt
sudo parted -s -a optimal /dev/sdb mkpart primaire 1MiB 100%
sudo parted -s /dev/sdb set 1 lvm on
sudo sgdisk -n 1:0:0 -t 1:8e00 -c 1:donnees /dev/sdc   # équivalent, scriptable
sudo partprobe /dev/sdb            # fait relire la table au noyau
lsblk /dev/sdb
```

Types utiles : `8300` Linux, `8e00` LVM, `8200` swap, `8309` LUKS, `fd00` RAID.
**Alignement** : commencer à 1 MiB (2048 secteurs) aligne sur toutes les tailles
d'effacement SSD et de bandes RAID courantes. `parted -a optimal` et les `fdisk`
récents le font seuls ; un vieux script qui démarre au secteur 63 divise les
performances d'écriture par deux.

### Systèmes de fichiers

| FS | Agrandir | Réduire | Points forts |
|---|---|---|---|
| ext4 | à chaud | oui, hors ligne | mûr, outillé, réparable |
| XFS | à chaud | **impossible** | gros fichiers, parallélisme |
| btrfs | à chaud | oui | snapshots, CoW, sommes de contrôle |
| tmpfs | `remount,size=` | `remount,size=` | en RAM, plafond, jamais sur disque |

```bash
sudo mkfs.ext4 -L donnees -m 1 /dev/sdb1     # -m 1 : 1 % réservé au lieu de 5
sudo mkfs.xfs -L pgdata /dev/sdc1
sudo tune2fs -l /dev/sdb1 | head -30         # tout sur un ext4
sudo xfs_info /srv/factura/db                # XFS : sur le POINT DE MONTAGE
sudo tune2fs -m 1 -c -1 -i 0 /dev/sdb1       # réserve, compteur, intervalle
sudo e2fsck -f /dev/sdb1                     # jamais sur un FS monté en rw
sudo xfs_repair /dev/sdc1                    # idem, démonté obligatoirement
```

Un `fsck` ext4 se déclenche : au montage d'un FS marqué *sale* (arrêt brutal), au
dépassement du compteur de montages (`-c`), de l'intervalle (`-i`), ou sur
`fsck.mode=force` en ligne de commande noyau. Ubuntu désactive compteur et
intervalle par défaut. XFS ne fait pas de fsck périodique : il rejoue son journal
au montage, `xfs_repair` est un outil de dernier recours.

### Monter

```bash
sudo mount -o noatime /dev/sdb1 /srv/factura/db
sudo mount -o remount,ro /srv/factura/db
sudo umount /srv/factura/db
findmnt /srv/factura/db          # ce qui est VRAIMENT monté, et comment
```

| Option | Effet |
|---|---|
| `defaults` | `rw,suid,dev,exec,auto,nouser,async` |
| `noatime` / `relatime` | n'écrit plus / écrit peu les dates d'accès |
| `nodev,nosuid,noexec` | durcissement : pas de périphérique, pas de setuid, pas d'exécutable |
| `ro` | lecture seule |
| `nofail` | ne bloque pas le boot si le volume manque |
| `x-systemd.automount` | monte à la première utilisation, pas au boot |
| `_netdev` | attend le réseau (NFS, iSCSI) |
| `discard` | TRIM synchrone — préférer le timer `fstrim.timer` |

Ligne de `/etc/fstab`, six champs :

```text
UUID=8f3c-...  /srv/factura/db  ext4  defaults,noatime  0  2
     1              2            3          4           5  6
1 source  2 point de montage  3 type  4 options
5 dump (toujours 0)  6 ordre de fsck : 1 pour /, 2 pour les autres, 0 = jamais
```

::: astuce
**Avant** de redémarrer après avoir édité `fstab` :

```bash
findmnt --verify --verbose     # analyse la syntaxe et l'existence des sources
sudo mount -a                  # monte tout ce qui manque, échoue bruyamment
sudo systemctl daemon-reload   # systemd régénère les unités .mount
```

Trois commandes, dix secondes, et tu ne passes pas ta soirée en console Proxmox.
:::

`target is busy` au démontage :

```bash
sudo fuser -vm /srv/factura/db     # qui utilise ce point de montage
sudo lsof /srv/factura/db          # quels fichiers exactement
sudo fuser -km /srv/factura/db     # tue les coupables (brutal)
sudo umount -l /srv/factura/db     # démontage paresseux : détache maintenant,
                                   # libère quand le dernier fd se ferme
```

### LVM

```text
/dev/sdb1  /dev/sdc1        <- PV  (Physical Volume)
        \      /
         vg_data            <- VG  (Volume Group), pool d'extents (PE, 4 Mio)
        /      \
  lv_pgdata   lv_sauv       <- LV  (Logical Volume) -> /dev/vg_data/lv_pgdata
```

```bash
sudo pvcreate /dev/sdb1 /dev/sdc1
sudo vgcreate vg_data /dev/sdb1
sudo lvcreate -L 3G -n lv_pgdata vg_data
sudo lvcreate -l 100%FREE -n lv_sauv vg_data
sudo vgextend vg_data /dev/sdc1            # ajoute un disque au groupe
sudo lvextend -L +2G -r /dev/vg_data/lv_pgdata   # -r redimensionne le FS aussi
sudo pvmove /dev/sdb1                      # vide un PV, à chaud
sudo vgreduce vg_data /dev/sdb1 && sudo pvremove /dev/sdb1
pvs ; vgs ; lvs ; lvs -o +devices ; lvdisplay /dev/vg_data/lv_pgdata
```

`-L` parle en taille (`-L 3G`, `-L +2G`), `-l` parle en **extents** ou en
pourcentage (`-l 100%FREE`, `-l +50%FREE`, `-l 512`). Piège classique :
`-l 100%FREE` à l'extension signifie « fais que le LV pèse 100 % du libre »,
`-l +100%FREE` signifie « ajoute tout le libre ». Le premier échoue presque
toujours.

::: attention
**Réduire** un LV est la seule opération LVM réellement dangereuse : si tu réduis
le volume avant le système de fichiers, tu coupes la fin des données. Ordre
obligatoire : démonter → `e2fsck -f` → `resize2fs` à la taille cible →
`lvreduce` à la même taille. XFS ne se réduit pas du tout : il faut sauvegarder,
recréer, restaurer.
:::

### Snapshots LVM

```bash
sudo lvcreate -s -L 1G -n snap_pg /dev/vg_data/lv_pgdata
sudo mount -o ro /dev/vg_data/snap_pg /mnt/snap       # XFS : ajouter -o nouuid
sudo lvconvert --merge /dev/vg_data/snap_pg           # restaure l'origine
sudo lvremove /dev/vg_data/snap_pg
lvs -o lv_name,attr,size,origin,data_percent
```

Un snapshot est un volume de **copie sur écriture** : il ne contient que les blocs
de l'origine modifiés depuis sa création. Sa taille dimensionne le **volume de
changement** qu'il peut absorber, pas les données. S'il se remplit, il devient
**invalide** (attribut `swi-I-s---`) et ne sert plus à rien — l'origine, elle,
n'est pas affectée.

### RAID logiciel, thin, swap

```bash
sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdb1 /dev/sdc1
cat /proc/mdstat                     # [UU] = sain, [U_] = un disque perdu
sudo mdadm --detail /dev/md0
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
sudo update-initramfs -u             # sinon le RAID n'est pas assemblé au boot
```

```bash
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
swapon --show ; free -h ; cat /proc/sys/vm/swappiness
```

### Performance

```bash
iostat -xz 2                # %util, r_await/w_await, aqu-sz, r/s + w/s = IOPS
sudo dd if=/dev/zero of=/srv/t bs=1M count=1024 oflag=direct conv=fdatasync
sudo fio --name=rr --filename=/srv/t.fio --size=1G --bs=4k --rw=randread \
  --ioengine=libaio --direct=1 --iodepth=32 --runtime=30 --time_based
```

`%util` à 100 % ne veut **pas** dire saturé sur un SSD ou un NVMe : la métrique
date des disques à une seule tête. Ce qui compte, c'est `await` (latence de
service, en ms) rapproché des IOPS.

---

## 10.3 Quiz — QCM

**Q10.1** — Tu remplaces une carte contrôleur sur un serveur physique. Au
redémarrage, `/dev/sdb` et `/dev/sdc` ont échangé leurs rôles. Quelles lignes de
`fstab` continuent de monter le bon volume ? **Deux réponses correctes.**

a) `/dev/sdb1 /srv/data ext4 defaults 0 2`
b) `UUID=3f1c-... /srv/data ext4 defaults 0 2`
c) `/dev/vg_data/lv_sauv /srv/sauv ext4 defaults 0 2`
d) `/dev/disk/by-path/pci-0000:00:10.0-scsi-0:0:1:0-part1 /srv/data ext4 defaults 0 2`

**Q10.2** — `lsblk -f` affiche sur `lab-db` :

```console
NAME        FSTYPE      LABEL   UUID                                 MOUNTPOINTS
sdb
└─sdb1      LVM2_member         kXd9Fe-...
  └─vg_data-lv_pgdata
            ext4        pgdata  8f3c1a2b-...            /srv/factura/db
```

Quel identifiant mets-tu dans `fstab` pour ce montage ?

a) `UUID=kXd9Fe-...`
b) `UUID=8f3c1a2b-...`
c) `/dev/sdb1`
d) `PARTUUID=8f3c1a2b-...`

**Q10.3** — Tu dois partitionner un disque de 4 Tio pour y stocker une seule
grosse partition de données. Quelle table de partitions ?

a) MBR, c'est plus compatible
b) GPT, car MBR plafonne à 2 Tio par partition et par disque
c) peu importe, le noyau Linux gère 4 Tio dans les deux cas
d) aucune : au-delà de 2 Tio il faut obligatoirement LVM

**Q10.4** — Après `sudo sgdisk -n 1:0:0 -t 1:8e00 /dev/sdb`, la commande
`sudo pvcreate /dev/sdb1` répond `Device /dev/sdb1 not found`. Que fais-tu ?

a) tu recrées la partition, elle a échoué
b) `sudo partprobe /dev/sdb` pour faire relire la table au noyau
c) tu redémarres la machine
d) tu utilises `/dev/sdb` directement, le PV n'a pas besoin de partition

**Q10.5** — Tu veux réduire de 500 Go un système de fichiers XFS monté sur un LV.
Quelle est la procédure ?

a) `umount`, `xfs_growfs -D`, puis `lvreduce`
b) `lvreduce -r -L -500G`, XFS gère
c) il n'y en a pas : XFS ne se réduit pas, il faut sauvegarder, recréer, restaurer
d) `xfs_repair -s` puis `lvreduce`

**Q10.6** — Dans `/etc/fstab`, quel est le rôle du **sixième** champ ?

a) l'ordre de sauvegarde par `dump`
b) l'ordre de passage de `fsck` au démarrage : 1 pour la racine, 2 pour les autres, 0 = jamais
c) le nombre de tentatives de montage
d) les droits Unix du point de montage

**Q10.7** — Tu ajoutes un volume de sauvegarde monté sur un NAS dans `fstab`.
Le NAS est parfois éteint. Quelles options mets-tu pour que la VM démarre quand
même ? **Deux réponses correctes.**

a) `nofail`
b) `noauto` seul
c) `x-systemd.automount`
d) `ro`

**Q10.8** — `sudo umount /srv/factura/db` répond `target is busy`. Quelle
commande t'indique **qui** bloque ?

a) `df -h /srv/factura/db`
b) `sudo fuser -vm /srv/factura/db`
c) `sudo umount -f /srv/factura/db`
d) `mount | grep factura`

**Q10.9** — Tu exécutes `sudo lvextend -l +100%FREE /dev/vg_data/lv_pgdata` puis
`df -h /srv/factura/db` : la taille affichée n'a pas bougé. Pourquoi ?

a) `lvextend` a échoué silencieusement
b) le LV est plus grand, mais le système de fichiers ne l'est pas encore : il manque `resize2fs` (ou `-r`)
c) il faut démonter et remonter le volume
d) `df` met jusqu'à 5 minutes à se rafraîchir

**Q10.10** — Un snapshot LVM de 1 Go a été créé sur un LV de 20 Go il y a trois
jours. `lvs` affiche pour lui l'attribut `swi-I-s---`. Que s'est-il passé et quel
est l'impact ?

a) le snapshot est en cours de fusion, il faut attendre
b) le snapshot a débordé, il est invalide et inutilisable ; l'origine n'a rien
c) le snapshot a débordé et l'origine est corrompue
d) le snapshot est simplement inactif, `lvchange -ay` suffit

**Q10.11** — Sur `lab-db`, `df -h /srv/factura/db` affiche 42 % d'utilisation, mais
toute écriture échoue avec `No space left on device`. Quelle est la cause la plus
probable ?

a) le volume est monté en lecture seule
b) les inodes sont épuisés (`df -i`)
c) un processus détient un fichier supprimé
d) le quota de l'utilisateur est atteint

**Q10.12** — Tu agrandis le disque `scsi0` d'une VM de 30 à 60 Go dans l'interface
Proxmox. Dans la VM, `lsblk` montre bien `sda` à 60 Go mais `/` fait toujours 28 Go.
Quelle séquence complète le travail, dans l'ordre ?

a) `resize2fs` → `lvextend` → `pvresize` → `growpart`
b) `growpart /dev/sda 3` → `pvresize /dev/sda3` → `lvextend -l +100%FREE` → `resize2fs`
c) `partprobe` → `resize2fs` → `lvextend`
d) rien à faire, `systemd-growfs` s'en charge au prochain boot

**Q10.13** — Après avoir créé un RAID1 avec `mdadm --create`, tu redémarres et le
tableau n'est plus assemblé : `/dev/md0` a disparu ou s'appelle `/dev/md127`.
Qu'a-t-on oublié ? **Deux réponses correctes.**

a) d'écrire la configuration dans `/etc/mdadm/mdadm.conf`
b) de lancer `sudo update-initramfs -u`
c) de formater le tableau en ext4
d) de marquer les partitions membres en type `fd00`

**Q10.14** — `iostat -xz 2` donne, sur un SSD NVMe :

```console
Device  r/s     w/s    rkB/s    wkB/s  r_await  w_await  aqu-sz  %util
nvme0n1 8200.0  310.0  32800.0  1240.0    0.28     0.41   2.45   99.80
```

Que conclus-tu ?

a) le disque est saturé, il faut le remplacer
b) `%util` proche de 100 % n'a pas de sens sur un NVMe multi-files ; `await` sous 0,5 ms indique un disque très à l'aise
c) `aqu-sz` à 2,45 prouve une file d'attente critique
d) les 8200 lectures/s dépassent la capacité d'un NVMe

**Q10.15** — Tu crées un fichier de swap avec `dd`, `mkswap` et `swapon` : tout
fonctionne. Après un redémarrage, `swapon --show` ne renvoie rien. Pourquoi ?

a) `mkswap` doit être relancé à chaque boot
b) il manque la ligne dans `/etc/fstab` (`/swapfile none swap sw 0 0`)
c) `vm.swappiness` est à 0
d) un fichier de swap ne survit jamais à un redémarrage, il faut une partition

**Q10.16** — Dans `/etc/crypttab`, à quoi sert le troisième champ quand il vaut
`none` ?

a) le volume n'est pas chiffré
b) aucune clé n'est fournie : la phrase de passe sera demandée interactivement au démarrage
c) le volume est déverrouillé sans authentification
d) c'est le nom du fichier de configuration LUKS

**Q10.17** — Tu montes un partage NFS dans `fstab` sans l'option `_netdev`.
Quel symptôme t'attends-tu à voir ?

a) le partage est monté en lecture seule
b) le montage échoue au démarrage parce que le réseau n'est pas encore prêt, et le boot part en mode maintenance
c) les droits Unix ne sont pas respectés
d) aucun, `_netdev` est cosmétique

**Q10.18** — Un LV `lv_sauv` doit accueillir des millions de petits fichiers. Au
formatage, quelle option ext4 te préserve d'une pénurie d'inodes ?

a) `mkfs.ext4 -m 0`
b) `mkfs.ext4 -T largefile`
c) `mkfs.ext4 -i 8192` (ou `-N <nombre>`)
d) `mkfs.ext4 -O ^has_journal`

---

## 10.4 Quiz — questions ouvertes

**QO10.1** — *On te demande en entretien* : « Explique-moi la chaîne complète entre
un disque physique neuf et un répertoire utilisable par une application, en
nommant chaque couche et l'outil qui la crée. » Réponds en listant les couches dans
l'ordre, et indique à chacune ce qu'on gagne et ce qu'on perd à la sauter.

::: repondre
lignes: 12
:::

**QO10.2** — Explique **précisément** pourquoi on ne met jamais `/dev/sdb1` dans
`/etc/fstab`, en décrivant le mécanisme d'attribution des noms `sdX` par le noyau.
Puis compare `UUID=`, `PARTUUID=` et `LABEL=` : dans quel cas chacun est le bon
choix, et lequel choisirais-tu pour une partition de swap non formatée ?

::: repondre
lignes: 10
:::

**QO10.3** — Un snapshot LVM de 2 Go sur un LV de 200 Go. Décris ce qui se passe
**bloc par bloc** quand une application écrit sur l'origine après la création du
snapshot. Déduis-en comment on dimensionne un snapshot, et ce qui arrive quand il
déborde — pour le snapshot et pour l'origine.

::: repondre
lignes: 10
:::

**QO10.4** — *On te demande en entretien* : « Le `/var` d'un serveur de production
est plein. Tu as un disque libre. Raconte-moi comment tu ajoutes 100 Go **sans
arrêter le service**, et dis-moi à quel moment exactement il y aurait eu une
coupure si le système n'avait pas été sur LVM. »

::: repondre
lignes: 10
:::

**QO10.5** — Compare ext4 et XFS sur cinq critères techniques concrets
(agrandissement, réduction, comportement sur gros fichiers, réparation, coût
d'un `fsck`). Pour chacun des trois cas suivants, dis lequel tu choisis et
pourquoi : un volume de logs, un datastore PostgreSQL de 4 To, une partition `/`
de 20 Go sur une VM.

::: repondre
lignes: 10
:::

**QO10.6** — Tu tapes `sudo umount /srv/sauvegardes` et tu obtiens `target is busy`.
Décris ta démarche de diagnostic complète, dans l'ordre, avec les commandes. Puis
explique la différence de mécanisme entre `umount -l` et `umount -f`, et le risque
propre à chacun.

::: repondre
lignes: 8
:::

**QO10.7** — Un collègue propose de désactiver complètement le swap sur les serveurs
de bases de données, « parce qu'il y a 128 Go de RAM et que le swap ralentit tout ».
Donne les arguments pour et contre, explique ce que fait réellement
`vm.swappiness`, et dis ce que tu recommandes et pourquoi.

::: repondre
lignes: 8
:::

**QO10.8** — Décris la procédure de récupération d'une machine Linux qui ne démarre
plus à cause d'une ligne fautive dans `/etc/fstab`. Tu n'as accès qu'à la console
Proxmox. Détaille : ce que tu vois à l'écran, comment tu obtiens un shell, pourquoi
la racine est en lecture seule à ce moment-là, et les commandes exactes de la
réparation. Termine par les deux options de `fstab` qui auraient évité l'incident.

::: repondre
lignes: 12
:::

**QO10.9** — On te confie un serveur dont le stockage « rame ». Décris les
métriques que tu regardes dans `iostat -xz 2`, dans quel ordre, et ce que chacune
t'apprend. Explique pourquoi `%util` est trompeur sur un SSD et par quoi tu le
remplaces.

::: repondre
lignes: 8
:::

**QO10.10** — Explique le rôle respectif de `/etc/crypttab` et de `/etc/fstab` pour
un volume LUKS monté au démarrage. Dans quel ordre systemd les traite-t-il, quel
nom apparaît dans chacun, et que se passe-t-il si tu mets l'UUID du système de
fichiers dans `crypttab` ?

::: repondre
lignes: 8
:::

---

## 10.5 Exercices guidés ★

Sauf mention contraire, tout se passe sur `lab-db`. Charge d'abord les noms de
disques : `. /etc/lab10.env` (les exercices utilisent `/dev/sdb` et `/dev/sdc`,
remplace par `$DISQUE1` / `$DISQUE2` si ton setup a basculé en *loop device*).

**E10.1** — Produis une vue unique qui montre, pour chaque périphérique bloc de la
machine : le nom, la taille, le type (disque/partition/lvm), le système de fichiers,
l'étiquette, l'UUID et le point de montage. Une seule commande.

**E10.2** — Affiche le numéro de série du disque `/dev/sdb` sans installer d'outil
supplémentaire, en te servant uniquement de `/dev/disk/`.

**E10.3** — Le fichier `/etc/fstab` de `lab-db` contient une ligne pour `/`.
Retrouve, à partir de son UUID, le nom de périphérique réel correspondant — dans
les deux sens (UUID → device, device → UUID), avec deux commandes différentes.

**E10.4** — Crée sur `/dev/sdb` une table GPT et une partition unique occupant tout
le disque, alignée sur 1 MiB, de type « Linux LVM ». Vérifie que le noyau a bien vu
la nouvelle partition sans redémarrer.

**E10.5** — Formate `/dev/sdb1` en ext4 avec l'étiquette `donnees`, en ne réservant
que 1 % de l'espace à root au lieu des 5 % par défaut. Calcule, pour un volume de
5 Go, combien d'octets tu viens de récupérer.

**E10.6** — Sur un ext4 existant, affiche : la date du dernier `fsck`, le nombre de
montages depuis, le compteur maximal avant vérification forcée, et le nombre
d'inodes libres. Une seule commande suffit pour les trois premières.

**E10.7** — Monte `/dev/sdb1` sur `/srv/factura/archives` avec : pas de mise à jour
des dates d'accès, interdiction d'exécuter un binaire, interdiction des fichiers
setuid et des fichiers de périphérique. Prouve ensuite que `noexec` fonctionne.

**E10.8** — Ajoute ce montage dans `/etc/fstab` par son UUID, avec les mêmes
options, sans passage de `fsck` au démarrage. Vérifie ta ligne **sans redémarrer**
et sans démonter le volume déjà monté.

**E10.9** — Crée un tmpfs de 256 Mio monté sur `/srv/factura/tmp`, accessible en
écriture uniquement par le groupe `factura`, sans exécution possible. Explique en
une ligne où sont réellement stockés les fichiers qu'on y écrit.

**E10.10** — Un processus détient un fichier ouvert sur `/srv/factura/archives` et
empêche le démontage. Reproduis la situation volontairement (avec `sleep` et une
redirection), puis identifie le PID coupable de deux façons différentes.

**E10.11** — Construis la pile LVM suivante : `/dev/sdb1` comme PV, un VG `vg_data`,
un LV `lv_pgdata` de 2 Go formaté en ext4 monté sur `/srv/factura/db`. Affiche
ensuite, en trois commandes, l'état des PV, des VG et des LV.

**E10.12** — Étends `lv_pgdata` de 1 Go supplémentaire **pendant que le volume est
monté et utilisé**, système de fichiers compris, en une seule commande. Vérifie
avec `df -h` avant et après.

**E10.13** — Ajoute `/dev/sdc1` au groupe `vg_data`, puis crée un LV `lv_sauv` qui
occupe **tout l'espace libre restant** du groupe. Attention à la différence entre
`-l 100%FREE` et `-l +100%FREE`.

**E10.14** — Affiche pour chaque LV du groupe `vg_data` les périphériques physiques
qui l'hébergent réellement, puis déplace tous les extents de `/dev/sdb1` vers
`/dev/sdc1` sans démonter quoi que ce soit.

**E10.15** — Prends un snapshot de 512 Mio de `lv_pgdata`, monte-le en lecture seule
sur `/mnt/snap`, et vérifie qu'un fichier créé sur l'origine **après** le snapshot
n'y apparaît pas.

**E10.16** — Affiche le taux de remplissage de tous les snapshots du système en une
commande, formaté en trois colonnes : nom, origine, pourcentage utilisé.

**E10.17** — Crée un fichier de swap de 1 Gio, active-le, rends-le permanent, et
règle `vm.swappiness` à 10 de façon persistante. Prouve que la valeur survit à un
`sysctl --system`.

**E10.18** — Mesure le débit séquentiel en écriture de `/srv/factura/db` avec `dd`
en contournant le cache de page, puis les IOPS en lecture aléatoire 4 k avec `fio`.
Compare les deux chiffres et explique pourquoi ils ne mesurent pas la même chose.

**E10.19** — Pendant que `fio` tourne, relève dans une seconde session les valeurs
de `r/s`, `r_await` et `%util` pour le périphérique concerné, et déduis-en les IOPS
et la latence moyenne.

**E10.20** — Chiffre `/dev/sdc1` avec LUKS2, ouvre-le sous le nom `coffre`, formate
le volume résultant en ext4 et monte-le sur `/srv/coffre`. Affiche ensuite les
en-têtes LUKS pour retrouver l'UUID du conteneur chiffré.

---

## 10.6 Labs ★★

### **L10.1** — Deux disques neufs à mettre en service proprement

::: contexte
Ticket INF-4102. `lab-db` vient de recevoir deux disques de 5 Go. L'équipe applicative
demande un volume `/srv/factura/archives` pour des fichiers de dépôt déposés par un
utilisateur peu fiable : pas question qu'un binaire posé là soit exécutable. Le
volume doit revenir après un redémarrage, et la panne d'un disque de données ne doit
**jamais** empêcher la VM de démarrer.
:::

1. Dresse l'état des lieux : liste les périphériques bloc avec taille, type,
   système de fichiers et point de montage. Note ce qui distingue `sdb` et `sdc` du
   disque système.
2. Sur `/dev/sdb`, crée une table **GPT** et une partition unique de type
   « Linux filesystem », alignée sur 1 MiB, occupant tout le disque. Fais relire la
   table par le noyau sans redémarrer.
3. Formate-la en ext4, étiquette `archives`, réserve root ramenée à 1 %.
4. Monte-la temporairement sur `/srv/factura/archives` avec `noatime`, `nodev`,
   `nosuid`, `noexec`. Vérifie que les quatre options sont actives avec `findmnt`.
5. Prouve que `noexec` fait son travail : copie `/bin/true` dans le volume, rends-le
   exécutable, lance-le, et note le message exact.
6. Rends le montage permanent dans `/etc/fstab`, **par UUID**, avec l'option qui
   empêche un disque absent de bloquer le démarrage, et sans vérification `fsck`
   au boot.
7. Vérifie ta ligne sans redémarrer : contrôle de syntaxe, puis démontage et
   `mount -a`, puis relecture par systemd.
8. Refais l'opération sur `/dev/sdc` mais en **XFS**, étiquette `journaux`, monté
   sur `/srv/factura/journaux`. Compare la sortie de `tune2fs -l` (ext4) et de
   `xfs_info` (XFS) : note trois différences structurelles.
9. Redémarre la VM et vérifie que les deux volumes reviennent seuls.

::: check
Critère de succès : après redémarrage, `/srv/factura/archives` et
`/srv/factura/journaux` sont montés, référencés par UUID dans `fstab`, avec les
options demandées, et `noexec` est effectif sur le premier.

```bash
bash check_M10_01.sh
```
:::

---

### **L10.2** — Mettre la base sous LVM et l'étendre à chaud

::: contexte
Ticket INF-4118. Le datastore de `factura-db` vit dans `/srv/factura/db`, sur une
partition brute. Chaque agrandissement demande une fenêtre d'arrêt et l'équipe en a
assez. On te demande de migrer sur LVM, puis de prouver qu'une extension se fait
désormais sans coupure — et de démontrer aussi le geste inverse, la réduction, pour
que l'équipe sache pourquoi on l'évite.
:::

Repars de disques propres : démonte ce que L10.1 a monté et efface les signatures
(`sudo wipefs -a /dev/sdb1 /dev/sdc1`) — les entrées `fstab` de L10.1 sont à mettre
en commentaire le temps du lab.

1. Change le type des deux partitions en « Linux LVM » (`8e00`), puis crée un PV sur
   chacune. Affiche la taille utile du PV et compare-la à la taille de la partition :
   où sont passés les quelques Mio manquants ?
2. Crée le groupe `vg_data` sur `/dev/sdb1` seul. Relève la taille du PE (extent).
3. Crée `lv_pgdata` de 2 Go, formate-le en ext4, monte-le sur `/srv/factura/db`,
   et ajoute-le à `fstab` par son chemin `/dev/vg_data/lv_pgdata`. Justifie en une
   phrase pourquoi, ici, on n'utilise pas l'UUID.
4. Lance le générateur d'écritures fourni par le setup, qui remplit le volume en
   continu :

   ```bash
   sudo /opt/factura/bin/factura-ecritures.sh /srv/factura/db &
   ```

5. **Sans rien arrêter**, étends `lv_pgdata` à 3,5 Go, système de fichiers compris,
   en une seule commande. Vérifie avec `df -h` que l'espace est disponible et que le
   générateur n'a pas bronché (aucune ligne d'erreur dans sa sortie).
6. Le VG est maintenant trop petit. Ajoute `/dev/sdc1` au groupe, puis étends
   `lv_pgdata` pour qu'il utilise **la moitié de l'espace libre restant**.
7. Le disque `sdb` doit partir en maintenance. Déplace **à chaud** tous ses extents
   vers `sdc`, retire-le du groupe, et supprime le PV. Vérifie à chaque étape que
   `/srv/factura/db` reste monté et accessible.
8. Réduction : crée un LV `lv_test` de 2 Go en ext4, monte-le sur `/mnt/test`,
   écris-y 200 Mio de données, puis réduis-le à 1 Go **sans perdre les données**.
   Note chaque commande dans l'ordre et explique ce qui casserait si on inversait
   deux étapes.
9. Rédige `~/lab10/rapports/inf-4118.md` : la pile obtenue (`pvs`, `vgs`,
   `lvs -o +devices`), le temps d'indisponibilité réel de chaque opération, et la
   procédure de réduction avec l'avertissement qui va bien.

::: check
Critère de succès : `/srv/factura/db` est monté sur `/dev/vg_data/lv_pgdata`,
le VG ne contient plus que `/dev/sdc1`, `lv_test` fait 1 Go et ses données sont
intactes, et le rapport existe.

```bash
bash check_M10_02.sh
```
:::

---

### **L10.3** — Une sauvegarde cohérente par snapshot LVM

::: contexte
Ticket INF-4133. La sauvegarde nocturne de `factura-db` produit une archive
inutilisable une nuit sur trois : elle est prise pendant que l'application écrit, et
l'archive contient des fichiers à moitié écrits. On te demande une sauvegarde
**cohérente** sans arrêter le service, et une procédure de restauration testée.
:::

1. Assure-toi que le générateur d'écritures tourne sur `/srv/factura/db`. Prends une
   archive « naïve » avec `tar` pendant qu'il écrit et observe le message de `tar`
   sur au moins un fichier.
2. Crée un snapshot de `lv_pgdata` nommé `snap_pg`, dimensionné à 512 Mio.
   Explique dans ton rapport **pourquoi 512 Mio suffisent** alors que l'origine fait
   plusieurs gigaoctets.
3. Monte le snapshot en lecture seule sur `/mnt/snap`. Vérifie qu'un fichier créé
   sur l'origine après la création du snapshot n'y figure pas.
4. Produis l'archive `/srv/sauvegardes/factura-db-$(date +%F).tar.gz` **depuis le
   snapshot**, pas depuis l'origine. Compare le temps d'exécution et l'absence de
   messages d'erreur avec l'étape 1.
5. Surveille le remplissage du snapshot pendant la sauvegarde (`lvs` en boucle).
   Note la vitesse à laquelle il se remplit et calcule combien de temps il tiendrait.
6. Démonte et supprime le snapshot. Explique ce qui se passerait si tu l'oubliais
   pendant trois semaines.
7. Restauration : supprime volontairement `/srv/factura/db/comptes.dat`, recrée un
   snapshot, puis **fusionne** le snapshot dans l'origine pour revenir à l'état
   antérieur. Le volume étant monté, observe le message de `lvconvert` et déduis-en
   quand la fusion a réellement lieu.
8. Écris `/opt/factura/bin/sauvegarde-snapshot.sh` : script bash
   (`#!/usr/bin/env bash`, `set -euo pipefail`) qui crée le snapshot, le monte,
   archive, démonte, supprime le snapshot, et **nettoie proprement même en cas
   d'erreur** (`trap`). Il refuse de démarrer si un snapshot du même nom existe déjà.

::: check
Critère de succès : une archive existe dans `/srv/sauvegardes/`, plus aucun snapshot
ne traîne dans `vg_data`, `comptes.dat` est revenu, et
`sauvegarde-snapshot.sh` s'exécute deux fois de suite sans laisser de résidu.

```bash
bash check_M10_03.sh
```
:::

---

### **L10.4** — « Le disque de la VM est plein » : croissance de bout en bout

::: contexte
Ticket INF-4150, celui que tu feras des dizaines de fois dans ta carrière.
`lab-db` a 30 Go de disque système et `/` est à 92 %. On t'accorde 20 Go de plus sur
le datastore Proxmox. Objectif : passer `/` à 50 Go **sans redémarrage**, et poser
un fichier de swap au passage parce que la VM n'en a pas.
:::

::: attention
Cette manipulation touche le disque système. Snapshot Proxmox **obligatoire** avant
de commencer : `qm snapshot 9003 avant-lab10-4`. Une inversion de numéro de
partition dans `growpart` détruit la table de partitions.
:::

1. Avant toute chose, relève et note : sortie de `lsblk`, de `df -h /`, de `pvs`,
   `vgs`, `lvs`, et le numéro de la partition qui porte le PV du VG système.
   Cette photo est ton filet de sécurité.
2. Côté hyperviseur, agrandis le disque :

   ```bash
   # shell Proxmox
   qm resize 9003 scsi0 +20G
   ```

3. Dans la VM, fais constater au noyau la nouvelle taille **sans redémarrer** et
   vérifie avec `lsblk` que `sda` fait bien 50 Go. Si le noyau ne voit rien, trouve
   la commande qui force une relecture de la géométrie du disque.
4. Agrandis la **partition** qui porte le PV avec `growpart`. Note pourquoi
   `fdisk` seul ne suffit pas ici et pourquoi `growpart` est l'outil correct.
5. Agrandis le **PV** pour qu'il occupe la nouvelle taille de la partition. Vérifie
   avec `pvs` que l'espace libre du VG a augmenté.
6. Étends le **LV** de `/` pour occuper tout le libre, système de fichiers compris,
   en une commande. Vérifie avec `df -h /` : le résultat doit être visible
   immédiatement, sans démontage.
7. Récapitule la chaîne des quatre couches traversées et, pour chacune, la commande
   utilisée et ce qui se serait passé si tu l'avais sautée.
8. Swap : crée un fichier de swap de 2 Gio avec les bons droits, active-le, rends-le
   permanent, et fixe `vm.swappiness` à 10 de manière persistante. Explique en deux
   lignes pourquoi 10 et pas 60 sur une machine de base de données.
9. Vérifie qu'un redémarrage ne casse rien : `findmnt --verify`, puis reboot, puis
   contrôle de `df -h /` et `swapon --show`.

::: astuce
Si `growpart` te répond `NOCHANGE: partition 3 is size X. it cannot be grown`,
regarde s'il existe une partition **après** celle que tu veux agrandir. Sur une
image cloud Ubuntu, la partition 3 est en dernier ; sur une installation manuelle,
une partition de swap peut la suivre et il faudra la supprimer avant.
:::

::: check
Critère de succès : `/` fait au moins 45 Go, le service n'a jamais été arrêté,
un swap de 2 Gio est actif et permanent, `vm.swappiness` vaut 10 après reboot.

```bash
bash check_M10_04.sh
```
:::

---

### **L10.5** — Coffre chiffré LUKS et partage NFS

::: contexte
Ticket INF-4166. Deux demandes le même jour. La première : les sauvegardes de
`factura` contiennent des données personnelles, elles doivent être chiffrées au
repos sur le volume qui les héberge. La seconde : l'équipe dev veut lire les
archives depuis `lab-adm` via un partage réseau, en lecture seule.
:::

**Partie A — LUKS**

1. Libère une partition (ou crée un LV `lv_coffre` de 1 Go dans `vg_data`) et
   chiffre-la avec LUKS2. Note la commande exacte et la confirmation demandée.
2. Ouvre le conteneur sous le nom `coffre`. Observe ce qui apparaît dans
   `/dev/mapper/` et dans `lsblk`.
3. Formate le volume déchiffré en ext4, monte-le sur `/srv/coffre`, écris un fichier
   témoin dedans.
4. Démonte, ferme le conteneur, et prouve que les données ne sont plus lisibles :
   `sudo blkid` sur le périphérique sous-jacent, et une tentative de montage direct.
5. Rends l'ouverture automatique au démarrage : renseigne `/etc/crypttab` (avec
   l'UUID **du conteneur LUKS**, pas celui du système de fichiers) et `/etc/fstab`
   (avec le nom `/dev/mapper/coffre`). Explique l'ordre dans lequel systemd traite
   les deux fichiers.
6. Ajoute une seconde phrase de passe dans un emplacement de clé libre, puis liste
   les emplacements occupés. Explique à quoi ça sert en exploitation réelle.
7. Redémarre : la VM doit demander la phrase de passe en console. Note ce qui se
   passe si personne ne la saisit, et l'option de `crypttab` qui évite de bloquer le
   boot indéfiniment.

**Partie B — NFS côté client**

8. Sur `lab-adm`, le setup en mode `--nfs` a exporté `/srv/exports/archives` en
   lecture seule pour `10.10.10.0/24`. Vérifie l'export depuis `lab-db` sans rien
   monter (`showmount -e 10.10.10.10`).
9. Monte-le à la main sur `/mnt/archives-adm` en NFSv4.2, en lecture seule, avec un
   montage `hard`. Vérifie le résultat avec `findmnt`.
10. Rends le montage permanent dans `fstab` avec les options qui conviennent à un
    volume réseau, dont celle qui dit à systemd d'attendre le réseau et celle qui
    évite de bloquer le boot si `lab-adm` est éteint.
11. Éteins temporairement le service NFS sur `lab-adm` et observe le comportement
    d'un `ls /mnt/archives-adm` avec `hard` : décris précisément ce que tu vois.
    Compare avec ce que donnerait `soft,timeo=50`.

::: check
Critère de succès : `/srv/coffre` est monté via `/dev/mapper/coffre`, `crypttab`
référence l'UUID LUKS, deux emplacements de clé sont occupés, et
`/mnt/archives-adm` est monté en lecture seule avec `_netdev`.

```bash
bash check_M10_05.sh
```
:::

---

## 10.7 Break & Fix ★★★

::: attention
Avant chaque Break & Fix : `qm snapshot 9003 avant-bf10-<n>`. Le snapshot de secours
reste `snap-clean`, mais l'utiliser vaut échec : l'objectif est de réparer, pas de
rembobiner. BF10.1 provoque un **échec de démarrage réel** : tu auras besoin de la
console Proxmox (`Console` → `noVNC`), le SSH ne répondra pas.
:::

### **BF10.1** — « La VM ne démarre plus depuis la maintenance d'hier »

```bash
sudo bash break_M10_01.sh
sudo reboot
```

**Symptôme utilisateur** : `lab-db` ne répond plus en SSH. Dans la console Proxmox,
le démarrage s'arrête sur :

```console
[ *** ] A start job is running for /dev/disk/by-uuid/9c1f... (1min 30s)
[DEPEND] Dependency failed for /srv/factura/archives.
[DEPEND] Dependency failed for Local File Systems.
You are in emergency mode. After logging in, type "journalctl -xb" to view
system logs, "systemctl reboot" to reboot, or "exit" to continue bootup.
Give root password for maintenance (or press Control-D to continue):
```

**Interdit** : rollback de snapshot, démarrage sur une ISO de secours, suppression
pure et simple du fichier `/etc/fstab`.

**Objectif** : obtenir un shell, identifier la ligne fautive, comprendre **pourquoi
la racine est en lecture seule** à ce stade, réparer, redémarrer normalement, puis
modifier la ligne pour que ce type d'erreur ne puisse plus jamais empêcher le boot.
Explique aussi pourquoi le démarrage a attendu 1 min 30 s avant d'abandonner, et
comment on raccourcit cette attente.

::: repondre
lignes: 12
:::

### **BF10.2** — « Plus une seule écriture ne passe, et le disque est à moitié vide »

```bash
sudo bash break_M10_02.sh
```

**Symptôme utilisateur** : l'application `factura` journalise
`OSError: [Errno 28] No space left on device` en écrivant dans
`/srv/factura/archives`. Mais `df -h` affiche 47 % d'utilisation sur ce volume, et
il reste plus de 500 Mio de libre. `touch /srv/factura/archives/test` échoue aussi.

**Interdit** : reformater le volume, supprimer les données existantes.

**Objectif** : identifier la ressource réellement épuisée, la prouver par une
commande, remettre le volume en état d'écriture **sans perdre de données**, puis
expliquer pourquoi l'extension du LV (`lvextend -r`) résout ou ne résout pas le
problème selon la façon dont le système de fichiers a été créé. Donne la commande
de formatage qui aurait évité l'incident.

::: repondre
lignes: 10
:::

### **BF10.3** — « La sauvegarde de cette nuit est vide et le snapshot est bizarre »

```bash
sudo bash break_M10_03.sh
```

**Symptôme utilisateur** : le script de sauvegarde a tourné, l'archive produite fait
quelques kilo-octets. `mount /dev/vg_data/snap_pg /mnt/snap` échoue avec
`mount: /mnt/snap: can't read superblock on /dev/mapper/vg_data-snap_pg`. La base de
données, elle, fonctionne parfaitement.

**Interdit** : supprimer le volume d'origine, restaurer depuis une sauvegarde
externe.

**Objectif** : lire l'état du snapshot dans `lvs` et nommer précisément l'attribut
qui trahit le problème, expliquer le mécanisme de copie sur écriture qui a conduit
là, remettre le système en état de produire une sauvegarde valide, et proposer deux
protections : une sur le dimensionnement, une sur la surveillance.

::: repondre
lignes: 10
:::

### **BF10.4** — « Impossible de démonter, et le volume refuse de s'étendre »

```bash
sudo bash break_M10_04.sh
```

**Symptôme utilisateur** : la maintenance prévue à 22 h est bloquée.
`sudo umount /srv/factura/archives` répond `target is busy` alors que le service
`factura` est arrêté. Et `sudo lvextend -L +1G -r /dev/vg_data/lv_pgdata` répond
`Insufficient free space: 256 extents needed, but only 0 available`, bien que le
groupe ait été dimensionné large.

**Interdit** : redémarrer la machine, `fuser -km` en aveugle sur le point de
montage.

**Objectif** : trouver les deux causes (ce ne sont pas les mêmes), démonter
proprement, libérer l'espace du groupe de volumes, réussir l'extension, et rédiger
en trois lignes la règle d'exploitation qui évite le second problème.

::: repondre
lignes: 10
:::

---

## 10.8 Défi du module ★★★

**D10 — Un volume de sauvegarde redondant, chiffré et surveillé**

::: contexte
La direction demande que les sauvegardes de `factura` survivent à la panne d'un
disque, soient chiffrées au repos, et que l'exploitation soit prévenue avant que le
volume ne se remplisse. Tu disposes des deux disques de `lab-db`. Livrable : une
pile de stockage fonctionnelle, un script de sauvegarde et un script de supervision.
:::

Repars d'un état propre (`qm rollback 9003 snap-clean` puis relance du setup), ou
libère toi-même `sdb` et `sdc`.

**Cahier des charges**

1. **RAID1** : un tableau `/dev/md0` en miroir sur `/dev/sdb1` et `/dev/sdc1`
   (partitions de type `fd00`). La configuration doit survivre à un redémarrage —
   `mdadm.conf` **et** initramfs.
2. **LVM par-dessus** : `/dev/md0` comme unique PV, un VG `vg_sauv`, un LV
   `lv_coffre` occupant 60 % du groupe. Les 40 % restants sont laissés libres
   **volontairement** : explique dans le rapport à quoi ils servent.
3. **LUKS** : `lv_coffre` chiffré en LUKS2, ouvert sous le nom `coffre`, formaté en
   ext4, monté sur `/srv/sauvegardes`. Ouverture au démarrage via `/etc/crypttab`,
   montage via `/etc/fstab`, avec les options de durcissement qui conviennent à un
   volume de données (`nodev,nosuid,noexec`).
4. **Script de sauvegarde** `/opt/factura/bin/sauvegarde.sh` :
   * `#!/usr/bin/env bash`, `set -euo pipefail`, idempotent, sans interaction ;
   * prend un snapshot LVM de `lv_pgdata` dimensionné à 10 % de l'origine ;
   * monte le snapshot en lecture seule, archive vers
     `/srv/sauvegardes/factura-db-AAAA-MM-JJ.tar.gz`, démonte, supprime le snapshot ;
   * `trap` de nettoyage : aucun snapshot ni montage résiduel, même en cas d'erreur
     ou d'interruption ;
   * refuse de s'exécuter si l'espace libre du VG est inférieur à la taille du
     snapshot demandée, avec un message explicite et un code de retour non nul ;
   * conserve 7 archives, supprime les plus anciennes ;
   * journalise dans `/var/log/factura/sauvegarde.log` avec horodatage.
5. **Script de supervision** `/opt/factura/bin/verif-stockage.sh`, exécutable par
   n'importe qui sans `sudo` autre que les lectures nécessaires, qui sort en 0 si
   tout va bien, 1 sinon, et signale :
   * un tableau mdadm dégradé (lecture de `/proc/mdstat`) ;
   * un LV dont le système de fichiers dépasse 85 % d'occupation en espace **ou en
     inodes** ;
   * un snapshot existant depuis plus de 24 h, ou rempli à plus de 70 % ;
   * un VG dont l'espace libre est inférieur à 10 % ;
   * une entrée de `fstab` dont la source n'existe pas
     (`findmnt --verify` est ton ami).
6. **Unité systemd** : un `factura-sauvegarde.timer` déclenche le script de
   sauvegarde chaque jour à 2 h 30, et `verif-stockage.timer` toutes les 15 minutes.
7. **Test de panne** : simule la perte d'un disque du miroir
   (`mdadm --fail` puis `--remove`), prouve que `/srv/sauvegardes` reste accessible,
   vérifie que le script de supervision le signale, puis réintègre le disque et
   observe la reconstruction dans `/proc/mdstat`.
8. **Rapport** `~/lab10/rapports/d10.md` : schéma texte de la pile complète (disque →
   partition → md → PV → VG → LV → LUKS → FS → point de montage), la sortie des
   commandes de vérification, le temps de reconstruction mesuré à l'étape 7, et la
   réponse argumentée à cette question : « pourquoi LUKS **au-dessus** de LVM et pas
   en dessous ? »

Temps visé : 90 minutes.

::: check
```bash
bash check_M10_06.sh
```
:::

---

## 10.9 Auto-évaluation

| Compétence | Acquis | À revoir |
|---|---|---|
| Identifier un périphérique bloc et son UUID | ☐ | ☐ |
| Justifier le montage par UUID plutôt que par `/dev/sdX` | ☐ | ☐ |
| Partitionner en GPT, aligner, faire relire la table | ☐ | ☐ |
| Choisir ext4 / XFS / btrfs / tmpfs sur des critères techniques | ☐ | ☐ |
| Écrire et **vérifier** une ligne de `fstab` champ par champ | ☐ | ☐ |
| Diagnostiquer un `target is busy` | ☐ | ☐ |
| Construire une pile PV / VG / LV et l'étendre à chaud | ☐ | ☐ |
| Réduire un LV sans perdre de données | ☐ | ☐ |
| Prendre, monter, fusionner et dimensionner un snapshot LVM | ☐ | ☐ |
| Agrandir un disque de VM de bout en bout sans coupure | ☐ | ☐ |
| Créer et surveiller un RAID1 mdadm | ☐ | ☐ |
| Chiffrer un volume avec LUKS et le monter au démarrage | ☐ | ☐ |
| Monter un partage NFS proprement et lire un `iostat -xz` | ☐ | ☐ |
| Récupérer une machine bloquée par un `fstab` fautif | ☐ | ☐ |

Pour aller plus loin :

* Lis `man 5 fstab`, `man 8 mount` à la section **FILESYSTEM-INDEPENDENT MOUNT
  OPTIONS**, et `man 5 systemd.mount` : trois pages qui règlent 90 % des incidents
  de montage.
* Monte une pile LVM **thin** (`lvcreate --type thin-pool`, puis
  `lvcreate -V 100G -T vg/pool -n lv`) et provisionne 300 Go de volumes sur 50 Go
  réels. Puis remplis-les et observe ce qui se passe. C'est la seule façon de
  comprendre pourquoi on surveille `data_percent` d'un pool thin comme le lait sur
  le feu.
* Compare `btrfs subvolume snapshot` et `lvcreate -s` sur les mêmes données : coût
  en espace, en temps, granularité, et facilité de restauration.
* Mets en place les quotas sur un volume ext4 (`usrquota,grpquota` dans `fstab`,
  `quotacheck -cug`, `edquota -u`) et l'équivalent XFS (`uquota`, `xfs_quota`).
  Note ce qui change dans la façon dont le quota est stocké.
