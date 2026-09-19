#!/usr/bin/env bash
# check_M14_01.sh — vérifie le lab L14.1 (inventaire des tâches planifiées)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L14.1 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab14/rapports/inventaire.md"

if [ ! -s "$RAP" ]; then
  ko "rapport absent : $RAP"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi
ok "rapport présent : $RAP"

LC=$(grep -c . "$RAP")
[ "$LC" -ge 20 ] \
  && ok "rapport substantiel ($LC lignes non vides)" \
  || ko "rapport trop court ($LC lignes) : 4 sources + tableau + anomalies"

# --- 1. les quatre sources de planification ----------------------------
src() {
  grep -qiE "$2" "$RAP" \
    && ok "source recensée : $1" \
    || ko "source manquante : $1 (cherche avec $3)"
}
src "crontabs utilisateurs" 'crontab' 'crontab -u <user> -l'
src "/etc/cron.d"           '/etc/cron\.d'  'ls /etc/cron.d/'
src "répertoires cron.*"    'cron\.(daily|hourly|weekly|monthly)' \
    'run-parts --test /etc/cron.daily'
src "timers systemd"        'timer' 'systemctl list-timers --all'
grep -qiE '\bat\b|atq|atjobs' "$RAP" \
  && ok "file at recensée" \
  || ko "les tâches at ne sont pas recensées (atq, /var/spool/cron/atjobs)"

# --- 2. le tableau à 4 colonnes ---------------------------------------
if grep -qE '^\|.*\|.*\|.*\|.*\|' "$RAP"; then
  ok "tableau Markdown à 4 colonnes présent"
  NL=$(grep -cE '^\|' "$RAP")
  [ "$NL" -ge 7 ] \
    && ok "tableau rempli ($NL lignes)" \
    || ko "tableau presque vide ($NL lignes) : la machine a plus de tâches"
else
  ko "pas de tableau | source | planification | commande | utilisateur |"
fi

# --- 3. les tâches réellement présentes doivent être citées -----------
cite() {
  grep -qiF "$1" "$RAP" \
    && ok "tâche citée : $1" \
    || ko "tâche non recensée : $1 ($2)"
}
cite "factura-rapport" "crontab de l'utilisateur factura"
cite "factura-veille-legacy" "fichier de /etc/cron.d"
cite "factura-purge" "script de /etc/cron.daily"

# --- 4. les quatre anomalies ------------------------------------------
echo "  -- anomalies attendues --"
grep -qi 'anomalie' "$RAP" \
  && ok "section Anomalies présente" \
  || ko "aucune section « Anomalies » dans le rapport"

grep -qiF 'factura-stats.sh' "$RAP" \
  && ok "anomalie : script cron.daily invisible pour run-parts" \
  || ko "un script de /etc/cron.daily ne sera jamais exécuté, lequel ? \
(run-parts --test /etc/cron.daily)"

grep -qF '/dev/null' "$RAP" \
  && ok "anomalie : tâche dont la sortie est jetée" \
  || ko "une tâche envoie toute sa sortie dans /dev/null, elle n'est pas \
signalée"

grep -qiF 'factura-archives' "$RAP" \
  && ok "anomalie : entrée /etc/cron.d mal formée" \
  || ko "un fichier de /etc/cron.d est invalide, lequel ? (compare le \
nombre de champs avec factura-veille-legacy)"

grep -qiF 'factura-orphelin' "$RAP" \
  && ok "anomalie : timer sans service associé" \
  || ko "un timer activé déclenche une unité inexistante \
(systemctl list-timers --all, colonne ACTIVATES)"

# --- 5. cohérence : l'apprenant n'a rien cassé ------------------------
if command -v crontab >/dev/null 2>&1; then
  crontab -u factura -l >/dev/null 2>&1 \
    && ok "la crontab de factura est toujours en place" \
    || note "la crontab de factura a disparu : L14.1 est un inventaire, \
pas un ménage"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
