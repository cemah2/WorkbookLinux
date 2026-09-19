# Annexes

## Annexe A — Grille de progression

### Par module

Coche les trois colonnes quand le quiz est fait (QCM + questions ouvertes),
quand tous les labs passent leur `check`, et quand le défi est livré. La
date est celle de la **dernière** case cochée. Une ligne sans date après
trois semaines est un signal, pas un détail.

| Module | Compétence clé | Quiz / Labs / Défi | Date |
|---|---|---|---|
| 01 Shell | prédire l'expansion, quoting, redirections | ☐ ☐ ☐ | |
| 02 Système de fichiers | FHS, inodes, liens, `find`, `df` vs `du` | ☐ ☐ ☐ | |
| 03 Permissions | rwx, umask, SUID/SGID/sticky, ACL, capabilities | ☐ ☐ ☐ | |
| 04 Utilisateurs et sudo | comptes, groupes, `chage`, `sudoers`, PAM | ☐ ☐ ☐ | |
| 05 Traitement de texte | pipelines, regex, `sed`, `awk`, `jq` | ☐ ☐ ☐ | |
| 06 Vim et archives | éditer vite, `tar`, `rsync`, intégrité | ☐ ☐ ☐ | |
| 07 Scripting bash | script robuste, `trap`, `getopts`, shellcheck | ☐ ☐ ☐ | |
| 08 Processus et systemd | signaux, cgroups, unité `.service` durcie | ☐ ☐ ☐ | |
| 09 Paquets | `apt`/`dpkg`, `dnf`/`rpm`, dépôts, épinglage | ☐ ☐ ☐ | |
| 10 Stockage et LVM | partitions, `fstab`, LVM à chaud, RAID, LUKS | ☐ ☐ ☐ | |
| 11 Réseau | `ip`, Netplan/`nmcli`, DNS, `ss`, `tcpdump` | ☐ ☐ ☐ | |
| 12 SSH | clés, bastion, `sshd` durci, tunnels | ☐ ☐ ☐ | |
| 13 Logs et supervision | journald, rsyslog, logrotate, métriques | ☐ ☐ ☐ | |
| 14 Planification | cron, timers, `flock`, détection d'absence | ☐ ☐ ☐ | |
| 15 Sécurité | pare-feu, fail2ban, SELinux, TLS, secrets | ☐ ☐ ☐ | |
| 16 Dépannage et incident | méthode USE, 60 secondes, post-mortem | ☐ ☐ ☐ | |
| 17 Git | branches, rebase, revue, hooks, dépôt distant | ☐ ☐ ☐ | |
| 18 Docker et Compose | image multi-étapes, réseau, volumes, registre | ☐ ☐ ☐ | |
| 19 Ansible | inventaire, rôles, idempotence, vault | ☐ ☐ ☐ | |
| 20 OpenTofu / cloud-init | VM Proxmox déclarées, état, modules | ☐ ☐ ☐ | |
| 21 CI/CD Gitea Actions | pipeline build/test/deploy, runner, secrets | ☐ ☐ ☐ | |
| 22 k3s et observabilité | déploiement, ingress, Prometheus, Loki | ☐ ☐ ☐ | |
| 23 Python pour l'ops | outils d'exploitation, API, tests, packaging | ☐ ☐ ☐ | |
| P1 Factura à la main | déployer et documenter une app 3 tiers | ☐ — ☐ | |
| P2 Factura industrialisée | la même en code : Ansible, CI, conteneurs | ☐ — ☐ | |
| P3 Semaine d'astreinte | 5 incidents, 5 post-mortem, 1 runbook | ☐ — ☐ | |

### Compétences transversales

Quatre niveaux, à évaluer honnêtement (le carnet de bord est ta preuve) :

* **D — Découverte** : je sais que ça existe et je reconnais la commande.
* **A — Autonome** : je le fais seul sur le lab, avec le `man` ouvert.
* **C — Confirmé** : je le fais en production, sous pression, et je sais
  ce qui peut mal tourner.
* **E — Expert** : je l'explique à un autre, je choisis entre plusieurs
  approches et je sais quand ne **pas** le faire.

L'objectif réaliste en fin de workbook : **A partout, C sur la moitié**.
Le niveau E vient avec les années de production, pas avec un workbook.

| Compétence | Niveau ☐D ☐A ☐C ☐E | Modules |
|---|---|---|
| Lire une commande inconnue et prédire ce qu'elle fait | ☐ ☐ ☐ ☐ | 01, 05, 07 |
| Trouver une réponse dans `man`/`--help`/`/usr/share/doc` | ☐ ☐ ☐ ☐ | 00, 01 |
| Diagnostiquer un « permission denied » de bout en bout | ☐ ☐ ☐ ☐ | 03, 04, 15 |
| Écrire une règle `sudoers` minimale et la valider | ☐ ☐ ☐ ☐ | 04 |
| Produire un rapport chiffré depuis un log brut | ☐ ☐ ☐ ☐ | 05, 13 |
| Écrire un script bash qui passe shellcheck et survit à cron | ☐ ☐ ☐ ☐ | 07, 14 |
| Savoir quand quitter bash pour Python ou Ansible | ☐ ☐ ☐ ☐ | 07, 19 |
| Lire `systemctl status` et `journalctl` sans approximation | ☐ ☐ ☐ ☐ | 08, 13 |
| Écrire et durcir une unité systemd | ☐ ☐ ☐ ☐ | 08 |
| Réparer une base de paquets cassée sans réinstaller | ☐ ☐ ☐ ☐ | 09 |
| Ajouter un dépôt tiers proprement (signature, épinglage) | ☐ ☐ ☐ ☐ | 09 |
| Agrandir un disque à chaud sans interruption | ☐ ☐ ☐ ☐ | 10 |
| Écrire une ligne `fstab` et la tester avant reboot | ☐ ☐ ☐ ☐ | 10 |
| Dérouler la checklist réseau couche par couche | ☐ ☐ ☐ ☐ | 11 |
| Lire une capture `tcpdump` (handshake, RST, retransmission) | ☐ ☐ ☐ ☐ | 11 |
| Configurer un accès SSH par bastion sans transfert d'agent | ☐ ☐ ☐ ☐ | 12 |
| Durcir `sshd` sans se verrouiller dehors | ☐ ☐ ☐ ☐ | 12 |
| Centraliser des logs et écrire une rotation | ☐ ☐ ☐ ☐ | 13 |
| Interpréter charge, `%wa`, `%st`, mémoire `available` | ☐ ☐ ☐ ☐ | 13, 16 |
| Détecter qu'une tâche planifiée n'a **pas** tourné | ☐ ☐ ☐ ☐ | 14 |
| Écrire une politique de pare-feu multi-machines | ☐ ☐ ☐ ☐ | 15 |
| Résoudre un refus SELinux sans passer en `disabled` | ☐ ☐ ☐ ☐ | 15 |
| Produire et vérifier un certificat TLS, configurer HTTPS | ☐ ☐ ☐ ☐ | 15 |
| Gérer des secrets (droits, vault, rotation, jamais en Git) | ☐ ☐ ☐ ☐ | 15, 19, 21 |
| Appliquer la méthode USE et les 60 premières secondes | ☐ ☐ ☐ ☐ | 16 |
| Remonter une machine qui ne boote plus | ☐ ☐ ☐ ☐ | 16 |
| Écrire un post-mortem blameless avec actions datées | ☐ ☐ ☐ ☐ | 16, P3 |
| Tenir un historique Git propre (commits atomiques, rebase) | ☐ ☐ ☐ ☐ | 17 |
| Construire une image Docker minimale et reproductible | ☐ ☐ ☐ ☐ | 18 |
| Écrire un rôle Ansible idempotent et testé | ☐ ☐ ☐ ☐ | 19 |
| Déclarer une infra en OpenTofu et gérer son état | ☐ ☐ ☐ ☐ | 20 |
| Concevoir un pipeline CI/CD avec étapes, secrets, rollback | ☐ ☐ ☐ ☐ | 21 |
| Déployer et exposer une application sur Kubernetes | ☐ ☐ ☐ ☐ | 22 |
| Définir des SLI/alertes utiles et lire un tableau de bord | ☐ ☐ ☐ ☐ | 13, 22 |
| Documenter pour quelqu'un d'autre (README, runbook) | ☐ ☐ ☐ ☐ | P1, P2, P3 |

---

## Annexe B — Correspondance certifications

Le workbook n'est pas un cours de certification, mais il en couvre la
majeure partie. Les listes officielles évoluent : **vérifie la version en
vigueur** sur le site de la Linux Foundation et de Red Hat avant de
t'inscrire, et utilise ce tableau pour cibler tes révisions, pas pour
remplacer le programme.

### LFCS (Linux Foundation Certified System Administrator)

Examen pratique, 2 h, distribution au choix (Ubuntu ou CentOS Stream). Les
cinq domaines et leur pondération (programme 2024-2025) :

| Domaine LFCS | Poids | Modules du workbook |
|---|---|---|
| Operations Deployment | 25 % | 08, 09, 13, 14, 16, 18, 20 |
| Networking | 25 % | 11, 12, 15 |
| Storage | 20 % | 02, 10 |
| Essential Commands | 20 % | 01, 02, 03, 05, 06, 17 |
| Users and Groups | 10 % | 04 |

Détail par domaine, avec ce qui n'est pas ou peu couvert :

* **Operations Deployment** : boot et `systemd` (08), paquets (09),
  planification (14), journaux et métriques (13), scripts (07), gestion de
  processus (08, 16), conteneurs (18) et machines virtuelles (20 pour
  Proxmox, cloud-init au chapitre 0). Le programme mentionne aussi la
  gestion des *kernel modules* et des paramètres `sysctl` : vus au passage en
  15 (modules interdits, `sysctl` de sécurité) — complète avec `man modprobe`,
  `man 5 modules-load.d` et `man 8 sysctl`.
* **Networking** : `ip`, routage, DNS, `ss` (11), SSH (12), pare-feu (15).
  Le programme cite aussi la configuration d'un reverse proxy ou d'un
  équilibreur de charge : nginx en reverse proxy est monté en P1 et 18, un
  `upstream` à plusieurs backends dans P2. Le NAT et le *port forwarding*
  côté Linux sont faits au chapitre 0 (règles `iptables` du nœud) et en 15.
* **Storage** : partitions, systèmes de fichiers, `fstab`, LVM, RAID, LUKS,
  NFS (10), quotas d'inodes et `du`/`df` (02). Les **quotas disque
  utilisateur** (`quota`, `edquota`) ne sont pas traités : `man quota` et
  le chapitre stockage de l'*Ubuntu Server Guide* suffisent en une heure.
* **Essential Commands** : tout 01 à 06, plus `git` de base (17). Le
  programme demande aussi de savoir manipuler SELinux/AppArmor en commandes
  simples (15) et de gérer les certificats (15).
* **Users and Groups** : 04 en totalité, PAM et `limits.conf` compris.
  Le programme parle d'un annuaire LDAP : abordé en 04 par `getent` et
  `nsswitch`, mais l'installation d'un client SSSD n'est pas faite — la
  documentation Red Hat « Configuring authentication and authorization »
  couvre ce cas.

### RHCSA (EX200, RHEL 9)

Examen pratique, 3 h, sur RHEL 9 : tout ce qui suit se travaille sur
`lab-rhel`, en suivant les blocs `::: rhel` des modules. Red Hat ne publie
pas de pondération ; les objectifs officiels, face aux modules :

| Objectif EX200 | Modules | Trous à combler |
|---|---|---|
| Understand and use essential tools | 01, 02, 05, 06 | — |
| Create simple shell scripts | 07 | — |
| Operate running systems | 08, 13, 14, 16 | cibles `systemctl isolate`, `tuned` |
| Configure local storage | 10 | — |
| Create and configure file systems | 10 | `autofs`, Stratis (selon version) |
| Deploy, configure, maintain systems | 09, 14, 16 | `chrony` détaillé, `kernel` args GRUB |
| Manage basic networking | 11, 15 | — (`nmcli` et `firewalld` traités) |
| Manage users and groups | 04 | — |
| Manage security | 03, 04, 12, 15 | — (SELinux traité en 15) |
| Manage containers | 18 | **`podman`** rootless, unités Quadlet |

Où trouver ce qui manque :

* **Réinitialisation du mot de passe root** au boot (`rd.break`, puis
  `chroot /sysroot`, `passwd`, `touch /.autorelabel`) : la méthode est en
  16 avec GRUB et `emergency`, mais en version Ubuntu ; refais-la sur
  `lab-rhel` avec la doc Red Hat « Recovering and restoring a system ».
* **`autofs`** : `man 5 autofs`, `man auto.master` ; monte le partage NFS du
  module 10 par `autofs` plutôt que par `fstab`.
* **`tuned`** : `tuned-adm list`, `tuned-adm profile virtual-guest`,
  10 minutes avec la doc Red Hat « Monitoring and managing system status ».
* **`podman`** : Docker (18) se transpose presque mot pour mot ; ce qui est
  spécifique à l'examen — conteneur rootless lancé comme service utilisateur
  (`podman generate systemd`, ou Quadlet en RHEL 9.4+), `loginctl
  enable-linger` — se travaille en deux heures sur `lab-rhel` avec la doc
  « Building, running, and managing containers ».
* **Arguments noyau** persistants : `grubby --update-kernel=ALL --args=...`
  sur RHEL, à la place de `/etc/default/grub` + `update-grub` d'Ubuntu.

### CKA et Terraform Associate : couverture partielle

Le workbook s'arrête volontairement avant ces deux certifications ; les
modules 20 et 22 en couvrent l'entrée, pas le programme.

| Certification | Ce que le workbook couvre | Ce qu'il ne couvre pas |
|---|---|---|
| **CKA** (Kubernetes) | 22 : déployer, exposer, stocker, observer sur k3s ; 16 : méthode de dépannage | architecture du plan de contrôle, `etcd`, RBAC, NetworkPolicy, mises à niveau, ~70 % du programme |
| **Terraform Associate (003)** | 20 : HCL, providers, état, variables, modules, `plan`/`apply` en OpenTofu | Terraform Cloud/HCP, *workspaces* distants, `import`, fonctions avancées ; syntaxe OpenTofu ≈ Terraform 1.6 |

Pour la CKA, le programme officiel (Cluster Architecture 25 %, Workloads
15 %, Services & Networking 20 %, Storage 10 %, Troubleshooting 30 %) et
`kubernetes.io/docs` sont la seule référence à suivre ; le module 22 te
met en confiance avec `kubectl`, il ne te prépare pas à l'examen.

---

## Annexe C — Parcours et carrière

### Trois profils

| Profil | Ce qu'on te demande | Modules qui pèsent le plus |
|---|---|---|
| **SRE** | fiabilité mesurée (SLI/SLO), astreinte, post-mortem, capacité, automatisation des toils | 08, 11, 13, 14, 16, 22, P3 |
| **DevOps / Platform** | chaîne de livraison, conteneurs, IaC, plateforme interne pour les devs | 07, 17, 18, 19, 20, 21, 22, P2 |
| **Ops cloud / système** | parc de VM, patching, stockage, réseau, sécurité, coût | 04, 09, 10, 11, 12, 15, 19, 20, P1 |

Les frontières sont floues et dépendent de la taille de l'entreprise : dans
une PME, un seul poste fait les trois. Le socle **système** (01 à 16) est
commun et non négociable ; c'est lui qui distingue un DevOps qui comprend ce
que son pipeline déploie de celui qui copie des YAML.

### Junior et confirmé : ce qu'on attend

**Junior (0 à 2 ans)** : tu sais faire tout le workbook au niveau *Autonome*
de l'annexe A. On attend de toi de la rigueur (snapshot, carnet, jamais
root, tests avant reboot), la capacité à suivre un runbook, à poser une
question précise avec les éléments de diagnostic déjà collectés, et à
documenter ce que tu as fait. On ne te demande pas de tout savoir ; on te
demande de savoir chercher et de ne pas casser la production en cachette.

**Confirmé (3 à 6 ans)** : niveau *Confirmé* sur la moitié de la grille.
On attend que tu conçoives (une architecture de déploiement, une politique
de sauvegarde, une stratégie de supervision), que tu mènes un incident et
son post-mortem, que tu formes un junior, que tu arbitres entre deux
solutions en tenant compte du coût et de la dette, et que tu saches dire non
à une demande dangereuse en proposant une alternative.

### Vingt questions d'entretien classiques

Sans réponse : la réponse est dans le module indiqué et, surtout, dans ce
que tu as **fait** dans ce module. Entraîne-toi à y répondre à voix haute
en deux minutes, avec un exemple concret tiré de ton carnet.

1. Que se passe-t-il, étape par étape, entre l'appui sur *Entrée* et
   l'affichage d'une page web ? (11, 12, 15)
2. Un serveur affiche une charge de 40 sur 4 cœurs. Que fais-tu dans les
   soixante premières secondes ? (13, 16)
3. `df` dit que le disque est plein, `du` ne trouve rien. Explique. (02, 16)
4. Quelle est la différence entre `kill -15` et `kill -9`, et pourquoi la
   seconde est-elle un aveu d'échec ? (08)
5. Un script marche dans ton shell mais pas dans cron. Cinq causes
   probables, dans l'ordre où tu les vérifies. (07, 14)
6. Comment agrandis-tu le disque d'une VM en production sans redémarrer ?
   (10)
7. Un utilisateur ne peut plus se connecter en SSH. Déroule ton
   diagnostic. (04, 12)
8. Explique `ProxyJump` et pourquoi tu refuses le transfert d'agent. (12)
9. Qu'est-ce qu'un zombie, faut-il s'en inquiéter, et que fais-tu d'un
   processus en état `D` ? (08, 16)
10. Comment structures-tu une politique de pare-feu sur trois machines, et
    pourquoi l'ordre des règles compte-t-il ? (15)
11. SELinux bloque ton application. Qu'est-ce qui est interdit, et que fais-tu
    à la place ? (15)
12. Un secret a été commité dans Git. Quelles sont les étapes, dans l'ordre ?
    (15, 17)
13. Quelle est la différence entre une image et un conteneur, et pourquoi ton
    Dockerfile a-t-il deux étapes ? (18)
14. Qu'est-ce que l'idempotence, et comment vérifies-tu qu'un rôle Ansible
    l'est ? (19)
15. Que contient le fichier d'état OpenTofu/Terraform, pourquoi est-il
    sensible, et comment le partages-tu en équipe ? (20)
16. Décris un pipeline de déploiement de bout en bout et où se trouve le
    rollback. (21)
17. Ton pod est en `CrashLoopBackOff`. Quelles commandes, dans quel ordre ?
    (16, 22)
18. Qu'est-ce qu'un post-mortem blameless, et que contient-il
    obligatoirement ? (16, P3)
19. Comment sais-tu qu'une sauvegarde fonctionne ? (06, 14, P1)
20. Raconte un incident que tu as géré : détection, diagnostic, correction,
    ce que tu as changé après. (P3, ton carnet)

### Le portfolio

Un recruteur technique regarde ton dépôt avant de te parler. Le workbook
t'en donne un, à condition de le rendre public et lisible :

* **Un dépôt public** (GitHub, GitLab ou Codeberg) nommé clairement, par
  exemple `devops-workbook`, avec les livrables des défis (`D07`, `D10`,
  `D15`…), les rôles Ansible et le code OpenTofu de P2, les post-mortem et
  le runbook de P3. Pas les corrigés du workbook, pas les énoncés : ton
  travail. Aucun secret, aucune IP publique réelle, aucun nom de client.
* **Un `README.md` à la racine** qui dit en dix lignes ce qu'est le dépôt,
  la topologie du lab (le schéma du chapitre 0 suffit), comment lancer
  chaque projet, et ce que tu as appris de plus dur. Un README par projet
  avec : objectif, architecture, commandes, ce qui casserait en production
  et ce que tu ferais différemment.
* **Des commits propres** (module 17) : on lit `git log --oneline` pour
  voir si tu travailles par petits pas cohérents ou par « fix » et « wip ».
* **Les post-mortem de P3**, même sur des incidents de lab : c'est le
  document qui montre le mieux comment tu raisonnes.

### Ressources reconnues

Uniquement des références qui ont fait leurs preuves ; pas de cours vidéo
inconnu, pas de site qui vend une certification.

**Références de base**

* Les pages de manuel de tes VM : `man`, `apropos`, `man 7 hier`,
  `man 5 sudoers`, `man 5 systemd.unit`. Gratuites, exactes, hors ligne.
* *The Linux Command Line*, William Shotts (linuxcommand.org, PDF libre) —
  si les modules 01 à 07 te semblent trop rapides.
* *UNIX and Linux System Administration Handbook*, 5e édition (Nemeth,
  Snyder, Hein, Whaley, Mackin) — le livre de chevet de l'administrateur,
  à lire par chapitre en parallèle des modules 08 à 16.
* *Ubuntu Server Guide* (documentation.ubuntu.com/server) et la
  documentation Red Hat pour RHEL 9 (docs.redhat.com) — les références pour
  chaque commande qui diffère entre les deux familles.
* Linux Foundation : programmes officiels LFCS et le cours libre *LFS101
  Introduction to Linux* (training.linuxfoundation.org).

**Performance, fiabilité, incident**

* Brendan Gregg : brendangregg.com — la méthode USE, la checklist des
  soixante secondes, les *flame graphs* ; et son livre *Systems Performance*,
  2e édition, pour aller loin.
* *Site Reliability Engineering* et *The Site Reliability Workbook*
  (Google, sre.google/books, lecture libre) — SLI/SLO, astreinte,
  post-mortem, gestion d'incident : la base de P3.
* Julia Evans (jvns.ca) — les *zines* sur `strace`, le réseau, les
  conteneurs, `git` ; le meilleur rapport clarté/page qui existe.

**Outils DevOps**

* Documentation Ansible (docs.ansible.com), Kubernetes (kubernetes.io/docs),
  Docker (docs.docker.com), OpenTofu (opentofu.org/docs), Gitea
  (docs.gitea.com), Prometheus (prometheus.io/docs) — toujours la doc
  officielle avant un tutoriel.
* *Pro Git*, Chacon et Straub (git-scm.com/book, libre) — chapitres 1 à 3
  et 7 pour le module 17.
* roadmap.sh/devops — pour situer ce que tu ne connais pas encore, pas pour
  l'apprendre.

**Pour s'entraîner**

* OverTheWire (overthewire.org) : *Bandit* pour le shell, *Natas* pour
  comprendre les failles web — à faire pendant les modules 01 à 07.
* sadservers.com : des serveurs cassés à réparer en temps limité ; c'est
  exactement l'esprit des Break & Fix, avec d'autres pannes.
* KodeKloud : labs interactifs payants pour Kubernetes, Ansible et Terraform,
  utiles pour la CKA après le module 22.

---

## Annexe D — Modèles

Les quatre modèles sont reproduits ici pour être copiés dans `~/carnet/`
(carnet), `~/lab16/rapports/` (post-mortem, runbook) ou le dépôt de P2
(demande de changement). Ils sont aussi installés par `setup_M16.sh` dans
`~/lab16/modeles/`.

### D.1 Carnet de bord de lab

Un fichier par module (`~/carnet/M10-stockage.md`), une entrée par séance.

```markdown
# Module 10 — Stockage et LVM — carnet

Objectif perso du module : (une phrase, avant de commencer)
Prérequis vérifiés : ☐ snapshot posé  ☐ setup lancé  ☐ check à blanc

## AAAA-MM-JJ — séance N — durée réelle
- VM utilisée(s) et snapshot posé :
- Fait : (identifiants : E10.1-E10.6, L10.1…)
- Bloqué sur : (identifiant + étape)
  - ce que j'ai cherché (man, doc, test) et combien de temps :
  - ce que j'ai trouvé / ce que le corrigé disait en plus :
- Commande ou notion à retenir (une, pas dix) :
- À revoir :
- Où j'ai trouvé la réponse (source) :
- État de fin : ☐ VM propre  ☐ rollback fait  ☐ snapshot intermédiaire
  supprimé  ☐ commit du carnet et des scripts

## Bilan du module (à la fin)
- Temps total contre temps estimé :
- Auto-évaluation X.9 remplie : ☐  Lignes « À revoir » :
- Ce que je referais autrement :
```

### D.2 Post-mortem

Même modèle que celui du module 16 (`~/lab16/modeles/postmortem.md`) :
utilise-le tel quel pour P3, sans en retirer de section.

```markdown
# Post-mortem — INC-XXXX — <titre court et factuel>

## Résumé
Une phrase compréhensible par la direction : quoi, pour qui, combien de temps.

## Impact
- Durée de l'indisponibilité : de HH:MM à HH:MM (XX min)
- Services touchés :
- Utilisateurs touchés (nombre, proportion) :
- Impact métier constaté (commandes perdues, SLA, pénalités) :

## Chronologie (heures locales, faits uniquement)
| Heure | Événement | Source |
|---|---|---|
| HH:MM | premier signal (alerte, appel client) | |
| HH:MM | prise en charge | |
| HH:MM | première hypothèse | |
| HH:MM | action corrective | |
| HH:MM | rétablissement confirmé | |

## Détection
Comment l'a-t-on su ? Alerte automatique ou utilisateur ? Délai entre le
début réel de l'incident et la détection. Ce délai est-il acceptable ?

## Cause racine
Mécanisme technique complet, en langage factuel, sans nom de personne.

### Cinq pourquoi
1. Pourquoi ... ? Parce que ...
2. Pourquoi ... ? Parce que ...
3. Pourquoi ... ? Parce que ...
4. Pourquoi ... ? Parce que ...
5. Pourquoi ... ? Parce que ...   <- cause systémique

## Ce qui a bien marché
(Oui, cette section est obligatoire.)

## Ce qui a manqué
Outils absents, documentation fausse, accès manquant, alerte inexistante.

## Facteurs aggravants
Ce qui a rallongé la résolution sans être la cause.

## Actions correctives
| # | Action | Type | Responsable | Échéance |
|---|---|---|---|---|
| 1 | | prévention | | |
| 2 | | détection | | |
| 3 | | atténuation | | |

## Annexes
Journaux, captures, liens vers les tickets et le canal de l'incident.
```

Règle blameless : ni la chronologie ni la cause racine ne nomment une
personne. Un post-mortem qui conclut par « rappel des consignes » n'a
produit aucune action corrective.

### D.3 Runbook

Un runbook répond à une alerte précise, la nuit, pour quelqu'un qui ne
connaît pas le système. Une page, pas plus ; des commandes copiables ; un
point de sortie clair.

````markdown
# Runbook — <nom de l'alerte ou du symptôme>

Dernière révision : AAAA-MM-JJ par <équipe>   Testé le : AAAA-MM-JJ

## Quand utiliser ce runbook
Alerte : <nom exact dans Prometheus/Grafana> ou symptôme rapporté : <…>
Gravité : P1 / P2 / P3   Délai de réaction attendu : <…>

## Impact si on ne fait rien
Une phrase.

## Confirmer (2 min)
```bash
# commandes qui prouvent que le symptôme est réel, avec sortie attendue
ssh lab-web 'systemctl is-active nginx; ss -tlnp | grep :443'
```
Si le symptôme n'est pas confirmé : fausse alerte probable, aller à
« Escalade » point 3.

## Causes connues et correctifs (du plus fréquent au plus rare)
1. **<cause 1>** — vérifier : `<commande>` — corriger : `<commande>` —
   vérifier après : `<commande>`
2. **<cause 2>** — …
3. **<cause 3>** — …

## Vérifier le rétablissement
```bash
curl -sSf -o /dev/null -w '%{http_code}\n' https://lab-web/
```
Attendu : `200`. Fermer l'alerte seulement après.

## Ne PAS faire
- <action tentante et dangereuse, et pourquoi>

## Escalade
1. Après 20 min sans progrès : <qui, comment>
2. Si perte de données suspectée : stopper, préserver (`cp -a` des logs),
   escalader immédiatement
3. Fausse alerte répétée : ticket d'ajustement de seuil, référence <…>

## Journal des exécutions
| Date | Cause retenue | Durée | Runbook à corriger ? |
|---|---|---|---|
````

### D.4 Demande de changement

Pour toute modification de production qui n'est pas un correctif d'incident :
mise à jour, changement de configuration, migration. En P2, chaque
déploiement hors pipeline automatique en fait l'objet.

```markdown
# Demande de changement — CHG-XXXX — <titre>

Demandeur :            Date de la demande : AAAA-MM-JJ
Exécutant :            Fenêtre proposée : AAAA-MM-JJ de HH:MM à HH:MM
Type : ☐ standard (préapprouvé)  ☐ normal  ☐ urgent
Risque : ☐ faible  ☐ moyen  ☐ élevé
Interruption de service : ☐ non  ☐ oui, XX min

## Objet et justification
Ce qu'on change, pourquoi maintenant, ce qui se passe si on ne le fait pas.

## Périmètre
Machines / services touchés :          Hors périmètre :

## Prérequis
- ☐ snapshot / sauvegarde vérifiée (commande, emplacement, date)
- ☐ testé sur le lab le AAAA-MM-JJ (référence du carnet)
- ☐ communication envoyée aux utilisateurs concernés
- ☐ fenêtre validée avec <responsable du service>

## Procédure (commandes exactes, dans l'ordre, avec durée estimée)
1. …
2. …

## Vérification de succès
Commandes et résultats attendus, observables par quelqu'un d'autre.

## Plan de retour arrière
Déclencheur (quel symptôme, quel délai) et commandes exactes.
Durée du retour arrière :         Testé : ☐ oui  ☐ non

## Approbation
Approuvé par :          Date :         ☐ approuvé  ☐ refusé  ☐ reporté

## Compte rendu d'exécution (à remplir après)
Début réel :        Fin réelle :
Résultat : ☐ succès  ☐ partiel  ☐ retour arrière
Écarts par rapport à la procédure et leçons :
```
