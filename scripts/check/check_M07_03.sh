#!/usr/bin/env bash
# check_M07_03.sh — vérifie le lab L7.3 (collecte.sh : verrou, trap, mktemp)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L7.3 =="

S="$HOME/lab07/bin/collecte.sh"
LOGS="$HOME/lab07/logs"
DEST="$HOME/lab07/archives"
LOCK="$HOME/lab07/var/run/collecte.lock"
STAMP=$(date +%F)
ARCHIVE="$DEST/collecte-$STAMP.tar.gz"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

if [ ! -f "$S" ]; then
  ko "$S est absent"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi
ok "le script existe"
[ -x "$S" ] && ok "le script est exécutable" \
            || ko "il manque le bit d'exécution (chmod +x)"

compte_tmp() { find /tmp -maxdepth 1 -user "$(id -un)" -type d \
                 -name 'collecte.*' 2>/dev/null | wc -l; }

AVANT=$(compte_tmp)

# --- 1. dry-run ne modifie rien -----------------------------------------
rm -f "$ARCHIVE"
"$S" --dry-run >/dev/null 2>"$TMP/dry.err"; rc=$?
[ "$rc" -eq 0 ] && ok "--dry-run sort en 0" \
                || ko "--dry-run doit sortir en 0, obtenu $rc"
[ ! -e "$ARCHIVE" ] && ok "--dry-run n'a produit aucune archive" \
                    || ko "--dry-run a créé $ARCHIVE : il ne doit rien écrire"

# --- 2. exécution nominale ----------------------------------------------
"$S" >/dev/null 2>"$TMP/run.err"; rc=$?
[ "$rc" -eq 0 ] && ok "exécution nominale -> code 0" \
                || ko "code 0 attendu, obtenu $rc (voir la sortie stderr)"

if [ -s "$ARCHIVE" ]; then
  ok "archive produite : collecte-$STAMP.tar.gz"
else
  ko "aucune archive $ARCHIVE"
fi

if tar -tzf "$ARCHIVE" 2>/dev/null | grep -q 'rapport final.log'; then
  ok "le journal au nom à espace est dans l'archive"
else
  ko "« rapport final.log » manque dans l'archive (find -print0 / read -d '')"
fi

NB_ARCH=$(tar -tzf "$ARCHIVE" 2>/dev/null | grep -c '\.log$')
NB_SRC=$(find "$LOGS" -maxdepth 1 -type f -name '*.log' | wc -l)
if [ "$NB_ARCH" -eq "$NB_SRC" ]; then
  ok "les $NB_SRC journaux sont archivés"
else
  ko "$NB_SRC journaux attendus dans l'archive, $NB_ARCH trouvés"
fi

# --- 3. idempotence ------------------------------------------------------
"$S" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "seconde exécution -> code 0 (idempotent)" \
                || ko "la seconde exécution échoue (code $rc)"

# --- 4. source absente : code 3 ET nettoyage ----------------------------
"$S" --source "$TMP/nexistepas" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ] && ok "source introuvable -> code 3" \
                || ko "source introuvable : code 3 attendu, obtenu $rc"

# --- 5. option inconnue --------------------------------------------------
"$S" --nimportequoi >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "option inconnue -> code 2" \
                || ko "option inconnue : code 2 attendu, obtenu $rc"

# --- 6. aucun espace de travail abandonné -------------------------------
APRES=$(compte_tmp)
if [ "$APRES" -le "$AVANT" ]; then
  ok "aucun répertoire de travail abandonné dans /tmp (trap EXIT)"
else
  ko "$((APRES - AVANT)) répertoire(s) /tmp/collecte.* laissé(s) derrière : \
le trap EXIT ne nettoie pas dans tous les chemins de sortie"
fi

# --- 7. verrou : on le prend, le script doit refuser de tourner ---------
if [ ! -e "$LOCK" ]; then
  ko "le verrou $LOCK n'existe pas : le script doit l'ouvrir (flock)"
else
  ok "le fichier de verrou attendu existe"
  (
    exec 9>"$LOCK"
    if flock -n 9; then
      "$S" >/dev/null 2>&1; rc2=$?
      [ "$rc2" -eq 9 ] && exit 0 || exit "$rc2"
    else
      exit 100
    fi
  )
  rcv=$?
  case "$rcv" in
    0)   ok "verrou déjà pris -> le script sort en 9 sans travailler" ;;
    100) ko "impossible de prendre le verrou pour le test" ;;
    *)   ko "verrou déjà pris : code 9 attendu, obtenu $rcv (flock -n)" ;;
  esac
fi

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "$S" >/dev/null 2>&1 \
    && ok "shellcheck ne signale rien" \
    || ko "shellcheck remonte des avertissements : shellcheck $S"
else
  note "shellcheck n'est pas installé (sudo apt install -y shellcheck)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
