#!/usr/bin/env bash
# setup_M16.sh — prépare le terrain du module 16
#                (dépannage, performance, gestion d'incident)
# À lancer avec sudo sur lab-web. Idempotent : relançable sans effet de bord.
#
# Installe l'application de démonstration « vitrine » (frontal + dépendance
# interne), un volume de données dédié (image loop, pour pouvoir le remplir
# et le passer en lecture seule sans toucher au système), le générateur de
# charge, et le bac à sable ~/lab16 avec ses modèles.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab16"
BIN=/opt/vitrine/bin
ETC=/etc/vitrine
LOGD=/var/log/vitrine
DATA=/srv/vitrine/data
IMG=/var/lib/vitrine/data.img
TAILLE_MO=512

echo "== Préparation du module 16 =="
echo "   utilisateur : $LAB_USER"
echo "   base        : $BASE"

command -v python3 >/dev/null 2>&1 || {
  echo "python3 est requis (voir §16.1)" >&2; exit 1; }

# ---------------------------------------------------------------------
# 1. Compte de service et répertoires
# ---------------------------------------------------------------------
groupadd -f vitrine
if ! getent passwd vitrine >/dev/null; then
  useradd -r -g vitrine -d /srv/vitrine -s /usr/sbin/nologin vitrine
fi

mkdir -p "$BIN" "$ETC" "$LOGD" /var/lib/vitrine /srv/vitrine "$DATA"
chown root:root /opt/vitrine "$BIN" "$ETC"
chmod 0755 /opt/vitrine "$BIN" "$ETC"
chown vitrine:vitrine "$LOGD" /srv/vitrine
chmod 0755 "$LOGD" /srv/vitrine

# ---------------------------------------------------------------------
# 2. Volume de données dédié (image loop montée sur /srv/vitrine/data)
#    Objectif pédagogique : pouvoir le remplir à 100 %, épuiser ses
#    inodes et le passer en lecture seule sans jamais menacer le système.
# ---------------------------------------------------------------------
if [ ! -f "$IMG" ]; then
  echo "   création du volume de données (${TAILLE_MO} Mo)"
  dd if=/dev/zero of="$IMG" bs=1M count="$TAILLE_MO" status=none
  mkfs.ext4 -q -L vitrine-data "$IMG"
fi

FSTAB_LIGNE="$IMG $DATA ext4 loop,errors=remount-ro,nofail 0 2"
if ! grep -qsF "$IMG $DATA" /etc/fstab; then
  cp -a /etc/fstab "/etc/fstab.avant-M16.$(date +%Y%m%d%H%M%S)"
  printf '%s\n' "$FSTAB_LIGNE" >> /etc/fstab
fi

if ! mountpoint -q "$DATA"; then
  mount "$DATA" 2>/dev/null || mount -o loop,errors=remount-ro "$IMG" "$DATA"
fi
chown vitrine:vitrine "$DATA"
chmod 0775 "$DATA"

# ---------------------------------------------------------------------
# 3. Résolution du nom de la dépendance interne
# ---------------------------------------------------------------------
if ! grep -qs 'api-interne.lab.local' /etc/hosts; then
  printf '127.0.0.1\tapi-interne.lab.local api-interne\n' >> /etc/hosts
fi

# ---------------------------------------------------------------------
# 4. vitrine-api : le frontal (port 8080)
# ---------------------------------------------------------------------
cat > "$BIN/vitrine-api.py" <<'PYEOF'
#!/usr/bin/env python3
"""vitrine-api — frontal HTTP de démonstration (workbook, module 16).

Variables d'environnement :
  VITRINE_PORT        port d'écoute                      (défaut 8080)
  VITRINE_LOG         journal        (défaut /var/log/vitrine/api.log)
  VITRINE_DATA        volume de données  (défaut /srv/vitrine/data)
  VITRINE_DEP_HOST    nom de la dépendance interne
  VITRINE_DEP_PORT    port de la dépendance              (défaut 8081)
  VITRINE_DEP_REPLI   IP de repli si la résolution échoue
  VITRINE_FUITE       Mo fuités par seconde              (défaut 0)
  VITRINE_FD          descripteurs conservés par requête (défaut 0)

Routes :
  /sante      réponse immédiate, aucun appel externe
  /produits   résout puis interroge la dépendance interne
  /commande   écrit un fichier dans VITRINE_DATA
  /rapport    ouvre VITRINE_FD descripteurs et les garde
"""
import http.server
import os
import socket
import socketserver
import sys
import threading
import time
import urllib.parse

PORT = int(os.environ.get("VITRINE_PORT", "8080"))
LOGF = os.environ.get("VITRINE_LOG", "/var/log/vitrine/api.log")
DATA = os.environ.get("VITRINE_DATA", "/srv/vitrine/data")
DEP_HOST = os.environ.get("VITRINE_DEP_HOST", "api-interne.lab.local")
DEP_PORT = int(os.environ.get("VITRINE_DEP_PORT", "8081"))
DEP_REPLI = os.environ.get("VITRINE_DEP_REPLI", "127.0.0.1")
FUITE = int(os.environ.get("VITRINE_FUITE", "0"))
FD_PAR_REQ = int(os.environ.get("VITRINE_FD", "0"))

_fuite = []
_fds = []
_debut = time.time()


def journal(msg):
    ligne = "%s [%d] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"),
                            os.getpid(), msg)
    print(ligne, flush=True)
    try:
        with open(LOGF, "a") as f:
            f.write(ligne + "\n")
    except OSError:
        pass


def fuiteur():
    """Alloue FUITE Mo par seconde et ne les rend jamais."""
    bloc = b"f" * (1024 * 1024)
    while True:
        for _ in range(FUITE):
            _fuite.append(bytearray(bloc))
        time.sleep(1)


def appel_dependance():
    """Résout puis interroge la dépendance. Rend (duree, texte)."""
    t0 = time.time()
    try:
        infos = socket.getaddrinfo(DEP_HOST, DEP_PORT,
                                   socket.AF_INET, socket.SOCK_STREAM)
        adr = infos[0][4]
    except socket.gaierror as err:
        journal("resolution de %s impossible (%s), repli sur %s"
                % (DEP_HOST, err, DEP_REPLI))
        adr = (DEP_REPLI, DEP_PORT)
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(10)
    try:
        s.connect(adr)
        s.sendall(b"GET /stock HTTP/1.0\r\nHost: interne\r\n\r\n")
        rep = s.recv(4096)
    finally:
        s.close()
    return time.time() - t0, rep.decode("utf-8", "replace")


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    server_version = "vitrine-api/2.1"

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
        if FD_PAR_REQ:
            try:
                for _ in range(FD_PAR_REQ):
                    _fds.append(open("/dev/null", "rb"))
            except OSError as err:
                journal("OSError: [Errno %d] %s (fd ouverts: %d)"
                        % (err.errno, err.strerror, len(_fds)))
                self._repondre(500, "erreur interne: %s\n" % err)
                return
        if parts.path == "/sante":
            self._repondre(200, "ok pid=%d uptime=%ds rss_mo=%d\n"
                           % (os.getpid(), int(time.time() - _debut),
                              rss_mo()))
        elif parts.path == "/produits":
            try:
                duree, rep = appel_dependance()
            except OSError as err:
                journal("OSError: [Errno %d] %s" % (err.errno, err.strerror))
                self._repondre(502, "dependance injoignable: %s\n" % err)
                return
            self._repondre(200, "produits ok en %.3fs\n%s\n" % (duree, rep))
        elif parts.path == "/commande":
            nom = os.path.join(DATA, "cmd-%d.txt" % int(time.time() * 1000))
            try:
                with open(nom, "w") as f:
                    f.write("commande enregistree\n")
            except OSError as err:
                journal("OSError: [Errno %d] %s" % (err.errno, err.strerror))
                self._repondre(500, "ecriture impossible: %s\n" % err)
                return
            self._repondre(200, "commande enregistree dans %s\n" % nom)
        elif parts.path == "/rapport":
            self._repondre(200, "rapport pret, %d descripteurs gardes\n"
                           % len(_fds))
        elif parts.path == "/":
            self._repondre(200, "vitrine-api, donnees dans %s\n" % DATA)
        else:
            self._repondre(404, "inconnu\n")


def rss_mo():
    try:
        with open("/proc/self/status") as f:
            for l in f:
                if l.startswith("VmRSS:"):
                    return int(l.split()[1]) // 1024
    except OSError:
        pass
    return -1


def main():
    journal("demarrage, port=%d data=%s dep=%s:%d fuite=%d Mo/s"
            % (PORT, DATA, DEP_HOST, DEP_PORT, FUITE))
    if FUITE:
        threading.Thread(target=fuiteur, daemon=True).start()
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    try:
        srv = socketserver.ThreadingTCPServer(("0.0.0.0", PORT), Handler)
    except OSError as err:
        journal("impossible d'ecouter sur %d: %s" % (PORT, err))
        return 13
    journal("en ecoute sur 0.0.0.0:%d" % PORT)
    srv.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYEOF

# ---------------------------------------------------------------------
# 5. vitrine-dep : la « dépendance interne » (port 8081)
# ---------------------------------------------------------------------
cat > "$BIN/vitrine-dep.py" <<'PYEOF'
#!/usr/bin/env python3
"""vitrine-dep — dépendance interne de vitrine-api (workbook, module 16).

Répond instantanément sur /stock. VITRINE_DEP_LATENCE ajoute un délai
artificiel (en secondes) pour jouer le scénario « dépendance lente ».
"""
import http.server
import os
import socketserver
import sys
import time

PORT = int(os.environ.get("VITRINE_DEP_PORT", "8081"))
LAT = float(os.environ.get("VITRINE_DEP_LATENCE", "0"))


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    server_version = "vitrine-dep/1.0"

    def log_message(self, fmt, *args):
        print("%s %s" % (time.strftime("%F %T"), fmt % args), flush=True)

    def do_GET(self):
        if LAT:
            time.sleep(LAT)
        corps = b"stock=412 depot=NORD\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)


def main():
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    try:
        srv = socketserver.ThreadingTCPServer(("127.0.0.1", PORT), Handler)
    except OSError as err:
        print("impossible d'ecouter sur %d: %s" % (PORT, err), flush=True)
        return 13
    print("vitrine-dep en ecoute sur 127.0.0.1:%d" % PORT, flush=True)
    srv.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYEOF

# ---------------------------------------------------------------------
# 6. Générateur de charge (le « client »)
# ---------------------------------------------------------------------
cat > "$BIN/vitrine-charge.sh" <<'SHEOF'
#!/usr/bin/env bash
# vitrine-charge.sh [chemin] [parallele] [duree_s] — tape sur vitrine-api.
# Exemple : vitrine-charge.sh /produits 10 60
set -uo pipefail
CHEMIN="${1:-/sante}"
PAR="${2:-5}"
DUREE="${3:-30}"
CIBLE="${CIBLE:-http://127.0.0.1:8080}"
FIN=$(( $(date +%s) + DUREE ))

client() {
  local n=0 ko=0
  while [ "$(date +%s)" -lt "$FIN" ]; do
    # -f : un code HTTP 5xx compte comme un échec, pas comme un succès
    if curl -sf -o /dev/null --max-time 15 "$CIBLE$CHEMIN"; then
      n=$((n+1))
    else
      ko=$((ko+1))
    fi
  done
  printf '%s ok=%d ko=%d\n' "$$" "$n" "$ko"
}

echo "charge sur $CIBLE$CHEMIN : $PAR clients pendant ${DUREE}s"
for _ in $(seq 1 "$PAR"); do client & done
wait
SHEOF

chmod 0755 "$BIN"/vitrine-*.py "$BIN"/vitrine-*.sh
chown root:root "$BIN"/vitrine-*

# ---------------------------------------------------------------------
# 7. Fichier d'environnement
# ---------------------------------------------------------------------
if [ ! -f "$ETC/api.env" ]; then
  cat > "$ETC/api.env" <<'ENVEOF'
# /etc/vitrine/api.env — lu par EnvironmentFile= dans l'unité.
VITRINE_PORT=8080
VITRINE_DATA=/srv/vitrine/data
VITRINE_LOG=/var/log/vitrine/api.log
VITRINE_DEP_HOST=api-interne.lab.local
VITRINE_DEP_PORT=8081
VITRINE_DEP_REPLI=127.0.0.1
VITRINE_FUITE=0
VITRINE_FD=0
ENVEOF
fi
chown root:vitrine "$ETC/api.env"
chmod 0640 "$ETC/api.env"

# ---------------------------------------------------------------------
# 8. Unités systemd (l'écriture d'unités est le sujet du module 08 ;
#    ici elles sont fournies, le module travaille sur les pannes)
# ---------------------------------------------------------------------
cat > /etc/systemd/system/vitrine-dep.service <<'EOF'
[Unit]
Description=Vitrine — dependance interne (stock)
After=network.target

[Service]
Type=simple
User=vitrine
Group=vitrine
Environment=VITRINE_DEP_PORT=8081
ExecStart=/opt/vitrine/bin/vitrine-dep.py
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/vitrine-api.service <<'EOF'
[Unit]
Description=Vitrine — frontal HTTP
After=network.target vitrine-dep.service
Wants=vitrine-dep.service

[Service]
Type=simple
User=vitrine
Group=vitrine
EnvironmentFile=/etc/vitrine/api.env
WorkingDirectory=/srv/vitrine
ExecStart=/opt/vitrine/bin/vitrine-api.py
Restart=on-failure
RestartSec=3s
StartLimitIntervalSec=60
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

chmod 0644 /etc/systemd/system/vitrine-*.service

if [ -d /run/systemd/system ]; then
  systemctl daemon-reload
  systemctl enable --now vitrine-dep.service >/dev/null 2>&1 || true
  systemctl enable --now vitrine-api.service >/dev/null 2>&1 || true
else
  echo "  note : systemd ne pilote pas cette machine, les unités ne sont"
  echo "         pas démarrées (le module 16 suppose une VM, pas un conteneur)"
fi

# ---------------------------------------------------------------------
# 9. Bac à sable de l'apprenant
# ---------------------------------------------------------------------
mkdir -p "$BASE"/{bin,rapports,preuves,modeles}

cat > "$BASE/modeles/postmortem.md" <<'MDEOF'
# Post-mortem — INC-XXXX — <titre court et factuel>

## Résumé
Une phrase compréhensible par la direction : quoi, pour qui, combien de temps.

## Impact
- Durée de l'indisponibilité : de HH:MM à HH:MM (XX min)
- Services touchés :
- Utilisateurs touchés (nombre, proportion) :
- Impact métier constaté (commandes perdues, SLA, pénalités) :

## Chronologie (heures locales, faits uniquement)
| Heure | Événement | Source |
|---|---|---|
| HH:MM | premier signal (alerte, appel client) | |
| HH:MM | prise en charge | |
| HH:MM | première hypothèse | |
| HH:MM | action corrective | |
| HH:MM | rétablissement confirmé | |

## Détection
Comment l'a-t-on su ? Alerte automatique ou utilisateur ? Délai entre le début
réel de l'incident et la détection. Ce délai est-il acceptable ?

## Cause racine
Mécanisme technique complet, en langage factuel, sans nom de personne.

### Cinq pourquoi
1. Pourquoi ... ? Parce que ...
2. Pourquoi ... ? Parce que ...
3. Pourquoi ... ? Parce que ...
4. Pourquoi ... ? Parce que ...
5. Pourquoi ... ? Parce que ...   <- cause systémique

## Ce qui a bien marché
(Oui, cette section est obligatoire.)

## Ce qui a manqué
Outils absents, documentation fausse, accès manquant, alerte inexistante.

## Facteurs aggravants
Ce qui a rallongé la résolution sans être la cause.

## Actions correctives
| # | Action | Type | Responsable | Échéance |
|---|---|---|---|---|
| 1 | | prévention | | |
| 2 | | détection | | |
| 3 | | atténuation | | |

## Annexes
Journaux, captures, liens vers les tickets et le canal de l'incident.
MDEOF

cat > "$BASE/modeles/runbook.md" <<'MDEOF'
# Runbook — <symptôme tel qu'il est signalé>

## Quand appliquer
Signal d'entrée : alerte, message d'erreur exact, plainte utilisateur type.

## Confirmer en 2 minutes
```bash
# commandes de confirmation, avec ce qu'on doit voir
```

## Impact et urgence
Ce qui est cassé pour l'utilisateur, ce qui continue de marcher.

## Correctif
```bash
# étapes, une par ligne, avec le résultat attendu de chacune
```

## Vérifier le rétablissement
```bash
# la commande qui prouve que c'est réparé, pas celle qui rassure
```

## Si ça ne marche pas
Escalade : qui, par quel canal, avec quelles informations déjà collectées.

## Causes déjà rencontrées
| Date | Incident | Cause | Ce qui a marché |
|---|---|---|---|
MDEOF

cat > "$BASE/bin/tirage-pannes.sh" <<'SHEOF'
#!/usr/bin/env bash
# tirage-pannes.sh [n] — applique n pannes tirées au sort parmi les huit
# Break & Fix du module 16 (défi D16). À lancer en root.
# La sortie (liste des pannes appliquées) doit être redirigée dans un
# fichier que le candidat n'ouvre pas.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

N="${1:-5}"
REP="${REP_BREAK:-$HOME/workbook/scripts/break}"
[ -d "$REP" ] || REP=/root/workbook/scripts/break
[ -d "$REP" ] || { echo "répertoire des scripts break introuvable : \
définis REP_BREAK" >&2; exit 1; }

mapfile -t TOUS < <(ls "$REP"/break_M16_*.sh | sort)
[ "${#TOUS[@]}" -ge "$N" ] || { echo "seulement ${#TOUS[@]} pannes \
disponibles" >&2; exit 1; }

mapfile -t TIRAGE < <(printf '%s\n' "${TOUS[@]}" | shuf -n "$N")

echo "# tirage du $(date '+%F %T')"
for s in "${TIRAGE[@]}"; do
  echo "$s"
  bash "$s" >/dev/null 2>&1 || echo "  (échec d'application de $s)"
done
echo "# $N panne(s) appliquée(s). Bon courage."
SHEOF
chmod 0755 "$BASE/bin/tirage-pannes.sh"

chown -R "$LAB_USER":"$LAB_USER" "$BASE"

# ---------------------------------------------------------------------
# 10. Avertissements d'outillage
# ---------------------------------------------------------------------
for p in sar iostat mpstat pidstat lsof strace ltrace gdb tcpdump ss \
         conntrack smartctl stress-ng fio dig curl; do
  command -v "$p" >/dev/null 2>&1 || \
    echo "  note : $p n'est pas installé (voir §16.1)"
done
if [ -f /etc/default/sysstat ] && \
   ! grep -q '^ENABLED="true"' /etc/default/sysstat; then
  echo "  note : la collecte sar est désactivée (voir §16.1) — sans elle,"
  echo "         aucun historique et donc aucun « avant » à comparer"
fi

cat <<EOF

Prêt.
  $BIN/vitrine-api.py        frontal HTTP (port 8080)
  $BIN/vitrine-dep.py        dépendance interne (127.0.0.1:8081)
  $BIN/vitrine-charge.sh     générateur de charge
  $ETC/api.env               environnement du frontal
  $DATA                      volume de données (image loop ${TAILLE_MO} Mo)
  $BASE/modeles/             post-mortem et runbook à remplir
  $BASE/bin/tirage-pannes.sh tirage de l'examen blanc (D16)

Vérification :
  systemctl is-active vitrine-api.service vitrine-dep.service
  curl -s http://127.0.0.1:8080/sante
  curl -s http://127.0.0.1:8080/produits
  curl -s http://127.0.0.1:8080/commande
EOF
