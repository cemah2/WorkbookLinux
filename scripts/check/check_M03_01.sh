#!/usr/bin/env bash
# check_M03_01.sh — vérifie le lab L3.1 (répertoire partagé facturation)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L3.1 =="

DIR=/srv/factura/exports

[ -d "$DIR" ] || { ko "$DIR absent (relance setup_M03.sh)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. groupe propriétaire ---------------------------------------------
if [ "$(stat -c '%G' "$DIR")" = "facturation" ]; then
  ok "$DIR appartient au groupe facturation"
else
  ko "$DIR n'est pas en groupe facturation (chgrp facturation)"
fi

# --- 2. SGID présent ----------------------------------------------------
mode=$(stat -c '%a' "$DIR")
# SGID = 's'/'S' en 7e position de la chaîne (bit x du groupe) de stat -c %A
if printf '%s' "$(stat -c '%A' "$DIR")" | grep -Eq '^d.....[sS]'; then
  ok "le bit SGID est positionné sur $DIR (mode $mode)"
else
  ko "SGID absent sur $DIR (chmod 2770) : les fichiers n'héritent pas du groupe"
fi

# --- 3. other exclu -----------------------------------------------------
if printf '%s' "$(stat -c '%A' "$DIR")" | grep -Eq '^d......---'; then
  ok "other n'a aucun accès sur $DIR"
else
  ko "other a des droits sur $DIR (attendu : ---)"
fi

# --- 4. héritage réel : on crée un fichier de test ----------------------
TESTU="webdev"; getent passwd "$TESTU" >/dev/null || TESTU="${SUDO_USER:-mathieu}"
TMPF="$DIR/.check01.$$"
if sudo -u "$TESTU" touch "$TMPF" 2>/dev/null; then
  g=$(stat -c '%G' "$TMPF")
  if [ "$g" = "facturation" ]; then
    ok "un fichier créé par $TESTU hérite du groupe facturation"
  else
    ko "le fichier créé est en groupe '$g', pas facturation (vérifie le SGID)"
  fi
  # --- 5. droit d'écriture du groupe sur le fichier créé ---------------
  if command -v getfacl >/dev/null 2>&1; then
    if getfacl -p "$TMPF" 2>/dev/null | grep -Eq '^group:facturation:rw|^group::rw'; then
      ok "le groupe facturation a le droit d'écriture sur le fichier créé"
    else
      ko "le groupe n'a pas 'w' sur le fichier créé (ACL par défaut manquante \
: setfacl -d -m g:facturation:rw)"
    fi
  else
    note "getfacl absent : contrôle du w de groupe ignoré"
  fi
  rm -f "$TMPF"
else
  ko "impossible de créer un fichier de test en tant que $TESTU"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
