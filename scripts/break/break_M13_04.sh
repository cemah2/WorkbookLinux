#!/usr/bin/env bash
# break_M13_04.sh — panne BF13.4 (copytruncate : fichier creux et lignes
#                   perdues)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
CONF=/etc/logrotate.d/factura-acces
LOGD=/var/log/factura
FIC="$LOGD/acces.log"
UDROPD=/etc/systemd/system/factura-ecrivain.service.d
UDROP="$UDROPD/10-sans-append.conf"
mkdir -p "$SAUV" "$UDROPD"

[ -d "$LOGD" ] || { echo "$LOGD absent : lance setup_M13.sh" >&2; exit 1; }

# --- 1. la configuration de rotation « recommandée par un forum » -------
[ -e "$CONF" ] && [ ! -f "$SAUV/M13_04.logrotate" ] && \
  cp -a "$CONF" "$SAUV/M13_04.logrotate"

cat > "$CONF" <<'EOF'
/var/log/factura/acces.log {
    daily
    rotate 7
    size 1M
    compress
    missingok
    notifempty
    copytruncate
}
EOF
chown root:root "$CONF"
chmod 0644 "$CONF"

# --- 2. l'application ouvre son log sans O_APPEND -----------------------
cat > "$UDROP" <<'EOF'
[Service]
ExecStart=
ExecStart=/opt/factura/bin/factura-ecrivain.py \
          --fichier /var/log/factura/acces.log --periode 0.2 --sans-append
EOF
chmod 0644 "$UDROP"

# --- 3. l'état dans lequel la nuit a laissé le fichier ------------------
# Un copytruncate sur un fichier de 800 Mo laisse deux traces : le trou
# de numérotation (lignes écrites pendant la copie) et la zone creuse
# (le processus écrit à sa position absolue, le noyau comble de zéros).
[ -f "$SAUV/M13_04.acces.log.debut" ] || \
  { head -c 200000 "$FIC" > "$SAUV/M13_04.acces.log.debut" 2>/dev/null \
    || true; }

DERNIER=$(grep -ao 'seq=[0-9]*' "$FIC" 2>/dev/null | tail -1 | cut -d= -f2)
[ -n "${DERNIER:-}" ] || DERNIER=20000

python3 - "$FIC" "$DERNIER" <<'PYEOF'
import datetime as dt
import os
import sys

fic, dernier = sys.argv[1], int(sys.argv[2])
trou = 640                      # lignes écrites pendant la copie : perdues
creux = 800 * 1024 * 1024       # position où en était le processus

fd = os.open(fic, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o640)
os.lseek(fd, creux, os.SEEK_SET)
t = dt.datetime.now() - dt.timedelta(minutes=13)
for i in range(4000):
    t += dt.timedelta(seconds=0.2)
    ligne = "%s seq=%d service=factura-acces etat=ok\n" % (
        t.strftime("%Y-%m-%dT%H:%M:%S%z"), dernier + trou + i)
    os.write(fd, ligne.encode())
os.close(fd)
PYEOF

chown factura:adm "$FIC" 2>/dev/null || chown factura:factura "$FIC"
chmod 0640 "$FIC"

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload
  systemctl restart factura-ecrivain.service >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : « ls -lh /var/log/factura/acces.log » annonce 800 Mo,
« du -h » sur le même fichier en annonce une douzaine, « wc -l » compte
quelques milliers de lignes, et les numéros de séquence sautent de
plusieurs centaines après chaque rotation. « less » affiche des ^@.
EOF
