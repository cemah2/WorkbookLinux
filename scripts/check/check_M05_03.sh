#!/usr/bin/env bash
# check_M05_03.sh — vérifie le lab L5.3 (autopsie du journal applicatif)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L5.3 =="

BASE="$HOME/lab05"
SRC="$BASE/app.log"
OOM="$BASE/rapports/oom.txt"
RAP="$BASE/rapports/erreurs-app.txt"

[ -f "$SRC" ] || { ko "app.log absent (setup_M05.sh)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. extraction des OutOfMemoryError ---------------------------------
if [ -s "$OOM" ]; then
  ok "rapports/oom.txt existe"
  n=$(grep -c 'OutOfMemoryError' "$OOM")
  [ "$n" -eq 13 ] && ok "13 OutOfMemoryError extraites" \
                  || ko "$n OutOfMemoryError au lieu de 13"
  e=$(grep -c '^2026-09-18 ' "$OOM")
  [ "$e" -eq 13 ] \
    && ok "chaque exception est précédée de sa ligne de journal" \
    || ko "$e lignes d'événement pour 13 exceptions : la ligne ERROR qui précède manque"
  f=$(grep -c $'^\t' "$OOM")
  [ "$f" -ge 70 ] \
    && ok "les piles d'appel sont présentes ($f lignes 'at ...')" \
    || ko "seulement $f lignes de pile : l'extraction s'arrête trop tôt"
  if grep -q 'NullPointerException\|SQLTransient\|PaiementRefuse' "$OOM"; then
    ko "oom.txt contient d'autres exceptions : la plage d'extraction déborde"
  else
    ok "oom.txt ne contient que des OutOfMemoryError"
  fi
else
  ko "rapports/oom.txt absent ou vide (étape 6)"
fi

# --- 2. le rapport ------------------------------------------------------
if [ -s "$RAP" ]; then
  ok "rapports/erreurs-app.txt existe"
  for v in 2847 1400 145 836; do
    grep -qw "$v" "$RAP" && ok "le chiffre $v figure dans le rapport" \
                         || ko "le chiffre $v est absent (lignes/événements/ERROR/INFO)"
  done
  grep -q 'SQLTransientConnectionException' "$RAP" \
    && ok "l'exception dominante est nommée" \
    || ko "l'exception la plus fréquente n'est pas citée (étapes 3 et 4)"
  grep -q 'SocketTimeoutException' "$RAP" \
    && ok "la cause racine dominante est nommée" \
    || ko "la cause racine dominante (Caused by:) n'est pas citée"
  grep -qw '63' "$RAP" \
    && ok "le chiffre qui prouve le couple dominant (63) est donné" \
    || ko "le nombre d'occurrences du couple dominant manque (étape 4)"
  grep -qE 'http-nio-8080-exec-2' "$RAP" \
    && ok "le thread sur-représenté est identifié" \
    || note "le thread le plus touché n'est pas nommé (étape 5)"
  grep -qE 'code=5[0-9]|refus' "$RAP" \
    && ok "les codes de refus banque sont repris" \
    || ko "les codes de refus (code=NN) manquent (étape 7)"
else
  ko "rapports/erreurs-app.txt absent ou vide (étape 8)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
