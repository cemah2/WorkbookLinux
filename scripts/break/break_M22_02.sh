#!/usr/bin/env bash
# break_M22_02.sh — panne BF22.2 (le rollout ne finit jamais)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/M22_02/.
# Suppose L22.2 terminé (Deployment factura-api avec readiness sur /pret).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
export KUBECONFIG="${KUBECONFIG:-$HOMEDIR/.kube/config}"
[ -r "$KUBECONFIG" ] || export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
SAUV=/root/.breakfix-backup/M22_02
mkdir -p "$SAUV"

kubectl get deploy factura-api -n factura >/dev/null 2>&1 \
  || { echo "Deployment factura-api absent : fais d'abord L22.2" >&2; exit 1; }
kubectl get deploy factura-api -n factura \
  -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.port}' \
  | grep -q . || { echo "pas de readinessProbe httpGet sur l'API : L22.2 étape 3" >&2; exit 1; }

if [ ! -s "$SAUV/deploy-factura-api.yaml" ]; then
  kubectl get deploy factura-api -n factura -o yaml > "$SAUV/deploy-factura-api.yaml"
fi

# --- la panne -----------------------------------------------------------
# la readiness probe vise un port sur lequel rien n'écoute
kubectl patch deploy factura-api -n factura --type=json -p '[
  {"op":"replace",
   "path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port",
   "value":8081}]' >/dev/null
sleep 5

cat <<'EOF'

Symptôme attendu : « kubectl rollout status deploy/factura-api -n factura »
reste sur « Waiting for deployment "factura-api" rollout to finish: 1 out
of 2 new replicas have been updated... ». Trois pods de l'API : deux
anciens 1/1 et un nouveau 0/1 Running, sans redémarrage. Le site
fonctionne. L'image n'a pas changé.
EOF
