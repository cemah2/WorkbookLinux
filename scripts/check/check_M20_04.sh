#!/usr/bin/env bash
# check_M20_04.sh — vérifie le lab L20.4 (sauvegarde à chaud et restauration)
# À lancer sur lab-virt, en tant que mathieu, sans sudo. Utilise l'agent
# invité de vm-01 pour regarder dans /srv/data.
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification L20.4 =="

V="virsh -c qemu:///system"
VM=vm-01
BK="$HOME/lab20/backups"

# gexec VM CMD [ARGS...] -> code de retour de la commande dans l'invité (99 si agent muet)
gexec() {
  local vm=$1 cmd=$2; shift 2
  local args pid st i
  args=$(jq -cn '$ARGS.positional' --args -- "$@")
  pid=$($V qemu-agent-command "$vm" "{\"execute\":\"guest-exec\",\"arguments\":\
{\"path\":\"$cmd\",\"arg\":$args,\"capture-output\":true}}" 2>/dev/null | jq -r .return.pid)
  [ -n "$pid" ] && [ "$pid" != null ] || { echo 99; return; }
  for i in $(seq 1 30); do
    st=$($V qemu-agent-command "$vm" \
         "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$pid}}" 2>/dev/null)
    if [ "$(jq -r .return.exited <<<"$st")" = true ]; then
      jq -r '.return.exitcode // 0' <<<"$st"; return
    fi
    sleep 0.5
  done
  echo 99
}

# --- sauvegarde autoportante --------------------------------------------------
LAST=$(ls -1t "$BK"/$VM-*.qcow2 2>/dev/null | head -1)
if [ -n "$LAST" ]; then
  ok "sauvegarde présente : $(basename "$LAST")"
  if qemu-img info "$LAST" 2>/dev/null | grep -q '^backing file'; then
    ko "la sauvegarde a un backing file : elle n'est pas autoportante (convert)"
  else
    ok "sauvegarde autoportante (pas de backing file)"
  fi
  [ -s "${LAST%.qcow2}.xml" ] && grep -q "<name>$VM</name>" "${LAST%.qcow2}.xml" \
    && ok "XML de la VM sauvegardé à côté" || ko "XML absent à côté de la sauvegarde"
  grep -q '\.sauv' "${LAST%.qcow2}.xml" 2>/dev/null \
    && ko "le XML sauvegardé référence l'overlay .sauv (dumpxml après le pivot)" \
    || ok "le XML sauvegardé ne référence pas l'overlay"
else
  ko "aucune sauvegarde $BK/$VM-*.qcow2"
fi

# --- état de la VM et de la chaîne --------------------------------------------
if [ "$($V domstate $VM 2>/dev/null)" = running ]; then
  ok "$VM en marche"
  DISK=$($V domblklist $VM | awk '$1=="vda"{print $2}')
  case "$DISK" in
    *.sauv*|*.snap*|*tmp*) ko "vda pointe sur un overlay ($DISK) : blockcommit --pivot manquant" ;;
    *) ok "vda sur un disque de référence : $DISK" ;;
  esac
  $V vol-list default | awk 'NR>2{print $1}' | grep -q '\.sauv' \
    && ko "un overlay .sauv traîne dans le pool default" \
    || ok "aucun overlay .sauv dans le pool"
  $V snapshot-list $VM | awk 'NR>2 && NF{print}' | grep -q . \
    && ko "des snapshots internes subsistent (snapshot-delete)" \
    || ok "aucun snapshot interne restant"
  $V domstate --reason $VM | grep -q saved \
    && ko "un managedsave est en attente (managedsave-remove ou start)" \
    || ok "pas de managedsave en attente"
  # contenu de l'invité, via l'agent
  case "$(gexec $VM /usr/bin/test -e /srv/data/avant.txt)" in
    0)  ok "/srv/data/avant.txt présent dans l'invité (restauration effective)" ;;
    99) ko "agent muet : impossible de vérifier /srv/data" ;;
    *)  ko "/srv/data/avant.txt absent : la restauration n'a pas repris la sauvegarde" ;;
  esac
  case "$(gexec $VM /usr/bin/test -e /srv/data/apres.txt)" in
    0)  ko "/srv/data/apres.txt présent : le disque n'a pas été remplacé" ;;
    99) : ;;
    *)  ok "/srv/data/apres.txt absent" ;;
  esac
else
  ko "$VM n'est pas en marche"
fi

# --- rapport ---------------------------------------------------------------
R="$HOME/lab20/rapports/sav-15.md"
[ -s "$R" ] && grep -qi 'vzdump' "$R" && grep -qi 'blockcommit' "$R" \
  && ok "rapport sav-15.md (blockcommit et vzdump cités)" \
  || ko "rapport $R absent ou incomplet"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
