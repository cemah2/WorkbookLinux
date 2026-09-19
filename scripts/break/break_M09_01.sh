#!/usr/bin/env bash
# break_M09_01.sh — panne BF9.1 (/boot plein : mise à jour du noyau impossible)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
LISTE="$SAUV/M09_01.files"

# /boot doit être une partition séparée : on ne remplit jamais la racine.
if ! findmnt -n /boot >/dev/null 2>&1; then
  echo "/boot n'est pas une partition séparée sur cette VM : scénario" >&2
  echo "inapplicable (l'installation guidée Ubuntu avec LVM en crée une)." >&2
  exit 1
fi
command -v fallocate >/dev/null 2>&1 || { echo "fallocate requis" >&2; exit 1; }

K="$(uname -r)"
# Deux versions « fantômes », plus anciennes que la courante, sans paquet.
V1="6.8.0-31-generic"; V2="6.8.0-35-generic"
for v in "$V1" "$V2"; do
  [ "$v" = "$K" ] && { echo "version fantôme = noyau courant ?!" >&2; exit 1; }
done

# Déjà cassé ? on ne refait pas le remplissage (idempotence).
if [ -s "$LISTE" ] && [ "$(df --output=avail -B1M /boot | tail -1)" -lt 16 ]
then
  :
else
  : > "$LISTE"
  # Espace à consommer : tout sauf ~6 Mo.
  AVAIL=$(df --output=avail -B1 /boot | tail -1 | tr -d ' ')
  RESTE=$((6 * 1024 * 1024))
  if [ "$AVAIL" -le $((RESTE + 40 * 1024 * 1024)) ]; then
    echo "/boot est déjà presque plein : rien à faire" >&2; exit 1
  fi
  ACONS=$((AVAIL - RESTE))
  PETIT=$((14 * 1024 * 1024))       # vmlinuz factice
  MAP=$((8 * 1024 * 1024))          # System.map factice
  # ce qui reste, réparti sur les deux initrd factices
  INITRD=$(( (ACONS - 2 * (PETIT + MAP)) / 2 ))
  for v in "$V1" "$V2"; do
    for f in "vmlinuz-$v:$PETIT" "System.map-$v:$MAP" \
             "initrd.img-$v:$INITRD"; do
      n="${f%%:*}"; s="${f##*:}"
      fallocate -l "$s" "/boot/$n" 2>/dev/null || \
        dd if=/dev/zero of="/boot/$n" bs=1M count=$((s/1024/1024)) \
           status=none 2>/dev/null || true
      echo "/boot/$n" >> "$LISTE"
    done
    printf '# fake config\n' > "/boot/config-$v"; echo "/boot/config-$v" >> "$LISTE"
  done
  sync
fi

# Le symptôme : la régénération de l'initrd échoue (sans rien abîmer :
# mkinitramfs écrit dans .new et efface en cas d'échec).
if command -v update-initramfs >/dev/null 2>&1; then
  update-initramfs -u -k "$K" >/dev/null 2>&1 || true
  # au cas où un .new aurait survécu
  rm -f "/boot/initrd.img-$K.new"
fi

cat <<'EOF2'

Symptôme attendu : « sudo apt upgrade » comme « sudo update-initramfs -u »
échouent sur « No space left on device » puis
« update-initramfs: failed for /boot/initrd.img-... with 1 ».
df -h / montre pourtant beaucoup d'espace libre.
Sauvegarde : la liste de ce qui a été ajouté est dans
/root/.breakfix-backup/M09_01.files (à ne lire qu'après avoir trouvé).
EOF2
