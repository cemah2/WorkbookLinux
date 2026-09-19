#!/usr/bin/env bash
# break_PC_1_1.sh — ticket PC.1.1 (lab-web)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_1_1; mkdir -p "$SAUV"
SSL=/etc/ssl/factura
[ -f "$SSL/ca.cnf" ] || { echo "lance d'abord setup_P3.sh (rôle web)" >&2; exit 1; }

cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"
[ -f "$SAUV/$ID.factura.crt" ] || cp -a "$SSL/factura.lab.local.crt" \
  "$SAUV/$ID.factura.crt"

# Certificat émis il y a 90 jours par la CA de lab, expiré ce matin à 03:00.
FIN=$(date -u -d "$(date +%F) 01:00:00" +%Y%m%d%H%M%SZ)   # 03:00 Paris = 01:00 UTC
DEBUT=$(date -u -d "$(date +%F) 01:00:00 90 days ago" +%Y%m%d%H%M%SZ)
openssl ca -batch -config "$SSL/ca.cnf" -notext \
  -in "$SSL/factura.lab.local.csr" -out "$SSL/factura.lab.local.crt" \
  -startdate "$DEBUT" -enddate "$FIN" >/dev/null 2>&1
chmod 0644 "$SSL/factura.lab.local.crt"
[ -d /run/systemd/system ] && systemctl reload nginx 2>/dev/null || true

cat <<'EOF'

Symptôme attendu : depuis 03:00, https://factura.lab.local affiche une
erreur de sécurité dans le navigateur, et l'alerte Prometheus
« SSLCertExpired » est active. Le site est inaccessible en HTTPS.
EOF
