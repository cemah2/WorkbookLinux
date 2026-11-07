#!/usr/bin/env bash
# break_M29_02.sh — panne BF29.2 (configuration HAProxy divergente)
# À lancer sur lab-ha1, avec sudo. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
[ "$(hostname -s)" = lab-ha1 ] || { echo "à lancer sur lab-ha1" >&2; exit 1; }
CFG=/etc/haproxy/haproxy.cfg
[ -f "$CFG" ] || { echo "$CFG absent : termine L29.1 d'abord" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
[ -f "$SAUV/M29_02.haproxy.cfg" ] || cp -a "$CFG" "$SAUV/M29_02.haproxy.cfg"

MARQUE='# mise à jour : délais resserrés (perf)'
if ! grep -qF "$MARQUE" "$CFG"; then
  if grep -Eq '^\s*timeout\s+server\b' "$CFG"; then
    sed -i -E "0,/^\s*timeout\s+server\b.*/s//    $MARQUE\n    timeout server 5s/" "$CFG"
  else
    sed -i -E "0,/^defaults/s//defaults\n    $MARQUE\n    timeout server 5s/" "$CFG"
  fi
fi
haproxy -c -q -f "$CFG"
systemctl reload haproxy

cat <<'EOF'

Symptôme attendu : depuis lab-adm, http://lab-vip/lent?s=8 renvoie
« 504 Gateway Time-out » ; les pages courtes marchent. Pendant un test de
bascule (IP virtuelle sur lab-ha2), les exports fonctionnent.
EOF
