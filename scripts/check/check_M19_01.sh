#!/usr/bin/env bash
# check_M19_01.sh — vérifie le lab L19.1 (baseline commune du parc)
# À lancer sur lab-adm, en tant que mathieu. QUICK=1 saute la 2e exécution.
set -uo pipefail
PASS=0; FAIL=0
ok()   { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()   { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  [note] %s\n' "$1"; }
has()  { grep "$@" >/dev/null; }
echo "== Vérification L19.1 =="

export PATH="$HOME/.local/bin:$PATH"
BASE="$HOME/lab19"
cd "$BASE" 2>/dev/null || { ko "$BASE absent (setup_M19.sh)"; exit 1; }
command -v ansible >/dev/null || { ko "ansible introuvable dans le PATH"; exit 1; }
PB=playbooks/baseline.yml
[ -f "$PB" ] && ok "$PB présent" || { ko "$PB absent"; exit 1; }

# --- 1. compte de service et ansible.cfg -----------------------------------
if grep -Eq '^\s*remote_user\s*=\s*ansible\b' ansible.cfg; then
  ok "ansible.cfg : remote_user = ansible"
else ko "ansible.cfg : remote_user n'est pas ansible"; fi

if out=$(ansible all -m ansible.builtin.ping 2>&1) && \
   [ "$(printf '%s\n' "$out" | grep -c SUCCESS)" -eq 4 ]; then
  ok "ping SUCCESS sur les 4 hôtes sans -K"
else ko "ping échoue sans -K sur au moins un hôte (compte ansible, clé, sudoers ?)"; fi

# ad hoc en become, une commande sur les 4 hôtes ; renvoie 'hôte | ...'
adhoc() { ansible all -b -m ansible.builtin.shell -a "$1" -o 2>/dev/null; }

r=$(adhoc 'id -u ansible; visudo -cf /etc/sudoers.d/ansible')
[ "$(printf '%s\n' "$r" | grep -c '900.*parsed OK')" -eq 4 ] \
  && ok "uid 900 et /etc/sudoers.d/ansible valide partout" \
  || ko "uid ou sudoers.d/ansible incorrect sur un hôte (id ansible ; visudo -cf)"

# --- 2. paquets ------------------------------------------------------------
r=$(adhoc 'for p in htop vim curl tree chrony; do command -v $p; done | wc -l')
[ "$(printf '%s\n' "$r" | grep -c '| 5$')" -eq 4 ] \
  && ok "htop vim curl tree chrony présents sur les 4 hôtes" \
  || ko "il manque un paquet du tronc commun sur un hôte"

# --- 3. fuseau et chrony ---------------------------------------------------
r=$(adhoc 'timedatectl show -p Timezone --value')
[ "$(printf '%s\n' "$r" | grep -c 'Europe/Paris')" -eq 4 ] \
  && ok "fuseau Europe/Paris partout" || ko "fuseau incorrect sur un hôte"
r=$(adhoc 'systemctl is-active chrony chronyd 2>/dev/null | grep -c ^active')
[ "$(printf '%s\n' "$r" | grep -c '| 1$')" -eq 4 ] \
  && ok "chrony actif partout" || ko "chrony(d) inactif sur un hôte"

# --- 4. mises à jour automatiques -----------------------------------------
r=$(ansible ubuntu -b -m ansible.builtin.shell -o \
      -a 'grep -c "\"1\"" /etc/apt/apt.conf.d/20auto-upgrades' 2>/dev/null)
[ "$(printf '%s\n' "$r" | grep -c '| 2$')" -eq 3 ] \
  && ok "20auto-upgrades configuré sur les 3 Ubuntu" \
  || ko "20auto-upgrades incomplet sur un Ubuntu"
r=$(ansible rhel -b -m ansible.builtin.shell -o \
      -a 'grep -c "^apply_updates *= *yes" /etc/dnf/automatic.conf; \
          systemctl is-active dnf-automatic.timer' 2>/dev/null)
printf '%s\n' "$r" | has -E '1.*active' \
  && ok "dnf-automatic configuré et timer actif sur lab-rhel" \
  || ko "dnf-automatic : apply_updates ou timer manquant sur lab-rhel"

# --- 5. sshd durci ---------------------------------------------------------
r=$(adhoc 'sshd -T 2>/dev/null | grep -Ei "^(passwordauthentication|permitrootlogin|maxauthtries) "')
[ "$(printf '%s\n' "$r" | grep -ci 'passwordauthentication no')" -eq 4 ] \
  && ok "PasswordAuthentication no effectif (sshd -T) partout" \
  || ko "sshd -T ne rapporte pas passwordauthentication no sur un hôte"
[ "$(printf '%s\n' "$r" | grep -ci 'permitrootlogin no')" -eq 4 ] \
  && ok "PermitRootLogin no partout" || ko "PermitRootLogin non durci"
[ "$(printf '%s\n' "$r" | grep -ci 'maxauthtries 3')" -eq 4 ] \
  && ok "MaxAuthTries 3 partout" || ko "MaxAuthTries != 3 sur un hôte"
r=$(adhoc 'test -f /etc/ssh/sshd_config.d/50-baseline.conf && echo present')
[ "$(printf '%s\n' "$r" | grep -c present)" -eq 4 ] \
  && ok "50-baseline.conf déployé partout" || ko "50-baseline.conf absent quelque part"

# --- 6. pare-feu -----------------------------------------------------------
r=$(ansible ubuntu -b -m ansible.builtin.shell -o \
      -a 'ufw status | grep -c "^Status: active"' 2>/dev/null)
[ "$(printf '%s\n' "$r" | grep -c '| 1$')" -eq 3 ] \
  && ok "ufw actif sur les 3 Ubuntu" || ko "ufw inactif sur un Ubuntu"
r=$(ansible ubuntu -b -m ansible.builtin.shell -o \
      -a 'ufw status | grep 9100 | grep -c 10.10.10.14' 2>/dev/null)
[ "$(printf '%s\n' "$r" | grep -c '| 1$')" -eq 3 ] \
  && ok "9100/tcp limité à 10.10.10.14 (ufw)" || ko "règle ufw 9100 depuis 10.10.10.14 absente"
r=$(ansible rhel -b -m ansible.builtin.shell -o \
      -a 'firewall-cmd --list-rich-rules | grep 9100 | grep -c 10.10.10.14' 2>/dev/null)
printf '%s\n' "$r" | has '| 1$' \
  && ok "rich rule 9100 depuis 10.10.10.14 (firewalld)" \
  || ko "firewalld : rich rule 9100/10.10.10.14 absente sur lab-rhel"

# --- 7. node_exporter ------------------------------------------------------
r=$(adhoc 'curl -s localhost:9100/metrics | head -1')
[ "$(printf '%s\n' "$r" | grep -c '# HELP')" -eq 4 ] \
  && ok "node_exporter répond sur :9100 partout" \
  || ko "node_exporter ne répond pas sur un hôte (systemctl status node_exporter)"
r=$(adhoc '/usr/local/bin/node_exporter --version 2>&1 | head -1')
[ "$(printf '%s\n' "$r" | grep -c '1\.9\.1')" -eq 4 ] \
  && ok "node_exporter 1.9.1 dans /usr/local/bin" || ko "version ou chemin du binaire incorrect"
r=$(adhoc 'getent passwd node_exporter | cut -d: -f7')
[ "$(printf '%s\n' "$r" | grep -c nologin)" -eq 4 ] \
  && ok "utilisateur node_exporter sans shell" || ko "utilisateur node_exporter absent ou avec shell"

# --- 8. idempotence et lint ------------------------------------------------
if [ "${QUICK:-0}" = 1 ]; then note "QUICK=1 : seconde exécution non testée"
else
  out=$(ansible-playbook "$PB" 2>&1)
  if [ "$(printf '%s\n' "$out" | grep -c 'changed=0 .*failed=0')" -eq 4 ] && \
     printf '%s\n' "$out" | has -E 'ok=[0-9]+ .*changed=0'; then
    ok "seconde exécution : changed=0 failed=0 sur les 4 hôtes"
  else
    ko "la seconde exécution n'est pas changed=0 partout (relis le recap)"
  fi
fi
if command -v ansible-lint >/dev/null; then
  ansible-lint -q "$PB" >/dev/null 2>&1 && ok "ansible-lint muet sur $PB" \
    || ko "ansible-lint signale des problèmes sur $PB"
else note "ansible-lint absent, lint non testé"; fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
