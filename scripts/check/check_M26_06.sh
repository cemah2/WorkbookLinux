#!/usr/bin/env bash
# check_M26_06.sh — vérifie le défi D26 (kustomize, PDB/HPA, SLO, règles
# burn rate testées, runbooks, tableau SLO, verif-prod.sh, post-mortem).
# À lancer sur lab-ops, en tant que mathieu.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification D26 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BASE="$HOMEDIR/lab26"
OBS=/opt/observabilite
PROM=http://10.10.10.14:9090
GRAF=http://10.10.10.14:3000
export KUBECONFIG="${KUBECONFIG:-$HOMEDIR/.kube/config}"
k() { kubectl -n factura "$@" 2>/dev/null; }

# --- 1. manifestes kustomize -------------------------------------------------
KZ="$BASE/prod/kustomization.yaml"
[ -s "$KZ" ] && ok "kustomization.yaml présent" || ko "$KZ absent"
python3 - "$KZ" <<'EOF' 2>/dev/null && ok "kustomization : namespace factura, images, secretGenerator" \
  || ko "kustomization.yaml : attendu namespace: factura, images: (newTag), secretGenerator ou Secrets en resources"
import sys, yaml
c = yaml.safe_load(open(sys.argv[1]))
assert c.get("namespace") == "factura"
assert c.get("images") and any("newTag" in i for i in c["images"])
assert c.get("secretGenerator") or any("secret" in r for r in c.get("resources", []))
EOF
OUT=$(kubectl kustomize "$BASE/prod/" 2>/dev/null)
if [ -n "$OUT" ]; then
  ok "kubectl kustomize construit sans erreur"
  for kind in PodDisruptionBudget HorizontalPodAutoscaler Ingress StatefulSet; do
    printf '%s' "$OUT" | grep -q "^kind: $kind$" && ok "  contient $kind" \
      || ko "  $kind absent du rendu kustomize"
  done
  printf '%s' "$OUT" | grep -c '^kind: Secret$' | grep -qE '^[3-9]' \
    && ok "  3 Secrets générés (postgres, registre, TLS)" \
    || ko "  moins de 3 Secrets dans le rendu : mot de passe, registre, TLS attendus"
else
  ko "kubectl kustomize ~/lab26/prod/ échoue"
fi
MA=$(k get pdb factura-api -o jsonpath='{.spec.minAvailable}')
[ "$MA" = 1 ] && ok "PDB factura-api minAvailable=1" || ko "PDB factura-api absent ou minAvailable != 1"
k get hpa factura-api -o jsonpath='{.spec.minReplicas} {.spec.maxReplicas}' \
  | grep -q '^2 4$' && ok "HPA factura-api 2..4 réplicas" \
  || ko "HPA factura-api absent ou bornes != 2..4"
A=$(k get deploy factura-api -o jsonpath='{.status.availableReplicas}')
[ "${A:-0}" -ge 2 ] && ok "API : $A réplicas disponibles" || ko "API : ${A:-0} disponibles"

# --- 2. SLO et règles ---------------------------------------------------------
grep -qiE 'burn ?rate' "$BASE/rapports/slo.md" 2>/dev/null \
  && grep -q '99,5\|99.5' "$BASE/rapports/slo.md" \
  && ok "slo.md : SLO 99,5 % et burn rate" \
  || ko "~/lab26/rapports/slo.md absent ou sans SLO 99,5 % / burn rate"
[ -s "$OBS/prometheus/rules/slo.yml" ] && ok "rules/slo.yml présent" \
  || ko "$OBS/prometheus/rules/slo.yml absent"
RULES=$(curl -s -m 10 "$PROM/api/v1/rules")
for r in slo:factura_errors:ratio_rate5m slo:factura_errors:ratio_rate30m \
         slo:factura_errors:ratio_rate1h slo:factura_errors:ratio_rate6h; do
  printf '%s' "$RULES" | grep -q "\"name\":\"$r\"" && ok "règle $r chargée" \
    || ko "règle $r absente de Prometheus (reload ?)"
done
printf '%s' "$RULES" | python3 -c '
import sys, json
g = json.load(sys.stdin)["data"]["groups"]
al = [r for x in g for r in x["rules"] if r["type"] == "alerting"
      and "slo" in str(r.get("labels", {})) + r["query"]]
q = lambda r: r["query"].replace(" ", "")
assert any(r["labels"].get("severity") == "page"
           and ("14.4*" in q(r) or "0.072" in q(r)) for r in al)
assert any(r["labels"].get("severity") == "ticket"
           and ("(6*" in q(r) or ">6*" in q(r) or "0.03" in q(r)) for r in al)
assert all("runbook_url" in r["annotations"] for r in al)
' 2>/dev/null && ok "alertes burn rate page (14,4) et ticket (6) avec runbook_url" \
  || ko "alertes multi-fenêtre : page à 14,4 et ticket à 6, chacune avec runbook_url"
T=$(ls "$OBS"/prometheus/tests/*.yml 2>/dev/null | head -1)
if [ -n "$T" ]; then
  (cd "$OBS" && docker compose exec -T prometheus promtool test rules \
     "/etc/prometheus/tests/$(basename "$T")" >/dev/null 2>&1) \
    && ok "promtool test rules : SUCCESS ($(basename "$T"))" \
    || ko "promtool test rules échoue sur $(basename "$T")"
else
  ko "aucun fichier de test dans $OBS/prometheus/tests/ (hors du glob rules/*.yml)"
fi

# --- 3. runbooks ------------------------------------------------------------
for f in api-erreurs.md instance-down.md; do
  if [ -s "$BASE/runbooks/$f" ] && grep -qi 'escalad' "$BASE/runbooks/$f"; then
    ok "runbook $f (avec section escalade)"
  else
    ko "~/lab26/runbooks/$f absent ou sans section « escalade »"
  fi
done

# --- 4. tableau SLO ------------------------------------------------------------
curl -s -m 10 -u admin:labpass "$GRAF/api/search?query=SLO" \
  | grep -q 'Lab — SLO factura' && ok "tableau « Lab — SLO factura » présent" \
  || ko "tableau « Lab — SLO factura » absent (fichier dans grafana/dashboards/)"

# --- 5. script de conformité ----------------------------------------------------
V="$BASE/bin/verif-prod.sh"
if [ -x "$V" ]; then
  head -5 "$V" | grep -q 'set -euo pipefail' && ok "verif-prod.sh : set -euo pipefail" \
    || ko "verif-prod.sh sans set -euo pipefail"
  if bash "$V" >/tmp/verif-prod.out 2>&1; then
    ok "verif-prod.sh passe (code 0)"
  else
    ko "verif-prod.sh échoue : $(grep -c FAIL /tmp/verif-prod.out) point(s) en FAIL"
  fi
  grep -qE '\[ OK \]|\[FAIL\]' /tmp/verif-prod.out && ok "sortie [ OK ]/[FAIL]" \
    || ko "verif-prod.sh doit afficher [ OK ] ou [FAIL] par point"
else
  ko "$V absent ou non exécutable"
fi

# --- 6. post-mortem ------------------------------------------------------------
PM="$BASE/rapports/postmortem.md"
[ -s "$PM" ] && grep -qi 'chronolog' "$PM" && grep -qi 'action' "$PM" \
  && ok "post-mortem rédigé (chronologie, actions)" \
  || ko "~/lab26/rapports/postmortem.md absent ou sans chronologie/actions"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
