#!/usr/bin/env bash
# break_M22_01.sh — panne BF22.1 (script shell en PID 1 : boucle et stop lent)
# Idempotent. Ne modifie rien sur l'hôte hors /opt/factura-docker/bf/01.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
BF=/opt/factura-docker/bf
SAUV=/root/.breakfix-backup
REF=/opt/factura-docker/api
mkdir -p "$SAUV" "$BF"

[ -f "$REF/app.py" ] || { echo "$REF/app.py absent : lance setup_M22.sh" >&2; exit 1; }
command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || {
  echo "Docker n'est pas installé ou ne tourne pas : fais d'abord le lab L22.1" >&2
  exit 1; }

# image de base commune aux Break & Fix (construite une seule fois)
construire_base() {
  docker image inspect factura-bf:base >/dev/null 2>&1 && return 0
  mkdir -p "$BF/base"
  cp "$REF/app.py" "$REF/requirements.txt" "$BF/base/"
  cat > "$BF/base/Dockerfile" <<'DEOF'
FROM python:3.12-slim-bookworm
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
ENTRYPOINT ["python3", "app.py"]
DEOF
  echo "construction de l'image factura-bf:base (une fois)…"
  docker build -q -t factura-bf:base "$BF/base" >/dev/null
}

mkdir -p "$BF/01"
cp "$REF/app.py" "$REF/requirements.txt" "$BF/01/"

cat > "$BF/01/start.sh" <<'SEOF'
#!/bin/sh
# start.sh — lance l'API et surveille son demarrage (equipe precedente)
echo "[start] lancement de l'API"
python3 /app/app.py &
echo "[start] API lancee, pid $!"
for i in 1 2 3 4 5 6; do
  sleep 5
  if python3 -c "import urllib.request as u; \
u.urlopen('http://127.0.0.1:8000/sante', timeout=2)" 2>/dev/null; then
    echo "[start] verification $i : OK"
  else
    echo "[start] verification $i : KO"
  fi
done
echo "[start] surveillance terminee, tout est en ordre"
SEOF
chmod 0755 "$BF/01/start.sh"

cat > "$BF/01/Dockerfile" <<'DEOF'
FROM python:3.12-slim-bookworm
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py start.sh ./
EXPOSE 8000
CMD sh /app/start.sh
DEOF

echo "construction de l'image factura-legacy:2.3…"
docker build -q -t factura-legacy:2.3 "$BF/01" >/dev/null
docker rm -f factura-legacy >/dev/null 2>&1 || true
docker run -d --name factura-legacy --restart always -p 8001:8000 \
  factura-legacy:2.3 >/dev/null

cat <<'EOF2'

Symptôme attendu : le conteneur factura-legacy (http://127.0.0.1:8001)
répond pendant une trentaine de secondes, puis « docker ps » le montre
en Restarting (0), puis il répond à nouveau, et ainsi de suite.
« docker stop factura-legacy » prend 10 secondes.
Les sources de l'image sont dans /opt/factura-docker/bf/01/.
EOF2
