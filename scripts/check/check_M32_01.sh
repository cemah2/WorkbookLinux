#!/usr/bin/env bash
# check_M32_01.sh — vérifie le lab L32.1 (corruption silencieuse, écriture atomique)
# À lancer avec sudo sur lab-db.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L32.1 =="
[ "$(id -u)" -eq 0 ] || { ko "à lancer avec sudo"; fin; }
H=$(getent passwd "${SUDO_USER:-mathieu}" | cut -d: -f6)/lab32

R="$H/corruption.md"
if [ -s "$R" ]; then
  ok "corruption.md présent"
  grep -qi 'sha' "$R" && ok "le rapport compare des empreintes" || ko "pas d'empreinte (SHA-256) dans le rapport"
  grep -qi 'e2fsck' "$R" && ok "le rapport cite e2fsck" || ko "le rapport ne dit pas ce qu'a répondu e2fsck"
  grep -qiE 'aucune erreur|sans erreur|silencieu' "$R" && ok "le rapport constate l'absence d'erreur" \
                                                    || ko "le rapport ne conclut pas à une corruption silencieuse"
else
  ko "lab32/corruption.md absent"
fi

S=$(ls "$H"/sauve-etat-corrige* 2>/dev/null | head -1)
if [ -z "$S" ]; then ko "lab32/sauve-etat-corrige.* absent"; fin; fi
ok "script corrigé : $(basename "$S")"
grep -Eq 'fsync|(^|[^a-z])sync ' "$S" && ok "il synchronise" || ko "aucun fsync / sync"
grep -Eq 'rename|replace|(^|[^a-z])mv ' "$S" && ok "il renomme un fichier temporaire" \
                                           || ko "pas de renommage (écriture en place ?)"
grep -Eq 'O_DIRECTORY|sync +"?\$\(dirname|sync +"?\$\{?[a-z_]*rep|sync +"?\$\{f%/\*\}' "$S" \
  && ok "il synchronise le répertoire" || ko "pas de fsync du répertoire après le renommage"

if command -v strace >/dev/null; then
  case "$S" in *.py) runner=python3 ;; *) head -1 "$S" | grep -q python && runner=python3 || runner=bash ;; esac
  T=$(strace -f -e trace=fsync,fdatasync,rename,renameat,renameat2 "$runner" "$S" verification 2>&1 >/dev/null)
  ordre=$(grep -oE '^(\[pid +[0-9]+\] )?(fsync|fdatasync|rename|renameat2?)' <<<"$T" | sed 's/.*\] //' | paste -sd' ' -)
  case "$ordre" in
    *sync*" "*rename*" "*sync*) ok "ordre des appels : $ordre" ;;
    "") ko "aucun appel fsync/rename observé à l'exécution" ;;
    *)  ko "ordre des appels incorrect : $ordre (attendu : fsync, rename, fsync)" ;;
  esac
else
  note "strace absent : ordre des appels non vérifié (apt install strace)"
fi
fin
