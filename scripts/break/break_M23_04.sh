#!/usr/bin/env bash
# break_M23_04.sh — panne BF23.4 : « on change le vhost, nginx ne bouge pas »
# Dépose ~/lab23/casse/vhost-update.yml (réutilise le template de L23.2).
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
BASE="$LAB_HOME/lab23"
CASSE="$BASE/casse"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV" "$CASSE"

[ -f "$BASE/playbooks/templates/vitrine.conf.j2" ] \
  || echo "[warn] playbooks/templates/vitrine.conf.j2 absent : fais L23.2 d'abord"

[ -f "$CASSE/vhost-update.yml" ] \
  && cp -a "$CASSE/vhost-update.yml" "$SAUV/M23_04_vhost-update.yml"

cat > "$CASSE/vhost-update.yml" <<'EOF'
---
# vhost-update.yml — change la version annoncée par le vhost vitrine
# usage : ansible-playbook casse/vhost-update.yml -e vitrine_version=1.0.1
- name: Mise a jour du vhost vitrine
  hosts: web
  become: true
  vars:
    vitrine_version: "1.0.1"

  tasks:
    - name: Deployer le vhost
      ansible.builtin.template:
        src: ../playbooks/templates/vitrine.conf.j2
        dest: "{{ nginx_vhost_dir }}/vitrine.conf"
        owner: root
        group: root
        mode: "0644"
      changed_when: false
      notify: Reload nginx

    - name: Verifier que le vhost est bien en place
      ansible.builtin.command: grep -q X-Vitrine-Version /etc/nginx/conf.d/vitrine.conf
      changed_when: false

  handlers:
    - name: Reload nginx
      ansible.builtin.systemd_service:
        name: nginx
        state: reloaded
      when: "'ubuntu' in group_names"
EOF
chown -R "$LAB_USER":"$LAB_USER" "$CASSE"

cat <<'EOF'

Symptôme attendu (prérequis : L23.2 appliqué) :
  cd ~/lab23 && ansible-playbook casse/vhost-update.yml
se termine sans erreur sur lab-rhel et en erreur sur lab-web ; dans les deux
cas, curl -skI https://10.10.10.11/ et https://10.10.10.13/ renvoient
toujours X-Vitrine-Version: 1.0.0, alors que le fichier vitrine.conf sur les
deux hôtes contient bien 1.0.1. Objectif : trois mécanismes distincts
empêchent le handler de tourner ; corrige-les et prouve que le handler se
déclenche une fois par hôte modifié, et pas du tout quand rien ne change.
EOF
