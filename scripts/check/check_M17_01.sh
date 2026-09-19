#!/usr/bin/env bash
# check_M17_01.sh — vérifie le lab L17.1 (intégration de feature/tls-letsencrypt)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
has()  { grep "$@" >/dev/null; }   # comme grep -q, sans SIGPIPE (pipefail)
echo "== Vérification L17.1 =="

D="$HOME/lab17/factura-infra"
TPL=ansible/roles/nginx/templates/factura.conf.j2
if ! git -C "$D" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ko "$D n'est pas un dépôt git : relance setup_M17.sh"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi
cd "$D" || exit 1
g() { git "$@" 2>/dev/null; }

# --- état du dépôt -------------------------------------------------------
if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ] || [ -f .git/MERGE_HEAD ]
then ko "un rebase ou un merge est encore en cours (git status)"
else ok "aucune opération en cours"; fi

[ "$(g branch --show-current)" = main ] \
  && ok "tu es sur main" || ko "reviens sur main (git switch main)"

if g status --porcelain | has '^[MADRU]'; then
  ko "des modifications sont encore en attente (git status)"
else ok "index et working tree propres"; fi

# --- contenu attendu sur main --------------------------------------------
if g show main:$TPL | has 'listen 443 ssl'; then
  ok "main écoute en 443 (le travail d'alice est intégré)"
else ko "main ne contient pas « listen 443 ssl » : la feature n'est pas intégrée"; fi

if g show main:$TPL | has 'Strict-Transport-Security'; then
  ok "main garde l'en-tête HSTS (le conflit a été résolu sans perdre main)"
else ko "l'en-tête HSTS a disparu : le conflit a été résolu en écrasant main"; fi

if g show main:$TPL | has -E '^(<<<<<<<|=======|>>>>>>>)'; then
  ko "des marqueurs de conflit sont commités dans $TPL"
else ok "aucun marqueur de conflit dans le template"; fi

g show main:ansible/roles/nginx/tasks_certbot.yml | has certbot.timer \
  && ok "tasks_certbot.yml (renouvellement) est sur main" \
  || ko "ansible/roles/nginx/tasks_certbot.yml manque ou est incomplet sur main"

# --- historique propre ----------------------------------------------------
if g log --format=%s main | has -xE 'wip|fix typo'; then
  ko "les commits « wip » / « fix typo » sont dans main : squash attendu"
else ok "les commits wip / fix typo ont été fusionnés (rebase -i)"; fi

n=$(g log --format=%s main | grep -c '^feat(nginx): écoute en 443')
[ "$n" -eq 1 ] && ok "un seul commit « écoute en 443 » dans main" \
               || ko "le commit « écoute en 443 » apparaît $n fois (attendu 1)"

if g log --merges --format=%s main | has -i 'tls'; then
  ok "un commit de merge --no-ff mentionne la branche tls"
else ko "pas de merge commit pour la feature (merge --no-ff attendu)"; fi

# --- tag et distant ------------------------------------------------------
if [ "$(g cat-file -t v1.1.0)" = tag ]; then
  ok "v1.1.0 est un tag annoté"
else ko "v1.1.0 absent ou léger (git tag -a v1.1.0 -m ...)"; fi

g merge-base --is-ancestor v1.1.0 main \
  && ok "v1.1.0 pointe dans l'historique de main" \
  || ko "v1.1.0 ne désigne pas un commit de main"

g fetch -q origin 2>/dev/null
[ "$(g rev-parse main)" = "$(g rev-parse origin/main)" ] \
  && ok "origin/main est à jour (push fait)" \
  || ko "origin/main diffère de main (git push)"

g ls-remote --tags origin 2>/dev/null | has 'refs/tags/v1.1.0$' \
  && ok "le tag v1.1.0 est sur origin" \
  || ko "le tag n'est pas poussé (git push origin v1.1.0)"

if g ls-remote --heads origin | has 'feature/tls-letsencrypt'; then
  note "la branche feature/tls-letsencrypt existe encore sur origin \
(git push origin --delete ... une fois fusionnée)"
else ok "la branche feature a été supprimée sur origin"; fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
