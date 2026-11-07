# Module 09 — Corrigé

## 9.3 Quiz — QCM

**Q9.1** — *`strace -c ls /` : 25 noms affichés, un seul `write`. Pourquoi ?*

**Réponse : b)** `printf` tamponne en espace utilisateur.

::: pourquoi
`strace` ne voit que ce qui franchit la frontière noyau : les **appels
système**. `printf`, `readdir`, `malloc` sont des fonctions de la libc qui
vivent en espace utilisateur ; elles n'apparaissent jamais dans `strace`.

La libc (glibc) gère un tampon de sortie : tant que la sortie standard n'est
pas un terminal, ou tant que le tampon (4 Ko à 8 Ko) n'est pas plein, rien ne
part. `ls` construit toute sa sortie en mémoire, puis, au `exit()`, la libc
vide le tampon : **un** `write(1, "bin\nboot\n...", 190)`. Sur un terminal, la
sortie est *line-buffered* : tu verrais alors un `write` par ligne — d'où une
différence de comptage entre `strace -c ls` (terminal) et
`strace -c -o out ls > /dev/null`.

Même logique pour `readdir` : la libc appelle `getdents64` avec un gros tampon
(32 Ko) et sert les entrées une à une depuis ce tampon. Deux appels
`getdents64` suffisent pour 25 entrées (le second retourne 0 = fin). C'est
tout l'intérêt de la libc : **amortir** le coût d'un passage en mode noyau.
:::

::: piege
« `strace` montre tout ce que fait un programme » est faux. Il montre les
appels système ; `ltrace` montre les appels de bibliothèque ; `perf` montre
où part le temps CPU. Et `strace -c` sur un programme court affiche des durées
à 0.000000 : les appels sont trop rapides pour la résolution du compteur, seul
le **nombre** est significatif ici. L'analyse fine est au module 19.
:::

---

**Q9.2** — *`/proc/2231/syscall` affiche `0 0x3 0x7f1c2a00 0x2000 ...` (deux
réponses).*

**Réponses : a) et c)**

::: pourquoi
Le format de `/proc/PID/syscall` est : numéro d'appel, six arguments, pointeur
de pile, pointeur d'instruction. `0` sur x86_64 est `read` (`ausyscall 0` →
`read`, `ausyscall --dump` pour toute la table). Les arguments sont ceux de
`read(fd, buf, count)` : le descripteur `3`, un tampon, `0x2000` = 8192 octets.
`ls -l /proc/2231/fd/3` dit sur quoi porte la lecture (fichier, pipe, socket).

Si le processus tournait en espace utilisateur, le fichier contiendrait
`running`. S'il était bloqué **hors** d'un appel système (rare, par exemple
stoppé), il contiendrait `-1` suivi des pointeurs. Cette lecture est
instantanée et sans effet sur le processus, contrairement à `strace -p` qui
pose un `ptrace` et le ralentit : c'est le premier réflexe sur un serveur en
production quand un processus « ne fait rien ».
:::

---

**Q9.3** — *Processus en `D` depuis dix minutes : quelle affirmation est
juste ?*

**Réponse : b)** bloqué dans un appel système, en attente d'un pilote.

::: pourquoi
`D` = `TASK_UNINTERRUPTIBLE`. Le processus a franchi la porte des appels
système et attend, **dans le noyau**, qu'un pilote lui rende la main : bloc
disque, réponse NFS, verrou de système de fichiers. Il ne consomme pas de CPU
(il dort). Les signaux sont mis en attente et ne seront regardés qu'au retour
en espace utilisateur ; `SIGKILL` inclus, sauf chemins `TASK_KILLABLE`.

Deux fichiers disent où il dort : `/proc/PID/wchan` (le nom de la fonction
noyau, par exemple `nfs_wait_bit_killable` ou `io_schedule`) et
`/proc/PID/stack` (la pile noyau complète, root requis). Le coupable est
toujours **en dessous** : `dmesg -T | grep -iE 'I/O error|blocked for more'`,
`iostat -xz 1`, l'état du NFS ou du stockage Proxmox. On répare la couche du
dessous, et le processus repart tout seul.
:::

::: piege
d) confond `D` et `Z`. Un zombie est **mort** et attend `wait()` ; un `D` est
**vivant** et attend le matériel. Le premier ne coûte rien, le second compte
dans la charge moyenne. Module 08 pour le détail des états.
:::

---

**Q9.4** — *Chaîne de démarrage correcte sur une VM UEFI.*

**Réponse : b)**

::: pourquoi
Le firmware UEFI lit ses variables NVRAM (`efibootmgr -v`), trouve la
partition ESP (FAT32, type `EFI System`, montée sur `/boot/efi`), et charge
`\EFI\ubuntu\shimx64.efi`. `shim` est signé par Microsoft : c'est ce qui permet
de démarrer avec Secure Boot ; il vérifie et charge `grubx64.efi`. GRUB lit
`/boot/efi/EFI/ubuntu/grub.cfg` (trois lignes qui pointent vers le vrai
`/boot/grub/grub.cfg`), affiche le menu, charge `vmlinuz-*` et
`initrd.img-*` en mémoire, et saute dans le noyau avec la ligne de commande.

Le noyau décompresse l'initramfs en RAM (`rootfs`), exécute son `/init`, qui
charge les pilotes (`virtio_scsi`, `dm-mod`), active LVM, monte la vraie
racine sur `/root`, puis `switch_root` vers `/sbin/init` → `systemd`, PID 1.
GRUB ne lit **jamais** `/etc/default/grub` : c'est l'entrée de `update-grub`.
:::

---

**Q9.5** — *`net.ifnames=0` ajouté dans `/etc/default/grub`, absent de
`/proc/cmdline` après reboot.*

**Réponse : b)** `update-grub` n'a pas été lancé.

::: pourquoi
`/etc/default/grub` est un fichier shell **source** par `grub-mkconfig`
(`update-grub` est un alias de `grub-mkconfig -o /boot/grub/grub.cfg`). Les
scripts de `/etc/grub.d/` (`10_linux` surtout) génèrent une entrée par noyau
trouvé dans `/boot` en y collant `GRUB_CMDLINE_LINUX` et
`GRUB_CMDLINE_LINUX_DEFAULT`. Sans régénération, `grub.cfg` reste l'ancien.

La vérification avant reboot : `grep -E '^\s+linux' /boot/grub/grub.cfg` doit
montrer le paramètre sur chaque ligne. `_DEFAULT` va sur les entrées normales
seulement, `GRUB_CMDLINE_LINUX` sur toutes, y compris *recovery* — c) n'est
donc pas une cause d'absence. d) est faux : l'initramfs ne contient pas la
ligne de commande, il la **reçoit**.
:::

---

**Q9.6** — *`quiet` dans `/etc/default/grub`, `console=ttyS0` sans `quiet`
dans `/proc/cmdline`, `update-grub` fait.*

**Réponse : b)** un fichier de `/etc/default/grub.d/` redéfinit la variable.

::: pourquoi
Sur Ubuntu, `grub-mkconfig` source `/etc/default/grub` **puis** tous les
`/etc/default/grub.d/*.cfg` dans l'ordre. Une variable affectée dans le second
écrase la première. Les images cloud livrent
`50-cloudimg-settings.cfg` avec `GRUB_CMDLINE_LINUX_DEFAULT="console=tty1
console=ttyS0"` ; `init-select.cfg` vient de `init-system-helpers`. C'est la
première cause de « j'ai modifié la ligne noyau et rien ne change ».

Diagnostic en une commande : `grep -r CMDLINE /etc/default/grub /etc/default/grub.d/`.
Correctif : modifier ou supprimer le fichier de `grub.d/`, ou y mettre sa
propre valeur dans un fichier `99-local.cfg`. Rocky n'a pas ce mécanisme, mais
a `grubby` qui écrit directement dans `/boot/loader/entries/`.
:::

---

**Q9.7** — *Quand faut-il régénérer l'initramfs ? (deux réponses)*

**Réponses : a) et c)**

::: pourquoi
L'initramfs est un mini-système de fichiers chargé par GRUB **avant** que la
vraie racine soit accessible. Il contient ce qu'il faut pour la monter :
modules de stockage, `lvm`, `cryptsetup`, `mdadm`, la configuration de
`modprobe.d`, les scripts de montage. Tout ce qui change la façon d'atteindre
`/` impose de le refaire : nouvelle disposition LVM/LUKS/RAID de la racine,
nouveau pilote de contrôleur, blacklist ou option d'un module utilisé tôt.

`/etc/modprobe.d/` est copié dans l'initrd par `initramfs-tools` : un
`blacklist` ajouté pour un pilote de stockage sans régénération ne s'applique
pas dans l'initrd (le module est chargé quand même tôt), et inversement une
blacklist déjà dans l'initrd survit à la suppression du fichier tant qu'on n'a
pas régénéré. `sysctl` et `/etc/hosts` sont lus par systemd, après le
`switch_root` : sans rapport.
:::

::: piege
Un noyau **et** son initrd vont ensemble : `update-initramfs -u` ne régénère
que celui du noyau le plus récent ; `-k all` les refait tous ; `-k $(uname -r)`
celui qui tourne. Sur Rocky, `dracut -f` sans argument refait celui du noyau
courant, `dracut -f --regenerate-all` tous.
:::

---

**Q9.8** — *`/boot` à 100 % : quelle action est dangereuse ?*

**Réponse : c)** supprimer l'initrd du noyau en cours.

::: pourquoi
Sans `initrd.img-$(uname -r)`, le prochain démarrage sur ce noyau échoue :
le noyau se charge, ne trouve ni `virtio_scsi` ni `lvm`, et finit sur
`VFS: Unable to mount root fs on unknown-block(0,0)`. Tant que tu ne redémarres
pas, rien ne se voit — c'est ce qui rend l'erreur sournoise.

La bonne séquence : `uname -r` (ce qu'il faut protéger), `dpkg -l
'linux-image-*' | grep ^ii` (ce qui est installé), `dpkg -S /boot/*` (ce qui
appartient à un paquet, et ce qui est orphelin : `dpkg-query: no path found`),
`apt autoremove --purge` (les noyaux non protégés), puis suppression manuelle
des orphelins, puis `update-initramfs -u -k all` et `update-grub`. Si `apt`
est bloqué en `dpkg was interrupted`, d'abord libérer, ensuite
`dpkg --configure -a`.
:::

---

**Q9.9** — *Rocky 9 : ajouter `console=ttyS0,115200` à tous les noyaux et
aux suivants (deux réponses).*

**Réponses : a) et b)**

::: pourquoi
Rocky 9 utilise BLS (*Boot Loader Specification*) : une entrée par noyau dans
`/boot/loader/entries/<machine-id>-<version>.conf`, avec sa ligne `options`.
`grubby --update-kernel=ALL --args="..."` modifie ces fichiers directement, et
`grubby --info=ALL` les relit. Aucune régénération de `grub.cfg` n'est
nécessaire pour ça.

Un noyau installé plus tard reçoit les options de l'entrée par défaut
courante — donc le `grubby` suffit en pratique. Mais `grub2-mkconfig -o
/boot/grub2/grub.cfg`, lancé un jour par quelqu'un, réécrit les options des
entrées à partir de `GRUB_CMDLINE_LINUX` : garder `/etc/default/grub` aligné
évite de perdre l'option à ce moment-là. c) est écrasé à la prochaine
génération ; d) est la commande Ubuntu, absente sur Rocky.
:::

---

**Q9.10** — *Rôle de `/etc/modprobe.d/dummy.conf` et
`/etc/modules-load.d/dummy.conf`.*

**Réponse : b)**

::: pourquoi
Deux mécanismes, deux lecteurs. `modprobe` lit `/etc/modprobe.d/*.conf` à
**chaque** chargement de module, quel qu'en soit l'auteur (udev, systemd, toi) :
`options` y fixe les paramètres, `blacklist`/`install`/`softdep`/`alias` y
règlent le comportement. Ce fichier ne charge rien.

`systemd-modules-load.service` lit `/etc/modules-load.d/*.conf` (et
`/etc/modules` sur Ubuntu) tôt au boot et fait un `modprobe` de chaque nom
listé, lequel applique alors les `options`. Sans le second fichier, `dummy`
n'est jamais chargé au boot (rien ne le demande : pas de matériel, pas
d'alias). Sans le premier, il est chargé avec `numdummies=1`. Les deux sont
donc nécessaires ; `modprobe dummy numdummies=2` à la main est volatil.
:::

---

**Q9.11** — *`blacklist virtio_net` : affirmations vraies (deux réponses).*

**Réponses : a) et b)**

::: pourquoi
`blacklist` ne fait qu'une chose : ignorer les **alias internes** du module.
Or udev charge les pilotes par alias — il lit `modalias` du périphérique
(`virtio:d00000001v00001AF4`), et `modprobe` résout cet alias vers
`virtio_net`. Blacklisté, l'alias est ignoré : le périphérique reste sans
pilote, plus de `ens18`. Mais `modprobe virtio_net` par son nom passe outre
(le nom n'est pas un alias). C'est voulu : `blacklist` sert à empêcher
l'**automatisme**, pas à interdire.

Pour interdire vraiment : `install virtio_net /bin/false` — `modprobe`
exécute la commande à la place du chargement, et `/bin/false` échoue. Les deux
lignes ensemble forment le « blacklist dur » qu'utilisent les guides de
durcissement (`install usb-storage /bin/false`). Le fichier `.ko` n'est pas
touché, et `module verification failed` concerne la signature, pas la
blacklist.
:::

---

**Q9.12** — *`10-factura.conf` = 10, `/etc/sysctl.conf` = 60 : valeur
effective ?*

**Réponse : b)** 60.

::: pourquoi
`sysctl --system` (et `systemd-sysctl.service` au boot) construit une liste
de fichiers : tous les `*.conf` de `/etc/sysctl.d`, `/run/sysctl.d`,
`/usr/local/lib/sysctl.d`, `/usr/lib/sysctl.d`, `/lib/sysctl.d`, triés par
**nom de base** toutes provenances confondues, puis `/etc/sysctl.conf`. Un
même nom présent dans `/etc` et `/usr/lib` : seul celui de `/etc` est lu (pour
neutraliser un fichier système, on crée un lien vers `/dev/null` de même nom
dans `/etc/sysctl.d`). Chaque fichier applique ses clés dans l'ordre ; **la
dernière écriture gagne**.

Ubuntu ajoute un détail : `/etc/sysctl.d/99-sysctl.conf` est un lien
symbolique vers `../sysctl.conf`. Le fichier historique est donc rejoué en
position 99, après `10-factura.conf`. Rocky n'a pas ce lien mais
`sysctl - -system` lit quand même `/etc/sysctl.conf` en dernier. Conclusion
pratique : ne jamais rien mettre dans `/etc/sysctl.conf`, et numéroter ses
fichiers **au-dessus** de ce que livrent les paquets (`60-`, `90-`).
:::

---

**Q9.13** — *`nf_conntrack_max` : `cannot stat ... No such file or
directory`.*

**Réponse : b)** module non chargé, donc clé inexistante.

::: pourquoi
`/proc/sys` est une vue **dynamique** : chaque module enregistre ses clés
au chargement. `net.netfilter.*` n'existe que si `nf_conntrack` est chargé,
ce qui arrive à la première règle `iptables`/`nft` à état, ou à un `modprobe`.
Sur une machine fraîche, la clé est absente et `sysctl -w` échoue. Au boot,
`systemd-sysctl` passe **avant** que quiconque ait chargé le module : le
paramètre est ignoré avec un avertissement dans le journal, et la machine
tourne avec la valeur par défaut.

Correctif en deux fichiers : `/etc/modules-load.d/nf_conntrack.conf`
(contenu : `nf_conntrack`) — `systemd-modules-load.service` est ordonné
**avant** `systemd-sysctl.service`, précisément pour ce cas — et
`/etc/sysctl.d/60-conntrack.conf` avec la valeur. Même piège pour
`net.bridge.bridge-nf-call-iptables` (module `br_netfilter`, prérequis
Kubernetes) et `net.ipv4.vs.*` (`ip_vs`).
:::

---

**Q9.14** — *Règle udev avec `SYMLINK+=`, disque déjà présent, lien absent.*

**Réponse : b)** recharger les règles, puis rejouer l'événement.

::: pourquoi
`systemd-udevd` compile les règles au démarrage et les garde en mémoire ;
il surveille `/etc/udev/rules.d` par inotify et recharge en général tout seul,
mais `udevadm control --reload` garantit la prise en compte. Surtout : une
règle ne s'applique **que lors du traitement d'un événement**. Un disque déjà
présent a eu son événement `add` au boot ; rien ne se passera tant qu'un
nouvel événement n'arrive pas. `udevadm trigger --action=add /dev/sdb` (ou
`--action=change`, le défaut) synthétise cet événement ; `udevadm settle`
attend la fin du traitement.

`udevadm test /sys/block/sdb` fait la même chose **à blanc** : il affiche les
règles parcourues et les propriétés résultantes (`DEVLINKS=`) sans rien
appliquer — c'est l'outil pour vérifier une règle avant de la rejouer.
:::

---

**Q9.15** — *`task jbd2/dm-0-8:312 blocked for more than 120 seconds`.*

**Réponse : b)** le journal ext4 attend le stockage.

::: pourquoi
`jbd2` est le thread de journalisation d'ext4 ; `dm-0` désigne un volume
LVM. Le détecteur *hung task* (`khungtaskd`) signale toute tâche restée en
`D` plus de `kernel.hung_task_timeout_secs` (120 s). Le thread a émis une
écriture vers le disque et attend son acquittement depuis deux minutes : le
disque, la couche virtio, ou le stockage de l'hôte Proxmox ne répond plus.

Ensuite : `dmesg -T | grep -iE 'I/O error|reset|timeout'` juste au-dessus du
message, `ps -eo pid,stat,wchan:24,args | awk '$2 ~ /D/'` pour voir qui est
bloqué, `iostat -xz 1` (`await` énorme, `%util` à 100 avec zéro débit), et
côté hôte l'état du stockage. La ligne « echo 0 > ... disables this message »
est une aide à la lecture, pas une recommandation. Ce n'est pas du CPU : la
tâche dort.
:::

---

**Q9.16** — *`soft lockup - CPU#1 stuck for 23s! [postgres:1204]` dans une
VM.*

**Réponse : b)** le vCPU n'a pas été ordonnancé par l'hôte.

::: pourquoi
Un *soft lockup* signifie que le *watchdog* du noyau n'a pas pu s'exécuter sur
ce CPU pendant N secondes : le CPU était monopolisé sans préemption. Sur du
matériel physique, c'est un bug noyau ou un pilote en boucle. Dans une VM,
c'est presque toujours le vCPU qui **n'a pas tourné** : l'hôte était saturé,
une sauvegarde, un snapshot avec mémoire ou une migration a gelé la VM, et au
réveil le noyau invité constate un trou de 23 s. Le nom entre crochets est
simplement le processus qui avait le CPU au moment du gel — pas le coupable.

Vérification : `st` (*steal*) dans `top`/`vmstat`, `journalctl -k` autour de
l'heure, et côté Proxmox les tâches (backup, snapshot) et la charge de l'hôte.
`kernel.softlockup_panic=0` par défaut, sinon la VM redémarrerait.
:::

---

**Q9.17** — *`System clock synchronized: no`, TLS « not yet valid » (deux
réponses).*

**Réponses : a) et b)**

::: pourquoi
Un certificat X.509 a une fenêtre `notBefore`/`notAfter` ; une horloge locale
en retard le voit « pas encore valide », en avance « expiré ». La correction
est de remettre l'heure **par le service de temps**, pas d'ignorer TLS.

chrony corrige par *slew* (ralentir ou accélérer l'horloge, au plus 8,3 % sur
Ubuntu : `maxslewrate 83333.333`) pour ne jamais faire sauter le temps, sauf
au démarrage où `makestep 1 3` autorise un saut si l'écart dépasse 1 s dans
les 3 premières mesures. Passé ce délai, un décalage de 44 jours mettrait des
mois à se résorber : `chronyc makestep` force un saut immédiat. Mais sans
source joignable (`chronyc sources` vide ou `?`), chrony n'a rien à quoi se
comparer et ne fait rien — d'où b) avant a). d) écrit l'horloge matérielle
dans l'horloge système : sur une VM, le RTC est lui-même faux.
:::

---

**Q9.18** — *Module DKMS : `Key was rejected by service`.*

**Réponse : b)** Secure Boot exige un module signé.

::: pourquoi
Avec Secure Boot actif, le noyau Ubuntu passe en mode *lockdown integrity* :
il n'accepte que les modules signés par une clé de sa base de confiance
(clé Canonical intégrée, plus les clés MOK enrôlées dans le firmware). Un
module compilé par DKMS est signé avec une clé locale générée dans
`/var/lib/shim-signed/mok/` ; si cette clé n'a pas été enrôlée
(`mokutil --import MOK.der`, puis confirmation au reboot dans l'interface
`MokManager`), le noyau la rejette avec ce message précis. `dmesg` montre
`Loading of unsigned module is rejected` ou `module verification failed`.

Vérification : `mokutil --sb-state`, `mokutil --list-enrolled`,
`modinfo -F signer module.ko`. Alternatives : désactiver Secure Boot dans le
firmware (sur Proxmox : VM OVMF, option *pre-enrolled keys* décochée), ou
utiliser un module livré et signé par la distribution. `kernel.modules_disabled=1`
donnerait `Operation not permitted`, pas un rejet de clé.
:::

---

## 9.4 Quiz — questions ouvertes

**QO9.1** — *Ce qui se passe quand un programme appelle `open()`.*

**Réponse attendue**

1. Le programme appelle `open("/etc/hosts", O_RDONLY)` : c'est une fonction de
   la **glibc**, en espace utilisateur. Elle place le numéro de l'appel
   (`openat` = 257 sur x86_64) et les arguments dans des registres, puis
   exécute l'instruction `syscall`.
2. Le CPU passe en **mode noyau** (ring 0) : même processus, même espace
   d'adressage, mais une pile noyau et le droit de tout faire. Ce n'est pas un
   *context switch* (pas de changement de processus), c'est un *mode switch*,
   plus léger — quelques centaines de nanosecondes, plus les mitigations
   Spectre.
3. Le noyau exécute `sys_openat` : résolution du chemin par le VFS, contrôle
   des permissions (DAC, puis AppArmor/SELinux), allocation d'un descripteur
   dans la table du processus, et retour.
4. Retour en mode utilisateur avec la valeur dans un registre : un descripteur
   positif, ou `-errno`. La glibc traduit : elle renvoie `-1` et pose `errno`
   (`ENOENT`, `EACCES`). C'est pour ça que `strace` affiche
   `openat(...) = -1 ENOENT (No such file or directory)`.
5. Cas sans passage noyau : `gettimeofday()` et `clock_gettime()` lisent une
   page partagée par le noyau, la **vDSO**, sans `syscall` — c'est pour ça que
   `strace` ne les montre pas. Et `printf` n'est pas un appel système : c'est
   un tampon qui finira par un `write`.
6. Si `sys_openat` doit attendre un disque ou un NFS, le noyau met le
   processus en `TASK_UNINTERRUPTIBLE` : état `D`. Il est **dans** l'appel,
   côté noyau ; les signaux attendent son retour ; `/proc/PID/syscall` montre
   `257 ...` et `/proc/PID/wchan` la fonction d'attente.

::: pourquoi
Ce qui distingue une bonne réponse : nommer la libc comme couche
intermédiaire, expliquer que le noyau **ne fait pas confiance** aux arguments
(il copie et vérifie chaque pointeur : `copy_from_user`), et distinguer
mode switch et context switch. Le coût réel d'un appel système explique toute
l'ingénierie des serveurs modernes : tampons, `epoll` plutôt que `select`,
`io_uring`, vDSO — et pourquoi `strace` (qui **double** chaque appel par un
arrêt `ptrace`) est si coûteux.
:::

---

**QO9.2** — *Le démarrage d'une VM Ubuntu 24.04 UEFI, de l'allumage à
`login:`.*

**Réponse attendue**

| Étape | Qui charge | Fichier réel |
|---|---|---|
| Firmware UEFI (OVMF) | la VM | variables NVRAM, `efibootmgr -v` |
| ESP | firmware | `/boot/efi/EFI/ubuntu/shimx64.efi` |
| GRUB | shim | `/boot/efi/EFI/ubuntu/grubx64.efi` |
| Configuration GRUB | GRUB | `/boot/efi/EFI/ubuntu/grub.cfg` → `/boot/grub/grub.cfg` |
| Noyau + initrd | GRUB | `/boot/vmlinuz-6.8.0-52-generic`, `/boot/initrd.img-6.8.0-52-generic` |
| Racine | `/init` de l'initramfs | `/dev/mapper/ubuntu--vg-ubuntu-` |
|  | `-` | `lv` |
| PID 1 | noyau après `switch_root` | `/sbin/init` → `/usr/lib/systemd/systemd` |
| Cible | systemd | `default.target` → `multi-user.target` |
| Login | systemd | `getty@tty1.service`, `serial-getty@ttyS0.service`, `ssh.service` |

1. Le firmware initialise le matériel virtuel, lit l'ordre de boot
   (`BootOrder`), trouve l'ESP (partition GPT de type *EFI System*, FAT32).
2. **Secure Boot** : le firmware ne charge que des binaires signés par une clé
   de sa base (`db`). `shimx64.efi` est signé par Microsoft ; il embarque la
   clé Canonical et vérifie `grubx64.efi`, qui vérifie `vmlinuz`. Le noyau
   passe alors en *lockdown* et n'accepte que des modules signés. Sans Secure
   Boot, `shim` est sauté ou ne vérifie rien.
3. GRUB lit le stub `grub.cfg` de l'ESP, qui contient `search.fs_uuid ...`
   et `configfile` vers `/boot/grub/grub.cfg`. Menu, choix de l'entrée,
   `linux` charge `vmlinuz` (+ ligne de commande), `initrd` charge
   l'initramfs en RAM. GRUB saute dans le noyau.
4. Le noyau se décompresse, initialise CPU, mémoire, bus PCI, découvre les
   périphériques virtio, monte l'initramfs comme racine temporaire et exécute
   `/init` (script `initramfs-tools`) : udev minimal, `modprobe virtio_scsi
   dm-mod`, `vgchange -ay`, montage de la racine sur `/root` en lecture seule,
   `run-init`/`switch_root`.
5. `systemd` devient PID 1, lit `/etc/fstab`, `/etc/sysctl.d`,
   `/etc/modules-load.d`, démarre les unités jusqu'à `default.target`.
   `systemd-analyze` donne le temps de chacune de ces phases : firmware,
   loader, kernel, userspace.

::: pourquoi
Un point souvent oublié : **la ligne de commande du noyau est lue par trois
acteurs** — le noyau (`console=`, `root=`, `quiet`), l'initramfs (`root=`,
`rd.break`, `break=premount`) et systemd (`systemd.unit=`,
`systemd.log_level=`). `init=/bin/bash` est lu par le noyau seul : il remplace
`/sbin/init` par bash au moment du `switch_root`, et systemd ne démarre
jamais.

En BIOS (SeaBIOS, défaut Proxmox) : pas d'ESP ni de shim ; le firmware charge
les 440 octets du MBR (`boot.img`), qui charge `core.img` logé dans la
partition *BIOS boot* (GPT) ou l'espace après le MBR, qui charge
`/boot/grub/grub.cfg`. Le reste est identique.
:::

---

**QO9.3** — *Mot de passe root perdu : procédure Ubuntu et Rocky.*

**Réponse attendue**

Ubuntu 24.04 :

1. Console (`qm terminal 9001` ou noVNC). Au menu GRUB (`Échap` s'il est
   caché), `e` sur l'entrée par défaut.
2. Sur la ligne `linux`, retirer `quiet splash` s'ils y sont, ajouter en fin
   `init=/bin/bash`. `Ctrl-x`.
3. Shell root sans mot de passe, racine montée **en lecture seule** (le noyau
   la monte `ro` par défaut, c'est `systemd` qui repasse en `rw` d'après
   `fstab`) : `mount -o remount,rw /`.
4. `passwd root` ou `passwd mathieu` ; vérifier `/etc/shadow` a bien changé.
5. `sync`, puis `exec /sbin/init` (continue le boot normalement) ou
   `reboot -f` (pas de `reboot` simple : sans systemd, il n'y a personne pour
   le traiter).

Rocky 9 :

1. GRUB, `e`, ligne `linux` : ajouter `rd.break` (arrêt dans l'initramfs
   **avant** le `switch_root`). `Ctrl-x`.
2. Invite `switch_root:/#`. La racine réelle est sur `/sysroot` en `ro` :
   `mount -o remount,rw /sysroot`, `chroot /sysroot`.
3. `passwd root`.
4. `touch /.autorelabel` : le fichier `/etc/shadow` a été réécrit **sans**
   SELinux actif (l'initramfs n'a pas la politique chargée), il porte un
   contexte incorrect ; sans ré-étiquetage, le login échoue ensuite. Le
   fichier déclenche un `restorecon` complet au prochain boot (long).
5. `exit` deux fois ; le boot continue.

Ce que ça prouve : **l'accès physique (ou console) donne root**. Les deux
contre-mesures : un mot de passe GRUB (`grub-mkpasswd-pbkdf2`, `set superusers`
dans `/etc/grub.d/40_custom`, `--unrestricted` sur l'entrée normale pour ne
pas bloquer le boot automatique) qui empêche `e` ; et le chiffrement du disque
(LUKS) qui rend le disque illisible sans passphrase, y compris monté ailleurs.
Sur Proxmox, restreindre qui peut ouvrir la console de la VM (`VM.Console`)
fait partie de la réponse.

::: pourquoi
`init=` est traité par le noyau : le programme indiqué est lancé comme PID 1
avec `/` monté en lecture seule et sans `/proc` ni `/sys` montés (les monter
si besoin : `mount -t proc proc /proc`). Aucun mot de passe n'est demandé
parce que personne ne le demande — il n'y a pas de login, pas de PAM. C'est
aussi pourquoi `systemd.unit=rescue.target` ne suffit pas sur Ubuntu : cette
cible lance `sulogin`, qui exige le mot de passe root ; or root est
verrouillé (`!` dans `shadow`), et `sulogin` refuse (`Cannot open access to
console, the root account is locked`). On peut autoriser ce shell sans mot de passe en posant `Environment=SYSTEMD_SULOGIN_FORCE=1` dans un drop-in de `rescue.service` et `emergency.service` — à faire **avant** l'incident ; à la main, `init=/bin/bash` reste la voie sûre.
:::

---

**QO9.4** — *À quoi sert l'initramfs, quand le régénérer.*

**Réponse attendue**

Le noyau seul ne sait monter une racine que si le pilote du contrôleur et la
logique du volume sont **compilés en dur**. Les distributions compilent
presque tout en modules (`virtio_scsi`, `dm-mod`, `ext4` parfois) : au moment
de monter `/`, ces modules sont… sur `/`. Œuf et poule. L'initramfs est une
archive `cpio` compressée que GRUB charge en RAM à côté du noyau ; le noyau la
déballe en `rootfs` et exécute `/init`, qui charge les modules, assemble
LVM/RAID/LUKS (avec `cryptsetup` et la demande de passphrase), résout
`root=UUID=` ou `root=/dev/mapper/...`, monte la racine, puis `switch_root`.

`MODULES=most` (défaut Ubuntu, `/etc/initramfs-tools/initramfs.conf`) embarque
la plupart des pilotes de stockage/réseau/USB : initrd de 60 à 150 Mo, mais
la VM peut changer de contrôleur ou être clonée sur un autre hôte et
démarrer quand même. `MODULES=dep` n'embarque que ce que la machine
**utilise** au moment de la génération : 20 Mo, mais fragile si le matériel
change. Dracut : `hostonly="yes"` (défaut RHEL, équivalent de `dep`) ou
`no` (générique, ce que fait `dracut --no-hostonly` pour un modèle de VM).

Vérifier : `lsinitramfs /boot/initrd.img-$(uname -r) | grep virtio_scsi`,
`lsinitrd | grep -E 'virtio|lvm'` sur Rocky ; `lsinitrd -f etc/modprobe.d/x.conf`
affiche un fichier embarqué.

Régénérer : (1) la racine change de nature — migration vers LVM, ajout de
LUKS, RAID ; (2) changement de contrôleur ou de pilote de stockage (clonage
vers un autre hyperviseur, passage IDE → virtio-scsi) ; (3) modification de
`/etc/modprobe.d/` ou de `/etc/initramfs-tools/modules` touchant un module
chargé tôt ; (4) après une mise à jour de microcode ou de firmware embarqué,
et évidemment à chaque nouveau noyau (fait par le paquet).

::: pourquoi
La question cache une compréhension de la **séquence** : `root=` n'est pas
résolu par le noyau mais par l'initramfs (c'est lui qui comprend `UUID=`,
`/dev/mapper`, `LABEL=`). Un `fstab` cassé n'empêche pas de monter `/` (module
11) ; un initramfs cassé, si. Les symptômes se distinguent : « `VFS: Unable to
mount root fs` » ou « `Gave up waiting for root file system device` » avec un
shell `(initramfs)` = problème d'initramfs ; « `emergency mode` » = systemd a
démarré, donc la racine est montée, et c'est `fstab` ou une unité.
:::

---

**QO9.5** — *Méthode pour poser un `sysctl` en production.*

**Réponse attendue**

1. Lire la valeur courante et sa provenance : `sysctl vm.swappiness`, puis
   `grep -r swappiness /etc/sysctl.conf /etc/sysctl.d /usr/lib/sysctl.d
   /run/sysctl.d` pour savoir si un fichier la fixe déjà.
2. Tester à chaud : `sudo sysctl -w vm.swappiness=10`. Volatile : un reboot
   efface. Mesurer l'effet (pour un `somaxconn`, vérifier que l'application
   redémarre : le backlog est lu au `listen()`, pas dynamiquement).
3. Persister dans **un** fichier `/etc/sysctl.d/60-factura.conf`, avec
   commentaire et ticket. Rang : au-dessus des fichiers de paquets (`10-*`
   Ubuntu), en dessous de `99-sysctl.conf`. Extension `.conf` obligatoire.
4. Appliquer comme au boot : `sudo sysctl --system`, et **lire la sortie** :
   elle liste chaque fichier dans l'ordre et chaque clé appliquée. Une clé
   absente donne `sysctl: cannot stat ...`. Une clé redéfinie plus loin se
   voit parce qu'elle apparaît deux fois.
5. Vérifier `sysctl -n vm.swappiness` = 10, puis `journalctl -u
   systemd-sysctl -b` après le prochain reboot (les avertissements y sont).

Ordre de précédence : `/etc/sysctl.d/*.conf` + `/run/sysctl.d` +
`/usr/local/lib/sysctl.d` + `/usr/lib/sysctl.d` + `/lib/sysctl.d`, fusionnés
et triés par nom de fichier (même nom : `/etc` gagne, puis `/run`, puis
`/usr`), puis `/etc/sysctl.conf` en dernier. Le dernier qui écrit une clé
gagne.

Cas du module : `net.netfilter.nf_conntrack_max`, `net.bridge.*`,
`net.ipv4.vs.*` n'existent qu'une fois `nf_conntrack`, `br_netfilter`,
`ip_vs` chargés. Solution : `/etc/modules-load.d/<module>.conf`, car
`systemd-modules-load.service` est ordonné avant `systemd-sysctl.service`.
Vérification après reboot : `lsmod | grep nf_conntrack` et la valeur.

::: pourquoi
Pourquoi pas `rc.local` ou un cron `@reboot` : ils s'exécutent après les
services, donc **après** que l'application a lu `somaxconn` ou que
`nf_conntrack` a dimensionné sa table ; ils ne sont pas idempotents ni
visibles pour un audit qui lit `sysctl --system`. Et pourquoi `sysctl -p
fichier` « marche » mais trompe : il applique ce fichier seul, dans l'instant,
sans la précédence — c'est un test, pas une preuve de persistance.
:::

---

**QO9.6** — *Un disque ajouté à chaud : la chaîne complète.*

**Réponse attendue**

1. Proxmox attache un disque au contrôleur virtio-scsi : le contrôleur émet
   un événement SCSI. Le pilote noyau (`virtio_scsi`) le reçoit, le sous-
   système SCSI crée un périphérique (`2:0:0:1`), la couche bloc alloue un
   nom **par ordre de découverte** : `sdb`, majeur 8, mineur 16.
2. Le noyau émet un **uevent** (message netlink, visible avec
   `udevadm monitor -k`) : `add /devices/pci0000:00/.../block/sdb`,
   `SUBSYSTEM=block`, `DEVNAME=sdb`, `MAJOR=8 MINOR=16`.
3. `devtmpfs` (monté sur `/dev` par le noyau lui-même) crée `/dev/sdb`
   immédiatement, avec les bons majeur/mineur. `mknod` à la main n'existe
   plus que pour les cas exotiques.
4. `systemd-udevd` reçoit l'uevent, parcourt les règles dans l'ordre des noms
   (`/usr/lib/udev/rules.d/60-persistent-storage.rules` importe le résultat de
   `scsi_id` → `ID_SERIAL`, puis `blkid` → `ID_FS_UUID`, `ID_ FS_LABEL`), et
   crée les liens `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1`,
   `by-path/pci-0000:05:00.0-scsi-0:0:0:1`, `by-uuid/...` s'il y a un système
   de fichiers. Il émet ensuite son propre événement (`udevadm monitor -u`).
5. Les règles de `/etc/udev/rules.d` s'intercalent par nom. Une règle stable :

```ini
SUBSYSTEM=="block", ENV{ID_SERIAL}=="0QEMU_QEMU_HARDDISK_drive-scsi1", \
  SYMLINK+="disk/lab/cache"
```

`sdb` n'est pas stable parce qu'il dépend de l'**ordre d'énumération** :
ajouter un disque sur un port inférieur, changer de contrôleur, ou un
délai de détection différent au boot, et `sdb` désigne un autre disque.
`ID_SERIAL`, `ID_PATH` (position sur le bus) et l'UUID du système de fichiers
sont des propriétés du disque, pas de l'ordre.

Tester sans reboot : `udevadm test /sys/block/sdb 2>&1 | grep -E
'DEVLINKS|60-lab'` pour voir la règle s'appliquer à blanc ; puis
`udevadm control --reload && udevadm trigger --action=add /dev/sdb &&
udevadm settle` ; `ls -l /dev/disk/lab/`.

::: pourquoi
Le point que les candidats ratent : `/dev` est **devtmpfs**, peuplé par le
noyau, et udev ne fait qu'**enrichir** (liens, permissions, `OWNER`, `GROUP`,
`ATTR{}`), exécuter (`RUN+=`) et **renommer les interfaces réseau** — les
seules choses qu'udev renomme, parce qu'une interface n'a pas de nœud dans
`/dev`. Un disque n'est jamais renommé : on lui ajoute des liens.
:::

---

**QO9.7** — *OOM, erreur E/S, soft lockup, hung task : lecture, couche,
commande suivante, kdump.*

**Réponse attendue**

| Trace | Sens | Couche | Commande suivante |
|---|---|---|---|
| `Out of memory: Killed process 3412 (java) total-vm:... anon-rss:...` | plus de RAM ni de swap, le noyau a tué le plus gros score | mémoire, application | `journalctl -k -b \| grep -B30 'Killed process'` pour le tableau des candidats ; `oom_score_adj`, `MemoryMax=` (module 08) |
| `I/O error, dev sda, sector 123456 op 0x1:(WRITE)` | le périphérique a répondu une erreur | disque, contrôleur, stockage hôte | `smartctl` (physique) ; sur VM : état du stockage Proxmox, `iostat -xz`, `dmesg` du **host** |
| `BUG: soft lockup - CPU#1 stuck for 23s` | le CPU n'a pas rendu la main au watchdog | CPU, hôte (VM) | `top` colonne `st`, charge de l'hôte, tâches Proxmox |
| `task X blocked for more than 120 seconds` | une tâche en `D` depuis 2 min | stockage / NFS | `ps ... wchan`, `iostat`, `dmesg` pour l'erreur d'origine |

Différence VM / physique : sur une VM, *soft lockup* et sauts d'horloge
viennent presque toujours de l'hôte (steal, pause, snapshot) ; une erreur
E/S n'est pas un disque physique mais un fichier `qcow2`, un LV ou un NFS sur
l'hôte, à diagnostiquer côté Proxmox ; un OOM peut être causé par le *balloon*
(`virtio_balloon` a repris de la RAM à la VM : `free -m` montre moins que
prévu).

`kdump` : au panic, le noyau exécute (`kexec`) un second noyau préchargé dans
une zone réservée (`crashkernel=`), qui écrit la mémoire du noyau planté
(`vmcore`) dans `/var/crash/`. Sans réservation et sans service chargé
**avant** l'incident, il n'y a rien à analyser après. À préparer : paquet
(`linux-crashdump` / `kexec-tools`), paramètre `crashkernel=` dans GRUB,
service `kdump-tools`/`kdump` actif, un test `echo c > /proc/sysrq-trigger`
sur un snapshot, et de la place dans `/var/crash`. `kernel.panic=10` pour
redémarrer seul ensuite.

::: pourquoi
Le fil conducteur : le journal noyau nomme une **couche**, pas un coupable.
Le processus cité dans un OOM est la victime choisie, pas forcément la fuite ;
celui du soft lockup est celui qui avait le CPU ; celui du hung task est celui
qui attendait. La commande suivante remonte toujours d'une couche : du
processus vers la mémoire, du système de fichiers vers le disque, de la VM
vers l'hôte.
:::

---

**QO9.8** — *Pourquoi l'heure d'une VM dérive, et ce que cinq minutes cassent.*

**Réponse attendue**

Deux horloges : le **RTC** (horloge matérielle, pile sur une machine
physique, registre émulé par QEMU sur une VM), lu une fois au boot ; et
l'**horloge système**, tenue par le noyau à partir d'une source
(`current_clocksource` : `kvm-clock` dans une VM, `tsc` sur du physique) et
d'interruptions. Le noyau recopie l'heure système dans le RTC toutes les 11
minutes quand il est synchronisé (« 11-minute mode »), sinon jamais :
`hwclock --systohc` le fait à la main, `/etc/adjtime` mémorise la dérive et
si le RTC est en UTC.

Une VM dérive plus parce que : ses vCPU ne tournent pas en continu (steal),
donc les ticks sont rattrapés par lots ; une pause, un snapshot avec
mémoire, une sauvegarde, une migration gèlent l'horloge le temps de
l'opération ; le RTC émulé est réinitialisé à l'heure de l'hôte à chaque
démarrage, et si l'hôte est faux, l'invité l'est aussi ; enfin
`kvm-clock` suit l'hôte : un hôte non synchronisé entraîne tous ses invités.

chrony : compare l'horloge à ses sources NTP, estime le décalage (*offset*)
et la dérive de fréquence (*frequency*, en ppm), et corrige par **slew**
(l'horloge avance un peu plus vite ou moins vite, au plus 8,3 %) pour que le
temps reste monotone. Le **step** (saut) n'est autorisé que par `makestep
1 3` : décalage > 1 s dans les 3 premières mises à jour après démarrage. Au
delà, `chronyc makestep` force. `timedatectl` montre : heure locale, UTC,
RTC, fuseau, `System clock synchronized`, `NTP service`, `RTC in local TZ`.

Ce qui casse à 5 minutes : TLS (certificats « not yet valid »/expirés, et
plus vite encore les certificats courts type Let's Encrypt en fin de vie) ;
Kerberos/AD (tolérance 5 min exactement, authentification refusée) ; TOTP/2FA
(fenêtre de 30 s) ; `apt`/`dnf` (`Release file is not valid yet`) ; les jetons
JWT et signatures AWS (`RequestTimeTooSkewed`, 5 min) ; la corrélation des
journaux entre machines ; `make` et les *builds* (« clock skew detected ») ;
les bases répliquées et les *leases* Kubernetes/etcd ; `cron` qui saute ou
double une exécution lors d'un step.

::: pourquoi
Le point d'entretien : « pourquoi ne pas juste faire `date -s` ? » Parce
qu'un **saut** en arrière casse tout ce qui suppose un temps monotone (bases
de données, `cron`, `systemd` timers, journaux) et qu'un saut en avant fait
expirer des baux et des sessions. chrony *slew* pour rester continu, et ne
saute que quand l'écart rendrait le slew absurde. Dans une VM, il faut en
plus une source : le service ne devine rien, il compare.
:::

---

**QO9.9** — *Monolithique, eBPF, live patching, temps réel en deux minutes.*

**Réponse attendue**

* **Monolithique modulaire.** Linux est monolithique : ordonnanceur, mémoire,
  VFS, réseau, pilotes tournent tous dans le même espace d'adressage noyau,
  en ring 0, et s'appellent par fonction — pas par messages comme dans un
  micro-noyau (Minix, seL4, ou le noyau de macOS pour partie). « Modulaire »
  signifie que du code peut être chargé et déchargé à chaud (`.ko`), mais une
  fois chargé, un module a tous les droits : un pilote qui plante plante le
  noyau. Exemple ops : `lsmod`, un pilote propriétaire qui marque le noyau
  *tainted* et invalide le support.
* **eBPF.** Une machine virtuelle **dans** le noyau qui exécute des petits
  programmes vérifiés (terminaison garantie, pas d'accès mémoire arbitraire)
  attachés à des points d'accroche : appels système, fonctions noyau
  (kprobes), paquets réseau (XDP, tc), cgroups. Sans module, sans reboot,
  sans risque de panic. Ops : `bpftrace -e 'tracepoint:syscalls:sys_enter_openat
  { printf("%s %s\n", comm, str(args->filename)); }'` liste tous les fichiers
  ouverts sur la machine, en direct, pour quelques pour cent de CPU ; Cilium
  (réseau Kubernetes), Falco (sécurité), `bcc` (`execsnoop`, `opensnoop`,
  `biolatency`).
* **Live patching.** Appliquer un correctif de sécurité au noyau en cours
  sans redémarrer : le noyau redirige les appels d'une fonction vers sa
  version corrigée (`ftrace`). Limité aux correctifs simples, pas aux
  changements de structures. Produits : Canonical Livepatch (`pro enable
  livepatch`, `canonical-livepatch status`), Red Hat `kpatch` (`kpatch list`),
  SUSE `kGraft`, KernelCare. Ops : ça repousse le reboot, ça ne le supprime
  pas — la prochaine mise à jour de noyau complète l'exige toujours.
* **Temps réel.** `PREEMPT_RT` (intégré dans le noyau 6.12) rend le noyau
  entièrement préemptible et borne la **latence** de réaction à une
  interruption (dizaines de μs) — pas la vitesse. Utile pour l'industriel,
  l'audio, les télécoms (5G). Produits : Ubuntu `linux-realtime` (Ubuntu
  Pro), Rocky/RHEL `kernel-rt`. Ops : `uname -v` contient `PREEMPT_RT`,
  `chrt` fixe les priorités temps réel, et un serveur web n'en a aucun besoin.

::: pourquoi
Le jury attend surtout que tu distingues **où** s'exécute le code (module =
ring 0 sans filet, eBPF = ring 0 avec vérificateur, live patch = remplacement
de fonctions noyau) et **ce que ça change pour l'exploitation** (risque de
panic, besoin de reboot, coût d'observation). Une réponse qui cite `bpftrace`
en une ligne vaut plus qu'une théorie sur les micro-noyaux.
:::

---

## 9.5 Exercices guidés

**E9.1** — *Compter les appels système d'un `ls -l /etc`, top 5, et les
fichiers réellement ouverts.*

```bash
strace -c -o /tmp/ls.count ls -l /etc > /dev/null
sort -k4 -rn /tmp/ls.count | head -5
strace -e trace=openat -o /tmp/ls.open ls -l /etc > /dev/null
grep -v ENOENT /tmp/ls.open | awk -F'"' '{print $2}'
```

Sortie plausible du top 5 (colonnes `% time seconds usecs/call calls errors
syscall`) :

```text
  0.00    0.000000           0       124           statx
  0.00    0.000000           0        31           mmap
  0.00    0.000000           0        14           openat
  0.00    0.000000           0        12           close
  0.00    0.000000           0        10           fstat
```

::: pourquoi
`-o fichier` sépare la sortie de `strace` de celle de `ls` (par défaut,
`strace` écrit sur stderr, mêlé aux erreurs de `ls`). `ls -l` fait un `statx` (le successeur de `lstat`, utilisé par coreutils ≥ 8.32)
par entrée : c'est l'appel dominant, et c'est ce qui rend `ls -l` lent sur un
NFS ou un répertoire de 100 000 fichiers — un aller-retour noyau par nom.

`readdir` et `printf` n'y sont pas : ce sont des fonctions de la libc.
`readdir` consomme le tampon rempli par `getdents64` ; `printf` remplit un
tampon vidé par `write`. `-e trace=openat` filtre à la source (moins de bruit
que `grep`), et `ENOENT` élimine les tentatives : la libc essaie plusieurs
chemins pour les bibliothèques et les locales avant de trouver le bon.
:::

---

**E9.2** — *`sleep 300 &` : appel bloquant, fonction noyau, état ; comparer
avec `yes`.*

```bash
sleep 300 & P=$!
cat /proc/$P/syscall            # 230 0x1 0x7ffd... 0x0 ...
ausyscall $(cut -d' ' -f1 /proc/$P/syscall)   # clock_nanosleep
cat /proc/$P/wchan ; echo        # hrtimer_nanosleep
grep State /proc/$P/status       # State:  S (sleeping)
yes > /dev/null & Y=$!
cat /proc/$Y/syscall             # running  (ou 1 0x1 ... = write)
grep State /proc/$Y/status       # State:  R (running)
kill $P $Y
```

::: pourquoi
`sleep` est dans `clock_nanosleep` (230 sur x86_64) : il a demandé au noyau
d'être réveillé plus tard, et dort en `S` (interruptible : un signal le
réveille). `wchan` (*wait channel*) donne la fonction noyau d'attente,
`hrtimer_nanosleep` : c'est le même fichier que `ps -o wchan` lit.

`yes` alterne entre espace utilisateur (construire le tampon) et `write`
(1) : selon l'instant, `syscall` affiche `running` ou `1 0x1 ...`. Il est en
`R`. Un processus en `D` afficherait un numéro d'appel (souvent `0` read,
`1` write, `74` fsync, `257` openat) et un `wchan` de type `io_schedule`,
`wait_on_page_bit`, `nfs_wait_bit_killable` : c'est ainsi qu'on sait **où**
il est bloqué sans `strace`.
:::

---

**E9.3** — *Provenance de chaque paramètre de `/proc/cmdline`.*

```bash
cat /proc/cmdline
# BOOT_IMAGE=/vmlinuz-6.8.0-52-generic root=/dev/mapper/ubuntu--vg-ubuntu--lv ro
grep -E '^GRUB_CMDLINE' /etc/default/grub
grep -rH CMDLINE /etc/default/grub.d/ 2>/dev/null
grep -E '^\s+linux' /boot/grub/grub.cfg | head -2
```

| Paramètre | Origine | Effet |
|---|---|---|
| `BOOT_IMAGE=` | ajouté par GRUB | chemin du noyau chargé, informatif |
| `root=` | `10_linux` (grub.cfg) | périphérique racine, lu par l'initramfs |
| `ro` | `10_linux` | racine montée en lecture seule, systemd remonte `rw` |
| `quiet` / `splash` | `GRUB_CMDLINE_LINUX_DEFAULT` | masque les messages |
| `console=` | `grub.d/50-cloudimg-settings.cfg` si présent | console série |

::: pourquoi
Trois provenances : ce que **GRUB** ajoute lui-même (`BOOT_IMAGE`), ce que
le script `/etc/grub.d/10_linux` génère (`root=`, `ro`, et l'entrée
*recovery* avec `single` ou `recovery nomodeset`), et ce que tu écris dans
`GRUB_CMDLINE_LINUX` (toutes les entrées) ou `GRUB_CMDLINE_LINUX_DEFAULT`
(entrées normales). Le `root=` est décidé par `grub-mkconfig` selon
`GRUB_DISABLE_LINUX_UUID` : `/dev/mapper/...` pour LVM, `UUID=` sinon.

`/etc/default/grub.d/*.cfg` est propre à Debian/Ubuntu ; le `grep -r` sur ce
répertoire est la commande à retenir avant tout diagnostic « mon paramètre
n'est pas appliqué ».
:::

---

**E9.4** — *BIOS ou UEFI, par deux moyens ; ESP ou emplacement GRUB.*

```bash
[ -d /sys/firmware/efi ] && echo UEFI || echo BIOS
sudo dmesg | grep -iE 'efi: |BIOS-provided' | head -3
# --- UEFI
sudo efibootmgr -v
findmnt /boot/efi
lsblk -o NAME,SIZE,FSTYPE,PARTTYPENAME,MOUNTPOINTS /dev/sda
sudo find /boot/efi -name '*.efi' -exec ls -lh {} +
# --- BIOS
sudo grub-probe -t device /boot
lsblk -o NAME,SIZE,PARTTYPENAME /dev/sda | grep -i 'bios boot'
sudo dd if=/dev/sda bs=512 count=1 2>/dev/null | strings | grep -i grub
```

::: pourquoi
`/sys/firmware/efi` n'existe que si le noyau a été démarré par un firmware
UEFI (les *runtime services* sont exposés). Le second moyen : `dmesg` affiche
`efi: EFI v2.70 by EDK II` avec OVMF, ou `BIOS-provided physical RAM map`
seul en SeaBIOS. `efibootmgr -v` lit la NVRAM : `BootCurrent`, `BootOrder`,
et chaque entrée avec son chemin `\EFI\ubuntu\shimx64.efi`.

Sur Proxmox, une VM créée avec les défauts est en **SeaBIOS** : pas d'ESP,
GRUB (`boot.img`, 440 octets) dans le MBR et `core.img` dans la partition
*BIOS boot* de 1 Mo créée par l'installeur Ubuntu sur un disque GPT. La
chaîne `strings` du premier secteur montre `GRUB` et le message d'erreur
`Geom` / `Hard Disk` / `Read` / `Error` embarqué dans `boot.img`.
:::

---

**E9.5** — *Contenu de l'initramfs, modules, taille, `initramfs.conf`.*

```bash
K=$(uname -r)
lsinitramfs /boot/initrd.img-$K | wc -l
lsinitramfs /boot/initrd.img-$K | grep -c '\.ko'
lsinitramfs /boot/initrd.img-$K | grep -E 'virtio_scsi|virtio_net|sbin/lvm'
ls -lh /boot/vmlinuz-$K /boot/initrd.img-$K
grep -vE '^#|^$' /etc/initramfs-tools/initramfs.conf
```

Sortie plausible :

```text
-rw------- 1 root root  14M ... /boot/vmlinuz-6.8.0-52-generic
-rw-r--r-- 1 root root  71M ... /boot/initrd.img-6.8.0-52-generic
MODULES=most
BUSYBOX=auto
COMPRESS=zstd
```

::: pourquoi
L'initrd fait cinq fois le noyau parce que `MODULES=most` y met tous les
pilotes de stockage, réseau, USB, et le microcode CPU (`kernel/x86/microcode`
en tête de l'archive, non compressé — d'où `unmkinitramfs` qui produit deux
répertoires `early/` et `main/`). `.ko.zst` : les modules d'Ubuntu 24.04 sont
compressés individuellement en zstd, comme l'archive.

Le nombre de `.ko` (plus de 1 000 avec `most`, une cinquantaine avec `dep`)
est la mesure du compromis. Sur une VM Proxmox jamais migrée, `MODULES=dep`
diviserait l'initrd par trois et gagnerait une seconde au boot ; sur un
modèle cloné vers des hyperviseurs différents, c'est un risque de
`Unable to mount root fs`.
:::

---

**E9.6** — *Temps de boot, dix unités lentes, chaîne critique, `boot.svg`.*

```bash
systemd-analyze
systemd-analyze blame | head -10
systemd-analyze critical-chain multi-user.target
systemd-analyze plot > ~/lab09/rapports/boot.svg
```

```text
Startup finished in 3.212s (firmware) + 1.802s (loader) + 4.118s (kernel)
+ 9.634s (userspace) = 18.767s
multi-user.target reached after 9.601s in userspace.
```

::: pourquoi
`firmware` et `loader` n'existent qu'en UEFI (le firmware transmet les
horodatages) ; en BIOS la ligne commence à `kernel`. `blame` donne le temps
**propre** de chaque unité, trié, mais deux unités parallèles ne s'additionnent
pas ; `critical-chain` donne le chemin le plus long jusqu'à la cible, avec
`@` (moment d'activation) et `+` (durée). C'est lui qu'on lit pour attaquer un
boot lent : on ne gagne rien à accélérer une unité hors chemin critique.

Sur une VM Ubuntu Server typique, les coupables sont `snapd.seeded.service`,
`cloud-init` (quatre unités), `systemd-networkd-wait-online.service` (attend
un lien, 2 min si une interface configurée n'a pas de câble), et
`apt-daily`. `plot` produit un diagramme de Gantt SVG à ouvrir dans un
navigateur (copie-le via `scp`) : les barres rouges sont les unités actives,
la ligne pointillée la cible.
:::

---

**E9.7** — *Inventaire des noyaux et capacité de `/boot`.*

```bash
uname -r
dpkg -l 'linux-image-*' | awk '/^ii/ {print $2, $3}'
ls -lh /boot/vmlinuz-* /boot/initrd.img-*
df -h /boot
grep -E '^GRUB_DEFAULT' /etc/default/grub
grep -E '^menuentry|^\s+menuentry' /boot/grub/grub.cfg | head -4
du -ch /boot/*-$(uname -r) | tail -1
```

```text
ii  linux-image-6.8.0-52-generic 6.8.0-52.53
ii  linux-image-generic          6.8.0-52.53
/dev/sda2   2.0G  190M  1.7G  11% /boot
95M  total
```

::: pourquoi
Un noyau Ubuntu occupe dans `/boot` : `vmlinuz` (14 Mo), `initrd.img`
(70–140 Mo), `System.map` (8 Mo), `config` (280 Ko). Avec 2 Go, on loge une
quinzaine de versions ; avec le `/boot` de 1 Go des anciennes installations,
six ou sept — et `apt` n'installe **jamais** en remplaçant : il ajoute une
version, garde la précédente, et `autoremove` ne purge que celles qui ne sont
ni courante, ni la plus récente, ni la précédente. Trois versions à 140 Mo
d'initrd tenaient mal dans 1 Go : c'est la panne BF9.1.

`GRUB_DEFAULT=0` désigne la première entrée, donc le noyau le plus récent
(`10_linux` trie par version décroissante). Le sous-menu *Advanced options*
liste les autres et les entrées *recovery*.
:::

---

**E9.8** — *Du périphérique au pilote via `/sys`, `modinfo`, modules virtio.*

```bash
basename "$(readlink /sys/class/net/ens18/device/driver)"       # virtio_net
basename "$(readlink /sys/block/sda/device/driver)"             # sd
basename "$(readlink /sys/block/sda/device/../../../driver)"    # virtio_scsi
cat /sys/class/net/ens18/device/modalias        # virtio:d00000001v00001AF4
modinfo virtio_net | grep -E '^(description|depends|signer|parm|filename)'
modinfo -p virtio_scsi
lsmod | grep -E '^virtio|^Module'
```

```text
Module                  Size  Used by
virtio_net             77824  0
virtio_scsi            28672  2
virtio_pci             24576  0
virtio_pci_legacy_dev  12288  1 virtio_pci
virtio_pci_modern_dev  20480  1 virtio_pci
virtio_balloon         28672  0
```

::: pourquoi
`/sys/class/net/ens18/device` est un lien vers le périphérique PCI/virtio, et
`driver` un lien vers le pilote qui l'a réclamé : c'est la **vérité** du
noyau, contrairement à `lsmod` qui ne dit pas qui pilote quoi. Pour un disque,
la chaîne est plus longue : `sda` est piloté par `sd` (générique SCSI), dont
le parent est la cible SCSI, puis l'hôte SCSI, puis le périphérique virtio dont le pilote est `virtio_scsi` (trois niveaux au-dessus de `device`).

`modalias` est la clé du chargement automatique : udev le lit, `modprobe`
le résout via `/lib/modules/$(uname -r)/modules.alias` (généré par `depmod`).
`signer: Build time autogenerated kernel key` sur Ubuntu : chaque noyau est
signé avec une clé jetable générée à la compilation, et les modules tiers
(DKMS) avec la clé MOK de la machine. `Used by` compte les références : 2 pour
`virtio_scsi` = deux disques ; un module à 0 se décharge, un module utilisé
non (`rmmod: Module is in use`).
:::

---

**E9.9** — *`udevadm monitor` pendant le chargement de `dummy`, paramètre,
décharge, dépendances, propriétés stables de `sda`.*

```bash
sudo modprobe dummy numdummies=2
cat /sys/module/dummy/parameters/numdummies      # 2
ip -br link | grep dummy                         # dummy0, dummy1 DOWN
sudo modprobe -r dummy
ip -br link | grep -c dummy                      # 0
modprobe --show-depends dummy
# insmod /lib/modules/6.8.0-52-generic/kernel/drivers/net/dummy.ko.zst
grep -E '/dummy\.ko' /lib/modules/$(uname -r)/modules.dep
# kernel/drivers/net/dummy.ko.zst:
modinfo -F parm dummy
# numdummies:Number of dummy pseudo devices (int)
```

::: pourquoi
Les paramètres d'un module se passent à `modprobe` (`nom=valeur`) ou dans
`/etc/modprobe.d/` (`options nom nom=valeur`) ; ils sont lus **au
chargement** et exposés en lecture (parfois en écriture) dans
`/sys/module/<m>/parameters/`. Pour changer `numdummies`, il faut décharger
et recharger : un module en usage (interface montée avec une adresse)
refuse `modprobe -r`. Les paramètres d'un module compilé en dur (`=y`) se
passent sur la ligne du noyau : `dummy.numdummies=2`.

`modules.dep` est la table produite par `depmod -a` à partir des symboles
importés/exportés de chaque `.ko` : `modprobe` la lit pour charger les
dépendances d'abord (ligne vide après `:` pour `dummy` : aucune). Un `.ko`
copié à la main sans `depmod` est invisible pour `modprobe`
(`Module not found`), même s'il est au bon endroit — c'est l'erreur classique
après un pilote compilé maison. `insmod` charge un fichier sans résoudre les
dépendances ; on ne s'en sert que pour tester.
:::

Terminal 1 :

```bash
sudo udevadm monitor -u -k
```

Terminal 2 :

```bash
sudo modprobe dummy ; sleep 1 ; sudo modprobe -r dummy
```

```text
KERNEL[1234.5] add   /module/dummy (module)
KERNEL[1234.5] add   /devices/virtual/net/dummy0 (net)
KERNEL[1234.5] add   /devices/virtual/net/dummy0/queues/rx-0 (queues)
UDEV  [1234.5] add   /module/dummy (module)
UDEV  [1234.5] add   /devices/virtual/net/dummy0 (net)
KERNEL[1235.6] remove /devices/virtual/net/dummy0 (net)
UDEV  [1235.6] remove /devices/virtual/net/dummy0 (net)
```

```bash
udevadm info -q property -n /dev/sda | grep -E \
  '^(ID_SERIAL|ID_PATH|ID_WWN|ID_BUS|ID_MODEL|DEVNAME|MAJOR|MINOR)='
```

::: pourquoi
Chaque ligne `KERNEL` est un uevent brut émis par le noyau ; la ligne `UDEV`
correspondante est émise par `systemd-udevd` **après** avoir traité les règles.
Le délai entre les deux est le temps de traitement (règles, `blkid`,
`scsi_id`). Un uevent `KERNEL` sans `UDEV` qui suit = udevd bloqué ou une
règle `RUN+=` qui ne rend pas la main (`udevadm settle - -timeout=5` échoue).

Propriétés stables de `sda` sur Proxmox : `ID_SERIAL=0QEMU_QEMU_HARDDISK_drive-scsi0`
(le nom du disque dans la config de la VM), `ID_PATH=pci-0000:05:00.0-scsi-0:0:0:0`
(position sur le bus), `ID_MODEL=QEMU_HARDDISK`. Non stables : `DEVNAME`,
`MAJOR`/`MINOR`, `ID_PATH` si le contrôleur change de slot PCI. Le lien
`/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0` est donc la clé de
choix pour un `fstab` ou une règle — après l'UUID du système de fichiers.
:::

---

**E9.10** — *`/proc` uniquement : CPU, mémoire, interruptions, et `sshd`.*

```bash
grep -c ^processor /proc/cpuinfo
grep -m1 -o -w hypervisor /proc/cpuinfo
grep -E '^(MemTotal|MemAvailable|Dirty|Writeback):' /proc/meminfo
grep -E 'virtio|CPU0' /proc/interrupts
P=$(cat /run/sshd.pid 2>/dev/null || pgrep -o -x sshd)
ls /proc/$P/fd | wc -l ; ls -l /proc/$P/fd | head -5
grep -E 'open files|processes' /proc/$P/limits
cat /proc/$P/cgroup                    # 0::/system.slice/ssh.service
tr '\0' '\n' < /proc/$P/environ | head -5
readlink /proc/$P/exe /proc/$P/cwd
```

::: pourquoi
Le drapeau `hypervisor` dans `flags` est positionné par le noyau invité quand
il détecte un hyperviseur via CPUID : c'est le test le plus simple « suis-je
dans une VM » (avec `systemd-detect-virt`). `Dirty`/`Writeback` dans
`meminfo` sont les pages modifiées pas encore écrites sur disque : c'est ce
que `vm.dirty_ratio` plafonne, et ce qui rend un `sync` lent.

`/proc/interrupts` ligne par IRQ, colonne par CPU : `virtio1-req.0` (disque),
`virtio0-input.0`/`output.0` (réseau). Une ligne qui n'incrémente que sur
`CPU0` signale une affinité d'interruption mal répartie (`irqbalance`). Pour
`sshd`, `cgroup` prouve que systemd le gère (`system.slice/ssh.service`),
`limits` donne les valeurs effectives héritées de l'unité (`LimitNOFILE`), et
`exe` le binaire réel — avec ` (deleted)` en suffixe si le paquet a été mis à
jour sans redémarrage du service : la façon fiable de détecter un service
qui tourne sur un vieux binaire.
:::

---

**E9.11** — *Deux réglages volatils de `/sys` : ordonnanceur de `sda`, puis
transparent hugepages.*

```bash
cat /sys/block/sda/queue/scheduler          # [mq-deadline] none kyber bfq
echo none | sudo tee /sys/block/sda/queue/scheduler
cat /sys/block/sda/queue/scheduler          # mq-deadline [none] kyber bfq
echo mq-deadline | sudo tee /sys/block/sda/queue/scheduler
cat /sys/block/sda/queue/rotational         # 1 (QEMU se déclare rotatif)
```

::: pourquoi
L'ordonnanceur E/S réordonne et fusionne les requêtes avant le périphérique.
`mq-deadline` (défaut Ubuntu pour un disque SCSI) garantit une latence
maximale par requête ; `bfq` répartit équitablement (postes de travail) ;
`kyber` vise les SSD ; `none` transmet dans l'ordre, sans travail. Sur une
VM, le « disque » est un fichier ou un LV sur l'hôte, qui a **déjà** son
propre ordonnanceur et son propre cache : réordonner deux fois coûte du CPU
pour rien, d'où `none` sur virtio, comme sur NVMe. C'est aussi ce qui explique
que `ionice` (classes `idle`, `best-effort`) n'ait d'effet complet qu'avec `bfq` :
`mq-deadline` ne gère que la classe (pas le niveau 0–7) depuis le noyau 5.14, et `none` ignore tout.

`/sys` est un système de fichiers en mémoire, recréé à chaque boot : rien de
ce qu'on y écrit ne survit. La persistance passe par une règle udev
(`ATTR{queue/scheduler}="none"` — L9.4) ou par le paramètre noyau
`elevator=` (obsolète, ignoré en multi-queue). Un `rotational=1` sur une VM
est un mensonge de QEMU : le choix de l'ordonnanceur ne doit pas s'y fier.
:::

Transparent hugepages :

```bash
cat /sys/kernel/mm/transparent_hugepage/enabled   # always [madvise] never
cat /sys/kernel/mm/transparent_hugepage/defrag
# always defer defer+madvise [madvise] never
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
grep AnonHugePages /proc/meminfo
```

Persistance 1, par le noyau (`/etc/default/grub` puis `update-grub`) :

```ini
GRUB_CMDLINE_LINUX="transparent_hugepage=never"
```

Persistance 2, par systemd (`/etc/systemd/system/thp-never.service`) :

```ini
[Unit]
Description=Desactive les transparent hugepages
DefaultDependencies=no
After=sysinit.target
Before=basic.target
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
[Install]
WantedBy=basic.target
```

::: pourquoi
Les THP font allouer des pages de 2 Mo au lieu de 4 Ko pour réduire les
défauts de TLB : gain pour des calculs sur de grands tableaux, **perte** pour
les bases de données et caches qui gèrent leur mémoire finement (Redis,
MongoDB, PostgreSQL, Oracle exigent `never` ou `madvise`) : `khugepaged`
compacte en arrière-plan, provoque des latences de dizaines de ms, et la
mémoire est gaspillée par des pages de 2 Mo à moitié vides. `madvise` (défaut
Ubuntu) ne les donne qu'aux programmes qui les demandent : c'est le bon
compromis ; Rocky est à `always`, et `tuned` sait le changer par profil.

Ce n'est pas un `sysctl` : `/sys/kernel/mm` n'est pas sous `/proc/sys`, donc
pas de fichier `sysctl.d` possible. D'où les deux voies : paramètre noyau
(appliqué avant tout processus, le plus propre) ou unité `oneshot` ordonnée
avant `basic.target` pour passer avant les services.
:::

---

**E9.12** — *Deux sysctl persistants, application, preuve, ordre de lecture.*

```bash
sudo tee /etc/sysctl.d/60-factura.conf >/dev/null <<'EOF'
# ticket OPS-412 : base de donnees et backlog des serveurs
vm.swappiness = 10
net.core.somaxconn = 8192
EOF
sudo sysctl --system 2>&1 | grep -E '^\*|swappiness|somaxconn'
sysctl -n vm.swappiness net.core.somaxconn
grep -rlE 'swappiness|somaxconn' /etc/sysctl.conf /etc/sysctl.d \
  /usr/lib/sysctl.d /run/sysctl.d 2>/dev/null
```

```text
* Applying /usr/lib/sysctl.d/50-pid-max.conf ...
* Applying /etc/sysctl.d/60-factura.conf ...
vm.swappiness = 10
net.core.somaxconn = 8192
* Applying /etc/sysctl.d/99-sysctl.conf ...
* Applying /etc/sysctl.conf ...
```

::: pourquoi
La sortie de `--system` **est** la preuve : chaque fichier dans l'ordre, et
la valeur au moment de l'application. Si `swappiness` apparaissait encore
sous `99-sysctl.conf` ou `/etc/sysctl.conf`, elle serait réécrite, et le
`grep -rl` final le montrerait. Le rang `60` passe après les `10-*` d'Ubuntu
(`10-kernel-hardening.conf`, `10-magic-sysrq.conf`, `10-ptrace.conf`…) et
après `/usr/lib/sysctl.d/50-*` de systemd, avant `99-sysctl.conf`.

`somaxconn` mérite une remarque : la valeur est lue par l'application au
`listen()`. Après `sysctl --system`, nginx ou PostgreSQL tournent encore avec
l'ancien backlog jusqu'à leur redémarrage. Un `sysctl` n'est pas toujours
« immédiat » au sens de l'application.
:::

---

**E9.13** — *Le paramètre absent : `nf_conntrack_max`.*

```bash
sysctl net.netfilter.nf_conntrack_max
# sysctl: cannot stat /proc/sys/net/netfilter/nf_conntrack_max: No such file
lsmod | grep -c nf_conntrack                       # 0
sudo modprobe nf_conntrack
sysctl net.netfilter.nf_conntrack_max              # 65536 (selon la RAM)
echo nf_conntrack | sudo tee /etc/modules-load.d/nf_conntrack.conf
echo 'net.netfilter.nf_conntrack_max = 131072' | \
  sudo tee /etc/sysctl.d/61-conntrack.conf
sudo sysctl --system | grep conntrack
systemctl list-dependencies --before systemd-modules-load.service | \
  grep sysctl                                       # systemd-sysctl.service
```

::: pourquoi
Le module enregistre ses clés dans `/proc/sys` au chargement ; avant, le
fichier n'existe pas et `sysctl` le dit littéralement. Au boot, l'ordre est :
`systemd-modules-load.service` (lit `modules-load.d`) **puis**
`systemd-sysctl.service` — `After=systemd-modules-load.service` est déclaré dans cette dernière
justement pour ce cas. Sans le premier fichier, le second échoue en silence
au boot (visible seulement dans `journalctl -u systemd-sysctl -b`), et la
machine tourne avec la valeur par défaut : sur 2 Go, 65 536 entrées, qu'un
serveur web derrière un NAT remplit en quelques minutes de pic
(`nf_conntrack: table full, dropping packet` dans `dmesg`, module 19).

Sur une machine avec `ufw`/`nftables` actif, le module est chargé tôt par la
première règle à état, et le piège ne se voit pas — jusqu'au jour où on
désactive le pare-feu sur un serveur, et où la valeur n'est plus appliquée.
Le fichier `modules-load.d` rend le comportement indépendant du pare-feu.
:::

---

**E9.14** — *Messages noyau filtrés, boot précédent, `printk`, SysRq `m`.*

```bash
sudo dmesg -T --level=err,warn
journalctl -k -b -1 -p warning --no-pager | tail -20
cat /proc/sys/kernel/printk          # 4       4       1       7
echo m | sudo tee /proc/sysrq-trigger
sudo dmesg -T | tail -30             # "sysrq: Show Memory" puis le détail
cat /proc/sys/kernel/sysrq           # 176
```

::: pourquoi
`dmesg` lit le tampon circulaire du noyau (*ring buffer*, taille fixée par
`log_buf_len=` au boot, 256 Ko à quelques Mo ; `dmesg | head -1` montre s'il
a déjà tourné quand il ne commence pas à `[0.000000]`). `journalctl -k`
lit les mêmes messages **persistés** par journald, ce qui donne accès aux
boots précédents (`-b -1`) — indispensable après un crash. `-T` traduit les
secondes depuis le boot en heure lisible (approximative après une suspension).

`kernel.printk` = quatre niveaux : ce qui va sur la **console** (4 = warning
et plus grave ; `quiet` le baisse à 1), le niveau des messages sans niveau,
le minimum autorisé pour la console, le défaut au boot. Monter le premier à 7
fait tout apparaître sur la console série : utile pendant un débogage de boot,
insupportable ensuite.

SysRq : `176` = 128 (reboot/poweroff) + 32 (remonter en lecture seule) + 16
(sync). `m` (état mémoire) n'est **pas** dans ce masque (il faut 8 =
`dump`)… sauf que `/proc/sysrq-trigger` en tant que root ignore le masque —
il ne s'applique qu'à la combinaison clavier. `t` liste toutes les tâches
avec leur pile, `w` seulement les tâches bloquées : c'est **la** commande
quand une machine a des `D` et qu'on ne sait pas pourquoi. `c` provoque un
panic (test kdump), `b` redémarre sans rien synchroniser.
:::

---

**E9.15** — *Heures système et matérielle, fuseau, source, synchronisation,
services par défaut.*

```bash
timedatectl
sudo hwclock --show --verbose | head -3
cat /etc/adjtime
cat /sys/devices/system/clocksource/clocksource0/current_clocksource
date -u +%s ; sudo hwclock --show | date -f - +%s     # écart en secondes
systemctl is-active systemd-timesyncd chrony 2>/dev/null
```

```text
               Local time: Sat 2026-09-19 10:14:02 UTC
           Universal time: Sat 2026-09-19 10:14:02 UTC
                 RTC time: Sat 2026-09-19 10:14:02
                Time zone: Etc/UTC (UTC, +0000)
System clock synchronized: yes
              NTP service: active
          RTC in local TZ: no
```

::: pourquoi
Ubuntu Server 24.04 livre `systemd-timesyncd` : un client SNTP minimal (une
seule source à la fois, pas de serveur, pas de `chronyc`) — suffisant pour un
poste, insuffisant pour un serveur qui veut plusieurs sources, du
monitoring et servir d'autres machines. Rocky 9 livre `chrony`
(`chronyd.service`). Installer `chrony` sur Ubuntu **désinstalle**
`systemd-timesyncd` : les deux paquets fournissent `time-daemon` et se déclarent en conflit (`apt` l'annonce dans « REMOVED »).

`current_clocksource` vaut `kvm-clock` dans une VM KVM : l'horloge est
fournie par l'hôte via une page partagée (paravirtualisation), ce qui rend
les lectures rapides et cohérentes… avec l'hôte. `/etc/adjtime` contient
la dérive estimée du RTC, le dernier calage, et `UTC` ou `LOCAL` : sur un
serveur, toujours `UTC` — `RTC in local TZ: yes` est un héritage du double
boot Windows et casse le changement d'heure.
:::

---

**E9.16** — *Trois niveaux de limite de fichiers, allocation, inotify.*

```bash
sysctl -n fs.file-max            # système : 9223372036854775807 ou ~ 200000
sysctl -n fs.nr_open             # maximum par processus : 1048576
ulimit -n ; ulimit -Hn           # effectif dans ce shell : 1024 / 524288
cat /proc/sys/fs/file-nr         # 2848    0       9223372036854775807
sysctl -n fs.inotify.max_user_watches fs.inotify.max_user_instances
# watches par processus (root) :
sudo find /proc/[0-9]*/fdinfo -type f 2>/dev/null | \
  xargs grep -c '^inotify' 2>/dev/null | grep -v ':0$' | \
  sed 's#/proc/\([0-9]*\)/.*:#\1 #' | awk '{a[$1]+=$2} END \
  {for (p in a) print a[p], p}' | sort -rn | head -3
```

::: pourquoi
Trois plafonds, trois messages différents. `fs.file-max` : total de
descripteurs ouvrables sur la machine (systemd le relève à 2⁶³−1) ;
dépassé, le noyau écrit `VFS: file-max limit reached` dans `dmesg` et tout
le monde est affecté. `fs.nr_open` : ce qu'un processus peut demander au
maximum (`ulimit -n` ne peut pas le dépasser : `ulimit -n 2000000` échoue).
`ulimit -n` / `RLIMIT_NOFILE` : la limite **du processus**, celle qui produit
`EMFILE: Too many open files` dans l'application — 99 % des cas, réglée par
`LimitNOFILE=` dans l'unité (module 08). `file-nr` donne alloués, libres
(toujours 0 sur les noyaux récents), maximum.

inotify a ses propres compteurs, **par utilisateur** : `max_user_instances`
(128 : nombre de `inotify_init`, ce que consomment les IDE, les agents de
supervision, `systemd --user`) et `max_user_watches` (chemins surveillés).
Dépassés, l'erreur est `ENOSPC` ou… `EMFILE: Too many open files` pour les
instances — le message trompe, `ulimit -n` n'y changera rien, et c'est
`sysctl fs.inotify.max_user_instances=512` qui répare. Le `find` sur `fdinfo`
compte les lignes `inotify wd:` de chaque descripteur : c'est la seule façon
de savoir **qui** consomme les watches.
:::

---

## 9.6 Labs

### **L9.1** — *Documenter le démarrage de `lab-adm` et ouvrir une console de
secours.*

**1. Mode de démarrage**

```bash
[ -d /sys/firmware/efi ] && echo UEFI || echo BIOS
lsblk -o NAME,SIZE,FSTYPE,PARTTYPENAME,MOUNTPOINTS /dev/sda
# UEFI : sda1 1G vfat "EFI System" /boot/efi ; sda2 2G ext4 /boot ; sda3 LVM
# BIOS : sda1 1M "BIOS boot" ; sda2 2G ext4 /boot ; sda3 LVM
sudo efibootmgr -v 2>/dev/null
sudo ls -lR /boot/efi/EFI 2>/dev/null
```

**2. Configuration GRUB effective**

```bash
grep -vE '^#|^$' /etc/default/grub
ls /etc/default/grub.d/ ; grep -H . /etc/default/grub.d/*.cfg
grep -E '^menuentry|^\s+linux' /boot/grub/grub.cfg
```

Sur une installation ISO : `GRUB_DEFAULT=0`, `GRUB_TIMEOUT_STYLE=hidden`,
`GRUB_TIMEOUT=0`, `GRUB_CMDLINE_LINUX_DEFAULT=""`, `GRUB_CMDLINE_LINUX=""`,
et `init-select.cfg` dans `grub.d/`.

**3. Menu visible et console série**

```bash
sudo tee /etc/default/grub.d/90-lab-serial.cfg >/dev/null <<'EOF'
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0,115200"
GRUB_TERMINAL="serial console"
GRUB_SERIAL_COMMAND="serial --unit=0 --speed=115200 --word=8 --parity=no \
--stop=1"
EOF
sudo update-grub
grep -E '^\s+linux' /boot/grub/grub.cfg | head -2     # ttyS0 présent
grep -E '^serial|^terminal' /boot/grub/grub.cfg
```

**4. Reboot et console série**

```bash
sudo reboot
# sur l'hôte Proxmox :
qm terminal 9001          # menu GRUB, messages noyau, puis login:
```

Dans la session série :

```bash
cat /proc/cmdline ; tty                        # /dev/ttyS0
systemctl status serial-getty@ttyS0.service    # active (running)
```

**5. `rescue.target` puis `init=/bin/bash`**

Au menu GRUB, `e`, fin de la ligne `linux`, `systemd.unit=rescue.target`,
`Ctrl-x`. Ubuntu affiche :

```text
Cannot open access to console, the root account is locked.
See sulogin(8) man page for more details.
Press Enter to continue.
```

Recommencer avec `init=/bin/bash` :

```bash
bash-5.2# mount -o remount,rw /
bash-5.2# cat /etc/hostname
lab-adm
bash-5.2# sync ; exec /sbin/init
```

**6. Mesure du boot**

```bash
systemd-analyze ; systemd-analyze blame | head ; systemd-analyze critical-chain
systemd-analyze plot > ~/lab09/rapports/boot.svg
```

**7. Rapport** `~/lab09/rapports/demarrage.md` (extrait attendu) :

```text
Mode : BIOS (SeaBIOS)  — /sys/firmware/efi absent
1. MBR /dev/sda (boot.img 440 o) -> core.img dans sda1 (BIOS boot, 1 Mo)
2. /boot/grub/grub.cfg (généré, 12 Ko) -> menu 5 s, série + tty0
3. /boot/vmlinuz-6.8.0-52-generic (14 Mo) + initrd.img-6.8.0-52 (71 Mo)
4. initramfs : virtio_scsi, dm-mod, vgchange -ay, root=/dev/mapper/...
5. switch_root -> /usr/lib/systemd/systemd (PID 1) -> multi-user.target
Ligne noyau : BOOT_IMAGE=... root=... ro console=tty0 console=ttyS0,115200
Boot : kernel 4.1 s + userspace 9.6 s
Console de secours : qm set 9001 --serial0 socket ; console=ttyS0 dans GRUB ;
  qm terminal 9001 ; Ctrl-O pour sortir.
Mot de passe perdu : e ; init=/bin/bash ; mount -o remount,rw / ; passwd ;
  sync ; exec /sbin/init.
```

::: pourquoi
**Pourquoi `grub.d/90-*.cfg` plutôt qu'éditer `/etc/default/grub`.** Le
fichier principal appartient au paquet `grub-common` ; une mise à jour peut
proposer de le remplacer. Un fichier séparé, à rang élevé, est lu après et
gagne : c'est la même logique que les drop-ins systemd et que `sysctl.d`.
Le rang 90 passe après `50-cloudimg-settings.cfg` d'une image cloud.

**Deux `console=`.** Le noyau écrit ses messages sur **toutes** les consoles
listées, mais `/dev/console` (celle qui reçoit les entrées, et que systemd
utilise pour `sulogin`) est la **dernière**. `console=tty0 console=ttyS0`
donne donc la série comme console principale tout en gardant l'écran noVNC
informé. systemd voit `console=ttyS0` et démarre tout seul
`serial-getty@ttyS0.service` (générateur `systemd-getty-generator`) : pas
d'unité à activer.

**`rescue.target` contre `init=/bin/bash`.** La cible *rescue* démarre
systemd, monte les systèmes de fichiers, puis lance `sulogin`, qui demande le
mot de passe root. Sur Ubuntu, root est verrouillé : `sulogin` refuse. C'est
pratique sur Rocky (root a un mot de passe) et inutile sur Ubuntu sans
`--force`. `init=/bin/bash` court-circuite : le noyau lance bash comme PID 1,
sans systemd, sans PAM, racine en lecture seule — d'où le `remount,rw`. On en
sort par `exec /sbin/init` (bash est remplacé par systemd, le boot continue
normalement) ; `reboot` simple échouerait parce qu'il parle à un systemd
absent.

**`GRUB_TERMINAL="serial console"`** fait afficher le menu **sur les deux**
sorties et accepter les touches des deux : sans ça, la console série voit le
noyau démarrer mais jamais le menu, et l'étape 5 est impossible depuis
`qm terminal`.
:::

::: piege
Oublier `GRUB_TIMEOUT_STYLE=menu` : avec `hidden` et `GRUB_TIMEOUT=0`, le
menu ne s'affiche jamais, et intercepter avec `Échap` dans une console série
demande un timing de quelques dizaines de millisecondes. Un serveur de
production doit avoir un menu visible 3 à 5 s : ce n'est pas du confort,
c'est la condition du dépannage.

Autre piège : `qm terminal` ne rend pas la main. La sortie est `Ctrl-O`. Et
si tu ajoutes le port série **après** un boot, le noyau en cours ne l'a pas
énuméré : un reboot est nécessaire avant que `qm terminal` montre quoi que
ce soit.
:::

Variante Rocky :

```bash
sudo grubby --update-kernel=ALL --args="console=tty0 console=ttyS0,115200"
sudo grubby --info=DEFAULT | grep args
cat /boot/loader/entries/*.conf | grep options
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub
printf 'GRUB_TERMINAL="serial console"\nGRUB_SERIAL_COMMAND="serial \
--unit=0 --speed=115200"\n' | sudo tee -a /etc/default/grub
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
```

`grubby` a réécrit la ligne `options` de chaque fichier de
`/boot/loader/entries/` ; `grub2-mkconfig` ne régénère que le squelette
(`grub.cfg` avec `blscfg`) et les réglages de terminal. Le shell de secours :
`rd.break` sur la ligne `linux`, puis `mount -o remount,rw /sysroot`,
`chroot /sysroot`, et `touch /.autorelabel` après toute modification.

---

### **L9.2** — *Passer `lab-adm` au noyau HWE et tenir `/boot` propre.*

**1. Inventaire avant**

```bash
{ uname -r ; dpkg -l 'linux-image-*' | grep ^ii ; ls -lh /boot ; df -h /boot
  grep -E '^GRUB_DEFAULT' /etc/default/grub ; } | \
  tee ~/lab09/rapports/noyaux-avant.txt
```

**2. Installation HWE**

```bash
sudo apt update
sudo apt install -y linux-generic-hwe-24.04
grep -E '^menuentry' /boot/grub/grub.cfg | head -1     # le HWE en premier
ls -lh /boot/initrd.img-* /boot/vmlinuz-*
```

**3. Reboot**

```bash
sudo reboot
uname -r          # 6.14.0-xx-generic (ou plus récent selon le point release)
dpkg -l 'linux-image-6.8*' | grep ^ii      # le 6.8 conservé comme repli
```

**4. Démarrer sur l'ancien noyau**

Dans `qm terminal 9001` : *Advanced options for Ubuntu* → l'entrée 6.8.
`uname -r` → `6.8.0-52-generic`. Rebooter sur le HWE. Pour fixer un repli
comme défaut :

```bash
grep -E "menuentry '|submenu '" /boot/grub/grub.cfg | grep -o "gnulinux[^']*"
# gnulinux-advanced-<uuid>          (le sous-menu)
# gnulinux-6.8.0-52-generic-advanced-<uuid>
```

```ini
GRUB_DEFAULT="gnulinux-advanced-<uuid>>\
gnulinux-6.8.0-52-generic-advanced-<uuid>"
```

puis `update-grub`. `GRUB_DEFAULT=saved` + `grub-set-default` ou
`grub-reboot 'entrée'` (une seule fois) sont les alternatives.

**5. Purge et protection du noyau courant**

```bash
sudo apt autoremove --purge
dpkg -l 'linux-image-*' | grep ^ii
sudo apt purge linux-image-$(uname -r)
# -> "You are running a kernel (version ...) and attempting to remove
#     the same version." ... Abort kernel removal? [Y/n]
cat /etc/apt/apt.conf.d/01autoremove-kernels
```

**6. Capacité de `/boot`**

```bash
du -ch /boot/*-$(uname -r) | tail -1        # ~95M par version
df -B1M --output=size,avail /boot           # 2048  1750
```

Avec 95 Mo par version et 2 Go, une quinzaine de versions tiennent ;
`update-initramfs` a besoin d'un espace libre au moins égal à la taille du
nouvel initrd **en plus** de l'ancien, parce qu'il écrit `initrd.img-X.new`
puis renomme : il échouerait vers 18 versions, ou bien plus tôt sur un
`/boot` de 1 Go (à partir de 8 à 9).

**7. Rapport et Secure Boot**

```bash
mokutil --sb-state                              # SecureBoot disabled (SeaBIOS)
sudo dmesg | grep -i 'secure boot'
modinfo -F signer virtio_net ; modinfo -F sig_key virtio_net | head -c 60
```

::: pourquoi
**HWE.** Ubuntu LTS livre son noyau d'origine (GA, 6.8 pour 24.04) pendant
cinq ans, et propose en parallèle le noyau de la version intermédiaire
suivante, mis à jour à chaque *point release* (`24.04.2` → 6.11, `24.04.3` →
6.14, et ainsi de suite jusqu'au noyau de la LTS suivante). Le métapaquet
`linux-generic-hwe-24.04` suit ce train : chaque mise à jour peut changer de
version majeure, ce qui casse les modules DKMS plus souvent. GA = stabilité
maximale, HWE = matériel et fonctionnalités récents. Un serveur sans besoin
particulier reste en GA ; on passe en HWE pour un pilote, ou parce que le
noyau GA sera abandonné avant la fin de la LTS.

**Pourquoi le nouveau noyau est en tête.** `/etc/grub.d/10_linux` trie les
`vmlinuz-*` de `/boot` par version décroissante (`linux-version sort`), et
`GRUB_DEFAULT=0` désigne cette première entrée. Fixer un repli par
**identifiant** (`gnulinux-.. .`) et non par numéro évite que le défaut se
décale à la prochaine installation. Le `>` sépare le sous-menu de l'entrée.

**La protection du noyau courant.** Le script
`/etc/kernel/postinst.d/apt-auto-removal` génère
`/etc/apt/apt.conf.d/01autoremove-kernels` à chaque installation de noyau :
il y liste comme `APT::NeverAutoRemove` le noyau en cours, le plus récent et
le précédent. Un `apt purge` explicite du noyau courant déclenche
`linux-check-removal`, qui demande confirmation ; il n'interdit pas, il
prévient — et sur une machine sans terminal interactif, `apt -y` passerait
outre. `apt-mark hold` sur `linux-image-$(uname -r)` est la ceinture.

**Secure Boot en SeaBIOS.** Il n'y a pas de Secure Boot sans UEFI :
`mokutil` répond `EFI variables are not supported on this system`. Sur une VM
OVMF avec les clés pré-enrôlées, `SecureBoot enabled`, `dmesg` montre
`Secure boot enabled` et `Kernel is locked down`, et un module DKMS devrait
être signé avec la clé de `/var/lib/shim-signed/mok/` enrôlée via
`mokutil --import`. Les modules Ubuntu sont signés par la clé de build du
noyau : `signer: Build time autogenerated kernel key`.
:::

Variante Rocky :

```bash
sudo grubby --info=ALL | grep -E '^(index|kernel|title)'
sudo grubby --default-kernel
dnf list installed 'kernel*'
grep installonly_limit /etc/dnf/dnf.conf          # 3
sudo dnf check-update kernel ; sudo dnf install -y kernel
sudo grubby --set-default /boot/vmlinuz-5.14.0-570.12.1.el9_6.x86_64
sudo dnf remove --oldinstallonly -y
sudo dnf remove kernel-core-$(uname -r)
# -> Error: Problem: The operation would result in removing the following
#    protected packages: kernel-core
```

`kernel` est un métapaquet qui tire `kernel-core` (`vmlinuz`, l'initramfs
généré par `dracut`, les modules indispensables au boot) et
`kernel-modules` (les pilotes courants : réseau, stockage, USB) ; depuis
9.2, `kernel-modules-core` porte les modules nécessaires au démarrage et
`kernel-modules-extra` les pilotes rares. Une VM minimale peut vivre avec
`kernel-core` seul. `installonly_limit=3` : `dnf` **n'écrase jamais** un
noyau, il en garde trois et supprime le plus ancien à la quatrième
installation ; `dnf remove --oldinstallonly` purge tout sauf le courant et le
plus récent.

---

### **L9.3** — *Modules : interface `dummy`, module interdit, inventaire
virtio.*

**1. Inventaire virtio**

```bash
lsmod | grep -E '^virtio'
for d in /sys/class/net/ens18 /sys/block/sda ; do
  printf '%s -> %s\n' "$d" "$(readlink -f $d/device | xargs -I{} sh -c \
    'basename $(readlink {}/driver 2>/dev/null || readlink {}/../../driver)')"
done
udevadm info -q property -n /dev/sda | grep -E 'ID_BUS|ID_PATH'
lspci -k | grep -A2 -i virtio
```

| Périphérique | Pilote | Module | Bus |
|---|---|---|---|
| `ens18` | `virtio_net` | `virtio_net` | virtio sur PCI `0000:00:12.0` |
| `sda` | `sd` → `virtio_scsi` | `virtio_scsi` | SCSI `2:0:0:0` sur PCI `0000:05:00.0` |
| mémoire ballon | `virtio_balloon` | `virtio_balloon` | PCI `0000:00:03.0` |

**2. et 3. `dummy` persistant**

```bash
sudo modprobe dummy numdummies=2 && ip -br link | grep dummy && \
  cat /sys/module/dummy/parameters/numdummies && sudo modprobe -r dummy
echo 'options dummy numdummies=2' | sudo tee /etc/modprobe.d/dummy.conf
echo dummy | sudo tee /etc/modules-load.d/dummy.conf
sudo systemctl restart systemd-modules-load.service
ip -br link | grep -c dummy                       # 2
```

**4. Adresse persistante (Netplan)**

```yaml
# /etc/netplan/60-dummy.yaml
network:
  version: 2
  ethernets:
    dummy0:
      addresses: [10.10.99.10/32]
```

```bash
sudo chmod 600 /etc/netplan/60-dummy.yaml
sudo netplan try ; sudo netplan apply
ip -4 -br addr show dummy0        # dummy0  UNKNOWN  10.10.99.10/32
```

**5. Blacklist dure**

```bash
lsmod | grep -E '^(joydev|mac_hid|pcspkr)'
sudo tee /etc/modprobe.d/blacklist-lab.conf >/dev/null <<'EOF'
# OPS-418 : aucune manette de jeu sur un serveur
blacklist joydev
install joydev /bin/false
EOF
sudo modprobe -r joydev
sudo modprobe joydev ; echo "code $?"     # modprobe: ERROR: ... /bin/false
sudo update-initramfs -u
lsinitramfs /boot/initrd.img-$(uname -r) | grep blacklist-lab
sudo reboot
lsmod | grep -c joydev                    # 0
```

**6. et 7.** Après le reboot final : `ip -br addr | grep dummy` montre
`dummy0` avec l'adresse et `dummy1` sans ; rapport `~/lab09/rapports/modules.md`.

::: pourquoi
**Remonter du périphérique au pilote.** `lsmod` liste ce qui est chargé, pas
ce qui sert. Le lien `device/driver` de `/sys` est posé par le noyau au
moment où un pilote **réclame** (*probe*) le périphérique ; c'est la seule
preuve. Pour un disque SCSI, `sd` est le pilote de haut niveau (commun aux
disques SATA, SAS, USB, virtio-scsi), et l'hôte SCSI deux niveaux plus haut
révèle `virtio_scsi`. `lspci -k` donne le même résultat côté PCI (`Kernel
driver in use: virtio-pci`) mais pas le pilote de la fonction virtio.

**Le redémarrage de `systemd-modules-load`.** L'unité est `Type=oneshot`,
`RemainAfterExit=yes` : la redémarrer rejoue la lecture de
`modules-load.d`, donc un `modprobe dummy`, qui applique
`/etc/modprobe.d/dummy.conf`. Si `dummy` était resté chargé avec
`numdummies=1`, le `modprobe` n'aurait rien fait (déjà chargé) et tu
n'aurais qu'une interface — d'où le `modprobe -r` avant. Vérifier « deux
interfaces » teste réellement les deux fichiers.

**Netplan et `dummy0`.** Netplan (backend `systemd-networkd` sur Ubuntu
Server) configure une interface dès qu'elle apparaît, par son nom : il
n'a pas besoin de la créer. Sur Rocky, NetworkManager sait créer
l'interface lui-même (`type dummy`), ce qui dispense de `modules-load.d` —
mais pas de `modprobe.d` pour `numdummies` si on en veut deux.

**`blacklist` + `install`.** `blacklist` bloque le chargement par alias
(udev, `modprobe` d'un `modalias`) ; `install X /bin/false` fait exécuter
`/bin/false` à la place de l'insertion, y compris pour `modprobe joydev` et
pour une dépendance. Ensemble, c'est l'interdiction que demandent les guides
de durcissement (CIS : `install cramfs /bin/false`, `install usb-storage
/bin/false`). Pourquoi régénérer l'initramfs alors que `joydev` ne sert pas
au boot : parce que `initramfs-tools` **copie** `/etc/modprobe.d/` dans
l'archive, et qu'un pilote de stockage ou réseau blacklisté par erreur y
serait bloqué aussi — ou, inversement, qu'une blacklist retirée resterait
active dans l'initrd jusqu'à régénération. Régénérer systématiquement évite
d'avoir deux vérités.

**DKMS.** *Dynamic Kernel Module Support* recompile automatiquement un module
tiers (ZFS, pilotes NVIDIA, VirtualBox, WireGuard sur vieux noyaux) à chaque
installation de noyau, via un *hook* dans `/etc/kernel/postinst.d/dkms`.
`dkms status` liste les modules et leur état par version de noyau ; un
module `added` mais pas `installed` après une mise à jour de noyau est la
cause classique du « ça marchait avant le reboot ».
:::

::: piege
Un module qui refuse de se décharger (`rmmod: ERROR: Module dummy is in
use`) est un module dont un périphérique est encore utilisé : ici `dummy0`
avec une adresse tenue par networkd. `ip link del dummy0` ou `netplan`
d'abord. Et `modprobe -r` ne retire que le module **et ses dépendances
devenues inutiles** ; `rmmod` ne retire que lui.
:::

---

### **L9.4** — *Un disque à chaud, un nom stable, un ordonnanceur adapté.*

**1. Hotplug observé**

Terminal 1 sur `lab-adm` : `sudo udevadm monitor -u -k`. Sur Proxmox :

```bash
qm set 9001 --scsi1 local-lvm:1
```

```text
KERNEL[512.1] add /devices/.../virtio4/host2/target2:0:1/2:0:1:0 (scsi)
KERNEL[512.1] add /devices/.../2:0:1:0/block/sdb (block)
UDEV  [512.2] add /devices/.../2:0:1:0/block/sdb (block)
```

Si rien n'arrive (contrôleur sans notification) :

```bash
echo '- - -' | sudo tee /sys/class/scsi_host/host*/scan
# ou : sudo rescan-scsi-bus.sh
```

**2. Identification**

```bash
lsblk -o NAME,SIZE,HCTL,SERIAL,TRAN /dev/sdb
udevadm info -q property -n /dev/sdb | grep -E '^ID_(SERIAL|PATH|BUS)='
# ID_SERIAL=0QEMU_QEMU_HARDDISK_drive-scsi1
# ID_PATH=pci-0000:05:00.0-scsi-0:0:1:0
ls -l /dev/disk/by-*/ | grep sdb
```

`by-uuid` et `by-label` sont vides : ces liens viennent de `blkid`
(`60-persistent-storage.rules`, `IMPORT{builtin}="blkid"`), qui ne trouve
aucun système de fichiers sur un disque vierge.

**3. Règle udev**

```ini
# /etc/udev/rules.d/61-lab-disque.rules
SUBSYSTEM=="block", KERNEL=="sd*", ENV{DEVTYPE}=="disk", \
  ENV{ID_SERIAL}=="0QEMU_QEMU_HARDDISK_drive-scsi1", \
  SYMLINK+="disk/lab/cache", ATTR{queue/scheduler}="none"
```

```bash
sudo udevadm test /sys/block/sdb 2>&1 | grep -E 'lab-disque|DEVLINKS|scheduler'
sudo udevadm control --reload
sudo udevadm trigger --action=add /dev/sdb ; udevadm settle
ls -l /dev/disk/lab/cache                    # -> ../../sdb
cat /sys/block/sdb/queue/scheduler           # mq-deadline [none] kyber bfq
```

**4. Format et label**

```bash
sudo mkfs.ext4 -L cache /dev/disk/lab/cache
ls -l /dev/disk/by-label/cache /dev/disk/by-uuid/ | grep sdb
```

**5. Agrandissement à chaud**

```bash
# Proxmox
qm disk resize 9001 scsi1 +1G
# lab-adm
lsblk /dev/sdb                                    # encore 1G
echo 1 | sudo tee /sys/class/block/sdb/device/rescan
lsblk /dev/sdb                                    # 2G
sudo mount /dev/disk/lab/cache /mnt && sudo resize2fs /dev/disk/lab/cache
df -h /mnt ; sudo umount /mnt
```

**6. Nom d'interface, à blanc**

```ini
# ~/lab09/udev/70-lan.rules
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="bc:24:11:3e:7a:10", \
  NAME="lan0"
```

```ini
# ~/lab09/udev/10-lan.link
[Match]
MACAddress=bc:24:11:3e:7a:10
[Link]
Name=lan0
```

```bash
sudo mkdir -p /run/udev/rules.d
sudo cp ~/lab09/udev/70-lan.rules /run/udev/rules.d/
sudo udevadm control --reload
sudo udevadm test /sys/class/net/ens18 2>&1 | grep -E '^NAME=|70-lan'
# NAME=lan0
sudo rm /run/udev/rules.d/70-lan.rules ; sudo udevadm control --reload
```

::: pourquoi
**Pourquoi l'événement arrive tout seul.** Le contrôleur virtio-scsi de QEMU
supporte le *hotplug* : il signale l'ajout d'une cible, le pilote
`virtio_scsi` déclenche un *scan* de la cible, la couche SCSI crée
`2:0:1:0` (hôte 2, canal 0, cible 1, LUN 0 — `HCTL`), `sd` réclame le disque,
le noyau alloue `sdb` et émet les uevents. Le `echo '- - -' > .../scan`
(*wildcard* canal, cible, LUN) demande le même scan à la main : nécessaire
sur des contrôleurs sans notification (certains SAS physiques, iSCSI après
ajout d'un LUN), inutile ici mais à connaître. Le `rescan` par disque, lui,
relit la **capacité** : c'est ce que fait `echo 1 > device/rescan` après un
`qm disk resize`, sans quoi le noyau garde l'ancienne taille en cache.

**Anatomie de la règle.** `SUBSYSTEM=="block"` et `ENV{DEVTYPE}=="disk"`
limitent aux disques entiers (pas aux partitions, qui ont leur propre uevent
avec `DEVTYPE=partition` et hériteraient sinon du lien). `ENV{ID_SERIAL}`
est une propriété importée par une règle **antérieure** :
`60-persistent-storage.rules` exécute `scsi_id` et `blkid`. Ta règle doit
donc trier **après** elle : l'ordre est alphabétique sur le nom de fichier,
et `60-lab-disque.rules` passerait **avant** `60-persistent-storage.rules`
(`l` < `p`) — `ID_SERIAL` serait encore vide au moment du test, et le lien
ne serait jamais créé. D'où le rang `61`. `udevadm test` révèle ce genre
d'erreur : la règle est bien lue, mais ne correspond pas.
`ATTR{queue/scheduler}=` écrit
dans le fichier `sysfs` du périphérique : l'affectation `=` sur `ATTR{}`
est **le** mécanisme de persistance des réglages `/sys`.

**`SYMLINK+=` et jamais `NAME=` pour un disque.** udev refuse de renommer
un nœud bloc (`NAME=` est ignoré avec un avertissement pour tout sauf les
interfaces réseau) : le nom `sdb` est au noyau, les liens sont à udev. Le
lien `/dev/disk/lab/cache` survit à un changement d'ordre d'énumération, à
un changement de contrôleur, et à une réinstallation — tant que le disque
garde son nom de *drive* dans la configuration de la VM.

**Le `.link` contre la règle udev.** Depuis systemd 209, le nommage des
interfaces est fait par udev via le *builtin* `net_setup_link`
(`80-net-setup-link.rules`), qui lit les fichiers `.link` et applique la
politique `NamePolicy=` de `99-default.link` (`ens18` = *slot* PCI 18). Une
règle `NAME=` dans un fichier de rang inférieur à 80 gagne, parce que
`80-net-setup-link` ne pose `NAME` que s'il est encore vide. Un `.link` est
préférable : même syntaxe partout, testable avec `udevadm test-builtin
net_setup_link /sys/class/net/ens18`, et compris par Netplan (`set-name:`
génère justement un `.link`).
:::

::: piege
`udevadm trigger` sans cible rejoue **tous** les périphériques : sur un
serveur, ça ré-exécute toutes les règles `RUN+=`, remet les permissions, et
peut faire réapparaître des liens supprimés. Toujours cibler
(`--name-match`, `--subsystem-match`, ou le chemin). Et `udevadm test`
n'applique rien — il liste les `RUN+=` sans les lancer, mais exécute pour de vrai les `PROGRAM=` et `IMPORT{program}=` : un programme à effet de bord appelé ainsi agit même «  à blanc ».
:::

---

### **L9.5** — *Un serveur de temps pour le lab, et une horloge qui dérive.*

**1. État initial et installation**

```bash
timedatectl                              # NTP service: active (timesyncd)
timedatectl timesync-status | head -4    # Server: ntp.ubuntu.com
sudo hwclock --show
sudo apt install -y chrony
systemctl is-active systemd-timesyncd chrony    # inactive / active
systemctl status systemd-timesyncd 2>&1 | head -1
# Unit systemd-timesyncd.service could not be found. (paquet retiré)
```

**2. Serveur sur `lab-adm`**

```ini
# /etc/chrony/conf.d/10-lab-serveur.conf
allow 10.10.10.0/24
local stratum 10
```

Les sources amont restent celles du fichier livré (`pool ntp.ubuntu.com
iburst maxsources 4`, plus les pools Debian). Pour préférer la passerelle :

```ini
# /etc/chrony/sources.d/10-passerelle.sources
server 10.10.10.1 iburst prefer
```

```bash
sudo systemctl restart chrony
chronyc tracking ; chronyc sources -v
sudo ss -ulpn | grep ':123 '
```

```text
Reference ID    : 5BC8ED0A (ntp3.example.net)
Stratum         : 3
Ref time (UTC)  : Sat Sep 19 10:20:41 2026
System time     : 0.000212 seconds slow of NTP time
Last offset     : -0.000118 seconds
RMS offset      : 0.000340 seconds
Frequency       : 12.317 ppm fast
Skew            : 0.104 ppm
Root delay      : 0.021 seconds
Leap status     : Normal
```

**3. Client `lab-web`**

```bash
sudo apt install -y chrony
sudo sed -i 's/^\(pool\|server\) /#&/' /etc/chrony/chrony.conf
echo 'server 10.10.10.10 iburst prefer' | \
  sudo tee /etc/chrony/sources.d/10-lab-adm.sources
sudo systemctl restart chrony
chronyc sources                    # ^* 10.10.10.10   11   6   377   12  ...
# sur lab-adm :
sudo chronyc clients               # 10.10.10.11  ...
```

**4. Client `lab-rhel`**

```bash
sudo sed -i 's/^\(pool\|server\) /#&/' /etc/chrony.conf
echo 'server 10.10.10.10 iburst prefer' | sudo tee -a /etc/chrony.conf
sudo systemctl restart chronyd ; chronyc sources
```

**5. Dérive contrôlée**

```bash
sudo date -s "$(date -d '+3 minutes')"
for i in 1 2 3 4 5 6 ; do chronyc tracking | \
  grep -E 'System time|Last offset|Frequency' ; sleep 10 ; done
```

```text
System time     : 179.998 seconds fast of NTP time
Last offset     : -179.9984 seconds
Frequency       : 12.317 ppm fast
```

Slew à la vitesse maximale : `maxslewrate 83333.333` ppm = 8,33 % →
180 s / 0,0833 ≈ 2 160 s ≈ **36 minutes**. Forcer :

```bash
sudo chronyc makestep              # 200 OK
chronyc tracking | grep 'System time'    # 0.000xxx seconds
```

`makestep 1 3` dans `/etc/chrony/chrony.conf` : sauter si l'écart dépasse
1 s, **seulement pendant les 3 premières mises à jour** après le démarrage
de `chronyd`. Le service tournait depuis plus longtemps : il n'a pas le droit
de sauter, il *slew*. `makestep 1 -1` autoriserait le saut à tout moment
(choix courant sur des VM).

**6. Fuseau**

```bash
sudo timedatectl set-timezone Europe/Paris
timedatectl | grep -E 'Local|Universal|RTC'
ls -l /etc/localtime              # -> /usr/share/zoneinfo/Europe/Paris
date ; date -u ; journalctl -n1 -o short --no-pager ; ls -l /etc/hostname
```

Le RTC reste en UTC (`RTC in local TZ: no`), l'horloge système compte des
secondes UTC (`date +%s` ne change pas), seule la **représentation** suit
`/etc/localtime`.

::: pourquoi
**Ce qu'installer chrony change.** Le paquet `chrony` déclare
`Conflicts: time-daemon` et `Provides: time-daemon` ; comme `systemd-timesyncd` fournit le même `time-daemon`, `apt` le retire en installant chrony : deux démons NTP se battraient pour la même
horloge. chrony apporte ce que timesyncd n'a pas : plusieurs sources
comparées (l'algorithme écarte un *falseticker*), un serveur, un mode
sans réseau (`local stratum`), la mesure de la dérive de fréquence
persistante (`driftfile`), et `chronyc` pour le diagnostic.

**`local stratum 10`.** Si toutes les sources amont deviennent
injoignables, chrony refuse normalement de servir (il se déclare
non synchronisé et les clients l'ignorent). `local stratum 10` lui fait
servir sa propre horloge à une strate basse (10, contre 2 ou 3 quand il est
synchronisé) : les VM du lab restent **cohérentes entre elles** même si
Internet tombe, ce qui est ce qui compte pour les journaux, TLS interne et
Kerberos. La strate 10 signale honnêtement aux clients que la source est
médiocre.

**Lire `tracking`.** `Reference ID` = la source retenue ; `Stratum` = la
distance à une horloge de référence ; `System time` = l'écart **actuel**
que chrony est en train de résorber ; `Last offset` = l'écart mesuré à la
dernière réponse ; `Frequency` = de combien l'horloge locale dérive
naturellement (12 ppm = 1 s par jour, typique d'une VM), et `Skew` la
confiance sur cette estimation ; `Leap status : Normal` = synchronisé
(`Not synchronised` sinon). Dans `sources`, `^*` est la source retenue,
`^+` une source combinée, `^-` écartée, `^?` injoignable ; `Reach 377` en
octal = les 8 dernières requêtes ont répondu.

**Slew contre step.** chrony n'accélère ou ne ralentit l'horloge que de
8,33 % maximum pour que les applications ne voient jamais le temps sauter.
C'est excellent pour 100 ms, absurde pour 3 minutes. D'où `makestep` avec
une fenêtre au démarrage (le cas normal : le RTC était faux) et `chronyc
makestep` en intervention. Un `date -s` corrige aussi, mais **sans** que
chrony le sache : il continue de croire à l'ancien écart et peut
sur-corriger, et l'horloge matérielle n'est pas recalée.

**RTC en UTC.** `hwclock` écrit dans le RTC ce que dit `/etc/adjtime`
(`UTC`) ; à `LOCAL`, chaque changement d'heure d'été impose une correction
et un double boot avec Windows la double. Un serveur n'a aucune raison
d'avoir autre chose qu'UTC dans le matériel, et Ubuntu comme Rocky le font
par défaut.
:::

::: piege
`chronyc clients` sur le serveur affiche des compteurs vides tant que le
service n'a pas reçu de requête depuis son démarrage : redémarre le serveur
**avant** les clients, pas après. Et sur Rocky, `firewalld` bloque l'UDP 123
entrant si tu faisais de `lab-rhel` le serveur : `firewall-cmd
--add-service=ntp --permanent`. Un client, lui, n'ouvre rien.
:::

---

## 9.7 Break & Fix

### **BF9.1** — *La mise à jour du noyau échoue, `/boot` est plein.*

**Démarche de diagnostic**

```bash
sudo update-initramfs -u
# update-initramfs: Generating /boot/initrd.img-6.8.0-52-generic
# zstd: error 70 : Write error : cannot write block : No space left on device
# E: mkinitramfs failure zstd -q -1 -T0 70
# update-initramfs: failed for /boot/initrd.img-6.8.0-52-generic with 1.
df -h / /boot
# /dev/sda2   2.0G  2.0G  3.2M 100% /boot
uname -r                                   # 6.8.0-52-generic : à protéger
dpkg -l 'linux-image-*' | grep ^ii         # une seule version installée
ls -lh /boot
```

```text
-rw-r--r-- 1 root root 280K config-6.8.0-31-generic
-rw-r--r-- 1 root root 280K config-6.8.0-35-generic
-rw-r--r-- 1 root root 280K config-6.8.0-52-generic
-rw-r--r-- 1 root root 890M initrd.img-6.8.0-31-generic
-rw-r--r-- 1 root root 890M initrd.img-6.8.0-35-generic
-rw-r--r-- 1 root root  71M initrd.img-6.8.0-52-generic
...
```

Deux versions présentes dans `/boot` mais **absentes de `dpkg -l`** : des
fichiers orphelins. Confirmation fichier par fichier :

```bash
for f in /boot/vmlinuz-* /boot/initrd.img-* /boot/System.map-* /boot/config-*
do dpkg -S "$f" >/dev/null 2>&1 || echo "ORPHELIN $f" ; done
```

`initrd.img-*` n'appartient **jamais** à un paquet (il est généré), donc le
test doit porter sur `vmlinuz-*` et `System.map-*` : si le `vmlinuz` d'une
version est orphelin, toute la version l'est.

**Cause racine** : des noyaux ont été retirés sans purge (`apt remove` au lieu
de `apt purge`, ou suppression manuelle du paquet avec `dpkg --force`), ou des
fichiers ont été copiés à la main : leurs `vmlinuz`/`initrd` sont restés dans
`/boot`. La partition est pleine, `mkinitramfs` ne peut plus écrire
`initrd.img-X.new`.

**Correctif**

```bash
sudo apt autoremove --purge                # ne trouve rien : pas de paquet
for v in 6.8.0-31-generic 6.8.0-35-generic ; do
  [ "$v" = "$(uname -r)" ] && { echo "refus : noyau courant" ; continue ; }
  sudo rm -f /boot/{vmlinuz,initrd.img,System.map,config}-$v
done
df -h /boot                                # 11 %
sudo dpkg --configure -a ; sudo apt -f install      # rien à faire
sudo update-initramfs -u -k all && sudo update-grub
grep -c '^menuentry\|^\s*menuentry' /boot/grub/grub.cfg
```

**Prévention** : un `apt purge` (pas `remove`) des noyaux, `apt autoremove
--purge` après chaque mise à jour de noyau (`unattended-upgrades` le fait avec
`Unattended-Upgrade::Remove-Unused-Kernel-Packages "true"`, activé par
défaut sur 24.04), et une alerte de supervision sur `/boot` à 70 % (module 16).
Un contrôle mensuel : `ls /boot/vmlinuz-* | wc -l` doit valoir le nombre de
paquets `linux-image-*` installés.

::: pourquoi
**Pourquoi `update-grub` après le nettoyage.** `10_linux` génère une entrée
pour chaque `vmlinuz-*` trouvé dans `/boot`, orphelin ou pas : avant le
nettoyage, le menu proposait des noyaux dont l'initrd était un fichier
factice ; après, il ne propose que le vrai. Sans régénération, GRUB garde des
entrées vers des fichiers absents (`error: file not found` si on les choisit).

**Pourquoi `-k all`.** `update-initramfs -u` seul ne régénère que l'initrd
du noyau le plus récent ; après un incident de ce type, on veut être sûr que
chaque version restante a un initrd complet et non tronqué — un initrd
partiellement écrit puis renommé serait une bombe à retardement.
`mkinitramfs` écrit dans `.new` et renomme à la fin, donc l'échec n'a rien
abîmé, mais la vérification coûte dix secondes.

**Distinguer paquet et fichier.** `dpkg -S chemin` répond au nom du paquet
propriétaire ou `no path found matching pattern`. C'est la frontière entre ce
que `apt` sait gérer et ce que l'administrateur a laissé derrière lui. Sur
Rocky, l'équivalent est `rpm -qf /boot/vmlinuz-*`, et les orphelins y sont
plus rares parce que `dnf` retire aussi l'initramfs via le script `%preun`
du paquet `kernel-core`.
:::

::: piege
Supprimer « le plus vieux » sans regarder `uname -r`. Après un reboot manqué
ou un `grub-reboot`, la machine peut tourner sur un noyau qui n'est pas le
plus récent : `uname -r` est la seule vérité, et le `check` refuse toute
solution qui a touché aux fichiers de la version en cours. Et ne jamais
`rm /boot/initrd.img-<courant>` « pour faire de la place, on le régénère
après » : si la régénération échoue (elle vient d'échouer !), la machine ne
redémarre plus.
:::

---

### **BF9.2** — *Le `swappiness` revient à 60 à chaque reboot.*

**Démarche de diagnostic**

```bash
sysctl vm.swappiness net.core.somaxconn        # 60, 4096
ls -la /etc/sysctl.d/
# 10-factura.conf  20-factura-reseau  30-factura-conntrack.conf
# 99-sysctl.conf -> ../sysctl.conf
grep -rn 'swappiness\|somaxconn\|conntrack' /etc/sysctl.conf /etc/sysctl.d/
# /etc/sysctl.conf:70:vm.swappiness = 60
# /etc/sysctl.d/10-factura.conf:2:vm.swappiness = 10
# /etc/sysctl.d/20-factura-reseau:1:net.core.somaxconn = 8192
# /etc/sysctl.d/30-factura-conntrack.conf:1:net.netfilter.nf_conntrack_max
#   = 131072
sudo sysctl --system 2>&1 | grep -E '^\*|swappiness|somaxconn|conntrack|cannot'
journalctl -u systemd-sysctl -b --no-pager | tail -3
```

```text
* Applying /etc/sysctl.d/10-factura.conf ...
vm.swappiness = 10
* Applying /etc/sysctl.d/30-factura-conntrack.conf ...
sysctl: cannot stat /proc/sys/net/netfilter/nf_conntrack_max: No such file
or directory
* Applying /etc/sysctl.d/99-sysctl.conf ...
vm.swappiness = 60
* Applying /etc/sysctl.conf ...
vm.swappiness = 60
```

**Les trois causes**

1. `vm.swappiness = 10` est bien appliqué… puis **réécrit** par
   `/etc/sysctl.conf`, rejoué en position 99 via le lien `99-sysctl.conf` et
   encore une fois à la fin. Le dernier gagne : 60.
2. `20-factura-reseau` n'a pas l'extension `.conf` : il n'est **jamais lu**.
   `somaxconn` reste à 4096. `sysctl -p /etc/sysctl.d/20-factura-reseau`
   marche, parce que `-p` lit n'importe quel fichier, ce qui a masqué
   l'erreur.
3. `nf_conntrack_max` est posé alors que le module `nf_conntrack` n'est pas
   chargé au moment où `systemd-sysctl` passe : la clé n'existe pas,
   avertissement, valeur ignorée.

**Correctif**

```bash
sudo sed -i '/^vm.swappiness = 60/d' /etc/sysctl.conf
sudo mv /etc/sysctl.d/20-factura-reseau /etc/sysctl.d/20-factura-reseau.conf
echo nf_conntrack | sudo tee /etc/modules-load.d/nf_conntrack.conf
sudo modprobe nf_conntrack
sudo sysctl --system 2>&1 | grep -E 'swappiness|somaxconn|conntrack|cannot'
sysctl -n vm.swappiness net.core.somaxconn net.netfilter.nf_conntrack_max
sudo reboot        # puis les trois valeurs et journalctl -u systemd-sysctl -b
```

Et pour ne plus dépendre du rang : regrouper les trois clés dans **un**
fichier `/etc/sysctl.d/60-factura.conf` et supprimer les trois autres.

**Prévention** : ne rien écrire dans `/etc/sysctl.conf` (le laisser au
paquet), toujours `.conf`, un rang ≥ 60, `sysctl --system` comme test
d'acceptation (pas `-p`), et lire `journalctl -u systemd-sysctl -b` après
chaque reboot — c'est une ligne dans le script de contrôle de D9.

::: pourquoi
**Pourquoi le lien `99-sysctl.conf` existe.** Historiquement, `procps` lisait
`/etc/sysctl.conf` ; systemd lit `sysctl.d`. Pour que les anciennes
configurations restent appliquées par `systemd-sysctl.service`, Debian a
placé un lien symbolique dans `sysctl.d` vers le fichier historique, en
position 99 : « ce que l'administrateur a écrit dans `sysctl.conf` gagne sur
les paquets ». Conséquence : un fichier `sysctl.d` à rang inférieur à 99 est
subordonné à `sysctl.conf`. L'ordre affiché par `sysctl --system` le
prouve et suffit à convaincre le collègue.

**`sysctl -p` contre `sysctl --system`.** `-p fichier` applique un fichier
et un seul, immédiatement, sans précédence, sans filtre d'extension. C'est
un outil de test, jamais une preuve de persistance. `--system` rejoue
**exactement** ce que fait le boot. Quand un `sysctl` « ne tient pas », la
question à poser est « qu'affiche `--system` ? », pas « que contient mon
fichier ? ».

**Pourquoi pas `rc.local`.** Un script tardif appliquerait bien la valeur,
mais après que les services l'ont lue (`somaxconn` au `listen()`), sans
visibilité pour `sysctl --system`, et sans ordre garanti par rapport au
chargement de `nf_conntrack`. La solution systemd — `modules-load.d` puis
`sysctl.d` — est ordonnée par construction.
:::

---

### **BF9.3** — *Plus de réseau après le reboot : module blacklisté.*

**Démarche de diagnostic**

Depuis Proxmox, `qm terminal 9001`. La VM est démarrée, `login:` s'affiche,
mais le mot de passe est réputé inconnu. Reboot (`qm reset 9001` ou
`Ctrl-Alt-Suppr` dans noVNC), menu GRUB, `e`, fin de ligne `linux` :

```text
init=/bin/bash
```

`Ctrl-x`. Dans le shell :

```bash
mount -o remount,rw /
mount -t proc proc /proc 2>/dev/null ; mount -t sysfs sys /sys 2>/dev/null
ls /sys/class/net                        # lo seulement
cat /sys/bus/pci/devices/*/modalias | grep -i 1af4   # le périphérique est là
grep -rn virtio /etc/modprobe.d/
# /etc/modprobe.d/durcissement-pilotes.conf:5:blacklist virtio_net
# /etc/modprobe.d/durcissement-pilotes.conf:6:install virtio_net /bin/false
```

**Cause racine** : un fichier de durcissement interdit le pilote de la
**seule** interface réseau de la VM. Au boot, udev lit le `modalias`
`virtio:d00000001v00001AF4`, `modprobe` résout l'alias vers `virtio_net`,
trouve la `blacklist` → alias ignoré. Même un chargement explicite par un
autre chemin tombe sur `install ... /bin/false`.

**Correctif**

```bash
sed -i '/virtio_net/d' /etc/modprobe.d/durcissement-pilotes.conf
cat /etc/modprobe.d/durcissement-pilotes.conf     # relire ce qui reste
sync
exec /sbin/init
```

Le boot reprend, udev charge `virtio_net`, `ens18` réapparaît, Netplan
applique l'adresse. Puis, en SSH :

```bash
ip -br addr show ens18
sudo update-initramfs -u -k all
lsinitramfs /boot/initrd.img-$(uname -r) | grep durcissement
sudo unmkinitramfs /boot/initrd.img-$(uname -r) /tmp/ird && \
  grep virtio_net /tmp/ird/main/etc/modprobe.d/* ; echo "code $?"   # 1
```

**Prévention** : tout playbook de blacklist doit vérifier `lsmod` et les
liens `device/driver` avant d'interdire un module ; en revue, chaque
`blacklist` d'un pilote `virtio_*`, `e1000*`, `*_scsi`, `nvme`, `dm_*` est
un bloqueur. Et la console série avec menu GRUB visible (L9.1) est ce qui a
rendu la réparation possible en cinq minutes.

::: pourquoi
**Pourquoi `rescue.target` ne convenait pas.** La cible *rescue* lance
`sulogin`, qui exige le mot de passe root ; sur Ubuntu root est verrouillé,
et le mot de passe de `mathieu` est réputé inconnu. `emergency.target`
souffre du même `sulogin`. Seul `init=/bin/bash` donne un shell **sans
authentification**, parce qu'il remplace `init` : il n'y a plus personne
pour demander quoi que ce soit. Sur Rocky, `rd.break` joue le même rôle
depuis l'initramfs.

**Pourquoi le réseau revient sans toucher à l'initramfs.** L'initrd contient
une copie du fichier de blacklist, donc pendant l'initramfs `virtio_net`
reste interdit — mais l'initramfs n'a pas besoin du réseau pour monter `/`.
Après `switch_root`, `systemd-udevd` démarre depuis la vraie racine, rejoue
les uevents (*coldplug*, `systemd-udev-trigger.service`), et `modprobe` lit
le `/etc/modprobe.d` **de la vraie racine**, corrigé. Le pilote se charge.
On régénère quand même l'initrd pour n'avoir qu'une seule vérité : un jour,
la blacklist en cause portera sur `virtio_scsi`, et là l'initramfs bloquera
avant même le montage de la racine — et c'est `break=premount` sur la ligne
`linux` qui donnera un shell `(initramfs)` pour comprendre.

**`blacklist` et `install`, encore.** `blacklist` empêche uniquement la
résolution d'alias (le mécanisme d'udev). La ligne `install X /bin/false`
est celle qui aurait bloqué un `modprobe virtio_net` tapé à la main dans le
shell de secours. Un dépanneur qui ne connaît que `blacklist` aurait tenté
`modprobe virtio_net`, obtenu `modprobe: ERROR: ../libkmod/libkmod-module.c
... command failed`, et perdu du temps. Le `grep -rn` sur tout `modprobe.d`
évite de découvrir la seconde ligne après le reboot.

**Pourquoi `exec /sbin/init` et pas `reboot`.** Dans un shell PID 1, il n'y a
pas de systemd pour recevoir la demande de `reboot` ; `reboot -f` force via
l'appel système et saute tout arrêt propre (les tampons ont été poussés par
`sync`, mais un `fsck` peut suivre). `exec /sbin/init` remplace bash par
systemd, qui démarre normalement : c'est la sortie la plus propre et la plus
rapide.
:::

---

### **BF9.4** — *L'interface a changé de nom, Netplan ne trouve plus rien.*

**Démarche de diagnostic**

Console série. Connexion locale possible cette fois.

```bash
ip -br link                       # lo, net0 (DOWN), pas d'ens18
ip -br addr                       # net0 sans adresse
sudo netplan get # ethernets: ens18: addresses: [10.10.10.10/24]
journalctl -b -u systemd-networkd --no-pager | grep -i ens18
grep -rn 'NAME=' /etc/udev/rules.d/ /etc/systemd/network/*.link 2>/dev/null
# /etc/udev/rules.d/70-lab-net-stable.rules:1: ... ATTR{address}=="bc:24:11:..",
#   NAME="net0"
udevadm test /sys/class/net/net0 2>&1 | grep -E '^NAME=|70-lab'
```

**Cause racine** : une règle udev renomme l'interface en `net0` à l'événement
`add`, **avant** que networkd la voie. Netplan a généré
`/run/systemd/network/10-netplan-ens18.network` avec `[Match] Name=ens18` :
aucune interface ne correspond, rien n'est configuré. `netplan apply` ne se
plaint pas : la configuration est syntaxiquement valide, elle ne matche
juste rien.

**Correctif immédiat, sans reboot**

```bash
sudo rm /etc/udev/rules.d/70-lab-net-stable.rules
sudo udevadm control --reload
sudo ip link set net0 down
sudo ip link set net0 name ens18
sudo ip link set ens18 up
sudo netplan apply
ip -br addr show ens18            # 10.10.10.10/24
ping -c1 10.10.10.1
```

**Correctif durable** : la règle est supprimée, le prochain boot nomme
`ens18` par la politique par défaut (`99-default.link`, `NamePolicy=keep
kernel database onboard slot path`). Reboot et vérifier.

**La bonne façon de figer un nom**, si l'équipe y tient, dans Netplan :

```yaml
# /etc/netplan/50-cloud-init.yaml (ou le fichier existant)
network:
  version: 2
  ethernets:
    lan0:
      match:
        macaddress: "bc:24:11:3e:7a:10"
      set-name: lan0
      addresses: [10.10.10.10/24]
      routes: [{to: default, via: 10.10.10.1}]
      nameservers: {addresses: [10.10.10.1]}
```

Netplan génère alors **lui-même** le fichier `.link`
(`/run/systemd/network/10-netplan-lan0.link`) et le `.network` cohérent :
une seule source de vérité.

::: pourquoi
**Qui nomme une interface, et quand.** Le noyau crée l'interface avec un nom
provisoire (`eth0`). À l'uevent `add`, udev exécute les règles : une règle
`NAME=` explicite gagne si elle vient avant `80-net-setup-link.rules` ;
sinon le *builtin* `net_setup_link` lit les `.link` (`/etc/systemd/network`
puis `/run` puis `/usr/lib`, tri par nom) et applique `NamePolicy=` : `ens18`
vient de `slot` (numéro de slot PCI 18 de la carte virtio). Le renommage
n'est possible **qu'à ce moment** : une interface déjà `up` ne se renomme pas
(`RTNETLINK answers: Device or resource busy`), d'où le `down` obligatoire
dans le correctif à chaud. Après, networkd (piloté par Netplan) cherche une
interface qui matche `[Match] Name=` ou `MACAddress=` : c'est là que la
configuration s'applique — ou non.

**Priorités.** Règle udev `NAME=` avec un rang < 80 > fichier `.link` >
politique par défaut. Netplan `set-name` produit un `.link` dans `/run`, qui
passe **après** un `.link` de `/etc` de même nom, et après toute règle
udev `NAME=`. La règle du collègue gagnait donc sur tout, et Netplan ne
pouvait rien. Avec `match: macaddress` + `set-name`, Netplan possède les
deux bouts : le nom et la configuration.

**Pourquoi « stable » était déjà le cas.** `ens18` **est** un nom stable :
il dépend du slot PCI, pas de l'ordre de détection ni du MAC. La règle
ajoutée ne résolvait aucun problème réel ; elle en créait un. Les noms
prévisibles (`enX`, `ensX`, `enpXsY`) existent précisément pour ne plus
avoir à écrire ces règles. Le cas légitime : une machine physique dont on
remplace une carte et dont on veut conserver le nom dans la conf — et là,
Netplan `match`/`set-name` ou un `.link` dans `/etc` sont les outils.
:::

::: piege
Renommer une interface à chaud sans la mettre `down` échoue ; la mettre
`down` sur la **seule** interface d'une machine distante coupe SSH — c'est
pour ça que ce Break & Fix se joue en console série. En production, sur une
machine sans console, on corrige la règle et on redémarre dans une fenêtre
de maintenance ; on ne renomme jamais à chaud en SSH.
:::

---

### **BF9.5** — *Tout ce qui est en HTTPS échoue : horloge dérivée.*

**Démarche de diagnostic**

```bash
date ; date -u                    # 44 jours dans le passé
timedatectl
# System clock synchronized: no      NTP service: inactive
sudo hwclock --show               # le RTC aussi est faux
systemctl status chrony | grep -E 'Loaded|Active'
# Loaded: ... disabled       Active: inactive (dead)
grep -nE '^#?makestep' /etc/chrony/chrony.conf     # #makestep 1 3
curl -sSI https://deb.debian.org 2>&1 | head -1
# curl: (60) SSL certificate problem: certificate is not yet valid
sudo apt update 2>&1 | grep -i 'not valid yet'
```

**Cause racine** : le collègue a reculé l'heure (`date -s`), l'a écrite dans
le RTC (`hwclock --systohc`), et chrony a été arrêté et désactivé pour « que
le test tienne » ; la directive `makestep` a été commentée. L'horloge est à
−44 jours, aucun service ne la corrige. TLS voit les certificats émis depuis moins de 44 jours comme « pas encore valides » (`notBefore` dans le futur), et `apt` voit un fichier `Release`
dont le champ `Date` est dans le futur : `not valid yet (invalid for another 44d ...)`.

**Pourquoi chrony ne corrige pas tout seul (deux raisons)** : il est arrêté
et désactivé ; et même relancé, sans `makestep` il ne ferait que *slew* à
8,33 % — 44 jours d'écart demanderaient **plus d'un an** de rattrapage. Une fois `makestep 1 3` rétabli, le redémarrage de
chrony suffit à faire le saut; `chronyc makestep` le force de toute façon.

**Correctif**

```bash
sudo sed -i 's/^#makestep 1 3/makestep 1 3/' /etc/chrony/chrony.conf
sudo systemctl enable --now chrony
sleep 5 ; chronyc sources              # ^* ou ^+ sur une source
sudo chronyc makestep                  # 200 OK : saut immédiat
chronyc tracking | grep -E 'System time|Leap'
timedatectl | grep -E 'synchronized|NTP service'
sudo hwclock --systohc                 # recaler le RTC sans attendre 11 min
date ; curl -sSI https://deb.debian.org | head -1 ; sudo apt update
```

**Supervision minimale** : `chronyc tracking | awk '/System time/ {print
$4}'` en seuil (> 0,5 s = alerte), ou `timedatectl show -p NTPSynchronized
--value` = `no` ; avec `node_exporter` (module 16) :
`abs(node_timex_offset_seconds) > 0.5` et `node_timex_sync_status == 0`.

::: pourquoi
**TLS et le temps.** Un certificat X.509 porte `notBefore`/`notAfter`. Une
horloge en avance fait tomber tous les certificats des serveurs contactés
dans le passé : « expired ». En retard : « not yet valid ». Le client
vérifie, pas le serveur : c'est donc la machine cliente qu'on répare, et
`-k` (ignorer la vérification) désactive la seule protection contre une
interception. `apt` a sa propre fenêtre : `Valid-Until` dans `InRelease`,
justement pour empêcher qu'on rejoue un vieux dépôt contenant des paquets
vulnérables.

**Slew et step, la règle.** chrony n'accepte de **sauter** que si la
directive `makestep seuil nombre` l'y autorise ; `1 3` = plus de 1 s
d'écart dans les 3 premières mesures après démarrage. Passé ce cadre, il
*slew*. `chronyc makestep` (sans argument) force un saut **une fois**, quelle
que soit la configuration : c'est la commande d'intervention. Après le saut,
chrony mesure à nouveau et affine par slew.

**Pourquoi le RTC était faux.** Le noyau ne recopie l'heure système dans le
RTC (toutes les 11 minutes) **que** quand un démon NTP le lui dit (drapeau
`STA_UNSYNC` **abaissé** par chrony grâce à `rtcsync`). Sans chrony, seul
`hwclock --systohc` écrit — et le collègue l'a fait. Après correction, chrony
abaissera de nouveau le drapeau et le noyau recalera le RTC de lui-même, mais un
`hwclock --systohc` immédiat évite un reboot dans les 11 minutes qui
repartirait de l'heure fausse.

**`timedatectl set-ntp`.** Sur une machine avec chrony, `timedatectl
set-ntp true` active l'unité déclarée dans
`/usr/lib/systemd/ntp-units.d/50-chrony.list` — c'est équivalent à `systemctl
enable --now chrony`, et c'est ce que lit `NTP service: active`.
:::

::: piege
`date -s` sur la bonne heure « répare » TLS en dix secondes, et c'est
interdit ici pour une raison : sans service de temps, la dérive reprend, le
RTC reste faux, et le prochain incident arrive en silence. La preuve de
réparation n'est pas `date`, c'est `System clock synchronized: yes`.
:::

---

## 9.8 Défi du module

**D9 — Une base noyau de production pour les VM Factura**

### /etc/sysctl.d/60-factura.conf

```ini
# Base noyau Factura — OPS-430. Verifie par ~/lab09/bin/verif-noyau.sh
# --- memoire
vm.swappiness = 10                    # swap en dernier recours (base, cache)
vm.dirty_background_ratio = 5         # ecriture de fond plus tot, plus lisse
vm.dirty_ratio = 10                   # borne les rafales d'ecriture bloquantes
fs.inotify.max_user_watches = 524288  # agents, IDE, outils de build
# --- reseau
net.core.somaxconn = 8192             # backlog listen() (relu au restart)
net.ipv4.ip_local_port_range = 10240 65000   # plus de ports sortants
net.ipv4.ip_forward = 0               # pas un routeur (Docker le remet a 1)
net.netfilter.nf_conntrack_max = 131072      # exige nf_conntrack charge
# --- securite (detail module 18)
kernel.kptr_restrict = 2              # adresses noyau masquees, meme root
kernel.dmesg_restrict = 1             # dmesg reserve a root
kernel.sysrq = 176                    # reboot/sync/ro seulement au clavier
# --- robustesse
kernel.panic = 10                     # reboot 10 s apres un panic (kdump avant)
```

### /etc/modules-load.d/factura.conf et modprobe.d

```ini
# /etc/modules-load.d/factura.conf
nf_conntrack
```

```ini
# /etc/modprobe.d/blacklist-factura.conf
blacklist joydev
install joydev /bin/false
```

### GRUB : /etc/default/grub.d/90-factura.cfg

```ini
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0,115200 \
transparent_hugepage=madvise"
GRUB_TERMINAL="serial console"
GRUB_SERIAL_COMMAND="serial --unit=0 --speed=115200"
```

Le paquet `kdump-tools` a déjà déposé `/etc/default/grub.d/kdump-tools.cfg`
(`crashkernel=2G-4G:320M,4G-32G:512M,...`, ajouté à
`GRUB_CMDLINE_LINUX_DEFAULT`). Sur une VM de 2 Go, la RAM vue par le noyau
est **légèrement inférieure** à 2 Go : la plage `2G-4G` ne s'applique pas et
rien n'est réservé (`dmesg | grep -i crashkernel` : `crashkernel reservation
failed`). On fixe alors une valeur explicite dans ce même fichier :

```bash
sudo sed -i 's/crashkernel=[^" ]*/crashkernel=256M/' \
  /etc/default/grub.d/kdump-tools.cfg
sudo update-grub && sudo update-initramfs -u -k all
```

### kdump

```bash
sudo apt install -y linux-crashdump          # kdump-tools + crash
sudo sed -i 's/^USE_KDUMP=.*/USE_KDUMP=1/' /etc/default/kdump-tools
sudo systemctl enable kdump-tools
sudo reboot
kdump-config show
```

```text
DUMP_MODE:        kdump
USE_KDUMP:        1
KDUMP_COREDIR:    /var/crash
crashkernel addr: 0x6f000000
   /var/lib/kdump/vmlinuz: symbolic link to /boot/vmlinuz-6.8.0-52-generic
kdump initrd:
   /var/lib/kdump/initrd.img: symbolic link to
     /var/lib/kdump/initrd.img-6.8.0-52-generic
current state:    ready to kdump
```

Test réel (sur snapshot) :

```bash
cat /sys/kernel/kexec_crash_loaded          # 1
date ; echo c | sudo tee /proc/sysrq-trigger
# ... console série : "Kernel panic - not syncing: sysrq triggered crash"
# ... kdump-tools : "Starting kdump-tools ... saving vmcore" puis reboot
# après retour :
ls -lh /var/crash/*/                        # dmesg.* et dump.*
sudo crash /usr/lib/debug/boot/vmlinux-$(uname -r) /var/crash/*/dump.* \
  2>/dev/null <<< 'log' | tail -5           # si les symboles sont installés
```

Durée typique : 2 s pour le panic, 20 à 40 s pour la capture (2 Go de RAM,
compression), 30 s de reboot : **environ une minute et demie**.

### chrony client (~/lab09/conf/chrony-client.conf)

```ini
# /etc/chrony/sources.d/10-lab-adm.sources sur les VM clonees
server 10.10.10.10 iburst prefer
# et dans chrony.conf : pools publics commentes, makestep 1 -1
```

### ~/lab09/bin/verif-noyau.sh

```bash
#!/usr/bin/env bash
# verif-noyau.sh — conformite de la base noyau Factura (D9)
set -euo pipefail
FAIL=0
ok() { printf '[ OK ] %s\n' "$1"; }
ko() { printf '[FAIL] %s\n' "$1"; FAIL=1; }
want() {  # want cle valeur_attendue
  local v; v=$(sysctl -n "$1" 2>/dev/null || echo ABSENT)
  [ "$v" = "$2" ] && ok "$1 = $2" || ko "$1 = $v (attendu $2)"
}
want vm.swappiness 10
want vm.dirty_background_ratio 5
want vm.dirty_ratio 10
want fs.inotify.max_user_watches 524288
want net.core.somaxconn 8192
want net.ipv4.ip_local_port_range "$(printf '10240\t65000')"
want net.ipv4.ip_forward 0
want net.netfilter.nf_conntrack_max 131072
want kernel.sysrq 176
want kernel.panic 10
[ "$(cat /proc/sys/kernel/kptr_restrict)" = 2 ] \
  && ok "kptr_restrict=2 (/proc/sys)" || ko "kptr_restrict != 2"
[ "$(cat /proc/sys/kernel/dmesg_restrict)" = 1 ] \
  && ok "dmesg_restrict=1 (/proc/sys)" || ko "dmesg_restrict != 1"
lsmod | grep -q '^nf_conntrack ' && ok "nf_conntrack charge" \
  || ko "nf_conntrack absent"
if lsmod | grep -q '^joydev '; then ko "joydev charge"; else
  grep -qs '^install joydev /bin/false' /etc/modprobe.d/*.conf \
    && ok "joydev interdit et absent" || ko "joydev absent mais pas interdit"
fi
CMD=$(cat /proc/cmdline)
[[ $CMD == *console=ttyS0* ]] && ok "console serie" || ko "pas de console=ttyS0"
[[ $CMD == *transparent_hugepage=madvise* ]] && ok "THP madvise" \
  || ko "transparent_hugepage=madvise absent"
[[ $CMD == *mitigations=off* ]] && ko "mitigations=off present" \
  || ok "mitigations actives"
if [ "$(cat /sys/kernel/kexec_crash_loaded 2>/dev/null)" = 1 ]; then
  ok "kdump charge"; else ko "kdump non charge (kdump-config show)"; fi
USE=$(df --output=pcent /boot | tail -1 | tr -dc 0-9)
[ "$USE" -lt 70 ] && ok "/boot a $USE %" || ko "/boot a $USE % (>= 70)"
N=$(ls /boot/vmlinuz-* | wc -l)
[ "$N" -le 2 ] && ok "$N noyau(x) dans /boot" || ko "$N noyaux dans /boot"
if [ "$(timedatectl show -p NTPSynchronized --value)" = yes ]; then
  ok "horloge synchronisee"; else ko "horloge non synchronisee"; fi
exit $FAIL
```

### Extrait du rapport `base-noyau.md`

| Paramètre (famille) | Valeur | Justification | Effet de bord |
|---|---|---|---|
| `vm.swappiness` (mémoire) | 10 | garder le cache applicatif en RAM | swap tard, OOM plus brutal |
| `dirty_ratio` / `_background` (mémoire) | 10 / 5 | écritures lissées, pas de gel à `sync` | débit séquentiel un peu moindre |
| `somaxconn` (réseau) | 8192 | rafales de connexions absorbées | effectif au redémarrage des services |
| `nf_conntrack_max` (réseau) | 131072 | pas de `table full` sous charge | 32 Mo de RAM, module chargé |
| `kptr_restrict` / `dmesg_restrict` (sécurité) | 2 / 1 | pas de fuite d'adresses, `dmesg` root | `perf`/`bpftrace` exigent root |
| `kernel.panic` + kdump (robustesse) | 10 / 256M | reboot seul après capture | 256 Mo de RAM indisponibles |

**Pourquoi pas `mitigations=off`** : le gain (5 à 15 % sur des charges à
forte densité d'appels système) s'obtient en désactivant les protections
contre Spectre, Meltdown, MDS, Retbleed ; sur une VM, un autre locataire
du même hôte pourrait lire notre mémoire, et un processus non privilégié
lire celle du noyau. Un serveur d'API multi-utilisateurs ne l'accepte
jamais ; un nœud de calcul isolé, peut-être, après décision écrite. Mesurer
d'abord (`perf stat`, module 19) : sur ces VM, le goulot n'est pas là.

**Pourquoi `kernel.panic` en sysctl et pas `panic=` sur la ligne noyau** :
même effet, mais le sysctl est lisible, vérifiable et modifiable sans reboot
ni régénération de GRUB, et il appartient au même fichier que le reste de la
base — une seule source. `panic=` a sa place seulement pour couvrir un panic
**avant** que `systemd-sysctl` ait tourné, c'est-à-dire dans l'initramfs.

::: pourquoi
**Le prérequis caché de `nf_conntrack_max`.** Le cahier des charges exige
que le fichier s'applique intégralement au boot sans avertissement : c'est
le piège d'E9.13 et de BF9.2 en conditions réelles. Le fichier
`modules-load.d` est la seule solution ordonnée ; la vérification est
`journalctl -u systemd-sysctl -b` vide d'erreur après reboot, et c'est ce que
teste le script en comparant les valeurs **effectives**.

**Le script lit l'état, pas la configuration.** `sysctl -n` et
`/proc/sys` disent ce que le noyau applique ; le fichier dit ce qu'on
voulait. Un audit sur le fichier valide un fichier ignoré (BF9.2) ; un audit
sur `/proc/sys` détecte aussi la valeur remise par un autre acteur (Docker
qui force `ip_forward=1`, `tuned` qui écrase `swappiness`). Idem pour kdump :
`/sys/kernel/kexec_crash_loaded` prouve que le noyau de secours est chargé
en mémoire **maintenant**, alors que `systemctl is-enabled kdump-tools` ne
dit rien de l'état réel après un changement de noyau.

**`crashkernel=256M`.** kdump réserve cette mémoire au boot, indisponible
pour tout le reste (`free -m` montre 2 Go − 256). Trop peu : le noyau de
secours manque de mémoire et le dump échoue au pire moment. Les syntaxes à
plages (`2G-4G:320M`, début inclus, fin exclue) sont pratiques pour un
modèle déployé sur des tailles variées, mais piègent la VM de 2 Go dont le
noyau ne voit que 2 047 Mo. Rocky utilise `crashkernel=1G-4G:192M,...` par
défaut, avec le même écueil. Le test réel est indispensable : un kdump
jamais testé est un kdump qui ne marche pas, et `kexec_crash_loaded` à 0
après reboot est le premier signe d'une réservation manquée.

**`transparent_hugepage=madvise` sur la ligne noyau plutôt qu'en unité** :
la valeur est en place avant le premier processus, donc avant que
PostgreSQL ou Redis alloue sa mémoire. Une unité `oneshot` arrive après
`sysinit.target` — suffisant en général, mais un service ordonné tôt pourrait
la précéder. Le paramètre noyau n'a pas ce problème.
:::
