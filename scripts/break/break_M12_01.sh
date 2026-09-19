#!/usr/bin/env bash
# break_M12_01.sh — panne BF12.1 (route par défaut supprimée)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

DEF="$(ip -o -4 route show default | head -1)"

if [ -n "$DEF" ]; then
  # on note la route exacte pour pouvoir la remettre en cas de besoin
  [ -f "$SAUV/M12_01.default-route" ] || \
    printf '%s\n' "$DEF" > "$SAUV/M12_01.default-route"
  GW="$(printf '%s' "$DEF" | awk '{print $3}')"
  DEV="$(printf '%s' "$DEF" | awk '{print $5}')"
  ip route del default >/dev/null 2>&1 || true
  # certaines configurations en posent plusieurs : on vide
  while ip -o -4 route show default | grep -q .; do
    ip route del default >/dev/null 2>&1 || break
  done
  echo "  (sauvegarde : $SAUV/M12_01.default-route — $GW via $DEV)" >&2
else
  [ -f "$SAUV/M12_01.default-route" ] || \
    echo "default via 10.10.10.1 dev ens18" > "$SAUV/M12_01.default-route"
fi

cat <<'EOF'

Symptôme attendu : le réseau local répond normalement (ping 10.10.10.11,
ssh lab-web), mais « ping 9.9.9.9 » renvoie « Network is unreachable »
immédiatement, sans attente, et « apt update » finit par échouer.
Aucune configuration sur disque n'a été modifiée.
EOF
