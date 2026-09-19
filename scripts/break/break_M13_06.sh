#!/usr/bin/env bash
# break_M13_06.sh — panne BF13.6 (résolveur transformé en forwarder mort)
# À lancer sur lab-ops, L13.4 en place (Unbound actif). Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
D=/etc/unbound/unbound.conf.d
F=$D/99-forward.conf

systemctl is-active -q unbound \
  || { echo "unbound n'est pas actif : L13.4 doit être en place" >&2; exit 1; }
[ -d "$SAUV/M13_06.unbound.conf.d" ] || cp -a "$D" "$SAUV/M13_06.unbound.conf.d"

# "on a mis le DNS de l'entreprise en amont, comme partout"
cat > "$F" <<'EOF'
# DNS d'entreprise en amont (demande INFRA-2210)
forward-zone:
    name: "."
    forward-addr: 10.10.10.99
EOF
unbound-checkconf >/dev/null
unbound-control reload >/dev/null 2>&1 || systemctl restart unbound
unbound-control flush_zone . >/dev/null 2>&1 || true

cat <<'EOF'

Symptôme attendu : sur toutes les VM, ping lab-db et ssh lab-web.lab.local
fonctionnent, mais apt update échoue et dig www.ubuntu.com renvoie SERVFAIL
après deux ou trois secondes. ping 9.9.9.9 répond. unbound est
active (running) et unbound-checkconf ne signale rien.
EOF
