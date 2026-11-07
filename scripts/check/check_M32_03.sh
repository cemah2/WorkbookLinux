#!/usr/bin/env bash
# check_M32_03.sh — vérifie le lab L32.3 (ZFS)
# À lancer avec sudo sur lab-db.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L32.3 =="
[ "$(id -u)" -eq 0 ] || { ko "à lancer avec sudo"; fin; }
command -v zpool >/dev/null || { ko "ZFS absent (apt install zfsutils-linux)"; fin; }

# --- ARC ---------------------------------------------------------------------------
[ "$(cat /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null)" = 268435456 ] \
  && ok "ARC limité à 256 Mio (en cours)" || ko "zfs_arc_max n'est pas à 268435456"
grep -qs 'zfs_arc_max=268435456' /etc/modprobe.d/*.conf && ok "limite persistante (modprobe.d)" \
                                                       || ko "limite non persistante dans /etc/modprobe.d/"

# --- pool tank ------------------------------------------------------------------------
if zpool list -H tank >/dev/null 2>&1; then
  ST=$(zpool status -P tank)
  [ "$(zpool list -H -o health tank)" = ONLINE ] && ok "tank ONLINE" || ko "tank : $(zpool list -H -o health tank)"
  grep -q 'mirror-0' <<<"$ST" && ok "tank en miroir" || ko "tank n'est pas un miroir"
  grep -Eq '/dev/disk/by-id/' <<<"$ST" && ! grep -Eq '^\s+/dev/sd[a-z]+[0-9]*\s' <<<"$ST" \
    && ok "disques désignés par identifiant (by-id)" || ko "le pool utilise des noms /dev/sdX"
  [ "$(zpool get -H -o value ashift tank)" = 12 ] && ok "ashift=12" || ko "ashift attendu : 12"
  grep -Eq 'scrub repaired [1-9]|repaired [0-9.]+[KMG]' <<<"$ST" \
    && ok "un scrub a réparé des données" \
    || note "pas de réparation visible (zpool clear fait ? scrub relancé ?) : vérifie l'étape 4"
else
  ko "pool tank absent"; fin
fi

g() { zfs get -H -o value "$1" "$2" 2>/dev/null; }
[ "$(g compression tank/donnees)" = zstd ] && ok "tank/donnees : compression zstd" || ko "tank/donnees : compression zstd attendue"
[ "$(g atime tank/donnees)" = off ] && ok "tank/donnees : atime=off" || ko "tank/donnees : atime=off attendu"
[ "$(g quota tank/donnees)" = 1G ] && ok "tank/donnees : quota 1G" || ko "tank/donnees : quota 1G attendu"
[ "$(g recordsize tank/pg)" = 16K ] && ok "tank/pg : recordsize 16K" || ko "tank/pg : recordsize 16K attendu"
[ "$(g reservation tank/pg)" = 200M ] && ok "tank/pg : réservation 200M" || ko "tank/pg : réservation 200M attendue"

# --- réplication ------------------------------------------------------------------------
if zpool list -H sauve >/dev/null 2>&1; then
  ok "pool sauve présent"
  src=$(zfs list -H -t snapshot -o name -d 1 tank/donnees 2>/dev/null | sed 's|.*@||' | sort)
  dst=$(zfs list -H -t snapshot -o name -d 1 sauve/donnees 2>/dev/null | sed 's|.*@||' | sort)
  n=$(comm -12 <(echo "$src") <(echo "$dst") | grep -c .)
  [ "$n" -ge 3 ] && ok "$n instantanés communs entre tank/donnees et sauve/donnees" \
                 || ko "$n instantané(s) en commun (3 attendus)"
else
  ko "pool sauve absent"
fi
fin
