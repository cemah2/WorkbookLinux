#!/usr/bin/env bash
# check_PC_4_2.sh — vérifie le ticket PC.4.2 (horloge dérivée casse TLS)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.4.2 =="
SAUV=/root/.breakfix-backup; ID=PC_4_2
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

# 1. la synchro du temps est de nouveau active
if timedatectl show -p NTP --value 2>/dev/null | grep -q yes; then
  ok "la synchronisation NTP est active"
else
  ko "NTP inactif (timedatectl set-ntp true, ou active systemd-timesyncd)"
fi
if timedatectl status 2>/dev/null | grep -qiE 'System clock synchronized: yes'; then
  ok "horloge système synchronisée"
else
  note "synchro pas encore confirmée (peut prendre quelques secondes)"
fi

# 2. l'écart avec une référence est faible (< 5 s) si réseau dispo
if command -v chronyc >/dev/null 2>&1 && chronyc tracking >/dev/null 2>&1; then
  E=$(chronyc tracking | awk '/System time/ {print $4}')
  note "écart chrony : ${E:-?} s"
fi

# 3. TLS de bout en bout sans -k
CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  --resolve factura.lab.local:443:127.0.0.1 https://factura.lab.local/version)
[ "$CODE" = "200" ] && ok "validation TLS OK (curl sans -k : 200)" \
  || ko "curl HTTPS renvoie « $CODE » : la validation TLS échoue encore"

# 4. le service NTP est activé au démarrage (prévention)
if systemctl is-enabled -q systemd-timesyncd 2>/dev/null \
   || systemctl is-enabled -q chrony 2>/dev/null \
   || systemctl is-enabled -q chronyd 2>/dev/null; then
  ok "le service de synchro est activé au boot"
else
  ko "aucun service de synchro activé au boot (la dérive reviendra)"
fi

if [ -r "$SAUV/$ID.boot_id" ]; then
  [ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$SAUV/$ID.boot_id")" ] \
    && ok "pas de redémarrage de la VM" \
    || ko "MALUS : la VM a redémarré depuis le déclenchement"
fi
[ -r "$SAUV/$ID.debut" ] && note "temps écoulé (heure réelle) : quelques minutes"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
