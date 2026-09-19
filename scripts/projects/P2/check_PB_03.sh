#!/usr/bin/env bash
# check_PB_03.sh — vérifie le jalon PB.3 (baseline Ansible)
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification PB.3 =="
REPO="${REPO:-$HOME/factura-v2}"
HOSTS="${HOSTS:-10.10.10.21 10.10.10.22 10.10.10.31 10.10.10.32}"
export PATH="$HOME/.local/bin:$PATH"

[ -f "$REPO/ansible/playbooks/baseline.yml" ] \
  && ok "playbook baseline.yml présent" || ko "ansible/playbooks/baseline.yml absent"
for r in ssh_hardening firewall chrony unattended_upgrades node_exporter \
         promtail docker; do
  [ -d "$REPO/ansible/roles/$r" ] && ok "rôle $r présent" \
    || ko "rôle ansible/roles/$r manquant"
done
if command -v ansible-lint >/dev/null 2>&1; then
  (cd "$REPO" && ansible-lint -q ansible/playbooks/baseline.yml \
     >/tmp/al.log 2>&1) && ok "ansible-lint passe sur baseline.yml" \
     || ko "ansible-lint signale des problèmes (/tmp/al.log)"
fi

r() { ssh -o BatchMode=yes -o ConnectTimeout=4 "mathieu@$1" "$2" 2>/dev/null; }
for h in $HOSTS; do
  echo "-- $h"
  r "$h" true || { ko "$h injoignable en SSH"; continue; }
  r "$h" 'id deploy' | grep -q docker \
    && ok "$h : compte deploy membre de docker" \
    || ko "$h : compte deploy absent ou hors groupe docker"
  r "$h" 'sudo sshd -T' >/tmp/sshd.$$
  grep -qi '^passwordauthentication no' /tmp/sshd.$$ \
    && ok "$h : PasswordAuthentication no" \
    || ko "$h : PasswordAuthentication n'est pas à no"
  grep -qi '^permitrootlogin no' /tmp/sshd.$$ \
    && ok "$h : PermitRootLogin no" || ko "$h : PermitRootLogin n'est pas à no"
  grep -qiE '^(allowusers|allowgroups) ' /tmp/sshd.$$ \
    && ok "$h : AllowUsers/AllowGroups restreint l'accès" \
    || ko "$h : pas d'AllowUsers/AllowGroups"
  rm -f /tmp/sshd.$$
  r "$h" 'sudo ufw status' | grep -q 'Status: active' \
    && ok "$h : ufw actif" || ko "$h : ufw inactif"
  r "$h" 'sudo ufw status' | grep -qE '22/tcp.*10\.10\.10\.(10|14)' \
    && ok "$h : SSH limité à lab-adm/lab-ops" \
    || ko "$h : le port 22 n'est pas restreint aux IP d'admin"
  r "$h" 'systemctl is-active chrony' | grep -q '^active' \
    && ok "$h : chrony actif" || ko "$h : chrony inactif"
  r "$h" 'chronyc tracking' | grep -q 'Leap status *: *Normal' \
    && ok "$h : horloge synchronisée" || ko "$h : horloge non synchronisée"
  r "$h" 'test -f /etc/apt/apt.conf.d/20auto-upgrades && \
          grep -q "Unattended-Upgrade \"1\"" /etc/apt/apt.conf.d/20auto-upgrades' \
    && ok "$h : unattended-upgrades activé" \
    || ko "$h : unattended-upgrades non activé"
  r "$h" 'curl -fsS -m 3 http://127.0.0.1:9100/metrics' | grep -q node_cpu \
    && ok "$h : node_exporter répond sur 9100" \
    || ko "$h : node_exporter ne répond pas sur 9100"
  r "$h" 'curl -fsS -m 3 http://127.0.0.1:9080/ready' | grep -qi ready \
    && ok "$h : promtail prêt (9080/ready)" \
    || ko "$h : promtail ne répond pas sur 9080/ready"
  r "$h" 'docker info' | grep -q 'Server Version' \
    && ok "$h : docker installé" || ko "$h : docker absent ou non accessible"
  r "$h" 'cat /etc/docker/daemon.json' | grep -q 'lab-ops.lab.local:3000' \
    && ok "$h : registre lab-ops déclaré dans daemon.json" \
    || ko "$h : insecure-registries manquant pour lab-ops.lab.local:3000"
done
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
