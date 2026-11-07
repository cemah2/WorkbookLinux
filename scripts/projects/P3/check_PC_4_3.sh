#!/usr/bin/env bash
# check_PC_4_3.sh — vérifie le ticket PC.4.3 (redis qui swappe)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.4.3 =="
SAUV=/root/.breakfix-backup; ID=PC_4_3
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo (lecture redis.conf)" >&2
                         exit 1; }
P='F4ctura-Redis-2026'
r() { redis-cli -a "$P" --no-auth-warning "$@" 2>/dev/null; }

r ping | grep -q PONG && ok "Redis répond" || ko "Redis ne répond pas"

# 1. une limite mémoire est posée
MM=$(r config get maxmemory | tail -1)
if [ "${MM:-0}" -gt 0 ]; then
  ok "maxmemory fixé à $MM octets"
else
  ko "maxmemory = 0 : Redis peut encore consommer toute la RAM"
fi

# 2. une politique d'éviction utile
POL=$(r config get maxmemory-policy | tail -1)
case "$POL" in
  noeviction|"") ko "maxmemory-policy = $POL : les écritures échoueront au \
lieu d'évincer (choisis allkeys-lru ou volatile-lru selon l'usage)" ;;
  *) ok "maxmemory-policy = $POL" ;;
esac

# 3. la mémoire utilisée est redescendue sous la limite
USED=$(r info memory | awk -F: '/used_memory:/ {print $2}' | tr -dc 0-9)
if [ -n "$USED" ] && [ "${MM:-0}" -gt 0 ] && [ "$USED" -le "$MM" ]; then
  ok "used_memory ($USED) sous maxmemory ($MM)"
else
  note "used_memory=$USED, maxmemory=$MM"
fi

# 4. la VM ne swappe plus activement
read -r SI SO < <(vmstat 1 2 | tail -1 | awk '{print $7, $8}')
if [ "${SI:-0}" -eq 0 ] && [ "${SO:-0}" -eq 0 ]; then
  ok "aucun swap actif (si=$SI so=$SO)"
else
  ko "la machine swappe encore (si=$SI so=$SO) : la pression mémoire persiste"
fi

# 5. la persistance/limite est durable (dans le fichier de conf)
grep -qE '^maxmemory\s+[1-9]' /etc/redis/redis.conf \
  && ok "maxmemory écrit dans redis.conf (survivra au redémarrage)" \
  || ko "maxmemory non persisté dans redis.conf (config set seul se perd)"

if [ -r "$SAUV/$ID.boot_id" ]; then
  [ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$SAUV/$ID.boot_id")" ] \
    && ok "pas de redémarrage de la VM" \
    || ko "MALUS : la VM a redémarré (l'énoncé l'interdit)"
fi
[ -r "$SAUV/$ID.debut" ] && note "temps écoulé : \
$(( ($(date +%s) - $(cat "$SAUV/$ID.debut")) / 60 )) min"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
