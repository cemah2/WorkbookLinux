#!/usr/bin/env bash
# setup_M32.sh — prépare le terrain du module 32 (systèmes de fichiers avancés)
# À lancer avec sudo sur lab-db, APRÈS avoir ajouté les quatre disques lab32-3..6
# (voir 32.1). Idempotent.
#
# Repère les disques par leur numéro de série, écrit leurs chemins stables dans
# ~/lab32/disques.env, installe le programme à corriger de L32.1. Ne formate rien.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
BASE="$LAB_HOME/lab32"

echo "== Préparation du module 32 =="
install -d -o "$LAB_USER" -g "$LAB_USER" -m 755 "$BASE" "$BASE/defi" "$BASE/banc"
install -d -m 755 /srv/lab32 /srv/lab32/ext4 /srv/lab32/xfs /srv/lab32/banc /srv/lab32/archives
install -d -m 755 /var/lib/lab32

# --- 1. les disques, par numéro de série -----------------------------------------
udevadm settle 2>/dev/null || true
ENV="$BASE/disques.env"
: > "$ENV.tmp"
manque=0
for pair in A:lab32-3 B:lab32-4 C:lab32-5 D:lab32-6; do
  var=${pair%%:*} serie=${pair#*:}
  nom=$(lsblk -dno NAME,SERIAL | awk -v s="$serie" '$2==s{print $1}' | head -1)
  if [ -z "$nom" ]; then
    echo "   $serie : INTROUVABLE (qm set 9003 --scsiN local-lvm:3,discard=on,ssd=1,serial=$serie)"
    manque=1; continue
  fi
  lien=""
  for l in /dev/disk/by-id/*; do
    [ "$(readlink -f "$l")" = "/dev/$nom" ] || continue
    case "$l" in *"$serie"*) lien=$l; break ;; esac
    [ -z "$lien" ] && lien=$l
  done
  [ -n "$lien" ] || lien=/dev/$nom
  usage=$(lsblk -no FSTYPE "/dev/$nom" | grep -v '^$' | sort -u | paste -sd, - || true)
  printf '%s=%s\n' "$var" "$lien" >> "$ENV.tmp"
  printf '   %s = %-48s (/dev/%s, %s)\n' "$var" "$lien" "$nom" "${usage:-vierge}"
done
mv "$ENV.tmp" "$ENV"; chown "$LAB_USER": "$ENV"
[ "$manque" -eq 0 ] || { echo "disques manquants : ajoute-les depuis le nœud Proxmox" >&2; exit 1; }

# garde-fou : aucun de ces disques ne doit porter le système
. "$ENV"
racine=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null | head -1)
for d in "$A" "$B" "$C" "$D"; do
  [ "$(basename "$(readlink -f "$d")")" != "$racine" ] || {
    echo "ERREUR : $d est le disque système" >&2; exit 1; }
done

# --- 2. le programme à corriger (L32.1, étape 5) -------------------------------
cat > /usr/local/bin/lab32-sauve-etat <<'PY'
#!/usr/bin/env python3
"""lab32-sauve-etat — enregistre l'avancement d'un traitement (module 32).
Usage : lab32-sauve-etat <valeur>
Écrit /var/lib/lab32/etat.json et annonce « état sauvegardé »."""
import json
import sys
import time

CHEMIN = "/var/lib/lab32/etat.json"
etat = {"valeur": sys.argv[1] if len(sys.argv) > 1 else "0", "horodatage": time.time()}
with open(CHEMIN, "w") as f:          # ouvre et TRONQUE le fichier en place
    json.dump(etat, f)
print("état sauvegardé")               # … sans rien garantir
PY
chmod 755 /usr/local/bin/lab32-sauve-etat
echo "   programme à corriger : /usr/local/bin/lab32-sauve-etat"

# --- 3. bilan -------------------------------------------------------------------------
echo
echo "== Prérequis =="
ok()    { printf '  [ OK ] %s\n' "$1"; }
avert() { printf '  [AVERT] %s\n' "$1"; }
for c in mkfs.btrfs zpool mkfs.xfs fio filefrag; do
  command -v "$c" >/dev/null && ok "$c présent" || avert "$c absent (voir 32.1 : paquets)"
done
modinfo zfs >/dev/null 2>&1 && ok "module ZFS disponible pour ce noyau" \
                             || avert "module ZFS absent (noyau sans zfs.ko ?)"
mem=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
ok "mémoire : $mem Mo (l'ARC sera limité à 256 Mio en L32.3)"
echo
echo "Charge les chemins avec :  . ~/lab32/disques.env"
