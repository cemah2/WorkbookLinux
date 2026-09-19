#!/usr/bin/env bash
# check_PC_2_1.sh — vérifie le ticket PC.2.1 (lab-db à 95 %)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.2.1 =="
SAUV=/root/.breakfix-backup; ID=PC_2_1
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
q() { sudo -u postgres psql -tAqc "$1" 2>/dev/null; }
LOGD=/var/log/postgresql

USE=$(df -P "$LOGD" | awk 'NR==2 {print $5}' | tr -dc 0-9)
[ "${USE:-100}" -lt 85 ] && ok "occupation du disque : $USE %" \
  || ko "disque encore à $USE % (du -xh --max-depth=1 /var | sort -h)"

q 'select 1' | grep -q 1 && ok "PostgreSQL répond" || ko "PostgreSQL ne répond pas"

LS=$(q 'show log_statement')
[ "$LS" = "none" ] || [ "$LS" = "ddl" ] \
  && ok "log_statement = $LS" \
  || ko "log_statement = $LS : la journalisation exhaustive continue à remplir le disque"
LMD=$(q 'show log_min_duration_statement')
[ "$LMD" != "0" ] && ok "log_min_duration_statement = $LMD" \
  || ko "log_min_duration_statement = 0 : chaque requête est journalisée"

SLOT=$(q "select count(*) from pg_replication_slots where active = false")
[ "${SLOT:-1}" -eq 0 ] && ok "aucun slot de réplication inactif" \
  || ko "$SLOT slot(s) inactif(s) retiennent du WAL (select * from pg_replication_slots)"

# les faux journaux tournés ont-ils été purgés ?
RESTE=$(find "$LOGD" -name 'postgresql-16-main.log.*' -size +100M 2>/dev/null | wc -l)
[ "$RESTE" -eq 0 ] && ok "journaux tournés volumineux purgés" \
  || ko "$RESTE journal(aux) tourné(s) de plus de 100 Mo restent dans $LOGD"

# interdictions : pas de rm dans pg_wal, pas de restart
if [ -r "$SAUV/$ID.pgstart" ] && [ -s "$SAUV/$ID.pgstart" ]; then
  NOW=$(q "select extract(epoch from pg_postmaster_start_time())::bigint")
  [ "$NOW" = "$(cat "$SAUV/$ID.pgstart")" ] \
    && ok "PostgreSQL n'a pas été redémarré" \
    || ko "MALUS : PostgreSQL a redémarré (interdit sur ce ticket)"
fi
q "select count(*) from pg_ls_waldir()" | grep -qE '^[1-9]' \
  && ok "pg_wal cohérent (pg_ls_waldir)" \
  || ko "pg_wal illisible ou vide : des fichiers WAL ont-ils été supprimés à la main ?"

# prévention : rotation des journaux en place
if grep -rqs 'postgresql' /etc/logrotate.d/ 2>/dev/null; then
  ok "une rotation logrotate couvre les journaux PostgreSQL"
else
  ko "aucune règle logrotate pour /var/log/postgresql"
fi

if [ -r "$SAUV/$ID.boot_id" ]; then
  [ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$SAUV/$ID.boot_id")" ] \
    && ok "pas de redémarrage de la VM" \
    || ko "MALUS : la VM a redémarré depuis le déclenchement"
fi
[ -r "$SAUV/$ID.debut" ] && note "temps écoulé : \
$(( ($(date +%s) - $(cat "$SAUV/$ID.debut")) / 60 )) min"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
