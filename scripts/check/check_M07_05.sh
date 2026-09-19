#!/usr/bin/env bash
# check_M07_05.sh — vérifie le défi D7 (sauvegarde.sh de qualité production)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D7 =="

S="$HOME/lab07/bin/sauvegarde.sh"
SRC="$HOME/lab07/depot"
LOCK="$HOME/lab07/var/run/sauvegarde.lock"
STAMP=$(date +%F)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
DEST="$TMP/archives"
RAPPORTS="$HOME/lab07/rapports"
mkdir -p "$DEST"

if [ ! -f "$S" ]; then
  ko "$S est absent"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi
ok "le script existe"
[ -x "$S" ] && ok "le script est exécutable" \
            || ko "il manque le bit d'exécution (chmod +x)"
[ -d "$SRC" ] || { ko "$SRC absent : relance setup_M07.sh"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

compte_tmp() { find /tmp -maxdepth 1 -user "$(id -un)" -type d \
                 -name 'sauvegarde.*' 2>/dev/null | wc -l; }
AVANT=$(compte_tmp)

# --- 1. interface --------------------------------------------------------
"$S" --help > "$TMP/aide" 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -qi 'usage' "$TMP/aide"; then
  ok "--help affiche l'usage et sort en 0"
else
  ko "--help : usage sur stdout et code 0 attendus (obtenu $rc)"
fi
if grep -qE '(^|[^0-9])9([^0-9]|$)' "$TMP/aide" && \
   grep -qiE 'code' "$TMP/aide"; then
  ok "l'aide documente les codes de sortie"
else
  ko "l'aide doit lister les codes de sortie (0,1,2,3,9)"
fi

"$S" --pas-une-option >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "option inconnue -> code 2" \
                || ko "option inconnue : code 2 attendu, obtenu $rc"

"$S" --source "$TMP/nexistepas" --dest "$DEST" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ] && ok "source introuvable -> code 3" \
                || ko "source introuvable : code 3 attendu, obtenu $rc"

"$S" --retention abc --dest "$DEST" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "rétention non numérique -> code 2" \
                || ko "rétention « abc » : code 2 attendu, obtenu $rc"

# --- 2. dry-run ----------------------------------------------------------
"$S" --source "$SRC" --dest "$DEST" --dry-run >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "--dry-run sort en 0" \
                || ko "--dry-run : code 0 attendu, obtenu $rc"
if [ -z "$(ls -A "$DEST" 2>/dev/null)" ]; then
  ok "--dry-run n'écrit rien dans la destination"
else
  ko "--dry-run a écrit dans $DEST : il doit être sans effet"
fi

# --- 3. jeu de rétention -------------------------------------------------
printf 'vieille\n' > "$DEST/factura-2026-01-01.tar.gz"
touch -d '40 days ago' "$DEST/factura-2026-01-01.tar.gz"
printf 'recente\n' > "$DEST/factura-2026-09-16.tar.gz"
touch -d '2 days ago' "$DEST/factura-2026-09-16.tar.gz"
printf 'etranger\n' > "$DEST/export final.tar.gz"
touch -d '90 days ago' "$DEST/export final.tar.gz"

"$S" --source "$SRC" --dest "$DEST" --retention 7 >"$TMP/out" 2>"$TMP/err"
rc=$?
[ "$rc" -eq 0 ] && ok "sauvegarde nominale -> code 0" \
                || ko "code 0 attendu, obtenu $rc (voir stderr)"

ARCHIVE="$DEST/factura-$STAMP.tar.gz"
if [ -s "$ARCHIVE" ]; then
  ok "archive datée produite : factura-$STAMP.tar.gz"
else
  ko "aucune archive $ARCHIVE"
fi
if tar -tzf "$ARCHIVE" >/dev/null 2>&1; then
  ok "l'archive est relisible (tar -tzf)"
else
  ko "archive illisible : vérifie-la avant de la publier"
fi
if tar -tzf "$ARCHIVE" 2>/dev/null | grep -q 'app.conf'; then
  ok "le contenu du dépôt est bien dans l'archive"
else
  ko "etc/app.conf absent de l'archive"
fi

[ ! -e "$DEST/factura-2026-01-01.tar.gz" ] \
  && ok "l'archive de 40 jours est purgée" \
  || ko "l'archive de 40 jours survit à une rétention de 7 jours"
[ -e "$DEST/factura-2026-09-16.tar.gz" ] \
  && ok "l'archive de 2 jours est conservée" \
  || ko "l'archive de 2 jours a été purgée à tort"
[ -e "$DEST/export final.tar.gz" ] \
  && ok "les fichiers hors motif factura-*.tar.gz sont épargnés" \
  || ko "« export final.tar.gz » a été supprimé : ton motif de purge \
est trop large"

# --- 4. journalisation et rapport ---------------------------------------
if [ -s "$TMP/err" ]; then
  ok "le journal de service part sur stderr"
else
  ko "rien sur stderr : log_info/log_error doivent y écrire"
fi
if grep -Eq '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' \
     "$TMP/err"; then
  ok "les lignes de journal sont horodatées"
else
  ko "horodatage ISO attendu sur les lignes de journal"
fi

RAPPORT=$(find "$RAPPORTS" -maxdepth 1 -name "sauvegarde-$STAMP.*" \
            -newermt '-10 minutes' 2>/dev/null | head -1)
if [ -n "$RAPPORT" ] && [ -s "$RAPPORT" ]; then
  ok "un rapport daté est écrit dans ~/lab07/rapports"
  grep -qiE 'r[ée]tention' "$RAPPORT" \
    && ok "le rapport mentionne la rétention appliquée" \
    || ko "le rapport doit indiquer la rétention appliquée"
else
  ko "aucun rapport ~/lab07/rapports/sauvegarde-$STAMP.md récent"
fi

# --- 5. idempotence, verrou, nettoyage ----------------------------------
"$S" --source "$SRC" --dest "$DEST" --retention 7 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "seconde exécution -> code 0 (idempotent)" \
                || ko "la seconde exécution échoue (code $rc)"

if [ ! -e "$LOCK" ]; then
  ko "le verrou $LOCK n'existe pas (flock)"
else
  (
    exec 9>"$LOCK"
    if flock -n 9; then
      "$S" --source "$SRC" --dest "$DEST" >/dev/null 2>&1; exit $?
    fi
    exit 100
  )
  rcv=$?
  case "$rcv" in
    9)   ok "verrou déjà pris -> code 9" ;;
    100) ko "impossible de prendre le verrou pour le test" ;;
    *)   ko "verrou déjà pris : code 9 attendu, obtenu $rcv" ;;
  esac
fi

APRES=$(compte_tmp)
[ "$APRES" -le "$AVANT" ] \
  && ok "aucun espace de travail abandonné dans /tmp" \
  || ko "$((APRES - AVANT)) répertoire(s) /tmp/sauvegarde.* laissé(s) derrière"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x "$S" >/dev/null 2>&1 \
    && ok "shellcheck ne signale rien" \
    || ko "shellcheck remonte des avertissements : shellcheck $S"
else
  note "shellcheck n'est pas installé (sudo apt install -y shellcheck)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
