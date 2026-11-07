#!/usr/bin/env bash
# break_M28_03.sh — panne BF28.3 (caches SSSD allongés à 24 h)
# À lancer sur lab-web inscrit dans lab.local, avec sudo. Idempotent.
# Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
C=/etc/sssd/sssd.conf
[ -f "$C" ] || { echo "$C absent : termine L28.2 d'abord" >&2; exit 1; }
DOM=$(sed -n 's/^\[domain\/\(.*\)\]$/\1/p' "$C" | head -1)
[ -n "$DOM" ] || { echo "aucune section [domain/...] dans $C" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"
[ -f "$SAUV/M28_03.sssd.conf" ] || cp -a "$C" "$SAUV/M28_03.sssd.conf"

if ! grep -q 'OPS-1342' "$C"; then
  sed -i "/^\[domain\/$DOM\]/a\\
# optimisation perf : moins de requêtes LDAP (ticket OPS-1342)\\
entry_cache_timeout = 86400\\
ldap_sudo_smart_refresh_interval = 86400\\
ldap_sudo_full_refresh_interval = 86400" "$C"
fi
chmod 600 "$C"
systemctl restart sssd

# le cache se remplit avec l'état actuel des droits d'alice
id alice >/dev/null 2>&1 || true
sudo -l -U alice >/dev/null 2>&1 || true

if ! id -nG alice 2>/dev/null | tr ' ' '\n' | grep -qx admins-lab; then
  echo "ATTENTION : alice n'est pas (ou plus) dans admins-lab : remets-la" \
       "(ipa group-add-member admins-lab --users=alice), puis relance." >&2
fi

cat <<'EOF'

Scénario :
  1. Depuis lab-adm, ouvre une session SSH d'alice sur lab-web et garde-la
     ouverte (vérifie « sudo -v » dedans).
  2. Sur lab-rhel, en responsable sécurité :
       ipa group-remove-member admins-lab --users=alice
  3. Sur lab-web : « sudo -l -U alice » montre toujours (ALL) ALL, « id alice »
     affiche toujours admins-lab, et la session ouverte d'alice passe root.
EOF
