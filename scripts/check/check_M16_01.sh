#!/usr/bin/env bash
# check_M16_01.sh — vérifie le lab L16.1 (enquête journal, INC-4102)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L16.1 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
DOS="$HOMEDIR/lab16/inc-4102"
EXTRAIT="$DOS/journal-api.log"
RAPPORT="$DOS/rapport.md"

# --- 1. journal persistant ----------------------------------------------
if [ -d /var/log/journal ]; then
  ok "/var/log/journal existe : le journal survit au redémarrage"
else
  ko "le journal est encore volatile (crée /var/log/journal puis \
redémarre systemd-journald)"
fi

STO=$(systemd-analyze cat-config systemd/journald.conf 2>/dev/null \
      | grep -E '^\s*Storage=' | tail -1 | cut -d= -f2)
case "${STO:-auto}" in
  persistent|auto) ok "Storage=${STO:-auto} (compatible persistant)" ;;
  *) ko "Storage=$STO empêche la persistance" ;;
esac

if journalctl --list-boots >/dev/null 2>&1; then
  NB=$(journalctl --list-boots 2>/dev/null | wc -l)
  ok "journalctl --list-boots répond ($NB démarrage(s) connu(s))"
else
  ko "journalctl --list-boots échoue (droits ? groupe systemd-journal ?)"
fi

# --- 2. extraction de la fenêtre ----------------------------------------
if [ -s "$EXTRAIT" ]; then
  ok "$EXTRAIT existe et n'est pas vide"
  if grep -qE 'factura-api' "$EXTRAIT"; then
    ok "l'extrait contient bien des entrées de factura-api"
  else
    ko "aucune entrée factura-api dans l'extrait (journalctl -u \
factura-api.service)"
  fi
  if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' "$EXTRAIT"; then
    ok "horodatage ISO (-o short-iso)"
  else
    ko "l'extrait n'est pas en horodatage ISO (option -o short-iso)"
  fi
  if grep -qiE 'pool|connexion' "$EXTRAIT"; then
    ok "les lignes du pool de connexions sont dans la fenêtre extraite"
  else
    ko "la fenêtre extraite ne couvre pas l'incident (relis \
$DOS/fenetre.txt)"
  fi
else
  ko "$EXTRAIT manquant ou vide"
fi

# --- 3. le rapport -------------------------------------------------------
if [ -s "$RAPPORT" ]; then
  L=$(grep -cve '^\s*$' "$RAPPORT")
  [ "$L" -ge 15 ] && ok "rapport.md fait $L lignes utiles" \
    || ko "rapport.md ne fait que $L lignes utiles (on en attend 15)"
  for MOT in 502 pool journalctl; do
    grep -qi "$MOT" "$RAPPORT" \
      && ok "le rapport mentionne « $MOT »" \
      || ko "le rapport ne parle pas de « $MOT »"
  done
  grep -qiE 'cause racine|cause-racine' "$RAPPORT" \
    && ok "une section cause racine est identifiée" \
    || ko "le rapport ne nomme pas explicitement la cause racine"
  grep -qiE 'nginx|access\.log' "$RAPPORT" \
    && ok "la corrélation avec les journaux nginx est faite" \
    || ko "le rapport n'exploite pas /var/log/nginx/access.log"
else
  ko "$RAPPORT manquant"
fi

# --- 4. indice si l'histogramme n'a pas été fait -------------------------
if [ -r /var/log/nginx/access.log ]; then
  N502=$(awk '$9==502' /var/log/nginx/access.log 2>/dev/null | wc -l)
  note "pour information : $N502 réponses 502 dans access.log"
else
  note "/var/log/nginx/access.log illisible sans sudo (groupe adm)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
