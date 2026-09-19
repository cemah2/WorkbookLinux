#!/usr/bin/env bash
# break_M22_05.sh — panne BF22.5 (toutes les VM DOWN dans Prometheus)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/M22_05/.
# Suppose L22.4 terminé (pile Compose démarrée, job node dans prometheus.yml).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

OBS=/opt/observabilite
CFG="$OBS/prometheus/prometheus.yml"
SAUV=/root/.breakfix-backup/M22_05
mkdir -p "$SAUV"

[ -s "$CFG" ] || { echo "$CFG absent : lance setup_M22.sh" >&2; exit 1; }
grep -q ':9100"' "$CFG" || grep -q ':9101"' "$CFG" \
  || { echo "aucune cible node :9100 dans $CFG : fais d'abord L22.4" >&2; exit 1; }
curl -sf -m 5 http://localhost:9090/-/ready >/dev/null \
  || { echo "Prometheus ne tourne pas : docker compose up -d dans $OBS" >&2; exit 1; }

[ -s "$SAUV/prometheus.yml" ] || cp "$CFG" "$SAUV/prometheus.yml"

# --- la panne -----------------------------------------------------------
# les cinq cibles du job node visent un port où rien n'écoute
sed -i 's/:9100"/:9101"/g' "$CFG"
curl -s -X POST http://localhost:9090/-/reload >/dev/null

cat <<'EOF'

Symptôme attendu : dans http://10.10.10.14:9090/targets, les 5 cibles du
job node passent DOWN dans la minute ; Grafana affiche « No data » sur
« Lab — Nœuds » et, au bout de 2 minutes, InstanceDown est firing pour
les 5 VM. Pourtant ssh fonctionne partout et
« curl http://10.10.10.11:9100/metrics » depuis lab-ops répond.
EOF
