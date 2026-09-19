#!/usr/bin/env bash
# break_M21_02.sh — panne BF21.2 : des commits « disparus » (HEAD détaché)
# Construit ~/lab21/bf2/factura-infra : deux correctifs faits pendant
# l'astreinte sur un HEAD détaché, puis un retour sur main qui les a
# rendus inaccessibles. Idempotent. Bundle dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
command -v git >/dev/null || { echo "git manquant" >&2; exit 1; }

BF="$LAB_HOME/lab21/bf2"
DEPOT="$BF/factura-infra"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV" "$BF"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null TZ=Europe/Paris
c() { # c <auteur> <date> <message>
  GIT_AUTHOR_NAME=$1 GIT_AUTHOR_EMAIL="$1@lab.local" GIT_AUTHOR_DATE="$2" \
  GIT_COMMITTER_NAME=$1 GIT_COMMITTER_EMAIL="$1@lab.local" \
  GIT_COMMITTER_DATE="$2" git commit -q "${@:4}" -m "$3"
}

rm -rf "$DEPOT"
mkdir -p "$DEPOT"; cd "$DEPOT"
git init -q -b main
git config user.name mathieu; git config user.email mathieu@lab.local
mkdir -p bin docs
cat > bin/deploy.sh <<'EOF'
#!/usr/bin/env bash
# deploy.sh — pousse la configuration vers un hôte du lab
set -euo pipefail
HOTE=${1:?usage: deploy.sh <hote>}
SRC=$(dirname $0)/../ansible/
DEST=/srv/factura-conf/

rsync -a --delete $SRC mathieu@$HOTE:$DEST
ssh mathieu@$HOTE sudo systemctl reload nginx
echo "déployé sur $HOTE"
EOF
chmod 755 bin/deploy.sh
printf '# factura-infra (extrait BF21.2)\n' > README.md
git add -A; c mathieu 2026-07-06T09:00:00+02:00 "chore: dépôt de départ"
printf '# Runbook\n\n1. bin/deploy.sh lab-web\n' > docs/runbook.md
git add -A; c mathieu 2026-07-07T10:00:00+02:00 "docs: runbook"
GIT_COMMITTER_NAME=mathieu GIT_COMMITTER_EMAIL=mathieu@lab.local \
GIT_COMMITTER_DATE=2026-07-07T10:05:00+02:00 \
  git tag -a v1.0.0 -m "Version 1.0.0"
printf '\n## 1.0.0\n\n* première mise en production\n' > CHANGELOG.md
git add -A; c alice 2026-07-09T14:20:00+02:00 "docs: changelog 1.0.0"
printf '\n2. vérifier curl -I http://factura.lab.local/\n' >> docs/runbook.md
git add -A; c alice 2026-07-10T11:00:00+02:00 "docs(runbook): vérification"

git bundle create -q "$SAUV/M21_02.bundle" --all

# --- la panne : astreinte sur un HEAD détaché, puis retour sur main -------
git switch -q --detach v1.0.0
python3 - <<'PY'
p='bin/deploy.sh'; s=open(p).read()
s=s.replace('SRC=$(dirname $0)/../ansible/','SRC="$(dirname "$0")/../ansible/"')
s=s.replace('DEST=/srv/factura-conf/','DEST="/srv/factura-conf/"')
s=s.replace('rsync -a --delete $SRC mathieu@$HOTE:$DEST',
            'rsync -a --delete "$SRC" "mathieu@$HOTE:$DEST"')
open(p,'w').write(s)
PY
git add -A; c mathieu 2026-07-11T02:14:00+02:00 \
  "fix(deploy): quote les chemins rsync (incident 2026-07-11)"
python3 - <<'PY'
p='bin/deploy.sh'; s=open(p).read()
s=s.replace('ssh mathieu@$HOTE sudo systemctl reload nginx',
            'ssh "mathieu@$HOTE" sudo nginx -t\n'
            'ssh "mathieu@$HOTE" sudo systemctl reload nginx')
open(p,'w').write(s)
PY
git add -A; c mathieu 2026-07-11T02:31:00+02:00 \
  "fix(deploy): nginx -t avant le reload"
# le lendemain : retour sur main, puis quelques allers-retours qui
# repoussent les commits dans le reflog
git switch -q main 2>/dev/null
git switch -q --detach v1.0.0
git switch -q main
printf '\n## 1.0.1\n\n* à venir\n' >> CHANGELOG.md
git add -A; c alice 2026-07-12T09:10:00+02:00 "docs: prépare 1.0.1"

chown -R "$LAB_USER":"$LAB_USER" "$BF"

cat <<EOF

Symptôme attendu : pendant l'astreinte de la nuit du 10 au 11 juillet, deux
correctifs de bin/deploy.sh ont été commités dans $DEPOT
(message d'incident « 2026-07-11 »). Ce matin, git log ne les montre pas,
git branch ne liste que main, et bin/deploy.sh sur main contient toujours
les chemins rsync non quotés. Aucune branche, aucun tag n'a été créé cette
nuit-là. Les commits doivent être retrouvés et réintégrés dans main.
EOF
