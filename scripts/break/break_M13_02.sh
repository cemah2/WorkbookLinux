#!/usr/bin/env bash
# break_M13_02.sh — panne BF13.2 (table conntrack saturée)
# À lancer sur lab-adm, L13.1 en place. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
modprobe nf_conntrack 2>/dev/null || true

# conntrack n'est actif dans le netns que si une règle "ct" existe :
# celles de L13.1 suffisent, sinon on pose un compteur anodin.
if ! nft list ruleset 2>/dev/null | grep -q 'ct state'; then
  nft add table inet monitoring 2>/dev/null || true
  nft add chain inet monitoring output \
    '{ type filter hook output priority 0; }' 2>/dev/null || true
  nft add rule inet monitoring output ct state new counter 2>/dev/null || true
fi

if [ ! -f "$SAUV/M13_02.sysctl" ]; then
  {
    printf 'net.netfilter.nf_conntrack_max=%s\n' \
      "$(sysctl -n net.netfilter.nf_conntrack_max)"
    printf 'net.netfilter.nf_conntrack_udp_timeout=%s\n' \
      "$(sysctl -n net.netfilter.nf_conntrack_udp_timeout)"
  } > "$SAUV/M13_02.sysctl"
fi

cat > /etc/sysctl.d/99-conntrack.conf <<'EOF'
# réglages "recommandés" trouvés sur un forum
net.netfilter.nf_conntrack_udp_timeout = 3600
net.netfilter.nf_conntrack_max = 128
EOF
sysctl -qw net.netfilter.nf_conntrack_udp_timeout=3600
sysctl -qw net.netfilter.nf_conntrack_max=128

# on remplit : 200 datagrammes UDP vers des ports morts de la passerelle,
# chacun crée une entrée UNREPLIED qui vivra une heure
python3 - <<'EOF'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
for p in range(31000, 31200):
    try:
        s.sendto(b"x", ("10.10.10.1", p))
    except OSError:
        pass
EOF

cat <<'EOF'

Symptôme attendu : depuis lab-web, curl http://10.10.10.10:8080/ réussit
parfois et expire souvent ; ouvrir une NOUVELLE session SSH sur lab-adm
échoue une fois sur deux, les sessions déjà ouvertes fonctionnent ; depuis c1,
curl http://10.10.10.11/ se comporte de même. La charge CPU est nulle.
EOF
