#!/usr/bin/env bash
# break_M25_01.sh — panne BF25.1 (le pipeline a disparu)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/. Commit + push sur
# main de ~/lab25/factura au nom d'un collègue.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
DEPOT="$HOMEDIR/lab25/factura"
WF="$DEPOT/.gitea/workflows/ci.yaml"
SAUV=/root/.breakfix-backup/M25_01
mkdir -p "$SAUV"

[ -f "$WF" ] || { echo "$WF absent : fais d'abord L25.1" >&2; exit 1; }
git_u() { sudo -u "$LAB_USER" git -C "$DEPOT" "$@"; }

if [ ! -f "$SAUV/ci.yaml" ]; then
  cp "$WF" "$SAUV/ci.yaml"
  git_u rev-parse HEAD > "$SAUV/head-avant"
fi

# --- la panne -----------------------------------------------------------
# « refacto » : deux désindentations qui rendent le document illisible.
python3 - "$WF" <<'EOF'
import re, sys
p = sys.argv[1]
lines = open(p).read().split("\n")
out, in_test, done_runs, done_step = [], False, False, False
for l in lines:
    if re.match(r"^  test:\s*$", l):
        in_test = True
    elif re.match(r"^  \S", l):
        in_test = False
    if in_test and not done_runs and re.match(r"^    runs-on:", l):
        l = l[2:]; done_runs = True            # runs-on remonté d'un cran
    elif in_test and done_runs and not done_step and re.match(r"^      - (uses|name|run):", l):
        l = l[2:]; done_step = True            # un step désaligné
    out.append(l)
open(p, "w").write("\n".join(out))
EOF

if ! git_u diff --quiet -- .gitea/workflows/ci.yaml; then
  git_u -c user.name='Julien Marchal' -c user.email='julien@lab.local' \
    commit -q -m 'refacto ci : alignement des jobs' -- .gitea/workflows/ci.yaml
  git_u push -q origin HEAD:main
fi

cat <<'EOF'

Symptôme attendu : depuis le commit « refacto ci » de Julien, plus aucun
run n'apparaît dans l'onglet Actions de factura, ni sur push, ni en
déclenchement manuel (le bouton « Run workflow » ne propose plus ci).
Le runner est Idle. Pour reproduire : fais un commit vide et pousse-le,
puis observe l'onglet Actions.
EOF
