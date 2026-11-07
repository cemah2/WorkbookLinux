#!/usr/bin/env bash
# break_M29_01.sh — panne BF29.1 (VRRP filtré : deux maîtres)
# À lancer sur lab-ha2, avec sudo. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
[ "$(hostname -s)" = lab-ha2 ] || { echo "à lancer sur lab-ha2" >&2; exit 1; }
systemctl is-active -q keepalived || {
  echo "keepalived ne tourne pas : termine L29.2 d'abord" >&2; exit 1; }
command -v nft >/dev/null || { echo "nftables absent (apt install nftables)" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
[ -f "$SAUV/M29_01.ruleset" ] || nft list ruleset > "$SAUV/M29_01.ruleset"

# « durcissement » : on ne laisse entrer que ce qu'on connaît… et on oublie VRRP
if ! nft list table inet durcissement >/dev/null 2>&1; then
  nft add table inet durcissement
  nft add chain inet durcissement entree \
    '{ type filter hook input priority filter - 10; policy accept; }'
  nft add rule inet durcissement entree ip protocol vrrp counter drop
fi

cat <<'EOF'

Symptôme attendu : depuis lab-adm, http://lab-vip/ répond par intermittence
(séries de réponses, puis plusieurs secondes de délais d'attente). HAProxy
est actif et sain sur les deux nœuds.
EOF
