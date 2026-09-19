#!/usr/bin/env bash
# break_M25_04.sh — panne BF25.4 (pipeline vert, prod vieille)
#   sur lab-ops : sudo bash break_M25_04.sh
#   sur lab-web : sudo bash break_M25_04.sh --web
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup/M25_04
mkdir -p "$SAUV"

# ======================= lab-web ==========================================
if [ "${1:-}" = "--web" ]; then
  FD=/usr/local/bin/factura-deploy
  [ -f "$FD" ] || { echo "$FD absent : fais d'abord L25.2" >&2; exit 1; }
  [ -f "$SAUV/factura-deploy" ] || cp "$FD" "$SAUV/factura-deploy"
  # « ajustement » du collègue : le tag latest passe la validation
  python3 - "$FD" <<'EOF'
import re, sys
p = sys.argv[1]
src = open(p).read()
if "latest" in src:
    sys.exit(0)
lines = src.split("\n")
done = False
for i, l in enumerate(lines):
    m = re.search(r"\[\[ *(\$\{?tag[^ ]*) *=~", l)
    if m:
        lines[i] = l.replace(m.group(0), "[[ %s == latest ]] || [[ %s =~" % (m.group(1), m.group(1)), 1)
        done = True
        break
if not done:
    for i, l in enumerate(lines):
        if re.match(r"^\s*read -r action tag", l):
            lines.insert(i + 1, '[ "${tag:-}" = latest ] && { cp .env .env.prev; '
                         'printf "TAG=latest\\n" > .env; docker compose pull -q '
                         '&& docker compose up -d; exit 0; }')
            break
open(p, "w").write("\n".join(lines))
EOF
  cat <<'EOF'

lab-web ajusté. Symptôme attendu : voir la sortie du script sur lab-ops.
EOF
  exit 0
fi

# ======================= lab-ops ==========================================
LAB_USER="${SUDO_USER:-mathieu}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
DEPOT="$HOMEDIR/lab25/factura"
WF="$DEPOT/.gitea/workflows/ci.yaml"
REG=10.10.10.14:5000
[ -f "$WF" ] || { echo "$WF absent : fais d'abord L25.2" >&2; exit 1; }
git_u() { sudo -u "$LAB_USER" git -C "$DEPOT" "$@"; }

if [ ! -f "$SAUV/ci.yaml" ]; then
  cp "$WF" "$SAUV/ci.yaml"
  git_u rev-parse HEAD > "$SAUV/head-avant"
fi

# --- 1. une image « latest » étrangère : la toute première version --------
if ! docker image inspect "$REG/factura:latest" >/dev/null 2>&1; then
  FIRST=$(git_u rev-list --max-parents=0 HEAD | tail -1)
  SHA12=${FIRST:0:12}
  git_u archive "$FIRST" | docker build -q \
    --build-arg "APP_VERSION=$SHA12" -t "$REG/factura:latest" - >/dev/null
fi
docker --config "$HOMEDIR/.docker" push -q "$REG/factura:latest" >/dev/null

# --- 2. « simplification » du workflow ------------------------------------
python3 - "$WF" <<'EOF'
import re, sys
p = sys.argv[1]
src = open(p).read()
# a) déploiement par latest
src = re.sub(r'deploy \$TAG', 'deploy latest', src)
src = re.sub(r'deploy \$\{\{[^}]*\}\}', 'deploy latest', src)
# b) le smoke test se contente d'un 200
lines = src.split("\n")
out, i = [], 0
while i < len(lines):
    l = lines[i]
    if re.match(r"^\s*- name: Smoke test\s*$", l):
        indent = len(l) - len(l.lstrip())
        out.append(l)
        i += 1
        while i < len(lines) and not (lines[i].strip() and
                                      len(lines[i]) - len(lines[i].lstrip()) <= indent):
            if re.match(r"^\s*run:", lines[i]):
                out.append(" " * (indent + 2) + "run: curl -fsS http://10.10.10.11:8080/health")
                i += 1
                while i < len(lines) and (not lines[i].strip() or
                        len(lines[i]) - len(lines[i].lstrip()) > indent + 2):
                    i += 1
                continue
            out.append(lines[i]); i += 1
        continue
    out.append(l); i += 1
open(p, "w").write("\n".join(out))
EOF

if ! git_u diff --quiet -- .gitea/workflows/ci.yaml; then
  git_u -c user.name='Julien Marchal' -c user.email='julien@lab.local' \
    commit -q -m 'simplification déploiement' -- .gitea/workflows/ci.yaml
  git_u push -q origin HEAD:main
fi

cat <<'EOF'

lab-ops cassé. Lance maintenant « sudo bash break_M25_04.sh --web » sur
lab-web (le collègue y a « aussi ajusté un truc »).

Symptôme attendu : depuis le commit « simplification déploiement », chaque
run ci est vert, deploy affiche Pulled / Started, le smoke test passe.
Pourtant http://10.10.10.11:8080/version renvoie un SHA qui n'est pas
celui du dernier commit de main, et /factures/0 répond 200 au lieu de 404.
EOF
