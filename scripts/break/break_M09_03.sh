#!/usr/bin/env bash
# break_M09_03.sh — panne BF9.3 (pilote réseau interdit : plus de réseau
#                   au prochain reboot). NE REDÉMARRE PAS la VM.
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
F=/etc/modprobe.d/durcissement-pilotes.conf

# Le pilote de l'interface par défaut doit être virtio_net.
IF=$(ip -o route show default 2>/dev/null | awk '{print $5; exit}')
DRV=$(basename "$(readlink -f "/sys/class/net/${IF:-none}/device/driver" \
      2>/dev/null)" 2>/dev/null || true)
if [ "$DRV" != "virtio_net" ]; then
  echo "l'interface ${IF:-?} n'utilise pas virtio_net (${DRV:-inconnu}) :" >&2
  echo "scénario prévu pour une VM Proxmox avec carte virtio." >&2
  exit 1
fi

[ -f "$F" ] && [ ! -f "$SAUV/M09_03.conf" ] && cp -a "$F" "$SAUV/M09_03.conf"
K="$(uname -r)"
[ -f "/boot/initrd.img-$K" ] && [ ! -f "$SAUV/M09_03.initrd.img-$K" ] && \
  cp -a "/boot/initrd.img-$K" "$SAUV/M09_03.initrd.img-$K"

# Le « durcissement » : une liste de pilotes inutiles… avec un intrus.
cat > "$F" <<'EOF2'
# SEC-77 : pilotes inutiles sur les VM (playbook durcissement v3)
blacklist floppy
blacklist pcspkr
blacklist joydev
blacklist virtio_net
install virtio_net /bin/false
blacklist usb_storage
install usb_storage /bin/false
EOF2
chmod 0644 "$F"

# Comme le playbook : l'initramfs est régénéré pour « appliquer ».
if command -v update-initramfs >/dev/null 2>&1; then
  update-initramfs -u -k "$K" >/dev/null 2>&1 || true
elif command -v dracut >/dev/null 2>&1; then
  dracut -f >/dev/null 2>&1 || true
fi

cat <<'EOF2'

Symptôme attendu : APRÈS « sudo reboot », la VM ne répond plus ni au ping
ni au SSH. Sur la console (qm terminal 9001), « ip link » ne montre que lo.
Le mot de passe local est réputé inconnu : la reprise se fait par GRUB.
Rien n'est cassé tant que la VM n'a pas redémarré.
EOF2
