#!/usr/bin/env bash
# check_M16_02.sh — vérifie le lab L16.2 (centralisation rsyslog)
#                   À LANCER SUR lab-ops (10.10.10.14).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L16.2 (collecteur) =="

CENTRAL=/var/log/central
CONFD=/etc/rsyslog.d

# --- 1. le collecteur écoute --------------------------------------------
if ss -tlnp 2>/dev/null | grep -q ':10514 '; then
  ok "un service écoute en TCP sur le port 10514"
else
  ko "rien n'écoute en TCP sur 10514 (module imtcp chargé ? \
rsyslog redémarré ?)"
fi

if ss -ulnp 2>/dev/null | grep -qE ':514 '; then
  ko "le port 514 UDP est ouvert : le lab demande du TCP sur 10514 \
uniquement"
else
  ok "aucune écoute UDP sur 514"
fi

if grep -rqsE '^\s*module\(load="imtcp"|^\s*\$ModLoad imtcp' \
     /etc/rsyslog.conf "$CONFD" 2>/dev/null; then
  ok "le module imtcp est chargé dans la configuration"
else
  ko "imtcp n'apparaît nulle part dans /etc/rsyslog.conf ni $CONFD"
fi

# --- 2. le rangement par hôte et par programme ---------------------------
if [ -d "$CENTRAL" ]; then
  ok "$CENTRAL existe"
else
  ko "$CENTRAL absent"
fi

if [ -d "$CENTRAL/lab-web" ]; then
  ok "$CENTRAL/lab-web existe : les messages distants arrivent"
  NB=$(find "$CENTRAL/lab-web" -type f -name '*.log' 2>/dev/null | wc -l)
  [ "$NB" -ge 1 ] && ok "$NB fichier(s) de programme rangés pour lab-web" \
    || ko "aucun fichier .log sous $CENTRAL/lab-web (template mal formé ?)"
  if find "$CENTRAL/lab-web" -type f -newermt '-10 minutes' 2>/dev/null \
       | grep -q .; then
    ok "au moins un fichier a été écrit dans les 10 dernières minutes"
  else
    ko "rien n'a été écrit récemment (envoie un logger depuis lab-web)"
  fi
else
  ko "$CENTRAL/lab-web absent : le nom d'hôte n'est pas exploité par le \
template, ou rien n'arrive"
fi

# --- 3. le service bruyant ne traverse pas le réseau ---------------------
if [ -d "$CENTRAL" ]; then
  if grep -rqs 'factura-bruyant' "$CENTRAL" 2>/dev/null || \
     find "$CENTRAL" -name '*bruyant*' 2>/dev/null | grep -q .; then
    ko "factura-bruyant est arrivé sur le collecteur : le filtre côté \
lab-web ne fonctionne pas"
  else
    ok "aucune trace de factura-bruyant sur le collecteur"
  fi
fi

# --- 4. les messages locaux restent locaux -------------------------------
HOTE=$(hostname -s)
if [ -d "$CENTRAL/$HOTE" ] && \
   find "$CENTRAL/$HOTE" -type f 2>/dev/null | grep -q .; then
  ko "les messages locaux de $HOTE atterrissent dans $CENTRAL : \
sépare l'entrée réseau dans un ruleset dédié"
else
  ok "les messages locaux ne polluent pas $CENTRAL"
fi

# --- 5. pare-feu ---------------------------------------------------------
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q active
then
  if ufw status 2>/dev/null | grep -q '10514'; then
    ufw status 2>/dev/null | grep '10514' | grep -q '10.10.10.0/24' \
      && ok "ufw autorise 10514 depuis 10.10.10.0/24 uniquement" \
      || ko "la règle ufw sur 10514 n'est pas limitée à 10.10.10.0/24"
  else
    ko "aucune règle ufw pour le port 10514"
  fi
else
  note "ufw inactif : vérifie toi-même le filtrage réseau du port 10514"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
