#!/usr/bin/env bash
# setup_M02.sh — prépare le terrain du module 02 (système de fichiers)
# À lancer avec sudo : il monte un système de fichiers de lab et remplit /var.
# Idempotent : relançable sans effet de bord.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab02"
IMG=/var/lib/lab02/appdata.img
MNT=/srv/appdata
LOGIMG=/var/lib/lab02/varlog.img
LOGMNT=/var/log/factura

echo "== Préparation du module 02 =="
echo "   utilisateur : $LAB_USER"
echo "   base        : $BASE"

# ---------------------------------------------------------------------
# 1. Arborescence de travail de l'apprenant
# ---------------------------------------------------------------------
mkdir -p "$BASE"/{arbo,liens,inventaire,rapports,livraison}

# ---------------------------------------------------------------------
# 2. Arborescence à fouiller avec find (L2.3)
# ---------------------------------------------------------------------
A="$BASE/arbo"
mkdir -p "$A"/{app/src,app/node_modules/left-pad,app/.git/objects}
mkdir -p "$A"/{logs,archives,uploads,tmp,conf}

mkfile() {  # $1 chemin  $2 taille en Kio  $3 date (format touch -d)
  if [ ! -e "$1" ]; then
    dd if=/dev/urandom of="$1" bs=1024 count="$2" status=none
  fi
  touch -d "$3" "$1"
}

mkfile "$A/logs/access.log"        14000 "2026-09-18 08:12:00"
mkfile "$A/logs/access.log.1"      11000 "2026-09-11 00:05:00"
mkfile "$A/logs/error.log"           120 "2026-09-18 09:40:00"
mkfile "$A/logs/debug.log"         18000 "2026-05-02 03:00:00"
mkfile "$A/logs/audit ancien.log"    300 "2025-12-24 18:30:00"
mkfile "$A/archives/dump-2025-11.sql" 9000 "2025-11-30 23:00:00"
mkfile "$A/archives/dump-2026-08.sql" 9500 "2026-08-31 23:00:00"
mkfile "$A/uploads/photo1.jpg"      2200 "2026-09-17 14:00:00"
mkfile "$A/uploads/photo2.jpg"      2400 "2026-06-01 14:00:00"
mkfile "$A/uploads/CV Dupont.pdf"    900 "2026-09-16 10:10:00"
mkfile "$A/app/src/main.py"           12 "2026-09-18 11:00:00"
mkfile "$A/app/src/utils.py"           8 "2026-09-15 11:00:00"
mkfile "$A/app/node_modules/left-pad/index.js" 4 "2026-09-01 11:00:00"
mkfile "$A/app/.git/objects/pack.idx" 640 "2026-09-01 11:00:00"
mkfile "$A/conf/app.conf"              2 "2026-09-18 07:00:00"
mkfile "$A/conf/app.conf.bak"          2 "2026-02-10 07:00:00"

# des .tmp à éliminer (E2.x et L2.3)
for i in 1 2 3 4 5; do
  mkfile "$A/tmp/session-$i.tmp" 50 "2026-09-1$i 02:00:00"
done
mkfile "$A/uploads/scan provisoire.tmp" 70 "2026-09-14 02:00:00"

# propriétaires variés : voir la section 7 (propriétaires finaux)

# fichier creux : 2 Gio apparents, quelques blocs réels
if [ ! -e "$A/archives/disque-vm.img" ]; then
  truncate -s 2G "$A/archives/disque-vm.img"
  dd if=/dev/urandom of="$A/archives/disque-vm.img" bs=1M count=4 \
     seek=0 conv=notrunc status=none
fi

# ---------------------------------------------------------------------
# 3. Terrain de jeu liens / types de fichiers (E2.x et L2.4)
# ---------------------------------------------------------------------
L="$BASE/liens"
mkdir -p "$L"/{source,copie,deplace}

[ -e "$L/source/rapport.txt" ] || \
  printf 'rapport trimestriel v1\n' > "$L/source/rapport.txt"
[ -e "$L/source/dur.txt" ] || ln "$L/source/rapport.txt" "$L/source/dur.txt"
[ -L "$L/source/mou.txt" ] || ln -s rapport.txt "$L/source/mou.txt"
[ -L "$L/source/absolu.txt" ] || \
  ln -s "$L/source/rapport.txt" "$L/source/absolu.txt"
[ -L "$L/casse.txt" ] || \
  ln -s /srv/factura/inexistant.txt "$L/casse.txt"

# fifo, socket, périphérique caractère : autres types de fichiers
[ -p "$L/file-attente" ] || mkfifo "$L/file-attente"
[ -c "$L/faux-null" ]    || mknod "$L/faux-null" c 1 3
if [ ! -S "$L/app.sock" ] && command -v python3 >/dev/null; then
  python3 - "$L/app.sock" <<'PY'
import socket, sys, os
p = sys.argv[1]
if os.path.exists(p):
    os.unlink(p)
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(p)
s.close()
PY
fi

# ---------------------------------------------------------------------
# 4. Livraison à ranger selon le FHS (L2.1)
# ---------------------------------------------------------------------
TARDIR=$(mktemp -d)
mkdir -p "$TARDIR/factura-2.4"
cat > "$TARDIR/factura-2.4/facturad" <<'EOF'
#!/usr/bin/env bash
# facturad — démon de facturation (simulacre pour le lab)
CONF=${FACTURA_CONF:-/etc/factura/factura.conf}
[ -r "$CONF" ] || { echo "conf introuvable : $CONF" >&2; exit 78; }
echo "$$" > "${RUNTIME_DIRECTORY:-/run/factura}/facturad.pid" 2>/dev/null
while :; do
  printf '%s facturad vivant\n' "$(date -Is)" \
    >> /var/log/factura/facturad.log
  sleep 5
done
EOF
cat > "$TARDIR/factura-2.4/facturactl" <<'EOF'
#!/usr/bin/env bash
# facturactl — client d'administration (simulacre)
echo "facturactl 2.4 — conf: ${FACTURA_CONF:-/etc/factura/factura.conf}"
EOF
cat > "$TARDIR/factura-2.4/factura.conf" <<'EOF'
# configuration facturad 2.4
listen = 127.0.0.1:8480
data_dir = /var/lib/factura
export_dir = /srv/factura/exports
log_level = info
EOF
cat > "$TARDIR/factura-2.4/factura.service" <<'EOF'
[Unit]
Description=Demon de facturation
After=network.target

[Service]
ExecStart=/opt/factura/bin/facturad
RuntimeDirectory=factura
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
printf 'id;client;montant\n1;ACME;1240.00\n' \
  > "$TARDIR/factura-2.4/exports-exemple.csv"
printf 'base sqlite initiale\n' > "$TARDIR/factura-2.4/factura.db"
printf 'Factura 2.4 — voir INSTALL\n' > "$TARDIR/factura-2.4/README.md"
chmod +x "$TARDIR/factura-2.4/facturad" "$TARDIR/factura-2.4/facturactl"

if [ ! -f "$BASE/livraison/factura-2.4.tar.gz" ]; then
  tar -czf "$BASE/livraison/factura-2.4.tar.gz" -C "$TARDIR" factura-2.4
fi
rm -rf "$TARDIR"

# ---------------------------------------------------------------------
# 5. Système de fichiers dédié /srv/appdata (L2.2, L2.4, BF2.1)
# ---------------------------------------------------------------------
mkdir -p /var/lib/lab02 "$MNT"
if [ ! -f "$IMG" ]; then
  truncate -s 256M "$IMG"
  mkfs.ext4 -q -F -L labappdata "$IMG"
fi
if ! findmnt -n "$MNT" >/dev/null 2>&1; then
  mount -o loop "$IMG" "$MNT"
fi
mkdir -p "$MNT"/{exports,incoming}
chown -R "$LAB_USER":"$LAB_USER" "$MNT"/exports "$MNT"/incoming

# ---------------------------------------------------------------------
# 6. /var/log/factura : partition dédiée saturée (L2.2)
# ---------------------------------------------------------------------
mkdir -p /var/cache/factura/thumbs /var/lib/factura "$LOGMNT"

if [ ! -f "$LOGIMG" ]; then
  truncate -s 300M "$LOGIMG"
  mkfs.ext4 -q -F -m 1 -L labvarlog "$LOGIMG"
fi
if ! findmnt -n "$LOGMNT" >/dev/null 2>&1; then
  mount -o loop "$LOGIMG" "$LOGMNT"
fi

# regénéré s'il fait moins de 100 Mio : relancer le setup remet en place
# le scénario de L2.2
taille=$(stat -c %s "$LOGMNT/factura.log" 2>/dev/null || echo 0)
if [ "$taille" -lt $((100 * 1024 * 1024)) ]; then
  dd if=/dev/urandom of="$LOGMNT/factura.log" bs=1M count=180 status=none
fi
for d in 1 2 3 4 5 6; do
  f="$LOGMNT/factura.log.$d.gz"
  [ -e "$f" ] || dd if=/dev/urandom of="$f" bs=1M count=12 status=none
done
# mémorise l'inode du journal : check_M02_02 vérifie qu'il n'a pas changé
stat -c %i "$LOGMNT/factura.log" > /var/lib/lab02/factura.log.inode

# ---------------------------------------------------------------------
# 6 bis. Un processus qui tient factura.log ouvert en écriture
#        (sinon l'étape 4 de L2.2 n'a aucun intérêt)
# ---------------------------------------------------------------------
cat > /usr/local/sbin/lab-collector <<'EOF'
#!/usr/bin/env bash
# lab-collector — simulacre de collecteur applicatif.
# Ouvre son fichier une fois pour toutes et ne le rouvre jamais :
# c'est ce comportement qui rend « rm » inopérant sur son journal.
set -u
CIBLE="${1:-/var/log/factura/factura.log}"
exec 3>>"$CIBLE"
while :; do
  printf '%s collecte ok\n' "$(date -Is)" >&3
  sleep 5
done
EOF
chmod 755 /usr/local/sbin/lab-collector

lab_demarrer() {  # $1 = nom de service, $2 = fichier cible
  if [ -d /run/systemd/system ]; then
    cat > "/etc/systemd/system/$1.service" <<EOF
[Unit]
Description=Collecteur de lab ($2)

[Service]
ExecStart=/usr/local/sbin/lab-collector $2
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now "$1.service" >/dev/null 2>&1 || true
  else
    pgrep -f "^bash /usr/local/sbin/lab-collector $2" \
      >/dev/null 2>&1 || \
      setsid nohup /usr/local/sbin/lab-collector "$2" \
        >/dev/null 2>&1 < /dev/null &
  fi
}

lab_demarrer lab-collector "$LOGMNT/factura.log"
if [ ! -e /var/cache/factura/thumbs/t0001.dat ]; then
  for i in $(seq -w 1 400); do
    dd if=/dev/urandom of="/var/cache/factura/thumbs/t0$i.dat" \
       bs=1024 count=40 status=none
  done
fi
[ -e /var/lib/factura/factura.db ] || \
  printf 'base sqlite de production\n' > /var/lib/factura/factura.db

# ---------------------------------------------------------------------
# 7. Propriétaires finaux
# ---------------------------------------------------------------------
chown -R "$LAB_USER":"$LAB_USER" "$BASE"
# un seul fichier à www-data (E2.11, L2.3). Pas les .jpg : L2.4 doit pouvoir
# les lier en dur et les modifier sans sudo (fs.protected_hardlinks=1).
if getent passwd www-data >/dev/null; then
  chown www-data:www-data "$A/uploads/CV Dupont.pdf" 2>/dev/null || true
fi

# avertissement si un outil de confort manque
for p in lsof ncdu plocate tree; do
  command -v "$p" >/dev/null 2>&1 || \
    echo "  note : $p n'est pas installé (voir §2.1)"
done

cat <<EOF

Prêt. Points d'entrée :
  $BASE/arbo            arborescence à fouiller avec find (L2.3)
  $BASE/liens           liens, fifo, socket, périphérique (E2.x, L2.4)
  $BASE/livraison/factura-2.4.tar.gz   livraison à ranger (L2.1)
  $MNT                  système de fichiers dédié, 256 Mio (L2.4, BF2.1)
  $LOGMNT      partition dédiée de 300 Mio, saturée (L2.2)
  /var/cache/factura    400 petits fichiers de cache (L2.2)
EOF
