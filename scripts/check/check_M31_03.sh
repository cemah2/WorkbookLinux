#!/usr/bin/env bash
# check_M31_03.sh — vérifie le lab L31.3 (analyse hors CPU)
# À lancer avec sudo sur lab-web.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L31.3 =="
[ "$(id -u)" -eq 0 ] || { ko "à lancer avec sudo"; fin; }
H=$(getent passwd "${SUDO_USER:-mathieu}" | cut -d: -f6)/lab31

command -v offcputime-bpfcc >/dev/null && ok "outils BCC présents" \
                                      || ko "offcputime-bpfcc absent (apt install bpfcc-tools)"
F="$H/offcpu.svg"
if [ -s "$F" ] && grep -q '<svg' "$F"; then
  ok "flame graph hors CPU présent"
  grep -q 'fsync' "$F" && ok "il montre la pile de fsync" \
                       || ko "fsync n'apparaît pas dans offcpu.svg : mauvais processus, ou profil sur CPU ?"
else
  ko "lab31/offcpu.svg absent ou invalide"
fi

P=$(pgrep -xo lab31-journal || true)
if [ -n "$P" ]; then
  arg=$(tr '\0' ' ' < "/proc/$P/cmdline")
  ok "lab31-journal tourne : $arg"
  note "valeur de --groupe retenue : $(grep -oE -- '--groupe [0-9]+' <<<"$arg" || echo 'défaut (1)')"
else
  ko "lab31-journal ne tourne pas avec la valeur choisie (étape 6)"
fi

R="$H/rapport-offcpu.md"
if [ -s "$R" ]; then
  ok "rapport-offcpu.md présent"
  grep -qi 'durab\|perd\|coupure' "$R" && ok "le rapport traite le risque de perte" \
                                       || ko "le rapport ne parle pas de durabilité / de perte"
  grep -Eq '\b(10|100)\b' "$R" && ok "le rapport compare plusieurs valeurs de --groupe" \
                                || ko "pas de comparaison chiffrée de --groupe"
else
  ko "lab31/rapport-offcpu.md absent"
fi
fin
