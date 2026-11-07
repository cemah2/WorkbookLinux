#!/usr/bin/env bash
# break_M11_01.sh — panne BF11.1 (fstab fautif : la VM ne démarre plus)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
#
# ATTENTION : cette panne empêche RÉELLEMENT le démarrage. Prends un
# snapshot Proxmox avant (qm snapshot 9003 avant-bf11-1) et prépare-toi
# à utiliser la console noVNC : le SSH ne répondra pas.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
CIBLE=/srv/factura/archives
MARQUE="# break_M11_01"
mkdir -p "$SAUV" "$CIBLE"

# --- sauvegarde de l'état avant de casser -------------------------------
[ -f "$SAUV/M11_01.fstab" ] || cp -a /etc/fstab "$SAUV/M11_01.fstab"

# --- on retire une éventuelle exécution précédente ----------------------
FAUX="9c1f7a30-2b4e-4d81-a5c6-7e0f3b9d1234"
sed -i "/$FAUX/d" /etc/fstab
sed -i "\|^$MARQUE|d" /etc/fstab

# --- on neutralise la ligne correcte, si l'apprenant en a posé une ------
# (elle est conservée, simplement commentée, pour que la réparation
#  consiste bien à corriger un UUID et non à en inventer un)
awk -v c="$CIBLE" '
  $0 !~ /^[[:space:]]*#/ && $2 == c { print "#break# " $0; next }
  { print }
' /etc/fstab > /etc/fstab.new && mv /etc/fstab.new /etc/fstab

# --- la ligne fautive ---------------------------------------------------
# UUID plausible mais qui ne correspond à aucun volume de la machine.
# Pas de nofail, pass=2 : l'échec entraîne local-fs.target, donc
# emergency.target. Le marqueur est sur sa propre ligne : une ligne de
# fstab ne doit compter que six champs.
printf '%s (panne volontaire)\nUUID=%s  %s  ext4  defaults  0  2\n' \
  "$MARQUE" "$FAUX" "$CIBLE" >> /etc/fstab

[ -d /run/systemd/system ] && systemctl daemon-reload >/dev/null 2>&1 || true

cat <<'EOF'

Symptôme attendu : après « sudo reboot », la VM ne répond plus en SSH.
Dans la console Proxmox, le démarrage s'arrête environ 1 min 30 s sur
« A start job is running for /dev/disk/by-uuid/9c1f... », puis affiche
« Dependency failed for Local File Systems » et
« You are in emergency mode ».

Rappel : console Proxmox obligatoire, le réseau n'est pas démarré.
EOF
