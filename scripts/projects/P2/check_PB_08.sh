#!/usr/bin/env bash
# check_PB_08.sh — vérifie le jalon PB.8 (Prometheus, Alertmanager, Grafana,
# Loki, alertes, SLO) — interroge lab-ops depuis lab-adm
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification PB.8 =="
REPO="${REPO:-$HOME/factura-v2}"
OPS="${OPS:-10.10.10.14}"
PROM="http://$OPS:9090"; AM="http://$OPS:9093"; GF="http://$OPS:3001"
LOKI="http://$OPS:3100"
q() { curl -fsS -m 6 "$@" 2>/dev/null; }

# --- dépôt ---------------------------------------------------------------
M="$REPO/infra/monitoring"
for f in compose.yaml prometheus/prometheus.yml alertmanager/alertmanager.yml \
         loki/loki.yml blackbox/blackbox.yml \
         grafana/provisioning/datasources/datasources.yml \
         grafana/provisioning/dashboards/dashboards.yml \
         grafana/dashboards/factura.json; do
  [ -f "$M/$f" ] && ok "infra/monitoring/$f" || ko "infra/monitoring/$f manquant"
done
ls "$M"/prometheus/rules/*.yml >/dev/null 2>&1 \
  && ok "règles dans prometheus/rules/" || ko "aucun fichier prometheus/rules/*.yml"
[ -f "$REPO/ansible/playbooks/monitoring.yml" ] \
  && ok "playbook monitoring.yml" || ko "ansible/playbooks/monitoring.yml absent"
grep -q 'inhibit_rules' "$M/alertmanager/alertmanager.yml" 2>/dev/null \
  && ok "alertmanager.yml : inhibition déclarée" \
  || ko "alertmanager.yml : pas d'inhibit_rules (critical doit taire warning)"
grep -qE 'group_by:.*alertname' "$M/alertmanager/alertmanager.yml" 2>/dev/null \
  && ok "alertmanager.yml : group_by alertname" \
  || ko "alertmanager.yml : group_by [alertname, env] attendu"
if [ -f "$REPO/docs/slo.md" ]; then
  grep -qE '99[,.]5' "$REPO/docs/slo.md" && grep -qiE 'budget' "$REPO/docs/slo.md" \
    && ok "docs/slo.md : SLO 99,5 % et budget d'erreur" \
    || ko "docs/slo.md : ne mentionne pas 99,5 % ou le budget"
else
  ko "docs/slo.md absent"
fi

# --- Prometheus ----------------------------------------------------------
if q "$PROM/-/ready" >/dev/null; then
  ok "Prometheus répond sur $PROM"
  T=$(q "$PROM/api/v1/targets")
  N=$(echo "$T" | jq '.data.activeTargets | length')
  D=$(echo "$T" | jq -r '.data.activeTargets[] | select(.health!="up") | .labels.instance')
  [ -z "$D" ] && ok "toutes les cibles sont up ($N)" \
    || ko "cibles down : $(echo "$D" | tr '\n' ' ')"
  for j in node factura-api factura-worker redis postgres blackbox-http; do
    echo "$T" | jq -r '.data.activeTargets[].labels.job' | grep -qx "$j" \
      && ok "job $j scrapé" || ko "job $j absent de prometheus.yml"
  done
  echo "$T" | jq -r '.data.activeTargets[] | select(.labels.job=="factura-api") | .labels.color' \
    | grep -q blue && ok "label color sur les cibles factura-api" \
    || ko "pas de label color sur factura-api (8081=blue, 8082=green)"
  R=$(q "$PROM/api/v1/rules")
  for rec in factura:http_requests:rate5m factura:http_errors:ratio_rate5m \
             factura:http_errors:ratio_rate1h factura:http_errors:ratio_rate6h; do
    echo "$R" | jq -r '.data.groups[].rules[] | select(.type=="recording") | .name' \
      | grep -qx "$rec" && ok "règle d'enregistrement $rec" \
      || ko "règle d'enregistrement $rec absente"
  done
  ALERTS=$(echo "$R" | jq -r '.data.groups[].rules[] | select(.type=="alerting") | .name' | sort -u)
  for a in Watchdog InstanceDown FacturaApiDown FacturaErrorBudgetBurn \
           FacturaQueueBacklog FacturaBackupTooOld DiskWillFillIn4h; do
    echo "$ALERTS" | grep -qx "$a" && ok "alerte $a définie" \
      || ko "alerte $a absente de rules/alerts.yml"
  done
  echo "$R" | jq -r '.data.groups[].rules[] | select(.type=="alerting") | .annotations.runbook // empty' \
    | grep -q . && ok "annotation runbook présente" \
    || ko "aucune alerte n'a d'annotation runbook"
  echo "$R" | jq -r '.data.groups[].rules[] | select(.name=="FacturaErrorBudgetBurn") | .query' \
    | grep -q '14.4' && ok "burn rate multi-fenêtre (14,4x)" \
    || ko "FacturaErrorBudgetBurn sans seuil 14,4x"
  q "$PROM/api/v1/alerts" | jq -r '.data.alerts[] | select(.labels.alertname=="Watchdog") | .state' \
    | grep -q firing && ok "Watchdog firing" || ko "Watchdog n'est pas firing"
else
  ko "Prometheus injoignable sur $PROM (docker compose ps sur lab-ops)"
fi

# --- Alertmanager --------------------------------------------------------
if q "$AM/-/ready" >/dev/null; then
  ok "Alertmanager répond"
  q "$AM/api/v2/alerts" | jq -r '.[].labels.alertname' | grep -q Watchdog \
    && ok "Alertmanager reçoit Watchdog" \
    || ko "Alertmanager ne reçoit pas Watchdog (alerting: dans prometheus.yml ?)"
  q "$AM/api/v2/status" | jq -r .config.original | grep -q 'alert-sink' \
    && ok "receiver webhook vers alert-sink" \
    || ko "aucun receiver vers alert-sink dans la config chargée"
else
  ko "Alertmanager injoignable sur $AM"
fi
if ssh -o BatchMode=yes -o ConnectTimeout=4 "mathieu@$OPS" \
     'grep -c Watchdog /opt/factura-monitoring/data/alerts.log' 2>/dev/null \
     | grep -qE '^[1-9]'; then
  ok "alerts.log sur lab-ops contient des notifications Watchdog"
else
  ko "alerts.log vide ou absent (/opt/factura-monitoring/data/alerts.log)"
fi
if ssh -o BatchMode=yes -o ConnectTimeout=4 "mathieu@$OPS" \
     'grep -q FacturaApiDown /opt/factura-monitoring/data/alerts.log' 2>/dev/null; then
  ok "alerts.log : FacturaApiDown a déjà été notifiée (preuve faite)"
else
  ko "alerts.log : FacturaApiDown jamais notifiée (arrête l'API du staging 3 min)"
fi

# --- Grafana -------------------------------------------------------------
if q "$GF/api/health" | grep -q '"database": *"ok"'; then
  ok "Grafana répond sur $GF"
  if [ -n "${GRAFANA_PASS:-}" ]; then
    S=$(q -u "admin:$GRAFANA_PASS" "$GF/api/search?query=Factura")
    echo "$S" | grep -qi factura && ok "dashboard Factura provisionné" \
      || ko "aucun dashboard 'Factura' (provisioning dashboards/)"
    q -u "admin:$GRAFANA_PASS" "$GF/api/datasources" | jq -r '.[].type' \
      | grep -q loki && ok "datasource Loki provisionnée" \
      || ko "datasource Loki absente"
  else
    echo "  [info] exporte GRAFANA_PASS pour vérifier dashboard et datasources"
  fi
else
  ko "Grafana injoignable sur $GF"
fi

# --- Loki ----------------------------------------------------------------
if q "$LOKI/ready" | grep -q ready; then
  ok "Loki prêt"
  L=$(q -G "$LOKI/loki/api/v1/query_range" \
      --data-urlencode 'query={env="staging"}' --data-urlencode 'limit=5' \
      --data-urlencode "start=$(( $(date +%s) - 3600 ))000000000")
  [ "$(echo "$L" | jq '.data.result | length')" -gt 0 ] \
    && ok "Loki reçoit des journaux avec le label env=staging" \
    || ko "aucun journal env=staging dans Loki (promtail ? labels ?)"
  L=$(q -G "$LOKI/loki/api/v1/query_range" \
      --data-urlencode 'query={container=~"factura-api.*"}' \
      --data-urlencode 'limit=5' \
      --data-urlencode "start=$(( $(date +%s) - 3600 ))000000000")
  [ "$(echo "$L" | jq '.data.result | length')" -gt 0 ] \
    && ok "journaux des conteneurs factura-api dans Loki" \
    || ko "aucun journal container=factura-api* (docker_sd_configs ?)"
else
  ko "Loki injoignable sur $LOKI"
fi
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
