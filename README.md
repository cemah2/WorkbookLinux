# Workbook Linux & DevOps

Auteur : Mathieu — démarré le AAAA-MM-JJ

Un parcours de 23 modules et 3 projets fil rouge, joué sur un laboratoire
Proxmox de six VM, pour passer d'administrateur Linux intermédiaire à
DevOps opérationnel : shell, système de fichiers, permissions, systemd,
stockage, réseau, SSH, logs, sécurité, dépannage, puis Git, Docker,
Ansible, OpenTofu, CI/CD (Gitea Actions), k3s et observabilité.

Ce dépôt contient **les sources du workbook** (énoncés, corrigés, mémo,
scripts, chaîne de construction des PDF) et **mes réponses** au fil des
modules (`reponses/`). Il est hébergé sur ma forge Gitea de lab
(`lab-git`) et, pour la partie portfolio, mis en miroir sur GitHub.

## Le laboratoire

| VM | VMID / IP | Ressources | Rôle |
|---|---|---|---|
| `lab-adm` (Ubuntu 24.04) | 9001 / 10.10.10.10 | 2 vCPU, 2 Go, 20 Go | admin, bastion, Ansible |
| `lab-web` (Ubuntu 24.04) | 9002 / 10.10.10.11 | 2 vCPU, 2 Go, 20 Go | web, reverse proxy, app |
| `lab-db` (Ubuntu 24.04) | 9003 / 10.10.10.12 | 2 vCPU, 2 Go, 30 Go + 2×5 Go | base de données, LVM |
| `lab-rhel` (Rocky 9) | 9004 / 10.10.10.13 | 2 vCPU, 2 Go, 20 Go | dnf, firewalld, SELinux |
| `lab-ops` (Ubuntu 24.04) | 9005 / 10.10.10.14 | 2 vCPU, 4 Go, 40 Go | Docker, CI, monitoring |
| `lab-git` (Ubuntu 24.04) | 9006 / 10.10.10.15 | 1 vCPU, 1 Go, 15 Go | forge Gitea, ce dépôt |

Réseau isolé `10.10.10.0/24` derrière un nœud Proxmox VE 8 (bridge
`vmbr1`, NAT, bastion SSH sur `lab-adm`). Le chapitre 0 des énoncés
(`src/00-mise-en-place.md`) décrit le montage complet et les scripts de
`scripts/lab/`.

## Structure du dépôt

```text
src/                 sources Markdown (ne pas modifier)
  00-mise-en-place.md, 99-annexes.md, memo.md
  labs/MXX-slug.md        énoncés          solutions/MXX-slug.md  corrigés
scripts/             setup/ check/ break/ lab/ lib/ projects/  (+ mes/)
tex/  css/           template LaTeX, filtre pandoc, feuille de style
build.py  Makefile   construction des PDF
CONVENTIONS.md       charte de rédaction des modules
reponses/            MES réponses : reponses/MXX/<identifiant>.md
.gitea/workflows/    CI : reconstruction des PDF à chaque push sur main
```

## Construire les PDF

Sur Ubuntu 24.04 (ou WSL) :

```bash
sudo apt install -y pandoc texlive-xetex texlive-latex-extra \
  texlive-fonts-recommended fonts-dejavu python3
make pdf          # les 3 volumes dans build/
make memo         # le mémo seul
make check-ids    # chaque identifiant d'énoncé a-t-il son corrigé ?
make zip-scripts  # build/workbook-scripts.zip à copier sur les VM
```

Les PDF (`build/`) ne sont pas versionnés : ils sont reproductibles et la
CI les publie en artefact. Trois volumes : *Énoncés*, *Corrigés &
explications*, *Mémo*.

## Mes réponses

Une réponse par lab, dans `reponses/MXX/`, nommée par l'identifiant du
workbook (`L7.2.md`, `BF10.1.md`, `D15.md`, `E7.md` pour les exercices
guidés d'un module). Le modèle est `reponses/M07/L7.2.md` ; les règles
sont dans `reponses/README.md` et `CONTRIBUTING.md`. Jamais de réponse
dans `src/`, jamais de secret nulle part (`reponses/**/secrets*` est
ignoré par Git pour les notes de lab).

Commits en Conventional Commits : `feat(M07): L7.2 rotation des journaux`.

## Progression

| Semaine | Modules | État |
|---|---|---|
| 1 | 01 shell, 02 système de fichiers | à faire |
| 2 | 03 permissions, 04 utilisateurs et sudo | à faire |
| 3 | 05 traitement de texte, 06 vim et archives | à faire |
| 4 | 07 scripting bash | à faire |
| 5 | 08 processus et systemd, 09 paquets | à faire |
| 6 | 10 stockage et LVM | à faire |
| 7 | 11 réseau, 12 SSH | à faire |
| 8 | 13 logs et supervision, 14 planification | à faire |
| 9 | 15 sécurité | à faire |
| 10 | 16 dépannage et incident | à faire |
| 11 | P1 « Factura » à la main | à faire |
| 12 | 17 Git, 18 Docker et Compose | à faire |
| 13 | 19 Ansible, 20 OpenTofu / cloud-init | à faire |
| 14 | 21 CI/CD Gitea Actions, 22 k3s + observabilité | à faire |
| 15 | P2 « Factura » industrialisée | à faire |
| 16 | P3 une semaine d'astreinte | à faire |

## Licence

Les sources du workbook (`src/`, `scripts/`, `tex/`, `css/`, `build.py`,
`CONVENTIONS.md`) sont fournies pour un **usage personnel** : les lire,
les construire, les annoter, les corriger pour soi. Pas de
redistribution, pas d'usage commercial, pas de publication des corrigés
(`src/solutions/`). Si ce dépôt est rendu public en tant que portfolio,
seul `reponses/` (mon travail) et ce README ont vocation à être lus ;
publier une branche `public` sans `src/solutions/` est la façon propre
de le faire (voir le chapitre 0.9 des énoncés).

Le contenu de `reponses/` est le mien.
