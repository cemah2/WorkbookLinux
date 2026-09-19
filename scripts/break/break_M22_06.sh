#!/usr/bin/env bash
# break_M22_06.sh — panne BF22.6 (limite de PID du cgroup atteinte)
# Idempotent. Ne modifie rien sur l'hôte hors /opt/factura-docker/bf/06.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
BF=/opt/factura-docker/bf
SAUV=/root/.breakfix-backup
REF=/opt/factura-docker/api
mkdir -p "$SAUV" "$BF/06"

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
construire_base

# le traitement par lots : 24 ouvriers en parallèle par lot
cat > "$BF/06/lots.sh" <<'SHEOF'
#!/usr/bin/env bash
# lots.sh — traite des lots de 24 taches en parallele, sans fin.
n=1
while :; do
  echo "$(date +%T) lot $n : lancement de 24 ouvriers"
  for i in $(seq 1 24); do
    ( sleep $((RANDOM % 5 + 4)); echo "  ouvrier $i termine" ) &
  done
  wait
  echo "$(date +%T) lot $n termine"
  n=$((n + 1))
  sleep 5
done
SHEOF
chmod 0755 "$BF/06/lots.sh"

docker rm -f factura-lots >/dev/null 2>&1 || true
docker run -d --name factura-lots --restart unless-stopped \
  --pids-limit 12 -v "$BF/06/lots.sh:/lots.sh:ro" \
  --entrypoint /lots.sh factura-bf:base >/dev/null

cat <<'EOF2'

Symptôme attendu : dans une minute, docker logs factura-lots répète
« fork: retry: Resource temporarily unavailable », aucun lot ne se termine,
et docker exec -it factura-lots bash échoue avec « OCI runtime exec failed …
resource temporarily unavailable ». L'hôte, lui, a de la mémoire, du disque
et des PID à revendre.
EOF2
