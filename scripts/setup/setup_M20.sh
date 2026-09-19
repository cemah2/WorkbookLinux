#!/usr/bin/env bash
# setup_M20.sh — prépare ~/lab20 pour le module 20 (IaC : OpenTofu,
# cloud-init, Proxmox). À lancer SANS sudo, en tant que mathieu, sur lab-adm.
# Idempotent : ne réécrit jamais un fichier de travail déjà présent
# (main.tf, .env, user-data enrichis...) ; les gabarits fournis portent le
# suffixe .example ou sont posés uniquement s'ils manquent.
set -euo pipefail

[ "$(id -u)" -ne 0 ] || { echo "à lancer SANS sudo (en tant que mathieu)" >&2; exit 1; }

BASE="$HOME/lab20"
PVE_IP=10.10.10.1
OPS_IP=10.10.10.14

echo "== Préparation du module 20 dans $BASE =="

install -d "$BASE" "$BASE/cloud-init" "$BASE/proxmox" "$BASE/bin" \
  "$BASE/e02" "$BASE/e04/templates" "$BASE/e06" "$BASE/e13" \
  "$BASE/01-premier" "$BASE/02-lab2" "$BASE/03-remote" \
  "$BASE/04-modules/templates" "$BASE/04-modules/tests" \
  "$BASE/modules/vm-ubuntu/templates" "$BASE/ansible" "$BASE/rapports"

# Pose un fichier seulement s'il est absent (ne touche pas au travail fait).
poser() {   # poser <chemin>  (contenu sur stdin)
  if [ -e "$1" ]; then cat >/dev/null; return 0; fi
  cat > "$1"
}

# ---------------------------------------------------------------------
# 1. Identifiants et hygiène git
# ---------------------------------------------------------------------
cat > "$BASE/.env.example" <<EOF
# Copie en .env (chmod 600) et remplis. Charge avec :
#   set -a; . ~/lab20/.env; set +a
# --- Proxmox (provider bpg/proxmox lit ces deux variables) ---
PROXMOX_VE_ENDPOINT=https://$PVE_IP:8006/
PROXMOX_VE_API_TOKEN=terraform@pve!tofu=00000000-0000-0000-0000-000000000000
PROXMOX_VE_INSECURE=true
# nom du nœud tel que « hostname » le donne sur le nœud
PVE_NODE=pve
# --- Backend S3 (MinIO sur lab-ops, L20.3) ---
AWS_ACCESS_KEY_ID=tofu
AWS_SECRET_ACCESS_KEY=change-moi
EOF

poser "$BASE/.gitignore" <<'EOF'
# secrets et état : jamais dans git
.env
*.tfstate
*.tfstate.*
*.tfvars
!*.tfvars.example
.terraform/
plan.bin
plan.txt
backup-*.json
crash.log
# fichiers générés
ansible/inventory.ini
hosts.lab2
EOF

# ---------------------------------------------------------------------
# 2. cloud-init : exemples de user-data
# ---------------------------------------------------------------------
KEY=""
for f in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
  [ -r "$f" ] && { KEY=$(head -n1 "$f"); break; }
done
[ -n "$KEY" ] || KEY="ssh-ed25519 AAAA... remplace-par-ta-cle mathieu@lab-adm"

cat > "$BASE/cloud-init/minimal.yaml" <<EOF
#cloud-config
# user-data minimal : identité + accès. Valider avec
#   cloud-init schema --config-file minimal.yaml
hostname: ci-minimal
fqdn: ci-minimal.lab.local
manage_etc_hosts: true
users:
  - name: mathieu
    groups: [sudo]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: true
    ssh_authorized_keys:
      - $KEY
package_update: true
packages: [qemu-guest-agent]
runcmd:
  - systemctl enable --now qemu-guest-agent
EOF

cat > "$BASE/cloud-init/vendor-agent.yaml" <<'EOF'
#cloud-config
# vendor-data : FUSIONNÉ avec le user-data (contrairement à --cicustom user=
# qui remplace). Utile pour garantir l'agent sans toucher au user-data.
#   qm set <vmid> --cicustom vendor=local:snippets/vendor-agent.yaml
package_update: true
packages: [qemu-guest-agent]
runcmd:
  - systemctl enable --now qemu-guest-agent
EOF

cat > "$BASE/cloud-init/README.md" <<'EOF'
# cloud-init

* `minimal.yaml` : point de départ de E20.7 (à enrichir dans `ci-test.yaml`)
* `vendor-agent.yaml` : vendor-data qui garantit qemu-guest-agent
* validation : `cloud-init schema --config-file <f>` puis
  `python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' <f>`
* copie sur le nœud : `scp <f> root@10.10.10.1:/var/lib/vz/snippets/`
EOF

# ---------------------------------------------------------------------
# 3. Script de fabrication du template (à exécuter SUR LE NŒUD)
# ---------------------------------------------------------------------
cat > "$BASE/proxmox/make-template.sh" <<'EOF'
#!/usr/bin/env bash
# make-template.sh — fabrique le template cloud-init 9100 (Ubuntu 24.04)
# À exécuter en root SUR LE NŒUD PROXMOX. Idempotent : ne refait rien si
# 9100 est déjà un template.
#   scp ~/lab20/proxmox/make-template.sh root@10.10.10.1:/root/
#   scp ~/.ssh/id_ed25519.pub root@10.10.10.1:/root/keys/mathieu.pub
#   ssh root@10.10.10.1 bash /root/make-template.sh
set -euo pipefail

VMID=${VMID:-9100}
NAME=${NAME:-ubuntu-2404-tpl}
STORAGE=${STORAGE:-local-lvm}        # stockage des disques (raw sur LVM)
BRIDGE=${BRIDGE:-vmbr1}
KEYFILE=${KEYFILE:-/root/keys/mathieu.pub}
IMG_URL=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
IMG=/root/noble-server-cloudimg-amd64.img

[ "$(id -u)" -eq 0 ] || { echo "à lancer en root sur le nœud" >&2; exit 1; }
[ -r "$KEYFILE" ] || { echo "clé publique $KEYFILE absente" >&2; exit 1; }

if qm config "$VMID" 2>/dev/null | grep -q '^template: 1'; then
  echo "VM $VMID est déjà un template, rien à faire"; exit 0
fi
if qm status "$VMID" >/dev/null 2>&1; then
  echo "VM $VMID existe mais n'est pas un template : détruis-la d'abord" >&2
  exit 1
fi

# 1. image cloud officielle (téléchargée une fois)
[ -s "$IMG" ] || wget -q -O "$IMG" "$IMG_URL"

# 2. l'image n'embarque pas qemu-guest-agent : on l'injecte hors ligne.
#    Sans agent, « agent { enabled = true } » du provider attend 15 min.
if ! command -v virt-customize >/dev/null; then
  apt-get update -q && apt-get install -y -q libguestfs-tools
fi
virt-customize -q -a "$IMG" \
  --install qemu-guest-agent \
  --run-command 'systemctl enable qemu-guest-agent' \
  --truncate /etc/machine-id            # sinon tous les clones ont le même id

# 3. la VM : machine sérielle (les images cloud parlent sur ttyS0),
#    CPU x86-64-v2-AES (jeu d'instructions moderne, migrable), agent activé
qm create "$VMID" --name "$NAME" --memory 1024 --cores 1 \
  --net0 "virtio,bridge=$BRIDGE" --scsihw virtio-scsi-single --ostype l26 \
  --agent enabled=1 --cpu x86-64-v2-AES --serial0 socket --vga serial0
qm disk import "$VMID" "$IMG" "$STORAGE"
qm set "$VMID" --scsi0 "$STORAGE:vm-$VMID-disk-0,discard=on,iothread=1"
qm set "$VMID" --ide2 "$STORAGE:cloudinit" --boot order=scsi0
qm set "$VMID" --ciuser mathieu --sshkeys "$KEYFILE" \
  --ipconfig0 ip=dhcp --ciupgrade 0
qm disk resize "$VMID" scsi0 20G
qm template "$VMID"
echo "template $VMID ($NAME) prêt :"
qm config "$VMID" | grep -E '^(template|agent|ide2|scsi0|serial0|cpu|ciuser):'
EOF
chmod 755 "$BASE/proxmox/make-template.sh"

# ---------------------------------------------------------------------
# 4. Squelettes des exercices (providers local/random, sans Proxmox)
# ---------------------------------------------------------------------
poser "$BASE/e02/versions.tf" <<'EOF'
terraform {
  required_version = ">= 1.6"
  required_providers {
    local  = { source = "hashicorp/local", version = "~> 2.5" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}
EOF

poser "$BASE/e04/versions.tf" <<'EOF'
terraform {
  required_version = ">= 1.6"
  required_providers {
    local = { source = "hashicorp/local", version = "~> 2.5" }
  }
}
EOF
poser "$BASE/e04/variables.tf" <<'EOF'
# Utilisée par E20.4 (tofu console) et E20.5 (hosts.lab2)
variable "vms" {
  description = "VM du lab2 : nom => { vm_id, host (dernier octet) }"
  type = map(object({
    vm_id = number
    host  = number
  }))
  default = {
    lab2-adm  = { vm_id = 9101, host = 101 }
    lab2-web  = { vm_id = 9102, host = 102 }
    lab2-db   = { vm_id = 9103, host = 103 }
    lab2-rhel = { vm_id = 9104, host = 104 }
    lab2-ops  = { vm_id = 9105, host = 105 }
  }
}
EOF

poser "$BASE/e06/versions.tf" <<'EOF'
terraform {
  required_version = ">= 1.6"
  required_providers {
    local = { source = "hashicorp/local", version = "~> 2.5" }
  }
}
EOF

poser "$BASE/e13/versions.tf" <<'EOF'
terraform {
  required_version = ">= 1.6"
  required_providers {
    proxmox = { source = "bpg/proxmox", version = "~> 0.7" }
  }
}
EOF

poser "$BASE/01-premier/README.md" <<'EOF'
# 01-premier

Bac à sable libre : recopie ici ce que tu veux garder de e02/ à e06/.
EOF

# ---------------------------------------------------------------------
# 5. Squelettes des labs
# ---------------------------------------------------------------------
poser "$BASE/02-lab2/versions.tf" <<'EOF'
terraform {
  required_version = ">= 1.6"
  required_providers {
    proxmox = { source = "bpg/proxmox", version = "~> 0.7" }
  }
}
EOF
poser "$BASE/02-lab2/providers.tf" <<'EOF'
# endpoint et token viennent de PROXMOX_VE_ENDPOINT / PROXMOX_VE_API_TOKEN
provider "proxmox" {
  insecure = true
}
EOF
poser "$BASE/02-lab2/terraform.tfvars.example" <<'EOF'
vms = {
  lab2-adm  = { vm_id = 9101, host = 101 }
  lab2-web  = { vm_id = 9102, host = 102 }
  lab2-db   = { vm_id = 9103, host = 103, disk = 30 }
  lab2-rhel = { vm_id = 9104, host = 104 }
  lab2-ops  = { vm_id = 9105, host = 105, memory = 4096 }
}
EOF
poser "$BASE/02-lab2/notes.md" <<'EOF'
# Notes L20.2
EOF

poser "$BASE/03-remote/README.md" <<'EOF'
# 03-remote

Fichiers annexes de L20.3 : politique MinIO (`policy-tfstate.json`),
commandes `mc`, sauvegardes d'état (`backup-*.json`, ignorées par git).
EOF
poser "$BASE/03-remote/policy-tfstate.json" <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation",
                 "s3:GetBucketVersioning", "s3:ListBucketVersions"],
      "Resource": ["arn:aws:s3:::tfstate"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject",
                 "s3:GetObjectVersion", "s3:DeleteObjectVersion"],
      "Resource": ["arn:aws:s3:::tfstate/*"]
    }
  ]
}
EOF

poser "$BASE/04-modules/README.md" <<'EOF'
# 04-modules

Racine de L20.4 et D20 : même état distant que 02-lab2 (clé
`lab2/terraform.tfstate`), ressources déplacées dans `module "vm"`.
EOF

# module vide (à remplir en L20.4)
poser "$BASE/modules/vm-ubuntu/README.md" <<'EOF'
# Module vm-ubuntu

À remplir (L20.4) : variables.tf, main.tf, outputs.tf, versions.tf.
EOF

# ---------------------------------------------------------------------
# 6. Ansible : gabarit d'inventaire et playbook de base fourni
# ---------------------------------------------------------------------
cat > "$BASE/ansible/inventory.ini.example" <<'EOF'
# Gabarit : le vrai inventory.ini est généré par OpenTofu (L20.4)
[lab2]
lab2-adm ansible_host=10.10.10.101
lab2-web ansible_host=10.10.10.102

[docker]
lab2-ops

[lab2:vars]
ansible_user=mathieu
EOF

cat > "$BASE/ansible/ansible.cfg" <<'EOF'
[defaults]
inventory = inventory.ini
interpreter_python = auto_silent
host_key_checking = False
retry_files_enabled = False
EOF

poser "$BASE/ansible/base.yml" <<'EOF'
---
# Configuration de base des VM lab2 (fournie par le setup ; D20 l'enrichit)
- name: Base lab2
  hosts: lab2
  become: true
  vars:
    fuseau: Europe/Paris
  tasks:
    - name: Paquets de base
      ansible.builtin.apt:
        name: [htop, qemu-guest-agent]
        state: present
        update_cache: true
        cache_valid_time: 3600

    - name: Agent QEMU actif
      ansible.builtin.service:
        name: qemu-guest-agent
        state: started
        enabled: true

    - name: Bannière
      ansible.builtin.copy:
        dest: /etc/motd
        mode: "0644"
        content: |
          {{ inventory_hostname }} — VM lab2 gérée par OpenTofu + Ansible.
          Toute modification manuelle sera perdue au prochain apply.

    - name: Fuseau horaire (symlink, idempotent)
      ansible.builtin.file:
        src: "/usr/share/zoneinfo/{{ fuseau }}"
        dest: /etc/localtime
        state: link
        force: true

    - name: /etc/timezone cohérent
      ansible.builtin.copy:
        dest: /etc/timezone
        content: "{{ fuseau }}\n"
        mode: "0644"
EOF

# ---------------------------------------------------------------------
# 7. Notes et permissions
# ---------------------------------------------------------------------
poser "$BASE/notes.md" <<'EOF'
# Notes du module 20
EOF
[ -f "$BASE/.env" ] && chmod 600 "$BASE/.env"

cat <<EOF

== ~/lab20 prêt ==
  .env.example         -> copie en .env (chmod 600) après E20.8
  cloud-init/          -> minimal.yaml, vendor-agent.yaml
  proxmox/make-template.sh -> à copier et lancer sur le nœud (E20.9)
  e02 e04 e06 e13      -> exercices ; 02-lab2 03-remote 04-modules -> labs
  modules/vm-ubuntu/   -> module à écrire (L20.4)
  ansible/base.yml     -> playbook fourni (L20.4)
Outils : $(command -v tofu >/dev/null && tofu version | head -1 || echo "tofu ABSENT (voir 20.1)") ;\
 $(command -v cloud-init >/dev/null && echo "cloud-init OK" || echo "cloud-init ABSENT")
EOF
