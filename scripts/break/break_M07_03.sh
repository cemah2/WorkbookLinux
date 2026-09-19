#!/usr/bin/env bash
# break_M07_03.sh — panne BF7.3 : le script de déploiement part en vrille
# Installe un script de déploiement buggé, son hook, ses cibles, et laisse
# derrière lui un fichier temporaire d'une exécution précédente.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab07"
BF="$BASE/bf3"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

[ -d "$BASE" ] || { echo "$BASE absent : lance d'abord setup_M07.sh" >&2; \
  exit 1; }

if [ -f "$BASE/bin/deploy-conf.sh" ] && \
   [ ! -f "$SAUV/M07_03.deploy-conf.sh" ]; then
  cp -a "$BASE/bin/deploy-conf.sh" "$SAUV/M07_03.deploy-conf.sh"
fi

# --- terrain : modèles de conf et cibles --------------------------------
rm -rf "$BF"
mkdir -p "$BF/modeles" "$BF/cible"/{prod,recette}

cat > "$BF/modeles/app.ini" <<'EOF'
version=2.1
environnement=@ENV@
listen=0.0.0.0:8080
EOF

# le modèle livré par l'équipe applicative, avec des espaces dans le nom
cat > "$BF/modeles/conf de secours.ini" <<'EOF'
version=2.1
environnement=@ENV@
listen=127.0.0.1:8080
EOF

cat > "$BF/post-deploy.sh" <<'EOF'
#!/usr/bin/env bash
# hook appelé après chaque déploiement : trace ce qu'il reçoit
printf 'hook appelé avec %d argument(s) :\n' "$#"
i=1
for a in "$@"; do
  printf '  $%d = [%s]\n' "$i" "$a"
  i=$((i + 1))
done
EOF
chmod 755 "$BF/post-deploy.sh"
chown -R "$LAB_USER":"$LAB_USER" "$BF"

# --- le script fautif ---------------------------------------------------
cat > "$BASE/bin/deploy-conf.sh" <<EOF
#!/bin/bash
# deploy-conf.sh — rend un modèle de conf et le pousse vers un environnement
# Repris d'un ancien dépôt. "Ça marchait avant", dit l'équipe applicative.
set -u

BF=$BF
TMP=/tmp/deploy-conf.tmp
HOOK=\$BF/post-deploy.sh

ENVIRONNEMENT=""
FICHIER=""
VERBEUX=0

usage() {
  echo "usage: \$0 --env <prod|recette> --fichier <modele> [--verbeux]"
}

journal() {
  echo "[\$(date +%T)] \$*"
}

while [ \$# -gt 0 ]; do
  case \$1 in
    --env)
      ENVIRONNEMENT=\$2
      shift 2
      ;;
    --fichier)
      FICHIER=\$2
      shift 2
      ;;
    --verbeux)
      VERBEUX=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "option inconnue : \$1" >&2
      usage
      exit 1
      ;;
  esac
done

VERSION=\$(grep ^version \$FICHIER | cut -d= -f2)

if [ "\$VERSION" -eq 2 ]; then
  journal "modele en version 2, rendu standard"
fi

cp \$FICHIER \$TMP
sed "s/@ENV@/\$ENVIRONNEMENT/" \$TMP > \$TMP.rendu
cp \$TMP.rendu \$BF/cible/\$ENVIRONNEMENT/app.ini

journal "deploiement de \$FICHIER vers \$ENVIRONNEMENT (verbeux=\$VERBEUX)"

\$HOOK \$FICHIER \$ENVIRONNEMENT
EOF
chmod 755 "$BASE/bin/deploy-conf.sh"
chown "$LAB_USER":"$LAB_USER" "$BASE/bin/deploy-conf.sh"

# --- résidu d'une exécution précédente, lancée par un autre compte -------
printf 'residu d une execution precedente\n' > /tmp/deploy-conf.tmp
chown root:root /tmp/deploy-conf.tmp
chmod 600 /tmp/deploy-conf.tmp
rm -f /tmp/deploy-conf.tmp.rendu

cat <<'EOF'

Symptôme attendu : ~/lab07/bin/deploy-conf.sh ne déploie plus rien, et sort
malgré tout en 0.
  - avec --verbeux, il ne rend jamais la main et consomme 100 % d'un cœur ;
  - sans --verbeux, il affiche "[: 2.1: integer expression expected" ;
  - il n'arrive pas à écrire son fichier temporaire : "Permission denied" ;
  - avec le modèle "conf de secours.ini", grep cherche trois fichiers
    inexistants et le hook post-deploy.sh annonce 4 arguments au lieu de 2.
EOF
