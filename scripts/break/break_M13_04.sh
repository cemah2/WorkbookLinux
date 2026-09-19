#!/usr/bin/env bash
# break_M13_04.sh — panne BF13.4 (MTU VXLAN incohérent + fragments filtrés)
# À lancer sur lab-web PUIS sur lab-db (le script détecte l'hôte),
# L13.3 en place (vxlan0). Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
HOSTN=$(hostname -s)

case "$HOSTN" in
  lab-web)
    ip link show vxlan0 >/dev/null 2>&1 \
      || { echo "vxlan0 absent : L13.3 doit être en place" >&2; exit 1; }
    [ -f "$SAUV/M13_04.vxlan0.mtu" ] \
      || cat /sys/class/net/vxlan0/mtu > "$SAUV/M13_04.vxlan0.mtu"
    # "on a remis le MTU standard, 1450 c'était sûrement une erreur"
    ip link set vxlan0 mtu 1500
    ;;
  lab-db)
    [ -f "$SAUV/M13_04.ruleset.nft" ] \
      || nft list ruleset > "$SAUV/M13_04.ruleset.nft"
    # "le pare-feu du site" : les fragments IP sont jetés avant réassemblage
    nft -f - <<'EOF'
table inet sitefw {}
flush table inet sitefw
table inet sitefw {
  chain raw_in {
    type filter hook prerouting priority -450; policy accept;
    ip frag-off & 0x3fff != 0 counter drop
  }
}
EOF
    ;;
  *)
    echo "ce script se lance sur lab-web puis sur lab-db" >&2; exit 1 ;;
esac

cat <<'EOF'

Symptôme attendu (une fois lancé sur les DEUX VM) : depuis lab-web,
ping 192.168.42.12 répond et ssh par le tunnel fonctionne, mais scp d'un gros
fichier vers lab-db se fige et iperf3 -c 192.168.42.12 affiche 0 bits/sec.
Dans l'autre sens (lab-db -> lab-web), tout fonctionne. Aucune erreur nulle
part.
EOF
