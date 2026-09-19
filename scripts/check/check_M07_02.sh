#!/usr/bin/env bash
# check_M07_02.sh — vérifie le lab L7.2 (inventaire.sh)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L7.2 =="

S="$HOME/lab07/bin/inventaire.sh"
CSV="$HOME/lab07/data/inventaire.csv"
RAP="$HOME/lab07/rapports/inventaire.txt"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

if [ ! -f "$S" ]; then
  ko "$S est absent"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi
ok "le script existe"
[ -x "$S" ] && ok "le script est exécutable" \
            || ko "il manque le bit d'exécution (chmod +x)"

if [ ! -f "$CSV" ]; then
  ko "$CSV absent : relance setup_M07.sh"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi
if [ "$(tail -c 1 "$CSV" | wc -l)" -ne 0 ]; then
  note "le CSV se termine maintenant par un saut de ligne : le piège de la \
dernière ligne ne se reproduira plus (relance setup_M07.sh pour le restaurer)"
fi

rm -f "$RAP"
"$S" > "$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" -eq 0 ] && ok "exécution nominale -> code 0" \
                || ko "code 0 attendu sur l'inventaire fourni, obtenu $rc"

verif_ligne() {   # $1 = libellé, $2 = ligne exacte attendue
  if grep -qxF "$2" "$TMP/out"; then
    ok "$1"
  else
    ko "$1 — ligne « $2 » absente de la sortie"
  fi
}

verif_ligne "en-tête des environnements"  "== Hôtes par environnement =="
verif_ligne "prod compte 4 hôtes"         "prod;4"
verif_ligne "recette compte 3 hôtes"      "recette;3"
verif_ligne "dev compte 1 hôte"           "dev;1"
verif_ligne "outillage compte 2 hôtes (runner-01 inclus)" "outillage;2"
verif_ligne "section de décommissionnement" "== À décommissionner =="
verif_ligne "cache-01 est repéré (5e champ)" "cache-01"
verif_ligne "section total"               "== Total =="

if grep -qx '10' "$TMP/out"; then
  ok "total = 10 : la dernière ligne sans saut de ligne est comptée"
else
  ko "total attendu 10 — 9 signifie que la dernière ligne du CSV est perdue \
(voir la condition || [ -n \"\$hote\" ])"
fi

if grep -q 'hote;ip;role;env' "$TMP/out"; then
  ko "la ligne d'en-tête du CSV est comptée comme un hôte"
else
  ok "l'en-tête du CSV est ignoré"
fi

if grep -Eq '^(base|frontal) ' "$TMP/out"; then
  ko "un champ contenant une espace a été découpé (IFS=';' manquant ?)"
else
  ok "les champs à espaces (« frontal web ») restent entiers"
fi

# --- rapport et idempotence ---------------------------------------------
if [ -s "$RAP" ]; then
  ok "le rapport $RAP est écrit"
else
  ko "le rapport ~/lab07/rapports/inventaire.txt n'a pas été produit"
fi

if diff -q "$TMP/out" "$RAP" >/dev/null 2>&1; then
  ok "le rapport et la sortie écran sont identiques"
else
  ko "le fichier et l'écran diffèrent (pense à tee)"
fi

"$S" > "$TMP/out2" 2>/dev/null
if diff -q "$TMP/out" "$TMP/out2" >/dev/null 2>&1; then
  ok "deux exécutions donnent le même résultat (idempotent)"
else
  ko "la seconde exécution ne donne pas le même résultat"
fi

# --- CSV absent ----------------------------------------------------------
"$S" -f "$TMP/nexistepas.csv" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 4 ] && ok "CSV introuvable -> code 4" \
                || ko "CSV introuvable : code 4 attendu, obtenu $rc"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "$S" >/dev/null 2>&1 \
    && ok "shellcheck ne signale rien" \
    || ko "shellcheck remonte des avertissements : shellcheck $S"
else
  note "shellcheck n'est pas installé (sudo apt install -y shellcheck)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
