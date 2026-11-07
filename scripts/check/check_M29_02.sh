#!/usr/bin/env bash
# check_M29_02.sh — vérifie le lab L29.2 (IP virtuelle keepalived)
# À lancer avec sudo sur lab-ha1, puis sur lab-ha2.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L29.2 sur $(hostname -s) =="

[ "$(id -u)" -eq 0 ] || { ko "à lancer avec sudo"; fin; }
C=/etc/keepalived/keepalived.conf
[ -f "$C" ] || { ko "$C absent"; fin; }
VIP=10.10.10.20

# --- 1. service et configuration ---------------------------------------------
systemctl is-active -q keepalived && ok "keepalived actif" || ko "keepalived n'est pas actif"
systemctl is-enabled -q keepalived && ok "keepalived activé au démarrage" \
                                   || ko "keepalived non activé au démarrage"
grep -Eq 'virtual_router_id\s+29\b' "$C" && ok "routeur virtuel 29" \
                                         || ko "virtual_router_id 29 attendu"
grep -Eq 'unicast_peer' "$C" && ok "annonces en unicast" || ko "pas de unicast_peer"
grep -Eq 'advert_int\s+1\b' "$C" && ok "intervalle d'annonce : 1 s" || ko "advert_int 1 attendu"
grep -q "$VIP/24" "$C" && ok "IP virtuelle $VIP/24 déclarée" || ko "$VIP/24 absente de la configuration"
grep -Eq 'track_script' "$C" && grep -Eq 'vrrp_script' "$C" \
  && ok "script de suivi déclaré et utilisé" || ko "pas de vrrp_script / track_script"
grep -Eq '^\s*notify' "$C" && ok "script de notification" || ko "pas de notify"

attendu=150; [ "$(hostname -s)" = lab-ha2 ] && attendu=100
grep -Eq "priority\s+$attendu\b" "$C" && ok "priorité $attendu sur $(hostname -s)" \
                                     || ko "priorité $attendu attendue sur $(hostname -s)"

# --- 2. qui porte l'IP, et un seul ------------------------------------------
porteur=0; ip -br addr show ens18 2>/dev/null | grep -q "$VIP/" && porteur=1
if command -v arping >/dev/null; then
  if arping -D -q -c 2 -w 3 -I ens18 "$VIP" >/dev/null 2>&1; then autre=0; else autre=1; fi
  case "$porteur$autre" in
    10) ok "ce nœud porte $VIP, et lui seul" ;;
    11) ko "ce nœud porte $VIP ET une autre machine aussi : split-brain VRRP" ;;
    01) ok "l'autre nœud porte $VIP" ;;
    00) ko "personne ne porte $VIP" ;;
  esac
else
  note "arping absent (apt install arping) : unicité de l'IP non vérifiée"
  [ "$porteur" -eq 1 ] && ok "ce nœud porte $VIP" || note "ce nœud ne porte pas $VIP"
fi
if [ "$porteur" -eq 1 ]; then
  systemctl is-active -q haproxy \
    && ok "HAProxy tourne sur le porteur de l'IP" \
    || ko "l'IP est sur un nœud sans HAProxy : le script de suivi ne fait pas son travail"
fi
code=$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://$VIP/")
[ "$code" = 200 ] && ok "http://$VIP/ répond 200" || ko "http://$VIP/ répond $code"

# --- 3. journal des transitions ----------------------------------------------
L=/var/log/keepalived-transitions.log
[ -s "$L" ] && ok "transitions journalisées ($(wc -l < "$L") lignes)" \
            || ko "$L absent ou vide"
note "les mesures de bascule se vérifient dans ~/lab29/mesures.md sur lab-adm"
fin
