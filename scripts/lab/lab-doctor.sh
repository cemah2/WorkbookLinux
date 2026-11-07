#!/usr/bin/env bash
# lab-doctor.sh — diagnostic de bout en bout du laboratoire.
# S'exécute depuis le nœud Proxmox (root, détecte `qm`) OU depuis lab-adm
# (utilisateur mathieu). Pour chaque VM : ping, SSH par clé, sudo sans mot
# de passe, /etc/hosts, résolution lab.local, heure NTP, fuseau, sortie
# internet, espace disque, agent invité ; plus sdb/sdc sur lab-db, /dev/kvm
# sur lab-virt, Gitea sur lab-git, scripts du workbook sur lab-adm. Depuis
# le nœud : existence, état, snapshot snap-clean, agent, bridge, NAT, nested.
#
# Usage : bash lab-doctor.sh [--quiet]      code retour 0 = tout est vert
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HERE/lab-env.sh" ]; then
  # shellcheck source=lab-env.sh
  . "$HERE/lab-env.sh"
else
  LAB_VMS=(
    "9001 lab-adm  10.10.10.10 ubuntu 2 2048 20"
    "9002 lab-web  10.10.10.11 ubuntu 2 2048 20"
    "9003 lab-db   10.10.10.12 ubuntu 2 2048 30"
    "9004 lab-rhel 10.10.10.13 rocky  2 2048 20"
    "9005 lab-ops  10.10.10.14 ubuntu 2 4096 40"
    "9006 lab-git  10.10.10.15 ubuntu 1 1024 15"
    "9007 lab-virt 10.10.10.16 ubuntu 4 6144 40"
  )
  LAB_SNAP="${LAB_SNAP:-snap-clean}"; LAB_BRIDGE="${LAB_BRIDGE:-vmbr1}"
  LAB_WAN_BRIDGE="${LAB_WAN_BRIDGE:-vmbr0}"; LAB_NET="${LAB_NET:-10.10.10.0/24}"
  LAB_USER="${LAB_USER:-mathieu}"; LAB_DIR="${LAB_DIR:-/root/lab}"
fi
TIMEZONE="${TIMEZONE:-Europe/Paris}"
GITEA_URL="${GITEA_URL:-http://10.10.10.15:3000}"
QUIET=0; [ "${1:-}" = "--quiet" ] && QUIET=1

PASS=0; FAIL=0; WARN=0
ok() { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
wn() { printf '  [WARN] %s\n' "$1"; WARN=$((WARN+1)); }

# --- D'où tourne-t-on ? -------------------------------------------------
if command -v qm >/dev/null 2>&1; then
  MODE=node
  [ "$(id -u)" -eq 0 ] || { echo "sur le nœud, lance-moi en root" >&2
                            exit 1; }
  SSH_USER="$LAB_USER"
  KH="$LAB_DIR/known_hosts"
else
  MODE=vm
  SSH_USER="$(id -un)"
  KH="$HOME/.ssh/known_hosts"
fi
MYHOST="$(hostname -s 2>/dev/null || echo "?")"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=6 -o LogLevel=ERROR
          -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KH")

echo "== Diagnostic du laboratoire (depuis $MYHOST, mode $MODE) =="

# --- Sonde exécutée dans chaque VM : imprime des « clé=valeur » ---------
PROBE='
sudo -n true 2>/dev/null && echo sudo=ok || echo sudo=ko
n=0; for h in lab-adm lab-web lab-db lab-rhel lab-ops lab-git lab-virt; do
  getent hosts "$h" >/dev/null 2>&1 && n=$((n+1)); done; echo hosts=$n
echo resolve=$(getent hosts lab-web.lab.local 2>/dev/null | awk "{print \$1}")
echo ntp=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
echo tz=$(timedatectl show -p Timezone --value 2>/dev/null)
echo inet=$(curl -sI -m 8 -o /dev/null -w "%{http_code}" \
  https://deb.debian.org/ 2>/dev/null)
echo used=$(df -P / | awk "NR==2 {gsub(\"%\",\"\",\$5); print \$5}")
echo agent=$(systemctl is-active qemu-guest-agent 2>/dev/null)
echo disks=$(lsblk -dn -o NAME 2>/dev/null | tr "\n" " ")
[ -e /dev/kvm ] && echo kvm=yes || echo kvm=no
echo vflags=$(grep -c -E "vmx|svm" /proc/cpuinfo)
d=""; for s in setup check break lab; do
  [ -d ~/workbook/scripts/$s ] && d="$d$s "; done; echo wbdirs=$d
[ -x ~/workbook/scripts/check/check_M01_01.sh ] && echo chk=yes || echo chk=no
'

declare -A P
probe_vm() {          # probe_vm IP NOM  -> remplit P[...]
  local ip="$1" name="$2" out line
  P=()
  if [ "$MODE" = vm ] && [ "$name" = "$MYHOST" ]; then
    out="$(bash -c "$PROBE" 2>/dev/null)" || return 1
  else
    out="$(ssh "${SSH_OPTS[@]}" "$SSH_USER@$ip" bash -s <<< "$PROBE" \
           2>/dev/null)" || return 1
  fi
  while IFS='=' read -r k v; do [ -n "$k" ] && P[$k]="$v"; done <<< "$out"
  [ -n "${P[sudo]:-}" ]
}

# --- Contrôles côté nœud ------------------------------------------------
if [ "$MODE" = node ]; then
  echo "-- Nœud Proxmox"
  if ip -4 -br addr show "$LAB_BRIDGE" 2>/dev/null | grep -q 10.10.10.1; then
    ok "bridge $LAB_BRIDGE en 10.10.10.1/24"
  else
    ko "bridge $LAB_BRIDGE absent ou sans IP (lab-deploy.sh --only 10)"
  fi
  if iptables -t nat -S POSTROUTING 2>/dev/null \
       | grep -q -- "-s $LAB_NET .*-o $LAB_WAN_BRIDGE -j MASQUERADE"; then
    ok "NAT $LAB_NET -> $LAB_WAN_BRIDGE"
  else
    ko "règle MASQUERADE absente ($LAB_DIR/lab-nat.sh up)"
  fi
  [ "$(cat /proc/sys/net/ipv4/ip_forward)" = 1 ] && ok "ip_forward = 1" \
    || ko "ip_forward = 0 (sysctl -w net.ipv4.ip_forward=1)"
  nested=$(cat /sys/module/kvm_intel/parameters/nested \
           /sys/module/kvm_amd/parameters/nested 2>/dev/null | head -1)
  case "$nested" in
    Y|1) ok "KVM nested=$nested sur le nœud" ;;
    *)   wn "KVM nested=${nested:-?} : lab-virt sans /dev/kvm (chapitre 0.3)" ;;
  esac
fi

# --- Chaque VM ----------------------------------------------------------
for line in "${LAB_VMS[@]}"; do
  read -r vmid name ip _ <<< "$line"
  echo "-- $name ($vmid, $ip)"

  if [ "$MODE" = node ]; then
    if ! qm status "$vmid" >/dev/null 2>&1; then
      ko "VM absente (lab-deploy.sh --from 30)"; continue
    fi
    if qm listsnapshot "$vmid" 2>/dev/null | grep -qw "$LAB_SNAP"; then
      ok "snapshot $LAB_SNAP présent"
    else
      ko "snapshot $LAB_SNAP absent (bash lab-create.sh snapshot)"
    fi
    if ! qm status "$vmid" | grep -q running; then
      if [ "$name" = lab-virt ]; then
        wn "éteinte (normal hors module 20 : qm start $vmid pour la tester)"
      else
        ko "éteinte (qm start $vmid)"
      fi
      continue
    fi
    ok "en marche"
    qm agent "$vmid" ping >/dev/null 2>&1 && ok "agent invité répond" \
      || wn "agent invité muet (qemu-guest-agent installé par bootstrap)"
  fi

  if ping -c1 -W2 "$ip" >/dev/null 2>&1; then
    ok "ping"
  elif [ "$name" = lab-virt ]; then
    wn "pas de ping : lab-virt éteinte (normal hors module 20)"; continue
  else
    ko "pas de ping (VM éteinte ? qm terminal $vmid)"; continue
  fi

  if ! probe_vm "$ip" "$name"; then
    if [ "$MODE" = vm ]; then
      ko "SSH par clé impossible depuis $MYHOST (ssh-copy-id $SSH_USER@$ip)"
    else
      ko "SSH par clé impossible (clé root absente de lab-keys.pub ?)"
    fi
    continue
  fi
  ok "SSH par clé ($SSH_USER@$ip)"
  [ "${P[sudo]}" = ok ] && ok "sudo sans mot de passe" \
    || ko "sudo -n refuse (cloud-init ciuser ? groupe sudo/wheel ?)"
  [ "${P[hosts]:-0}" -eq 7 ] && ok "/etc/hosts : les 7 VM" \
    || ko "/etc/hosts incomplet (${P[hosts]:-0}/7) : sudo bash bootstrap-lab.sh"
  [ "${P[resolve]:-}" = 10.10.10.11 ] && ok "lab-web.lab.local -> 10.10.10.11" \
    || ko "lab-web.lab.local ne résout pas (dnsmasq du nœud ou /etc/hosts)"
  [ "${P[ntp]:-}" = yes ] && ok "heure synchronisée (NTP)" \
    || wn "NTPSynchronized=${P[ntp]:-?} (chrony démarré ? sortie UDP/123 ?)"
  [ "${P[tz]:-}" = "$TIMEZONE" ] && ok "fuseau $TIMEZONE" \
    || ko "fuseau ${P[tz]:-?} (timedatectl set-timezone $TIMEZONE)"
  case "${P[inet]:-}" in
    2*|3*) ok "sortie internet (https://deb.debian.org)" ;;
    *) ko "pas d'internet (NAT du nœud, DNS ${P[resolve]:+ok}, curl)" ;;
  esac
  if [ "${P[used]:-100}" -le 80 ]; then
    ok "disque / : ${P[used]}% utilisé"
  else
    ko "disque / à ${P[used]}% : moins de 20 % libre (apt clean, journalctl)"
  fi
  [ "${P[agent]:-}" = active ] && ok "qemu-guest-agent actif" \
    || wn "qemu-guest-agent ${P[agent]:-absent} (bootstrap-lab.sh l'installe)"

  case "$name" in
    lab-db)
      if echo " ${P[disks]:-} " | grep -q ' sdb ' \
         && echo " ${P[disks]:-} " | grep -q ' sdc '; then
        ok "/dev/sdb et /dev/sdc présents"
      else
        ko "sdb/sdc manquants (${P[disks]:-?}) : qm set 9003 --scsi1 ..."
      fi ;;
    lab-virt)
      [ "${P[kvm]:-}" = yes ] && ok "/dev/kvm présent" \
        || ko "/dev/kvm absent (nested sur le nœud + cpu host, chapitre 0.3)"
      [ "${P[vflags]:-0}" -gt 0 ] && ok "drapeaux vmx/svm visibles" \
        || ko "pas de vmx/svm : qm set 9007 --cpu host" ;;
    lab-git)
      v="$(curl -fs -m 5 "$GITEA_URL/api/v1/version" 2>/dev/null \
           | sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p')"
      if [ -n "$v" ]; then
        ok "Gitea $v répond sur $GITEA_URL"
      elif curl -fs -m 5 "$GITEA_URL/api/healthz" >/dev/null 2>&1; then
        # INSTALL_LOCK = false : seul l'installateur web est servi
        wn "Gitea répond, installation web à terminer (chapitre 0.8)"
      else
        ko "Gitea muet sur $GITEA_URL (systemctl status gitea)"
      fi ;;
    lab-adm)
      if [ "$(echo "${P[wbdirs]:-}" | wc -w)" -eq 4 ]; then
        ok "workbook/scripts : setup check break lab"
      else
        ko "workbook/scripts incomplet (${P[wbdirs]:-vide}) : chapitre 0.4"
      fi
      [ "${P[chk]:-}" = yes ] && ok "check_M01_01.sh exécutable" \
        || ko "check_M01_01.sh absent ou non exécutable (chmod +x)" ;;
  esac
done

echo
echo "Résultat : $PASS réussis, $FAIL échoués, $WARN avertissements"
if [ "$FAIL" -eq 0 ]; then
  echo "Lab opérationnel."
elif [ "$QUIET" -eq 0 ]; then
  echo "Corrige les [FAIL] puis relance ; lab-deploy.sh --from <phase>" \
       "refait une étape."
fi
[ "$FAIL" -eq 0 ]
