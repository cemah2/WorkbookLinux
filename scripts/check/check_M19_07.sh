#!/usr/bin/env bash
# check_M19_07.sh — vérifie le lab L19.6 (profiler avant d'optimiser)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L19.6 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
P="$HOMEDIR/lab19/perf"
RAPD="$HOMEDIR/lab19/rapports"
REF=/opt/vitrine/perf

# durée d'une exécution en millisecondes (meilleure de N)
duree_ms() {  # $1 = répertoire, $2 = script, $3 = itérations
  local best=999999 t0 t1 d i
  for i in $(seq 1 "$3"); do
    t0=$(date +%s%N)
    ( cd "$1" && python3 "$2" factures.csv clients.csv >/dev/null 2>&1 )
    t1=$(date +%s%N)
    d=$(( (t1 - t0) / 1000000 ))
    [ "$d" -lt "$best" ] && best=$d
  done
  echo "$best"
}

# --- 1. le terrain ----------------------------------------------------------
[ -s "$REF/rapport-tva.py" ] && [ -s "$REF/sortie.md5" ] \
  && ok "copie de référence présente dans $REF" \
  || { ko "$REF incomplet : sudo bash setup_M19_perf.sh"; \
       echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
[ -s "$P/rapport-tva.py" ] && ok "script de travail présent" \
  || { ko "$P/rapport-tva.py absent"; \
       echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 2. le contrat : même sortie --------------------------------------------
ATTENDU=$(cat "$REF/sortie.md5")
OBTENU=$( cd "$P" && python3 rapport-tva.py factures.csv clients.csv 2>/dev/null \
  | md5sum | cut -d' ' -f1 )
if [ "$OBTENU" = "$ATTENDU" ]; then
  ok "la sortie du script corrigé est identique à la référence"
else
  ko "la sortie diffère de la référence (md5 $OBTENU ≠ $ATTENDU) : \
l'optimisation a changé le résultat"
fi
if cmp -s "$P/rapport-tva.py" "$REF/rapport-tva.py"; then
  ko "rapport-tva.py n'a pas été modifié (étape 5)"
else
  ok "rapport-tva.py a été modifié"
fi
cmp -s "$P/factures.csv" "$REF/factures.csv" && cmp -s "$P/clients.csv" \
  "$REF/clients.csv" && ok "les données sont celles de référence" \
  || ko "factures.csv ou clients.csv ont été modifiés : restaure-les depuis $REF"

# --- 3. le gain ---------------------------------------------------------------
note "mesure des durées (quelques secondes)…"
AVANT=$(duree_ms "$REF" rapport-tva.py 1)
APRES=$(duree_ms "$P" rapport-tva.py 3)
[ "$APRES" -gt 0 ] || APRES=1
GAIN=$(( AVANT / APRES ))
if [ "$GAIN" -ge 5 ]; then
  ok "gain mesuré : ${AVANT} ms → ${APRES} ms (×${GAIN})"
elif [ "$GAIN" -ge 2 ]; then
  ko "gain ×${GAIN} seulement (${AVANT} → ${APRES} ms) : la fonction chaude \
est-elle vraiment celle que perf désignait ?"
else
  ko "pas de gain mesurable (${AVANT} → ${APRES} ms) : relis perf report"
fi

# --- 4. les mesures et le rapport ---------------------------------------------
for f in perf-avant.txt perf-apres.txt; do
  if [ -s "$RAPD/$f" ]; then
    grep -qiE 'elapsed|real|wall clock' "$RAPD/$f" \
      && ok "$f contient une mesure de temps" \
      || ko "$f ne contient pas de mesure de temps (/usr/bin/time -v ou time)"
  else
    ko "$RAPD/$f absent"
  fi
done
if [ -s "$RAPD/profilage.md" ]; then
  grep -q 'chercher_client' "$RAPD/profilage.md" \
    && ok "profilage.md nomme la fonction chaude" \
    || ko "profilage.md ne nomme pas la fonction chaude trouvée par perf"
  grep -qiE 'perf (record|report|top)' "$RAPD/profilage.md" \
    && ok "profilage.md décrit la méthode perf" \
    || ko "profilage.md ne mentionne pas perf record/report"
  grep -qiE '×|x[0-9]+|facteur|fois' "$RAPD/profilage.md" \
    && ok "profilage.md chiffre le gain" \
    || ko "profilage.md ne chiffre pas le gain"
  grep -qi 'go' "$RAPD/profilage.md" \
    && ok "profilage.md répond sur la réécriture en Go" \
    || note "aucune réponse au développeur sur Go dans profilage.md"
else
  ko "rapport absent : $RAPD/profilage.md"
fi
ls "$P"/perf.data* >/dev/null 2>&1 && ok "perf.data présent dans $P" \
  || note "aucun perf.data dans $P : perf record a-t-il été lancé là ?"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
