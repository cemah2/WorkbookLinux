#!/usr/bin/env bash
# break_M08_02.sh — panne BF8.2 (boucle : EnvironmentFile absent)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

UNIT=/etc/systemd/system/factura-collecte.service
ENVF=/etc/factura/collecte.env
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

[ -x /opt/factura/bin/factura-api.py ] || {
  echo "/opt/factura/bin/factura-api.py absent : lance setup_M08.sh" >&2
  exit 1; }

# --- sauvegarde de l'état avant de casser -------------------------------
if [ -f "$UNIT" ] && [ ! -f "$SAUV/M08_02.service" ]; then
  cp -a "$UNIT" "$SAUV/M08_02.service"
fi

# --- l'unité, parfaitement correcte -------------------------------------
cat > "$UNIT" <<'EOF'
[Unit]
Description=Factura — collecteur permanent de metriques
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=factura
Group=factura
WorkingDirectory=/srv/factura
EnvironmentFile=/etc/factura/collecte.env
ExecStart=/opt/factura/bin/factura-api.py
Restart=always
RestartSec=1s

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "$UNIT"

# --- le fichier d'environnement : créé, sauvegardé, puis supprimé -------
if [ ! -f "$SAUV/M08_02.collecte.env" ]; then
  cat > "$SAUV/M08_02.collecte.env" <<'EOF'
FACTURA_PORT=8091
FACTURA_DATA=/srv/factura/data
FACTURA_LOG=/var/log/factura/collecte.log
EOF
fi
rm -f "$ENVF"

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload
  systemctl reset-failed factura-collecte.service >/dev/null 2>&1 || true
  systemctl start factura-collecte.service >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : factura-collecte.service apparaît en activating,
disparaît, revient, puis reste définitivement en failed au bout d'une
dizaine de secondes.
« systemctl restart factura-collecte » échoue aussitôt sur un message
« start request repeated too quickly ». L'unité n'a pas été modifiée.
EOF
