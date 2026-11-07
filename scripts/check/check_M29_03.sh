#!/usr/bin/env bash
# check_M29_03.sh — vérifie le lab L29.3 (cluster, qdevice, fencing)
# À lancer avec sudo sur lab-ha1.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L29.3 =="

[ "$(id -u)" -eq 0 ] || { ko "à lancer avec sudo"; fin; }
command -v pcs >/dev/null || { ko "pcs absent (apt install pcs pacemaker corosync)"; fin; }

# --- 1. cluster -----------------------------------------------------------------
grep -Eq '^\s*cluster_name:\s*lab29\b' /etc/corosync/corosync.conf 2>/dev/null \
  && ok "cluster lab29" || ko "corosync.conf ne déclare pas cluster_name: lab29"
for s in corosync pacemaker; do
  systemctl is-active -q "$s" && ok "$s actif" || ko "$s n'est pas actif"
  systemctl is-enabled -q "$s" && ok "$s activé au démarrage" || ko "$s non activé (pcs cluster enable --all)"
done
EN_LIGNE=$(crm_mon -1 2>/dev/null | grep -E 'Online:' | head -1)
grep -q lab-ha1 <<<"$EN_LIGNE" && grep -q lab-ha2 <<<"$EN_LIGNE" \
  && ok "deux nœuds en ligne" || ko "nœuds en ligne : ${EN_LIGNE:-aucun}"

# --- 2. quorum et arbitre -------------------------------------------------------
Q=$(corosync-quorumtool -s 2>/dev/null)
grep -Eq 'Expected votes:\s+3' <<<"$Q" && ok "3 votes attendus" \
                                       || ko "3 votes attendus (qdevice ajouté ?)"
grep -Eq 'Flags:.*Qdevice' <<<"$Q" && ok "qdevice actif" || ko "pas de qdevice dans le quorum"
grep -Eq 'Flags:.*Quorate' <<<"$Q" && ok "cluster avec quorum" || ko "cluster sans quorum"
grep -q 'ffsplit' /etc/corosync/corosync.conf 2>/dev/null \
  && ok "algorithme ffsplit" || ko "algorithme ffsplit attendu pour le qdevice"
grep -Eq '^\s*two_node:\s*1' /etc/corosync/corosync.conf 2>/dev/null \
  && ko "two_node: 1 toujours présent avec un qdevice" || ok "pas de two_node avec le qdevice"

# --- 3. fencing -------------------------------------------------------------------
SE=$(crm_attribute -t crm_config -n stonith-enabled -G -q 2>/dev/null || echo true)
[ "$SE" = true ] && ok "stonith-enabled=true" \
                 || ko "stonith-enabled=$SE : un cluster sans fencing peut produire deux instances"
pcs stonith status 2>/dev/null | grep -q 'fence-pve.*Started' \
  && ok "ressource de fencing fence-pve démarrée" || ko "fence-pve absente ou arrêtée"
MAP=$(crm_resource -r fence-pve -g pcmk_host_map 2>/dev/null)
grep -q 'lab-ha1:9021' <<<"$MAP" && grep -q 'lab-ha2:9022' <<<"$MAP" \
  && ok "correspondance nœuds -> VM : $MAP" \
  || ko "pcmk_host_map incorrect : « ${MAP:-absent} » (lab-ha1:9021;lab-ha2:9022)"
if stonith_admin --history '*' 2>/dev/null | grep -q 'successful'; then
  ok "au moins un fencing réussi dans l'historique"
else
  ko "aucun fencing réussi dans l'historique : pcs stonith fence lab-ha2 (étape 6)"
fi

# --- 4. hygiène -------------------------------------------------------------------
systemctl is-enabled -q lab29-batch 2>/dev/null \
  && ko "lab29-batch est activé dans systemd : seul Pacemaker doit le démarrer" \
  || ok "lab29-batch n'est pas activé dans systemd"
fin
