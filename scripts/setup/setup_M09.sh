#!/usr/bin/env bash
# setup_M09.sh — prépare le terrain du module 09 (noyau et démarrage)
# À lancer avec sudo sur lab-adm (fonctionne aussi sur lab-rhel).
# Idempotent : relançable sans effet de bord.
#
# Il crée l'arborescence ~/lab09 et capture une RÉFÉRENCE de l'état noyau
# de la VM (cmdline, modules, sysctl, /boot, interfaces) que l'apprenant
# compare après chaque lab et chaque Break & Fix. Il ne modifie ni GRUB,
# ni l'initramfs, ni sysctl, ni udev : c'est le travail du module.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab09"
REF="$BASE/reference"

echo "== Préparation du module 09 =="
echo "   utilisateur : $LAB_USER"
echo "   base        : $BASE"

# ---------------------------------------------------------------------
# 1. Arborescence de travail
# ---------------------------------------------------------------------
mkdir -p "$BASE"/{rapports,conf,udev,bin,reference}

# ---------------------------------------------------------------------
# 2. Vérification des outils (installés en 9.1, on ne fait que signaler)
# ---------------------------------------------------------------------
manque=()
for c in strace ausyscall udevadm chronyc dmesg sysctl lsmod modinfo \
         systemd-analyze timedatectl; do
  command -v "$c" >/dev/null 2>&1 || manque+=("$c")
done
if command -v apt-get >/dev/null 2>&1; then
  command -v lsinitramfs >/dev/null 2>&1 || manque+=("lsinitramfs")
  command -v update-grub >/dev/null 2>&1 || manque+=("update-grub")
else
  command -v lsinitrd >/dev/null 2>&1 || manque+=("lsinitrd")
  command -v grubby >/dev/null 2>&1 || manque+=("grubby")
fi
if [ "${#manque[@]}" -gt 0 ]; then
  echo "   outils manquants : ${manque[*]} (voir les paquets du §9.1)"
fi

# ---------------------------------------------------------------------
# 3. Capture de référence (écrasée à chaque exécution : c'est voulu,
#    on relance le setup après un rollback snap-clean)
# ---------------------------------------------------------------------
capture() {  # capture <fichier> <commande...>
  local f="$REF/$1"; shift
  { "$@" ; } > "$f" 2>/dev/null || true
}
capture uname.txt        uname -a
capture cmdline.txt      cat /proc/cmdline
capture lsmod.txt        sh -c 'lsmod | sort'
capture sysctl.txt       sh -c 'sysctl -a 2>/dev/null | sort'
capture boot.txt         ls -l /boot
capture df-boot.txt      df -h /boot
capture link.txt         ip -br link
capture addr.txt         ip -br addr
capture timedate.txt     timedatectl
capture scheduler.txt    sh -c 'for d in /sys/block/[sv]d*; do \
  printf "%s %s\n" "$(basename "$d")" "$(cat "$d/queue/scheduler")"; done'
capture thp.txt          cat /sys/kernel/mm/transparent_hugepage/enabled
capture sysctl-files.txt sh -c 'ls -la /etc/sysctl.conf /etc/sysctl.d/ \
  /usr/lib/sysctl.d/ 2>/dev/null'
capture modprobe-d.txt   sh -c 'grep -Hv "^#" /etc/modprobe.d/*.conf'
capture udev-rules.txt   sh -c 'ls -la /etc/udev/rules.d/'
if [ -f /etc/default/grub ]; then
  capture grub-default.txt sh -c 'cat /etc/default/grub; \
    cat /etc/default/grub.d/*.cfg 2>/dev/null'
fi
if command -v grubby >/dev/null 2>&1; then
  capture grubby.txt grubby --info=ALL
fi
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$REF/date.txt"

# ---------------------------------------------------------------------
# 4. Un aide-mémoire de comparaison
# ---------------------------------------------------------------------
cat > "$BASE/bin/diff-reference.sh" <<'EOF'
#!/usr/bin/env bash
# diff-reference.sh — compare l'état courant à la référence du setup
set -uo pipefail
REF="$HOME/lab09/reference"
echo "== cmdline =="   ; diff <(cat "$REF/cmdline.txt") <(cat /proc/cmdline)
echo "== modules ==" ; diff "$REF/lsmod.txt" <(lsmod | sort)
echo "== sysctl =="   ; diff "$REF/sysctl.txt" <(sysctl -a 2>/dev/null | sort)
echo "== /boot =="    ; diff "$REF/boot.txt" <(ls -l /boot)
echo "== liens =="    ; diff "$REF/link.txt" <(ip -br link)
echo "(aucune sortie sous un titre = identique à la référence)"
EOF
chmod 0755 "$BASE/bin/diff-reference.sh"

chown -R "$LAB_USER:$LAB_USER" "$BASE"

echo
echo "Référence capturée dans $REF ($(ls "$REF" | wc -l) fichiers)."
echo "Comparer plus tard : bash ~/lab09/bin/diff-reference.sh"
echo "Rappel : qm snapshot 9001 avant-lab09 et qm set 9001 --serial0 socket"
echo "         doivent avoir été faits depuis le shell Proxmox."
