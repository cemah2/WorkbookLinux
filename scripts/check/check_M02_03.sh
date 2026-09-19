#!/usr/bin/env bash
# check_M02_03.sh — vérifie le lab L2.3 (audit d'arborescence avec find)
set -uo pipefail
PASS=0; FAIL=0
ok() { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification L2.3 =="

HOMEDIR=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)
INV="$HOMEDIR/lab02/inventaire"
ARBO="$HOMEDIR/lab02/arbo"

[ -d "$ARBO" ] || { ko "$ARBO absent (relance setup_M02.sh)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. les six livrables existent et ne sont pas vides -----------------
for f in gros.txt anciens.txt par-proprietaire.txt code.txt sommes.txt \
         resume.txt; do
  if [ -s "$INV/$f" ]; then
    ok "$f présent et non vide"
  else
    ko "$INV/$f absent ou vide"
  fi
done

# --- 2. gros.txt : les gros fichiers sont bien là -----------------------
if [ -s "$INV/gros.txt" ]; then
  manquants=""
  for n in debug.log access.log dump-2026-08.sql; do
    grep -q "$n" "$INV/gros.txt" || manquants="$manquants $n"
  done
  [ -z "$manquants" ] \
    && ok "gros.txt liste bien les fichiers de plus de 5 Mio" \
    || ko "gros.txt ne contient pas :$manquants (find -size +5M)"
fi

# --- 3. anciens.txt : les fichiers de plus de 90 jours ------------------
if [ -s "$INV/anciens.txt" ]; then
  if grep -q 'audit ancien.log' "$INV/anciens.txt"; then
    ok "anciens.txt contient 'audit ancien.log' avec son nom entier"
  else
    ko "anciens.txt : 'audit ancien.log' manquant ou tronqué par l'espace"
  fi
  if grep -q 'dump-2025-11.sql' "$INV/anciens.txt"; then
    ok "anciens.txt contient les vieux dumps"
  else
    ko "anciens.txt : dump-2025-11.sql manquant (-mtime +90)"
  fi
fi

# --- 4. par-proprietaire.txt --------------------------------------------
if [ -s "$INV/par-proprietaire.txt" ]; then
  if grep -q 'photo1.jpg' "$INV/par-proprietaire.txt" \
     && grep -q 'www-data' "$INV/par-proprietaire.txt"; then
    ok "par-proprietaire.txt liste les fichiers de www-data"
  else
    ko "par-proprietaire.txt : attendu les .jpg de uploads, propriétaire \
www-data (find ! -user ...)"
  fi
fi

# --- 5. code.txt : node_modules et .git exclus mais intacts -------------
if [ -s "$INV/code.txt" ]; then
  if grep -q 'node_modules\|\.git' "$INV/code.txt"; then
    ko "code.txt contient encore node_modules ou .git (-prune)"
  else
    ok "code.txt exclut node_modules et .git"
  fi
  grep -q 'main.py' "$INV/code.txt" \
    && ok "code.txt contient bien le code applicatif" \
    || ko "code.txt ne contient pas app/src/main.py"
fi
[ -e "$ARBO/app/node_modules/left-pad/index.js" ] \
  && ok "node_modules est intact (exclu du parcours, pas supprimé)" \
  || ko "node_modules a été supprimé : -prune n'efface rien"
[ -e "$ARBO/app/.git/objects/pack.idx" ] \
  && ok ".git est intact" \
  || ko ".git a été supprimé"

# --- 6. sommes.txt : une ligne par .log, espaces compris ----------------
nblog=$(find "$ARBO" -type f -name '*.log' | wc -l)
if [ -s "$INV/sommes.txt" ]; then
  nbsom=$(grep -c . "$INV/sommes.txt")
  if [ "$nbsom" -eq "$nblog" ]; then
    ok "sommes.txt contient $nbsom lignes pour $nblog fichiers .log"
  else
    ko "sommes.txt : $nbsom lignes pour $nblog .log (print0 + xargs -0)"
  fi
  grep -q 'audit ancien.log' "$INV/sommes.txt" \
    && ok "le nom contenant une espace apparaît entier dans sommes.txt" \
    || ko "sommes.txt : 'audit ancien.log' absent ou découpé"
fi

# --- 7. ménage des .tmp anciens -----------------------------------------
reste=$(find "$ARBO" -type f -name '*.tmp' -mtime +3 2>/dev/null | wc -l)
if [ "$reste" -eq 0 ]; then
  ok "plus aucun .tmp de plus de 3 jours"
else
  ko "$reste fichiers .tmp de plus de 3 jours subsistent"
fi

# --- 8. resume.txt : chiffres cohérents ---------------------------------
if [ -s "$INV/resume.txt" ] && grep -Eq '[0-9]' "$INV/resume.txt"; then
  ok "resume.txt contient des valeurs chiffrées"
else
  ko "resume.txt doit contenir nombre de fichiers, de répertoires, \
d'inodes et les deux tailles"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
