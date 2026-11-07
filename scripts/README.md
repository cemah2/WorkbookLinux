# Scripts du Workbook Linux & DevOps

Sur chaque VM, ces scripts doivent se trouver dans `~/workbook/scripts/` :
c'est le chemin qu'utilisent les énoncés. Le plus simple est de cloner le
dépôt (voir [chapitre 0, §0.4](../docs/00-mise-en-place.md#récupérer-le-workbook-sur-les-vm)) :

```bash
git clone https://github.com/cemah2/WorkbookLinux.git ~/workbook
```

`lab/bootstrap-lab.sh` fait ce clone tout seul s'il ne trouve pas d'archive
`workbook.zip` / `workbook-scripts.zip` dans le répertoire personnel.

| Dossier | Contenu | Où l'exécuter |
|---|---|---|
| `lab/lab-deploy.sh` | déploiement automatique complet du lab (réseau, templates, 7 VM, bootstrap, Gitea, snapshots) ; `--help`, `--from`, `--dry-run` | nœud Proxmox, en root (chapitre 0.3) |
| `lab/lab-doctor.sh` | diagnostic de bout en bout : VM, snapshots, SSH, sudo, DNS, NTP, internet, disques, Gitea, scripts ; code retour 0/1 | nœud Proxmox ou `lab-adm` (chapitre 0.5) |
| `lab/` | création / reset / statut des VM, templates cloud-init, bootstrap | nœud Proxmox (`lab-*.sh`, `make-templates.sh`) puis chaque VM (`bootstrap-lab.sh`) |
| `lab/install-gitea.sh`, `backup-gitea.sh` | forge Gitea de `lab-git` : installation binaire + systemd, sauvegarde `gitea dump` (+ `gitea-backup.timer`) | `lab-git` (chapitre 0.8) |
| `setup/setup_MXX.sh` | prépare l'environnement du module XX (idempotent) | la VM indiquée en section X.1 du module |
| `check/check_MXX_YY.sh` | vérifie le lab YY du module XX | même VM, après ton travail |
| `break/break_MXX_YY.sh` | installe la panne du Break & Fix YY (`sudo`) | même VM, après un snapshot |
| `projects/P1`, `P2`, `P3` | setup, checks, breaks et sources des projets fil rouge | selon le jalon |

Règles : snapshot Proxmox avant tout `break_*`, jamais `sudo` sur un `check_*`
(sauf indication), et un `check` vérifie le résultat, pas la méthode.
Tous les scripts sont testés par `bash -n` et `shellcheck` à chaque push
(CI GitHub) ; la plupart ont été exécutés sur Ubuntu 24.04 pendant la
rédaction, sauf ceux qui exigent Proxmox, Docker, k3s, Ansible ou OpenTofu
réels (voir [docs/a-verifier.md](../docs/a-verifier.md)).
