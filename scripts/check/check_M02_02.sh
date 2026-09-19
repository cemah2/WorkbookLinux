#!/usr/bin/env bash
# check_M02_02.sh — vérifie le lab L2.2 (INC-3187, récupération d'espace)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L2.2 =="

LOGMNT=/var/log/factura
HOMEDIR=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)

findmnt -n "$LOGMNT" >/dev/null 2>&1 || {
  ko "$LOGMNT n'est plus monté (relance setup_M02.sh)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

# --- 1. occupation redescendue ------------------------------------------
pct=$(df --output=pcent "$LOGMNT" | tail -1 | tr -dc '0-9')
if [ "${pct:-100}" -lt 50 ]; then
  ok "$LOGMNT est à ${pct}% (objectif : moins de 50 %)"
else
  ko "$LOGMNT est encore à ${pct}% (df -h puis du -x, par paliers)"
fi

# --- 2. le journal a été tronqué, pas supprimé --------------------------
if [ -f "$LOGMNT/factura.log" ]; then
  ok "factura.log existe toujours"
  taille=$(stat -c %s "$LOGMNT/factura.log")
  if [ "$taille" -lt $((1024 * 1024)) ]; then
    ok "factura.log pèse $taille octets (moins de 1 Mio)"
  else
    ko "factura.log pèse encore $taille octets"
  fi
  ref=$(cat /var/lib/lab02/factura.log.inode 2>/dev/null || echo 0)
  cur=$(stat -c %i "$LOGMNT/factura.log")
  if [ "$ref" != "0" ] && [ "$ref" = "$cur" ]; then
    ok "l'inode du journal est inchangé : il a bien été tronqué en place"
  elif [ "$ref" = "0" ]; then
    note "inode de référence inconnu (setup non rejoué), contrôle ignoré"
  else
    ko "l'inode a changé : le fichier a été supprimé/recréé, le processus \
écrit toujours dans l'ancien"
  fi
else
  ko "factura.log a disparu : un rm sur un journal ouvert casse la \
journalisation et ne rend pas l'espace"
fi

# --- 3. le producteur de logs tourne toujours ---------------------------
if pgrep -f '^bash /usr/local/sbin/lab-collector' >/dev/null 2>&1; then
  ok "le collecteur tourne toujours (aucune coupure de service)"
else
  ko "le collecteur ne tourne plus : l'énoncé interdisait de l'arrêter"
fi

# --- 4. archives : il n'en reste que deux -------------------------------
nbgz=$(find "$LOGMNT" -maxdepth 1 -name 'factura.log.*.gz' | wc -l)
if [ "$nbgz" -eq 2 ]; then
  ok "il reste exactement 2 archives .gz"
else
  ko "$nbgz archives .gz présentes, l'énoncé en demande 2 (les plus récentes)"
fi

# --- 5. cache applicatif vidé -------------------------------------------
if [ -d /var/cache/factura/thumbs ]; then
  nbt=$(find /var/cache/factura/thumbs -type f | wc -l)
  if [ "$nbt" -eq 0 ]; then
    ok "le cache /var/cache/factura/thumbs est vide"
  else
    ko "$nbt fichiers encore dans /var/cache/factura/thumbs"
  fi
else
  ok "/var/cache/factura/thumbs a été vidé (répertoire supprimé)"
fi

# --- 6. limite journald rendue permanente -------------------------------
if grep -Eq '^[[:space:]]*SystemMaxUse=' /etc/systemd/journald.conf \
     /etc/systemd/journald.conf.d/*.conf 2>/dev/null; then
  ok "SystemMaxUse est configuré pour journald"
else
  ko "la limite journald n'est pas permanente (SystemMaxUse= dans \
/etc/systemd/journald.conf)"
fi

# --- 7. le fichier creux n'a pas été supprimé ---------------------------
if [ -f "$HOMEDIR/lab02/arbo/archives/disque-vm.img" ]; then
  ok "le fichier creux disque-vm.img est intact"
else
  ko "disque-vm.img a été supprimé : il n'occupait que 4 Mio réels"
fi

# --- 8. rapport ----------------------------------------------------------
RAP="$HOMEDIR/lab02/rapports/inc-3187.md"
if [ -s "$RAP" ] && [ "$(grep -c . "$RAP")" -ge 10 ]; then
  ok "le rapport inc-3187.md est rédigé"
else
  ko "rapport ~/lab02/rapports/inc-3187.md absent ou trop court"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
