#!/usr/bin/env bash
# bootstrap-lab.sh — prépare une VM fraîchement clonée pour le workbook.
# À lancer UNE fois sur CHAQUE VM (Ubuntu 24.04 ou Rocky 9), en sudo :
#   sudo bash ~/workbook/scripts/lab/bootstrap-lab.sh
# Idempotent : relançable sans effet de bord.
#
# Ce qu'il fait :
#   1. outils de base (vim curl git tmux htop jq tree net-tools dnsutils
#      rsync unzip shellcheck) + qemu-guest-agent + chrony
#   2. /etc/hosts avec les 7 VM du lab (10.10.10.10-16, domaine lab.local)
#   3. fuseau horaire Europe/Paris, locale, historique bash horodaté
#   4. message du jour (motd) qui rappelle le rôle de la machine
#   5. répertoire ~/workbook accessible à l'utilisateur de lab : déballe
#      ~/workbook.zip ou ~/workbook-scripts.zip s'il y en a un, sinon clone
#      le dépôt ($WORKBOOK_REPO), ou le met à jour s'il est déjà cloné
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "lance-moi avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

. /etc/os-release
HOST="$(hostname -s)"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

# Dépôt du workbook (ton fork, si tu en as un) : WORKBOOK_REPO=... sudo -E bash ...
WORKBOOK_REPO="${WORKBOOK_REPO:-https://github.com/cemah2/WorkbookLinux.git}"

# ---------------------------------------------------------------------
# 1. Paquets
# ---------------------------------------------------------------------
COMMON="vim curl git tmux htop jq tree net-tools rsync unzip wget \
        bash-completion chrony qemu-guest-agent"

case "$ID" in
  ubuntu|debian)
    info "paquets (apt) sur $PRETTY_NAME"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -q
    # shellcheck disable=SC2086
    apt-get install -y -q $COMMON dnsutils shellcheck
    ;;
  rocky|rhel|almalinux|centos)
    info "paquets (dnf) sur $PRETTY_NAME"
    dnf install -y -q epel-release
    # shellcheck disable=SC2086
    dnf install -y -q $COMMON bind-utils ShellCheck
    # Rocky : la config vim minimale ne crée pas ~/.vimrc, on laisse.
    ;;
  *)
    echo "distribution non gérée : $ID" >&2; exit 1 ;;
esac

systemctl enable --now qemu-guest-agent >/dev/null 2>&1 || true
systemctl enable --now chronyd >/dev/null 2>&1 \
  || systemctl enable --now chrony >/dev/null 2>&1 || true

# ---------------------------------------------------------------------
# 2. /etc/hosts — les 7 VM, entre deux marqueurs pour rester idempotent
# ---------------------------------------------------------------------
info "/etc/hosts"
HOSTS_BLOCK='# BEGIN workbook
10.10.10.10  lab-adm.lab.local  lab-adm
10.10.10.11  lab-web.lab.local  lab-web
10.10.10.12  lab-db.lab.local   lab-db
10.10.10.13  lab-rhel.lab.local lab-rhel
10.10.10.14  lab-ops.lab.local  lab-ops
10.10.10.15  lab-git.lab.local  lab-git
10.10.10.16  lab-virt.lab.local lab-virt
# END workbook'
put_block() {           # put_block FICHIER : remplace le bloc, idempotent
  sed -i '/^# BEGIN workbook/,/^# END workbook/d' "$1"
  printf '%s\n' "$HOSTS_BLOCK" >> "$1"
}
put_block /etc/hosts

# cloud-init réécrit /etc/hosts à chaque boot si manage_etc_hosts est
# actif. Proxmox le met à true dans le user-data qu'il génère, et le
# user-data l'emporte sur cloud.cfg.d : on désactive quand même, ET on
# ajoute le bloc aux modèles dont cloud-init régénère /etc/hosts.
if [ -d /etc/cloud/cloud.cfg.d ]; then
  cat > /etc/cloud/cloud.cfg.d/99-workbook.cfg <<'EOF'
# Workbook Linux/DevOps : /etc/hosts est géré par bootstrap-lab.sh
manage_etc_hosts: false
EOF
fi
for tpl in /etc/cloud/templates/hosts.debian.tmpl \
           /etc/cloud/templates/hosts.redhat.tmpl; do
  if [ -f "$tpl" ]; then put_block "$tpl"; fi
done

# ---------------------------------------------------------------------
# 3. Fuseau, locale, historique
# ---------------------------------------------------------------------
info "fuseau horaire Europe/Paris"
timedatectl set-timezone Europe/Paris

if [ "$ID" = ubuntu ]; then
  locale-gen fr_FR.UTF-8 >/dev/null 2>&1 || true
fi

# Historique bash exploitable (module 01 y revient) : horodaté, gros,
# écrit à chaque commande. Fichier global, l'utilisateur peut surcharger.
cat > /etc/profile.d/workbook-history.sh <<'EOF'
# Workbook Linux/DevOps — historique bash
[ -n "${BASH_VERSION:-}" ] || return 0
export HISTSIZE=50000 HISTFILESIZE=100000
export HISTTIMEFORMAT='%F %T  '
export HISTCONTROL=ignoredups
shopt -s histappend 2>/dev/null
case "$PROMPT_COMMAND" in
  *history\ -a*) ;;
  *) PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}" ;;
esac
EOF

# ---------------------------------------------------------------------
# 4. motd
# ---------------------------------------------------------------------
info "motd"
case "$HOST" in
  lab-adm)  ROLE="poste d'admin, bastion, noeud de controle Ansible" ;;
  lab-web)  ROLE="frontal web / reverse proxy / app" ;;
  lab-db)   ROLE="base de donnees, disques sdb/sdc pour LVM" ;;
  lab-rhel) ROLE="variantes RHEL : dnf, firewalld, SELinux" ;;
  lab-ops)  ROLE="Docker, CI runner, monitoring, registre" ;;
  lab-git)  ROLE="forge Gitea : versionner le workbook, portfolio" ;;
  lab-virt) ROLE="hyperviseur KVM/QEMU/libvirt imbrique (module 20)" ;;
  *)        ROLE="machine hors table du lab" ;;
esac

MOTD_TEXT="
  Workbook Linux/DevOps — $HOST ($PRETTY_NAME)
  Role   : $ROLE
  IP     : $(hostname -I 2>/dev/null | awk '{print $1}')
  Regle  : jamais root direct, snapshot avant un lab destructeur,
           qm rollback <vmid> snap-clean pour repartir propre.
"
if [ -d /etc/update-motd.d ]; then
  # Ubuntu : script dynamique, on neutralise les pubs et le bruit.
  cat > /etc/update-motd.d/01-workbook <<EOF
#!/bin/sh
cat <<'TXT'
$MOTD_TEXT
TXT
EOF
  chmod 755 /etc/update-motd.d/01-workbook
  chmod -x /etc/update-motd.d/10-help-text \
           /etc/update-motd.d/50-motd-news 2>/dev/null || true
  [ -f /etc/default/motd-news ] \
    && sed -i 's/^ENABLED=.*/ENABLED=0/' /etc/default/motd-news
else
  printf '%s\n' "$MOTD_TEXT" > /etc/motd
fi

# ---------------------------------------------------------------------
# 5. Répertoire du workbook et droits
# ---------------------------------------------------------------------
info "répertoire $LAB_HOME/workbook"
install -d -o "$LAB_USER" -g "$LAB_USER" "$LAB_HOME/workbook" \
  "$LAB_HOME/workbook/scripts" "$LAB_HOME/carnet"
# Le workbook (cf. chapitre 0.4) : une archive déposée à côté du script
# (workbook.zip ou workbook-scripts.zip) a la priorité ; sinon, clone Git.
zip_done=0
for z in workbook.zip workbook-scripts.zip; do
  if [ -f "$LAB_HOME/$z" ]; then
    su - "$LAB_USER" -c "unzip -o -q ~/$z -d ~/workbook"
    find "$LAB_HOME/workbook/scripts" -name '*.sh' -exec chmod +x {} +
    zip_done=1
    break
  fi
done
if [ "$zip_done" -eq 0 ]; then
  if [ -d "$LAB_HOME/workbook/.git" ]; then
    info "workbook déjà cloné : mise à jour (git pull)"
    su - "$LAB_USER" -c "git -C ~/workbook pull --ff-only -q" \
      || warn "git pull impossible (réseau, modifications locales ?) : workbook laissé tel quel"
  elif [ -z "$(ls -A "$LAB_HOME/workbook/scripts" 2>/dev/null)" ] \
       && [ "$(ls -A "$LAB_HOME/workbook" 2>/dev/null)" = "scripts" ]; then
    info "clone de $WORKBOOK_REPO dans $LAB_HOME/workbook"
    rmdir "$LAB_HOME/workbook/scripts" "$LAB_HOME/workbook"
    if ! su - "$LAB_USER" -c "git clone -q '$WORKBOOK_REPO' ~/workbook"; then
      install -d -o "$LAB_USER" -g "$LAB_USER" "$LAB_HOME/workbook/scripts"
      warn "clone impossible : copie les scripts à la main (chapitre 0.4)"
    fi
  fi
fi

# ---------------------------------------------------------------------
# Bilan
# ---------------------------------------------------------------------
echo
echo "== $HOST bootstrapé =="
echo "   distribution : $PRETTY_NAME"
echo "   heure        : $(date '+%F %T %Z')"
echo "   agent QEMU   : $(systemctl is-active qemu-guest-agent 2>/dev/null)"
echo "   résolution   : $(getent hosts lab-ops | awk '{print $1}')"
echo "   shellcheck   : $(command -v shellcheck || echo ABSENT)"
echo
echo "Reconnecte-toi pour voir le motd et le nouvel historique."
