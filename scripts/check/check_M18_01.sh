#!/usr/bin/env bash
# check_M18_01.sh — vérifie le lab L18.1 (politique de pare-feu)
# À lancer sur CHAQUE VM concernée : le rôle est déduit de l'adresse IP.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }

IPS=$(hostname -I 2>/dev/null || ip -4 -o addr show \
      | awk '{print $4}' | cut -d/ -f1)
case " $IPS " in
  *10.10.10.10*) ROLE=adm  ;;
  *10.10.10.11*) ROLE=web  ;;
  *10.10.10.12*) ROLE=db   ;;
  *10.10.10.13*) ROLE=rhel ;;
  *10.10.10.14*) ROLE=ops  ;;
  *) ROLE=inconnu ;;
esac
echo "== Vérification L18.1 (rôle détecté : $ROLE) =="
[ "$ROLE" = inconnu ] && note "IP hors plan d'adressage : contrôles \
génériques seulement"

# =====================================================================
# Machines firewalld (Rocky)
# =====================================================================
if command -v firewall-cmd >/dev/null 2>&1 && [ "$ROLE" = rhel ]; then
  if firewall-cmd --state >/dev/null 2>&1; then
    ok "firewalld est en fonctionnement"
  else
    ko "firewalld n'est pas démarré (systemctl enable --now firewalld)"
    echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
  fi

  [ "$(systemctl is-enabled firewalld 2>/dev/null)" = enabled ] \
    && ok "firewalld démarre au boot" \
    || ko "firewalld n'est pas enabled : la politique ne survivra pas \
au redémarrage"

  PUB=$(firewall-cmd --zone=public --list-all 2>/dev/null)
  grep -q 'services:.*http\b'  <<<"$PUB" \
    && ok "http ouvert dans la zone public"  \
    || ko "http absent de la zone public (--add-service=http)"
  grep -q 'services:.*https'   <<<"$PUB" \
    && ok "https ouvert dans la zone public" \
    || ko "https absent de la zone public (--add-service=https)"
  grep -q 'services:.*\bssh\b' <<<"$PUB" \
    && ko "ssh est encore ouvert dans public : il ne doit l'être que \
pour lab-adm" \
    || ok "ssh n'est pas ouvert à tous dans la zone public"

  ZSRC=$(firewall-cmd --get-active-zones 2>/dev/null)
  grep -q '10.10.10.10' <<<"$ZSRC" \
    && ok "10.10.10.10 est rattachée à une zone dédiée" \
    || ko "aucune zone n'a la source 10.10.10.10 \
(--zone=internal --add-source=10.10.10.10/32)"

  ZADM=$(awk '/^[a-z]/{z=$1} /10\.10\.10\.10/{print z}' <<<"$ZSRC" \
         | head -1)
  if [ -n "$ZADM" ]; then
    firewall-cmd --zone="$ZADM" --list-all 2>/dev/null \
      | grep -qE 'services:.*\bssh\b|port="22"' \
      && ok "la zone $ZADM autorise SSH" \
      || ko "la zone $ZADM ne contient pas ssh : lab-adm ne pourra pas \
se connecter"
  fi

  # permanent == runtime : la politique survivra-t-elle au reload ?
  R=$(firewall-cmd --list-all 2>/dev/null | grep -E 'services:|ports:')
  P=$(firewall-cmd --permanent --list-all 2>/dev/null \
      | grep -E 'services:|ports:')
  [ "$R" = "$P" ] \
    && ok "runtime et permanent sont identiques (survit au reboot)" \
    || ko "runtime et permanent divergent : il manque --permanent ou \
--runtime-to-permanent"

  echo "Résultat : $PASS réussis, $FAIL échoués"
  [ "$FAIL" -eq 0 ]; exit
fi

# =====================================================================
# Machines ufw (Ubuntu)
# =====================================================================
command -v ufw >/dev/null 2>&1 || {
  ko "ufw n'est pas installé (apt install ufw)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

ST=$(sudo -n ufw status verbose 2>/dev/null || ufw status verbose 2>/dev/null)
NUM=$(sudo -n ufw status numbered 2>/dev/null || ufw status numbered \
      2>/dev/null)
[ -n "$ST" ] || { ko "impossible de lire l'état de ufw (relance avec sudo)"
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

grep -q '^Status: active' <<<"$ST" \
  && ok "ufw est actif" \
  || ko "ufw est inactif (ufw enable — pense à autoriser SSH AVANT)"

grep -q 'deny (incoming)' <<<"$ST" \
  && ok "politique par défaut : deny incoming" \
  || ko "la politique entrante n'est pas deny (ufw default deny incoming)"

grep -q 'allow (outgoing)' <<<"$ST" \
  && ok "politique par défaut : allow outgoing" \
  || note "sortie non autorisée par défaut : assure-toi que DNS, NTP et \
les mises à jour passent"

regle() {   # regle <motif-port> <motif-source> <libellé>
  if grep -E "$1" <<<"$NUM" | grep -qE "$2"; then
    ok "$3"
  else
    ko "$3 — absent de « ufw status numbered »"
  fi
}

case "$ROLE" in
  web)
    regle '(80|443|Nginx)' 'Anywhere' "80/443 ouverts depuis n'importe où"
    regle '22'  '10\.10\.10\.10' "SSH autorisé depuis lab-adm"
    grep -E '^\[.*22/tcp' <<<"$NUM" | grep -q 'Anywhere' \
      && ko "SSH est ouvert à tous : il ne doit l'être que depuis \
10.10.10.10" \
      || ok "SSH n'est pas ouvert à tous"
    grep -qiE '5432|3306' <<<"$NUM" \
      && ko "un port de base de données est ouvert sur le frontal web" \
      || ok "aucun port de base de données ouvert"
    ;;
  db)
    regle '5432' '10\.10\.10\.11' "5432 autorisé depuis lab-web uniquement"
    regle '22'   '10\.10\.10\.10' "SSH autorisé depuis lab-adm"
    grep -E '^\[.*5432' <<<"$NUM" | grep -q 'Anywhere' \
      && ko "5432 est ouvert à tous : supprime cette règle \
(ufw delete <n>)" \
      || ok "5432 n'est pas ouvert à tous"
    grep -qE '^\[.*(80|443)/tcp.*Anywhere' <<<"$NUM" \
      && ko "un port web est ouvert sur la base de données" \
      || ok "aucun port web ouvert sur la base"
    ;;
  adm)
    regle '22' '10\.10\.10\.0/24' "SSH autorisé depuis le réseau du lab"
    n=$(grep -c '^\[' <<<"$NUM")
    [ "${n:-0}" -le 4 ] \
      && ok "surface réduite : $n règle(s) seulement" \
      || ko "$n règles sur le bastion : l'énoncé n'en demande qu'une"
    ;;
  *)
    grep -q '^\[' <<<"$NUM" \
      && ok "des règles utilisateur existent" \
      || ko "aucune règle utilisateur définie"
    ;;
esac

# --- l'ordre des règles : aucun DENY avant un ALLOW sur le même port ---
premier_deny=$(grep -nE '^\[.*(DENY|REJECT) IN' <<<"$NUM" \
               | head -1 | cut -d: -f1)
premier_allow=$(grep -nE '^\[.*ALLOW IN' <<<"$NUM" | head -1 | cut -d: -f1)
if [ -n "$premier_deny" ] && [ -n "$premier_allow" ] \
   && [ "$premier_deny" -lt "$premier_allow" ]; then
  ko "une règle DENY précède la première règle ALLOW : vérifie l'ordre \
(ufw insert 1 ...)"
else
  ok "aucune règle de refus ne précède les autorisations"
fi

# --- ce que voit le noyau, pas seulement ufw --------------------------
if command -v nft >/dev/null 2>&1; then
  RS=$(sudo -n nft list ruleset 2>/dev/null)
  if [ -n "$RS" ]; then
    grep -q 'ufw' <<<"$RS" \
      && ok "les règles ufw sont bien chargées dans le noyau" \
      || ko "aucune chaîne ufw dans nft list ruleset : ufw n'applique rien"
  else
    note "nft list ruleset illisible sans sudo : contrôle noyau ignoré"
  fi
fi

# --- la matrice de flux ------------------------------------------------
LAB_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
MAT="$LAB_HOME/lab18/matrice-flux.md"
if [ -f "$MAT" ]; then
  n=$(grep -cE '10\.10\.10\.[0-9]+' "$MAT")
  [ "${n:-0}" -ge 6 ] \
    && ok "matrice de flux présente ($n lignes de test)" \
    || ko "la matrice ne documente que $n flux, l'énoncé en demande 6"
else
  note "~/lab18/matrice-flux.md absent (à produire depuis lab-adm)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
