#!/usr/bin/env bash
# break_M15_06.sh — panne BF15.6 (à lancer sur lab-db, après L15.3)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
PW="$(grep '^PGPASSWORD=' /etc/factura/db.env | cut -d= -f2-)"
[ -n "$PW" ] || { echo "/etc/factura/db.env absent : lance setup_M15.sh" >&2; exit 1; }
DEST=/var/backups/factura-offsite

# le compte dédié du collègue, avec son .pgpass... créé avec umask 022
getent passwd dumpops >/dev/null || \
  useradd -r -m -d /var/lib/dumpops -s /bin/sh dumpops
install -d -o dumpops -g dumpops -m 0750 "$DEST"
echo "127.0.0.1:5432:factura_demo:factura_app:$PW" > /var/lib/dumpops/.pgpass
chown dumpops:dumpops /var/lib/dumpops/.pgpass
chmod 0644 /var/lib/dumpops/.pgpass

cat > /usr/local/bin/factura-offsite.sh <<'EOF2'
#!/bin/sh
# export SQL de factura_demo pour le site distant (copie rsync par ailleurs)
pg_dump -h 127.0.0.1 -U factura_app factura_demo \
  > /var/backups/factura-offsite/factura-$(date +%Y%m%d-%H%M).sql 2>/dev/null
EOF2
chmod 0755 /usr/local/bin/factura-offsite.sh
cat > /etc/cron.d/factura-offsite <<'EOF2'
# export factura_demo vers le site distant (toutes les 2 min pour le lab)
*/2 * * * * dumpops /usr/local/bin/factura-offsite.sh
EOF2
chmod 0644 /etc/cron.d/factura-offsite
# un premier passage tout de suite, comme cron le ferait
sudo -u dumpops -H env -i HOME=/var/lib/dumpops PATH=/usr/bin:/bin SHELL=/bin/sh \
  /bin/sh /usr/local/bin/factura-offsite.sh </dev/null >/dev/null 2>&1 || true

cat <<'EOF2'

Symptôme attendu : /var/backups/factura-offsite/ contient des fichiers
factura-<date>.sql à la bonne heure, tous de 0 octet. Lancé à la main par
le collègue, « ça marche ». cron n'a rien signalé.
Interdit : passer par postgres/peer, mettre le mot de passe dans cron.
EOF2
