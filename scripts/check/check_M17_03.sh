#!/usr/bin/env bash
# check_M17_03.sh — vérifie le lab L17.3 (migration vers un timer systemd)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L17.3 =="

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
[ -d /run/systemd/system ] || { \
  ko "systemd ne pilote pas cette machine : lab inapplicable ici"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
VALID="$HOMEDIR/lab17/rapports/validation.txt"
SVC=factura-sauv.service
TMR=factura-sauv.timer

v() { systemctl show -p "$2" --value "$1" 2>/dev/null; }

# --- 1. le service -----------------------------------------------------
if systemctl cat "$SVC" >/dev/null 2>&1; then
  ok "$SVC existe"
  [ "$(v "$SVC" Type)" = oneshot ] \
    && ok "Type=oneshot" \
    || ko "Type=$(v "$SVC" Type) : une sauvegarde se termine, elle ne \
tourne pas en continu"
  [ "$(v "$SVC" User)" = factura ] \
    && ok "User=factura" \
    || ko "User=$(v "$SVC" User) : la sauvegarde ne doit pas tourner en root"
  EXE=$(v "$SVC" ExecStart)
  echo "$EXE" | grep -q 'factura-sauvegarde-nuit.sh' \
    && ok "ExecStart appelle le script de L17.2" \
    || ko "ExecStart n'appelle pas /opt/factura/bin/factura-sauvegarde-nuit.sh"

  # -- contraintes de ressources --
  v "$SVC" After | grep -q 'srv-factura.mount' \
    && ok "After=srv-factura.mount (dépendance d'ordre)" \
    || ko "aucune dépendance d'ordre sur srv-factura.mount (point 2)"
  CPU=$(v "$SVC" CPUQuotaPerSecUSec)
  if [ -n "$CPU" ] && [ "$CPU" != "infinity" ]; then
    ok "quota CPU appliqué ($CPU)"
  else
    ko "CPUQuota= absent : l'énoncé demande 50 % d'un cœur"
  fi
  MEM=$(v "$SVC" MemoryMax)
  if [ -n "$MEM" ] && [ "$MEM" != "infinity" ] && \
     [ "$MEM" -le 600000000 ] 2>/dev/null; then
    ok "MemoryMax appliqué ($MEM octets)"
  else
    ko "MemoryMax= absent ou trop large ($MEM) : 512M attendu"
  fi
  RMS=$(v "$SVC" RuntimeMaxUSec)
  if [ -n "$RMS" ] && [ "$RMS" != "infinity" ]; then
    ok "RuntimeMaxSec appliqué ($RMS)"
  else
    ko "RuntimeMaxSec= absent : une sauvegarde bloquée doit être tuée \
au-delà de 30 minutes (point 2)"
  fi
else
  ko "$SVC introuvable (systemctl cat $SVC)"
fi

# --- 2. le timer -------------------------------------------------------
if systemctl cat "$TMR" >/dev/null 2>&1; then
  ok "$TMR existe"
  CAL=$(v "$TMR" TimersCalendar)
  echo "$CAL" | grep -q '02:30' \
    && ok "OnCalendar à 02:30 ($CAL)" \
    || ko "expression calendaire inattendue : $CAL"
  [ "$(v "$TMR" Persistent)" = yes ] \
    && ok "Persistent=true (rattrapage machine éteinte)" \
    || ko "Persistent=true manquant : la sauvegarde d'une nuit où la \
machine était éteinte ne serait jamais rattrapée (point 3)"
  RD=$(v "$TMR" RandomizedDelayUSec)
  if [ -n "$RD" ] && [ "$RD" != "0" ]; then
    ok "RandomizedDelaySec appliqué ($RD)"
  else
    ko "RandomizedDelaySec= absent : 300 serveurs taperaient tous à 02:30"
  fi
  [ "$(systemctl is-enabled "$TMR" 2>/dev/null)" = enabled ] \
    && ok "$TMR est enabled" \
    || ko "$TMR n'est pas activé (systemctl enable --now $TMR)"
  [ "$(systemctl is-active "$TMR" 2>/dev/null)" = active ] \
    && ok "$TMR est active" \
    || ko "$TMR n'est pas démarré"
  systemctl list-timers --all --no-pager 2>/dev/null | grep -q "$TMR" \
    && ok "$TMR apparaît dans systemctl list-timers" \
    || ko "$TMR n'apparaît pas dans la liste des timers"
  [ "$(systemctl is-enabled "$SVC" 2>/dev/null)" != enabled ] \
    && ok "$SVC n'est pas activé séparément (c'est le timer qui pilote)" \
    || ko "$SVC est enabled : il démarrera aussi à chaque boot, en plus \
du timer"
else
  ko "$TMR introuvable"
fi

# --- 3. la validation faite AVANT installation ------------------------
if [ -s "$VALID" ]; then
  ok "rapport de validation présent"
  grep -qi 'calendar' "$VALID" \
    && ok "sortie de systemd-analyze calendar consignée" \
    || ko "la sortie de systemd-analyze calendar n'est pas dans $VALID"
  grep -qi 'verify\|analyze' "$VALID" \
    && ok "sortie de systemd-analyze verify consignée" \
    || ko "la sortie de systemd-analyze verify n'est pas dans $VALID"
  grep -qiE 'parall|chevauch|simultan|en cours|déjà actif|deja actif' \
    "$VALID" \
    && ok "point 7 traité (timer qui se déclenche pendant l'exécution)" \
    || ko "point 7 non traité : que fait systemd si le timer se déclenche \
alors que le service tourne encore ?"
else
  ko "rapport absent : $VALID"
fi

# --- 4. vérification par systemd-analyze ------------------------------
if systemd-analyze verify "/etc/systemd/system/$TMR" 2>/tmp/.m14_03.v; then
  if [ -s /tmp/.m14_03.v ]; then
    note "systemd-analyze verify remonte des avertissements :"
    sed 's/^/        /' /tmp/.m14_03.v
  else
    ok "systemd-analyze verify passe sans avertissement"
  fi
else
  ko "systemd-analyze verify échoue sur $TMR (voir /tmp/.m14_03.v)"
fi

# --- 5. la version cron est neutralisée, pas supprimée ----------------
if [ -f /etc/cron.d/factura-sauvegarde ]; then
  if grep -vE '^[[:space:]]*#' /etc/cron.d/factura-sauvegarde \
     | grep -qE '^[0-9*]'; then
    ko "la ligne cron de L17.2 est toujours active : elle ferait une \
deuxième sauvegarde en parallèle du timer (point 6)"
  else
    ok "la tâche cron est commentée, le fichier est conservé"
  fi
else
  ko "le fichier /etc/cron.d/factura-sauvegarde a été supprimé : l'énoncé \
demande une neutralisation réversible et visible (point 6)"
fi

# --- 6. une exécution manuelle produit une archive --------------------
AVANT=$(ls -1 /srv/factura/backups 2>/dev/null | wc -l)
systemctl start "$SVC" >/dev/null 2>&1
sleep 2
APRES=$(ls -1 /srv/factura/backups 2>/dev/null | wc -l)
RES=$(v "$SVC" Result)
[ "$RES" = success ] \
  && ok "systemctl start $SVC : Result=success" \
  || ko "Result=$RES après démarrage manuel (journalctl -u $SVC -n 30)"
[ "$APRES" -gt "$AVANT" ] \
  && ok "une archive a été produite par le service" \
  || ko "aucune nouvelle archive dans /srv/factura/backups"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
