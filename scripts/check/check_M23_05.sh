#!/usr/bin/env bash
# check_M23_05.sh — vérifie le lab L23.5 (rôle node_exporter réutilisable)
# À lancer sur lab-adm, en tant que mathieu. QUICK=1 saute la 2e exécution.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
has()  { grep "$@" >/dev/null; }
echo "== Vérification L23.5 =="

export PATH="$HOME/.local/bin:$PATH"
BASE="$HOME/lab23"
cd "$BASE" 2>/dev/null || { ko "$BASE absent (setup_M23.sh)"; exit 1; }
command -v ansible-playbook >/dev/null || { ko "ansible introuvable"; exit 1; }
R=roles/node_exporter
[ -d "$R" ] && ok "$R présent" || { ko "$R absent (ansible-galaxy role init)"; exit 1; }

# --- 1. structure ----------------------------------------------------------
for f in defaults/main.yml tasks/main.yml tasks/install.yml tasks/service.yml \
         tasks/firewall_Debian.yml tasks/firewall_RedHat.yml \
         handlers/main.yml meta/main.yml meta/argument_specs.yml README.md \
         templates/node_exporter.service.j2; do
  [ -f "$R/$f" ] && ok "$f" || ko "$R/$f manquant"
done
for d in tests vars; do
  [ -e "$R/$d" ] && ko "$R/$d existe encore (à supprimer, énoncé étape 1)" \
    || ok "$R/$d supprimé"
done

# --- 2. contenu des defaults et de l'argument_specs -----------------------
res=$(python3 - "$R" <<'EOF'
import sys, yaml
r = sys.argv[1]; rc = 0
def ok(m): print(f"  [ OK ] {m}")
def ko(m):
    global rc; rc += 1; print(f"  [FAIL] {m}")
d = yaml.safe_load(open(f"{r}/defaults/main.yml")) or {}
attendu = {"node_exporter_version": "1.9.1", "node_exporter_listen": "0.0.0.0:9100",
           "node_exporter_allowed_cidr": "10.10.10.14/32",
           "node_exporter_manage_firewall": True, "node_exporter_extra_args": []}
for k, v in attendu.items():
    if k in d and (str(d[k]) == str(v) or d[k] == v): ok(f"defaults : {k}")
    else: ko(f"defaults : {k} absent ou valeur inattendue ({d.get(k)!r})")
if "node_exporter_user" in d: ok("defaults : node_exporter_user")
else: ko("defaults : node_exporter_user absent")
spec = yaml.safe_load(open(f"{r}/meta/argument_specs.yml")) or {}
opts = spec.get("argument_specs", {}).get("main", {}).get("options", {})
for k in attendu:
    o = opts.get(k)
    if not o: ko(f"argument_specs : {k} non documenté"); continue
    if not o.get("type"): ko(f"argument_specs : {k} sans type")
    elif not o.get("description"): ko(f"argument_specs : {k} sans description")
    else: ok(f"argument_specs : {k} ({o['type']})")
if opts.get("node_exporter_manage_firewall", {}).get("type") == "bool": ok("manage_firewall typé bool")
else: ko("node_exporter_manage_firewall doit être de type bool")
if opts.get("node_exporter_extra_args", {}).get("type") == "list": ok("extra_args typé list")
else: ko("node_exporter_extra_args doit être de type list")
meta = yaml.safe_load(open(f"{r}/meta/main.yml")) or {}
gi = meta.get("galaxy_info", {})
if gi.get("platforms") and gi.get("min_ansible_version"): ok("meta/main.yml : platforms et min_ansible_version")
else: ko("meta/main.yml : platforms ou min_ansible_version manquant")
main = open(f"{r}/tasks/main.yml").read()
if "include_tasks" in main and "os_family" in main: ok("tasks/main.yml : include_tasks dynamique par os_family")
else: ko("tasks/main.yml : pas d'include_tasks construit avec ansible_facts['os_family']")
tpl = open(f"{r}/templates/node_exporter.service.j2").read()
if "node_exporter_extra_args" in tpl and "join" in tpl: ok("template : extra_args | join(' ')")
else: ko("template : node_exporter_extra_args | join(' ') absent")
EOF
)
printf '%s\n' "$res"
PASS=$((PASS + $(printf '%s\n' "$res" | grep -c '\[ OK \]')))
FAIL=$((FAIL + $(printf '%s\n' "$res" | grep -c '\[FAIL\]')))
grep -Eiq 'ip|10\.10\.10\.|lab-' "$R/defaults/main.yml" \
  && note "defaults contient une IP ou un nom du lab : acceptable si c'est un défaut documenté"
grep -rqE 'lab-(web|db|rhel|ops|adm)' "$R/tasks" "$R/templates" 2>/dev/null \
  && ko "un nom d'hôte du lab est codé en dur dans tasks/ ou templates/" \
  || ok "aucun nom d'hôte du lab dans tasks/ ni templates/"
grep -q node_exporter "$R/README.md" && grep -Eq 'node_exporter_version' "$R/README.md" \
  && ok "README documente les variables" || ko "README ne décrit pas les variables du rôle"

# --- 3. playbooks ----------------------------------------------------------
PB=playbooks/monitoring.yml
[ -f "$PB" ] && ok "$PB présent" || ko "$PB absent"
grep -q 'node_exporter' "$PB" 2>/dev/null && ok "$PB applique le rôle" \
  || ko "$PB n'appelle pas le rôle node_exporter"
if [ -f playbooks/baseline.yml ]; then
  grep -q 'get_url' playbooks/baseline.yml \
    && ko "baseline.yml contient encore les tâches node_exporter (get_url)" \
    || ok "baseline.yml ne contient plus de tâche node_exporter"
  grep -q 'node_exporter' playbooks/baseline.yml \
    && ok "baseline.yml appelle le rôle node_exporter" \
    || ko "baseline.yml n'appelle pas le rôle node_exporter"
fi

# --- 4. exécution, idempotence, validation des arguments -------------------
if [ "${QUICK:-0}" = 1 ]; then note "QUICK=1 : seconde exécution non testée"
else
  out=$(ansible-playbook "$PB" 2>&1)
  [ "$(printf '%s\n' "$out" | grep -c 'changed=0 .*failed=0')" -eq 4 ] \
    && ok "monitoring.yml : changed=0 failed=0 sur les 4 hôtes" \
    || ko "monitoring.yml n'est pas changed=0 partout (relis le recap)"
fi
out=$(ansible-playbook "$PB" -e node_exporter_manage_firewall=oui 2>&1)
printf '%s\n' "$out" | has -i 'not a valid boolean' \
  && ok "argument_specs refuse manage_firewall=oui" \
  || ko "manage_firewall=oui n'est pas refusé (argument_specs : type bool ?)"
r=$(ansible all -m ansible.builtin.shell -a 'curl -s localhost:9100/metrics | head -1' \
      -o 2>/dev/null)
[ "$(printf '%s\n' "$r" | grep -c '# HELP')" -eq 4 ] \
  && ok "node_exporter répond sur :9100 partout" \
  || ko "node_exporter ne répond pas sur un hôte"

# --- 5. lint ---------------------------------------------------------------
if command -v ansible-lint >/dev/null; then
  ansible-lint -q "$R" >/dev/null 2>&1 && ok "ansible-lint muet sur $R" \
    || ko "ansible-lint signale des problèmes sur $R"
else note "ansible-lint absent, lint non testé"; fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
