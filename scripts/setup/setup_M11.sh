#!/usr/bin/env bash
# setup_M11.sh — prépare le terrain du module 11
#                (stockage, partitions, systèmes de fichiers, LVM)
# À lancer avec sudo. Idempotent : relançable sans effet de bord.
#
# Ce script NE crée AUCUNE partition, AUCUN PV, AUCUN LV, AUCUN système de
# fichiers sur les disques de travail : les construire est le travail du
# module. Il se contente de :
#   - vérifier la présence des paquets nécessaires ;
#   - déterminer QUELS périphériques serviront de terrain de jeu, et en
#     fabriquer deux (fichiers-images + loop devices) s'il n'y en a pas ;
#   - poser l'arborescence /srv/factura, le jeu de données et les scripts.
#
# Modes :
#   setup_M11.sh              préparation standard (sur lab-db)
#   setup_M11.sh --raid5      idem + une 3e image loop de 5 Go (E11.22)
#   setup_M11.sh --nfs        serveur NFS du lab L11.5 (sur lab-adm)
#   setup_M11.sh --etat       n'affiche que l'état courant, ne modifie rien
#   setup_M11.sh --detacher   détache les loop devices simulés (nettoyage)
#
# Le script regarde aussi le NOM D'HÔTE :
#   lab-ops : installe/vérifie nfs-kernel-server + targetcli-fb, prépare
#             /srv/nfs et /var/lib/iscsi (labs L11.7 et L11.8), puis s'arrête ;
#   lab-db  : vérifie en plus nfs-common et open-iscsi.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

MODE="${1:-}"
HOTE="$(hostname -s 2>/dev/null || hostname)"

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6 || true)"
# --etat et --detacher n'ont pas besoin du compte de l'apprenant.
case "${1:-}" in
  --etat|--detacher|--nfs|--raid5|"") : ;;
  *) echo "mode inconnu : $1 (voir l'en-tête du script)" >&2; exit 1 ;;
esac
case "${1:-}" in
  --etat|--detacher|--nfs) : ;;
  *) [ "$HOTE" = "lab-ops" ] || [ -n "$LAB_HOME" ] \
       || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; } ;;
esac

BASE="${LAB_HOME:-/root}/lab11"
BIN=/opt/factura/bin
LOGD=/var/log/factura
IMGD=/var/lib/lab11
ENVF=/etc/lab11.env
TAILLE_IMG=5G

# Candidats « vrais disques » du lab, dans l'ordre de préférence.
CANDIDATS=(/dev/sdb /dev/sdc /dev/vdb /dev/vdc)

# ---------------------------------------------------------------------
# Utilitaires
# ---------------------------------------------------------------------
titre() { printf '\n== %s ==\n' "$1"; }
info()  { printf '   %s\n' "$1"; }

# Un disque est utilisable par le module s'il existe, s'il n'a aucune
# partition montée, s'il ne porte pas de PV LVM actif et s'il ne fait pas
# partie d'un tableau RAID. On ne veut surtout pas proposer le disque
# système comme terrain de jeu.
disque_libre() {
  local d="$1"
  [ -b "$d" ] || return 1
  # une seule partition montée quelque part suffit à le disqualifier
  lsblk -nro MOUNTPOINT "$d" 2>/dev/null | grep -q . && return 1
  # membre d'un RAID en cours d'assemblage ?
  grep -q "$(basename "$d")" /proc/mdstat 2>/dev/null && return 1
  # PV LVM déjà déclaré ?
  if command -v pvs >/dev/null 2>&1; then
    pvs --noheadings -o pv_name 2>/dev/null | grep -qE "^\s*${d}[0-9]*\s*$" \
      && return 1
  fi
  return 0
}

# Renvoie le loop device associé à une image, ou rien.
loop_de() {
  losetup -j "$1" 2>/dev/null | cut -d: -f1 | head -1
}

# ---------------------------------------------------------------------
# Mode --etat
# ---------------------------------------------------------------------
if [ "$MODE" = "--etat" ]; then
  titre "État du module 11"
  [ -f "$ENVF" ] && { info "$ENVF :"; sed 's/^/     /' "$ENVF"; } \
                 || info "$ENVF absent (setup jamais lancé)"
  info "loop devices :"
  losetup -a 2>/dev/null | sed 's/^/     /' || info "     aucun"
  info "périphériques bloc :"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS | sed 's/^/     /'
  exit 0
fi

# ---------------------------------------------------------------------
# Mode --detacher
# ---------------------------------------------------------------------
if [ "$MODE" = "--detacher" ]; then
  titre "Détachement des disques simulés"
  for img in "$IMGD"/sdb.img "$IMGD"/sdc.img "$IMGD"/sdd.img; do
    [ -f "$img" ] || continue
    ld="$(loop_de "$img")"
    if [ -n "$ld" ]; then
      losetup -d "$ld" 2>/dev/null && info "$ld détaché ($img)" \
        || info "$ld occupé : démonte d'abord ce qui l'utilise"
    fi
  done
  info "les images restent dans $IMGD (supprime-les à la main si besoin)"
  exit 0
fi

# ---------------------------------------------------------------------
# Mode --nfs : serveur NFS pour L11.5, à lancer sur lab-adm
# ---------------------------------------------------------------------
if [ "$MODE" = "--nfs" ]; then
  titre "Serveur NFS du lab L11.5"
  if ! command -v exportfs >/dev/null 2>&1; then
    echo "nfs-kernel-server n'est pas installé." >&2
    echo "  sudo apt install -y nfs-kernel-server" >&2
    echo "  (Rocky : sudo dnf install -y nfs-utils)" >&2
    exit 1
  fi
  EXP=/srv/exports/archives
  mkdir -p "$EXP"
  for i in 1 2 3; do
    [ -f "$EXP/facture-2026-0$i.txt" ] || \
      printf 'facture %s\nmontant 1%s42,00 EUR\n' "$i" "$i" \
        > "$EXP/facture-2026-0$i.txt"
  done
  chown -R nobody:nogroup "$EXP" 2>/dev/null || chown -R nobody:nobody "$EXP"
  chmod -R 0755 /srv/exports

  LIGNE="$EXP 10.10.10.0/24(ro,sync,no_subtree_check)"
  if ! grep -qF "$EXP" /etc/exports 2>/dev/null; then
    echo "$LIGNE" >> /etc/exports
    info "export ajouté dans /etc/exports"
  else
    info "export déjà présent dans /etc/exports"
  fi
  exportfs -ra
  [ -d /run/systemd/system ] && systemctl restart nfs-server 2>/dev/null || true
  exportfs -v
  cat <<EOF

Le partage est prêt. Depuis lab-db :
  showmount -e 10.10.10.10
  sudo mount -t nfs4 -o ro,hard 10.10.10.10:$EXP /mnt/archives-adm
EOF
  exit 0
fi

# ---------------------------------------------------------------------
# 0. lab-ops : serveur NFS (L11.7) et cible iSCSI (L11.8)
# ---------------------------------------------------------------------
# Installation conditionnelle : on n'installe pas un serveur NFS ni une
# cible iSCSI sur lab-db, ni LVM/mdadm sur lab-ops. Le script s'arrête ici
# sur lab-ops : les exports et la cible sont le travail des labs.
if [ "$HOTE" = "lab-ops" ]; then
  titre "Préparation de lab-ops (serveur NFS + cible iSCSI)"
  A_INSTALLER=()
  command -v exportfs  >/dev/null 2>&1 || A_INSTALLER+=(nfs-kernel-server)
  command -v targetcli >/dev/null 2>&1 || A_INSTALLER+=(targetcli-fb)
  if [ "${#A_INSTALLER[@]}" -gt 0 ]; then
    if command -v apt-get >/dev/null 2>&1; then
      info "installation : ${A_INSTALLER[*]}"
      DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
        "${A_INSTALLER[@]}" >/dev/null
    else
      info "paquets absents : ${A_INSTALLER[*]}"
      info "  Rocky : sudo dnf install -y nfs-utils targetcli"
    fi
  else
    info "nfs-kernel-server et targetcli-fb sont présents"
  fi
  mkdir -p /srv/nfs /var/lib/iscsi
  chmod 0755 /srv/nfs
  chmod 0700 /var/lib/iscsi
  if [ -d /run/systemd/system ]; then
    systemctl enable --now nfs-server.service >/dev/null 2>&1 \
      && info "nfs-server.service actif" \
      || info "nfs-server.service : à démarrer à la main"
    systemctl enable --now rtslib-fb-targetctl.service >/dev/null 2>&1 \
      && info "rtslib-fb-targetctl.service actif" \
      || info "rtslib-fb-targetctl.service : à démarrer à la main"
  fi
  cat <<'EOF'

   lab-ops est prêt. Rien n'est exporté ni publié : c'est le travail des
   labs L11.7 (/etc/exports, exportfs -ra) et L11.8 (targetcli).
     - répertoire des exports NFS  : /srv/nfs
     - répertoire des backstores   : /var/lib/iscsi
   Si ufw est actif, pense à ouvrir 2049/tcp et 3260/tcp depuis 10.10.10.0/24.
EOF
  exit 0
fi

# ---------------------------------------------------------------------
# 1. Paquets
# ---------------------------------------------------------------------
titre "Préparation du module 11"
info "utilisateur : $LAB_USER"

MANQUE=()
OUTILS=(lsblk blkid parted sgdisk pvcreate vgcreate lvcreate mkfs.ext4
        mkfs.xfs xfs_quota mdadm cryptsetup growpart iostat fio fuser)
# lab-db est aussi client NFS (L11.5, L11.7) et initiateur iSCSI (L11.8)
[ "$HOTE" = "lab-db" ] && OUTILS+=(mount.nfs4 showmount iscsiadm)
for c in "${OUTILS[@]}"; do
  command -v "$c" >/dev/null 2>&1 || MANQUE+=("$c")
done
if [ "${#MANQUE[@]}" -gt 0 ]; then
  info "commandes absentes : ${MANQUE[*]}"
  info "installe-les (voir §11.1) :"
  info "  sudo apt install -y lvm2 xfsprogs btrfs-progs mdadm cryptsetup-bin \\"
  info "    gdisk parted nfs-common open-iscsi sysstat fio \\"
  info "    cloud-guest-utils quota"
  info "le setup continue : les labs concernés attendront."
else
  info "tous les outils attendus sont présents"
fi

# ---------------------------------------------------------------------
# 2. Choix des deux disques de travail
# ---------------------------------------------------------------------
titre "Disques de travail"

TROUVES=()
# Relance (ex. --raid5 après E11.21) : les disques réels déjà retenus sont
# désormais partitionnés, membres d'un RAID ou PV. On les garde tels quels
# au lieu de basculer à tort sur des disques simulés.
A1=""; A2=""; ASIM=""
if [ -f "$ENVF" ]; then
  A1="$(sed -n 's/^DISQUE1=//p' "$ENVF")"
  A2="$(sed -n 's/^DISQUE2=//p' "$ENVF")"
  ASIM="$(sed -n 's/^LAB11_SIMULE=//p' "$ENVF")"
fi
if [ "$ASIM" = "0" ] && [ -b "$A1" ] && [ -b "$A2" ]; then
  TROUVES=("$A1" "$A2")
  info "disques déjà retenus par un setup précédent ($ENVF)"
else
  for d in "${CANDIDATS[@]}"; do
    disque_libre "$d" && TROUVES+=("$d")
    [ "${#TROUVES[@]}" -ge 2 ] && break
  done
fi

SIMULE=0
if [ "${#TROUVES[@]}" -ge 2 ]; then
  DISQUE1="${TROUVES[0]}"
  DISQUE2="${TROUVES[1]}"
  info "disques réels détectés : $DISQUE1 et $DISQUE2"
  info "taille : $(lsblk -dno SIZE "$DISQUE1") / $(lsblk -dno SIZE "$DISQUE2")"
else
  SIMULE=1
  cat <<'EOF'

   ATTENTION — AUCUN DISQUE SUPPLÉMENTAIRE LIBRE N'A ÉTÉ TROUVÉ.

   Cette machine n'a pas (ou plus) deux disques vierges utilisables.
   Le setup fabrique donc DEUX DISQUES SIMULÉS : deux fichiers-images de
   5 Go attachés en « loop device ». Ils se comportent comme de vrais
   périphériques bloc : partitionnement, LVM, RAID, LUKS et montage
   fonctionnent normalement.

   Trois différences à connaître :
     - les noms sont /dev/loopN, pas /dev/sdb et /dev/sdc ;
     - les performances mesurées (E11.18, E11.19) n'ont aucun sens :
       tu mesures le disque qui héberge les images ;
     - après un redémarrage, les loop devices doivent être rattachés.
       Le service « lab11-loop.service » installé ci-dessous s'en charge.

EOF
  mkdir -p "$IMGD"
  for n in sdb sdc; do
    img="$IMGD/$n.img"
    [ -f "$img" ] || { truncate -s "$TAILLE_IMG" "$img"; info "image créée : $img"; }
    chmod 600 "$img"
    if [ -z "$(loop_de "$img")" ]; then
      losetup -fP "$img"
    fi
  done
  DISQUE1="$(loop_de "$IMGD/sdb.img")"
  DISQUE2="$(loop_de "$IMGD/sdc.img")"
  [ -n "$DISQUE1" ] && [ -n "$DISQUE2" ] || {
    echo "échec de l'attachement des images en loop device" >&2
    echo "vérifie que le module noyau 'loop' est disponible" >&2
    exit 1; }
  info "disques simulés : $DISQUE1 ($IMGD/sdb.img)"
  info "                  $DISQUE2 ($IMGD/sdc.img)"

  # --- rattachement automatique au démarrage --------------------------
  cat > /usr/local/sbin/lab11-loop-attach.sh <<'ATT'
#!/usr/bin/env bash
# Rattache les images du module 11 en loop device au démarrage.
set -euo pipefail
IMGD=/var/lib/lab11
for n in sdb sdc; do
  img="$IMGD/$n.img"
  [ -f "$img" ] || continue
  losetup -j "$img" | grep -q . || losetup -fP "$img"
done
ATT
  chmod 0755 /usr/local/sbin/lab11-loop-attach.sh

  if [ -d /run/systemd/system ]; then
    cat > /etc/systemd/system/lab11-loop.service <<'UNIT'
[Unit]
Description=Lab 11 - rattache les disques simules en loop device
DefaultDependencies=no
After=local-fs-pre.target systemd-udevd.service
Before=local-fs.target lvm2-activation-early.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/lab11-loop-attach.sh

[Install]
WantedBy=local-fs.target
UNIT
    systemctl daemon-reload
    systemctl enable lab11-loop.service >/dev/null 2>&1 || true
    info "service lab11-loop.service activé (rattachement au démarrage)"
  fi
fi

# ---------------------------------------------------------------------
# 2b. Troisième disque pour le RAID5 (E11.22), toujours simulé
# ---------------------------------------------------------------------
# Même quand sdb et sdc sont réels, la VM n'a pas de 3e disque : on en
# fabrique un en loop device. Il est conservé d'une exécution à l'autre.
DISQUE3=""
if [ "$MODE" = "--raid5" ] || [ -f "$IMGD/sdd.img" ]; then
  titre "Troisième disque (RAID5)"
  mkdir -p "$IMGD"
  img="$IMGD/sdd.img"
  [ -f "$img" ] || { truncate -s "$TAILLE_IMG" "$img"; info "image créée : $img"; }
  chmod 600 "$img"
  [ -n "$(loop_de "$img")" ] || losetup -fP "$img"
  DISQUE3="$(loop_de "$img")"
  [ -n "$DISQUE3" ] || { echo "échec de l'attachement de $img" >&2; exit 1; }
  info "disque simulé : $DISQUE3 ($img) — partition : ${DISQUE3}p1"
  # rattachement au démarrage : le script d'attache traite aussi sdd.img
  if [ -f /usr/local/sbin/lab11-loop-attach.sh ]; then
    sed -i 's/^for n in sdb sdc; do$/for n in sdb sdc sdd; do/' \
      /usr/local/sbin/lab11-loop-attach.sh
  else
    cat > /usr/local/sbin/lab11-loop-attach.sh <<'ATT'
#!/usr/bin/env bash
# Rattache les images du module 11 en loop device au démarrage.
set -euo pipefail
IMGD=/var/lib/lab11
for n in sdb sdc sdd; do
  img="$IMGD/$n.img"
  [ -f "$img" ] || continue
  losetup -j "$img" | grep -q . || losetup -fP "$img"
done
ATT
    chmod 0755 /usr/local/sbin/lab11-loop-attach.sh
    if [ -d /run/systemd/system ]; then
      cat > /etc/systemd/system/lab11-loop.service <<'UNIT'
[Unit]
Description=Lab 11 - rattache les disques simules en loop device
DefaultDependencies=no
After=local-fs-pre.target systemd-udevd.service
Before=local-fs.target lvm2-activation-early.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/lab11-loop-attach.sh

[Install]
WantedBy=local-fs.target
UNIT
      systemctl daemon-reload
      systemctl enable lab11-loop.service >/dev/null 2>&1 || true
    fi
  fi
fi

# ---------------------------------------------------------------------
# 3. /etc/lab11.env
# ---------------------------------------------------------------------
cat > "$ENVF" <<EOF
# Généré par setup_M11.sh — ne pas éditer à la main.
# Les deux disques de travail du module 11.
DISQUE1=$DISQUE1
DISQUE2=$DISQUE2
# Troisième disque (RAID5, E11.22), toujours un loop device ; vide sinon.
DISQUE3=$DISQUE3
# 1 = disques simulés par fichiers-images + loop devices
LAB11_SIMULE=$SIMULE
EOF
chmod 0644 "$ENVF"
info "$ENVF écrit"

# ---------------------------------------------------------------------
# 4. Compte de service, arborescence, jeu de données
# ---------------------------------------------------------------------
titre "Arborescence et jeu de données"

groupadd -f factura
if ! getent passwd factura >/dev/null; then
  useradd -r -g factura -d /srv/factura -s /usr/sbin/nologin factura
fi

mkdir -p /srv/factura/db /srv/factura/archives /srv/factura/journaux \
         /srv/sauvegardes "$BIN" "$LOGD" \
         "$BASE/rapports" "$BASE/sauvegardes"
chown -R factura:factura /srv/factura "$LOGD"
chmod 0755 /srv/factura /srv/sauvegardes
chown -R "$LAB_USER":"$LAB_USER" "$BASE"

# Jeu de données à sauvegarder / migrer. Volontairement modeste : le
# module manipule des volumes, pas des téraoctets.
if [ ! -f /srv/factura/db/comptes.dat ]; then
  {
    echo "# factura — plan comptable simplifié"
    for i in $(seq 1 400); do
      printf '%06d;CLI%04d;%d,%02d\n' "$i" $((i % 97)) $((i * 13)) $((i % 100))
    done
  } > /srv/factura/db/comptes.dat
  head -c 2M /dev/urandom > /srv/factura/db/index.bin
  : > /srv/factura/db/journal.wal
  chown -R factura:factura /srv/factura/db
  info "jeu de données créé dans /srv/factura/db"
else
  info "jeu de données déjà présent"
fi

# ---------------------------------------------------------------------
# 5. Générateur d'écritures (L11.2, L11.3)
# ---------------------------------------------------------------------
cat > "$BIN/factura-ecritures.sh" <<'GEN'
#!/usr/bin/env bash
# factura-ecritures.sh — simule une application qui écrit en continu.
#
#   factura-ecritures.sh <repertoire> [debit_ko_par_seconde]
#
# Écrit dans <repertoire>/journal.wal et fait tourner un lot de fichiers
# de travail. S'arrête proprement sur SIGINT/SIGTERM. Ne remplit jamais
# le volume : il recycle ses fichiers au-delà de 200 Mio écrits.
set -uo pipefail

CIBLE="${1:-/srv/factura/db}"
DEBIT="${2:-256}"          # Ko/s

[ -d "$CIBLE" ] || { echo "répertoire introuvable : $CIBLE" >&2; exit 1; }

ARRET=0
trap 'ARRET=1' INT TERM

echo "écritures en cours dans $CIBLE (${DEBIT} Ko/s) — Ctrl-C pour arrêter"
N=0
while [ "$ARRET" -eq 0 ]; do
  N=$((N + 1))
  printf '%s transaction %06d\n' "$(date '+%F %T')" "$N" >> "$CIBLE/journal.wal"
  dd if=/dev/urandom of="$CIBLE/travail-$((N % 20)).tmp" \
     bs=1K count="$DEBIT" status=none 2>/dev/null || true
  # on garde le journal sous les 50 Mio
  if [ "$(stat -c %s "$CIBLE/journal.wal" 2>/dev/null || echo 0)" -gt 52428800 ]
  then
    : > "$CIBLE/journal.wal"
  fi
  sleep 1
done
echo "arrêt propre après $N transactions"
GEN
chmod 0755 "$BIN/factura-ecritures.sh"
info "$BIN/factura-ecritures.sh installé"

# ---------------------------------------------------------------------
# 6. Résumé
# ---------------------------------------------------------------------
titre "Prêt"
cat <<EOF
   Disques de travail du module :
     DISQUE1 = $DISQUE1
     DISQUE2 = $DISQUE2
$([ -n "$DISQUE3" ] && echo "     DISQUE3 = $DISQUE3  (RAID5, simulé)" \
   || echo "     (3e disque pour le RAID5 : sudo bash \$0 --raid5)")
$([ "$SIMULE" -eq 1 ] && echo "   (SIMULÉS par fichiers-images — voir l'avertissement ci-dessus)")

   Charge-les dans ton shell avant chaque séance :
     . /etc/lab11.env
     echo "\$DISQUE1 \$DISQUE2"

   Générateur d'écritures (labs L11.2 et L11.3) :
     sudo $BIN/factura-ecritures.sh /srv/factura/db &

   État à tout moment :
     sudo bash \$0 --etat

   Snapshot Proxmox avant de commencer : qm snapshot 9003 avant-lab11
EOF
