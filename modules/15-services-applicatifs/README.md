<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Partie III — Exploitation, sécurité et incidents › **Module 15**  
[← Module 14](../14-ssh/README.md) · [Corrigé](corrige.md) · [Module 16 →](../16-logs-monitoring/README.md)

<details><summary>Scripts du module (13)</summary>

Sur la VM indiquée en section « Mise en place », depuis `~/workbook/scripts/` (voir [chapitre 0](../../docs/00-mise-en-place.md)).

| Script | Rôle |
|---|---|
| [`setup_M15.sh`](../../scripts/setup/setup_M15.sh) | prépare le module |
| [`check_M15_01.sh`](../../scripts/check/check_M15_01.sh) | vérifie L15.1 |
| [`check_M15_02.sh`](../../scripts/check/check_M15_02.sh) | vérifie L15.2 |
| [`check_M15_03.sh`](../../scripts/check/check_M15_03.sh) | vérifie L15.3 |
| [`check_M15_04.sh`](../../scripts/check/check_M15_04.sh) | vérifie L15.4 |
| [`check_M15_05.sh`](../../scripts/check/check_M15_05.sh) | vérifie L15.5 |
| [`check_M15_06.sh`](../../scripts/check/check_M15_06.sh) | vérifie D15 |
| [`break_M15_01.sh`](../../scripts/break/break_M15_01.sh) | installe la panne BF15.1 |
| [`break_M15_02.sh`](../../scripts/break/break_M15_02.sh) | installe la panne BF15.2 |
| [`break_M15_03.sh`](../../scripts/break/break_M15_03.sh) | installe la panne BF15.3 |
| [`break_M15_04.sh`](../../scripts/break/break_M15_04.sh) | installe la panne BF15.4 |
| [`break_M15_05.sh`](../../scripts/break/break_M15_05.sh) | installe la panne BF15.5 |
| [`break_M15_06.sh`](../../scripts/break/break_M15_06.sh) | installe la panne BF15.6 |

</details>
<!-- nav:fin -->

# Module 15 — Services applicatifs : nginx, PostgreSQL, Redis

## 15.0 Objectifs et compétences

> [!NOTE]
> **Objectifs**
>
> Ce module ouvre la partie « Exploitation ». Les trois briques qu'on te confie
> le plus souvent sans formation sont un frontal web, une base relationnelle et
> un cache. Le projet P1 (Factura) les fait travailler ensemble ; ici tu apprends à tenir
> chacune séparément. À la fin de ce module, je sais :
>
> * lire un échange HTTP en exploitant (`curl -v`), nommer les en-têtes qui
>   comptent derrière un reverse proxy (`Host`, `X-Forwarded-For`,
>   `X-Forwarded-Proto`), et expliquer ce que change HTTP/2 et la terminaison
>   TLS ;
> * écrire un vhost nginx complet — statique, reverse proxy vers plusieurs
>   backends, TLS, limitation, authentification, journal avec temps de réponse —
>   et énoncer sans hésiter **l'ordre de priorité des blocs `location`** ;
> * diagnostiquer en moins de cinq minutes un 502, un 504, un 413, un 403 et une
>   boucle de redirection, à partir de `error.log` et de deux commandes `curl` ;
> * installer PostgreSQL 16 sur Ubuntu et Rocky, régler les douze paramètres qui
>   comptent dans `postgresql.conf`, et écrire un `pg_hba.conf` minimal qui
>   n'ouvre que ce qu'il faut, avec la bonne méthode ;
> * créer un rôle applicatif sans superuser, utiliser `psql` au quotidien sans
>   taper de mot de passe, et lire `\du`, `\l`, `\d+` ;
> * mettre en place une sauvegarde `pg_dump` nocturne **restaurée et
>   vérifiée**, et expliquer ce que `pg_basebackup` + archivage WAL apportent en
>   plus (PITR) ;
> * trouver une requête lente, une transaction qui bloque tout le monde et une
>   table gonflée avec `pg_stat_activity`, `pg_locks`, `pg_stat_user_tables` et
>   `EXPLAIN ANALYZE`, et savoir quoi faire de `VACUUM` ;
> * configurer Redis pour la production (bind, ACL, `maxmemory` et politique
>   d'éviction, persistance) et diagnostiquer une mémoire pleine, une latence ou
>   un swap avec `redis-cli` ;
> * dire, pour chacun des trois composants, quel compte de service l'exécute,
>   quelle socket Unix il ouvre et qui peut l'utiliser, dans quel ordre ils
>   démarrent, et ce qu'on doit en savoir en entretien.
>
> **Temps estimé** : 9 h (nginx 3 h 30, PostgreSQL 3 h 30, Redis 2 h)
>
> **Prérequis** : modules 08 (unités systemd, `systemctl cat`, drop-ins),
> 12 (`ss`, `curl`, `/etc/hosts`), 14 (SSH entre les VM). Les certificats sont
> fabriqués au module 18 (L18.4) : ici on les **configure** dans nginx. Les
> timers de sauvegarde sont détaillés au module 17, les journaux au module 16.

---

## 15.1 Mise en place

VM concernées : **`lab-web` (10.10.10.11)** pour HTTP et nginx,
**`lab-db` (10.10.10.12)** pour PostgreSQL et Redis. `lab-adm` (10.10.10.10)
sert de poste client pour tester « depuis l'extérieur ». `lab-ops`
(10.10.10.14) n'intervient que dans le lab facultatif de réplication.

```bash
# depuis le shell Proxmox, avant de commencer
qm snapshot 9002 avant-lab15
qm snapshot 9003 avant-lab15
```

Sur chacune des deux VM, depuis ton clone du workbook :

```bash
sudo bash ~/workbook/scripts/setup/setup_M15.sh
```

Le script détecte le hostname. Il installe les paquets et prépare le terrain,
mais **ne configure rien** de ce que le module t'apprend à configurer :

| VM | Ce que le setup installe | Ce qu'il laisse à faire |
|---|---|---|
| `lab-web` | nginx (conf d'origine), `mini-api` en 2 instances (8001, 8002) sous `mini-api@.service`, site statique `/srv/www/factura-demo`, page 503, `psql`, `redis-cli`, `htpasswd` | tous les vhosts |
| `lab-db` | PostgreSQL 16 (cluster `16/main`) avec la base `factura_demo` (400 000 lignes, aucun index utile), rôles `factura_app` et `factura_ro`, Redis 7 en conf d'origine, `redis-app.py` | `listen_addresses`, `pg_hba.conf`, tuning, `redis.conf` |

Les identifiants de la base d'exemple sont dans `/etc/factura/db.env` sur
`lab-db` (lisible par le groupe `factura`, dans lequel le setup t'ajoute :
reconnecte-toi). Outils fournis dans `/opt/factura/bin/` :

| Outil | Rôle |
|---|---|
| `mini-api.py --port N` | backend HTTP : `/api/health`, `/api/whoami` (en-têtes reçus), `/api/invoices.json`, `/api/slow?s=N`, `/api/upload` (POST), `/api/login`, `/api/metrics`, `/api/stream` |
| `tir.sh URL [N]` | N requêtes, compte les codes HTTP |
| `requete-lente.sql`, `charge-sql.sh [P] [T]` | la requête lente de l'application, et une charge |
| `verrou-demo.sh [N]` | une transaction qui verrouille une facture N secondes |
| `redis-app.py [--url] [--loop]` | simule l'application côté Redis (sessions, compteurs, file) |

> [!IMPORTANT]
> **Variante Rocky / RHEL**
>
> Ce module se joue sur Ubuntu. Les écarts Rocky 9 sont donnés en encadrés :
> `dnf install nginx` (pas de `sites-enabled`, tout dans `conf.d/`), module
> `postgresql:16` et `postgresql-setup --initdb`, SELinux qui bloque
> `proxy_pass` tant que `httpd_can_network_connect` est à `off`. Si tu veux les
> rejouer, `lab-rhel` (10.10.10.13) suffit pour la partie nginx.

> [!CAUTION]
> **Attention**
>
> Les labs de la partie PostgreSQL redémarrent le cluster et modifient
> `pg_hba.conf` ; L15.4 active l'archivage WAL et joue une restauration à un
> instant donné. Le Break & Fix BF15.4 sature les connexions et t'interdit de
> redémarrer la base. Les snapshots ne sont pas optionnels.

---

## 15.2 Rappel express

### A — HTTP vu de l'ops

```bash
curl -sI http://10.10.10.11/            # en-têtes seuls (HEAD)
curl -sv http://10.10.10.11/api/health -o /dev/null   # dialogue complet
curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' URL
curl -H 'Host: factura-demo.lab.local' http://10.10.10.11/
curl --resolve factura-demo.lab.local:443:10.10.10.11 \
  https://factura-demo.lab.local/
curl -k https://... ; curl --cacert ca.crt https://...
curl -X POST --data-binary @fichier URL ; curl -u admin:secret URL
```

| Code | Sens pour l'ops |
|---|---|
| `301`/`302`/`308` | redirection ; `301` est mis en cache par le navigateur |
| `400`, `413`, `414` | requête refusée par nginx lui-même (taille : `client_max_body_size`) |
| `401` / `403` | auth manquante / interdit (droits fichiers, `deny`, `try_files`) |
| `404` | nginx ne trouve pas : mauvais `root`, mauvaise `location` |
| `429` / `503` | `limit_req` ; `503` aussi pour la page de maintenance |
| `502` | nginx n'a pas pu parler au backend (mort, mauvais port, socket, SELinux) |
| `504` | le backend n'a pas répondu à temps (`proxy_read_timeout`) |

En-têtes à connaître : `Host` (quel vhost), `X-Forwarded-For` (IP réelle
derrière le proxy — le backend ne voit que 127.0.0.1 sinon),
`X-Forwarded-Proto` (l'app sait qu'elle est en HTTPS), `Cache-Control` /
`Expires`, `Connection: keep-alive` (HTTP/1.1 réutilise la connexion TCP).
HTTP/2 : une connexion, flux multiplexés, en-têtes compressés ; côté nginx
c'est une option de `listen`, le backend reste en HTTP/1.1. **Terminaison
TLS** : nginx déchiffre, le backend parle en clair sur `127.0.0.1`.

### A — nginx (Ubuntu 24.04, nginx 1.24)

```text
/etc/nginx/nginx.conf            user www-data ; include conf.d/*.conf ;
                                 include sites-enabled/*
/etc/nginx/sites-available/X     le vhost ; sites-enabled/X -> lien symbolique
/etc/nginx/conf.d/*.conf         fragments globaux (log_format, upstream, map)
/etc/nginx/snippets/             morceaux à inclure (TLS, en-têtes)
/var/log/nginx/{access,error}.log   /var/www/html (site default)
```

```bash
sudo nginx -t                    # syntaxe + fichiers référencés
sudo nginx -T | less             # conf EFFECTIVE, includes résolus
sudo systemctl reload nginx      # nouveaux workers, les anciens finissent
sudo systemctl restart nginx     # seulement si listen/user/modules changent
sudo ln -s /etc/nginx/sites-available/X /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo tail -f /var/log/nginx/error.log
```

**Priorité des `location`** — la règle, dans l'ordre :

1. `location = /uri` : correspondance exacte, gagne toujours.
2. Le **préfixe le plus long** est retenu ; s'il est marqué `^~`, on s'arrête là.
3. Sinon les **regex** (`~` sensible, `~*` insensible) sont testées **dans
   l'ordre du fichier** : la première qui correspond gagne.
4. Aucune regex ne correspond : le préfixe le plus long s'applique.

Conséquence : une regex `~* \.(json|js)$` ajoutée « pour le cache » capture
`/api/invoices.json` et court-circuite `location /api/`. Parade : `^~ /api/`.

```nginx
server {
    listen 80; listen [::]:80;
    server_name factura-demo.lab.local;
    root /srv/www/factura-demo;
    index index.html;
    location / { try_files $uri $uri/ =404; }        # ou /index.html (SPA)
    location /static/ { expires 30d; add_header Cache-Control "public"; }
    location /docs/ { alias /srv/www/factura-demo/docs/; }   # alias = remplace
    location ^~ /api/ {
        proxy_pass http://factura_api;        # sans URI : chemin conservé
        proxy_http_version 1.1;
        proxy_set_header Connection "";              # keepalive vers l'upstream
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 3s; proxy_read_timeout 30s;
    }
}
upstream factura_api {                                # dans conf.d/ ou http{}
    server 127.0.0.1:8001; server 127.0.0.1:8002 max_fails=2 fail_timeout=10s;
    keepalive 16;
}
```

`root` **ajoute** l'URI complète au chemin ; `alias` **remplace** la partie
correspondant à la location (les deux barres finales comptent).
`proxy_pass http://b;` transmet l'URI telle quelle ; `proxy_pass http://b/;`
remplace le préfixe de la location par `/` (interdit dans une location regex).

<p align="center"><img src="../../assets/figures/nginx-upstream.svg" alt="Schéma : nginx-upstream"></p>

*Figure — Client HTTPS → nginx (TLS, `location`, statique) → `upstream factura_api` (deux instances) → PostgreSQL et Redis sur lab-db ; le 502 naît quand nginx ne peut pas parler au backend, le 504 quand le backend ne répond pas à temps.*

| Directive | Rôle |
|---|---|
| `try_files $uri $uri/ /index.html;` | fichier, puis dossier, puis repli |
| `return 301 https://$host$request_uri;` | redirection : préférer à `rewrite` |
| `rewrite ^/ancien/(.*)$ /nouveau/$1 permanent;` | réécriture regex |
| `map $http_upgrade $connection_upgrade { default upgrade; '' close; }` | variable calculée (WebSocket) |
| `limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;` | zone (http{}) |
| `limit_req zone=login burst=5 nodelay; limit_req_status 429;` | dans la location |
| `limit_conn_zone $binary_remote_addr zone=perip:10m; limit_conn perip 20;` | connexions simultanées |
| `auth_basic "Zone"; auth_basic_user_file /etc/nginx/.htpasswd;` | `htpasswd -cB fichier user` |
| `allow 10.10.10.14; deny all;` | premier qui correspond gagne |
| `client_max_body_size 2m;` | sinon `413` à 1 Mo |
| `proxy_buffering off;` | flux, SSE : sinon nginx accumule |
| `gzip on; gzip_types text/css application/javascript application/json;` | `text/html` est implicite |
| `add_header X-Frame-Options DENY always;` | **un `add_header` dans une location annule ceux du server** |

```nginx
log_format factura '$remote_addr - $remote_user [$time_local] "$request" '
    '$status $body_bytes_sent "$http_referer" "$http_user_agent" '
    'rt=$request_time urt=$upstream_response_time ua=$upstream_addr '
    'us=$upstream_status';
access_log /var/log/nginx/factura.access.log factura;
error_log  /var/log/nginx/factura.error.log warn;   # debug..warn error crit
```

TLS (certificats : module 18) : `listen 443 ssl http2;`,
`ssl_certificate` (serveur **puis** chaîne), `ssl_certificate_key`,
`ssl_protocols TLSv1.2 TLSv1.3;`, `ssl_session_cache shared:SSL:10m;`,
`add_header Strict-Transport-Security "max-age=31536000" always;`, server
séparé sur 80 avec `return 301`. OCSP stapling (`ssl_stapling on`) : nginx
joint la preuve de non-révocation ; sans intérêt avec une CA de lab.

Maintenance sans redémarrer : `if (-f /srv/www/maintenance.on) { return 503; }`
dans `location /`, `error_page 503 @maintenance;` et une location nommée qui
sert la page. Blue/green : `root` pointe sur un lien symbolique qu'on bascule
(module 25).

Diagnostic dans `error.log` : `connect() failed (111: Connection refused)`
→ 502, backend mort ou mauvais port ; `(13: Permission denied) while
connecting to upstream` → socket Unix ou SELinux ; `upstream timed out (110)`
→ 504 ; `client intended to send too large body` → 413 ; `directory index of
"..." is forbidden` → 403 sans `index` ; `open() ... failed (2: No such file)`
→ 404, mauvais `root`/`alias`. Boucle de redirection : `return 301 https://`
dans un `server` qui écoute aussi en 443, ou proto ignoré derrière un LB.

> [!IMPORTANT]
> **Variante Rocky / RHEL**
>
> Rocky 9 : `dnf install nginx`, user `nginx`, tout dans `/etc/nginx/conf.d/`.
> SELinux : `setsebool -P httpd_can_network_connect 1` pour `proxy_pass`, et
> `semanage port -a -t http_port_t -p tcp 8081` pour un port non standard.
> `firewall-cmd --add-service={http,https} --permanent`. Apache : `a2ensite`,
> `a2enmod`, `apachectl configtest`, `.htaccess` par répertoire (nginx n'en a
> pas, par conception : tout est central). Caddy : `Caddyfile` de trois lignes,
> HTTPS automatique. Traefik : reverse proxy piloté par labels Docker (module 22).

### B — PostgreSQL 16

```text
Ubuntu : apt install postgresql-16    Rocky : dnf module enable postgresql:16
  pg_lsclusters ; postgresql@16-main.service   dnf install postgresql-server
  /etc/postgresql/16/main/{postgresql.conf,     postgresql-setup --initdb
       pg_hba.conf,pg_ident.conf,conf.d/}       PGDATA=/var/lib/pgsql/data
  PGDATA=/var/lib/postgresql/16/main            (conf DANS PGDATA)
  /var/log/postgresql/postgresql-16-main.log    postgresql.service
  /usr/lib/postgresql/16/bin/                   firewall-cmd --add-service=
                                                  postgresql
  socket /run/postgresql/.s.PGSQL.5432
```

```bash
sudo -u postgres psql                       # peer : compte Unix = rôle
psql -h 10.10.10.12 -U factura_app -d factura_demo      # -W force le prompt
psql -Atc "SELECT 1" ; psql -f script.sql -v ON_ERROR_STOP=1 ; psql --csv
\l  \du  \dn  \dt+  \d+ invoices  \di  \x  \timing  \conninfo  \c base role
SHOW listen_addresses; SELECT pg_reload_conf();
SELECT name, setting, unit, context, pending_restart FROM pg_settings
  WHERE name IN ('max_connections','shared_buffers');
  -- context = postmaster : restart obligatoire
ALTER SYSTEM SET work_mem = '16MB';         # écrit postgresql.auto.conf
sudo systemctl reload postgresql@16-main
sudo systemctl restart postgresql@16-main
```

Mot de passe sans le taper : `PGPASSWORD=...` (visible dans `ps` / l'env),
`~/.pgpass` en **0600** au format `hôte:port:base:rôle:mdp`, ou variables
`PGHOST`/`PGUSER`/`PGDATABASE`.

Les douze paramètres (`postgresql.conf` ou `conf.d/10-site.conf`) :

| Paramètre | Valeur de départ (VM 2 Go) | Rechargement |
|---|---|---|
| `listen_addresses` | `'localhost,10.10.10.12'` (jamais `'*'` sans pare-feu) | restart |
| `port`, `max_connections` | `5432`, `100` (chaque connexion = un processus) | restart |
| `shared_buffers` | 25 % de la RAM : `512MB` | restart |
| `work_mem` | `8MB` **par opération de tri**, par requête | reload |
| `effective_cache_size` | 50–75 % de la RAM : `1536MB` (indice pour le planificateur) | reload |
| `wal_level` | `replica` (défaut) ; `logical` pour la réplication logique | restart |
| `log_min_duration_statement` | `500` ms : journalise les requêtes lentes | reload |
| `log_line_prefix`, `log_lock_waits`, `log_checkpoints` | `'%m [%p] %u@%d '`, `on`, `on` | reload |
| `timezone` | `'Europe/Paris'` | reload |
| `shared_preload_libraries` | `'pg_stat_statements'` | restart |
| `password_encryption` | `scram-sha-256` (défaut 16) | reload |
| `archive_mode` / `archive_command` | `on` / un script qui copie `%p` vers l'archive sous le nom `%f` **sans écraser** | restart / reload |

`pg_hba.conf` : `TYPE  DATABASE  USER  ADDRESS  METHOD`. **Première ligne qui
correspond, et une seule** : si l'authentification échoue, on ne passe pas à
la suivante. `local` = socket Unix ; `host` = TCP ; `hostssl` = TCP chiffré.
Méthodes : `peer` (compte Unix = rôle, socket seulement), `scram-sha-256`
(mot de passe, le seul acceptable), `md5` (hérité ; accepte un secret SCRAM
mais pas l'inverse), `trust` (aucune vérification : interdit), `reject`.

```text
local   all            postgres                            peer
local   all            all                                 peer
host    all            all            127.0.0.1/32         scram-sha-256
host    factura_demo   factura_app    10.10.10.11/32       scram-sha-256
```

`SELECT * FROM pg_hba_file_rules;` montre les règles chargées et les erreurs.

Rôles : `CREATE ROLE factura_app LOGIN PASSWORD '...';`, `CREATE DATABASE
factura_demo OWNER factura_app;`, `GRANT SELECT ON ALL TABLES IN SCHEMA public
TO factura_ro; ALTER DEFAULT PRIVILEGES ... GRANT SELECT ON TABLES TO
factura_ro;`. L'application n'est **jamais** superuser ni propriétaire de
`postgres`.

Sauvegardes :

```bash
pg_dump -Fc -d factura_demo -f factura_demo.dump  # custom : compressé, -j
pg_dump -Fp -d factura_demo > factura_demo.sql    # plain : restaurable via psql
pg_dumpall --globals-only > globals.sql              # rôles et mots de passe
pg_restore -l factura_demo.dump | head               # contenu (TOC)
createdb -O factura_app factura_restore
pg_restore -d factura_restore --no-owner -j 2 factura_demo.dump
pg_basebackup -D /srv/pg-archive/base -Ft -z -Xs -P -c fast   # physique
```

`pg_dump` = état logique à l'instant T (RPO = intervalle). `pg_basebackup` +
archivage WAL = restauration à **n'importe quel instant** (PITR) :
`restore_command = 'cp /srv/pg-archive/wal/%f %p'`,
`recovery_target_time = '...'`, fichier `recovery.signal`, démarrage.

Supervision :

```sql
SELECT pid, usename, state, wait_event_type, now()-query_start AS age,
       left(query,60) FROM pg_stat_activity WHERE state <> 'idle'
       ORDER BY age DESC;
SELECT pid, pg_blocking_pids(pid), state, left(query,50)
  FROM pg_stat_activity WHERE cardinality(pg_blocking_pids(pid)) > 0;
SELECT pg_cancel_backend(pid); SELECT pg_terminate_backend(pid);
SELECT relname, seq_scan, idx_scan, n_live_tup, n_dead_tup, last_autovacuum
  FROM pg_stat_user_tables ORDER BY n_dead_tup DESC;
SELECT pg_size_pretty(pg_database_size('factura_demo'));
SELECT relname, pg_size_pretty(pg_total_relation_size(oid)) FROM pg_class
  WHERE relkind='r' AND relnamespace='public'::regnamespace;
SELECT calls, round(mean_exec_time) ms, left(query,60) FROM pg_stat_statements
  ORDER BY total_exec_time DESC LIMIT 5;
EXPLAIN (ANALYZE, BUFFERS) SELECT ...;  -- Seq Scan + Rows Removed = index ?
CREATE INDEX CONCURRENTLY ON invoices (customer_id);
VACUUM (VERBOSE, ANALYZE) invoices;  -- VACUUM FULL verrouille : pas en journée
```

Pannes : `remaining connection slots are reserved` → `max_connections` atteint (connexions `idle`, pool absent) ; `too many connections for role` → `CONNECTION LIMIT` du rôle atteint;
`no pg_hba.conf entry for host` → ligne manquante (adresse, base, rôle,
SSL) ; `password authentication failed` → mot de passe, ou secret `md5`
face à une méthode `scram` ; `Connection refused` → `listen_addresses` ou
pare-feu ; `PANIC: could not write to file "pg_wal/..."` → disque plein,
**ne jamais supprimer** `pg_wal/` à la main (chercher `archive_command` en
échec dans `pg_stat_archiver` ou un slot de réplication inactif).
Mise à jour majeure Ubuntu : `pg_upgradecluster 16 main` (crée `17/main` sur
5433, bascule), puis `pg_dropcluster 16 main`. Exporter Prometheus :
`postgres_exporter` (module 26).

### C — Redis 7

```text
apt install redis-server   redis-server.service
/etc/redis/redis.conf (redis:redis 0640)
/var/lib/redis/dump.rdb    /var/log/redis/redis-server.log
/run/redis/redis-server.sock (si unixsocket est activé)
```

| `redis.conf` | Production |
|---|---|
| `bind 127.0.0.1 10.10.10.12` / `protected-mode yes` | jamais `0.0.0.0` : Redis n'a pas d'auth par défaut |
| `requirepass` ou `user app on >mdp ~factura:* +@all -@dangerous` | ACL par utilisateur ; `user default off` |
| `maxmemory 128mb` / `maxmemory-policy` | `noeviction` (file), `volatile-lru` (cache avec TTL), `allkeys-lru` (cache pur) |
| `save 3600 1 300 100 60 10000` | RDB : instantané par `fork()`, perte possible entre deux |
| `appendonly yes` / `appendfsync everysec` | AOF : journal ; `always` = lent, `no` = OS décide |
| `dir /var/lib/redis` | où vivent `dump.rdb` et `appendonlydir/` |

```bash
redis-cli -h 10.10.10.12 -a 'mdp' PING ; redis-cli --user app --pass 'mdp'
export REDISCLI_AUTH='mdp'               # évite le mot de passe dans ps
redis-cli INFO memory | grep -E 'used_memory:|used_memory_rss|fragmentation'
redis-cli INFO stats | grep -E 'evicted|expired|rejected|keyspace'
redis-cli INFO persistence ; redis-cli INFO clients ; INFO keyspace
redis-cli CONFIG GET 'maxmemory*'
redis-cli CONFIG SET maxmemory-policy volatile-lru ; redis-cli CONFIG REWRITE
redis-cli --scan --pattern 'sess:*' | head   # jamais KEYS * en prod
redis-cli --stat ; --latency ; --bigkeys ; SLOWLOG GET 10 ; CLIENT LIST
redis-cli MONITOR                  # coûteux : quelques secondes, pas plus
redis-cli BGSAVE ; LASTSAVE ; cp /var/lib/redis/dump.rdb /var/backups/
```

Structures : string (`SET k v EX 1800`, `INCR`, `TTL`), hash (`HSET user:1
name x`, `HGETALL`), list = file (`LPUSH`, `BRPOP`, `LLEN`), set (`SADD`,
`SISMEMBER`), sorted set (`ZADD`). Diagnostic : `used_memory` = ce que Redis
croit occuper, `used_memory_rss` = ce que le noyau lui donne ;
`mem_fragmentation_ratio` > 1,5 = fragmentation, **< 1 = la machine swappe**,
et Redis en swap répond en secondes. `OOM command not allowed` = `maxmemory`
atteint en `noeviction`. `MISCONF ... unable to persist` = `BGSAVE` échoue
(disque, droits) et Redis refuse les écritures. Valkey (fork communautaire
2024, compatible) remplace Redis dans Fedora/Rocky 10 ; Sentinel = bascule
automatique primaire/réplica ; Cluster = partitionnement en 16 384 slots.

### D — Transversal

`systemctl cat nginx postgresql@16-main redis-server` : `www-data`,
`postgres`, `redis` ; sockets `/run/postgresql/.s.PGSQL.5432` (mode `777`,
protégée par `pg_hba`) et `/run/redis/redis-server.sock` (mode `700` si
activée, protégée par le groupe `redis`). Une app **sur la même machine**
déclare `After=postgresql.service redis-server.service` ; sur une autre
machine, `After=network-online.target` et une reconnexion applicative.
`postgresql.service` est une unité parapluie (`oneshot`) : l'unité réelle
est `postgresql@16-main.service`.

---

## 15.3 Quiz — QCM

<a id="q15-1"></a>**[Q15.1](corrige.md#q15-1)** — Le vhost de `lab-web` contient, dans cet ordre :

```nginx
location /api/ { proxy_pass http://factura_api; }
location ~* \.(json|js|css)$ { root /srv/www/factura-demo; expires 7d; }
```

`GET /api/invoices.json` arrive. Quel bloc traite la requête, et avec quel
résultat ?

a) `location /api/` : c'est le premier du fichier
b) `location /api/` : `/api/` est un préfixe plus long que la regex
c) la regex : elle est testée après le meilleur préfixe et gagne dès qu'elle
   correspond ; nginx cherche `/srv/www/factura-demo/api/invoices.json` et
   répond 404
d) nginx refuse la configuration : deux locations se recouvrent

<a id="q15-2"></a>**[Q15.2](corrige.md#q15-2)** — `location /api/ { proxy_pass http://127.0.0.1:8001/; }` reçoit
`GET /api/health?x=1`. Que reçoit le backend ?

a) `GET /api/health?x=1`
b) `GET /health?x=1` : la barre finale de `proxy_pass` remplace le préfixe
   `/api/` par `/`
c) `GET /health` : les paramètres sont perdus
d) `GET //api/health?x=1`

<a id="q15-3"></a>**[Q15.3](corrige.md#q15-3)** — `location /static/ { root /srv/www/factura-demo/static/; }` puis
`GET /static/app.js`. Quel fichier nginx ouvre-t-il ?

a) `/srv/www/factura-demo/static/app.js`
b) `/srv/www/factura-demo/static/static/app.js` : `root` concatène l'URI
   complète ; il fallait `alias`
c) `/srv/www/factura-demo/app.js`
d) nginx répond 403 : `root` est interdit dans une location

<a id="q15-4"></a>**[Q15.4](corrige.md#q15-4)** — Tu modifies un vhost et tapes `sudo systemctl reload nginx` sans
`nginx -t`. La conf contient une erreur. Que se passe-t-il ?

a) nginx s'arrête, le site est coupé
b) le processus maître relit la conf, la refuse, journalise l'erreur et
   **continue avec l'ancienne** ; les workers ne sont pas remplacés
c) nginx charge la conf partiellement, jusqu'à la ligne fautive
d) le reload attend la fin des requêtes en cours puis échoue

<a id="q15-5"></a>**[Q15.5](corrige.md#q15-5)** — `error.log` : `connect() failed (111: Connection refused) while
connecting to upstream, client: 10.10.10.10, upstream: "http://127.0.0.1:8003/api/health"`.
Le navigateur voit :

a) `504 Gateway Time-out`, le backend est lent
b) `502 Bad Gateway` : rien n'écoute sur 127.0.0.1:8003 (backend mort ou
   mauvais port dans `upstream`)
c) `503 Service Unavailable` à cause de `limit_req`
d) `403 Forbidden`, SELinux bloque la connexion

<a id="q15-6"></a>**[Q15.6](corrige.md#q15-6)** — `curl -sIL http://factura-demo.lab.local/` affiche vingt fois de
suite `HTTP/1.1 301 Moved Permanently` puis `curl` abandonne. Cause probable ?

a) le backend renvoie 301 sur `/`
b) un `return 301 https://$host$request_uri;` est placé dans un `server`
   qui écoute **aussi** en 443, ou nginx ignore `X-Forwarded-Proto` derrière
   un équilibreur qui termine le TLS
c) `try_files` boucle sur `$uri/`
d) le cache de `curl` rejoue l'ancienne redirection

<a id="q15-7"></a>**[Q15.7](corrige.md#q15-7)** — Le bloc `server` contient `add_header Strict-Transport-Security
"max-age=31536000" always;`. La location `/api/` contient
`add_header X-Request-Id $request_id;`. Sur `/api/health`, l'en-tête HSTS
est :

a) présent : les `add_header` s'additionnent à chaque niveau
b) **absent** : dès qu'un niveau définit son propre `add_header`, il n'hérite
   plus de ceux du niveau supérieur ; il faut répéter HSTS ou utiliser un
   `include`
c) présent seulement si la réponse est un 200
d) absent parce que `always` ne s'applique pas aux locations

<a id="q15-8"></a>**[Q15.8](corrige.md#q15-8)** — `limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;`
et, dans `location /api/login`, `limit_req zone=login burst=5 nodelay;`. Une
IP envoie 12 requêtes en une seconde. Combien passent, et quel code reçoivent
les autres ?

a) 5 passent, les 7 autres reçoivent 429
b) 6 passent (1 au débit + 5 de rafale, servies sans délai grâce à
   `nodelay`), les 6 autres reçoivent **503** par défaut — 429 seulement avec
   `limit_req_status 429`
c) toutes passent, mais ralenties à une toutes les 12 secondes
d) 10 passent, les 2 autres sont mises en attente

<a id="q15-9"></a>**[Q15.9](corrige.md#q15-9)** — Sur `lab-db`, tu passes `listen_addresses` de `localhost` à
`localhost,10.10.10.12` et tu ajoutes une ligne à `pg_hba.conf`. Quelle
séquence minimale rend les deux effectifs ?

a) `SELECT pg_reload_conf();` suffit pour les deux
b) `sudo systemctl restart postgresql@16-main` : `listen_addresses` a le
   contexte `postmaster` (restart obligatoire) ; le restart relit aussi
   `pg_hba.conf`
c) `sudo systemctl reload postgresql` puis `pg_ctlcluster 16 main reload`
d) rien, PostgreSQL surveille ses fichiers

<a id="q15-10"></a>**[Q15.10](corrige.md#q15-10)** — `pg_hba.conf` contient dans cet ordre :

```text
host    all           all           10.10.10.0/24     reject
host    factura_demo  factura_app   10.10.10.11/32    scram-sha-256
```

Depuis `lab-web`, `factura_app` se connecte avec le bon mot de passe. Résultat ?

a) accepté : la ligne la plus précise gagne
b) refusé, `pg_hba.conf rejects connection for host "10.10.10.11"` : la
   **première** ligne dont l'adresse, la base et le rôle correspondent
   s'applique, et on ne passe jamais à la suivante
c) accepté après un second essai
d) refusé pour `no pg_hba.conf entry`

<a id="q15-11"></a>**[Q15.11](corrige.md#q15-11)** — L'API loggue `FATAL: remaining connection slots are reserved for
roles with the SUPERUSER attribute`. **Deux réponses correctes.**

a) `max_connections` moins les slots réservés est atteint ; il faut regarder
   `pg_stat_activity` — souvent des dizaines de connexions `idle` que
   l'application n'a jamais fermées
b) on peut encore se connecter en `postgres` par la socket pour diagnostiquer
   et terminer des sessions avec `pg_terminate_backend(pid)`
c) `ALTER SYSTEM SET max_connections = 500` puis `pg_reload_conf()` corrige
   sans redémarrer
d) le message signifie que le mot de passe de `factura_app` est expiré

<a id="q15-12"></a>**[Q15.12](corrige.md#q15-12)** — Quel avantage réel a `pg_dump -Fc` sur `pg_dump` en SQL brut ?

a) il est plus fidèle : le format plain perd les index
b) il permet une restauration **sélective** (`pg_restore -t table`, `-l` /
   `-L`), **parallèle** (`-j`) et compressée, restaurable avec `pg_restore`
   au lieu de `psql`
c) il inclut les rôles et les mots de passe
d) il est incrémental

<a id="q15-13"></a>**[Q15.13](corrige.md#q15-13)** — `EXPLAIN (ANALYZE, BUFFERS)` sur la requête de l'écran client :

```text
Seq Scan on invoices  (cost=0.00..3073.00 rows=20 width=0)
                      (actual time=0.969..6.189 rows=18 loops=1)
  Filter: (customer_id = 4242)
  Rows Removed by Filter: 99982
```

Conclusion la plus juste ?

a) l'estimation est fausse, il faut `ANALYZE invoices`
b) la table est parcourue entièrement pour garder 18 lignes sur 100 000 :
   il manque un index sur `invoices(customer_id)` ; à créer avec
   `CREATE INDEX CONCURRENTLY` en production
c) `work_mem` est trop bas
d) la requête est déjà optimale : 6 ms

<a id="q15-14"></a>**[Q15.14](corrige.md#q15-14)** — `pg_stat_activity` montre une session `idle in transaction` depuis
3 heures, et quatre sessions `active` en `wait_event_type = Lock` sur la
même table. Que fais-tu ?

a) `pg_cancel_backend` sur les quatre sessions bloquées
b) `pg_terminate_backend` sur la session `idle in transaction` (elle tient
   des verrous sans rien faire), puis on cherche dans l'application la
   transaction ouverte jamais validée et on pose
   `idle_in_transaction_session_timeout`
c) `VACUUM FULL` de la table pour libérer les verrous
d) redémarrer PostgreSQL, c'est plus sûr

<a id="q15-15"></a>**[Q15.15](corrige.md#q15-15)** — Le journal contient `PANIC: could not write to file
"pg_wal/xlogtemp.1234": No space left on device` et PostgreSQL s'est arrêté.
**Deux réponses correctes.**

a) supprimer les plus vieux fichiers de `pg_wal/` pour redémarrer vite
b) libérer de l'espace **ailleurs** (journaux, `/tmp`, dumps) puis redémarrer,
   et chercher pourquoi `pg_wal` a grossi : `archive_command` en échec
   (`pg_stat_archiver`) ou slot de réplication inactif
c) `pg_wal` qui grossit sans limite est presque toujours le symptôme d'un
   archivage ou d'une réplication qui ne consomme plus, pas d'une base trop
   active
d) passer `wal_level = minimal` règle définitivement le problème

<a id="q15-16"></a>**[Q15.16](corrige.md#q15-16)** — Redis sert à la fois de cache de sessions (clés avec TTL) et de
file de travaux (`LPUSH factura:jobs`, sans TTL). `maxmemory` est atteint.
Quelle politique est la moins mauvaise ?

a) `noeviction` : rien n'est perdu
b) `allkeys-lru` : tout est cache
c) `volatile-lru` : seules les clés qui ont un TTL (les sessions) sont
   évincées ; la file, sans TTL, est protégée — et en `noeviction` les
   écritures échoueraient avec `OOM command not allowed`
d) `volatile-ttl` sans `maxmemory`

<a id="q15-17"></a>**[Q15.17](corrige.md#q15-17)** — Un collègue lance `redis-cli KEYS 'sess:*' | wc -l` sur la
production pour « compter les sessions ». Pourquoi est-ce interdit ?

a) `KEYS` n'existe plus en Redis 7
b) Redis est mono-thread : `KEYS` parcourt **tout** l'espace de clés en
   bloquant toutes les autres commandes pendant ce temps ; on utilise
   `SCAN` (curseur, par lots) ou `redis-cli --scan --pattern`
c) `KEYS` renvoie aussi les clés expirées
d) c'est autorisé si `protected-mode` est actif

<a id="q15-18"></a>**[Q15.18](corrige.md#q15-18)** — `INFO memory` sur `lab-db` :

```text
used_memory:1258291200
used_memory_rss:3984588800
mem_fragmentation_ratio:3.17
```

**Deux réponses correctes.**

a) Redis utilise 3,9 Go côté noyau pour 1,2 Go de données utiles : forte
   fragmentation, typique après une suppression massive de clés
b) un ratio **inférieur à 1** aurait signifié l'inverse : une partie de la
   mémoire de Redis est en swap, et chaque commande peut prendre des secondes
c) `maxmemory` doit être monté à 4 Go pour couvrir le RSS
d) `FLUSHALL` est la réponse standard

---

## 15.4 Quiz — questions ouvertes

<a id="qo15-1"></a>**[QO15.1](corrige.md#qo15-1)** — *On te demande en entretien* : « Un navigateur demande
`https://factura.lab.local/api/invoices`. Raconte-moi ce qui se passe entre
l'arrivée du paquet sur `lab-web` et la réponse de Gunicorn. » Couvre : la
terminaison TLS, le choix du `server` (par quoi ?), le choix de la
`location`, les en-têtes que nginx ajoute et pourquoi le backend en a
besoin, ce que change `keepalive` vers l'upstream, et ce que le backend voit
comme adresse source.

<a id="qo15-2"></a>**[QO15.2](corrige.md#qo15-2)** — Énonce la règle complète de sélection d'un bloc `location`
(exact, préfixe, `^~`, regex, ordre du fichier). Donne trois configurations
où « le bloc évident » n'est pas celui qui sert la requête, et pour chacune
la correction. Explique enfin la différence entre `root` et `alias` avec un
exemple de chemin résolu.

<a id="qo15-3"></a>**[QO15.3](corrige.md#qo15-3)** — Décris ta méthode de diagnostic pour chacun de ces codes renvoyés
par nginx : 502, 504, 413, 403, 404 et une boucle de 301. Pour chaque cas :
la commande `curl` qui le confirme, la ligne que tu cherches dans
`error.log`, les deux ou trois causes racines classiques, et le correctif.

<a id="qo15-4"></a>**[QO15.4](corrige.md#qo15-4)** — *On te demande en entretien* : « Explique-moi comment PostgreSQL
décide d'accepter une connexion. » Traite : le rôle de `pg_hba.conf` et son
ordre d'évaluation, `local` vs `host` vs `hostssl`, les méthodes `peer`,
`scram-sha-256`, `md5` et `trust` (et pourquoi `trust` même sur `localhost`
est un problème), ce que `listen_addresses` fait *avant* `pg_hba.conf`, et
les trois messages d'erreur qui te disent à quelle étape ça bloque.

<a id="qo15-5"></a>**[QO15.5](corrige.md#qo15-5)** — Compare `pg_dump` et `pg_basebackup` + archivage WAL : ce que
chacun capture, le RPO qu'il permet, le temps de restauration, la place, les
cas d'usage. Décris ensuite ce que veut dire « une sauvegarde testée » avec
la procédure exacte et une métrique de succès. Termine par ce que
`pg_dumpall --globals-only` apporte et pourquoi on l'oublie.

<a id="qo15-6"></a>**[QO15.6](corrige.md#qo15-6)** — « La base est lente depuis ce matin. » Donne, dans l'ordre, les
cinq premières requêtes SQL que tu exécutes (sur quelles vues) et ce que tu
cherches dans chacune. Explique ensuite ce qu'est le *bloat*, ce que fait
`VACUUM` (et ce qu'il ne fait pas), pourquoi `VACUUM FULL` est dangereux en
journée, et comment tu vérifies qu'`autovacuum` fait son travail sur une
table.

<a id="qo15-7"></a>**[QO15.7](corrige.md#qo15-7)** — *On te demande en entretien* : « Redis, c'est un cache ou une
base de données ? » Réponds en expliquant ce qui se passe quand la mémoire
atteint `maxmemory` selon la politique, la différence RDB / AOF et ce que
chacune perd en cas de coupure, pourquoi `appendfsync always` est rarement
choisi, pourquoi un Redis qui swappe est une panne et non un ralentissement,
et comment tu le détectes.

<a id="qo15-8"></a>**[QO15.8](corrige.md#qo15-8)** — Sur `lab-db`, PostgreSQL et Redis exposent chacun une socket
Unix. Explique qui peut s'y connecter et par quel mécanisme la sécurité est
assurée dans chaque cas (mode de la socket, groupe, `pg_hba`, ACL Redis), et
pourquoi les deux projets ont fait des choix différents. Décris ensuite
l'ordre de démarrage correct d'une application locale qui dépend des deux
(`After=`, `Wants=`, `Requires=`) et ce qui change quand la base est sur une
autre machine.

<a id="qo15-9"></a>**[QO15.9](corrige.md#qo15-9)** — Prépare ta fiche d'entretien : pour chacun des trois composants,
les cinq choses qu'un DevOps doit savoir dire en deux minutes (rôle, fichiers
de configuration, commande de validation, la panne classique et son
diagnostic, ce qu'on supervise). Sois concret : noms de fichiers, de
commandes, de vues, de métriques.

---

## 15.5 Exercices guidés ★

<a id="e15-1"></a>**[E15.1](corrige.md#e15-1)** — Sur `lab-web`, sans passer par nginx : affiche uniquement les
en-têtes de réponse de `http://127.0.0.1:8001/api/health`, puis le code HTTP et
le temps total (en secondes) de cinq requêtes successives sur
`/api/slow?s=1`, sans afficher les corps. Repère l'en-tête qui identifie
l'instance.

<a id="e15-2"></a>**[E15.2](corrige.md#e15-2)** — Affiche la configuration **effective** de nginx (includes
résolus), compte les blocs `server` actifs, et trouve la ligne de
`nginx.conf` qui explique pourquoi un fichier déposé dans `sites-available/`
n'est pas pris en compte tant qu'on ne fait rien d'autre.

<a id="e15-3"></a>**[E15.3](corrige.md#e15-3)** — Crée un vhost `factura-demo.lab.local` qui sert
`/srv/www/factura-demo` sur le port 80, active-le, désactive le site
`default`, valide, recharge. Prouve depuis `lab-adm` que la page d'accueil
est servie en forçant l'en-tête `Host` (sans toucher à `/etc/hosts`), puis
ajoute l'entrée dans `/etc/hosts` de `lab-adm`. Que renvoie nginx si tu
demandes un `Host` inconnu, et pourquoi ?

<a id="e15-4"></a>**[E15.4](corrige.md#e15-4)** — Ajoute au vhost trois locations : `/` (fichiers statiques avec
`try_files`), `/docs/` (servie depuis `/srv/www/factura-demo/docs/` avec
`alias`) et `/api/` (proxy vers `127.0.0.1:8001`). Ajoute dans chacune un
en-tête `X-Location` distinct, puis prouve avec `curl -sI` quel bloc sert
`/`, `/docs/`, `/docs/index.html`, `/api/health` et `/static/app.js`.
Remplace ensuite `alias` par `root` sur `/docs/` et explique le 404.

<a id="e15-5"></a>**[E15.5](corrige.md#e15-5)** — Compare `proxy_pass http://127.0.0.1:8001;` et
`proxy_pass http://127.0.0.1:8001/;` dans `location /api/` : pour chacun,
affiche ce que le backend reçoit comme chemin (`/api/whoami` te le dit) et
ses en-têtes `Host` et `X-Forwarded-For`. Ajoute ensuite les `proxy_set_header`
qui rendent `Host` et `X-Forwarded-For` corrects, et vérifie.

<a id="e15-6"></a>**[E15.6](corrige.md#e15-6)** — Déclare un `upstream` avec les deux instances, un `log_format`
qui inclut `$upstream_addr`, `$upstream_response_time` et `$request_time`, et
un `access_log` dédié au vhost. Envoie 10 requêtes sur `/api/whoami` et
compte les réponses par instance dans le journal. Arrête `mini-api@8002`,
renvoie 10 requêtes : que voit l'utilisateur, que dit `error.log` ?
Redémarre l'instance.

<a id="e15-7"></a>**[E15.7](corrige.md#e15-7)** — Mets le vhost en HTTPS : réutilise le certificat de L18.4 s'il
existe, sinon fabrique un auto-signé pour `factura-demo.lab.local` avec
`openssl req -x509` (une commande). `listen 443 ssl http2`, TLS 1.2 et 1.3
seulement, HSTS, et un second `server` sur 80 qui redirige en 301. Vérifie
avec `curl -vk` (version TLS négociée, protocole HTTP, en-tête HSTS) et avec
`openssl s_client`.

<a id="e15-8"></a>**[E15.8](corrige.md#e15-8)** — Protège trois chemins : `/api/login` limité à 5 requêtes par
minute et par IP (rafale de 5, réponse 429 au-delà), `/docs/` protégé par
un mot de passe (`htpasswd`, utilisateur `ops`), `/api/metrics` accessible
depuis `10.10.10.14` seulement. Prouve chaque règle avec `tir.sh`, `curl -u`
et un `curl` depuis `lab-adm` (attendu : 403).

<a id="e15-9"></a>**[E15.9](corrige.md#e15-9)** — Sur `lab-db`, en tant que `postgres` par la socket : liste les
bases avec leur taille, les rôles avec leurs attributs, les tables de
`factura_demo` avec leur taille, la description complète de `invoices`
(colonnes, index, contraintes). Active l'affichage étendu et le chronomètre,
puis exécute `/opt/factura/bin/requete-lente.sql` et note le temps.

<a id="e15-10"></a>**[E15.10](corrige.md#e15-10)** — Explique le plan de la requête lente avec `EXPLAIN (ANALYZE,
BUFFERS)` : repère les parcours séquentiels et les `Rows Removed by Filter`.
Crée les index qui manquent **sans verrouiller la table**, rejoue la
requête, compare les temps et les plans. Vérifie ensuite dans
`pg_stat_user_tables` que les index sont utilisés.

<a id="e15-11"></a>**[E15.11](corrige.md#e15-11)** — Lance `/opt/factura/bin/charge-sql.sh 3 120` en arrière-plan.
Liste les requêtes actives avec leur durée et leur état, annule la plus
ancienne **sans** fermer sa session. Lance ensuite
`/opt/factura/bin/verrou-demo.sh 300` dans un second terminal, puis tente
`UPDATE invoices SET status='paid' WHERE id=42;` dans un troisième : trouve
le PID qui bloque, ce qu'il fait, depuis combien de temps, et débloque.

<a id="e15-12"></a>**[E15.12](corrige.md#e15-12)** — Mesure la taille de `invoice_lines` (table seule, puis avec ses
index), supprime 20 % des lignes dans une copie de la table (`CREATE TABLE
... AS`), observe `n_dead_tup` avant et après un `VACUUM (VERBOSE)`, et note
si la taille sur disque a diminué. Explique en une ligne ce qu'il faudrait
pour qu'elle diminue.

<a id="e15-13"></a>**[E15.13](corrige.md#e15-13)** — Depuis `lab-web`, connecte-toi à `factura_demo` sur `lab-db` en
tant que `factura_app` sans taper de mot de passe, de deux façons
(variable, puis `~/.pgpass`). Mets volontairement `~/.pgpass` en `0644` et
montre le message obtenu. Quelle façon laisse une trace dans `ps` ?
(Suppose L15.3 fait ; sinon travaille sur `lab-db` en `-h 127.0.0.1`.)

<a id="e15-14"></a>**[E15.14](corrige.md#e15-14)** — Sur `lab-db`, avec `redis-cli` : vérifie que Redis répond,
affiche la version et le temps de fonctionnement, crée une session
`sess:abc` avec 60 s de durée de vie et lis le temps restant, stocke un
profil `user:1` (nom, ville) et relis-le, simule une file de travaux (pousse
trois jobs, consomme-en un en attente bloquante), lance 200 tours de
`redis-app.py`, compte les clés `sess:*` **sans `KEYS`**, puis liste les
plus grosses clés.

<a id="e15-15"></a>**[E15.15](corrige.md#e15-15)** — Déclenche une sauvegarde RDB en arrière-plan, prouve qu'elle est
terminée et à quelle heure, copie le fichier dans `~/lab15/backups/` avec un
horodatage. Active ensuite l'AOF **à chaud** et persiste le changement dans
`redis.conf` sans l'éditer à la main. Montre les fichiers créés dans
`/var/lib/redis/`.

<a id="e15-16"></a>**[E15.16](corrige.md#e15-16)** — Sur `lab-db`, affiche les unités réellement chargées pour
PostgreSQL et Redis (avec drop-ins), leur `User=`, et l'état des sockets
Unix `/run/postgresql/.s.PGSQL.5432` et `/run/redis/` (propriétaire, mode).
Dis qui peut se connecter par chaque socket et grâce à quoi. Écris ensuite
la section `[Unit]` d'une application locale qui a besoin des deux.

---

## 15.6 Labs ★★

### <a id="l15-1"></a>**[L15.1](corrige.md#l15-1)** — Ticket WEB-412 : « Mettre Factura-demo derrière nginx, proprement »

> **Contexte**
>
> L'équipe de développement livre un front statique et une API qui tourne en
> deux instances sur `127.0.0.1:8001` et `8002`. Elle demande « un nginx
> devant ». Le responsable d'exploitation ajoute : « avec des journaux
> exploitables, une page de maintenance, et sans que le premier script venu
> puisse brute-forcer le login ». Tu fais le vhost complet, sur `lab-web`.

Écris `/etc/nginx/sites-available/factura-demo` (copie de travail dans
`~/lab15/conf/`), activé, site `default` désactivé, `server_tokens off`.

1. `server_name factura-demo.lab.local`, `root /srv/www/factura-demo`,
   `index index.html`, `location /` avec `try_files` qui renvoie
   `index.html` pour toute URI inconnue (le front est une SPA).
2. `/static/` : cache navigateur 30 jours, `Cache-Control: public`, gzip
   activé pour CSS, JS, JSON et SVG (prouve-le sur `/static/gros.txt` avec
   `curl --compressed -sI`).
3. `/docs/` : servi depuis `/srv/www/factura-demo/docs/`, protégé par
   `auth_basic` (utilisateur `ops`, fichier hors de `root`).
4. `/api/` : `upstream factura_api` avec les deux instances, `keepalive`,
   HTTP/1.1 vers l'upstream, en-têtes `Host`, `X-Real-IP`,
   `X-Forwarded-For`, `X-Forwarded-Proto`, `proxy_connect_timeout 3s`,
   `proxy_read_timeout 30s`, et la location écrite de façon qu'**aucune
   regex** ajoutée plus tard ne puisse la court-circuiter.
5. `/api/login` : 5 requêtes par minute et par IP, rafale 5, réponse 429.
6. `/api/metrics` : `10.10.10.14` seulement, 403 pour les autres.
7. `/api/stream` : réponse transmise au fil de l'eau (vérifie avec
   `curl -N` que les lignes arrivent une par une).
8. `client_max_body_size 2m` ; un POST de 3 Mo sur `/api/upload` doit
   renvoyer 413, un POST de 1 Mo doit passer.
9. Journal : `log_format factura` (combined + `$request_time`,
   `$upstream_response_time`, `$upstream_addr`, `$upstream_status`),
   `access_log` et `error_log` propres au vhost, niveau `warn`.
10. Page de maintenance : `touch /srv/www/maintenance.on` fait répondre 503
    avec `/srv/www/maintenance/503.html` sur tout le site sauf `/api/health`
    (la supervision doit continuer à voir l'API) ; supprimer le fichier
    rétablit le service, **sans reload**.
11. `~/lab15/rapports/web-412.md` : la conf commentée bloc par bloc et le
    résultat des dix vérifications (`curl` + code attendu / obtenu).

> [!TIP]
> **Astuce**
>
> Construis par étapes : `nginx -t` puis `systemctl reload nginx` après
> **chaque** location. Une erreur de conf ne coupe rien (Q15.4), mais une
> location qui n'a pas l'effet attendu se voit tout de suite avec un
> `add_header X-Loc "api"` temporaire.

> [!TIP]
> **Critère de succès**
>
> Critère de succès : la page d'accueil répond 200, `/api/health` alterne entre
> les deux instances, `/docs/` répond 401 sans mot de passe, `/api/metrics` 403
> depuis `lab-adm`, un POST de 3 Mo répond 413, 12 requêtes rapides sur
> `/api/login` produisent des 429, et le fichier de maintenance bascule le site
> en 503.
>
> ```bash
> bash check_M15_01.sh
> ```

---

### <a id="l15-2"></a>**[L15.2](corrige.md#l15-2)** — HTTPS et exercice de diagnostic : six pannes, six preuves

> **Contexte**
>
> Le site passe en HTTPS. Avant la mise en production, ton responsable veut que
> tu **provoques** toi-même chaque panne classique du frontal et que tu
> consignes, pour chacune, le symptôme exact, la ligne de journal et le
> correctif — pour le runbook. Sur `lab-web`, en partant du vhost de L15.1.

Partie 1 — TLS :

1. Certificat : celui de L18.4 (module 18) s'il existe, sinon un certificat
   auto-signé pour `factura-demo.lab.local` avec SAN, dans
   `/etc/nginx/ssl/` (clé en `0600`, propriétaire `root`).
2. `server` 443 : `ssl http2`, `TLSv1.2 TLSv1.3`, `ssl_session_cache`,
   `ssl_session_tickets off`, HSTS six mois, `X-Content-Type-Options`,
   `X-Frame-Options` — **sur toutes les locations**, y compris `/api/`
   (relis Q15.7).
3. `server` 80 : redirection 301 vers HTTPS, sauf `/.well-known/acme-challenge/`
   qui reste servi en clair (pour un futur certbot, module 18).
4. Preuves : `curl -vk` (protocole négocié `h2`, TLS 1.3), `openssl s_client`
   (certificat présenté), et `curl -sI http://...` (301 + `Location`).

Partie 2 — provoque, observe, corrige. Pour chaque cas, note dans
`~/lab15/rapports/codes-http.md` : commande, code HTTP, ligne d'`error.log`,
cause, correctif.

5. **502** : arrête les deux instances `mini-api@`. Puis relance-les.
6. **502 variante** : change un port de l'upstream en 8003, recharge,
   observe ; note ce que fait nginx quand **un seul** des deux backends est
   mort (pas de 502 ! pourquoi ?). Remets le bon port.
7. **504** : `proxy_read_timeout 5s` puis `GET /api/slow?s=10`. Remets 30 s.
8. **413** : POST de 3 Mo sur `/api/upload`.
9. **403** : `chmod 700 /srv/www/factura-demo/docs` puis `GET /docs/` avec
   le bon mot de passe. Remets `755`. Deuxième 403 : retire `index` et
   demande `/docs/` — quelle ligne dans `error.log` ?
10. **Boucle 301** : déplace le `return 301` dans le `server` 443 « par
    erreur » ; observe avec `curl -sIL --max-redirs 3`. Remets en ordre.
11. **404 sur l'API** : ajoute `location ~* \.(json|js|css)$ { expires 7d; }`
    au vhost et demande `/api/invoices.json`. Explique pourquoi ta location
    `/api/` de L15.1 résiste (ou pas) et corrige si besoin.

> [!TIP]
> **Critère de succès**
>
> Critère de succès : `curl -sI https://factura-demo.lab.local/` depuis
> `lab-adm` (avec `--cacert` ou `-k`) renvoie 200 avec HSTS, `http://` renvoie
> 301, `/api/health` en HTTPS porte aussi HSTS, et le rapport contient les six
> cas avec une ligne d'`error.log` chacun.
>
> ```bash
> bash check_M15_02.sh
> ```

---

### <a id="l15-3"></a>**[L15.3](corrige.md#l15-3)** — Ouvrir la base à `lab-web`, et seulement à lui

> **Contexte**
>
> `factura_demo` n'est joignable que par la socket locale de `lab-db`. L'API de
> `lab-web` doit s'y connecter avec le rôle `factura_app`, un outil de
> reporting en lecture seule avec `factura_ro`. Le RSSI a un mot : « rien en
> `trust`, rien en `md5`, rien en `0.0.0.0` ». Et le responsable d'exploitation
> veut que la base soit **réglée** pour une VM de 2 Go, pas laissée aux valeurs
> d'usine, avec les requêtes lentes journalisées.

Sur `lab-db` :

1. `pg_lsclusters`, `systemctl status postgresql@16-main`, `SHOW
   data_directory;`, `SHOW config_file;`, `SHOW hba_file;` : note les
   chemins. Vérifie avec `ss -tlnp` sur quoi PostgreSQL écoute.
2. Crée `/etc/postgresql/16/main/conf.d/10-factura.conf` avec les douze
   paramètres du rappel express, adaptés à 2 Go de RAM et 2 vCPU, dont
   `log_min_duration_statement = 500`, `log_lock_waits = on`,
   `log_line_prefix` avec horodatage, PID, rôle et base, `timezone =
   'Europe/Paris'`, et `shared_preload_libraries = 'pg_stat_statements'`.
   Avant de redémarrer, liste avec `pg_settings` ceux qui exigent un restart.
3. `pg_hba.conf` : `factura_app` et `factura_ro` vers `factura_demo` depuis
   `10.10.10.11/32` uniquement, en `scram-sha-256`. Aucune ligne `trust`,
   `md5`, ni réseau plus large. Recharge et lis `pg_hba_file_rules`.
4. Redémarre, vérifie l'écoute sur `10.10.10.12:5432`, `SHOW` des
   paramètres modifiés, et `CREATE EXTENSION pg_stat_statements;` dans
   `factura_demo`.
5. Pare-feu : si `ufw` est actif (module 18), n'ouvre 5432 que depuis
   `10.10.10.11`. Sinon, note dans le rapport que `listen_addresses` seul ne
   protège rien.

Sur `lab-web` :

6. Connexion `factura_app` avec `~/.pgpass` : `SELECT count(*) FROM
   invoices;`. Connexion `factura_ro` : un `SELECT` passe, un `UPDATE` est
   refusé (quel message ?). Connexion depuis `lab-adm` : refusée — note le
   message exact et **à quelle étape** (TCP, `pg_hba`, mot de passe).
7. Rejoue dix fois la requête lente depuis `lab-web`, puis sur `lab-db` :
   retrouve-la dans `/var/log/postgresql/postgresql-16-main.log` et dans
   `pg_stat_statements` (top 5 par temps total).
8. Livrable : `~/lab15/conf/lab-db/10-factura.conf`, `pg_hba.conf`, et
   `~/lab15/rapports/pg-ouverture.md` (paramètres choisis et pourquoi, les
   trois messages d'erreur observés, la commande `ss` finale).

> [!CAUTION]
> **Attention**
>
> `listen_addresses = '*'` avec `pg_hba.conf` restrictif est **acceptable**,
> mais `listen_addresses = '*'` avec `host all all 0.0.0.0/0 md5` et pas de
> pare-feu est la configuration la plus scannée d'Internet. Ne l'écris jamais,
> même « pour tester ».

> [!TIP]
> **Critère de succès**
>
> Critère de succès : PostgreSQL écoute sur `10.10.10.12:5432` et pas sur
> `0.0.0.0`, `pg_hba` ne contient ni `trust` ni `md5`, `factura_app` se
> connecte depuis `lab-web`, `pg_stat_statements` est chargé,
> `log_min_duration_statement` vaut 500 ms, et le rapport existe.
>
> ```bash
> bash check_M15_03.sh
> ```

---

### <a id="l15-4"></a>**[L15.4](corrige.md#l15-4)** — Sauvegarde nocturne restaurée, puis retour dans le temps (PITR)

> **Contexte**
>
> « On a une sauvegarde » n'est pas une phrase acceptable. On te demande une
> sauvegarde logique par nuit, vérifiée par une restauration réelle, puis —
> parce qu'une facture supprimée à 10 h 15 ne se retrouve pas dans le dump de
> 2 h 30 — une sauvegarde physique avec archivage des WAL, et la preuve que tu
> sais revenir à 10 h 14. Sur `lab-db`. C'est la mécanique que tu remettras en
> place au projet P1 (Factura).

Partie 1 — logique :

1. Script `/usr/local/sbin/pg-sauvegarde.sh` (`set -euo pipefail`), exécuté
   par `postgres` en `peer` (donc sans mot de passe ni `.pgpass`) :
   `pg_dumpall --globals-only`, puis un `pg_dump -Fc` par base non
   template, dans `/var/backups/postgresql/<AAAAMMJJ-HHMM>/`, les sommes SHA-256 ( un `.sha256`
   par fichier ou un `SHA256SUMS`), suppression des répertoires de plus de 7 jours, une ligne de
   journal par étape, sortie non nulle en cas d'échec.
2. `pg-sauvegarde.service` (`Type=oneshot`, `User=postgres`) et
   `pg-sauvegarde.timer` à 02:30 avec `Persistent=yes` (module 17). Lance le
   service à la main, contrôle `systemctl list-timers`.
3. Restauration testée : `pg_restore` du dernier dump dans une base
   `factura_restore` (`--no-owner`, `-j 2`), `SELECT count(*)` identique sur
   les trois tables, **temps mesuré**. Écris la procédure dans
   `~/lab15/rapports/restauration.md`.

Partie 2 — physique et PITR :

4. Crée `/srv/pg-archive/{base,wal}` (propriétaire `postgres`). Active
   `archive_mode = on` et un `archive_command` qui **refuse d'écraser** un
   segment existant. Redémarre. Force un segment avec `SELECT
   pg_switch_wal();` et vérifie l'arrivée du fichier et
   `pg_stat_archiver`.
5. `pg_basebackup` en format tar compressé, WAL inclus, avec barre de
   progression, dans `/srv/pg-archive/base/`.
6. Insère une facture témoin `F-PITR-0001`, note l'heure exacte
   (`SELECT now();`), attends 30 s, puis simule la catastrophe : `DELETE
   FROM invoice_lines; DELETE FROM invoices;` puis `pg_switch_wal()`.
7. Restaure **dans un second cluster** (`pg_createcluster 16 pitr -p 5433`
   puis remplace son `PGDATA` par la base tar, ou arrête `main` et travaille
   dedans après un snapshot) : `restore_command`, `recovery_target_time` =
   l'heure notée + 10 s, `recovery_target_action = 'promote'`, fichier
   `recovery.signal`. Démarre, suis le journal jusqu'à « recovery stopping
   before commit of transaction... » puis « database system is ready ».
8. Preuve : `F-PITR-0001` est présente, les 100 000 factures aussi. Consigne
   le temps total et le RPO obtenu dans `restauration.md`.

Partie 3 (facultative) — réplication streaming vers `lab-ops` :

9. Sur `lab-db` : rôle `repl` avec `REPLICATION`, ligne `host replication
   repl 10.10.10.14/32 scram-sha-256`, `max_wal_senders`. Sur `lab-ops` :
   `apt install postgresql-16`, arrêt du cluster, `PGDATA` vidé,
   `pg_basebackup -h 10.10.10.12 -U repl -D /var/lib/postgresql/16/main -R
   -P -X stream`, démarrage. Vérifie `pg_stat_replication` côté primaire et
   `pg_is_in_recovery()` côté secondaire, insère une ligne d'un côté,
   lis-la de l'autre.

> [!CAUTION]
> **Attention**
>
> Partie 2 étape 7 : si tu choisis de restaurer **dans** le cluster `main`, tu
> détruis les données courantes. Prends `qm snapshot 9003 avant-pitr`. La
> variante « second cluster sur 5433 » est plus longue mais c'est celle qu'on
> fait en production.

> [!TIP]
> **Critère de succès**
>
> Critère de succès : le timer est actif, un répertoire de sauvegarde du jour
> contient `globals.sql`, `factura_demo.dump` et leurs sommes SHA-256 valides,
> `factura_restore` a autant de factures que `factura_demo`, `archive_mode` est
> `on` avec au moins un segment archivé et `pg_stat_archiver.failed_count = 0`,
> et `restauration.md` contient un temps mesuré.
>
> ```bash
> bash check_M15_04.sh
> ```

---

### <a id="l15-5"></a>**[L15.5](corrige.md#l15-5)** — Redis : sécuriser, dimensionner, observer

> **Contexte**
>
> Redis a été installé « par défaut » sur `lab-db`. Un audit rapide : pas de
> mot de passe, `maxmemory` à zéro (illimité), aucune persistance journalisée,
> et l'application de `lab-web` ne peut même pas s'y connecter. On te demande
> une configuration de production **justifiée**, puis une session
> d'observation sous charge.

1. État des lieux : `redis-cli INFO server`, `CONFIG GET bind`,
   `CONFIG GET maxmemory*`, `CONFIG GET appendonly`, `ss -tlnp`. Note tout
   dans `~/lab15/rapports/redis.md`.
2. `redis.conf` (garde un `diff -u` contre l'original dans
   `~/lab15/conf/lab-db/redis.conf.diff`) : `bind 127.0.0.1 10.10.10.12`,
   `protected-mode yes`, un utilisateur ACL `factura` limité aux clés
   `sess:*`, `user:*`, `factura:*` et sans commandes dangereuses,
   utilisateur `default` désactivé, `maxmemory 128mb`, politique choisie
   pour un usage **mixte sessions + file** (justifie), `appendonly yes`
   avec `appendfsync everysec`, `save` conservé. Redémarre, vérifie que
   `PING` sans auth est refusé et que `KEYS`/`FLUSHALL` sont interdits à
   `factura` même authentifié.
3. Pare-feu (si actif) : 6379 depuis `10.10.10.11` seulement.
4. Depuis `lab-web` : `redis-cli -h 10.10.10.12 --user factura --pass ...
   PING`, puis `redis-app.py --url redis://factura:...@10.10.10.12:6379/0
   --loop` pendant deux minutes.
5. Pendant la charge, sur `lab-db` : `redis-cli --stat` (30 s), `INFO
   memory` (`used_memory` vs RSS, ratio), `INFO stats` (`evicted_keys`,
   `expired_keys`, `keyspace_hits`), `INFO clients`, `SLOWLOG GET 5`,
   `--latency` pendant 10 s, `CLIENT LIST`. Consigne chaque valeur et ce
   qu'elle veut dire.
6. Abaisse temporairement `maxmemory` à `2mb` avec `CONFIG SET` pendant que
   l'application tourne : observe `evicted_keys`, la file `LLEN
   factura:jobs`, et ce que l'application affiche. Remets 128 Mo. Explique
   ce qui se serait passé en `noeviction`.
7. Sauvegarde : `BGSAVE`, attends la fin (`INFO persistence`), copie
   `dump.rdb` horodaté dans `/var/backups/redis/`. Note pourquoi copier
   `dump.rdb` pendant un `BGSAVE` en cours est sans danger, et pourquoi
   l'AOF n'a pas le même mode de sauvegarde.
8. `~/lab15/rapports/redis.md` : la configuration justifiée ligne par ligne,
   les mesures, et trois seuils d'alerte que tu proposerais au module 26.

> [!TIP]
> **Critère de succès**
>
> Critère de succès : Redis écoute sur `10.10.10.12` et `127.0.0.1`, `PING`
> sans authentification est refusé, l'utilisateur `factura` existe avec des
> restrictions, `maxmemory` vaut 128 Mo avec une politique différente de
> `noeviction`, l'AOF est activé, une copie de `dump.rdb` existe et le rapport
> est rédigé.
>
> ```bash
> bash check_M15_05.sh
> ```

---

## 15.7 Break & Fix ★★★

> [!CAUTION]
> **Attention**
>
> Avant chaque Break & Fix : `qm snapshot 9002 avant-bf15` (BF15.1, BF15.2) ou
> `qm snapshot 9003 avant-bf15` (BF15.3 à BF15.6). Les scripts sauvegardent ce
> qu'ils cassent dans `/root/.breakfix-backup/`, mais le snapshot reste la
> sortie de secours — et l'utiliser vaut échec de l'exercice.

### <a id="bf15-1"></a>**[BF15.1](corrige.md#bf15-1)** — « La page charge mais dit ERREUR, et l'API répond pourtant »

```bash
# sur lab-web, après L15.1
sudo bash break_M15_01.sh
```

**Symptôme utilisateur** : `https://factura-demo.lab.local/` s'affiche, mais
la ligne « Chargement… » devient « ERREUR : HTTP 404 sur
/api/invoices.json ». La supervision est verte : `/api/health` répond 200,
les deux instances tournent, `nginx -t` est bon. Un collègue a « juste ajouté
du cache sur les fichiers statiques » ce matin.

**Interdit** : redémarrer les instances, supprimer le cache ajouté (le
collègue y tient), modifier l'application.

**Objectif** : trouver quel bloc sert réellement `/api/invoices.json` (une
commande `curl` et une ligne d'`error.log` suffisent), rétablir l'API sans
retirer la fonctionnalité du collègue, et expliquer la règle de priorité qui
a joué.

### <a id="bf15-2"></a>**[BF15.2](corrige.md#bf15-2)** — « 502 sur tout /api/, le statique marche »

```bash
# sur lab-web, après L15.1
sudo bash break_M15_02.sh
```

**Symptôme utilisateur** : toutes les URI `/api/...` renvoient
`502 Bad Gateway`. Le site statique est normal. `systemctl status
mini-api@8001 mini-api@8002` : `active (running)`. Le collègue de
l'infogérance dit avoir « harmonisé les ports avec la nouvelle norme ».

**Interdit** : redémarrer nginx (un `reload` est autorisé), changer les
ports de l'application.

**Objectif** : identifier en moins de trois commandes où nginx essaie de se
connecter et pourquoi ça échoue, corriger, et proposer une vérification qui
aurait empêché la mise en production de ce changement.

### <a id="bf15-3"></a>**[BF15.3](corrige.md#bf15-3)** — « L'application ne se connecte plus à la base depuis la migration »

```bash
# sur lab-db, après L15.3
sudo bash break_M15_03.sh
```

**Symptôme utilisateur** : depuis `lab-web`, `psql -h 10.10.10.12 -U
factura_app -d factura_demo` échoue. Le mot de passe dans
`/etc/factura/db.env` est le bon, personne ne l'a changé. PostgreSQL est
`active`, écoute sur `10.10.10.12:5432`, et `sudo -u postgres psql -d
factura_demo` fonctionne. Un prestataire a « préparé la migration de la
base » hier soir : il devait renommer des choses et « moderniser
l'authentification ».

**Interdit** : `trust`, réinitialiser le mot de passe à une autre valeur,
redémarrer PostgreSQL.

**Objectif** : il y a **deux** causes superposées. Trouve la première avec
le message d'erreur côté client et `pg_hba_file_rules`, corrige, retrouve la
seconde dans le journal du serveur (`DETAIL:`) et dans `pg_authid`, corrige
avec le **même** mot de passe, et explique pourquoi la seconde ne se voit pas
tant que la première n'est pas réglée.

### <a id="bf15-4"></a>**[BF15.4](corrige.md#bf15-4)** — « Plus aucune connexion possible, mais la base ne fait rien »

```bash
# sur lab-db, après L15.3
sudo bash break_M15_04.sh
```

**Symptôme utilisateur** : l'API renvoie des 503 ; son journal contient
`FATAL: remaining connection slots are reserved for roles with the SUPERUSER
attribute`. Sur `lab-db`, la charge est nulle, le disque est libre. Un
collègue a « optimisé la mémoire » de PostgreSQL la semaine dernière.

**Interdit** : **redémarrer PostgreSQL** (une session de clôture comptable
est en cours et ne doit pas être coupée), toucher à l'application.

**Objectif** : rendre la base joignable immédiatement sans redémarrage,
identifier qui occupe les connexions et depuis combien de temps, trouver la
modification du collègue et dire ce qu'elle a changé, puis proposer deux
mesures durables (une côté base, une côté architecture).

### <a id="bf15-5"></a>**[BF15.5](corrige.md#bf15-5)** — « L'application plante en écriture Redis, mais Redis répond »

```bash
# sur lab-db, après L15.5
sudo bash break_M15_05.sh
```

**Symptôme utilisateur** : `redis-app.py` (depuis `lab-web` ou `lab-db`)
s'arrête au bout de quelques tours avec `ECRITURE REFUSEE`. `redis-cli PING`
répond `PONG`, `INFO clients` est normal, le service est `active`. Il y a eu
« un réglage mémoire » après une alerte de la supervision.

**Interdit** : `FLUSHALL`, redémarrer Redis (les sessions des utilisateurs
seraient perdues... vérifie d'ailleurs si c'est vrai).

**Objectif** : lire le message d'erreur complet, trouver les deux valeurs de
configuration en cause et la raison pour laquelle leur combinaison bloque
l'application, corriger **à chaud** et durablement, et dire quelle politique
tu aurais choisie pour cette application.

### <a id="bf15-6"></a>**[BF15.6](corrige.md#bf15-6)** — « Les exports de nuit font 0 octet »

```bash
# sur lab-db, après L15.3
sudo bash break_M15_06.sh
```

**Symptôme utilisateur** : un collègue a mis en place un export SQL
périodique dans `/var/backups/factura-offsite/`. Les fichiers sont créés
avec le bon nom et la bonne heure, mais ils sont **vides**. Lancé à la main
par ce collègue « ça marche ». Aucune alerte, aucun mail, `cron` dit que la
tâche a tourné.

**Interdit** : passer par `postgres`/`peer` (le collègue veut garder son
compte dédié), mettre le mot de passe dans la ligne cron.

**Objectif** : reproduire l'échec exactement comme cron l'exécute, trouver
les deux erreurs (une de droits, une de conception du script), corriger,
et faire en sorte qu'un fichier vide ne puisse plus jamais passer inaperçu.

---

## 15.8 Défi du module ★★★

<a id="d15"></a>**[D15](corrige.md#d15) — Le dossier d'exploitation des trois briques**

> **Contexte**
>
> Tu pars en congés dans trois jours. Le collègue qui te remplace n'a jamais
> touché ni nginx, ni PostgreSQL, ni Redis. Tu lui laisses un dossier complet :
> les configurations, un script qui dit en trente secondes si tout va bien, et
> un runbook qui répond aux questions de 3 h du matin. C'est aussi ce que tu
> présenteras en entretien.

Cahier des charges :

1. **Configurations versionnées** dans `~/lab15/conf/` (sur `lab-adm`, avec
   un sous-dossier par hôte) : le vhost nginx final de L15.1/L15.2, le
   `conf.d/10-factura.conf` et le `pg_hba.conf` de L15.3, le script et le
   timer de L15.4, le `redis.conf.diff` de L15.5. Chaque fichier commence par
   un commentaire de trois lignes : rôle, hôte, date.
2. **Le script de conformité** `~/lab15/bin/verif-services.sh`, en bash,
   `#!/usr/bin/env bash`, `set -euo pipefail`, exécutable sur `lab-adm`
   (il interroge les autres VM en SSH, module 14). Une ligne `[ OK ]` /
   `[FAIL]` par point, sortie 0 si tout passe :
   * nginx : `nginx -t` propre, `/` répond 200 en HTTPS avec HSTS, `/api/health`
     répond 200, les **deux** instances ont servi au moins une requête dans
     les 5 dernières minutes (lu dans `factura.access.log`), le certificat
     expire dans plus de 30 jours, `server_tokens off` ;
   * PostgreSQL : joignable depuis `lab-web` en `factura_app`, aucune ligne
     `trust`/`md5` dans `pg_hba`, `max_connections` utilisé à moins de 80 %,
     aucune session `idle in transaction` de plus de 5 minutes, dernière
     sauvegarde de moins de 26 h avec `.sha256` valide, `pg_stat_archiver.
     failed_count = 0`, plus de 20 % d'espace libre sur `PGDATA` ;
   * Redis : `PING` sans mot de passe refusé, `maxmemory` non nul, politique
     différente de `noeviction`, `mem_fragmentation_ratio` entre 1 et 1,5,
     `rdb_last_bgsave_status:ok`, `aof_last_write_status:ok`, aucun swap sur
     la machine.
3. **Le runbook** `~/lab15/rapports/runbook-services.md`, au minimum :
   * pour chaque brique : fichiers de conf, commande de validation,
     commande de rechargement **sans coupure**, journal à lire, compte de
     service ;
   * ordre de démarrage / arrêt des trois briques et pourquoi ;
   * six fiches incident (502, 504, `no pg_hba.conf entry`, `too many
     connections`, `OOM command not allowed`, sauvegarde vide) : symptôme,
     trois commandes, cause usuelle, correctif ;
   * la procédure de restauration (logique et PITR) copiée de L15.4 avec les
     temps mesurés ;
   * la procédure de rotation du mot de passe `factura_app` et de
     l'utilisateur ACL Redis sans interruption de service.
4. **La fiche entretien** `~/lab15/rapports/entretien.md` : pour chaque
   brique, dix lignes maximum, ce que tu dis quand on te demande « tu
   connais nginx / PostgreSQL / Redis ? ». Concret, sans adjectif.
5. **La preuve** : la sortie de `verif-services.sh` collée en fin de runbook,
   toute verte.

Temps visé : 60 à 90 minutes.

> [!TIP]
> **Critère de succès**
>
> ```bash
> bash check_M15_06.sh
> ```

---

## 15.9 Auto-évaluation

| Compétence | Acquis | À revoir |
|---|---|---|
| Lire un échange HTTP avec `curl -v` et nommer les en-têtes du reverse proxy | ☐ | ☐ |
| Énoncer l'ordre de priorité des `location` et le prouver | ☐ | ☐ |
| Distinguer `root`/`alias` et `proxy_pass` avec/sans URI | ☐ | ☐ |
| Écrire un upstream, un log_format avec temps, une limitation, une auth | ☐ | ☐ |
| Configurer TLS dans nginx (protocoles, HSTS, redirection, HTTP/2) | ☐ | ☐ |
| Diagnostiquer 502/504/413/403/boucle 301 depuis `error.log` | ☐ | ☐ |
| Installer PostgreSQL 16, régler les douze paramètres, savoir lesquels exigent un restart | ☐ | ☐ |
| Écrire un `pg_hba.conf` minimal et lire ses trois messages d'erreur | ☐ | ☐ |
| Créer un rôle applicatif, un rôle lecture seule, utiliser `psql` sans mot de passe | ☐ | ☐ |
| Sauvegarder avec `pg_dump`, restaurer et prouver ; expliquer PITR | ☐ | ☐ |
| Trouver une requête lente, un bloqueur, une table gonflée | ☐ | ☐ |
| Configurer Redis (bind, ACL, `maxmemory`, politique, AOF) et lire `INFO` | ☐ | ☐ |
| Dire qui exécute chaque service, quelle socket, quel ordre de démarrage | ☐ | ☐ |

Pour aller plus loin :

* Lis la page « How nginx processes a request » et « Understanding the
  location directive » de la documentation nginx : deux pages, tout le
  module 15-A tient dedans.
* Installe `pgbouncer` devant `factura_demo` en mode `transaction` et
  rejoue BF15.4 : mesure combien de connexions serveur suffisent à 100
  clients.
* Lis `redis.conf` d'origine en entier (il est commenté ligne par ligne) et
  note chaque directive dont tu ne peux pas expliquer l'effet ; puis
  `LATENCY DOCTOR` et `MEMORY DOCTOR` sur ton instance.

<!-- nav:début -->
---

[← Module 14](../14-ssh/README.md) · [Corrigé](corrige.md) · [Module 16 →](../16-logs-monitoring/README.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
