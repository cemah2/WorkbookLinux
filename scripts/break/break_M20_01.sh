#!/usr/bin/env bash
# break_M20_01.sh — panne BF20.1 : « vm-01 met quatre minutes à démarrer et
# l'hôte est à 100 % ». Idempotent. Sauvegarde le XML de vm-01 dans
# /root/.breakfix-backup/. À lancer avec sudo sur lab-virt (L20.1 fait).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
V="virsh -c qemu:///system"
VM=vm-01
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

$V dominfo $VM >/dev/null 2>&1 || { echo "$VM n'existe pas : fais L20.1 d'abord" >&2; exit 1; }
[ -f "$SAUV/M20_01_$VM.xml" ] || $V dumpxml --inactive $VM > "$SAUV/M20_01_$VM.xml"

if $V dumpxml --inactive $VM | head -1 | grep -q "type='qemu'"; then
  echo "$VM est déjà dans l'état de la panne, rien à refaire"
else
  $V dumpxml --inactive $VM | python3 -c '
import sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
root.set("type", "qemu")
cpu = root.find("cpu")
if cpu is not None:
    root.remove(cpu)
cpu = ET.SubElement(root, "cpu", {"mode": "custom", "match": "exact", "check": "none"})
ET.SubElement(cpu, "model", {"fallback": "forbid"}).text = "qemu64"
sys.stdout.write(ET.tostring(root, encoding="unicode"))
' > /tmp/break_m20_01.xml
  $V define /tmp/break_m20_01.xml >/dev/null
  rm -f /tmp/break_m20_01.xml
fi

if [ "$($V domstate $VM)" != "shut off" ]; then
  $V destroy $VM >/dev/null 2>&1 || true
fi
$V start $VM >/dev/null

cat <<'EOF'

Symptôme attendu : vm-01 vient d'être redémarrée après « l'intervention de
nuit ». Elle met plusieurs minutes à donner un prompt, chaque commande y est
lente, et top sur lab-virt montre son processus qemu-system-x86_64 en
permanence autour de 100 % de CPU. /dev/kvm est présent, les autres VM
vont bien. Interdit de recréer la VM ou de redémarrer lab-virt.
EOF
