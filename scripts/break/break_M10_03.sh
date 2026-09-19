#!/usr/bin/env bash
# break_M10_03.sh — panne BF10.3 (snapshot LVM débordé, sauvegarde vide)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
VG=vg_data
LV=lv_pgdata
SNAP=snap_pg
DEST=/srv/sauvegardes
mkdir -p "$SAUV" "$DEST"

# --- prérequis ----------------------------------------------------------
command -v lvs >/dev/null 2>&1 || {
  echo "lvm2 n'est pas installé : sudo apt install -y lvm2" >&2; exit 1; }

if ! lvs "$VG/$LV" >/dev/null 2>&1; then
  cat >&2 <<EOF
Le volume $VG/$LV n'existe pas.
Cette panne se pose sur la pile LVM construite au lab L10.2 : fais-le
d'abord (pvcreate / vgcreate / lvcreate / mkfs / mount sur
/srv/factura/db), puis relance ce script.
EOF
  exit 1
fi

MNT=$(lvs --noheadings -o lv_path "$VG/$LV" | tr -d ' ')
CIBLE=$(findmnt -nro TARGET -S "$(readlink -f "$MNT")" 2>/dev/null | head -1)
if [ -z "$CIBLE" ]; then
  echo "$VG/$LV n'est monté nulle part : monte-le d'abord." >&2
  exit 1
fi

# --- trace de l'état avant ---------------------------------------------
[ -f "$SAUV/M10_03.lvs" ] || lvs -o +devices > "$SAUV/M10_03.lvs" 2>/dev/null

# --- on repart d'un état propre ----------------------------------------
umount /mnt/snap 2>/dev/null || true
lvs "$VG/$SNAP" >/dev/null 2>&1 && lvremove -y "$VG/$SNAP" >/dev/null 2>&1 || true

# --- le snapshot volontairement sous-dimensionné -----------------------
# 32 Mio : quelques dizaines de mégaoctets d'écritures sur l'origine
# suffisent à saturer la zone de copie sur écriture.
lvcreate -s -L 32M -n "$SNAP" "$MNT" >/dev/null

# --- on fait déborder : écritures massives sur l'ORIGINE ---------------
# Chaque écriture force la recopie de l'ancien chunk dans le snapshot.
mkdir -p "$CIBLE/lot-nocturne"
for i in $(seq 1 12); do
  dd if=/dev/urandom of="$CIBLE/lot-nocturne/lot-$i.dat" \
     bs=1M count=8 status=none 2>/dev/null || true
  sync
  dd if=/dev/urandom of="$CIBLE/lot-nocturne/lot-$i.dat" \
     bs=1M count=8 status=none 2>/dev/null || true
  sync
done
rm -rf "$CIBLE/lot-nocturne"
sync
sleep 2

# --- l'archive « produite » par la sauvegarde nocturne -----------------
ARCH="$DEST/factura-db-$(date -d 'yesterday' +%F).tar.gz"
tar czf "$ARCH" -T /dev/null 2>/dev/null || : > "$ARCH"
touch -d 'yesterday 02:31' "$ARCH" 2>/dev/null || true

cat <<'EOF'

Symptôme attendu : l'archive de la nuit dans /srv/sauvegardes ne fait que
quelques kilo-octets. Et
« sudo mount /dev/vg_data/snap_pg /mnt/snap » échoue sur
« can't read superblock on /dev/mapper/vg_data-snap_pg ».
La base, elle, fonctionne parfaitement : /srv/factura/db répond normalement.
EOF
