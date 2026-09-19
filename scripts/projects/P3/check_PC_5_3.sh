#!/usr/bin/env bash
# check_PC_5_3.sh — vérifie le ticket PC.5.3 (inodes épuisés)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.5.3 =="
SAUV=/root/.breakfix-backup; ID=PC_5_3
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
DIR=/var/lib/factura-cache

# 1. le processus qui remplit les inodes est arrêté
if pgrep -f factura-sessioncache >/dev/null; then
  ko "le processus factura-sessioncache tourne encore (il re-remplit les inodes)"
else
  ok "le processus qui épuisait les inodes est arrêté"
fi

# 2. des inodes sont de nouveau disponibles
if mountpoint -q "$DIR" 2>/dev/null; then
  IFREE=$(df -i --output=iavail "$DIR" | tail -1 | tr -dc 0-9)
  IPCT=$(df -i --output=ipcent "$DIR" | tail -1 | tr -dc 0-9)
  if [ "${IFREE:-0}" -gt 100 ]; then
    ok "inodes de nouveau disponibles ($IFREE libres, $IPCT % utilisés)"
  else
    ko "inodes toujours épuisés ($IFREE libres) — df -i $DIR"
  fi
  # on peut réécrire
  if touch "$DIR/.check_ecriture" 2>/dev/null; then
    ok "écriture possible sur $DIR"; rm -f "$DIR/.check_ecriture"
  else
    ko "écriture toujours impossible sur $DIR"
  fi
else
  note "$DIR n'est plus monté (volume jetable démonté : acceptable)"
  ok "plus de volume saturé en inodes"
fi

# 3. prévention : une surveillance des inodes (pas seulement de l'espace)
if grep -rqsE 'df -i|iused|ipcent|inode' /etc/cron.d/ /usr/local/sbin/ \
     /usr/local/bin/ /etc/prometheus/ 2>/dev/null; then
  ok "une surveillance des inodes existe"
else
  ko "aucune surveillance des inodes (df -i) : l'alerte espace ne suffit pas"
fi

if [ -r "$SAUV/$ID.boot_id" ]; then
  [ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat "$SAUV/$ID.boot_id")" ] \
    && ok "pas de redémarrage de la VM" \
    || ko "MALUS : la VM a redémarré depuis le déclenchement"
fi
[ -r "$SAUV/$ID.debut" ] && note "temps écoulé : \
$(( ($(date +%s) - $(cat "$SAUV/$ID.debut")) / 60 )) min"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
