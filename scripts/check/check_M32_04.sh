#!/usr/bin/env bash
# check_M32_04.sh — vérifie le lab L32.4 (banc d'essai fio)
# À lancer avec sudo sur lab-db.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L32.4 =="
[ "$(id -u)" -eq 0 ] || { ko "à lancer avec sudo"; fin; }
H=$(getent passwd "${SUDO_USER:-mathieu}" | cut -d: -f6)/lab32

S="$H/banc.sh"
if [ -f "$S" ]; then
  ok "banc.sh présent"
  bash -n "$S" && ok "banc.sh : syntaxe correcte" || ko "banc.sh : erreur de syntaxe"
  grep -q 'fio' "$S" && ok "utilise fio" || ko "n'utilise pas fio"
  grep -Eq -- '--direct=1|direct=1' "$S" && ok "caches contournés (direct=1)" || ko "pas de direct=1"
  grep -Eq -- '--fsync=1|fsync=1|--sync=1' "$S" && ok "charge base : écritures synchronisées" \
                                               || ko "la charge base ne synchronise pas ses écritures"
  grep -Eq -- 'bs=8k|bs=8K' "$S" && grep -Eq -- 'bs=1M|bs=1m' "$S" \
    && ok "les deux tailles de bloc (8 Kio, 1 Mio)" || ko "tailles de bloc 8k et 1M attendues"
else
  ko "lab32/banc.sh absent"
fi

n=0
for fs in ext4 xfs btrfs zfs; do
  c=$(ls "$H"/banc/"$fs"*-base-*.json 2>/dev/null | wc -l)
  [ "$c" -ge 3 ] && n=$((n + 1)) || ko "$fs : $c passage(s) base (3 attendus)"
done
[ "$n" -eq 4 ] && ok "quatre systèmes de fichiers mesurés trois fois"

R="$H/banc.md"
if [ -s "$R" ]; then
  ok "banc.md présent"
  for fs in ext4 XFS Btrfs ZFS; do grep -qi "$fs" "$R" || ko "banc.md ne parle pas de $fs"; done
  grep -qi 'p99' "$R" && ok "banc.md donne la latence p99" || ko "pas de p99 dans banc.md"
  grep -qi 'limite' "$R" && ok "banc.md contient une section sur les limites" || ko "pas de section « limites »"
else
  ko "lab32/banc.md absent"
fi
fin
