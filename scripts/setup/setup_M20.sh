#!/usr/bin/env bash
# setup_M20.sh — prépare lab-virt pour le module 20 (KVM, QEMU, libvirt).
# À lancer AVEC sudo sur lab-virt (10.10.10.16). Idempotent : relançable.
#
# Ce qu'il fait :
#   1. vérifie /dev/kvm (virtualisation imbriquée) et s'arrête sinon
#   2. installe la pile QEMU/libvirt/virtinst et les outils du module
#   3. ajoute l'utilisateur aux groupes libvirt et kvm
#   4. pool « default » (/var/lib/libvirt/images) et réseau « default »
#   5. télécharge l'image cloud Ubuntu 24.04 -> ubuntu-24.04-base.qcow2
#      (lecture seule) et y injecte qemu-guest-agent si virt-customize est là
#   6. clé SSH pour l'utilisateur si absente
#   7. ~/lab20/ : seed cloud-init d'exemple, gabarits XML, squelette de
#      l'usine à VM (L20.5), répertoires de livrables
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab20"
IMG_DIR=/var/lib/libvirt/images
IMG_NAME=ubuntu-24.04-base.qcow2
IMG_URL=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
SUMS_URL=https://cloud-images.ubuntu.com/noble/current/SHA256SUMS
. /etc/os-release

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
echo "== Préparation du module 20 sur $(hostname) =="

# ---------------------------------------------------------------------
# 1. KVM disponible ?
# ---------------------------------------------------------------------
info "vérification de la virtualisation imbriquée"
if ! grep -qE 'vmx|svm' /proc/cpuinfo; then
  cat >&2 <<'EOF'
Le CPU vu par cette VM n'a ni vmx ni svm : la virtualisation imbriquée
n'est pas active. Sur le nœud Proxmox :
  cat /sys/module/kvm_intel/parameters/nested      # Y attendu (AMD: kvm_amd -> 1)
  echo "options kvm-intel nested=1" > /etc/modprobe.d/kvm-intel.conf
  (AMD : "options kvm-amd nested=1" > /etc/modprobe.d/kvm-amd.conf) puis reboot
  qm set 9007 --cpu host ; qm stop 9007 ; qm start 9007
puis relance ce script.
EOF
  exit 1
fi
modprobe kvm_intel 2>/dev/null || modprobe kvm_amd 2>/dev/null || true
if [ ! -c /dev/kvm ]; then
  echo "/dev/kvm absent alors que le CPU annonce vmx/svm : lsmod | grep kvm, dmesg" >&2
  exit 1
fi
echo "   /dev/kvm présent, CPU : $(grep -m1 -oE 'vmx|svm' /proc/cpuinfo)"

# ---------------------------------------------------------------------
# 2. Paquets
# ---------------------------------------------------------------------
case "$ID" in
  ubuntu|debian)
    info "paquets (apt)"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -q
    apt-get install -y -q qemu-system-x86 qemu-utils libvirt-daemon-system \
      libvirt-clients virtinst cloud-image-utils genisoimage guestfs-tools \
      virt-top cpu-checker libosinfo-bin python3-libvirt python3-yaml jq \
      cloud-init uuid-runtime
    LV_GROUP=libvirt ; LV_UNIT=libvirtd
    ;;
  rocky|rhel|almalinux|centos)
    info "paquets (dnf)"
    dnf install -y -q qemu-kvm qemu-img libvirt libvirt-client virt-install \
      guestfs-tools genisoimage virt-top libosinfo python3-libvirt \
      python3-pyyaml jq cloud-init util-linux
    LV_GROUP=libvirt ; LV_UNIT=virtqemud
    # démons modulaires activés par socket (RHEL 9)
    for d in qemu interface network nodedev nwfilter secret storage; do
      systemctl enable --now "virt${d}d.socket" "virt${d}d-ro.socket" \
        "virt${d}d-admin.socket" >/dev/null 2>&1 || true
    done
    ;;
  *) echo "distribution non gérée : $ID" >&2; exit 1 ;;
esac
[ "$LV_UNIT" = libvirtd ] && { systemctl enable --now libvirtd >/dev/null 2>&1 || true; }
systemctl is-active --quiet libvirtd 2>/dev/null \
  || systemctl is-active --quiet virtqemud.socket 2>/dev/null \
  || { echo "libvirt ne tourne pas : systemctl status $LV_UNIT" >&2; exit 1; }

# ---------------------------------------------------------------------
# 3. Groupes
# ---------------------------------------------------------------------
info "groupes $LV_GROUP et kvm pour $LAB_USER"
for g in "$LV_GROUP" kvm; do
  getent group "$g" >/dev/null && usermod -aG "$g" "$LAB_USER"
done

# ---------------------------------------------------------------------
# 4. Pool et réseau default
# ---------------------------------------------------------------------
V="virsh -c qemu:///system"
info "pool default ($IMG_DIR)"
mkdir -p "$IMG_DIR"
if ! $V pool-info default >/dev/null 2>&1; then
  $V pool-define-as default dir --target "$IMG_DIR" >/dev/null
fi
$V pool-build default >/dev/null 2>&1 || true
$V pool-info default | grep -q 'State: *running' || $V pool-start default >/dev/null
$V pool-autostart default >/dev/null
info "réseau default (virbr0, NAT)"
if $V net-info default >/dev/null 2>&1; then
  $V net-info default | grep -q 'Active: *yes' || $V net-start default >/dev/null
  $V net-autostart default >/dev/null
else
  warn "réseau default absent : libvirt-daemon-system aurait dû le créer"
fi

# ---------------------------------------------------------------------
# 5. Image cloud Ubuntu 24.04
# ---------------------------------------------------------------------
IMG="$IMG_DIR/$IMG_NAME"
if [ ! -s "$IMG" ]; then
  info "téléchargement de l'image cloud Ubuntu 24.04 (~600 Mo)"
  curl -fL --progress-bar -o "$IMG.part" "$IMG_URL"
  if SUMS=$(curl -fsSL "$SUMS_URL" 2>/dev/null); then
    ATTENDU=$(printf '%s\n' "$SUMS" | awk '/noble-server-cloudimg-amd64.img$/{print $1}')
    OBTENU=$(sha256sum "$IMG.part" | cut -d' ' -f1)
    if [ -n "$ATTENDU" ] && [ "$ATTENDU" != "$OBTENU" ]; then
      echo "somme SHA256 incorrecte, téléchargement rejeté" >&2; rm -f "$IMG.part"; exit 1
    fi
    echo "   SHA256 vérifiée"
  else
    warn "SHA256SUMS injoignable : image non vérifiée"
  fi
  mv "$IMG.part" "$IMG"
fi
qemu-img info "$IMG" | grep -q 'file format: qcow2' \
  || { echo "$IMG n'est pas un qcow2 ?" >&2; exit 1; }

if [ ! -f "$IMG_DIR/.base-customized" ] && command -v virt-customize >/dev/null; then
  info "injection de qemu-guest-agent dans la base (virt-customize, 2 à 5 min)"
  chmod 0644 "$IMG"
  if LIBGUESTFS_BACKEND=direct timeout 900 virt-customize -a "$IMG" \
       --install qemu-guest-agent \
       --run-command 'systemctl enable qemu-guest-agent' >/dev/null 2>&1; then
    touch "$IMG_DIR/.base-customized"
    echo "   agent injecté"
  else
    warn "virt-customize a échoué : l'agent sera installé par cloud-init (packages:)"
  fi
fi
chown root:root "$IMG" ; chmod 0444 "$IMG"
$V pool-refresh default >/dev/null
echo "   base : $($V vol-info --pool default "$IMG_NAME" | tr -s ' ' | paste -sd' ')"

# ---------------------------------------------------------------------
# 6. Clé SSH de l'utilisateur sur lab-virt
# ---------------------------------------------------------------------
if [ ! -s "$LAB_HOME/.ssh/id_ed25519.pub" ]; then
  info "génération d'une clé SSH pour $LAB_USER"
  su - "$LAB_USER" -c 'ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519 -C mathieu@lab-virt'
fi
KEYS=$(cat "$LAB_HOME/.ssh/id_ed25519.pub" "$LAB_HOME/.ssh/authorized_keys" 2>/dev/null \
       | grep -E '^(ssh|ecdsa)-' | sort -u)

# ---------------------------------------------------------------------
# 7. ~/lab20
# ---------------------------------------------------------------------
info "arborescence $BASE"
install -d -o "$LAB_USER" -g "$LAB_USER" "$BASE" "$BASE/cloud-init" "$BASE/xml" \
  "$BASE/bin" "$BASE/img" "$BASE/rapports" "$BASE/backups"

poser() {   # poser <chemin>  (contenu sur stdin) : ne réécrit pas un fichier présent
  if [ -e "$1" ]; then cat >/dev/null; return 0; fi
  cat > "$1"; chown "$LAB_USER:$LAB_USER" "$1"
}

{
  cat <<'EOF'
#cloud-config
# user-data d'exemple (E20.6) : à copier dans cloud-init/<vm>/user-data
# et à adapter (hostname, marqueur). Valider : cloud-init schema --config-file
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
  printf '%s\n' "$KEYS" | sed 's/^/      - /'
  cat <<'EOF'
packages: [qemu-guest-agent]
write_files:
  - path: /etc/lab20-marker
    permissions: "0644"
    content: "vm-01\n"
runcmd:
  - systemctl enable --now qemu-guest-agent
EOF
} | poser "$BASE/cloud-init/user-data.example"

printf 'instance-id: vm-01-%s\nlocal-hostname: vm-01\n' "$(uuidgen)" \
  | poser "$BASE/cloud-init/meta-data.example"

poser "$BASE/cloud-init/network-config.example" <<'EOF'
# network-config v2 (Netplan) pour une VM sur le bridge br0 : pas de DHCP
# sur 10.10.10.0/24. cloud-localds -N network-config seed.iso user-data meta-data
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

poser "$BASE/xml/net-isole.xml" <<'EOF'
<network>
  <name>isole</name>
  <bridge name='virbr20' stp='on' delay='0'/>
  <ip address='10.20.0.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='10.20.0.100' end='10.20.0.199'/>
    </dhcp>
  </ip>
</network>
EOF

poser "$BASE/xml/net-lan.xml" <<'EOF'
<network>
  <name>lan</name>
  <forward mode='bridge'/>
  <bridge name='br0'/>
</network>
EOF

poser "$BASE/xml/pool-lab20.xml" <<'EOF'
<pool type='dir'>
  <name>lab20</name>
  <target>
    <path>/srv/vm</path>
  </target>
</pool>
EOF

poser "$BASE/bin/usine-vm.sh" <<'EOF'
#!/usr/bin/env bash
# usine-vm.sh — une commande, une VM libvirt prête (image cloud + cloud-init)
# Usage : usine-vm.sh --name NOM [--ram MO] [--vcpus N] [--key CLE.pub]
#         [--net network=default|bridge=br0] [--ip A.B.C.D/24] [--disk GO]
#         [--pool POOL]        crée (ou ne fait rien si la VM existe)
#         usine-vm.sh --name NOM --delete     détruit VM, disque, seed
# Squelette L20.5 : les parties marquées TODO sont à écrire.
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

if [ "$DELETE" -eq 1 ]; then
  # TODO : destroy si allumée, undefine, vol-delete des deux volumes,
  #        suppression de $SEEDS/$NAME. Rien d'autre.
  die "--delete : à écrire" 1
fi

# TODO idempotence : si la VM existe, afficher état + IP et sortir en 0.
# TODO contrôles : clé lisible, --net valide, --ip avec bridge, base présente,
#      pas de volume orphelin (code 3).
# TODO seed : user-data (clé $KEY), meta-data (instance-id = uuidgen),
#      network-config si --ip ; cloud-localds.
# TODO volumes : vol-create-as (overlay sur $BASE) + vol-create-as/vol-upload
#      du seed.
# TODO virt-install --import (host-passthrough, virtio, discard=unmap, agent).
# TODO attente IP (bail ou --ip) puis port 22, 180 s max, code 4 sinon.
die "création : à écrire (voir L20.5)" 1
EOF
chmod +x "$BASE/bin/usine-vm.sh"

poser "$BASE/README.md" <<'EOF'
# lab20 — Virtualisation KVM / libvirt

* `cloud-init/*.example` : seed de départ (E20.6) ; un sous-répertoire par VM
* `xml/` : réseaux `isole`, `lan` (bridge br0) et pool `lab20` (/srv/vm)
* `bin/usine-vm.sh` : squelette de l'usine à VM (L20.5)
* `img/` : images d'exercice (E20.4, E20.5) ; `backups/` : L20.4 ; `rapports/`
* base : /var/lib/libvirt/images/ubuntu-24.04-base.qcow2 (pool default, 0444)
* plage LAN réservée aux VM imbriquées bridgées : 10.10.10.160-179
EOF
chown -R "$LAB_USER:$LAB_USER" "$BASE"

# ---------------------------------------------------------------------
# Bilan
# ---------------------------------------------------------------------
echo
echo "== lab-virt prêt pour le module 20 =="
echo "   libvirt      : $($V version 2>/dev/null | awk '/Using library/{print $3,$4}')"
echo "   QEMU         : $($V version 2>/dev/null | awk '/Running hypervisor/{print $3,$4}')"
echo "   pool default : $($V pool-info default | awk '/State/{print $2}')"
echo "   réseau       : $($V net-list --name | paste -sd' ')"
echo "   base         : $IMG"
echo "   groupes      : $(id -nG "$LAB_USER" | tr ' ' '\n' | grep -xE 'libvirt|kvm' | paste -sd' ')"
echo
echo "Reconnecte-toi (nouveaux groupes) puis :"
echo "   echo 'export LIBVIRT_DEFAULT_URI=qemu:///system' >> ~/.bashrc"
