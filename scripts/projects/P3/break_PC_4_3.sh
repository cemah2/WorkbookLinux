#!/usr/bin/env bash
# break_PC_4_3.sh — ticket PC.4.3 (lab-db)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_4_3; mkdir -p "$SAUV"
CONF=/etc/redis/redis.conf
[ -f "$CONF" ] || { echo "lance d'abord setup_P3.sh (rôle db)" >&2; exit 1; }
cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"
[ -f "$SAUV/$ID.redis.conf" ] || cp -a "$CONF" "$SAUV/$ID.redis.conf"

# Aucune limite mémoire + pas de politique d'éviction : Redis grossit sans
# borne. On charge des clés pour occuper la mémoire et déclencher le swap.
sed -i -E 's/^maxmemory .*/maxmemory 0/' "$CONF"
grep -qE '^maxmemory ' "$CONF" || echo 'maxmemory 0' >> "$CONF"
sed -i -E '/^maxmemory-policy /d' "$CONF"
echo 'maxmemory-policy noeviction' >> "$CONF"
[ -d /run/systemd/system ] && systemctl restart redis-server || true
sleep 1

PASS='F4ctura-Redis-2026'
# on remplit jusqu'à ~60 % de la RAM ou 400 Mo, au plus petit
MEMKB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
CIBLE_MO=$(( MEMKB / 1024 * 60 / 100 )); [ "$CIBLE_MO" -gt 400 ] && CIBLE_MO=400
redis-cli -a "$PASS" --no-auth-warning config set save "" >/dev/null 2>&1 || true
VAL=$(head -c 100000 /dev/zero | tr '\0' 'x')
N=$(( CIBLE_MO * 10 ))          # ~100 Ko par clé
{
  echo "SELECT 0"
  for i in $(seq 1 "$N"); do echo "SET sess:$i $VAL"; done
} | redis-cli -a "$PASS" --no-auth-warning --pipe >/dev/null 2>&1 || true
# on abaisse la réticence du noyau à swapper pour rendre le symptôme visible
sysctl -q vm.swappiness=80 2>/dev/null || true

cat <<'EOF'

Symptôme attendu : Redis répond lentement, la VM lab-db swappe (si/so non
nuls dans vmstat), et « redis-cli info memory » montre used_memory qui
dépasse largement le raisonnable, sans maxmemory. Le reste de la VM rame.
EOF
