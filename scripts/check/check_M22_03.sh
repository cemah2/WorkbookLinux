#!/usr/bin/env bash
# check_M22_03.sh — vérifie le lab L22.3 (namespace casse remis en état)
# À lancer sur lab-ops, en tant que mathieu.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification L22.3 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BASE="$HOMEDIR/lab22"
export KUBECONFIG="${KUBECONFIG:-$HOMEDIR/.kube/config}"
NS=casse
k() { kubectl -n $NS "$@" 2>/dev/null; }

# --- 1. chaque Deployment a ses réplicas disponibles ---------------------
for d in gourmand api-image api-crash api-dns; do
  W=$(k get deploy "$d" -o jsonpath='{.spec.replicas}')
  A=$(k get deploy "$d" -o jsonpath='{.status.availableReplicas}')
  if [ -z "$W" ]; then
    ko "Deployment $d absent du namespace casse"
  elif [ "${A:-0}" -ge "$W" ]; then
    ok "Deployment $d : $A/$W disponibles"
  else
    ko "Deployment $d : ${A:-0}/$W disponibles (kubectl describe pod -l app=$d)"
  fi
done
# aucun pod en erreur ou en boucle
BAD=$(k get pods -o jsonpath='{range .items[*]}{.status.containerStatuses[0].state.waiting.reason}{"\n"}{end}' \
      | grep -cE 'CrashLoopBackOff|ImagePullBackOff|ErrImagePull')
[ "$BAD" -eq 0 ] && ok "aucun pod en CrashLoop/ImagePull" \
  || ko "$BAD pod(s) encore en CrashLoopBackOff/ImagePullBackOff"
k get secret registre-lab -o jsonpath='{.type}' | grep -q dockerconfigjson \
  && ok "Secret registre-lab présent dans casse" \
  || ko "Secret registre-lab absent de casse (les Secrets ne traversent pas les namespaces)"

# --- 2. les manifestes ont été corrigés (pas seulement les objets) -------
C="$BASE/k8s/casse"
grep -q 'FACTURA_CRASH_APRES' "$C/03-crashloop.yaml" 2>/dev/null \
  && ko "03-crashloop.yaml contient encore FACTURA_CRASH_APRES" \
  || ok "03-crashloop.yaml corrigé"
grep -q 'disque: ssd' "$C/01-pending.yaml" 2>/dev/null \
  && ko "01-pending.yaml contient encore le nodeSelector disque=ssd" \
  || ok "01-pending.yaml sans nodeSelector fautif"
grep -q 'imagePullSecrets' "$C/02-imagepull.yaml" 2>/dev/null \
  && ok "02-imagepull.yaml référence un imagePullSecrets" \
  || ko "02-imagepull.yaml sans imagePullSecrets"
grep -q 'postgres.factura' "$C/04-dns.yaml" 2>/dev/null \
  && ok "04-dns.yaml : DB_HOST qualifié avec le namespace" \
  || ko "04-dns.yaml : DB_HOST doit être postgres.factura(.svc.cluster.local)"

# --- 3. l'Ingress répond ----------------------------------------------------
CODE=$(curl -sk -m 10 -o /dev/null -w '%{http_code}' \
        --resolve casse.lab.local:443:10.10.10.14 https://casse.lab.local/factures)
[ "$CODE" = 200 ] && ok "https://casse.lab.local/factures -> 200" \
  || ko "/factures renvoie $CODE (pathType, path, endpoints de api-dns ?)"

# --- 4. rapport -----------------------------------------------------------
N=$(grep -c '^|' "$BASE/rapports/debug.md" 2>/dev/null || echo 0)
[ "$N" -ge 7 ] && ok "rapport debug.md : $N lignes de tableau" \
  || ko "~/lab22/rapports/debug.md : tableau attendu, une ligne par panne (>= 5 + en-tête)"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
