#!/usr/bin/env bash
# check_M21_04.sh — vérifie le lab L21.4 (pipelines Ansible et OpenTofu)
# À lancer sur lab-ops, en tant que mathieu.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L21.4 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BASE="$HOMEDIR/lab21"
API=http://10.10.10.14:3000/api/v1
TOKEN=$(tr -d '[:space:]' < "$BASE/.gitea-token" 2>/dev/null || true)
REPO="$API/repos/mathieu/factura-infra"
api() { curl -s -m 10 -H "Authorization: token $TOKEN" "$@"; }
json() { python3 -c "import sys,json; d=json.load(sys.stdin); $1" 2>/dev/null; }

# --- 1. la tâche piège est corrigée ---------------------------------------
PB=$(api "$REPO/raw/ansible/site.yml")
printf '%s' "$PB" | python3 - <<'EOF' && ok "site.yml : la tâche nginx -t a changed_when: false" \
  || ko "site.yml : la tâche « nginx -t » doit porter changed_when: false (et check_mode: false)"
import sys, yaml
p = yaml.safe_load(sys.stdin)
t = [x for x in p[0]["tasks"] if "nginx -t" in str(x.get("ansible.builtin.command", ""))]
assert t and t[0].get("changed_when") is False
EOF

# --- 2. workflow ansible ----------------------------------------------------
WA=$(api "$REPO/raw/.gitea/workflows/ansible.yaml")
printf '%s' "$WA" | python3 - <<'EOF' && ok "ansible.yaml : lint, check (PR, --check --diff), apply (push main, needs lint, concurrency)" \
  || ko "ansible.yaml : attendu jobs lint / check (pull_request, --check --diff) / apply (push sur main, needs, concurrency)"
import sys, yaml
w = yaml.safe_load(sys.stdin); j = w["jobs"]
assert "ansible-lint" in str(j["lint"]["steps"])
c = j["check"]; a = j["apply"]
assert "pull_request" in str(c.get("if", "")) and "--check" in str(c["steps"]) and "--diff" in str(c["steps"])
assert "main" in str(a.get("if", "")) and "lint" in str(a["needs"]) and "concurrency" in a
assert any("always()" in str(s.get("if", "")) for s in c["steps"])
EOF
printf '%s' "$WA" | grep -qE 'run:.*\$\{\{ *secrets\.' \
  && ko "ansible.yaml : un secret est interpolé dans un run: (passe par env:)" \
  || ok "ansible.yaml : secrets passés par env:"
printf '%s' "$WA" | grep -qE 'ansible_become_pass(word)?=' \
  && ko "ansible.yaml : le mot de passe become passe en ligne de commande (-e var=...)" \
  || ok "ansible.yaml : mot de passe become hors de la ligne de commande"

# --- 3. workflow tofu -----------------------------------------------------
WT=$(api "$REPO/raw/.gitea/workflows/tofu.yaml")
printf '%s' "$WT" | python3 - <<'EOF' && ok "tofu.yaml : plan (fmt, validate, plan -out, artefact) et apply gardé par workflow_dispatch + confirm + actor" \
  || ko "tofu.yaml : attendu plan (fmt -check, validate, plan -out, upload-artifact) et apply (workflow_dispatch, inputs.confirm == 'apply', gitea.actor, runs-on lab-shell)"
import sys, yaml
w = yaml.safe_load(sys.stdin); j = w["jobs"]
on = w.get("on") or w.get(True)
assert "confirm" in on["workflow_dispatch"]["inputs"]
p = j["plan"]; a = j["apply"]
sp = str(p["steps"])
assert "fmt" in sp and "validate" in sp and "-out=" in sp and "upload-artifact" in sp
cond = str(a.get("if", ""))
assert "workflow_dispatch" in cond and "confirm" in cond and "actor" in cond
assert a["runs-on"] == "lab-shell" and p["runs-on"] == "lab-shell"
assert "download-artifact" in str(a["steps"]) and "plan.bin" in str(a["steps"])
EOF

# --- 4. protection de main -----------------------------------------------
BP=$(api "$REPO/branch_protections/main")
if printf '%s' "$BP" | json 'assert d.get("branch_name")=="main"'; then
  ok "main de factura-infra protégée"
  printf '%s' "$BP" | json 'c=d["status_check_contexts"]; assert "ansible / lint" in c and "tofu / plan" in c' \
    && ok "status checks « ansible / lint » et « tofu / plan » requis" \
    || ko "status checks attendus : ansible / lint, tofu / plan"
else
  ko "aucune protection sur main de factura-infra"
fi

# --- 5. runs (API tasks si disponible) -------------------------------------
T=$(api "$REPO/actions/tasks?limit=100")
if printf '%s' "$T" | json 'assert "workflow_runs" in d'; then
  for job in check apply plan; do
    printf '%s' "$T" | json "
assert any(r.get('name')=='$job' and r.get('status')=='success' for r in d['workflow_runs'])" \
      && ok "un job $job en succès" || ko "aucun job $job réussi"
  done
else
  note "API actions/tasks indisponible : vérifie à la main check (PR), apply (main), plan"
fi

# --- 6. lab-web a reçu le changement --------------------------------------
WC=$(ssh -o BatchMode=yes -o ConnectTimeout=5 mathieu@10.10.10.11 \
      'grep -E "^\s*worker_connections" /etc/nginx/nginx.conf' 2>/dev/null | tr -d '\t;')
if [ -n "$WC" ]; then
  [ "${WC##* }" != "768" ] && ok "nginx.conf sur lab-web : $WC (appliqué par le pipeline)" \
    || note "worker_connections vaut encore 768 : la PR de l'étape 4 est-elle mergée ?"
else
  note "lab-web non joignable en ssh mathieu@ : vérification nginx.conf sautée"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
