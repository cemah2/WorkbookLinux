#!/usr/bin/env bash
# check_M20_01.sh — vérifie le lab L20.1 (vm-01 depuis l'image cloud)
# À lancer sur lab-virt, en tant que mathieu (groupe libvirt), sans sudo.
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification L20.1 =="

V="virsh -c qemu:///system"
VM=vm-01
BASE_IMG=/var/lib/libvirt/images/ubuntu-24.04-base.qcow2

# --- hôte ----------------------------------------------------------------
[ -c /dev/kvm ] && ok "/dev/kvm présent" \
  || ko "/dev/kvm absent (virtualisation imbriquée : cpu host + nested=1 sur le nœud)"
id -nG | tr ' ' '\n' | grep -qx libvirt && ok "membre du groupe libvirt" \
  || ko "pas dans le groupe libvirt (adduser, puis nouvelle session)"
grep -qsE 'LIBVIRT_DEFAULT_URI=qemu:///system|uri_default *= *"qemu:///system"' \
  ~/.bashrc ~/.profile ~/.config/libvirt/libvirt.conf 2>/dev/null \
  && ok "URI qemu:///system fixée de façon persistante" \
  || ko "LIBVIRT_DEFAULT_URI=qemu:///system absent de ~/.bashrc"
$V net-info default 2>/dev/null | grep -q 'Active: *yes' \
  && ok "réseau default actif" || ko "réseau default inactif (virsh net-start default)"
[ -r "$BASE_IMG" ] && ok "image de base présente" \
  || ko "$BASE_IMG absent ou illisible (setup_M20.sh)"

# --- la VM ---------------------------------------------------------------
if ! $V dominfo $VM >/dev/null 2>&1; then
  ko "$VM n'est pas définie (virt-install --import, étape 6)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi
ok "$VM définie"
[ "$($V domstate $VM)" = "running" ] && ok "$VM en marche" \
  || ko "$VM n'est pas running (virsh start $VM)"
XML=$($V dumpxml $VM 2>/dev/null)
grep -q "<domain type='kvm'" <<<"$XML" && ok "domaine de type kvm" \
  || ko "le domaine n'est pas de type kvm (TCG ?) : virsh dumpxml $VM | head -1"
DISK=$(grep -A4 "<disk type='file' device='disk'" <<<"$XML" | grep -o "file='[^']*'" \
       | head -1 | cut -d"'" -f2)
case "$DISK" in
  /var/lib/libvirt/images/*.qcow2) ok "disque vda dans le pool default : $DISK" ;;
  *) ko "disque vda attendu comme qcow2 du pool default (trouvé : ${DISK:-aucun})" ;;
esac
grep -A3 '<backingStore' <<<"$XML" | grep -q "ubuntu-24.04-base.qcow2" \
  && ok "backing file = ubuntu-24.04-base.qcow2" \
  || ko "pas de backingStore vers la base (vol-create-as --backing-vol ; VM allumée ?)"
grep -q "discard='unmap'" <<<"$XML" && ok "discard=unmap sur le disque" \
  || ko "discard='unmap' absent du driver disque (--disk ...,discard=unmap)"
grep -q "<model type='virtio'/>" <<<"$XML" && ok "carte réseau virtio" \
  || ko "carte réseau non virtio"
grep -q "org.qemu.guest_agent.0" <<<"$XML" && ok "canal de l'agent présent" \
  || ko "canal org.qemu.guest_agent.0 absent"
IP=$($V domifaddr $VM 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1 | head -1)
case "$IP" in
  192.168.122.*) ok "adresse sur le réseau NAT : $IP" ;;
  *) ko "pas d'adresse 192.168.122.x (virsh domifaddr $VM ; dnsmasq ; cloud-init ?)" ;;
esac
if [ -n "$IP" ] && timeout 3 bash -c "exec 3<>/dev/tcp/$IP/22" 2>/dev/null; then
  ok "port 22 ouvert sur $IP"
else
  ko "port 22 fermé (virsh console $VM : cloud-init terminé ? clé déployée ?)"
fi
$V qemu-agent-command $VM '{"execute":"guest-ping"}' >/dev/null 2>&1 \
  && ok "l'agent répond à guest-ping" \
  || ko "agent muet (qemu-guest-agent installé et actif dans l'invité ?)"
$V dominfo $VM | grep -q 'Autostart: *enable' && ok "autostart activé" \
  || ko "autostart désactivé (virsh autostart $VM)"

# --- rapport ---------------------------------------------------------------
R="$HOME/lab20/rapports/evo-412.md"
if [ -s "$R" ] && [ "$(wc -l < "$R")" -ge 12 ]; then
  ok "rapport evo-412.md présent"
  grep -q 'qemu-system-x86_64' "$R" && ok "la ligne QEMU est dans le rapport" \
    || ko "ligne de commande QEMU absente du rapport"
else
  ko "rapport $R absent ou trop court"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
