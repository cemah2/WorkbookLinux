# Projet A — Corrigé

Ce corrigé donne une **solution de référence** : ce n'est pas la seule
possible. Les checks vérifient le résultat, pas la méthode. Chaque jalon
rappelle l'énoncé en une ligne, donne les commandes dans l'ordre, les fichiers
complets, puis les blocs `::: pourquoi` sur les choix d'architecture et
`::: piege` sur ce qui casse le plus souvent.

Conventions du corrigé : les mots de passe sont `ChangeMe-Db-2026` (PostgreSQL)
et `ChangeMe-Redis-2026` (Redis). Remplace-les. Les commandes se lancent dans
le home de `mathieu`, sauf mention contraire.

---

## A.2 Jalons — corrigé

### **PA.1** — Terrain, comptes de service, arborescence

*Résoudre les noms, créer les comptes de service et l'arborescence FHS sur
les quatre VM, avec un script idempotent.*

Sur les quatre VM, `/etc/hosts` :

```
127.0.0.1   localhost
10.10.10.10 lab-adm lab-adm.lab.local
10.10.10.11 lab-web lab-web.lab.local factura.lab.local
10.10.10.12 lab-db  lab-db.lab.local
10.10.10.14 lab-ops lab-ops.lab.local
```

Le script `~/P1/bin/pa1-terrain.sh`, à copier et lancer sur chaque VM :

```bash
#!/usr/bin/env bash
# pa1-terrain.sh — comptes de service et arborescence Factura (idempotent)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "sudo requis" >&2; exit 1; }
HOST="$(hostname -s)"

mk() { install -d -o "$2" -g "$3" -m "$4" "$1"; }   # mk <dir> <u> <g> <m>

case "$HOST" in
lab-web)
  getent group factura >/dev/null || groupadd -r factura
  getent passwd factura >/dev/null || useradd -r -g factura -M \
    -d /srv/factura -s /usr/sbin/nologin -c "Factura service" factura
  mk /opt/factura            root    root    0755
  mk /etc/factura            root    factura 0750
  mk /srv/factura            root    root    0755
  mk /srv/factura/www        root    root    0755
  mk /srv/factura/exports    factura factura 0750
  mk /var/log/factura        factura adm     0750
  mk /var/lib/factura        factura factura 0750
  mk /var/backups/factura    factura factura 0750
  ;;
lab-db)
  mk /etc/factura            root    root    0750
  mk /var/log/factura        root    adm     0750
  ;;
lab-ops)
  getent group backup >/dev/null || groupadd -r backup
  getent passwd backup >/dev/null || useradd -r -g backup -M \
    -d /srv/backups -s /bin/sh -c "Depot de sauvegardes" backup
  # Ubuntu fournit déjà backup (uid 34, /var/backups, nologin) : on l'aligne
  usermod -d /srv/backups -s /bin/sh backup
  mk /srv/backups            root    root    0755
  mk /srv/backups/factura    backup  backup  0750
  mk /var/log/factura        root    adm     0750
  ;;
esac
echo "terrain OK sur $HOST"
```

Sur `lab-adm` : `install -d -m 0700 ~/P1/pki` et première ligne du journal.

::: pourquoi
Le FHS sépare quatre choses que les débutants mélangent dans un seul
`/home/app` : le **code** (`/opt/factura`, à root, jamais modifiable par le
service qui l'exécute — sinon une faille dans l'API permet de réécrire l'API),
la **configuration** (`/etc/factura`, lisible par le groupe du service mais
pas au-delà), les **données servies** (`/srv/factura`) et l'**état variable**
(`/var/log`, `/var/lib`, `/var/backups`). Cette séparation n'est pas
esthétique : c'est elle qui rend possible `ProtectSystem=strict` au jalon 3
(tout est en lecture seule sauf les chemins listés) et qui rend les
sauvegardes évidentes (on sauvegarde `/srv` et `/var/lib`, pas `/opt`).

`/var/log/factura` au groupe `adm` : sur Ubuntu, `mathieu` est dans `adm`, ce
qui lui permet de lire les journaux sans `sudo`, exactement comme pour
`/var/log/syslog`. C'est le modèle de la distribution, autant le suivre.

Le compte `backup` sur `lab-ops` a un shell, contrairement à `factura` : SSH
exécute la commande forcée de `authorized_keys` via `$SHELL -c`, un
`nologin` la refuserait. La restriction vient de la clé (PA.7), pas du shell. Or Ubuntu livre déjà un compte `backup` (uid 34, home `/var/backups`, shell `nologin`) : le `getent` le trouve, le `useradd` ne joue pas, d'où le `usermod` explicite (sans effet s'il est déjà aligné, donc idempotent).
:::

::: piege
`useradd factura` sans `-r` crée un uid ≥ 1000 : le compte apparaît sur l'écran
de connexion, entre dans les quotas et les politiques « utilisateurs » de
`lynis`. `useradd -r` sans `-M` sur Ubuntu ne crée pas le home non plus, mais
c'est l'inverse sur Rocky (`CREATE_HOME` diffère) : `-M` explicite évite la
surprise.
:::

---

### **PA.2** — PostgreSQL 16, Redis, réseau et pare-feu

*Sur `lab-db` : LV dédié aux données, PostgreSQL 16 et Redis en écoute
restreinte et authentifiée, schéma chargé, pare-feu fermé.*

**1. Le volume logique, avant PostgreSQL**

```bash
sudo pvcreate /dev/sdb
sudo vgcreate vg_data /dev/sdb
sudo lvcreate -L 4G -n lv_pg vg_data
sudo mkfs.ext4 -L pgdata /dev/vg_data/lv_pg
sudo install -d -m 0755 /var/lib/postgresql
UUID=$(sudo blkid -s UUID -o value /dev/vg_data/lv_pg)
echo "UUID=$UUID /var/lib/postgresql ext4 defaults,noatime 0 2" \
  | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /var/lib/postgresql
findmnt /var/lib/postgresql
```

**2. PostgreSQL**

```bash
sudo apt update && sudo apt install -y postgresql-16 postgresql-client-16
sudo chown postgres:postgres /var/lib/postgresql
pg_lsclusters      # 16 main 5432 online postgres /var/lib/postgresql/16/main
```

`/etc/postgresql/16/main/postgresql.conf`, lignes modifiées (garde un
`diff -u` dans `~/P1/conf/lab-db/`) :

```ini
listen_addresses = 'localhost,10.10.10.12'
password_encryption = scram-sha-256
log_line_prefix = '%m [%p] %q%u@%d '
log_connections = on
```

`/etc/postgresql/16/main/pg_hba.conf`, en remplaçant le bloc final :

```
# TYPE  DATABASE   USER          ADDRESS          METHOD
local   all        postgres                       peer
local   all        all                            peer
host    all        all           127.0.0.1/32     scram-sha-256
host    all        all           ::1/128          scram-sha-256
# application Factura, uniquement depuis lab-web
host    factura    factura_app   10.10.10.11/32   scram-sha-256
```

```bash
sudo systemctl restart postgresql@16-main.service    # listen_addresses
sudo -u postgres psql <<'SQL'
CREATE ROLE factura_app LOGIN PASSWORD 'ChangeMe-Db-2026';
CREATE DATABASE factura OWNER factura_app;
SQL
cd /usr/local/src/factura/sql
PGPASSWORD='ChangeMe-Db-2026' psql -h 127.0.0.1 -U factura_app -d factura \
  -f schema.sql -f seed.sql
sudo -u postgres psql -c 'SHOW listen_addresses;'
ss -ltnp 'sport = :5432'
```

**3. Redis**

```bash
sudo apt install -y redis-server redis-tools
```

`/etc/redis/redis.conf`, lignes modifiées :

```ini
bind 127.0.0.1 10.10.10.12
protected-mode yes
requirepass ChangeMe-Redis-2026
maxmemory 128mb
maxmemory-policy noeviction
appendonly yes
appendfsync everysec
```

```bash
sudo systemctl restart redis-server && sudo systemctl enable redis-server
redis-cli -h 10.10.10.12 ping                   # (error) NOAUTH ...
redis-cli -h 10.10.10.12 -a ChangeMe-Redis-2026 CONFIG GET maxmemory-policy
```

**4. Pare-feu**

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 10.10.10.10 to any port 22 proto tcp comment 'ssh adm'
sudo ufw allow from 10.10.10.11 to any port 5432 proto tcp comment 'pg web'
sudo ufw allow from 10.10.10.11 to any port 6379 proto tcp comment 'redis web'
sudo ufw enable
sudo ufw status numbered
```

Tests croisés : depuis `lab-web`, `nc -zv -w2 10.10.10.12 5432` répond
`succeeded` ; depuis `lab-adm`, il expire. Puis `sudo reboot` de `lab-db` et
`pg_lsclusters` + `systemctl is-active redis-server`.

::: pourquoi
**Le LV avant l'installation** : le paquet `postgresql-16` crée le cluster
`16/main` là où `/var/lib/postgresql` se trouve. Si c'est déjà un point de
montage, le cluster naît sur le bon disque et on n'a jamais à le déplacer. Le
jour où la base grossit, `lvextend -r` agrandit en ligne. Le jour où on veut
un snapshot cohérent pour la sauvegarde, `lvcreate -s` est possible. Et une
base qui remplit son disque ne remplit pas `/`.

**`scram-sha-256` et une seule règle `host`** : `pg_hba.conf` est lu de haut
en bas, première règle qui correspond gagne. Une règle `host all all
0.0.0.0/0 md5` « pour que ça marche » donne à toute machine du réseau le
droit d'essayer tous les comptes. La règle unique `factura factura_app
10.10.10.11/32` dit exactement qui, quoi, d'où. Le pare-feu redit la même
chose une couche plus bas : deux verrous indépendants, c'est voulu.

**`factura_app` propriétaire de sa base** : le schéma est joué par
`factura_app`, donc les tables lui appartiennent et aucun `GRANT` n'est à
gérer. Dans un système plus gros, on sépare un rôle propriétaire (migrations)
d'un rôle applicatif (`SELECT/INSERT/UPDATE` seulement) : c'est la remarque
à faire aux développeurs, pas à implémenter ici.

**`noeviction`** : `allkeys-lru` (défaut de certaines images) supprime
silencieusement les clés les moins utilisées quand `maxmemory` est atteint —
donc des jobs de la file. Avec `noeviction`, Redis renvoie une erreur à
l'API sur `LPUSH` : la facture est créée en base mais pas mise en file, ce
qui se voit (`status=pending` sans job) et se rattrape par `requeue`. Une
erreur visible vaut mieux qu'une perte silencieuse.
:::

::: piege
* `listen_addresses` demande un **restart** ; un `reload` l'ignore sans
  message. `SHOW listen_addresses;` dit la vérité.
* `bind 10.10.10.12` seul (sans `127.0.0.1`) casse `redis-cli` local et le
  check ; `bind 0.0.0.0` avec `requirepass` est « sécurisé » mais expose le
  service au brute force. Les deux adresses, pas plus.
* `ufw enable` sur une session SSH sans règle 22 : tu es dehors. La règle
  d'abord, `enable` ensuite, et la console Proxmox ouverte.
* `chown postgres /var/lib/postgresql` après le montage : le point de montage
  fraîchement monté appartient à root ( et `lost+found` aussi).
  `pg_createcluster`, lancé en root par le paquet, crée quand même `16/main`, mais ce répertoire est le **home** de `postgres` : sans le `chown`, la clé SSH de PA.7 (`/var/lib/postgresql/.ssh`) ne pourra pas y être créée.
:::

---

### **PA.3** — L'API sous systemd, durcie

*Sur `lab-web` : venv, Gunicorn sur 127.0.0.1:8000, unité systemd durcie
(score < 4.0), secrets dans `/etc/factura/api.env`.*

```bash
sudo apt install -y python3-venv python3-pip postgresql-client redis-tools jq
sudo install -d -m 0755 /opt/factura/api
sudo cp /usr/local/src/factura/api/factura_api.py /opt/factura/api/
sudo cp /usr/local/src/factura/requirements.txt /opt/factura/
sudo python3 -m venv /opt/factura/venv
sudo /opt/factura/venv/bin/pip install --no-cache-dir \
  -r /opt/factura/requirements.txt
sudo chown -R root:root /opt/factura
sudo find /opt/factura -type d -exec chmod 0755 {} +
```

`/etc/factura/api.env` (`sudo install -m 0640 -o root -g factura`) :

```ini
FACTURA_DB_URL=postgresql://factura_app:ChangeMe-Db-2026@lab-db:5432/factura
FACTURA_REDIS_URL=redis://:ChangeMe-Redis-2026@lab-db:6379/0
FACTURA_QUEUE=factura:jobs
FACTURA_LOG_LEVEL=INFO
PYTHONDONTWRITEBYTECODE=1
PYTHONUNBUFFERED=1
```

`/etc/systemd/system/factura-api.service` :

```ini
[Unit]
Description=Factura API (Gunicorn)
Documentation=file:///opt/factura/api/factura_api.py
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=factura
Group=factura
WorkingDirectory=/opt/factura/api
EnvironmentFile=/etc/factura/api.env
ExecStart=/opt/factura/venv/bin/gunicorn \
  --workers 2 --bind 127.0.0.1:8000 \
  --access-logfile /var/log/factura/api-access.log \
  --error-logfile - --capture-output \
  --graceful-timeout 20 --timeout 30 \
  factura_api:app
ExecReload=/bin/kill -HUP $MAINPID
KillMode=mixed
TimeoutStopSec=25
Restart=on-failure
RestartSec=5

# Journaux : le répertoire est créé et ouvert en écriture par systemd
LogsDirectory=factura
LogsDirectoryMode=0750
UMask=0027

# Ressources
MemoryMax=256M
TasksMax=64
LimitNOFILE=8192

# Durcissement
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
PrivateUsers=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
ProtectProc=invisible
ProcSubset=pid
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
CapabilityBoundingSet=
AmbientCapabilities=
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
SystemCallErrorNumber=EPERM

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemd-analyze verify /etc/systemd/system/factura-api.service
sudo systemctl daemon-reload
sudo systemctl enable --now factura-api.service
systemctl status factura-api --no-pager
curl -s http://127.0.0.1:8000/health | jq .
systemd-analyze security factura-api.service | tail -n 3
```

Score obtenu avec cette unité sur Ubuntu 24.04 : **1.9 OK** (départ sans
durcissement : 9.6 UNSAFE). Preuves demandées :

```bash
# le service ne peut pas écrire dans /opt ni /etc
sudo systemd-run -p User=factura -p ProtectSystem=strict -P \
  touch /opt/factura/x    # Permission denied (droits) ; en root :
sudo systemd-run -p ProtectSystem=strict -P touch /etc/x   # Read-only
# le /tmp du service est privé
sudo ls /tmp/systemd-private-*-factura-api.service-*/tmp/
# reload sans changement de PID
systemctl show -p MainPID factura-api; sudo systemctl reload factura-api
systemctl show -p MainPID factura-api
```

::: pourquoi
**`Type=notify`** : Gunicorn appelle `sd_notify(READY=1)` quand l'arbitre a
fini de démarrer les workers. Avec `Type=exec`, systemd considère le service
prêt dès que `execve()` a réussi — nginx, démarré juste après, verrait un
port 8000 fermé pendant une seconde. `notify` fait de `systemctl start` un
vrai « c'est prêt », ce que `After=factura-api` d'une autre unité peut
exploiter.

**`--error-logfile -` et `--access-logfile` fichier** : les erreurs vont sur
stderr, donc dans le journal systemd (`journalctl -u factura-api`), avec
l'horodatage et les métadonnées de systemd. Le journal d'accès est volumineux
et régulier : un fichier plat, tourné par logrotate (PA.6), est plus adapté et
se transfère tel quel vers rsyslog. `LogsDirectory=factura` crée
`/var/log/factura` au bon propriétaire **et** le rend accessible en écriture
malgré `ProtectSystem=strict` : c'est la directive « propre » attendue par
l'énoncé, plutôt que `ReadWritePaths=/var/log/factura`. Contrepartie : à chaque démarrage, systemd remet le répertoire à `User:Group` du service, donc `factura:factura` au lieu de `factura: adm` (PA.1); `mathieu` devra passer par `sudo` ou `journalctl`. Le check PA.1 accepte les deux.

**`PrivateUsers=yes`** vaut à lui seul plus d'un point : le service voit un
espace d'uid où root n'est personne. Il n'est possible que parce que le
service n'a pas besoin d'être root, même une seconde.

**`SystemCallFilter=@system-service`** puis `~@privileged @resources` : la
première liste blanche couvre ce dont un service ordinaire a besoin, la
seconde retire ce qui n'a rien à y faire. `SystemCallErrorNumber=EPERM`
transforme un appel interdit en erreur applicative plutôt qu'en `SIGSYS`
(qui tuerait le worker Gunicorn sans message utile).

**`KillMode=mixed`** : `SIGTERM` à l'arbitre seul, qui arrête ses workers
proprement (fin des requêtes en cours dans `--graceful-timeout`), puis
`SIGKILL` à tout le cgroup à l'expiration de `TimeoutStopSec`. Avec
`control-group`, tous les processus reçoivent `SIGTERM` d'un coup et les
workers meurent avant d'avoir répondu.
:::

::: piege
* `PYTHONDONTWRITEBYTECODE=1` : sans lui, Python tente d'écrire
  `__pycache__` dans `/opt/factura/api`, échoue en silence (lecture seule)
  et l'import est juste plus lent. Pas grave, mais une ligne dans le journal
  à chaque démarrage qu'on finit par ne plus lire.
* `MemoryDenyWriteExecute=yes` peut casser des bibliothèques qui compilent du
  code à la volée (certaines versions de `cffi`, des JIT). Avec Flask,
  `psycopg[binary]` et `redis`, ça passe. Si un jour l'API plante au démarrage
  avec `mmap: Operation not permitted`, c'est cette directive.
* `RestrictAddressFamilies=AF_INET` sans `AF_UNIX` : Gunicorn ne peut plus
  parler à `sd_notify` (socket Unix) ni au journal. Le service démarre puis
  passe en `failed` après `TimeoutStartSec`, faute de `READY=1`.
* `lab-db` est résolu par `/etc/hosts`, donc `ProtectHome` et
  `ProtectSystem` ne gênent pas. Mais `PrivateNetwork=yes` (tentant pour le
  score) couperait tout accès réseau : ne le mets jamais sur un serveur.
* Le score `systemd-analyze security` n'est pas une note de sécurité, c'est
  une liste de directives présentes ou absentes. Un service non durci qui ne
  fait rien est plus sûr qu'un service durci qui exécute `eval` sur l'entrée
  utilisateur. Dis-le en entretien.
:::

---

### **PA.4** — Le worker et la file

*Sur `lab-web` : `factura-worker.service` durci, PDF en `factura 0640`,
résilience aux coupures Redis/PostgreSQL, arrêt propre en charge.*

```bash
sudo install -d -m 0755 /opt/factura/worker
sudo cp /usr/local/src/factura/worker/factura_worker.py /opt/factura/worker/
sudo chown -R root:root /opt/factura/worker
sudo install -m 0640 -o root -g factura /dev/null /etc/factura/worker.env
```

`/etc/factura/worker.env` :

```ini
FACTURA_DB_URL=postgresql://factura_app:ChangeMe-Db-2026@lab-db:5432/factura
FACTURA_REDIS_URL=redis://:ChangeMe-Redis-2026@lab-db:6379/0
FACTURA_QUEUE=factura:jobs
FACTURA_EXPORT_DIR=/srv/factura/exports
FACTURA_LOG_LEVEL=INFO
PYTHONDONTWRITEBYTECODE=1
PYTHONUNBUFFERED=1
```

`/etc/systemd/system/factura-worker.service` :

```ini
[Unit]
Description=Factura worker (export PDF depuis la file Redis)
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=factura
Group=factura
WorkingDirectory=/opt/factura/worker
EnvironmentFile=/etc/factura/worker.env
ExecStart=/opt/factura/venv/bin/python3 /opt/factura/worker/factura_worker.py
SyslogIdentifier=factura-worker
KillSignal=SIGTERM
TimeoutStopSec=30
Restart=always
RestartSec=5
UMask=0027

MemoryMax=128M
TasksMax=32
LimitNOFILE=1024

NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/srv/factura/exports
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
PrivateUsers=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
ProtectProc=invisible
ProcSubset=pid
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
CapabilityBoundingSet=
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
SystemCallErrorNumber=EPERM

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now factura-worker.service
journalctl -u factura-worker -n 5 --no-pager
/usr/local/src/factura/tools/factura-smoke.sh --requeue -n 3
sudo ls -l /srv/factura/exports/
```

Les trois tests demandés :

```bash
# 1. coupure Redis (sur lab-db) pendant que journalctl -f tourne sur lab-web
sudo systemctl stop redis-server; sleep 30; sudo systemctl start redis-server
# lab-web : « redis indisponible ... nouvel essai dans 5 s » puis reprise
systemctl show -p NRestarts factura-worker         # NRestarts=0

# 2. coupure PostgreSQL : idem avec postgresql@16-main
#    « postgresql indisponible ... », le job en cours repart en file (rpush)

# 3. arrêt en charge
/usr/local/src/factura/tools/factura-smoke.sh -n 20 & sleep 1
sudo systemctl stop factura-worker
# journal : « signal 15 recu, arret apres le job en cours » ... « arret propre »
redis-cli -h lab-db -a ChangeMe-Redis-2026 LLEN factura:jobs     # > 0
sudo systemctl start factura-worker      # la file se vide, rien en error
```

::: pourquoi
**`Restart=always` et non `on-failure`** : un consommateur de file n'a aucune
raison légitime de s'arrêter seul. S'il sort avec 0 (par exemple après un
`SIGTERM` envoyé à la main par un `pkill` malheureux), on veut qu'il revienne.
Pour l'API c'était `on-failure`, parce qu'un `systemctl stop` doit rester un
arrêt. Ici aussi : `Restart=always` ne s'applique pas à un `systemctl stop`,
seulement à une sortie non demandée par systemd.

**Pas de `After=factura-api`** : le worker parle à Redis et PostgreSQL, pas à
l'API. Le déclarer dépendant crée un faux ordre de démarrage et, pire, avec
`Requires=`, un arrêt de l'API arrêterait le worker. Les dépendances systemd
doivent refléter les dépendances réelles.

**Le renommage atomique** (`.pdf.tmp` puis `replace`) dans le code fourni :
la sauvegarde de PA.7 ne verra jamais un PDF à moitié écrit. C'est le genre
de détail qu'un exploitant repère en lisant le code, et dont il se sert
ensuite pour décider si `tar` peut tourner pendant que le worker travaille
(oui).

**`ReadWritePaths=/srv/factura/exports`** est le seul trou dans
`ProtectSystem=strict`. C'est précisément ce qu'INC-A2 exploitera : quand le
dossier ne sera plus accessible en écriture au niveau des permissions Unix,
le worker ne pourra rien faire, et systemd n'y verra rien — la panne sera
applicative, pas système.
:::

::: piege
* Oublier `ReadWritePaths` : le worker démarre, prend un job, échoue avec
  `[Errno 30] Read-only file system`, marque la facture `error`, et continue.
  `systemctl status` est vert. C'est déjà une panne silencieuse.
* `TimeoutStopSec` trop court (5 s) : le worker en plein `export_invoice`
  reçoit `SIGKILL`, le job est perdu (déjà `BRPOP`). Avec 30 s et une
  génération de PDF de quelques millisecondes, jamais.
* Tester l'arrêt en charge avec `-n 3` : trop rapide pour observer quoi que
  ce soit. Il faut une file non vide **au moment** du `stop`.
:::

---

### **PA.5** — nginx en frontal TLS, PKI de lab, en-têtes, journaux

*PKI sur `lab-adm`, certificat `factura.lab.local` signé par la CA, nginx
en HTTPS strict avec en-têtes de sécurité, `/api/` relayé, `/api/metrics`
réservé à `lab-ops`, journaux dédiés, pare-feu.*

**1. La PKI sur `lab-adm`** — `~/P1/pki/ext.cnf` :

```ini
[ v3_ca ]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash

[ v3_srv ]
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:factura.lab.local, DNS:lab-web.lab.local, IP:10.10.10.11
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid, issuer
```

```bash
cd ~/P1/pki && umask 077
openssl genrsa -out ca.key 4096
openssl req -x509 -new -key ca.key -sha256 -days 3650 \
  -subj "/O=Ravel & Associes/CN=Ravel Lab CA" \
  -extensions v3_ca -config <(cat /etc/ssl/openssl.cnf ext.cnf) -out ca.crt
chmod 644 ca.crt
```

`~/P1/bin/pa5-cert.sh` (rotation du certificat serveur) :

```bash
#!/usr/bin/env bash
# pa5-cert.sh — (re)génère et signe le certificat de factura.lab.local
set -euo pipefail
PKI="$HOME/P1/pki"; cd "$PKI"; umask 077
CN=factura.lab.local; DAYS="${1:-825}"
[ -f factura.key ] || openssl genrsa -out factura.key 2048
openssl req -new -key factura.key -subj "/O=Ravel & Associes/CN=$CN" \
  -out factura.csr
openssl x509 -req -in factura.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days "$DAYS" -sha256 -extfile ext.cnf -extensions v3_srv -out factura.crt
openssl verify -CAfile ca.crt factura.crt
openssl x509 -in factura.crt -noout -dates -ext subjectAltName
echo "Déploiement : scp factura.crt factura.key mathieu@lab-web: puis"
echo "  sudo install -m 0644 -o root -g root factura.crt /etc/nginx/ssl/"
echo "  sudo install -m 0600 -o root -g root factura.key /etc/nginx/ssl/"
echo "  sudo nginx -t && sudo systemctl reload nginx"
```

Installation de la CA sur `lab-adm` puis `lab-ops` :

```bash
sudo install -m 0644 ~/P1/pki/ca.crt \
  /usr/local/share/ca-certificates/ravel-lab-ca.crt
sudo update-ca-certificates            # 1 added
scp ~/P1/pki/ca.crt mathieu@lab-ops:   # puis la même chose sur lab-ops
```

**2. nginx sur `lab-web`**

```bash
sudo apt install -y nginx
sudo install -d -m 0750 -o root -g root /etc/nginx/ssl
sudo install -m 0644 factura.crt /etc/nginx/ssl/factura.crt
sudo install -m 0600 factura.key /etc/nginx/ssl/factura.key
sudo cp -r /usr/local/src/factura/www/. /srv/factura/www/
sudo chown -R root:root /srv/factura/www
sudo rm -f /etc/nginx/sites-enabled/default
```

`/etc/nginx/sites-available/factura` :

```nginx
log_format factura '$remote_addr - $remote_user [$time_local] "$request" '
                   '$status $body_bytes_sent "$http_referer" '
                   '"$http_user_agent" rt=$request_time '
                   'urt=$upstream_response_time us=$upstream_status';

server {
    listen 80;
    listen [::]:80;
    server_name factura.lab.local lab-web.lab.local 10.10.10.11;
    return 301 https://factura.lab.local$request_uri;
}

server {
    listen 443 ssl http2;   # nginx 1.24 (Ubuntu 24.04) : pas de « http2 on »
    listen [::]:443 ssl http2;
    server_name factura.lab.local lab-web.lab.local;

    ssl_certificate     /etc/nginx/ssl/factura.crt;
    ssl_certificate_key /etc/nginx/ssl/factura.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    # suites TLS 1.2 : ECDHE + AES-GCM ou ChaCha20 (TLS 1.3 a les siennes)
    ssl_ciphers ECDHE+AESGCM:ECDHE+CHACHA20;
    ssl_session_cache shared:factura:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    server_tokens off;
    client_max_body_size 1m;

    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    add_header Content-Security-Policy "default-src 'self'" always;

    access_log /var/log/nginx/factura.access.log factura;
    error_log  /var/log/nginx/factura.error.log warn;

    root /srv/factura/www;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    location = /api/metrics {
        allow 10.10.10.14;
        deny all;
        proxy_pass http://127.0.0.1:8000/metrics;
        proxy_set_header Host $host;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8000/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 3s;
        proxy_read_timeout 30s;
        proxy_send_timeout 10s;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/factura /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo ufw default deny incoming
sudo ufw allow from 10.10.10.10 to any port 22 proto tcp comment 'ssh adm'
sudo ufw allow from 10.10.10.0/24 to any port 80 proto tcp
sudo ufw allow from 10.10.10.0/24 to any port 443 proto tcp
sudo ufw enable
# depuis lab-adm
curl -sI https://factura.lab.local/ | head -n 12
curl -s https://factura.lab.local/api/health | jq .
```

::: pourquoi
**Une CA interne plutôt qu'un auto-signé** : un certificat auto-signé doit
être importé sur chaque poste et refait à chaque rotation. Une CA importée
une fois valide tous les certificats qu'elle émettra pendant dix ans. C'est
ce qu'une PME fait vraiment (via son AD ou une CA d'entreprise) et c'est
pourquoi la clé de la CA ne quitte jamais `lab-adm` : qui la possède peut
émettre `www.banque.fr` pour tous les postes de l'entreprise.

**`subjectAltName` obligatoire** : depuis 2017, Chrome et `curl` ignorent le
`CN`. Un certificat sans SAN est rejeté même s'il est signé correctement
(c'est la question Q18.16 du module 18). L'IP dans le SAN sert au
healthcheck si un jour la résolution de noms tombe.

**`proxy_pass http://127.0.0.1:8000/`** avec la barre finale : nginx remplace
`/api/` par `/`, donc `/api/health` devient `/health` côté Gunicorn. Sans la
barre, l'API recevrait `/api/health` et répondrait 404. Le `location =
/api/metrics` exact passe avant le préfixe `/api/` et porte les `allow/deny` :
c'est là qu'on ferme les métriques au reste du réseau.

**`always` sur `add_header`** : sans lui, nginx n'ajoute les en-têtes que sur
les réponses 2xx/3xx. Une 404 ou une 502 partirait sans HSTS ni CSP.

**CSP `default-src 'self'`** : le front est écrit sans script inline ni CDN,
précisément pour permettre cette politique. Si les développeurs ajoutent un
`<script>` inline, la page casse — c'est le moment de leur expliquer pourquoi
c'est une bonne chose.

**Le `log_format` avec `rt=` et `urt=`** : c'est la différence entre « le
site est lent » et « nginx répond en 3 ms, Gunicorn en 2,9 s ». Le module 19
t'a appris à chercher la couche lente ; ce format te la donne dans chaque
ligne.
:::

::: piege
* `ssl_certificate` avec le certificat de la CA collé derrière : inutile ici
  (pas d'intermédiaire) mais pas nocif. Mettre la **clé** de la CA sur
  `lab-web` « au cas où » : faute éliminatoire.
* `curl https://10.10.10.11/` échoue (le SAN a l'IP, mais nginx sert le
  bloc `default` pour ce `server_name`, ou le `return 301` du port 80) :
  teste toujours avec le nom.
* `ufw allow 443` sans source : le check ne le pénalise pas, mais l'énoncé
  demande `10.10.10.0/24`. Sur un vrai réseau, l'interface aurait une patte
  publique et une privée : l'habitude de sourcer les règles vient d'ici.
* Le check envoie une requête sur `/api/metrics` depuis `127.0.0.1` et attend
  **403**. Si tu as mis `allow 127.0.0.1` « pour tester », retire-le : ton
  test local se fait avec `curl -s http://127.0.0.1:8000/metrics`, sans
  passer par nginx.
:::

---

### **PA.6** — Journaux centralisés et rotation

*journald persistant partout, rsyslog collecteur sur `lab-ops` (TCP 10514,
un dossier par hôte), transfert avec file disque depuis `lab-web` et
`lab-db`, nginx vers syslog, logrotate.*

**1. journald, sur les trois VM** — `/etc/systemd/journald.conf.d/factura.conf` :

```ini
[Journal]
Storage=persistent
SystemMaxUse=200M
MaxRetentionSec=1month
Compress=yes
```

```bash
sudo install -d -m 2755 -g systemd-journal /var/log/journal
sudo systemctl restart systemd-journald
journalctl --disk-usage
```

**2. Collecteur sur `lab-ops`** — `/etc/rsyslog.d/05-collecteur.conf` :

```
# réception TCP sur 10514 (pas 514 : pas de conflit, pas de privilège)
module(load="imtcp")
input(type="imtcp" port="10514" ruleset="distant")

template(name="ParHote" type="string"
         string="/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log")

ruleset(name="distant") {
    action(type="omfile" dynaFile="ParHote"
           dirCreateMode="0750" fileCreateMode="0640"
           dirOwner="syslog" dirGroup="adm" fileOwner="syslog" fileGroup="adm")
    stop
}
```

```bash
sudo install -d -m 0750 -o syslog -g adm /var/log/remote
sudo rsyslogd -N1 && sudo systemctl restart rsyslog
sudo ufw allow from 10.10.10.11 to any port 10514 proto tcp comment 'syslog'
sudo ufw allow from 10.10.10.12 to any port 10514 proto tcp comment 'syslog'
ss -ltnp 'sport = :10514'
```

`/etc/logrotate.d/remote` :

```
/var/log/remote/*/*.log {
    weekly
    rotate 8
    missingok
    notifempty
    compress
    delaycompress
    create 0640 syslog adm
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
```

**3. Émetteurs `lab-web` et `lab-db`** — `/etc/rsyslog.d/90-forward.conf` :

```
# tout vers lab-ops en TCP, avec file disque si lab-ops est injoignable
action(type="omfwd" target="10.10.10.14" port="10514" protocol="tcp"
       queue.type="LinkedList"
       queue.filename="fwd-lab-ops"
       queue.maxDiskSpace="200m"
       queue.saveOnShutdown="on"
       action.resumeRetryCount="-1"
       action.resumeInterval="10")
```

```bash
sudo rsyslogd -N1 && sudo systemctl restart rsyslog
logger -t test-p1 "bonjour depuis $(hostname)"
# sur lab-ops : sudo cat /var/log/remote/lab-web/test-p1.log
```

Test de coupure : sur `lab-ops`, `sudo systemctl stop rsyslog` ; sur `lab-web`,
`for i in $(seq 1 50); do logger -t coupure "ligne $i"; done` ; on voit
apparaître `/var/spool/rsyslog/fwd-lab-ops.*` ; `start` sur `lab-ops` ;
`sudo grep -c coupure /var/log/remote/lab-web/coupure.log` → 50.

**4. nginx vers syslog** — dans le `server` 443, en plus du fichier :

```nginx
    access_log /var/log/nginx/factura.access.log factura;
    access_log syslog:server=unix:/dev/log,facility=local5,tag=nginx_factura
               factura;
    error_log  /var/log/nginx/factura.error.log warn;
    error_log  syslog:server=unix:/dev/log,tag=nginx_factura warn;
```

**5. Rotation sur `lab-web`** — `/etc/logrotate.d/factura` :

```
/var/log/factura/*.log {
    daily
    rotate 14
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    create 0640 factura adm
    su factura adm
}
```

```bash
sudo logrotate -d /etc/logrotate.d/factura      # simulation
sudo logrotate -f /etc/logrotate.d/factura      # rotation forcée
ls -l /var/log/factura/
grep -A3 'nginx/\*.log' /etc/logrotate.d/nginx  # couvre factura.*.log
```

La requête d'exemple depuis `lab-ops` :

```bash
sudo awk -v d="$(date -d '1 hour ago' '+%b %e %H')" '$0 ~ d' \
  /var/log/remote/lab-web/gunicorn.log | grep -i error
# ou, plus lisible : sudo grep -h ERROR /var/log/remote/lab-web/*.log \
#   | grep "$(date '+%b %e')"
```

::: pourquoi
**TCP et file disque** : en UDP (`@`), un rsyslog collecteur arrêté deux
minutes = deux minutes de journaux perdus, sans erreur nulle part. En TCP
avec `queue.type="LinkedList"` et `queue.filename`, rsyslog garde les messages
en mémoire puis sur disque (`/var/spool/rsyslog/`) jusqu'à
`queue.maxDiskSpace`, et `action.resumeRetryCount="-1"` lui dit de réessayer
indéfiniment. Le test de coupure prouve que les 50 lignes arrivent : c'est
la seule preuve qui compte.

**`copytruncate` pour Gunicorn** : Gunicorn sait rouvrir ses journaux sur
`SIGUSR1`, mais pour l'envoyer il faut connaître le PID, et le `postrotate`
tournerait en root contre un service durci. `copytruncate` copie puis vide
le fichier en place : simple, sans signal, au prix d'une fenêtre de quelques
millisecondes où une ligne peut être perdue. Pour un journal d'accès, c'est
acceptable ; pour un journal de transactions, on prendrait le signal.
`su factura adm` est nécessaire parce que `/var/log/factura` n'appartient
pas à root et que logrotate refuse de travailler dans un répertoire
inscriptible par un autre utilisateur.

**`%PROGRAMNAME%` dans le template** : un fichier par programme
(`gunicorn.log`, `factura-worker.log`, `nginx_factura.log`, `sshd.log`)
rend la lecture directe : pas besoin de `grep` pour isoler l'API. Le nom vient de l'identifiant syslog, par défaut le nom de l'exécutable : sans `SyslogIdentifier=factura-worker` (PA.4), le worker finirait dans `python3.log`.

**Port 10514 plutôt que 514** : 514 est un port privilégié, rsyslog devrait
démarrer root pour l'ouvrir (il le fait, puis abandonne les privilèges, mais
c'est une surface en plus), et 514/UDP est souvent déjà occupé ou filtré.
:::

::: piege
* Le fragment `90-forward.conf` sans `stop` ni `ruleset` : le message est
  envoyé **et** écrit localement, c'est voulu. Mais sur `lab-ops`, sans le
  `stop` dans le ruleset `distant`, les journaux des autres machines
  atterrissent aussi dans son `/var/log/syslog` : mélange garanti.
* `Storage=persistent` sans créer `/var/log/journal` : journald reste en
  volatile jusqu'au reboot. `journalctl --disk-usage` doit mentionner
  `/var/log/journal`.
* `logrotate -d` accepte une configuration où `create` et `copytruncate`
  coexistent, mais `copytruncate` l'emporte silencieusement. Ce n'est pas
  une erreur, mais lis le `-d` en entier une fois.
:::

---

### **PA.7** — Sauvegardes nocturnes et restauration testée

*`pg_dump` sur `lab-db`, archive des exports sur `lab-web`, rotation 7
jours, sommes de contrôle, rsync vers un compte restreint sur `lab-ops`,
restauration prouvée, alerte sur échec.*

**1. Le dépôt sur `lab-ops`**

```bash
sudo install -d -m 0700 -o backup -g backup /srv/backups/.ssh
sudo install -d -m 0750 -o backup -g backup \
  /srv/backups/factura/lab-db /srv/backups/factura/lab-web
ls -l /usr/bin/rrsync             # fourni par le paquet rsync
```

**2. Les clés des émetteurs**

```bash
# lab-db, compte postgres
sudo -u postgres ssh-keygen -t ed25519 -N '' -C 'factura-backup lab-db' \
  -f /var/lib/postgresql/.ssh/id_ed25519
sudo -u postgres sh -c 'ssh-keyscan -H 10.10.10.14 >> ~/.ssh/known_hosts'
sudo cat /var/lib/postgresql/.ssh/id_ed25519.pub
# lab-web, compte factura (pas de shell : -s /bin/sh temporaire ou sudo -u)
sudo install -d -m 0700 -o factura -g factura /srv/factura/.ssh
sudo -u factura ssh-keygen -t ed25519 -N '' -C 'factura-backup lab-web' \
  -f /srv/factura/.ssh/id_ed25519
sudo -u factura sh -c \
  'ssh-keyscan -H 10.10.10.14 >> /srv/factura/.ssh/known_hosts'
```

`/srv/backups/.ssh/authorized_keys` sur `lab-ops` (`backup:backup 0600`) :

(chaque entrée tient sur **une seule ligne** ; coupée ici pour la mise en
page)

```
restrict,from="10.10.10.12",command="/usr/bin/rrsync \
  /srv/backups/factura/lab-db" ssh-ed25519 AAAA...db factura-backup lab-db
restrict,from="10.10.10.11",command="/usr/bin/rrsync \
  /srv/backups/factura/lab-web" ssh-ed25519 AAAA...web factura-backup lab-web
```

Tests de restriction depuis `lab-db` :

```bash
sudo -u postgres ssh backup@10.10.10.14 id
# -> "rrsync error: ..." ou connexion fermée : pas de shell
sudo -u postgres rsync -a /etc/hostname backup@10.10.10.14:/tmp/
# -> rrsync: SECURITY VIOLATION / refus : hors du dossier autorisé
sudo -u postgres rsync -a /etc/hostname backup@10.10.10.14:./
# -> OK (le "./" est relatif au dossier imposé par rrsync)
```

**3. `lab-db` : `/usr/local/sbin/factura-backup.sh`**

```bash
#!/usr/bin/env bash
# factura-backup.sh — sauvegarde nocturne Factura (lab-db : base ;
# lab-web : exports). Sort en erreur si une étape échoue.
set -euo pipefail
umask 027
HOST="$(hostname -s)"
DEST=/var/backups/factura
KEEP_DAYS=7
STAMP="$(date +%Y%m%d-%H%M)"
REMOTE="backup@10.10.10.14:./"
log() { logger -t factura-backup -p local6.info -- "$*"; echo "$*"; }
trap 'log "ECHEC à la ligne $LINENO (étape : ${STEP:-?})"; exit 1' ERR

cd "$DEST"
case "$HOST" in
lab-db)
  STEP=pg_dump
  FILE="factura-$STAMP.dump"
  pg_dump -Fc --no-owner -d factura -f "$FILE.tmp"
  mv "$FILE.tmp" "$FILE"
  ;;
lab-web)
  STEP=tar
  FILE="exports-$STAMP.tar.gz"
  tar -C /srv/factura -czf "$FILE.tmp" exports
  mv "$FILE.tmp" "$FILE"
  ;;
*) log "hôte $HOST sans rôle de sauvegarde"; exit 2 ;;
esac

STEP=sha256
sha256sum "$FILE" > "$FILE.sha256"
[ -s "$FILE" ] || { log "fichier vide : $FILE"; exit 1; }

STEP=rotation
find "$DEST" -maxdepth 1 -type f \( -name 'factura-*' -o -name 'exports-*' \) \
  -mtime +"$KEEP_DAYS" -print -delete | sed 's/^/rotation: /'

STEP=rsync
rsync -a --delete --timeout=60 -e 'ssh -o BatchMode=yes' \
  "$DEST/" "$REMOTE"

log "OK $FILE ($(du -h "$FILE" | cut -f1)) copié vers lab-ops"
```

`/etc/systemd/system/factura-backup.service` (`lab-db` ; sur `lab-web`,
`User=factura`, `Group=factura`, `ReadWritePaths=/var/backups/factura /srv/factura/.ssh` et sans `After=postgresql@16-main.service`) :

```ini
[Unit]
Description=Factura — sauvegarde nocturne
OnFailure=factura-alerte@%n.service
After=network-online.target postgresql@16-main.service
Wants=network-online.target

[Service]
Type=oneshot
User=postgres
Group=postgres
ExecStart=/usr/local/sbin/factura-backup.sh
Nice=10
IOSchedulingClass=idle
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/var/backups/factura /var/lib/postgresql/.ssh
PrivateTmp=yes
```

`/etc/systemd/system/factura-backup.timer` :

```ini
[Unit]
Description=Factura — sauvegarde chaque nuit à 02:30

[Timer]
OnCalendar=*-*-* 02:30:00
RandomizedDelaySec=15min
Persistent=yes
Unit=factura-backup.service

[Install]
WantedBy=timers.target
```

Unité d'alerte provisoire (remplacée en PA.8),
`/etc/systemd/system/factura-alerte@.service` :

```ini
[Unit]
Description=Factura — alerte pour %i

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo "$(date -Is) $(hostname -s) %i \
  $(systemctl show -p Result --value %i)" >> /var/log/factura/alertes.log'
```

```bash
sudo install -d -m 0750 -o postgres -g postgres /var/backups/factura   # lab-db
sudo systemctl daemon-reload
sudo systemctl enable --now factura-backup.timer
sudo systemctl start factura-backup.service && systemctl status factura-backup
ls -l /var/backups/factura/
systemctl list-timers factura-backup.timer
```

**4. Restauration sur `lab-db`** (`~/P1/restore.md`) :

```bash
time sudo -u postgres sh -c '
  DUMP=$(ls -t /var/backups/factura/factura-*.dump | head -n1)
  sha256sum -c "$DUMP.sha256" &&
  psql -c "DROP DATABASE IF EXISTS factura_restore" &&
  psql -c "CREATE DATABASE factura_restore OWNER factura_app" &&
  pg_restore -d factura_restore --no-owner --role=factura_app "$DUMP"'
sudo -u postgres psql -d factura -tAc 'SELECT count(*) FROM invoices'
sudo -u postgres psql -d factura_restore -tAc 'SELECT count(*) FROM invoices'
# real 0m1.2s pour ~30 factures ; procédure complète (avec vérifs) : 4 min
```

Restauration des exports sur `lab-web` :

```bash
sudo -u factura sh -c 'cd /tmp && tar -xzf \
  $(ls -t /var/backups/factura/exports-*.tar.gz | head -n1) && \
  diff -r /tmp/exports /srv/factura/exports && echo IDENTIQUE'
```

Réponse à la question RPO : dump à 02:30, donc jusqu'à ~24 h de pertes
(RPO = 24 h) ; RTO mesuré ≈ 5 min. Pour réduire le RPO : (1) archivage WAL
continu (`archive_mode=on`, `archive_command` vers `lab-ops`) qui ramène le
RPO à quelques minutes ; (2) réplication streaming vers un second serveur.
Les deux sont hors périmètre ici, mais à nommer.

::: pourquoi
**`pg_dump -Fc`** (format custom) plutôt que `.sql` : compressé, restaurable
sélectivement (`pg_restore -t invoices`), et parallélisable. Il est pris par
`postgres` en `peer` : aucun mot de passe dans le script, aucun `.pgpass` à
protéger, et le compte ne peut rien faire d'autre que ce que `postgres` fait
déjà.

**Écrire dans `.tmp` puis `mv`** : si le dump est interrompu (disque plein,
`SIGKILL`), il ne reste jamais un fichier `.dump` tronqué que la rotation
garderait et qu'on croirait valide. La somme de contrôle à côté permet de
détecter une corruption ultérieure (disque, transfert) — `sha256sum -c`
avant chaque restauration.

**`rrsync` avec `restrict` et `from=`** : la clé de `postgres` ne peut
ouvrir qu'une session `rsync` dans un seul dossier, depuis une seule IP,
sans redirection de port ni agent. Si `lab-db` est compromise, l'attaquant
peut au pire écraser les sauvegardes de `lab-db` — pas lire celles de
`lab-web`, pas obtenir un shell sur `lab-ops`. C'est exactement la question
« et si le compte de sauvegarde est compromis ? » qu'on te posera.

**`--delete` dans le rsync** : le dépôt distant reflète la rotation locale.
Sans lui, `lab-ops` accumule indéfiniment. Avec lui, une erreur locale
(rotation trop agressive) se propage : c'est le compromis assumé, et la
raison pour laquelle on garde `KEEP_DAYS` dans une variable visible.

**`Persistent=yes`** : si `lab-db` était éteinte à 02:30, la sauvegarde part
au prochain démarrage. `RandomizedDelaySec` évite que les deux machines
frappent `lab-ops` à la même seconde.

**`OnFailure=`** : la sauvegarde qui échoue en silence est le scénario
classique du module 17. Ici, tout `exit ≠ 0` du script (grâce à `set -e` et
au `trap ERR`) déclenche l'alerte. Le test à faire : `chmod 000
/var/backups/factura` puis `systemctl start factura-backup` — l'alerte doit
tomber dans `alertes.log`.
:::

::: piege
* `factura` n'a pas de shell : `sudo -u factura ssh-keygen` marche, mais
  `su - factura` non. `ssh` en tant que `factura` marche aussi (le shell
  n'intervient que côté serveur).
* Oublier `known_hosts` : le premier `rsync` de nuit se bloque sur « Are you
  sure you want to continue connecting? » jusqu'au timeout, l'unité passe en
  `failed`, l'alerte part. `BatchMode=yes` transforme la question en erreur
  immédiate, ce qui est mieux, mais ne dispense pas du `ssh-keyscan`.
* Sur `lab-web`, `/var/backups/factura` avait été créé `factura:factura` en
  PA.1 : c'était pour ça. Sur `lab-db`, il faut le créer `postgres:postgres`
  (PA.1 ne l'avait pas fait, PostgreSQL n'existait pas encore).
* `ProtectSystem=strict` sur le service de sauvegarde sans
  `ReadWritePaths=/var/lib/postgresql/.ssh` : `ssh` veut écrire
  `known_hosts` (même si rien ne change) et échoue de façon obscure. Le
  `journalctl -u factura-backup` le montre.
:::

---

### **PA.8** — Supervision et alerting par timers

*`node_exporter` partout, webhook local sur `lab-ops`, unité d'alerte
modèle, healthcheck toutes les 2 minutes avec métriques pour le textfile
collector et anti-tempête.*

**1. `node_exporter`** (sur les trois VM) :

```bash
sudo apt install -y prometheus-node-exporter
curl -s 127.0.0.1:9100/metrics | grep '^node_load1'
# lab-web et lab-db uniquement :
sudo ufw allow from 10.10.10.14 to any port 9100 proto tcp comment 'node_exp'
```

**2. Le webhook sur `lab-ops`** — `/etc/systemd/system/factura-webhook.service` :

```ini
[Unit]
Description=Factura — récepteur d'alertes (webhook local)
After=network.target

[Service]
Type=exec
DynamicUser=yes
LogsDirectory=factura
Environment=FACTURA_WEBHOOK_BIND=127.0.0.1
Environment=FACTURA_WEBHOOK_PORT=9999
Environment=FACTURA_WEBHOOK_LOG=/var/log/factura/webhook.log
ExecStart=/usr/bin/python3 /usr/local/src/factura/tools/factura-webhook.py
Restart=always
RestartSec=3
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
CapabilityBoundingSet=

[Install]
WantedBy=multi-user.target
```

Pour que `lab-web` et `lab-db` puissent alerter aussi, le webhook doit être
joignable sur 10.10.10.14. Solution retenue : `FACTURA_WEBHOOK_BIND=0.0.0.0`
dans l'unité, à la place de `127.0.0.1` ci-dessus (il reste joignable en local), et `ufw` limite 9999 aux deux
émetteurs — le trafic local n'est pas filtré par ufw :

```bash
sudo ufw allow from 10.10.10.11 to any port 9999 proto tcp comment 'alertes'
sudo ufw allow from 10.10.10.12 to any port 9999 proto tcp comment 'alertes'
```

Le check PA.8 vérifie que le webhook répond sur `127.0.0.1:9999`, pas
l'adresse d'écoute. À noter dans le journal : un webhook sans authentification, sur le LAN. Un
vrai Slack a un jeton dans l'URL ; ici la restriction par IP en tient lieu.

**3. L'unité d'alerte** — `/usr/local/sbin/factura-alerte.sh` (sur les trois VM) :

```bash
#!/usr/bin/env bash
# factura-alerte.sh <unité> — journalise et POSTe une alerte, au plus une
# fois par quart d'heure pour une même unité.
set -uo pipefail
UNIT="${1:?unité}"
HOST="$(hostname -s)"
WEBHOOK="${FACTURA_WEBHOOK_URL:-http://10.10.10.14:9999/}"
STATE=/var/lib/factura/alerte-"${UNIT//\//_}".last
LOG=/var/log/factura/alertes.log
NOW=$(date +%s)
RESULT=$(systemctl show -p Result --value "$UNIT")
STATUS=$(systemctl show -p ExecMainStatus --value "$UNIT")
SINCE=$(systemctl show -p InactiveEnterTimestamp --value "$UNIT")
LINE="$(date -Is) $HOST $UNIT result=$RESULT status=$STATUS"
echo "$LINE" >> "$LOG"

if [ -f "$STATE" ] && [ $((NOW - $(cat "$STATE"))) -lt 900 ]; then
  echo "$(date -Is) $HOST $UNIT alerte déjà envoyée (< 15 min)" -> "$LOG"
  exit 0
fi
FMT='{"host":"%s","unit":"%s","result":"%s","status":"%s","since":"%s"}'
PAYLOAD=$(printf "$FMT" "$HOST" "$UNIT" "$RESULT" "$STATUS" "$SINCE")
if curl -fsS --max-time 5 -X POST -H 'Content-Type: application/json' \
     -d "$PAYLOAD" "$WEBHOOK" >/dev/null; then
  echo "$NOW" > "$STATE"
else
  echo "$(date -Is) $HOST $UNIT ECHEC envoi webhook $WEBHOOK" >> "$LOG"
  exit 1
fi
```

`/etc/systemd/system/factura-alerte@.service` :

```ini
[Unit]
Description=Factura — alerte pour %i
# pas d'OnFailure ici : une unité d'alerte qui alerte sur elle-même boucle

[Service]
Type=oneshot
ExecStartPre=/usr/bin/mkdir -p /var/lib/factura /var/log/factura
ExecStart=/usr/local/sbin/factura-alerte.sh %i
```

Sur `lab-ops`, `Environment=FACTURA_WEBHOOK_URL=http://127.0.0.1:9999/`
dans `[Service]`. L'unité tourne en root : un `mkdir -p` suffit à créer
`/var/lib/factura` sur `lab-db` et `lab-ops`. Surtout **pas** de
`StateDirectory=`/`LogsDirectory=` ici : systemd ferait un `chown -R` vers
l'utilisateur de l'unité (root) et retirerait à `factura` ses propres
répertoires sur `lab-web`.

**4. Le healthcheck sur `lab-ops`** — `/usr/local/sbin/factura-healthcheck.sh` :

```bash
#!/usr/bin/env bash
# factura-healthcheck.sh — contrôle Factura, écrit factura.prom, sort en 1
# si un contrôle échoue (OnFailure= déclenche l'alerte).
set -uo pipefail
URL=https://factura.lab.local
PROM=/var/lib/prometheus/node-exporter/factura.prom
BK=/srv/backups/factura
T0=$(date +%s.%N); KO=0; UP=0; QLEN=-1; ALIVE=0
say() { logger -t factura-healthcheck -- "$*"; echo "$*"; }

# 1. santé de l'API via nginx, CA système
H=$(curl -fsS --max-time 5 "$URL/api/health" 2>/dev/null) \
  && echo "$H" | grep -q '"status": *"ok"' && UP=1
[ "$UP" -eq 1 ] || { say "KO health : ${H:-pas de réponse}"; KO=1; }

# 2. métriques applicatives
M=$(curl -fsS --max-time 5 "$URL/api/metrics" 2>/dev/null) || \
  { say "KO metrics injoignable"; KO=1; }
QLEN=$(echo "$M" | awk '/^factura_queue_length/{print $2}'); QLEN=${QLEN:--1}
ALIVE=$(echo "$M" | awk '/^factura_worker_alive/{print $2}'); ALIVE=${ALIVE:-0}
ERR=$(echo "$M" | awk '/^factura_invoices_total\{status="error"\}/{print $2}')
[ "$QLEN" -ge 0 ] && [ "$QLEN" -lt 100 ] || { say "KO file : $QLEN"; KO=1; }
[ "$ALIVE" -eq 1 ] || { say "KO worker sans battement de cœur"; KO=1; }

# 3. fraîcheur des sauvegardes
age() { local f; f=$(find "$BK/$1" -type f ! -name '*.sha256' \
        -printf '%T@\n' 2>/dev/null | sort -n | tail -n1)
        [ -n "$f" ] && echo $(( $(date +%s) - ${f%.*} )) || echo 999999; }
AGE_DB=$(age lab-db); AGE_WEB=$(age lab-web)
[ "$AGE_DB"  -lt 93600 ] || { say "KO sauvegarde lab-db : ${AGE_DB}s"; KO=1; }
[ "$AGE_WEB" -lt 93600 ] || { say "KO sauvegarde lab-web : ${AGE_WEB}s"; KO=1; }

# 4. espace du dépôt
FREE=$(df --output=pcent /srv/backups | tail -n1 | tr -dc '0-9')
[ "$FREE" -lt 85 ] || { say "KO /srv/backups plein à ${FREE}%"; KO=1; }

# 5. export pour node_exporter (écriture atomique)
DUR=$(echo "$(date +%s.%N) - $T0" | bc)
TMP=$(mktemp "$PROM.XXXXXX")
cat > "$TMP" <<EOF
# HELP factura_health_up 1 si /api/health repond ok via nginx
# TYPE factura_health_up gauge
factura_health_up $UP
factura_queue_length $QLEN
factura_worker_alive $ALIVE
factura_invoices_error_total ${ERR:-0}
factura_backup_age_seconds{host="lab-db"} $AGE_DB
factura_backup_age_seconds{host="lab-web"} $AGE_WEB
factura_backup_disk_used_percent $FREE
factura_check_duration_seconds $DUR
factura_check_last_run_timestamp $(date +%s)
EOF
chmod 0644 "$TMP" && mv "$TMP" "$PROM"
[ "$KO" -eq 0 ] && say "OK up=$UP file=$QLEN worker=$ALIVE" 
exit "$KO"
```

`/etc/systemd/system/factura-healthcheck.service` et `.timer` :

```ini
[Unit]
Description=Factura — contrôle de santé
OnFailure=factura-alerte@%n.service
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/factura-healthcheck.sh
TimeoutStartSec=60
```

```ini
[Unit]
Description=Factura — contrôle toutes les 2 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
AccuracySec=30s
Unit=factura-healthcheck.service

[Install]
WantedBy=timers.target
```

```bash
sudo apt install -y bc
sudo chmod 0755 /usr/local/sbin/factura-*.sh
sudo systemctl daemon-reload
sudo systemctl enable --now factura-webhook.service factura-healthcheck.timer
sudo systemctl start factura-healthcheck.service
cat /var/lib/prometheus/node-exporter/factura.prom
curl -s 127.0.0.1:9100/metrics | grep '^factura_'
```

Preuve : `sudo systemctl stop factura-api` sur `lab-web` à 10:02:00 ;
`webhook.log` sur `lab-ops` reçoit à 10:03:41 :

```
2026-09-18T10:03:41+02:00 127.0.0.1 {"host": "lab-ops", "unit":
"factura-healthcheck.service", "result": "exit-code", "status": "1", ...}
```

puis plus rien pendant 15 minutes malgré les échecs suivants (ligne « alerte
déjà envoyée » dans `alertes.log`). Délai de détection : 1 min 41 s.

::: pourquoi
**Le healthcheck sort en 1, l'alerte est dans `OnFailure=`** : le script ne
contient aucune logique d'alerte. Il mesure, il écrit, il dit « ça va » ou
« ça ne va pas » par son code de sortie. C'est systemd qui décide quoi faire
d'un échec, et la même unité d'alerte sert aux sauvegardes, au healthcheck,
et demain à n'importe quel timer. Un mécanisme, pas un par script (c'est la
leçon de L17.4).

**Anti-tempête dans l'unité d'alerte, pas dans le healthcheck** : le
healthcheck ne sait pas qu'il échoue depuis 20 minutes, et ne doit pas le
savoir. L'unité d'alerte, elle, garde un horodatage par unité dans
`/var/lib/factura/` : 15 minutes entre deux envois pour la même unité. Une
panne de 3 minutes produit une alerte ; une panne de 3 heures en produit 12,
pas 90.

**Le textfile collector** : `node_exporter` expose déjà CPU, disque, réseau.
Lui donner nos mesures métier (`factura_ backup_age_seconds`) via un fichier
`.prom` signifie qu'au module 26, Prometheus les récupérera **sans rien
changer** : les règles d'alerte s'écriront sur ces métriques. L'écriture
atomique (`mktemp` + `mv`) évite que node_exporter lise un fichier à moitié
écrit et exporte une erreur de parsing.

**Contrôler via nginx et la CA système, pas via `127.0.0.1:8000`** : on teste
ce que l'utilisateur voit. Un contrôle sur Gunicorn en local aurait dit « tout
va bien » pendant INC-A3, où seul le pare-feu bloquait.

**`OnBootSec` + `OnUnitActiveSec`** (timer monotone) plutôt qu'`OnCalendar`
pour une cadence courte, on veut « 2 minutes après la fin du précédent »,
pas « aux minutes paires ». Et si `lab-ops` redémarre, le premier contrôle
part une minute après le boot.
:::

::: piege
* `curl` sans `--max-time` : un frontal qui accepte la connexion TCP mais ne
  répond jamais (INC-A3 en variante) bloque le script jusqu'au `TimeoutStartSec`
  de l'unité. Le service passe en `failed` par timeout, ce qui déclenche bien
  l'alerte — mais 60 s plus tard, et avec un `factura.prom` jamais réécrit.
* Écrire `factura.prom` **après** les contrôles mais **avant** `exit` : si
  on fait `set -e`, le premier contrôle en échec sort du script sans écrire
  le fichier. C'est pourquoi le script n'utilise pas `-e` et accumule `KO`.
* `factura_health_up 0` reste dans `factura.prom` si le script est lancé à
  la main en root puis par le timer : le fichier appartient à root, lisible
  par tous — pas de souci. Mais un `mktemp` dans `/var/lib/prometheus/
  node-exporter/` exige que ce dossier soit inscriptible par l'utilisateur du
  service (root ici). `DynamicUser=yes` + `LogsDirectory=factura` sur `lab-ops` : systemd déplace `/var/log/factura` (créé root :adm en PA.1) vers `/var/log/private/factura` et laisse un lien symbolique. `alertes.log` et `webhook.log` y cohabitent, mais `ls -ld /var/log/factura` te surprendra (le check PA.1 reconnaît ce lien). Si tu préfères un compte dédié (`User= factura-webhook`), crée-le avec `useradd -r` et donne-lui l'écriture sur le dossier.
* La preuve « une seule alerte » : si tu la fais juste après un test manuel
  qui a déjà envoyé une alerte, l'anti-tempête l'avale et tu crois que la
  chaîne est cassée. `rm /var/lib/factura/alerte-*.last` avant le test.
:::

---

### **PA.9** — Durcissement et audit

*SSH verrouillé, `pme-ops` avec sudo restreint, fail2ban sur SSH et nginx,
sysctl, `unattended-upgrades`, permissions, lynis ≥ 65, rapport d'audit.*

**1. SSH** — `/etc/ssh/sshd_config.d/10-factura.conf` (les trois VM) :

```
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 30
AllowGroups ssh-users
Banner /etc/issue.net
ClientAliveInterval 300
ClientAliveCountMax 2
```

```bash
sudo groupadd -r ssh-users && sudo usermod -aG ssh-users mathieu
echo "Acces reserve. Toute connexion est journalisee." | sudo tee /etc/issue.net
sudo sshd -t && sudo systemctl reload ssh      # seconde session ouverte !
sudo sshd -T | grep -E '^(passwordauth|permitroot|allowgroups)'
```

**2. `pme-ops`** sur `lab-web` :

```bash
sudo useradd -m -s /bin/bash -G ssh-users -c "Exploitant PME" pme-ops
sudo install -d -m 0700 -o pme-ops -g pme-ops /home/pme-ops/.ssh
# copier sa clé publique dans /home/pme-ops/.ssh/authorized_keys (0600)
```

`/usr/local/bin/factura-logs` (enveloppe sans pager) :

```bash
#!/usr/bin/env bash
# factura-logs [unité] [N] — journaux Factura, sans pager, sans shell
set -euo pipefail
U="${1:-factura-api}"; N="${2:-100}"
case "$U" in factura-api|factura-worker|factura-backup) ;;
  *) echo "unité non autorisée : $U" >&2; exit 2 ;; esac
exec journalctl --no-pager -u "$U.service" -n "$N"
```

`/etc/sudoers.d/pme-ops` (`sudo visudo -f`, mode 0440) :

```
Cmnd_Alias FACTURA_CTL = /usr/bin/systemctl status factura-api, \
    /usr/bin/systemctl status factura-worker, \
    /usr/bin/systemctl restart factura-api, \
    /usr/bin/systemctl restart factura-worker, \
    /usr/bin/systemctl reload factura-api
Cmnd_Alias FACTURA_LOGS = /usr/local/bin/factura-logs
Cmnd_Alias FACTURA_BKP  = /usr/local/sbin/factura-backup.sh
Defaults:pme-ops !lecture, env_reset, secure_path="/usr/bin:/bin"
pme-ops ALL=(root) NOPASSWD: FACTURA_CTL, FACTURA_LOGS
pme-ops ALL=(factura) NOPASSWD: FACTURA_BKP
```

```bash
sudo visudo -cf /etc/sudoers.d/pme-ops
sudo -l -U pme-ops
sudo -u pme-ops sudo systemctl restart nginx    # refusé, journalisé
```

**3. fail2ban** — `/etc/fail2ban/jail.local` :

```ini
[DEFAULT]
ignoreip = 127.0.0.1/8 10.10.10.10
bantime  = 1h
findtime = 10m
maxretry = 3
banaction = ufw
backend = systemd

[sshd]
enabled = true

[nginx-factura-4xx]
enabled  = true
port     = http,https
filter   = nginx-factura-4xx
logpath  = /var/log/nginx/factura.access.log
backend  = auto
findtime = 1m
maxretry = 20
bantime  = 10m
```

`/etc/fail2ban/filter.d/nginx-factura-4xx.conf` (`lab-web`) :

```ini
[Definition]
failregex = ^<HOST> - \S+ \[[^\]]+\] "\w+ /api/\S* \S+" (401|403|404) 
ignoreregex =
```

```bash
sudo apt install -y fail2ban
sudo fail2ban-regex /var/log/nginx/factura.access.log \
  /etc/fail2ban/filter.d/nginx-factura-4xx.conf | tail -n 5
sudo systemctl restart fail2ban && sudo fail2ban-client status
# test depuis lab-ops (pas lab-adm : ignoreip)
for i in $(seq 1 25); do
  curl -so /dev/null https://factura.lab.local/api/x$i; done
# lab-web : sudo fail2ban-client status nginx-factura-4xx ; puis
sudo fail2ban-client set nginx-factura-4xx unbanip 10.10.10.14
```

**4. sysctl** — `/etc/sysctl.d/60-factura-hardening.conf` :

```ini
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.all.rp_filter = 1
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
fs.protected_regular = 2
fs.protected_fifos = 2
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
```

`sudo sysctl --system` puis `sysctl -n kernel.kptr_restrict`.

**5. Mises à jour** :

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades   # Yes
# dans /etc/apt/apt.conf.d/50unattended-upgrades, décommenter :
#   Unattended-Upgrade::Automatic-Reboot "false";
#   Unattended-Upgrade::Mail "root";
sudo sed -i 's|^//\(Unattended-Upgrade::Automatic-Reboot \)|\1|' \
  /etc/apt/apt.conf.d/50unattended-upgrades
apt-config dump | grep Periodic::Unattended
sudo unattended-upgrade --dry-run -d 2>&1 | tail -n 3
```

**6. Permissions et lynis** :

```bash
sudo find /opt/factura /srv/factura /etc/factura -perm -o+w ! -type l
sudo find /etc/factura -type f -perm /o+r
sudo chmod 700 /var/lib/postgresql/16/main        # lab-db (déjà le cas)
sudo apt install -y lynis
sudo lynis audit system --quick | tail -n 20      # Hardening index : 61
sudo lynis show details SSH-7408
```

Suggestions traitées pour passer de 61 à 71 sur `lab-web` (à noter dans
`audit.md`) : bannière SSH (`BANN-7126`), `umask 027` dans `/etc/login.defs`
(`AUTH-9328`), `PASS_MAX_DAYS 365` (`AUTH-9286`), `auditd` installé avec les
règles du module 18 (`ACCT-9628`), `sysstat` activé (`ACCT-9626`),
`/tmp` en tmpfs `nodev,nosuid,noexec` (`FILE-6310`), `apt-listbugs`/`debsums`
(`PKGS-7370`), `AllowTcpForwarding no` (`SSH-7408`), `LogLevel VERBOSE`
(`SSH-7408`), `kernel.sysrq = 0`. Volontairement laissées : partitions
séparées pour `/home` et `/var` (refaire l'installation : hors périmètre),
`fail2ban` sur `lab-ops` (pas de service exposé au-delà de SSH), TLS entre
API et PostgreSQL (coût : PKI serveur sur `lab-db`, à planifier).

Risques résiduels à signaler : (1) secrets en fichiers `.env` lisibles par
tout processus du groupe `factura` ; (2) webhook non authentifié sur le LAN ;
(3) aucune redondance : `lab-db` est un point unique de panne, RPO 24 h.

::: pourquoi
**`journalctl` dans sudoers, la faille classique** : `sudo journalctl -u
factura-api` ouvre `less` en root ; dans `less`, `!sh` donne un shell root.
`Defaults:pme-ops !lecture` ne suffit pas (c'est pour les leçons de sudo).
La bonne réponse est de ne jamais mettre dans sudoers une commande qui ouvre
un pager, un éditeur ou accepte un argument libre : l'enveloppe
`factura-logs` fixe `--no-pager`, valide l'unité contre une liste, et ne
laisse passer aucun autre argument vers `journalctl`. Même logique pour
`systemctl` : chaque commande complète est listée, pas `systemctl *`.

**`pme-ops ALL=(factura) FACTURA_BKP`** : la sauvegarde des exports tourne
sous `factura`, donc l'exploitant la lance **en tant que `factura`**, pas
root. Le principe du moindre privilège s'applique aussi à `sudo`.

**fail2ban avec `banaction = ufw`** : cohérent avec le pare-feu en place ;
`fail2ban-client status nginx-factura-4xx` et `ufw status` montrent la même
IP. Le filtre vise `/api/` et les codes 401/403/404 : ce qu'un scanner
produit, pas ce qu'un utilisateur fait. `maxretry 20` en 1 minute est
volontairement haut : un front qui fait 6 requêtes par rafraîchissement ne
doit jamais bannir la comptable.

**`Automatic-Reboot "false"`** : une mise à jour du noyau sur `lab-db` ne
doit pas redémarrer la base à 6 h du matin sans qu'on le sache. Le paquet
laisse `/var/run/reboot-required` ; c'est au healthcheck ou au runbook de le
remonter (bonus : l'ajouter à `factura.prom`).

**`lynis` comme conversation, pas comme note** : l'index mesure la
conformité à une liste de contrôles génériques. Passer de 61 à 71 en une
heure est facile ; ce qui compte pour l'entretien, c'est de savoir dire
pourquoi on a laissé tel point et ce qu'on ferait avec plus de temps.
:::

::: piege
* `AllowGroups ssh-users` sans y mettre `mathieu` **avant** le `reload` :
  la session ouverte survit, la suivante est refusée. Toujours `sshd -t`,
  toujours une deuxième session, toujours tester une nouvelle connexion
  avant de fermer l'ancienne.
* `backend = systemd` pour `sshd` (Ubuntu 24.04 n'a plus `/var/log/auth.log`
  par défaut sans rsyslog — ici rsyslog est installé, les deux marchent) mais
  `backend = auto` pour la jail nginx qui lit un fichier.
* Tester le filtre nginx depuis `lab-adm` : `ignoreip` l'ignore et tu
  conclus que le filtre ne marche pas. Depuis `lab-ops`, oui — et pense à
  débannir, sinon le healthcheck (qui part de `lab-ops`) tombe et l'alerte
  part : une bonne démonstration involontaire.
* `sudo visudo -f /etc/sudoers.d/pme-ops` puis un fichier en 0644 : sudo
  refuse tout le répertoire (`sudoers.d/pme-ops is world writable` ou mode
  incorrect). 0440.
:::

---

### **PA.10** — Runbook et exercice d'incident

*Un runbook de 120 lignes minimum, exploitable par un tiers ; trois
incidents résolus avec post-mortem ; runbook amélioré.*

Squelette de `~/P1/runbook.md` (les commandes doivent être les tiennes) :

```markdown
# Factura — runbook d'exploitation (v1.3, 2026-09)

## 1. Architecture
(schéma de A.1) — lab-web 10.10.10.11 : nginx 443, factura-api 8000 local,
factura-worker ; lab-db 10.10.10.12 : postgresql@16-main 5432, redis 6379 ;
lab-ops 10.10.10.14 : rsyslog 10514, sauvegardes, healthcheck, webhook 9999.
Comptes : factura (web), postgres (db), backup (ops), pme-ops (exploitant).

## 2. Démarrage / Arrêt
Ordre de démarrage : lab-db (postgresql, redis) -> lab-web (factura-api,
factura-worker, nginx) -> lab-ops (healthcheck). Arrêt dans l'ordre inverse.
    sudo systemctl start postgresql@16-main redis-server        # lab-db
    sudo systemctl start factura-api factura-worker nginx       # lab-web
Vérification en 3 commandes :
    curl -s https://factura.lab.local/api/health | jq .        # lab-adm
    systemctl --failed                                         # partout
    tail -n 5 /var/log/factura/alertes.log                     # lab-ops

## 3. Secrets
/etc/factura/api.env et worker.env (lab-web, root:factura 0640) ;
/etc/redis/redis.conf (requirepass) ; mot de passe factura_app dans
PostgreSQL. Rotation du mot de passe base : ALTER ROLE ... ; éditer les deux
.env ; systemctl restart factura-api factura-worker. Certificat : sur
lab-adm ~/P1/bin/pa5-cert.sh puis déploiement (voir sortie du script) ;
expiration surveillée par `openssl x509 -checkend` (à ajouter au
healthcheck : historique v1.2).

## 4. Sauvegarde / Restauration
02:30 chaque nuit, /var/backups/factura sur lab-db et lab-web, copie sur
lab-ops:/srv/backups/factura/<hôte>/. 7 jours. Vérifier :
    systemctl list-timers factura-backup.timer ; ls -lt /var/backups/factura
Restaurer la base : (procédure restore.md, RTO 5 min, RPO 24 h)
Restaurer les exports : tar -xzf ... -C /srv/factura

## 5. Supervision
lab-ops : /var/log/factura/webhook.log (alertes reçues), alertes.log
(émises), /var/lib/prometheus/node-exporter/factura.prom (mesures),
/var/log/remote/<hôte>/ (journaux). Seuils : file < 100, sauvegarde < 26 h,
disque < 85 %.

## 6. Incidents — checklists
### Site en timeout depuis les postes
1. curl -sv --max-time 5 https://factura.lab.local/ (depuis lab-adm) : TCP ?
2. ping 10.10.10.11 ; ssh lab-web
3. sur lab-web : ss -ltn 'sport = :443' ; curl -k https://127.0.0.1/
4. sudo ufw status numbered | head ; sudo nft list ruleset | grep 443
5. journalctl -u nginx -n 20 ; tail /var/log/ufw.log
### 502 Bad Gateway
1. curl -s http://127.0.0.1:8000/health (lab-web) ; systemctl status factura-api
2. journalctl -u factura-api -n 50 ; tail /var/log/nginx/factura.error.log
### 503 « degraded »
1. curl -s http://127.0.0.1:8000/health | jq . : db ou redis ?
2. psql "$FACTURA_DB_URL" -c 'select 1' (depuis lab-web, URL de api.env)
3. lab-db : systemctl status postgresql@16-main ; tail /var/log/postgresql/*.log
4. pg_hba.conf, ufw status, ss -ltn 'sport = :5432'
### Factures en « error », pas de PDF
1. journalctl -u factura-worker -n 50 (chercher Errno 13 / 30)
2. ls -ld /srv/factura/exports ; systemctl show -p ReadWritePaths factura-worker
3. redis-cli -h lab-db -a ... LLEN factura:jobs:failed
4. après correction : factura-smoke.sh --requeue
### Alerte sauvegarde
1. journalctl -u factura-backup -n 30 (ligne « ECHEC à la ligne ... ») ...
### Disque plein
1. df -h ; du -xsh /var/log/* /var/backups/* | sort -h | tail ...

## 7. Contacts et escalade
Exploitant : pme-ops (heures ouvrées). Admin : mathieu (astreinte,
15 min). Développeur : ... (bug applicatif, 4 h). Direction : au-delà de
2 h d'indisponibilité.

## Historique
v1.1 après INC-A1 : ajout « pg_hba.conf » et « tail postgresql.log » dans
la checklist 503. v1.2 après INC-A2 : ajout de factura_invoices_error_total
au healthcheck, checklist « factures en error ». v1.3 après INC-A3 : ajout
« ufw status numbered » en étape 4 de « timeout », règle sur les règles
temporaires (commentaire + date + ticket, revue hebdomadaire).
```

Le post-mortem suit le modèle du module 19 (Résumé, Impact, Chronologie,
Détection, Cause racine, Ce qui a marché / manqué, Actions correctives).

::: pourquoi
Un runbook est un **contrat avec toi-même fatigué**. Il est bon si quelqu'un
qui ne connaît pas la plateforme retrouve le service en suivant les
checklists sans réfléchir ; il est excellent s'il s'améliore à chaque
incident. Le `## Historique` est la partie la plus importante : elle prouve
que le document vit. En entretien, « j'ai un runbook » vaut peu ; « voici
les trois choses que mes incidents m'ont fait ajouter » vaut beaucoup.
:::

---

## A.3 Incidents — diagnostic pas à pas

### **INC-A1** — « degraded », factures non enregistrées

*Un collègue a « durci » PostgreSQL vendredi soir ; lundi, l'API est en 503.*

**Diagnostic**

1. Depuis `lab-adm` : `curl -s https://factura.lab.local/api/health | jq .`
   → `"db": "ko: connection failed: ... pg_hba.conf rejects connection for
   host "10.10.10.11", user "factura_app", database "factura", no encryption"`,
   `"redis": "ok"`. Le message dit tout : c'est **pg_hba**, pas le réseau,
   pas le mot de passe (ce serait « password authentication failed »), pas
   le pare-feu (ce serait un timeout ou « connection refused »).
2. Confirmation depuis `lab-web`, avec les identifiants de l'API :
   `psql "$(sudo grep -h ^FACTURA_DB_URL /etc/factura/api.env | cut -d= -f2-)" -c 'select 1'`
   → même erreur.
3. Sur `lab-db` : `sudo tail -n 20 /var/log/postgresql/postgresql-16-main.log`
   → `FATAL: pg_hba.conf rejects connection for host "10.10.10.11"...`,
   répété toutes les 5 s (le worker) et à chaque requête (`/health`).
4. `sudo grep -nv '^#' /etc/postgresql/16/main/pg_hba.conf | grep -v '^\s*$'`
   → première ligne : `host all all 10.10.10.11/32 reject`, précédée du
   commentaire « hardening 2026-09 ». Première règle qui correspond gagne :
   le `reject` capte tout avant la règle `scram-sha-256` plus bas.
5. `ls -l /etc/postgresql/16/main/pg_hba.conf` et
   `sudo journalctl _COMM=sudo --since -3d | grep pg_hba` : qui, quand.

**Cause racine** : une règle `reject` insérée en tête de `pg_hba.conf`,
sans ticket ni test, rechargée un vendredi soir. `pg_hba.conf` est évalué
dans l'ordre ; une règle plus haut masque toute règle plus bas.

**Correctif**

```bash
sudo cp -a /etc/postgresql/16/main/pg_hba.conf ~/pg_hba.conf.incA1
sudo sed -i '/^# hardening 2026-09/,+1d' /etc/postgresql/16/main/pg_hba.conf
sudo -u postgres psql -c "SELECT pg_reload_conf();"
sudo -u postgres psql -c \
  "SELECT line_number, type, address, auth_method FROM pg_hba_file_rules;"
curl -s https://factura.lab.local/api/health | jq .status     # "ok"
```

Le worker s'est-il arrêté ? Non : il boucle avec « postgresql indisponible
… nouvel essai » et reprend seul. Les factures créées pendant la panne ?
L'API répondait 500 sur `POST /invoices` (l'`INSERT` échouait avant le
`LPUSH`) : rien à rattraper, les utilisateurs ont vu l'erreur.

**Prévention** : (1) `pg_hba_file_rules` (vue système) dans la checklist :
elle montre les règles **telles que lues** et signale les erreurs ; (2) toute
modification de `pg_hba.conf` passe par un test depuis `lab-web`
(`psql ... -c 'select 1'`) avant le `reload`, écrit dans le runbook ;
(3) le healthcheck aurait dû alerter en moins de 4 minutes — vérifier
`webhook.log` : l'alerte est bien partie vendredi à 18:32, personne ne
lisait. Une alerte sans destinataire est une ligne de log.

---

### **INC-A2** — factures en `error`, pas de PDF

*Un collègue a « remis les droits au propre » ; les factures passent en
`error`, tout est vert.*

**Diagnostic**

1. `journalctl -u factura-worker -n 30 --no-pager` sur `lab-web` →
   `export id=41 impossible : [Errno 13] Permission denied:
   '/srv/factura/exports/FAC-2026-001041.pdf.tmp'`. Errno 13 = permissions
   Unix (Errno 30 aurait été `ProtectSystem`).
2. `ls -ld /srv/factura/exports` → `drwxr-xr-x root root`. Le dossier
   appartient à root, `factura` n'a que la lecture.
3. `systemctl show -p ReadWritePaths factura-worker` → le chemin y est
   toujours : ce n'est pas l'unité. `sudo cat /root/.breakfix-backup/PA_02.exports.stat`
   ou, en vrai, `journalctl _COMM=chown --since today` / l'historique shell.
4. Étendue : `curl -s http://127.0.0.1:8000/invoices?limit=50 | jq -r
   '.[] | select(.status=="error") | .id'` → 3 factures ;
   `redis-cli -h lab-db -a ... LLEN factura:jobs:failed` → 3.

**Cause racine** : `chown root:root` + `chmod 755` sur
`/srv/factura/exports` par un `chown -R` trop large. Le worker, correctement
durci (`ProtectSystem=strict` + `ReadWritePaths`), n'a toujours que les
droits Unix de `factura` : le durcissement systemd ne **donne** jamais de
droits, il en retire.

**Correctif et récupération**

```bash
sudo chown factura:factura /srv/factura/exports
sudo chmod 0750 /srv/factura/exports
/usr/local/src/factura/tools/factura-smoke.sh --requeue -n 0
# ou, une par une : curl -X POST http://127.0.0.1:8000/invoices/41/requeue
redis-cli -h lab-db -a ChangeMe-Redis-2026 DEL factura:jobs:failed
curl -s 'http://127.0.0.1:8000/invoices?limit=50' \
  | jq -r '.[].status' | sort | uniq -c
```

**Pourquoi la supervision n'a rien vu** : le healthcheck teste `/health`
(base et Redis joignables : vrai), `factura_ worker_alive` (le worker tourne
et pose son battement de cœur : vrai) et la longueur de la file (vide, parce
que le worker consomme et échoue vite : vrai). Tous les signaux de
*liveness* sont verts ; le signal métier — « des factures finissent en
erreur » — n'était pas surveillé.

**Prévention** : ajouter `factura_invoices_total{status="error"}` au
healthcheck (seuil : > 0 pendant deux contrôles consécutifs → alerte), c'est
la version 1.2 du runbook ; et une remarque aux développeurs : un worker qui
échoue sur `EACCES` devrait sortir en erreur (et laisser systemd le relancer,
ce qui se verrait dans `NRestarts`) plutôt que marquer `error` et continuer.

---

### **INC-A3** — timeout depuis les postes

*Maintenance réseau et renouvellement de certificat le même jour ; depuis
les postes, timeout ; en local sur `lab-web`, tout va bien.*

**Diagnostic**

1. `curl -sv --max-time 5 https://factura.lab.local/` depuis `lab-adm` →
   `Trying 10.10.10.11:443...` puis `Connection timed out`. Pas de
   `Connected`, donc **aucune** poignée de main TLS : le certificat n'est
   pas en cause (un problème de certificat donnerait `SSL certificate
   problem` **après** `Connected`). Fausse piste éliminée en 5 secondes.
2. `ping -c2 10.10.10.11` → répond. `ssh lab-web` → passe. La machine est
   joignable, seul 443 est bloqué. Timeout (et non `refused`) = paquet
   **jeté** : pare-feu, pas service absent.
3. Sur `lab-web` : `ss -ltn 'sport = :443'` → écoute sur `0.0.0.0:443` ;
   `curl -k https://127.0.0.1/` → 200. nginx est sain.
4. `sudo ufw status numbered` → `[ 1] 443/tcp DENY IN 10.10.10.0/24 #
   maintenance reseau`, **avant** la règle `ALLOW`. ufw évalue dans l'ordre.
   `sudo nft list ruleset | grep -B2 'dport 443'` le confirme au niveau
   noyau. `sudo tail /var/log/ufw.log` montre les `[UFW BLOCK]` depuis
   `10.10.10.10` (si `ufw logging` est activé).
5. Sur `lab-ops`, `tail /var/log/factura/webhook.log` : l'alerte est partie
   1 min 41 s après la pose de la règle.

**Cause racine** : règle `deny` « temporaire » insérée en position 1 et
jamais retirée. Le renouvellement du certificat le même jour est une
coïncidence qui a orienté vers la mauvaise couche.

**Correctif**

```bash
sudo ufw status numbered | head -n 5
sudo ufw delete 1                # confirmer
curl -s --max-time 5 https://factura.lab.local/api/health | jq .status
```

**Prévention** : (1) une règle temporaire porte un commentaire avec date et
ticket, et un rappel (`systemd-run --on-active=4h ufw delete ...`, ou une
ligne dans le runbook) ; (2) la checklist « timeout » commence par `curl -v`
pour séparer TCP de TLS, puis `ufw status numbered` ; (3) le healthcheck fait
son travail : vérifier que quelqu'un lit `webhook.log`, ou mieux, y brancher
un vrai canal au module 26.

::: pourquoi
Les trois incidents ont un point commun : le système était **vert** partout
(`active (running)`, ports en écoute, certificats valides) et la panne était
dans une **règle** — `pg_hba`, permissions Unix, pare-feu. C'est la forme
la plus courante d'incident en production, et celle que la supervision de
base voit le moins bien. La méthode du module 19 (quelle couche, depuis où,
qu'est-ce qui a changé) est ce qui fait la différence entre 10 minutes et
2 heures.
:::
