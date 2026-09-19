#!/usr/bin/env bash
# break_M22_04.sh — panne BF22.4 (/var/lib/docker remplit le disque)
# Idempotent. Rien à sauvegarder : l'espace est pris dans la couche
# d'écriture d'un conteneur.
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

construire_base
FICHIER=/var/tmp/export-clients-$(date +%Y%m).bin

if ! docker inspect factura-export >/dev/null 2>&1; then
  docker run -d --name factura-export --entrypoint sleep \
    --restart unless-stopped factura-bf:base infinity >/dev/null
fi

if docker exec factura-export test -f "$FICHIER" 2>/dev/null; then
  echo "le disque est déjà rempli (fichier présent)"
else
  # espace libre réel du système de fichiers de Docker, blocs réservés
  # à root compris (Docker tourne en root), moins 48 Mio de marge
  DOCKER_ROOT=$(docker info --format '{{.DockerRootDir}}')
  read -r BLOCS TAILLE_BLOC < <(stat -f -c '%f %S' "$DOCKER_ROOT")
  LIBRE=$(( BLOCS * TAILLE_BLOC ))
  TAILLE=$(( LIBRE - 48 * 1024 * 1024 ))
  [ "$TAILLE" -gt $((1024 * 1024 * 1024)) ] || {
    echo "moins de 1 Go de libre : panne non déclenchée" >&2; exit 1; }
  docker exec factura-export fallocate -l "$TAILLE" "$FICHIER"
fi

cat <<'EOF2'

Symptôme attendu : df -h / affiche 100 % d'utilisation. docker build
échoue avec « no space left on device », apt et journalctl se plaignent.
Personne n'a copié de fichier sur la VM, du -sh /home /srv /var/log ne
montre rien d'anormal.
EOF2
