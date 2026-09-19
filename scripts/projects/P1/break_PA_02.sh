#!/usr/bin/env bash
# break_PA_02.sh — incident INC-A2 (à lancer sur lab-web)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
[ "$(hostname -s)" = lab-web ] || { echo "à lancer sur lab-web" >&2; exit 1; }

EXP=/srv/factura/exports
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
[ -d "$EXP" ] || { echo "$EXP absent : PA.1/PA.4 pas faits" >&2; exit 1; }

[ -f "$SAUV/PA_02.exports.stat" ] \
  || stat -c '%U:%G %a' "$EXP" > "$SAUV/PA_02.exports.stat"

# Une « remise au propre » des droits par un collègue, récursive et
# trop zélée : le dossier passe à root.
chown root:root "$EXP"
chmod 0755 "$EXP"

# Quelques factures arrivent pendant ce temps.
for i in 1 2 3; do
  curl -s --max-time 5 -X POST -H 'Content-Type: application/json' \
    -d "{\"customer\":\"Client INC-A2 n°$i\",\"amount\":$((100 + i)).00}" \
    http://127.0.0.1:8000/invoices >/dev/null 2>&1 || true
done
sleep 2

cat <<'EOF'

Symptôme attendu : les nouvelles factures apparaissent dans l'interface avec
le statut « error » et aucun PDF n'est produit. Le worker est « active
(running) », ne redémarre pas, l'API répond 200 sur /health et la file
Redis est vide. La comptable attend ses PDF.
EOF
