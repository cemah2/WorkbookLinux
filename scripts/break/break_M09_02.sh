#!/usr/bin/env bash
# break_M09_02.sh — panne BF9.2 (dépôt tiers non vérifiable : NO_PUBKEY)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
DEPOT=/srv/depot-lab
SRC=/etc/apt/sources.list.d/depot-lab.sources
LEGACY=/etc/apt/sources.list.d/depot-lab.list
mkdir -p "$SAUV"

[ -f "$DEPOT/InRelease" ] || {
  echo "$DEPOT absent : lance d'abord setup_M09.sh" >&2; exit 1; }

# --- sauvegarde de l'existant -----------------------------------------
for f in "$SRC" "$LEGACY" /etc/apt/keyrings/depot-lab.gpg; do
  base="$(basename "$f")"
  if [ -e "$f" ] && [ ! -e "$SAUV/M09_02.$base" ]; then
    cp -a "$f" "$SAUV/M09_02.$base"
  fi
done

# --- la casse ----------------------------------------------------------
# 1. on retire la clé du trousseau apt et toute trace de confiance
rm -f /etc/apt/keyrings/depot-lab.gpg \
      /etc/apt/trusted.gpg.d/depot-lab.gpg \
      /usr/share/keyrings/depot-lab.gpg
rm -f "$SRC"

# 2. on réécrit la source à l'ancienne : format une ligne, aucun
#    signed-by. C'est exactement le copier-coller qu'on trouve encore
#    dans la moitié des tutoriels en ligne.
cat > "$LEGACY" <<'EOF'
# Depot interne de l'equipe socle — ajoute en urgence pendant l'astreinte
deb http://127.0.0.1:8099 ./
EOF
chmod 0644 "$LEGACY"

# 3. le paquet a été purgé « pour repartir propre » pendant l'astreinte :
#    impossible de le réinstaller tant que le dépôt n'est pas vérifiable
if dpkg -s outil-lab >/dev/null 2>&1; then
  dpkg-query -W -f '${Version}\n' outil-lab > "$SAUV/M09_02.version" \
    2>/dev/null || true
  DEBIAN_FRONTEND=noninteractive apt-get -y purge outil-lab \
    >/dev/null 2>&1 || dpkg --purge --force-all outil-lab >/dev/null 2>&1
fi

# 4. le dépôt HTTP doit répondre, sinon le symptôme est faussé
if [ -d /run/systemd/system ]; then
  systemctl start depot-lab.service >/dev/null 2>&1 || true
fi

# 5. purge des index déjà validés pour ce dépôt : sans ça, apt réutilise
#    l'ancien index signé et l'erreur reste un simple avertissement.
rm -f /var/lib/apt/lists/*8099* /var/lib/apt/lists/*depot?lab* \
      /var/lib/apt/lists/*srv_depot* 2>/dev/null || true

apt-get update >/dev/null 2>&1 || true

cat <<'EOF'

Symptôme attendu : « sudo apt update » se termine sur un W: puis un E:
concernant le dépôt http://127.0.0.1:8099, et « sudo apt install
outil-lab » répond « E: Unable to locate package outil-lab » alors que
le dépôt est bien joignable (curl http://127.0.0.1:8099/Packages
fonctionne).
EOF
