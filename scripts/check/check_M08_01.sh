#!/usr/bin/env bash
# check_M08_01.sh — vérifie le lab L8.1 (triage d'une machine qui rame)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L8.1 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab08/rapports/inc-3187.md"

# --- 1. les processus de charge tournent et sont dépriorisés -------------
# pgrep -f attrape le script ET ses sous-shells : ils partagent la même
# ligne de commande. Tous doivent avoir été dépriorisés.
CHARGE_PIDS=$(pgrep -f 'factura-charge.sh' 2>/dev/null | tr '\n' ' ')
if [ -n "$CHARGE_PIDS" ]; then
  ok "factura-charge.sh tourne (pid : $CHARGE_PIDS)"
  TROP_HAUT=0
  for p in $CHARGE_PIDS; do
    ni=$(ps -o ni= -p "$p" 2>/dev/null | tr -d ' ')
    [ -n "$ni" ] || continue
    [ "$ni" -gt 0 ] 2>/dev/null || TROP_HAUT=1
  done
  if [ "$TROP_HAUT" -eq 0 ]; then
    ok "tous les processus de charge ont un nice strictement positif"
  else
    ko "au moins un processus de charge est encore à nice 0 ou moins \
(renice -n 15 -p <pid>, vérifie aussi les processus fils)"
  fi
else
  ko "aucun factura-charge.sh en cours : relance-le avant le contrôle \
(/opt/factura/bin/factura-charge.sh 2 &)"
fi

# --- 2. l'ogre mémoire est désigné volontaire pour l'OOM killer ---------
GPID=$(pgrep -f 'factura-gourmand.py' 2>/dev/null | head -1)
if [ -n "$GPID" ]; then
  ADJ=$(cat "/proc/$GPID/oom_score_adj" 2>/dev/null || echo 0)
  if [ "$ADJ" -gt 500 ] 2>/dev/null; then
    ok "oom_score_adj de factura-gourmand.py = $ADJ (> 500)"
  else
    ko "oom_score_adj = $ADJ : il doit dépasser 500 pour être tué en \
premier (échelle -1000 à 1000, écris dans /proc/<pid>/oom_score_adj)"
  fi
else
  ko "factura-gourmand.py ne tourne pas : relance-le avant le contrôle"
fi

# --- 3. le rapport d'incident ------------------------------------------
if [ -s "$RAP" ]; then
  L=$(grep -c . "$RAP")
  if [ "$L" -ge 12 ]; then
    ok "rapport inc-3187.md rédigé ($L lignes)"
  else
    ko "rapport inc-3187.md trop court ($L lignes, 12 minimum)"
  fi
  for mot in load nice oom; do
    grep -qi "$mot" "$RAP" || \
      note "le rapport ne parle pas de « $mot » : est-il complet ?"
  done
else
  ko "rapport absent : ~/lab08/rapports/inc-3187.md"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
