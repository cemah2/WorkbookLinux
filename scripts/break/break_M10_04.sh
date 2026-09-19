#!/usr/bin/env bash
# break_M10_04.sh — panne BF10.4 (démontage impossible + VG saturé)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
#
# Deux causes indépendantes sont posées :
#   A) le point de montage refuse de se démonter (processus + bind mount) ;
#   B) le groupe de volumes n'a plus un extent libre (snapshot oublié).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
CIBLE=/srv/factura/archives
BIND=/srv/backup-tmp
VG=vg_data
LV=lv_pgdata
SNAP=snap_pg
mkdir -p "$SAUV"

# ======================= Cause A : target is busy =====================
if ! findmnt -no TARGET "$CIBLE" >/dev/null 2>&1; then
  cat >&2 <<EOF
$CIBLE n'est monté sur rien.
Cette panne se pose sur le volume mis en service au lab L10.1 :
monte-le d'abord, puis relance ce script.
EOF
  exit 1
fi

[ -f "$SAUV/M10_04.mountinfo" ] || cp /proc/self/mountinfo "$SAUV/M10_04.mountinfo"

# 1. un processus dont le RÉPERTOIRE COURANT est dans le volume
#    (aucun fichier ouvert : lsof seul peut passer à côté)
if ! pgrep -f 'lab10-verrou' >/dev/null 2>&1; then
  mkdir -p "$CIBLE/depots"
  setsid bash -c "cd '$CIBLE/depots' && exec -a lab10-verrou sleep 86400" \
    </dev/null >/dev/null 2>&1 &
  sleep 1
fi

# 2. un bind mount du volume ailleurs dans l'arborescence
#    (aucun processus en cause : fuser et lsof ne verront rien)
mkdir -p "$BIND"
if ! findmnt -no TARGET "$BIND" >/dev/null 2>&1; then
  mount --bind "$CIBLE/depots" "$BIND"
fi

# ======================= Cause B : le VG est plein ====================
if command -v lvs >/dev/null 2>&1 && lvs "$VG/$LV" >/dev/null 2>&1; then
  LIBRE_M=$(vgs --noheadings --units m --nosuffix -o vg_free "$VG" \
    | tr -d ' ' | cut -d. -f1)
  if [ "${LIBRE_M:-0}" -gt 64 ]; then
    lvs "$VG/$SNAP" >/dev/null 2>&1 && lvremove -y "$VG/$SNAP" >/dev/null || true
    # un snapshot qui avale tout l'espace libre restant du groupe
    lvcreate -s -l 100%FREE -n "$SNAP" "/dev/$VG/$LV" >/dev/null 2>&1 \
      || lvcreate -s -L "${LIBRE_M}M" -n "$SNAP" "/dev/$VG/$LV" >/dev/null
  fi
  # on le fait remonter à trois semaines pour qu'il ait l'air oublié
  touch -d '3 weeks ago' "$SAUV/M10_04.snapshot-cree" 2>/dev/null || true
else
  echo "(lvm2 absent ou $VG/$LV inexistant : seule la cause A est posée)" >&2
fi

cat <<'EOF'

Symptôme attendu :
  - « sudo umount /srv/factura/archives » répond « target is busy » alors
    que le service factura est arrêté ;
  - « sudo lvextend -L +1G -r /dev/vg_data/lv_pgdata » répond
    « Insufficient free space », alors que le groupe avait été
    dimensionné large.
EOF
