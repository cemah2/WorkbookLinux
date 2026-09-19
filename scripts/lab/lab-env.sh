#!/usr/bin/env bash
# lab-env.sh — variables communes des scripts du laboratoire (nœud Proxmox).
# Ce fichier est « sourcé » par lab-create.sh, lab-reset.sh, lab-status.sh
# et make-templates.sh. Surcharge possible par variable d'environnement :
#   LAB_STORAGE=local-zfs LAB_WAN_BRIDGE=vmbr0 bash lab-create.sh
#
# Il ne contient aucune commande : uniquement des affectations.
# shellcheck disable=SC2034

# --- Proxmox -----------------------------------------------------------
LAB_STORAGE="${LAB_STORAGE:-local-lvm}"     # stockage des disques VM
LAB_ISO_STORE="${LAB_ISO_STORE:-local}"     # stockage type « dir » (images)
LAB_WAN_BRIDGE="${LAB_WAN_BRIDGE:-vmbr0}"   # bridge relié au monde extérieur
LAB_BRIDGE="${LAB_BRIDGE:-vmbr1}"           # bridge isolé du lab

# --- Réseau du lab (cf. CONVENTIONS.md §1) ------------------------------
LAB_NET="${LAB_NET:-10.10.10.0/24}"
LAB_GW="${LAB_GW:-10.10.10.1}"
LAB_DNS="${LAB_DNS:-10.10.10.1}"            # 9.9.9.9 si pas de dnsmasq
LAB_DOMAIN="${LAB_DOMAIN:-lab.local}"

# --- Templates ---------------------------------------------------------
TPL_UBUNTU_ID="${TPL_UBUNTU_ID:-9000}"
TPL_UBUNTU_NAME="${TPL_UBUNTU_NAME:-tpl-ubuntu-2404}"
UBUNTU_BASE="https://cloud-images.ubuntu.com/noble/current"
UBUNTU_IMG="noble-server-cloudimg-amd64.img"
TPL_UBUNTU_URL="${TPL_UBUNTU_URL:-$UBUNTU_BASE/$UBUNTU_IMG}"
TPL_UBUNTU_SUMS="${TPL_UBUNTU_SUMS:-$UBUNTU_BASE/SHA256SUMS}"

TPL_ROCKY_ID="${TPL_ROCKY_ID:-9010}"
TPL_ROCKY_NAME="${TPL_ROCKY_NAME:-tpl-rocky-9}"
ROCKY_BASE="https://dl.rockylinux.org/pub/rocky/9/images/x86_64"
ROCKY_IMG="Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
TPL_ROCKY_URL="${TPL_ROCKY_URL:-$ROCKY_BASE/$ROCKY_IMG}"
TPL_ROCKY_SUMS="${TPL_ROCKY_SUMS:-$ROCKY_BASE/CHECKSUM}"

# Répertoire de travail sur le nœud (images téléchargées, clés).
LAB_DIR="${LAB_DIR:-/root/lab}"

# --- Utilisateur et clé déployés par cloud-init -------------------------
LAB_USER="${LAB_USER:-mathieu}"
LAB_SSHKEYS="${LAB_SSHKEYS:-/root/lab/lab-keys.pub}"   # clés publiques

# --- Les 7 VM : "vmid nom ip template cores ram_mo disque_go" ------------
# L'ordre est celui de la table du §1 des conventions.
LAB_VMS=(
  "9001 lab-adm  10.10.10.10 ubuntu 2 2048 20"
  "9002 lab-web  10.10.10.11 ubuntu 2 2048 20"
  "9003 lab-db   10.10.10.12 ubuntu 2 2048 30"
  "9004 lab-rhel 10.10.10.13 rocky  2 2048 20"
  "9005 lab-ops  10.10.10.14 ubuntu 2 4096 40"
  "9006 lab-git  10.10.10.15 ubuntu 1 1024 15"
  "9007 lab-virt 10.10.10.16 ubuntu 4 6144 40"
)

# Disques additionnels de lab-db (taille en Go), non formatés.
LAB_DB_VMID=9003
LAB_DB_EXTRA_DISKS=(5 5)

# lab-virt (module 20) : CPU « host » pour la virtualisation imbriquée.
# Le paramètre nested du module KVM du nœud reste à activer à la main
# (chapitre 0.3) ; lab-status.sh le vérifie.
LAB_VIRT_VMID=9007

# Nom du snapshot de référence.
LAB_SNAP="${LAB_SNAP:-snap-clean}"

# --- Fonctions d'affichage ---------------------------------------------
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[1;32m[ OK ]\033[0m %s\n' "$*"; }
ko()   { printf '  \033[1;31m[FAIL]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERREUR:\033[0m %s\n' "$*" >&2; exit 1; }

need_root() {
  [ "$(id -u)" -eq 0 ] || die "à lancer en root sur le nœud Proxmox"
}
need_qm()   { command -v qm >/dev/null 2>&1 || die "commande qm introuvable"; }
