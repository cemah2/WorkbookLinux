#!/usr/bin/env bash
# check_M05_04.sh — vérifie le lab L5.4 (encodages, CRLF, diff/patch)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L5.4 =="

BASE="$HOME/lab05"
E="$BASE/encodages"

# --- 1. le script n'est plus en CRLF ------------------------------------
if [ -f "$E/deploiement.sh" ]; then
  if grep -qU $'\r' "$E/deploiement.sh"; then
    ko "deploiement.sh contient encore des CR (sed 's/\\r\$//' ou dos2unix)"
  else
    ok "deploiement.sh n'a plus de retour chariot"
    if bash "$E/deploiement.sh" >/dev/null 2>&1; then
      ok "deploiement.sh s'exécute sans erreur"
    else
      ko "deploiement.sh échoue encore à l'exécution"
    fi
  fi
else
  ko "encodages/deploiement.sh introuvable"
fi

# --- 2. conversion latin-1 ----------------------------------------------
UTF="$E/clients-utf8.csv"
if [ -s "$UTF" ]; then
  ok "clients-utf8.csv existe"
  if LC_ALL=C.UTF-8 grep -q 'Orléans' "$UTF" && LC_ALL=C.UTF-8 grep -q 'Besançon' "$UTF"; then
    ok "les accents sont corrects en UTF-8"
  else
    ko "les accents ne sont pas lisibles (iconv -f ISO-8859-1 -t UTF-8)"
  fi
  if file "$UTF" | grep -qi 'utf-8\|ascii'; then
    ok "file confirme l'encodage du fichier converti"
  else
    ko "file ne reconnaît pas le fichier comme UTF-8"
  fi
else
  ko "encodages/clients-utf8.csv absent (étape 3)"
fi

# --- 3. BOM supprimé ----------------------------------------------------
if [ -f "$E/export-tableur.csv" ]; then
  if [ "$(head -c3 "$E/export-tableur.csv" | od -An -tx1 | tr -d ' ')" = "efbbbf" ]; then
    ko "le BOM est toujours là (sed -i '1s/^\\xEF\\xBB\\xBF//')"
  else
    ok "le BOM a été retiré de export-tableur.csv"
    grep -q '^hostname' "$E/export-tableur.csv" \
      && ok "grep '^hostname' trouve maintenant l'en-tête" \
      || ko "grep '^hostname' ne trouve toujours rien"
  fi
else
  ko "encodages/export-tableur.csv introuvable"
fi

# --- 4. patch -----------------------------------------------------------
P="$BASE/conf/shop.patch"
if [ -s "$P" ]; then
  ok "conf/shop.patch existe"
  tmp=$(mktemp -d)
  cp "$BASE/conf/shop.conf" "$tmp/essai.conf"
  if (cd "$tmp" && patch -p0 --silent essai.conf < "$P") 2>/dev/null; then
    if diff -q "$tmp/essai.conf" "$BASE/conf/shop-propose.conf" >/dev/null; then
      ok "le patch appliqué à shop.conf redonne exactement shop-propose.conf"
    else
      ko "le patch s'applique mais le résultat diffère de shop-propose.conf"
    fi
  else
    ko "le patch ne s'applique pas sur shop.conf (diff -u ancien nouveau)"
  fi
  rm -rf "$tmp"
else
  ko "conf/shop.patch absent (étape 6)"
fi

# --- 5. le compte rendu -------------------------------------------------
R="$BASE/rapports/recette-livraison.txt"
if [ -s "$R" ]; then
  ok "rapports/recette-livraison.txt existe"
  l=$(grep -c . "$R")
  [ "$l" -ge 6 ] && ok "le compte rendu fait $l lignes utiles" \
                 || ko "le compte rendu ne fait que $l lignes (3 diagnostic + 3 correctif + 1 règle)"
else
  ko "rapports/recette-livraison.txt absent (étape 7)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
