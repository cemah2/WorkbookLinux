#!/usr/bin/env bash
# check_M03_03.sh — vérifie le lab L3.3 (audit SUID/SGID)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L3.3 =="

HOMEDIR=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)
SUSPECT=/usr/local/bin/factura-backup

# --- 1. le binaire suspect n'est plus SUID ------------------------------
if [ -e "$SUSPECT" ]; then
  if printf '%s' "$(stat -c '%A' "$SUSPECT")" | grep -q '^...s'; then
    ko "$SUSPECT est encore SUID (chmod u-s $SUSPECT)"
  else
    ok "$SUSPECT n'a plus le bit SUID"
  fi
  # il doit toujours exister (interdit de le supprimer)
  ok "$SUSPECT existe toujours (non supprimé)"
else
  ko "$SUSPECT a été supprimé : l'énoncé demandait de retirer le bit, pas le \
fichier"
fi

# --- 2. il n'apparaît plus dans un find -perm -4000 ---------------------
if find /usr/local/bin -maxdepth 1 -perm -4000 -type f 2>/dev/null \
     | grep -q 'factura-backup'; then
  ko "factura-backup ressort encore d'un find -perm -4000"
else
  ok "factura-backup ne ressort plus d'un find -perm -4000"
fi

# --- 3. les SUID légitimes sont intacts ---------------------------------
legit_ok=1
for b in /usr/bin/passwd /usr/bin/sudo /usr/bin/mount /usr/bin/su; do
  [ -e "$b" ] || continue
  if ! printf '%s' "$(stat -c '%A' "$b")" | grep -q '^...s'; then
    ko "$b n'est plus SUID : tu as touché à un binaire système légitime"
    legit_ok=0
  fi
done
[ "$legit_ok" -eq 1 ] && ok "les SUID système (passwd, sudo, mount, su) sont intacts"

# --- 4. inventaire écrit et non vide ------------------------------------
INV="$HOMEDIR/lab03/rapports/suid-inventaire.txt"
if [ -s "$INV" ] && [ "$(grep -c . "$INV")" -ge 5 ]; then
  ok "l'inventaire suid-inventaire.txt est présent et non vide"
else
  ko "inventaire ~/lab03/rapports/suid-inventaire.txt absent ou trop court"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
