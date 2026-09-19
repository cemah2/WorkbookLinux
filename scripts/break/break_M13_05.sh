#!/usr/bin/env bash
# break_M13_05.sh — panne BF13.5 (zone modifiée, serial non incrémenté)
# À lancer sur lab-ops (primaire BIND9), L13.4 en place. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
Z=/etc/bind/zones/db.lab.local

[ -f "$Z" ] || { echo "$Z absent : L13.4 doit être en place" >&2; exit 1; }
[ -f "$SAUV/M13_05.db.lab.local.orig" ] || cp -a "$Z" "$SAUV/M13_05.db.lab.local.orig"

# "l'équipe a ajouté monitoring.lab.local hier" — sans toucher au serial
if ! grep -qE '^monitoring[[:space:]]' "$Z"; then
  printf 'monitoring  IN  A    10.10.10.14\n' >> "$Z"
fi
named-checkzone lab.local "$Z" >/dev/null
rndc reload lab.local >/dev/null 2>&1 || systemctl reload named
# le résolveur a peut-être déjà mémorisé l'ancienne réponse : on l'efface
# pour que le "parfois" dépende du serveur interrogé, pas d'un vieux cache
unbound-control flush_zone lab.local >/dev/null 2>&1 || true

cat <<'EOF'

Symptôme attendu : dig @10.10.10.14 monitoring.lab.local répond 10.10.10.14 ;
dig @10.10.10.10 monitoring.lab.local répond NXDOMAIN ; dig @10.10.10.53
répond parfois l'un, parfois l'autre. named-checkzone est content sur le
primaire, rndc status est sain des deux côtés, aucune erreur dans les journaux
de lab-adm.
EOF
