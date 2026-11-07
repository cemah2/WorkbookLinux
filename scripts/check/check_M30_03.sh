#!/usr/bin/env bash
# check_M30_03.sh — vérifie le lab L30.3 (archivage WAL et PITR)
# À lancer avec sudo sur lab-db, puis sur lab-ops.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

case "$(hostname -s)" in
lab-db)
  echo "== Vérification L30.3 — lab-db =="
  q() { sudo -u postgres psql -qAt -c "$1" 2>/dev/null; }
  [ "$(q 'SHOW archive_mode')" = on ] && ok "archive_mode = on" || ko "archive_mode n'est pas à on"
  q 'SHOW archive_command' | grep -q archive-wal && ok "archive_command : archive-wal" \
                                                 || ko "archive_command n'utilise pas archive-wal"
  [ "$(q 'SHOW archive_timeout')" = 5min ] && ok "archive_timeout = 5 min" \
                                           || ko "archive_timeout = $(q 'SHOW archive_timeout') (5min attendu)"
  IFS='|' read -r ok_t fail_t nfail <<<"$(q "SELECT coalesce(extract(epoch FROM now()-last_archived_time)::int,-1),
    coalesce(extract(epoch FROM now()-last_failed_time)::int,-1), failed_count FROM pg_stat_archiver")"
  if [ "$ok_t" -ge 0 ] && [ "$ok_t" -le 900 ]; then ok "dernier segment archivé il y a ${ok_t} s"
  else ko "aucun archivage depuis plus de 15 min (pg_stat_archiver)"; fi
  if [ "$fail_t" -ge 0 ] && { [ "$ok_t" -lt 0 ] || [ "$fail_t" -lt "$ok_t" ]; }; then
    ko "le dernier événement d'archivage est un ÉCHEC ($nfail échecs au total)"
  else
    ok "pas d'échec d'archivage en cours ($nfail échecs historiques)"
  fi
  grep -Eqs '^\s*host\s+replication\s+sauvegarde_pg\s+10\.10\.10\.14/32' /etc/postgresql/16/main/pg_hba.conf \
    && ok "réplication autorisée pour sauvegarde_pg depuis lab-ops seulement" \
    || ko "pas de ligne pg_hba « host replication sauvegarde_pg 10.10.10.14/32 »"
  n=$(sudo -u postgres psql -d lab30 -qAt -c 'SELECT count(*) FROM factures' 2>/dev/null)
  [ "${n:-0}" -ge 1000 ] && ok "factures de retour en production ($n lignes)" \
                         || ko "factures absente ou incomplète en production (étape 8)"
  ;;
lab-ops)
  echo "== Vérification L30.3 — lab-ops =="
  ls /srv/pgwal/*.zst >/dev/null 2>&1 && ok "$(ls /srv/pgwal/*.zst | wc -l) segments archivés dans /srv/pgwal" \
                                      || ko "aucun segment dans /srv/pgwal"
  grep -qs 'rrsync -wo /srv/pgwal' /home/pgwal/.ssh/authorized_keys \
    && ok "clé de postgres@lab-db en écriture seule (rrsync -wo)" \
    || ko "authorized_keys de pgwal sans rrsync -wo /srv/pgwal"
  B=$(ls -1d /srv/pgbase/*/ 2>/dev/null | tail -1)
  if [ -n "$B" ] && [ -s "$B/base.tar.gz" ] && [ -s "$B/pg_wal.tar.gz" ]; then
    ok "sauvegarde de base : $(basename "$B") (base.tar.gz + pg_wal.tar.gz)"
  else
    ko "pas de sauvegarde de base complète dans /srv/pgbase"
  fi
  if pg_lsclusters 2>/dev/null | grep -Eq '^16\s+restau\s+5439\s+online'; then
    ok "instance 16/restau en ligne sur le port 5439"
    r() { sudo -u postgres psql -p 5439 -qAt -c "$1" "${@:2}" 2>/dev/null; }
    [ "$(r 'SELECT pg_is_in_recovery()')" = f ] && ok "instance promue (hors restauration)" \
                                                || ko "l'instance est toujours en restauration"
    [ "$(r 'SHOW archive_mode')" = off ] && ok "l'instance restaurée n'archive pas" \
                                         || ko "l'instance restaurée archive : risque de polluer /srv/pgwal"
    n=$(r 'SELECT count(*) FROM factures' -d lab30)
    [ "${n:-0}" -eq 1000 ] && ok "factures restaurée : 1000 lignes" \
                           || ko "factures dans restau : ${n:-absente}"
  else
    ko "instance 16/restau absente ou arrêtée (pg_lsclusters)"
  fi
  ;;
*) echo "== Vérification L30.3 =="; ko "à lancer sur lab-db puis sur lab-ops" ;;
esac
fin
