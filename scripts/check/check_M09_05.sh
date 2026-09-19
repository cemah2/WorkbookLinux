#!/usr/bin/env bash
# check_M09_05.sh — vérifie le lab L9.5 (serveur chrony sur lab-adm)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L9.5 (à lancer sur lab-adm) =="

HOME_DIR="$(getent passwd "${SUDO_USER:-${USER:-$(id -un)}}" | cut -d: -f6)"
RAP="$HOME_DIR/lab09/rapports"

if [ -f /etc/chrony/chrony.conf ]; then
  UNIT=chrony.service; CONF=/etc/chrony
elif [ -f /etc/chrony.conf ]; then
  UNIT=chronyd.service; CONF=/etc
else
  ko "chrony n'est pas installé"; echo "Résultat : $PASS réussis, $FAIL échoués"
  exit 1
fi

[ "$(systemctl is-active $UNIT 2>/dev/null)" = active ] \
  && ok "$UNIT est actif" || ko "$UNIT inactif"
[ "$(systemctl is-enabled $UNIT 2>/dev/null)" = enabled ] \
  && ok "$UNIT activé au boot" || ko "$UNIT n'est pas enabled"
case "$(systemctl is-active systemd-timesyncd 2>/dev/null)" in
  active) ko "systemd-timesyncd tourne encore en même temps que chrony" ;;
  *)      ok "systemd-timesyncd n'est pas actif" ;;
esac

ss -ulnp 2>/dev/null | grep -q ':123 ' \
  && ok "écoute UDP 123" || ko "rien n'écoute en UDP 123 (chronyd démarré ?)"

grep -rhsE '^\s*allow\s' "$CONF" 2>/dev/null | grep -q '10.10.10' \
  && ok "directive allow pour 10.10.10.0/24" \
  || ko "aucune directive 'allow 10.10.10.0/24' dans la configuration"
grep -rhsqE '^\s*local\s+stratum' "$CONF" 2>/dev/null \
  && ok "local stratum configuré (sert le lab sans Internet)" \
  || ko "pas de 'local stratum 10'"

if command -v chronyc >/dev/null 2>&1; then
  chronyc tracking 2>/dev/null | grep -q 'Leap status *: Normal' \
    && ok "chronyc tracking : Leap status Normal (synchronisé)" \
    || ko "chrony n'est pas synchronisé (chronyc sources -v)"
  C=$(sudo -n chronyc clients 2>/dev/null | grep -cE '^10\.10\.10\.' || true)
  [ "${C:-0}" -ge 1 ] && ok "$C client(s) du lab vu(s) par chronyc clients" \
    || ko "aucun client 10.10.10.x vu (clients configurés ? serveur \
redémarré avant eux ?)"
fi

TZ_NOW=$(timedatectl show -p Timezone --value 2>/dev/null)
[ "$TZ_NOW" = "Europe/Paris" ] && ok "fuseau Europe/Paris" \
  || ko "fuseau = ${TZ_NOW:-?}, attendu Europe/Paris"
[ "$(timedatectl show -p LocalRTC --value 2>/dev/null)" = no ] \
  && ok "RTC en UTC" || ko "RTC en heure locale : à remettre en UTC"

if [ -f "$RAP/temps.md" ] && [ "$(wc -l < "$RAP/temps.md")" -ge 15 ]; then
  ok "rapport temps.md présent"
  grep -qiE 'slew|makestep' "$RAP/temps.md" \
    && ok "le rapport traite slew/makestep" \
    || ko "le rapport ne parle ni de slew ni de makestep"
else
  ko "rapport $RAP/temps.md absent ou trop court"
fi
note "lab-web et lab-rhel : vérifie 'chronyc sources' à la main (^* 10.10.10.10)"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
