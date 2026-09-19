#!/usr/bin/env bash
# break_M05_02.sh — casse la configuration de livraison (BF5.2)
# Idempotent. Sauvegarde dans ~/.breakfix-backup/M05/.
set -euo pipefail

BASE="$HOME/lab05"
BK="$HOME/.breakfix-backup/M05"
CIBLE="$BASE/conf/livraison.env"

[ -f "$CIBLE" ] || { echo "lance d'abord setup_M05.sh" >&2; exit 1; }
mkdir -p "$BK"
[ -f "$BK/livraison.env" ] || cp -- "$CIBLE" "$BK/livraison.env"

# le fichier revient d'un aller-retour par un poste Windows
printf 'CIBLE=/srv/factura\r\nVERSION=2.7.1\r\nRESPONSABLE=mathieu\r\n' > "$CIBLE"

echo "Symptôme attendu : bin/livrer.sh refuse la cible alors que"
echo "cat conf/livraison.env affiche la bonne valeur."
