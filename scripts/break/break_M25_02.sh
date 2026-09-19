#!/usr/bin/env bash
# break_M25_02.sh — panne BF25.2 (job en attente indéfinie)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/. Commit + push sur
# main de ~/lab25/factura au nom d'un collègue.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
DEPOT="$HOMEDIR/lab25/factura"
WF="$DEPOT/.gitea/workflows/ci.yaml"
SAUV=/root/.breakfix-backup/M25_02
mkdir -p "$SAUV"

[ -f "$WF" ] || { echo "$WF absent : fais d'abord L25.1/L25.2" >&2; exit 1; }
git_u() { sudo -u "$LAB_USER" git -C "$DEPOT" "$@"; }

if [ ! -f "$SAUV/ci.yaml" ]; then
  cp "$WF" "$SAUV/ci.yaml"
  git_u rev-parse HEAD > "$SAUV/head-avant"
fi

# --- la panne -----------------------------------------------------------
# Le job build (ou, à défaut, le premier job) demande un label que
# personne ne porte.
python3 - "$WF" <<'EOF'
import re, sys
p = sys.argv[1]
lines = open(p).read().split("\n")
jobs = [i for i, l in enumerate(lines) if re.match(r"^  [A-Za-z0-9_-]+:\s*$", l)]
start = next((i for i in jobs if lines[i].strip() == "build:"), jobs[0] if jobs else None)
if start is None:
    sys.exit("aucun job trouvé")
for i in range(start + 1, len(lines)):
    if re.match(r"^  \S", lines[i]):
        break
    if re.match(r"^    runs-on:", lines[i]):
        lines[i] = "    runs-on: build-docker"
        break
open(p, "w").write("\n".join(lines))
EOF

if ! git_u diff --quiet -- .gitea/workflows/ci.yaml; then
  git_u -c user.name='Julien Marchal' -c user.email='julien@lab.local' \
    commit -q -m 'runner dédié build' -- .gitea/workflows/ci.yaml
  git_u push -q origin HEAD:main
fi

cat <<'EOF'

Symptôme attendu : le run du commit « runner dédié build » affiche lint et
test en vert, mais build reste en « waiting » indéfiniment. Le runner est
Idle dans Administration → Actions → Runners. Relancer le job ne change
rien.
EOF
