#!/usr/bin/env bash
# break_M02_02.sh — panne BF2.2 (inodes épuisés sur /srv/archives)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

IMG=/var/lib/lab02/archives.img
MNT=/srv/archives
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV" /var/lib/lab02 "$MNT"

printf 'panne BF2.2 posée le %s\n' "$(date -Is)" > "$SAUV/M02_02.marqueur"
echo "  (préparation, une vingtaine de secondes)" >&2

# --- système de fichiers volontairement mal dimensionné en inodes -------
# 96 Mio de blocs mais seulement 1024 inodes : le quota d'inodes tombe
# bien avant le quota d'octets.
if findmnt -n "$MNT" >/dev/null 2>&1; then
  umount "$MNT"
fi
rm -f "$IMG"
truncate -s 96M "$IMG"
mkfs.ext4 -q -F -N 1024 -L labarchives "$IMG"
mount -o loop "$IMG" "$MNT"

mkdir -p "$MNT/lots" "$MNT/spool"

# --- quelques gros lots légitimes : ~45 % des blocs ---------------------
for i in 1 2 3 4 5 6 7 8 9 10; do
  dd if=/dev/urandom of="$MNT/lots/lot-0$i.tar" bs=1M count=4 status=none
done

# --- et la vraie cause : un spool jamais purgé --------------------------
i=0
while [ "$i" -lt 2000 ]; do
  printf '{"id":%d}\n' "$i" > "$MNT/spool/evt-$i.json" || break
  i=$((i + 1))
done 2>/dev/null

chmod 1777 "$MNT/spool"

cat <<'EOF'

Symptôme attendu : toute écriture dans /srv/archives échoue avec
"No space left on device", y compris un simple touch ou mkdir, alors que
df -h /srv/archives affiche largement moins de 100 % et qu'il reste des
mégaoctets libres.
EOF
