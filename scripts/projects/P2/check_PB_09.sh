#!/usr/bin/env bash
# check_PB_09.sh — vérifie le jalon PB.9 (sauvegardes, restauration CI,
# reconstruction chronométrée)
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification PB.9 =="
REPO="${REPO:-$HOME/factura-v2}"
OPS="${OPS:-10.10.10.14}"
PROM="http://$OPS:9090"
r() { ssh -o BatchMode=yes -o ConnectTimeout=4 "mathieu@$1" "$2" 2>/dev/null; }

# --- dépôt ---------------------------------------------------------------
[ -d "$REPO/ansible/roles/pg_backup" ] && ok "rôle pg_backup" \
  || ko "ansible/roles/pg_backup manquant"
for p in backup.yml restore.yml; do
  [ -f "$REPO/ansible/playbooks/$p" ] && ok "playbook $p" \
    || ko "ansible/playbooks/$p absent"
done
W="$REPO/.gitea/workflows/restore-test.yaml"
[ -f "$W" ] || W="$REPO/.gitea/workflows/restore-test.yml"
if [ -f "$W" ]; then
  ok "workflow restore-test présent"
  grep -q 'schedule' "$W" && grep -qE "cron:.*4 \* \* 1" "$W" \
    && ok "restore-test : planifié le lundi à 04:00" \
    || ko "restore-test : pas de schedule '0 4 * * 1'"
  grep -q 'pg_restore' "$W" && ok "restore-test : pg_restore" \
    || ko "restore-test : pas de pg_restore"
  grep -q 'always()' "$W" && ok "restore-test : nettoyage en always()" \
    || ko "restore-test : le conteneur jetable n'est pas supprimé en always()"
else
  ko ".gitea/workflows/restore-test.yaml absent"
fi
grep -qiE 'RPO|RTO' "$REPO/docs/runbook-deploy.md" 2>/dev/null \
  && ok "runbook : RPO/RTO documentés" \
  || ko "docs/runbook-deploy.md : section sinistre avec RPO/RTO attendue"
LOG=$(ls -t "$REPO"/docs/rebuild-*.log 2>/dev/null | head -1)
if [ -n "$LOG" ]; then
  ok "journal de reconstruction $(basename "$LOG")"
  TOT=$(grep -oE 'TOTAL: *[0-9]+' "$LOG" | tail -1 | grep -oE '[0-9]+')
  if [ -n "$TOT" ]; then
    [ "$TOT" -lt 3600 ] && ok "reconstruction en $TOT s (< 3600)" \
      || ko "reconstruction en $TOT s (objectif < 3600 s)"
  else
    ko "pas de ligne 'TOTAL: n s' dans $LOG (rebuild.sh interrompu ?)"
  fi
  grep -q '5/5' "$LOG" && ok "les 5 étapes apparaissent dans le journal" \
    || ko "étape 5/5 absente du journal de reconstruction"
else
  ko "aucun docs/rebuild-<date>.log (tools/rebuild.sh prod <tag>)"
fi

# --- VM db ---------------------------------------------------------------
for e in staging prod; do
  case $e in staging) D=10.10.10.22;; *) D=10.10.10.32;; esac
  echo "-- $e db ($D)"
  r "$D" 'systemctl is-active factura-backup.timer' | grep -q '^active' \
    && ok "$e : factura-backup.timer actif" \
    || ko "$e : factura-backup.timer inactif"
  r "$D" 'systemctl show -p User factura-backup.service' | grep -q 'User=deploy' \
    && ok "$e : factura-backup.service tourne en deploy" \
    || ko "$e : le service de sauvegarde ne tourne pas sous User=deploy"
  r "$D" 'test -x /usr/local/sbin/factura-backup.sh' \
    && ok "$e : /usr/local/sbin/factura-backup.sh" \
    || ko "$e : script /usr/local/sbin/factura-backup.sh absent"
  P=$(r "$D" 'cat /var/lib/prometheus/node-exporter/factura.prom')
  TS=$(echo "$P" | awk '/^factura_backup_last_success_timestamp/{print $2}' \
       | tail -1 | cut -d. -f1)
  if [ -n "$TS" ]; then
    AGE=$(( $(date +%s) - TS ))
    [ "$AGE" -lt $((26*3600)) ] \
      && ok "$e : dernière sauvegarde réussie il y a $((AGE/60)) min" \
      || ko "$e : dernière sauvegarde trop vieille ($((AGE/3600)) h)"
  else
    ko "$e : factura_backup_last_success_timestamp absent du textfile collector"
  fi
  echo "$P" | grep -q '^factura_backup_size_bytes' \
    && ok "$e : factura_backup_size_bytes exposé" \
    || ko "$e : factura_backup_size_bytes absent"
  r "$D" 'sudo test -f /home/deploy/.ssh/id_ed25519' \
    && ok "$e : clé SSH de deploy présente" \
    || ko "$e : /home/deploy/.ssh/id_ed25519 absente (générée par le rôle ?)"
done

# --- lab-ops -------------------------------------------------------------
echo "-- lab-ops"
r "$OPS" 'getent passwd backup' | grep -q backup \
  && ok "compte backup sur lab-ops" || ko "compte backup absent sur lab-ops"
r "$OPS" 'sudo grep -q rrsync /srv/backups/.ssh/authorized_keys || \
          sudo grep -q rrsync /home/backup/.ssh/authorized_keys' \
  && ok "authorized_keys de backup restreint à rrsync" \
  || ko "authorized_keys de backup sans command=\"rrsync ...\""
for e in staging prod; do
  N=$(r "$OPS" "ls /srv/backups/factura/$e/*.dump 2>/dev/null | wc -l")
  [ "${N:-0}" -ge 1 ] && ok "$e : $N dump(s) sur lab-ops" \
    || ko "$e : aucun dump dans /srv/backups/factura/$e/ (rsync ? droits ?)"
  r "$OPS" "ls /srv/backups/factura/$e/*.sha256 /srv/backups/factura/$e/*.meta" \
    >/dev/null && ok "$e : .sha256 et .meta présents" \
    || ko "$e : fichiers .sha256/.meta manquants à côté du dump"
done
RT=$(r "$OPS" 'ls /srv/backups/factura/restore-tests/ 2>/dev/null')
echo "$RT" | grep -qE -- '-ok\.txt$' \
  && ok "restore-tests : au moins un rapport -ok.txt (job CI hebdo)" \
  || ko "restore-tests : aucun rapport -ok.txt (lance restore-test à la main)"
r "$OPS" 'id runner' | grep -q backup \
  && ok "runner membre du groupe backup (lecture des dumps)" \
  || ko "le compte runner n'est pas dans le groupe backup"

# --- Prometheus ----------------------------------------------------------
A=$(curl -fsS -m 6 "$PROM/api/v1/alerts" 2>/dev/null \
    | jq -r '.data.alerts[] | select(.labels.alertname=="FacturaBackupTooOld") | .state')
[ -z "$A" ] && ok "FacturaBackupTooOld inactive" \
  || ko "FacturaBackupTooOld est $A (métrique absente ou trop vieille)"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
