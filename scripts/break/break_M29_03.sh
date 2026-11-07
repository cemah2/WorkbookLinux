#!/usr/bin/env bash
# break_M29_03.sh — panne BF29.3 (fencing impossible : mauvaise correspondance)
# À lancer sur lab-ha1, avec sudo. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
[ "$(hostname -s)" = lab-ha1 ] || { echo "à lancer sur lab-ha1" >&2; exit 1; }
command -v pcs >/dev/null || { echo "pcs absent : termine L29.3" >&2; exit 1; }
cibadmin -Q 2>/dev/null | grep -q 'id="fence-pve"' || {
  echo "ressource fence-pve absente : termine L29.3" >&2; exit 1; }
cibadmin -Q 2>/dev/null | grep -q '<group id="grp-batch"' || {
  echo "groupe grp-batch absent : termine L29.4" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
[ -f "$SAUV/M29_03.pcmk_host_map" ] || \
  crm_resource -r fence-pve -g pcmk_host_map > "$SAUV/M29_03.pcmk_host_map"

# la « faute de frappe » d'une modification récente
pcs stonith update fence-pve pcmk_host_map="lab-ha1:9021;lab-ha2:9220"

# le service doit tourner sur lab-ha2 au moment de la panne
pcs resource move grp-batch lab-ha2 >/dev/null 2>&1 || true
for _ in $(seq 30); do
  crm_resource --locate -r grp-batch 2>/dev/null | grep -q 'lab-ha2' && break
  sleep 2
done
pcs resource clear grp-batch >/dev/null 2>&1 || true

cat <<'EOF'

grp-batch tourne maintenant sur lab-ha2. Simule sa panne : sur lab-ha2,

  sudo nft add table inet panne
  sudo nft add chain inet panne e '{ type filter hook input priority 0; }'
  sudo nft add chain inet panne s '{ type filter hook output priority 0; }'
  sudo nft add rule inet panne e udp dport 5405 drop
  sudo nft add rule inet panne s udp dport 5405 drop

Symptôme attendu (sur lab-ha1, après une minute) : lab-ha2 en UNCLEAN dans
« pcs status », grp-batch arrêté, et il ne redémarre pas sur lab-ha1.
EOF
