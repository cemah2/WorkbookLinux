#!/usr/bin/env bash
# check_M08_04.sh — vérifie le lab L8.4 (durcissement + override par drop-in)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L8.4 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
UNIT=factura-api.service
val() { systemctl show -p "$1" --value "$UNIT" 2>/dev/null; }

[ -d /run/systemd/system ] || { \
  ko "systemd ne pilote pas cette machine : ce lab est inapplicable ici"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

systemctl cat "$UNIT" >/dev/null 2>&1 || { \
  ko "$UNIT introuvable : fais d'abord L8.2"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. score d'exposition ----------------------------------------------
SCORE=$(systemd-analyze security "$UNIT" 2>/dev/null \
        | awk '/exposure level/ {for (i=1;i<=NF;i++) \
               if ($i ~ /^[0-9]+\.[0-9]$/) print $i}' | tail -1)
if [ -n "$SCORE" ]; then
  if awk -v s="$SCORE" 'BEGIN {exit !(s < 3.0)}'; then
    ok "score systemd-analyze security = $SCORE (< 3.0)"
  else
    ko "score = $SCORE : il doit passer sous 3.0 (relance \
systemd-analyze security $UNIT et traite les lignes ✗ les plus lourdes)"
  fi
else
  ko "score d'exposition illisible (systemd-analyze security $UNIT)"
fi

# --- 2. directives d'isolation exigées ----------------------------------
[ "$(val NoNewPrivileges)" = yes ] \
  && ok "NoNewPrivileges=yes" || ko "NoNewPrivileges=yes manquant"
[ "$(val ProtectSystem)" = strict ] \
  && ok "ProtectSystem=strict" \
  || ko "ProtectSystem vaut « $(val ProtectSystem) », on attend strict"
case "$(val ProtectHome)" in
  yes|tmpfs) ok "ProtectHome=$(val ProtectHome)" ;;
  *) ko "ProtectHome doit rendre /home et /root inaccessibles (yes ou tmpfs)" ;;
esac
[ "$(val PrivateTmp)" = yes ] \
  && ok "PrivateTmp=yes" || ko "PrivateTmp=yes manquant"
[ "$(val CapabilityBoundingSet)" = "" ] \
  && ok "CapabilityBoundingSet vide : aucune capability conservée" \
  || ko "il reste des capabilities : $(val CapabilityBoundingSet)"
[ -n "$(val RestrictAddressFamilies)" ] \
  && ok "RestrictAddressFamilies=$(val RestrictAddressFamilies)" \
  || ko "RestrictAddressFamilies manquant (AF_INET AF_INET6 AF_UNIX suffisent)"

# --- 3. limites de ressources -------------------------------------------
[ "$(val LimitNOFILE)" = 65536 ] \
  && ok "LimitNOFILE=65536" \
  || ko "LimitNOFILE vaut $(val LimitNOFILE), on attend 65536"
[ "$(val MemoryMax)" = 268435456 ] \
  && ok "MemoryMax=256M (268435456 octets)" \
  || ko "MemoryMax vaut $(val MemoryMax), on attend 268435456"
case "$(val CPUQuotaPerSecUSec)" in
  500ms|500000) ok "CPUQuota=50%" ;;
  *) ko "CPUQuota=50% attendu (lu : $(val CPUQuotaPerSecUSec))" ;;
esac
[ "$(val TasksMax)" = 64 ] \
  && ok "TasksMax=64" || ko "TasksMax vaut $(val TasksMax), on attend 64"

# --- 4. le service fonctionne toujours -----------------------------------
PORT=$(grep -E '^FACTURA_PORT=' /etc/factura/api.env 2>/dev/null \
       | cut -d= -f2); PORT="${PORT:-8080}"
if curl -fsS --max-time 4 "http://127.0.0.1:$PORT/sante" >/dev/null 2>&1; then
  ok "le service durci répond toujours sur le port $PORT"
else
  ko "plus de réponse sur $PORT : le durcissement a cassé le service \
(regarde 226/NAMESPACE et les chemins en écriture)"
fi

MP=$(val MainPID)
if [ -n "$MP" ] && [ "$MP" != 0 ] && [ -r "/proc/$MP/limits" ]; then
  SOFT=$(awk '/Max open files/ {print $4}' "/proc/$MP/limits")
  [ "$SOFT" = 65536 ] \
    && ok "limite effective du processus : $SOFT descripteurs" \
    || ko "le processus tourne avec $SOFT descripteurs, pas 65536 \
(un drop-in écrase-t-il ta valeur ? systemctl cat $UNIT)"
fi

# --- 5. variante DynamicUser --------------------------------------------
DYN="$HOMEDIR/lab08/units/factura-api-dyn.service"
if [ -s "$DYN" ] && grep -q '^DynamicUser=yes' "$DYN"; then
  ok "variante DynamicUser rédigée dans ~/lab08/units/"
else
  ko "~/lab08/units/factura-api-dyn.service absent ou sans DynamicUser=yes"
fi

# --- 6. l'override ssh a été posé PUIS retiré ----------------------------
if [ -d /etc/systemd/system/ssh.service.d ] && \
   compgen -G '/etc/systemd/system/ssh.service.d/*.conf' >/dev/null; then
  ko "il reste un drop-in sur ssh.service : l'étape 10 demande de l'annuler \
(systemctl revert ssh, puis daemon-reload)"
else
  ok "aucun drop-in résiduel sur ssh.service"
fi
SSHNOF=$(systemctl show -p LimitNOFILE --value ssh.service 2>/dev/null)
[ "$SSHNOF" != 16384 ] \
  && ok "LimitNOFILE de ssh.service revenu à sa valeur d'origine ($SSHNOF)" \
  || ko "ssh.service est encore à 16384 : l'override n'a pas été annulé"

# --- 7. le rapport de précédence ----------------------------------------
RAP="$HOMEDIR/lab08/rapports/override.md"
if [ -s "$RAP" ] && [ "$(grep -c . "$RAP")" -ge 8 ]; then
  ok "rapport override.md rédigé"
  grep -q '/usr/lib/systemd/system' "$RAP" || \
    note "le rapport ne cite pas /usr/lib/systemd/system"
else
  ko "rapport absent ou trop court : ~/lab08/rapports/override.md"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
