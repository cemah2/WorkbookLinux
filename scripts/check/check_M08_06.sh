#!/usr/bin/env bash
# check_M08_06.sh — vérifie le défi D8 (factura-api en production)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D8 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
UNIT=factura-api.service
DROPIN=/etc/systemd/system/factura-api.service.d/10-preprod.conf
RUNBOOK="$HOMEDIR/lab08/rapports/runbook-factura-api.md"
VERIF="$HOMEDIR/lab08/bin/verif-factura.sh"
val() { systemctl show -p "$1" --value "$UNIT" 2>/dev/null; }

[ -d /run/systemd/system ] || { \
  ko "systemd ne pilote pas cette machine : ce défi est inapplicable ici"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. l'unité et sa copie versionnée -----------------------------------
[ -f /etc/systemd/system/factura-api.service ] \
  && ok "unité présente dans /etc/systemd/system" \
  || ko "unité absente de /etc/systemd/system"
[ -s "$HOMEDIR/lab08/units/factura-api.service" ] \
  && ok "copie versionnée dans ~/lab08/units/" \
  || ko "copie versionnée manquante : ~/lab08/units/factura-api.service"

# --- 2. EnvironmentFile tolérant ----------------------------------------
if val EnvironmentFiles | grep -q 'ignore_errors=yes'; then
  ok "EnvironmentFile tolérant à l'absence du fichier (préfixe -)"
else
  ko "EnvironmentFile doit être préfixé d'un tiret : \
EnvironmentFile=-/etc/factura/api.env"
fi

# --- 3. état et directives -----------------------------------------------
[ "$(systemctl is-active  "$UNIT")" = active ]  \
  && ok "service actif"   || ko "service inactif"
[ "$(systemctl is-enabled "$UNIT")" = enabled ] \
  && ok "service activé au boot" || ko "service non activé au boot"
case "$(val Type)" in
  exec|notify) ok "Type=$(val Type)" ;;
  *) ko "Type=$(val Type) ne détecte pas une erreur de démarrage" ;;
esac
[ -n "$(val ExecReload)" ] \
  && ok "ExecReload défini" || ko "ExecReload manquant"
[ "$(val Restart)" = on-failure ] \
  && ok "Restart=on-failure" || ko "Restart=$(val Restart) inattendu"
case "$(val TimeoutStopUSec)" in
  20s|20000000) ok "TimeoutStopSec=20s" ;;
  *) ko "TimeoutStopSec attendu à 20s (lu : $(val TimeoutStopUSec))" ;;
esac
[ "$(val LimitNOFILE)" = 65536 ] \
  && ok "LimitNOFILE=65536" || ko "LimitNOFILE=$(val LimitNOFILE)"
[ "$(val TasksMax)" = 64 ] \
  && ok "TasksMax=64" || ko "TasksMax=$(val TasksMax)"
case "$(val CPUQuotaPerSecUSec)" in
  500ms|500000) ok "CPUQuota=50%" ;;
  *) ko "CPUQuota=50% attendu (lu : $(val CPUQuotaPerSecUSec))" ;;
esac

# --- 4. le drop-in de préprod prime sur l'unité --------------------------
if [ -f "$DROPIN" ]; then
  ok "drop-in 10-preprod.conf présent"
  [ "$(val MemoryMax)" = 134217728 ] \
    && ok "MemoryMax=128M : le drop-in l'emporte sur l'unité de base" \
    || ko "MemoryMax vaut $(val MemoryMax), le drop-in doit l'abaisser à \
134217728 (128M)"
  val Environment | tr ' ' '\n' | grep -q '^FACTURA_PORT=8081$' \
    && ok "le port effectif est 8081 (posé par le drop-in)" \
    || ko "FACTURA_PORT=8081 attendu dans l'environnement effectif \
(systemctl show -p Environment $UNIT)"
else
  ko "drop-in absent : $DROPIN"
fi

if curl -fsS --max-time 4 "http://127.0.0.1:8081/sante" >/dev/null 2>&1; then
  ok "l'API répond sur le port 8081"
else
  ko "aucune réponse sur 8081 (ss -tulpn, puis le journal du service)"
fi

# --- 5. score de durcissement --------------------------------------------
SCORE=$(systemd-analyze security "$UNIT" 2>/dev/null \
        | awk '/exposure level/ {for (i=1;i<=NF;i++) \
               if ($i ~ /^[0-9]+\.[0-9]$/) print $i}' | tail -1)
if [ -n "$SCORE" ] && awk -v s="$SCORE" 'BEGIN {exit !(s < 2.5)}'; then
  ok "score systemd-analyze security = $SCORE (< 2.5)"
else
  ko "score = ${SCORE:-illisible} : le cahier des charges exige < 2.5"
fi

# --- 6. le runbook -------------------------------------------------------
if [ -s "$RUNBOOK" ]; then
  L=$(grep -c . "$RUNBOOK")
  [ "$L" -ge 30 ] \
    && ok "runbook rédigé ($L lignes)" \
    || ko "runbook trop court ($L lignes, 30 minimum)"
  MANQUE=""
  for mot in reload restart 203 SIGKILL drop-in; do
    grep -qi -- "$mot" "$RUNBOOK" || MANQUE="$MANQUE $mot"
  done
  [ -z "$MANQUE" ] \
    && ok "le runbook couvre les cinq rubriques imposées" \
    || ko "il manque dans le runbook :$MANQUE"
else
  ko "runbook absent : ~/lab08/rapports/runbook-factura-api.md"
fi

# --- 7. le script de conformité ------------------------------------------
if [ -x "$VERIF" ]; then
  ok "verif-factura.sh présent et exécutable"
  head -1 "$VERIF" | grep -q '^#!/usr/bin/env bash' \
    && ok "shebang conforme" || ko "shebang attendu : #!/usr/bin/env bash"
  grep -q 'set -euo pipefail' "$VERIF" \
    && ok "set -euo pipefail présent" || ko "set -euo pipefail manquant"
  grep -q 'systemctl show' "$VERIF" \
    && ok "le script interroge systemctl show (et non le fichier d'unité)" \
    || ko "le script doit lire les valeurs effectives avec systemctl show"
  grep -q 'limits' "$VERIF" \
    && ok "le script lit /proc/<pid>/limits" \
    || ko "la limite effective doit être lue dans /proc/<pid>/limits"
  if sudo -u "$LAB_USER" bash "$VERIF" >/dev/null 2>&1; then
    ok "verif-factura.sh sort en 0"
  else
    ko "verif-factura.sh sort en erreur : la machine n'est pas conforme \
à ton propre script"
  fi
else
  ko "script absent ou non exécutable : ~/lab08/bin/verif-factura.sh"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
