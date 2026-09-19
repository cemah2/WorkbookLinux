#!/usr/bin/env bash
# break_M26_01.sh — panne BF26.1 (l'API répond 502)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/M26_01/.
# Suppose L26.2 terminé (namespace factura, Service factura-api, front).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
export KUBECONFIG="${KUBECONFIG:-$HOMEDIR/.kube/config}"
[ -r "$KUBECONFIG" ] || export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
SAUV=/root/.breakfix-backup/M26_01
mkdir -p "$SAUV"

kubectl get svc factura-api -n factura >/dev/null 2>&1 \
  || { echo "Service factura-api absent : fais d'abord L26.2" >&2; exit 1; }

if [ ! -s "$SAUV/svc-factura-api.yaml" ]; then
  kubectl get svc factura-api -n factura -o yaml > "$SAUV/svc-factura-api.yaml"
fi

# --- la panne -----------------------------------------------------------
# « un label pour le tri dans Lens » : ajouté au selector du Service.
kubectl patch svc factura-api -n factura --type=merge \
  -p '{"spec":{"selector":{"app":"factura-api","equipe":"compta"}}}' >/dev/null
sleep 3

cat <<'EOF'

Symptôme attendu : https://factura.lab.local/ répond « factura front »,
mais /api/factures (et /api/) renvoie 502 Bad Gateway, page nginx.
Les pods de l'API sont Running 1/1, sans redémarrage, et leurs logs ne
montrent aucune requête entrante. Un collègue dit avoir « juste ajusté
un label pour le tri dans Lens » ce matin.
EOF
