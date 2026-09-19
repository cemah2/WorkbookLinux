#!/usr/bin/env bash
# check_M05_05.sh — vérifie le lab L5.5 (brute force SSH)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L5.5 =="

BASE="$HOME/lab05"
BAN="$BASE/rapports/ips-a-bannir.txt"
SH="$BASE/rapports/ips-a-bannir.sh"
RAP="$BASE/rapports/rapport-ssh.txt"

[ -f "$BASE/journal-ssh.txt" ] || { ko "journal-ssh.txt absent (setup_M05.sh)"; \
  echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1; }

ATTENDU='45.155.205.14
185.220.101.7
141.98.11.62
92.63.197.5
218.92.0.31'

# --- 1. liste de bannissement -------------------------------------------
if [ -s "$BAN" ]; then
  ok "rapports/ips-a-bannir.txt existe"
  obtenu=$(tr -d ' \r' < "$BAN" | grep -c .)
  [ "$obtenu" -eq 5 ] && ok "5 adresses retenues (seuil de 50 échecs)" \
                      || ko "$obtenu adresses au lieu de 5 : revois le seuil ou le filtre"
  if [ "$(tr -d ' \r' < "$BAN" | grep .)" = "$ATTENDU" ]; then
    ok "les 5 IP sont les bonnes, dans l'ordre décroissant des échecs"
  else
    ko "contenu ou ordre incorrect (tri par nombre d'échecs décroissant, sans compteur)"
  fi
  if grep -qE '^[[:space:]]*[0-9]+[[:space:]]+[0-9]' "$BAN"; then
    ko "le fichier contient encore les compteurs de uniq -c : il doit être consommable tel quel"
  else
    ok "le fichier ne contient que des adresses"
  fi
else
  ko "rapports/ips-a-bannir.txt absent ou vide (étape 5)"
fi

# --- 2. commandes générées ----------------------------------------------
if [ -s "$SH" ]; then
  ok "rapports/ips-a-bannir.sh existe"
  n=$(grep -c 'ufw deny from' "$SH")
  [ "$n" -eq 5 ] && ok "5 commandes ufw générées" \
                 || ko "$n commandes 'ufw deny from' au lieu de 5"
  grep -q 'ufw deny from 45.155.205.14 to any port 22' "$SH" \
    && ok "la syntaxe des commandes est conforme" \
    || ko "syntaxe attendue : sudo ufw deny from <IP> to any port 22"
else
  ko "rapports/ips-a-bannir.sh absent ou vide (étape 6)"
fi

# --- 3. rapport ---------------------------------------------------------
if [ -s "$RAP" ]; then
  ok "rapports/rapport-ssh.txt existe"
  for v in 900 623 76; do
    grep -qw "$v" "$RAP" && ok "le chiffre $v figure dans le rapport" \
                         || ko "le chiffre $v manque (total / échecs / acceptées)"
  done
  grep -q '45.155.205.14' "$RAP" \
    && ok "le top des IP figure dans le rapport" \
    || ko "le top 5 des IP manque (étape 7)"
  grep -qw 'root' "$RAP" && grep -qw 'oracle\|test\|admin' "$RAP" \
    && ok "le top des comptes visés figure dans le rapport" \
    || ko "le top 5 des comptes visés manque (attention aux 'invalid user')"
  grep -qw '185' "$RAP" && note "vérifie que 185 correspond bien aux échecs sur root"
else
  ko "rapports/rapport-ssh.txt absent ou vide (étape 7)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
