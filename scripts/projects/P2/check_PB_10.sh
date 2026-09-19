#!/usr/bin/env bash
# check_PB_10.sh — vérifie le jalon PB.10 (API sur k3s, comparaison)
#   KUBECONFIG=~/.kube/factura-k3s.yaml bash check_PB_10.sh
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification PB.10 =="
REPO="${REPO:-$HOME/factura-v2}"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/factura-k3s.yaml}"
NS="${NS:-factura}"
HOST=factura-k3s.lab.local
K() { kubectl -n "$NS" "$@" 2>/dev/null; }

# --- dépôt ---------------------------------------------------------------
[ -f "$REPO/infra/envs/k3s.tfvars" ] && ok "infra/envs/k3s.tfvars" \
  || ko "infra/envs/k3s.tfvars absent"
(cd "$REPO/infra" && tofu workspace list 2>/dev/null | grep -qw k3s) \
  && ok "workspace tofu k3s" || ko "workspace k3s absent (tofu workspace new k3s)"
[ -d "$REPO/ansible/roles/k3s" ] && ok "rôle ansible k3s" \
  || ko "ansible/roles/k3s manquant"
[ -f "$REPO/ansible/playbooks/k3s.yml" ] && ok "playbook k3s.yml" \
  || ko "ansible/playbooks/k3s.yml absent"
for f in namespace configmap postgres redis api worker service ingress hpa; do
  [ -f "$REPO/k8s/$f.yaml" ] && ok "k8s/$f.yaml" || ko "k8s/$f.yaml manquant"
done
git -C "$REPO" ls-files --error-unmatch k8s/secret.yaml >/dev/null 2>&1 \
  && ko "k8s/secret.yaml est versionné (secrets dans Git !)" \
  || ok "k8s/secret.yaml non versionné"
grep -rqE 'image:.*:latest' "$REPO/k8s/" 2>/dev/null \
  && ko "une image :latest dans k8s/" || ok "aucune image :latest dans k8s/"
if [ -f "$REPO/docs/compose-vs-k3s.md" ]; then
  N=$(wc -l < "$REPO/docs/compose-vs-k3s.md")
  [ "$N" -ge 60 ] && ok "docs/compose-vs-k3s.md ($N lignes)" \
    || ko "docs/compose-vs-k3s.md trop court ($N lignes, 60 minimum)"
  grep -qiE 'recommand' "$REPO/docs/compose-vs-k3s.md" \
    && ok "comparaison : une recommandation est formulée" \
    || ko "comparaison : pas de section recommandation"
  grep -qE '[0-9]+ ?(Mo|MiB|MB)' "$REPO/docs/compose-vs-k3s.md" \
    && ok "comparaison : empreinte mémoire chiffrée" \
    || ko "comparaison : aucune mesure mémoire (free -m attendu)"
else
  ko "docs/compose-vs-k3s.md absent"
fi

# --- cluster -------------------------------------------------------------
[ -f "$KUBECONFIG" ] || { ko "kubeconfig $KUBECONFIG absent"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
[ "$(stat -c %a "$KUBECONFIG")" = 600 ] && ok "kubeconfig en 0600" \
  || ko "kubeconfig n'est pas en 0600"
grep -q '10.10.10.41' "$KUBECONFIG" && ok "kubeconfig pointe sur 10.10.10.41" \
  || ko "kubeconfig pointe encore sur 127.0.0.1"
kubectl get nodes 2>/dev/null | grep -q ' Ready' \
  && ok "nœud k3s Ready" || { ko "kubectl get nodes échoue ou nœud NotReady"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
kubectl get ns "$NS" >/dev/null 2>&1 && ok "namespace $NS" \
  || ko "namespace $NS absent"
kubectl top nodes >/dev/null 2>&1 && ok "metrics-server répond (kubectl top)" \
  || ko "kubectl top ne répond pas (metrics-server)"

# --- Deployment api ------------------------------------------------------
if K get deploy api >/dev/null; then
  D=$(K get deploy api -o json)
  R=$(echo "$D" | jq '.status.readyReplicas // 0')
  [ "$R" -ge 2 ] && ok "deployment api : $R réplicas prêts" \
    || ko "deployment api : $R réplica(s) prêt(s), 2 attendus"
  echo "$D" | jq -e '.spec.strategy.rollingUpdate.maxUnavailable == 0' >/dev/null \
    && ok "RollingUpdate maxUnavailable: 0" \
    || ko "strategy RollingUpdate avec maxUnavailable: 0 attendue"
  echo "$D" | jq -e '.spec.template.spec.containers[0].readinessProbe.httpGet.path == "/health"' \
    >/dev/null && ok "readinessProbe sur /health" \
    || ko "readinessProbe sur /health absente"
  echo "$D" | jq -e '.spec.template.spec.containers[0].livenessProbe.httpGet.path == "/version"' \
    >/dev/null && ok "livenessProbe sur /version" \
    || ko "livenessProbe sur /version absente"
  echo "$D" | jq -e '.spec.template.spec.containers[0].resources.requests.cpu' \
    >/dev/null && ok "resources.requests.cpu défini (HPA)" \
    || ko "resources.requests absent : l'HPA ne peut pas calculer"
  echo "$D" | jq -e '.spec.template.spec.containers[0].resources.limits' \
    >/dev/null && ok "resources.limits défini" || ko "resources.limits absent"
  U=$(echo "$D" | jq '.spec.template.spec.securityContext.runAsUser // .spec.template.spec.containers[0].securityContext.runAsUser // 0')
  [ "$U" = 10001 ] && ok "securityContext runAsUser 10001" \
    || ko "runAsUser n'est pas 10001 (valeur : $U)"
  echo "$D" | jq -r '.spec.template.spec.containers[0].image' | grep -q 'lab-ops' \
    && ok "image tirée du registre lab-ops" \
    || ko "l'image de l'API ne vient pas du registre lab-ops"
else
  ko "deployment api absent dans $NS"
fi
K get deploy worker >/dev/null && ok "deployment worker" || ko "deployment worker absent"
K get statefulset postgres >/dev/null && ok "statefulset postgres" \
  || ko "statefulset postgres absent"
K get pvc 2>/dev/null | grep -q Bound && ok "PVC postgres Bound (local-path)" \
  || ko "aucun PVC Bound"

# --- HPA / Ingress -------------------------------------------------------
if K get hpa api >/dev/null; then
  H=$(K get hpa api -o json)
  [ "$(echo "$H" | jq .spec.minReplicas)" = 2 ] \
    && [ "$(echo "$H" | jq .spec.maxReplicas)" = 5 ] \
    && ok "HPA min 2 / max 5" || ko "HPA : min 2 et max 5 attendus"
  echo "$H" | jq -e '.spec.metrics[0].resource.target.averageUtilization == 60' \
    >/dev/null && ok "HPA cible CPU 60 %" || ko "HPA : cible CPU 60 % attendue"
  echo "$H" | jq -r '.status.currentMetrics[0].resource.current.averageUtilization // "unknown"' \
    | grep -qE '^[0-9]+$' && ok "HPA lit une métrique CPU" \
    || ko "HPA sans métrique (<unknown>) : requests ? metrics-server ?"
else
  ko "HPA api absent"
fi
I=$(K get ingress -o json)
echo "$I" | jq -e '.items[] | select(.spec.tls != null)' >/dev/null \
  && ok "Ingress avec TLS" || ko "aucun Ingress avec section tls"
K get secret factura-tls >/dev/null && ok "secret factura-tls" \
  || ko "secret factura-tls absent"
K get secret regcred >/dev/null && ok "secret de pull regcred" \
  || ko "secret regcred absent (imagePullSecrets)"

# --- fonctionnel ---------------------------------------------------------
curl -ksS -m 6 "https://$HOST/health" | grep -q '"status":"ok"' \
  && ok "https://$HOST/health -> ok" \
  || ko "https://$HOST/health ne répond pas ok (ingress ? /etc/hosts ? ufw 443 ?)"
C=$(curl -s -m 6 -o /dev/null -w '%{http_code}' "http://$HOST/health")
[ "$C" = 301 ] || [ "$C" = 308 ] && ok "http -> https redirigé ($C)" \
  || ko "http://$HOST/health renvoie $C (redirection 301/308 attendue)"
C=$(curl -ks -m 6 -o /dev/null -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' -d '{"client":"check","montant_ht":10}' \
  "https://$HOST/api/factures")
[ "$C" = 201 ] && ok "POST /api/factures -> 201" || ko "POST /api/factures -> $C"
sleep 3
K logs deploy/worker --tail=20 2>/dev/null | grep -q 'facture trait' \
  && ok "le worker traite les jobs sur k3s" \
  || ko "le worker ne journalise aucun traitement"
curl -fsS -m 6 "http://10.10.10.14:9090/api/v1/targets" 2>/dev/null \
  | jq -r '.data.activeTargets[] | select(.labels.env=="k3s") | .health' \
  | grep -q up && ok "Prometheus scrape l'API sur k3s" \
  || ko "aucune cible env=k3s up dans Prometheus (NodePort + ufw + prometheus.yml)"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
