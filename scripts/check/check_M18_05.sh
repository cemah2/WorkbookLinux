#!/usr/bin/env bash
# check_M18_05.sh — vérifie le lab L18.5 (durcissement et audit)
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
echo "== Vérification L18.5 =="

LAB_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
B="$LAB_HOME/lab18"

# --- 1. les deux états des lieux ---------------------------------------
for f in etat-initial.md etat-final.md; do
  if [ -s "$B/$f" ]; then
    n=$(wc -l < "$B/$f")
    [ "$n" -ge 20 ] \
      && ok "$f présent ($n lignes)" \
      || ko "$f trop court ($n lignes) : l'énoncé demande 7 rubriques"
  else
    ko "~/lab18/$f absent"
  fi
done

# --- 2. sysctl ---------------------------------------------------------
attendu="net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.tcp_syncookies=1
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.randomize_va_space=2"
ecarts=0; detail=""
while IFS='=' read -r cle val; do
  lu=$(sysctl -n "$cle" 2>/dev/null) || continue
  if [ "$lu" != "$val" ]; then
    ecarts=$((ecarts+1)); detail="$detail $cle=$lu(att.$val)"
  fi
done <<< "$attendu"
[ "$ecarts" -eq 0 ] \
  && ok "les 8 sysctl de sécurité sont aux valeurs attendues" \
  || ko "$ecarts écart(s) :$detail"

ls /etc/sysctl.d/*.conf >/dev/null 2>&1 \
  && grep -qrs 'kptr_restrict' /etc/sysctl.d/ \
  && ok "les valeurs sont persistées dans /etc/sysctl.d/" \
  || ko "rien dans /etc/sysctl.d/ : un sysctl -w ne survit pas au reboot"

# --- 3. /tmp -----------------------------------------------------------
OPTS=$(findmnt -no OPTIONS /tmp 2>/dev/null)
if [ -n "$OPTS" ]; then
  for o in noexec nosuid nodev; do
    grep -q "$o" <<<"$OPTS" \
      && ok "/tmp est monté $o" \
      || ko "/tmp n'a pas l'option $o (options : $OPTS)"
  done
  # preuve par l'usage
  T=$(mktemp /tmp/chk15.XXXX)
  printf '#!/bin/sh\necho ok\n' > "$T"; chmod +x "$T"
  if "$T" >/dev/null 2>&1; then
    ko "un script de /tmp s'exécute encore : noexec n'est pas effectif"
  else
    ok "l'exécution depuis /tmp est bien refusée"
  fi
  rm -f "$T"
else
  ko "/tmp n'est pas un point de montage distinct : impossible d'y poser \
noexec (fstab ou tmp.mount)"
fi

# --- 4. modules noyau --------------------------------------------------
BLK=$(cat /etc/modprobe.d/*.conf 2>/dev/null)
manque=""
for m in usb-storage firewire-core cramfs dccp sctp; do
  grep -qE "^\s*(install\s+$m\s+/bin/(true|false)|blacklist\s+$m)" \
    <<<"$BLK" || manque="$manque $m"
done
[ -z "$manque" ] \
  && ok "les cinq modules sont neutralisés" \
  || ko "modules non traités :$manque"
grep -qE '^\s*install\s+usb-storage' <<<"$BLK" \
  && ok "la forme « install ... /bin/true » est utilisée (plus solide que \
blacklist)" \
  || note "« blacklist » n'empêche que le chargement automatique : \
préfère « install <mod> /bin/true »"

# --- 5. comptes et mots de passe ---------------------------------------
U=$(awk '/^UMASK/{print $2}' /etc/login.defs 2>/dev/null)
[ "$U" = 027 ] || [ "$U" = 077 ] \
  && ok "UMASK = $U dans /etc/login.defs" \
  || ko "UMASK = ${U:-absent}, l'énoncé demande 027"
M=$(awk '/^PASS_MAX_DAYS/{print $2}' /etc/login.defs 2>/dev/null)
[ "${M:-99999}" -le 365 ] \
  && ok "PASS_MAX_DAYS = $M" \
  || ko "PASS_MAX_DAYS = ${M:-absent}, attendu 365 au plus"
W=$(awk '/^PASS_WARN_AGE/{print $2}' /etc/login.defs 2>/dev/null)
[ "${W:-0}" -ge 14 ] \
  && ok "PASS_WARN_AGE = $W" \
  || ko "PASS_WARN_AGE = ${W:-absent}, attendu 14"
grep -qE '^\s*minlen\s*=\s*(1[2-9]|[2-9][0-9])' \
  /etc/security/pwquality.conf 2>/dev/null \
  && ok "longueur minimale de mot de passe >= 12" \
  || ko "minlen non configuré dans /etc/security/pwquality.conf"

# --- 6. bannière -------------------------------------------------------
[ -s /etc/issue.net ] \
  && ok "/etc/issue.net contient une bannière" \
  || ko "/etc/issue.net vide : pas de bannière légale"

# --- 7. mises à jour automatiques --------------------------------------
if command -v apt-get >/dev/null 2>&1; then
  grep -rqs 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/ \
    && ok "unattended-upgrades est activé" \
    || ko "les mises à jour automatiques ne sont pas activées"
else
  systemctl is-enabled dnf-automatic.timer >/dev/null 2>&1 \
    && ok "dnf-automatic.timer est activé" \
    || ko "dnf-automatic.timer n'est pas activé"
fi

# --- 8. auditd ---------------------------------------------------------
if command -v auditctl >/dev/null 2>&1; then
  R=$(auditctl -l 2>/dev/null)
  for cible in /etc/passwd /etc/shadow /etc/sudoers; do
    grep -q "$cible" <<<"$R" \
      && ok "règle auditd active sur $cible" \
      || ko "aucune règle auditd chargée sur $cible (augenrules --load)"
  done
  grep -qs 'passwd' /etc/audit/rules.d/*.rules 2>/dev/null \
    && ok "les règles sont persistées dans /etc/audit/rules.d/" \
    || ko "règles non persistées : un auditctl -w disparaît au reboot"
else
  ko "auditd n'est pas installé"
fi

# --- 9. surface d'écoute ----------------------------------------------
if command -v ss >/dev/null 2>&1; then
  n=$(ss -tulnH 2>/dev/null | grep -vcE '127\.0\.0\.1|\[::1\]')
  [ "${n:-99}" -le 4 ] \
    && ok "surface d'écoute réduite : $n socket(s) exposé(s)" \
    || ko "$n sockets exposés hors boucle locale : l'étape 4 demande de \
justifier ou de restreindre chacun"
fi

# --- 10. lynis ---------------------------------------------------------
if [ -f /var/log/lynis-report.dat ]; then
  H=$(awk -F= '/^hardening_index=/{print $2}' /var/log/lynis-report.dat \
      | tail -1)
  ok "lynis a tourné, indice de durcissement : ${H:-?}"
  [ -f "$B/lynis-avant.dat" ] \
    && ok "le rapport d'origine est archivé pour l'avant/après" \
    || note "archive le rapport initial pour documenter la progression"
else
  ko "aucun rapport lynis (/var/log/lynis-report.dat)"
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
