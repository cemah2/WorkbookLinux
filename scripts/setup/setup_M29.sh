#!/usr/bin/env bash
# setup_M29.sh — prépare le terrain du module 29 (haute disponibilité)
# À lancer avec sudo sur lab-web, lab-ops, lab-ha1, lab-ha2 et lab-adm.
# Idempotent : relançable sans effet de bord.
#
# Ce script NE configure NI HAProxy, NI keepalived, NI le cluster : c'est le
# travail du module. Il installe les applications servies (lab29-app sur les
# serveurs, lab29-batch sur les nœuds, désactivée), la sonde de lab-adm, et
# fait le bilan des prérequis.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
BASE="$LAB_HOME/lab29"
LIB=/usr/local/lib/lab29

role=inconnu
for a in $(hostname -I); do
  case "$a" in
    10.10.10.10) role=adm ;;
    10.10.10.11|10.10.10.14) role=serveur ;;
    10.10.10.21|10.10.10.22) role=noeud ;;
  esac
done
echo "== Préparation du module 29 =="
echo "   machine : $(hostname -s), rôle : $role"
[ "$role" != inconnu ] || {
  echo "   pas une VM du module 29 (lab-web, lab-ops, lab-ha1, lab-ha2, lab-adm)" >&2
  exit 1; }
install -d -o "$LAB_USER" -g "$LAB_USER" -m 755 "$BASE"

# ---------------------------------------------------------------------
# Petite application HTTP (partagée par lab29-app et lab29-batch)
# ---------------------------------------------------------------------
ecrire_app() {
  install -d -m 755 "$LIB"
  cat > "$LIB/app.py" <<'PY'
#!/usr/bin/env python3
"""Application HTTP du module 29.

MODE=app   (port 8029) : /  /sante (503 si /run/lab29/maintenance)  /lent?s=N
MODE=batch (port 9029) : /  dit sur quel nœud et depuis quand le service tourne
"""
import http.server
import os
import socket
import time
import urllib.parse

NOM = socket.gethostname().split(".")[0]
MODE = os.environ.get("MODE", "app")
PORT = int(os.environ.get("PORT", "8029"))
DEBUT = time.strftime("%H:%M:%S")
MAINT = "/run/lab29/maintenance"


class Gestionnaire(http.server.BaseHTTPRequestHandler):
    server_version = "lab29/1.0"

    def repondre(self, code, texte):
        corps = (texte + "\n").encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        if MODE == "batch":
            if url.path == "/":
                return self.repondre(200, f"lab29-batch actif sur {NOM} depuis {DEBUT} (pid {os.getpid()})")
            return self.repondre(404, "introuvable")
        if url.path == "/sante":
            if os.path.exists(MAINT):
                return self.repondre(503, f"{NOM} en maintenance")
            return self.repondre(200, f"{NOM} ok")
        if url.path == "/lent":
            try:
                s = min(float(urllib.parse.parse_qs(url.query).get("s", ["1"])[0]), 120)
            except ValueError:
                s = 1.0
            time.sleep(s)
            return self.repondre(200, f"{NOM} a répondu en {s:g} s")
        if url.path == "/":
            return self.repondre(200, f"servi par {NOM}")
        return self.repondre(404, "introuvable")

    def log_message(self, fmt, *args):
        pass  # pas de journal par requête : les sondes en feraient des millions


http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Gestionnaire).serve_forever()
PY
  chmod 755 "$LIB/app.py"
}

case "$role" in
  serveur)
    ecrire_app
    cat > /etc/systemd/system/lab29-app.service <<'EOF'
[Unit]
Description=lab29-app : application HTTP du module 29 (port 8029)
After=network-online.target
Wants=network-online.target

[Service]
Environment=MODE=app PORT=8029
ExecStart=/usr/bin/python3 /usr/local/lib/lab29/app.py
DynamicUser=yes
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now lab29-app >/dev/null 2>&1
    systemctl restart lab29-app
    if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
      for n in 10.10.10.21 10.10.10.22 10.10.10.10; do
        ufw allow from "$n" to any port 8029 proto tcp comment 'lab29' >/dev/null
      done
      echo "   ufw : 8029/tcp ouvert pour lab-ha1, lab-ha2, lab-adm"
    fi
    sleep 1
    curl -fsS http://127.0.0.1:8029/sante >/dev/null \
      && echo "   lab29-app répond sur le port 8029" \
      || echo "   ATTENTION : lab29-app ne répond pas (journalctl -u lab29-app)"
    ;;
  noeud)
    ecrire_app
    cat > /etc/systemd/system/lab29-batch.service <<'EOF'
[Unit]
Description=lab29-batch : traitement unique du module 29 (piloté par Pacemaker)
After=network-online.target

[Service]
Environment=MODE=batch PORT=9029
ExecStart=/usr/bin/python3 /usr/local/lib/lab29/app.py
DynamicUser=yes
# PAS de [Install] : jamais activé dans systemd, c'est Pacemaker qui décide
EOF
    systemctl daemon-reload
    systemctl disable --now lab29-batch >/dev/null 2>&1 || true
    echo "   lab29-batch.service installé, désactivé (Pacemaker le démarrera)"
    ;;
  adm)
    install -d -o "$LAB_USER" -g "$LAB_USER" -m 755 "$BASE/defi"
    cat > "$BASE/sonde.sh" <<'EOF'
#!/usr/bin/env bash
# sonde.sh — interroge une URL dix fois par seconde et mesure les interruptions
# Usage : sonde.sh URL      (Ctrl-C pour le bilan)
set -uo pipefail
URL=${1:?usage : sonde.sh URL}
total=0; echecs=0; panne=0; debut=0; n=0; cumul=0; max=0
ms() { date +%s%3N; }
fmt() { awk -v v="$1" 'BEGIN{printf "%.1f", v/1000}' | tr . ,; }
bilan() {
  [ "$panne" -eq 1 ] && { d=$(( $(ms) - debut )); n=$((n+1)); cumul=$((cumul+d)); [ $d -gt $max ] && max=$d; }
  echo
  echo "requêtes : $total, en échec : $echecs"
  echo "interruptions : $n, durée totale $(fmt $cumul) s, plus longue $(fmt $max) s"
  exit 0
}
trap bilan INT TERM
echo "sonde sur $URL (Ctrl-C pour le bilan)"
while :; do
  t=$(ms)
  code=$(curl -s -o /dev/null -m 1 -w '%{http_code}' "$URL" 2>/dev/null) || code=000
  total=$((total+1))
  if [ "$code" = 200 ]; then
    if [ "$panne" -eq 1 ]; then
      d=$((t - debut)); n=$((n+1)); cumul=$((cumul+d)); [ $d -gt $max ] && max=$d
      printf '%s  retour après %s s\n' "$(date +%T)" "$(fmt $d)"; panne=0
    fi
  else
    echecs=$((echecs+1))
    if [ "$panne" -eq 0 ]; then
      panne=1; debut=$t
      printf '%s  interruption (code %s)\n' "$(date +%T)" "$code"
    fi
  fi
  sleep 0.1
done
EOF
    chown "$LAB_USER": "$BASE/sonde.sh"; chmod 755 "$BASE/sonde.sh"
    echo "   sonde : $BASE/sonde.sh URL"
    ;;
esac

# ---------------------------------------------------------------------
# Bilan des prérequis
# ---------------------------------------------------------------------
echo
echo "== Prérequis =="
AV=0
ok()    { printf '  [ OK ] %s\n' "$1"; }
avert() { printf '  [AVERT] %s\n' "$1"; AV=$((AV + 1)); }

for nom in lab-vip lab-ha1 lab-ha2 lab-batch; do
  getent hosts "$nom" >/dev/null \
    && ok "$nom se résout ($(getent hosts "$nom" | awk '{print $1}'))" \
    || avert "$nom ne se résout pas : entrées à ajouter à /root/lab/lab.hosts du nœud"
done
if [ "$role" = noeud ]; then
  ip link show ens18 >/dev/null 2>&1 \
    && ok "interface ens18 présente" \
    || avert "pas d'interface ens18 : adapte le nom dans les configurations"
  timeout 3 bash -c '</dev/tcp/10.10.10.1/8006' 2>/dev/null \
    && ok "API Proxmox joignable (10.10.10.1:8006, pour le fencing)" \
    || avert "API Proxmox injoignable depuis ce nœud : pas de fencing possible"
  [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ] \
    && ok "horloge synchronisée" || avert "horloge non synchronisée (chrony)"
fi
if [ "$role" = adm ]; then
  for s in lab-web lab-ops; do
    curl -fsS -m 2 "http://$s:8029/sante" >/dev/null 2>&1 \
      && ok "lab29-app répond sur $s:8029" \
      || avert "lab29-app ne répond pas sur $s:8029 (setup_M29.sh lancé là-bas ?)"
  done
fi
echo
[ "$AV" -eq 0 ] && echo "Prérequis réunis." || echo "$AV avertissement(s) à corriger."
