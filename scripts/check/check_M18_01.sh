#!/usr/bin/env bash
# check_M18_01.sh — vérifie le lab L18.1 (installation de Docker Engine)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L18.1 =="

# --- 1. paquets et provenance ------------------------------------------
if dpkg -s docker-ce >/dev/null 2>&1; then
  ok "le paquet docker-ce est installé"
  if apt-cache policy docker-ce 2>/dev/null | grep -q 'download.docker.com'; then
    ok "docker-ce provient du dépôt download.docker.com"
  else
    ko "docker-ce ne vient pas de download.docker.com (apt-cache policy docker-ce)"
  fi
else
  ko "docker-ce n'est pas installé (dépôt officiel, pas docker.io ni snap)"
fi
dpkg -s docker.io >/dev/null 2>&1 \
  && ko "le paquet docker.io d'Ubuntu est encore présent : retire-le" \
  || ok "pas de paquet docker.io"
snap list 2>/dev/null | grep -q '^docker ' \
  && ko "le snap docker est présent : retire-le" \
  || ok "pas de snap docker"
for p in docker-compose-plugin docker-buildx-plugin containerd.io; do
  dpkg -s "$p" >/dev/null 2>&1 && ok "$p installé" \
    || ko "$p manquant (apt install $p)"
done

# --- 2. service ---------------------------------------------------------
[ "$(systemctl is-active docker 2>/dev/null)" = active ] \
  && ok "docker.service est actif" \
  || ko "docker.service n'est pas actif (systemctl status docker)"
[ "$(systemctl is-enabled docker 2>/dev/null)" = enabled ] \
  && ok "docker.service démarre au boot" \
  || ko "docker.service n'est pas enabled"

# --- 3. daemon.json -----------------------------------------------------
DJ=/etc/docker/daemon.json
if [ -r "$DJ" ] && jq . "$DJ" >/dev/null 2>&1; then
  ok "daemon.json existe et est du JSON valide"
  [ "$(jq -r '."log-opts"."max-size" // empty' "$DJ")" = "10m" ] \
    && ok "log-opts max-size=10m" \
    || ko "log-opts.max-size doit valoir \"10m\" dans daemon.json"
  [ "$(jq -r '."log-opts"."max-file" // empty' "$DJ")" = "3" ] \
    && ok "log-opts max-file=3" \
    || ko "log-opts.max-file doit valoir \"3\" (chaîne) dans daemon.json"
  jq -e '."insecure-registries" | index("lab-ops.lab.local:5000")' "$DJ" \
    >/dev/null 2>&1 \
    && ok "lab-ops.lab.local:5000 déclaré en insecure-registries" \
    || note "lab-ops.lab.local:5000 absent des insecure-registries \
(normal si L18.5 est déjà fait en TLS)"
else
  ko "$DJ absent ou invalide (jq . $DJ)"
fi

# --- 4. accès sans sudo, plugins ----------------------------------------
if docker info >/dev/null 2>&1; then
  ok "docker info fonctionne pour $(id -un) sans sudo"
  [ "$(docker info --format '{{.LoggingDriver}}')" = json-file ] \
    && ok "driver de journalisation json-file" \
    || ko "le driver de journalisation n'est pas json-file"
  [ "$(docker info --format '{{.CgroupVersion}}')" = 2 ] \
    && ok "cgroup v2" || ko "cgroup v1 détecté : inattendu sur Ubuntu 24.04"
else
  ko "docker info échoue : $(id -un) n'est pas dans le groupe docker, \
ou la session n'a pas été rouverte"
fi
id -nG "${SUDO_USER:-$(id -un)}" | tr ' ' '\n' | grep -qx docker \
  && ok "l'utilisateur est membre du groupe docker" \
  || ko "l'utilisateur n'est pas dans le groupe docker (usermod -aG docker)"
docker compose version >/dev/null 2>&1 \
  && ok "docker compose (v2) répond" || ko "docker compose ne répond pas"
docker buildx version >/dev/null 2>&1 \
  && ok "docker buildx répond" || ko "docker buildx ne répond pas"

# --- 5. rapport ---------------------------------------------------------
R="$HOME/lab18/rapports/installation.md"
if [ -s "$R" ] && grep -qiE 'root' "$R" && grep -qiE 'overlay2' "$R"; then
  ok "rapport installation.md présent (groupe docker = root, overlay2)"
else
  ko "rapport $R absent ou incomplet (conclusion sur le groupe docker, \
driver de stockage)"
fi
note "la variante rootless (kevin) et Podman ne sont pas vérifiées ici"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
