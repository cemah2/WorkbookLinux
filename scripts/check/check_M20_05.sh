#!/usr/bin/env bash
# check_M20_05.sh — vérifie le lab L20.5 (usine-vm.sh : création, idempotence,
# suppression). Crée puis détruit une VM de test « chk-m20 » (1 à 3 min).
# À lancer sur lab-virt, en tant que mathieu, sans sudo.
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification L20.5 =="

V="virsh -c qemu:///system"
S="$HOME/lab20/bin/usine-vm.sh"
TEST=chk-m20

# --- le script ------------------------------------------------------------
if [ ! -s "$S" ]; then
  ko "$S absent"; echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi
[ -x "$S" ] && ok "usine-vm.sh exécutable" || ko "usine-vm.sh n'est pas exécutable"
bash -n "$S" 2>/dev/null && ok "syntaxe bash valide" || ko "bash -n échoue"
head -1 "$S" | grep -q '^#!/usr/bin/env bash' && ok "shebang env bash" \
  || ko "shebang attendu : #!/usr/bin/env bash"
grep -q 'set -euo pipefail' "$S" && ok "set -euo pipefail" || ko "set -euo pipefail absent"
grep -q -- '--help' "$S" && "$S" --help >/dev/null 2>&1 && ok "--help répond en 0" \
  || ko "--help absent ou en erreur"
grep -q 'TODO' "$S" && ko "des TODO subsistent dans le script" || ok "plus de TODO"
grep -q 'sudo' "$S" && ko "le script appelle sudo (tout doit passer par l'API libvirt)" \
  || ok "aucun sudo dans le script"
"$S" --name 'Nom Invalide!' >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "nom invalide refusé avec le code 2" \
  || ko "nom invalide : code $rc attendu 2"
"$S" --name chk-bridge --net bridge=br0 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "bridge sans --ip refusé avec le code 2" \
  || ko "bridge sans --ip : code $rc attendu 2"

# --- usine-1 en marche ------------------------------------------------------
if [ "$($V domstate usine-1 2>/dev/null)" = running ]; then
  ok "usine-1 en marche"
  IP=$($V domifaddr usine-1 --source agent 2>/dev/null | awk '/ipv4/ && !/127\./{print $4}' \
       | cut -d/ -f1 | head -1)
  [ -z "$IP" ] && IP=$($V domifaddr usine-1 2>/dev/null | awk '/ipv4/{print $4}' | cut -d/ -f1 | head -1)
  [ -n "$IP" ] && timeout 3 bash -c "exec 3<>/dev/tcp/$IP/22" 2>/dev/null \
    && ok "usine-1 répond sur le port 22 ($IP)" || ko "usine-1 : pas de SSH joignable"
  $V dumpxml usine-1 | grep -q "<domain type='kvm'" && ok "usine-1 en kvm" || ko "usine-1 en TCG"
  $V dumpxml usine-1 | grep -q "discard='unmap'" && ok "usine-1 : discard=unmap" \
    || ko "usine-1 : discard=unmap absent"
  N0=$($V list --all --name | grep -c .)
  T0=$(date +%s)
  "$S" --name usine-1 >/dev/null 2>&1; rc=$?
  T=$(( $(date +%s) - T0 ))
  N1=$($V list --all --name | grep -c .)
  [ "$rc" -eq 0 ] && ok "relance sur usine-1 : code 0" || ko "relance sur usine-1 : code $rc"
  [ "$T" -le 5 ] && ok "relance en ${T}s (aucune création)" || ko "relance trop longue (${T}s)"
  [ "$N0" -eq "$N1" ] && ok "nombre de VM inchangé" || ko "la relance a créé quelque chose"
else
  ko "usine-1 n'est pas en marche (usine-vm.sh --name usine-1)"
fi

# --- création puis suppression d'une VM de test ---------------------------
$V dominfo $TEST >/dev/null 2>&1 && "$S" --name $TEST --delete >/dev/null 2>&1
echo "  [....] création de $TEST (jusqu'à 4 min)"
if timeout 240 "$S" --name $TEST --ram 512 >/dev/null 2>&1; then
  ok "$TEST créée et joignable"
else
  ko "création de $TEST échouée ou trop longue (journal du script sur stderr)"
fi
"$S" --name $TEST --delete >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "--delete sort en 0" || ko "--delete : code $rc"
$V dominfo $TEST >/dev/null 2>&1 && ko "$TEST existe encore après --delete" \
  || ok "$TEST supprimée"
for v in $TEST.qcow2 $TEST-seed.iso; do
  $V vol-info --pool default "$v" >/dev/null 2>&1 \
    && ko "volume $v orphelin après --delete" || ok "volume $v supprimé"
done
[ -d "$HOME/lab20/cloud-init/$TEST" ] && ko "répertoire de seed de $TEST non supprimé" \
  || ok "répertoire de seed supprimé"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
