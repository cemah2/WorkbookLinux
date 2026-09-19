#!/usr/bin/env bash
# check_M07_01.sh — vérifie le lab L7.1 (rapport-erreurs.sh)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L7.1 =="

S="$HOME/lab07/bin/rapport-erreurs.sh"
LOGS="$HOME/lab07/logs"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

if [ ! -f "$S" ]; then
  ko "$S est absent"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi
ok "le script existe"

[ -x "$S" ] && ok "le script est exécutable" \
            || ko "il manque le bit d'exécution (chmod +x)"

head -1 "$S" | grep -q '^#!.*bash' \
  && ok "shebang bash présent" \
  || ko "première ligne : shebang bash attendu (#!/usr/bin/env bash)"

if [ ! -d "$LOGS" ] || [ ! -e "$LOGS/rapport final.log" ]; then
  ko "$LOGS incomplet : relance setup_M07.sh"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi

# --- 1. aide -------------------------------------------------------------
"$S" -h > "$TMP/aide" 2>"$TMP/aide.err"; rc=$?
if [ "$rc" -eq 0 ] && grep -qi 'usage' "$TMP/aide"; then
  ok "-h affiche une aide sur stdout et sort en 0"
else
  ko "-h doit afficher l'usage sur stdout et sortir en 0 (obtenu : $rc)"
fi

# --- 2. option inconnue --------------------------------------------------
"$S" -Z >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "option inconnue -> code 2" \
                || ko "option inconnue : code 2 attendu, obtenu $rc"

# --- 3. répertoire absent ------------------------------------------------
"$S" -d "$TMP/nexistepas" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ] && ok "répertoire inexistant -> code 3" \
                || ko "répertoire inexistant : code 3 attendu, obtenu $rc"

# --- 4. exécution nominale ----------------------------------------------
"$S" -d "$LOGS" -s 25 > "$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" -eq 1 ] && ok "seuil dépassé -> code 1" \
                || ko "avec -s 25, code 1 attendu (44 erreurs le 16), obtenu $rc"

if grep -Eq '\[(INFO|WARN|ERROR|DEBUG)\]' "$TMP/out"; then
  ko "des lignes de journal polluent stdout : elles vont sur stderr"
else
  ok "stdout ne contient que le rapport (journal sur stderr)"
fi

if [ -s "$TMP/err" ]; then
  ok "le journal de service part bien sur stderr"
else
  ko "aucune ligne sur stderr : log_info/log_warn doivent y écrire"
fi

if [ "$(head -1 "$TMP/out")" = "app-2026-09-16.log;44" ]; then
  ok "tri décroissant : app-2026-09-16.log;44 en tête"
else
  ko "1re ligne attendue « app-2026-09-16.log;44 », obtenu : \
$(head -1 "$TMP/out")"
fi

if grep -qx 'rapport final.log;6' "$TMP/out"; then
  ok "le journal dont le nom contient une espace est traité (;6)"
else
  ko "« rapport final.log;6 » absent : ton script découpe les noms \
(quoting / for sur ls)"
fi

ATTENDU=$(find "$LOGS" -maxdepth 1 -type f -name '*.log' | wc -l)
OBTENU=$(grep -c . "$TMP/out")
if [ "$OBTENU" -eq "$ATTENDU" ]; then
  ok "les $ATTENDU journaux du répertoire sont dans le rapport"
else
  ko "$ATTENDU lignes attendues (un journal .log = une ligne), obtenu $OBTENU"
fi

# --- 5. seuil non atteint ------------------------------------------------
"$S" -d "$LOGS" -s 100 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "aucun dépassement -> code 0" \
                || ko "avec -s 100, code 0 attendu, obtenu $rc"

# --- 6. shellcheck -------------------------------------------------------
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x "$S" >"$TMP/sc" 2>&1; then
    ok "shellcheck ne signale rien"
  else
    ko "shellcheck remonte des avertissements : shellcheck $S"
  fi
else
  note "shellcheck n'est pas installé (sudo apt install -y shellcheck)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
