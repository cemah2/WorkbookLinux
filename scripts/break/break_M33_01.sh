#!/usr/bin/env bash
# break_M33_01.sh — panne BF33.1 (« modernisation » de la clé du dépôt apt)
# À lancer sur lab-adm, en tant que mathieu (SANS sudo), L33.4 terminé. Idempotent.
# Sauvegarde dans ~/lab33/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "à lancer SANS sudo (le trousseau GnuPG est celui de ton compte)" >&2; exit 1; }
L="$HOME/lab33"
B="$L/reprepro"
[ -f "$B/conf/distributions" ] || { echo "$B/conf/distributions absent : termine L33.4 d'abord" >&2; exit 1; }
[ -f "$HOME/.ssh/id_depot" ]   || { echo "clé ~/.ssh/id_depot absente : termine L33.4 (étape 4) d'abord" >&2; exit 1; }
SAUV="$L/.breakfix-backup"
mkdir -p "$SAUV"
[ -f "$SAUV/M33_01.distributions" ] || cp "$B/conf/distributions" "$SAUV/M33_01.distributions"

UID_NEUF='Dépôt lab33 (2027) <depot@lab.local>'
if ! gpg --list-secret-keys "$UID_NEUF" >/dev/null 2>&1; then
  # « plus simple pour la CI » : pas de phrase de passe, une seule clé qui fait tout
  gpg --batch --pinentry-mode loopback --passphrase '' \
      --quick-generate-key "$UID_NEUF" rsa3072 sign 2y 2>/dev/null
fi
NEUVE=$(gpg --list-secret-keys --with-colons "$UID_NEUF" | awk -F: '/^fpr/{print $10; exit}')

sed -i "s/^SignWith:.*/SignWith: $NEUVE/" "$B/conf/distributions"
reprepro -b "$B" export lab33 >/dev/null
gpg --armor --export "$NEUVE" > "$L/publication/lab33-2027.asc"
rsync -a --delete --delay-updates -e "ssh -i $HOME/.ssh/id_depot" \
      "$L/publication/" depot@lab-web.lab.local:

cat <<'EOF'

Symptôme attendu : sur lab-db, « sudo apt update » affiche une erreur de
signature pour lab-web.lab.local:8033 et ignore le dépôt lab33.
Le collègue : « J'ai bien publié la nouvelle clé sur le serveur, c'est
lab33-2027.asc. »
EOF
