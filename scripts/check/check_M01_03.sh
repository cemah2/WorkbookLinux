#!/usr/bin/env bash
# check_M01_03.sh — vérifie le lab L1.3 (noms de fichiers hostiles)
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification L1.3 =="

DIR="$HOME/lab01/livraison"
ARC="$HOME/lab01/livraison.tar.gz"

if [ -d "$DIR" ]; then
  ok "$DIR existe"
else
  ko "répertoire ~/lab01/livraison absent (relance setup_M01.sh)"
  echo "Résultat : $PASS réussis, $FAIL échoués"
  exit 1
fi

# --- 1. plus aucun nom avec espace --------------------------------------
avec_espace=0
for f in "$DIR"/*; do
  [ -e "$f" ] || continue
  base=${f##*/}
  case "$base" in *\ *) avec_espace=$((avec_espace+1)) ;; esac
done
if [ "$avec_espace" -eq 0 ]; then
  ok "aucun nom de fichier ne contient d'espace"
else
  ko "$avec_espace fichier(s) contiennent encore une espace"
fi

# --- 2. les renommages ont bien eu lieu ---------------------------------
attendus=0; trouves=0
for n in "compte_rendu.txt" "notes_de_version.md" "config_final.yml"; do
  attendus=$((attendus+1))
  [ -e "$DIR/$n" ] && trouves=$((trouves+1))
done
if [ "$trouves" -eq "$attendus" ]; then
  ok "les 3 fichiers à espaces ont été renommés avec des soulignés"
else
  ko "$trouves/$attendus fichiers renommés (espace -> _, sans rien perdre)"
fi

# --- 3. le fichier à tiret initial est supprimé -------------------------
if [ ! -e "$DIR/-rapport-2026.txt" ]; then
  ok "le fichier commençant par un tiret a été supprimé"
else
  ko "-rapport-2026.txt est toujours là (rm -- ou rm ./-...)"
fi

# --- 4. le fichier avec ? est intact ------------------------------------
if [ -e "$DIR/donnees?.csv" ]; then
  ok "donnees?.csv a été conservé tel quel"
else
  ko "donnees?.csv a disparu : le ? a dû être développé comme un glob"
fi

# --- 5. rien n'a été perdu ----------------------------------------------
nb_dir=0
for f in "$DIR"/*; do [ -e "$f" ] && nb_dir=$((nb_dir+1)); done
if [ "$nb_dir" -ge 6 ]; then
  ok "$nb_dir fichiers présents, aucun disparu au passage"
else
  ko "seulement $nb_dir fichiers : des fichiers ont été perdus"
fi

# --- 6. archive ----------------------------------------------------------
if [ -f "$ARC" ]; then
  ok "l'archive ~/lab01/livraison.tar.gz existe"
  nb_tar=$(tar -tzf "$ARC" 2>/dev/null | grep -cv '/$')
  if [ "${nb_tar:-0}" -eq "$nb_dir" ]; then
    ok "l'archive contient les $nb_dir fichiers du répertoire"
  else
    ko "l'archive contient $nb_tar fichiers pour $nb_dir sur le disque"
  fi
  if tar -tzf "$ARC" 2>/dev/null | grep -q '^/'; then
    ko "l'archive contient des chemins absolus (utilise tar -C)"
  else
    ok "l'archive utilise des chemins relatifs"
  fi
else
  ko "archive ~/lab01/livraison.tar.gz absente"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
