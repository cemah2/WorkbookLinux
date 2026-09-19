#!/usr/bin/env bash
# check_M22_04.sh — vérifie le lab L22.4 (Prometheus, exporters, blackbox,
# découverte k8s, règles, Alertmanager). À lancer sur lab-ops.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification L22.4 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BASE="$HOMEDIR/lab22"
OBS=/opt/observabilite
PROM=http://10.10.10.14:9090
q() { curl -s -m 10 "$PROM/api/v1/query" --data-urlencode "query=$1" \
      | python3 -c 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else 0)' 2>/dev/null; }

# --- 1. Prometheus et ses cibles ----------------------------------------
curl -sf -m 5 "$PROM/-/ready" >/dev/null && ok "Prometheus répond" \
  || ko "Prometheus ne répond pas sur :9090 (docker compose ps)"
UP=$(q 'count(up == 1)')
[ "${UP:-0}" -ge 8 ] && ok "$UP cibles UP (>= 8)" \
  || ko "seulement ${UP:-0} cibles UP : voir $PROM/targets"
for j in node nginx postgres; do
  N=$(q "count(up{job=\"$j\"} == 1)")
  [ "${N:-0}" -ge 1 ] && ok "job $j : $N cible(s) UP" \
    || ko "job $j : aucune cible UP (exporter, prometheus.yml, reload ?)"
done
NODE=$(q 'count(up{job="node"} == 1)')
[ "${NODE:-0}" -ge 5 ] && ok "les 5 VM sont scrapées" \
  || ko "job node : ${NODE:-0}/5 (node_exporter partout ? firewalld sur lab-rhel ?)"
PS=$(q 'count(probe_success{job="blackbox-http"})')
[ "${PS:-0}" -ge 3 ] && ok "blackbox-http : $PS sondes" \
  || ko "blackbox-http : ${PS:-0} sondes (metrics_path /probe, relabel, extra_hosts ?)"
curl -s "$PROM/api/v1/label/instance/values?match[]=probe_success" \
  | grep -q 'http' && ok "instance des sondes = URL sondée" \
  || ko "le label instance des sondes doit être l'URL (relabel __param_target -> instance)"
K8S=$(q 'count(factura_http_requests_total{job="k8s-pods"})')
[ "${K8S:-0}" -ge 1 ] && ok "job k8s-pods : séries factura_http_requests_total" \
  || ko "job k8s-pods : pas de factura_http_requests_total (kubernetes_sd, token, relabel ?)"
curl -s "$PROM/api/v1/series?match[]=up{job=\"k8s-pods\"}" \
  | grep -q '"namespace":"factura"' && ok "labels namespace/pod sur les cibles k8s" \
  || ko "les cibles k8s-pods n'ont pas de label namespace (relabel __meta_kubernetes_namespace)"

# --- 2. règles ---------------------------------------------------------------
for f in lab-enregistrement.yml lab-alertes.yml; do
  [ -s "$OBS/prometheus/rules/$f" ] && ok "fichier rules/$f présent" \
    || ko "fichier $OBS/prometheus/rules/$f absent"
done
(cd "$OBS" && docker compose exec -T prometheus promtool check rules \
  /etc/prometheus/rules/lab-enregistrement.yml \
  /etc/prometheus/rules/lab-alertes.yml >/dev/null 2>&1) \
  && ok "promtool check rules : SUCCESS" \
  || ko "promtool check rules échoue sur un des deux fichiers"
RULES=$(curl -s "$PROM/api/v1/rules")
for r in instance:node_cpu_utilisation:ratio_5m instance:node_memory_utilisation:ratio \
         job:factura_http_requests:rate5m job:factura_http_errors:ratio_rate5m; do
  printf '%s' "$RULES" | grep -q "\"name\":\"$r\"" && ok "règle $r chargée" \
    || ko "règle d'enregistrement $r absente (nom exact ? reload ?)"
done
NA=$(printf '%s' "$RULES" | python3 -c '
import sys, json
g = json.load(sys.stdin)["data"]["groups"]
a = {r["name"] for x in g for r in x["rules"] if r["type"] == "alerting"}
att = {"InstanceDown","CpuEleve","MemoireBasse","DisquePleinDans24h",
       "DisquePresquePlein","ApiErreurs5xx","ApiLatenceP95","SondeEchec",
       "CertificatExpire","PodEnCrashLoop","PostgresDown"}
print(" ".join(sorted(att - a)))' 2>/dev/null)
[ -z "$NA" ] && ok "les 11 alertes sont chargées" \
  || ko "alertes manquantes : $NA"
printf '%s' "$RULES" | python3 -c '
import sys, json
g = json.load(sys.stdin)["data"]["groups"]
rs = [r for x in g for r in x["rules"] if r["type"] == "alerting"
      and r["name"] != "PrometheusCibleAbsente"]
assert rs
for r in rs:
    assert r["labels"].get("severity") in ("page", "ticket"), r["name"]
    assert "runbook_url" in r["annotations"], r["name"]
    assert "summary" in r["annotations"], r["name"]
' 2>/dev/null && ok "chaque alerte a severity page|ticket, summary, runbook_url" \
  || ko "une alerte sans severity (page|ticket), summary ou runbook_url"

# --- 3. Alertmanager -------------------------------------------------------
AM="$OBS/alertmanager/alertmanager.yml"
python3 - "$AM" <<'EOF' 2>/dev/null && ok "alertmanager.yml : routes page/ticket + inhibition" \
  || ko "alertmanager.yml : attendu 2 routes (severity page/ticket) et 1 inhibit_rule InstanceDown -> ticket"
import sys, yaml
c = yaml.safe_load(open(sys.argv[1]))
routes = c["route"]["routes"]
recv = {r["receiver"] for r in routes}
assert {"page", "ticket"} <= recv
assert any("page" in str(r.get("matchers", r.get("match", ""))) for r in routes)
inh = c["inhibit_rules"]
assert any("InstanceDown" in str(i.get("source_matchers", i.get("source_match", "")))
           and "instance" in i.get("equal", []) for i in inh)
EOF
(cd "$OBS" && docker compose exec -T alertmanager amtool check-config \
  /etc/alertmanager/alertmanager.yml >/dev/null 2>&1) \
  && ok "amtool check-config : SUCCESS" || ko "amtool check-config échoue"
curl -sf -m 5 http://10.10.10.14:9093/-/ready >/dev/null \
  && ok "Alertmanager répond" || ko "Alertmanager ne répond pas sur :9093"

# --- 4. rapport --------------------------------------------------------------
[ -s "$BASE/rapports/alerting.md" ] && grep -qi 'firing' "$BASE/rapports/alerting.md" \
  && ok "rapport alerting.md rédigé" \
  || ko "~/lab22/rapports/alerting.md absent ou sans chronologie pending/firing"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
