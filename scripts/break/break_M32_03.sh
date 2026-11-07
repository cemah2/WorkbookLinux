#!/usr/bin/env bash
# break_M32_03.sh — panne BF32.3 (espace libéré dans l'invité, jamais rendu à l'hôte)
# À lancer sur lab-db, avec sudo. REFORMATE le disque $A. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
H=$(getent passwd "${SUDO_USER:-mathieu}" | cut -d: -f6)
# shellcheck disable=SC1091
. "$H/lab32/disques.env" || { echo "setup_M32.sh d'abord" >&2; exit 1; }
M=/srv/lab32/archives
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV" "$M"
[ -f "$SAUV/M32_03.fstab" ] || cp -a /etc/fstab "$SAUV/M32_03.fstab"
systemctl is-enabled fstrim.timer > "$SAUV/M32_03.fstrim" 2>&1 || true

dev=$(readlink -f "$A")
if zpool status 2>/dev/null | grep -q "$(basename "$dev")\|lab32-3"; then
  echo "\$A appartient à un pool ZFS : détruis-le (zpool destroy) avant ce Break & Fix" >&2; exit 1
fi

if ! grep -q "[[:space:]]${M}[[:space:]]" /etc/fstab; then
  for m in $(findmnt -rno TARGET -S "$dev" || true); do umount "$m"; done
  wipefs -aq "$dev"
  mkfs.ext4 -q -F -E nodiscard -L archives "$dev"
  U=$(blkid -s UUID -o value "$dev")
  echo "UUID=$U $M ext4 defaults,nofail 0 2" >> /etc/fstab
  systemctl daemon-reload
fi
findmnt "$M" >/dev/null || mount "$M"

# le « nettoyage » : archives écrites puis supprimées
if [ ! -f "$SAUV/M32_03.fait" ]; then
  libre=$(df -Pm "$M" | awk 'NR==2{print $4}')
  mo=$(( libre * 85 / 100 ))
  echo "écriture puis suppression de $mo Mo d'archives…"
  dd if=/dev/urandom of="$M/archives-2025.tar" bs=1M count="$mo" status=none
  sync
  rm -f "$M/archives-2025.tar"
  sync
  date -Is > "$SAUV/M32_03.fait"
fi
systemctl disable --now fstrim.timer >/dev/null 2>&1 || true

cat <<'EOF'

Symptôme attendu (sur le nœud Proxmox) : « lvs » montre le volume du disque
lab32-3 de lab-db fortement rempli (Data%), alors que dans lab-db,
« df -h /srv/lab32/archives » montre un volume presque vide.
EOF
