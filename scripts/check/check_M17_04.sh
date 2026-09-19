#!/usr/bin/env bash
# check_M17_04.sh — vérifie le lab L17.4 (purge d'un secret de l'historique)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
has()  { grep "$@" >/dev/null; }   # comme grep -q, sans SIGPIPE (pipefail)
echo "== Vérification L17.4 =="

D="$HOME/lab17/factura-infra"
O="$HOME/lab17/remote/factura-infra.git"
RAP="$HOME/lab17/rapports/incident-secret.md"
SECRET='S3cr3t-Factura-2026'
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

for R in "$O" "$D"; do
  if ! git -C "$R" rev-parse --git-dir >/dev/null 2>&1; then
    ko "$R n'est pas un dépôt git"; continue
  fi
  nom=${R##*/}
  if git -C "$R" log --all --format=%h -- .env 2>/dev/null | has .; then
    ko "$nom : des commits touchent encore .env (git log --all -- .env)"
  else ok "$nom : plus aucun commit ne touche .env"; fi
  if git -C "$R" grep -q "$SECRET" $(git -C "$R" rev-list --all 2>/dev/null) \
     2>/dev/null; then
    ko "$nom : le mot de passe est encore lisible dans un objet de l'historique"
  else ok "$nom : le secret n'apparaît dans aucune révision"; fi
  if git -C "$R" for-each-ref refs/original refs/replace 2>/dev/null | has .
  then ko "$nom : refs/original ou refs/replace subsistent (les anciens \
objets restent joignables)"
  else ok "$nom : pas de référence de secours vers l'ancien historique"; fi
  # objets orphelins encore présents ?
  if git -C "$R" cat-file -e 1557f83fa5280573d92393c3cc2ae285890be472 2>/dev/null
  then ko "$nom : l'ancien commit 1557f83 est encore dans la base d'objets \
(reflog expire + gc --prune=now)"
  else ok "$nom : l'ancien commit 1557f83 a été physiquement supprimé"; fi
done

# le clone de travail suit bien le nouvel historique
git -C "$D" fetch -q origin 2>/dev/null
[ "$(git -C "$D" rev-parse main 2>/dev/null)" = \
  "$(git -C "$D" rev-parse origin/main 2>/dev/null)" ] \
  && ok "main et origin/main coïncident après réécriture" \
  || ko "main et origin/main divergent : re-clone ou reset --hard origin/main"

git -C "$D" cat-file -e v1.0.0 2>/dev/null \
  && ok "le tag v1.0.0 a survécu à la réécriture" \
  || ko "le tag v1.0.0 a disparu"

grep -qx '.env' "$D/.gitignore" 2>/dev/null \
  && ok ".env reste ignoré" || ko ".env n'est plus dans .gitignore"

# --- hook pre-commit ------------------------------------------------------
HP=$(git -C "$D" config core.hooksPath 2>/dev/null)
if [ -n "$HP" ]; then HOOK="$D/$HP/pre-commit"; else HOOK="$D/.git/hooks/pre-commit"; fi
[ "${HP:0:1}" = / ] && HOOK="$HP/pre-commit"
if [ -x "$HOOK" ]; then
  ok "hook pre-commit en place ($HOOK)"
  git clone -q "$D" "$TMP/t" 2>/dev/null
  mkdir -p "$TMP/t/$(dirname "${HP:-.git/hooks}")"
  if [ -n "$HP" ] && [ "${HP:0:1}" != / ]; then
    cp -r "$D/$HP" "$TMP/t/$HP" 2>/dev/null
  else
    cp "$HOOK" "$TMP/t/.git/hooks/pre-commit"
  fi
  git -C "$TMP/t" config user.name t; git -C "$TMP/t" config user.email t@t
  [ -n "$HP" ] && git -C "$TMP/t" config core.hooksPath "$HP"
  printf 'DB_PASSWORD=Encore-Un-S3cret\nAWS_SECRET_ACCESS_KEY=abc\n' \
    > "$TMP/t/conf.env"
  git -C "$TMP/t" add -f conf.env
  if git -C "$TMP/t" -c commit.gpgsign=false commit -q -m "test" >/dev/null 2>&1
  then ko "le hook laisse passer un fichier contenant DB_PASSWORD="
  else ok "le hook bloque un commit contenant un secret"; fi
  git -C "$TMP/t" reset -q; rm -f "$TMP/t/conf.env"
  printf 'x=1\n' > "$TMP/t/ok.txt"; git -C "$TMP/t" add ok.txt
  if git -C "$TMP/t" -c commit.gpgsign=false commit -q -m "test ok" \
       >/dev/null 2>&1
  then ok "le hook laisse passer un commit sain"
  else ko "le hook bloque aussi un commit sans secret"; fi
else ko "pas de hook pre-commit exécutable"; fi

if [ -f "$RAP" ]; then
  ok "rapport d'incident présent"
  grep -qiE 'rotation|révoqu|revoqu|changé|change' "$RAP" \
    && ok "le rapport parle de rotation du secret" \
    || ko "le rapport doit expliquer que le secret est révoqué/tourné"
else ko "rapport ~/lab17/rapports/incident-secret.md absent"; fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
