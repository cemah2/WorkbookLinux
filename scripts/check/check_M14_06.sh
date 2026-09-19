#!/usr/bin/env bash
# check_M14_06.sh — vérifie le défi D14 (audit de la planification)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D14 =="

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
AUDIT="$HOMEDIR/bin/audit-planif.sh"
RAPP="$HOMEDIR/lab14/rapports/audit-lab-web.md"
DEC="$HOMEDIR/lab14/rapports/decisions.md"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- 1. le script ------------------------------------------------------
if [ -x "$AUDIT" ]; then
  ok "$AUDIT existe et est exécutable"
  head -1 "$AUDIT" | grep -q '#!/usr/bin/env bash' \
    && ok "shebang #!/usr/bin/env bash" \
    || ko "shebang attendu : #!/usr/bin/env bash"
  grep -q 'set -euo pipefail' "$AUDIT" \
    && ok "set -euo pipefail" \
    || ko "set -euo pipefail manquant"
  grep -qE 'crond?\.service|command -v crontab|cronie|/etc/redhat-release|\
ID_LIKE|is-active cron' "$AUDIT" \
    && ok "le script s'adapte au nom du service cron (cron vs crond)" \
    || ko "le script suppose un seul nom de service : il doit tourner sur \
lab-web (cron.service) et lab-rhel (crond.service) sans modification"
else
  ko "$AUDIT absent ou non exécutable"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi

# --- 2. séparation stdout / stderr ------------------------------------
"$AUDIT" > "$TMP/out.md" 2> "$TMP/err.txt"
RC=$?
if [ -s "$TMP/out.md" ]; then
  ok "le script produit un rapport sur stdout"
  grep -qE '^#|^\|' "$TMP/out.md" \
    && ok "la sortie est du Markdown (titres ou tableau)" \
    || ko "stdout ne ressemble pas à du Markdown"
  grep -qiE 'diagnostic|analyse en cours|\[debug\]|lecture de' "$TMP/out.md" \
    && ko "des traces de diagnostic polluent stdout : elles vont sur stderr" \
    || ok "stdout ne contient que le rapport"
else
  ko "stdout est vide"
fi

# --- 3. contenu du rapport --------------------------------------------
sec() {
  grep -qiE "$2" "$TMP/out.md" \
    && ok "rapport : $1" \
    || ko "rapport : $1 manquant"
}
sec "crontabs utilisateurs recensées" 'crontab'
sec "/etc/cron.d recensé"             '/etc/cron\.d|cron\.d'
sec "répertoires cron.* recensés"     'cron\.(daily|hourly|weekly|monthly)'
sec "timers systemd recensés"         'timer'
sec "section Anomalies"               'anomalie'

if grep -qE '^\|.*\|.*\|.*\|.*\|.*\|' "$TMP/out.md"; then
  ok "tableau à 5 colonnes (source, planification, commande, user, dernière)"
else
  ko "le tableau du rapport n'a pas les 5 colonnes demandées au point 2"
fi

# --- 4. les sept détections, éprouvées sur des cas fabriqués ----------
echo "  -- mise en place de cas de test --"
BK="$TMP/backup"; mkdir -p "$BK"
CLEAN=""

# (a) % non échappé + (b) /dev/null, dans un fichier de /etc/cron.d
cat > /etc/cron.d/zz-audit-test1 <<'EOF'
17 3 * * * root tar czf /tmp/t-$(date +%F).tgz /srv/factura/data
23 3 * * * root /opt/factura/bin/factura-rapport.sh > /dev/null 2>&1
EOF
# (c) script cron.daily invisible pour run-parts
printf '#!/bin/sh\nexit 0\n' > /etc/cron.daily/zz-audit-test.sh
chmod 0755 /etc/cron.daily/zz-audit-test.sh
# (d) entrée /etc/cron.d sans champ utilisateur
printf '*/7 * * * * /bin/true\n' > /etc/cron.d/zz-audit-test2
chmod 0644 /etc/cron.d/zz-audit-test1 /etc/cron.d/zz-audit-test2
# (g) tâche fréquente sans verrou
printf '*/5 * * * * root /opt/factura/bin/factura-lent.sh 2\n' \
  > /etc/cron.d/zz-audit-test3
chmod 0644 /etc/cron.d/zz-audit-test3

"$AUDIT" > "$TMP/out2.md" 2>/dev/null
RC2=$?

det() {
  grep -qiF "$2" "$TMP/out2.md" \
    && ok "détection : $1" \
    || ko "détection manquante : $1 (cas fabriqué : $2)"
}
det "% non échappé"                     "zz-audit-test1"
det "script cron.daily jamais exécuté"  "zz-audit-test.sh"
det "entrée /etc/cron.d sans user"      "zz-audit-test2"
det "tâche fréquente sans verrou"       "zz-audit-test3"
grep -qF '/dev/null' "$TMP/out2.md" \
  && ok "détection : sortie envoyée dans /dev/null" \
  || ko "détection manquante : une tâche jette toute sa sortie"
grep -qiF 'factura-orphelin' "$TMP/out2.md" \
  && ok "détection : timer sans unité déclenchée" \
  || ko "détection manquante : factura-orphelin.timer déclenche une unité \
inexistante"
grep -qiE 'dernière exécution|derniere execution|jamais exécuté|obsolète|\
obsolete|périmé|perime|trop ancien' "$TMP/out2.md" \
  && ok "détection : timer dont la dernière exécution est trop ancienne" \
  || ko "détection manquante : timer dont la dernière exécution remonte à \
plus de deux fois son intervalle"

[ "$RC2" -ne 0 ] \
  && ok "code de sortie non nul en présence d'anomalies ($RC2)" \
  || ko "le script sort en 0 alors que 7 anomalies sont présentes"

rm -f /etc/cron.d/zz-audit-test1 /etc/cron.d/zz-audit-test2 \
      /etc/cron.d/zz-audit-test3 /etc/cron.daily/zz-audit-test.sh

# --- 5. la machine est effectivement propre ---------------------------
"$AUDIT" > "$TMP/out3.md" 2>/dev/null
RC3=$?
[ "$RC3" -eq 0 ] \
  && ok "sur la machine nettoyée, audit-planif.sh sort en 0 (point 5)" \
  || ko "audit-planif.sh sort encore en $RC3 : il reste des anomalies à \
corriger sur lab-web (voir la section Anomalies de sa propre sortie)"

if [ "$RC3" -ne 0 ]; then
  note "anomalies restantes :"
  sed -n '/[Aa]nomalie/,$p' "$TMP/out3.md" | head -12 | sed 's/^/        /'
fi

# --- 6. les livrables --------------------------------------------------
[ -s "$RAPP" ] \
  && ok "livrable présent : $RAPP" \
  || ko "livrable manquant : $RAPP (généré par le script)"
if [ -s "$DEC" ]; then
  ok "livrable présent : $DEC"
  L=$(grep -cE '^[-*|[:alnum:]]' "$DEC")
  [ "$L" -ge 3 ] \
    && ok "decisions.md documente au moins 3 migrations" \
    || ko "decisions.md trop court : une ligne par tâche migrée, indiquant \
ce que le timer apporte"
else
  ko "livrable manquant : $DEC"
fi

# --- 7. la règle interne est appliquée --------------------------------
if [ -d /run/systemd/system ]; then
  NT=$(systemctl list-timers --all --no-pager 2>/dev/null \
       | grep -c 'factura')
  [ "$NT" -ge 2 ] \
    && ok "$NT timers factura en place" \
    || ko "seulement $NT timer factura : les tâches récurrentes devaient \
être converties (point 5)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
