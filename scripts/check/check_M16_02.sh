#!/usr/bin/env bash
# check_M16_02.sh — vérifie le lab L16.2 (fuite mémoire, OOM, garde-fou)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L16.2 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
BASE="$HOMEDIR/lab16"
CSV="$BASE/rapports/rss.csv"
RAP="$BASE/rapports/oom.md"

# --- 1. la mesure répétée ------------------------------------------------
if [ -s "$CSV" ]; then
  L=$(grep -c '[0-9]' "$CSV")
  if [ "$L" -ge 20 ]; then
    ok "rss.csv contient $L mesures"
  else
    ko "rss.csv ne contient que $L mesures : un échantillon toutes les 5 s \
pendant 3 min en donne une trentaine"
  fi
  # croissance : on compare la 2e valeur numérique de la 1re et de la
  # dernière ligne de données
  PREM=$(grep -oE '[0-9]+' "$CSV" | head -20 | sort -n | tail -1)
  DERN=$(grep -oE '[0-9]+' "$CSV" | tail -20 | sort -n | tail -1)
  if [ -n "$PREM" ] && [ -n "$DERN" ] && [ "$DERN" -gt "$PREM" ]; then
    ok "les valeurs mesurées croissent ($PREM -> $DERN)"
  else
    ko "aucune croissance visible dans rss.csv : la mesure a-t-elle tourné \
pendant que la fuite était active ?"
  fi
  head -1 "$CSV" | grep -qiE 'rss|date|horod' \
    && ok "rss.csv a un en-tête de colonnes" \
    || note "pense à une ligne d'en-tête : horodatage,rss_mo,dispo_mo"
else
  ko "fichier absent : $CSV"
fi

# --- 2. le rapport -------------------------------------------------------
if [ -s "$RAP" ]; then
  ok "oom.md présent"
  grep -qi 'oom' "$RAP" \
    && ok "la trace OOM est citée" \
    || ko "oom.md ne mentionne pas l'OOM killer"
  grep -qiE 'anon-rss|total-vm|oom_score' "$RAP" \
    && ok "les champs de la trace noyau sont repris" \
    || ko "oom.md doit reprendre les champs de la trace : anon-rss, \
total-vm, oom_score_adj"
  grep -qiE 'vmrss|/proc/[0-9]+/status|status' "$RAP" \
    && ok "la preuve de la fuite s'appuie sur /proc/<pid>/status" \
    || ko "oom.md doit citer la ligne VmRSS de /proc/<pid>/status"
  grep -qiE 'memorymax|cgroup|garde-fou' "$RAP" \
    && ok "le garde-fou est documenté" \
    || ko "oom.md ne documente pas le garde-fou posé"
  [ "$(grep -c '[^[:space:]]' "$RAP")" -ge 15 ] \
    && ok "oom.md est étoffé" \
    || ko "oom.md fait moins de 15 lignes utiles"
else
  ko "rapport absent : $RAP"
fi

# --- 3. le garde-fou effectif -------------------------------------------
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  MM=$(systemctl show vitrine-api -p MemoryMax --value 2>/dev/null)
  if [ "$MM" = "268435456" ]; then
    ok "MemoryMax=256M effectif sur vitrine-api"
  else
    ko "MemoryMax vaut « $MM » : on attend 268435456 (256M) — vérifie le \
drop-in et daemon-reload"
  fi
  CG=$(systemctl show vitrine-api -p ControlGroup --value 2>/dev/null)
  if [ -n "$CG" ] && [ -r "/sys/fs/cgroup$CG/memory.max" ]; then
    VAL=$(cat "/sys/fs/cgroup$CG/memory.max")
    [ "$VAL" = "268435456" ] \
      && ok "le cgroup applique bien memory.max=268435456" \
      || ko "le cgroup annonce memory.max=$VAL"
  else
    note "cgroup illisible ici : vérifie à la main \
cat /sys/fs/cgroup\$(systemctl show vitrine-api -p ControlGroup \
--value)/memory.max"
  fi
  [ "$(systemctl is-active vitrine-api)" = active ] \
    && ok "vitrine-api est actif" \
    || ko "vitrine-api n'est pas actif : le garde-fou ne doit pas empêcher \
le service de tourner"
else
  note "systemd absent : contrôle du garde-fou impossible ici"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
