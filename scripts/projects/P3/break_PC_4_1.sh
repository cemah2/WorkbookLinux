#!/usr/bin/env bash
# break_PC_4_1.sh — ticket PC.4.1 (lab-web) : demande de changement.
# Ne casse rien : prépare le contexte de la demande d'ouverture de port.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_4_1; mkdir -p "$SAUV"
cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"

# Un petit service de collecte partenaire écoute sur 9443 (simulation).
cat > /opt/factura/bin/partenaire-collecte.py <<'PYEOF'
#!/usr/bin/env python3
import http.server, socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers()
        self.wfile.write(b"collecte partenaire OK\n")
    def log_message(self, *a): pass
socketserver.TCPServer(("0.0.0.0", 9443), H).serve_forever()
PYEOF
cat > /etc/systemd/system/partenaire-collecte.service <<'EOF'
[Unit]
Description=Endpoint de collecte partenaire (port 9443)
After=network-online.target
[Service]
ExecStart=/usr/bin/python3 /opt/factura/bin/partenaire-collecte.py
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
[ -d /run/systemd/system ] && { systemctl daemon-reload
  systemctl enable --now partenaire-collecte.service >/dev/null 2>&1 || true; }

cat <<'EOF'

Demande déposée : le partenaire « Comptaflux » (IP 203.0.113.42) doit
pouvoir joindre l'endpoint de collecte sur le port 9443/tcp de lab-web.
Ouvrir l'accès en respectant le principe du moindre privilège.
EOF
