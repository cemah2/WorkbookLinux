#!/usr/bin/env bash
# break_M20_04.sh — panne BF20.4 : « la VM importée refuse de démarrer :
# Permission denied ». Fabrique import-1 (overlay sur la base + seed) dans
# /root/import/ et la définit à partir du XML de vm-01. Idempotent.
# Sauvegarde le XML généré dans /root/.breakfix-backup/.
# À lancer avec sudo sur lab-virt (L20.1 fait).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
V="virsh -c qemu:///system"
LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
BASE=/var/lib/libvirt/images/ubuntu-24.04-base.qcow2
IMP=/root/import
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV" "$IMP"
chmod 700 /root

$V dominfo vm-01 >/dev/null 2>&1 || { echo "vm-01 absente : fais L20.1 d'abord" >&2; exit 1; }
[ -r "$BASE" ] || { echo "$BASE absente : setup_M20.sh" >&2; exit 1; }

if $V dominfo import-1 >/dev/null 2>&1; then
  echo "import-1 existe déjà : rien à refaire"
else
  # disque : overlay sur la base (comme sur « l'ancien hôte »)
  [ -f "$IMP/import-1.qcow2" ] \
    || qemu-img create -q -f qcow2 -F qcow2 -b "$BASE" "$IMP/import-1.qcow2" 20G
  # seed : identité propre, mêmes clés que vm-01
  UD="$LAB_HOME/lab20/cloud-init/vm-01/user-data"
  [ -r "$UD" ] || UD="$LAB_HOME/lab20/cloud-init/user-data.example"
  sed 's/vm-01/import-1/g' "$UD" > "$IMP/user-data"
  printf 'instance-id: import-1-%s\nlocal-hostname: import-1\n' "$(uuidgen)" \
    > "$IMP/meta-data"
  cloud-localds "$IMP/import-1-seed.iso" "$IMP/user-data" "$IMP/meta-data"
  chmod 600 "$IMP"/import-1.qcow2 "$IMP"/import-1-seed.iso
  # XML : celui de vm-01, réidentifié, disques dans /root/import
  $V dumpxml --inactive vm-01 | python3 -c '
import sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
root.find("name").text = "import-1"
for tag in ("uuid", "seclabel"):
    for el in root.findall(tag):
        root.remove(el)
dev = root.find("devices")
for itf in dev.findall("interface"):
    for mac in itf.findall("mac"):
        itf.remove(mac)
for disk in dev.findall("disk"):
    src = disk.find("source")
    if disk.get("device") == "disk":
        src.set("file", "/root/import/import-1.qcow2")
    elif disk.get("device") == "cdrom":
        src.set("file", "/root/import/import-1-seed.iso")
    for bs in disk.findall("backingStore"):
        disk.remove(bs)
sys.stdout.write(ET.tostring(root, encoding="unicode"))
' > "$IMP/import-1.xml"
  cp "$IMP/import-1.xml" "$SAUV/M20_04_import-1.xml"
  $V define "$IMP/import-1.xml" >/dev/null
fi

cat <<'EOF'

Symptôme attendu : un collègue a rapatrié une VM d'un autre hôte (disque +
XML) dans /root/import/ et l'a définie avec « virsh define » : import-1.
« virsh start import-1 » répond « Permission denied » sur le fichier
disque. Le fichier appartient à root, en 0600, libvirt tourne en root, et
« sudo cat » du fichier fonctionne. Interdit : chmod/chown sur /root,
désactiver AppArmor, mettre user = "root" dans qemu.conf.
EOF
