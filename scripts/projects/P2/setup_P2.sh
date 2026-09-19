#!/usr/bin/env bash
# setup_P2.sh — prépare le terrain du Projet B (Factura v2, DevOps)
# À lancer avec sudo sur lab-adm (10.10.10.10). Idempotent.
#
# Ce script :
#   1. installe l'outillage du projet (git, pre-commit, gitleaks, shellcheck,
#      yamllint, ansible + ansible-lint, OpenTofu, docker, kubectl) ;
#   2. dépose le mono-repo de départ dans ~/factura-v2 (squelette + app) ;
#   3. ajoute les noms des VM du projet dans /etc/hosts ;
#   4. affiche ce qu'il reste à faire à la main (template Proxmox, Gitea).
# Il NE crée aucune VM, aucun dépôt Gitea, aucun pipeline : c'est le projet.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$LAB_HOME/factura-v2"
TOFU_VERSION="${TOFU_VERSION:-1.8.2}"
GITLEAKS_VERSION="${GITLEAKS_VERSION:-8.18.4}"

echo "== Préparation du Projet B (Factura v2) =="
echo "   utilisateur : $LAB_USER"
echo "   dépôt local : $REPO"

# ---------------------------------------------------------------------
# 1. Outillage
# ---------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git curl jq unzip python3 python3-pip python3-venv \
  pipx shellcheck yamllint make openssl ca-certificates gnupg \
  docker.io docker-compose-v2 postgresql-client >/dev/null

usermod -aG docker "$LAB_USER"

# pre-commit, ansible, ansible-lint : isolés dans pipx (pas de pip --user
# cassé par PEP 668 sur Ubuntu 24.04)
sudo -u "$LAB_USER" -H bash -c '
  export PATH="$HOME/.local/bin:$PATH"
  pipx ensurepath >/dev/null 2>&1 || true
  for p in pre-commit ansible-lint; do
    pipx list 2>/dev/null | grep -q "package $p " || pipx install -q "$p"
  done
  pipx list 2>/dev/null | grep -q "package ansible " \
    || pipx install -q --include-deps ansible
  pipx inject -q ansible psycopg2-binary jmespath >/dev/null 2>&1 || true
  pipx inject -q ansible-lint yamllint >/dev/null 2>&1 || true
'

# OpenTofu (binaire officiel)
if ! command -v tofu >/dev/null 2>&1 \
   || ! tofu version | grep -q "v$TOFU_VERSION"; then
  ARCH=$(dpkg --print-architecture)
  URL="https://github.com/opentofu/opentofu/releases/download"
  URL="$URL/v$TOFU_VERSION/tofu_${TOFU_VERSION}_linux_${ARCH}.zip"
  TMP=$(mktemp -d)
  if curl -fsSL "$URL" -o "$TMP/tofu.zip"; then
    unzip -q -o "$TMP/tofu.zip" -d "$TMP"
    install -m 0755 "$TMP/tofu" /usr/local/bin/tofu
  else
    echo "   [warn] téléchargement OpenTofu impossible, installe-le à la main"
  fi
  rm -rf "$TMP"
fi

# gitleaks (binaire officiel)
if ! command -v gitleaks >/dev/null 2>&1; then
  ARCH=$(dpkg --print-architecture); [ "$ARCH" = amd64 ] && ARCH=x64
  URL="https://github.com/gitleaks/gitleaks/releases/download"
  URL="$URL/v$GITLEAKS_VERSION/gitleaks_${GITLEAKS_VERSION}_linux_${ARCH}.tar.gz"
  TMP=$(mktemp -d)
  if curl -fsSL "$URL" | tar -xz -C "$TMP" gitleaks 2>/dev/null; then
    install -m 0755 "$TMP/gitleaks" /usr/local/bin/gitleaks
  else
    echo "   [warn] téléchargement gitleaks impossible, installe-le à la main"
  fi
  rm -rf "$TMP"
fi

# kubectl (pour PB.10)
if ! command -v kubectl >/dev/null 2>&1; then
  KV=$(curl -fsSL https://dl.k8s.io/release/stable.txt 2>/dev/null || true)
  if [ -n "$KV" ] && curl -fsSL -o /tmp/kubectl \
     "https://dl.k8s.io/release/$KV/bin/linux/$(dpkg --print-architecture)/kubectl"
  then
    install -m 0755 /tmp/kubectl /usr/local/bin/kubectl; rm -f /tmp/kubectl
  else
    echo "   [warn] kubectl non téléchargé (PB.10 : à installer plus tard)"
  fi
fi

# ---------------------------------------------------------------------
# 2. Mono-repo de départ
# ---------------------------------------------------------------------
if [ ! -d "$REPO" ]; then
  mkdir -p "$REPO"
  cp -a "$HERE/repo-skeleton/." "$REPO/"
  cp -a "$HERE/app/." "$REPO/app/"
  chown -R "$LAB_USER:$LAB_USER" "$REPO"
  echo "   squelette déposé dans $REPO"
else
  echo "   $REPO existe déjà : squelette non réécrit"
fi

# Copie des outils du projet (utilisés par les checks et la reconstruction)
mkdir -p "$REPO/tools"
for t in rebuild.sh smoke.sh; do
  [ -f "$REPO/tools/$t" ] || cp "$HERE/tools/$t" "$REPO/tools/$t"
done
chmod 0755 "$REPO"/tools/*.sh
chown -R "$LAB_USER:$LAB_USER" "$REPO/tools"

# Clé SSH de déploiement (utilisée par cloud-init et par le runner CI)
KEY="$LAB_HOME/.ssh/id_ed25519"
if [ ! -f "$KEY" ]; then
  sudo -u "$LAB_USER" ssh-keygen -q -t ed25519 -N "" -f "$KEY" \
    -C "$LAB_USER@lab-adm"
  echo "   clé SSH générée : $KEY"
fi

# ---------------------------------------------------------------------
# 3. Résolution de noms des VM du projet
# ---------------------------------------------------------------------
add_host() {
  grep -qE "^$1[[:space:]]" /etc/hosts \
    || printf '%s %s %s.lab.local\n' "$1" "$2" "$2" >> /etc/hosts
}
add_host 10.10.10.14 lab-ops
add_host 10.10.10.21 factura-staging-web
add_host 10.10.10.22 factura-staging-db
add_host 10.10.10.31 factura-prod-web
add_host 10.10.10.32 factura-prod-db
add_host 10.10.10.41 factura-k3s

# Registre Gitea en HTTP (pas de TLS dans le lab) : docker doit l'accepter
mkdir -p /etc/docker
if [ ! -f /etc/docker/daemon.json ] \
   || ! grep -q 'lab-ops.lab.local:3000' /etc/docker/daemon.json; then
  cat > /etc/docker/daemon.json <<'EOF'
{
  "insecure-registries": ["lab-ops.lab.local:3000"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
  systemctl restart docker
fi

# ---------------------------------------------------------------------
# 4. Ce que le script ne fait pas
# ---------------------------------------------------------------------
cat <<EOF

== Prêt. Reste à faire à la main (voir B.0 de l'énoncé) ==
  * Proxmox : template cloud-init VMID 9000 (module 24). Si absent :
      scp $HERE/tools/make-template.sh root@<proxmox>:/root/
      ssh root@<proxmox> bash /root/make-template.sh
  * Proxmox : token API pour OpenTofu (tofu@pve!factura), puis :
      export TF_VAR_pve_api_token='tofu@pve!factura=xxxxxxxx-...'
  * Gitea (lab-ops:3000, module 25) : dépôt mathieu/factura, runner
    act_runner label « ops-host », token d'accès au registre.
  * Reconnecte-toi pour que le groupe docker et ~/.local/bin soient pris
    en compte : exit puis ssh lab-adm.
EOF
