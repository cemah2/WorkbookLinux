#!/usr/bin/env bash
# break_M15_05.sh — panne BF15.5 (à lancer sur lab-db, après L15.5)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
CONF=/etc/redis/redis.conf
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
[ -f "$CONF" ] || { echo "$CONF absent : redis-server n'est pas installé" >&2; exit 1; }
[ -f "$SAUV/M15_05.redis.conf" ] || cp -a "$CONF" "$SAUV/M15_05.redis.conf"

# « réglage mémoire » après une alerte de la supervision
sed -i -E '/^\s*maxmemory(-policy)?\s/d' "$CONF"
cat >> "$CONF" <<'EOF2'

# alerte supervision 2026-09 : limiter la RAM de Redis
maxmemory 1mb
maxmemory-policy noeviction
EOF2
if [ -d /run/systemd/system ]; then
  systemctl restart redis-server.service 2>/dev/null || systemctl restart redis.service
fi

cat <<'EOF2'

Symptôme attendu : redis-app.py (depuis lab-web ou lab-db) s'arrête au
bout de quelques tours avec « ECRITURE REFUSEE ». redis-cli PING répond
PONG, le service est actif, INFO clients est normal.
Interdit : FLUSHALL, redémarrer Redis.
EOF2
