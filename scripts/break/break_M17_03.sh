#!/usr/bin/env bash
# break_M17_03.sh — panne BF17.3 : push rejeté (non-fast-forward)
# Construit ~/lab17/bf3/ : un origin bare, un clone local avec deux commits
# non poussés, et un collègue qui a poussé entre-temps sur la même zone
# d'un fichier. Idempotent. Bundle dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
command -v git >/dev/null || { echo "git manquant" >&2; exit 1; }

BF="$LAB_HOME/lab17/bf3"
DEPOT="$BF/factura-infra"
ORIGIN="$BF/origin.git"
COLLEGUE="$BF/collegue"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV" "$BF"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null TZ=Europe/Paris
c() { # c <auteur> <date> <message>
  GIT_AUTHOR_NAME=$1 GIT_AUTHOR_EMAIL="$1@lab.local" GIT_AUTHOR_DATE="$2" \
  GIT_COMMITTER_NAME=$1 GIT_COMMITTER_EMAIL="$1@lab.local" \
  GIT_COMMITTER_DATE="$2" git commit -q -m "$3"
}

rm -rf "$DEPOT" "$ORIGIN" "$COLLEGUE"
mkdir -p "$DEPOT"; cd "$DEPOT"
git init -q -b main
git config user.name mathieu; git config user.email mathieu@lab.local
mkdir -p ansible bin
cat > ansible/inventory.ini <<'EOF'
[adm]
lab-adm  ansible_host=10.10.10.10

[web]
lab-web  ansible_host=10.10.10.11

[db]
lab-db   ansible_host=10.10.10.12

[lab:children]
adm
web
db
EOF
printf '# factura-infra (extrait BF17.3)\n' > README.md
git add -A; c mathieu 2026-07-06T09:00:00+02:00 "chore: dépôt de départ"

git clone -q --bare "$DEPOT" "$ORIGIN"
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
git remote add origin "$ORIGIN"; git fetch -q origin
git branch -q -u origin/main main
git bundle create -q "$SAUV/M17_03.bundle" --all

# --- le collègue pousse deux commits ------------------------------------
git clone -q "$ORIGIN" "$COLLEGUE"
cd "$COLLEGUE"
git config user.name alice; git config user.email alice@lab.local
python3 - <<'PY'
p='ansible/inventory.ini'; s=open(p).read()
s=s.replace('[lab:children]','[rhel]\nlab-rhel ansible_host=10.10.10.13\n\n[lab:children]')
s=s.replace('adm\nweb\ndb\n','adm\nweb\ndb\nrhel\n')
open(p,'w').write(s)
PY
git add -A; c alice 2026-07-13T10:20:00+02:00 \
  "feat(ansible): ajoute lab-rhel à l'inventaire"
printf '\n## Convention\n\nUne branche par ticket.\n' >> README.md
git add -A; c alice 2026-07-13T10:35:00+02:00 "docs(readme): convention"
git push -q origin main

# --- le clone local : deux commits non poussés, dont un sur la même zone --
cd "$DEPOT"
python3 - <<'PY'
p='ansible/inventory.ini'; s=open(p).read()
s=s.replace('[lab:children]','[ops]\nlab-ops  ansible_host=10.10.10.14\n\n[lab:children]')
s=s.replace('adm\nweb\ndb\n','adm\nweb\ndb\nops\n')
open(p,'w').write(s)
PY
git add -A; c mathieu 2026-07-13T09:50:00+02:00 \
  "feat(ansible): ajoute lab-ops à l'inventaire"
cat > bin/rotate-logs.sh <<'EOF'
#!/usr/bin/env bash
# rotate-logs.sh — archive les journaux de déploiement de plus de 7 jours
set -euo pipefail
find "${1:-/var/log/factura}" -name '*.log' -mtime +7 -exec gzip -q {} +
EOF
chmod 755 bin/rotate-logs.sh
git add -A; c mathieu 2026-07-13T11:05:00+02:00 \
  "feat(bin): rotate-logs.sh"
# un « durcissement » de config posé il y a longtemps
git config pull.ff only

chown -R "$LAB_USER":"$LAB_USER" "$BF"

cat <<EOF

Symptôme attendu : dans $DEPOT, tu as deux commits prêts
(git log origin/main..main). git push est rejeté avec « non-fast-forward »,
et git pull répond « Not possible to fast-forward, aborting ». Les deux
commits doivent arriver sur origin/main sans perdre le travail d'alice.
EOF
