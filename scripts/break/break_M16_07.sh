#!/usr/bin/env bash
# break_M16_07.sh — panne BF16.7 (système de fichiers repassé en lecture
#                   seule après erreur d'E/S)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
DATA=/srv/vitrine/data
mkdir -p "$SAUV"

mountpoint -q "$DATA" || {
  echo "$DATA n'est pas monté : lance setup_M16.sh" >&2; exit 1; }

DEV=$(findmnt -n -o SOURCE --target "$DATA")
[ -b "$DEV" ] || {
  echo "périphérique de $DATA introuvable ($DEV)" >&2; exit 1; }

if [ ! -f "$SAUV/M16_07.etat" ]; then
  {
    printf 'device=%s\n' "$DEV"
    findmnt -n -o TARGET,SOURCE,FSTYPE,OPTIONS --target "$DATA"
  } > "$SAUV/M16_07.etat"
fi

# --- la trace que le noyau aurait laissée --------------------------------
# Sur une vraie machine, c'est le pilote de bloc qui écrit ces lignes.
# Ici on les injecte dans le tampon du noyau pour que le diagnostic se
# fasse exactement comme en production : par dmesg.
BASENOM=$(basename "$DEV")
if [ -w /dev/kmsg ]; then
  {
    printf 'blk_update_request: I/O error, dev %s, sector 208896 op 0x1:\n' \
      "$BASENOM"
    printf 'EXT4-fs warning (device %s): ext4_end_bio: I/O error 10 \n' \
      "$BASENOM"
    printf 'EXT4-fs error (device %s): ext4_journal_check_start: \n' \
      "$BASENOM"
    printf 'EXT4-fs (%s): Remounting filesystem read-only\n' "$BASENOM"
  } > /dev/kmsg 2>/dev/null || true
fi

# --- la panne : lecture seule au niveau bloc ET au niveau montage -------
sync
mount -o remount,ro "$DATA"
blockdev --setro "$DEV" 2>/dev/null || true

if [ -d /run/systemd/system ]; then
  systemctl restart vitrine-api.service >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : l'application répond en lecture, mais toute commande
passée sur le site échoue. Le journal applicatif affiche
« OSError: [Errno 30] Read-only file system ». Personne n'a touché à la
configuration.
Pour reproduire : curl -s http://127.0.0.1:8080/commande
EOF
