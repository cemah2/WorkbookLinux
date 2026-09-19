#!/usr/bin/env bash
# break_PA_01.sh — incident INC-A1 (à lancer sur lab-db)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
[ "$(hostname -s)" = lab-db ] || { echo "à lancer sur lab-db" >&2; exit 1; }

HBA=/etc/postgresql/16/main/pg_hba.conf
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
[ -f "$HBA" ] || { echo "$HBA absent : PA.2 n'est pas fait" >&2; exit 1; }

[ -f "$SAUV/PA_01.pg_hba.conf" ] || cp -a "$HBA" "$SAUV/PA_01.pg_hba.conf"

# Un « durcissement » passé en urgence un vendredi soir, sans ticket.
if ! grep -q '# hardening 2026-09' "$HBA"; then
  TMP="$(mktemp)"
  {
    echo "# hardening 2026-09 : restreindre l'acces applicatif"
    echo "host    all             all             10.10.10.11/32          reject"
    cat "$HBA"
  } > "$TMP"
  cat "$TMP" > "$HBA"; rm -f "$TMP"
fi
systemctl reload postgresql@16-main.service

cat <<'EOF'

Symptôme attendu : depuis lab-adm, https://factura.lab.local/ affiche
« état : degraded » et /api/health renvoie 503. Les factures créées ne sont
plus enregistrées. Sur lab-db, PostgreSQL est « active (running) », le port
5432 est en écoute, et « sudo -u postgres psql -d factura » fonctionne.
EOF
