#!/usr/bin/env bash
# break_M12_04.sh — panne BF12.4 (/etc/hosts fantôme contre le DNS)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

[ -f "$SAUV/M12_04.hosts" ] || cp -a /etc/hosts "$SAUV/M12_04.hosts"

# 10.10.10.12 : lab-db, qui existe mais ne sert rien sur le port 80 -> RST
# immédiat, donc « Connection refused ». L'entrée est volontairement
# anodine : ni commentaire, ni date, comme une ligne de test oubliee il y a
# six mois.
if ! grep -qE '^10\.10\.10\.12[[:space:]].*www\.lab\.local' /etc/hosts; then
  printf '10.10.10.12\twww.lab.local www\n' >> /etc/hosts
fi

# le cache du résolveur ne doit pas brouiller la lecture du symptôme
if [ -d /run/systemd/system ]; then
  resolvectl flush-caches >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : depuis cette machine, « curl http://www.lab.local/ »
renvoie « Connection refused ». Depuis les autres VM du lab, le même site
répond normalement. « dig +short @10.10.10.10 www.lab.local » affiche
pourtant la bonne adresse, 10.10.10.11, et « curl http://10.10.10.11/ »
fonctionne.
EOF
