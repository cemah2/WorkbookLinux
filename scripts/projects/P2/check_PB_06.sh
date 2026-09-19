#!/usr/bin/env bash
# check_PB_06.sh — vérifie le jalon PB.6 (pipeline CI)
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification PB.6 =="
REPO="${REPO:-$HOME/factura-v2}"
GITEA="${GITEA:-http://lab-ops.lab.local:3000}"
OWNER="${OWNER:-mathieu}"
W="$REPO/.gitea/workflows/ci.yaml"
[ -f "$W" ] || W="$REPO/.gitea/workflows/ci.yml"
[ -f "$W" ] && ok "workflow CI présent" || { ko ".gitea/workflows/ci.yaml absent"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
python3 - "$W" <<'PY' && ok "ci.yaml est du YAML valide" || ko "ci.yaml invalide"
import sys, yaml; yaml.safe_load(open(sys.argv[1]))
PY
for j in lint test build; do
  grep -qE "^\s+$j[a-z-]*:" "$W" && ok "job $j" || ko "job $j absent"
done
grep -qE 'pre-commit|gitleaks|yamllint' "$W" && ok "lint exécuté en CI" \
  || ko "aucun lint en CI"
grep -q pytest "$W" && ok "pytest exécuté en CI" || ko "pas de pytest en CI"
grep -qE 'trivy|grype' "$W" && ok "scan d'image (trivy/grype)" \
  || ko "pas de scan d'image"
grep -qE 'severity.*(HIGH|CRITICAL)|--exit-code 1' "$W" \
  && ok "le scan est bloquant sur HIGH/CRITICAL" \
  || ko "le scan n'est pas bloquant (--exit-code 1 --severity HIGH,CRITICAL)"
grep -q 'docker push' "$W" || grep -q 'push: true' "$W" \
  && ok "push vers le registre" || ko "pas de docker push"
grep -qE 'needs:' "$W" && ok "les jobs sont chaînés (needs)" \
  || ko "pas de needs : le build ne dépend pas des tests"
grep -qE 'secrets\.[A-Z_]+' "$W" && ok "les secrets viennent de secrets.*" \
  || ko "aucun secrets.* : où est le token du registre ?"
grep -qE 'sha-|github\.sha|gitea\.sha' "$W" \
  && ok "tag d'image dérivé du commit" \
  || ko "les images ne sont pas taguées par commit (latest seul = non traçable)"
grep -qE 'lab-ops(\.lab\.local)?:3000' "$W" \
  && ok "registre lab-ops:3000 ciblé" || ko "registre lab-ops:3000 non ciblé"
grep -qE 'runs-on:\s*ops-host' "$W" \
  && ok "runs-on: ops-host" || ko "runs-on n'est pas ops-host (label du runner)"

# --- côté Gitea ----------------------------------------------------------
if curl -fsS -m 5 "$GITEA/api/v1/repos/$OWNER/factura" >/dev/null 2>&1 \
   || [ -n "${GITEA_TOKEN:-}" ]; then
  H=(); [ -n "${GITEA_TOKEN:-}" ] && H=(-H "Authorization: token $GITEA_TOKEN")
  RUNS=$(curl -fsS -m 5 "${H[@]}" \
    "$GITEA/api/v1/repos/$OWNER/factura/actions/tasks?limit=10" 2>/dev/null)
  echo "$RUNS" | grep -q '"status":"success"' \
    && ok "au moins un run CI en succès" \
    || ko "aucun run CI en succès (Gitea > Actions ; GITEA_TOKEN pour l'API)"
  TAGS=$(curl -fsS -m 5 "${H[@]}" \
    "$GITEA/v2/$OWNER/factura-api/tags/list" 2>/dev/null)
  echo "$TAGS" | grep -qE 'sha-[0-9a-f]{7}' \
    && ok "le registre contient des tags sha-xxxxxxx pour factura-api" \
    || ko "aucun tag sha-* dans le registre (push ? droits ?)"
  echo "$TAGS" | grep -qE '"v[0-9]+\.[0-9]+\.[0-9]+"' \
    && ok "au moins une version vX.Y.Z publiée" \
    || ko "aucun tag vX.Y.Z : git tag v2.0.0 && git push --tags"
  curl -fsS -m 5 "${H[@]}" "$GITEA/v2/$OWNER/factura-worker/tags/list" \
    2>/dev/null | grep -q tags \
    && ok "image factura-worker publiée" || ko "factura-worker non publiée"
else
  ko "Gitea injoignable sur $GITEA (ou dépôt privé : exporte GITEA_TOKEN)"
fi
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
