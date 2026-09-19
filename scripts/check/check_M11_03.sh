#!/usr/bin/env bash
# check_M11_03.sh — vérifie le lab L11.3 (sauvegarde cohérente par snapshot)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L11.3 =="

VG=vg_data
DEST=/srv/sauvegardes
SCRIPT=/opt/factura/bin/sauvegarde-snapshot.sh

# --- 1. une archive produite depuis le snapshot ------------------------
ARCHIVE=$(ls -1t "$DEST"/factura-db-*.tar.gz 2>/dev/null | head -1)
if [ -n "$ARCHIVE" ] && [ -s "$ARCHIVE" ]; then
  ok "archive trouvée : $(basename "$ARCHIVE") ($(du -h "$ARCHIVE" | cut -f1))"
  if tar tzf "$ARCHIVE" 2>/dev/null | grep -q 'comptes.dat'; then
    ok "l'archive contient comptes.dat"
  else
    ko "l'archive ne contient pas comptes.dat : as-tu archivé le snapshot \
monté sur /mnt/snap, et non un répertoire vide ?"
  fi
  NB=$(tar tzf "$ARCHIVE" 2>/dev/null | wc -l)
  [ "$NB" -ge 3 ] && ok "l'archive contient $NB entrées" \
    || ko "l'archive ne contient que $NB entrée(s) : elle est probablement vide"
else
  ko "aucune archive factura-db-*.tar.gz dans $DEST"
fi

# --- 2. plus aucun snapshot résiduel -----------------------------------
if command -v lvs >/dev/null 2>&1; then
  RESTE=$(lvs --noheadings -o lv_name -S 'origin!=""' 2>/dev/null | tr -d ' ')
  if [ -z "$RESTE" ]; then
    ok "aucun snapshot LVM résiduel"
  else
    ko "snapshot(s) encore présent(s) : $RESTE — un snapshot est temporaire, \
il se supprime après usage (lvremove)"
  fi
else
  note "lvm2 absent : contrôle des snapshots impossible"
fi

# --- 3. comptes.dat est revenu sur l'origine ---------------------------
if [ -s /srv/factura/db/comptes.dat ]; then
  ok "comptes.dat est présent sur le volume d'origine (fusion réussie)"
else
  ko "comptes.dat manque dans /srv/factura/db : la fusion du snapshot \
(lvconvert --merge puis désactivation/activation du LV) n'a pas abouti"
fi

# --- 4. le script de sauvegarde ----------------------------------------
if [ -x "$SCRIPT" ]; then
  ok "$SCRIPT existe et est exécutable"
  head -1 "$SCRIPT" | grep -q '^#!/usr/bin/env bash' \
    && ok "shebang conforme (#!/usr/bin/env bash)" \
    || ko "shebang attendu : #!/usr/bin/env bash"
  grep -q 'set -euo pipefail' "$SCRIPT" \
    && ok "set -euo pipefail présent" \
    || ko "set -euo pipefail manquant"
  grep -qE '^\s*trap\b' "$SCRIPT" \
    && ok "un trap de nettoyage est installé" \
    || ko "aucun trap : un échec en cours de route laissera un snapshot monté"
  grep -qE 'lvremove' "$SCRIPT" \
    && ok "le script supprime bien le snapshot" \
    || ko "le script n'appelle jamais lvremove"
  grep -qiE 'existe|already|deja|déjà' "$SCRIPT" \
    && ok "le script gère le cas « snapshot déjà présent »" \
    || note "vérifie que le script refuse de démarrer si le snapshot existe déjà"
else
  ko "$SCRIPT absent ou non exécutable"
fi

# --- 5. le script est rejouable ----------------------------------------
if [ -x "$SCRIPT" ] && [ "$(id -u)" -eq 0 ] && command -v lvs >/dev/null 2>&1; then
  if "$SCRIPT" >/dev/null 2>&1 && "$SCRIPT" >/dev/null 2>&1; then
    RESTE2=$(lvs --noheadings -o lv_name -S 'origin!=""' 2>/dev/null | tr -d ' ')
    [ -z "$RESTE2" ] \
      && ok "deux exécutions consécutives : aucun résidu" \
      || ko "après deux exécutions, il reste : $RESTE2"
  else
    ko "le script échoue à la première ou à la seconde exécution"
  fi
else
  note "contrôle de rejouabilité sauté (lance le check avec sudo)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
