#!/usr/bin/env bash
# check_M11_06.sh — vérifie le défi D11 (netdiag.sh)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification D11 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BIN="$HOMEDIR/bin/netdiag.sh"
RAP="$HOMEDIR/lab11/rapports/netdiag-www.md"
VAL="$HOMEDIR/lab11/rapports/netdiag-validation.md"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- 1. le script existe, est exécutable, est du bash propre ----------
if [ -x "$BIN" ]; then
  ok "netdiag.sh présent et exécutable"
else
  ko "script absent ou non exécutable : $BIN (chmod +x)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi

head -1 "$BIN" | grep -q '^#!/usr/bin/env bash' \
  && ok "shebang conforme" \
  || ko "le shebang attendu est #!/usr/bin/env bash"

grep -q 'set -euo pipefail' "$BIN" \
  && ok "set -euo pipefail présent" \
  || ko "set -euo pipefail manquant (cahier des charges, point 1)"

bash -n "$BIN" 2>/dev/null \
  && ok "syntaxe bash valide" \
  || ko "bash -n signale une erreur de syntaxe"

# --- 2. usage et code de retour 2 sur argument invalide ---------------
"$BIN" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 2 ] \
  && ok "sans argument : code de retour 2" \
  || ko "sans argument le script sort en $RC, on attend 2"

# --- 3. exécution nominale : Markdown sur stdout ----------------------
CIBLE=www.lab.local
getent hosts "$CIBLE" >/dev/null 2>&1 || CIBLE=127.0.0.1
"$BIN" "$CIBLE" > "$TMP/out.md" 2> "$TMP/err.txt"; RC=$?
note "exécution sur $CIBLE : code de retour $RC"

if [ -s "$TMP/out.md" ]; then
  ok "le script produit un rapport sur stdout"
else
  ko "stdout vide : le rapport doit partir sur stdout, la trace sur stderr"
fi

grep -qE '^\|' "$TMP/out.md" \
  && ok "le rapport contient un tableau Markdown" \
  || ko "aucune ligne de tableau : format attendu | couche | test | ... |"

grep -qiE '^## *Diagnostic' "$TMP/out.md" \
  && ok "section Diagnostic présente" \
  || ko "la section « ## Diagnostic » manque (point 4)"

N=$(grep -cE '^\|' "$TMP/out.md")
[ "$N" -ge 5 ] \
  && ok "$N lignes de tableau : les étages sont couverts" \
  || ko "seulement $N lignes de tableau, on attend un verdict par étage"

for m in OK KO SKIP; do
  grep -q "$m" "$TMP/out.md" && continue
  note "aucun verdict « $m » dans cette exécution (peut être normal)"
done

# le Markdown ne doit pas être pollué par des messages d'erreur
if grep -qiE 'command not found|No such file|Traceback' "$TMP/out.md"; then
  ko "le rapport contient des messages d'erreur : sépare stdout et stderr"
else
  ok "le rapport est propre (pas de message d'erreur mêlé)"
fi

# --- 4. cible volontairement injoignable -> code 1 --------------------
"$BIN" -p 9 10.10.10.254 > "$TMP/ko.md" 2>/dev/null; RC=$?
[ "$RC" -eq 1 ] \
  && ok "cible injoignable : code de retour 1" \
  || ko "sur une cible injoignable le script sort en $RC, on attend 1"

# --- 5. les livrables --------------------------------------------------
[ -s "$RAP" ] \
  && ok "rapport netdiag-www.md livré" \
  || ko "livrable manquant : $RAP (point 7)"

if [ -s "$VAL" ]; then
  ok "rapport de validation présent"
  n=0
  for b in BF11.1 BF11.2 BF11.3 BF11.4; do
    grep -q "$b" "$VAL" && n=$((n+1))
  done
  [ "$n" -eq 4 ] \
    && ok "les quatre pannes sont rejouées et documentées" \
    || ko "seulement $n/4 pannes documentées dans $VAL (point 6)"
else
  ko "livrable manquant : $VAL (les quatre pannes rejouées)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
