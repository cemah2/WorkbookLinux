#!/usr/bin/env bash
# check_M19_05.sh — vérifie le lab L19.5 (conduite d'incident, preuves,
#                   post-mortem, runbook)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L19.5 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BASE="$HOMEDIR/lab19"
JOURNAL="$BASE/rapports/INC-3355.md"
PREUVES="$BASE/bin/preuves.sh"
PM="$BASE/rapports/postmortem-INC-3355.md"

# --- 1. journal de bord --------------------------------------------------
if [ -s "$JOURNAL" ]; then
  ok "journal de bord présent"
  H=$(grep -cE '[0-2][0-9][:h][0-5][0-9]' "$JOURNAL")
  [ "$H" -ge 5 ] \
    && ok "$H horodatages dans le journal" \
    || ko "seulement $H horodatages : un journal d'incident date chaque \
action"
  grep -qiE 'hypoth|conclusion|d[ée]duit' "$JOURNAL" \
    && ok "le journal contient des hypothèses, pas seulement des commandes" \
    || ko "le journal doit tracer hypothèse -> test -> conclusion"
  grep -qiE 'r[ôo]le|responsable d.incident|communication' "$JOURNAL" \
    && ok "les rôles sont consignés" \
    || ko "les rôles (incident, technique, communication) ne sont pas écrits"
  grep -qiE 'T\+0|T\+15|T\+30|message' "$JOURNAL" \
    && ok "les messages de communication figurent" \
    || ko "les trois messages de la cadence 15 min sont absents"
  grep -qiE 'd[ée]cision|arbitr' "$JOURNAL" \
    && ok "l'arbitrage de T+20 est écrit" \
    || ko "la décision « rétablir ou creuser » n'est pas tracée"
else
  ko "journal absent : $JOURNAL"
fi

# --- 2. collecte de preuves ----------------------------------------------
if [ -s "$PREUVES" ]; then
  ok "preuves.sh présent"
  MANQUE=""
  for c in 'ps ' 'ss ' 'free' 'df ' 'dmesg' 'uptime' 'top' 'journalctl'; do
    grep -qF "$c" "$PREUVES" || MANQUE="$MANQUE ${c% }"
  done
  grep -qE 'df -i|df.*-i' "$PREUVES" || MANQUE="$MANQUE df-i"
  if [ -z "$MANQUE" ]; then
    ok "preuves.sh capture les huit familles d'information"
  else
    ko "captures absentes de preuves.sh :$MANQUE"
  fi
  grep -qE 'mktemp|/tmp|\$HOME|df |espace' "$PREUVES" \
    && ok "preuves.sh se préoccupe de l'endroit où il écrit" \
    || ko "preuves.sh doit prévoir le cas du disque plein (écrire ailleurs, \
ou vérifier l'espace avant)"
else
  ko "script absent : $PREUVES"
fi

D=$(ls -1d "$BASE"/preuves/*/ 2>/dev/null | wc -l)
if [ "$D" -ge 1 ]; then
  ok "$D répertoire(s) de preuves horodaté(s)"
  DERN=$(ls -1dt "$BASE"/preuves/*/ 2>/dev/null | head -1)
  N=$(ls -1 "$DERN" 2>/dev/null | wc -l)
  [ "$N" -ge 8 ] \
    && ok "la dernière collecte contient $N fichiers" \
    || ko "la dernière collecte ne contient que $N fichiers (8 minimum)"
else
  ko "aucune collecte dans $BASE/preuves/"
fi

# --- 3. post-mortem ------------------------------------------------------
if [ -s "$PM" ]; then
  ok "post-mortem présent"
  for s in 'Impact' 'Chronologie' 'Cause racine' 'Actions correctives'; do
    grep -qi "$s" "$PM" \
      && ok "section « $s » remplie" \
      || ko "section « $s » absente du post-mortem"
  done
  P=$(grep -ciE '^[[:space:]]*[1-5][.)] *pourquoi|parce que' "$PM")
  [ "$P" -ge 5 ] \
    && ok "les cinq pourquoi sont déroulés" \
    || ko "seulement $P niveau(x) de « pourquoi » : va jusqu'à la cause \
systémique"
  grep -qi 'pr[ée]vention' "$PM" \
    && ok "une action de prévention est proposée" \
    || ko "aucune action de prévention"
  grep -qi 'd[ée]tection' "$PM" \
    && ok "une action de détection est proposée" \
    || ko "aucune action de détection (comment le saura-t-on plus tôt ?)"
  grep -qE '20[0-9]{2}-[0-9]{2}-[0-9]{2}|/20[0-9]{2}|[0-9]{2}/[0-9]{2}' "$PM" \
    && ok "les actions sont datées" \
    || ko "les actions correctives n'ont pas d'échéance"
  grep -qiE 'faute|coupable|aurait d[ûu] faire attention' "$PM" \
    && ko "formulation accusatoire détectée : un post-mortem est blameless" \
    || ok "aucune formulation accusatoire détectée"
  grep -qi 'XXXX' "$PM" \
    && ko "le modèle n'a pas été complété (il reste des XXXX)" \
    || ok "le modèle est complété"
else
  ko "post-mortem absent : $PM"
fi

# --- 4. runbook et retour au vert ---------------------------------------
R=$(ls -1 "$BASE"/rapports/runbook-*.md 2>/dev/null | wc -l)
[ "$R" -ge 1 ] \
  && ok "$R runbook(s) rédigé(s)" \
  || ko "aucun runbook-<panne>.md dans $BASE/rapports/"

if [ -d /run/systemd/system ]; then
  [ "$(systemctl is-active vitrine-api 2>/dev/null)" = active ] \
    && ok "vitrine-api est de nouveau actif" \
    || ko "vitrine-api n'est pas actif : l'incident n'est pas clos"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
