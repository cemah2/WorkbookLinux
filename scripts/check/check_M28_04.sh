#!/usr/bin/env bash
# check_M28_04.sh — vérifie le lab L28.4 (sauvegarde par keytab, SSH GSSAPI)
# À lancer avec sudo sur lab-db (côté client), puis sur lab-web (côté cible).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
SVC=svc-sauvegarde
id "$SVC" >/dev/null 2>&1 || { echo "== Vérification L28.4 =="
  ko "$SVC inconnu sur cette machine (étape 1, ou SSSD arrêté)"; fin; }

case "$(hostname -s)" in
# ===========================================================================
lab-db)
  echo "== Vérification L28.4 — lab-db (client de la sauvegarde) =="
  K=/etc/svc-sauvegarde.keytab
  if [ -f "$K" ]; then
    [ "$(stat -c '%U %a' "$K")" = "$SVC 600" ] \
      && ok "keytab : propriétaire $SVC, 0600" \
      || ko "keytab : $(stat -c '%U %a' "$K") ; attendu $SVC 600"
    klist -k "$K" 2>/dev/null | grep -q "$SVC@LAB.LOCAL" \
      && ok "keytab : principal $SVC@LAB.LOCAL" \
      || ko "le keytab ne contient pas $SVC@LAB.LOCAL"
    CC=$(mktemp -u /tmp/krb5cc_check.XXXXXX)
    if sudo -u "$SVC" env KRB5CCNAME="FILE:$CC" kinit -k -t "$K" "$SVC@LAB.LOCAL" 2>/dev/null; then
      ok "kinit -k fonctionne avec ce keytab"
      sudo -u "$SVC" env KRB5CCNAME="FILE:$CC" kdestroy -q 2>/dev/null || true
    else
      ko "kinit -k échoue : clés régénérées ailleurs ? (kvno) heure ?"
    fi
    rm -f "$CC"
  else
    ko "$K absent (étape 2)"
  fi

  S=/usr/local/sbin/sauvegarde-nginx.sh
  if [ -x "$S" ]; then
    ok "script de sauvegarde présent et exécutable"
    grep -q 'kinit -k' "$S" \
      && ok "le script obtient son ticket par keytab" \
      || ko "le script n'utilise pas kinit -k"
    grep -Eq 'ssh .*-i |IdentityFile' "$S" \
      && ko "le script utilise encore une clé privée SSH" \
      || ok "aucune clé privée SSH dans le script"
    grep -q 'kdestroy' "$S" \
      && ok "le ticket est détruit en fin de script" \
      || ko "pas de kdestroy : le ticket survit au script"
  else
    ko "$S absent ou non exécutable (étape 4)"
  fi

  systemctl cat sauvegarde-nginx.service 2>/dev/null | grep -q "^User=$SVC" \
    && ok "le service tourne sous $SVC" \
    || ko "sauvegarde-nginx.service absent ou sans User=$SVC"
  systemctl is-enabled -q sauvegarde-nginx.timer 2>/dev/null \
    && systemctl is-active -q sauvegarde-nginx.timer \
    && ok "timer actif et activé au démarrage" \
    || ko "sauvegarde-nginx.timer inactif : systemctl enable --now"
  R=$(systemctl show -p Result --value sauvegarde-nginx.service 2>/dev/null)
  [ "$R" = success ] \
    && ok "dernier passage : success" \
    || ko "dernier passage : ${R:-jamais lancé} (journalctl -u sauvegarde-nginx)"

  D=/srv/sauvegardes/nginx
  A=$(find "$D" -maxdepth 1 -name 'nginx-*.tar.gz' -mtime -1 2>/dev/null | sort | tail -1)
  if [ -n "$A" ]; then
    ok "archive récente : $(basename "$A")"
    tar -tzf "$A" 2>/dev/null | grep -q '^nginx/nginx.conf$' \
      && ok "l'archive contient nginx/nginx.conf" \
      || ko "archive illisible ou sans nginx/nginx.conf"
  else
    ko "aucune archive de moins de 24 h dans $D"
  fi
  n=$(find "$D" -maxdepth 1 -name 'nginx-*.tar.gz' 2>/dev/null | wc -l)
  [ "$n" -le 7 ] && ok "rotation : $n archive(s), 7 au plus" \
                 || ko "rotation : $n archives, 7 au plus"
  [ -z "$(find "$D" -maxdepth 1 -name '*.part' 2>/dev/null)" ] \
    && ok "aucune archive partielle qui traîne" \
    || ko "des fichiers .part traînent dans $D"
  ;;
# ===========================================================================
lab-web)
  echo "== Vérification L28.4 — lab-web (cible de la sauvegarde) =="
  sss_cache -E 2>/dev/null || true
  L=$(sudo -l -U "$SVC" 2>/dev/null)
  grep -q 'tar -C /etc -czf - nginx' <<<"$L" \
    && ok "sudo : $SVC peut lancer la commande d'archivage exacte" \
    || ko "sudo : pas de règle « /usr/bin/tar -C /etc -czf - nginx » pour $SVC"
  grep -Eq '\(ALL( : ALL)?\) ALL' <<<"$L" \
    && ko "sudo : $SVC a (ALL) ALL ; une seule commande suffit" \
    || ok "sudo : $SVC n'a que ce dont il a besoin"
  grep -q 'NOPASSWD\|!authenticate' <<<"$L" \
    && ok "sudo sans mot de passe pour cette commande (!authenticate)" \
    || note "pas de NOPASSWD visible : la sauvegarde non interactive échouera"

  journalctl -u ssh -u sshd --since '-2 days' --no-pager 2>/dev/null |
    grep -q "Accepted gssapi-with-mic for $SVC" \
    && ok "journal : connexion GSSAPI de $SVC acceptée" \
    || ko "aucune connexion « Accepted gssapi-with-mic for $SVC » depuis 2 jours"

  FP=$(cat /var/lib/lab28/ancienne-cle.fp 2>/dev/null)
  if [ -n "$FP" ]; then
    trouve=""
    for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
      [ -f "$f" ] || continue
      ssh-keygen -lf "$f" 2>/dev/null | grep -qF "$FP" && trouve="$trouve $f"
      grep -q 'sauvegarde-legacy' "$f" && trouve="$trouve $f"
    done
    [ -z "$trouve" ] \
      && ok "l'ancienne clé n'est plus autorisée nulle part" \
      || ko "l'ancienne clé est encore autorisée :$trouve"
    LAB_HOME=$(getent passwd "${SUDO_USER:-mathieu}" | cut -d: -f6)
    ls "$LAB_HOME"/lab28/ancienne-cle/id_sauvegarde* >/dev/null 2>&1 \
      && ko "la paire de l'ancienne clé traîne encore dans ~/lab28/ancienne-cle/" \
      || ok "la paire de l'ancienne clé est détruite"
  else
    note "empreinte de l'ancienne clé inconnue : setup_M28.sh n'a pas été lancé ici"
  fi
  ;;
*)
  echo "== Vérification L28.4 =="
  ko "ce contrôle se lance sur lab-db puis sur lab-web" ;;
esac

fin
