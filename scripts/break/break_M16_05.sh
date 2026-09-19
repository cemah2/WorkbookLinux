#!/usr/bin/env bash
# break_M16_05.sh — panne BF16.5 (ports éphémères / conntrack épuisés)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
CONF=/etc/sysctl.d/99-m16-05-reseau.conf
mkdir -p "$SAUV"

# --- sauvegarde des valeurs courantes -----------------------------------
if [ ! -f "$SAUV/M16_05.env" ]; then
  {
    printf 'ip_local_port_range=%s\n' \
      "$(sysctl -n net.ipv4.ip_local_port_range | tr '\t' ' ')"
    printf 'tcp_fin_timeout=%s\n' "$(sysctl -n net.ipv4.tcp_fin_timeout)"
    if [ -f /proc/sys/net/netfilter/nf_conntrack_max ]; then
      printf 'nf_conntrack_max=%s\n' \
        "$(cat /proc/sys/net/netfilter/nf_conntrack_max)"
    fi
  } > "$SAUV/M16_05.env"
fi

# --- la panne -----------------------------------------------------------
# Un « durcissement réseau » recopié d'un billet de blog : la plage de
# ports éphémères tombe à onze ports, et le suivi de connexions à 256
# entrées. Tant qu'il y a peu de trafic, personne ne voit rien.
{
  echo "# durcissement reseau - ticket CHG-1187"
  echo "net.ipv4.ip_local_port_range = 32768 32778"
  echo "net.ipv4.tcp_fin_timeout = 120"
  if [ -f /proc/sys/net/netfilter/nf_conntrack_max ]; then
    echo "net.netfilter.nf_conntrack_max = 256"
  fi
} > "$CONF"
chmod 0644 "$CONF"

sysctl -q -p "$CONF" >/dev/null 2>&1 || {
  sysctl -q -w net.ipv4.ip_local_port_range="32768 32778" || true
  sysctl -q -w net.ipv4.tcp_fin_timeout=120 || true
}

cat <<'EOF'

Symptôme attendu : l'endpoint /produits répond parfois normalement,
parfois en erreur 502. Le journal applicatif alterne entre succès et
« OSError: [Errno 99] Cannot assign requested address ». Le réseau est
joignable : ping et curl manuels fonctionnent... la plupart du temps.
Pour reproduire : bash /opt/vitrine/bin/vitrine-charge.sh /produits 10 30
EOF
