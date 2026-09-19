#!/usr/bin/env bash
# check_M01_02.sh — vérifie le lab L1.2 (wrapper de journalisation)
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification L1.2 =="

WRAP="$HOME/lab01/bin/sauvegarde-wrap.sh"
LOG="$HOME/lab01/logs/sauvegarde.log"

if [ -x "$WRAP" ]; then
  ok "$WRAP existe et est exécutable"
else
  ko "wrapper absent ou non exécutable (chmod +x)"
  echo "Résultat : $PASS réussis, $FAIL échoués"
  exit 1
fi

taille_avant=0
[ -f "$LOG" ] && taille_avant=$(stat -c %s "$LOG")

# --- 1. exécution en échec forcé ----------------------------------------
sortie=$(FORCER_ECHEC=1 "$WRAP" 2>&1); code=$?

if [ "$code" -eq 3 ]; then
  ok "le code retour du script appelé (3) est préservé"
else
  ko "code retour = $code au lieu de 3 (regarde \${PIPESTATUS[0]})"
fi

if printf '%s' "$sortie" | grep -q '\[info\]' &&
   printf '%s' "$sortie" | grep -q '\[erreur\]'; then
  ok "les deux flux sont visibles à l'écran en mode normal"
else
  ko "stdout et stderr ne sont pas tous deux affichés"
fi

# --- 2. contenu du journal ----------------------------------------------
if [ -f "$LOG" ]; then
  ok "le journal $LOG existe"
else
  ko "journal absent : ~/lab01/logs/sauvegarde.log"
fi

if grep -q '\[info\]' "$LOG" 2>/dev/null &&
   grep -q '\[erreur\]' "$LOG" 2>/dev/null; then
  ok "le journal contient stdout ET stderr"
else
  ko "le journal ne contient pas les deux flux (2>&1 avant le tube)"
fi

if grep -qE '=== .* (début|debut) ===' "$LOG" 2>/dev/null; then
  ok "chaque exécution est précédée d'une ligne de début horodatée"
else
  ko "ligne '=== <date> début ===' absente du journal"
fi

taille_apres=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
if [ "$taille_apres" -gt "$taille_avant" ]; then
  ok "le journal est ouvert en ajout, pas en écrasement"
else
  ko "le journal a rétréci : utilise tee -a et >> au lieu de > "
fi

# --- 3. mode silencieux --------------------------------------------------
avant=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
vis=$(SILENCIEUX=1 FORCER_ECHEC=0 "$WRAP" 2>&1); code=$?
apres=$(stat -c %s "$LOG" 2>/dev/null || echo 0)

if [ -z "$vis" ]; then
  ok "SILENCIEUX=1 n'affiche rien sur le terminal"
else
  ko "SILENCIEUX=1 affiche encore : ${vis:0:40}"
fi

if [ "$apres" -gt "$avant" ]; then
  ok "SILENCIEUX=1 journalise quand même dans le fichier"
else
  ko "en mode silencieux, rien n'est écrit dans le journal"
fi

if [ "$code" -eq 0 ]; then
  ok "le code retour 0 est également préservé"
else
  ko "code retour = $code au lieu de 0 sur une exécution réussie"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
