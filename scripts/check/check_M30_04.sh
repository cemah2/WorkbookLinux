#!/usr/bin/env bash
# check_M30_04.sh — vérifie le lab L30.4 (vzdump et restauration isolée)
# À lancer en root sur le nœud Proxmox.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L30.4 =="

[ "$(id -u)" -eq 0 ] || { ko "à lancer en root"; fin; }
command -v qm >/dev/null || { ko "qm absent : ce contrôle se lance sur le nœud Proxmox"; fin; }

# --- 1. pont isolé --------------------------------------------------------------
if ip link show vmbr9 >/dev/null 2>&1; then
  ok "pont vmbr9 présent"
  ports=$(bridge link show 2>/dev/null | awk '/master vmbr9/{print $2}' | tr -d ':' | grep -Ev '^(tap|fwpr|veth)' || true)
  [ -z "$ports" ] && ok "vmbr9 n'a aucun port physique" || ko "vmbr9 est relié à : $ports"
  ip -4 addr show vmbr9 | grep -q inet && ko "vmbr9 a une adresse IP sur le nœud" \
                                      || ok "vmbr9 n'a pas d'adresse sur le nœud"
else
  ko "pas de pont vmbr9"
fi

# --- 2. sauvegarde et rétention ---------------------------------------------------
D=$(find /var/lib/vz/dump -name 'vzdump-qemu-9002-*.vma.zst' -mtime -7 2>/dev/null | sort | tail -1)
[ -n "$D" ] && ok "sauvegarde récente de 9002 : $(basename "$D")" || ko "aucune sauvegarde de 9002 de moins de 7 jours"
L=${D%.vma.zst}.log
[ -n "$D" ] && grep -q "fs-freeze" "$L" 2>/dev/null && ok "systèmes de fichiers gelés par l'agent (fs-freeze)" \
                                                   || ko "pas de fs-freeze dans le journal de la sauvegarde"
if pvesh get /cluster/backup --output-format json 2>/dev/null | grep -q '"prune-backups"' ||
   grep -Eq 'prune-backups' /etc/pve/storage.cfg; then
  ok "rétention configurée (tâche planifiée ou stockage)"
else
  ko "aucune rétention prune-backups configurée"
fi

# --- 3. la VM restaurée -------------------------------------------------------------
if qm config 9102 >/dev/null 2>&1; then
  C=$(qm config 9102)
  grep -q '^name: lab-web-pra' <<<"$C" && ok "VM 9102 nommée lab-web-pra" || ko "VM 9102 mal nommée"
  grep -q '^net0:.*bridge=vmbr9' <<<"$C" && ok "9102 branchée sur vmbr9" || ko "9102 n'est pas sur vmbr9"
  grep -q '^onboot: 1' <<<"$C" && ko "9102 démarre avec le nœud" || ok "9102 ne démarre pas avec le nœud"
  m1=$(qm config 9002 | sed -n 's/^net0: [a-z0-9]*=\([^,]*\),.*/\1/p')
  m2=$(sed -n 's/^net0: [a-z0-9]*=\([^,]*\),.*/\1/p' <<<"$C")
  [ -n "$m2" ] && [ "${m1,,}" != "${m2,,}" ] && ok "MAC différente de la production" \
                                            || ko "même MAC que 9002 : --unique oublié"
else
  ko "pas de VM 9102 (étape 4)"
fi
[ -s /root/lab30/rto.md ] && ok "RTO consigné dans /root/lab30/rto.md" \
                          || note "rto.md absent ici : vérifie qu'il est sur lab-adm (~/lab30/rto.md)"
fin
