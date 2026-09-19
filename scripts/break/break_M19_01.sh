#!/usr/bin/env bash
# break_M19_01.sh — panne BF19.1 : le playbook « qu'il faut lancer deux fois »
# Dépose ~/lab19/casse/prepa-deploy.yml, écrit par un collègue en congé.
# Idempotent. Sauvegarde dans /root/.breakfix-backup/.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
CASSE="$LAB_HOME/lab19/casse"
SAUV=/root/.breakfix-backup
mkdir -p "$SAUV" "$CASSE/files"

[ -f "$CASSE/prepa-deploy.yml" ] \
  && cp -a "$CASSE/prepa-deploy.yml" "$SAUV/M19_01_prepa-deploy.yml"

cat > "$CASSE/prepa-deploy.yml" <<'EOF'
---
# prepa-deploy.yml — prépare les frontaux pour l'appli vitrine (Julien)
# Testé sur mon poste, ça marche.
- name: Preparation des frontaux
  hosts: web
  become: true
  tasks:
    - name: nginx
      ansible.builtin.apt:
        name: nginx
        state: present
        update_cache: true

    - name: compte deploy
      ansible.builtin.shell: useradd -m -s /bin/bash deploy

    - name: dossier de release
      ansible.builtin.shell: mkdir /srv/deploy

    - name: droits sur le dossier
      ansible.builtin.shell: chown deploy:deploy /srv/deploy && chmod 750 /srv/deploy

    - name: sudo pour deploy
      ansible.builtin.shell: echo 'deploy ALL=(ALL) NOPASSWD: /bin/systemctl reload nginx' >> /etc/sudoers.d/deploy

    - name: page de maintenance
      ansible.builtin.copy:
        src: maintenance.html
        dest: /var/www/html/maintenance.html

    - name: redemarrer nginx
      ansible.builtin.shell: systemctl restart nginx
EOF

cat > "$CASSE/files/maintenance.html" <<'EOF'
<!doctype html>
<html><head><meta charset="utf-8"><title>Maintenance</title></head>
<body><h1>Vitrine en maintenance</h1><p>Retour dans quelques minutes.</p>
</body></html>
EOF

chown -R "$LAB_USER":"$LAB_USER" "$CASSE"

cat <<EOF

Symptôme attendu : ~/lab19/casse/prepa-deploy.yml, laissé par Julien,
« marche » selon lui. Première exécution (cd ~/lab19 &&
ansible-playbook casse/prepa-deploy.yml) : lab-rhel échoue dès la première
tâche, lab-web finit changed=7. Deuxième exécution : lab-web échoue à son
tour (useradd: user 'deploy' already exists, puis mkdir: cannot create
directory). Une fois ces deux tâches commentées, tout est changed à chaque
passage et /etc/sudoers.d/deploy s'allonge d'une ligne identique par run.
Objectif : le même playbook, même intentions, changed=0 en seconde passe
sur lab-web ET lab-rhel, nginx redémarré seulement si sa conf change.
EOF
