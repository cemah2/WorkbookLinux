#!/usr/bin/env bash
# break_M06_01.sh — BF6.1 : swap vim contenant du travail non enregistré,
# laissé par une session encore vivante (terminal oublié dans un tmux).
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

BK=/root/.breakfix-backup
CONF=/etc/factura/frontal.conf
DIR=$(dirname "$CONF")
mkdir -p "$BK" "$DIR"

# --- état de départ propre -----------------------------------------------
pkill -9 -f "vim -u NONE .*$CONF" >/dev/null 2>&1 || true
sleep 1
rm -f "$DIR"/.frontal.conf.sw?

if [ ! -f "$CONF" ]; then
  cat > "$CONF" <<'EOF'
# /etc/factura/frontal.conf — propriété de root, 644
listen = 0.0.0.0:8080
data_dir = /srv/factura
log_level = info
workers = 2
EOF
fi
[ -f "$BK/frontal.conf" ] || cp -a "$CONF" "$BK/frontal.conf"
chown root:root "$CONF"; chmod 644 "$CONF"

# --- la session du collègue : deux lignes ajoutées, jamais enregistrées ---
# vim exige un terminal : script(1) lui en fabrique un.
# :preserve force l'écriture du swap sur le disque, puis la session reste
# ouverte (le collègue est parti en réunion et n'a jamais fait :w).
setsid env TERM=xterm script -qec \
  "vim -u NONE \
       -c 'normal Gomax_upload_mb = 250' \
       -c 'normal Goworker_timeout = 120' \
       -c preserve \
       -c 'sleep 86400' $CONF" /dev/null \
  >/dev/null 2>&1 </dev/null &
disown || true
sleep 3

if ! ls "$DIR"/.frontal.conf.sw? >/dev/null 2>&1; then
  echo "le swap n'a pas été créé : vérifie que 'script' et 'vim' sont là" >&2
  exit 1
fi

echo
echo "Symptôme attendu :"
echo "  sudo vim $CONF affiche un pavé E325: ATTENTION et un menu,"
echo "  et les deux réglages ajoutés hier ne sont pas dans le fichier."
