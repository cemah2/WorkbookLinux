#!/usr/bin/env bash
# break_M13_01.sh — panne BF13.1 (routeur qui ne relaie plus)
# À lancer sur lab-adm, L13.1 en place. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
F=/etc/sysctl.d/99-durcissement.conf

[ -f "$SAUV/M13_01.ip_forward" ] \
  || sysctl -n net.ipv4.ip_forward > "$SAUV/M13_01.ip_forward"
if [ -f "$F" ] && [ ! -f "$SAUV/M13_01.durcissement.orig" ]; then
  cp -a "$F" "$SAUV/M13_01.durcissement.orig"
fi

# le "profil de durcissement standard" impose l'absence de forwarding
if ! grep -qs '^net.ipv4.ip_forward *= *0' "$F"; then
  {
    [ -f "$F" ] && cat "$F"
    printf '\n# profil de durcissement standard (audit)\n'
    printf 'net.ipv4.ip_forward = 0\n'
    printf 'net.ipv4.conf.all.send_redirects = 0\n'
  } > "$F.tmp" && mv "$F.tmp" "$F"
fi
# un fichier "plus tardif" laissé par le lab l'emporterait : on le neutralise
[ -f /etc/sysctl.d/99-minidocker.conf ] && {
  mv /etc/sysctl.d/99-minidocker.conf "$SAUV/M13_01.minidocker.conf" 2>/dev/null \
    || true
}
sysctl -q --system >/dev/null 2>&1 || true
sysctl -qw net.ipv4.ip_forward=0

cat <<'EOF'

Symptôme attendu : depuis c1, ping 172.20.0.12 et ping 172.20.0.1 répondent,
ping 10.10.10.11 reste muet. Depuis lab-web, curl http://10.10.10.10:8080/
expire. nft list ruleset n'a pas changé. Un collègue dit avoir « appliqué le
durcissement sysctl standard ».
EOF
