#!/usr/bin/env bash
# check_M15_04.sh — vérifie le lab L15.4 (sauvegardes, restauration, PITR) sur lab-db
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L15.4 =="
Q() { sudo -n -u postgres psql -Atqc "$1" 2>/dev/null; }
QD() { sudo -n -u postgres psql -d "$1" -Atqc "$2" 2>/dev/null; }

# --- script et timer ---------------------------------------------------
S=/usr/local/sbin/pg-sauvegarde.sh
[ -x "$S" ] && ok "script $S exécutable" || ko "script $S absent ou non exécutable"
[ -x "$S" ] && head -5 "$S" | grep -q 'set -euo pipefail' && ok "set -euo pipefail" \
  || ko "le script n'a pas set -euo pipefail"
[ "$(systemctl is-enabled pg-sauvegarde.timer 2>/dev/null)" = enabled ] \
  && ok "pg-sauvegarde.timer activé" || ko "pg-sauvegarde.timer non enabled"
[ "$(systemctl is-active pg-sauvegarde.timer 2>/dev/null)" = active ] \
  && ok "pg-sauvegarde.timer actif" || ko "pg-sauvegarde.timer inactif"
systemctl show -p User --value pg-sauvegarde.service 2>/dev/null | grep -q '^postgres$' \
  && ok "service sous User=postgres" || ko "pg-sauvegarde.service ne tourne pas sous postgres"
systemctl show -p Type --value pg-sauvegarde.service 2>/dev/null | grep -q '^oneshot$' \
  && ok "Type=oneshot" || ko "pg-sauvegarde.service n'est pas Type=oneshot"
systemctl cat pg-sauvegarde.timer 2>/dev/null | grep -qi 'Persistent=yes' \
  && ok "Persistent=yes" || ko "Persistent=yes absent du timer"

# --- dernière sauvegarde -----------------------------------------------
LAST="$(sudo -n ls -d /var/backups/postgresql/*/ 2>/dev/null | tail -1)"
if [ -n "$LAST" ]; then
  ok "répertoire de sauvegarde : $LAST"
  sudo -n test -s "$LAST/globals.sql" && ok "globals.sql non vide" || ko "globals.sql absent ou vide"
  sudo -n test -s "$LAST/factura_demo.dump" && ok "factura_demo.dump non vide" \
    || ko "factura_demo.dump absent ou vide"
  if sudo -n test -f "$LAST/SHA256SUMS" || sudo -n ls "$LAST"/*.sha256 >/dev/null 2>&1; then
    if sudo -n bash -c "cd '$LAST' && { [ -f SHA256SUMS ] && sha256sum -c --quiet SHA256SUMS || cat *.sha256 | sha256sum -c --quiet; }" >/dev/null 2>&1
    then ok "sommes SHA256 valides"; else ko "sommes SHA256 invalides ou illisibles"; fi
  else ko "aucun fichier .sha256 / SHA256SUMS"; fi
  AGE=$(( $(date +%s) - $(sudo -n stat -c %Y "$LAST") ))
  [ "$AGE" -lt 93600 ] && ok "sauvegarde de moins de 26 h" || ko "sauvegarde trop ancienne"
else
  ko "aucune sauvegarde dans /var/backups/postgresql (lance le service)"
fi

# --- restauration testée -----------------------------------------------
if [ "$(Q "SELECT 1 FROM pg_database WHERE datname='factura_restore'")" = 1 ]; then
  ok "base factura_restore présente"
  A="$(QD factura_demo 'SELECT count(*) FROM invoices')"; B="$(QD factura_restore 'SELECT count(*) FROM invoices')"
  [ -n "$B" ] && [ "$A" = "$B" ] && ok "invoices : $A lignes des deux côtés" \
    || ko "invoices : $A (source) vs ${B:-absent} (restaurée)"
else
  ko "base factura_restore absente (pg_restore dans une base neuve)"
fi

# --- archivage et base physique -----------------------------------------
[ "$(Q 'SHOW archive_mode')" = on ] && ok "archive_mode = on" || ko "archive_mode n'est pas on (restart)"
AC="$(Q 'SELECT archived_count FROM pg_stat_archiver')"; FC="$(Q 'SELECT failed_count FROM pg_stat_archiver')"
[ "${AC:-0}" -gt 0 ] && ok "$AC segment(s) archivé(s)" || ko "aucun segment archivé (pg_switch_wal ?)"
[ "${FC:-1}" = 0 ] && ok "aucun échec d'archivage" || ko "failed_count = $FC (archive_command)"
[ "$(sudo -n ls /srv/pg-archive/wal 2>/dev/null | wc -l)" -gt 0 ] \
  && ok "segments présents dans /srv/pg-archive/wal" || ko "/srv/pg-archive/wal vide"
sudo -n ls /srv/pg-archive/base/base.tar.gz >/dev/null 2>&1 \
  && ok "pg_basebackup présent (base.tar.gz)" || ko "pas de base.tar.gz dans /srv/pg-archive/base"

# --- rapport -----------------------------------------------------------
RAP="$HOME/lab15/rapports/restauration.md"
if [ -f "$RAP" ]; then
  grep -qi 'pg_restore' "$RAP" && grep -qE '[0-9]+ ?(s|sec|min|m)\b' "$RAP" \
    && ok "restauration.md avec procédure et temps mesuré" \
    || ko "restauration.md sans pg_restore ou sans temps mesuré"
  grep -qiE 'recovery_target_time|PITR' "$RAP" && ok "PITR documenté" \
    || ko "PITR absent de restauration.md"
else ko "rapport $RAP absent"; fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
