#!/usr/bin/env bash
# check_M11_05.sh — vérifie le lab L11.5 (capture, MTU, bande passante)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L11.5 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
CAP="$HOMEDIR/lab11/captures/http.pcap"
RCAP="$HOMEDIR/lab11/rapports/capture.md"
RDEB="$HOMEDIR/lab11/rapports/debit.md"
IFACE=$(ip -o -4 route show default 2>/dev/null | awk '{print $5; exit}')
[ -n "$IFACE" ] || IFACE=ens18

# --- 1. la capture produite par l'apprenant ---------------------------
if [ -s "$CAP" ]; then
  ok "capture http.pcap présente ($(stat -c '%s' "$CAP") octets)"
  if command -v tcpdump >/dev/null 2>&1; then
    N=$(tcpdump -nn -r "$CAP" 2>/dev/null | wc -l)
    [ "$N" -ge 6 ] \
      && ok "la capture contient $N paquets (échange complet)" \
      || ko "seulement $N paquets : la capture a été arrêtée trop tôt"
    tcpdump -nn -r "$CAP" 2>/dev/null | grep -q 'Flags \[S\]' \
      && ok "un SYN figure dans la capture" \
      || ko "aucun SYN : le filtre ou le moment de capture est à revoir"
  fi
else
  ko "capture absente : $CAP (tcpdump -w)"
fi

# --- 2. l'analyse de la capture d'incident ----------------------------
if [ -s "$RCAP" ] && [ "$(grep -cv '^[[:space:]]*$' "$RCAP")" -ge 4 ]; then
  ok "rapport capture.md rédigé"
  if grep -qiE '\bRST\b|\[R' "$RCAP"; then
    ok "le rapport identifie les RST de la capture d'incident"
  else
    ko "le rapport ne mentionne pas les RST : relis la capture avec \
un filtre sur tcp-rst"
  fi
  grep -qE '8199|8099' "$RCAP" \
    && ok "le port en jeu est identifié" \
    || ko "le rapport ne nomme pas le port concerné"
else
  ko "rapport absent ou trop court : $RCAP (5 lignes de conclusion)"
fi

# --- 3. le rapport de débit -------------------------------------------
if [ -s "$RDEB" ] && [ "$(grep -cv '^[[:space:]]*$' "$RDEB")" -ge 4 ]; then
  ok "rapport debit.md rédigé"
  grep -qiE 'retr' "$RDEB" \
    && ok "la colonne Retr est reportée" \
    || ko "le rapport ne reporte pas la colonne Retr (interprétation \
attendue)"
  grep -qiE 'bits/sec|mbit|gbit' "$RDEB" \
    && ok "les débits mesurés sont reportés" \
    || ko "aucun débit chiffré dans le rapport"
else
  ko "rapport absent ou trop court : $RDEB"
fi

# --- 4. le MTU est revenu à la normale --------------------------------
MTU=$(cat "/sys/class/net/$IFACE/mtu" 2>/dev/null)
if [ "${MTU:-0}" = 1500 ]; then
  ok "MTU de $IFACE remis à 1500"
else
  ko "MTU de $IFACE = ${MTU:-?} : remets-le à 1500 (ip link set dev \
$IFACE mtu 1500)"
fi

# --- 5. pas de serveur iperf3 oublié en écoute ------------------------
if ss -tln 2>/dev/null | grep -q ':5201'; then
  note "un serveur iperf3 écoute encore sur 5201 : pense à l'arrêter"
else
  ok "aucun serveur iperf3 résiduel"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
