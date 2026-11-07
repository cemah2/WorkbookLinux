#!/usr/bin/env bash
# check_M09_04.sh — vérifie le lab L9.4 (disque à chaud, udev, ordonnanceur)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L9.4 =="

HOME_DIR="$(getent passwd "${SUDO_USER:-${USER:-$(id -un)}}" | cut -d: -f6)"
RAP="$HOME_DIR/lab09/rapports"
LINK=/dev/disk/lab/cache

# --- 1. lien stable --------------------------------------------------------
if [ -L "$LINK" ]; then
  DEV=$(readlink -f "$LINK"); B=$(basename "$DEV")
  ok "$LINK -> $DEV"
else
  ko "$LINK absent : règle udev (SYMLINK+=) + udevadm trigger ?"
  DEV=""; B=""
fi

# --- 2. la règle -----------------------------------------------------------
RULE=$(grep -lsE 'disk/lab/cache' /etc/udev/rules.d/*.rules | head -1)
if [ -n "$RULE" ]; then
  ok "règle trouvée : $RULE"
  grep -qE 'ID_SERIAL|ID_PATH|ID_WWN' "$RULE" \
    && ok "la règle identifie le disque par une propriété stable" \
    || ko "la règle n'utilise ni ID_SERIAL ni ID_PATH : KERNEL==\"sdb\" \
n'est pas stable"
  grep -qE 'queue/scheduler' "$RULE" \
    && ok "la règle fixe l'ordonnanceur" \
    || ko "pas de ATTR{queue/scheduler} dans la règle"
  N=$(basename "$RULE" | cut -d- -f1)
  case "$N" in
    [0-5]*|60) ko "rang $N : la règle passe avant 60-persistent-storage \
(ID_SERIAL pas encore importé)" ;;
    *) ok "rang $N, après 60-persistent-storage" ;;
  esac
else
  ko "aucune règle dans /etc/udev/rules.d mentionnant disk/lab/cache"
fi

# --- 3. état du disque ------------------------------------------------------
if [ -n "$B" ] && [ -f "/sys/block/$B/queue/scheduler" ]; then
  grep -q '\[none\]' "/sys/block/$B/queue/scheduler" \
    && ok "ordonnanceur de $B : none" \
    || ko "ordonnanceur de $B : $(cat /sys/block/$B/queue/scheduler)"
  SZ=$(( $(cat /sys/block/$B/size) * 512 / 1024 / 1024 ))
  [ "$SZ" -ge 2000 ] && ok "taille de $B : $SZ Mo (agrandi à chaud)" \
    || ko "taille de $B : $SZ Mo, attendu 2 Go (qm disk resize + rescan)"
  FS=$(lsblk -no FSTYPE "$DEV" 2>/dev/null | head -1)
  LB=$(lsblk -no LABEL "$DEV" 2>/dev/null | head -1)
  [ "$FS" = ext4 ] && ok "système de fichiers ext4" \
    || ko "pas de ext4 sur $DEV (lu : ${FS:-aucun})"
  [ "$LB" = cache ] && ok "label 'cache' (by-label présent)" \
    || ko "label attendu 'cache', lu : ${LB:-aucun}"
  [ -e /dev/disk/by-label/cache ] && ok "/dev/disk/by-label/cache existe" \
    || ko "/dev/disk/by-label/cache absent (udevadm trigger après mkfs ?)"
fi

# --- 4. fichiers de nommage d'interface (non installés) --------------------
if ls "$HOME_DIR"/lab09/udev/*.link >/dev/null 2>&1; then
  ok "un fichier .link est rédigé dans ~/lab09/udev"
else
  ko "aucun .link dans ~/lab09/udev"
fi
ls "$HOME_DIR"/lab09/udev/*.rules >/dev/null 2>&1 \
  && ok "une règle udev de nommage est rédigée dans ~/lab09/udev" \
  || ko "aucune règle .rules dans ~/lab09/udev"
if grep -lsqE 'NAME=|^Name=' /etc/udev/rules.d/*.rules \
   /etc/systemd/network/*.link 2>/dev/null; then
  ko "une règle de renommage est INSTALLÉE (elle devait rester à blanc)"
else
  ok "aucune règle de renommage installée pour de bon"
fi

# --- 5. rapport --------------------------------------------------------------
[ -f "$RAP/udev.md" ] && [ "$(wc -l < "$RAP/udev.md")" -ge 12 ] \
  && ok "rapport udev.md présent" \
  || ko "rapport $RAP/udev.md absent ou trop court"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
