#!/usr/bin/env bash
# check_M05_01.sh — vérifie le lab L5.1 (rapport d'analyse d'access.log)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L5.1 =="

BASE="$HOME/lab05"
SRC="$BASE/access.log"
RAP="$BASE/rapports/rapport-acces.txt"

[ -f "$SRC" ] || { ko "$SRC absent (relance setup_M05.sh)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

if [ -s "$RAP" ]; then
  ok "$RAP existe et n'est pas vide"
else
  ko "rapports/rapport-acces.txt absent ou vide (étape 8)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi

lignes=$(wc -l < "$RAP")
if [ "$lignes" -ge 25 ]; then
  ok "le rapport fait $lignes lignes"
else
  ko "le rapport ne fait que $lignes lignes : les 8 sections y sont-elles ?"
fi

# --- les chiffres du rapport doivent être ceux du journal ----------------
att_total=$(wc -l < "$SRC")
att_5xx=$(awk '$9 ~ /^5/' "$SRC" | wc -l)
att_ips=$(awk '{ print $1 }' "$SRC" | sort -u | wc -l)
att_404=$(awk '$9 == 404' "$SRC" | wc -l)

grep -q "$att_total" "$RAP" \
  && ok "le volume total ($att_total) figure dans le rapport" \
  || ko "le volume total ($att_total lignes) est absent (wc -l)"

grep -qw "$att_5xx" "$RAP" \
  && ok "le nombre de 5xx ($att_5xx) figure dans le rapport" \
  || ko "le nombre de 5xx est absent ou faux (awk '\$9 ~ /^5/')"

grep -qw "$att_404" "$RAP" \
  && ok "le nombre de 404 ($att_404) figure dans le rapport" \
  || ko "le nombre de 404 est absent ou faux"

grep -qw "$att_ips" "$RAP" \
  && ok "le nombre d'IP distinctes ($att_ips) figure dans le rapport" \
  || ko "le nombre d'IP distinctes est absent (sort -u | wc -l)"

grep -q '14/Sep/2026' "$RAP" && grep -q '18/Sep/2026' "$RAP" \
  && ok "la période couverte est indiquée" \
  || ko "la période (première et dernière date) n'apparaît pas"

# --- l'analyse doit désigner le bon coupable ----------------------------
grep -q '/api/v1/reports/export' "$RAP" \
  && ok "l'endpoint le plus lent est cité" \
  || ko "l'endpoint le plus lent n'est pas cité (étape 5, moyenne décroissante)"

grep -qE '(^|[^0-9])3[.,]9' "$RAP" \
  && ok "son temps de réponse moyen (~3.9 s) est indiqué" \
  || ko "le temps moyen de l'endpoint le plus lent n'apparaît pas"

# heure de pointe : 18
att_h=$(awk '{ print substr($4, 14, 2) }' "$SRC" | sort | uniq -c \
        | sort -rn | head -1 | awk '{ print $2 }')
grep -qE "(^|[^0-9:])${att_h}([^0-9]|$)" "$RAP" \
  && ok "l'heure de pointe (${att_h} h) est mentionnée" \
  || ko "l'heure de pointe n'est pas identifiée (étape 3)"

grep -qiE 'normalis|:id' "$RAP" \
  && ok "les endpoints sont normalisés (trace de :id)" \
  || note "pas de trace de normalisation d'URL : vérifie l'étape 4"

grep -qiE 'propos|action|recommand|conclusion' "$RAP" \
  && ok "le rapport se termine par une conclusion" \
  || ko "il manque les trois lignes de conclusion (étape 8)"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
