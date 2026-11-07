#!/usr/bin/env bash
# check_M31_04.sh — vérifie le lab L31.4 (sondes bpftrace maison)
# À lancer avec sudo sur lab-web.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L31.4 =="
[ "$(id -u)" -eq 0 ] || { ko "à lancer avec sudo"; fin; }
H=$(getent passwd "${SUDO_USER:-mathieu}" | cut -d: -f6)/lab31
command -v bpftrace >/dev/null || { ko "bpftrace absent"; fin; }

charge() {
  if bpftrace --help 2>&1 | grep -q -- '--dry-run'; then
    timeout 30 bpftrace --dry-run "$@" >/dev/null 2>&1
  else
    timeout -s INT 4 bpftrace "$@" >/dev/null 2>&1; [ $? -ne 1 ]
  fi
}

for s in latence-open processus-courts compte-naif; do
  f="$H/$s.bt"
  if [ ! -s "$f" ]; then ko "lab31/$s.bt absent"; continue; fi
  case "$s" in
    latence-open) charge "$f" sshd ;;
    *)            charge "$f" ;;
  esac && ok "$s.bt se charge sans erreur" || ko "$s.bt ne se charge pas (bpftrace $f)"
  head -15 "$f" | grep -Eqi 'surco(u|û)t' && ok "$s.bt documente son surcoût" \
                                       || ko "$s.bt : pas de ligne « Surcoût » en tête"
done
grep -qs 'hist(' "$H/latence-open.bt" && grep -qs 'interval:s:10' "$H/latence-open.bt" \
  && ok "latence-open : histogramme toutes les 10 s" || ko "latence-open : hist() + interval:s:10 attendus"
grep -qs 'uretprobe:' "$H/compte-naif.bt" && ok "compte-naif : uprobe + uretprobe" \
                                         || ko "compte-naif : pas de uretprobe"
grep -Eqs 'sched_process_(exec|exit)|execve' "$H/processus-courts.bt" \
  && ok "processus-courts : suit la vie des processus" || ko "processus-courts : sondes exec/exit attendues"
fin
