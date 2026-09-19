#!/usr/bin/env bash
# check_M06_04.sh — vérifie le lab L6.4 (sauvegardes --link-dest + transfert)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L6.4 =="

HOMEDIR=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)
BK="$HOMEDIR/lab06/backup"

command -v rsync >/dev/null 2>&1 || \
  note "rsync n'est pas installé : installe-le (voir §6.1)"

# --- 1. au moins trois sauvegardes datées --------------------------------
mapfile -t SNAPS < <(find "$BK" -maxdepth 1 -type d \
  -regextype posix-extended \
  -regex '.*/[0-9]{4}-[0-9]{2}-[0-9]{2}$' -printf '%f\n' 2>/dev/null | sort)
if [ "${#SNAPS[@]}" -ge 3 ]; then
  ok "${#SNAPS[@]} sauvegardes datées : ${SNAPS[*]}"
else
  ko "seulement ${#SNAPS[@]} répertoire(s) AAAA-MM-JJ dans $BK (il en faut 3)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi
S1="$BK/${SNAPS[0]}"; S2="$BK/${SNAPS[1]}"; SN="$BK/${SNAPS[-1]}"

# --- 2. contenu et exclusions --------------------------------------------
for S in "$S1" "$S2" "$SN"; do
  if [ -d "$S/app/src" ] || [ -d "$S/factura/app/src" ]; then
    ok "$(basename "$S") contient l'arborescence applicative"
  else
    ko "$(basename "$S") ne contient pas app/src (source : arbo/factura/)"
  fi
done
EXCL=0
for S in "$S1" "$S2" "$SN"; do
  find "$S" -maxdepth 3 \( -name node_modules -o -name cache \) \
    -type d 2>/dev/null | grep -q . && EXCL=$((EXCL+1))
done
[ "$EXCL" -eq 0 ] && ok "node_modules et var/cache exclus partout" || \
  ko "$EXCL sauvegarde(s) embarquent node_modules ou var/cache (--exclude)"

# --- 3. partage par liens durs -------------------------------------------
REF=$(find "$S1" -path '*app/src/mod_01.py' | head -1)
CMP=$(find "$S2" -path '*app/src/mod_01.py' | head -1)
if [ -n "$REF" ] && [ -n "$CMP" ]; then
  I1=$(stat -c %i "$REF"); I2=$(stat -c %i "$CMP")
  if [ "$I1" = "$I2" ]; then
    ok "mod_01.py partage le même inode entre les deux sauvegardes"
  else
    ko "mod_01.py est dupliqué (inodes $I1 et $I2) : --link-dest n'a pas joué"
  fi
  NL=$(stat -c %h "$REF")
  [ "$NL" -ge 2 ] && ok "le fichier inchangé a $NL liens durs" || \
    ko "le fichier n'a qu'un lien dur : chaque sauvegarde est une copie pleine"
else
  ko "mod_01.py introuvable dans les deux premières sauvegardes"
fi

# --- 4. le fichier modifié, lui, est bien distinct ------------------------
C1=$(find "$S1" -path '*conf/factura.conf' | head -1)
C2=$(find "$S2" -path '*conf/factura.conf' | head -1)
if [ -n "$C1" ] && [ -n "$C2" ]; then
  if cmp -s "$C1" "$C2"; then
    ko "conf/factura.conf est identique dans les deux sauvegardes : \
l'étape 2 demandait de le modifier entre les deux"
  else
    ok "conf/factura.conf diffère : chaque sauvegarde garde sa version"
  fi
  [ "$(stat -c %i "$C1")" != "$(stat -c %i "$C2")" ] && \
    ok "les deux versions occupent des inodes distincts" || \
    ko "même inode pour deux contenus différents : impossible, vérifie"
else
  ko "conf/factura.conf introuvable dans les sauvegardes"
fi

# --- 5. suppression propagée à la dernière seulement ----------------------
DISPARUS=0
while IFS= read -r f; do
  rel=${f#"$S1"/}
  [ -e "$SN/$rel" ] || DISPARUS=$((DISPARUS+1))
done < <(find "$S1" -type f | head -400)
if [ "$DISPARUS" -ge 1 ]; then
  ok "$DISPARUS fichier(s) présents dans la 1re sauvegarde et absents de la \
dernière : --delete a joué sans toucher à l'historique"
else
  ko "aucun fichier supprimé n'est visible : l'étape 5 (suppression à la \
source + nouvelle sauvegarde avec --delete) n'a pas été faite"
fi

# --- 6. notes écrites -----------------------------------------------------
N="$BK/NOTES.md"
if [ -s "$N" ] && [ "$(grep -c . "$N")" -ge 3 ]; then
  ok "NOTES.md rédigé"
  grep -qi 'scp' "$N" && grep -qi 'sftp' "$N" && \
    ok "NOTES.md compare bien scp et sftp" || \
    ko "NOTES.md doit citer scp ET sftp"
else
  ko "$N absent ou de moins de 3 lignes"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
