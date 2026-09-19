#!/usr/bin/env bash
# check_PA_04.sh — vérifie le jalon PA.4 (worker et file Redis) sur lab-web
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
HOST="$(hostname -s)"
echo "== Vérification PA.4 sur $HOST =="
[ "$HOST" = lab-web ] || { note "ce jalon se vérifie sur lab-web"; exit 0; }

UNIT=factura-worker.service
val() { systemctl show -p "$1" --value "$UNIT" 2>/dev/null; }
API=http://127.0.0.1:8000
command -v jq >/dev/null || { ko "jq requis (apt install jq)"; exit 1; }

systemctl cat "$UNIT" >/dev/null 2>&1 && ok "$UNIT connue" \
  || { ko "$UNIT introuvable"; echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
[ "$(systemctl is-active "$UNIT")" = active ] && ok "worker actif" \
  || ko "worker inactif (journalctl -u $UNIT -n 50)"
[ "$(systemctl is-enabled "$UNIT" 2>/dev/null)" = enabled ] \
  && ok "worker activé au boot" || ko "worker non enabled"
[ "$(val User)" = factura ] && ok "User=factura" || ko "User= doit être factura"
[ "$(val Restart)" = always ] && ok "Restart=always" \
  || ko "Restart= vaut « $(val Restart) » : always attendu pour un consommateur"
val EnvironmentFiles | grep -q '/etc/factura/worker.env' \
  && ok "EnvironmentFile=/etc/factura/worker.env" \
  || ko "pas d'EnvironmentFile=/etc/factura/worker.env"
val After | grep -q 'factura-api' \
  && note "After=factura-api.service : inutile, le worker n'en dépend pas" \
  || ok "pas de dépendance artificielle sur factura-api"
[ "$(val NoNewPrivileges)" = yes ] && ok "NoNewPrivileges=yes" \
  || ko "NoNewPrivileges manquant"
case "$(val ProtectSystem)" in strict|full) ok "ProtectSystem=$(val ProtectSystem)";;
  *) ko "ProtectSystem strict attendu";; esac
val ReadWritePaths | grep -q '/srv/factura/exports' \
  && ok "ReadWritePaths contient /srv/factura/exports" \
  || ko "avec ProtectSystem=strict, /srv/factura/exports doit être dans \
ReadWritePaths="
case "$(val KillSignal)" in SIGTERM|"") ok "arrêt par SIGTERM";;
  *) ko "KillSignal=$(val KillSignal) : le worker gère SIGTERM";; esac

# --- bout en bout : création, export, statut -----------------------------
R="$(curl -s --max-time 5 -X POST -H 'Content-Type: application/json' \
     -d '{"customer":"check PA.4","amount":42.5}' "$API/invoices")"
ID="$(echo "$R" | jq -r '.id // empty' 2>/dev/null)"
if [ -z "$ID" ]; then
  ko "POST /invoices a échoué : $R"
else
  ok "facture créée (id=$ID)"
  ST=pending
  for _ in $(seq 1 15); do
    sleep 1
    ST="$(curl -s --max-time 3 "$API/invoices/$ID" | jq -r .status)"
    [ "$ST" = exported ] && break
  done
  if [ "$ST" = exported ]; then
    ok "facture exportée par le worker en moins de 15 s"
    P="$(curl -s "$API/invoices/$ID" | jq -r .pdf_path)"
    if sudo -n test -s "$P" 2>/dev/null || [ -s "$P" ]; then
      ok "fichier $P présent"
      HEAD="$(sudo -n head -c 5 "$P" 2>/dev/null || head -c 5 "$P")"
      [ "$HEAD" = '%PDF-' ] && ok "le fichier est un PDF" \
        || ko "$P ne commence pas par %PDF-"
      OWN="$(sudo -n stat -c '%U %a' "$P" 2>/dev/null || stat -c '%U %a' "$P")"
      [ "$OWN" = "factura 640" ] && ok "PDF factura 0640" \
        || ko "PDF : $OWN (attendu factura 640 : umask ou droits du dossier)"
    else
      ko "pdf_path=$P introuvable ou vide (lance avec sudo si besoin)"
    fi
  else
    ko "facture toujours en « $ST » après 15 s : le worker consomme-t-il la \
file ? (journalctl -u $UNIT, redis-cli LLEN factura:jobs)"
  fi
fi

M="$(curl -s --max-time 5 "$API/metrics")"
echo "$M" | grep -q '^factura_worker_alive 1' \
  && ok "/metrics : factura_worker_alive 1 (battement de cœur Redis)" \
  || ko "/metrics : factura_worker_alive vaut 0 (heartbeat absent)"
Q="$(echo "$M" | awk '/^factura_queue_length/{print $2}')"
[ "${Q:-1}" -eq 0 ] && ok "file vide (factura_queue_length 0)" \
  || ko "file non vide (factura_queue_length ${Q:-?})"

# --- reprise après coupure Redis : le worker doit rester actif -----------
FAILS="$(systemctl show -p NRestarts --value "$UNIT")"
[ "${FAILS:-0}" -le 3 ] && ok "NRestarts=$FAILS (pas de crash-loop)" \
  || ko "NRestarts=$FAILS : le worker redémarre en boucle"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
