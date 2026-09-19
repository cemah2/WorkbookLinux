# Module 18 — Corrigé

## 18.3 Quiz — QCM

**Q18.1** — *Relancer à l'identique `docker run -d --name web -p 8080:80
nginx:1.28-alpine` alors que `web` tourne déjà.*

**Réponse : b)** conflit de nom, le premier conteneur continue.

::: pourquoi
`docker run` enchaîne deux appels au démon : `create` puis `start`. Le nom
est vérifié à la **création** : le démon tient une table nom → ID et refuse
tout doublon, quel que soit l'état du conteneur homonyme (même `Exited`). Le
message exact est :

```text
docker: Error response from daemon: Conflict. The container name "/web" is
already in use by container "3f2a…". You have to remove (or rename) that
container to be able to reuse that name.
```

Le port n'est vérifié qu'au **démarrage**, quand le démon tente le `bind()`
et pose ses règles `iptables`. Ici on n'y arrive jamais. Si le collègue avait
utilisé un autre nom, il aurait obtenu `Bind for 0.0.0.0:8080 failed: port is
already allocated`, et le conteneur existerait en état `Created`, à nettoyer.
:::

::: piege
La réponse c) décrit le comportement de `docker compose up`, qui **recrée**
un conteneur dont la définition a changé. Avec `docker run` seul, rien n'est
jamais remplacé : c'est `docker rm -f web` puis `run`, ou `docker rename`.
:::

---

**Q18.2** — *`docker stop` met 10 s et le code de sortie vaut 137 avec
`CMD python3 app.py`.*

**Réponse : b)** forme shell, `/bin/sh -c` est PID 1 et ne relaie pas le signal.

::: pourquoi
`CMD python3 app.py` sans crochets est la **forme shell** : Docker l'exécute
comme `/bin/sh -c "python3 app.py"`. Le processus PID 1 du conteneur est donc
`sh`, et Python est son fils. `docker stop` envoie `SIGTERM` **au PID 1
uniquement**. Deux règles du noyau se combinent :

* un processus PID 1 (de son namespace) ne reçoit un signal que s'il a
  explicitement installé un handler : sans handler, `SIGTERM` est ignoré, et
  même `SIGKILL` venu de l'intérieur du namespace l'est ;
* `sh -c` en attente d'un fils ne propage aucun signal à ce fils.

Résultat : rien ne se passe pendant `--time` (10 s par défaut), puis Docker
envoie `SIGKILL` depuis l'hôte, ce qui tue `sh` ; ses fils sont tués avec le
namespace. Code de sortie 128 + 9 = **137**. L'application n'a jamais vu le
signal qu'elle sait pourtant traiter.

La forme exec `CMD ["python3", "app.py"]` fait de Python le PID 1 ; il a
installé un handler `SIGTERM` (c'est le cas de `factura-api`), s'arrête
proprement en quelques millisecondes et sort en `0`.
:::

::: piege
`sh -c` avec une **seule** commande simple est parfois optimisé par `dash` ou
`bash` en `exec` implicite, ce qui masque le problème sur le poste du
développeur… et le fait réapparaître dès qu'on ajoute un `&&` ou un `echo`
avant. Ne compte jamais sur cette optimisation : forme exec, toujours.
:::

---

**Q18.3** — *`Restarting (0) 2 seconds ago` avec `--restart always` (deux
réponses).*

**Réponses : a) et c)**

::: pourquoi
`Restarting (N)` affiche entre parenthèses le **code de sortie** de la
dernière exécution. `0` signifie que le processus principal s'est terminé
**normalement** : ce n'est pas un plantage, c'est un programme qui a fini son
travail. Le cas typique est un script de démarrage qui lance le vrai service
avec `&` puis atteint sa dernière ligne ; PID 1 sort, le conteneur est
terminé, et la politique `always` le relance. Docker applique un délai
croissant (100 ms, 200 ms, 400 ms…), d'où l'état `Restarting` visible.

`docker logs` conserve la sortie de **toutes** les exécutions du conteneur
(c'est le même fichier `*-json.log` tant que le conteneur n'est pas
supprimé), et `docker inspect --format '{{.RestartCount}}'` compte les
relances. Ce sont les deux premières commandes à taper.
:::

::: piege
b) est faux : un healthcheck en échec passe le conteneur en `unhealthy` mais
Docker Engine **ne redémarre jamais** sur ce critère (Compose non plus, sauf
outil externe comme `autoheal` ; Kubernetes, lui, le fait avec les probes).
d) est faux : un OOM donne `Restarting (137)`, pas `(0)`.
:::

---

**Q18.4** — *`ufw deny 8080/tcp` n'empêche pas l'accès à un port publié par
Docker.*

**Réponse : b)**

::: pourquoi
Un paquet destiné à `10.10.10.14:8080` traverse `PREROUTING` (table `nat`),
où la chaîne `DOCKER` contient une règle `DNAT --to 172.17.0.2:80`. Sa
destination n'est plus l'hôte : il ne passe pas par `INPUT` mais par
`FORWARD`. Là, Docker a inséré en tête ses chaînes (`DOCKER-USER`, puis
`DOCKER-FORWARD` ou `DOCKER` selon la version) qui **acceptent** le trafic
vers le conteneur avant que les chaînes d'`ufw` (`ufw-before-forward`,
`ufw-user-forward`) ne soient consultées. `ufw` gère `INPUT` : il ne voit
jamais ce paquet.

La seule chaîne que Docker crée, place en premier et **ne touche jamais**
est `DOCKER-USER` : c'est là qu'on filtre, avec `-i ens18` pour ne viser que
le trafic entrant par l'interface externe.
:::

::: piege
c) contient un grain de vérité déformé : `docker-proxy` existe, mais ne sert
que le trafic vers `127.0.0.1` (et IPv6 sans NAT) ; le trafic externe passe par
le noyau. Et « redémarrer ufw » (d) aggrave les choses : `ufw reload` peut
effacer les règles Docker, qu'il faudra régénérer par `systemctl restart
docker`.
:::

---

**Q18.5** — *`pip install` rejoué à chaque modification de `app.py`.*

**Réponse : b)** copier `requirements.txt` seul, installer, puis copier le
reste.

::: pourquoi
Le cache de BuildKit fonctionne couche par couche, dans l'ordre du
Dockerfile. Pour `COPY`, la clé de cache est le **contenu** (somme de
contrôle) des fichiers copiés ; pour `RUN`, c'est la chaîne de commande
**et** l'état de la couche parente. Dès qu'une instruction sort du cache,
**toutes les suivantes** sont rejouées, sans exception.

`COPY . .` en tête change dès qu'un octet du contexte change, donc à chaque
sauvegarde du code, et entraîne le `pip install`. En copiant d'abord
`requirements.txt` seul, la couche `pip install` ne dépend que de ce fichier
et reste en cache tant que les dépendances ne bougent pas. Le code, copié en
dernier, n'invalide que sa propre couche.
:::

::: piege
a) `--no-cache` est l'inverse de ce qu'on veut. d) `ADD` a le même
comportement de cache que `COPY`, avec en plus deux pièges : il décompresse
les archives et télécharge les URL (sans cache, d'ailleurs). Un `.dockerignore`
complète la correction : sans lui, `.git/` et les données font partie du
contexte et invalident le cache pour rien.
:::

---

**Q18.6** — *`ARG` contre `ENV`.*

**Réponse : b)**

::: pourquoi
`ARG` déclare une variable **de build**, valorisée par `--build-arg` ou par
sa valeur par défaut, visible par les instructions `RUN`, `COPY`, `FROM` qui
suivent, et absente de l'image finale. `ENV` écrit une paire clé/valeur dans
la configuration de l'image (`docker inspect --format '{{.Config.Env}}'`), et
chaque processus lancé dans le conteneur en hérite. Le motif courant
`ARG VERSION` + `ENV APP_VERSION=$VERSION` fait passer une valeur de build en
variable d'exécution.
:::

::: piege
d) est dangereux parce qu'il est cru : `ARG` **n'est pas secret**. Sa valeur
apparaît dans `docker history` de la couche qui l'utilise. Pour un jeton
nécessaire au build, il faut `RUN --mount=type=secret,id=token …` avec
`--secret id=token,src=…` : le fichier est monté le temps du `RUN` et ne
laisse aucune trace dans l'image.
:::

---

**Q18.7** — *`getent hosts redis` ne renvoie rien sur le bridge par défaut.*

**Réponse : b)**

::: pourquoi
Le réseau `bridge` par défaut (`docker0`) est un héritage : les conteneurs y
reçoivent le `/etc/resolv.conf` de l'hôte et aucun service de noms. Les
réseaux **utilisateur** (`docker network create`) activent le serveur DNS
intégré du démon, exposé en `127.0.0.11` dans chaque conteneur : il résout les
noms et les alias des conteneurs du même réseau, puis relaie le reste vers
les DNS de l'hôte. La connectivité IP existe dans les deux cas (d est faux),
c'est la résolution qui manque.
:::

::: piege
a) `--link` fonctionne encore sur le bridge par défaut mais est **déprécié**
depuis des années : il écrit dans `/etc/hosts` du conteneur, ne survit pas à
une recréation de la cible et est unidirectionnel. c) confond publication
(vers l'hôte) et communication inter-conteneurs : deux conteneurs d'un même
réseau se joignent sur tous les ports sans `-p`.
:::

---

**Q18.8** — *Copie du contenu de l'image dans le montage au premier
démarrage.*

**Réponse : b)** uniquement avec un volume nommé **vide**.

::: pourquoi
Quand un volume nommé est monté sur un chemin de l'image qui contient déjà
des fichiers, et que ce volume est **vide**, Docker y copie le contenu du
chemin (fichiers, propriétaires, droits). C'est ce qui permet à une image
`postgres` ou `nginx` de peupler un volume neuf. Un bind mount ne déclenche
jamais cette copie : le répertoire hôte masque le contenu de l'image, tel
quel, avec ses droits à lui. Un volume non vide n'est pas touché non plus.
:::

::: piege
C'est ce mécanisme qui rend le volume nommé « magique » côté droits : le
répertoire copié garde le `chown app:app` fait dans le Dockerfile. Avec un
bind mount, l'UID du répertoire est celui de l'hôte, d'où les
`Permission denied` de QO18.7. L'option `--mount … ,volume-nocopy` désactive
la copie.
:::

---

**Q18.9** — *`Exited (137)` après `/fuite` avec `--memory 64m`.*

**Réponse : b)**

::: pourquoi
`137` signifie seulement « tué par `SIGKILL` » : `docker kill`, un `stop`
expiré ou l'OOM killer produisent le même code. Ce qui tranche, c'est le champ
`State.OOMKilled` que le démon positionne quand le cgroup du conteneur signale
un `oom_kill`, et la trace noyau `Memory cgroup out of memory: Killed process
… (python3)` dans `journalctl -k`. Le fichier `memory.events` du cgroup
(`oom_kill 1`) le confirme aussi.
:::

::: piege
`--memory 64m` seul autorise autant de **swap** en plus (`--memory-swap`
vaut le double par défaut si l'hôte a du swap, ce qui est le cas d'une
Ubuntu Server avec `/swap.img`) : l'allocation de 100 Mo peut passer en
ralentissant tout. Pour un test franc : `--memory 64m --memory-swap 64m`.
a) est faux : `Killed` est écrit par le **shell** parent, il n'y en a pas ici.
:::

---

**Q18.10** — *`docker run -d nginx` le lendemain d'un `docker pull nginx`.*

**Réponse : b)**

::: pourquoi
`docker run` ne contacte le registre que si l'image (`nginx:latest`) est
absente localement, ou avec `--pull always`. Et `latest` n'est qu'un tag : une
étiquette mobile que le mainteneur déplace quand il le veut. Rien ne garantit
qu'elle désigne la version la plus récente, ni qu'elle désigne demain la même
chose qu'aujourd'hui. Seul le digest (`nginx@sha256:…`) identifie un contenu ;
`docker images --digests` le montre, et `docker inspect --format
'{{.RepoDigests}}'` aussi.
:::

::: piege
En production, on épingle un tag précis (`nginx:1.28.0-alpine`) ou un
digest, et on met à jour **volontairement**. `docker compose pull` puis
`up -d` recrée les conteneurs dont l'image a changé — mais avec `latest`, on
ne saura pas dire ce qui tournait avant.
:::

---

**Q18.11** — *Monter `docker.sock` dans un conteneur (deux réponses).*

**Réponses : b) et c)**

::: pourquoi
Le socket est l'API du démon, qui tourne en root. Qui peut lui parler peut
créer un conteneur `--privileged` avec `/` de l'hôte monté, et y faire
`chroot` : root sur `lab-ops`, sans mot de passe ni trace `sudo`. C'est
exactement le pouvoir du groupe `docker` (le socket est `root:docker` en
`0660`). L'utilisateur du conteneur n'y change rien (a) : c'est le démon qui
exécute, pas le conteneur. Et Docker ne refuse rien (d) : un bind mount est un
bind mount.
:::

::: piege
Si un pipeline a vraiment besoin de construire des images, les alternatives
sont : un runner **dédié** et jetable, `docker-socket-proxy` qui filtre l'API,
BuildKit en mode rootless, ou Kaniko/Buildah sans démon. Et surtout : le
socket monté doit apparaître dans l'audit de sécurité comme « accès root ».
:::

---

**Q18.12** — *`depends_on: [db]` et `connection refused` au premier `up`.*

**Réponse : a)**

::: pourquoi
La forme courte de `depends_on` équivaut à `condition: service_started` :
Compose attend que le **conteneur** `db` soit démarré, c'est-à-dire que son
PID 1 existe. PostgreSQL met ensuite deux à cinq secondes à initialiser le
répertoire de données et à écouter. `app` démarre dans cette fenêtre et
échoue. La forme longue avec `condition: service_healthy` bloque le
démarrage d'`app` jusqu'à ce que le `healthcheck` de `db` soit vert
(`pg_isready`).
:::

::: piege
Même avec `service_healthy`, `db` peut redémarrer plus tard : l'application
doit **retenter** ses connexions. `depends_on` règle le démarrage initial,
pas la vie de la pile ; `restart: unless-stopped` sur `app` couvre le reste,
et depuis Compose 2.17, `depends_on: db: {condition: service_healthy,
restart: true}` redémarre `app` quand `db` est recréé.
:::

---

**Q18.13** — *`.env` ne peuple pas l'environnement de `db`.*

**Réponse : b)**

::: pourquoi
Compose lit `.env` (dans le répertoire du projet) pour **interpoler**
`${VAR}` dans le fichier Compose lui-même : `image: postgres:${PG_VERSION}`.
Le conteneur, lui, ne reçoit que ce que `environment:` ou `env_file:`
déclarent sur son service. Les deux fichiers ont la même syntaxe, d'où la
confusion. `docker compose config` montre le résultat de l'interpolation et
l'environnement effectif de chaque service.
:::

::: piege
`env_file: .env` fait passer **tout** le fichier dans le conteneur, y compris
les variables qui ne le concernent pas. Pour un mot de passe, aucune des deux
méthodes n'est bonne : `docker inspect` affiche `Config.Env` en clair. C'est le
rôle de `secrets:`.
:::

---

**Q18.14** — *`exec: "sh": executable file not found` (deux réponses).*

**Réponses : a) et c)**

::: pourquoi
L'image est *distroless* ou `scratch` : pas de shell, c'est voulu. Deux
techniques d'inspection sans modifier l'image :

* lancer un conteneur outillé qui **partage les namespaces** de la cible :
  `--pid container:app` (voir ses processus, lire `/proc/1/root/…`) et
  `--network container:app` (ses ports, `ss`, `curl localhost`). Depuis
  Docker 23, `docker debug` fait la même chose côté Docker Desktop ;
* `nsenter` depuis l'hôte, avec le PID vu par l'hôte : `-n -m -p` entre dans
  le réseau, les montages et le namespace PID. Avec `-m` on voit le système de
  fichiers du conteneur, mais les binaires utilisés sont ceux… du conteneur,
  donc `sh` manquera aussi : on combine `-n -p` sans `-m`, ou on lit
  `/proc/PID/root/` depuis l'hôte.
:::

::: piege
b) est une non-réponse : remettre un shell en production élargit la surface
d'attaque pour un besoin de débogage occasionnel. d) `--shell` n'existe pas.
:::

---

**Q18.15** — *`*-json.log` de 9 Go et `max-size` ajouté après coup (deux
réponses).*

**Réponses : b) et c)**

::: pourquoi
Les options de journalisation sont **figées à la création** du conteneur
(`docker inspect --format '{{json .HostConfig.LogConfig}}'`). `daemon.json`
ne fixe que la valeur par défaut des conteneurs futurs. Il faut donc recréer
le conteneur. En attendant, `truncate -s 0` sur le fichier libère l'espace
immédiatement : le démon garde le fichier ouvert en mode ajout, le tronquer
ne casse rien (contrairement à `rm`, qui laisserait l'inode occupé tant que
le démon l'a ouvert).
:::

::: piege
d) est faux : `json-file` tourne très bien avec `max-size`/`max-file`. Mais
il faut savoir qu'après rotation, `docker logs` ne voit que les fichiers
conservés. Pour une rétention longue, `journald` (`journalctl
CONTAINER_NAME=web`) ou un collecteur (module 13) sont plus adaptés.
:::

---

**Q18.16** — *`-p 127.0.0.1:8080:80` vu depuis `lab-adm`.*

**Réponse : b)**

::: pourquoi
La syntaxe `-p [IP:]hôte:conteneur` fixe l'adresse d'écoute côté hôte. Avec
`127.0.0.1`, la règle DNAT ne s'applique qu'aux paquets destinés à la boucle
locale et `docker-proxy` n'écoute que sur `lo`. Depuis le réseau, rien
n'écoute sur `10.10.10.14:8080` : `Connection refused` immédiat, pas de
timeout. C'est le motif standard « service derrière un reverse proxy local » :
nginx sur l'hôte parle à `127.0.0.1:8080`, le monde parle à nginx.
:::

::: piege
Sans IP, `-p 8080:80` publie sur `0.0.0.0` **et** `[::]` : toutes les
interfaces, IPv6 compris. Beaucoup de « fuites » de bases de données viennent
d'un `-p 5432:5432` qu'on croyait local.
:::

---

**Q18.17** — *`chown: Operation not permitted` avec `--cap-drop ALL`.*

**Réponse : b)**

::: pourquoi
`chown` sur un fichier dont on n'est pas propriétaire est contrôlé par
`CAP_CHOWN`. Un conteneur Docker root possède par défaut 14 capabilities dont
`CHOWN`, `DAC_OVERRIDE`, `SETUID`, `NET_BIND_SERVICE`… `--cap-drop ALL` les
retire toutes : même en UID 0, le processus n'est plus qu'un utilisateur
ordinaire pour ce type d'opération. Ici en plus `--user 10001` : le point
d'entrée d'une image (souvent un `chown -R` de `/data`) est pensé pour root.
Solution : préparer les droits dans l'image (`RUN chown`), ou sur l'hôte, ou
`--cap-add CHOWN` si on tient à l'`ENTRYPOINT` d'origine.
:::

::: piege
`--privileged` (c) donne **tout** : toutes les capabilities, tous les
périphériques, pas de seccomp ni d'AppArmor. C'est la réponse « ça marche »
qui annule tout l'intérêt du conteneur. Vérifie ce qu'il te faut vraiment
avec `capsh --print` ou `getpcaps PID`.
:::

---

**Q18.18** — *`docker rmi` refuse : un conteneur arrêté utilise l'image.*

**Réponse : b)**

::: pourquoi
Un conteneur, même `Exited`, est un objet complet : sa couche d'écriture
repose sur les couches de l'image, et le démon garde la référence. `docker
rmi -f` ne fait que **détacher le tag** : les couches restent, l'image devient
`<none>:<none>` (une *dangling image*) et l'espace n'est pas libéré. L'ordre
correct est `docker rm` du conteneur, puis `docker rmi`. `docker ps -a
--filter ancestor=factura-api:1.0` liste les conteneurs concernés.
:::

::: piege
c) `docker system prune -a --volumes` supprime **tous** les conteneurs
arrêtés, toutes les images non utilisées par un conteneur en cours, tous les
réseaux inutilisés et tous les volumes anonymes : sur un serveur, c'est
potentiellement des données perdues. On ne le lance jamais « immédiatement ».
:::

---

## 18.4 Quiz — questions ouvertes

**QO18.1** — *Conteneur contre machine virtuelle, sans citer Docker.*

**Réponse attendue**

Une machine virtuelle exécute un **noyau complet** sur un processeur
virtualisé par l'hyperviseur (KVM sur Proxmox) : elle a ses pilotes, sa
mémoire réservée, son disque virtuel, et démarre comme une machine physique.
Un conteneur est un **processus** du noyau hôte, lancé avec quatre mécanismes
du noyau :

| Mécanisme | Ce qu'il fait |
|---|---|
| namespaces (`pid`, `net`, `mnt`, `uts`, `ipc`, `user`) | **isolent la vue** : le processus voit ses propres PID, interfaces, montages, hostname, UID |
| cgroups v2 | **limitent la consommation** : mémoire, CPU, nombre de PID, E/S |
| système de fichiers en couches (overlayfs) | **assemblent** des couches en lecture seule et une couche d'écriture jetable |
| capabilities, seccomp, AppArmor/SELinux | **réduisent les privilèges** : fragments de root, appels système autorisés |

Trois conséquences :

1. **Sécurité** : le noyau est partagé. Une faille noyau exploitable depuis
   un conteneur compromet l'hôte et tous les autres conteneurs ; la barrière
   est du code noyau (namespaces), pas du matériel (VT-x). Un conteneur root
   sans durcissement est presque root sur l'hôte. Une VM isole bien mieux.
2. **Performance et densité** : pas de second noyau, pas de mémoire réservée,
   démarrage en millisecondes (c'est un `fork`+`exec`), appels système à
   vitesse native. On empile des dizaines de conteneurs là où on met cinq VM.
3. **Exploitation** : un conteneur meurt avec son processus principal, il n'a
   ni `init`, ni `sshd`, ni journal propre ; on ne « se connecte » pas dedans,
   on lit ses sorties et on le remplace plutôt que de le réparer. Son PID 1
   n'a pas les protections d'un vrai `init` : un shell ou une application mal
   écrite ignore `SIGTERM` et laisse des zombies.

::: pourquoi
La question sert à vérifier qu'on ne récite pas « c'est plus léger ». La
clé est de nommer **ce qui isole** (namespaces), **ce qui limite** (cgroups)
et **ce qui reste partagé** (le noyau) : tout le reste en découle. Un bon
candidat ajoute que la frontière est poreuse par conception (`docker.sock`,
`--privileged`, `--pid host`) et que Kubernetes n'y change rien : c'est le
même noyau.
:::

---

**QO18.2** — *`ENTRYPOINT` ou `CMD`, forme exec ou shell, PID 1, `--init`.*

**Réponse attendue**

* `ENTRYPOINT` est le **programme**, `CMD` ses **arguments par défaut**. La
  commande effective est la concaténation `ENTRYPOINT + CMD`. `docker run
  image arg1 arg2` **remplace `CMD`** et garde l'`ENTRYPOINT` ;
  `--entrypoint` remplace l'`ENTRYPOINT` (et vide `CMD`). Sans `ENTRYPOINT`,
  `CMD` est la commande complète.
* **Forme exec** `["python3", "app.py"]` : Docker appelle directement
  `execve("python3", …)`. Python est PID 1. Pas de shell, donc pas
  d'expansion de variables (`$PORT` reste littéral).
* **Forme shell** `python3 app.py` : Docker exécute `/bin/sh -c "python3
  app.py"`. `sh` est PID 1, Python est son fils. Les variables sont
  développées, mais `docker stop` envoie `SIGTERM` à `sh`, qui, en tant que
  PID 1 sans handler, l'ignore ; après 10 s, `SIGKILL`, code 137.
* Mélange piégeux : `ENTRYPOINT` en forme shell **ignore `CMD`** et les
  arguments de `docker run`.
* `--init` (ou `init: true` en Compose) insère `docker-init` (tini) en PID 1 :
  il **relaie** les signaux au processus fils et **récolte les zombies**
  (appelle `wait()` pour les orphelins réadoptés). Il rend un programme non
  prévu pour être PID 1 exploitable sans le modifier.

::: pourquoi
Le PID 1 d'un namespace a deux propriétés noyau : les signaux sans handler
sont ignorés (pour qu'un `init` ne meure pas par accident), et il adopte les
orphelins du namespace. Un serveur applicatif n'est pas écrit pour ça. Il y a
trois solutions propres : forme exec avec une application qui gère
`SIGTERM`, `exec` en fin de script shell (le shell se remplace par
l'application, qui devient PID 1), ou `--init`. La combinaison
`ENTRYPOINT ["tini", "--"]` + `CMD` est ce que font beaucoup d'images
officielles.
:::

::: piege
`docker inspect --format '{{.Config.Entrypoint}} {{.Config.Cmd}}'` montre
la forme réellement enregistrée : `[/bin/sh -c python3 app.py]` trahit une
forme shell. Et `docker top conteneur` montre qui est PID 1 : si c'est `sh`,
tu as ta réponse avant même de chronométrer.
:::

---

**QO18.3** — *Le cache de build.*

**Réponse attendue**

* Le build est une **suite ordonnée** d'instructions ; chaque `RUN`, `COPY`,
  `ADD` produit une couche. Une couche est réutilisée si l'instruction est
  identique **et** que la couche parente est la même. Pour `COPY`/`ADD`, la
  somme de contrôle du contenu copié entre dans la clé ; pour `RUN`, seule la
  chaîne de commande compte (le résultat d'un `apt-get update` d'il y a un
  mois est donc « en cache »).
* Dès qu'une instruction est invalidée, **toutes les suivantes** sont
  rejouées : le cache ne se « resynchronise » pas.
* `COPY . .` en tête envoie tout le contexte (donc le code, qui change à
  chaque commit) dans la première couche : chaque build repart de zéro. On
  copie d'abord ce qui change rarement (`requirements.txt`, `package.json`),
  on installe, puis on copie le code.
* Le **multi-stage** sépare l'outillage de build (compilateurs, headers,
  `pip` avec cache, `.git`) de l'image finale : `FROM … AS builder` construit,
  `COPY --from=builder` ne rapporte que les artefacts. L'image finale est
  plus petite et n'expose ni compilateur ni sources.
* Taille par couche : `docker history --no-trunc factura-api:1.0`, ou
  `docker image inspect --format '{{json .RootFS.Layers}}'` pour les digests ;
  `docker build --progress=plain` montre `CACHED` ou le temps de chaque étape.
  `dive` (outil tiers) permet de voir les fichiers par couche.

::: pourquoi
Comprendre le cache, c'est comprendre qu'une image est **immuable et
additive** : supprimer un fichier dans une couche ultérieure ne réduit pas la
taille, le fichier existe toujours dans la couche précédente. D'où la règle
« installer et nettoyer dans le même `RUN` », et le multi-stage qui est la
seule façon de ne pas embarquer ce qui a servi à construire.
:::

::: piege
Le cache peut être **trop** fidèle : `RUN apt-get update && apt-get install
-y curl` reste en cache indéfiniment, avec des paquets vieux de six mois.
`docker build --no-cache` ou `--pull` (pour rafraîchir la base) fait partie
du pipeline de nuit, pas du cycle de dev. Et le contexte de build inclut
tout le répertoire : sans `.dockerignore`, `.git` de 300 Mo est envoyé au
démon à chaque build.
:::

---

**QO18.4** — *Méthode de diagnostic d'un conteneur qui ne démarre pas.*

**Réponse attendue**

| Étape | Commande | Ce qu'on cherche |
|---|---|---|
| 1. État et code | `docker ps -a --filter name=app` ; `docker inspect app --format '{{.State.Status}} {{.State.ExitCode}} {{.State.Error}} {{.State.OOMKilled}}'` | `Exited (N)`, `Created` (jamais démarré : erreur de `start`), `Restarting`, message d'erreur du démon |
| 2. Journaux | `docker logs --tail 100 app` (ou `--since 5m`) | trace applicative, `Traceback`, `Address already in use`, `Permission denied` |
| 3. Configuration effective | `docker inspect app --format '{{.Config.Entrypoint}} {{.Config.Cmd}} {{.Config.User}}'`, `{{.Config.Env}}`, `{{json .Mounts}}`, `{{json .HostConfig.PortBindings}}` | commande réellement lancée, variable manquante, chemin de montage faux |
| 4. Image sans shell | `docker run --rm -it --pid container:app --network container:app busybox sh` ; `docker run --rm --entrypoint sh image` | tester à la main dans le même environnement |
| 5. Port pris | `ss -tlnp 'sport = :8080'` ; `docker ps --filter publish=8080` | `Bind for 0.0.0.0:8080 failed: port is already allocated` ; erreur 125 |
| 6. Dépendance | `docker network inspect net` ; `docker exec app getent hosts db` ; `docker compose ps` | conteneur cible absent du réseau, pas `healthy` |
| 7. Montage | `docker exec app id` ; `ls -ln /srv/chemin` ; `docker exec app touch /data/x` | UID du processus ≠ propriétaire hôte |
| 8. Mémoire | `docker inspect --format '{{.State.OOMKilled}}'` ; `journalctl -k \| grep -i 'out of memory'` ; `docker stats --no-stream` | `137` + `OOMKilled: true` |

Codes : `0` sortie normale (script qui finit : voir Q18.3) ; `1` erreur
applicative, lire les journaux ; `125` le démon n'a pas pu démarrer le
conteneur (option invalide, port pris, montage impossible) ; `126` commande
non exécutable ; `127` commande introuvable (`ENTRYPOINT` mal orthographié,
binaire absent de l'image) ; `137` `SIGKILL` (OOM, `docker kill`, `stop`
expiré) ; `139` `SIGSEGV`, plantage natif ; `143` `SIGTERM` reçu et non géré,
arrêt demandé.

::: pourquoi
L'ordre compte : on regarde **l'état** avant les journaux (un conteneur
`Created` n'a pas de journaux), et la **configuration effective** avant de
relire le Dockerfile ou le Compose, parce que l'image en cache, un override
ou une variable `.env` peuvent différer de ce qu'on croit avoir écrit.
`docker events --since 10m` complète en montrant qui a fait quoi (`die`,
`oom`, `kill`, `start`).
:::

---

**QO18.5** — *Trajet d'un paquet vers `-p 8080:80`, `docker-proxy`, `ufw`.*

**Réponse attendue**

1. Le paquet `10.10.10.10 → 10.10.10.14:8080` arrive sur `ens18` et entre
   dans **`PREROUTING` (table `nat`)**. La règle `-A PREROUTING -m addrtype
   --dst-type LOCAL -j DOCKER` l'envoie dans la chaîne `DOCKER`, où
   `-d 0.0.0.0/0 -p tcp --dport 8080 -j DNAT --to-destination 172.17.0.2:80`
   réécrit la destination.
2. La destination n'étant plus locale, le paquet est **routé** vers `docker0`
   et passe par **`FORWARD` (table `filter`)**. Docker y a inséré en tête :
   `DOCKER-USER` (vide par défaut, `RETURN`), puis ses chaînes
   d'acceptation (`DOCKER-FORWARD`/`DOCKER`, `DOCKER-ISOLATION-STAGE-*`), dont
   une règle `-d 172.17.0.2/32 -p tcp --dport 80 -j ACCEPT`.
3. Les chaînes d'`ufw` (`ufw-before-forward`, `ufw-user-forward`) viennent
   **après** dans `FORWARD` : le paquet a déjà été accepté. Et `ufw deny
   8080` cible `INPUT`, que ce paquet ne traverse jamais.
4. Au retour, `POSTROUTING` fait le `MASQUERADE` du trafic sortant du
   sous-réseau `172.17.0.0/16`.
5. `docker-proxy` est un processus utilisateur qui écoute sur
   `0.0.0.0:8080` ; il ne sert que les cas que le DNAT ne couvre pas : trafic
   depuis l'hôte vers `127.0.0.1:8080` (la boucle locale ne passe pas par
   `PREROUTING` avec DNAT vers un autre hôte… sauf `route_localnet`), et
   IPv6 vers un conteneur IPv4. Son écoute explique le `ss -tlnp` qui montre
   le port alors que `ufw` le croit fermé.

Restreindre correctement :

* `iptables -I DOCKER-USER -i ens18 -p tcp --dport 80 ! -s 10.10.10.10
  -j DROP` (le port testé est celui **après DNAT**, donc le port conteneur ;
  `-m conntrack --ctorigdstport 8080` permet de tester le port d'origine), à
  rejouer au boot ;
* publier sur une adresse précise : `-p 127.0.0.1:8080:80` derrière un
  reverse proxy, ou `-p 10.10.10.14:8080:80` si l'hôte a plusieurs
  interfaces ; ou ne rien publier et joindre le conteneur par le réseau
  utilisateur depuis le proxy conteneurisé.

::: pourquoi
Le point à retenir : **publier un port, c'est écrire des règles NAT dans le
noyau**, pas « ouvrir un port » au sens d'un service. Le pare-feu d'hôte
raisonne en `INPUT` ; Docker travaille en `FORWARD` et passe avant. C'est
documenté noir sur blanc par Docker (« Docker and ufw ») et c'est la cause
de nombreuses bases de données exposées à Internet.
:::

::: piege
`ufw route deny` semble prometteur mais reste après les règles Docker.
Désactiver `"iptables": false` dans `daemon.json` casse la publication de
ports et le NAT sortant : ce n'est pas une option. Et `DOCKER-USER` doit
laisser passer le trafic **établi** si tu y mets un `DROP` large : ajoute
d'abord `-m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT`.
:::

---

**QO18.6** — *Le groupe `docker` est root ; rootless ; cinq options de
durcissement.*

**Réponse attendue**

Preuve en une ligne (en tant que `mathieu`, membre du groupe `docker`) :

```bash
docker run --rm -v /:/host alpine:3.20 cat /host/etc/shadow
```

ou, plus radical, `docker run --rm -it --privileged -v /:/host alpine:3.20
chroot /host bash` : un shell root sur `lab-ops`, sans `sudo`, sans mot de
passe, sans ligne dans `auth.log`. Le démon tourne en root et fait ce que le
socket lui demande ; le groupe `docker` a le droit d'écrire sur le socket.

**Rootless** : le démon `dockerd` tourne **sous l'UID de l'utilisateur**
(`ps -o user,pid,args -C dockerd`), lancé par `systemctl --user`, socket
`/run/user/1001/docker.sock`, données dans `~/.local/share/docker`. Il crée
un **user namespace** : l'UID 0 des conteneurs est projeté sur l'UID de
l'utilisateur, les autres UID sur la plage de `/etc/subuid` (`kevin:100000:
65536`). Le réseau passe par `slirp4netns` ou `pasta` (pas de `docker0`, pas
de règles `iptables` dans l'hôte). Ce qui ne marche plus : ports < 1024
(sauf `sysctl net.ipv4.ip_unprivileged_port_start=0`), `--network host`
limité, pas de cgroup sans délégation systemd (`Delegate=`), stockage
overlay2 seulement si le noyau l'autorise en user namespace (oui sur 24.04),
performances réseau moindres, `--privileged` sans effet réel sur l'hôte.

Cinq options de `docker run` :

| Option | Ce qu'elle empêche |
|---|---|
| `--user 10001:10001` | tourner en root dans le conteneur : une évasion par le système de fichiers arrive en UID 10001 sur l'hôte |
| `--cap-drop ALL` (+ `--cap-add` ciblé) | `chown`, `mknod`, `setuid`, `net_raw`, `sys_admin`… : les fragments de root qu'un exploit utiliserait |
| `--read-only --tmpfs /tmp` | modifier le système de fichiers de l'image : dépôt de binaire, altération de configuration |
| `--security-opt no-new-privileges` | regagner des privilèges via un binaire `setuid` (`sudo`, `su`, `ping`) |
| `--memory 256m --pids-limit 100` | épuiser la mémoire ou la table des PID de l'hôte (fork bomb) |

Autres : `--network none`, `--security-opt seccomp=profil.json`, ne jamais
monter `docker.sock`, ni `--privileged`, ni `--pid host`.

::: pourquoi
L'entretien vérifie qu'on distingue **l'isolation du conteneur** (options de
`run`) et **le contrôle d'accès au démon** (groupe, socket, rootless). Les
deux sont indépendants : un conteneur parfaitement durci ne protège pas
contre un développeur qui a le socket. Le rootless répond au second problème,
les options au premier.
:::

---

**QO18.7** — *`Permission denied` sur un bind mount de `~/projet/data`.*

**Réponse attendue**

Le noyau ne connaît que des **UID numériques**. Le conteneur n'a pas de
table d'utilisateurs commune avec l'hôte : l'`app` UID 10001 du conteneur est
l'UID 10001 sur l'hôte, sans nom. `~/projet/data` appartient à `mathieu`
(1000) en `0755` : le processus 10001 n'a que `r-x`, donc `open(…, "a")`
échoue avec `EACCES`. À l'inverse, un conteneur root écrit partout et
laisse des fichiers `root:root` que `mathieu` ne pourra plus supprimer.

Un volume nommé n'aurait pas posé le problème : à son premier montage, Docker
y **copie le contenu du répertoire de l'image avec ses droits**, donc le
`chown app:app /data` du Dockerfile ; ensuite le volume vit sous
`/var/lib/docker/volumes/`, où seul le conteneur écrit.

Trois corrections :

| Correction | Inconvénient |
|---|---|
| `chown -R 10001 ~/projet/data` sur l'hôte | les fichiers ne sont plus à `mathieu` ; avec un UID sans nom, `ls -l` affiche `10001` ; gênant en dev |
| lancer le conteneur avec `--user $(id -u):$(id -g)` | l'image doit accepter un UID arbitraire (pas de `USER` fixe, `HOME` inexistant, `/etc/passwd` sans entrée : certains programmes plantent) ; les fichiers de l'image possédés par `app` deviennent inaccessibles |
| `setfacl -m u:10001:rwx ~/projet/data` (ACL, avec `-d` pour l'héritage) | invisible dans `ls -l` (juste un `+`), oublié dans les sauvegardes qui ne gèrent pas les ACL |

Autres pistes : construire l'image avec `ARG UID=1000` pour aligner l'UID
sur celui du développeur ; en rootless, l'UID 10001 du conteneur devient
`100000+10000` sur l'hôte — le problème change de forme mais ne disparaît
pas ; sous SELinux (Rocky), ajouter `:Z` sinon c'est le label qui bloque.

::: pourquoi
La question teste la compréhension que **l'identité est numérique et
traverse la frontière** du conteneur sans traduction (hors user namespace).
C'est la même règle que NFS et que les partages entre machines : les noms sont
locaux, les nombres sont globaux.
:::

---

**QO18.8** — *`down` contre `stop`, `-v`, mise à jour d'un seul service,
démarrage au boot.*

**Réponse attendue**

* `docker compose stop` arrête les conteneurs (SIGTERM puis SIGKILL après
  `stop_grace_period`, 10 s) et les **garde** : `ps -a` les montre `Exited`,
  `start` les relance avec leur état et leur IP.
* `docker compose down` arrête **et supprime** les conteneurs, puis le
  réseau du projet. Les volumes nommés et les images restent. `down -v`
  supprime **aussi les volumes** déclarés dans le fichier et les volumes
  anonymes : `pg-data` disparaît, la base avec. `--rmi all` supprime les
  images en plus.
* Mettre à jour `app` seule : reconstruire ou tirer l'image, puis
  `docker compose up -d --no-deps --build app` (ou `--pull always` si
  l'image vient du registre). `--no-deps` évite de toucher `db` et `cache` ;
  sans lui, Compose vérifie les dépendances et ne les recrée que si leur
  définition a changé, mais un `up -d` global peut les recréer si le fichier
  a bougé. `proxy`, qui dépend d'`app`, sera redémarré si `app` est recréé
  et que `depends_on` est déclaré avec `restart: true`.
* Au boot : `restart: unless-stopped` (ou `always`) sur chaque service, et
  `docker.service` activé (`systemctl is-enabled docker`). Au démarrage du
  démon, les conteneurs qui n'ont pas été arrêtés manuellement sont relancés.
  Pas d'unité systemd à écrire ; `docker compose stop` marque les conteneurs
  comme arrêtés manuellement, ils ne reviendront pas avant un `start`.

::: pourquoi
La distinction `stop`/`down` est celle entre **processus** et **objets** :
un conteneur arrêté est encore un objet avec sa couche d'écriture, ses
journaux, son IP. `down` repart d'une feuille blanche, sauf ce qui est
explicitement persistant (volumes nommés). `-v` est la commande la plus
destructrice de Compose : elle mérite un snapshot ou une sauvegarde avant.
:::

::: piege
`always` et `unless-stopped` respectent tous deux un `docker stop` tant que
le démon tourne. La différence apparaît au **redémarrage du démon** (ou de
la machine) : `always` relance tout, y compris un conteneur qu'on avait
volontairement arrêté ; `unless-stopped` mémorise l'arrêt manuel et ne le
relance pas. C'est la seule différence entre les deux, et c'est pour ça
qu'`unless-stopped` est le choix par défaut d'un exploitant.
:::

---

**QO18.9** — *41 CVE dont 3 `CRITICAL` dans `libssl3` et 1 `HIGH` en
Python.*

**Réponse attendue**

Pour chaque CVE : (1) le paquet et la **version installée** contre la
**version corrigée** (`FixedVersion` dans Trivy) ; (2) le vecteur : la faille
est-elle atteignable dans mon usage ? `libssl3` dans une API qui ne termine
pas de TLS (le proxy le fait) est bien moins exposée qu'un `libssl3` en
frontal ; (3) le contexte d'exécution : non-root, `cap-drop`, `read-only`
réduisent l'impact d'une exécution de code ; (4) la source : image de base
(le correctif vient d'un nouveau tag de la base, il faut **reconstruire avec
`--pull`**) ou dépendance applicative (bump dans `requirements.txt`, tests,
rebuild).

Ce qui justifie d'ignorer : pas de correctif disponible (`--ignore-unfixed`),
faille non atteignable (composant non utilisé, documenté dans
`.trivyignore` avec la justification et une date de revue), faux positif
confirmé. Ce qui impose un rebuild : `CRITICAL`/`HIGH` avec correctif
disponible, ou tout ce qui touche un composant en contact avec l'entrée
utilisateur (parseur, TLS, désérialisation).

`--ignore-unfixed` est utile parce qu'il retire le bruit sur lequel on ne
peut rien faire (Debian classe beaucoup de CVE `no-dsa`), et dangereux parce
qu'une CVE sans correctif reste exploitable : il faut la **connaître** et
compenser (durcissement, isolation, surveillance), pas l'oublier. On le garde
pour la porte du pipeline (`--exit-code 1`), et on lance un scan complet
hebdomadaire sans lui.

::: pourquoi
Un scanner produit une **liste**, pas une décision. La démarche de l'exploitant
est de transformer la liste en trois tas : rebuild maintenant, accepté avec
justification écrite et date, à surveiller. Et de rescanner régulièrement les
images **déjà en production** : une image qui était propre au build ne le
reste pas (`trivy image` sur le registre, en tâche planifiée).
:::

---

## 18.5 Exercices guidés

**E18.1** — *Un shell PID 1 avec son propre hostname, sans Docker.*

```bash
sudo unshare --pid --fork --mount-proc --uts bash
# --- dans le nouveau shell ---
echo $$                      # 1
ps -ef                       # deux lignes : bash (PID 1) et ps
hostname conteneur-test
hostname                     # conteneur-test
```

Dans un second terminal, sur l'hôte :

```bash
hostname                     # lab-ops : le namespace UTS a fait son travail
sudo lsns -t pid -t uts      # une ligne par namespace, avec le PID du bash
PID=$(sudo lsns -t uts -n -o PID | tail -1)
sudo ls -l /proc/$PID/ns | awk '{print $9, $10, $11}'
ls -l /proc/$$/ns | awk '{print $9, $10, $11}'
```

Seuls `pid` et `uts` diffèrent (les numéros d'inode entre crochets) ;
`mnt`, `net`, `ipc`, `user` sont identiques : ce « conteneur » partage
encore le réseau et les montages de l'hôte.

Sans `sudo` :

```bash
unshare --user --map-root-user --pid --fork --mount-proc --uts bash
id                           # uid=0(root) … mais dans le namespace seulement
hostname conteneur-test      # accepté
touch /etc/preuve            # Permission denied : root de pacotille
```

::: pourquoi
Créer un namespace PID, UTS ou réseau exige `CAP_SYS_ADMIN`. Le namespace
**user** est l'exception : n'importe qui peut en créer un, et à l'intérieur
il détient toutes les capabilities… sur les ressources de ce namespace
uniquement. `--map-root-user` projette ton UID 1000 sur l'UID 0 du namespace
(via `/proc/PID/uid_map`). C'est exactement le mécanisme de Docker rootless
et de Podman. `--fork` est nécessaire avec `--pid` parce que le processus qui
appelle `unshare` reste dans l'ancien namespace PID : seul son **fils** est
dans le nouveau. `--mount-proc` remonte `/proc` dans un namespace de
montage privé, sinon `ps` lirait le `/proc` de l'hôte.
:::

::: piege
Sur Ubuntu 24.04, `kernel.apparmor_restrict_unprivileged_userns=1`
interdit les user namespaces aux programmes non confinés ; `unshare` a un
profil AppArmor qui l'autorise, mais un script maison obtiendra
`unshare: unshare failed: Operation not permitted`. C'est une mesure de
sécurité délibérée : la majorité des exploits noyau récents commencent par un
user namespace.
:::

---

**E18.2** — *64 Mo de mémoire sans swap, sans Docker.*

```bash
sudo mkdir /sys/fs/cgroup/lab18
echo 64M | sudo tee /sys/fs/cgroup/lab18/memory.max
echo 0   | sudo tee /sys/fs/cgroup/lab18/memory.swap.max
sudo sh -c 'echo $$ > /sys/fs/cgroup/lab18/cgroup.procs && \
  exec python3 -c "b = bytearray(200 * 1024 * 1024); input()"'
# Killed
cat /sys/fs/cgroup/lab18/memory.events
# low 0  high 0  max 3  oom 1  oom_kill 1  oom_group_kill 0
sudo journalctl -k -n 30 | grep -iE 'out of memory|oom-kill'
# kernel: Memory cgroup out of memory: Killed process 4211 (python3) …
sudo rmdir /sys/fs/cgroup/lab18
```

Équivalent avec systemd (une unité transitoire, cgroup créé et détruit
pour toi) :

```bash
sudo systemd-run --scope -p MemoryMax=64M -p MemorySwapMax=0 \
  python3 -c 'b = bytearray(200 * 1024 * 1024); input()'
# Running scope as unit: run-r7c1….scope
# Killed
```

::: pourquoi
Un cgroup v2 est un répertoire : le créer active les contrôleurs hérités
du parent (`cgroup.subtree_control` de la racine contient `memory`), écrire
un PID dans `cgroup.procs` y déplace le processus **et ses futurs fils**,
d'où le `sh -c` qui s'inscrit puis fait `exec`. `memory.max` est une limite
dure : au-delà, le noyau réclame, puis déclenche l'OOM killer **du cgroup**
(pas celui de la machine), ce que `memory.events` compte dans `oom_kill`.
Sans `memory.swap.max=0`, le cgroup aurait pu déborder dans `/swap.img` et
ne jamais être tué. Docker fait exactement ceci avec `--memory` et
`--memory-swap`, dans `system.slice/docker-<id>.scope`.
:::

---

**E18.3** — *Le processus `nginx` du conteneur `web` vu de l'hôte.*

```bash
PID=$(docker inspect web --format '{{.State.Pid}}')
ps -o pid,ppid,user,args -p "$PID"
#  PID  PPID USER  COMMAND
# 5120  5098 root  nginx: master process nginx -g daemon off;
sudo ls -l /proc/$PID/ns | awk '{print $9, $11}'
ls -l /proc/$$/ns | awk '{print $9, $11}'
```

Différents : `cgroup`, `ipc`, `mnt`, `net`, `pid`, `uts`. Identiques :
`user` (Docker n'utilise pas de user namespace par défaut) et `time`.

```bash
cat /proc/$PID/cgroup
# 0::/system.slice/docker-3f2a9c….scope
sudo nsenter -t "$PID" -n ss -tlnp
# LISTEN 0 511 0.0.0.0:80 0.0.0.0:* users:(("nginx",pid=5120,fd=6))
sudo lsns -t net
#         NS TYPE NPROCS   PID USER COMMAND
# 4026531840 net     143     1 root /sbin/init
# 4026532571 net       3  5120 root nginx: master process nginx -g daemon off;
```

::: pourquoi
Le PID `5120` n'existe que pour l'hôte : dans le conteneur, ce même
processus est le PID 1. `State.Pid` est la passerelle entre les deux mondes,
et `nsenter` permet d'exécuter **un binaire de l'hôte** (`ss`, `tcpdump`,
`strace`) dans les namespaces du conteneur, sans que l'image ait besoin de le
contenir. `-n` seul suffit pour le réseau ; `-m` ferait aussi basculer sur le
système de fichiers du conteneur, où `ss` n'existe peut-être pas. Le PPID
`5098` est le *shim* de containerd (`containerd-shim-runc-v2`) : c'est lui,
et non `dockerd`, qui est le père du conteneur — c'est pourquoi un
redémarrage du démon Docker ne tue pas les conteneurs (`live-restore`).
:::

---

**E18.4** — *Capabilities du PID 1 de `web`, avec et sans `--cap-drop`.*

```bash
PID=$(docker inspect web --format '{{.State.Pid}}')
grep CapEff /proc/$PID/status
# CapEff: 00000000a80425fb
capsh --decode=00000000a80425fb
# 0x00000000a80425fb=cap_chown,cap_dac_override,cap_fowner,cap_fsetid,
# cap_kill,cap_setgid,cap_setuid,cap_setpcap,cap_net_bind_service,
# cap_net_raw,cap_sys_chroot,cap_mknod,cap_audit_write,cap_setfcap

docker run -d --name web-nocap --cap-drop ALL nginx:1.28-alpine
sleep 1; docker logs web-nocap | tail -2
# nginx: [emerg] bind() to 0.0.0.0:80 failed (13: Permission denied)
docker inspect web-nocap --format '{{.State.ExitCode}}'     # 1

docker run -d --name web-bind --cap-drop ALL \
  --cap-add NET_BIND_SERVICE nginx:1.28-alpine
docker logs web-bind 2>&1 | grep -m1 alert
# nginx: [alert] setgid(101) failed (1: Operation not permitted)  (workers)
docker rm -f web-nocap web-bind
docker run -d --name web-min --cap-drop ALL --cap-add NET_BIND_SERVICE \
  --cap-add SETUID --cap-add SETGID nginx:1.28-alpine
grep CapEff /proc/$(docker inspect web-min --format '{{.State.Pid}}')/status
# CapEff: 00000000000004c0
```

`CAP_NET_BIND_SERVICE` est celle qui autorise l'écoute sur un port < 1024.

::: pourquoi
Root dans un conteneur n'est pas root : Docker ne lui laisse que 14
capabilities sur 41, encodées dans le masque `a80425fb`. Sans
`NET_BIND_SERVICE`, même l'UID 0 ne peut pas ouvrir le port 80. L'image
`nginx` officielle a besoin en plus de `SETUID`/`SETGID` parce que le maître
tourne en root et lance ses workers sous l'utilisateur `nginx` — l'image
`nginxinc/nginx-unprivileged` (port 8080, UID 101) n'a besoin de rien. La
démarche pour toute image : `--cap-drop ALL`, lire les journaux, ajouter une
à une les capabilities réclamées, et documenter le résultat dans le Compose
(`cap_add:`).
:::

::: piege
`--user 10001` sans `--cap-drop` laisse un processus non-root **sans**
capabilities effectives (elles ne survivent pas au changement d'UID sauf
`--cap-add` explicite plus fichiers `setcap`), mais le bounding set reste
celui de Docker : un binaire `setuid root` dans l'image les récupérerait.
D'où `no-new-privileges` en complément.
:::

---

**E18.5** — *Digest, couches et taille de `nginx:1.28-alpine`.*

```bash
docker pull nginx:1.28-alpine
docker image inspect nginx:1.28-alpine \
  --format '{{index .RepoDigests 0}}{{"\n"}}{{len .RootFS.Layers}} couches'
# nginx@sha256:5f4a…   (le digest du manifeste)
# 8 couches
docker history nginx:1.28-alpine
# IMAGE          CREATED       CREATED BY                          SIZE
# 2a9f…          3 weeks ago   CMD ["nginx" "-g" "daemon off;"]    0B
# <missing>      3 weeks ago   STOPSIGNAL SIGQUIT                  0B
# <missing>      …             RUN /bin/sh -c set -x && addgroup … 38.9MB
# <missing>      …             ADD alpine-minirootfs-3.20.…tar.gz  7.8MB

DIGEST=$(docker image inspect nginx:1.28-alpine \
  --format '{{index .RepoDigests 0}}' | cut -d@ -f2)
docker pull nginx@"$DIGEST"
# Status: Image is up to date for nginx@sha256:5f4a…
docker images --digests nginx
# REPOSITORY  TAG           DIGEST         IMAGE ID   SIZE
# nginx       1.28-alpine   sha256:5f4a…   2a9f…      52.1MB
# nginx       <none>        sha256:5f4a…   2a9f…      52.1MB
```

::: pourquoi
Trois identifiants coexistent : le **tag** (mobile), le **digest** du
manifeste (`RepoDigests`, ce que le registre garantit), et l'**ID d'image**
(hash de la configuration locale). Tirer par digest ne télécharge rien parce
que le démon compare les digests de chaque couche avec ceux déjà présents ;
la seconde ligne de `docker images` est la même image, référencée sans tag.
Les lignes `<missing>` de `history` ne sont pas une erreur : les couches
intermédiaires ont été construites ailleurs et seuls leurs contenus ont été
tirés, pas les images intermédiaires. Les instructions à `0B` (`CMD`, `ENV`,
`EXPOSE`) ne créent pas de couche de fichiers, seulement des métadonnées.
:::

---

**E18.6** — *Trois limites vues de l'intérieur et de l'extérieur.*

```bash
docker run --rm -it --name limite --memory 64m --memory-swap 64m \
  --cpus 0.5 --pids-limit 50 alpine:3.20 sh
# --- dans le conteneur ---
cat /sys/fs/cgroup/memory.max        # 67108864
cat /sys/fs/cgroup/memory.swap.max   # 0
cat /sys/fs/cgroup/cpu.max           # 50000 100000
cat /sys/fs/cgroup/pids.max          # 50
```

Depuis l'hôte, dans un second terminal :

```bash
ID=$(docker inspect limite --format '{{.Id}}')
cat /sys/fs/cgroup/system.slice/docker-$ID.scope/{memory.max,cpu.max,pids.max}
```

::: pourquoi
Le conteneur voit **son** cgroup à la racine de `/sys/fs/cgroup` : Docker
monte le sous-arbre correspondant (namespace cgroup). `cpu.max` = `quota
période` : 50 000 µs par période de 100 000 µs, soit un demi-cœur, réparti
comme le noyau veut sur les deux vCPU. `--cpus` est une limite de bande
(CFS quota) ; `--cpu-shares` serait une pondération relative, qui ne limite
rien quand la machine est inoccupée. `--memory-swap` égal à `--memory`
signifie « zéro swap » ; par défaut il vaut le double.
:::

---

**E18.7** — *Chronométrer `docker stop` et produire 139 et 1.*

```bash
docker run -d --name dort1 alpine:3.20 sleep 3600
docker run -d --name dort2 --init alpine:3.20 sleep 3600
docker run -d --name dort3 alpine:3.20 sh -c 'sleep 3600; echo fin'
time docker stop dort1     # real 0m10.2s
time docker stop dort2     # real 0m0.3s
time docker stop dort3     # real 0m10.2s
docker inspect dort1 dort2 dort3 --format '{{.Name}} {{.State.ExitCode}}'
# /dort1 137
# /dort2 143
# /dort3 137
```

* `dort1` : `sleep` est PID 1, n'a pas de handler `SIGTERM`, le noyau ignore
  le signal ; après 10 s, `SIGKILL` → 137.
* `dort2` : `docker-init` (tini) est PID 1, relaie `SIGTERM` à `sleep`, qui
  n'est plus PID 1 et meurt par l'action par défaut ; tini sort avec
  128 + 15 = 143.
* `dort3` : `sh` est PID 1 (forme shell avec deux commandes, pas d'`exec`
  implicite), ignore `SIGTERM` et ne le relaie pas → 137.

```bash
docker run --name seg --init alpine:3.20 sh -c 'kill -SEGV $$'
docker inspect seg --format '{{.State.ExitCode}}'          # 139
docker run --name un alpine:3.20 sh -c 'echo erreur >&2; exit 1'
docker inspect un --format '{{.State.ExitCode}}'           # 1
docker rm dort1 dort2 dort3 seg un
```

::: pourquoi
Le code de sortie d'un conteneur est celui de son PID 1 : `128 + numéro du
signal` s'il est tué. Il faut `--init` pour le `139` volontaire : sans lui,
`sh` serait PID 1 et **ignorerait aussi** le `SIGSEGV` qu'il s'envoie (la
règle du PID 1 vaut pour tous les signaux sans handler envoyés depuis le
namespace, sauf `SIGKILL`/`SIGSTOP` depuis l'extérieur). Un vrai plantage
(déréférencement d'un pointeur nul) est délivré quand même, car c'est une
exception synchrone forcée par le noyau, pas un `kill()`.
:::

::: piege
`docker stop -t 30` allonge le délai, `docker kill` le supprime : aucun des
deux ne règle le problème d'un PID 1 sourd. Sur `docker compose stop`, le
délai s'appelle `stop_grace_period`. Et un `STOPSIGNAL SIGQUIT` dans le
Dockerfile (nginx) change le signal envoyé par `stop` : à lire dans
`docker inspect --format '{{.Config.StopSignal}}'`.
:::

---

**E18.8** — *`inspect` avec `--format`, journaux horodatés, `docker cp`.*

```bash
docker inspect web --format \
  '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
docker inspect web --format '{{.HostConfig.RestartPolicy.Name}}'
docker inspect web --format \
  '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'
docker inspect web --format '{{.Path}} {{join .Args " "}}'
# nginx -g daemon off;
docker logs -t --since 5m --tail 20 web
docker cp web:/etc/nginx/conf.d/default.conf ~/lab18/rapports/
```

::: pourquoi
`--format` prend un template Go appliqué à l'objet JSON d'`inspect` : `range`
itère, `index` accède à une clé ou un rang, `json` sérialise une sous-partie
(`{{json .State.Health}}`), `join` concatène. C'est plus robuste que `jq`
dans un script parce que la sortie est vide plutôt qu'erronée si le champ
manque. `docker logs -t` préfixe chaque ligne de l'horodatage **du démon**,
utile quand l'application n'horodate pas. `docker cp` fonctionne sur un
conteneur arrêté et sans shell dans l'image : il lit la couche d'écriture
via le démon.
:::

---

**E18.9** — *`ENTRYPOINT` + `CMD` en trois lignes.*

`~/lab18/bin/entrypoint-test/Dockerfile` :

```dockerfile
FROM alpine:3.20
ENTRYPOINT ["echo", "bonjour"]
CMD ["monde"]
```

```bash
cd ~/lab18/bin/entrypoint-test
docker build -t ep-test .
docker run --rm ep-test              # bonjour monde
docker run --rm ep-test lab-ops      # bonjour lab-ops
docker inspect ep-test --format '{{.Config.Entrypoint}} {{.Config.Cmd}}'
# [echo bonjour] [monde]
```

Forme shell :

```dockerfile
FROM alpine:3.20
ENTRYPOINT echo bonjour
CMD ["monde"]
```

```bash
docker build -t ep-shell . && docker run --rm ep-shell lab-ops
# bonjour
docker inspect ep-shell --format '{{.Config.Entrypoint}}'
# [/bin/sh -c echo bonjour]
docker run --rm -it --entrypoint sh ep-test
```

::: pourquoi
Avec un `ENTRYPOINT` en forme shell, la commande finale est
`/bin/sh -c "echo bonjour" monde` : le `sh -c` ne lit que son premier
argument, les suivants deviennent `$0`, `$1`… du script, jamais utilisés.
`CMD` et les arguments de `docker run` sont donc **silencieusement
ignorés**. C'est le second défaut de la forme shell, après le PID 1.
`--entrypoint` ne prend qu'un mot : les arguments vont après l'image
(`--entrypoint sh ep-test -c 'ls /'`).
:::

---

**E18.10** — *`ARG` fuit dans `docker history`.*

```dockerfile
FROM alpine:3.20
ARG VERSION=dev
ENV APP_VERSION=$VERSION
RUN echo "$VERSION" > /version.txt
```

```bash
docker build --build-arg VERSION=1.2 -t arg-test .
docker inspect arg-test --format '{{.Config.Env}}'
# [PATH=/usr/local/sbin:… APP_VERSION=1.2]
docker run --rm arg-test sh -c 'echo "VERSION=[$VERSION]"; cat /version.txt'
# VERSION=[]
# 1.2
docker history --no-trunc --format '{{.CreatedBy}}' arg-test | head -3
# RUN |1 VERSION=1.2 /bin/sh -c echo "$VERSION" > /version.txt # buildkit
# ENV APP_VERSION=1.2
# ARG VERSION=dev
```

::: pourquoi
Chaque couche enregistre l'instruction qui l'a produite **avec les
arguments de build en vigueur** (`|1 VERSION=1.2`) : c'est ce qui permet au
cache de distinguer deux builds avec des `--build-arg` différents. Donc tout
`ARG` utilisé par un `RUN` est lisible par quiconque a l'image, même sans
`ENV`. On ne passe jamais de jeton, mot de passe ou clé privée en
`--build-arg` : `RUN --mount=type=secret,id=pip,dst=/etc/pip.conf …` avec
`docker build --secret id=pip,src=$HOME/.config/pip/pip.conf` monte le
fichier le temps de l'instruction, sans trace dans les couches ni l'historique.
:::

---

**E18.11** — *Cache invalidé par un `COPY . .` trop tôt.*

Version « Q18.5 » de `~/lab18/api/Dockerfile` :

```dockerfile
FROM python:3.12-slim-bookworm
WORKDIR /app
COPY . .
RUN pip install --no-cache-dir -r requirements.txt
CMD ["python3", "app.py"]
```

```bash
cd ~/lab18/api
docker build -t factura-api:cache-test .
sed -i 's/^"""factura-api/"""factura-api (test cache)/' app.py
time docker build --progress=plain -t factura-api:cache-test . 2>&1 \
  | grep -E '^#[0-9]+ (\[|CACHED)'
# #6 [2/4] WORKDIR /app                      CACHED
# #7 [3/4] COPY . .                          (rejoué)
# #8 [4/4] RUN pip install …                 (rejoué : ~25 s)
```

Version corrigée :

```dockerfile
FROM python:3.12-slim-bookworm
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python3", "app.py"]
```

```bash
docker build -t factura-api:cache-test .          # premier build complet
sed -i 's/(test cache)/(test cache 2)/' app.py
time docker build --progress=plain -t factura-api:cache-test . 2>&1 \
  | grep -E '^#[0-9]+ (\[|CACHED)'
# #7 CACHED [3/5] COPY requirements.txt .
# #8 CACHED [4/5] RUN pip install …
# #9 [5/5] COPY . .                          (seule étape rejouée : ~1 s)
```

::: pourquoi
Voir Q18.5 : le cache est un préfixe. Tout ce qui précède la première
instruction invalidée est réutilisé, tout ce qui suit est rejoué. On classe
donc les instructions de la plus stable à la plus volatile : image de base,
paquets système, dépendances applicatives, code, configuration. La
différence de temps (25 s contre 1 s) se multiplie par le nombre de builds
par jour dans un pipeline.
:::

---

**E18.12** — *Volume : persistance, sauvegarde, restauration.*

```bash
docker volume create factura-data
docker run --rm -v factura-data:/data alpine:3.20 \
  sh -c 'echo "bonjour $(date)" > /data/test.txt'
docker run --rm -v factura-data:/data alpine:3.20 cat /data/test.txt
docker volume inspect factura-data --format '{{.Mountpoint}}'
# /var/lib/docker/volumes/factura-data/_data

docker run --rm --user "$(id -u):$(id -g)" \
  -v factura-data:/from:ro -v ~/lab18/rapports:/to alpine:3.20 \
  tar czf /to/factura-data.tgz -C /from .
ls -l ~/lab18/rapports/factura-data.tgz

docker volume create factura-data-copie
docker run --rm -v factura-data-copie:/to -v ~/lab18/rapports:/from:ro \
  alpine:3.20 tar xzf /from/factura-data.tgz -C /to
docker run --rm -v factura-data-copie:/data alpine:3.20 cat /data/test.txt
```

::: pourquoi
Un volume nommé est un répertoire géré par le démon sous
`/var/lib/docker/volumes/`, accessible seulement par root : la façon
propre d'y lire et d'y écrire est un conteneur utilitaire qui le monte. La
sauvegarde s'exécute avec ton UID pour que l'archive t'appartienne ; la
restauration se fait en root parce que `_data` du volume neuf appartient à
root. `-C /from .` archive les chemins relatifs, ce qui permet de restaurer
n'importe où. Pour une base de données, on n'archive pas les fichiers à chaud :
on utilise l'outil du moteur (`pg_dump`) ou on arrête le conteneur avant.
:::

---

**E18.13** — *Bind mount et UID 10001.*

```bash
docker run --rm --user 10001:10001 -v /srv/factura-docker/data:/data \
  alpine:3.20 touch /data/test
# touch: /data/test: Permission denied
sudo chown 10001:10001 /srv/factura-docker/data       # 0755 conservé
docker run --rm --user 10001:10001 -v /srv/factura-docker/data:/data \
  alpine:3.20 touch /data/test
ls -ln /srv/factura-docker/data/test
# -rw-r--r-- 1 10001 10001 0 sept. 19 10:42 /srv/factura-docker/data/test
ls -l /srv/factura-docker/data/test
# -rw-r--r-- 1 10001 10001 0 sept. 19 10:42 /srv/factura-docker/data/test
```

`ls -l` affiche le nombre parce qu'aucune entrée de `/etc/passwd` de
**l'hôte** ne porte l'UID 10001 : le nom `app` n'existe que dans l'image.

::: pourquoi
Le bind mount ne traduit rien : le noyau compare l'UID du processus (10001)
aux bits de droits du répertoire hôte (`root:root 0755`). Seul le
propriétaire peut y créer un fichier. `chown` au bon UID est la correction
la plus restrictive ; `chgrp` + `g+w` ou une ACL `setfacl -m u:10001:rwx`
sont les alternatives quand le répertoire doit rester à son propriétaire.
`chmod 777` donne le droit à tout le monde sur l'hôte, y compris à un
service compromis.
:::

---

**E18.14** — *DNS des réseaux utilisateur et règles NAT.*

```bash
docker network create factura-net
docker run -d --name cache --network factura-net redis:7-alpine
docker run --rm --network factura-net alpine:3.20 \
  sh -c 'getent hosts cache; grep nameserver /etc/resolv.conf'
# 172.18.0.2        cache
# nameserver 127.0.0.11
docker run --rm alpine:3.20 sh -c 'getent hosts cache || echo "echec $?"'
# echec 2

sudo iptables -t nat -S DOCKER
# -N DOCKER
# -A DOCKER -i docker0 -j RETURN
# -A DOCKER -i br-1c4e… -j RETURN
# -A DOCKER ! -i docker0 -p tcp -m tcp --dport 8080 \
#   -j DNAT --to-destination 172.17.0.2:80
sudo iptables -t nat -S PREROUTING | grep DOCKER
# -A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
docker port web
# 80/tcp -> 0.0.0.0:8080
# 80/tcp -> [::]:8080
```

::: pourquoi
`127.0.0.11` est le résolveur intégré du démon, injecté dans chaque
conteneur d'un réseau utilisateur ; il connaît les noms de conteneurs, les
alias (`--network-alias`) et les noms de services Compose, et transmet le
reste aux DNS de l'hôte. Le bridge par défaut en est privé pour des raisons
de compatibilité historique. Côté NAT, la règle `DNAT` de la chaîne `DOCKER`
est la matérialisation de `-p 8080:80` ; `! -i docker0` évite de re-NATer le
trafic qui vient déjà du bridge. La seconde ligne de `docker port` rappelle
que la publication vaut aussi en IPv6.
:::

---

**E18.15** — *Rotation des journaux pour un seul conteneur.*

```bash
docker run -d --name bavard --log-opt max-size=1m --log-opt max-file=2 \
  alpine:3.20 yes "journal de test, ligne de remplissage pour la rotation"
sleep 10
ID=$(docker inspect bavard --format '{{.Id}}')
sudo ls -l /var/lib/docker/containers/$ID/ | grep json.log
# -rw-r----- 1 root root  612344 … 3f2a…-json.log
# -rw-r----- 1 root root 1048576 … 3f2a…-json.log.1
docker logs bavard | wc -l          # ~20 000 lignes, pas des millions
docker inspect bavard --format '{{json .HostConfig.LogConfig}}'
# {"Type":"json-file","Config":{"max-file":"2","max-size":"1m"}}
docker rm -f bavard
```

Pour tous les conteneurs futurs, dans `/etc/docker/daemon.json` :

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
```

::: pourquoi
Le driver `json-file` écrit chaque ligne de stdout/stderr en JSON
(horodatage, flux, contenu) dans un fichier par conteneur. Sans `max-size`,
le fichier grossit sans limite — c'est la première cause de disque plein sur
un hôte Docker. La rotation garde `max-file` fichiers de `max-size` au plus ;
`docker logs` ne lit que ce qui reste. L'option est figée à la création du
conteneur (Q18.15). Une application qui journalise beaucoup gagne à envoyer
vers `journald` ou un collecteur plutôt qu'à remplir des fichiers JSON.
:::

---

**E18.16** — *`docker events` et `docker system df`.*

Terminal 2 : `docker events --format '{{.Time}} {{.Type}} {{.Action}} {{.Actor.Attributes.name}}'`.

Terminal 1 :

```bash
docker run --name ev alpine:3.20 true && docker rm ev
docker volume create ev-vol && docker volume rm ev-vol
```

Événements observés (terminal 2) :

```text
1758270012 container create ev
1758270012 network connect bridge
1758270012 container start ev
1758270012 container die ev
1758270012 network disconnect bridge
1758270013 container destroy ev
1758270014 volume create ev-vol
1758270014 volume destroy ev-vol
```

```bash
docker system df
# TYPE            TOTAL   ACTIVE   SIZE      RECLAIMABLE
# Images          6       3        612MB     318MB (51%)
# Containers      4       2        1.2MB     0B (0%)
# Local Volumes   3       1        41MB      12MB (29%)
# Build Cache     22      0        231MB     231MB
docker system df -v | sed -n '/Images space usage/,/Containers space/p'
```

* `SIZE` : taille totale de l'image ;
* `SHARED SIZE` : la part de couches partagées avec au moins une autre image
  (comptée une seule fois sur le disque) ;
* `UNIQUE SIZE` : ce qui n'appartient qu'à cette image ;
* `RECLAIMABLE` : ce qu'un `prune` libérerait, c'est-à-dire ce qui n'est
  utilisé par aucun conteneur (les volumes non montés, les images sans
  conteneur, tout le cache de build).

::: pourquoi
`docker events` est le journal d'audit du démon : chaque action y passe avec
son auteur (`Actor`), en temps réel ou avec `--since`/`--until`. C'est
l'outil pour répondre à « qui a redémarré ce conteneur à 3 h du matin » (en
croisant avec `journalctl -u docker`). `docker system df` est le `df` de
Docker : il distingue ce qui est **utilisé** de ce qui est **récupérable**,
et c'est lui qu'on lit avant tout `prune`. Le cache de build (BuildKit) est
souvent le poste le plus gros et le plus sûr à purger (`docker builder
prune`).
:::

---

## 18.6 Labs

### **L18.1** — *Installer Docker Engine proprement sur `lab-ops`.*

**1. État des lieux**

```bash
dpkg -l | grep -E 'docker|containerd|podman'
snap list 2>/dev/null | grep docker
sudo apt remove -y docker.io docker-doc docker-compose podman-docker \
  containerd runc 2>/dev/null
ls /var/lib/docker 2>/dev/null
```

Un paquet retiré ne supprime pas `/var/lib/docker` : images, conteneurs et
volumes de l'ancienne installation y restent (et seraient repris par la
nouvelle installation si le driver de stockage est le même).

**2. Dépôt officiel**

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) \
signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu noble stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
apt-cache policy docker-ce | head -4
# docker-ce:
#   Installed: 5:28.3.3-1~ubuntu.24.04~noble
#   Candidate: 5:28.3.3-1~ubuntu.24.04~noble
#   Version table: … https://download.docker.com/linux/ubuntu noble/stable
```

**3. `daemon.json`**

```bash
sudo install -m 0644 /dev/stdin /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "insecure-registries": ["lab-ops.lab.local:5000"]
}
EOF
jq . /etc/docker/daemon.json >/dev/null && echo "JSON valide"
sudo systemctl restart docker
docker info --format '{{.LoggingDriver}}'                 # json-file
docker info --format '{{.RegistryConfig.InsecureRegistryCIDRs}}'
docker info | grep -A3 'Insecure Registries'
#  Insecure Registries:
#   lab-ops.lab.local:5000
#   127.0.0.0/8
```

**4. Démarrage au boot**

```bash
systemctl is-enabled docker containerd    # enabled enabled
systemctl is-active docker.socket         # active
```

`docker.socket` permet l'activation par socket : le démon pourrait ne
démarrer qu'au premier appel d'un client. Comme `docker.service` est
lui-même `enabled` et que les conteneurs à politique de redémarrage doivent
revenir au boot, il démarre de toute façon ; le socket sert surtout à ce
qu'un client lancé pendant le boot n'échoue pas.

**5. Le groupe `docker`**

```bash
sudo usermod -aG docker mathieu
# nouvelle session SSH, puis :
id -nG | tr ' ' '\n' | grep -x docker
docker info >/dev/null && echo OK
```

La démonstration demandée est celle de QO18.6 : un membre du groupe peut
monter n'importe quel chemin de l'hôte dans un conteneur et le lire ou
l'écrire en tant que root. Conclusion à écrire dans le rapport : « être dans
le groupe `docker` = être root sans mot de passe et sans trace `sudo` ; sur
un serveur partagé, on réserve ce groupe aux comptes de service, et on
préfère `sudo docker` (tracé) ou le mode rootless. »

**6. Le rapport**

```bash
{
  echo "# Installation Docker sur lab-ops — $(date +%F)"
  docker version --format 'Engine {{.Server.Version}}'
  docker compose version
  docker buildx version
  docker info --format 'storage={{.Driver}} cgroup=v{{.CgroupVersion}} \
racine={{.DockerRootDir}}'
} >> ~/lab18/rapports/installation.md
```

Attendu sur Ubuntu 24.04 : `storage=overlay2 cgroup=v2
racine=/var/lib/docker`.

**7. Rootless**

```bash
sudo apt install -y docker-ce-rootless-extras
sudo useradd -m -s /bin/bash kevin
sudo passwd kevin
sudo loginctl enable-linger kevin
ssh kevin@localhost
# --- session de kevin ---
dockerd-rootless-setuptool.sh install
# [INFO] Installed docker.service successfully.
# [INFO] To control docker service run: systemctl --user (start|stop|…)
# [INFO] Make sure the following environment variable is set:
# export DOCKER_HOST=unix:///run/user/1001/docker.sock
echo 'export DOCKER_HOST=unix:///run/user/1001/docker.sock' >> ~/.bashrc
export DOCKER_HOST=unix:///run/user/1001/docker.sock
docker run -d --name web-rootless -p 8081:80 nginx:1.28-alpine
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8081/   # 200
ps -o user,pid,args -C dockerd
# USER   PID  COMMAND
# root   812  /usr/bin/dockerd -H fd:// --containerd=/run/containerd/…
# kevin 4410 dockerd
docker run -d -p 80:80 nginx:1.28-alpine
# docker: Error response from daemon: … listen tcp4 0.0.0.0:80:
# bind: permission denied
```

Le démon de `kevin` n'est pas root : il ne peut pas ouvrir un port
privilégié (sauf `sudo sysctl net.ipv4.ip_unprivileged_port_start=0`). Ses
données sont dans `~/.local/share/docker`, et `/etc/subuid` contient
`kevin:100000:65536` : la plage d'UID que ses conteneurs utilisent.

::: rhel
Sur `lab-rhel`, `podman run -d -p 8080:80 docker.io/library/nginx:1.28-alpine`
fonctionne sans démon ni groupe : `ps -o user,pid,args -C conmon` montre le
superviseur du conteneur sous ton propre compte. Deux différences visibles :
le nom d'image doit être complet (`docker.io/library/…`, ou configuré dans
`/etc/containers/registries.conf`) et il n'y a pas de `dockerd` dans
`ps` — chaque conteneur est un fils de `conmon`, lui-même fils de ton shell
(ou de systemd si tu génères une unité avec `podman generate systemd`).
:::

::: pourquoi
Le dépôt officiel donne des versions récentes et cohérentes (Engine,
containerd, buildx, Compose v2) ; `docker.io` d'Ubuntu retarde de plusieurs
versions et le snap isole le démon d'une façon qui casse les bind mounts hors
de `/home`. `daemon.json` est lu **au démarrage** du démon : une erreur de
syntaxe empêche Docker de démarrer, d'où la validation par `jq` avant le
`restart`. La rotation des journaux est réglée dès l'installation parce
qu'elle ne s'applique qu'aux conteneurs créés après (Q18.15).
:::

::: piege
`usermod -aG` ne prend effet qu'à la **prochaine session** : le `docker info`
qui échoue avec `permission denied while trying to connect to the Docker
daemon socket` juste après est normal. `newgrp docker` dépanne dans le shell
courant. Et il faut le `-a` : `usermod -G docker mathieu` retirerait le
compte de tous ses autres groupes, `sudo` compris.
:::

---

### **L18.2** — *Du Dockerfile de Kevin à une image livrable.*

**1. Mesures sur l'image de Kevin**

```bash
cd ~/lab18/mauvaise
time docker build -t factura-api:kevin .            # ~1 min 30
docker images factura-api:kevin --format '{{.Size}}'  # 1.2GB
docker history factura-api:kevin | head -12
docker image inspect factura-api:kevin --format '{{.Config.User}}'
# (vide : root)
docker image inspect factura-api:kevin --format '{{json .Config.Env}}' | jq
# … "DATABASE_URL=postgresql://factura:Factura-2024@db:5432/factura",
#    "FACTURA_CLE_API=sk-prod-9f8e7d6c5b4a"
docker run --rm factura-api:kevin ls -la /app /app/donnees
# secret.txt, donnees/export-clients.bin (64 Mo) sont dans l'image
docker run -d --name kevin -p 8000:8000 factura-api:kevin
time docker stop kevin                              # 10 s, code 137
```

**2. L'audit** (`~/lab18/rapports/audit-dockerfile.md`)

| Ligne | Problème | Correction |
|---|---|---|
| `FROM python:latest` | tag mobile, image complète (1 Go), non reproductible | `python:3.12.6-slim-bookworm` épinglé |
| `ADD . /app` | copie tout le contexte (secret, 64 Mo de données, README), `ADD` décompresse et télécharge | `COPY` ciblé + `.dockerignore` |
| `RUN apt-get update` seul | couche de listes de paquets figée en cache, jamais nettoyée | fusionner avec l'install et `rm -rf /var/lib/apt/lists/*`, ou supprimer |
| `apt-get install curl vim git` | outils inutiles à l'exécution, surface d'attaque, +200 Mo | aucun, ou étage `debug` |
| `pip install flask redis psycopg[binary]` | versions non épinglées, cache pip dans la couche | `requirements.txt` + `--no-cache-dir`, en premier étage |
| `ENV DATABASE_URL=…mot de passe…` | secret en clair dans l'image et `docker inspect` | variable au déploiement, mot de passe via secret/fichier |
| `ENV FACTURA_CLE_API=…` | clé de production dans une image (et dans le registre) | idem, jamais dans l'image |
| pas de `USER` | root dans le conteneur | `USER app` (UID 10001) |
| `CMD sh /app/start.sh` | forme shell, `sh` PID 1 sourd à `SIGTERM`, 10 s d'arrêt, code 137 | `ENTRYPOINT ["python3", "app.py"]` |
| pas de `HEALTHCHECK` | Compose/`docker ps` ne savent pas si l'API répond | `HEALTHCHECK` sur `/sante` |
| `EXPOSE 8000` sans commentaire | pas un défaut, mais ne publie rien : à documenter | garder |
| `secret.txt` dans le contexte | fuit dans l'image via `ADD .` | `.dockerignore`, et retirer le fichier du dépôt |

**3. `.dockerignore` et `Dockerfile`** (`~/lab18/api/`)

```text
.git
.gitignore
*.md
__pycache__/
*.pyc
.env
secrets/
donnees/
secret.txt
*.bin
*.tgz
Dockerfile*
.dockerignore
```

```dockerfile
# syntax=docker/dockerfile:1
FROM python:3.12.6-slim-bookworm AS builder
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build
COPY requirements.txt .
RUN pip install --prefix=/install -r requirements.txt

FROM python:3.12.6-slim-bookworm AS base
ARG APP_VERSION=dev
LABEL org.opencontainers.image.title="factura-api" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.source="https://git.lab.local/factura/api"
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 \
    APP_VERSION=${APP_VERSION} PORT=8000
RUN groupadd -r -g 10001 app \
    && useradd -r -u 10001 -g app -d /app -s /usr/sbin/nologin app \
    && mkdir -p /app /data && chown app:app /app /data \
    && rm -rf /usr/local/lib/python3.12/site-packages/pip*
COPY --from=builder /install /usr/local
WORKDIR /app
COPY --chown=app:app app.py .
USER app
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD python3 -c "import urllib.request as u; \
u.urlopen('http://127.0.0.1:8000/sante', timeout=2)"
ENTRYPOINT ["python3", "app.py"]

FROM base AS debug
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl procps \
    && rm -rf /var/lib/apt/lists/*
USER app

FROM base AS runtime
```

**4. Construction et vérifications**

```bash
cd ~/lab18/api
docker build --build-arg APP_VERSION=1.0 -t factura-api:1.0 .
docker images factura-api:1.0 --format '{{.Size}}'          # ~140MB
docker image inspect factura-api:1.0 \
  --format 'user={{.Config.User}} hc={{.Config.Healthcheck.Test}}'
# user=app hc=[CMD-SHELL python3 -c "import urllib…"]
docker image inspect factura-api:1.0 --format '{{.Config.Entrypoint}}'
# [python3 app.py]
docker run --rm factura-api:1.0 ls -la /app            # app.py seulement
docker run -d --name api -p 8000:8000 factura-api:1.0
docker ps --format '{{.Names}} {{.Status}}'   # api Up 3s (health: starting)
sleep 12
docker ps --format '{{.Names}} {{.Status}}'   # api Up 15s (healthy)
curl -s http://127.0.0.1:8000/ | jq .uid               # 10001
time docker stop api                                   # 0,4 s
docker inspect api --format '{{.State.ExitCode}}'      # 0
docker logs api | tail -1
# [factura-api] signal SIGTERM recu : arret propre
docker rm api
```

**5. Trivy**

```bash
trivy image --severity HIGH,CRITICAL --ignore-unfixed factura-api:1.0 \
  | tee ~/lab18/rapports/trivy-factura-api.txt
trivy image --severity HIGH,CRITICAL --ignore-unfixed factura-api:kevin \
  | grep -E '^Total'
```

L'image de Kevin traîne des centaines de CVE (Debian complet, `git`,
`vim`, `curl`) ; la slim en a une poignée, presque toutes dans la base
Debian. S'il reste une `CRITICAL` corrigée en amont, on relit
`docker.io/library/python` pour prendre le dernier `3.12.x-slim-bookworm`
et on reconstruit avec `--pull`.

**6. L'étage `debug`**

```bash
docker build --target debug -t factura-api:1.0-debug .
docker build -t factura-api:1.0 .      # cible par défaut = runtime
docker run --rm factura-api:1.0-debug curl --version | head -1
docker run --rm factura-api:1.0 curl --version
# exec: "curl": executable file not found in $PATH   (attendu)
```

::: pourquoi
La cible par défaut d'un build multi-stage est le **dernier** étage du
fichier : c'est pourquoi `runtime` est un étage vide placé en dernier,
dérivé de `base`, et `debug` est intercalé. `--prefix=/install` puis
`COPY --from=builder /install /usr/local` ne rapporte que les paquets
installés, sans le cache pip ni les éventuels compilateurs. `mkdir /data &&
chown app:app` prépare le point de montage : un volume nommé vide héritera
de ce propriétaire (Q18.8). Retirer `pip` de l'image finale enlève 10 Mo et
un outil qui n'a rien à faire en production. `PYTHONDONTWRITEBYTECODE`
permet le `--read-only` sans que Python cherche à écrire des `.pyc`.
:::

::: piege
`useradd -r` sans `-u` choisirait un UID système libre (< 1000), différent
d'une machine à l'autre : les bind mounts deviendraient imprévisibles. On
fixe **toujours** l'UID. Et `USER app` doit venir **après** tout ce qui
requiert root (`groupadd`, `chown`, `apt-get`) mais **avant** `ENTRYPOINT`,
sinon le processus démarre en root. `COPY --chown` est nécessaire parce que
`COPY` copie en root par défaut, quel que soit le `USER` courant.
:::

---

### **L18.3** — *Données, UID et réseau : faire tourner l'API pour de vrai.*

**1. Volume nommé**

```bash
docker volume create factura-data
docker run -d --name factura-visites -p 8000:8000 -e DATA_DIR=/data \
  -v factura-data:/data factura-api:1.0
for i in 1 2 3; do curl -s http://127.0.0.1:8000/visites; done
docker rm -f factura-visites
docker run -d --name factura-visites -p 8000:8000 -e DATA_DIR=/data \
  -v factura-data:/data factura-api:1.0
curl -s http://127.0.0.1:8000/visites
# {"fichier":"/data/visites.log","visites":4}
sudo ls -ln /var/lib/docker/volumes/factura-data/_data
# -rw-r--r-- 1 10001 10001 … visites.log
```

Le volume vide a été peuplé au premier montage avec le `/data` de l'image,
propriétaire `app:app` (UID 10001) — c'est le `chown` du Dockerfile qui
s'est propagé. Les données vivent dans `/var/lib/docker/volumes/`.

**2. Bind mount et UID**

```bash
docker rm -f factura-visites
docker run -d --name factura-visites -p 8000:8000 -e DATA_DIR=/data \
  -v /srv/factura-docker/data:/data factura-api:1.0
curl -s http://127.0.0.1:8000/visites        # HTTP 500
docker logs factura-visites 2>&1 | grep -m1 Error
# PermissionError: [Errno 13] Permission denied: '/data/visites.log'
sudo chown 10001:root /srv/factura-docker/data
sudo chmod 0750 /srv/factura-docker/data
curl -s http://127.0.0.1:8000/visites        # {"visites":1,…}
ls -ln /srv/factura-docker/data/visites.log
# -rw-r--r-- 1 10001 10001 …
```

`ls -l` affiche `10001 10001` faute d'entrée dans `/etc/passwd` ; sur un
hôte où l'UID 10001 existerait sous le nom `jenkins`, on lirait `jenkins
jenkins` — sans que ce compte ait le moindre rapport avec l'API. `0750`
`10001:root` est le réglage le plus restrictif : seul le processus de l'API
écrit, root lit pour les sauvegardes.

**3. Réseau utilisateur et Redis**

```bash
docker network create factura-net
docker run -d --name cache --network factura-net --restart unless-stopped \
  redis:7-alpine redis-server --save '' --appendonly no
docker rm -f factura-visites
docker run -d --name factura-visites --network factura-net \
  -p 8000:8000 -e DATA_DIR=/data -e REDIS_URL=redis://cache:6379/0 \
  -v /srv/factura-docker/data:/data factura-api:1.0
curl -s http://127.0.0.1:8000/compteur       # {"compteur":1}
curl -s http://127.0.0.1:8000/compteur       # {"compteur":2}
ss -tlnp | grep 6379                         # rien : port non publié
docker run --rm alpine:3.20 sh -c 'nc -zvw2 cache 6379'
# nc: bad address 'cache'
docker run --rm alpine:3.20 sh -c 'nc -zvw2 172.18.0.2 6379'
# nc: 172.18.0.2 (172.18.0.2:6379): Operation timed out
```

Le second test montre que Docker **isole les réseaux entre eux**
(`DOCKER-ISOLATION-STAGE-*`) : même par IP, le bridge par défaut ne joint
pas `factura-net`.

**4. Durcissement**

```bash
docker rm -f factura-visites
docker run -d --name factura-visites --network factura-net \
  -p 8000:8000 -e DATA_DIR=/data -e REDIS_URL=redis://cache:6379/0 \
  -v /srv/factura-docker/data:/data \
  --read-only --tmpfs /tmp --cap-drop ALL \
  --security-opt no-new-privileges --memory 128m --memory-swap 128m \
  --restart unless-stopped factura-api:1.0
curl -s http://127.0.0.1:8000/visites        # écrit toujours dans /data
docker exec factura-visites touch /app/x
# touch: cannot touch '/app/x': Read-only file system
docker inspect factura-visites --format '{{.HostConfig.ReadonlyRootfs}} \
{{.HostConfig.CapDrop}} {{.HostConfig.Memory}}'
# true [ALL] 134217728
```

**5. Publication et filtrage**

```bash
# depuis lab-adm
curl -s http://10.10.10.14:8000/sante        # {"statut":"ok"}
# sur lab-ops
sudo iptables -I DOCKER-USER -i ens18 -p tcp --dport 8000 \
  ! -s 10.10.10.10 -j DROP
sudo iptables -S DOCKER-USER
# -N DOCKER-USER
# -A DOCKER-USER -i ens18 ! -s 10.10.10.10/32 -p tcp -m tcp --dport 8000 -j DROP
# -A DOCKER-USER -j RETURN
# depuis lab-web : curl -m 5 http://10.10.10.14:8000/sante
# curl: (28) Connection timed out after 5001 milliseconds
```

`DOCKER-USER` est la seule chaîne que Docker crée puis **laisse
intacte** : elle est appelée en premier depuis `FORWARD`, avant les chaînes
`DOCKER*` qui acceptent le trafic vers les conteneurs, et Docker ne la
réécrit pas au redémarrage. `--dport 8000` est le port **du conteneur**
(après DNAT) — ici identique au port publié.

Persistance : `sudo apt install iptables-persistent` puis
`sudo netfilter-persistent save` (fichier `/etc/iptables/rules.v4`), ou
une unité systemd `After=docker.service` qui rejoue la règle. À écrire dans
`stockage.md`.

**6. Sauvegarde et rapport**

```bash
docker run --rm --user "$(id -u):$(id -g)" -v factura-data:/from:ro \
  -v ~/lab18/rapports:/to alpine:3.20 tar czf /to/factura-data.tgz -C /from .
```

`~/lab18/rapports/stockage.md` :

```text
Restauration :
  docker volume create factura-data
  docker run --rm -v factura-data:/to -v ~/lab18/rapports:/from:ro \
    alpine:3.20 tar xzf /from/factura-data.tgz -C /to
  docker run -d … -v factura-data:/data factura-api:1.0

| Type       | Cas d'usage                                              |
|------------|----------------------------------------------------------|
| volume     | données d'un service : portable, sauvegardable, droits OK |
| bind mount | conf, code en dev, données déjà sur l'hôte : UID à aligner|
| tmpfs      | temporaires, secrets éphémères, avec --read-only          |

Règle iptables persistée dans /etc/iptables/rules.v4 (iptables-persistent).
```

::: pourquoi
Ce lab enchaîne les quatre questions qu'un exploitant se pose pour un
conteneur : **où sont les données** (volume géré, ou chemin hôte qu'on
maîtrise), **qui écrit** (UID numérique, sans traduction), **qui parle à
qui** (réseau utilisateur avec DNS, ports non publiés pour ce qui reste
interne), **qui entre** (publication + `DOCKER-USER`). Le durcissement de
l'étape 4 ne casse rien parce que l'application a été conçue pour : elle
n'écrit que dans `/data`, lit sa configuration dans l'environnement, et
n'a besoin d'aucune capability sur un port > 1024.
:::

::: piege
`--memory` sans `--memory-swap` laisse le conteneur déborder dans le swap
de l'hôte (Q18.9). `--read-only` sans `--tmpfs /tmp` casse beaucoup de
programmes qui écrivent des fichiers temporaires. Et un `docker rm -f` du
conteneur `cache` sans volume perd les compteurs : c'est voulu ici (cache),
ce ne l'est pas pour une base.
:::

---

### **L18.4** — *La pile complète en Compose.*

Arborescence de `~/lab18/compose/` :

```text
compose.yaml  compose.override.yaml  compose.prod.yaml  .env
nginx/default.conf  secrets/db_password.txt
```

`.env` :

```text
APP_VERSION=1.0
```

`nginx/default.conf` :

```nginx
server {
    listen 80;
    location / {
        proxy_pass http://app:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

Le secret :

```bash
mkdir -p ~/lab18/compose/secrets
openssl rand -base64 24 > ~/lab18/compose/secrets/db_password.txt
chmod 0700 ~/lab18/compose/secrets
chmod 0444 ~/lab18/compose/secrets/db_password.txt
```

`compose.yaml` :

```yaml
name: factura

services:
  proxy:
    image: nginx:1.28-alpine
    ports:
      - "8080:80"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      app:
        condition: service_healthy
    restart: unless-stopped

  app:
    build:
      context: ../api
      args:
        APP_VERSION: ${APP_VERSION}
    image: factura-api:${APP_VERSION}
    environment:
      APP_VERSION: ${APP_VERSION}
      DATA_DIR: /data
      REDIS_URL: redis://cache:6379/0
      DATABASE_URL: postgresql://factura@db:5432/factura
      DATABASE_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    volumes:
      - app-data:/data
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    mem_limit: 256m
    depends_on:
      db:
        condition: service_healthy
      cache:
        condition: service_healthy
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: factura
      POSTGRES_DB: factura
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    volumes:
      - pg-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h 127.0.0.1 -U factura -d factura"]
      interval: 5s
      timeout: 3s
      retries: 10
    restart: unless-stopped

  cache:
    image: redis:7-alpine
    command: ["redis-server", "--save", "", "--appendonly", "no"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 10
    restart: unless-stopped

  adminer:
    image: adminer:4
    profiles:
      - debug
    ports:
      - "127.0.0.1:8081:8080"
    depends_on:
      - db

volumes:
  pg-data:
  app-data:

secrets:
  db_password:
    file: ./secrets/db_password.txt
```

**3. Séquence de démarrage**

```bash
cd ~/lab18/compose
docker compose up -d --build
docker compose ps --format 'table {{.Name}}\t{{.Status}}'
# factura-cache-1   Up 2 seconds (health: starting)
# factura-db-1      Up 2 seconds (health: starting)
# (app et proxy n'existent pas encore)
sleep 15; docker compose ps --format 'table {{.Name}}\t{{.Status}}'
# factura-app-1     Up 8 seconds (healthy)
# factura-cache-1   Up 20 seconds (healthy)
# factura-db-1      Up 20 seconds (healthy)
# factura-proxy-1   Up 1 second
docker compose events --json | jq -r '.time+" "+.service+" "+.action' &
```

**4. Fonctionnement et preuve du secret**

```bash
curl -s http://127.0.0.1:8080/clients                  # {"clients":0}
curl -s -X POST 'http://127.0.0.1:8080/clients?nom=Dupont'
curl -s http://127.0.0.1:8080/clients                  # {"clients":1}
curl -s http://127.0.0.1:8080/compteur                 # {"compteur":1}
docker inspect factura-app-1 --format '{{.Config.Env}}' \
  | grep -c "$(cat secrets/db_password.txt)"           # 0
docker compose exec app cat /run/secrets/db_password   # le secret, monté
```

**5. Profil**

```bash
docker compose config --services                 # proxy app db cache
docker compose --profile debug config --services # + adminer
docker compose --profile debug up -d adminer
```

**6. Override et prod**

`compose.override.yaml` (lu automatiquement) :

```yaml
services:
  app:
    environment:
      APP_VERSION: dev
    volumes:
      - ../api:/app:ro
    ports:
      - "127.0.0.1:8000:8000"
```

`compose.prod.yaml` :

```yaml
services:
  app:
    build: !reset null
    image: lab-ops.lab.local:5000/factura-api:${APP_VERSION}
    logging:
      driver: json-file
      options:
        max-size: "5m"
        max-file: "2"
  proxy:
    logging:
      driver: json-file
      options:
        max-size: "5m"
        max-file: "2"
```

```bash
docker compose config | grep -A2 'APP_VERSION'        # dev (override)
docker compose -f compose.yaml -f compose.prod.yaml config \
  | grep -E 'image: lab-ops|build:|max-size'
# image: lab-ops.lab.local:5000/factura-api:1.0   (pas de build:)
docker compose -f compose.yaml -f compose.prod.yaml up -d   # prod
```

**7. Mettre à jour `app` seule**

```bash
sed -i 's/service="factura-api"/service="factura-api v2"/' ../api/app.py
docker compose up -d --build --no-deps app
docker compose ps --format 'table {{.Name}}\t{{.Status}}'
# app : Up 5 seconds ; db, cache : Up 20 minutes ; proxy : inchangé
curl -s http://127.0.0.1:8080/ | jq .service                # "factura-api v2"
```

**8. Redémarrage et rapport**

```bash
sudo reboot
# après reconnexion
docker compose -f ~/lab18/compose/compose.yaml ps        # tout est Up
```

`compose.md` : `stop` arrête et conserve ; `down` supprime conteneurs et
réseau ; `down -v` supprime aussi `pg-data` et `app-data` (données perdues) ;
la pile est revenue parce que `docker.service` est activé et que chaque
service porte `restart: unless-stopped`.

::: pourquoi
Les briques qui font qu'un `up` « marche du premier coup » : les
**healthchecks** (le service dit lui-même quand il est prêt), `depends_on`
avec `condition: service_healthy` (Compose attend ce signal), le **DNS du
réseau de projet** (`db`, `cache`, `app` sont des noms), et les **secrets**
montés en fichiers (l'image `postgres` sait lire `*_FILE`, l'application
aussi). Le fichier de secret est en `0444` dans un répertoire `0700` : sur
l'hôte, seul `mathieu` y accède ; dans les conteneurs, seul le fichier est
monté, lisible par l'UID 70 de `db` et l'UID 10001 d'`app`. Le `!reset` du
fichier prod retire la clé `build:` héritée, sans quoi un `up` sur une
machine où l'image manque **construirait** au lieu de tirer du registre.
:::

::: piege
`pg_isready` sans `-h 127.0.0.1` passe par le socket Unix et répond « prêt »
pendant la phase d'initialisation, où PostgreSQL tourne un instant sans
TCP : `app` démarrerait trop tôt. `mem_limit` est la syntaxe Compose v2 hors
Swarm ; `deploy.resources.limits.memory` fonctionne aussi depuis Compose
2.20. Et `docker compose down` sur le fichier prod sans `-f` identique
laisse des conteneurs orphelins : toujours les mêmes `-f` pour `up` et
`down`, ou `COMPOSE_FILE=compose.yaml:compose.prod.yaml` dans `.env`.
:::

---

### **L18.5** — *Un registre privé sur `lab-ops`.*

**1. En clair**

```bash
grep -q lab-ops.lab.local /etc/hosts \
  || echo '10.10.10.14 lab-ops.lab.local lab-ops' | sudo tee -a /etc/hosts
docker run -d --name registre -p 5000:5000 --restart unless-stopped \
  -v registre-data:/var/lib/registry registry:2.8
docker tag factura-api:1.0 lab-ops.lab.local:5000/factura-api:1.0
docker push lab-ops.lab.local:5000/factura-api:1.0
curl -s http://lab-ops.lab.local:5000/v2/_catalog
# {"repositories":["factura-api"]}
curl -s http://lab-ops.lab.local:5000/v2/factura-api/tags/list
# {"name":"factura-api","tags":["1.0"]}
```

Le `push` passe parce que L18.1 a inscrit `lab-ops.lab.local:5000` dans
`insecure-registries` (`daemon.json`) : sans cela, le client exige HTTPS et
échoue avec `http: server gave HTTP response to HTTPS client`. Le registre
lui-même n'exige rien par défaut : `registry:2` répond à tout le monde.

**2. Depuis `lab-adm`**

```bash
echo '10.10.10.14 lab-ops.lab.local' | sudo tee -a /etc/hosts
curl -s http://lab-ops.lab.local:5000/v2/_catalog     # même réponse
```

`curl` accepte l'HTTP ; un démon Docker d'une autre machine refuserait tant
que **son** `daemon.json` ne déclare pas ce registre en `insecure` — et un
registre en clair, joignable par tout le réseau, permet à n'importe qui de
pousser une image piégée sous le nom `factura-api:1.0`.

**3. TLS et authentification**

```bash
cd ~/lab18/registre && mkdir -p certs auth
openssl req -x509 -newkey rsa:4096 -nodes -sha256 -days 365 \
  -subj "/CN=lab-ops.lab.local" \
  -addext "subjectAltName=DNS:lab-ops.lab.local,IP:10.10.10.14" \
  -keyout certs/domain.key -out certs/domain.crt
htpasswd -Bbn ci 'Registre-2024' > auth/htpasswd
docker rm -f registre
docker run -d --name registre -p 5000:5000 --restart unless-stopped \
  -v registre-data:/var/lib/registry \
  -v "$PWD/certs":/certs:ro -v "$PWD/auth":/auth:ro \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
  -e REGISTRY_AUTH=htpasswd \
  -e REGISTRY_AUTH_HTPASSWD_REALM="Registre factura" \
  -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
  -e REGISTRY_STORAGE_DELETE_ENABLED=true \
  registry:2.8
curl -sk -o /dev/null -w '%{http_code}\n' https://lab-ops.lab.local:5000/v2/
# 401
sudo sed -i '/insecure-registries/d' /etc/docker/daemon.json
# (et retirer la virgule finale de la ligne précédente)
jq . /etc/docker/daemon.json && sudo systemctl restart docker
```

**4. Confiance côté client Docker et `docker login`**

```bash
sudo mkdir -p /etc/docker/certs.d/lab-ops.lab.local:5000
sudo cp certs/domain.crt /etc/docker/certs.d/lab-ops.lab.local:5000/ca.crt
docker login lab-ops.lab.local:5000 -u ci
# Password:  → Login Succeeded
docker push lab-ops.lab.local:5000/factura-api:1.0
jq . ~/.docker/config.json
# { "auths": { "lab-ops.lab.local:5000": {
#     "auth": "Y2k6UmVnaXN0cmUtMjAyNA==" } } }
echo Y2k6UmVnaXN0cmUtMjAyNA== | base64 -d      # ci:Registre-2024
```

Les identifiants sont en **base64, pas chiffrés**, dans un fichier `0600` :
sur un serveur, on utilise un compte de registre dédié aux droits limités,
ou un *credential helper* (`pass`, `secretservice`).

**5. Clients distants**

```bash
# lab-adm
scp mathieu@10.10.10.14:lab18/registre/certs/domain.crt .
curl --cacert domain.crt -u ci:Registre-2024 \
  https://lab-ops.lab.local:5000/v2/_catalog
# lab-rhel
sudo mkdir -p /etc/containers/certs.d/lab-ops.lab.local:5000
sudo cp domain.crt /etc/containers/certs.d/lab-ops.lab.local:5000/ca.crt
podman login lab-ops.lab.local:5000 -u ci
podman pull lab-ops.lab.local:5000/factura-api:1.0
podman run -d --name api -p 8000:8000 lab-ops.lab.local:5000/factura-api:1.0
curl -s http://127.0.0.1:8000/sante
```

**6. Suppression et ramasse-miettes**

```bash
URL=https://lab-ops.lab.local:5000/v2/factura-api
DIGEST=$(curl -sI --cacert certs/domain.crt -u ci:Registre-2024 \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
  "$URL/manifests/1.0" \
  | awk 'tolower($1)=="docker-content-digest:" {print $2}' | tr -d '\r')
curl -s -o /dev/null -w '%{http_code}\n' --cacert certs/domain.crt \
  -u ci:Registre-2024 -X DELETE "$URL/manifests/$DIGEST"      # 202
docker exec registre registry garbage-collect --delete-untagged \
  /etc/docker/registry/config.yml
```

`registre.md` doit lister : chemins (`certs/`, `auth/`, volume
`registre-data`, `/etc/docker/certs.d/…`), rotation du mot de passe
(`htpasswd -Bb auth/htpasswd ci 'nouveau'` puis `docker restart registre`,
puis `docker login` sur chaque client), et ce qui manque pour la production :
certificat signé par une AC interne (pas d'autosigné à distribuer), un compte
par usage (lecture seule pour les serveurs, écriture pour la CI),
sauvegarde du volume, `registry:2` derrière un reverse proxy avec
journalisation, scan des images poussées, rétention (`garbage-collect`
planifié), et un vrai serveur d'identités (jeton, `REGISTRY_AUTH=token`)
au-delà de quelques comptes.

::: pourquoi
Un registre est un serveur HTTP qui stocke des *blobs* adressés par
digest et des manifestes ; `push` envoie les couches manquantes, `pull` les
récupère. Le client Docker impose TLS par défaut parce que l'image est du
code exécuté en root sur tes machines : un registre en clair, c'est du code
non authentifié. Le répertoire `/etc/docker/certs.d/<hôte:port>/` permet de
faire confiance à une AC **pour ce registre seulement**, sans toucher au
magasin système, ce qui limite la portée d'un certificat autosigné. La
suppression par l'API ne retire que le manifeste ; les blobs restent jusqu'au
`garbage-collect`, qui doit tourner registre arrêté ou en lecture seule
(`REGISTRY_STORAGE_MAINTENANCE_READONLY_ENABLED=true`) pour ne pas
corrompre un push concurrent.
:::

::: piege
Le SAN est obligatoire : un certificat avec seulement `CN=` est refusé par
Docker et Podman (`x509: certificate relies on legacy Common Name field`).
Et `htpasswd` doit être en **bcrypt** (`-B`) : le registre ignore les
entrées MD5/SHA et répond `401` sans explication.
:::

---

## 18.7 Break & Fix

### **BF18.1** — *L'API legacy redémarre toute seule et met 10 s à s'arrêter.*

**Démarche de diagnostic**

```bash
docker ps -a --filter name=factura-legacy
# STATUS: Restarting (0) 3 seconds ago      ← code 0, pas un plantage
docker inspect factura-legacy --format \
  '{{.RestartCount}} {{.State.ExitCode}} {{.HostConfig.RestartPolicy.Name}}'
# 7 0 always
docker logs --tail 12 factura-legacy
# [start] lancement de l'API
# [start] API lancee, pid 7
# [factura-api] demarrage version=dev sur 0.0.0.0:8000 pid=7 uid=0
# [start] verification 1 : OK
# …
# [start] verification 6 : OK
# [start] surveillance terminee, tout est en ordre
docker inspect factura-legacy --format '{{.Config.Entrypoint}} {{.Config.Cmd}}'
# [] [/bin/sh -c sh /app/start.sh]
docker top factura-legacy
# PID   CMD
# 8123  sh /app/start.sh          ← PID 1 du conteneur
# 8150  python3 /app/app.py
# 8402  sleep 5
```

Trois indices convergent : le conteneur sort en `0` après ~30 s (six
vérifications de 5 s), la commande est en **forme shell**, et le PID 1 est
`sh`. Lecture de `/opt/factura-docker/bf/01/start.sh` : l'API est lancée
avec `&`, le script fait sa surveillance, puis **atteint sa fin**. `sh`
(PID 1) sort en 0, le noyau tue tout le namespace — Python compris —, et
`--restart always` relance. Pendant les 30 s, `docker stop` envoie `SIGTERM`
à `sh`, qui l'ignore (PID 1 sans handler) et ne le relaie pas : 10 s puis
`SIGKILL`, code 137.

**Cause racine** : un script shell en PID 1 qui lance le service en
arrière-plan et se termine.

**Correctif** (dans `/opt/factura-docker/bf/01/`) :

```dockerfile
FROM python:3.12-slim-bookworm
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8000
ENTRYPOINT ["python3", "app.py"]
```

```bash
cd /opt/factura-docker/bf/01
sudo docker build -t factura-legacy:2.4 .
docker rm -f factura-legacy
docker run -d --name factura-legacy --restart always -p 8001:8000 \
  factura-legacy:2.4
sleep 60; docker ps --filter name=factura-legacy --format '{{.Status}}'
# Up About a minute
time docker stop factura-legacy                  # 0,3 s
docker inspect factura-legacy --format '{{.State.ExitCode}}'   # 0
```

Deux autres façons sans réécrire le script :

* garder `start.sh` mais le **terminer par `exec python3 /app/app.py`** au
  lieu de `&` + boucle : le shell se remplace par Python, qui devient PID 1
  et reçoit les signaux (la surveillance de démarrage est le rôle d'un
  `HEALTHCHECK`, pas d'un script) ;
* ne pas toucher à l'image et contourner au lancement :
  `docker run --entrypoint python3 … factura-legacy:2.3 app.py` (ou
  `entrypoint:` en Compose). Utile en urgence, à documenter comme dette.

**Prévention** : forme exec obligatoire dans les revues de Dockerfile ;
`docker top` et `docker inspect` du PID 1 avant toute mise en production ;
un `HEALTHCHECK` plutôt qu'une boucle maison ; `--init` quand on ne maîtrise
pas le programme.

::: pourquoi
`Restarting (0)` est le point d'entrée : un code 0 en boucle n'est jamais un
crash, c'est un processus principal qui **finit** son travail. Le second
indice est le temps d'arrêt de 10 s, signature d'un PID 1 sourd. Les deux
symptômes n'ont qu'une cause parce que dans un conteneur, la vie du
processus principal **est** la vie du conteneur : pas de superviseur, pas de
« service en arrière-plan ». Tout ce que fait `&` dans un script PID 1,
c'est créer un orphelin condamné.
:::

::: piege
`--restart no` supprime le symptôme visible et laisse une API qui meurt
toutes les 30 secondes. `docker kill` comme procédure d'arrêt masque le
137 et interdit tout arrêt propre (connexions coupées, fichiers non
vidés). Enfin, `--init` seul **ne suffit pas** ici : tini relaierait bien
`SIGTERM`, mais le script sortirait toujours en 0 au bout de 30 s.
:::

---

### **BF18.2** — */visites renvoie une erreur 500 depuis la migration.*

**Démarche de diagnostic**

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8002/visites  # 500
docker logs factura-migration 2>&1 | grep -B2 -m1 PermissionError
# File "/app/app.py", line 106, in visites
#   with open(chemin, "a", encoding="utf-8") as f:
# PermissionError: [Errno 13] Permission denied: '/data/visites.log'
docker inspect factura-migration --format '{{.Config.User}} \
{{range .Mounts}}{{.Type}} {{.Source}}->{{.Destination}}{{end}}'
# 10001:10001 bind /srv/factura-docker/data->/data
docker exec factura-migration id
# uid=10001 gid=10001 groups=10001
ls -ldn /srv/factura-docker/data
# drwxr-xr-x 2 0 0 4096 … /srv/factura-docker/data
```

**Cause racine** : le conteneur écrit avec l'UID 10001 (`--user`), le
répertoire hôte appartient à l'UID 0 en `0755` : seul root peut y créer un
fichier. La « migration » a recréé le répertoire avec les droits par défaut
et perdu le `chown` fait à l'époque.

**Correctif** (côté hôte, sans toucher au conteneur) :

```bash
sudo chown 10001:root /srv/factura-docker/data
sudo chmod 0750 /srv/factura-docker/data
curl -s http://127.0.0.1:8002/visites
# {"fichier":"/data/visites.log","visites":1}
ls -ln /srv/factura-docker/data/visites.log
# -rw-r--r-- 1 10001 10001 …
```

Un bind mount est un pointeur vers l'inode hôte : le changement de droits
est vu immédiatement par le processus, sans redémarrage.

**Prévention** : documenter l'UID de chaque image dans le runbook ;
préparer les répertoires hôte dans le script de déploiement (`install -d
-o 10001 -g root -m 0750 …`) ; préférer un volume nommé quand rien n'oblige
à un chemin hôte.

::: pourquoi
Un volume nommé n'aurait pas eu ce problème parce qu'à sa création Docker
y copie le contenu de `/data` de l'image **avec son propriétaire** — et si
le répertoire n'existe pas dans l'image, il le crée en root, mais un `chown
app:app /data` dans le Dockerfile règle ce cas une fois pour toutes, sur
toutes les machines. Le bind mount, lui, dépend de l'hôte, donc de chaque
machine, donc de chaque migration.
:::

::: piege
`chmod 777` marche et c'est le réflexe interdit : tout processus de l'hôte,
tout autre conteneur avec le même bind mount, peut alors écrire et lire les
données. `--privileged` ne change rien aux droits POSIX. Et lancer le
conteneur en root déplace le problème : les fichiers créés appartiendront à
root, et un compromis de l'application donne root sur le montage.
:::

---

### **BF18.3** — *Le port est publié mais personne n'y accède.*

**Démarche de diagnostic**

```bash
docker port factura-public                  # 8000/tcp -> 0.0.0.0:8003
ss -tlnp | grep 8003                        # docker-proxy écoute
curl -s http://127.0.0.1:8003/sante         # OK en local
# depuis lab-adm : curl -m 5 http://10.10.10.14:8003/sante → timeout
sudo ufw status                             # rien sur 8003
sudo iptables -t nat -S DOCKER | grep 8003  # la DNAT est là
# -A DOCKER ! -i docker0 -p tcp -m tcp --dport 8003 \
#   -j DNAT --to-destination 172.17.0.3:8000
sudo iptables -S DOCKER-USER
# -N DOCKER-USER
# -A DOCKER-USER -d 172.17.0.3/32 -p tcp -m tcp --dport 8000 -j DROP
# -A DOCKER-USER -j RETURN
sudo iptables -L DOCKER-USER -nv            # le compteur de la règle monte
```

Le timeout (et non un refus) oriente vers un `DROP`. La chaîne
`DOCKER-USER`, la seule que Docker laisse à l'administrateur, contient une
règle qui jette tout ce qui va vers l'IP du conteneur sur son port 8000 —
c'est-à-dire tout le trafic **après DNAT**.

**Cause racine** : une règle `DROP` « temporaire » dans `DOCKER-USER`,
jamais retirée ni documentée.

**Correctif** :

```bash
sudo iptables -D DOCKER-USER -d 172.17.0.3/32 -p tcp --dport 8000 -j DROP
# depuis lab-adm : curl http://10.10.10.14:8003/sante → {"statut":"ok"}
```

**Pourquoi le test local passait** : une connexion vers `127.0.0.1:8003`
est prise en charge par `docker-proxy` (processus utilisateur) ou par le NAT
de la chaîne `OUTPUT` ; dans les deux cas le trafic vers le conteneur part
**de l'hôte** et passe par `OUTPUT`, pas par `FORWARD`. `DOCKER-USER` n'est
appelée que depuis `FORWARD`, donc uniquement pour les paquets qui
traversent la machine — ceux de `lab-adm`.

**Prévention** : toute règle `DOCKER-USER` vit dans un fichier versionné
(`/etc/iptables/rules.v4` avec `iptables-persistent`, ou une unité
`docker-user-rules.service` avec `After=docker.service`), avec un
commentaire `-m comment --comment "ticket-1234"` ; revue des règles à chaque
incident réseau (`iptables -S DOCKER-USER` fait partie des cinq commandes du
runbook).

::: pourquoi
La distinction `INPUT`/`FORWARD` est tout le sujet. Un port publié est un
**NAT** : pour le noyau, l'hôte n'est pas la destination, il route. Les
outils qui raisonnent « service local » (`ufw status`, `ss -tlnp`, `curl
localhost`) répondent tous « c'est ouvert » et ont raison de leur point de
vue. Seul le chemin `PREROUTING → FORWARD → DOCKER-USER` explique ce que
voit un client distant. `iptables -L -nv` avec ses compteurs de paquets est
la preuve : la règle `DROP` compte exactement les tentatives de `lab-adm`.
:::

::: piege
`iptables -F` viderait aussi les chaînes de Docker : plus aucune
publication de port ne fonctionnerait jusqu'à un `systemctl restart docker`
— et l'interdit de l'énoncé est là pour ça. Redémarrer Docker aurait fait
disparaître le symptôme (la règle n'est pas persistée) sans qu'on comprenne
rien, et elle serait revenue au prochain « `iptables` de l'ancien collègue ».
:::

---

### **BF18.4** — *Plus rien ne se lance : no space left on device.*

**Démarche de diagnostic**

```bash
df -h /
# /dev/sda2   39G   39G     0  100% /
sudo du -xsh /var/lib/docker/* 2>/dev/null | sort -h | tail -3
# 1.1G  /var/lib/docker/image
# 36G   /var/lib/docker/overlay2
docker system df
# TYPE           TOTAL  ACTIVE  SIZE     RECLAIMABLE
# Images         7      4       1.4GB    412MB (29%)
# Containers     6      5       35.2GB   0B (0%)     ← les conteneurs !
# Local Volumes  4      3       48MB     0B
docker ps -as --format 'table {{.Names}}\t{{.Status}}\t{{.Size}}'
# factura-export   Up 20 minutes   35.2GB (virtual 35.3GB)
docker inspect factura-export --format '{{.Path}} {{.Args}}'
# sleep [infinity]
docker exec factura-export sh -c 'du -xsh /var/tmp/* 2>/dev/null'
# 35.2G  /var/tmp/export-clients-202609.bin
```

`docker system df` sépare images, conteneurs et volumes : ici ce sont les
**conteneurs** (leurs couches d'écriture) qui pèsent, et `docker ps -s`
désigne le coupable. La colonne `SIZE` de `ps -s` est la taille de la couche
d'écriture (ce que le conteneur a écrit par-dessus l'image).

**Cause racine** : un conteneur qui écrit un export de 35 Go dans sa couche
d'écriture (`/var/tmp`), invisible pour `du` sur `/home` ou `/srv`, sans
aucune limite.

**Correctif** (par Docker, pas à la main sous `/var/lib/docker`) :

```bash
docker exec factura-export rm /var/tmp/export-clients-202609.bin
# ou, si le conteneur est jetable :
docker rm -f factura-export
df -h /                                   # 4 % utilisé
docker run --rm alpine:3.20 true          # fonctionne à nouveau
```

**Prévention** :

* les exports et gros fichiers vont dans un **volume** ou un bind mount sur
  un système de fichiers dédié, jamais dans la couche d'écriture ;
* `--storage-opt size=10G` (overlay2 sur XFS avec quotas) ou, plus
  simplement, `/var/lib/docker` sur un volume logique séparé (module 10)
  pour que le remplissage ne bloque pas la racine ;
* surveillance : alerte à 80 % sur `/var/lib/docker` (module 13),
  `docker system df` dans le check hebdomadaire, rotation `json-file`
  globale (déjà en place ici : ce n'étaient pas les journaux).

::: pourquoi
La couche d'écriture d'un conteneur est un répertoire overlay2 sous
`/var/lib/docker/overlay2/<id>/diff` : `du` sur les emplacements habituels
ne la voit pas, et `docker images` ne la compte pas (elle n'appartient à
aucune image). Il faut les outils Docker (`system df`, `ps -s`) pour la
mesurer. Supprimer le fichier depuis le conteneur ou détruire le conteneur
libère l'espace immédiatement ; supprimer un fichier directement sous
`/var/lib/docker` désynchronise le démon et peut corrompre le stockage.
:::

::: piege
`docker system prune -a` aurait libéré des images et le cache de build,
peut-être assez pour repartir quelques heures, sans toucher au conteneur
**actif** qui remplit le disque : le symptôme serait revenu, avec en prime
des images de production à retélécharger. Le `prune` n'est pas un outil de
diagnostic, c'est un nettoyage qu'on fait quand on sait ce qu'on supprime.
:::

---

### **BF18.5** — *L'API ne trouve plus Redis.*

**Démarche de diagnostic**

```bash
docker logs factura-app 2>&1 | grep -m1 -iE 'not known|gaierror'
# redis.exceptions.ConnectionError: Error -2 connecting to
# factura-cache:6379. Name or service not known.
docker exec factura-app getent hosts factura-cache      # rien
docker exec factura-app cat /etc/resolv.conf
# nameserver 10.10.10.1          ← le DNS de l'hôte, pas 127.0.0.11
docker inspect factura-app factura-cache --format '{{.Name}} \
{{range $k, $v := .NetworkSettings.Networks}}{{$k}}={{$v.IPAddress}} {{end}}'
# /factura-app bridge=172.17.0.4
# /factura-cache bridge=172.17.0.3
docker exec factura-app python3 -c \
  "import socket; socket.create_connection(('172.17.0.3', 6379), 2); \
print('ok')"
# ok
```

**Cause racine** : les deux conteneurs sont sur le réseau `bridge` **par
défaut**, qui n'a pas de serveur DNS intégré. La connectivité IP existe, la
résolution de nom n'existe pas (Q18.7).

**Correctif sans recréer les conteneurs** :

```bash
docker network create factura-bf-net
docker network connect factura-bf-net factura-cache
docker network connect factura-bf-net factura-app
docker exec factura-app cat /etc/resolv.conf     # nameserver 127.0.0.11
docker exec factura-app getent hosts factura-cache
# 172.19.0.2   factura-cache
curl -s http://127.0.0.1:8005/compteur           # {"compteur":1}
```

`docker network connect` ajoute une interface au conteneur **à chaud** et
réécrit son `/etc/resolv.conf` vers le résolveur intégré. L'application
n'a pas besoin de redémarrer : elle ouvre une connexion Redis à chaque
requête.

**Comment il fallait les lancer** : `docker network create factura-net`
puis `--network factura-net` sur les deux `run` (ou un `compose.yaml`, qui
crée un réseau de projet d'office). Optionnellement, `docker network
disconnect bridge factura-app` pour ne pas rester sur deux réseaux.

::: pourquoi
Le bridge par défaut date d'avant le DNS intégré : Docker y a gardé le
comportement historique (`/etc/hosts` statique, `--link` déprécié) pour ne
rien casser. Tout réseau créé par l'utilisateur active le résolveur
`127.0.0.11`, qui répond pour les conteneurs **du même réseau**. Le
diagnostic tient en une commande : `cat /etc/resolv.conf` dans le conteneur.
`10.10.10.1` = bridge par défaut, `127.0.0.11` = réseau utilisateur.
:::

::: piege
`--link factura-cache:factura-cache` aurait fonctionné et c'est pour ça
qu'il est interdit : déprécié, unidirectionnel, et cassé dès que la cible
est recréée (nouvelle IP, `/etc/hosts` obsolète). L'IP en dur dans
`REDIS_URL` tient jusqu'au prochain redémarrage de la machine, où l'ordre
de démarrage change les adresses. Et éditer `/etc/hosts` du conteneur ne
survit pas à un `docker restart` — le fichier est régénéré.
:::

---

## 18.8 Défi du module

**D18** — *Conteneuriser et livrer `factura-api` 2.0.*

**1. L'image** : le Dockerfile est celui du corrigé de L18.2 (multi-stage,
`base`/`debug`/`runtime`, UID 10001, `HEALTHCHECK`, labels, `ARG
APP_VERSION`). Un seul ajout pour le défi : `USER 10001:10001` en numérique
plutôt que `USER app`, pour que `docker inspect` et Kubernetes
(`runAsNonRoot`) puissent le vérifier sans lire `/etc/passwd` de l'image.

```bash
cd ~/lab18/api
docker build --pull --build-arg APP_VERSION=2.0 -t factura-api:2.0 .
docker image inspect factura-api:2.0 --format '{{.Config.User}} {{.Size}} \
{{index .Config.Labels "org.opencontainers.image.version"}}'
# 10001:10001 146800640 2.0
```

**2. La pile** : `compose.yaml` et `compose.prod.yaml` du corrigé de L18.4.
`compose.prod.yaml` retire le `build:` et pointe sur
`lab-ops.lab.local:5000/factura-api:${APP_VERSION}`. Pour ne plus dépendre
de `-f` à chaque commande, on peut ajouter à `.env` :

```text
APP_VERSION=2.0
COMPOSE_FILE=compose.yaml:compose.prod.yaml
```

**3. Le script** `~/lab18/bin/livrer.sh` :

```bash
#!/usr/bin/env bash
# livrer.sh — construit, scanne, contrôle, pousse et déploie factura-api
# usage : livrer.sh VERSION      (ex. livrer.sh 2.0)
set -euo pipefail

VERSION="${1:?usage: livrer.sh VERSION}"
REGISTRE=lab-ops.lab.local:5000
LOCALE="factura-api:$VERSION"
IMAGE="$REGISTRE/factura-api:$VERSION"
API="$HOME/lab18/api"
PILE="$HOME/lab18/compose"
JOURNAL="$HOME/lab18/rapports/livraisons.log"
TAILLE_MAX=$((150 * 1024 * 1024))
DIGEST=""

log()     { printf '[livrer] %s\n' "$*"; }
journal() {
  printf '%s version=%s digest=%s resultat=%s\n' "$(date +%FT%T)" \
    "$VERSION" "${DIGEST:-aucun}" "$1" >> "$JOURNAL"
}
trap 'rc=$?; [ "$rc" -eq 0 ] || journal "ECHEC (code $rc)"' EXIT

log "1/6 construction de $LOCALE"
docker build --pull --build-arg APP_VERSION="$VERSION" \
  -t "$LOCALE" "$API"

log "2/6 scan Trivy (CRITICAL corrigeables = refus)"
trivy image --quiet --severity CRITICAL --ignore-unfixed \
  --exit-code 1 "$LOCALE"

log "3/6 contrôles de l'image"
TAILLE=$(docker image inspect "$LOCALE" --format '{{.Size}}')
USAGER=$(docker image inspect "$LOCALE" --format '{{.Config.User}}')
if [ "$TAILLE" -ge "$TAILLE_MAX" ]; then
  log "refus : image de $((TAILLE / 1024 / 1024)) Mio (max 150)"; exit 1
fi
case "$USAGER" in
  ""|root|0|0:0) log "refus : l'image tourne en root"; exit 1 ;;
esac
log "   taille $((TAILLE / 1024 / 1024)) Mio, utilisateur $USAGER"

log "4/6 publication dans $REGISTRE"
docker tag "$LOCALE" "$IMAGE"
docker push --quiet "$IMAGE"
DIGEST=$(docker image inspect "$IMAGE" \
  --format '{{range .RepoDigests}}{{.}} {{end}}' \
  | tr ' ' '\n' | grep "^$REGISTRE/" | head -1 | cut -d@ -f2)

log "5/6 déploiement de la pile"
cd "$PILE"
APP_VERSION="$VERSION" docker compose -f compose.yaml -f compose.prod.yaml \
  up -d --pull always --wait

log "6/6 vérification"
OBTENUE=$(curl -fsS --max-time 5 http://127.0.0.1:8080/version \
  | jq -r .version)
if [ "$OBTENUE" != "$VERSION" ]; then
  log "refus : /version répond $OBTENUE au lieu de $VERSION"; exit 1
fi
sed -i "s/^APP_VERSION=.*/APP_VERSION=$VERSION/" .env
journal OK
log "livraison $VERSION terminée ($DIGEST)"
```

```bash
chmod 0755 ~/lab18/bin/livrer.sh
~/lab18/bin/livrer.sh 2.0
# [livrer] 1/6 construction de factura-api:2.0
# …
# [livrer] livraison 2.0 terminée (sha256:8c1e…)
sed -i 's/service="factura-api"/service="factura-api 2.1"/' ~/lab18/api/app.py
~/lab18/bin/livrer.sh 2.1
cat ~/lab18/rapports/livraisons.log
# 2026-09-19T15:02:11 version=2.0 digest=sha256:8c1e… resultat=OK
# 2026-09-19T15:09:47 version=2.1 digest=sha256:0b77… resultat=OK
```

**4. Le runbook** (`~/lab18/rapports/runbook-docker.md`, extrait des
sections obligatoires) :

```text
# Runbook factura-api (Docker / Compose sur lab-ops)

## Démarrer / arrêter
cd ~/lab18/compose            (COMPOSE_FILE est dans .env)
docker compose up -d --wait   |  docker compose stop  |  docker compose down
Jamais « down -v » sans sauvegarde : il détruit pg-data.

## Mettre à jour un seul service
docker compose pull app && docker compose up -d --no-deps app

## Revenir à la version précédente (< 5 lignes)
APP_VERSION=2.0 docker compose up -d --pull always --wait app
curl -s http://127.0.0.1:8080/version        # {"version":"2.0"}
sed -i 's/^APP_VERSION=.*/APP_VERSION=2.0/' .env
(l'image 2.0 est toujours dans le registre : pas de rebuild)

## Sauvegarder / restaurer pg-data
docker compose exec db pg_dump -U factura factura > factura-$(date +%F).sql
docker compose exec -T db psql -U factura factura < factura-2026-09-19.sql
(à froid : docker run --rm -v factura_pg-data:/from:ro -v $PWD:/to \
 alpine:3.20 tar czf /to/pg-data.tgz -C /from .)

## Un conteneur ne démarre pas : les cinq commandes
1. docker compose ps -a                      état et code de sortie
2. docker compose logs --tail 100 SERVICE    trace applicative
3. docker inspect --format '{{.State.ExitCode}} {{.State.OOMKilled}} \
   {{.State.Error}}' CONTENEUR               137 ? OOM ? erreur démon ?
4. docker compose config                     ce que Compose exécute vraiment
5. sudo iptables -S DOCKER-USER ; df -h /var/lib/docker   réseau, disque

## Codes de sortie
0 fin normale | 1 erreur applicative | 125 démon | 126/127 commande
137 SIGKILL (OOM, kill, stop expiré) | 139 SIGSEGV | 143 SIGTERM non géré

## /var/lib/docker plein
docker system df ; docker ps -as ; du -xsh /var/lib/docker/* ;
supprimer PAR DOCKER (rm du fichier dans le conteneur, docker rm, builder
prune, image prune) ; jamais rm sous /var/lib/docker ; ensuite corriger la
cause (volume dédié, rotation, --storage-opt).

## Interdit dans un docker run sur cette machine
- -v /var/run/docker.sock : root sur l'hôte pour le conteneur
- --privileged : toutes les capabilities et les périphériques
- --pid host / --network host sans ticket : voit ou touche tout l'hôte
- image :latest ou sans tag : non reproductible, rollback impossible
- pas de --memory : un conteneur peut mettre lab-ops en OOM
- root dans l'image (pas de USER) : évasion = root sur les montages
```

**5. La preuve** : sortie de `livrer.sh 2.0` puis `2.1`, et retour à 2.0
exécuté, collés dans le runbook.

::: pourquoi
La chaîne du défi est celle d'un pipeline de livraison (module 21), écrite
à la main pour en comprendre chaque maillon : **construire** de façon
reproductible (version en argument, base épinglée, `--pull`), **refuser**
avant de livrer (scan bloquant, taille, non-root — lus dans l'image, pas
dans le Dockerfile, parce que c'est l'image qui part en production),
**publier** dans un registre dont on connaît le digest, **déployer** depuis
ce registre avec attente de santé, **vérifier** de l'extérieur, et
**journaliser** avec le digest pour pouvoir dire, plus tard, exactement ce
qui tournait. Le rollback est trivial parce que la 2.0 existe encore dans le
registre et que le seul paramètre est `APP_VERSION`.
:::

::: piege
`trivy --exit-code 1` sans `--ignore-unfixed` bloque la livraison sur des
CVE que personne ne peut corriger : le pipeline devient rouge en permanence
et on finit par le désactiver. L'inverse (ignorer tout) est pire. Le
compromis du script — bloquer sur `CRITICAL` corrigeable, journaliser le
reste — est un point de départ, à durcir avec `HIGH` quand les images sont
propres. Deuxième piège : `up -d` sans `--pull always` réutilise l'image
locale taguée `2.0` même si le registre en a une autre ; le tag n'est pas
une garantie, le digest oui.
:::
