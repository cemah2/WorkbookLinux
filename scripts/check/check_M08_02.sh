#!/usr/bin/env bash
# check_M08_02.sh — vérifie le lab L8.2 (servicifier factura-api)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L8.2 =="

UNIT=factura-api.service
val() { systemctl show -p "$1" --value "$UNIT" 2>/dev/null; }

[ -d /run/systemd/system ] || { \
  ko "systemd ne pilote pas cette machine : ce lab est inapplicable ici"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. l'unité est connue, active et activée au boot -------------------
if systemctl cat "$UNIT" >/dev/null 2>&1; then
  ok "l'unité $UNIT est chargée par systemd"
else
  ko "unité introuvable : crée /etc/systemd/system/$UNIT puis \
systemctl daemon-reload"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi

[ "$(systemctl is-active  "$UNIT" 2>/dev/null)" = active ] \
  && ok "le service est active" \
  || ko "le service n'est pas actif (systemctl status $UNIT)"

[ "$(systemctl is-enabled "$UNIT" 2>/dev/null)" = enabled ] \
  && ok "le service est activé au démarrage" \
  || ko "le service n'est pas enabled (il manque [Install] WantedBy= ou \
systemctl enable)"

# --- 2. les directives demandées ---------------------------------------
T=$(val Type)
case "$T" in
  exec|notify) ok "Type=$T : une erreur sur le binaire est détectée" ;;
  simple) ko "Type=simple ne détecte pas un binaire absent : relis le \
point 4 de l'énoncé" ;;
  *) ko "Type=$T inattendu pour un serveur au premier plan" ;;
esac

[ "$(val User)" = factura ] \
  && ok "le service tourne sous l'utilisateur factura" \
  || ko "User= vaut « $(val User) » au lieu de factura"

[ "$(val WorkingDirectory)" = /srv/factura ] \
  && ok "WorkingDirectory=/srv/factura" \
  || ko "WorkingDirectory attendu : /srv/factura"

val EnvironmentFiles | grep -q '/etc/factura/api.env' \
  && ok "la configuration vient de /etc/factura/api.env" \
  || ko "aucun EnvironmentFile=/etc/factura/api.env (pas de valeur en dur \
dans l'unité)"

[ "$(val Restart)" = on-failure ] \
  && ok "Restart=on-failure (pas de relance après un stop volontaire)" \
  || ko "Restart= vaut « $(val Restart) », on attend on-failure"

# systemd rend ces durées en microsecondes ou en forme lisible selon la
# version : on accepte les deux écritures.
case "$(val RestartUSec)" in
  5s|5000000) ok "RestartSec=5s" ;;
  *) ko "RestartSec attendu à 5s (valeur lue : $(val RestartUSec))" ;;
esac

case "$(val TimeoutStopUSec)" in
  20s|20000000) ok "TimeoutStopSec=20s" ;;
  *) ko "TimeoutStopSec attendu à 20s (lu : $(val TimeoutStopUSec))" ;;
esac

[ -n "$(val ExecReload)" ] \
  && ok "ExecReload est défini (systemctl reload possible)" \
  || ko "ExecReload manquant : systemctl reload refusera de recharger"

val After | grep -q 'network-online.target' \
  && ok "ordonnancement After=network-online.target" \
  || ko "le service doit démarrer après network-online.target (et le \
Wants= qui va avec)"

# --- 3. comportement réel -----------------------------------------------
PID=$(val MainPID)
if [ -n "$PID" ] && [ "$PID" != 0 ]; then
  OWNER=$(ps -o user= -p "$PID" 2>/dev/null | tr -d ' ')
  [ "$OWNER" = factura ] \
    && ok "le processus principal ($PID) appartient à factura" \
    || ko "le processus principal appartient à « $OWNER »"
else
  ko "pas de processus principal : le service ne tourne pas"
fi

PORT=$(grep -E '^FACTURA_PORT=' /etc/factura/api.env 2>/dev/null \
       | cut -d= -f2)
PORT="${PORT:-8080}"
if curl -fsS --max-time 4 "http://127.0.0.1:$PORT/sante" >/dev/null 2>&1; then
  ok "l'API répond sur http://127.0.0.1:$PORT/sante"
else
  ko "aucune réponse sur le port $PORT (vérifie ss -tulpn et le journal)"
fi

# --- 4. reload sans changement de PID ------------------------------------
if [ -n "${PID:-}" ] && [ "${PID:-0}" != 0 ]; then
  if systemctl reload "$UNIT" >/dev/null 2>&1; then
    sleep 1
    [ "$(val MainPID)" = "$PID" ] \
      && ok "systemctl reload n'a pas changé le PID principal" \
      || ko "le reload a redémarré le service : ExecReload doit envoyer un \
signal, pas relancer le processus"
  else
    ko "systemctl reload a échoué (ExecReload absent ou invalide)"
  fi
fi

note "copie de travail attendue dans ~/lab08/units/ (non bloquant)"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
