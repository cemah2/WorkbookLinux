#!/usr/bin/env bash
# check_M29_01.sh — vérifie le lab L29.1 (répartiteur HAProxy)
# À lancer avec sudo sur lab-ha1, puis sur lab-ha2.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L29.1 sur $(hostname -s) =="

[ "$(id -u)" -eq 0 ] || { ko "à lancer avec sudo"; fin; }
command -v haproxy >/dev/null || { ko "HAProxy absent (apt install haproxy)"; fin; }
CFG=/etc/haproxy/haproxy.cfg

# --- 1. service et configuration -------------------------------------------
systemctl is-active -q haproxy && ok "haproxy actif" || ko "haproxy n'est pas actif"
systemctl is-enabled -q haproxy && ok "haproxy activé au démarrage" \
                                || ko "haproxy non activé au démarrage"
haproxy -c -q -f "$CFG" 2>/dev/null && ok "configuration valide (haproxy -c)" \
                                    || ko "configuration invalide : haproxy -c -f $CFG"

grep -Eq '^\s*server\s+\S+\s+10\.10\.10\.11:8029\b.*\bcheck\b' "$CFG" \
  && ok "serveur lab-web:8029 contrôlé" || ko "pas de serveur 10.10.10.11:8029 avec check"
grep -Eq '^\s*server\s+\S+\s+10\.10\.10\.14:8029\b.*\bcheck\b' "$CFG" \
  && ok "serveur lab-ops:8029 contrôlé" || ko "pas de serveur 10.10.10.14:8029 avec check"
grep -Eq 'option\s+httpchk' "$CFG" && grep -Eq '/sante' "$CFG" \
  && ok "contrôle de santé HTTP sur /sante" \
  || ko "pas de contrôle de niveau 7 sur /sante (option httpchk + http-check)"
grep -Eq 'option\s+forwardfor' "$CFG" \
  && ok "X-Forwarded-For transmis" || ko "option forwardfor absente"
grep -Eq 'X-Backend' "$CFG" \
  && ok "en-tête X-Backend configuré" || ko "pas d'en-tête X-Backend"

# --- 2. comportement ----------------------------------------------------------
vus=$(for _ in 1 2 3 4 5 6; do
        curl -s -m 3 -D - -o /dev/null http://127.0.0.1/ | tr -d '\r' |
          awk -F': ' 'tolower($1)=="x-backend"{print $2}'
      done | sort -u | paste -sd' ' -)
case "$vus" in
  *" "*) ok "les requêtes alternent entre serveurs : $vus" ;;
  "")    ko "aucune réponse avec X-Backend sur le port 80" ;;
  *)     ko "un seul serveur répond ($vus) : l'autre est-il DOWN ?" ;;
esac

if [ -S /run/haproxy/admin.sock ] && command -v socat >/dev/null; then
  etat=$(echo "show stat" | socat stdio /run/haproxy/admin.sock 2>/dev/null |
         awk -F, 'NR>1 && $2!="FRONTEND" && $2!="BACKEND" && $1!="stats" {print $2"="$18}')
  if grep -q . <<<"$etat" && ! grep -qv '=UP' <<<"$etat"; then
    ok "socket d'administration : $(paste -sd' ' - <<<"$etat")"
  else
    ko "état des serveurs : $(paste -sd' ' - <<<"$etat")"
  fi
else
  note "socket /run/haproxy/admin.sock ou socat absent (apt install socat)"
fi

# --- 3. statistiques réservées à lab-adm ------------------------------------
code=$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:8404/)
case "$code" in
  403) ok "statistiques (8404) refusées depuis une autre machine que lab-adm" ;;
  200) ko "statistiques (8404) ouvertes à tous : restreins à 10.10.10.10" ;;
  *)   ko "rien sur le port 8404 (code $code)" ;;
esac

note "empreinte de la configuration : $(sha256sum "$CFG" | cut -c1-16)… (doit être identique sur l'autre nœud)"
fin
