#!/usr/bin/env bash
# check_M05_06.sh — vérifie le défi D5 (rapport hebdomadaire)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D5 =="

BASE="$HOME/lab05"
MD="$BASE/rapports/hebdo-2026-S38.md"
PL="$BASE/rapports/hebdo-pipelines.sh"

[ -f "$BASE/access.log" ] || { ko "jeu de données absent (setup_M05.sh)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. le rapport ------------------------------------------------------
if [ -s "$MD" ]; then
  ok "rapports/hebdo-2026-S38.md existe"
else
  ko "rapports/hebdo-2026-S38.md absent ou vide"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi

for s in "## Trafic web" "## Performance" "## Erreurs applicatives" \
         "## Sécurité" "## Parc" "## Actions proposées"; do
  grep -qF "$s" "$MD" && ok "section présente : $s" \
                      || ko "section manquante : $s (titre à reprendre à l'identique, accents compris)"
done

# --- 2. les chiffres sont recalculés ici et comparés --------------------
a_total=$(wc -l < "$BASE/access.log")
a_5xx=$(awk '$9 ~ /^5/' "$BASE/access.log" | wc -l)
a_4xx=$(awk '$9 ~ /^4/' "$BASE/access.log" | wc -l)
p5=$(awk -v n="$a_5xx" -v t="$a_total" 'BEGIN { printf "%.1f", 100*n/t }')
p4=$(awk -v n="$a_4xx" -v t="$a_total" 'BEGIN { printf "%.1f", 100*n/t }')
e_err=$(grep -cE '^2026-09-18 [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3} ERROR ' "$BASE/app.log")
s_fail=$(grep -c 'Failed password' "$BASE/journal-ssh.txt")

grep -qw "$a_total" "$MD" && ok "volume total ($a_total) correct" \
                          || ko "volume total absent ou faux (attendu $a_total)"
grep -q "$p5" "$MD" && ok "part des 5xx ($p5 %) correcte" \
                    || ko "part des 5xx absente ou fausse (attendu $p5)"
grep -q "$p4" "$MD" && ok "part des 4xx ($p4 %) correcte" \
                    || ko "part des 4xx absente ou fausse (attendu $p4)"
grep -qw "$e_err" "$MD" && ok "nombre d'événements ERROR ($e_err) correct" \
                        || ko "nombre d'ERROR absent ou faux (attendu $e_err)"
grep -qw "$s_fail" "$MD" && ok "nombre d'échecs SSH ($s_fail) correct" \
                         || ko "nombre d'échecs SSH absent ou faux (attendu $s_fail)"
grep -q '14998' "$MD" && ok "coût mensuel total du parc présent" \
                      || ko "coût mensuel total absent (attendu 14998.40)"
grep -q '1872' "$MD" && ok "coût des hôtes non supervisés présent" \
                     || ko "coût des non supervisés absent (attendu 1872.00)"
grep -q '/api/v1/reports/export' "$MD" \
  && ok "l'endpoint le plus lent figure dans la section Performance" \
  || ko "l'endpoint le plus lent manque"
grep -q 'SQLTransientConnectionException' "$MD" \
  && ok "l'exception dominante figure dans le rapport" \
  || ko "l'exception dominante manque"
grep -q '45.155.205.14' "$MD" \
  && ok "l'IP attaquante principale figure dans le rapport" \
  || ko "le top 3 des IP SSH manque"

# tableau Markdown dans la section Performance
if awk '/^## Performance/, /^## Erreurs/' "$MD" | grep -qE '^\|.*\|'; then
  ok "la section Performance contient un tableau Markdown"
else
  ko "la section Performance doit présenter un tableau Markdown (| ... | ... |)"
fi

if [ "$(grep -cE '^[[:space:]]*[-*] ' "$MD")" -ge 3 ]; then
  ok "les actions proposées sont présentées en puces"
else
  ko "il manque les trois puces de la section Actions proposées"
fi

# --- 3. le fichier de pipelines -----------------------------------------
if [ -s "$PL" ]; then
  ok "rapports/hebdo-pipelines.sh existe"
  grep -q 'set -o pipefail' "$PL" \
    && ok "set -o pipefail est en tête du fichier" \
    || ko "set -o pipefail manquant (contrainte 3)"
  n=$(grep -cE '^[[:space:]]*#' "$PL")
  [ "$n" -ge 10 ] && ok "$n lignes de commentaire : chaque chiffre est documenté" \
                  || ko "seulement $n commentaires : un commentaire par pipeline attendu"
  p=$(grep -cE '\|' "$PL")
  [ "$p" -ge 10 ] && ok "$p pipelines livrés" \
                  || ko "seulement $p lignes contenant un pipe"
  if grep -qE '^[[:space:]]*cat[[:space:]]+[^|]*\|' "$PL"; then
    ko "un 'cat' inutile ouvre au moins un pipeline (contrainte 3)"
  else
    ok "aucun cat inutile en tête de pipeline"
  fi
  if grep -qE '(^|[^a-z])(printf|%\.[0-9]f)' "$PL"; then
    ok "les décimaux sont formatés avec printf"
  else
    ko "aucun formatage printf trouvé (contrainte 3)"
  fi
  if grep -qE '/tmp/|\.tmp|tmpfile' "$PL"; then
    ko "des fichiers temporaires apparaissent : utilise <( ), tee, exec 3>"
  else
    ok "aucun fichier temporaire"
  fi
else
  ko "rapports/hebdo-pipelines.sh absent ou vide (livrable 2)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
