#!/usr/bin/env bash
# check_M20_06.sh — vérifie le défi D20 (parc, sauvegarde, restauration,
# inventaire). À lancer sur lab-virt, en tant que mathieu, sans sudo.
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification D20 =="

V="virsh -c qemu:///system"
L="$HOME/lab20"

# --- fichiers ---------------------------------------------------------------
for f in parc.txt bin/parc.sh bin/sauvegarde-vm.sh bin/restaure-vm.sh bin/inventaire.py \
         bin/usine-vm.sh rapports/d20.md; do
  [ -s "$L/$f" ] && ok "$f présent" || ko "$f absent"
done
for s in parc.sh sauvegarde-vm.sh restaure-vm.sh usine-vm.sh; do
  [ -s "$L/bin/$s" ] && { bash -n "$L/bin/$s" 2>/dev/null && ok "$s : bash -n" \
    || ko "$s : erreur de syntaxe"; }
done
[ -s "$L/bin/inventaire.py" ] && { python3 -m py_compile "$L/bin/inventaire.py" 2>/dev/null \
  && ok "inventaire.py : compile" || ko "inventaire.py : erreur de syntaxe"; }
grep -q 'trap' "$L/bin/sauvegarde-vm.sh" 2>/dev/null \
  && ok "sauvegarde-vm.sh a un trap (blockcommit garanti)" \
  || ko "sauvegarde-vm.sh sans trap : un overlay peut rester derrière"
grep -qE '^p-web|^p-app|^p-db' "$L/parc.txt" 2>/dev/null \
  && ok "parc.txt décrit p-web, p-app, p-db" || ko "parc.txt incomplet"

# --- le parc -------------------------------------------------------------------
for vm in p-web p-app p-db; do
  if [ "$($V domstate $vm 2>/dev/null)" = running ]; then
    ok "$vm en marche"
  else
    ko "$vm absente ou éteinte (parc.sh apply parc.txt)"; continue
  fi
  IFS=$'\n' read -r -d '' -a NETS < <($V domiflist $vm | awk 'NR>2 && NF{print $3}'; printf '\0')
  case "$vm" in
    p-db)
      printf '%s\n' "${NETS[@]}" | grep -qx isole && ok "p-db sur isole" || ko "p-db pas sur isole"
      printf '%s\n' "${NETS[@]}" | grep -qxE 'lan|br0' && ko "p-db ne doit pas être sur lan" \
        || ok "p-db hors du LAN" ;;
    *)
      printf '%s\n' "${NETS[@]}" | grep -qxE 'lan|br0' && ok "$vm sur lan" || ko "$vm pas sur lan"
      printf '%s\n' "${NETS[@]}" | grep -qx isole && ok "$vm sur isole" || ko "$vm pas sur isole" ;;
  esac
done
ping -c1 -W1 10.10.10.170 >/dev/null 2>&1 && ok "p-web répond en 10.10.10.170" \
  || ko "10.10.10.170 ne répond pas"
ping -c1 -W1 10.10.10.171 >/dev/null 2>&1 && ok "p-app répond en 10.10.10.171" \
  || ko "10.10.10.171 ne répond pas"

# --- idempotence de apply ---------------------------------------------------
if [ -x "$L/bin/parc.sh" ]; then
  N0=$($V list --all --name | grep -c .)
  T0=$(date +%s)
  ( cd "$L" && timeout 60 bin/parc.sh apply parc.txt >/dev/null 2>&1 ); rc=$?
  T=$(( $(date +%s) - T0 ))
  [ "$rc" -eq 0 ] && ok "parc.sh apply (second passage) : code 0" || ko "parc.sh apply : code $rc"
  [ "$T" -le 15 ] && ok "second apply en ${T}s" || ko "second apply trop long (${T}s) : recrée ?"
  [ "$N0" -eq "$($V list --all --name | grep -c .)" ] && ok "aucune VM créée au second apply" \
    || ko "le second apply a créé des VM"
  ( cd "$L" && timeout 60 bin/parc.sh status parc.txt 2>/dev/null | grep -q 'p-db' ) \
    && ok "parc.sh status liste p-db" || ko "parc.sh status ne fonctionne pas"
else
  ko "parc.sh non exécutable"
fi

# --- sauvegardes -----------------------------------------------------------------
LAST=$(ls -1t "$L"/backups/p-db/*.qcow2 2>/dev/null | head -1)
if [ -n "$LAST" ]; then
  ok "sauvegarde de p-db présente"
  qemu-img info "$LAST" 2>/dev/null | grep -q '^backing file' \
    && ko "sauvegarde p-db non autoportante" || ok "sauvegarde p-db autoportante"
  [ -s "${LAST%.qcow2}.xml" ] && ok "XML joint" || ko "XML absent à côté de la sauvegarde"
  [ "$(ls -1 "$L"/backups/p-db/*.qcow2 | wc -l)" -le 3 ] && ok "rotation : 3 sauvegardes max" \
    || ko "plus de 3 sauvegardes conservées"
else
  ko "aucune sauvegarde dans backups/p-db/"
fi
[ -s "$L/backups/sauvegarde.log" ] && ok "journal sauvegarde.log" || ko "sauvegarde.log absent"
for vm in p-web p-app p-db; do
  $V domblklist $vm 2>/dev/null | awk '$1=="vda"{print $2}' | grep -q '\.sauv' \
    && ko "$vm tourne encore sur un overlay .sauv" || ok "$vm sans overlay résiduel"
done

# --- inventaire ------------------------------------------------------------------
if [ -s "$L/bin/inventaire.py" ]; then
  OUT=$(python3 "$L/bin/inventaire.py" 2>/dev/null)
  printf '%s' "$OUT" | jq -e 'map(select(.nom=="p-db")) | length == 1' >/dev/null 2>&1 \
    && ok "inventaire.py : JSON valide avec p-db" || ko "inventaire.py : JSON invalide ou sans p-db"
  INV=$(python3 "$L/bin/inventaire.py" --ansible 2>/dev/null)
  grep -q '^\[lan\]' <<<"$INV" && grep -q '^\[isole\]' <<<"$INV" \
    && ok "--ansible : groupes [lan] et [isole]" || ko "--ansible : groupes attendus absents"
  grep -qE '^p-web ansible_host=10\.10\.10\.170' <<<"$INV" \
    && ok "--ansible : p-web ansible_host=10.10.10.170" \
    || ko "--ansible : p-web sans ansible_host sur lan"
fi

# --- rapport ---------------------------------------------------------------------
R="$L/rapports/d20.md"
[ -s "$R" ] && grep -q 'vzdump' "$R" && grep -q 'qm ' "$R" \
  && ok "rapport d20.md avec les équivalents Proxmox" || ko "rapport $R incomplet"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
