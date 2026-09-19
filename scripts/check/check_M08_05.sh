#!/usr/bin/env bash
# check_M08_05.sh — vérifie le lab L8.5 (opérations longues en SSH)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L8.5 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab08/rapports/operations-longues.md"

# --- 1. la session tmux détachée ----------------------------------------
if command -v tmux >/dev/null 2>&1; then
  if sudo -u "$LAB_USER" tmux ls 2>/dev/null | grep -q '^migration:'; then
    ok "session tmux « migration » présente"
    sudo -u "$LAB_USER" tmux ls 2>/dev/null | grep '^migration:' \
      | grep -q 'attached' \
      && note "session attachée : l'énoncé demandait de s'en détacher" \
      || ok "la session est détachée"
  else
    ko "aucune session tmux nommée « migration » (tmux new -s migration)"
  fi
else
  ko "tmux n'est pas installé (voir §8.1)"
fi

# --- 2. l'unité transitoire a bien existé -------------------------------
if [ -d /run/systemd/system ]; then
  if systemctl list-units --all 'migration*' --no-legend 2>/dev/null \
     | grep -q migration; then
    note "l'unité transitoire migration est encore présente : \
systemctl stop migration, puis reset-failed si besoin"
  else
    ok "aucune unité transitoire migration résiduelle"
  fi
fi

# --- 3. le rapport comparatif -------------------------------------------
if [ -s "$RAP" ]; then
  L=$(grep -c . "$RAP")
  if [ "$L" -ge 10 ]; then
    ok "rapport operations-longues.md rédigé ($L lignes)"
  else
    ko "rapport trop court ($L lignes, 10 minimum)"
  fi
  MANQUE=""
  for mot in nohup tmux systemd-run SIGHUP; do
    grep -qi -- "$mot" "$RAP" || MANQUE="$MANQUE $mot"
  done
  if [ -z "$MANQUE" ]; then
    ok "les quatre méthodes et le signal en cause sont traités"
  else
    ko "le rapport ne parle pas de :$MANQUE (les quatre colonnes de \
l'étape 5 doivent y être)"
  fi
  grep -qi 'disown\|setsid' "$RAP" \
    || note "ni disown ni setsid ne sont cités : c'était la nuance de \
l'étape 2"
else
  ko "rapport absent : ~/lab08/rapports/operations-longues.md"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
