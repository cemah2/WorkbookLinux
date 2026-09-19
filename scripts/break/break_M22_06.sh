#!/usr/bin/env bash
# break_M22_06.sh — panne BF22.6 (l'alerte ne part jamais)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/M22_06/.
# Suppose L22.4 terminé (rules/lab-alertes.yml avec InstanceDown).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

OBS=/opt/observabilite
RULES="$OBS/prometheus/rules/lab-alertes.yml"
SAUV=/root/.breakfix-backup/M22_06
mkdir -p "$SAUV"

grep -q 'alert: InstanceDown' "$RULES" 2>/dev/null \
  || { echo "InstanceDown absente de $RULES : fais d'abord L22.4" >&2; exit 1; }
curl -sf -m 5 http://localhost:9090/-/ready >/dev/null \
  || { echo "Prometheus ne tourne pas : docker compose up -d dans $OBS" >&2; exit 1; }

[ -s "$SAUV/lab-alertes.yml" ] || cp "$RULES" "$SAUV/lab-alertes.yml"

# --- la panne -----------------------------------------------------------
# une lettre dans le « for » de la règle InstanceDown (et seulement elle)
python3 - "$RULES" <<'EOF'
import re, sys
p = sys.argv[1]
lines = open(p).read().split("\n")
out, dans = [], False
for l in lines:
    if re.match(r"\s*-\s*alert:\s*InstanceDown\s*$", l):
        dans = True
    elif re.match(r"\s*-\s*alert:", l):
        dans = False
    if dans and re.match(r"\s*for:\s*\d+m\s*$", l):
        l = re.sub(r"(\d+)m\s*$", r"\1h", l)
        dans = False
    out.append(l)
open(p, "w").write("\n".join(out))
EOF
curl -s -X POST http://localhost:9090/-/reload >/dev/null

cat <<'EOF'

Symptôme attendu : hier soir, lab-rhel est resté injoignable une heure
et personne n'a été prévenu. Pour reproduire : arrête node_exporter sur
lab-rhel (sudo systemctl stop node_exporter). InstanceDown apparaît en
« pending » dans http://10.10.10.14:9090/alerts et y reste, jamais
« firing » ; rien n'arrive dans « docker compose logs -f webhook ».
Les autres alertes fonctionnent normalement.
EOF
