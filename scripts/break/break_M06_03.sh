#!/usr/bin/env bash
# break_M06_03.sh — BF6.3 : synchro du site avec la mauvaise barre oblique
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

BK=/root/.breakfix-backup
SRC=/srv/factura-site
WEB=/var/www/factura
LOG=/var/log/factura-sync.log
mkdir -p "$BK"

# --- la source de vérité, gérée par les développeurs ---------------------
mkdir -p "$SRC"/{css,img,js}
cat > "$SRC/index.html" <<'EOF'
<!doctype html><html lang="fr"><head><meta charset="utf-8">
<title>Factura</title><link rel="stylesheet" href="css/style.css"></head>
<body><h1>Factura</h1><p>Frontal public.</p></body></html>
EOF
printf 'body{font-family:sans-serif}\n'      > "$SRC/css/style.css"
printf 'console.log("factura");\n'           > "$SRC/js/app.js"
printf 'page de maintenance\n'               > "$SRC/maintenance.html"
head -c 2048 /dev/urandom                    > "$SRC/img/logo.png"

# --- sauvegarde de l'état correct avant de le casser ---------------------
if [ -d "$WEB" ] && [ ! -d "$BK/www-factura" ]; then
  cp -a "$WEB" "$BK/www-factura"
fi

# --- l'état "correct" d'avant-hier, puis la synchro fautive --------------
rm -rf "$WEB"
mkdir -p "$WEB"
cp -a "$SRC"/. "$WEB"/
chown -R www-data:www-data "$WEB" 2>/dev/null || true

# ce qu'a produit la commande de nuit : tout est descendu d'un cran, et
# --delete a fait le ménage à la racine.
TMPD=$(mktemp -d)
cp -a "$SRC" "$TMPD/factura-site"
rm -rf "${WEB:?}"/*
mv "$TMPD/factura-site" "$WEB/factura-site"
rmdir "$TMPD"
chown -R www-data:www-data "$WEB" 2>/dev/null || true

# --- la trace laissée par le job ----------------------------------------
{
  printf '%s synchronisation du frontal factura\n' "$(date -Is)"
  printf '%s commande : rsync -a --delete %s %s/\n' \
    "$(date -Is)" "$SRC" "$WEB"
  printf '%s sent 5 files, 4.2K bytes ; deleted 5 files\n' "$(date -Is)"
  printf '%s exit status 0\n' "$(date -Is)"
} >> "$LOG"
chmod 644 "$LOG"

echo
echo "Symptôme attendu :"
echo "  http://10.10.10.11/ répond 404 et $WEB ne contient plus"
echo "  qu'un répertoire factura-site/."
