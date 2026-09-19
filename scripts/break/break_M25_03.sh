#!/usr/bin/env bash
# break_M25_03.sh — panne BF25.3 (secret divulgué dans les journaux)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/. Commit + push sur
# main de ~/lab25/factura au nom d'un collègue.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
DEPOT="$HOMEDIR/lab25/factura"
WF="$DEPOT/.gitea/workflows/ci.yaml"
SAUV=/root/.breakfix-backup/M25_03
mkdir -p "$SAUV"

[ -f "$WF" ] || { echo "$WF absent : fais d'abord L25.2" >&2; exit 1; }
grep -q '^  build:' "$WF" || { echo "pas de job build : fais L25.2" >&2; exit 1; }
git_u() { sudo -u "$LAB_USER" git -C "$DEPOT" "$@"; }

if [ ! -f "$SAUV/ci.yaml" ]; then
  cp "$WF" "$SAUV/ci.yaml"
  git_u rev-parse HEAD > "$SAUV/head-avant"
fi

# --- la panne -----------------------------------------------------------
# Un step de « debug » ajouté au job build, juste après le checkout.
python3 - "$WF" <<'EOF'
import re, sys
p = sys.argv[1]
src = open(p).read()
if "Debug push registre" in src:
    sys.exit(0)
lines = src.split("\n")
start = next(i for i, l in enumerate(lines) if l.strip() == "build:")
ins = None
for i in range(start + 1, len(lines)):
    if re.match(r"^  \S", lines[i]):
        break
    if "actions/checkout" in lines[i]:
        ins = i + 1
        break
if ins is None:
    sys.exit("pas de checkout dans build")
step = """      - name: Debug push registre
        env:
          REG_USER: ${{ vars.REGISTRY_USER }}
          REG_PASS: ${{ secrets.REGISTRY_PASSWORD }}
        run: |
          set -x
          auth=$(printf '%s:%s' "$REG_USER" "$REG_PASS" | base64 -w0)
          curl -sv -H "Authorization: Basic $auth" \\
            http://10.10.10.14:5000/v2/ -o /dev/null
          echo "$REG_PASS" | sed 's/./& /g'""".split("\n")
lines[ins:ins] = step
open(p, "w").write("\n".join(lines))
EOF

if ! git_u diff --quiet -- .gitea/workflows/ci.yaml; then
  git_u -c user.name='Julien Marchal' -c user.email='julien@lab.local' \
    commit -q -m 'debug push registre' -- .gitea/workflows/ci.yaml
  git_u push -q origin HEAD:main
fi

cat <<'EOF'

Symptôme attendu : le run du commit « debug push registre » est vert. Un
auditeur affirme que le journal du job build permet de se connecter au
registre 10.10.10.14:5000, alors que le secret REGISTRY_PASSWORD y
apparaît bien sous la forme *** à plusieurs endroits.
EOF
