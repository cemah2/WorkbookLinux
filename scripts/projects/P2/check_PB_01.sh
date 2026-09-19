#!/usr/bin/env bash
# check_PB_01.sh — vérifie le jalon PB.1 (mono-repo Gitea, pre-commit)
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification PB.1 =="
REPO="${REPO:-$HOME/factura-v2}"
export PATH="$HOME/.local/bin:$PATH"

cd "$REPO" 2>/dev/null || { ko "dépôt $REPO introuvable (setup_P2.sh ?)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  && ok "$REPO est un dépôt git" \
  || { ko "$REPO n'est pas un dépôt git (git init)"; \
       echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- remote Gitea -------------------------------------------------------
URL=$(git remote get-url origin 2>/dev/null || true)
echo "$URL" | grep -qE 'lab-ops(\.lab\.local)?(:3000|:22|:)?.*factura' \
  && ok "remote origin pointe vers Gitea sur lab-ops ($URL)" \
  || ko "remote origin absent ou ne pointe pas vers lab-ops (git remote -v)"
if git ls-remote --exit-code origin >/dev/null 2>&1; then
  ok "git ls-remote origin répond"
  git fetch -q origin 2>/dev/null
  [ -z "$(git log origin/main..main --oneline 2>/dev/null)" ] \
    && ok "main est poussée sur origin" \
    || ko "des commits locaux ne sont pas poussés (git push)"
else
  ko "origin injoignable (dépôt créé sur Gitea ? clé SSH/token ?)"
fi

# --- arborescence mono-repo ---------------------------------------------
for d in app infra ansible .gitea/workflows; do
  [ -d "$d" ] && ok "répertoire $d/ présent" || ko "répertoire $d/ manquant"
done
git ls-files --error-unmatch app/api/Dockerfile >/dev/null 2>&1 \
  && ok "app/ est versionné" || ko "app/ n'est pas commité"

# --- pre-commit ----------------------------------------------------------
CFG=.pre-commit-config.yaml
[ -f "$CFG" ] && ok "$CFG présent" || ko "$CFG manquant"
for h in gitleaks shellcheck yamllint ansible-lint; do
  grep -q "$h" "$CFG" 2>/dev/null \
    && ok "hook $h déclaré" || ko "hook $h absent de $CFG"
done
[ -x .git/hooks/pre-commit ] && grep -q pre-commit .git/hooks/pre-commit \
  && ok "hooks installés (.git/hooks/pre-commit)" \
  || ko "hooks non installés (pre-commit install)"
[ -x .git/hooks/commit-msg ] \
  && ok "hook commit-msg installé" \
  || ko "pas de hook commit-msg (pre-commit install --hook-type commit-msg)"
if command -v pre-commit >/dev/null 2>&1; then
  if pre-commit run --all-files >/tmp/pc.log 2>&1; then
    ok "pre-commit run --all-files passe"
  else
    ko "pre-commit run --all-files échoue (voir /tmp/pc.log)"
  fi
else
  ko "pre-commit n'est pas dans le PATH (pipx ensurepath)"
fi

# --- convention de commit -------------------------------------------------
RE='^(feat|fix|chore|docs|ci|infra|refactor|test)(\([a-z0-9._/-]+\))?!?: .+'
BAD=$(git log -n 10 --format=%s | grep -vE "$RE" | grep -v '^Merge' || true)
[ -z "$BAD" ] && ok "les 10 derniers messages suivent type(scope): sujet" \
  || ko "messages hors convention : $(echo "$BAD" | head -2 | tr '\n' '|')"
[ "$(git log --oneline | wc -l)" -ge 5 ] \
  && ok "au moins 5 commits" || ko "moins de 5 commits : travaille par petits pas"

# --- aucun secret en clair ---------------------------------------------
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --no-banner -q >/dev/null 2>&1 \
    && ok "gitleaks ne trouve aucun secret dans l'historique" \
    || ko "gitleaks détecte un secret (gitleaks detect -v) : purge l'historique"
fi
git ls-files | grep -qE '(^|/)terraform\.tfvars$|\.tfstate$|^\.vault-pass$' \
  && ko "un fichier sensible est versionné (tfvars/tfstate/.vault-pass)" \
  || ok "aucun tfstate/tfvars/.vault-pass versionné"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
