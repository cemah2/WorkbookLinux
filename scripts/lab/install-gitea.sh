#!/usr/bin/env bash
# install-gitea.sh — installe Gitea en binaire + systemd + SQLite sur lab-git
# (Ubuntu 24.04). Sans Docker : la forge doit exister avant le module 22.
# À lancer en sudo sur lab-git, depuis n'importe quel répertoire :
#   sudo bash ~/workbook/scripts/lab/install-gitea.sh        # installe
#   sudo bash ~/workbook/scripts/lab/install-gitea.sh lock   # après le web
# Idempotent : relançable pour mettre à jour le binaire (change GITEA_VERSION)
# ou pour réparer les droits ; il ne touche jamais à un app.ini existant.
#
# Ce qu'il fait, dans l'ordre de la doc officielle
# (https://docs.gitea.com/installation/install-from-binary) :
#   1. paquets : git, git-lfs, gnupg, curl, xz-utils
#   2. utilisateur système git (home /home/git, shell bash)
#   3. téléchargement du binaire linux-amd64 depuis dl.gitea.com,
#      vérification du sha256 ET de la signature GPG (clé Teabot)
#   4. /var/lib/gitea/{custom,data,log} (750, git:git), /etc/gitea (770)
#   5. app.ini minimal si absent (SQLite, LFS, URL du lab, SSH système)
#   6. unité systemd gitea.service (celle du dépôt Gitea, contrib/systemd)
#   7. enable --now, test de /api/healthz
set -euo pipefail

# --- Variables (surchargeables : GITEA_VERSION=1.27.3 sudo -E bash ...) ---
GITEA_VERSION="${GITEA_VERSION:-1.27.3}"     # cf. https://dl.gitea.com/gitea/
GITEA_DOMAIN="${GITEA_DOMAIN:-lab-git.lab.local}"
GITEA_HTTP_PORT="${GITEA_HTTP_PORT:-3000}"
GITEA_SSH_PORT="${GITEA_SSH_PORT:-22}"       # le sshd du système, pas Gitea
GITEA_USER="${GITEA_USER:-git}"
GITEA_HOME="/home/$GITEA_USER"
GITEA_WORK="/var/lib/gitea"
GITEA_ETC="/etc/gitea"
GITEA_BIN="/usr/local/bin/gitea"
GITEA_BASE_URL="https://dl.gitea.com/gitea/$GITEA_VERSION"
GITEA_GPG_FPR="7C9E68152594688862D62AF62D9AE806EC1592E2"   # Teabot

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERREUR:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "lance-moi avec sudo"
[ "$(uname -m)" = "x86_64" ] || die "binaire linux-amd64 : x86_64 attendu"

# ---------------------------------------------------------------------
# Post-installation : « lock » resserre les droits et ferme l'inscription
# ---------------------------------------------------------------------
if [ "${1:-}" = "lock" ]; then
  [ -f "$GITEA_ETC/app.ini" ] || die "pas d'app.ini : installe d'abord"
  info "verrouillage post-installation"
  sed -i 's/^DISABLE_REGISTRATION *=.*/DISABLE_REGISTRATION   = true/' \
    "$GITEA_ETC/app.ini"
  grep -q '^DISABLE_REGISTRATION' "$GITEA_ETC/app.ini" \
    || printf '\n[service]\nDISABLE_REGISTRATION = true\n' \
       >> "$GITEA_ETC/app.ini"
  chmod 750 "$GITEA_ETC"
  chmod 640 "$GITEA_ETC/app.ini"
  systemctl restart gitea
  echo "   inscription fermée, $GITEA_ETC en 750, app.ini en 640"
  exit 0
fi

# ---------------------------------------------------------------------
# 1. Paquets
# ---------------------------------------------------------------------
info "paquets"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q git git-lfs gnupg curl xz-utils ca-certificates

# ---------------------------------------------------------------------
# 2. Utilisateur système git
# ---------------------------------------------------------------------
if id "$GITEA_USER" >/dev/null 2>&1; then
  info "utilisateur $GITEA_USER déjà présent"
else
  info "création de l'utilisateur système $GITEA_USER"
  adduser --system --shell /bin/bash --gecos 'Git Version Control' \
    --group --disabled-password --home "$GITEA_HOME" "$GITEA_USER"
fi

# ---------------------------------------------------------------------
# 3. Binaire : téléchargement + sha256 + signature GPG
# ---------------------------------------------------------------------
current="$("$GITEA_BIN" --version 2>/dev/null | awk '{print $3}' || true)"
if [ "$current" = "$GITEA_VERSION" ]; then
  info "gitea $GITEA_VERSION déjà installé"
else
  info "téléchargement de gitea $GITEA_VERSION (linux-amd64)"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  f="gitea-$GITEA_VERSION-linux-amd64"
  ( cd "$tmp"
    curl -fsSLO "$GITEA_BASE_URL/$f"
    curl -fsSLO "$GITEA_BASE_URL/$f.sha256"
    curl -fsSLO "$GITEA_BASE_URL/$f.asc"
    info "vérification sha256"
    sha256sum -c "$f.sha256"
    info "vérification de la signature GPG (Teabot)"
    export GNUPGHOME="$tmp/gnupg"; mkdir -m 700 "$GNUPGHOME"
    gpg --batch --keyserver hkps://keys.openpgp.org \
      --recv-keys "$GITEA_GPG_FPR" >/dev/null 2>&1 \
      || echo "  (serveur de clés injoignable : signature non vérifiée," \
              "sha256 OK)"
    if gpg --batch --list-keys "$GITEA_GPG_FPR" >/dev/null 2>&1; then
      gpg --batch --verify "$f.asc" "$f" 2>&1 | grep -q 'Good signature' \
        || die "signature GPG invalide pour $f"
      echo "  signature OK"
    fi
  )
  if [ -n "$current" ]; then
    info "arrêt de gitea pour remplacer $current par $GITEA_VERSION"
    systemctl stop gitea 2>/dev/null || true
    cp -a "$GITEA_BIN" "$GITEA_BIN.$current"     # retour arrière possible
  fi
  install -m 755 -o root -g root "$tmp/$f" "$GITEA_BIN"
  "$GITEA_BIN" --version
fi

# ---------------------------------------------------------------------
# 4. Arborescence et droits (idempotent : on les réapplique)
# ---------------------------------------------------------------------
info "arborescence $GITEA_WORK et $GITEA_ETC"
install -d -m 750 -o "$GITEA_USER" -g "$GITEA_USER" \
  "$GITEA_WORK" "$GITEA_WORK/custom" "$GITEA_WORK/data" "$GITEA_WORK/log"
chown -R "$GITEA_USER:$GITEA_USER" "$GITEA_WORK"
install -d -m 770 -o root -g "$GITEA_USER" "$GITEA_ETC"

# ---------------------------------------------------------------------
# 5. app.ini minimal (jamais écrasé s'il existe déjà)
# ---------------------------------------------------------------------
if [ -f "$GITEA_ETC/app.ini" ]; then
  info "$GITEA_ETC/app.ini existe : conservé tel quel"
else
  info "écriture de $GITEA_ETC/app.ini (SQLite, LFS, $GITEA_DOMAIN)"
  gen() { su -s /bin/bash "$GITEA_USER" -c "$GITEA_BIN generate secret $1"; }
  SECRET_KEY="$(gen SECRET_KEY)"
  INTERNAL_TOKEN="$(gen INTERNAL_TOKEN)"
  JWT_SECRET="$(gen JWT_SECRET)"
  LFS_JWT_SECRET="$(gen LFS_JWT_SECRET)"
  cat > "$GITEA_ETC/app.ini" <<EOF
; app.ini — Gitea sur lab-git (workbook Linux/DevOps, chapitre 0.8)
; Généré par install-gitea.sh. L'installateur web complète ce fichier
; au premier démarrage ; ensuite : DISABLE_REGISTRATION = true.
APP_NAME = Forge du lab
RUN_USER = $GITEA_USER
RUN_MODE = prod
WORK_PATH = $GITEA_WORK

[server]
PROTOCOL         = http
DOMAIN           = $GITEA_DOMAIN
HTTP_ADDR        = 0.0.0.0
HTTP_PORT        = $GITEA_HTTP_PORT
ROOT_URL         = http://$GITEA_DOMAIN:$GITEA_HTTP_PORT/
SSH_DOMAIN       = $GITEA_DOMAIN
SSH_PORT         = $GITEA_SSH_PORT
START_SSH_SERVER = false
LFS_START_SERVER = true
LFS_JWT_SECRET   = $LFS_JWT_SECRET
OFFLINE_MODE     = true
APP_DATA_PATH    = $GITEA_WORK/data

[database]
DB_TYPE = sqlite3
PATH    = $GITEA_WORK/data/gitea.db

[repository]
ROOT = $GITEA_WORK/data/gitea-repositories

[lfs]
PATH = $GITEA_WORK/data/lfs

[service]
DISABLE_REGISTRATION   = false
REQUIRE_SIGNIN_VIEW    = false
DEFAULT_KEEP_EMAIL_PRIVATE = true

[security]
INSTALL_LOCK   = false
SECRET_KEY     = $SECRET_KEY
INTERNAL_TOKEN = $INTERNAL_TOKEN

[oauth2]
JWT_SECRET = $JWT_SECRET

[actions]
ENABLED = true

[log]
MODE      = file
LEVEL     = Info
ROOT_PATH = $GITEA_WORK/log
EOF
  chown root:"$GITEA_USER" "$GITEA_ETC/app.ini"
  chmod 660 "$GITEA_ETC/app.ini"     # l'installateur web doit pouvoir écrire
fi

# ---------------------------------------------------------------------
# 6. Unité systemd (contenu de contrib/systemd/gitea.service, élagué)
# ---------------------------------------------------------------------
info "/etc/systemd/system/gitea.service"
cat > /etc/systemd/system/gitea.service <<EOF
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target

[Service]
# LimitNOFILE=524288:524288
RestartSec=2s
Type=simple
User=$GITEA_USER
Group=$GITEA_USER
WorkingDirectory=$GITEA_WORK/
ExecStart=$GITEA_BIN web --config $GITEA_ETC/app.ini
Restart=always
Environment=USER=$GITEA_USER HOME=$GITEA_HOME GITEA_WORK_DIR=$GITEA_WORK
# Pour écouter sous 1024 (port 80) sans root :
#CapabilityBoundingSet=CAP_NET_BIND_SERVICE
#AmbientCapabilities=CAP_NET_BIND_SERVICE
#PrivateUsers=false

[Install]
WantedBy=multi-user.target
EOF

# ---------------------------------------------------------------------
# 7. Démarrage et contrôle
# ---------------------------------------------------------------------
systemctl daemon-reload
systemctl enable --now gitea >/dev/null
systemctl restart gitea
for _i in $(seq 1 20); do
  if curl -fs "http://127.0.0.1:$GITEA_HTTP_PORT/api/healthz" \
       >/dev/null 2>&1; then break; fi
  sleep 1
done
curl -fs "http://127.0.0.1:$GITEA_HTTP_PORT/api/healthz" >/dev/null \
  || die "gitea ne répond pas : journalctl -u gitea -n 50"

echo
ver="$("$GITEA_BIN" --version | awk '{print $3}')"
echo "== Gitea $ver sur $(hostname -s) =="
echo "   service   : $(systemctl is-active gitea)"
echo "   URL       : http://$GITEA_DOMAIN:$GITEA_HTTP_PORT/"
echo "   données   : $GITEA_WORK   config : $GITEA_ETC/app.ini"
if grep -q '^INSTALL_LOCK *= *false' "$GITEA_ETC/app.ini"; then
  echo
  echo "Étape suivante : ouvre l'URL ci-dessus, termine l'installation"
  echo "(compte administrateur mathieu), puis :"
  echo "  sudo bash $0 lock    # verrouille app.ini et coupe l'inscription"
fi
