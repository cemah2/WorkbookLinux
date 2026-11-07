#!/usr/bin/env bash
# check_M33_03.sh — vérifie le lab L33.3 (le même logiciel en RPM)
# À lancer avec sudo sur lab-rhel.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
has()  { grep "$@" >/dev/null; }   # comme grep -q, sans SIGPIPE (pipefail)
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L33.3 =="
[ "$(id -u)" -eq 0 ] || { ko "à lancer avec sudo"; fin; }
U="${SUDO_USER:-mathieu}"
H=$(getent passwd "$U" | cut -d: -f6)
T="$H/rpmbuild"

# --- le .spec ---------------------------------------------------------------------
SPEC="$T/SPECS/lab33-sante.spec"
if [ -s "$SPEC" ]; then
  ok "lab33-sante.spec présent"
  has -E '^Version:[[:space:]]*1\.1' "$SPEC" && ok "Version: 1.1" || ko "le .spec n'est pas en version 1.1"
  has -E '^Release:[[:space:]]*1%\{\?dist\}' "$SPEC" && ok "Release: 1%{?dist}" || ko "Release attendue : 1%{?dist}"
  has '%autosetup' "$SPEC" && ok "%autosetup" || ko "pas de %autosetup"
  has -E '%make_build.*PREFIX=%\{_prefix\}' "$SPEC" && ok "%make_build avec PREFIX=%{_prefix}" \
    || ko "%make_build sans PREFIX=%{_prefix} (le binaire chercherait /usr/local/etc)"
  has -E '%make_install.*PREFIX=%\{_prefix\}' "$SPEC" && ok "%make_install avec PREFIX=%{_prefix}" \
                                                      || ko "%make_install sans PREFIX=%{_prefix}"
  has -E '%config\(noreplace\)[[:space:]]+%\{_sysconfdir\}/' "$SPEC" && ok "%config(noreplace) pour la configuration" \
                                                                      || ko "pas de %config(noreplace) %{_sysconfdir}/…"
  has '%license' "$SPEC" && ok "%license" || ko "pas de %license"
  has '%sysusers_create_compat' "$SPEC" && ok "utilisateur créé par %sysusers_create_compat" \
                                        || ko "pas de %sysusers_create_compat"
  has -E '%systemd_post' "$SPEC" && has -E '%systemd_preun' "$SPEC" && ok "scriptlets systemd (%systemd_post/preun)" \
                                                                    || ko "scriptlets systemd manquants"
  has '%changelog' "$SPEC" && [ "$(sed -n '/^%changelog/,$p' "$SPEC" | grep -c '^\*')" -ge 2 ] \
    && ok "%changelog avec au moins deux entrées" || ko "%changelog : une entrée par version attendue (1.0-1, 1.1-1)"
else
  ko "rpmbuild/SPECS/lab33-sante.spec absent"
fi

# --- les paquets construits ----------------------------------------------------------
RPM=$(find "$T/RPMS/x86_64" -maxdepth 1 -name 'lab33-sante-1.1-1.*.x86_64.rpm' 2>/dev/null | head -1)
SRPM=$(find "$T/SRPMS" -maxdepth 1 -name 'lab33-sante-1.1-1.*.src.rpm' 2>/dev/null | head -1)
[ -n "$SRPM" ] && ok "paquet source $(basename "$SRPM")" || ko "pas de lab33-sante-1.1-1….src.rpm (rpmbuild -ba)"
if [ -n "$RPM" ]; then
  ok "paquet binaire $(basename "$RPM")"
  if command -v rpmlint >/dev/null; then
    res=$(sudo -u "$U" rpmlint "$SPEC" "$RPM" 2>/dev/null | grep 'checked' | tail -1)
    case "$res" in
      *" 0 errors"*) ok "rpmlint : 0 erreur ($res)" ;;
      *) ko "rpmlint : $res" ;;
    esac
  else
    ko "rpmlint absent (voir 33.1)"
  fi
else
  ko "pas de lab33-sante-1.1-1….x86_64.rpm dans rpmbuild/RPMS/x86_64"
fi

# --- installation ----------------------------------------------------------------------
v=$(rpm -q --qf '%{VERSION}-%{RELEASE}' lab33-sante 2>/dev/null) || v=""
case "$v" in
  1.1-*) ok "lab33-sante $v installé" ;;
  "")    ko "lab33-sante n'est pas installé"; fin ;;
  *)     ko "lab33-sante $v installé : la 1.1 est attendue" ;;
esac
strings -a /usr/bin/lab33-sante 2>/dev/null | has -x '/etc/lab33-sante.conf' \
  && ok "le binaire installé lit /etc/lab33-sante.conf" || ko "le binaire installé ne lit pas /etc/lab33-sante.conf"
has -x 'ExecStart=/usr/bin/lab33-sante' /usr/lib/systemd/system/lab33-sante.service 2>/dev/null \
  && ok "l'unité lance /usr/bin/lab33-sante" || ko "l'unité ne lance pas /usr/bin/lab33-sante"
getent passwd lab33 >/dev/null && ok "utilisateur système lab33" || ko "utilisateur lab33 absent"
[ "$(systemctl is-enabled lab33-sante.timer 2>/dev/null)" = enabled ] && ok "minuteur activé" \
  || ko "lab33-sante.timer non activé (sur RHEL, les presets n'activent rien : systemctl enable --now)"
systemctl is-active --quiet lab33-sante.timer && ok "minuteur actif" || ko "lab33-sante.timer inactif"
ctx=$(stat -c %C /usr/bin/lab33-sante 2>/dev/null)
case "$ctx" in *:bin_t:*) ok "contexte SELinux du binaire : bin_t" ;; *) ko "contexte SELinux inattendu : ${ctx:-?}" ;; esac
[ -e /etc/lab33-sante.conf.rpmnew ] && ok "/etc/lab33-sante.conf.rpmnew présent (configuration locale gardée)" \
  || ko "pas de .rpmnew : modifie /etc/lab33-sante.conf AVANT la mise à jour 1.0 → 1.1"
rpm -V lab33-sante 2>/dev/null | has '/etc/lab33-sante.conf' && ok "configuration locale modifiée et conservée" \
                                                             || note "configuration identique à celle du paquet"
fin
