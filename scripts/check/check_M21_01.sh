#!/usr/bin/env bash
# check_M21_01.sh — vérifie le lab L21.1 (forge, runner, premier pipeline)
# À lancer sur lab-ops, en tant que mathieu.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L21.1 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BASE="$HOMEDIR/lab21"
API=http://10.10.10.14:3000/api/v1
TOKEN=$(tr -d '[:space:]' < "$BASE/.gitea-token" 2>/dev/null || true)
REPO="$API/repos/mathieu/factura"
api() { curl -s -m 10 -H "Authorization: token $TOKEN" "$@"; }
json() { python3 -c "import sys,json; d=json.load(sys.stdin); $1" 2>/dev/null; }

# --- 1. la forge répond -------------------------------------------------
curl -fs -m 5 http://10.10.10.14:3000/api/healthz >/dev/null \
  && ok "Gitea répond sur :3000" \
  || ko "Gitea ne répond pas (docker compose -f ~/lab21/forge/compose.yaml ps)"
[ -n "$TOKEN" ] && ok "jeton d'API présent" || ko "~/lab21/.gitea-token absent"

# --- 2. le runner --------------------------------------------------------
if [ -s "$BASE/forge/runner/data/.runner" ]; then
  ok "runner enregistré (.runner présent)"
else
  ko "runner non enregistré : docker compose logs runner"
fi
docker ps --format '{{.Names}} {{.Status}}' 2>/dev/null | grep -q '^act-runner Up' \
  && ok "conteneur act-runner en marche" \
  || ko "conteneur act-runner absent ou en échec (docker ps)"
CFG="$BASE/forge/runner/config.yaml"
python3 - "$CFG" <<'EOF' && ok "config.yaml : capacity 2 et cache activé" \
  || ko "config.yaml : attendu runner.capacity: 2 et cache.enabled: true"
import sys, yaml
c = yaml.safe_load(open(sys.argv[1]))
sys.exit(0 if c["runner"]["capacity"] == 2 and c["cache"]["enabled"] else 1)
EOF

# --- 3. protection de main -----------------------------------------------
BP=$(api "$REPO/branch_protections/main")
if printf '%s' "$BP" | json 'assert d.get("branch_name")=="main"'; then
  ok "branche main protégée"
  printf '%s' "$BP" | json 'assert d["required_approvals"]>=1' \
    && ok "au moins une approbation requise" \
    || ko "required_approvals doit valoir 1 ou plus"
  printf '%s' "$BP" | json 'assert "ci / lint" in d["status_check_contexts"]' \
    && ok "status check « ci / lint » requis" \
    || ko "le status check « ci / lint » n'est pas requis (nom exact : ci / lint)"
else
  ko "aucune protection sur main (Paramètres → Branches)"
fi

# --- 4. le workflow ------------------------------------------------------
WF=$(api "$REPO/raw/.gitea/workflows/ci.yaml")
if [ -n "$WF" ] && ! printf '%s' "$WF" | grep -q '"message"'; then
  ok ".gitea/workflows/ci.yaml présent sur main"
  printf '%s' "$WF" | python3 - <<'EOF' && ok "ci.yaml : jobs lint et test, artefact publié même en échec, timeout" \
    || ko "ci.yaml : attendu jobs lint + test, upload-artifact avec if: always(), timeout-minutes"
import sys, yaml
w = yaml.safe_load(sys.stdin)
j = w["jobs"]
assert "lint" in j and "test" in j
assert all("timeout-minutes" in j[k] for k in ("lint", "test"))
steps = j["test"]["steps"]
assert any("upload-artifact" in str(s.get("uses", "")) and "always()" in str(s.get("if", ""))
           for s in steps)
assert any("cache@" in str(s.get("uses", "")) for s in steps)
EOF
else
  ko "ci.yaml introuvable sur main (poussé ? bon chemin .gitea/workflows/ ?)"
fi
YL=$(api "$REPO/raw/.yamllint")
printf '%s' "$YL" | grep -q 'truthy' && ok ".yamllint présent (règle truthy)" \
  || ko ".yamllint absent ou sans règle truthy"

# --- 5. le résultat des tests (par l'API des tâches, si disponible) -------
T=$(api "$REPO/actions/tasks?limit=50")
if printf '%s' "$T" | json 'assert "workflow_runs" in d'; then
  printf '%s' "$T" | json '
runs=d["workflow_runs"]
assert any(r.get("name")=="lint" and r.get("status")=="success" for r in runs)
assert any(r.get("name")=="test" and r.get("status")=="success" for r in runs)' \
    && ok "un run avec lint et test en succès" \
    || ko "pas de jobs lint et test réussis (corrige smoke.sh et app.py, pas les tests)"
else
  note "API actions/tasks indisponible : vérifie à la main un run vert de ci"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
