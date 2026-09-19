# Scripts du Workbook Linux & DevOps

À copier sur `lab-adm` dans `~/workbook/scripts/` (voir chapitre 0, §0.4) :

    scp workbook-scripts.zip mathieu@10.10.10.10:
    ssh mathieu@10.10.10.10 'mkdir -p ~/workbook && cd ~/workbook && unzip -o ~/workbook-scripts.zip'

| Dossier | Contenu | Où l'exécuter |
|---|---|---|
| `lab/` | création / reset / statut des VM, templates cloud-init, bootstrap | nœud Proxmox (`lab-*.sh`, `make-templates.sh`) puis chaque VM (`bootstrap-lab.sh`) |
| `lab/install-gitea.sh`, `backup-gitea.sh` | forge Gitea de `lab-git` : installation binaire + systemd, sauvegarde `gitea dump` (+ `gitea-backup.timer`) | `lab-git` (chapitre 0.8) |
| `setup/setup_MXX.sh` | prépare l'environnement du module XX (idempotent) | la VM indiquée en section X.1 du module |
| `check/check_MXX_YY.sh` | vérifie le lab YY du module XX | même VM, après ton travail |
| `break/break_MXX_YY.sh` | installe la panne du Break & Fix YY (`sudo`) | même VM, après un snapshot |
| `projects/P1`, `P2`, `P3` | setup, checks, breaks et sources des projets fil rouge | selon le jalon |
| `lib/` | outils internes (vérification des identifiants) | — |

Règles : snapshot Proxmox avant tout `break_*`, jamais `sudo` sur un `check_*`
(sauf indication), et un `check` vérifie le résultat, pas la méthode.
Tous les scripts sont testés par `bash -n` ; la plupart ont été exécutés
sur Ubuntu 24.04 pendant la rédaction, sauf ceux qui exigent Proxmox, Docker,
k3s, Ansible ou OpenTofu réels.
