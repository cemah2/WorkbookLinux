#!/usr/bin/env bash
# check_M13_04.sh — vérifie le lab L13.4 (collecte de métriques + rapport)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L13.4 =="

COL=/opt/factura/bin/collecte-metriques.sh
RAPS=/opt/factura/bin/rapport-quotidien.sh
CSV=/var/log/factura/metriques.csv
LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab13/rapport-quotidien.md"
priv() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo -n "$@"; fi; }

# --- 1. les deux scripts --------------------------------------------------
for S in "$COL" "$RAPS"; do
  if [ -x "$S" ]; then
    ok "$(basename "$S") existe et est exécutable"
    head -1 "$S" | grep -q '^#!/usr/bin/env bash' \
      && ok "$(basename "$S") : shebang conforme" \
      || ko "$(basename "$S") : shebang attendu #!/usr/bin/env bash"
    grep -q 'set -euo pipefail' "$S" \
      && ok "$(basename "$S") : set -euo pipefail" \
      || ko "$(basename "$S") : set -euo pipefail manquant"
  else
    ko "$S manquant ou non exécutable"
  fi
done

# --- 2. le CSV ------------------------------------------------------------
if priv test -s "$CSV"; then
  ok "$CSV existe"
  ENTETE=$(priv head -1 "$CSV")
  NCOL=$(echo "$ENTETE" | awk -F, '{print NF}')
  [ "$NCOL" -ge 12 ] \
    && ok "en-tête à $NCOL colonnes" \
    || ko "en-tête à $NCOL colonnes : il en faut au moins 12 (voir la \
liste du §13.6 L13.4)"
  for C in charge wa mem; do
    echo "$ENTETE" | grep -qi "$C" \
      && ok "colonne « $C » présente" \
      || ko "aucune colonne ne mentionne « $C »"
  done
  NL=$(priv wc -l < "$CSV")
  [ "$NL" -ge 21 ] \
    && ok "$((NL - 1)) relevés enregistrés" \
    || ko "seulement $((NL - 1)) relevés : on en attend au moins 20"
  MAL=$(priv awk -F, -v n="$NCOL" 'NF != n {c++} END {print c+0}' "$CSV")
  [ "$MAL" -eq 0 ] \
    && ok "toutes les lignes ont le même nombre de colonnes" \
    || ko "$MAL ligne(s) n'ont pas $NCOL colonnes"
  DOUBLE=$(priv grep -c -i '^horodat\|^date\|^timestamp' "$CSV")
  [ "${DOUBLE:-0}" -le 1 ] \
    && ok "l'en-tête n'est écrit qu'une fois" \
    || ko "l'en-tête est réécrit à chaque exécution ($DOUBLE fois)"
else
  ko "$CSV absent ou vide"
fi

# --- 3. le script de collecte est rejouable et rapide ---------------------
if [ -x "$COL" ]; then
  AVANT=$(priv wc -l < "$CSV" 2>/dev/null || echo 0)
  DEB=$(date +%s)
  if priv "$COL" >/dev/null 2>&1; then
    DUREE=$(( $(date +%s) - DEB ))
    [ "$DUREE" -le 4 ] \
      && ok "une collecte dure ${DUREE}s (budget : 3s)" \
      || ko "une collecte dure ${DUREE}s : trop long pour un relevé"
    APRES=$(priv wc -l < "$CSV" 2>/dev/null || echo 0)
    [ "$APRES" -eq $((AVANT + 1)) ] \
      && ok "la collecte ajoute exactement une ligne" \
      || ko "la collecte a ajouté $((APRES - AVANT)) ligne(s) au lieu d'une"
  else
    ko "$COL sort en erreur"
  fi
fi

# --- 4. le rapport --------------------------------------------------------
if [ -x "$RAPS" ]; then
  ERRS=$(priv "$RAPS" 2>&1 >/dev/null)
  [ -z "$ERRS" ] \
    && ok "rapport-quotidien.sh n'écrit rien sur stderr" \
    || ko "rapport-quotidien.sh écrit sur stderr : $(echo "$ERRS" | head -1)"
  SORTIE=$(priv "$RAPS" 2>/dev/null)
  echo "$SORTIE" | grep -q '^#' \
    && ok "la sortie est du Markdown (au moins un titre)" \
    || ko "la sortie ne ressemble pas à du Markdown"
  echo "$SORTIE" | grep -qiE 'min|moy|max' \
    && ok "le rapport donne min/moyenne/max" \
    || ko "le rapport ne donne pas min/moyenne/max"
  echo "$SORTIE" | grep -qiE 'surveiller|anomalie|seuil' \
    && ok "une section d'anomalies existe" \
    || ko "aucune section « À surveiller » / seuils dans la sortie"
fi

if [ -s "$RAP" ]; then
  ok "$RAP existe"
  grep -qiE 'cpu|e/s|io|m[ée]moire' "$RAP" \
    && ok "le rapport désigne une ressource limitante" \
    || ko "le rapport ne conclut pas sur la ressource limitante"
else
  ko "$RAP manquant"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
