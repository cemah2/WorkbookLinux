#!/usr/bin/env bash
# break_M31_02.sh — panne BF31.2 (piles tronquées par perf_event_max_stack)
# À lancer sur lab-web, avec sudo. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
B=/usr/local/bin/lab31-calcul
[ -x "$B" ] || { echo "setup_M31.sh d'abord" >&2; exit 1; }
file "$B" | grep -q 'not stripped' || {
  echo "lab31-calcul est dépouillé : termine BF31.1 (ou relance setup_M31.sh) d'abord" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
sysctl -n kernel.perf_event_max_stack > "$SAUV/M31_02.perf_event_max_stack"

cat > /etc/sysctl.d/99-perf-memoire.conf <<'EOF'
# réduit la mémoire utilisée par les profils perf (demande OPS-2311)
kernel.perf_event_max_stack = 4
EOF
sysctl -q -p /etc/sysctl.d/99-perf-memoire.conf
systemctl is-active -q lab31-calcul || systemctl start lab31-calcul

cat <<'EOF'

Symptôme attendu : le flame graph de lab31-calcul est lisible, mais les
tours ne descendent plus jusqu'à main ni _start, et « perf report
--children » n'attribue plus rien à main.
EOF
