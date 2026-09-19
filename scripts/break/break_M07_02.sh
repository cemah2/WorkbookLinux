#!/usr/bin/env bash
# break_M07_02.sh — panne BF7.2 : la sauvegarde dit toujours OK
# Installe un script de sauvegarde buggé et une source partiellement
# illisible, puis laisse une exécution derrière lui.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab07"
BF="$BASE/bf2"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

[ -d "$BASE" ] || { echo "$BASE absent : lance d'abord setup_M07.sh" >&2; \
  exit 1; }

if [ -f "$BASE/bin/sauve-conf.sh" ] && \
   [ ! -f "$SAUV/M07_02.sauve-conf.sh" ]; then
  cp -a "$BASE/bin/sauve-conf.sh" "$SAUV/M07_02.sauve-conf.sh"
fi

# --- source à sauvegarder : un fichier n'est pas lisible par l'apprenant -
rm -rf "$BF"
mkdir -p "$BF/source/etc" "$BF/source/srv" "$BF/coffre"
printf 'listen=8080\nworkers=4\n'            > "$BF/source/etc/app.conf"
printf 'id;client;montant\n1;ACME;1240.00\n' > "$BF/source/srv/rapport.csv"
head -c 120000 /dev/urandom                  > "$BF/source/srv/blob.bin"
chown -R "$LAB_USER":"$LAB_USER" "$BF"

# le grain de sable : une clé privée déposée par une autre équipe, en 0600
# root. tar la voit, ne peut pas la lire, et sort en erreur… dans un pipe.
printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\n(fictive)\n' \
  > "$BF/source/etc/deploy.key"
chown root:root "$BF/source/etc/deploy.key"
chmod 600 "$BF/source/etc/deploy.key"

# --- le script fautif ---------------------------------------------------
cat > "$BASE/bin/sauve-conf.sh" <<EOF
#!/bin/bash
# sauve-conf.sh — sauvegarde quotidienne de la configuration factura
# "set -e, donc si ça casse, ça s'arrête" (commentaire de l'auteur, 2024)
set -e

SRC=$BF/source
DEST=$BF/coffre
STAMP=\$(date +%F)
ARCHIVE=\$DEST/factura-\$STAMP.tar.gz

verifier_archive() {
  local taille=\$(du -h "\$ARCHIVE" | cut -f1)
  gzip -t "\$ARCHIVE"
  echo "  archive : \$taille"
  if [ "\$taille" -eq 0 ]; then
    echo "  ATTENTION archive vide"
    return 1
  fi
  return 0
}

echo "sauvegarde de \$SRC"
tar -cf - -C "\$SRC" . | gzip -9 > "\$ARCHIVE"

if verifier_archive; then
  echo "SAUVEGARDE OK (\$ARCHIVE)"
  exit 0
else
  echo "SAUVEGARDE EN ECHEC" >&2
  exit 1
fi
EOF
chmod 755 "$BASE/bin/sauve-conf.sh"
chown "$LAB_USER":"$LAB_USER" "$BASE/bin/sauve-conf.sh"

# --- une exécution pour laisser la trace du matin -----------------------
sudo -u "$LAB_USER" bash "$BASE/bin/sauve-conf.sh" \
  > "$BF/derniere-execution.log" 2>&1 || true
chown "$LAB_USER":"$LAB_USER" "$BF/derniere-execution.log"

cat <<'EOF'

Symptôme attendu : ~/lab07/bin/sauve-conf.sh affiche "SAUVEGARDE OK" et sort
en 0 toutes les nuits. La restauration de l'archive produite dans
~/lab07/bf2/coffre/ ne rend pourtant pas l'arborescence complète : il manque
des fichiers. Le journal de la dernière exécution est dans
~/lab07/bf2/derniere-execution.log.
EOF
