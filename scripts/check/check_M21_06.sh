#!/usr/bin/env bash
# check_M21_06.sh — vérifie le défi D21 (dépôt de référence de l'équipe)
# À lancer sur lab-adm, en tant que mathieu.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
has()  { grep "$@" >/dev/null; }   # comme grep -q, sans SIGPIPE (pipefail)
echo "== Vérification D21 =="

D="$HOME/lab21/factura-infra"
BARE=/srv/git/factura-infra.git
RAP="$HOME/lab21/rapports/D21.md"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$D" 2>/dev/null || { ko "$D absent"; exit 1; }
g() { git "$@" 2>/dev/null; }

# --- 1. hooks côté client, versionnés -------------------------------------
[ "$(g config core.hooksPath)" = .githooks ] \
  && ok "core.hooksPath = .githooks" \
  || ko "core.hooksPath n'est pas .githooks (git config core.hooksPath .githooks)"
for h in pre-commit commit-msg; do
  if g ls-files --error-unmatch ".githooks/$h" >/dev/null 2>&1 && \
     [ -x ".githooks/$h" ]; then ok ".githooks/$h est versionné et exécutable"
  else ko ".githooks/$h manquant, non versionné ou non exécutable"; fi
done

# test des hooks dans un clone jetable
git clone -q "$D" "$TMP/c" 2>/dev/null
cd "$TMP/c" || exit 1
git config user.name t; git config user.email t@t
git config core.hooksPath .githooks; git config commit.gpgsign false
printf 'x=1\n' > ok.txt; git add ok.txt
git commit -q -m "chore: test" >/dev/null 2>&1 \
  && ok "un commit conforme passe les hooks" \
  || ko "un commit conforme (chore: test) est refusé par les hooks"
printf 'y=2\n' > ok2.txt; git add ok2.txt
git commit -q -m "modif rapide" >/dev/null 2>&1 \
  && ko "commit-msg laisse passer « modif rapide » (Conventional Commits ?)" \
  || ok "commit-msg refuse un message hors convention"
git reset -q
printf 'DB_PASSWORD=Hop-2026\n' > prod.env; git add -f prod.env
git commit -q -m "chore: conf" >/dev/null 2>&1 \
  && ko "pre-commit laisse passer un DB_PASSWORD=" \
  || ok "pre-commit bloque un secret"
git reset -q; rm -f prod.env
printf '#!/bin/bash\nrm -rf $1/*\n' > bad.sh; git add bad.sh
if command -v shellcheck >/dev/null 2>&1; then
  git commit -q -m "chore: script" >/dev/null 2>&1 \
    && ko "pre-commit laisse passer un script que shellcheck refuse" \
    || ok "pre-commit fait passer shellcheck sur les .sh"
else note "shellcheck absent : contrôle shellcheck non testé"; fi
cd "$D" || exit 1

# --- 2. fichiers de gouvernance ------------------------------------------
if [ -f CONTRIBUTING.md ]; then
  ok "CONTRIBUTING.md présent"
  for mot in 'feat' 'fix' 'main' 'secret'; do
    grep -qi "$mot" CONTRIBUTING.md || ko "CONTRIBUTING.md ne parle pas de « $mot »"
  done
else ko "CONTRIBUTING.md absent"; fi
for p in '.env' '*.pem' '*.key' '*.tfstate'; do
  grep -qxF "$p" .gitignore && ok ".gitignore contient $p" \
                            || ko ".gitignore ne contient pas $p"
done
grep -q 'eol=lf' .gitattributes 2>/dev/null \
  && ok ".gitattributes force LF" || ko ".gitattributes sans eol=lf"

# --- 3. signature ----------------------------------------------------------
if g cat-file -p v1.2.0 | has 'BEGIN \(SSH\|PGP\) SIGNATURE'; then
  ok "v1.2.0 est un tag annoté et signé"
else ko "v1.2.0 absent, léger ou non signé (git tag -s)"; fi
sig=$(g log -1 --format=%G? main)
case "$sig" in G) ok "le dernier commit de main est signé et vérifié" ;;
  N) ko "le dernier commit de main n'est pas signé" ;;
  *) note "signature présente mais non vérifiable ici (%G? = $sig) : \
gpg.ssh.allowedSignersFile ?" ;;
esac
grep -q '1.2.0' CHANGELOG.md 2>/dev/null \
  && ok "CHANGELOG.md documente 1.2.0" || ko "CHANGELOG.md sans entrée 1.2.0"

# --- 4. serveur : pre-receive ---------------------------------------------
if [ -d "$BARE" ]; then
  if [ -x "$BARE/hooks/pre-receive" ]; then
    ok "pre-receive présent sur $BARE"
    cp -a "$BARE" "$TMP/bare"
    git clone -q "$TMP/bare" "$TMP/s" 2>/dev/null
    cd "$TMP/s" || exit 1
    git config user.name t; git config user.email t@t
    git config commit.gpgsign false
    printf 'z\n' > z.txt; git add z.txt
    git commit -q -m "n'importe quoi" >/dev/null 2>&1
    git push -q origin HEAD:main >/dev/null 2>&1 \
      && ko "le serveur accepte sur main un commit hors convention" \
      || ok "le serveur refuse un commit hors convention sur main"
    git reset -q --hard HEAD~1
    printf 'DB_PASSWORD=x\n' > .env; git add -f .env
    git commit -q -m "chore: conf" >/dev/null 2>&1
    git push -q origin HEAD:main >/dev/null 2>&1 \
      && ko "le serveur accepte un push qui ajoute .env" \
      || ok "le serveur refuse un push contenant .env"
    cd "$D" || exit 1
  else ko "pas de hook pre-receive exécutable sur $BARE"; fi
  git -C "$BARE" tag 2>/dev/null | has -x v1.2.0 \
    && ok "v1.2.0 est sur le serveur" || ko "v1.2.0 n'est pas poussé sur lab-adm"
else note "$BARE absent : partie serveur non vérifiée (lance sur lab-adm)"; fi

[ -f "$RAP" ] && ok "rapport D21.md présent" || ko "rapport $RAP absent"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
