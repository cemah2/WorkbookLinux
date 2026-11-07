<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Partie III — Exploitation, sécurité et incidents › **Module 15** · corrigé  
[← Module 14](../14-ssh/corrige.md) · [Énoncé](README.md) · [Module 16 →](../16-logs-monitoring/corrige.md)

> [!TIP]
> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, pas avant. Chaque identifiant renvoie à son énoncé.
<!-- nav:fin -->

# Module 15 — Corrigé

## 15.3 Quiz — QCM

<a id="q15-1"></a>**[Q15.1](README.md#q15-1)** — *`location /api/` puis `location ~* \.(json|js|css)$` ; requête `GET /api/invoices.json`.*

**Réponse : c)** la regex gagne, nginx cherche un fichier sur disque et
répond 404.

> [!NOTE]
> **Pourquoi**
>
> L'algorithme de sélection ne lit pas le fichier de haut en bas en s'arrêtant
> au premier bloc qui « ressemble ». Il se déroule en deux temps :
>
> 1. nginx compare l'URI à **tous les préfixes** (`location /api/`, `location
>    /`, etc.) et retient le plus long : ici `/api/`. Si ce préfixe était
>    marqué `=` (exact) ou `^~`, la recherche s'arrêterait là.
> 2. Comme ce n'est pas le cas, nginx teste ensuite **toutes les regex dans
>    l'ordre du fichier**, et la première qui correspond l'emporte sur le
>    préfixe retenu. `\.(json|js|css)$` correspond à `/api/invoices.json`.
>
> Le bloc regex n'a pas de `proxy_pass` : il sert des fichiers depuis `root`,
> donc nginx tente d'ouvrir `/srv/www/factura-demo/api/invoices.json`, qui
> n'existe pas, et journalise `open() "..." failed (2: No such file or
> directory)`. La position de la regex dans le fichier (avant ou après
> `/api/`) ne change rien : une regex bat toujours un préfixe simple.
>
> Deux corrections propres : marquer la location API `^~ /api/` (le préfixe
> gagne et les regex ne sont plus consultées), ou exclure `/api/` de la regex
> avec une assertion négative `~* ^(?!/api/).*\.(json|js|css)$`. La première
> est plus lisible et plus robuste : elle protège aussi contre la prochaine
> regex qu'un collègue ajoutera.

> [!WARNING]
> **Piège**
>
> a) et b) reposent sur l'idée qu'un préfixe plus long ou placé en premier
> gagne : c'est vrai **entre préfixes**, faux face à une regex. d) nginx ne
> détecte jamais de recouvrement : des locations qui se chevauchent sont la
> norme. Le piège de production associé : `/api/health` continue de répondre
> 200 (pas de suffixe `.json`), donc la supervision reste verte pendant que
> l'application est cassée. C'est BF15.1.

---

<a id="q15-2"></a>**[Q15.2](README.md#q15-2)** — *`proxy_pass http://127.0.0.1:8001/;` dans `location /api/`, requête `/api/health?x=1`.*

**Réponse : b)** le backend reçoit `GET /health?x=1`.

> [!NOTE]
> **Pourquoi**
>
> La règle tient en une phrase : si `proxy_pass` contient une URI (ne serait-ce
> que `/`), nginx **remplace la partie de l'URI qui a correspondu à la
> location** par cette URI. La location est `/api/`, l'URI de `proxy_pass` est
> `/`, donc `/api/health` devient `/health`. La chaîne de requête (`?x=1`) est
> toujours conservée, elle n'entre pas dans le calcul.
>
> Sans URI (`proxy_pass http://127.0.0.1:8001;`), l'URI cliente est transmise
> telle quelle : le backend reçoit `/api/health?x=1`. C'est ce qu'il faut
> quand l'application connaît son préfixe (Flask avec un blueprint `/api`),
> et l'autre forme quand elle ne le connaît pas (elle expose `/health` à la
> racine et nginx la « monte » sous `/api/`).
>
> Deux limites à connaître : dans une location **regex**, `proxy_pass` avec
> URI est refusé (`"proxy_pass" cannot have URI part in location given by
> regular expression`), parce que nginx ne saurait pas quelle partie
> remplacer ; et si `proxy_pass` utilise des variables, aucune substitution
> n'est faite du tout.

> [!WARNING]
> **Piège**
>
> c) : les paramètres ne sont jamais perdus par `proxy_pass`. d) : nginx ne
> produit pas de double barre ici ; il en produirait avec `location /api` (sans
> barre finale) et `proxy_pass .../` : la partie `/api` est remplacée par `/` et
> `/api/health` devient `//health`. La cohérence des barres finales entre `location`
> et `proxy_pass` est le premier réflexe quand un backend reçoit un chemin
> inattendu : `/api/whoami` du setup te montre exactement ce qu'il reçoit.

---

<a id="q15-3"></a>**[Q15.3](README.md#q15-3)** — *`location /static/ { root /srv/www/factura-demo/static/; }` et `GET /static/app.js`.*

**Réponse : b)** `/srv/www/factura-demo/static/static/app.js`.

> [!NOTE]
> **Pourquoi**
>
> `root` définit un répertoire de base et nginx y **concatène l'URI
> complète** : chemin = `root` + URI. C'est la bonne directive quand
> l'arborescence disque reflète l'arborescence des URI (`/static/app.js` se
> trouve dans `<root>/static/app.js`).
>
> `alias` remplace la partie de l'URI qui correspond à la location par le
> chemin donné : avec `location /static/ { alias /srv/www/factura-demo/static/; }`,
> `/static/app.js` devient `/srv/www/factura-demo/static/` + `app.js`. C'est la
> directive à utiliser quand l'URI et le disque ne coïncident pas (`/docs/`
> servi depuis `/srv/www/factura-demo/docs/` en E15.4, ou `/media/` servi
> depuis `/var/lib/app/uploads/`).
>
> Deux règles pratiques : la barre finale doit être présente des deux côtés
> (`location /static/` et `alias .../static/`), sinon nginx colle les chaînes
> sans séparateur ; et `alias` dans une location regex utilise les captures
> (`alias /srv/$1;`). Dans 90 % des cas, un `root` posé **au niveau du
> server** suffit et aucune location statique n'a besoin de le répéter.

> [!WARNING]
> **Piège**
>
> Le 404 obtenu avec `root` mal placé est silencieux dans `access.log` ; c'est
> `error.log` qui donne le chemin réellement tenté : `open()
> "/srv/www/factura-demo/static/static/app.js" failed (2: No such file or
> directory)`. Lire ce chemin tel quel résout la quasi-totalité des 404
> statiques.

---

<a id="q15-4"></a>**[Q15.4](README.md#q15-4)** — *`systemctl reload nginx` avec une configuration invalide.*

**Réponse : b)** le maître refuse la nouvelle conf, garde l'ancienne, les
workers continuent.

> [!NOTE]
> **Pourquoi**
>
> `systemctl reload nginx` envoie `SIGHUP` au processus maître (`ExecReload=
> /usr/sbin/nginx -g 'daemon on; master_process on;' -s reload` dans l'unité
> Ubuntu). Le maître **relit et valide** la configuration complète en mémoire.
> Si elle est valide : il ouvre les nouvelles sockets d'écoute si nécessaire,
> lance de nouveaux workers avec la nouvelle conf, puis demande aux anciens
> de s'arrêter **gracieusement** — ils cessent d'accepter des connexions et
> terminent les requêtes en cours. Aucune requête n'est perdue.
>
> Si elle est invalide : le maître journalise l'erreur dans `error.log`
> (`[emerg] ... in /etc/nginx/sites-enabled/factura-demo:42`), et **continue
> avec l'ancienne configuration**. Les workers ne sont pas touchés. Le site
> reste servi, mais avec la conf d'avant : c'est le piège — tu crois avoir
> appliqué ton changement.
>
> D'où l'enchaînement obligatoire `sudo nginx -t && sudo systemctl reload
> nginx` : `-t` fait exactement la même validation, mais **te** l'affiche.
> `restart` n'est nécessaire que pour ce que le reload ne sait pas changer :
> `user`, modules dynamiques, changement de binaire (qui se fait
> à chaud par le signal `USR2`, hors périmètre).

> [!WARNING]
> **Piège**
>
> Le vrai danger n'est pas le reload raté, c'est le **restart** raté : `systemctl
> restart nginx` avec une conf invalide arrête l'ancien nginx et n'en démarre
> pas de nouveau — site coupé. Et au prochain reboot, un nginx dont la conf
> est invalide ne démarre pas non plus. Règle : `nginx -t` avant toute
> action, et `reload` par défaut.

---

<a id="q15-5"></a>**[Q15.5](README.md#q15-5)** — *`connect() failed (111: Connection refused) while connecting to upstream ... :8003`.*

**Réponse : b)** 502 Bad Gateway, rien n'écoute sur 8003.

> [!NOTE]
> **Pourquoi**
>
> Le couple « code HTTP côté client / ligne dans `error.log` » est la grille de
> lecture du reverse proxy :
>
> * `502 Bad Gateway` : nginx **n'a pas obtenu de réponse valide** du backend.
>   Les lignes associées : `connect() failed (111: Connection refused)` (rien
>   n'écoute : backend arrêté, mauvais port, mauvaise IP), `connect() failed
>   (113: No route to host)` (pare-feu, réseau), `(13: Permission denied)`
>   (socket Unix sans droits, ou SELinux sur Rocky avec
>   `httpd_can_network_connect` à off), `upstream prematurely closed
>   connection` (le backend a planté **pendant** la requête), `upstream sent
>   too big header` (buffers).
> * `504 Gateway Time-out` : la connexion a réussi mais le backend n'a pas
>   répondu dans `proxy_read_timeout` (60 s par défaut) : `upstream timed out
>   (110: Connection timed out) while reading response header`.
> * `503` : nginx lui-même refuse (`limit_req`, `limit_conn`, page de
>   maintenance) — aucun backend n'est contacté.
>
> Ici `111` = `ECONNREFUSED` : le noyau de `lab-web` a répondu par un RST
> parce qu'aucun processus n'écoute sur `127.0.0.1:8003`. Le diagnostic tient
> en une commande : `ss -tlnp | grep 800` pour voir qui écoute réellement.

> [!WARNING]
> **Piège**
>
> d) : SELinux donne `13: Permission denied`, pas `111`. Et un 502 n'apparaît
> que si **tous** les serveurs de l'`upstream` échouent : avec deux backends
> dont un seul est mort, nginx bascule sur l'autre (`proxy_next_upstream`
> inclut `error` et `timeout` par défaut) et l'utilisateur ne voit rien — seul
> `error.log` s'agite. C'est l'étape 6 de L15.2.

---

<a id="q15-6"></a>**[Q15.6](README.md#q15-6)** — *Boucle de `301` sur `http://factura-demo.lab.local/`.*

**Réponse : b)** redirection HTTPS dans un `server` qui reçoit aussi le
trafic HTTPS, ou proto ignoré derrière un équilibreur.

> [!NOTE]
> **Pourquoi**
>
> Une boucle de redirection, c'est une réponse `301 Location: X` renvoyée
> **pour la requête X elle-même**. Deux configurations la produisent :
>
> 1. Un seul bloc `server` avec `listen 80;` et `listen 443 ssl;`, et
>    `return 301 https://$host$request_uri;` sans condition. La requête HTTP
>    est redirigée vers HTTPS ; la requête HTTPS arrive dans le **même**
>    bloc et est redirigée vers elle-même. Correction : deux blocs `server`
>    (un 80 qui ne fait que rediriger, un 443 qui sert), ou `if ($scheme =
>    http) { return 301 ... }` si on tient au bloc unique.
> 2. nginx est derrière un équilibreur ou un CDN qui termine le TLS et lui
>    parle en HTTP clair sur le port 80. Toute requête arrive en HTTP, la
>    règle redirige vers HTTPS, le client revient en HTTPS, l'équilibreur
>    re-transmet en HTTP... La bonne information est dans l'en-tête
>    `X-Forwarded-Proto` : il faut rediriger si `$http_x_forwarded_proto != "https"`, pas si `$scheme = http`.
>
> `curl -sIL --max-redirs 5` montre la boucle : chaque `Location:` répète
> l'URL demandée. Un navigateur affiche « ERR_TOO_MANY_REDIRECTS ».

> [!WARNING]
> **Piège**
>
> Le `301` est **mis en cache** par les navigateurs, sans date d'expiration
> explicite. Une boucle corrigée côté serveur peut continuer à être vue par
> un utilisateur pendant des jours. C'est une raison de tester les
> redirections avec un `302` (temporaire) puis de passer en `301`, et de
> toujours tester avec `curl`, qui ne cache rien.

---

<a id="q15-7"></a>**[Q15.7](README.md#q15-7)** — *`add_header` HSTS dans `server`, un autre `add_header` dans `location /api/`.*

**Réponse : b)** HSTS absent sur `/api/` : l'héritage est tout ou rien.

> [!NOTE]
> **Pourquoi**
>
> La documentation nginx le dit en une ligne qu'on ne lit jamais : « These
> directives are inherited from the previous configuration level if and only
> if there are no `add_header` directives defined on the current level. »
> L'héritage d'`add_header` (comme `proxy_set_header`, `fastcgi_param`,
> `expires`...) n'est pas additif : dès qu'un niveau en définit **un**, il
> repart de zéro et n'hérite **d'aucun** de ceux du niveau supérieur.
>
> Conséquence : une location qui ajoute `X-Request-Id` perd HSTS,
> `X-Frame-Options`, `X-Content-Type-Options` définis dans le `server`. Les
> scanners de sécurité voient les en-têtes sur `/` et pas sur `/api/`, et le
> rapport dit « configuration incohérente ».
>
> Solutions : regrouper tous les en-têtes de sécurité dans
> `/etc/nginx/snippets/securite.conf` et l'`include` dans **chaque** location
> qui définit ses propres `add_header` ; ou ne définir aucun `add_header` dans
> les locations (mettre `X-Request-Id` au niveau server aussi). Le paramètre
> `always` est indépendant de ce mécanisme : il fait ajouter l'en-tête aussi
> sur les réponses d'erreur (4xx, 5xx), sans lui HSTS est absent d'un 404.

> [!WARNING]
> **Piège**
>
> Le même mécanisme s'applique à `proxy_set_header` : une location qui ajoute
> `proxy_set_header X-Truc 1;` perd les `Host`, `X-Forwarded-For` définis au
> niveau `server`, et le backend se met à voir `Host: factura_api` (le nom de
> l'upstream) sans que personne ne comprenne pourquoi. `nginx -T` ne le
> montre pas : il faut interroger le backend (`/api/whoami`).

---

<a id="q15-8"></a>**[Q15.8](README.md#q15-8)** — *`rate=5r/m`, `burst=5 nodelay`, 12 requêtes en une seconde.*

**Réponse : b)** 6 passent, 6 reçoivent 503 (429 seulement avec
`limit_req_status 429`).

> [!NOTE]
> **Pourquoi**
>
> `limit_req` implémente un **seau percé** (*leaky bucket*). `rate=5r/m`
> signifie qu'en régime permanent une requête est acceptée toutes les 12
> secondes ; nginx tient pour chaque clé (`$binary_remote_addr`) un compteur
> d'« excès » qui augmente de 1 à chaque requête et diminue au rythme du
> débit. Une requête est acceptée tant que l'excès ne dépasse pas `burst`.
>
> Déroulé sur 12 requêtes instantanées : la première trouve un compteur à
> zéro et passe ; les cinq suivantes font monter l'excès à 1, 2, 3, 4, 5 —
> toutes acceptées puisque `burst=5` ; la septième porterait l'excès à 6 :
> rejetée, comme les cinq suivantes. **Six** requêtes passent, six sont
> rejetées. Le compteur redescend ensuite d'une unité toutes les 12 s.
>
> Le rôle de `nodelay` : sans lui, les cinq requêtes de la rafale sont
> acceptées mais **retardées** pour respecter le débit (la deuxième attend
> 12 s, la troisième 24 s...) — l'utilisateur voit des réponses très lentes.
> Avec `nodelay`, elles sont servies immédiatement, et l'excès consommé se
> résorbe au fil du temps. `delay=N` (nginx ≥ 1.15.7) est l'intermédiaire :
> N requêtes de rafale sans délai, les autres retardées.
>
> Le code de rejet par défaut est **503**, trompeur pour la supervision (un
> 503 ressemble à une panne). `limit_req_status 429;` donne le code
> sémantiquement juste, *Too Many Requests*. Chaque rejet est journalisé
> dans `error.log` au niveau `error` : `limiting requests, excess: 5.xxx by
> zone "login"`.

> [!WARNING]
> **Piège**
>
> La zone est indexée sur `$binary_remote_addr` : derrière un équilibreur,
> toutes les requêtes ont la même adresse source et **tous les utilisateurs
> partagent le même seau**. Il faut alors `set_real_ip_from` + `real_ip_header
> X-Forwarded-For` (module `ngx_http_realip_module`) pour que
> `$binary_remote_addr` vaille l'IP réelle. Et `10m` de zone stockent environ
> 160 000 adresses : au-delà, nginx évince les états les moins récents, et seulement s'il n'y parvient pas renvoie une erreur.

---

<a id="q15-9"></a>**[Q15.9](README.md#q15-9)** — *Changer `listen_addresses` et `pg_hba.conf`.*

**Réponse : b)** `systemctl restart postgresql@16-main` (le restart relit
aussi `pg_hba.conf`).

> [!NOTE]
> **Pourquoi**
>
> Chaque paramètre de `postgresql.conf` a un **contexte** visible dans
> `pg_settings.context` :
>
> * `postmaster` : lu une seule fois au démarrage du processus principal ;
>   changement = **restart**. C'est le cas de tout ce qui touche à la mémoire
>   partagée ou aux sockets d'écoute : `listen_addresses`, `port`,
>   `max_connections`, `shared_buffers`, `wal_level`,
>   `shared_preload_libraries`, `archive_mode`.
> * `sighup` : rechargé par `pg_reload_conf()` ou `systemctl reload` :
>   `work_mem`, `log_*`, `archive_command`, `timezone`, `effective_cache_size`.
> * `user` / `superuser` : modifiable par session (`SET work_mem = '64MB'`).
>
> Après une modification, `SELECT name, pending_restart FROM pg_settings WHERE
> pending_restart;` liste ce qui attend un restart — la colonne est mise à
> jour au reload. `pg_hba.conf` et `pg_ident.conf` sont relus au reload (et
> donc aussi au restart). Un reload dont `pg_hba.conf` contient une erreur de
> syntaxe **garde les anciennes règles** et journalise `pg_hba.conf was not
> reloaded` — comme nginx. La surprise vient au prochain restart, où le
> serveur refuse alors de démarrer.

> [!WARNING]
> **Piège**
>
> c) : `systemctl reload postgresql` (l'unité parapluie) déclenche bien un
> reload des clusters, mais un reload ne suffit pas pour `listen_addresses`.
> d) : PostgreSQL ne surveille pas ses fichiers. Et un piège d'exploitation :
> le restart est une coupure — toutes les sessions sont fermées. On le
> programme, on prévient, et on regroupe les changements `postmaster`.

---

<a id="q15-10"></a>**[Q15.10](README.md#q15-10)** — *`host all all 10.10.10.0/24 reject` avant la ligne de `factura_app`.*

**Réponse : b)** refusé, `pg_hba.conf rejects connection`.

> [!NOTE]
> **Pourquoi**
>
> `pg_hba.conf` est évalué **séquentiellement, première correspondance
> gagnante**. Pour chaque ligne, PostgreSQL vérifie si le type de connexion
> (`local`/`host`/`hostssl`/`hostnossl`), la base, le rôle et l'adresse
> correspondent. Dès qu'une ligne correspond, sa méthode s'applique et **la
> recherche s'arrête** : si la méthode est `reject`, la connexion est
> refusée ; si c'est `scram-sha-256` et que le mot de passe est faux, la
> connexion est refusée aussi — on ne « retente » jamais avec la ligne
> suivante.
>
> La ligne `10.10.10.0/24` couvre `10.10.10.11`, `all` couvre `factura_demo`
> et `factura_app` : elle correspond, elle est la première, elle rejette. La
> spécificité de la seconde ligne ne compte pas — PostgreSQL n'a pas de
> notion de « ligne la plus précise », contrairement à une table de routage.
>
> L'ordre canonique : les lignes les plus spécifiques en haut, les plus
> générales en bas, et un `reject` explicite en dernier si l'on veut un
> journal clair (par défaut, l'absence de ligne donne `no pg_hba.conf entry`).
> `SELECT line_number, type, database, user_name, address, auth_method FROM
> pg_hba_file_rules;` affiche les règles **dans l'ordre chargé** et signale
> dans `error` une ligne invalide.

> [!WARNING]
> **Piège**
>
> d) confond deux messages : `no pg_hba.conf entry for host ...` = aucune
> ligne ne correspond ; `pg_hba.conf rejects connection for host ...` = une
> ligne `reject` a été atteinte. Le premier te dit d'ajouter une ligne, le
> second de regarder **laquelle** rejette et **avant** quoi. Depuis PG 16, le
> serveur ajoute `DETAIL: Connection matched file ... line N` dans son
> journal : le numéro de ligne coupable est donné.

---

<a id="q15-11"></a>**[Q15.11](README.md#q15-11)** — *`remaining connection slots are reserved for roles with the SUPERUSER attribute` (deux réponses).*

**Réponses : a) et b)**

> [!NOTE]
> **Pourquoi**
>
> PostgreSQL crée **un processus par connexion**. `max_connections` (100 par
> défaut) plafonne leur nombre ; `superuser_reserved_connections` (3) en
> garde pour les superusers, et PG 16 ajoute `reserved_connections` (0 par
> défaut) pour les rôles membres de `pg_use_reserved_connections`. Quand
> 97 connexions non-superuser sont ouvertes, la 98e reçoit ce message. Quand
> les 100 sont prises, même le superuser reçoit `sorry, too many clients
> already`.
>
> La cause n'est presque jamais une charge réelle : c'est une application
> qui ouvre des connexions sans les fermer (pas de pool, pool mal
> dimensionné, workers × threads × instances), ou des sessions `idle` qui
> survivent à un crash du client. `pg_stat_activity` le montre : `SELECT
> state, count(*) FROM pg_stat_activity GROUP BY 1;` avec 90 lignes en
> `idle`, et `now() - state_change` pour l'ancienneté.
>
> Réponse immédiate (b) : se connecter en `postgres` par la socket (les slots
> réservés sont là pour ça) et `SELECT pg_terminate_backend(pid) FROM
> pg_stat_activity WHERE state = 'idle' AND usename = 'factura_app' AND
> state_change < now() - interval '10 min';`. Réponse durable : un pooler
> (pgbouncer en mode `transaction`), `idle_session_timeout` /
> `idle_in_transaction_session_timeout` côté serveur, et `CONNECTION LIMIT`
> par rôle pour qu'une application ne puisse pas assécher les autres.

> [!WARNING]
> **Piège**
>
> c) : `max_connections` a le contexte `postmaster`, `pg_reload_conf()` ne
> l'applique pas — et monter à 500 sans pooler ne fait que repousser le mur
> en consommant de la RAM (chaque backend coûte quelques Mo, plus `work_mem`
> par tri). d) : un mot de passe faux donne `password authentication failed`.
> Le piège de BF15.4 : le collègue a **baissé** `max_connections`, et la panne
> n'est apparue qu'au restart suivant.

---

<a id="q15-12"></a>**[Q15.12](README.md#q15-12)** — *Avantage de `pg_dump -Fc` sur le SQL brut.*

**Réponse : b)** restauration sélective, parallèle, compressée, via
`pg_restore`.

> [!NOTE]
> **Pourquoi**
>
> `pg_dump` produit toujours le même contenu logique (schéma + données), mais
> le **format** change ce qu'on peut en faire :
>
> * `-Fp` (plain, défaut) : un script SQL. Lisible, `grep`-able, restaurable
>   avec `psql -f`. Mais tout ou rien, séquentiel, non compressé (sauf `| gzip`).
> * `-Fc` (custom) : une archive binaire avec une table des matières (TOC).
>   `pg_restore -l` la liste ; `-L` restaure une sélection ; `-t table` ou
>   `-n schema` filtrent ; `-j N` restaure en parallèle (indexes et tables
>   en même temps) ; la compression est intégrée (gzip par défaut, `-Z`
>   pour le niveau, `--compress=zstd` depuis PG 16). `--no-owner`
>   `--no-privileges` s'appliquent **à la restauration**, sans refaire le
>   dump.
> * `-Fd` (directory) : un fichier par table, seul format qui permet aussi
>   le **dump** parallèle (`pg_dump -Fd -j 4`).
> * `-Ft` (tar) : comme custom sans compression, rarement utile.
>
> Le format custom est le choix par défaut en production : on ne perd rien
> (on peut toujours en extraire du SQL avec `pg_restore -f dump.sql`), et on
> gagne la restauration partielle — le cas réel est « restaure-moi juste la
> table `invoices` d'hier ».

> [!WARNING]
> **Piège**
>
> c) : aucun format de `pg_dump` n'inclut les rôles, les mots de passe ni les
> tablespaces : ce sont des objets du **cluster**, pas de la base. D'où
> `pg_dumpall --globals-only`, à sauvegarder à côté, sans quoi la
> restauration sur une machine neuve échoue sur `role "factura_app" does not
> exist`. d) : `pg_dump` n'est jamais incrémental — c'est le rôle des WAL.

---

<a id="q15-13"></a>**[Q15.13](README.md#q15-13)** — *`Seq Scan on invoices`, `rows=20` estimées, `rows=18` réelles, `Rows Removed by Filter: 99982`.*

**Réponse : b)** il manque un index sur `invoices(customer_id)`.

> [!NOTE]
> **Pourquoi**
>
> Lire un plan `EXPLAIN ANALYZE`, c'est comparer trois choses par nœud :
>
> * le **type de nœud** : `Seq Scan` lit toute la table ; `Index Scan` /
>   `Index Only Scan` / `Bitmap Heap Scan` passent par un index ;
> * `rows=` estimé (cost) contre `rows=` réel (actual) : ici 20 contre 18,
>   l'estimation est **bonne** — les statistiques sont à jour, `ANALYZE` ne
>   changerait rien ;
> * `Rows Removed by Filter` : le nombre de lignes lues pour rien. 99 982
>   lignes lues pour en garder 18, c'est un taux de sélectivité de 0,02 % —
>   le cas d'école de l'index manquant.
>
> Le planificateur a choisi un `Seq Scan` **parce qu'il n'a pas le choix** :
> il n'existe aucun index sur `customer_id`. Après `CREATE INDEX
> CONCURRENTLY invoices_customer_id_idx ON invoices (customer_id);`, le plan
> devient `Index Scan using invoices_customer_id_idx` avec `actual rows=18`
> et un temps de l'ordre de 0,05 ms au lieu de 6 ms. Sur la requête complète
> du setup (sous-requête corrélée sur `invoice_lines`, 18 fois un parcours de
> 300 000 lignes), l'effet est de 3 s à 2 ms.
>
> `CONCURRENTLY` construit l'index sans verrou exclusif : la table reste
> lisible et modifiable pendant la construction (plus lente, deux passes).
> Sans lui, `CREATE INDEX` pose un `SHARE` lock qui bloque les écritures
> jusqu'à la fin — sur une grosse table en production, c'est un incident.

> [!WARNING]
> **Piège**
>
> « 6 ms, c'est rapide » (d) est le raisonnement qui tue : la requête est
> appelée 200 fois par seconde, et surtout elle **lit 1 823 blocs**
> (`Buffers: shared hit=1823`) qui occupent le cache au détriment des autres.
> c) : `work_mem` joue sur les tris et les hachages, pas sur un `Seq Scan`
> avec filtre. L'option `BUFFERS` est celle qu'on oublie : `shared read`
> élevé = lecture disque, `shared hit` = cache ; c'est elle qui explique
> pourquoi la même requête prend 2 s la première fois et 50 ms ensuite.

---

<a id="q15-14"></a>**[Q15.14](README.md#q15-14)** — *Session `idle in transaction` depuis 3 h, quatre sessions en attente de verrou.*

**Réponse : b)** terminer la session `idle in transaction`, puis corriger
l'application et poser un timeout.

> [!NOTE]
> **Pourquoi**
>
> `idle in transaction` est l'état le plus dangereux de `pg_stat_activity` :
> la session a exécuté `BEGIN` puis au moins une requête, et **attend** — elle
> n'exécute rien, mais la transaction est ouverte, donc tous ses verrous sont
> tenus (un `UPDATE` pose un `RowExclusiveLock` sur la table et un verrou de
> ligne), et son instantané empêche `VACUUM` de nettoyer les lignes mortes
> plus récentes que lui (bloat garanti au bout de trois heures).
>
> Les quatre sessions `active` avec `wait_event_type = Lock` attendent ce
> verrou : `SELECT pid, pg_blocking_pids(pid) FROM pg_stat_activity WHERE
> cardinality(pg_blocking_pids(pid)) > 0;` renvoie pour chacune le PID du
> bloqueur — le même. `pg_cancel_backend` (SIGINT, annule la requête en
> cours) ne fait rien sur une session qui n'exécute rien ; il faut
> `pg_terminate_backend(pid)` (SIGTERM, ferme la session, ce qui provoque un
> `ROLLBACK`).
>
> La cause est toujours dans l'application : une transaction ouverte et
> jamais validée (exception non gérée après `BEGIN`, ORM en mode autocommit
> désactivé, connexion rendue au pool sans `COMMIT`). Le filet de sécurité
> côté serveur : `idle_in_transaction_session_timeout = '5min'` (contexte
> `user`, donc posable par rôle : `ALTER ROLE factura_app SET
> idle_in_transaction_session_timeout = '5min';`), qui tue automatiquement ce
> type de session, et `log_lock_waits = on` pour voir les attentes de plus
> de `deadlock_timeout` (1 s) dans le journal.

> [!WARNING]
> **Piège**
>
> a) annule les victimes, pas le coupable : elles reviendront. c) `VACUUM
> FULL` a besoin d'un verrou `ACCESS EXCLUSIVE` : il se mettrait **lui-même**
> en file d'attente derrière le bloqueur, et bloquerait à son tour toutes
> les lectures. d) redémarrer résout le symptôme à coup sûr et perd toutes
> les autres sessions — c'est ce qu'on fait quand on n'a pas lu
> `pg_stat_activity`.

---

<a id="q15-15"></a>**[Q15.15](README.md#q15-15)** — *`PANIC: could not write to file "pg_wal/..."`, disque plein (deux réponses).*

**Réponses : b) et c)**

> [!NOTE]
> **Pourquoi**
>
> Le WAL (*write-ahead log*) est le journal de toutes les modifications,
> écrit **avant** les fichiers de données ; c'est lui qui garantit la
> durabilité. Quand PostgreSQL ne peut plus l'écrire, il ne peut plus rien
> garantir : il s'arrête volontairement (`PANIC`) plutôt que de corrompre.
>
> Les segments de `pg_wal/` (16 Mo chacun) sont recyclés automatiquement
> après chaque checkpoint, dans la limite de `max_wal_size` (1 Go). S'ils
> s'accumulent bien au-delà, c'est qu'**on lui a interdit de les recycler** :
>
> * `archive_mode = on` et `archive_command` qui échoue (destination pleine,
>   droits, SSH cassé) : PostgreSQL garde chaque segment tant qu'il n'est pas
>   archivé. `SELECT * FROM pg_stat_archiver;` montre `failed_count` qui
>   monte et `last_failed_wal`.
> * un **slot de réplication** dont le consommateur (réplica, outil CDC) est
>   arrêté : `SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(
>   pg_current_wal_lsn(), restart_lsn)) FROM pg_replication_slots;` — un slot
>   inactif retient tout le WAL depuis sa dernière lecture. PG 13+ a
>   `max_slot_wal_keep_size` pour plafonner.
>
> La remise en service : libérer de l'espace **ailleurs** (vieux dumps,
> journaux, `apt clean`), redémarrer, corriger la cause, et laisser le
> checkpoint suivant recycler. Sur un vrai disque plein, on peut aussi
> étendre le LV (module 11) — c'est l'argument pour un LV dédié à `PGDATA`.

> [!WARNING]
> **Piège**
>
> a) est l'erreur irréversible : supprimer des segments de `pg_wal` à la
> main, c'est retirer des pages du journal comptable. Le serveur peut ne plus
> démarrer (`could not open file "pg_wal/000000010000000000000042"`) et le
> cluster est perdu — restauration depuis sauvegarde. `pg_archivecleanup` et
> `pg_resetwal` existent pour des cas précis, pas pour « faire de la place ».
> b) : `wal_level = minimal` désactive l'archivage et la réplication ; ce
> n'est pas un correctif, c'est une régression.

---

<a id="q15-16"></a>**[Q15.16](README.md#q15-16)** — *Sessions avec TTL + file sans TTL, `maxmemory` atteint.*

**Réponse : c)** `volatile-lru`.

> [!NOTE]
> **Pourquoi**
>
> Quand `used_memory` atteint `maxmemory`, chaque commande qui écrit
> déclenche la politique `maxmemory-policy` :
>
> * `noeviction` : la commande est refusée avec `OOM command not allowed when
>   used memory > 'maxmemory'`. Les lectures continuent. Aucune donnée n'est
>   perdue, mais l'application qui écrit **plante** (c'est BF15.5). C'est la
>   bonne politique pour une **file** ou une base de données, quand perdre
>   une écriture est pire qu'échouer.
> * `allkeys-lru` / `allkeys-lfu` / `allkeys-random` : Redis supprime des
>   clés parmi **toutes** pour faire de la place. Parfait pour un cache pur
>   (tout est reconstructible), catastrophique pour une file : `factura:jobs`
>   peut être évincée avec ses travaux dedans.
> * `volatile-lru` / `volatile-lfu` / `volatile-ttl` / `volatile-random` :
>   Redis n'évince que les clés **qui ont un TTL**. Les sessions (`SETEX`)
>   sont candidates, la file (sans TTL) ne l'est jamais. Si toutes les clés
>   volatiles sont déjà évincées et que la mémoire est encore pleine, Redis
>   se comporte comme `noeviction` — la file reste protégée, l'écriture
>   échoue.
>
> C'est donc `volatile-lru` (ou `volatile-lfu`) qui correspond à un usage
> mixte : les sessions se sacrifient d'abord, la file jamais. La vraie bonne
> réponse d'architecture est cependant **deux instances Redis** (pas deux
> `db` numérotées : la politique est globale à l'instance), une par usage, chacune
> avec sa politique. C'est ce que tu proposeras au projet P1.

> [!WARNING]
> **Piège**
>
> Redis ne mesure pas exactement `maxmemory` : `used_memory` inclut la
> structure interne (~1 Mo à vide) et les buffers clients. Un `maxmemory` de
> quelques Mo est atteint avant la première clé. Et l'éviction ne rend pas
> forcément de la mémoire au système (fragmentation) : `used_memory` baisse,
> `used_memory_rss` non. `INFO stats` → `evicted_keys` est la métrique à
> grapher : si elle monte en continu, le cache est sous-dimensionné.

---

<a id="q15-17"></a>**[Q15.17](README.md#q15-17)** — *`redis-cli KEYS 'sess:*' | wc -l` en production.*

**Réponse : b)** Redis est mono-thread, `KEYS` bloque tout.

> [!NOTE]
> **Pourquoi**
>
> Redis exécute les commandes **une par une sur un seul thread**. C'est ce
> qui le rend simple et prévisible (pas de verrou, atomicité gratuite), et
> c'est ce qui rend toute commande en O(N) dangereuse : pendant que `KEYS`
> parcourt 10 millions de clés (plusieurs centaines de millisecondes à
> quelques secondes), **aucune autre commande n'est traitée**. Toutes les
> requêtes de l'application s'empilent, les timeouts côté client se
> déclenchent, la supervision voit une latence de 2 s, et le tout ressemble
> à une panne réseau.
>
> `SCAN cursor MATCH pattern COUNT n` fait la même chose par lots : chaque
> appel renvoie une poignée de clés et un curseur, entre deux appels les
> autres commandes passent. `redis-cli --scan --pattern 'sess:*'` enchaîne
> les appels pour toi. Le résultat n'est pas un instantané exact (une clé
> modifiée pendant le parcours peut apparaître deux fois ou pas du tout),
> ce qui est acceptable pour compter des sessions. Pour compter **sans
> lister**, `DBSIZE` donne le total de clés, et un compteur maintenu par
> l'application (`INCR`/`DECR`) donne le total par type en O(1).
>
> Les autres commandes de la même famille : `FLUSHALL`, `FLUSHDB`, `SMEMBERS`
> sur un gros set, `HGETALL` sur un gros hash, `LRANGE 0 -1`, `DEBUG`, et
> `MONITOR` qui ralentit chaque commande. L'ACL `-@dangerous` les retire aux
> utilisateurs applicatifs (`KEYS`, `FLUSH*`, `CONFIG`, `SHUTDOWN`,
> `MONITOR`, `DEBUG`...).

> [!WARNING]
> **Piège**
>
> `SLOWLOG GET` te dira après coup qu'un `KEYS` a pris 1,8 s ; `LATENCY
> DOCTOR` te dira qu'un pic de latence a eu lieu. Le collègue dira « mais
> sur mon poste c'est instantané » : avec 200 clés, oui. Le test de
> performance qui compte se fait avec le volume de la production.

---

<a id="q15-18"></a>**[Q15.18](README.md#q15-18)** — *`used_memory` 1,2 Go, `used_memory_rss` 3,9 Go, ratio 3,17 (deux réponses).*

**Réponses : a) et b)**

> [!NOTE]
> **Pourquoi**
>
> * `used_memory` : ce que l'allocateur de Redis (jemalloc) a alloué pour les
>   données et ses structures — la vue « logique ».
> * `used_memory_rss` : le *Resident Set Size* vu par le noyau — les pages
>   physiques réellement attribuées au processus.
> * `mem_fragmentation_ratio` = RSS / `used_memory`.
>
> Un ratio entre 1,0 et 1,5 est normal (l'allocateur garde un peu de marge).
> Au-dessus, c'est de la **fragmentation** : Redis a libéré des clés (TTL
> expirés, `DEL` massifs, évictions), jemalloc a des pages à moitié vides
> qu'il ne peut pas rendre au noyau, et le RSS reste haut. La mémoire est
> « perdue » pour le système jusqu'à un redémarrage — ou jusqu'à ce que
> `activedefrag yes` (défragmentation en ligne, jemalloc requis) compacte
> progressivement. `MEMORY DOCTOR` le dit en clair.
>
> Un ratio **inférieur à 1** signifie l'inverse : le noyau a donné à Redis
> moins de pages physiques qu'il n'en a allouées — le reste est **en swap**.
> Redis est conçu pour la RAM : chaque accès à une page swappée coûte des
> millisecondes de disque, et comme il est mono-thread, une commande
> ralentie ralentit toutes les suivantes. Un Redis qui swappe est une panne,
> pas une dégradation. Vérification : `INFO memory` (`used_memory_rss` <
> `used_memory`), `free -m`, `vmstat 1` (colonnes `si`/`so` non nulles), `grep VmSwap`
> `/proc/$(pidof redis-server)/status`. Parade : `maxmemory`
> **strictement inférieur** à la RAM disponible, `vm.swappiness` bas, ou pas
> de swap du tout sur un serveur Redis dédié.

> [!WARNING]
> **Piège**
>
> c) : `maxmemory` limite `used_memory`, pas le RSS ; le monter n'aide en
> rien. d) : `FLUSHALL` vide les données — le RSS ne redescend même pas
> forcément (fragmentation). Le seul « reset » propre est un redémarrage avec
> persistance à jour (`BGSAVE` puis `systemctl restart redis-server`), pendant
> une fenêtre où l'application tolère une reconnexion.

---

## 15.4 Quiz — questions ouvertes

<a id="qo15-1"></a>**[QO15.1](README.md#qo15-1)** — *En entretien : le trajet d'une requête `https://factura.lab.local/api/invoices` jusqu'à Gunicorn.*

**Réponse attendue** (l'ordre compte) :

1. **TCP et TLS.** Le paquet arrive sur `10.10.10.11:443`. Un worker nginx
   accepte la connexion. Le client envoie un `ClientHello` qui contient le
   nom demandé en clair : le **SNI** (`factura.lab.local`). nginx choisit
   le bloc `server` dont le `server_name` correspond au SNI (ou le
   `default_server` du `listen 443`), et présente **ce** certificat. La
   session TLS est négociée (TLS 1.3, un aller-retour) ; à partir de là
   tout est chiffré entre le client et nginx — et **seulement** jusqu'à
   nginx : c'est la terminaison TLS.
2. **Choix du `server` (bis).** Une fois la requête HTTP déchiffrée, nginx
   relit l'en-tête `Host` (ou `:authority` en HTTP/2) et resélectionne le
   `server` — normalement le même. Si SNI et `Host` diffèrent, c'est
   `Host` qui gagne pour le routage HTTP.
3. **Choix de la `location`.** Sur l'URI `/api/invoices` : préfixe le plus
   long, `^~` éventuel, puis regex dans l'ordre. `location ^~ /api/` gagne.
4. **Le proxy.** nginx ouvre (ou réutilise, si `keepalive` est configuré
   dans l'`upstream` avec `proxy_http_version 1.1` et `Connection ""`) une
   connexion vers `127.0.0.1:8000`, en HTTP/1.1 clair. Il reconstruit la
   requête et ajoute les en-têtes de `proxy_set_header` :
   * `Host: $host` — sinon Gunicorn reçoit le nom de l'upstream et
     construit de mauvaises URL absolues ;
   * `X-Forwarded-For: $proxy_add_x_forwarded_for` — l'IP du client,
     ajoutée à la liste existante ; sans elle, l'application ne voit que
     `127.0.0.1` (journaux inutiles, rate-limiting applicatif impossible) ;
   * `X-Real-IP: $remote_addr` — la même information, sans liste ;
   * `X-Forwarded-Proto: https` — l'application sait qu'elle est servie en
     HTTPS et génère des liens et des cookies `Secure` corrects.
5. **Le backend.** Gunicorn (maître + workers) lit la requête sur son
   socket, un worker exécute la vue Flask, qui interroge PostgreSQL. Le
   backend voit comme **adresse source TCP** `127.0.0.1` — l'IP réelle
   n'est que dans l'en-tête, et il doit être configuré pour lui faire
   confiance (`ProxyFix` en Flask) **uniquement** parce qu'un nginx de
   confiance est devant. La réponse remonte : Gunicorn → nginx (qui la met
   en tampon par défaut, `proxy_buffering on`, pour libérer le worker
   backend vite) → chiffrement TLS → client.
6. **Journal.** nginx écrit une ligne d'`access.log` avec `$request_time`
   (total) et `$upstream_response_time` (temps backend) : la différence
   est le temps réseau client + TLS.

Ce que change `keepalive` : sans lui, chaque requête coûte une poignée de
main TCP vers Gunicorn (et le port éphémère qui va avec, `TIME_WAIT`) ;
avec, les connexions vers l'upstream sont réutilisées. HTTP/2 côté client
ne change rien côté upstream : nginx parle HTTP/1.1 au backend.

> [!NOTE]
> **Pourquoi**
>
> Ce récit est une question d'entretien classique parce qu'il traverse cinq
> couches et montre si le candidat sait **où regarder** quand ça casse : le
> certificat présenté dépend du SNI (donc `openssl s_client -servername`),
> le vhost choisi dépend de `Host` (donc `curl -H Host:`), la location de la
> règle de priorité, le 502/504 de la connexion upstream, et l'IP dans les
> journaux applicatifs de `X-Forwarded-For`. Chaque étape a sa commande de
> test.

---

<a id="qo15-2"></a>**[QO15.2](README.md#qo15-2)** — *Règle complète de sélection des `location`, trois pièges, `root` vs `alias`.*

**La règle** :

1. Les locations **préfixe** (`location /x`, `location = /x`, `location ^~
   /x`) sont comparées à l'URI ; nginx retient **la plus longue** qui
   correspond.
2. Si cette location est `=` (exacte) : elle est retenue immédiatement.
   Si elle est `^~` : elle est retenue, les regex ne sont **pas** testées.
3. Sinon, nginx teste les locations **regex** (`~` sensible à la casse, `~*`
   insensible) **dans l'ordre d'apparition dans la configuration** ; la
   première qui correspond est retenue.
4. Si aucune regex ne correspond, la location préfixe retenue à l'étape 1
   s'applique.

L'ordre des préfixes dans le fichier ne compte pas ; l'ordre des regex
compte. Les locations imbriquées suivent la même règle à l'intérieur de
leur parent.

**Trois pièges** :

* *Regex de cache statique* : `location ~* \.(css|js|json)$ { expires 7d; }`
  capture `/api/data.json`. Correction : `location ^~ /api/` ou regex avec
  exclusion `^(?!/api/)`.
* *Préfixe sans barre* : `location /api { proxy_pass http://b; }` correspond
  aussi à `/apiculture` et `/api-docs`. Correction : `location /api/` et,
  si l'on veut aussi `/api` seul, `location = /api { return 301 /api/; }`.
* *Zone protégée par une location exacte* : `location = /admin/ {
  auth_basic ...; }` ne protège que l'URI `/admin/` : `/admin/index.html`
  et `/admin/export.csv` tombent dans `location /`, sans mot de passe.
  Correction : protéger un **préfixe** (`location /admin/`), jamais un
  exact, pour une zone ; garder `=` pour une URI unique (`= /favicon.ico`,
  `= /health`).

**`root` vs `alias`** : `root` **ajoute** l'URI complète ; `alias`
**remplace** la partie couverte par la location. Avec `location /docs/` et
`GET /docs/guide.html` : `root /srv/www;` → `/srv/www/docs/guide.html` ;
`alias /srv/documentation/;` → `/srv/documentation/guide.html`. On met un
seul `root` au niveau `server` et on n'utilise `alias` que lorsque l'URI ne
reflète pas le disque.

> [!NOTE]
> **Pourquoi**
>
> La raison d'être de ce mécanisme : les préfixes sont rangés dans un arbre
> et la recherche du plus long est en O(longueur de l'URI), indépendante du
> nombre de locations ; les regex sont coûteuses et doivent être testées
> une par une, d'où l'ordre du fichier. `^~` existe précisément pour dire
> « ce préfixe est assez précis, ne dépense pas de temps en regex » — et
> c'est l'arme contre le premier piège. En entretien, l'énoncé de la règle
> en quatre étapes avec le cas `^~` distingue immédiatement quelqu'un qui a
> lu la documentation de quelqu'un qui copie des configurations.

---

<a id="qo15-3"></a>**[QO15.3](README.md#qo15-3)** — *Méthode de diagnostic pour 502, 504, 413, 403, 404 et boucle 301.*

Le préambule commun : `sudo tail -f /var/log/nginx/factura.error.log` dans
un terminal, la commande `curl` dans l'autre. `access.log` donne le code et
`$upstream_addr` ; `error.log` donne la cause.

| Code | `curl` et ligne d'`error.log` | Causes, correctif |
|---|---|---|
| **502** | `curl -sI URL` → 502 ; `connect() failed (111: Connection refused) while connecting to upstream, upstream: "http://127.0.0.1:8001/..."` | rien n'écoute (`ss -tlnp`) : backend arrêté, mauvais port/IP dans `upstream`, socket Unix absente ou sans droits (`13: Permission denied` → `chmod`/groupe, ou SELinux `httpd_can_network_connect`) ; `upstream prematurely closed` → le backend a planté, lire **son** journal |
| **504** | `curl -o /dev/null -w '%{http_code} %{time_total}\n' URL` → 504 après exactement N s ; `upstream timed out (110: Connection timed out) while reading response header from upstream` | backend trop lent (requête SQL, verrou, dépendance externe) ; on mesure côté backend avant de monter `proxy_read_timeout` ; `proxy_connect_timeout` si c'est la **connexion** qui traîne (pare-feu qui drop) |
| **413** | `curl -X POST --data-binary @gros.bin URL` → `413 Request Entity Too Large` ; `client intended to send too large body: 3145728 bytes` | `client_max_body_size` (1 Mo par défaut) au bon niveau (server ou location) ; penser aussi à la limite du backend (Gunicorn, PHP `upload_max_filesize`) |
| **403** | `curl -sI URL` → 403 ; `directory index of "/srv/www/x/" is forbidden` ou `open() "..." failed (13: Permission denied)` ou `access forbidden by rule` | pas de fichier `index` et `autoindex off` ; droits : `www-data` a besoin de `x` sur **chaque** répertoire du chemin et `r` sur le fichier (`namei -l /srv/www/x/f`) ; `deny` qui correspond ; `try_files` qui finit sur un répertoire |
| **404** | `curl -sI URL` → 404 ; `open() "/chemin/réellement/tenté" failed (2: No such file or directory)` | le chemin tenté révèle l'erreur : `root` dupliqué (voulait `alias`), mauvaise location (regex), `try_files` sans repli ; côté proxy : `upstream_status 404` dans `access.log` = c'est le backend qui répond 404, pas nginx |
| **301 en boucle** | `curl -sIL --max-redirs 3 URL` → même `Location:` répété | `return 301 https://` dans un server qui écoute aussi 443 ; derrière un LB, tester `$http_x_forwarded_proto` ; `301` mis en cache par le navigateur : tester avec `curl` |

> [!NOTE]
> **Pourquoi**
>
> Le principe : nginx **sait toujours pourquoi** il a renvoyé un code, et il
> l'écrit dans `error.log` avec le chemin ou l'adresse exacts qu'il a tentés.
> La méthode n'est donc pas de deviner mais de lire cette ligne, puis de
> vérifier l'hypothèse avec la commande système correspondante (`ss`,
> `namei`, `stat`, `curl` direct sur le backend en sautant nginx :
> `curl http://127.0.0.1:8001/api/health`). Si le backend répond directement
> mais pas via nginx, le problème est dans nginx ; s'il ne répond pas
> directement, nginx est innocent. Ce test « avec et sans le proxy » est le
> premier à faire, avant même de lire la conf.

---

<a id="qo15-4"></a>**[QO15.4](README.md#qo15-4)** — *En entretien : comment PostgreSQL décide d'accepter une connexion.*

**Réponse attendue** :

**Étape 0 — le réseau.** Avant toute authentification, il faut que le
paquet arrive : `listen_addresses` détermine sur quelles interfaces le
postmaster ouvre une socket TCP (par défaut `localhost` seulement), et le
pare-feu doit laisser passer 5432. Si ça bloque ici, le client voit
`connection to server at "10.10.10.12", port 5432 failed: Connection
refused` (rien n'écoute) ou un timeout (pare-feu qui jette). `pg_hba.conf`
n'est même pas consulté.

**Étape 1 — `pg_hba.conf` (host-based authentication).** Le serveur reçoit
la demande de connexion avec trois informations : le rôle demandé, la base
demandée, et l'origine (socket Unix, ou adresse IP, chiffrée ou non). Il
parcourt `pg_hba.conf` **de haut en bas** et s'arrête à la **première**
ligne dont les quatre premiers champs correspondent :

* `local` : connexion par socket Unix (`/run/postgresql/.s.PGSQL.5432`) ;
  `host` : TCP, chiffré ou non ; `hostssl` : TCP chiffré seulement ;
  `hostnossl` : TCP en clair seulement.
* base : `all`, un nom, `replication` (pour les connexions de réplication),
  `sameuser`.
* rôle : `all`, un nom, `+groupe`.
* adresse : CIDR (`10.10.10.11/32`), `samehost`, `samenet`.

Si aucune ligne ne correspond : `no pg_hba.conf entry for host
"10.10.10.10", user "factura_app", database "factura_demo", SSL encryption`
(le message dit tout, y compris si la tentative était chiffrée, ce qui
compte pour `hostssl`). Si une ligne correspond, sa **méthode** s'applique
et on ne passe jamais à la suivante.

**Étape 2 — la méthode.**

* `peer` : socket Unix seulement ; le noyau donne l'UID du client
  (`SO_PEERCRED`), le serveur exige que le nom du compte Unix soit égal
  au rôle (ou le mappe via `pg_ident.conf`). Aucun mot de passe. C'est
  ce qui permet `sudo -u postgres psql`, et c'est parfait pour les
  scripts locaux (sauvegarde).
* `scram-sha-256` : échange de défi/réponse ; le mot de passe **ne
  transite jamais**, le serveur stocke un secret dérivé salé. La seule
  méthode par mot de passe acceptable aujourd'hui.
* `md5` : héritée ; hachage MD5 non salé côté stockage (rejouable si la
  table `pg_authid` fuit). Si le secret stocké est en SCRAM, `md5` bascule
  automatiquement en SCRAM ; l'inverse est faux — un secret `md5` face à une
  méthode `scram-sha-256` donne `password authentication failed`.
* `trust` : aucune vérification. Même sur `localhost`, c'est un problème :
  **tout processus** de la machine (une application web compromise, un
  utilisateur quelconque) devient superuser en tapant `psql -U postgres
  -h 127.0.0.1`. Il n'y a aucun cas de production pour `trust`.
* `reject`, `cert` (certificat client), `ldap`, `gss`... existent pour
  des contextes précis.

Si la méthode échoue : `password authentication failed for user
"factura_app"` ou `Peer authentication failed for user "factura_app"`. Le
journal du serveur ajoute `DETAIL: Connection matched file
"/etc/postgresql/16/main/pg_hba.conf" line 5` et, en cas de secret
incompatible, `User "factura_app" does not have a valid SCRAM secret`.

**Étape 3 — le rôle.** `LOGIN` requis (`role "x" is not permitted to log
in`), `CONNECTION LIMIT` non atteint (`too many connections for role`),
`VALID UNTIL` non dépassé, et le privilège `CONNECT` sur la base
(`permission denied for database`).

> [!NOTE]
> **Pourquoi**
>
> Les trois messages — `Connection refused`, `no pg_hba.conf entry`,
> `password authentication failed` — situent l'échec dans l'ordre : réseau,
> règle, secret. C'est ce qui permet en entretien de dérouler un diagnostic
> sans hésiter : « refused → `listen_addresses`/pare-feu ; no entry → j'ajoute
> ou je réordonne une ligne ; auth failed → mot de passe, ou incompatibilité
> md5/scram, je regarde le `DETAIL` du journal serveur ». Et la question
> piège qui suit : « pourquoi `trust` sur localhost est-il dangereux ? » —
> parce que l'authentification n'a lieu **qu'à** cette étape ; sans elle,
> l'identité est celle que le client déclare.

---

<a id="qo15-5"></a>**[QO15.5](README.md#qo15-5)** — *`pg_dump` vs `pg_basebackup` + WAL ; sauvegarde testée ; `--globals-only`.*

**`pg_dump`** produit une copie **logique** : des instructions SQL (ou leur
équivalent binaire) qui recréent le schéma et rechargent les données. Ce
qu'il capture : une base, cohérente à l'instant du début du dump (grâce à
un instantané MVCC : le dump tourne pendant que la base vit, sans verrou
d'écriture). Ce qu'il ne capture pas : les rôles, les tablespaces, la
configuration, les autres bases. RPO = intervalle entre deux dumps (une
nuit = jusqu'à 24 h de pertes). Restauration : rejouer le SQL — des minutes
à des heures selon le volume (index reconstruits, contraintes revérifiées).
Place : compressé, souvent 5 à 10 fois plus petit que `PGDATA`. Avantages
décisifs : portable entre versions majeures et architectures, restauration
partielle (une table), lisible.

**`pg_basebackup` + archivage WAL** produit une copie **physique** : les
fichiers de `PGDATA` tels quels (incohérents pendant la copie), rendus
cohérents par le rejeu du WAL écrit pendant la copie. Ensuite,
`archive_command` copie chaque segment WAL (16 Mo) terminé vers un stockage
sûr. Ce qu'on capture : **tout le cluster**, toutes les bases, les rôles,
et **chaque transaction** depuis la base. RPO = un segment WAL (ou moins
avec `archive_timeout`, ou zéro avec la réplication streaming). RTO :
copier la base + rejouer les WAL — rapide pour la base (copie de fichiers),
proportionnel au volume de WAL à rejouer. Place : la taille de `PGDATA`
plus le flux de WAL (potentiellement énorme sur une base très active).
Contraintes : même version majeure, même architecture, tout ou rien (on ne
restaure pas une table — sauf en restaurant tout dans un cluster à côté,
ce qu'on fait en pratique).

Le **PITR** (*point-in-time recovery*) est ce que la seconde méthode
apporte de plus : on restaure la base physique, on pose
`restore_command`, `recovery_target_time = '2026-09-19 10:14:50'` et un
fichier `recovery.signal`, et PostgreSQL rejoue le WAL **jusqu'à cet
instant** puis s'arrête. Une suppression malheureuse à 10 h 15 se répare en
revenant à 10 h 14, sans perdre la matinée.

**Une sauvegarde testée** : une sauvegarde dont on a **mesuré** qu'elle se
restaure, avec une procédure écrite et un critère de réussite objectif.
Procédure minimale : (1) prendre le dernier dump, vérifier son `.sha256` ;
(2) `createdb factura_restore` ; (3) `pg_restore --no-owner -j 2 -d
factura_restore fichier.dump`, **chronométré** ; (4) comparer des
métriques — `count(*)` sur les tables principales, `max(id)`, une somme de
contrôle métier (`sum(total_cents)`) — avec la source ; (5) un test
applicatif (une requête de l'application sur la base restaurée) ; (6)
consigner date, durée, résultat. Automatisée par timer hebdomadaire, elle
devient une métrique (`restore_test_success`, `restore_duration_seconds`).
Sans ça, on a un fichier, pas une sauvegarde.

**`pg_dumpall --globals-only`** exporte ce qui n'appartient à aucune base :
`CREATE ROLE` avec les mots de passe hachés, les `ALTER ROLE ... SET`, les
tablespaces. On l'oublie parce que « ça marche » sur le serveur d'origine,
où les rôles existent déjà. Sur une machine neuve, `pg_restore` échoue sur
`role "factura_app" does not exist` — ou pire, restaure sans propriétaire
avec `--no-owner` et l'application ne peut plus écrire.

> [!NOTE]
> **Pourquoi**
>
> Les deux méthodes ne sont pas concurrentes : la logique protège contre les
> erreurs (une table supprimée, une migration ratée, une montée de version)
> et permet l'archivage long terme lisible ; la physique protège contre la
> perte du serveur et donne un RPO fin. Une production sérieuse a les deux,
> et un test de restauration périodique pour chacune. L'argument d'entretien
> qui compte : « le RPO de mon `pg_dump` nocturne est de 24 h ; si le métier
> n'accepte pas de perdre une journée, il me faut l'archivage WAL, et je
> sais le mettre en place ».

---

<a id="qo15-6"></a>**[QO15.6](README.md#qo15-6)** — *« La base est lente depuis ce matin » : cinq requêtes ; bloat, `VACUUM`, `autovacuum`.*

**Les cinq requêtes, dans l'ordre** :

1. **Qu'est-ce qui tourne, depuis combien de temps ?** — `pg_stat_activity`
   ```sql
   SELECT pid, usename, state, wait_event_type, wait_event,
          now() - query_start AS age, left(query, 80)
   FROM pg_stat_activity WHERE state <> 'idle' AND pid <> pg_backend_pid()
   ORDER BY age DESC;
   ```
   Je cherche : des requêtes actives depuis des minutes (une requête
   pathologique), des `wait_event_type = Lock` (contention), des `idle in
   transaction` anciens, et le **nombre** de sessions (`count(*)` par
   `state`) proche de `max_connections`.
2. **Qui bloque qui ?** — `pg_locks` via `pg_blocking_pids`
   ```sql
   SELECT pid, pg_blocking_pids(pid) AS bloque_par, state,
          now() - state_change AS depuis, left(query, 60)
   FROM pg_stat_activity WHERE cardinality(pg_blocking_pids(pid)) > 0;
   ```
   Je cherche : un PID qui apparaît partout dans `bloque_par` — c'est lui
   qu'on regarde (souvent `idle in transaction`).
3. **Quelles requêtes coûtent le plus, cumulé ?** — `pg_stat_statements`
   ```sql
   SELECT calls, round(total_exec_time) AS total_ms,
          round(mean_exec_time::numeric, 1) AS moy_ms, rows, left(query, 70)
   FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;
   ```
   Je cherche : une requête au `total_exec_time` dominant (soit très
   appelée, soit très lente), et je compare à hier si j'ai un export
   (module 26). Un `EXPLAIN (ANALYZE, BUFFERS)` sur la première.
4. **Les tables sont-elles saines ?** — `pg_stat_user_tables`
   ```sql
   SELECT relname, seq_scan, idx_scan, n_live_tup, n_dead_tup,
          round(100.0 * n_dead_tup / greatest(n_live_tup, 1), 1) AS pct_mort,
          last_autovacuum, last_autoanalyze
   FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 10;
   ```
   Je cherche : `seq_scan` qui explose sur une grosse table (index
   manquant ou inutilisé), `n_dead_tup` élevé avec `last_autovacuum` vieux
   (bloat), `last_autoanalyze` absent (statistiques périmées → mauvais
   plans).
5. **La machine et le cache** — `pg_stat_database` et le système
   ```sql
   SELECT datname, numbackends, xact_commit, xact_rollback, deadlocks,
          temp_files, pg_size_pretty(temp_bytes) AS temp,
          round(100.0 * blks_hit / greatest(blks_hit + blks_read, 1), 1)
            AS cache_pct
   FROM pg_stat_database WHERE datname = 'factura_demo';
   ```
   Je cherche : `temp_files` qui monte (`work_mem` trop bas, tris sur
   disque), `cache_pct` sous 95 % (`shared_buffers` trop petit ou données
   qui ne tiennent plus en RAM), `deadlocks`. En parallèle, `iostat -x 1`,
   `free -m` (swap ?), `df -h` de `PGDATA` — la base est peut-être lente
   parce que le disque l'est.

**Le bloat.** PostgreSQL ne modifie jamais une ligne en place : un `UPDATE`
écrit une nouvelle version et marque l'ancienne comme morte (MVCC — les
transactions plus anciennes peuvent encore la voir). Un `DELETE` marque
seulement. Les versions mortes occupent de la place dans les fichiers de
la table et de ses index : c'est le **bloat**. Une table de 1 Go de
données vivantes peut peser 5 Go sur disque, et chaque `Seq Scan` lit les
5 Go.

**`VACUUM`** parcourt la table, identifie les versions mortes que plus
aucune transaction ne peut voir, et marque leur espace **réutilisable**
(dans la *free space map*). Il ne rend pas l'espace au système de fichiers
(sauf les pages entièrement vides en fin de fichier). Il met aussi à jour
la *visibility map* (indispensable aux `Index Only Scan`) et empêche le
*wraparound* des identifiants de transaction — la panne qui arrête une base
si `VACUUM` ne passe jamais. `VACUUM ANALYZE` rafraîchit en plus les
statistiques du planificateur. Il tourne **sans bloquer** lectures et
écritures.

**`VACUUM FULL`** réécrit la table entière dans un nouveau fichier compact
et rend l'espace au système. Il pose un verrou `ACCESS EXCLUSIVE` : pendant
toute sa durée (minutes à heures), **plus aucune lecture ni écriture** sur
la table, et il a besoin de deux fois la place. En journée sur une table
de production, c'est un incident. Alternative : `pg_repack` (extension,
réécrit sans verrou long) ou une fenêtre de maintenance.

**Vérifier qu'`autovacuum` travaille** : `SHOW autovacuum;` (`on`) ;
`pg_stat_user_tables.last_autovacuum` et `autovacuum_count` par table ; le
seuil de déclenchement par défaut est `autovacuum_vacuum_threshold` (50) +
`autovacuum_vacuum_scale_factor` (20 %) × lignes — sur une table de 100
millions de lignes, il attend 20 millions de lignes mortes : on abaisse le
facteur par table (`ALTER TABLE invoices SET (autovacuum_vacuum_scale_factor
= 0.02);`). `SELECT * FROM pg_stat_progress_vacuum;` montre les `VACUUM` en
cours ; `log_autovacuum_min_duration = 0` les journalise.

> [!NOTE]
> **Pourquoi**
>
> L'ordre des requêtes va du plus urgent (une session qui bloque tout le
> monde se règle en une commande) au plus structurel (le cache, le disque).
> Le bloat est la notion que les entretiens testent parce qu'elle est propre
> à PostgreSQL : un candidat qui sait dire « MVCC, versions mortes, `VACUUM`
> recycle sans rendre, `VACUUM FULL` verrouille » a compris pourquoi une
> table « vide » peut peser des gigaoctets et pourquoi `autovacuum` ne se
> désactive jamais.

---

<a id="qo15-7"></a>**[QO15.7](README.md#qo15-7)** — *En entretien : « Redis, cache ou base ? » ; `maxmemory`, RDB/AOF, swap.*

**Réponse attendue** : « Les deux, et c'est la configuration qui décide. »
Redis est un serveur de structures de données **en mémoire** : par défaut
il garde tout en RAM, écrit un instantané sur disque de temps en temps, et
si on lui donne une limite mémoire il jette des clés. Selon les réglages,
il se comporte en cache (tout est perdu sans dommage) ou en base (rien
n'est perdu sans qu'il le dise).

**À `maxmemory`** : chaque écriture consulte `maxmemory-policy`.
`noeviction` refuse l'écriture (`OOM command not allowed when used memory >
'maxmemory'`) — comportement de base de données : l'application doit gérer
l'erreur. `allkeys-lru`/`lfu` évince n'importe quelle clé — comportement de
cache : les données sont reconstructibles. `volatile-*` n'évince que les
clés à TTL — usage mixte. Sans `maxmemory` (défaut !), Redis grossit
jusqu'à ce que le noyau le tue (OOM killer) ou le fasse swapper.

**RDB** (`save 3600 1 300 100 60 10000`) : Redis `fork()` un processus
enfant qui écrit un instantané complet `dump.rdb`, pendant que le parent
continue de servir (*copy-on-write*). Compact, rapide à recharger, parfait
pour les sauvegardes (copier un fichier). Perte en cas de coupure : tout
ce qui s'est passé depuis le dernier instantané — jusqu'à une heure avec
les réglages par défaut. Coût : le `fork()` d'un processus de 20 Go prend
du temps et peut doubler la mémoire si les pages sont beaucoup modifiées.

**AOF** (`appendonly yes`) : chaque commande d'écriture est ajoutée à un
journal ; au redémarrage, Redis le rejoue. `appendfsync everysec` (défaut
raisonnable) : `fsync` une fois par seconde → perte maximale d'une seconde.
`always` : `fsync` à chaque commande → durabilité de base de données, mais
le débit d'écriture devient celui du disque (centaines de fois plus lent
sur un disque mécanique, sensible même sur SSD) — c'est pourquoi on le
choisit rarement, et seulement quand la donnée n'existe **que** là. `no` :
le noyau décide (30 s sous Linux). Le fichier grossit ; `BGREWRITEAOF` (ou
`auto-aof-rewrite-percentage`) le compacte ; Redis 7 le découpe en
`appendonlydir/` (un fichier de base RDB + incréments). Les deux se
combinent : RDB pour les copies, AOF pour la durabilité.

**Le swap.** Redis est conçu pour que **chaque** accès soit en RAM ; ses
structures sont éparses (pointeurs partout), et il est mono-thread. Si le
noyau déplace une partie de ses pages en swap, un `GET` qui touche une page
swappée attend le disque (millisecondes), et **toutes les commandes
suivantes attendent derrière**. La latence passe de 100 μs à plusieurs
secondes, les clients passent en timeout et se reconnectent, ce qui
aggrave. Ce n'est pas un ralentissement, c'est une indisponibilité.
Détection : `INFO memory` avec `used_memory_rss < used_memory` (ratio
< 1), `grep VmSwap /proc/$(pidof redis-server)/status`, `vmstat 1` avec
`si`/`so` non nuls, `redis-cli --latency` qui montre des pics. Prévention :
`maxmemory` inférieur à la RAM libre (en comptant le `fork()` RDB), pas
d'autre gros consommateur sur la machine, `vm.overcommit_memory = 1` (sinon
le `fork()` échoue), `swapoff` ou `vm.swappiness = 1`.

> [!NOTE]
> **Pourquoi**
>
> La question est posée pour voir si le candidat sait que Redis **ne protège
> pas les données par défaut** : sans `maxmemory` il grossit sans limite,
> avec `maxmemory` et une politique `allkeys` il jette des données sans
> prévenir, avec RDB seul il peut perdre une heure. Les projets qui mettent
> une file de travaux dans un Redis « configuré comme un cache » perdent des
> travaux, et ne s'en aperçoivent que lorsqu'un client réclame. La réponse
> attendue relie chaque réglage à ce qu'il **perd** en cas de problème.

---

<a id="qo15-8"></a>**[QO15.8](README.md#qo15-8)** — *Sockets Unix de PostgreSQL et Redis ; ordre de démarrage.*

**PostgreSQL** ouvre `/run/postgresql/.s.PGSQL.5432` avec le mode **`0777`**
(`unix_socket_permissions`, défaut `0777`) dans un répertoire `postgres:
postgres 2775`. N'importe quel utilisateur de la machine peut donc s'y
connecter au niveau système. La sécurité n'est **pas** dans le système de
fichiers : elle est dans `pg_hba.conf`, ligne `local all all peer`, qui
demande au noyau l'UID du client (`SO_PEERCRED`) et exige qu'il corresponde
au rôle. `mathieu` peut ouvrir la socket, mais `psql -U postgres` lui
répond `Peer authentication failed`. Choix de conception : PostgreSQL
authentifie **par rôle**, quel que soit le transport, et veut que la
socket soit utilisable par tous les comptes applicatifs de la machine sans
jouer avec des groupes.

**Redis** : la socket Unix n'est pas activée par défaut sur Ubuntu
(`# unixsocket /run/redis/redis-server.sock`, `unixsocketperm 700`) ; quand
on l'active, elle est créée avec le mode **`0700`** dans `/run/redis`
(`redis:redis`). Seuls `redis` et les membres du groupe `redis` (si l'on
passe à `770`) peuvent l'ouvrir. La sécurité est **dans le système de
fichiers** — parce que Redis, historiquement, n'avait **aucune**
authentification par utilisateur : quiconque parle à la socket est admin.
Les ACL (Redis 6+) ajoutent une couche par utilisateur, mais la socket
Unix reste protégée par ses droits, et c'est un mécanisme sain : un
processus qui n'est pas dans le groupe `redis` ne peut même pas tenter
`AUTH`.

**Ordre de démarrage.** Pour une application locale sur `lab-db` :

```ini
[Unit]
After=network-online.target postgresql.service redis-server.service
Wants=network-online.target postgresql.service redis-server.service
```

`After=` ordonne : l'application démarre quand les deux unités ont atteint
leur état actif. `Wants=` déclenche leur démarrage sans rendre
l'application dépendante de leur succès. `Requires=` ferait tomber
l'application si Redis s'arrête — presque jamais souhaitable : on préfère
une application qui retente. Attention à `postgresql.service` : c'est
l'unité parapluie, `Type=oneshot` + `RemainAfterExit`, qui est « active »
quand `postgresql@16-main.service` a démarré — donc `After=postgresql.service`
attend bien le cluster ; `After=postgresql@16-main.service` est plus
précis mais casse si le cluster est renommé.

Quand la base est sur une autre machine (`lab-web` → `lab-db`), aucune
unité systemd locale ne représente PostgreSQL : `After=network-online.target`
garantit seulement que le réseau local est configuré. L'ordre de démarrage
des **machines** n'est pas maîtrisé ; c'est l'application qui doit
**retenter** sa connexion (avec backoff), ou l'unité qui doit avoir
`Restart=on-failure` + `RestartSec=` pour absorber une base pas encore
prête. Un `ExecStartPre=` qui attend le port (`pg_isready -h 10.10.10.12
-t 3` en boucle) est un compromis courant.

> [!NOTE]
> **Pourquoi**
>
> Les deux sockets illustrent deux philosophies de sécurité : PostgreSQL
> authentifie l'identité (le transport est ouvert, `pg_hba` décide), Redis
> protège le transport (la socket est fermée, celui qui y accède est de
> confiance). Confondre les deux mène à des erreurs symétriques : mettre
> `unix_socket_permissions = 0700` sur PostgreSQL casse toutes les
> applications locales sans rien sécuriser de plus ; laisser la socket Redis
> en `777` donne l'administration de Redis à tout processus de la machine.

---

<a id="qo15-9"></a>**[QO15.9](README.md#qo15-9)** — *Fiche d'entretien : cinq choses par composant.*

**nginx**

1. Rôle : serveur de fichiers statiques et reverse proxy / terminaison TLS
   devant des backends (Gunicorn, Node, PHP-FPM) ; architecture maître +
   workers événementiels, un worker par cœur, des dizaines de milliers de
   connexions par worker.
2. Fichiers : `/etc/nginx/nginx.conf` → `conf.d/*.conf` + `sites-enabled/*`
   (Debian) ; un vhost = un bloc `server` choisi par `listen` + `server_name`
   ; le routage interne par `location` (exact > `^~` > regex dans l'ordre >
   préfixe le plus long).
3. Validation et rechargement : `nginx -t` puis `systemctl reload nginx`
   (sans coupure, anciens workers drainés) ; `nginx -T` pour la conf
   effective ; jamais `restart` sans `-t`.
4. Panne classique : 502 (`connect() failed` dans `error.log` → backend ou
   port), 504 (`upstream timed out` → backend lent, `proxy_read_timeout`),
   404 sur une API à cause d'une regex de cache (priorité des locations),
   en-tête de sécurité absent sur une location (héritage `add_header`).
5. Supervision : `access.log` avec `$request_time` et
   `$upstream_response_time`, taux de 5xx par vhost, `stub_status` ou
   `nginx-prometheus-exporter` (connexions actives, requêtes/s), expiration
   du certificat.

**PostgreSQL**

1. Rôle : base relationnelle transactionnelle, MVCC (pas de verrou en
   lecture, versions de lignes, `VACUUM` obligatoire), un processus par
   connexion, WAL pour la durabilité et la réplication.
2. Fichiers : `postgresql.conf` (+ `conf.d/`, `postgresql.auto.conf` par
   `ALTER SYSTEM`), `pg_hba.conf` (qui, d'où, comment), `PGDATA` =
   `/var/lib/postgresql/16/main` (Ubuntu) ; `pg_lsclusters`,
   `postgresql@16-main.service` ; journal
   `/var/log/postgresql/postgresql-16-main.log`.
3. Validation et rechargement : `pg_settings.context` dit si c'est
   `reload` (`pg_reload_conf()`) ou `restart` (`listen_addresses`,
   `shared_buffers`, `max_connections`) ; `pg_hba_file_rules` pour
   vérifier les règles chargées ; `pending_restart`.
4. Pannes classiques : `too many connections` (sessions `idle`, pas de
   pool → `pg_terminate_backend`, pgbouncer), `no pg_hba.conf entry`
   (ligne manquante ou mal ordonnée), `idle in transaction` qui bloque
   (`pg_blocking_pids`), disque plein par `pg_wal` (archivage ou slot en
   échec — ne jamais `rm`), requête lente (`EXPLAIN ANALYZE`, index
   `CONCURRENTLY`).
5. Supervision et exploitation : `pg_stat_activity`, `pg_stat_statements`,
   `pg_stat_user_tables` (`n_dead_tup`, `last_autovacuum`), taille des
   bases, `pg_stat_archiver`, `pg_stat_replication` (retard) ;
   `postgres_exporter` ; sauvegarde `pg_dump -Fc` nocturne **restaurée**,
   `pg_basebackup` + WAL pour le PITR, `pg_dumpall --globals-only`.

**Redis**

1. Rôle : structures de données en mémoire (string, hash, list, set, zset),
   mono-thread, latence sub-milliseconde ; usages : cache, sessions, file
   simple, compteurs, verrous distribués ; ce n'est pas une base durable
   par défaut.
2. Fichiers : `/etc/redis/redis.conf` (`bind`, `protected-mode`, ACL ou
   `requirepass`, `maxmemory` + `maxmemory-policy`, `save`, `appendonly`),
   `/var/lib/redis/` (`dump.rdb`, `appendonlydir/`), `redis-server.service`.
3. Validation : `redis-cli PING`, `CONFIG GET`, `CONFIG SET` à chaud puis
   `CONFIG REWRITE` ; `ACL LIST` ; `INFO` par section.
4. Pannes classiques : `OOM command not allowed` (`maxmemory` +
   `noeviction`), évictions silencieuses d'une file (`allkeys-lru` avec une
   file), `KEYS *` qui gèle l'instance, `MISCONF` (`BGSAVE` en échec, disque
   ou droits, écritures refusées), swap (ratio de fragmentation < 1),
   `fork()` impossible (`vm.overcommit_memory`), instance exposée sans mot
   de passe (`bind 0.0.0.0`).
5. Supervision : `used_memory` / `maxmemory`, `evicted_keys`,
   `keyspace_hits`/`misses`, `connected_clients`, `rejected_connections`,
   `instantaneous_ops_per_sec`, `rdb_last_bgsave_status`,
   `aof_last_write_status`, `--latency` ; `redis_exporter`. Sauvegarde =
   copier `dump.rdb` après `BGSAVE`. Haute disponibilité : réplication +
   Sentinel ; partitionnement : Cluster.

> [!NOTE]
> **Pourquoi**
>
> Une bonne fiche d'entretien n'est pas un résumé de documentation : elle
> donne pour chaque composant **un fichier, une commande, une panne, une
> métrique**. L'interlocuteur cherche des signes de pratique : quelqu'un qui
> dit « `pg_stat_activity` et `idle in transaction` », « `nginx -t` avant
> `reload` », « `evicted_keys` et `noeviction` », a exploité ces services.
> Quelqu'un qui dit « très performant » et « facile à configurer » ne les a
> pas exploités.

---

## 15.5 Exercices guidés

<a id="e15-1"></a>**[E15.1](README.md#e15-1)** — *En-têtes seuls de `/api/health` sur 8001 ; code + temps de cinq requêtes `/api/slow?s=1`.*

```bash
curl -sI http://127.0.0.1:8001/api/health
# HTTP/1.0 200 OK  ... X-Backend-Instance: 8001
for i in 1 2 3 4 5; do
  curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' \
    'http://127.0.0.1:8001/api/slow?s=1'
done
```

> [!NOTE]
> **Pourquoi**
>
> `-I` envoie une requête `HEAD` : le serveur renvoie les en-têtes sans le
> corps. Attention, certains backends ne gèrent pas `HEAD` et répondent 501
> ou 405 (la mini-API le gère) ; dans ce cas `-s -D - -o /dev/null` fait un
> `GET` en affichant les en-têtes (`-D -` = *dump headers* sur la sortie
> standard) et jette le corps. `-w` formate des variables après la
> requête : `%{http_code}`, `%{time_total}`, `%{time_connect}`,
> `%{time_starttransfer}` (temps jusqu'au premier octet — c'est le temps
> backend), `%{size_download}`, `%{remote_ip}`. C'est le plus petit outil de
> mesure de latence qui existe, et il suffit dans 80 % des diagnostics.
> `X-Backend-Instance` est ajouté par la mini-API : derrière nginx, il te dira
> quelle instance a répondu sans ouvrir les journaux.

---

<a id="e15-2"></a>**[E15.2](README.md#e15-2)** — *Conf effective, nombre de `server`, et la ligne qui explique `sites-available`.*

```bash
sudo nginx -T 2>/dev/null | grep -c '^\s*server\s*{'
sudo nginx -T 2>/dev/null | grep -n 'include'
grep -n 'sites-enabled' /etc/nginx/nginx.conf
#   include /etc/nginx/conf.d/*.conf;
#   include /etc/nginx/sites-enabled/*;
```

> [!NOTE]
> **Pourquoi**
>
> `nginx -T` (majuscule) valide **et** affiche la configuration telle que le
> maître la lit : chaque `include` résolu, chaque fichier précédé de
> `# configuration file /etc/nginx/...:`. C'est la seule vue fiable quand la
> configuration est éclatée en dix fichiers : on y voit les doublons de
> `server_name`, les `add_header` qui s'annulent, les `upstream` définis deux
> fois. Le `2>/dev/null` masque les deux lignes de `-t` (`syntax is ok`, `test
> is successful`) qui partent sur stderr.
>
> `nginx.conf` n'inclut que `sites-enabled/*` : `sites-available/` est une
> convention Debian, un simple dépôt de fichiers que nginx ignore. Le lien
> symbolique dans `sites-enabled/` **est** l'activation. Cette séparation
> permet de désactiver un site sans le supprimer (`rm` du lien) et de
> préparer un site sans le servir. Sur Rocky, cette convention n'existe pas :
> tout ce qui est dans `conf.d/*.conf` est chargé, et on désactive en
> renommant en `.conf.disabled`.

---

<a id="e15-3"></a>**[E15.3](README.md#e15-3)** — *Vhost `factura-demo.lab.local` sur 80, `default` désactivé, test par `Host`, `Host` inconnu.*

```nginx
# /etc/nginx/sites-available/factura-demo
server {
    listen 80;
    listen [::]:80;
    server_name factura-demo.lab.local;
    root /srv/www/factura-demo;
    index index.html;
    location / { try_files $uri $uri/ =404; }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/factura-demo /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
# depuis lab-adm
curl -s -H 'Host: factura-demo.lab.local' http://10.10.10.11/ | head -3
curl -sI -H 'Host: inconnu.example' http://10.10.10.11/
echo '10.10.10.11 factura-demo.lab.local' | sudo tee -a /etc/hosts
curl -sI http://factura-demo.lab.local/
```

Avec un `Host` inconnu, nginx sert **quand même** ce vhost : c'est le seul
sur `listen 80`, donc il est `default_server` implicite.

> [!NOTE]
> **Pourquoi**
>
> nginx choisit le `server` en deux temps : d'abord par `listen` (adresse et
> port), puis, parmi les candidats, par `server_name` comparé à l'en-tête
> `Host`. Si aucun `server_name` ne correspond, il prend le serveur marqué
> `default_server` sur ce `listen`, ou **le premier déclaré** en son absence.
> Avant ta modification, le site `default` du paquet (marqué
> `default_server`) répondait aux requêtes sans `Host` connu ; après, c'est
> ton vhost. En production, on garde un serveur par défaut explicite qui
> répond `444` (fermeture sans réponse) ou `404` : `server { listen 80
> default_server; server_name _; return 444; }` — sinon le premier client
> qui tape l'IP tombe sur le vhost qui se trouve être premier par ordre
> alphabétique, et un scanner voit ton application sous un mauvais nom.
>
> `-H 'Host: ...'` est la façon de tester un vhost **avant** de toucher au
> DNS ou à `/etc/hosts` — et de vérifier après une migration que le nouveau
> serveur répond bien pour ce nom. `--resolve nom:port:ip` fait la même chose
> en HTTPS, où `Host` seul ne suffit pas (le SNI doit aussi correspondre).

---

<a id="e15-4"></a>**[E15.4](README.md#e15-4)** — *Trois locations avec `X-Location`, preuve par `curl -sI`, puis `alias` → `root`.*

```nginx
    location / {
        try_files $uri $uri/ =404;
        add_header X-Location "racine";
    }
    location /docs/ {
        alias /srv/www/factura-demo/docs/;
        add_header X-Location "docs";
    }
    location /api/ {
        proxy_pass http://127.0.0.1:8001;
        add_header X-Location "api";
    }
```

```bash
for u in / /docs/ /docs/index.html /api/health /static/app.js; do
  printf '%-18s ' "$u"
  curl -s -D - -o /dev/null "http://factura-demo.lab.local$u" \
    | grep -E '^(HTTP|X-Location)' | tr '\n' ' '; echo
done
# /                200 racine   /docs/ 200 docs   /docs/index.html 200 docs
# /api/health      200 api      /static/app.js 200 racine
```

Avec `root /srv/www/factura-demo/docs/;` à la place d'`alias`, `/docs/`
répond 404 et `error.log` montre : `open()
"/srv/www/factura-demo/docs/docs/index.html" failed (2: No such file or
directory)`.

> [!NOTE]
> **Pourquoi**
>
> Le tag `X-Location` est la méthode de preuve la plus rapide : elle montre
> quel bloc a **réellement** traité chaque URI, sans interpréter la règle de
> tête. `/static/app.js` tombe dans `/` parce qu'aucune location `/static/`
> n'existe — le préfixe le plus long qui correspond est `/`. `/docs/index.html`
> tombe dans `/docs/` et non dans `/` : entre deux préfixes qui
> correspondent, le plus long gagne, quel que soit l'ordre dans le fichier.
>
> Le passage `alias` → `root` illustre la concaténation : `root` + URI
> complète = `/srv/www/factura-demo/docs/` + `/docs/index.html`. Le chemin
> tenté est écrit tel quel dans `error.log` : lire ce chemin suffit, on n'a
> pas besoin de « comprendre » la conf pour trouver la faute. Note que
> `index index.html` hérité du `server` fait que `/docs/` cherche
> `index.html` dans le répertoire résolu.

> [!WARNING]
> **Piège**
>
> Le `add_header` posé dans `location /api/` désactive l'héritage des
> `add_header` du `server` (Q15.7). Ici il n'y en a pas encore ; quand tu
> ajouteras HSTS en L15.2, pense à retirer ces tags de diagnostic ou à
> utiliser un `include` commun.

---

<a id="e15-5"></a>**[E15.5](README.md#e15-5)** — *`proxy_pass` avec et sans URI finale ; `Host` et `X-Forwarded-For` reçus.*

```bash
curl -s http://factura-demo.lab.local/api/whoami | jq '{path, headers}'
```

Sans barre (`proxy_pass http://127.0.0.1:8001;`) :

```json
{ "path": "/api/whoami",
  "headers": { "Host": "127.0.0.1:8001", "Connection": "close" } }
```

Avec barre (`proxy_pass http://127.0.0.1:8001/;`) : `"path": "/whoami"` —
que la mini-API ne connaît pas : 404 du backend (`upstream_status 404`
dans le journal, pas une erreur nginx).

Correction des en-têtes :

```nginx
    location /api/ {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
```

```json
{ "path": "/api/whoami",
  "headers": { "Host": "factura-demo.lab.local",
               "X-Forwarded-For": "10.10.10.10",
               "X-Forwarded-Proto": "http", "X-Real-IP": "10.10.10.10" } }
```

> [!NOTE]
> **Pourquoi**
>
> Par défaut, nginx réécrit deux en-têtes en les envoyant à l'upstream :
> `Host` devient `$proxy_host` (l'hôte de `proxy_pass`, ici `127.0.0.1:8001`)
> et `Connection` devient `close` (une connexion par requête). Tout le reste
> est transmis tel quel. Le backend ne voit donc **ni le nom demandé par le
> client, ni son adresse** — il voit `127.0.0.1` comme source TCP et
> `127.0.0.1:8001` comme `Host`. Une application qui construit des URL
> absolues (redirections après login, liens dans un e-mail) les construit
> alors avec `127.0.0.1:8001`.
>
> `$proxy_add_x_forwarded_for` = la valeur reçue de `X-Forwarded-For` (si le
> client ou un proxy amont en avait mis une), virgule, `$remote_addr`. C'est
> une **liste** : le dernier élément est celui qu'on peut croire (posé par
> nous), les précédents sont déclaratifs. `$remote_addr` dans `X-Real-IP` est
> la version simple, une seule valeur, celle que nginx a vue. Le backend ne
> doit faire confiance à ces en-têtes que s'il n'est joignable que par ce
> nginx (d'où le `bind 127.0.0.1` de la mini-API et de Gunicorn) : un client
> qui parle directement au backend peut y écrire ce qu'il veut.

---

<a id="e15-6"></a>**[E15.6](README.md#e15-6)** — *`upstream` à deux instances, `log_format` avec temps, 10 requêtes, instance arrêtée.*

```nginx
# /etc/nginx/conf.d/factura-upstream.conf
upstream factura_api {
    server 127.0.0.1:8001;
    server 127.0.0.1:8002;
    keepalive 16;
}
log_format factura '$remote_addr - $remote_user [$time_local] "$request" '
    '$status $body_bytes_sent "$http_referer" "$http_user_agent" '
    'rt=$request_time urt=$upstream_response_time ua=$upstream_addr '
    'us=$upstream_status';
```

```nginx
# dans le server
    access_log /var/log/nginx/factura.access.log factura;
    error_log  /var/log/nginx/factura.error.log warn;
    location /api/ {
        proxy_pass http://factura_api;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        # ... proxy_set_header Host etc.
    }
```

```bash
sudo nginx -t && sudo systemctl reload nginx
/opt/factura/bin/tir.sh http://factura-demo.lab.local/api/whoami 10
sudo grep -o 'ua=[0-9.:]*' /var/log/nginx/factura.access.log | sort | uniq -c
#   5 ua=127.0.0.1:8001
#   5 ua=127.0.0.1:8002
sudo systemctl stop mini-api@8002
/opt/factura/bin/tir.sh http://factura-demo.lab.local/api/whoami 10
#  10 200                      <- l'utilisateur ne voit rien
sudo tail -3 /var/log/nginx/factura.error.log
# [error] ... connect() failed (111: Connection refused) while connecting
#   to upstream, ... upstream: "http://127.0.0.1:8002/api/whoami"
sudo grep -oE 'ua=[^ ]+(, [^ ]+)*' /var/log/nginx/factura.access.log | tail -3
# ua=127.0.0.1:8002, 127.0.0.1:8001      <- deux adresses : tentative puis repli
sudo systemctl start mini-api@8002
```

> [!NOTE]
> **Pourquoi**
>
> Un `upstream` sans directive d'équilibrage fait du **round-robin pondéré**
> (poids 1 par défaut) : les requêtes alternent. `$upstream_addr` dans le
> journal est la preuve — et quand nginx a dû essayer plusieurs serveurs pour
> une même requête, la variable contient **toutes** les adresses tentées,
> séparées par des virgules, dans l'ordre ; `$upstream_status` et
> `$upstream_response_time` sont des listes parallèles.
>
> Quand 8002 refuse la connexion, `proxy_next_upstream` (par défaut `error
> timeout`) fait retenter la requête sur le serveur suivant : l'utilisateur
> reçoit un 200, seul `error.log` trahit la panne. Après `max_fails` échecs
> (1 par défaut) en `fail_timeout` (10 s), nginx marque le serveur
> indisponible pendant 10 s et ne l'essaie plus, puis le retente. Ce
> comportement est excellent pour la disponibilité et terrible pour la
> supervision si on ne regarde que les codes HTTP : la métrique à surveiller
> est le nombre de lignes `connect() failed` dans `error.log` ou, avec
> l'exporter, `nginx_upstream_server_health`. C'est pourquoi le défi D15
> demande de vérifier que **les deux** instances ont servi du trafic.
>
> `keepalive 16` garde jusqu'à 16 connexions inactives ouvertes vers
> l'upstream par worker ; il n'a d'effet que si `proxy_http_version 1.1` et
> `proxy_set_header Connection ""` sont posés (sinon nginx envoie
> `Connection: close` et le backend ferme). Le gain : pas de poignée de main
> TCP par requête, et moins de ports en `TIME_WAIT`.

---

<a id="e15-7"></a>**[E15.7](README.md#e15-7)** — *HTTPS : certificat, `listen 443 ssl http2`, TLS 1.2/1.3, HSTS, 301 depuis 80, vérification.*

```bash
sudo install -d -m 0750 -o root -g root /etc/nginx/ssl
# variante rapide, si le certificat de L18.4 n'existe pas
sudo openssl req -x509 -newkey rsa:2048 -nodes -days 397 \
  -keyout /etc/nginx/ssl/factura-demo.key \
  -out /etc/nginx/ssl/factura-demo.crt \
  -subj '/CN=factura-demo.lab.local' \
  -addext 'subjectAltName=DNS:factura-demo.lab.local,IP:10.10.10.11'
sudo chmod 0600 /etc/nginx/ssl/factura-demo.key
```

```nginx
server {
    listen 80; listen [::]:80;
    server_name factura-demo.lab.local;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl http2; listen [::]:443 ssl http2;
    server_name factura-demo.lab.local;
    ssl_certificate     /etc/nginx/ssl/factura-demo.crt;
    ssl_certificate_key /etc/nginx/ssl/factura-demo.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    add_header Strict-Transport-Security "max-age=15768000" always;
    root /srv/www/factura-demo;
    index index.html;
    # ... locations
}
```

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -vk https://factura-demo.lab.local/ -o /dev/null 2>&1 \
  | grep -E 'SSL connection|ALPN|HTTP/2 200|strict-transport'
# * SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
# * ALPN: server accepted h2
# < HTTP/2 200
# < strict-transport-security: max-age=15768000
curl -sI http://factura-demo.lab.local/ | head -3
# HTTP/1.1 301 Moved Permanently ... Location: https://factura-demo.lab.local/
openssl s_client -connect 10.10.10.11:443 -servername factura-demo.lab.local \
  </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -dates -ext subjectAltName
```

> [!NOTE]
> **Pourquoi**
>
> Deux blocs `server` : le port 80 ne fait **que** rediriger (aucun `root`,
> aucune location — c'est ce qui rend la boucle de Q15.6 impossible), le 443
> sert. `$host` plutôt que `$server_name` dans la redirection : si le vhost
> répond à plusieurs noms, on redirige vers celui que le client a demandé.
> `$request_uri` (l'URI brute avec la chaîne de requête) plutôt que `$uri`
> (normalisée, sans paramètres) pour ne rien perdre.
>
> `http2` sur `listen` (syntaxe nginx ≤ 1.24 ; `http2 on;` séparé depuis
> 1.25.1) : nginx annonce `h2` par ALPN pendant la poignée de main TLS ; le
> client qui le supporte l'utilise, les autres restent en HTTP/1.1 sur la
> même socket. Côté backend rien ne change. `ssl_prefer_server_ciphers off`
> est la recommandation actuelle : laisser le client choisir parmi des suites
> toutes sûres (en TLS 1.3 la question ne se pose plus). `ssl_session_cache`
> évite une poignée de main complète à chaque reconnexion ; `ssl_session_tickets
> off` parce que les tickets, chiffrés avec une clé que nginx ne fait pas
> tourner seul, affaiblissent la *forward secrecy*.
>
> HSTS (`max-age` en secondes ; 15 768 000 = six mois, un an minimum pour la
> liste de préchargement) dit au navigateur : « pendant ce temps, ne me
> contacte plus jamais en HTTP ». `always` l'ajoute aussi aux erreurs. Le
> piège : une fois HSTS reçu, un certificat invalide n'est **plus
> contournable** par l'utilisateur (« continuer quand même » disparaît). On
> ne pose HSTS qu'une fois le certificat en ordre, et on commence avec un
> `max-age` court.

> [!WARNING]
> **Piège**
>
> `-addext subjectAltName` est indispensable depuis 2017 : Chrome, Firefox et
> `curl` ignorent le `CN` et n'acceptent que les SAN. Un certificat sans SAN
> donne `curl: (60) SSL: no alternative certificate subject name matches`
> même si le `CN` est bon. Et la clé en `0600 root` : nginx lit les
> certificats **en root** au démarrage avant de passer à `www-data`, la clé
> n'a donc jamais besoin d'être lisible par `www-data`.

---

<a id="e15-8"></a>**[E15.8](README.md#e15-8)** — *`limit_req` sur `/api/login`, `auth_basic` sur `/docs/`, `allow/deny` sur `/api/metrics`.*

```nginx
# conf.d/factura-upstream.conf (contexte http)
limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;
```

```nginx
    location = /api/login {
        limit_req zone=login burst=5 nodelay;
        limit_req_status 429;
        proxy_pass http://factura_api;
        # ... proxy_set_header (répétés, ou include)
    }
    location /docs/ {
        alias /srv/www/factura-demo/docs/;
        auth_basic "Documentation";
        auth_basic_user_file /etc/nginx/htpasswd-factura;
    }
    location = /api/metrics {
        allow 10.10.10.14;
        deny all;
        proxy_pass http://factura_api;
    }
```

```bash
sudo htpasswd -cB /etc/nginx/htpasswd-factura ops   # -c : créer ; -B : bcrypt
sudo chown root:www-data /etc/nginx/htpasswd-factura
sudo chmod 0640 /etc/nginx/htpasswd-factura
sudo nginx -t && sudo systemctl reload nginx
/opt/factura/bin/tir.sh http://factura-demo.lab.local/api/login 12
#   6 200      6 429
curl -sI http://factura-demo.lab.local/docs/ | head -1          # 401
curl -sI -u ops:secret http://factura-demo.lab.local/docs/ | head -1   # 200
curl -sI http://factura-demo.lab.local/api/metrics | head -1   # lab-adm : 403
```

> [!NOTE]
> **Pourquoi**
>
> Les trois mécanismes agissent à des phases différentes du traitement :
>
> * `limit_req` : phase *preaccess*, avant toute autre chose. La zone est un
>   segment de mémoire partagée entre workers (`10m` ≈ 160 000 adresses en
>   IPv4) indexé sur la clé — `$binary_remote_addr` (4 octets) plutôt que
>   `$remote_addr` (chaîne, 15 octets) pour économiser la zone. Le rejet
>   ne touche jamais le backend.
> * `auth_basic` : phase *access*. nginx exige `Authorization: Basic
>   base64(user:mdp)`, compare au fichier (bcrypt, `-B`, résiste aux attaques
>   hors ligne contrairement au MD5 historique). Le fichier est lu par les
>   workers, donc lisible par `www-data` mais pas par tous (`0640
>   root:www-data`), et **hors** de `root` — sinon il est téléchargeable.
>   Sans TLS, Basic transmet le mot de passe en clair : c'est un complément
>   de L15.2, pas un substitut.
> * `allow`/`deny` : phase *access* aussi, évalués **dans l'ordre**, premier
>   qui correspond gagne — `deny all` doit donc être en dernier. Le
>   `X-Forwarded-For` n'entre pas en jeu : c'est l'adresse source TCP
>   (`$remote_addr`) qui est testée, sauf avec le module `realip`.
>
> `location = /api/login` en exact : la requête ne parcourt pas les regex,
> et `/api/login/autre` n'est pas concerné. C'est une location **sœur** de `/api/`, pas une location imbriquée : elle n'hérite de rien de
> `/api/`, et ses propres `proxy_set_header` annulent ceux d'un éventuel niveau `server` (même règle que `add_header`) : soit on les répète, soit on les
> place dans un `snippets/proxy-factura.conf` inclus partout.

---

<a id="e15-9"></a>**[E15.9](README.md#e15-9)** — *`psql` : bases et tailles, rôles, tables, `\d+ invoices`, `\x`, `\timing`, requête lente.*

```bash
sudo -u postgres psql
```

```text
\l+                       -- bases, propriétaires, encodage, taille
\du                       -- rôles et attributs (Superuser, Create DB...)
\c factura_demo
\dt+                      -- tables du schéma courant, taille
\d+ invoices              -- colonnes, index, contraintes, FK, taille
\x                        -- affichage étendu (une colonne par ligne)
\timing
\i /opt/factura/bin/requete-lente.sql
-- Time: 2885.489 ms (00:02.885)   -- 0,3 à 3 s selon la machine et le cache
\q
```

En une ligne, pour un script :
`sudo -u postgres psql -d factura_demo -Atc "SELECT pg_size_pretty(pg_database_size('factura_demo'))"`.

> [!NOTE]
> **Pourquoi**
>
> Les méta-commandes `\` sont exécutées par `psql` **côté client** : elles se
> traduisent en requêtes sur le catalogue (`pg_database`, `pg_roles`,
> `pg_class`, `pg_attribute`, `pg_index`) ; `psql -E` affiche ces requêtes
> sous-jacentes, ce qui est la meilleure façon d'apprendre le catalogue.
> Le `+` demande les colonnes supplémentaires (taille, description). `\d+
> invoices` révèle ce qu'un `SELECT` ne dit pas : il n'existe **aucun index**
> sur `customer_id` — seule la clé primaire `invoices_pkey` est indexée, et
> la contrainte `FOREIGN KEY (customer_id)` n'en crée pas un automatiquement
> (contrairement à MySQL).
>
> `\x` bascule en affichage vertical, indispensable sur `pg_stat_activity`
> ou `\d+` d'une table large ; `\x auto` ne le fait que si la ligne est trop
> large. `\timing` mesure côté client (aller-retour inclus), ce qui est ce
> que l'application subit. `-A` (non aligné) `-t` (sans en-tête) `-c` sont
> la combinaison pour les scripts : une valeur, rien d'autre.

---

<a id="e15-10"></a>**[E15.10](README.md#e15-10)** — *`EXPLAIN (ANALYZE, BUFFERS)`, index `CONCURRENTLY`, comparaison, `pg_stat_user_tables`.*

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT i.number, i.issued_on, i.status,
       (SELECT sum(l.qty * l.unit_cents) FROM invoice_lines l
         WHERE l.invoice_id = i.id) / 100.0 AS total_eur
FROM invoices i
WHERE i.customer_id = (SELECT id FROM customers
                       WHERE email = 'client4242@exemple.fr')
ORDER BY i.issued_on DESC;
```

Avant (extrait, simplifié — sur 2 vCPU tu verras un `Gather Merge` et un
`Parallel Seq Scan` sur `invoices`) :

```text
 Sort  (actual time=2871.2..2871.2 rows=18 loops=1)
   InitPlan 2 (returns $1)
     ->  Seq Scan on customers  (rows=1)  Filter: (email = ...)
           Rows Removed by Filter: 4999
   ->  Seq Scan on invoices i  (actual time=... rows=18 loops=1)
         Filter: (customer_id = $1)
         Rows Removed by Filter: 99982
         Buffers: shared hit=1823
   SubPlan 1
     ->  Aggregate  (actual time=158.9..158.9 rows=1 loops=18)
           Buffers: shared hit=45000
           ->  Seq Scan on invoice_lines l  (rows=3 loops=18)
                 Filter: (invoice_id = i.id)
                 Rows Removed by Filter: 299997
 Execution Time: 2871.5 ms
```

Trois parcours séquentiels, dont un exécuté **18 fois** (`loops=18`) sur
300 000 lignes : 5,4 millions de lignes lues et 45 000 blocs de 8 Ko
visités pour garder 54 lignes. Le temps absolu dépend de la machine (de
0,2 s tout en cache sur un poste rapide à 3 s sur la VM), le **rapport**
avec la version indexée non.

```sql
CREATE INDEX CONCURRENTLY invoice_lines_invoice_id_idx
  ON invoice_lines (invoice_id);
CREATE INDEX CONCURRENTLY invoices_customer_id_idx ON invoices (customer_id);
CREATE INDEX CONCURRENTLY customers_email_idx ON customers (email);
```

Après : `Index Scan using invoices_customer_id_idx`, `Index Scan using
invoice_lines_invoice_id_idx ... loops=18`, `Buffers: shared hit=~120`,
`Execution Time: 1.9 ms`. Facteur 100 à 1 500 selon le point de départ.

```sql
SELECT relname, seq_scan, idx_scan FROM pg_stat_user_tables;
-- rejouer la requête : idx_scan augmente, seq_scan reste
SELECT indexrelname, idx_scan FROM pg_stat_user_indexes
 WHERE relname = 'invoice_lines';
```

> [!NOTE]
> **Pourquoi**
>
> La lecture d'un plan se fait **de l'intérieur vers l'extérieur** et en
> suivant `loops` : un nœud à 159 ms exécuté 18 fois coûte 2,9 s. Les
> colonnes `actual time` sont cumulées par nœud parent, `rows` est par
> boucle. `Rows Removed by Filter` est l'indicateur d'index manquant ; sur
> le nœud `customers` c'est 4 999 lignes pour en garder une — un index sur
> `email` est justifié aussi, même si son gain absolu est faible ici.
>
> `CREATE INDEX CONCURRENTLY` fait deux passes sur la table et attend la fin
> des transactions en cours, sans jamais bloquer les écritures ; il ne peut
> pas s'exécuter dans une transaction, et s'il échoue il laisse un index
> `INVALID` (visible dans `\d`, à supprimer et refaire). Sans `CONCURRENTLY`,
> le verrou `SHARE` bloque `INSERT`/`UPDATE`/`DELETE` pendant la
> construction — quelques secondes ici, des minutes sur des dizaines de
> millions de lignes.
>
> Pourquoi le planificateur ne trouvait-il pas mieux ? Il choisit le meilleur
> plan **parmi les possibles** : sans index, le seul accès à `invoice_lines`
> par `invoice_id` est le parcours complet. Les statistiques étaient bonnes
> (estimations proches du réel) : ce n'est pas un problème d'`ANALYZE`, c'est
> un problème de structure. C'est la distinction à faire en entretien entre
> « mauvais plan » (statistiques, `work_mem`, paramètres du planificateur) et
> « pas de bon plan possible » (schéma, index).

---

<a id="e15-11"></a>**[E15.11](README.md#e15-11)** — *Requêtes actives et durée, annuler la plus ancienne ; bloqueur de `verrou-demo.sh`.*

```bash
/opt/factura/bin/charge-sql.sh 3 120 &
sudo -u postgres psql -d factura_demo
```

```sql
SELECT pid, usename, state, now() - query_start AS age, left(query, 50)
  FROM pg_stat_activity
 WHERE state = 'active' AND pid <> pg_backend_pid()
 ORDER BY age DESC;
SELECT pg_cancel_backend(<pid le plus ancien>);   -- true
-- la session existe toujours, en 'idle' : elle relance la boucle
```

Verrou :

```sql
-- terminal 3, bloqué :
UPDATE invoices SET status = 'paid' WHERE id = 42;
-- terminal postgres :
SELECT pid, pg_blocking_pids(pid) AS bloque_par, state,
       now() - state_change AS depuis, left(query, 50)
  FROM pg_stat_activity WHERE cardinality(pg_blocking_pids(pid)) > 0;
--  pid  | bloque_par |  state | depuis   | left
-- 6120  | {6118}     | active | 00:00:41 | UPDATE invoices SET status = ...
SELECT pid, state, now() - state_change AS depuis, left(query, 50)
  FROM pg_stat_activity WHERE pid = 6118;
--  6118 | active | ... | SELECT pg_sleep(300);     (transaction ouverte)
SELECT locktype, relation::regclass, mode, granted
  FROM pg_locks WHERE pid IN (6118, 6120) AND relation IS NOT NULL;
SELECT pg_terminate_backend(6118);
-- le terminal 3 obtient UPDATE 1 immédiatement
```

> [!NOTE]
> **Pourquoi**
>
> `pg_cancel_backend(pid)` envoie `SIGINT` au processus serveur : la requête
> en cours est annulée (`ERROR: canceling statement due to user request`),
> la session survit et, si elle était dans une transaction, celle-ci est
> annulée. `pg_terminate_backend(pid)` envoie `SIGTERM` : la session est
> fermée, le client reçoit `FATAL: terminating connection due to
> administrator command`. Le premier est la réponse à « cette requête est
> trop longue », le second à « cette session ne devrait pas exister ». Les
> deux exigent d'être superuser ou membre de `pg_signal_backend` (ou de
> posséder la session).
>
> Dans l'exemple du verrou, le bloqueur est `active` (il exécute
> `pg_sleep`), ce qui est artificiel : dans la vraie vie il est `idle in
> transaction` — un `UPDATE` fait, puis plus rien, la transaction jamais
> validée. C'est ce que `pg_blocking_pids()` (PG 9.6+) rend trivial à
> trouver ; avant, il fallait la fameuse jointure `pg_locks` ⋈ `pg_locks`
> sur `granted = false`. `pg_locks` reste utile pour voir **quel** verrou :
> `RowExclusiveLock` sur `invoices` pour les deux (compatibles entre eux),
> et un verrou `transactionid` — le vrai conflit est sur la **ligne** 42,
> matérialisé par l'attente sur l'identifiant de transaction du bloqueur.
> `log_lock_waits = on` journalise toute attente de plus de `deadlock_timeout`
> (1 s) avec les deux PID : c'est le réglage à avoir en production pour
> retrouver ces situations après coup.

---

<a id="e15-12"></a>**[E15.12](README.md#e15-12)** — *Taille avec et sans index, copie, `DELETE` 20 %, `n_dead_tup`, `VACUUM`, taille.*

```sql
SELECT pg_size_pretty(pg_relation_size('invoice_lines')) AS table_seule,
       pg_size_pretty(pg_indexes_size('invoice_lines')) AS index,
       pg_size_pretty(pg_total_relation_size('invoice_lines')) AS total;
CREATE TABLE lignes_copie AS SELECT * FROM invoice_lines;
DELETE FROM lignes_copie WHERE id % 5 = 0;             -- 60 000 lignes
SELECT n_live_tup, n_dead_tup, last_autovacuum
  FROM pg_stat_user_tables WHERE relname = 'lignes_copie';
--  240000 | 60000 | (null)
SELECT pg_size_pretty(pg_relation_size('lignes_copie'));   -- 20 MB
VACUUM (VERBOSE) lignes_copie;
-- INFO: ... pages: 0 removed, 2xxx remain ...
--       tuples: 60000 removed, 240000 remain ...
SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'lignes_copie'; -- 0
SELECT pg_size_pretty(pg_relation_size('lignes_copie'));   -- 20 MB : inchangé
DROP TABLE lignes_copie;
```

Pour que la taille diminue : `VACUUM FULL lignes_copie` (réécriture
complète, verrou exclusif) ou `pg_repack`.

> [!NOTE]
> **Pourquoi**
>
> Les trois fonctions de taille répondent à trois questions :
> `pg_relation_size` = le *heap* de la table (sans index ni TOAST),
> `pg_indexes_size` = tous ses index, `pg_total_relation_size` = tout, TOAST
> compris (les valeurs longues stockées à part). Une table dont les index
> pèsent plus que les données n'est pas anormale (beaucoup d'index, ou
> colonnes courtes) ; une table dont le `total` est dix fois `n_live_tup ×
> largeur moyenne` est gonflée.
>
> Le `DELETE` ne libère rien : il pose un marqueur `xmax` sur chaque version
> de ligne. `n_dead_tup` (estimation entretenue par le collecteur de
> statistiques) passe à 60 000. `VACUUM` les trouve, vérifie qu'aucune
> transaction ne peut encore les voir, et inscrit l'espace dans la *free
> space map* : les prochains `INSERT` le réutiliseront. Mais les pages
> restent allouées au fichier — il ne tronque que les pages **vides en fin
> de fichier**. Comme les lignes supprimées (`id % 5`) sont réparties
> partout, aucune page n'est vide : la taille ne bouge pas. C'est le
> comportement voulu : rendre l'espace au système de fichiers impose une
> réécriture, donc un verrou, donc une décision humaine (`VACUUM FULL` la
> nuit, ou `pg_repack`).
>
> `last_autovacuum` est `null` sur la copie : l'autovacuum ne s'est pas
> encore déclenché (seuil : 50 + 20 % de 300 000 = 60 050 lignes mortes ; on
> est juste en dessous). Sur une table de production active, il passe
> régulièrement et `n_dead_tup` oscille — c'est ce qu'il faut vérifier, pas
> qu'il soit à zéro.

---

<a id="e15-13"></a>**[E15.13](README.md#e15-13)** — *Connexion sans mot de passe depuis `lab-web` : variable, `.pgpass`, `0644`, trace dans `ps`.*

```bash
# 1. variable d'environnement (visible dans /proc/PID/environ du processus)
PGPASSWORD='Factura-App-2026' psql -h 10.10.10.12 -U factura_app \
  -d factura_demo -Atc 'SELECT count(*) FROM invoices'
# 2. fichier .pgpass
cat > ~/.pgpass <<'EOF'
10.10.10.12:5432:factura_demo:factura_app:Factura-App-2026
EOF
chmod 0600 ~/.pgpass
psql -h 10.10.10.12 -U factura_app -d factura_demo -Atc 'SELECT 1'
# 3. mauvais droits
chmod 0644 ~/.pgpass
psql -h 10.10.10.12 -U factura_app -d factura_demo -Atc 'SELECT 1'
# WARNING: password file "/home/mathieu/.pgpass" has group or world access;
# permissions should be u=rw (0600) or less
# Password for user factura_app:            <- le fichier est IGNORÉ
chmod 0600 ~/.pgpass
```

Aucune des deux méthodes ne met le mot de passe dans la ligne de commande,
donc aucune n'apparaît dans `ps`. En revanche `PGPASSWORD` est lisible
dans `/proc/PID/environ` par le propriétaire du processus (et root), et
il fuit dans tout sous-processus et dans les journaux qui capturent
l'environnement (`systemctl show`, `journalctl` avec certaines unités,
scripts qui font `env`).

> [!NOTE]
> **Pourquoi**
>
> `libpq` cherche le mot de passe dans cet ordre : paramètre de connexion
> (`password=` dans une URI — celui-là **est** dans `ps`), `PGPASSWORD`,
> `PGPASSFILE` ou `~/.pgpass`, puis prompt. Le format `.pgpass` accepte `*`
> comme joker sur chaque champ (`*:*:*:factura_app:mdp`), et la première
> ligne qui correspond gagne. Le contrôle de droits est fait par libpq
> lui-même (pas par le noyau) : c'est un garde-fou contre le cas classique
> d'un fichier créé avec `umask 022` puis oublié — et il **ignore** le
> fichier au lieu de refuser la connexion, d'où le prompt interactif, ou en
> batch (`-w`, cron, `< /dev/null`) l'erreur `fe_sendauth: no password
> supplied`. C'est BF15.6.
>
> Pour un service systemd, la bonne place est `EnvironmentFile=` avec un
> fichier `0640 root:groupe-du-service` — c'est ce que fait `/etc/factura/
> db.env` — ou, mieux, un `.pgpass` dans le home du compte de service, ou un
> fichier de service `~/.pg_service.conf` (`[factura]` + `host=`, `dbname=`,
> `user=`, et `PGSERVICE=factura`). Le compte `postgres` en `peer` local n'a
> besoin de rien : c'est pourquoi les sauvegardes tournent sous ce compte.

---

<a id="e15-14"></a>**[E15.14](README.md#e15-14)** — *`redis-cli` : `PING`, version, TTL, hash, file, 200 tours, compter sans `KEYS`, grosses clés.*

```bash
redis-cli PING                                  # PONG
redis-cli INFO server | grep -E 'redis_version|uptime_in_days'
redis-cli SET sess:abc 'donnees' EX 60          # ou SETEX sess:abc 60 donnees
redis-cli TTL sess:abc                          # 57 ... puis -2 quand expiré
redis-cli HSET user:1 name Mathieu ville Lyon
redis-cli HGETALL user:1
redis-cli LPUSH factura:jobs '{"id":1}' '{"id":2}' '{"id":3}'
redis-cli LLEN factura:jobs                     # 3
redis-cli BRPOP factura:jobs 5                  # bloque jusqu'à 5 s : {"id":1}
python3 /opt/factura/bin/redis-app.py -n 200
redis-cli --scan --pattern 'sess:*' | wc -l     # 200 (+ celles d'avant)
redis-cli DBSIZE
redis-cli --bigkeys
# Biggest list found 'factura:jobs' has 2xx items
# Biggest hash found 'user:42' has 2 fields ...
```

> [!NOTE]
> **Pourquoi**
>
> Chaque structure répond à un besoin d'application, et un exploitant doit
> les reconnaître pour comprendre ce que fait l'application dans Redis :
>
> * **string** avec `EX` : la session, le cache d'une page, un verrou
>   (`SET lock:x 1 NX EX 30`), un compteur (`INCR` est atomique). `TTL` = -1
>   sans expiration, -2 clé absente.
> * **hash** : un objet avec des champs, lisible champ par champ (`HGET`),
>   compact en mémoire pour les petits objets (encodage `listpack`).
> * **list** : la file. `LPUSH` à gauche, `BRPOP` à droite = FIFO ; `BRPOP`
>   **bloque** le client jusqu'à ce qu'un élément arrive (ou timeout) —
>   c'est ce qui permet un worker sans boucle d'attente active. Un élément
>   pris est retiré : si le worker meurt avant de le traiter, il est perdu
>   (« au plus une fois ») ; `LMOVE` vers une liste de travail en cours
>   permet le « au moins une fois ».
> * **set** : appartenance (`SISMEMBER`), unicité ; **sorted set** :
>   classement, files à priorité, fenêtres temporelles.
>
> `--scan` enchaîne des `SCAN` de 10 clés par défaut ; `--bigkeys` fait de
> même en appelant `STRLEN`/`LLEN`/`HLEN`/`SCARD`/`ZCARD` sur chaque clé,
> sans bloquer (il est prévu pour la production) ; `--memkeys` utilise
> `MEMORY USAGE`, plus précis mais plus lent. `OBJECT ENCODING clé` montre
> l'encodage interne (`listpack`, `quicklist`, `int`, `embstr`) — utile
> pour comprendre pourquoi une clé pèse ce qu'elle pèse.

---

<a id="e15-15"></a>**[E15.15](README.md#e15-15)** — *`BGSAVE`, preuve de fin, copie horodatée, AOF à chaud, `CONFIG REWRITE`, fichiers.*

```bash
redis-cli BGSAVE                                # Background saving started
redis-cli INFO persistence \
  | grep -E 'rdb_bgsave_in_progress|rdb_last_save_time|rdb_last_bgsave_status'
# rdb_bgsave_in_progress:0  rdb_last_bgsave_status:ok
redis-cli LASTSAVE                              # horodatage epoch
date -d @"$(redis-cli LASTSAVE)"
sudo cp /var/lib/redis/dump.rdb ~/lab15/backups/dump-$(date +%Y%m%d-%H%M).rdb
sudo chown mathieu: ~/lab15/backups/dump-*.rdb
redis-cli CONFIG SET appendonly yes             # OK ; réécriture AOF initiale
redis-cli CONFIG REWRITE                        # persiste dans redis.conf
sudo grep -n '^appendonly' /etc/redis/redis.conf   # appendonly yes
sudo ls -la /var/lib/redis/ /var/lib/redis/appendonlydir/
# dump.rdb
# appendonlydir/appendonly.aof.1.base.rdb
# appendonlydir/appendonly.aof.1.incr.aof
# appendonlydir/appendonly.aof.manifest
```

> [!NOTE]
> **Pourquoi**
>
> `BGSAVE` fait un `fork()` : l'enfant écrit `temp-<pid>.rdb` puis le
> renomme en `dump.rdb` — le renommage est atomique, donc `dump.rdb` est
> **toujours** un fichier complet et cohérent, même pendant une sauvegarde
> en cours. C'est pourquoi le copier à n'importe quel moment est sûr
> (alors que copier `appendonlydir/` pendant une réécriture ne l'est pas).
> `SAVE` (sans `BG`) fait la même chose dans le processus principal, en
> bloquant tout : à ne jamais utiliser en production.
>
> `CONFIG SET appendonly yes` déclenche une réécriture AOF (`BGREWRITEAOF`)
> pour créer le fichier de base à partir de l'état courant ; ensuite chaque
> écriture est ajoutée à l'`.incr.aof`. Redis 7 a remplacé l'AOF monolithique
> par ce répertoire multi-fichiers : un fichier de base (au format RDB par
> défaut, `aof-use-rdb-preamble yes`), des incréments, et un manifeste. Au
> démarrage, si l'AOF est activé, c'est lui qui est chargé — `dump.rdb` ne
> sert plus qu'aux copies.
>
> `CONFIG REWRITE` réécrit `redis.conf` en conservant les commentaires et
> en modifiant seulement les directives qui diffèrent de la valeur chargée :
> c'est le seul moyen propre de rendre un `CONFIG SET` persistant. Il exige
> que Redis puisse écrire le fichier — sur Ubuntu `redis.conf` appartient à
> `redis`, c'est prévu pour. Sans `REWRITE`, le prochain restart repart de
> l'ancien fichier, et l'AOF disparaît silencieusement.

---

<a id="e15-16"></a>**[E15.16](README.md#e15-16)** — *Unités chargées, `User=`, sockets, qui peut se connecter, `[Unit]` d'une application locale.*

```bash
systemctl cat postgresql@16-main.service | grep -E '^(User|ExecStart|Type)'
# Type=forking
# ExecStart=-/usr/bin/pg_ctlcluster --skip-systemctl-redirect %i start
# (pas de User= : pg_ctlcluster passe sous le propriétaire du cluster,
#  postgres — colonne Owner de pg_lsclusters)
systemctl cat redis-server.service \
  | grep -E '^(User|ExecStart|Type|ReadWrite|Protect)'
# Type=notify  User=redis
# ExecStart=/usr/bin/redis-server /etc/redis/redis.conf --supervised systemd
systemctl cat postgresql.service | grep -E '^(Type|RemainAfterExit|ExecStart)'
# Type=oneshot  RemainAfterExit=on  ExecStart=/bin/true
ls -la /run/postgresql/
# drwxrwsr-x postgres postgres .   srwxrwxrwx postgres postgres .s.PGSQL.5432
ls -la /run/redis/
# drwxr-sr-x redis redis .   (redis-server.pid ; pas de socket par défaut)
```

PostgreSQL : tout le monde peut ouvrir la socket ; `pg_hba` (`local all all
peer`) exige compte Unix = rôle. Redis : socket non activée ; si on
décommente `unixsocket /run/redis/redis-server.sock` et `unixsocketperm
770`, seuls `redis` et le groupe `redis` peuvent l'ouvrir, puis l'ACL
s'applique.

```ini
[Unit]
Description=Application locale Factura (lab-db)
After=network-online.target postgresql.service redis-server.service
Wants=network-online.target postgresql.service redis-server.service
```

> [!NOTE]
> **Pourquoi**
>
> `systemctl cat` affiche l'unité **et** ses drop-ins : sur Ubuntu,
> `postgresql@16-main.service` est en fait générée à partir du modèle
> `postgresql@.service` (dans `/usr/lib/systemd/system/`), qui lance
> `pg_ctlcluster` — c'est lui qui lit `/etc/postgresql/16/main/` et démarre
> le bon binaire dans `/usr/lib/postgresql/16/bin/` sous le compte propriétaire du cluster. `Type=forking` : `pg_ctlcluster` attend que le postmaster **accepte les connexions** (`pg_ctl -w`) avant de rendre la main, d'où la fiabilité d'`After=`. Le
> service `redis-server` est `Type=` `notify` grâce à `--supervised
> systemd` (`User=redis`), et l'unité Ubuntu est déjà durcie (`ProtectSystem=strict`,
> `ReadWritePaths=` sur `/var/lib/redis`, `/var/log/redis`, `/var/run/redis`, `ReadWriteDirectories=-/etc/redis`).
>
> `postgresql.service` est la cible parapluie : `Wants=postgresql@16-main.service`
> généré par `postgresql-generator`, et `RemainAfterExit=on` pour qu'elle
> apparaisse `active (exited)`. `After=postgresql.service` dans une
> application est donc correct et stable (le nom ne change pas quand on
> migre vers 17), mais un `systemctl restart postgresql.service` redémarre
> **tous** les clusters — pour un seul, viser `postgresql@16-main`.

---

## 15.6 Labs

### <a id="l15-1"></a>**[L15.1](README.md#l15-1)** — Ticket WEB-412 : le vhost complet

*Écrire `/etc/nginx/sites-available/factura-demo` : statique SPA, cache et
gzip, docs protégées, upstream à deux instances, limitation, allow/deny,
flux, taille de corps, journal, maintenance.*

**Fragment global** `/etc/nginx/conf.d/factura.conf` :

```nginx
upstream factura_api {
    server 127.0.0.1:8001 max_fails=2 fail_timeout=10s;
    server 127.0.0.1:8002 max_fails=2 fail_timeout=10s;
    keepalive 16;
}
limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;
log_format factura '$remote_addr - $remote_user [$time_local] "$request" '
    '$status $body_bytes_sent "$http_referer" "$http_user_agent" '
    'rt=$request_time urt=$upstream_response_time ua=$upstream_addr '
    'us=$upstream_status';
```

**Morceau réutilisable** `/etc/nginx/snippets/proxy-factura.conf` :

```nginx
proxy_http_version 1.1;
proxy_set_header Connection "";
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_connect_timeout 3s;
proxy_read_timeout 30s;
proxy_send_timeout 30s;
```

**Le vhost** `/etc/nginx/sites-available/factura-demo` :

```nginx
server {
    listen 80; listen [::]:80;
    server_name factura-demo.lab.local;
    server_tokens off;
    root /srv/www/factura-demo;
    index index.html;
    client_max_body_size 2m;

    access_log /var/log/nginx/factura.access.log factura;
    error_log  /var/log/nginx/factura.error.log warn;

    gzip on;
    gzip_types text/css application/javascript application/json
               image/svg+xml text/plain;
    gzip_min_length 256;
    gzip_vary on;

    # --- maintenance : présence d'un fichier, sans reload ---------------
    error_page 503 @maintenance;
    location @maintenance {
        root /srv/www/maintenance;
        rewrite ^ /503.html break;
    }

    # --- front SPA -------------------------------------------------------
    location / {
        if (-f /srv/www/maintenance.on) { return 503; }
        try_files $uri $uri/ /index.html;
    }
    location /static/ {
        if (-f /srv/www/maintenance.on) { return 503; }
        expires 30d;
        add_header Cache-Control "public";
    }
    location /docs/ {
        if (-f /srv/www/maintenance.on) { return 503; }
        alias /srv/www/factura-demo/docs/;
        auth_basic "Documentation Factura";
        auth_basic_user_file /etc/nginx/htpasswd-factura;
    }

    # --- API : ^~ pour qu'aucune regex ne passe devant -------------------
    location ^~ /api/ {
        if (-f /srv/www/maintenance.on) { return 503; }
        include snippets/proxy-factura.conf;
        proxy_pass http://factura_api;
    }
    location = /api/health {                 # reste visible en maintenance
        include snippets/proxy-factura.conf;
        proxy_pass http://factura_api;
    }
    location = /api/login {
        if (-f /srv/www/maintenance.on) { return 503; }
        limit_req zone=login burst=5 nodelay;
        limit_req_status 429;
        include snippets/proxy-factura.conf;
        proxy_pass http://factura_api;
    }
    location = /api/metrics {
        allow 10.10.10.14;
        deny all;
        include snippets/proxy-factura.conf;
        proxy_pass http://factura_api;
    }
    location = /api/stream {
        include snippets/proxy-factura.conf;
        proxy_buffering off;
        proxy_read_timeout 120s;
        proxy_pass http://factura_api;
    }
}
```

```bash
sudo htpasswd -cB /etc/nginx/htpasswd-factura ops
sudo chown root:www-data /etc/nginx/htpasswd-factura
sudo chmod 0640 /etc/nginx/htpasswd-factura
sudo ln -sf /etc/nginx/sites-available/factura-demo /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

**Les dix vérifications** (depuis `lab-adm`, `H=http://factura-demo.lab.local`) :

```bash
curl -s -o /dev/null -w '%{http_code}\n' $H/                       # 200
curl -s -o /dev/null -w '%{http_code}\n' $H/page/inexistante       # 200 (SPA)
curl --compressed -sI $H/static/gros.txt \
  | grep -Ei 'content-encoding|cache-control|expires'
curl -s -o /dev/null -w '%{http_code}\n' $H/docs/                  # 401
curl -s -o /dev/null -w '%{http_code}\n' -u ops:secret $H/docs/    # 200
for i in $(seq 6); do curl -s $H/api/whoami | jq -r .instance; done # alterne
curl -s $H/api/whoami | jq .headers                    # Host, X-Forwarded-*
/opt/factura/bin/tir.sh $H/api/login 12                # 6×200, 6×429
curl -s -o /dev/null -w '%{http_code}\n' $H/api/metrics   # 403 depuis lab-adm
curl -sN $H/api/stream | head -3                       # lignes une par une
head -c 3M /dev/zero > /tmp/3m; curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST --data-binary @/tmp/3m $H/api/upload                      # 413
head -c 1M /dev/zero > /tmp/1m; curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST --data-binary @/tmp/1m $H/api/upload                      # 200
sudo touch /srv/www/maintenance.on   # sur lab-web
curl -s -o /dev/null -w '%{http_code}\n' $H/                        # 503
curl -s -o /dev/null -w '%{http_code}\n' $H/api/health              # 200
sudo rm /srv/www/maintenance.on
sudo tail -2 /var/log/nginx/factura.access.log    # rt= urt= ua= us= présents
```

> [!NOTE]
> **Pourquoi**
>
> Les choix qui comptent, et pourquoi :
>
> * **`^~ /api/`** : le préfixe gagne et les regex ne sont plus consultées.
>   C'est la ligne qui rend BF15.1 impossible. Les locations exactes
>   (`= /api/login`, `= /api/health`...) restent prioritaires sur lui — c'est
>   voulu — et comme chacune définit ses propres directives, chacune
>   `include` le snippet : sans ça, la location `= /api/login` enverrait
>   `Host: factura_api` au backend (héritage non additif).
> * **`/api/health` hors maintenance** : la supervision doit distinguer
>   « site en maintenance » de « site mort ». Une location exacte sans le
>   test `-f` suffit ; on aurait pu aussi laisser passer `10.10.10.14`.
> * **`if (-f ...) { return 503; }`** : la règle « `if` is evil » de nginx
>   vise les `if` qui contiennent autre chose que `return` ou `rewrite ...
>   last` — ceux-là sont sûrs. L'alternative sans `if` (`try_files
>   /maintenance.on @maintenance;`) fonctionne mais renvoie 200 avec la page
>   au lieu d'un 503 honnête, et casse `try_files` existant. Le test de
>   fichier est fait **à chaque requête** : pas de reload, et la page
>   disparaît dès que le fichier est supprimé.
> * **`error_page 503 @maintenance`** + location nommée avec son propre
>   `root` : le `rewrite ... break` remplace l'URI par `/503.html` sans
>   relancer la recherche de location. nginx garde le code 503 : les
>   moteurs de recherche et les sondes savent que c'est temporaire.
> * **`try_files $uri $uri/ /index.html`** : une SPA gère ses routes côté
>   client ; toute URI inconnue doit renvoyer l'application (200), pas un
>   404. Le revers : une faute de frappe dans une URL de fichier statique
>   renvoie `index.html` en 200, ce que `/static/` (sans `try_files`, donc
>   404 franc) évite pour les assets.
> * **`gzip`** : `text/html` est toujours inclus ; `gzip_vary on` ajoute
>   `Vary: Accept-Encoding` pour que les caches intermédiaires ne servent
>   pas une version compressée à un client qui ne la comprend pas. Ne jamais
>   compresser en TLS des contenus qui mélangent secret et entrée
>   utilisateur (attaque BREACH) — un JSON d'API avec un jeton, par
>   exemple ; ici le JSON est public.
> * **`expires 30d` + `Cache-Control: public`** : `expires` génère à la fois
>   `Expires:` et `Cache-Control: max-age=`. Le `add_header` ajouté ici
>   désactive l'héritage — il n'y avait rien à hériter dans cette version
>   HTTP ; en L15.2 avec HSTS, il faudra l'`include`.
> * **`max_fails=2 fail_timeout=10s`** : deux échecs en 10 s sortent
>   l'instance pendant 10 s ; avec la valeur par défaut (1), un seul
>   timeout la sort, ce qui amplifie une simple lenteur.
> * **`server_tokens off`** : la version de nginx disparaît de `Server:` et
>   des pages d'erreur. Ce n'est pas de la sécurité, c'est de l'hygiène.

> [!WARNING]
> **Piège**
>
> * `client_max_body_size` se pose au niveau `server` : posé seulement dans
>   `location ^~ /api/`, il ne s'appliquerait pas à `= /api/upload` si on en
>   créait une — chaque location exacte repart des valeurs du `server`.
> * `limit_req` sur `= /api/login` avec `nodelay` : les 6 premières passent,
>   puis 429 ; **sans** `nodelay`, le compte est le même (6 × 200, 6 × 429) mais les 5 requêtes de rafale sont retardées de 12 s en 12 s : `tir.sh` met une minute et tu crois à une panne du backend.
> * `htpasswd -c` **écrase** le fichier : pour ajouter un second
>   utilisateur, sans `-c`.
> * `error_log ... warn` : les `connect() failed` sont en `error`, donc
>   visibles ; les `limiting requests` aussi ; en `crit` on ne verrait plus
>   rien d'utile.

---

### <a id="l15-2"></a>**[L15.2](README.md#l15-2)** — HTTPS et les six pannes

*Certificat, `server` 443 durci, redirection 80 sauf ACME, puis provoquer
502, 502 partiel, 504, 413, 403 ×2, boucle 301, 404 API.*

**Partie 1** — si L18.4 a été fait, `sudo cp ~/lab18/pki/app.lab.local.*
...` puis adapter `server_name` ; sinon E15.7 donne l'auto-signé.

`/etc/nginx/snippets/securite-factura.conf` :

```nginx
add_header Strict-Transport-Security "max-age=15768000" always;
add_header X-Content-Type-Options nosniff always;
add_header X-Frame-Options DENY always;
```

```nginx
server {
    listen 80; listen [::]:80;
    server_name factura-demo.lab.local;
    location ^~ /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://$host$request_uri; }
}
server {
    listen 443 ssl http2; listen [::]:443 ssl http2;
    server_name factura-demo.lab.local;
    ssl_certificate     /etc/nginx/ssl/factura-demo.crt;
    ssl_certificate_key /etc/nginx/ssl/factura-demo.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    include snippets/securite-factura.conf;
    # ... tout le contenu du server de L15.1, avec
    #     include snippets/securite-factura.conf;
    #     dans CHAQUE location qui contient un add_header
}
```

Vérification : `curl -vk https://factura-demo.lab.local/api/health -o
/dev/null 2>&1 | grep -iE 'TLSv|ALPN|strict'` → `TLSv1.3`, `h2`, HSTS
présent sur `/api/health` (preuve de l'include).

**Partie 2** — le tableau attendu dans `codes-http.md` :

| Panne | Commande / code | `error.log` (extrait) | Cause / correctif |
|---|---|---|---|
| 5. 502 | `systemctl stop 'mini-api@*'` ; `curl -sk .../api/health` → 502 | `connect() failed (111: Connection refused) while connecting to upstream ... upstream: "http://127.0.0.1:8002/api/health"` (une ligne par backend tenté, puis `no live upstreams while connecting to upstream`) | rien n'écoute ; `systemctl start mini-api@8001 mini-api@8002` |
| 6. 502 partiel | port 8003 dans `upstream`, reload, 10 requêtes → **10 × 200** | `connect() failed (111...) upstream: "http://127.0.0.1:8003/..."` à chaque requête, puis silence 10 s (serveur marqué down) | `proxy_next_upstream` bascule sur 8001 ; l'utilisateur ne voit rien, seule `error.log` sait ; remettre 8002 |
| 7. 504 | `proxy_read_timeout 5s` ; `curl -sk -o /dev/null -w '%{http_code} %{time_total}' '.../api/slow?s=10'` → `504 5.0xx` | `upstream timed out (110: Connection timed out) while reading response header from upstream` | backend plus lent que le timeout ; mesurer côté backend, puis ajuster ; remettre 30 s |
| 8. 413 | POST 3 Mo → 413 | `client intended to send too large body: 3145728 bytes` | `client_max_body_size` ; la requête n'atteint jamais le backend |
| 9a. 403 | `chmod 700 .../docs` ; `curl -u ops:x .../docs/` → 403 | `open() "/srv/www/factura-demo/docs/index.html" failed (13: Permission denied)` | `www-data` sans `x` sur le répertoire ; `namei -l` ; `chmod 755` |
| 9b. 403 | `index` retiré ; `/docs/` → 403 | `directory index of "/srv/www/factura-demo/docs/" is forbidden` | pas de fichier index et `autoindex off` ; remettre `index` |
| 10. boucle | `return 301` dans le 443 ; `curl -sIL --max-redirs 3 https://...` → 3 × 301 puis erreur `Maximum (3) redirects followed` | rien (nginx a répondu correctement à chaque fois) | le 301 doit vivre **uniquement** dans le `server` 80 |
| 11. 404 API | regex `\.(json\|js\|css)$` ajoutée ; `/api/invoices.json` → **200** | rien | `^~ /api/` protège : le préfixe gagne et la regex n'est pas consultée. Sans `^~`, 404 et `open() ".../api/invoices.json" failed (2: No such file or directory)` |

> [!NOTE]
> **Pourquoi**
>
> Deux mécanismes à retenir de cette partie :
>
> **`/.well-known/acme-challenge/` en clair.** Le protocole ACME (Let's
> Encrypt, certbot) prouve la possession du nom en demandant un fichier
> sur `http://nom/.well-known/acme-challenge/<jeton>` — en HTTP, port 80,
> parce qu'avant le premier certificat il n'y a pas de HTTPS. Une
> redirection 301 globale casse le renouvellement `certbot --webroot`.
> La location `^~` en tête du `server` 80 passe avant le `return`. Sur le
> lab il n'y a pas d'ACME (pas de DNS public), mais le réflexe s'installe
> ici, et le module 18 montre `certbot`.
>
> **Le 502 « no live upstreams ».** Quand nginx a marqué tous les serveurs
> d'un `upstream` comme indisponibles (après `max_fails`), il ne tente même
> plus de connexion pendant `fail_timeout` et répond 502 instantanément avec
> cette ligne — plus rapide, mais aussi plus déroutant : les backends sont
> peut-être revenus depuis 5 secondes. À l'inverse, avec un seul serveur
> dans l'upstream (ou `server ... ` unique), nginx ignore `max_fails` et
> retente à chaque requête. Le comportement de l'étape 6 est le plus
> important à connaître : une instance morte sur deux ne produit **aucune
> erreur utilisateur**. Une supervision fondée sur les codes HTTP ne la
> verra jamais ; c'est pourquoi le défi demande de compter les instances
> dans `access.log` (`ua=`), ou de surveiller `error.log`, ou de sonder
> chaque instance directement (`curl 127.0.0.1:8002/api/health` depuis
> `lab-web`).

> [!WARNING]
> **Piège**
>
> Étape 7 : le 504 arrive après **exactement** `proxy_read_timeout`
> (`%{time_total}` ≈ 5,0 s) — c'est la signature qui distingue un timeout
> nginx d'un backend qui répond lui-même 504 (`upstream_status 504` dans
> `access.log`, temps quelconque). Et attention : après le 504, le backend
> **continue** de traiter la requête (il dort encore 5 s) ; les clients qui
> réessaient empilent des requêtes sur un backend déjà saturé. C'est
> l'argument pour un timeout côté backend aussi (Gunicorn `--timeout`).

---

### <a id="l15-3"></a>**[L15.3](README.md#l15-3)** — Ouvrir la base à `lab-web`

*`conf.d/10-factura.conf` avec les douze paramètres, `pg_hba` minimal en
scram, restart, `pg_stat_statements`, tests depuis `lab-web` et `lab-adm`,
requête lente retrouvée dans le journal.*

**Étape 1** :

```bash
pg_lsclusters
# Ver Cluster Port Status Owner    Data directory              Log file
# 16  main    5432 online postgres /var/lib/postgresql/16/main \
#     /var/log/postgresql/postgresql-16-main.log
sudo -u postgres psql -Atc 'SHOW data_directory' -c 'SHOW config_file' \
  -c 'SHOW hba_file'
ss -tlnp | grep 5432          # 127.0.0.1:5432 et [::1]:5432 seulement
```

**Étape 2** — `/etc/postgresql/16/main/conf.d/10-factura.conf` :

```ini
# Module 15 — réglages lab-db (2 Go RAM, 2 vCPU)
listen_addresses = 'localhost,10.10.10.12'      # restart
port = 5432
max_connections = 100                            # restart
shared_buffers = 512MB                           # restart ; ~25 % RAM
work_mem = 8MB                                   # par opération de tri
maintenance_work_mem = 128MB                     # VACUUM, CREATE INDEX
effective_cache_size = 1536MB                    # indice planificateur
wal_level = replica
max_wal_size = 1GB
checkpoint_completion_target = 0.9
shared_preload_libraries = 'pg_stat_statements'  # restart
log_min_duration_statement = 500                 # ms
log_line_prefix = '%m [%p] %u@%d %a '
log_lock_waits = on
log_checkpoints = on
log_connections = off
log_temp_files = 0
timezone = 'Europe/Paris'
password_encryption = scram-sha-256
idle_in_transaction_session_timeout = '10min'
```

```bash
sudo -u postgres psql -Atc "SELECT pg_reload_conf()"
sudo -u postgres psql -c "SELECT name, setting, pending_restart \
  FROM pg_settings WHERE pending_restart"
#  listen_addresses | localhost | t      shared_buffers | 16384 | t
#  shared_preload_libraries | | t
```

**Étape 3** — `pg_hba.conf` (les lignes ajoutées, après les `local`) :

```text
host    factura_demo    factura_app     10.10.10.11/32      scram-sha-256
host    factura_demo    factura_ro      10.10.10.11/32      scram-sha-256
```

```bash
sudo -u postgres psql -Atc "SELECT pg_reload_conf()"
sudo -u postgres psql -c "SELECT line_number, type, database, user_name, \
  address, auth_method, error FROM pg_hba_file_rules"
```

**Étape 4** :

```bash
sudo systemctl restart postgresql@16-main
ss -tlnp | grep 5432      # 10.10.10.12:5432 + 127.0.0.1:5432, pas 0.0.0.0
sudo -u postgres psql -Atc 'SHOW shared_buffers' \
  -c 'SHOW log_min_duration_statement' -c 'SHOW timezone'
sudo -u postgres psql -d factura_demo \
  -c 'CREATE EXTENSION IF NOT EXISTS pg_stat_statements'
```

**Étape 5** : `sudo ufw allow from 10.10.10.11 to any port 5432 proto tcp`.

**Étape 6** (sur `lab-web`, `.pgpass` avec les deux rôles) :

```bash
psql -h 10.10.10.12 -U factura_app -d factura_demo \
  -Atc 'SELECT count(*) FROM invoices'
# 100000
psql -h 10.10.10.12 -U factura_ro -d factura_demo \
  -Atc 'SELECT count(*) FROM customers'
psql -h 10.10.10.12 -U factura_ro -d factura_demo \
  -c "UPDATE customers SET city='X' WHERE id=1"
# ERROR:  permission denied for table customers
```

Depuis `lab-adm` :

```bash
psql -h 10.10.10.12 -U factura_app -d factura_demo -c 'SELECT 1'
# avec ufw : psql: error: connection to server at "10.10.10.12", port 5432
#   failed: Connection timed out            -> étape TCP (pare-feu DROP)
# sans ufw : ... FATAL:  no pg_hba.conf entry for host "10.10.10.10",
#   user "factura_app", database "factura_demo", SSL encryption
#   -> étape pg_hba (le TCP est passé, la règle manque)
```

**Étape 7** :

```bash
# lab-web
for i in $(seq 10); do psql -h 10.10.10.12 -U factura_app -d factura_demo \
  -Atq -f /opt/factura/bin/requete-lente.sql >/dev/null; done
# lab-db
sudo grep -A1 'duration: [0-9]\{3,\}' \
  /var/log/postgresql/postgresql-16-main.log | tail -4
# (si la VM est rapide et que la requête passe sous 500 ms, abaisse
#  temporairement log_min_duration_statement à 100 puis pg_reload_conf())
# 2026-09-19 10:42:11.318 CEST [5921] factura_app@factura_demo psql LOG:
#   duration: 3012.447 ms  statement: SELECT i.number, i.issued_on, ...
sudo -u postgres psql -d factura_demo -c "SELECT calls,
  round(total_exec_time) AS total_ms, round(mean_exec_time) AS moy_ms,
  left(query, 60) FROM pg_stat_statements
  ORDER BY total_exec_time DESC LIMIT 5"
```

> [!NOTE]
> **Pourquoi**
>
> **Pourquoi `conf.d/` et pas `postgresql.conf`** : le fichier principal est
> livré par le paquet et fait 800 lignes ; `include_dir = 'conf.d'` (déjà
> présent en fin de fichier sur Ubuntu) charge les `*.conf` du répertoire
> **après**, donc ils l'emportent. Un fichier de 20 lignes est lisible,
> diffable, déployable par Ansible, et survit à une mise à jour du paquet.
> `ALTER SYSTEM` écrit `postgresql.auto.conf`, chargé en dernier : il
> l'emporte sur `conf.d/` — un piège quand on ne sait pas qui a fait quoi ;
> `SELECT name, source, sourcefile FROM pg_settings WHERE source <> 'default'`
> dit d'où vient chaque valeur.
>
> **Les valeurs** : `shared_buffers` est le cache de pages de PostgreSQL ;
> 25 % de la RAM est le point de départ classique, le reste de la RAM
> servant au cache de fichiers du noyau (que `effective_cache_size` décrit
> au planificateur — c'est une **estimation**, pas une allocation : elle
> influence le choix index vs parcours séquentiel). `work_mem` est alloué
> **par opération** de tri/hachage, **par requête**, et il peut y en avoir
> plusieurs par requête et 100 requêtes en parallèle : 8 Mo × 100 × 3 = 2,4
> Go dans le pire cas — d'où la prudence ; on le monte par session pour une
> requête précise plutôt que globalement. `maintenance_work_mem` ne
> concerne que `VACUUM`, `CREATE INDEX` : on peut être généreux.
> `log_min_duration_statement = 500` journalise **la requête complète** avec
> sa durée dès qu'elle dépasse 500 ms : c'est la trace qu'on cherche à 3 h
> du matin ; `pg_stat_statements` agrège par requête normalisée (les
> constantes remplacées par `$1`) et donne le cumul — les deux se
> complètent. `idle_in_transaction_session_timeout` est le filet contre
> Q15.14.
>
> **`pg_hba` minimal** : une ligne par rôle, base explicite, `/32`, `scram`.
> Pas de `hostssl` ici : le chiffrement entre `lab-web` et `lab-db` est
> souhaitable mais exige un certificat serveur vérifié côté client
> (`sslmode=verify-full`), sinon `hostssl` chiffre sans authentifier — à
> faire proprement avec la PKI du module 18. Le message d'erreur depuis
> `lab-adm` cite `SSL encryption` : libpq tente d'abord en SSL (Ubuntu
> livre un certificat *snakeoil* et `ssl = on`), puis en clair si aucune
> règle `hostssl` ne correspond — d'où parfois deux lignes dans le journal
> serveur pour une seule tentative.

> [!WARNING]
> **Piège**
>
> Le restart coupe toutes les sessions. Sur une vraie production, on
> regroupe les changements `postmaster` et on annonce une fenêtre. Et on
> vérifie **avant** avec `pending_restart` qu'on n'a pas oublié un
> paramètre : sinon on redémarre deux fois. Enfin, `log_connections = on`
> est tentant pour le diagnostic mais produit une ligne par connexion —
> avec une application sans pool, c'est des milliers de lignes par minute.

---

### <a id="l15-4"></a>**[L15.4](README.md#l15-4)** — Sauvegarde nocturne, restauration, PITR

*Script `pg-sauvegarde.sh` sous `postgres`, timer 02:30, restauration
chronométrée, archivage WAL, `pg_basebackup`, catastrophe, retour à T-10 s,
réplication facultative.*

**Partie 1** — `/usr/local/sbin/pg-sauvegarde.sh` :

```bash
#!/usr/bin/env bash
# pg-sauvegarde.sh — dumps logiques quotidiens (exécuté par postgres, peer)
set -euo pipefail
DEST=/var/backups/postgresql
RETENTION=7
HORO="$(date +%Y%m%d-%H%M)"
DIR="$DEST/$HORO"
log() { printf '%s pg-sauvegarde: %s\n' "$(date -Is)" "$*"; }
trap 'log "ECHEC a la ligne $LINENO"; exit 1' ERR

install -d -m 0750 "$DIR"
log "debut -> $DIR"
pg_dumpall --globals-only > "$DIR/globals.sql"
log "globals.sql ($(stat -c %s "$DIR/globals.sql") octets)"
for db in $(psql -Atc "SELECT datname FROM pg_database
                       WHERE NOT datistemplate AND datname <> 'postgres'"); do
  pg_dump -Fc -d "$db" -f "$DIR/$db.dump"
  [ -s "$DIR/$db.dump" ] || { log "dump vide pour $db"; exit 1; }
  log "$db.dump ($(stat -c %s "$DIR/$db.dump") octets)"
done
( cd "$DIR" && sha256sum -- * > SHA256SUMS )
find "$DEST" -mindepth 1 -maxdepth 1 -type d -mtime +"$RETENTION" \
  -print -exec rm -rf {} + | while read -r d; do log "purge $d"; done
log "fin OK"
```

```bash
sudo install -m 0755 pg-sauvegarde.sh /usr/local/sbin/
sudo install -d -o postgres -g postgres -m 0750 /var/backups/postgresql
```

```ini
# /etc/systemd/system/pg-sauvegarde.service
[Unit]
Description=Sauvegarde logique PostgreSQL
After=postgresql.service
Requires=postgresql.service

[Service]
Type=oneshot
User=postgres
Group=postgres
ExecStart=/usr/local/sbin/pg-sauvegarde.sh
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
```

```ini
# /etc/systemd/system/pg-sauvegarde.timer
[Unit]
Description=Sauvegarde PostgreSQL chaque nuit

[Timer]
OnCalendar=*-*-* 02:30:00
RandomizedDelaySec=10min
Persistent=yes

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now pg-sauvegarde.timer
sudo systemctl start pg-sauvegarde.service && journalctl -u pg-sauvegarde -n 6
systemctl list-timers pg-sauvegarde.timer
ls -la /var/backups/postgresql/*/
```

**Restauration testée** :

```bash
D=$(ls -d /var/backups/postgresql/*/ | tail -1)
( cd "$D" && sha256sum -c SHA256SUMS )
sudo -u postgres createdb -O factura_app factura_restore
time sudo -u postgres pg_restore --no-owner -j 2 -d factura_restore \
  "$D/factura_demo.dump"
# real 0m4.8s   (à noter dans restauration.md)
for t in customers invoices invoice_lines; do
  printf '%-14s ' $t
  sudo -u postgres psql -d factura_demo -Atc "SELECT count(*) FROM $t" \
    | tr '\n' ' '
  sudo -u postgres psql -d factura_restore -Atc "SELECT count(*) FROM $t"
done
# customers 5000 5000 / invoices 100000 100000 / invoice_lines 300000 300000
sudo -u postgres psql -d factura_restore \
  -Atc "SELECT sum(total_cents) FROM invoices"
```

**Partie 2** — archivage :

```bash
sudo install -d -o postgres -g postgres -m 0750 /srv/pg-archive/base \
  /srv/pg-archive/wal
```

```bash
#!/usr/bin/env bash
# /usr/local/sbin/pg-archive-wal.sh <chemin> <nom> — copie un segment WAL
# sans jamais écraser un segment déjà archivé (sortie 1 : PostgreSQL
# réessaiera et le signalera dans pg_stat_archiver).
set -euo pipefail
DEST=/srv/pg-archive/wal
[ ! -f "$DEST/$2" ] || { echo "segment $2 déjà archivé" >&2; exit 1; }
cp "$1" "$DEST/$2.tmp" && mv "$DEST/$2.tmp" "$DEST/$2"
```

```ini
# ajouté à conf.d/10-factura.conf
archive_mode = on                                # restart
archive_command = '/usr/local/sbin/pg-archive-wal.sh %p %f'
archive_timeout = 300                   # un segment toutes les 5 min max
```

```bash
sudo systemctl restart postgresql@16-main
sudo -u postgres psql -Atc "SELECT pg_switch_wal()"
ls /srv/pg-archive/wal/          # 000000010000000000000012 ...
sudo -u postgres psql -c "SELECT archived_count, last_archived_wal, \
  failed_count FROM pg_stat_archiver"
```

```bash
sudo -u postgres pg_basebackup -D /srv/pg-archive/base -Ft -z -Xs -P -c fast
ls -la /srv/pg-archive/base/      # base.tar.gz, pg_wal.tar.gz, backup_manifest
```

Témoin et catastrophe :

```sql
INSERT INTO invoices (number, customer_id, issued_on, status, total_cents)
  VALUES ('F-PITR-0001', 1, current_date, 'paid', 100);
SELECT now();                           -- 2026-09-19 11:02:17.4 +02
-- attendre 30 s
DELETE FROM invoice_lines; DELETE FROM invoices;
SELECT pg_switch_wal();
```

Restauration dans un second cluster :

```bash
sudo pg_createcluster 16 pitr -p 5433          # crée conf + PGDATA vide
sudo systemctl stop postgresql@16-pitr 2>/dev/null || true
sudo rm -rf /var/lib/postgresql/16/pitr/*
sudo -u postgres tar -xzf /srv/pg-archive/base/base.tar.gz \
  -C /var/lib/postgresql/16/pitr
sudo -u postgres tar -xzf /srv/pg-archive/base/pg_wal.tar.gz \
  -C /var/lib/postgresql/16/pitr/pg_wal
sudo tee /etc/postgresql/16/pitr/conf.d/20-pitr.conf <<'EOF'
restore_command = 'cp /srv/pg-archive/wal/%f %p'
recovery_target_time = '2026-09-19 11:02:27+02'
recovery_target_action = 'promote'
archive_mode = off
EOF
sudo -u postgres touch /var/lib/postgresql/16/pitr/recovery.signal
sudo systemctl start postgresql@16-pitr
sudo tail -f /var/log/postgresql/postgresql-16-pitr.log
# LOG:  starting point-in-time recovery to 2026-09-19 11:02:27+02
# LOG:  restored log file "000000010000000000000013" from archive
# LOG:  recovery stopping before commit of transaction 812,
#       time 2026-09-19 11:02:49
# LOG:  redo done at 0/13A1B2C8
# LOG:  selected new timeline ID: 2
# LOG:  database system is ready to accept connections
sudo -u postgres psql -p 5433 -d factura_demo -Atc \
  "SELECT count(*) FROM invoices" \
  -c "SELECT number FROM invoices WHERE number LIKE 'F-PITR%'"
# 100001
# F-PITR-0001
```

**Partie 3** (facultatif) : sur `lab-db`, `CREATE ROLE repl REPLICATION
LOGIN PASSWORD '...';`, ligne `host replication repl 10.10.10.14/32
scram-sha-256`, reload. Sur `lab-ops` : `apt install postgresql-16`,
`systemctl stop postgresql@16-main`, `rm -rf /var/lib/postgresql/16/main/*`,
`sudo -u postgres pg_basebackup -h 10.10.10.12 -U repl -D
/var/lib/postgresql/16/main -R -P -X stream -C -S lab_ops`, `systemctl start
postgresql@16-main`. Vérifications : `pg_stat_replication` sur `lab-db`
(`state = streaming`, `replay_lag`), `SELECT pg_is_in_recovery()` → `t` sur
`lab-ops`, un `INSERT` sur `lab-db` visible sur `lab-ops` en moins d'une
seconde, et un `INSERT` sur `lab-ops` refusé (`cannot execute INSERT in a
read-only transaction`).

> [!NOTE]
> **Pourquoi**
>
> **Le script** : sous `postgres` en `peer`, aucun secret. `set -euo
> pipefail` + `trap ERR` : une étape qui échoue arrête tout avec une ligne
> explicite, et le service passe en `failed` — ce qu'un `OnFailure=` (module
> 17) transformera en alerte. Le test `[ -s ]` refuse un dump vide — c'est
> la leçon de BF15.6. `sha256sum` permet à la copie distante (rsync) d'être
> vérifiée. La purge par `-mtime +7` sur les répertoires horodatés est plus
> sûre qu'une purge par nom.
>
> **`pg_dump` est cohérent sans verrou** : il ouvre une transaction en
> `REPEATABLE READ` et lit un instantané ; les écritures continuent pendant
> le dump (elles ne sont pas dans le dump, c'est tout). Sur une base de
> plusieurs centaines de Go, la durée du dump devient le problème
> (`-Fd -j`), et l'espace de sauvegarde aussi : c'est là que la physique
> prend le relais.
>
> **L'archivage** : à chaque segment WAL terminé (16 Mo, ou `archive_timeout`),
> PostgreSQL exécute `archive_command` avec `%p` (chemin du segment) et `%f`
> (son nom). La commande doit renvoyer 0 **uniquement** si le segment est
> en sécurité ; le test `! -f` refuse d'écraser (un segment archivé deux
> fois signale un problème, on veut le voir), et la copie vers `.tmp` suivie
> d'un `mv` garantit qu'un fichier au nom final est toujours complet. Tant que la commande échoue,
> le segment est **conservé** dans `pg_wal` et réessayé : c'est le
> mécanisme de la Q15.15. En production, `cp` local est un brouillon : la
> destination est un autre disque, un NFS, un S3 (`pgbackrest`, `wal-g`
> font ça proprement, avec compression, chiffrement et rétention).
>
> **`pg_basebackup -c fast -Xs`** : demande un checkpoint immédiat (sinon
> attente jusqu'au prochain, plusieurs minutes), et `-X stream` ouvre une
> seconde connexion pour recevoir le WAL produit **pendant** la copie — la
> base tar seule est incohérente (des pages copiées à des instants
> différents) ; ce WAL la rend cohérente au rejeu.
>
> **Le PITR** : au démarrage, la présence de `recovery.signal` fait entrer
> le serveur en mode restauration ; il rejoue le WAL local puis appelle
> `restore_command` segment par segment jusqu'à atteindre
> `recovery_target_time`, **s'arrête avant la première transaction validée
> après cet instant**, puis (`promote`) sort de la restauration en créant
> une nouvelle *timeline* (`00000002...`) — la branche d'histoire divergente.
> La cible peut aussi être un LSN, un nom de point de restauration
> (`pg_create_restore_point('avant-migration')`) ou un identifiant de
> transaction. Le RPO est ici le `DELETE` lui-même : on revient 10 s avant.
> La procédure sur un second cluster est celle de la production : on
> restaure à côté, on vérifie, on extrait ce qu'il faut (ou on bascule).

> [!WARNING]
> **Piège**
>
> * La cible temporelle est en **fuseau de la session** ; donner l'offset
>   (`+02`) évite une heure d'écart avec `timezone = 'Europe/Paris'`.
> * Une cible antérieure à la fin de la sauvegarde de base est impossible : `requested`
>   `recovery stop point is before consistent recovery point`. La base
>   `pg_basebackup` doit être **antérieure** à l'instant visé (et une cible au-delà du dernier WAL archivé donne `recovery ended before configured recovery target was reached`).
> * `archive_mode = on` avec un `archive_command` qui échoue en silence
>   (destination pleine à 3 h du matin) remplit `pg_wal` : surveiller
>   `pg_stat_archiver.failed_count` et `last_failed_time` est obligatoire
>   dès qu'on active l'archivage.
> * Le second cluster a `archive_mode = off` : sinon il archiverait ses
>   propres segments (timeline 2) dans le même répertoire.

---

### <a id="l15-5"></a>**[L15.5](README.md#l15-5)** — Redis : sécuriser, dimensionner, observer

*État des lieux, `redis.conf` de production justifié, ACL, pare-feu, charge
depuis `lab-web`, mesures, `maxmemory` abaissé à chaud, `BGSAVE`.*

**Étape 1** : `bind 127.0.0.1 -::1`, `maxmemory 0`, `maxmemory-policy
noeviction`, `appendonly no`, aucune ACL (`ACL LIST` → `user default on
nopass ~* &* +@all`).

**Étape 2** — le diff attendu (`~/lab15/conf/lab-db/redis.conf.diff`) :

```diff
-bind 127.0.0.1 -::1
+bind 127.0.0.1 10.10.10.12
 protected-mode yes
+# ACL : l'application, limitée à ses préfixes, sans commandes dangereuses
+# (redis.conf n'a pas de continuation de ligne : la directive user factura
+#  tient sur UNE ligne, coupée ici pour l'impression)
+user default off
+user factura on >Redis-Factura-2026 ~sess:* ~user:* ~factura:* &* \
+     +@all -@dangerous
+user admin on >Redis-Admin-2026 ~* &* +@all
-# maxmemory <bytes>
+maxmemory 128mb
-# maxmemory-policy noeviction
+maxmemory-policy volatile-lru
-appendonly no
+appendonly yes
 appendfsync everysec
```

```bash
sudo systemctl restart redis-server
redis-cli PING
# (error) NOAUTH Authentication required.
redis-cli --user factura --pass 'Redis-Factura-2026' PING     # PONG
redis-cli --user factura --pass 'Redis-Factura-2026' KEYS '*'
# (error) NOPERM this user has no permissions to run the 'keys' command
redis-cli --user factura --pass 'Redis-Factura-2026' SET autre:cle 1
# (error) NOPERM this user has no permissions to access one of the keys
#         used as arguments
redis-cli --user admin --pass 'Redis-Admin-2026' ACL LIST
ss -tlnp | grep 6379          # 127.0.0.1:6379 et 10.10.10.12:6379
```

**Étape 3** : `sudo ufw allow from 10.10.10.11 to any port 6379 proto tcp`.

**Étapes 4 et 5** (sur `lab-web`, puis mesures sur `lab-db`) :

```bash
# lab-web
export REDISCLI_AUTH='Redis-Factura-2026'
redis-cli -h 10.10.10.12 --user factura PING
python3 /opt/factura/bin/redis-app.py \
  --url 'redis://factura:Redis-Factura-2026@10.10.10.12:6379/0' --loop
# lab-db
export REDISCLI_AUTH='Redis-Admin-2026'
redis-cli --user admin --stat            # 30 s : keys, mem, clients, req/s
redis-cli --user admin INFO memory | grep -E \
  -e '^(used_memory|used_memory_rss|used_memory_peak|maxmemory):' \
  -e '^mem_fragmentation_ratio:'
redis-cli --user admin INFO stats | grep -E \
  -e '^(total_commands_processed|instantaneous_ops_per_sec|expired_keys):' \
  -e '^(evicted_keys|keyspace_hits|keyspace_misses|rejected_connections):'
redis-cli --user admin INFO clients | grep -E 'connected_clients|blocked'
redis-cli --user admin SLOWLOG GET 5
redis-cli --user admin --latency                 # min/max/avg en ms, Ctrl-C
redis-cli --user admin CLIENT LIST
```

**Étape 6** :

```bash
redis-cli --user admin CONFIG SET maxmemory 2mb
watch -n1 "redis-cli --user admin INFO stats | grep evicted_keys; \
  redis-cli --user admin LLEN factura:jobs"
# evicted_keys monte ; LLEN continue de monter (la file n'a pas de TTL) ;
# l'application continue sans erreur (les sessions sont sacrifiées)
redis-cli --user admin CONFIG SET maxmemory 128mb
```

En `noeviction`, l'application aurait affiché `ECRITURE REFUSEE ... OOM
command not allowed when used memory > 'maxmemory'` et se serait arrêtée.

**Étape 7** :

```bash
redis-cli --user admin BGSAVE
until redis-cli --user admin INFO persistence \
      | grep -q 'rdb_bgsave_in_progress:0'; do sleep 1; done
redis-cli --user admin INFO persistence \
  | grep -E 'rdb_last_bgsave_status|rdb_last_save_time'
sudo install -d -m 0750 /var/backups/redis
sudo cp /var/lib/redis/dump.rdb /var/backups/redis/dump-$(date +%Y%m%d-%H%M).rdb
```

> [!NOTE]
> **Pourquoi**
>
> **`bind` et `protected-mode`** : Redis n'a **aucune** authentification par
> défaut ; `protected-mode yes` refuse les connexions non locales tant
> qu'aucun mot de passe n'est défini — c'est le garde-fou ajouté après les
> milliers d'instances Redis ouvertes sur Internet en 2015-2016 (et
> rançonnées). `bind` sur l'adresse du LAN + pare-feu + ACL : trois couches,
> parce qu'une seule saute toujours un jour.
>
> **ACL plutôt que `requirepass`** : `requirepass` est un mot de passe unique
> pour un utilisateur `default` qui peut tout — y compris `CONFIG SET dir
> /var/www/html` puis `SAVE`, le vecteur classique pour écrire un fichier
> arbitraire. Les ACL (Redis 6+) donnent un utilisateur par application avec
> un **motif de clés** (`~sess:*`) et un **jeu de commandes** (`+@all
> -@dangerous` retire `KEYS`, `FLUSHALL`, `CONFIG`, `SHUTDOWN`, `DEBUG`,
> `MONITOR`, `SAVE`, `BGSAVE`...). `user default off` supprime l'accès sans
> mot de passe. `&*` est le motif de canaux Pub/Sub. Les mots de passe sont
> stockés hachés (SHA-256) dans le fichier ACL ou `redis.conf`. Sur une
> production, `aclfile /etc/redis/users.acl` sépare les utilisateurs de la
> configuration.
>
> **`maxmemory 128mb`** sur une VM de 2 Go partagée avec PostgreSQL
> (`shared_buffers 512MB`) : le calcul est RAM totale moins PostgreSQL moins
> cache de fichiers moins marge pour le `fork()` de `BGSAVE` (copie sur
> écriture : dans le pire cas, la mémoire de Redis double le temps de la
> sauvegarde). `volatile-lru` parce que les sessions ont un TTL et la file
> non (Q15.16). `appendonly yes` + `everysec` : une seconde de perte maximum,
> acceptable pour des sessions et une file rejouable ; `save` conservé pour
> les copies. Le prix de l'AOF : des écritures disque continues et un
> redémarrage plus long (rejeu).
>
> **Les mesures** : `used_memory` vs `maxmemory` (marge), `evicted_keys` (si
> ça monte hors incident, le cache est trop petit), `keyspace_hits /
> (hits+misses)` (taux de succès du cache ; sous 80 % on s'interroge),
> `instantaneous_ops_per_sec`, `connected_clients` (une application sans
> pool qui fuit se voit ici), `rejected_connections` (`maxclients` atteint),
> `SLOWLOG` (commandes > 10 ms par défaut : un `KEYS` ou un gros `HGETALL`
> y apparaît), `--latency` (typiquement 0,1 ms en local ; des pics = `fork`,
> `KEYS`, swap). Les trois seuils à proposer au module 26 : `used_memory /
> maxmemory > 0.9`, `evicted_keys` en hausse sur 5 min, `mem_fragmentation_
> ratio` hors [1 ; 1,5].
>
> **`BGSAVE` et la copie** : le `rename()` atomique de `temp-*.rdb` vers
> `dump.rdb` garantit qu'à tout instant `dump.rdb` est un fichier complet ;
> la copie ne voit jamais un fichier en cours d'écriture. Pour l'AOF, le
> répertoire évolue en continu et une copie brute peut prendre un manifeste
> et des incréments incohérents : la sauvegarde AOF passe par `BGREWRITEAOF`
> puis copie du répertoire complet, ou plus simplement par le RDB.

> [!WARNING]
> **Piège**
>
> * `CONFIG SET` sans `CONFIG REWRITE` (ou sans éditer le fichier) : le
>   changement disparaît au prochain restart. Ici on édite le fichier, donc
>   pas de problème — mais l'étape 6 utilise `CONFIG SET` volontairement à
>   titre temporaire.
> * Le mot de passe dans `--pass` ou `-a` apparaît dans `ps` et l'historique
>   du shell (`redis-cli` affiche d'ailleurs un avertissement) ;
>   `REDISCLI_AUTH` évite les deux.
> * `redis-app.py` reçoit l'URL avec le mot de passe en argument : lisible
>   dans `ps`. Pour un vrai service, `FACTURA_REDIS_URL` vient d'un
>   `EnvironmentFile=`.

---

## 15.7 Break & Fix

### <a id="bf15-1"></a>**[BF15.1](README.md#bf15-1)** — « La page dit ERREUR, l'API répond »

*`/api/invoices.json` renvoie 404 alors que `/api/health` répond 200 ; un
collègue a « ajouté du cache statique ».*

**Diagnostic** :

```bash
U=https://factura-demo.lab.local
curl -sk -o /dev/null -w '%{http_code}\n' $U/api/invoices.json   # 404
curl -sk -o /dev/null -w '%{http_code}\n' $U/api/health          # 200
curl -s http://127.0.0.1:8001/api/invoices.json | head -2
# le backend répond : nginx est en cause
sudo tail -2 /var/log/nginx/factura.error.log
# [error] ... open() "/srv/www/factura-demo/api/invoices.json" failed
#   (2: No such file or directory), request: "GET /api/invoices.json"
sudo grep -n 'us=' /var/log/nginx/factura.access.log | tail -1
#   ... 404 ... ua=- us=-        <- pas d'upstream contacté
sudo nginx -T 2>/dev/null | grep -n 'location'
#   location ~* \.(json|js|css|png|svg|ico)$ {   <- la nouveauté
#   location /api/ {                             <- le ^~ a disparu
diff ~/lab15/conf/factura-demo /etc/nginx/sites-available/factura-demo
```

**Cause racine** : le collègue a ajouté une location **regex** pour les
extensions statiques — et, au passage, « nettoyé » le `^~` de la location
API qu'il prenait pour une faute de frappe (le `diff` avec ta copie de
`~/lab15/conf/` le montre). Sans `^~`, nginx retient `/api/` comme
meilleur préfixe, puis teste les regex, et `\.(json|...)$` correspond à
`/api/invoices.json` — la regex gagne, nginx cherche un fichier, 404.
`/api/health` n'a pas d'extension : il reste sur `/api/`, d'où la
supervision verte.

**Correctif** (sans retirer le cache) :

```nginx
    location ^~ /api/ { ... }   # le préfixe s'impose, regex non consultées
```

ou, si l'on ne veut pas toucher à la location API, restreindre la regex :
`location ~* ^/static/.*\.(json|js|css|png|svg|ico)$` (cache limité au
répertoire des assets, ce qui est de toute façon plus juste).
`nginx -t && systemctl reload nginx`, puis `curl` → 200 et la page se
charge.

**Prévention** : toute location d'API est écrite `^~` dès le départ, avec
un commentaire qui dit pourquoi (pour que personne ne le « nettoie ») ;
toute regex statique est ancrée sur un préfixe (`^/static/`) ; un test de
non-régression (`curl` sur trois URI de l'API dont une avec extension)
dans le check de déploiement ; et une sonde de supervision sur une URI
**réelle** de l'application, pas seulement `/health`.

> [!NOTE]
> **Pourquoi**
>
> Le mécanisme est celui de Q15.1. Ce qui le rend redoutable : la
> modification est « évidemment sans rapport » avec l'API (elle parle de
> `.css` et `.js`), `nginx -t` la valide, le collègue a testé `/static/app.js`
> et vu le cache fonctionner, et la sonde `/api/health` continue de
> répondre. L'incident n'est visible que par l'utilisateur, et seulement sur
> les routes dont le nom finit par une extension — dans une API REST
> moderne, il y en a rarement, ce qui explique pourquoi cette panne dort
> parfois des mois avant qu'une route `/export.csv` ne la réveille.
>
> Le réflexe de diagnostic est celui de QO15.3 : tester le backend en
> direct (il répond → nginx est coupable), puis lire le chemin de fichier
> dans `error.log` (nginx a cherché un **fichier** pour une URI d'API → une
> location statique a capturé la requête), puis `nginx -T | grep location`
> pour trouver laquelle.

---

### <a id="bf15-2"></a>**[BF15.2](README.md#bf15-2)** — « 502 sur tout /api/ »

*Toutes les URI `/api/` en 502, instances `active`, le collègue a
« harmonisé les ports ».*

**Diagnostic** (trois commandes) :

```bash
sudo tail -3 /var/log/nginx/factura.error.log
# connect() failed (111: Connection refused) while connecting to upstream,
#   ... upstream: "http://127.0.0.1:8011/api/health"
# connect() failed (111: Connection refused) ... "http://127.0.0.1:8012/..."
# no live upstreams while connecting to upstream
ss -tlnp | grep -E ':80(0|1)[0-9]'
# LISTEN 127.0.0.1:8001 ... python3   LISTEN 127.0.0.1:8002 ... python3
sudo nginx -T 2>/dev/null | grep -A3 'upstream factura_api'
#   server 127.0.0.1:8011;  server 127.0.0.1:8012;
```

**Cause racine** : l'`upstream` pointe sur 8011/8012 (« nouvelle norme »),
les instances écoutent toujours sur 8001/8002. nginx a marqué les deux
serveurs indisponibles après leurs échecs : `no live upstreams`, 502
immédiat.

**Correctif** : remettre `127.0.0.1:8001` et `8002` dans
`/etc/nginx/conf.d/factura.conf` (ou dans le vhost, selon où l'`upstream`
est déclaré), `nginx -t`, `systemctl reload nginx`. Le reload suffit :
l'ancienne conf est remplacée, les compteurs d'échec sont remis à zéro.

**Vérification qui aurait empêché la mise en production** : un script de
pré-déploiement qui, pour chaque `server` d'un `upstream` de la conf
(`nginx -T | awk '/upstream/,/}/' | grep server`), fait un `curl --max-time
2 http://IP:PORT/api/health` et refuse le reload si un backend ne répond
pas. Plus simplement : `nginx -t` ne vérifie que la **syntaxe** — la
validation fonctionnelle est `curl` après reload, sur une URI de l'API,
**avant** de fermer le ticket. Et une supervision de la ligne `no live
upstreams` dans `error.log`.

> [!NOTE]
> **Pourquoi**
>
> `connect() failed (111)` = `ECONNREFUSED` : le noyau de `lab-web` a répondu
> par un `RST` parce qu'aucune socket n'écoute sur ce port. C'est différent
> d'un timeout (`110`, pare-feu qui jette) et d'un `113` (`No route to host`,
> réseau). Le port apparaît en clair dans la ligne : le diagnostic tient
> dans la lecture de cette ligne + `ss -tlnp` pour confronter à la réalité.
>
> Le passage par `no live upstreams` explique un détail : après avoir
> constaté deux échecs (`max_fails=2` de L15.1, ou 1 par défaut), nginx
> n'essaie même plus pendant `fail_timeout` (10 s) et répond 502 sans
> tenter de connexion — les lignes `connect() failed` cessent, remplacées par
> `no live upstreams`. Un opérateur qui lit `error.log` **après** la
> première salve ne voit plus le port fautif : il faut remonter quelques
> lignes, ou attendre le prochain essai. C'est aussi pourquoi, après
> correction, le premier `curl` peut encore donner 502 pendant quelques
> secondes si l'on n'a pas rechargé (le reload réinitialise l'état des
> upstreams).
>
> Sur Rocky, le même symptôme avec `13: Permission denied` au lieu de `111`
> désigne SELinux : `setsebool -P httpd_can_network_connect 1`. Et avec une
> socket Unix (`proxy_pass http://unix:/run/app.sock;`), `13` désigne les
> droits de la socket (`www-data` doit avoir `rw`, souvent via un groupe
> commun) ou `2: No such file` si l'application ne l'a pas créée.

---

### <a id="bf15-3"></a>**[BF15.3](README.md#bf15-3)** — « L'application ne se connecte plus depuis la migration »

*Deux causes superposées : `pg_hba` modifié, puis secret `md5` face à une
méthode `scram`.*

**Diagnostic, première couche** (depuis `lab-web`) :

```bash
psql -h 10.10.10.12 -U factura_app -d factura_demo -c 'SELECT 1'
# psql: error: connection to server at "10.10.10.12", port 5432 failed:
#   FATAL:  no pg_hba.conf entry for host "10.10.10.11", user "factura_app",
#   database "factura_demo", SSL encryption
```

Le TCP passe (on a une réponse du serveur) ; aucune ligne ne correspond.
Sur `lab-db` :

```bash
sudo -u postgres psql -c "SELECT line_number, type, database, user_name, \
  address, auth_method, error FROM pg_hba_file_rules"
#  ... | host | {factura}      | {factura_app} | 10.10.10.11 | scram-sha-256 |
sudo grep -n '10.10.10.11' /etc/postgresql/16/main/pg_hba.conf
# host  factura  factura_app  10.10.10.11/32  scram-sha-256   # migration
```

Le prestataire a remplacé `factura_demo` par `factura` (le futur nom de
la base) **avant** de renommer la base. Aucune ligne ne couvre
`factura_demo` depuis `10.10.10.11`.

**Correctif 1** : remettre `factura_demo` (ou ajouter une ligne pour les
deux noms, le temps de la migration), `pg_reload_conf()`,
`pg_hba_file_rules` sans `error`.

**Diagnostic, seconde couche** :

```bash
# lab-web
psql -h 10.10.10.12 -U factura_app -d factura_demo -c 'SELECT 1'
# FATAL:  password authentication failed for user "factura_app"
# lab-db
sudo tail -3 /var/log/postgresql/postgresql-16-main.log
# FATAL:  password authentication failed for user "factura_app"
# DETAIL:  User "factura_app" does not have a valid SCRAM secret.
#   Connection matched file ".../pg_hba.conf" line 96:
#   "host factura_demo factura_app 10.10.10.11/32 scram-sha-256"
sudo -u postgres psql -Atc "SELECT rolname, left(rolpassword, 12) \
  FROM pg_authid WHERE rolname LIKE 'factura%'"
# factura_ro|SCRAM-SHA-25
# factura_app|md54ce0e2e71
sudo -u postgres psql -Atc 'SHOW password_encryption'      # md5
sudo grep -rn 'password_encryption' /etc/postgresql/16/main/
# conf.d/90-migration.conf:1:password_encryption = md5   # compat ancien pilote
```

Le prestataire a passé `password_encryption` à `md5` (« compatibilité avec
l'ancien pilote ») puis ré-enregistré le mot de passe : il est maintenant
stocké sous forme `md5...`. La ligne `pg_hba` exige `scram-sha-256`, qui
ne peut pas vérifier un secret MD5.

**Correctif 2** (même mot de passe, tiré de `/etc/factura/db.env`) :

```bash
sudo rm /etc/postgresql/16/main/conf.d/90-migration.conf
sudo -u postgres psql -Atc "SELECT pg_reload_conf()" \
  -c "SHOW password_encryption"                    # scram-sha-256
sudo -u postgres psql -c "ALTER ROLE factura_app PASSWORD 'Factura-App-2026'"
sudo -u postgres psql -Atc "SELECT left(rolpassword, 12) \
  FROM pg_authid WHERE rolname='factura_app'"
# SCRAM-SHA-25
```

Depuis `lab-web`, `SELECT 1` passe. Aucun restart, aucun `trust`.

**Pourquoi la seconde ne se voit pas avant la première** : `pg_hba.conf`
est évalué **avant** toute authentification. Tant qu'aucune ligne ne
correspond, PostgreSQL refuse sans jamais demander de mot de passe — il ne
consulte `pg_authid` qu'une fois une ligne retenue. Les couches
s'empilent dans l'ordre réseau → règle → secret (QO15.4), et on ne voit
que la première qui bloque.

**Prévention** : `pg_hba.conf` et `conf.d/` sous gestion de configuration
(Ansible, module 23) avec revue ; `password_encryption` figé à
`scram-sha-256` et vérifié par le script de conformité (D15) ; interdire
`md5` par une requête de contrôle sur `pg_authid` (`rolpassword LIKE
'md5%'`) ; et un compte de prestataire nominatif, pour que `journalctl` et
`\du` disent qui a fait quoi.

> [!NOTE]
> **Pourquoi**
>
> La compatibilité `md5`/`scram` est asymétrique : la méthode `md5` de
> `pg_hba` sait vérifier un secret SCRAM (elle bascule d'elle-même en
> SCRAM), mais la méthode `scram-sha-256` ne sait rien faire d'un secret
> MD5 — le protocole SCRAM exige un secret dérivé par PBKDF2 avec un sel,
> que le hachage MD5 non salé ne fournit pas. D'où le `DETAIL: does not have
> a valid SCRAM secret`, qui n'apparaît **que côté serveur** : le client
> reçoit le même `password authentication failed` qu'avec un mot de passe
> faux, par conception (ne pas renseigner un attaquant).
>
> `password_encryption` ne convertit rien : il ne s'applique qu'au
> **prochain** `ALTER ROLE ... PASSWORD` ou `\password`. Une base migrée
> depuis PG 10-13 peut donc contenir des secrets MD5 des années après le
> passage en `scram-sha-256` par défaut (PG 14), sans que personne ne le
> sache, jusqu'au jour où quelqu'un remplace `md5` par `scram-sha-256` dans
> `pg_hba.conf` « pour durcir ». Le contrôle `SELECT rolname FROM pg_authid
> WHERE rolpassword LIKE 'md5%'` fait partie de tout audit PostgreSQL.

---

### <a id="bf15-4"></a>**[BF15.4](README.md#bf15-4)** — « Plus aucune connexion, la base ne fait rien »

*`remaining connection slots are reserved`, charge nulle, restart interdit,
« optimisation mémoire » d'un collègue.*

**Remise en service immédiate** (la socket + les slots réservés sont là
pour ça) :

```bash
sudo -u postgres psql
```

```sql
SHOW max_connections;                                        -- 20 (!)
SELECT count(*), state, usename, application_name
  FROM pg_stat_activity WHERE backend_type = 'client backend'
 GROUP BY 2, 3, 4 ORDER BY 1 DESC;
--  17 | idle | factura_app | factura-api
SELECT pid, client_addr, backend_start, state_change,
       now() - state_change AS inactif_depuis, left(query, 40)
  FROM pg_stat_activity
 WHERE state = 'idle' AND usename = 'factura_app'
 ORDER BY state_change LIMIT 5;
-- 17 sessions idle, toutes ouvertes à la même seconde, aucune requête
-- depuis ; en production elles auraient des heures
-- la clôture comptable : quelle session ? (state = active ou idle in
--  transaction, usename différent, application_name) -> on ne la touche pas
SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
 WHERE state = 'idle' AND usename = 'factura_app'
   AND application_name = 'factura-api';
-- 17 lignes à true  (en production : ... AND state_change < now() -
--                    interval '15 min', pour ne tuer que l'oubli)
```

Depuis `lab-web`, la connexion passe à nouveau.

**La modification du collègue** :

```bash
sudo grep -rn max_connections /etc/postgresql/16/main/conf.d/
# conf.d/90-tuning.conf:2:max_connections = 20   # reduit pour economiser la RAM
sudo -u postgres psql -Atc "SELECT name, setting, source, sourcefile \
  FROM pg_settings WHERE name='max_connections'"
```

Avec `max_connections = 20` et `superuser_reserved_connections = 3`, il
reste **17** slots pour les rôles ordinaires ; 17 sessions `idle` oubliées
les occupaient toutes. Le changement était en place depuis une semaine
mais n'a pris effet qu'au dernier restart (contexte `postmaster`), d'où le
délai entre la cause et l'effet.

**Correctif durable** — on ne peut pas remonter `max_connections` sans
restart : on le note pour la prochaine fenêtre (100, ou une valeur
justifiée par le nombre de workers de l'application), et on pose tout de
suite ce qui se recharge à chaud :

```ini
# conf.d/10-factura.conf
idle_session_timeout = '30min'                 # PG 14+ : tue les idle
idle_in_transaction_session_timeout = '5min'
```

```sql
SELECT pg_reload_conf();
ALTER ROLE factura_app CONNECTION LIMIT 12;    -- laisse de la place aux autres
```

**Deux mesures durables** : côté base, `idle_session_timeout` +
`CONNECTION LIMIT` par rôle (une application ne peut plus assécher la
base) ; côté architecture, un **pooler** (pgbouncer en mode
`transaction`) devant PostgreSQL : l'application ouvre autant de
connexions qu'elle veut vers pgbouncer, qui n'en maintient qu'une poignée
vers PostgreSQL. C'est la réponse standard, et elle rend `max_connections
= 20` presque acceptable.

> [!NOTE]
> **Pourquoi**
>
> Chaque connexion PostgreSQL est un **processus** (`fork()` du postmaster)
> avec sa mémoire propre (quelques Mo) plus `work_mem` par tri : c'est pour
> ça que le collègue voulait baisser `max_connections`, et c'est pour ça
> qu'on ne le monte pas à 1 000. Mais une session `idle` coûte presque rien
> en CPU : elle occupe juste un slot. Le vrai problème est l'application qui
> ouvre sans fermer — un pool mal réglé (`pool_size` × workers × instances >
> slots), ou des connexions abandonnées après un crash côté client sans
> `tcp_keepalives` (PostgreSQL ne les voit mourir qu'au premier envoi ;
> `tcp_keepalives_idle = 60` accélère la détection).
>
> Les slots réservés (`superuser_reserved_connections`, et
> `reserved_connections` + rôle `pg_use_reserved_connections` en PG 16) sont
> précisément la porte de secours de cet incident : sans eux, l'opérateur
> serait enfermé dehors avec les utilisateurs. `pg_terminate_backend` sur
> des sessions `idle` est sans risque fonctionnel : elles n'ont aucune
> transaction en cours ; le client recevra une erreur à sa **prochaine**
> requête et devra se reconnecter — une application correcte le fait.
> L'interdit de l'énoncé (pas de restart) est réaliste : un restart aurait
> tout réglé en 5 secondes et tué la session de clôture ; l'exploitant qui
> sait lire `pg_stat_activity` n'a pas besoin de ce marteau.

---

### <a id="bf15-5"></a>**[BF15.5](README.md#bf15-5)** — « L'application plante en écriture, Redis répond »

*`ECRITURE REFUSEE`, `PING` OK, « réglage mémoire » récent.*

**Diagnostic** :

```bash
python3 /opt/factura/bin/redis-app.py -n 50 2>&1 | tail -1
# redis-app: ECRITURE REFUSEE au tour 1 : OOM command not allowed when used
#   memory > 'maxmemory'.
redis-cli --user admin CONFIG GET maxmemory              # 1048576  (1 Mo)
redis-cli --user admin CONFIG GET maxmemory-policy       # noeviction
redis-cli --user admin INFO memory | grep -E '^used_memory:|^maxmemory:'
# used_memory:4410232   maxmemory:1048576   (AOF rechargé au restart)
redis-cli --user admin INFO keyspace          # db0:keys=6xxx,expires=6xxx
redis-cli --user admin --bigkeys | tail -5    # que des sess:* de 512 o
sudo grep -n '^maxmemory' /etc/redis/redis.conf
# maxmemory 1mb          # alerte supervision 2026-09 : limiter la RAM
# maxmemory-policy noeviction
```

**Cause** : `maxmemory` abaissé à 1 Mo (réponse à une alerte mémoire) avec
la politique `noeviction` : dès que les sessions (30 min de TTL) remplissent
1 Mo — c'est-à-dire presque tout de suite, la structure interne de Redis
occupant déjà près d'1 Mo à vide —, **toute écriture est refusée** (`SETEX`, `INCR`, `LPUSH`...) alors que
les lectures (`PING`, `GET`) continuent — d'où un service « qui répond »
mais une application qui plante. Redis ne libère les clés expirées que
paresseusement (à l'accès) ou par échantillonnage (10 fois par seconde) :
la mémoire ne redescend pas assez vite pour absorber le flux.

**Correctif à chaud** (sans restart, sans `FLUSHALL`) :

```bash
redis-cli --user admin CONFIG SET maxmemory 128mb
redis-cli --user admin CONFIG SET maxmemory-policy volatile-lru
redis-cli --user admin CONFIG REWRITE          # persiste dans redis.conf
python3 /opt/factura/bin/redis-app.py -n 50 | tail -1    # terminé sans erreur
```

Sur l'interdit « redémarrer perdrait les sessions » : avec `appendonly
yes` (L15.5), un restart **ne perd pas** les sessions — elles sont dans
l'AOF, TTL compris. L'énoncé demandait de vérifier ; la réponse dépend de
la persistance configurée (sans AOF ni `save` récent, oui, on les perdrait).

**Politique pour cette application** : `volatile-lru` (Q15.16) — les
sessions ont un TTL et se sacrifient, la file `factura:jobs` n'en a pas
et reste. Ou deux instances Redis : `noeviction` pour la file (une
écriture refusée vaut mieux qu'un travail perdu, et l'application doit
gérer l'erreur), `allkeys-lru` pour le cache pur.

> [!NOTE]
> **Pourquoi**
>
> Le message `OOM command not allowed when used memory > 'maxmemory'` est
> renvoyé **par commande** : Redis vérifie avant chaque commande marquée
> « consomme de la mémoire » si `used_memory > maxmemory` ; si la politique
> est `noeviction` (ou si elle est `volatile-*` et qu'il n'y a plus rien
> de volatil à évincer), la commande est refusée. Les commandes en lecture
> ne sont pas concernées, ni `DEL`, ni `PING` : c'est ce qui rend la panne
> partielle et trompeuse pour une sonde qui ne fait que `PING`.
>
> Une bonne sonde Redis **écrit** une clé de test (`SET sonde:x 1 EX 10`)
> et mesure le résultat. Et le réglage de `maxmemory` ne se fait jamais en
> réponse à une alerte sans regarder `INFO keyspace` (combien de clés,
> combien avec TTL) et `used_memory_peak` : ici l'application avait besoin
> d'environ 3 Mo par tranche de 30 minutes de sessions ; 1 Mo était en
> dessous de la mémoire de base de Redis lui-même (`used_memory` à vide). `CONFIG SET` + `CONFIG REWRITE` est la
> séquence sans coupure ; l'oubli du `REWRITE` est la cause classique d'une
> panne qui « revient toute seule » au restart suivant.

---

### <a id="bf15-6"></a>**[BF15.6](README.md#bf15-6)** — « Les exports de nuit font 0 octet »

*Fichiers horodatés mais vides ; « à la main ça marche » ; compte dédié,
pas de mot de passe dans cron.*

**Reproduire comme cron** :

```bash
sudo cat /etc/cron.d/factura-offsite
# */2 * * * * dumpops /usr/local/bin/factura-offsite.sh
sudo cat /usr/local/bin/factura-offsite.sh
# pg_dump -h 127.0.0.1 -U factura_app factura_demo \
#   > /var/backups/factura-offsite/factura-$(date +%Y%m%d-%H%M).sql \
#   2>/dev/null
ls -la /var/backups/factura-offsite/     # -rw-r--r-- ... 0 ... factura-*.sql
sudo -u dumpops -H env -i HOME=/var/lib/dumpops PATH=/usr/bin:/bin \
  bash -c 'pg_dump -h 127.0.0.1 -U factura_app factura_demo </dev/null \
           | head -c 0'
# WARNING: password file "/var/lib/dumpops/.pgpass" has group or world access;
#   permissions should be u=rw (0600) or less
# pg_dump: error: connection to server at "127.0.0.1", port 5432 failed:
#   fe_sendauth: no password supplied
sudo ls -la /var/lib/dumpops/.pgpass          # -rw-r--r--  (0644)
```

**Les deux erreurs** :

1. **Droits** : `.pgpass` en `0644` → libpq l'ignore avec un avertissement
   et, sans terminal (cron), échoue avec `fe_sendauth: no password
   supplied`. « À la main ça marche » parce que le collègue le lance
   depuis **son** compte, avec **son** `.pgpass` en `0600` — pas depuis
   `dumpops`.
2. **Conception** : `> fichier 2>/dev/null` — la redirection crée le
   fichier **avant** que `pg_dump` ne démarre, l'erreur part à la poubelle,
   et le code de retour n'est jamais testé. Cron voit une commande qui a
   « tourné ». Le fichier vide est la preuve de l'échec, et personne ne
   la regarde.

**Correctif** :

```bash
sudo chmod 0600 /var/lib/dumpops/.pgpass
sudo chown dumpops:dumpops /var/lib/dumpops/.pgpass
```

```bash
#!/usr/bin/env bash
# /usr/local/bin/factura-offsite.sh — export SQL vers le site distant
set -euo pipefail
DEST=/var/backups/factura-offsite
F="$DEST/factura-$(date +%Y%m%d-%H%M).sql.gz"
TMP="$F.partiel"
pg_dump -w -h 127.0.0.1 -U factura_app -d factura_demo | gzip > "$TMP"
[ "$(stat -c %s "$TMP")" -gt 1024 ] \
  || { echo "export vide : $TMP" >&2; rm -f "$TMP"; exit 1; }
mv "$TMP" "$F"
sha256sum "$F" > "$F.sha256"
echo "OK $F $(stat -c %s "$F") octets"
```

* `-w` : ne jamais demander de mot de passe (échec franc en batch) ;
* écriture dans un fichier `.partiel` puis `mv` : un fichier au nom final
  est **toujours** complet ;
* test de taille : un dump de `factura_demo` fait des dizaines de Mo, pas
  0 ;
* `set -euo pipefail` : le code de retour de `pg_dump` dans le pipe
  compte ;
* la sortie d'erreur n'est plus jetée : cron l'envoie par mail (si
  `MAILTO` est défini) ou dans `journalctl -t CRON` ; mieux, un timer
  systemd avec `OnFailure=` (module 17).

**Pour qu'un fichier vide ne passe plus** : le script refuse de le
produire (ci-dessus) ; un contrôle indépendant (le healthcheck de D15 ou
du projet P1) vérifie **âge et taille** du dernier fichier ; et une
restauration de test périodique — la seule preuve.

> [!NOTE]
> **Pourquoi**
>
> Deux mécanismes se combinent. Le premier est celui de E15.13 : libpq
> vérifie lui-même le mode de `.pgpass` et **ignore** un fichier trop
> ouvert au lieu de refuser la connexion — un choix qui protège le secret
> (il ne l'utilisera pas si d'autres peuvent le lire) mais qui transforme
> une faute de droits en échec d'authentification. Le second est la
> sémantique du shell : dans `cmd > f`, le shell ouvre (et tronque) `f`
> **avant** d'exécuter `cmd` ; si `cmd` échoue sans rien écrire, `f` existe,
> vide, avec une date récente. Toute vérification fondée sur « le fichier du
> jour existe » est trompée.
>
> C'est pourquoi le script de L15.4 (sous `postgres`, `peer`, pas de
> `.pgpass`) est la meilleure réponse au besoin : il supprime la première
> cause. Quand un compte dédié est imposé, le `.pgpass` en `0600` dans son
> home, ou `PGPASSFILE=` vers un fichier en `0600` que `dumpops` possède — pas un `root:dumpops 0640` : libpq
> refuse tout bit groupe ou autres, quel que soit le propriétaire; la
> variante propre est un `~/.pg_service.conf` + `.pgpass`, ou un
> `EnvironmentFile=` de service systemd. Et dans tous les cas, `2>/dev/null`
> sur une commande de sauvegarde est une faute professionnelle : on
> supprime la seule trace de l'échec.

---

## 15.8 Défi du module

<a id="d15"></a>**[D15](README.md#d15)** — *Dossier d'exploitation : configurations, `verif-services.sh`,
runbook, fiche entretien, preuve.*

**Configurations** : copie de chaque fichier avec l'en-tête demandé, par
exemple `~/lab15/conf/lab-web/nginx-factura-demo.conf` :

```nginx
# Rôle : vhost HTTPS factura-demo.lab.local (statique + reverse proxy)
# Hôte : lab-web (10.10.10.11) — /etc/nginx/sites-available/factura-demo
# Date : 2026-09-19 — module 15, L15.1 + L15.2
```

**`~/lab15/bin/verif-services.sh`** (exécuté sur `lab-adm`, SSH par clé
vers `mathieu@lab-web` et `mathieu@lab-db`, `sudo` sans mot de passe
supposé pour les lectures privilégiées) :

```bash
#!/usr/bin/env bash
# verif-services.sh — conformité nginx / PostgreSQL / Redis (module 15, D15)
set -euo pipefail
WEB=mathieu@10.10.10.11; DB=mathieu@10.10.10.12
URL=https://factura-demo.lab.local
CA="${CA:-$HOME/lab18/pki/ca.crt}"; CURL=(curl -s --max-time 5)
[ -r "$CA" ] && CURL+=(--cacert "$CA") || CURL+=(-k)
PASS=0; FAIL=0
ok() { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko() { printf '  [FAIL] %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
rweb() { ssh -o BatchMode=yes -o ConnectTimeout=5 "$WEB" "$@"; }
rdb()  { ssh -o BatchMode=yes -o ConnectTimeout=5 "$DB"  "$@"; }
sql()  { rdb "sudo -n -u postgres psql -Atqc \"$1\""; }

echo "== nginx (lab-web) =="
rweb 'sudo -n nginx -t' >/dev/null 2>&1 && ok "nginx -t" || ko "nginx -t KO"
H="$("${CURL[@]}" -D - -o /dev/null "$URL/" || true)"
grep -q ' 200' <<<"$H" && ok "/ répond 200" || ko "/ ne répond pas 200"
grep -qi 'strict-transport-security' <<<"$H" && ok "HSTS" || ko "HSTS absent"
grep -qi '^server: nginx\s*$' <<<"$H" && ok "server_tokens off" \
  || ko "version nginx exposée"
[ "$("${CURL[@]}" -o /dev/null -w '%{http_code}' "$URL/api/health")" = 200 ] \
  && ok "/api/health 200" || ko "/api/health KO"
INST="$(rweb "sudo -n awk -v d=\"\$(date -d '-5 min' +%d/%b/%Y:%H:%M)\" \
  '\$4 > \"[\"d' /var/log/nginx/factura.access.log" \
  | grep -o 'ua=127.0.0.1:800[12]' | sort -u | wc -l)"
[ "$INST" -ge 2 ] && ok "les 2 instances ont servi (5 min)" \
  || ko "une seule instance (ou aucune) a servi en 5 min : $INST"
EXP="$(rweb "echo | openssl s_client -connect 127.0.0.1:443 \
  -servername factura-demo.lab.local 2>/dev/null \
  | openssl x509 -noout -checkend 2592000" \
  && echo ok || echo ko)"
[ "$EXP" = ok ] && ok "certificat > 30 jours" || ko "certificat expire < 30 j"

echo "== PostgreSQL (lab-db) =="
rweb 'psql -h 10.10.10.12 -U factura_app -d factura_demo -Atc "SELECT 1"' \
  2>/dev/null \
  | grep -q '^1$' && ok "factura_app joignable depuis lab-web" \
  || ko "connexion factura_app depuis lab-web KO"
rdb 'sudo -n grep -Ev "^\s*#|^\s*$" /etc/postgresql/16/main/pg_hba.conf' \
  | grep -qE '\s(trust|md5)\s*$' && ko "pg_hba contient trust ou md5" \
  || ok "pg_hba sans trust/md5"
MAXC="$(sql 'SHOW max_connections')"
CUR="$(sql "SELECT count(*) FROM pg_stat_activity \
  WHERE backend_type='client backend'")"
[ $((CUR * 100 / MAXC)) -lt 80 ] && ok "connexions $CUR/$MAXC" \
  || ko "connexions $CUR/$MAXC (> 80 %)"
IIT="$(sql "SELECT count(*) FROM pg_stat_activity \
  WHERE state='idle in transaction' \
  AND state_change < now()-interval '5 min'")"
[ "$IIT" = 0 ] && ok "aucun idle in transaction > 5 min" \
  || ko "$IIT session(s) idle in transaction > 5 min"
# le glob doit être développé par root : le répertoire est en 0750 postgres
LAST="$(rdb "sudo -n sh -c 'ls -d /var/backups/postgresql/*/' 2>/dev/null \
  | tail -1")"
if [ -n "$LAST" ]; then
  AGE=$(( $(date +%s) - $(rdb "sudo -n stat -c %Y $LAST") ))
  [ "$AGE" -lt 93600 ] && ok "dernière sauvegarde : $((AGE/3600)) h" \
    || ko "sauvegarde vieille de $((AGE/3600)) h"
  rdb "sudo -n sh -c 'cd $LAST && sha256sum -c --quiet SHA256SUMS'" \
    && ok "SHA256 valides" || ko "SHA256 invalides"
else ko "aucune sauvegarde dans /var/backups/postgresql"; fi
[ "$(sql 'SELECT failed_count FROM pg_stat_archiver')" = 0 ] \
  && ok "archivage WAL sans échec" || ko "pg_stat_archiver.failed_count > 0"
FREE="$(rdb "df --output=pcent /var/lib/postgresql | tail -1 | tr -dc 0-9")"
[ "$FREE" -lt 80 ] && ok "PGDATA : $FREE % utilisés" || ko "PGDATA à $FREE %"

echo "== Redis (lab-db) =="
rdb 'redis-cli PING 2>&1' | grep -q NOAUTH && ok "PING sans auth refusé" \
  || ko "Redis accepte sans mot de passe"
RC='REDISCLI_AUTH="$(sudo -n cat /etc/factura/redis-admin.pass)"'
RC="$RC redis-cli --user admin"
MM="$(rdb "$RC CONFIG GET maxmemory | tail -1")"
POL="$(rdb "$RC CONFIG GET maxmemory-policy | tail -1")"
[ "$MM" != 0 ] && ok "maxmemory=$MM" || ko "maxmemory non défini"
[ "$POL" != noeviction ] && ok "politique $POL" || ko "politique noeviction"
FR="$(rdb "$RC INFO memory" | grep mem_fragmentation_ratio \
  | cut -d: -f2 | tr -d '\r')"
awk -v f="$FR" 'BEGIN{exit !(f>=1 && f<=1.5)}' && ok "fragmentation $FR" \
  || ko "fragmentation $FR hors [1;1.5]"
P="$(rdb "$RC INFO persistence")"
grep -q 'rdb_last_bgsave_status:ok' <<<"$P" && ok "dernier BGSAVE ok" \
  || ko "BGSAVE en échec"
grep -q 'aof_last_write_status:ok' <<<"$P" && ok "AOF ok" || ko "AOF en échec"
SW="$(rdb 'free -m | awk "/Swap/{print \$3}"')"
[ "$SW" = 0 ] && ok "pas de swap utilisé" || ko "swap utilisé sur lab-db"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
```

(Le mot de passe admin Redis est lu dans `/etc/factura/redis-admin.pass`,
`root:root 0600`, sur `lab-db` — à créer ; la ligne `sudo -n` suppose une
règle sudoers sans mot de passe pour `mathieu`, ce qui est le cas du lab. Le filtre `awk` sur `access.log` compare les dates lexicalement : c'est juste dans le mois courant, ce qui suffit pour une fenêtre de 5 minutes, sauf à cheval sur un changement de mois.)

**Runbook** — squelette attendu de `runbook-services.md` :

```markdown
# Runbook services applicatifs — Factura (lab)
## 1. Fiches par brique
### nginx (lab-web, www-data)
- conf : /etc/nginx/sites-available/factura-demo, conf.d/factura.conf, snippets/
- valider : sudo nginx -t ; recharger sans coupure : sudo systemctl reload nginx
- journaux : /var/log/nginx/factura.{access,error}.log (rt= urt= ua= us=)
### PostgreSQL 16 (lab-db, postgres)
- conf : /etc/postgresql/16/main/conf.d/10-factura.conf, pg_hba.conf
- valider : SELECT * FROM pg_hba_file_rules WHERE error IS NOT NULL ;
  pending_restart ; recharger : SELECT pg_reload_conf() ;
  restart (listen, shared_buffers, max_connections) :
  systemctl restart postgresql@16-main
- journal : /var/log/postgresql/postgresql-16-main.log
### Redis 7 (lab-db, redis)
- conf : /etc/redis/redis.conf ; à chaud : CONFIG SET + CONFIG REWRITE
- valider : redis-cli --user admin PING / INFO
- journal : /var/log/redis/redis-server.log
## 2. Ordre de démarrage / arrêt
démarrage : PostgreSQL et Redis (lab-db) -> mini-api@8001/8002 -> nginx
arrêt : nginx (maintenance.on d'abord) -> mini-api -> Redis (BGSAVE avant)
        -> PostgreSQL
pourquoi : chaque couche doit trouver la suivante prête ; nginx en dernier
pour éviter les 502 ; PostgreSQL en dernier à l'arrêt pour laisser
l'application terminer ses transactions.
## 3. Fiches incident (502, 504, no pg_hba entry, too many connections,
##    OOM Redis, sauvegarde vide) : symptôme / 3 commandes / cause / correctif
## 4. Restauration (logique : 5 s pour factura_demo ; PITR : 4 min)
## 5. Rotation des secrets
### factura_app : ALTER ROLE factura_app PASSWORD 'nouveau' ; mise à jour de
    /etc/factura/*.env et ~/.pgpass ; reload/restart de l'application ;
    fenêtre de double validité impossible en PostgreSQL -> ordonner : appli en
    pause 2 s, ALTER, reload
### Redis : ACL SETUSER factura >nouveau (l'ancien reste valide : deux mots
    de passe pendant la bascule), mise à jour de l'application, puis
    ACL SETUSER factura <ancien, ACL SAVE / CONFIG REWRITE
## 6. Preuve : sortie de verif-services.sh
## Historique
```

**Fiche entretien** : QO15.9 en donne la matière ; le format attendu est
dix lignes par brique, à la première personne, avec un exemple vécu (« sur
le lab, j'ai provoqué un 404 d'API par une regex de cache et je sais
pourquoi `^~` le rend impossible »).

> [!NOTE]
> **Pourquoi**
>
> Le script de conformité est le cœur du livrable parce qu'il transforme
> chaque leçon du module en **assertion vérifiable** : les deux instances
> qui servent (E15.6, L15.2 étape 6), `pg_hba` sans `trust`/`md5` (BF15.3),
> le taux de connexions et les `idle in transaction` (Q15.14, BF15.4), la
> sauvegarde récente et vérifiée (L15.4, BF15.6), l'archivage sans échec
> (Q15.15), `PING` refusé et la politique d'éviction (L15.5, BF15.5), la
> fragmentation et le swap (Q15.18). C'est exactement ce qu'un exporter
> Prometheus mesurera au module 26 — ici en bash, pour comprendre ce que
> chaque métrique veut dire avant de la grapher.
>
> La rotation de secrets « sans interruption » est la question de runbook
> la plus discriminante : PostgreSQL n'a qu'un mot de passe par rôle (donc
> il faut soit un second rôle temporaire, soit une micro-coupure ordonnée),
> alors que les ACL Redis acceptent **plusieurs** mots de passe par
> utilisateur (`>nouveau` ajoute, `<ancien` retire) — ce qui permet une
> bascule propre. Savoir que les deux briques diffèrent sur ce point est le
> genre de détail qui prouve une pratique réelle.

<!-- nav:début -->
---

[← Module 14](../14-ssh/corrige.md) · [Énoncé](README.md) · [Module 16 →](../16-logs-monitoring/corrige.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
