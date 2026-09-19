#!/usr/bin/env bash
# break_M05_03.sh — casse le classement des IP (BF5.3)
# Idempotent. Sauvegarde dans ~/.breakfix-backup/M05/.
set -euo pipefail

BASE="$HOME/lab05"
BK="$HOME/.breakfix-backup/M05"
SRC="$BASE/access.log"
AGG="$BASE/access-agrege.log"

[ -f "$SRC" ] || { echo "lance d'abord setup_M05.sh" >&2; exit 1; }
mkdir -p "$BK"

# « nouvelle source » : le journal passe par un agrégateur qui indente
# une partie des lignes et termine tout en CRLF.
awk '{
  m = NR % 5
  if (m == 1)      printf " %s\r\n", $0
  else if (m == 2) printf "\t%s\r\n", $0
  else             printf "%s\r\n", $0
}' "$SRC" > "$AGG"

cp -- "$BASE/bin/top-ip.sh" "$BK/top-ip.sh" 2>/dev/null || true
sed -i 's|SRC="${1:-$HOME/lab05/access.log}"|SRC="${1:-$HOME/lab05/access-agrege.log}"|' \
  "$BASE/bin/top-ip.sh"

echo "Symptôme attendu : bin/top-ip.sh classe la même adresse à plusieurs"
echo "rangs et fait remonter une ligne sans adresse en tête."
