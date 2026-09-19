#!/usr/bin/env bash
# check_M27_04.sh — vérifie le lab L27.4 (rotate_backups.py + tests)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L27.4 =="

D="$HOME/lab27/rotate"
S="$D/rotate_backups.py"
PY="$HOME/lab27/venv/bin/python"; [ -x "$PY" ] || PY=python3
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

[ -f "$S" ] || { ko "$S est absent (nom importable : underscore, pas tiret)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
ok "le script existe"

# jeu d'essai isolé : 120 jours + intrus
mkdir -p "$TMP/sauv"
for i in $(seq 0 119); do
  d=$(date -d "-$i days" +%F); echo x > "$TMP/sauv/factura-$d.tar.gz"
done
echo x > "$TMP/sauv/export final.tar.gz"
echo x > "$TMP/sauv/gitea-$(date +%F).tar.gz"

# --- dry-run -------------------------------------------------------------
"$PY" "$S" --dry-run "$TMP/sauv" > "$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" -eq 0 ] && ok "--dry-run sort en 0" || ko "--dry-run : code 0 attendu, obtenu $rc"
[ "$(ls "$TMP/sauv" | wc -l)" -eq 122 ] && ok "--dry-run n'a rien supprimé" \
  || ko "--dry-run a supprimé des fichiers"

# --- exécution réelle ----------------------------------------------------
"$PY" "$S" "$TMP/sauv" > "$TMP/out2" 2>"$TMP/err2"; rc=$?
[ "$rc" -eq 0 ] && ok "exécution réelle : code 0" || ko "code 0 attendu, obtenu $rc"
[ -f "$TMP/sauv/export final.tar.gz" ] && ok "« export final.tar.gz » survit" \
  || ko "un fichier hors motif a été supprimé"
[ -f "$TMP/sauv/gitea-$(date +%F).tar.gz" ] && ok "un autre préfixe survit" \
  || ko "le préfixe gitea- ne devait pas être touché"
manque=0
for i in $(seq 0 6); do
  d=$(date -d "-$i days" +%F); [ -f "$TMP/sauv/factura-$d.tar.gz" ] || manque=1
done
[ "$manque" -eq 0 ] && ok "les 7 dernières quotidiennes sont gardées" \
  || ko "une des 7 dernières archives quotidiennes manque"
n=$(ls "$TMP/sauv" | grep -c '^factura-')
[ "$n" -ge 12 ] && [ "$n" -le 17 ] && ok "$n archives factura gardées (7+4+6 avec recouvrements)" \
  || ko "$n archives gardées : attendu entre 12 et 17"
p1=$(date -d "$(date +%Y-%m-01) -1 month" +%F)
[ -f "$TMP/sauv/factura-$p1.tar.gz" ] && ok "la mensuelle du 1er du mois précédent est gardée" \
  || ko "factura-$p1.tar.gz (1er du mois précédent) devrait être gardée"
"$PY" "$S" "$TMP/sauv" >/dev/null 2>&1
[ "$(ls "$TMP/sauv" | grep -c '^factura-')" -eq "$n" ] && ok "idempotent : 2e passage sans effet" \
  || ko "le second passage a encore supprimé des fichiers"

# --- tests ---------------------------------------------------------------
if [ -d "$D/tests" ] && ls "$D"/tests/test_*.py >/dev/null 2>&1; then
  ok "un répertoire tests/ avec des test_*.py existe"
  if "$PY" -m pytest --version >/dev/null 2>&1; then
    if (cd "$D" && "$PY" -m pytest -q > "$TMP/pt" 2>&1); then
      nt=$(grep -Eo '[0-9]+ passed' "$TMP/pt" | grep -Eo '[0-9]+')
      ok "pytest : $nt tests passent"
      [ "${nt:-0}" -ge 5 ] && ok "au moins 5 tests" || ko "au moins 5 tests attendus"
    else ko "pytest échoue : cd $D && $PY -m pytest"; fi
  else note "pytest absent du venv"; fi
else ko "$D/tests/test_*.py attendu"; fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
