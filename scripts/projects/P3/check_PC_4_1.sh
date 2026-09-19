#!/usr/bin/env bash
# check_PC_4_1.sh — vérifie le ticket PC.4.1 (ouverture de port partenaire)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification PC.4.1 =="
SAUV=/root/.breakfix-backup; ID=PC_4_1
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo (lecture ufw)" >&2; exit 1; }

# le service partenaire écoute
ss -tlnH 'sport = :9443' | grep -q 9443 \
  && ok "un service écoute sur 9443" \
  || ko "rien n'écoute sur 9443 (systemctl status partenaire-collecte)"

RULES=$(ufw status verbose 2>/dev/null)
if echo "$RULES" | grep -q '9443'; then
  ok "une règle ufw concerne le port 9443"
  # règle restreinte à l'IP du partenaire, pas ouverte à tous
  if echo "$RULES" | grep '9443' | grep -q '203.0.113.42'; then
    ok "la règle est restreinte à l'IP du partenaire (moindre privilège)"
  else
    ko "le port 9443 est ouvert sans restriction de source (Anywhere) : \
limite-le à 203.0.113.42"
  fi
  echo "$RULES" | grep '9443' | grep -qiE 'tcp' \
    && ok "restreinte au protocole tcp" \
    || ko "la règle n'est pas limitée à tcp"
else
  ko "aucune règle ufw pour 9443 (ufw status)"
fi

# les services essentiels restent joignables
for p in 22 443; do
  echo "$RULES" | grep -qE "^$p/tcp|(^| )$p " \
    && ok "port $p toujours autorisé" \
    || note "vérifie que le port $p reste autorisé"
done

# aucun autre port n'a été ouvert par erreur
INATTENDU=$(echo "$RULES" | grep -cE 'Anywhere' )
note "règles 'Anywhere' présentes : $INATTENDU (doivent rester limitées à 22/80/443)"

if [ -r "$SAUV/$ID.debut" ]; then
  note "temps écoulé : $(( ($(date +%s) - $(cat "$SAUV/$ID.debut")) / 60 )) min"
fi
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
