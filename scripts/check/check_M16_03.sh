#!/usr/bin/env bash
# check_M16_03.sh — vérifie le lab L16.3 (rotation des journaux factura)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L16.3 =="

CONF=/etc/logrotate.d/factura
LOGD=/var/log/factura
LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab16/rotation.md"
priv() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo -n "$@"; fi; }

command -v logrotate >/dev/null 2>&1 || {
  ko "logrotate n'est pas installé"; echo "Résultat : $PASS réussis, \
$FAIL échoués"; exit 1; }

# --- 1. le fichier de configuration --------------------------------------
if [ -f "$CONF" ]; then
  ok "$CONF existe"
  MODE=$(stat -c %a "$CONF"); PROP=$(stat -c %U:%G "$CONF")
  case "$MODE" in
    644|444) ok "mode $MODE : logrotate ne l'ignorera pas" ;;
    *) ko "mode $MODE : logrotate ignore tout fichier accessible en \
écriture au groupe ou aux autres (attendu 0644)" ;;
  esac
  [ "$PROP" = "root:root" ] && ok "propriétaire root:root" \
    || ko "propriétaire $PROP au lieu de root:root"
else
  ko "$CONF manquant"
fi

# --- 2. les directives exigées -------------------------------------------
if [ -f "$CONF" ]; then
  besoin() { grep -qE "^\s*$1" "$CONF" \
    && ok "directive $1 présente" || ko "directive $1 absente de $CONF"; }
  besoin 'daily'
  besoin 'rotate 14'
  besoin 'delaycompress'
  besoin 'notifempty'
  besoin 'missingok'
  besoin 'create 0640 factura adm'
  besoin 'su '
  besoin 'size'
  besoin 'postrotate'
  besoin 'sharedscripts'
  grep -qE '^\s*dateext' "$CONF" \
    && ok "dateext présent (bloc acces.log)" \
    || ko "dateext manquant : acces.log doit être suffixé par une date"
  grep -qE '^\s*weekly' "$CONF" \
    && ok "un bloc hebdomadaire existe (acces.log)" \
    || ko "aucun bloc weekly : acces.log doit tourner chaque semaine"
  grep -qE 'copytruncate' "$CONF" \
    && ko "copytruncate est utilisé : ce n'est pas le choix attendu ici" \
    || ok "pas de copytruncate"
  grep -qE 'kill.*[0-9]{3,}' "$CONF" \
    && ko "un PID en dur apparaît dans postrotate (utilise systemctl kill)" \
    || ok "aucun PID codé en dur dans postrotate"
fi

# --- 3. le dry run ne signale rien ---------------------------------------
SORTIE=$(priv logrotate -d /etc/logrotate.conf 2>&1)
if [ -n "$SORTIE" ]; then
  echo "$SORTIE" | grep -qi 'ignoring.*factura' \
    && ko "logrotate ignore encore la configuration factura" \
    || ok "logrotate ne rejette pas la configuration factura"
  echo "$SORTIE" | grep -qiE '^error:' \
    && ko "logrotate -d remonte une erreur : $(echo "$SORTIE" \
| grep -iE '^error:' | head -1)" \
    || ok "logrotate -d ne remonte aucune erreur"
  echo "$SORTIE" | grep -q 'considering log /var/log/factura/app.log' \
    && ok "app.log est bien pris en charge" \
    || ko "app.log n'apparaît pas dans la sortie de logrotate -d"
else
  ko "logrotate -d n'a rien produit (droits insuffisants : relance avec \
sudo)"
fi

# --- 4. la rotation a réellement eu lieu ---------------------------------
priv test -f "$LOGD/app.log.1" \
  && ok "$LOGD/app.log.1 existe" \
  || ko "aucune génération app.log.1 (force une rotation : \
sudo logrotate -f /etc/logrotate.conf)"
priv test -f "$LOGD/app.log.2.gz" \
  && ok "$LOGD/app.log.2.gz existe (delaycompress fonctionne)" \
  || ko "pas de app.log.2.gz : delaycompress compresse au tour SUIVANT, \
il faut donc deux rotations"
priv test -f "$LOGD/app.log.1.gz" \
  && ko "app.log.1.gz existe : delaycompress n'est pas appliqué" \
  || ok "app.log.1 n'est pas compressé, conforme à delaycompress"

if priv test -f "$LOGD/app.log"; then
  D=$(priv stat -c %U:%G:%a "$LOGD/app.log")
  [ "$D" = "factura:adm:640" ] \
    && ok "app.log recréé en factura:adm 0640" \
    || ko "app.log est en $D, on attend factura:adm:640 (directive create)"
fi

# --- 5. état et rapport ---------------------------------------------------
for E in /var/lib/logrotate/status /var/lib/logrotate.status; do
  priv test -f "$E" || continue
  priv grep -q '/var/log/factura/app.log' "$E" \
    && ok "l'état de rotation connaît app.log ($E)" \
    || ko "app.log absent de l'état $E"
done

if [ -s "$RAP" ]; then
  ok "$RAP existe"
  grep -qi 'copytruncate' "$RAP" \
    && ok "le rapport justifie le choix face à copytruncate" \
    || ko "le rapport ne parle pas de copytruncate"
else
  ko "$RAP manquant"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
