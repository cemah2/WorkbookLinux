#!/usr/bin/env bash
# break_M13_03.sh — panne BF13.3 (les logs du service ont des trous)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
DROPD=/etc/systemd/journald.conf.d
DROP="$DROPD/90-limite-debit.conf"
UDROPD=/etc/systemd/system/factura-api.service.d
UDROP="$UDROPD/10-debit.conf"
mkdir -p "$SAUV" "$DROPD" "$UDROPD"

[ -d /run/systemd/system ] || {
  echo "systemd ne pilote pas cette machine : panne inapplicable" >&2
  exit 1; }
[ -x /opt/factura/bin/factura-api.py ] || {
  echo "factura-api absent : lance setup_M13.sh" >&2; exit 1; }

# --- 1. un limiteur de débit resserré « pour protéger le disque » -------
[ -f "$DROP" ] && [ ! -f "$SAUV/M13_03.journald.conf" ] && \
  cp -a "$DROP" "$SAUV/M13_03.journald.conf"

cat > "$DROP" <<'EOF'
# Durcissement appliqué après l'incident disque de mars.
[Journal]
RateLimitIntervalSec=30s
RateLimitBurst=50
EOF
chmod 0644 "$DROP"

# --- 2. l'application, elle, s'est mise à parler beaucoup ---------------
# Une ligne par requête, et le trafic a été multiplié par cinquante.
[ -f "$UDROP" ] && [ ! -f "$SAUV/M13_03.unit.conf" ] && \
  cp -a "$UDROP" "$SAUV/M13_03.unit.conf"

cat > "$UDROP" <<'EOF'
[Service]
Environment=FACTURA_PERIODE=0.01
EOF
chmod 0644 "$UDROP"

systemctl daemon-reload
systemctl restart systemd-journald
systemctl restart factura-api.service >/dev/null 2>&1 || \
  systemctl start factura-api.service >/dev/null 2>&1 || true

# on laisse le limiteur frapper au moins une fois avant de rendre la main
sleep 35

cat <<'EOF'

Symptôme attendu : « journalctl -u factura-api -f » montre quelques
lignes, puis plus rien pendant une trentaine de secondes, puis reprend.
L'application tourne, « systemctl status factura-api » est vert, et le
développeur affirme qu'elle écrit une ligne par requête.
EOF
