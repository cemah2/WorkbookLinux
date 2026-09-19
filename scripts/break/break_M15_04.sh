#!/usr/bin/env bash
# break_M15_04.sh — panne BF15.4 (à lancer sur lab-db, après L15.3)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
CONFD=/etc/postgresql/16/main/conf.d
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
PW="$(grep '^PGPASSWORD=' /etc/factura/db.env | cut -d= -f2-)"
[ -n "$PW" ] || { echo "/etc/factura/db.env absent : lance setup_M15.sh" >&2; exit 1; }
[ -f "$SAUV/M15_04.conf.d.tar" ] || tar -cf "$SAUV/M15_04.conf.d.tar" -C "$CONFD" .

# « optimisation mémoire » de la semaine dernière, effective au restart
cat > "$CONFD/90-tuning.conf" <<'EOF2'
# tuning 2026-09 : moins de backends = moins de RAM
max_connections = 20
EOF2
chown postgres:postgres "$CONFD/90-tuning.conf"
if [ -d /run/systemd/system ]; then systemctl restart postgresql@16-main.service
else pg_ctlcluster 16 main restart; fi
for _ in $(seq 20); do sudo -u postgres psql -Atqc 'SELECT 1' >/dev/null 2>&1 && break; sleep 1; done

# des connexions applicatives jamais fermées (17 = 20 - 3 réservées)
pkill -f '^bf15-idle-' 2>/dev/null || true
for i in $(seq 17); do
  setsid -f bash -c "exec -a bf15-idle-$i sleep 86400 | \
    PGPASSWORD='$PW' PGAPPNAME=factura-api psql -h 127.0.0.1 -U factura_app \
    -d factura_demo -q >/dev/null 2>&1" </dev/null >/dev/null 2>&1
done
sleep 2

cat <<'EOF2'

Symptôme attendu : toute nouvelle connexion de l'application échoue avec
« FATAL: remaining connection slots are reserved for roles with the
SUPERUSER attribute ». La charge de lab-db est nulle, le disque est libre.
Interdit : redémarrer PostgreSQL.
EOF2
