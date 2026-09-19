#!/usr/bin/env bash
# check_PC_2_2.sh — vérifie le ticket PC.2.2 (montage NFS bloqué)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.2.2 =="
SAUV=/root/.breakfix-backup; ID=PC_2_2
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

if nft list table inet nas_coupure >/dev/null 2>&1; then
  ko "le trafic NFS est toujours bloqué (nft list ruleset)"
else
  ok "plus de blocage du trafic NFS"
fi

if timeout 5 ls /mnt/archives >/dev/null 2>&1; then
  ok "/mnt/archives répond en moins de 5 s"
else
  ko "/mnt/archives ne répond pas (ou n'existe plus)"
fi
timeout 5 mountpoint -q /mnt/archives \
  && ok "/mnt/archives est monté" \
  || ko "/mnt/archives n'est pas (re)monté"
timeout 5 df -h >/dev/null 2>&1 && ok "df rend la main" || ko "df reste bloqué"

D=$(ps -eo state,comm | awk '$1 ~ /^D/ && $2 ~ /export-archives|cp|df|ls/' | wc -l)
[ "$D" -eq 0 ] && ok "aucun processus bloqué en état D sur le montage" \
  || ko "$D processus toujours en état D (ps -eo state,pid,wchan:30,comm)"

# prévention : le montage ne doit plus pouvoir bloquer le boot ni les jobs
OPTS=$(grep -E '^[^#].*[[:space:]]/mnt/archives[[:space:]]' /etc/fstab \
       | awk '{print $4}')
if [ -n "$OPTS" ]; then
  echo "$OPTS" | grep -q 'nofail' && ok "fstab : nofail présent" \
    || ko "fstab : ajoute nofail (un NAS absent ne doit pas bloquer le boot)"
  echo "$OPTS" | grep -qE 'soft|x-systemd.mount-timeout|_netdev' \
    && ok "fstab : temporisation/soft/_netdev présent ($OPTS)" \
    || ko "fstab : aucune option limitant l'attente (soft,timeo= ou x-systemd.mount-timeout=)"
else
  ko "aucune entrée fstab active pour /mnt/archives"
fi

if [ -r "$SAUV/$ID.boot_id" ]; then
  [ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$SAUV/$ID.boot_id")" ] \
    && ok "pas de redémarrage de la VM" \
    || ko "MALUS : la VM a redémarré depuis le déclenchement (interdit)"
fi
[ -r "$SAUV/$ID.debut" ] && note "temps écoulé : \
$(( ($(date +%s) - $(cat "$SAUV/$ID.debut")) / 60 )) min"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
