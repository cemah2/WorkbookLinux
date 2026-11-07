# Module 20 — Corrigé

## 20.3 Quiz — QCM

**Q20.1** — *`lscpu` de `lab-virt` : `Hypervisor vendor: KVM`, `Virtualization: VT-x`.*

**Réponses : a) et b)**

::: pourquoi
Deux lignes, deux informations indépendantes. `Hypervisor vendor: KVM` vient
du *leaf CPUID* `0x40000000` que l'hyperviseur expose à son invité : la
signature `KVMKVMKVM` dit « tu tournes sous KVM ». C'est le nœud Proxmox qui
la présente. `Virtualization: VT-x` vient du drapeau `vmx` de
`/proc/cpuinfo` : le processeur **vu par la VM** possède les extensions de
virtualisation. Ce drapeau n'apparaît que si le nœud a `kvm_intel nested=1`
**et** si la VM a un CPU en mode `host` (ou un modèle qui inclut `vmx`) : un
`x86-64-v2-AES` par défaut ne l'expose pas.

Les deux ensemble signifient : je suis une VM, et je peux moi-même charger
`kvm_intel` et créer `/dev/kvm`. C'est exactement l'état attendu de `lab-virt`.
TCG n'est pas en cause : on ne parle ici que des capacités du CPU vu, pas de
la manière dont `lab-virt` est exécutée. Et Xen exposerait
`Hypervisor vendor: Xen`.
:::

::: piege
Un `lscpu` sans ligne `Virtualization:` mais avec `Hypervisor vendor: KVM`
est le cas classique après un `qm set --cpu host` oublié : la VM tourne
parfaitement, mais `kvm-ok` répond `KVM acceleration can NOT be used` et
toute VM imbriquée partira en TCG. Vérifier d'abord `cat
/sys/module/kvm_intel/parameters/nested` sur le nœud, puis `qm config 9007 |
grep cpu`. Le changement de `--cpu` exige un arrêt/démarrage complet, pas
un `reboot` depuis l'invité.
:::

---

**Q20.2** — *`virsh list --all` vide en tant que `mathieu`, sans erreur.*

**Réponse : b)** `qemu:///session`.

::: pourquoi
libvirt a deux instances QEMU distinctes. `qemu:///system` est le démon
`libvirtd` lancé en root, avec les réseaux, les pools et les VM « système »,
joignable par la socket `/run/libvirt/libvirt-sock`. `qemu:///session` est
une instance **par utilisateur**, lancée à la demande dans ta session
(`libvirtd` en tant que `mathieu`, socket dans
`$XDG_RUNTIME_DIR/libvirt/`), sans privilège : pas de bridge, pas de réseau
`default`, ses VM sont dans `~/.config/libvirt/`.

Sans `-c` ni `LIBVIRT_DEFAULT_URI`, `virsh` demande à chaque pilote quelle
URI il propose ; le pilote QEMU répond `qemu:///system` si le processus est
root, `qemu:///session` sinon. `mathieu` voit donc un hyperviseur vide,
parfaitement fonctionnel, et aucune erreur n'est levée. `virsh uri` le
confirme.

Le correctif : `export LIBVIRT_DEFAULT_URI=qemu:///system` dans `~/.bashrc`
(ou `uri_default = "qemu:///system"` dans `~/.config/libvirt/libvirt.conf`),
**et** l'appartenance au groupe `libvirt` pour avoir le droit d'écrire sur
la socket système.
:::

::: piege
c) est fausse : le groupe `kvm` donne accès à `/dev/kvm`, ce qui ne concerne
que le mode session (QEMU lancé sous ton compte). En mode système, c'est
`libvirt-qemu` qui ouvre `/dev/kvm`. Un `virsh list` **avec** erreur
(`Failed to connect socket ... Permission denied`) est l'autre panne : là,
c'est le groupe `libvirt` qui manque — ou la session shell qui n'a pas été
rouverte après `adduser`.
:::

---

**Q20.3** — *`<domain type='qemu'>` au lieu de `kvm`.*

**Réponses : b) et c)**

::: pourquoi
L'attribut `type` du domaine choisit l'**accélérateur** que libvirt passe à
QEMU : `type='kvm'` → `-accel kvm` ; `type='qemu'` → `-accel tcg`. TCG
(*Tiny Code Generator*) traduit chaque bloc d'instructions invité en code
hôte, à la volée, puis l'exécute : c'est de l'émulation complète, portable
(on peut faire tourner un ARM sur x86), mais dix à cinquante fois plus
lente qu'une exécution native sous VT-x. Un noyau Ubuntu qui boote en 8 s
sous KVM prend plusieurs minutes, et le processus QEMU consomme 100 % d'un
cœur en permanence puisqu'il « calcule » chaque instruction.

Le multi-vCPU n'est pas interdit sous TCG (MTTCG existe), et les deux modes
n'ont rien d'alias. Le diagnostic tient en une commande :
`ps -o args -C qemu-system-x86_64 | grep -o -- '-accel [a-z]*'`.
:::

::: piege
`virt-install` sans `--virt-type` choisit `kvm` si `/dev/kvm` existe, sinon
il **bascule silencieusement** en `qemu` avec un simple avertissement
`KVM acceleration not available, using 'qemu'`. Sur un hôte où la
virtualisation imbriquée a sauté après un redémarrage du nœud, on obtient
des VM qui « marchent » mais rament. `virsh domcapabilities` sans
`--virttype kvm` te dit ce que libvirt considère disponible.
:::

---

**Q20.4** — *`disk size: 312 MiB`, `backing file: ...ubuntu-24.04-base.qcow2`.*

**Réponse : b)**

::: pourquoi
Un qcow2 avec *backing file* est un **overlay** : il ne stocke que les
clusters (64 Ko) qui ont été écrits depuis sa création. Toute lecture d'un
cluster absent est redirigée vers la base. La VM voit 20 Go (taille
virtuelle de l'overlay), mais le fichier pèse 312 Mo : le reste est lu dans
la base, qui doit rester disponible au chemin enregistré dans l'en-tête de
l'overlay (chemin absolu ou relatif au répertoire de l'overlay).

La base doit être **immuable** : si on y écrit — par exemple en démarrant
une VM directement dessus — les clusters non couverts par les overlays
changent sous leurs pieds et tous les invités qui en dépendent voient un
disque incohérent. D'où la pratique `chmod 0444` et un nom explicite.

`disk size` est l'espace réellement alloué sur l'hôte (`st_blocks`), jamais
la taille vue par l'invité. Aucune copie n'a lieu au démarrage ; pour rendre
un overlay autonome, il faut `qemu-img convert` (aplatit dans un nouveau
fichier) ou `qemu-img rebase -b ''` / `virsh blockpull` (ramène la base dans
l'overlay).
:::

---

**Q20.5** — *`virtio-blk` ou `virtio-scsi`.*

**Réponses : a) et b)**

::: pourquoi
Les deux sont paravirtualisés : aucun n'émule un contrôleur réel. La
différence est le **protocole** transporté dans les virtqueues.

`virtio-blk` transporte des requêtes bloc brutes : simple, court chemin,
excellent en latence, mais chaque disque est un périphérique PCI (limite
pratique de quelques dizaines), et longtemps sans TRIM (supporté depuis
QEMU 4.0). Les disques apparaissent en `/dev/vdX`.

`virtio-scsi` transporte des **commandes SCSI** vers un contrôleur unique
qui peut porter des milliers de LUN : `/dev/sdX`, `UNMAP` (TRIM) natif,
hotplug fiable, *pass-through* d'un vrai périphérique SCSI, et une file par
vCPU avec `iothread`. C'est pour ça que Proxmox propose
`virtio-scsi-single` par défaut : un contrôleur par disque + un iothread.
Le surcoût est marginal sur du stockage rapide.
:::

::: piege
c) confond paravirtualisation et émulation : ce qui est lent, c'est l'AHCI
ou l'IDE émulé, pas virtio-scsi. d) est fausse depuis des années : le défaut
Proxmox est `virtio-scsi-single`. Dans la VM, ne cherche pas `vda` si le
bus est `scsi` : c'est `sda`, et `lsblk -o NAME,TRAN` affiche `virtio`.
:::

---

**Q20.6** — *`cache='none'`.*

**Réponse : b)**

::: pourquoi
Le mode de cache décrit ce que QEMU fait entre l'invité et le fichier image,
**côté hôte**. L'invité garde toujours son propre cache de pages.

* `writeback` (défaut QEMU sans attribut) : les écritures vont dans le cache
  de pages de l'hôte, QEMU acquitte avant que le disque physique ait écrit,
  et honore les `flush` de l'invité (`fsync`) : sûr avec un invité moderne,
  mais la RAM de l'hôte se remplit de cache de VM, et une migration à chaud
  vers un autre hôte devient dangereuse (le cache n'est pas sur l'autre
  hôte).
* `none` : l'image est ouverte avec `O_DIRECT` : pas de cache hôte, les
  données traversent directement vers le stockage, le cache reste dans
  l'invité (une seule copie en RAM au lieu de deux). Sûr, prévisible,
  compatible migration et stockage partagé : c'est le choix de Proxmox
  (« Default (No cache) ») et de la plupart des recommandations.
* `writethrough` : cache hôte en lecture, écriture synchrone : sûr, lent.
* `unsafe` : ignore les `flush` : parfait pour une installation jetable,
  catastrophique pour des données.
:::

::: piege
« Plus rapide dans tous les cas » est faux : `writeback` gagne sur des
rafales d'écritures courtes grâce au cache hôte. `none` gagne en stabilité,
en RAM, et sur les gros volumes séquentiels. Et les snapshots ne dépendent
pas du cache. Ce qu'il faut retenir : `cache='none'` + `io='native'` pour
un serveur, et jamais `unsafe` sur une base de données.
:::

---

**Q20.7** — *Migration à chaud entre CPU de générations différentes.*

**Réponse : b)**

::: pourquoi
L'invité découvre son CPU par `CPUID` au démarrage et compile parfois du
code pour lui (AVX-512, AES-NI…). En migration à chaud, la RAM est copiée
telle quelle : si le nouvel hôte n'a pas une instruction que l'invité
utilise, c'est un `SIGILL` dans l'invité au premier usage, sans avertissement.

`host-passthrough` expose le CPU exact : performance maximale, imbrication
possible, mais migration uniquement vers un hôte **strictement identique**.
`host-model` demande à libvirt de trouver le modèle nommé le plus proche
(`Skylake-Client-IBRS`, `EPYC-Rome`…) plus les drapeaux supplémentaires :
migrable vers tout hôte qui supporte ce modèle. `custom` avec un modèle nommé
commun (`Westmere`, `Skylake-Client`…; côté Proxmox, `x86-64-v2-AES`, son défaut depuis la version 8) est le
dénominateur le plus sûr dans un cluster hétérogène, au prix de quelques
instructions. `migratable='on'` sur `host-passthrough` ne fait que retirer
les drapeaux connus comme non migrables ; il ne rend pas deux CPU
différents compatibles.
:::

---

**Q20.8** — *`virsh shutdown` sans effet, `virsh destroy` fonctionne.*

**Réponse : b)**

::: pourquoi
`virsh shutdown` par défaut (`--mode acpi`) demande à QEMU d'émettre un
événement **bouton d'alimentation ACPI**. C'est une **demande** : l'invité
doit avoir un composant qui l'écoute — `systemd-logind` (`HandlePowerKey=`)
sur tout Ubuntu/Rocky moderne, `acpid` sur les systèmes anciens — et un
noyau démarré. Un invité arrêté au menu GRUB, un noyau en panique, un
Windows avec une session verrouillée qui affiche « voulez-vous vraiment… »,
ou un conteneur minimal sans logind ignorent l'événement : la commande
`virsh` rend la main immédiatement (elle a bien envoyé l'événement) et rien
ne se passe.

`virsh destroy` est un `SIGKILL` du processus QEMU : ça marche toujours, au
prix d'un arrêt brutal (journal de FS à rejouer). L'alternative propre est
`virsh shutdown --mode agent`, qui passe par l'agent invité (`guest-shutdown`)
et ne dépend pas d'ACPI, ou `--mode acpi,agent` pour essayer les deux.
:::

::: piege
d) inverse la logique : l'agent est une option supplémentaire, pas une
condition. Et libvirt sait attendre pour toi : `virsh shutdown vm &&
virsh event vm --event lifecycle --timeout 60` ou, dans un script, une
boucle sur `virsh domstate`. Proxmox fait exactement la même chose avec
`qm shutdown --timeout 60`, puis `qm stop` si ça n'a pas suffi.
:::

---

**Q20.9** — *Juste après `snapshot-create-as --disk-only --atomic`.*

**Réponse : b)**

::: pourquoi
Un snapshot **externe** ne copie rien. libvirt demande à QEMU (commandes
QMP `blockdev-add` + `blockdev-snapshot`, groupées dans une `transaction`) de créer un **nouveau fichier qcow2** dont le backing
file est le disque actuel, puis de basculer les écritures de l'invité dans
ce nouveau fichier. L'ancien fichier `vm-01.qcow2` n'est plus jamais écrit :
il est figé à l'instant du snapshot, ce qui est précisément ce qui le rend
copiable pendant que la VM tourne.

Le nom par défaut est `<fichier>.<nom du snapshot>`, ici `vm-01.s1`,
extension trompeuse mais format qcow2. `--disk-only` exclut la RAM (sinon un
snapshot externe complet écrit aussi un fichier d'état mémoire avec
`--memspec`). La VM n'est en pause que le temps de la bascule, quelques
millisecondes. `--atomic` garantit que soit tous les disques ont basculé,
soit aucun.
:::

---

**Q20.10** — *`blockcommit vm-01 vda --active --pivot`.*

**Réponse : a)**

::: pourquoi
`blockcommit` lance un *block job* QEMU qui copie les clusters de la couche
haute vers la couche du dessous (ici `vm-01.s1` → `vm-01.qcow2`) pendant que
la VM continue d'écrire. Quand la couche à fusionner est la couche **active**
(celle où l'invité écrit), le job ne peut pas se terminer seul : il atteint
un état « prêt » puis attend qu'on lui dise de **pivoter**, c'est-à-dire de
rediriger les écritures de l'invité vers `vm-01.qcow2` et d'abandonner
`vm-01.s1`. C'est le rôle de `--pivot` (sinon `virsh blockjob vm-01 vda
--pivot` à la main). `--verbose` affiche la progression.

Après le pivot, `virsh domblklist` montre de nouveau `vm-01.qcow2`, et
`vm-01.s1` n'est plus référencé : libvirt ne le supprime pas — c'est à toi
de le faire. b) décrit `blockpull` (la base remonte dans l'overlay). Rien ne
redémarre.
:::

::: piege
Sans `--active`, `blockcommit` refuse de fusionner la couche active
(`commit of 'vda' active layer requires active flag`) ; on l'utilise alors avec `--top`/`--base`
pour fusionner des couches **intermédiaires** d'une longue chaîne. Et si tu
lances `blockcommit` sans `--pivot` ni `--wait`, le job reste en état
`ready` indéfiniment : `virsh blockjob vm-01 vda --info` le montre, et un
`virsh destroy` à ce moment-là laisse la chaîne dans l'état d'avant.
:::

---

**Q20.11** — *`setvcpus 4 --live` : `4 > 1`.*

**Réponse : b)**

::: pourquoi
Le hot-plug de vCPU passe par des sockets CPU virtuels que QEMU a déclarés
au démarrage : `-smp 1,maxcpus=4` crée quatre emplacements dont un occupé.
libvirt les décrit avec `<vcpu current='1'>4</vcpu>` : maximum 4, actuel 1.
Sans `current`, maximum = actuel et QEMU n'a aucun emplacement libre : la
demande est refusée.

Le maximum ne se change qu'à froid : `virsh setvcpus vm-01 4 --maximum
--config` (ou `virsh edit`), arrêt/démarrage, puis `virsh setvcpus vm-01 3
--live --config`. Dans l'invité, le nouveau CPU arrive en ligne
automatiquement (`udev` + `/sys/devices/system/cpu/cpuN/online`), visible
avec `nproc`. Le retrait à chaud fonctionne aussi mais dépend de l'invité.
Le mode CPU (`host-passthrough`) n'a rien à voir ; `--config` seul ne
changerait que la définition persistante, pas la VM en cours.
:::

---

**Q20.12** — *DHCP sur `default`, rien sur `br0`.*

**Réponse : b)**

::: pourquoi
Le réseau `default` n'est pas qu'un bridge : libvirt lance un `dnsmasq`
dédié (`dnsmasq --conf-file=/var/lib/libvirt/dnsmasq/default.conf`) qui
sert DHCP et DNS sur `virbr0`, plus les règles NAT. C'est ce `dnsmasq` qui
répond au `DHCPDISCOVER` de la VM.

Sur `br0`, la trame DHCP de la VM part sur le LAN de lab `10.10.10.0/24`,
comme si la VM était branchée sur `vmbr1` du nœud Proxmox. Or le `dnsmasq`
du nœud est configuré `no-dhcp-interface=vmbr1` : il ne sert que le DNS.
Personne ne répond, la VM reste sans adresse. La solution est celle du
reste du lab : une adresse **statique**, portée par le `network-config` v2
du seed cloud-init (ou un DHCP que tu ajoutes volontairement sur le LAN).
:::

::: piege
Un réflexe erroné est d'ajouter `<ip>`/`<dhcp>` au réseau libvirt
`lan` en mode bridge : libvirt refuse (`ip` n'est pas compatible avec
`forward mode='bridge'`), parce qu'il ne possède pas le bridge et ne
lancera pas de `dnsmasq` dessus. Autre piège : `virsh domifaddr` ne sait
lire que les baux de **son** `dnsmasq` (`--source lease`) ; pour une VM
bridgée, c'est `--source agent` ou `--source arp`.
:::

---

**Q20.13** — *`Permission denied` sur `/root/import/import-1.qcow2`.*

**Réponses : a) et b)**

::: pourquoi
`libvirtd` tourne en root, mais il ne lance pas QEMU en root. Sur Ubuntu,
`/etc/libvirt/qemu.conf` fixe `user = "libvirt-qemu"` et `group = "kvm"` ;
sur Rocky, `qemu:qemu`. Le processus `qemu-system-x86_64` de chaque VM
s'exécute sous ce compte, confiné en plus par AppArmor ou SELinux. C'est
**lui** qui fait `open()` sur l'image.

Avec `dynamic_ownership = 1`, libvirt fait un `chown libvirt-qemu:kvm` sur
le fichier au démarrage (et le rend au propriétaire à l'arrêt). Mais il ne
touche pas aux répertoires traversés : `/root` est `0700 root:root`, et
sans le bit `x` pour les autres, le `open()` échoue à la traversée avant
même d'atteindre le fichier. `namei -l /root/import/import-1.qcow2` montre
la chaîne, et `sudo -u libvirt-qemu test -r /root/import/import-1.qcow2 ;
echo $?` reproduit l'échec.

Le correctif attendu : mettre l'image là où elle doit vivre — un pool
libvirt (`/var/lib/libvirt/images`, `0711 root:root`, traversable) — et
corriger le `<source file>` du XML. AppArmor n'est pas la cause ici : le
profil généré autoriserait ce chemin, c'est le DAC qui bloque.
:::

---

**Q20.14** — *`domifaddr` vide pour une VM sur `br0`.*

**Réponse : a)**

::: pourquoi
`virsh domifaddr` a trois sources. `--source lease` (défaut) lit les baux du
`dnsmasq` de libvirt (`/var/lib/libvirt/dnsmasq/<bridge>.status`, ici `virbr0.status`) : il ne
connaît que les réseaux que libvirt sert en DHCP, donc rien pour un bridge
externe ou une adresse statique. `--source agent` interroge
`qemu-guest-agent` (`guest-network-get-interfaces`) : exact, toutes les
interfaces, y compris `lo`, mais l'agent doit tourner. `--source arp` lit
la table ARP de l'hôte : ne voit que les VM qui ont déjà parlé à l'hôte, et
pas d'IPv6.

`net-dhcp-leases` ne s'applique qu'à un réseau libvirt, `br0` n'en est pas
un. `domiflist` liste les interfaces (type, source, modèle, MAC) sans
adresse.
:::

---

**Q20.15** — *`qm snapshot` sur `local-lvm`.*

**Réponse : b)**

::: pourquoi
Proxmox n'utilise pas libvirt et choisit le mécanisme de snapshot selon le
**type de stockage** du disque. Sur `local-lvm` (LVM-thin), un `qm snapshot`
crée un **snapshot thin** du volume logique (`lvcreate -s`), instantané et
copie-sur-écriture au niveau du pool thin ; l'état RAM, si demandé, va dans
un volume `vm-<id>-state-<nom>`. La configuration est dupliquée dans une
section `[nom]` de `/etc/pve/qemu-server/<vmid>.conf` : c'est ce qui permet
de revenir à la configuration matérielle d'alors.

Sur un stockage `dir` avec des disques qcow2, `qm snapshot` fait un snapshot
**interne** qcow2 (`savevm`) ; sur ZFS, un `zfs snapshot` ; sur Ceph RBD, un
snapshot RBD ; sur un stockage `dir` en raw, le snapshot est refusé. Un
overlay externe comme celui de `virsh --disk-only` n'est jamais utilisé par
Proxmox pour les snapshots (mais sa sauvegarde `vzdump` en mode `snapshot`
s'appuie sur un *backup block job* QEMU avec bitmap de blocs modifiés, ce
qui est un autre mécanisme encore).
:::

---

**Q20.16** — *Frontière KVM / QEMU.*

**Réponse : b)**

::: pourquoi
KVM est un module du noyau Linux qui expose `/dev/kvm` et une API
`ioctl()`. Il crée une VM (`KVM_CREATE_VM`), des vCPU, mappe de la mémoire,
puis entre en mode invité (`KVM_RUN`) : le CPU exécute les instructions de
l'invité **nativement**, en mode non-root VT-x, jusqu'à ce qu'un événement
nécessite l'hôte (accès à un registre de périphérique, instruction
privilégiée, interruption) : c'est une **sortie de VM** (*VM exit*), et
`KVM_RUN` rend la main.

QEMU est le processus userland qui a fait ces `ioctl` : à chaque sortie, il
regarde pourquoi (« l'invité a écrit sur le port I/O 0x1F0 ») et joue le rôle
du matériel correspondant (disque, carte réseau, chipset, BIOS/UEFI via
OVMF), puis rappelle `KVM_RUN`. Sans KVM, QEMU fait tout, y compris le CPU
(TCG). Sans QEMU, KVM ne sait rien émuler. Firecracker, par exemple,
remplace QEMU par un device model minimal au-dessus de la même API KVM.
:::

---

**Q20.17** — *`st` à 35 % dans l'invité.*

**Réponse : b)**

::: pourquoi
Le *steal time* est rapporté par l'hyperviseur à l'invité (via la
*paravirt steal-time* de KVM, `MSR_KVM_STEAL_TIME`) : c'est le temps pendant
lequel un vCPU était prêt à s'exécuter mais l'ordonnanceur de l'**hôte** a
donné le CPU physique à quelqu'un d'autre (une autre VM, un processus hôte,
un thread QEMU d'E/S). Vu de l'invité, ses processus « attendent » sans
raison : latence, charge moyenne qui grimpe, CPU « occupé » à ne rien
faire.

Rien dans l'invité ne peut le corriger : c'est l'hôte qui est suralloué.
Côté hôte : `virt-top` ou `virsh cpu-stats` pour trouver qui consomme,
réduire le nombre total de vCPU face aux cœurs physiques, épingler les VM
sensibles (`vcpupin`), donner des `<shares>` cgroup, ou déplacer une VM.
Sur `lab-virt` (4 vCPU eux-mêmes partagés avec le reste du nœud Proxmox), le
steal apparaît dès que le nœud est chargé : c'est du steal **à deux étages**.
:::

---

**Q20.18** — *Migration à chaud sans stockage partagé.*

**Réponse : b)**

::: pourquoi
Une migration à chaud transfère la RAM et l'état des périphériques ; le
disque, lui, est normalement **le même** vu des deux hôtes (NFS, Ceph,
iSCSI). Sans stockage partagé, libvirt sait aussi copier le disque pendant
la migration : `--copy-storage-all` (copie complète) ou `--copy-storage-inc`
(seulement ce qui manque par rapport à un backing file déjà présent sur la
cible). QEMU ouvre un *block mirror* : les clusters sont copiés en tâche de
fond, les écritures de l'invité sont dupliquées, puis la RAM suit.

Condition : le fichier de destination doit **exister** sur la cible, au
chemin indiqué dans le XML, à la bonne taille (`qemu-img create -f qcow2
... 20G`) — libvirt ne le pré-crée lui-même que si ce chemin appartient à un pool actif de la cible. `--offline` n'est pas une
migration à chaud, et copier un qcow2 en cours d'écriture donne une image
incohérente.
:::

---

## 20.4 Quiz — questions ouvertes

**QO20.1** — *Le trajet d'une écriture disque de `vm-01` jusqu'au SSD du nœud.*

::: pourquoi
1. **Application dans `vm-01`** : `write()` → cache de pages du noyau
   invité. Rien ne sort tant qu'un `fsync` ou le *writeback* de l'invité ne
   décide d'écrire.
2. **Pilote `virtio_blk` de l'invité** : il place un descripteur (adresse
   des données, secteur, longueur) dans la *virtqueue* partagée avec QEMU,
   puis « sonne » (`notify`) : une écriture sur un registre PCI → **sortie
   de VM**, KVM rend la main à QEMU.
3. **QEMU (`lab-virt`, userland)** lit la virtqueue et exécute la requête
   sur le fichier `vm-01.qcow2` : traduction cluster qcow2 (allocation si
   premier accès), puis `pwrite()`. Avec `cache='none'`, le fichier est
   ouvert en `O_DIRECT` : l'écriture contourne le cache de pages de
   `lab-virt` ; avec `writeback`, elle y reste jusqu'au prochain `flush`.
   `discard='unmap'` intervient ici sur une autre requête : un `TRIM` de
   l'invité devient un `fallocate(PUNCH_HOLE)` sur le qcow2.
4. **Noyau de `lab-virt`** : système de fichiers ext4 de `/var/lib/libvirt/
   images` → couche bloc → pilote `virtio_scsi` de `lab-virt` (son disque
   est un `scsi0` Proxmox).
5. **QEMU du nœud Proxmox** : même mécanisme un étage plus bas, écriture
   sur le volume LVM-thin `vm-9007-disk-0`, avec le cache configuré par
   Proxmox (`none`).
6. **Noyau du nœud** → pilote NVMe/SATA → SSD. L'acquittement remonte toute
   la pile ; un `fsync` de l'invité n'est « vrai » que si chaque couche
   honore les `flush` (d'où l'interdiction de `cache='unsafe'`).

Chaque étage ajoute une sortie de VM et une copie : c'est le coût de la
virtualisation imbriquée, et la raison pour laquelle `lab-virt` n'est pas
un banc de mesure de performance.
:::

**QO20.2** — *Entretien : virtio, e1000 vs virtio-net.*

::: pourquoi
Une `e1000` émulée est une **imitation exacte** d'une carte Intel réelle :
le pilote invité (celui de Linux pour la vraie carte) programme des
registres, des anneaux de descripteurs au format Intel, des interruptions.
Chaque écriture de registre est une instruction `mov` vers une adresse MMIO
que le CPU ne peut pas exécuter en mode invité : **sortie de VM**, retour à
QEMU, qui met à jour son modèle logiciel de la carte, puis retour. Envoyer
un paquet coûte plusieurs sorties ; en recevoir aussi. À 100 000 paquets/s,
c'est le CPU hôte qui s'effondre.

**virtio** part du principe inverse : l'invité *sait* qu'il est virtualisé.
Le contrat est une interface standardisée (spécification OASIS) : des
**virtqueues** en mémoire partagée où l'invité empile des descripteurs, un
seul `notify` pour tout un lot, et des mécanismes de suppression de
notifications quand l'autre côté est déjà en train de traiter. Le pilote
invité est minuscule, le device model QEMU aussi ; et pour le réseau,
`vhost-net` déporte même le traitement dans le noyau hôte, sans passer par
QEMU. Résultat : dix fois moins de sorties de VM, un débit proche du natif.

Les cinq du quotidien : `virtio-blk` ou `virtio-scsi` (disques),
`virtio-net` (réseau, multiqueue), `virtio-balloon` (rendre de la RAM à
l'hôte à chaud, statistiques mémoire), `virtio-rng` (entropie de l'hôte vers
`/dev/hwrng`), et le canal `virtio-serial` qui porte `qemu-guest-agent`.
Bonus : `virtiofs` pour partager un répertoire de l'hôte avec des
performances de FS local.
:::

**QO20.3** — *raw vs qcow2, thin provisioning, discard, et le choix Proxmox.*

::: pourquoi
**raw** : le fichier est une image octet pour octet du disque. Zéro
métadonnée, performance maximale, mais aucune fonction : pas de snapshot
interne, pas de backing file, pas de compression. L'allocation dépend du
système de fichiers hôte (un raw créé par `qemu-img` est *sparse* : `ls -l`
dit 20 Go, `du` dit 0).

**qcow2** : une table de correspondance (L1/L2) entre clusters logiques et
clusters physiques. On n'alloue que ce qui est écrit (*thin*), on peut
empiler des overlays, garder des snapshots internes, compresser, chiffrer.
Coût : une indirection par accès (−3 à −5 %), et de la fragmentation.

Le piège du thin : chaque VM croit avoir 20 Go, l'hôte en a 40 pour dix VM.
Tant que les VM n'écrivent pas, tout va bien ; le jour où trois d'entre
elles font une mise à jour et un `dd` de test, le qcow2 grossit — et un
qcow2 **ne rétrécit jamais seul** : un fichier supprimé dans l'invité libère
des blocs pour l'invité, pas pour l'hôte. Quand le FS hôte est plein, QEMU
reçoit `ENOSPC`, libvirt met la VM en **pause** (`virsh domstate --reason`
→ `paused (ioerror)`), et toutes les VM du même FS suivent.

`discard='unmap'` change ça : un `fstrim` (ou `mount -o discard`) dans
l'invité envoie des `TRIM`/`UNMAP`, QEMU les traduit en trous dans le qcow2
(`fallocate PUNCH_HOLE`), et `du` redescend. Sans `discard`, `fstrim` répond
`the discard operation is not supported`.

Proxmox préfère **raw sur LVM-thin** (ou ZFS) : le *thin provisioning*, les
snapshots et le discard sont assurés par la couche stockage, pas par le
format, donc la VM lit/écrit un volume bloc sans indirection qcow2, et les
snapshots sont des snapshots thin. Le qcow2 n'y reste que sur les stockages
de type répertoire.
:::

**QO20.4** — *Sauvegarde à chaud par snapshot externe, étape par étape.*

::: pourquoi
État initial : la VM écrit dans `vm-01.qcow2` (lui-même overlay de la base).

1. `virsh snapshot-create-as vm-01 sauv --disk-only --atomic --quiesce
   --no-metadata --diskspec vda,snapshot=external,file=.../vm-01.sauv`.
   * `--quiesce` : libvirt demande d'abord à l'agent `guest-fsfreeze-freeze`.
     Le noyau invité termine les écritures en cours, vide ses caches, et
     bloque toute nouvelle écriture (comme `fsfreeze -f`). Sans ça, l'image
     est *crash-consistent* : cohérente comme après une coupure de courant,
     le journal ext4 s'en sort, une base de données pas toujours.
   * `--atomic` : si plusieurs disques, un seul `transaction` QMP ; tout ou
     rien.
   * QEMU crée `vm-01.sauv` (backing = `vm-01.qcow2`) et bascule les
     écritures. Puis `guest-fsfreeze-thaw`. Durée du gel : quelques dizaines
     de millisecondes.
   * `--no-metadata` : libvirt ne garde **pas** de fiche de snapshot
     (`snapshot-list` reste vide) ; c'est volontaire, parce qu'on va détruire
     l'overlay nous-mêmes et qu'une fiche orpheline gênerait.
2. `vm-01.qcow2` est figé : `qemu-img convert -O qcow2 vm-01.qcow2
   sauvegarde.qcow2` produit un fichier **autoportant** (la chaîne base +
   overlay est lue et aplatie) qu'on peut copier n'importe où. On y joint
   `virsh dumpxml --inactive`.
3. `virsh blockcommit vm-01 vda --active --pivot` : QEMU recopie dans
   `vm-01.qcow2` tout ce qui a été écrit dans `vm-01.sauv` depuis l'étape 1,
   puis pivote : la VM écrit de nouveau dans `vm-01.qcow2`.
4. `rm vm-01.sauv`. État final identique à l'état initial.

Si l'on oublie l'étape 3 : la VM continue d'écrire dans `vm-01.sauv`
pendant des mois. Ce fichier grossit (toutes les écritures y vont),
`snapshot-list` ne montre rien (`--no-metadata`), la chaîne s'allonge à
chaque sauvegarde (`.sauv` sur `.sauv`), les lectures traversent N couches,
et le jour où quelqu'un « nettoie » le fichier bizarre, la VM perd des mois
de données. C'est BF20.5.
:::

**QO20.5** — *Entretien : la migration à chaud.*

::: pourquoi
Le principe est le **pre-copy** :

1. Le domaine est défini sur l'hôte cible (même XML, disque accessible au
   même chemin), QEMU y démarre en attente (`-incoming`).
2. Toute la RAM est copiée une première fois pendant que la VM tourne sur
   la source. KVM active le suivi des **pages sales** (*dirty page
   tracking*) : chaque page modifiée par l'invité pendant la copie est
   marquée.
3. Itérations : on recopie les pages sales, qui se salissent à nouveau,
   etc. Chaque passe est plus courte, tant que l'invité salit moins vite
   que le réseau ne transfère.
4. Quand le reste à copier est assez petit pour tenir dans le *downtime*
   autorisé (`virsh migrate-setmaxdowntime`, 300 ms par défaut), la VM est
   mise en **pause** sur la source, les dernières pages et l'état des
   périphériques (registres, horloges, file réseau) partent, et la VM
   reprend sur la cible. Un ARP gratuit annonce le MAC sur le nouveau port
   de bridge. Le downtime réel est de l'ordre de 50 à 500 ms.

Si l'invité salit plus vite que le réseau (base de données très active), la
migration ne converge pas : `--auto-converge` ralentit les vCPU,
`--postcopy` bascule tout de suite et rapatrie les pages à la demande (une
coupure réseau pendant le post-copy tue la VM).

Prérequis : CPU compatible (`host-model` ou modèle commun), même chipset
QEMU (`pc-q35-8.2`), stockage partagé ou `--copy-storage-all`, même bridge
disponible côté cible, `libvirtd` joignable (`qemu+ssh://` ou TLS), pas de
périphérique non migrable (passthrough PCI); un disque **partagé** en `cache='writeback'` fait refuser la migration (`--unsafe` pour forcer). Ports 49152-49215 ouverts pour le flux.

Proxmox : `qm migrate 9002 pve2 --online [--with-local-disks]` fait tout ça
(tunnel SSH ou réseau de migration dédié, copie des disques locaux par
*block mirror*, ré-attachement au même `vmbrX` sur la cible, et la
configuration bouge dans `/etc/pve` répliqué par corosync). Le HA de
Proxmox le déclenche automatiquement.
:::

**QO20.6** — *Méthode quand `virsh start` échoue ou que la VM ne répond pas.*

::: pourquoi
1. **Lire l'erreur de `virsh start` en entier.** Elle est souvent
   suffisante : `Cannot access backing file` (chaîne cassée),
   `Cannot get interface MTU on 'br0'` (bridge absent), `Permission denied`
   (DAC/sVirt), `unsupported configuration` (XML incohérent), `KVM is not
   supported` (`/dev/kvm`).
2. **Le journal QEMU** : `sudo tail -30 /var/log/libvirt/qemu/<vm>.log`. On
   y trouve la ligne de commande QEMU complète et son dernier message avant
   `shutting down`. Un `qemu-system-x86_64: -blockdev ...: Could not open`
   désigne le fichier.
3. **Le journal libvirt** : `journalctl -u libvirtd -n 50` (Rocky :
   `virtqemud`) pour les erreurs internes, AppArmor (`apparmor="DENIED"
   ... profile="libvirt-<uuid>"` dans `journalctl -k`), SELinux
   (`ausearch -m avc -ts recent`).
4. **La définition** : `virsh dumpxml vm --inactive` puis `virt-xml vm
   --edit --print-diff`… ou simplement `xmllint --noout`. Vérifier
   `type='kvm'`, chaque `<source file>` (`ls -l`, `namei -l`), chaque
   `<source bridge|network>` (`ip link`, `virsh net-list`).
5. **La chaîne disque** : `sudo qemu-img info -U --backing-chain <disque>`.
6. **Les prérequis hôte** : `ls -l /dev/kvm`, `kvm-ok`, `virsh
   domcapabilities --virttype kvm`, espace disque (`df` du pool : une VM
   en `paused (ioerror)` est un FS plein).

Si la VM **démarre mais ne répond pas** :

7. `virsh domstate --reason vm` (`paused`, `crashed`, `running`).
8. `virsh console vm` : si rien ne s'affiche, soit pas de `<serial>`, soit
   pas de `console=ttyS0` dans la ligne de commande du noyau invité ; en
   secours, `virsh screenshot vm /tmp/s.ppm` ou un `<graphics type='vnc'>`.
9. Réseau : `virsh domiflist`, `virsh domifaddr --source agent|arp`,
   `sudo tcpdump -ni virbr0 port 67` pour voir si la VM demande une
   adresse, `virsh net-dhcp-leases`, `iptables -L LIBVIRT_FWO -nv`.
10. Agent : `virsh qemu-agent-command vm '{"execute":"guest-ping"}'` ; si
    `Guest agent is not responding`, vérifier le `<channel>` dans le XML et
    `systemctl status qemu-guest-agent` dans l'invité.
11. Performance : `ps -o args -C qemu-system-x86_64 | grep -o -- '-accel
    [a-z]*'`, `virsh cpu-stats`, `top` dans l'invité (colonne `st`).
:::

**QO20.7** — *Les quatre modes réseau et leurs équivalents Proxmox.*

::: pourquoi
* **NAT** (`<forward mode='nat'/>`) : libvirt crée un bridge `virbrN` sans
  port physique, lui donne une IP, lance un `dnsmasq` (DHCP + DNS) et pose
  des règles `iptables` : `MASQUERADE` en sortie (`LIBVIRT_PRT`), `ACCEPT`
  des retours établis, `REJECT` du reste (`LIBVIRT_FWI/FWO`). Les VM sortent
  avec l'IP de l'hôte ; personne sur le LAN ne peut les joindre sans DNAT.
  Usage : poste de développeur, VM de test qui doivent seulement sortir.
  Proxmox : `vmbr1` du chapitre 0 + le script `lab-nat.sh` : exactement la
  même construction, à la main.
* **Bridge** (`<forward mode='bridge'/><bridge name='br0'/>` ou
  `bridge=br0`) : l'hôte a déjà un bridge dont un port est la carte
  physique ; libvirt ne fait qu'y brancher le `tap` de la VM. La VM est un
  hôte du LAN à part entière, avec sa propre adresse, servie par le DHCP du
  LAN s'il existe. Aucun netfilter, aucun `dnsmasq`. Usage : serveurs.
  Proxmox : `vmbr0` (bridge sur la carte physique).
* **Isolé** (pas de `<forward>`) : bridge + `dnsmasq` optionnel, mais des
  règles `REJECT` interdisent tout ce qui n'est pas VM ↔ VM sur ce bridge
  (l'hôte reste joignable par l'IP du bridge). Usage : réseau de backend
  entre un frontal et sa base, lab de sécurité. Proxmox : un `vmbrX` avec
  `bridge-ports none` et sans NAT.
* **macvtap** (`<interface type='direct'>`) : pas de bridge ; une interface
  virtuelle macvlan sur la carte physique, chaque VM avec son MAC sur le
  LAN. Plus léger, mais **l'hôte ne peut pas parler à ses propres VM** (le
  trafic ne remonte pas dans la pile de l'hôte en mode `bridge` de
  macvtap), et le Wi-Fi ne le supporte pas. Usage : hôtes sans besoin de
  dialogue hôte ↔ VM, performance. Proxmox n'en propose pas.

Dans tous les cas le pare-feu de Proxmox (`Datacenter/Node/VM →
Firewall`) s'insère au niveau du `tap` de chaque VM, via des chaînes
`iptables`/`nftables` générées par `pve-firewall` : c'est le même outil que
libvirt utilise pour ses `LIBVIRT_*`.
:::

**QO20.8** — *Entretien : Proxmox, OpenStack, vSphere, Firecracker ; VM ou conteneur.*

::: pourquoi
1. **vSphere (ESXi + vCenter)** : la référence historique en entreprise.
   Hyperviseur propriétaire, écosystème complet (vMotion, DRS, HA, SRM,
   VSAN, NSX), support éditeur, certifications. Ce qu'il a que les autres
   n'ont pas : la maturité outillage/écosystème et les intégrations tierces.
   Ce qui pousse à en sortir : le modèle de licence Broadcom depuis 2024.
2. **Proxmox VE** : QEMU/KVM + LXC + Ceph + corosync, tout en open source
   sur un Debian, API REST, sauvegardes intégrées (PBS), HA simple. Ce
   qu'il a de plus : la simplicité et le coût, un cluster complet en une
   journée. Ce qui lui manque : la multi-location (un « locataire » avec
   son propre réseau, ses quotas, son API isolée) et l'échelle à des
   centaines d'hôtes.
3. **OpenStack** : un **cloud** IaaS multi-locataire : Nova (compute, qui
   pilote libvirt/KVM sur chaque hôte), Neutron (réseaux virtuels par
   locataire, VXLAN/OVN), Cinder (volumes), Glance (images), Keystone
   (identités, projets, quotas), Horizon. Ce qu'il a de plus : l'API
   auto-service pour des milliers d'utilisateurs, compatible Terraform.
   Coût : une équipe pour l'opérer.
4. **Firecracker** : un VMM minimal en Rust au-dessus de KVM, sans QEMU :
   quelques périphériques virtio, pas de BIOS, boot en ~125 ms, empreinte
   de 5 Mo. Fait pour lancer des **microVM** à la demande (AWS Lambda,
   Fargate) et pour isoler des conteneurs avec un vrai noyau (Kata
   Containers). Ce qu'il a de plus : densité et vitesse de démarrage avec
   l'isolation d'une VM. Ce qu'il n'a pas : hotplug, GPU, migration.
5. **VM ou conteneur** : un conteneur partage le noyau de l'hôte (namespaces
   + cgroups) : démarrage en millisecondes, densité maximale, image
   légère, mais toute faille noyau est commune et on ne peut pas y faire
   tourner un autre OS ou un autre noyau. Une VM a son propre noyau :
   isolation forte, autre OS, snapshots/migration de l'état complet, au
   prix de la RAM et du démarrage. Règle pratique : conteneur pour une
   application stateless que je maîtrise, VM pour un système entier, un
   autre OS, une exigence d'isolation forte (multi-locataire), ou un
   logiciel tiers qui veut « son serveur ». Et les deux se combinent :
   Kubernetes tourne dans des VM.
:::

**QO20.9** — *Ballooning, KSM, hugepages.*

::: pourquoi
**Ballooning** (`virtio-balloon`) : l'hôte demande à l'invité de « gonfler
un ballon » : le pilote invité alloue des pages qu'il ne rendra pas à ses
processus et les signale à l'hôte, qui les récupère (`madvise(DONTNEED)`).
`virsh setmem` déclenche ça ; Proxmox le fait automatiquement (option
`balloon`, *shares*) quand l'hôte dépasse 80 % de RAM. Gain : suralloc
souple, mémoire rendue sans redémarrage. Coût : l'invité voit `MemTotal`
baisser et peut se mettre à swapper ; le ballon ne se dégonfle pas tout
seul si l'hôte ne le demande pas. Incident : hôte à 95 %, balloons gonflés
au maximum, invité qui déclenche son OOM killer sur sa base de données.

**KSM** (*Kernel Samepage Merging*) : un thread noyau (`ksmd`) parcourt les
pages marquées `MADV_MERGEABLE` (QEMU le fait pour la RAM invité), calcule
des empreintes, et fusionne les pages identiques en une seule page
copie-sur-écriture. Dix Ubuntu identiques partagent leur noyau et leurs
bibliothèques : 20 à 40 % de RAM récupérée. Coût : du CPU pour scanner, une
latence à la première écriture (copie), et une **faille de canal auxiliaire**
connue (une VM peut deviner si une page existe ailleurs par le temps
d'écriture) : désactivé dans les environnements multi-locataires
(`echo 0 > /sys/kernel/mm/ksm/run`, `ksmtuned` sur Proxmox). Incident : la
RAM « libre » de l'hôte n'est libre que tant que les VM restent identiques ;
une mise à jour dans chaque VM casse le partage et l'hôte manque soudain de
10 Go.

**Hugepages** : des pages de 2 Mo (ou 1 Go) au lieu de 4 Ko pour la RAM de
l'invité. Moins d'entrées TLB, moins de fautes, pas de swap possible : 5 à
15 % de gain pour les bases de données et le calcul. Coût : la mémoire est
**réservée** à l'avance (`vm.nr_hugepages`, ou `hugepages=` au boot),
inutilisable par le reste, pas de ballooning ni de KSM dessus. Incident :
`vm.nr_hugepages=2048` posé à chaud sur un hôte fragmenté n'obtient que 900
pages, la VM refuse de démarrer (`unable to map backing store for guest
RAM`), et 1,8 Go sont bloqués pour rien.
:::

---

## 20.5 Exercices guidés

**E20.1** — *Prouver que `lab-virt` peut accélérer des VM ; paramètre `nested` et ligne `cpu:` sur le nœud.*

```bash
# sur lab-virt
ls -l /dev/kvm                 # crw-rw---- 1 root kvm 10, 232 ... /dev/kvm
kvm-ok                         # INFO: /dev/kvm exists
                               # KVM acceleration can be used
grep -m1 -oE 'vmx|svm' /proc/cpuinfo      # vmx (Intel) ou svm (AMD)
lsmod | grep '^kvm'            # kvm_intel ... kvm ... (kvm_intel utilise kvm)
# sur le nœud Proxmox
cat /sys/module/kvm_intel/parameters/nested        # Y
grep '^cpu:' /etc/pve/qemu-server/9007.conf        # cpu: host
```

::: pourquoi
Quatre couches, quatre preuves. `/proc/cpuinfo` dit ce que le **processeur
vu** sait faire ; c'est le nœud qui l'a exposé grâce à `cpu: host` (sans
cette ligne, `qm` présente `x86-64-v2-AES`, sans `vmx`). `lsmod` dit que le
**noyau** de `lab-virt` a chargé le pilote : `kvm` (générique) et
`kvm_intel` ou `kvm_amd` (spécifique), chargés automatiquement par `udev`
quand le CPU annonce `vmx`. `/dev/kvm` est le **périphérique** que ce module
crée : sans lui, QEMU n'a rien à ouvrir. `kvm-ok` fait tout ça pour toi et
va jusqu'à vérifier que le BIOS n'a pas désactivé VT-x.

Côté nœud, `nested` est le paramètre du module `kvm_intel` qui autorise un
invité à exécuter lui-même `VMXON`. Il ne se lit que dans `/sys/module` ;
`modinfo -p kvm_intel` liste les paramètres possibles. Sous AMD c'est
`kvm_amd`, et la valeur s'affiche `1` au lieu de `Y` (type `int` contre
`bool`).
:::

::: piege
`grep -c vmx /proc/cpuinfo` compte les lignes, donc les cœurs : `4` n'est
pas « 4 fois oui », c'est « 4 CPU avec le drapeau ». Et un `kvm-ok` qui
répond `KVM acceleration can be used` sur un hôte où `lsmod` ne montre
rien est possible : `kvm-ok` charge le module pour tester.
:::

---

**E20.2** — *URI par défaut, accès persistant à `qemu:///system`, socket.*

```bash
virsh uri                              # qemu:///session
echo 'export LIBVIRT_DEFAULT_URI=qemu:///system' >> ~/.bashrc
. ~/.bashrc ; virsh uri                # qemu:///system
virsh list --all                       #  Id  Name  State  (vide, sans erreur)
id -nG | tr ' ' '\n' | grep -x libvirt # libvirt
ls -l /run/libvirt/libvirt-sock   # srw-rw---- 1 root libvirt 0 ... libvirt-sock
systemctl cat libvirtd.socket | grep -E 'Socket(Mode|Group)'
# SocketGroup=libvirt
# SocketMode=0660
```

::: pourquoi
Sans URI, chaque pilote propose la sienne, et le pilote QEMU répond selon
l'UID : `system` pour root, `session` pour les autres. La variable
`LIBVIRT_DEFAULT_URI` est lue par tous les clients (`virsh`, `virt-install`,
`virt-manager`, `libvirt-python`), ce qui en fait le bon endroit pour fixer
le choix. L'alternative `~/.config/libvirt/libvirt.conf` avec `uri_default =
"qemu:///system"` a le même effet sans polluer l'environnement.

Le droit d'entrer vient de la **socket Unix**, comme pour Docker : la
socket est créée par systemd (`libvirtd.socket`, activation à la demande),
en `0660 root:libvirt`. Être dans le groupe `libvirt` suffit donc pour
parler au démon ; il n'y a pas de rôle « lecture seule » sur cette socket,
c'est `libvirt-sock-ro` (`0666`) qui sert aux clients en lecture
(`virsh -r`, `openReadOnly` en Python). Sur Rocky, la même socket est
`/run/libvirt/virtqemud-sock` et l'accès passe par une règle polkit qui
autorise le groupe `libvirt`.
:::

---

**E20.3** — *Versions, ressources, types de domaine, modes CPU.*

```bash
virsh version
# Compiled against library: libvirt 10.0.0
# Using library: libvirt 10.0.0
# Using API: QEMU 10.0.0
# Running hypervisor: QEMU 8.2.2
virsh nodeinfo
# CPU model:           x86_64
# CPU(s):              4
# CPU frequency:       2400 MHz
# CPU socket(s):       1
# Core(s) per socket:  4
# Thread(s) per core:  1
# NUMA cell(s):        1
# Memory size:         6103880 KiB
virsh capabilities | xmllint --xpath \
  "//guest[arch/@name='x86_64']/arch/domain/@type" -
# type="qemu" type="kvm"
virsh domcapabilities --virttype kvm | xmllint --xpath \
  "//cpu/mode/@name | //cpu/mode/@supported" - | paste - -
# name="host-passthrough" supported="yes"
# name="maximum"          supported="yes"
# name="host-model"       supported="yes"
# name="custom"           supported="yes"
```

::: pourquoi
`capabilities` décrit l'**hôte** : ce que libvirt a détecté (topologie,
NUMA, sécurité `apparmor` avec le DOI et le modèle, et pour chaque
architecture invitée disponible les types de domaine : `qemu` = TCG,
`kvm` = accéléré). Si `kvm` manque de la liste, `/dev/kvm` n'est pas
utilisable par libvirt et il faut regarder les groupes ou le module.

`domcapabilities` décrit ce qu'un **domaine** peut demander pour un binaire
QEMU, une machine et un type donnés : modes CPU, modèle `host-model`
calculé (le nom du CPU le plus proche et les drapeaux ajoutés), liste des
modèles `custom` avec `usable='yes|no'` (ceux que l'hôte peut exécuter),
disques, graphismes, TPM, firmware UEFI disponible. C'est la référence
avant d'écrire un XML à la main : un `<cpu mode='custom'><model>EPYC-Milan`
sur un hôte Intel se lit ici comme `usable='no'` avant l'erreur de
démarrage.
:::

---

**E20.4** — *qcow2 vide, occupation réelle, conversion raw, resize, measure.*

```bash
mkdir -p ~/lab20/img && cd ~/lab20/img
qemu-img create -f qcow2 vide.qcow2 20G
ls -l vide.qcow2          # 196616 octets : uniquement l'en-tête et les tables
du -h vide.qcow2          # 196K
qemu-img info vide.qcow2  # virtual size: 20 GiB ; disk size: 196 KiB
qemu-img convert -p -f qcow2 -O raw vide.qcow2 vide.raw
ls -lh vide.raw           # 20G  (taille apparente)
du -h vide.raw            # 0    (fichier creux : aucun bloc alloué)
qemu-img resize vide.qcow2 +5G      # Image resized.
qemu-img info vide.qcow2 | grep virtual   # 25 GiB
qemu-img measure -f raw -O qcow2 vide.raw
# required size: 196608
# fully allocated size: 21478375424
```

::: pourquoi
Un fichier a deux tailles : la **taille apparente** (`st_size`, ce que
`ls -l` affiche, jusqu'où on peut lire) et les **blocs alloués**
(`st_blocks`, ce que `du` et `qemu-img info : disk size` affichent). Un
fichier *sparse* a une taille apparente de 20 Go et zéro bloc : le système
de fichiers renvoie des zéros pour les régions jamais écrites. `qemu-img
convert` produit du creux par défaut : il détecte les zéros et saute
(`-S` règle la granularité, `-S 0` désactive).

Le qcow2 ne compte pas sur le creux du FS : il n'écrit que les clusters
utilisés et ses métadonnées (196 Ko pour 20 Go : l'en-tête, la table L1,
la table de refcounts). C'est pour ça qu'un qcow2 se copie avec `cp` sans
perdre sa compacité, alors qu'un raw creux copié avec un outil naïf (ou
transféré par `scp`) devient plein : `cp --sparse=always` ou `rsync -S`.

`resize` ne touche qu'à l'en-tête (taille virtuelle) : rien n'est alloué.
`measure` calcule, sans écrire, la taille qu'aurait la conversion : utile
avant de convertir 500 Go vers un stockage juste.
:::

---

**E20.5** — *Overlay sur la base, chaîne, pointeur déplacé et rétabli.*

```bash
cd ~/lab20/img
qemu-img create -f qcow2 -F qcow2 \
  -b /var/lib/libvirt/images/ubuntu-24.04-base.qcow2 test.qcow2 20G
qemu-img info --backing-chain test.qcow2
# image: test.qcow2            virtual size: 20 GiB   disk size: 196 KiB
# backing file: /var/lib/libvirt/images/ubuntu-24.04-base.qcow2
# backing file format: qcow2
# image: /var/lib/libvirt/images/ubuntu-24.04-base.qcow2
# virtual size: 3.5 GiB        disk size: 584 MiB
qemu-img rebase -u -F qcow2 -b /tmp/base.qcow2 test.qcow2
qemu-img info test.qcow2 | grep '^backing file:'   # /tmp/base.qcow2
qemu-img info --backing-chain test.qcow2
# qemu-img: Could not open '/tmp/base.qcow2': Could not open
# '/tmp/base.qcow2': No such file or directory
qemu-img rebase -u -F qcow2 \
  -b /var/lib/libvirt/images/ubuntu-24.04-base.qcow2 test.qcow2
```

::: pourquoi
`-b` inscrit dans l'en-tête de l'overlay le chemin de la base ; `-F` inscrit
son format. Depuis QEMU 6, `-F` est obligatoire : deviner le format d'une
base en la sondant est une faille (un raw contenant un en-tête qcow2 forgé
par l'invité pouvait faire lire n'importe quel fichier de l'hôte). Sans
`-F`, `qemu-img` refuse (`Backing file specified without backing format`).

La chaîne peut être plus grande que la base (20 Go sur une base de 3,5 Go) :
les secteurs au-delà de la base se lisent comme des zéros.

`rebase -u` (*unsafe*) ne fait que réécrire le pointeur, sans lire ni copier
de données : c'est l'outil pour réparer une chaîne après un déplacement de
fichiers, à condition que la nouvelle base ait **exactement** le même
contenu que l'ancienne. Sans `-u`, `rebase` lit l'ancienne et la nouvelle
base, et copie dans l'overlay les clusters qui diffèrent : c'est un vrai
changement de base, long mais sûr. Un chemin relatif dans `-b` est
interprété par rapport au répertoire de l'overlay, pas au répertoire
courant : `qemu-img info` l'affiche tel quel, et un déplacement des deux
fichiers ensemble reste cohérent.
:::

---

**E20.6** — *user-data / meta-data, validation, seed par `cloud-localds` puis `genisoimage`, `isoinfo`.*

```bash
mkdir -p ~/lab20/cloud-init/vm-01 && cd ~/lab20/cloud-init/vm-01
{ cat <<'EOF'
#cloud-config
hostname: vm-01
fqdn: vm-01.lab.local
manage_etc_hosts: true
users:
  - name: mathieu
    groups: [sudo]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: true
    ssh_authorized_keys:
EOF
  cat ~/.ssh/id_ed25519.pub ~/.ssh/authorized_keys | sort -u \
    | sed 's/^/      - /'
  cat <<'EOF'
packages: [qemu-guest-agent]
write_files:
  - path: /etc/lab20-marker
    permissions: "0644"
    content: "vm-01\n"
runcmd:
  - systemctl enable --now qemu-guest-agent
EOF
} > user-data
printf 'instance-id: vm-01-%s\nlocal-hostname: vm-01\n' "$(uuidgen)" \
  > meta-data
python3 -c 'import yaml,sys; yaml.safe_load(open("user-data"))' && echo ok
cloud-init schema --config-file user-data      # Valid schema user-data
cloud-localds seed.iso user-data meta-data
genisoimage -quiet -output seed2.iso -volid cidata -joliet -rock \
  user-data meta-data
for i in seed.iso seed2.iso; do
  isoinfo -d -i $i | grep -i 'volume id'        # Volume id: cidata
  isoinfo -R -l -i $i | grep -E 'meta-data|user-data'
done
```

::: pourquoi
Le datasource **NoCloud** de cloud-init cherche, au premier démarrage, un
périphérique bloc dont le label de système de fichiers est `cidata` (ou
`CIDATA`), et y lit `user-data` et `meta-data` (et `network-config`,
`vendor-data` s'ils existent). Le format du support importe peu : ISO 9660
ou vFAT. `cloud-localds` n'est qu'un enrobage de `genisoimage -volid cidata
-joliet -rock` (ou `xorriso`), ce que la seconde commande refait à la main :
c'est ce qu'on utilise sur Rocky, où `cloud-localds` n'existe pas.

Une extension de noms (`-rock` et/ou `-joliet`) est nécessaire : sans elle, ISO 9660 majuscule et
tronque les noms (`USER_DAT.;1`) et cloud-init ne trouve rien. `isoinfo -R`
affiche les noms Rock Ridge.

`meta-data` porte l'`instance-id` : c'est l'identité de l'instance. Les
modules *per-instance* (utilisateurs, clés, `runcmd`, `write_files`) ne
rejouent que si cet identifiant change : mettre un UUID dedans garantit
qu'un seed refait déclenche bien une reconfiguration. `cloud-init schema`
valide contre le schéma JSON des modules (clé inconnue, type faux) — ce que
`yaml.safe_load` ne voit pas : un `packages: qemu-guest-agent` (chaîne au
lieu de liste) est du YAML valide et un user-data invalide.
:::

---

**E20.7** — *Lire le XML de `vm-01` sans éditeur.*

```bash
X() { virsh dumpxml vm-01 | xmllint --xpath "$1" - ; echo; }
X 'string(/domain/os/type/@machine)'                       # pc-q35-8.2
X 'string(/domain/cpu/@mode)'                              # host-passthrough
X "/domain/devices/disk[target/@dev='vda']/driver"
# <driver name="qemu" type="qcow2" discard="unmap"/>   -> pas d'attribut cache
X 'string(/domain/devices/interface/model/@type)'          # virtio
X 'string(/domain/devices/interface/mac/@address)'         # 52:54:00:3a:9c:e1
X "string(/domain/devices/channel/target/@name)"   # org.qemu.guest_agent.0
X 'string(/domain/devices/console/@type)'                  # pty
```

::: pourquoi
Le XML libvirt est **la** définition : tout ce que `virt-install` a décidé
y est, et la ligne de commande QEMU en est dérivée. Points à retenir :

* `machine='pc-q35-8.2'` : chipset moderne (PCIe, AHCI, pas d'IDE), version
  figée au moment de la création : la VM gardera `8.2` même après une mise
  à jour de QEMU, ce qui garantit une carte mère stable (migration,
  Windows qui ne réactive pas sa licence).
* `cache` **absent** : QEMU applique son défaut, `writeback`. Pour un
  serveur, on ajoute `cache='none' io='native'`.
* `discard='unmap'` : présent parce qu'on l'a demandé ; `fstrim` marchera.
* `<channel>` `org.qemu.guest_agent.0` : virt-install l'ajoute dès que
  l'osinfo indique que l'OS sait l'utiliser ; sans ce canal, l'agent
  installé dans l'invité n'a rien à quoi se connecter.
* `<console type='pty'>` : le port série de la VM est relié à un
  pseudo-terminal de l'hôte, ce que `virsh console` attache.

`xmllint --xpath` évite les `grep` fragiles ; `virt-xml vm-01 --print-xml`
et `virsh dumpxml --inactive` donnent la version persistante (celle sur
disque dans `/etc/libvirt/qemu/vm-01.xml`, qu'on n'édite **jamais** à la
main : `virsh edit` valide et notifie le démon).
:::

---

**E20.8** — *virtio-rng : constater, retirer, remettre par `virsh edit` puis `virt-xml` à chaud.*

```bash
virsh dumpxml vm-01 | grep -A2 '<rng'
# <rng model='virtio'>
#   <backend model='random'>/dev/urandom</backend>
virsh shutdown vm-01 && sleep 15
virt-xml vm-01 --remove-device --rng all  # Domain 'vm-01' defined successfully.
virsh start vm-01 && sleep 30
ssh mathieu@$(virsh domifaddr vm-01 | awk '/ipv4/{print $4}' | cut -d/ -f1) \
  'ls /dev/hwrng; lsmod | grep virtio_rng'    # ls: cannot access '/dev/hwrng'
virsh shutdown vm-01 && sleep 15
virsh edit vm-01     # dans <devices> :
#   <rng model='virtio'>
#     <backend model='random'>/dev/urandom</backend>
#   </rng>
virsh start vm-01    # /dev/hwrng présent, virtio_rng chargé
virt-xml vm-01 --remove-device --rng all --update   # à chaud ET dans la conf
# Device hotunplug successful. / Domain 'vm-01' defined successfully.
virt-xml vm-01 --add-device --rng /dev/urandom --update
# Device hotplug successful. / Domain 'vm-01' defined successfully.
ssh ... 'ls -l /dev/hwrng; cat /sys/devices/virtual/misc/hw_random/rng_current'
# virtio_rng.0
```

::: pourquoi
`virtio-rng` fournit à l'invité une source d'entropie matérielle « fournie
par l'hôte » : le pilote `virtio_rng` l'expose en `/dev/hwrng` et le noyau
invité l'utilise pour alimenter son pool (`rng_current`). Les noyaux
récents (≥ 5.6) n'en ont plus un besoin vital (jitter entropy), mais c'est
resté le standard des images cloud et `virt-install` le pose par défaut.

Deux façons de modifier une VM. `virsh edit` ouvre la définition
**persistante** dans `$EDITOR`, la valide à l'enregistrement, et ne touche
pas à la VM en cours : il faut un arrêt/démarrage (pas un simple `reboot`
invité : la VM QEMU reste la même) pour que le nouveau périphérique existe.
`virt-xml` fait la même chose sans éditeur : par défaut il modifie la
définition persistante (comme `virsh edit`), et `--update` tente en plus
l'opération **à chaud** (`virsh attach-device --live` derrière) : c'est
l'équivalent en ligne de commande d'un clic dans virt-manager, sans
redémarrage. Le hotplug marche pour les
périphériques PCI que QEMU sait ajouter (disques, NIC, rng, USB), pas pour
le CPU model, la machine ou le firmware.
:::

---

**E20.9** — *Console série : mot de passe par l'agent, connexion, conditions.*

```bash
virsh console vm-01
# Connected to domain 'vm-01'
# Escape character is ^] (Ctrl + ])
# vm-01 login:  mathieu  ->  Password:  (refusé : lock_passwd: true)
# Ctrl+]  pour sortir
virsh set-user-password vm-01 mathieu 'Lab20!'   # via l'agent, à chaud
virsh console vm-01       # login mathieu / Lab20! fonctionne
virsh dumpxml vm-01 | grep -E '<(serial|console)'
ssh mathieu@... 'cat /proc/cmdline'   # ... console=tty1 console=ttyS0 ...
```

::: pourquoi
La console série est le lien de secours qui survit à un réseau cassé, comme
`qm terminal 9007` côté Proxmox. Deux conditions :

* **Côté XML** : `<serial type='pty'>` crée un port série (UART 16550 sur
  `COM1`, `0x3F8`) relié à un pseudo-terminal de l'hôte (`/dev/pts/N`,
  visible dans le journal QEMU : `char device redirected to /dev/pts/1`),
  et `<console type='pty'><target type='serial'/>` en fait la console
  libvirt. `virt-install --graphics none` l'ajoute automatiquement.
* **Côté invité** : le noyau doit écrire sur ce port (`console=ttyS0` dans
  la ligne de commande, posée par les images cloud dans
  `/etc/default/grub.d/50-cloudimg-settings.cfg`) et systemd doit y lancer
  un `getty` : `systemd-getty-generator` crée `serial-getty@ttyS0.service`
  pour chaque `console=` du noyau, d'où le prompt de login.

Le mot de passe : l'image cloud n'en a pas, cloud-init verrouille le compte
(`lock_passwd: true`), donc SSH par clé uniquement — c'est voulu. L'agent
offre `guest-set-user-password`, que `virsh set-user-password` appelle : le
mot de passe transite par le canal virtio-serial, jamais par le réseau. En
production, on ne pose un mot de passe console que pour un dépannage, et on
le retire après. `Ctrl+]` est le caractère d'échappement de `virsh console`
(`--escape` pour en changer) ; deux consoles sur le même pty se disputent
la sortie (`--force` pour reprendre).
:::

---

**E20.10** — *Interroger l'agent, équivalents `qm`, `guest-exec`.*

```bash
virsh qemu-agent-command vm-01 '{"execute":"guest-ping"}'     # {"return":{}}
virsh qemu-agent-command vm-01 '{"execute":"guest-info"}' \
  | jq '.return.version, ([.return.supported_commands[]
          | select(.enabled) | .name] | length)'
virsh domfsinfo vm-01                # Mountpoint  Name  Type  Target
virsh domhostname vm-01              # vm-01
virsh domifaddr vm-01 --source agent # lo + enp1s0 avec IPv4 et IPv6
virsh domtime vm-01 --pretty         # Time: 2026-09-19 10:41:07
virsh guestinfo vm-01 --os --hostname
# sur le nœud Proxmox, pour lab-virt :
qm agent 9007 ping ; qm agent 9007 get-fsinfo ; qm agent 9007 get-host-name
qm agent 9007 network-get-interfaces ; qm agent 9007 get-time
qm guest exec 9007 -- uptime          # JSON avec out-data déjà décodé
# guest-exec brut, côté libvirt :
PID=$(virsh qemu-agent-command vm-01 '{"execute":"guest-exec",
  "arguments":{"path":"uptime","capture-output":true}}' | jq .return.pid)
virsh qemu-agent-command vm-01 "{\"execute\":\"guest-exec-status\",
  \"arguments\":{\"pid\":$PID}}" | jq -r '.return."out-data"' | base64 -d
```

::: pourquoi
L'agent (`qemu-ga`) est un petit démon dans l'invité, branché sur un port
`virtio-serial` nommé `org.qemu.guest_agent.0`, qui parle JSON (le même
protocole QMP que QEMU). Il permet à l'hôte de faire des choses **dans**
l'invité sans réseau ni identifiants : geler/dégeler les systèmes de
fichiers (`fsfreeze`, c'est la clé des snapshots cohérents), lire les
adresses IP, régler l'horloge après une restauration ou une migration
(`guest-set-time`), arrêter proprement, poser un mot de passe, exécuter une
commande (`guest-exec`, désactivé par défaut sur certaines distributions
via `--block-rpcs`), lire ou écrire un fichier.

`virsh` habille les commandes courantes (`domfsinfo`, `domhostname`,
`guestinfo`, `domfsfreeze`, `domtime`) et `qemu-agent-command` donne accès à
tout le reste. Proxmox fait exactement la même chose avec `qm agent
<vmid> <commande>` et `qm guest exec` — c'est le même `qemu-ga` dans
`lab-virt`, branché sur le même type de canal (`- -agent enabled=1` ajoute le
`virtio-serial` à la VM Proxmox). Et c'est ce même agent qui permet à
`vzdump --mode snapshot` de geler le FS et à Proxmox d'afficher l'IP dans
l'interface. Sans agent : `--source arp`, `virsh console`, et des snapshots
seulement *crash-consistent*.

`guest-exec` est asynchrone : on reçoit un PID, puis on interroge
`guest-exec-status` jusqu'à `exited: true` ; la sortie est en base64.
:::

---

**E20.11** — *Le processus QEMU de `vm-01` : ligne de commande, utilisateur, cgroup, unité, machinectl.*

```bash
PID=$(pgrep -f 'qemu-system-x86_64 -name guest=vm-01,')
ps -o user,pid,%cpu,%mem -p "$PID"     # libvirt+  4213  3.2  9.8
tr '\0' '\n' < /proc/$PID/cmdline \
  | grep -A1 -xE -- '-(accel|cpu|m|smp|machine)' | grep -v '^--$'
# -machine      pc-q35-8.2,usb=off,vmport=off,dump-guest-core=off,...
# -accel        kvm
# -cpu          host,migratable=on
# -m            size=1048576k
# -smp          1,sockets=1,dies=1,cores=1,threads=1
cat /proc/$PID/cgroup
# 0::/machine.slice/machine-qemu\x2d1\x2dvm\x2d01.scope/libvirt/emulator
systemctl status 'machine-qemu\x2d1\x2dvm\x2d01.scope' --no-pager | head -5
systemd-cgls -u machine.slice --no-pager
machinectl list          # MACHINE       CLASS  SERVICE       OS  VERSION
                         # qemu-1-vm-01  vm     libvirt-qemu  -   -
```

::: pourquoi
Une VM, c'est **un processus** `qemu-system-x86_64` (plus ses threads : un
par vCPU, des threads d'E/S, le thread principal). Tout ce que tu sais des
processus (module 08) s'applique : `top` montre sa consommation, `kill -9`
équivaut à `virsh destroy`, un `SIGSTOP` le fige (c'est ce que fait
`virsh suspend`). La ligne de commande est le miroir exact du XML : lire
`-accel`, `-cpu`, `-m`, `-smp`, `-machine`, puis les `-blockdev`/`-device`
et `-netdev`, c'est lire la VM sans passer par libvirt.

L'utilisateur est `libvirt-qemu` (affiché tronqué `libvirt+` par `ps`),
jamais root ; le processus a été confiné en plus par AppArmor.

Le **cgroup** : libvirt demande à systemd (via `systemd-machined`) de créer
une unité transitoire `machine-qemu\x2d<id>\x2d<nom>.scope` dans
`machine.slice` (`\x2d` est le tiret échappé). Dessous, libvirt crée ses
sous-groupes `emulator`, `vcpu0`, `vcpuN`, `iothreadN` : c'est là que
`<cputune><shares>`, `<blkiotune>` et `<memtune>` du XML se traduisent en
`cpu.weight`, `io.max`, `memory.max`. `systemd-cgtop` classe donc les VM
comme n'importe quel service. `machinectl` voit la VM comme une
« machine » : `machinectl status qemu-1-vm-01` donne PID, cgroup et l'OS si
l'agent le rapporte. Proxmox fait pareil : `qemu.slice/<vmid>.scope`.
:::

---

**E20.12** — *Mémoire et disque à chaud, persistants.*

```bash
virsh setmem vm-01 512M --live --config
virsh dommemstat vm-01           # actual 524288 ; unused ; available ; rss
ssh mathieu@IP free -m           # Mem: total 456 (au lieu de 960)
virsh setmem vm-01 1G --live --config
virsh vol-create-as default vm-01-data.qcow2 2G --format qcow2
virsh attach-disk vm-01 /var/lib/libvirt/images/vm-01-data.qcow2 vdb \
  --driver qemu --subdriver qcow2 --targetbus virtio --persistent
# Disk attached successfully
ssh mathieu@IP lsblk              # vdb 252:16 0 2G 0 disk
virsh domblklist vm-01 ; virsh dumpxml vm-01 --inactive | grep vdb
virsh detach-disk vm-01 vdb --persistent   # Disk detached successfully
virsh vol-delete --pool default vm-01-data.qcow2
```

::: pourquoi
`setmem` ne redimensionne pas la VM : il actionne le **ballon**. La borne
haute reste `<memory>` (1 Go) ; on ne peut que descendre en dessous et
remonter jusqu'à cette borne. Le pilote `virtio_balloon` de l'invité alloue
les pages demandées et les rend à l'hôte, et il les retire du compte
(`MemTotal` baisse : `adjust_managed_page_count`). `dommemstat` montre le
point de vue de l'hôte : `actual` = mémoire visible, `rss` = ce que le
processus QEMU occupe réellement (souvent bien moins que `actual` avant
que l'invité ait touché toutes ses pages). Monter au-delà de `<memory>`
demande `virsh setmaxmem` à froid (ou un `<maxMemory>` avec des slots DIMM
pour du vrai hotplug mémoire).

`attach-disk` fabrique le `<disk>` pour toi (`--driver qemu --subdriver
qcow2` sinon libvirt supposerait du raw et l'invité verrait des données
absurdes). `--persistent` sur une VM en marche = `--live` + `--config` :
hotplug immédiat **et** écriture dans la définition. Sans `--config`, le
disque disparaît au prochain arrêt ; sans `--live`, rien ne se passe avant.
Le détachement est une **demande** à l'invité (ACPI/PCIe unplug) : si un
système de fichiers est monté dessus, le noyau invité peut refuser, et
`domblklist` le montre encore. On démonte d'abord.
:::

---

**E20.13** — *Charge CPU mesurée depuis l'hôte, steal time.*

```bash
ssh mathieu@IP 'yes >/dev/null & yes >/dev/null & sleep 1'
virsh cpu-stats vm-01 --total   # Total: cpu_time 84.2s user_time system_time
sleep 10 ; virsh cpu-stats vm-01 --total       # ~ +10 s en 10 s
virsh domstats vm-01 --cpu-total   # cpu.time=94213456789 (ns) cpu.user ...
virt-top -b -n 2 | tail -3   # ID S RDRQ WRRQ RXBY TXBY %CPU %MEM TIME NAME
                             #  1 R    0    0    0    0 25.0  16.4 ... vm-01
ssh mathieu@IP 'top -bn1 | grep Cpu' # ... 0.0 wa, 0.0 hi, 0.0 si, 0.3 st
for i in 1 2 3 4; do yes >/dev/null & done     # sur lab-virt
ssh mathieu@IP 'top -bn1 | grep Cpu' # ... 35.2 st   (varie)
pkill yes ; ssh mathieu@IP pkill yes
```

::: pourquoi
Vu de l'hôte, `vm-01` est un processus qui consomme 100 % d'un cœur (son
unique vCPU est saturé par deux `yes`). `cpu-stats` et `domstats` lisent
les compteurs du cgroup (`cpu.stat`) : `cpu_time` cumule le temps CPU
donné à la VM, tous threads confondus ; la dérivée sur 10 s donne l'usage.
`virt-top` fait cette dérivée et affiche un `%CPU` normalisé par le nombre
de CPU hôte (`25.0` = un cœur entier sur les 4 de `lab-virt`); la première trame n'a pas de mesure précédente et affiche 0, d'où `-n 2`.

Puis on sature l'hôte : 4 `yes` sur 4 vCPU de `lab-virt`, plus le thread
vCPU de `vm-01`, plus les threads QEMU : 5 demandeurs pour 4 CPU. Le CFS de
`lab-virt` partage équitablement, donc le thread vCPU n'obtient que ~80 %
d'un cœur. L'invité, lui, n'a rien changé : ses deux `yes` demandent
toujours 100 %. La différence apparaît en `st` : KVM écrit dans une page
partagée (`steal time` paravirtuel) le temps pendant lequel le vCPU était
prêt mais non ordonnancé, et le noyau invité le comptabilise à part. Sans
cette colonne, l'invité verrait simplement ses processus ralentir sans
explication. Le problème appartient à l'hôte : c'est là qu'il faut agir
(moins de charge, `cputune` avec `<shares>` pour prioriser `vm-01`, ou
pinning). Et souviens-toi que `lab-virt` subit elle-même le steal du nœud
Proxmox : `top` sur `lab-virt` a aussi une colonne `st`.
:::

---

**E20.14** — *Réseau `default` : XML, baux, bridge, NAT, réservation à chaud.*

```bash
virsh net-dumpxml default
# <network connections='1'>
#   <name>default</name>
#   <forward mode='nat'><nat><port start='1024' end='65535'/></nat></forward>
#   <bridge name='virbr0' stp='on' delay='0'/>
#   <ip address='192.168.122.1' netmask='255.255.255.0'>
#     <dhcp><range start='192.168.122.2' end='192.168.122.254'/></dhcp>
virsh net-dhcp-leases default
# Expiry Time  MAC address  Protocol  IP address  Hostname  Client ID
# 2026-09-19 11:52:10  52:54:00:3a:9c:e1  ipv4  192.168.122.101/24  vm-01  ...
ip -br link show master virbr0     # vnet0  UNKNOWN  fe:54:00:3a:9c:e1
bridge link | grep virbr0
sudo iptables -t nat -L LIBVIRT_PRT -nv
# MASQUERADE tcp -- * * 192.168.122.0/24 !192.168.122.0/24 masq ports:1024-65535
# MASQUERADE udp ... / MASQUERADE all ...
MAC=$(virsh domiflist vm-01 | awk '/default/{print $5}')
virsh net-update default add ip-dhcp-host \
  "<host mac='$MAC' name='vm-01' ip='192.168.122.50'/>" --live --config
ssh mathieu@192.168.122.101 'sudo networkctl reconfigure enp1s0'
sleep 5 ; virsh domifaddr vm-01     # 192.168.122.50/24
```

::: pourquoi
Le réseau `default` est une recette en trois ingrédients que libvirt
assemble à `net-start` : (1) un bridge `virbr0` créé par `ip link add`,
adressé `192.168.122.1` — c'est l'équivalent exact de `vmbr1` sur le nœud,
et le `vnet0` qui y est branché est le `tap` de `vm-01`, comme le `tap9007i0`
de `lab-virt` sur `vmbr1` ; (2) un `dnsmasq` dédié
(`/var/lib/libvirt/dnsmasq/default.conf`, baux dans `default.status`) —
l'équivalent du `dnsmasq` du chapitre 0, avec DHCP en plus ; (3) des règles
netfilter dans des chaînes préfixées `LIBVIRT_` : `PRT` (nat POSTROUTING,
le `MASQUERADE` avec plage de ports pour ne pas entrer en collision avec les
ports de l'hôte), `FWO`/`FWI` (FORWARD sortant/entrant, `REJECT` par
défaut sauf établi), `FWX` (VM ↔ VM), `INP` (autoriser DHCP/DNS vers le
bridge). C'est `lab-nat.sh` écrit par un programme.

`net-update` modifie un réseau **en marche** : `--live` réécrit la conf de
`dnsmasq` et lui envoie `SIGHUP`, `--config` met à jour le XML persistant.
Sections modifiables : `ip-dhcp-host`, `ip-dhcp-range`, `dns-host`,
`portgroup`… La réservation ne prend effet que quand le client redemande un
bail : `networkctl reconfigure` relance le DHCP de `systemd-networkd`
(l'image Ubuntu utilise Netplan → networkd), et `dnsmasq` refuse l'ancienne
adresse (`DHCPNAK`) puis attribue la réservée.
:::

---

**E20.15** — *Journal QEMU, événements libvirt, journal du démon.*

```bash
sudo grep -n 'qemu-system-x86_64' /var/log/libvirt/qemu/vm-01.log | tail -1
sudo grep 'shutting down' /var/log/libvirt/qemu/vm-01.log | tail -1
# 2026-09-19 10:33:02.118+0000: shutting down, reason=shutdown
# terminal 1 :
virsh event --all --loop
# terminal 2 :
virsh reboot vm-01
# terminal 1 reçoit :
# event 'reboot' for domain 'vm-01'
# event 'agent-lifecycle' for domain 'vm-01': state: 'disconnected' reason: ...
# event 'agent-lifecycle' for domain 'vm-01': state: 'connected' reason: ...
journalctl -u libvirtd -n 20 --no-pager
```

::: pourquoi
Trois journaux, trois niveaux. `/var/log/libvirt/qemu/<vm>.log` est la
**sortie standard/erreur de QEMU** pour cette VM : chaque démarrage y écrit
un en-tête (`starting up libvirt version..., qemu version..., hostname`),
la ligne de commande complète avec ses variables d'environnement, la
redirection des pty, puis tout ce que QEMU dit jusqu'à `shutting down,
reason=…` (`shutdown` = arrêt demandé par l'invité, `destroyed` =
`virsh destroy`, `crashed`). C'est le premier fichier à ouvrir sur une VM
qui ne démarre pas : l'erreur y est presque toujours.

`virsh event` s'abonne aux **événements** du démon : `lifecycle` (Started,
Stopped, Suspended avec la raison), `reboot`, `agent-lifecycle`,
`block-job`, `disk-change`, `tray-change`, `watchdog`… C'est l'API qu'un
outil comme un orchestrateur utilise pour réagir sans scruter (`libvirt
-python` : `domainEventRegisterAny`). Un `virsh reboot` ne produit **pas** de
`Stopped/Started` : le processus QEMU ne meurt pas, seul l'invité
redémarre ; l'agent, lui, se déconnecte/reconnecte.

`journalctl -u libvirtd` contient les messages du démon lui-même : erreurs
internes, problèmes de configuration, refus de démarrage avant même le
lancement de QEMU. Les refus AppArmor sont dans `journalctl -k` (`DENIED`),
SELinux dans `ausearch`.
:::

---

**E20.16** — *Inventaire en Python et en bash ; état d'une VM en `managedsave`.*

```python
#!/usr/bin/env python3
"""inventaire.py — VM de qemu:///system en JSON (libvirt-python)."""
import json
import xml.etree.ElementTree as ET
import libvirt

ETATS = {
    libvirt.VIR_DOMAIN_NOSTATE: "inconnu",
    libvirt.VIR_DOMAIN_RUNNING: "running",
    libvirt.VIR_DOMAIN_BLOCKED: "blocked",
    libvirt.VIR_DOMAIN_PAUSED: "paused",
    libvirt.VIR_DOMAIN_SHUTDOWN: "shutdown",
    libvirt.VIR_DOMAIN_SHUTOFF: "shut off",
    libvirt.VIR_DOMAIN_CRASHED: "crashed",
    libvirt.VIR_DOMAIN_PMSUSPENDED: "pmsuspended",
}

conn = libvirt.openReadOnly("qemu:///system")
vms = []
for dom in conn.listAllDomains():
    etat, maxmem, mem, vcpus, _cputime = dom.info()
    racine = ET.fromstring(dom.XMLDesc(0))
    disques = [s.get("file") for s in
               racine.findall("./devices/disk[@device='disk']/source")]
    vms.append({"nom": dom.name(), "etat": ETATS.get(etat, "?"),
                "saved": bool(dom.hasManagedSaveImage(0)),
                "vcpus": vcpus, "mem_mo": mem // 1024, "disques": disques})
print(json.dumps(sorted(vms, key=lambda v: v["nom"]), indent=2))
```

```bash
#!/usr/bin/env bash
# inventaire.sh — même chose avec virsh + jq
set -euo pipefail
for vm in $(virsh list --all --name); do
  etat=$(virsh domstate --reason "$vm")
  cpu=$(virsh dominfo "$vm" | awk -F': *' '/^CPU\(s\)/{print $2}')
  mem=$(virsh dominfo "$vm" | awk '/^Used memory/{print int($3/1024)}')
  disques=$(virsh domblklist "$vm" --details | awk '$2=="disk"{print $4}' \
            | paste -sd,)
  jq -n --arg n "$vm" --arg e "$etat" --argjson c "$cpu" --argjson m "$mem" \
    --arg d "$disques" \
    '{nom:$n, etat:$e, vcpus:$c, mem_mo:$m, disques:($d|split(","))}'
done | jq -s 'sort_by(.nom)'
```

::: pourquoi
`libvirt-python` est un binding fin sur l'API C : `openReadOnly` suffit
pour inventorier (socket `libvirt-sock-ro`, accessible à tout le monde),
`open` pour agir (`dom.create()`, `dom.shutdown()`, `dom.destroy()`,
`conn.defineXML()`, `dom.attachDeviceFlags()`). `dom.info()` renvoie un
tuple (état, mémoire max en Ko, mémoire courante, vCPU, temps CPU en ns) ;
tout le reste se lit dans le XML, d'où `ElementTree`. C'est le module 27 :
un script qui produit du JSON se branche sur tout (inventaire Ansible
dynamique, Prometheus, une CLI `argparse`).

Le cas `managedsave` montre la limite d'un inventaire naïf : pour libvirt,
une VM dont l'état a été sauvegardé sur disque est **shut off** (`info()`
dit `SHUTOFF`, `virsh list` dit `shut off`) : il n'y a pas de processus.
Mais elle ne démarrera pas « propre » : elle reprendra son état sauvegardé.
`hasManagedSaveImage()` en Python, `virsh domstate --reason` (`shut off
(saved)`) ou `virsh list --all --managed-save` (`saved`) en bash rendent
cette nuance visible ; l'oublier, c'est croire qu'on peut modifier le
disque d'une VM « arrêtée » alors que sa RAM sauvegardée croit encore
l'ancien contenu.
:::

---

## 20.6 Labs

### **L20.1** — *Premier hôte KVM : `vm-01` depuis l'image cloud, cloud-init, SSH, agent.*

**Étape 1 — imbrication (nœud Proxmox, puis `lab-virt`)**

```bash
# nœud
cat /sys/module/kvm_intel/parameters/nested \
  || cat /sys/module/kvm_amd/parameters/nested
echo "options kvm-intel nested=1" > /etc/modprobe.d/kvm-intel.conf   # si N
qm set 9007 --cpu host --cores 4 --memory 6144
qm stop 9007 ; qm start 9007
# lab-virt
ls -l /dev/kvm && kvm-ok
```

**Étape 2 — pile, groupes, URI**

```bash
sudo bash ~/workbook/scripts/setup/setup_M20.sh
sudo adduser mathieu libvirt ; sudo adduser mathieu kvm
echo 'export LIBVIRT_DEFAULT_URI=qemu:///system' >> ~/.bashrc ; exec bash
virsh list --all            # vide
virsh net-list --all        # default  active  yes (autostart)  yes (persistent)
```

**Étape 3 — la base**

```bash
virsh vol-list default --details
#  Name                     Path                    Type  Capacity  Allocation
#  ubuntu-24.04-base.qcow2  /var/lib/libvirt/i...   file  3.50 GiB  584.00 MiB
virsh vol-dumpxml default ubuntu-24.04-base.qcow2 \
  | grep -E 'capacity|allocation|format'
```

Capacité = taille virtuelle (ce que l'invité voit, 3,5 Go : l'image cloud
est petite et cloud-init agrandit la partition au premier démarrage) ;
allocation = octets réellement occupés sur l'hôte (le qcow2 est compressé
et creux).

**Étape 4 — le disque, comme volume**

```bash
virsh vol-create-as default vm-01.qcow2 20G --format qcow2 \
  --backing-vol ubuntu-24.04-base.qcow2 --backing-vol-format qcow2
virsh vol-dumpxml default vm-01.qcow2 | grep -A3 backingStore
#   <backingStore>
#     <path>/var/lib/libvirt/images/ubuntu-24.04-base.qcow2</path>
#     <format type='qcow2'/>
```

**Étape 5 — le seed**

```bash
cd ~/lab20/cloud-init/vm-01          # user-data et meta-data de E20.6
cloud-localds seed.iso user-data meta-data
virsh vol-create-as default vm-01-seed.iso "$(stat -c %s seed.iso)" --format raw
virsh vol-upload --pool default vm-01-seed.iso seed.iso
virsh vol-list default | grep vm-01
```

**Étape 6 — `virt-install`**

```bash
virt-install --osinfo list | grep -x ubuntu24.04 || echo "prends ubuntu22.04"
virt-install --name vm-01 --memory 1024 --vcpus 1 --cpu host-passthrough \
  --osinfo ubuntu24.04 --import \
  --disk vol=default/vm-01.qcow2,bus=virtio,discard=unmap \
  --disk vol=default/vm-01-seed.iso,device=cdrom \
  --network network=default,model=virtio \
  --graphics none --noautoconsole
# Starting install...
# Creating domain...                              |    0 B  00:00:00
# Domain creation completed.
```

**Étape 7 — console, IP, SSH, agent**

```bash
virsh console vm-01      # ... Cloud-init v. 24.4 finished at ... Datasource
                         # DataSourceNoCloud [seed=/dev/sr0][dsmode=net]. Up 31s
                         # Ctrl+]
virsh domifaddr vm-01
#  Name   MAC address         Protocol   Address
#  vnet0  52:54:00:3a:9c:e1   ipv4       192.168.122.101/24
IP=192.168.122.101
ssh mathieu@$IP 'cat /etc/lab20-marker; cloud-init status'
# vm-01
# status: done
virsh qemu-agent-command vm-01 '{"execute":"guest-ping"}'    # {"return":{}}
```

**Étape 8 — autostart, arrêt, instance-id**

```bash
virsh autostart vm-01            # Domain 'vm-01' marked as autostarted
ls -l /etc/libvirt/qemu/autostart/       # lien symbolique vm-01.xml
ssh mathieu@$IP 'cloud-init query instance_id'
virsh shutdown vm-01 ; sleep 15 ; virsh start vm-01 ; sleep 30
ssh mathieu@$IP 'cloud-init query instance_id; ls -l /etc/lab20-marker'
```

**Étape 9 — le rapport** (`~/lab20/rapports/evo-412.md`) : la ligne QEMU vient
de `sudo grep -m1 qemu-system /var/log/libvirt/qemu/vm-01.log` ; les cinq
points à commenter : `-machine pc-q35-8.2` (chipset), `-accel kvm` (KVM),
`-cpu host,migratable=on` (passthrough), `-blockdev ... "driver":"qcow2"
... "backing":"libvirt-2-format"` (la chaîne base + overlay, ouverte par
QEMU, pas par libvirt), `-device virtio-blk-pci` / `virtio-net-pci` /
`virtserialport ... name=org.qemu.guest_agent.0` (virtio et le canal de
l'agent).

::: pourquoi
Tout ce lab fait **une chose** : montrer qu'une VM n'est pas installée mais
**assemblée**. L'image cloud est un disque déjà installé, générique, sans
identité. Le volume overlay lui donne un espace d'écriture privé sans
copier la base (étape 4 : quelques centaines de Ko). Le seed lui donne son
identité (étape 5), lue au premier démarrage par le datasource NoCloud
(`seed=/dev/sr0` dans le message final : cloud-init a bien trouvé le
cdrom `cidata`). `virt-install --import` ne fait qu'écrire le XML et
démarrer : pas de média d'installation, `--import` dit « boote sur le
premier disque tel quel ».

Passer par les **volumes** plutôt que par `sudo qemu-img create` dans
`/var/lib/libvirt/images` n'est pas de la coquetterie : l'API libvirt fait
le travail en root pour toi (création, upload, propriétaire), ce qui permet
un script sans `sudo` (L20.5) et une exécution à distance
(`virsh -c qemu+ssh://lab-virt/system`). `--backing-vol` demande à
libvirt de lancer `qemu-img create -b ... -F qcow2` avec les bons chemins.

L'`instance-id` inchangé à l'étape 8 prouve que cloud-init distingue un
*redémarrage* d'un *premier démarrage* : les modules per-instance ne
rejouent pas, le marqueur n'est pas réécrit, la clé SSH d'hôte ne change
pas. L'autostart est un simple lien dans `/etc/libvirt/qemu/autostart/`
que `libvirtd` lit à son démarrage : c'est l'équivalent de `qm set --onboot
1`.
:::

::: piege
Trois erreurs qui reviennent : (1) `virt-install` sans `--osinfo` refuse de
continuer (« --os-variant/--osinfo OS name is required ») ; `--osinfo
detect=on,require=off` est l'échappatoire quand on ne sait pas. (2) Oublier
`device=cdrom` sur la seed : virt-install la traite comme un second disque
et cloud-init ne trouve pas de `cidata`... il le trouve quand même en
réalité (il scanne tous les blocs), mais l'invité voit un `vdb` bizarre.
(3) Lancer `virt-install` depuis `qemu:///session` par oubli de l'URI : la
VM se crée, sans réseau `default` (« Network not found »), et elle
n'apparaît pas dans `sudo virsh list`.
:::

---

### **L20.2** — *Bridge `br0` sur le LAN, VM en statique, réseau isolé, netfilter.*

**Étape 1 — le bridge Netplan sur `lab-virt`**

```bash
ip -br link           # eth0  UP  bc:24:11:7e:2a:10 <BROADCAST,MULTICAST,UP,...>
sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg <<'EOF'
network: {config: disabled}
EOF
sudo cp /etc/netplan/50-cloud-init.yaml ~/lab20/50-cloud-init.yaml.orig
MAC=$(cat /sys/class/net/eth0/address)
sudo tee /etc/netplan/50-cloud-init.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      match:
        macaddress: $MAC
      set-name: eth0
      dhcp4: false
EOF
sudo tee /etc/netplan/60-br0.yaml <<'EOF'
network:
  version: 2
  bridges:
    br0:
      interfaces: [eth0]
      addresses: [10.10.10.16/24]
      routes:
        - to: default
          via: 10.10.10.1
      nameservers:
        addresses: [10.10.10.1]
        search: [lab.local]
EOF
sudo chmod 600 /etc/netplan/*.yaml
sudo netplan try          # Entrée pour confirmer dans les 120 s
# pas de bloc parameters: (stp, forward-delay) : netplan try refuse un
# bridge qui en a (« reverting custom parameters ... is not supported »)
ip -br addr show br0      # br0  UP  10.10.10.16/24
bridge link               # 2: eth0: ... master br0 state forwarding
ping -c2 10.10.10.10
```

**Étape 2 — le réseau `lan` côté libvirt**

```bash
cat > ~/lab20/xml/net-lan.xml <<'EOF'
<network>
  <name>lan</name>
  <forward mode='bridge'/>
  <bridge name='br0'/>
</network>
EOF
virsh net-define ~/lab20/xml/net-lan.xml
virsh net-start lan ; virsh net-autostart lan
diff <(virsh net-dumpxml default) <(virsh net-dumpxml lan)
```

Il manque `<ip>`, `<dhcp>`, `<mac>` et le mode `nat` : en mode `bridge`,
libvirt ne **possède** pas le bridge, il se contente d'y brancher des `tap`.
Pas de `dnsmasq`, pas de netfilter, pas d'adresse.

**Étape 3 — `vm-lan` en statique**

```bash
mkdir -p ~/lab20/cloud-init/vm-lan && cd ~/lab20/cloud-init/vm-lan
sed 's/vm-01/vm-lan/g' ../vm-01/user-data > user-data
printf 'instance-id: vm-lan-%s\nlocal-hostname: vm-lan\n' "$(uuidgen)" \
  > meta-data
cat > network-config <<'EOF'
version: 2
ethernets:
  id0:
    match:
      name: "en*"
    dhcp4: false
    addresses: [10.10.10.161/24]
    routes:
      - to: default
        via: 10.10.10.1
    nameservers:
      addresses: [10.10.10.1]
      search: [lab.local]
EOF
cloud-localds -N network-config seed.iso user-data meta-data
virsh vol-create-as default vm-lan.qcow2 20G --format qcow2 \
  --backing-vol ubuntu-24.04-base.qcow2 --backing-vol-format qcow2
virsh vol-create-as default vm-lan-seed.iso "$(stat -c %s seed.iso)" \
  --format raw
virsh vol-upload --pool default vm-lan-seed.iso seed.iso
virt-install --name vm-lan --memory 1024 --vcpus 1 --cpu host-passthrough \
  --osinfo ubuntu24.04 --import \
  --disk vol=default/vm-lan.qcow2,bus=virtio,discard=unmap \
  --disk vol=default/vm-lan-seed.iso,device=cdrom \
  --network bridge=br0,model=virtio --graphics none --noautoconsole
# depuis lab-adm :
ping -c2 10.10.10.161
ssh mathieu@10.10.10.161 'hostname; getent hosts lab-git'
```

**Étape 4 — trouver l'adresse, voir les trames**

```bash
virsh domifaddr vm-lan                    # (rien : pas de bail libvirt)
virsh domifaddr vm-lan --source agent     # enp1s0 ... 10.10.10.161/24
virsh domifaddr vm-lan --source arp       # après un premier échange
sudo tcpdump -ni br0 -e icmp -c 2         # pendant un ping depuis lab-adm
# bc:24:11:2c:51:0a > 52:54:00:9d:44:b7, ... 10.10.10.10 > 10.10.10.161:
#   ICMP echo request
# 52:54:00:9d:44:b7 > bc:24:11:2c:51:0a, ... 10.10.10.161 > 10.10.10.10:
#   ICMP echo reply
```

Le MAC source est celui de `lab-adm` (OUI `bc:24:11`, Proxmox), la
destination celui de la VM (OUI `52:54:00`, QEMU). `lab-virt` n'apparaît
nulle part : le bridge commute en couche 2, la pile IP de l'hôte n'est pas
traversée.

**Étape 5 — réseau isolé et seconde carte à chaud**

```bash
virsh net-define ~/lab20/xml/net-isole.xml
virsh net-start isole ; virsh net-autostart isole
for vm in vm-01 vm-lan; do
  virsh attach-interface $vm network isole --model virtio --persistent
done
virsh domiflist vm-lan          # vnet3  network  isole  virtio  52:54:00:..
# dans chaque invité (exemple vm-lan) :
MAC=$(virsh domiflist vm-lan | awk '/isole/{print $5}')
ssh mathieu@10.10.10.161 "sudo tee /etc/netplan/60-isole.yaml <<EOF
network:
  version: 2
  ethernets:
    isole0:
      match: {macaddress: '$MAC'}
      set-name: isole0
      dhcp4: true
      dhcp4-overrides: {use-routes: false, use-dns: false}
EOF
sudo chmod 600 /etc/netplan/60-isole.yaml; sudo netplan apply; ip -br -4 a"
# idem sur vm-01 avec son IP 192.168.122.x et son MAC
virsh net-dhcp-leases isole      # les deux VM en 10.20.0.1xx
ssh mathieu@10.10.10.161 'ping -c2 10.20.0.1; ping -c2 10.20.0.101; \
  ping -c1 -W1 -I isole0 9.9.9.9'   # OK, OK, 100% loss
ping -c1 -W1 10.20.0.1              # depuis lab-adm : injoignable
```

`use-routes: false` évite que le DHCP de `isole` impose une route par
défaut vers `10.20.0.1`, qui ne mène nulle part.

**Étape 6 — les bridges et les règles**

```bash
ip -br link show type bridge      # br0  virbr0  virbr20
bridge link                       # eth0 -> br0 ; vnet0,vnet3 -> virbr0/virbr20
sudo iptables -L LIBVIRT_FWO -nv  # ACCEPT -s 192.168.122.0/24 -i virbr0
                                  # REJECT -i virbr0 ; REJECT -i virbr20
sudo iptables -L LIBVIRT_FWI -nv  # ACCEPT -d 192.168.122.0/24 -o virbr0
                                  #   ctstate RELATED,ESTABLISHED
                                  # REJECT -o virbr0 ; REJECT -o virbr20
sudo iptables -L LIBVIRT_FWX -nv  # ACCEPT -i virbr0 -o virbr0
                                  # ACCEPT -i virbr20 -o virbr20
sudo iptables -t nat -L LIBVIRT_PRT -nv   # MASQUERADE 192.168.122.0/24
                                          # (rien pour isole)
```

`FWO` : ce qui **sort** d'un bridge vers ailleurs : autorisé pour le NAT,
rejeté pour l'isolé. `FWI` : ce qui **entre** vers un bridge : seulement
les retours de connexions établies (NAT), rien (isolé). `FWX` : VM ↔ VM sur
un même bridge, toujours accepté. `PRT` : le `MASQUERADE`, seulement pour
le NAT. Pour `br0` : aucune règle, libvirt ne s'en mêle pas.

**Étape 7 — le tableau** (`res-77.md`)

| Mode | Qui voit la VM | Adressage | Proxmox |
|---|---|---|---|
| NAT | l'hôte et les VM du même `virbrN` ; le LAN ne voit que l'IP de l'hôte | DHCP dnsmasq libvirt | `vmbr1` + `lab-nat.sh` |
| bridge | tout le LAN, comme une machine physique | DHCP du LAN ou statique | `vmbr0`, `vmbr1` |
| isolé | les VM du bridge + l'hôte par l'IP du bridge | DHCP dnsmasq, sans route | `vmbrX` sans port, sans NAT |
| macvtap | le LAN, mais pas l'hôte | DHCP du LAN | (pas d'équivalent) |

::: pourquoi
Un bridge Linux est un **commutateur** logiciel. `eth0` en devient un port ;
l'adresse IP de `lab-virt` passe sur `br0` (l'interface du commutateur
lui-même), et chaque VM branchée reçoit un port `vnetN`. Quand `lab-adm`
envoie un ping à `10.10.10.161`, la trame arrive sur `eth0`, le bridge lit
le MAC destination dans sa table (`bridge fdb show`) et la commute vers
`vnet1` : le noyau de `lab-virt` ne « route » rien, il commute. C'est la
même chose que `vmbr1` : sur le nœud, `tap9007i0` (le port de `lab-virt`)
transporte maintenant des trames avec deux MAC sources différents (celui de
`eth0` et celui de la VM), ce qu'un bridge accepte sans broncher — sauf si le
pare-feu Proxmox de la VM active le filtrage MAC.

Netplan désactivé côté cloud-init : sinon, à un changement d'`instance-id`,
cloud-init réécrirait `50-cloud-init.yaml` avec l'adresse sur `eth0` et on
aurait deux fois `10.10.10.16`. `netplan try` applique, attend 120 s, et
annule si tu ne confirmes pas : indispensable quand on travaille sur
l'interface qui porte sa propre session SSH.

Le réseau isolé montre ce qu'est réellement un réseau libvirt : un bridge
que **libvirt crée** (`virbr20`, sans port physique), une adresse pour
l'hôte, un `dnsmasq` si `<dhcp>`, et des règles `REJECT` en `FORWARD` qui
interdisent au noyau de router ces paquets : les VM se parlent (couche 2),
l'hôte répond (`10.20.0.1` est à lui), rien ne sort. Retire les règles
`REJECT` et active `ip_forward` : tu as un réseau routé.
:::

---

### **L20.3** — *Pool `dir`, trois clones en 30 s, resize à chaud, clone complet et sysprep.*

**Étapes 1-2 — pool et base**

```bash
virsh pool-define-as lab20 dir --target /srv/vm      # ou pool-define du gabarit
virsh pool-build lab20 ; virsh pool-start lab20 ; virsh pool-autostart lab20
ls -ld /srv/vm                    # drwx--x--x 2 root root ... /srv/vm
sudo cp /var/lib/libvirt/images/ubuntu-24.04-base.qcow2 /srv/vm/
sudo chmod 0444 /srv/vm/ubuntu-24.04-base.qcow2
virsh pool-refresh lab20 ; virsh vol-list lab20 --details
```

**Étape 3 — `clone3.sh`**

```bash
#!/usr/bin/env bash
# clone3.sh — trois VM jetables depuis la base du pool lab20
set -euo pipefail
export LIBVIRT_DEFAULT_URI=qemu:///system
POOL=lab20 BASE=ubuntu-24.04-base.qcow2
if virt-install --osinfo list | grep -x ubuntu24.04 >/dev/null; then
  OSINFO=ubuntu24.04; else OSINFO=ubuntu22.04; fi
for n in 1 2 3; do
  vm=clone-$n; d=~/lab20/cloud-init/$vm; mkdir -p "$d"
  if virsh dominfo "$vm" >/dev/null 2>&1; then echo "$vm existe"; continue; fi
  virsh vol-create-as $POOL "$vm.qcow2" 20G --format qcow2 \
    --backing-vol $BASE --backing-vol-format qcow2 >/dev/null
  { printf '#cloud-config\nhostname: %s\nmanage_etc_hosts: true\n' "$vm"
    printf 'users:\n  - name: mathieu\n    groups: [sudo]\n'
    printf '    shell: /bin/bash\n'
    printf '    sudo: "ALL=(ALL) NOPASSWD:ALL"\n    lock_passwd: true\n'
    printf '    ssh_authorized_keys:\n'
    cat ~/.ssh/id_ed25519.pub ~/.ssh/authorized_keys | sort -u \
      | sed 's/^/      - /'
    printf 'packages: [qemu-guest-agent]\nruncmd:\n'
    printf '  - systemctl enable --now qemu-guest-agent\n'
  } > "$d/user-data"
  printf 'instance-id: %s\nlocal-hostname: %s\n' "$(uuidgen)" "$vm" \
    > "$d/meta-data"
  cloud-localds "$d/seed.iso" "$d/user-data" "$d/meta-data"
  virsh vol-create-as $POOL "$vm-seed.iso" "$(stat -c %s "$d/seed.iso")" \
    --format raw >/dev/null
  virsh vol-upload --pool $POOL "$vm-seed.iso" "$d/seed.iso"
  virt-install --name "$vm" --memory 512 --vcpus 1 --cpu host-passthrough \
    --osinfo "$OSINFO" --import \
    --disk "vol=$POOL/$vm.qcow2,bus=virtio,discard=unmap" \
    --disk "vol=$POOL/$vm-seed.iso,device=cdrom" \
    --network network=default,model=virtio --graphics none --noautoconsole \
    >/dev/null
  echo "$vm lancée"
done
```

```bash
time bash ~/lab20/bin/clone3.sh      # real 0m9.8s
```

**Étape 4 — l'espace**

```bash
for n in 1 2 3; do virsh vol-info --pool lab20 clone-$n.qcow2; done
# Capacity: 20.00 GiB  Allocation: 168.31 MiB   (après cloud-init et apt)
sudo du -sh /srv/vm/clone-*.qcow2 /srv/vm/ubuntu-24.04-base.qcow2
virsh pool-info lab20              # Allocation / Available du FS
```

Trois VM « de 20 Go » = une base de 584 Mo lue par tous + trois overlays de
quelques centaines de Mo (ce que cloud-init, le journal et `apt` ont
écrit). L'allocation grandira avec chaque écriture, jamais au-delà de 20 Go
par VM, et l'hôte a 40 Go : la surallocation est de 60 Go pour 3 VM.

**Étape 5 — agrandir à chaud**

```bash
virsh blockresize clone-1 vda 30G     # Block device 'vda' is resized
IP=$(virsh domifaddr clone-1 | awk '/ipv4/{print $4}' | cut -d/ -f1)
ssh mathieu@$IP 'lsblk /dev/vda; sudo growpart /dev/vda 1; \
  sudo resize2fs /dev/vda1; df -h /'
# vda 30G ; CHANGED: partition=1 ... ; resize2fs ... now 7864059 blocks ; / 29G
```

**Étape 6 — clone complet et sysprep**

```bash
virsh shutdown clone-1 ; sleep 15
time virt-clone --original clone-1 --name clone-4 --auto-clone \
  --file /srv/vm/clone-4.qcow2       # real 0m41s
virsh vol-info --pool lab20 clone-4.qcow2   # Allocation: 2.31 GiB
sudo qemu-img info /srv/vm/clone-4.qcow2 | grep backing   # (rien)
sudo virt-sysprep -d clone-4 --hostname clone-4 \
  --operations defaults,-ssh-userdir
# seed neuf
d=~/lab20/cloud-init/clone-4; mkdir -p $d
sed 's/clone-1/clone-4/g' ~/lab20/cloud-init/clone-1/user-data \
  > $d/user-data
printf 'instance-id: %s\nlocal-hostname: clone-4\n' "$(uuidgen)" > $d/meta-data
cloud-localds $d/seed.iso $d/user-data $d/meta-data
virsh vol-create-as lab20 clone-4-seed.iso "$(stat -c %s $d/seed.iso)" \
  --format raw
virsh vol-upload --pool lab20 clone-4-seed.iso $d/seed.iso
virt-xml clone-4 --edit target=sda --disk path=/srv/vm/clone-4-seed.iso
virsh start clone-4 ; virsh start clone-1 ; sleep 40
for vm in clone-1 clone-4; do
  ssh mathieu@$(virsh domifaddr $vm | awk '/ipv4/{print $4}' | cut -d/ -f1) \
    'hostname; cat /etc/machine-id; \
     ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'
done
```

**Étape 7 — destruction propre**

```bash
for vm in clone-2 clone-3; do
  virsh destroy $vm ; virsh undefine $vm --remove-all-storage
done
virsh vol-list lab20              # base, clone-1*, clone-4*
```

**Étape 8** (`sto-208.md`) : backing file : ~10 s pour trois VM, ~170 Mo
chacune ; clone complet : ~40 s pour une VM, 2,3 Go. À nettoyer sur un
clone à plat : `machine-id` (`/etc/machine-id` et
`/var/lib/dbus/machine-id`), clés d'hôte SSH, identité cloud-init
(`instance-id`, sinon per-instance ne rejoue pas et le Netplan reste épinglé
à l'ancien MAC), MAC de la carte (virt-clone le fait), UUID du domaine
(virt-clone le fait), et les baux DHCP/logs.

::: pourquoi
Un pool `dir`, c'est un répertoire que libvirt **surveille et administre** :
il le crée (`pool-build`, mode `0711` : traversable, non listable), y crée
les fichiers avec les bons propriétaires, et sait les inventorier
(`pool-refresh` relit le répertoire après un `cp` fait derrière son dos).
Les autres types (`logical` = un VG LVM dont chaque volume est un LV,
`netfs` = un export NFS monté par libvirt, `iscsi`, `rbd`) exposent la même
interface `vol-*` : un script qui parle en volumes fonctionne sur les
quatre. C'est ce que fait Proxmox avec ses *storages* (`pvesm`).

Le backing file est ce qui rend les trois VM quasi gratuites : la base est
ouverte en **lecture seule et partagée** par trois processus QEMU, et le
cache de pages de l'hôte ne la charge qu'une fois. Le coût réel est la
lecture qcow2 traversant deux couches. `virt-clone`, à l'inverse, appelle
`virStorageVolCreateXMLFrom` : libvirt lance `qemu-img convert` sur la
chaîne, ce qui **aplatit** : le fichier résultant n'a plus de backing file,
il contient tout, d'où 2,3 Go et 40 s. C'est le bon choix pour une VM qui
doit survivre à la suppression de la base, ou partir sur un autre hôte.

`blockresize` agit sur la VM en marche : QEMU agrandit l'image
(`block_resize` QMP, équivalent d'un `qemu-img resize` mais sur un fichier
ouvert) et notifie l'invité, dont le noyau voit la nouvelle capacité
(`lsblk`). Ensuite c'est le module 11 : la table de partitions (`growpart`)
puis le FS (`resize2fs`, en ligne pour ext4). Proxmox : `qm disk resize`,
puis la même chose dans l'invité (cloud-init `growpart` ne rejoue qu'au
premier boot).

`virt-sysprep` monte l'image **hors ligne** (libguestfs lance un mini-QEMU
pour ça, d'où `sudo` pour lire le noyau de l'hôte) et retire ce qui rend
une machine unique. Sans le seed neuf, cloud-init trouverait le même
`instance-id` que `clone-1` et ne rejouerait rien : hostname de sysprep
conservé, mais Netplan épinglé sur l'ancien MAC (`match: macaddress`), donc
pas de réseau.
:::

::: piege
`undefine --remove-all-storage` supprime **tous** les volumes référencés,
ISO comprises. Si plusieurs VM partagent une ISO d'installation dans un
pool, elle disparaît avec la première VM supprimée. `--storage vda` cible
un disque précis. Et `virsh undefine` sans option sur une VM avec des
snapshots internes échoue : `--snapshots-metadata`.
:::

---

### **L20.4** — *Snapshot interne, snapshot externe cohérent, sauvegarde à chaud, restauration prouvée, managedsave.*

**Étape 1 — données et écriture continue**

```bash
IP=$(virsh domifaddr vm-01 | awk '/ipv4/{print $4}' | cut -d/ -f1)
ssh mathieu@$IP 'sudo mkdir -p /srv/data && sudo chown mathieu /srv/data
  date > /srv/data/avant.txt
  nohup bash -c "while true; do date >> /srv/data/journal.log; sleep 1; done" \
    >/dev/null 2>&1 &'
```

**Étape 2 — snapshot interne**

```bash
time virsh snapshot-create-as vm-01 interne        # real 0m6.4s (VM en pause)
virsh snapshot-list vm-01
#  Name     Creation Time              State
#  interne  2026-09-19 11:02:14 +0200  running
sudo qemu-img snapshot -l -U /var/lib/libvirt/images/vm-01.qcow2
# ID  TAG      VM SIZE  DATE                 VM CLOCK      ICOUNT
# 1   interne  312 MiB  2026-09-19 11:02:14  00:41:12.331
virsh vol-info --pool default vm-01.qcow2      # Allocation +~320 Mo
ssh mathieu@$IP 'date > /srv/data/pendant.txt; wc -l /srv/data/journal.log'
virsh snapshot-revert vm-01 interne
ssh mathieu@$IP 'ls /srv/data; wc -l /srv/data/journal.log; sleep 3; \
  wc -l /srv/data/journal.log'
# avant.txt journal.log   (pendant.txt a disparu)
# journal.log ramené au nombre de lignes de 11:02:14, et il RECOMMENCE à grandir
virsh snapshot-delete vm-01 interne
```

La boucle `while` a été restaurée avec la RAM : elle continue d'écrire.
Un snapshot interne d'une VM en marche est une **photo complète**, disque
et mémoire ; `revert` remet la machine exactement dans cet état.

**Étape 3 — snapshot externe cohérent**

```bash
time virsh snapshot-create-as vm-01 sauv --disk-only --atomic --quiesce \
  --no-metadata \
  --diskspec vda,snapshot=external,file=/var/lib/libvirt/images/vm-01.sauv \
  --diskspec sda,snapshot=no
# Domain snapshot sauv created      real 0m0.6s
virsh domblklist vm-01             # vda  /var/lib/libvirt/images/vm-01.sauv
sudo qemu-img info -U --backing-chain /var/lib/libvirt/images/vm-01.sauv \
  | grep -E '^image|backing file:'
# image: /var/lib/libvirt/images/vm-01.sauv
# backing file: /var/lib/libvirt/images/vm-01.qcow2
# image: /var/lib/libvirt/images/vm-01.qcow2
# backing file: /var/lib/libvirt/images/ubuntu-24.04-base.qcow2
# image: /var/lib/libvirt/images/ubuntu-24.04-base.qcow2
virsh snapshot-list vm-01           # vide (--no-metadata)
# preuve du gel :
virsh domfsfreeze vm-01 ; sleep 5 ; virsh domfsthaw vm-01
ssh mathieu@$IP 'tail -8 /srv/data/journal.log'   # trou de 5 s, puis reprise
```

**Étape 4 — la sauvegarde autoportante**

```bash
mkdir -p ~/lab20/backups
S=~/lab20/backups/vm-01-$(date +%F-%H%M).qcow2
time sudo qemu-img convert -p -U -O qcow2 \
  /var/lib/libvirt/images/vm-01.qcow2 "$S"          # ~25 s
sudo chown mathieu: "$S"
qemu-img info "$S" | grep -E 'backing|virtual|disk size'
# virtual size: 20 GiB   disk size: 2.29 GiB   (pas de ligne backing file)
```

**Étape 5 — refermer**

```bash
virsh blockcommit vm-01 vda --active --pivot --verbose
# Block commit: [100 %]
# Successfully pivoted
virsh domblklist vm-01              # vda  /var/lib/libvirt/images/vm-01.qcow2
sudo rm /var/lib/libvirt/images/vm-01.sauv ; virsh pool-refresh default
virsh dumpxml vm-01 --inactive > "${S%.qcow2}.xml"
ssh mathieu@$IP 'wc -l /srv/data/journal.log'     # continue de grandir
```

Le `dumpxml` vient **après** le pivot : pendant le snapshot, la définition
persistante pointait aussi sur `vm-01.sauv` (libvirt met à jour les deux),
et un XML sauvegardé à ce moment-là aurait référencé un fichier temporaire.

**Étape 6 — sinistre et restauration**

```bash
ssh mathieu@$IP 'sudo rm -rf /srv/data; sudo mkdir /srv/data; \
  sudo touch /srv/data/apres.txt'
virsh shutdown vm-01
while [ "$(virsh domstate vm-01)" != "shut off" ]; do sleep 1; done
sudo cp "$S" /var/lib/libvirt/images/vm-01-restaure.qcow2
virsh pool-refresh default
virt-xml vm-01 --edit target=vda \
  --disk path=/var/lib/libvirt/images/vm-01-restaure.qcow2
virsh start vm-01 ; sleep 30
ssh mathieu@$IP 'ls /srv/data; tail -1 /srv/data/journal.log'
# avant.txt journal.log  -> apres.txt absent, dernière ligne = heure du snapshot
```

Indisponibilité : le temps d'un arrêt propre + copie (déjà faite) +
démarrage, environ 60 s. La sauvegarde elle-même : 0 s d'arrêt, une pause
de quelques dizaines de ms pendant le gel.

**Étape 7 — `managedsave`**

```bash
ssh mathieu@$IP uptime
virsh managedsave vm-01              # Domain 'vm-01' state saved by libvirt
virsh list --all --managed-save      #  -  vm-01  saved
virsh domstate --reason vm-01        # shut off (saved)
sudo ls -lh /var/lib/libvirt/qemu/save/   # vm-01.save  ~ 400M-1G
virsh start vm-01                    # reprend, pas de boot
ssh mathieu@$IP uptime               # l'uptime a continué
```

Utile : libérer la RAM de l'hôte le temps d'une maintenance, ou survivre à
un redémarrage de l'hôte sans perdre l'état des VM (`libvirt-guests.service`
le fait à l'arrêt de l'hôte si `ON_SHUTDOWN=suspend`). Dangereux : modifier
le disque pendant que la VM est « sauvée » (restauration, `virt-sysprep`,
`qemu-img`) : la RAM restaurée ne correspond plus au disque, corruption
garantie ; et l'horloge de l'invité saute (l'agent la recale avec
`guest-set-time`). `virsh managedsave-remove vm-01` jette l'état pour
repartir sur un boot normal.

**Étape 8 — le tableau** (`sav-15.md`)

| Méthode | RAM incluse | VM en marche | Cohérence FS |
|---|---|---|---|
| interne (`snapshot-create-as`) | oui si VM allumée | oui (pause) | oui (RAM incluse) |
| externe `--disk-only --quiesce` | non | oui | oui (fsfreeze) |
| `qm snapshot` (LVM-thin) | option `--vmstate` | oui | avec agent (fsfreeze) |
| `vzdump --mode snapshot` | non | oui | avec agent |

Où sont les données : dans le qcow2 (interne), dans l'overlay puis la copie
(externe), dans un snapshot thin plus la section `[nom]` du `.conf`
(`qm snapshot`), dans une archive `.vma.zst` ou sur PBS (`vzdump`).

::: pourquoi
Un **snapshot n'est pas une sauvegarde** : il vit dans le même fichier (ou
sur le même stockage) que la VM ; si le disque de l'hôte meurt, snapshot et
VM meurent ensemble. Il sert à revenir en arrière vite (test d'une mise à
jour) ou à **figer** un instant pour le copier. C'est cette seconde
utilisation que fait la sauvegarde à chaud : le snapshot externe transforme
le fichier en cours en fichier immuable pendant quelques minutes, on le
copie en l'aplatissant, puis on referme.

`--quiesce` est ce qui distingue « cohérent comme après une coupure de
courant » (le journal ext4 rejouera, une base de données aura peut-être des
transactions perdues) de « cohérent comme après un `sync` propre » : l'agent
exécute `FIFREEZE` sur chaque FS monté, ce qui force l'écriture des
tampons et bloque tout `write()` jusqu'au `FITHAW`. L'étape 3 le rend
visible : cinq secondes de trou dans le journal. Les applications qui ont
un état en RAM (PostgreSQL) profitent en plus des *hooks* de `qemu-ga`
(`/etc/qemu/fsfreeze-hook.d/`) pour faire un `pg_start_backup` avant le gel.

`qemu-img convert` produit un fichier **autoportant** parce qu'il lit à
travers la chaîne (base + overlay) et écrit chaque cluster non nul : la
sauvegarde ne dépend plus de la base, elle est restaurable sur un hôte qui
ne l'a jamais eue. C'est aussi plus gros (2,3 Go contre 300 Mo d'overlay) :
c'est le prix de l'indépendance, et c'est ce que `vzdump` fait aussi (une
archive contenant tout le disque, en mode *snapshot* grâce au *backup job*
de QEMU qui lit les blocs avant qu'ils ne soient réécrits).

La restauration prouve la sauvegarde : tant qu'on n'a pas redémarré sur la
copie et vu `avant.txt`, on n'a rien prouvé. `virt-xml --edit target=vda
--disk path=` modifie seulement `<source file>` : le reste du XML (UUID,
MAC, agent) est conservé, la VM garde son identité réseau.
:::

::: piege
`qemu-img info` sans `-U` sur un fichier ouvert par QEMU répond `Failed to
get shared "write" lock. Is another process using the image?` : le
verrouillage d'image de QEMU (≥ 2.10) protège contre deux écrivains ;
`-U`/`--force-share` lit sans prendre le verrou. `qemu-img convert` sans
`-U` sur `vm-01.qcow2` pendant le snapshot passe parfois (QEMU le tient en
lecture seule comme backing) : mets `-U` par principe. Autre piège :
oublier `--diskspec sda,snapshot=no` fait échouer sur certaines versions
(`disk 'sda' is readonly`) ; et sans `--no-metadata`, `snapshot-delete`
d'un externe reste délicat sur les versions < 9.0.
:::

---

### **L20.5** — *`usine-vm.sh` : une commande, une VM, idempotente.*

```bash
#!/usr/bin/env bash
# usine-vm.sh — une commande, une VM libvirt prête (image cloud + cloud-init)
# Usage : usine-vm.sh --name NOM [--ram MO] [--vcpus N] [--key CLE.pub]
#         [--net network=default|bridge=br0] [--ip A.B.C.D/24] [--disk GO]
#         [--pool POOL]        crée (ou ne fait rien si la VM existe)
#         usine-vm.sh --name NOM --delete     détruit VM, disque, seed
set -euo pipefail
export LIBVIRT_DEFAULT_URI="${LIBVIRT_DEFAULT_URI:-qemu:///system}"

NAME="" RAM=1024 VCPUS=1 KEY="$HOME/.ssh/id_ed25519.pub" NET="network=default"
IP="" DISK=20 POOL=default DELETE=0
BASE=ubuntu-24.04-base.qcow2 GW=10.10.10.1 DNS=10.10.10.1 DOMAIN=lab.local
SEEDS="$HOME/lab20/cloud-init"

log() { printf '%s %s\n' "$(date +%T)" "$*" >&2; }
die() { log "ERREUR : $1"; exit "${2:-1}"; }
usage() { sed -n '2,6p' "$0" >&2; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --name)   NAME=${2:?}; shift 2 ;;    --ram)    RAM=${2:?}; shift 2 ;;
    --vcpus)  VCPUS=${2:?}; shift 2 ;;   --key)    KEY=${2:?}; shift 2 ;;
    --net)    NET=${2:?}; shift 2 ;;     --ip)     IP=${2:?}; shift 2 ;;
    --disk)   DISK=${2:?}; shift 2 ;;    --pool)   POOL=${2:?}; shift 2 ;;
    --delete) DELETE=1; shift ;;         -h|--help) usage 0 ;;
    *) log "option inconnue : $1"; usage 2 ;;
  esac
done
[[ $NAME =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]] || die "nom invalide : '$NAME'" 2

# --- suppression --------------------------------------------------------
if [ "$DELETE" -eq 1 ]; then
  if virsh dominfo "$NAME" >/dev/null 2>&1; then
    [ "$(virsh domstate "$NAME")" = "shut off" ] || virsh destroy "$NAME" >&2
    virsh undefine "$NAME" --managed-save --snapshots-metadata >&2
  fi
  for v in "$NAME.qcow2" "$NAME-seed.iso"; do
    if virsh vol-info --pool "$POOL" "$v" >/dev/null 2>&1; then
      virsh vol-delete --pool "$POOL" "$v" >&2
    fi
  done
  rm -rf "${SEEDS:?}/$NAME"
  log "$NAME supprimée (domaine, volumes, seed)"; exit 0
fi

# --- idempotence --------------------------------------------------------
if virsh dominfo "$NAME" >/dev/null 2>&1; then
  st=$(virsh domstate "$NAME")
  ip=$(virsh domifaddr "$NAME" --source agent 2>/dev/null \
       | awk '/ipv4/ && !/127\./{print $4; exit}' || true)
  echo "$NAME existe déjà : $st${ip:+ ($ip)}"; exit 0
fi

# --- contrôles ----------------------------------------------------------
[ -r "$KEY" ] || die "clé publique illisible : $KEY" 2
case "$NET" in
  network=*|bridge=*) ;;
  *) die "--net attend network=X ou bridge=X" 2 ;;
esac
if [[ $NET == bridge=* && -z $IP ]]; then
  die "--ip obligatoire avec un bridge" 2
fi
virsh vol-info --pool "$POOL" "$BASE" >/dev/null 2>&1 \
  || die "base $BASE absente du pool $POOL (setup_M20.sh)" 2
for v in "$NAME.qcow2" "$NAME-seed.iso"; do
  if virsh vol-info --pool "$POOL" "$v" >/dev/null 2>&1; then
    die "volume orphelin $v dans $POOL : $0 --name $NAME --delete d'abord" 3
  fi
done
if virt-install --osinfo list 2>/dev/null | grep -x ubuntu24.04 >/dev/null; then
  OSINFO=ubuntu24.04; else OSINFO=ubuntu22.04; fi

# --- seed ---------------------------------------------------------------
D="$SEEDS/$NAME"; mkdir -p "$D"
{
  printf '#cloud-config\nhostname: %s\nfqdn: %s.%s\nmanage_etc_hosts: true\n' \
    "$NAME" "$NAME" "$DOMAIN"
  printf 'users:\n  - name: mathieu\n    groups: [sudo]\n    shell: /bin/bash\n'
  printf '    sudo: "ALL=(ALL) NOPASSWD:ALL"\n    lock_passwd: true\n'
  printf '    ssh_authorized_keys:\n'
  grep -v '^[[:space:]]*$' "$KEY" | sed 's/^/      - /'
  printf 'packages: [qemu-guest-agent]\nruncmd:\n'
  printf '  - systemctl enable --now qemu-guest-agent\n'
} > "$D/user-data"
printf 'instance-id: %s\nlocal-hostname: %s\n' "$(uuidgen)" "$NAME" \
  > "$D/meta-data"
NETCFG=()
if [ -n "$IP" ]; then
  cat > "$D/network-config" <<EOF
version: 2
ethernets:
  id0:
    match: {name: "en*"}
    dhcp4: false
    addresses: [$IP]
    routes: [{to: default, via: $GW}]
    nameservers: {addresses: [$DNS], search: [$DOMAIN]}
EOF
  NETCFG=(-N "$D/network-config")
fi
log "seed cloud-init dans $D"
cloud-localds "${NETCFG[@]}" "$D/seed.iso" "$D/user-data" "$D/meta-data"

# --- volumes et VM ------------------------------------------------------
log "volume $NAME.qcow2 (${DISK}G, base $BASE)"
virsh vol-create-as "$POOL" "$NAME.qcow2" "${DISK}G" --format qcow2 \
  --backing-vol "$BASE" --backing-vol-format qcow2 >&2
virsh vol-create-as "$POOL" "$NAME-seed.iso" "$(stat -c %s "$D/seed.iso")" \
  --format raw >&2
virsh vol-upload --pool "$POOL" "$NAME-seed.iso" "$D/seed.iso"
log "virt-install ($RAM Mo, $VCPUS vCPU, $NET)"
virt-install --name "$NAME" --memory "$RAM" --vcpus "$VCPUS" \
  --cpu host-passthrough --osinfo "$OSINFO" --import \
  --disk "vol=$POOL/$NAME.qcow2,bus=virtio,discard=unmap" \
  --disk "vol=$POOL/$NAME-seed.iso,device=cdrom" \
  --network "$NET,model=virtio" --graphics none --noautoconsole >&2

# --- attente ------------------------------------------------------------
log "attente de l'adresse et du port 22 (180 s max)"
VMIP=""
for _ in $(seq 1 90); do
  if [ -n "$IP" ]; then VMIP=${IP%/*}
  else VMIP=$(virsh domifaddr "$NAME" 2>/dev/null \
              | awk '/ipv4/{print $4; exit}' | cut -d/ -f1); fi
  if [ -n "$VMIP" ] \
     && timeout 2 bash -c "exec 3<>/dev/tcp/$VMIP/22" 2>/dev/null; then
    log "prête : ssh mathieu@$VMIP"; echo "$VMIP"; exit 0
  fi
  sleep 2
done
die "pas de SSH après 180 s : virsh console $NAME" 4
```

Tests :

```bash
chmod +x ~/lab20/bin/usine-vm.sh
time ~/lab20/bin/usine-vm.sh --name usine-1            # ~50 s, affiche l'IP
time ~/lab20/bin/usine-vm.sh --name usine-1            # "existe déjà", 0.3 s
~/lab20/bin/usine-vm.sh --name usine-2 --net bridge=br0 --ip 10.10.10.162/24 \
  --ram 768
ssh mathieu@10.10.10.162 hostname                      # depuis lab-adm
~/lab20/bin/usine-vm.sh --name usine-2 --delete
virsh vol-list default | grep usine                    # usine-1 seulement
~/lab20/bin/usine-vm.sh --name usine-1 --delete
~/lab20/bin/usine-vm.sh --name usine-1
```

::: pourquoi
L'idempotence est une **décision de conception**, pas une option : le script
commence par regarder l'état du monde (`virsh dominfo`) et ne fait quelque
chose que si l'état voulu n'existe pas. Relancer un outil idempotent est
toujours sûr, ce qui permet de le mettre dans un `cron`, un pipeline ou un
playbook Ansible sans garde-fou externe. Le refus explicite sur un volume
orphelin est l'autre face : plutôt que « réparer » silencieusement (écraser
un disque qui contient peut-être des données), le script explique et
s'arrête, code 3, et l'humain tranche.

Tout passe par l'API libvirt (`vol-*`, `virt-install`) pour deux raisons :
pas de `sudo` — le compte est dans le groupe `libvirt`, c'est libvirt qui
écrit dans `/var/lib/libvirt/images` en root — et **portabilité** : remplace
`LIBVIRT_DEFAULT_URI` par `qemu+ssh://mathieu@10.10.10.16/system` et le
script tourne depuis `lab-adm` sans modification (sauf `cloud-localds`,
local, et `vol-upload` qui pousse le seed à travers la connexion).

L'attente sur le port 22 plutôt que sur `domifaddr` seul est ce qui rend
« prête » vrai : une adresse dans un bail ne dit pas que `sshd` est lancé ni
que cloud-init a posé la clé. Les codes de retour distincts (2 usage, 3
orphelin, 4 délai) permettent au `parc.sh` de D20 de réagir différemment.
Ce qui manque encore pour la production : un `trap` qui nettoie volumes et
domaine si `virt-install` échoue à mi-chemin, un verrou (`flock`) contre
deux lancements simultanés, et une option `--net2` pour la seconde carte —
c'est D20.
:::

---

## 20.7 Break & Fix

### **BF20.1** — *`vm-01` met quatre minutes à démarrer, QEMU à 100 %.*

**Diagnostic**

```bash
ps -o pid,%cpu,args -C qemu-system-x86_64 \
  | grep -o -- '-name guest=[^,]*\|-accel [a-z]*'
# -name guest=vm-01
# -accel tcg                          <- les autres VM : -accel kvm
virsh dumpxml vm-01 | head -1         # <domain type='qemu'>
virsh dumpxml vm-01 | grep '<cpu'     # <cpu mode='custom' ...><model>qemu64
sudo grep -m1 'starting up' /var/log/libvirt/qemu/vm-01.log ; ls -l /dev/kvm
```

**Cause racine** : la définition de `vm-01` a été passée en
`<domain type='qemu'>` (émulation TCG) et son CPU en `qemu64`, un modèle
générique. `/dev/kvm` est intact, `virsh domcapabilities --virttype kvm`
répond : ce n'est pas l'hôte, c'est **cette VM** qui n'utilise plus
l'accélérateur.

**Correctif**

```bash
virsh destroy vm-01
virsh edit vm-01
#   <domain type='kvm'>
#   <cpu mode='host-passthrough' check='none' migratable='on'/>
# (ou sans éditeur, en deux commandes virt-xml :)
virt-xml vm-01 --edit --xml ./@type=kvm
virt-xml vm-01 --edit --cpu host-passthrough
time (virsh start vm-01; until virsh qemu-agent-command vm-01 \
  '{"execute":"guest-ping"}' >/dev/null 2>&1; do sleep 1; done)   # ~25 s
ps -o args -C qemu-system-x86_64 | grep -o -- '-accel [a-z]*'    # kvm
```

::: pourquoi
`type='qemu'` change une seule chose dans la ligne de commande QEMU :
`-accel tcg` au lieu de `-accel kvm`. TCG traduit chaque bloc de code
invité en code hôte avant de l'exécuter : la VM **fonctionne** (c'est de
l'émulation correcte, c'est même ainsi qu'on fait tourner un ARM sur x86),
mais chaque instruction coûte des dizaines d'instructions hôte, et le
thread vCPU consomme un cœur entier en permanence. Un boot Ubuntu passe de
20 s à 4 min, `apt` prend des heures. Le passage à `qemu64` accompagne le
changement : `host-passthrough` est refusé sous TCG (`CPU mode
'host-passthrough' ... is not supported by hypervisor`), le collègue a donc
dû le remplacer pour que ça démarre — c'est un indice.

**Prévention** : le XML est la seule vérité ; toute modification passe par
`virsh edit` (validation) et un dépôt Git des XML (`virsh dumpxml
--inactive` versionné, D20). Un contrôle de conformité peut tourner en
cron : `for d in $(virsh list --name --all); do virsh dumpxml $d | head -1 |
grep -q "type='kvm'" || echo "$d en TCG"; done`. `virt-top` rend le
symptôme visible en un coup d'œil : une VM à 100 % qui ne fait rien.
:::

---

### **BF20.2** — *`vm-lan` ne démarre plus : MTU et périphérique introuvable.*

**Diagnostic**

```bash
virsh start vm-lan
# error: Failed to start domain 'vm-lan'
# error: Cannot get interface MTU on 'br0': No such device
virsh domiflist vm-lan            # bridge  br0  virtio
ip -br link show br0              # Device "br0" does not exist.
ip -br addr show eth0             # eth0  UP  10.10.10.16/24
ls /etc/netplan/ ; sudo cat /etc/netplan/*.yaml
# 60-br0.yaml a disparu, 50-cloud-init.yaml porte à nouveau l'adresse sur eth0
sudo ls /root/.breakfix-backup/    # (indice : la conf précédente y est)
```

**Cause racine** : le Netplan de `lab-virt` a été réécrit sans le bridge :
`eth0` a repris l'adresse, `br0` n'existe plus. `lab-virt` communique
parfaitement — une adresse sur `eth0` suffit à l'hôte — mais `vm-lan`
demande à libvirt de brancher son `tap` sur un bridge nommé `br0`, et
libvirt échoue au premier `ioctl` dessus (la lecture de son MTU).

**Correctif**

```bash
MAC=$(cat /sys/class/net/eth0/address)
sudo tee /etc/netplan/50-cloud-init.yaml <<EOF
network:
  version: 2
  ethernets:
    eth0:
      match: {macaddress: $MAC}
      set-name: eth0
      dhcp4: false
EOF
sudo tee /etc/netplan/60-br0.yaml <<'EOF'
network:
  version: 2
  bridges:
    br0:
      interfaces: [eth0]
      addresses: [10.10.10.16/24]
      routes: [{to: default, via: 10.10.10.1}]
      nameservers: {addresses: [10.10.10.1], search: [lab.local]}
EOF
sudo chmod 600 /etc/netplan/*.yaml
sudo netplan try                  # confirmer ; qm terminal 9007 en secours
ip -br addr show br0 ; bridge link
virsh start vm-lan ; sleep 30
ssh mathieu@10.10.10.161 hostname        # depuis lab-adm
```

::: pourquoi
Une VM en mode bridge n'a **aucune existence réseau propre** côté hôte :
elle dépend d'un objet que libvirt ne gère pas. Au démarrage, libvirt crée
un `tap` (`vnetN`), le passe à QEMU par descripteur de fichier, et exécute
l'équivalent de `ip link set vnetN master br0` après avoir lu le MTU de
`br0` pour l'appliquer au `tap` : d'où le message, qui est le premier accès
au bridge. Le réseau `default`, lui, est autonome : libvirt crée `virbr0`
lui-même à `net-start`, ce qui explique que `vm-01` démarre.

Le piège de l'exercice est la tentation de « réparer » en rattachant la VM
à `default` : ça démarre, mais la VM change de réseau, perd son adresse
`10.10.10.161`, et l'équipe ne la joint plus — on a déplacé le problème.
La règle : quand une VM ne démarre pas à cause d'une ressource hôte
(bridge, fichier, pool), on répare la ressource, pas la VM.

**Prévention** : versionner `/etc/netplan/` (Git, ou au moins un
`etckeeper`), et un test dans `lab-status.sh`-like : `for b in $(virsh
net-dumpxml lan | xmllint --xpath 'string(//bridge/@name)' -); do ip link
show $b >/dev/null || echo "bridge $b manquant"; done`. `netplan try`
systématiquement sur une machine distante. Sur Proxmox, la même panne
s'appelle `bridge 'vmbr1' does not exist` au `qm start`.
:::

---

### **BF20.3** — *`clone-1` refuse de démarrer : backing file introuvable.*

**Diagnostic**

```bash
virsh start clone-1
# error: Failed to start domain 'clone-1'
# error: Cannot access backing file '/srv/vm/ubuntu-24.04-base.qcow2' of
# storage file '/srv/vm/clone-1.qcow2' (as uid:64055, gid:108):
# No such file or directory
virsh domblklist clone-1                 # vda  /srv/vm/clone-1.qcow2  (existe)
sudo qemu-img info /srv/vm/clone-1.qcow2 | grep backing
# backing file: /srv/vm/ubuntu-24.04-base.qcow2
sudo find /srv /var/lib/libvirt -name 'ubuntu-24.04-base.qcow2'
# /srv/vm/archive/ubuntu-24.04-base.qcow2     <- le « rangement »
# /var/lib/libvirt/images/ubuntu-24.04-base.qcow2
sudo sha256sum /srv/vm/archive/ubuntu-24.04-base.qcow2 \
  /var/lib/libvirt/images/ubuntu-24.04-base.qcow2      # identiques
```

**Cause racine** : le disque de `clone-1` est un **overlay** ; il ne
contient que les clusters écrits depuis la création, et son en-tête pointe
vers `/srv/vm/ubuntu-24.04-base.qcow2`, déplacé dans `archive/`. Ce chemin
n'apparaît nulle part dans le XML de libvirt : libvirt le découvre en
ouvrant le qcow2 (c'est le `backingStore` de `dumpxml` sur une VM en
marche), et QEMU en a besoin pour lire tout ce que l'overlay ne contient
pas — c'est-à-dire le système entier.

**Correctif** (sans redéplacer le fichier, comme exigé)

```bash
for f in /srv/vm/clone-*.qcow2; do
  if sudo qemu-img info "$f" | grep -q 'backing file: /srv/vm/ubuntu'; then
    sudo qemu-img rebase -u -F qcow2 \
      -b /srv/vm/archive/ubuntu-24.04-base.qcow2 "$f"
  fi
done
sudo qemu-img info --backing-chain /srv/vm/clone-1.qcow2 | grep -E '^image'
virsh pool-refresh lab20 ; virsh start clone-1
# la base archivée doit rester lisible et immuable :
sudo chmod 0444 /srv/vm/archive/ubuntu-24.04-base.qcow2
```

::: pourquoi
`rebase -u` réécrit uniquement le champ « backing file » de l'en-tête qcow2,
sans lire une donnée : c'est instantané et sûr **si et seulement si** le
nouveau fichier est bit à bit celui d'avant (d'où le `sha256sum`). Sans
`-u`, `rebase` compare ancienne et nouvelle base cluster par cluster et
copie dans l'overlay ce qui diffère : c'est l'outil pour *changer* de base
(par exemple vers une image mise à jour), long mais qui préserve le
contenu vu par l'invité.

`clone-4`, s'il a été gardé, n'est pas touché : `virt-clone` l'a aplati, il
n'a pas de backing file, et démarre : c'est la contrepartie des 2,3 Go.

La leçon d'exploitation : une chaîne qcow2 est une **dépendance
invisible**. `virsh` ne la montre que sur une VM allumée ; `qemu-img info
--backing-chain` est la seule commande qui la liste à froid, et elle doit
faire partie de toute procédure de déplacement, renommage ou archivage
(`find /srv/vm -name '*.qcow2' -exec qemu-img info --backing-chain {} \; |
grep 'backing file'`). Deux protections : des chemins **relatifs** dans
les overlays (`qemu-img create -b ubuntu-24.04-base.qcow2` depuis le
répertoire du pool : la chaîne survit à un déplacement du répertoire
entier), et un nom de base explicite avec `chmod 0444` pour que personne ne
la « range » sans réfléchir. Proxmox contourne le problème en n'utilisant
pas de backing file (les *linked clones* existent, mais sur des stockages
qui gèrent la relation : qcow2 `base-<id>-disk-0`, ZFS, LVM-thin).
:::

---

### **BF20.4** — *`import-1` : `Permission denied` sur `/root/import/import-1.qcow2`.*

**Diagnostic**

```bash
virsh start import-1
# error: Failed to start domain 'import-1'
# error: Cannot access storage file '/root/import/import-1.qcow2'
#   (as uid:64055, gid:108): Permission denied
grep -E '^(user|group|dynamic_ownership)' /etc/libvirt/qemu.conf
ps -o user -C qemu-system-x86_64 | sort -u          # libvirt+
sudo namei -l /root/import/import-1.qcow2
# drwx------ root root root
# drwxr-xr-x root root import
# -rw------- root root import-1.qcow2
sudo -u libvirt-qemu cat /root/import/import-1.qcow2 >/dev/null
# cat: /root/import/import-1.qcow2: Permission denied
```

**Cause racine** : le processus QEMU ne tourne pas en root mais sous
`libvirt-qemu:kvm` ; `/root` est `0700` et ne se traverse pas. libvirt
(root) a bien fait son travail (il change même le propriétaire du fichier
au démarrage grâce à `dynamic_ownership = 1`), mais l'`open()` est fait par
QEMU : libvirt le vérifie d'avance **sous l'identité de QEMU** (`as uid:64055`), et le noyau refuse à la traversée de `/root`. AppArmor n'a rien
refusé (`journalctl -k | grep DENIED` est vide) : le DAC a tranché avant.

**Correctif**

```bash
sudo mv /root/import/import-1.qcow2 /var/lib/libvirt/images/import-1.qcow2
sudo mv /root/import/import-1-seed.iso /var/lib/libvirt/images/
virsh pool-refresh default
virt-xml import-1 --edit target=vda \
  --disk path=/var/lib/libvirt/images/import-1.qcow2
virt-xml import-1 --edit target=sda \
  --disk path=/var/lib/libvirt/images/import-1-seed.iso
virsh start import-1
UUID=$(virsh domuuid import-1)
sudo cat /etc/apparmor.d/libvirt/libvirt-$UUID.files | grep -E 'images/import-1'
#   "/var/lib/libvirt/images/import-1.qcow2" rwk,
#   "/var/lib/libvirt/images/ubuntu-24.04-base.qcow2" rk,
sudo aa-status | grep "libvirt-$UUID"          # profil en mode enforce
ps -o pid,label,args -C qemu-system-x86_64 | grep import-1 | cut -c1-80
```

::: pourquoi
C'est l'illustration de **sVirt** : libvirt ne se contente pas de lancer
QEMU sous un compte non privilégié, il construit pour chaque VM un
confinement dédié. Sur Ubuntu, `virt-aa-helper` génère au démarrage un
profil AppArmor `libvirt-<uuid>` (dans `/etc/apparmor.d/libvirt/`) qui
n'autorise que les fichiers du XML : le disque en `rwk` (lecture, écriture,
verrou), les backing files en `rk`, le cdrom en `r`, les sockets de
l'agent et du monitor, `/dev/kvm`, `/dev/net/tun`. Tout le reste est
refusé, quel que soit le DAC. Sur Rocky, c'est SELinux : QEMU tourne en
`svirt_t` avec une paire de catégories MCS unique (`s0:c123,c456`) et les
images reçoivent le label `svirt_image_t` avec les mêmes catégories le
temps de l'exécution ; deux VM ne peuvent pas lire leurs disques
mutuellement même si elles sont sous le même compte `qemu`.

Ici les deux couches disaient non : le DAC (traversée de `/root`) en
premier. `chmod o+x /root` aurait « marché » et transformé `/root` en
répertoire traversable par tous : c'est exactement le genre de correctif qui
finit dans un rapport d'audit. Le répertoire d'un pool (`0711`) est conçu
pour ça : traversable, non listable, fichiers chownés à la volée.

**Prévention** : une VM s'importe dans un pool (`virsh vol-upload`, ou copie
puis `pool-refresh`), et un XML importé se relit avant `define` : chaque
`<source file>` doit être dans un pool. `virt-v2v`/`virt-p2v` sont les
outils pour importer depuis VMware/Hyper-V avec conversion des pilotes en
virtio, et ils écrivent directement dans un pool.
:::

---

### **BF20.5** — *Le disque de `lab-virt` se remplit ; `snapshot-list` est vide.*

**Diagnostic**

```bash
df -h / ; sudo du -sh /var/lib/libvirt/images
sudo ls -la /var/lib/libvirt/images/        # -a : .vm-01.tmp-overlay (caché !)
O=/var/lib/libvirt/images/.vm-01.tmp-overlay
sudo du -h $O ; sleep 30 ; sudo du -h $O            # ça grossit
virsh domblklist vm-01
#  vda   /var/lib/libvirt/images/.vm-01.tmp-overlay
sudo qemu-img info -U --backing-chain $O | grep -E '^image|backing file:'
# image: .../.vm-01.tmp-overlay -> backing: .../vm-01.qcow2 -> .../base
virsh snapshot-list vm-01                 # vide
sudo lsof $O | head -2                    # qemu-syst PID ... (QEMU le tient)
virsh blockjob vm-01 vda --info           # No current block job
IP=$(virsh domifaddr vm-01 | awk '/ipv4/{print $4}' | cut -d/ -f1)
ssh mathieu@$IP 'sudo du -sh /var/tmp/* 2>/dev/null | sort -h | tail -2'
```

**Cause racine** : quelqu'un a pris un snapshot externe de `vm-01` avec
`--no-metadata` (libvirt n'en garde donc **aucune trace** dans
`snapshot-list`) vers un fichier caché, et n'a jamais fait le
`blockcommit`. Depuis, toutes les écritures de la VM vont dans cet overlay
orphelin. `vm-01.qcow2` est figé, et un processus dans l'invité a écrit un
gros fichier dans `/var/tmp`, qui grossit l'overlay côté hôte.

**Correctif à chaud, sans perte**

```bash
virsh blockcommit vm-01 vda --active --pivot --verbose # fusion dans vm-01.qcow2
virsh domblklist vm-01                                   # vda vm-01.qcow2
sudo lsof $O                                             # plus personne
sudo rm $O
ssh mathieu@$IP 'sudo rm -f /var/tmp/fill*; sudo fstrim -v /'
# /: 1.5 GiB (1610612736 bytes) trimmed
sudo du -h /var/lib/libvirt/images/vm-01.qcow2 ; df -h /
```

La commande qui aurait évité l'orphelin, si le but était une sauvegarde :

```bash
I=/var/lib/libvirt/images
virsh snapshot-create-as vm-01 sauv --disk-only --atomic --quiesce \
  --no-metadata --diskspec vda,snapshot=external,file=$I/vm-01.sauv \
&& sudo qemu-img convert -U -O qcow2 $I/vm-01.qcow2 /backup/vm-01.qcow2 \
;  virsh blockcommit vm-01 vda --active --pivot && sudo rm $I/vm-01.sauv
```

(en une seule séquence, avec le `blockcommit` **toujours** exécuté, même si
la copie échoue : c'est le `trap` de `sauvegarde-vm.sh` en D20).

::: pourquoi
Deux mécanismes s'additionnent. Le premier : un overlay externe reçoit
**toutes** les écritures ; il grossit du volume écrit par l'invité, même si
l'invité réécrit les mêmes fichiers (les clusters sont alloués une fois par
cluster de 64 Ko touché) ; l'ancien fichier, lui, ne bouge plus. Sans le
`blockcommit`, on a créé sans le savoir une seconde copie vivante du disque
qui ne fera que grossir. Le second : un qcow2 ne rend jamais d'espace de
lui-même. Supprimer `/var/tmp/fill` dans l'invité libère des blocs pour
l'invité, mais l'hôte ne le sait pas ; c'est `fstrim` (grâce à
`discard='unmap'` posé en L20.1) qui envoie les `UNMAP`, que QEMU traduit en
`fallocate(PUNCH_HOLE)` : `du` redescend. Sans `discard`, il faudrait
`qemu-img convert` (à froid) pour compacter.

`--no-metadata` est utile pour les sauvegardes scriptées (pas de fiche à
nettoyer), mais c'est ce qui rend l'orphelin **invisible** à `virsh
snapshot-list`. La seule vérité est `virsh domblklist` + `qemu-img info
--backing-chain` : une VM dont le disque actif n'est pas le fichier « de
référence » est en situation anormale. `lsof` prouve qui tient le fichier
avant tout `rm` : supprimer un overlay actif ne casse pas la VM tout de suite
(QEMU garde le descripteur, l'espace n'est même pas libéré), mais au
prochain arrêt, tout ce qui a été écrit depuis le snapshot est perdu.

**Prévention** : un contrôle périodique `for d in $(virsh list --name); do
virsh domblklist $d | awk '$1=="vda" && $2 !~ /\/'$d'\.qcow2$/'; done`, une
alerte sur l'espace du pool (module 16), et la règle « un snapshot
externe est toujours suivi de son blockcommit dans le même script ».
:::

---

## 20.8 Défi du module

**D20** — *Mini-plateforme : parc décrit dans un fichier, réseaux front/back, sauvegarde tournante, restauration, inventaire, comparaison Proxmox.*

### `parc.txt`

```text
# nom    ram_mo  vcpus  reseaux     ip
p-web    1024    1      lan+isole   10.10.10.170/24
p-app    1024    1      lan+isole   10.10.10.171/24
p-db     1024    1      isole       -
```

### Extension de `usine-vm.sh`

Deux options ajoutées : `--net2 network=isole` (seconde carte, persistante,
avec un `network-config` qui la met en DHCP sans route par défaut) et, quand
`--net` vaut `network=isole` seul, une attente de l'IP par
`virsh domifaddr --source lease` sur ce réseau. Le `network-config` généré
pour deux cartes :

```yaml
version: 2
ethernets:
  front:
    match: {macaddress: "MAC1"}
    set-name: front
    dhcp4: false
    addresses: [10.10.10.170/24]
    routes: [{to: default, via: 10.10.10.1}]
    nameservers: {addresses: [10.10.10.1], search: [lab.local]}
  back:
    match: {macaddress: "MAC2"}
    set-name: back
    dhcp4: true
    dhcp4-overrides: {use-routes: false, use-dns: false}
```

Les MAC sont générés **avant** `virt-install` (`printf '52:54:00:%02x:%02x:%02x'
$((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256))`) et passés avec
`--network network=lan,model=virtio,mac=MAC1 --network network=isole,model=virtio,mac=MAC2`,
ce qui permet au seed de nommer les cartes de façon fiable, quelle que soit
l'énumération PCI.

### `bin/parc.sh`

```bash
#!/usr/bin/env bash
# parc.sh apply|status|destroy parc.txt
set -euo pipefail
export LIBVIRT_DEFAULT_URI=qemu:///system
ACTION=${1:?apply|status|destroy} FICHIER=${2:?parc.txt}
USINE="$(dirname "$0")/usine-vm.sh"
lire() { grep -vE '^\s*(#|$)' "$FICHIER"; }
ip_agent() {  # ip_agent vm reseau -> IP de la carte branchée sur ce réseau
  local mac
  mac=$(virsh domiflist "$1" | awk -v r="$2" '$3==r{print $5}')
  [ -n "$mac" ] || return 0
  virsh domifaddr "$1" --source agent 2>/dev/null \
    | awk -v m="$mac" '$2==m && /ipv4/{print $4}' | head -1
}
case "$ACTION" in
  apply)
    lire | while read -r nom ram vcpus reseaux ip; do
      args=(--name "$nom" --ram "$ram" --vcpus "$vcpus")
      case "$reseaux" in
        lan+isole) args+=(--net network=lan --ip "$ip" --net2 network=isole) ;;
        lan)       args=("${args[@]}" --net network=lan --ip "$ip") ;;
        isole)     args+=(--net network=isole) ;;
        *) echo "réseau inconnu : $reseaux" >&2; exit 2 ;;
      esac
      "$USINE" "${args[@]}"
    done ;;
  status)
    printf '%-8s %-9s %-16s %-16s %s\n' VM ETAT LAN ISOLE DISQUE
    lire | while read -r nom _; do
      if ! virsh dominfo "$nom" >/dev/null 2>&1; then
        printf '%-8s %s\n' "$nom" ABSENTE; continue; fi
      alloc=$(virsh vol-info --pool default "$nom.qcow2" \
              | awk -F': *' '/Allocation/{print $2}')
      printf '%-8s %-9s %-16s %-16s %s\n' "$nom" "$(virsh domstate "$nom")" \
        "$(ip_agent "$nom" lan)" "$(ip_agent "$nom" isole)" "$alloc"
    done ;;
  destroy)
    lire | while read -r nom _; do "$USINE" --name "$nom" --delete; done ;;
  *) echo "usage: $0 apply|status|destroy parc.txt" >&2; exit 2 ;;
esac
```

### `bin/sauvegarde-vm.sh`

```bash
#!/usr/bin/env bash
# sauvegarde-vm.sh NOM — sauvegarde à chaud, autoportante, rotation 3
set -euo pipefail
export LIBVIRT_DEFAULT_URI=qemu:///system
VM=${1:?nom de VM} ; POOL_DIR=/var/lib/libvirt/images
DEST="$HOME/lab20/backups/$VM" ; LOG="$HOME/lab20/backups/sauvegarde.log"
mkdir -p "$DEST"
log() { printf '%s %s %s\n' "$(date '+%F %T')" "$VM" "$*" | tee -a "$LOG" >&2; }
if [ "$(virsh domstate "$VM")" != running ]; then
  log "VM éteinte : refus (copie à froid : cp du disque, à documenter)"; exit 2
fi
DISK=$(virsh domblklist "$VM" | awk '$1=="vda"{print $2}')
if [[ $DISK != *.qcow2 ]]; then
  log "disque actif inattendu : $DISK (chaîne déjà ouverte ?)"; exit 3
fi
OVER="$DISK.sauv"
refermer() {
  if virsh domblklist "$VM" | grep -q "$OVER"; then
    if ! virsh blockcommit "$VM" vda --active --pivot >/dev/null; then
      log "ÉCHEC blockcommit : $OVER est le disque actif, conservé"; return 1
    fi
    log "blockcommit ok"
  fi
  sudo rm -f "$OVER"
}
trap refermer EXIT
T0=$(date +%s)
virsh snapshot-create-as "$VM" sauv --disk-only --atomic --quiesce \
  --no-metadata --diskspec "vda,snapshot=external,file=$OVER" \
  --diskspec sda,snapshot=no >/dev/null
log "snapshot externe créé (gel $(( $(date +%s) - T0 )) s)"
OUT="$DEST/$VM-$(date +%F-%H%M%S).qcow2"
sudo qemu-img convert -U -O qcow2 "$DISK" "$OUT" && sudo chown "$USER": "$OUT"
virsh dumpxml --inactive "$VM" | sed "s#$OVER#$DISK#" > "${OUT%.qcow2}.xml"
log "export $OUT ($(du -h "$OUT" | cut -f1)) en $(( $(date +%s) - T0 )) s"
ls -1t "$DEST"/*.qcow2 | tail -n +4 | while read -r old; do
  rm -f "$old" "${old%.qcow2}.xml"; log "rotation : $old supprimé"; done
```

Le `trap` garantit le `blockcommit` même si `qemu-img convert` échoue
(disque plein, `Ctrl-C`) : l'overlay ne survit jamais au script. Le `sed`
sur le XML corrige la référence à l'overlay, présente dans la définition
persistante pendant la fenêtre de sauvegarde.

### `bin/restaure-vm.sh`

```bash
#!/usr/bin/env bash
# restaure-vm.sh NOM [FICHIER.qcow2] — restaure dans un nouveau volume
set -euo pipefail
export LIBVIRT_DEFAULT_URI=qemu:///system
VM=${1:?} ; SRC=${2:-$(ls -1t "$HOME/lab20/backups/$VM"/*.qcow2 | head -1)}
[ -r "$SRC" ] || { echo "sauvegarde introuvable" >&2; exit 2; }
if qemu-img info "$SRC" | grep -q '^backing file'; then
  echo "sauvegarde non autoportante" >&2; exit 3
fi
DISK=$(virsh domblklist "$VM" | awk '$1=="vda"{print $2}')
[ "$(virsh domstate "$VM")" = "shut off" ] || virsh shutdown "$VM"
for _ in $(seq 60); do
  [ "$(virsh domstate "$VM")" = "shut off" ] && break; sleep 1
done
[ "$(virsh domstate "$VM")" = "shut off" ] || virsh destroy "$VM"
sudo mv "$DISK" "$DISK.avant-restauration"
sudo cp "$SRC" "$DISK" ; virsh pool-refresh default
virsh start "$VM"
echo "restauré depuis $SRC ; ancien disque : $DISK.avant-restauration"
```

Le chemin du disque ne change pas (donc pas de modification du XML) ;
l'ancien contenu est conservé sous un autre nom, à supprimer après
validation. Démonstration sur `p-db` : `ssh` via `p-web` (réseau isolé),
`echo marqueur | sudo tee /srv/marqueur`, `sauvegarde-vm.sh p-db`,
`sudo rm /srv/marqueur`, `restaure-vm.sh p-db`, `cat /srv/marqueur`.

### `bin/inventaire.py --ansible`

Extension de E20.16 : pour chaque `<interface>`, lire `mac`, `source
network|bridge`, puis `dom.interfaceAddresses(
libvirt.VIR_DOMAIN_INTERFACE_ADDRESSES_SRC_AGENT)` pour les adresses (un
`try/except libvirt.libvirtError` si l'agent est absent). Pour `--ansible` :

```python
groupes = {}
for vm in vms:
    for itf in vm["interfaces"]:
        groupes.setdefault(itf["reseau"], []).append((vm["nom"], itf.get("ip")))
for g, membres in sorted(groupes.items()):
    print(f"[{g}]")
    for nom, ip in membres:
        print(f"{nom} ansible_host={ip}" if g == "lan" and ip else nom)
print("[all:vars]\nansible_user=mathieu")
```

`p-db` n'a pas d'adresse sur `lan` : elle apparaît dans `[isole]` sans
`ansible_host`, et le module 23 lui donnera `ansible_ssh_common_args` avec
un `ProxyJump` par `p-web`.

### `rapports/d20.md` — les équivalents Proxmox

| Action libvirt | Proxmox |
|---|---|
| `virt-install --import` + seed | `qm clone <template>` + `qm set --ipconfig0/--sshkeys` |
| `vol-create-as --backing-vol` | `qm clone --full 0` (linked clone) |
| `snapshot-create-as` | `qm snapshot <id> <nom> [--vmstate 1]` |
| `sauvegarde-vm.sh` | `vzdump <id> --mode snapshot --storage local` |
| `restaure-vm.sh` | `qmrestore <archive> <id>` |
| `inventaire.py` | `pvesh get /cluster/resources --type vm --output-format json` |
| réseau `isole` | `vmbr2` avec `bridge-ports none`, pas de NAT |
| `virt-clone` + `virt-sysprep` | `qm clone --full 1` (cloud-init réidentifie) |

Ce que Proxmox donne que libvirt seul ne donne pas : (1) le **cluster** :
configuration répliquée (`/etc/pve`, corosync), migration en un clic, HA
avec fencing ; (2) la **sauvegarde intégrée** planifiée avec rétention,
vérification et déduplication (Proxmox Backup Server, sauvegardes
incrémentales par *dirty bitmap*) ; (3) l'**API + interface + droits**
(utilisateurs, rôles, pools, tokens) sur lesquels OpenTofu et Ansible se
branchent (module 24). libvirt est la brique ; Proxmox (ou OpenStack,
oVirt) est le produit.

::: pourquoi
Le défi vérifie que tu sais faire d'un hyperviseur nu une petite
plateforme **reproductible** : la description (`parc.txt`) est la source de
vérité, le code (`parc.sh`) converge vers elle sans effet de bord au second
passage, la sauvegarde est un script qui ne peut pas laisser l'hôte dans un
état incohérent (`trap`), la restauration est testée et non supposée, et
l'inventaire est produit par l'API plutôt que maintenu à la main. C'est
exactement le modèle des modules 23 et 24 (Ansible, OpenTofu) appliqué à la
main : quand tu liras `proxmox_virtual_environment_vm` avec un `for_each`,
tu sauras ce que le provider fait derrière, et pourquoi un `plan` vide est
la même chose qu'un `apply` qui « ne crée rien ».

Les mesures attendues sur `lab-virt` : `apply` à froid en 2 à 3 min (trois
VM séquentielles, l'attente SSH domine), 200 à 400 Mo réels par VM après le
premier boot, 30 à 60 s de sauvegarde pour 2,3 Go, gel inférieur à 1 s,
restauration en 60 à 90 s dont l'essentiel est l'arrêt propre.
:::
