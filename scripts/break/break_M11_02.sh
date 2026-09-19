#!/usr/bin/env bash
# break_M11_02.sh — panne BF11.2 (/etc/resolv.conf vers un DNS mort)
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

SAUV=/root/.breakfix-backup
mkdir -p "$SAUV"

# --- sauvegarde de la NATURE de /etc/resolv.conf ------------------------
if [ ! -f "$SAUV/M11_02.resolv.state" ]; then
  if [ -L /etc/resolv.conf ]; then
    printf 'symlink %s\n' "$(readlink /etc/resolv.conf)" \
      > "$SAUV/M11_02.resolv.state"
  else
    printf 'file\n' > "$SAUV/M11_02.resolv.state"
    cp -a /etc/resolv.conf "$SAUV/M11_02.resolv.conf"
  fi
fi

# --- on remplace le lien par un fichier réel pointant dans le vide ------
# 10.10.10.250 : adresse du réseau de lab où rien ne répond. Les paquets
# partent, personne ne répond : chaque résolution coûte le timeout plein.
rm -f /etc/resolv.conf
cat > /etc/resolv.conf <<'EOF'
# fichier statique (ne pas modifier)
nameserver 10.10.10.250
options timeout:5 attempts:2
EOF
chmod 0644 /etc/resolv.conf

# systemd-resolved reste actif : le stub écoute toujours, mais plus
# personne ne lui parle. C'est ce qui rend la panne déroutante.
if [ -d /run/systemd/system ]; then
  systemctl restart systemd-resolved >/dev/null 2>&1 || true
  resolvectl flush-caches >/dev/null 2>&1 || true
fi

cat <<'EOF'

Symptôme attendu : « curl http://10.10.10.11/ » répond instantanément,
mais « curl http://www.lab.local/ » attend une dizaine de secondes puis
échoue sur « Could not resolve host ». « apt update » est devenu
interminable. « ping 9.9.9.9 » fonctionne parfaitement.
EOF
