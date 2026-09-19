#!/usr/bin/env bash
# break_M15_03.sh — panne BF15.3 (à lancer sur lab-db, après L15.3)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
HBA=/etc/postgresql/16/main/pg_hba.conf
CONFD=/etc/postgresql/16/main/conf.d
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
grep -q '10.10.10.11' "$HBA" || { echo "pas de ligne 10.10.10.11 dans pg_hba : fais L15.3" >&2; exit 1; }
PW="$(grep '^PGPASSWORD=' /etc/factura/db.env | cut -d= -f2-)"
[ -n "$PW" ] || { echo "/etc/factura/db.env absent : lance setup_M15.sh" >&2; exit 1; }

[ -f "$SAUV/M15_03.pg_hba.conf" ] || cp -a "$HBA" "$SAUV/M15_03.pg_hba.conf"

# 1. « préparation du renommage » : la base s'appellera factura
sed -i -E '/10\.10\.10\.11/ s/\bfactura_demo\b/factura/' "$HBA"
# 2. « modernisation » : compatibilité ancien pilote
cat > "$CONFD/90-migration.conf" <<'EOF2'
password_encryption = md5   # compat ancien pilote applicatif (migration)
EOF2
chown postgres:postgres "$CONFD/90-migration.conf"
sudo -u postgres psql -Atqc "SELECT pg_reload_conf()" >/dev/null
sleep 1
sudo -u postgres psql -Atqc "ALTER ROLE factura_app PASSWORD '$PW'" >/dev/null

cat <<'EOF2'

Symptôme attendu : depuis lab-web, psql -h 10.10.10.12 -U factura_app
-d factura_demo échoue, alors que le mot de passe de /etc/factura/db.env
n'a pas changé. PostgreSQL est actif, écoute sur 10.10.10.12:5432 et
« sudo -u postgres psql -d factura_demo » fonctionne.
EOF2
