# Module 09 — Noyau Linux et démarrage

## 9.0 Objectifs et compétences

::: objectif
À la fin de ce module, je sais :

* expliquer la frontière espace noyau / espace utilisateur, ce qu'est un appel
  système, comment un programme y entre et en sort, et pourquoi un processus en
  état `D` « est dans le noyau » ;
* dérouler un démarrage de bout en bout — firmware, ESP, shim, GRUB2, `vmlinuz`
  et initramfs, `systemd` — en nommant les fichiers réels de chaque étape sur
  Ubuntu 24.04 et sur Rocky 9 ;
* modifier la ligne de commande du noyau proprement (`/etc/default/grub` +
  `update-grub`, `grubby` sous Rocky), éditer une entrée GRUB au démarrage, et
  reprendre la main sur une VM dont on a perdu le mot de passe root ;
* dire à quoi sert l'initramfs, l'inspecter, le régénérer, et savoir dans quels
  cas c'est obligatoire (LVM, LUKS, pilote de stockage, blacklist) ;
* gérer les noyaux installés (plusieurs versions, HWE, purge, `/boot` plein),
  et expliquer Secure Boot et MOK en deux phrases ;
* charger, paramétrer, blacklister et rendre persistant un module noyau,
  et lire les dépendances dans `modules.dep` ;
* exploiter `/proc` et `/sys` sans intermédiaire : `cmdline`, `meminfo`,
  `interrupts`, `/proc/PID/*`, ordonnanceur E/S, transparent hugepages ;
* poser un paramètre `sysctl` au bon endroit, connaître l'ordre de précédence
  des fichiers, et éviter le piège du paramètre qui n'existe pas tant que le
  module n'est pas chargé ;
* écrire une règle udev qui nomme un disque ou une interface de façon stable,
  la tester sans reboot, et brancher un disque à chaud dans une VM Proxmox ;
* lire le journal du noyau et reconnaître une trace OOM, une erreur E/S, un
  *soft lockup*, un *hung task* ; activer `kdump` ; utiliser SysRq à bon escient ;
* mettre en place un serveur de temps de lab avec chrony, expliquer pourquoi
  l'heure d'une VM dérive et ce qu'un décalage de cinq minutes casse.

Temps estimé : 7 h
Prérequis : modules 08 (processus, `/proc/PID`, systemd), 10 (paquets) pour la
gestion des noyaux, 11 (stockage) pour les manipulations de disques.
`strace` en profondeur et `perf` sont au module 19 ; les partitions, `fstab` et
le mode `emergency` au module 11 ; le durcissement `sysctl` au module 18.
:::

---

## 9.1 Mise en place

VM concernées : **`lab-adm` (10.10.10.10)** pour tout le module, **`lab-web`
(10.10.10.11)** comme client de temps (L9.5), **`lab-rhel` (10.10.10.13)** pour
les variantes `grubby`/`dracut`/chrony.

```bash
# depuis le shell Proxmox, avant de commencer — OBLIGATOIRE
qm snapshot 9001 avant-lab09
qm snapshot 9004 avant-lab09
# console série, utilisée par L9.1 et par tous les Break & Fix
qm set 9001 --serial0 socket
qm set 9004 --serial0 socket
```

Paquets nécessaires sur `lab-adm` :

```bash
sudo apt update
sudo apt install -y strace auditd chrony kmod initramfs-tools efibootmgr \
  sg3-utils linux-crashdump bpftrace mokutil util-linux procps
```

`auditd` fournit `ausyscall` ; `sg3-utils` fournit `rescan-scsi-bus.sh` ;
`linux-crashdump` installe `kdump-tools` et le paquet `crash` (D9).
L'installation de `linux-crashdump` demande d'activer kdump : réponds **Non**
pour l'instant, tu l'activeras toi-même en 9.8.

::: rhel
Sous Rocky 9 : `sudo dnf install -y strace audit chrony kmod dracut efibootmgr
sg3_utils kexec-tools bpftrace mokutil grubby`. `ausyscall` vient du paquet
`audit`, `lsinitrd` du paquet `dracut`, `grubby` est déjà installé sur une
Rocky standard.
:::

Préparation du terrain (idempotent) :

```bash
sudo bash ~/workbook/scripts/setup/setup_M09.sh
```

Le script crée `~/lab09/{rapports,conf,udev,bin,reference}` et capture une
**référence** de l'état noyau de la VM : `uname -a`, `/proc/cmdline`, `lsmod`,
`sysctl -a`, `ls -l /boot`, `ip -br link`. Tu compareras l'état de la machine à
cette référence après chaque lab et chaque Break & Fix — c'est le premier
réflexe de diagnostic de ce module (`diff`).

::: attention
Les labs L9.1, L9.2, L9.3 et les Break & Fix BF9.1, BF9.3, BF9.4 touchent
GRUB, `/boot`, l'initramfs et la configuration réseau au démarrage. Sans
snapshot, une erreur te coûte une réinstallation. Le port série et
`qm terminal 9001` sont ta porte de secours quand SSH ne répond plus : teste-les
dès L9.1, **avant** d'en avoir besoin.
:::

---

## 9.2 Rappel express

### Deux espaces, une porte

```text
 espace utilisateur   ls -> libc (opendir, readdir, printf)
                             |  syscall  (instruction CPU, changement de mode)
 ------------------------------------------------------------
 espace noyau         sys_openat / sys_getdents64 / sys_write
                             |  pilotes, VFS, ordonnanceur, mémoire
                      matériel (ou l'hyperviseur qui l'imite)
```

@fig(noyau-espaces): Espace utilisateur, frontière des appels système, espace noyau et matériel ; `/proc`, `/sys`, `/dev` comme fenêtres, `sysctl` qui écrit dans `/proc/sys`.

Un appel système est la **seule** porte d'entrée normale dans le noyau. La libc
enveloppe chaque appel (`open()` → `openat`), et parfois l'évite (`printf`
tamponne, `gettimeofday` passe par la vDSO sans changer de mode). Un processus
en `D` est **dans** un appel système, en attente d'un pilote : les signaux
attendent qu'il en sorte.

```bash
strace -c ls /                 # compteur d'appels : observer, pas analyser
cat /proc/1234/syscall         # numéro + arguments de l'appel en cours
ausyscall 257                  # 257 -> openat ; ausyscall --dump
cat /proc/1234/wchan           # fonction noyau où le processus dort
```

### La chaîne de démarrage

```text
firmware (BIOS ou UEFI) -> ESP /boot/efi (UEFI) ou MBR+BIOS boot (BIOS)
  -> shimx64.efi (Secure Boot) -> grubx64.efi -> /boot/grub/grub.cfg
  -> vmlinuz-6.8.0-xx + initrd.img-6.8.0-xx (initramfs)
  -> noyau : pilotes, montage de la racine par l'initramfs
  -> /sbin/init = systemd -> default.target -> getty / sshd
```

@fig(boot-chaine): La chaîne de démarrage du micrologiciel à la connexion, avec le fichier ou la commande qui agit à chaque étape.

| Élément | Ubuntu 24.04 | Rocky 9 |
|---|---|---|
| Config GRUB éditable | `/etc/default/grub` (+ `grub.d/*.cfg`) | `/etc/default/grub` |
| Fichier généré | `/boot/grub/grub.cfg` | `/boot/grub2/grub.cfg` + `/boot/loader/entries/` |
| Régénérer | `update-grub` | `grub2-mkconfig -o /boot/grub2/grub.cfg` |
| Paramètres noyau | éditer puis `update-grub` | `grubby --update-kernel=ALL --args=` |
| initramfs | `update-initramfs -u -k all` | `dracut -f` |
| Inspecter l'initrd | `lsinitramfs`, `unmkinitramfs` | `lsinitrd` |
| Config initrd | `/etc/initramfs-tools/` | `/etc/dracut.conf.d/` |
| Noyau par défaut | `GRUB_DEFAULT=` | `grubby --set-default` |
| Paquet noyau | `linux-image-*`, `linux-generic-hwe-24.04` | `kernel`, `kernel-core`, `kernel-modules` |

```bash
cat /proc/cmdline ; [ -d /sys/firmware/efi ] && echo UEFI || echo BIOS
efibootmgr -v ; findmnt /boot/efi
grep -E '^menuentry|^\s+linux' /boot/grub/grub.cfg
systemd-analyze ; systemd-analyze blame | head
systemd-analyze critical-chain ; systemd-analyze plot > boot.svg
lsinitramfs /boot/initrd.img-$(uname -r) | grep -E 'virtio|lvm' | head
```

Ubuntu : `/etc/default/grub.d/*.cfg` est lu **après** `/etc/default/grub` et
l'écrase. `GRUB_TIMEOUT_STYLE=hidden` + `GRUB_TIMEOUT=0` = menu invisible ;
maintenir `Échap` (ou `Maj`) pour le voir.

Dépanner au menu GRUB : `e` sur l'entrée, fin de la ligne `linux`, ajouter
`systemd.unit=rescue.target` (shell root, mot de passe requis) ou
`init=/bin/bash` (shell sans mot de passe, racine en lecture seule :
`mount -o remount,rw /`), puis `Ctrl-x`. Rocky : `rd.break`, `mount -o remount,rw /sysroot`,
`chroot /sysroot`, et `touch /.autorelabel` (SELinux).

| Paramètre | Effet |
|---|---|
| `quiet` / `splash` | masque les messages / affiche l'image |
| `console=ttyS0,115200` | console série (Proxmox `qm terminal`) |
| `nomodeset` | pas de pilote graphique noyau (VM, écran noir) |
| `net.ifnames=0` | noms `eth0` au lieu de `ens18` |
| `mitigations=off` | +5–15 % CPU, ouvre Spectre/Meltdown : jamais en prod |
| `crashkernel=` | réserve la mémoire pour kdump |
| `transparent_hugepage=never` | THP désactivées pour les bases |
| `panic=10` | reboot 10 s après un panic |

### Noyaux et modules

```bash
uname -r ; dpkg -l 'linux-image-*' | grep ^ii ; ls -lh /boot ; df -h /boot
sudo apt install linux-generic-hwe-24.04     # noyau HWE, plus récent
sudo apt autoremove --purge                  # vieux noyaux (garde le courant)
mokutil --sb-state ; dmesg | grep -i 'secure boot'
lsmod | grep virtio ; modinfo -F depends virtio_net ; modinfo -p dummy
sudo modprobe dummy numdummies=2 ; sudo modprobe -r dummy
cat /sys/module/dummy/parameters/numdummies
modprobe --show-depends virtio_scsi ; sudo depmod -a
```

```ini
# /etc/modprobe.d/lab.conf  — paramètres et interdictions (lu par modprobe)
options dummy numdummies=2
blacklist joydev            # bloque le chargement AUTOMATIQUE (par alias)
install pcspkr /bin/false   # bloque aussi modprobe explicite
# /etc/modules-load.d/lab.conf — chargement au boot (systemd-modules-load)
dummy
```

::: rhel
Rocky : `dnf install kernel` installe le plus récent (limite `installonly_limit=3`
dans `/etc/dnf/dnf.conf`), `dnf remove --oldinstallonly` purge les anciens,
`grubby --info=ALL`, `grubby --default-kernel`. `kernel-core` = `vmlinuz` +
modules vitaux ; `kernel-modules` = les pilotes courants.
:::

### /proc, /sys, sysctl

```bash
cat /proc/cpuinfo | grep -m1 -E 'model name|flags' ; nproc
grep -E 'MemTotal|MemAvailable|Dirty' /proc/meminfo
cat /proc/interrupts | grep virtio ; ls /proc/1234/fd | wc -l
cat /sys/block/sda/queue/scheduler          # [mq-deadline] none kyber bfq
echo none | sudo tee /sys/block/sda/queue/scheduler
cat /sys/kernel/mm/transparent_hugepage/enabled
sysctl vm.swappiness ; sudo sysctl -w vm.swappiness=10    # volatile
sudo sysctl --system                                       # rejoue les fichiers
sysctl -a 2>/dev/null | wc -l
```

Ordre `sysctl --system` : `/etc/sysctl.d/*.conf`, `/run/sysctl.d`,
`/usr/local/lib/sysctl.d`, `/usr/lib/sysctl.d`, `/lib/sysctl.d`, puis
`/etc/sysctl.conf`. Tri **lexical par nom de fichier**, le dernier gagne ; un même
nom dans `/etc` masque celui de `/usr/lib`. Ubuntu : `99-sysctl.conf` est un lien
vers `/etc/sysctl.conf`, lu en dernier. Un fichier sans `.conf` est ignoré.

| Paramètre | Défaut Ubuntu | Pourquoi on y touche |
|---|---|---|
| `vm.swappiness` | 60 | 10 pour une base, 1 pour Kubernetes |
| `vm.overcommit_memory` | 0 | 1 exigé par Redis, 2 pour interdire |
| `vm.dirty_ratio` / `_background_ratio` | 20 / 10 | 10 / 5 : lisser les écritures |
| `fs.file-max` | 2⁶³−1 (systemd) | plafond système de fichiers ouverts |
| `fs.inotify.max_user_watches` | selon RAM | IDE, agents, `inotify` limit |
| `kernel.pid_max` | 4194304 | rarement, 32768 sur vieux systèmes |
| `kernel.panic` | 0 | 10 : reboot automatique après panic |
| `kernel.sysrq` | 176 | 1 pour tout, 0 pour rien |
| `net.core.somaxconn` | 4096 | backlog `listen()` des serveurs |
| `net.ipv4.ip_forward` | 0 | 1 pour un routeur / Docker / K8s |
| `net.ipv4.tcp_tw_reuse` | 2 | 1 : réutiliser TIME_WAIT (client sortant) |
| `net.ipv4.ip_local_port_range` | 32768 60999 | élargir pour les proxys |
| `net.netfilter.nf_conntrack_max` | selon RAM | table pleine → paquets perdus |
| `kernel.kptr_restrict` | 1 | 2 : cache les adresses noyau |
| `kernel.dmesg_restrict` | 1 | `dmesg` réservé à root |

`net.netfilter.*` n'existe pas tant que `nf_conntrack` n'est pas chargé :
`sysctl --system` au boot échoue en silence sur cette clé.

### Périphériques et udev

```bash
ls -l /dev/sda /dev/null            # b 8,0 ; c 1,3 : majeur, mineur
ls -l /dev/disk/by-id/ /dev/disk/by-path/ /dev/disk/by-uuid/
udevadm info -q property -n /dev/sdb | grep -E 'ID_SERIAL|ID_PATH'
udevadm info -a -n /dev/sdb | head -40         # attributs pour ATTR{}
udevadm monitor -u -k                          # événements en direct
udevadm test /sys/class/net/ens18 2>&1 | tail  # simulation d'une règle
sudo udevadm control --reload ; sudo udevadm trigger --action=add /dev/sdb
echo '- - -' | sudo tee /sys/class/scsi_host/host*/scan   # disque à chaud
echo 1 | sudo tee /sys/class/block/sdb/device/rescan      # disque agrandi
```

```ini
# /etc/udev/rules.d/61-lab-disque.rules
SUBSYSTEM=="block", ENV{ID_SERIAL}=="0QEMU_QEMU_HARDDISK_drive-scsi1", \
  SYMLINK+="disk/lab/cache", ATTR{queue/scheduler}="none"
# /etc/udev/rules.d/70-lab-net.rules
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="bc:24:11:aa:bb:cc", NAME="lan0"
```

`==` compare, `=` affecte, `+=` ajoute. Les règles sont triées par nom entre
`/usr/lib/udev/rules.d`, `/run/udev/rules.d` et `/etc/udev/rules.d`. Pour une
interface réseau, `/etc/systemd/network/10-lan.link` est la voie moderne.

### Journal du noyau, temps, limites

```bash
sudo dmesg -T --level=err,warn ; sudo dmesg -T -w      # suivre en direct
journalctl -k -b -1 -p warning          # noyau, boot précédent
cat /proc/sys/kernel/printk              # 4 4 1 7 : console, défaut, min, boot
echo m | sudo tee /proc/sysrq-trigger    # état mémoire dans dmesg
kdump-config show ; sudo kdump-config load
timedatectl ; sudo hwclock --show ; cat /etc/adjtime
chronyc tracking ; chronyc sources -v ; chronyc makestep
cat /sys/devices/system/clocksource/clocksource0/current_clocksource
cat /proc/sys/fs/file-nr ; ulimit -n ; cat /proc/1234/limits
```

| Trace `dmesg` | Couche en cause |
|---|---|
| `Out of memory: Killed process` | mémoire, `oom_score_adj` (module 08) |
| `I/O error, dev sda, sector` | disque, câble, stockage hyperviseur |
| `BUG: soft lockup - CPU#0 stuck for 22s` | CPU volé (`st`), hôte saturé |
| `task X blocked for more than 120 seconds` | stockage ou NFS qui ne répond plus |
| `Kernel panic - not syncing` | fatal : `kdump` ou reboot |

chrony sur Ubuntu : `/etc/chrony/chrony.conf`, `conf.d/`, `sources.d/`,
`chrony.service`. Rocky : `/etc/chrony.conf`, `chronyd.service`. Ubuntu Server
livre `systemd-timesyncd` : installer chrony le remplace.

---

## 9.3 Quiz — QCM

**Q9.1** — `strace -c ls /` sur `lab-adm` compte 17 `mmap`, 7 `openat`,
2 `getdents64` et **un seul** `write`, alors que `ls` affiche 25 noms. Pourquoi
un seul `write` ?

a) `strace -c` ne compte que le premier appel de chaque type
b) `ls` écrit avec `printf`, fonction de la libc qui **tamponne** en espace
   utilisateur ; le tampon part en un seul `write` à la fin
c) le terminal regroupe les écritures
d) `getdents64` écrit directement sur la sortie standard

**Q9.2** — `cat /proc/2231/syscall` affiche `0 0x3 0x7f1c2a00 0x2000 ...`.
Que peut-on en conclure ? **Deux réponses correctes.**

a) le processus exécute l'appel numéro 0, `read`, sur le descripteur 3
b) il est en train de tourner en espace utilisateur
c) `ausyscall 0` confirme le nom de l'appel ; `/proc/2231/fd/3` dit sur quoi
   il lit
d) il attend un signal `SIGCONT`

**Q9.3** — Un processus est en `D` depuis dix minutes. Quelle affirmation est
juste ?

a) il consomme 100 % d'un cœur en espace noyau
b) il est bloqué **à l'intérieur** d'un appel système, en attente d'un pilote ;
   `/proc/PID/wchan` et `/proc/PID/stack` disent où, et le problème est en
   dessous (disque, NFS), pas dans le processus
c) `kill -9` le libère, puisque `SIGKILL` n'est pas attrapable
d) c'est un zombie que son père n'a pas récupéré

**Q9.4** — Sur une VM UEFI, quelle est la chaîne correcte ?

a) firmware → `/boot/grub/grub.cfg` → `vmlinuz` → initramfs → systemd
b) firmware → ESP (`shimx64.efi` → `grubx64.efi`) → `grub.cfg` → `vmlinuz` +
   initramfs → montage de `/` par l'initramfs → `systemd`
c) firmware → MBR → `vmlinuz` → `/etc/default/grub` → systemd
d) firmware → `systemd-boot` → `initramfs` → GRUB → `vmlinuz`

**Q9.5** — Tu ajoutes `net.ifnames=0` dans `GRUB_CMDLINE_LINUX` de
`/etc/default/grub`, tu redémarres, et `/proc/cmdline` ne contient pas le
paramètre. Cause la plus probable ?

a) le paramètre n'existe plus sur un noyau 6.8
b) `update-grub` n'a pas été lancé : GRUB lit `/boot/grub/grub.cfg`, pas
   `/etc/default/grub`
c) il fallait l'écrire dans `GRUB_CMDLINE_LINUX_DEFAULT`
d) il faut aussi régénérer l'initramfs

**Q9.6** — `/etc/default/grub` contient `GRUB_CMDLINE_LINUX_DEFAULT="quiet"`,
mais `/proc/cmdline` montre `console=tty1 console=ttyS0` et pas `quiet`, après
un `update-grub` correct. Où regarder ?

a) `/boot/grub/grub.cfg` a été édité à la main
b) `/etc/default/grub.d/*.cfg` : ces fichiers sont lus **après**
   `/etc/default/grub` et redéfinissent la variable
c) le firmware impose la console série
d) `GRUB_CMDLINE_LINUX_DEFAULT` n'est utilisé qu'en mode recovery

**Q9.7** — Dans quels cas faut-il régénérer l'initramfs ? **Deux réponses
correctes.**

a) après avoir ajouté un fichier `blacklist` dans `/etc/modprobe.d/` qui
   concerne un pilote de stockage ou de réseau
b) après avoir changé `vm.swappiness` dans `/etc/sysctl.d/`
c) après avoir déplacé `/` sur un volume LVM ou chiffré LUKS
d) après avoir modifié `/etc/hosts`

**Q9.8** — `apt upgrade` échoue : `update-initramfs: ... No space left on
device`, et `df -h /boot` affiche 100 %. Quelle action est **dangereuse** ?

a) `dpkg -l 'linux-image-*' | grep ^ii` puis `apt autoremove --purge`
b) supprimer les fichiers de `/boot` qui n'appartiennent à aucun paquet
   (`dpkg -S` ne les connaît pas), après avoir vérifié `uname -r`
c) `rm /boot/initrd.img-$(uname -r)` pour faire de la place immédiatement
d) purger explicitement un vieux `linux-image-6.8.0-31-generic` non courant

**Q9.9** — Sous Rocky 9, tu veux ajouter `console=ttyS0,115200` à tous les
noyaux installés **et** aux prochains. Que fais-tu ? **Deux réponses
correctes.**

a) `grubby --update-kernel=ALL --args="console=ttyS0,115200"`
b) éditer `GRUB_CMDLINE_LINUX` dans `/etc/default/grub`, pour que les noyaux
   installés plus tard héritent aussi de l'option
c) éditer `/boot/grub2/grub.cfg` à la main
d) `update-grub`

**Q9.10** — Que fait chaque fichier ?

```ini
# /etc/modprobe.d/dummy.conf
options dummy numdummies=2
# /etc/modules-load.d/dummy.conf
dummy
```

a) les deux chargent le module au boot
b) le premier fixe les paramètres **quand** le module est chargé, par qui que
   ce soit ; le second demande à `systemd-modules-load.service` de le charger
   au démarrage
c) le second fixe les paramètres, le premier charge
d) le premier est ignoré sans le second

**Q9.11** — `/etc/modprobe.d/x.conf` contient `blacklist virtio_net`. Quelles
affirmations sont vraies ? **Deux réponses correctes.**

a) `modprobe virtio_net` tapé à la main charge quand même le module
b) le chargement automatique par udev (via l'alias `virtio:d00000001v...`)
   est bloqué : plus de réseau au prochain boot
c) le module est supprimé de `/lib/modules`
d) le noyau refuse le module et écrit `module verification failed`

**Q9.12** — `/etc/sysctl.d/10-factura.conf` contient `vm.swappiness = 10`,
`/etc/sysctl.conf` contient `vm.swappiness = 60`. Valeur effective après reboot
sur Ubuntu 24.04 ?

a) 10, `/etc/sysctl.d` est prioritaire sur `/etc/sysctl.conf`
b) 60 : `/etc/sysctl.d/99-sysctl.conf` est un lien vers `/etc/sysctl.conf`,
   lu **après** `10-factura.conf`, et le dernier gagne
c) 60, parce que `sysctl.conf` est lu en premier et verrouille la valeur
d) erreur au boot, conflit détecté

**Q9.13** — `sudo sysctl -w net.netfilter.nf_conntrack_max=262144` répond
`sysctl: cannot stat /proc/sys/net/netfilter/nf_conntrack_max: No such file or
directory`. Explication et correctif durable ?

a) la clé a été renommée en `net.nf_conntrack_max`
b) le module `nf_conntrack` n'est pas chargé, donc la clé n'existe pas ; il faut
   `/etc/modules-load.d/nf_conntrack.conf` **et** le fichier `sysctl.d`, dans
   cet ordre au démarrage
c) il faut redémarrer pour que `sysctl` voie la clé
d) `sysctl -w` ne fonctionne qu'en mode `--system`

**Q9.14** — Tu écris `/etc/udev/rules.d/61-cache.rules` avec un `SYMLINK+=`,
mais `/dev/disk/lab/cache` n'apparaît pas. Le disque est déjà présent.
Que manque-t-il ?

a) un redémarrage obligatoire
b) `udevadm control --reload` (les règles sont mises en cache) **puis**
   `udevadm trigger` (les règles ne sont rejouées que sur un événement)
c) la règle doit être dans `/usr/lib/udev/rules.d`
d) `SYMLINK=` au lieu de `SYMLINK+=`

**Q9.15** — `dmesg` sur `lab-db` :

```text
INFO: task jbd2/dm-0-8:312 blocked for more than 120 seconds.
      Not tainted 6.8.0-52-generic #53-Ubuntu
"echo 0 > /proc/sys/kernel/hung_task_timeout_secs" disables this message.
```

Que faut-il comprendre ?

a) le CPU est saturé, il faut ajouter des vCPU
b) le thread de journal ext4 attend le stockage depuis deux minutes : l'E/S ne
   revient pas — regarder le disque, le stockage Proxmox, les erreurs E/S
   juste au-dessus, et les processus en `D`
c) le message conseille de désactiver le détecteur pour résoudre le problème
d) c'est un OOM déguisé

**Q9.16** — `watchdog: BUG: soft lockup - CPU#1 stuck for 23s!
[postgres:1204]` dans une VM Proxmox, sans autre erreur. Première hypothèse ?

a) bug de PostgreSQL
b) le vCPU n'a pas été ordonnancé par l'hôte pendant 23 s (hôte saturé,
   snapshot, sauvegarde, migration) : vérifier `st` dans `top` et l'hôte
c) barrette mémoire défectueuse
d) l'ordonnanceur E/S est mal réglé

**Q9.17** — `timedatectl` sur `lab-web` : `System clock synchronized: no`,
`NTP service: inactive`, et `curl https://` échoue avec `certificate is not yet
valid`. Que fais-tu ? **Deux réponses correctes.**

a) `chronyc makestep` après avoir démarré chrony, pour corriger d'un coup un
   décalage que le *slew* mettrait des heures à rattraper
b) vérifier `chronyc sources` : sans source joignable, chrony ne corrige rien
c) désactiver la vérification TLS (`curl -k`) sur tous les scripts
d) `hwclock --hctosys` toutes les minutes en cron

**Q9.18** — Un module DKMS compilé localement refuse de se charger :
`modprobe: ERROR: could not insert 'x': Key was rejected by service`.
Cause ?

a) le module dépend d'un autre module absent
b) Secure Boot est actif : le noyau n'accepte que les modules signés par une
   clé de confiance ; il faut signer le module avec une clé MOK enrôlée
   (`mokutil --import`) ou désactiver Secure Boot
c) `depmod -a` n'a pas été lancé
d) `kernel.modules_disabled` vaut 1

---

## 9.4 Quiz — questions ouvertes

**QO9.1** — *On te demande en entretien* : « Explique-moi ce qui se passe quand
un programme appelle `open()`. » Décris la frontière espace utilisateur /
espace noyau, le rôle de la libc, le changement de mode (et pourquoi ce n'est
pas un changement de contexte), le retour avec `errno`, et cite un cas où
un appel « système » ne passe **pas** par le noyau. Termine par ce qu'est un
processus en `D` dans ce modèle.

::: repondre
lignes: 10
:::

**QO9.2** — Déroule le démarrage d'une VM Ubuntu 24.04 en UEFI depuis
l'allumage jusqu'à l'invite `login:`, en nommant à chaque étape **le fichier
réel** chargé et **qui** le charge. Précise ce que change Secure Boot, ce que
fait exactement l'initramfs, et à quel moment `systemd` devient PID 1.

::: repondre
lignes: 12
:::

**QO9.3** — *On te demande en entretien* : « Mot de passe root perdu sur une VM,
pas de clé SSH, pas de sauvegarde du mot de passe. Tu fais quoi ? » Donne la
procédure complète sur Ubuntu **et** sur Rocky (touches GRUB, paramètre ajouté,
commandes dans le shell obtenu, pourquoi `mount -o remount,rw`, pourquoi
`/.autorelabel`), puis explique ce que ça prouve sur la sécurité physique
d'une machine et les deux contre-mesures.

::: repondre
lignes: 12
:::

**QO9.4** — À quoi sert l'initramfs, et pourquoi le noyau ne peut-il pas s'en
passer sur une machine dont `/` est sur LVM ? Explique la différence entre
`MODULES=most` et `MODULES=dep` (Ubuntu) ou `hostonly` (dracut), le compromis
taille / portabilité, comment vérifier qu'un pilote y est présent, et les
quatre situations où il faut le régénérer.

::: repondre
lignes: 10
:::

**QO9.5** — Décris ta méthode pour poser un paramètre `sysctl` en production
sans surprise : test à chaud, persistance, nom et rang du fichier, vérification
après `sysctl --system` puis après reboot. Explique l'ordre de précédence
complet et le cas particulier du paramètre qui n'existe qu'une fois un module
chargé, avec la solution.

::: repondre
lignes: 10
:::

**QO9.6** — Un disque est ajouté à chaud à une VM. Explique la chaîne complète :
qui détecte le matériel, ce qu'est un *uevent*, ce que fait `udevd`, comment
sont produits `/dev/sdb` et les liens `/dev/disk/by-*`, et pourquoi `sdb`
n'est pas un nom stable. Donne la règle udev qui crée un lien stable, et dis
comment tu la testes **sans** redémarrer.

::: repondre
lignes: 10
:::

**QO9.7** — Pour chacune de ces quatre traces du journal noyau — OOM, erreur E/S,
*soft lockup*, *hung task* — dis ce qu'elle signifie, quelle couche est en cause,
quelle commande tu lances ensuite, et ce qui distingue une VM d'une machine
physique dans l'interprétation. Termine par le rôle de `kdump` et ce qu'il
faut avoir configuré **avant** l'incident.

::: repondre
lignes: 12
:::

**QO9.8** — Pourquoi l'heure d'une VM dérive-t-elle plus qu'une machine
physique ? Explique horloge matérielle vs horloge système, ce que fait chrony
(*slew* vs *step*, `makestep`), ce que `timedatectl` te montre, et liste au
moins cinq choses concrètes qui cassent avec cinq minutes de décalage.

::: repondre
lignes: 10
:::

**QO9.9** — *On te demande en entretien* : « Linux est-il un noyau monolithique
? Et c'est quoi eBPF, le live patching, le temps réel ? » Réponds en deux
minutes chrono : une définition, un exemple concret d'usage ops pour chaque
notion, et une commande ou un produit qui l'incarne.

::: repondre
lignes: 10
:::

---

## 9.5 Exercices guidés ★

**E9.1** — Sur `lab-adm`, compte les appels système d'un `ls -l /etc`, affiche
les cinq plus fréquents, et explique pourquoi `readdir` et `printf`
n'apparaissent pas dans la liste alors que `ls` les utilise. Puis montre, en
une commande, la liste des **fichiers** que `ls` a réellement ouverts.

**E9.2** — Lance `sleep 300 &`, puis, uniquement à partir de `/proc`, affiche
l'appel système dans lequel il est bloqué (numéro **et** nom, traduit par
`ausyscall`), la fonction noyau où il dort, et son état dans `status`.
Compare avec un processus qui tourne (`yes > /dev/null &`).

**E9.3** — Affiche la ligne de commande du noyau actuel, puis retrouve d'où vient
chaque paramètre : dans `/etc/default/grub`, dans `/etc/default/grub.d/*.cfg`, ou
dans `/boot/grub/grub.cfg` seulement. Pour chaque paramètre, une ligne
« paramètre → fichier d'origine → effet ».

**E9.4** — Détermine si `lab-adm` démarre en BIOS ou en UEFI, par deux moyens
indépendants. Si UEFI : liste les entrées du firmware, l'ordre de boot, la
partition ESP et les fichiers `.efi` qu'elle contient avec leur taille. Si
BIOS : trouve où GRUB est installé (`grub-probe`, partition `BIOS boot`).

**E9.5** — Liste le contenu de l'initramfs du noyau courant, compte les
modules `.ko` qu'il embarque, vérifie que `virtio_scsi`, `virtio_net` et `lvm`
y sont, et affiche la taille de l'initrd comparée à celle de `vmlinuz`. Puis
montre le contenu de `/etc/initramfs-tools/initramfs.conf` qui explique cette
taille.

**E9.6** — Mesure le temps de démarrage de `lab-adm` (firmware, chargeur,
noyau, espace utilisateur), les dix unités les plus lentes, la chaîne critique
jusqu'à `multi-user.target`, et produis `~/lab09/rapports/boot.svg`. Dis quelle
unité tu attaquerais en premier et pourquoi.

**E9.7** — Inventaire des noyaux : version qui tourne, versions installées
(paquets), fichiers correspondants dans `/boot` avec leur taille, espace libre
de `/boot`, et entrée GRUB par défaut. Déduis combien de noyaux
supplémentaires `/boot` peut accueillir.

**E9.8** — Pour le pilote de l'interface `ens18` et celui du disque `sda` :
trouve le nom du module depuis `/sys` (pas depuis `lsmod`), affiche sa
description, ses dépendances, son signataire, et ses paramètres possibles.
Liste enfin tous les modules `virtio*` chargés avec leur compteur d'usage.

**E9.9** — Lance `udevadm monitor` dans un terminal ; dans un autre, charge
le module `dummy` avec deux interfaces, prouve la valeur du paramètre par
`/sys`, affiche les interfaces créées, puis décharge le module. Relève les
événements `add`/`remove` reçus, côté noyau et côté udev. Montre ensuite ce
que `modprobe --show-depends` et `modules.dep` disent de `dummy`.

**E9.10** — Depuis `/proc` uniquement : nombre de cœurs, présence du drapeau
`hypervisor`, mémoire totale / disponible / *dirty*, interruptions attribuées
aux périphériques virtio, et pour le processus `sshd` principal : ses
descripteurs, ses limites, son cgroup, son environnement, son binaire.

**E9.11** — Deux réglages volatils de `/sys`. D'abord l'ordonnanceur E/S de
`/dev/sda` : affiche l'actif et les choix possibles, passe-le à `none` à
chaud, vérifie, reviens à la valeur initiale ; explique pourquoi `none` est
raisonnable pour un disque virtio sur un SSD hôte et pourquoi le réglage ne
survit pas au reboot. Ensuite les *transparent hugepages* : affiche `enabled`
et `defrag`, passe `enabled` à `never` à chaud, et donne les deux méthodes
pour rendre ce réglage persistant (l'une par le noyau, l'autre par systemd)
sans les appliquer.

**E9.12** — Pose `vm.swappiness=10` et `net.core.somaxconn=8192` de façon
persistante dans un fichier correctement nommé, applique sans reboot, prouve
les valeurs, puis affiche l'ordre exact dans lequel `sysctl --system` a lu
les fichiers. Vérifie qu'aucun fichier de rang supérieur ne les écrase.

**E9.13** — Démontre le piège du paramètre absent : tente de lire
`net.netfilter.nf_conntrack_max` sur une machine sans règle de filtrage,
charge le module qui le fait apparaître, relis, puis écris la configuration
qui rend la valeur `131072` persistante **à travers un reboot**.

**E9.14** — Affiche les messages noyau d'avertissement et d'erreur du boot
courant avec horodatage lisible, puis ceux du boot précédent, puis les quatre
valeurs de `kernel.printk` avec leur sens. Enfin, provoque un vidage de l'état
mémoire par SysRq et retrouve-le dans `dmesg`.

**E9.15** — Sur `lab-adm` : affiche l'heure système, l'heure matérielle, le
fuseau, la source d'horloge du noyau, et l'état de la synchronisation. Calcule
le décalage entre horloge système et horloge matérielle. Dis quel service NTP
tourne par défaut sur Ubuntu Server 24.04 et sur Rocky 9.

**E9.16** — Montre les trois niveaux de limite de fichiers ouverts (système,
par processus maximal, par processus effectif) et le nombre actuellement
alloué. Puis trouve quel processus consomme le plus de *watches* inotify et
compare à la limite. Explique quelle limite produit « too many open files » dans
chaque cas.

---

## 9.6 Labs ★★

### **L9.1** — Ticket INC-3402 : « Documenter le démarrage de lab-adm et
ouvrir une console de secours »

::: contexte
Après un incident où plus personne n'a pu se connecter à une VM en panne
réseau, l'équipe exige que chaque VM ait une console série exploitable depuis
Proxmox (`qm terminal`), un menu GRUB visible, et une fiche décrivant sa chaîne
de démarrage avec les vrais fichiers. `lab-adm` sert de modèle.
:::

1. Établis le mode de démarrage (BIOS ou UEFI) et, selon le cas, la partition
   ESP et ses fichiers, ou l'emplacement de GRUB. Note la taille de
   `/boot/efi` ou de la partition `BIOS boot`.
2. Relève la configuration GRUB effective : `/etc/default/grub`, les fichiers
   de `/etc/default/grub.d/`, puis les lignes `menuentry` et `linux` de
   `grub.cfg`. Repère `GRUB_TIMEOUT` et `GRUB_TIMEOUT_STYLE`.
3. Rends le menu **visible 5 secondes** au démarrage, et ajoute une console
   série : `console=tty0 console=ttyS0,115200` côté noyau, et GRUB lui-même
   sur le port série (`GRUB_TERMINAL`, `GRUB_SERIAL_COMMAND`). Régénère.
   Vérifie dans le fichier généré que les lignes `linux` portent bien les
   paramètres **avant** de redémarrer.
4. Redémarre. Depuis le shell Proxmox, `qm terminal 9001` : tu dois voir le
   menu GRUB, puis les messages du noyau, puis une invite `login:`. Connecte-toi.
   Prouve depuis cette session : `/proc/cmdline`, `tty`, et l'unité
   `serial-getty@ttyS0.service`.
5. Toujours dans la console série, redémarre et interromps GRUB : édite l'entrée
   par défaut (`e`), ajoute `systemd.unit=rescue.target`, démarre. Constate ce
   que demande Ubuntu et pourquoi ça bloque. Recommence avec `init=/bin/bash`,
   obtiens un shell, monte la racine en écriture, lis `/etc/hostname`, puis
   redémarre proprement (`exec /sbin/init` ou `reboot -f`). Note dans le
   rapport pourquoi la deuxième méthode marche et pas la première.
6. Mesure le boot : `systemd-analyze`, `blame`, `critical-chain`, et
   `~/lab09/rapports/boot.svg`.
7. Rédige `~/lab09/rapports/demarrage.md` : mode de démarrage, chaîne complète
   avec un chemin de fichier réel et sa taille par étape, ligne de commande du
   noyau commentée, temps de boot, procédure de console de secours en cinq
   lignes, et procédure « mot de passe perdu » en cinq lignes.

::: rhel
Sur `lab-rhel`, fais la partie console série : `grubby --update-kernel=ALL
--args="console=tty0 console=ttyS0,115200"`, `GRUB_TERMINAL`/`GRUB_SERIAL_COMMAND`
dans `/etc/default/grub`, puis `grub2-mkconfig -o /boot/grub2/grub.cfg`.
Regarde ce que `grubby` a modifié dans `/boot/loader/entries/`. Le shell de
secours s'obtient avec `rd.break` puis `chroot /sysroot`.
:::

::: check
Critère de succès : `/proc/cmdline` contient `console=ttyS0`, le menu GRUB est
visible au moins 5 s, `serial-getty@ttyS0.service` est actif, `boot.svg` et
`demarrage.md` existent.

```bash
bash check_M09_01.sh
```
:::

---

### **L9.2** — Passer `lab-adm` au noyau HWE et tenir `/boot` propre

::: contexte
Un pilote dont l'équipe a besoin n'existe que dans un noyau plus récent que le
6.8 livré avec Ubuntu 24.04. On te demande de passer `lab-adm` au noyau HWE
(*Hardware Enablement*), de garder un noyau de repli, et de rédiger la règle
d'exploitation « combien de noyaux garder, comment purger, que faire si `/boot`
est plein ». Variante Rocky sur `lab-rhel`.
:::

1. Inventaire avant : `uname -r`, paquets `linux-image-*` installés, contenu et
   taille de `/boot`, espace libre, entrée GRUB par défaut. Garde une copie dans
   `~/lab09/rapports/noyaux-avant.txt`.
2. Installe le métapaquet HWE. Avant de redémarrer, vérifie dans `grub.cfg`
   que le nouveau noyau est **la première** entrée, et que son initrd existe
   dans `/boot` avec une taille cohérente.
3. Redémarre, prouve avec `uname -r` que tu tournes sur le HWE, et note la
   version du 6.8 conservée comme repli.
4. Depuis `qm terminal 9001`, redémarre et choisis manuellement l'ancien
   noyau dans le sous-menu *Advanced options*. Prouve par `uname -r`, puis
   reviens sur le HWE. Explique dans le rapport comment fixer durablement le
   noyau de repli comme défaut si le HWE posait problème (`GRUB_DEFAULT=`
   avec l'identifiant de l'entrée, pas son numéro).
5. Purge tout noyau autre que les deux à garder (le HWE courant et le dernier
   6.8). Montre que `apt` **refuse** de supprimer le noyau en cours si tu
   l'y forces, et explique le mécanisme qui protège le noyau courant de
   `autoremove`.
6. Simule « `/boot` plein » sans le remplir : calcule, à partir des tailles
   réelles de `vmlinuz` + `initrd` + `System.map` + `config`, combien de
   versions tiennent dans ta partition `/boot`, et à partir de quel nombre
   `update-initramfs` échouerait.
7. Rapport `~/lab09/rapports/noyaux.md` : avant/après, règle « garder N
   noyaux », procédure de purge en 4 commandes, procédure `/boot` plein en
   5 lignes, et une section Secure Boot : état sur `lab-adm`
   (`mokutil --sb-state`), signataire du noyau (`dmesg | grep -i secure`,
   `modinfo -F signer virtio_net`), et ce qu'il faudrait faire pour un module
   DKMS.

::: rhel
Sur `lab-rhel` : `grubby --info=ALL`, `grubby --default-kernel`,
`dnf list installed 'kernel*'`, `installonly_limit` dans `/etc/dnf/dnf.conf`,
`dnf install kernel` (ou `dnf check-update kernel` s'il n'y a rien de plus
récent), `grubby --set-default`, `dnf remove --oldinstallonly`. Explique la
différence entre `kernel`, `kernel-core` et `kernel-modules`, et vérifie que
`dnf` refuse de retirer le noyau en cours.
:::

::: check
Critère de succès : `uname -r` n'est plus un 6.8, le métapaquet HWE est
installé, au plus deux versions de noyau sont présentes, `/boot` a plus de
30 % d'espace libre, et le rapport existe.

```bash
bash check_M09_02.sh
```
:::

---

### **L9.3** — Modules : une interface de test, un module interdit, un
inventaire virtio

::: contexte
L'équipe supervision veut une interface réseau « factice » persistante sur
`lab-adm` (deux interfaces `dummy`, adresse fixe, pour tester des sondes sans
toucher au réseau réel). L'audit demande aussi de bloquer un module inutile
sur une VM et de documenter les pilotes virtio en jeu. Tout doit survivre à un
reboot.
:::

1. Inventaire virtio : liste les modules `virtio*` chargés, et pour `ens18` et
   `sda`, remonte du périphérique au pilote via `/sys` (`device/driver`).
   Note le résultat sous forme de tableau (périphérique, pilote, module, bus).
2. Charge `dummy` avec `numdummies=2` à la main, vérifie `dummy0`/`dummy1` et
   la valeur dans `/sys/module/dummy/parameters/`. Décharge.
3. Rends-le persistant : paramètre dans `/etc/modprobe.d/`, chargement au boot
   dans `/etc/modules-load.d/`. Applique **sans reboot** en redémarrant l'unité
   systemd concernée, et prouve que le paramètre est bien pris (deux
   interfaces, pas une).
4. Donne à `dummy0` l'adresse `10.10.99.10/32` de façon persistante avec
   Netplan (fichier séparé dans `/etc/netplan/`, sans toucher au fichier
   existant). `netplan try` puis `apply`.
5. Blacklist : identifie un module chargé mais inutile sur une VM (`joydev`,
   sinon `mac_hid` ou `pcspkr` si présent), interdis-le de façon à bloquer
   **aussi** un `modprobe` explicite, régénère ce qu'il faut, redémarre, et
   prouve qu'il n'est plus chargé. Montre que `lsinitramfs` embarque ton
   fichier de `modprobe.d`, et explique pourquoi c'est important pour un
   pilote de stockage.
6. Reboot final : `dummy0` et `dummy1` existent, l'adresse est là, le module
   interdit est absent.
7. Rapport `~/lab09/rapports/modules.md` : tableau virtio, fichiers créés avec
   leur contenu, différence `blacklist` / `install /bin/false`, et une note
   sur DKMS (à quoi ça sert, où voir l'état).

::: rhel
Sur `lab-rhel` : mêmes fichiers `modprobe.d` et `modules-load.d`. L'adresse
va dans NetworkManager (`nmcli con add type dummy ifname dummy0 con-name
dummy0 ip4 10.10.99.13/32`). Régénère l'initramfs avec `dracut -f` et vérifie
avec `lsinitrd | grep modprobe.d`.
:::

::: check
Critère de succès : après reboot, `dummy0` et `dummy1` existent,
`numdummies` vaut 2, `dummy0` porte `10.10.99.10`, le module choisi est
interdit dans `/etc/modprobe.d/` et absent de `lsmod`, le rapport existe.

```bash
bash check_M09_03.sh
```
:::

---

### **L9.4** — Un disque à chaud, un nom stable, un ordonnanceur adapté

::: contexte
Ticket : « ajouter 1 Go de cache disque à `lab-adm`, sans redémarrer, avec un
nom de périphérique qui ne change jamais, ordonnanceur E/S `none` sur ce
disque, et documenter la procédure d'agrandissement ». Tu opères depuis le
shell Proxmox et depuis `lab-adm`.
:::

1. Ouvre un second terminal sur `lab-adm` avec `udevadm monitor -u -k`.
   Depuis Proxmox : `qm set 9001 --scsi1 local-lvm:1`. Observe les événements
   `add` (noyau puis udev). Si rien n'arrive, force un *rescan* SCSI et note
   la différence.
2. Identifie le nouveau disque (`lsblk -o NAME,SIZE,HCTL,SERIAL,TRAN`), sa
   propriété `ID_SERIAL` et son `ID_PATH` avec `udevadm info`. Liste ses liens
   dans `/dev/disk/by-*` et explique pourquoi `by-uuid` et `by-label` sont
   vides pour l'instant.
3. Écris `/etc/udev/rules.d/61-lab-disque.rules` qui, pour **ce** disque
   identifié par `ID_SERIAL` : crée le lien `/dev/disk/lab/cache`, et fixe
   `queue/scheduler` à `none`. Teste la règle à blanc avec `udevadm test`,
   recharge, rejoue l'événement, et prouve le lien et l'ordonnanceur.
4. Formate-le en ext4 avec le label `cache` (une commande, via le lien stable).
   Montre que `/dev/disk/by-label/cache` est apparu **sans** que tu aies rien
   demandé, et explique par quelle règle udev livrée avec le système.
5. Agrandis le disque à chaud de 1 Go côté Proxmox (`qm disk resize 9001
   scsi1 +1G`). Depuis la VM, fais voir la nouvelle taille au noyau sans
   reboot, puis agrandis le système de fichiers.
6. Nom d'interface stable : dans `~/lab09/udev/`, écris **sans l'installer**
   les deux façons de nommer `ens18` en `lan0` par son adresse MAC (règle udev
   et fichier `.link` systemd). Valide la syntaxe de la règle avec
   `udevadm test /sys/class/net/ens18` en la plaçant temporairement dans
   `/run/udev/rules.d/` (volatile), lis la ligne `NAME`, puis retire-la.
   Explique dans le rapport ce qui se passerait avec Netplan si tu
   l'installais pour de bon (c'est le sujet de BF9.4).
7. Rapport `~/lab09/rapports/udev.md` : chaîne uevent → udevd → règle → `/dev`,
   la règle écrite, la procédure hotplug + resize en 6 lignes, et une phrase
   sur `/dev/sdb` vs `by-id`.

::: check
Critère de succès : `/dev/disk/lab/cache` pointe sur un disque de 2 Go dont
l'ordonnanceur est `none`, ce disque porte un système de fichiers ext4
labellisé `cache`, la règle existe, le rapport existe.

```bash
bash check_M09_04.sh
```
:::

---

### **L9.5** — Un serveur de temps pour le lab, et une horloge qui dérive

::: contexte
Les journaux des VM ne sont pas alignés et un certificat interne a été refusé
« pas encore valide » sur `lab-web`. On te demande un serveur NTP de lab sur
`lab-adm`, que toutes les VM l'utilisent, et un rapport sur la dérive.
:::

1. Sur `lab-adm` : relève l'état initial avec `timedatectl` (quel service NTP ?
   synchronisé ?), l'heure matérielle, et le décalage éventuel. Installe
   chrony et constate ce qu'est devenu `systemd-timesyncd`.
2. Configure `lab-adm` en serveur : sources amont (pool Ubuntu ou
   `10.10.10.1` si ta passerelle sert NTP), autorisation du réseau
   `10.10.10.0/24`, et strate locale de secours (`local stratum 10`) pour
   continuer à servir le lab si Internet tombe. Utilise le répertoire
   `conf.d/` plutôt que d'éditer le fichier principal. Vérifie `tracking`,
   `sources -v`, et l'écoute UDP 123.
3. Sur `lab-web` : installe chrony, remplace les pools publics par
   `lab-adm` uniquement (`sources.d/`, et neutralise les `pool` du fichier
   principal), redémarre, vérifie que la source est `10.10.10.10` avec `^*`.
   Sur `lab-adm`, prouve le client avec `chronyc clients`.
4. Sur `lab-rhel` : même chose dans `/etc/chrony.conf`, service `chronyd`.
   Vérifie avec `chronyc sources`. Note la différence de noms d'unité et de
   fichiers entre les deux distributions.
5. Dérive contrôlée sur `lab-web` : avance l'horloge système de 3 minutes
   (`date -s`), observe `chronyc tracking` toutes les 10 s pendant une minute
   (`System time`, `Last offset`, `Frequency`). Calcule combien de temps le
   *slew* mettrait à rattraper 180 s à la vitesse maximale de chrony, puis
   force la correction et prouve-la. Explique la directive `makestep` du
   fichier livré et pourquoi elle n'a pas joué ici.
6. Fuseaux : mets `lab-adm` en `Europe/Paris`, montre que `date`, `journalctl`
   et `ls -l` suivent le fuseau alors que l'horloge système et le RTC restent
   en UTC. Explique pourquoi on garde le RTC en UTC sur un serveur.
7. Rapport `~/lab09/rapports/temps.md` : schéma RTC → horloge système →
   chrony → clients, fichiers modifiés sur les trois VM, sortie de `tracking`
   avant/après, calcul du *slew*, et liste de ce qu'un décalage de 5 minutes
   casse.

::: check
Critère de succès : sur `lab-adm`, chrony est actif et écoute en UDP 123,
`systemd-timesyncd` est inactif, la configuration autorise `10.10.10.0/24`,
`chronyc tracking` indique `Leap status : Normal`, au moins un client est vu,
le fuseau est `Europe/Paris`, le rapport existe.

```bash
bash check_M09_05.sh
```
:::

---

## 9.7 Break & Fix ★★★

::: attention
Avant chaque Break & Fix : `qm snapshot 9001 avant-bf09`. Trois pannes (BF9.3,
BF9.4, BF9.5) te privent de SSH ou de TLS : la console série de L9.1
(`qm terminal 9001`) est ton seul accès. Le snapshot de secours reste
`snap-clean`, mais y revenir vaut échec de l'exercice.
:::

### **BF9.1** — « La mise à jour du noyau échoue et `apt` ne veut plus rien faire »

```bash
sudo bash break_M09_01.sh
```

**Symptôme utilisateur** : `sudo apt upgrade` (comme `sudo update-initramfs
-u`) s'arrête sur `update-initramfs: failed for /boot/initrd.img-... with 1`
précédé de `No space left on device`, et `apt` refuse depuis toute mise à jour
de noyau. `df -h /` montre pourtant 60 % d'espace libre. Le collègue jure qu'il
ne stocke rien sur cette VM et qu'il n'a « jamais installé plus de deux
noyaux ».

**Interdit** : agrandir la partition, supprimer l'initrd ou le `vmlinuz` du
noyau **en cours**, réinstaller le système.

**Objectif** : identifier ce qui remplit la partition concernée (tout n'est pas
géré par `dpkg`), libérer proprement en distinguant ce qui appartient à un
paquet de ce qui n'appartient à rien, vérifier que `dpkg` n'a rien laissé à
moitié configuré, régénérer l'initramfs, et laisser une règle qui empêche la
récidive.

::: repondre
lignes: 10
:::

### **BF9.2** — « Le swappiness revient à 60 à chaque reboot »

```bash
sudo bash break_M09_02.sh
```

**Symptôme utilisateur** : l'équipe base de données a demandé `vm.swappiness=10`
et `net.core.somaxconn=8192` sur `lab-adm`, et le fichier est bien là dans
`/etc/sysctl.d/`. Après reboot, `sysctl vm.swappiness` répond 60 et
`somaxconn` 4096. En plus, `systemd-sysctl.service` affiche un avertissement
au démarrage que personne ne lit. `sudo sysctl -p /etc/sysctl.d/<fichier>`
« marche », jusqu'au reboot suivant.

**Interdit** : mettre les valeurs dans un script `rc.local`, dans un cron
`@reboot`, ou dans une unité systemd maison.

**Objectif** : expliquer les **trois** raisons distinctes pour lesquelles ces
valeurs ne tiennent pas (il y en a bien trois), corriger sans rien ajouter
d'exotique, prouver avec `sysctl --system` que la lecture se fait dans le bon
ordre, et vérifier après reboot.

::: repondre
lignes: 10
:::

### **BF9.3** — « Depuis le reboot, la VM n'a plus de réseau »

```bash
sudo bash break_M09_03.sh
sudo reboot
```

**Symptôme utilisateur** : après un durcissement « suppression des pilotes
inutiles » appliqué par un playbook, `lab-adm` ne répond plus au ping ni au
SSH. Sur la console, `ip link` ne montre que `lo` (et les `dummy` si tu as fait
L9.3). Personne ne connaît le mot de passe local de `mathieu` — considère-le
comme inconnu, **comme en production** : tu n'as pas le droit de t'en servir
sur la console.

**Interdit** : `qm rollback`, monter le disque depuis une autre VM, utiliser un
mot de passe local.

**Objectif** : reprendre la main via GRUB (console série), trouver la cause
dans la configuration des modules, corriger, régénérer ce qui doit l'être,
redémarrer et retrouver le réseau. Dans le rapport : pourquoi
`systemd.unit=rescue.target` ne convenait pas ici, pourquoi la ligne fautive
bloquait le chargement **automatique** alors qu'elle n'empêche pas un
`modprobe` à la main, et pourquoi régénérer l'initramfs même si le réseau n'y
est pas nécessaire.

::: repondre
lignes: 12
:::

### **BF9.4** — « L'interface a changé de nom et Netplan ne trouve plus rien »

```bash
sudo bash break_M09_04.sh
sudo reboot
```

**Symptôme utilisateur** : `lab-adm` redémarre sans adresse IP. Sur la
console, l'interface existe et le pilote est chargé, mais elle ne s'appelle
plus `ens18`, et `netplan apply` affirme que le fichier de configuration est
correct. Un collègue avait « juste ajouté une règle pour que le nom soit
stable ».

**Interdit** : réécrire le fichier Netplan avec le nouveau nom (l'équipe
veut retrouver `ens18`), désactiver udev.

**Objectif** : retrouver la règle, expliquer le mécanisme de nommage (qui
décide du nom, à quel moment, ce qui a la priorité entre une règle udev, un
fichier `.link` et Netplan `set-name`), rétablir le réseau **sans reboot**
d'abord, puis proprement au reboot. Proposer la bonne façon de figer un nom
d'interface si l'équipe y tient vraiment.

::: repondre
lignes: 10
:::

### **BF9.5** — « Tout ce qui est en HTTPS échoue depuis ce matin »

```bash
sudo bash break_M09_05.sh
```

**Symptôme utilisateur** : sur `lab-adm`, `apt update` échoue avec
`Release file ... is not valid yet (invalid for another 44d ...)`, `curl
https://` refuse les certificats récents (`certificate is not yet valid`), et les journaux affichent des dates
« dans le passé ». Le réseau fonctionne. Le collègue a « peut-être touché à
l'heure pour tester un script ».

**Interdit** : `curl -k`, `apt -o Acquire::Check-Valid-Until=false`, régler
l'heure à la main avec `date -s` sur la bonne valeur (ça doit être le service
de temps qui corrige).

**Objectif** : diagnostiquer avec `timedatectl` et `chronyc`, comprendre
pourquoi chrony ne corrige pas tout seul (deux raisons), remettre l'heure
juste par le service de temps, vérifier TLS et `apt`, expliquer pourquoi
l'heure matérielle avait aussi dérivé, et laisser une supervision minimale
(commande ou métrique) qui aurait détecté le problème avant les utilisateurs.

::: repondre
lignes: 10
:::

---

## 9.8 Défi du module ★★★

**D9 — Une base noyau de production pour les VM Factura**

::: contexte
Les VM de l'application Factura (`lab-web`, `lab-db`) vont être clonées à
partir d'un modèle. On te demande de définir sur `lab-adm` la « base noyau »
que chaque VM devra embarquer, de la rendre vérifiable par un script, et de
la documenter. Ansible la déploiera plus tard (module 23) : ce qui compte
ici, ce sont les bons fichiers aux bons endroits et une justification par
réglage.
:::

Cahier des charges :

1. **Paramètres noyau** dans **un seul** fichier `/etc/sysctl.d/60-factura.conf`,
   avec un commentaire d'une ligne par paramètre : `vm.swappiness=10`,
   `vm.dirty_background_ratio=5`, `vm.dirty_ratio=10`,
   `net.core.somaxconn=8192`, `net.ipv4.ip_local_port_range=10240 65000`,
   `fs.inotify.max_user_watches=524288`, `kernel.panic=10`,
   `kernel.kptr_restrict=2`, `kernel.dmesg_restrict=1`, `kernel.sysrq=176`,
   `net.ipv4.ip_forward=0`, `net.netfilter.nf_conntrack_max=131072`. Le
   fichier doit s'appliquer **intégralement** au boot, sans avertissement de
   `systemd-sysctl` : le dernier paramètre impose un prérequis que tu dois
   résoudre proprement.
2. **Ligne de commande du noyau** : console série (`console=tty0
   console=ttyS0,115200`) et `transparent_hugepage=madvise`. Justifie dans le
   rapport pourquoi tu **n'ajoutes pas** `mitigations=off` malgré la demande
   du dev qui veut « +10 % de perf », et pourquoi le reboot après panic se
   règle par `kernel.panic` (sysctl) plutôt que par `panic=` sur la ligne du
   noyau. Applique et vérifie après reboot.
3. **kdump** activé : réservation `crashkernel=` adaptée à 2 Go de RAM, service
   chargé, `kdump-config show` conforme, et **un test réel** : provoque un
   crash par SysRq (`c`) et retrouve le dump dans `/var/crash/`. Note la
   durée totale de l'opération.
4. **Modules** : `nf_conntrack` chargé au boot, `joydev` (ou celui de L9.3)
   interdit, initramfs régénéré.
5. **Temps** : chrony client de `lab-adm` (pour les VM clonées : mets le
   fichier tel qu'il sera sur `lab-web`, en le rangeant dans
   `~/lab09/conf/chrony-client.conf`).
6. **Le script de conformité** `~/lab09/bin/verif-noyau.sh`, bash,
   `set -euo pipefail`, sans argument, une ligne `[ OK ]`/`[FAIL]` par point,
   code de sortie 0/1 :
   * chaque paramètre du point 1 a sa valeur **effective** (`sysctl -n`) ;
   * `nf_conntrack` chargé ; `joydev` absent et interdit ;
   * `/proc/cmdline` contient `console=ttyS0` et `transparent_hugepage=madvise`,
     ne contient pas `mitigations=off` ;
   * `kdump` prêt (`kdump-config show` ou `/sys/kernel/kexec_crash_loaded`) ;
   * `/boot` occupé à moins de 70 % ; au plus 2 versions de noyau ;
   * horloge synchronisée (`timedatectl` ou `chronyc tracking`) ;
   * `kernel.dmesg_restrict` à 1 et `kernel.kptr_restrict` à 2 (lus via
     `/proc/sys`, pas via le fichier).
7. **Le rapport** `~/lab09/rapports/base-noyau.md` : un tableau par famille
   (mémoire, réseau, sécurité, robustesse) avec valeur, justification en une
   ligne, et effet de bord connu ; la sortie du script ; la durée du test kdump.

Temps visé : 60 à 90 minutes.

::: check
```bash
bash check_M09_06.sh
```
:::

---

## 9.9 Auto-évaluation

| Compétence | Acquis | À revoir |
|---|---|---|
| Expliquer appel système, libc, changement de mode, état `D` | ☐ | ☐ |
| Dérouler la chaîne de boot UEFI/BIOS avec les fichiers réels | ☐ | ☐ |
| Modifier la ligne de commande noyau (Ubuntu et Rocky) et vérifier | ☐ | ☐ |
| Éditer une entrée GRUB au boot, `init=/bin/bash`, mot de passe perdu | ☐ | ☐ |
| Expliquer, inspecter et régénérer l'initramfs, savoir quand | ☐ | ☐ |
| Gérer plusieurs noyaux, HWE, purge, `/boot` plein | ☐ | ☐ |
| Charger, paramétrer, blacklister, rendre persistant un module | ☐ | ☐ |
| Lire `/proc` et `/sys`, changer un ordonnanceur E/S, THP | ☐ | ☐ |
| Poser un `sysctl` au bon rang et éviter le piège du module absent | ☐ | ☐ |
| Écrire et tester une règle udev, brancher un disque à chaud | ☐ | ☐ |
| Reconnaître OOM, erreur E/S, soft lockup, hung task ; activer kdump | ☐ | ☐ |
| Configurer chrony serveur/client, expliquer la dérive d'une VM | ☐ | ☐ |
| Répondre sur monolithique/modulaire, eBPF, live patching, temps réel | ☐ | ☐ |

Pour aller plus loin :

* Lis `man 7 bootup` et `man 7 kernel-command-line` : la première page décrit
  exactement l'enchaînement initramfs → systemd, la seconde liste tous les
  paramètres que systemd lui-même lit sur la ligne du noyau.
* Sur le snapshot, teste `kernel.modules_disabled=1` puis essaie de charger
  un module : c'est un aller simple jusqu'au reboot, et c'est ce que certains
  profils de durcissement imposent.
* Écris trois one-liners `bpftrace` : compter les `openat` par processus,
  afficher les `execve` avec leurs arguments, mesurer la latence des `read`
  sur `sda`. Compare le coût avec `strace` (module 19).
