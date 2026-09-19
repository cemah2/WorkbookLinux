#!/usr/bin/env bash
# check_M16_05.sh — vérifie le lab L16.5 (node_exporter)
#                   À LANCER SUR lab-ops (10.10.10.14).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L16.5 =="

IP=10.10.10.14
LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
DOC="$HOMEDIR/lab16/use-golden.md"

# --- 1. le service tourne --------------------------------------------------
UNITE=""
for U in prometheus-node-exporter.service node_exporter.service; do
  systemctl cat "$U" >/dev/null 2>&1 && UNITE="$U" && break
done
if [ -n "$UNITE" ]; then
  ok "unité trouvée : $UNITE"
  [ "$(systemctl is-active "$UNITE")" = active ] \
    && ok "$UNITE est active" || ko "$UNITE n'est pas active"
  [ "$(systemctl is-enabled "$UNITE" 2>/dev/null)" = enabled ] \
    && ok "$UNITE démarre au boot" || ko "$UNITE n'est pas activée au boot"
  UTIL=$(systemctl show -p User --value "$UNITE")
  [ "$UTIL" != root ] && [ -n "$UTIL" ] \
    && ok "tourne sous l'utilisateur $UTIL (pas root)" \
    || ko "le service tourne sous root : utilise un compte dédié"
else
  ko "aucune unité node_exporter trouvée"
fi

# --- 2. écoute restreinte --------------------------------------------------
ECOUTE=$(ss -tlnp 2>/dev/null | grep ':9100 ' | awk '{print $4}' | head -1)
if [ -n "$ECOUTE" ]; then
  ok "quelque chose écoute sur le port 9100 ($ECOUTE)"
  case "$ECOUTE" in
    0.0.0.0:9100|\[::\]:9100|*:::9100)
      ko "écoute sur toutes les interfaces : restreins à $IP \
(--web.listen-address)" ;;
    "$IP":9100) ok "écoute uniquement sur $IP" ;;
    *) note "adresse d'écoute inhabituelle : $ECOUTE" ;;
  esac
else
  ko "rien n'écoute sur 9100"
fi

# --- 3. le drop-in, pas le fichier du paquet -------------------------------
DROP=$(find /etc/systemd/system -path '*node*exporter*.d/*.conf' 2>/dev/null \
       | head -1)
if [ -n "$DROP" ]; then
  ok "drop-in présent : $DROP"
  grep -q 'ExecStart=$' "$DROP" \
    && ok "l'ExecStart d'origine est bien remis à zéro avant redéfinition" \
    || note "si tu redéfinis ExecStart, pense à la ligne ExecStart= vide"
else
  ko "aucun drop-in sous /etc/systemd/system : le fichier du paquet a-t-il \
été modifié directement ?"
fi
if [ -n "$UNITE" ]; then
  CHEMIN=$(systemctl show -p FragmentPath --value "$UNITE")
  case "$CHEMIN" in
    /lib/*|/usr/lib/*) ok "le fichier d'unité du paquet est intact" ;;
    *) ko "l'unité vient de $CHEMIN : le paquet a été contourné" ;;
  esac
fi

# --- 4. /metrics ------------------------------------------------------------
M=$(curl -sf --max-time 5 "http://$IP:9100/metrics" 2>/dev/null)
if [ -n "$M" ]; then
  ok "/metrics répond sur $IP:9100"
  N=$(echo "$M" | grep -vc '^#')
  ok "$N séries exposées"
  for MET in node_load1 node_memory_MemAvailable_bytes \
             node_filesystem_avail_bytes node_cpu_seconds_total \
             node_network_receive_bytes_total; do
    echo "$M" | grep -q "^$MET" \
      && ok "métrique $MET présente" \
      || ko "métrique $MET absente (collecteur désactivé ?)"
  done
else
  ko "/metrics injoignable sur http://$IP:9100/metrics"
fi

# --- 5. le document -----------------------------------------------------
if [ -s "$DOC" ]; then
  ok "$DOC existe"
  for MOT in latence trafic erreur saturation; do
    grep -qi "$MOT" "$DOC" \
      && ok "les signaux dorés : « $MOT » traité" \
      || ko "le tableau des signaux dorés ne traite pas « $MOT »"
  done
  grep -qiE 'utilisation' "$DOC" && grep -qiE 'saturation' "$DOC" \
    && ok "le tableau USE est rempli" \
    || ko "le tableau USE (Utilisation/Saturation/Erreurs) est incomplet"
  [ "$(grep -c '^|' "$DOC")" -ge 10 ] \
    && ok "les deux tableaux contiennent des lignes" \
    || ko "les tableaux semblent vides (moins de 10 lignes de tableau)"
else
  ko "$DOC manquant"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
