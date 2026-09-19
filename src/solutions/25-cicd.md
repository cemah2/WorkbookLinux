# Module 25 — Corrigé

## 25.3 Quiz — QCM

**Q25.1** — *Déploiement en prod dès que le pipeline est vert, sans humain :
livraison continue ?*

**Réponse : c)** déploiement continu, qui inclut la livraison continue.

::: pourquoi
La frontière entre les trois pratiques est la position de la **dernière
décision humaine**. En CI, l'automate s'arrête après build et tests : il
produit un verdict, pas un livrable. En livraison continue, il produit un
artefact déployable, validé, prêt — et **quelqu'un** appuie sur le bouton
pour la production. En déploiement continu, le bouton n'existe plus : le
pipeline est la seule autorité, et chaque commit vert arrive en prod.
Le déploiement continu suppose donc la livraison continue (il faut un
artefact validé) plus une confiance mesurée dans les tests, le smoke test
et le rollback automatique.
:::

::: piege
Le manager n'a pas tort sur la technique, il a tort sur la gouvernance :
« livraison continue » laisse entendre qu'un humain décide, ce qui n'est pas
le cas ici. En entretien, la confusion entre les deux CD est la question
piège la plus fréquente sur le sujet.
:::

---

**Q25.2** — *Aucun run après push ; `runs-on` mal indenté.*

**Réponse : b)**

::: pourquoi
`jobs.test` est un mapping dont les clés (`runs-on`, `steps`) doivent être
indentées **sous** `test`. Ici `runs-on` est au niveau de `test`, donc YAML
lit `test:` comme une valeur nulle et `runs-on:` comme un second job… puis
`steps` indenté de quatre espaces sous une clé scalaire déclenche
`mapping values are not allowed here`. Le fichier n'est pas du YAML valide.
Gitea ne crée pas de run pour un workflow qu'il ne peut pas parser : il
journalise un avertissement (`Gitea → Administration → Journaux`, ou
`docker compose logs gitea`) et l'onglet *Actions* reste vide. Rien à voir
avec `branches: [ main ]`, forme parfaitement valide, ni avec
`workflow_dispatch`, qui ne concerne que le déclenchement manuel.
:::

::: piege
`python3 -c 'import yaml,sys; yaml.safe_load(sys.stdin)' < ci.yaml` ou
`yamllint ci.yaml` avant de commiter : dix secondes qui évitent une heure.
BF25.1 exploite exactement ce mécanisme.
:::

---

**Q25.3** — *Job `runs-on: ubuntu-22.04` en `waiting` alors que le runner
travaille.*

**Réponse : a)**

::: pourquoi
Un job n'est pas « envoyé » à un runner : chaque runner **interroge** Gitea
(`fetch_interval`) en présentant ses labels, et Gitea lui remet un job dont
`runs-on` figure dans ces labels. Un job dont aucun runner ne porte le label
n'est proposé à personne ; il reste `waiting` sans message d'erreur, parce
que du point de vue de Gitea la situation n'est pas anormale — un runner
avec ce label pourrait apparaître plus tard. Le runner, lui, ne voit même
pas ce job : ses logs restent silencieux.
:::

::: piege
Il n'y a ni approbation ni verrou de cache dans Gitea Actions qui bloquent un
job de cette façon. Devant un `waiting` qui dure, la première commande est
la comparaison entre `runs-on` et *Administration → Actions → Runners*.
:::

---

**Q25.4** — *Différence entre un label `docker://` et un label `host`.*

**Réponses : b) et c)**

::: pourquoi
Avec le schéma `docker://image`, act_runner crée un conteneur neuf à partir
de l'image pour chaque job, y copie le dépôt, exécute les steps, puis détruit
le conteneur : chaque job repart de zéro, ce qu'un job installe disparaît.
Avec `host`, les steps tournent dans un shell du processus runner :
même utilisateur, même `$HOME`, mêmes outils, et tout ce qu'un job laisse
(paquets, fichiers, `~/.docker/config.json`, une clé SSH oubliée) est visible
par les jobs suivants — y compris ceux d'autres dépôts. `host` n'est pas
« privilégié » au sens Docker (a est faux) et `docker://` n'interdit pas
l'accès à Docker : cela dépend de `container.docker_host` (d est faux).
:::

---

**Q25.5** — *Quels steps exposent le secret malgré le masquage ?*

**Réponses : b) et c)**

::: pourquoi
Le masquage est une substitution textuelle : le runner connaît la valeur
exacte du secret et remplace chaque occurrence **de cette chaîne** par
`***` dans le flux de sortie. Tout ce qui n'est pas cette chaîne exacte
passe :

* b) `set -x` trace la commande développée ; le secret y apparaît sous forme
  `base64` dans l'en-tête `Authorization: Basic …`, chaîne différente de
  l'original, donc non masquée. Décodable en une commande.
* c) `curl -v` affiche les en-têtes envoyés, dont `Authorization: Basic`
  calculé par curl à partir de `-u` : même mécanisme, même fuite.
* a) le secret est dans une variable, jamais imprimé : rien ne sort.
* d) `${#REG_PASS}` n'imprime que la longueur — une information, pas un
  secret.
:::

::: piege
Le masquage protège contre l'erreur d'inattention, pas contre la
transformation. Les fuites réelles sont presque toujours des encodages
(base64, URL, JSON) ou des traces de débogage laissées dans le workflow.
:::

---

**Q25.6** — *`build` échoue ; `deploy` a `needs: build` et un step
`if: failure()`.*

**Réponse : b)**

::: pourquoi
`needs` crée une dépendance : si `build` échoue, `deploy` n'est pas
**exécuté** mais **sauté** (état `skipped`), et aucun de ses steps ne
tourne — donc pas le rollback non plus. `failure()` est évalué au niveau
des steps d'un job **en cours** : il vaut vrai si un step précédent de ce
job a échoué. Pour qu'un job dépendant tourne malgré un échec en amont,
il faut une condition au niveau du job : `if: always()` ou
`if: failure()` (au niveau `jobs.deploy.if`), et lire alors
`needs.build.result` (`success`, `failure`, `cancelled`, `skipped`).
:::

---

**Q25.7** — *Prod vieille de trois jours, pipeline vert, déploiement par
`latest`.*

**Réponse : b)**

::: pourquoi
Un tag d'image est un nom qui pointe sur un digest ; n'importe qui ayant le
droit d'écrire sur le registre peut le déplacer. Si un poste de dev, un
autre pipeline ou un script de « hotfix » pousse `latest`, le prochain
`docker compose pull` sur `lab-web` récupère ce contenu-là, et `up -d`
redémarre le conteneur avec — le pipeline, lui, a bien construit et poussé
sa propre image, il est vert de bonne foi. Le tag SHA, immuable par
construction (un commit = un SHA), est la seule identité fiable ; c'est
ce que vérifie un smoke test sur `/version`.
:::

::: piege
`docker compose up -d` recrée bien un conteneur dont l'image a changé
(a faux) ; le registre ne cache rien (c faux). BF25.4 reproduit ce scénario.
:::

---

**Q25.8** — *Runner en `Restarting`, `connection refused` vers
`http://gitea:3000`.*

**Réponse : b)**

::: pourquoi
Le nom `gitea` n'est résolu que par le DNS interne du réseau Docker dans
lequel le conteneur `gitea` est attaché. Si le runner est sur un autre
réseau (compose séparé, `network_mode: host`, réseau par défaut), le nom
ne se résout pas ou l'adresse n'est pas joignable. Ton navigateur passe par
le port publié `10.10.10.14:3000`, ce qui n'a rien à voir. C'est aussi
pourquoi le setup enregistre le runner sur `http://10.10.10.14:3000` : les
**conteneurs de jobs** que le runner crée via le socket de l'hôte ne sont
pas dans le réseau du compose et ne connaîtraient pas `gitea` non plus.
:::

---

**Q25.9** — *Les quatre métriques DORA.*

**Réponse : b)**

::: pourquoi
Fréquence de déploiement et *lead time* mesurent le **débit** ; taux
d'échec des changements et temps de rétablissement mesurent la
**stabilité**. Les recherches DORA montrent que les équipes performantes
sont bonnes sur les quatre à la fois — le débit ne se paie pas en stabilité
quand le pipeline est bon. Les autres listes sont respectivement des
métriques de qualité de code, les *golden signals* de la supervision, et
des indicateurs de continuité d'activité.
:::

---

**Q25.10** — *Ce qu'interdit « build once, deploy many ».*

**Réponse : b)**

::: pourquoi
L'artefact testé doit être **bit pour bit** celui déployé. Reconstruire pour
la prod réintroduit tout ce qu'un build peut faire varier : versions de
dépendances non figées, image de base mise à jour, variable d'environnement
du runner, horloge. Le principe exige au contraire de déployer le même
artefact sur plusieurs environnements (a faux) et repose sur les tags Git
pour nommer les versions (d faux).
:::

---

**Q25.11** — *Cache pip à clé fixe, tests rouges après changement de
`requirements.txt`.*

**Réponse : a)**

::: pourquoi
`actions/cache` restaure le contenu associé à la clé **si elle existe**,
et ne le met à jour que si la clé est nouvelle. Avec `key: pip-cache`,
la clé existe depuis le premier run : le cache restauré est figé. `pip`
trouve ses roues en cache pour les anciens paquets, et pour le nouveau…
il devrait télécharger — sauf si le cache porte aussi sur `site-packages`
ou si le réseau est coupé. Dans tous les cas, un cache dont la clé ne
dépend pas de ce qu'il contient finit par mentir. La clé doit inclure
`hashFiles('requirements*.txt')` : contenu changé → clé changée → cache
reconstruit. `restore-keys` permet un repli partiel.
:::

---

**Q25.12** — *Après `ln -sfn`, que faire pour que nginx bascule ?*

**Réponse : b)**

::: pourquoi
nginx lit sa configuration au démarrage et au `reload` (SIGHUP) : il
résout alors les `include`, donc suit le symlink vers le nouveau fichier.
`nginx -t` valide la configuration complète avant de la charger — sur une
erreur, `reload` refuserait de toute façon et garderait l'ancienne, mais le
test donne le message. Le `reload` lance de nouveaux workers avec la
nouvelle configuration et laisse les anciens finir leurs requêtes : aucune
connexion coupée. `restart` tue les workers ; inutile et coûteux.
:::

---

**Q25.13** — *PR d'un fork qui exfiltre l'environnement.*

**Réponse : b)**

::: pourquoi
Le masquage n'empêche pas l'envoi réseau (a faux) ; le conteneur n'empêche
rien non plus, le secret est dedans (d faux). La seule protection est que
les secrets **ne soient pas fournis** au workflow d'une PR non approuvée :
GitHub n'expose pas les secrets aux PR issues de forks, Gitea demande une
approbation dans l'interface avant d'exécuter les workflows d'une PR venant
d'un fork ou d'un contributeur inconnu, GitLab
distingue les *protected variables* accessibles uniquement sur branches
protégées. Corollaire : ne jamais faire tourner un job avec secrets sur
`pull_request` si le dépôt accepte des contributions externes.
:::

---

**Q25.14** — *Approbation humaine avant `tofu apply` sur Gitea.*

**Réponses : a) et c)**

::: pourquoi
Gitea n'a pas d'`environment` avec relecteurs. L'approbation se construit
avec ce qui existe : la **protection de branche** (qui a le droit de faire
arriver un commit sur `main`) et le **déclenchement manuel**
(`workflow_dispatch`, réservé à qui peut pousser sur la branche). Dans les
deux cas, la décision est celle d'un humain identifié. `if: gitea.actor ==
'mathieu'` seul (b) est une condition d'affichage, pas une protection :
l'auteur d'un commit sur une branche non protégée peut l'enlever.
:::

---

**Q25.15** — *`Cannot connect to the Docker daemon` dans
`container: python:3.12-slim`.*

**Réponse : b)**

::: pourquoi
Deux causes distinctes donnent des messages proches. Si le binaire `docker`
est absent, le message est `docker: command not found`, pas celui-ci. Le
message « cannot connect » vient d'un client qui existe mais ne trouve pas
le socket : soit `config.yaml` a `container.docker_host: "-"` (le runner ne
monte pas le socket dans les jobs), soit le socket est monté à un autre
chemin. `python:3.12-slim` n'a pas de client Docker, donc si tu vois ce
message précis, quelqu'un a installé le client dans un step et le problème
est bien le socket. `which docker` puis `ls -l /var/run/docker.sock`
tranchent en deux commandes.
:::

---

**Q25.16** — *`2.3.7`, ajout d'un endpoint compatible + correction.*

**Réponse : b) `2.4.0`**

::: pourquoi
SemVer : le **mineur** s'incrémente pour un ajout rétro-compatible, et
remet le correctif à zéro. Un correctif seul donnerait `2.3.8` ; une rupture
de compatibilité `3.0.0`. `2.4.1` supposerait un correctif après `2.4.0`,
qui n'existe pas.
:::

---

**Q25.17** — *Pipeline de 9 min dont 6 en `apt-get install` répété.*

**Réponse : b)**

::: pourquoi
Le temps perdu est une installation identique refaite quatre fois. Le
remède est de ne la faire qu'une fois : image de runner ou `container:`
qui embarque les outils (installation à zéro seconde), ou à défaut un job
d'installation unique dont les autres dépendent (mais alors ils attendent
et perdent le parallélisme). `timeout-minutes` ne rend rien plus rapide,
`fail-fast` concerne les matrices, et `host` ne changerait le temps que si
les outils étaient déjà sur l'hôte — ce qui revient à b.
:::

---

**Q25.18** — *`concurrency` avec `cancel-in-progress: true` sur un
déploiement.*

**Réponse : b)**

::: pourquoi
`concurrency.group` sérialise : un seul run du groupe à la fois.
`cancel-in-progress` décide du sort du run **en cours** quand un nouveau
arrive : `true` l'annule (parfait pour des tests sur une PR, on ne veut
que le dernier), `false` met le nouveau en file d'attente. Annuler un
déploiement à mi-chemin laisse la cible dans un état indéfini : pour
`deploy`, toujours `false`.
:::

---

## 25.4 Quiz — questions ouvertes

**QO25.1** — *CI, livraison continue, déploiement continu : artefact final,
décideur, contre-exemple.*

**Réponse.**

* **CI** : à chaque commit, build + tests automatiques. Artefact final : un
  verdict (vert/rouge) et éventuellement un binaire de test jetable.
  Décideur de la prod : hors périmètre.
* **Livraison continue** : le pipeline produit un artefact **versionné,
  scanné, déployé au moins en recette** et prêt pour la prod. Artefact
  final : l'image `factura:<sha>` dans le registre, promue « candidate ».
  Décideur : un humain (bouton, tag, approbation).
* **Déploiement continu** : le même pipeline déploie en prod sans
  intervention. Artefact final : la prod elle-même. Décideur : le pipeline,
  via smoke test et rollback automatique.

Contre-exemple : une équipe qui édite un logiciel embarqué certifié, ou un
SaaS soumis à des fenêtres de changement contractuelles (banque, santé).
Le déploiement continu y est une erreur non pas technique mais de
gouvernance : la mise en prod est un acte engageant une responsabilité
externe, qui doit être tracé et décidé.

::: pourquoi
Le mécanisme sous-jacent est toujours le même : plus la décision humaine
est repoussée loin, plus il faut de **preuves automatiques** en amont
(tests, scan, smoke test) et de **filet** en aval (rollback, blue/green).
Passer d'un niveau au suivant n'est pas un réglage de pipeline, c'est un
investissement en tests et en observabilité.
:::

---

**QO25.2** — *Entretien : le pipeline d'une application conteneurisée, du
commit à la prod.*

**Réponse type (10 lignes).**

1. Déclenchement sur push et PR ; sur PR, tout sauf le déploiement.
2. Lint et analyse statique d'abord : c'est le moins cher et ça bloque les
   erreurs de forme (YAML, shell, Dockerfile) en moins d'une minute.
3. Tests unitaires en parallèle du lint, dans un conteneur figé, avec cache
   des dépendances ; rapport publié en artefact même en échec.
4. Build de l'image **une seule fois**, taguée par le SHA du commit, avec
   la version injectée dedans (`ARG`) pour qu'elle sache se présenter.
5. Scan de vulnérabilités de l'image ; bloquant sur les critiques corrigées.
6. Push vers le registre uniquement hors PR ; tag SemVer ajouté si le commit
   est tagué.
7. Déploiement sur la recette (ou la couleur inactive) par un canal
   restreint : clé SSH à commande forcée, ou Ansible.
8. Smoke test qui prouve **cette** version (`/version` = SHA), pas un 200.
9. Bascule ou promotion vers la prod ; rollback automatique si le smoke
   test échoue ; sérialisation des déploiements (`concurrency`).
10. Outils, à la fin seulement : yamllint/shellcheck/hadolint, pytest,
    docker build, trivy, registre OCI, SSH/Ansible, nginx pour le blue/green.

::: pourquoi
L'ordre suit le **coût croissant** et la **confiance croissante** : chaque
étape ne s'exécute que si la précédente a réussi (`needs`), et l'étape la
plus coûteuse/risquée (déployer) est la dernière. Ce qui bloque à chaque
étape est un code de retour non nul : c'est pour cela que tous les outils
cités ont un `--exit-code` ou échouent proprement.
:::

---

**QO25.3** — *Mécanisme d'une fuite de secret « masqué », trois vecteurs,
pourquoi `env:`.*

**Réponse.**

Le masquage est un filtre de sortie : le runner remplace, dans les logs, la
chaîne exacte de chaque secret par `***`. Il ne sait rien de la sémantique.

| Vecteur | Ce qui sort | Contre-mesure |
|---|---|---|
| `set -x`, `bash -x`, `PS4` | commandes développées, arguments | jamais de trace sur un step à secret ; `set +x` local |
| `curl -v`, `git clone https://u:t@…` | en-tête `Authorization`, URL | `-sS`, `.netrc` ou `credential.helper`, `--header @fichier` |
| encodage/découpage : `base64`, URL, JSON, `${P:0:4}` | une chaîne différente de l'original | ne transformer qu'en mémoire, jamais vers stdout |

Pourquoi `env:` plutôt que `${{ secrets.X }}` dans `run:` : l'expression
est substituée **avant** que le shell lise le script. Le secret devient une
partie du texte de la commande : il apparaît dans la trace `set -x`, dans
`ps`, dans un message d'erreur de syntaxe, et un secret contenant `'` ou
`$` casse ou injecte du shell. Passé par `env:`, il n'existe que comme
variable d'environnement, lue par `"$X"` sans interprétation.

::: pourquoi
Il y a un quatrième vecteur qu'on oublie : les **artefacts et caches**.
Un `.env` publié « pour déboguer » ou un `~/.docker/config.json` mis en
cache est un secret stocké sur la forge, téléchargeable par quiconque lit
le run. Règle de revue : tout `upload-artifact` liste explicitement ses
fichiers.
:::

---

**QO25.4** — *Socket Docker monté dans les jobs : pouvoir réel,
alternatives, compromis.*

**Réponse.**

Avec `/var/run/docker.sock`, un job parle au démon Docker de `lab-ops`,
qui tourne en root. Il peut donc : lancer `docker run -v /:/host --privileged`
et lire/écrire tout le disque de l'hôte, lire les secrets des autres jobs
et des autres conteneurs (`docker exec gitea cat /data/gitea/conf/app.ini`,
`docker inspect` des variables d'environnement, dont le mot de passe
PostgreSQL), détruire la forge. C'est root par construction : le démon
n'a aucune notion d'utilisateur derrière le socket.

Deux architectures sans socket :

1. **Builder sans démon dans le conteneur du job** : `buildah`, `kaniko`
   ou `buildkit` en mode *rootless* construisent l'image en espace
   utilisateur et poussent directement vers le registre. Coût : outillage
   différent de `docker build`, quelques fonctionnalités absentes, un peu
   plus lent.
2. **Runner isolé et éphémère** : une VM (ou un conteneur `docker:dind`
   dédié) par job, détruite ensuite. Le socket monté est celui d'un démon
   jetable, sans rien d'autre dedans. Coût : provisionnement, temps de
   démarrage, une image de VM à maintenir.

Compromis PME de 15 devs : un runner **dédié** au build d'images, sur une
VM à part de la forge (jamais sur `lab-ops` comme ici), socket monté mais
**sans aucun autre service** sur cet hôte, jobs de build limités aux
branches protégées, PR de forks non exécutées. Passer à kaniko/buildah le
jour où l'on ouvre le dépôt à des contributeurs externes.

::: pourquoi
La question sous-jacente est celle du **rayon d'explosion**. Un socket
monté n'est pas grave sur un hôte qui ne contient rien ; il est catastrophique
sur l'hôte de la forge, parce que la compromission d'un job donne la forge,
donc tous les secrets, donc la prod. Le lab viole cette règle sciemment
(une seule VM) : dis-le dans ton rapport.
:::

---

**QO25.5** — *Blue/green vs canary : infra, mesure, état, limites, feature
flags.*

**Réponse.**

| | Blue/green | Canary |
|---|---|---|
| Infra | 2× la capacité, un aiguillage | 1× + une petite instance, un répartiteur pondéré |
| Mesure avant d'aller plus loin | smoke test sur la couleur inactive | erreurs/latence de la fraction canari **comparées** au reste, sur un trafic réel |
| Bascule | instantanée, tout ou rien | progressive (1 % → 10 % → 50 % → 100 %) |
| Retour arrière | re-symlink + reload | retirer le canari |

État : ni l'une ni l'autre ne résout la base de données. Une migration de
schéma incompatible casse la couleur inactive ou l'ancienne version selon
le sens ; la règle est **expand/contract** (migrations rétro-compatibles,
suppression des colonnes deux versions plus tard). Sessions : stockées hors
des instances (Redis, cookie signé), sinon la bascule déconnecte.

Inapplicable : blue/green quand on ne peut pas doubler l'infra (base de
données, appliance) ; canary quand le trafic est trop faible pour qu'une
fraction soit statistiquement lisible, ou quand deux versions ne peuvent
pas coexister (protocole modifié).

Feature flags : orthogonaux. On déploie **une** version avec la fonction
désactivée (donc blue/green ou canary sans risque fonctionnel), puis on
active la fonction par configuration, pour un groupe, sans redéployer. Le
flag est le canari **fonctionnel**, la stratégie de déploiement est le
canari **technique**.

::: pourquoi
Le point que l'examinateur attend : blue/green répond à « la nouvelle
version démarre-t-elle ? », canary répond à « la nouvelle version
se comporte-t-elle bien sous trafic réel ? ». Ce sont deux questions
différentes, d'où deux stratégies qu'on combine souvent.
:::

---

**QO25.6** — *Entretien : pipeline vert, prod cassée.*

**Réponse : démarche.**

1. **Ce qui tourne** : sur `lab-web`, `docker compose ps` puis
   `docker image inspect --format '{{.Id}} {{.RepoDigests}}' <image>` et
   `curl -s localhost:8080/version`. On obtient un digest et une version.
2. **Ce qui a été construit** : sur `lab-ops`, dans le run vert, le SHA du
   commit et le tag poussé ; sur le registre,
   `curl -sI -H 'Accept: application/vnd.oci.image.manifest.v1+json'
   http://10.10.10.14:5000/v2/factura/manifests/<tag>` →
   `Docker-Content-Digest`. Comparer avec l'étape 1.
3. **Ce qui a été demandé** : `cat /srv/factura/.env` sur `lab-web`, le
   journal du step `deploy`, `journalctl -u ssh` pour voir la commande reçue.
4. Si les digests diffèrent : mauvais tag, `latest`, ou déploiement non
   effectué (échec silencieux, `|| true`). Si les digests sont identiques :
   la différence est dans l'**environnement**, pas dans l'image.
5. Environnement : `docker compose config` sur `lab-web` vs ce que les tests
   ont vu ; variables absentes, volume monté, port, version de base de
   données, secret expiré, réseau (`insecure-registries`, DNS).
6. Les tests : que testent-ils réellement ? Un smoke test qui vérifie un 200
   sur `/` ne prouve rien sur `/factures`.

Trois causes à 90 % : (1) image déployée ≠ image testée (`latest`, rebuild,
mauvais tag) ; (2) configuration d'exécution différente (variable, secret,
fichier monté) ; (3) le pipeline ne teste pas ce qui a cassé (couverture,
smoke test trop faible, dépendance externe absente en CI).

::: pourquoi
La méthode est une **comparaison de trois identités** : ce qui a été
testé, ce qui a été livré, ce qui tourne. Si l'une des trois manque
(pas de SHA dans l'image, pas de digest dans le run), le diagnostic devient
de la spéculation. C'est l'argument décisif pour `APP_VERSION` injecté au
build et `/version` exposé.
:::

---

**QO25.7** — *Build once, deploy many ; promotion ; tag de version seul
insuffisant ; `latest`.*

**Réponse.**

L'artefact (image) est construit une fois à partir d'un commit, identifié
par un tag immuable (SHA). La **promotion** consiste à donner à ce même
digest un nom supplémentaire qui exprime un état (`v1.4.2`, `staging`,
`prod`) : `docker tag` + `push`, ou mieux, création du tag via l'API du
registre sans transfert. Rien n'est reconstruit ; les environnements se
distinguent par la **configuration** injectée au déploiement.

Un tag Git `v1.4.2` seul est insuffisant parce qu'un tag Git peut être
déplacé (`git tag -f`), parce qu'il ne dit pas **quel build** de ce commit
a été promu (deux builds du même commit peuvent différer), et parce que le
lien commit → digest doit être vérifiable : la release doit noter le
digest. Le SHA de commit dans l'image (`APP_VERSION`) et le digest dans la
release ferment la chaîne.

`latest` : au mieux une commodité pour un développeur en local ; jamais
dans un `compose.yaml` de déploiement, jamais poussé par le pipeline.
S'il faut un pointeur « dernière stable », nommer explicitement (`stable`)
et ne le déplacer que par le job de promotion.

::: pourquoi
Le mécanisme qui rend tout cela sûr est l'**adressage par contenu** des
registres OCI : le digest `sha256:…` est le hachage du manifest ; deux
tags sur le même digest désignent rigoureusement les mêmes couches. La
promotion est donc gratuite et sans risque de divergence.
:::

---

**QO25.8** — *Approbation avant `tofu apply` sur GitLab, GitHub, Gitea.*

**Réponse.**

* **GitLab CI** : natif. `when: manual` sur le job `apply` (+ `allow_failure:
  false` pour bloquer le pipeline), et `environment: production` avec
  *protected environment* et *required approvals* : seuls les approbateurs
  peuvent lancer le job.
* **GitHub Actions** : natif. `environment: production` sur le job, avec
  *required reviewers* dans les réglages de l'environnement ; le job se met
  en attente jusqu'à approbation ; les secrets de l'environnement ne sont
  fournis qu'après.
* **Gitea Actions** : pas d'environnement à relecteurs. Contournement :
  `workflow_dispatch` avec un `inputs.confirm`, restreint par la protection
  de branche (qui peut pousser/déclencher sur `main`) et un `if:
  gitea.actor == …` en garde-fou d'affichage ; ou apply automatique au
  merge sur `main` protégée par revue obligatoire — l'approbation est alors
  la revue de la PR, et `plan` doit être publié dans la PR pour que le
  relecteur sache ce qu'il approuve.

Risque spécifique du contournement : le **plan approuvé n'est pas
forcément le plan appliqué**. Sur GitHub/GitLab, le `plan.bin` produit en
PR est celui qu'`apply` consomme dans le même run. Avec un
`workflow_dispatch` séparé, `apply` refait un `plan` plus tard : l'état a
pu changer (dérive, autre PR mergée). Parade : `apply` télécharge
l'artefact `plan.bin` du run approuvé et applique **celui-là** ; OpenTofu
refuse un plan si l'état a bougé entre-temps.

::: pourquoi
Un plan est un contrat entre l'état lu et les actions prévues ; l'appliquer
plus tard n'est sûr que si l'état n'a pas changé, et OpenTofu le vérifie
(le plan enregistre le numéro de série de l'état). C'est pour cela qu'on
publie `plan.bin` et non seulement `plan.txt`.
:::

---

**QO25.9** — *Runner éphémère : définition, problème résolu, coût, disque.*

**Réponse.**

Un runner éphémère exécute **un seul job** puis est détruit (VM, conteneur,
ou act_runner lancé avec `--ephemeral` qui se désenregistre après le job).
Il résout la contamination entre jobs : un job malveillant ou bogué qui
laisse une clé dans `~/.ssh`, un `~/.docker/config.json` connecté au
registre, un paquet modifié dans `/usr/local/bin`, un processus en fond qui
écoute — le job suivant, d'un autre dépôt, hérite de tout cela sur un
runner persistant. Incident type : une PR de fork qui installe un
`git` modifié dans le PATH du runner `host` et vole le jeton des jobs
suivants. Coût : temps de provisionnement à chaque job (30 s à quelques
minutes), perte du cache local, image de runner à maintenir.

Disque d'un runner persistant à 40 builds/jour : les couches
intermédiaires, les images tirées et le cache de build s'accumulent.
Nettoyage planifié (timer systemd nocturne) :

```bash
docker image prune -af --filter "until=48h"
docker builder prune -af --filter "until=48h"
docker volume prune -f          # attention aux volumes de cache nommés
docker system df                # pour mesurer avant/après
```

Plus une alerte de supervision sur `/var/lib/docker` à 80 % : un runner à
disque plein produit des échecs incompréhensibles (`no space left on
device` au milieu d'un `pip install`, images corrompues).

::: pourquoi
`docker system prune` sans filtre `until` supprime aussi les couches de base
(`python:3.12-slim`) que tous les builds réutilisent : le nettoyage trop
agressif rallonge chaque pipeline de la durée du `pull`. Le filtre temporel
garde ce qui sert tous les jours.
:::

---

**QO25.10** — *Définition opérationnelle des quatre métriques DORA.*

**Réponse.**

| Métrique | Donnée brute | Source |
|---|---|---|
| Fréquence de déploiement | nombre de runs `deploy` réussis en prod / semaine | API Gitea `actions/tasks`, ou journal de `factura-deploy` sur `lab-web` |
| Lead time | date du commit (`git log --format=%cI`) → date du déploiement réussi qui le contient | `git` + journal de déploiement, médiane sur 30 j |
| Taux d'échec des changements | déploiements suivis d'un rollback ou d'un incident / déploiements | steps `rollback`/`back` exécutés, tickets d'incident |
| Temps de rétablissement | horodatage incident → horodatage retour à la normale | journal de déploiement (`ko` → `ok` suivant), supervision |

Optimiser les deux premières seulement est l'erreur du « on déploie
10 fois par jour » qui compte aussi les 10 rollbacks : le débit monte, la
stabilité s'effondre, et les utilisateurs mesurent la seconde. Les quatre
forment un système : réduire la taille des changements (débit) réduit aussi
le risque de chaque changement (stabilité), **à condition** que le
pipeline vérifie chaque changement. Un pipeline qui saute les tests ou le
smoke test transfère le coût vers le taux d'échec et le MTTR.

::: pourquoi
Ces métriques sont mesurables **sans outil dédié** avec ce que produit le
module : le journal `deploiements.log` (E25.15) est exactement la source
minimale. La difficulté réelle n'est pas le calcul mais la définition
d'« incident » : convenir d'une règle (rollback exécuté = échec de
changement) et s'y tenir.
:::

---

## 25.5 Exercices guidés

**E25.1** — *Inspecter la forge livrée par le setup.*

```bash
cd ~/lab25/forge
docker compose ps --format 'table {{.Name}}\t{{.Image}}\t{{.Ports}}'
grep -nE 'ACTIONS__ENABLED|INSTALL_LOCK|docker.sock' compose.yaml
ls -la runner/data/.runner
```

* `GITEA__actions__ENABLED=true` active Gitea Actions (équivalent de
  `[actions] ENABLED = true` dans `app.ini`) ;
* `GITEA__security__INSTALL_LOCK=true` marque l'installation comme faite :
  sans elle, le premier accès affiche l'installateur web et l'API refuse
  tout ;
* `/var/run/docker.sock:/var/run/docker.sock` sous `runner` donne au runner
  le démon de l'hôte ;
* `runner/data/.runner` (fichier JSON : `id`, `uuid`, `token`, `address`,
  `labels`) est l'enregistrement. Le supprimer force un nouvel
  enregistrement au prochain démarrage.

::: pourquoi
Gitea lit toute variable `GITEA__section__CLE` et l'écrit dans `app.ini`
au démarrage : `GITEA__database__HOST=db:5432` devient `[database]
HOST = db:5432`. C'est le mécanisme qui permet de configurer Gitea entièrement
depuis le compose, sans éditer le fichier dans le volume. Le runner, lui,
n'a pas d'équivalent : ses variables `GITEA_*` ne servent qu'au **premier**
enregistrement ; ensuite `.runner` et `config.yaml` font foi.
:::

---

**E25.2** — *API Gitea avec le jeton, credential helper Git.*

```bash
TOKEN=$(cat ~/lab25/.gitea-token)
API=http://10.10.10.14:3000/api/v1
curl -s -H "Authorization: token $TOKEN" "$API/user/repos" \
  | python3 -c 'import sys,json
for r in json.load(sys.stdin): print(r["full_name"])'
curl -s -H "Authorization: token $TOKEN" \
  "$API/repos/mathieu/factura/raw/README.md"

cd ~/lab25/factura
git config credential.helper "store --file $HOME/lab25/.git-credentials"
printf 'http://mathieu:%s@10.10.10.14\n' "$TOKEN" > ~/lab25/.git-credentials
chmod 600 ~/lab25/.git-credentials
git push            # « Everything up-to-date », sans demande de mot de passe
```

::: pourquoi
Un jeton d'accès personnel remplace le mot de passe sur HTTP : l'en-tête
`Authorization: token …` pour l'API, `mathieu:<jeton>` en Basic Auth pour
Git. Le helper `store` garde l'identifiant en clair dans un fichier — c'est
acceptable pour un jeton de lab, pas pour un mot de passe. En production on
préfère SSH (clé) ou un helper chiffré. Le setup a déjà posé ce helper ;
l'exercice te le fait refaire pour que tu saches où il est.
:::

::: piege
Ne mets jamais le jeton dans l'URL du remote (`git remote add origin
http://mathieu:TOKEN@…`) : il finit dans `.git/config`, dans `git remote -v`
et dans les journaux de tout script qui affiche l'URL.
:::

---

**E25.3** — *Workflow `hello.yaml` : contextes et variables.*

```yaml
name: hello
on:
  push:
  workflow_dispatch:
jobs:
  hello:
    runs-on: ubuntu-latest
    steps:
      - name: Contextes
        run: |
          echo "sha=${{ gitea.sha }}"
          echo "ref=${{ gitea.ref }}"
          echo "actor=${{ gitea.actor }}"
          echo "event=${{ gitea.event_name }}"
      - name: Variables d'environnement
        run: |
          echo "GITHUB_SHA=$GITHUB_SHA"
          echo "GITHUB_REF_NAME=$GITHUB_REF_NAME"
          echo "GITHUB_WORKSPACE=$GITHUB_WORKSPACE"
          pwd; ls -la
```

Différences observées : `event` vaut `push` puis `workflow_dispatch` ; le
`sha` est identique (même commit) ; `ls -la` montre un répertoire **vide**
hormis `.` et `..` — sans `actions/checkout`, le dépôt n'est pas cloné.

::: pourquoi
Le runner ne clone rien de lui-même : il fournit un répertoire de travail
(`GITHUB_WORKSPACE`, `/workspace/mathieu/factura` dans le conteneur) et des
variables. `actions/checkout@v4` est une action Node qui utilise
`gitea.server_url` et le jeton automatique pour cloner. Les contextes
`${{ }}` sont évalués par le runner **avant** l'exécution ; les variables
`GITHUB_*` sont lues par le shell **pendant**. Les deux disent la même
chose, mais seules les variables peuvent être lues par un script sans
passer par le YAML.
:::

---

**E25.4** — *Matrice Python et `fail-fast`.*

```yaml
  test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: true
      matrix:
        python: ["3.11", "3.12"]
    container:
      image: python:${{ matrix.python }}-slim
    steps:
      - uses: actions/checkout@v4
      - run: pip install -r requirements.txt -r requirements-dev.txt
      - run: pytest -q
      - if: matrix.python == '3.11'
        run: exit 1
```

Avec `fail-fast: true`, l'échec de 3.11 **annule** 3.12 (état `cancelled`)
s'il n'est pas terminé ; avec `false`, 3.12 va au bout et le run montre un
job rouge et un vert.

::: pourquoi
Une matrice développe un job en N jobs indépendants, un par combinaison.
`fail-fast` est une politique d'économie : dès qu'une combinaison échoue,
le résultat global sera rouge, donc inutile de consommer des runners pour
les autres. On le désactive quand l'information « lesquelles échouent »
compte plus que la vitesse (support de plusieurs versions). Le premier
`pytest` échoue sur `ModuleNotFoundError: flask` parce que l'image est nue :
chaque job repart d'un conteneur neuf.
:::

---

**E25.5** — *`needs` et `outputs`.*

```yaml
jobs:
  a:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.v.outputs.version }}
    steps:
      - id: v
        run: echo "version=1.$(date +%s)" >> "$GITHUB_OUTPUT"
      - run: sleep 20
  b:
    runs-on: ubuntu-latest
    steps:
      - run: sleep 20
  c:
    needs: [a, b]
    runs-on: ubuntu-latest
    steps:
      - run: 'echo "version reçue : ${{ needs.a.outputs.version }}"'
```

Durée : `a` et `b` en parallèle → ~20 s + `c`. Avec `needs: a` sur `b`,
40 s + `c`. Avec `runner.capacity: 1`, les deux cas se valent : un seul job
à la fois.

::: pourquoi
Une sortie de step est une ligne `nom=valeur` écrite dans le fichier
`$GITHUB_OUTPUT` ; le runner la lit à la fin du step et l'expose dans
`steps.<id>.outputs`. Le job la republie via `jobs.<id>.outputs`, et seul un
job qui déclare `needs` sur lui peut la lire, parce que c'est `needs` qui
garantit que la valeur existe au moment de l'évaluation. Limite : les sorties
sont des chaînes courtes ; un fichier passe par un artefact.
:::

---

**E25.6** — *Artefact produit, consommé, puis cassé.*

```yaml
  produire:
    runs-on: ubuntu-latest
    steps:
      - run: date > rapport.txt
      - uses: actions/upload-artifact@v4
        with:
          name: rapport
          path: rapport.txt
  consommer:
    needs: produire
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: rapport
      - run: cat rapport.txt
```

Après renommage (`date > rapport-final.txt` sans changer `path`),
`upload-artifact` échoue dans le job **producteur** :
`Error: No files were found with the provided path: rapport.txt`. Le job
`consommer` est sauté.

::: pourquoi
L'artefact est téléversé vers Gitea à la fin du step d'upload, puis
téléchargé par l'autre job : c'est le seul canal de fichiers entre jobs,
puisque chaque job a son propre conteneur et son propre workspace. `path`
est relatif à `GITHUB_WORKSPACE`. Gitea 1.22+ implémente l'API artefacts
v4 ; avec une version plus ancienne, utiliser `@v3`. Les artefacts ont une
rétention (`retention-days`, défaut 90 sur Gitea) et pèsent sur le disque
de la forge.
:::

---

**E25.7** — *Cache pip avec `hashFiles`.*

```yaml
      - uses: actions/cache@v4
        with:
          path: ~/.cache/pip
          key: pip-${{ runner.os }}-${{ hashFiles('requirements*.txt') }}
          restore-keys: |
            pip-${{ runner.os }}-
```

Run 1 : `Cache not found for input keys: pip-Linux-<hash>` puis, en fin de
job, `Cache saved with key…`. Run 2 : `Cache restored from key…`. Après
modification de `requirements-dev.txt`, le hash change : `Cache not found`
pour la clé exacte, mais `restore-keys` restaure l'ancien cache (repli
partiel) et une nouvelle clé est sauvegardée.

::: pourquoi
Le cache est sauvegardé par un step *post* implicite, ajouté par l'action à
la fin du job, **uniquement si la clé exacte n'existait pas**. La clé est
donc le contrat : elle doit changer quand le contenu attendu change. Le
serveur de cache est act_runner lui-même (`cache.enabled: true`, il expose
un port aux conteneurs de jobs via `ACTIONS_CACHE_URL`) : si `cache.enabled`
est `false`, l'action affiche `Cache service responded with 4xx` ou est
ignorée. C'est pour cela que L25.1 l'active.
:::

---

**E25.8** — *Service PostgreSQL joignable par son nom.*

```yaml
  db-test:
    runs-on: ubuntu-latest
    container:
      image: python:3.12-slim
    services:
      db:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: ci
    steps:
      - run: |
          apt-get update -q && apt-get install -y -q postgresql-client
          for i in $(seq 1 20); do
            pg_isready -h db -U postgres && break; sleep 2
          done
          PGPASSWORD=ci psql -h db -U postgres -c 'select version();'
```

Sans `container:`, le job tourne dans l'image du runner, que act_runner
place dans le **même réseau** que les services : `db` reste résolu. La
différence apparaît sur GitHub hébergé : sans `container:`, les services
ne sont joignables que par `localhost:<port publié>`.

::: pourquoi
act_runner crée un réseau Docker par job et y attache le conteneur du job
et chaque service sous le nom de sa clé (`db`). La résolution est faite
par le DNS interne de Docker. La boucle `pg_isready` est indispensable : le
service est *démarré* avant les steps, pas *prêt* — PostgreSQL met quelques
secondes à initialiser son cluster. Sur GitHub Actions on ajoute
`options: --health-cmd pg_isready …` pour que le runner attende.
:::

---

**E25.9** — *Secret via l'API, masquage et ses limites.*

```bash
TOKEN=$(cat ~/lab25/.gitea-token); API=http://10.10.10.14:3000/api/v1
curl -s -X PUT -H "Authorization: token $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"data":"s3cr3t-lab25"}' \
  "$API/repos/mathieu/factura/actions/secrets/DEMO_SECRET"
```

```yaml
      - name: Usage correct
        env:
          DEMO_SECRET: ${{ secrets.DEMO_SECRET }}
        run: echo "longueur = ${#DEMO_SECRET}"
      - name: Fuites
        env:
          DEMO_SECRET: ${{ secrets.DEMO_SECRET }}
        run: |
          echo "$DEMO_SECRET"
          echo "$DEMO_SECRET" | base64
          set -x
          curl -s -o /dev/null -u "u:$DEMO_SECRET" http://10.10.10.14:5000/v2/
```

Journal : `longueur = 12` ; `***` pour le premier `echo` ; la ligne base64
`czNjcjN0LWxhYjIxCg==` en clair ; la trace `+ curl -s -o /dev/null -u u:***`
masquée, car `set -x` développe la valeur exacte. Le vecteur qui fuit ici
est **l'encodage**, pas la trace.

::: pourquoi
Le masquage compare des chaînes : la valeur exacte est remplacée partout où
elle apparaît, y compris dans la trace de `set -x`. Ce qui passe est ce
qui n'est plus la valeur exacte. `curl -v` aurait fuité de la même façon
(`Authorization: Basic dTpzM2NyM3QtbGFiMjE=`). Règle : un secret ne sort
jamais d'une variable, sous aucune forme.
:::

::: piege
L'API `PUT …/actions/secrets/{name}` renvoie `201` à la création et `204`
à la mise à jour : le même appel sert pour la rotation. Rien ne permet de
**lire** un secret ensuite, ni par l'API ni par l'interface : si tu l'as
perdu, tu le remplaces.
:::

---

**E25.10** — *Build, tag SHA, push, digest.*

```bash
cd ~/lab25/factura
SHA=$(git rev-parse --short=12 HEAD)
IMG=10.10.10.14:5000/factura
docker build --build-arg APP_VERSION="$SHA" -t "$IMG:$SHA" .
docker push "$IMG:$SHA"
curl -s -u mathieu:Factura-Reg-2026 http://10.10.10.14:5000/v2/factura/tags/list
docker inspect --format '{{index .RepoDigests 0}}' "$IMG:$SHA"
curl -sI -u mathieu:Factura-Reg-2026 \
  -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
  "http://10.10.10.14:5000/v2/factura/manifests/$SHA" \
  | grep -i docker-content-digest
```

Les deux digests sont identiques : `sha256:…`.

::: pourquoi
`RepoDigests` est rempli au `push` : c'est le hachage du **manifest** tel
que le registre l'a reçu, et le registre le renvoie dans
`Docker-Content-Digest`. C'est ce digest, et non le tag, qui identifie
l'image de façon immuable ; un `compose.yaml` peut d'ailleurs référencer
`factura@sha256:…` directement. Sans l'en-tête `Accept` adapté (OCI ou
`application/vnd.docker.distribution.manifest.v2+json`), le registre peut
renvoyer une conversion en schéma 1 avec un digest différent — piège
classique des scripts de promotion.
:::

---

**E25.11** — *Scan trivy et seuil de blocage.*

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -v trivy-cache:/root/.cache aquasec/trivy:0.58.1 image \
  --severity HIGH,CRITICAL "$IMG:$SHA"
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -v trivy-cache:/root/.cache aquasec/trivy:0.58.1 image \
  --exit-code 1 --severity CRITICAL --ignore-unfixed "$IMG:$SHA"
```

Le premier rapport liste des `HIGH` avec `Fixed Version` vide : ce sont
les vulnérabilités de la base Debian sans correctif publié. Le second,
avec `--ignore-unfixed`, ne compte que ce qu'on **peut** corriger.

Seuil défendable : bloquant sur `CRITICAL` corrigées (`--ignore-unfixed`),
avertissement sur `HIGH`, et un job hebdomadaire planifié qui rescanne les
images **déployées** — une image saine au build devient vulnérable avec le
temps sans qu'aucun commit ne la touche.

::: pourquoi
Bloquer sur tout ce qui est `HIGH` sans distinction rend le pipeline rouge
en permanence pour des CVE que personne ne peut corriger, et l'équipe finit
par ignorer le scan. Le scan est utile quand il produit une action
possible : mettre à jour l'image de base ou une dépendance. Le volume
`trivy-cache` évite de retélécharger la base de vulnérabilités (plusieurs
dizaines de Mo) à chaque run.
:::

---

**E25.12** — *Clé à commande forcée pour `deploy` sur `lab-web`.*

Sur `lab-ops` :

```bash
cat ~/lab25/keys/deploy.pub
```

Sur `lab-web`, en tant que `mathieu` :

```bash
sudo install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
PUB='<contenu de deploy.pub>'
printf 'command="/usr/local/bin/factura-deploy",from="10.10.10.14",\
no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty %s\n' \
  "$PUB" | sudo tee /home/deploy/.ssh/authorized_keys
sudo chown deploy:deploy /home/deploy/.ssh/authorized_keys
sudo chmod 600 /home/deploy/.ssh/authorized_keys
sudo tee /usr/local/bin/factura-deploy >/dev/null <<'EOF'
#!/usr/bin/env bash
echo "commande reçue : ${SSH_ORIGINAL_COMMAND:-<aucune>}"
EOF
sudo chmod 755 /usr/local/bin/factura-deploy
```

Depuis `lab-ops` :

```bash
ssh -i ~/lab25/keys/deploy deploy@10.10.10.11 id
# commande reçue : id
```

::: pourquoi
`command="…"` dans `authorized_keys` remplace **toute** commande demandée
par le client par celle indiquée ; l'original est transmis dans
`SSH_ORIGINAL_COMMAND`. Le script devient un mini-protocole : il décide ce
qu'il accepte. `from=` limite l'adresse source, `no-pty` empêche un shell
interactif, les `no-*-forwarding` ferment les tunnels. Même si la clé
privée fuit du pipeline, l'attaquant ne peut que déployer une version déjà
présente dans le registre, depuis `lab-ops`.
:::

---

**E25.13** — *Runner natif `host` sur `lab-ops`.*

```bash
V=0.2.11     # vérifie la dernière version sur https://dl.gitea.com/act_runner/
sudo curl -fsSL -o /usr/local/bin/act_runner \
  "https://dl.gitea.com/act_runner/$V/act_runner-$V-linux-amd64"
sudo chmod 755 /usr/local/bin/act_runner
sudo useradd -r -m -d /var/lib/act_runner -s /usr/sbin/nologin runner
TOKEN_REG=$(docker exec -u git gitea gitea actions generate-runner-token)
sudo -u runner bash -c "cd /var/lib/act_runner && \
  act_runner generate-config > config.yaml && \
  act_runner register --no-interactive --instance http://10.10.10.14:3000 \
  --token $TOKEN_REG --name runner-shell --labels lab-shell:host"
sudo tee /etc/systemd/system/act_runner.service >/dev/null <<'EOF'
[Unit]
Description=Gitea act_runner (host)
After=network-online.target

[Service]
User=runner
WorkingDirectory=/var/lib/act_runner
ExecStart=/usr/local/bin/act_runner daemon --config config.yaml
Restart=always

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now act_runner.service
```

```yaml
  shell:
    runs-on: lab-shell
    steps:
      - run: id; hostname; pwd
```

Sur `lab-shell` : `uid=…(runner)`, `lab-ops`, `/var/lib/act_runner/…`
(dans `host.workdir_parent`) ; sur `ubuntu-latest` : `uid=0(root)`, un
nom de conteneur aléatoire, `/workspace/mathieu/factura`.

::: pourquoi
Un runner `host` exécute les steps dans un sous-processus de `act_runner` :
l'identité, le `PATH` et le disque sont ceux de l'utilisateur système
`runner`. C'est utile pour des jobs qui ont besoin de l'hôte (accès à un
matériel, à un cache local volumineux, à `sudo` maîtrisé) et dangereux
pour tout le reste : l'utilisateur `runner` ne doit être ni dans `docker`
ni dans `sudo`, sinon on a un `host` équivalent root. Le jeton
d'enregistrement expire ; en générer un par runner.
:::

---

**E25.14** — *Tag Git `v0.1.0` et tag d'image conditionnel.*

```bash
cd ~/lab25/factura
git tag -a v0.1.0 -m 'première version'
git push origin v0.1.0
```

```yaml
      - name: Tag de version
        if: startsWith(gitea.ref, 'refs/tags/v')
        run: |
          docker tag "$IMAGE:$TAG" "$IMAGE:$GITHUB_REF_NAME"
          docker push "$IMAGE:$GITHUB_REF_NAME"
```

```bash
for t in "$SHA" v0.1.0; do
  curl -sI -u mathieu:Factura-Reg-2026 \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    "http://10.10.10.14:5000/v2/factura/manifests/$t" \
    | grep -i docker-content-digest
done
```

Même digest sur les deux lignes.

::: pourquoi
Un push de tag déclenche `on.push.tags` avec `gitea.ref =
refs/tags/v0.1.0` et `GITHUB_REF_NAME = v0.1.0`. Le `docker tag` n'ajoute
qu'un nom local ; le `push` du second tag ne transfère aucune couche (le
registre les possède déjà) et crée un second pointeur sur le même
manifest. C'est la forme la plus simple de promotion. Attention : un push
de tag crée un run **distinct** de celui du commit ; l'image du SHA doit
donc être reconstruite ou retrouvée — d'où le job `promote` du défi.
:::

---

**E25.15** — *`dora.sh` : quatre métriques à partir de `git log` et du
journal de déploiements.*

```bash
#!/usr/bin/env bash
# dora.sh — métriques DORA sur 30 jours (factura)
set -euo pipefail
LOG="${1:-$HOME/lab25/rapports/deploiements.log}"   # date;sha;resultat
DEPOT="${2:-$HOME/lab25/factura}"
DEPUIS=$(date -d '30 days ago' +%s)

total=0; ok=0; ko=0; declare -a leads=()
mttr_total=0; mttr_n=0; debut_ko=""
while IFS=';' read -r d sha res; do
  [[ -z $d || $d == \#* ]] && continue
  t=$(date -d "$d" +%s); (( t < DEPUIS )) && continue
  total=$((total+1))
  if [[ $res == ok ]]; then
    ok=$((ok+1))
    c=$(git -C "$DEPOT" log -1 --format=%ct "$sha" 2>/dev/null || echo "")
    [[ -n $c ]] && leads+=( $(( (t - c) / 3600 )) )
    if [[ -n $debut_ko ]]; then
      mttr_total=$((mttr_total + t - debut_ko)); mttr_n=$((mttr_n+1))
      debut_ko=""
    fi
  else
    ko=$((ko+1)); [[ -z $debut_ko ]] && debut_ko=$t
  fi
done < "$LOG"

mediane() { printf '%s\n' "$@" | sort -n | awk '{a[NR]=$1}
  END{ if(NR==0){print "n/a"} else if(NR%2){print a[(NR+1)/2]}
       else {print (a[NR/2]+a[NR/2+1])/2} }'; }

printf 'Déploiements (30 j)       : %d (%.1f / jour)\n' "$total" \
  "$(echo "$total/30" | bc -l)"
printf 'Lead time médian (h)      : %s\n' "$(mediane "${leads[@]:-}")"
printf 'Taux d'"'"'échec              : %d %%\n' \
  "$(( total ? ko*100/total : 0 ))"
printf 'MTTR moyen (min)          : %s\n' \
  "$(( mttr_n ? mttr_total/60/mttr_n : 0 ))"
```

::: pourquoi
Chaque métrique se ramène à une soustraction de deux horodatages ou à un
rapport de deux compteurs, à condition d'avoir la **donnée brute** : un
journal de déploiements avec date, identité de la version et résultat.
C'est ce que produit naturellement un pipeline qui journalise ses
déploiements (une ligne écrite par `factura-deploy` dans
`/srv/factura/deploiements.log`, rapatriée par `scp` ou exposée par
l'API). Le *lead time* relie la date du commit (`git log --format=%ct`) à
la date de mise en prod ; le MTTR relie un déploiement `ko` au premier `ok`
suivant.
:::

---

## 25.6 Labs

### **L25.1** — *La forge : Gitea, runner, premier pipeline vert*

**1. `forge.md` : trois réponses attendues.**

* `GITEA_INSTANCE_URL=http://10.10.10.14:3000` : cette URL est
  enregistrée dans `.runner` et transmise aux **conteneurs de jobs**
  (`gitea.server_url`, utilisée par `actions/checkout`). Ces conteneurs
  sont créés par le démon de l'hôte, hors du réseau du compose : `gitea`
  n'y est pas résolu. L'IP de l'hôte, avec le port publié, est joignable de
  partout.
* `ROOT_URL` en IP pour la même raison, plus une : `lab.local` n'est résolu
  que par `/etc/hosts` des VM, jamais par le DNS interne de Docker.
* `container.docker_host: ""` : act_runner détecte le socket et le
  **monte dans chaque job**, qui devient root sur `lab-ops`. `"-"` ne le
  monterait pas, et `docker build` échouerait.

**2. Capacité et cache.**

```bash
cd ~/lab25/forge
sed -i -e 's/^  capacity: .*/  capacity: 2/' \
       -e 's/^  enabled: false/  enabled: true/' runner/config.yaml
grep -nE 'capacity|enabled' runner/config.yaml
docker compose restart runner
docker compose logs --tail 20 runner | grep -iE 'labels|listen|cache'
```

**3. Protection de branche** — *Dépôt → Paramètres → Branches → Ajouter
une règle* : nom `main`, « Activer la protection des push » avec liste
blanche `mathieu`, « Exiger des approbations » = 1, « Vérification de
statut » = `ci / lint` (visible après un premier run). Par l'API :

```bash
TOKEN=$(cat ~/lab25/.gitea-token); API=http://10.10.10.14:3000/api/v1
curl -s -X POST -H "Authorization: token $TOKEN" \
  -H 'Content-Type: application/json' \
  "$API/repos/mathieu/factura/branch_protections" -d '{
  "branch_name": "main", "enable_push": true,
  "enable_push_whitelist": true, "push_whitelist_usernames": ["mathieu"],
  "required_approvals": 1, "enable_status_check": true,
  "status_check_contexts": ["ci / lint"] }'
```

**4. `.yamllint` puis `.gitea/workflows/ci.yaml`.**

```yaml
# .yamllint
extends: default
rules:
  line-length:
    max: 100
  truthy:
    allowed-values: ["true", "false", "on"]
  document-start: disable
```

```yaml
# .gitea/workflows/ci.yaml — version L25.1
name: ci
on:
  push:
  pull_request:
  workflow_dispatch:

jobs:
  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - name: Outils
        run: |
          apt-get update -q
          apt-get install -y -q --no-install-recommends shellcheck yamllint
      - name: yamllint
        run: yamllint -s .
      - name: shellcheck
        run: shellcheck -x scripts/*.sh deploy/*.sh
      - name: hadolint
        run: docker run --rm -i hadolint/hadolint:2.12.0 < Dockerfile

  test:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    container:
      image: python:3.12-slim
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        with:
          path: ~/.cache/pip
          key: pip-${{ hashFiles('requirements*.txt') }}
      - name: Dépendances
        run: pip install -r requirements.txt -r requirements-dev.txt
      - name: Tests
        run: pytest -q --junitxml=rapport-tests.xml
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: rapport-tests
          path: rapport-tests.xml
```

**5. Les deux causes.** `shellcheck` signale `SC2086` dans
`scripts/smoke.sh` (`curl -fsS $URL/version` non quoté) : quoter
`"$URL/version"`. `pytest` échoue sur `test_facture_zero` : `app.py`
renvoie 200 pour `/factures/0` au lieu de 404 — la condition est `n < 0`,
il faut `n <= 0`. Correction sur `fix/ci`, PR, pipeline vert sur la PR,
merge (avec ton auto-approbation impossible : désactive temporairement
`required_approvals` ou crée un second compte relecteur — c'est l'occasion
de voir que la règle s'applique aussi à l'admin).

::: pourquoi
Le job `lint` tourne dans l'image du runner (Ubuntu avec Docker CLI et
socket), d'où `apt-get` sans `sudo` (root dans le conteneur) et `docker
run` possible pour hadolint. Le `Dockerfile` est passé **sur stdin**
(`-i … < Dockerfile`) parce qu'un montage `-v "$PWD:/src"` désignerait un
chemin sur l'**hôte**, où le workspace du job n'existe pas : le conteneur
frère verrait un répertoire vide. Le job `test` tourne dans
`python:3.12-slim` : plus petit, sans Docker, reproductible, et
`actions/checkout` y fonctionne parce que act_runner injecte son propre
Node dans tout conteneur de job.
`if: always()` sur l'artefact est ce qui rend le rapport de tests utile :
on en a besoin **surtout** quand ils échouent.
:::

::: piege
`yamllint -s` traite les avertissements comme des erreurs ; sans le
`.yamllint`, la règle `truthy` refuse la clé `on` et le job est rouge avant
même d'avoir regardé tes fichiers. Second piège : `status_check_contexts`
attend le nom exact `workflow / job` (`ci / lint`) ; une faute de frappe
rend la PR à jamais « en attente de vérification ».
:::

---

### **L25.2** — *Pipeline complet : de la PR au rollback automatique*

**1. `/usr/local/bin/factura-deploy` sur `lab-web`.**

```bash
#!/usr/bin/env bash
# factura-deploy — commande forcée de la clé de déploiement (user deploy)
set -euo pipefail
cd /srv/factura
LOG=/srv/factura/deploiements.log
read -r action tag _ <<<"${SSH_ORIGINAL_COMMAND:-}"

journal() { printf '%s;%s;%s\n' "$(date -Is)" "$1" "$2" >> "$LOG"; }

case "${action:-}" in
  deploy)
    [[ ${tag:-} =~ ^([0-9a-f]{12}|v[0-9]+\.[0-9]+\.[0-9]+)$ ]] \
      || { echo "tag invalide : '${tag:-}'" >&2; exit 2; }
    cp .env .env.prev
    printf 'TAG=%s\n' "$tag" > .env
    if docker compose pull -q && docker compose up -d; then
      journal "$tag" ok
    else
      journal "$tag" ko; exit 1
    fi ;;
  rollback)
    [[ -s .env.prev ]] || { echo "pas de version précédente" >&2; exit 3; }
    cp .env.prev .env
    docker compose pull -q && docker compose up -d
    journal "$(cut -d= -f2 .env)" rollback ;;
  status)
    cat .env; docker compose ps --format '{{.Name}} {{.Image}} {{.Status}}' ;;
  *)
    echo "commande refusée : '${SSH_ORIGINAL_COMMAND:-}'" >&2; exit 2 ;;
esac
```

`authorized_keys` de `deploy` : la ligne de E25.12 (commande forcée,
`from="10.10.10.14"`, `no-pty`, `no-*-forwarding`).

**2. `/srv/factura/compose.yaml` et `.env`.**

```yaml
services:
  app:
    image: 10.10.10.14:5000/factura:${TAG:?TAG obligatoire}
    ports:
      - "8080:8000"
    restart: unless-stopped
    environment:
      APP_COLOR: single
```

```bash
printf 'TAG=\n' > /srv/factura/.env
docker compose config      # error: required variable TAG is missing a value
```

**3. Registre.** `/etc/docker/daemon.json` contient
`{"insecure-registries": ["10.10.10.14:5000"]}` ; test :
`sudo -u deploy docker pull 10.10.10.14:5000/factura:<sha12>`.

**4. Secret et variable.**

```bash
TOKEN=$(cat ~/lab25/.gitea-token); API=http://10.10.10.14:3000/api/v1
H=(-H "Authorization: token $TOKEN" -H 'Content-Type: application/json')
python3 - <<'EOF' > /tmp/secret.json
import json,os
cle = open(os.path.expanduser("~/lab25/keys/deploy")).read()
print(json.dumps({"data": cle}))
EOF
R=$API/repos/mathieu/factura/actions
curl -s -X PUT "${H[@]}" -d @/tmp/secret.json "$R/secrets/DEPLOY_SSH_KEY"
rm /tmp/secret.json
curl -s -X PUT "${H[@]}" -d '{"data":"Factura-Reg-2026"}' \
  "$R/secrets/REGISTRY_PASSWORD"
curl -s -X POST "${H[@]}" -d '{"value":"mathieu"}' "$R/variables/REGISTRY_USER"
HK=$(ssh-keyscan -t ed25519 10.10.10.11 2>/dev/null)
curl -s -X POST "${H[@]}" -d "{\"value\": \"$HK\"}" \
  "$R/variables/LAB_WEB_HOSTKEY"
```

**5. `ci.yaml` complet (version L25.2).**

```yaml
name: ci
on:
  push:
    branches: ["**"]
    tags: ["v*"]
  pull_request:
  workflow_dispatch:

env:
  IMAGE: 10.10.10.14:5000/factura

jobs:
  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - name: Outils
        run: |
          apt-get update -q
          apt-get install -y -q --no-install-recommends shellcheck yamllint
      - run: yamllint -s .
      - run: shellcheck -x scripts/*.sh deploy/*.sh
      - run: docker run --rm -i hadolint/hadolint:2.12.0 < Dockerfile

  test:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    container:
      image: python:3.12-slim
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        with:
          path: ~/.cache/pip
          key: pip-${{ hashFiles('requirements*.txt') }}
      - run: pip install -r requirements.txt -r requirements-dev.txt
      - run: pytest -q --junitxml=rapport-tests.xml
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: rapport-tests
          path: rapport-tests.xml

  build:
    needs: [lint, test]
    runs-on: ubuntu-latest
    timeout-minutes: 15
    outputs:
      tag: ${{ steps.meta.outputs.tag }}
    steps:
      - uses: actions/checkout@v4
      - id: meta
        run: echo "tag=${GITHUB_SHA::12}" >> "$GITHUB_OUTPUT"
      - name: Build
        env:
          TAG: ${{ steps.meta.outputs.tag }}
        run: docker build --build-arg "APP_VERSION=$TAG" -t "$IMAGE:$TAG" .
      - name: Scan trivy
        env:
          TAG: ${{ steps.meta.outputs.tag }}
        run: |
          docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
            -v trivy-cache:/root/.cache aquasec/trivy:0.58.1 image \
            --exit-code 1 --severity CRITICAL --ignore-unfixed "$IMAGE:$TAG"
      - name: Login registre
        if: gitea.event_name != 'pull_request'
        env:
          REG_USER: ${{ vars.REGISTRY_USER }}
          REG_PASS: ${{ secrets.REGISTRY_PASSWORD }}
        run: |
          printf '%s' "$REG_PASS" | docker login 10.10.10.14:5000 \
            -u "$REG_USER" --password-stdin
      - name: Push
        if: gitea.event_name != 'pull_request'
        env:
          TAG: ${{ steps.meta.outputs.tag }}
        run: docker push "$IMAGE:$TAG"
      - name: Tag de version
        if: startsWith(gitea.ref, 'refs/tags/v')
        env:
          TAG: ${{ steps.meta.outputs.tag }}
        run: |
          docker tag "$IMAGE:$TAG" "$IMAGE:$GITHUB_REF_NAME"
          docker push "$IMAGE:$GITHUB_REF_NAME"

  deploy:
    needs: build
    if: gitea.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    timeout-minutes: 10
    concurrency:
      group: deploy-lab-web
      cancel-in-progress: false
    env:
      TAG: ${{ needs.build.outputs.tag }}
      SSH: ssh -i /root/.ssh/deploy -o BatchMode=yes deploy@10.10.10.11
    steps:
      - name: Clé SSH
        env:
          KEY: ${{ secrets.DEPLOY_SSH_KEY }}
          HOSTKEY: ${{ vars.LAB_WEB_HOSTKEY }}
        run: |
          mkdir -p /root/.ssh && chmod 700 /root/.ssh
          printf '%s\n' "$KEY" > /root/.ssh/deploy
          chmod 600 /root/.ssh/deploy
          printf '%s\n' "$HOSTKEY" > /root/.ssh/known_hosts
      - name: Déploiement
        run: $SSH "deploy $TAG"
      - name: Smoke test
        run: |
          for i in $(seq 1 10); do
            v=$(curl -fsS http://10.10.10.11:8080/version || true)
            [ "$v" = "$TAG" ] && { echo "OK version $v"; exit 0; }
            sleep 3
          done
          echo "version servie '$v', attendue '$TAG'" >&2
          exit 1
      - name: Rollback
        if: failure()
        run: $SSH rollback
```

**6–7.** Après push sur `main` : `curl http://10.10.10.11:8080/version`
renvoie le SHA. Version cassée :

```bash
cd ~/lab25/factura
sed -i 's/return VERSION + "\\n"/return "broken-" + VERSION + "\\n"/' app.py
git commit -am 'test rollback' && git push
```

Le run montre `deploy` vert, `Smoke test` rouge (`version servie
'broken-…'`), `Rollback` vert. Sur `lab-web` : `cat /srv/factura/.env`
donne l'ancien tag, `/version` l'ancien SHA, `deploiements.log` une ligne
`ok`, puis `rollback`. Retour à une version saine : `git revert HEAD` et push.

**8. Rapport** : ordres de grandeur attendus sur `lab-ops` (4 Go) : `lint`
40–60 s (dont `apt-get` 30 s), `test` 30 s puis 15 s avec cache, `build`
60–90 s la première fois (pull de `python:3.12-slim`, base trivy) puis
30 s, `deploy` 20 s. Pour tenir sous 3 minutes : image de runner avec
`shellcheck`/`yamllint` préinstallés, `docker build` avec
`--cache-from`, base trivy dans le volume nommé (fait), `lint` et `test`
parallèles (fait).

::: pourquoi
Le mécanisme central est l'**identité de bout en bout** : le SHA est
calculé une fois (`meta`), injecté dans l'image (`APP_VERSION`), transmis
au job `deploy` par `needs.build.outputs.tag`, validé par regex côté
`lab-web`, puis **exigé** par le smoke test. Chaque étape peut échouer
pour une raison distincte et le rollback n'agit que si le job de
déploiement a réellement commencé (il est dans le même job que le smoke
test, donc `failure()` fonctionne). `concurrency` sérialise les
déploiements sans annuler celui en cours. La clé privée n'existe que dans
le conteneur du job, détruit à la fin.

Le `if: gitea.event_name != 'pull_request'` sur le push est ce qui fait
de la PR une CI pure : on construit et scanne (preuve), on ne publie pas
(pas d'effet de bord).
:::

::: piege
* `printf '%s\n' "$KEY"` : un `echo $KEY` non quoté recolle la clé sur une
  ligne, `ssh` répond `invalid format`.
* `BatchMode=yes` : sans lui, un problème de clé fait attendre un mot de
  passe jusqu'au `timeout-minutes`.
* `${TAG:?}` dans le compose : sans le `:?`, un `.env` vide donne
  `factura:` et Docker tire… `latest`.
* Sur `lab-web`, `deploy` doit être dans le groupe `docker` — ce qui
  équivaut à root sur `lab-web` ; la commande forcée est ce qui rend ce
  choix acceptable.
:::

**9. Le même pipeline ailleurs.**

`.gitlab-ci.yml` :

```yaml
stages: [lint, test, build, deploy]

variables:
  IMAGE: 10.10.10.14:5000/factura
  TAG: $CI_COMMIT_SHORT_SHA

default:
  tags: [docker]

lint:
  stage: lint
  image: python:3.12-slim
  script:
    - apt-get update -q && apt-get install -y -q shellcheck
    - pip install -q yamllint
    - yamllint -s .
    - shellcheck -x scripts/*.sh deploy/*.sh

hadolint:
  stage: lint
  image: hadolint/hadolint:2.12.0-alpine
  script: [hadolint Dockerfile]

test:
  stage: test
  image: python:3.12-slim
  cache:
    key:
      files: [requirements.txt, requirements-dev.txt]
    paths: [.cache/pip]
  variables:
    PIP_CACHE_DIR: $CI_PROJECT_DIR/.cache/pip
  script:
    - pip install -r requirements.txt -r requirements-dev.txt
    - pytest -q --junitxml=rapport-tests.xml
  artifacts:
    when: always
    reports:
      junit: rapport-tests.xml

build:
  stage: build
  image: docker:27
  services: [docker:27-dind]
  needs: [lint, hadolint, test]
  script:
    - docker build --build-arg "APP_VERSION=$TAG" -t "$IMAGE:$TAG" .
    - docker run --rm -v /var/run/docker.sock:/var/run/docker.sock
        aquasec/trivy:0.58.1 image --exit-code 1 --severity CRITICAL
        --ignore-unfixed "$IMAGE:$TAG"
    - docker push "$IMAGE:$TAG"
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      when: never
    - if: $CI_COMMIT_BRANCH || $CI_COMMIT_TAG

deploy:
  stage: deploy
  image: alpine:3.20
  needs: [build]
  environment:
    name: production
    url: http://10.10.10.11:8080
  resource_group: lab-web
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
      when: manual
  before_script:
    - apk add --no-cache openssh-client curl
    - mkdir -p ~/.ssh && chmod 700 ~/.ssh
    - printf '%s\n' "$DEPLOY_SSH_KEY" > ~/.ssh/deploy && chmod 600 ~/.ssh/deploy
    - printf '%s\n' "$LAB_WEB_HOSTKEY" > ~/.ssh/known_hosts
  script:
    - ssh -i ~/.ssh/deploy deploy@10.10.10.11 "deploy $TAG"
    - |
      for i in $(seq 1 10); do
        [ "$(curl -fsS http://10.10.10.11:8080/version)" = "$TAG" ] && exit 0
        sleep 3
      done
      ssh -i ~/.ssh/deploy deploy@10.10.10.11 rollback; exit 1
```

Correspondances : `stages` + `stage:` remplacent `needs` pour l'ordre
(et `needs:` GitLab permet de démarrer dès que les dépendances sont
finies, sans attendre tout le stage) ; `rules:` remplace `if:` ;
`resource_group` remplace `concurrency` ; `when: manual` + `environment`
donnent l'approbation native ; les variables masquées sont déclarées
*masked* et *protected* dans les réglages CI/CD, `$DEPLOY_SSH_KEY` de
type *file* évite même le `printf`. Le rollback est dans le `script`,
GitLab n'ayant pas de `if: failure()` par step (mais `after_script`
s'exécute toujours).

GitHub Actions, avec les actions Docker officielles et un environnement à
relecteurs :

```yaml
name: ci
on:
  push:
    branches: [main]
    tags: ["v*"]
  pull_request:

env:
  IMAGE: ghcr.io/${{ github.repository }}

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: pip
      - run: pip install -r requirements.txt -r requirements-dev.txt
      - run: pytest -q

  build:
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    outputs:
      tag: ${{ steps.meta.outputs.version }}
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.IMAGE }}
          tags: |
            type=sha,format=short,prefix=
            type=semver,pattern={{version}}
      - uses: docker/build-push-action@v5
        with:
          context: .
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          build-args: APP_VERSION=${{ steps.meta.outputs.version }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy:
    needs: build
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment:
      name: production
      url: http://10.10.10.11:8080
    concurrency:
      group: deploy-prod
      cancel-in-progress: false
    steps:
      - uses: webfactory/ssh-agent@v0.9.0
        with:
          ssh-private-key: ${{ secrets.DEPLOY_SSH_KEY }}
      - run: ssh deploy@10.10.10.11 "deploy ${{ needs.build.outputs.tag }}"
```

`environment: production` avec *required reviewers* met le job en attente
d'approbation ; `secrets.GITHUB_TOKEN` avec `permissions: packages:
write` publie sur `ghcr.io` sans secret statique ; `cache-from/to:
type=gha` met en cache les couches Docker dans le cache d'Actions.
L'OIDC : `permissions: id-token: write` puis
`aws-actions/configure-aws-credentials@v4` obtient des identifiants
temporaires sans aucun secret stocké — c'est le modèle vers lequel tendre.

`Jenkinsfile` déclaratif :

```groovy
pipeline {
  agent { docker { image 'python:3.12-slim' } }
  stages {
    stage('lint')  { steps { sh 'pip install -q yamllint; yamllint -s .' } }
    stage('test') { steps { sh 'pip install -r requirements-dev.txt; pytest' } }
    stage('build') {
      agent { label 'docker' }
      steps { sh "docker build -t factura:${GIT_COMMIT.take(12)} ." }
    }
  }
  post { always { junit allowEmptyResults: true, testResults: 'rapport.xml' } }
}
```

::: pourquoi
Les trois forges ont le même modèle sous des noms différents : un
**graphe de jobs** (stages ou `needs`), des **agents étiquetés**
(`tags`/`runs-on`/`agent { label }`), des **artefacts** et un **cache**,
des **conditions** (`rules`/`if`/`when`), des **secrets** injectés dans
l'environnement. Ce qui change vraiment : la gouvernance (environnements,
approbations, variables protégées), native sur GitLab et GitHub, à
construire sur Gitea et Jenkins ; et le modèle d'exécution de Jenkins,
où le pipeline est un programme Groovy exécuté par le contrôleur, ce qui
explique sa puissance et ses dérives.
:::

---

### **L25.3** — *Blue/green derrière nginx, bascule depuis le pipeline*

**1. `/srv/factura-bg/compose.yaml` et `.env`.**

```yaml
services:
  blue:
    image: 10.10.10.14:5000/factura:${TAG_BLUE:?}
    ports:
      - "127.0.0.1:8081:8000"
    restart: unless-stopped
    environment:
      APP_COLOR: blue
  green:
    image: 10.10.10.14:5000/factura:${TAG_GREEN:?}
    ports:
      - "127.0.0.1:8082:8000"
    restart: unless-stopped
    environment:
      APP_COLOR: green
```

```bash
printf 'TAG_BLUE=%s\nTAG_GREEN=%s\n' <sha_prod> <sha_precedent> \
  > /srv/factura-bg/.env
cd /srv/factura-bg && docker compose up -d
```

**2. nginx.**

```nginx
# /etc/nginx/factura/blue.conf
upstream factura_live { server 127.0.0.1:8081; }
```

```nginx
# /etc/nginx/factura/green.conf
upstream factura_live { server 127.0.0.1:8082; }
```

```nginx
# /etc/nginx/sites-available/factura.conf
map $upstream_addr $factura_color {
    "~:8081" blue;
    "~:8082" green;
    default  unknown;
}
server {
    listen 80 default_server;
    server_name _;
    location / {
        proxy_pass http://factura_live;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        add_header X-Factura-Color $factura_color always;
    }
}
```

```bash
sudo mkdir -p /etc/nginx/factura
sudo ln -sfn /etc/nginx/factura/blue.conf \
  /etc/nginx/conf.d/factura-upstream.conf
sudo ln -sfn /etc/nginx/sites-available/factura.conf \
  /etc/nginx/sites-enabled/factura.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
curl -sI http://10.10.10.11/ | grep -i x-factura-color
```

Pourquoi hors de `conf.d` : nginx inclut **tous** les `conf.d/*.conf` ;
deux fichiers définissant `upstream factura_live` donneraient
`duplicate upstream "factura_live"`. Seul le symlink vit dans `conf.d`.

**3. `/usr/local/bin/factura-bg` et sudoers.**

```bash
#!/usr/bin/env bash
# factura-bg — commande forcée de la clé blue/green (user deploy)
set -euo pipefail
cd /srv/factura-bg
LINK=/etc/nginx/conf.d/factura-upstream.conf
read -r action tag _ <<<"${SSH_ORIGINAL_COMMAND:-}"

live()     { basename "$(readlink -f "$LINK")" .conf; }   # blue | green
inactive() { [ "$(live)" = blue ] && echo green || echo blue; }
port()     { [ "$1" = blue ] && echo 8081 || echo 8082; }
bascule()  {
  sudo /usr/bin/ln -sfn "/etc/nginx/factura/$1.conf" "$LINK"
  sudo /usr/sbin/nginx -t && sudo /usr/bin/systemctl reload nginx
}

case "${action:-}" in
  status)
    echo "live=$(live) inactive=$(inactive) port_inactive=$(port "$(inactive)")"
    cat .env ;;
  stage)
    [[ ${tag:-} =~ ^([0-9a-f]{12}|v[0-9]+\.[0-9]+\.[0-9]+)$ ]] || exit 2
    c=$(inactive); var=TAG_${c^^}
    sed -i "s/^$var=.*/$var=$tag/" .env
    docker compose pull -q "$c" && docker compose up -d "$c"
    for i in $(seq 1 15); do
      curl -fsS "http://127.0.0.1:$(port "$c")/health" >/dev/null && exit 0
      sleep 2
    done
    echo "$c ne répond pas" >&2; exit 1 ;;
  smoke)
    curl -fsS "http://127.0.0.1:$(port "$(inactive)")/version" ;;
  switch) bascule "$(inactive)"; echo "live=$(live)" ;;
  back)   bascule "$(inactive)"; echo "live=$(live)" ;;
  *) echo "commande refusée" >&2; exit 2 ;;
esac
```

```text
# /etc/sudoers.d/factura-bg  (visudo -cf pour valider)
Cmnd_Alias BG_BLUE  = /usr/bin/ln -sfn /etc/nginx/factura/blue.conf \
                      /etc/nginx/conf.d/factura-upstream.conf
Cmnd_Alias BG_GREEN = /usr/bin/ln -sfn /etc/nginx/factura/green.conf \
                      /etc/nginx/conf.d/factura-upstream.conf
deploy ALL=(root) NOPASSWD: BG_BLUE, BG_GREEN
deploy ALL=(root) NOPASSWD: /usr/sbin/nginx -t
deploy ALL=(root) NOPASSWD: /usr/bin/systemctl reload nginx
```

Seconde ligne d'`authorized_keys` pour `deploy`, avec
`command="/usr/local/bin/factura-bg"` et la clé `bg.pub`.

**4.** La boucle de `curl` n'affiche que des `200` pendant `switch` :
`reload` ne coupe aucune connexion.

**5. Job `deploy` blue/green.**

```yaml
  deploy:
    needs: build
    if: gitea.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    timeout-minutes: 10
    concurrency:
      group: deploy-lab-web
      cancel-in-progress: false
    env:
      TAG: ${{ needs.build.outputs.tag }}
      SSH: ssh -i /root/.ssh/bg -o BatchMode=yes deploy@10.10.10.11
    steps:
      - name: Clé SSH
        env:
          KEY: ${{ secrets.BG_SSH_KEY }}
          HOSTKEY: ${{ vars.LAB_WEB_HOSTKEY }}
        run: |
          mkdir -p /root/.ssh && chmod 700 /root/.ssh
          printf '%s\n' "$KEY" > /root/.ssh/bg && chmod 600 /root/.ssh/bg
          printf '%s\n' "$HOSTKEY" > /root/.ssh/known_hosts
      - name: Stage sur la couleur inactive
        run: $SSH "stage $TAG"
      - name: Smoke test inactif
        run: |
          v=$($SSH smoke)
          [ "$v" = "$TAG" ] || { echo "attendu $TAG, servi $v" >&2; exit 1; }
      - name: Switch
        id: switch
        run: $SSH switch
      - name: Smoke test live
        run: |
          v=$(curl -fsS http://10.10.10.11/version)
          [ "$v" = "$TAG" ] || { echo "attendu $TAG, servi $v" >&2; exit 1; }
      - name: Back
        if: failure() && steps.switch.outcome == 'success'
        run: $SSH back
```

Le port de la couleur inactive n'est publié que sur `127.0.0.1`
(étape 1) : depuis `lab-ops`, on ne peut pas le joindre, et la commande
forcée interdit un `ssh … curl`. D'où la sous-commande `smoke` de
`factura-bg`, qui exécute le `curl` sur place et renvoie `/version` : le
port reste fermé, le pipeline garde sa preuve. L'énoncé te laissait trouver
cette contrainte ; publier les ports sur `10.10.10.11` aurait aussi marché,
au prix d'une surface exposée en plus.

**6.** Avec la version `broken-`, le run s'arrête à `Smoke test inactif` ;
`switch` n'a pas tourné, `Back` est sauté (`steps.switch.outcome` vaut
`skipped`), et la prod n'a servi que l'ancienne couleur.

**7. Ce que blue/green ne résout pas.** Migrations de schéma (les deux
couleurs partagent la base : seules les migrations *expand/contract* sont
compatibles) ; sessions en mémoire (perdues à la bascule → session
externalisée) ; coût double ; tâches de fond en double si les deux couleurs
tournent des workers. Canari nginx à 10 % :

```nginx
upstream factura_live {
    server 127.0.0.1:8081 weight=9;
    server 127.0.0.1:8082 weight=1;
}
```

ou `split_clients "$remote_addr" $backend { 10% green; * blue; }` pour une
affectation stable par client.

::: pourquoi
La bascule est un `reload` de nginx après changement du **symlink**, donc
une opération atomique côté fichier (`ln -sfn` remplace le lien d'un coup)
et sans coupure côté réseau (les anciens workers finissent leurs
requêtes). Le retour arrière est la même opération dans l'autre sens :
c'est ce qui rend le rollback instantané et sans `docker compose`.
Le smoke test **avant** bascule est ce qui change tout par rapport à
L25.2 : on valide la version sur une instance qui ne reçoit pas de trafic.
La séparation en deux clés (`deploy`, `bg`) avec deux commandes forcées
tient les privilèges au plus juste : la clé `bg` est la seule à pouvoir
faire un `sudo`, et seulement les quatre commandes du fichier sudoers.
:::

::: piege
`steps.switch.outcome` distingue `success`, `failure`, `cancelled`,
`skipped` : sans cette condition, un échec **avant** `switch` déclencherait
un `back` qui basculerait vers la couleur non testée. Autre piège :
`readlink -f` sur le symlink donne le chemin résolu ; `basename … .conf`
donne `blue`/`green`. Si tu nommes les fichiers autrement, `live()` casse
en silence.
:::

---

### **L25.4** — *Pipeline d'infrastructure : Ansible et OpenTofu*

**1. Clé Ansible et premier `--check --diff`.**

Sur `lab-web`, pour `mathieu` :
`from="10.10.10.14" ssh-ed25519 AAAA… ansible@lab-ops` dans
`~/.ssh/authorized_keys`. Sur `lab-ops` :

```bash
cd ~/lab25/factura-infra/ansible
ansible-playbook -i inventory.ini site.yml --check --diff \
  --private-key ~/lab25/keys/ansible --ask-become-pass
```

Le playbook livré contient une tâche `ansible.builtin.command: nginx -t`
sans `changed_when` : `ansible-lint` (profil `production`) la rejette
(`no-changed-when`), et en `--check` la tâche est sautée sans rien dire.
Correctif :

```yaml
    - name: Vérifier la configuration nginx
      ansible.builtin.command: nginx -t
      changed_when: false
      check_mode: false
```

**2. Secrets** : `ANSIBLE_SSH_KEY` (clé privée `~/lab25/keys/ansible`),
`ANSIBLE_BECOME_PASS`, variable `LAB_WEB_HOSTKEY` — mêmes appels d'API
qu'en L25.2 sur `repos/mathieu/factura-infra`.

**3. `.gitea/workflows/ansible.yaml`.**

```yaml
name: ansible
on:
  push:
    branches: [main]
    paths: ["ansible/**"]
  pull_request:
    paths: ["ansible/**"]

jobs:
  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    container:
      image: python:3.12-slim
    steps:
      - uses: actions/checkout@v4
      - run: pip install -q ansible-core==2.17.* ansible-lint==24.* yamllint
      - run: yamllint -s ansible
      - run: ansible-lint --profile production ansible/site.yml

  check:
    needs: lint
    if: gitea.event_name == 'pull_request'
    runs-on: ubuntu-latest
    timeout-minutes: 15
    container:
      image: python:3.12-slim
    env:
      ANSIBLE_HOST_KEY_CHECKING: "true"
    steps:
      - uses: actions/checkout@v4
      - name: Outils et accès
        env:
          KEY: ${{ secrets.ANSIBLE_SSH_KEY }}
          HOSTKEY: ${{ vars.LAB_WEB_HOSTKEY }}
          BECOME: ${{ secrets.ANSIBLE_BECOME_PASS }}
        run: |
          apt-get update -q && apt-get install -y -q openssh-client
          pip install -q ansible-core==2.17.*
          mkdir -p /root/.ssh && chmod 700 /root/.ssh
          printf '%s\n' "$KEY" > /root/.ssh/ansible
          chmod 600 /root/.ssh/ansible
          printf '%s\n' "$HOSTKEY" > /root/.ssh/known_hosts
          printf 'ansible_become_password: "%s"\n' "$BECOME" > /root/become.yml
          chmod 600 /root/become.yml
      - name: Check + diff
        working-directory: ansible
        run: |
          ansible-playbook -i inventory.ini site.yml --check --diff \
            --private-key /root/.ssh/ansible -e @/root/become.yml
      - name: Nettoyage
        if: always()
        run: rm -f /root/become.yml /root/.ssh/ansible

  apply:
    needs: lint
    if: gitea.event_name == 'push' && gitea.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    timeout-minutes: 15
    concurrency:
      group: ansible-lab-web
      cancel-in-progress: false
    container:
      image: python:3.12-slim
    env:
      ANSIBLE_HOST_KEY_CHECKING: "true"
    steps:
      - uses: actions/checkout@v4
      - name: Outils et accès
        env:
          KEY: ${{ secrets.ANSIBLE_SSH_KEY }}
          HOSTKEY: ${{ vars.LAB_WEB_HOSTKEY }}
          BECOME: ${{ secrets.ANSIBLE_BECOME_PASS }}
        run: |
          apt-get update -q && apt-get install -y -q openssh-client
          pip install -q ansible-core==2.17.*
          mkdir -p /root/.ssh && chmod 700 /root/.ssh
          printf '%s\n' "$KEY" > /root/.ssh/ansible
          chmod 600 /root/.ssh/ansible
          printf '%s\n' "$HOSTKEY" > /root/.ssh/known_hosts
          printf 'ansible_become_password: "%s"\n' "$BECOME" > /root/become.yml
          chmod 600 /root/become.yml
      - name: Apply
        working-directory: ansible
        run: |
          ansible-playbook -i inventory.ini site.yml --diff \
            --private-key /root/.ssh/ansible -e @/root/become.yml
      - name: Nettoyage
        if: always()
        run: rm -f /root/become.yml /root/.ssh/ansible
```

**4.** PR modifiant `nginx_worker_connections: 1024` dans `site.yml` :
le journal de `check` montre le diff de `lineinfile` sur
`/etc/nginx/nginx.conf` (`-\tworker_connections 768;` /
`+\tworker_connections 1024;`) et `changed=1` en jaune. Après merge, `apply`
applique et le handler `Recharger nginx` tourne ; sur `lab-web` :
`grep worker_connections /etc/nginx/nginx.conf` et
`journalctl -u nginx --since -5min` montrent le reload.

**5. `.gitea/workflows/tofu.yaml`.**

```yaml
name: tofu
on:
  pull_request:
    paths: ["tofu/**"]
  push:
    branches: [main]
    paths: ["tofu/**"]
  workflow_dispatch:
    inputs:
      confirm:
        description: "Taper apply pour appliquer"
        required: true
        default: "non"

env:
  TF_IN_AUTOMATION: "1"
  STATE: /var/lib/act_runner/state/factura.tfstate

jobs:
  plan:
    runs-on: lab-shell
    timeout-minutes: 10
    defaults:
      run:
        working-directory: tofu
    steps:
      - uses: actions/checkout@v4
      - run: tofu fmt -check -diff
      - run: tofu init -input=false
      - run: tofu validate
      - name: Plan
        run: |
          mkdir -p "$(dirname "$STATE")"
          tofu plan -input=false -state="$STATE" -out=plan.bin
          tofu show -no-color plan.bin > plan.txt
      - uses: actions/upload-artifact@v4
        with:
          name: plan
          path: |
            tofu/plan.bin
            tofu/plan.txt

  apply:
    needs: plan
    if: >-
      gitea.event_name == 'workflow_dispatch' &&
      gitea.event.inputs.confirm == 'apply' &&
      gitea.actor == 'mathieu'
    runs-on: lab-shell
    timeout-minutes: 10
    concurrency:
      group: tofu-apply
      cancel-in-progress: false
    defaults:
      run:
        working-directory: tofu
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: plan
          path: tofu
      - run: tofu init -input=false
      - name: Apply du plan approuvé
        run: tofu apply -input=false -state="$STATE" plan.bin
```

Installation de `tofu` sur `lab-ops` pour le runner natif :

```bash
V=1.9.1
curl -fsSL -o /tmp/tofu.zip \
  "https://github.com/opentofu/opentofu/releases/download/v$V/\
tofu_${V}_linux_amd64.zip"
sudo unzip -o -d /usr/local/bin /tmp/tofu.zip tofu
sudo install -d -o runner -g runner /var/lib/act_runner/state
tofu version
```

`confirm: non` → le job `apply` est `skipped`, le run reste vert avec
`plan` seul.

**6.** Protection de `main` sur `factura-infra` avec
`status_check_contexts: ["ansible / lint", "tofu / plan"]`.

::: pourquoi
Le principe des deux workflows est identique : **en PR, on montre ; au
merge ou sur décision, on fait**. `--check --diff` et `plan` sont les
« preuves » que le relecteur lit ; `apply` réutilise exactement ce qui a
été montré (`plan.bin`, même playbook). Le mot de passe `become` passe par
un fichier de variables lu par Ansible, jamais par `-e
ansible_become_password=…` qui apparaîtrait dans `ps` et dans la trace.
Pour OpenTofu, `plan.bin` enregistre l'état lu : si l'état a changé entre
`plan` et `apply`, `apply` refuse (`Saved plan is stale`) — c'est la
garantie qu'on applique ce qui a été approuvé, et la raison de passer par
un artefact plutôt que de replanifier.

L'état sur le disque du runner est inacceptable au-delà du lab parce qu'il
n'est ni sauvegardé, ni verrouillé, ni partagé : deux runners = deux
états, un disque perdu = infrastructure orpheline. En production : backend
distant avec verrou (S3/MinIO + DynamoDB ou verrou natif, PostgreSQL,
Consul), et l'état ne transite jamais par un artefact lisible (il
contient des secrets en clair).
:::

::: piege
* `paths:` sur `push`/`pull_request` évite de lancer Ansible quand seul
  `tofu/` change, mais un PR qui touche les **deux** déclenche les deux
  workflows : c'est voulu.
* `ansible-lint --profile production` exige les FQCN
  (`ansible.builtin.apt`), un `name` sur chaque tâche, `changed_when` sur
  `command`/`shell`, et des permissions explicites sur `file`/`template`.
  Le playbook livré est conforme sauf la tâche piège.
* `gitea.event.inputs.confirm` : sur un `push`, `inputs` n'existe pas et
  l'expression vaut `''` : le job `apply` est sauté, pas en erreur.
:::

---

## 25.7 Break & Fix

### **BF25.1** — *« Le pipeline a disparu »*

*Depuis le commit « refacto ci », aucun run n'apparaît, ni sur push ni en
manuel ; le runner est Idle.*

**Diagnostic.**

1. L'onglet *Actions* du dépôt est vide pour ce commit : ce n'est pas un
   job en attente (il serait listé), c'est un run **jamais créé**. Gitea ne
   crée pas de run pour un workflow qu'il ne sait pas lire.
2. Où Gitea le dit : le bouton *Run workflow* n'énumère plus `ci` (la liste
   ne contient que les workflows parsés). Et dans le journal de Gitea :

```bash
cd ~/lab25/forge
docker compose logs --since 30m gitea | grep -iE 'workflow|yaml|actions' | tail
```

   on lit une ligne du type `...ci.yaml: yaml: line 12: did not find
   expected key` ou `mapping values are not allowed in this context`.

3. Confirmation locale, sans Gitea :

```bash
cd ~/lab25/factura
git show --stat HEAD
yamllint .gitea/workflows/ci.yaml
python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' \
  .gitea/workflows/ci.yaml
```

**Cause racine.** Le commit a « aligné » les jobs : `runs-on` et `steps` du
job `test` sont remontés au niveau de la clé `test`, et un step `- name:`
a perdu deux espaces. Le fichier n'est plus un document YAML valide ; il
n'y a aucun run parce qu'il n'y a plus de workflow.

**Correctif.** Réindenter (`runs-on`/`steps` sous `test`, les steps alignés
sous `steps:`), valider avec `yamllint -s`, commiter, pousser. Le run
réapparaît immédiatement.

**Prévention.** Un hook `pre-commit` local :

```bash
cat > .git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
set -e
git diff --cached --name-only --diff-filter=ACM | grep -E '\.ya?ml$' \
  | xargs -r yamllint -s
EOF
chmod +x .git/hooks/pre-commit
```

et, côté forge, un workflow minimal `lint-workflows.yaml` qui ne fait que
`yamllint .gitea/workflows/` — il ne protège pas contre un `ci.yaml`
invalide (il tournerait quand même, lui, et deviendrait rouge : c'est le
signal qu'on cherchait).

::: pourquoi
Le mécanisme : Gitea, à la réception d'un push, lit chaque fichier de
`.gitea/workflows/`, le parse, évalue `on:` et **seulement alors** crée un
run par workflow concerné. Un fichier illisible est écarté à la première
étape ; l'erreur va dans le journal du serveur, pas dans l'interface du
dépôt, parce qu'il n'existe aucun objet « run » auquel l'attacher. C'est
le cas d'école du « silence de l'automate » : l'absence de résultat est
le seul symptôme.
:::

---

### **BF25.2** — *« Ça tourne depuis 40 minutes »*

*`lint` et `test` verts, `build` en `waiting`, runner Idle.*

**Diagnostic.**

1. Le job est bien créé (il est listé) mais aucun runner ne le prend :
   `waiting` + runner `Idle` = **aucune correspondance de label**.
2. Comparer :

```bash
cd ~/lab25/factura && git show HEAD -- .gitea/workflows/ci.yaml | grep runs-on
grep -A3 'labels:' ~/lab25/forge/runner/config.yaml
cat ~/lab25/forge/runner/data/.runner | python3 -m json.tool | grep -A3 labels
```

   Le diff montre `runs-on: ubuntu-latest` → `runs-on: build-docker` pour
   le job `build` (« runner dédié build », mais ce runner n'existe pas).
   Le runner n'annonce que `ubuntu-latest` (et `lab-shell` si E25.13 est
   fait).

3. Bonus : `docker compose logs -f runner` pendant qu'on relance le job —
   rien n'apparaît. Le runner ne **voit** pas le job : Gitea ne lui propose
   que ce qui correspond à ses labels.

**Cause racine.** `runs-on` désigne un label que personne ne porte.

**Deux correctifs valables.**

* Côté workflow : revenir à `runs-on: ubuntu-latest`. Simple, immédiat ;
  à retenir si l'idée de « runner dédié » n'était pas une décision
  d'équipe.
* Côté runner : ajouter le label
  `build-docker:docker://docker.gitea.com/runner-images:ubuntu-latest`
  dans `runner.labels` de `config.yaml` (une ligne par label) et
  redémarrer le runner. À retenir si l'on veut effectivement séparer plus
  tard les jobs de build (sur un runner isolé, avec socket) des jobs de
  test (sans socket) : le label est alors une **intention** documentée.

Dans les deux cas, écrire la justification dans le commit ou dans
`forge.md`. Un label ajouté « pour que ça passe » sans décision est une
dette.

::: pourquoi
Un runner tire ses labels de `config.yaml` (`runner.labels`) s'ils y sont
définis, sinon de `.runner` (enregistrement initial). Il les envoie à
Gitea à chaque démarrage (`declare`). Gitea assigne un job à un runner si
**la valeur de `runs-on`** figure dans les labels de ce runner. Il n'y a
ni message d'erreur ni délai d'expiration : du point de vue de la forge,
un runner adéquat peut apparaître à tout moment. `timeout-minutes` ne
s'applique qu'à un job **démarré**.
:::

::: piege
Modifier `.runner` à la main ne suffit pas : c'est `config.yaml` qui prime
quand `runner.labels` y est non vide, et il faut redémarrer. Et si tu
enregistres un second runner avec le même nom, l'ancien reste listé
`Offline` dans l'administration : supprime-le, sinon tu liras de faux
labels.
:::

---

### **BF25.3** — *« Le mot de passe du registre est dans les logs »*

*Le secret apparaît en `***` mais l'auditeur a trouvé de quoi se
connecter.*

**Diagnostic.**

1. Ouvrir le journal du step incriminé (« debug push registre »). Les
   lignes avec `***` prouvent que le masquage fonctionne pour la chaîne
   exacte. Chercher ce qui **n'est pas** la chaîne exacte :

```bash
cd ~/lab25/factura
git show HEAD -- .gitea/workflows/ci.yaml
```

   Le commit ajoute dans le step `Login registre` :

```yaml
        run: |
          set -x
          auth=$(printf '%s:%s' "$REG_USER" "$REG_PASS" | base64 -w0)
          curl -v -H "Authorization: Basic $auth" \
            http://10.10.10.14:5000/v2/ -o /dev/null
          echo "$REG_PASS" | sed 's/./& /g'
```

2. Vecteur 1 : `set -x` + `base64`. La trace affiche
   `+ curl -v -H 'Authorization: Basic bWF0aGlldTpGYWN0dXJhLVJlZy0yMDI2'`
   — la valeur base64 n'est pas la chaîne du secret, elle n'est pas
   masquée ; `echo … | base64 -d` la restitue. `curl -v` répète le même
   en-tête dans `> Authorization: Basic …`.
3. Vecteur 2 : `sed 's/./& /g'` insère une espace entre chaque caractère :
   `F a c t u r a - R e g - 2 0 2 6`. Chaîne différente, non masquée,
   lisible à l'œil nu.

**Cause racine.** Deux transformations du secret avant impression :
encodage et espacement. Le masquage ne connaît que la chaîne exacte.

**Correctif.**

```yaml
      - name: Login registre
        env:
          REG_USER: ${{ vars.REGISTRY_USER }}
          REG_PASS: ${{ secrets.REGISTRY_PASSWORD }}
        run: printf '%s' "$REG_PASS" | docker login 10.10.10.14:5000 \
               -u "$REG_USER" --password-stdin
```

**Rotation** (le secret est considéré compromis : il est dans un journal
que d'autres ont pu lire) :

```bash
# côté registre (htpasswd bcrypt du registry:2 protégé, cf. setup)
NEW=$(openssl rand -base64 24)
htpasswd -Bbn mathieu "$NEW" > ~/lab25/forge/registry/auth/htpasswd
docker login 10.10.10.14:5000 -u mathieu --password-stdin <<<"$NEW"
docker compose -f ~/lab25/forge/compose.yaml restart registry
# côté Gitea
TOKEN=$(cat ~/lab25/.gitea-token)
API=http://10.10.10.14:3000/api/v1
curl -s -X PUT -H "Authorization: token $TOKEN" \
  -H 'Content-Type: application/json' -d "{\"data\":\"$NEW\"}" \
  "$API/repos/mathieu/factura/actions/secrets/REGISTRY_PASSWORD"
# côté lab-web : docker login avec la nouvelle valeur pour deploy
```

Puis supprimer les journaux du run (*Actions → run → Supprimer les
journaux*) **après** avoir noté la preuve.

**Deux règles de revue.** (1) Aucun `set -x`, `-v`, `--debug`, `-x` dans
un step qui a accès à un secret ; (2) un secret ne quitte jamais sa
variable : pas de `echo`, `printf`, `base64`, `sed`, `cut`, `jq` dessus,
même « pour vérifier ».

::: pourquoi
Le masquage est implémenté dans le runner comme un filtre de flux qui
remplace les valeurs connues (secrets, plus ce qui est déclaré par
`::add-mask::`) ; il est efficace contre l'oubli, impuissant contre la
transformation. `--password-stdin` de `docker login` existe pour cela : le
secret passe par un tube, jamais par la ligne de commande (visible dans
`ps` et dans la trace). La rotation n'est pas optionnelle : un secret vu
est un secret perdu, quelle que soit la probabilité qu'il ait été lu.
:::

---

### **BF25.4** — *« Le pipeline est vert, la prod est vieille »*

*Runs verts, `deploy` affiche Pulled/Started, mais `/version` renvoie un
SHA inconnu et la fonctionnalité n'est pas là.*

**Diagnostic — les trois identités.**

1. Ce qui tourne (`lab-web`) :

```bash
cd /srv/factura && cat .env
docker compose ps
docker image inspect --format '{{.Id}} {{.RepoDigests}} {{.Created}}' \
  10.10.10.14:5000/factura:latest
curl -s localhost:8080/version
```

   `.env` contient `TAG=latest` ; l'image a une date de création
   antérieure au commit ; `/version` donne un SHA qui, sur `lab-ops`,
   `git log --oneline | grep <sha>` ne trouve pas dans les 10 derniers.

2. Ce qui a été construit (`lab-ops`) :

```bash
curl -s -u mathieu:Factura-Reg-2026 http://10.10.10.14:5000/v2/factura/tags/list
for t in latest $(git -C ~/lab25/factura rev-parse --short=12 HEAD); do
  printf '%s ' "$t"; curl -sI -u mathieu:Factura-Reg-2026 \
   -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
   "http://10.10.10.14:5000/v2/factura/manifests/$t" | grep -i content-digest
done
```

   Le digest de `latest` ≠ digest du SHA courant. `latest` pointe sur une
   image plus ancienne, poussée par « quelqu'un » (le break le fait depuis
   `lab-ops`, comme le ferait un poste de dev).

3. Ce qui a été demandé : `git show HEAD -- .gitea/workflows/ci.yaml`.
   Trois changements :
   * `deploy` : `$SSH "deploy $TAG"` → `$SSH "deploy latest"` ;
   * `build` : le `docker push` ne pousse plus `latest` (le commit « a
     simplifié ») — donc rien ne réécrase le `latest` étranger ;
   * smoke test : `[ "$v" = "$TAG" ]` remplacé par un simple
     `curl -fsS …/health` : un 200 suffit, n'importe quelle version passe.

   Et `factura-deploy` acceptait `latest` parce que sa regex avait été
   élargie (`|latest`) dans le même mouvement.

**Cause racine.** Le déploiement désigne un **pointeur mobile** dont le
pipeline n'est plus le seul écrivain, et la vérification a été affaiblie
au point de ne plus rien prouver.

**Correctif.**

1. Rétablir `deploy $TAG` avec le SHA, la regex stricte de
   `factura-deploy`, le smoke test sur `/version` = `$TAG`.
2. Ne plus jamais pousser `latest` depuis le pipeline ; supprimer le tag
   du registre (`registry:2` : `DELETE /v2/factura/manifests/<digest>`
   avec `REGISTRY_STORAGE_DELETE_ENABLED=true`, puis garbage-collect) ou
   au minimum le documenter comme interdit.
3. Redéployer le SHA courant : `ssh … "deploy <sha12>"` via le pipeline
   (relance du run) et vérifier `/version`.

**Prévention.** Le smoke test est un test de **version**, pas de
disponibilité ; `factura-deploy` refuse tout tag non immuable ; une revue
de code refuse tout `latest` dans `deploy/`, `compose.yaml` et le
workflow. Optionnel : un job planifié qui compare chaque jour le digest en
prod au digest attendu du dernier commit de `main`.

::: pourquoi
Un tag est une entrée dans un index du registre : `tags/list` renvoie des
noms, `manifests/<tag>` renvoie **ce sur quoi le nom pointe aujourd'hui**.
`docker compose pull` demande le nom, reçoit le digest courant, compare
avec l'image locale et redémarre le conteneur si c'est différent : tout
fonctionne comme prévu, avec une mauvaise entrée. La panne est invisible
parce que les trois garde-fous (tag immuable, pipeline unique écrivain,
smoke test de version) ont été retirés **ensemble**, chacun paraissant
inutile tant que les deux autres tenaient.
:::

---

## 25.8 Défi du module

**D25** — *Chaîne de release : tag SemVer → promotion sans rebuild →
changelog → release → approbation → prod.*

**1. `release.yaml`, job `guard`.**

```yaml
name: release
on:
  push:
    tags: ["v*"]

env:
  IMAGE: 10.10.10.14:5000/factura
  REGISTRY: http://10.10.10.14:5000

jobs:
  guard:
    runs-on: ubuntu-latest
    outputs:
      sha12: ${{ steps.g.outputs.sha12 }}
      version: ${{ steps.g.outputs.version }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - id: g
        run: |
          v="$GITHUB_REF_NAME"
          [[ $v =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
            || { echo "tag '$v' non SemVer" >&2; exit 1; }
          git branch -r --contains "$GITHUB_SHA" | grep -qx ' *origin/main' \
            || { echo "le tag ne pointe pas sur main" >&2; exit 1; }
          echo "version=$v" >> "$GITHUB_OUTPUT"
          echo "sha12=${GITHUB_SHA::12}" >> "$GITHUB_OUTPUT"

  promote:
    needs: guard
    runs-on: ubuntu-latest
    env:
      SHA12: ${{ needs.guard.outputs.sha12 }}
      VERSION: ${{ needs.guard.outputs.version }}
      REG_AUTH: ${{ vars.REGISTRY_USER }}:${{ secrets.REGISTRY_PASSWORD }}
    steps:
      - name: Image du commit présente ?
        run: |
          code=$(curl -s -u "$REG_AUTH" -o /dev/null -w '%{http_code}' \
            -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
            "$REGISTRY/v2/factura/manifests/$SHA12")
          [ "$code" = 200 ] \
            || { echo "pas d'image factura:$SHA12 : ci a-t-il poussé ?" >&2
                 exit 1; }
      - name: Promotion sans pull (manifest copié par l'API)
        run: |
          ACCEPT='application/vnd.oci.image.manifest.v1+json'
          ACCEPT2='application/vnd.docker.distribution.manifest.v2+json'
          curl -fsS -u "$REG_AUTH" -H "Accept: $ACCEPT, $ACCEPT2" -D /tmp/h \
            "$REGISTRY/v2/factura/manifests/$SHA12" -o /tmp/manifest
          ct=$(grep -i '^content-type:' /tmp/h | tr -d '\r' | cut -d' ' -f2)
          for t in "$VERSION" "${VERSION%.*}"; do
            curl -fsS -u "$REG_AUTH" -X PUT -H "Content-Type: $ct" \
              --data-binary @/tmp/manifest \
              "$REGISTRY/v2/factura/manifests/$t"
          done
          curl -s -u "$REG_AUTH" "$REGISTRY/v2/factura/tags/list"
```

**3. Changelog** (`scripts/changelog.sh`) :

```bash
#!/usr/bin/env bash
# changelog.sh <version> — ajoute une section en tête de CHANGELOG.md
set -euo pipefail
v=${1:?version}
prev=$(git describe --tags --abbrev=0 "$v^" 2>/dev/null || true)
plage=${prev:+$prev..}$v
section() {                       # $1 titre, $2 regex de préfixe
  local lignes
  lignes=$(git log --no-merges --format='- %s (%h)' "$plage" \
             | grep -E "^- $2" | sed -E "s/^- $2:? ?/- /" || true)
  [ -n "$lignes" ] && printf '### %s\n%s\n\n' "$1" "$lignes"
}
{
  printf '## %s — %s\n\n' "$v" "$(date +%F)"
  section 'Nouveautés' 'feat'
  section 'Corrections' 'fix'
  section 'Autres' '[^f]|f[^ei]|fe[^a]|fi[^x]'
  [ -f CHANGELOG.md ] && cat CHANGELOG.md
} > CHANGELOG.new
mv CHANGELOG.new CHANGELOG.md
```

Commit par le pipeline **sans boucle** : le message commence par
`[skip ci]` — Gitea ignore les pushes dont le message contient `[skip
ci]`, `[ci skip]`, `[no ci]`, `[skip actions]` ou `[actions skip]`.

```yaml
  changelog:
    needs: [guard, promote]
    runs-on: ubuntu-latest
    env:
      VERSION: ${{ needs.guard.outputs.version }}
      GITEA_TOKEN: ${{ secrets.GITEA_TOKEN }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          ref: main
      - run: bash scripts/changelog.sh "$VERSION"
      - uses: actions/upload-artifact@v4
        with:
          name: changelog
          path: CHANGELOG.md
      - name: Commit sur main
        run: |
          git config user.name ci-bot
          git config user.email ci-bot@lab.local
          git add CHANGELOG.md
          git commit -m "[skip ci] changelog $VERSION"
          url="http://ci-bot:${GITEA_TOKEN}@10.10.10.14:3000"
          git push "$url/mathieu/factura.git" HEAD:main
```

Si `main` est protégée avec liste blanche, `ci-bot` (l'identité du jeton
automatique) doit y figurer, ou la protection doit autoriser les pushes
du jeton d'Actions.

**4. Release Gitea.**

```yaml
  release:
    needs: [guard, promote, changelog]
    runs-on: ubuntu-latest
    env:
      VERSION: ${{ needs.guard.outputs.version }}
      SHA12: ${{ needs.guard.outputs.sha12 }}
      GITEA_TOKEN: ${{ secrets.GITEA_TOKEN }}
      REG_AUTH: ${{ vars.REGISTRY_USER }}:${{ secrets.REGISTRY_PASSWORD }}
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: changelog
      - run: |
          digest=$(curl -sI -u "$REG_AUTH" \
            -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
            "$REGISTRY/v2/factura/manifests/$VERSION" \
            | grep -i docker-content-digest | tr -d '\r' | cut -d' ' -f2)
          corps=$(awk '/^## /{n++} n==1' CHANGELOG.md)
          python3 - "$VERSION" "$corps" "$digest" > /tmp/rel.json <<'EOF'
          import json, sys
          v, body, d = sys.argv[1:]
          print(json.dumps({"tag_name": v, "name": v,
            "body": body + "\n\nImage : factura@" + d}))
          EOF
          curl -fsS -X POST -H "Authorization: token $GITEA_TOKEN" \
            -H 'Content-Type: application/json' -d @/tmp/rel.json \
            http://10.10.10.14:3000/api/v1/repos/mathieu/factura/releases
```

**5. `deploy-prod` et `promote.yaml`.** Dans `release.yaml`, un dernier job
`stage` fait `$SSH "stage $VERSION"` + `$SSH smoke` (clé `bg`) et s'arrête :
la version est prête sur la couleur inactive. L'approbation est le
lancement manuel de `promote.yaml` :

```yaml
name: promote
on:
  workflow_dispatch:
    inputs:
      version:
        description: "vX.Y.Z déjà stagée"
        required: true
      confirm:
        description: "Taper switch"
        required: true

jobs:
  switch:
    if: gitea.event.inputs.confirm == 'switch' && gitea.actor == 'mathieu'
    runs-on: ubuntu-latest
    concurrency:
      group: deploy-lab-web
      cancel-in-progress: false
    env:
      VERSION: ${{ gitea.event.inputs.version }}
      SSH: ssh -i /root/.ssh/bg -o BatchMode=yes deploy@10.10.10.11
    steps:
      - name: Clé SSH
        env:
          KEY: ${{ secrets.BG_SSH_KEY }}
          HOSTKEY: ${{ vars.LAB_WEB_HOSTKEY }}
        run: |
          mkdir -p /root/.ssh && chmod 700 /root/.ssh
          printf '%s\n' "$KEY" > /root/.ssh/bg && chmod 600 /root/.ssh/bg
          printf '%s\n' "$HOSTKEY" > /root/.ssh/known_hosts
      - name: La couleur inactive porte bien la version
        run: |
          $SSH smoke >/dev/null
          $SSH status | grep -q "=$VERSION\$" \
            || { echo "$VERSION n'est pas stagée" >&2; exit 1; }
      - id: switch
        run: $SSH switch
      - name: Smoke live
        run: curl -fsS http://10.10.10.11/version
      - if: failure() && steps.switch.outcome == 'success'
        run: $SSH back
```

Note : `/version` renvoie le SHA injecté au build (`APP_VERSION`), pas le
tag `vX.Y.Z` — l'image a été promue, pas reconstruite. Le contrôle se fait
donc sur `.env` (`TAG_<COULEUR>=vX.Y.Z`) via `status`, et sur le SHA
attendu si tu le passes en second input. C'est un bon rappel : la version
sémantique est un **nom**, le SHA est l'**identité**.

**6. `scripts/release-check.sh`.**

```bash
#!/usr/bin/env bash
# release-check.sh vX.Y.Z — vérifie la cohérence d'une release factura
set -uo pipefail
v=${1:?version}; rc=0
REG=http://10.10.10.14:5000; API=http://10.10.10.14:3000/api/v1
TOKEN=$(cat ~/lab25/.gitea-token); DEPOT=~/lab25/factura
ok() { printf '  [ OK ] %s\n' "$1"; }
ko() { printf '  [FAIL] %s\n' "$1"; rc=1; }
dig() { curl -sI -u mathieu:Factura-Reg-2026 \
  -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
  "$REG/v2/factura/manifests/$1" | grep -i docker-content-digest \
  | tr -d '\r' | cut -d' ' -f2; }

git -C "$DEPOT" fetch -q --tags
sha=$(git -C "$DEPOT" rev-parse --short=12 "$v^{commit}" 2>/dev/null) \
  && ok "tag Git $v -> $sha" || ko "tag Git $v absent"
dv=$(dig "$v"); ds=$(dig "${sha:-x}")
[ -n "$dv" ] && ok "image taguée $v" || ko "pas d'image $v dans le registre"
[ -n "$dv" ] && [ "$dv" = "$ds" ] && ok "digest $v == digest $sha" \
  || ko "digest de $v différent de celui du SHA (rebuild ?)"
curl -sf -H "Authorization: token $TOKEN" \
  "$API/repos/mathieu/factura/releases/tags/$v" >/dev/null \
  && ok "release Gitea $v" || ko "release Gitea $v absente"
exit $rc
```

**7. Rapport.** Schéma attendu : `git push --tags` → `guard` → `promote`
(re-tag par manifest, 0 transfert) → `changelog` (commit `[skip ci]`) →
`release` → `stage` (couleur inactive) → **humain** → `promote.yaml`
(`switch`). Temps typique : 2 à 3 minutes jusqu'au stage, puis le délai
humain. Secrets : `BG_SSH_KEY` (dépôt `factura`, `lab-web` seulement,
commande forcée `factura-bg`), `GITEA_TOKEN` (automatique, portée dépôt,
durée du run), `DEPLOY_SSH_KEY` (plus utilisé par la release — à retirer
si L25.3 remplace L25.2). DORA : `dora.sh` sur `deploiements.log`
rapatrié de `lab-web`.

::: pourquoi
Le cœur du défi est la **promotion par manifest** : l'API OCI permet de
`GET` le manifest d'un tag et de le `PUT` sous un autre nom ; le registre
reconnaît les couches déjà présentes, rien n'est transféré, et le digest
est identique par construction — `release-check.sh` le vérifie. Tout le
reste (changelog, release, approbation) est de la traçabilité : rendre
lisible **ce qui** a été promu, **par qui**, **quand**. L'approbation par
`workflow_dispatch` est la seule forme native sur Gitea ; sa faiblesse
(rien ne garantit que ce qui est en stage est ce qui a été validé) est
compensée par le contrôle du `.env` avant `switch`.
:::

::: piege
* Sans `fetch-depth: 0`, `git describe` et `git branch --contains` ne
  voient qu'un commit : `guard` et `changelog` mentent.
* Le `PUT` du manifest échoue en `400 MANIFEST_INVALID` si le
  `Content-Type` renvoyé n'est pas repris tel quel — d'où la lecture de
  l'en-tête.
* `[skip ci]` doit être dans le message du **commit**, pas du tag.
* Un push de tag et le push du commit correspondant déclenchent deux runs
  (`ci` et `release`) ; `promote` exige que `ci` ait fini de pousser
  l'image du SHA — d'où le test d'existence et le message d'erreur
  explicite. En pratique : pousser le tag **après** le run `ci` vert.
:::
