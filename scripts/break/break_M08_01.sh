#!/usr/bin/env bash
# break_M08_01.sh — panne BF8.1 (mauvais Type= : démarrage en timeout)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

UNIT=/etc/systemd/system/factura-import.service
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

[ -x /opt/factura/bin/factura-api.py ] || {
  echo "/opt/factura/bin/factura-api.py absent : lance setup_M08.sh" >&2
  exit 1; }

# --- sauvegarde de l'état avant de casser -------------------------------
if [ -f "$UNIT" ] && [ ! -f "$SAUV/M08_01.service" ]; then
  cp -a "$UNIT" "$SAUV/M08_01.service"
fi

# --- l'unité fautive ----------------------------------------------------
# Le binaire reste au premier plan ; l'unité prétend qu'il se détache.
cat > "$UNIT" <<'EOF'
[Unit]
Description=Factura — import des ecritures comptables
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/run/factura/import.pid
User=factura
Group=factura
RuntimeDirectory=factura
WorkingDirectory=/srv/factura
EnvironmentFile=/etc/factura/api.env
Environment=FACTURA_PORT=8090
Environment=FACTURA_LOG=/var/log/factura/import.log
ExecStart=/opt/factura/bin/factura-api.py
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "$UNIT"

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload
  systemctl stop factura-import.service >/dev/null 2>&1 || true
  systemctl reset-failed factura-import.service >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : « sudo systemctl start factura-import » reste bloqué
environ 90 s, puis rend la main sur « Job for factura-import.service
failed ».
Pendant l'attente, « curl http://127.0.0.1:8090/sante » répond correctement.
Le service finit en failed et rien ne tourne plus ensuite.
EOF
