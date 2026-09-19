#!/usr/bin/env bash
# break_M20_03.sh — panne BF20.3 : « clone-1 refuse de démarrer : fichier
# introuvable ». « Range » la base du pool lab20 dans /srv/vm/archive/ après
# avoir arrêté les clones. Idempotent. Note l'emplacement d'origine dans
# /root/.breakfix-backup/. À lancer avec sudo sur lab-virt (L20.3 fait).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
V="virsh -c qemu:///system"
DIR=/srv/vm ; BASE=ubuntu-24.04-base.qcow2
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

$V pool-info lab20 >/dev/null 2>&1 || { echo "pool lab20 absent : fais L20.3 d'abord" >&2; exit 1; }
$V dominfo clone-1 >/dev/null 2>&1 || { echo "clone-1 absente : fais L20.3 d'abord" >&2; exit 1; }

# les VM en marche gardent le fichier ouvert : il faut les arrêter d'abord
for vm in $($V list --name); do
  if $V domblklist "$vm" | grep -q "^ *vd[a-z] *$DIR/"; then
    $V destroy "$vm" >/dev/null 2>&1 || true
  fi
done

if [ -f "$DIR/$BASE" ]; then
  mkdir -p "$DIR/archive"
  echo "$DIR/$BASE -> $DIR/archive/$BASE" > "$SAUV/M20_03_emplacement.txt"
  mv "$DIR/$BASE" "$DIR/archive/$BASE"
  $V pool-refresh lab20 >/dev/null 2>&1 || true
else
  echo "la base a déjà été rangée : rien à refaire"
fi

cat <<'EOF'

Symptôme attendu : après un « rangement » de /srv/vm validé par l'équipe,
« virsh start clone-1 » échoue. L'erreur cite un fichier que clone-1 n'a
jamais eu comme disque, alors que « virsh domblklist clone-1 » montre un
disque qui existe bel et bien. clone-4, si tu l'as gardé, démarre sans
problème. Interdit de recréer les VM, de relancer clone3.sh ou de
retélécharger l'image ; le rangement ne doit pas être défait.
EOF
