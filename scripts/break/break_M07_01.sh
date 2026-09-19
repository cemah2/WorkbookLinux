#!/usr/bin/env bash
# break_M07_01.sh — panne BF7.1 : la purge nocturne efface tout
# Installe un script de purge buggé + son jeu de données, puis déclenche
# une exécution nocturne pour que le symptôme soit visible.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab07"
BF="$BASE/bf1"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

[ -d "$BASE" ] || { echo "$BASE absent : lance d'abord setup_M07.sh" >&2; \
  exit 1; }

# --- sauvegarde de l'état précédent -------------------------------------
if [ -f "$BASE/bin/purge-archives.sh" ] && \
   [ ! -f "$SAUV/M07_01.purge-archives.sh" ]; then
  cp -a "$BASE/bin/purge-archives.sh" "$SAUV/M07_01.purge-archives.sh"
fi

# --- jeu de données : une graine intacte, restaurable à volonté ---------
rm -rf "$BF"
mkdir -p "$BF/.seed/archives"/{prod,recette}

seed() {
  local sous="$1" nom="$2" jours="$3"
  printf 'archive factice %s\n' "$nom" > "$BF/.seed/archives/$sous/$nom"
  touch -d "$jours days ago" "$BF/.seed/archives/$sous/$nom"
}

seed prod    'factura-2026-08-20.tar.gz'   29
seed prod    'factura-2026-09-03.tar.gz'   15
seed prod    'factura-2026-09-14.tar.gz'    4
seed prod    'factura-2026-09-17.tar.gz'    1
seed prod    'export final.tar.gz'         30
seed recette 'recette-2026-08-25.tar.gz'   24
seed recette 'recette-2026-09-16.tar.gz'    2
seed recette 'dump du soir.tar.gz'         18

cat > "$BF/.seed/purge.conf" <<'EOF'
# purge.conf — configuration de la purge nocturne
# 12/09 : clé renommée pour s'aligner sur les variables ansible
sous_repertoire=prod
retention_jours=7
EOF

cp -a "$BF/.seed/archives" "$BF/archives"
cp -a "$BF/.seed/purge.conf" "$BF/purge.conf"

cat > "$BF/restaure-jeu.sh" <<'EOF'
#!/usr/bin/env bash
# remet le jeu de données de BF7.1 dans son état initial
set -euo pipefail
BF="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$BF/archives" "$BF/purge.conf"
cp -a "$BF/.seed/archives"  "$BF/archives"
cp -a "$BF/.seed/purge.conf" "$BF/purge.conf"
echo "jeu de données restauré"
EOF
chmod 755 "$BF/restaure-jeu.sh"

# --- le script fautif ---------------------------------------------------
cat > "$BASE/bin/purge-archives.sh" <<EOF
#!/bin/bash
# purge-archives.sh — purge nocturne des archives factura
# Tourne toutes les nuits. Personne ne l'a relu depuis 2024.

BASE=$BF
CONF=\$BASE/purge.conf

SOUS=\$(grep sous_dossier \$CONF | cut -d= -f2)
JOURS=\$(grep retention_jours \$CONF | cut -d= -f2)

cd \$BASE/archives/\$SOUS

echo "purge de \$BASE/archives/\$SOUS (> \$JOURS jours)"

for f in \$(ls)
do
  if [ \$(find . -maxdepth 1 -name "\$f" -mtime +\$JOURS | wc -l) = 1 ]
  then
    echo "  vieux : \$f"
  fi
done

rm -rf \$BASE/archives/\$SOUS/*

echo "purge terminee"
EOF
chmod 755 "$BASE/bin/purge-archives.sh"
chown "$LAB_USER":"$LAB_USER" "$BASE/bin/purge-archives.sh"
chown -R "$LAB_USER":"$LAB_USER" "$BF"

# --- une exécution « nocturne » pour produire le symptôme ---------------
sudo -u "$LAB_USER" bash "$BASE/bin/purge-archives.sh" >/dev/null 2>&1 || true

cat <<'EOF'

Symptôme attendu : la purge nocturne devait ne toucher qu'au sous-répertoire
prod et n'y supprimer que les archives de plus de 7 jours. Résultat au matin :
~/lab07/bf1/archives est entièrement vide — prod ET recette ont disparu, y
compris l'archive d'hier. Le script n'a affiché aucune erreur et s'est terminé
par "purge terminee" avec un code de retour 0.
Le jeu de données se remet à zéro avec : bash ~/lab07/bf1/restaure-jeu.sh
EOF
