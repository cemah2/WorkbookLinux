#!/usr/bin/env bash
# check_M24_01.sh — vérifie le lab L24.1 (template cloud-init, ci-test, ci-vm.sh)
# À lancer sur lab-adm, en tant que mathieu (accès ssh root@10.10.10.1).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L24.1 =="

BASE="$HOME/lab24"
NODE="${NODE:-root@10.10.10.1}"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new"
CI="$BASE/cloud-init/ci-test.yaml"

# --- 1. le user-data ----------------------------------------------------
if [ -s "$CI" ]; then
  ok "ci-test.yaml présent"
  [ "$(head -n1 "$CI")" = "#cloud-config" ] \
    && ok "première ligne #cloud-config" \
    || ko "la première ligne doit être exactement #cloud-config"
  python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$CI" \
    2>/dev/null && ok "YAML syntaxiquement valide" \
    || ko "YAML invalide (python3 -c 'import yaml; ...')"
  grep -qE '^\s*-\s*docker\.io' "$CI" \
    && ok "docker.io dans packages" || ko "docker.io absent des packages"
  grep -q 'lab24-marker' "$CI" \
    && ok "write_files /etc/lab24-marker" || ko "write_files /etc/lab24-marker absent"
  grep -q 'final_message' "$CI" \
    && ok "final_message présent" || ko "final_message absent"
  if command -v cloud-init >/dev/null 2>&1; then
    cloud-init schema --config-file "$CI" >/dev/null 2>&1 \
      && ok "cloud-init schema : valide" \
      || ko "cloud-init schema refuse le fichier (lis son message)"
  fi
else
  ko "$CI absent (E24.7 puis L24.1 étape 2)"
fi

# --- 2. côté nœud ---------------------------------------------------------
if $SSH "$NODE" true 2>/dev/null; then
  ok "accès ssh au nœud $NODE"
  $SSH "$NODE" 'qm config 9100 2>/dev/null' | grep -q '^template: 1' \
    && ok "9100 est un template" || ko "9100 n'est pas un template (E24.9)"
  $SSH "$NODE" 'qm config 9100 2>/dev/null' | grep -q '^ide2: .*cloudinit' \
    && ok "9100 a un lecteur cloud-init" || ko "9100 sans ide2 cloudinit"
  $SSH "$NODE" 'test -s /var/lib/vz/snippets/ci-test.yaml' \
    && ok "snippet ci-test.yaml présent sur le nœud" \
    || ko "/var/lib/vz/snippets/ci-test.yaml absent sur le nœud"
  $SSH "$NODE" 'pvesm status -storage local 2>/dev/null; pvesm config local 2>/dev/null' \
    | grep -q snippets \
    && ok "stockage local accepte les snippets" \
    || note "vérifie : pvesm set local --content iso,vztmpl,backup,snippets"
  CFG=$($SSH "$NODE" 'qm config 9110 2>/dev/null')
  if [ -n "$CFG" ]; then
    ok "VM 9110 existe"
    grep -q '^name: ci-test$' <<<"$CFG" && ok "9110 s'appelle ci-test" \
      || ko "9110 ne s'appelle pas ci-test"
    grep -q '^cicustom: user=local:snippets/ci-test.yaml' <<<"$CFG" \
      && ok "cicustom pointe sur le snippet" || ko "cicustom absent sur 9110"
    grep -q '^ipconfig0: ip=10.10.10.110/24,gw=10.10.10.1' <<<"$CFG" \
      && ok "ipconfig0 10.10.10.110/24 gw 10.10.10.1" || ko "ipconfig0 incorrect"
    grep -qE '^scsi0: .*size=25G' <<<"$CFG" \
      && ok "disque scsi0 agrandi à 25G" || ko "scsi0 n'est pas à 25G (étape 6)"
    $SSH "$NODE" 'qm listsnapshot 9110' | grep -q 'avant-test' \
      && ok "snapshot avant-test présent" || ko "snapshot avant-test absent"
  else
    ko "VM 9110 (ci-test) absente"
  fi
  $SSH "$NODE" 'qm config 9111 2>/dev/null' | grep -q '^name: ci-test2$' \
    && ok "VM 9111 ci-test2 créée par ci-vm.sh" \
    || ko "VM 9111 ci-test2 absente (étape 7)"
else
  ko "ssh $NODE impossible : les tests côté nœud sont sautés"
fi

# --- 3. dans les VM -------------------------------------------------------
R=$($SSH mathieu@10.10.10.110 'cat /etc/lab24-marker; id -nG; cloud-init status; hostname; df -BG / | tail -1' 2>/dev/null)
if [ -n "$R" ]; then
  ok "ssh mathieu@10.10.10.110"
  grep -q 'ci-test provisionne par cloud-init' <<<"$R" \
    && ok "/etc/lab24-marker correct" || ko "/etc/lab24-marker absent ou différent"
  grep -qw docker <<<"$R" && ok "mathieu membre du groupe docker" \
    || ko "mathieu n'est pas dans le groupe docker"
  grep -q 'status: done' <<<"$R" && ok "cloud-init status: done" \
    || ko "cloud-init n'est pas en done (cloud-init status --long)"
  grep -q '^ci-test$' <<<"$R" && ok "hostname ci-test" || ko "hostname incorrect"
  SZ=$(grep -oE '^/dev/\S+\s+[0-9]+G' <<<"$R" | awk '{print $2}' | tr -d G)
  [ -n "${SZ:-}" ] && [ "$SZ" -ge 24 ] && ok "/ fait ${SZ}G (growpart OK)" \
    || ko "/ n'a pas grandi (reboot après qm disk resize ?)"
else
  ko "ssh mathieu@10.10.10.110 injoignable"
fi
$SSH mathieu@10.10.10.111 'hostname' 2>/dev/null | grep -q . \
  && ok "ci-test2 joignable en 10.10.10.111" \
  || ko "ci-test2 (10.10.10.111) injoignable"

# --- 4. le script -----------------------------------------------------
S="$BASE/bin/ci-vm.sh"
if [ -x "$S" ]; then
  ok "ci-vm.sh présent et exécutable"
  bash -n "$S" && ok "ci-vm.sh : syntaxe bash OK" || ko "ci-vm.sh : erreur de syntaxe"
  grep -q 'set -euo pipefail' "$S" && ok "set -euo pipefail" || ko "pas de set -euo pipefail"
  grep -qE '180' "$S" && ok "délai d'attente 180 s codé" \
    || note "délai de 180 s non trouvé dans le script"
else
  ko "$S absent ou non exécutable"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
