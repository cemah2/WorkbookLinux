#!/usr/bin/env bash
# setup_M23.sh — prépare le nœud de contrôle Ansible du module 23 (lab-adm)
# À lancer avec sudo sur lab-adm : installe pipx, ansible-core, ansible-lint,
# yamllint, sshpass, les collections du module, et crée ~/lab23/ pour
# l'apprenant (ansible.cfg, inventaire, group_vars, vault chiffré).
# Idempotent : les fichiers déjà présents dans ~/lab23 ne sont PAS écrasés
# (sauf le vault, réécrit s'il ne se déchiffre plus avec .vault_pass).
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  LAB_USER="${SUDO_USER:-mathieu}"
else
  echo "à lancer avec sudo (installation de paquets)" >&2; exit 1
fi
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
BASE="$LAB_HOME/lab23"

echo "== Préparation du module 23 =="
echo "   utilisateur : $LAB_USER"
echo "   projet      : $BASE"

# en tant qu'apprenant, avec ~/.local/bin dans le PATH
as_user() { sudo -u "$LAB_USER" -H env PATH="$LAB_HOME/.local/bin:$PATH" "$@"; }

# ---------------------------------------------------------------------
# 1. Paquets système et outils pipx
# ---------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q pipx sshpass python3-yaml git curl tree >/dev/null

as_user pipx ensurepath >/dev/null 2>&1 || true
for outil in ansible-core ansible-lint yamllint; do
  if as_user pipx list --short 2>/dev/null | grep -q "^$outil "; then
    echo "   $outil déjà installé"
  else
    echo "   pipx install $outil"
    as_user pipx install "$outil" >/dev/null
  fi
done
as_user ansible --version | head -1

# ---------------------------------------------------------------------
# 2. Résolution de noms et known_hosts (pas de host_key_checking=False)
# ---------------------------------------------------------------------
declare -A HOTES=( [lab-adm]=10.10.10.10 [lab-web]=10.10.10.11
                   [lab-db]=10.10.10.12 [lab-rhel]=10.10.10.13
                   [lab-ops]=10.10.10.14 )
for h in "${!HOTES[@]}"; do
  grep -qE "^${HOTES[$h]}[[:space:]]" /etc/hosts \
    || echo "${HOTES[$h]} $h.lab.local $h" >> /etc/hosts
done

as_user mkdir -p "$LAB_HOME/.ssh"
as_user chmod 700 "$LAB_HOME/.ssh"
KH="$LAB_HOME/.ssh/known_hosts"
as_user touch "$KH"
for h in lab-web lab-db lab-rhel lab-ops; do
  ip=${HOTES[$h]}
  if ! as_user ssh-keygen -F "$ip" -f "$KH" >/dev/null 2>&1; then
    as_user ssh-keyscan -T 5 -t ed25519,rsa "$ip" 2>/dev/null >> "$KH" \
      || echo "   [warn] $h ($ip) injoignable pour ssh-keyscan"
  fi
  if ! as_user ssh-keygen -F "$h" -f "$KH" >/dev/null 2>&1; then
    as_user ssh-keyscan -T 5 -t ed25519,rsa "$h" 2>/dev/null >> "$KH" || true
  fi
done
[ -f "$LAB_HOME/.ssh/id_ed25519.pub" ] \
  || echo "   [warn] pas de ~/.ssh/id_ed25519.pub : génère et déploie ta clé" \
          "(module 14) avant les exercices"

# ---------------------------------------------------------------------
# 3. Arborescence du projet
# ---------------------------------------------------------------------
as_user mkdir -p "$BASE"/{inventory/group_vars/all,inventory/host_vars} \
  "$BASE"/{playbooks/templates,roles,collections,rapports,casse}

# n'écrase jamais un fichier existant
ecrire() { # ecrire <chemin>  (contenu sur stdin)
  local f=$1
  if [ -e "$f" ]; then cat >/dev/null; return; fi
  cat > "$f"; chown "$LAB_USER":"$LAB_USER" "$f"
}

ecrire "$BASE/ansible.cfg" <<'EOF'
[defaults]
inventory          = inventory/hosts.yml
remote_user        = mathieu
private_key_file   = ~/.ssh/id_ed25519
interpreter_python = auto_silent
forks              = 10
roles_path         = roles
collections_path   = collections
callback_result_format = yaml
vault_password_file = .vault_pass
retry_files_enabled = False
# host_key_checking = False   # NON : les clés sont dans known_hosts

[privilege_escalation]
# become = True  -> à activer après L23.1 (compte ansible en NOPASSWD)
become_method = sudo

[ssh_connection]
pipelining = True
ssh_args   = -o ControlMaster=auto -o ControlPersist=60s
EOF

ecrire "$BASE/inventory/hosts.yml" <<'EOF'
---
# Inventaire du lab (module 23). Un hôte peut être dans plusieurs groupes.
all:
  hosts:
    lab-web:
      ansible_host: 10.10.10.11
    lab-db:
      ansible_host: 10.10.10.12
    lab-rhel:
      ansible_host: 10.10.10.13
    lab-ops:
      ansible_host: 10.10.10.14
  children:
    web:
      hosts:
        lab-web:
        lab-rhel:
    db:
      hosts:
        lab-db:
    ops:
      hosts:
        lab-ops:
    ubuntu:
      hosts:
        lab-web:
        lab-db:
        lab-ops:
    rhel:
      hosts:
        lab-rhel:
EOF

ecrire "$BASE/inventory/group_vars/all/vars.yml" <<'EOF'
---
# Variables communes à tout le parc
lab_domain: lab.local
admin_user: mathieu
prometheus_host: 10.10.10.14
# secret : la valeur vit dans vault.yml (chiffré), ici seulement la référence
monitoring_token: "{{ vault_monitoring_token }}"
EOF

ecrire "$BASE/inventory/group_vars/ubuntu.yml" <<'EOF'
---
sudo_group: sudo
ansible_python_interpreter: /usr/bin/python3
EOF

ecrire "$BASE/inventory/group_vars/rhel.yml" <<'EOF'
---
sudo_group: wheel
ansible_python_interpreter: /usr/bin/python3
EOF

ecrire "$BASE/collections/requirements.yml" <<'EOF'
---
collections:
  - name: ansible.posix
    version: ">=1.5.0,<3.0.0"
  - name: community.crypto
    version: ">=2.16.0,<3.0.0"
  - name: community.postgresql
    version: ">=3.4.0,<4.0.0"
EOF

ecrire "$BASE/.yamllint" <<'EOF'
---
extends: default
rules:
  line-length:
    max: 100
  truthy:
    allowed-values: ["true", "false"]
  comments:
    min-spaces-from-content: 1
  braces:
    max-spaces-inside: 1
EOF

ecrire "$BASE/.ansible-lint" <<'EOF'
---
profile: production
exclude_paths:
  - collections/
  - casse/
  - .cache/
EOF

ecrire "$BASE/.gitignore" <<'EOF'
.vault_pass
*.retry
.cache/
collections/ansible_collections/
EOF

# ---------------------------------------------------------------------
# 4. Vault d'équipe : mot de passe + fichier chiffré
# ---------------------------------------------------------------------
VP="$BASE/.vault_pass"
if [ ! -f "$VP" ]; then
  printf 'Lab19-Vault-Equipe\n' > "$VP"
  chown "$LAB_USER":"$LAB_USER" "$VP"; chmod 600 "$VP"
fi
VAULT="$BASE/inventory/group_vars/all/vault.yml"
if [ -f "$VAULT" ] && as_user ansible-vault view --vault-password-file "$VP" \
     "$VAULT" >/dev/null 2>&1; then
  echo "   vault.yml présent et déchiffrable"
else
  TMPV=$(mktemp)
  cat > "$TMPV" <<'EOF'
---
# Secrets du parc : préfixe vault_, référencés depuis vars.yml
vault_monitoring_token: "tok-lab23-3f9a1c7e"
EOF
  chown "$LAB_USER":"$LAB_USER" "$TMPV"
  as_user ansible-vault encrypt --vault-password-file "$VP" \
    --output "$VAULT" "$TMPV" >/dev/null
  rm -f "$TMPV"
  chown "$LAB_USER":"$LAB_USER" "$VAULT"
  echo "   vault.yml chiffré avec .vault_pass"
fi

# ---------------------------------------------------------------------
# 5. Collections du module (dans ./collections, cf. collections_path)
# ---------------------------------------------------------------------
( cd "$BASE" && as_user ansible-galaxy collection install \
    -r collections/requirements.yml -p collections >/dev/null ) \
  && echo "   collections installées dans $BASE/collections" \
  || echo "   [warn] installation des collections échouée (accès Internet ?)"
# community.general est volontairement absente : E23.15 la fait ajouter

chown -R "$LAB_USER":"$LAB_USER" "$BASE"

cat <<EOF

Prêt. Ouvre un nouveau shell (ou 'exec bash') pour avoir ~/.local/bin
dans le PATH, puis :
  cd ~/lab23 && ansible all -m ansible.builtin.ping
Tant que L23.1 n'est pas fait, ajoute -K aux commandes qui utilisent become.
EOF
