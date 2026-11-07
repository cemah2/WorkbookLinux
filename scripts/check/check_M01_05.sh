#!/usr/bin/env bash
# check_M01_05.sh — vérifie le défi D1 (audit-shell.sh + rapport)
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification D1 =="

AUDIT="$HOME/bin/audit-shell.sh"
RAPPORT="$HOME/lab01/audit-lab-adm.md"
TMP=$(mktemp -d); trap 'rm -rf -- "$TMP"' EXIT

if [ -x "$AUDIT" ]; then
  ok "~/bin/audit-shell.sh existe et est exécutable"
else
  ko "~/bin/audit-shell.sh absent ou non exécutable"
  echo "Résultat : $PASS réussis, $FAIL échoués"
  exit 1
fi

head -1 "$AUDIT" | grep -q 'env bash' \
  && ok "shebang #!/usr/bin/env bash" \
  || ko "shebang attendu : #!/usr/bin/env bash"

grep -q 'set -euo pipefail' "$AUDIT" \
  && ok "set -euo pipefail présent" \
  || ko "set -euo pipefail absent"

# --- 1. exécution nominale ----------------------------------------------
"$AUDIT" > "$TMP/out.md" 2> "$TMP/err.txt"; code=$?
if [ "$code" -eq 0 ] || [ "$code" -eq 1 ]; then
  ok "le script sort en 0 ou 1 (ici $code)"
else
  ko "code retour inattendu : $code"
fi

if [ -s "$TMP/out.md" ]; then
  ok "un rapport est produit sur stdout"
else
  ko "stdout est vide : le rapport doit partir sur stdout"
fi

manquants=""
for titre in "## Shell" "## Fichiers de démarrage" "## PATH" "## Anomalies"; do
  grep -qF -- "$titre" "$TMP/out.md" || manquants="$manquants [$titre]"
done
if [ -z "$manquants" ]; then
  ok "toutes les sections obligatoires sont présentes"
else
  ko "sections manquantes :$manquants"
fi

for cle in HISTCONTROL HISTSIZE EDITOR PAGER histappend checkwinsize; do
  grep -q -- "$cle" "$TMP/out.md" || ko "le rapport ne mentionne pas $cle"
done
grep -q HISTCONTROL "$TMP/out.md" && grep -q checkwinsize "$TMP/out.md" \
  && ok "les réglages d'historique et de shell sont rapportés"

if grep -qE '^\[audit\]|^\[' "$TMP/out.md"; then
  ko "des traces de diagnostic polluent stdout (elles vont sur stderr)"
else
  ok "stdout ne contient que du Markdown"
fi

# --- 2. détection d'anomalies -------------------------------------------
PATH_SALE="$PATH:.:/repertoire/qui/nexiste/pas"
if PATH="$PATH_SALE" "$AUDIT" > "$TMP/sale.md" 2>/dev/null; then
  ko "un PATH contenant '.' et un répertoire absent doit sortir en 1"
else
  ok "un PATH pollué fait sortir le script en 1"
fi
# '.' seul : entre backticks/guillemets, isolé, ou « répertoire courant »
MOTIF_POINT='`\.`|"\."|courant|(^|[[:space:]:])\.([[:space:]:]|$)'
if grep -qiE "$MOTIF_POINT" "$TMP/sale.md" &&
   grep -qi 'inexistant\|nexiste' "$TMP/sale.md"
then
  ok "les deux anomalies de PATH sont signalées nommément"
else
  ko "le rapport ne signale pas '.' et le répertoire inexistant"
fi

# --- 3. livrable ---------------------------------------------------------
if [ -s "$RAPPORT" ]; then
  ok "le livrable ~/lab01/audit-lab-adm.md existe"
else
  ko "livrable manquant : audit-shell.sh > ~/lab01/audit-lab-adm.md"
fi

if grep -qF '## Anomalies' "$RAPPORT" 2>/dev/null; then
  ok "le livrable contient la section Anomalies"
else
  ko "le livrable ne ressemble pas à la sortie du script"
fi

if grep -qi 'aucune anomalie' "$RAPPORT" 2>/dev/null; then
  ok "l'environnement audité est propre (0 anomalie)"
else
  ko "le livrable liste encore des anomalies : corrige ton environnement"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
