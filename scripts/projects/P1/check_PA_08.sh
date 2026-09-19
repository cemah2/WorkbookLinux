#!/usr/bin/env bash
# check_PA_08.sh — vérifie le jalon PA.8 (supervision et alerting par timers)
# À lancer sur lab-ops (superviseur) puis sur lab-web et lab-db (exporters).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
HOST="$(hostname -s)"
echo "== Vérification PA.8 sur $HOST =="
S() { sudo -n "$@" 2>/dev/null; }

# --- commun : node_exporter ----------------------------------------------
NE=prometheus-node-exporter.service
[ "$(systemctl is-active $NE)" = active ] && ok "$NE actif" \
  || ko "$NE inactif (apt install prometheus-node-exporter)"
curl -s --max-time 3 http://127.0.0.1:9100/metrics | grep -q '^node_load1' \
  && ok "node_exporter répond sur 9100" || ko "9100 ne répond pas"

case "$HOST" in
lab-web|lab-db)
  U="$(S ufw status || ufw status 2>/dev/null)"
  echo "$U" | grep -E '9100' | grep -q '10.10.10.14' \
    && ok "ufw : 9100 autorisé depuis lab-ops" \
    || ko "ufw : 9100 doit être autorisé depuis 10.10.10.14"
  echo "$U" | grep -E '9100' | grep -q 'Anywhere *$' \
    && ko "ufw : 9100 ouvert à tous" || ok "ufw : 9100 non ouvert à tous"
  ;;
lab-ops)
  # --- webhook local ---------------------------------------------------
  [ "$(systemctl is-active factura-webhook.service)" = active ] \
    && ok "factura-webhook.service actif" \
    || ko "factura-webhook.service inactif"
  ss -Hltn 'sport = :9999' | grep -Eq '(127.0.0.1|0.0.0.0|10.10.10.14):9999' \
    && ok "webhook en écoute sur le port 9999" \
    || ko "rien n'écoute sur 9999 (journalctl -u factura-webhook)"
  curl -s --max-time 3 http://127.0.0.1:9999/ | grep -q 'factura-webhook ok' \
    && ok "webhook répond sur 127.0.0.1:9999" \
    || ko "le webhook ne répond pas sur 127.0.0.1:9999"
  [ "$(systemctl show -p User --value factura-webhook.service)" != root ] \
    && ok "webhook ne tourne pas en root" \
    || ko "factura-webhook.service tourne en root : User= ou DynamicUser="

  # --- healthcheck par timer -------------------------------------------
  T=factura-healthcheck.timer; SV=factura-healthcheck.service
  [ "$(systemctl is-active $T)" = active ] && ok "$T actif" || ko "$T inactif"
  systemctl show -p TimersMonotonic -p TimersCalendar --value "$T" \
    | grep -q . && ok "$T : cadence définie" || ko "$T : ni OnCalendar ni \
OnUnitActiveSec"
  N="$(journalctl -u "$SV" --since '-10min' --no-pager -q 2>/dev/null | wc -l)"
  [ "$N" -gt 0 ] && ok "$SV a tourné dans les 10 dernières minutes" \
    || ko "$SV n'a pas tourné depuis 10 min (cadence <= 5 min attendue)"
  systemctl show -p OnFailure --value "$SV" | grep -q 'factura-alerte' \
    && ok "$SV : OnFailure=factura-alerte@%n.service" \
    || ko "$SV : OnFailure vers factura-alerte@ attendu"
  systemctl cat factura-alerte@.service >/dev/null 2>&1 \
    && ok "unité modèle factura-alerte@.service présente" \
    || ko "factura-alerte@.service absente"

  # --- textfile collector -----------------------------------------------
  TF=/var/lib/prometheus/node-exporter/factura.prom
  if [ -f "$TF" ]; then
    ok "$TF présent"
    [ -n "$(find "$TF" -mmin -10)" ] && ok "$TF rafraîchi depuis < 10 min" \
      || ko "$TF n'a pas été réécrit depuis 10 min"
    curl -s http://127.0.0.1:9100/metrics | grep -q '^factura_' \
      && ok "les métriques factura_* remontent dans node_exporter" \
      || ko "node_exporter n'expose pas factura_* (textfile collector)"
    grep -q '^factura_backup_age_seconds' "$TF" \
      && ok "factura_backup_age_seconds exposée" \
      || ko "factura_backup_age_seconds manquante dans $TF"
    grep -q '^factura_health_up' "$TF" && ok "factura_health_up exposée" \
      || ko "factura_health_up manquante dans $TF"
  else
    ko "$TF absent : le healthcheck doit écrire ses mesures pour node_exporter"
  fi

  # --- une alerte a été prouvée -----------------------------------------
  L=/var/log/factura/alertes.log
  if S test -s "$L"; then
    ok "$L non vide : au moins une alerte a été déclenchée"
  else
    ko "$L vide : provoque un échec (systemctl start d'un service cassé) \
et vérifie la chaîne OnFailure -> alerte -> webhook"
  fi
  W=/var/log/factura/webhook.log
  S test -s "$W" && ok "$W non vide : le webhook a reçu une alerte" \
    || ko "$W vide : l'unité d'alerte doit POSTer sur 127.0.0.1:9999"

  # --- accès aux cibles -------------------------------------------------
  for ip in 10.10.10.11 10.10.10.12; do
    curl -s --max-time 3 "http://$ip:9100/metrics" | grep -q '^node_load1' \
      && ok "node_exporter de $ip joignable depuis lab-ops" \
      || ko "node_exporter de $ip injoignable (ufw sur la cible ?)"
  done
  curl -s --max-time 5 https://factura.lab.local/api/metrics \
    | grep -q '^factura_queue_length' \
    && ok "/api/metrics accessible depuis lab-ops (CA + allow nginx)" \
    || ko "/api/metrics inaccessible depuis lab-ops (CA installée ? \
allow 10.10.10.14 dans nginx ?)"
  ;;
*) note "hostname $HOST hors projet" ;;
esac

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
