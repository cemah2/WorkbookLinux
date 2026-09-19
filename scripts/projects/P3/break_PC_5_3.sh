#!/usr/bin/env bash
# break_PC_5_3.sh — ticket PC.5.3 (lab-ops)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SAUV=/root/.breakfix-backup; ID=PC_5_3; mkdir -p "$SAUV"
cat /proc/sys/kernel/random/boot_id > "$SAUV/$ID.boot_id"
date +%s > "$SAUV/$ID.debut"

# On crée un petit système de fichiers dédié avec PEU d'inodes, monté là
# où un processus « bavard » écrit des milliers de petits fichiers de
# session : les inodes s'épuisent alors que l'espace reste libre.
# (On n'attaque pas le vrai /var/lib/docker : on reproduit fidèlement le
#  symptôme sur un volume jetable monté au même usage.)
IMG=/var/lib/factura-inodes.img
DIR=/var/lib/factura-cache
mkdir -p "$DIR"
if ! mountpoint -q "$DIR"; then
  [ -f "$IMG" ] || dd if=/dev/zero of="$IMG" bs=1M count=64 status=none
  # ~1500 inodes seulement
  mkfs.ext4 -q -N 1536 -F "$IMG" 2>/dev/null
  mount -o loop "$IMG" "$DIR"
fi

# le processus qui remplit les inodes
cat > /usr/local/sbin/factura-sessioncache <<EOF
#!/usr/bin/env bash
set -uo pipefail
D=$DIR
i=0
while :; do
  i=\$((i+1))
  printf '' > "\$D/sess-\$i.tmp" 2>/dev/null || sleep 30
done
EOF
chmod 0755 /usr/local/sbin/factura-sessioncache
pgrep -f factura-sessioncache >/dev/null \
  || setsid nohup /usr/local/sbin/factura-sessioncache >/dev/null 2>&1 </dev/null &
# on attend l'épuisement des inodes
for _ in $(seq 1 30); do
  FREE=$(df -i --output=iavail "$DIR" | tail -1 | tr -dc 0-9)
  [ "${FREE:-1}" -le 1 ] && break
  sleep 1
done

cat <<'EOF'

Symptôme attendu : les écritures échouent avec « No space left on device »
alors que « df -h /var/lib/factura-cache » montre le volume quasi vide.
Indice : compare df -h et df -i.
EOF
