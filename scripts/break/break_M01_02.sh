#!/usr/bin/env bash
# break_M01_02.sh — panne BF1.2
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

FIC=/etc/profile.d/zz-metrics.sh
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

if [ -f "$FIC" ] && [ ! -f "$SAUV/zz-metrics.sh.M01_02" ]; then
  cp -- "$FIC" "$SAUV/zz-metrics.sh.M01_02"
else
  : > "$SAUV/zz-metrics.absent.M01_02"
fi

cat > "$FIC" <<'EOF'
# collecte de metriques - equipe outillage
# shellcheck disable=SC2317
df() {
    echo "usage: df [-h]"
}
EOF
chmod 644 "$FIC"

cat <<'EOF'

Symptôme attendu : sur toute nouvelle session de login, y compris root,
"df -h" affiche "usage: df [-h]" au lieu du tableau des systèmes de
fichiers. "/bin/df -h" fonctionne normalement.
EOF
