#!/usr/bin/env bash
# setup_M17.sh — prépare le terrain du module 17 (Git pour l'ops)
# Se lance sans sudo (ou avec : le contenu reste la propriété de l'apprenant).
# Idempotent : relançable sans effet de bord... sauf que le dépôt
# ~/lab17/factura-infra est REMIS À ZÉRO à chaque exécution (l'historique
# doit être identique pour tout le monde : mêmes SHA, mêmes sorties).
# ~/lab17/rapports/ n'est jamais touché.
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  LAB_USER="${SUDO_USER:-root}"
else
  LAB_USER="$(id -un)"
fi
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab17"
DEPOT="$BASE/factura-infra"
REMOTE="$BASE/remote/factura-infra.git"
COLLEGUE="$BASE/collegue/factura-infra"

command -v git >/dev/null 2>&1 || { echo "git manquant : apt install git" >&2; \
  exit 1; }

echo "== Préparation du module 17 =="
echo "   utilisateur : $LAB_USER"
echo "   base        : $BASE"

# ---------------------------------------------------------------------
# 0. Déterminisme : aucune config globale/système ne doit influencer
#    l'historique généré (signature, autocrlf, hooks templates...).
# ---------------------------------------------------------------------
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_TEMPLATE_DIR=""
export TZ=Europe/Paris

# commit_as <auteur> <date ISO> <message...>
commit_as() {
  local nom=$1 date=$2; shift 2
  GIT_AUTHOR_NAME=$nom GIT_AUTHOR_EMAIL="$nom@lab.local" \
  GIT_AUTHOR_DATE="$date" \
  GIT_COMMITTER_NAME=$nom GIT_COMMITTER_EMAIL="$nom@lab.local" \
  GIT_COMMITTER_DATE="$date" \
  git commit -q "$@"
}
# tag_as <auteur> <date> <args de git tag...>
tag_as() {
  local nom=$1 date=$2; shift 2
  GIT_COMMITTER_NAME=$nom GIT_COMMITTER_EMAIL="$nom@lab.local" \
  GIT_COMMITTER_DATE="$date" git tag "$@"
}
# merge_as <auteur> <date> <args de git merge...>
merge_as() {
  local nom=$1 date=$2; shift 2
  GIT_AUTHOR_NAME=$nom GIT_AUTHOR_EMAIL="$nom@lab.local" \
  GIT_AUTHOR_DATE="$date" \
  GIT_COMMITTER_NAME=$nom GIT_COMMITTER_EMAIL="$nom@lab.local" \
  GIT_COMMITTER_DATE="$date" git merge -q "$@"
}

# ---------------------------------------------------------------------
# 1. Arborescence
# ---------------------------------------------------------------------
mkdir -p "$BASE"/{rapports,remote,collegue}
rm -rf "$DEPOT" "$REMOTE" "$COLLEGUE" "$BASE/.build"
mkdir -p "$BASE/.build"
cd "$BASE/.build"
git init -q -b main
git config user.name mathieu
git config user.email mathieu@lab.local
git config core.autocrlf false

# ---------------------------------------------------------------------
# 2. Historique de factura-infra
# ---------------------------------------------------------------------

# --- c1 : init --------------------------------------------------------
cat > README.md <<'EOF'
# factura-infra

Infrastructure as code de l'application **factura** (lab.local).

* `ansible/`   : inventaire, playbooks, rôles
* `terraform/` : VM Proxmox et réseau de lab
* `bin/`       : scripts d'exploitation (healthcheck, déploiement)
* `docs/`      : runbook
EOF
cat > .gitignore <<'EOF'
# Terraform
.terraform/
*.tfstate
*.tfstate.backup

# Ansible
*.retry

# éditeurs
*.swp
EOF
git add -A
commit_as mathieu "2026-06-01T09:12:00+02:00" \
  -m "chore: initialise le dépôt factura-infra"

# --- c2 : inventaire --------------------------------------------------
mkdir -p ansible/playbooks ansible/roles/nginx/templates
cat > ansible/inventory.ini <<'EOF'
[adm]
lab-adm  ansible_host=10.10.10.10

[web]
lab-web  ansible_host=10.10.10.11

[db]
lab-db   ansible_host=10.10.10.12

[rhel]
lab-rhel ansible_host=10.10.10.13

[ops]
lab-ops  ansible_host=10.10.10.14

[lab:children]
adm
web
db
rhel
ops
EOF
git add -A
commit_as mathieu "2026-06-02T10:03:00+02:00" \
  -m "feat(ansible): inventaire statique du lab"

# --- c3 : playbook + rôle nginx (alice) --------------------------------
cat > ansible/playbooks/web.yml <<'EOF'
---
- name: Frontal web factura
  hosts: web
  become: true
  roles:
    - nginx
EOF
cat > ansible/roles/nginx/templates/factura.conf.j2 <<'EOF'
# {{ ansible_managed }}
events {
    worker_connections 1024;
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
git add -A
commit_as alice "2026-06-03T14:41:00+02:00" \
  -m "feat(ansible): playbook web.yml et rôle nginx"

# --- c4 : healthcheck (mathieu) ---------------------------------------
mkdir -p bin
cat > bin/healthcheck.sh <<'EOF'
#!/usr/bin/env bash
# healthcheck.sh — vérifie la cohérence du dépôt avant déploiement
set -euo pipefail
cd "$(dirname "$0")/.."

rc=0
[ -f ansible/inventory.ini ] || { echo "manquant : ansible/inventory.ini"; rc=1; }
[ -f ansible/playbooks/web.yml ] || { echo "manquant : ansible/playbooks/web.yml"; rc=1; }
grep -q 'server_name factura.lab.local' \
  ansible/roles/nginx/templates/factura.conf.j2 \
  || { echo "server_name absent du template nginx"; rc=1; }

[ "$rc" -eq 0 ] && echo "healthcheck OK"
exit "$rc"
EOF
chmod 755 bin/healthcheck.sh
git add -A
commit_as mathieu "2026-06-04T09:30:00+02:00" \
  -m "feat(bin): healthcheck.sh, contrôle de cohérence du dépôt"

# --- c5 : terraform (bob) ---------------------------------------------
mkdir -p terraform
cat > terraform/main.tf <<'EOF'
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.60"
    }
  }
}

provider "proxmox" {
  endpoint = var.pve_endpoint
  insecure = true
}

resource "proxmox_virtual_environment_vm" "lab_web" {
  name      = "lab-web"
  node_name = var.pve_node
  vm_id     = 9002
}
EOF
cat > terraform/variables.tf <<'EOF'
variable "pve_endpoint" {
  type    = string
  default = "https://192.168.1.50:8006/"
}

variable "pve_node" {
  type    = string
  default = "pve"
}
EOF
git add -A
commit_as bob "2026-06-05T16:20:00+02:00" \
  -m "feat(terraform): main.tf et variables.tf pour Proxmox"

# --- c6 : fix nginx (alice) -------------------------------------------
sed -i 's/worker_connections 1024;/worker_connections 4096;/' \
  ansible/roles/nginx/templates/factura.conf.j2
git add -A
commit_as alice "2026-06-08T11:05:00+02:00" \
  -m "fix(nginx): worker_connections 1024 -> 4096"

# --- c7 : le secret commité par erreur (bob) --------------------------
cat > .env <<'EOF'
# conf locale de bob — NE PAS COMMITER
DB_HOST=10.10.10.12
DB_USER=factura
DB_PASSWORD=S3cr3t-Factura-2026!
API_KEY=AKIAIOSFODNN7EXAMPLE
EOF
git add -A
commit_as bob "2026-06-09T08:47:00+02:00" \
  -m "chore: ajoute la conf locale de dev"

# --- c8 : "retire" le secret (bob) ------------------------------------
git rm -q .env
printf '\n# conf locale\n.env\n' >> .gitignore
git add -A
commit_as bob "2026-06-09T09:02:00+02:00" \
  -m "fix: retire .env du dépôt et l'ignore"
tag_as bob "2026-06-09T09:05:00+02:00" v0.9.0

# --- branche feature/inventaire-dynamique (alice), 2 commits ----------
git switch -q -c feature/inventaire-dynamique
cat > ansible/ansible.cfg <<'EOF'
[defaults]
inventory = inventory.ini
host_key_checking = False
retry_files_enabled = False
interpreter_python = auto_silent
EOF
git add -A
commit_as alice "2026-06-10T10:15:00+02:00" \
  -m "feat(ansible): ansible.cfg avec inventaire par défaut"
cat >> ansible/inventory.ini <<'EOF'

[lab:vars]
ansible_user=mathieu
ansible_python_interpreter=/usr/bin/python3
EOF
git add -A
commit_as alice "2026-06-11T15:48:00+02:00" \
  -m "feat(ansible): variables de groupe lab"

# --- c9 sur main : runbook (mathieu) ----------------------------------
git switch -q main
mkdir -p docs
cat > docs/runbook.md <<'EOF'
# Runbook factura

## Mise en production

1. `bin/healthcheck.sh` doit répondre `healthcheck OK`.
2. `ansible-playbook -i ansible/inventory.ini ansible/playbooks/web.yml`
3. Vérifier `curl -I http://factura.lab.local/`.
EOF
git add -A
commit_as mathieu "2026-06-10T17:30:00+02:00" \
  -m "docs: runbook de mise en production"

# --- merge --no-ff (mathieu) ------------------------------------------
merge_as mathieu "2026-06-12T09:00:00+02:00" --no-ff \
  -m "Merge branch 'feature/inventaire-dynamique'" \
  feature/inventaire-dynamique
git branch -q -d feature/inventaire-dynamique

# --- c10 : deploy.sh (mathieu) ----------------------------------------
cat > bin/deploy.sh <<'EOF'
#!/usr/bin/env bash
# deploy.sh — pousse la configuration vers un hôte du lab
set -euo pipefail
HOTE=${1:?usage: deploy.sh <hote>}
SRC="$(dirname "$0")/../ansible/"
DEST="/srv/factura-conf/"

rsync -a --delete "$SRC" "mathieu@$HOTE:$DEST"
ssh "mathieu@$HOTE" sudo systemctl reload nginx
echo "déployé sur $HOTE"
EOF
chmod 755 bin/deploy.sh
git add -A
commit_as mathieu "2026-06-15T14:10:00+02:00" \
  -m "feat(bin): deploy.sh, déploiement par rsync"
tag_as mathieu "2026-06-15T14:15:00+02:00" -a v1.0.0 \
  -m "Version 1.0.0 — première mise en production"

# --- branche hotfix/ansible-timeout (bob), depuis v1.0.0 --------------
git switch -q -c hotfix/ansible-timeout
printf 'timeout = 30\nforks = 10\n' >> ansible/ansible.cfg
git add -A
commit_as bob "2026-06-19T18:22:00+02:00" \
  -m "fix(ansible): timeout SSH 30 s et 10 forks"
git switch -q main

# --- c11 : LE commit qui casse le healthcheck (bob) -------------------
cat > bin/healthcheck.sh <<'EOF'
#!/usr/bin/env bash
# healthcheck.sh — vérifie la cohérence du dépôt avant déploiement
set -euo pipefail
cd "$(dirname "$0")/.."

rc=0
verif_fichier() {
  [ -f "$1" ] || { echo "manquant : $1"; rc=1; }
}
verif_motif() {
  grep -q "$1" "$2" || { echo "motif absent : $1 ($2)"; rc=1; }
}

for f in ansible/inventory.ini ansible/ansible.cfg \
         ansible/playbooks/web.yaml bin/deploy.sh; do
  verif_fichier "$f"
done
verif_motif 'server_name factura.lab.local' \
  ansible/roles/nginx/templates/factura.conf.j2

[ "$rc" -eq 0 ] && echo "healthcheck OK"
exit "$rc"
EOF
git add -A
commit_as bob "2026-06-18T10:40:00+02:00" \
  -m "refactor(healthcheck): factorise les vérifications"

# --- c12 : terraform réseau (bob) -------------------------------------
cat > terraform/network.tf <<'EOF'
resource "proxmox_virtual_environment_network_linux_bridge" "vmbr1" {
  node_name = var.pve_node
  name      = "vmbr1"
  comment   = "réseau de lab 10.10.10.0/24"
}
EOF
git add -A
commit_as bob "2026-06-20T11:00:00+02:00" \
  -m "feat(terraform): bridge vmbr1 du réseau de lab"

# --- c13 : changelog (alice) ------------------------------------------
cat > CHANGELOG.md <<'EOF'
# Changelog

## 1.0.0 — 2026-06-15

* première mise en production
* déploiement par `bin/deploy.sh`
EOF
git add -A
commit_as alice "2026-06-22T09:25:00+02:00" \
  -m "docs: changelog 1.0.0"

# --- c14 : fix deploy (mathieu) ---------------------------------------
cat > bin/deploy.sh <<'EOF'
#!/usr/bin/env bash
# deploy.sh — pousse la configuration vers un hôte du lab
set -euo pipefail
HOTE=${1:?usage: deploy.sh <hote> [--vraiment]}
SRC="$(dirname "$0")/../ansible/"
DEST="/srv/factura-conf/"

opts=(-a --delete)
[ "${2:-}" = "--vraiment" ] || opts+=(--dry-run -v)

rsync "${opts[@]}" "$SRC" "mathieu@$HOTE:$DEST"
if [ "${2:-}" = "--vraiment" ]; then
  ssh "mathieu@$HOTE" sudo systemctl reload nginx
  echo "déployé sur $HOTE"
else
  echo "simulation terminée ; relance avec --vraiment pour déployer"
fi
EOF
git add -A
commit_as mathieu "2026-06-25T16:05:00+02:00" \
  -m "fix(deploy): rsync --delete en simulation par défaut"

# --- c15 : .gitattributes (mathieu) -----------------------------------
cat > .gitattributes <<'EOF'
* text=auto eol=lf
*.sh text eol=lf
*.png binary
*.tar.gz binary
EOF
git add -A
commit_as mathieu "2026-06-26T09:10:00+02:00" \
  -m "chore: .gitattributes, fins de ligne LF et binaires"

# --- c16 : HSTS (alice) — touche la zone que feature/tls modifiera ----
python3 - <<'PY'
p='ansible/roles/nginx/templates/factura.conf.j2'
s=open(p).read()
s=s.replace('''        root /srv/factura/public;
''','''        root /srv/factura/public;
        add_header Strict-Transport-Security "max-age=31536000" always;
        add_header X-Content-Type-Options nosniff;
''')
open(p,'w').write(s)
PY
git add -A
commit_as alice "2026-06-29T13:37:00+02:00" \
  -m "feat(nginx): en-têtes de sécurité HSTS et nosniff"

# --- c17 : rollback dans le runbook (mathieu) -------------------------
cat >> docs/runbook.md <<'EOF'

## Rollback

1. `git switch --detach <tag précédent>`
2. `bin/deploy.sh lab-web --vraiment`
3. Ouvrir un ticket post-mortem.
EOF
git add -A
commit_as mathieu "2026-07-01T10:00:00+02:00" \
  -m "docs(runbook): procédure de rollback"

# --- branche feature/tls-letsencrypt (alice) depuis c14 ---------------
git switch -q -c feature/tls-letsencrypt "main~3"
python3 - <<'PY'
p='ansible/roles/nginx/templates/factura.conf.j2'
s=open(p).read()
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
git add -A
commit_as alice "2026-07-02T09:15:00+02:00" \
  -m "feat(nginx): écoute en 443 avec certificat Let's Encrypt"
cat > ansible/roles/nginx/tasks_certbot.yml <<'EOF'
---
- name: Installe certbot
  ansible.builtin.apt:
    name: certbot
    state: present
EOF
git add -A
commit_as alice "2026-07-02T11:40:00+02:00" -m "wip"
sed -i 's/Installe certbot/Installe certbot (paquet Ubuntu)/' \
  ansible/roles/nginx/tasks_certbot.yml
git add -A
commit_as alice "2026-07-02T11:52:00+02:00" -m "fix typo"
cat >> ansible/roles/nginx/tasks_certbot.yml <<'EOF'

- name: Active le renouvellement automatique
  ansible.builtin.systemd:
    name: certbot.timer
    enabled: true
    state: started
EOF
git add -A
commit_as alice "2026-07-03T10:05:00+02:00" \
  -m "feat(nginx): renouvellement automatique par certbot.timer"
git switch -q main

# ---------------------------------------------------------------------
# 3. Dépôt distant (bare) + clone de travail + clone « collègue »
# ---------------------------------------------------------------------
cd "$BASE"
git clone -q --bare "$BASE/.build" "$REMOTE"
git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
rm -rf "$BASE/.build"

git clone -q "$REMOTE" "$DEPOT"
cd "$DEPOT"
git config user.name mathieu
git config user.email mathieu@lab.local
git switch -q -c feature/tls-letsencrypt origin/feature/tls-letsencrypt
git switch -q -c hotfix/ansible-timeout origin/hotfix/ansible-timeout
git switch -q main

# le collègue (alice) pousse un commit que le clone local n'a pas encore
git clone -q "$REMOTE" "$COLLEGUE"
cd "$COLLEGUE"
git config user.name alice
git config user.email alice@lab.local
printf '\nVoir aussi `docs/runbook.md` avant toute mise en production.\n' \
  >> README.md
git add -A
commit_as alice "2026-07-03T16:20:00+02:00" \
  -m "docs(readme): renvoi vers le runbook"
git push -q origin main

# ---------------------------------------------------------------------
# 4. Bruit non suivi dans le clone de travail (exercices .gitignore)
# ---------------------------------------------------------------------
cd "$DEPOT"
mkdir -p terraform/.terraform/providers/registry.terraform.io/bpg/proxmox
printf 'lock\n' > terraform/.terraform/providers/lock.json
printf '{"version": 4}\n' > terraform/terraform.tfstate
printf 'lab-web\n' > ansible/playbooks/web.retry
mkdir -p logs
: > logs/.gitkeep
printf '2026-07-03 deploy lab-web ok\n' > logs/deploy.log
printf 'brouillon\n' > ansible/notes-perso.txt
printf 'swap\n' > .README.md.swp

# ---------------------------------------------------------------------
# 5. Propriétaire final
# ---------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ] && [ "$LAB_USER" != root ]; then
  chown -R "$LAB_USER":"$LAB_USER" "$BASE"
fi

for outil in git-filter-repo shellcheck yamllint; do
  command -v "$outil" >/dev/null 2>&1 || \
    echo "  note : $outil n'est pas installé (voir §17.1)"
done

cat <<EOF

Prêt. Points d'entrée :
  $DEPOT            dépôt de travail (branche main, 1 commit en retard)
  $REMOTE   « origin » : dépôt bare local
  $COLLEGUE  clone d'alice, pour simuler un collègue
  $BASE/rapports/                 tes livrables (jamais effacé)

Branches : main, feature/tls-letsencrypt, hotfix/ansible-timeout
Tags     : v0.9.0 (léger), v1.0.0 (annoté)
EOF
