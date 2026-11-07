#!/usr/bin/env bash
# check_PB_07.sh — vérifie le jalon PB.7 (CD : staging auto, prod promue,
# bleu/vert, smoke, rollback)
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification PB.7 =="
REPO="${REPO:-$HOME/factura-v2}"
STG=10.10.10.21; PRD=10.10.10.31
r() { ssh -o BatchMode=yes -o ConnectTimeout=4 "mathieu@$1" "$2" 2>/dev/null; }

# --- workflows -----------------------------------------------------------
CI="$REPO/.gitea/workflows/ci.yaml"; [ -f "$CI" ] || CI="$REPO/.gitea/workflows/ci.yml"
CD="$REPO/.gitea/workflows/cd-prod.yaml"
[ -f "$CD" ] || CD="$REPO/.gitea/workflows/cd-prod.yml"
[ -f "$CI" ] && ok "ci.yaml présent" || ko "ci.yaml absent"
if [ -f "$CD" ]; then
  ok "cd-prod.yaml présent"
  python3 - "$CD" <<'PY' && ok "cd-prod.yaml est du YAML valide" \
    || ko "cd-prod.yaml invalide"
import sys, yaml; yaml.safe_load(open(sys.argv[1]))
PY
  grep -q 'workflow_dispatch' "$CD" && ok "cd-prod : workflow_dispatch" \
    || ko "cd-prod : pas de workflow_dispatch (promotion manuelle attendue)"
  grep -qE '^\s+tag:' "$CD" && grep -q 'required: true' "$CD" \
    && ok "cd-prod : input tag obligatoire" \
    || ko "cd-prod : inputs.tag manquant ou non obligatoire"
  grep -qE 'v\[0-9\]\+' "$CD" \
    && ok "cd-prod : garde-fou sur le format vX.Y.Z" \
    || ko "cd-prod : aucun contrôle du format du tag (regex v[0-9]+...)"
  grep -q "$STG" "$CD" && grep -q '/version' "$CD" \
    && ok "cd-prod : vérifie que le staging tourne le tag" \
    || ko "cd-prod : ne vérifie pas /version du staging avant la prod"
  grep -qE 'manifests|tags/list' "$CD" \
    && ok "cd-prod : vérifie la présence de l'image dans le registre" \
    || ko "cd-prod : ne vérifie pas que l'image existe dans le registre"
  grep -q 'always()' "$CD" \
    && ok "cd-prod : nettoyage en always()" \
    || ko "cd-prod : pas de step always() pour supprimer les secrets"
else
  ko ".gitea/workflows/cd-prod.yaml absent"
fi
if [ -f "$CI" ]; then
  grep -qE '^\s+deploy-staging:' "$CI" && ok "ci.yaml : job deploy-staging" \
    || ko "ci.yaml : pas de job deploy-staging"
  grep -q "refs/heads/main" "$CI" \
    && ok "ci.yaml : déploiement conditionné à main" \
    || ko "ci.yaml : deploy-staging n'est pas limité à refs/heads/main"
  grep -q 'smoke.sh' "$CI" && ok "ci.yaml : smoke test après déploiement" \
    || ko "ci.yaml : tools/smoke.sh n'est pas appelé"
  grep -qE 'secrets\.(VAULT_PASS|DEPLOY_SSH_KEY)' "$CI" \
    && ok "ci.yaml : VAULT_PASS / DEPLOY_SSH_KEY depuis les secrets" \
    || ko "ci.yaml : secrets VAULT_PASS/DEPLOY_SSH_KEY non utilisés"
fi
[ -f "$REPO/ansible/inventory/ci/staging.ini" ] \
  && ok "inventaire CI ansible/inventory/ci/staging.ini versionné" \
  || ko "ansible/inventory/ci/staging.ini absent (comment le runner connaît-il les IP ?)"

# --- rôle bleu/vert -------------------------------------------------------
ROLE="$REPO/ansible/roles/factura_compose"
grep -rq 'rescue:' "$ROLE/tasks" 2>/dev/null \
  && ok "rôle factura_compose : block/rescue présent" \
  || ko "rôle factura_compose : pas de rescue (rollback automatique ?)"
grep -rqE 'switch\.sh' "$ROLE/tasks" 2>/dev/null \
  && ok "rôle : appelle switch.sh" || ko "rôle : n'appelle pas bin/switch.sh"
[ -f "$REPO/docs/runbook-deploy.md" ] \
  && grep -qiE 'rollback|arrière|switch' "$REPO/docs/runbook-deploy.md" \
  && ok "docs/runbook-deploy.md présent avec la procédure de retour arrière" \
  || ko "docs/runbook-deploy.md absent ou sans procédure de retour arrière"
grep -qE '^promote:' "$REPO/Makefile" 2>/dev/null \
  && ok "Makefile : cible promote" || ko "Makefile : pas de cible promote"

# --- état sur les VM -----------------------------------------------------
for e in staging prod; do
  case $e in staging) W=$STG;; *) W=$PRD;; esac
  echo "-- $e ($W)"
  # /srv/factura est en 0750 deploy : lecture par sudo (mathieu)
  r "$W" 'sudo test -x /srv/factura/bin/switch.sh' \
    && ok "$e : /srv/factura/bin/switch.sh exécutable" \
    || ko "$e : bin/switch.sh absent ou non exécutable"
  ST=$(r "$W" 'sudo cat /srv/factura/state.env')
  ACT=$(echo "$ST" | awk -F= '/^ACTIVE=/{print $2}')
  [ "$ACT" = blue ] || [ "$ACT" = green ] \
    && ok "$e : state.env ACTIVE=$ACT" \
    || { ko "$e : state.env sans ACTIVE=blue|green"; continue; }
  V80=$(curl -fsS -m 5 "http://$W/version" 2>/dev/null | jq -r .color)
  [ "$V80" = "$ACT" ] \
    && ok "$e : le port 80 sert la couleur active ($ACT)" \
    || ko "$e : /version sur :80 dit '$V80', state.env dit '$ACT'"
  P=$([ "$ACT" = blue ] && echo 8081 || echo 8082)
  curl -fsS -m 5 "http://$W:$P/health" >/dev/null 2>&1 \
    && ok "$e : port direct $P de la couleur active répond" \
    || ko "$e : http://$W:$P/health ne répond pas (ports directs ? ufw ?)"
  T=$(curl -fsS -m 5 "http://$W/version" | jq -r .version)
  if bash "$REPO/tools/smoke.sh" "http://$W" "$T" >/tmp/smoke.$$ 2>&1; then
    ok "$e : smoke.sh passe (version $T)"
  else
    ko "$e : smoke.sh échoue ($(grep FAIL /tmp/smoke.$$ | head -1))"
  fi
  rm -f /tmp/smoke.$$
  r "$W" 'sudo grep -c "switch ->" /srv/factura/switch.log' \
    | grep -qE '^[1-9]' \
    && ok "$e : switch.log contient au moins une bascule" \
    || ko "$e : switch.log vide (aucune bascule bleu/vert effectuée ?)"
done
r "$STG" 'sudo grep -q "rollback" /srv/factura/switch.log' \
  && ok "staging : une ligne rollback dans switch.log (test v9.9.9)" \
  || ko "staging : aucune ligne rollback dans switch.log (test de rollback à faire)"
[ "$(curl -fsS -m 5 "http://$PRD/version" | jq -r .version)" != "v9.9.9" ] \
  && ok "prod : ne tourne pas v9.9.9" || ko "prod : tourne v9.9.9 (rollback raté)"
[ "$(curl -fsS -m 5 "http://$STG/version" | jq -r .version)" != "v9.9.9" ] \
  && ok "staging : ne tourne pas v9.9.9" || ko "staging : tourne v9.9.9"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
