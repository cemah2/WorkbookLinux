#!/usr/bin/env bash
# check_PA_10.sh — vérifie le jalon PA.10 (runbook, incidents, bout en bout)
# À lancer sur lab-adm (documents) ; sur lab-web/lab-db : état de la plateforme.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
HOST="$(hostname -s)"
echo "== Vérification PA.10 sur $HOST =="

case "$HOST" in
lab-adm)
  H="$(getent passwd "${SUDO_USER:-mathieu}" | cut -d: -f6)"
  RB="$H/P1/runbook.md"
  if [ -f "$RB" ]; then
    ok "runbook présent : $RB"
    N="$(wc -l < "$RB")"
    [ "$N" -ge 120 ] && ok "runbook : $N lignes" \
      || ko "runbook : $N lignes, on attend au moins 120"
    for sec in 'Architecture' 'Démarrage' 'Arrêt' 'Sauvegarde' \
               'Restauration' 'Supervision' 'Incidents' 'Contacts' \
               'Secrets'; do
      grep -qi "^#.*$sec" "$RB" && ok "runbook : section « $sec »" \
        || ko "runbook : section « $sec » manquante"
    done
    grep -q 'systemctl' "$RB" && ok "runbook : commandes concrètes" \
      || ko "runbook : aucune commande systemctl ? il doit être exécutable"
    grep -Eq '10\.10\.10\.1[124]' "$RB" && ok "runbook : IP du lab" \
      || ko "runbook : cite les hôtes et IP réels"
  else
    ko "$RB absent"
  fi
  for i in 1 2 3; do
    F="$(ls "$H"/P1/incidents/INC-A$i*.md 2>/dev/null | head -n1)"
    if [ -n "$F" ]; then
      ok "post-mortem INC-A$i : $F"
      for sec in 'Chronologie' 'Cause racine' 'Correctif' 'Prévention'; do
        grep -qi "$sec" "$F" && ok "INC-A$i : $sec" \
          || ko "INC-A$i : section « $sec » manquante"
      done
    else
      ko "$H/P1/incidents/INC-A$i-*.md absent"
    fi
  done
  C="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
       https://factura.lab.local/api/health)"
  [ "$C" = 200 ] && ok "plateforme opérationnelle depuis lab-adm (health 200)" \
    || ko "https://factura.lab.local/api/health répond « $C »"
  ;;
lab-web)
  for u in factura-api factura-worker nginx factura-backup.timer \
           prometheus-node-exporter fail2ban rsyslog; do
    [ "$(systemctl is-active "$u")" = active ] && ok "$u actif" \
      || ko "$u inactif"
  done
  [ "$(systemctl --failed --no-legend | wc -l)" -eq 0 ] \
    && ok "aucune unité en échec" \
    || ko "unités en échec : $(systemctl --failed --no-legend \
         | awk '{print $1}' | tr '\n' ' ')"
  command -v jq >/dev/null && {
    B="$(curl -s --max-time 5 http://127.0.0.1:8000/health)"
    echo "$B" | jq -e '.status == "ok"' >/dev/null 2>&1 \
      && ok "API : status ok (db et redis joignables)" \
      || ko "API dégradée : $B"
    E="$(curl -s "http://127.0.0.1:8000/invoices?limit=500" \
         | jq '[.[] | select(.status == "error")] | length')"
    [ "${E:-1}" -eq 0 ] && ok "aucune facture en erreur" \
      || ko "$E facture(s) en « error » : remets-les en file après l'incident"
  }
  [ -d /root/.breakfix-backup ] || sudo -n test -d /root/.breakfix-backup \
    2>/dev/null && note "des break_PA_* ont été joués sur cette VM"
  ;;
lab-db)
  for u in postgresql@16-main redis-server factura-backup.timer \
           prometheus-node-exporter fail2ban rsyslog; do
    [ "$(systemctl is-active "$u")" = active ] && ok "$u actif" \
      || ko "$u inactif"
  done
  [ "$(systemctl --failed --no-legend | wc -l)" -eq 0 ] \
    && ok "aucune unité en échec" || ko "des unités sont en échec"
  ;;
lab-ops)
  for u in rsyslog factura-webhook factura-healthcheck.timer \
           prometheus-node-exporter; do
    [ "$(systemctl is-active "$u")" = active ] && ok "$u actif" \
      || ko "$u inactif"
  done
  ;;
*) note "hostname $HOST hors projet" ;;
esac

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
