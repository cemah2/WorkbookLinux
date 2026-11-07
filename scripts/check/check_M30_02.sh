#!/usr/bin/env bash
# check_M30_02.sh — vérifie le lab L30.2 (borg en ajout seul)
# À lancer avec sudo sur lab-db (client), puis sur lab-ops (dépôt).
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
fin()  { echo "Résultat : $PASS réussis, $FAIL échoués"; [ "$FAIL" -eq 0 ]; exit; }
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

case "$(hostname -s)" in
lab-db)
  echo "== Vérification L30.2 — lab-db =="
  command -v borg >/dev/null || { ko "borg absent (apt install borgbackup)"; fin; }
  ls /var/backups/pg/lab30-*.dump >/dev/null 2>&1 && ok "dumps locaux présents" \
                                                 || ko "aucun /var/backups/pg/lab30-*.dump"
  systemctl is-active -q pg-dump-lab30.timer 2>/dev/null && ok "timer pg-dump-lab30 actif" \
                                                         || ko "pg-dump-lab30.timer inactif"
  F=/root/.config/borg/phrase
  [ "$(stat -c '%U %a' "$F" 2>/dev/null)" = "root 600" ] && ok "phrase borg : root 0600" \
                                                        || ko "phrase borg absente ou mal protégée"
  E=/etc/borg/lab-db.env
  [ -f "$E" ] || { ko "$E absent"; fin; }
  set -a; . "$E"; set +a
  if L=$(borg list --short 2>/dev/null) && [ -n "$L" ]; then
    ok "$(wc -l <<<"$L") archive(s) dans le dépôt"
    der=$(tail -1 <<<"$L")
    borg list --short "::$der" 2>/dev/null | grep -q 'var/backups/pg/lab30-.*\.dump' \
      && ok "la dernière archive contient un dump de lab30" \
      || ko "pas de dump de lab30 dans $der"
    quand=$(borg info --json "::$der" 2>/dev/null | jq -r '.archives[0].start')
    age=$(( $(date +%s) - $(date -d "$quand" +%s) ))
    [ "$age" -le 93600 ] && ok "dernière archive il y a $((age / 3600)) h" \
                         || ko "dernière archive il y a $((age / 3600)) h"
  else
    ko "borg list échoue ou dépôt vide (après l'attaque : étape 6 faite ?)"
  fi
  ls /root/borg-cle-* >/dev/null 2>&1 \
    && ko "la clé exportée traîne encore sur lab-db : elle doit être ailleurs" \
    || ok "pas de clé exportée laissée sur lab-db"
  grep -q 'borg prune' <<<"$(systemctl cat borg-sauvegarde.service 2>/dev/null)" \
    && ok "rétention (borg prune) dans l'unité" || ko "pas de borg prune dans borg-sauvegarde.service"
  ;;
lab-ops)
  echo "== Vérification L30.2 — lab-ops =="
  A=/home/borg/.ssh/authorized_keys
  if [ -f "$A" ]; then
    grep -q 'borg serve' "$A" && ok "commande forcée borg serve" || ko "pas de command=\"borg serve …\""
    grep -q -- '--append-only' "$A" && ok "mode ajout seul imposé côté serveur" \
                                    || ko "--append-only absent de authorized_keys"
    grep -q -- '--restrict-to-path /srv/borg/lab-db' "$A" && ok "limité à /srv/borg/lab-db" \
                                                          || ko "--restrict-to-path absent"
    grep -Eq '(^|,)restrict(,| )' "$A" && ok "option restrict" || ko "option restrict absente"
  else
    ko "$A absent"
  fi
  R=/srv/borg/lab-db
  [ -f "$R/config" ] && ok "dépôt borg dans $R" || ko "pas de dépôt dans $R"
  if [ -f "$R/transactions" ]; then
    ok "journal des transactions présent ($(wc -l < "$R/transactions") transactions)"
  else
    ko "pas de fichier transactions : le dépôt n'a jamais servi en ajout seul"
  fi
  sudo -u borg borg check --repository-only "$R" >/dev/null 2>&1 \
    && ok "borg check --repository-only : dépôt sain" || ko "borg check signale un problème"
  ;;
*) echo "== Vérification L30.2 =="; ko "à lancer sur lab-db puis sur lab-ops" ;;
esac
fin
