#!/usr/bin/env bash
# check_M26_05.sh — vérifie le lab L26.5 (Grafana provisionné, tableau API,
# Loki avec les flux systemd-journal et k8s-pods). À lancer sur lab-ops.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification L26.5 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BASE="$HOMEDIR/lab26"
GRAF=http://10.10.10.14:3000
LOKI=http://10.10.10.14:3100
g() { curl -s -m 10 -u admin:labpass "$GRAF$1"; }
py() { python3 -c "import sys,json; d=json.load(sys.stdin); $1" 2>/dev/null; }

# --- 1. Grafana et les sources ------------------------------------------------
curl -sf -m 5 "$GRAF/api/health" >/dev/null && ok "Grafana répond" \
  || ko "Grafana ne répond pas sur :3000"
g /api/datasources | py '
t = {x["type"] for x in d}
assert {"prometheus", "loki", "alertmanager"} <= t' \
  && ok "3 sources provisionnées (Prometheus, Loki, Alertmanager)" \
  || ko "sources manquantes (provisioning/datasources/sources.yml)"

# --- 2. tableaux du dossier Lab ------------------------------------------------
S=$(g '/api/search?type=dash-db')
N=$(printf '%s' "$S" | py 'print(len([x for x in d if x.get("folderTitle")=="Lab"]))')
[ "${N:-0}" -ge 2 ] && ok "$N tableaux dans le dossier Lab" \
  || ko "moins de 2 tableaux dans le dossier Lab (fichier copié dans grafana/dashboards/ ?)"
UID_=$(printf '%s' "$S" | py '
r = [x for x in d if x.get("title","").strip() == "Lab — API factura"]
print(r[0]["uid"] if r else "")')
if [ -n "$UID_" ]; then
  ok "tableau « Lab — API factura » trouvé (uid $UID_)"
  D=$(g "/api/dashboards/uid/$UID_")
  printf '%s' "$D" | py '
db = d["dashboard"]
panels = db.get("panels", [])
panels += [p for r in panels if r.get("type") == "row" for p in r.get("panels", [])]
assert len([p for p in panels if p.get("type") != "row"]) >= 5' \
    && ok "au moins 5 panneaux" || ko "moins de 5 panneaux dans Lab — API factura"
  printf '%s' "$D" | py '
v = [x for x in d["dashboard"].get("templating", {}).get("list", []) if x["name"] == "pod"]
assert v and "factura_http_requests_total" in str(v[0].get("query", v[0].get("definition", "")))' \
    && ok "variable pod (label_values(factura_http_requests_total, pod))" \
    || ko "variable pod absente ou sans label_values(factura_http_requests_total, pod)"
  printf '%s' "$D" | py 'assert d["meta"].get("provisioned")' \
    && ok "tableau provisionné par fichier" \
    || ko "le tableau a été créé dans l'UI, pas provisionné par fichier"
  printf '%s' "$D" | py '
assert any(p.get("type") == "logs" for p in d["dashboard"]["panels"])' \
    && ok "panneau Logs (Loki) présent" || ko "pas de panneau de type logs"
  printf '%s' "$D" | py '
assert any(p.get("type") == "state-timeline" for p in d["dashboard"]["panels"])' \
    && ok "panneau State timeline présent" || ko "pas de panneau state-timeline (ALERTS)"
else
  ko "tableau « Lab — API factura » absent (titre exact, tiret cadratin)"
fi

# --- 3. Loki ---------------------------------------------------------------
curl -sf -m 5 "$LOKI/ready" >/dev/null && ok "Loki répond" || ko "Loki ne répond pas sur :3100"
J=$(curl -s -m 10 "$LOKI/loki/api/v1/label/job/values")
printf '%s' "$J" | grep -q '"systemd-journal"' && ok "flux job=systemd-journal" \
  || ko "aucun flux systemd-journal (docker compose logs alloy)"
printf '%s' "$J" | grep -q '"k8s-pods"' && ok "flux job=k8s-pods" \
  || ko "aucun flux k8s-pods (config.alloy : /var/log/pods/*/*/*.log, restart alloy)"
curl -s -m 10 "$LOKI/loki/api/v1/label/namespace/values" | grep -q '"factura"' \
  && ok "label namespace=factura extrait du chemin" \
  || ko "pas de label namespace=factura dans Loki (relabel sur __path__)"

# --- 4. rapport -----------------------------------------------------------------
[ -s "$BASE/rapports/grafana.md" ] && ok "rapport grafana.md rédigé" \
  || ko "~/lab26/rapports/grafana.md absent"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
