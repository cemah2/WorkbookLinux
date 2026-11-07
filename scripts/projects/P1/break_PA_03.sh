#!/usr/bin/env bash
# break_PA_03.sh — incident INC-A3 (à lancer sur lab-web)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
[ "$(hostname -s)" = lab-web ] || { echo "à lancer sur lab-web" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
ufw status | grep -q 'Status: active' \
  || { echo "ufw inactif : PA.5 n'est pas fait" >&2; exit 1; }

[ -f "$SAUV/PA_03.ufw-status" ] || ufw status numbered > "$SAUV/PA_03.ufw-status"
cp -a /etc/ufw/user.rules "$SAUV/PA_03.user.rules" 2>/dev/null || true

# Une règle « temporaire » posée pendant une maintenance réseau, jamais
# retirée, insérée en tête pour être sûr qu'elle s'applique.
if ! ufw status | grep -Eq '^443/tcp +DENY( IN)? +10\.10\.10\.0/24'; then
  ufw insert 1 deny proto tcp from 10.10.10.0/24 to any port 443 \
    comment 'maintenance reseau' >/dev/null
fi
# Le certificat est aussi renouvelé le même jour : nginx est rechargé,
# pour que le journal montre une activité « normale ».
systemctl reload nginx

cat <<'EOF'

Symptôme attendu : depuis lab-adm, « curl https://factura.lab.local/ »
reste bloqué puis échoue en timeout (code 28). Sur lab-web, nginx est
« active », « curl -k https://127.0.0.1/ » répond 200, le certificat est
valide et la supervision de lab-ops remonte factura_health_up 0.
EOF
