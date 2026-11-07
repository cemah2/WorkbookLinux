#!/usr/bin/env bash
# check_M32_02.sh — vérifie le lab L32.2 (Btrfs) ; à lancer AVANT L32.3
# À lancer avec sudo sur lab-db.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L32.2 =="
[ "$(id -u)" -eq 0 ] || { ko "à lancer avec sudo"; fin; }
H=$(getent passwd "${SUDO_USER:-mathieu}" | cut -d: -f6)/lab32
# shellcheck disable=SC1091
. "$H/disques.env" 2>/dev/null || { ko "lab32/disques.env absent (setup_M32.sh)"; fin; }
M=/srv/btrfs

[ "$(findmnt -no FSTYPE "$M")" = btrfs ] && ok "$M monté en Btrfs" || { ko "$M n'est pas un Btrfs monté"; fin; }
findmnt -no OPTIONS "$M" | grep -q 'compress=zstd' && ok "compression zstd active" || ko "pas de compress=zstd"
findmnt -no OPTIONS "$M" | grep -q 'degraded' && ko "monté en degraded" || ok "pas monté en degraded"

S=$(btrfs filesystem show "$M" 2>/dev/null)
grep -qi 'missing' <<<"$S" && ko "un disque manque au volume" || ok "aucun disque manquant"
devs=$(awk '/devid/{print $NF}' <<<"$S" | xargs -n1 readlink -f | sort | paste -sd' ' -)
b=$(readlink -f "$B"); d=$(readlink -f "$D")
grep -qw "$b" <<<"$devs" && grep -qw "$d" <<<"$devs" \
  && ok "membres : \$B et \$D (le disque perdu a été remplacé)" \
  || ko "membres actuels : $devs (attendu \$B=$b et \$D=$d)"

U=$(btrfs filesystem usage -b "$M" 2>/dev/null)
grep -Eq '^Data,RAID1' <<<"$U" && grep -Eq '^Metadata,RAID1' <<<"$U" \
  && ok "données et métadonnées en RAID1" || ko "profils attendus : Data,RAID1 et Metadata,RAID1"
if grep -E '^(Data|Metadata|System),single:.*Used:[1-9]' <<<"$U" >/dev/null; then
  ko "des morceaux « single » contiennent des données : balance -dconvert=raid1,soft"
else
  ok "aucun morceau single utilisé"
fi

UU=$(blkid -s UUID -o value "$b")
grep -Eq "^UUID=${UU}[[:space:]]+${M}[[:space:]]+btrfs" /etc/fstab && ok "ligne fstab par UUID" \
                                                             || ko "pas de ligne fstab UUID=… $M btrfs"
grep -E "[[:space:]]${M}[[:space:]]" /etc/fstab | grep -q nofail && ok "fstab : nofail" \
                                                              || ko "fstab : nofail absent"

btrfs subvolume list -r "$M" 2>/dev/null | grep -q . && ok "au moins un instantané en lecture seule" \
                                                    || ko "aucun instantané en lecture seule"
btrfs scrub status "$M" 2>/dev/null | grep -Eqi 'corrected|no errors found|error summary' \
  && ok "un scrub a été lancé" || ko "aucun scrub dans l'historique"
n=$(ls "$H"/*.btrfs 2>/dev/null | wc -l)
[ "$n" -ge 2 ] && ok "$n flux btrfs send dans lab32/" || ko "il faut deux flux send (complet + incrémental) dans lab32/"
fin
