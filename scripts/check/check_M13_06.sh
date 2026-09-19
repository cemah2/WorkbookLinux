#!/usr/bin/env bash
# check_M13_06.sh — vérifie le défi D13 (poste de pilotage)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D13 =="

SANTE=/opt/factura/bin/sante.sh
CSV=/var/log/factura/metriques.csv
LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
DOC="$HOMEDIR/lab13/pilotage.md"
priv() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo -n "$@"; fi; }

# --- 1. journalisation ----------------------------------------------------
[ -d /var/log/journal ] && ok "journal persistant" \
  || ko "/var/log/journal absent"
CFG=$(systemd-analyze cat-config systemd/journald.conf 2>/dev/null)
MAX=$(echo "$CFG" | grep -E '^\s*SystemMaxUse=' | tail -1 | cut -d= -f2)
case "$MAX" in
  500M|500m|512M) ok "SystemMaxUse=$MAX" ;;
  "") ko "SystemMaxUse non défini : le journal n'a pas de plafond explicite" ;;
  *) ko "SystemMaxUse=$MAX, le cahier des charges demande 500M" ;;
esac
echo "$CFG" | grep -qE '^\s*MaxRetentionSec=(30day|2592000|1month)' \
  && ok "MaxRetentionSec limite la rétention à 30 jours" \
  || ko "MaxRetentionSec=30day manquant"

if priv test -s /var/log/factura/metier.log; then
  ok "/var/log/factura/metier.log est alimenté (facilité local6)"
else
  ko "/var/log/factura/metier.log vide ou absent (règle rsyslog local6)"
fi
grep -rqs 'local6' /etc/rsyslog.d/ \
  && ok "une règle rsyslog traite la facilité local6" \
  || ko "aucune règle rsyslog sur local6 dans /etc/rsyslog.d/"
priv grep -qs 'local6' /var/log/syslog 2>/dev/null \
  && ko "des messages local6 sont encore dans /var/log/syslog" \
  || ok "les messages local6 ne polluent plus /var/log/syslog"
grep -rqs 'factura-bruyant' /etc/rsyslog.d/ \
  && ok "une règle rsyslog traite factura-bruyant" \
  || ko "aucune règle rsyslog ne filtre factura-bruyant"

# --- 2. rotation ----------------------------------------------------------
SORTIE=$(priv logrotate -d /etc/logrotate.conf 2>&1)
echo "$SORTIE" | grep -qiE '^error:' \
  && ko "logrotate -d remonte une erreur sur la configuration de la machine" \
  || ok "logrotate -d : aucune erreur sur toute la configuration"
echo "$SORTIE" | grep -qi 'ignoring' \
  && ko "logrotate ignore encore au moins un fichier : $(echo "$SORTIE" \
| grep -i ignoring | head -1)" \
  || ok "logrotate n'ignore aucun fichier de configuration"
echo "$SORTIE" | grep -q "$CSV" \
  && ok "metriques.csv est géré par logrotate" \
  || ko "$CSV n'est pas pris en charge par logrotate"
grep -rqsE '^\s*size\s' /etc/logrotate.d/ \
  && ok "au moins une règle est déclenchée par la taille" \
  || ko "aucune règle basée sur size"

# --- 3. le script de santé -------------------------------------------------
if [ -x "$SANTE" ]; then
  ok "$SANTE existe et est exécutable"
  head -1 "$SANTE" | grep -q '^#!/usr/bin/env bash' \
    && ok "shebang conforme" || ko "shebang attendu #!/usr/bin/env bash"
  grep -q 'set -euo pipefail' "$SANTE" \
    && ok "set -euo pipefail" || ko "set -euo pipefail manquant"

  SORTIE=$(priv "$SANTE" 2>/dev/null); RC=$?
  case "$RC" in
    0|1|2) ok "code retour $RC conforme (0/1/2)" ;;
    *) ko "code retour $RC hors contrat (attendu 0, 1 ou 2)" ;;
  esac
  for SEC in charge cpu 'm[ée]moire' inode journal VERDICT; do
    echo "$SORTIE" | grep -qiE "$SEC" \
      && ok "section « $SEC » présente" \
      || ko "section « $SEC » absente du rapport"
  done
  echo "$SORTIE" | grep -qiE 'us[^a-z]|sy[^a-z]|wa[^a-z]|st[^a-z]' \
    && ok "la répartition CPU us/sy/wa/st est affichée" \
    || ko "la répartition CPU us/sy/wa/st n'apparaît pas"
  echo "$SORTIE" | grep -qiE 'inode' \
    && ok "l'usage des inodes est affiché" \
    || ko "l'usage des inodes manque (le piège du /var plein à 40 %)"
  echo "$SORTIE" | grep -qiE 'failed|en [ée]chec' \
    && ok "les unités en échec sont listées" \
    || note "aucune unité en échec à afficher, section peut-être vide"

  # robustesse : le script ne doit pas mourir sans iostat
  if PATH=/usr/bin:/bin priv env PATH=/usr/bin:/bin "$SANTE" \
       >/dev/null 2>&1; then
    ok "le script s'exécute encore dans un PATH réduit"
  else
    RC2=$?
    [ "$RC2" -le 2 ] \
      && ok "le script dégrade proprement (code $RC2)" \
      || ko "le script casse quand un outil optionnel manque (code $RC2)"
  fi
else
  ko "$SANTE manquant ou non exécutable"
fi

# --- 4. le document -------------------------------------------------------
if [ -s "$DOC" ]; then
  ok "$DOC existe"
  L=$(grep -cve '^\s*$' "$DOC")
  [ "$L" -ge 25 ] && ok "$L lignes utiles" \
    || ko "seulement $L lignes utiles (on en attend 25)"
  grep -qiE 'seuil' "$DOC" && ok "les seuils sont justifiés" \
    || ko "aucune justification de seuil"
  grep -qiE 'astreinte|nuit' "$DOC" \
    && ok "le document tranche sur ce qui réveille la nuit" \
    || ko "le document ne dit pas quelles alertes justifient une astreinte"
  [ "$(grep -ciE 'alerte|alert' "$DOC")" -ge 3 ] \
    && ok "au moins trois alertes sont décrites" \
    || ko "moins de trois alertes décrites"
else
  ko "$DOC manquant"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
