#!/usr/bin/env bash
# check_PA_09.sh — vérifie le jalon PA.9 (durcissement et audit)
# À lancer sur lab-web et lab-db (lab-ops : tests communs).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
HOST="$(hostname -s)"
echo "== Vérification PA.9 sur $HOST =="
S() { sudo -n "$@" 2>/dev/null; }

# --- SSH -----------------------------------------------------------------
if T="$(S sshd -T)"; then
  echo "$T" | grep -q '^passwordauthentication no' \
    && ok "sshd : PasswordAuthentication no" \
    || ko "sshd : PasswordAuthentication doit être no"
  echo "$T" | grep -q '^permitrootlogin no' \
    && ok "sshd : PermitRootLogin no" || ko "sshd : PermitRootLogin doit être no"
  echo "$T" | grep -Eq '^(allowgroups|allowusers) ' \
    && ok "sshd : AllowGroups/AllowUsers défini" \
    || ko "sshd : restreins les comptes autorisés (AllowGroups)"
  echo "$T" | grep -q '^x11forwarding no' && ok "sshd : X11Forwarding no" \
    || ko "sshd : X11Forwarding no attendu"
else
  ko "sshd -T non exécutable (lance ce check avec sudo)"
fi

# --- pare-feu : politique par défaut -------------------------------------
U="$(S ufw status verbose)"
echo "$U" | grep -q 'Status: active' && ok "ufw actif" || ko "ufw inactif"
echo "$U" | grep -q 'deny (incoming)' && ok "ufw : deny incoming par défaut" \
  || ko "ufw : la politique entrante doit être deny"

# --- fail2ban ------------------------------------------------------------
[ "$(systemctl is-active fail2ban)" = active ] && ok "fail2ban actif" \
  || ko "fail2ban inactif"
J="$(S fail2ban-client status | grep 'Jail list' | cut -d: -f2)"
echo "$J" | grep -q sshd && ok "jail sshd active" || ko "jail sshd absente"
[ -f /etc/fail2ban/jail.local ] && ok "/etc/fail2ban/jail.local présent" \
  || ko "configure fail2ban dans jail.local, jamais jail.conf"
grep -rhs '^ignoreip' /etc/fail2ban/jail.local /etc/fail2ban/jail.d/ \
  | grep -q '10.10.10.10' && ok "fail2ban : ignoreip contient lab-adm" \
  || ko "fail2ban : ignoreip doit contenir 10.10.10.10 (sinon tu te bannis)"

# --- sysctl --------------------------------------------------------------
for kv in net.ipv4.tcp_syncookies=1 kernel.dmesg_restrict=1 \
          net.ipv4.conf.all.accept_redirects=0 \
          net.ipv4.conf.all.log_martians=1 kernel.kptr_restrict=2; do
  k="${kv%=*}"; v="${kv#*=}"
  [ "$(sysctl -n "$k" 2>/dev/null)" = "$v" ] && ok "sysctl $k = $v" \
    || ko "sysctl $k vaut « $(sysctl -n "$k" 2>/dev/null) », attendu $v"
done
ls /etc/sysctl.d/*factura* /etc/sysctl.d/*harden* >/dev/null 2>&1 \
  && ok "réglages sysctl persistés dans /etc/sysctl.d/" \
  || ko "les sysctl doivent être dans /etc/sysctl.d/ (pas seulement sysctl -w)"

# --- mises à jour automatiques --------------------------------------------
apt-config dump 2>/dev/null | grep -q 'APT::Periodic::Unattended-Upgrade "1"' \
  && ok "unattended-upgrades activé" \
  || ko "unattended-upgrades non activé (dpkg-reconfigure unattended-upgrades)"

# --- lynis ---------------------------------------------------------------
R=/var/log/lynis-report.dat
if S test -f "$R"; then
  IDX="$(S grep '^hardening_index=' "$R" | cut -d= -f2)"
  ok "rapport lynis présent (hardening_index=$IDX)"
  [ "${IDX:-0}" -ge 65 ] && ok "hardening_index >= 65" \
    || ko "hardening_index $IDX < 65 : traite encore quelques suggestions"
  [ -n "$(S find "$R" -mtime -7)" ] && ok "audit lynis de moins de 7 jours" \
    || ko "relance lynis après tes corrections (rapport > 7 jours)"
else
  ko "$R absent : sudo lynis audit system"
fi

case "$HOST" in
lab-web)
  # --- sudo restreint pour l'exploitant -----------------------------------
  if getent passwd pme-ops >/dev/null; then
    ok "compte pme-ops présent"
    L="$(S sudo -l -U pme-ops)"
    echo "$L" | grep -q 'systemctl' && ok "pme-ops : sudo sur systemctl" \
      || ko "pme-ops : aucune règle sudo pour systemctl"
    echo "$L" | grep -Eq '\(ALL(:ALL)?\) (NOPASSWD: )?ALL' \
      && ko "pme-ops a sudo ALL : la règle doit être restreinte" \
      || ok "pme-ops n'a pas sudo ALL"
    echo "$L" | grep -q 'factura' && ok "pme-ops : règles limitées à factura" \
      || ko "pme-ops : les commandes autorisées doivent viser factura-*"
    ls /etc/sudoers.d/ | grep -q . && ok "règles dans /etc/sudoers.d/" \
      || ko "écris les règles dans /etc/sudoers.d/ (visudo -cf)"
    for f in /etc/sudoers.d/*; do
      [ -e "$f" ] || continue
      S visudo -cf "$f" >/dev/null && ok "visudo -cf $f" \
        || ko "$f invalide selon visudo"
    done
  else
    ko "compte pme-ops absent (exploitant de la PME, sudo restreint)"
  fi

  # --- permissions --------------------------------------------------------
  W="$(S find /srv/factura /opt/factura /etc/factura -perm -o+w \
        ! -type l | head -n3)"
  [ -z "$W" ] && ok "aucun fichier world-writable sous factura" \
    || ko "world-writable : $W"
  O="$(S find /etc/factura -type f -perm /o+r | head -n3)"
  [ -z "$O" ] && ok "aucun secret de /etc/factura lisible par tous" \
    || ko "lisible par tous : $O"
  S find /opt/factura -type f ! -user root | grep -q . \
    && ko "des fichiers de /opt/factura n'appartiennent pas à root (le code \
ne doit pas être modifiable par le service)" \
    || ok "/opt/factura appartient à root"
  J="$(S fail2ban-client status | grep 'Jail list' | cut -d: -f2)"
  echo "$J" | grep -q nginx && ok "une jail nginx est active" \
    || ko "aucune jail nginx-* (filtre sur /var/log/nginx/factura.access.log)"
  S aa-status | grep -q 'profiles are in enforce mode' \
    && ok "AppArmor actif en enforce" || ko "AppArmor inactif ?"
  ;;
lab-db)
  P="$(S stat -c '%a' /var/lib/postgresql/16/main)"
  case "$P" in 700|750) ok "PGDATA en $P" ;; *) ko "PGDATA en $P (700)";; esac
  S grep -q '^ssl = on' /etc/postgresql/16/main/postgresql.conf \
    && ok "PostgreSQL : ssl = on" \
    || note "PostgreSQL sans TLS interne (acceptable dans le lab, à noter)"
  ;;
esac

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
