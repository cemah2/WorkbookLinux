#!/usr/bin/env bash
# check_PA_03.sh — vérifie le jalon PA.3 (API sous systemd durci) sur lab-web
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
HOST="$(hostname -s)"
echo "== Vérification PA.3 sur $HOST =="
[ "$HOST" = lab-web ] || { note "ce jalon se vérifie sur lab-web"; exit 0; }

UNIT=factura-api.service
val() { systemctl show -p "$1" --value "$UNIT" 2>/dev/null; }

systemctl cat "$UNIT" >/dev/null 2>&1 \
  && ok "$UNIT connue de systemd" \
  || { ko "$UNIT introuvable (/etc/systemd/system + daemon-reload)"; \
       echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

[ "$(systemctl is-active "$UNIT")" = active ] && ok "service actif" \
  || ko "service inactif (journalctl -u $UNIT -n 50)"
[ "$(systemctl is-enabled "$UNIT" 2>/dev/null)" = enabled ] \
  && ok "service activé au boot" || ko "service non enabled"

[ "$(val User)" = factura ] && ok "User=factura" \
  || ko "User= vaut « $(val User) » : le service doit tourner sous factura"
val EnvironmentFiles | grep -q '/etc/factura/api.env' \
  && ok "configuration par EnvironmentFile=/etc/factura/api.env" \
  || ko "pas d'EnvironmentFile=/etc/factura/api.env"

case "$(val Type)" in
  notify|exec) ok "Type=$(val Type)" ;;
  *) ko "Type=$(val Type) : préfère notify (gunicorn sait le faire) ou exec";;
esac
case "$(val Restart)" in
  on-failure|always) ok "Restart=$(val Restart)" ;;
  *) ko "Restart= vaut « $(val Restart) » : le service doit se relancer" ;;
esac

# --- durcissement --------------------------------------------------------
[ "$(val NoNewPrivileges)" = yes ] && ok "NoNewPrivileges=yes" \
  || ko "NoNewPrivileges manquant"
case "$(val ProtectSystem)" in
  strict|full) ok "ProtectSystem=$(val ProtectSystem)" ;;
  *) ko "ProtectSystem= vaut « $(val ProtectSystem) » : strict attendu" ;;
esac
case "$(val ProtectHome)" in
  yes|read-only|tmpfs) ok "ProtectHome=$(val ProtectHome)" ;;
  *) ko "ProtectHome manquant" ;;
esac
[ "$(val PrivateTmp)" = yes ] && ok "PrivateTmp=yes" || ko "PrivateTmp manquant"
[ "$(val PrivateDevices)" = yes ] && ok "PrivateDevices=yes" \
  || ko "PrivateDevices manquant"
[ "$(val ProtectKernelTunables)" = yes ] && ok "ProtectKernelTunables=yes" \
  || ko "ProtectKernelTunables manquant"
M="$(val MemoryMax)"
[ -n "$M" ] && [ "$M" != infinity ] && ok "MemoryMax=$M" \
  || ko "MemoryMax non défini (une limite mémoire chiffrée est demandée)"
val RestrictAddressFamilies | grep -q AF_INET \
  && ok "RestrictAddressFamilies=$(val RestrictAddressFamilies)" \
  || ko "RestrictAddressFamilies manquant (AF_UNIX AF_INET AF_INET6)"

SCORE="$(systemd-analyze security "$UNIT" --no-pager 2>/dev/null \
         | grep -oE 'exposure level for [^:]+: [0-9.]+' | grep -oE '[0-9.]+$')"
if [ -n "$SCORE" ]; then
  awk -v s="$SCORE" 'BEGIN{exit !(s<4.0)}' \
    && ok "systemd-analyze security : $SCORE (< 4.0)" \
    || ko "systemd-analyze security : $SCORE, on attend < 4.0"
else
  note "systemd-analyze security indisponible"
fi

# --- secrets -------------------------------------------------------------
ENVF=/etc/factura/api.env
if sudo -n test -f "$ENVF" 2>/dev/null; then
  P="$(sudo -n stat -c '%U:%G %a' "$ENVF")"
  case "$P" in
    "root:factura 640"|"root:factura 440"|"root:root 600"|"factura:factura 600")
      ok "$ENVF ($P)" ;;
    *) ko "$ENVF a les droits $P : root:factura 0640 attendu" ;;
  esac
  sudo -n grep -q '^FACTURA_DB_URL=postgresql://' "$ENVF" \
    && ok "FACTURA_DB_URL défini" || ko "FACTURA_DB_URL manquant dans $ENVF"
  sudo -n grep -q '^FACTURA_REDIS_URL=redis://' "$ENVF" \
    && ok "FACTURA_REDIS_URL défini" \
    || ko "FACTURA_REDIS_URL manquant dans $ENVF"
else
  ko "$ENVF absent (ou lance ce check avec sudo)"
fi

# --- écoute et santé -----------------------------------------------------
L="$(ss -Hltn 'sport = :8000')"
echo "$L" | grep -q '127.0.0.1:8000' && ok "gunicorn écoute sur 127.0.0.1:8000" \
  || ko "rien n'écoute sur 127.0.0.1:8000 (ss -tlnp, journal du service)"
echo "$L" | grep -Eq '0.0.0.0:8000|\*:8000' \
  && ko "8000 est exposé sur toutes les interfaces : bind 127.0.0.1" \
  || ok "8000 n'est pas exposé hors de la boucle locale"

H="$(curl -s --max-time 5 -w '\n%{http_code}' http://127.0.0.1:8000/health)"
CODE="$(echo "$H" | tail -n1)"; BODY="$(echo "$H" | head -n1)"
[ "$CODE" = 200 ] && ok "/health répond 200" \
  || ko "/health répond « $CODE » : $BODY"
echo "$BODY" | grep -q '"db":"ok"\|"db": "ok"' && ok "/health : db ok" \
  || ko "/health : PostgreSQL injoignable depuis l'API ($BODY)"
echo "$BODY" | grep -q '"redis":"ok"\|"redis": "ok"' && ok "/health : redis ok" \
  || ko "/health : Redis injoignable depuis l'API ($BODY)"

PID="$(val MainPID)"
if [ -n "$PID" ] && [ "$PID" != 0 ]; then
  [ "$(ps -o user= -p "$PID" | tr -d ' ')" = factura ] \
    && ok "le processus principal ($PID) appartient à factura" \
    || ko "le processus principal n'appartient pas à factura"
  N="$(pgrep -c -P "$PID" 2>/dev/null || echo 0)"
  [ "$N" -ge 2 ] && ok "$N workers gunicorn" \
    || ko "moins de 2 workers gunicorn (--workers 2 attendu au minimum)"
fi

{ [ -f /var/log/factura/api-access.log ] || sudo -n test -f \
  /var/log/factura/api-access.log 2>/dev/null; } \
  && ok "journal d'accès /var/log/factura/api-access.log présent" \
  || ko "pas de /var/log/factura/api-access.log (--access-logfile)"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
