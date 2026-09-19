#!/usr/bin/env bash
# break_M19_06.sh — panne BF19.6 (résolution de noms qui expire :
#                   5 secondes sur chaque requête)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
SINK=/usr/local/sbin/dns-cache-local
UNIT=/etc/systemd/system/dns-cache-local.service
mkdir -p "$SAUV"

# --- sauvegardes --------------------------------------------------------
[ -f "$SAUV/M19_06.hosts" ] || cp -a /etc/hosts "$SAUV/M19_06.hosts"
if [ ! -f "$SAUV/M19_06.resolv" ]; then
  if [ -L /etc/resolv.conf ]; then
    printf 'lien:%s\n' "$(readlink /etc/resolv.conf)" \
      > "$SAUV/M19_06.resolv.type"
  else
    printf 'fichier\n' > "$SAUV/M19_06.resolv.type"
  fi
  cp -aL /etc/resolv.conf "$SAUV/M19_06.resolv"
fi

# --- 1. l'« agent de cache DNS » déployé la veille : il écoute et ne
#        répond jamais. C'est lui qui fabrique les 5 secondes. ----------
cat > "$SINK" <<'PYEOF'
#!/usr/bin/env python3
"""dns-cache-local — agent de cache DNS local (v0.9, deploiement pilote).

Ecoute en UDP sur 127.0.0.77:53. La partie « reponse » n'est pas encore
implementee : les requetes sont acceptees et jamais servies.
"""
import socket

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("127.0.0.77", 53))
while True:
    s.recvfrom(4096)
PYEOF
chmod 0755 "$SINK"

cat > "$UNIT" <<'EOF'
[Unit]
Description=Cache DNS local (agent de resolution)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/dns-cache-local
Restart=always
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "$UNIT"

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload
  systemctl enable --now dns-cache-local.service >/dev/null 2>&1 || true
else
  pgrep -f "$SINK" >/dev/null 2>&1 || \
    setsid nohup "$SINK" >/dev/null 2>&1 < /dev/null &
fi

# --- 2. le nettoyage de /etc/hosts qui a tout déclenché -----------------
sed -i 's/^\([^#].*api-interne\.lab\.local.*\)$/#\1/' /etc/hosts

# --- 3. le résolveur local mis en tête, avec 5 s de temporisation -------
# Reconstruit à partir de la sauvegarde : le script reste idempotent même
# s'il est relancé dix fois.
TMP=$(mktemp)
{
  echo "# agent de cache local - CHG-1191"
  echo "nameserver 127.0.0.77"
  grep -E '^(nameserver|search|domain)' "$SAUV/M19_06.resolv" \
    | grep -v '^nameserver 127.0.0.77$' || true
  echo "options timeout:5 attempts:1"
} > "$TMP"
rm -f /etc/resolv.conf
mv "$TMP" /etc/resolv.conf
chmod 0644 /etc/resolv.conf

if [ -d /run/systemd/system ]; then
  systemctl restart vitrine-api.service >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : chaque page met 5 secondes environ, avec une
régularité suspecte. Les pages qui ne font aucun appel externe (/sante)
répondent instantanément. Aucune ressource n'est saturée : CPU, mémoire,
disque et réseau sont au repos.
Pour reproduire : time curl -s http://127.0.0.1:8080/produits
EOF
