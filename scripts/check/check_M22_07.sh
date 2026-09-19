#!/usr/bin/env bash
# check_M22_07.sh — vérifie le lab L22.6 (reconstruire Docker à la main)
# À lancer avec sudo : l'overlay et le rootfs appartiennent à root.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L22.6 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
M="$HOMEDIR/lab22/manuel"
RAP="$HOMEDIR/lab22/rapports/docker-a-la-main.md"
CFG="$M/config.json"

# --- 1. le rootfs ------------------------------------------------------
if [ -d "$M/lower" ]; then
  [ -x "$M/lower/bin/busybox" ] && ok "lower/ contient un rootfs Alpine" \
    || ko "lower/bin/busybox absent : docker export | tar -x dans lower/"
  [ -s "$M/image.tar" ] && ok "image.tar présent" \
    || note "image.tar absent (facultatif si déballé directement)"
else
  ko "$M/lower absent (étape 1)"
fi

# --- 2. overlayfs et copy-on-write ------------------------------------
if [ -d "$M/upper" ]; then
  grep -q 'fabrique-a-la-main' "$M/upper/etc/motd" 2>/dev/null \
    && ok "upper/etc/motd contient le marqueur (copy-up)" \
    || ko "upper/etc/motd ne contient pas « fabrique-a-la-main » : écris \
via merged/, pas dans lower/"
  [ -e "$M/lower/etc/motd" ] && grep -q 'fabrique' "$M/lower/etc/motd" \
    2>/dev/null && ko "lower/etc/motd a été modifié : la couche basse doit \
rester intacte" || ok "lower/ intact"
  if [ -c "$M/upper/etc/alpine-release" ]; then
    ok "upper/etc/alpine-release est un whiteout (périphérique 0,0)"
  else
    ko "pas de whiteout pour etc/alpine-release dans upper/ (rm via merged/)"
  fi
  if mountpoint -q "$M/merged" 2>/dev/null; then
    note "l'overlay est encore monté sur merged/ (umount avant tout rm -rf)"
  fi
else
  ko "$M/upper absent (étape 2)"
fi

# --- 3. le bundle OCI ---------------------------------------------------
if [ -s "$CFG" ] && jq -e . "$CFG" >/dev/null 2>&1; then
  ok "config.json est un JSON valide"
  [ "$(jq -r '.ociVersion // empty' "$CFG")" != "" ] \
    && ok "ociVersion présent (généré par runc spec)" \
    || ko "config.json sans ociVersion : pars de runc spec"
  [ "$(jq -r .hostname "$CFG")" = manuel ] && ok "hostname manuel" \
    || ko "hostname doit valoir manuel"
  [ "$(jq -r .root.path "$CFG")" = merged ] && ok "root.path = merged" \
    || ko "root.path doit pointer sur merged (lu : $(jq -r .root.path "$CFG"))"
  [ "$(jq -r .root.readonly "$CFG")" = false ] && ok "racine en écriture" \
    || ko "root.readonly doit être false"
  [ "$(jq -r .linux.cgroupsPath "$CFG")" = /factura-manuel ] \
    && ok "cgroupsPath /factura-manuel" \
    || ko "linux.cgroupsPath doit valoir /factura-manuel"
  [ "$(jq -r '.linux.resources.memory.limit // 0' "$CFG")" = 67108864 ] \
    && ok "limite mémoire 64 Mo dans le bundle" \
    || ko "linux.resources.memory.limit attendu : 67108864"
  [ "$(jq -r '.linux.resources.pids.limit // 0' "$CFG")" = 50 ] \
    && ok "limite de 50 PID dans le bundle" \
    || ko "linux.resources.pids.limit attendu : 50"
else
  ko "$CFG absent ou invalide (runc spec, puis jq)"
fi
if command -v runc >/dev/null 2>&1; then
  ST=$(runc state manuel 2>/dev/null | jq -r .status 2>/dev/null)
  case "$ST" in
    running) ok "conteneur runc « manuel » en cours d'exécution" ;;
    stopped) note "conteneur runc « manuel » en état stopped : runc delete manuel" ;;
    *)       note "aucun conteneur runc « manuel » actif (normal s'il est fini)" ;;
  esac
  [ -d /sys/fs/cgroup/factura-manuel ] && [ "$ST" != running ] \
    && note "cgroup /factura-manuel résiduel : sudo rmdir /sys/fs/cgroup/factura-manuel"
else
  ko "runc introuvable (paquet containerd.io, L22.1)"
fi

# --- 4. côté Docker ------------------------------------------------------
if docker info >/dev/null 2>&1; then
  if docker inspect docker-manuel >/dev/null 2>&1; then
    ok "conteneur docker-manuel présent"
    dinsp() { docker inspect docker-manuel --format "$1"; }
    [ "$(dinsp '{{.Config.Hostname}}')" = manuel ] && ok "hostname manuel" \
      || ko "docker-manuel : --hostname manuel attendu"
    [ "$(dinsp '{{.HostConfig.Memory}}')" = 67108864 ] \
      && ok "docker-manuel : 64 Mo" || ko "docker-manuel : --memory 64m attendu"
    [ "$(dinsp '{{.HostConfig.PidsLimit}}')" = 50 ] \
      && ok "docker-manuel : 50 PID" || ko "docker-manuel : --pids-limit 50 attendu"
  else
    ko "conteneur docker-manuel absent (étape 6)"
  fi
  if grep -q 'userns-remap' /etc/docker/daemon.json 2>/dev/null; then
    ko "userns-remap encore présent dans daemon.json : à retirer (étape 7)"
  else
    ok "userns-remap retiré de daemon.json"
  fi
  grep -q '^dockremap:' /etc/subuid 2>/dev/null \
    && ok "le compte dockremap existe : userns-remap a été activé" \
    || note "pas de dockremap dans /etc/subuid : l'étape 7 n'a pas été jouée ?"
else
  ko "Docker inaccessible (L22.1)"
fi

# --- 5. le rapport --------------------------------------------------------
if [ -s "$RAP" ]; then
  [ "$(grep -c . "$RAP")" -ge 30 ] && ok "rapport d'au moins 30 lignes" \
    || ko "rapport trop court"
  MANQUE=""
  for mot in overlay runc lsns nsenter memory.max 100000 chroot; do
    grep -qi -- "$mot" "$RAP" || MANQUE="$MANQUE $mot"
  done
  [ -z "$MANQUE" ] && ok "le rapport couvre les mécanismes attendus" \
    || ko "le rapport ne parle pas de :$MANQUE"
  grep -q '|' "$RAP" && ok "tableau comparatif présent" \
    || ko "aucun tableau (étape 6) dans le rapport"
else
  ko "rapport absent : $RAP"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
