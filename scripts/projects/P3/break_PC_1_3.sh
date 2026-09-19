#!/usr/bin/env bash
# break_PC_1_3.sh — ticket PC.1.3 (lab-web) : demande de changement.
# Ne casse rien : dépose la livraison de l'équipe documentation.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_1_3; mkdir -p "$SAUV"
cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"

mkdir -p /srv/www/docs/api
cat > /srv/www/docs/index.html <<'EOF'
<!doctype html><html lang="fr"><head><meta charset="utf-8">
<title>Documentation Factura</title></head>
<body><h1>Documentation Factura</h1>
<p>Guide utilisateur et référence de l'API.</p>
<ul><li><a href="api/">Référence API</a></li></ul></body></html>
EOF
cat > /srv/www/docs/api/index.html <<'EOF'
<!doctype html><html lang="fr"><head><meta charset="utf-8">
<title>API Factura</title></head><body><h1>API Factura v2</h1>
<p>GET /factures — liste des factures.</p></body></html>
EOF
# livraison telle que déposée par l'équipe doc (droits à revoir)
chown -R 1042:1042 /srv/www/docs 2>/dev/null || true
chmod -R o-rwx /srv/www/docs

cat <<'EOF'

Demande déposée : la livraison du site de documentation est dans
/srv/www/docs. À publier sur https://docs.factura.lab.local avant 17 h.
EOF
