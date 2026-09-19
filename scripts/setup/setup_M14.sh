#!/usr/bin/env bash
# setup_M14.sh — prépare le terrain du module 14 (SSH)
# À lancer avec sudo SUR CHAQUE VM du lab. Idempotent.
# Le script détecte le nom d'hôte et n'applique que la partie qui le concerne.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab14"
SAUV=/root/.m12-backup
HOTE="$(hostname -s)"

echo "== Préparation du module 14 =="
echo "   machine     : $HOTE"
echo "   utilisateur : $LAB_USER"

# ---------------------------------------------------------------------
# 0. Outils du module
# ---------------------------------------------------------------------
for p in ssh sshd ssh-keygen ssh-keyscan ssh-add ssh-agent ssh-copy-id; do
  command -v "$p" >/dev/null 2>&1 || echo "  note : $p absent (voir §14.1)"
done
command -v ssh-audit >/dev/null 2>&1 || \
  echo "  note : ssh-audit absent — apt install ssh-audit (L14.3)"

# ---------------------------------------------------------------------
# 1. Sauvegarde de /etc/ssh, une seule fois
# ---------------------------------------------------------------------
mkdir -p "$SAUV"
if [ ! -d "$SAUV/etc-ssh" ] && [ -d /etc/ssh ]; then
  cp -a /etc/ssh "$SAUV/etc-ssh"
  echo "   /etc/ssh sauvegardé dans $SAUV/etc-ssh"
fi

# ---------------------------------------------------------------------
# 2. Bac à sable de l'apprenant (toutes les machines)
# ---------------------------------------------------------------------
mkdir -p "$BASE"/{bin,conf,rapports}
install -d -o "$LAB_USER" -g "$LAB_USER" -m 700 "$LAB_HOME/.ssh"

# script utilisé par E14.12 (exécution distante d'un script local)
cat > "$BASE/bin/etat.sh" <<'EOF'
#!/usr/bin/env bash
# etat.sh [--court|--long] — état résumé de la machine
set -euo pipefail
mode="${1:---court}"
printf 'hote     : %s\n' "$(hostname -f 2>/dev/null || hostname)"
printf 'uptime   : %s\n' "$(uptime -p 2>/dev/null || uptime)"
case "$mode" in
  --court) : ;;
  --long)
    printf 'noyau    : %s\n' "$(uname -r)"
    printf 'charge   : %s\n' "$(cut -d' ' -f1-3 /proc/loadavg)"
    printf 'memoire  : %s\n' "$(free -h | awk '/^Mem:/{print $3" / "$2}')"
    printf 'sshd     : %s\n' "$(systemctl is-active ssh 2>/dev/null \
                                || systemctl is-active sshd 2>/dev/null \
                                || echo inconnu)"
    ;;
  *) echo "usage: etat.sh [--court|--long]" >&2; exit 64 ;;
esac
EOF
chmod 755 "$BASE/bin/etat.sh"

# ---------------------------------------------------------------------
# 3. La vieille clé RSA 2048 sans passphrase, à faire tourner en L14.1
# ---------------------------------------------------------------------
if [ ! -f "$LAB_HOME/.ssh/id_rsa" ]; then
  runuser -u "$LAB_USER" -- ssh-keygen -q -t rsa -b 2048 -N '' \
    -C "$LAB_USER@$HOTE-heritee" -f "$LAB_HOME/.ssh/id_rsa"
  echo "   clé RSA 2048 héritée créée (sans passphrase : c'est voulu)"
fi
# elle est réellement utilisable : on l'autorise sur la machine courante
touch "$LAB_HOME/.ssh/authorized_keys"
if ! grep -qxF "$(cat "$LAB_HOME/.ssh/id_rsa.pub")" \
     "$LAB_HOME/.ssh/authorized_keys" 2>/dev/null; then
  cat "$LAB_HOME/.ssh/id_rsa.pub" >> "$LAB_HOME/.ssh/authorized_keys"
fi
chown -R "$LAB_USER":"$LAB_USER" "$LAB_HOME/.ssh"
chmod 700 "$LAB_HOME/.ssh"
chmod 600 "$LAB_HOME/.ssh/authorized_keys" "$LAB_HOME/.ssh/id_rsa"
chmod 644 "$LAB_HOME/.ssh/id_rsa.pub"
chmod go-w "$LAB_HOME"

# ---------------------------------------------------------------------
# 4. Faux services (rôle par rôle)
# ---------------------------------------------------------------------
mkdir -p /opt/lab14

# --- 4a. faux serveur de base de données, écoute 5432, répond une bannière
faux_pg() {
  cat > /opt/lab14/faux-pg.py <<'EOF'
#!/usr/bin/env python3
"""Faux service 'base de données' du module 14 : bannière sur le port 5432."""
import socket, socketserver, sys

PORT = 5432

class Banniere(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.sendall(
            ("LAB12-DB-OK %s\n" % socket.gethostname()).encode())

class Serveur(socketserver.ThreadingTCPServer):
    allow_reuse_address = True

if __name__ == "__main__":
    try:
        Serveur(("0.0.0.0", PORT), Banniere).serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)
EOF
  chmod 755 /opt/lab14/faux-pg.py
  cat > /etc/systemd/system/lab14-db.service <<'EOF'
[Unit]
Description=Lab12 — faux service de base de données (port 5432)
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
ExecStart=/opt/lab14/faux-pg.py
DynamicUser=yes
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF
}

# --- 4b. fausse application web locale, port 3000 (cible du tunnel -R)
faux_app() {
  cat > /opt/lab14/faux-app.py <<'EOF'
#!/usr/bin/env python3
"""Fausse application du module 14 : HTTP sur 127.0.0.1:3000."""
import socket
from http.server import BaseHTTPRequestHandler, HTTPServer

class App(BaseHTTPRequestHandler):
    def do_GET(self):
        corps = ("LAB12-APP-OK %s\n" % socket.gethostname()).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)
    def log_message(self, *a):
        pass

if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 3000), App).serve_forever()
EOF
  chmod 755 /opt/lab14/faux-app.py
  cat > /etc/systemd/system/lab14-app.service <<'EOF'
[Unit]
Description=Lab12 — fausse application locale (127.0.0.1:3000)
After=network.target

[Service]
Type=exec
ExecStart=/opt/lab14/faux-app.py
DynamicUser=yes
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF
}

activer() {
  if [ -d /run/systemd/system ]; then
    systemctl daemon-reload
    systemctl enable --now "$1" >/dev/null 2>&1 || \
      echo "  note : $1 n'a pas démarré (systemctl status $1)"
  else
    echo "  note : systemd absent, $1 non démarré"
  fi
}

case "$HOTE" in
  lab-db)
    faux_pg; activer lab14-db.service
    echo "   faux service base de données actif sur 5432"
    ;;
  lab-adm)
    faux_app; activer lab14-app.service
    mkdir -p "$LAB_HOME/.ssh/cm" "$LAB_HOME/.ssh/config.d"
    chown -R "$LAB_USER":"$LAB_USER" "$LAB_HOME/.ssh"
    chmod 700 "$LAB_HOME/.ssh/cm" "$LAB_HOME/.ssh/config.d"
    echo "   fausse application active sur 127.0.0.1:3000"
    echo "   ~/.ssh/cm et ~/.ssh/config.d prêts"
    ;;
  lab-web)
    # compte de service de L14.5 : pas de mot de passe, home dédié
    if ! getent passwd sauvegarde >/dev/null; then
      useradd -m -U -d /home/sauvegarde -s /bin/bash \
              -c "Depot de sauvegardes (lab14)" sauvegarde
      passwd -q -l sauvegarde >/dev/null 2>&1 || true
    fi
    install -d -o sauvegarde -g sauvegarde -m 700 /home/sauvegarde/.ssh
    install -d -o sauvegarde -g sauvegarde -m 750 /srv/sauvegarde
    mkdir -p /srv/app
    printf 'donnees applicatives du lab14\n' > /srv/app/donnees.txt
    : > /srv/sauvegarde/.conserver
    echo "   compte sauvegarde + /srv/sauvegarde + /srv/app prêts"
    ;;
  lab-ops)
    echo "   rôle CI : rien de particulier à installer"
    ;;
  *)
    echo "  note : nom d'hôte '$HOTE' hors du lab, seule la partie"
    echo "         commune a été appliquée"
    ;;
esac

chown -R "$LAB_USER":"$LAB_USER" "$BASE"

# ---------------------------------------------------------------------
# 5. Rappel des points d'entrée
# ---------------------------------------------------------------------
cat <<EOF

Prêt sur $HOTE. Points d'entrée :
  $BASE/bin/etat.sh        script local à exécuter à distance (E14.12)
  $BASE/conf/              tes fichiers de configuration livrables
  $BASE/rapports/          tes rapports
  ~/.ssh/id_rsa            vieille clé RSA 2048 à faire tourner (L14.1)
  $SAUV/etc-ssh            sauvegarde de /etc/ssh avant le module

Rappel : garde une session ouverte avant toute modification de sshd_config.
EOF
