#!/usr/bin/env bash
# lab-deploy.sh — déploie TOUT le laboratoire du workbook en une commande,
# sur le nœud Proxmox VE 8, en root :
#   bridge vmbr1 + NAT + dnsmasq, templates cloud-init (9000 Ubuntu 24.04,
#   9010 Rocky 9), clone des 7 VM, démarrage, bootstrap-lab.sh, scripts du
#   workbook sur lab-adm, Gitea sur lab-git, snapshot snap-clean, diagnostic.
#
# Idempotent et reprenable : chaque phase détecte ce qui est déjà fait.
# Il orchestre les scripts du chapitre 0 (lab-nat.sh, make-templates.sh,
# lab-create.sh, bootstrap-lab.sh, install-gitea.sh, lab-doctor.sh) au
# lieu de dupliquer leur logique.
#
# Usage : bash lab-deploy.sh [options]      (--help pour le détail)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_VERSION="1.0"

# =====================================================================
# Configuration — surcharge possible (priorité décroissante) :
#   1. variable d'environnement :  STORAGE=local-zfs bash lab-deploy.sh
#   2. fichier lab-deploy.conf à côté du script (affectations bash)
#   3. valeurs par défaut ci-dessous
# =====================================================================
CONF_VARS=(STORAGE BRIDGE_EXT BRIDGE_LAB SSH_PUBKEY LAB_USER LAB_PASSWORD
  DNS_UPSTREAM GITEA_VERSION TIMEZONE WORKBOOK_ZIP LAB_DIR LAN_NET
  INSTALL_LIBGUESTFS INSTALL_DNSMASQ UPGRADE_PACKAGES WAVE_SIZE
  SSH_TIMEOUT LOG_FILE GITEA_BACKUP_TIMER)

declare -A _ENV_SAVED=()
for _v in "${CONF_VARS[@]}"; do
  if [ -n "${!_v+x}" ]; then _ENV_SAVED[$_v]="${!_v}"; fi
done
CONF_FILE="${LAB_DEPLOY_CONF:-$SCRIPT_DIR/lab-deploy.conf}"
if [ -f "$CONF_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONF_FILE"
fi
for _v in "${!_ENV_SAVED[@]}"; do
  printf -v "$_v" '%s' "${_ENV_SAVED[$_v]}"
done
unset _v

STORAGE="${STORAGE:-local-lvm}"          # stockage des disques VM
BRIDGE_EXT="${BRIDGE_EXT:-vmbr0}"        # bridge relié à ton LAN
BRIDGE_LAB="${BRIDGE_LAB:-vmbr1}"        # bridge isolé du lab
SSH_PUBKEY="${SSH_PUBKEY:-}"             # défaut : 1re clé /root/.ssh/*.pub
LAB_USER="${LAB_USER:-mathieu}"          # utilisateur créé par cloud-init
LAB_PASSWORD="${LAB_PASSWORD:-}"         # mot de passe console (facultatif)
DNS_UPSTREAM="${DNS_UPSTREAM:-9.9.9.9}"  # relais de dnsmasq
GITEA_VERSION="${GITEA_VERSION:-1.27.3}" # cf. https://dl.gitea.com/gitea/
TIMEZONE="${TIMEZONE:-Europe/Paris}"
WORKBOOK_ZIP="${WORKBOOK_ZIP:-}"         # défaut : cherché à côté, /root
LAB_DIR="${LAB_DIR:-/root/lab}"          # images, clés, journaux
LAN_NET="${LAN_NET:-}"                   # défaut : détecté sur BRIDGE_EXT
INSTALL_LIBGUESTFS="${INSTALL_LIBGUESTFS:-1}"  # virt-customize (agent)
INSTALL_DNSMASQ="${INSTALL_DNSMASQ:-1}"  # DNS du lab sur 10.10.10.1
UPGRADE_PACKAGES="${UPGRADE_PACKAGES:-1}"      # apt/dnf upgrade au bootstrap
WAVE_SIZE="${WAVE_SIZE:-3}"              # VM démarrées simultanément
SSH_TIMEOUT="${SSH_TIMEOUT:-600}"        # attente SSH par VM (s)
LOG_FILE="${LOG_FILE:-/var/log/lab-deploy.log}"
GITEA_BACKUP_TIMER="${GITEA_BACKUP_TIMER:-1}"  # gitea-backup.timer

# Les scripts du chapitre 0 lisent lab-env.sh : on aligne les noms.
export LAB_STORAGE="$STORAGE" LAB_WAN_BRIDGE="$BRIDGE_EXT" \
  LAB_BRIDGE="$BRIDGE_LAB" LAB_USER LAB_DIR
export LAB_SSHKEYS="${LAB_SSHKEYS:-$LAB_DIR/lab-keys.pub}"
if [ "$INSTALL_DNSMASQ" = 1 ]; then
  export LAB_DNS="${LAB_DNS:-10.10.10.1}"
else
  export LAB_DNS="${LAB_DNS:-$DNS_UPSTREAM}"
fi
# shellcheck source=lab-env.sh
. "$SCRIPT_DIR/lab-env.sh"

# =====================================================================
# Journal, couleurs, messages
# =====================================================================
USE_COLOR=0
[ -t 1 ] && USE_COLOR=1
if [ "$USE_COLOR" = 1 ]; then
  C_B=$'\033[1;34m'; C_G=$'\033[1;32m'; C_Y=$'\033[1;33m'
  C_R=$'\033[1;31m'; C_0=$'\033[0m'
else
  C_B=''; C_G=''; C_Y=''; C_R=''; C_0=''
fi
_stamp() { date '+%F %T'; }
log()  { printf '%s %s==>%s %s\n' "$(_stamp)" "$C_B" "$C_0" "$*"; }
ok()   { printf '%s   %s[ OK ]%s %s\n' "$(_stamp)" "$C_G" "$C_0" "$*"; }
warn() { printf '%s   %s[WARN]%s %s\n' "$(_stamp)" "$C_Y" "$C_0" "$*" >&2
         WARNINGS=$((WARNINGS+1)); }
die()  { printf '%s %sERREUR:%s %s\n' "$(_stamp)" "$C_R" "$C_0" "$*" >&2
         exit 1; }
WARNINGS=0

# =====================================================================
# Options
# =====================================================================
PHASES=(00-preflight 10-network 20-templates 30-vms 40-start 50-bootstrap
  60-workbook 70-gitea 80-snapshots 90-doctor)
FROM=""; ONLY=""; SKIP=""; DRY_RUN=0; YES=0; DESTROY=0; DESTROY_ALL=0

usage() {
  cat <<EOF
lab-deploy.sh $DEPLOY_VERSION — déploiement automatique du laboratoire

  bash lab-deploy.sh                 tout déployer (20 à 30 min)
  bash lab-deploy.sh --from 50       reprendre à partir d'une phase
  bash lab-deploy.sh --only 90       une seule phase
  bash lab-deploy.sh --skip 70,80    sauter des phases
  bash lab-deploy.sh --dry-run       afficher sans rien faire
  bash lab-deploy.sh --yes           aucune question
  bash lab-deploy.sh --destroy       supprimer les 7 VM (pas les templates
                                     ni le réseau ; --destroy-all : tout)
  bash lab-deploy.sh --help          cette aide

Phases (un numéro ou un nom suffit : --from 40, --from start) :
  00-preflight   root, PVE 8, qm/pvesh, stockage, disque, RAM, nested, clé
  10-network     $BRIDGE_LAB 10.10.10.1/24, NAT vers $BRIDGE_EXT, DNAT 2222
                 et 3000, dnsmasq (lab.local), /etc/network/interfaces
  20-templates   images cloud (SHA256), templates 9000 Ubuntu / 9010 Rocky
  30-vms         clone des 7 VM (IP, clé, ressources, sdb/sdc, cpu host)
  40-start       démarrage par vagues de $WAVE_SIZE, attente agent + SSH
  50-bootstrap   bootstrap-lab.sh sur chaque VM, mises à jour, fuseau
  60-workbook    scripts du workbook dans /home/$LAB_USER/workbook sur lab-adm
  70-gitea       install-gitea.sh sur lab-git, attente du port 3000
  80-snapshots   snapshot $LAB_SNAP sur les 7 VM
  90-doctor      lab-doctor.sh : diagnostic de bout en bout

Configuration : variables d'environnement, ou lab-deploy.conf à côté du
script. Valeurs actuelles :
  STORAGE=$STORAGE BRIDGE_EXT=$BRIDGE_EXT BRIDGE_LAB=$BRIDGE_LAB
  LAB_USER=$LAB_USER DNS_UPSTREAM=$DNS_UPSTREAM TIMEZONE=$TIMEZONE
  GITEA_VERSION=$GITEA_VERSION LAB_DIR=$LAB_DIR
  SSH_PUBKEY=${SSH_PUBKEY:-(1re clé de /root/.ssh/*.pub)}
  WORKBOOK_ZIP=${WORKBOOK_ZIP:-(workbook-scripts.zip à côté ou dans /root)}
  LAB_PASSWORD=${LAB_PASSWORD:+(défini)}${LAB_PASSWORD:-(aucun)}

Journal : $LOG_FILE
EOF
}

# Normalise « 40 », « start », « 40-start » en « 40-start ».
phase_name() {
  local want="$1" p
  for p in "${PHASES[@]}"; do
    case "$p" in
      "$want"|"$want"-*|*-"$want") echo "$p"; return 0 ;;
    esac
  done
  die "phase inconnue : $want (voir --help)"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --from)    FROM="$(phase_name "${2:?phase attendue}")"; shift 2 ;;
    --only)    ONLY="$(phase_name "${2:?phase attendue}")"; shift 2 ;;
    --skip)    SKIP="${2:?liste attendue}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y)  YES=1; shift ;;
    --destroy) DESTROY=1; shift ;;
    --destroy-all) DESTROY=1; DESTROY_ALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "option inconnue : $1 (--help)" ;;
  esac
done

SKIP_LIST=()
if [ -n "$SKIP" ]; then
  IFS=',' read -r -a _skips <<< "$SKIP"
  for _s in "${_skips[@]}"; do SKIP_LIST+=("$(phase_name "$_s")"); done
  unset _skips _s
fi

# Journal : tout ce qui s'affiche est aussi écrit dans LOG_FILE.
if [ "$DRY_RUN" = 0 ]; then
  if touch "$LOG_FILE" 2>/dev/null; then
    exec > >(tee -a "$LOG_FILE") 2>&1
  else
    LOG_FILE="$LAB_DIR/lab-deploy.log"
    mkdir -p "$LAB_DIR"
    exec > >(tee -a "$LOG_FILE") 2>&1
  fi
fi

# =====================================================================
# Outils
# =====================================================================
# run CMD... : exécute, ou affiche seulement en --dry-run.
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '%s   %s[dry ]%s %s\n' "$(_stamp)" "$C_Y" "$C_0" "$*"
    return 0
  fi
  "$@"
}
# runq CMD... : comme run, mais sans sortie (sauf en --dry-run).
runq() {
  if [ "$DRY_RUN" = 1 ]; then run "$@"; return 0; fi
  "$@" >/dev/null 2>&1
}

# ask "question" : vrai si l'utilisateur répond oui (ou --yes).
ask() {
  local rep
  [ "$YES" = 1 ] && return 0
  read -r -p "$1 [O/n] " rep </dev/tty || return 1
  case "${rep:-o}" in o|O|y|Y|oui|OUI) return 0 ;; *) return 1 ;; esac
}

vm_exists()  { qm status "$1" >/dev/null 2>&1; }
vm_running() { qm status "$1" 2>/dev/null | grep -q running; }
has_snap()   { qm listsnapshot "$1" 2>/dev/null | grep -qw "$LAB_SNAP"; }
port_open()  { timeout 3 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }
agent_ping() { qm agent "$1" ping >/dev/null 2>&1; }

# ip_of NOM / vmid_of NOM : lecture de la table LAB_VMS de lab-env.sh
ip_of() {
  local line vmid name ip
  for line in "${LAB_VMS[@]}"; do
    read -r vmid name ip _ <<< "$line"
    [ "$name" = "$1" ] && { echo "$ip"; return 0; }
  done
  return 1
}
vmid_of() {
  local line vmid name
  for line in "${LAB_VMS[@]}"; do
    read -r vmid name _ <<< "$line"
    [ "$name" = "$1" ] && { echo "$vmid"; return 0; }
  done
  return 1
}
ADM_IP="$(ip_of lab-adm)"; GIT_IP="$(ip_of lab-git)"

# --- SSH depuis le nœud, avec la clé privée de root -------------------
SSH_PRIVKEY=""
KNOWN_HOSTS="$LAB_DIR/known_hosts"
ssh_opts() {
  local o=(-o StrictHostKeyChecking=accept-new
           -o UserKnownHostsFile="$KNOWN_HOSTS" -o ConnectTimeout=10
           -o BatchMode=yes -o LogLevel=ERROR)
  [ -n "$SSH_PRIVKEY" ] && o+=(-i "$SSH_PRIVKEY")
  printf '%s\n' "${o[@]}"
}
# vm_ssh IP CMD... : commande sur une VM (utilisateur du lab)
vm_ssh() {
  local ip="$1"; shift
  local opts; mapfile -t opts < <(ssh_opts)
  ssh "${opts[@]}" "$LAB_USER@$ip" "$@"
}
# vm_scp SRC... IP:DEST
vm_scp() {
  local dest="${*: -1}" opts
  mapfile -t opts < <(ssh_opts)
  scp -q "${opts[@]}" "${@:1:$#-1}" "$LAB_USER@$dest"
}

# --- Repli : agent invité (qm guest exec), en root dans la VM ---------
# guest_exec VMID CMD : sortie sur stdout, code retour de la commande.
guest_exec() {
  local vmid="$1" cmd="$2" json rc
  json="$(qm guest exec "$vmid" --timeout 1800 -- /bin/bash -c "$cmd")" \
    || return 1
  rc="$(printf '%s' "$json" | grep -o '"exitcode" *: *[0-9]*' \
        | grep -o '[0-9]*$' || echo 1)"
  printf '%s' "$json" | sed -n 's/.*"out-data" *: *"\(.*\)",\{0,1\}$/\1/p' \
    | head -c 4000 || true
  echo
  return "$rc"
}
# guest_put VMID FICHIER_LOCAL CHEMIN_DISTANT
guest_put() {
  qm guest exec "$1" --pass-stdin 1 -- /bin/bash -c "cat > '$3'" \
    < "$2" >/dev/null
}

# vm_run VMID IP CMD : SSH d'abord ; si la connexion échoue (code 255)
# et que l'agent répond, on passe par lui (en root : pas de sudo).
vm_run() {
  local vmid="$1" ip="$2" cmd="$3" rc=0
  vm_ssh "$ip" "$cmd" || rc=$?
  if [ "$rc" -eq 255 ] && agent_ping "$vmid"; then
    warn "SSH injoignable sur $ip, repli sur l'agent invité"
    guest_exec "$vmid" "${cmd#sudo -n }"
    return $?
  fi
  return "$rc"
}
# vm_put VMID IP SRC DEST : copie par scp, repli par l'agent.
vm_put() {
  local vmid="$1" ip="$2" src="$3" dest="$4"
  if ! vm_scp "$src" "$ip:$dest" 2>/dev/null; then
    agent_ping "$vmid" || return 1
    warn "scp impossible vers $ip, repli sur l'agent invité"
    guest_put "$vmid" "$src" "$dest"
  fi
}

# wait_vm VMID IP : attend l'agent (facultatif) puis le port 22, SSH_TIMEOUT.
wait_vm() {
  local vmid="$1" ip="$2" t=0 agent=no
  while [ "$t" -lt "$SSH_TIMEOUT" ]; do
    [ "$agent" = no ] && agent_ping "$vmid" && agent=yes
    if port_open "$ip" 22; then
      ok "$ip : SSH ouvert après ${t}s (agent : $agent)"
      return 0
    fi
    sleep 5; t=$((t+5))
  done
  return 1
}
# effective_ip VMID IP_ATTENDUE : IP vue par l'agent (ou celle attendue).
effective_ip() {
  local vmid="$1" want="$2" got
  got="$(qm agent "$vmid" network-get-interfaces 2>/dev/null \
    | grep -o '"ip-address" *: *"10\.10\.10\.[0-9]*"' \
    | grep -o '10\.10\.10\.[0-9]*' | head -1 || true)"
  echo "${got:-$want}"
}

# =====================================================================
# Phase 00 — préflight
# =====================================================================
phase_00_preflight() {
  local c
  for c in qm pvesh pvesm pveversion ip iptables ssh scp wget curl; do
    command -v "$c" >/dev/null 2>&1 || die "commande absente : $c"
  done
  local pve
  pve="$(pveversion 2>/dev/null | sed -n 's#^pve-manager/\([0-9.]*\).*#\1#p')"
  case "$pve" in
    8.*) ok "Proxmox VE $pve" ;;
    "")  die "pveversion ne répond pas : est-ce bien un nœud Proxmox ?" ;;
    *)   warn "Proxmox VE $pve : le workbook est écrit pour la version 8" ;;
  esac

  # Stockage, place disque, RAM
  local st avail_k
  st="$(pvesm status --storage "$STORAGE" 2>/dev/null | awk 'NR==2')" \
    || true
  [ -n "$st" ] || die "stockage $STORAGE introuvable (pvesm status)"
  echo "$st" | grep -q ' active ' \
    || die "stockage $STORAGE inactif : $st"
  avail_k="$(echo "$st" | awk '{print $6}')"
  if [ "${avail_k:-0}" -ge $((220*1024*1024)) ]; then
    ok "stockage $STORAGE : $((avail_k/1024/1024)) Go disponibles"
  else
    warn "stockage $STORAGE : $((avail_k/1024/1024)) Go libres, 220 Go" \
         "conseillés (7 VM + templates + snapshots)"
  fi
  local ram_g
  ram_g="$(free -g | awk '/^Mem:/ {print $2}')"
  if [ "${ram_g:-0}" -ge 24 ]; then
    ok "RAM du nœud : ${ram_g} Go"
  else
    warn "RAM du nœud : ${ram_g} Go (24 Go conseillés pour les 7 VM" \
         "ensemble ; laisse lab-virt éteinte hors module 20)"
  fi

  # Virtualisation imbriquée (lab-virt, module 20)
  local mod param nested
  if lsmod | grep -q '^kvm_amd'; then mod=kvm_amd; param=kvm-amd
  else mod=kvm_intel; param=kvm-intel; fi
  nested="$(cat /sys/module/$mod/parameters/nested 2>/dev/null || true)"
  case "$nested" in
    Y|1) ok "KVM nested=$nested ($mod)" ;;
    *)
      log "activation de la virtualisation imbriquée ($mod)"
      run bash -c "echo 'options $param nested=1' \
        > /etc/modprobe.d/$param.conf"
      if qm list 2>/dev/null | grep -q running; then
        warn "des VM tournent : nested sera actif au prochain reboot" \
             "du nœud (ou : arrête-les puis modprobe -r $mod; modprobe $mod)"
      else
        run modprobe -r "$mod" || true
        run modprobe "$mod" || true
        nested="$(cat /sys/module/$mod/parameters/nested 2>/dev/null \
                  || true)"
        case "$nested" in
          Y|1) ok "KVM nested=$nested ($mod) activé" ;;
          *) [ "$DRY_RUN" = 1 ] \
               || warn "nested toujours ${nested:-?} : reboot du nœud" \
                       "nécessaire avant le module 20" ;;
        esac
      fi ;;
  esac

  # libguestfs-tools (facultatif) : injecte l'agent dans les images
  if command -v virt-customize >/dev/null 2>&1; then
    ok "virt-customize présent (agent injecté dans les templates)"
  elif [ "$INSTALL_LIBGUESTFS" = 1 ]; then
    log "installation de libguestfs-tools (facultatif, ~5 min)"
    runq apt-get update -q || true
    if ! runq apt-get install -y -q libguestfs-tools; then
      warn "libguestfs-tools non installé : bootstrap-lab.sh installera" \
           "l'agent au premier démarrage"
    fi
  else
    warn "virt-customize absent : l'agent sera installé par bootstrap"
  fi

  # Clé SSH publique -> lab-keys.pub (cloud-init)
  ok "clé publique : $SSH_PUBKEY"
  [ -n "$SSH_PRIVKEY" ] \
    || warn "clé privée ${SSH_PUBKEY%.pub} absente : ssh utilisera tes" \
            "clés par défaut (ou l'agent invité en repli)"
  run mkdir -p "$LAB_DIR"
  if [ "$DRY_RUN" = 0 ]; then
    touch "$LAB_SSHKEYS"
    if ! grep -qxF "$(cat "$SSH_PUBKEY")" "$LAB_SSHKEYS"; then
      cat "$SSH_PUBKEY" >> "$LAB_SSHKEYS"
      ok "clé ajoutée à $LAB_SSHKEYS ($(wc -l < "$LAB_SSHKEYS") clé(s))"
    else
      ok "$LAB_SSHKEYS contient déjà la clé"
    fi
  fi

  # Copie des scripts du lab dans LAB_DIR (chemin utilisé par
  # /etc/network/interfaces et par le chapitre 0).
  if [ "$SCRIPT_DIR" != "$LAB_DIR" ]; then
    run install -m 755 "$SCRIPT_DIR"/*.sh "$LAB_DIR/"
    run install -m 644 "$SCRIPT_DIR"/gitea-backup.service \
      "$SCRIPT_DIR"/gitea-backup.timer "$LAB_DIR/"
    ok "scripts copiés dans $LAB_DIR"
  fi

  ok "LAN exclu du NAT : $LAN_NET (via $BRIDGE_EXT)"
  ip link show "$BRIDGE_EXT" >/dev/null 2>&1 \
    || die "bridge externe $BRIDGE_EXT introuvable (BRIDGE_EXT=...)"
}

# setup_context : ce dont TOUTES les phases ont besoin (clé, LAN), sans
# rien modifier — exécuté même avec --from / --only / --destroy.
setup_context() {
  if [ -z "$SSH_PUBKEY" ]; then
    SSH_PUBKEY="$(ls /root/.ssh/*.pub 2>/dev/null | head -1 || true)"
  fi
  if [ -z "$SSH_PUBKEY" ] || [ ! -s "$SSH_PUBKEY" ]; then
    die "aucune clé publique : crée-la avec
    ssh-keygen -t ed25519 -N '' -f /root/.ssh/id_ed25519
puis relance, ou indique SSH_PUBKEY=/chemin/cle.pub. Cette clé est
déployée par cloud-init dans le compte $LAB_USER des 7 VM : c'est avec
elle que ce script s'y connecte pour le bootstrap."
  fi
  [ -f "${SSH_PUBKEY%.pub}" ] && SSH_PRIVKEY="${SSH_PUBKEY%.pub}"
  # LAN à exclure du NAT (détecté sur le bridge externe)
  if [ -z "$LAN_NET" ]; then
    LAN_NET="$(ip -4 route show dev "$BRIDGE_EXT" proto kernel scope link \
      2>/dev/null | awk '{print $1}' | head -1 || true)"
    LAN_NET="${LAN_NET:-192.168.1.0/24}"
  fi
}

# =====================================================================
# Phase 10 — réseau
# =====================================================================
phase_10_network() {
  local ifaces=/etc/network/interfaces
  # 1. vmbr1 dans /etc/network/interfaces
  if grep -q "^iface $BRIDGE_LAB " "$ifaces" 2>/dev/null; then
    ok "$BRIDGE_LAB déjà défini dans $ifaces"
  else
    log "ajout de $BRIDGE_LAB (10.10.10.1/24) à $ifaces"
    if [ "$DRY_RUN" = 0 ]; then
      cp -a "$ifaces" "$ifaces.bak-lab-$(date +%Y%m%d%H%M%S)"
      cat >> "$ifaces" <<EOF

# Workbook Linux/DevOps : réseau de lab isolé (chapitre 0.3)
auto $BRIDGE_LAB
iface $BRIDGE_LAB inet static
    address $LAB_GW/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    post-up   env LAN_NET=$LAN_NET LAB_WAN_BRIDGE=$BRIDGE_EXT \\
              $LAB_DIR/lab-nat.sh up
    post-down env LAN_NET=$LAN_NET LAB_WAN_BRIDGE=$BRIDGE_EXT \\
              $LAB_DIR/lab-nat.sh down
EOF
    fi
  fi
  # 2. ip_forward persistant
  if [ -f /etc/sysctl.d/99-lab.conf ]; then
    ok "/etc/sysctl.d/99-lab.conf présent"
  else
    run bash -c "echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-lab.conf"
  fi
  # 3. activation du bridge
  if ip -4 -br addr show "$BRIDGE_LAB" 2>/dev/null | grep -q "$LAB_GW/24"; then
    ok "$BRIDGE_LAB actif ($LAB_GW/24)"
  else
    run ifreload -a
    [ "$DRY_RUN" = 1 ] \
      || ip -4 -br addr show "$BRIDGE_LAB" | grep -q "$LAB_GW/24" \
      || die "$BRIDGE_LAB sans adresse après ifreload : vérifie $ifaces"
    ok "$BRIDGE_LAB activé"
  fi
  # 4. NAT (post-up ne se rejoue pas si le bridge existait déjà)
  if iptables -t nat -C POSTROUTING -s "$LAB_NET" ! -d "$LAN_NET" \
       -o "$BRIDGE_EXT" -j MASQUERADE 2>/dev/null; then
    ok "NAT $LAB_NET -> $BRIDGE_EXT déjà en place"
  else
    run env LAN_NET="$LAN_NET" LAB_WAN_BRIDGE="$BRIDGE_EXT" \
      bash "$LAB_DIR/lab-nat.sh" up
    ok "règles NAT appliquées (2222 -> lab-adm:22, 3000 -> lab-git:3000)"
  fi
  # 5. dnsmasq : lab.local + relais vers DNS_UPSTREAM
  if [ "$INSTALL_DNSMASQ" != 1 ]; then
    ok "dnsmasq ignoré (INSTALL_DNSMASQ=0) : DNS des VM = $LAB_DNS"
    return 0
  fi
  if ! command -v dnsmasq >/dev/null 2>&1; then
    log "installation de dnsmasq"
    runq apt-get update -q || true
    if ! runq apt-get install -y -q dnsmasq; then
      warn "dnsmasq non installable : DNS des VM = $DNS_UPSTREAM"
      export LAB_DNS="$DNS_UPSTREAM"; return 0
    fi
  fi
  if [ "$DRY_RUN" = 1 ]; then
    run "écriture de /etc/dnsmasq.d/lab.conf et $LAB_DIR/lab.hosts"
    return 0
  fi
  local hosts_new line vmid name ip
  hosts_new="$(mktemp)"
  for line in "${LAB_VMS[@]}"; do
    read -r vmid name ip _ <<< "$line"; echo "$ip $name" >> "$hosts_new"
  done
  local changed=0
  if ! cmp -s "$hosts_new" "$LAB_DIR/lab.hosts" 2>/dev/null; then
    cp "$hosts_new" "$LAB_DIR/lab.hosts"; changed=1
  fi
  rm -f "$hosts_new"
  local conf_new
  conf_new="interface=$BRIDGE_LAB
bind-interfaces
no-dhcp-interface=$BRIDGE_LAB
domain=$LAB_DOMAIN
local=/$LAB_DOMAIN/
expand-hosts
addn-hosts=$LAB_DIR/lab.hosts
server=$DNS_UPSTREAM"
  if [ "$(cat /etc/dnsmasq.d/lab.conf 2>/dev/null)" != "$conf_new" ]; then
    printf '%s\n' "$conf_new" > /etc/dnsmasq.d/lab.conf; changed=1
  fi
  if [ "$changed" = 1 ] || ! systemctl is-active -q dnsmasq; then
    systemctl enable -q dnsmasq 2>/dev/null || true
    systemctl restart dnsmasq \
      || { warn "dnsmasq ne démarre pas (journalctl -u dnsmasq) :" \
                "DNS des VM = $DNS_UPSTREAM"; export LAB_DNS="$DNS_UPSTREAM"
           return 0; }
  fi
  ok "dnsmasq actif sur $LAB_GW ($LAB_DOMAIN, relais $DNS_UPSTREAM)"
}

# =====================================================================
# Phase 20 — templates
# =====================================================================
phase_20_templates() {
  if vm_exists "$TPL_UBUNTU_ID" && vm_exists "$TPL_ROCKY_ID"; then
    ok "templates $TPL_UBUNTU_ID et $TPL_ROCKY_ID déjà présents"
    return 0
  fi
  log "make-templates.sh (téléchargement + SHA256 + qm template)"
  run bash "$SCRIPT_DIR/make-templates.sh" all
}

# =====================================================================
# Phase 30 — clone des 7 VM
# =====================================================================
phase_30_vms() {
  local line vmid name existing=() missing=()
  for line in "${LAB_VMS[@]}"; do
    read -r vmid name _ <<< "$line"
    if vm_exists "$vmid"; then existing+=("$name"); else missing+=("$name"); fi
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    ok "les 7 VM existent déjà"
    return 0
  fi
  if [ "${#existing[@]}" -gt 0 ]; then
    echo
    echo "VM déjà présentes : ${existing[*]}"
    echo "VM manquantes     : ${missing[*]}"
    if [ "$YES" = 1 ]; then
      log "reprise : on crée seulement les VM manquantes (--yes)"
    else
      local rep
      read -r -p "[R]eprendre (créer les manquantes) / [N]ouveau lab \
(tout supprimer et recréer) / [A]bandonner ? [R/n/a] " rep </dev/tty \
        || rep=a
      case "${rep:-r}" in
        n|N) destroy_vms ;;
        a|A) die "abandon demandé" ;;
        *)   log "reprise" ;;
      esac
    fi
  fi
  log "lab-create.sh (clone, ipconfig, sshkeys, ciuser, ressources)"
  LAB_NO_START=1 run bash "$SCRIPT_DIR/lab-create.sh" create
  if [ -n "$LAB_PASSWORD" ]; then
    for name in "${missing[@]}"; do
      vmid="$(vmid_of "$name")"
      runq qm set "$vmid" --cipassword "$LAB_PASSWORD"
    done
    ok "mot de passe console posé sur ${#missing[@]} VM (qm terminal)"
  fi
}

# =====================================================================
# Phase 40 — démarrage par vagues, attente agent + SSH
# =====================================================================
declare -A VM_IP_SEEN=()
phase_40_start() {
  local line vmid name ip wave=() failed=0
  local -a all=()
  for line in "${LAB_VMS[@]}"; do all+=("$line"); done
  local i=0 n="${#all[@]}"
  while [ "$i" -lt "$n" ]; do
    wave=("${all[@]:$i:$WAVE_SIZE}")
    for line in "${wave[@]}"; do
      read -r vmid name ip _ <<< "$line"
      if ! vm_exists "$vmid"; then
        [ "$DRY_RUN" = 1 ] || die "$name ($vmid) absent : phase 30 d'abord"
        run qm start "$vmid"; continue
      fi
      if vm_running "$vmid"; then
        ok "$name déjà en marche"
      else
        log "démarrage de $name ($vmid)"
        run qm start "$vmid"
      fi
    done
    [ "$DRY_RUN" = 1 ] && { i=$((i+WAVE_SIZE)); continue; }
    for line in "${wave[@]}"; do
      read -r vmid name ip _ <<< "$line"
      if wait_vm "$vmid" "$ip"; then
        VM_IP_SEEN[$name]="$(effective_ip "$vmid" "$ip")"
        [ "${VM_IP_SEEN[$name]}" = "$ip" ] \
          || warn "$name : IP vue par l'agent ${VM_IP_SEEN[$name]} != $ip"
      else
        warn "$name : pas de SSH après ${SSH_TIMEOUT}s" \
             "(qm terminal $vmid, puis cloud-init status --long)"
        failed=$((failed+1))
      fi
    done
    i=$((i+WAVE_SIZE))
  done
  [ "$failed" -eq 0 ] || die "$failed VM injoignable(s) : corrige puis" \
    "relance avec --from 40"
}

# =====================================================================
# Phase 50 — bootstrap-lab.sh sur chaque VM
# =====================================================================
STAMP=/var/lib/workbook/bootstrap.stamp
phase_50_bootstrap() {
  local line vmid name ip sum failed=0
  sum="$(sha256sum "$SCRIPT_DIR/bootstrap-lab.sh" | awk '{print $1}')"
  for line in "${LAB_VMS[@]}"; do
    read -r vmid name ip _ <<< "$line"
    if [ "$DRY_RUN" = 1 ]; then
      run "scp bootstrap-lab.sh -> $name puis sudo bash ~/bootstrap-lab.sh"
      continue
    fi
    if [ "$(vm_run "$vmid" "$ip" "cat $STAMP 2>/dev/null" 2>/dev/null \
            | head -c 64)" = "$sum" ]; then
      ok "$name déjà bootstrapée (même bootstrap-lab.sh)"
      continue
    fi
    log "bootstrap de $name ($ip)"
    if ! vm_put "$vmid" "$ip" "$SCRIPT_DIR/bootstrap-lab.sh" \
           "/home/$LAB_USER/bootstrap-lab.sh"; then
      warn "$name : copie impossible (ni scp ni agent)"; failed=$((failed+1))
      continue
    fi
    # cloud-init doit avoir fini (verrou apt/dpkg) avant le bootstrap.
    vm_run "$vmid" "$ip" "sudo -n cloud-init status --wait >/dev/null 2>&1;
      for _i in \$(seq 1 60); do
        sudo -n fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || break
        sleep 5; done; true" >/dev/null 2>&1 || true
    local cmd
    cmd="sudo -n bash /home/$LAB_USER/bootstrap-lab.sh"
    if ! vm_run "$vmid" "$ip" "$cmd"; then
      warn "$name : bootstrap-lab.sh a échoué (relance : --from 50)"
      failed=$((failed+1)); continue
    fi
    # Fuseau (bootstrap pose Europe/Paris) et mises à jour
    cmd="sudo -n timedatectl set-timezone $TIMEZONE"
    vm_run "$vmid" "$ip" "$cmd" >/dev/null 2>&1 \
      || warn "$name : timedatectl set-timezone $TIMEZONE a échoué"
    if [ "$UPGRADE_PACKAGES" = 1 ]; then
      log "  mise à jour des paquets de $name"
      cmd='if command -v apt-get >/dev/null; then
        sudo -n env DEBIAN_FRONTEND=noninteractive apt-get -y -q \
          -o Dpkg::Options::=--force-confold upgrade >/dev/null;
      else sudo -n dnf -y -q upgrade >/dev/null; fi'
      vm_run "$vmid" "$ip" "$cmd" \
        || warn "$name : mise à jour des paquets en échec (non bloquant)"
    fi
    cmd="sudo -n install -d /var/lib/workbook && \
echo $sum | sudo -n tee $STAMP >/dev/null"
    vm_run "$vmid" "$ip" "$cmd" >/dev/null
    ok "$name bootstrapée"
  done
  [ "$failed" -eq 0 ] || die "$failed VM non bootstrapée(s) : --from 50" \
    "après correction"
}

# =====================================================================
# Phase 60 — scripts du workbook sur lab-adm
# =====================================================================
find_zip() {
  local c
  for c in "$WORKBOOK_ZIP" "$SCRIPT_DIR/workbook-scripts.zip" \
           "$SCRIPT_DIR/../workbook-scripts.zip" \
           "$SCRIPT_DIR/../../workbook-scripts.zip" \
           "$SCRIPT_DIR/../../build/workbook-scripts.zip" \
           "$LAB_DIR/workbook-scripts.zip" /root/workbook-scripts.zip \
           "$SCRIPT_DIR/workbook.zip" "$LAB_DIR/workbook.zip" \
           /root/workbook.zip; do
    [ -n "$c" ] && [ -f "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}
phase_60_workbook() {
  local zip home="/home/$LAB_USER" sum remote_sum
  zip="$(find_zip || true)"
  if [ "$DRY_RUN" = 1 ]; then
    run "copie de ${zip:-workbook-scripts.zip} sur lab-adm ($ADM_IP) et" \
        "unzip dans $home/workbook/"
    return 0
  fi
  if [ -z "$zip" ]; then
    if [ -d "$SCRIPT_DIR/../check" ] && [ -d "$SCRIPT_DIR/../setup" ]; then
      warn "workbook-scripts.zip introuvable : copie du dossier scripts/" \
           "par scp -r"
      vm_ssh "$ADM_IP" "mkdir -p $home/workbook"
      local opts; mapfile -t opts < <(ssh_opts)
      scp -q -r "${opts[@]}" "$SCRIPT_DIR/.." \
        "$LAB_USER@$ADM_IP:$home/workbook/scripts"
    else
      warn "workbook-scripts.zip introuvable (WORKBOOK_ZIP=...) :" \
           "phase 60 sautée"
      return 0
    fi
  else
    sum="$(sha256sum "$zip" | awk '{print $1}')"
    remote_sum="$(vm_ssh "$ADM_IP" "cat $home/workbook/.scripts.sha256 \
      2>/dev/null" || true)"
    if [ "$remote_sum" = "$sum" ]; then
      ok "lab-adm : $home/workbook déjà à jour ($(basename "$zip"))"
    else
      log "copie de $zip sur lab-adm"
      vm_scp "$zip" "$ADM_IP:$home/workbook-scripts.zip"
      vm_ssh "$ADM_IP" "mkdir -p $home/workbook && cd $home/workbook \
        && unzip -o -q $home/workbook-scripts.zip \
        && echo $sum > $home/workbook/.scripts.sha256"
    fi
  fi
  vm_ssh "$ADM_IP" "find $home/workbook/scripts -name '*.sh' \
    -exec chmod +x {} +"
  if vm_ssh "$ADM_IP" "test -x $home/workbook/scripts/check/check_M01_01.sh \
       && bash -n $home/workbook/scripts/check/check_M01_01.sh"; then
    ok "lab-adm : ~/workbook/scripts/check/check_M01_01.sh exécutable"
  else
    warn "lab-adm : check_M01_01.sh absent ou non exécutable"
  fi
  # Clé de lab-adm (bastion, nœud de contrôle Ansible) sur les autres VM.
  local pub line vmid name ip
  pub="$(vm_ssh "$ADM_IP" "[ -f ~/.ssh/id_ed25519.pub ] || ssh-keygen -q \
    -t ed25519 -N '' -f ~/.ssh/id_ed25519 -C $LAB_USER@lab-adm;
    cat ~/.ssh/id_ed25519.pub" 2>/dev/null || true)"
  if [ -n "$pub" ]; then
    for line in "${LAB_VMS[@]}"; do
      read -r vmid name ip _ <<< "$line"
      vm_run "$vmid" "$ip" "grep -qxF '$pub' ~/.ssh/authorized_keys \
        2>/dev/null || echo '$pub' >> ~/.ssh/authorized_keys" >/dev/null \
        || warn "$name : clé de lab-adm non ajoutée"
    done
    ok "clé SSH de $LAB_USER@lab-adm déployée sur les 7 VM"
  fi
}

# =====================================================================
# Phase 70 — Gitea sur lab-git
# =====================================================================
gitea_version() {
  curl -fs --max-time 5 "http://$GIT_IP:3000/api/v1/version" 2>/dev/null \
    | sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p'
}
phase_70_gitea() {
  local home="/home/$LAB_USER" cur
  cur="$(gitea_version || true)"
  if [ -n "$cur" ] && [ "$cur" = "$GITEA_VERSION" ]; then
    ok "Gitea $cur répond déjà sur http://$GIT_IP:3000/"
  else
    [ -n "$cur" ] && log "Gitea $cur en place, passage à $GITEA_VERSION"
    if [ "$DRY_RUN" = 1 ]; then
      run "scp install-gitea.sh -> lab-git ; sudo bash install-gitea.sh"
      return 0
    fi
    vm_ssh "$GIT_IP" "mkdir -p $home/workbook/scripts/lab"
    vm_scp "$SCRIPT_DIR/install-gitea.sh" "$SCRIPT_DIR/backup-gitea.sh" \
      "$SCRIPT_DIR/gitea-backup.service" "$SCRIPT_DIR/gitea-backup.timer" \
      "$GIT_IP:$home/workbook/scripts/lab/"
    log "install-gitea.sh $GITEA_VERSION sur lab-git (binaire + systemd)"
    vm_ssh "$GIT_IP" "sudo -n env GITEA_VERSION=$GITEA_VERSION \
      bash $home/workbook/scripts/lab/install-gitea.sh" \
      || die "install-gitea.sh a échoué : ssh $LAB_USER@$GIT_IP puis" \
             "journalctl -u gitea -n 50"
    local t=0
    while [ "$t" -lt 120 ] && [ -z "$(gitea_version || true)" ]; do
      sleep 5; t=$((t+5))
    done
    cur="$(gitea_version || true)"
    [ -n "$cur" ] || die "Gitea ne répond pas sur http://$GIT_IP:3000/"
    ok "Gitea $cur répond sur http://$GIT_IP:3000/"
  fi
  if [ "$GITEA_BACKUP_TIMER" = 1 ] && [ "$DRY_RUN" = 0 ]; then
    vm_ssh "$GIT_IP" "sudo -n install -m 755 \
        $home/workbook/scripts/lab/backup-gitea.sh /usr/local/sbin/ &&
      sudo -n install -m 644 $home/workbook/scripts/lab/gitea-backup.service \
        $home/workbook/scripts/lab/gitea-backup.timer /etc/systemd/system/ &&
      sudo -n systemctl daemon-reload &&
      sudo -n systemctl enable -q --now gitea-backup.timer" \
      && ok "gitea-backup.timer actif (dump quotidien 03:30)" \
      || warn "gitea-backup.timer non installé (chapitre 0.8)"
  fi
  local node_ip
  node_ip="$(ip -4 -br addr show "$BRIDGE_EXT" 2>/dev/null \
    | awk '{print $3}' | cut -d/ -f1 | head -1)"
  echo
  echo "  Gitea : http://$GIT_IP:3000/  (depuis le lab)"
  [ -z "$node_ip" ] \
    || echo "          http://$node_ip:3000/  (depuis ton LAN, DNAT)"
  echo "  Termine l'installation dans le navigateur : crée le compte"
  echo "  administrateur $LAB_USER, puis sur lab-git :"
  echo "    sudo bash ~/workbook/scripts/lab/install-gitea.sh lock"
  echo
}

# =====================================================================
# Phase 80 — snapshots
# =====================================================================
phase_80_snapshots() {
  local line vmid name todo=0
  for line in "${LAB_VMS[@]}"; do
    read -r vmid name _ <<< "$line"
    has_snap "$vmid" || todo=$((todo+1))
  done
  if [ "$todo" -eq 0 ]; then
    ok "$LAB_SNAP présent sur les 7 VM"; return 0
  fi
  log "lab-create.sh snapshot ($todo VM sans $LAB_SNAP)"
  run bash "$SCRIPT_DIR/lab-create.sh" snapshot \
    || warn "des snapshots manquent : bash lab-create.sh snapshot plus tard"
}

# =====================================================================
# Phase 90 — diagnostic
# =====================================================================
DOCTOR_RC=""
phase_90_doctor() {
  [ -x "$SCRIPT_DIR/lab-doctor.sh" ] || [ -f "$SCRIPT_DIR/lab-doctor.sh" ] \
    || { warn "lab-doctor.sh absent"; return 0; }
  if [ "$DRY_RUN" = 1 ]; then run bash "$SCRIPT_DIR/lab-doctor.sh"; return 0; fi
  DOCTOR_RC=0
  bash "$SCRIPT_DIR/lab-doctor.sh" || DOCTOR_RC=$?
}

# =====================================================================
# Destruction
# =====================================================================
destroy_vms() {
  log "suppression des 7 VM"
  LAB_YES=1 run bash "$SCRIPT_DIR/lab-create.sh" destroy
  local line vmid name ip
  for line in "${LAB_VMS[@]}"; do
    read -r vmid name ip _ <<< "$line"
    [ -f "$KNOWN_HOSTS" ] && ssh-keygen -q -R "$ip" -f "$KNOWN_HOSTS" \
      >/dev/null 2>&1 || true
  done
}
do_destroy() {
  echo
  if [ "$DESTROY_ALL" = 1 ]; then
    echo "Cette action SUPPRIME les 7 VM, les templates $TPL_UBUNTU_ID et"
    echo "$TPL_ROCKY_ID, le bridge $BRIDGE_LAB, le NAT et dnsmasq."
  else
    echo "Cette action SUPPRIME les 7 VM du lab (les templates et le"
    echo "réseau restent : --destroy-all pour tout enlever)."
  fi
  if [ "$YES" != 1 ]; then
    local rep
    read -r -p "Taper SUPPRIMER pour confirmer : " rep </dev/tty || rep=""
    [ "$rep" = "SUPPRIMER" ] || die "abandon"
  fi
  destroy_vms
  [ "$DESTROY_ALL" = 1 ] || return 0
  local t
  for t in "$TPL_UBUNTU_ID" "$TPL_ROCKY_ID"; do
    vm_exists "$t" && run qm destroy "$t" --purge
  done
  if iptables -t nat -C POSTROUTING -s "$LAB_NET" ! -d "$LAN_NET" \
       -o "$BRIDGE_EXT" -j MASQUERADE 2>/dev/null; then
    run env LAN_NET="$LAN_NET" LAB_WAN_BRIDGE="$BRIDGE_EXT" \
      bash "$LAB_DIR/lab-nat.sh" down
  fi
  if grep -q "^iface $BRIDGE_LAB " /etc/network/interfaces 2>/dev/null; then
    log "retrait de $BRIDGE_LAB de /etc/network/interfaces"
    run ifdown "$BRIDGE_LAB" || true
    run sed -i \
      "/^# Workbook Linux\/DevOps : réseau de lab/,/lab-nat.sh down/d" \
      /etc/network/interfaces
    run ifreload -a
  fi
  run rm -f /etc/dnsmasq.d/lab.conf /etc/sysctl.d/99-lab.conf
  [ "$DRY_RUN" = 1 ] || { systemctl restart dnsmasq 2>/dev/null || true; }
  ok "lab entièrement supprimé (les images restent dans $LAB_DIR)"
}

# =====================================================================
# Résumé final
# =====================================================================
summary() {
  local line vmid name ip st ssh snap
  echo
  echo "== Résumé du laboratoire =="
  printf '%-9s | %-5s | %-12s | %-8s | %s\n' VM VMID IP SSH SNAPSHOT
  printf '%s\n' "----------+-------+--------------+----------+---------"
  for line in "${LAB_VMS[@]}"; do
    read -r vmid name ip _ <<< "$line"
    if ! vm_exists "$vmid"; then st=absente; ssh=-; snap=-
    else
      vm_running "$vmid" && st=running || st=stopped
      ssh=non; [ "$st" = running ] && port_open "$ip" 22 && ssh=oui
      snap=non; has_snap "$vmid" && snap=oui
      [ "$st" = running ] || ssh="$st"
    fi
    printf '%-9s | %-5s | %-12s | %-8s | %s\n' "$name" "$vmid" \
      "${VM_IP_SEEN[$name]:-$ip}" "$ssh" "$snap"
  done
  echo
  [ "$WARNINGS" -eq 0 ] || echo "$WARNINGS avertissement(s) : voir $LOG_FILE"
  case "$DOCTOR_RC" in
    0)  echo "lab-doctor.sh : tout est vert." ;;
    "") ;;
    *)  echo "lab-doctor.sh signale des problèmes (voir ci-dessus)." ;;
  esac
  echo
  echo "Les 5 commandes suivantes :"
  echo "  1. ssh $LAB_USER@$ADM_IP                 # ton poste d'admin"
  echo "  2. http://$GIT_IP:3000/                  # Gitea : compte admin"
  echo "  3. bash $LAB_DIR/lab-status.sh           # état des VM (nœud)"
  echo "  4. bash $LAB_DIR/lab-doctor.sh           # diagnostic complet"
  echo "  5. bash ~/workbook/scripts/setup/setup_M01.sh   # sur lab-adm :"
  echo "     première séance, module 01"
  echo
  echo "Journal complet : $LOG_FILE"
}

# =====================================================================
# Orchestration
# =====================================================================
should_run() {
  local p="$1" s
  [ -n "$ONLY" ] && { [ "$p" = "$ONLY" ]; return; }
  if [ -n "$FROM" ] && [[ "$p" < "$FROM" ]]; then return 1; fi
  for s in "${SKIP_LIST[@]}"; do [ "$s" = "$p" ] && return 1; done
  return 0
}

main() {
  echo
  echo "===== lab-deploy.sh $DEPLOY_VERSION — $(date '+%F %T') ====="
  [ "$DRY_RUN" = 1 ] && echo "(mode --dry-run : aucune modification)"
  echo "  stockage $STORAGE, bridges $BRIDGE_EXT -> $BRIDGE_LAB," \
       "utilisateur $LAB_USER, DNS $LAB_DNS, Gitea $GITEA_VERSION"
  echo "  journal : $LOG_FILE"
  echo

  [ "$(id -u)" -eq 0 ] || die "à lancer en root sur le nœud Proxmox VE 8"
  setup_context
  if [ "$DESTROY" = 1 ]; then
    do_destroy; return 0
  fi

  if [ "$YES" != 1 ] && [ "$DRY_RUN" = 0 ] && [ -z "$ONLY" ]; then
    ask "Déployer le laboratoire (7 VM, ~20-30 min) ?" || die "abandon"
  fi

  local p fn t0
  for p in "${PHASES[@]}"; do
    fn="phase_${p//-/_}"
    if ! should_run "$p"; then
      printf '%s   %s[skip]%s %s\n' "$(_stamp)" "$C_Y" "$C_0" "$p"
      continue
    fi
    echo
    log "===== $p ====="
    t0=$SECONDS
    "$fn"
    ok "$p terminé en $((SECONDS-t0))s"
  done
  summary
  [ "${DOCTOR_RC:-0}" = 0 ]
}

main "$@"
