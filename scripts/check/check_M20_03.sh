#!/usr/bin/env bash
# check_M20_03.sh — vérifie le lab L20.3 (pool lab20, clones, resize, virt-clone)
# À lancer sur lab-virt, en tant que mathieu, sans sudo.
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification L20.3 =="

V="virsh -c qemu:///system"
POOL=lab20 ; DIR=/srv/vm ; BASE=ubuntu-24.04-base.qcow2

# --- pool -----------------------------------------------------------------
if $V pool-info $POOL >/dev/null 2>&1; then
  ok "pool $POOL défini"
  $V pool-info $POOL | grep -q 'State: *running' && ok "pool actif" \
    || ko "pool inactif (virsh pool-start $POOL)"
  $V pool-info $POOL | grep -q 'Autostart: *yes' && ok "pool en autostart" \
    || ko "pool sans autostart"
  [ "$($V pool-dumpxml $POOL | grep -o '<path>[^<]*' | cut -d'>' -f2)" = "$DIR" ] \
    && ok "cible $DIR" || ko "le pool ne cible pas $DIR"
  $V vol-info --pool $POOL $BASE >/dev/null 2>&1 && ok "base présente dans le pool" \
    || ko "$BASE absente du pool (cp + pool-refresh)"
else
  ko "pool $POOL non défini"; echo "Résultat : $PASS réussis, $FAIL échoués"; exit 1
fi

# --- clone-1 : en marche, backing file, 30 Go ------------------------------
if $V dominfo clone-1 >/dev/null 2>&1; then
  ok "clone-1 définie"
  if [ "$($V domstate clone-1)" = running ]; then
    ok "clone-1 en marche"
    $V dumpxml clone-1 | grep -A3 '<backingStore' | grep -q "$DIR/$BASE" \
      && ok "clone-1 : overlay sur $DIR/$BASE" \
      || ko "clone-1 n'a pas la base du pool en backing file"
  else
    ko "clone-1 éteinte (virsh start clone-1)"
  fi
  CAP=$($V domblkinfo clone-1 vda 2>/dev/null | awk '/Capacity/{print $2}')
  [ -n "$CAP" ] && [ "$CAP" -ge 32212254720 ] \
    && ok "clone-1 : capacité vda >= 30 Go" \
    || ko "clone-1 : capacité vda < 30 Go (virsh blockresize clone-1 vda 30G)"
  $V domblklist clone-1 | grep -q "$DIR/clone-1.qcow2" \
    && ok "disque de clone-1 dans $DIR" || ko "disque de clone-1 hors du pool $POOL"
else
  ko "clone-1 non définie (clone3.sh)"
fi

# --- clone-4 : clone complet, sans backing file ----------------------------
if $V dominfo clone-4 >/dev/null 2>&1; then
  ok "clone-4 définie"
  VOL=$($V domblklist clone-4 | awk '$1=="vda"{print $2}')
  if [ -n "$VOL" ] && $V vol-dumpxml "$VOL" 2>/dev/null | grep -q '<backingStore'; then
    ko "clone-4 a encore un backing file : ce n'est pas un clone complet"
  else
    ok "clone-4 : disque autonome (pas de backing file)"
  fi
  U1=$($V domuuid clone-1 2>/dev/null); U4=$($V domuuid clone-4 2>/dev/null)
  [ -n "$U4" ] && [ "$U1" != "$U4" ] && ok "clone-4 a son propre UUID" \
    || ko "UUID de clone-4 identique à clone-1 ?"
else
  ko "clone-4 non définie (virt-clone)"
fi

# --- clone-2 / clone-3 supprimées avec leurs volumes -----------------------
for n in 2 3; do
  $V dominfo clone-$n >/dev/null 2>&1 \
    && ko "clone-$n existe encore (undefine --remove-all-storage)" \
    || ok "clone-$n supprimée"
  $V vol-info --pool $POOL clone-$n.qcow2 >/dev/null 2>&1 \
    && ko "volume clone-$n.qcow2 orphelin dans $POOL" \
    || ok "volume clone-$n.qcow2 absent"
done

# --- livrables -------------------------------------------------------------
S="$HOME/lab20/bin/clone3.sh"
if [ -s "$S" ]; then
  bash -n "$S" 2>/dev/null && ok "clone3.sh : syntaxe bash valide" \
    || ko "clone3.sh : erreur de syntaxe"
  grep -q 'backing-vol' "$S" && ok "clone3.sh crée des overlays (--backing-vol)" \
    || ko "clone3.sh n'utilise pas --backing-vol"
else
  ko "$S absent"
fi
R="$HOME/lab20/rapports/sto-208.md"
[ -s "$R" ] && grep -qi 'machine-id' "$R" && ok "rapport sto-208.md (machine-id cité)" \
  || ko "rapport $R absent ou incomplet (que nettoyer sur un clone à plat ?)"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
