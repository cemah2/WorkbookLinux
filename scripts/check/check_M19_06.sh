#!/usr/bin/env bash
# check_M19_06.sh — vérifie le défi D19 (examen blanc : 5 pannes en 90 min)
# Contrôle les huit axes de panne du module + les livrables. À lancer en
# root pour que tous les contrôles soient possibles.
set -uo pipefail
PASS=0; FAIL=0; AXES=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
axe()  { AXES=$((AXES+1)); printf '\n-- axe %d : %s\n' "$AXES" "$1"; }

echo "== Vérification D19 — examen blanc =="
[ "$(id -u)" -eq 0 ] || note "lance-moi en root (sudo) pour tout contrôler"

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BASE="$HOMEDIR/lab19"
DATA=/srv/vitrine/data
URL="${URL:-http://127.0.0.1:8080}"
SAINS=0

v() { systemctl show vitrine-api -p "$1" --value 2>/dev/null; }

# --- axe 1 : fuite mémoire ----------------------------------------------
axe "mémoire (BF19.1)"
ENVV=$(v Environment)
if printf '%s' "$ENVV" | grep -qE 'VITRINE_FUITE=[1-9]'; then
  ko "VITRINE_FUITE est encore positionné : la fuite tourne toujours"
else
  ok "aucune fuite injectée dans l'environnement du service"
  SAINS=$((SAINS+1))
fi
MP=$(v MainPID)
if [ -n "$MP" ] && [ "$MP" != 0 ] && [ -r "/proc/$MP/status" ]; then
  RSS=$(awk '/^VmRSS:/ {print int($2/1024)}' "/proc/$MP/status")
  [ "${RSS:-0}" -lt 200 ] \
    && ok "RSS du frontal : ${RSS} Mo" \
    || ko "RSS du frontal : ${RSS} Mo — anormalement haut"
fi
dmesg -T 2>/dev/null | tail -200 | grep -qi 'out of memory' \
  && note "trace OOM encore visible dans dmesg (normal si l'incident a eu lieu)"

# --- axe 2 : descripteurs -----------------------------------------------
axe "descripteurs de fichiers (BF19.2)"
NOF=$(v LimitNOFILE)
if [ -n "$NOF" ] && [ "$NOF" != infinity ] && [ "$NOF" -lt 1024 ] \
   2>/dev/null; then
  ko "LimitNOFILE=$NOF : limite trop basse, l'incident reviendra"
else
  ok "LimitNOFILE=$NOF"
  SAINS=$((SAINS+1))
fi
if printf '%s' "$ENVV" | grep -qE 'VITRINE_FD=[1-9]'; then
  ko "VITRINE_FD force encore l'application à garder des descripteurs"
elif [ -n "${MP:-}" ] && [ "$MP" != 0 ] && [ -d "/proc/$MP/fd" ]; then
  NFD=$(ls -1 "/proc/$MP/fd" 2>/dev/null | wc -l)
  [ "$NFD" -lt 100 ] \
    && ok "$NFD descripteurs ouverts par le frontal" \
    || ko "$NFD descripteurs ouverts : la fuite de descripteurs continue"
fi

# --- axe 3 : espace disque ----------------------------------------------
axe "espace disque (BF19.3)"
if mountpoint -q "$DATA" 2>/dev/null; then
  USE=$(df --output=pcent "$DATA" | tail -1 | tr -dc '0-9')
  IUSE=$(df -i --output=ipcent "$DATA" | tail -1 | tr -dc '0-9')
  if [ "${USE:-100}" -lt 90 ] && [ "${IUSE:-100}" -lt 90 ]; then
    ok "occupation ${USE}%, inodes ${IUSE}%"
    SAINS=$((SAINS+1))
  else
    ko "occupation ${USE}%, inodes ${IUSE}% — volume toujours saturé"
  fi
  if [ "$(id -u)" -eq 0 ] && command -v lsof >/dev/null 2>&1; then
    RET=$(lsof +L1 2>/dev/null | awk -v d="$DATA" '$0 ~ d {s+=$8} END \
      {printf "%d", s/1048576}')
    [ "${RET:-0}" -lt 50 ] \
      && ok "aucun fichier supprimé ne retient d'espace" \
      || ko "${RET} Mo retenus par un fichier supprimé encore ouvert"
  fi
else
  ko "$DATA n'est pas monté"
fi

# --- axe 4 : CPU ---------------------------------------------------------
axe "CPU (BF19.4)"
if pgrep -f vitrine-reindex >/dev/null 2>&1; then
  ko "le processus vitrine-reindex tourne toujours"
elif systemctl is-enabled vitrine-reindex.service >/dev/null 2>&1; then
  ko "vitrine-reindex.service est encore activé : il repartira au boot"
else
  ok "aucune boucle de calcul résiduelle"
  SAINS=$((SAINS+1))
fi
CH=$(cut -d' ' -f1 /proc/loadavg)
CPUS=$(nproc)
if awk -v c="$CH" -v n="$CPUS" 'BEGIN {exit !(c < n)}'; then
  ok "charge $CH pour $CPUS vCPU"
else
  ko "charge $CH pour $CPUS vCPU : quelque chose consomme encore"
fi

# --- axe 5 : ports éphémères / conntrack --------------------------------
axe "réseau : ports éphémères (BF19.5)"
read -r LO HI < <(sysctl -n net.ipv4.ip_local_port_range 2>/dev/null \
  | tr '\t' ' ')
LARG=$(( ${HI:-0} - ${LO:-0} ))
if [ "$LARG" -ge 10000 ]; then
  ok "plage de ports éphémères : $LO-$HI ($LARG ports)"
  SAINS=$((SAINS+1))
else
  ko "plage de ports éphémères réduite à $LARG ports ($LO-$HI)"
fi
if [ -f /proc/sys/net/netfilter/nf_conntrack_max ]; then
  CTM=$(cat /proc/sys/net/netfilter/nf_conntrack_max)
  [ "$CTM" -ge 32768 ] \
    && ok "nf_conntrack_max=$CTM" \
    || ko "nf_conntrack_max=$CTM : table de suivi trop petite"
fi

# --- axe 6 : résolution de noms -----------------------------------------
axe "résolution de noms (BF19.6)"
T0=$(date +%s%N)
getent hosts api-interne.lab.local >/dev/null 2>&1
T1=$(date +%s%N)
D=$(( (T1 - T0) / 1000000 ))
if [ "$D" -lt 500 ]; then
  ok "api-interne.lab.local résolu en ${D} ms"
  SAINS=$((SAINS+1))
else
  ko "résolution en ${D} ms : un serveur de noms ne répond pas"
fi
grep -q '^nameserver 127.0.0.77' /etc/resolv.conf 2>/dev/null \
  && ko "le résolveur muet est toujours en tête de /etc/resolv.conf" \
  || ok "/etc/resolv.conf ne pointe plus vers le résolveur muet"
systemctl is-active dns-cache-local.service >/dev/null 2>&1 \
  && note "dns-cache-local.service tourne encore (acceptable s'il n'est \
plus dans resolv.conf, mais pourquoi le garder ?)"

# --- axe 7 : montage en écriture ----------------------------------------
axe "système de fichiers en écriture (BF19.7)"
OPT=$(findmnt -n -o OPTIONS --target "$DATA" 2>/dev/null)
case "$OPT" in
  ro,*|*,ro|*,ro,*) ko "$DATA est monté en lecture seule" ;;
  "") ko "$DATA n'est pas monté" ;;
  *) ok "$DATA est monté en écriture"; SAINS=$((SAINS+1)) ;;
esac
DEV=$(findmnt -n -o SOURCE --target "$DATA" 2>/dev/null)
if [ -n "$DEV" ] && [ -b "$DEV" ]; then
  RO=$(blockdev --getro "$DEV" 2>/dev/null || echo 0)
  [ "$RO" = 0 ] \
    && ok "le périphérique $DEV est accessible en écriture" \
    || ko "le périphérique $DEV est encore marqué read-only au niveau bloc"
fi

# --- axe 8 : stabilité du service ---------------------------------------
axe "stabilité du service (BF19.8)"
RMAX=$(v RuntimeMaxUSec)
case "$RMAX" in
  infinity|"")
     ok "aucun RuntimeMaxSec posé sur l'unité"; SAINS=$((SAINS+1)) ;;
  *) ko "RuntimeMaxSec=$RMAX : systemd tue le service périodiquement" ;;
esac
NR=$(v NRestarts)
ETAT=$(systemctl is-active vitrine-api 2>/dev/null)
SINCE=$(systemctl show vitrine-api -p ActiveEnterTimestampMonotonic --value \
  2>/dev/null)
UPS=$(( ${SINCE:-0} / 1000000 ))
if [ "$ETAT" = active ] && [ "$UPS" -ge 60 ]; then
  ok "vitrine-api actif et stable (démarré il y a plus de 60 s)"
else
  ko "vitrine-api : état « $ETAT », dernier démarrage il y a ${UPS}s"
fi
note "compteur de redémarrages systemd : ${NR:-?}"

# --- fonctionnel ---------------------------------------------------------
axe "vérification fonctionnelle bout en bout"
if command -v curl >/dev/null 2>&1; then
  for R in /sante /produits /commande; do
    T=$(curl -s -o /tmp/d16.$$ -w '%{time_total} %{http_code}' \
        --max-time 15 "$URL$R" 2>/dev/null || echo "99 000")
    SEC=${T% *}; CODE=${T#* }
    MS=$(printf '%.0f' "$(echo "$SEC * 1000" | bc -l 2>/dev/null || \
         echo 99000)")
    if [ "$CODE" = 200 ] && [ "$MS" -lt 200 ]; then
      ok "$R : HTTP $CODE en ${MS} ms"
    else
      ko "$R : HTTP $CODE en ${MS} ms (attendu 200 en moins de 200 ms)"
    fi
  done
  rm -f /tmp/d16.$$
fi
FAILED=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
[ "$FAILED" -eq 0 ] \
  && ok "aucune unité en échec" \
  || ko "$FAILED unité(s) en échec (systemctl --failed)"

# --- livrables -----------------------------------------------------------
axe "livrables de l'examen"
J="$BASE/rapports/examen.md"
S="$BASE/rapports/examen-synthese.md"
LIV=0
if [ -s "$J" ] && [ "$(grep -cE '[0-2][0-9][:h][0-5][0-9]' "$J")" -ge 10 ]; then
  ok "journal de bord tenu et horodaté"; LIV=$((LIV+1))
else
  ko "journal $J absent ou sans horodatage continu (10 marques minimum)"
fi
if [ -s "$S" ] && [ "$(grep -c '[^[:space:]]' "$S")" -ge 25 ]; then
  ok "synthèse des pannes présente"; LIV=$((LIV+1))
else
  ko "synthèse $S absente ou trop courte (5 lignes par panne)"
fi
if [ "$(ls -1d "$BASE"/preuves/*/ 2>/dev/null | wc -l)" -ge 1 ]; then
  ok "preuves collectées"; LIV=$((LIV+1))
else
  ko "aucune collecte de preuves dans $BASE/preuves/"
fi
grep -qiE 'cause|parce que' "$S" 2>/dev/null \
  && ok "la synthèse expose des causes racines" \
  || ko "la synthèse n'expose pas de cause racine"

# --- verdict -------------------------------------------------------------
SCORE=$(( SAINS * 10 + LIV * 5 ))
[ "$FAILED" -eq 0 ] && SCORE=$((SCORE + 5))
echo
echo "== Verdict =="
echo "  axes de panne sains : $SAINS / 8"
echo "  livrables présents  : $LIV / 3"
echo "  score indicatif     : $SCORE / 100"
echo "  (le barème complet du §19.8 demande une relecture humaine du"
echo "   journal de bord : continuité, une modification à la fois,"
echo "   vérification après chaque correctif)"
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
