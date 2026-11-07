#!/usr/bin/env bash
# check_M30_01.sh — vérifie le lab L30.1 (restic vers lab-ops)
# À lancer avec sudo sur lab-web (client), puis sur lab-ops (dépôt).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

case "$(hostname -s)" in
lab-web)
  echo "== Vérification L30.1 — lab-web =="
  command -v restic >/dev/null || { ko "restic absent"; fin; }
  E=/etc/restic/lab-web.env; P=/etc/restic/mot-de-passe
  [ -f "$E" ] && ok "fichier d'environnement $E" || { ko "$E absent"; fin; }
  if [ -f "$P" ]; then
    [ "$(stat -c '%U %a' "$P")" = "root 600" ] && ok "phrase de passe : root, 0600" \
      || ko "phrase de passe : $(stat -c '%U %a' "$P") ; attendu root 600"
  else ko "$P absent"; fi
  set -a; . "$E"; set +a
  grep -q '^sftp:restic@lab-ops' <<<"${RESTIC_REPOSITORY:-}" \
    && ok "dépôt SFTP sur lab-ops : $RESTIC_REPOSITORY" || ko "dépôt inattendu : ${RESTIC_REPOSITORY:-vide}"

  J=$(restic snapshots --json 2>/dev/null)
  if [ -n "$J" ] && [ "$J" != "null" ] && [ "$J" != "[]" ]; then
    n=$(jq length <<<"$J"); ok "$n instantané(s) dans le dépôt"
    der=$(jq -r '.[-1].time' <<<"$J")
    age=$(( $(date +%s) - $(date -d "$der" +%s) ))
    [ "$age" -le 93600 ] && ok "dernier instantané il y a $((age / 3600)) h" \
                         || ko "dernier instantané il y a $((age / 3600)) h (plus de 26 h)"
    restic ls latest /etc/nginx/nginx.conf 2>/dev/null | grep -qxF /etc/nginx/nginx.conf \
      && ok "/etc/nginx/nginx.conf est dans le dernier instantané" \
      || ko "/etc/nginx/nginx.conf absent du dernier instantané"
    restic ls latest /var/www 2>/dev/null | grep -q 'cache/a-ne-pas-sauvegarder.bin' \
      && ko "le cache de /var/www/lab30 est sauvegardé : exclusions inopérantes" \
      || ok "le cache est bien exclu"
  else
    ko "aucun instantané lisible (dépôt, phrase, clé SSH ?)"
  fi
  U=$(systemctl cat restic-sauvegarde.service 2>/dev/null)
  grep -q 'restic forget' <<<"$U" && grep -q -- '--prune' <<<"$U" \
    && ok "rétention avec nettoyage dans l'unité" || ko "pas de restic forget … --prune dans l'unité"
  grep -q 'restic check' <<<"$U" && ok "contrôle du dépôt dans l'unité" || ko "pas de restic check"
  systemctl is-enabled -q restic-sauvegarde.timer 2>/dev/null && \
    systemctl is-active -q restic-sauvegarde.timer \
    && ok "timer actif" || ko "restic-sauvegarde.timer inactif"
  ;;
lab-ops)
  echo "== Vérification L30.1 — lab-ops =="
  T=$(sshd -T -C user=restic,host=lab-web,addr=10.10.10.11 2>/dev/null)
  grep -qi '^forcecommand internal-sftp' <<<"$T" && ok "restic : SFTP seulement (internal-sftp)" \
                                                 || ko "restic : ForceCommand internal-sftp absent"
  grep -qi '^chrootdirectory /srv/restic' <<<"$T" && ok "restic : prison chroot /srv/restic" \
                                                  || ko "restic : pas de ChrootDirectory /srv/restic"
  grep -qi '^allowtcpforwarding no' <<<"$T" && ok "restic : pas de redirection de ports" \
                                            || ko "restic : AllowTcpForwarding n'est pas à no"
  [ "$(stat -c '%U %a' /srv/restic)" = "root 755" ] && ok "/srv/restic : root 755 (exigence du chroot)" \
    || ko "/srv/restic : $(stat -c '%U %a' /srv/restic) ; le chroot exige root et pas d'écriture tiers"
  [ -f /srv/restic/lab-web/config ] && ok "dépôt initialisé dans /srv/restic/lab-web" \
                                    || ko "pas de dépôt dans /srv/restic/lab-web"
  [ "$(stat -c %U /srv/restic/lab-web 2>/dev/null)" = restic ] && ok "dépôt appartenant à restic" \
                                                               || ko "le dépôt n'appartient pas à restic"
  getent passwd restic | grep -q 'nologin$' && ok "restic n'a pas de shell" \
                                            || note "restic a un shell (inutile avec internal-sftp)"
  ;;
*) echo "== Vérification L30.1 =="; ko "à lancer sur lab-web puis sur lab-ops" ;;
esac
fin
