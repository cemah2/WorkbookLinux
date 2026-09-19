#!/usr/bin/env bash
# break_M13_03.sh — panne BF13.3 (pare-feu qui jette le trafic de retour)
# À lancer sur lab-adm, L13.1 en place (table inet filter, chaîne forward).
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

if ! nft list chain inet filter forward >/dev/null 2>&1; then
  echo "la chaîne inet filter forward n'existe pas : L13.1 doit être en place" >&2
  exit 1
fi
[ -f "$SAUV/M13_03.ruleset.nft" ] || nft list ruleset > "$SAUV/M13_03.ruleset.nft"

handle_of() { # handle_of <motif exact de règle>
  nft -a list chain inet filter forward | grep -F "$1" | head -1 \
    | sed -n 's/.*# handle \([0-9]*\)$/\1/p'
}

# 1. la règle stateful disparaît
h=$(handle_of 'ct state established,related accept')
[ -n "$h" ] && nft delete rule inet filter forward handle "$h"

# 2. la règle de sortie ne laisse plus passer que les nouveaux flux
h=$(handle_of 'iifname "br-lab" oifname "ens18" accept')
if [ -n "$h" ]; then
  nft replace rule inet filter forward handle "$h" \
    iifname '"br-lab"' oifname '"ens18"' ct state new accept
fi

# 3. "on a gardé le ping pour la supervision"
if ! nft list chain inet filter forward | grep -q 'ip protocol icmp accept'; then
  h=$(handle_of 'ct state invalid')
  if [ -n "$h" ]; then
    nft add rule inet filter forward position "$h" ip protocol icmp accept
  else
    nft insert rule inet filter forward ip protocol icmp accept
  fi
fi

cat <<'EOF'

Symptôme attendu : depuis c1, curl http://10.10.10.11/ expire alors que
ping 10.10.10.11 répond ; tcpdump -i ens18 sur lab-adm montre le SYN partir
et le SYN-ACK revenir. Depuis lab-web, curl http://10.10.10.10:8080/ expire
aussi, alors que tcpdump -i veth-c1 montre le SYN arriver dans c1.
ip_forward vaut 1 et le masquerade est en place.
EOF
