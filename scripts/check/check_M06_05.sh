#!/usr/bin/env bash
# check_M06_05.sh — vérifie le défi D6 (chaîne de sauvegarde factura)
# Le script de l'apprenant est réellement exécuté, dans ses propres
# répertoires. Rien n'est vérifié sur la façon dont il est écrit.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D6 =="

HOMEDIR=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)
BIN="$HOMEDIR/bin/factura-backup.sh"
BK="$HOMEDIR/lab06/backup"
AR="$BK/archives"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# --- 1. le livrable existe ------------------------------------------------
if [ -x "$BIN" ]; then
  ok "$BIN existe et est exécutable"
else
  ko "$BIN absent ou non exécutable (chmod +x)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi
head -1 "$BIN" | grep -q '^#!/usr/bin/env bash' && ok "shebang conforme" || \
  ko "le shebang doit être #!/usr/bin/env bash"
grep -q 'set -euo pipefail' "$BIN" && ok "set -euo pipefail présent" || \
  ko "set -euo pipefail manquant"

# --- 2. aide --------------------------------------------------------------
if AIDE=$("$BIN" -h 2>&1) && printf '%s' "$AIDE" | grep -q 'restaurer'; then
  ok "-h renvoie 0 et documente les modes"
else
  ko "-h doit sortir en 0 et lister les modes (sauver, miroir, restaurer, \
verifier)"
fi

compte_arch() { ls -1 "$AR"/factura-*.tar.gz 2>/dev/null | wc -l; }

# --- 3. --dry-run ne crée rien -------------------------------------------
AVANT=$(compte_arch)
"$BIN" --dry-run sauver >/dev/null 2>&1 || "$BIN" -n sauver >/dev/null 2>&1
APRES=$(compte_arch)
if [ "$AVANT" = "$APRES" ]; then
  ok "--dry-run sauver n'a créé aucune archive"
else
  ko "--dry-run a quand même produit une archive ($AVANT -> $APRES)"
fi

# --- 4. sauver ------------------------------------------------------------
if "$BIN" sauver >"$TMP/sauver.out" 2>"$TMP/sauver.err"; then
  ok "'sauver' se termine en 0"
else
  ko "'sauver' sort en erreur : $(tail -1 "$TMP/sauver.err")"
fi
TGZ=$(ls -1t "$AR"/factura-*.tar.gz 2>/dev/null | head -1)
if [ -n "${TGZ:-}" ]; then
  ok "archive produite : $(basename "$TGZ")"
  basename "$TGZ" | grep -qE 'factura-[0-9]{4}-?[0-9]{2}-?[0-9]{2}\.tar\.gz' \
    && ok "le nom porte la date du jour" || \
    ko "le nom d'archive doit contenir la date (factura-AAAA-MM-JJ.tar.gz)"
  if [ -f "$TGZ.sha256" ] && \
     ( cd "$AR" && sha256sum -c --status "$(basename "$TGZ").sha256" ); then
    ok "le .sha256 associé existe et vérifie l'archive"
  else
    ko "pas de $(basename "$TGZ").sha256 valide à côté de l'archive"
  fi
  L=$(tar -tzf "$TGZ" 2>/dev/null)
  printf '%s\n' "$L" | grep -q '^/' && \
    ko "chemins absolus dans l'archive" || ok "chemins relatifs"
  printf '%s\n' "$L" | grep -qE 'node_modules|var/cache|\.log$' && \
    ko "les exclusions ne sont pas appliquées (node_modules, cache, *.log)" || \
    ok "exclusions appliquées"
  printf '%s\n' "$L" | grep -q 'app/src/mod_01.py' && \
    ok "l'application est bien dans l'archive" || \
    ko "app/src/mod_01.py absent de l'archive"
else
  ko "aucune archive dans $AR après 'sauver'"
fi

# --- 5. verifier détecte une archive saine puis une archive cassée --------
if "$BIN" verifier >/dev/null 2>&1; then
  ok "'verifier' sort en 0 sur des archives saines"
else
  ko "'verifier' échoue alors que les archives sont saines"
fi
if [ -n "${TGZ:-}" ]; then
  CASSE="$AR/factura-1999-01-01.tar.gz"
  cp "$TGZ" "$CASSE"
  cp "$TGZ.sha256" "$CASSE.sha256" 2>/dev/null || true
  sed -i "s/$(basename "$TGZ")/$(basename "$CASSE")/" "$CASSE.sha256" \
    2>/dev/null || true
  SZ=$(stat -c %s "$CASSE"); truncate -s $((SZ - 2048)) "$CASSE"
  if "$BIN" verifier >/dev/null 2>&1; then
    ko "'verifier' n'a pas détecté une archive tronquée"
  else
    ok "'verifier' détecte l'archive tronquée et sort en erreur"
  fi
  rm -f "$CASSE" "$CASSE.sha256"
fi

# --- 6. rotation à 7 ------------------------------------------------------
if [ -n "${TGZ:-}" ]; then
  for d in 01 02 03 04 05 06 07 08 09; do
    FAUX="$AR/factura-2020-01-$d.tar.gz"
    cp "$TGZ" "$FAUX"
    if [ -f "$TGZ.sha256" ]; then
      sed "s#$(basename "$TGZ")#$(basename "$FAUX")#" "$TGZ.sha256" \
        > "$FAUX.sha256"
    fi
    touch -d "2020-01-$d" "$FAUX"
  done
  "$BIN" sauver >/dev/null 2>&1
  N=$(compte_arch)
  if [ "$N" -le 7 ]; then
    ok "rotation effective : $N archives conservées"
  else
    ko "$N archives après rotation : il ne devait en rester que 7"
  fi
  RECENTE=$(ls -1t "$AR"/factura-*.tar.gz 2>/dev/null | head -1)
  if basename "$RECENTE" | grep -q '2020-01'; then
    ko "la rotation a gardé les vieilles et jeté la plus récente"
  else
    ok "la sauvegarde la plus récente a survécu à la rotation"
  fi
  rm -f "$AR"/factura-2020-01-*.tar.gz "$AR"/factura-2020-01-*.sha256
fi

# --- 7. miroir ------------------------------------------------------------
if ! command -v rsync >/dev/null 2>&1; then
  note "rsync absent : le mode 'miroir' n'est pas testé (voir §6.1)"
elif "$BIN" miroir >/dev/null 2>&1; then
  ok "'miroir' se termine en 0"
  MIR=$(find "$BK" -maxdepth 1 -type d -regextype posix-extended \
        -regex '.*/[0-9]{4}-[0-9]{2}-[0-9]{2}$' | wc -l)
  [ "$MIR" -ge 1 ] && ok "$MIR répertoire(s) miroir daté(s)" || \
    ko "aucun répertoire AAAA-MM-JJ produit par 'miroir'"
else
  ko "'miroir' sort en erreur"
fi

# --- 8. restaurer ---------------------------------------------------------
if [ -n "${TGZ:-}" ]; then
  CIBLE="$TMP/restaure"; mkdir -p "$CIBLE"
  if "$BIN" restaurer "$TGZ" "$CIBLE" >/dev/null 2>&1; then
    ok "'restaurer' se termine en 0 sur un répertoire vide"
    find "$CIBLE" -name 'mod_01.py' | grep -q . && \
      ok "les fichiers sont réellement restaurés" || \
      ko "rien d'utile dans la cible après restauration"
  else
    ko "'restaurer <archive> <cible>' échoue sur un répertoire vide"
  fi
  if "$BIN" restaurer "$TGZ" "$CIBLE" >/dev/null 2>&1; then
    ko "'restaurer' a écrasé un répertoire NON vide sans --force"
  else
    ok "'restaurer' refuse un répertoire non vide sans --force"
  fi
  BIDON="$TMP/bidon.tar.gz"; head -c 4096 /dev/urandom > "$BIDON"
  printf '%s  %s\n' "$(sha256sum < /dev/null | cut -d' ' -f1)" \
    "$(basename "$BIDON")" > "$BIDON.sha256"
  if "$BIN" restaurer "$BIDON" "$TMP/vide2" >/dev/null 2>&1; then
    ko "'restaurer' a accepté une archive dont la somme est fausse"
  else
    ok "'restaurer' refuse une archive dont la somme ne correspond pas"
  fi
fi

# --- 9. journal -----------------------------------------------------------
LOG="$BK/backup.log"
if [ -s "$LOG" ] && [ "$(grep -c . "$LOG")" -ge 2 ]; then
  ok "backup.log alimenté ($(grep -c . "$LOG") lignes)"
  grep -qE '(19|20)[0-9]{2}-[0-9]{2}-[0-9]{2}' "$LOG" && \
    ok "les lignes du journal sont horodatées" || \
    ko "les lignes de backup.log ne portent pas de date"
else
  ko "$LOG absent ou quasi vide : chaque exécution doit y écrire une ligne"
fi

# --- 10. documentation ----------------------------------------------------
DOC="$BK/PROCEDURE.md"
if [ -s "$DOC" ] && [ "$(grep -c . "$DOC")" -ge 10 ]; then
  ok "PROCEDURE.md rédigé"
  grep -qi 'restaur' "$DOC" && ok "il décrit la restauration" || \
    ko "PROCEDURE.md ne décrit pas la restauration"
  grep -qi 'sha256' "$DOC" && ok "il décrit la vérification d'intégrité" || \
    ko "PROCEDURE.md ne décrit pas la vérification d'intégrité"
  grep -qE '(19|20)[0-9]{2}-[0-9]{2}-[0-9]{2}' "$DOC" && \
    ok "le test de restauration est daté" || \
    ko "PROCEDURE.md doit porter la date de ton test de restauration réel"
else
  ko "$DOC absent ou de moins de 10 lignes"
fi

VIMRC="$HOMEDIR/.vimrc"
if [ -s "$VIMRC" ]; then
  ok "~/.vimrc présent"
  C=$(grep -c '"' "$VIMRC")
  [ "$C" -ge 5 ] && ok "$C lignes commentées dans ~/.vimrc" || \
    ko "~/.vimrc doit être commenté (un commentaire par réglage)"
else
  ko "~/.vimrc absent"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
