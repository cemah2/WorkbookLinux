#!/usr/bin/env bash
# check_M17_02.sh — vérifie le lab L17.2 (bisect : le healthcheck cassé)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
has()  { grep "$@" >/dev/null; }   # comme grep -q, sans SIGPIPE (pipefail)
echo "== Vérification L17.2 =="

D="$HOME/lab17/factura-infra"
RAP="$HOME/lab17/rapports/bisect.md"
if ! git -C "$D" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ko "$D n'est pas un dépôt git : relance setup_M17.sh"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi
cd "$D" || exit 1
g() { git "$@" 2>/dev/null; }

[ -f .git/BISECT_LOG ] && ko "une session bisect est encore ouverte (git bisect reset)" \
                       || ok "aucune session bisect ouverte"
[ "$(g branch --show-current)" = main ] \
  && ok "tu es sur main" || ko "reviens sur main"

# le commit fautif, retrouvé dynamiquement (l'historique peut avoir été
# réécrit par L17.4)
BAD=$(g log --format=%h -S'ansible/playbooks/web.yaml' --reverse main | head -1)
[ -n "$BAD" ] && ok "commit fautif identifiable dans main : $BAD" \
              || ko "impossible de retrouver le commit qui a introduit web.yaml"

if g ls-files --error-unmatch ansible/playbooks/web.yml >/dev/null 2>&1; then
  ok "ansible/playbooks/web.yml existe toujours (le playbook n'a pas été renommé)"
else ko "web.yml a disparu : le bon correctif touche healthcheck.sh, pas le playbook"; fi

if [ -x bin/healthcheck.sh ] && bin/healthcheck.sh >/dev/null 2>&1; then
  ok "bin/healthcheck.sh répond 0 sur main"
else ko "bin/healthcheck.sh échoue encore sur main"; fi

if g show main:bin/healthcheck.sh | has 'verif_fichier'; then
  ok "la factorisation de bob est conservée (correctif ciblé, pas un revert brut)"
else
  ko "healthcheck.sh est revenu à la version d'avant : corrige la faute de \
frappe plutôt que d'annuler tout le refactor"
fi

last=$(g log -1 --format=%s -- bin/healthcheck.sh)
if printf '%s' "$last" | has -E '^fix(\([a-z-]+\))?: '; then
  ok "le correctif suit Conventional Commits : « $last »"
else ko "message du dernier commit sur healthcheck.sh : « $last » (attendu fix(...): ...)"; fi

if [ -f "$RAP" ]; then
  ok "rapport $RAP présent"
  full=$(g rev-parse "$BAD" 2>/dev/null)
  if grep -q "${BAD:-XXXX}" "$RAP" || { [ -n "$full" ] && grep -q "$full" "$RAP"; }
  then ok "le rapport cite le SHA du commit fautif"
  else ko "le rapport ne cite pas le SHA du commit fautif ($BAD)"; fi
  grep -qi 'bisect run' "$RAP" && ok "le rapport documente git bisect run" \
                              || ko "explique dans le rapport comment bisect run a été utilisé"
else ko "rapport ~/lab17/rapports/bisect.md absent"; fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
