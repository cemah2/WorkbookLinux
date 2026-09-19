#!/usr/bin/env bash
# setup_M25.sh — prépare le terrain du module 25 (CI/CD)
# À lancer avec sudo. Détecte l'hôte :
#   lab-ops (10.10.10.14) : Docker, forge Gitea + PostgreSQL + registre +
#                            act_runner, dépôts factura et factura-infra,
#                            clés de déploiement, jeton d'API.
#   lab-web (10.10.10.11) : Docker, nginx, utilisateur deploy, /srv/factura.
# Idempotent : relançable. Les dépôts ~/lab25/factura et factura-infra ne
# sont PAS réinitialisés s'ils existent déjà (travail de l'apprenant).
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

OPS_IP=10.10.10.14
WEB_IP=10.10.10.11
GITEA_URL="http://$OPS_IP:3000"
REG="$OPS_IP:5000"
REG_USER=mathieu
REG_PASS='Factura-Reg-2026'
GITEA_PASS='Factura2026!'
BASE="$LAB_HOME/lab25"

mode="${1:-auto}"
if [ "$mode" = auto ]; then
  if ip -4 addr | grep -q "$OPS_IP/"; then mode=ops
  elif ip -4 addr | grep -q "$WEB_IP/"; then mode=web
  else
    case "$(hostname -s)" in
      lab-ops) mode=ops ;; lab-web) mode=web ;;
      *) echo "hôte non reconnu : lance avec --ops ou --web" >&2; exit 1 ;;
    esac
  fi
fi
mode="${mode#--}"

# ---------------------------------------------------------------------
# Commun : Docker + registre non sécurisé
# ---------------------------------------------------------------------
installer_docker() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -q
  apt-get install -y -q docker.io docker-compose-v2 curl git jq \
    python3-yaml "$@"
  systemctl enable --now docker
}

daemon_json() {
  python3 - <<EOF
import json, os
p = "/etc/docker/daemon.json"
d = {}
if os.path.exists(p):
    try:
        d = json.load(open(p))
    except Exception:
        d = {}
lst = d.setdefault("insecure-registries", [])
if "$REG" not in lst:
    lst.append("$REG")
    json.dump(d, open(p, "w"), indent=2)
    print("changed")
EOF
}

docker_login_fichier() {   # $1 = home, $2 = owner
  install -d -m 700 -o "$2" -g "$2" "$1/.docker"
  local auth
  auth=$(printf '%s:%s' "$REG_USER" "$REG_PASS" | base64 -w0)
  python3 - "$1/.docker/config.json" "$auth" <<'EOF'
import json, os, sys
p, auth = sys.argv[1:]
d = {}
if os.path.exists(p):
    try:
        d = json.load(open(p))
    except Exception:
        d = {}
d.setdefault("auths", {})["10.10.10.14:5000"] = {"auth": auth}
json.dump(d, open(p, "w"), indent=2)
EOF
  chown "$2:$2" "$1/.docker/config.json"; chmod 600 "$1/.docker/config.json"
}

# =====================================================================
# lab-web
# =====================================================================
if [ "$mode" = web ]; then
  echo "== Préparation du module 25 sur lab-web =="
  installer_docker nginx
  if [ "$(daemon_json)" = changed ]; then systemctl restart docker; fi
  id deploy >/dev/null 2>&1 || useradd -m -s /bin/bash -G docker deploy
  usermod -aG docker deploy
  install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
  install -d -m 755 -o deploy -g deploy /srv/factura /srv/factura-bg
  docker_login_fichier /home/deploy deploy
  cat <<EOF

lab-web prêt :
  - Docker + nginx installés, registre $REG déclaré non sécurisé
  - utilisateur deploy (groupe docker), /srv/factura et /srv/factura-bg
  - docker login vers $REG fait pour deploy
À toi : clés dans /home/deploy/.ssh/authorized_keys (E25.12, L25.2, L25.3),
/usr/local/bin/factura-deploy, compose.yaml, nginx.
EOF
  exit 0
fi

# =====================================================================
# lab-ops
# =====================================================================
echo "== Préparation du module 25 sur lab-ops =="
echo "   utilisateur : $LAB_USER"
echo "   base        : $BASE"

installer_docker apache2-utils shellcheck yamllint openssh-client
usermod -aG docker "$LAB_USER"
if [ "$(daemon_json)" = changed ]; then systemctl restart docker; fi

install -d -o "$LAB_USER" -g "$LAB_USER" \
  "$BASE" "$BASE/forge" "$BASE/forge/runner" "$BASE/forge/runner/data" \
  "$BASE/forge/registry" "$BASE/forge/registry/auth" "$BASE/keys" \
  "$BASE/rapports" "$BASE/rapports/equivalents"

# ---------------------------------------------------------------------
# 1. Forge : compose
# ---------------------------------------------------------------------
[ -s "$BASE/forge/registry/auth/htpasswd" ] \
  || htpasswd -Bbn "$REG_USER" "$REG_PASS" > "$BASE/forge/registry/auth/htpasswd"

cat > "$BASE/forge/compose.yaml" <<EOF
# Forge du lab : Gitea + PostgreSQL + registre OCI + act_runner
# Le runner est dans le profil "runner" : il a besoin d'un jeton
# d'enregistrement généré une fois Gitea démarré (voir .env).
services:
  gitea:
    image: docker.gitea.com/gitea:1.24
    container_name: gitea
    restart: unless-stopped
    environment:
      USER_UID: "1000"
      USER_GID: "1000"
      GITEA__database__DB_TYPE: postgres
      GITEA__database__HOST: db:5432
      GITEA__database__NAME: gitea
      GITEA__database__USER: gitea
      GITEA__database__PASSWD: gitea
      GITEA__server__ROOT_URL: $GITEA_URL/
      GITEA__server__DOMAIN: $OPS_IP
      GITEA__server__SSH_DOMAIN: $OPS_IP
      GITEA__server__SSH_PORT: "2222"
      GITEA__server__HTTP_PORT: "3000"
      GITEA__security__INSTALL_LOCK: "true"
      GITEA__service__DISABLE_REGISTRATION: "true"
      GITEA__actions__ENABLED: "true"
      GITEA__actions__DEFAULT_ACTIONS_URL: github
      GITEA__log__LEVEL: Info
    volumes:
      - ./gitea:/data
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "3000:3000"
      - "2222:22"
    depends_on:
      - db

  db:
    image: postgres:16
    container_name: gitea-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: gitea
      POSTGRES_PASSWORD: gitea
      POSTGRES_DB: gitea
    volumes:
      - ./postgres:/var/lib/postgresql/data

  registry:
    image: registry:2
    container_name: registry
    restart: unless-stopped
    environment:
      REGISTRY_AUTH: htpasswd
      REGISTRY_AUTH_HTPASSWD_REALM: factura-registry
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/htpasswd
      REGISTRY_STORAGE_DELETE_ENABLED: "true"
    volumes:
      - ./registry/data:/var/lib/registry
      - ./registry/auth:/auth:ro
    ports:
      - "5000:5000"

  runner:
    image: docker.gitea.com/act_runner:latest
    container_name: act-runner
    restart: unless-stopped
    profiles: ["runner"]
    # network_mode host : les conteneurs de jobs (créés via le socket de
    # l'hôte, hors de ce réseau compose) joignent le runner et Gitea par
    # l'IP de lab-ops. Le nom "gitea" n'existe pas pour eux.
    network_mode: host
    environment:
      CONFIG_FILE: /config.yaml
      GITEA_INSTANCE_URL: $GITEA_URL
      GITEA_RUNNER_REGISTRATION_TOKEN: \${RUNNER_TOKEN}
      GITEA_RUNNER_NAME: runner-ops
      GITEA_RUNNER_LABELS: >-
        ubuntu-latest:docker://docker.gitea.com/runner-images:ubuntu-latest
    volumes:
      - ./runner/config.yaml:/config.yaml:ro
      - ./runner/data:/data
      - /var/run/docker.sock:/var/run/docker.sock
EOF

cat > "$BASE/forge/runner/config.yaml" <<EOF
# Configuration act_runner (format act_runner generate-config)
log:
  level: info

runner:
  file: .runner
  capacity: 1
  envs: {}
  env_file: .env
  timeout: 3h
  shutdown_timeout: 0s
  insecure: false
  fetch_timeout: 5s
  fetch_interval: 2s
  labels:
    - "ubuntu-latest:docker://docker.gitea.com/runner-images:ubuntu-latest"

cache:
  enabled: false
  dir: ""
  host: "$OPS_IP"
  port: 4000
  external_server: ""

container:
  network: ""
  privileged: false
  options:
  workdir_parent:
  valid_volumes: []
  # "" : le socket Docker est monté dans chaque job ; "-" : jamais
  docker_host: ""
  force_pull: true
  force_rebuild: false

host:
  workdir_parent:
EOF

cd "$BASE/forge"
[ -f .env ] || printf 'RUNNER_TOKEN=\n' > .env
chmod 600 .env
docker compose up -d gitea db registry

echo "   attente de Gitea..."
for i in $(seq 1 60); do
  curl -fs "$GITEA_URL/api/healthz" >/dev/null 2>&1 && break
  sleep 2
  [ "$i" -eq 60 ] && { echo "Gitea ne répond pas" >&2; exit 1; }
done
sleep 3

# ---------------------------------------------------------------------
# 2. Compte, jeton d'API, jeton runner
# ---------------------------------------------------------------------
gitea_cli() { docker exec -u git gitea gitea "$@"; }

if ! gitea_cli admin user list 2>/dev/null | awk '{print $2}' | grep -qx "$LAB_USER"; then
  gitea_cli admin user create --admin --username "$LAB_USER" \
    --password "$GITEA_PASS" --email "$LAB_USER@lab.local" \
    --must-change-password=false
fi

TOKEN_FILE="$BASE/.gitea-token"
if [ ! -s "$TOKEN_FILE" ]; then
  gitea_cli admin user generate-access-token --username "$LAB_USER" \
    --token-name "lab25-$(date +%s)" --scopes all --raw > "$TOKEN_FILE"
fi
chown "$LAB_USER:$LAB_USER" "$TOKEN_FILE"; chmod 600 "$TOKEN_FILE"
TOKEN=$(tr -d '[:space:]' < "$TOKEN_FILE")
API="$GITEA_URL/api/v1"
api() { curl -s -H "Authorization: token $TOKEN" \
          -H 'Content-Type: application/json' "$@"; }

if [ ! -s "$BASE/forge/runner/data/.runner" ]; then
  RT=$(gitea_cli actions generate-runner-token | tr -d '[:space:]')
  sed -i "s/^RUNNER_TOKEN=.*/RUNNER_TOKEN=$RT/" .env
fi
docker compose --profile runner up -d runner

# ---------------------------------------------------------------------
# 3. Clés, credential helper, docker login
# ---------------------------------------------------------------------
for k in deploy bg ansible; do
  [ -f "$BASE/keys/$k" ] || sudo -u "$LAB_USER" ssh-keygen -q -t ed25519 \
    -N '' -C "$k@lab-ops" -f "$BASE/keys/$k"
done
printf 'http://%s:%s@%s\n' "$LAB_USER" "$TOKEN" "$OPS_IP" \
  > "$BASE/.git-credentials"
chown "$LAB_USER:$LAB_USER" "$BASE/.git-credentials"
chmod 600 "$BASE/.git-credentials"
docker_login_fichier "$LAB_HOME" "$LAB_USER"

# ---------------------------------------------------------------------
# 4. Dépôts Gitea
# ---------------------------------------------------------------------
for r in factura factura-infra; do
  api -o /dev/null -w '' -X POST "$API/user/repos" \
    -d "{\"name\":\"$r\",\"default_branch\":\"main\",\"private\":false,\
\"description\":\"module 25\"}" || true
done

git_u() { sudo -u "$LAB_USER" git "$@"; }

publier_depot() {   # $1 = répertoire, $2 = nom du dépôt
  local d=$1 r=$2
  chown -R "$LAB_USER:$LAB_USER" "$d"
  if [ ! -d "$d/.git" ]; then
    git_u -C "$d" init -q -b main
    git_u -C "$d" config user.name "$LAB_USER"
    git_u -C "$d" config user.email "$LAB_USER@lab.local"
    git_u -C "$d" config credential.helper "store --file $BASE/.git-credentials"
    git_u -C "$d" remote add origin "$GITEA_URL/$LAB_USER/$r.git"
    git_u -C "$d" add -A
    git_u -C "$d" commit -q -m "feat: version initiale de $r"
    git_u -C "$d" push -q -u origin main
  fi
}

# ---- factura : application Flask ------------------------------------
APP="$BASE/factura"
if [ ! -d "$APP/.git" ]; then
  install -d -o "$LAB_USER" -g "$LAB_USER" "$APP" "$APP/scripts" "$APP/deploy"

  cat > "$APP/README.md" <<'EOF'
# factura

Micro-service de démonstration du module 25 (Flask + gunicorn).

* `GET /` : bannière
* `GET /health` : JSON `{"status":"ok","version":...,"color":...}`
* `GET /version` : le SHA injecté au build (`APP_VERSION`), en texte brut
* `GET /factures/<id>` : une facture fictive, 404 si `id <= 0`

Tests : `pip install -r requirements-dev.txt && pytest -q`
Image : `docker build --build-arg APP_VERSION=$(git rev-parse --short=12 HEAD) .`
EOF

  cat > "$APP/app.py" <<'EOF'
"""factura — micro-service de démonstration (module 25)."""
import os

from flask import Flask, abort, jsonify

app = Flask(__name__)
VERSION = os.environ.get("APP_VERSION", "dev")
COLOR = os.environ.get("APP_COLOR", "none")


@app.get("/")
def index():
    return f"factura {VERSION} ({COLOR})\n"


@app.get("/health")
def health():
    return jsonify(status="ok", version=VERSION, color=COLOR)


@app.get("/version")
def version():
    return VERSION + "\n"


@app.get("/factures/<int:num>")
def facture(num):
    # BUG livré volontairement : 0 doit renvoyer 404 (voir test_app.py)
    if num < 0:
        abort(404)
    return jsonify(id=num, montant=round(num * 12.5, 2), devise="EUR")
EOF

  cat > "$APP/test_app.py" <<'EOF'
import pytest

from app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def test_index(client):
    r = client.get("/")
    assert r.status_code == 200
    assert b"factura" in r.data


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"


def test_version(client):
    r = client.get("/version")
    assert r.status_code == 200
    assert r.data.strip() != b""


def test_facture(client):
    r = client.get("/factures/4")
    assert r.status_code == 200
    assert r.get_json()["montant"] == 50.0


def test_facture_zero(client):
    assert client.get("/factures/0").status_code == 404
EOF

  cat > "$APP/requirements.txt" <<'EOF'
flask==3.0.3
gunicorn==23.0.0
EOF
  cat > "$APP/requirements-dev.txt" <<'EOF'
-r requirements.txt
pytest==8.3.3
EOF

  cat > "$APP/Dockerfile" <<'EOF'
FROM python:3.12-slim

ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && useradd --system --uid 10001 --no-create-home app
COPY app.py .

USER app
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"]
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "app:app"]
EOF

  cat > "$APP/compose.yaml" <<'EOF'
# Développement local : docker compose up --build
services:
  app:
    build:
      context: .
      args:
        APP_VERSION: local
    ports:
      - "8000:8000"
    environment:
      APP_COLOR: local
EOF

  cat > "$APP/deploy/compose.yaml" <<'EOF'
# Modèle pour /srv/factura/compose.yaml sur lab-web (L25.2).
# TAG vient de /srv/factura/.env, écrit par factura-deploy.
services:
  app:
    image: 10.10.10.14:5000/factura:${TAG:?TAG obligatoire}
    ports:
      - "8080:8000"
    restart: unless-stopped
    environment:
      APP_COLOR: single
EOF

  cat > "$APP/deploy/factura-deploy.sh" <<'EOF'
#!/usr/bin/env bash
# Squelette de /usr/local/bin/factura-deploy (lab-web) — à compléter en L25.2.
# Commande forcée : SSH_ORIGINAL_COMMAND contient "deploy <tag>",
# "rollback" ou "status".
set -euo pipefail
cd /srv/factura
read -r action tag _ <<<"${SSH_ORIGINAL_COMMAND:-}"
case "${action:-}" in
  deploy)   echo "TODO: valider '$tag', sauvegarder .env, pull, up" ;;
  rollback) echo "TODO: restaurer .env.prev, pull, up" ;;
  status)   cat .env ;;
  *)        echo "commande refusée" >&2; exit 2 ;;
esac
EOF
  chmod 755 "$APP/deploy/factura-deploy.sh"

  cat > "$APP/scripts/smoke.sh" <<'EOF'
#!/usr/bin/env bash
# smoke.sh <url> <version attendue> — vérifie que /version répond avec le tag
set -euo pipefail
URL=${1:?url}; ATTENDU=${2:?version}
for i in $(seq 1 10); do
  v=$(curl -fsS $URL/version || true)
  if [ "$v" = "$ATTENDU" ]; then echo "OK $v"; exit 0; fi
  sleep 3
done
echo "version servie '$v', attendue '$ATTENDU'" >&2
exit 1
EOF
  chmod 755 "$APP/scripts/smoke.sh"

  cat > "$APP/.gitignore" <<'EOF'
__pycache__/
*.pyc
.pytest_cache/
rapport-tests.xml
EOF
  cat > "$APP/.dockerignore" <<'EOF'
.git
__pycache__
.pytest_cache
test_app.py
deploy
scripts
EOF
fi
publier_depot "$APP" factura

# ---- factura-infra : Ansible + OpenTofu ------------------------------
INF="$BASE/factura-infra"
if [ ! -d "$INF/.git" ]; then
  install -d -o "$LAB_USER" -g "$LAB_USER" "$INF" "$INF/ansible" \
    "$INF/ansible/templates" "$INF/tofu"

  cat > "$INF/README.md" <<'EOF'
# factura-infra

* `ansible/` : configuration de lab-web (nginx blue/green, deploy, Docker)
* `tofu/` : génération de l'inventaire du lab (OpenTofu, provider local)

Pipelines : voir L25.4 du module 25.
EOF

  cat > "$INF/ansible/ansible.cfg" <<'EOF'
[defaults]
inventory = inventory.ini
interpreter_python = auto_silent
host_key_checking = True
retry_files_enabled = False
EOF

  cat > "$INF/ansible/inventory.ini" <<'EOF'
[web]
lab-web ansible_host=10.10.10.11 ansible_user=mathieu
EOF

  cat > "$INF/ansible/site.yml" <<'EOF'
---
- name: Frontal factura blue/green sur lab-web
  hosts: web
  become: true
  vars:
    registry: "10.10.10.14:5000"
    nginx_worker_connections: 768
    factura_colors:
      blue: 8081
      green: 8082

  handlers:
    - name: Redémarrer docker
      ansible.builtin.service:
        name: docker
        state: restarted

    - name: Recharger nginx
      ansible.builtin.service:
        name: nginx
        state: reloaded

  tasks:
    - name: Paquets
      ansible.builtin.apt:
        name:
          - nginx
          - docker.io
          - docker-compose-v2
        state: present
        update_cache: true
        cache_valid_time: 3600

    - name: Utilisateur deploy
      ansible.builtin.user:
        name: deploy
        groups: docker
        append: true
        shell: /bin/bash

    - name: Registre non sécurisé
      ansible.builtin.template:
        src: templates/daemon.json.j2
        dest: /etc/docker/daemon.json
        owner: root
        group: root
        mode: "0644"
      notify: Redémarrer docker

    - name: Répertoires de déploiement
      ansible.builtin.file:
        path: "{{ item.path }}"
        state: directory
        owner: "{{ item.owner }}"
        group: "{{ item.owner }}"
        mode: "0755"
      loop:
        - {path: /srv/factura, owner: deploy}
        - {path: /srv/factura-bg, owner: deploy}
        - {path: /etc/nginx/factura, owner: root}

    - name: Upstreams blue et green
      ansible.builtin.template:
        src: templates/upstream.conf.j2
        dest: "/etc/nginx/factura/{{ item.key }}.conf"
        owner: root
        group: root
        mode: "0644"
      loop: "{{ factura_colors | dict2items }}"
      notify: Recharger nginx

    - name: Symlink d'aiguillage présent ?
      ansible.builtin.stat:
        path: /etc/nginx/conf.d/factura-upstream.conf
      register: aiguillage

    - name: Aiguillage initial sur blue
      ansible.builtin.file:
        src: /etc/nginx/factura/blue.conf
        dest: /etc/nginx/conf.d/factura-upstream.conf
        state: link
      when: not aiguillage.stat.exists
      notify: Recharger nginx

    - name: Site factura
      ansible.builtin.template:
        src: templates/factura-site.conf.j2
        dest: /etc/nginx/sites-available/factura.conf
        owner: root
        group: root
        mode: "0644"
      notify: Recharger nginx

    - name: Site factura activé
      ansible.builtin.file:
        src: /etc/nginx/sites-available/factura.conf
        dest: /etc/nginx/sites-enabled/factura.conf
        state: link
      notify: Recharger nginx

    - name: Site default désactivé
      ansible.builtin.file:
        path: /etc/nginx/sites-enabled/default
        state: absent
      notify: Recharger nginx

    - name: Taille du pool de connexions nginx
      ansible.builtin.lineinfile:
        path: /etc/nginx/nginx.conf
        regexp: '^\s*worker_connections'
        line: "\tworker_connections {{ nginx_worker_connections }};"
      notify: Recharger nginx

    - name: Vérifier la configuration nginx
      ansible.builtin.command: nginx -t
EOF

  cat > "$INF/ansible/templates/daemon.json.j2" <<'EOF'
{
  "insecure-registries": ["{{ registry }}"]
}
EOF
  cat > "$INF/ansible/templates/upstream.conf.j2" <<'EOF'
# {{ item.key }} — géré par Ansible (factura-infra)
upstream factura_live { server 127.0.0.1:{{ item.value }}; }
EOF
  cat > "$INF/ansible/templates/factura-site.conf.j2" <<'EOF'
# géré par Ansible (factura-infra)
map $upstream_addr $factura_color {
    "~:8081" blue;
    "~:8082" green;
    default  unknown;
}
server {
    listen 80 default_server;
    server_name _;
    location / {
        proxy_pass http://factura_live;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        add_header X-Factura-Color $factura_color always;
    }
}
EOF

  cat > "$INF/.yamllint" <<'EOF'
extends: default
rules:
  line-length:
    max: 100
  truthy:
    allowed-values: ["true", "false", "on"]
  document-start: disable
EOF

  cat > "$INF/tofu/versions.tf" <<'EOF'
terraform {
  required_version = ">= 1.6"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
EOF
  cat > "$INF/tofu/main.tf" <<'EOF'
variable "hosts" {
  description = "Machines du lab : nom => IP"
  type        = map(string)
  default = {
    lab-adm = "10.10.10.10"
    lab-web = "10.10.10.11"
    lab-db  = "10.10.10.12"
    lab-ops = "10.10.10.14"
  }
}

resource "local_file" "inventaire" {
  filename        = "${path.module}/generated/inventaire.ini"
  file_permission = "0644"
  content = join("\n", concat(
    ["[lab]"],
    [for n, ip in var.hosts : "${n} ansible_host=${ip}"],
    [""]
  ))
}

output "hosts" {
  value = keys(var.hosts)
}
EOF
  cat > "$INF/tofu/.gitignore" <<'EOF'
.terraform/
*.tfstate
*.tfstate.backup
plan.bin
plan.txt
generated/
EOF
fi
publier_depot "$INF" factura-infra

# ---------------------------------------------------------------------
# 5. Données pour E25.15 (journal de déploiements fictif)
# ---------------------------------------------------------------------
if [ ! -s "$BASE/rapports/deploiements.log" ]; then
  first=$(git_u -C "$APP" rev-parse --short=12 HEAD)
  {
    echo "# date;sha;resultat  (journal fictif fourni par le setup)"
    for j in 20 17 15 12 9 8 6 3 1; do
      d=$(date -d "$j days ago 10:$((RANDOM % 60)):00" -Is)
      res=ok; [ "$j" -eq 9 ] && res=ko
      echo "$d;$first;$res"
    done
  } > "$BASE/rapports/deploiements.log"
fi

chown -R "$LAB_USER:$LAB_USER" "$BASE"
# les données Gitea/PostgreSQL/registre appartiennent aux conteneurs
chown -R 1000:1000 "$BASE/forge/gitea" 2>/dev/null || true

cat <<EOF

== lab-ops prêt ==
  Gitea      : $GITEA_URL  ($LAB_USER / $GITEA_PASS)
  API        : jeton dans $BASE/.gitea-token
  Registre   : $REG  ($REG_USER / $REG_PASS), docker login fait
  Runner     : docker compose -f $BASE/forge/compose.yaml ps
  Dépôts     : $GITEA_URL/$LAB_USER/factura, .../factura-infra
  Clés       : $BASE/keys/{deploy,bg,ansible}
Pense à « newgrp docker » (ou reconnecte-toi) pour utiliser docker sans sudo.
EOF
