#!/usr/bin/env bash
# break_M15_01.sh — panne BF15.1 (à lancer sur lab-web, après L15.1)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SITE=/etc/nginx/sites-available/factura-demo
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
[ -f "$SITE" ] || { echo "$SITE absent : fais L15.1 d'abord" >&2; exit 1; }
[ -f "$SAUV/M15_01.factura-demo" ] || cp -a "$SITE" "$SAUV/M15_01.factura-demo"

if ! grep -q 'cache statique 2026-09' "$SITE"; then
  python3 - "$SITE" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
# « nettoyage » de la syntaxe : le ^~ disparaît
s = re.sub(r'location\s+\^~\s+/api/', 'location /api/', s)
# cache des fichiers statiques, inséré avant la première location
bloc = ('    # cache statique 2026-09 : 7 jours sur les assets\n'
        '    location ~* \\.(json|js|css|png|svg|ico)$ {\n'
        '        expires 7d;\n'
        '        add_header Cache-Control "public";\n'
        '    }\n')
i = s.find('    location')
s = s[:i] + bloc + s[i:] if i >= 0 else s + bloc
open(p, 'w').write(s)
PY
fi
nginx -t >/dev/null 2>&1 && systemctl reload nginx

cat <<'EOF2'

Symptôme attendu : la page https://factura-demo.lab.local/ s'affiche mais
indique « ERREUR : HTTP 404 sur /api/invoices.json ». /api/health répond
200, les deux instances mini-api sont actives, nginx -t est correct.
EOF2
