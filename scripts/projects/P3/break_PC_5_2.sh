#!/usr/bin/env bash
# break_PC_5_2.sh — ticket PC.5.2 (lab-web)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_5_2; mkdir -p "$SAUV"
CONF=/etc/nginx/sites-available/factura.conf
[ -f "$CONF" ] || { echo "lance d'abord setup_P3.sh (rôle web)" >&2; exit 1; }
cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"
[ -f "$SAUV/$ID.factura.conf" ] || cp -a "$CONF" "$SAUV/$ID.factura.conf"

# Une mise à jour du paquet a « proposé » sa version du fichier et
# l'ancienne a été mise de côté en .dpkg-old : le vhost personnalisé
# (TLS, upstream) a été remplacé par un vhost par défaut sur le port 80.
mv "$CONF" "$CONF.dpkg-old"
cat > "$CONF" <<'EOF'
# Configuration livrée par le paquet (nginx-common) — NE PAS ÉDITER.
server {
    listen 80 default_server;
    server_name _;
    root /var/www/html;
    index index.html;
    location / { try_files $uri $uri/ =404; }
}
EOF
mkdir -p /var/www/html
echo '<h1>Welcome to nginx!</h1>' > /var/www/html/index.html
printf '%s upgrade nginx 1.24.0-1 -> 1.24.0-2ubuntu1 : \
/etc/nginx/sites-available/factura.conf conserve sous .dpkg-old\n' \
  "$(date '+%F %T')" >> /var/log/factura/deploy.log
[ -d /run/systemd/system ] && { nginx -t >/dev/null 2>&1 \
  && systemctl reload nginx || systemctl restart nginx; } 2>/dev/null || true

cat <<'EOF'

Symptôme attendu : depuis la fenêtre de mises à jour de cette nuit,
https://factura.lab.local ne répond plus (plus rien sur 443) et le port 80
affiche la page « Welcome to nginx! » par défaut. L'API, elle, tourne.
EOF
