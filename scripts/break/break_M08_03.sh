#!/usr/bin/env bash
# break_M08_03.sh — panne BF8.3 (une unité masquée que personne ne comprend)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

VENDOR=/usr/lib/systemd/system
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

[ -x /opt/factura/bin/factura-collecte.sh ] || {
  echo "/opt/factura/bin/factura-collecte.sh absent : lance setup_M08.sh" >&2
  exit 1; }

# --- deux unités « livrées par le paquet », de structure identique ------
# factura-exports : celle qui marche, pour la comparaison.
cat > "$VENDOR/factura-exports.service" <<'EOF'
[Unit]
Description=Factura — generation des exports

[Service]
Type=oneshot
RemainAfterExit=yes
User=factura
Group=factura
Environment=FACTURA_DUREE=1
Environment=FACTURA_DATA=/srv/factura/data
Environment=FACTURA_LOG=/var/log/factura/exports.log
ExecStart=/opt/factura/bin/factura-collecte.sh

[Install]
WantedBy=multi-user.target
EOF

# factura-rapports : celle qui refusera de démarrer.
cat > "$VENDOR/factura-rapports.service" <<'EOF'
[Unit]
Description=Factura — generation des rapports mensuels

[Service]
Type=oneshot
RemainAfterExit=yes
User=factura
Group=factura
Environment=FACTURA_DUREE=1
Environment=FACTURA_DATA=/srv/factura/data
Environment=FACTURA_LOG=/var/log/factura/rapports.log
ExecStart=/opt/factura/bin/factura-collecte.sh

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "$VENDOR/factura-exports.service" \
           "$VENDOR/factura-rapports.service"

# --- on masque, comme un prédécesseur pressé l'aurait fait --------------
# Un masque est un lien symbolique vers /dev/null dans /etc/systemd/system :
# il court-circuite le fichier livré par le paquet, quel qu'en soit le
# contenu. On sauvegarde l'état antérieur avant de poser le lien.
TARGET=/etc/systemd/system/factura-rapports.service
if [ -e "$TARGET" ] && [ ! -L "$TARGET" ] && \
   [ ! -f "$SAUV/M08_03.service" ]; then
  cp -a "$TARGET" "$SAUV/M08_03.service"
fi
rm -f "$TARGET"
ln -s /dev/null "$TARGET"

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload
  systemctl reset-failed factura-rapports.service >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : « sudo systemctl start factura-rapports » échoue
instantanément, sans PID, sans code de sortie et sans trace applicative.
Le fichier d'unité existe et son contenu est correct. Le service
factura-exports, de structure identique, démarre lui sans problème.
EOF
