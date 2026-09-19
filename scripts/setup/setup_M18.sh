#!/usr/bin/env bash
# setup_M18.sh — prépare le terrain du module 18 (Docker et Compose)
# À lancer avec sudo sur lab-ops. Idempotent : relançable sans effet de bord.
#
# Ce script N'INSTALLE PAS Docker : c'est le travail du lab L18.1. Il dépose
# uniquement l'application « factura-api » à conteneuriser (une petite API
# Flask), une seconde version « mal faite » à corriger, et le bac à sable
# de l'apprenant dans ~/lab18/.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab18"
REF=/opt/factura-docker          # copie de référence, propriété de root
DATA=/srv/factura-docker/data    # répertoire hôte pour les bind mounts

echo "== Préparation du module 18 =="
echo "   utilisateur : $LAB_USER"
echo "   base        : $BASE"

for outil in unshare nsenter lsns python3 curl; do
  command -v "$outil" >/dev/null 2>&1 || {
    echo "outil manquant : $outil (voir §18.1)" >&2; exit 1; }
done

mkdir -p "$REF/api" "$REF/mauvaise/donnees" "$DATA"
chown root:root "$DATA"; chmod 0755 "$DATA"

# ---------------------------------------------------------------------
# 1. factura-api : l'application de référence (propre, à conteneuriser)
# ---------------------------------------------------------------------
cat > "$REF/api/app.py" <<'PYEOF'
#!/usr/bin/env python3
"""factura-api — API de démonstration à conteneuriser (workbook, module 18).

Variables d'environnement reconnues :
  APP_VERSION             affichée sur / et /version         (défaut dev)
  BIND_ADDR               adresse d'écoute                   (défaut 0.0.0.0)
  PORT                    port d'écoute                      (défaut 8000)
  DATA_DIR                répertoire où /visites écrit un fichier
  REDIS_URL               ex. redis://cache:6379/0  (route /compteur)
  DATABASE_URL            ex. postgresql://factura@db:5432/factura
  DATABASE_PASSWORD_FILE  fichier contenant le mot de passe PostgreSQL
  FACTURA_*               renvoyées telles quelles par /env

Routes : /  /sante  /version  /env  /visites  /compteur  /clients
         /fuite?mo=N (alloue N Mo et les garde : démo --memory)
"""
import os
import signal
import socket
import sys
import time

from flask import Flask, jsonify, request

APP_VERSION = os.environ.get("APP_VERSION", "dev")
BIND_ADDR = os.environ.get("BIND_ADDR", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8000"))
DATA_DIR = os.environ.get("DATA_DIR", "")
REDIS_URL = os.environ.get("REDIS_URL", "")
DATABASE_URL = os.environ.get("DATABASE_URL", "")
DATABASE_PASSWORD_FILE = os.environ.get("DATABASE_PASSWORD_FILE", "")
DEMARRAGE = time.time()
LEST = []

app = Flask(__name__)


def log(msg):
    print(f"[factura-api] {msg}", flush=True)


@app.get("/")
def racine():
    return jsonify(service="factura-api", version=APP_VERSION,
                   hote=socket.gethostname(), pid=os.getpid(),
                   uid=os.getuid(), uptime_s=round(time.time() - DEMARRAGE))


@app.get("/sante")
def sante():
    return jsonify(statut="ok")


@app.get("/version")
def version():
    return jsonify(version=APP_VERSION)


@app.get("/env")
def env():
    return jsonify({k: v for k, v in os.environ.items()
                    if k.startswith("FACTURA_")})


@app.get("/visites")
def visites():
    if not DATA_DIR:
        return jsonify(erreur="DATA_DIR non defini"), 503
    chemin = os.path.join(DATA_DIR, "visites.log")
    with open(chemin, "a", encoding="utf-8") as f:
        f.write(f"{time.strftime('%FT%T')} {request.remote_addr}\n")
    with open(chemin, encoding="utf-8") as f:
        n = sum(1 for _ in f)
    return jsonify(visites=n, fichier=chemin)


@app.get("/compteur")
def compteur():
    if not REDIS_URL:
        return jsonify(erreur="REDIS_URL non defini"), 503
    import redis
    r = redis.Redis.from_url(REDIS_URL, socket_connect_timeout=2)
    return jsonify(compteur=r.incr("factura:compteur"))


def _connexion_pg():
    import psycopg
    mdp = None
    if DATABASE_PASSWORD_FILE:
        with open(DATABASE_PASSWORD_FILE, encoding="utf-8") as f:
            mdp = f.read().strip()
    return psycopg.connect(DATABASE_URL, password=mdp, connect_timeout=3)


@app.get("/clients")
def clients():
    if not DATABASE_URL:
        return jsonify(erreur="DATABASE_URL non defini"), 503
    with _connexion_pg() as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS clients "
                     "(id serial PRIMARY KEY, nom text NOT NULL)")
        n = conn.execute("SELECT count(*) FROM clients").fetchone()[0]
    return jsonify(clients=n)


@app.post("/clients")
def ajouter_client():
    if not DATABASE_URL:
        return jsonify(erreur="DATABASE_URL non defini"), 503
    nom = (request.get_json(silent=True) or {}).get("nom") \
        or request.args.get("nom", "anonyme")
    with _connexion_pg() as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS clients "
                     "(id serial PRIMARY KEY, nom text NOT NULL)")
        conn.execute("INSERT INTO clients (nom) VALUES (%s)", (nom,))
    return jsonify(ajoute=nom), 201


@app.get("/fuite")
def fuite():
    mo = int(request.args.get("mo", "50"))
    LEST.append(bytearray(mo * 1024 * 1024))
    return jsonify(alloue_mo=sum(len(b) for b in LEST) // (1024 * 1024))


def arret(signum, _frame):
    log(f"signal {signal.Signals(signum).name} recu : arret propre")
    sys.exit(0)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, arret)
    signal.signal(signal.SIGINT, arret)
    log(f"demarrage version={APP_VERSION} sur {BIND_ADDR}:{PORT} "
        f"pid={os.getpid()} uid={os.getuid()}")
    app.run(host=BIND_ADDR, port=PORT, threaded=True, use_reloader=False)
PYEOF

cat > "$REF/api/requirements.txt" <<'EOF'
flask==3.0.3
redis==5.0.8
psycopg[binary]==3.2.1
EOF

cat > "$REF/api/README.md" <<'EOF'
# factura-api

API Flask de démonstration. Lancement local : `pip install -r
requirements.txt && python3 app.py`. Écoute sur 0.0.0.0:8000.
Le Dockerfile, le .dockerignore et le compose.yaml sont à écrire (module 18).
EOF

# ---------------------------------------------------------------------
# 2. La version « mal faite » : même application, Dockerfile à corriger
# ---------------------------------------------------------------------
cp "$REF/api/app.py" "$REF/mauvaise/app.py"

cat > "$REF/mauvaise/Dockerfile" <<'EOF'
FROM python:latest
ADD . /app
WORKDIR /app
RUN apt-get update
RUN apt-get install -y curl vim git
RUN pip install flask redis psycopg[binary]
ENV DATABASE_URL=postgresql://factura:Factura-2024@db:5432/factura
ENV FACTURA_CLE_API=sk-prod-9f8e7d6c5b4a
EXPOSE 8000
CMD sh /app/start.sh
EOF

cat > "$REF/mauvaise/start.sh" <<'EOF'
#!/bin/sh
echo "[start] verification de l'environnement"
echo "[start] lancement de l'API"
python3 /app/app.py
EOF
chmod 0755 "$REF/mauvaise/start.sh"

cat > "$REF/mauvaise/secret.txt" <<'EOF'
mot de passe du registre : Registre-2024
EOF

# un « gros » fichier qui n'a rien à faire dans le contexte de build
if [ ! -s "$REF/mauvaise/donnees/export-clients.bin" ]; then
  dd if=/dev/urandom of="$REF/mauvaise/donnees/export-clients.bin" \
     bs=1M count=64 status=none
fi

cat > "$REF/mauvaise/README.md" <<'EOF'
# factura-api (version de l'équipe précédente)

Build : `docker build -t factura-api .` puis `docker run -d -p 8000:8000
factura-api`. Ça marche sur le poste de Kevin.
EOF

chown -R root:root "$REF"
chmod -R u=rwX,go=rX "$REF"

# ---------------------------------------------------------------------
# 3. Bac à sable de l'apprenant
# ---------------------------------------------------------------------
mkdir -p "$BASE"/{api,mauvaise,compose,registre,rapports,bin}
if [ ! -f "$BASE/api/app.py" ]; then
  cp "$REF/api/"{app.py,requirements.txt,README.md} "$BASE/api/"
fi
if [ ! -f "$BASE/mauvaise/Dockerfile" ]; then
  cp -r "$REF/mauvaise/." "$BASE/mauvaise/"
fi
chown -R "$LAB_USER:$LAB_USER" "$BASE"

# ---------------------------------------------------------------------
# 4. Rappels
# ---------------------------------------------------------------------
cat <<EOF

Terrain prêt.
  application de référence : $REF/api/          (copie : $BASE/api/)
  application à corriger   : $REF/mauvaise/     (copie : $BASE/mauvaise/)
  répertoire hôte (bind)   : $DATA  (root:root, 0755 — c'est voulu)

Docker n'est PAS installé par ce script : commence par le lab L18.1.
Une fois Docker installé, vérifie que $LAB_USER peut l'utiliser sans sudo :
  docker info >/dev/null && echo OK
EOF
