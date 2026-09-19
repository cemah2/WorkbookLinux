#!/usr/bin/env bash
# check_M06_03.sh — vérifie le lab L6.3 (archive de migration + restauration)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L6.3 =="

HOMEDIR=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)
ARCH="$HOMEDIR/lab06/archives"
REST="$HOMEDIR/lab06/restauration"

# --- 1. l'archive existe --------------------------------------------------
TGZ=$(ls -1t "$ARCH"/factura-2[0-9][0-9][0-9][0-1][0-9][0-3][0-9].tar.gz \
        2>/dev/null | head -1)
if [ -z "${TGZ:-}" ]; then
  ko "aucune archive $ARCH/factura-<AAAAMMJJ>.tar.gz"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi
ok "archive trouvée : $(basename "$TGZ")"

LISTE=$(mktemp); tar -tzf "$TGZ" > "$LISTE" 2>/dev/null || \
  ko "l'archive n'est pas lisible par tar -tzf"

# --- 2. chemins relatifs, préfixe factura/ --------------------------------
if grep -q '^/' "$LISTE"; then
  ko "l'archive contient des chemins absolus (utilise -C et un chemin relatif)"
else
  ok "aucun chemin absolu dans l'archive"
fi
if grep -q '^factura/' "$LISTE"; then
  ok "les entrées sont préfixées par factura/"
else
  ko "les entrées ne commencent pas par factura/ (tar -czf x -C ~/lab06/arbo \
factura)"
fi
if grep -qE '^(home|[^/]*/home)' "$LISTE"; then
  ko "le chemin du home a été embarqué dans l'archive"
else
  ok "le chemin du home n'apparaît pas"
fi

# --- 3. exclusions --------------------------------------------------------
for MOTIF in 'node_modules' 'var/cache' '\.log$'; do
  if grep -qE "$MOTIF" "$LISTE"; then
    ko "des entrées correspondant à '$MOTIF' sont dans l'archive (--exclude)"
  else
    ok "aucune entrée '$MOTIF' : exclusion effective"
  fi
done

# --- 4. contenu attendu ---------------------------------------------------
for ENTREE in 'factura/app/src/mod_01.py' 'factura/conf/factura.conf' \
              'factura/conf/secrets/api.token'; do
  grep -qx "$ENTREE" "$LISTE" && ok "$ENTREE présent" || \
    ko "$ENTREE absent de l'archive"
done

# --- 5. modes et propriétaires numériques ---------------------------------
DET=$(tar -tvzf "$TGZ" --numeric-owner 2>/dev/null | \
        grep 'factura/conf/secrets/api.token' | head -1)
if printf '%s' "$DET" | grep -q '^-rw-r-----'; then
  ok "api.token conserve le mode 640 dans l'archive"
else
  ko "api.token n'est pas en 640 dans l'archive (ligne lue : ${DET:-aucune})"
fi
if printf '%s' "$DET" | grep -qE '(^| )0/[0-9]+( |$)'; then
  ok "api.token est stocké avec l'UID numérique 0 (--numeric-owner)"
else
  ko "api.token n'est pas stocké avec l'UID 0 : il manque --numeric-owner \
(lu : ${DET:-aucune})"
fi

# --- 6. somme de contrôle -------------------------------------------------
SUM="$TGZ.sha256"
if [ -f "$SUM" ]; then
  ok "$(basename "$SUM") présent"
  if ( cd "$ARCH" && sha256sum -c --status "$(basename "$SUM")" ); then
    ok "sha256sum -c valide l'archive"
  else
    ko "sha256sum -c échoue : somme obsolète ou chemin absolu dans le fichier"
  fi
else
  ko "pas de $(basename "$TGZ").sha256 (sha256sum x.tar.gz > x.tar.gz.sha256)"
fi

# --- 7. découpe en morceaux de 2 Mio --------------------------------------
BASE=$(basename "$TGZ" .tar.gz)
mapfile -t PARTS < <(ls -1 "$ARCH/$BASE".part.* 2>/dev/null | sort)
if [ "${#PARTS[@]}" -ge 2 ]; then
  ok "${#PARTS[@]} morceaux $BASE.part.* trouvés"
  TROP=0
  for p in "${PARTS[@]}"; do
    [ "$(stat -c %s "$p")" -le 2097152 ] || TROP=$((TROP+1))
  done
  [ "$TROP" -eq 0 ] && ok "aucun morceau ne dépasse 2 Mio" || \
    ko "$TROP morceau(x) dépassent 2 Mio (split -b 2M)"
  REF=$(sha256sum < "$TGZ" | cut -d' ' -f1)
  GOT=$(cat "${PARTS[@]}" | sha256sum | cut -d' ' -f1)
  [ "$REF" = "$GOT" ] && ok "cat des morceaux redonne l'archive à l'octet près" \
    || ko "la concaténation des morceaux ne redonne pas l'archive (ordre ?)"
else
  ko "moins de 2 morceaux $BASE.part.* (split -b 2M $TGZ $BASE.part.)"
fi

# --- 8. restauration testée ----------------------------------------------
if [ -d "$REST/test/factura/app/src" ]; then
  ok "$REST/test/factura/ contient l'application restaurée"
  NB=$(find "$REST/test/factura/app/src" -name '*.py' | wc -l)
  [ "$NB" -ge 25 ] && ok "$NB modules restaurés dans app/src" || \
    ko "seulement $NB modules dans app/src : restauration incomplète"
  if [ -f "$REST/test/factura/conf/secrets/api.token" ]; then
    M=$(stat -c %a "$REST/test/factura/conf/secrets/api.token")
    [ "$M" = 640 ] && ok "api.token restauré en 640" || \
      ko "api.token restauré en $M : il fallait extraire avec -p"
  else
    ko "api.token n'a pas été restauré"
  fi
else
  ko "pas de restauration dans $REST/test/ (tar -xzpf ... -C $REST/test)"
fi

# --- 9. reconstitution vérifiée ------------------------------------------
if ls "$REST"/*.tar.gz >/dev/null 2>&1; then
  ok "une archive reconstituée est présente dans $REST"
else
  note "aucune archive reconstituée dans $REST (étape 5 : cat des morceaux)"
fi

# --- 10. procédure écrite -------------------------------------------------
DOC="$ARCH/RESTAURATION.md"
if [ -s "$DOC" ] && [ "$(grep -c . "$DOC")" -ge 8 ]; then
  ok "RESTAURATION.md rédigé"
  grep -q 'tar' "$DOC" && ok "il contient la commande de restauration" || \
    ko "RESTAURATION.md ne cite aucune commande tar"
  grep -qi 'sha256\|integrit' "$DOC" && \
    ok "il traite la vérification d'intégrité" || \
    ko "RESTAURATION.md ne dit pas comment vérifier l'intégrité"
else
  ko "$DOC absent ou trop court (8 lignes minimum)"
fi

rm -f "$LISTE"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
