#!/usr/bin/env bash
# setup_M12.sh — prépare le terrain du module 12 (réseau et diagnostic)
# À lancer avec sudo sur lab-adm ET sur lab-web. Idempotent.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab12"
HOSTN="$(hostname -s)"
SAUV=/root/.m11-backup
mkdir -p "$SAUV"

# interface portant la route par défaut (ens18 sur les VM du lab)
IFACE="$(ip -o -4 route show default 2>/dev/null | awk '{print $5; exit}')"
[ -n "$IFACE" ] || IFACE="$(ip -o -4 -br a show up scope global \
                            | awk '{print $1; exit}')"
[ -n "$IFACE" ] || IFACE=ens18

echo "== Préparation du module 12 =="
echo "   hôte        : $HOSTN"
echo "   utilisateur : $LAB_USER"
echo "   interface   : $IFACE"

# ---------------------------------------------------------------------
# 1. Sauvegardes de ce que les labs et les pannes vont modifier
# ---------------------------------------------------------------------
for f in /etc/hosts /etc/nsswitch.conf; do
  b="$SAUV/$(basename "$f").orig"
  [ -f "$b" ] || cp -a "$f" "$b"
done
if [ -d /etc/netplan ] && [ ! -d "$SAUV/netplan.orig" ]; then
  cp -a /etc/netplan "$SAUV/netplan.orig"
fi
# nature de /etc/resolv.conf avant que BF12.2 n'y touche
[ -f "$SAUV/resolv.conf.state" ] || {
  if [ -L /etc/resolv.conf ]; then
    printf 'symlink %s\n' "$(readlink /etc/resolv.conf)" \
      > "$SAUV/resolv.conf.state"
  else
    printf 'file\n' > "$SAUV/resolv.conf.state"
    cp -a /etc/resolv.conf "$SAUV/resolv.conf.orig"
  fi
}

# ---------------------------------------------------------------------
# 2. Bac à sable de l'apprenant
# ---------------------------------------------------------------------
mkdir -p "$BASE"/{bin,rapports,captures}

cat > "$BASE/bin/mauvais-serveur.py" <<'EOF'
#!/usr/bin/env python3
"""Serveur volontairement bogué : il accepte les connexions et ne les
ferme jamais. Sert à produire des sockets en CLOSE-WAIT (L12.4)."""
import socket
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8100
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", PORT))
srv.listen(64)
print(f"mauvais-serveur : 127.0.0.1:{PORT} — jamais de close()", flush=True)

gardes = []          # on garde les descripteurs ouverts : c'est le bug
while True:
    conn, _ = srv.accept()
    gardes.append(conn)
    print(f"connexion acceptee, {len(gardes)} descripteurs retenus",
          flush=True)
EOF
chmod 755 "$BASE/bin/mauvais-serveur.py"

cat > "$BASE/rapports/plan-adressage.md" <<'EOF'
# Plan d'adressage — L12.1

<!-- À compléter : quatre sous-réseaux de 10.10.10.0/24, placement des VM,
     proposition de DMZ, et les trois sorties de `ip route get`. -->
EOF

for f in zone-lab-local.md sockets.md capture.md debit.md; do
  [ -e "$BASE/rapports/$f" ] || : > "$BASE/rapports/$f"
done

chown -R "$LAB_USER":"$LAB_USER" "$BASE"

# ---------------------------------------------------------------------
# 3. Le service applicatif factura-api (cible de L12.4 et BF12.3)
# ---------------------------------------------------------------------
install -d -m 0755 /opt/factura/bin
cat > /opt/factura/bin/factura-api.py <<'EOF'
#!/usr/bin/env python3
"""API de lab. Adresse et port pris dans l'environnement, ce qui permet
de les modifier par un drop-in systemd (voir BF12.3)."""
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

BIND = os.environ.get("FACTURA_BIND", "0.0.0.0")
PORT = int(os.environ.get("FACTURA_PORT", "8099"))


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        corps = json.dumps({"status": "ok", "bind": BIND,
                            "path": self.path}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    do_HEAD = do_GET

    def log_message(self, *a):
        pass


HTTPServer((BIND, PORT), H).serve_forever()
EOF
chmod 755 /opt/factura/bin/factura-api.py

getent passwd factura >/dev/null || \
  useradd -r -s /usr/sbin/nologin -d /opt/factura factura

cat > /etc/systemd/system/factura-api.service <<'EOF'
[Unit]
Description=Factura API (lab12)
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=factura
Group=factura
Environment=FACTURA_BIND=0.0.0.0
Environment=FACTURA_PORT=8099
ExecStart=/opt/factura/bin/factura-api.py
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 /etc/systemd/system/factura-api.service

# un passage de break_M12_03.sh ne doit pas survivre au setup
rm -f /etc/systemd/system/factura-api.service.d/override.conf
rmdir --ignore-fail-on-non-empty \
  /etc/systemd/system/factura-api.service.d 2>/dev/null || true

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload
  systemctl enable --now factura-api.service >/dev/null 2>&1 || \
    echo "  note : factura-api n'a pas démarré (python3 absent ?)"
fi

# ---------------------------------------------------------------------
# 4. Serveur DNS du lab — uniquement sur lab-adm
# ---------------------------------------------------------------------
if [ "$HOSTN" = lab-adm ] && command -v dnsmasq >/dev/null 2>&1; then
  cat > /etc/dnsmasq.d/lab.conf <<'EOF'
# zone de lab lab.local — module 12
# bind-interfaces + listen-address : cohabitation avec le stub
# systemd-resolved qui occupe deja 127.0.0.53:53
bind-interfaces
listen-address=10.10.10.10
no-dhcp-interface=
domain=lab.local
local=/lab.local/
expand-hosts
domain-needed
bogus-priv
local-ttl=300

address=/lab-adm.lab.local/10.10.10.10
address=/lab-web.lab.local/10.10.10.11
address=/lab-db.lab.local/10.10.10.12
address=/lab-rhel.lab.local/10.10.10.13
address=/lab-ops.lab.local/10.10.10.14

cname=www.lab.local,lab-web.lab.local
cname=shop.lab.local,lab-web.lab.local
mx-host=lab.local,lab-adm.lab.local,10
txt-record=lab.local,"v=spf1 ip4:10.10.10.0/24 -all"
srv-host=_http._tcp.lab.local,lab-web.lab.local,80,10,10

ptr-record=10.10.10.10.in-addr.arpa,lab-adm.lab.local
ptr-record=11.10.10.10.in-addr.arpa,lab-web.lab.local
ptr-record=12.10.10.10.in-addr.arpa,lab-db.lab.local

server=9.9.9.9
EOF
  systemctl enable dnsmasq >/dev/null 2>&1 || true
  systemctl restart dnsmasq >/dev/null 2>&1 || \
    echo "  note : dnsmasq n'a pas démarré (conflit sur le port 53 ?)"
fi

# ---------------------------------------------------------------------
# 5. Frontal web — uniquement sur lab-web
# ---------------------------------------------------------------------
if [ "$HOSTN" = lab-web ] && command -v nginx >/dev/null 2>&1; then
  install -d -m 0755 /var/www/lab
  cat > /var/www/lab/index.html <<'EOF'
<!doctype html><html lang="fr"><head><meta charset="utf-8">
<title>lab-web</title></head>
<body><h1>lab-web — vhost par defaut</h1></body></html>
EOF
  # un fichier volumineux pour les tests de MTU et de debit (L12.5)
  [ -f /var/www/lab/gros.bin ] || \
    head -c 20971520 /dev/urandom > /var/www/lab/gros.bin

  cat > /etc/nginx/sites-available/lab-web <<'EOF'
server {
    listen 80 default_server;
    server_name www.lab.local lab-web.lab.local _;
    root /var/www/lab;
    index index.html;
}
EOF
  ln -sf /etc/nginx/sites-available/lab-web \
         /etc/nginx/sites-enabled/lab-web
  rm -f /etc/nginx/sites-enabled/default
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || \
    { systemctl enable --now nginx >/dev/null 2>&1 || true; }
fi

# ---------------------------------------------------------------------
# 6. Capture d'incident à analyser (L12.5 étape 3)
#    Générée pour de vrai : 5 tentatives TCP vers un port fermé.
#    On ne fabrique pas un pcap à la main, on en capture un.
# ---------------------------------------------------------------------
install -d -m 0755 /srv/captures
PCAP=/srv/captures/incident.pcap
if [ ! -s "$PCAP" ] && command -v tcpdump >/dev/null 2>&1; then
  CIBLE=10.10.10.11
  ping -c1 -W1 "$CIBLE" >/dev/null 2>&1 || CIBLE=127.0.0.1
  IF_CAP="$IFACE"
  [ "$CIBLE" = 127.0.0.1 ] && IF_CAP=lo
  tcpdump -i "$IF_CAP" -nn -w "$PCAP" \
    "host $CIBLE and tcp port 8199" >/dev/null 2>&1 &
  TPID=$!
  sleep 2
  for _ in 1 2 3 4 5; do
    timeout 2 bash -c "</dev/tcp/$CIBLE/8199" 2>/dev/null || true
    sleep 0.3
  done
  sleep 1
  kill "$TPID" 2>/dev/null || true
  wait "$TPID" 2>/dev/null || true
  chmod 0644 "$PCAP" 2>/dev/null || true
  [ -s "$PCAP" ] || echo "  note : capture incident.pcap vide (tcpdump ?)"
fi

# ---------------------------------------------------------------------
# 7. Contrôle de l'outillage
# ---------------------------------------------------------------------
MANQUE=""
for p in ip ss dig curl nc tcpdump ping traceroute lsof iperf3; do
  command -v "$p" >/dev/null 2>&1 || MANQUE="$MANQUE $p"
done
[ -z "$MANQUE" ] || echo "  note : outils absents ->$MANQUE (voir §12.1)"

cat <<EOF

Prêt sur $HOSTN. Points d'entrée :
  $BASE/rapports/           tes livrables
  $BASE/bin/mauvais-serveur.py   provoque des CLOSE-WAIT (L12.4)
  /opt/factura/bin/factura-api.py + factura-api.service   port 8099
  /srv/captures/incident.pcap    capture à analyser (L12.5)
  /etc/dnsmasq.d/lab.conf        zone lab.local (lab-adm uniquement)
  /etc/nginx/sites-available/lab-web   vhost (lab-web uniquement)

Sauvegardes : $SAUV/
EOF
