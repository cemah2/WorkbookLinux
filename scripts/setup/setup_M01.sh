#!/usr/bin/env bash
# setup_M01.sh — prépare le terrain de jeu du module 01 (shell au quotidien)
# Idempotent : relançable sans effet de bord.
set -euo pipefail

BASE="$HOME/lab01"

echo "== Préparation du module 01 dans $BASE =="

mkdir -p "$BASE"/{logs,bin,backup,livraison}
mkdir -p "$BASE"/deploy/{blue,green}/{bin,conf,logs}

# --- sauvegarde du .bashrc d'origine (une seule fois) -------------------
if [ -f "$HOME/.bashrc" ] && [ ! -f "$BASE/backup/bashrc.orig" ]; then
  cp -- "$HOME/.bashrc" "$BASE/backup/bashrc.orig"
  echo "  .bashrc sauvegardé dans $BASE/backup/bashrc.orig"
fi

# --- journaux d'exemple -------------------------------------------------
gen_log() {
  # $1 = chemin, $2 = nombre de lignes, $3 = étiquette
  [ -s "$1" ] && return 0
  local i=1
  : > "$1"
  while [ "$i" -le "$2" ]; do
    printf '2026-09-18T%02d:%02d:%02d %s ligne %d\n' \
      $(( i % 24 )) $(( (i * 7) % 60 )) $(( (i * 13) % 60 )) "$3" "$i" \
      >> "$1"
    i=$(( i + 1 ))
  done
}

gen_log "$BASE/logs/app.log"            42 "app"
gen_log "$BASE/logs/app.log.1"          18 "app"
gen_log "$BASE/logs/access.log"        120 "access"
gen_log "$BASE/logs/error.log"           7 "error"
gen_log "$BASE/logs/rapport final.log"  11 "rapport"

# noms hostiles volontaires
[ -e "$BASE/logs/-fichier-bizarre.txt" ] || \
  printf 'a supprimer avec rm --\n' > "$BASE/logs/-fichier-bizarre.txt"

# --- livraison « générée sous Windows » ---------------------------------
mk() { [ -e "$1" ] || printf '%s\n' "$2" > "$1"; }

mk "$BASE/livraison/compte rendu.txt"      "compte rendu de recette"
mk "$BASE/livraison/notes de version.md"   "# notes de version 4.2"
mk "$BASE/livraison/config final.yml"      "app: facturation"
mk "$BASE/livraison/-rapport-2026.txt"     "fichier a supprimer"
mk "$BASE/livraison/donnees?.csv"          "id,valeur"
mk "$BASE/livraison/README.md"             "# livraison 4.2"
mk "$BASE/livraison/app.jar"               "faux binaire"

# --- script de sauvegarde du lab L1.2 -----------------------------------
cat > "$BASE/bin/sauvegarde.sh" <<'EOF'
#!/usr/bin/env bash
# sauvegarde.sh — script « fourni par une autre équipe », ne pas modifier.
# Écrit volontairement sur stdout ET sur stderr, et échoue une fois sur deux.
# FORCER_ECHEC=1 impose l'échec, FORCER_ECHEC=0 impose le succès.
echo "[info] début de la sauvegarde de /srv/app"
echo "[info] 3 volumes à traiter"
echo "[erreur] volume nfs-archives injoignable" >&2
echo "[info] 2 volumes traités"

case "${FORCER_ECHEC:-}" in
  1) code=3 ;;
  0) code=0 ;;
  *) code=$(( RANDOM % 2 == 0 ? 0 : 3 )) ;;
esac

if [ "$code" -ne 0 ]; then
  echo "[erreur] sauvegarde incomplète" >&2
else
  echo "[info] sauvegarde terminée"
fi
exit "$code"
EOF
chmod +x "$BASE/bin/sauvegarde.sh"

# --- répertoire ~/bin, utilisé par L1.1 et D1 ---------------------------
mkdir -p "$HOME/bin"

echo
echo "Prêt. Points d'entrée :"
echo "  $BASE/logs        journaux, dont un nom avec espace"
echo "  $BASE/livraison   noms de fichiers hostiles (L1.3)"
echo "  $BASE/bin/sauvegarde.sh   script du lab L1.2"
echo "  $BASE/backup/bashrc.orig  copie de secours de ton .bashrc"
