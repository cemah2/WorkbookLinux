#!/usr/bin/env bash
# setup_M16.sh — prépare le terrain du module 16
#                (journalisation, rsyslog, logrotate, supervision)
# À lancer avec sudo. Idempotent : relançable sans effet de bord.
#
# Ce script N'ÉCRIT AUCUNE configuration logrotate ni rsyslog : les écrire
# est le travail du module. Il installe l'application de démonstration
# « factura », ses unités systemd, une semaine d'historique de journaux,
# des échantillons de journaux système, et rejoue l'incident INC-4102.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab16"
BIN=/opt/factura/bin
ETC=/etc/factura
LOGD=/var/log/factura
NGXD=/var/log/nginx
ECH="$BASE/echantillons"
MARQ=/var/lib/factura/.setup-m16

command -v python3 >/dev/null 2>&1 || {
  echo "python3 est requis (voir §16.1)" >&2; exit 1; }

echo "== Préparation du module 16 =="
echo "   utilisateur : $LAB_USER"
echo "   base        : $BASE"

SYSTEMD=0
[ -d /run/systemd/system ] && SYSTEMD=1
[ "$SYSTEMD" -eq 1 ] || echo "   (systemd absent : les unités ne seront pas démarrées)"

# ---------------------------------------------------------------------
# 1. Compte de service, répertoires
# ---------------------------------------------------------------------
groupadd -f factura
if ! getent passwd factura >/dev/null; then
  useradd -r -g factura -d /srv/factura -s /usr/sbin/nologin factura
fi
# groupe « adm » : présent sur Ubuntu, pas toujours sur Rocky.
getent group adm >/dev/null || groupadd -r adm

mkdir -p "$BIN" "$ETC" "$LOGD" "$NGXD" /srv/factura /var/lib/factura \
         "$BASE" "$ECH" "$BASE/inc-4102" "$BASE/rapports"
chown root:root /opt/factura "$BIN" "$ETC"
chmod 0755 /opt/factura "$BIN" "$ETC"
chown factura:adm "$LOGD"
chmod 0750 "$LOGD"
chown -R "$LAB_USER":"$LAB_USER" "$BASE"

# ---------------------------------------------------------------------
# 2. factura-api.py — le service dont on lit les journaux
#    Deux modes : rejeu de l'incident (FACTURA_REJEU=1) et régime normal.
# ---------------------------------------------------------------------
cat > "$BIN/factura-api.py" <<'PYEOF'
#!/usr/bin/env python3
"""factura-api — service de démonstration (workbook, module 16).

Écrit sur stdout/stderr. Sous systemd, journald interprète le préfixe
« <N> » en tête de ligne comme la sévérité syslog du message : c'est le
mécanisme le plus simple pour qu'une application donne son niveau de log
sans dépendre de libsystemd.

Variables d'environnement :
  FACTURA_REJEU=1    rejoue l'incident INC-4102 puis sort en 1
  FACTURA_FORMAT     texte (défaut) | json
  FACTURA_PERIODE    secondes entre deux lignes en régime normal (défaut 20)
"""
import json
import os
import random
import sys
import time
import uuid

FORMAT = os.environ.get("FACTURA_FORMAT", "texte")
PERIODE = float(os.environ.get("FACTURA_PERIODE", "20"))

SEV = {"debug": 7, "info": 6, "notice": 5, "warning": 4,
       "err": 3, "crit": 2}


def emet(niveau, message, **champs):
    """Une ligne de log, préfixée de sa sévérité syslog."""
    if FORMAT == "json":
        corps = {"niveau": niveau, "message": message}
        corps.update(champs)
        texte = json.dumps(corps, ensure_ascii=False)
    else:
        extra = " ".join("%s=%s" % (k, v) for k, v in champs.items())
        texte = "%s %s" % (message, extra) if extra else message
    flux = sys.stderr if SEV[niveau] <= 4 else sys.stdout
    flux.write("<%d>%s\n" % (SEV[niveau], texte))
    flux.flush()


def rid():
    return uuid.uuid4().hex[:12]


def rejeu():
    """Incident INC-4102 : le batch d'export monopolise le pool."""
    emet("info", "demarrage factura-api", version="2.4.1", workers=4,
         pool_max=20)
    emet("notice", "pool PostgreSQL initialise", taille=20,
         hote="10.10.10.12")
    emet("info", "batch factura-exports demarre", req_id=rid(),
         connexions_demandees=20)
    for i in range(6):
        emet("info", "requete traitee", req_id=rid(), route="/api/factures",
             duree_ms=random.randint(40, 90), statut=200)
    emet("warning", "pool de connexions sature", en_service=20, taille=20,
         attente_ms=3200)
    for i in range(10):
        emet("warning", "attente d'une connexion libre", req_id=rid(),
             attente_ms=random.randint(4000, 9500))
    for i in range(14):
        emet("err", "echec d'obtention d'une connexion apres 30s",
             req_id=rid(), route="/api/factures", statut=502)
    emet("err", "psycopg2.OperationalError: connection pool exhausted",
         req_id=rid())
    emet("warning", "consommation memoire du worker 3", rss_mo=1480,
         seuil_mo=1024)
    emet("crit", "worker 3 termine par le noyau (signal 9)", pid=os.getpid())
    emet("err", "arret de factura-api : 3 workers sur 4 indisponibles")
    return 1


def normal():
    emet("info", "demarrage factura-api", version="2.4.1", workers=4,
         pool_max=20)
    routes = ["/api/factures", "/api/clients", "/sante", "/api/exports"]
    while True:
        r = random.random()
        if r < 0.03:
            emet("err", "requete en echec", req_id=rid(),
                 route=random.choice(routes), statut=500)
        elif r < 0.10:
            emet("warning", "requete lente", req_id=rid(),
                 route=random.choice(routes),
                 duree_ms=random.randint(1200, 4000))
        else:
            emet("info", "requete traitee", req_id=rid(),
                 route=random.choice(routes),
                 duree_ms=random.randint(12, 180), statut=200)
        time.sleep(PERIODE)


if __name__ == "__main__":
    if os.environ.get("FACTURA_REJEU") == "1" or "--rejeu" in sys.argv:
        sys.exit(rejeu())
    try:
        normal()
    except KeyboardInterrupt:
        emet("notice", "arret demande")
PYEOF

# ---------------------------------------------------------------------
# 3. factura-bruyant.sh — le service qui inonde le journal
# ---------------------------------------------------------------------
cat > "$BIN/factura-bruyant.sh" <<'BREOF'
#!/usr/bin/env bash
# factura-bruyant — simule un service mal configuré en niveau debug.
# FACTURA_DEBIT : messages par seconde (défaut 200)
# FACTURA_RAFALE : nombre de messages par rafale (défaut 400), puis pause
set -uo pipefail
DEBIT="${FACTURA_DEBIT:-200}"
RAFALE="${FACTURA_RAFALE:-0}"
n=0
if [ "$RAFALE" -gt 0 ]; then
  while :; do
    for _ in $(seq 1 "$RAFALE"); do
      n=$((n+1))
      printf '<7>trace debug interne seq=%d etat=ok\n' "$n"
    done
    sleep 20
  done
fi
pause=$(awk -v d="$DEBIT" 'BEGIN {printf "%.4f", 1/d}')
while :; do
  n=$((n+1))
  printf '<7>trace debug interne seq=%d etat=ok\n' "$n"
  sleep "$pause"
done
BREOF

# ---------------------------------------------------------------------
# 4. factura-ecrivain.py — écrit dans un FICHIER, descripteur conservé.
#    Sert aux labs logrotate : mode append (propre) ou mode position
#    absolue (reproduit le trou de copytruncate).
# ---------------------------------------------------------------------
cat > "$BIN/factura-ecrivain.py" <<'ECEOF'
#!/usr/bin/env python3
"""factura-ecrivain — écrit des lignes numérotées dans un fichier et
garde son descripteur ouvert, comme une application qui ne sait pas
rouvrir son log.

  --fichier CHEMIN   fichier cible (défaut /var/log/factura/acces.log)
  --periode N        secondes entre deux lignes (défaut 1)
  --sans-append      ouvre SANS O_APPEND : après une troncature, le
                     noyau remplit de zéros jusqu'à la position courante
  --hup              rouvre le fichier sur réception de SIGHUP
"""
import argparse
import os
import signal
import sys
import time

p = argparse.ArgumentParser()
p.add_argument("--fichier", default="/var/log/factura/acces.log")
p.add_argument("--periode", type=float, default=1.0)
p.add_argument("--sans-append", action="store_true")
p.add_argument("--hup", action="store_true")
a = p.parse_args()

etat = {"fd": None, "rouvrir": False}


def ouvrir():
    drapeaux = os.O_WRONLY | os.O_CREAT
    if not a.sans_append:
        drapeaux |= os.O_APPEND
    fd = os.open(a.fichier, drapeaux, 0o640)
    if a.sans_append:
        os.lseek(fd, 0, os.SEEK_END)
    return fd


def sur_hup(signum, frame):
    etat["rouvrir"] = True


if a.hup:
    signal.signal(signal.SIGHUP, sur_hup)

etat["fd"] = ouvrir()
n = 0
try:
    while True:
        n += 1
        ligne = "%s seq=%d service=factura-acces etat=ok\n" % (
            time.strftime("%Y-%m-%dT%H:%M:%S%z"), n)
        os.write(etat["fd"], ligne.encode())
        if etat["rouvrir"]:
            os.close(etat["fd"])
            etat["fd"] = ouvrir()
            etat["rouvrir"] = False
            sys.stderr.write("<5>fichier de log rouvert\n")
            sys.stderr.flush()
        time.sleep(a.periode)
except KeyboardInterrupt:
    pass
ECEOF

chmod 0755 "$BIN"/factura-api.py "$BIN"/factura-bruyant.sh \
           "$BIN"/factura-ecrivain.py

# ---------------------------------------------------------------------
# 5. Fichier d'environnement (pas de valeur en dur dans les unités)
# ---------------------------------------------------------------------
if [ ! -f "$ETC/api.env" ]; then
  cat > "$ETC/api.env" <<'EOF'
FACTURA_FORMAT=texte
FACTURA_PERIODE=20
FACTURA_REJEU=0
EOF
fi
chmod 0644 "$ETC/api.env"

# ---------------------------------------------------------------------
# 6. Unités systemd
# ---------------------------------------------------------------------
cat > /etc/systemd/system/factura-api.service <<'EOF'
[Unit]
Description=Factura — API de facturation (demonstration workbook)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=factura
Group=factura
EnvironmentFile=/etc/factura/api.env
ExecStart=/opt/factura/bin/factura-api.py
Restart=no
SyslogIdentifier=factura-api

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/factura-bruyant.service <<'EOF'
[Unit]
Description=Factura — collecteur de traces (service volontairement bruyant)

[Service]
Type=simple
User=factura
Group=factura
Environment=FACTURA_DEBIT=200
ExecStart=/opt/factura/bin/factura-bruyant.sh
Restart=always
RestartSec=2
SyslogIdentifier=factura-bruyant

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/factura-ecrivain.service <<'EOF'
[Unit]
Description=Factura — ecriture du journal d'acces dans un fichier

[Service]
Type=simple
User=factura
Group=factura
ExecStart=/opt/factura/bin/factura-ecrivain.py \
          --fichier /var/log/factura/acces.log --periode 1 --hup
Restart=always
RestartSec=2
SyslogIdentifier=factura-ecrivain

[Install]
WantedBy=multi-user.target
EOF

chmod 0644 /etc/systemd/system/factura-*.service

# ---------------------------------------------------------------------
# 7. Génération des journaux historiques
#    Idempotent : on ne régénère pas si le marqueur existe.
# ---------------------------------------------------------------------
if [ ! -f "$MARQ" ]; then
  echo "   génération des journaux (une dizaine de secondes)..."
  python3 - "$LOGD" "$NGXD" "$ECH" <<'GENEOF'
import datetime as dt
import gzip
import os
import random
import sys

LOGD, NGXD, ECH = sys.argv[1], sys.argv[2], sys.argv[3]
random.seed(4102)
maintenant = dt.datetime.now().replace(microsecond=0)
# Fenêtre de l'incident dans les journaux fichiers : les 40 minutes qui
# précèdent le lancement du setup.
debut = maintenant - dt.timedelta(minutes=40)

ROUTES = ["/api/factures", "/api/clients", "/api/exports", "/sante",
          "/static/app.js", "/static/logo.png"]
IPS = ["10.10.10.10", "10.10.10.14", "192.168.1.42", "192.168.1.77",
       "203.0.113.19"]
UA = ('"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/128.0 Safari/537.36"')


def rid():
    return "%012x" % random.getrandbits(48)


# --- 7.1 nginx access.log : 40 min de trafic, 502 sur les 20 dernières --
lignes = []
err = []
t = debut
while t < maintenant:
    n = random.randint(28, 55)
    for _ in range(n):
        h = t + dt.timedelta(seconds=random.randint(0, 59))
        route = random.choice(ROUTES)
        degrade = (maintenant - h).total_seconds() < 20 * 60
        if degrade and route.startswith("/api/") and random.random() < 0.55:
            statut, taille, duree = 502, 552, round(random.uniform(30, 31), 3)
            err.append(
                '%s [error] 918#918: *%d upstream timed out (110: '
                'Connection timed out) while reading response header from '
                'upstream, client: %s, server: factura.lab.local, '
                'request: "GET %s HTTP/1.1", upstream: '
                '"http://127.0.0.1:8080%s", host: "factura.lab.local"'
                % (h.strftime("%Y/%m/%d %H:%M:%S"),
                   random.randint(1000, 9999), random.choice(IPS), route,
                   route))
        else:
            statut = 200
            taille = random.randint(180, 9000)
            duree = round(random.uniform(0.008, 0.240), 3)
        lignes.append(
            '%s - - [%s] "GET %s HTTP/1.1" %d %d "-" %s %.3f'
            % (random.choice(IPS),
               h.strftime("%d/%b/%Y:%H:%M:%S +0200"),
               route, statut, taille, UA, duree))
    t += dt.timedelta(minutes=1)
lignes.sort(key=lambda s: s.split("[")[1][:20])
with open(os.path.join(NGXD, "access.log"), "w") as f:
    f.write("\n".join(lignes) + "\n")
with open(os.path.join(NGXD, "error.log"), "w") as f:
    f.write("\n".join(sorted(err)) + "\n")

# --- 7.2 factura app.log : 7 jours d'historique -------------------------
NIVEAUX = [("INFO", 78), ("DEBUG", 12), ("WARN", 7), ("ERROR", 3)]


def tire_niveau():
    x = random.randint(1, 100)
    c = 0
    for nom, poids in NIVEAUX:
        c += poids
        if x <= c:
            return nom
    return "INFO"


MSG = {
    "INFO": ["requete traitee", "cache renouvele", "export genere",
             "connexion client etablie", "tache planifiee terminee"],
    "DEBUG": ["entree dans traiter_facture()", "requete SQL preparee",
              "cache hit", "serialisation du payload"],
    "WARN": ["requete lente", "pool de connexions a 80%",
             "reessai apres echec temporaire", "certificat expire dans 12j"],
    "ERROR": ["echec d'ecriture en base", "timeout upstream",
              "payload invalide rejete", "echec d'envoi de mail"],
}

app = open(os.path.join(LOGD, "app.log"), "w")
erreurs = open(os.path.join(LOGD, "erreurs.log"), "w")
t = maintenant - dt.timedelta(days=7)
n = 0
API = [r for r in ROUTES if r.startswith("/api/")]
while t < maintenant:
    niveau = tire_niveau()
    route = random.choice(API if niveau in ("WARN", "ERROR") else ROUTES)
    ligne = ("%s factura-api[918] %-5s req_id=%s route=%s duree_ms=%d %s\n"
             % (t.strftime("%Y-%m-%dT%H:%M:%S+02:00"), niveau, rid(),
                route, random.randint(8, 3200),
                random.choice(MSG[niveau])))
    app.write(ligne)
    if niveau == "ERROR":
        erreurs.write(ligne)
    n += 1
    t += dt.timedelta(seconds=random.uniform(2, 10))
app.close()
erreurs.close()

# --- 7.3 acces.log : lignes numérotées, plus deux générations ----------
acces = open(os.path.join(LOGD, "acces.log"), "w")
t = maintenant - dt.timedelta(hours=6)
for i in range(1, 20001):
    acces.write("%s seq=%d service=factura-acces etat=ok\n"
                % ((t + dt.timedelta(seconds=i)).strftime(
                    "%Y-%m-%dT%H:%M:%S+0200"), i))
acces.close()

# --- 7.4 metier.log absent : c'est le travail de l'apprenant -----------

# --- 7.5 échantillons pour lecture (jamais dans /var/log) --------------
auth = []
t = maintenant - dt.timedelta(hours=3)
for i in range(400):
    t += dt.timedelta(seconds=random.randint(5, 40))
    h = t.strftime("%b %d %H:%M:%S")
    r = random.random()
    if r < 0.35:
        auth.append("%s lab-web sshd[%d]: Failed password for invalid user "
                    "admin from 203.0.113.%d port %d ssh2"
                    % (h, random.randint(2000, 9000),
                       random.randint(2, 250), random.randint(30000, 65000)))
    elif r < 0.55:
        auth.append("%s lab-web sshd[%d]: Accepted publickey for mathieu "
                    "from 10.10.10.10 port %d ssh2: ED25519 SHA256:"
                    "9k2Jb1vQ8mZc0pT7rXn4Ls6Yw3Ae5Uf2Hd1Gi8Ko0Pq"
                    % (h, random.randint(2000, 9000),
                       random.randint(30000, 65000)))
    elif r < 0.75:
        auth.append("%s lab-web sudo: mathieu : TTY=pts/1 ; PWD=/home/mathieu"
                    " ; USER=root ; COMMAND=/usr/bin/systemctl restart "
                    "factura-api" % h)
    else:
        auth.append("%s lab-web systemd-logind[712]: New session %d of user "
                    "mathieu." % (h, random.randint(10, 400)))
open(os.path.join(ECH, "auth.log"), "w").write("\n".join(auth) + "\n")

pg = []
t = maintenant - dt.timedelta(hours=3)
for i in range(180):
    t += dt.timedelta(seconds=random.randint(20, 120))
    h = t.strftime("%Y-%m-%d %H:%M:%S.%f")[:-3] + " CEST"
    r = random.random()
    if r < 0.15:
        pg.append("%s [%d] LOG:  duration: %.3f ms  statement: SELECT * FROM "
                  "factures WHERE client_id = %d"
                  % (h, random.randint(900, 9999),
                     random.uniform(1200, 9000), random.randint(1, 9000)))
    elif r < 0.25:
        pg.append("%s [%d] FATAL:  sorry, too many clients already"
                  % (h, random.randint(900, 9999)))
    elif r < 0.35:
        pg.append("%s [%d] WARNING:  there is already a transaction in "
                  "progress" % (h, random.randint(900, 9999)))
    else:
        pg.append("%s [%d] LOG:  checkpoint complete: wrote %d buffers "
                  "(%.1f%%); write=%.3f s, sync=%.3f s, total=%.3f s"
                  % (h, random.randint(900, 9999), random.randint(80, 4000),
                     random.uniform(0.2, 9.0), random.uniform(0.1, 3.0),
                     random.uniform(0.01, 0.9), random.uniform(0.4, 9.5)))
open(os.path.join(ECH, "postgresql-16-main.log"), "w").write(
    "\n".join(pg) + "\n")

ci = """\
2026-09-11 08:12:03,441 - stages.py[DEBUG]: Using distro class <class \
'cloudinit.distros.ubuntu.Distro'>
2026-09-11 08:12:03,512 - handlers.py[DEBUG]: start: init-network/\
check-cache: attempting to read from cache [trust]
2026-09-11 08:12:04,120 - DataSourceNoCloud.py[DEBUG]: Seeing DataSource \
NoCloud [seed=/var/lib/cloud/seed/nocloud-net]
2026-09-11 08:12:06,884 - cc_set_hostname.py[DEBUG]: Setting hostname to \
lab-web (lab-web)
2026-09-11 08:12:11,006 - cc_ssh.py[DEBUG]: Restoring authorized_keys for \
mathieu
2026-09-11 08:12:19,773 - util.py[WARNING]: Failed to run module \
scripts-user (scripts in /var/lib/cloud/instance/scripts)
2026-09-11 08:12:19,774 - util.py[DEBUG]: Failed running \
/var/lib/cloud/instance/scripts [1]
"""
open(os.path.join(ECH, "cloud-init.log"), "w").write(ci)

uu = """\
2026-09-17 06:32:01,004 INFO Starting unattended upgrades script
2026-09-17 06:32:01,118 INFO Allowed origins are: o=Ubuntu,a=noble-security
2026-09-17 06:32:47,552 INFO Packages that will be upgraded: libssl3t64 \
openssl
2026-09-17 06:32:47,552 INFO Writing dpkg log to \
/var/log/unattended-upgrades/unattended-upgrades-dpkg.log
2026-09-17 06:33:29,901 INFO All upgrades installed
2026-09-17 06:33:30,004 WARNING Found /var/run/reboot-required, rebooting \
is needed
"""
open(os.path.join(ECH, "unattended-upgrades.log"), "w").write(uu)

# une génération déjà compressée, pour montrer zcat/zgrep
with gzip.open(os.path.join(ECH, "app.log.3.gz"), "wt") as g:
    t = maintenant - dt.timedelta(days=9)
    for i in range(4000):
        t += dt.timedelta(seconds=random.uniform(3, 12))
        g.write("%s factura-api[918] INFO  req_id=%s route=%s duree_ms=%d "
                "requete traitee\n"
                % (t.strftime("%Y-%m-%dT%H:%M:%S+02:00"), rid(),
                   random.choice(ROUTES), random.randint(8, 300)))

print("   access.log : %d lignes" % len(lignes))
print("   app.log    : %d lignes" % n)
GENEOF
  touch "$MARQ"
else
  echo "   journaux déjà générés (marqueur $MARQ) — rien à refaire"
fi

chown factura:adm "$LOGD"/*.log
chmod 0640 "$LOGD"/*.log
chown -R "$LAB_USER":"$LAB_USER" "$BASE"
[ -d "$NGXD" ] && chmod 0755 "$NGXD"

# ---------------------------------------------------------------------
# 8. Rejeu de l'incident INC-4102 dans le journal systemd
# ---------------------------------------------------------------------
FEN="$BASE/inc-4102/fenetre.txt"
if [ "$SYSTEMD" -eq 1 ]; then
  systemctl daemon-reload
  if [ ! -f "$FEN" ]; then
    echo "   rejeu de l'incident INC-4102 dans le journal..."
    DEB=$(date '+%Y-%m-%d %H:%M:%S')
    sed -i 's/^FACTURA_REJEU=.*/FACTURA_REJEU=1/' "$ETC/api.env"
    systemctl start factura-api.service || true
    sleep 3
    # trace noyau contemporaine (OOM killer) : journalctl -k la verra
    printf '<4>Out of memory: Killed process 918 (factura-api) '\
'total-vm:2148600kB, anon-rss:1515208kB, file-rss:0kB, shmem-rss:0kB, '\
'UID:996 pgtables:3068kB oom_score_adj:0\n' > /dev/kmsg 2>/dev/null || true
    FIN=$(date '+%Y-%m-%d %H:%M:%S')
    sed -i 's/^FACTURA_REJEU=.*/FACTURA_REJEU=0/' "$ETC/api.env"
    systemctl reset-failed factura-api.service >/dev/null 2>&1 || true
    {
      echo "INC-4102 — fenêtre de rejeu dans le journal systemd"
      echo "DEBUT=$DEB"
      echo "FIN=$FIN"
      echo
      echo "Les journaux fichiers (/var/log/nginx/access.log,"
      echo "/var/log/factura/app.log) couvrent les 40 minutes qui"
      echo "précèdent DEBUT : la dégradation y est visible avant la"
      echo "chute du service."
    } > "$FEN"
    chown "$LAB_USER":"$LAB_USER" "$FEN"
  fi
  systemctl enable --now factura-api.service >/dev/null 2>&1 || true
  systemctl enable --now factura-ecrivain.service >/dev/null 2>&1 || true
  # factura-bruyant est installé mais PAS démarré : c'est l'apprenant qui
  # le lance quand il en a besoin (E16.10, BF16.3).
  systemctl disable factura-bruyant.service >/dev/null 2>&1 || true
else
  {
    echo "INC-4102 — pas de systemd sur cette machine."
    echo "Le rejeu dans le journal n'a pas eu lieu."
  } > "$FEN"
  chown "$LAB_USER":"$LAB_USER" "$FEN"
fi

# ---------------------------------------------------------------------
# 9. Résumé
# ---------------------------------------------------------------------
cat <<EOF

Terrain prêt.

  $BIN/factura-api.py         service journalisé (unité factura-api)
  $BIN/factura-bruyant.sh     service bruyant (unité factura-bruyant, arrêtée)
  $BIN/factura-ecrivain.py    écrivain fichier (unité factura-ecrivain)
  $LOGD/                      app.log, erreurs.log, acces.log
  $NGXD/                      access.log, error.log
  $ECH/                       auth.log, postgresql, cloud-init, .gz
  $FEN                        fenêtre de l'incident INC-4102

Aucune configuration logrotate ni rsyslog n'a été écrite : c'est le travail
du module. Commence par §16.5.
EOF
