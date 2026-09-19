# Module 18 — Conteneurs : Docker et Compose

## 18.0 Objectifs et compétences

::: objectif
À la fin de ce module, je sais :

* expliquer ce qu'est **réellement** un conteneur — des namespaces, des
  cgroups, un système de fichiers en couches et un jeu de capabilities — et le
  prouver avec `unshare`, `nsenter`, `/proc/PID/ns` et `/sys/fs/cgroup`, sans
  Docker ;
* énoncer les conséquences de « un conteneur n'est pas une VM » : noyau
  partagé, surface d'attaque, PID 1 qui ne se comporte pas comme un processus
  ordinaire ;
* installer Docker Engine depuis le dépôt officiel sur Ubuntu 24.04 et Rocky 9,
  expliquer pourquoi le groupe `docker` équivaut à root, et lancer un démon
  rootless ;
* lire une image comme un empilement de couches, distinguer tag et digest,
  et refuser `latest` en production ;
* piloter le cycle de vie d'un conteneur (`run`, `stop`, `kill`, `exec`,
  `logs`, `inspect`, `stats`, `cp`), interpréter les codes de sortie 0, 1,
  137, 139 et 143, et expliquer pourquoi `docker stop` prend parfois 10 s ;
* écrire un Dockerfile multi-stage propre : image de base choisie, cache
  respecté, non-root, `ENTRYPOINT` en forme exec, `HEALTHCHECK`,
  `.dockerignore`, versions épinglées — et le passer au scanner ;
* choisir entre volume nommé, bind mount et tmpfs, sauvegarder un volume, et
  résoudre un « permission denied » dû aux UID ;
* expliquer le bridge par défaut, les réseaux utilisateur et leur DNS, la
  publication de ports par iptables, et pourquoi `ufw` ne protège pas un port
  publié par Docker ;
* décrire une pile complète en `compose.yaml` (proxy, application, base,
  cache) avec `healthcheck`, `depends_on` conditionnel, secrets, profils et
  fichier d'override ;
* monter un registre privé, y pousser une image, et le sécuriser en TLS ;
* exploiter au quotidien : rotation des journaux, `docker system df`,
  `/var/lib/docker` plein, redémarrage au boot, durcissement (`cap-drop`,
  `read-only`, `no-new-privileges`, jamais `docker.sock` dans un conteneur).

Temps estimé : 9 h
Prérequis : modules 08 (processus, signaux, systemd, cgroups), 11 (réseau,
iptables), 03 (permissions et UID). Kubernetes est au module 22 et
l'intégration continue au module 21 : ici on ne construit et n'exploite que
des conteneurs sur une machine.
:::

---

## 18.1 Mise en place

VM principale : **`lab-ops` (10.10.10.14)** — 4 Go de RAM et 40 Go de disque,
c'est la seule VM dimensionnée pour Docker. **`lab-rhel` (10.10.10.13)** sert
à la variante Rocky et à Podman. **`lab-adm` (10.10.10.10)** joue le client
distant pour tester les ports publiés et le registre.

```bash
# depuis le shell Proxmox, avant de commencer
qm snapshot 9005 avant-lab18
qm snapshot 9004 avant-lab18
```

Outillage sur `lab-ops` (Docker lui-même s'installe au lab L18.1, **pas ici**,
et surtout pas via `snap` ni via le paquet `docker.io`) :

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg jq util-linux uidmap \
  dbus-user-session libcap2-bin python3 openssl apache2-utils
```

`util-linux` fournit `unshare`, `nsenter` et `lsns` ; `uidmap` et
`dbus-user-session` servent au mode rootless ; `libcap2-bin` fournit `capsh`
et `getpcaps` ; `apache2-utils` fournit `htpasswd` pour le registre.

::: rhel
Sur `lab-rhel` : `sudo dnf install -y dnf-plugins-core util-linux jq
libcap openssl httpd-tools`. Podman est déjà installé sur Rocky 9
(`podman --version`) ; Docker CE s'installe depuis le dépôt CentOS de Docker
(L18.1, variante).
:::

Préparation du terrain (idempotent) :

```bash
sudo bash ~/workbook/scripts/setup/setup_M18.sh
```

Il dépose l'application **fil rouge** du module, une petite API Flask :

| Chemin | Rôle |
|---|---|
| `~/lab18/api/app.py` | API HTTP sur 8000 : `/sante`, `/version`, `/visites`, `/compteur`, `/clients`, `/fuite` |
| `~/lab18/api/requirements.txt` | dépendances épinglées (Flask, redis, psycopg) |
| `~/lab18/mauvaise/` | la même API avec un Dockerfile « qui marche sur le poste de Kevin », à corriger |
| `/srv/factura-docker/data` | répertoire hôte, `root:root`, pour les bind mounts |

L'application lit sa configuration dans l'environnement (`PORT`, `BIND_ADDR`,
`DATA_DIR`, `REDIS_URL`, `DATABASE_URL`, `DATABASE_PASSWORD_FILE`,
`APP_VERSION`) et **réagit proprement à `SIGTERM`** : c'est important pour
plusieurs exercices. Le script ne crée aucun Dockerfile, aucun
`compose.yaml` : les écrire est le travail du module.

Pour le scanner d'images (L18.2), installe Trivy depuis son dépôt :

```bash
curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key \
  | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] \
https://aquasecurity.github.io/trivy-repo/deb generic main" \
  | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt update && sudo apt install -y trivy
```

::: attention
Les Break & Fix remplissent le disque de `lab-ops`, lancent des conteneurs en
boucle et modifient `/etc/docker/daemon.json`. Prends le snapshot. Et retiens
dès maintenant : **tout membre du groupe `docker` est root sur la machine**
(QO18.6) — sur `lab-ops` c'est acceptable, sur un serveur partagé non.
:::

---

## 18.2 Rappel express

### Ce qu'est un conteneur

Un conteneur est un **processus ordinaire** du noyau hôte, lancé avec :

| Mécanisme | Ce qu'il isole ou limite | Le voir |
|---|---|---|
| namespaces `pid` `net` `mnt` `uts` `ipc` `user` | PID, interfaces/routes, montages, hostname, IPC, UID | `lsns`, `ls -l /proc/PID/ns` |
| cgroups v2 | CPU, mémoire, PID, E/S | `/sys/fs/cgroup/.../memory.max` |
| overlayfs | couches d'image en lecture seule + couche d'écriture | `mount \| grep overlay` |
| capabilities | fragments de root conservés | `grep Cap /proc/PID/status` |

Conséquences : même noyau pour tous (un `uname -r` identique partout, une
faille noyau touche tout le monde), pas de « démarrage », un conteneur meurt
avec son processus principal, et ce processus est **PID 1** de son namespace —
le noyau ne lui délivre pas les signaux dont il n'a pas installé le handler.

```bash
unshare --pid --fork --mount-proc bash       # ps : bash est PID 1
unshare --user --map-root-user id            # root… dans le namespace
nsenter -t PID -n ss -tlnp                   # entrer dans un netns
cat /proc/PID/cgroup                         # 0::/system.slice/docker-….scope
capsh --decode=00000000a80425fb              # décoder CapEff
```

### Installation et démon

```bash
# Ubuntu : dépôt officiel, jamais snap ni docker.io
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) \
signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu noble stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt update && sudo apt install -y docker-ce docker-ce-cli \
  containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker mathieu    # = root sans mot de passe, cf QO18.6
docker info ; docker version ; systemctl status docker containerd
```

`/etc/docker/daemon.json` (puis `systemctl restart docker`) :

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "insecure-registries": ["lab-ops.lab.local:5000"]
}
```

::: rhel
Rocky 9 : `sudo dnf config-manager --add-repo
https://download.docker.com/linux/centos/docker-ce.repo` puis le même
`dnf install`, `systemctl enable --now docker`, et `firewall-cmd
--add-port=8080/tcp --permanent`. Alternative native : **Podman**
(`podman run`, `podman compose`, rootless par défaut, sans démon, `alias
docker=podman` via le paquet `podman-docker`). Sur bind mount avec SELinux :
suffixe `:Z` (`-v /srv/data:/data:Z`).
:::

### Images

```bash
docker pull nginx:1.28-alpine           # registre/dépôt:tag
docker pull nginx@sha256:…              # par digest : immuable
docker images ; docker image ls --digests
docker image inspect nginx:1.28-alpine --format '{{.Config.User}}'
docker history nginx:1.28-alpine        # une ligne par couche
docker tag factura-api:1.0 lab-ops.lab.local:5000/factura-api:1.0
docker push lab-ops.lab.local:5000/factura-api:1.0
docker rmi IMAGE ; docker image prune   # -a : aussi les non utilisées
```

Un tag est un **pointeur mobile** : `latest` ne veut pas dire « la dernière »
mais « ce que le mainteneur a poussé sous ce nom ». Seul le digest identifie
un contenu. Les couches sont partagées entre images et mises en cache.

### Conteneurs

```bash
docker run -d --name web -p 8080:80 --restart unless-stopped \
  --memory 128m --cpus 0.5 --user 10001:10001 --read-only --tmpfs /tmp \
  --cap-drop ALL --security-opt no-new-privileges -e CLE=val \
  --env-file app.env --network factura-net -v pg-data:/var/lib/postgresql \
  nginx:1.28-alpine
docker run --rm -it alpine:3.20 sh          # interactif, supprimé à la fin
docker run -d --init IMAGE                  # tini en PID 1 : signaux, zombies
docker ps -a ; docker ps --filter status=exited
docker logs -f --tail 100 --since 10m web
docker exec -it web sh ; docker exec -u 0 web id
docker stop web        # SIGTERM à PID 1, puis SIGKILL après 10 s (-t)
docker kill -s HUP web ; docker restart web
docker inspect web --format '{{.State.Status}} {{.State.ExitCode}}'
docker inspect web --format '{{.State.OOMKilled}} {{.State.Pid}}'
docker inspect web --format \
  '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
docker stats --no-stream ; docker top web ; docker cp web:/etc/nginx/ ./
docker events --since 15m ; docker container prune
```

| Code de sortie | Signification |
|---|---|
| `0` | fin normale |
| `1` | erreur applicative (lire `docker logs`) |
| `125` / `126` / `127` | erreur du démon / commande non exécutable / introuvable |
| `137` | `SIGKILL` (128+9) : `docker kill`, OOM (`OOMKilled: true`) ou `stop` expiré |
| `139` | `SIGSEGV` (128+11) : plantage |
| `143` | `SIGTERM` (128+15) reçu et non attrapé : arrêt « brut mais normal » |

### Dockerfile

```dockerfile
# syntax=docker/dockerfile:1
FROM python:3.12-slim-bookworm AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim-bookworm
LABEL org.opencontainers.image.source="https://git.lab.local/factura"
RUN groupadd -r -g 10001 app && useradd -r -u 10001 -g app app
WORKDIR /app
COPY --from=builder /install /usr/local
COPY --chown=app:app app.py .
ENV PYTHONUNBUFFERED=1
EXPOSE 8000
USER app
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD python3 -c "import urllib.request as u; \
u.urlopen('http://127.0.0.1:8000/sante', timeout=2)"
ENTRYPOINT ["python3", "app.py"]
```

| Instruction | Piège |
|---|---|
| `FROM` | `latest` ; `alpine` (musl) casse certains wheels ; distroless = pas de shell |
| `RUN` | une couche par `RUN` : grouper, `rm -rf /var/lib/apt/lists/*` **dans la même** |
| `COPY` vs `ADD` | `ADD` décompresse les tar et télécharge les URL : utiliser `COPY` |
| `ENV` vs `ARG` | `ARG` n'existe qu'au build ; `ENV` reste dans l'image (et `docker inspect`) |
| `CMD` vs `ENTRYPOINT` | `ENTRYPOINT` = programme, `CMD` = arguments par défaut ; forme **exec** (`["…"]`) sinon `sh -c` devient PID 1 |
| `EXPOSE` | documentation seulement ; ne publie rien |
| `USER` | sans lui, root ; l'UID doit exister ou être numérique |

Ordre = cache : tout ce qui change souvent (le code) **après** ce qui change
rarement (dépendances). `.dockerignore` : `.git`, `*.md`, secrets, données.

```bash
docker build -t factura-api:1.0 .            # BuildKit par défaut
docker build -f Dockerfile.debug --target builder --build-arg VER=1.0 \
  --no-cache --progress=plain -t factura-api:debug .
docker buildx build --platform linux/amd64,linux/arm64 -t … --push .
trivy image --severity HIGH,CRITICAL --ignore-unfixed factura-api:1.0
```

### Stockage et réseau

| Type | Syntaxe | Quand |
|---|---|---|
| volume nommé | `-v pg-data:/var/lib/postgresql/data` | données d'un service ; géré par Docker, sauvegardable |
| bind mount | `-v /srv/x:/x:ro` ou `--mount type=bind,src=,dst=` | conf, code en dev ; **UID hôte = UID conteneur** |
| tmpfs | `--tmpfs /tmp` | secrets éphémères, `--read-only` |

```bash
docker volume create pg-data ; docker volume ls ; docker volume inspect pg-data
docker run --rm -v pg-data:/from:ro -v "$PWD":/to alpine:3.20 \
  tar czf /to/pg-data.tgz -C /from .           # sauvegarde
docker network create factura-net              # DNS intégré 127.0.0.11
docker network ls ; docker network inspect bridge
docker run -d --network factura-net --name cache redis:7-alpine
docker run -d --network host … ; --network none
docker run -p 127.0.0.1:8080:80 …              # n'écoute que sur lo
```

Le bridge par défaut (`docker0`, `172.17.0.0/16`) **ne résout pas les noms**.
Publier un port ajoute des règles `iptables` dans les chaînes `DOCKER`
(`nat` et `filter`) **avant** celles d'`ufw` : seule la chaîne `DOCKER-USER`
est respectée.

### Compose v2

```bash
docker compose up -d --build ; docker compose ps ; docker compose logs -f app
docker compose exec app sh ; docker compose pull ; docker compose config
docker compose --profile debug up -d ; docker compose down -v   # -v : volumes
docker compose -f compose.yaml -f compose.prod.yaml up -d
```

`compose.yaml` : `name:`, `services:`, `volumes:`, `networks:`, `secrets:`.
Pas de `version:` (obsolète, ignoré avec avertissement). `.env` sert à
l'**interpolation** `${VAR}` du fichier ; `env_file:` injecte des variables
**dans le conteneur** : ce n'est pas la même chose. `depends_on` ne garantit
que l'ordre de démarrage, sauf avec `condition: service_healthy` et un
`healthcheck` sur la cible. `compose.override.yaml` est fusionné d'office.

### Exploitation

```bash
docker system df -v ; docker system prune -a --volumes    # destructeur
du -sh /var/lib/docker/{overlay2,containers,volumes,image}
ls -la /var/lib/docker/containers/ID/*-json.log
docker run --log-driver journald … ; journalctl CONTAINER_NAME=web
docker inspect web --format '{{json .State.Health}}' | jq
docker run --rm -it --pid container:app --network container:app \
  busybox sh                     # debug d'un conteneur sans shell
```

---

## 18.3 Quiz — QCM

**Q18.1** — Sur `lab-ops`, `docker run -d --name web -p 8080:80 nginx:1.28-alpine`
réussit. Un collègue relance exactement la même commande. Que se passe-t-il ?

a) un second conteneur `web` démarre, Docker choisit un autre port
b) la commande échoue : `Conflict. The container name "/web" is already in
   use by container "…"` ; le premier conteneur continue de tourner
c) le premier conteneur est remplacé par le second
d) la commande échoue sur `Bind for 0.0.0.0:8080 failed: port is already
   allocated` avant même de vérifier le nom

**Q18.2** — `time docker stop app` met exactement 10 secondes, et
`docker inspect app --format '{{.State.ExitCode}}'` renvoie `137`. Le
Dockerfile se termine par `CMD python3 app.py`. Explication ?

a) l'application met 10 s à fermer ses connexions, c'est normal
b) la forme shell de `CMD` fait de `/bin/sh -c` le PID 1 ; il ne relaie pas
   `SIGTERM` à Python et, en tant que PID 1 sans handler, l'ignore ; Docker
   envoie `SIGKILL` à l'expiration du délai
c) Python n'attrape jamais `SIGTERM`, il faut toujours `docker kill`
d) `137` signifie que l'application a planté pendant l'arrêt

**Q18.3** — `docker ps` affiche pour un conteneur lancé avec
`--restart always` : `Restarting (0) 2 seconds ago`. Qu'en déduis-tu ?
**Deux réponses correctes.**

a) le processus principal se termine **sans erreur** et Docker le relance en
   boucle : typiquement un script de démarrage qui lance le service en
   arrière-plan puis sort
b) Docker a détecté un healthcheck en échec et redémarre le conteneur
c) `docker logs app` montrera les sorties de toutes les tentatives, et
   `docker inspect --format '{{.RestartCount}}'` compte les relances
d) le conteneur a été tué par l'OOM killer

**Q18.4** — Tu as fait `sudo ufw deny 8080/tcp` sur `lab-ops`. Depuis
`lab-adm`, `curl http://10.10.10.14:8080` répond quand même, alors que le port
est publié par `docker run -p 8080:80`. Pourquoi ?

a) `ufw` ne filtre que les connexions sortantes
b) Docker insère ses règles de DNAT et de `FORWARD` dans ses propres chaînes
   `iptables` (`DOCKER`), évaluées avant celles d'`ufw` ; le trafic est
   redirigé vers le conteneur sans passer par `INPUT`
c) le port 8080 est ouvert par `docker-proxy` qui contourne le noyau
d) `ufw` doit être redémarré après chaque `docker run`

**Q18.5** — Dockerfile :

```dockerfile
FROM python:3.12-slim-bookworm
WORKDIR /app
COPY . .
RUN pip install --no-cache-dir -r requirements.txt
CMD ["python3", "app.py"]
```

À chaque modification de `app.py`, `pip install` est rejoué. Correction ?

a) ajouter `--no-cache` au build pour forcer un cache propre
b) copier d'abord `requirements.txt` seul, faire le `pip install`, puis
   `COPY . .` : une couche est invalidée dès que son entrée change, et toutes
   les suivantes avec elle
c) mettre `RUN pip install` avant `WORKDIR`
d) utiliser `ADD` au lieu de `COPY`, qui gère le cache

**Q18.6** — Différence entre `ARG` et `ENV` dans un Dockerfile ?

a) aucune, `ARG` est l'ancienne syntaxe
b) `ARG` est une variable de build fournie par `--build-arg`, absente du
   conteneur final ; `ENV` est enregistrée dans l'image et visible dans
   `docker inspect` et dans chaque processus du conteneur
c) `ENV` n'existe qu'au build, `ARG` persiste
d) `ARG` est chiffrée, `ENV` non

**Q18.7** — Deux conteneurs lancés sans option réseau : `app` et `redis`.
Dans `app`, `getent hosts redis` ne renvoie rien. Cause ?

a) il faut ajouter `--link redis` (méthode recommandée)
b) le bridge par défaut n'offre pas de résolution de noms entre conteneurs ;
   seuls les réseaux créés par `docker network create` disposent du DNS
   intégré (`127.0.0.11`)
c) Redis n'a pas publié son port avec `-p 6379:6379`
d) les deux conteneurs sont dans des namespaces réseau différents et ne
   peuvent pas communiquer

**Q18.8** — L'image `postgres:16-alpine` contient des fichiers dans
`/var/lib/postgresql/data`. Tu montes ce chemin. Dans quel cas le contenu de
l'image est-il **copié** dans le montage au premier démarrage ?

a) avec un bind mount `-v /srv/pg:/var/lib/postgresql/data`
b) avec un volume nommé vide `-v pg-data:/var/lib/postgresql/data`
c) dans les deux cas
d) dans aucun cas, le montage masque toujours le contenu

**Q18.9** — `docker run -d --memory 64m --name gourmand factura-api:1.0`, puis
`curl 'localhost:8080/fuite?mo=100'`. Ensuite `docker ps -a` montre
`Exited (137)`. Qu'est-ce qui le confirme sans ambiguïté ?

a) `docker logs gourmand` contient « Killed »
b) `docker inspect gourmand --format '{{.State.OOMKilled}}'` renvoie `true`,
   et `dmesg`/`journalctl -k` montre `Memory cgroup out of memory`
c) `docker stats` affiche 100 %
d) le code 137 suffit : il signifie toujours OOM

**Q18.10** — Hier, `docker pull nginx` a ramené `nginx:latest`. Aujourd'hui
`docker run -d nginx` démarre. Quelle version tourne ?

a) la dernière publiée sur Docker Hub : `run` vérifie toujours le registre
b) celle téléchargée hier : `latest` est un tag comme un autre, `run` utilise
   l'image locale si elle existe, et rien ne dit que ce tag pointe vers la
   version la plus récente
c) une version aléatoire parmi celles en cache
d) `latest` n'est pas un tag valide pour `run`

**Q18.11** — Un dev demande `-v /var/run/docker.sock:/var/run/docker.sock`
pour son conteneur de CI. **Deux réponses correctes.**

a) c'est sans risque tant que le conteneur tourne en `--user 1000`
b) quiconque contrôle ce conteneur peut lancer
   `docker run -v /:/host --privileged … chroot /host` et devenir root sur
   `lab-ops`
c) c'est l'équivalent exact d'ajouter l'utilisateur au groupe `docker` : accès
   root sans mot de passe
d) Docker refuse ce montage sans `--privileged`

**Q18.12** — Dans un `compose.yaml`, `app` déclare
`depends_on: [db]` (forme courte). Au `docker compose up`, `app` plante avec
`connection refused` vers `db`, puis fonctionne après un `restart`. Pourquoi ?

a) `depends_on` n'ordonne que le **démarrage des conteneurs**, pas la
   disponibilité du service : PostgreSQL met quelques secondes à accepter des
   connexions ; il faut `condition: service_healthy` et un `healthcheck` sur `db`
b) il manque `links:`
c) `db` doit être déclaré avant `app` dans le fichier
d) `app` doit publier le port de `db`

**Q18.13** — Dans le répertoire du `compose.yaml`, un fichier `.env` contient
`POSTGRES_PASSWORD=secret`. Le service `db` ne reçoit pas cette variable.
Pourquoi ?

a) `.env` doit s'appeler `docker.env`
b) `.env` sert à l'**interpolation** des `${VAR}` dans le fichier Compose, pas
   à peupler l'environnement des conteneurs ; il faut `env_file:` ou
   `environment:` sur le service
c) les variables de `.env` sont réservées aux `build:`
d) Compose ne lit `.env` qu'avec `--env-file`

**Q18.14** — `docker exec -it app sh` répond `OCI runtime exec failed: …
exec: "sh": executable file not found in $PATH`. Quelles approches permettent
d'inspecter le conteneur ? **Deux réponses correctes.**

a) `docker run --rm -it --pid container:app --network container:app
   busybox sh`, qui partage ses namespaces sans toucher à son image
b) reconstruire l'image avec `FROM alpine` en production
c) `nsenter -t $(docker inspect app --format '{{.State.Pid}}') -n -m -p`
   depuis l'hôte
d) `docker exec -it --shell app`

**Q18.15** — `/var/lib/docker/containers/` pèse 9 Go sur `lab-ops`, à cause
d'un fichier `*-json.log` d'un seul conteneur. Tu ajoutes `max-size` dans
`daemon.json` et redémarres Docker. **Deux réponses correctes.**

a) le fichier existant est immédiatement tronqué à `max-size`
b) la rotation ne s'applique qu'aux conteneurs **créés après** le changement ;
   celui-ci doit être recréé (`docker rm` + `run`, ou `compose up -d
   --force-recreate`)
c) en attendant, `truncate -s 0` sur le fichier libère l'espace sans arrêter le
   conteneur
d) il faut passer au driver `syslog`, `json-file` ne sait pas tourner

**Q18.16** — `docker run -d -p 127.0.0.1:8080:80 nginx:1.28-alpine`. Que
donne `curl http://10.10.10.14:8080` depuis `lab-adm` ?

a) une réponse normale
b) `Connection refused` : le port n'est publié que sur la boucle locale de
   `lab-ops` ; c'est la bonne façon d'exposer un service uniquement à un
   reverse proxy local
c) une redirection vers 127.0.0.1
d) un timeout, car `ufw` bloque

**Q18.17** — Un conteneur lancé avec `--cap-drop ALL --user 10001` échoue
avec `chown: changing ownership of '/data': Operation not permitted`. Cause ?

a) `--user` interdit toujours `chown`
b) `chown` sur un fichier qu'on ne possède pas requiert `CAP_CHOWN` ; toutes
   les capabilities ont été retirées, et même en root le conteneur ne pourrait
   pas
c) il faut `--privileged`
d) `/data` est en lecture seule

**Q18.18** — `docker rmi factura-api:1.0` répond `conflict: unable to remove
repository reference "factura-api:1.0" (must force) - container 3f2a… is using
its referenced image`. Le conteneur `3f2a…` est **arrêté**. Que fais-tu ?

a) `docker rmi -f`, sans conséquence
b) `docker rm 3f2a` puis `docker rmi` : un conteneur, même arrêté, référence
   ses couches ; forcer supprimerait le tag mais laisserait les couches
   (image `<none>`) tant que le conteneur existe
c) `docker system prune -a --volumes` immédiatement
d) redémarrer Docker

---

## 18.4 Quiz — questions ouvertes

**QO18.1** — *On te demande en entretien* : « Quelle est la différence entre
un conteneur et une machine virtuelle ? » Réponds sans citer une seule commande
Docker : nomme les mécanismes noyau impliqués, ce que chacun isole ou limite,
et déduis-en trois conséquences concrètes pour la sécurité, la performance et
l'exploitation.

::: repondre
lignes: 12
:::

**QO18.2** — *On te demande en entretien* : « `ENTRYPOINT` ou `CMD` ? Forme
exec ou forme shell ? » Explique comment les deux se combinent, ce que
`docker run image arg` remplace, ce qui devient PID 1 dans chaque forme, et
pourquoi ce PID 1 change le comportement de `docker stop`. Termine par le rôle
de `--init`.

::: repondre
lignes: 12
:::

**QO18.3** — Décris le fonctionnement du cache de build : ce qui invalide une
couche, ce qui se propage, pourquoi `COPY . .` en tête de Dockerfile est un
contresens, ce qu'apporte un build multi-stage, et comment tu vérifies la
taille de chaque couche d'une image produite.

::: repondre
lignes: 10
:::

**QO18.4** — Un conteneur « ne démarre pas ». Déroule ta méthode de diagnostic
dans l'ordre, avec pour chaque étape la commande et **ce que tu cherches** :
état et code de sortie, journaux, configuration effective, image sans shell,
port déjà pris, dépendance absente, permissions sur un montage, limite
mémoire. Distingue les codes 0, 1, 125, 137, 139, 143.

::: repondre
lignes: 14
:::

**QO18.5** — Explique le trajet d'un paquet TCP de `lab-adm` vers un conteneur
qui a publié `-p 8080:80` sur `lab-ops` : chaînes `iptables` traversées,
DNAT, rôle de `docker-proxy`, et pourquoi `ufw` n'a pas son mot à dire.
Donne ensuite deux façons correctes de restreindre l'accès à ce port.

::: repondre
lignes: 10
:::

**QO18.6** — *On te demande en entretien* : « Pourquoi dit-on que le groupe
`docker` équivaut à root ? » Donne la commande en une ligne qui le prouve,
puis explique ce que change le mode rootless (où tourne le démon, comment les
UID sont projetés, ce qui ne marche plus). Cite enfin cinq options de
`docker run` qui réduisent la surface d'attaque d'un conteneur et ce que
chacune empêche.

::: repondre
lignes: 12
:::

**QO18.7** — Un développeur monte `~/projet/data` dans son conteneur et obtient
`PermissionError: [Errno 13] Permission denied`. Explique ce qui se passe au
niveau des UID entre l'hôte et le conteneur, pourquoi un volume nommé n'aurait
pas posé le problème, et donne trois corrections possibles avec leurs
inconvénients.

::: repondre
lignes: 10
:::

**QO18.8** — Dans une pile Compose (proxy, app, base, cache), explique ce que
fait précisément `docker compose down` par rapport à `stop`, ce que `-v`
détruit, comment tu mets à jour **uniquement** l'image de `app` sans couper les
autres services, et comment tu fais démarrer la pile au boot de la machine sans
écrire d'unité systemd.

::: repondre
lignes: 10
:::

**QO18.9** — Trivy remonte 41 CVE sur ton image, dont 3 `CRITICAL` dans
`libssl3` de l'image de base et 1 `HIGH` dans une bibliothèque Python.
Décris ta démarche de décision : ce que tu vérifies pour chaque CVE, ce qui
justifie d'ignorer une alerte, ce qui impose un rebuild, et pourquoi
`--ignore-unfixed` est à la fois utile et dangereux.

::: repondre
lignes: 8
:::

---

## 18.5 Exercices guidés ★

E18.1 et E18.2 se font **avant** d'installer Docker : ils montrent ce que
Docker fera pour toi. À partir de E18.3, il te faut Docker installé (lab
L18.1) et l'image `nginx:1.28-alpine` lancée sous le nom `web` avec le port
8080 publié. Tout se passe sur `lab-ops` sauf mention contraire.

**E18.1** — Sans Docker, lance un shell qui est **PID 1** de son propre
namespace PID, avec un `/proc` cohérent, et un hostname `conteneur-test` qui
n'affecte pas `lab-ops`. Prouve les trois points depuis l'intérieur (`ps`,
`hostname`) et depuis un second terminal sur l'hôte (`hostname`, `lsns`,
`ls -l /proc/PID/ns` comparé à ton shell). Recommence sans `sudo` et explique
ce qui rend cela possible.

**E18.2** — Toujours sans Docker, exécute
`python3 -c 'b = bytearray(200 * 1024 * 1024); input()'` dans un cgroup
limité à 64 Mo de mémoire **et sans swap**. Montre que le processus est tué,
retrouve la preuve dans le fichier `memory.events` du cgroup et dans
`journalctl -k`, puis donne l'équivalent avec `systemd-run`.

**E18.3** — Retrouve, depuis l'hôte, le PID du processus `nginx` maître du
conteneur `web`. Affiche ses namespaces, montre lesquels diffèrent de ceux de
ton shell, affiche son cgroup, et liste les ports en écoute **dans** son
namespace réseau sans `docker exec`. Termine par la commande `lsns` qui liste
tous les namespaces réseau de la machine avec le premier processus de chacun.

**E18.4** — Affiche les capabilities effectives du PID 1 du conteneur `web`,
décode-les en clair, et compare avec un conteneur lancé avec `--cap-drop ALL`
puis avec `--cap-drop ALL --cap-add NET_BIND_SERVICE`. Dis laquelle des
capabilities par défaut permet à `nginx` d'écouter sur 80 en root.

**E18.5** — Pour l'image `nginx:1.28-alpine` : affiche son digest, le nombre
de couches, la taille de chaque couche et l'instruction qui l'a produite.
Télécharge ensuite la même image **par digest** et prouve avec `docker images`
qu'aucun octet n'a été téléchargé et qu'il s'agit du même ID d'image.

**E18.6** — Lance un conteneur `alpine:3.20` interactif limité à 64 Mo de
mémoire, un demi-cœur et 50 processus, et prouve les trois limites **depuis
l'intérieur** du conteneur en lisant les fichiers du cgroup. Puis, depuis
l'hôte, retrouve le même cgroup sous `/sys/fs/cgroup/system.slice/`.

**E18.7** — Chronomètre `docker stop` sur trois conteneurs : `sleep 3600`
lancé tel quel, le même avec `--init`, et `sh -c 'sleep 3600; echo fin'`.
Relève pour chacun la durée et le code de sortie, et explique les trois
résultats en une phrase chacun. Produis ensuite un conteneur qui sort en
`139` et un autre en `1`.

**E18.8** — Sur le conteneur `web`, en une commande chacune et sans `grep` ni
`jq` quand `--format` suffit : son adresse IP, sa politique de redémarrage, la
liste de ses montages (source et destination), la commande complète qui a
servi à le lancer, et les 20 dernières lignes de journal des cinq dernières
minutes horodatées. Copie enfin `/etc/nginx/conf.d/default.conf` du
conteneur vers `~/lab18/rapports/` sans `docker exec`.

**E18.9** — Dans `~/lab18/bin/entrypoint-test/`, écris un Dockerfile de
trois lignes à base d'`alpine:3.20` dont `docker run --rm IMAGE` affiche
`bonjour monde` et `docker run --rm IMAGE lab-ops` affiche `bonjour lab-ops`.
Puis remplace l'`ENTRYPOINT` par sa forme shell, reconstruis, et explique ce
que devient `CMD`. Montre enfin comment lancer `sh` dans cette image malgré
l'`ENTRYPOINT`.

**E18.10** — Écris un Dockerfile qui prend un argument de build `VERSION`
(valeur par défaut `dev`), le stocke dans la variable d'environnement
`APP_VERSION` de l'image et l'écrit dans `/version.txt`. Construis avec
`VERSION=1.2`, puis prouve trois choses : `APP_VERSION` est visible dans
l'image, `VERSION` n'y est pas, et pourtant `docker history` révèle sa valeur.
Conclus sur ce qu'on ne doit **jamais** passer en `--build-arg`.

**E18.11** — Dans `~/lab18/api/`, construis l'image avec le Dockerfile de la
question Q18.5 (copie de tout le contexte avant `pip install`). Modifie un
commentaire dans `app.py`, reconstruis, et relève dans la sortie
`--progress=plain` les étapes rejouées. Corrige l'ordre des instructions,
refais la même modification et montre que `pip install` sort de `CACHED`.
Chronomètre les deux reconstructions.

**E18.12** — Crée un volume `factura-data`, écris-y un fichier depuis un
conteneur, supprime le conteneur, prouve que le fichier survit dans un second
conteneur. Sauvegarde ce volume dans `~/lab18/rapports/factura-data.tgz` sans
arrêter quoi que ce soit ni utiliser `sudo`, puis restaure l'archive dans un
nouveau volume `factura-data-copie` et vérifie le contenu.

**E18.13** — Avec `alpine:3.20`, `--user 10001:10001` et un bind mount de
`/srv/factura-docker/data` sur `/data`, tente de créer un fichier. Note
l'erreur exacte. Corrige **côté hôte**, sans `chmod 777`, crée le fichier,
puis affiche depuis l'hôte à qui il appartient en numérique et en nom. Explique
la ligne obtenue.

**E18.14** — Crée le réseau `factura-net`. Lance `cache` (`redis:7-alpine`)
dessus et prouve depuis un conteneur du même réseau que le nom `cache` se
résout, que le serveur DNS utilisé est `127.0.0.11`, et que le même test
échoue depuis un conteneur du bridge par défaut. Affiche ensuite les règles
`iptables` (table `nat` et chaîne `DOCKER`) créées par la publication du port
8080 de `web`.

**E18.15** — Lance un conteneur qui écrit des lignes de journal sans pause
(`yes` fait l'affaire), avec une rotation à 1 Mo sur 2 fichiers configurée
**pour ce seul conteneur**. Après 10 s, montre les fichiers de journal côté
hôte, leur taille, et prouve que `docker logs` ne renvoie plus l'intégralité
de l'historique. Donne la ligne `daemon.json` qui rendrait cette rotation
globale, puis arrête et supprime ce conteneur.

**E18.16** — Dans un second terminal, laisse tourner `docker events`. Dans le
premier, crée puis supprime un conteneur et un volume. Relève les événements
produits. Puis affiche l'occupation disque de Docker par catégorie, avec le
détail par image, et explique la différence entre les colonnes `SIZE`,
`SHARED SIZE` et `RECLAIMABLE`.

---

## 18.6 Labs ★★

### **L18.1** — Installer Docker Engine proprement sur `lab-ops`

::: contexte
`lab-ops` va héberger le registre, le runner CI et le monitoring des modules
suivants. On te demande une installation **reproductible** de Docker Engine
depuis le dépôt officiel, un démon configuré dès le départ (journaux bornés,
registre local) et un compte de service pour les futurs pipelines. La variante
Rocky et le mode rootless font partie du ticket.
:::

1. Vérifie qu'aucun Docker n'est déjà présent (`docker.io`, snap `docker`,
   `podman-docker`). Si oui, retire-le et note ce qui resterait dans
   `/var/lib/docker`.
2. Ajoute le dépôt `download.docker.com` pour Ubuntu `noble` avec sa clé
   dans `/etc/apt/keyrings/`, puis installe `docker-ce`, `docker-ce-cli`,
   `containerd.io`, `docker-buildx-plugin` et `docker-compose-plugin`.
   Vérifie avec `apt-cache policy docker-ce` que le paquet vient bien de
   `download.docker.com`.
3. Écris `/etc/docker/daemon.json` : driver `json-file` limité à 10 Mo × 3
   fichiers, et `lab-ops.lab.local:5000` en registre non sécurisé (le lab
   L18.5 le passera en TLS). Valide le JSON **avant** de redémarrer le démon,
   puis prouve avec `docker info` que les deux réglages sont pris en compte.
4. Le service doit démarrer au boot. Vérifie aussi l'état de `containerd` et
   explique en une ligne ce que `docker.socket` change au démarrage.
5. Ajoute `mathieu` au groupe `docker`, ouvre une nouvelle session, et prouve
   par une seule commande `docker run` que ce compte peut lire
   `/etc/shadow` de l'hôte. Écris la conclusion dans
   `~/lab18/rapports/installation.md`.
6. Ajoute au même rapport : la version d'Engine, de Compose et de buildx, le
   driver de stockage, la version de cgroup, et le chemin racine des données.
7. Variante rootless : crée un compte `kevin`, installe
   `docker-ce-rootless-extras`, ouvre une session **complète** sur ce compte
   (`ssh kevin@localhost` ou `machinectl shell kevin@`), lance
   `dockerd-rootless-setuptool.sh install`, active le *lingering*, et lance
   `nginx:1.28-alpine` publié sur le port 8081. Montre ensuite quel
   utilisateur porte le processus `dockerd` et pourquoi le port 80 aurait été
   refusé.

::: rhel
Sur `lab-rhel` : `sudo dnf config-manager --add-repo
https://download.docker.com/linux/centos/docker-ce.repo`, le même `dnf
install`, `sudo systemctl enable --now docker`, puis `sudo firewall-cmd
--add-port=8080/tcp --permanent && sudo firewall-cmd --reload`. Compare
ensuite avec Podman déjà présent : `podman run -d -p 8080:80
docker.io/library/nginx:1.28-alpine` sans `sudo`, `podman ps`, et
`ps -o user,pid,args -C conmon`. Note deux différences visibles.
:::

::: check
Critère de succès : `docker-ce` installé depuis le dépôt Docker, service actif
et activé, `daemon.json` valide avec rotation et registre, `mathieu` dans le
groupe `docker`, plugins Compose v2 et buildx fonctionnels, rapport rédigé.

```bash
bash check_M18_01.sh
```
:::

---

### **L18.2** — Du Dockerfile de Kevin à une image livrable

::: contexte
L'équipe précédente a laissé `~/lab18/mauvaise/` : « ça marche sur le poste
de Kevin ». L'image fait 1,2 Go, contient un mot de passe, tourne en root et
met 10 s à s'arrêter. On te demande un audit écrit, puis une image propre de
`~/lab18/api/`, scannée, et la preuve que les défauts sont corrigés.
:::

1. Construis l'image de Kevin telle quelle (`docker build -t factura-api:kevin
   ~/lab18/mauvaise`). Relève : sa taille, le temps de build, ce que
   `docker history` montre, l'utilisateur d'exécution, les variables
   d'environnement visibles dans `docker inspect`, et le temps que met
   `docker stop`. Vérifie si `secret.txt` et `donnees/export-clients.bin` sont
   dans l'image.
2. Rédige `~/lab18/rapports/audit-dockerfile.md` : un tableau **ligne du
   Dockerfile → problème → correction**. Il doit couvrir au moins huit
   défauts distincts.
3. Dans `~/lab18/api/`, écris `.dockerignore` puis un `Dockerfile`
   **multi-stage** : image de base épinglée, dépendances installées dans le
   premier étage à partir de `requirements.txt` seul, code copié en dernier,
   utilisateur `app` (UID 10001) créé et actif, `/data` prêt à recevoir un
   volume, `ENTRYPOINT` en forme exec, `HEALTHCHECK` sur `/sante`,
   `APP_VERSION` fournie par un argument de build, labels
   `org.opencontainers.image.version` et `.source`.
4. Construis `factura-api:1.0` avec `APP_VERSION=1.0`. Vise moins de 150 Mo.
   Vérifie : utilisateur, healthcheck, taille, absence de fichiers parasites,
   `docker stop` en moins de 2 s avec code de sortie `0`, et le passage de
   l'état `(health: starting)` à `(healthy)` dans `docker ps`.
5. Scanne l'image avec Trivy (`HIGH,CRITICAL`, sans les CVE sans correctif),
   enregistre le rapport dans `~/lab18/rapports/trivy-factura-api.txt`, et
   compare le nombre de CVE avec l'image de Kevin. Si une CVE `CRITICAL` reste
   sur l'image de base, note la version corrigée de l'image de base à prendre.
6. Ajoute un étage `debug` (avec `sh`, `curl`, `procps`) constructible par
   `--target debug`, sans que la cible par défaut change.

::: astuce
`docker build --progress=plain --no-cache . 2>&1 | grep -E '^#[0-9]+ '` liste
les étapes ; `docker history --no-trunc --format '{{.Size}}\t{{.CreatedBy}}'`
dit où partent les mégaoctets. Un `RUN apt-get install` sans nettoyage dans la
**même** couche coûte 40 Mo de listes de paquets à vie.
:::

::: check
Critère de succès : image `factura-api:1.0` sous 150 Mo, non-root, avec
healthcheck et `ENTRYPOINT` exec, qui s'arrête proprement, sans secret ni
fichier de données, `.dockerignore` et audit présents.

```bash
bash check_M18_02.sh
```
:::

---

### **L18.3** — Données, UID et réseau : faire tourner l'API pour de vrai

::: contexte
L'API doit conserver ses compteurs de visites entre deux déploiements, lire
un cache Redis, et n'être joignable que depuis `lab-adm`. Le répertoire hôte
`/srv/factura-docker/data` a été créé par l'équipe système en `root:root`.
Tu utilises l'image `factura-api:1.0` du lab précédent.
:::

1. Lance l'API avec `DATA_DIR=/data` et le volume nommé `factura-data` sur
   `/data`. Appelle `/visites` trois fois, supprime le conteneur, relance,
   appelle une quatrième fois : le compteur doit être à 4. Explique où sont
   physiquement les données et pourquoi le premier démarrage n'a pas échoué
   en permissions alors que l'application tourne en UID 10001.
2. Remplace le volume par un bind mount de `/srv/factura-docker/data`.
   Reproduis l'erreur `PermissionError`, corrige côté hôte de la façon la plus
   restrictive possible, et vérifie. Note ce que `ls -ln` affiche pour le
   fichier créé et ce qu'afficherait un `ls -l` sur un hôte où l'UID 10001
   existe.
3. Crée `factura-net`. Lance `cache` (`redis:7-alpine`, sans port publié,
   sans données persistantes) et l'API sous le nom `factura-visites`, sur ce
   réseau, avec `REDIS_URL=redis://cache:6379/0`. `/compteur` doit
   s'incrémenter. Prouve que `cache` n'est joignable ni depuis l'hôte ni
   depuis un conteneur du bridge par défaut.
4. Durcis `factura-visites` : système de fichiers racine en lecture seule,
   `/tmp` en tmpfs, aucune capability, `no-new-privileges`, 128 Mo de mémoire
   sans swap, redémarrage automatique sauf arrêt manuel. L'API doit continuer
   à écrire dans `/data`.
5. Publie le port 8000 de `factura-visites` sur `10.10.10.14:8000`. Depuis
   `lab-adm`, `curl http://10.10.10.14:8000/sante` doit répondre. Depuis
   `lab-web`, la connexion doit **expirer**, sans toucher à `ufw` et sans
   republier le port. Montre la règle et la chaîne où tu l'as placée, et
   explique pourquoi c'est la seule chaîne où Docker la respectera.
6. Sauvegarde le volume `factura-data` dans `~/lab18/rapports/` et documente
   la procédure de restauration en trois lignes dans
   `~/lab18/rapports/stockage.md`, avec le tableau volume / bind / tmpfs et
   le cas d'usage de chacun.

::: attention
Une règle `iptables` ajoutée à la main disparaît au redémarrage, et Docker
recrée ses propres chaînes à chaque démarrage du démon. La règle de l'étape 5
doit donc vivre dans un fichier rejoué au boot : dis lequel dans le rapport.
:::

::: check
Critère de succès : volume `factura-data` peuplé, `/srv/factura-docker/data`
écrivable par l'UID 10001 sans être ouvert à tous, `cache` et
`factura-visites` sur `factura-net`, API durcie et publiée sur 8000,
règle `DOCKER-USER` limitant l'accès à `10.10.10.10`.

```bash
bash check_M18_03.sh
```
:::

---

### **L18.4** — La pile complète en Compose : proxy, API, PostgreSQL, Redis

::: contexte
Le développeur veut « un `docker compose up` et tout marche » : nginx en
frontal sur 8080, l'API derrière, PostgreSQL pour `/clients`, Redis pour
`/compteur`, et un mot de passe de base qui n'apparaît **nulle part** dans
`docker inspect`. L'environnement de dev doit pouvoir monter le code source
sans modifier le fichier principal.
:::

Tout se fait dans `~/lab18/compose/`.

1. Écris `compose.yaml` avec le nom de projet `factura` et quatre services :
   `proxy` (`nginx:1.28-alpine`, port 8080 publié, configuration montée en
   lecture seule depuis `./nginx/default.conf`), `app` (construit depuis
   `../api`, image `factura-api:${APP_VERSION}`), `db` (`postgres:16-alpine`,
   volume nommé `pg-data`), `cache` (`redis:7-alpine`, sans persistance).
   Un `.env` fournit `APP_VERSION=1.0`.
2. Le mot de passe PostgreSQL vit dans `./secrets/db_password.txt` et
   parvient à `db` et à `app` **par un secret Compose**, jamais par
   `environment:`. Attention aux droits du fichier : `db` le lit avec l'UID
   70, `app` avec l'UID 10001.
3. `db` et `cache` ont un `healthcheck`. `app` n'est démarré que lorsque les
   deux sont **en bonne santé**, et `proxy` seulement lorsque `app` l'est.
   Prouve la séquence avec `docker compose up -d` suivi de `docker compose
   ps` pendant le démarrage, puis avec `docker compose events`.
4. `app` tourne durci (lecture seule, tmpfs, `cap_drop`,
   `no-new-privileges`), avec `DATA_DIR` sur un volume `app-data`, et tous
   les services redémarrent sauf arrêt manuel. `curl
   http://127.0.0.1:8080/clients`, `POST /clients?nom=Dupont` puis
   `/compteur` doivent fonctionner à travers le proxy.
5. Ajoute un service `adminer` (`adminer:4`, port `127.0.0.1:8081`) dans un
   profil `debug` : il ne doit pas démarrer par défaut. Vérifie avec
   `docker compose config --services` avec et sans `--profile debug`.
6. Écris `compose.override.yaml` pour le dev : monte `../api` dans `app` en
   lecture seule, publie son port 8000 sur `127.0.0.1`, et force
   `APP_VERSION=dev` **sans** toucher au `.env`. Puis `compose.prod.yaml` qui
   retire le `build:`, utilise l'image du registre
   `lab-ops.lab.local:5000/factura-api:${APP_VERSION}` et fixe la rotation des
   journaux à 5 Mo × 2. Montre la commande qui applique l'un ou l'autre et
   vérifie le résultat avec `docker compose config`.
7. Mets à jour uniquement `app` après une modification de `app.py` (le
   message de `/` doit changer), sans redémarrer `db` ni `cache` : prouve-le
   avec le `CreatedAt` ou le temps de fonctionnement des quatre conteneurs.
8. Redémarre `lab-ops`. La pile doit revenir seule. Note dans
   `~/lab18/rapports/compose.md` la différence entre `stop`, `down`,
   `down -v`, et ce qui a fait revenir la pile au boot.

::: astuce
`docker compose config` affiche le fichier **résolu** : variables
interpolées, override fusionné, profils filtrés. C'est ce que Compose exécute
réellement — relis-le avant chaque `up` dès que tu utilises plusieurs
fichiers.
:::

::: check
Critère de succès : la pile `factura` tourne, `/clients` et `/compteur`
répondent via `:8080`, les quatre services sont `healthy` ou dépendent de
services `healthy`, le mot de passe n'apparaît pas dans l'environnement de
`app`, le profil `debug` est inactif par défaut, `compose.override.yaml` et
`compose.prod.yaml` sont valides.

```bash
bash check_M18_04.sh
```
:::

---

### **L18.5** — Un registre privé sur `lab-ops`

::: contexte
Les images ne doivent plus transiter par Docker Hub ni par des `docker save`
envoyés en pièce jointe. On te demande un registre sur `lab-ops`, d'abord en
clair pour comprendre, puis avec TLS et authentification, consultable depuis
`lab-adm` et utilisable par Podman sur `lab-rhel`.
:::

Tout se fait dans `~/lab18/registre/`.

1. Lance `registry:2.8` sous le nom `registre`, port 5000, données dans un
   volume `registre-data`, redémarrage automatique. Tague `factura-api:1.0`
   pour ce registre, pousse-la, et liste le catalogue et les tags avec `curl`.
   Explique pourquoi le `push` fonctionne alors qu'il n'y a ni TLS ni
   authentification, et où ce comportement est configuré.
2. Depuis `lab-adm`, `curl http://lab-ops.lab.local:5000/v2/_catalog`
   (ajoute l'entrée dans `/etc/hosts` si besoin). Constate, puis explique
   pourquoi un `docker pull` depuis une autre machine serait refusé sans
   configuration supplémentaire.
3. Génère un certificat autosigné pour `lab-ops.lab.local` (avec `IP:
   10.10.10.14` en SAN), un fichier `htpasswd` en **bcrypt** pour
   l'utilisateur `ci`, et relance le registre avec TLS et authentification
   `htpasswd`. Retire `insecure-registries` de `daemon.json`.
4. Fais confiance au certificat côté client Docker sur `lab-ops` **sans**
   l'ajouter au magasin système, connecte-toi avec `docker login`, repousse
   l'image, et montre où Docker a stocké les identifiants et sous quelle
   forme.
5. Depuis `lab-adm`, `curl` le catalogue avec le certificat et les
   identifiants. Depuis `lab-rhel`, fais confiance au certificat pour Podman,
   `podman login` puis `podman pull` de l'image, et lance-la.
6. Supprime le tag `1.0` du registre par l'API (il faut activer la
   suppression), puis lance le ramasse-miettes du registre. Documente dans
   `~/lab18/rapports/registre.md` : les chemins, la procédure de rotation du
   mot de passe, et ce qui manque encore pour la production (au moins trois
   points).

::: check
Critère de succès : `registre` en TLS avec authentification sur 5000, image
`lab-ops.lab.local:5000/factura-api` présente dans le catalogue, `docker
login` réussi depuis `lab-ops`, certificat de confiance déposé au bon endroit,
`insecure-registries` retiré, rapport rédigé.

```bash
bash check_M18_05.sh
```
:::

---

## 18.7 Break & Fix ★★★

::: attention
Avant chaque Break & Fix : `qm snapshot 9005 avant-bf18`. Le snapshot de
secours reste `snap-clean` (`qm rollback 9005 snap-clean`), mais l'utiliser
vaut échec de l'exercice. Les scripts supposent Docker installé (L18.1) et
construisent une image `factura-bf:base` au premier lancement.
:::

### **BF18.1** — « L'API legacy redémarre toute seule et met 10 s à s'arrêter »

```bash
sudo bash break_M18_01.sh
```

**Symptôme utilisateur** : le conteneur `factura-legacy` (port 8001) répond
pendant une trentaine de secondes, puis `curl` échoue, puis ça remarche.
`docker ps` le montre tantôt `Up 12 seconds`, tantôt `Restarting (0)`. Un
`docker stop factura-legacy` prend exactement 10 secondes. L'équipe précédente
dit que « l'image est celle de prod, elle a toujours fait ça ».

**Interdit** : modifier `app.py`, passer par `--restart no` pour « calmer »
le conteneur, utiliser `docker kill` comme procédure d'arrêt.

**Objectif** : expliquer les deux symptômes par **une seule** cause, corriger
l'image (le Dockerfile et le script sont dans `/opt/factura-docker/bf/01/`)
de façon que le conteneur tourne indéfiniment et s'arrête en moins de 2 s
avec le code `0`, et citer deux autres façons d'obtenir le même résultat sans
réécrire le script.

::: repondre
lignes: 10
:::

### **BF18.2** — « /visites renvoie une erreur 500 depuis la migration »

```bash
sudo bash break_M18_02.sh
```

**Symptôme utilisateur** : le conteneur `factura-migration` (port 8002)
répond sur `/sante` et `/version`, mais `/visites` renvoie une erreur 500 et
le journal parle de `Permission denied`. Le répertoire `/srv/factura-docker/data`
existe, il est en `0755`, « comme d'habitude ». Le conteneur a été relancé
« à l'identique » après la migration de la VM.

**Interdit** : lancer le conteneur en root, `chmod 777`, `--privileged`,
changer le chemin de données.

**Objectif** : identifier avec quel UID l'application écrit, corriger
l'hôte de la façon la plus restrictive possible, sans redémarrer le
conteneur, et expliquer pourquoi un volume nommé n'aurait pas eu ce problème.

::: repondre
lignes: 8
:::

### **BF18.3** — « Le port est publié mais personne n'y accède »

```bash
sudo bash break_M18_03.sh
```

**Symptôme utilisateur** : `factura-public` (port 8003) répond à
`curl http://127.0.0.1:8003/sante` sur `lab-ops`, et `docker ps` affiche
bien `0.0.0.0:8003->8000/tcp`. Depuis `lab-adm`, `curl http://10.10.10.14:8003/sante`
expire. `ufw` n'a aucune règle sur ce port, `ss -tlnp` montre le port en
écoute.

**Interdit** : `iptables -F`, redémarrer Docker ou la machine, republier le
port, désactiver `iptables` dans `daemon.json`.

**Objectif** : retrouver ce qui bloque, le retirer chirurgicalement, expliquer
pourquoi le test local passait (quel chemin prend un paquet vers
`127.0.0.1:8003` par rapport à un paquet venant de `lab-adm`), et dire où une
telle règle aurait dû être documentée.

::: repondre
lignes: 8
:::

### **BF18.4** — « Plus rien ne se lance : no space left on device »

```bash
sudo bash break_M18_04.sh
```

**Symptôme utilisateur** : `df -h /` est à 100 %, `docker build` échoue avec
`no space left on device`, `apt` et `journalctl` se plaignent aussi.
Personne n'a copié de fichier sur la VM, `du -sh /home /srv /var/log` ne
montre rien d'anormal, et `docker images` ne liste que quelques images de
quelques centaines de Mo.

**Interdit** : `docker system prune -a`, supprimer quoi que ce soit à la main
sous `/var/lib/docker/`, agrandir le disque, supprimer les images du module.

**Objectif** : trouver **quel conteneur** occupe l'espace et **quoi** dedans,
libérer l'espace par une commande Docker, et proposer deux mesures pour que
ça ne se reproduise pas (dont une limite chiffrée).

::: repondre
lignes: 8
:::

### **BF18.5** — « L'API ne trouve plus Redis »

```bash
sudo bash break_M18_05.sh
```

**Symptôme utilisateur** : `factura-app` (port 8005) renvoie une erreur 500
sur `/compteur` avec `Name or service not known` pour `factura-cache`.
Pourtant `docker ps` montre `factura-cache` `Up`, et `docker exec
factura-cache redis-cli ping` répond `PONG`. Les deux conteneurs ont une IP en
`172.17.0.x` et se `ping`ent par IP.

**Interdit** : `--link`, écrire dans `/etc/hosts` du conteneur, mettre l'IP
en dur dans `REDIS_URL`, recréer les conteneurs.

**Objectif** : expliquer pourquoi la résolution échoue alors que la
connectivité IP fonctionne, corriger **sans recréer** les conteneurs, et
dire comment il aurait fallu les lancer.

::: repondre
lignes: 8
:::

---

## 18.8 Défi du module ★★★

**D18 — Conteneuriser et livrer `factura-api` 2.0**

::: contexte
La version 2.0 de l'API part en préproduction sur `lab-ops`. On te demande
la chaîne complète : image durcie, scan bloquant, publication dans le registre
privé, déploiement Compose depuis le registre, script de livraison et runbook.
Un collègue qui n'a pas fait le module doit pouvoir relivrer la 2.1 en
lançant un seul script.
:::

Cahier des charges :

1. **L'image** `lab-ops.lab.local:5000/factura-api:2.0`, construite depuis
   `~/lab18/api/Dockerfile` :
   * multi-stage, base épinglée sur un tag précis (pas `latest`, pas de tag
     flottant à un seul chiffre), **moins de 150 Mo** ;
   * utilisateur non-root numérique, `ENTRYPOINT` en forme exec,
     `HEALTHCHECK` sur `/sante` ;
   * `APP_VERSION` fournie par `--build-arg` et reportée dans le label
     `org.opencontainers.image.version` **et** dans `/version` ;
   * aucun secret, aucun fichier de `~/lab18/api/` autre que le code et
     `requirements.txt`.
2. **La pile** `~/lab18/compose/` : `compose.yaml` + `compose.prod.yaml`
   tel que `docker compose -f compose.yaml -f compose.prod.yaml up -d`
   déploie **l'image du registre** (pas de `build:`), avec `app` durci
   (lecture seule, `cap_drop: [ALL]`, `no-new-privileges`, limite mémoire),
   journaux bornés, dépendances conditionnées à la santé, secret pour le mot
   de passe PostgreSQL, et `curl http://127.0.0.1:8080/version` qui répond
   `2.0`.
3. **Le script** `~/lab18/bin/livrer.sh`, en bash strict, appelé avec la
   version en argument (`livrer.sh 2.0`). Il :
   * construit l'image avec la version, échoue si le build échoue ;
   * la scanne avec Trivy et **refuse de livrer** s'il reste une CVE
     `CRITICAL` corrigeable ;
   * refuse de livrer si l'image dépasse 150 Mo ou tourne en root
     (lu par `docker image inspect`, pas par lecture du Dockerfile) ;
   * la tague et la pousse dans le registre (identifiants déjà stockés par
     `docker login`) ;
   * déploie la pile avec `APP_VERSION` positionnée, attend que tout soit
     `healthy` (`--wait`), et vérifie que `/version` renvoie la version
     demandée, sinon sort en 1 ;
   * écrit un journal de livraison dans `~/lab18/rapports/livraisons.log`
     (date, version, digest de l'image poussée, résultat).
4. **Le runbook** `~/lab18/rapports/runbook-docker.md` : démarrer, arrêter,
   mettre à jour un seul service, revenir à la version précédente en moins
   de cinq lignes, sauvegarder et restaurer `pg-data`, les cinq commandes à
   taper quand un conteneur ne démarre pas, le tableau des codes de sortie,
   la conduite à tenir quand `/var/lib/docker` est plein, et la liste de ce
   qui est interdit dans un `docker run` sur cette machine (au moins quatre
   points avec la raison).
5. **La preuve** : `livrer.sh 2.0` sort en 0, puis `livrer.sh 2.1` (après
   avoir changé une chaîne dans `app.py`) aussi, et le runbook contient le
   retour à 2.0 exécuté avec sa sortie.

Temps visé : 60 à 90 minutes.

::: check
```bash
bash check_M18_06.sh
```
:::

---

## 18.9 Auto-évaluation

| Compétence | Acquis | À revoir |
|---|---|---|
| Expliquer namespaces, cgroups, overlayfs, capabilities et le prouver sans Docker | ☐ | ☐ |
| Installer Docker Engine depuis le dépôt officiel et configurer `daemon.json` | ☐ | ☐ |
| Expliquer pourquoi le groupe `docker` est root et ce que change le rootless | ☐ | ☐ |
| Lire une image : tag, digest, couches, taille, utilisateur | ☐ | ☐ |
| Piloter un conteneur et interpréter 0, 1, 125, 137, 139, 143 | ☐ | ☐ |
| Expliquer PID 1, `docker stop`, forme exec et `--init` | ☐ | ☐ |
| Écrire un Dockerfile multi-stage non-root, avec cache respecté et healthcheck | ☐ | ☐ |
| Scanner une image et décider quoi faire d'une CVE | ☐ | ☐ |
| Choisir volume, bind mount ou tmpfs et régler un problème d'UID | ☐ | ☐ |
| Expliquer bridge par défaut, réseau utilisateur, DNS 127.0.0.11 | ☐ | ☐ |
| Restreindre un port publié malgré `ufw` avec `DOCKER-USER` | ☐ | ☐ |
| Écrire une pile Compose avec healthcheck, `depends_on`, secrets, profils, override | ☐ | ☐ |
| Monter un registre privé en TLS avec authentification | ☐ | ☐ |
| Diagnostiquer un conteneur qui ne démarre pas, un disque plein, une boucle | ☐ | ☐ |

Pour aller plus loin :

* Lis la sortie complète de `docker inspect` d'un conteneur de la pile et
  cherche à quoi sert chaque section de `HostConfig` : c'est la
  représentation exacte de ce que Kubernetes appellera un `PodSpec` au
  module 22.
* Rejoue L18.4 avec Podman et `podman kube generate` : tu obtiens un
  manifeste Kubernetes à partir de tes conteneurs, et tu vois ce que Compose
  n'exprime pas.
* Reconstruis `factura-api` sur une base *distroless*
  (`gcr.io/distroless/python3-debian12`) : mesure la taille et le nombre de
  CVE, puis essaie de la déboguer avec la technique de Q18.14.
