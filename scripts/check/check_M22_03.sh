#!/usr/bin/env bash
# check_M22_03.sh — vérifie le lab L22.3 (volumes, UID, réseau, filtrage)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L22.3 =="

C=factura-visites
DATA=/srv/factura-docker/data
cinsp() { docker inspect "$C" --format "$1" 2>/dev/null; }

docker info >/dev/null 2>&1 || { ko "Docker inaccessible (L22.1)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. volume ----------------------------------------------------------
if docker volume inspect factura-data >/dev/null 2>&1; then
  ok "le volume factura-data existe"
  MP=$(docker volume inspect factura-data --format '{{.Mountpoint}}')
  sudo test -s "$MP/visites.log" 2>/dev/null \
    && ok "factura-data contient visites.log" \
    || ko "factura-data ne contient pas de visites.log (étape 1)"
else
  ko "volume factura-data absent (docker volume create factura-data)"
fi
ls "$HOME"/lab22/rapports/factura-data*.tgz >/dev/null 2>&1 \
  && ok "sauvegarde du volume présente dans ~/lab22/rapports/" \
  || ko "aucune archive factura-data*.tgz dans ~/lab22/rapports/"

# --- 2. bind mount et UID ----------------------------------------------
if [ -d "$DATA" ]; then
  OWN=$(stat -c %u "$DATA"); MODE=$(stat -c %a "$DATA")
  [ "$OWN" = 10001 ] && ok "$DATA appartient à l'UID 10001" \
    || ko "$DATA appartient à l'UID $OWN, l'API écrit avec 10001"
  if (( ${MODE: -1} & 2 )); then
    ko "$DATA est en $MODE : « autres » peuvent écrire (chmod 777 interdit)"
  else
    ok "$DATA en $MODE, pas d'écriture pour « autres »"
  fi
  [ -s "$DATA/visites.log" ] && ok "visites.log écrit dans le bind mount" \
    || ko "pas de visites.log dans $DATA (l'API a-t-elle pu écrire ?)"
else
  ko "$DATA absent : relance setup_M22.sh"
fi

# --- 3. réseau ----------------------------------------------------------
docker network inspect factura-net >/dev/null 2>&1 \
  && ok "réseau factura-net présent" \
  || ko "réseau factura-net absent (docker network create factura-net)"
for c in cache "$C"; do
  if [ "$(docker inspect "$c" --format '{{.State.Running}}' 2>/dev/null)" \
    = true ]; then
    ok "conteneur $c en cours d'exécution"
    docker inspect "$c" --format '{{range $k, $_ := .NetworkSettings.Networks}}{{$k}} {{end}}' \
      | grep -qw factura-net && ok "$c est attaché à factura-net" \
      || ko "$c n'est pas sur factura-net"
  else
    ko "conteneur $c absent ou arrêté"
  fi
done
[ -z "$(docker inspect cache --format '{{.HostConfig.PortBindings}}' \
  2>/dev/null | tr -d 'map[]')" ] \
  && ok "cache ne publie aucun port" \
  || ko "cache publie un port : Redis ne doit pas être joignable de l'hôte"

# --- 4. durcissement ----------------------------------------------------
[ "$(cinsp '{{.HostConfig.ReadonlyRootfs}}')" = true ] \
  && ok "$C : racine en lecture seule" || ko "$C : --read-only manquant"
cinsp '{{.HostConfig.CapDrop}}' | grep -qi all \
  && ok "$C : --cap-drop ALL" || ko "$C : --cap-drop ALL manquant"
cinsp '{{.HostConfig.SecurityOpt}}' | grep -q no-new-privileges \
  && ok "$C : no-new-privileges" || ko "$C : --security-opt \
no-new-privileges manquant"
MEM=$(cinsp '{{.HostConfig.Memory}}')
[ "${MEM:-0}" = $((128 * 1024 * 1024)) ] \
  && ok "$C : limite mémoire 128 Mo" \
  || ko "$C : --memory 128m attendu (lu : ${MEM:-aucune})"
[ "$(cinsp '{{.HostConfig.MemorySwap}}')" = "$MEM" ] \
  && ok "$C : swap désactivé (--memory-swap = --memory)" \
  || ko "$C : --memory-swap doit être égal à --memory"
[ "$(cinsp '{{.HostConfig.RestartPolicy.Name}}')" = unless-stopped ] \
  && ok "$C : --restart unless-stopped" \
  || ko "$C : politique de redémarrage attendue : unless-stopped"
cinsp '{{json .HostConfig.Tmpfs}}' | grep -q '/tmp' \
  && ok "$C : /tmp en tmpfs" || ko "$C : --tmpfs /tmp manquant"

# --- 5. publication et DOCKER-USER ------------------------------------
cinsp '{{json .HostConfig.PortBindings}}' | grep -q '"8000/tcp"' \
  && ok "$C publie son port 8000" || ko "$C ne publie pas le port 8000"
curl -fsS --max-time 3 http://127.0.0.1:8000/compteur 2>/dev/null \
  | grep -q compteur && ok "/compteur répond via Redis" \
  || ko "/compteur ne répond pas (REDIS_URL, réseau, cache ?)"
if sudo iptables -S DOCKER-USER 2>/dev/null | grep -q '10.10.10.10'; then
  ok "règle DOCKER-USER mentionnant 10.10.10.10 présente"
else
  ko "aucune règle DOCKER-USER pour 10.10.10.10 (sudo iptables -S \
DOCKER-USER)"
fi
[ -s "$HOME/lab22/rapports/stockage.md" ] \
  && ok "rapport stockage.md présent" \
  || ko "~/lab22/rapports/stockage.md absent"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
