#!/usr/bin/env bash
# check_M03_02.sh — vérifie le lab L3.2 (lecture seule auditeur via ACL)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L3.2 =="

SRV=/srv/factura
FILE="$SRV/exports/rapport.csv"
HOMEDIR=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)

getent passwd webdev >/dev/null || { \
  ko "compte webdev absent (relance setup_M03.sh)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

if ! command -v getfacl >/dev/null 2>&1; then
  note "getfacl/setfacl absents : ce lab repose sur les ACL, installe le \
paquet acl (voir §3.1). Contrôles ACL ignorés."
fi

# --- 1. webdev peut lire un fichier -------------------------------------
if sudo -u webdev cat "$FILE" >/dev/null 2>&1; then
  ok "webdev peut lire $FILE"
else
  ko "webdev ne peut pas lire $FILE (setfacl -R -m u:webdev:rX $SRV)"
fi

# --- 2. webdev peut traverser jusqu'aux exports -------------------------
if sudo -u webdev ls "$SRV/exports" >/dev/null 2>&1; then
  ok "webdev peut lister $SRV/exports"
else
  ko "webdev ne peut pas traverser jusqu'à exports (rX récursif manquant)"
fi

# --- 3. webdev NE peut PAS écrire ---------------------------------------
if sudo -u webdev touch "$SRV/exports/.w02.$$" 2>/dev/null; then
  ko "webdev peut écrire : l'accès devait rester en lecture seule"
  rm -f "$SRV/exports/.w02.$$"
else
  ok "webdev ne peut pas écrire (lecture seule respectée)"
fi

# --- 4. other reste exclu -----------------------------------------------
if printf '%s' "$(stat -c '%A' "$SRV")" | grep -Eq '^d......---'; then
  ok "other reste à --- sur $SRV (pas d'ouverture au monde)"
else
  ko "other a des droits sur $SRV : l'énoncé interdit o+rX (utilise une ACL)"
fi

# --- 5. entrée ACL nominale + par défaut --------------------------------
if command -v getfacl >/dev/null 2>&1; then
  if getfacl -p "$SRV" 2>/dev/null | grep -q '^user:webdev:'; then
    ok "ACL d'accès user:webdev présente sur $SRV"
  else
    ko "aucune ACL user:webdev sur $SRV"
  fi
  if getfacl -p "$SRV" 2>/dev/null | grep -q '^default:user:webdev:'; then
    ok "ACL par défaut default:user:webdev présente (fichiers futurs couverts)"
  else
    ko "ACL par défaut manquante (setfacl -R -d -m u:webdev:rX $SRV)"
  fi
fi

# --- 6. rapport ---------------------------------------------------------
RAP="$HOMEDIR/lab03/rapports/acl-audit.md"
if [ -s "$RAP" ] && [ "$(grep -c . "$RAP")" -ge 8 ]; then
  ok "le rapport acl-audit.md est rédigé"
else
  ko "rapport ~/lab03/rapports/acl-audit.md absent ou trop court (8 lignes min)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
