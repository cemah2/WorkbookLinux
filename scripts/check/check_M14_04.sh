#!/usr/bin/env bash
# check_M14_04.sh — vérifie le lab L14.4 (tunnels -L, -R, -D)
# À lancer sur lab-adm, SANS sudo.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L14.4 =="

R="$HOME/lab14/rapports/tunnels.md"
ecoute() { ss -tlnH "( sport = :$1 )" 2>/dev/null | grep -q . ; }
banniere() {   # banniere <port> : lit la première ligne du service
  timeout 4 bash -c "exec 3<>/dev/tcp/127.0.0.1/$1 && head -1 <&3" 2>/dev/null
}

# --- 1. le ménage a été fait (étape 6) ------------------------------------
for p in 15432 1080 8080; do
  if ecoute "$p"; then
    ko "le port $p écoute encore : les tunnels devaient être fermés"
  else
    ok "port $p libre"
  fi
done
if pgrep -af 'ssh .*-[NfD]' >/dev/null 2>&1 && \
   pgrep -af 'ssh ' | grep -qE '\-N|\-D [0-9]+'; then
  ko "des processus ssh de tunnel subsistent (pgrep -af ssh)"
else
  ok "aucun processus de tunnel résiduel"
fi

# --- 2. l'infrastructure permet bien les trois tunnels --------------------
# On remonte nous-mêmes un tunnel local : ça valide la configuration client,
# le rebond, et AllowTcpForwarding sur le bastion.
if ssh -f -N -o BatchMode=yes -o ConnectTimeout=5 \
       -o ExitOnForwardFailure=yes -o ControlMaster=no -o ControlPath=none \
       -L 15499:10.10.10.12:5432 bastion 2>/tmp/m12.tun; then
  ok "tunnel local monté via le bastion (ExitOnForwardFailure actif)"
  sleep 1
  case "$(banniere 15499)" in
    LAB12-DB-OK*) ok "le service de lab-db répond à travers le tunnel" ;;
    *) ko "aucune bannière LAB12-DB-OK : lab14-db.service tourne-t-il ?" ;;
  esac
  pkill -f 'ssh -f -N .*15499' 2>/dev/null
else
  ko "impossible de monter le tunnel : $(head -1 /tmp/m12.tun)"
fi

# proxy SOCKS
if ssh -f -N -o BatchMode=yes -o ConnectTimeout=5 \
       -o ExitOnForwardFailure=yes -o ControlMaster=no -o ControlPath=none \
       -D 1099 bastion 2>/dev/null; then
  sleep 1
  if command -v curl >/dev/null 2>&1; then
    curl -s --max-time 5 --socks5-hostname 127.0.0.1:1099 \
         http://10.10.10.11/ >/dev/null 2>&1 \
      && ok "le proxy SOCKS atteint lab-web" \
      || note "SOCKS monté mais lab-web ne sert rien en HTTP (sans gravité)"
  else
    note "curl absent : test SOCKS applicatif sauté"
  fi
  ok "proxy SOCKS montable via le bastion"
  pkill -f 'ssh -f -N .*-D 1099' 2>/dev/null
else
  ko "le proxy SOCKS ne peut pas être monté (AllowTcpForwarding sur bastion ?)"
fi

# --- 3. GatewayPorts a bien été traité sur lab-ops ------------------------
GP=$(ssh -o BatchMode=yes -o ConnectTimeout=5 lab-ops \
     'grep -rhi "^[[:space:]]*GatewayPorts" /etc/ssh/sshd_config \
      /etc/ssh/sshd_config.d/ 2>/dev/null | tail -1' 2>/dev/null)
case "$GP" in
  *clientspecified*|*yes*) ok "lab-ops : GatewayPorts configuré ($GP)" ;;
  "") ko "lab-ops : aucune directive GatewayPorts (étape 4 non traitée)" ;;
  *)  ko "lab-ops : GatewayPorts vaut '$GP' (clientspecified attendu)" ;;
esac

# --- 4. le rapport --------------------------------------------------------
if [ -s "$R" ]; then
  ok "rapport présent : ~/lab14/rapports/tunnels.md"
  L=$(grep -c . "$R")
  [ "$L" -ge 20 ] \
    && ok "rapport suffisamment détaillé ($L lignes)" \
    || ko "rapport trop court ($L lignes, 20 minimum)"
  MANQUE=""
  for mot in '\-L' '\-R' '\-D' GatewayPorts AllowTcpForwarding \
             ExitOnForwardFailure; do
    grep -qE -- "$mot" "$R" || MANQUE="$MANQUE ${mot#\\}"
  done
  [ -z "$MANQUE" ] \
    && ok "le rapport couvre les trois tunnels et les directives serveur" \
    || ko "il manque dans le rapport :$MANQUE"
  grep -qiE 'risque|sécurit|danger' "$R" \
    && ok "le rapport traite le risque de sécurité de chaque tunnel" \
    || ko "chaque ticket doit s'accompagner de son risque de sécurité"
else
  ko "rapport manquant : ~/lab14/rapports/tunnels.md"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
