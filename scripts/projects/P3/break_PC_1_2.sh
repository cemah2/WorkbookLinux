#!/usr/bin/env bash
# break_PC_1_2.sh — ticket PC.1.2 (lab-db)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_1_2; mkdir -p "$SAUV"
PGD=/etc/postgresql/16/main/conf.d
[ -d "$PGD" ] || { echo "lance d'abord setup_P3.sh (rôle db)" >&2; exit 1; }

cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"

# 1. Un « tuning » passé vendredi soir, sans ticket.
if [ ! -f "$PGD/20-tuning.conf" ]; then
  cat > "$PGD/20-tuning.conf" <<'EOF'
# tuning perf — test vendredi, à valider lundi
max_connections = 8
EOF
  touch -d 'last friday 18:40' "$PGD/20-tuning.conf"
  pg_ctlcluster 16 main restart
fi

# 2. Un ETL de la compta qui ouvre des transactions et ne les ferme jamais.
cat > /usr/local/bin/etl-compta <<'EOF'
#!/usr/bin/env bash
# etl-compta — synchronisation comptable (v0.9, prototype)
export PGPASSWORD='F4ctura-Pr0d-2026!'
for i in 1 2 3 4 5; do
  ( printf 'BEGIN;\nSELECT count(*) FROM factures;\n'; sleep 86400 ) \
    | psql -q -h 127.0.0.1 -U factura -d factura >/dev/null 2>&1 &
done
wait
EOF
chmod 0755 /usr/local/bin/etl-compta
pgrep -f /usr/local/bin/etl-compta >/dev/null \
  || setsid nohup /usr/local/bin/etl-compta >/dev/null 2>&1 < /dev/null &
sleep 3

cat <<'EOF'

Symptôme attendu : l'application Factura affiche « FATAL: sorry, too many
clients already » à chaque connexion. Les utilisateurs ne peuvent plus se
connecter. Test : psql -h 127.0.0.1 -U factura -d factura -c 'select 1'
EOF
