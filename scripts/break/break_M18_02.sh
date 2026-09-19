#!/usr/bin/env bash
# break_M18_02.sh — panne BF18.2 (contexte SELinux cassé par un mv)
# À lancer sur lab-rhel, avec sudo. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

command -v getenforce >/dev/null 2>&1 || {
  echo "SELinux absent : cette panne se joue sur lab-rhel (Rocky 9)" >&2
  exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

DOCROOT=/usr/share/nginx/html
[ -d "$DOCROOT" ] || DOCROOT=/var/www/html
mkdir -p "$DOCROOT"

# --- la machine doit être dans l'état nominal --------------------------
if [ "$(getenforce)" != Enforcing ]; then
  echo "SELinux était en $(getenforce) : remise en Enforcing" >&2
  echo "$(getenforce)" > "$SAUV/M18_02.selinux-mode"
  setenforce 1
fi

systemctl is-active nginx >/dev/null 2>&1 || systemctl start nginx \
  >/dev/null 2>&1 || true

# --- sauvegarde --------------------------------------------------------
[ -f "$SAUV/M18_02.docroot" ] || echo "$DOCROOT" > "$SAUV/M18_02.docroot"

# --- la panne : un fichier fabriqué dans /home puis déplacé ------------
SRC="$LAB_HOME/rapport.html"
cat > "$SRC" <<'EOF'
<!doctype html><html lang="fr"><meta charset="utf-8">
<title>Rapport trimestriel</title>
<h1>Rapport trimestriel</h1>
<p>Document déposé par l'équipe métier.</p>
EOF
chown "$LAB_USER": "$SRC"
chmod 0644 "$SRC"
# on force explicitement l'étiquette d'un fichier de home, au cas où
# /home serait sur un système de fichiers séparé (où mv recopierait)
chcon -t user_home_t "$SRC" 2>/dev/null || true

rm -f "$DOCROOT/rapport.html"
mv "$SRC" "$DOCROOT/rapport.html"
chown root:root "$DOCROOT/rapport.html"
chmod 0644 "$DOCROOT/rapport.html"
chcon -t user_home_t "$DOCROOT/rapport.html" 2>/dev/null || true

# le reste du site doit être correct, pour que le contraste soit net
restorecon -R "$DOCROOT" 2>/dev/null || true
chcon -t user_home_t "$DOCROOT/rapport.html" 2>/dev/null || true

systemctl reload nginx >/dev/null 2>&1 || true

cat <<'EOF'

Symptôme attendu : le site répond normalement, mais /rapport.html renvoie
systématiquement 403 Forbidden, y compris en local
(curl -I http://127.0.0.1/rapport.html).
Le fichier existe, il est en -rw-r--r-- root:root, il est au même endroit
que les pages qui fonctionnent, et le journal d'erreur nginx indique
« Permission denied ».
EOF
