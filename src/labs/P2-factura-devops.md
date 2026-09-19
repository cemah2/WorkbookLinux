# Projet B — Factura v2 : industrialisation DevOps

## B.0 Présentation

::: objectif
Ce projet fil rouge reprend la plateforme Factura du projet A et la refait
**avec les outils des modules 17 à 22** : Git, Docker et Compose, Ansible,
OpenTofu, Gitea Actions, k3s et la pile Prometheus/Grafana/Loki. À la fin, tu
sais :

* tenir un mono-repo infra + application sur une forge, protégé par des
  hooks (secrets, lint) et une convention de commit ;
* provisionner un environnement complet (VM, réseau, comptes, cloud-init)
  en une commande, et en avoir deux identiques (staging, prod) sans copier
  du code ;
* décrire l'état attendu d'une machine dans des rôles Ansible idempotents,
  et prouver l'idempotence ;
* conteneuriser une application proprement (multi-stage, non-root,
  healthcheck, scan) et la déployer par Compose avec des secrets chiffrés ;
* écrire un pipeline complet : lint → tests → build → scan → push → staging
  automatique → promotion manuelle en prod, **bleu/vert**, smoke test et
  rollback automatique ;
* superviser avec des SLO et un budget d'erreur, alerter, corréler métriques
  et journaux ;
* prouver que la plateforme se **reconstruit de zéro en moins d'une heure**,
  sauvegardes restaurées comprises ;
* porter l'API sur Kubernetes (k3s) et défendre, chiffres à l'appui, le
  choix Compose ou k3s pour une PME.

Temps estimé : 30 à 40 h, sur trois à quatre semaines.
Prérequis : projet A terminé (ou au moins lu), modules 17 à 22 faits.
:::

### Le contexte

Six mois après le projet A, Factura est devenue indispensable chez Ravel &
Associés. Deux développeurs ont rejoint l'équipe et livrent des évolutions
toutes les semaines. La direction a trois exigences nouvelles :

1. **Déployer plusieurs fois par jour, sans coupure.** Aujourd'hui, une mise
   à jour c'est toi, un `scp`, un `systemctl restart`, et cinq minutes de
   « ça ne répond pas ». Ce n'est plus acceptable.
2. **Un staging identique à la prod.** Les devs testent sur leur portable.
   La dernière régression (une lib système absente) n'a été vue qu'en prod.
3. **Une reconstruction complète en moins d'une heure.** Un audit a demandé :
   « si `lab-web` et `lab-db` brûlent ce soir, vous êtes de retour quand ? ».
   Ta réponse honnête était « deux jours, si je retrouve mes notes ».

Tu as convaincu la direction que la réponse s'appelle *infrastructure as
code* et *livraison continue*. Tu as trois semaines pour le prouver. Ce
projet est le résultat.

L'application a été reprise par les devs pour la rendre « cloud-friendly » :
configuration par variables d'environnement, journaux JSON sur la sortie
standard, métriques Prometheus natives, route `/version` qui dit quelle
version et quelle couleur (bleu/vert) répond. Elle est fournie dans `app/`
du mono-repo et tu ne la modifies **pas**, sauf les `Dockerfile`, le
`compose.yaml` et la conf nginx qui sont ton territoire.

| Composant | Image | Où (par environnement) |
|---|---|---|
| nginx frontal, bleu/vert | `nginx:1.27-alpine` | VM `web` |
| API `factura-api` (Flask/Gunicorn, :8000) | construite par la CI | VM `web`, deux couleurs |
| Worker `factura-worker` (file Redis) | construite par la CI | VM `web` |
| Redis | `redis:7-alpine` | VM `web` |
| PostgreSQL 16 | `postgres:16-alpine` | VM `db` |

### Règles du jeu

* **Tout est dans le dépôt** : `~/factura-v2` sur `lab-adm`, poussé sur
  Gitea (`lab-ops`). Un fichier de configuration qui n'est pas dans Git
  n'existe pas. Les seuls fichiers hors Git : le token Proxmox, le mot de
  passe du coffre (`.vault-pass`), l'état OpenTofu (local pour ce projet)
  et les inventaires générés.
* **Rien à la main sur les VM du projet.** Tu n'ouvres une session SSH sur
  `factura-*` que pour diagnostiquer. Si tu dois corriger quelque chose, tu
  corriges le code (rôle, template, HCL) et tu rejoues. Le check de PB.5
  vérifie l'idempotence : une modification manuelle se voit.
* **`lab-ops` reste ta machine d'outillage** (Gitea, runner, registre,
  supervision, sauvegardes) : elle a été configurée aux modules 21 et 22 et
  tu la complètes par des playbooks (inventaire `ops.ini`).
* Chaque jalon a un **livrable dans le dépôt** et se valide par
  `check_PB_YY.sh` (dans `~/workbook/scripts/projects/P2/`), lancé depuis
  `lab-adm` sauf mention contraire. Le check vérifie le résultat, pas la
  méthode.
* Tu tiens `docs/journal.md` : date, jalon, ce que tu as fait, ce qui a
  coincé, temps passé. Il compte dans la note.
* Convention de commit **`type(scope): sujet`** (Conventional Commits),
  petits commits, jamais de secret dans l'historique : les hooks de PB.1 te
  le rappelleront.

### Mise en place

VM du projet : `lab-adm` (10.10.10.10, poste de travail), `lab-ops`
(10.10.10.14, outillage), et **cinq VM créées par OpenTofu** au fil des
jalons :

| VM | VMID | IP | Rôle |
|---|---|---|---|
| `factura-staging-web` | 9021 | 10.10.10.21 | nginx, API ×2, worker, Redis |
| `factura-staging-db` | 9022 | 10.10.10.22 | PostgreSQL |
| `factura-prod-web` | 9031 | 10.10.10.31 | idem, prod |
| `factura-prod-db` | 9032 | 10.10.10.32 | idem, prod |
| `factura-k3s` | 9041 | 10.10.10.41 | k3s mono-nœud (PB.10) |

Budget mémoire : 2 Go par VM (4 Go pour `factura-k3s`), soit 12 Go de plus
que le lab de base. Si ton Proxmox est juste, détruis le staging
(`tofu destroy` dans le workspace `staging`) avant PB.10 : c'est précisément
ce que l'infrastructure as code permet.

Prérequis à vérifier avant de commencer (tout vient des modules 20 à 22) :

1. **Proxmox** : template cloud-init Ubuntu 24.04 **VMID 9000** sur `vmbr1`
   (`tools/make-template.sh` le recrée), stockage `local` acceptant les
   `snippets`, un token API `tofu@pve!factura` avec les droits `VM.*`,
   `Datastore.AllocateSpace`, `Datastore.AllocateTemplate`, `SDN.Use` sur
   `/`, et une clé SSH de `mathieu@lab-adm` acceptée par `root@10.10.10.1`
   (le provider envoie les snippets par SSH).
2. **Gitea** sur `lab-ops:3000` (module 21) : compte `mathieu`, le registre
   de paquets intégré activé (`http://lab-ops.lab.local:3000/v2/`), un
   **act_runner en mode hôte** enregistré avec le label `ops-host`
   (c'est-à-dire `ops-host:host` dans `runner.labels`), lancé par une unité
   systemd sous un compte `runner` membre du groupe `docker`, avec `nodejs`,
   `ansible` (pipx), `trivy` et `jq` installés sur `lab-ops`. Ce runner
   exécute les jobs directement sur `lab-ops` : c'est ce qui lui permet de
   lancer `ansible-playbook` et `docker push` sans conteneur.
3. **Supervision** : `lab-ops` a de la place sur les ports 9090, 9093, 3001,
   3100, 9115 (Prometheus, Alertmanager, Grafana, Loki, blackbox). Gitea
   garde le 3000. Si le module 22 a laissé une pile dans
   `/opt/observabilite`, arrête-la : PB.8 en déploie une nouvelle, par
   Ansible, dans `/opt/factura-monitoring`.

```bash
# depuis le shell Proxmox : snapshots des deux VM d'outillage
qm snapshot 9001 avant-P2 ; qm snapshot 9005 avant-P2
```

Sur `lab-adm` :

```bash
sudo bash ~/workbook/scripts/projects/P2/setup_P2.sh
exit   # puis reconnecte-toi : groupe docker et ~/.local/bin
```

Le script installe l'outillage (git, pre-commit, gitleaks, shellcheck,
yamllint, ansible, ansible-lint, OpenTofu, docker, kubectl), dépose le
squelette du mono-repo dans `~/factura-v2` (avec l'application dans `app/`),
génère une clé SSH `~/.ssh/id_ed25519` si tu n'en as pas, complète
`/etc/hosts` avec les noms des cinq VM et déclare le registre de `lab-ops`
comme non sécurisé pour Docker. Il ne crée **ni VM, ni dépôt Gitea, ni
pipeline** : c'est le projet.

::: attention
OpenTofu **détruit** des VM aussi facilement qu'il les crée, et la
reconstruction de PB.9 le fait exprès. Vérifie deux fois `terraform.workspace`
avant un `apply` ou un `destroy`. Les VMID 9021–9041 sont réservés au projet
: si `tofu plan` propose de toucher un autre VMID, arrête-toi.
:::

::: astuce
Lis `app/api/app.py` et `app/worker/worker.py` en entier avant PB.4 : les
variables d'environnement, `/health`, `/version`, `/metrics`, le format des
journaux et le nom de la file Redis sont tout ce dont tes rôles, ton pipeline
et tes alertes auront besoin. Les devs ont mis les réponses dans l'en-tête.
:::

---

## B.1 Architecture cible

```
   lab-adm 10.10.10.10                        lab-ops 10.10.10.14
   ┌───────────────────┐   git push   ┌─────────────────────────────────┐
   │ ~/factura-v2      │─────────────►│ Gitea :3000  ─┬─ dépôt factura  │
   │ tofu · ansible    │              │               └─ registre /v2   │
   │ vault · kubectl   │              │ act_runner (hôte, label ops-host)│
   └────────┬──────────┘              │   lint → test → build → scan    │
            │ tofu apply              │   → push → deploy staging        │
            ▼                         │   → (manuel) promotion prod      │
   Proxmox 10.10.10.1:8006            │ Prometheus :9090  Alertmanager   │
   template 9000 + snippets           │ Grafana :3001     Loki :3100     │
            │ clone + cloud-init      │ /srv/backups/factura/{staging,prod}│
            ▼                         └───────┬──────────────┬──────────┘
   ┌────────────────────────┐  ansible-playbook│ ssh deploy   │ scrape / push
   │ factura-staging-web .21│◄─────────────────┘              │
   │  nginx :80 ──► api-blue :8000  (couleur active)          │
   │          └──► api-green:8000  (couleur inactive)         │
   │  :8081 → blue  :8082 → green   (tests directs)           │
   │  worker  redis  redis_exporter :9121  node_exporter :9100│
   │  promtail ──────────────────────────────────────────────►│ Loki
   ├────────────────────────┤                                 │
   │ factura-staging-db  .22│  postgres :5432 (web seulement) │
   │  postgres_exporter :9187  node_exporter  promtail        │
   │  factura-backup.timer 02:30 ──── rsync ──► lab-ops       │
   └────────────────────────┘                                 │
   ┌────────────────────────┐  même code, autre workspace     │
   │ factura-prod-web    .31│  (promotion manuelle)           │
   │ factura-prod-db     .32│                                 │
   └────────────────────────┘                                 │
   ┌────────────────────────┐  PB.10                          │
   │ factura-k3s         .41│  k3s : api ×2 + HPA, Ingress TLS│
   └────────────────────────┘  https://factura-k3s.lab.local  │
```

### Flux autorisés (tout le reste est fermé par ufw)

| Source | Destination | Port | Usage |
|---|---|---|---|
| lab-adm, lab-ops | factura-* | 22 | Ansible (admin et runner CI) |
| 10.10.10.0/24 | web | 80 | application |
| lab-adm, lab-ops | web | 8081, 8082 | tests directs bleu/vert |
| web | db (même env) | 5432 | PostgreSQL |
| lab-ops | web, db, k3s | 9100, 9121, 9187, 9200 | exporters |
| web, db, k3s | lab-ops | 3100 | promtail → Loki |
| web, db | lab-ops | 3000 | pull d'images |
| db | lab-ops | 22 | rsync des sauvegardes (compte `backup`) |
| 10.10.10.0/24 | k3s | 443 | Ingress TLS |
| lab-adm | k3s | 6443 | kubectl |

### Le mono-repo

```
factura-v2/
  app/            api/, worker/, nginx/, sql/, compose.yaml (dev)
  infra/          OpenTofu : *.tf, templates/, envs/*.tfvars
  infra/monitoring/   compose + configs Prometheus, Alertmanager,
                      Grafana, Loki, blackbox (déployés sur lab-ops)
  ansible/        inventory/ (généré + group_vars), roles/, playbooks/
  .gitea/workflows/   ci.yaml, cd-prod.yaml, restore-test.yaml
  k8s/            manifestes k3s
  docs/           journal, runbook, SLO, rapports
  tools/          smoke.sh, rebuild.sh, make-template.sh
  Makefile, .pre-commit-config.yaml, .gitleaks.toml, .yamllint, ...
```

### Comptes et secrets

| Quoi | Où | Qui l'utilise |
|---|---|---|
| `mathieu` + clé ed25519 | toutes les VM (cloud-init) | toi, Ansible admin |
| `deploy` (groupe docker, sans sudo) | VM factura-* (PB.3) | le runner CI |
| `backup` (rrsync) | lab-ops (PB.9) | timers de sauvegarde |
| token Proxmox `tofu@pve!factura` | `TF_VAR_pve_api_token` sur lab-adm | OpenTofu |
| `.vault-pass` (0600, hors Git) | lab-adm ; secret `VAULT_PASS` sur Gitea | Ansible |
| token Gitea « packages » | secrets `REGISTRY_USER/TOKEN` sur Gitea | CI |
| mots de passe PostgreSQL, Redis, Grafana | `group_vars/<env>/vault.yml` | tout, via le vault |

---

## B.2 Jalons

Chaque jalon : contexte, objectif, cahier des charges (chaque puce est
vérifiable), modules mobilisés, indices, livrable, critère de réussite. Dans
l'ordre : chaque check suppose les précédents.

### **PB.1** — Mono-repo sur Gitea, hooks et convention

::: contexte
Deux devs, toi, et bientôt un prestataire : il faut un seul endroit où vit
tout ce qui décrit la plateforme. Le squelette est dans `~/factura-v2`. Tu
en fais un dépôt Git protégé : un secret commité ne passe pas, un script
Bash cassé ne passe pas, un YAML mal indenté ne passe pas.
:::

**Objectif** : `~/factura-v2` versionné, poussé sur Gitea, avec des hooks
`pre-commit` qui bloquent secrets et fautes de lint, et une convention de
commit appliquée par un hook.

**Cahier des charges**

* Dépôt `mathieu/factura` sur Gitea (`http://lab-ops.lab.local:3000`),
  privé, créé par l'API ou l'interface ; `origin` en SSH ou HTTP, `main`
  poussée. Branche `main` protégée : pas de push forcé, statut CI requis
  (tu l'activeras vraiment en PB.6).
* `.pre-commit-config.yaml` avec au minimum : `gitleaks` (config
  `.gitleaks.toml` fournie), `shellcheck` (sur `tools/*.sh` et les scripts
  des rôles), `yamllint` (config `.yamllint` fournie), `ansible-lint`
  (config `.ansible-lint` fournie), plus les hooks de base
  (`end-of-file-fixer`, `trailing-whitespace`, `check-merge-conflict`,
  `check-added-large-files`). Hooks installés (`pre-commit install`) **et**
  un hook `commit-msg` qui refuse tout message hors
  `type(scope): sujet` avec `type` dans `feat fix chore docs ci infra
  refactor test`.
* `pre-commit run --all-files` passe sur le dépôt entier.
* Preuve : un commit contenant `pve_api_token = "tofu@pve!factura=..."`
  (un faux, 36 caractères hexadécimaux au bon format) est **refusé** par
  le hook ; un message `update stuff` est refusé ; le journal en garde la
  trace.
* Au moins 5 commits atomiques (squelette, hooks, docs, ...), aucun
  `tfstate`, `terraform.tfvars` ou `.vault-pass` versionné (regarde le
  `.gitignore` fourni et complète-le si besoin).
* `docs/journal.md` commencé, `README.md` à jour (qui fait quoi, comment
  lancer les checks).

**Modules mobilisés** : 17 (Git, hooks, conventions, forge), 07 (scripts).

**Indices**

* `pre-commit install --hook-type pre-commit --hook-type commit-msg`.
  Pour le message de commit, un hook `local` avec `language: script` ou
  `pygrep` suffit : pas besoin de commitlint et de Node.
* `gitleaks detect --no-banner -v` analyse tout l'historique ; `gitleaks
  protect --staged` ce qui est en cours de commit. Si un secret est déjà
  passé dans l'historique, le hook ne le fera pas disparaître : il faut
  réécrire l'historique (`git filter-repo`) ou repartir d'un dépôt propre —
  et **révoquer le secret**, dans tous les cas.
* `ansible-lint` sur un dépôt sans playbook passe trivialement ; il commence
  à mordre en PB.3. Garde le profil `production` du `.ansible-lint`.
* Créer le dépôt par l'API :
  `curl -u mathieu -X POST $GITEA/api/v1/user/repos -d '{"name":"factura",
  "private":true}'`.

**Livrable** : le dépôt sur Gitea, `.pre-commit-config.yaml`, le hook de
message de commit (dans `tools/` ou en ligne dans la config), `README.md`,
`docs/journal.md`.

::: check
Critère de réussite : `check_PB_01.sh` passe sur `lab-adm`.

```bash
bash ~/workbook/scripts/projects/P2/check_PB_01.sh
```
:::

---

### **PB.2** — OpenTofu, cloud-init, deux environnements identiques

::: contexte
Staging et prod doivent être **le même code**. Tu écris une configuration
OpenTofu qui crée les VM `web` et `db` d'un environnement à partir du
template cloud-init, et tu l'appliques deux fois : une par *workspace*. Elle
génère aussi l'inventaire Ansible, pour que la suite du projet ne dépende
jamais d'une IP tapée à la main.
:::

**Objectif** : `tofu apply` dans le workspace `staging` crée
`factura-staging-web` et `factura-staging-db` joignables en SSH par clé ;
même chose pour `prod` ; l'inventaire `ansible/inventory/<env>.ini` est
généré par OpenTofu ; `tofu plan` est vide après apply.

**Cahier des charges**

* `infra/` : `versions.tf` (OpenTofu ≥ 1.6, provider `bpg/proxmox`),
  `providers.tf` (endpoint `https://10.10.10.1:8006`, `insecure = true`,
  token via `var.pve_api_token` **sensible**, jamais en dur, SSH vers le
  nœud pour les snippets), `variables.tf` (une `map(object)` `vms` avec
  `vm_id`, `host` (dernier octet), `cores`, `memory`, `disk`, `name`
  optionnels, validés : `vm_id` entre 9021 et 9049, `host` entre 20 et 49),
  `main.tf` (`proxmox_virtual_environment_vm` en **`for_each`** sur
  `var.vms`, clone du template 9000, agent QEMU, IP statique
  `10.10.10.<host>/24`, passerelle `10.10.10.1`, DNS `10.10.10.1`, disque
  redimensionné), `cloud-init.tf` (un snippet `user-data` par VM via
  `proxmox_virtual_environment_file`, rendu depuis
  `templates/user-data.yaml.tftpl`), `inventory.tf` (`local_file` qui
  écrit `../ansible/inventory/${terraform.workspace}.ini` depuis
  `templates/inventory.ini.tftpl`), `outputs.tf` (map nom → IP).
* Le nom des VM est dérivé du workspace :
  `factura-${terraform.workspace}-${clé}` (surchargé par `name` pour la
  VM k3s, plus tard). Le workspace `default` ne doit rien pouvoir créer
  (une `precondition` ou une validation qui refuse `default`).
* `envs/staging.tfvars` : `web` (9021, hôte 21), `db` (9022, hôte 22,
  disque 30 Go). `envs/prod.tfvars` : `web` (9031, 31), `db` (9032, 32,
  30 Go). Rien d'autre ne diffère entre les deux fichiers.
* Le user-data cloud-init : hostname = nom de la VM, utilisateur `mathieu`
  avec ta clé publique et sudo sans mot de passe, `qemu-guest-agent`
  installé et démarré, `PasswordAuthentication no`, fuseau `Europe/Paris`,
  `package_update`, et **rien d'autre** : tout le reste est du ressort
  d'Ansible (PB.3). Pas de `package_upgrade` (il rallonge le boot de
  plusieurs minutes et casse le chronomètre de PB.9).
* L'inventaire généré contient les groupes `<env>_web`, `<env>_db`, les
  groupes parents `web`, `db` et `<env>` (pour les `group_vars`), les
  `ansible_host`, et `ansible_user=mathieu`. Pas de `ansible_become`
  global (le runner CI se connectera en `deploy`, sans sudo).
* Workspaces `staging` et `prod` créés, appliqués ; `tofu plan
  -detailed-exitcode` renvoie 0 dans chacun. `default` est vide.
* Le token n'apparaît ni dans les `.tf`, ni dans les `.tfvars` versionnés,
  ni dans un output. Il vient de `TF_VAR_pve_api_token` (mets-le dans
  `~/.config/factura/pve.env`, mode 0600, et `source`-le).
* Preuve de « même code » : `diff envs/staging.tfvars envs/prod.tfvars` ne
  montre que des VMID, des IP et des noms.

**Modules mobilisés** : 20 (bpg/proxmox, cloud-init, `for_each`,
workspaces, `templatefile`, `local_file`), 12 (SSH, clés), 11 (IP).

**Indices**

* Le provider a besoin de `provider "proxmox" { ssh { agent = true
  username = "root" } }` pour envoyer les snippets sur le nœud ; lance
  `eval $(ssh-agent) && ssh-add` avant `tofu apply`. Si l'agent te gêne,
  `private_key = file("~/.ssh/id_ed25519")` marche aussi.
* Un snippet est un fichier `local:snippets/<nom>.yaml` ; `file_name` doit
  être unique par VM, sinon les deux VM partagent le même user-data (même
  hostname !).
* `initialization { user_data_file_id = ... }` **remplace** `user_account`
  et `ip_config` ? Non : `ip_config` reste pris en compte via le lecteur
  cloud-init (network-config), le user-data personnalisé ne porte que la
  partie utilisateurs/paquets. Vérifie sur la VM avec
  `cloud-init status --long` et `cat /var/lib/cloud/instance/user-data.txt`.
* `agent { enabled = true }` : sans l'agent QEMU, le provider attend l'IP
  jusqu'au timeout. Le template 9000 l'active déjà ; ton user-data doit
  installer le paquet.
* Un `tofu plan` non vide après apply, c'est presque toujours un attribut
  que Proxmox normalise (taille de disque, `network_device.mac_address`,
  `cpu.type`). `lifecycle { ignore_changes = [...] }` pour ceux-là, en
  expliquant chacun dans le journal.

**Livrable** : `infra/*.tf`, `infra/templates/*.tftpl`, `infra/envs/*.tfvars`,
et dans le journal : le temps d'un `apply` complet du staging (il servira de
référence en PB.9).

::: check
Critère de réussite : `check_PB_02.sh` passe sur `lab-adm` (il lit l'état
des deux workspaces et se connecte aux quatre VM).

```bash
bash ~/workbook/scripts/projects/P2/check_PB_02.sh
```
:::

---

### **PB.3** — Baseline Ansible

::: contexte
Au projet A, tu as fait à la main sur chaque VM : comptes, SSH durci, ufw,
NTP, mises à jour automatiques, `node_exporter`. Tu as les fichiers dans
`~/P1/conf/`. Tu les transformes en rôles Ansible, appliqués aux quatre VM
en une commande, rejouables sans effet la seconde fois.
:::

**Objectif** : `ansible-playbook ansible/playbooks/baseline.yml` amène toute
VM fraîchement créée par PB.2 à l'état « prête à recevoir l'application »,
et `changed=0` au second passage.

**Cahier des charges**

* Rôles dans `ansible/roles/`, chacun avec `defaults/main.yml`,
  `tasks/main.yml`, `handlers/main.yml` si besoin, `templates/` :
  * `common` : paquets utiles (`curl jq rsync ca-certificates`), `/etc/hosts`
    avec `lab-ops`, `lab-adm` et les VM de l'environnement, compte
    **`deploy`** (uid fixe, shell bash, membre de `docker`, **sans sudo**,
    clé publique du runner CI dans `authorized_keys`), `journald` persistant
    borné (comme en PA.6) ;
  * `ssh_hardening` : fragment `/etc/ssh/sshd_config.d/50-factura.conf` :
    `PasswordAuthentication no`, `PermitRootLogin no`, `X11Forwarding no`,
    `MaxAuthTries 3`, `AllowUsers mathieu deploy`, validé par `sshd -t`
    **avant** le handler de restart (un `validate:` sur le template) ;
  * `firewall` : ufw deny entrant par défaut, règles décrites dans une
    variable de groupe (`firewall_rules` : port, source, commentaire), 22
    depuis 10.10.10.10 et 10.10.10.14, puis les ports du tableau de B.1 selon
    le groupe (`web`, `db`) ; et les ports **publiés par Docker**
    (5432, 8081, 8082, 9121, 9187, 9200) filtrés dans la chaîne
    `DOCKER-USER` via `/etc/ufw/after.rules` — parce que Docker contourne
    ufw, teste-le avant de me croire ;
  * `chrony` : serveur `10.10.10.1` ou un pool public, `chronyc tracking`
    en `Normal` ;
  * `unattended_upgrades` : sécurité seulement, pas de reboot automatique,
    `20auto-upgrades` activé ;
  * `node_exporter` : paquet `prometheus-node-exporter`, actif, port 9100
    ouvert pour 10.10.10.14 seulement, répertoire du *textfile collector*
    accessible en écriture au groupe `deploy` (PB.9 s'en servira) ;
  * `promtail` : binaire Grafana Promtail (version épinglée dans
    `defaults`), unité systemd durcie, utilisateur `promtail` dans
    `systemd-journal` et `docker`, config qui lit le journal systemd
    **et** les conteneurs Docker (`docker_sd_configs`) avec les labels
    `host`, `env`, `container`, envoi vers `http://10.10.10.14:3100`,
    `/ready` sur 9080 ;
  * `docker` : `docker.io` + `docker-compose-v2` (paquets Ubuntu),
    `/etc/docker/daemon.json` avec `insecure-registries` pour
    `lab-ops.lab.local:3000`, `log-driver json-file` borné, `live-restore`.
* `ansible/playbooks/baseline.yml` : un play sur `all` avec les rôles dans
  cet ordre ; `become: true` ; `ansible-lint` (profil `production`) passe.
* Variables par groupe dans `ansible/inventory/group_vars/{all,web,db}/`,
  **pas** dans les rôles. Le rôle `firewall` ne connaît aucun port :
  il applique une liste.
* Idempotence prouvée : second passage `changed=0` sur les quatre VM, et
  `--check --diff` ne propose rien.
* Tests : depuis `lab-adm`, `ssh deploy@10.10.10.21 docker ps` marche ;
  `ssh deploy@10.10.10.21 sudo true` échoue ; `nc -zv 10.10.10.22 5432`
  depuis `lab-adm` échoue même quand PostgreSQL tournera (PB.5).

**Modules mobilisés** : 19 (rôles, handlers, templates, `group_vars`,
idempotence, `validate`), 12, 13, 14, 15 (ce que les rôles reproduisent).

**Indices**

* `ansible-galaxy collection install -r ansible/requirements.yml` d'abord
  (`community.general` pour `ufw`, `community.docker`, `ansible.posix`).
* Docker et ufw : Docker insère ses règles dans `FORWARD` via la chaîne
  `DOCKER-USER`, évaluée **avant** les chaînes ufw. Un port publié est
  ouvert au monde tant que `DOCKER-USER` ne dit rien. Le pattern : dans
  `/etc/ufw/after.rules`, un bloc `*filter` qui déclare `:DOCKER-USER -
  [0:0]`, accepte `RELATED,ESTABLISHED`, accepte les couples (port, source)
  de ta liste, puis `DROP` ce qui arrive de l'extérieur sur les ports
  publiés, et `RETURN`. Publier les ports sur l'IP de la VM
  (`10.10.10.22:5432:5432`) plutôt que `0.0.0.0` est un plus, pas un
  substitut.
* Promtail (déclaré en fin de vie au profit d'Alloy, mais encore livré et
  suffisant ici) : `journal` scrape avec `json: false` et `relabel` sur
  `__journal__systemd_unit` ; `docker_sd_configs` avec `host:
  unix:///var/run/docker.sock` et un relabel de
  `__meta_docker_container_name`. Le module 22 a la variante Alloy.
* `unattended-upgrades` : le paquet est installé par défaut sur Ubuntu
  Server ; c'est `/etc/apt/apt.conf.d/20auto-upgrades` qui l'active.
* Quand un rôle n'est pas idempotent, c'est presque toujours un `command`
  sans `creates:`/`changed_when:`, ou un template avec une date/un
  aléatoire dedans.

**Livrable** : `ansible/roles/{common,ssh_hardening,firewall,chrony,
unattended_upgrades,node_exporter,promtail,docker}`, `baseline.yml`,
`group_vars/{all,web,db}/main.yml`, et dans le journal la sortie
`PLAY RECAP` du second passage.

::: check
Critère de réussite : `check_PB_03.sh` passe sur `lab-adm` (il interroge les
quatre VM).

```bash
bash ~/workbook/scripts/projects/P2/check_PB_03.sh
```
:::

---

### **PB.4** — Conteneurisation et stack Compose de dev

::: contexte
Les devs ont écrit un `Dockerfile` « qui marche » : `FROM python`, `COPY .`,
`pip install`, root, 1,1 Go. Tu le reprends : image minimale, non-root,
healthcheck, version injectée au build, scan de vulnérabilités. Puis un
`compose.yaml` pour qu'un dev lance toute la stack en une commande sur son
poste — c'est aussi ce que la CI utilisera.
:::

**Objectif** : `docker build` produit des images `factura-api` et
`factura-worker` de moins de 250 Mo, non-root, avec healthcheck, dont
`/version` renvoie la version passée au build ; `docker compose up -d`
dans `app/` donne une stack complète fonctionnelle ; `trivy` ne trouve
aucune vulnérabilité HIGH/CRITICAL corrigeable.

**Cahier des charges**

* `app/api/Dockerfile` et `app/worker/Dockerfile` : **multi-stage** (un
  étage `builder` qui construit un venv, un étage `runtime` sur
  `python:3.12-slim` qui ne contient ni pip cache, ni compilateur, ni
  tests), `ARG APP_VERSION` propagé en `ENV`, utilisateur `app` (uid 10001)
  créé et **`USER app`**, `HEALTHCHECK` qui interroge `/version` (API) ou
  le port de métriques (worker), `CMD` en forme exec (JSON) — Gunicorn
  doit recevoir `SIGTERM`, pas un `sh` intermédiaire ; `.dockerignore`
  excluant `tests/`, caches et `.git`. Le squelette en fournit une version
  : relis-la ligne à ligne, corrige ce qui manque, et **justifie chaque
  ligne dans le journal** (tu seras interrogé dessus).
* `docker build --build-arg APP_VERSION=dev -t factura-api:dev app/api`
  puis `docker run --rm -p 8000:8000 -e DATABASE_URL=x factura-api:dev`
  → `curl :8000/version` renvoie `"version":"dev"`. L'image tourne en
  `app`, pèse moins de 250 Mo, `docker inspect` montre le healthcheck.
* `app/compose.yaml` (dev) : services `nginx` (port 8080 publié), `api`,
  `worker`, `postgres` (volume nommé, `init.sql` monté dans
  `docker-entrypoint-initdb.d`, **healthcheck `pg_isready`**), `redis` ;
  `depends_on` avec `condition: service_healthy` sur postgres ; **aucun**
  port publié pour postgres et redis ; mot de passe via `${DB_PASSWORD}`
  avec une valeur de dev par défaut ; `APP_VERSION` passé en `args`.
* `docker compose up -d --build` puis `curl :8080/health` → `ok`, `POST
  /api/factures` → 201, le worker journalise « facture traitée ». `docker
  compose down -v` puis `up` : la base est ré-initialisée par `init.sql`
  (5 factures de démo).
* `trivy image --severity HIGH,CRITICAL --ignore-unfixed factura-api:dev`
  : rapport sauvé dans `docs/scan-api.txt` (et `scan-worker.txt`). S'il
  reste des HIGH corrigeables, corrige (mise à jour de base ou de
  dépendance) et rescanne. Les non corrigeables (`--ignore-unfixed`) sont
  listés dans le journal avec une phrase chacun.
* `pytest` passe dans un conteneur jetable :
  `docker run --rm -v $PWD/app/api:/src -w /src python:3.12-slim sh -c
  "pip install -q -r requirements-dev.txt && pytest -q"`.
* Journaux : `docker compose logs api` montre du JSON, une ligne par
  requête (Gunicorn en `--access-logfile -`).

**Modules mobilisés** : 18 (Dockerfile, multi-stage, Compose, healthchecks,
volumes, réseaux), 15 (scan, non-root).

**Indices**

* `docker history factura-api:dev` montre le poids de chaque couche ;
  `dive` si tu l'as. La couche `pip install` doit être dans `builder`,
  pas dans `runtime`.
* `HEALTHCHECK` ne peut pas utiliser `curl` s'il n'est pas dans l'image ;
  `python -c "import urllib.request; ..."` est là de toute façon.
* Le `--start-period` du healthcheck de l'API compte : Gunicorn met 2 à 3 s
  à écouter. Sans lui, `depends_on: condition: service_healthy` fait
  attendre nginx pour rien.
* `docker compose config` montre le fichier interpolé : c'est ce que tu
  dois lire quand « ça ne prend pas ma variable ».

**Livrable** : les deux `Dockerfile`, `.dockerignore`, `app/compose.yaml`,
`app/nginx/dev.conf`, `docs/scan-api.txt`, `docs/scan-worker.txt`, et dans
le journal la justification ligne à ligne du `Dockerfile` de l'API.

::: check
Critère de réussite : `check_PB_04.sh` passe sur `lab-adm` avec la stack de
dev démarrée (`cd ~/factura-v2/app && docker compose up -d`).

```bash
bash ~/workbook/scripts/projects/P2/check_PB_04.sh
```
:::

---

### **PB.5** — Rôle de déploiement Compose, secrets chiffrés, staging puis prod

::: contexte
Tu as des VM prêtes (PB.3) et des images (PB.4). Reste à les marier : un
rôle Ansible qui dépose la stack Compose sur les VM `web` et `db` d'un
environnement, avec les secrets sortis d'un coffre `ansible-vault`, et qui
prépare déjà le bleu/vert de PB.7 (deux services API, une couleur active).
Ce rôle sera exécuté par le runner CI en tant que `deploy` : il ne doit
jamais avoir besoin de `sudo`.
:::

**Objectif** : `ansible-playbook ansible/playbooks/deploy.yml -i
ansible/inventory/staging.ini -e factura_image_tag=<tag>` déploie ou met à
jour Factura sur le staging ; même commande avec `prod.ini` pour la prod ;
idempotent ; aucun secret en clair dans Git.

**Cahier des charges**

* Rôle `ansible/roles/factura_compose` : variables par défaut (`registry`,
  `registry_namespace`, `factura_image_tag` **vide par défaut**,
  `factura_base_dir: /srv/factura`, ports), tâches en deux parties selon le
  groupe (`web` / `db`), templates `compose-web.yaml.j2`,
  `compose-db.yaml.j2`, `env.j2`, `nginx/factura.conf.j2`,
  `nginx/active.conf.j2`, `switch.sh.j2`.
* Sur `web` : `/srv/factura/` (propriétaire `deploy`), `compose.yaml`,
  `.env` (**0600**, contient `DB_PASSWORD`, `REDIS_PASSWORD`, `DATABASE_URL`
  etc.), `state.env` (`ACTIVE=blue`, `TAG_BLUE=`, `TAG_GREEN=`,
  `TAG_WORKER=`), `nginx/factura.conf` (port 80 : `/` vers l'upstream
  actif ; 8081 → `api-blue`, 8082 → `api-green`, pour les tests directs et
  le scrape des métriques), `nginx/active.conf` (`upstream factura_api {
  server api-blue:8000; }`), `bin/switch.sh <blue|green> [raison]` qui
  réécrit `active.conf`, recharge nginx (`nginx -s reload` dans le
  conteneur, sans redémarrage), met à jour `ACTIVE=` et ajoute une ligne
  horodatée dans `/srv/factura/switch.log`. Services : `nginx`,
  `api-blue`, `api-green` (`APP_COLOR` respectif), `worker`, `redis`
  (avec `requirepass`), `redis_exporter` (`--check-single-keys
  factura:jobs`, port 9121 publié sur l'IP de la VM), worker port 9200
  publié sur l'IP de la VM. Au premier déploiement, une seule couleur
  démarre (`blue`), avec le tag demandé.
* Sur `db` : `postgres` (volume nommé, `init.sql`, healthcheck, port 5432
  publié **sur l'IP de la VM seulement**), `postgres_exporter` (9187).
* Le rôle refuse de tourner si `factura_image_tag` est vide **et** qu'aucun
  `state.env` n'existe (« premier déploiement : tag requis »). Si le tag est
  vide et que `state.env` existe, le rôle ne change rien aux images
  (c'est ce qui rend `--check` idempotent en CI).
* Secrets : `ansible/inventory/group_vars/<env>/vault.yml` chiffré par
  `ansible-vault` (`.vault-pass` en 0600 hors Git, déclaré dans
  `ansible.cfg`), variables `vault_db_password`, `vault_redis_password`,
  `vault_registry_token` ; `group_vars/<env>/main.yml` **en clair** fait
  l'indirection `db_password: "{{ vault_db_password }}"`. Staging et prod
  ont des mots de passe **différents**. `ansible-vault view` marche,
  `git show HEAD:...vault.yml` montre `$ANSIBLE_VAULT;1.1;AES256`.
* Pull d'images : `docker login` sur le registre avec le token du vault
  (`community.docker.docker_login`) en tant que `deploy`.
* `deploy.yml` : play `db` puis play `web` (l'API a besoin de la base),
  sans `become`, `serial: 1`. Le rôle fait un `wait_for` sur
  `/health` = 200 de la couleur déployée avant de rendre la main.
* Déploiement du staging avec `factura_image_tag=dev-<sha court>` (image
  construite et poussée à la main depuis `lab-adm` : `docker tag`,
  `docker push lab-ops.lab.local:3000/mathieu/factura-api:dev-abc1234`),
  puis de la prod avec le même tag. `curl http://10.10.10.21/health`,
  `/version`, `POST /api/factures` : tout répond.
* Idempotence : second passage `changed=0` ; `--check --diff` sans le tag
  ne propose rien.

**Modules mobilisés** : 19 (rôles, vault, `docker_compose_v2`, `block`,
templates conditionnels), 18 (Compose en prod : `restart`, `env_file`,
réseaux, volumes nommés), 15 (secrets).

**Indices**

* `community.docker.docker_compose_v2` avec `project_src`, `env_files:
  [.env, state.env]`, `pull: policy`, `remove_orphans: true`. Le module
  supporte `--check` (dry-run Compose).
* Pour ne démarrer qu'une couleur, `profiles` Compose (`blue`, `green`) et
  `COMPOSE_PROFILES=blue` dans `state.env` sont plus propres qu'un
  `services:` conditionnel dans le template.
* Le mot de passe Redis dans `REDIS_URL` :
  `redis://:motdepasse@redis:6379/0`. L'API et le worker lisent `REDIS_URL`.
* Le worker n'a pas de couleur : il est recréé à chaque déploiement
  (quelques secondes), les jobs attendent dans Redis. Note-le comme
  compromis assumé dans le journal.
* `ansible-vault encrypt_string --vault-id default@.vault-pass 'xxx' -n
  vault_db_password` pour une variable seule ; ici, un fichier entier
  `vault.yml` est plus simple à faire tourner.
* `no_log: true` sur les tâches qui manipulent le `.env` ou le login : la
  sortie d'Ansible finit dans les journaux du runner CI.

**Livrable** : `ansible/roles/factura_compose/`, `deploy.yml`,
`group_vars/{staging,prod}/{main.yml,vault.yml}`, et dans le journal le
`PLAY RECAP` idempotent et le résultat de `nc -zv 10.10.10.22 5432` depuis
`lab-adm` (refusé) et depuis `10.10.10.21` (ouvert).

::: check
Critère de réussite : `check_PB_05.sh` passe sur `lab-adm`.

```bash
bash ~/workbook/scripts/projects/P2/check_PB_05.sh
```
:::

---

### **PB.6** — Pipeline d'intégration continue

::: contexte
À partir de maintenant, plus personne ne construit une image sur son poste.
Chaque push sur Gitea déclenche un pipeline qui lint, teste, construit,
scanne et publie. Une image qui n'a pas été produite par ce pipeline n'a pas
le droit de tourner en prod.
:::

**Objectif** : `.gitea/workflows/ci.yaml` avec les jobs `lint`, `test`,
`build` chaînés, qui pousse `factura-api` et `factura-worker` sur le
registre de Gitea avec un tag dérivé du commit (`sha-<7>`) et, sur un tag
Git `vX.Y.Z`, avec ce tag aussi ; le scan bloque sur HIGH/CRITICAL.

**Cahier des charges**

* Déclencheurs : `push` sur `main` et sur les tags `v*`, `pull_request`,
  `workflow_dispatch`. `concurrency` par référence, `cancel-in-progress`.
  `runs-on: ops-host` partout.
* `lint` : `pre-commit run --all-files` (donc gitleaks, shellcheck,
  yamllint, ansible-lint) **plus** `tofu fmt -check` et `tofu validate`
  dans `infra/` (avec `-backend=false`, sans token) et `docker compose
  -f app/compose.yaml config -q`.
* `test` : `pytest` de `app/api/tests` dans un conteneur `python:3.12-slim`
  (ou un venv sur le runner — justifie), avec rapport JUnit en artefact.
* `build` (`needs: [lint, test]`) : calcule le tag (`sha-${sha:0:7}`, et
  `${ref_name}` si c'est un tag `v*`), construit les deux images avec
  `--build-arg APP_VERSION=<tag>`, `docker login` au registre avec
  `secrets.REGISTRY_USER` / `secrets.REGISTRY_TOKEN` (jamais dans un
  `run:` interpolé : passe par `env:`), `trivy image --exit-code 1
  --severity HIGH,CRITICAL --ignore-unfixed` **avant** le push, push des
  tags, et publie en sortie de job (`outputs`) le tag et le **digest** de
  chaque image (`docker inspect --format '{{index .RepoDigests 0}}'`).
* Sur `pull_request` : lint et test seulement (pas de push).
* Secrets Gitea (`Settings → Actions → Secrets` du dépôt) :
  `REGISTRY_USER`, `REGISTRY_TOKEN` (token Gitea avec `write:package`),
  `VAULT_PASS`, `DEPLOY_SSH_KEY` (les deux derniers servent en PB.7).
* Branche `main` protégée : le statut `ci / build` requis pour fusionner.
* Preuve : un push avec un test cassé (fais-le sur une branche + PR)
  produit un run rouge et la PR non fusionnable ; `git tag v2.0.0 && git
  push --tags` produit `factura-api:v2.0.0` **et** `factura-api:sha-xxxxxxx`
  dans le registre. Le journal note la durée du pipeline et les trois
  postes les plus longs.

**Modules mobilisés** : 21 (workflows, runner hôte, secrets, artefacts,
`needs`/`outputs`, registre), 18 (build, tags, digests), 17 (tags,
branches protégées).

**Indices**

* En mode hôte, les jobs s'exécutent sous le compte `runner` de `lab-ops`,
  dans un répertoire de travail éphémère : tout ce que tu installes
  (`pipx`, `trivy`, `tofu`) doit être dans son `PATH`. Vérifie avec un job
  `run: which tofu trivy ansible-playbook`.
* `gitea.ref_type == 'tag'` et `gitea.ref_name` dans les expressions ;
  `GITHUB_REF_NAME` et `GITHUB_SHA` dans les `run:`.
* Écris dans `$GITHUB_OUTPUT` (`echo "tag=$TAG" >> "$GITHUB_OUTPUT"`) pour
  passer des valeurs entre jobs via `needs.build.outputs.tag`.
* Trivy télécharge sa base à chaque run : `TRIVY_CACHE_DIR` sur un chemin
  persistant de `lab-ops` (le runner est en mode hôte, c'est le seul
  avantage à en tirer) ou un `--skip-db-update` après le premier.
* Le registre de Gitea liste ses tags sur `GET /v2/mathieu/factura-api/
  tags/list` (auth basique) : pratique pour le check et pour PB.7.

**Livrable** : `.gitea/workflows/ci.yaml`, capture ou lien du run vert dans
le journal, `docs/journal.md` avec la durée et l'analyse.

::: check
Critère de réussite : `check_PB_06.sh` passe sur `lab-adm` (`export
GITEA_TOKEN=...` pour qu'il interroge l'API du dépôt privé).

```bash
GITEA_TOKEN=xxx bash ~/workbook/scripts/projects/P2/check_PB_06.sh
```
:::

---

### **PB.7** — Livraison continue : staging automatique, prod promue, bleu/vert

::: contexte
Le pipeline produit des images ; il doit maintenant les déployer. Tout ce
qui arrive sur `main` part en staging automatiquement. La prod, elle, ne
bouge que sur décision humaine : quelqu'un promeut un tag `vX.Y.Z` qui a
déjà tourné en staging. Dans les deux cas : bleu/vert, smoke test, retour
arrière automatique si le smoke échoue, et zéro requête perdue sur le
port 80.
:::

**Objectif** : push sur `main` → staging à jour en moins de 5 minutes ;
`cd-prod.yaml` lancé à la main avec un tag → prod à jour sans coupure ; un
mauvais déploiement est annulé tout seul, et on le voit dans
`switch.log`.

**Cahier des charges**

* `ci.yaml` gagne un job `deploy-staging` (`needs: build`, `if:
  gitea.ref == 'refs/heads/main'`) : récupère `VAULT_PASS` et
  `DEPLOY_SSH_KEY` dans des fichiers temporaires (0600, supprimés en
  `always()`), lance `ansible-playbook -i ansible/inventory/staging.ini
  ansible/playbooks/deploy.yml -e factura_image_tag=<tag> -e
  ansible_user=deploy`, puis `tools/smoke.sh http://10.10.10.21 <tag>`.
  L'inventaire `staging.ini` n'est pas dans Git : le job le **régénère**
  (un template minimal depuis une variable, ou `tofu output` sans apply —
  choisis et justifie ; l'option retenue par le corrigé est un inventaire
  `ansible/inventory/ci/<env>.ini` versionné, avec les IP, et un test qui
  vérifie qu'il correspond à `tofu output`).
* `.gitea/workflows/cd-prod.yaml` : `workflow_dispatch` avec `inputs.tag`
  obligatoire. Garde-fous **avant** de toucher à la prod : le tag
  correspond à `^v[0-9]+\.[0-9]+\.[0-9]+$` ; l'image existe dans le
  registre ; **le staging tourne ce tag** (`/version` sur 10.10.10.21) ;
  sinon échec explicite. Puis déploiement bleu/vert, smoke, et écriture
  d'une ligne dans `docs/deployments.log` ? Non — la CI n'écrit pas dans
  Git ; elle laisse une trace via l'API Gitea (une *release* ou un
  commentaire sur le tag) et dans `switch.log` sur la VM.
* Bleu/vert dans le rôle `factura_compose` (PB.5, complété) : lire
  `state.env`, déterminer la couleur **inactive**, y déployer le tag (pull,
  `up -d` du profil), attendre `/health` = 200 et `/version` = tag sur le
  port direct (8081/8082), lancer `tools/smoke.sh` contre le port direct,
  **basculer** (`switch.sh`), re-tester sur le port 80, mettre à jour
  `state.env`. Le tout dans un `block` ; le `rescue` rebascule sur
  l'ancienne couleur (si on avait basculé), arrête la couleur en échec,
  écrit `rollback` dans `switch.log` et fait échouer le play avec la raison.
* Zéro coupure : pendant une promotion, une boucle `while curl -sf
  http://10.10.10.31/health` toutes les 0,2 s depuis `lab-adm` ne voit
  **aucune** erreur (nginx recharge sans fermer les connexions).
* Test de rollback : pousse une image qui ment sur sa version (`docker tag
  ...:sha-xxxxxxx ...:v9.9.9 && docker push`), promeus `v9.9.9` sur le
  staging (par le playbook ou un `cd-staging` manuel) : le smoke détecte
  `/version ≠ v9.9.9`, le rôle rebascule, le run est rouge, la prod et le
  staging répondent toujours avec l'ancien tag. `switch.log` contient une
  ligne `rollback`.
* `docs/runbook-deploy.md` : comment livrer en staging, promouvoir en prod,
  revenir en arrière **en moins de 2 minutes** (`switch.sh` à la main sur
  la couleur précédente, qui tourne encore), que faire si le smoke échoue
  en prod, comment retrouver quelle version tourne (`/version`,
  `state.env`, `docker inspect` du digest).

**Modules mobilisés** : 21 (CD, `workflow_dispatch`, garde-fous, secrets,
`always()`), 19 (`block`/`rescue`, `wait_for`, `uri`), 18 (profils,
reload nginx), 11.

**Indices**

* `docker compose exec nginx nginx -s reload` : nginx relit
  `active.conf` et bascule les nouvelles connexions ; les anciennes
  finissent sur l'ancien upstream. C'est ça, le zéro coupure. Ne fais
  jamais `restart nginx` dans `switch.sh`.
* Le `rescue` s'exécute aussi quand le `wait_for` expire : pense à
  distinguer « on n'a pas encore basculé » et « on a basculé et le smoke
  a échoué » (un `set_fact switched: true` juste après le switch).
* `workflow_dispatch` se lance depuis l'onglet *Actions* de Gitea ou par
  `curl -X POST .../actions/workflows/cd-prod.yaml/dispatches -d
  '{"ref":"main","inputs":{"tag":"v2.1.0"}}'`. Mets cette commande dans
  le `Makefile` (`make promote TAG=v2.1.0`).
* Pour tester sans attendre la CI :
  `ansible-playbook ... deploy.yml -e factura_image_tag=v9.9.9` depuis
  `lab-adm` fait exactement ce que le runner fera.

**Livrable** : `ci.yaml` (avec `deploy-staging`), `cd-prod.yaml`, le rôle
complété, `docs/runbook-deploy.md`, et dans le journal : la boucle
zéro-coupure (nombre de requêtes, 0 erreur), le run de rollback rouge et
la ligne `switch.log` correspondante.

::: check
Critère de réussite : `check_PB_07.sh` passe sur `lab-adm`.

```bash
bash ~/workbook/scripts/projects/P2/check_PB_07.sh
```
:::

---

### **PB.8** — Observabilité : métriques, journaux, alertes, SLO

::: contexte
Au projet A, ta supervision était un script et un timer. Ici, la direction
veut « un chiffre » : le service est-il dans l'objectif ce mois-ci, et
combien de marge reste-t-il ? Tu déploies Prometheus, Alertmanager,
Grafana et Loki sur `lab-ops` par Ansible, tu branches les exporters de
PB.3 et PB.5, tu définis un SLO et tu alertes sur son budget d'erreur —
pas sur « CPU > 80 % ».
:::

**Objectif** : `ansible-playbook -i ansible/inventory/ops.ini
ansible/playbooks/monitoring.yml` déploie la pile dans
`/opt/factura-monitoring` sur `lab-ops` ; toutes les cibles sont `up` ; au
moins 5 alertes utiles dont une sur le budget d'erreur ; un dashboard
Factura provisionné ; les journaux des conteneurs sont dans Loki ;
`docs/slo.md` chiffre le SLO et le budget.

**Cahier des charges**

* `infra/monitoring/` : `compose.yaml` (`prometheus`, `alertmanager`,
  `grafana` sur **3001**, `loki`, `blackbox-exporter`, un récepteur de
  webhook `alert-sink` qui journalise les notifications dans
  `/opt/factura-monitoring/data/alerts.log` — le remplaçant de Slack pour
  le lab), `prometheus/prometheus.yml`, `prometheus/rules/*.yml`,
  `alertmanager/alertmanager.yml`, `loki/loki.yml`, `blackbox/blackbox.yml`,
  `grafana/provisioning/{datasources,dashboards}/`,
  `grafana/dashboards/factura.json`. Rôle ou playbook `monitoring.yml` qui
  copie tout ça, gère le mot de passe admin Grafana depuis le vault
  (`group_vars/ops/vault.yml`) et fait `docker compose up -d`.
* Cibles Prometheus (labels `env`, `role`, `host`) : `node_exporter` des
  quatre VM et de `lab-ops` ; API bleue et verte de chaque env via les
  ports directs 8081/8082 (`/metrics`), label `color` ; worker 9200 ;
  `redis_exporter` 9121 ; `postgres_exporter` 9187 ; blackbox `http_2xx`
  sur `http://10.10.10.21/health` et `http://10.10.10.31/health` ;
  Prometheus lui-même, Alertmanager, Loki, Grafana. `up == 0` nulle part.
* Règles d'enregistrement pour le SLI de disponibilité :
  `factura:http_requests:rate5m`, `factura:http_errors:ratio_rate5m`,
  `ratio_rate1h`, `ratio_rate6h` à partir de
  `factura_http_requests_total{status=~"5.."}`, par `env`.
* Alertes (au moins 5, dans `rules/alerts.yml`, avec `severity`,
  `summary`, `description`, `runbook` en annotation) : `InstanceDown` ;
  `FacturaApiDown` (blackbox) ; `FacturaErrorBudgetBurn` (burn rate
  multi-fenêtre : 14,4× sur 1 h **et** 5 min → `critical`, 6× sur 6 h
  **et** 30 min → `warning`) ; `FacturaQueueBacklog`
  (`redis_key_size{key="factura:jobs"} > 100` pendant 10 min) ;
  `FacturaBackupTooOld` (métrique posée par PB.9, > 26 h ; en attendant,
  l'alerte existe et est `firing`, c'est normal) ; `DiskWillFillIn4h`
  (`predict_linear` sur `node_filesystem_avail_bytes`) ; et `Watchdog`,
  toujours `firing`, routée vers le sink, pour prouver que la chaîne
  fonctionne.
* Alertmanager : `group_by: [alertname, env]`, `group_wait 30s`,
  `repeat_interval 4h`, `receiver` webhook vers `alert-sink`, une route
  `severity=critical` avec `repeat_interval 1h`, une inhibition (`critical`
  inhibe `warning` de même `alertname` et `env`). `amtool check-config`
  passe.
* Loki reçoit les journaux de promtail (PB.3) des quatre VM : `{env="prod",
  container=~"factura-api.*"} | json | level="ERROR"` renvoie quelque chose
  après avoir provoqué une erreur (un `POST` invalide). Les journaux de
  Gunicorn (`access log`) sont là aussi.
* Grafana : datasources Prometheus et Loki provisionnées, dashboard
  `Factura` provisionné (pas créé à la souris) avec au moins : requêtes/s
  par env et couleur, taux d'erreur 5xx, latence p95 (`histogram_quantile`
  sur `factura_http_request_seconds_bucket`), longueur de la file, jobs
  traités/erreur du worker, **budget d'erreur restant sur 30 jours**, un
  panneau Loki des erreurs.
* `docs/slo.md` : SLI (définition exacte en PromQL), SLO **99,5 % de
  requêtes non-5xx sur 30 jours glissants** et **95 % des requêtes sous
  300 ms**, budget d'erreur en minutes, ce qu'on fait quand il est
  consommé (gel des déploiements non correctifs), et une justification en
  cinq lignes de « pourquoi pas 99,99 % ».
* Preuve : arrête `api-blue` et `api-green` sur le staging 3 minutes →
  `FacturaApiDown` passe `firing`, une ligne arrive dans `alerts.log` en
  moins de 3 minutes, `Watchdog` y est déjà. Relance : `resolved` arrive.
  Génère 200 requêtes dont 30 % de 5xx (le worker arrêté ne fait pas de
  5xx… trouve comment produire des 5xx sans modifier le code : une base
  injoignable, par exemple via `switch.sh` vers une couleur arrêtée) :
  `FacturaErrorBudgetBurn` se déclenche.

**Modules mobilisés** : 22 (Prometheus, PromQL, règles, Alertmanager,
Grafana provisioning, Loki/LogQL, SLO), 19 (déploiement par Ansible), 18.

**Indices**

* Burn rate : budget = 1 − 0,995 = 0,5 %. Un taux d'erreur de
  14,4 × 0,5 % = 7,2 % soutenu 1 h consomme 2 % du budget mensuel : c'est
  le seuil « page ». Les deux fenêtres (longue et courte) évitent d'alerter
  sur un incident déjà terminé.
* `histogram_quantile(0.95, sum by (le, env) (rate(
  factura_http_request_seconds_bucket[5m])))`.
* Budget restant :
  `1 - (sum_over_time(factura:http_errors:ratio_rate5m[30d]) /
  count_over_time(...)) / 0.005` est approximatif mais suffisant ; le
  corrigé donne une version plus propre avec `increase`.
* Grafana provisioning : un fichier `datasources.yml`, un
  `dashboards.yml` qui pointe sur un dossier, et le JSON exporté avec
  `"uid"` fixe et `${DS_PROMETHEUS}` remplacé par le nom de la datasource.
* Loki : dans `promtail`, le label `container` vient de
  `__meta_docker_container_name` (retire le `/` initial avec un `regex`).
  Ne mets **jamais** un identifiant de requête ou de facture en label.

**Livrable** : `infra/monitoring/`, `monitoring.yml`, `docs/slo.md`, et
dans le journal : la ligne d'`alerts.log` de `FacturaApiDown` avec le délai
de détection, et une capture du dashboard pendant le burn.

::: check
Critère de réussite : `check_PB_08.sh` passe sur `lab-adm` (il interroge
Prometheus, Alertmanager, Grafana et Loki sur `lab-ops`).

```bash
bash ~/workbook/scripts/projects/P2/check_PB_08.sh
```
:::

---

### **PB.9** — Sauvegardes, restauration testée par la CI, reconstruction chronométrée

::: contexte
La question de l'audit : « si `factura-prod-web` et `factura-prod-db`
disparaissent, vous êtes de retour quand ? ». Tu vas y répondre avec un
chronomètre. Mais d'abord, la sauvegarde : automatisée, poussée sur
`lab-ops`, **restaurée toutes les semaines par un job CI** qui compare le
nombre de lignes — parce qu'une sauvegarde qu'on n'a pas restaurée n'existe
pas (projet A, tu te souviens).
:::

**Objectif** : sauvegarde nocturne de chaque base sur `lab-ops`, métrique
d'âge dans Prometheus, restauration hebdomadaire automatique par la CI
avec rapport, playbook de restauration, et `tools/rebuild.sh prod <tag>`
qui détruit et reconstruit la prod **complète, données comprises, en moins
de 60 minutes**, journal de temps à l'appui.

**Cahier des charges**

* Rôle `pg_backup` (appliqué aux hôtes `db` par `ansible/playbooks/
  backup.yml`, `become: true`) : script `/usr/local/sbin/factura-backup.sh`
  (`docker exec` du conteneur postgres, `pg_dump -Fc`, `.sha256`, un
  fichier `.meta` avec le nombre de lignes de `factures`, rétention 7
  jours, `rsync` vers `backup@10.10.10.14:/srv/backups/factura/<env>/`,
  et écriture **atomique** de `factura_backup_last_success_timestamp` et
  `factura_backup_size_bytes` dans le textfile collector de
  `node_exporter`), `factura-backup.service` (`User=deploy`,
  `Type=oneshot`) + `factura-backup.timer` (02:30, `RandomizedDelaySec`,
  `Persistent`), clé SSH de `deploy` générée par le rôle et **publiée par
  Ansible** sur `lab-ops` (play sur `ops` dans le même playbook :
  compte `backup`, `authorized_keys` avec `restrict,from="<ip db>",
  command="/usr/bin/rrsync /srv/backups/factura/<env>"`, répertoires).
* `ansible/playbooks/restore.yml` (hôtes `db`) : récupère le dernier dump
  de l'environnement sur `lab-ops` (via `lab-adm`, ou directement par
  `fetch`/`synchronize` — attention aux droits), vérifie le `.sha256`,
  `pg_restore --clean --if-exists` dans la base `factura` du conteneur,
  compare `count(*)` avec le `.meta`, échoue si différent. Utilisé par
  `tools/rebuild.sh` (fourni : lis-le).
* `.gitea/workflows/restore-test.yaml` : `schedule: '0 4 * * 1'` +
  `workflow_dispatch`, sur `ops-host` : prend le dernier dump de `prod`
  dans `/srv/backups/factura/prod/`, vérifie le hash, lance un
  `postgres:16-alpine` jetable, `pg_restore`, compare `count(*)` au
  `.meta`, écrit un rapport `/srv/backups/factura/restore-tests/
  <date>-<résultat>.txt` (durée, taille, lignes), supprime le conteneur
  en `always()`. Un échec fait un run rouge (et, bonus, une alerte : le
  rapport peut être lu par un `textfile` sur `lab-ops`).
* Alerte `FacturaBackupTooOld` (PB.8) passe de `firing` à `inactive` une
  fois la première sauvegarde faite. Le dashboard affiche l'âge.
* `tools/rebuild.sh prod <tag>` : lis-le, complète ce qu'il attend
  (`restore.yml`, inventaire, playbooks), lance-le **sur le staging
  d'abord**, corrige, puis sur la prod : `docs/rebuild-<date>.log` avec
  `TOTAL: <n> s`, `n < 3600`. Les cinq étapes sont chronométrées ; le
  journal analyse les deux plus longues et propose une réduction pour
  chacune (sans l'implémenter).
* RPO et RTO mesurés dans `docs/runbook-deploy.md` (section « Sinistre »)
  : RPO = au pire 24 h (sauvegarde à 02:30) ; RTO = le `TOTAL` mesuré.
  Une piste chiffrée pour un RPO < 1 h.

**Modules mobilisés** : 14 (timers), 12 (rrsync, clés restreintes), 07
(script robuste), 19 (multi-play, `delegate_to`, `fetch`), 21 (`schedule`,
`always()`), 20 (destroy/apply), 22 (textfile collector, alerte).

**Indices**

* `docker exec factura-postgres-1 pg_dump -U factura -Fc factura >
  fichier` : le dump sort du conteneur par stdout, pas besoin de volume.
  Pour la restauration : `docker exec -i ... pg_restore -U factura -d
  factura --clean --if-exists < fichier`.
* Le textfile collector : `/var/lib/prometheus/node-exporter/factura.prom`
  (paquet Ubuntu) ; écris dans `.tmp` puis `mv`. Le rôle `node_exporter`
  de PB.3 a mis le répertoire en groupe `deploy`, avec `g+w`.
* Le job CI hebdo tourne sous `runner` sur `lab-ops` : il lui faut le
  droit de lire `/srv/backups/factura/prod/` (groupe `backup` en lecture)
  et d'écrire `restore-tests/`. Règle ça dans le play `ops` de
  `backup.yml`, pas à la main.
* `rebuild.sh` fait `tofu destroy` puis `apply` : la baseline et le
  déploiement doivent marcher sur une VM neuve **sans** qu'un fichier
  d'état de `switch.log` existe. Si ton rôle de PB.5 échoue au premier
  déploiement, tu le sauras ici.
* `ssh-keygen -R` et `StrictHostKeyChecking=accept-new` sont déjà dans
  `rebuild.sh` : les VM recréées changent de clé d'hôte.

**Livrable** : `ansible/roles/pg_backup/`, `backup.yml`, `restore.yml`,
`restore-test.yaml`, `docs/rebuild-<date>.log` (< 3600 s),
`docs/runbook-deploy.md` complété (sinistre, RPO/RTO), un rapport de
restauration hebdo dans `restore-tests/`.

::: check
Critère de réussite : `check_PB_09.sh` passe sur `lab-adm`.

```bash
bash ~/workbook/scripts/projects/P2/check_PB_09.sh
```
:::

---

### **PB.10** — L'API sur k3s, et le verdict Compose contre k3s

::: contexte
Un des devs a lu que « tout le monde est sur Kubernetes ». La direction
te demande un avis argumenté, pas un avis de principe. Tu portes l'API (et
son worker, Redis, PostgreSQL) sur un k3s mono-nœud créé par OpenTofu,
avec ce que Kubernetes apporte réellement — probes, autoscaling, Ingress
TLS, rolling update natif — et tu compares avec ce que tu as déjà.
:::

**Objectif** : `factura-k3s` (10.10.10.41) créée par le workspace `k3s`,
k3s installé par Ansible, manifestes dans `k8s/`, API joignable en HTTPS
sur `https://factura-k3s.lab.local/health`, HPA fonctionnel, et
`docs/compose-vs-k3s.md` qui tranche.

**Cahier des charges**

* `infra/envs/k3s.tfvars` : une VM `k3s` (9041, hôte 41, 4 vCPU, 4 Go,
  40 Go, `name = "factura-k3s"`) ; workspace `k3s` ; inventaire
  `k3s.ini` généré avec un groupe `k3s`. Baseline PB.3 appliquée (avec un
  `firewall_rules` adapté : 443 et 6443 en plus, et pas de Docker : k3s
  embarque containerd — le rôle `docker` doit pouvoir être exclu par une
  variable).
* Rôle `k3s` + `ansible/playbooks/k3s.yml` : installation par le script
  officiel (version épinglée, `--tls-san factura-k3s.lab.local
  --disable servicelb`? Non, garde ServiceLB : Traefik en a besoin pour
  prendre l'IP du nœud), `/etc/rancher/k3s/registries.yaml` avec le
  registre Gitea (HTTP, identifiants du vault), kubeconfig rapatrié sur
  `lab-adm` dans `~/.kube/factura-k3s.yaml` avec l'IP du nœud à la place
  de `127.0.0.1`, mode 0600.
* `k8s/` : `namespace.yaml`, `configmap.yaml` (`REDIS_URL`, `LOG_LEVEL`),
  `secret.yaml` **généré depuis le vault et non versionné**
  (`DATABASE_URL`, mot de passe PostgreSQL, secret de pull du registre
  `imagePullSecrets`), `postgres.yaml` (StatefulSet + PVC `local-path` +
  Service, `init.sql` via ConfigMap), `redis.yaml`, `api.yaml`
  (Deployment 2 réplicas, `readinessProbe` sur `/health`, `livenessProbe`
  sur `/version`, `resources.requests/limits`, `strategy: RollingUpdate
  maxUnavailable: 0`, `securityContext` non-root, `runAsUser: 10001`),
  `worker.yaml`, `service.yaml`, `ingress.yaml` (Traefik, host
  `factura-k3s.lab.local`, TLS avec un secret `factura-tls` créé depuis
  un certificat signé par ta CA du projet A ou auto-signé, redirection
  HTTP→HTTPS), `hpa.yaml` (`autoscaling/v2`, CPU 60 %, min 2, max 5).
  Aucune image en `:latest`.
* `kubectl --kubeconfig ~/.kube/factura-k3s.yaml apply -f k8s/` puis
  `rollout status` OK ; `curl --cacert ... https://factura-k3s.lab.local/
  health` → `ok` ; `POST /api/factures` → 201, le worker traite.
* Rolling update : `kubectl set image deployment/api api=...:<autre tag>`
  pendant une boucle `curl` : aucune erreur (compare avec le bleu/vert de
  PB.7 : qu'est-ce que Kubernetes fait pour toi ici ?).
* HPA : charge avec `hey -z 60s -c 20 https://...` (ou une boucle `curl`
  en parallèle) : `kubectl get hpa -w` monte à 3+ réplicas, puis
  redescend. Note le délai de montée et de descente.
* Prometheus (PB.8) scrape l'API sur k3s (un `Service` de type `NodePort`
  pour `/metrics`, ou l'Ingress sur un chemin restreint) et promtail
  envoie les journaux des pods (le rôle de PB.3 lit Docker ; sur k3s c'est
  containerd : `/var/log/pods/` — adapte la config par une variable).
* `docs/compose-vs-k3s.md` (60 lignes minimum) : tableau critères ×
  solution (déploiement sans coupure, rollback, autoscaling, secrets,
  stockage, supervision, courbe d'apprentissage, empreinte mémoire
  **mesurée** avec `free -m` sur les deux VM, temps de reconstruction,
  nombre de lignes de YAML), puis une **recommandation** pour Ravel &
  Associés (40 personnes, une application, un admin), et ce qui ferait
  changer d'avis.

**Modules mobilisés** : 22 (k3s, manifestes, probes, HPA, Ingress,
registre privé, scrape), 20 (workspace supplémentaire), 19 (rôle k3s), 15
(TLS).

**Indices**

* `registries.yaml` : `mirrors: {"lab-ops.lab.local:3000": {endpoint:
  ["http://lab-ops.lab.local:3000"]}}` et `configs: {"lab-ops.lab.local:
  3000": {auth: {username, password}}}`. Redémarre `k3s` après.
* Le secret de pull : `kubectl create secret docker-registry regcred
  --docker-server=lab-ops.lab.local:3000 --docker-username=mathieu
  --docker-password=<token> -n factura --dry-run=client -o yaml` te donne
  le YAML à générer depuis le vault (par un template Ansible, jamais à
  la main).
* Le HPA a besoin de `resources.requests.cpu` et de metrics-server (k3s
  l'embarque) ; `kubectl top pods -n factura` doit répondre avant de
  tester.
* `hey` : `go install github.com/rakyll/hey@latest` ou le binaire ; ou
  `for i in $(seq 20); do (while :; do curl -sk https://.../api/factures
  >/dev/null; done) & done` puis `kill %1 ...`.
* Traefik est déjà là (k3s), avec un `IngressClass` `traefik` par défaut ;
  la redirection HTTP→HTTPS se fait par annotation
  `traefik.ingress.kubernetes.io/router.entrypoints: websecure` plus un
  `Middleware` `redirectscheme`, ou plus simplement deux Ingress.

**Livrable** : `infra/envs/k3s.tfvars`, `ansible/roles/k3s`, `k3s.yml`,
`k8s/*.yaml` (sauf `secret.yaml`), `tools/k8s-secret.sh` ou le play qui le
génère, `docs/compose-vs-k3s.md`, et dans le journal : délais HPA, et la
sortie de `free -m` sur `factura-prod-web` et `factura-k3s` au repos.

::: check
Critère de réussite : `check_PB_10.sh` passe sur `lab-adm`
(`KUBECONFIG=~/.kube/factura-k3s.yaml`).

```bash
bash ~/workbook/scripts/projects/P2/check_PB_10.sh
```
:::

---

## B.3 Incidents

::: attention
Avant chaque incident : `qm snapshot 9001 avant-incB<n>` (lab-adm) et le
snapshot des VM concernées. Les scripts sauvegardent ce qu'ils cassent dans
`/root/.breakfix-backup/` sur la machine où ils tournent, mais certains
touchent au registre, à l'état OpenTofu ou à l'historique Git : le snapshot
est ta vraie sortie de secours. Un incident à la fois. Résous avec le
runbook et l'outillage, pas avec le corrigé. Post-mortem dans
`docs/incidents/INC-B<n>-<slug>.md` (Résumé, Impact, Chronologie, Cause
racine, Correctif, Prévention).
:::

### **INC-B1** — « Le pipeline est vert, mais la prod calcule mal la TVA »

**Contexte.** Lundi 11 h. Le service comptable signale que les factures
créées depuis 10 h ont un TTC faux (19,6 % au lieu de 20 %). Un collègue
dit avoir « relancé le déploiement de prod ce matin pour rafraîchir, avec
le même tag que vendredi, ça n'a rien changé au code ».

**Symptôme.** `curl http://10.10.10.31/version` renvoie exactement le tag
de vendredi. Le dernier run de `cd-prod` est vert. `git log` sur `main` ne
montre rien de nouveau. Pourtant `POST /api/factures` avec `montant_ht:
100` renvoie `montant_ttc: 119.6`. Le staging, lui, renvoie `120.0`.

**Interdit.** Reconstruire l'image sur ton poste, modifier `app.py`,
redéployer « pour voir » avant d'avoir compris.

**Objectif.** Prod correcte en moins de 30 minutes ; preuve de ce qui a
tourné (digest) ; mesure pour que le pipeline ne puisse plus déployer
autre chose que ce qu'il a construit.

```bash
# sur lab-adm
sudo bash ~/workbook/scripts/projects/P2/break_PB_01.sh
```

::: repondre
lignes: 8
:::

---

### **INC-B2** — « `tofu plan` veut recréer la base de prod »

**Contexte.** Mardi 9 h. Hier soir, un collègue a « libéré de la RAM à
chaud sur Proxmox » pour une autre VM, et « nettoyé un truc dans OpenTofu
qui traînait ». Il est en congé.

**Symptôme.** `make infra-plan ENV=staging` propose une modification sur
`factura-staging-db`. `make infra-plan ENV=prod` propose de **créer**
`factura-prod-db`… qui tourne, avec les données de prod dedans. Un autre
collègue propose `tofu apply` « puisque c'est ce que dit le code ».

**Interdit.** `tofu apply` sans avoir lu le plan ligne à ligne ; supprimer
une VM ; modifier les `.tfvars` pour « faire coller ».

**Objectif.** Un plan vide sur les deux workspaces, sans reboot de la prod,
sans perte de données ; explication des deux drifts ; règle d'équipe.

```bash
# sur lab-adm
sudo bash ~/workbook/scripts/projects/P2/break_PB_02.sh
```

::: repondre
lignes: 8
:::

---

### **INC-B3** — « Le déploiement de prod échoue : vault illisible »

**Contexte.** Mercredi 16 h. Un collègue a « fait tourner le mot de passe
PostgreSQL de prod » ce matin et commité « chore(vault): rotation ». Depuis,
la promotion en prod échoue. Le staging se déploie normalement.

**Symptôme.** `ansible-vault view ansible/inventory/group_vars/prod/
vault.yml` échoue. Le run `cd-prod` est rouge à l'étape Ansible. La prod
tourne encore (le déploiement n'a rien touché), mais un correctif urgent
doit partir avant 18 h.

**Interdit.** Réinitialiser le vault avec de nouveaux mots de passe (la
prod tourne avec les anciens, et tu ne les as pas... ou si ?), désactiver
le vault, mettre les secrets en clair.

**Objectif.** Vault lisible, promotion possible, vérification que le mot de
passe dans le vault est bien celui que la prod utilise, et une procédure
de rotation qui ne peut plus produire ça.

```bash
# sur lab-adm
sudo bash ~/workbook/scripts/projects/P2/break_PB_03.sh
```

::: repondre
lignes: 8
:::

---

### **INC-B4** — « Le staging est tombé à midi, personne n'a été prévenu »

**Contexte.** Vendredi 17 h. Un dev te dit que le staging ne répond plus
« depuis midi, au moins ». Tu regardes `alerts.log` : rien depuis ce
matin, à part `Watchdog`. Une maintenance réseau a eu lieu hier.

**Symptôme.** `curl http://10.10.10.21/health` échoue. Sur Prometheus,
`FacturaApiDown{env="staging"}` est `firing` depuis des heures.
Alertmanager est `up`. Aucune notification n'est partie.

**Interdit.** Redémarrer Alertmanager ou Prometheus « pour voir »,
supprimer la pile de supervision et la redéployer.

**Objectif.** Staging remis en service, cause de l'absence d'alerte
trouvée et corrigée, et une alerte (ou un panneau) qui détecte ce cas à
l'avenir.

```bash
# sur lab-adm
sudo bash ~/workbook/scripts/projects/P2/break_PB_04.sh
```

::: repondre
lignes: 8
:::

---

## B.4 Grille d'évaluation

Note sur 100. Un jalon dont le `check` ne passe pas ne peut pas obtenir plus
de la moitié de ses points.

| Jalon | Points | Ce qui est noté |
|---|---|---|
| PB.1 Mono-repo | 6 | check ; hooks qui refusent secret et message ; commits atomiques |
| PB.2 OpenTofu | 10 | check ; plan vide ; workspaces ; user-data minimal ; token hors Git ; temps d'apply noté |
| PB.3 Baseline | 10 | check ; `changed=0` ; ports Docker réellement filtrés ; `deploy` sans sudo |
| PB.4 Images | 8 | check ; taille, non-root, healthcheck ; scan ; justification ligne à ligne |
| PB.5 Déploiement | 12 | check ; vault et indirection ; idempotence en `--check` ; pas de sudo ; 5432 fermé à lab-adm |
| PB.6 CI | 10 | check ; scan bloquant ; tags sha + version ; secrets par `env:` ; durée analysée |
| PB.7 CD | 14 | check ; zéro erreur pendant la bascule ; rollback automatique prouvé ; garde-fous prod ; runbook |
| PB.8 Observabilité | 12 | check ; alertes utiles avec runbook ; burn rate ; dashboard provisionné ; SLO chiffré |
| PB.9 Sauvegardes | 10 | check ; restauration hebdo CI ; `TOTAL < 3600 s` ; RPO/RTO ; analyse des étapes |
| PB.10 k3s | 8 | check ; probes/HPA/TLS ; rolling update sans erreur ; comparaison chiffrée et tranchée |

Pénalités transverses (jusqu'à −10) : secret en clair dans Git (même
« supprimé » au commit suivant), intervention manuelle sur une VM
`factura-*` non reportée dans le code, image `:latest` en prod, `sudo`
pour le compte `deploy`, journal vide, `tfstate` commité.

Bonus (jusqu'à +5) : backend d'état distant avec verrou (MinIO sur
`lab-ops`), signature des images (cosign), déploiement par digest plutôt
que par tag, Alloy à la place de Promtail, cAdvisor dans le scrape,
PostgreSQL en réplication vers le staging (RPO < 1 h).

---

## B.5 Pour l'entretien

1. **« J'ai industrialisé une plateforme que j'avais d'abord montée à la
   main. »** Tu sais dire, pour chaque rôle Ansible, quelle procédure du
   projet A il remplace et ce que l'idempotence change quand on rejoue à
   3 h du matin. Tu as le tableau de B.6 en tête.
2. **« Staging et prod, c'est le même code avec deux fichiers de
   variables. »** `for_each`, workspaces, `templatefile`, inventaire
   généré : tu peux expliquer pourquoi un `diff` de 6 lignes entre deux
   `.tfvars` vaut mieux que deux répertoires copiés-collés, et ce qu'est
   un drift (INC-B2).
3. **« Une image est identifiée par son digest, pas par son tag. »**
   INC-B1 t'a montré qu'un tag est un pointeur mutable. Tu sais ce que le
   pipeline doit publier (`outputs.digest`), comment déployer par digest,
   et pourquoi `:latest` est interdit en prod.
4. **« Déployer sans coupure : bleu/vert avec un reload nginx, ou rolling
   update Kubernetes. »** Tu as mesuré zéro erreur sur les deux, tu sais
   ce que l'un demande d'écrire (un rôle, un `switch.sh`, un `rescue`)
   et ce que l'autre donne gratuitement (probes, `maxUnavailable: 0`),
   et à quel prix.
5. **« Le rollback est automatique, et je l'ai vu marcher. »** Smoke test
   après bascule, `rescue` qui rebascule, ligne `rollback` dans le
   journal : tu as un run rouge à montrer et un temps de retour arrière
   mesuré.
6. **« On alerte sur le budget d'erreur, pas sur le CPU. »** SLO 99,5 %,
   budget de 3 h 36 par mois, burn rate multi-fenêtre : tu sais expliquer
   pourquoi une alerte « CPU > 80 % » réveille pour rien et pourquoi
   « 7,2 % d'erreurs pendant une heure » réveille à raison. Et INC-B4 :
   un silence oublié rend tout ça muet.
7. **« La reconstruction complète prend N minutes, je l'ai chronométrée. »**
   Détruire la prod volontairement et la revoir tourner avec ses données
   sous l'heure, c'est la meilleure réponse à « c'est sauvegardé ? ». Tu
   connais les deux étapes les plus longues et comment les raccourcir.
8. **« Kubernetes ou pas : voici mon avis, et voici ce qui le ferait
   changer. »** Empreinte mémoire mesurée, lignes de YAML comptées,
   compétences de l'équipe : pour une PME avec une application et un admin,
   tu as une recommandation argumentée, pas une opinion.

---

## B.6 Du manuel à l'automatisé

| À la main dans le projet A | Automatisé par… | Jalon |
|---|---|---|
| `qm create`, installation d'Ubuntu, IP fixe, clé SSH | OpenTofu + cloud-init (`for_each`, snippets) | PB.2 |
| `/etc/hosts`, comptes, `useradd -r`, arborescence | rôle `common` | PB.3 |
| `sshd_config.d/`, `sshd -t` puis restart | rôle `ssh_hardening` (template + `validate`) | PB.3 |
| `ufw allow from ... to any port ...` un par un | rôle `firewall` (liste `firewall_rules`, `DOCKER-USER`) | PB.3 |
| `unattended-upgrades`, chrony, node_exporter | rôles dédiés | PB.3 |
| venv, `pip install`, unité systemd durcie, `ExecStart` | `Dockerfile` multi-stage, `USER app`, `CMD` | PB.4 |
| `/etc/factura/*.env` en 0640, `SECRETS.md` | `ansible-vault`, template `.env` 0600 | PB.5 |
| `scp` + `systemctl restart` (coupure) | rôle `factura_compose`, bleu/vert, `switch.sh` | PB.5, PB.7 |
| `pytest` sur le poste du dev, « ça marche chez moi » | job `test` en CI, image construite une fois | PB.6 |
| `openssl` + `pa5-cert.sh` pour le certificat | secret TLS Kubernetes, Ingress | PB.10 |
| rsyslog TCP 10514, `/var/log/remote/<hôte>/` | promtail → Loki, requêtes LogQL | PB.3, PB.8 |
| `factura-healthcheck.timer`, `.prom` textfile, webhook | Prometheus, blackbox, règles, Alertmanager | PB.8 |
| `factura-backup.timer`, rsync, `restore.md` | rôle `pg_backup`, `restore.yml`, job CI hebdo | PB.9 |
| Runbook de deux jours pour tout refaire | `tools/rebuild.sh` : < 1 h, chronométré | PB.9 |
| Un serveur, un service, `Restart=on-failure` | Deployment, probes, HPA, rolling update | PB.10 |
