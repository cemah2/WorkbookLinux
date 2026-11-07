#!/usr/bin/env bash
# break_M32_01.sh — panne BF32.1 (instantané oublié qui retient l'espace)
# À lancer sur lab-db, avec sudo, pool tank de L32.3 en place. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
zpool list -H tank >/dev/null 2>&1 || { echo "pool tank absent : termine L32.3 d'abord" >&2; exit 1; }
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
zfs list -o space -r tank > "$SAUV/M32_01.espace-avant.txt"

zfs list -H tank/exports >/dev/null 2>&1 || zfs create tank/exports
D=/tank/exports

if ! zfs list -H -t snapshot tank/exports@avant-nettoyage >/dev/null 2>&1; then
  dispo=$(zfs get -Hp -o value available tank/exports)
  mo=$(( dispo * 70 / 100 / 1048576 ))
  echo "écriture d'un export de $mo Mo…"
  dd if=/dev/urandom of="$D/export-annuel.tar" bs=1M count="$mo" status=none
  sync
  zfs snapshot tank/exports@avant-nettoyage       # « par prudence »
  rm -f "$D/export-annuel.tar"                    # « pour faire de la place »
fi

# l'application continue d'écrire jusqu'à saturation
mkdir -p "$D/encours"
i=0
while [ "$i" -lt 400 ]; do
  i=$((i + 1))
  f="$D/encours/lot-$(printf '%04d' "$i").dat"
  [ -e "$f" ] && continue
  dd if=/dev/urandom of="$f" bs=1M count=50 status=none 2>/dev/null || break
done
sync

cat <<'EOF'

Symptôme attendu : toute écriture dans /tank/exports échoue (« No space left
on device »). « du -sh /tank/exports » ne montre que quelques centaines de Mo,
« df -h /tank/exports » affiche le pool plein.
EOF
