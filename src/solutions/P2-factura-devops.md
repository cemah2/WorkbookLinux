# Projet B — Corrigé

Ce corrigé donne une **solution de référence** pour Factura v2 : ce n'est pas
la seule possible, les checks vérifient le résultat et pas la méthode. Chaque
jalon rappelle l'énoncé en une ligne, donne les commandes dans l'ordre, les
fichiers **complets** tels qu'ils vivent dans le mono-repo, puis les blocs
`::: pourquoi` sur les choix d'architecture et `::: piege` sur ce qui casse le
plus souvent. Les incidents (B.3) sont traités commande par commande.

Conventions du corrigé :

* le dépôt est `~/factura-v2` sur `lab-adm`, tout chemin relatif part de là ;
* Gitea est `http://lab-ops.lab.local:3000`, le registre
  `lab-ops.lab.local:3000/mathieu/` ;
* les mots de passe d'exemple sont `Stg-Db-2026`, `Stg-Redis-2026` (staging),
  `Prd-Db-2026`, `Prd-Redis-2026` (prod), `Ops-Grafana-2026` (Grafana).
  Ils ne vivent qu'en clair dans ce document : dans le dépôt ils sont dans
  des `vault.yml` chiffrés ;
* `~/.local/bin` (pipx) est dans le `PATH` : `pre-commit`, `ansible-*`.

Arborescence finale du dépôt, pour s'y retrouver :

```
factura-v2/
  .gitea/workflows/   ci.yaml  cd-prod.yaml  restore-test.yaml
  .pre-commit-config.yaml  .gitleaks.toml  .yamllint  .ansible-lint
  .gitignore  .editorconfig  Makefile  README.md
  app/                api/ worker/ nginx/ sql/ compose.yaml
  infra/              *.tf  templates/  envs/{staging,prod,k3s}.tfvars
  infra/monitoring/   compose.yaml prometheus/ alertmanager/ grafana/
                      loki/ blackbox/ alert-sink/
  ansible/            ansible.cfg requirements.yml
    inventory/        ops.ini  ci/{staging,prod}.ini  group_vars/
                      (staging.ini prod.ini k3s.ini : générés, ignorés)
    playbooks/        baseline.yml deploy.yml monitoring.yml backup.yml
                      restore.yml k3s.yml k8s-secret.yml
    roles/            common ssh_hardening firewall chrony
                      unattended_upgrades node_exporter promtail docker
                      factura_compose pg_backup k3s
  k8s/                namespace configmap postgres redis api worker
                      service ingress hpa  (secret.yaml : ignoré)
  docs/               journal.md runbook-deploy.md slo.md
                      compose-vs-k3s.md rebuild-<date>.log scan-*.txt
                      incidents/
  tools/              smoke.sh rebuild.sh make-template.sh
                      check-commit-msg.sh check-inventory.sh
```

---

## B.2 Jalons — corrigé

### **PB.1** — Mono-repo sur Gitea, hooks et convention

*Versionner `~/factura-v2`, le pousser sur Gitea, installer des hooks
`pre-commit` qui bloquent secrets et fautes de lint, et un hook `commit-msg`
qui impose `type(scope): sujet`.*

**1. Le dépôt sur Gitea, par l'API**

```bash
GITEA=http://lab-ops.lab.local:3000
read -rs -p 'mot de passe Gitea : ' GP; echo
curl -fsS -u "mathieu:$GP" -X POST "$GITEA/api/v1/user/repos" \
  -H 'Content-Type: application/json' \
  -d '{"name":"factura","private":true,"default_branch":"main",
       "description":"Factura v2 - infra + app"}' | jq .clone_url
# clé publique de lab-adm sur le compte Gitea (une fois)
curl -fsS -u "mathieu:$GP" -X POST "$GITEA/api/v1/user/keys" \
  -H 'Content-Type: application/json' \
  -d "{\"title\":\"mathieu@lab-adm\",\"key\":\"$(cat ~/.ssh/id_ed25519.pub)\"}" \
  >/dev/null
unset GP
```

**2. Initialisation locale et hooks**

```bash
cd ~/factura-v2
git init -b main
git config user.name "Mathieu"; git config user.email "mathieu@lab.local"
git remote add origin ssh://git@lab-ops.lab.local:2222/mathieu/factura.git
# (port 2222 = SSH du conteneur Gitea du module 21 ; sinon HTTP :
#  http://lab-ops.lab.local:3000/mathieu/factura.git)
```

`.pre-commit-config.yaml` (remplace le squelette) :

```yaml
# Hooks du mono-repo Factura v2 (PB.1). Installer :
#   pre-commit install --hook-type pre-commit --hook-type commit-msg
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: end-of-file-fixer
      - id: trailing-whitespace
        args: [--markdown-linebreak-ext=md]
      - id: check-merge-conflict
      - id: check-added-large-files
        args: [--maxkb=512]
      - id: check-yaml
        args: [--allow-multiple-documents]
        exclude: ^(infra/monitoring/grafana/dashboards/|k8s/)

  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.4
    hooks:
      - id: gitleaks
        args: [--config=.gitleaks.toml]

  - repo: https://github.com/shellcheck-py/shellcheck-py
    rev: v0.10.0.1
    hooks:
      - id: shellcheck
        files: ^(tools/.*\.sh|ansible/roles/.*/(files|templates)/.*\.sh(\.j2)?)$
        args: [-x, -S, warning]

  - repo: https://github.com/adrienverge/yamllint
    rev: v1.35.1
    hooks:
      - id: yamllint
        args: [-c, .yamllint, --strict]

  - repo: https://github.com/ansible/ansible-lint
    rev: v24.7.0
    hooks:
      - id: ansible-lint
        files: ^ansible/
        additional_dependencies: [ansible-core>=2.16]

  - repo: local
    hooks:
      - id: commit-msg-convention
        name: "message de commit type(scope): sujet"
        entry: tools/check-commit-msg.sh
        language: script
        stages: [commit-msg]
      - id: tofu-fmt
        name: tofu fmt -check
        entry: tofu fmt -check -recursive infra/
        language: system
        files: \.tf$
        pass_filenames: false
```

`tools/check-commit-msg.sh` :

```bash
#!/usr/bin/env bash
# check-commit-msg.sh — hook commit-msg : impose type(scope): sujet
# Types acceptés : feat fix chore docs ci infra refactor test
set -euo pipefail
MSG_FILE="${1:?fichier du message}"
FIRST=$(grep -v '^#' "$MSG_FILE" | sed -n '1p')
RE='^(feat|fix|chore|docs|ci|infra|refactor|test)(\([a-z0-9._/-]+\))?!?: .{3,72}$'
case "$FIRST" in
  Merge*|Revert*|fixup!*|squash!*) exit 0 ;;
esac
if ! printf '%s\n' "$FIRST" | grep -qE "$RE"; then
  cat >&2 <<EOF
Message de commit refusé : "$FIRST"
Format attendu : type(scope): sujet   (scope optionnel, sujet 3-72 car.)
Types : feat fix chore docs ci infra refactor test
Exemple : infra(tofu): ajoute le workspace prod
EOF
  exit 1
fi
```

Compléments au `.gitignore` fourni (le squelette couvre déjà `*.tfstate`,
`terraform.tfvars`, `.vault-pass`, `ansible/inventory/*.ini`) :

```gitignore
# PB.2 : état par workspace (tofu) et snippets rendus localement
infra/terraform.tfstate.d/
# PB.10 : secret k8s généré depuis le vault
k8s/secret.yaml
k8s/*-tls.{crt,key}
# kubeconfig et rapports temporaires
*.kubeconfig
```

Installation et premier passage :

```bash
chmod 0755 tools/check-commit-msg.sh
pre-commit install --hook-type pre-commit --hook-type commit-msg
pre-commit run --all-files        # première fois : télécharge les hooks
```

**3. Commits atomiques et push**

```bash
git add .gitignore .editorconfig .yamllint .gitleaks.toml .ansible-lint
git commit -m "chore(repo): squelette et configuration des linters"
git add .pre-commit-config.yaml tools/check-commit-msg.sh
git commit -m "ci(hooks): pre-commit, gitleaks, shellcheck, commit-msg"
git add app/
git commit -m "feat(app): API, worker et stack Compose de dev fournis"
git add infra/ ansible/ k8s/ docs/ Makefile README.md tools/
git commit -m "chore(repo): arborescence infra, ansible, k8s, docs"
printf '# Journal de bord\n\n## %s — PB.1\n\n' "$(date +%F)" \
  > docs/journal.md
git add docs/journal.md
git commit -m "docs(journal): ouverture du journal de bord"
git push -u origin main
```

**4. Preuves demandées**

Le faux token (format réel d'un token Proxmox : `user@realm!nom=uuid`) :

```bash
echo 'pve_api_token = "tofu@pve!factura=3f1c2a9e-8b7d-4e21-9c55-0a1b2c3d4e5f"' \
  >> infra/terraform.tfvars.example
git add -f infra/terraform.tfvars.example
git commit -m "infra(tofu): exemple de tfvars"
#   gitleaks.................Failed
#   - hook id: gitleaks
#   Finding: pve_api_token = "tofu@pve!factura=3f1c2a9e-8b7d-...
#   Secret: 3f1c2a9e-8b7d-4e21-9c55-0a1b2c3d4e5f   RuleID: generic-api-key
git reset HEAD infra/terraform.tfvars.example; rm infra/terraform.tfvars.example
```

Le message hors convention :

```bash
git commit --allow-empty -m "update stuff"
#   Message de commit refusé : "update stuff"
#   Format attendu : type(scope): sujet ...
```

Ces deux sorties vont dans `docs/journal.md`. La protection de `main` par
l'API (le statut requis `ci / build` n'existe qu'à PB.6, on la prépare) :

```bash
curl -fsS -u mathieu -X POST \
  "$GITEA/api/v1/repos/mathieu/factura/branch_protections" \
  -H 'Content-Type: application/json' \
  -d '{"branch_name":"main","enable_push":true,"enable_force_push":false,
       "enable_status_check":false,"status_check_contexts":["ci / build"],
       "block_on_rejected_reviews":true}'
```

`README.md` reçoit une section « Comment vérifier » (`make lint`, le chemin
des checks) et un tableau « qui fait quoi » (toi : infra, devs : `app/`).

::: pourquoi
**Un hook local par `language: script` plutôt que commitlint** : commitlint
demande Node et une configuration, pour vérifier une expression régulière.
Le script Bash est lu par tout le monde, testé par shellcheck (il est dans
`tools/`), et il tourne sans réseau. `stages: [commit-msg]` fait que
pre-commit l'installe dans `.git/hooks/commit-msg` et l'appelle avec le
fichier du message en argument — c'est le contrat de Git.

**gitleaks en hook ET dans la CI (PB.6)** : le hook protège le poste du dev
consciencieux ; la CI protège contre `git commit --no-verify` et contre le
collègue qui n'a pas installé les hooks. Le `.gitleaks.toml` fourni met en
liste blanche les `vault.yml` (leur contenu chiffré ressemble à de
l'entropie, donc à un secret) et `devpass` (mot de passe de démonstration de
`compose.yaml`). La règle : la liste blanche décrit des **chemins** ou des
**valeurs de démo connues**, jamais un motif large comme `password`.

**`tofu fmt -check` en hook `system`** : il utilise le binaire du poste
(pas de dépôt de hooks à télécharger) ; il ne corrige pas, il refuse, pour
que le dev lance `tofu fmt` lui-même et voie ce qui change.

**Cinq commits au lieu d'un** : `git bisect`, `git revert` et la revue
travaillent sur des commits ; un commit « tout le projet » n'est ni
révocable ni lisible. Le type en tête (`infra`, `ci`, `docs`) permet plus
tard de générer un changelog (`git log --grep='^feat'`) et de faire
tourner des règles (une PR `infra(...)` demande une relecture de l'admin).
:::

::: piege
* `pre-commit install` seul n'installe **pas** le hook `commit-msg` :
  sans `--hook-type commit-msg`, `update stuff` passe. Le check regarde
  `.git/hooks/commit-msg`.
* Le hook `ansible-lint` de pre-commit tourne dans un venv isolé, sans
  les collections installées sur le poste : `additional_dependencies`
  doit contenir `ansible-core`, et le `.ansible-lint` exclut `app/`,
  `infra/`, `k8s/` (sinon il lit les manifestes k8s comme des playbooks).
* Un secret commité puis « supprimé » au commit suivant est **toujours dans
  l'historique** (`git log -p`, `gitleaks detect`). La seule réponse est
  la révocation du secret ; la réécriture d'historique (`git filter-repo`)
  ne fait que nettoyer les traces. Le check lance `gitleaks detect` sur
  tout l'historique : un secret ancien fait échouer PB.1 même si `HEAD`
  est propre.
* `yamllint --strict` transforme les avertissements en erreurs : la clé
  `on:` des workflows déclenche `truthy` — le `.yamllint` fourni autorise
  `on` (`allowed-values: ["true", "false", "on"]`), ne l'enlève pas.
:::

---

### **PB.2** — OpenTofu, cloud-init, deux environnements identiques

*Une configuration OpenTofu (provider bpg/proxmox) qui crée `web` et `db`
d'un environnement depuis le template 9000, appliquée dans deux workspaces
`staging` et `prod`, qui génère l'inventaire Ansible ; plan vide après
apply.*

**1. Le token, hors Git**

Sur Proxmox (une fois, shell du nœud) :

```bash
pveum user add tofu@pve --comment "OpenTofu Factura"
pveum role add TofuFactura -privs "VM.Allocate VM.Clone VM.Config.CDROM \
VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType \
VM.Config.Memory VM.Config.Network VM.Config.Options VM.Audit \
VM.PowerMgmt VM.Monitor VM.Snapshot Datastore.AllocateSpace \
Datastore.AllocateTemplate Datastore.Audit SDN.Use Sys.Audit"
pveum acl modify / -user tofu@pve -role TofuFactura
pveum user token add tofu@pve factura --privsep 0
# full-tokenid : tofu@pve!factura   value : 6d2f...-...   (affiché une fois)
```

Sur `lab-adm` :

```bash
install -d -m 0700 ~/.config/factura
cat > ~/.config/factura/pve.env <<'EOF'
export TF_VAR_pve_api_token=\
'tofu@pve!factura=6d2f0e6a-1234-4c9a-9b1e-0f0e0d0c0b0a'
EOF
chmod 0600 ~/.config/factura/pve.env
source ~/.config/factura/pve.env
# clé de mathieu@lab-adm acceptée par root@pve (snippets par SSH)
ssh-copy-id root@10.10.10.1
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519
```

**2. Les fichiers `infra/`**

`infra/versions.tf` :

```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
```

`infra/providers.tf` :

```hcl
provider "proxmox" {
  endpoint  = var.pve_endpoint
  api_token = var.pve_api_token
  insecure  = true # certificat auto-signé du lab

  # Les snippets cloud-init sont déposés sur le nœud par SSH (pas d'API
  # pour /var/lib/vz/snippets) : clé de mathieu@lab-adm acceptée par root.
  ssh {
    agent    = true
    username = "root"
    node {
      name    = var.pve_node
      address = "10.10.10.1"
    }
  }
}
```

`infra/variables.tf` :

```hcl
variable "pve_endpoint" {
  type    = string
  default = "https://10.10.10.1:8006"
}

variable "pve_node" {
  type    = string
  default = "pve"
}

variable "pve_api_token" {
  description = "Token API Proxmox : user@realm!name=uuid (TF_VAR_pve_api_token)"
  type        = string
  sensitive   = true
  validation {
    condition     = can(regex("^[^!]+![^=]+=[0-9a-f-]{36}$", var.pve_api_token))
    error_message = "Format attendu : tofu@pve!factura=<uuid>."
  }
}

variable "template_id" {
  type    = number
  default = 9000
}

variable "datastore" {
  type    = string
  default = "local-lvm"
}

variable "snippets_datastore" {
  type    = string
  default = "local"
}

variable "bridge" {
  type    = string
  default = "vmbr1"
}

variable "ssh_public_key_file" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "vms" {
  description = "VM de l'environnement, indexées par rôle (web, db, k3s)"
  type = map(object({
    vm_id  = number
    host   = number # dernier octet de 10.10.10.x
    cores  = optional(number, 2)
    memory = optional(number, 2048)
    disk   = optional(number, 20)
    name   = optional(string) # surcharge du nom dérivé du workspace
  }))
  validation {
    condition = alltrue([
      for k, v in var.vms : v.vm_id >= 9021 && v.vm_id <= 9049
    ])
    error_message = "vm_id doit être entre 9021 et 9049 (plage du projet)."
  }
  validation {
    condition = alltrue([
      for k, v in var.vms : v.host >= 20 && v.host <= 49
    ])
    error_message = "host (dernier octet) doit être entre 20 et 49."
  }
  validation {
    condition = (length(distinct([for k, v in var.vms : v.vm_id]))
      == length(var.vms))
    error_message = "Deux VM ont le même vm_id."
  }
}
```

`infra/locals.tf` :

```hcl
locals {
  env = terraform.workspace

  vm_names = {
    for k, v in var.vms : k => coalesce(v.name, "factura-${local.env}-${k}")
  }
  vm_ips = {
    for k, v in var.vms : k => cidrhost("10.10.10.0/24", v.host)
  }
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_file)))
}
```

`infra/cloud-init.tf` :

```hcl
resource "proxmox_virtual_environment_file" "user_data" {
  for_each = var.vms

  content_type = "snippets"
  datastore_id = var.snippets_datastore
  node_name    = var.pve_node

  source_raw {
    # file_name unique par VM : deux VM ne partagent jamais un user-data
    file_name = "${local.vm_names[each.key]}-user-data.yaml"
    data = templatefile("${path.module}/templates/user-data.yaml.tftpl", {
      hostname       = local.vm_names[each.key]
      ssh_public_key = local.ssh_public_key
    })
  }
}
```

`infra/templates/user-data.yaml.tftpl` :

```yaml
#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.lab.local
manage_etc_hosts: true
timezone: Europe/Paris
users:
  - name: mathieu
    groups: [sudo]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: true
    ssh_authorized_keys:
      - ${ssh_public_key}
ssh_pwauth: false
package_update: true
packages:
  - qemu-guest-agent
runcmd:
  - systemctl enable --now qemu-guest-agent
```

`infra/main.tf` :

```hcl
resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

  name        = local.vm_names[each.key]
  vm_id       = each.value.vm_id
  node_name   = var.pve_node
  description = "Factura ${local.env}/${each.key} - géré par OpenTofu"
  tags        = ["factura", local.env, each.key]
  on_boot     = true

  clone {
    vm_id = var.template_id
    full  = true
  }

  agent {
    enabled = true
    timeout = "5m"
  }

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.datastore
    interface    = "scsi0"
    size         = each.value.disk
    discard      = "on"
    iothread     = true
    file_format  = "raw"
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  initialization {
    datastore_id = var.datastore
    ip_config {
      ipv4 {
        address = "${local.vm_ips[each.key]}/24"
        gateway = "10.10.10.1"
      }
    }
    dns {
      servers = ["10.10.10.1"]
      domain  = "lab.local"
    }
    user_data_file_id = proxmox_virtual_environment_file.user_data[each.key].id
  }

  lifecycle {
    precondition {
      condition     = terraform.workspace != "default"
      error_message = <<-EOT
        Le workspace default ne crée rien :
        tofu workspace select staging|prod|k3s
      EOT
    }
    # Attributs normalisés par Proxmox après création (journal PB.2)
    ignore_changes = [
      network_device[0].mac_address,
      initialization[0].user_account,
    ]
  }
}
```

`infra/inventory.tf` :

```hcl
resource "local_file" "inventory" {
  filename        = "${path.module}/../ansible/inventory/${local.env}.ini"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/inventory.ini.tftpl", {
    env = local.env
    hosts = {
      for k, v in var.vms : k => {
        name = local.vm_names[k]
        ip   = local.vm_ips[k]
      }
    }
  })
}
```

`infra/templates/inventory.ini.tftpl` :

```ini
# Inventaire GÉNÉRÉ par OpenTofu (workspace ${env}) - ne pas éditer
%{ for role, h in hosts ~}
[${env}_${role}]
${h.name} ansible_host=${h.ip}

%{ endfor ~}
%{ for role, h in hosts ~}
[${role}:children]
${env}_${role}

%{ endfor ~}
[${env}:children]
%{ for role, h in hosts ~}
${env}_${role}
%{ endfor ~}

[${env}:vars]
factura_env=${env}

[all:vars]
ansible_user=mathieu
```

`infra/outputs.tf` :

```hcl
output "vm_ips" {
  description = "nom de VM -> IP"
  value       = { for k, v in var.vms : local.vm_names[k] => local.vm_ips[k] }
}

output "inventory_file" {
  value = local_file.inventory.filename
}
```

`infra/envs/staging.tfvars` :

```hcl
vms = {
  web = { vm_id = 9021, host = 21 }
  db  = { vm_id = 9022, host = 22, disk = 30 }
}
```

`infra/envs/prod.tfvars` :

```hcl
vms = {
  web = { vm_id = 9031, host = 31 }
  db  = { vm_id = 9032, host = 32, disk = 30 }
}
```

`diff infra/envs/staging.tfvars infra/envs/prod.tfvars` : deux lignes,
quatre nombres.

**3. Apply, deux fois**

```bash
cd ~/factura-v2/infra
tofu init
tofu fmt -recursive && tofu validate
tofu workspace new staging
time tofu apply -var-file=envs/staging.tfvars      # ~3 à 4 min
tofu plan -detailed-exitcode -var-file=envs/staging.tfvars; echo "rc=$?"
tofu workspace new prod
tofu apply -var-file=envs/prod.tfvars
tofu plan -detailed-exitcode -var-file=envs/prod.tfvars; echo "rc=$?"
tofu workspace select default && tofu state list   # vide
tofu workspace select staging
cat ../ansible/inventory/staging.ini
ssh mathieu@10.10.10.21 'hostname; cloud-init status; timedatectl | grep zone'
```

Inventaire généré (`ansible/inventory/staging.ini`) :

```ini
# Inventaire GÉNÉRÉ par OpenTofu (workspace staging) - ne pas éditer
[staging_db]
factura-staging-db ansible_host=10.10.10.22

[staging_web]
factura-staging-web ansible_host=10.10.10.21

[db:children]
staging_db

[web:children]
staging_web

[staging:children]
staging_db
staging_web

[staging:vars]
factura_env=staging

[all:vars]
ansible_user=mathieu
```

Temps mesuré pour référence (PB.9) : `apply` staging complet **3 min 40 s**
(clone plein 2 × 40 s, boot + cloud-init `package_update` +
`qemu-guest-agent` ≈ 1 min 30 par VM, en parallèle). Note-le dans le journal.

::: pourquoi
**Un workspace par environnement, un seul code** : le workspace ne change
que le fichier d'état (`terraform.tfstate.d/<ws>/`). Le nom des VM, le nom
des snippets et le chemin de l'inventaire dérivent de `terraform.workspace`,
donc deux environnements ne peuvent pas se marcher dessus, et un
troisième (`k3s`, PB.10) coûte un `.tfvars`. La `precondition` sur
`default` ferme la porte à l'accident classique : `tofu apply` lancé avant
`workspace select`, qui créerait `factura-default-web`.

**`for_each` sur une `map(object)` avec `optional()`** : la clé (`web`,
`db`) est stable, donc retirer `db` ne recrée pas `web` (ce que `count`
ferait). Les `optional(type, défaut)` gardent les `.tfvars` minimaux :
tout ce qui est commun est un défaut dans `variables.tf`, tout ce qui
diffère est dans `envs/`. C'est ce qui rend le `diff` de deux lignes
possible. Les `validation` refusent un VMID hors de la plage réservée
**avant** de parler à Proxmox.

**Un snippet par VM, rendu par `templatefile`** : `--cicustom` remplace le
user-data généré par Proxmox, donc `user_account` n'a plus d'effet (d'où
son `ignore_changes`). `ip_config` et `dns`, eux, vont dans le
`network-config` que Proxmox génère toujours : c'est pourquoi on garde l'IP
dans le HCL et l'utilisateur dans le snippet. Le `file_name` contient le
nom de la VM : deux VM avec le même snippet auraient le même `hostname`.

**Le user-data minimal** : cloud-init ne rejoue les modules *per-instance*
qu'au premier boot. Tout ce qu'on y met est **non rejouable** sans
recréer la VM ; tout ce qu'Ansible fait est rejouable à volonté. Le
partage des rôles est donc : cloud-init pose l'identité (hostname, compte,
clé, agent) ; Ansible fait le reste. `package_upgrade: true` ajouterait
2 à 5 minutes au boot et une dépendance au miroir Ubuntu du jour : c'est
`unattended-upgrades` (PB.3) qui gère les mises à jour, dans le temps.

**Le token en `TF_VAR_`** : il n'est ni dans le code, ni dans un fichier
du dépôt, ni dans un output. Il finit quand même dans l'état (`sensitive`
masque l'affichage, pas le JSON) : c'est la raison pour laquelle
`*.tfstate` et `terraform.tfstate.d/` sont ignorés par Git, et l'argument
du bonus « backend distant chiffré ».
:::

::: piege
* `Error: ... failed to upload snippet ... permission denied` : le
  provider n'a pas pu se connecter en SSH au nœud. Vérifie `ssh
  root@10.10.10.1 true` depuis `lab-adm` **avec l'agent chargé** (le
  bloc `ssh { agent = true }` lit `SSH_AUTH_SOCK`) et que `local` accepte
  les snippets (`pvesm status`, `pvesm set local --content ...,snippets`).
* Plan non vide après apply : trois coupables sur bpg. `mac_address`
  (Proxmox en génère une, le code n'en donne pas), `user_account` (ignoré
  à cause du snippet mais lu dans la config), et `disk.size` si le
  template a un disque de 20 Go et que tu demandes 20 : mets une valeur
  strictement supérieure ou identique au template, jamais inférieure.
  Ajoute à `ignore_changes` seulement ce que tu as **compris**, et écris
  pourquoi dans le journal : c'est noté.
* `cloud-init status` → `error` avec `Invalid cloud-config` : le rendu du
  template contient une clé `${...}` non fournie, ou la première ligne n'est
  pas exactement `#cloud-config` (sans espace). `cloud-init schema
  --config-file` sur `/var/lib/cloud/instance/user-data.txt` dit tout.
* Le provider attend l'IP via l'agent QEMU : si le template 9000 a été
  créé sans `--agent enabled=1`, ou si le user-data n'installe pas
  `qemu-guest-agent`, `apply` bloque 5 minutes puis échoue. Avec `agent {
  timeout = "5m" }` l'échec est explicite au lieu de l'attente par défaut
  (15 min).
* `tofu destroy` dans le mauvais workspace détruit le mauvais
  environnement. Le `Makefile` fait toujours `workspace select $(ENV)`
  avant : utilise-le (`make infra-plan ENV=prod`), pas `tofu` à la main.
:::

---

### **PB.3** — Baseline Ansible

*Transformer les procédures manuelles du projet A (comptes, SSH, ufw, NTP,
mises à jour, node_exporter, journaux) en rôles Ansible appliqués aux quatre
VM par `baseline.yml`, avec `changed=0` au second passage.*

**1. Collections et configuration**

`ansible/requirements.yml` (le squelette + `community.crypto` pour PB.9) :

```yaml
collections:
  - name: community.docker
    version: ">=3.10.0"
  - name: community.general
    version: ">=9.0.0"
  - name: ansible.posix
    version: ">=1.5.0"
  - name: community.postgresql
    version: ">=3.4.0"
  - name: community.crypto
    version: ">=2.20.0"
```

```bash
cd ~/factura-v2/ansible
ansible-galaxy collection install -r requirements.yml -p collections
ansible -i inventory/staging.ini all -m ping
```

`ansible/ansible.cfg` est celui du squelette (`inventory = inventory/
staging.ini` par défaut, `roles_path = roles`, `vault_password_file =
../.vault-pass`, `pipelining`). Le `.vault-pass` n'existe qu'à PB.5 : tant
qu'aucun fichier chiffré n'est lu, Ansible ne s'en plaint pas.

**2. Variables de groupe**

`ansible/inventory/group_vars/all/main.yml` :

```yaml
# Variables communes à tous les environnements
lab_domain: lab.local
lab_admin_ip: 10.10.10.10
lab_ops_ip: 10.10.10.14
registry: lab-ops.lab.local:3000
registry_namespace: mathieu

# Résolution locale : outillage + VM de l'environnement (rôle common)
common_static_hosts:
  - { ip: "{{ lab_admin_ip }}", name: lab-adm }
  - { ip: "{{ lab_ops_ip }}", name: lab-ops }

# Compte de déploiement utilisé par le runner CI (sans sudo)
deploy_user: deploy
deploy_uid: 1500
deploy_authorized_keys:
  - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExempleCleDuRunner runner@lab-ops"
  - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExempleCleDeMathieu mathieu@lab-adm"
# Comptes humains ajoutés au groupe docker (diagnostic sans sudo)
common_docker_admins: [mathieu]

# Pare-feu : règles communes (le rôle applique common + group)
firewall_rules_common:
  - { port: 22, src: "{{ lab_admin_ip }}", comment: "ssh lab-adm" }
  - { port: 22, src: "{{ lab_ops_ip }}", comment: "ssh runner CI" }
  - { port: 9100, src: "{{ lab_ops_ip }}", comment: "node_exporter" }
firewall_rules_group: []
firewall_docker_rules: []

chrony_servers: ["10.10.10.1"]
chrony_pools: ["2.ubuntu.pool.ntp.org"]

node_exporter_textfile_dir: /var/lib/prometheus/node-exporter
node_exporter_textfile_group: "{{ deploy_user }}"

promtail_version: "3.4.2"
promtail_loki_url: "http://{{ lab_ops_ip }}:3100/loki/api/v1/push"
promtail_scrape_docker: true
promtail_scrape_pods: false

docker_insecure_registries: ["{{ registry }}"]
baseline_docker: true
```

`ansible/inventory/group_vars/web/main.yml` :

```yaml
# VM web : nginx :80, API bleue/verte :8081/:8082, exporters
firewall_rules_group:
  - { port: 80, src: 10.10.10.0/24, comment: "application" }
  - { port: 8081, src: "{{ lab_admin_ip }}", comment: "api-blue direct" }
  - { port: 8081, src: "{{ lab_ops_ip }}", comment: "api-blue scrape/CI" }
  - { port: 8082, src: "{{ lab_admin_ip }}", comment: "api-green direct" }
  - { port: 8082, src: "{{ lab_ops_ip }}", comment: "api-green scrape/CI" }
  - { port: 9121, src: "{{ lab_ops_ip }}", comment: "redis_exporter" }
  - { port: 9200, src: "{{ lab_ops_ip }}", comment: "worker metrics" }
# Ports publiés par Docker : filtrés dans DOCKER-USER (sources autorisées)
firewall_docker_rules:
  - { port: 8081, src: "{{ lab_admin_ip }}" }
  - { port: 8081, src: "{{ lab_ops_ip }}" }
  - { port: 8082, src: "{{ lab_admin_ip }}" }
  - { port: 8082, src: "{{ lab_ops_ip }}" }
  - { port: 9121, src: "{{ lab_ops_ip }}" }
  - { port: 9200, src: "{{ lab_ops_ip }}" }
```

`ansible/inventory/group_vars/db/main.yml` :

```yaml
# VM db : PostgreSQL pour la VM web du même environnement, exporter
factura_web_ip: "{{ hostvars[groups[factura_env ~ '_web'][0]].ansible_host }}"
firewall_rules_group:
  - { port: 5432, src: "{{ factura_web_ip }}", comment: "postgres web" }
  - { port: 9187, src: "{{ lab_ops_ip }}", comment: "postgres_exporter" }
firewall_docker_rules:
  - { port: 5432, src: "{{ factura_web_ip }}" }
  - { port: 9187, src: "{{ lab_ops_ip }}" }
```

**3. Le playbook**

`ansible/playbooks/baseline.yml` :

```yaml
---
# Baseline : amène une VM neuve (PB.2) à l'état "prête pour Factura".
# Rejouable : changed=0 au second passage.
- name: Baseline des VM Factura
  hosts: all
  become: true
  gather_facts: true
  roles:
    - role: common
    - role: ssh_hardening
    - role: firewall
    - role: chrony
    - role: unattended_upgrades
    - role: node_exporter
    - role: promtail
    - role: docker
      when: baseline_docker | bool
```

**4. Les rôles**

`ansible/roles/common/defaults/main.yml` :

```yaml
common_packages: [curl, jq, rsync, ca-certificates, unzip]
common_static_hosts: []
deploy_user: deploy
deploy_uid: 1500
deploy_authorized_keys: []
common_docker_admins: []
journald_max_use: 200M
journald_max_file: 50M
```

`ansible/roles/common/tasks/main.yml` :

```yaml
---
- name: Paquets utiles
  ansible.builtin.apt:
    name: "{{ common_packages }}"
    state: present
    update_cache: true
    cache_valid_time: 3600

- name: Groupe docker (créé avant le paquet pour y placer deploy)
  ansible.builtin.group:
    name: docker
    state: present

- name: Compte de déploiement (sans sudo)
  ansible.builtin.user:
    name: "{{ deploy_user }}"
    uid: "{{ deploy_uid }}"
    shell: /bin/bash
    groups: [docker]
    append: true
    create_home: true
    comment: "Deploiement Factura (runner CI)"

- name: Clés autorisées du compte deploy
  ansible.posix.authorized_key:
    user: "{{ deploy_user }}"
    key: "{{ deploy_authorized_keys | join('\n') }}"
    exclusive: true

- name: Comptes humains dans le groupe docker
  ansible.builtin.user:
    name: "{{ item }}"
    groups: [docker]
    append: true
  loop: "{{ common_docker_admins }}"

- name: Arborescence applicative appartenant à deploy
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: "{{ deploy_user }}"
    group: "{{ deploy_user }}"
    mode: "0750"
  loop:
    - /srv/factura
    - /srv/factura/backups

- name: /etc/hosts - outillage et VM de l'environnement
  ansible.builtin.blockinfile:
    path: /etc/hosts
    marker: "# {mark} ANSIBLE FACTURA"
    block: |
      {% for h in common_static_hosts %}
      {{ h.ip }} {{ h.name }} {{ h.name }}.{{ lab_domain }}
      {% endfor %}
      {% for h in groups[factura_env] | default([]) | sort %}
      {{ hostvars[h].ansible_host }} {{ h }} {{ h }}.{{ lab_domain }}
      {% endfor %}

- name: Journal systemd persistant et borné
  ansible.builtin.copy:
    dest: /etc/systemd/journald.conf.d/50-factura.conf
    owner: root
    group: root
    mode: "0644"
    content: |
      [Journal]
      Storage=persistent
      SystemMaxUse={{ journald_max_use }}
      SystemMaxFileSize={{ journald_max_file }}
      MaxRetentionSec=1month
      Compress=yes
  notify: Restart journald

- name: Répertoire du journal persistant
  ansible.builtin.file:
    path: /var/log/journal
    state: directory
    owner: root
    group: systemd-journal
    mode: "2755"
```

`ansible/roles/common/handlers/main.yml` :

```yaml
---
- name: Restart journald
  ansible.builtin.systemd:
    name: systemd-journald
    state: restarted
```

`ansible/roles/ssh_hardening/defaults/main.yml` :

```yaml
sshd_allow_users: [mathieu, "{{ deploy_user }}"]
sshd_max_auth_tries: 3
```

`ansible/roles/ssh_hardening/tasks/main.yml` :

```yaml
---
- name: Fragment sshd durci (validé par sshd -t avant écriture)
  ansible.builtin.template:
    src: 50-factura.conf.j2
    dest: /etc/ssh/sshd_config.d/50-factura.conf
    owner: root
    group: root
    mode: "0644"
    validate: /usr/sbin/sshd -t -f %s
  notify: Restart sshd

- name: Aucun fragment concurrent ne réactive le mot de passe
  ansible.builtin.file:
    path: /etc/ssh/sshd_config.d/50-cloud-init.conf
    state: absent
  notify: Restart sshd
```

`ansible/roles/ssh_hardening/templates/50-factura.conf.j2` :

```
# {{ ansible_managed }} - durcissement SSH Factura
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
X11Forwarding no
MaxAuthTries {{ sshd_max_auth_tries }}
AllowUsers {{ sshd_allow_users | join(' ') }}
ClientAliveInterval 300
ClientAliveCountMax 2
```

`ansible/roles/ssh_hardening/handlers/main.yml` :

```yaml
---
- name: Restart sshd
  ansible.builtin.systemd:
    name: ssh
    state: restarted
```

`ansible/roles/firewall/defaults/main.yml` :

```yaml
# Le rôle ne connaît aucun port : il applique des listes.
firewall_rules_common: []
firewall_rules_group: []
firewall_docker_rules: []
firewall_external_iface: "{{ ansible_default_ipv4.interface }}"
```

`ansible/roles/firewall/tasks/main.yml` :

```yaml
---
- name: Paquet ufw
  ansible.builtin.apt:
    name: ufw
    state: present

- name: Politique par défaut (entrant refusé, sortant autorisé)
  community.general.ufw:
    direction: "{{ item.dir }}"
    policy: "{{ item.policy }}"
  loop:
    - { dir: incoming, policy: deny }
    - { dir: outgoing, policy: allow }

- name: Règles entrantes (communes + groupe)
  community.general.ufw:
    rule: allow
    direction: in
    proto: tcp
    to_port: "{{ item.port | string }}"
    from_ip: "{{ item.src }}"
    comment: "{{ item.comment | default(omit) }}"
  loop: "{{ firewall_rules_common + firewall_rules_group }}"
  loop_control:
    label: "{{ item.port }} <- {{ item.src }}"

- name: Chaîne DOCKER-USER - filtrage des ports publiés par Docker
  ansible.builtin.blockinfile:
    path: /etc/ufw/after.rules
    marker: "# {mark} ANSIBLE DOCKER-USER"
    insertafter: EOF
    block: "{{ lookup('ansible.builtin.template', 'docker-user.rules.j2') }}"
  notify: Reload ufw

- name: ufw actif au démarrage
  community.general.ufw:
    state: enabled
```

`ansible/roles/firewall/templates/docker-user.rules.j2` :

```
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
-A DOCKER-USER ! -i {{ firewall_external_iface }} -j RETURN
{% for r in firewall_docker_rules %}
-A DOCKER-USER -p tcp -m conntrack --ctorigdstport {{ r.port }} \
  -s {{ r.src }} -j RETURN
{% endfor %}
{% for p in firewall_docker_rules | map(attribute='port') | unique %}
-A DOCKER-USER -p tcp -m conntrack --ctorigdstport {{ p }} -j DROP
{% endfor %}
-A DOCKER-USER -j RETURN
COMMIT
```

`ansible/roles/firewall/handlers/main.yml` :

```yaml
---
- name: Reload ufw
  community.general.ufw:
    state: reloaded
```

`ansible/roles/chrony/defaults/main.yml` :

```yaml
chrony_servers: []
chrony_pools: ["2.ubuntu.pool.ntp.org"]
```

`ansible/roles/chrony/tasks/main.yml` :

```yaml
---
- name: Paquet chrony
  ansible.builtin.apt:
    name: chrony
    state: present

- name: Sources de temps
  ansible.builtin.template:
    src: factura.sources.j2
    dest: /etc/chrony/sources.d/factura.sources
    owner: root
    group: root
    mode: "0644"
  notify: Restart chrony

- name: chrony actif
  ansible.builtin.systemd:
    name: chrony
    state: started
    enabled: true
```

`ansible/roles/chrony/templates/factura.sources.j2` :

```
# {{ ansible_managed }}
{% for s in chrony_servers %}
server {{ s }} iburst
{% endfor %}
{% for p in chrony_pools %}
pool {{ p }} iburst maxsources 2
{% endfor %}
```

`ansible/roles/chrony/handlers/main.yml` :

```yaml
---
- name: Restart chrony
  ansible.builtin.systemd:
    name: chrony
    state: restarted
```

`ansible/roles/unattended_upgrades/tasks/main.yml` (pas de `defaults`
nécessaires) :

```yaml
---
- name: Paquet unattended-upgrades
  ansible.builtin.apt:
    name: unattended-upgrades
    state: present

- name: Activation (20auto-upgrades)
  ansible.builtin.copy:
    dest: /etc/apt/apt.conf.d/20auto-upgrades
    owner: root
    group: root
    mode: "0644"
    content: |
      APT::Periodic::Update-Package-Lists "1";
      APT::Periodic::Unattended-Upgrade "1";
      APT::Periodic::AutocleanInterval "7";

- name: Politique - sécurité seulement, pas de reboot automatique
  ansible.builtin.copy:
    dest: /etc/apt/apt.conf.d/52factura-unattended
    owner: root
    group: root
    mode: "0644"
    content: |
      Unattended-Upgrade::Allowed-Origins {
        "${distro_id}:${distro_codename}-security";
        "${distro_id}ESMApps:${distro_codename}-apps-security";
        "${distro_id}ESM:${distro_codename}-infra-security";
      };
      Unattended-Upgrade::Automatic-Reboot "false";
      Unattended-Upgrade::Remove-Unused-Dependencies "true";
      Unattended-Upgrade::Package-Blacklist { "docker.io"; "containerd"; };

- name: Timers apt actifs
  ansible.builtin.systemd:
    name: "{{ item }}"
    state: started
    enabled: true
  loop: [apt-daily.timer, apt-daily-upgrade.timer]
```

`ansible/roles/node_exporter/defaults/main.yml` :

```yaml
node_exporter_textfile_dir: /var/lib/prometheus/node-exporter
node_exporter_textfile_group: deploy
```

`ansible/roles/node_exporter/tasks/main.yml` :

```yaml
---
- name: Paquet prometheus-node-exporter
  ansible.builtin.apt:
    name: prometheus-node-exporter
    state: present

- name: Options - textfile collector
  ansible.builtin.copy:
    dest: /etc/default/prometheus-node-exporter
    owner: root
    group: root
    mode: "0644"
    content: |
      ARGS="--collector.textfile.directory={{ node_exporter_textfile_dir }} \
      --web.listen-address=:9100"
  notify: Restart node_exporter

- name: Répertoire du textfile collector (écriture pour deploy)
  ansible.builtin.file:
    path: "{{ node_exporter_textfile_dir }}"
    state: directory
    owner: root
    group: "{{ node_exporter_textfile_group }}"
    mode: "2775"

- name: node_exporter actif
  ansible.builtin.systemd:
    name: prometheus-node-exporter
    state: started
    enabled: true
```

`ansible/roles/node_exporter/handlers/main.yml` :

```yaml
---
- name: Restart node_exporter
  ansible.builtin.systemd:
    name: prometheus-node-exporter
    state: restarted
```

`ansible/roles/promtail/defaults/main.yml` :

```yaml
promtail_version: "3.4.2"
promtail_loki_url: "http://10.10.10.14:3100/loki/api/v1/push"
promtail_scrape_docker: true      # conteneurs Docker (web, db)
promtail_scrape_pods: false       # /var/log/pods (k3s, PB.10)
promtail_http_port: 9080
```

`ansible/roles/promtail/tasks/main.yml` :

```yaml
---
- name: Compte promtail (journal + docker)
  ansible.builtin.user:
    name: promtail
    system: true
    shell: /usr/sbin/nologin
    create_home: false
    groups: >-
      {{ ['systemd-journal', 'adm']
         + (['docker'] if promtail_scrape_docker else []) }}
    append: true

- name: Binaire promtail (version épinglée)
  ansible.builtin.unarchive:
    src: >-
      https://github.com/grafana/loki/releases/download/v{{
      promtail_version }}/promtail-linux-amd64.zip
    dest: /usr/local/bin
    remote_src: true
    creates: /usr/local/bin/promtail-linux-amd64
    mode: "0755"

- name: Lien /usr/local/bin/promtail
  ansible.builtin.file:
    src: /usr/local/bin/promtail-linux-amd64
    dest: /usr/local/bin/promtail
    state: link

- name: Répertoires de configuration et de positions
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: promtail
    group: promtail
    mode: "0750"
  loop: [/etc/promtail, /var/lib/promtail]

- name: Configuration promtail
  ansible.builtin.template:
    src: promtail.yml.j2
    dest: /etc/promtail/promtail.yml
    owner: root
    group: promtail
    mode: "0640"
  notify: Restart promtail

- name: Unité systemd durcie
  ansible.builtin.template:
    src: promtail.service.j2
    dest: /etc/systemd/system/promtail.service
    owner: root
    group: root
    mode: "0644"
  notify: Restart promtail

- name: promtail actif
  ansible.builtin.systemd:
    name: promtail
    state: started
    enabled: true
    daemon_reload: true
```

`ansible/roles/promtail/templates/promtail.yml.j2` :

```yaml
# {{ ansible_managed }}
server:
  http_listen_port: {{ promtail_http_port }}
  grpc_listen_port: 0
positions:
  filename: /var/lib/promtail/positions.yaml
clients:
  - url: {{ promtail_loki_url }}
scrape_configs:
  - job_name: journal
    journal:
      json: false
      max_age: 12h
      labels:
        job: systemd-journal
        host: {{ inventory_hostname }}
        env: {{ factura_env }}
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: unit
      - source_labels: ['__journal_priority_keyword']
        target_label: level
{% if promtail_scrape_docker %}
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 15s
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: container
      - source_labels:
          - __meta_docker_container_label_com_docker_compose_service
        target_label: service
      - replacement: {{ inventory_hostname }}
        target_label: host
      - replacement: {{ factura_env }}
        target_label: env
      - replacement: docker
        target_label: job
{% endif %}
{% if promtail_scrape_pods %}
  - job_name: pods
    static_configs:
      - targets: [localhost]
        labels:
          job: k8s-pods
          host: {{ inventory_hostname }}
          env: {{ factura_env }}
          __path__: /var/log/pods/*/*/*.log
    pipeline_stages:
      - cri: {}
    relabel_configs:
      - source_labels: ['__path__']
        regex: '/var/log/pods/([^_]+)_([^_]+)_[^/]+/([^/]+)/.*'
        replacement: '$1'
        target_label: namespace
      - source_labels: ['__path__']
        regex: '/var/log/pods/([^_]+)_([^_]+)_[^/]+/([^/]+)/.*'
        replacement: '$2'
        target_label: pod
      - source_labels: ['__path__']
        regex: '/var/log/pods/([^_]+)_([^_]+)_[^/]+/([^/]+)/.*'
        replacement: '$3'
        target_label: container
{% endif %}
```

`ansible/roles/promtail/templates/promtail.service.j2` :

```ini
[Unit]
Description=Promtail - envoi des journaux vers Loki
After=network-online.target docker.service
Wants=network-online.target

[Service]
User=promtail
Group=promtail
{% if promtail_scrape_pods %}
# /var/log/pods est à root (containerd) : lecture via capacité ciblée
AmbientCapabilities=CAP_DAC_READ_SEARCH
{% endif %}
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail.yml
Restart=on-failure
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/var/lib/promtail
ProtectKernelTunables=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
LockPersonality=yes
MemoryMax=256M

[Install]
WantedBy=multi-user.target
```

`ansible/roles/promtail/handlers/main.yml` :

```yaml
---
- name: Restart promtail
  ansible.builtin.systemd:
    name: promtail
    state: restarted
    daemon_reload: true
```

`ansible/roles/docker/defaults/main.yml` :

```yaml
docker_insecure_registries: []
docker_log_max_size: 20m
docker_log_max_file: "5"
```

`ansible/roles/docker/tasks/main.yml` :

```yaml
---
- name: Paquets Docker et Compose v2 (dépôts Ubuntu)
  ansible.builtin.apt:
    name: [docker.io, docker-compose-v2]
    state: present

- name: daemon.json
  ansible.builtin.copy:
    dest: /etc/docker/daemon.json
    owner: root
    group: root
    mode: "0644"
    content: "{{ docker_daemon | to_nice_json }}\n"
  vars:
    docker_daemon:
      insecure-registries: "{{ docker_insecure_registries }}"
      log-driver: json-file
      log-opts:
        max-size: "{{ docker_log_max_size }}"
        max-file: "{{ docker_log_max_file }}"
      live-restore: true
      iptables: true
  notify: Restart docker

- name: Docker actif
  ansible.builtin.systemd:
    name: docker
    state: started
    enabled: true
```

`ansible/roles/docker/handlers/main.yml` :

```yaml
---
- name: Restart docker
  ansible.builtin.systemd:
    name: docker
    state: restarted
```

**5. Exécution et preuves**

```bash
cd ~/factura-v2
ansible-lint ansible/playbooks/baseline.yml
for e in staging prod; do
  ansible-playbook -i ansible/inventory/$e.ini ansible/playbooks/baseline.yml
done
# second passage : changed=0
ansible-playbook -i ansible/inventory/staging.ini ansible/playbooks/baseline.yml \
  | tail -n 4
ansible-playbook -i ansible/inventory/staging.ini ansible/playbooks/baseline.yml \
  --check --diff | grep -c '^changed' || true      # 0
```

```
PLAY RECAP *******************************************************************
factura-staging-db : ok=41  changed=0  unreachable=0  failed=0  skipped=0
factura-staging-web: ok=41  changed=0  unreachable=0  failed=0  skipped=0
```

Tests demandés :

```bash
ssh deploy@10.10.10.21 docker ps          # marche (clé mathieu@lab-adm)
ssh deploy@10.10.10.21 sudo true          # "deploy is not in the sudoers file"
nc -zv -w2 10.10.10.22 5432               # timed out (même après PB.5)
ssh mathieu@10.10.10.21 'sudo iptables -S DOCKER-USER'
```

Le test qui prouve que Docker contourne ufw **sans** `DOCKER-USER` : sur
le staging, `docker run -d -p 9999:80 nginx:1.27-alpine` puis depuis
`lab-rhel` (10.10.10.13, hors de toute règle) `curl -m2 10.10.10.21:9999`
→ répond. Ajoute `{ port: 9999, src: 10.10.10.10 }` à
`firewall_docker_rules`, rejoue, `curl` expire. Retire la règle et le
conteneur. Journal.

::: pourquoi
**Les listes de règles dans `group_vars`, pas dans le rôle** : le rôle
`firewall` est réutilisable tel quel pour `k3s` (PB.10), pour `lab-ops` ou
pour le projet suivant. Ansible ne **fusionne pas** les listes entre
`group_vars/all` et `group_vars/web` (la plus précise remplace l'autre),
d'où deux variables `firewall_rules_common` + `firewall_rules_group` que le
rôle concatène. `hash_behaviour=merge` ferait la même chose de façon
implicite et globale : déconseillé, et interdit par `ansible-lint`.

**`DOCKER-USER`** : Docker écrit ses règles de NAT dans `PREROUTING` et de
filtrage dans `FORWARD` (chaîne `DOCKER`), après avoir sauté dans
`DOCKER-USER`. ufw ne travaille que dans `INPUT` (`ufw-user-input`), donc
un paquet destiné à un port publié est DNATé vers le conteneur, traverse
`FORWARD` et n'est jamais vu par les règles ufw. `DOCKER-USER` est le point
d'accroche officiel : vide par défaut, évalué en premier, jamais réécrit
par Docker. Le motif `--ctorigdstport` compare le **port d'origine** (avant
DNAT), donc les règles parlent des ports publiés (5432, 8081), pas des
ports internes. `! -i ens18 -j RETURN` laisse passer le trafic entre
conteneurs et le trafic sortant. Publier sur `10.10.10.22:5432` en plus
(PB.5) réduit la surface (pas de 0.0.0.0) mais ne filtre pas la source :
c'est un plus, pas un substitut.

**`validate: /usr/sbin/sshd -t -f %s` sur le template** : Ansible écrit
le rendu dans un fichier temporaire, lance `sshd -t` dessus, et ne remplace
le fichier réel que si la commande renvoie 0. Un mot-clé inconnu ou une
faute de frappe ne coupe jamais SSH — l'équivalent du `sshd -t &&
systemctl restart` du projet A, mais impossible à oublier.

**`50-cloud-init.conf` supprimé** : sur les images cloud Ubuntu, cloud-init
dépose un fragment `PasswordAuthentication no` (bien) mais un fragment
concurrent peut réactiver le mot de passe selon l'ordre lexical. Un seul
fragment, sous notre contrôle, et `sshd -T` (config effective) pour
vérifier — c'est ce que fait le check.

**Promtail avec `docker_sd_configs`** : lire le socket Docker donne les
journaux de tous les conteneurs avec leurs labels Compose (service,
projet), sans dépendre des chemins `/var/lib/docker/containers/*`. Le
compte `promtail` dans `docker` a un accès équivalent à root sur l'hôte
(le socket) : l'unité systemd durcie limite les dégâts (`ProtectSystem=
strict`, pas de home, mémoire bornée). Sur k3s (PB.10), pas de socket :
`promtail_scrape_pods` bascule sur `/var/log/pods` avec le parseur `cri`.

**`live-restore: true`** : un redémarrage du démon Docker (mise à jour du
paquet, restart du rôle) ne tue pas les conteneurs. C'est ce qui permet
de rejouer la baseline en journée sans coupure de Factura.
:::

::: piege
* `changed=1` sur `blockinfile` `/etc/hosts` à chaque passage : le
  bloc contient une liste non triée (`groups[...]` n'a pas d'ordre
  garanti). Le `| sort` est là pour ça. Même chose pour tout template
  qui itère sur un `dict` ou un `set`.
* `unarchive` avec `remote_src` et sans `creates:` retélécharge le zip à
  chaque run et marque `changed`. Le `creates:` sur le binaire rend la
  tâche idempotente ; changer `promtail_version` demande alors de
  supprimer l'ancien binaire (ou d'inclure la version dans le nom —
  amélioration possible).
* `community.general.ufw` avec `to_port: 22` (entier) déclenche un
  `changed` permanent sur certaines versions : `| string`.
* Le paquet Ubuntu `prometheus-node-exporter` lit `ARGS` dans
  `/etc/default/prometheus-node-exporter` ; une ligne `ARGS=` sur deux
  lignes sans `\` casse le service silencieusement (`systemctl status`
  montre `exit-code`).
* `AllowUsers mathieu deploy` sans `deploy` : le runner CI ne pourra plus
  se connecter à PB.7 et le message sera un laconique « Permission denied
  (publickey) ». `sshd -T | grep allowusers` avant de chercher côté clé.
* L'ordre des rôles compte : `common` crée le groupe `docker` et
  `/srv/factura` avant `docker` ; `firewall` ouvre 9100 avant que
  `node_exporter` écoute. Inverser fait passer le premier run mais pas
  le check.
:::

---

### **PB.4** — Conteneurisation et stack Compose de dev

*Images `factura-api` et `factura-worker` multi-stage, non-root, avec
healthcheck et version injectée au build, de moins de 250 Mo, scannées par
trivy ; `compose.yaml` de dev complet.*

**1. Relecture du `Dockerfile` fourni — ce qui manquait**

Le squelette de `app/api/Dockerfile` est presque bon. Trois manques, un
ajout :

* `app/worker/.dockerignore` **absent** (l'API en a un, pas le worker) :
  `__pycache__` du poste du dev entre dans l'image et fait varier le
  digest d'un build à l'autre.
* Worker : pas de `--start-period` sur le `HEALTHCHECK`, pas de
  `PYTHONDONTWRITEBYTECODE`.
* Aucun label OCI : `docker inspect` d'une image en prod doit dire quel
  commit l'a produite (INC-B1 en dépend).
* Ajout : `STOPSIGNAL SIGTERM` explicite pour Gunicorn (documentaire, mais
  c'est la question d'entretien : pourquoi pas `SIGQUIT` ? parce que
  `SIGTERM` = arrêt gracieux dans Gunicorn, `SIGINT`/`SIGQUIT` = arrêt
  rapide).

`app/api/Dockerfile` :

```dockerfile
# Factura API — multi-stage, non-root, healthcheck (PB.4)
# --- étage 1 : construction du venv (compilateurs, cache pip) ---------
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN python -m venv /venv \
 && /venv/bin/pip install --no-cache-dir --upgrade pip \
 && /venv/bin/pip install --no-cache-dir -r requirements.txt

# --- étage 2 : image d'exécution (venv copié, rien d'autre) -----------
FROM python:3.12-slim AS runtime
ARG APP_VERSION=dev
ARG VCS_REF=unknown
LABEL org.opencontainers.image.title="factura-api" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="http://lab-ops.lab.local:3000/mathieu"
ENV APP_VERSION=${APP_VERSION} \
    PATH=/venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
RUN groupadd -g 10001 app \
 && useradd -u 10001 -g app -M -s /usr/sbin/nologin app
COPY --from=builder /venv /venv
WORKDIR /app
COPY --chown=app:app app.py .
USER app
EXPOSE 8000
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request,sys; \
sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/version',\
timeout=2).status==200 else 1)"
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", \
     "--access-logfile", "-", "--graceful-timeout", "20", "app:app"]
```

`app/worker/Dockerfile` :

```dockerfile
# Factura worker — multi-stage, non-root, healthcheck sur :9200 (PB.4)
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN python -m venv /venv \
 && /venv/bin/pip install --no-cache-dir --upgrade pip \
 && /venv/bin/pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim AS runtime
ARG APP_VERSION=dev
ARG VCS_REF=unknown
LABEL org.opencontainers.image.title="factura-worker" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"
ENV APP_VERSION=${APP_VERSION} \
    PATH=/venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
RUN groupadd -g 10001 app \
 && useradd -u 10001 -g app -M -s /usr/sbin/nologin app
COPY --from=builder /venv /venv
WORKDIR /app
COPY --chown=app:app worker.py .
USER app
EXPOSE 9200
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; \
urllib.request.urlopen('http://127.0.0.1:9200/',timeout=2)"
CMD ["python", "worker.py"]
```

`app/api/.dockerignore` et `app/worker/.dockerignore` (identiques) :

```
tests/
__pycache__/
*.pyc
.pytest_cache/
.git
*.md
```

**2. Build, test, mesure**

```bash
cd ~/factura-v2/app
docker build --build-arg APP_VERSION=dev \
  --build-arg VCS_REF="$(git rev-parse --short HEAD)" \
  -t factura-api:dev api
docker build --build-arg APP_VERSION=dev -t factura-worker:dev worker
docker image ls factura-api:dev factura-worker:dev
#  factura-api      dev   ...   168MB
#  factura-worker   dev   ...   161MB
docker run -d --rm --name t -p 8000:8000 -e DATABASE_URL=x factura-api:dev
sleep 3; curl -s :8000/version
#  {"app":"factura-api","color":"none","version":"dev"}
docker inspect -f '{{.Config.User}} {{.State.Health.Status}}' t
#  app healthy
docker exec t id                        # uid=10001(app) gid=10001(app)
docker stop t
docker history factura-api:dev | head -5   # la couche COPY /venv ≈ 55 Mo
```

**3. `compose.yaml` de dev**

Celui du squelette respecte déjà le cahier des charges (services, healthcheck
`pg_isready`, `depends_on` conditionnel, aucun port publié pour postgres et
redis, `${DB_PASSWORD:-devpass}`, `APP_VERSION` en `args`). Une seule
correction : l'API doit être `healthy` avant que nginx démarre, ce qui
demande le `start_period` de l'image (fait) et un `healthcheck` côté
Compose pour redis, sinon `condition: service_started` ne dit rien.

```yaml
# Stack de développement Factura v2 (poste dev / lab-ops) — PB.4
name: factura-dev
services:
  nginx:
    image: nginx:1.27-alpine
    ports: ["8080:80"]
    volumes:
      - ./nginx/dev.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      api: { condition: service_healthy }
  api:
    build:
      context: ./api
      args: { APP_VERSION: "${APP_VERSION:-dev}" }
    environment:
      DATABASE_URL: postgresql://factura:${DB_PASSWORD:-devpass}@postgres:5432/factura
      REDIS_URL: redis://redis:6379/0
      APP_COLOR: dev
    depends_on:
      postgres: { condition: service_healthy }
      redis: { condition: service_healthy }
  worker:
    build:
      context: ./worker
      args: { APP_VERSION: "${APP_VERSION:-dev}" }
    environment:
      DATABASE_URL: postgresql://factura:${DB_PASSWORD:-devpass}@postgres:5432/factura
      REDIS_URL: redis://redis:6379/0
    depends_on:
      postgres: { condition: service_healthy }
      redis: { condition: service_healthy }
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: factura
      POSTGRES_PASSWORD: ${DB_PASSWORD:-devpass}
      POSTGRES_DB: factura
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./sql/init.sql:/docker-entrypoint-initdb.d/10-init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U factura -d factura"]
      interval: 5s
      timeout: 3s
      retries: 10
  redis:
    image: redis:7-alpine
    command: ["redis-server", "--save", "", "--appendonly", "no"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 2s
      retries: 5
volumes:
  pgdata: {}
```

```bash
docker compose up -d --build
curl -s :8080/health                  # {"db":"ok",...,"status":"ok"}
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"client":"ACME","montant_ht":100}' :8080/api/factures
#  {"id":6,"montant_ttc":120.0,"statut":"nouvelle"}   (201)
docker compose logs worker | tail -1
#  {"ts":"...","level":"INFO","logger":"factura.worker",
#   "msg":"facture traitée","id":6}
docker compose logs api | grep -c '"GET /health'      # JSON, une ligne/requête
docker compose down -v && docker compose up -d
curl -s :8080/api/factures | jq length               # 5 (init.sql rejoué)
```

**4. Scan et tests**

```bash
trivy image --severity HIGH,CRITICAL --ignore-unfixed \
  factura-api:dev | tee ~/factura-v2/docs/scan-api.txt
trivy image --severity HIGH,CRITICAL --ignore-unfixed \
  factura-worker:dev | tee ~/factura-v2/docs/scan-worker.txt
# Total: 0 (HIGH: 0, CRITICAL: 0) sur python:3.12-slim à jour.
# Si un HIGH corrigeable apparaît dans une lib Python : bump dans
# requirements.txt (jamais dans le Dockerfile), rebuild, rescan.
docker run --rm -v "$PWD/api:/src" -w /src python:3.12-slim \
  sh -c "pip install -q -r requirements-dev.txt && pytest -q"
#  5 passed in 0.41s
```

Les CVE non corrigeables (`--ignore-unfixed` les cache ; `trivy image
factura-api:dev` sans l'option les montre) se listent dans le journal avec
une ligne chacune, typiquement des CVE de `glibc` ou `openssl` de Debian
bookworm marquées `will_not_fix` par Debian.

Justification ligne à ligne pour le journal (résumé — c'est ce qu'on te
demandera en entretien) :

| Ligne | Pourquoi |
|---|---|
| `FROM python:3.12-slim AS builder` | pip et compilateurs restent ici |
| `python -m venv /venv` + `--no-cache-dir` | un répertoire copiable, sans cache |
| `FROM python:3.12-slim AS runtime` | même base : le venv est binairement compatible |
| `ARG APP_VERSION` → `ENV` | `ARG` n'existe qu'au build, l'app lit `ENV` |
| `LABEL org.opencontainers.*` | traçabilité version/commit dans `inspect` |
| `useradd -u 10001 -M -s nologin` | uid fixe (k8s `runAsUser`), pas de home, pas de shell |
| `COPY --from=builder /venv /venv` | la seule chose qui traverse les étages |
| `COPY --chown=app:app app.py .` | pas de `COPY .` : le `.dockerignore` est une ceinture, pas un plan |
| `USER app` | tout ce qui suit et le processus final : non-root |
| `HEALTHCHECK` en python | pas de `curl` dans slim ; `start-period` pour Gunicorn |
| `CMD [...]` forme exec | PID 1 = gunicorn, reçoit `SIGTERM`, arrêt gracieux |
| `--access-logfile -` | journaux sur stdout, un JSON par requête, pour promtail |

::: pourquoi
**Multi-stage avec un venv** : `pip install` produit des fichiers dans
`site-packages` et des dépendances de build (`gcc`, en-têtes) qu'on ne
veut pas en prod. Copier `/venv` d'un étage à l'autre ramène exactement les
paquets Python, rien d'autre ; la base `slim` (≈ 45 Mo) + venv (≈ 55 Mo) +
app donne 170 Mo, contre 1,1 Go pour `FROM python` + `COPY .`. Moins de
paquets, c'est aussi moins de CVE à scanner : la moitié des HIGH du
`Dockerfile` des devs venaient de `gcc` et `perl` de l'image complète.

**uid 10001 et pas 1000** : 1000 est le premier utilisateur humain de
n'importe quelle distribution ; si un volume hôte est monté, les fichiers
créés par le conteneur appartiennent à `mathieu`. Un uid haut et fixe évite
la collision et sera repris tel quel dans `securityContext.runAsUser` (PB.10)
— Kubernetes refuse `runAsNonRoot` si l'image ne dit pas quel uid elle
utilise.

**Forme exec du `CMD`** : `CMD gunicorn ...` (forme shell) lance `/bin/sh
-c "gunicorn ..."`, le PID 1 est `sh`, qui ne transmet pas `SIGTERM`.
`docker stop` attend 10 s puis `SIGKILL` : les requêtes en cours sont
perdues, et le bleu/vert de PB.7 devient un « presque sans coupure ». Avec
la forme exec, Gunicorn est PID 1, reçoit `SIGTERM`, ferme l'écoute, finit
les requêtes en cours (`--graceful-timeout 20`) et sort.

**Le healthcheck dans l'image et non seulement dans Compose** : Compose,
Swarm, Nomad et `docker run` le lisent ; Kubernetes l'**ignore** (il a ses
probes). Le mettre dans l'image documente « comment savoir si je vais
bien » là où l'app vit ; `--start-period` évite les faux `unhealthy`
pendant que Gunicorn charge Flask et psycopg.

**`--ignore-unfixed`** : une CVE sans correctif disponible ne peut pas être
corrigée par un rebuild ; la faire bloquer la CI produit un pipeline rouge
en permanence que tout le monde apprend à ignorer. On la **liste**
(journal) et on la suit ; on bloque sur ce qu'on peut corriger.
:::

::: piege
* `ENV PATH=/venv/bin:$PATH` avant `COPY --from=builder` : l'ordre des
  instructions ne change rien ici, mais oublier cette ligne fait tourner
  le `python` système, sans Flask : `ModuleNotFoundError` au démarrage,
  `healthy` jamais atteint.
* `depends_on: condition: service_healthy` sans `healthcheck` sur le
  service visé : Compose refuse de démarrer (« no healthcheck »). D'où le
  healthcheck ajouté sur redis.
* `docker compose down` sans `-v` garde le volume `pgdata` : `init.sql` ne
  rejoue **jamais** (le script d'init ne tourne que sur un répertoire de
  données vide). « J'ai changé init.sql et rien ne change » = ce piège.
* `docker compose config` montre les valeurs interpolées : si
  `DB_PASSWORD` est défini dans ton shell, il l'emporte sur le `.env` et
  sur le défaut — la stack de dev prend alors un mot de passe que tu n'as
  pas mis dans `init` de PostgreSQL... qui a été initialisé avec un autre.
  `down -v` et on recommence.
* Le `HEALTHCHECK` en Python avec `urlopen(...).status==200` : sur une 503
  (`/health` dégradé) `urlopen` lève `HTTPError` — l'exception fait sortir
  avec un code non nul, c'est bien le comportement voulu. Sur `/version`,
  l'API répond 200 même sans base : le healthcheck de l'image dit « le
  processus répond », pas « la plateforme va bien ». C'est `/health` (et
  blackbox, PB.8) qui dit le second.
:::

---

### **PB.5** — Rôle de déploiement Compose, secrets chiffrés, staging puis prod

*Un rôle `factura_compose` qui dépose la stack sur `web` et `db` d'un
environnement en tant que `deploy` (sans sudo), secrets dans un vault,
deux couleurs d'API dont une active, idempotent en `--check`.*

**1. Le coffre**

```bash
cd ~/factura-v2
openssl rand -base64 32 > .vault-pass && chmod 0600 .vault-pass
git check-ignore .vault-pass          # .vault-pass (ignoré)
mkdir -p ansible/inventory/group_vars/{staging,prod}
```

`ansible/inventory/group_vars/staging/vault.yml` (contenu **avant**
chiffrement ; prod : mêmes clés, autres valeurs) :

```yaml
vault_db_password: "Stg-Db-2026"
vault_redis_password: "Stg-Redis-2026"
vault_registry_user: "mathieu"
vault_registry_token: "b1a2c3d4e5f60718293a4b5c6d7e8f9012345678"
```

```bash
ansible-vault encrypt ansible/inventory/group_vars/staging/vault.yml
ansible-vault encrypt ansible/inventory/group_vars/prod/vault.yml
head -1 ansible/inventory/group_vars/prod/vault.yml   # $ANSIBLE_VAULT;1.1;AES256
ansible-vault view ansible/inventory/group_vars/prod/vault.yml | head -1
```

Le token de registre est un token Gitea créé pour cet usage (*Paramètres →
Applications → Générer un jeton*, permission `write:package`) ; le même
sert aux VM (pull) et à la CI (`REGISTRY_TOKEN`, PB.6). Deux tokens
(lecture pour les VM, écriture pour la CI) seraient mieux : note-le.

`ansible/inventory/group_vars/staging/main.yml` (en clair, indirection) :

```yaml
# Variables de l'environnement staging (les secrets sont dans vault.yml)
db_password: "{{ vault_db_password }}"
redis_password: "{{ vault_redis_password }}"
registry_user: "{{ vault_registry_user }}"
registry_token: "{{ vault_registry_token }}"
factura_log_level: DEBUG
```

`ansible/inventory/group_vars/prod/main.yml` : identique avec
`factura_log_level: INFO`.

**2. Le rôle `factura_compose`**

`ansible/roles/factura_compose/defaults/main.yml` :

```yaml
registry: lab-ops.lab.local:3000
registry_namespace: mathieu
registry_user: ""
registry_token: ""
factura_image_tag: ""          # vide = ne pas toucher aux images
factura_base_dir: /srv/factura
factura_http_port: 80
factura_blue_port: 8081
factura_green_port: 8082
factura_worker_metrics_port: 9200
factura_redis_exporter_port: 9121
factura_pg_port: 5432
factura_pg_exporter_port: 9187
factura_log_level: INFO
factura_db_user: factura
factura_db_name: factura
factura_health_timeout: 90
factura_smoke_script: "{{ playbook_dir }}/../../tools/smoke.sh"
images:
  nginx: nginx:1.27-alpine
  redis: redis:7-alpine
  redis_exporter: oliver006/redis_exporter:v1.62.0
  postgres: postgres:16-alpine
  postgres_exporter: prometheuscommunity/postgres-exporter:v0.15.0
```

`ansible/roles/factura_compose/tasks/main.yml` :

```yaml
---
- name: Le tag ne doit pas contenir de caractère hors [A-Za-z0-9._@:-]
  ansible.builtin.assert:
    that: factura_image_tag is match('^[A-Za-z0-9._@:-]*$')
    quiet: true

- name: Version attendue par le smoke (tag sans digest)
  ansible.builtin.set_fact:
    factura_expected_version: >-
      {{ factura_image_tag | regex_replace('@.*$', '') }}

- name: Connexion au registre (compte deploy)
  community.docker.docker_login:
    registry_url: "{{ registry }}"
    username: "{{ registry_user }}"
    password: "{{ registry_token }}"
  no_log: true
  when: registry_token | length > 0

- name: Partie db
  ansible.builtin.include_tasks: db.yml
  when: "'db' in group_names"

- name: Partie web
  ansible.builtin.include_tasks: web.yml
  when: "'web' in group_names"
```

`ansible/roles/factura_compose/tasks/db.yml` :

```yaml
---
- name: Arborescence db
  ansible.builtin.file:
    path: "{{ factura_base_dir }}/{{ item }}"
    state: directory
    mode: "0750"
  loop: ["", "sql"]

- name: Schéma initial
  ansible.builtin.copy:
    src: "{{ playbook_dir }}/../../app/sql/init.sql"
    dest: "{{ factura_base_dir }}/sql/init.sql"
    mode: "0640"

- name: Fichier .env (secrets)
  ansible.builtin.template:
    src: env-db.j2
    dest: "{{ factura_base_dir }}/.env"
    mode: "0600"
  no_log: true

- name: compose.yaml
  ansible.builtin.template:
    src: compose-db.yaml.j2
    dest: "{{ factura_base_dir }}/compose.yaml"
    mode: "0640"

- name: Stack db démarrée
  community.docker.docker_compose_v2:
    project_src: "{{ factura_base_dir }}"
    state: present
    pull: missing
    remove_orphans: true
    wait: true
    wait_timeout: "{{ factura_health_timeout }}"

- name: PostgreSQL accepte les connexions
  ansible.builtin.wait_for:
    host: "{{ ansible_host }}"
    port: "{{ factura_pg_port }}"
    timeout: 60
```

`ansible/roles/factura_compose/tasks/web.yml` :

```yaml
---
- name: Arborescence web
  ansible.builtin.file:
    path: "{{ factura_base_dir }}/{{ item }}"
    state: directory
    mode: "0750"
  loop: ["", "nginx", "bin"]

- name: Lecture de l'état (state.env) s'il existe
  ansible.builtin.stat:
    path: "{{ factura_base_dir }}/state.env"
  register: state_file

- name: Premier déploiement - un tag est requis
  ansible.builtin.assert:
    that: factura_image_tag | length > 0
    fail_msg: "premier déploiement : factura_image_tag est requis"
  when: not state_file.stat.exists

- name: Chargement de l'état existant
  when: state_file.stat.exists
  block:
    - name: Lecture de state.env
      ansible.builtin.slurp:
        path: "{{ factura_base_dir }}/state.env"
      register: state_raw
    - name: Parse de state.env
      ansible.builtin.set_fact:
        state: >-
          {{ state | default({})
             | combine({item.split('=', 1)[0]: item.split('=', 1)[1]}) }}
      loop: >-
        {{ (state_raw.content | b64decode).splitlines()
           | select('match', '^[A-Z_]+=') | list }}

- name: État initial (premier déploiement)
  ansible.builtin.set_fact:
    state:
      ACTIVE: blue
      TAG_BLUE: "{{ factura_image_tag }}"
      TAG_GREEN: ""
      TAG_WORKER: "{{ factura_image_tag }}"
      COMPOSE_PROFILES: blue
    first_deploy: true
  when: not state_file.stat.exists

- name: Adresse de la base de l'environnement
  ansible.builtin.set_fact:
    factura_db_host: "{{ hostvars[groups[factura_env ~ '_db'][0]].ansible_host }}"

- name: Fichiers de configuration (secrets en .env 0600)
  ansible.builtin.template:
    src: env-web.j2
    dest: "{{ factura_base_dir }}/.env"
    mode: "0600"
  no_log: true

- name: compose.yaml, nginx, switch.sh
  ansible.builtin.template:
    src: "{{ item.src }}"
    dest: "{{ factura_base_dir }}/{{ item.dest }}"
    mode: "{{ item.mode }}"
  loop:
    - { src: compose-web.yaml.j2, dest: compose.yaml, mode: "0640" }
    - { src: nginx/factura.conf.j2, dest: nginx/factura.conf, mode: "0644" }
    - { src: switch.sh.j2, dest: bin/switch.sh, mode: "0750" }
  notify: Reload nginx

- name: nginx/active.conf (créé une fois, géré ensuite par switch.sh)
  ansible.builtin.template:
    src: nginx/active.conf.j2
    dest: "{{ factura_base_dir }}/nginx/active.conf"
    mode: "0644"
    force: false

- name: state.env (premier déploiement)
  ansible.builtin.template:
    src: state.env.j2
    dest: "{{ factura_base_dir }}/state.env"
    mode: "0640"
  when: not state_file.stat.exists

- name: Stack web (couleur active seulement, sans changer d'image)
  community.docker.docker_compose_v2:
    project_src: "{{ factura_base_dir }}"
    env_files: [.env, state.env]
    profiles: ["{{ state.ACTIVE }}"]
    state: present
    pull: missing
    remove_orphans: true
    wait: true
    wait_timeout: "{{ factura_health_timeout }}"
  when: factura_image_tag | length == 0 or first_deploy | default(false)

- name: Couleur active en bonne santé
  ansible.builtin.uri:
    url: >-
      http://{{ ansible_host }}:{{ factura_blue_port
      if state.ACTIVE == 'blue' else factura_green_port }}/health
    status_code: 200
  register: active_health
  until: active_health.status == 200
  retries: "{{ (factura_health_timeout / 3) | int }}"
  delay: 3
  when: factura_image_tag | length == 0 or first_deploy | default(false)

- name: Déploiement bleu/vert d'un nouveau tag
  ansible.builtin.include_tasks: bluegreen.yml
  when: factura_image_tag | length > 0 and not first_deploy | default(false)
```

`tasks/bluegreen.yml` est l'objet de PB.7 (il est donné là-bas). Au jalon
PB.5, un fichier avec une seule tâche `debug` suffit pour que le rôle
tourne ; le bleu/vert le remplace.

`ansible/roles/factura_compose/handlers/main.yml` :

```yaml
---
- name: Reload nginx
  ansible.builtin.command:
    cmd: docker compose exec -T nginx sh -c 'nginx -t && nginx -s reload'
    chdir: "{{ factura_base_dir }}"
  changed_when: true
  failed_when: false   # nginx pas encore démarré au premier déploiement
```

`ansible/roles/factura_compose/templates/env-web.j2` :

```
# {{ ansible_managed }} - secrets Factura ({{ factura_env }}) - 0600
DB_PASSWORD={{ db_password }}
REDIS_PASSWORD={{ redis_password }}
DATABASE_URL=postgresql://{{ factura_db_user }}:{{ db_password }}@{{
  factura_db_host }}:{{ factura_pg_port }}/{{ factura_db_name }}
REDIS_URL=redis://:{{ redis_password }}@redis:6379/0
LOG_LEVEL={{ factura_log_level }}
REGISTRY={{ registry }}/{{ registry_namespace }}
BIND_IP={{ ansible_host }}
```

`ansible/roles/factura_compose/templates/env-db.j2` :

```
# {{ ansible_managed }} - secrets PostgreSQL ({{ factura_env }}) - 0600
POSTGRES_USER={{ factura_db_user }}
POSTGRES_PASSWORD={{ db_password }}
POSTGRES_DB={{ factura_db_name }}
BIND_IP={{ ansible_host }}
```

`ansible/roles/factura_compose/templates/state.env.j2` :

```
ACTIVE={{ state.ACTIVE }}
TAG_BLUE={{ state.TAG_BLUE }}
TAG_GREEN={{ state.TAG_GREEN }}
TAG_WORKER={{ state.TAG_WORKER }}
COMPOSE_PROFILES={{ state.COMPOSE_PROFILES }}
```

`ansible/roles/factura_compose/templates/compose-web.yaml.j2` :

```yaml
# {{ ansible_managed }} - Factura {{ factura_env }} / web
name: factura
x-api: &api
  restart: unless-stopped
  env_file: [.env]
  networks: [factura]
  stop_grace_period: 25s
  logging:
    driver: json-file
    options: { max-size: "20m", max-file: "5" }

services:
  nginx:
    image: "{{ images.nginx }}"
    restart: unless-stopped
    ports:
      - "{{ factura_http_port }}:80"
      - "${BIND_IP}:{{ factura_blue_port }}:8081"
      - "${BIND_IP}:{{ factura_green_port }}:8082"
    volumes:
      - ./nginx:/etc/nginx/conf.d:ro
    networks: [factura]
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1/nginx-health"]
      interval: 10s
      timeout: 3s
      retries: 3

  api-blue:
    <<: *api
    image: ${REGISTRY}/factura-api:${TAG_BLUE:-none}
    profiles: [blue]
    environment: { APP_COLOR: blue }

  api-green:
    <<: *api
    image: ${REGISTRY}/factura-api:${TAG_GREEN:-none}
    profiles: [green]
    environment: { APP_COLOR: green }

  worker:
    <<: *api
    image: ${REGISTRY}/factura-worker:${TAG_WORKER}
    ports:
      - "${BIND_IP}:{{ factura_worker_metrics_port }}:9200"

  redis:
    image: "{{ images.redis }}"
    restart: unless-stopped
    command: ["redis-server", "--requirepass", "${REDIS_PASSWORD}",
              "--appendonly", "yes", "--maxmemory", "128mb",
              "--maxmemory-policy", "noeviction"]
    volumes: [redisdata:/data]
    networks: [factura]
    healthcheck:
      test: ["CMD-SHELL", "redis-cli -a \"$$REDIS_PASSWORD\" ping | grep -q PONG"]
      interval: 10s
      timeout: 3s
      retries: 5
    environment: { REDIS_PASSWORD: "${REDIS_PASSWORD}" }

  redis_exporter:
    image: "{{ images.redis_exporter }}"
    restart: unless-stopped
    command: ["--check-single-keys", "factura:jobs"]
    environment:
      REDIS_ADDR: redis://redis:6379
      REDIS_PASSWORD: "${REDIS_PASSWORD}"
    ports:
      - "${BIND_IP}:{{ factura_redis_exporter_port }}:9121"
    networks: [factura]
    depends_on: [redis]

networks:
  factura: {}
volumes:
  redisdata: {}
```

`ansible/roles/factura_compose/templates/compose-db.yaml.j2` :

```yaml
# {{ ansible_managed }} - Factura {{ factura_env }} / db
name: factura
services:
  postgres:
    image: "{{ images.postgres }}"
    restart: unless-stopped
    env_file: [.env]
    ports:
      - "${BIND_IP}:{{ factura_pg_port }}:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./sql/init.sql:/docker-entrypoint-initdb.d/10-init.sql:ro
    healthcheck:
      test: ["CMD-SHELL",
             "pg_isready -U {{ factura_db_user }} -d {{ factura_db_name }}"]
      interval: 5s
      timeout: 3s
      retries: 10
    logging:
      driver: json-file
      options: { max-size: "20m", max-file: "5" }

  postgres_exporter:
    image: "{{ images.postgres_exporter }}"
    restart: unless-stopped
    environment:
      DATA_SOURCE_URI: "postgres:5432/${POSTGRES_DB}?sslmode=disable"
      DATA_SOURCE_USER: "${POSTGRES_USER}"
      DATA_SOURCE_PASS: "${POSTGRES_PASSWORD}"
    ports:
      - "${BIND_IP}:{{ factura_pg_exporter_port }}:9187"
    depends_on:
      postgres: { condition: service_healthy }

volumes:
  pgdata: {}
```

`ansible/roles/factura_compose/templates/nginx/factura.conf.j2` :

```nginx
# {{ ansible_managed }} - frontal Factura bleu/vert
# L'upstream actif est défini dans active.conf (géré par bin/switch.sh).
resolver 127.0.0.11 valid=10s ipv6=off;

server {
    listen 80;
    server_name _;
    location = /nginx-health { return 200 "ok\n"; }
    location / {
        proxy_pass http://factura_api;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_next_upstream error timeout http_502;
        proxy_connect_timeout 2s;
    }
}

# Accès direct par couleur (tests, smoke, scrape /metrics)
server {
    listen 8081;
    location / {
        set $blue http://api-blue:8000;
        proxy_pass $blue;
        proxy_set_header Host $host;
    }
}
server {
    listen 8082;
    location / {
        set $green http://api-green:8000;
        proxy_pass $green;
        proxy_set_header Host $host;
    }
}
```

`ansible/roles/factura_compose/templates/nginx/active.conf.j2` :

```nginx
# couleur active : géré par bin/switch.sh, ne pas éditer
upstream factura_api { server api-{{ state.ACTIVE }}:8000; }
```

`ansible/roles/factura_compose/templates/switch.sh.j2` :

```bash
#!/usr/bin/env bash
# switch.sh — bascule la couleur active de Factura (sans coupure)
# usage : switch.sh <blue|green> [raison]
set -euo pipefail
COLOR="${1:?blue|green}"; REASON="${2:-manuel}"
BASE="{{ factura_base_dir }}"
case "$COLOR" in blue|green) ;; *) echo "couleur invalide" >&2; exit 2;; esac
cd "$BASE"
# 1. la couleur cible doit répondre
PORT={{ factura_blue_port }}
[ "$COLOR" = green ] && PORT={{ factura_green_port }}
curl -fsS -m 3 "http://127.0.0.1:$PORT/health" >/dev/null \
  || { echo "api-$COLOR muet sur :$PORT, bascule refusée" >&2; exit 1; }
# 2. réécriture atomique d'active.conf puis reload (jamais restart)
printf 'upstream factura_api { server api-%s:8000; }\n' "$COLOR" \
  > nginx/active.conf.tmp
mv nginx/active.conf.tmp nginx/active.conf
docker compose exec -T nginx nginx -t
docker compose exec -T nginx nginx -s reload
# 3. état et journal
sed -i "s/^ACTIVE=.*/ACTIVE=$COLOR/" state.env
printf '%s switch -> %s (%s)\n' "$(date -Is)" "$COLOR" "$REASON" >> switch.log
echo "active: $COLOR"
```

**3. Le playbook**

`ansible/playbooks/deploy.yml` :

```yaml
---
# Déploiement Factura : db puis web (l'API a besoin de la base).
# Exécuté en tant que deploy (runner CI) : aucun become.
#   ansible-playbook -i inventory/<env>.ini playbooks/deploy.yml \
#     -e factura_image_tag=<tag>
- name: Base de données
  hosts: db
  become: false
  serial: 1
  roles:
    - factura_compose

- name: Frontal et API
  hosts: web
  become: false
  serial: 1
  roles:
    - factura_compose
```

**4. Première image, premier déploiement**

```bash
cd ~/factura-v2
SHA=$(git rev-parse --short HEAD)
docker login lab-ops.lab.local:3000 -u mathieu    # token write:package
for i in api worker; do
  docker build --build-arg APP_VERSION=dev-$SHA -t factura-$i:dev-$SHA app/$i
  docker tag factura-$i:dev-$SHA \
    lab-ops.lab.local:3000/mathieu/factura-$i:dev-$SHA
  docker push lab-ops.lab.local:3000/mathieu/factura-$i:dev-$SHA
done
ansible-playbook -i ansible/inventory/staging.ini ansible/playbooks/deploy.yml \
  -e factura_image_tag=dev-$SHA -e ansible_user=deploy
curl -s http://10.10.10.21/health; curl -s http://10.10.10.21/version
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"client":"ACME","montant_ht":100}' http://10.10.10.21/api/factures
ansible-playbook -i ansible/inventory/prod.ini ansible/playbooks/deploy.yml \
  -e factura_image_tag=dev-$SHA -e ansible_user=deploy
```

Idempotence et preuves :

```bash
ansible-playbook -i ansible/inventory/staging.ini ansible/playbooks/deploy.yml \
  -e ansible_user=deploy | grep -A3 'PLAY RECAP'
#  factura-staging-db  : ok=9   changed=0 ...
#  factura-staging-web : ok=15  changed=0 ...
ansible-playbook -i ansible/inventory/staging.ini ansible/playbooks/deploy.yml \
  --check --diff | grep -c '^changed:'                     # 0
nc -zv -w2 10.10.10.22 5432                                # timed out
ssh mathieu@10.10.10.21 nc -zv -w2 10.10.10.22 5432        # succeeded!
git show HEAD:ansible/inventory/group_vars/prod/vault.yml | head -1
```

Le playbook tourne aussi en `mathieu` (ansible.cfg ne force pas
`ansible_user`, l'inventaire dit `mathieu`) : `deploy` est le compte du
runner, `mathieu` celui du diagnostic. Les deux sont dans `docker`, et
`/srv/factura` appartient à `deploy` avec `0750`... donc en `mathieu` le
`template` échoue en écriture. Pour que `make deploy` marche depuis
`lab-adm`, ajoute `-e ansible_user=deploy` dans le `Makefile` (cible
`deploy`) : le compte de déploiement est `deploy`, point.

::: pourquoi
**Profils Compose pour la couleur** : un service avec `profiles: [green]`
n'existe pour Compose que si le profil est actif. `COMPOSE_PROFILES=blue`
dans `state.env` et `profiles:` du module font qu'un `up -d` ne démarre
que la couleur active, sans `if` dans le template. Le bleu/vert de PB.7
active les deux profils le temps de la bascule.

**`state.env` séparé de `.env`** : `.env` est un secret (0600, rendu par
Ansible depuis le vault) ; `state.env` est un état mutable (0640, écrit par
Ansible **et** par `switch.sh`). Les mélanger ferait réécrire les secrets
par un script shell, ou rendrait l'état non idempotent côté Ansible. Le
rôle ne réécrit `state.env` qu'au premier déploiement : ensuite c'est le
bleu/vert et `switch.sh` qui le font évoluer, et Ansible le **lit**.

**Tag vide = ne rien changer** : c'est ce qui rend `--check` et le second
passage vides. Sans cette convention, chaque `deploy.yml` sans tag
essaierait de déployer « rien » ou `latest`. Et le garde-fou « premier
déploiement : tag requis » évite de démarrer une stack avec une image
`:none` qui n'existe pas (le `${TAG_BLUE:-none}` du template est là pour
que `docker compose config` reste valide, pas pour tourner).

**Indirection `db_password: "{{ vault_db_password }}"`** : `grep -r
db_password` trouve où la variable est utilisée sans décrypter ; on peut
changer la source (vault → gestionnaire de secrets) sans toucher aux
rôles ; et `ansible-vault view` sur un fichier de 4 lignes est lisible.
Les mots de passe diffèrent entre staging et prod pour qu'une fuite du
staging (moins protégé, plus de monde dessus) ne donne pas la prod.

**`5432` publié sur `BIND_IP` et filtré par `DOCKER-USER`** : le port est
joignable de la VM web seulement — vérifié par les deux `nc`. Le
`postgres_exporter` parle à `postgres` par le réseau Compose, jamais par
le port publié.

**Le worker sans couleur** : deux workers consommant la même file
donneraient deux versions traitant des factures en parallèle pendant la
bascule. Un seul worker, recréé (3 à 5 s pendant lesquels les jobs
attendent dans Redis, `appendonly yes` les protège) : compromis assumé,
documenté.
:::

::: piege
* `docker_compose_v2` avec `pull: always` rend chaque run `changed`
  (il tente le pull même si rien ne change). `pull: missing` en régime
  normal ; le bleu/vert fait un `docker_image_pull` explicite du tag
  demandé.
* `no_log: true` sur le template `.env` masque aussi le `--diff` : en
  `--check --diff`, tu ne verras pas qu'un mot de passe a changé, juste
  `changed`. C'est voulu : la sortie va dans les journaux du runner.
* `redis-cli -a` dans le healthcheck : la variable doit être échappée en
  `$$REDIS_PASSWORD` pour que Compose ne l'interpole pas dans le
  fichier (sinon le mot de passe apparaît en clair dans `docker inspect`
  du healthcheck — il y est de toute façon via `command`, d'où le
  `0640` sur `compose.yaml` et l'idée d'un `redis.conf` monté en secret
  pour aller plus loin).
* nginx et un upstream absent : `upstream { server api-green:8000; }`
  avec `api-green` non démarré fait échouer `nginx -t` (« host not found
  in upstream »). C'est pourquoi `active.conf` ne pointe que sur la
  couleur qui tourne et que les blocs 8081/8082 utilisent `set $x` +
  `resolver` : nginx résout au moment de la requête, et une couleur
  éteinte donne un 502 propre au lieu d'empêcher nginx de démarrer.
* Un `ansible-vault encrypt` sur un fichier déjà commité en clair laisse
  le secret dans l'historique. Ici, les `vault.yml` naissent chiffrés ;
  si tu as commité une version claire « pour tester », la seule réponse
  est de changer les mots de passe (staging comme prod).
:::

---

### **PB.6** — Pipeline d'intégration continue

*`.gitea/workflows/ci.yaml` : `lint`, `test`, `build` chaînés sur le runner
`ops-host`, images poussées avec un tag `sha-<7>` (et `vX.Y.Z` sur un tag
Git), scan trivy bloquant, secrets par `env:`, digest en sortie de job.*

**1. Préparation du runner (`lab-ops`, une fois, module 21 rappelé)**

```bash
# sur lab-ops : les outils dans le PATH du compte runner
sudo -u runner -H bash -c 'pipx install pre-commit ansible-lint; \
  pipx install --include-deps ansible; pipx ensurepath'
which tofu trivy jq node                     # /usr/local/bin/...
sudo install -d -o runner -g runner -m 0750 /var/lib/act_runner/trivy-cache
sudo -u runner ssh-keygen -t ed25519 -N '' -f /home/runner/.ssh/id_ed25519 \
  -C runner@lab-ops
cat /home/runner/.ssh/id_ed25519.pub         # -> deploy_authorized_keys (PB.3)
```

Secrets du dépôt (*Settings → Actions → Secrets*) : `REGISTRY_USER`
(`mathieu`), `REGISTRY_TOKEN` (token `write:package`), `VAULT_PASS` (le
contenu de `.vault-pass`), `DEPLOY_SSH_KEY` (la clé privée
`/home/runner/.ssh/id_ed25519` — ou, plus propre, une clé générée pour la
CI et ajoutée à `deploy_authorized_keys`).

**2. Le workflow**

`.gitea/workflows/ci.yaml` (version complète, avec le job `deploy-staging`
de PB.7) :

```yaml
name: ci
on:
  push:
    branches: [main]
    tags: ["v*"]
  pull_request:
  workflow_dispatch:

concurrency:
  group: ci-${{ gitea.ref }}
  cancel-in-progress: true

env:
  REGISTRY: lab-ops.lab.local:3000
  NAMESPACE: mathieu
  TRIVY_CACHE_DIR: /var/lib/act_runner/trivy-cache

jobs:
  lint:
    runs-on: ops-host
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - name: Outils du runner
        run: which tofu trivy ansible-playbook pre-commit jq
      - name: pre-commit (gitleaks, shellcheck, yamllint, ansible-lint)
        run: |
          export PATH="$HOME/.local/bin:$PATH"
          pre-commit run --all-files --show-diff-on-failure
      - name: OpenTofu fmt et validate (sans état, sans token)
        working-directory: infra
        run: |
          tofu fmt -check -recursive
          tofu init -backend=false -input=false >/dev/null
          TF_VAR_pve_api_token='x@pve!ci=00000000-0000-0000-0000-000000000000' \
            tofu validate
      - name: Compose de dev valide
        run: docker compose -f app/compose.yaml config -q

  test:
    runs-on: ops-host
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - name: pytest dans un conteneur jetable
        run: |
          docker run --rm -v "$PWD/app/api:/src" -w /src \
            -e PIP_DISABLE_PIP_VERSION_CHECK=1 python:3.12-slim \
            sh -c "pip install -q -r requirements-dev.txt \
                   && pytest -q --junitxml=junit.xml"
      - uses: actions/upload-artifact@v3
        if: always()
        with:
          name: junit
          path: app/api/junit.xml

  build:
    needs: [lint, test]
    runs-on: ops-host
    timeout-minutes: 20
    outputs:
      tag: ${{ steps.meta.outputs.tag }}
      version_tag: ${{ steps.meta.outputs.version_tag }}
      api_digest: ${{ steps.digests.outputs.api }}
      worker_digest: ${{ steps.digests.outputs.worker }}
    steps:
      - uses: actions/checkout@v4
      - name: Calcul des tags
        id: meta
        run: |
          TAG="sha-${GITHUB_SHA:0:7}"
          echo "tag=$TAG" >> "$GITHUB_OUTPUT"
          if [ "${{ gitea.ref_type }}" = tag ]; then
            echo "version_tag=${GITHUB_REF_NAME}" >> "$GITHUB_OUTPUT"
          else
            echo "version_tag=" >> "$GITHUB_OUTPUT"
          fi
      - name: Build des deux images
        env:
          TAG: ${{ steps.meta.outputs.tag }}
          VTAG: ${{ steps.meta.outputs.version_tag }}
        run: |
          APP_VERSION="${VTAG:-$TAG}"
          for i in api worker; do
            docker build --pull \
              --build-arg APP_VERSION="$APP_VERSION" \
              --build-arg VCS_REF="$GITHUB_SHA" \
              -t "$REGISTRY/$NAMESPACE/factura-$i:$TAG" "app/$i"
          done
      - name: Scan bloquant (HIGH/CRITICAL corrigeables)
        env:
          TAG: ${{ steps.meta.outputs.tag }}
        run: |
          for i in api worker; do
            trivy image --exit-code 1 --severity HIGH,CRITICAL \
              --ignore-unfixed --no-progress \
              "$REGISTRY/$NAMESPACE/factura-$i:$TAG"
          done
      - name: Connexion au registre (secrets par env, jamais dans run)
        if: gitea.event_name != 'pull_request'
        env:
          REGISTRY_USER: ${{ secrets.REGISTRY_USER }}
          REGISTRY_TOKEN: ${{ secrets.REGISTRY_TOKEN }}
        run: |
          printf '%s' "$REGISTRY_TOKEN" \
            | docker login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin
      - name: Push des tags
        if: gitea.event_name != 'pull_request'
        env:
          TAG: ${{ steps.meta.outputs.tag }}
          VTAG: ${{ steps.meta.outputs.version_tag }}
        run: |
          for i in api worker; do
            IMG="$REGISTRY/$NAMESPACE/factura-$i"
            docker push "$IMG:$TAG"
            if [ -n "$VTAG" ]; then
              docker tag "$IMG:$TAG" "$IMG:$VTAG" && docker push "$IMG:$VTAG"
            fi
          done
      - name: Digests (identité réelle des images)
        id: digests
        if: gitea.event_name != 'pull_request'
        env:
          TAG: ${{ steps.meta.outputs.tag }}
        run: |
          for i in api worker; do
            D=$(docker inspect --format '{{index .RepoDigests 0}}' \
                "$REGISTRY/$NAMESPACE/factura-$i:$TAG")
            echo "$i=${D#*@}" >> "$GITHUB_OUTPUT"
            echo "factura-$i:$TAG -> ${D#*@}"
          done
      - name: Déconnexion du registre
        if: always()
        run: docker logout "$REGISTRY" || true

  deploy-staging:
    needs: build
    if: gitea.ref == 'refs/heads/main'
    runs-on: ops-host
    timeout-minutes: 15
    env:
      ANSIBLE_HOST_KEY_CHECKING: "false"
      ANSIBLE_FORCE_COLOR: "true"
    steps:
      - uses: actions/checkout@v4
      - name: Secrets dans des fichiers temporaires (0600)
        env:
          VAULT_PASS: ${{ secrets.VAULT_PASS }}
          DEPLOY_SSH_KEY: ${{ secrets.DEPLOY_SSH_KEY }}
        run: |
          umask 077
          printf '%s\n' "$VAULT_PASS" > .vault-pass
          printf '%s\n' "$DEPLOY_SSH_KEY" > "$RUNNER_TEMP/deploy_key"
      - name: Inventaire CI cohérent avec les IP attendues
        run: tools/check-inventory.sh staging
      - name: Déploiement staging (bleu/vert, smoke, rollback)
        env:
          TAG: ${{ needs.build.outputs.tag }}
          API_DIGEST: ${{ needs.build.outputs.api_digest }}
        run: |
          export PATH="$HOME/.local/bin:$PATH"
          cd ansible
          ansible-galaxy collection install -r requirements.yml -p collections -q
          ansible-playbook -i inventory/ci/staging.ini playbooks/deploy.yml \
            -e "factura_image_tag=$TAG" -e ansible_user=deploy \
            --private-key "$RUNNER_TEMP/deploy_key"
      - name: Smoke final sur le port 80
        env:
          TAG: ${{ needs.build.outputs.tag }}
        run: tools/smoke.sh http://10.10.10.21 "$TAG"
      - name: Nettoyage des secrets
        if: always()
        run: rm -f .vault-pass "$RUNNER_TEMP/deploy_key"
```

**3. Protection de branche et preuves**

```bash
# statut requis (le contexte est "<workflow> / <job>")
curl -fsS -u mathieu -X PATCH \
  "$GITEA/api/v1/repos/mathieu/factura/branch_protections/main" \
  -H 'Content-Type: application/json' \
  -d '{"enable_status_check":true,"status_check_contexts":["ci / build"]}'
# PR avec un test cassé
git switch -c test/casse
sed -i 's/== 120.0/== 121.0/' app/api/tests/test_api.py
git commit -am "test(api): casse volontaire du test TTC"
git push -u origin test/casse
# -> PR sur Gitea : run rouge au job test, "build" sauté, PR non fusionnable
git switch main && git branch -D test/casse
# version
git tag -a v2.0.0 -m "Factura v2.0.0" && git push --tags
curl -s -u mathieu "$GITEA/v2/mathieu/factura-api/tags/list" | jq .
#  {"name":"mathieu/factura-api","tags":["sha-3f9c1e2","v2.0.0", ...]}
```

Durée mesurée du pipeline (journal) : **4 min 10 s**, dont `build` 2 min 30
(les trois postes : `pip install` dans le builder ≈ 50 s, `trivy` ≈ 45 s la
première fois puis 10 s avec le cache, `push` ≈ 20 s), `lint` 55 s
(`ansible-lint` fait la moitié), `test` 40 s (le `pip install` dans le
conteneur jetable). Pistes : cache pip par un volume monté, `--cache-from`
sur l'image précédente, `ansible-lint` sur les fichiers modifiés seulement.

::: pourquoi
**Runner en mode hôte** : les jobs tournent sous `runner` dans un shell
de `lab-ops`, avec ses binaires et son socket Docker. C'est ce qui rend
possible `docker build` sans Docker-in-Docker, `ansible-playbook` avec les
collections installées et le cache trivy persistant. Le prix : un job
peut lire ce qu'un autre a laissé (d'où `rm -f` en `always()` et `docker
logout`), et tout ce qui manque dans le `PATH` de `runner` fait échouer le
job avec « command not found » — le premier step `which ...` diagnostique
ça en une ligne.

**`sha-<7>` toujours, `vX.Y.Z` en plus** : le SHA identifie le commit, la
version identifie l'intention humaine. Une image existe **une fois**,
construite sur le commit ; le tag de version est un alias posé sur la même
image (`docker tag` + `push`, pas de rebuild), ce que le registre
confirme par un digest identique. C'est le principe « construire une
fois, promouvoir ensuite ». Et parce qu'un tag est **mutable** (INC-B1),
le job publie le digest en `outputs` : c'est le seul identifiant que
personne ne peut déplacer.

**Scan avant push** : une image vulnérable qui a atteint le registre est
déjà « disponible » pour un `deploy.yml` lancé à la main. Bloquer avant
le push garantit que tout ce qui est dans le registre a passé le scan du
jour de sa construction — pas celui d'aujourd'hui, d'où le bonus d'un
scan périodique du registre.

**Secrets par `env:`** : `${{ secrets.X }}` est substitué dans le texte du
script avant exécution ; dans `run:` il apparaît en clair dans le journal
si le step a `set -x` ou si la commande échoue avec son texte. Par `env:`
la valeur est dans l'environnement du processus, lue par `"$VAR"`, et le
masquage du runner s'applique.

**`tofu validate` avec un faux token** : `validate` ne contacte pas
Proxmox mais la `validation` de la variable exige le format ; un token
au bon format et faux passe la validation sans donner accès à rien.
`-backend=false` évite de chercher un état qui n'existe pas sur le runner.

**`pull_request` sans push** : une PR d'un collègue (ou d'un compte
compromis) ne doit pas pouvoir écrire dans le registre. Les conditions
`if: gitea.event_name != 'pull_request'` sur login/push/digests le
garantissent ; `lint` et `test` donnent quand même le verdict.
:::

::: piege
* Le contexte du statut requis s'appelle `ci / build` (nom du workflow,
  espace, barre, espace, nom du job). Un autre libellé et la PR reste
  bloquée pour toujours sur « en attente du statut ».
* `actions/upload-artifact@v4` demande une API que Gitea 1.22 n'a pas
  encore partout : `@v3` marche. Vérifie la version de ton Gitea.
* `gitea.ref_type` vaut `tag` sur un push de tag ; `GITHUB_REF_NAME` vaut
  alors `v2.0.0`. Sur un push de branche, `ref_type` vaut `branch`. Tester
  `startsWith(gitea.ref, 'refs/tags/')` marche aussi.
* `concurrency` avec `cancel-in-progress` annule le run précédent de la
  même référence : deux pushes rapprochés sur `main` n'en déploient qu'un.
  Sur un tag, chaque tag est sa propre référence.
* `docker build` sans `--pull` réutilise une base `python:3.12-slim` vieille
  de trois mois présente sur `lab-ops` : le scan trouve des HIGH que la
  base à jour n'a plus. `--pull` coûte quelques secondes.
* Le job `build` tourne aussi sur les PR (sans push) : c'est le
  contexte `ci / build` qui est requis, il doit donc exister sur les PR.
  Si tu mets `if: != pull_request` sur tout le job, la PR n'a jamais de
  statut `ci / build` et n'est jamais fusionnable.
:::

---

### **PB.7** — Livraison continue : staging automatique, prod promue, bleu/vert

*Push sur `main` → staging à jour ; `cd-prod.yaml` lancé à la main avec un
tag `vX.Y.Z` (déjà en staging) → prod sans coupure ; smoke, rollback
automatique tracé dans `switch.log`.*

**1. L'inventaire de la CI**

`ansible/inventory/ci/staging.ini` (versionné, avec les IP) :

```ini
# Inventaire de la CI : copie versionnée de l'inventaire généré par
# OpenTofu. tools/check-inventory.sh vérifie qu'ils coïncident.
[staging_web]
factura-staging-web ansible_host=10.10.10.21

[staging_db]
factura-staging-db ansible_host=10.10.10.22

[web:children]
staging_web

[db:children]
staging_db

[staging:children]
staging_web
staging_db

[staging:vars]
factura_env=staging

[all:vars]
ansible_user=deploy
```

`ansible/inventory/ci/prod.ini` : même chose avec `.31`/`.32` et `prod`.
Les `group_vars` sont cherchés à côté de l'inventaire :

```bash
ln -s ../group_vars ansible/inventory/ci/group_vars
git add ansible/inventory/ci
```

`tools/check-inventory.sh` :

```bash
#!/usr/bin/env bash
# check-inventory.sh — l'inventaire CI (versionné) doit coïncider avec
# l'inventaire généré par OpenTofu (quand il est disponible) et, en CI,
# avec les VM réellement joignables.
# usage : tools/check-inventory.sh <staging|prod>
set -euo pipefail
ENV="${1:?env}"
cd "$(dirname "$0")/.."
CI="ansible/inventory/ci/$ENV.ini"
GEN="ansible/inventory/$ENV.ini"
hosts() { awk '/ansible_host=/{sub("ansible_host=","",$2); print $1, $2}' "$1" \
          | sort; }
if [ -f "$GEN" ]; then
  diff <(hosts "$GEN") <(hosts "$CI") \
    || { echo "inventaire CI $CI différent de $GEN (tofu output)" >&2; exit 1; }
  echo "inventaire CI = inventaire OpenTofu ($ENV)"
fi
while read -r name ip; do
  h=$(ssh -o BatchMode=yes -o ConnectTimeout=4 \
        -o StrictHostKeyChecking=accept-new "deploy@$ip" hostname 2>/dev/null \
        || true)
  [ "$h" = "$name" ] \
    || { echo "$ip ne répond pas '$name' (reçu '$h')" >&2; exit 1; }
done < <(hosts "$CI")
echo "inventaire CI $ENV : hôtes joignables et nommés comme attendu"
```

Sur `lab-adm`, `make lint` lance aussi `tools/check-inventory.sh staging`
(l'état OpenTofu n'existe que là). En CI, le script vérifie que chaque IP
répond avec le bon `hostname` — ce que la génération par `tofu output`
n'aurait pas vérifié non plus.

**2. Le bleu/vert dans le rôle**

`ansible/roles/factura_compose/tasks/bluegreen.yml` :

```yaml
---
# Déploiement bleu/vert d'un nouveau tag sur la couleur inactive.
# Variables d'entrée : factura_image_tag, state (lu par web.yml)
- name: Couleurs
  ansible.builtin.set_fact:
    old_color: "{{ state.ACTIVE }}"
    new_color: "{{ 'green' if state.ACTIVE == 'blue' else 'blue' }}"
    switched: false

- name: Port direct de la nouvelle couleur
  ansible.builtin.set_fact:
    new_port: >-
      {{ factura_blue_port if new_color == 'blue' else factura_green_port }}
    old_port: >-
      {{ factura_blue_port if old_color == 'blue' else factura_green_port }}

- name: Rien à faire si la couleur active tourne déjà ce tag
  ansible.builtin.meta: end_host
  when: state['TAG_' ~ (old_color | upper)] == factura_image_tag

- name: Déploiement {{ new_color }} avec {{ factura_image_tag }}
  block:
    - name: Pull explicite des images du tag
      community.docker.docker_image_pull:
        name: "{{ registry }}/{{ registry_namespace }}/factura-{{ item }}"
        tag: "{{ factura_image_tag }}"
      loop: [api, worker]

    - name: state.env - tag de la couleur cible
      ansible.builtin.lineinfile:
        path: "{{ factura_base_dir }}/state.env"
        regexp: "^TAG_{{ new_color | upper }}="
        line: "TAG_{{ new_color | upper }}={{ factura_image_tag }}"

    - name: Démarrage de la couleur cible (les deux profils actifs)
      community.docker.docker_compose_v2:
        project_src: "{{ factura_base_dir }}"
        env_files: [.env, state.env]
        profiles: [blue, green]
        services: ["api-{{ new_color }}"]
        state: present
        recreate: always
        wait: true
        wait_timeout: "{{ factura_health_timeout }}"

    - name: "/health = 200 et /version = tag sur le port direct"
      ansible.builtin.uri:
        url: "http://{{ ansible_host }}:{{ new_port }}/{{ item }}"
        return_content: true
      register: direct
      until: >
        direct.status == 200 and
        (item != 'version' or direct.json.version == factura_expected_version)
      retries: "{{ (factura_health_timeout / 3) | int }}"
      delay: 3
      loop: [health, version]

    - name: Smoke sur le port direct (avant bascule)
      ansible.builtin.script:
        cmd: >-
          {{ factura_smoke_script }}
          http://{{ ansible_host }}:{{ new_port }}
          {{ factura_expected_version }}
      changed_when: false

    - name: Bascule nginx vers {{ new_color }}
      ansible.builtin.command:
        cmd: >-
          {{ factura_base_dir }}/bin/switch.sh {{ new_color }}
          deploy-{{ factura_image_tag }}
      changed_when: true

    - name: Bascule effectuée
      ansible.builtin.set_fact:
        switched: true

    - name: Smoke sur le port 80 (après bascule)
      ansible.builtin.script:
        cmd: >-
          {{ factura_smoke_script }}
          http://{{ ansible_host }}:{{ factura_http_port }}
          {{ factura_expected_version }}
      changed_when: false

    - name: Worker recréé avec le nouveau tag
      ansible.builtin.lineinfile:
        path: "{{ factura_base_dir }}/state.env"
        regexp: "^TAG_WORKER="
        line: "TAG_WORKER={{ factura_image_tag }}"

    - name: state.env - profil actif
      ansible.builtin.lineinfile:
        path: "{{ factura_base_dir }}/state.env"
        regexp: "^COMPOSE_PROFILES="
        line: "COMPOSE_PROFILES={{ new_color }}"

    - name: Stack finale (worker recréé, ancienne couleur laissée en place)
      community.docker.docker_compose_v2:
        project_src: "{{ factura_base_dir }}"
        env_files: [.env, state.env]
        profiles: [blue, green]
        state: present
        wait: true
        wait_timeout: "{{ factura_health_timeout }}"

  rescue:
    - name: Rebascule vers {{ old_color }} si on avait basculé
      ansible.builtin.command:
        cmd: >-
          {{ factura_base_dir }}/bin/switch.sh {{ old_color }}
          rollback-{{ factura_image_tag }}
      when: switched | bool
      changed_when: true

    - name: Arrêt de la couleur en échec
      community.docker.docker_compose_v2:
        project_src: "{{ factura_base_dir }}"
        env_files: [.env, state.env]
        profiles: [blue, green]
        services: ["api-{{ new_color }}"]
        state: stopped
      failed_when: false

    - name: state.env - tag de la couleur en échec effacé, profil restauré
      ansible.builtin.lineinfile:
        path: "{{ factura_base_dir }}/state.env"
        regexp: "{{ item.re }}"
        line: "{{ item.line }}"
      loop:
        - re: "^TAG_{{ new_color | upper }}="
          line: "TAG_{{ new_color | upper }}="
        - re: "^COMPOSE_PROFILES="
          line: "COMPOSE_PROFILES={{ old_color }}"

    - name: Trace du rollback
      ansible.builtin.lineinfile:
        path: "{{ factura_base_dir }}/switch.log"
        line: >-
          {{ now(utc=true, fmt='%Y-%m-%dT%H:%M:%S+00:00') }}
          rollback {{ new_color }} -> {{ old_color }}
          (tag {{ factura_image_tag }}, étape: {{ ansible_failed_task.name }})
        create: true
        mode: "0640"

    - name: Échec explicite du déploiement
      ansible.builtin.fail:
        msg: >-
          Déploiement de {{ factura_image_tag }} sur {{ new_color }} annulé
          ({{ ansible_failed_task.name }}) ;
          {{ 'rebasculé sur ' ~ old_color if switched
             else 'aucune bascule effectuée' }}.
          {{ ansible_failed_result.msg | default('') }}
```

**3. Le workflow de promotion**

`.gitea/workflows/cd-prod.yaml` :

```yaml
name: cd-prod
on:
  workflow_dispatch:
    inputs:
      tag:
        description: "Version à promouvoir (vX.Y.Z, déjà en staging)"
        required: true
        type: string

concurrency:
  group: cd-prod
  cancel-in-progress: false

env:
  REGISTRY: lab-ops.lab.local:3000
  NAMESPACE: mathieu
  STAGING_URL: http://10.10.10.21
  PROD_URL: http://10.10.10.31
  ANSIBLE_HOST_KEY_CHECKING: "false"

jobs:
  guard:
    runs-on: ops-host
    timeout-minutes: 5
    outputs:
      digest: ${{ steps.registry.outputs.digest }}
    steps:
      - name: Le tag est une version
        env:
          TAG: ${{ gitea.event.inputs.tag }}
        run: |
          echo "$TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' \
            || { echo "tag '$TAG' hors format vX.Y.Z" >&2; exit 1; }
      - name: L'image existe dans le registre
        id: registry
        env:
          TAG: ${{ gitea.event.inputs.tag }}
          REGISTRY_USER: ${{ secrets.REGISTRY_USER }}
          REGISTRY_TOKEN: ${{ secrets.REGISTRY_TOKEN }}
        run: |
          D=$(curl -fsS -u "$REGISTRY_USER:$REGISTRY_TOKEN" -o /dev/null \
              -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
              -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
              -w '%header{docker-content-digest}' \
              "http://$REGISTRY/v2/$NAMESPACE/factura-api/manifests/$TAG") \
            || { echo "factura-api:$TAG absent du registre" >&2; exit 1; }
          echo "digest=$D" >> "$GITHUB_OUTPUT"
          echo "factura-api:$TAG = $D"
      - name: Le staging tourne ce tag
        env:
          TAG: ${{ gitea.event.inputs.tag }}
        run: |
          V=$(curl -fsS -m 5 "$STAGING_URL/version" | jq -r .version)
          [ "$V" = "$TAG" ] \
            || { echo "staging tourne $V, pas $TAG : promeus le testé" >&2
                 exit 1; }

  promote:
    needs: guard
    runs-on: ops-host
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - name: Secrets temporaires
        env:
          VAULT_PASS: ${{ secrets.VAULT_PASS }}
          DEPLOY_SSH_KEY: ${{ secrets.DEPLOY_SSH_KEY }}
        run: |
          umask 077
          printf '%s\n' "$VAULT_PASS" > .vault-pass
          printf '%s\n' "$DEPLOY_SSH_KEY" > "$RUNNER_TEMP/deploy_key"
      - name: Inventaire prod cohérent
        run: tools/check-inventory.sh prod
      - name: Version en prod avant promotion
        run: curl -fsS "$PROD_URL/version" | tee before.json
      - name: Déploiement bleu/vert en prod
        env:
          TAG: ${{ gitea.event.inputs.tag }}
        run: |
          export PATH="$HOME/.local/bin:$PATH"
          cd ansible
          ansible-galaxy collection install -r requirements.yml -p collections -q
          ansible-playbook -i inventory/ci/prod.ini playbooks/deploy.yml \
            -e "factura_image_tag=$TAG" -e ansible_user=deploy \
            --private-key "$RUNNER_TEMP/deploy_key"
      - name: Smoke final port 80
        env:
          TAG: ${{ gitea.event.inputs.tag }}
        run: tools/smoke.sh "$PROD_URL" "$TAG"
      - name: Trace - release Gitea
        if: success()
        env:
          TAG: ${{ gitea.event.inputs.tag }}
          DIGEST: ${{ needs.guard.outputs.digest }}
          TOKEN: ${{ secrets.GITEA_TOKEN }}
        run: |
          BEFORE=$(jq -r .version before.json)
          BODY="Promu en prod par ${{ gitea.actor }} le $(date -Is). \
          factura-api:$TAG digest $DIGEST. Version précédente : $BEFORE."
          curl -fsS -X POST \
            -H "Authorization: token $TOKEN" -H 'Content-Type: application/json' \
            "$GITHUB_SERVER_URL/api/v1/repos/$GITHUB_REPOSITORY/releases" \
            -d "$(jq -n --arg t "$TAG" --arg b "$BODY" \
                 '{tag_name:$t,name:("Factura "+$t),body:$b}')" >/dev/null \
            || echo "release déjà existante ou API indisponible (non bloquant)"
      - name: Nettoyage
        if: always()
        run: rm -f .vault-pass "$RUNNER_TEMP/deploy_key" before.json
```

`Makefile`, cibles ajoutées :

```makefile
GITEA ?= http://lab-ops.lab.local:3000
promote:   ## make promote TAG=v2.1.0 (GITEA_TOKEN dans l'environnement)
	curl -fsS -X POST -H "Authorization: token $$GITEA_TOKEN" \
	  -H 'Content-Type: application/json' \
	  "$(GITEA)/api/v1/repos/mathieu/factura/actions/workflows/cd-prod.yaml/dispatches" \
	  -d '{"ref":"main","inputs":{"tag":"$(TAG)"}}'
lint: check-inventory
check-inventory:
	bash tools/check-inventory.sh staging
```

**4. Preuves**

Zéro coupure pendant une promotion (depuis `lab-adm`, avant `make
promote TAG=v2.1.0`) :

```bash
n=0; e=0; end=$((SECONDS+240))
while [ $SECONDS -lt $end ]; do
  curl -sf -m 2 -o /dev/null http://10.10.10.31/health || e=$((e+1))
  n=$((n+1)); sleep 0.2
done; echo "requêtes=$n erreurs=$e"
#  requêtes=1148 erreurs=0
```

Rollback provoqué (une image qui ment sur sa version) :

```bash
docker pull lab-ops.lab.local:3000/mathieu/factura-api:sha-3f9c1e2
docker tag lab-ops.lab.local:3000/mathieu/factura-api:sha-3f9c1e2 \
  lab-ops.lab.local:3000/mathieu/factura-api:v9.9.9
docker tag lab-ops.lab.local:3000/mathieu/factura-worker:sha-3f9c1e2 \
  lab-ops.lab.local:3000/mathieu/factura-worker:v9.9.9
docker push lab-ops.lab.local:3000/mathieu/factura-api:v9.9.9
docker push lab-ops.lab.local:3000/mathieu/factura-worker:v9.9.9
ansible-playbook -i ansible/inventory/staging.ini ansible/playbooks/deploy.yml \
  -e factura_image_tag=v9.9.9 -e ansible_user=deploy
#  TASK [factura_compose : /health = 200 et /version = tag ...]  FAILED
#  (retries exhausted: version sha-3f9c1e2 != v9.9.9)
#  TASK [factura_compose : Rebascule ...]  skipping (switched=false)
#  TASK [factura_compose : Arrêt de la couleur en échec]  ok
#  TASK [factura_compose : Trace du rollback]  changed
#  fatal: Déploiement de v9.9.9 sur green annulé (...) ; aucune bascule
ssh mathieu@10.10.10.21 tail -n 2 /srv/factura/switch.log
#  2026-09-14T10:02:11+02:00 switch -> blue (deploy-v2.1.0)
#  2026-09-14T10:41:03+00:00 rollback green -> blue (tag v9.9.9, étape: ...)
curl -s http://10.10.10.21/version | jq -r .version     # v2.1.0
```

Pour voir le cas « on avait basculé » : provoque l'échec **après** la
bascule (un `tools/smoke.sh` temporairement modifié pour échouer sur le
port 80 ; ou une image dont `/api/factures` renvoie 500). Le `rescue`
appelle alors `switch.sh <ancienne> rollback-...` et `switch.log` contient
`switch -> green`, puis `switch -> blue (rollback-...)`, puis la ligne
`rollback`.

**5. Le runbook**

`docs/runbook-deploy.md` (sections, condensées ici — le fichier fait une
page) :

```markdown
# Runbook — livraison Factura v2

## Livrer en staging
Pousser sur `main` (PR fusionnée). `ci` construit `sha-xxxxxxx`, le
déploie en staging (bleu/vert), smoke. Vérifier : Actions → run vert,
`curl http://10.10.10.21/version`.

## Promouvoir en prod
1. Tag : `git tag -a v2.1.0 -m "..." && git push --tags` → `ci` publie
   `factura-*:v2.1.0`, et le déploie en staging (push de tag).
2. Vérifier que le staging répond `v2.1.0`, faire les tests métier.
3. `make promote TAG=v2.1.0` (ou Actions → cd-prod → Run workflow).
   Garde-fous : format, image présente, staging = tag. Puis bleu/vert,
   smoke, release Gitea.
4. Vérifier `curl http://10.10.10.31/version`, Grafana (taux d'erreur).

## Revenir en arrière (< 2 min)
L'ancienne couleur tourne encore :
  ssh deploy@10.10.10.31 /srv/factura/bin/switch.sh blue "retour v2.0.0"
Vérifier `/version`. Puis relancer un `cd-prod` avec l'ancien tag pour
que `state.env` et le worker soient cohérents (le switch manuel ne
touche pas au worker).

## Si le smoke échoue en prod
Le rôle a déjà rebasculé (`switch.log` : `rollback`). La prod répond
avec l'ancien tag. Lire le run rouge, `docker compose logs api-<couleur>`
sur la VM, corriger dans une PR, repasser par le staging.

## Quelle version tourne ?
  curl http://10.10.10.31/version            # tag + couleur
  ssh deploy@10.10.10.31 cat /srv/factura/state.env
  ssh deploy@10.10.10.31 docker inspect --format '{{index .RepoDigests 0}}' \
    factura-api-blue-1                       # digest = identité réelle
Comparer le digest avec la release Gitea du tag.

## Sinistre (PB.9)
RPO 24 h (sauvegarde 02:30), RTO mesuré : voir docs/rebuild-<date>.log.
  tools/rebuild.sh prod v2.1.0
```

::: pourquoi
**La couleur inactive reçoit le nouveau tag, l'ancienne reste en vie** :
c'est ce qui donne un retour arrière en 5 secondes (`switch.sh`), sans
pull ni démarrage. Le coût est une deuxième instance d'API en mémoire
(≈ 60 Mo ici) : dérisoire face à un redémarrage raté à 18 h.

**`nginx -s reload` et pas `restart`** : le reload lance de nouveaux
workers avec la nouvelle configuration et laisse les anciens finir leurs
connexions, puis les arrête. Aucun `accept()` n'est raté : le socket
d'écoute est partagé. Un `restart` ferme le socket pendant quelques
centaines de millisecondes : la boucle `curl` de la preuve verrait des
`connection refused`. La variable `switched` distingue les deux cas
d'échec : avant la bascule (rien à défaire côté trafic) et après (il
faut rebasculer).

**Trois garde-fous avant la prod** : le format (`v9.9.9` passe, mais
`sha-xxx` ou `latest` non — on ne promeut que des versions nommées), la
présence de l'image (le tag existe dans le registre : sinon le pull
échouerait sur la VM de prod, en plein déploiement), et « le staging
tourne ce tag » : on promeut **ce qui a été testé**, jamais autre chose.
Les trois échouent vite, avant toute action sur la prod.

**La CI n'écrit pas dans Git** : un commit automatique de
`deployments.log` crée des boucles (push → CI → push), des conflits, et
brouille l'historique. La trace vit dans Gitea (release avec le digest,
run archivé) et sur la VM (`switch.log`). `git log` reste l'histoire du
code, pas celle des déploiements.

**Inventaire CI versionné plutôt que `tofu output`** : `tofu output` a
besoin de l'état, qui est local à `lab-adm` ; l'exposer au runner
impliquerait un backend distant (bonus) et un token Proxmox sur `lab-ops`.
Le fichier versionné est explicite, revu en PR, et `check-inventory.sh`
détecte la divergence des deux côtés (sur `lab-adm` : diff avec le
généré ; en CI : hostname réel).
:::

::: piege
* `meta: end_host` quand la couleur active tourne déjà le tag : sans ça,
  relancer `cd-prod` avec le même tag redéploie inutilement sur l'autre
  couleur et bascule — deux runs identiques feraient un ping-pong.
* `recreate: always` sur la couleur cible : sans lui, si `api-green`
  existe déjà (arrêtée, avec un ancien tag), Compose peut la redémarrer
  sans recréer... et `/version` renvoie l'ancien tag, le `until` expire,
  le `rescue` conclut à un rollback pour rien.
* `until:` avec `direct.json.version` : si `/version` renvoie autre chose
  que du JSON (502 de nginx en HTML pendant le démarrage), `direct.json`
  n'existe pas et l'expression lève une erreur au lieu de réessayer. La
  condition `direct.status == 200 and (...)` court-circuite : sur un 502,
  `status != 200` suffit à continuer d'attendre.
* Le `rescue` s'exécute aussi sur un timeout de `wait:` du module
  Compose. Il ne s'exécute **pas** si l'échec vient d'un `set_fact`
  (pas de tâche exécutée) ou d'un `end_host`. Et une erreur **dans** le
  `rescue` termine le play avec l'erreur du rescue, pas celle d'origine :
  d'où `failed_when: false` sur l'arrêt de la couleur.
* `switch.sh` à la main pour revenir en arrière ne touche pas au worker :
  il tourne avec le nouveau tag pendant que l'API répond l'ancien. Si le
  format des jobs a changé entre les deux, c'est un problème. Le runbook
  demande de relancer un déploiement avec l'ancien tag juste après.
* `curl -w '%header{docker-content-digest}'` : le `Accept` doit lister le
  type de manifeste OCI **et** Docker v2, sinon le registre renvoie le
  digest d'une conversion, différent de celui que `docker inspect` a
  publié. Compare les deux dans le journal : ils doivent coïncider.
:::

---

### **PB.8** — Observabilité : métriques, journaux, alertes, SLO

*Déployer par Ansible sur `lab-ops` la pile Prometheus, Alertmanager,
Grafana, Loki, blackbox et un récepteur de webhook ; scraper tout ; règles
SLI, alertes sur le budget d'erreur ; dashboard provisionné ; `docs/slo.md`.*

**1. Arborescence `infra/monitoring/`**

```
infra/monitoring/
  compose.yaml
  prometheus/prometheus.yml   prometheus/rules/recording.yml
  prometheus/rules/alerts.yml
  alertmanager/alertmanager.yml.j2     (template : mot de passe Grafana non,
                                        mais l'URL du sink oui)
  loki/loki.yml               blackbox/blackbox.yml
  alert-sink/sink.py
  grafana/provisioning/datasources/datasources.yml
  grafana/provisioning/dashboards/dashboards.yml
  grafana/dashboards/factura.json
```

`infra/monitoring/compose.yaml` :

```yaml
name: factura-monitoring
services:
  prometheus:
    image: prom/prometheus:v2.54.1
    restart: unless-stopped
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --storage.tsdb.retention.time=45d
      - --web.enable-lifecycle
    ports: ["9090:9090"]
    volumes:
      - ./prometheus:/etc/prometheus:ro
      - prom-data:/prometheus
  alertmanager:
    image: prom/alertmanager:v0.27.0
    restart: unless-stopped
    command:
      - --config.file=/etc/alertmanager/alertmanager.yml
      - --storage.path=/alertmanager
    ports: ["9093:9093"]
    volumes:
      - ./alertmanager:/etc/alertmanager:ro
      - am-data:/alertmanager
  alert-sink:
    image: python:3.12-alpine
    restart: unless-stopped
    command: ["python", "/sink.py"]
    volumes:
      - ./alert-sink/sink.py:/sink.py:ro
      - ./data:/data
    user: "10001:10001"
  grafana:
    image: grafana/grafana:11.2.0
    restart: unless-stopped
    ports: ["3001:3000"]
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD__FILE: /run/secrets/grafana_admin
      GF_USERS_ALLOW_SIGN_UP: "false"
      GF_ANALYTICS_REPORTING_ENABLED: "false"
    secrets: [grafana_admin]
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
      - grafana-data:/var/lib/grafana
  loki:
    image: grafana/loki:3.2.0
    restart: unless-stopped
    command: ["-config.file=/etc/loki/loki.yml"]
    ports: ["3100:3100"]
    volumes:
      - ./loki:/etc/loki:ro
      - loki-data:/loki
  blackbox:
    image: prom/blackbox-exporter:v0.25.0
    restart: unless-stopped
    ports: ["9115:9115"]
    volumes:
      - ./blackbox:/etc/blackbox_exporter:ro
secrets:
  grafana_admin:
    file: ./secrets/grafana_admin
volumes:
  prom-data: {}
  am-data: {}
  grafana-data: {}
  loki-data: {}
```

`infra/monitoring/prometheus/prometheus.yml` :

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels: { site: lab }

rule_files: [/etc/prometheus/rules/*.yml]

alerting:
  alertmanagers:
    - static_configs: [{ targets: ["alertmanager:9093"] }]

scrape_configs:
  - job_name: prometheus
    static_configs: [{ targets: ["localhost:9090"], labels: { host: lab-ops } }]
  - job_name: alertmanager
    static_configs: [{ targets: ["alertmanager:9093"], labels: { host: lab-ops } }]
  - job_name: grafana
    static_configs: [{ targets: ["grafana:3000"], labels: { host: lab-ops } }]
  - job_name: loki
    static_configs: [{ targets: ["loki:3100"], labels: { host: lab-ops } }]

  - job_name: node
    static_configs:
      - targets: ["10.10.10.14:9100"]
        labels: { env: ops, role: ops, host: lab-ops }
      - targets: ["10.10.10.21:9100"]
        labels: { env: staging, role: web, host: factura-staging-web }
      - targets: ["10.10.10.22:9100"]
        labels: { env: staging, role: db, host: factura-staging-db }
      - targets: ["10.10.10.31:9100"]
        labels: { env: prod, role: web, host: factura-prod-web }
      - targets: ["10.10.10.32:9100"]
        labels: { env: prod, role: db, host: factura-prod-db }

  - job_name: factura-api
    metrics_path: /metrics
    static_configs:
      - targets: ["10.10.10.21:8081"]
        labels: { env: staging, role: web, host: factura-staging-web, color: blue }
      - targets: ["10.10.10.21:8082"]
        labels: { env: staging, role: web, host: factura-staging-web, color: green }
      - targets: ["10.10.10.31:8081"]
        labels: { env: prod, role: web, host: factura-prod-web, color: blue }
      - targets: ["10.10.10.31:8082"]
        labels: { env: prod, role: web, host: factura-prod-web, color: green }

  - job_name: factura-worker
    static_configs:
      - targets: ["10.10.10.21:9200"]
        labels: { env: staging, role: web, host: factura-staging-web }
      - targets: ["10.10.10.31:9200"]
        labels: { env: prod, role: web, host: factura-prod-web }

  - job_name: redis
    static_configs:
      - targets: ["10.10.10.21:9121"]
        labels: { env: staging, role: web, host: factura-staging-web }
      - targets: ["10.10.10.31:9121"]
        labels: { env: prod, role: web, host: factura-prod-web }

  - job_name: postgres
    static_configs:
      - targets: ["10.10.10.22:9187"]
        labels: { env: staging, role: db, host: factura-staging-db }
      - targets: ["10.10.10.32:9187"]
        labels: { env: prod, role: db, host: factura-prod-db }

  - job_name: blackbox-http
    metrics_path: /probe
    params: { module: [http_2xx] }
    static_configs:
      - targets: ["http://10.10.10.21/health"]
        labels: { env: staging, role: web }
      - targets: ["http://10.10.10.31/health"]
        labels: { env: prod, role: web }
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox:9115
```

`infra/monitoring/prometheus/rules/recording.yml` :

```yaml
groups:
  - name: factura-sli
    interval: 15s
    rules:
      - record: factura:http_requests:rate5m
        expr: sum by (env) (rate(factura_http_requests_total[5m]))
      - record: factura:http_errors:ratio_rate5m
        expr: >
          sum by (env) (rate(factura_http_requests_total{status=~"5.."}[5m]))
          / sum by (env) (rate(factura_http_requests_total[5m]))
      - record: factura:http_errors:ratio_rate30m
        expr: >
          sum by (env) (rate(factura_http_requests_total{status=~"5.."}[30m]))
          / sum by (env) (rate(factura_http_requests_total[30m]))
      - record: factura:http_errors:ratio_rate1h
        expr: >
          sum by (env) (rate(factura_http_requests_total{status=~"5.."}[1h]))
          / sum by (env) (rate(factura_http_requests_total[1h]))
      - record: factura:http_errors:ratio_rate6h
        expr: >
          sum by (env) (rate(factura_http_requests_total{status=~"5.."}[6h]))
          / sum by (env) (rate(factura_http_requests_total[6h]))
      - record: factura:http_latency:p95_5m
        expr: >
          histogram_quantile(0.95,
            sum by (le, env) (rate(factura_http_request_seconds_bucket[5m])))
      - record: factura:error_budget:remaining_30d
        expr: >
          1 - (
            sum by (env) (increase(factura_http_requests_total{status=~"5.."}[30d]))
            / sum by (env) (increase(factura_http_requests_total[30d]))
          ) / 0.005
```

`infra/monitoring/prometheus/rules/alerts.yml` :

```yaml
groups:
  - name: factura-alerts
    rules:
      - alert: Watchdog
        expr: vector(1)
        labels: { severity: none }
        annotations:
          summary: "Chaîne d'alerte vivante"
          description: >-
            Toujours firing : si cette alerte cesse d'arriver dans
            alerts.log, la chaîne Prometheus -> Alertmanager -> sink est
            cassée.
          runbook: "docs/runbook-deploy.md#supervision"

      - alert: InstanceDown
        expr: up == 0
        for: 2m
        labels: { severity: critical }
        annotations:
          summary: "{{ $labels.job }} sur {{ $labels.host }} ne répond plus"
          description: >-
            Cible {{ $labels.instance }} (env {{ $labels.env }})
            down depuis 2 min.
          runbook: "docs/runbook-deploy.md#instance-down"

      - alert: FacturaApiDown
        expr: probe_success{job="blackbox-http"} == 0
        for: 1m
        labels: { severity: critical }
        annotations:
          summary: "Factura {{ $labels.env }} ne répond pas sur /health"
          description: >-
            Sonde blackbox {{ $labels.instance }} en échec depuis 1 min :
            l'application est indisponible pour les utilisateurs.
          runbook: "docs/runbook-deploy.md#api-down"

      - alert: FacturaErrorBudgetBurn
        expr: >
          factura:http_errors:ratio_rate1h > (14.4 * 0.005)
          and factura:http_errors:ratio_rate5m > (14.4 * 0.005)
        for: 2m
        labels: { severity: critical }
        annotations:
          summary: "Budget d'erreur {{ $labels.env }} brûlé à 14,4x"
          description: >-
            Taux de 5xx > 7,2 % sur 1 h et sur 5 min : 2 % du budget
            mensuel consommé en 1 h. Page.
          runbook: "docs/slo.md#burn"

      - alert: FacturaErrorBudgetBurn
        expr: >
          factura:http_errors:ratio_rate6h > (6 * 0.005)
          and factura:http_errors:ratio_rate30m > (6 * 0.005)
        for: 5m
        labels: { severity: warning }
        annotations:
          summary: "Budget d'erreur {{ $labels.env }} brûlé à 6x"
          description: >-
            Taux de 5xx > 3 % sur 6 h et 30 min : 5 % du budget consommé
            en 6 h. Ticket.
          runbook: "docs/slo.md#burn"

      - alert: FacturaQueueBacklog
        expr: redis_key_size{key="factura:jobs"} > 100
        for: 10m
        labels: { severity: warning }
        annotations:
          summary: "File factura:jobs en retard ({{ $labels.env }})"
          description: >-
            {{ $value }} jobs en attente depuis 10 min : worker arrêté ou
            base injoignable.
          runbook: "docs/runbook-deploy.md#backlog"

      - alert: FacturaBackupTooOld
        expr: >
          (time() - factura_backup_last_success_timestamp) > 26 * 3600
          or absent(factura_backup_last_success_timestamp)
        for: 15m
        labels: { severity: warning }
        annotations:
          summary: "Aucune sauvegarde récente ({{ $labels.env }})"
          description: >-
            Dernière sauvegarde réussie il y a plus de 26 h, ou métrique
            absente (timer ? rsync ? textfile ?).
          runbook: "docs/runbook-deploy.md#sauvegarde"

      - alert: DiskWillFillIn4h
        expr: >
          predict_linear(
            node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"}[1h],
            4 * 3600) < 0
          and node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} < 5e9
        for: 30m
        labels: { severity: warning }
        annotations:
          summary: "{{ $labels.host }}:{{ $labels.mountpoint }} plein dans < 4 h"
          description: >-
            Au rythme de la dernière heure, le système de fichiers sera
            plein avant 4 h.
          runbook: "docs/runbook-deploy.md#disque"

      - alert: AlertmanagerSilenceTooLong
        expr: alertmanager_silences{state="active"} > 0
        for: 12h
        labels: { severity: warning }
        annotations:
          summary: "Un silence Alertmanager dure depuis plus de 12 h"
          description: >-
            Un silence oublié rend les alertes muettes (INC-B4).
            amtool silence query.
          runbook: "docs/runbook-deploy.md#silences"
```

`infra/monitoring/alertmanager/alertmanager.yml` :

```yaml
global:
  resolve_timeout: 5m

route:
  receiver: sink
  group_by: [alertname, env]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - matchers: [alertname = Watchdog]
      receiver: sink
      group_wait: 0s
      repeat_interval: 1h
    - matchers: [severity = critical]
      receiver: sink
      repeat_interval: 1h

receivers:
  - name: sink
    webhook_configs:
      - url: http://alert-sink:8080/alert
        send_resolved: true

inhibit_rules:
  - source_matchers: [severity = critical]
    target_matchers: [severity = warning]
    equal: [alertname, env]
```

`infra/monitoring/alert-sink/sink.py` (le « Slack » du lab) :

```python
#!/usr/bin/env python3
"""alert-sink : reçoit les webhooks Alertmanager, une ligne par alerte."""
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = "/data/alerts.log"


class H(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(n) or b"{}")
        with open(LOG, "a", encoding="utf-8") as f:
            for a in body.get("alerts", []):
                lab = a.get("labels", {})
                f.write("%s %s %s env=%s severity=%s %s\n" % (
                    time.strftime("%Y-%m-%dT%H:%M:%S%z"), a.get("status"),
                    lab.get("alertname"), lab.get("env", "-"),
                    lab.get("severity", "-"),
                    a.get("annotations", {}).get("summary", "")))
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok\n")

    def log_message(self, *args):
        pass


HTTPServer(("0.0.0.0", 8080), H).serve_forever()
```

`infra/monitoring/blackbox/blackbox.yml` :

```yaml
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_status_codes: [200]
      method: GET
      fail_if_body_not_matches_regexp: ['"status":\s*"ok"']
      preferred_ip_protocol: ip4
```

`infra/monitoring/loki/loki.yml` :

```yaml
auth_enabled: false
server:
  http_listen_port: 3100
  grpc_listen_port: 9096
common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore: { store: inmemory }
schema_config:
  configs:
    - from: "2024-01-01"
      store: tsdb
      object_store: filesystem
      schema: v13
      index: { prefix: index_, period: 24h }
limits_config:
  retention_period: 336h
  reject_old_samples: true
  reject_old_samples_max_age: 168h
compactor:
  working_directory: /loki/compactor
  retention_enabled: true
  delete_request_store: filesystem
ruler:
  alertmanager_url: http://alertmanager:9093
analytics:
  reporting_enabled: false
```

`infra/monitoring/grafana/provisioning/datasources/datasources.yml` :

```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
  - name: Loki
    uid: loki
    type: loki
    access: proxy
    url: http://loki:3100
```

`infra/monitoring/grafana/provisioning/dashboards/dashboards.yml` :

```yaml
apiVersion: 1
providers:
  - name: factura
    folder: Factura
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: false
    options:
      path: /var/lib/grafana/dashboards
```

`infra/monitoring/grafana/dashboards/factura.json` : construis-le dans
Grafana (variable `env` = `label_values(factura_http_requests_total,
env)`), exporte-le (*Share → Export → Export for sharing externally*
**décoché**, pour garder `"datasource": {"uid": "prometheus"}`), fixe
`"uid": "factura-main"`, `"id": null`, et versionne. Panneaux attendus,
avec leur requête :

| Panneau | Requête |
|---|---|
| Requêtes/s par env, couleur | `sum by (env, color) (rate(factura_http_requests_total[5m]))` |
| Taux 5xx | `factura:http_errors:ratio_rate5m` (unité `percentunit`, seuil 0,005) |
| Latence p95 | `factura:http_latency:p95_5m` (seuil 0,3 s) |
| File Redis | `redis_key_size{key="factura:jobs"}` |
| Jobs worker | `sum by (env, result) (rate(factura_jobs_processed_total[5m]))` |
| Budget restant 30 j | `factura:error_budget:remaining_30d` (stat, `percentunit`, rouge < 0) |
| Burn rate 1 h / 6 h | `factura:http_errors:ratio_rate1h / 0.005`, `..._rate6h / 0.005` |
| Âge sauvegarde | `time() - factura_backup_last_success_timestamp` (unité `s`) |
| Erreurs (Loki) | `{env="$env", container=~"factura-api.*"} \| json \| level="ERROR"` |

**2. Déploiement par Ansible**

`ansible/inventory/group_vars/ops/vault.yml` (avant chiffrement) :

```yaml
vault_grafana_admin_password: "Ops-Grafana-2026"
```

`ansible/inventory/group_vars/ops/main.yml` :

```yaml
grafana_admin_password: "{{ vault_grafana_admin_password }}"
monitoring_dir: /opt/factura-monitoring
```

`ansible/playbooks/monitoring.yml` :

```yaml
---
- name: Pile de supervision Factura sur lab-ops
  hosts: ops
  become: true
  vars:
    src: "{{ playbook_dir }}/../../infra/monitoring"
  tasks:
    - name: Ancienne pile du module 22 arrêtée (si présente)
      community.docker.docker_compose_v2:
        project_src: /opt/observabilite
        state: absent
      failed_when: false

    - name: Arborescence
      ansible.builtin.file:
        path: "{{ monitoring_dir }}/{{ item.p }}"
        state: directory
        owner: "{{ item.o | default('root') }}"
        group: "{{ item.o | default('root') }}"
        mode: "{{ item.m | default('0755') }}"
      loop:
        - { p: "" }
        - { p: secrets, m: "0700" }
        - { p: data, o: "10001", m: "0750" }

    - name: Configurations (copie récursive du dépôt)
      ansible.builtin.copy:
        src: "{{ src }}/{{ item }}"
        dest: "{{ monitoring_dir }}/"
        owner: root
        group: root
        mode: preserve
        directory_mode: "0755"
      loop: [compose.yaml, prometheus, alertmanager, loki, blackbox,
             alert-sink, grafana]
      notify: [Reload prometheus, Reload alertmanager]

    - name: Mot de passe admin Grafana (depuis le vault)
      ansible.builtin.copy:
        dest: "{{ monitoring_dir }}/secrets/grafana_admin"
        content: "{{ grafana_admin_password }}"
        owner: root
        group: root
        mode: "0644"
      no_log: true

    - name: Vérification des configurations avant démarrage
      ansible.builtin.command:
        cmd: >
          docker run --rm -v {{ monitoring_dir }}/prometheus:/etc/prometheus:ro
          --entrypoint promtool prom/prometheus:v2.54.1
          check config /etc/prometheus/prometheus.yml
      changed_when: false

    - name: amtool check-config
      ansible.builtin.command:
        cmd: >
          docker run --rm -v {{ monitoring_dir }}/alertmanager:/etc/alertmanager:ro
          --entrypoint amtool prom/alertmanager:v0.27.0
          check-config /etc/alertmanager/alertmanager.yml
      changed_when: false

    - name: Pile démarrée
      community.docker.docker_compose_v2:
        project_src: "{{ monitoring_dir }}"
        state: present
        remove_orphans: true
        wait: true

  handlers:
    - name: Reload prometheus
      ansible.builtin.uri:
        url: http://127.0.0.1:9090/-/reload
        method: POST
        status_code: [200, 204]
      failed_when: false
    - name: Reload alertmanager
      ansible.builtin.uri:
        url: http://127.0.0.1:9093/-/reload
        method: POST
        status_code: [200, 204]
      failed_when: false
```

```bash
cd ~/factura-v2
ansible-vault encrypt ansible/inventory/group_vars/ops/vault.yml
ansible-playbook -i ansible/inventory/ops.ini ansible/playbooks/monitoring.yml
curl -s http://lab-ops:9090/api/v1/targets | jq '[.data.activeTargets[]
  | select(.health != "up") | .labels.instance]'         # []
curl -s http://lab-ops:9093/api/v2/alerts | jq '.[].labels.alertname'
#  "Watchdog"  "FacturaBackupTooOld" (normal avant PB.9)
ssh mathieu@lab-ops tail -n 2 /opt/factura-monitoring/data/alerts.log
```

Le `secrets/grafana_admin` en 0644 : Grafana tourne en uid 472 dans le
conteneur ; un fichier 0600 root lui serait illisible. Le répertoire
`secrets/` en 0700 le protège des autres comptes de `lab-ops`.

**3. Preuves**

```bash
# FacturaApiDown : arrêt des deux couleurs sur le staging
ssh deploy@10.10.10.21 'cd /srv/factura && docker compose --profile blue \
  --profile green stop api-blue api-green'
date -Is                                       # T0
watch -n 10 'curl -s http://lab-ops:9093/api/v2/alerts \
  | jq -r ".[].labels.alertname"'
ssh mathieu@lab-ops 'tail -f /opt/factura-monitoring/data/alerts.log'
#  2026-09-15T14:03:41+0200 firing FacturaApiDown env=staging severity=critical ...
#  -> T0 + 2 min 10 s (for: 1m + scrape 15 s + group_wait 30 s + évaluation)
ssh deploy@10.10.10.21 'cd /srv/factura && docker compose --profile blue \
  --profile green start api-blue'
#  ... resolved FacturaApiDown env=staging ...  (T0 + ~5 min, resolve_timeout)

# Burn : des 5xx sans toucher au code -> bascule vers une couleur arrêtée
ssh deploy@10.10.10.21 'cd /srv/factura && printf \
  "upstream factura_api { server api-green:8000; }\n" > nginx/active.conf.tmp'
# (switch.sh refuse une couleur qui ne répond pas : c'est le but ; pour la
#  preuve, on coupe la base à la place, ce qui donne des 503 sur /health
#  et des 500 sur /api/factures)
ssh mathieu@10.10.10.22 'cd /srv/factura && docker compose stop postgres'
for i in $(seq 200); do
  [ $((i % 10)) -lt 3 ] && p=/api/factures || p=/version
  curl -s -o /dev/null "http://10.10.10.21$p"
done
#  factura:http_errors:ratio_rate5m{env="staging"} ≈ 0.30 > 0.072
#  -> FacturaErrorBudgetBurn (critical) pending puis firing après 2 min ;
#     la version warning est inhibée (même alertname et env).
ssh mathieu@10.10.10.22 'cd /srv/factura && docker compose start postgres'
```

Loki :

```bash
curl -s -X POST -H 'Content-Type: application/json' -d '{"client":""}' \
  http://10.10.10.31/api/factures                         # 400
curl -sG http://lab-ops:3100/loki/api/v1/query_range \
  --data-urlencode \
    'query={env="prod", container=~"factura-api.*"} | json | level="ERROR"' \
  --data-urlencode "start=$(date -d '-1 hour' +%s)000000000" \
  | jq '.data.result | length'
curl -sG http://lab-ops:3100/loki/api/v1/query_range \
  --data-urlencode \
    'query={env="prod", container=~"factura-api.*"} |= "POST /api/factures"' \
  | jq -r '.data.result[0].values[0][1]'
```

Un `400` n'est pas une erreur applicative (pas de `level=ERROR`) ; pour en
produire une, la base coupée ci-dessus donne `psycopg.OperationalError`
dans `/health` → `log.exception` → `ERROR`. Les journaux d'accès Gunicorn
(`|= "POST /api/factures"`) sont là, ligne par requête.

**4. `docs/slo.md`**

```markdown
# SLO Factura

## SLI
* Disponibilité : part des requêtes HTTP non-5xx, par env, calculée par
  `1 - factura:http_errors:ratio_rate5m` (source :
  `factura_http_requests_total{status=~"5.."}` / total).
* Latence : part des requêtes servies en moins de 300 ms :
  `sum(rate(factura_http_request_seconds_bucket{le="0.25"}[5m]))
   / sum(rate(factura_http_request_seconds_count[5m]))`
  (bucket 0,25 s : le plus proche de 300 ms dans l'histogramme fourni ;
  demander aux devs un bucket 0,3).

## SLO (30 jours glissants)
* 99,5 % des requêtes non-5xx.
* 95 % des requêtes sous 300 ms.

## Budget d'erreur
0,5 % de 30 jours = 216 minutes = 3 h 36 d'indisponibilité totale, ou
0,5 % de requêtes en erreur réparties sur le mois. Sur 50 000 requêtes/mois
(mesuré), 250 requêtes en erreur.

## Burn rate
| Fenêtre longue | Fenêtre courte | Seuil | Budget consommé | Sévérité |
|---|---|---|---|---|
| 1 h | 5 min | 14,4× (7,2 % d'erreurs) | 2 % en 1 h | critical (page) |
| 6 h | 30 min | 6× (3 %) | 5 % en 6 h | warning (ticket) |
La fenêtre courte confirme que l'incident est en cours ; sans elle,
l'alerte 1 h reste firing 55 min après la fin de l'incident.

## Quand le budget est consommé
Gel des déploiements non correctifs jusqu'au retour du budget
positif ; post-mortem obligatoire ; la priorité de l'équipe devient la
fiabilité. Le stat « budget restant » du dashboard est le point d'entrée
de la réunion hebdomadaire.

## Pourquoi pas 99,99 %
99,99 % = 4 min 19 par mois. Une seule promotion ratée avec rollback
automatique (≈ 90 s) en consommerait un tiers ; une VM Proxmox qui
redémarre (2 min) la moitié. Le tenir demanderait deux VM web derrière
un répartiteur, une base répliquée, un Proxmox en cluster : plusieurs
milliers d'euros et un second admin. Personne chez Ravel & Associés ne
fait de facture à 3 h du matin : 99,5 % couvre le besoin réel, et laisse
un budget pour déployer souvent. On revoit le SLO si le besoin change.
```

::: pourquoi
**Alerter sur le burn rate et pas sur le CPU** : « CPU > 80 % » est une
cause possible parmi cent, et souvent sans effet utilisateur. Le taux de
5xx **est** l'effet utilisateur. Les deux fenêtres (longue pour la
signification statistique, courte pour la fraîcheur) évitent les deux
défauts classiques : alerter sur un pic de 30 s, et alerter une heure
après la fin de l'incident. Les seuils 14,4 et 6 viennent du SRE
Workbook : ils correspondent à « consomme 2 % du budget en 1 h » et
« 5 % en 6 h », soit un incident qui, s'il durait, épuiserait le budget
mensuel en 2 jours ou en 5 jours.

**Règles d'enregistrement** : la même expression sert au dashboard, à
l'alerte et au check ; Prometheus la calcule une fois toutes les 15 s au
lieu de la recalculer à chaque affichage ; et le nom
`factura:http_errors:ratio_rate5m` (niveau:métrique:opération) dit ce
qu'il contient. La version `increase(...[30d])` du budget restant
compte réellement les requêtes du mois, là que `sum_over_time` d'un ratio
donnait une moyenne de ratios (fausse quand le trafic varie).

**Watchdog** : une alerte toujours `firing`, routée sans attente. Si
elle cesse d'arriver dans `alerts.log`, ce n'est pas que tout va bien :
c'est que la chaîne est cassée. C'est la seule façon de superviser la
supervision sans second système.

**`FacturaBackupTooOld` avec `absent()`** : une alerte qui dépend d'une
métrique posée par un script est muette si le script ne tourne jamais
(métrique absente = pas de série = pas d'alerte). `or absent(...)` fait
que « aucune sauvegarde n'a jamais eu lieu » alerte aussi. C'est
pourquoi l'alerte est `firing` dès PB.8 : elle prouve qu'elle marche.

**Un sink de webhook plutôt que Slack** : le lab n'a pas d'Internet
garanti ; un fichier `alerts.log` est vérifiable par le check et
lisible avec `tail -f`. La configuration Alertmanager est exactement
celle qu'on aurait avec Slack (`slack_configs` à la place de
`webhook_configs`).

**Grafana provisionné par fichiers** : un dashboard cliqué dans l'UI
disparaît avec le volume ; un JSON versionné se relit, se revoit en PR
et se redéploie par `monitoring.yml`. `allowUiUpdates: false` empêche
qu'une modification à la souris diverge du dépôt.
:::

::: piege
* Le port de Grafana : la pile du module 22 utilisait 3001 aussi ; si
  `/opt/observabilite` tourne encore, le `up -d` échoue avec « port is
  already allocated ». Le playbook l'arrête d'abord.
* `promtool check rules` sur `alerts.yml` : deux alertes du même nom
  (`FacturaErrorBudgetBurn` en `critical` et `warning`) sont légales et
  voulues — c'est l'inhibition qui les articule (`equal: [alertname,
  env]`). Deux règles avec **exactement** les mêmes labels seraient
  fusionnées : la sévérité les distingue.
* Le job `factura-api` a quatre cibles dont, en régime normal, une par
  env est **éteinte** (la couleur inactive après un rollback, ou avant
  le premier bleu/vert) : `up == 0` et `InstanceDown` se déclencheraient.
  Solution retenue : après un déploiement réussi, les deux couleurs
  tournent (l'ancienne reste en vie). Si tu préfères éteindre l'ancienne,
  ajoute `unless on (instance) ...` ou un `job!="factura-api"` à
  `InstanceDown` et surveille l'API par blackbox seulement.
* `fail_if_body_not_matches_regexp` sur `"status":"ok"` : `/health`
  répond 200 avec `status: ok` ou 503 avec `degraded`. Sans le regexp,
  un 503 fait déjà échouer la sonde (`valid_status_codes: [200]`) ; le
  regexp est là pour le jour où quelqu'un met `/health` en 200
  permanent.
* Loki 3 refuse les lignes plus vieilles que `reject_old_samples_max_age`
  : une VM dont l'horloge retarde (chrony pas encore synchronisé au
  premier boot) voit ses premières lignes rejetées, promtail affiche
  `entry too far behind`. Ce n'est pas une panne, c'est PB.3 qui n'a pas
  encore tourné.
* La sonde blackbox depuis le conteneur : `10.10.10.21` est joignable
  parce que `lab-ops` est dans le `/24` et que le port 80 est ouvert au
  réseau. Les ports 8081/8082 sont ouverts à `10.10.10.14` — la source
  vue par la VM est l'IP de `lab-ops` (SNAT Docker), donc le scrape
  passe. Sans cette règle ufw, `up == 0` sur `factura-api`.
:::

---

### **PB.9** — Sauvegardes, restauration testée par la CI, reconstruction chronométrée

*Rôle `pg_backup` (script, timer, rsync vers `lab-ops`, métrique dans le
textfile collector), `restore.yml`, job CI hebdomadaire de restauration,
et `tools/rebuild.sh prod <tag>` en moins de 60 minutes.*

**1. Le rôle `pg_backup`**

`ansible/roles/pg_backup/defaults/main.yml` :

```yaml
pg_backup_user: deploy
pg_backup_dir: /srv/factura/backups
pg_backup_container: factura-postgres-1
pg_backup_db: factura
pg_backup_db_user: factura
pg_backup_retention_days: 7
pg_backup_remote_user: backup
pg_backup_remote_host: 10.10.10.14
pg_backup_remote_dir: "/srv/backups/factura/{{ factura_env }}"
pg_backup_textfile: /var/lib/prometheus/node-exporter/factura.prom
pg_backup_on_calendar: "*-*-* 02:30:00"
```

`ansible/roles/pg_backup/tasks/main.yml` :

```yaml
---
- name: Répertoire local des sauvegardes
  ansible.builtin.file:
    path: "{{ pg_backup_dir }}"
    state: directory
    owner: "{{ pg_backup_user }}"
    group: "{{ pg_backup_user }}"
    mode: "0750"

- name: Clé SSH du compte deploy (rsync vers lab-ops)
  community.crypto.openssh_keypair:
    path: "/home/{{ pg_backup_user }}/.ssh/id_ed25519"
    type: ed25519
    comment: "{{ pg_backup_user }}@{{ inventory_hostname }} backup"
    owner: "{{ pg_backup_user }}"
    group: "{{ pg_backup_user }}"
    mode: "0600"
  register: deploy_key

- name: Clé d'hôte de lab-ops connue de deploy
  ansible.builtin.known_hosts:
    path: "/home/{{ pg_backup_user }}/.ssh/known_hosts"
    name: "{{ pg_backup_remote_host }}"
    key: >-
      {{ lookup('ansible.builtin.pipe',
                'ssh-keyscan -t ed25519 ' ~ pg_backup_remote_host) }}
  become_user: "{{ pg_backup_user }}"

- name: Script de sauvegarde
  ansible.builtin.template:
    src: factura-backup.sh.j2
    dest: /usr/local/sbin/factura-backup.sh
    owner: root
    group: root
    mode: "0755"

- name: Service et timer
  ansible.builtin.template:
    src: "{{ item }}.j2"
    dest: "/etc/systemd/system/{{ item }}"
    owner: root
    group: root
    mode: "0644"
  loop: [factura-backup.service, factura-backup.timer]
  notify: Reload systemd

- name: Flush handlers
  ansible.builtin.meta: flush_handlers

- name: Timer actif
  ansible.builtin.systemd:
    name: factura-backup.timer
    state: started
    enabled: true
```

`ansible/roles/pg_backup/handlers/main.yml` :

```yaml
---
- name: Reload systemd
  ansible.builtin.systemd:
    daemon_reload: true
```

`ansible/roles/pg_backup/templates/factura-backup.sh.j2` :

```bash
#!/usr/bin/env bash
# {{ ansible_managed }}
# factura-backup.sh — dump PostgreSQL, hash, meta, rétention, rsync,
# métriques node_exporter. Tourne en {{ pg_backup_user }} (timer 02:30).
set -euo pipefail
DIR="{{ pg_backup_dir }}"
CTN="{{ pg_backup_container }}"
DB="{{ pg_backup_db }}"; DBU="{{ pg_backup_db_user }}"
ENV="{{ factura_env }}"
REMOTE="{{ pg_backup_remote_user }}@{{ pg_backup_remote_host }}"
REMOTE="$REMOTE:{{ pg_backup_remote_dir }}/"
PROM="{{ pg_backup_textfile }}"
KEEP={{ pg_backup_retention_days }}
STAMP=$(date +%Y%m%d-%H%M%S)
BASE="$DIR/factura-$ENV-$STAMP"
T0=$(date +%s)

log() { printf '%s factura-backup %s\n' "$(date -Is)" "$*"; }
metrics() {  # metrics <ok:0|1> <size> <dur>
  local tmp="$PROM.tmp"
  {
    echo "# HELP factura_backup_last_run_timestamp Dernière exécution (epoch)"
    echo "# TYPE factura_backup_last_run_timestamp gauge"
    echo "factura_backup_last_run_timestamp{env=\"$ENV\"} $(date +%s)"
    if [ "$1" -eq 1 ]; then
      echo "# HELP factura_backup_last_success_timestamp Dernier succès (epoch)"
      echo "# TYPE factura_backup_last_success_timestamp gauge"
      echo "factura_backup_last_success_timestamp{env=\"$ENV\"} $(date +%s)"
      echo "# HELP factura_backup_size_bytes Taille du dernier dump"
      echo "# TYPE factura_backup_size_bytes gauge"
      echo "factura_backup_size_bytes{env=\"$ENV\"} $2"
      echo "# HELP factura_backup_duration_seconds Durée de la sauvegarde"
      echo "# TYPE factura_backup_duration_seconds gauge"
      echo "factura_backup_duration_seconds{env=\"$ENV\"} $3"
    else
      # on garde le dernier succès connu, s'il existe
      grep '^factura_backup_\(last_success_timestamp\|size_bytes\)' "$PROM" \
        2>/dev/null || true
    fi
  } > "$tmp"
  mv "$tmp" "$PROM"     # écriture atomique : node_exporter ne lit jamais
                        # un fichier à moitié écrit
}
trap 'rc=$?; [ $rc -ne 0 ] && { log "ECHEC rc=$rc"; metrics 0 0 0; }' EXIT

log "début ($ENV)"
docker exec "$CTN" pg_dump -U "$DBU" -Fc "$DB" > "$BASE.dump"
sha256sum "$BASE.dump" | sed "s#$DIR/##" > "$BASE.sha256"
ROWS=$(docker exec "$CTN" psql -U "$DBU" -d "$DB" -Atc \
       'SELECT count(*) FROM factures')
SIZE=$(stat -c %s "$BASE.dump")
printf 'env=%s\ndate=%s\nrows_factures=%s\nsize=%s\nhost=%s\n' \
  "$ENV" "$STAMP" "$ROWS" "$SIZE" "$(hostname)" > "$BASE.meta"
find "$DIR" -name 'factura-*' -mtime +"$KEEP" -delete
rsync -a --delete-after --timeout=60 "$DIR/" "$REMOTE"
DUR=$(( $(date +%s) - T0 ))
metrics 1 "$SIZE" "$DUR"
log "OK $BASE.dump ($SIZE octets, $ROWS factures, ${DUR}s)"
```

`ansible/roles/pg_backup/templates/factura-backup.service.j2` :

```ini
[Unit]
Description=Sauvegarde PostgreSQL Factura ({{ factura_env }})
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User={{ pg_backup_user }}
Group={{ pg_backup_user }}
ExecStart=/usr/local/sbin/factura-backup.sh
Nice=10
IOSchedulingClass=idle
TimeoutStartSec=20min
PrivateTmp=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths={{ pg_backup_dir }} {{ pg_backup_textfile | dirname }}
```

`ansible/roles/pg_backup/templates/factura-backup.timer.j2` :

```ini
[Unit]
Description=Sauvegarde nocturne Factura ({{ factura_env }})

[Timer]
OnCalendar={{ pg_backup_on_calendar }}
RandomizedDelaySec=10min
Persistent=true
Unit=factura-backup.service

[Install]
WantedBy=timers.target
```

**2. Le playbook `backup.yml` (db, puis ops)**

`ansible/playbooks/backup.yml` :

```yaml
---
- name: Sauvegarde PostgreSQL sur les VM db
  hosts: db
  become: true
  roles:
    - pg_backup

- name: Réception des sauvegardes sur lab-ops
  hosts: ops
  become: true
  vars:
    backup_root: /srv/backups/factura
    backup_envs: >-
      {{ groups['db'] | map('extract', hostvars, 'factura_env')
         | unique | list }}
  tasks:
    - name: Paquet rsync (fournit /usr/bin/rrsync)
      ansible.builtin.apt:
        name: rsync
        state: present

    - name: Compte backup (shell requis pour la commande forcée)
      ansible.builtin.user:
        name: backup
        system: true
        shell: /bin/sh
        home: /srv/backups
        create_home: false

    - name: Arborescence des sauvegardes
      ansible.builtin.file:
        path: "{{ item.p }}"
        state: directory
        owner: backup
        group: backup
        mode: "{{ item.m }}"
      loop:
        - { p: /srv/backups, m: "0755" }
        - { p: "{{ backup_root }}", m: "0750" }
        - { p: "{{ backup_root }}/restore-tests", m: "0775" }
        - { p: /srv/backups/.ssh, m: "0700" }

    - name: Un répertoire par environnement
      ansible.builtin.file:
        path: "{{ backup_root }}/{{ item }}"
        state: directory
        owner: backup
        group: backup
        mode: "0750"
      loop: "{{ backup_envs }}"

    - name: Clés des VM db, restreintes à rrsync sur leur répertoire
      ansible.posix.authorized_key:
        user: backup
        path: /srv/backups/.ssh/authorized_keys
        manage_dir: false
        key: "{{ hostvars[item].deploy_key.public_key }}"
        key_options: >-
          restrict,from="{{ hostvars[item].ansible_host }}",command="/usr/bin/rrsync
          {{ backup_root }}/{{ hostvars[item].factura_env }}"
      loop: "{{ groups['db'] }}"

    - name: Lecture pour le runner CI et l'admin (groupe backup)
      ansible.builtin.user:
        name: "{{ item }}"
        groups: [backup]
        append: true
      loop: [runner, mathieu]
```

`deploy_key` est le `register` de `openssh_keypair` du play précédent :
Ansible garde les faits et registres des hôtes `db` accessibles via
`hostvars` dans le play `ops`. Le playbook a besoin des hôtes `db` **et**
de `lab-ops` : on passe les deux inventaires, Ansible les fusionne. Chaque
passage ajoute la clé de son environnement sans effacer l'autre (pas
d'`exclusive`).

```bash
cd ~/factura-v2
ansible-playbook -i ansible/inventory/staging.ini -i ansible/inventory/ops.ini \
  ansible/playbooks/backup.yml
ansible-playbook -i ansible/inventory/prod.ini -i ansible/inventory/ops.ini \
  ansible/playbooks/backup.yml
```

Première sauvegarde et vérification :

```bash
ssh mathieu@10.10.10.32 'sudo systemctl start factura-backup.service; \
  systemctl list-timers factura-backup.timer --no-pager; \
  cat /var/lib/prometheus/node-exporter/factura.prom'
ssh mathieu@lab-ops 'ls -l /srv/backups/factura/prod/'
#  factura-prod-20260915-104412.dump  .meta  .sha256
curl -sG http://lab-ops:9090/api/v1/query \
  --data-urlencode 'query=ALERTS{alertname="FacturaBackupTooOld"}' \
  | jq '.data.result | length'                              # 0 : inactive
```

**3. `restore.yml`**

`ansible/playbooks/restore.yml` :

```yaml
---
# Restauration du dernier dump de l'environnement depuis lab-ops.
# Lancé depuis lab-adm (mathieu, membre de backup sur lab-ops) :
#   ansible-playbook -i inventory/<env>.ini playbooks/restore.yml
- name: Restauration PostgreSQL Factura
  hosts: db
  become: true
  vars:
    backup_host: 10.10.10.14
    backup_root: "/srv/backups/factura/{{ factura_env }}"
    work: "/tmp/factura-restore"
    container: factura-postgres-1
  tasks:
    - name: Dernier dump disponible sur lab-ops
      ansible.builtin.command:
        cmd: ssh -o BatchMode=yes mathieu@{{ backup_host }}
             ls -1t {{ backup_root }}/
      delegate_to: localhost
      become: false
      register: listing
      changed_when: false

    - name: Nom du dump
      ansible.builtin.set_fact:
        dump: "{{ listing.stdout_lines | select('search', '\\.dump$') | first }}"

    - name: Base du nom (sans extension)
      ansible.builtin.set_fact:
        base: "{{ dump | regex_replace('\\.dump$', '') }}"

    - name: Rapatriement sur lab-adm (dump, sha256, meta)
      ansible.builtin.command:
        cmd: >
          rsync -a
          mathieu@{{ backup_host }}:{{ backup_root }}/{{ base }}.{dump,sha256,meta}
          {{ work }}/
      delegate_to: localhost
      become: false
      args:
        creates: "{{ work }}/{{ dump }}"

    - name: Copie sur la VM db
      ansible.builtin.copy:
        src: "{{ work }}/{{ base }}.{{ item }}"
        dest: "{{ work }}/"
        mode: "0640"
      loop: [dump, sha256, meta]

    - name: Vérification du hash
      ansible.builtin.command:
        cmd: sha256sum -c {{ base }}.sha256
        chdir: "{{ work }}"
      changed_when: false

    - name: Nombre de lignes attendu
      ansible.builtin.shell:
        cmd: awk -F= '/^rows_factures=/{print $2}' {{ work }}/{{ base }}.meta
      register: expected
      changed_when: false

    - name: pg_restore (clean, if-exists) dans le conteneur
      ansible.builtin.shell:
        cmd: >
          docker exec -i {{ container }} pg_restore -U factura -d factura
          --clean --if-exists --no-owner < {{ work }}/{{ dump }}
      changed_when: true

    - name: Nombre de lignes restauré
      ansible.builtin.command:
        cmd: docker exec {{ container }} psql -U factura -d factura -Atc
             "SELECT count(*) FROM factures"
      register: actual
      changed_when: false

    - name: Comparaison
      ansible.builtin.assert:
        that: actual.stdout | int == expected.stdout | int
        fail_msg: >-
          restauré {{ actual.stdout }} lignes, attendu {{ expected.stdout }}
        success_msg: "{{ actual.stdout }} factures restaurées depuis {{ dump }}"

    - name: Nettoyage
      ansible.builtin.file:
        path: "{{ work }}"
        state: absent
```

**4. Le job CI hebdomadaire**

`.gitea/workflows/restore-test.yaml` :

```yaml
name: restore-test
on:
  schedule:
    - cron: "0 4 * * 1"
  workflow_dispatch:

jobs:
  restore:
    runs-on: ops-host
    timeout-minutes: 20
    env:
      SRC: /srv/backups/factura/prod
      OUT: /srv/backups/factura/restore-tests
      CTN: restore-test-${{ gitea.run_id }}
    steps:
      - name: Dernier dump de prod et vérification du hash
        run: |
          DUMP=$(ls -1t "$SRC"/*.dump | head -1)
          [ -n "$DUMP" ] || { echo "aucun dump dans $SRC" >&2; exit 1; }
          B="${DUMP%.dump}"
          (cd "$SRC" && sha256sum -c "$(basename "$B").sha256")
          echo "DUMP=$DUMP" >> "$GITHUB_ENV"
          echo "META=$B.meta" >> "$GITHUB_ENV"
      - name: PostgreSQL jetable
        run: |
          docker run -d --name "$CTN" -e POSTGRES_PASSWORD=x \
            -e POSTGRES_USER=factura -e POSTGRES_DB=factura postgres:16-alpine
          for i in $(seq 30); do
            docker exec "$CTN" pg_isready -U factura -d factura && break
            sleep 2
          done
      - name: Restauration et comparaison
        run: |
          T0=$(date +%s)
          docker exec -i "$CTN" pg_restore -U factura -d factura \
            --clean --if-exists --no-owner < "$DUMP"
          ROWS=$(docker exec "$CTN" psql -U factura -d factura -Atc \
                 'SELECT count(*) FROM factures')
          EXP=$(awk -F= '/^rows_factures=/{print $2}' "$META")
          DUR=$(( $(date +%s) - T0 ))
          SIZE=$(stat -c %s "$DUMP")
          if [ "$ROWS" = "$EXP" ]; then R=ok; else R=fail; fi
          REPORT="$OUT/$(date +%Y%m%d-%H%M)-$R.txt"
          FMT='dump=%s\nsize=%s\nduration_s=%s\nrows=%s\nexpected=%s\nresult=%s\n'
          printf "$FMT" \
            "$(basename "$DUMP")" "$SIZE" "$DUR" "$ROWS" "$EXP" "$R" \
            | tee "$REPORT"
          [ "$R" = ok ]
      - name: Nettoyage
        if: always()
        run: docker rm -f "$CTN" >/dev/null 2>&1 || true
```

Le premier run se lance à la main (*Actions → restore-test → Run
workflow*) ; `ls /srv/backups/factura/restore-tests/` montre
`20260915-1112-ok.txt`.

**5. Reconstruction chronométrée**

`tools/rebuild.sh` est fourni : il attend `restore.yml` et l'inventaire
généré, et suppose que `baseline.yml` et `deploy.yml` marchent sur une VM
neuve. Sur le staging d'abord :

```bash
cd ~/factura-v2
source ~/.config/factura/pve.env; eval "$(ssh-agent -s)"; ssh-add
tools/rebuild.sh staging v2.1.0
tools/rebuild.sh prod v2.1.0
cat docs/rebuild-20260916-0915.log | grep -E '^\[|TOTAL'
```

```
[    0s] reconstruction prod démarrée (tag v2.1.0)
[    0s] 1/5 destruction des VM
[   48s] 2/5 provisionnement OpenTofu
[  302s] 3/5 baseline Ansible
[  611s] 4/5 déploiement de l'application (v2.1.0)
[  742s] 5/5 restauration de la dernière sauvegarde
[  801s]   ok   curl -fsS -m 5 http://10.10.10.31/health
...
[  804s] TOTAL: 804 s
```

**13 min 24 s** au lieu de « deux jours ». Analyse pour le journal : les
deux étapes les plus longues sont **la baseline** (309 s : `apt update` +
paquets sur deux VM, le téléchargement de promtail, `unattended-upgrades`)
et **le provisionnement** (254 s : clone plein de deux disques de 20 et
30 Go, `package_update` de cloud-init). Réductions possibles, non
implémentées : un template Proxmox préparé par Packer avec la baseline
déjà appliquée (la baseline tomberait à ≈ 40 s de vérification) ; un
miroir apt local sur `lab-ops` (`apt-cacher-ng`) ; des clones liés
(`full = false`) pour le staging.

Un point à gérer dans le rôle `pg_backup` après reconstruction : la clé
SSH de `deploy` est régénérée sur la nouvelle VM, donc `backup.yml` doit
être rejoué pour publier la nouvelle clé sur `lab-ops` — `rebuild.sh` ne
le fait pas ; ajoute-le en étape 6 (ou dans le runbook, juste après).

`docs/runbook-deploy.md`, section « Sinistre » :

```markdown
## Sinistre : reconstruction complète
RPO : 24 h au pire (sauvegarde à 02:30, restauration = dernier dump).
RTO : 13 min 24 s mesuré le 2026-09-16 (docs/rebuild-20260916-0915.log).
Procédure : source ~/.config/factura/pve.env ; ssh-agent chargé ;
  tools/rebuild.sh prod <tag en prod>   (tag : dernière release Gitea)
  ansible-playbook -i ansible/inventory/prod.ini -i ansible/inventory/ops.ini \
    ansible/playbooks/backup.yml          (nouvelle clé de sauvegarde)
Vérifier : smoke, Grafana (cibles up), FacturaBackupTooOld inactive après
la sauvegarde suivante (ou `systemctl start factura-backup` à la main).
RPO < 1 h : réplication logique PostgreSQL vers factura-staging-db
(publication/subscription, ~10 lignes de config, RPO ≈ secondes) ; ou
dumps horaires (`OnCalendar=hourly`, rétention 48 h : 48 × 2 Mo = trivial).
```

::: pourquoi
**Le compte `deploy` sauvegarde, pas root** : le script n'a besoin que du
socket Docker (groupe `docker`), du répertoire de sauvegarde et du
textfile collector (groupe `deploy`, `g+w` posé par le rôle
`node_exporter`). `ProtectSystem=strict` + `ReadWritePaths` dans l'unité
disent exactement où il peut écrire. Un script de sauvegarde en root avec
`rsync --delete` mal paramétré est un classique des post-mortems.

**`rrsync` avec `restrict,from=,command=`** : la clé de `deploy@prod-db`
ne peut que faire du rsync dans `/srv/backups/factura/prod/`, depuis
`10.10.10.32`, sans shell, sans redirection de port, sans agent. Une VM
de prod compromise ne peut ni lire les sauvegardes du staging, ni
toucher au reste de `lab-ops`. Le `--delete-after` côté client applique
la rétention de 7 jours sur le dépôt distant ; rrsync l'autorise (pas
d'option `-ro`).

**La métrique écrite atomiquement, et le dernier succès conservé** :
`node_exporter` lit le `.prom` à chaque scrape ; un `mv` sur le même
système de fichiers est atomique. En cas d'échec, le script réécrit
`last_run` mais garde `last_success` : l'alerte se déclenche 26 h après
le dernier **succès**, pas après le dernier essai. C'est la sémantique
que `FacturaBackupTooOld` attend.

**Une restauration hebdomadaire par la CI** : un test de restauration
fait par un humain est fait deux fois puis oublié. Un job planifié sur
le runner produit un rapport horodaté et un run rouge quand ça casse. Le
compte `runner` dans le groupe `backup` (lecture) et `restore-tests` en
`0775` : les droits sont posés par `backup.yml`, jamais à la main — le
check de PB.3 sur l'idempotence le verrait.

**Détruire la prod pour de vrai** : le seul test qui prouve que
l'infrastructure as code est complète. Tout ce qui manquait (un fichier
posé à la main, un `switch.log` supposé exister, une clé de sauvegarde
à republier) apparaît dans le premier `rebuild.sh staging`. C'est
pourquoi l'énoncé impose le staging d'abord.
:::

::: piege
* `pg_dump` dans le conteneur passe par la socket Unix locale, en
  `trust` (image officielle) : pas de mot de passe. Depuis l'hôte via
  `10.10.10.32:5432`, il en faudrait un — et ufw refuserait la VM
  elle-même ? Non, `lo`/l'IP locale n'est pas filtrée ; mais rester dans
  le conteneur évite d'exposer le mot de passe au script.
* `known_hosts` de `deploy` : la première connexion rsync vers `lab-ops`
  demande une confirmation interactive, que le timer ne peut pas donner :
  le service échoue avec `Host key verification failed`. La tâche
  `known_hosts` du rôle est là pour ça — et après une reconstruction de
  `lab-ops`, il faudra la rejouer.
* `--clean --if-exists` sans `--no-owner` : si le dump a été fait par
  `factura` et restauré par `factura`, pas de problème ; dans le conteneur
  jetable de la CI, le rôle existe aussi (`POSTGRES_USER=factura`). Avec
  un autre utilisateur, `pg_restore` râle sur chaque `ALTER OWNER`.
* Le rapport de restauration compte `factures`, pas les bytes : un dump
  tronqué qui passe le `sha256` (le hash a été calculé sur le fichier
  tronqué) serait détecté par le `count(*)` ≠ `.meta`. Le hash protège
  contre la corruption en transit, le compte contre une sauvegarde faite
  à moitié.
* `rebuild.sh` fait `ssh-keygen -R` puis `accept-new` : les nouvelles VM
  ont de nouvelles clés d'hôte. Mais le runner CI sur `lab-ops` a aussi un
  `known_hosts` (`ANSIBLE_HOST_KEY_CHECKING=false` dans les workflows
  le rend indifférent : c'est un compromis de lab, à noter).
* `RandomizedDelaySec=10min` sur staging et prod : deux rsync simultanés
  vers `lab-ops` ne se gênent pas, mais deux `pg_dump` sur le même
  Proxmox à la même seconde doublent le temps ; le décalage aléatoire
  lisse ça.
:::

---

### **PB.10** — L'API sur k3s, et le verdict Compose contre k3s

*Une VM `factura-k3s` par le workspace `k3s`, k3s installé par Ansible,
manifestes dans `k8s/` (probes, HPA, Ingress TLS, rolling update), scrape
et journaux branchés, et `docs/compose-vs-k3s.md` qui tranche.*

**1. La VM**

`infra/envs/k3s.tfvars` :

```hcl
vms = {
  k3s = { vm_id = 9041, host = 41, cores = 4, memory = 4096, disk = 40,
          name = "factura-k3s" }
}
```

```bash
cd ~/factura-v2/infra
tofu workspace new k3s
tofu apply -var-file=envs/k3s.tfvars
cat ../ansible/inventory/k3s.ini      # [k3s_k3s] factura-k3s ... [k3s:children]
```

`ansible/inventory/group_vars/k3s/main.yml` :

```yaml
# Nœud k3s : pas de Docker (containerd), promtail lit /var/log/pods
baseline_docker: false
promtail_scrape_docker: false
promtail_scrape_pods: true
firewall_rules_group:
  - { port: 443, src: 10.10.10.0/24, comment: "ingress TLS" }
  - { port: 80, src: 10.10.10.0/24, comment: "redirection https" }
  - { port: 6443, src: "{{ lab_admin_ip }}", comment: "kubectl" }
  - { port: 30200, src: "{{ lab_ops_ip }}", comment: "api /metrics NodePort" }
firewall_docker_rules: []
k3s_version: "v1.30.6+k3s1"
k3s_tls_san: factura-k3s.lab.local
registry_user: "{{ vault_registry_user }}"
registry_token: "{{ vault_registry_token }}"
db_password: "{{ vault_db_password }}"
redis_password: "{{ vault_redis_password }}"
```

`ansible/inventory/group_vars/k3s/vault.yml` (chiffré) : les mêmes clés
que staging, avec ses propres valeurs.

```bash
ansible-playbook -i ansible/inventory/k3s.ini ansible/playbooks/baseline.yml
```

Le rôle `common` crée `deploy` dans le groupe `docker` qui existe (créé
par `common`) même sans Docker : sans effet, sans erreur.

**2. Le rôle `k3s`**

`ansible/roles/k3s/defaults/main.yml` :

```yaml
k3s_version: "v1.30.6+k3s1"
k3s_tls_san: "{{ inventory_hostname }}.lab.local"
k3s_kubeconfig_local: "{{ lookup('env', 'HOME') }}/.kube/factura-k3s.yaml"
registry: lab-ops.lab.local:3000
registry_user: ""
registry_token: ""
```

`ansible/roles/k3s/tasks/main.yml` :

```yaml
---
- name: Registre Gitea (HTTP) pour containerd
  ansible.builtin.template:
    src: registries.yaml.j2
    dest: /etc/rancher/k3s/registries.yaml
    owner: root
    group: root
    mode: "0600"
  notify: Restart k3s
  no_log: true

- name: Script d'installation officiel (version épinglée)
  ansible.builtin.get_url:
    url: https://get.k3s.io
    dest: /usr/local/src/install-k3s.sh
    mode: "0755"

- name: Installation de k3s (serveur mono-nœud)
  ansible.builtin.command:
    cmd: /usr/local/src/install-k3s.sh
  environment:
    INSTALL_K3S_VERSION: "{{ k3s_version }}"
    INSTALL_K3S_EXEC: >-
      server --tls-san {{ k3s_tls_san }}
      --write-kubeconfig-mode 0600
      --node-name {{ inventory_hostname }}
  args:
    creates: /usr/local/bin/k3s

- name: k3s actif
  ansible.builtin.systemd:
    name: k3s
    state: started
    enabled: true

- name: Nœud Ready
  ansible.builtin.command:
    cmd: >-
      k3s kubectl get node {{ inventory_hostname }}
      -o jsonpath={.status.conditions[-1].type}
  register: node
  until: node.stdout == "Ready"
  retries: 30
  delay: 5
  changed_when: false

- name: Kubeconfig lu sur le nœud
  ansible.builtin.slurp:
    path: /etc/rancher/k3s/k3s.yaml
  register: kubeconfig

- name: Kubeconfig déposé sur lab-adm (IP du nœud, mode 0600)
  ansible.builtin.copy:
    content: >-
      {{ kubeconfig.content | b64decode
         | replace('127.0.0.1', ansible_host)
         | replace('default', 'factura-k3s') }}
    dest: "{{ k3s_kubeconfig_local }}"
    mode: "0600"
  delegate_to: localhost
  become: false
```

`ansible/roles/k3s/templates/registries.yaml.j2` :

```yaml
# {{ ansible_managed }}
mirrors:
  "{{ registry }}":
    endpoint:
      - "http://{{ registry }}"
configs:
  "{{ registry }}":
    auth:
      username: "{{ registry_user }}"
      password: "{{ registry_token }}"
```

`ansible/roles/k3s/handlers/main.yml` :

```yaml
---
- name: Restart k3s
  ansible.builtin.systemd:
    name: k3s
    state: restarted
```

`ansible/playbooks/k3s.yml` :

```yaml
---
- name: k3s mono-nœud Factura
  hosts: k3s
  become: true
  roles:
    - k3s
```

`ansible/playbooks/k8s-secret.yml` (le secret **généré** depuis le vault,
jamais versionné) :

```yaml
---
- name: Génération de k8s/secret.yaml depuis le vault
  hosts: k3s
  gather_facts: false
  connection: local
  become: false
  vars:
    out: "{{ playbook_dir }}/../../k8s/secret.yaml"
    docker_auth: >-
      {{ {'auths': {registry: {'username': registry_user,
          'password': registry_token,
          'auth': (registry_user ~ ':' ~ registry_token) | b64encode}}}
         | to_json }}
  tasks:
    - name: secret.yaml
      ansible.builtin.copy:
        dest: "{{ out }}"
        mode: "0600"
        content: |
          # GÉNÉRÉ par ansible/playbooks/k8s-secret.yml - ne pas versionner
          apiVersion: v1
          kind: Secret
          metadata: { name: factura-secrets, namespace: factura }
          type: Opaque
          stringData:
            DATABASE_URL: "postgresql://factura:{{ db_password }}@postgres:5432/factura"
            POSTGRES_PASSWORD: "{{ db_password }}"
            REDIS_URL: "redis://:{{ redis_password }}@redis:6379/0"
            REDIS_PASSWORD: "{{ redis_password }}"
          ---
          apiVersion: v1
          kind: Secret
          metadata: { name: regcred, namespace: factura }
          type: kubernetes.io/dockerconfigjson
          data:
            .dockerconfigjson: "{{ docker_auth | b64encode }}"
      no_log: true
```

```bash
cd ~/factura-v2
ansible-playbook -i ansible/inventory/k3s.ini ansible/playbooks/k3s.yml
export KUBECONFIG=~/.kube/factura-k3s.yaml
kubectl get nodes -o wide                   # factura-k3s Ready
kubectl top nodes                            # metrics-server répond
ansible-playbook -i ansible/inventory/k3s.ini ansible/playbooks/k8s-secret.yml
git check-ignore k8s/secret.yaml             # ignoré
```

**3. Les manifestes**

`k8s/namespace.yaml` :

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: factura
  labels: { app.kubernetes.io/part-of: factura }
```

`k8s/configmap.yaml` :

```yaml
apiVersion: v1
kind: ConfigMap
metadata: { name: factura-config, namespace: factura }
data:
  LOG_LEVEL: INFO
  APP_COLOR: k3s
---
apiVersion: v1
kind: ConfigMap
metadata: { name: postgres-init, namespace: factura }
data:
  10-init.sql: |
    CREATE TABLE IF NOT EXISTS factures (
      id          SERIAL PRIMARY KEY,
      client      TEXT NOT NULL,
      montant_ht  NUMERIC(12,2) NOT NULL,
      montant_ttc NUMERIC(12,2) NOT NULL,
      statut      TEXT NOT NULL DEFAULT 'nouvelle',
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS factures_statut_idx ON factures (statut);
    INSERT INTO factures (client, montant_ht, montant_ttc, statut)
    SELECT 'Client demo ' || g, 100 * g, 120 * g, 'traitee'
    FROM generate_series(1, 5) AS g
    WHERE NOT EXISTS (SELECT 1 FROM factures);
```

`k8s/postgres.yaml` :

```yaml
apiVersion: v1
kind: Service
metadata: { name: postgres, namespace: factura }
spec:
  clusterIP: None
  selector: { app: postgres }
  ports: [{ port: 5432, name: pg }]
---
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: postgres, namespace: factura }
spec:
  serviceName: postgres
  replicas: 1
  selector: { matchLabels: { app: postgres } }
  template:
    metadata: { labels: { app: postgres } }
    spec:
      securityContext: { fsGroup: 70 }
      containers:
        - name: postgres
          image: postgres:16-alpine
          ports: [{ containerPort: 5432, name: pg }]
          env:
            - { name: POSTGRES_USER, value: factura }
            - { name: POSTGRES_DB, value: factura }
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef: { name: factura-secrets, key: POSTGRES_PASSWORD }
            - { name: PGDATA, value: /var/lib/postgresql/data/pgdata }
          volumeMounts:
            - { name: data, mountPath: /var/lib/postgresql/data }
            - name: init
              mountPath: /docker-entrypoint-initdb.d
              readOnly: true
          readinessProbe:
            exec: { command: [pg_isready, -U, factura, -d, factura] }
            periodSeconds: 5
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits: { cpu: "1", memory: 512Mi }
      volumes:
        - name: init
          configMap: { name: postgres-init }
  volumeClaimTemplates:
    - metadata: { name: data }
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: local-path
        resources: { requests: { storage: 2Gi } }
```

`k8s/redis.yaml` :

```yaml
apiVersion: v1
kind: Service
metadata: { name: redis, namespace: factura }
spec:
  selector: { app: redis }
  ports: [{ port: 6379 }]
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: redis, namespace: factura }
spec:
  replicas: 1
  selector: { matchLabels: { app: redis } }
  template:
    metadata: { labels: { app: redis } }
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          args: ["redis-server", "--requirepass", "$(REDIS_PASSWORD)",
                 "--appendonly", "yes", "--maxmemory", "128mb",
                 "--maxmemory-policy", "noeviction"]
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef: { name: factura-secrets, key: REDIS_PASSWORD }
          ports: [{ containerPort: 6379 }]
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - redis-cli -a "$REDIS_PASSWORD" ping | grep -q PONG
            periodSeconds: 5
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits: { cpu: 500m, memory: 192Mi }
```

`k8s/api.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: factura
  labels: { app: api }
spec:
  replicas: 2
  selector: { matchLabels: { app: api } }
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxUnavailable: 0, maxSurge: 1 }
  template:
    metadata:
      labels: { app: api }
    spec:
      imagePullSecrets: [{ name: regcred }]
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        seccompProfile: { type: RuntimeDefault }
      terminationGracePeriodSeconds: 25
      containers:
        - name: api
          image: lab-ops.lab.local:3000/mathieu/factura-api:v2.1.0
          ports: [{ containerPort: 8000, name: http }]
          envFrom:
            - configMapRef: { name: factura-config }
            - secretRef: { name: factura-secrets }
          readinessProbe:
            httpGet: { path: /health, port: http }
            periodSeconds: 5
            failureThreshold: 3
          livenessProbe:
            httpGet: { path: /version, port: http }
            initialDelaySeconds: 10
            periodSeconds: 15
          startupProbe:
            httpGet: { path: /version, port: http }
            periodSeconds: 2
            failureThreshold: 15
          resources:
            requests: { cpu: 100m, memory: 96Mi }
            limits: { cpu: 500m, memory: 256Mi }
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: { drop: [ALL] }
          volumeMounts: [{ name: tmp, mountPath: /tmp }]
      volumes:
        - name: tmp
          emptyDir: {}
```

`k8s/worker.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: worker, namespace: factura, labels: { app: worker } }
spec:
  replicas: 1
  strategy: { type: Recreate }
  selector: { matchLabels: { app: worker } }
  template:
    metadata: { labels: { app: worker } }
    spec:
      imagePullSecrets: [{ name: regcred }]
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
      containers:
        - name: worker
          image: lab-ops.lab.local:3000/mathieu/factura-worker:v2.1.0
          ports: [{ containerPort: 9200, name: metrics }]
          envFrom:
            - configMapRef: { name: factura-config }
            - secretRef: { name: factura-secrets }
          livenessProbe:
            httpGet: { path: /, port: metrics }
            periodSeconds: 15
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits: { cpu: 300m, memory: 192Mi }
```

`k8s/service.yaml` :

```yaml
apiVersion: v1
kind: Service
metadata: { name: api, namespace: factura }
spec:
  selector: { app: api }
  ports: [{ port: 8000, targetPort: http, name: http }]
---
# /metrics pour Prometheus (lab-ops), via NodePort filtré par ufw
apiVersion: v1
kind: Service
metadata: { name: api-metrics, namespace: factura }
spec:
  type: NodePort
  selector: { app: api }
  ports: [{ port: 8000, targetPort: http, nodePort: 30200, name: http }]
```

`k8s/ingress.yaml` :

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata: { name: redirect-https, namespace: factura }
spec:
  redirectScheme: { scheme: https, permanent: true }
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-http
  namespace: factura
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
    traefik.ingress.kubernetes.io/router.middlewares: factura-redirect-https@kubernetescrd
spec:
  ingressClassName: traefik
  rules:
    - host: factura-k3s.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: api, port: { name: http } } }
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api
  namespace: factura
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
spec:
  ingressClassName: traefik
  tls:
    - hosts: [factura-k3s.lab.local]
      secretName: factura-tls
  rules:
    - host: factura-k3s.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: api, port: { name: http } } }
```

`k8s/hpa.yaml` :

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: api, namespace: factura }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: api }
  minReplicas: 2
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: { type: Utilization, averageUtilization: 60 }
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 60
```

Certificat (signé par la CA du projet A si tu l'as gardée dans
`~/P1/pki`, sinon auto-signé) et application :

```bash
cd ~/factura-v2
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -keyout k8s/factura-tls.key -out k8s/factura-tls.crt -days 365 \
  -subj '/CN=factura-k3s.lab.local' \
  -addext 'subjectAltName=DNS:factura-k3s.lab.local'
kubectl apply -f k8s/namespace.yaml
kubectl -n factura create secret tls factura-tls \
  --cert=k8s/factura-tls.crt --key=k8s/factura-tls.key
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/
kubectl -n factura rollout status deploy/api
kubectl -n factura get pods,svc,ingress,hpa
curl --cacert k8s/factura-tls.crt https://factura-k3s.lab.local/health
curl -sI http://factura-k3s.lab.local/health | head -1     # 301 -> https
curl -s --cacert k8s/factura-tls.crt -X POST -H 'Content-Type: application/json' \
  -d '{"client":"ACME","montant_ht":100}' https://factura-k3s.lab.local/api/factures
kubectl -n factura logs deploy/worker | tail -1              # facture traitée
```

**4. Rolling update et HPA**

```bash
# boucle pendant le rolling update
( n=0; e=0; end=$((SECONDS+120)); while [ $SECONDS -lt $end ]; do
    curl -sf -m 2 --cacert k8s/factura-tls.crt -o /dev/null \
      https://factura-k3s.lab.local/health || e=$((e+1)); n=$((n+1)); sleep 0.2
  done; echo "requêtes=$n erreurs=$e" ) &
kubectl -n factura set image deploy/api \
  api=lab-ops.lab.local:3000/mathieu/factura-api:sha-3f9c1e2
kubectl -n factura rollout status deploy/api
wait                                          # requêtes=571 erreurs=0
kubectl -n factura rollout undo deploy/api    # retour en une commande
```

```bash
kubectl -n factura get hpa api -w &
for i in $(seq 20); do
  ( while :; do curl -sk https://factura-k3s.lab.local/api/factures \
      >/dev/null; done ) &
done
sleep 90; kill $(jobs -p)
#  api  Deployment/api  12%/60%  2  5  2
#  api  Deployment/api  148%/60% 2  5  2      (+15 s : metrics-server)
#  api  Deployment/api  148%/60% 2  5  4      (+30 s : montée à 4)
#  api  Deployment/api  71%/60%  2  5  5      (+60 s)
#  api  Deployment/api  3%/60%   2  5  5      (charge coupée)
#  api  Deployment/api  3%/60%   2  5  2      (+5 min : stabilisation par
#                                              défaut 300 s de scaleDown)
```

Délais mesurés : montée en **≈ 30 s** après le début de la charge (délai
de collecte de metrics-server, 15 s, plus le cycle de l'HPA, 15 s) ;
descente en **≈ 5 min** (fenêtre de stabilisation par défaut ; la
`behavior.scaleDown` à 60 s réduit à ~1 min 30). Journal.

**5. Supervision de k3s**

Dans `prometheus.yml`, ajouter au job `factura-api` :

```yaml
      - targets: ["10.10.10.41:30200"]
        labels: { env: k3s, role: k3s, host: factura-k3s, color: k3s }
```

et au job `node` la cible `10.10.10.41:9100`. Le NodePort répartit sur
les réplicas : les compteurs sont **par pod**, le scrape en voit un au
hasard — suffisant pour le lab, faux en vrai (il faudrait un
`kubernetes_sd_configs` avec un ServiceAccount, comme au module 22).
Promtail sur k3s lit `/var/log/pods` (variable de PB.3) :
`{env="k3s", container="api"} | json` dans Grafana.

**6. `docs/compose-vs-k3s.md`** (extrait ; le fichier fait 80 lignes)

```markdown
# Compose ou k3s pour Factura ?

Mesures (2026-09-17, au repos, même application, même tag v2.1.0)

| Critère | Compose (factura-prod-web) | k3s (factura-k3s) |
|---|---|---|
| Mémoire utilisée (`free -m`, used) | 612 Mo (nginx, 2 API, worker, redis, exporters) | 1 480 Mo (k3s 640 Mo + Traefik, CoreDNS, metrics-server, pods) |
| Déploiement sans coupure | oui, mais écrit par nous : rôle 120 lignes + switch.sh + rescue | natif : `maxUnavailable: 0` + readinessProbe, 8 lignes |
| Rollback | `switch.sh` (5 s), à la main ou par rescue | `rollout undo` (30 s), historique conservé |
| Autoscaling | non (recréer avec plus de workers Gunicorn) | HPA : 2 → 5 pods en 30 s |
| Secrets | vault Ansible → .env 0600 | Secret k8s (base64, non chiffré au repos par défaut) généré depuis le vault |
| Stockage | volume Docker local, sauvegarde par script | PVC local-path : même chose, une abstraction en plus |
| Supervision | exporters + ports publiés + ufw | idem + NodePort ; kube-state-metrics à ajouter |
| Reconstruction | 13 min (rebuild.sh) | 17 min (baseline + k3s + apply) |
| Lignes de YAML/Jinja à maintenir | 410 (rôle + templates + playbook) | 330 (manifestes) + 95 (rôle k3s) |
| Courbe d'apprentissage | Docker + Compose : une semaine | Kubernetes : plusieurs mois pour être à l'aise en incident |
| Panne à 3 h du matin | `docker compose logs`, `switch.sh` : 5 commandes connues | `kubectl describe`, events, probes : une discipline |

## Recommandation pour Ravel & Associés
Rester sur **Compose + bleu/vert** pour Factura. Une application, deux
VM, un admin : tout ce que k3s apporte réellement ici (rolling update
natif, HPA) existe déjà sous une forme suffisante (bleu/vert prouvé sans
erreur, charge de 40 utilisateurs qui ne sature jamais deux workers
Gunicorn). Le prix de k3s est réel : 900 Mo de RAM de plus, un composant
de plus à mettre à jour (k3s tous les mois), et surtout une compétence
que personne d'autre n'a dans l'entreprise — le jour où l'admin est
absent, `docker compose ps` est lisible par un développeur,
`kubectl get events -A` beaucoup moins.

## Ce qui ferait changer d'avis
* une deuxième application, ou une troisième : la mutualisation
  (Ingress, secrets, supervision, rolling update) commence à payer ;
* un besoin de montée en charge imprévisible (l'HPA, mesuré à 30 s) ;
* un second admin formé, ou un prestataire Kubernetes sous contrat ;
* l'obligation d'un standard (audit, hébergeur) qui impose des
  manifestes plutôt que des rôles.
Dans ce cas, le chemin est prêt : k8s/ fonctionne, le pipeline
construit déjà les images, et la migration se fait un environnement à
la fois.
```

::: pourquoi
**Readiness sur `/health`, liveness sur `/version`** : la readiness
retire le pod du Service quand la base est injoignable — plus aucun
trafic ne lui arrive, mais on ne le redémarre pas (redémarrer n'a jamais
réparé une base). La liveness sur `/version` (qui ne dépend que du
processus) redémarre le conteneur si Gunicorn est bloqué. Inverser les
deux (liveness sur `/health`) donne des redémarrages en boucle pendant
une panne de base : le pire des cas. La `startupProbe` laisse 30 s au
démarrage sans que la liveness intervienne.

**`maxUnavailable: 0, maxSurge: 1`** : un pod de plus est créé, attend
d'être Ready (readiness), puis un ancien est arrêté (`SIGTERM`, 25 s de
grâce, Gunicorn finit ses requêtes). Zéro requête perdue, sans rien
écrire : c'est exactement ce que le rôle de PB.7 fait en 120 lignes. La
comparaison est le cœur de PB.10.

**`runAsUser: 10001` + `readOnlyRootFilesystem`** : le uid choisi en
PB.4 rend `runAsNonRoot` vérifiable ; le système de fichiers en lecture
seule avec un `emptyDir` sur `/tmp` interdit à une faille dans l'API
d'écrire ailleurs. `capabilities: drop: [ALL]` : Gunicorn sur 8000 (port
> 1024) n'en a besoin d'aucune.

**Deux Ingress plutôt qu'un** : Traefik écoute sur `web` (80) et
`websecure` (443) ; un Ingress par point d'entrée, celui de 80 portant le
Middleware de redirection, reste lisible et évite l'annotation qui mélange
les deux. Le certificat est un Secret `kubernetes.io/tls` créé par
`kubectl`, jamais versionné (comme `secret.yaml`).

**Le secret généré par un play, pas par `kubectl create secret` à la
main** : la source de vérité reste le vault ; le fichier généré est
reproductible, ignoré par Git, et la rotation d'un mot de passe suit le
même chemin qu'en Compose (INC-B3).

**Empreinte mémoire mesurée** : 900 Mo de plus pour k3s au repos, c'est
la moitié de la RAM d'une VM du lab. Sur un hébergeur à 4 Go, c'est le
prix d'une VM de plus par an. La recommandation s'appuie sur ce chiffre
et sur les lignes de YAML comptées (`wc -l`), pas sur une préférence.
:::

::: piege
* `ImagePullBackOff` avec `401` : `regcred` absent du namespace ou
  `registries.yaml` non pris en compte (k3s doit être **redémarré**
  après sa modification, d'où le handler). `x509`/`http: server gave
  HTTP response` : le `mirrors.endpoint` en `http://` manque.
* `kubectl top pods` vide pendant la première minute : metrics-server
  n'a pas encore de données ; l'HPA affiche `<unknown>/60%`. Attendre,
  ne pas « réparer ».
* Sans `resources.requests.cpu`, l'HPA ne calcule rien (`unknown`) :
  l'utilisation est **relative aux requests**, pas à la machine.
* Le `readOnlyRootFilesystem` casse Gunicorn si `--worker-tmp-dir`
  pointe sur `/tmp` non monté : d'où le `emptyDir`. Symptôme :
  `CrashLoopBackOff`, `logs --previous` dit `Read-only file system`.
* Le port 6443 est ouvert à `lab-adm` seulement ; le kubeconfig
  rapatrié contient l'IP `10.10.10.41`. Depuis `lab-ops`, `kubectl`
  échoue : c'est voulu (le runner n'a pas à administrer k3s).
* `/etc/hosts` de `lab-adm` résout `factura-k3s.lab.local` (setup_P2) ;
  les autres postes du réseau n'ont pas cette entrée. Pour un test
  depuis `lab-rhel`, `curl --resolve factura-k3s.lab.local:443:10.10.10.41`.
* Le StatefulSet avec `local-path` : les données sont sur le disque de
  `factura-k3s`, dans `/var/lib/rancher/k3s/storage/`. Un `tofu destroy`
  du workspace `k3s` les perd. Ce n'est pas différent de Compose — mais
  l'abstraction PVC fait croire le contraire.
:::

---

## B.3 Incidents — diagnostic pas à pas

Les scripts `break_PB_0N.sh` tournent sur `lab-adm` avec `sudo` ; ils
sauvegardent ce qu'ils touchent dans `/root/.breakfix-backup/INC-BN/`.
Le post-mortem attendu est dans `docs/incidents/INC-BN-<slug>.md`.

### **INC-B1** — « Le pipeline est vert, mais la prod calcule mal la TVA »

*La prod répond le bon tag sur `/version`, `git log` n'a rien de neuf, le
dernier `cd-prod` est vert, et pourtant `montant_ttc` vaut 119,6 pour
100 HT. Le staging donne 120.*

**Diagnostic**

1. Constater, et mesurer l'ampleur :

   ```bash
   for h in 10.10.10.31 10.10.10.21; do
     curl -s -X POST -H 'Content-Type: application/json' \
       -d '{"client":"test","montant_ht":100}' http://$h/api/factures; echo
   done
   #  {"id":..,"montant_ttc":119.6,...}   prod
   #  {"id":..,"montant_ttc":120.0,...}   staging
   curl -s http://10.10.10.31/version    # {"version":"v2.1.0","color":"green"}
   curl -s http://10.10.10.21/version    # {"version":"v2.1.0","color":"blue"}
   ```

   Même tag, comportement différent : **le tag ne dit pas ce qui tourne**.

2. L'identité réelle : le digest.

   ```bash
   ssh deploy@10.10.10.31 'docker inspect --format \
     "{{.Name}} {{.Config.Image}} {{index .Image}} {{index .RepoDigests 0}}" \
     $(docker ps -q --filter name=api)' 2>/dev/null
   # ou, plus sûr :
   ssh deploy@10.10.10.31 'docker image inspect --format \
     "{{index .RepoDigests 0}}" lab-ops.lab.local:3000/mathieu/factura-api:v2.1.0'
   #  ...factura-api@sha256:9c4e...   (prod)
   ssh deploy@10.10.10.21 'docker image inspect --format \
     "{{index .RepoDigests 0}}" lab-ops.lab.local:3000/mathieu/factura-api:v2.1.0'
   #  ...factura-api@sha256:3f7a...   (staging) : DIFFÉRENT
   ```

3. Ce que la CI a construit : le run de `ci` sur le tag `v2.1.0` (Actions →
   run → job `build` → step « Digests ») affiche `factura-api:sha-xxxxxxx
   -> sha256:3f7a...`. La release Gitea créée par `cd-prod` (PB.7) porte le
   même digest. Le staging tourne l'image de la CI ; **la prod tourne autre
   chose sous le même tag**.

4. Quand le tag a bougé : le registre Gitea (*Packages → factura-api →
   v2.1.0*) montre la date de publication de la version, postérieure au run
   CI. Et sur la VM de prod :

   ```bash
   ssh deploy@10.10.10.31 'tail -n 3 /srv/factura/switch.log'
   #  ... switch -> blue (deploy-v2.1.0)                     vendredi 16:40
   #  ... switch -> green (redeploiement v2.1.0 (rafraichissement))  09:52
   ssh deploy@10.10.10.31 'docker image ls --digests | grep factura-api'
   ssh mathieu@10.10.10.31 'sudo journalctl _UID=1500 --since 09:30 | grep -E \
     "docker compose|switch"'      # ou : last, .bash_history de deploy
   ```

   Le « redéploiement pour rafraîchir » n'est pas passé par `cd-prod` (le
   rôle refuse de redéployer un tag déjà actif, `meta: end_host`) : la
   raison dans `switch.log` n'est pas `deploy-…`, et le journal montre un
   `docker compose pull` + `up -d` + `switch.sh` faits **à la main** en
   `deploy` sur la VM. Le `pull` a tiré l'image mutée sous le tag,
   `/version` disait `v2.1.0` (l'`ENV` est resté), la bascule a eu lieu.

5. Qui a poussé ? Le journal de Gitea (`docker logs gitea | grep
   'v2/mathieu/factura-api/manifests/v2.1.0' | grep PUT`) donne l'heure et
   l'IP source (`10.10.10.10`, pas le runner `10.10.10.14`) : un push depuis
   un poste avec le token `write:package`.

**Cause racine** : un tag d'image est un pointeur **mutable**. Une image
construite hors pipeline (avec un `montant_ttc` à 19,6 %) a été poussée
sous le tag `v2.1.0`, écrasant celle de la CI. Le rôle de déploiement
déploie par tag et fait un `pull` : il a tiré, validé (`/version` ne
vérifie que la variable d'environnement) et basculé une image que le
pipeline n'avait jamais vue. Le pipeline est vert parce qu'il n'a pas
tourné : rien n'a changé dans Git.

**Correctif** (sans rebuild sur le poste, sans toucher `app.py`) :

```bash
# 1. l'ancienne couleur (blue) tourne encore avec la bonne image ? vérifier :
ssh deploy@10.10.10.31 'curl -s localhost:8081/version; docker inspect \
  --format "{{index .RepoDigests 0}}" factura-api-blue-1'
#  si le digest est 3f7a... : retour arrière immédiat (< 1 min)
ssh deploy@10.10.10.31 '/srv/factura/bin/switch.sh blue "INC-B1: v2.1.0 mutée"'
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"client":"test","montant_ht":100}' http://10.10.10.31/api/factures
#  120.0
# 2. remettre la bonne image sous le tag, depuis le staging (image de la CI)
IMG=lab-ops.lab.local:3000/mathieu/factura-api:v2.1.0
ssh deploy@10.10.10.21 "docker save $IMG" | docker load
docker image inspect --format '{{index .RepoDigests 0}}' \
  lab-ops.lab.local:3000/mathieu/factura-api:v2.1.0      # 3f7a... : la bonne
docker push lab-ops.lab.local:3000/mathieu/factura-api:v2.1.0
# 3. redéployer proprement par le pipeline (make promote TAG=v2.1.0) : la
#    couleur inactive (green) reçoit l'image de la CI, bascule, smoke.
# 4. les factures créées entre 10:00 et la correction : requête SQL
ssh mathieu@10.10.10.32 'docker exec factura-postgres-1 psql -U factura -d factura \
  -Atc "SELECT id, montant_ht, montant_ttc FROM factures WHERE \
        created_at > now() - interval '"'"'3 hours'"'"' \
        AND round(montant_ht*1.2,2) <> montant_ttc"'
#  -> liste à corriger (UPDATE ... SET montant_ttc = round(montant_ht*1.2,2))
#     après validation par la comptabilité, dans un ticket.
```

Le token `write:package` utilisé pour le push hors pipeline est
**révoqué** et recréé (Gitea → Applications), le secret `REGISTRY_TOKEN`
et `vault_registry_token` (staging, prod, k3s) mis à jour.

**Prévention** :

1. **Déployer par digest.** Le job `build` publie déjà `api_digest` ; le
   rôle accepte `factura_image_tag=v2.1.0@sha256:3f7a...` (le template
   Compose produit `factura-api:v2.1.0@sha256:...`, Docker vérifie le
   digest au pull, `factura_expected_version` retire le `@...` pour le
   smoke). `cd-prod.yaml` passe `"$TAG@$DIGEST"` avec le digest lu dans le
   registre **et** comparé à celui de la release CI : s'ils diffèrent, le
   garde-fou échoue avec « le tag a bougé depuis sa construction ».
2. **Un token de registre en lecture seule sur les VM** (`read:package`),
   et le token d'écriture uniquement dans le secret CI. Personne d'autre
   que le runner ne peut écrire dans le registre.
3. **Le smoke compare le digest**, pas seulement `/version` : `tools/
   smoke.sh` reçoit le digest attendu et interroge `docker inspect` par
   SSH (ou l'API expose le digest via une variable injectée au build).
4. **Plus d'action manuelle en `deploy` sur la prod** : la clé de
   `mathieu@lab-adm` sort de `deploy_authorized_keys` en prod (seul le
   runner déploie) ; le diagnostic se fait en `mathieu`, qui est dans
   `docker` mais n'a pas `/srv/factura` en écriture.
5. Bonus : signature des images (`cosign sign` dans `build`, `cosign
   verify` dans le rôle avant le `up`).

---

### **INC-B2** — « `tofu plan` veut recréer la base de prod »

*`make infra-plan ENV=staging` propose une modification de
`factura-staging-db` ; `ENV=prod` propose de **créer** `factura-prod-db`,
qui tourne.*

**Diagnostic**

1. Lire les plans, ligne à ligne, sans appliquer :

   ```bash
   cd ~/factura-v2 && source ~/.config/factura/pve.env
   make infra-plan ENV=staging
   #  ~ resource "proxmox_virtual_environment_vm" "vm" ("db") {
   #      ~ memory { ~ dedicated = 1536 -> 2048 }
   #  Plan: 0 to add, 1 to change, 0 to destroy.
   make infra-plan ENV=prod
   #  + resource "proxmox_virtual_environment_vm" "vm" ("db") {
   #      + vm_id = 9032 ...
   #  Plan: 1 to add, 0 to change, 0 to destroy.
   ```

   Deux symptômes différents : un `~` (l'état connaît la VM, la réalité a
   changé) et un `+` (l'état **ne connaît plus** la VM).

2. Le staging : la réalité.

   ```bash
   ssh root@10.10.10.1 'qm config 9022 | grep -E "^(memory|balloon)"'
   #  memory: 1536
   ssh root@10.10.10.1 'grep 9022 /var/log/pve/tasks/index | tail -3'
   #  ... qmconfig ... root@pam ... hier 21:14
   ```

   Quelqu'un a fait `qm set 9022 --memory 1536` (« libérer de la RAM à
   chaud »). OpenTofu ne l'a pas vu venir : c'est un **drift**.

3. La prod : l'état.

   ```bash
   cd infra && tofu workspace select prod
   tofu state list
   #  local_file.inventory
   #  proxmox_virtual_environment_file.user_data["db"]
   #  proxmox_virtual_environment_file.user_data["web"]
   #  proxmox_virtual_environment_vm.vm["web"]        <- plus de ["db"]
   ls -la terraform.tfstate.d/prod/
   #  terraform.tfstate   terraform.tfstate.backup    (hier 21:20)
   diff <(jq '.resources[].instances[].attributes.vm_id' \
            terraform.tfstate.d/prod/terraform.tfstate.backup) \
        <(jq '.resources[].instances[].attributes.vm_id' \
            terraform.tfstate.d/prod/terraform.tfstate)
   #  < 9032
   ```

   Le `.backup` contient encore `9032` : un `tofu state rm
   'proxmox_virtual_environment_vm.vm["db"]'` a été exécuté (« nettoyé un
   truc qui traînait »). La VM existe, l'état l'a oubliée : au prochain
   `apply`, OpenTofu la **créerait** — et Proxmox refuserait (VMID 9032
   déjà pris), ou pire, avec un autre VMID, créerait une deuxième base
   de prod vide et écrirait `factura-prod-db` en double dans l'inventaire.

**Cause racine** : deux drifts d'origine humaine. (1) Une modification
hors code sur Proxmox (mémoire de 9022) : la réalité ne correspond plus
au code. (2) Une suppression dans l'état OpenTofu (`state rm`) : l'état ne
correspond plus à la réalité. Le code, lui, est correct.

**Correctif**

```bash
# Prod : ré-adopter la VM existante dans l'état (aucune action sur Proxmox)
cd ~/factura-v2/infra && tofu workspace select prod
tofu import -var-file=envs/prod.tfvars \
  'proxmox_virtual_environment_vm.vm["db"]' pve/9032
tofu plan -detailed-exitcode -var-file=envs/prod.tfvars; echo rc=$?
#  rc=0 : plan vide, la VM n'a jamais redémarré
# Staging : le code a raison (2048), on applique après avoir lu le plan
tofu workspace select staging
tofu apply -var-file=envs/staging.tfvars      # ~ memory 1536 -> 2048
#  bpg met à jour la mémoire à chaud (ballooning) : pas de reboot ;
#  si le provider annonce "reboot required", le staging peut redémarrer.
tofu plan -detailed-exitcode -var-file=envs/staging.tfvars; echo rc=$?
```

Si l'`import` échoue sur un attribut non importable (`clone`, `disk`
normalisé), le plan après import montre un `-/+` : **ne pas appliquer**.
Ajouter l'attribut à `ignore_changes` ou aligner le code sur la réalité
(`tofu show` de la ressource importée), jusqu'au plan vide.

**Prévention** :

1. **Règle d'équipe écrite dans le README** : personne ne touche à une VM
   `factura-*` depuis Proxmox ni à l'état sans un ticket ; `tofu state
   rm|mv` seulement en binôme, avec un `cp` de l'état avant.
2. **Un plan quotidien** : un job `restore-test`-like (`schedule`) qui
   lance `tofu plan -detailed-exitcode` sur les trois workspaces et écrit
   une métrique `factura_tofu_drift{env}` dans le textfile de `lab-ops`
   → alerte `TofuDrift`. Cela demande l'état et le token sur `lab-ops` :
   c'est l'argument pour le **backend distant** (MinIO sur `lab-ops`,
   bonus) avec verrou, qui rend aussi l'état visible et sauvegardé.
3. `prevent_destroy = true` sur les VM `db` (dans `lifecycle`) : un plan
   qui voudrait détruire une base échoue avant d'exister. À poser via une
   variable (`protect_db = true` en prod) car `rebuild.sh` a besoin de
   détruire.
4. Le « RAM à chaud » qui a déclenché tout ça : la vraie réponse était
   `tofu apply` avec `memory = 1536` dans `staging.tfvars` — le code
   aurait suivi, l'historique Git aussi.

---

### **INC-B3** — « Le déploiement de prod échoue : vault illisible »

*Après un commit « chore(vault): rotation », `ansible-vault view
group_vars/prod/vault.yml` échoue, `cd-prod` est rouge à l'étape Ansible,
le staging se déploie normalement. Un correctif doit partir avant 18 h.*

**Diagnostic**

1. Le symptôme exact :

   ```bash
   cd ~/factura-v2
   ansible-vault view ansible/inventory/group_vars/prod/vault.yml
   #  ERROR! Decryption failed (no vault secrets were found that could decrypt)
   ansible-vault view ansible/inventory/group_vars/staging/vault.yml | head -1
   #  vault_db_password: ...          (le .vault-pass est bon)
   ```

   Le mot de passe du coffre marche pour le staging, pas pour la prod : le
   fichier prod a été **rechiffré avec un autre mot de passe**, pas
   corrompu (un fichier corrompu donne « Vault format unhexlify error »).

2. Qui, quand, quoi :

   ```bash
   git log --oneline -3 -- ansible/inventory/group_vars/prod/vault.yml
   #  a1b2c3d chore(vault): rotation
   #  9f8e7d6 feat(deploy): vault prod
   git show a1b2c3d --stat
   git show 9f8e7d6:ansible/inventory/group_vars/prod/vault.yml > /tmp/v.yml
   ansible-vault view /tmp/v.yml | head -1
   #  vault_db_password: Prd-Db-2026        (l'ancienne version se lit)
   ```

   L'historique Git contient la version précédente, chiffrée avec le
   `.vault-pass` que tout le monde a.

3. Ce que la prod utilise réellement :

   ```bash
   ssh deploy@10.10.10.31 'grep ^DB_PASSWORD= /srv/factura/.env'
   #  DB_PASSWORD=Prd-Db-2026
   ssh mathieu@10.10.10.32 'docker exec factura-postgres-1 psql -U factura \
     -d factura -Atc "select 1"'                     # 1 : socket, sans mdp
   ssh mathieu@10.10.10.32 "PGPASSWORD=Prd-Db-2026 psql -h 10.10.10.32 \
     -U factura -d factura -Atc 'select 1'"          # 1 : le mdp est valide
   ```

   La prod tourne avec l'ancien mot de passe ; la « rotation » n'a pas
   touché PostgreSQL (le déploiement a échoué avant). Le collègue a fait
   `ansible-vault rekey` (ou `encrypt` avec un nouveau fichier de mot de
   passe), changé la valeur dedans, commité, et gardé le nouveau mot de
   passe du coffre... sur son poste, en congé.

**Cause racine** : rotation faite en dehors de toute procédure : (1) le
mot de passe **du coffre** a été changé pour un seul fichier, sans
partager le nouveau (le `.vault-pass` et le secret CI `VAULT_PASS` sont
restés les anciens) ; (2) la valeur du secret a été changée dans le coffre
sans que la base soit modifiée, donc même déchiffré, ce vault aurait
déployé un `.env` faux et cassé la prod au premier redémarrage de l'API.

**Correctif** (avant 18 h : rendre la promotion possible, sans changer les
secrets)

```bash
cd ~/factura-v2
cp ansible/inventory/group_vars/prod/vault.yml /tmp/vault-prod-inconnu.yml
git checkout 9f8e7d6 -- ansible/inventory/group_vars/prod/vault.yml
ansible-vault view ansible/inventory/group_vars/prod/vault.yml   # lisible
# vérifier que ce coffre = ce que la prod utilise
diff <(ansible-vault view ansible/inventory/group_vars/prod/vault.yml \
       | awk -F'"' '/vault_db_password/{print $2}') \
     <(ssh deploy@10.10.10.31 'grep ^DB_PASSWORD= /srv/factura/.env' | cut -d= -f2) \
  && echo "vault == prod"
git commit -m "fix(vault): restaure le coffre prod lisible (INC-B3)"
git push
ansible-playbook -i ansible/inventory/prod.ini ansible/playbooks/deploy.yml \
  --check -e ansible_user=deploy       # changed=0 : le .env ne bougerait pas
make promote TAG=v2.1.1                # le correctif part
```

Le fichier `/tmp/vault-prod-inconnu.yml` est gardé jusqu'au retour du
collègue (il contient peut-être un mot de passe qu'il a aussi mis
ailleurs), puis détruit.

**Prévention** — la procédure de rotation, dans `docs/runbook-deploy.md` :

```markdown
## Rotation d'un secret (ex. mot de passe PostgreSQL de prod)
1. Jamais `ansible-vault rekey` : le mot de passe du coffre est unique
   (.vault-pass) et partagé (secret CI VAULT_PASS). Le changer est une
   opération à part, sur TOUS les vault.yml, avec mise à jour du secret CI.
2. `ansible-vault edit group_vars/prod/vault.yml` : nouvelle valeur.
   Vérifier immédiatement : `ansible-vault view ... | grep db_password`.
3. Changer le secret côté service AVANT de déployer :
   docker exec factura-postgres-1 psql -U factura -c \
     "ALTER ROLE factura PASSWORD 'nouveau'"
   (l'API en cours garde ses connexions ouvertes ; les nouvelles
   connexions utilisent le nouveau mot de passe : fenêtre de quelques
   secondes où /health peut passer degraded, acceptable en heures creuses).
4. Déployer dans la foulée (`deploy.yml` sans tag : réécrit .env,
   recrée les conteneurs dont l'env a changé).
5. Commit `chore(vault): rotation db prod` et PR relue par un second
   admin : la PR doit montrer un diff sur vault.yml ET la mention de
   l'ALTER ROLE dans la description.
```

Et deux garde-fous techniques : un hook pre-commit `local` qui fait
`ansible-vault view` sur chaque `vault.yml` modifié (échoue si le
`.vault-pass` du poste ne le déchiffre pas — la « rotation » n'aurait
jamais été commitée) ; et dans le job `lint` de la CI, la même
vérification avec `VAULT_PASS` (un coffre illisible par la CI casse le
pipeline **avant** la prod, pas pendant).

---

### **INC-B4** — « Le staging est tombé à midi, personne n'a été prévenu »

*`curl http://10.10.10.21/health` échoue, `FacturaApiDown{env="staging"}`
est `firing` depuis des heures sur Prometheus, Alertmanager est `up`, et
`alerts.log` n'a rien reçu d'autre que `Watchdog`.*

**Diagnostic**

1. Séparer les deux problèmes : le staging **et** l'absence d'alerte.

   ```bash
   curl -m 3 http://10.10.10.21/health          # connection refused / 502
   ssh deploy@10.10.10.21 'cd /srv/factura && docker compose ps -a'
   #  factura-api-blue-1   exited (0)   ... 12:02
   #  factura-api-green-1  exited (0)
   ssh deploy@10.10.10.21 'docker inspect --format "{{.State.ExitCode}} \
     {{.State.FinishedAt}}" factura-api-blue-1'   # 0 : arrêt demandé, pas crash
   ssh mathieu@10.10.10.21 'sudo journalctl -u docker --since 11:55 --until 12:10 \
     | grep -i stop'
   ```

   Exit 0 à 12:02 : quelqu'un a fait `docker compose stop`. Ce n'est pas
   un crash, la remise en service est un `start`. Mais d'abord la chaîne
   d'alerte, sinon on ne verra pas non plus la prochaine fois.

2. La chaîne : Prometheus → Alertmanager → sink.

   ```bash
   curl -s 'http://lab-ops:9090/api/v1/alerts' | jq '.data.alerts[]
     | select(.labels.alertname=="FacturaApiDown") | {state, activeAt}'
   #  { "state": "firing", "activeAt": "…T10:03:12Z" }
   curl -s http://lab-ops:9093/api/v2/alerts | jq '.[]
     | {alertname: .labels.alertname, env: .labels.env,
        state: .status.state, silencedBy: .status.silencedBy}'
   #  { "alertname": "FacturaApiDown", "env": "staging",
   #    "state": "suppressed", "silencedBy": ["7c1d…"] }
   ```

   Alertmanager **a** l'alerte, mais en `suppressed` : elle est sous un
   silence (ce serait `inhibitedBy` pour une inhibition).

3. Le silence :

   ```bash
   curl -s http://lab-ops:9093/api/v2/silences | jq '.[]
     | select(.status.state=="active")
     | {id, createdBy, comment, startsAt, endsAt, matchers}'
   #  { "createdBy": "mathieu", "comment": "maintenance réseau",
   #    "startsAt": "hier 22:00", "endsAt": "dans 6 jours",
   #    "matchers": [{"name":"env","value":"staging","isRegex":false}] }
   ```

   Un silence sur `env="staging"`, sans `alertname`, posé pour la
   maintenance réseau d'hier soir, avec une durée d'une semaine « pour être
   tranquille ». Toute alerte du staging est muette depuis 22 h hier.
   `Watchdog` n'a pas de label `env` : il passait — et donnait
   l'illusion que tout marchait.

**Cause racine** : un silence Alertmanager trop large (`env=staging` sans
`alertname`) et trop long (7 jours pour une maintenance d'une heure),
jamais expiré. Le staging a été arrêté à midi (un dev « pour libérer de la
RAM », `switch.log` et `docker events` le disent) : l'alerte a été
évaluée, envoyée à Alertmanager, et supprimée par le silence.

**Correctif**

```bash
# 1. expirer le silence
curl -s -X DELETE http://lab-ops:9093/api/v2/silence/7c1d…-…   # ou amtool
# amtool --alertmanager.url=http://lab-ops:9093 silence expire 7c1d…
# 2. la notification part au prochain cycle (group_wait) : vérifier
ssh mathieu@lab-ops 'tail -n 2 /opt/factura-monitoring/data/alerts.log'
#  … firing FacturaApiDown env=staging severity=critical …
# 3. remettre le staging
ssh deploy@10.10.10.21 'cd /srv/factura && docker compose --profile blue \
  --profile green start api-blue api-green'
curl -s http://10.10.10.21/health
#  … resolved FacturaApiDown …  dans alerts.log quelques minutes après
```

**Prévention** :

1. **Alerte sur les silences** : `AlertmanagerSilenceTooLong`
   (`alertmanager_silences{state="active"} > 0` pendant 12 h) est ajoutée
   à `rules/alerts.yml` (déjà dans le corrigé de PB.8) ; elle n'a pas de
   label `env`, donc aucun silence par env ne peut la taire. Un panneau
   Grafana « silences actifs » (`alertmanager_silences{state="active"}`) sur
   le dashboard Factura.
2. **Règle de silence** : toujours `alertname=...` **et** `env=...`, durée
   ≤ 4 h, commentaire avec le ticket. `amtool silence add
   alertname=InstanceDown env=staging --duration=2h --comment="MAINT-42"`
   dans le runbook ; jamais depuis l'interface sans commentaire.
3. **Watchdog par environnement** : `vector(1)` avec `labels: {env:
   staging}` et `{env: prod}` (deux règles) : un silence sur `env=staging`
   fait alors **disparaître** le Watchdog staging d'`alerts.log`, ce qui se
   voit. Et une alerte « dead man's switch » : `absent(ALERTS{alertname=
   "Watchdog", env="staging"})`... ne marche pas depuis le même Prometheus
   ; la vraie version est un timer sur `lab-adm` qui vérifie que
   `alerts.log` a reçu un Watchdog de chaque env dans la dernière heure.
4. Le staging arrêté « pour libérer de la RAM » : la bonne réponse est
   `tofu destroy` du workspace staging (l'énoncé le suggère) — une VM
   absente ne génère pas d'alerte fantôme si on retire aussi ses cibles
   (ou si on accepte `InstanceDown` sur le staging détruit : mieux, une
   variable Ansible `monitoring_envs` qui régénère `prometheus.yml`).

---

## B.6 Du manuel à l'automatisé — corrigé

| À la main dans le projet A | Automatisé par… | Ce que ça change |
|---|---|---|
| `qm create`, ISO, IP, clé SSH (PA.1, 2 h par VM) | `tofu apply` : `for_each`, snippets cloud-init (PB.2) | 4 min, identique à chaque fois, diff de 2 lignes entre staging et prod |
| `/etc/hosts`, `useradd -r`, arborescence (PA.1) | rôle `common` (PB.3) | rejouable, `changed=0`, un `deploy` sans sudo pour la CI |
| `sshd_config.d/`, `sshd -t`, restart (PA.9) | rôle `ssh_hardening`, `validate:` (PB.3) | impossible de couper SSH avec une faute de frappe |
| `ufw allow` un par un (PA.2, PA.9) | rôle `firewall`, listes par groupe, `DOCKER-USER` (PB.3) | les ports Docker sont vraiment filtrés ; la liste est revue en PR |
| chrony, unattended-upgrades, node_exporter (PA.8, PA.9) | rôles dédiés (PB.3) | posés sur une VM neuve en 3 min |
| venv, `pip`, unité systemd durcie (PA.3, PA.4) | `Dockerfile` multi-stage, `USER app`, healthcheck (PB.4) | une image de 170 Mo, scannée, identique du poste à la prod |
| `/etc/factura/*.env` 0640, `SECRETS.md` (PA.3) | `ansible-vault`, indirection, `.env` 0600 par template (PB.5) | secrets chiffrés dans Git, différents par env, rotation documentée |
| `scp` + `systemctl restart`, 5 min de coupure | rôle `factura_compose`, bleu/vert, `switch.sh`, `rescue` (PB.5, PB.7) | 0 erreur sur 1 148 requêtes, rollback automatique tracé |
| `pytest` sur le poste du dev | job `test`, image construite une fois, `sha-<7>` (PB.6) | « ça marche chez moi » n'existe plus ; PR non fusionnable si rouge |
| `openssl` + `pa5-cert.sh` (PA.5) | Secret TLS + Ingress Traefik (PB.10) | le certificat est un objet, renouvelable sans toucher nginx |
| rsyslog TCP 10514, `/var/log/remote/` (PA.6) | promtail → Loki, LogQL par `env`/`container` (PB.3, PB.8) | `| json | level="ERROR"` en une requête, corrélé aux métriques |
| `factura-healthcheck.timer`, `.prom`, webhook (PA.8) | Prometheus, blackbox, règles SLI, Alertmanager (PB.8) | on alerte sur le budget d'erreur ; Watchdog prouve la chaîne |
| `factura-backup.timer`, rsync, `restore.md` (PA.7) | rôle `pg_backup`, `restore.yml`, job CI hebdo (PB.9) | la restauration est testée chaque lundi, sans humain |
| Runbook « deux jours pour tout refaire » (PA.10) | `tools/rebuild.sh` (PB.9) | 13 min 24 s, mesurés, avec les données |
| Un service, `Restart=on-failure` (PA.3) | Deployment, probes, HPA, rolling update (PB.10) | ce que Kubernetes donne gratuitement — et ce qu'il coûte |
