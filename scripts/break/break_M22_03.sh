#!/usr/bin/env bash
# break_M22_03.sh — panne BF22.3 (l'API redémarre en boucle)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/M22_03/.
# Suppose L22.2 terminé (Deployment factura-api avec resources).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
export KUBECONFIG="${KUBECONFIG:-$HOMEDIR/.kube/config}"
[ -r "$KUBECONFIG" ] || export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
SAUV=/root/.breakfix-backup/M22_03
mkdir -p "$SAUV"

kubectl get deploy factura-api -n factura >/dev/null 2>&1 \
  || { echo "Deployment factura-api absent : fais d'abord L22.2" >&2; exit 1; }

if [ ! -s "$SAUV/deploy-factura-api.yaml" ]; then
  kubectl get deploy factura-api -n factura -o yaml > "$SAUV/deploy-factura-api.yaml"
fi

# --- la panne -----------------------------------------------------------
# limite mémoire bien en dessous du besoin réel de l'interpréteur Python
# (la request est abaissée aussi, sinon l'API server refuse limits < requests)
kubectl set resources deploy/factura-api -n factura -c api \
  --requests=memory=16Mi --limits=memory=20Mi >/dev/null
sleep 5

cat <<'EOF'

Symptôme attendu : les pods de l'API passent en CrashLoopBackOff, la
colonne RESTARTS grimpe. « kubectl logs --previous » montre un démarrage
normal (ligne msg="demarrage") puis plus rien : aucune erreur applicative.
Le développeur jure que l'image 1.0 est celle de la semaine dernière.
EOF
