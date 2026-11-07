#!/usr/bin/env bash
# break_M32_02.sh — panne BF32.2 (Btrfs en miroir privé d'un disque)
# À lancer sur lab-db, avec sudo. Crée son propre volume sur deux fichiers en
# boucle (/var/lib/lab32/bf-*.img), monté sur /srv/btrfs-bf. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
command -v mkfs.btrfs >/dev/null || { echo "apt install btrfs-progs" >&2; exit 1; }
R=/var/lib/lab32; M=/srv/btrfs-bf
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV" "$R" "$M"
[ -f "$SAUV/M32_02.fstab" ] || cp -a /etc/fstab "$SAUV/M32_02.fstab"

if ! grep -q "[[:space:]]${M}[[:space:]]" /etc/fstab; then
  truncate -s 1G "$R/bf-a.img" "$R/bf-b.img"
  LA=$(losetup -f --show "$R/bf-a.img")
  LB=$(losetup -f --show "$R/bf-b.img")
  mkfs.btrfs -f -q -L bf32 -d raid1 -m raid1 "$LA" "$LB"
  mount "$LA" "$M"
  cp -a /usr/share/doc "$M/" 2>/dev/null || true
  sync
  U=$(blkid -s UUID -o value "$LA")
  echo "UUID=$U $M btrfs defaults 0 0" >> /etc/fstab
  systemctl daemon-reload
  umount "$M"
  # l'« intervention matérielle » : le second disque disparaît
  losetup -d "$LB"
  mv "$R/bf-b.img" "$SAUV/M32_02.bf-b.img.perdu"
  btrfs device scan --forget >/dev/null 2>&1 || true
  btrfs device scan "$LA" >/dev/null 2>&1 || true
fi
findmnt "$M" >/dev/null && umount "$M"

cat <<'EOF'

Symptôme attendu : « mount /srv/btrfs-bf » échoue avec un message peu
explicite (wrong fs type, bad option, bad superblock…). La ligne de
/etc/fstab ferait échouer le démarrage.
EOF
