#!/usr/bin/env bash
# check_M11_09.sh — vérifie le lab L11.8 (cible iSCSI sur lab-ops,
#                   initiateur lab-db + LVM + fstab). À lancer sur les deux VM.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L11.8 =="

PORTAIL=10.10.10.14
IQN_CIBLE=iqn.2026-09.local.lab:ops.disque0
IQN_INIT=iqn.2026-09.local.lab:db
SAVE=/etc/rtslib-fb-target/saveconfig.json
VG=vg_iscsi
LV=lv_depots
MNT=/srv/factura/depots
HOTE="$(hostname -s 2>/dev/null || hostname)"

case "$HOTE" in
# ======================= cible ============================================
lab-ops)
  if ! command -v targetcli >/dev/null 2>&1; then
    ko "targetcli absent : sudo apt install -y targetcli-fb"
    echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
  fi
  if [ -d /run/systemd/system ]; then
    systemctl is-active --quiet rtslib-fb-targetctl.service \
      && ok "rtslib-fb-targetctl.service est actif" \
      || ko "rtslib-fb-targetctl.service n'est pas actif"
    systemctl is-enabled --quiet rtslib-fb-targetctl.service 2>/dev/null \
      && ok "rtslib-fb-targetctl.service est activé au démarrage" \
      || ko "rtslib-fb-targetctl.service n'est pas activé (enable)"
  fi
  # la configuration vivante est dans configfs ; la persistance dans le JSON
  CFG=/sys/kernel/config/target/iscsi
  if [ -d "$CFG/$IQN_CIBLE" ]; then
    ok "la cible $IQN_CIBLE existe (configfs)"
    TPG="$CFG/$IQN_CIBLE/tpgt_1"
    ls "$TPG/lun/" 2>/dev/null | grep -q '^lun_0$' \
      && ok "la LUN 0 est présente" \
      || ko "pas de LUN 0 sur tpg1 (luns/ create /backstores/fileio/...)"
    if [ -d "$TPG/acls/$IQN_INIT" ]; then
      ok "ACL présente pour $IQN_INIT"
      U=$(cat "$TPG/acls/$IQN_INIT/auth/userid" 2>/dev/null)
      if [ -n "$U" ] && [ "$U" != "NULL" ]; then
        ok "CHAP configuré sur l'ACL (userid=$U)"
      else
        ko "pas d'identifiant CHAP sur l'ACL (set auth userid=... password=...)"
      fi
    else
      ko "aucune ACL pour $IQN_INIT (acls/ create $IQN_INIT)"
    fi
    A=$(cat "$TPG/attrib/authentication" 2>/dev/null)
    [ "${A:-0}" = "1" ] \
      && ok "authentification exigée sur le TPG" \
      || ko "attribut authentication=0 : CHAP n'est pas exigé sur le TPG"
    G=$(cat "$TPG/attrib/generate_node_acls" 2>/dev/null)
    [ "${G:-0}" = "0" ] \
      && ok "generate_node_acls=0 : seuls les IQN listés passent" \
      || ko "generate_node_acls=1 : mode démo, n'importe quel IQN se connecte"
    ls "$TPG/np/" 2>/dev/null | grep -q "^$PORTAIL:3260$" \
      && ok "portail $PORTAIL:3260 présent" \
      || ko "pas de portail $PORTAIL:3260 (portals/ create $PORTAIL 3260)"
    ls "$TPG/np/" 2>/dev/null | grep -q '^0.0.0.0:3260$' \
      && ko "le portail 0.0.0.0:3260 écoute encore sur toutes les interfaces"
  else
    ko "la cible $IQN_CIBLE n'existe pas dans configfs (targetcli, /iscsi ls)"
  fi
  BS=/sys/kernel/config/target/core
  if ls -d "$BS"/fileio_*/disque0 >/dev/null 2>&1; then
    ok "backstore fileio « disque0 » présent"
  else
    ko "pas de backstore fileio nommé disque0"
  fi
  if [ -r "$SAVE" ]; then
    grep -q "$IQN_CIBLE" "$SAVE" \
      && ok "la cible est sauvegardée dans $SAVE" \
      || ko "$SAVE ne contient pas la cible : saveconfig oublié"
    grep -q "$IQN_INIT" "$SAVE" \
      && ok "l'ACL est sauvegardée dans $SAVE" \
      || ko "$SAVE ne contient pas l'ACL : saveconfig après la modification"
  else
    ko "$SAVE absent ou illisible : rien ne survivra au redémarrage"
  fi
  ss -tln 2>/dev/null | grep -q ":3260 " \
    && ok "le port 3260 écoute" \
    || ko "rien n'écoute sur 3260"
  ;;
# ======================= initiateur ======================================
lab-db)
  if ! command -v iscsiadm >/dev/null 2>&1; then
    ko "open-iscsi absent : sudo apt install -y open-iscsi"
    echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
  fi
  grep -qs "^InitiatorName=$IQN_INIT\$" /etc/iscsi/initiatorname.iscsi \
    && ok "IQN de l'initiateur : $IQN_INIT" \
    || ko "/etc/iscsi/initiatorname.iscsi ne vaut pas InitiatorName=$IQN_INIT"
  if iscsiadm -m session 2>/dev/null | grep -q "$IQN_CIBLE"; then
    ok "une session iSCSI est ouverte vers $IQN_CIBLE"
  else
    ko "aucune session vers $IQN_CIBLE (iscsiadm -m discovery, puis --login)"
  fi
  if lsblk -dno VENDOR 2>/dev/null | grep -q 'LIO-ORG'; then
    ok "un disque LIO-ORG est visible dans lsblk"
  else
    ko "aucun disque LIO-ORG dans lsblk -o NAME,VENDOR"
  fi
  NODE=/etc/iscsi/nodes/$IQN_CIBLE/$PORTAIL,3260,1/default
  if [ -r "$NODE" ]; then
    grep -q '^node.startup = automatic' "$NODE" \
      && ok "node.startup = automatic" \
      || ko "node.startup n'est pas automatic (iscsiadm --op update -n \
node.startup -v automatic)"
    grep -q '^node.session.auth.authmethod = CHAP' "$NODE" \
      && ok "CHAP configuré sur le nœud" \
      || ko "pas de CHAP sur le nœud (node.session.auth.authmethod)"
  else
    [ "$(id -u)" -eq 0 ] \
      && ko "enregistrement de nœud absent : $NODE (discovery ?)" \
      || note "relance avec sudo pour vérifier $NODE"
  fi
  if [ -d /run/systemd/system ]; then
    for u in iscsid.service open-iscsi.service; do
      systemctl is-enabled --quiet "$u" 2>/dev/null \
        && ok "$u est activé au démarrage" \
        || ko "$u n'est pas activé (systemctl enable $u)"
    done
  fi
  if command -v pvs >/dev/null 2>&1; then
    PV=$(pvs --noheadings -o pv_name,vg_name 2>/dev/null \
      | awk -v vg="$VG" '$2==vg{print $1}')
    if [ -n "$PV" ]; then
      ok "le VG $VG repose sur $PV"
      PVDEV=$(readlink -f "$PV")
      lsblk -dno VENDOR "$PVDEV" 2>/dev/null | grep -q 'LIO-ORG' \
        && ok "ce PV est bien le disque iSCSI" \
        || ko "$PV n'est pas le disque iSCSI (lsblk -o NAME,VENDOR)"
    else
      ko "pas de VG $VG (pvcreate sur le disque iSCSI, vgcreate $VG)"
    fi
    lvs "$VG/$LV" >/dev/null 2>&1 \
      && ok "le LV $VG/$LV existe" \
      || ko "le LV $VG/$LV n'existe pas"
  fi
  if findmnt -no TARGET "$MNT" >/dev/null 2>&1; then
    SRC=$(findmnt -no SOURCE "$MNT")
    case "$SRC" in
      /dev/mapper/${VG}-${LV}|/dev/${VG}/${LV})
        ok "$MNT est monté depuis $VG/$LV" ;;
      *) ko "$MNT est monté depuis $SRC, attendu $VG/$LV" ;;
    esac
  else
    ko "$MNT n'est pas monté"
  fi
  LIGNE=$(awk -v m="$MNT" '$0 !~ /^[[:space:]]*#/ && $2 == m {print}' \
    /etc/fstab 2>/dev/null | tail -1)
  if [ -n "$LIGNE" ]; then
    ok "une ligne /etc/fstab couvre $MNT"
    OPTS=$(echo "$LIGNE" | awk '{print $4}')
    echo "$OPTS" | grep -q '_netdev' \
      && ok "_netdev présent" \
      || ko "il manque _netdev : le montage serait tenté avant iSCSI"
    echo "$OPTS" | grep -q 'nofail' \
      && ok "nofail présent" \
      || ko "il manque nofail : cible absente = mode maintenance"
    echo "$LIGNE" | awk '{print $1}' | grep -qE '^/dev/sd' \
      && ko "la source est un /dev/sdX : utilise le chemin LVM"
  else
    ko "aucune ligne /etc/fstab pour $MNT"
  fi
  ;;
*)
  ko "hôte inattendu ($HOTE) : lance ce script sur lab-ops ou lab-db"
  ;;
esac

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
