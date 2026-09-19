#!/usr/bin/env bash
# break_M08_04.sh — panne BF8.4 (drop-in oublié : LimitNOFILE trop bas)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

VENDOR=/usr/lib/systemd/system
DROPIN=/etc/systemd/system/factura-api.service.d
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV" "$DROPIN"

[ -x /opt/factura/bin/factura-api.py ] || {
  echo "/opt/factura/bin/factura-api.py absent : lance setup_M08.sh" >&2
  exit 1; }

# --- filet de sécurité : si l'apprenant n'a pas fait L8.2, on installe
# --- une unité de base côté paquet pour que la panne soit reproductible.
if ! [ -f /etc/systemd/system/factura-api.service ] && \
   ! [ -f "$VENDOR/factura-api.service" ]; then
  cat > "$VENDOR/factura-api.service" <<'EOF'
[Unit]
Description=Factura — API de facturation
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=factura
Group=factura
WorkingDirectory=/srv/factura
EnvironmentFile=/etc/factura/api.env
ExecStart=/opt/factura/bin/factura-api.py
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s
TimeoutStopSec=20s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$VENDOR/factura-api.service"
fi

# --- sauvegarde des drop-ins existants ----------------------------------
if [ ! -d "$SAUV/M08_04.d" ]; then
  mkdir -p "$SAUV/M08_04.d"
  cp -a "$DROPIN"/. "$SAUV/M08_04.d/" 2>/dev/null || true
fi

# --- un drop-in anodin, qui n'a aucun effet de bord ---------------------
cat > "$DROPIN/10-local.conf" <<'EOF'
[Unit]
Description=Factura — API de facturation (instance lab-web)
EOF

# --- et celui qui fait mal, au nom rassurant ----------------------------
cat > "$DROPIN/90-tuning.conf" <<'EOF'
# Ajusté le 12/03 suite au ticket INC-2980 (fuite de descripteurs).
# À revoir après la mise à jour applicative.
[Service]
LimitNOFILE=128
EOF
chmod 0644 "$DROPIN"/*.conf

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload
  systemctl restart factura-api.service >/dev/null 2>&1 || \
    systemctl start factura-api.service >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : factura-api démarre et répond à
« curl http://127.0.0.1:8080/sante ». Mais
« curl 'http://127.0.0.1:8080/charge?n=200' » renvoie une erreur 500
contenant « Too many open files ». « ulimit -n » dans un shell d'admin
affiche pourtant une valeur confortable, et le fichier d'unité n'a pas
été modifié.
EOF
