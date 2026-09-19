#!/usr/bin/env bash
# check_M14_05.sh — vérifie le lab L14.5 (dead man's switch)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L14.5 =="

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
[ -d /run/systemd/system ] || { \
  ko "systemd ne pilote pas cette machine : lab inapplicable ici"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab14/rapports/veille.md"
VEILLE=/opt/factura/bin/factura-veille.sh
TEMOIN=/var/lib/factura/derniere-sauvegarde
SAUV=/opt/factura/bin/factura-sauvegarde-nuit.sh
ALOG=/var/log/factura/alertes.log

v() { systemctl show -p "$2" --value "$1" 2>/dev/null; }

# --- 1. le témoin est posé par la sauvegarde, en cas de succès seulement
if [ -f "$SAUV" ]; then
  grep -q "$TEMOIN" "$SAUV" \
    && ok "la sauvegarde référence le témoin $TEMOIN" \
    || ko "la sauvegarde ne touche pas $TEMOIN (point 1)"
  LTOUCH=$(grep -n "$TEMOIN" "$SAUV" | head -1 | cut -d: -f1)
  LTOT=$(wc -l < "$SAUV")
  if [ -n "$LTOUCH" ] && [ "$LTOUCH" -gt $((LTOT / 2)) ]; then
    ok "le témoin est posé en fin de script (ligne $LTOUCH/$LTOT)"
  else
    note "le témoin est posé ligne $LTOUCH sur $LTOT : vérifie qu'il n'est \
pas posé avant l'archivage — il ne doit marquer qu'un succès"
  fi
else
  ko "$SAUV absent : L14.5 s'appuie sur la sauvegarde de L14.2"
fi

# --- 2. le script de veille -------------------------------------------
if [ -x "$VEILLE" ]; then
  ok "$VEILLE existe et est exécutable"
  SAUVE=""
  [ -e "$TEMOIN" ] && { SAUVE=$(mktemp); cp -a "$TEMOIN" "$SAUVE"; }

  touch "$TEMOIN"
  "$VEILLE" 26 >/tmp/.m14_05.frais 2>&1; RF=$?
  [ "$RF" -eq 0 ] \
    && ok "témoin frais : code 0" \
    || ko "témoin fraîchement touché, code $RF au lieu de 0 \
(/tmp/.m14_05.frais)"

  touch -d '-40 hours' "$TEMOIN"
  "$VEILLE" 26 >/tmp/.m14_05.vieux 2>&1; RV=$?
  [ "$RV" -eq 1 ] \
    && ok "témoin vieux de 40 h avec seuil 26 h : code 1" \
    || ko "témoin antidaté de 40 h, code $RV au lieu de 1 \
(/tmp/.m14_05.vieux)"
  grep -qE '[0-9]+' /tmp/.m14_05.vieux \
    && ok "le message indique l'âge réel" \
    || ko "le message d'alerte ne donne pas l'âge du témoin en heures"

  mv "$TEMOIN" "$TEMOIN.bak" 2>/dev/null
  "$VEILLE" 26 >/dev/null 2>&1; RA=$?
  mv "$TEMOIN.bak" "$TEMOIN" 2>/dev/null
  [ "$RA" -eq 1 ] \
    && ok "témoin absent : code 1" \
    || ko "témoin absent, code $RA au lieu de 1 — l'absence de témoin est \
le cas le plus grave, pas une erreur à ignorer"

  grep -qE '\$\{?1' "$VEILLE" \
    && ok "le seuil est paramétrable (argument 1)" \
    || ko "le seuil n'est pas passé en argument (N en argument, 26 par \
défaut)"

  [ -n "$SAUVE" ] && cp -a "$SAUVE" "$TEMOIN" && rm -f "$SAUVE"
else
  ko "$VEILLE absent ou non exécutable"
fi

# --- 3. le timer de veille --------------------------------------------
TMR=""
for t in factura-veille.timer; do
  systemctl cat "$t" >/dev/null 2>&1 && TMR="$t"
done
if [ -n "$TMR" ]; then
  ok "$TMR existe"
  [ "$(systemctl is-enabled "$TMR" 2>/dev/null)" = enabled ] \
    && ok "$TMR est enabled" \
    || ko "$TMR n'est pas activé"
  [ "$(systemctl is-active "$TMR" 2>/dev/null)" = active ] \
    && ok "$TMR est active" \
    || ko "$TMR n'est pas démarré"
  CAL=$(v "$TMR" TimersCalendar)
  MON=$(v "$TMR" TimersMonotonic)
  if echo "$CAL" | grep -qiE 'hourly|\*:00|\*-\*-\* \*:'; then
    ok "cadence horaire ($CAL)"
  elif echo "$MON" | grep -q '3600'; then
    ok "cadence horaire (monotone : $MON)"
  else
    ko "cadence inattendue (OnCalendar=$CAL) : l'énoncé demande toutes les \
heures"
  fi
  OF=$(v factura-veille.service OnFailure)
  echo "$OF" | grep -q 'factura-alerte@' \
    && ok "l'échec de la veille déclenche l'unité d'alerte de L14.4" \
    || ko "OnFailure= n'est pas branché sur factura-alerte@ (point 3) — \
valeur : « $OF »"
  # protection contre le faux positif au démarrage (point 6)
  UCAT=$(systemctl cat factura-veille.service "$TMR" 2>/dev/null)
  if echo "$UCAT" | grep -qE 'ConditionUptime|OnBootSec|uptime|/proc/uptime'
  then
    ok "protection contre le faux positif au démarrage présente"
  else
    ko "rien ne protège du faux positif dans les 10 min après un \
redémarrage (point 6) : ConditionUptime= ou un test sur /proc/uptime"
  fi
else
  ko "aucun timer factura-veille.timer trouvé"
fi

# --- 4. le dispositif produit réellement une alerte -------------------
echo "  -- test dynamique --"
SAUVE2=""
[ -e "$TEMOIN" ] && { SAUVE2=$(mktemp); cp -a "$TEMOIN" "$SAUVE2"; }
AV=$(wc -l < "$ALOG" 2>/dev/null || echo 0)
touch -d '-40 hours' "$TEMOIN"
systemctl start factura-veille.service >/dev/null 2>&1
sleep 3
AP=$(wc -l < "$ALOG" 2>/dev/null || echo 0)
[ "$AP" -gt "$AV" ] \
  && ok "témoin antidaté : une alerte est écrite dans $ALOG" \
  || ko "témoin vieux de 40 h et aucune alerte : la chaîne \
timer -> service -> OnFailure -> alerte est rompue"

touch "$TEMOIN"
systemctl reset-failed factura-veille.service >/dev/null 2>&1
systemctl start factura-veille.service >/dev/null 2>&1
sleep 2
[ "$(v factura-veille.service Result)" = success ] \
  && ok "témoin remis à l'heure : la veille repasse au vert" \
  || ko "la veille reste en échec après remise à l'heure du témoin"
[ -n "$SAUVE2" ] && cp -a "$SAUVE2" "$TEMOIN" && rm -f "$SAUVE2"

# --- 5. le rapport ----------------------------------------------------
if [ -s "$RAP" ]; then
  ok "rapport veille.md présent"
  grep -qiE 'éteint|eteint|arrêt|arret|hors tension|coup(é|e)' "$RAP" \
    && ok "le cas « machine éteinte » est traité" \
    || ko "le rapport ne dit pas si le dispositif détecte une machine \
entièrement éteinte (point 5)"
  grep -qiE 'healthcheck|health check|ping|sortant|externe' "$RAP" \
    && ok "le principe du healthcheck externe est décrit" \
    || ko "le rapport ne décrit pas le service externe de type healthcheck \
(ping sortant périodique)"
else
  ko "rapport absent : $RAP"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
