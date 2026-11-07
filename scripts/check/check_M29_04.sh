#!/usr/bin/env bash
# check_M29_04.sh — vérifie le lab L29.4 (service unique sous Pacemaker)
# À lancer avec sudo sur lab-ha1.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L29.4 =="

[ "$(id -u)" -eq 0 ] || { ko "à lancer avec sudo"; fin; }
command -v pcs >/dev/null || { ko "pcs absent"; fin; }

# --- 1. règles générales ----------------------------------------------------------
ST=$(crm_attribute -t rsc_defaults -n resource-stickiness -G -q 2>/dev/null)
[ "$ST" = 100 ] && ok "adhérence par défaut : 100" || ko "resource-stickiness=${ST:-absent} (100 attendu)"
NQ=$(crm_attribute -t crm_config -n no-quorum-policy -G -q 2>/dev/null)
[ "$NQ" = stop ] && ok "no-quorum-policy=stop" || ko "no-quorum-policy=${NQ:-défaut} (stop attendu)"

# --- 2. le groupe -------------------------------------------------------------------
CIB=$(cibadmin -Q 2>/dev/null)
grep -q '<group id="grp-batch"' <<<"$CIB" && ok "groupe grp-batch" || { ko "pas de groupe grp-batch"; fin; }
grep -q 'value="10.10.10.25"' <<<"$CIB" && ok "IP 10.10.10.25 dans le cluster" \
                                       || ko "pas de ressource IPaddr2 pour 10.10.10.25"
grep -q 'type="lab29-batch"' <<<"$CIB" && ok "service lab29-batch géré (systemd:lab29-batch)" \
                                      || ko "lab29-batch n'est pas une ressource du groupe"
LOC=$(crm_resource --locate -r grp-batch 2>/dev/null)
n=$(grep -c 'is running on' <<<"$LOC")
[ "$n" -eq 1 ] && ok "grp-batch tourne sur un seul nœud : ${LOC##* }" \
               || ko "grp-batch tourne sur $n nœud(s)"
grep -Eq 'rsc="grp-batch"[^>]*node="lab-ha1"[^>]*score="50"|rsc="grp-batch"[^>]*score="50"[^>]*node="lab-ha1"' <<<"$CIB" \
  && ok "préférence 50 pour lab-ha1" || ko "pas de contrainte location grp-batch prefers lab-ha1=50"
grep -Eq 'id="cli-(prefer|ban)-' <<<"$CIB" \
  && ko "contrainte de déplacement oubliée (cli-prefer/cli-ban) : pcs resource clear" \
  || ok "aucune contrainte de déplacement oubliée"

code=$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://10.10.10.25:9029/)
[ "$code" = 200 ] && ok "http://10.10.10.25:9029/ répond : $(curl -s -m 3 http://10.10.10.25:9029/)" \
                  || ko "http://10.10.10.25:9029/ répond $code"

# --- 3. preuve par la coupure ------------------------------------------------------
nf=$(stonith_admin --history '*' 2>/dev/null | grep -c 'successful')
[ "$nf" -ge 2 ] && ok "$nf fencings réussis dans l'historique (test manuel + coupure)" \
                || ko "$nf fencing(s) réussi(s) : la coupure de l'étape 6 n'a pas été faite ?"
crm_mon -1f 2>/dev/null | grep -q 'fail-count' \
  && ko "compteurs d'échecs non nettoyés (pcs resource cleanup)" \
  || ok "aucun compteur d'échecs en suspens"
fin
