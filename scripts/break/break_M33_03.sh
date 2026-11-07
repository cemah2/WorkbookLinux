#!/usr/bin/env bash
# break_M33_03.sh — panne BF33.3 (RPM republié sans sa signature)
# À lancer sur lab-adm, en tant que mathieu (SANS sudo), L33.4 terminé. Idempotent.
# La phrase de passe de la clé du dépôt est demandée (signature de repomd.xml).
# Sauvegarde dans ~/lab33/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "à lancer SANS sudo" >&2; exit 1; }
L="$HOME/lab33"
D="$L/publication/rpm/el9/x86_64"
[ -f "$L/cle.env" ] || { echo "$L/cle.env absent (FPR, SUB) : termine L33.4 d'abord" >&2; exit 1; }
[ -f "$HOME/.ssh/id_depot" ] || { echo "clé ~/.ssh/id_depot absente : termine L33.4 (étape 4) d'abord" >&2; exit 1; }
# shellcheck disable=SC1091
. "$L/cle.env"
RPM=$(find "$D" -maxdepth 1 -name 'lab33-sante-*.rpm' ! -name '*.src.rpm' 2>/dev/null | sort -V | tail -1)
[ -n "$RPM" ] || { echo "aucun RPM lab33-sante dans $D : termine L33.4 (étape 3) d'abord" >&2; exit 1; }
SAUV="$L/.breakfix-backup"
mkdir -p "$SAUV"
[ -f "$SAUV/M33_03.$(basename "$RPM")" ] || cp -p "$RPM" "$SAUV/M33_03.$(basename "$RPM")"

# « republié depuis le poste de secours » : le RPM d'origine, jamais signé
rpmsign --delsign "$RPM" >/dev/null 2>&1 || true
createrepo_c --update "$D" >/dev/null
gpg --batch --yes --local-user "${SUB}!" --detach-sign --armor "$D/repodata/repomd.xml"
rsync -a --delete --delay-updates -e "ssh -i $HOME/.ssh/id_depot" \
      "$L/publication/" depot@lab-web.lab.local:

cat <<EOF

Sur lab-rhel, pour voir la panne comme une nouvelle machine :
  sudo dnf remove -y lab33-sante
  sudo dnf clean metadata
  sudo dnf install lab33-sante

Symptôme attendu : dnf télécharge $(basename "$RPM") puis refuse de
l'installer, avec un message sur sa signature. « dnf makecache » ne signale
pourtant aucune erreur sur les métadonnées du dépôt.
EOF
