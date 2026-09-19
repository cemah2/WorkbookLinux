#!/usr/bin/env bash
# check_M19_04.sh — vérifie le lab L19.4 (application lente : où part le
#                   temps ?)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L19.4 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BASE="$HOMEDIR/lab19"
RAP="$BASE/rapports/latence.md"
BASELINE="$BASE/rapports/baseline.txt"
URL="${URL:-http://127.0.0.1:8080}"

# --- 1. la latence est revenue ------------------------------------------
if command -v curl >/dev/null 2>&1; then
  MAX=0
  for _ in 1 2 3 4 5; do
    T=$(curl -s -o /dev/null -w '%{time_total}' --max-time 20 \
        "$URL/produits" 2>/dev/null || echo 99)
    MS=$(printf '%.0f' "$(echo "$T * 1000" | bc -l 2>/dev/null || echo 99000)")
    [ "$MS" -gt "$MAX" ] && MAX=$MS
  done
  if [ "$MAX" -lt 200 ]; then
    ok "/produits répond en moins de 200 ms (pire cas : ${MAX} ms)"
  elif [ "$MAX" -lt 1000 ]; then
    ko "pire cas ${MAX} ms : mieux, mais on n'est pas revenu à la baseline"
  else
    ko "pire cas ${MAX} ms : la cause de la lenteur est toujours là \
(décompose avec curl -w time_namelookup)"
  fi
  TS=$(curl -s -o /dev/null -w '%{time_total}' --max-time 20 \
       "$URL/sante" 2>/dev/null || echo 99)
  note "référence /sante : ${TS}s"
else
  note "curl absent : mesure de latence impossible"
fi

# --- 2. la résolution de noms est saine ---------------------------------
if command -v getent >/dev/null 2>&1; then
  T0=$(date +%s%N)
  getent hosts api-interne.lab.local >/dev/null 2>&1
  T1=$(date +%s%N)
  D=$(( (T1 - T0) / 1000000 ))
  if [ "$D" -lt 500 ]; then
    ok "résolution de api-interne.lab.local en ${D} ms"
  else
    ko "résolution en ${D} ms : le résolveur attend toujours un serveur \
qui ne répond pas (/etc/resolv.conf, /etc/hosts)"
  fi
fi

# --- 3. les livrables ----------------------------------------------------
if [ -s "$BASELINE" ]; then
  ok "baseline.txt présent (E19.15)"
else
  ko "baseline absente : $BASELINE — sans « avant », pas de comparaison"
fi

if [ -s "$RAP" ]; then
  ok "latence.md présent"
  grep -qiE 'dns|r[ée]solution|resolv' "$RAP" \
    && ok "la cause (résolution de noms) est identifiée" \
    || ko "latence.md ne désigne pas la résolution de noms"
  grep -qiE 'namelookup|connect|starttransfer|time_total' "$RAP" \
    && ok "la décomposition curl -w figure dans le rapport" \
    || ko "latence.md doit décomposer la requête (time_namelookup, \
time_connect, time_starttransfer)"
  grep -qiE 'strace|tcpdump' "$RAP" \
    && ok "au moins un outil d'observation fine est cité" \
    || ko "latence.md doit s'appuyer sur strace ou tcpdump"
  grep -qiE 'avant|apr[èe]s|baseline' "$RAP" \
    && ok "la comparaison avant/après est présente" \
    || ko "latence.md ne compare pas avant et après correctif"
  grep -qE '[0-9]+[.,][0-9]+' "$RAP" \
    && ok "des mesures chiffrées figurent au rapport" \
    || ko "aucun chiffre dans latence.md"
  [ "$(grep -c '[^[:space:]]' "$RAP")" -ge 15 ] \
    && ok "latence.md est étoffé" \
    || ko "latence.md fait moins de 15 lignes utiles"
else
  ko "rapport absent : $RAP"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
