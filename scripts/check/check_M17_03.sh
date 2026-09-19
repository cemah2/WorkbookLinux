#!/usr/bin/env bash
# check_M17_03.sh — vérifie le lab L17.3 (serveur Git minimal sur lab-adm)
# À lancer sur lab-adm, en tant que mathieu.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
has()  { grep "$@" >/dev/null; }   # comme grep -q, sans SIGPIPE (pipefail)
echo "== Vérification L17.3 =="

BARE=/srv/git/factura-infra.git
DEST=/srv/factura-conf
D="$HOME/lab17/factura-infra"

if [ ! -d "$BARE" ]; then
  ko "$BARE absent (git init --bare)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi
[ "$(git -C "$BARE" rev-parse --is-bare-repository 2>/dev/null)" = true ] \
  && ok "$BARE est un dépôt bare" || ko "$BARE n'est pas bare"

[ "$(git -C "$BARE" symbolic-ref HEAD 2>/dev/null)" = refs/heads/main ] \
  && ok "HEAD du bare pointe sur main" \
  || ko "HEAD du bare ne pointe pas sur main (git symbolic-ref HEAD refs/heads/main)"

grp=$(stat -c %G "$BARE")
[ "$grp" = git ] && ok "le dépôt appartient au groupe git" \
                 || ko "groupe du dépôt : $grp (attendu git)"
if [ -g "$BARE/objects" ]; then ok "bit setgid posé sur objects/"
else ko "objects/ n'a pas le bit setgid : les objets créés par un autre \
membre auront le mauvais groupe (chmod -R g+s)"; fi
shared=$(git -C "$BARE" config core.sharedRepository 2>/dev/null)
case "$shared" in
  group|true|1|0660|660) ok "core.sharedRepository=$shared" ;;
  *) ko "core.sharedRepository non défini (git init --bare --shared=group)" ;;
esac
id -nG | has -w git && ok "$(id -un) est membre du groupe git" \
                     || ko "$(id -un) n'est pas dans le groupe git (usermod -aG git)"

H="$BARE/hooks/post-receive"
if [ -x "$H" ]; then
  ok "hook post-receive présent et exécutable"
  head -1 "$H" | has '^#!' && ok "le hook a un shebang" \
                               || ko "le hook n'a pas de shebang"
  grep -q 'refs/heads/main' "$H" && ok "le hook filtre sur refs/heads/main" \
    || ko "le hook ne filtre pas la référence poussée (il déploierait \
n'importe quelle branche)"
else ko "$H absent ou non exécutable (chmod +x)"; fi

if [ -d "$DEST" ]; then
  ok "$DEST existe"
  if git -C "$BARE" show main:ansible/inventory.ini 2>/dev/null \
     | diff -q - "$DEST/ansible/inventory.ini" >/dev/null 2>&1; then
    ok "$DEST/ansible/inventory.ini est identique à main"
  else ko "$DEST n'est pas au niveau de main : le hook n'a pas déployé"; fi
  [ -d "$DEST/.git" ] && ko "$DEST contient un .git : déploie avec git archive \
ou --work-tree, pas avec clone" || ok "$DEST est une copie de travail sans .git"
else ko "$DEST absent : rien n'a été déployé"; fi

if git -C "$D" remote get-url lab-adm 2>/dev/null | has -E 'lab-adm|10\.10\.10\.10'
then ok "le remote « lab-adm » est déclaré dans ~/lab17/factura-infra"
else note "pas de remote lab-adm dans $D (attendu si tu as poussé depuis lab-ops)"
fi

n=$(git -C "$BARE" rev-list --count main 2>/dev/null || echo 0)
[ "$n" -ge 20 ] && ok "main du bare contient l'historique complet ($n commits)" \
                || ko "main du bare n'a que $n commits"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
