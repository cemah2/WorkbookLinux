#!/usr/bin/env bash
# setup_M08.sh — prépare le terrain du module 08
#                (processus, signaux, jobs, limites, systemd)
# À lancer avec sudo. Idempotent : relançable sans effet de bord.
#
# Ce script NE crée AUCUNE unité systemd : les écrire est le travail du
# module. Il installe uniquement l'application « factura » à servicifier,
# ses répertoires, son fichier d'environnement et le bac à sable de
# l'apprenant.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab08"
BIN=/opt/factura/bin
ETC=/etc/factura
LOGD=/var/log/factura
DATA=/srv/factura/data

echo "== Préparation du module 08 =="
echo "   utilisateur : $LAB_USER"
echo "   base        : $BASE"

command -v python3 >/dev/null 2>&1 || {
  echo "python3 est requis (voir §8.1)" >&2; exit 1; }

# ---------------------------------------------------------------------
# 1. Compte de service et répertoires
# ---------------------------------------------------------------------
groupadd -f factura
if ! getent passwd factura >/dev/null; then
  useradd -r -g factura -d /srv/factura -s /usr/sbin/nologin factura
fi

mkdir -p "$BIN" "$ETC" "$LOGD" "$DATA" /var/lib/factura
chown -R factura:factura "$LOGD" /srv/factura /var/lib/factura
chmod 0755 "$LOGD" /srv/factura "$DATA"
chown root:root /opt/factura "$BIN" "$ETC"
chmod 0755 /opt/factura "$BIN" "$ETC"

# ---------------------------------------------------------------------
# 2. factura-api : le serveur HTTP à servicifier (L8.2 à L8.5, D8)
# ---------------------------------------------------------------------
cat > "$BIN/factura-api.py" <<'PYEOF'
#!/usr/bin/env python3
"""factura-api — serveur HTTP de démonstration (workbook, module 08).

Variables d'environnement reconnues :
  FACTURA_PORT          port d'écoute            (défaut 8080)
  FACTURA_LOG           journal   (defaut /var/log/factura/api.log)
  FACTURA_DATA          répertoire de données    (défaut /srv/factura/data)
  FACTURA_DELAI_PRET    secondes avant d'écouter (défaut 0)
  FACTURA_DELAI_ARRET   secondes de drainage     (défaut 0)
  FACTURA_SOURD=1       ignore SIGTERM et SIGINT (démo kill -9)

Routes : /  /sante  /charge?n=N  (N descripteurs ouverts et conservés)
"""
import http.server
import os
import signal
import socket
import socketserver
import sys
import threading
import time
import urllib.parse

PORT = int(os.environ.get("FACTURA_PORT", "8080"))
LOGF = os.environ.get("FACTURA_LOG", "/var/log/factura/api.log")
DATA = os.environ.get("FACTURA_DATA", "/srv/factura/data")
DELAI_PRET = float(os.environ.get("FACTURA_DELAI_PRET", "0"))
DELAI_ARRET = float(os.environ.get("FACTURA_DELAI_ARRET", "0"))
SOURD = os.environ.get("FACTURA_SOURD", "0") == "1"

_fds = []
_debut = time.time()
_srv = None


def journal(msg):
    ligne = "%s [%d] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"),
                            os.getpid(), msg)
    print(ligne, flush=True)
    try:
        with open(LOGF, "a") as f:
            f.write(ligne + "\n")
    except OSError as err:
        print("%s [%d] journal indisponible: %s"
              % (time.strftime("%Y-%m-%d %H:%M:%S"), os.getpid(), err),
              flush=True)


def notifier(etat):
    """sd_notify minimal : utile uniquement avec Type=notify."""
    adr = os.environ.get("NOTIFY_SOCKET")
    if not adr:
        return False
    if adr[0] == "@":
        adr = "\0" + adr[1:]
    s = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    try:
        s.connect(adr)
        s.sendall(etat.encode())
        return True
    except OSError as err:
        journal("sd_notify a échoué: %s" % err)
        return False
    finally:
        s.close()


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "factura-api/1.3"

    def log_message(self, fmt, *args):
        journal("http %s %s" % (self.address_string(), fmt % args))

    def _repondre(self, code, corps):
        data = corps.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        parts = urllib.parse.urlsplit(self.path)
        if parts.path == "/sante":
            self._repondre(200, "ok pid=%d uptime=%ds fds=%d\n"
                           % (os.getpid(),
                              int(time.time() - _debut), len(_fds)))
        elif parts.path == "/charge":
            q = urllib.parse.parse_qs(parts.query)
            n = int(q.get("n", ["100"])[0])
            ouverts = 0
            try:
                for _ in range(n):
                    _fds.append(open("/dev/null", "rb"))
                    ouverts += 1
            except OSError as err:
                journal("ouverture refusée après %d fd: %s" % (ouverts, err))
                self._repondre(500, "erreur apres %d fd: %s\n"
                               % (ouverts, err))
                return
            self._repondre(200, "%d descripteurs ouverts, total %d\n"
                           % (ouverts, len(_fds)))
        elif parts.path == "/":
            self._repondre(200, "factura-api, donnees dans %s\n" % DATA)
        else:
            self._repondre(404, "inconnu\n")


def _arret_propre():
    if DELAI_ARRET:
        journal("drainage des requetes en cours (%.0fs)" % DELAI_ARRET)
        time.sleep(DELAI_ARRET)
    if _srv is not None:
        _srv.shutdown()


def sur_arret(signum, _frame):
    nom = signal.Signals(signum).name
    if SOURD:
        journal("%s recu — IGNORE (FACTURA_SOURD=1)" % nom)
        return
    journal("%s recu — arret demande" % nom)
    notifier("STOPPING=1")
    threading.Thread(target=_arret_propre, daemon=True).start()


def sur_hup(_signum, _frame):
    journal("SIGHUP recu — rechargement de la configuration")
    notifier("RELOADING=1")
    notifier("READY=1")


def main():
    global _srv
    journal("demarrage, port=%d data=%s" % (PORT, DATA))
    if DELAI_PRET:
        journal("initialisation (%.0fs) avant mise en ecoute" % DELAI_PRET)
        time.sleep(DELAI_PRET)
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    try:
        _srv = socketserver.ThreadingTCPServer(("0.0.0.0", PORT), Handler)
    except OSError as err:
        journal("impossible d'ecouter sur %d: %s" % (PORT, err))
        return 13
    signal.signal(signal.SIGTERM, sur_arret)
    signal.signal(signal.SIGINT, sur_arret)
    signal.signal(signal.SIGHUP, sur_hup)
    journal("en ecoute sur 0.0.0.0:%d" % PORT)
    notifier("READY=1")
    _srv.serve_forever()
    _srv.server_close()
    for f in _fds:
        f.close()
    journal("arret propre, sortie 0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYEOF

# ---------------------------------------------------------------------
# 3. factura-collecte : traitement ponctuel (Type=oneshot)
# ---------------------------------------------------------------------
cat > "$BIN/factura-collecte.sh" <<'SHEOF'
#!/usr/bin/env bash
# factura-collecte — traitement ponctuel : prend une mesure et sort.
set -euo pipefail
LOG="${FACTURA_LOG:-/var/log/factura/collecte.log}"
DEST="${FACTURA_DATA:-/srv/factura/data}"
DUREE="${FACTURA_DUREE:-3}"

printf '%s [%d] collecte demarree\n' "$(date '+%F %T')" "$$" >> "$LOG"
sleep "$DUREE"
{
  printf 'date;charge1;memdispo_ko\n'
  printf '%s;%s;%s\n' "$(date '+%F %T')" \
    "$(cut -d' ' -f1 /proc/loadavg)" \
    "$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
} > "$DEST/collecte.csv"
printf '%s [%d] collecte terminee -> %s\n' "$(date '+%F %T')" "$$" \
  "$DEST/collecte.csv" >> "$LOG"
SHEOF

# ---------------------------------------------------------------------
# 4. factura-legacy : démon « historique » qui se détache (Type=forking)
# ---------------------------------------------------------------------
cat > "$BIN/factura-legacy.sh" <<'SHEOF'
#!/usr/bin/env bash
# factura-legacy — démon à l'ancienne : il se détache lui-même en tâche
# de fond et écrit son fichier de PID. Le processus lancé sort en 0.
set -euo pipefail
PIDFILE="${FACTURA_PIDFILE:-/run/factura/legacy.pid}"
LOG="${FACTURA_LOG:-/var/log/factura/legacy.log}"
mkdir -p "$(dirname "$PIDFILE")"

boucle() {
  # $BASHPID et non $$ : dans un sous-shell, $$ reste le PID du père.
  trap 'printf "%s [%d] arret propre\n" "$(date "+%F %T")" "$BASHPID" \
          >> "$LOG"
        rm -f "$PIDFILE"; exit 0' TERM INT
  while :; do
    printf '%s [%d] tick historique\n' "$(date '+%F %T')" "$BASHPID" \
      >> "$LOG"
    sleep 10 & wait $!
  done
}

boucle &
echo $! > "$PIDFILE"
printf '%s [%d] demon detache, pid fils %s\n' "$(date '+%F %T')" "$$" \
  "$(cat "$PIDFILE")" >> "$LOG"
exit 0
SHEOF

# ---------------------------------------------------------------------
# 5. Outils de démonstration : charge CPU, ogre mémoire, zombie
# ---------------------------------------------------------------------
cat > "$BIN/factura-charge.sh" <<'SHEOF'
#!/usr/bin/env bash
# factura-charge [n] — occupe n coeurs (défaut 1) jusqu'à SIGTERM.
set -euo pipefail
n="${1:-1}"
pids=()
brule() { while :; do :; done; }
trap 'kill "${pids[@]}" 2>/dev/null; exit 0' TERM INT
for _ in $(seq 1 "$n"); do brule & pids+=("$!"); done
echo "charge lancee sur $n coeur(s), pids: ${pids[*]}"
wait
SHEOF

cat > "$BIN/factura-gourmand.py" <<'PYEOF'
#!/usr/bin/env python3
"""factura-gourmand — alloue de la memoire par tranches jusqu'a etre tue.

Usage : factura-gourmand.py [Mo_par_tranche] [pause_secondes]
"""
import os
import sys
import time

tranche = int(sys.argv[1]) if len(sys.argv) > 1 else 50
pause = float(sys.argv[2]) if len(sys.argv) > 2 else 0.5
bloc = b"x" * (tranche * 1024 * 1024)
gardes = []
total = 0
print("pid=%d, tranches de %d Mo" % (os.getpid(), tranche), flush=True)
while True:
    gardes.append(bytearray(bloc))
    total += tranche
    print("alloue %d Mo" % total, flush=True)
    time.sleep(pause)
PYEOF

cat > "$BIN/factura-zombie.py" <<'PYEOF'
#!/usr/bin/env python3
"""factura-zombie [duree] — fabrique un zombie pendant `duree` secondes.

Le pere fork(), le fils sort immediatement, et le pere ne fait JAMAIS
wait() : l'entree du fils reste dans la table des processus en etat Z.
Ecrit en Python et non en bash parce que bash recolte automatiquement
ses jobs d'arriere-plan — impossible d'obtenir un zombie durable avec
un simple `( exit 0 ) &`.
"""
import os
import sys
import time

duree = int(sys.argv[1]) if len(sys.argv) > 1 else 120
pid = os.fork()
if pid == 0:
    os._exit(0)
print("pere=%d  fils zombie=%d  (pendant %ds)" % (os.getpid(), pid, duree),
      flush=True)
time.sleep(duree)
PYEOF

chmod 0755 "$BIN"/factura-*.py "$BIN"/factura-*.sh
chown root:root "$BIN"/factura-*

# ---------------------------------------------------------------------
# 6. Fichier d'environnement (EnvironmentFile= des labs)
# ---------------------------------------------------------------------
if [ ! -f "$ETC/api.env" ]; then
  cat > "$ETC/api.env" <<'ENVEOF'
# /etc/factura/api.env — lu par EnvironmentFile= dans l'unité.
# Syntaxe : CLE=valeur, une par ligne, pas d'export, pas d'expansion shell.
FACTURA_PORT=8080
FACTURA_DATA=/srv/factura/data
FACTURA_LOG=/var/log/factura/api.log
FACTURA_DELAI_PRET=0
FACTURA_DELAI_ARRET=0
ENVEOF
fi
chown root:factura "$ETC/api.env"
chmod 0640 "$ETC/api.env"

# ---------------------------------------------------------------------
# 7. Bac à sable de l'apprenant
# ---------------------------------------------------------------------
mkdir -p "$BASE"/{units,rapports,bin}
[ -f "$BASE/rapports/.gardien" ] || : > "$BASE/rapports/.gardien"
chown -R "$LAB_USER":"$LAB_USER" "$BASE"

# ---------------------------------------------------------------------
# 8. Avertissements d'outillage
# ---------------------------------------------------------------------
for p in htop tmux pstree pgrep lsof ss systemd-analyze; do
  command -v "$p" >/dev/null 2>&1 || \
    echo "  note : $p n'est pas installé (voir §8.1)"
done
[ -d /run/systemd/system ] || \
  echo "  note : systemd ne pilote pas cette machine, la partie B ne \
fonctionnera pas ici"

cat <<EOF

Prêt. Points d'entrée :
  $BIN/factura-api.py        serveur HTTP à servicifier (port 8080)
  $BIN/factura-collecte.sh   traitement ponctuel (Type=oneshot)
  $BIN/factura-legacy.sh     démon qui se détache (Type=forking)
  $BIN/factura-charge.sh     occupe n coeurs (nice, renice, top)
  $BIN/factura-gourmand.py   mange la RAM (MemoryMax, OOM killer)
  $BIN/factura-zombie.sh     fabrique un processus en état Z
  $ETC/api.env               fichier d'environnement du service
  $LOGD/                     journaux applicatifs (propriétaire factura)
  $BASE/units/               ton atelier d'écriture d'unités

Vérification rapide, sans service :
  sudo -u factura env FACTURA_PORT=8080 $BIN/factura-api.py &
  curl -s http://127.0.0.1:8080/sante
EOF
