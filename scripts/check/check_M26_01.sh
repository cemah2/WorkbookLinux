#!/usr/bin/env bash
# check_M26_01.sh — vérifie le lab L26.1 (k3s, kubectl, registre, rollout, Helm)
# À lancer sur lab-ops, en tant que mathieu (sans sudo).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L26.1 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BASE="$HOMEDIR/lab26"
export KUBECONFIG="${KUBECONFIG:-$HOMEDIR/.kube/config}"
k() { kubectl "$@" 2>/dev/null; }

# --- 1. k3s et le nœud ---------------------------------------------------
systemctl is-active --quiet k3s.service \
  && ok "k3s.service actif" || ko "k3s.service inactif (systemctl status k3s)"
if [ -r "$KUBECONFIG" ] && [ "$(stat -c %U "$KUBECONFIG")" = "$LAB_USER" ]; then
  ok "kubeconfig $KUBECONFIG appartient à $LAB_USER"
else
  ko "kubeconfig absent ou pas à $LAB_USER (copie de /etc/rancher/k3s/k3s.yaml ?)"
fi
if k get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' \
    | grep -q True; then
  ok "nœud Ready via kubectl sans sudo"
else
  ko "kubectl get nodes ne renvoie pas un nœud Ready (droits du kubeconfig ?)"
fi

# --- 2. registre HTTP connu de containerd --------------------------------
if sudo -n true 2>/dev/null; then
  if sudo grep -rqs '10.10.10.14:5000' \
      /var/lib/rancher/k3s/agent/etc/containerd/ 2>/dev/null; then
    ok "containerd connaît le registre 10.10.10.14:5000"
  else
    ko "registre absent de la config containerd (registries.yaml, restart k3s ?)"
  fi
else
  note "sudo interactif : vérification containerd sautée"
fi

# --- 3. namespace et Secret ----------------------------------------------
k get ns factura >/dev/null && ok "namespace factura" || ko "namespace factura absent"
T=$(k get secret registre-lab -n factura -o jsonpath='{.type}')
[ "$T" = "kubernetes.io/dockerconfigjson" ] \
  && ok "Secret registre-lab de type dockerconfigjson" \
  || ko "Secret registre-lab absent ou mauvais type (create secret docker-registry)"

# --- 4. Deployment factura-api -------------------------------------------
IMG=$(k get deploy factura-api -n factura \
      -o jsonpath='{.spec.template.spec.containers[0].image}')
case "$IMG" in
  10.10.10.14:5000/factura-api:1.0) ok "image $IMG" ;;
  "") ko "Deployment factura-api absent dans factura" ;;
  *)  ko "image attendue 10.10.10.14:5000/factura-api:1.0, trouvée $IMG (rollout undo ?)" ;;
esac
AV=$(k get deploy factura-api -n factura -o jsonpath='{.status.availableReplicas}')
[ "${AV:-0}" -ge 2 ] && ok "2 réplicas disponibles" \
  || ko "réplicas disponibles : ${AV:-0}/2 (kubectl describe pod)"
k get pod -n factura -l app=factura-api \
  -o jsonpath='{.items[0].spec.imagePullSecrets[*].name}' | grep -q registre-lab \
  && ok "imagePullSecrets référence registre-lab" \
  || ko "les pods ne référencent pas imagePullSecrets registre-lab"
NREV=$(k get rs -n factura -l app=factura-api \
       -o jsonpath='{.items[*].metadata.annotations.deployment\.kubernetes\.io/revision}' \
       | wc -w)
[ "$NREV" -ge 2 ] && ok "au moins 2 révisions (ReplicaSets) du Deployment" \
  || ko "une seule révision : set image puis rollout undo attendus"

# --- 5. Helm ---------------------------------------------------------------
REV=$(helm list -n monitoring -o json 2>/dev/null \
      | python3 -c 'import sys,json; r=[x for x in json.load(sys.stdin) if x["name"]=="ksm"]; print(r[0]["revision"] if r else 0)' 2>/dev/null)
if [ "${REV:-0}" -ge 3 ]; then
  ok "release Helm ksm en révision $REV"
elif [ "${REV:-0}" -gt 0 ]; then
  ko "release ksm en révision $REV : upgrade puis rollback attendus (>= 3)"
else
  ko "release Helm ksm absente du namespace monitoring"
fi
k get pod -n monitoring -l app.kubernetes.io/name=kube-state-metrics \
  -o jsonpath='{.items[0].metadata.annotations.prometheus\.io/scrape}' \
  | grep -q true && ok "pod kube-state-metrics annoté prometheus.io/scrape" \
  || ko "annotation prometheus.io/scrape absente (podAnnotations dans ksm-values.yaml)"

# --- 6. rapport ------------------------------------------------------------
if [ -s "$BASE/rapports/rollout.md" ] \
   && grep -qi 'maxSurge' "$BASE/rapports/rollout.md"; then
  ok "rapport rollout.md rédigé"
else
  ko "~/lab26/rapports/rollout.md absent ou sans mention de maxSurge"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
