#!/usr/bin/env bash
# break_M20_05.sh — panne BF20.5 : « le disque de lab-virt se remplit ».
# Pose sur vm-01 (en marche) un snapshot externe SANS métadonnées vers un
# fichier caché, jamais refermé, puis fait écrire 1,5 Go dans l'invité via
# l'agent (l'overlay orphelin grossit). Idempotent. Note l'état initial dans
# /root/.breakfix-backup/. À lancer avec sudo sur lab-virt (L20.1 fait).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
V="virsh -c qemu:///system"
VM=vm-01
IMG=/var/lib/libvirt/images
OVER="$IMG/.vm-01.tmp-overlay"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

$V dominfo $VM >/dev/null 2>&1 || { echo "$VM absente : fais L20.1 d'abord" >&2; exit 1; }
[ "$($V domstate $VM)" = running ] || $V start $VM >/dev/null
for _ in $(seq 1 60); do
  $V qemu-agent-command $VM '{"execute":"guest-ping"}' >/dev/null 2>&1 && break; sleep 2
done
DISK=$($V domblklist $VM | awk '$1=="vda"{print $2}')
[ -f "$SAUV/M20_05_disque.txt" ] || echo "$DISK" > "$SAUV/M20_05_disque.txt"

if [ "$DISK" = "$OVER" ]; then
  echo "$VM écrit déjà dans l'overlay caché : rien à refaire"
elif [[ $DISK == *.qcow2 ]]; then
  SPEC=(--diskspec "vda,snapshot=external,file=$OVER")
  $V domblklist $VM | awk '$1=="sda"' | grep -q . && SPEC+=(--diskspec sda,snapshot=no)
  Q=(--quiesce)
  $V qemu-agent-command $VM '{"execute":"guest-ping"}' >/dev/null 2>&1 || Q=()
  $V snapshot-create-as $VM tmp --disk-only --atomic --no-metadata "${Q[@]}" "${SPEC[@]}" \
    >/dev/null
else
  echo "disque actif inattendu ($DISK) : chaîne déjà ouverte, abandon" >&2; exit 1
fi

# l'invité écrit 1,5 Go : tout va dans l'overlay orphelin
gexec() {
  local pid st
  pid=$($V qemu-agent-command $VM "{\"execute\":\"guest-exec\",\"arguments\":\
{\"path\":\"$1\",\"arg\":$2,\"capture-output\":false}}" 2>/dev/null | jq -r .return.pid)
  [ -n "$pid" ] && [ "$pid" != null ] || return 1
  for _ in $(seq 1 240); do
    st=$($V qemu-agent-command $VM \
         "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$pid}}" 2>/dev/null)
    [ "$(jq -r .return.exited <<<"$st")" = true ] && return 0
    sleep 1
  done
  return 1
}
if gexec /usr/bin/dd '["if=/dev/urandom","of=/var/tmp/fill-bf20","bs=1M","count=1500"]'; then
  :
else
  echo "agent muet ou dd trop long : l'overlay grossira au fil de l'activité de la VM" >&2
fi

cat <<'EOF'

Symptôme attendu : « df -h / » sur lab-virt a perdu plusieurs Go en peu de
temps. « virsh snapshot-list vm-01 » est vide, « ls /var/lib/libvirt/images »
ne montre rien d'inhabituel à première vue, et pourtant « du » sur ce
répertoire grossit à vue d'œil. vm-01 fonctionne normalement. Interdit de
supprimer un fichier sans avoir prouvé qu'aucune VM ne l'utilise, et
d'arrêter vm-01.
EOF
