#!/usr/bin/env bash
# check_M31_02.sh — vérifie le lab L31.2 (appels système, bpftrace)
# À lancer avec sudo sur lab-web.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L31.2 =="
[ "$(id -u)" -eq 0 ] || { ko "à lancer avec sudo"; fin; }
H=$(getent passwd "${SUDO_USER:-mathieu}" | cut -d: -f6)/lab31
command -v bpftrace >/dev/null || { ko "bpftrace absent"; fin; }

# charge un script bpftrace sans le laisser tourner
charge() {
  if bpftrace --help 2>&1 | grep -q -- '--dry-run'; then
    timeout 30 bpftrace --dry-run "$@" >/dev/null 2>&1
  else
    timeout -s INT 4 bpftrace "$@" >/dev/null 2>&1; [ $? -ne 1 ]
  fi
}

S="$H/ecritures.bt"
if [ -s "$S" ]; then
  ok "ecritures.bt présent"
  charge "$S" && ok "ecritures.bt se charge sans erreur" || ko "ecritures.bt ne se charge pas (bpftrace $S)"
  grep -q 'interval:s:5' "$S" && ok "affichage toutes les 5 s" || ko "pas de sonde interval:s:5"
  grep -Eq 'sys_(enter|exit)_write' "$S" && ok "s'appuie sur les tracepoints de write" \
                                        || ko "pas de tracepoint syscalls:sys_*_write"
  grep -q 'sum(' "$S" && ok "cumule les volumes écrits" || ko "pas de sum() pour le volume"
else
  ko "lab31/ecritures.bt absent"
fi

R="$H/rapport-syscalls.md"
if [ -s "$R" ]; then
  ok "rapport-syscalls.md présent"
  grep -qi 'strace' "$R" && grep -qi 'perf trace\|bpftrace' "$R" \
    && ok "le rapport compare strace et un outil léger" || ko "le rapport ne compare pas les outils"
  grep -Eq '65536|4096' "$R" && ok "le rapport donne les mesures par taille de tampon" \
                              || ko "le rapport ne donne pas les mesures de l'étape 5"
else
  ko "lab31/rapport-syscalls.md absent"
fi
fin
