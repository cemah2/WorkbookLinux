#!/usr/bin/env bash
# check_M31_01.sh — vérifie le lab L31.1 (profil CPU, flame graphs)
# À lancer avec sudo sur lab-web.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L31.1 =="
[ "$(id -u)" -eq 0 ] || { ko "à lancer avec sudo"; fin; }
H=$(getent passwd "${SUDO_USER:-mathieu}" | cut -d: -f6)/lab31

command -v perf >/dev/null && ok "perf installé ($(perf --version 2>/dev/null))" \
                           || ko "perf absent : apt install linux-tools-\$(uname -r)"

for f in cpu-naif cpu-rapide; do
  if [ -s "$H/$f.svg" ] && grep -q '<svg' "$H/$f.svg"; then
    ok "flame graph $f.svg présent"
  else
    ko "lab31/$f.svg absent ou invalide"
  fi
done
grep -q 'compte_naif' "$H/cpu-naif.svg" 2>/dev/null \
  && ok "cpu-naif.svg montre compte_naif" \
  || ko "compte_naif n'apparaît pas dans cpu-naif.svg (symboles ? bon processus ?)"
if [ -s "$H/cpu-rapide.svg" ]; then
  grep -q 'compte_naif' "$H/cpu-rapide.svg" \
    && ko "cpu-rapide.svg contient encore compte_naif : profil pris avant le correctif ?" \
    || ok "cpu-rapide.svg ne contient plus compte_naif"
  grep -qi 'memmem' "$H/cpu-rapide.svg" && ok "le temps est désormais dans memmem (glibc)" \
                                         || note "memmem absent du profil rapide (symboles de la glibc ?)"
fi

E=$(systemctl show -p ExecStart --value lab31-calcul 2>/dev/null)
grep -q -- '--rapide' <<<"$E" && ok "le service tourne avec --rapide" \
                              || ko "lab31-calcul.service n'utilise pas --rapide (systemctl edit)"
systemctl is-active -q lab31-calcul && note "lab31-calcul tourne : pense à l'arrêter après le module" \
                                    || true

R="$H/rapport-cpu.md"
if [ -s "$R" ]; then
  ok "rapport-cpu.md présent"
  grep -Eq '[0-9]+([.,][0-9]+)? *passes' "$R" && ok "le rapport chiffre le débit" \
                                              || ko "le rapport ne donne pas les débits (passes/s)"
  grep -qi 'ipc\|insn per cycle' "$R" && ok "le rapport parle de l'IPC" || ko "le rapport ne donne pas l'IPC"
else
  ko "lab31/rapport-cpu.md absent"
fi
fin
