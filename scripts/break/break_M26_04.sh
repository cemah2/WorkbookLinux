#!/usr/bin/env bash
# break_M26_04.sh — panne BF26.4 (ImagePullBackOff après redémarrage)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/M26_04/.
# Suppose L26.2 terminé (namespace factura, Secret registre-lab, API).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
export KUBECONFIG="${KUBECONFIG:-$HOMEDIR/.kube/config}"
[ -r "$KUBECONFIG" ] || export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
SAUV=/root/.breakfix-backup/M26_04
mkdir -p "$SAUV"

kubectl get deploy factura-api -n factura >/dev/null 2>&1 \
  || { echo "Deployment factura-api absent : fais d'abord L26.2" >&2; exit 1; }

if [ ! -s "$SAUV/secret-registre-lab.yaml" ]; then
  kubectl get secret registre-lab -n factura -o yaml \
    > "$SAUV/secret-registre-lab.yaml" 2>/dev/null || true
fi
REPL=$(kubectl get deploy factura-api -n factura -o jsonpath='{.spec.replicas}')
echo "${REPL:-2}" > "$SAUV/replicas"

# --- la panne -----------------------------------------------------------
# 1. le Secret de registre disparaît du namespace factura
kubectl delete secret registre-lab -n factura --ignore-not-found >/dev/null
# 2. le cache d'images du nœud est purgé (« pour libérer du disque »)
kubectl scale deploy/factura-api -n factura --replicas=0 >/dev/null
for i in $(seq 1 30); do
  [ "$(kubectl get pods -n factura -l app=factura-api --no-headers 2>/dev/null | wc -l)" -eq 0 ] && break
  sleep 2
done
for img in $(k3s crictl images -q 2>/dev/null); do
  if k3s crictl inspecti "$img" 2>/dev/null | grep -q 'factura-api'; then
    k3s crictl rmi "$img" >/dev/null 2>&1 || true
  fi
done
# 3. « rollout restart » : les pods reviennent
kubectl scale deploy/factura-api -n factura --replicas="${REPL:-2}" >/dev/null
sleep 5

cat <<'EOF'

Symptôme attendu : après le redémarrage de l'API, les nouveaux pods
restent en ErrImagePull puis ImagePullBackOff. L'image existe : un
« docker pull 10.10.10.14:5000/factura-api:1.0 » avec login fonctionne
depuis lab-ops. Le namespace casse n'est pas affecté.
EOF
