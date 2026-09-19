#!/usr/bin/env bash
# check_M19_01.sh — vérifie le lab L19.1 (triage des 60 secondes)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L19.1 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BASE="$HOMEDIR/lab19"
SCRIPT="$BASE/bin/triage.sh"
RAP="$BASE/rapports/triage.md"

# --- 1. le script existe et tourne vite ---------------------------------
if [ -s "$SCRIPT" ]; then
  ok "triage.sh présent"
  T0=$(date +%s)
  if timeout 45 bash "$SCRIPT" >/tmp/triage-check.$$ 2>&1; then
    T1=$(date +%s)
    D=$((T1 - T0))
    if [ "$D" -le 30 ]; then
      ok "triage.sh s'exécute en ${D}s (limite : 30 s)"
    else
      ko "triage.sh met ${D}s : trop long pour un triage (vmstat 1 5, pas \
vmstat 1 60)"
    fi
  else
    ko "triage.sh sort en erreur ou dépasse 45 s"
  fi
  rm -f /tmp/triage-check.$$

  # contenu : la checklist doit être complète
  MANQUE=""
  for c in uptime vmstat free dmesg top; do
    grep -qE "(^|[^[:alnum:]_])$c" "$SCRIPT" || MANQUE="$MANQUE $c"
  done
  grep -qE 'iostat|/proc/diskstats' "$SCRIPT" || MANQUE="$MANQUE iostat"
  grep -qE 'mpstat|pidstat|ps ' "$SCRIPT"     || MANQUE="$MANQUE mpstat/pidstat"
  grep -qE '\bss\b|netstat|sar -n' "$SCRIPT"  || MANQUE="$MANQUE ss"
  if [ -z "$MANQUE" ]; then
    ok "la checklist couvre CPU, mémoire, disque, réseau et noyau"
  else
    ko "commandes absentes de triage.sh :$MANQUE (revois §19.2)"
  fi

  grep -qE 'systemctl (restart|stop)|kill |reboot' "$SCRIPT" \
    && ko "triage.sh modifie l'état de la machine : un triage observe, \
il ne répare pas" \
    || ok "triage.sh ne modifie rien sur la machine"
else
  ko "script absent : $SCRIPT"
fi

# --- 2. le rapport horodaté ---------------------------------------------
N=$(ls -1 "$BASE"/rapports/triage-*.txt 2>/dev/null | wc -l)
if [ "$N" -ge 1 ]; then
  ok "$N rapport(s) horodaté(s) dans $BASE/rapports/"
  DERNIER=$(ls -1t "$BASE"/rapports/triage-*.txt 2>/dev/null | head -1)
  if [ "$(wc -l < "$DERNIER")" -ge 25 ]; then
    ok "le dernier rapport contient des sorties réelles"
  else
    ko "le rapport $DERNIER est trop court : les sorties ne sont pas \
capturées (redirection oubliée ?)"
  fi
else
  ko "aucun rapport triage-<date>.txt : le script doit écrire sa sortie"
fi

# --- 3. la conclusion écrite --------------------------------------------
if [ -s "$RAP" ]; then
  ok "triage.md présent"
  [ "$(grep -c '[^[:space:]]' "$RAP")" -ge 12 ] \
    && ok "triage.md est étoffé" \
    || ko "triage.md fait moins de 12 lignes utiles : symptôme, ressource, \
trois preuves, hypothèse suivante"
  grep -qiE 'cpu|m[ée]moire|disque|r[ée]seau' "$RAP" \
    && ok "une ressource est désignée" \
    || ko "triage.md ne désigne aucune ressource en cause"
  grep -qiE 'hypoth[èe]se' "$RAP" \
    && ok "l'hypothèse suivante est formulée" \
    || ko "triage.md ne formule pas l'hypothèse à tester ensuite"
  grep -qE '[0-9]+[.,][0-9]+|load average|%[a-z]{2}' "$RAP" \
    && ok "des valeurs mesurées sont recopiées" \
    || ko "aucun chiffre dans triage.md : recopie les lignes de sortie qui \
t'ont fait conclure"
else
  ko "rapport absent : $RAP"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
