#!/usr/bin/env bash
# check_PC_1_2.sh — vérifie le ticket PC.1.2 (max_connections atteint)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.1.2 =="
SAUV=/root/.breakfix-backup; ID=PC_1_2
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo (accès postgres)" >&2; exit 1; }
q() { sudo -u postgres psql -tAqc "$1" 2>/dev/null; }

# 1. le service répond
q 'select 1' | grep -q 1 && ok "PostgreSQL répond" \
  || ko "PostgreSQL ne répond pas (pg_lsclusters, journalctl -u postgresql@16-main)"

# 2. les utilisateurs peuvent se connecter, plusieurs à la fois
export PGPASSWORD='F4ctura-Pr0d-2026!'
NB=$( for i in $(seq 1 10); do
        ( psql -q -h 127.0.0.1 -U factura -d factura \
            -c 'select pg_sleep(2)' >/dev/null 2>&1 && echo ok ) &
      done; wait ) ; NB=$(printf '%s\n' "$NB" | grep -c ok)
[ "$NB" -ge 10 ] && ok "10 connexions applicatives simultanées acceptées" \
  || ko "seulement $NB/10 connexions simultanées passent (pg_stat_activity ?)"

# 3. le fuiteur de sessions
if pgrep -f /usr/local/bin/etl-compta >/dev/null; then
  ko "le processus qui garde des sessions ouvertes tourne encore"
else
  ok "plus de processus retenant des sessions"
fi
IIT=$(q "select count(*) from pg_stat_activity where state = \
'idle in transaction' and xact_start < now() - interval '5 min'")
[ "${IIT:-1}" -eq 0 ] && ok "aucune session « idle in transaction » ancienne" \
  || ko "$IIT session(s) idle in transaction depuis > 5 min"

# 4. le paramètre de fond
MC=$(q 'show max_connections')
if [ "${MC:-0}" -ge 100 ]; then
  ok "max_connections effectif = $MC"
else
  if grep -rhsE '^\s*max_connections\s*=\s*[0-9]+' /etc/postgresql/16/main/ \
       | tail -1 | grep -qE '=\s*([1-9][0-9]{2,})'; then
    note "max_connections=$MC en mémoire, valeur corrigée en attente de \
restart (fenêtre 12h30) : accepté si tracé dans le ticket"
    ok "max_connections corrigé dans la configuration"
  else
    ko "max_connections = $MC (où est-il fixé ? grep -r max_connections \
/etc/postgresql/16/main/)"
  fi
fi

# 5. prévention : garde-fou sur les transactions abandonnées
TO=$(q 'show idle_in_transaction_session_timeout')
case "$TO" in
  0|"") ko "idle_in_transaction_session_timeout = 0 : aucune protection" ;;
  *) ok "idle_in_transaction_session_timeout = $TO" ;;
esac

# 6. discipline : redémarrage de PostgreSQL ?
if [ -r "$SAUV/$ID.debut" ]; then
  START=$(q "select extract(epoch from pg_postmaster_start_time())::bigint")
  if [ "${START:-0}" -gt "$(cat "$SAUV/$ID.debut")" ]; then
    note "PostgreSQL a redémarré après le ticket : justifié uniquement dans \
la fenêtre 12h30-13h00 (à tracer)"
  else
    ok "aucun redémarrage de PostgreSQL hors fenêtre"
  fi
  note "temps écoulé : $(( ($(date +%s) - $(cat "$SAUV/$ID.debut")) / 60 )) min"
fi
if [ -r "$SAUV/$ID.boot_id" ]; then
  [ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$SAUV/$ID.boot_id")" ] \
    && ok "pas de redémarrage de la VM" \
    || ko "MALUS : la VM a redémarré depuis le déclenchement (interdit)"
fi
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
