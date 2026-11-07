#!/usr/bin/env bash
# break_M30_03.sh — panne BF30.3 (restauration de test sur le réseau de production)
# À lancer en root sur le nœud Proxmox. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer en root" >&2; exit 1; }
command -v qmrestore >/dev/null || { echo "à lancer sur le nœud Proxmox" >&2; exit 1; }
VMID=9103

F=$(ls -1t /var/lib/vz/dump/vzdump-qemu-9002-*.vma.zst 2>/dev/null | head -1 || true)
[ -n "$F" ] || { echo "aucune sauvegarde vzdump de 9002 : termine L30.4 d'abord" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

if ! qm config "$VMID" >/dev/null 2>&1; then
  echo "restauration de $(basename "$F") dans $VMID (cela prend quelques minutes)…"
  # l'erreur du collègue : ni --unique, ni réseau isolé
  qmrestore "$F" "$VMID" --storage local-lvm >/dev/null
  qm set "$VMID" --name lab-web-test --onboot 0 >/dev/null
  echo "$VMID restaurée depuis $F le $(date -Is)" > "$SAUV/M30_03.etat"
fi
qm status "$VMID" | grep -q running || qm start "$VMID"

cat <<'EOF'

Symptôme attendu (depuis lab-adm, dans une ou deux minutes) : les sessions
SSH vers lab-web se figent par moments, http://lab-web/ répond une fois sur
deux, « ssh-keyscan lab-web » donne toujours la même clé d'hôte, et lab-web
lui-même ne voit rien d'anormal.
EOF
