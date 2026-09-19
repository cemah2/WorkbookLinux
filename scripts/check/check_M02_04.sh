#!/usr/bin/env bash
# check_M02_04.sh — vérifie le lab L2.4 (liens physiques et symboliques)
set -uo pipefail
PASS=0; FAIL=0
ok() { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification L2.4 =="

HOMEDIR=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)
UP="$HOMEDIR/lab02/arbo/uploads"
LI="$HOMEDIR/lab02/liens"

# le répertoire a pu être renommé copie-v2 à l'étape 7
COPIE=""
for c in "$LI/copie-v2" "$LI/copie"; do
  [ -d "$c" ] && { COPIE="$c"; break; }
done
if [ -n "$COPIE" ]; then
  ok "répertoire de doublons trouvé : ${COPIE##*/}"
else
  ko "ni liens/copie ni liens/copie-v2 n'existe"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi

# --- 1. dédoublonnage par lien physique ---------------------------------
for p in photo1.jpg photo2.jpg; do
  if [ -f "$UP/$p" ] && [ -f "$COPIE/$p" ]; then
    i1=$(stat -c %i "$UP/$p"); i2=$(stat -c %i "$COPIE/$p")
    n1=$(stat -c %h "$UP/$p")
    if [ "$i1" = "$i2" ]; then
      ok "$p : même inode ($i1) des deux côtés, une seule copie physique"
    else
      ko "$p : inodes différents ($i1 / $i2), c'est encore une copie (ln)"
    fi
    if [ "$n1" -ge 2 ]; then
      ok "$p : compteur de liens à $n1"
    else
      ko "$p : compteur de liens à $n1, le lien physique manque"
    fi
  else
    ko "$p absent de uploads ou de ${COPIE##*/}"
  fi
done

# --- 2. lien symbolique absolu vers l'autre système de fichiers ---------
SL=/srv/appdata/incoming/photo2.jpg
if [ -L "$SL" ]; then
  ok "$SL est un lien symbolique"
  cible=$(readlink "$SL")
  case "$cible" in
    /*) ok "le lien est absolu ($cible)" ;;
     *) ko "le lien est relatif ($cible) : il ne survivra pas au \
déplacement, l'énoncé demande un absolu" ;;
  esac
  if [ -e "$SL" ]; then
    ok "le lien résout vers un fichier existant"
  else
    ko "le lien est cassé : readlink -f $SL pour voir vers quoi il pointe"
  fi
elif [ -f "$SL" ]; then
  ko "$SL est un fichier ordinaire : l'espace est toujours consommé deux fois"
else
  ko "$SL n'existe pas"
fi

# --- 3. aucun lien cassé sous ~/lab02 (hors casse.txt du setup) ---------
casses=$(find "$HOMEDIR/lab02" -xtype l ! -name 'casse.txt' 2>/dev/null | wc -l)
if [ "$casses" -eq 0 ]; then
  ok "aucun lien symbolique cassé sous ~/lab02 (hors casse.txt du setup)"
else
  ko "$casses lien(s) cassé(s) sous ~/lab02 : find ~/lab02 -xtype l"
fi

# --- 4. les deux emplacements sont bien sur deux fs différents ---------
d1=$(stat -c %d "$UP" 2>/dev/null); d2=$(stat -c %d /srv/appdata 2>/dev/null)
if [ -n "$d1" ] && [ "$d1" != "$d2" ]; then
  ok "uploads et /srv/appdata sont sur deux systèmes de fichiers distincts"
else
  ko "/srv/appdata n'est plus monté : relance setup_M02.sh"
fi

# --- 5. rapport ----------------------------------------------------------
RAP="$HOMEDIR/lab02/rapports/liens.md"
if [ -s "$RAP" ] && [ "$(grep -c . "$RAP")" -ge 3 ]; then
  ok "la règle de décision liens.md est rédigée"
else
  ko "rapport ~/lab02/rapports/liens.md absent ou trop court"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
