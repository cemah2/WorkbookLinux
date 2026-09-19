#!/usr/bin/env bash
# break_M03_01.sh — panne BF3.1 (nginx 403 : un répertoire parent perd son x)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

WEB=/var/www/factura
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

[ -d "$WEB" ] || { echo "$WEB absent : lance d'abord setup_M03.sh" >&2; exit 1; }

# --- sauvegarde de l'état des droits avant de casser --------------------
stat -c '%a %n' /var/www "$WEB" > "$SAUV/M03_01.modes" 2>/dev/null || true

# --- la subtilité : ce n'est PAS le fichier ni la racine du site qui      -
# --- bloque, mais le répertoire PARENT /var/www qui perd son bit x.       -
# --- Les fichiers restent en 644, le site "a l'air" correct.              -
chmod o-x /var/www

# on s'assure que le contenu du site est irréprochable, pour que le
# diagnostic ne se laisse pas distraire par les droits des fichiers
find "$WEB" -type d -exec chmod 755 {} +
find "$WEB" -type f -exec chmod 644 {} +
chown -R www-data:www-data "$WEB"

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  systemctl reload nginx >/dev/null 2>&1 || \
    systemctl restart nginx >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : http://10.10.10.11/ renvoie 403 Forbidden sur toutes les
pages. Les fichiers HTML existent bien dans /var/www/factura et sont en 644.
/var/log/nginx/error.log répète "Permission denied" à l'ouverture des fichiers.
EOF
