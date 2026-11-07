#!/usr/bin/env bash
# check_M33_02.sh — vérifie le lab L33.2 (paquet Debian)
# À lancer sans sudo sur lab-adm (construction), puis sur lab-db (installation).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
has()  { grep "$@" >/dev/null; }   # comme grep -q, sans SIGPIPE (pipefail)
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
echo "== Vérification L33.2 =="
H=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)/lab33

role=""
for a in $(hostname -I 2>/dev/null); do
  case "$a" in 10.10.10.10) role=adm ;; 10.10.10.12) role=db ;; esac
done
[ -n "$role" ] || { [ -d "$H/deb" ] && role=adm || role=db; }
echo "   rôle : $role"

if [ "$role" = adm ]; then
  D="$H/deb"
  DEB="$D/lab33-sante_1.1-1_amd64.deb"
  [ -s "$D/lab33-sante_1.0-1_amd64.deb" ] && ok "paquet 1.0-1 construit" || ko "lab33-sante_1.0-1_amd64.deb absent de lab33/deb"
  [ -s "$D/lab33-sante_1.1-1.dsc" ] && ok "paquet source 1.1-1 (.dsc)" || ko "lab33-sante_1.1-1.dsc absent (construis avec dpkg-buildpackage, pas seulement -b)"
  [ -s "$DEB" ] || { ko "lab33-sante_1.1-1_amd64.deb absent de lab33/deb"; fin; }
  ok "paquet 1.1-1 construit"
  for f in control rules copyright changelog source/format; do
    [ -s "$D/lab33-sante-1.1/debian/$f" ] || ko "debian/$f absent dans lab33-sante-1.1"
  done
  has -E '^[[:space:]]*dh \$@' "$D/lab33-sante-1.1/debian/rules" 2>/dev/null \
    && ok "debian/rules utilise dh \$@" || ko "debian/rules n'utilise pas dh \$@"
  has -i 'format.*copyright-format/1.0' "$D/lab33-sante-1.1/debian/copyright" 2>/dev/null \
    && ok "copyright au format machine" || ko "debian/copyright n'est pas au format machine (Format: …copyright-format/1.0/)"

  t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
  dpkg-deb -x "$DEB" "$t/x" && dpkg-deb -e "$DEB" "$t/c"
  [ -x "$t/x/usr/bin/lab33-sante" ] && ok "le paquet livre /usr/bin/lab33-sante" || ko "pas de /usr/bin/lab33-sante dans le paquet"
  strings -a "$t/x/usr/bin/lab33-sante" 2>/dev/null | has -x '/etc/lab33-sante.conf' \
    && ok "le binaire empaqueté lit /etc/lab33-sante.conf" \
    || ko "le binaire empaqueté ne lit pas /etc/lab33-sante.conf (PREFIX=/usr à la COMPILATION)"
  has -x 'ExecStart=/usr/bin/lab33-sante' "$t/x/usr/lib/systemd/system/lab33-sante.service" 2>/dev/null \
    && ok "l'unité lance /usr/bin/lab33-sante" || ko "l'unité ne lance pas /usr/bin/lab33-sante"
  [ -e "$t/x/usr/local" ] && ko "le paquet installe sous /usr/local" || ok "rien sous /usr/local"
  has -x '/etc/lab33-sante.conf' "$t/c/conffiles" 2>/dev/null && ok "/etc/lab33-sante.conf est un conffile" \
                                                             || ko "/etc/lab33-sante.conf n'est pas un conffile"
  has 'systemd-sysusers' "$t/c/postinst" 2>/dev/null && ok "le postinst crée l'utilisateur (systemd-sysusers)" \
    || ko "le postinst n'appelle pas systemd-sysusers (dh-sequence-installsysusers dans Build-Depends ?)"
  has "enable 'lab33-sante.timer'" "$t/c/postinst" 2>/dev/null && ok "le postinst active le minuteur" \
                                                               || ko "le postinst n'active pas lab33-sante.timer"
  has "enable 'lab33-sante.service'" "$t/c/postinst" 2>/dev/null \
    && note "le service est aussi activé : seul le minuteur devrait l'être (dh_installsystemd lab33-sante.timer)"
  has -x 'User=lab33' "$t/x/usr/lib/systemd/system/lab33-sante.service" 2>/dev/null \
    && ok "le service s'exécute sous lab33" || ko "l'unité n'a pas User=lab33"
  dpkg-deb -f "$DEB" Depends | has 'libc6' && ok "Depends généré (libc6, \${shlibs:Depends})" \
                                           || ko "pas de dépendance libc6 (\${shlibs:Depends} oublié ?)"
  if command -v lintian >/dev/null; then
    out=$(lintian "$DEB" 2>/dev/null)
    if printf '%s\n' "$out" | has -E '^[EW]: '; then
      ko "lintian signale encore des erreurs ou avertissements :"
      printf '%s\n' "$out" | grep -E '^[EW]: ' | head -5 | sed 's/^/         /'
    else
      ok "lintian : aucune erreur ni avertissement"
    fi
  else
    ko "lintian absent (voir 33.1)"
  fi
  fin
fi

# --- lab-db --------------------------------------------------------------------------
st=$(dpkg-query -W -f='${db:Status-Status} ${Version}' lab33-sante 2>/dev/null)
case "$st" in
  installed\ *) v=${st#installed }
                if dpkg --compare-versions "$v" ge 1.1-1; then ok "lab33-sante $v installé"
                else ko "lab33-sante $v installé : la 1.1-1 est attendue"; fi ;;
  *) ko "lab33-sante n'est pas installé"; fin ;;
esac
u=$(getent passwd lab33)
[ -n "$u" ] && ok "utilisateur système lab33" || ko "utilisateur lab33 absent"
case "$u" in *nologin|*/false) ok "lab33 sans shell de connexion" ;; "") ;; *) ko "lab33 a un shell de connexion" ;; esac
if [ -n "$u" ]; then
  [ "$(echo "$u" | cut -d: -f3)" -lt 1000 ] && ok "UID système (< 1000)" || ko "UID de lab33 ≥ 1000 : pas un utilisateur système"
fi
[ "$(systemctl is-enabled lab33-sante.timer 2>/dev/null)" = enabled ] && ok "minuteur activé" || ko "lab33-sante.timer non activé"
systemctl is-active --quiet lab33-sante.timer && ok "minuteur actif" || ko "lab33-sante.timer inactif"
[ "$(systemctl show -p User --value lab33-sante.service 2>/dev/null)" = lab33 ] && ok "service exécuté sous lab33" \
                                                                     || ko "le service ne s'exécute pas sous lab33"
r=$(systemctl show -p Result --value lab33-sante.service 2>/dev/null)
case "$r" in
  success|exit-code) ok "le service s'est exécuté (résultat : $r ; exit-code = un service injoignable)" ;;
  *) ko "résultat du service : $r (journalctl -u lab33-sante)" ;;
esac
if journalctl -u lab33-sante.service -n 20 --no-pager 2>/dev/null | has 'services joignables'; then
  ok "le journal contient les passages de lab33-sante"
else
  note "aucun passage visible dans le journal (droits : groupe adm, ou sudo journalctl)"
fi
if dpkg --verify lab33-sante 2>/dev/null | has '/etc/lab33-sante.conf'; then
  ok "configuration locale conservée (modifiée par rapport au paquet)"
else
  note "configuration identique à celle du paquet (normal après le purge de l'étape 6)"
fi
[ -e /etc/lab33-sante.conf.dpkg-dist ] && note "/etc/lab33-sante.conf.dpkg-dist présent : version du paquet à fusionner"
fin
