#!/usr/bin/env bash
# check_M17_02.sh — vérifie le lab L17.2 (sauvegarde nocturne en cron)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L17.2 =="

SCRIPT=/opt/factura/bin/factura-sauvegarde-nuit.sh
CRND=/etc/cron.d/factura-sauvegarde
BACK=/srv/factura/backups

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

# --- 1. le script ------------------------------------------------------
if [ -x "$SCRIPT" ]; then
  ok "$SCRIPT existe et est exécutable"
  head -1 "$SCRIPT" | grep -q 'bash' \
    && ok "shebang bash" \
    || ko "shebang : #!/usr/bin/env bash attendu"
  if grep -qE '^[[:space:]]*set -[a-zA-Z]*e' "$SCRIPT"; then
    ok "set -e… présent (durcissement bash)"
  else
    ko "le script ne durcit pas bash : set -euo pipefail attendu"
  fi
  grep -qE '^[[:space:]]*(export[[:space:]]+)?PATH=' "$SCRIPT" \
    && ok "le script définit son propre PATH" \
    || ko "le script hérite du PATH de cron (/usr/bin:/bin) : définis-le \
explicitement en tête (point 1 de l'énoncé)"
  grep -qE 'exit[[:space:]]+2|return[[:space:]]+2' "$SCRIPT" \
    && ok "code de sortie 2 prévu (source vide/absente)" \
    || ko "aucun exit 2 : le point 2 demande 0 / 1 / 2 selon le cas"
else
  ko "$SCRIPT absent ou non exécutable"
fi

# --- 2. le fichier /etc/cron.d ----------------------------------------
if [ -f "$CRND" ]; then
  ok "$CRND existe"
  LIGNE=$(grep -vE '^[[:space:]]*(#|$)' "$CRND" | grep -E '^[0-9*]' | head -1)
  if [ -n "$LIGNE" ]; then
    NCH=$(echo "$LIGNE" | awk '{print NF}')
    [ "$NCH" -ge 7 ] \
      && ok "la ligne a au moins 7 champs (5 temps + user + commande)" \
      || ko "la ligne n'a que $NCH champs : dans /etc/cron.d il faut un \
champ utilisateur entre les 5 champs de temps et la commande"
    echo "$LIGNE" | awk '{print $6}' | grep -qx 'factura' \
      && ok "exécutée par l'utilisateur factura" \
      || ko "6e champ = $(echo "$LIGNE" | awk '{print $6}') — on attend \
« factura »"
    echo "$LIGNE" | awk '{print $1" "$2}' | grep -qx '30 2' \
      && ok "planifiée à 02:30" \
      || ko "planification $(echo "$LIGNE" | awk '{print $1" "$2}') — \
l'énoncé demande 02:30 tous les jours"
  else
    ko "aucune ligne de planification exploitable dans $CRND"
  fi
  grep -vE '^[[:space:]]*#' "$CRND" | grep -q '%' \
    && ko "un % non commenté traîne dans $CRND : dans une crontab il coupe \
la commande et devient un saut de ligne" \
    || ok "aucun % dans le fichier"
  CONT=$(grep -c '\\[[:space:]]*$' "$CRND")
  [ "$CONT" -eq 0 ] \
    && ok "aucune continuation de ligne par \\ (cron ne la connaît pas)" \
    || ko "$CONT ligne(s) se terminent par \\ : cron ne supporte pas la \
continuation de ligne, la tâche doit tenir sur une seule ligne physique"
  grep -qE '^[[:space:]]*MAILTO[[:space:]]*=' "$CRND" \
    && ok "MAILTO positionné explicitement" \
    || ko "MAILTO n'est pas défini : sans lui, cron tente d'envoyer la \
sortie par mail au propriétaire (point 5)"
  [ "$(stat -c '%a' "$CRND")" = 644 ] \
    && ok "droits 0644 sur $CRND" \
    || note "droits $(stat -c '%a' "$CRND") : cron attend un fichier \
non inscriptible par le groupe/les autres"
else
  ko "$CRND absent : la tâche doit être livrable par fichier, pas par \
crontab utilisateur"
fi

# --- 3. verrou anti-chevauchement -------------------------------------
VERR=0
grep -qE 'flock|run-one' "$CRND" 2>/dev/null && VERR=1
grep -qE 'flock' "$SCRIPT" 2>/dev/null && VERR=1
[ "$VERR" -eq 1 ] \
  && ok "un verrou (flock / run-one) protège la tâche" \
  || ko "rien n'empêche deux exécutions simultanées (point 4) : \
flock -n /var/lock/... attendu"
if grep -q 'flock' "$CRND" 2>/dev/null; then
  grep -qE 'flock[^|]*-[a-zA-Z]*n' "$CRND" \
    && ok "flock en mode non bloquant (-n)" \
    || ko "flock sans -n : la seconde exécution attendrait au lieu \
d'échouer immédiatement (point 4)"
fi

# --- 4. journalisation -------------------------------------------------
JOURN=0
grep -qE 'logger' "$CRND" 2>/dev/null && JOURN=1
grep -qE 'logger|systemd-cat' "$SCRIPT" 2>/dev/null && JOURN=1
[ "$JOURN" -eq 1 ] \
  && ok "la sortie part vers le journal système (logger)" \
  || ko "la sortie ne part pas dans le journal : logger -t factura-sauv \
attendu (point 5)"
if grep -q '2>&1' "$CRND" 2>/dev/null || grep -q '2>&1' "$SCRIPT" 2>/dev/null
then
  ok "stderr est redirigé avec stdout (2>&1)"
else
  ko "stderr n'est pas capturé : sans 2>&1 les erreurs partent par mail ou \
se perdent"
fi
if grep -vE '^[[:space:]]*#' "$CRND" 2>/dev/null \
   | grep -qE '>[[:space:]]*/dev/null'; then
  ko "la sortie finit dans /dev/null : tu détruis la trace des échecs"
else
  ok "rien n'est jeté dans /dev/null"
fi

# --- 5. le résultat : une exécution réelle produit une archive --------
if [ -x "$SCRIPT" ]; then
  AVANT=$(ls -1 "$BACK" 2>/dev/null | wc -l)
  runuser -u factura -- env -i PATH=/usr/bin:/bin HOME=/srv/factura \
    SHELL=/bin/sh "$SCRIPT" >/tmp/.m17_02.out 2>&1
  RC=$?
  APRES=$(ls -1 "$BACK" 2>/dev/null | wc -l)
  [ "$RC" -eq 0 ] \
    && ok "exécution dans un environnement de type cron : code 0" \
    || ko "exécution en environnement cron : code $RC (voir \
/tmp/.m17_02.out) — c'est exactement ce que cron fera à 02:30"
  [ "$APRES" -gt "$AVANT" ] \
    && ok "une archive a été produite dans $BACK" \
    || ko "aucune nouvelle archive dans $BACK après exécution"

  # rétention : 7 archives max
  for i in 1 2 3 4 5 6 7 8 9; do
    touch -d "-$i day" "$BACK/factura-vieux-$i.tgz" 2>/dev/null
  done
  runuser -u factura -- env -i PATH=/usr/bin:/bin HOME=/srv/factura \
    "$SCRIPT" >/dev/null 2>&1
  N=$(ls -1 "$BACK" 2>/dev/null | wc -l)
  [ "$N" -le 8 ] \
    && ok "rétention appliquée ($N archives restantes)" \
    || ko "$N archives dans $BACK : la rétention à 7 n'est pas appliquée"
  rm -f "$BACK"/factura-vieux-*.tgz

  # --- 6. deux exécutions simultanées ---------------------------------
  A=$(ls -1 "$BACK" 2>/dev/null | wc -l)
  VERROU=$(grep -oE '/(var|run)/lock/[^ ]*' "$CRND" 2>/dev/null | head -1)
  VERROU="${VERROU:-/var/lock/factura-sauvegarde.lock}"
  ( flock -n "$VERROU" -c "sleep 4" ) &
  sleep 1
  runuser -u factura -- flock -n "$VERROU" -c "$SCRIPT" >/dev/null 2>&1
  RC2=$?
  wait
  [ "$RC2" -ne 0 ] \
    && ok "une seconde exécution est refusée pendant que le verrou est pris" \
    || ko "deux exécutions simultanées ont abouti : le verrou $VERROU n'est \
pas celui utilisé par la tâche"
  B=$(ls -1 "$BACK" 2>/dev/null | wc -l)
  [ "$B" -le $((A + 1)) ] \
    && ok "pas d'archive surnuméraire produite en concurrence" \
    || note "des archives supplémentaires sont apparues pendant le test"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
