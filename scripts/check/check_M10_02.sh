#!/usr/bin/env bash
# check_M10_02.sh — vérifie le lab L10.2 (base sous LVM, extension, pvmove)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L10.2 =="

command -v lvs >/dev/null 2>&1 || {
  echo "  [FAIL] lvm2 n'est pas installé : sudo apt install -y lvm2"
  exit 1; }

DB=/srv/factura/db
VG=vg_data
[ -f /etc/lab10.env ] && . /etc/lab10.env
DISQUE1="${DISQUE1:-/dev/sdb}"

# --- 1. le VG et les LV existent ---------------------------------------
if vgs --noheadings -o vg_name 2>/dev/null | grep -qw "$VG"; then
  ok "le groupe de volumes $VG existe"
else
  ko "le groupe $VG n'existe pas (vgcreate $VG <pv>)"
fi

if lvs --noheadings -o lv_name "$VG" 2>/dev/null | grep -qw lv_pgdata; then
  ok "le volume logique lv_pgdata existe"
else
  ko "lv_pgdata est absent de $VG (lvcreate -L 2G -n lv_pgdata $VG)"
fi

# --- 2. /srv/factura/db est monté sur ce LV ----------------------------
if findmnt -no TARGET "$DB" >/dev/null 2>&1; then
  SRC=$(findmnt -no SOURCE "$DB")
  REEL=$(readlink -f "/dev/$VG/lv_pgdata" 2>/dev/null)
  if [ "$(readlink -f "$SRC")" = "$REEL" ] && [ -n "$REEL" ]; then
    ok "$DB est monté sur $VG/lv_pgdata"
  else
    ko "$DB est monté sur $SRC, pas sur /dev/$VG/lv_pgdata"
  fi
  TAILLE=$(df -BM --output=size "$DB" 2>/dev/null | tail -1 | tr -dc '0-9')
  if [ "${TAILLE:-0}" -ge 3000 ]; then
    ok "le système de fichiers fait ${TAILLE} Mio (extension propagée)"
  else
    ko "le système de fichiers ne fait que ${TAILLE:-0} Mio : as-tu utilisé \
lvextend -r (ou resize2fs) après l'extension du LV ?"
  fi
else
  ko "$DB n'est pas monté"
fi

# --- 3. le VG ne contient plus le premier disque -----------------------
PVS=$(pvs --noheadings -o pv_name --select "vg_name=$VG" 2>/dev/null \
  | tr -d ' ' | tr '\n' ' ')
if [ -n "$PVS" ]; then
  note "PV du groupe $VG : $PVS"
  if echo "$PVS" | grep -q "^${DISQUE1}[0-9]* $\|${DISQUE1}[0-9]* "; then
    ko "$DISQUE1 appartient encore à $VG : pvmove puis vgreduce n'ont pas \
été menés à leur terme"
  else
    ok "$DISQUE1 ne fait plus partie de $VG"
  fi
  NB=$(echo "$PVS" | wc -w)
  [ "$NB" -eq 1 ] && ok "le groupe ne contient plus qu'un seul PV" \
    || note "le groupe contient $NB PV (1 attendu après l'étape 7)"
else
  ko "impossible de lister les PV de $VG"
fi

# --- 4. lv_test réduit à 1 Go, données intactes ------------------------
if lvs --noheadings -o lv_name "$VG" 2>/dev/null | grep -qw lv_test; then
  ok "lv_test existe"
  MO=$(lvs --noheadings --units m --nosuffix -o lv_size "$VG/lv_test" \
    2>/dev/null | tr -d ' ' | cut -d. -f1)
  if [ "${MO:-0}" -ge 900 ] && [ "${MO:-0}" -le 1100 ]; then
    ok "lv_test fait ${MO} Mio (~1 Go, réduction réussie)"
  else
    ko "lv_test fait ${MO:-?} Mio : la réduction à 1 Go n'a pas abouti"
  fi

  MNT=$(lvs --noheadings -o lv_path "$VG/lv_test" 2>/dev/null | tr -d ' ')
  CIBLE=$(findmnt -nro TARGET -S "$(readlink -f "$MNT")" 2>/dev/null | head -1)
  if [ -n "$CIBLE" ]; then
    if [ -s "$CIBLE/donnees.bin" ]; then
      ok "les données de lv_test sont intactes ($CIBLE/donnees.bin)"
    else
      ko "donnees.bin est absent ou vide sur $CIBLE : la réduction a mangé \
les données (mauvais ordre resize2fs / lvreduce ?)"
    fi
  else
    note "lv_test n'est pas monté : impossible de vérifier les données. \
Remonte-le puis relance le contrôle."
  fi
else
  ko "lv_test est absent : l'étape 8 (réduction) n'a pas été faite"
fi

# --- 5. le rapport ------------------------------------------------------
LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab10/rapports/inf-4118.md"
if [ -s "$RAP" ]; then
  L=$(grep -c . "$RAP")
  [ "$L" -ge 10 ] && ok "rapport inf-4118.md rédigé ($L lignes)" \
    || ko "rapport inf-4118.md trop court ($L lignes, 10 minimum)"
  for mot in pvmove lvextend resize2fs; do
    grep -qi "$mot" "$RAP" || note "le rapport ne mentionne pas « $mot »"
  done
else
  ko "rapport absent : $RAP"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
