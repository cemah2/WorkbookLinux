#!/usr/bin/env bash
# break_PB_04.sh — INC-B4 : le staging est tombé, personne n'a été prévenu
# À lancer avec sudo sur lab-adm. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/INC-B4/ (id du silence, état).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
LAB_USER="${SUDO_USER:-mathieu}"
BK=/root/.breakfix-backup/INC-B4
AM=http://10.10.10.14:9093
STG_WEB=10.10.10.21
mkdir -p "$BK"

# 1. un silence « maintenance réseau » trop large et trop long, posé hier
if ! curl -fsS -m 5 "$AM/api/v2/silences" \
     | jq -e '.[] | select(.status.state=="active" and .comment=="maintenance réseau")' \
     >/dev/null 2>&1; then
  START=$(date -u -d '-20 hours' +%Y-%m-%dT%H:%M:%SZ)
  END=$(date -u -d '+6 days' +%Y-%m-%dT%H:%M:%SZ)
  curl -fsS -m 5 -X POST "$AM/api/v2/silences" -H 'Content-Type: application/json' \
    -d "{\"matchers\":[{\"name\":\"env\",\"value\":\"staging\",\"isRegex\":false,\"isEqual\":true}],
         \"startsAt\":\"$START\",\"endsAt\":\"$END\",
         \"createdBy\":\"$LAB_USER\",\"comment\":\"maintenance réseau\"}" \
    | jq -r .silenceID >> "$BK/silence-ids.txt"
fi

# 2. « libérer de la RAM » : arrêt des API du staging, à midi
sudo -u "$LAB_USER" ssh -o BatchMode=yes -o ConnectTimeout=5 "deploy@$STG_WEB" \
  'cd /srv/factura && docker ps --format "{{.Names}}" | grep api > /tmp/running.txt; \
   docker compose --env-file .env --env-file state.env \
     --profile blue --profile green stop api-blue api-green' \
  >/dev/null 2>&1 || true
sudo -u "$LAB_USER" ssh -o BatchMode=yes "deploy@$STG_WEB" 'cat /tmp/running.txt' \
  > "$BK/staging-api-running.txt" 2>/dev/null || true

cat <<EOF
Symptôme : un dev signale que le staging ne répond plus « depuis midi ».
  curl http://$STG_WEB/health          -> échec
  Prometheus : FacturaApiDown{env="staging"} firing depuis des heures.
  Alertmanager est up. alerts.log : rien depuis ce matin, sauf Watchdog.
  Une maintenance réseau a eu lieu hier soir.
EOF
