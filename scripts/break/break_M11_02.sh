#!/usr/bin/env bash
# break_M11_02.sh — panne BF11.2 (inodes épuisés, espace disponible)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
CIBLE=/srv/factura/archives
IMG=/var/lib/lab11/bf11-02.img
mkdir -p "$SAUV" "$(dirname "$IMG")" "$CIBLE"

# --- mémoriser ce qui était monté là ------------------------------------
if [ ! -f "$SAUV/M11_02.montage" ]; then
  findmnt -no SOURCE,FSTYPE,OPTIONS "$CIBLE" > "$SAUV/M11_02.montage" 2>/dev/null \
    || echo "(rien n'était monté sur $CIBLE)" > "$SAUV/M11_02.montage"
fi

# --- déjà cassé ? on ne refait rien -------------------------------------
if findmnt -no SOURCE "$CIBLE" 2>/dev/null | grep -q .; then
  LIBRES=$(df --output=iavail "$CIBLE" 2>/dev/null | tail -1 | tr -dc '0-9')
  if [ "${LIBRES:-1}" -eq 0 ]; then
    echo "La panne est déjà en place." >&2
  fi
fi

# --- on démonte ce qui traîne pour poser notre volume -------------------
umount "$CIBLE" 2>/dev/null || true

# --- un volume avec très peu d'inodes -----------------------------------
# 1 Gio, 2560 inodes seulement : la pénurie arrive bien avant le remplissage.
rm -f "$IMG"
truncate -s 1G "$IMG"
chmod 600 "$IMG"
mkfs.ext4 -q -F -L archives -N 2560 -m 1 "$IMG"
mount -o loop,noatime,nodev,nosuid,noexec "$IMG" "$CIBLE"

# --- des données légitimes qu'il est INTERDIT de supprimer --------------
mkdir -p "$CIBLE/depots"
for i in $(seq 1 30); do
  dd if=/dev/urandom of="$CIBLE/depots/depot-$(printf '%03d' "$i").tar" \
     bs=1M count=15 status=none 2>/dev/null || break
done

# --- le vrai coupable : des milliers de fichiers de session vides -------
mkdir -p "$CIBLE/sessions"
VIEUX="$(date -d '6 days ago' '+%Y%m%d%H%M')"
i=0
while [ "$i" -lt 5000 ]; do
  ( : > "$CIBLE/sessions/sess-$(printf '%05d' "$i").tmp" ) 2>/dev/null || break
  i=$((i + 1))
done
touch -t "$VIEUX" "$CIBLE/sessions/"* 2>/dev/null || true
chown -R factura:factura "$CIBLE" 2>/dev/null || true
sync

cat <<'EOF'

Symptôme attendu : toute écriture dans /srv/factura/archives échoue avec
« No space left on device », y compris un simple
« sudo touch /srv/factura/archives/test ».
Pourtant « df -h /srv/factura/archives » affiche moins de 50 % d'utilisation
et plusieurs centaines de mégaoctets libres.
EOF
