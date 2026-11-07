#!/usr/bin/env bash
# break_M30_01.sh — panne BF30.1 (motif d'exclusion trop large)
# À lancer sur lab-web, avec sudo. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
X=/etc/restic/exclusions
[ -f "$X" ] || { echo "$X absent : termine L30.1 d'abord" >&2; exit 1; }
systemctl cat restic-sauvegarde.service >/dev/null 2>&1 || {
  echo "restic-sauvegarde.service absent : termine L30.1 d'abord" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
[ -f "$SAUV/M30_01.exclusions" ] || cp -a "$X" "$SAUV/M30_01.exclusions"

if ! grep -qx 'nginx' "$X"; then
  printf '# journaux volumineux (demande OPS-2207)\nnginx\n' >> "$X"
  touch -d '-3 days' "$X"
fi

# la sauvegarde de la nuit, en avance
systemctl start restic-sauvegarde.service || true

cat <<'EOF'

Symptôme attendu : on te demande de restaurer /etc/nginx dans l'état
d'hier. restic-sauvegarde.service est en succès, « restic check » ne trouve
rien, mais « restic restore latest --include /etc/nginx » ne restaure rien.
EOF
