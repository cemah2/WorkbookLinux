#!/usr/bin/env bash
# break_M17_04.sh — panne BF17.4 : git status liste 2 000 fichiers
# Construit ~/lab17/bf4/factura-infra : le .gitignore a été supprimé par un
# commit, terraform init a rempli .terraform/, un état terraform est suivi
# par erreur. Idempotent. Bundle dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
command -v git >/dev/null || { echo "git manquant" >&2; exit 1; }

BF="$LAB_HOME/lab17/bf4"
DEPOT="$BF/factura-infra"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV" "$BF"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null TZ=Europe/Paris
c() { # c <auteur> <date> <message>
  GIT_AUTHOR_NAME=$1 GIT_AUTHOR_EMAIL="$1@lab.local" GIT_AUTHOR_DATE="$2" \
  GIT_COMMITTER_NAME=$1 GIT_COMMITTER_EMAIL="$1@lab.local" \
  GIT_COMMITTER_DATE="$2" git commit -q -m "$3"
}

rm -rf "$DEPOT"
mkdir -p "$DEPOT"; cd "$DEPOT"
git init -q -b main
git config user.name mathieu; git config user.email mathieu@lab.local
mkdir -p terraform logs
cat > .gitignore <<'EOF'
# Terraform
.terraform/
*.tfstate
*.tfstate.backup
crash.log

# journaux locaux
logs/*
!logs/.gitkeep

# éditeurs
*.swp
EOF
cat > terraform/main.tf <<'EOF'
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.60"
    }
  }
}
EOF
cat > terraform/.terraform.lock.hcl <<'EOF'
# This file is maintained automatically by "terraform init".
provider "registry.terraform.io/bpg/proxmox" {
  version     = "0.66.3"
  constraints = "~> 0.60"
}
EOF
: > logs/.gitkeep
printf '# factura-infra (extrait BF17.4)\n' > README.md
git add -A; c mathieu 2026-07-06T09:00:00+02:00 "chore: dépôt de départ"

# un état terraform commité « pour partager avec l'équipe »
cat > terraform/terraform.tfstate <<'EOF'
{
  "version": 4,
  "terraform_version": "1.9.5",
  "serial": 17,
  "outputs": {
    "pve_password": {
      "value": "Pr0xm0x-Lab-2026",
      "type": "string"
    }
  },
  "resources": []
}
EOF
git add -f terraform/terraform.tfstate
c bob 2026-07-08T15:10:00+02:00 "chore(terraform): partage l'état courant"

git bundle create -q "$SAUV/M17_04.bundle" --all

# --- la panne : .gitignore supprimé par un « nettoyage » ------------------
git rm -q .gitignore
c bob 2026-07-09T17:45:00+02:00 "chore: nettoyage des fichiers cachés"

# terraform init a rempli .terraform/ (1 900 fichiers), les journaux
# s'accumulent, l'éditeur laisse ses fichiers d'échange
P=terraform/.terraform/providers/registry.terraform.io/bpg/proxmox/0.66.3
mkdir -p "$P/linux_amd64/docs/resources" "$P/linux_amd64/docs/data-sources"
head -c 200000 /dev/urandom > "$P/linux_amd64/terraform-provider-proxmox_v0.66.3"
for i in $(seq 1 950); do
  printf 'resource doc %d\n' "$i" > "$P/linux_amd64/docs/resources/r$i.md"
  printf 'data source doc %d\n' "$i" > "$P/linux_amd64/docs/data-sources/d$i.md"
done
for i in $(seq 1 120); do
  printf '2026-07-%02d deploy ok\n' "$((i % 28 + 1))" > "logs/deploy-$i.log"
done
printf '{"version": 4, "serial": 16}\n' > terraform/terraform.tfstate.backup
sed -i 's/"serial": 17/"serial": 18/' terraform/terraform.tfstate
printf 'swap\n' > terraform/.main.tf.swp
printf 'panic: runtime error\n' > terraform/crash.log

chown -R "$LAB_USER":"$LAB_USER" "$BF"

cat <<EOF

Symptôme attendu : dans $DEPOT, git status liste
plus de 2 000 fichiers non suivis et git add -A est devenu impossible sans
embarquer tout .terraform/. Un fichier terraform.tfstate, qui contient un
mot de passe, apparaît en plus comme « modifié » à chaque terraform apply.
Objectif : un git status qui ne montre que ce qui doit être commité.
EOF
