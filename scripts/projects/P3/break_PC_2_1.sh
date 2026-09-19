#!/usr/bin/env bash
# break_PC_2_1.sh — ticket PC.2.1 (lab-db)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_2_1; mkdir -p "$SAUV"
PGD=/etc/postgresql/16/main/conf.d
LOGD=/var/log/postgresql
[ -d "$PGD" ] || { echo "lance d'abord setup_P3.sh (rôle db)" >&2; exit 1; }
cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"
sudo -u postgres psql -tAqc \
  "select extract(epoch from pg_postmaster_start_time())::bigint" \
  > "$SAUV/$ID.pgstart" 2>/dev/null || true

# 1. Journalisation exhaustive activée « pour déboguer » et jamais retirée
cat > "$PGD/30-debug.conf" <<'EOF'
# debug lenteurs du 12/09 — Julie
log_statement = 'all'
log_min_duration_statement = 0
log_connections = on
log_disconnections = on
EOF
touch -d '6 days ago' "$PGD/30-debug.conf"
pg_ctlcluster 16 main reload

# 2. Un slot de réplication d'un réplica décommissionné, qui retient le WAL
sudo -u postgres psql -tAqc "select pg_create_physical_replication_slot(\
'replica_reporting') where not exists (select 1 from pg_replication_slots \
where slot_name = 'replica_reporting')" >/dev/null
for i in 1 2 3; do
  sudo -u postgres psql -tAqc "select pg_switch_wal()" >/dev/null
  sudo -u postgres psql -tAqc "insert into factures(client_id,montant) \
select 1, 1 from generate_series(1,2000)" >/dev/null
done

# 3. Des journaux « tournés » qui remplissent le disque à 95 %
mkdir -p "$LOGD"
FS_TOTAL=$(df -kP "$LOGD" | awk 'NR==2 {print $2}')
FS_USED=$(df -kP "$LOGD" | awk 'NR==2 {print $3}')
CIBLE=$(( FS_TOTAL * 95 / 100 ))
A_AJOUTER=$(( CIBLE - FS_USED ))
if [ "$A_AJOUTER" -gt 0 ]; then
  N=1
  while [ "$A_AJOUTER" -gt 0 ] && [ "$N" -le 30 ]; do
    MO=$(( A_AJOUTER / 1024 )); [ "$MO" -gt 1024 ] && MO=1024
    [ "$MO" -lt 1 ] && break
    F="$LOGD/postgresql-16-main.log.$N"
    fallocate -l "${MO}M" "$F"
    touch -d "$N days ago" "$F"
    A_AJOUTER=$(( A_AJOUTER - MO * 1024 )); N=$((N+1))
  done
fi
chown postgres:adm "$LOGD"/postgresql-16-main.log.* 2>/dev/null || true
# un peu de vrai trafic pour que le journal courant grossisse visiblement
for i in $(seq 1 200); do
  sudo -u postgres psql -tAqc "select count(*) from factures" >/dev/null
done

cat <<'EOF'

Symptôme attendu : alerte Prometheus « DiskSpaceLow » sur lab-db, le
système de fichiers racine est à 95 %. PostgreSQL fonctionne encore.
EOF
