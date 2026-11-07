#!/usr/bin/env bash
# break_M30_02.sh — panne BF30.2 (archivage des WAL en échec silencieux)
# À lancer sur lab-db, avec sudo. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
[ "$(sudo -u postgres psql -qAt -c 'SHOW archive_mode' 2>/dev/null)" = on ] || {
  echo "l'archivage n'est pas actif : termine L30.3 d'abord" >&2; exit 1; }
K=/var/lib/postgresql/.ssh

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
echo "rotation simulée le $(date -Is)" > "$SAUV/M30_02.etat"

# « rotation des clés » : l'ancienne clé est rangée, aucune nouvelle n'est posée
if [ -f "$K/id_archive" ]; then
  install -d -o postgres -g postgres -m 700 "$K/ancien"
  mv "$K/id_archive" "$K/id_archive.pub" "$K/ancien/" 2>/dev/null || true
fi

# de l'activité, pour que pg_wal grossisse vite
sudo -u postgres psql -qAt -d lab30 <<'SQL' >/dev/null
CREATE TABLE IF NOT EXISTS bourrage (id bigint, charge text);
INSERT INTO bourrage SELECT g, repeat(md5(g::text), 8) FROM generate_series(1, 400000) g;
SELECT pg_switch_wal();
SQL

cat <<'EOF'

Symptôme attendu : l'espace libre de /var/lib/postgresql diminue
(du -sh /var/lib/postgresql/16/main/pg_wal), l'application fonctionne,
aucune erreur côté applicatif.
EOF
