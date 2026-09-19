#!/usr/bin/env bash
# check_M08_07.sh — vérifie le lab L8.6 (batch confiné dans batch.slice)
# À lancer avec sudo (lecture du journal du noyau).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L8.6 =="

LAB_USER="${SUDO_USER:-$(id -un)}"
HOMEDIR=$(getent passwd "$LAB_USER" | cut -d: -f6)
RAP="$HOMEDIR/lab08/rapports/inc-3244.md"
SLICE=batch.slice
SVC=factura-lots.service
CG=/sys/fs/cgroup/$SLICE

# --- 1. le slice ----------------------------------------------------------
if [ -f "/etc/systemd/system/$SLICE" ]; then
  ok "unité $SLICE présente dans /etc/systemd/system"
  MM=$(systemctl show "$SLICE" -p MemoryMax --value 2>/dev/null)
  if [ -n "$MM" ] && [ "$MM" != infinity ] && [ "$MM" -le $((400*1024*1024)) ]; then
    ok "MemoryMax du slice = $((MM/1024/1024)) Mo (≤ 400)"
  else
    ko "MemoryMax du slice absent ou > 400M (lu : ${MM:-rien})"
  fi
  SW=$(systemctl show "$SLICE" -p MemorySwapMax --value 2>/dev/null)
  [ "$SW" = 0 ] && ok "MemorySwapMax=0 : pas de contournement par le swap" \
    || ko "MemorySwapMax doit valoir 0 sur le slice (lu : ${SW:-rien})"
  CQ=$(systemctl show "$SLICE" -p CPUQuotaPerSecUSec --value 2>/dev/null)
  [ -n "$CQ" ] && [ "$CQ" != infinity ] && ok "CPUQuota posé ($CQ par seconde)" \
    || ko "CPUQuota absent sur le slice"
  TM=$(systemctl show "$SLICE" -p TasksMax --value 2>/dev/null)
  [ -n "$TM" ] && [ "$TM" -le 64 ] 2>/dev/null && ok "TasksMax=$TM" \
    || ko "TasksMax absent ou trop grand sur le slice (lu : ${TM:-rien})"
  ls /etc/systemd/system.control/"$SLICE".d/*.conf >/dev/null 2>&1 \
    && ok "modification à chaud persistée (system.control, étape 6)" \
    || note "aucun drop-in system.control : set-property à chaud non joué ?"
else
  ko "/etc/systemd/system/$SLICE absent (étape 2)"
fi

# --- 2. le service ----------------------------------------------------------
if systemctl cat "$SVC" >/dev/null 2>&1; then
  ok "unité $SVC connue de systemd"
  [ "$(systemctl show "$SVC" -p Slice --value)" = "$SLICE" ] \
    && ok "$SVC rattaché à $SLICE" \
    || ko "$SVC n'est pas dans $SLICE (Slice= manquant ou daemon-reload oublié)"
  R=$(systemctl show "$SVC" -p Restart --value)
  case "$R" in
    on-failure|always|on-abnormal) ok "Restart=$R" ;;
    *) ko "Restart= doit relancer sur échec (lu : ${R:-no})" ;;
  esac
  [ "$(systemctl show "$SVC" -p User --value)" = factura ] \
    && ok "le batch tourne sous le compte factura" \
    || ko "User=factura attendu sur $SVC"
  SB=$(systemctl show "$SVC" -p StartLimitBurst --value)
  [ -n "$SB" ] && [ "$SB" -le 3 ] 2>/dev/null && ok "StartLimitBurst=$SB" \
    || ko "StartLimitBurst doit limiter à 3 relances (lu : ${SB:-défaut})"
  RES=$(systemctl show "$SVC" -p Result --value)
  case "$RES" in
    oom-kill|start-limit-hit) ok "dernier résultat du service : $RES" ;;
    *) note "Result=$RES : le batch n'a pas (encore) été tué par l'OOM du cgroup" ;;
  esac
else
  ko "$SVC introuvable (étape 3)"
fi

# --- 3. l'OOM est confiné ---------------------------------------------------
if [ -r "$CG/memory.events" ]; then
  OK_KILL=$(awk '/^oom_kill/{print $2}' "$CG/memory.events")
  [ "${OK_KILL:-0}" -ge 1 ] && ok "memory.events du slice : oom_kill $OK_KILL" \
    || ko "aucun oom_kill compté dans $CG/memory.events"
else
  note "$CG absent (slice vide : normal après reset-failed) — lecture via le journal"
fi
if journalctl -k -b --no-pager 2>/dev/null | grep -q 'oom_memcg=/batch.slice'; then
  ok "journal du noyau : OOM de cgroup dans batch.slice"
else
  ko "aucune ligne « Memory cgroup out of memory » pour batch.slice dans \
journalctl -k (étape 3-4)"
fi
GLOB=$(journalctl -k -b --no-pager 2>/dev/null | grep -c 'Out of memory: Killed process')
if [ "$GLOB" -eq 0 ]; then
  ok "aucun OOM global depuis le démarrage"
else
  note "$GLOB OOM global(aux) dans ce boot : attendu si l'étape 1 a été jouée \
sans limite ; vérifie qu'aucun n'est postérieur au slice"
fi
if systemctl is-active --quiet factura-api.service \
   || curl -fs -m2 http://127.0.0.1:8080/sante >/dev/null 2>&1; then
  ok "factura-api répond : l'API a survécu au batch"
else
  ko "factura-api ne répond pas sur 8080 (L8.2, ou unité transitoire à relancer)"
fi

# --- 4. le rapport ------------------------------------------------------------
if [ -s "$RAP" ]; then
  [ "$(grep -c . "$RAP")" -ge 15 ] && ok "rapport inc-3244.md rédigé" \
    || ko "rapport trop court (15 lignes minimum)"
  MANQUE=""
  for mot in batch.slice MemoryMax oom_kill set-property; do
    grep -qi -- "$mot" "$RAP" || MANQUE="$MANQUE $mot"
  done
  [ -z "$MANQUE" ] && ok "le rapport couvre slice, limite, preuve et modification" \
    || ko "le rapport ne parle pas de :$MANQUE"
else
  ko "rapport absent : $RAP"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
