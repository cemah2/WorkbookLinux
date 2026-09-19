#!/usr/bin/env bash
# break_M15_02.sh — panne BF15.2 (à lancer sur lab-web, après L15.1)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
FILES="$(grep -rlE '127\.0\.0\.1:800[12]' /etc/nginx/sites-available /etc/nginx/conf.d 2>/dev/null || true)"
[ -n "$FILES" ] || { echo "aucun upstream 8001/8002 dans nginx : fais L15.1" >&2; exit 1; }
for f in $FILES; do
  b="$SAUV/M15_02.$(basename "$f")"
  [ -f "$b" ] || cp -a "$f" "$b"
  sed -i 's/127\.0\.0\.1:8001/127.0.0.1:8011/g; s/127\.0\.0\.1:8002/127.0.0.1:8012/g' "$f"
done
nginx -t >/dev/null 2>&1 && systemctl reload nginx
# quelques requêtes pour que l'état des upstreams reflète la panne
for _ in 1 2 3; do curl -sk -o /dev/null --max-time 3 \
  --resolve factura-demo.lab.local:443:127.0.0.1 \
  --resolve factura-demo.lab.local:80:127.0.0.1 \
  https://factura-demo.lab.local/api/health \
  http://factura-demo.lab.local/api/health 2>/dev/null || true; done

cat <<'EOF2'

Symptôme attendu : toute URI /api/... renvoie 502 Bad Gateway ; le site
statique répond normalement ; mini-api@8001 et mini-api@8002 sont
« active (running) ».
EOF2
