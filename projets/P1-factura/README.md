# Projet A — Factura : plateforme de facturation multi-services

## A.0 Présentation

::: objectif
Ce projet fil rouge fait travailler ensemble tout ce que tu as appris dans les
modules 1 à 19 : comptes et permissions, FHS, systemd, paquets, LVM, réseau,
SSH, journaux, timers, sécurité et diagnostic. À la fin, tu sais :

* héberger une application multi-services (frontal, API, worker, base, file)
  sur plusieurs machines, **entièrement à la main**, et expliquer chaque choix ;
* isoler chaque composant : compte de service dédié, unité systemd durcie,
  ports fermés par défaut, secrets hors du code ;
* mettre en place ce qu'une PME attend réellement : TLS propre, journaux
  centralisés, sauvegardes **testées**, supervision qui alerte, procédure
  d'exploitation écrite ;
* diagnostiquer et résoudre trois incidents réalistes en te servant du runbook
  que tu auras écrit toi-même ;
* dire, en entretien, ce que Docker et Ansible automatiseront ensuite — parce
  que tu l'auras fait sans eux.

Temps estimé : 20 à 30 h, à étaler sur deux ou trois semaines.
Prérequis : modules 01 à 19. Aucun outil des modules 21 et suivants (Docker,
Ansible, CI) n'est autorisé : le but est de comprendre ce qu'ils remplacent.
:::

### Le contexte

Une PME de quarante personnes, « Ravel & Associés », a fait développer en
interne une application de facturation baptisée **Factura**. Elle tourne
aujourd'hui sur le portable du développeur qui l'a écrite, lancée à la main
dans un terminal. Le développeur part dans un mois. La direction te confie
l'hébergement : « on veut que ça tourne tout seul, que ce soit sauvegardé, et
qu'on sache quoi faire quand ça tombe ».

L'application est fournie (tu ne la modifies pas) :

| Composant | Techno | Où |
|---|---|---|
| Front statique | HTML/JS/CSS | `lab-web`, servi par nginx |
| API `factura-api` | Python Flask sous Gunicorn, port 8000 local | `lab-web` |
| Worker `factura-worker` | Python, consomme une file Redis, génère des PDF | `lab-web` |
| Base de données | PostgreSQL 16 | `lab-db` |
| File de travaux | Redis | `lab-db` |
| Journaux, sauvegardes, supervision | rsyslog, rsync, timers | `lab-ops` |

Le cahier des charges de la direction, tel qu'elle l'a formulé :

1. L'interface est accessible en HTTPS sur `https://factura.lab.local`
   depuis le réseau de l'entreprise, avec un certificat reconnu par les postes.
2. Rien d'autre que le HTTPS n'est exposé : ni l'API, ni la base, ni Redis.
3. Chaque composant redémarre seul après un reboot ou un plantage.
4. Les journaux de tout ça sont lisibles depuis une seule machine.
5. Une sauvegarde par nuit, conservée une semaine, copiée sur une autre
   machine, et **on a la preuve qu'elle se restaure**.
6. Quand quelque chose ne va pas, une alerte part sans qu'on ait à regarder.
7. Un exploitant non-administrateur peut redémarrer les services et lire les
   journaux, mais rien d'autre.
8. Il existe un document qui dit quoi faire à 3 h du matin.

### Règles du jeu

* Tout se fait **à la main** : `apt`, éditeur, `systemctl`, `openssl`, `ufw`.
  Tu peux (tu dois) écrire des scripts Bash, mais ni Docker, ni Ansible, ni
  aucun outil de déploiement.
* Tu ne modifies pas le code Python fourni. Si tu penses qu'il a un défaut,
  note-le dans le journal de bord : c'est une question d'entretien classique
  (« que demanderais-tu aux devs ? »).
* Chaque jalon produit un **livrable** et se valide par un script `check_PA_YY`.
  Le check vérifie le résultat, pas la méthode. Les scripts sont dans
  `~/workbook/scripts/projects/P1/`. Sur `lab-web`, `lab-db` et `lab-ops`, lance-les avec `sudo` : ils lisent des fichiers protégés via `sudo -n` et afficheraient sinon de faux échecs.
* Tu tiens un **journal de bord** (`~/P1/journal.md` sur `lab-adm`) : date,
  jalon, ce que tu as fait, ce qui a coincé. Il compte dans la note.
* Tu gardes une **copie de chaque fichier de configuration** que tu écris dans
  `~/P1/conf/<hôte>/` sur `lab-adm`. C'est ton dépôt de configuration, à la
  main, avant que Git et Ansible ne le fassent pour toi.

### Mise en place

Quatre VM : `lab-adm` (10.10.10.10), `lab-web` (10.10.10.11), `lab-db`
(10.10.10.12), `lab-ops` (10.10.10.14). `lab-rhel` n'est pas utilisée.

```bash
# depuis le shell Proxmox : un snapshot par VM avant de commencer
for id in 9001 9002 9003 9005; do qm snapshot $id avant-P1; done
```

Sur **chaque** VM, depuis ton clone du workbook :

```bash
sudo bash ~/workbook/scripts/projects/P1/setup_P1.sh
```

Le script dépose les sources de l'application dans `/usr/local/src/factura/`
selon le rôle de la machine (API, worker et front sur `lab-web` ; schéma SQL
sur `lab-db` ; outils partout) et crée `~/P1/` avec un journal de bord vide.
Il **n'installe rien d'autre**, ne crée aucun compte, aucun service, aucune
configuration : tout ça, c'est le projet.

::: attention
Prends un snapshot **avant chaque jalon** (`qm snapshot 9002 avant-PA3`…).
Certains jalons (pare-feu, SSH, sudo) peuvent t'enfermer dehors : garde
toujours une seconde session SSH ouverte et la console Proxmox sous la main.
:::

::: astuce
Lis les en-têtes de `factura_api.py` et `factura_worker.py` avant de
commencer : ils listent les variables d'environnement attendues, les routes et
le comportement sur `SIGTERM`. Un admin qui héberge une application commence
par lire ce qu'elle attend de lui.
:::

---

## A.1 Architecture cible

```
                      réseau PME 10.10.10.0/24
   ┌──────────────┐
   │   lab-adm    │  poste d'admin, CA de lab, runbook, journal de bord
   │ 10.10.10.10  │──── ssh 22 ────────────────────────────────┐
   └──────┬───────┘                                            │
          │ https 443 (factura.lab.local)                      │
          ▼                                                    │
   ┌──────────────────────────────────────────┐                │
   │ lab-web 10.10.10.11                      │                │
   │  nginx :443 TLS ──► /            (www)   │                │
   │            └──────► /api/  ──► gunicorn  │                │
   │                          127.0.0.1:8000  │                │
   │  factura-api.service   (user factura)    │                │
   │  factura-worker.service (user factura)   │                │
   │        │ PDF ──► /srv/factura/exports    │                │
   │  node_exporter :9100  rsyslog ──┐        │                │
   └────┬───────┬────────────────────┼────────┘                │
        │ 5432  │ 6379               │ tcp 10514               │
        ▼       ▼                    │                         │
   ┌──────────────────────────┐      │    ┌─────────────────────────────┐
   │ lab-db 10.10.10.12       │      └───►│ lab-ops 10.10.10.14         │
   │  postgresql@16-main      │ 10514     │  rsyslog collecteur         │
   │  redis-server            │─────────► │  /var/log/remote/<hôte>/    │
   │  LV vg_data/lv_pg        │           │  /srv/backups/factura/<hôte>│
   │  factura-backup.timer ───│─ rsync ──►│  factura-healthcheck.timer  │
   │  node_exporter :9100     │  ssh 22   │  factura-webhook :9999      │
   └──────────────────────────┘           │  node_exporter :9100        │
                                          └─────────────────────────────┘
```

@fig(p1-architecture): La plateforme Factura à la main : lab-web (nginx TLS, API Gunicorn, worker), lab-db (PostgreSQL, Redis), lab-ops (rsyslog central, sauvegardes rsync, healthcheck et webhook par timers), lab-adm seule porte d'administration en SSH.

### Flux autorisés (tout le reste est fermé)

| Source | Destination | Port | Usage |
|---|---|---|---|
| réseau PME | lab-web | 80, 443 | redirection, HTTPS |
| lab-adm | web, db, ops | 22 | administration |
| lab-web | lab-db | 5432, 6379 | PostgreSQL, Redis |
| lab-web, lab-db | lab-ops | 10514 | rsyslog TCP |
| lab-web, lab-db | lab-ops | 22 | rsync des sauvegardes |
| lab-ops | web, db | 9100 | node_exporter |
| lab-ops | lab-web | 443 | healthcheck, `/api/metrics` |
| lab-web, lab-db | lab-ops | 9999 | alertes vers le webhook (option PA.8) |

### Arborescence sur `lab-web`

| Chemin | Contenu | Propriétaire |
|---|---|---|
| `/opt/factura/{api,worker,venv}` | code et venv Python, **non modifiables par le service** | `root:root` |
| `/etc/factura/*.env` | configuration et secrets | `root:factura 0640` |
| `/srv/factura/www` | front statique | `root:root` |
| `/srv/factura/exports` | PDF générés | `factura:factura 0750` |
| `/var/log/factura` | journaux applicatifs | `factura:adm 0750` |
| `/var/lib/factura` | état du service | `factura:factura` |
| `/var/backups/factura` | archives locales avant rsync | `factura:factura` |

### Comptes

| Compte | Où | Rôle |
|---|---|---|
| `factura` | lab-web | exécute API, worker, sauvegarde des exports |
| `postgres` | lab-db | PostgreSQL et `pg_dump` (peer) |
| `backup` | lab-ops | reçoit les rsync, shell `/bin/sh`, clé restreinte |
| `pme-ops` | lab-web | exploitant, sudo restreint (PA.9) |
| `mathieu` | partout | toi, administrateur |

---

## A.2 Jalons

Chaque jalon suit le même plan : contexte, objectif, cahier des charges
(chaque puce est vérifiable), modules mobilisés, indices, livrable, critère de
réussite. Fais-les dans l'ordre : chaque check suppose les précédents.

### **PA.1** — Terrain, comptes de service, arborescence

::: contexte
Avant d'installer quoi que ce soit, tu prépares le terrain sur les quatre VM :
noms, comptes, répertoires, droits. C'est le jalon le plus court et celui qu'on
bâcle le plus. Chaque raccourci pris ici (un `chmod 777`, un compte avec
shell) ressort au jalon 9.
:::

**Objectif** : des machines qui se connaissent, des comptes de service sans
shell, une arborescence conforme au FHS avec les bons propriétaires.

**Cahier des charges**

* `/etc/hosts` de chaque VM résout `lab-adm`, `lab-web`, `lab-db`, `lab-ops`
  et `factura.lab.local` (vers 10.10.10.11).
* Sur `lab-web` : compte système `factura`, home `/srv/factura`, shell
  `nologin`, groupe primaire `factura`. Pas de mot de passe.
* Sur `lab-ops` : compte système `backup`, home `/srv/backups`, shell
  `/bin/sh` (il exécutera `rsync` via SSH ; la restriction viendra de la clé,
  pas du shell).
* Arborescence de `lab-web` exactement comme le tableau de A.1 (chemins,
  propriétaires, modes). Sur `lab-db` : `/etc/factura` (`root:root 0750`) et
  `/var/log/factura` (`root:adm 0750`). Sur `lab-ops` : `/srv/backups/factura`
  (`backup:backup 0750`), `/var/log/factura` (`root:adm 0750`).
* Aucun fichier de `/etc/factura` n'est lisible par « others », maintenant et
  pour toute la durée du projet.
* Sur `lab-adm` : `~/P1/pki/` créé (mode 0700), première entrée du journal.
* `setup_P1.sh` a été lancé sur les quatre VM.

**Modules mobilisés** : 02 (FHS), 03 (permissions), 04 (comptes), 12 (`/etc/hosts`).

**Indices**

* `useradd -r` crée un compte système (uid < 1000) ; `-M` évite de créer le
  home si tu veux le créer toi-même avec les bons droits.
* `install -d -o factura -g factura -m 0750 /srv/factura/exports` fait en une
  commande ce que `mkdir` + `chown` + `chmod` font en trois.
* Pourquoi `/var/log/factura` appartient-il au groupe `adm` ? Regarde qui est
  dans ce groupe sur Ubuntu et ce que ça permet à `mathieu`. `getent passwd backup` sur `lab-ops` avant de créer quoi que ce soit : Ubuntu a déjà un compte `backup`. Adapte-le (`usermod`) plutôt que d'en créer un autre.

**Livrable** : `~/P1/conf/lab-web/hosts`, un script `~/P1/bin/pa1-terrain.sh`
idempotent qui crée comptes et arborescence sur la machine où il tourne (tu
le rejoueras si tu repars du snapshot), et la première entrée du journal.

::: check
Critère de réussite : sur chaque VM, `bash check_PA_01.sh` passe. Ton script
`pa1-terrain.sh` relancé deux fois ne change rien la seconde fois.

```bash
bash ~/workbook/scripts/projects/P1/check_PA_01.sh
```
:::

---

### **PA.2** — PostgreSQL 16, Redis, réseau et pare-feu

::: contexte
`lab-db` héberge la donnée. Le développeur te donne `schema.sql` et `seed.sql`
et te dit : « la base s'appelle `factura`, l'appli se connecte avec
`factura_app` ». Le reste — où sont les données, qui peut s'y connecter,
depuis où — c'est ton métier.
:::

**Objectif** : une base et une file joignables **uniquement** depuis `lab-web`,
authentifiées, dont les données vivent sur un volume dédié.

**Cahier des charges**

* Le répertoire de données PostgreSQL (`/var/lib/postgresql`) est monté depuis
  un volume logique `vg_data/lv_pg` (4 Go, ext4) créé sur `/dev/sdb`, déclaré
  dans `/etc/fstab` par UUID. Fais-le **avant** d'installer PostgreSQL, ou
  déplace les données proprement après.
* PostgreSQL 16 écoute sur `10.10.10.12` (et localhost), pas sur `0.0.0.0`.
* `password_encryption = scram-sha-256`. Le rôle `factura_app` a `LOGIN`,
  un mot de passe fort, n'est ni superuser ni `CREATEDB`, et possède la base
  `factura`.
* `pg_hba.conf` : accès de `factura_app` à `factura` depuis `10.10.10.11/32`
  en `scram-sha-256`, et rien d'autre en `host`. Aucune règle `trust`, `md5`
  ou `0.0.0.0/0`.
* `schema.sql` puis `seed.sql` joués **en tant que `factura_app`** (les objets
  lui appartiennent). La fonction `next_invoice_number()` existe.
* Redis écoute sur `10.10.10.12` et `127.0.0.1`, `protected-mode yes`,
  `requirepass` avec un mot de passe fort, `maxmemory 128mb` avec une
  politique d'éviction qui **ne détruit jamais la file** (réfléchis :
  `allkeys-lru` est-il acceptable pour une file de travaux ?).
* Les deux services sont `enabled` et survivent à un reboot de `lab-db`.
* `ufw` sur `lab-db` : deny entrant par défaut ; 22 depuis `10.10.10.10`
  seulement ; 5432 et 6379 depuis `10.10.10.11` seulement. Depuis `lab-adm`,
  5432 et 6379 sont refusés.
* Les mots de passe sont notés dans `~/P1/conf/SECRETS.md` sur `lab-adm`, en
  mode 0600. C'est ton coffre-fort provisoire (le vrai viendra plus tard).

**Modules mobilisés** : 10 (apt, dépôts), 11 (LVM, fstab), 12 (écoute, `ss`),
15 (PostgreSQL, Redis, rôles), 18 (ufw, mots de passe).

**Indices**

* Le paquet `postgresql-16` d'Ubuntu 24.04 initialise le cluster `16/main`
  à l'installation : si `/var/lib/postgresql` est déjà un point de montage
  vide et accessible, il s'y installe. Sinon `pg_dropcluster` /
  `pg_createcluster` savent recréer un cluster ailleurs.
* `listen_addresses` demande un **restart**, pas un reload. `pg_hba.conf`, un
  reload suffit. `SHOW listen_addresses;` te dit ce qui est réellement appliqué.
* Redis : `redis-cli -h 10.10.10.12 -a '...' CONFIG GET maxmemory-policy`.
  Lis la documentation de `noeviction`.
* Teste chaque règle ufw depuis la machine qui **doit** passer et depuis une
  qui **ne doit pas** : `nc -zv -w2 10.10.10.12 5432`.

**Livrable** : `~/P1/conf/lab-db/{postgresql.conf.diff,pg_hba.conf,redis.conf.diff,ufw.txt}`
(pour les `.conf` volumineux, garde un `diff -u` contre le fichier d'origine),
et `SECRETS.md`.

::: check
Critère de réussite : `check_PA_02.sh` passe sur `lab-db`, sur `lab-web`
(ports joignables) et sur `lab-adm` (ports refusés). Après
`sudo reboot` de `lab-db`, tout est revenu sans intervention.

```bash
bash ~/workbook/scripts/projects/P1/check_PA_02.sh
```
:::

---

### **PA.3** — L'API sous systemd, durcie

::: contexte
Le développeur lance l'API avec `flask run` dans un `tmux`. Tu en fais un
service : venv dédié, Gunicorn, unité systemd durcie, secrets hors du code,
journaux à leur place. Et tu prouves que le service ne peut pas faire plus que
ce qu'il doit.
:::

**Objectif** : `factura-api.service` actif, activé au boot, sous le compte
`factura`, joignable **seulement** sur `127.0.0.1:8000`, avec un score
`systemd-analyze security` inférieur à 4.0.

**Cahier des charges**

* Code dans `/opt/factura/api/`, venv dans `/opt/factura/venv/` créé avec
  `python3 -m venv` et `requirements.txt`. Tout appartient à `root`, en
  lecture seule pour `factura`.
* `/etc/factura/api.env` (`root:factura 0640`) contient `FACTURA_DB_URL`,
  `FACTURA_REDIS_URL` et ce dont Gunicorn a besoin. Aucun secret dans l'unité.
* Gunicorn : au moins 2 workers, bind `127.0.0.1:8000`, journal d'accès dans
  `/var/log/factura/api-access.log`, erreurs vers le journal systemd.
* Unité : `Type=notify` (Gunicorn sait le faire) ou `exec` ; `User=factura` ;
  `EnvironmentFile=` ; `Restart=on-failure` avec `RestartSec=5` ;
  `ExecReload=` qui recharge sans changer le PID principal (Gunicorn réagit à
  `SIGHUP`) ; démarrage après `network-online.target`.
* Durcissement : `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`,
  `PrivateTmp`, `PrivateDevices`, `ProtectKernelTunables`,
  `ProtectControlGroups`, `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`,
  `CapabilityBoundingSet=` vide, `SystemCallFilter=@system-service`,
  `MemoryMax=256M`, `LimitNOFILE=8192`. Le service doit **encore écrire**
  dans `/var/log/factura` : trouve la directive qui le permet proprement.
* `curl http://127.0.0.1:8000/health` renvoie 200 avec `db` et `redis` à
  `ok`. `curl http://10.10.10.11:8000/health` depuis `lab-adm` échoue.
* Preuve du durcissement : montre que `factura` ne peut pas écrire dans
  `/opt/factura` ni dans `/etc`, et que le `/tmp` du service est privé.

**Modules mobilisés** : 03, 04, 08 (unités, durcissement, `systemd-analyze
security`), 10 (venv, paquets `python3-venv`, `libpq`), 16 (journal).

**Indices**

* `psycopg[binary]` embarque `libpq` : pas besoin du client PostgreSQL pour
  l'API. Mais installe quand même `postgresql-client` sur `lab-web` : tu en
  auras besoin pour diagnostiquer.
* `LogsDirectory=factura` crée `/var/log/factura` avec le bon propriétaire et
  l'ajoute automatiquement aux chemins accessibles en écriture. Il le remet aussi au groupe du service (`factura:factura`, et non plus `adm`) à chaque démarrage : le check PA.1 l'admet, note-le dans le journal.
* `systemd-analyze security factura-api.service` liste chaque directive
  manquante avec son poids. Attaque par les plus lourdes.
* Si le service refuse de démarrer après le durcissement, `journalctl -u
  factura-api -n 30` et le code de sortie te disent laquelle des directives
  bloque : `226/NAMESPACE`, `EACCES`, `Operation not permitted`.

**Livrable** : `~/P1/conf/lab-web/factura-api.service`, `api.env` (avec les
secrets remplacés par `XXX`), et dans le journal : score de départ, score
final, et les trois directives qui ont le plus pesé.

::: check
Critère de réussite : `check_PA_03.sh` passe sur `lab-web` ; `systemctl
reload factura-api` ne change pas le PID principal ; après `sudo reboot`,
l'API répond sans intervention.

```bash
bash ~/workbook/scripts/projects/P1/check_PA_03.sh
```
:::

---

### **PA.4** — Le worker et la file

::: contexte
Créer une facture, c'est une ligne en base plus un travail dans une file Redis.
Le worker prend le travail, génère le PDF dans `/srv/factura/exports/`, et
marque la facture `exported`. Il doit tourner en permanence, survivre à une
coupure de Redis ou de PostgreSQL, et s'arrêter proprement.
:::

**Objectif** : `factura-worker.service` sous `factura`, durci, qui exporte une
facture en moins de 15 s, et qu'on peut arrêter sans perdre de travail.

**Cahier des charges**

* Code dans `/opt/factura/worker/`, même venv que l'API,
  `/etc/factura/worker.env` (`root:factura 0640`) avec `FACTURA_DB_URL`,
  `FACTURA_REDIS_URL`, `FACTURA_EXPORT_DIR=/srv/factura/exports`.
* Unité : `Type=exec`, `Restart=always`, `RestartSec=5`, arrêt par `SIGTERM`
  avec `TimeoutStopSec=30`, même durcissement que l'API **plus**
  `ReadWritePaths=/srv/factura/exports`. Pas de `After=factura-api.service`
  : le worker ne dépend pas de l'API, seulement de Redis et PostgreSQL, qui
  sont sur une autre machine (donc `After=network-online.target` suffit).
* Les PDF sont créés en `factura:factura 0640`. Trouve où se règle l'umask
  d'un service.
* Test bout en bout : `POST /invoices` → PDF présent → statut `exported`,
  vérifié avec `tools/factura-smoke.sh`. Les 5 factures du `seed.sql`, qui ne
  sont pas dans la file, sont exportées après un `--requeue`.
* Test de résilience : `sudo systemctl stop redis-server` sur `lab-db` pendant
  30 s, puis restart. Le worker **ne doit pas** redémarrer (`NRestarts` reste
  à 0) et reprend le travail tout seul. Même chose avec PostgreSQL.
* Test d'arrêt : crée 20 factures d'un coup (`factura-smoke.sh -n 20`) et
  lance `systemctl stop factura-worker` pendant le traitement. Aucune facture
  ne reste en `pending` sans être dans la file, et aucune n'est en `error`.
* `/metrics` de l'API expose `factura_worker_alive 1` (battement de cœur posé
  dans Redis par le worker) et `factura_queue_length 0` au repos.

**Modules mobilisés** : 08 (signaux, `Type=`, `Restart=`, umask),
16 (journalctl), 19 (méthode de diagnostic).

**Indices**

* `UMask=0027` dans `[Service]`. Le worker fait un `chmod 0640` de toute
  façon, mais l'umask protège aussi ses fichiers temporaires.
* Pour observer la file : `redis-cli -h 10.10.10.12 -a '...' LLEN factura:jobs`
  depuis `lab-web` (installe `redis-tools`). Pour voir les jobs perdus :
  `LRANGE factura:jobs:failed 0 -1`.
* `journalctl -u factura-worker -f` dans un terminal pendant les tests de
  résilience : tu dois voir « redis indisponible … nouvel essai » puis la
  reprise, sans « Started » ni « Stopped ».

**Livrable** : `~/P1/conf/lab-web/factura-worker.service`, `worker.env`
expurgé, et dans le journal : le résultat des trois tests (résilience Redis,
résilience PostgreSQL, arrêt en charge) avec les lignes de journal qui le
prouvent.

::: check
Critère de réussite : `check_PA_04.sh` passe sur `lab-web` (il crée une
facture et attend le PDF) ; `NRestarts` du worker vaut 0 après les tests.

```bash
bash ~/workbook/scripts/projects/P1/check_PA_04.sh
```
:::

---

### **PA.5** — nginx en frontal TLS, PKI de lab, en-têtes, journaux

::: contexte
Les postes de la PME doivent ouvrir `https://factura.lab.local` sans
avertissement. Il n'y a pas d'accès Internet entrant, donc pas de Let's
Encrypt : tu montes une autorité de certification interne sur `lab-adm`, tu
émets le certificat du frontal, et tu déploies la CA sur les postes (ici :
`lab-adm` et `lab-ops`).
:::

**Objectif** : nginx sert le front en HTTPS, relaie `/api/` vers Gunicorn,
n'expose rien d'autre, journalise utilement, et obtient un « A » sur les
en-têtes de sécurité.

**Cahier des charges**

* PKI dans `~/P1/pki/` sur `lab-adm` (mode 0700) : `ca.key` (0600, 10 ans,
  `CN=Ravel Lab CA`), `ca.crt` ; clé et certificat serveur pour
  `factura.lab.local` valables 825 jours, avec `subjectAltName` =
  `DNS:factura.lab.local, DNS:lab-web.lab.local, IP:10.10.10.11`, signés par
  la CA, `extendedKeyUsage = serverAuth`.
* `ca.crt` installé dans le magasin système de `lab-adm` **et** de `lab-ops`
  (`update-ca-certificates`) : `curl https://factura.lab.local/` passe sans
  `-k` depuis les deux.
* Sur `lab-web` : clé dans `/etc/nginx/ssl/factura.key` (`root:root 0600`),
  certificat dans `/etc/nginx/ssl/factura.crt`. La clé privée de la CA ne
  quitte **jamais** `lab-adm`.
* nginx : site `factura` dans `sites-available/` activé par lien symbolique,
  site `default` désactivé ; `server_tokens off` ; port 80 → `301` vers
  `https://factura.lab.local$request_uri` ; 443 en `TLSv1.2 TLSv1.3`
  uniquement, `ssl_prefer_server_ciphers off`, session cache ; en-têtes
  `Strict-Transport-Security` (1 an), `X-Content-Type-Options: nosniff`,
  `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`,
  `Content-Security-Policy: default-src 'self'` (le front est prévu pour) ;
  `location /` → `/srv/factura/www` ; `location /api/` → `proxy_pass
  http://127.0.0.1:8000/` avec `X-Forwarded-For`, `X-Forwarded-Proto`, `Host`,
  timeouts explicites ; `location /api/metrics` → `allow 10.10.10.14; deny
  all;` ; `client_max_body_size 1m`.
* Journaux : `access_log /var/log/nginx/factura.access.log factura;` avec un
  `log_format factura` qui ajoute `$request_time`, `$upstream_response_time`
  et `$upstream_status` au format combiné ; `error_log` dédié.
* `ufw` sur `lab-web` : deny entrant ; 22 depuis `10.10.10.10` ; 80 et 443
  depuis `10.10.10.0/24` ; rien d'autre. Le port 8000 reste inaccessible.
* `/etc/hosts` de `lab-adm` et `lab-ops` : `factura.lab.local` → 10.10.10.11
  (déjà fait en PA.1, vérifie).

**Modules mobilisés** : 12 (curl, DNS, `ss`), 15 (vhost nginx, en-têtes, `proxy_pass`), 18 (mini-PKI, ufw, TLS),
16 (formats de log).

**Indices**

* Un fichier d'extensions `openssl` de quatre lignes suffit pour le SAN et
  l'EKU ; `openssl x509 -req -extfile ext.cnf -extensions v3_srv ...`.
  Vérifie avec `openssl verify -CAfile ca.crt factura.crt` **avant** de
  déployer.
* Le transfert `lab-adm → lab-web` se fait en `scp` vers ton home puis
  `sudo install -m 0600 -o root ...` : ne fais jamais un `scp` direct vers
  `/etc` en root.
* `curl -sI https://factura.lab.local/ | grep -i strict` pour les en-têtes ;
  `openssl s_client -connect 10.10.10.11:443 -servername factura.lab.local
  </dev/null | openssl x509 -noout -dates -ext subjectAltName` pour le
  certificat réellement servi.
* Si `/api/health` renvoie 502, regarde `factura.error.log` : « connect()
  failed » = Gunicorn absent ; « upstream prematurely closed » = Gunicorn a
  planté sur la requête.

**Livrable** : `~/P1/conf/lab-web/nginx-factura.conf`, `~/P1/pki/ext.cnf`,
et un script `~/P1/bin/pa5-cert.sh` qui régénère et signe le certificat
serveur (tu l'utiliseras pour la rotation, dans le runbook).

::: check
Critère de réussite : `check_PA_05.sh` passe sur `lab-web` puis sur `lab-adm`.

```bash
bash ~/workbook/scripts/projects/P1/check_PA_05.sh
```
:::

---

### **PA.6** — Journaux centralisés et rotation

::: contexte
« Quand ça plante, on ne sait jamais sur quelle machine regarder. » Tu
centralises tout sur `lab-ops`, tu bornes ce que chaque machine garde, et tu
t'assures que rien ne se perd si `lab-ops` est injoignable pendant une heure.
:::

**Objectif** : tous les journaux (système, nginx, API, worker, PostgreSQL,
Redis) arrivent sur `lab-ops`, rangés par hôte, avec rotation partout.

**Cahier des charges**

* Sur les trois VM : journald **persistant** (`Storage=persistent`,
  `SystemMaxUse=200M`, `MaxRetentionSec=1month`) via un fichier dans
  `/etc/systemd/journald.conf.d/`, pas en modifiant `journald.conf`.
* `lab-ops` : rsyslog reçoit en TCP sur **10514** (`imtcp`), range dans
  `/var/log/remote/<hostname>/<programme>.log` via un template, ne mélange
  pas avec ses propres journaux ; `ufw` autorise 10514 depuis 10.10.10.11 et
  10.10.10.12 seulement ; rotation hebdomadaire, 8 semaines, compressée, de
  `/var/log/remote/*/*.log`.
* `lab-web` et `lab-db` : un fragment `/etc/rsyslog.d/90-forward.conf` envoie
  tout vers `@@10.10.10.14:10514` avec une **file d'attente disque**
  (`queue.type="LinkedList"`, `queue.filename`, `queue.saveOnShutdown`,
  `action.resumeRetryCount="-1"`). Test : coupe rsyslog sur `lab-ops` 2
  minutes, émets 50 lignes avec `logger` sur `lab-web`, relance : les 50
  lignes arrivent.
* nginx envoie `factura.access.log` **aussi** vers syslog
  (`access_log syslog:server=unix:/dev/log,facility=local5,tag=nginx_factura
  factura;`) pour qu'il parte sur `lab-ops` ; le fichier local reste.
* Rotation sur `lab-web` : `/etc/logrotate.d/factura` pour
  `/var/log/factura/*.log` (quotidien, 14 jours, compressé, `delaycompress`,
  `copytruncate` pour Gunicorn ou signal `USR1` — justifie ton choix) et
  `/var/log/nginx/factura.*.log` si la règle `nginx` du paquet ne les couvre
  pas déjà (vérifie).
* Depuis `lab-ops`, une requête d'exemple : « toutes les erreurs de
  `factura-api` de la dernière heure, sur `lab-web` » en une commande.

**Modules mobilisés** : 16 (journald, rsyslog, logrotate), 05 (`grep`, `awk`
sur les journaux), 12 (TCP), 18 ( pare-feu).

**Indices**

* Sur Ubuntu, journald relaie vers rsyslog (`ForwardToSyslog=yes`, module `imuxsock`) : ce qui arrive à
  `journalctl -u factura-api` passe aussi par rsyslog, donc part vers
  `lab-ops`. Vérifie avec `logger -t test` puis `grep test
  /var/log/remote/lab-web/test.log` sur `lab-ops`.
* Template rsyslog : `$template Remote,"/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log"`
  puis `if $fromhost-ip != "127.0.0.1" then { ?Remote; stop }` — écris-le en
  syntaxe RainerScript moderne (`template(name=... type="string" ...)`).
* `logrotate -d /etc/logrotate.d/factura` simule sans rien faire ;
  `logrotate -f` force une rotation pour tester le `postrotate`.

**Livrable** : `~/P1/conf/lab-ops/{05-collecteur.conf,logrotate-remote}`,
`~/P1/conf/lab-web/{90-forward.conf,logrotate-factura,journald-factura.conf}`,
et dans le journal : le résultat du test de coupure (50 lignes retrouvées).

::: check
Critère de réussite : `check_PA_06.sh` passe sur `lab-web`, `lab-db` puis
`lab-ops` (dans cet ordre : les deux premiers émettent une ligne de test que
le troisième cherche).

```bash
bash ~/workbook/scripts/projects/P1/check_PA_06.sh
```
:::

---

### **PA.7** — Sauvegardes nocturnes et restauration testée

::: contexte
« On a une sauvegarde » ne veut rien dire tant qu'on n'a pas restauré. Tu mets
en place deux sauvegardes (la base sur `lab-db`, les PDF sur `lab-web`),
poussées chaque nuit vers `lab-ops` par un compte à qui on ne peut faire
**que** ça, et tu restaures pour de vrai.
:::

**Objectif** : deux timers, une rotation, une copie distante, une restauration
prouvée, et une alerte si l'un des deux échoue.

**Cahier des charges**

* `lab-db` : script `/usr/local/sbin/factura-backup.sh` exécuté par
  `factura-backup.service` (`User=postgres`, `Type=oneshot`) déclenché par
  `factura-backup.timer` à **02:30** avec `RandomizedDelaySec=15min` et
  `Persistent=yes`. Le script : `pg_dump -Fc` de `factura` vers
  `/var/backups/factura/factura-<AAAAMMJJ-HHMM>.dump`, un `.sha256` à côté,
  supprime les dumps de plus de 7 jours, puis `rsync` le répertoire vers
  `backup@lab-ops:/srv/backups/factura/lab-db/`. Sortie en erreur (code ≠ 0)
  si l'une des étapes échoue, avec un message clair.
* `lab-web` : même mécanique sous `User=factura` pour
  `/srv/factura/exports` → `exports-<date>.tar.gz` + `.sha256`, vers
  `.../lab-web/`. Réfléchis : la racine `/var/backups/factura` de PA.1 a-t-elle
  le bon propriétaire pour ça ?
* `lab-ops` : le compte `backup` accepte les deux clés (une par machine
  émettrice) avec `restrict,from="10.10.10.12",command="/usr/bin/rrsync
  /srv/backups/factura/lab-db"` (et l'équivalent pour lab-web). Test : depuis
  `lab-db`, `ssh backup@lab-ops` doit être refusé ; `rsync` vers un autre
  dossier doit être refusé ; `rsync` vers le bon dossier passe.
* Les deux services ont `OnFailure=factura-alerte@%n.service` (l'unité
  d'alerte est écrite en PA.8 : pour l'instant, une unité minimale qui écrit
  dans `/var/log/factura/alertes.log` suffit — tu la remplaceras).
* Restauration testée sur `lab-db` : `pg_restore` du dernier dump dans une base
  `factura_restore` ; `SELECT count(*)` identique à la source ; la procédure
  est écrite pas à pas dans `~/P1/restore.md` **avec le temps mesuré**.
* Restauration testée sur `lab-web` : extraire l'archive dans `/tmp`, comparer
  avec `diff -r`. Note le temps.
* Question à traiter dans le journal : le dump est pris à 02:30, une facture
  créée à 02:31 est perdue si le disque meurt à 03:00. Quel est le RPO
  résultant, et que faudrait-il pour le réduire (deux pistes, sans les mettre
  en œuvre) ?

**Modules mobilisés** : 07 (script robuste, `set -euo pipefail`, `trap`),
14 (clés, `authorized_keys` restreint, `rrsync`), 17 (timers, `Persistent`,
`OnFailure`), 06 (tar), 05 (`find -mtime`), 15 (`pg_dump`/`pg_restore`).

**Indices**

* `pg_dump` en `peer` : le service tourne sous `postgres`, aucun mot de passe
  n'est nécessaire, aucun `.pgpass` à protéger.
* La clé SSH du compte `postgres` va dans `/var/lib/postgresql/.ssh/`
  (`ssh-keygen -t ed25519 -N ''`), avec `known_hosts` pré-rempli pour le nom **et** l'IP que tu utiliseras
  (`ssh-keyscan -H lab-ops 10.10.10.14`), sinon le premier rsync de nuit restera bloqué
  sur la question « Are you sure… ». Même chose pour `factura` sur `lab-web`
  — qui n'a pas de shell : `sudo -u factura ssh-keygen ...` marche quand
  même.
* `rrsync` est fourni par le paquet `rsync` d'Ubuntu 24.04
  (`/usr/bin/rrsync`). `rrsync -ro` pour un dépôt en lecture seule, ici tu
  veux l'écriture.
* `systemctl list-timers --all` montre le prochain déclenchement ;
  `systemctl start factura-backup.service` teste sans attendre 02:30.

**Livrable** : `~/P1/conf/lab-db/{factura-backup.sh,factura-backup.service,factura-backup.timer}`,
équivalents pour `lab-web`, `~/P1/conf/lab-ops/authorized_keys.backup`,
`~/P1/restore.md`.

::: check
Critère de réussite : `check_PA_07.sh` passe sur `lab-db`, `lab-web` et
`lab-ops` ; `factura_restore` a autant de factures que `factura`.

```bash
bash ~/workbook/scripts/projects/P1/check_PA_07.sh
```
:::

---

### **PA.8** — Supervision et alerting par timers

::: contexte
Pas encore de Prometheus (module 26). Mais la direction veut savoir **avant les
utilisateurs** que Factura est tombée, et savoir si la sauvegarde de la nuit a
eu lieu. Tu fais de la supervision avec ce que tu as : un script, un timer,
`node_exporter`, et un webhook local qui joue le rôle de Slack.
:::

**Objectif** : un contrôle toutes les 2 minutes depuis `lab-ops`, des mesures
exposées à `node_exporter`, et une alerte qui part sur le webhook quand un
contrôle ou un timer échoue.

**Cahier des charges**

* `prometheus-node-exporter` sur `lab-web`, `lab-db`, `lab-ops`, port 9100
  ouvert (`ufw`) uniquement depuis 10.10.10.14 sur les deux premiers.
* `lab-ops` : `tools/factura-webhook.py` servicifié en
  `factura-webhook.service` (`DynamicUser=yes` ou compte dédié, écoute
  `127.0.0.1:9999`, journal dans `/var/log/factura/webhook.log` — pense à
  `LogsDirectory=`).
* Unité modèle `factura-alerte@.service` sur `lab-ops` (et une copie
  équivalente sur `lab-web` et `lab-db` qui **envoie au webhook de lab-ops**
  — comment, puisque 9999 n'écoute que sur localhost ? Deux options : ouvrir
  9999 sur 10.10.10.14 aux deux émetteurs, ou relayer par SSH. Choisis,
  justifie) : reçoit `%i` (le nom de l'unité en échec), écrit une ligne
  horodatée dans `/var/log/factura/alertes.log` et POSTe un JSON
  `{"host":..., "unit":.. ., "result":..., "since":...}` sur le webhook.
* `/usr/local/sbin/factura-healthcheck.sh` sur `lab-ops`, lancé par
  `factura-healthcheck.timer` toutes les 2 minutes (`OnUnitActiveSec`,
  `AccuracySec=30s`), avec `OnFailure=factura-alerte@%n.service` sur le
  service. Il vérifie : `https://factura.lab.local/api/health` en 200 avec
  `status: ok` (via la CA système, pas `-k`) ; `factura_queue_length` < 100
  et `factura_worker_alive` = 1 sur `/api/metrics` ; âge de la dernière
  sauvegarde dans `/srv/backups/factura/lab-db/` < 26 h ; espace libre de
  `/srv/backups` > 15 %. Il écrit `factura_health_up`,
  `factura_backup_age_seconds{host="lab-db"}`, `factura_backup_age_seconds{host="lab-web"}`,
  `factura_queue_length` et `factura_check_duration_seconds` dans
  `/var/lib/prometheus/node-exporter/factura.prom` (écriture **atomique** :
  fichier temporaire puis `mv`), puis sort en 1 si un contrôle échoue.
* Anti-tempête : une même alerte ne repart pas plus d'une fois toutes les 15
  minutes (un fichier d'état par unité sous `/var/lib/factura/`).
* Preuve : arrête `factura-api` sur `lab-web` 3 minutes. L'alerte doit arriver
  dans `webhook.log` en moins de 4 minutes, et **une seule fois**. Relance,
  et vérifie que `factura_health_up` repasse à 1.
* Preuve 2 : simule un échec de `factura-backup.service` sur `lab-db`
  (`systemctl start` avec un dossier de destination rendu inaccessible) et
  vérifie que l'alerte arrive sur `lab-ops`.

**Modules mobilisés** : 16 (`node_exporter`, textfile collector), 17 (timers
monotones, `OnFailure`, unités modèles), 07 (script, codes de sortie), 12
(curl, timeouts).

**Indices**

* Le textfile collector d'Ubuntu lit `/var/lib/prometheus/node-exporter/*.prom`
  par défaut (voir `/etc/default/prometheus-node-exporter`). Le fichier doit
  être lisible par `prometheus`.
* `curl --fail --max-time 5 -s` : sans `--max-time`, un frontal qui ne répond
  pas bloque ton healthcheck jusqu'au timeout du timer.
* `systemctl show -p Result,ExecMainStatus factura-healthcheck.service`
  depuis l'unité d'alerte donne le résultat de l'unité en échec.
* Pour la copie d'alerte sur `lab-web`/`lab-db`, la solution la plus simple
  et la plus honnête est d'ouvrir 9999 sur 10.10.10.14 aux deux émetteurs.
  Note dans le journal ce que ça implique (un webhook sans authentification
  sur le LAN).

**Livrable** : `~/P1/conf/lab-ops/{factura-healthcheck.sh,factura-healthcheck.service,factura-healthcheck.timer,factura-alerte@.service,factura-webhook.service}`
et dans le journal : la ligne de `webhook.log` reçue lors de la preuve, avec
l'horodatage de l'arrêt de l'API pour calculer le délai de détection.

::: check
Critère de réussite : `check_PA_08.sh` passe sur `lab-ops`, `lab-web` et
`lab-db` ; `curl -s 127.0.0.1:9100/metrics | grep factura_` sur `lab-ops`
renvoie les cinq métriques.

```bash
bash ~/workbook/scripts/projects/P1/check_PA_08.sh
```
:::

---

### **PA.9** — Durcissement et audit

::: contexte
L'expert-comptable de la PME demande « une attestation de sécurité » avant de
laisser les factures sur cette plateforme. Tu n'as pas de RSSI : tu fais un
audit honnête, tu corriges ce qui se corrige, tu documentes ce qui reste.
:::

**Objectif** : SSH verrouillé, sudo restreint pour l'exploitant, fail2ban sur
SSH et nginx, sysctl durcis, mises à jour automatiques, `lynis` à plus de 65,
et un rapport d'audit qui dit ce qui reste ouvert et pourquoi.

**Cahier des charges**

* SSH sur les trois VM : `PasswordAuthentication no`, `PermitRootLogin no`,
  `X11Forwarding no`, `AllowGroups ssh-users` (crée le groupe, mets-y
  `mathieu` et `pme-ops` sur `lab-web`, `mathieu` ailleurs), `MaxAuthTries 3`,
  bannière. Dans un fragment `/etc/ssh/sshd_config.d/`, validé par `sshd -t`
  **avant** tout restart, avec une session de secours ouverte.
* Compte `pme-ops` sur `lab-web` (avec clé SSH, sans mot de passe) et fichier
  `/etc/sudoers.d/pme-ops` qui l'autorise, sans mot de passe, à :
  `systemctl status|restart|reload` de `factura-api` et `factura-worker`,
  `journalctl -u factura-*`, `/usr/local/sbin/factura-backup.sh`, et **rien
  d'autre**. Preuve : `sudo -u pme-ops sudo -l`, puis tentative de
  `sudo systemctl restart nginx` refusée. Attention à la faille classique :
  `journalctl` sans restriction permet-il d'ouvrir un shell ?
* `fail2ban` sur les trois VM : `jail.local` avec `ignoreip = 127.0.0.1/8
  10.10.10.10`, jail `sshd` (`maxretry 3`, `bantime 1h`), et sur `lab-web` une
  jail maison `nginx-factura-4xx` avec un filtre qui bannit 10 minutes une IP
  qui produit 20 réponses 401/403/404 en 1 minute sur
  `/var/log/nginx/factura.access.log`. Teste ton filtre avec `fail2ban-regex`
  puis en vrai depuis `lab-ops` (pas depuis `lab-adm`, qui est en `ignoreip`)
  et débannis-toi.
* `/etc/sysctl.d/60-factura-hardening.conf` sur les trois VM avec au moins :
  `net.ipv4.tcp_syncookies=1`, `net.ipv4.conf.all.accept_redirects=0`,
  `net.ipv4.conf.all.send_redirects=0`, `net.ipv4.conf.all.log_martians=1`,
  `kernel.dmesg_restrict=1`, `kernel.kptr_restrict=2`,
  `kernel.yama.ptrace_scope=1`, `fs.protected_regular=2`.
* `unattended-upgrades` activé pour les mises à jour de sécurité, avec
  redémarrage automatique **désactivé** (tu veux choisir quand `lab-db`
  redémarre) et un mail/ligne de log en cas d'échec.
* Permissions : aucun fichier world-writable sous `/opt/factura`,
  `/srv/factura`, `/etc/factura` ; `/opt/factura` entièrement à `root` ;
  aucun secret lisible par others ; `PGDATA` en 0700.
* `sudo lynis audit system` sur `lab-web` et `lab-db` : note l'index de
  départ, traite au moins 8 suggestions, relance, et atteins **65 ou plus**.
* Rapport `~/P1/audit.md` : index avant/après par machine, les suggestions
  traitées, celles **volontairement** laissées (avec la raison : coût,
  risque, hors périmètre), et les trois risques résiduels que tu signalerais à
  la direction.

**Modules mobilisés** : 04 (sudoers), 14 (sshd), 18 (fail2ban, sysctl,
lynis, unattended-upgrades, AppArmor), 03 (audit de permissions).

**Indices**

* `journalctl` a un pager : `sudo journalctl` sans `--no-pager` donne un
  `less`, et `less` sait lancer `!sh`. Regarde `SYSTEMD_PAGER`, l'option
  `NOEXEC`, ou une petite commande enveloppe dans `/usr/local/bin/`.
* Filtre fail2ban : `failregex = ^<HOST> - .* "(GET|POST) /api/[^"]*" (401|403|404) `
  à adapter à ton `log_format`. `fail2ban-regex /var/log/nginx/factura.access.log
  /etc/fail2ban/filter.d/nginx-factura-4xx.conf` doit montrer des « matched ».
* Sur Ubuntu, `dpkg-reconfigure -plow unattended-upgrades` active le
  périodique ; le comportement est dans
  `/etc/apt/apt.conf.d/50unattended-upgrades`.
* `lynis show details <TEST-ID>` explique chaque suggestion. Les plus
  rentables : bannière SSH, `umask` par défaut, `/tmp` séparé ou `nodev`, comptes
  sans expiration, `auditd`, `sysstat`.

**Livrable** : `~/P1/conf/*/60-factura-hardening.conf`, `sshd-factura.conf`,
`sudoers-pme-ops`, `jail.local`, `nginx-factura-4xx.conf`, et `~/P1/audit.md`.

::: check
Critère de réussite : `check_PA_09.sh` passe sur `lab-web` et `lab-db` (lance
le check avec `sudo`, il lit `sshd -T` et le rapport lynis).

```bash
sudo bash ~/workbook/scripts/projects/P1/check_PA_09.sh
```
:::

---

### **PA.10** — Runbook et exercice d'incident

::: contexte
Tu pars en congés. L'exploitant `pme-ops` et un prestataire qui ne connaît pas
la plateforme doivent pouvoir la faire tourner. Tu écris le runbook, puis tu le
mets à l'épreuve : trois incidents (section A.3), à résoudre en te servant
**uniquement** du runbook et des outils en place, chronomètre en main.
:::

**Objectif** : un runbook exploitable par quelqu'un d'autre, trois incidents
résolus, trois post-mortems, et le runbook amélioré par ce que les incidents
t'ont appris.

**Cahier des charges**

* `~/P1/runbook.md` (120 lignes minimum, en Markdown, sections `#`/`##`) :
  1. **Architecture** : le schéma de A.1, les IP, les ports, les comptes ;
  2. **Démarrage / Arrêt** : ordre de démarrage et d'arrêt des composants, et
     pourquoi cet ordre ; commandes exactes ;
  3. **Secrets** : où ils sont, qui y accède, comment les faire tourner (mot
     de passe PostgreSQL, Redis, certificat) — procédure complète pour le
     certificat avec `pa5-cert.sh` ;
  4. **Sauvegarde / Restauration** : où, quand, comment vérifier, comment
     restaurer (le contenu de `restore.md`), RPO et RTO mesurés ;
  5. **Supervision** : où regarder (`webhook.log`, `alertes.log`,
     `/var/log/remote`, `/metrics`), que signifie chaque alerte, seuils ;
  6. **Incidents** : pour chaque symptôme courant (site en timeout, 502, 503
     degraded, factures en error, alerte sauvegarde, disque plein) une
     **checklist de diagnostic** en 5 à 8 commandes, et le correctif usuel ;
  7. **Contacts et escalade** : fictifs, mais structurés (qui appeler pour
     quoi, en combien de temps).
* Les commandes du runbook sont copiables telles quelles (vrais chemins, vrais
  noms d'unités, vraies IP).
* Exercice : lance les trois `break_PA_YY.sh` (A.3) **un par un**, dans
  l'ordre, avec un snapshot avant chacun. Pour chaque incident : chronomètre
  du symptôme à la remise en service, journal des commandes tapées, puis
  post-mortem `~/P1/incidents/INC-A<n>-<slug>.md` avec les sections
  Résumé, Impact, Chronologie, Cause racine, Correctif, Prévention (le
  modèle du module 19).
* Après les trois incidents : au moins une modification du runbook par
  incident (une commande qui manquait, un seuil, une vérification à ajouter).
  Marque-les dans un `## Historique` en fin de document.
* Toutes les factures passées en `error` pendant les incidents sont remises
  en file et exportées. Aucune unité en échec ne subsiste. Les
  `check_PA_01` à `09` passent tous à nouveau.

**Modules mobilisés** : 19 (méthode, post-mortem), tous les autres.

**Indices**

* Un bon runbook se lit à 3 h du matin par quelqu'un de fatigué : commandes
  d'abord, explications ensuite, jamais l'inverse.
* Pour chaque symptôme, la checklist commence toujours par la même question :
  **quelle couche** (réseau, TLS, nginx, API, worker, données) et **depuis
  où** (lab-adm, lab-web local, lab-ops). Le module 19 t'a donné la méthode
  ; ici tu l'écris pour quelqu'un d'autre.
* `script -a ~/P1/incidents/INC-A1.typescript` enregistre ta session : tu auras
  la chronologie exacte pour le post-mortem.

**Livrable** : `~/P1/runbook.md`, `~/P1/incidents/INC-A1-*.md`,
`INC-A2-*.md`, `INC-A3-*.md`.

::: check
Critère de réussite : `check_PA_10.sh` passe sur `lab-adm` (documents) et sur
les trois autres VM (plateforme saine, aucune facture en erreur).

```bash
bash ~/workbook/scripts/projects/P1/check_PA_10.sh
```
:::

---

## A.3 Incidents

::: attention
Avant chaque incident : `qm snapshot <vmid> avant-incA<n>`. Les scripts
sauvegardent ce qu'ils cassent dans `/root/.breakfix-backup/`, mais le
snapshot est ta vraie sortie de secours. Un seul incident à la fois. Résous
avec le runbook, pas avec le corrigé.
:::

### **INC-A1** — « Le site dit "degraded" et les factures ne s'enregistrent plus »

**Contexte.** Lundi 8 h 10. Le vendredi soir, un collègue a « durci un peu la
base » avant de partir en week-end. Il est injoignable.

**Symptôme.** `https://factura.lab.local/` affiche « état : degraded »,
`/api/health` répond 503. Le formulaire de création renvoie une erreur. Sur
`lab-db`, PostgreSQL est `active (running)`, `ss` montre 5432 en écoute,
`sudo -u postgres psql -d factura` fonctionne. Le worker de `lab-web` se
plaint aussi.

**Interdit.** Réinstaller PostgreSQL, restaurer la sauvegarde, redémarrer
`lab-db`.

**Objectif.** Remise en service, cause racine identifiée, et une mesure pour
que « durcir un peu » ne se reproduise plus sans trace.

```bash
# sur lab-db
sudo bash ~/workbook/scripts/projects/P1/break_PA_01.sh
```

::: repondre
lignes: 8
:::

---

### **INC-A2** — « Les factures passent en erreur, aucun PDF »

**Contexte.** Mardi 14 h. Un collègue a « remis les droits au propre » sur
`lab-web` ce matin après avoir vu un dossier « bizarre ».

**Symptôme.** Les nouvelles factures apparaissent dans l'interface avec le
statut `error`. Aucun PDF n'est produit. `factura-worker` est `active
(running)` et ne redémarre pas, `/api/health` est `ok`, `factura_queue_length`
vaut 0, `factura_worker_alive` vaut 1. La supervision **n'a rien vu**.

**Interdit.** Redéployer le worker, modifier le code Python, toucher à Redis.

**Objectif.** Remise en service, **récupération des factures en erreur** (elles
doivent finir en `exported`), cause racine, et une amélioration de la
supervision pour qu'elle voie ce type de panne la prochaine fois.

```bash
# sur lab-web
sudo bash ~/workbook/scripts/projects/P1/break_PA_02.sh
```

::: repondre
lignes: 8
:::

---

### **INC-A3** — « Le site ne répond plus depuis les postes »

**Contexte.** Jeudi 9 h 30. Hier, une maintenance réseau et un renouvellement
de certificat ont eu lieu le même jour. Les deux personnes concernées se
renvoient la balle.

**Symptôme.** Depuis `lab-adm` (et tous les postes), `curl
https://factura.lab.local/` reste bloqué puis échoue avec le code 28
(timeout). Sur `lab-web`, nginx est `active`, `curl -k https://127.0.0.1/`
répond 200, le certificat servi est valide. Sur `lab-ops`, la supervision
remonte `factura_health_up 0` et une alerte est partie.

**Interdit.** Redémarrer `lab-web`, réinstaller nginx, désactiver le pare-feu
(`ufw disable`) même « pour tester ».

**Objectif.** Remise en service en moins de 15 minutes, cause racine, et une
règle d'exploitation pour les « règles temporaires ».

```bash
# sur lab-web
sudo bash ~/workbook/scripts/projects/P1/break_PA_03.sh
```

::: repondre
lignes: 8
:::

---

## A.4 Grille d'évaluation

Note sur 100. Un jalon dont le `check` ne passe pas ne peut pas obtenir plus
de la moitié de ses points, quelle que soit la qualité du livrable.

| Jalon | Points | Ce qui est noté |
|---|---|---|
| PA.1 Terrain | 5 | check, script idempotent, journal commencé |
| PA.2 Données et réseau | 12 | check ; LV + fstab ; pg_hba minimal ; politique Redis justifiée ; reboot sans intervention |
| PA.3 API | 12 | check ; score sécurité < 4 ; secrets protégés ; reload sans changement de PID ; journal des directives |
| PA.4 Worker | 8 | check ; trois tests de résilience documentés avec preuves |
| PA.5 nginx et TLS | 12 | check sur web et adm ; PKI propre (clé CA jamais déployée) ; en-têtes ; script de rotation |
| PA.6 Journaux | 8 | check sur les trois VM ; test de coupure réussi ; requête d'exemple |
| PA.7 Sauvegardes | 12 | check sur les trois VM ; clé restreinte prouvée ; restauration chronométrée ; réponse RPO |
| PA.8 Supervision | 10 | check ; alerte reçue une seule fois ; délai de détection mesuré ; anti-tempête |
| PA.9 Durcissement | 10 | check ; lynis ≥ 65 ; pme-ops sans échappatoire ; audit honnête (risques résiduels) |
| PA.10 Runbook et incidents | 11 | check ; runbook utilisable par un tiers ; 3 post-mortems ; runbook amélioré |

Pénalités transverses (jusqu'à −10) : secret en clair dans un livrable de
`~/P1/conf/`, `chmod 777` quelque part, service tournant en root sans raison,
règle pare-feu « Anywhere » sur un port interne, journal de bord vide.

Bonus (jusqu'à +5) : une amélioration non demandée mais justifiée (par exemple
TLS entre l'API et PostgreSQL, `systemd` watchdog sur le worker, chiffrement
des sauvegardes sur `lab-ops`, test de restauration automatisé par timer).

---

## A.5 Pour l'entretien

Ce que ce projet t'a appris à dire — et à défendre — en entretien :

1. **« J'ai hébergé une application multi-services à la main avant de
   l'automatiser. »** Tu sais ce qu'un `Dockerfile` remplace (venv, chemins,
   utilisateur, `ENTRYPOINT` = ton `ExecStart`) et ce qu'un rôle Ansible
   remplace (ton `pa1-terrain.sh`, tes fichiers dans `~/P1/conf/`). Tu peux
   expliquer *pourquoi* ces outils existent, pas seulement les utiliser.
2. **« Un service ne tourne pas en root, ne voit que ce dont il a besoin, et je
   peux le prouver. »** `systemd-analyze security`, `ProtectSystem=strict`,
   `ReadWritePaths=`, `RestrictAddressFamilies=` : tu as un score, un avant
   et un après, et tu sais quelle directive a cassé quoi.
3. **« Une sauvegarde n'existe que si elle a été restaurée. »** Tu as un temps
   de restauration mesuré, un RPO chiffré, et une réponse à « et si le
   compte de sauvegarde est compromis ? » (`restrict`, `rrsync`, `from=`).
4. **« Le pare-feu est fermé par défaut, et chaque ouverture a une source. »**
   Tu as un tableau de flux, tu as testé chaque règle dans les deux sens, et
   tu as vécu un incident causé par une règle « temporaire ».
5. **« La supervision doit voir les pannes silencieuses. »** INC-A2 t'a montré
   qu'un service `active (running)` avec `/health` à `ok` peut ne plus rien
   produire. Tu sais expliquer la différence entre *liveness*, *readiness* et
   une métrique métier (`factura_invoices_total{status="error"}`).
6. **« J'ai écrit un runbook et je l'ai testé sur de vrais incidents. »** Tu
   peux raconter les trois incidents en format post-mortem : symptôme, durée,
   cause racine, ce qui a manqué, ce que tu as changé.
7. **« Je sais ce que je n'ai pas fait. »** Pas de TLS entre l'API et la base,
   un webhook sans authentification, des secrets dans des fichiers `.env`,
   pas de haute disponibilité : tu as un rapport d'audit avec des risques
   résiduels assumés. C'est plus crédible qu'un « tout est sécurisé ».
8. **« Voici ce que je demanderais aux développeurs. »** Une connexion par
   requête sans pool, des compteurs de métriques dans Redis, pas de
   `sd_notify` dans le worker, une file « au plus une fois » : tu as lu le
   code que tu héberges et tu as des remarques d'exploitant.
