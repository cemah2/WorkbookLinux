#!/usr/bin/env bash
# break_M33_02.sh — panne BF33.2 (paquet d'outils qui livre un fichier déjà livré)
# À lancer sur lab-adm, en tant que mathieu (SANS sudo), L33.4 terminé. Idempotent.
# La phrase de passe de la clé du dépôt est demandée (signature de InRelease).
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "à lancer SANS sudo" >&2; exit 1; }
L="$HOME/lab33"
B="$L/reprepro"
[ -f "$B/conf/distributions" ] || { echo "$B/conf/distributions absent : termine L33.4 d'abord" >&2; exit 1; }
[ -f "$HOME/.ssh/id_depot" ]   || { echo "clé ~/.ssh/id_depot absente : termine L33.4 (étape 4) d'abord" >&2; exit 1; }
if gpg --list-secret-keys 'Dépôt lab33 (2027)' >/dev/null 2>&1 \
   && grep -q "^SignWith: $(gpg --list-secret-keys --with-colons 'Dépôt lab33 (2027)' | awk -F: '/^fpr/{print $10; exit}')" \
           "$B/conf/distributions"; then
  echo "le dépôt est encore signé par la clé de BF33.1 : répare d'abord BF33.1" >&2; exit 1
fi

O="$L/outils"
R="$O/racine"
rm -rf "$R"
mkdir -p "$R/DEBIAN" "$R/usr/bin"
cat > "$R/DEBIAN/control" <<'EOF'
Package: lab33-outils
Version: 1.0-1
Architecture: all
Maintainer: Equipe exploitation <exploitation@lab.local>
Depends: bash
Section: admin
Priority: optional
Description: petits scripts d'exploitation du parc lab33
 lab33-journaux résume les derniers passages de lab33-sante ;
 lab33-sante vérifie tous les services connus de l'équipe.
EOF
cat > "$R/usr/bin/lab33-journaux" <<'EOF'
#!/bin/bash
# lab33-journaux — derniers résultats du minuteur lab33-sante
exec journalctl -u lab33-sante.service -n "${1:-20}" --no-pager -o cat
EOF
# « une enveloppe pratique » : même nom que le binaire de lab33-sante
cat > "$R/usr/bin/lab33-sante" <<'EOF'
#!/bin/bash
# lab33-sante (outils) — vérifie la liste complète de l'équipe
exec /usr/bin/lab33-sante.bin -c /etc/lab33-outils/tous.conf "$@"
EOF
chmod 755 "$R/usr/bin/lab33-journaux" "$R/usr/bin/lab33-sante"
dpkg-deb --root-owner-group --build "$R" "$O/lab33-outils_1.0-1_all.deb" >/dev/null

reprepro -b "$B" includedeb lab33 "$O/lab33-outils_1.0-1_all.deb"
rsync -a --delete --delay-updates -e "ssh -i $HOME/.ssh/id_depot" \
      "$L/publication/" depot@lab-web.lab.local:

cat <<'EOF'

Symptôme attendu : sur lab-db (où lab33-sante est installé depuis le dépôt),
« sudo apt update && sudo apt install lab33-outils » échoue avec une erreur
de dpkg. apt conseille « apt --fix-broken install », qui ne règle rien.
EOF
