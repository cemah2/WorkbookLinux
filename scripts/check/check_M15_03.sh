#!/usr/bin/env bash
# check_M15_03.sh — vérifie le lab L15.3 (PostgreSQL ouvert à lab-web)
# À lancer sur lab-db (contrôles principaux) puis sur lab-web (connexion).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
HOST="$(hostname -s)"
echo "== Vérification L15.3 sur $HOST =="

case "$HOST" in
lab-db)
  Q() { sudo -n -u postgres psql -Atqc "$1" 2>/dev/null; }
  U=postgresql@16-main.service
  [ "$(systemctl is-active $U 2>/dev/null)" = active ] && ok "$U actif" \
    || ko "$U inactif (systemctl status $U ; journal postgresql-16-main.log)"
  ss -Hltn 'sport = :5432' | grep -q '10.10.10.12:5432' \
    && ok "écoute sur 10.10.10.12:5432" \
    || ko "pas d'écoute sur 10.10.10.12 (listen_addresses, puis RESTART)"
  ss -Hltn 'sport = :5432' | grep -q '0.0.0.0:5432' \
    && ko "écoute sur 0.0.0.0 : restreins listen_addresses" || ok "pas d'écoute sur 0.0.0.0"
  [ -f /etc/postgresql/16/main/conf.d/10-factura.conf ] \
    && ok "conf.d/10-factura.conf présent" || ko "conf.d/10-factura.conf absent"
  # paramètres effectifs
  chk() { local v; v="$(Q "SHOW $1")"; [ "$v" = "$2" ] && ok "$1 = $v" \
          || ko "$1 vaut « $v », attendu $2 (reload ou restart ?)"; }
  chk log_min_duration_statement 500ms
  chk log_lock_waits on
  chk timezone Europe/Paris
  chk password_encryption scram-sha-256
  SB="$(Q "SELECT setting::bigint*8/1024 FROM pg_settings WHERE name='shared_buffers'")"
  [ "${SB:-0}" -ge 256 ] && ok "shared_buffers = ${SB} MB" \
    || ko "shared_buffers = ${SB:-?} MB : trop bas pour 2 Go (et restart nécessaire)"
  Q "SHOW shared_preload_libraries" | grep -q pg_stat_statements \
    && ok "pg_stat_statements préchargé" \
    || ko "shared_preload_libraries sans pg_stat_statements (restart nécessaire)"
  [ "$(sudo -n -u postgres psql -d factura_demo -Atqc \
      "SELECT 1 FROM pg_extension WHERE extname='pg_stat_statements'" 2>/dev/null)" = 1 ] \
    && ok "extension pg_stat_statements créée dans factura_demo" \
    || ko "CREATE EXTENSION pg_stat_statements manquant dans factura_demo"
  PR="$(Q "SELECT count(*) FROM pg_settings WHERE pending_restart")"
  [ "$PR" = 0 ] && ok "aucun paramètre en attente de restart" \
    || ko "$PR paramètre(s) en attente de restart (pg_settings.pending_restart)"
  # pg_hba
  HBA="$(sudo -n cat /etc/postgresql/16/main/pg_hba.conf 2>/dev/null | grep -Ev '^\s*#|^\s*$')"
  grep -qE '\strust\s*$' <<<"$HBA" && ko "pg_hba contient trust" || ok "aucune ligne trust"
  grep -qE '\smd5\s*$' <<<"$HBA" && ko "pg_hba contient md5" || ok "aucune ligne md5"
  grep -E '^host' <<<"$HBA" | grep -E 'factura_demo\s+factura_app\s+10\.10\.10\.11/32\s+scram-sha-256' -q \
    && ok "ligne host factura_demo factura_app 10.10.10.11/32 scram-sha-256" \
    || ko "pas de ligne host factura_demo factura_app 10.10.10.11/32 scram-sha-256"
  grep -E '^host' <<<"$HBA" | grep -qE '0\.0\.0\.0/0|10\.10\.10\.0/24|/0\s' \
    && ko "une ligne host couvre tout un réseau" || ok "aucune ligne host large"
  ERR="$(Q "SELECT count(*) FROM pg_hba_file_rules WHERE error IS NOT NULL")"
  [ "$ERR" = 0 ] && ok "pg_hba_file_rules sans erreur" \
    || ko "pg_hba_file_rules signale $ERR erreur(s)"
  [ -f "$HOME/lab15/rapports/pg-ouverture.md" ] && ok "rapport pg-ouverture.md présent" \
    || ko "rapport ~/lab15/rapports/pg-ouverture.md absent"
  ;;
lab-web)
  command -v psql >/dev/null || ko "psql absent (postgresql-client)"
  if psql -w -h 10.10.10.12 -U factura_app -d factura_demo -Atc 'SELECT 1' 2>/dev/null | grep -q '^1$'
  then ok "connexion factura_app sans mot de passe interactif (.pgpass)"
  else ko "connexion factura_app impossible sans prompt (pg_hba ? .pgpass 0600 ?)"; fi
  psql -w -h 10.10.10.12 -U factura_ro -d factura_demo -Atc 'SELECT 1' 2>/dev/null | grep -q '^1$' \
    && ok "connexion factura_ro" || ko "connexion factura_ro impossible"
  psql -w -h 10.10.10.12 -U factura_ro -d factura_demo \
    -c "UPDATE customers SET city=city WHERE id=1" 2>&1 | grep -q 'permission denied' \
    && ok "factura_ro ne peut pas écrire" || ko "factura_ro peut écrire (ou erreur autre)"
  ;;
*) note "ce check se lance sur lab-db puis lab-web" ;;
esac
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
