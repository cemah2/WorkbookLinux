#!/usr/bin/env bash
# check_M04_05.sh — vérifie le Défi D4 (audit des comptes et des délégations)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D4 =="

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
SCRIPT="$LAB_HOME/lab04/bin/audit-comptes.sh"
RAP="$LAB_HOME/lab04/rapports/audit-lab-adm.md"
TMPF=/etc/sudoers.d/89-checkd4
SENTINELLE=/tmp/.d4-sentinelle-$$

nettoyer() { rm -f "$TMPF" "$SENTINELLE"; }
trap nettoyer EXIT

# --- 1. le script existe et respecte le contrat -------------------------
if [ -f "$SCRIPT" ]; then
  ok "le script $SCRIPT existe"
else
  ko "script $SCRIPT introuvable"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi
[ -x "$SCRIPT" ] && ok "il est exécutable" || ko "il n'est pas exécutable (chmod +x)"
head -1 "$SCRIPT" | grep -q '^#!/usr/bin/env bash' \
  && ok "shebang #!/usr/bin/env bash" || ko "shebang attendu : #!/usr/bin/env bash"
grep -qE '^\s*set -euo pipefail' "$SCRIPT" \
  && ok "set -euo pipefail présent" || ko "set -euo pipefail manquant"

# --- 2. il produit un rapport propre sur stdout -------------------------
OUT=$(mktemp); ERR=$(mktemp)
"$SCRIPT" >"$OUT" 2>"$ERR"; RC=$?
if [ -s "$OUT" ]; then
  ok "le script écrit un rapport sur stdout"
else
  ko "stdout vide : le rapport doit partir sur stdout, la trace sur stderr"
fi
grep -qE '^#{1,2} ' "$OUT" && ok "le rapport est structuré en Markdown" \
  || ko "aucun titre Markdown dans le rapport"
grep -qi 'comptes humains' "$OUT" && ok "section « comptes humains » présente" \
  || ko "section des comptes humains manquante"
grep -qi 'sudo' "$OUT" && ok "les règles sudo sont inventoriées" \
  || ko "aucune trace des règles sudo dans le rapport"
grep -qiE '(é|e|É|E)carts?' "$OUT" && ok "section « Écarts » présente" \
  || ko "section des écarts manquante"
if grep -qiE '^\[audit\]|^\s*\+|^\s*=' "$OUT"; then
  note "des lignes de trace semblent partir sur stdout : elles doivent aller \
sur stderr pour que le Markdown reste propre"
fi

# --- 3. le script ne modifie rien ---------------------------------------
touch "$SENTINELLE"
AVANT=$(getent passwd | md5sum; getent group | md5sum; \
        stat -c '%a %U %n' /etc/sudoers /etc/sudoers.d/* 2>/dev/null | md5sum)
"$SCRIPT" >/dev/null 2>&1
APRES=$(getent passwd | md5sum; getent group | md5sum; \
        stat -c '%a %U %n' /etc/sudoers /etc/sudoers.d/* 2>/dev/null | md5sum)
[ "$AVANT" = "$APRES" ] && ok "le script est en lecture seule (rien n'a changé)" \
  || ko "le script a modifié comptes, groupes ou sudoers : il doit AUDITER"

# --- 4. il détecte réellement une anomalie plantée ----------------------
cat > "$TMPF" <<'EOF'
%factura ALL=(ALL) NOPASSWD: ALL
EOF
# mode non conforme (0644 au lieu de 0440), mais PAS world-writable :
# un 0666 ferait refuser tout sudo pendant le test
chown root:root "$TMPF"; chmod 0644 "$TMPF"
OUT2=$(mktemp)
"$SCRIPT" >"$OUT2" 2>/dev/null; RC2=$?
if grep -qiE '89-checkd4|NOPASSWD' "$OUT2"; then
  ok "le script signale la règle 'NOPASSWD: ALL' plantée pour le test"
else
  ko "la règle 'NOPASSWD: ALL' de $TMPF n'est pas signalée"
fi
if grep -qiE '89-checkd4|0?644|mode' "$OUT2"; then
  ok "le script signale le mode non conforme d'un fichier sudoers.d"
else
  ko "le mode 0644 de $TMPF n'est pas signalé (attendu 0440)"
fi
[ "$RC2" -ne 0 ] && ok "code retour non nul quand il reste des écarts" \
  || ko "le script renvoie 0 alors qu'une anomalie est présente"
rm -f "$TMPF" "$OUT2"

# --- 5. la machine est revenue conforme ---------------------------------
if "$SCRIPT" >/dev/null 2>&1; then
  ok "sur la machine remise en état, le script sort en 0"
else
  ko "le script sort encore en 1 : il reste des écarts à corriger (relance-le \
et lis la section Écarts)"
fi

# --- 6. l'anomalie héritée a été traitée, pas supprimée -----------------
LEG=/etc/sudoers.d/50-legacy
if [ -f "$LEG" ]; then
  if grep -vE '^\s*(#|Defaults)' "$LEG" \
       | grep -qE '/usr/bin/(vim|vi|nano|emacs|less|more)'; then
    ko "$LEG délègue toujours un éditeur : sudoedit répond au même besoin"
  else
    ok "$LEG ne délègue plus d'éditeur"
  fi
  if grep -q 'sudoedit' "$LEG"; then
    ok "le besoin d'édition est couvert par sudoedit"
    grep -qE 'Defaults:.*editor=' "$LEG" \
      && ok "  l'éditeur est figé (Defaults:... editor=..., !env_editor)" \
      || ko "  sans 'editor=' + '!env_editor', SUDO_EDITOR redonne un shell root"
  else
    note "$LEG ne contient plus de règle : vérifie que le besoin d'édition de \
/opt/factura/etc/factura.conf est couvert autrement"
  fi
else
  note "$LEG a été supprimé : acceptable seulement si le besoin est couvert \
ailleurs (l'énoncé demandait d'y répondre, pas de l'ignorer)"
fi

# --- 7. le rapport livré -------------------------------------------------
if [ -s "$RAP" ] && [ "$(grep -c . "$RAP")" -ge 15 ]; then
  ok "le rapport $RAP est livré"
else
  ko "rapport $RAP absent ou trop court (audit-comptes.sh > $RAP)"
fi

rm -f "$OUT" "$ERR"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
