#!/usr/bin/env bash
# check_M02_05.sh — vérifie le défi D2 (audit-fs.sh)
set -uo pipefail
PASS=0; FAIL=0
ok() { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification D2 =="

BIN=/usr/local/bin/audit-fs.sh
HOMEDIR=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# --- 1. le script existe et est exécutable ------------------------------
if [ -x "$BIN" ]; then
  ok "$BIN existe et est exécutable"
else
  ko "$BIN absent ou non exécutable"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi

head -1 "$BIN" | grep -q '^#!/usr/bin/env bash' \
  && ok "shebang conforme" || ko "shebang attendu : #!/usr/bin/env bash"
grep -q 'set -euo pipefail' "$BIN" \
  && ok "set -euo pipefail présent" || ko "set -euo pipefail manquant"

# --- 2. exécution : rapport sur stdout, trace sur stderr ----------------
"$BIN" / > "$TMP/out.md" 2> "$TMP/err.txt"
rc=$?
if [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; then
  ok "code de retour $rc (0 = sain, 1 = anomalies)"
else
  ko "code de retour $rc : seuls 0 et 1 sont prévus"
fi

if [ -s "$TMP/out.md" ]; then
  ok "le script produit un rapport sur stdout"
else
  ko "stdout est vide : le rapport doit y aller, la trace sur stderr"
fi

premiere=$(grep -m1 . "$TMP/out.md")
case "$premiere" in
  '#'*) ok "stdout commence par un titre Markdown" ;;
  *)    ko "stdout ne commence pas par un titre Markdown : '$premiere'" ;;
esac

# --- 3. sections obligatoires -------------------------------------------
manque=""
for mot in "ontage" "épertoire" "ichier" "upprim" "ien" "reux" "ournal" \
           "nomalie"; do
  grep -qi "$mot" "$TMP/out.md" || manque="$manque $mot"
done
if [ -z "$manque" ]; then
  ok "les huit sections attendues sont présentes"
else
  ko "sections manquantes (mot-clé) :$manque"
fi

# --- 4. usage en blocs ET en inodes -------------------------------------
if grep -qiE 'inode' "$TMP/out.md"; then
  ok "le rapport donne l'usage en inodes"
else
  ko "le rapport doit donner le % d'inodes (df -i), pas seulement df -h"
fi

# --- 5. option -n et argument de chemin ---------------------------------
mkdir -p "$TMP/cible/sous"
printf 'x\n' > "$TMP/cible/sous/f.txt"
avant=$(find "$TMP/cible" | sort | md5sum)
"$BIN" -n "$TMP/cible" > "$TMP/out2.md" 2>/dev/null
rc2=$?
apres=$(find "$TMP/cible" | sort | md5sum)
if [ "$avant" = "$apres" ]; then
  ok "le script n'écrit rien dans l'arborescence auditée"
else
  ko "le script a modifié l'arborescence auditée"
fi
if [ "$rc2" -eq 0 ] || [ "$rc2" -eq 1 ]; then
  ok "le script accepte un chemin en argument et l'option -n"
else
  ko "échec sur '$BIN -n <chemin>' (code $rc2)"
fi

# --- 6. robustesse aux noms à espaces -----------------------------------
mkdir -p "$TMP/cible/repertoire avec espaces"
printf 'y\n' > "$TMP/cible/repertoire avec espaces/fichier a espace.txt"
"$BIN" -n "$TMP/cible" > "$TMP/out3.md" 2>/dev/null
rc3=$?
if [ "$rc3" -eq 0 ] || [ "$rc3" -eq 1 ]; then
  ok "le script survit aux noms contenant des espaces"
else
  ko "le script échoue sur un nom contenant une espace (code $rc3)"
fi

# --- 7. rapport livré ----------------------------------------------------
RAP="$HOMEDIR/lab02/rapports/audit-lab-ops.md"
if [ -s "$RAP" ] && [ "$(grep -c . "$RAP")" -ge 15 ]; then
  ok "le rapport audit-lab-ops.md est livré"
else
  ko "rapport ~/lab02/rapports/audit-lab-ops.md absent ou trop court"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
