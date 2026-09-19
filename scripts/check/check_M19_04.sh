#!/usr/bin/env bash
# check_M19_04.sh — vérifie le lab L19.4 (rolling update avec santé)
# À lancer sur lab-adm, en tant que mathieu. VERSION=2.1.0 par défaut.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
has()  { grep "$@" >/dev/null; }
echo "== Vérification L19.4 =="

export PATH="$HOME/.local/bin:$PATH"
BASE="$HOME/lab19"
V="${VERSION:-2.1.0}"
cd "$BASE" 2>/dev/null || { ko "$BASE absent (setup_M19.sh)"; exit 1; }
command -v ansible-playbook >/dev/null || { ko "ansible introuvable"; exit 1; }
PB=playbooks/rolling.yml
[ -f "$PB" ] && ok "$PB présent" || { ko "$PB absent"; exit 1; }

# --- 1. structure du playbook (résultat observable via --list-*) -----------
python3 - "$PB" <<'EOF' && ok "serial: 1 et max_fail_percentage: 0 sur le play web" \
  || ko "serial: 1 / max_fail_percentage: 0 absents du play (énoncé, étape 1)"
import sys, yaml
plays = yaml.safe_load(open(sys.argv[1]))
ok_ = any(str(p.get('serial')) == '1' and p.get('max_fail_percentage') == 0
          for p in plays if isinstance(p, dict))
sys.exit(0 if ok_ else 1)
EOF
grep -Eq '^\s*(pre_tasks|post_tasks):' "$PB" && grep -Eq 'pre_tasks' "$PB" \
  && grep -Eq 'post_tasks' "$PB" && ok "pre_tasks et post_tasks présents" \
  || ko "pre_tasks / post_tasks manquants"
grep -q 'flush_handlers' "$PB" && ok "meta: flush_handlers présent" \
  || ko "pas de flush_handlers : le reload arriverait après la vérification"
grep -Eq 'until:' "$PB" && grep -Eq 'uri:' "$PB" \
  && ok "vérification uri avec until" || ko "uri + until absents des post_tasks"
grep -q 'run_once' "$PB" && ok "tâche run_once (journal)" \
  || ko "pas de run_once pour le journal des déploiements"
hosts=$(ansible-playbook "$PB" --list-hosts 2>/dev/null)
printf '%s\n' "$hosts" | has 'lab-web' && printf '%s\n' "$hosts" | has 'lab-rhel' \
  && ok "--list-hosts montre lab-web et lab-rhel" \
  || ko "--list-hosts ne montre pas les deux frontaux (hosts: web ?)"

# --- 2. les deux frontaux servent la version -------------------------------
for h in lab-web:10.10.10.11 lab-rhel:10.10.10.13; do
  n=${h%%:*}; ip=${h##*:}
  body=$(curl -sk -m 5 "https://$ip/" 2>/dev/null)
  printf '%s\n' "$body" | has "vitrine $V sur $n" \
    && ok "$n : corps « vitrine $V sur $n »" \
    || ko "$n : le corps ne contient pas « vitrine $V sur $n »"
  curl -skI -m 5 "https://$ip/" 2>/dev/null | has -i "x-vitrine-version: $V" \
    && ok "$n : en-tête X-Vitrine-Version: $V" \
    || ko "$n : en-tête X-Vitrine-Version != $V (vhost redéployé + reload ?)"
done

# --- 3. journal des déploiements -------------------------------------------
LOG=rapports/deploiements.log
if [ -f "$LOG" ]; then
  n=$(grep -c " $V " "$LOG")
  [ "$n" -ge 2 ] && ok "$LOG : $n lignes pour $V (une par lot)" \
    || ko "$LOG : $n ligne(s) pour $V, attendu >= 2 (run_once par lot)"
  grep " $V " "$LOG" | has -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' \
    && ok "lignes datées en ISO 8601" || ko "les lignes ne commencent pas par une date ISO"
  grep " $V " "$LOG" | has 'lab-web' && grep " $V " "$LOG" | has 'lab-rhel' \
    && ok "les deux hôtes apparaissent dans le journal" \
    || ko "un des deux hôtes manque dans le journal (ansible_play_batch)"
else ko "$LOG absent"; fi

# --- 4. la validation de version refuse un mauvais format -----------------
out=$(ansible-playbook "$PB" -e vitrine_version=abc --check 2>&1)
printf '%s\n' "$out" | has -E 'failed=1|FAILED' \
  && ok "vitrine_version=abc est refusé (assert)" \
  || ko "vitrine_version=abc n'est pas refusé par l'assert des pre_tasks"

# --- 5. lint ---------------------------------------------------------------
if command -v ansible-lint >/dev/null; then
  ansible-lint -q "$PB" >/dev/null 2>&1 && ok "ansible-lint muet sur $PB" \
    || ko "ansible-lint signale des problèmes sur $PB"
else note "ansible-lint absent, lint non testé"; fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
