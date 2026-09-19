#!/usr/bin/env bash
# check_M15_05.sh — vérifie le lab L15.5 (Redis sécurisé et dimensionné) sur lab-db
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L15.5 =="
CONF="$(sudo -n cat /etc/redis/redis.conf 2>/dev/null | grep -Ev '^\s*#|^\s*$')"
[ -n "$CONF" ] || { ko "impossible de lire /etc/redis/redis.conf (sudo)"; exit 1; }
cfg() { grep -E "^$1\s" <<<"$CONF" | tail -1 | awk '{$1=""; print substr($0,2)}'; }

U=redis-server.service
[ "$(systemctl is-active $U 2>/dev/null)" = active ] && ok "$U actif" || ko "$U inactif"
ss -Hltn 'sport = :6379' | grep -q '10.10.10.12:6379' && ok "écoute sur 10.10.10.12" \
  || ko "pas d'écoute sur 10.10.10.12 (bind, puis restart)"
ss -Hltn 'sport = :6379' | grep -q '127.0.0.1:6379' && ok "écoute sur 127.0.0.1" \
  || ko "pas d'écoute sur 127.0.0.1"
ss -Hltn 'sport = :6379' | grep -q '0.0.0.0:6379' && ko "écoute sur 0.0.0.0" || ok "pas d'écoute sur 0.0.0.0"
[ "$(cfg protected-mode)" = yes ] && ok "protected-mode yes" || ko "protected-mode n'est pas yes"

redis-cli PING 2>&1 | grep -q NOAUTH && ok "PING sans authentification refusé" \
  || ko "PING sans authentification accepté (user default off ou requirepass)"
grep -qE '^user default off' <<<"$CONF" && ok "user default désactivé" \
  || ko "user default n'est pas off (ACL)"
FA="$(grep -E '^user factura on' <<<"$CONF")"
[ -n "$FA" ] && ok "utilisateur ACL factura défini" || ko "utilisateur ACL factura absent"
grep -q -- '-@dangerous' <<<"$FA" && ok "factura sans commandes dangereuses" \
  || ko "factura n'a pas -@dangerous"
grep -qE '~(sess|factura|user):' <<<"$FA" && ok "factura limité à ses préfixes de clés" \
  || ko "factura n'est pas limité par motif de clés (~sess:* ...)"
grep -qE '^user (admin|ops)[a-z0-9_-]* on' <<<"$CONF" && ok "un utilisateur d'administration existe" \
  || note "pas d'utilisateur admin/ops : comment administres-tu Redis ?"

MM="$(cfg maxmemory)"; POL="$(cfg maxmemory-policy)"
[ "$MM" = 128mb ] && ok "maxmemory 128mb" || ko "maxmemory vaut « $MM », attendu 128mb"
[ -n "$POL" ] && [ "$POL" != noeviction ] && ok "maxmemory-policy $POL" \
  || ko "maxmemory-policy absente ou noeviction (choisis pour sessions + file)"
[ "$(cfg appendonly)" = yes ] && ok "appendonly yes" || ko "appendonly n'est pas yes"
[ "$(cfg appendfsync)" = everysec ] && ok "appendfsync everysec" || ko "appendfsync n'est pas everysec"
sudo -n ls /var/lib/redis/appendonlydir/ >/dev/null 2>&1 && ok "appendonlydir/ présent" \
  || ko "/var/lib/redis/appendonlydir absent (l'AOF n'est pas actif à chaud)"
sudo -n ls /var/backups/redis/dump-*.rdb >/dev/null 2>&1 && ok "copie de dump.rdb présente" \
  || ko "aucune copie dump-*.rdb dans /var/backups/redis"
[ -f "$HOME/lab15/conf/lab-db/redis.conf.diff" ] && ok "redis.conf.diff présent" \
  || ko "~/lab15/conf/lab-db/redis.conf.diff absent"
[ -f "$HOME/lab15/rapports/redis.md" ] && [ "$(wc -l < "$HOME/lab15/rapports/redis.md")" -ge 20 ] \
  && ok "rapport redis.md présent" || ko "rapport redis.md absent ou trop court"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
