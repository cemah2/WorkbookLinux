#!/usr/bin/env bash
# setup_P3.sh — prépare le terrain du Projet C « Une semaine d'astreinte »
#
# À lancer avec sudo sur CHAQUE VM du lab. Le rôle est déduit du hostname
# (lab-web, lab-db, lab-ops) ; on peut le forcer : --role web|db|ops|all.
# Idempotent : relançable sans effet de bord.
#
#   web : nginx + TLS (CA de lab), factura-api.service (port 8081),
#         compte deploy + « CI » locale, ufw, bac à sable ~/astreinte
#   db  : PostgreSQL 16 (base factura), Redis
#   ops : rsyslog récepteur, sauvegarde (timer), exports, NFS local,
#         dépôt Git, conteneur Docker factura-worker (si Docker présent)
#
# Chaque rôle est autonome : un scénario se joue sur une seule VM.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

ROLE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --role) ROLE="$2"; shift 2 ;;
    *) echo "option inconnue : $1" >&2; exit 2 ;;
  esac
done
if [ -z "$ROLE" ]; then
  case "$(hostname -s)" in
    lab-web) ROLE=web ;;
    lab-db)  ROLE=db ;;
    lab-ops) ROLE=ops ;;
    *) echo "hostname inconnu : précise --role web|db|ops|all" >&2; exit 2 ;;
  esac
fi

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
BASE="$LAB_HOME/astreinte"
ICI="$(cd "$(dirname "$0")" && pwd)"
SAUV=/root/.breakfix-backup
DB_PASS='F4ctura-Pr0d-2026!'
REDIS_PASS='F4ctura-Redis-2026'

echo "== Préparation du Projet C (rôle : $ROLE) =="
mkdir -p "$SAUV"
export DEBIAN_FRONTEND=noninteractive

apt_install() {
  local manque=()
  for p in "$@"; do
    dpkg -s "$p" >/dev/null 2>&1 || manque+=("$p")
  done
  if [ ${#manque[@]} -gt 0 ]; then
    echo "   installation : ${manque[*]}"
    apt-get update -qq
    apt-get install -y -qq "${manque[@]}" >/dev/null
  fi
}

a_systemd() { [ -d /run/systemd/system ]; }

# ---------------------------------------------------------------------
# 0. Commun à tous les rôles
# ---------------------------------------------------------------------
commun() {
  echo "-- commun"
  for l in "10.10.10.10 lab-adm" \
           "10.10.10.11 lab-web factura.lab.local docs.factura.lab.local" \
           "10.10.10.12 lab-db" "10.10.10.13 lab-rhel" \
           "10.10.10.14 lab-ops"; do
    nom=$(echo "$l" | awk '{print $2}')
    grep -qsE "[[:space:]]$nom([[:space:]]|$)" /etc/hosts \
      || printf '%s\n' "$l" >> /etc/hosts
  done

  mkdir -p "$BASE"/{journal,rapports,communication,preuves,modeles}
  cp -f "$ICI/rapport-journee.md" "$ICI/postmortem.md" "$BASE/modeles/" \
    2>/dev/null || true
  chown -R "$LAB_USER:$LAB_USER" "$BASE"

  mkdir -p /var/lib/factura
  cat /proc/sys/kernel/random/boot_id > /var/lib/factura/boot_id.setup
  apt_install curl openssl python3 nftables
}

# ---------------------------------------------------------------------
# 1. Rôle web : nginx, TLS, factura-api, deploy, ufw
# ---------------------------------------------------------------------
role_web() {
  echo "-- rôle web"
  apt_install nginx openssh-server ufw
  groupadd -f factura
  getent passwd factura >/dev/null \
    || useradd -r -g factura -d /srv/factura -s /usr/sbin/nologin factura
  getent passwd deploy >/dev/null \
    || useradd -m -s /bin/bash -G factura deploy

  mkdir -p /opt/factura/bin /etc/factura /srv/factura/{www,exports} \
           /var/log/factura /var/lib/factura-ci
  chown factura:factura /var/log/factura /srv/factura/exports

  # --- CA de lab et certificat -----------------------------------------
  local ssl=/etc/ssl/factura
  mkdir -p "$ssl"; chmod 0755 "$ssl"
  if [ ! -f "$ssl/ca.key" ]; then
    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
      -keyout "$ssl/ca.key" -out "$ssl/ca.crt" \
      -subj "/O=Factura Lab/CN=Factura Lab CA" 2>/dev/null
    chmod 0600 "$ssl/ca.key"
  fi
  cat > "$ssl/ca.cnf" <<EOF
[ca]
default_ca = lab
[lab]
dir = $ssl
database = $ssl/index.txt
new_certs_dir = $ssl
serial = $ssl/serial
certificate = $ssl/ca.crt
private_key = $ssl/ca.key
default_md = sha256
default_days = 90
policy = pol
copy_extensions = copy
x509_extensions = ext
unique_subject = no
[pol]
commonName = supplied
organizationName = optional
[ext]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF
  [ -f "$ssl/index.txt" ] || touch "$ssl/index.txt"
  [ -f "$ssl/serial" ] || echo 1000 > "$ssl/serial"
  cat > "$ssl/req.cnf" <<'EOF'
[req]
distinguished_name = dn
req_extensions = ext
prompt = no
[dn]
O = Factura Lab
CN = factura.lab.local
[ext]
subjectAltName = DNS:factura.lab.local, DNS:docs.factura.lab.local, \
DNS:lab-web, IP:10.10.10.11, IP:127.0.0.1
EOF
  if [ ! -f "$ssl/factura.lab.local.key" ]; then
    openssl req -new -newkey rsa:2048 -nodes -config "$ssl/req.cnf" \
      -keyout "$ssl/factura.lab.local.key" \
      -out "$ssl/factura.lab.local.csr" 2>/dev/null
    chmod 0640 "$ssl/factura.lab.local.key"
    chgrp www-data "$ssl/factura.lab.local.key"
  fi
  if ! openssl x509 -in "$ssl/factura.lab.local.crt" -noout \
       -checkend 604800 >/dev/null 2>&1; then
    openssl ca -batch -config "$ssl/ca.cnf" -notext \
      -in "$ssl/factura.lab.local.csr" \
      -out "$ssl/factura.lab.local.crt" >/dev/null 2>&1
  fi
  cp -f "$ssl/ca.crt" /usr/local/share/ca-certificates/factura-lab-ca.crt
  update-ca-certificates >/dev/null 2>&1 || true

  # --- l'API ------------------------------------------------------------
  cat > /opt/factura/bin/factura-api.py <<'PYEOF'
#!/usr/bin/env python3
"""factura-api — API de démonstration de la plateforme Factura.

Lit sa configuration dans FACTURA_ENV_FILE (défaut /etc/factura/api.env)
et refuse de démarrer si ce fichier est modifiable par tout le monde.

Routes : /sante /version /factures /export /
"""
import json
import os
import socket
import stat
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ENVF = os.environ.get("FACTURA_ENV_FILE", "/etc/factura/api.env")
CONF = {}


def charge_env():
    try:
        st = os.stat(ENVF)
    except OSError as err:
        sys.stderr.write("impossible de lire %s : %s\n" % (ENVF, err))
        sys.exit(78)
    if st.st_mode & stat.S_IWOTH:
        sys.stderr.write(
            "refus de charger %s : permissions trop larges (%s), "
            "un fichier de secrets ne doit pas etre modifiable par tous\n"
            % (ENVF, oct(st.st_mode & 0o777)))
        sys.exit(78)
    with open(ENVF) as f:
        for ligne in f:
            ligne = ligne.strip()
            if not ligne or ligne.startswith("#") or "=" not in ligne:
                continue
            k, v = ligne.split("=", 1)
            CONF[k.strip()] = v.strip().strip('"').strip("'")


def teste_dependance(hote, port):
    """Rend (resolution, tcp) sous forme de chaines lisibles."""
    try:
        infos = socket.getaddrinfo(hote, port, socket.AF_INET,
                                   socket.SOCK_STREAM)
        adr = infos[0][4]
        res = "ok (%s)" % adr[0]
    except socket.gaierror as err:
        return ('echec: could not translate host name "%s" to address: %s'
                % (hote, err.strerror or err)), "non teste"
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    try:
        s.connect(adr)
        tcp = "ok"
    except OSError as err:
        tcp = "echec: %s" % (err.strerror or err)
    finally:
        s.close()
    return res, tcp


FACTURES = [
    {"id": 1041, "client": "Boulangerie Martin", "montant": 1240.50,
     "emise": "2026-09-02", "payee": True},
    {"id": 1042, "client": "Garage Lopez", "montant": 3890.00,
     "emise": "2026-09-05", "payee": False},
    {"id": 1043, "client": "Cabinet Durand", "montant": 760.00,
     "emise": "2026-09-11", "payee": False},
]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "factura-api/" + os.environ.get("APP_VERSION", "0")

    def log_message(self, fmt, *args):
        sys.stdout.write("%s %s %s\n" % (time.strftime("%Y-%m-%dT%H:%M:%S"),
                                         self.address_string(),
                                         fmt % args))
        sys.stdout.flush()

    def _rep(self, code, corps, ctype="application/json"):
        data = corps.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        chemin = self.path.split("?")[0]
        version = os.environ.get("APP_VERSION", CONF.get("APP_VERSION", "?"))
        if chemin == "/sante":
            dns_db, tcp_db = teste_dependance(CONF.get("DB_HOST", "lab-db"),
                                              int(CONF.get("DB_PORT", 5432)))
            dns_rd, tcp_rd = teste_dependance(
                CONF.get("REDIS_HOST", "lab-db"),
                int(CONF.get("REDIS_PORT", 6379)))
            etat = {"version": version, "pid": os.getpid(),
                    "db_resolution": dns_db, "db_tcp": tcp_db,
                    "redis_resolution": dns_rd, "redis_tcp": tcp_rd}
            code = 200 if dns_db.startswith("ok") else 503
            self._rep(code, json.dumps(etat, ensure_ascii=False) + "\n")
        elif chemin == "/version":
            self._rep(200, json.dumps({"version": version}) + "\n")
        elif chemin == "/factures":
            self._rep(200, json.dumps(FACTURES) + "\n")
        elif chemin == "/export":
            lignes = ["id;client;montant;emise;payee"]
            for f in FACTURES:
                lignes.append("%d;%s;%.2f;%s;%s" % (
                    f["id"], f["client"], f["montant"], f["emise"],
                    "oui" if f["payee"] else "non"))
            self._rep(200, "\n".join(lignes) + "\n", "text/csv")
        elif chemin == "/":
            self._rep(200, "<h1>Factura</h1><p>API v%s</p>\n" % version,
                      "text/html")
        else:
            self._rep(404, '{"erreur": "route inconnue"}\n')


def main():
    charge_env()
    port = int(os.environ.get("PORT", CONF.get("PORT", "8081")))
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    sys.stdout.write("factura-api v%s en ecoute sur 127.0.0.1:%d\n"
                     % (os.environ.get("APP_VERSION",
                                       CONF.get("APP_VERSION", "?")), port))
    sys.stdout.flush()
    srv.serve_forever()


if __name__ == "__main__":
    main()
PYEOF
  chmod 0755 /opt/factura/bin/factura-api.py

  if [ ! -f /etc/factura/api.env ]; then
    cat > /etc/factura/api.env <<EOF
# Configuration de factura-api (secrets : ne pas versionner)
PORT=8081
APP_VERSION=2.3.1
DB_HOST=lab-db
DB_PORT=5432
DB_NAME=factura
DB_USER=factura
DB_PASSWORD=$DB_PASS
REDIS_HOST=lab-db
REDIS_PORT=6379
REDIS_PASSWORD=$REDIS_PASS
EOF
  fi
  chown root:factura /etc/factura/api.env
  chmod 0640 /etc/factura/api.env
  chmod 0755 /etc/factura

  cat > /etc/systemd/system/factura-api.service <<'EOF'
[Unit]
Description=Factura API (demonstration)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=factura
Group=factura
EnvironmentFile=/etc/factura/api.env
Environment=FACTURA_ENV_FILE=/etc/factura/api.env
ExecStart=/usr/bin/python3 /opt/factura/bin/factura-api.py
Restart=on-failure
RestartSec=3
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

  # --- nginx ------------------------------------------------------------
  mkdir -p /etc/nginx/factura
  cat > /etc/nginx/factura/upstream.conf <<'EOF'
# Factura : définitions partagées (upstream, limitation de débit)
upstream factura_api {
    server 127.0.0.1:8081;
    keepalive 16;
}
limit_req_zone $binary_remote_addr zone=factura_req:10m rate=30r/s;
EOF
  if ! grep -q '/etc/nginx/factura/' /etc/nginx/nginx.conf; then
    cp -a /etc/nginx/nginx.conf "$SAUV/nginx.conf.avant-P3"
    sed -i 's|^\(\s*\)include /etc/nginx/conf.d/\*.conf;|\1include /etc/nginx/factura/*.conf;\n\1include /etc/nginx/conf.d/*.conf;|' \
      /etc/nginx/nginx.conf
  fi
  cat > /etc/nginx/sites-available/factura.conf <<'EOF'
# Factura — frontal principal
server {
    listen 80;
    server_name factura.lab.local lab-web;
    return 301 https://factura.lab.local$request_uri;
}

server {
    listen 443 ssl;
    server_name factura.lab.local lab-web;

    ssl_certificate     /etc/ssl/factura/factura.lab.local.crt;
    ssl_certificate_key /etc/ssl/factura/factura.lab.local.key;

    access_log /var/log/nginx/factura.access.log;
    error_log  /var/log/nginx/factura.error.log;

    location / {
        limit_req zone=factura_req burst=50 nodelay;
        proxy_pass http://factura_api;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_connect_timeout 2s;
        proxy_read_timeout 10s;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/factura.conf \
         /etc/nginx/sites-enabled/factura.conf
  rm -f /etc/nginx/sites-enabled/default

  # --- deploy + CI locale -------------------------------------------------
  if [ ! -f /var/lib/factura-ci/id_ed25519 ]; then
    ssh-keygen -q -t ed25519 -N "" -C "ci-factura@lab-ops" \
      -f /var/lib/factura-ci/id_ed25519
  fi
  chmod 0700 /var/lib/factura-ci
  install -d -m 0700 -o deploy -g deploy /home/deploy/.ssh
  if ! grep -qsF "$(cut -d' ' -f2 /var/lib/factura-ci/id_ed25519.pub)" \
       /home/deploy/.ssh/authorized_keys; then
    cat /var/lib/factura-ci/id_ed25519.pub >> /home/deploy/.ssh/authorized_keys
  fi
  chown deploy:deploy /home/deploy/.ssh/authorized_keys
  chmod 0600 /home/deploy/.ssh/authorized_keys
  chmod 0755 /home/deploy
  cat > /etc/sudoers.d/deploy <<'EOF'
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart factura-api, \
  /usr/bin/systemctl restart factura-api.service
EOF
  chmod 0440 /etc/sudoers.d/deploy
  cat > /usr/local/bin/factura-deploy <<'EOF'
#!/usr/bin/env bash
# factura-deploy — simule le job de déploiement de la CI (lab-ops).
# La CI se connecte en SSH avec la clé de service et redémarre l'API.
set -uo pipefail
CLE=/var/lib/factura-ci/id_ed25519
echo "[ci] connexion deploy@lab-web avec $CLE"
if ssh -i "$CLE" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
     -o ConnectTimeout=5 deploy@127.0.0.1 \
     'sudo systemctl restart factura-api && systemctl is-active factura-api'
then
  echo "[ci] déploiement OK"
else
  echo "[ci] ECHEC du déploiement (code $?)" >&2
  exit 1
fi
EOF
  chmod 0755 /usr/local/bin/factura-deploy

  # --- pare-feu ----------------------------------------------------------
  if command -v ufw >/dev/null 2>&1 && a_systemd; then
    ufw allow 22/tcp  >/dev/null 2>&1 || true
    ufw allow 80/tcp  >/dev/null 2>&1 || true
    ufw allow 443/tcp >/dev/null 2>&1 || true
    ufw --force enable >/dev/null 2>&1 || true
  fi

  # --- horloge : NTP actif (scénario PC.4.1) -------------------------------
  if a_systemd; then
    timedatectl set-ntp true 2>/dev/null || true
    systemctl daemon-reload
    systemctl enable --now factura-api.service >/dev/null 2>&1 || true
    systemctl restart factura-api.service
    nginx -t >/dev/null 2>&1 && systemctl enable --now nginx >/dev/null 2>&1
    systemctl reload nginx 2>/dev/null || systemctl restart nginx
    systemctl enable --now ssh >/dev/null 2>&1 || true
  fi
  echo "   factura-api : $(curl -s http://127.0.0.1:8081/version || echo KO)"
  echo "   nginx       : $(curl -s -o /dev/null -w '%{http_code}' \
                          https://factura.lab.local/version \
                          --resolve factura.lab.local:443:127.0.0.1 \
                          || echo KO)"
}

# ---------------------------------------------------------------------
# 2. Rôle db : PostgreSQL 16 + Redis
# ---------------------------------------------------------------------
role_db() {
  echo "-- rôle db"
  apt_install postgresql postgresql-client redis-server
  local pgconf=/etc/postgresql/16/main
  [ -d "$pgconf" ] || { echo "PostgreSQL 16 attendu dans $pgconf" >&2; exit 1; }

  cat > "$pgconf/conf.d/10-factura.conf" <<'EOF'
# Factura — réglages de base (géré par setup_P3.sh)
listen_addresses = '*'
max_connections = 100
log_line_prefix = '%m [%p] %u@%d '
log_min_duration_statement = 2000
EOF
  if ! grep -qs '10.10.10.0/24' "$pgconf/pg_hba.conf"; then
    printf 'host    all    all    10.10.10.0/24    scram-sha-256\n' \
      >> "$pgconf/pg_hba.conf"
  fi
  if a_systemd; then
    systemctl enable --now postgresql >/dev/null 2>&1 || true
    systemctl restart postgresql@16-main.service
  fi
  sudo -u postgres psql -v ON_ERROR_STOP=1 -q <<EOF
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'factura') THEN
    CREATE ROLE factura LOGIN PASSWORD '$DB_PASS';
  END IF;
END \$\$;
SELECT 'CREATE DATABASE factura OWNER factura'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'factura')\gexec
EOF
  sudo -u postgres psql -v ON_ERROR_STOP=1 -q -d factura <<'EOF'
CREATE TABLE IF NOT EXISTS clients (
  id serial PRIMARY KEY, nom text NOT NULL, email text);
CREATE TABLE IF NOT EXISTS factures (
  id serial PRIMARY KEY, client_id int REFERENCES clients(id),
  montant numeric(10,2) NOT NULL, emise date NOT NULL DEFAULT current_date,
  payee boolean NOT NULL DEFAULT false);
INSERT INTO clients (nom, email)
SELECT 'Client ' || g, 'client' || g || '@exemple.fr'
FROM generate_series(1, 50) g
WHERE NOT EXISTS (SELECT 1 FROM clients);
INSERT INTO factures (client_id, montant, emise, payee)
SELECT (g % 50) + 1, (random() * 5000)::numeric(10,2),
       current_date - (g % 400), (g % 3 = 0)
FROM generate_series(1, 2000) g
WHERE NOT EXISTS (SELECT 1 FROM factures);
ALTER TABLE clients OWNER TO factura;
ALTER TABLE factures OWNER TO factura;
EOF

  # Redis : accessible depuis lab-web, mot de passe
  if [ -f /etc/redis/redis.conf ]; then
    [ -f "$SAUV/redis.conf.avant-P3" ] \
      || cp -a /etc/redis/redis.conf "$SAUV/redis.conf.avant-P3"
    sed -i -E 's/^bind .*/bind 0.0.0.0 -::1/' /etc/redis/redis.conf
    sed -i -E 's/^protected-mode .*/protected-mode yes/' /etc/redis/redis.conf
    grep -qE '^requirepass ' /etc/redis/redis.conf \
      && sed -i -E "s/^requirepass .*/requirepass $REDIS_PASS/" \
           /etc/redis/redis.conf \
      || printf 'requirepass %s\n' "$REDIS_PASS" >> /etc/redis/redis.conf
    a_systemd && systemctl enable --now redis-server >/dev/null 2>&1 \
      && systemctl restart redis-server
  fi
  echo "   postgresql : $(sudo -u postgres psql -tAc 'select version()' \
                          | cut -d' ' -f1-2)"
  echo "   redis      : $(redis-cli -a "$REDIS_PASS" --no-auth-warning ping \
                          2>/dev/null || echo KO)"
}

# ---------------------------------------------------------------------
# 3. Rôle ops : rsyslog, sauvegarde, exports, NFS, Git, Docker
# ---------------------------------------------------------------------
role_ops() {
  echo "-- rôle ops"
  apt_install rsyslog git nfs-kernel-server nfs-common postgresql-client
  mkdir -p /srv/factura/{data,exports} /var/backups/factura /var/log/remote

  # --- rsyslog récepteur ---------------------------------------------------
  cat > /etc/rsyslog.d/10-reception.conf <<'EOF'
# Réception des journaux des autres VM du lab (Factura)
module(load="imtcp")
input(type="imtcp" port="514")
template(name="ParHote" type="string"
         string="/var/log/remote/%HOSTNAME%/syslog.log")
if $fromhost-ip != "127.0.0.1" then { action(type="omfile"
    dynaFile="ParHote") stop }
EOF
  a_systemd && systemctl restart rsyslog 2>/dev/null || true

  # --- données et exports ---------------------------------------------------
  if [ "$(ls /srv/factura/data 2>/dev/null | wc -l)" -lt 40 ]; then
    for i in $(seq 1 40); do
      printf 'facture %04d;client %d;%d.00\n' "$i" "$((i % 7))" \
        "$((i * 37))" > "/srv/factura/data/facture-$(printf %04d "$i").txt"
    done
  fi
  chown -R "$LAB_USER:$LAB_USER" /srv/factura/exports

  # --- sauvegarde (timer) ---------------------------------------------------
  cat > /usr/local/sbin/factura-backup <<'EOF'
#!/usr/bin/env bash
# factura-backup — archive quotidienne des données Factura
# Conserve 7 archives dans /var/backups/factura.
set -euo pipefail
SRC=${FACTURA_SRC:-/srv/factura/data}
DEST=/var/backups/factura
ARCH="$DEST/factura-$(date +%Y%m%d-%H%M).tar.gz"
mkdir -p "$DEST"
tar -czf "$ARCH" -C "$(dirname "$SRC")" "$(basename "$SRC")"
NB=$(tar -tzf "$ARCH" | grep -c -v '/$')
[ "$NB" -gt 0 ] || { echo "archive vide : $ARCH" >&2; exit 1; }
ls -1t "$DEST"/factura-*.tar.gz | tail -n +8 | xargs -r rm -f
echo "Sauvegarde OK : $ARCH ($NB fichiers, $(du -h "$ARCH" | cut -f1))"
EOF
  chmod 0755 /usr/local/sbin/factura-backup
  cat > /etc/systemd/system/factura-backup.service <<'EOF'
[Unit]
Description=Sauvegarde quotidienne Factura

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/factura-backup
EOF
  cat > /etc/systemd/system/factura-backup.timer <<'EOF'
[Unit]
Description=Sauvegarde quotidienne Factura (02:00)

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

  # --- NFS local (archives) ---------------------------------------------------
  mkdir -p /srv/factura-nfs /mnt/archives
  [ "$(ls /srv/factura-nfs | wc -l)" -gt 0 ] \
    || for m in 2026-06 2026-07 2026-08; do
         echo "archive $m" > "/srv/factura-nfs/factures-$m.csv"; done
  grep -qs '/srv/factura-nfs' /etc/exports \
    || printf '/srv/factura-nfs 127.0.0.1(rw,sync,no_subtree_check) 10.10.10.0/24(rw,sync,no_subtree_check)\n' \
       >> /etc/exports
  local nfsline='127.0.0.1:/srv/factura-nfs /mnt/archives nfs defaults 0 0'
  grep -qs '/mnt/archives' /etc/fstab || printf '%s\n' "$nfsline" >> /etc/fstab
  if a_systemd; then
    systemctl enable --now nfs-kernel-server >/dev/null 2>&1 || true
    exportfs -ra 2>/dev/null || true
    mountpoint -q /mnt/archives || mount /mnt/archives 2>/dev/null \
      || echo "   (NFS : montage impossible, scénario PC.2.2 dégradé)"
  fi

  # --- dépôt Git -------------------------------------------------------------
  if [ ! -d /srv/git/factura.git ]; then
    mkdir -p /srv/git
    git init -q --bare --initial-branch=main /srv/git/factura.git
    local w; w=$(mktemp -d)
    git -C "$w" init -q --initial-branch=main
    git -C "$w" config user.email "julie@factura.lab.local"
    git -C "$w" config user.name "Julie"
    printf '# Factura\n\nAPI de facturation.\n' > "$w/README.md"
    printf 'PORT=8081\nDB_HOST=lab-db\nDB_PASSWORD=changez-moi\n' \
      > "$w/api.env.example"
    printf '#!/usr/bin/env bash\nssh deploy@lab-web sudo systemctl restart factura-api\n' \
      > "$w/deploy.sh"
    git -C "$w" add -A && git -C "$w" commit -qm "Import initial"
    git -C "$w" remote add origin /srv/git/factura.git
    git -C "$w" push -q origin main
    rm -rf "$w"
  fi
  chown -R "$LAB_USER:$LAB_USER" /srv/git
  if [ ! -d /srv/factura/src/.git ]; then
    sudo -u "$LAB_USER" git clone -q /srv/git/factura.git /srv/factura/src
    sudo -u "$LAB_USER" git -C /srv/factura/src config user.email \
      "julie@factura.lab.local"
    sudo -u "$LAB_USER" git -C /srv/factura/src config user.name "Julie"
  fi

  # --- conteneur factura-worker ---------------------------------------------
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    mkdir -p /srv/factura/worker
    cat > /srv/factura/worker/worker.sh <<'EOF'
#!/bin/sh
# factura-worker : traite les exports en attente (simulation)
i=0
while true; do
  i=$((i+1))
  echo "$(date +%H:%M:%S) traitement du lot $i"
  sleep 15
done
EOF
    cat > /srv/factura/worker/health.sh <<'EOF'
#!/bin/sh
# Sonde de santé : interroge la file de travail (simulation : 1,5 s)
sleep 1.5
exit 0
EOF
    chmod 0755 /srv/factura/worker/*.sh
    cat > /usr/local/sbin/factura-worker-run <<'EOF'
#!/usr/bin/env bash
# Lance le conteneur factura-worker (appelé par factura-worker.service)
set -euo pipefail
IMG=${FACTURA_IMAGE:-alpine:3.20}
docker image inspect "$IMG" >/dev/null 2>&1 || docker pull -q "$IMG"
docker rm -f factura-worker >/dev/null 2>&1 || true
exec docker run --rm --name factura-worker \
  -v /srv/factura/worker:/app:ro \
  --health-cmd "sh /app/health.sh" \
  --health-interval "${HC_INTERVAL:-10s}" \
  --health-timeout "${HC_TIMEOUT:-5s}" \
  --health-retries "${HC_RETRIES:-3}" \
  --health-start-period "${HC_START:-10s}" \
  "$IMG" sh /app/worker.sh
EOF
    chmod 0755 /usr/local/sbin/factura-worker-run
    cat > /etc/systemd/system/factura-worker.service <<'EOF'
[Unit]
Description=Factura worker (conteneur Docker)
After=docker.service
Requires=docker.service

[Service]
Type=simple
EnvironmentFile=-/etc/factura/worker.env
ExecStart=/usr/local/sbin/factura-worker-run
ExecStop=/usr/bin/docker stop factura-worker
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    mkdir -p /etc/factura
    [ -f /etc/factura/worker.env ] || cat > /etc/factura/worker.env <<'EOF'
# Paramètres du healthcheck du worker
HC_INTERVAL=10s
HC_TIMEOUT=5s
HC_RETRIES=3
HC_START=10s
EOF
    cat > /usr/local/sbin/factura-autoheal <<'EOF'
#!/usr/bin/env bash
# factura-autoheal — redémarre les conteneurs marqués « unhealthy »
set -uo pipefail
for c in $(docker ps -q --filter health=unhealthy); do
  nom=$(docker inspect -f '{{.Name}}' "$c" | tr -d /)
  echo "conteneur $nom unhealthy : redémarrage"
  docker restart "$c" >/dev/null
done
EOF
    chmod 0755 /usr/local/sbin/factura-autoheal
    cat > /etc/systemd/system/factura-autoheal.service <<'EOF'
[Unit]
Description=Redémarre les conteneurs unhealthy

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/factura-autoheal
EOF
    cat > /etc/systemd/system/factura-autoheal.timer <<'EOF'
[Unit]
Description=Autoheal des conteneurs (toutes les 30 s)

[Timer]
OnBootSec=1min
OnUnitActiveSec=30s
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
  else
    echo "   Docker absent : le scénario PC.4.4 ne sera pas jouable ici"
  fi

  if a_systemd; then
    systemctl daemon-reload
    systemctl enable --now factura-backup.timer >/dev/null 2>&1 || true
    if [ -f /etc/systemd/system/factura-worker.service ]; then
      systemctl enable --now factura-worker.service >/dev/null 2>&1 || true
      systemctl enable --now factura-autoheal.timer >/dev/null 2>&1 || true
    fi
  fi
  echo "   sauvegarde : $(/usr/local/sbin/factura-backup 2>&1 | tail -1)"
}

commun
case "$ROLE" in
  web) role_web ;;
  db)  role_db ;;
  ops) role_ops ;;
  all) role_web; role_db; role_ops ;;
  *) echo "rôle inconnu : $ROLE" >&2; exit 2 ;;
esac
echo "== Terminé. Bac à sable : $BASE =="
