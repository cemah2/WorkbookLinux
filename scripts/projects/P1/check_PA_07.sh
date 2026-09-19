#!/usr/bin/env bash
# check_PA_07.sh — vérifie le jalon PA.7 (sauvegardes, rotation, restauration)
# À lancer sur lab-db, lab-web (producteurs) et lab-ops (dépôt).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
HOST="$(hostname -s)"
echo "== Vérification PA.7 sur $HOST =="
S() { sudo -n "$@" 2>/dev/null; }

check_timer() {   # check_timer <unité.timer>
  local t="$1" s="${1%.timer}.service"
  [ "$(systemctl is-active "$t")" = active ] && ok "$t actif" \
    || ko "$t inactif"
  [ "$(systemctl is-enabled "$t" 2>/dev/null)" = enabled ] \
    && ok "$t activé au boot" || ko "$t non enabled"
  systemctl show -p TimersCalendar --value "$t" | grep -q 'OnCalendar' \
    && ok "$t : OnCalendar défini" || ko "$t : OnCalendar attendu"
  [ "$(systemctl show -p Persistent --value "$t")" = yes ] \
    && ok "$t : Persistent=yes (rattrapage après extinction)" \
    || ko "$t : Persistent=yes manquant"
  systemctl show -p OnFailure --value "$s" | grep -q . \
    && ok "$s : OnFailure= défini" \
    || ko "$s : OnFailure=factura-alerte@%n.service attendu"
  [ "$(systemctl show -p Result --value "$s")" != failed ] \
    && ok "$s : dernier résultat non « failed »" \
    || ko "$s en échec (journalctl -u $s)"
}

check_dir() {     # check_dir <dossier> <motif> <max_fichiers>
  local d="$1" pat="$2" max="$3" last n
  S test -d "$d" || { ko "$d absent"; return; }
  last="$(S find "$d" -maxdepth 1 -name "$pat" -mmin -1560 -size +1k \
          | sort | tail -n1)"
  [ -n "$last" ] && ok "sauvegarde récente (< 26 h) : $last" \
    || ko "aucun fichier $pat de moins de 26 h et de plus de 1 Ko dans $d"
  n="$(S find "$d" -maxdepth 1 -name "$pat" | wc -l)"
  [ "$n" -le "$max" ] && ok "rotation : $n fichier(s) <= $max" \
    || ko "rotation : $n fichiers $pat, plus que $max"
  if [ -n "$last" ]; then
    if S test -f "$last.sha256"; then
      S sh -c "cd '$d' && sha256sum -c --quiet '$(basename "$last").sha256'" \
        && ok "somme de contrôle valide pour $(basename "$last")" \
        || ko "sha256 invalide pour $last"
    else
      ko "pas de $last.sha256 : chaque sauvegarde doit être signée"
    fi
  fi
}

case "$HOST" in
lab-db)
  check_timer factura-backup.timer
  U="$(systemctl show -p User --value factura-backup.service)"
  [ "$U" = postgres ] && ok "factura-backup.service tourne sous postgres" \
    || ko "factura-backup.service : User=postgres attendu (lu : « $U »)"
  check_dir /var/backups/factura 'factura-*.dump' 8
  S -u postgres psql -tAc "SELECT 1 FROM pg_database \
    WHERE datname='factura_restore'" | grep -q 1 \
    && ok "base factura_restore présente (test de restauration)" \
    || ko "base factura_restore absente : la restauration doit être testée"
  A="$(S -u postgres psql -d factura -tAc 'SELECT count(*) FROM invoices')"
  B="$(S -u postgres psql -d factura_restore -tAc \
       'SELECT count(*) FROM invoices')"
  [ -n "$B" ] && [ "$B" -ge 5 ] \
    && ok "factura_restore contient $B factures (source : $A)" \
    || ko "factura_restore vide ou sans table invoices"
  S test -f /var/lib/postgresql/.ssh/id_ed25519 \
    && ok "clé SSH de postgres présente pour le rsync" \
    || ko "pas de clé /var/lib/postgresql/.ssh/id_ed25519"
  ;;
lab-web)
  check_timer factura-backup.timer
  U="$(systemctl show -p User --value factura-backup.service)"
  [ "$U" = factura ] && ok "factura-backup.service tourne sous factura" \
    || ko "factura-backup.service : User=factura attendu (lu : « $U »)"
  check_dir /var/backups/factura 'exports-*.tar.gz' 8
  ;;
lab-ops)
  for h in lab-db lab-web; do
    D=/srv/backups/factura/$h
    S test -d "$D" && ok "$D existe" || { ko "$D absent"; continue; }
    R="$(S find "$D" -type f -mmin -1560 ! -name '*.sha256' | head -n1)"
    [ -n "$R" ] && ok "$h : copie distante de moins de 26 h" \
      || ko "$h : aucune copie de moins de 26 h dans $D (rsync ?)"
  done
  AK=/srv/backups/.ssh/authorized_keys
  if S test -f "$AK"; then
    S grep -q 'restrict' "$AK" && ok "authorized_keys de backup : restrict" \
      || ko "authorized_keys de backup sans « restrict »"
    S grep -q 'command=' "$AK" \
      && ok "authorized_keys de backup : commande forcée" \
      || ko "authorized_keys de backup sans command= (rrsync)"
    S grep -q 'from=' "$AK" && ok "authorized_keys de backup : from=" \
      || ko "authorized_keys de backup sans from=\"10.10.10.1x\""
  else
    ko "$AK absent"
  fi
  ;;
*) note "hostname $HOST hors projet" ;;
esac

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
