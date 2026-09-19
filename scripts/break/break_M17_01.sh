#!/usr/bin/env bash
# break_M17_01.sh — panne BF17.1 : un rebase abandonné en plein conflit
# Construit ~/lab17/bf1/factura-infra (dépôt autonome, indépendant du dépôt
# principal du module) et le laisse au milieu d'un rebase mal engagé.
# Idempotent. Sauvegarde (bundle) dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
command -v git >/dev/null || { echo "git manquant" >&2; exit 1; }

BF="$LAB_HOME/lab17/bf1"
DEPOT="$BF/factura-infra"
ORIGIN="$BF/origin.git"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV" "$BF"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null TZ=Europe/Paris
c() { # c <auteur> <date> <message>
  GIT_AUTHOR_NAME=$1 GIT_AUTHOR_EMAIL="$1@lab.local" GIT_AUTHOR_DATE="$2" \
  GIT_COMMITTER_NAME=$1 GIT_COMMITTER_EMAIL="$1@lab.local" \
  GIT_COMMITTER_DATE="$2" git commit -q -m "$3"
}
TPL=ansible/roles/nginx/templates/factura.conf.j2

rm -rf "$DEPOT" "$ORIGIN"
mkdir -p "$DEPOT"; cd "$DEPOT"
git init -q -b main
git config user.name mathieu; git config user.email mathieu@lab.local
mkdir -p "$(dirname $TPL)"
cat > $TPL <<'EOF'
# {{ ansible_managed }}
events {
    worker_connections 4096;
}

http {
    server {
        listen 80;
        server_name factura.lab.local;
        root /srv/factura/public;

        location /api/ {
            proxy_pass http://127.0.0.1:8080/;
        }
    }
}
EOF
printf '# factura-infra (extrait BF17.1)\n' > README.md
git add -A; c mathieu 2026-07-06T09:00:00+02:00 "chore: dépôt de départ"

git switch -q -c feature/tls
python3 - <<'PY'
p='ansible/roles/nginx/templates/factura.conf.j2'; s=open(p).read()
s=s.replace('''        listen 80;
        server_name factura.lab.local;
        root /srv/factura/public;
''','''        listen 443 ssl;
        server_name factura.lab.local;
        root /srv/factura/public;
        ssl_certificate     /etc/letsencrypt/live/factura/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/factura/privkey.pem;
''')
open(p,'w').write(s)
PY
git add -A; c alice 2026-07-07T10:15:00+02:00 \
  "feat(nginx): écoute en 443 avec certificat Let's Encrypt"
mkdir -p ansible/roles/nginx/tasks
cat > ansible/roles/nginx/tasks/main.yml <<'EOF'
---
- name: Installe certbot
  ansible.builtin.apt:
    name: certbot
    state: present
EOF
git add -A; c alice 2026-07-07T11:40:00+02:00 "feat(nginx): tâche certbot"
printf '\n# TODO: tester le renouvellement\n' >> ansible/roles/nginx/tasks/main.yml
git add -A; c alice 2026-07-07T11:52:00+02:00 "wip"

git switch -q main
python3 - <<'PY'
p='ansible/roles/nginx/templates/factura.conf.j2'; s=open(p).read()
s=s.replace('''        root /srv/factura/public;
''','''        root /srv/factura/public;
        add_header Strict-Transport-Security "max-age=31536000" always;
        add_header X-Content-Type-Options nosniff;
''')
open(p,'w').write(s)
PY
git add -A; c mathieu 2026-07-08T09:30:00+02:00 \
  "feat(nginx): en-têtes de sécurité HSTS et nosniff"
printf '\nVoir docs/runbook.md.\n' >> README.md
git add -A; c mathieu 2026-07-08T09:45:00+02:00 "docs(readme): renvoi runbook"

# origin + sauvegarde
git clone -q --bare "$DEPOT" "$ORIGIN"
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
git remote add origin "$ORIGIN"; git fetch -q origin
git branch -q -u origin/main main
git branch -q -u origin/feature/tls feature/tls
git bundle create -q "$SAUV/M17_01.bundle" --all

# --- la panne : rebase lancé, conflit, « résolution » bâclée, abandon -----
git switch -q feature/tls
git -c core.editor=true rebase main >/dev/null 2>&1 || true
# le collègue a « résolu » en gardant les marqueurs, puis a fait git add
git add "$TPL"
printf 'reprendre le rebase lundi\n' > notes-alice.txt

chown -R "$LAB_USER":"$LAB_USER" "$BF"

cat <<EOF

Symptôme attendu : alice devait rebaser feature/tls sur main dans
$DEPOT avant de partir en congé.
Ce matin, dans ce dépôt, git status parle d'un « rebase in progress »,
git switch main refuse, le template nginx contient des lignes <<<<<<< et
>>>>>>>, et la branche feature/tls n'a toujours pas les commits HSTS de main.
Le collègue n'est pas joignable.
EOF
