#!/usr/bin/env bash
# break_M05_01.sh — casse le rapport quotidien (BF5.1)
# Idempotent. Sauvegarde dans ~/.breakfix-backup/M05/.
set -euo pipefail

BASE="$HOME/lab05"
BK="$HOME/.breakfix-backup/M05"
CIBLE="$BASE/bin/rapport-quotidien.sh"

[ -f "$CIBLE" ] || { echo "lance d'abord setup_M05.sh" >&2; exit 1; }
mkdir -p "$BK"
[ -f "$BK/rapport-quotidien.sh" ] || cp -- "$CIBLE" "$BK/rapport-quotidien.sh"

# « harmonisation du format de date » décidée par une autre équipe
sed -i \
  -e 's|JOUR="${1:-18/Sep/2026}"|JOUR="${1:-2026-09-18}"|' \
  -e 's|grep -F "\[\$JOUR"|grep -F "$JOUR"|' \
  "$CIBLE"

: > "$BASE/rapports/quotidien.txt"

echo "Symptôme attendu : rapports/quotidien.txt ne contient plus que sa ligne de"
echo "titre après exécution de bin/rapport-quotidien.sh, et echo \$? affiche 0."
