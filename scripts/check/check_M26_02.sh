#!/usr/bin/env bash
# check_M26_02.sh — vérifie le lab L26.2 (factura : postgres, API, front,
# Ingress TLS, NetworkPolicy). À lancer sur lab-ops, en tant que mathieu.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification L26.2 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
export KUBECONFIG="${KUBECONFIG:-$HOMEDIR/.kube/config}"
NS=factura
k() { kubectl -n $NS "$@" 2>/dev/null; }
jp() { k get "$1" "$2" -o jsonpath="$3"; }

# --- 1. PostgreSQL ---------------------------------------------------------
R=$(jp statefulset postgres '{.status.readyReplicas}')
[ "${R:-0}" -eq 1 ] && ok "StatefulSet postgres 1/1" \
  || ko "StatefulSet postgres pas prêt (describe pod postgres-0, readiness pg_isready)"
P=$(jp pvc donnees-postgres-0 '{.status.phase}')
[ "$P" = Bound ] && ok "PVC donnees-postgres-0 Bound" \
  || ko "PVC donnees-postgres-0 absent ou non Bound (volumeClaimTemplates ?)"
jp statefulset postgres '{.spec.template.spec.containers[0].env[*].valueFrom.secretKeyRef.name}' \
  | grep -q postgres-auth && ok "variables PostgreSQL tirées du Secret postgres-auth" \
  || ko "POSTGRES_USER/PASSWORD ne viennent pas du Secret postgres-auth"

# --- 2. API ---------------------------------------------------------------
A=$(jp deploy factura-api '{.status.availableReplicas}')
[ "${A:-0}" -ge 2 ] && ok "Deployment factura-api : $A réplicas disponibles" \
  || ko "factura-api : ${A:-0}/2 disponibles (describe pod : readiness /pret ?)"
C=$(jp deploy factura-api '{.spec.template.spec.containers[0]}')
printf '%s' "$C" | python3 -c '
import sys, json
c = json.load(sys.stdin)
assert c["livenessProbe"]["httpGet"]["path"] == "/sante"
assert c["readinessProbe"]["httpGet"]["path"] == "/pret"
assert c["resources"]["limits"]["memory"]
assert c["resources"]["requests"]["memory"]
assert any(e.get("configMapRef", {}).get("name") == "factura-api-config"
           for e in c.get("envFrom", []))
' 2>/dev/null && ok "API : probes /sante et /pret, limites, envFrom ConfigMap" \
  || ko "API : il manque liveness /sante, readiness /pret, resources ou envFrom"
DB=$(jp configmap factura-api-config '{.data.DB_HOST}')
case "$DB" in
  postgres|postgres.factura|postgres.factura.svc|postgres.factura.svc.cluster.local)
    ok "DB_HOST=$DB" ;;
  *) ko "DB_HOST vaut « $DB », attendu le nom du Service postgres" ;;
esac

# --- 3. front, Ingress, TLS ---------------------------------------------
F=$(jp deploy front '{.status.availableReplicas}')
[ "${F:-0}" -ge 1 ] && ok "Deployment front disponible" || ko "front indisponible"
S=$(jp ingress factura '{.spec.tls[0].secretName}')
[ "$S" = factura-tls ] && ok "Ingress factura avec tls -> factura-tls" \
  || ko "Ingress factura sans bloc tls vers le Secret factura-tls"
T=$(jp secret factura-tls '{.type}')
[ "$T" = kubernetes.io/tls ] && ok "Secret factura-tls de type kubernetes.io/tls" \
  || ko "Secret factura-tls absent (kubectl create secret tls)"
B=$(jp ingress factura '{.spec.rules[0].http.paths[0].backend.service.name}')
[ "$B" = front ] && ok "backend de l'Ingress = front" \
  || ko "backend de l'Ingress : « $B », attendu front"
CODE=$(curl -sk -m 10 -o /dev/null -w '%{http_code}' \
        --resolve factura.lab.local:443:10.10.10.14 \
        https://factura.lab.local/api/factures)
[ "$CODE" = 200 ] && ok "https://factura.lab.local/api/factures -> 200" \
  || ko "/api/factures renvoie $CODE (endpoints de factura-api ? proxy_pass ?)"
CN=$(echo | openssl s_client -connect 10.10.10.14:443 \
      -servername factura.lab.local 2>/dev/null \
      | openssl x509 -noout -subject 2>/dev/null)
printf '%s' "$CN" | grep -q 'factura.lab.local' \
  && ok "certificat servi : $CN" \
  || ko "Traefik ne sert pas le certificat factura.lab.local (TRAEFIK DEFAULT CERT ?)"

# --- 4. NetworkPolicy ------------------------------------------------------
k get networkpolicy -o jsonpath='{.items[*].spec.podSelector.matchLabels.app}' \
  | grep -qw postgres && ok "NetworkPolicy ciblant app=postgres" \
  || ko "aucune NetworkPolicy avec podSelector app=postgres dans factura"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
