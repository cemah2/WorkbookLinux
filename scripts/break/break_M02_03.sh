#!/usr/bin/env bash
# break_M02_03.sh — panne BF2.3 (lien symbolique de déploiement cassé)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

WWW=/srv/www
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV" "$WWW/releases"

# --- arborescence de releases (créée si absente) ------------------------
for r in 2026-09-04 2026-09-11 2026-09-18; do
  d="$WWW/releases/$r"
  mkdir -p "$d"
  [ -f "$d/index.html" ] || printf '<h1>factura %s</h1>\n' "$r" \
    > "$d/index.html"
  [ -f "$d/VERSION" ] || printf '%s\n' "$r" > "$d/VERSION"
done

# --- sauvegarde de la cible actuelle du lien, si elle existe ------------
if [ -L "$WWW/current" ] && [ ! -f "$SAUV/M02_03.cible" ]; then
  readlink "$WWW/current" > "$SAUV/M02_03.cible"
fi
[ -f "$SAUV/M02_03.cible" ] || printf 'releases/2026-09-11\n' \
  > "$SAUV/M02_03.cible"

# --- la panne : le script de livraison a posé un lien relatif depuis le
#     mauvais répertoire de base (il a fait « cd releases » avant le ln)
ln -sfn 2026-09-18 "$WWW/current"

# quelques fichiers servis, pour que le répertoire ne soit pas vide
[ -f "$WWW/robots.txt" ] || printf 'User-agent: *\n' > "$WWW/robots.txt"

printf 'panne BF2.3 posée le %s\n' "$(date -Is)" > "$SAUV/M02_03.marqueur"

cat <<'EOF'

Symptôme attendu : ls /srv/www/current/ répond "No such file or directory"
et cat /srv/www/current/index.html aussi, alors que ls -l /srv/www montre
bien une entrée nommée current et que les répertoires de
/srv/www/releases sont tous intacts et lisibles.
EOF
