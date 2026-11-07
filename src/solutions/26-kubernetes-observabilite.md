# Module 26 — Corrigé

## 26.3 Quiz — QCM

**Q26.1** — *Ce qui se passe réellement après `kubectl scale deploy factura-api --replicas=3`.*

**Réponse : b)**

::: pourquoi
`kubectl` ne « fait » rien : il envoie un `PATCH` sur l'objet Deployment à
l'API server, qui l'enregistre dans le datastore (SQLite via kine sur k3s,
etcd ailleurs). À partir de là, tout est asynchrone et découplé :

1. le **contrôleur de Deployment** (dans `kube-controller-manager`) observe que
   `spec.replicas` du Deployment vaut 3 et met à jour le ReplicaSet courant ;
2. le **contrôleur de ReplicaSet** compte 2 pods portant son sélecteur, en
   veut 3, crée un objet Pod avec `spec.nodeName` vide ;
3. le **scheduler** surveille les pods sans nœud, choisit un nœud (filtrage
   sur les `requests`, `nodeSelector`, taints ; puis score) et écrit
   `spec.nodeName` ;
4. le **kubelet** du nœud désigné voit un pod qui lui est affecté, demande à
   containerd de tirer l'image et démarrer le conteneur, puis remonte le
   `status`.

Chacun ne parle qu'à l'API server, et chacun ne lit que ce qui le concerne.
C'est le modèle déclaratif : tu écris l'état voulu, des boucles convergent.
:::

::: piege
a) et c) supposent un appel direct entre composants qui n'existe pas. d) est
faux deux fois : etcd ne notifie personne d'autre que l'API server, et le
kubelet n'a aucune notion de « pod manquant » — il ne connaît que les pods
qui lui sont assignés.
:::

---

**Q26.2** — *k3s mono-nœud : deux affirmations vraies.*

**Réponses : b) et c)**

::: pourquoi
k3s remplace etcd par **kine**, une couche de traduction qui présente l'API
etcd à l'API server au-dessus de SQLite (`/var/lib/rancher/k3s/server/db/`).
Avec `--cluster-init` ou `--datastore-endpoint`, on retrouve etcd embarqué,
MySQL ou PostgreSQL. Les *packaged components* (Traefik, CoreDNS,
metrics-server, ServiceLB, local-path-provisioner) sont déployés au démarrage
depuis `/var/lib/rancher/k3s/server/manifests/` : ce sont de vrais pods dans
`kube-system`, désactivables avec `--disable traefik` par exemple.
:::

::: piege
a) est faux : il n'y a pas d'etcd, et quand il y en a un, il tourne dans le
binaire `k3s`, pas dans un pod. d) : kube-proxy est bien présent (dans le
binaire), c'est Traefik qui remplace un *Ingress controller*, pas kube-proxy.
:::

---

**Q26.3** — *Raison de la sortie précédente d'un conteneur en `CrashLoopBackOff`.*

**Réponse : b)** `kubectl logs factura-api-7d9c8b5f4-x2k9p --previous`

::: pourquoi
En `CrashLoopBackOff`, le conteneur courant est soit en attente de
redémarrage (délai exponentiel 10 s, 20 s, 40 s… plafonné à 5 min), soit
vient de redémarrer et n'a pas encore reproduit l'erreur. `kubectl logs` sans
option lit le conteneur **courant** : souvent vide ou tronqué. `--previous`
(`-p`) lit la sortie standard du conteneur **précédent**, que le kubelet garde
sur le disque du nœud (`/var/log/pods/<ns>_<pod>_<uid>/<conteneur>/N.log`)
tant que le pod existe. C'est là que se trouve la ligne fatale.
:::

::: piege
c) `get events` montre `Back-off restarting failed container`, pas la cause
applicative. d) `top` donne la consommation instantanée, inutile sur un
conteneur mort. Réflexe complémentaire : `describe pod` → `Last State:
Terminated`, `Reason` et `Exit Code` (1 = erreur applicative, 137 = SIGKILL,
souvent OOM, 143 = SIGTERM).
:::

---

**Q26.4** — *`Last State: Terminated, Reason: OOMKilled, Exit Code: 137`.*

**Réponse : b)**

::: pourquoi
`limits.memory` se traduit en `memory.max` du cgroup du conteneur. Quand le
processus dépasse, le **noyau** (pas le kubelet, pas Kubernetes) déclenche
l'OOM killer dans ce cgroup et envoie `SIGKILL` : 128 + 9 = **137**. Le
kubelet constate la mort, lit la raison dans containerd (`OOMKilled`), et
redémarre selon `restartPolicy`. Deux remèdes : monter la limite après avoir
mesuré le besoin réel (`kubectl top pod --containers` sur un pod sain, ou
`container_memory_working_set_bytes` dans Prometheus), ou corriger la fuite.
:::

::: piege
c) décrit une **éviction** par le kubelet sous pression mémoire du nœud :
`Reason: Evicted` dans `describe`, pas `OOMKilled`, et le pod est recréé
ailleurs. d) : `requests` sert au scheduler, jamais au noyau ; l'augmenter ne
change rien à l'OOM. a) : un échec de liveness produit `Reason: Error` ou
`Completed` et l'événement `Liveness probe failed`, avec un code 143 si l'app
gère `SIGTERM`.
:::

---

**Q26.5** — *ClusterIP présente, Endpoints `<none>`, pods `Running 1/1`.*

**Réponse : b)**

::: pourquoi
Les Endpoints (et EndpointSlices) sont calculés par le contrôleur d'endpoints
à partir de **deux** conditions : les pods dont les labels satisfont
`spec.selector` du Service, **et** qui sont `Ready`. Les pods sont `1/1`,
donc prêts : il ne reste que le sélecteur. Vérification en deux commandes :

```bash
kubectl get svc factura-api -n factura -o jsonpath='{.spec.selector}'
kubectl get pods -n factura --show-labels
```

Un `targetPort` faux (a) donnerait des Endpoints **présents** avec un mauvais
port : `curl` répondrait *connection refused*, pas `<none>`.
:::

---

**Q26.6** — *Même Service, pods `Running 0/1` : deux réponses.*

**Réponses : a) et c)**

::: pourquoi
`READY 0/1` = conteneur démarré mais readiness en échec. Conséquence exacte :
le pod est retiré des Endpoints (il ne reçoit plus de trafic) mais **n'est
pas redémarré**. `describe` montre l'événement `Readiness probe failed: HTTP
probe failed with statuscode: 503` (ou `connection refused`, `context
deadline exceeded`). Sur `factura-api`, `/pret` répond 503 tant que
PostgreSQL n'est pas joignable : le 0/1 est donc un **symptôme de dépendance**,
pas un bug de l'API.
:::

::: piege
b) : c'est la liveness qui redémarre, et `RESTARTS` resterait à 0 ici. d) :
un pod en attente de scheduling est `Pending`, pas `Running`.
:::

---

**Q26.7** — *Secret avec `POSTGRES_PASSWORD: bGFicGFzcw==`.*

**Réponse : b)**

::: pourquoi
`data` d'un Secret est du base64 pour transporter des octets arbitraires en
JSON, rien d'autre. `kubectl get secret postgres-auth -o
jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d` donne `labpass`. Ce qui
protège un Secret, c'est le **RBAC** (verbe `get` sur `secrets`), pas
l'encodage. Le chiffrement au repos dans etcd est **optionnel**
(`EncryptionConfiguration` sur l'API server ; sur k3s `--secrets-encryption`).
Par défaut, rien n'est chiffré.
:::

::: piege
Le vrai piège de production : `kubectl get secret -o yaml` dans un ticket, un
`describe pod` qui montre les `env` en clair, ou un dépôt Git avec le Secret
en base64 « parce que ça ressemble à du chiffré ». Solutions : `stringData` +
+ SOPS/sealed-secrets/external-secrets en GitOps.
:::

---

**Q26.8** — *`nslookup postgres` en NXDOMAIN depuis le namespace `casse`.*

**Réponse : a)** `postgres.factura`

::: pourquoi
Le `resolv.conf` d'un pod de `casse` contient `search casse.svc.cluster.local
svc.cluster.local cluster.local` et `ndots:5`. `postgres` (0 point) est
essayé comme `postgres.casse.svc.cluster.local` → NXDOMAIN, puis
`postgres.svc.cluster.local` → NXDOMAIN, etc. `postgres.factura` (1 point,
< 5) parcourt aussi la liste : `postgres.factura.svc.cluster.local` existe.
Le nom complet `postgres.factura.svc.cluster.local` marche aussi et évite les
allers-retours DNS.
:::

::: piege
c) inverse service et namespace ; le schéma est toujours
`<service>.<namespace>.svc.<domaine>`. d) : `kube-system` héberge CoreDNS,
pas le Service `postgres`.
:::

---

**Q26.9** — *Rolling update avec une readiness qui ne passe jamais.*

**Réponse : b)**

::: pourquoi
Défauts d'un `RollingUpdate` : `maxSurge: 25 %` et `maxUnavailable: 25 %`,
arrondis respectivement vers le haut et vers le bas. Sur 2 réplicas :
`maxSurge` = 1 (on peut monter à 3 pods), `maxUnavailable` = 0 (on ne peut
jamais descendre sous 2 prêts). Le contrôleur crée donc **un** nouveau pod,
attend qu'il soit `Ready` pour tuer un ancien… et attend indéfiniment. Les
deux anciens continuent de servir. Après `progressDeadlineSeconds` (600 s par
défaut) le Deployment est marqué `Progressing=False`,
`reason: ProgressDeadlineExceeded`, mais **rien ne revient en arrière tout
seul** : c'est à toi de faire `kubectl rollout undo`.
:::

::: piege
d) : un pod dont la readiness échoue est `Running 0/1`, pas
`CrashLoopBackOff` — sauf si la liveness échoue aussi. Le piège de production
est `maxUnavailable: 1` sur 1 réplica : là, oui, le service est coupé.
:::

---

**Q26.10** — *`404 page not found` de Traefik sur `/api/factures`.*

**Réponse : b)**

::: pourquoi
Le corps `404 page not found` en texte brut est la signature de Traefik
lui-même (Go, `http.NotFound`) : aucune route n'a matché, la requête n'est
jamais partie vers un backend. Il faut donc regarder ce qui fait le routage :
`kubectl get ingress -A` (le `HOSTS` doit contenir `factura.lab.local`),
`kubectl describe ingress factura -n factura` (les règles `host`/`path`, le
`pathType`), et l'en-tête `Host` réellement envoyé par `curl`. Un 404 en JSON
`{"erreur":"route inconnue"}` viendrait, lui, de l'application : la route a
matché, c'est le chemin transmis qui est faux.
:::

---

**Q26.11** — *`qosClass: Burstable`.*

**Réponse : c)**

::: pourquoi
Trois classes, calculées par l'API server à la création du pod :
`Guaranteed` si chaque conteneur a `requests == limits` pour CPU **et**
mémoire ; `BestEffort` si aucun conteneur n'a rien ; `Burstable` pour tout le
reste. Sous pression mémoire, le kubelet évince d'abord les `BestEffort`,
puis les `Burstable` qui dépassent le plus leurs `requests`, et les
`Guaranteed` en dernier (`oom_score_adj` respectivement 1000, entre 2 et 999,
−997). Sur `factura-api`, `requests.memory: 64Mi` et `limits.memory: 128Mi`
→ `Burstable`, ce qui est un choix raisonnable pour une API.
:::

---

**Q26.12** — *`rate` contre `increase` sur 5 min : deux réponses.*

**Réponses : a) et b)**

::: pourquoi
`increase(c[5m])` est littéralement `rate(c[5m]) × 300`. Les deux
extrapolent aux bornes de la fenêtre, d'où des `increase` non entiers sur un
counter entier : c'est normal. Les deux gèrent les *resets* (redémarrage →
counter à 0) en ne comptant que les montées. `rate` s'exprime **par
seconde**, `increase` en nombre d'événements sur la fenêtre.
:::

::: piege
c) : les deux exigent un counter ; sur une gauge le résultat est absurde
(les baisses sont prises pour des resets). d) : `irate` ne regarde que les 2
derniers points, une alerte dessus bat au moindre pic et `for:` n'y change
rien parce qu'une seule évaluation basse remet le compteur à zéro. En
alerte : `rate`, fenêtre ≥ 4 × `scrape_interval`.
:::

---

**Q26.13** — *p95 correct depuis l'histogramme, toutes routes confondues.*

**Réponse : b)**

::: pourquoi
Un histogramme Prometheus est une famille de counters `_bucket{le="x"}`
cumulatifs. `histogram_quantile` a besoin de **taux** (sinon on calcule le
quantile depuis le démarrage du process) et d'une agrégation qui **conserve
`le`** : `sum by (le)`. Pour ventiler par route on garderait aussi `path`
(`sum by (le, path)`). Le p95 est interpolé linéairement dans le bucket qui
contient le 95e centile : la précision dépend des bornes (`0.25`, `0.5`,
`1.0` sur cette API).
:::

::: piege
a) : sans `rate`, résultat cumulé depuis le début. c) : `quantile` est un
agrégateur sur des séries instantanées, pas sur une distribution. d) est la
**latence moyenne**, utile mais ce n'est pas un p95 ; une moyenne cache les
queues de distribution qui font justement mal aux utilisateurs.
:::

---

**Q26.14** — *`InstanceDown`, `for: 2m`, à `t+60s`.*

**Réponse : b)**

::: pourquoi
Cycle de vie d'une règle : à chaque `evaluation_interval` (15 s), Prometheus
évalue `expr`. Première évaluation vraie → état **pending**, horodaté. Elle
reste pending tant que l'expression est vraie et que `for` n'est pas écoulé ;
au premier `t + for` → **firing**, et c'est **seulement à ce moment** que
l'alerte est envoyée à Alertmanager (puis renvoyée à chaque évaluation tant
qu'elle est active). Si une seule évaluation est fausse pendant la période,
l'alerte repasse en inactive et le chronomètre repart de zéro.
:::

::: piege
c) confond les deux composants : `group_wait` est un délai d'Alertmanager,
qui ne commence qu'à réception d'une alerte firing. Le temps total avant
notification est donc `for` + `group_wait` ≈ 2 min 30 s ici, plus jusqu'à un
`evaluation_interval` d'imprécision.
:::

---

**Q26.15** — *Le bloc `inhibit_rules`.*

**Réponse : b)**

::: pourquoi
L'inhibition supprime la **notification**, pas l'alerte : elle reste dans
l'UI avec l'état *inhibited* et disparaît normalement à la résolution. Le
critère `equal: ['instance']` exige que les deux alertes portent la même
valeur d'`instance` : un `CpuEleve` sur lab-db n'est pas inhibé par un
`InstanceDown` sur lab-rhel. Utilité : quand une machine est injoignable,
toutes ses alertes de second niveau (disque, mémoire, sonde) sont du bruit ;
on ne veut qu'une page.
:::

::: piege
Un `equal` sur un label absent des deux côtés est considéré comme égal
(vide = vide) : une règle d'inhibition sans `equal` ou avec un label mal
orthographié peut faire taire **toutes** les alertes `ticket` du cluster dès
qu'une machine tombe. Toujours tester avec `amtool alert query` et un
`amtool check-config`.
:::

---

**Q26.16** — *SLO 99,9 % sur 30 jours, 30 min d'indisponibilité en 10 jours.*

**Réponse : b)**

::: pourquoi
Budget : `(1 − 0,999) × 30 j × 24 h × 60 min = 0,001 × 43 200 = 43,2 min`.
Consommé : 30 min, il reste **13,2 min** pour les 20 jours restants. Burn
rate = part du budget consommée / part de la fenêtre écoulée =
`(30 / 43,2) / (10 / 30) = 0,694 / 0,333 ≈ 2,08`. À ce rythme, le budget est
vide au jour `30 / 2,08 ≈ 14,4`, bien avant la fin de la fenêtre. Le SLO
n'est pas encore violé (a est faux), mais l'équipe doit ralentir les mises en
production ou investir en fiabilité **maintenant**.
:::

::: piege
c) : 70 % du budget restant serait vrai si on avait consommé 13 min, pas 30.
d) : on ne sait rien du SLA, contrat distinct et plus lâche que le SLO.
:::

---

**Q26.17** — *Ce qu'indexe Loki.*

**Réponse : b)**

::: pourquoi
Un flux Loki = un jeu de labels ; les lignes sont compressées en *chunks*
sans index de contenu. Une requête sélectionne d'abord des flux par labels
(rapide, via l'index TSDB), puis **parcourt** les chunks pour appliquer `|=`,
`|~`, `| logfmt`… Coût proportionnel au volume lu, d'où l'importance de
limiter la fenêtre et de bien choisir les labels de sélection. Un label à
forte cardinalité (`request_id`, `pod` renouvelé à chaque déploiement…)
crée des milliers de petits flux : index énorme, chunks minuscules, requêtes
lentes.
:::

::: piege
d) : les champs `logfmt` sont extraits **à la requête** (`| logfmt`), ils ne
sont pas des labels. On peut en promouvoir un en label dans le pipeline
Alloy (`stage.labels`), mais uniquement si sa cardinalité est faible
(`niveau`, `code` HTTP).
:::

---

**Q26.18** — *L'alerte qui mérite une page de nuit.*

**Réponse : b)**

::: pourquoi
Une page se justifie par trois critères simultanés : **impact utilisateur**
avéré, **urgence** (ça ne peut pas attendre le matin) et **action possible**.
b) coche les trois : 5 % de 5xx et une sonde externe en échec, c'est le site
indisponible pour de vrais clients. a), c), d) sont des **causes** ou des
tendances sans impact immédiat ; elles vont dans un ticket traité en journée.
Le disque de lab-adm à 70 % ou un CPU à 80 % n'ont jamais réveillé un client.
:::

::: piege
Le réflexe fautif classique : paginer sur tout « pour ne rien rater ».
Résultat, 40 pages par nuit, l'astreinte les ignore, et la seule vraie est
noyée (QO26.10).
:::

---

## 26.4 Quiz — questions ouvertes

**QO26.1** — *De `kubectl apply -f deployment.yaml` au conteneur qui répond.*

**Réponse attendue :**

1. **`kubectl`** lit le fichier, calcule un *three-way merge* entre le
   fichier, l'annotation `last-applied-configuration` et l'objet vivant, et
   envoie un `PATCH` (ou `POST` si l'objet n'existe pas) à
   **kube-apiserver** en HTTPS, authentifié par le kubeconfig.
2. **kube-apiserver** authentifie, autorise (RBAC), passe les *admission
   controllers* (quotas, `LimitRange`, webhooks), valide le schéma, puis écrit
   l'objet Deployment dans **etcd** (kine/SQLite sur k3s). L'état — désiré
   *et* observé — vit uniquement là. Il répond `200` : `apply` est terminé,
   rien ne tourne encore.
3. Le **contrôleur de Deployment** (kube-controller-manager) est en `watch`
   sur les Deployments ; il crée ou met à jour un **ReplicaSet** (écriture via
   l'API). Le **contrôleur de ReplicaSet** voit N pods désirés, 0 existants, et
   crée N objets **Pod** sans `nodeName`.
4. Le **scheduler** surveille les pods sans nœud, filtre les nœuds possibles
   (ressources, taints, `nodeSelector`, affinités), les note, et écrit un
   *Binding* (`spec.nodeName`).
5. Le **kubelet** du nœud, en `watch` sur ses pods, appelle le runtime via
   **CRI** (containerd) : pull de l'image (avec `imagePullSecrets`), création
   du *sandbox* (le CNI flannel attribue l'IP), démarrage des conteneurs,
   lancement des probes. Il écrit `status` (phase, conditions, IP).
6. En parallèle, le **contrôleur d'Endpoints** ajoute l'IP du pod aux
   EndpointSlices du Service dès que la readiness passe, **kube-proxy** met à
   jour iptables/ipvs sur chaque nœud, et **CoreDNS** sert déjà le nom du
   Service. Le conteneur répond.

**Modèle déclaratif** : tu décris l'état voulu, jamais les actions. Chaque
contrôleur compare en boucle l'état observé à l'état désiré et agit sur
l'écart — c'est la réconciliation. Exemple sans humain : un nœud tombe, le
contrôleur de nœud le marque `NotReady` et lui pose la taint `node.kubernetes.io/not-ready`, après les 300 s de `tolerationSeconds` posées par défaut sur chaque pod,
ses pods sont marqués pour suppression, le ReplicaSet en manque N, il les
recrée, le scheduler les place ailleurs. Personne n'a tapé de commande.

::: pourquoi
Ce qui distingue une bonne réponse d'entretien : dire que **`kubectl apply`
rend la main avant que quoi que ce soit ne tourne**, que **tous les
composants ne parlent qu'à l'API server** (jamais entre eux, jamais à etcd),
et que chaque étape est un `watch` — pas un appel. C'est aussi pourquoi
`kubectl apply` puis `kubectl get pods` immédiat montre souvent
`ContainerCreating` : les boucles n'ont pas encore convergé.
:::

---

**QO26.2** — *Liveness, readiness, startup.*

**Réponse attendue :**

| Probe | Échec → | Question posée |
|---|---|---|
| liveness | restart du conteneur (après `failureThreshold`) | « Es-tu bloqué ? » |
| readiness | retrait des Endpoints, pas de restart | « Peux-tu servir ? » |
| startup | bloque les deux autres ; échec → restart | « As-tu fini de démarrer ? » |

Mauvais usage typique : une **liveness qui teste la base de données**
(`/pret` de factura-api en liveness). Si PostgreSQL tombe, tous les pods de
l'API échouent leur liveness, sont redémarrés en boucle, passent en
`CrashLoopBackOff`, et quand la base revient, plus aucun pod n'est là pour
répondre : on a transformé une panne partielle (503 propres) en panne totale
avec tempête de redémarrages. Règle : la liveness ne teste que le processus
lui-même (`/sante` répond = l'event loop tourne) ; la readiness teste les
dépendances.

Une readiness qui échoue est une **bonne nouvelle** quand c'est elle qui
retire proprement du trafic un pod qui ne peut pas servir : pendant un
rolling update (le nouveau pod ne reçoit rien tant qu'il n'est pas prêt),
pendant une reconnexion à la base, ou quand une instance est saturée — les
requêtes vont aux autres réplicas au lieu d'échouer.

::: pourquoi
Le paramètre le plus mal réglé est `initialDelaySeconds` sur la liveness
d'une application lente à démarrer (JVM) : le kubelet tue le conteneur avant
la fin du démarrage, ad vitam. C'est exactement ce que corrige la startup
probe (`failureThreshold: 30, periodSeconds: 10` = 5 min de tolérance), sans
retarder la liveness une fois le démarrage passé.
:::

---

**QO26.3** — *Pod `Pending` depuis 10 minutes : la méthode.*

**Réponse attendue :**

```bash
kubectl get pod NOM -n NS -o wide             # nœud vide ? phase ?
kubectl describe pod NOM -n NS                # section Events, en bas
kubectl get events -n NS --sort-by=.lastTimestamp | tail -20
```

Ce que l'on cherche dans `describe` → `Events`, par cause :

1. **Ressources insuffisantes** : `0/1 nodes are available: 1 Insufficient
   cpu` (ou `memory`). Vérifier `kubectl describe node | grep -A8
   "Allocated resources"` et les `requests` du pod ; réduire les requests ou
   libérer le nœud.
2. **`nodeSelector` / affinité / taints** : `1 node(s) didn't match Pod's
   node affinity/selector` ou `1 node(s) had untolerated taint
   {node.kubernetes.io/unschedulable: }`. Comparer `kubectl get nodes
   --show-labels` et `kubectl describe node | grep Taints` avec le manifeste
   (`nodeSelector`, `tolerations`). Un nœud `cordon` porte cette taint.
3. **PVC non lié** : `pod has unbound immediate PersistentVolumeClaims`.
   `kubectl get pvc -n NS` → `Pending` ; `describe pvc` → StorageClass
   inexistante ou provisioner absent. Sur k3s, `local-path` est
   `WaitForFirstConsumer` : le PVC reste `Pending` **jusqu'au** scheduling du
   pod, c'est normal.
4. **`ResourceQuota` dépassé** : ce n'est **pas** dans les événements du pod,
   parce que le pod n'est jamais créé. Le refus est dans les événements du
   **ReplicaSet** : `kubectl describe rs` → `Error creating: pods "x" is
   forbidden: exceeded quota: ...`. Et `kubectl describe quota -n NS` montre
   `Used` contre `Hard`. Le Deployment affiche `READY 3/5`, pas de pod
   `Pending` du tout.
5. **Nœud `NotReady`** : `kubectl get nodes` ; `describe node` → Conditions
   (`MemoryPressure`, `DiskPressure`, `PIDPressure`, `Ready=False` avec le
   message du kubelet) ; sur le nœud, `journalctl -u k3s -n 100`.

Le scheduler ne rapporte que la **première** raison qui filtre le nœud :
corriger une cause peut en révéler une autre (L26.3, `gourmand`).

::: pourquoi
La distinction entre « pod `Pending` » (créé, pas placé : scheduler) et « pod
jamais créé » (admission refusée : quota, LimitRange, webhook) est ce qui
sépare le diagnostic rapide du diagnostic à tâtons. Le premier se lit dans
`describe pod`, le second dans `describe rs`/`describe deploy` et
`get events`.
:::

---

**QO26.4** — *Deployment ou StatefulSet pour PostgreSQL ? Pourquoi un Service headless ?*

**Réponse attendue :**

StatefulSet. Ce qu'il apporte et qu'un Deployment n'a pas :

* **Identité stable** : les pods s'appellent `postgres-0`, `postgres-1`… et
  gardent ce nom à travers les redémarrages et les replanifications.
* **`volumeClaimTemplates`** : un PVC **par pod**, nommé
  `donnees-postgres-0`, qui suit le pod ; supprimer le pod ne supprime pas le
  PVC, et `postgres-0` recréé retrouve **ses** données.
* **Ordre** : création `0` puis `1` (chacun `Ready` avant le suivant),
  suppression en ordre inverse, mise à jour en ordre inverse (`partition`
  permet un canary). Indispensable pour une réplication primaire/secondaire.
* **DNS par pod** via le Service headless (`clusterIP: None`) :
  `postgres-0.postgres.factura.svc.cluster.local`. Un Service normal ne donne
  qu'une VIP qui répartit : impossible de désigner « le primaire ».

Ce qu'un Deployment + PVC ferait de mal en rolling update : avec
`maxSurge: 1`, le nouveau pod démarre **pendant** que l'ancien tourne, les
deux montent le même PVC (`ReadWriteOnce` sur `local-path` : même nœud, donc
le montage passe), et deux instances de PostgreSQL ouvrent le même `PGDATA` :
corruption ou refus de démarrer (`lock file postmaster.pid already exists`).
Avec 2 réplicas, ils partageraient carrément le PVC. Le contournement
`strategy: Recreate` coupe le service à chaque mise à jour — le StatefulSet
fait mieux.

::: pourquoi
Réponse d'entretien complète = **« identité + stockage + ordre »**, et le
Service headless expliqué par « les clients doivent parler à *un* pod
précis, pas à la VIP ». Ajouter que le StatefulSet ne gère **pas** la
réplication PostgreSQL elle-même : c'est le rôle d'un operator (CloudNativePG,
Zalando) ou de scripts d'init, et que sur un mono-nœud k3s la vraie
sauvegarde reste `pg_dump` (E26.7).
:::

---

**QO26.5** — *GitOps, operators, service mesh, managé vs auto-hébergé.*

**Réponse attendue :**

* **GitOps** : l'état désiré du cluster est un dépôt Git ; un agent dans le
  cluster tire les manifestes et réconcilie en continu, au lieu que la CI
  pousse avec `kubectl apply`. Outil : **ArgoCD** (ou Flux). Résout : la
  dérive (*drift*) entre ce qui est déployé et ce qui est versionné,
  l'audit (qui a changé quoi = `git log`), le rollback (`git revert`), et le
  fait de ne plus distribuer de kubeconfig admin à la CI.
* **Operator** : un contrôleur maison qui réconcilie une ressource
  personnalisée (CRD) représentant un logiciel complexe, avec le savoir-faire
  d'exploitation codé dedans (sauvegardes, bascule, mise à jour). Outil :
  **CloudNativePG** pour PostgreSQL, **Prometheus Operator**. Résout : « je
  veux un PostgreSQL HA en écrivant `kind: Cluster, instances: 3` », sans
  scripter la réplication.
* **Service mesh** : un proxy (sidecar ou ambient) devant chaque pod qui
  prend en charge mTLS, retries, timeouts, routage canari et télémétrie
  uniformes, sans toucher au code. Outil : **Istio**, **Linkerd**. Résout :
  la sécurité et l'observabilité entre services quand on en a des dizaines et
  plusieurs langages.
* **Managé vs auto-hébergé** : managé (EKS, GKE, AKS) = le fournisseur opère
  le control plane, les mises à jour, etcd, la HA ; auto-hébergé (k3s,
  kubeadm, RKE2) = tu fais tout, mais tu maîtrises le coût, le réseau et
  l'emplacement des données. Résout, côté managé : le temps d'exploitation ;
  côté auto-hébergé : la souveraineté et la facture.

**Position pour 4 personnes et 10 applications** : un cluster **managé** si
le cloud est déjà là, sinon **k3s/RKE2** en HA sur trois nœuds (simple à
opérer) ; **GitOps dès le premier jour** (ArgoCD coûte un après-midi et
évite 90 % des « qui a modifié ça ? ») ; **un ou deux operators** seulement
là où ça remplace du savoir-faire absent (base de données, certificats via
cert-manager) ; **pas de service mesh** — à 10 applications, un Ingress +
NetworkPolicies + TLS terminé au bord suffisent, et un mesh ajouterait un
système distribué de plus à comprendre à 3 h du matin.

::: pourquoi
Ce qu'on évalue : la capacité à dire **non** à une technologie. Une équipe
de 4 a une capacité d'exploitation limitée ; chaque brique doit rembourser
son coût cognitif. Le mesh est le cas d'école de l'outil adopté trop tôt.
:::

---

**QO26.6** — *SLI, SLO, SLA, budget d'erreur ; pourquoi alerter sur le burn rate.*

**Réponse attendue :**

* **SLI** : un ratio mesuré. Pour `factura-api` : part des requêtes hors 5xx
  = `1 − sum(rate(factura_http_requests_total{code=~"5.."}[30d])) /
  sum(rate(factura_http_requests_total[30d]))`.
* **SLO** : objectif interne : 99,5 % sur 30 jours glissants.
* **SLA** : le contrat signé avec le client, avec pénalités, toujours plus
  lâche : 99 % mensuel, avoir de 10 % en cas de manquement.
* **Budget d'erreur** : `1 − SLO = 0,5 %`. Sur 2 millions de requêtes par
  mois, **10 000 requêtes** peuvent échouer ; en temps, `0,005 × 43 200 min =
  216 min` d'indisponibilité totale.

**Pourquoi le burn rate** : un seuil fixe (« taux d'erreur > 1 % ») ne dit
ni depuis quand, ni si c'est grave. 1 % pendant 5 min consomme 0,02 % du
budget mensuel — on ne réveille personne pour ça ; 1 % pendant 3 jours en
consomme 20 %. Le burn rate = taux d'erreur observé / taux d'erreur autorisé
`(1 − SLO)` rapporte tout au budget : burn rate 1 = on épuise exactement le
budget en 30 jours ; burn rate 14,4 = on l'épuise en 2 jours ; 6 = en 5
jours.

**Multi-fenêtre, multi-burn-rate** (Google SRE Workbook) : on page si
`burn rate > 14,4` sur **1 h** *et* sur **5 min** (la fenêtre longue prouve
que ce n'est pas un pic, la courte prouve que c'est encore en cours, donc
l'alerte se résout vite) ; on ouvre un ticket si `burn rate > 6` sur **6 h**
*et* **30 min**. Les seuils viennent de : 14,4 × 1 h = 2 % du budget
consommé en 1 heure ; 6 × 6 h = 5 % du budget en 6 heures.

::: pourquoi
La valeur de cette approche : **une seule alerte de page** pour toute la
disponibilité du service, dont la sensibilité s'adapte au volume — un petit
taux d'erreur longtemps et un gros taux brièvement déclenchent tous deux
parce qu'ils coûtent la même chose au budget. Et le budget devient un
**outil de décision produit** : budget restant → on livre ; budget brûlé →
gel des mises en production, on travaille la fiabilité.
:::

---

**QO26.7** — *Pourquoi `rate()`, les resets, la fenêtre trop courte, `sum(rate())`.*

**Réponse attendue :**

Une soustraction de deux valeurs (`c − c offset 5m`) donne un résultat
**négatif** et faux dès que le service a redémarré entre les deux : le
counter est reparti de 0. `rate()` parcourt tous les échantillons de la
fenêtre, détecte chaque baisse comme un *reset*, additionne uniquement les
montées, puis extrapole aux bornes de la fenêtre et divise par la durée. Si
le service redémarre, on perd au plus les incréments entre le dernier scrape
avant et le redémarrage — pas le signe du résultat.

`[1m]` avec un scrape à 15 s laisse au mieux 4 échantillons, souvent 3 (les
scrapes ne tombent pas pile), et **un seul** au moindre scrape raté :
`rate` a besoin d'au moins 2 points, sinon la série disparaît (« no data »),
et avec 2 ou 3 points le bruit est énorme. Règle : fenêtre ≥ 4 × intervalle,
soit `[1m]` minimum pour 15 s et plus confortablement `[5m]`.

`sum(rate(c[5m]))` calcule un taux **par série** (donc par process, avec ses
propres resets), puis additionne : correct. `rate(sum(c)[5m])` additionne
d'abord des counters de process différents : quand un seul redémarre, la
somme baisse, `rate` croit à un reset global et compte une montée fictive
égale à toute la somme. Faux, et d'ailleurs syntaxiquement refusé sans une
sous-requête (`[5m:]`) — ce qui devrait alerter.

::: pourquoi
Le mot-clé d'entretien : `rate()` est **la seule** fonction correcte sur un
counter, toujours **à l'intérieur** de l'agrégation. `irate()` pour un
graphe à haute résolution, jamais en alerte. `increase()` pour un total
lisible par un humain (« 340 erreurs cette heure »).
:::

---

**QO26.8** — *Le chemin complet d'une alerte, et où elle peut se perdre.*

**Réponse attendue :**

| Étape | Ce qui se passe | Où ça peut se perdre |
|---|---|---|
| 1. Évaluation | toutes les `evaluation_interval`, `expr` est calculée | fichier non listé dans `rule_files`, YAML invalide (Prometheus refuse de charger), expression qui ne renvoie aucune série (label mal orthographié) |
| 2. pending → firing | vraie sans interruption pendant `for` | `for` trop long ; expression qui clignote (`irate`, fenêtre courte) : le chrono repart à zéro |
| 3. Envoi | POST vers chaque `alertmanagers` à chaque évaluation | `alerting:` absent ou mauvaise cible (`prometheus:9090/targets` ne le montre pas, regarder `/status` → Alertmanagers) |
| 4. Déduplication | même jeu de labels = même alerte, quel que soit le Prometheus émetteur | deux Prometheus avec des `external_labels` différents = deux alertes |
| 5. Routage | l'alerte descend l'arbre `route` jusqu'à la première branche qui matche | `matchers` qui ne matchent pas (`severity=page` vs `Page`) → route par défaut → mauvais receiver |
| 6. Groupement | attente `group_wait` puis notification groupée par `group_by` ; nouvelles alertes du groupe après `group_interval` ; rappel après `repeat_interval` | `group_wait` de 5 min, `repeat_interval` de 7 jours : personne ne revoit l'alerte |
| 7. Inhibition | tue si une `source` active a les mêmes `equal` | règle trop large (Q26.15) |
| 8. Silence | matchers + durée, posés par un humain | silence oublié, sans date de fin sensée, ou trop large (`instance=~".*"`) |
| 9. Notification | receiver (webhook, mail, PagerDuty) | URL fausse, TLS, token expiré : visible dans les logs Alertmanager (`notify retry`) et `alertmanager_notifications_failed_total` |
| 10. Résolution | Prometheus cesse d'envoyer ; après `resolve_timeout` (ou sur `EndsAt`), Alertmanager envoie `resolved` si `send_resolved` | le receiver ignore `resolved`, ou l'alerte a été silencée et se résout sans que personne le sache |

::: pourquoi
Deux outils rendent ce chemin observable : `promtool test rules` pour les
étapes 1-2, et `amtool alert query` / `amtool config routes test
severity=page` pour les étapes 5-8. Et une **alerte méta** :
`absent(up{job="prometheus"})` côté Prometheus, plus une *Watchdog*
(`vector(1)` toujours firing) dont l'absence côté récepteur signifie que la
chaîne est cassée. C'est la première alerte à créer sur toute nouvelle
plateforme.
:::

---

**QO26.9** — *Labels `user_id` et `request_id` : la cardinalité.*

**Réponse attendue :**

La **cardinalité** est le nombre de combinaisons distinctes de labels, donc
de séries. `factura_http_requests_total{method, path, code}` = 3 × 5 × 4 ≈
60 séries. Ajouter `user_id` (10 000 utilisateurs) donne 600 000 séries, et
chaque série coûte en mémoire (index + ~1-2 Ko par série active), en disque
et surtout en temps de requête : `sum(rate(...))` parcourt toutes les
séries. Prometheus est conçu pour des dizaines de milliers de séries par
instance, pas des millions ; le symptôme est un `prometheus` qui swappe
et des requêtes qui expirent. Pire, `request_id` est **unique** : une série
par requête, un échantillon chacune — Prometheus devient un journal, très
mal.

Dans Loki, un label `request_id` crée un **flux par requête** : l'index
explose, chaque chunk contient une ligne, l'ingestion est refusée
(`too many streams`) et les requêtes deviennent plus lentes que `grep`.

La bonne façon :

* **Métriques** : labels bornés seulement (`path` normalisé `/factures/:id`,
  `code`, `method`). On y répond à « combien, à quelle vitesse ».
* **Logs** : `request_id` et `user_id` **dans la ligne** (logfmt/JSON), pas
  en label. On les retrouve par filtre :
  `{namespace="factura"} | logfmt | request_id="abc123"`.
* **Traces** : chaque requête a un `trace_id` propagé (`traceparent`) ;
  Tempo/Jaeger le retrouve directement. Le `trace_id` est écrit dans les
  logs pour sauter de l'un à l'autre.
* **Exemplars** : sur un histogramme, Prometheus peut stocker à côté d'un
  bucket un `trace_id` d'exemple : du p99 qui grimpe, on clique vers **une**
  trace lente.

::: pourquoi
La question cache une règle générale : chaque pilier a un axe d'index
différent. Prometheus indexe des dimensions **agrégeables**, Loki des
**flux**, les traces des **requêtes**. Mettre un identifiant unique là où
l'on agrège casse l'outil. En entretien, citer le seuil pratique : un label
ne doit pas dépasser quelques dizaines de valeurs.
:::

---

**QO26.10** — *40 alertes par nuit, 3 utiles : la fatigue d'alerte.*

**Réponse attendue :**

La fatigue d'alerte, c'est l'astreinte qui **cesse de lire** : chaque page
est acquittée sans regarder parce que 37 sur 40 sont du bruit. Conséquences :
la vraie panne est traitée en retard (ou pas), le sommeil et le moral sont
détruits, les meilleurs partent, et l'équipe finit par mettre en silence
« temporaire » des alertes qui restent muettes des mois.

Plan en cinq actions :

1. **Inventaire chiffré** : exporter 30 jours d'alertes (`amtool`, base
   Alertmanager ou logs webhook), compter par `alertname`, et pour chacune
   noter « action prise ». Une alerte sans action dans 90 % des cas n'est
   pas une page.
2. **Reclasser** : ne garder en `page` que les **symptômes** avec impact
   utilisateur (erreurs, latence, sonde externe, budget d'erreur) ; tout ce
   qui est cause (CPU, disque à 70 %, un pod redémarré) passe en `ticket`
   ou disparaît au profit d'un tableau de bord.
3. **Remplacer les seuils par le burn rate** (QO26.6) : une seule alerte de
   disponibilité multi-fenêtre au lieu de dix seuils.
4. **Ajouter `for`, groupement et inhibition** : pas d'alerte sur une seule
   évaluation ; `group_by [alertname, instance]` pour recevoir une
   notification par incident et non une par série ; inhiber les enfants d'un
   `InstanceDown`.
5. **Un runbook par alerte, ou l'alerte est supprimée**. Et un rituel : revue
   hebdomadaire des alertes de la semaine (5 min, question unique : « était-ce
   utile ? »), avec un budget : pas plus de N pages par semaine, sinon on
   arrête les fonctionnalités et on répare.

**Rôle du post-mortem** : chaque incident sérieux sort avec des actions dont
certaines concernent les alertes elles-mêmes : « on a été prévenus 40 min
trop tard », « l'alerte a sonné mais elle était noyée », « il manquait une
alerte sur X ». Le post-mortem est la boucle de rétroaction qui fait évoluer
le catalogue d'alertes d'après la réalité et non d'après ce qu'on imaginait
au départ.

::: pourquoi
Il n'est pas prudent de supprimer des alertes sans mesure : le point 1 est
ce qui rend la démarche défendable devant un manager inquiet. Et le point 5
est ce qui empêche le retour du bruit : une alerte a un **propriétaire**, un
runbook et une date de revue, ou elle n'existe pas.
:::

---

## 26.5 Exercices guidés

**E26.1** — *Kubeconfig de k3s sur lab-adm, namespace par défaut, complétion, alias `k`.*

Sur `lab-adm` :

```bash
mkdir -p ~/.kube && chmod 0700 ~/.kube
ssh mathieu@10.10.10.14 sudo cat /etc/rancher/k3s/k3s.yaml \
  | sed 's#https://127.0.0.1:6443#https://10.10.10.14:6443#' \
  > ~/.kube/config
chmod 0600 ~/.kube/config
kubectl get nodes
kubectl config set-context --current --namespace=factura
kubectl config get-contexts        # colonne NAMESPACE = factura
```

Complétion et alias, persistants :

```bash
cat >> ~/.bashrc <<'EOF'
source <(kubectl completion bash)
alias k=kubectl
complete -o default -F __start_kubectl k
EOF
source ~/.bashrc
k get po <TAB><TAB>                # propose les pods du namespace factura
```

::: pourquoi
Le kubeconfig généré par k3s pointe sur `127.0.0.1` parce qu'il est prévu
pour le nœud lui-même ; le certificat serveur de k3s inclut d'office l'IP du
nœud dans ses SAN, donc remplacer l'adresse suffit, sans toucher au CA. Le
fichier contient le certificat client **admin** du cluster : c'est un secret
de niveau root, d'où le `0600` (kubectl affiche un avertissement sinon).
L'alias `k` ne complète pas tout seul parce que la complétion bash est
attachée au nom de la commande : `complete -F __start_kubectl k` rattache la
fonction générée par `kubectl completion` à l'alias.
:::

::: piege
`sudo cat ... | sed > fichier` exécuté **sur lab-ops** avec `sudo` crée le
fichier appartenant à root. Sur lab-adm, le `sudo` est dans le `ssh`, le
fichier local est à `mathieu`. Autre piège : `kubectl config set-context
--current` modifie le kubeconfig local, pas le cluster ; chaque poste a son
propre namespace par défaut.
:::

---

**E26.2** — *Générer un Deployment et un Service sans les appliquer, nettoyer, appliquer dans `demo`.*

```bash
mkdir -p ~/lab26/demo && cd ~/lab26/demo
kubectl create namespace demo --dry-run=client -o yaml > 00-ns.yaml
kubectl create deployment demo --image=nginx:1.27-alpine --replicas=2 \
  -n demo --dry-run=client -o yaml > 10-deploy.yaml
kubectl create service clusterip demo --tcp=80:80 -n demo \
  --dry-run=client -o yaml > 20-svc.yaml
sed -i '/creationTimestamp: null/d; /^status: {}$/d; /resources: {}/d' \
  *.yaml
kubectl apply -f .
kubectl get all -n demo
```

Résultat après nettoyage, `10-deploy.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: demo
  name: demo
  namespace: demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo
  template:
    metadata:
      labels:
        app: demo
    spec:
      containers:
      - image: nginx:1.27-alpine
        name: nginx
```

et `20-svc.yaml` :

```yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: demo
  name: demo
  namespace: demo
spec:
  ports:
  - name: 80-80
    port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: demo
  type: ClusterIP
```

::: pourquoi
`--dry-run=client -o yaml` est la façon standard d'obtenir un squelette
**exact** pour la version de l'API du cluster, plutôt que de recopier un
exemple de blog. Les champs à nettoyer sont des artefacts de la
sérialisation Go (`creationTimestamp: null`, `status: {}`) : inoffensifs
mais ils polluent le diff Git. `kubectl create service clusterip` déduit le
sélecteur `app=demo` du nom : vérifie toujours qu'il correspond aux labels
du template du Deployment, c'est la source n° 1 de « Service sans endpoint ».
:::

---

**E26.3** — *Trois affichages en une commande.*

```bash
# (a) nom, IP, nœud — tous namespaces
kubectl get pods -A -o custom-columns=\
NS:.metadata.namespace,NOM:.metadata.name,IP:.status.podIP,NOEUD:.spec.nodeName

# (b) image de chaque conteneur de chaque Deployment de factura
kubectl get deploy -n factura -o jsonpath='{range .items[*]}{.metadata.name}\
{"\t"}{range .spec.template.spec.containers[*]}{.image}{" "}{end}{"\n"}{end}'

# (c) 15 derniers événements du cluster
kubectl get events -A --sort-by=.lastTimestamp | tail -15
```

::: pourquoi
`custom-columns` et `jsonpath` lisent le même document JSON que
`-o json` : quand tu hésites sur un chemin, `kubectl get pod X -o json |
jq .status` te le montre. `{range}{end}` est la boucle de jsonpath ; sans
elle, une liste de valeurs est jointe par des espaces. `--sort-by` trie côté
client sur un champ jsonpath : `.lastTimestamp` peut être vide pour les
événements agrégés récents (champ `eventTime`), auquel cas ils sortent en
tête ; c'est acceptable pour un tri d'exploitation.
:::

---

**E26.4** — *Port-forward, `resolv.conf` d'un pod, logs de tous les pods du Deployment.*

Sur `lab-adm` :

```bash
kubectl port-forward -n demo deploy/demo 8080:80 &
curl -s http://127.0.0.1:8080/ | head -3      # Welcome to nginx!
kill %1
```

```bash
POD=$(kubectl get pod -n demo -l app=demo \
  -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n demo "$POD" -- cat /etc/resolv.conf
```

Sortie attendue :

```text
search demo.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.43.0.10
options ndots:5
```

* `search` : suffixes essayés dans l'ordre pour tout nom qui contient moins
  de `ndots` points. `demo` → `demo.demo.svc.cluster.local` en premier
  (même namespace), puis `demo.svc.cluster.local`, puis `demo.cluster.local`.
* `ndots:5` : un nom avec **moins de 5 points** est d'abord complété par les
  suffixes, avant d'être essayé tel quel. `api.github.com` (2 points) produit
  donc trois requêtes NXDOMAIN inutiles avant la bonne. Pour un nom externe
  très sollicité, on termine le nom par un point (`api.github.com.`) ou on
  baisse `ndots` via `dnsConfig`.
* `10.43.0.10` : le Service `kube-dns` de CoreDNS dans `kube-system`.

```bash
kubectl logs -n demo deploy/demo --all-containers --tail=20 --prefix
# ou, tous les pods du sélecteur :
kubectl logs -n demo -l app=demo --tail=20 --prefix
```

::: pourquoi
`port-forward` ouvre un tunnel via l'API server jusqu'au kubelet, puis au
pod : aucune règle réseau ni Service nécessaire, parfait pour déboguer un
pod isolé, inutilisable en production (un seul pod, une seule session).
`kubectl logs deploy/demo` choisit **un** pod au hasard ; `-l app=demo`
avec `--prefix` couvre tous les pods et préfixe chaque ligne du nom du pod.
:::

---

**E26.5** — *Labels : poser, filtrer, et changer `app` d'un pod du Deployment.*

```bash
POD=$(kubectl get pod -n demo -l app=demo \
  -o jsonpath='{.items[0].metadata.name}')
kubectl label pod -n demo "$POD" env=test
kubectl get pods -n demo -L env                  # colonne ENV
kubectl get pods -n demo -l env=test
kubectl get pods -n demo -l '!env'               # ceux qui n'ont PAS env
kubectl get pods -n demo -l 'env!=test'          # équivalent ici
```

Changer `app` sur un pod du Deployment :

```bash
kubectl label pod -n demo "$POD" app=orphelin --overwrite
kubectl get pods -n demo -L app --show-labels
```

Sortie : **trois** pods. Le pod relabelisé est toujours `Running` mais ne
correspond plus au sélecteur du ReplicaSet, qui voit 1 pod au lieu de 2 et en
crée un nouveau. Le pod `orphelin` est aussi sorti des Endpoints du Service
`demo` (sélecteur `app=demo`). Nettoyage : `kubectl delete pod -n demo
"$POD"` (ou remettre `app=demo`, le ReplicaSet supprimera alors l'excédent).

::: pourquoi
Le ReplicaSet n'a **aucune** notion de « ses » pods : il ne connaît qu'un
sélecteur et compte les pods qui y répondent (plus une vérification
d'`ownerReferences` pour ne pas adopter n'importe quoi). C'est ce
découplage par labels qui permet la technique d'isolation d'un pod fautif :
on change son label, le Deployment le remplace, et on garde le pod malade
en vie pour l'autopsie sans impacter le service.
:::

::: piege
`kubectl label` sans `--overwrite` refuse de modifier un label existant.
Et `!env` doit être protégé du shell (`'!env'`) : bash interprète `!` comme
un rappel d'historique.
:::

---

**E26.6** — *ConfigMap fichier + littéral, en env et en volume ; mise à jour à chaud.*

```bash
cd ~/lab26/demo
echo "bonjour depuis la configmap" > message.txt
kubectl create configmap demo-conf -n demo --from-file=message.txt \
  --from-literal=COULEUR=bleu
kubectl get cm demo-conf -n demo -o yaml
```

Pod qui consomme les deux formes, `conf-pod.yaml` :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: conf-pod
  namespace: demo
spec:
  containers:
    - name: sh
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      env:
        - name: COULEUR
          valueFrom:
            configMapKeyRef:
              name: demo-conf
              key: COULEUR
      volumeMounts:
        - name: conf
          mountPath: /etc/demo
          readOnly: true
  volumes:
    - name: conf
      configMap:
        name: demo-conf
```

```bash
kubectl apply -f conf-pod.yaml
kubectl exec -n demo conf-pod -- \
  sh -c 'echo $COULEUR; cat /etc/demo/message.txt'
kubectl patch cm demo-conf -n demo --type merge \
  -p '{"data":{"COULEUR":"rouge","message.txt":"texte modifie\n"}}'
sleep 90
kubectl exec -n demo conf-pod -- \
  sh -c 'echo $COULEUR; cat /etc/demo/message.txt'
```

Observation : `message.txt` **change** (après jusqu'à ~60-90 s), `$COULEUR`
vaut toujours `bleu`.

::: pourquoi
Un volume ConfigMap est projeté par le kubelet et rafraîchi à chaque période
de synchronisation (`syncFrequency`, 1 min) plus le délai de cache : le
kubelet remplace atomiquement un lien symbolique `..data` vers un nouveau
répertoire horodaté — d'où l'importance de ne pas monter avec `subPath`, qui
casse ce mécanisme et fige le fichier. Les variables d'environnement, elles,
sont fixées à la **création du processus** : seul un redémarrage du conteneur
(`kubectl rollout restart` pour un Deployment) les met à jour. Une
application qui doit suivre sa config à chaud doit relire le fichier
(inotify ou périodiquement) ; sinon, on déclenche un rollout en changeant
une annotation ou le nom de la ConfigMap (hash du contenu, ce que fait
Kustomize avec `configMapGenerator`).
:::

---

**E26.7** — *CronJob `sauvegarde-pg` avec PVC, déclenchement immédiat, non-chevauchement.*

`~/lab26/k8s/60-cronjob-sauvegarde.yaml` complété :

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: sauvegardes
  namespace: factura
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: sauvegarde-pg
  namespace: factura
spec:
  schedule: "30 2 * * *"
  timeZone: "Europe/Paris"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: pgdump
              image: postgres:16-alpine
              env:
                - name: PGPASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: postgres-auth
                      key: POSTGRES_PASSWORD
                - name: PGUSER
                  valueFrom:
                    secretKeyRef:
                      name: postgres-auth
                      key: POSTGRES_USER
              command: ["/bin/sh", "-c"]
              args:
                - >-
                  pg_dump -h postgres -U "$PGUSER" factura
                  > /backup/factura-$(date +%F).sql
                  && ls -l /backup
              volumeMounts:
                - name: backup
                  mountPath: /backup
          volumes:
            - name: backup
              persistentVolumeClaim:
                claimName: sauvegardes
```

```bash
kubectl apply -f ~/lab26/k8s/60-cronjob-sauvegarde.yaml
kubectl create job -n factura --from=cronjob/sauvegarde-pg sauvegarde-test
kubectl get jobs -n factura -w                    # COMPLETIONS 1/1
kubectl logs -n factura job/sauvegarde-test       # ls -l /backup
kubectl run -n factura -it --rm verif --image=busybox:1.36 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"verif","image":"busybox:1.36",
  "command":["sh","-c","ls -l /b && head -5 /b/*.sql"],
  "volumeMounts":[{"name":"b","mountPath":"/b"}]}],
  "volumes":[{"name":"b","persistentVolumeClaim":{"claimName":"sauvegardes"}}]}}'
```

La directive qui empêche le chevauchement : **`concurrencyPolicy: Forbid`**
(défaut `Allow` ; `Replace` tue l'exécution en cours au profit de la
nouvelle).

::: pourquoi
`kubectl create job --from=cronjob/...` copie le `jobTemplate` dans un Job
immédiat : c'est la façon officielle de tester un CronJob sans attendre.
`restartPolicy` est **obligatoire** dans un Job et ne peut valoir que
`OnFailure` (le conteneur est relancé dans le même pod) ou `Never` (un
nouveau pod par tentative, plus lisible pour les logs) ; `backoffLimit`
borne les tentatives. `timeZone` évite la surprise d'un cron en UTC.
`local-path` étant `WaitForFirstConsumer`, le PVC reste `Pending` jusqu'au
premier Job : c'est normal.
:::

::: piege
Le PVC `sauvegardes` est en `ReadWriteOnce` sur le même nœud que PostgreSQL :
sauvegarde sur le **même disque** que la base, ce n'est pas une sauvegarde.
En production, le Job pousse vers un stockage objet (S3/MinIO) avec
`pg_dump | gzip | aws s3 cp - s3://...`.
:::

---

**E26.8** — *DaemonSet `noeud-info` : nom du nœud par Downward API, uptime du nœud.*

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: noeud-info
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: noeud-info
  template:
    metadata:
      labels:
        app: noeud-info
    spec:
      tolerations:
        - operator: Exists          # tourne aussi sur les nœuds taintés
      containers:
        - name: info
          image: busybox:1.36
          command: ["sh", "-c"]
          args:
            - >-
              while true; do
              echo "$(date +%T) noeud=$NOEUD uptime_s=$(cut -d' ' -f1
              /hote/uptime)"; sleep 60; done
          env:
            - name: NOEUD
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
          volumeMounts:
            - name: uptime
              mountPath: /hote/uptime
              readOnly: true
          resources:
            requests: {cpu: 5m, memory: 8Mi}
            limits: {memory: 16Mi}
      volumes:
        - name: uptime
          hostPath:
            path: /proc/uptime
            type: File
```

```bash
kubectl apply -f ~/lab26/demo/noeud-info.yaml
kubectl get ds -n kube-system noeud-info          # DESIRED = nombre de nœuds
kubectl logs -n kube-system -l app=noeud-info --tail=3
```

::: pourquoi
La **Downward API** expose au conteneur des champs de son propre objet Pod
(`spec.nodeName`, `metadata.name`, `status.podIP`, limites de ressources)
sans appeler l'API server : pas de RBAC, pas de token. Le `hostPath` monte un
fichier du nœud ; ici `/proc/uptime`. Nuance honnête : sans *time namespace*
(défaut sur Kubernetes), `/proc/uptime` du conteneur donne déjà l'uptime du
noyau, donc de l'hôte — le montage rend l'intention explicite et fonctionne
quel que soit le runtime. Un DaemonSet a un pod par nœud éligible ;
`tolerations: operator: Exists` le fait aussi tourner sur les nœuds
`cordon` ou control-plane, comme un agent de supervision doit le faire.
:::

---

**E26.9** — *(optionnel) Agent k3s sur lab-web, label, `nodeSelector`, retrait propre.*

```bash
# sur lab-ops
sudo cat /var/lib/rancher/k3s/server/node-token
# sur lab-web
curl -sfL https://get.k3s.io | K3S_URL=https://10.10.10.14:6443 \
  K3S_TOKEN='K10...::server:...' sh -
# sur lab-adm
kubectl get nodes -o wide                         # lab-web Ready, 10.10.10.11
kubectl label node lab-web role=web
kubectl patch deploy demo -n demo -p \
  '{"spec":{"template":{"spec":{"nodeSelector":{"role":"web"}}}}}'
kubectl rollout status deploy/demo -n demo
kubectl get pods -n demo -o wide                  # NODE = lab-web pour tous
```

Retrait propre :

```bash
kubectl drain lab-web --ignore-daemonsets --delete-emptydir-data
kubectl get pods -n demo -o wide     # Pending : nodeSelector insatisfaisable
kubectl patch deploy demo -n demo --type json \
  -p '[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]'
kubectl delete node lab-web
# sur lab-web
sudo /usr/local/bin/k3s-agent-uninstall.sh
```

::: pourquoi
`drain` = `cordon` (taint `unschedulable`) + éviction de tous les pods gérés
par un contrôleur, en respectant les `PodDisruptionBudget`. Les DaemonSets
sont ignorés (ils reviendraient), les pods sans contrôleur sont refusés sauf
`--force`. C'est la procédure standard avant toute maintenance de nœud. Le
piège observé : un `nodeSelector` qui ne matche plus aucun nœud laisse les
pods `Pending` — le scheduler ne « relâche » jamais une contrainte.
:::

---

**E26.10** — *ServiceAccount `lecteur` avec lecture seule sur `factura` via une ClusterRole existante.*

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: lecteur
  namespace: factura
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: lecteur-view
  namespace: factura
subjects:
  - kind: ServiceAccount
    name: lecteur
    namespace: factura
roleRef:
  kind: ClusterRole
  name: view
  apiGroup: rbac.authorization.k8s.io
```

```bash
kubectl apply -f ~/lab26/demo/lecteur.yaml
SA=system:serviceaccount:factura:lecteur
kubectl auth can-i list pods -n factura --as=$SA          # yes
kubectl auth can-i get pods --subresource=log -n factura --as=$SA  # yes
kubectl auth can-i delete pods -n factura --as=$SA        # no
kubectl auth can-i list pods -n kube-system --as=$SA      # no
kubectl auth can-i --list -n factura --as=$SA             # le détail
```

::: pourquoi
Une **ClusterRole** liée par un **RoleBinding** donne ses permissions
**uniquement dans le namespace du binding** : c'est le motif standard pour
réutiliser `view`/`edit`/`admin` sans réécrire des règles. Un
ClusterRoleBinding donnerait `view` partout. `view` couvre pods, services,
configmaps, `pods/log`, mais **pas les Secrets** (volontairement).
`--as=system:serviceaccount:<ns>:<nom>` est la forme d'impersonation d'un
ServiceAccount ; `kubectl auth can-i` interroge l'API `SelfSubjectAccessReview`
et répond ce que l'API server décidera vraiment.
:::

---

**E26.11** — *ResourceQuota : 4 pods, 2 CPU, 2 Gi de requests, scale à 5.*

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: factura-quota
  namespace: factura
spec:
  hard:
    pods: "4"
    requests.cpu: "2"
    requests.memory: 2Gi
```

```bash
kubectl apply -f ~/lab26/demo/quota.yaml
kubectl describe quota factura-quota -n factura   # Used / Hard
kubectl scale deploy factura-api -n factura --replicas=5
kubectl get pods -n factura                       # 4 pods au total, pas 5
kubectl get deploy factura-api -n factura         # READY 2/5 (front + pg + 2)
kubectl describe rs -n factura -l app=factura-api | grep -A3 Events
kubectl get events -n factura --field-selector reason=FailedCreate
kubectl scale deploy factura-api -n factura --replicas=2
kubectl delete quota factura-quota -n factura
```

Le refus se lit dans les **événements du ReplicaSet** :

```text
Warning  FailedCreate  replicaset-controller  Error creating: pods
"factura-api-7d9c8b5f4-abcde" is forbidden: exceeded quota: factura-quota,
requested: pods=1, used: pods=4, limited: pods=4
```

::: pourquoi
Le quota est appliqué par un *admission controller* de l'API server : le
pod est **refusé à la création**, il n'existe pas, donc `get pods` ne peut
rien montrer. Le ReplicaSet réessaie avec un backoff exponentiel et logue
chaque refus dans ses propres événements. Avec `factura` déjà occupé par
`postgres` (1) et `front` (1), la place restante pour l'API est 2 : la
quota est atteinte avant même le premier pod supplémentaire. Autre effet
important : dès qu'une quota `requests.cpu` existe, **tout pod sans
`requests` est refusé** — d'où le couple habituel ResourceQuota +
LimitRange (valeurs par défaut).
:::

---

**E26.12** — *PromQL système : CPU, mémoire, disque, charge, réseau.*

```text
# (a) CPU utilisé en %
100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))

# (b) mémoire disponible en %
100 * node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes

# (c) espace disque / utilisé en %
100 * (1 - node_filesystem_avail_bytes{mountpoint="/"}
           / node_filesystem_size_bytes{mountpoint="/"})

# (d) charge 5 min par cœur
node_load5 / count by (instance) (node_cpu_seconds_total{mode="idle"})

# (e) débit entrant en bit/s hors lo et interfaces virtuelles
8 * sum by (instance) (rate(node_network_receive_bytes_total{
  device!~"lo|veth.*|docker.*|br-.*|cni.*|flannel.*|virbr.*"}[5m]))
```

Valeurs plausibles sur `lab-web` au repos : (a) 1-3 %, (b) 60-75 %,
(c) 25-35 %, (d) 0,02-0,1, (e) quelques kbit/s (scrapes + SSH).

::: pourquoi
(a) : `node_cpu_seconds_total` est un counter **par CPU et par mode** ; le
taux du mode `idle` est la fraction de temps oisif par CPU (0..1), la
moyenne par instance donne la fraction oisive de la machine. (b) :
`MemAvailable` (calculé par le noyau : libre + cache récupérable) est la bonne
métrique, `MemFree` sous-estime grossièrement. (c) : `avail` (non-root)
plutôt que `free` (inclut les 5 % réservés à root) : c'est ce que voient
les applications. (d) : compter les séries `idle` est l'astuce standard pour
obtenir le nombre de cœurs ; une charge par cœur > 1 signifie une file
d'attente. (e) : `× 8` pour passer en bits ; l'exclusion par regex évite de
compter deux fois le trafic qui traverse un bridge.
:::

---

**E26.13** — *PromQL applicatif : débit, ratio 5xx, p95, disque plein, cibles down.*

```text
# (f) requêtes/s de l'API par code HTTP
sum by (code) (rate(factura_http_requests_total[5m]))

# (g) ratio de 5xx sur 5 min
sum(rate(factura_http_requests_total{code=~"5.."}[5m]))
  / sum(rate(factura_http_requests_total[5m]))

# (h) p95 de latence de /factures
histogram_quantile(0.95, sum by (le) (
  rate(factura_http_request_duration_seconds_bucket{path="/factures"}[5m])))

# (i) dans combien de secondes / de lab-db sera plein (tendance 6 h),
#     puis la date (horodatage Unix ; Grafana l'affiche en date)
node_filesystem_avail_bytes{instance="lab-db",mountpoint="/"}
  / -deriv(node_filesystem_avail_bytes{instance="lab-db",mountpoint="/"}[6h])
time() + node_filesystem_avail_bytes{instance="lab-db",mountpoint="/"}
  / -deriv(node_filesystem_avail_bytes{instance="lab-db",mountpoint="/"}[6h])
# variante « sera-t-il plein dans 24 h ? » (la forme utilisée en alerte)
predict_linear(node_filesystem_avail_bytes{instance="lab-db",
  mountpoint="/"}[6h], 24*3600) < 0

# (j) cibles down, et depuis combien de secondes (dernier passage à 1)
up == 0
time() - max_over_time(timestamp(up == 1)[24h:1m]) and on (instance, job) up == 0
changes(up[1h]) > 0        # les cibles qui ont clignoté dans l'heure
```

::: pourquoi
(g) : la division de deux agrégats sans label fonctionne parce que les deux
côtés sont des scalaires vectoriels sans dimension ; si on ventile par
`path`, il faut `sum by (path)` des deux côtés. (h) : filtrer sur `path`
**avant** `sum by (le)` — après, le label a disparu. (i) : `deriv` est la
pente (octets/s, négative quand ça se remplit) ; diviser l'espace restant par
la pente donne le temps restant. Si `deriv` est positif (le disque se vide)
le résultat est négatif : on l'ignore. (j) : `timestamp()` renvoie l'heure
de l'échantillon, `max_over_time` sur une sous-requête garde le dernier
moment où la cible était UP ; `and on (...)` restreint aux cibles
actuellement DOWN. `changes()` répond à une question différente — la
stabilité — utile pour repérer une cible qui clignote sans jamais rester
DOWN assez longtemps pour alerter.
:::

---

**E26.14** — *SLO 99,5 % sur 30 jours : budget, minutes, burn rate, épuisement.*

**Calcul :**

* (a) budget = `1 − 0,995 = 0,5 %`. Sur 2 000 000 de requêtes :
  `0,005 × 2 000 000 = 10 000 requêtes` en erreur autorisées par mois.
* (b) en temps : 30 jours = `30 × 24 × 60 = 43 200 min` ;
  `0,005 × 43 200 = 216 min` = 3 h 36 d'indisponibilité totale.
* (c) burn rate = taux d'erreur mesuré / taux autorisé = `0,02 / 0,005 = 4`.
* (d) épuisement : `30 j / 4 = 7,5 jours` (si le taux de 2 % se maintient).

**Vérification en PromQL** (avec `charge-api.sh` et éventuellement
`FACTURA_TAUX_ERREUR=0.02` pendant l'exercice) :

```text
# taux d'erreur sur 1 h
sum(rate(factura_http_requests_total{code=~"5.."}[1h]))
  / sum(rate(factura_http_requests_total[1h]))

# burn rate 1 h
( sum(rate(factura_http_requests_total{code=~"5.."}[1h]))
  / sum(rate(factura_http_requests_total[1h])) ) / (1 - 0.995)

# requêtes en erreur consommées sur la fenêtre de 30 j, à comparer à 10 000
sum(increase(factura_http_requests_total{code=~"5.."}[30d]))

# budget restant en fraction (1 = intact, 0 = épuisé)
1 - ( sum(increase(factura_http_requests_total{code=~"5.."}[30d]))
      / sum(increase(factura_http_requests_total[30d])) ) / (1 - 0.995)
```

::: pourquoi
Le passage « pourcentage → minutes » suppose que les erreurs sont
concentrées (panne totale) ; le passage « pourcentage → requêtes » est plus
juste pour un SLI fondé sur les requêtes, parce qu'une panne à 3 h du matin
coûte moins de requêtes qu'à 11 h. C'est pourquoi les SLO modernes sont
définis en **requêtes**, et la conversion en minutes n'est là que pour
parler aux humains. Le burn rate 4 signifie : « on consomme le budget 4 fois
trop vite » ; c'est en dessous des deux seuils du SRE Workbook (14,4 pour une page, 6 pour un ticket), donc pas d'alerte — mais le budget serait vide en 7,5 jours, donc à traiter dans la journée si le taux se maintient.
:::

---

**E26.15** — *`amtool` : alertes, silence, expiration, `check-config`.*

```bash
cd /opt/observabilite
docker compose exec alertmanager amtool alert query
docker compose exec alertmanager amtool silence add \
  alertname=InstanceDown instance=lab-rhel --duration=2h \
  --author=mathieu --comment="maintenance lab-rhel, ticket CHG-4410"
# affiche l'ID du silence, ex. 4a1c...-....
docker compose exec alertmanager amtool silence query
docker compose exec alertmanager amtool silence expire <ID>
docker compose exec alertmanager amtool silence query --expired
docker compose exec alertmanager amtool check-config \
  /etc/alertmanager/alertmanager.yml
```

Sortie attendue de `check-config` :

```text
Checking '/etc/alertmanager/alertmanager.yml'  SUCCESS
Found:
 - global config
 - route
 - 1 inhibit rules
 - 2 receivers
 - 0 templates
```

::: pourquoi
`amtool` dans le conteneur parle à `localhost:9093` par défaut ; depuis
lab-ops directement il faudrait `--alertmanager.url=http://10.10.10.14:9093`.
Un silence est un jeu de **matchers** (`=`, `^=`, `=~`) avec début, fin,
auteur et commentaire obligatoires — c'est volontaire : un silence sans
motif est une alerte perdue. Un silence expiré reste consultable (audit).
`check-config` valide la syntaxe et la cohérence (receivers référencés,
matchers valides) mais pas la logique de routage : pour ça, `amtool config
routes test --config.file=... severity=page instance=lab-rhel` affiche le
receiver qui recevrait l'alerte.
:::

---

**E26.16** — *LogQL : filtres, compte par minute, `logfmt`, taux de 5xx.*

```text
# (a) journal de lab-ops, k3s, sans level=info
{job="systemd-journal", host="lab-ops"} |= "k3s" != "level=info"

# (b) lignes par minute sur 30 min (régler la fenêtre Explore à 30 min)
sum(count_over_time({job="systemd-journal", host="lab-ops"}[1m]))

# (c) lignes de l'API dont duree_ms > 50
{namespace="factura", container="api"} | logfmt | duree_ms > 50

# (d) taux de lignes code=5xx par seconde
sum(rate({namespace="factura", container="api"} | logfmt | code=~"5.." [1m]))
```

::: pourquoi
L'ordre d'un pipeline LogQL est celui de l'exécution : sélecteur de flux
(index) → filtres de ligne `|=`/`!=`/`|~` (rapides, sur le texte brut) →
parseur (`| logfmt`, `| json`, `| regexp`) qui extrait des **champs** →
filtres de champs (`duree_ms > 50`, `code=~"5.."`). Mettre les filtres de
ligne **avant** le parseur évite de parser des lignes qui seront rejetées.
`count_over_time` compte des lignes, `rate` divise par la fenêtre ;
`sum()` agrège les flux (un par pod). Les lignes de l'API sont en logfmt
(`ts=... niveau=info msg="requete" path=/factures code=200 duree_ms=12.3`),
donc `| logfmt` suffit — pas de regex.
:::

---

## 26.6 Labs

### **L26.1** — *Installer k3s et livrer un premier Deployment proprement*

*Ticket CHG-4401 : cluster k3s sur lab-ops, `kubectl` depuis lab-ops et
lab-adm, registre HTTP connu de containerd, Secret de registre, Deployment
`factura-api` avec rollout et rollback, rapport, chart Helm
`kube-state-metrics` avec upgrade et rollback.*

**1. Installation de k3s.**

```bash
curl -sfL https://get.k3s.io | sh -
systemctl status k3s.service --no-pager | head -5
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -n kube-system
```

```text
NAME      STATUS   ROLES                  AGE   VERSION
lab-ops   Ready    control-plane,master   64s   v1.31.4+k3s1

NAME                                      READY   STATUS      RESTARTS   AGE
coredns-ccb96694c-h8x2v                   1/1     Running     0          52s
local-path-provisioner-5cf85fd84d-kq7wn   1/1     Running     0          52s
metrics-server-5985cbc9d7-7sd6b           1/1     Running     0          52s
helm-install-traefik-crd-2xr4p            0/1     Completed   0          52s
helm-install-traefik-nl7ds                0/1     Completed   1          52s
svclb-traefik-3b4c9d1a-9kq2m              2/2     Running     0          31s
traefik-d7c865d47-m6zjt                   1/1     Running     0          31s
```

Ce qui tourne **en pods** : CoreDNS, `local-path-provisioner`,
metrics-server, Traefik (installé par un Job Helm interne) et `svclb-*`
(ServiceLB, un pod par Service `LoadBalancer`). Ce qui est **dans le
binaire** `k3s` (un seul processus, `journalctl -u k3s`) : api-server,
scheduler, controller-manager, kine + SQLite (`/var/lib/rancher/k3s/server/
db/state.db`), kubelet, kube-proxy, flannel et containerd (lancé comme
sous-processus, socket `/run/k3s/containerd/containerd.sock`).

**2. `kubectl` pour `mathieu`, sans `sudo`.**

```bash
mkdir -p ~/.kube && chmod 0700 ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown mathieu:mathieu ~/.kube/config && chmod 0600 ~/.kube/config
sudo ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl 2>/dev/null || true
kubectl get nodes                       # sans sudo, sans KUBECONFIG
echo 'source <(kubectl completion bash)' >> ~/.bashrc
```

`kubectl` lit `~/.kube/config` par défaut : aucune variable à exporter.
Sur k3s, `/usr/local/bin/kubectl` est déjà un lien vers `k3s` (le binaire
se comporte selon son `argv[0]`). Puis E26.1 sur lab-adm, et depuis les
deux VM :

```bash
kubectl cluster-info
kubectl get --raw /healthz          # ok
```

**3. Le registre HTTP côté containerd.**

```bash
cat /etc/rancher/k3s/registries.yaml
sudo cat /var/lib/rancher/k3s/agent/etc/containerd/certs.d/\
10.10.10.14:5000/hosts.toml
```

```text
mirrors:
  "10.10.10.14:5000":
    endpoint:
      - "http://10.10.10.14:5000"

# hosts.toml généré par k3s
server = "http://10.10.10.14:5000"

[host."http://10.10.10.14:5000"]
  capabilities = ["pull", "resolve"]
```

Sur les k3s antérieurs à 1.29, la même information est dans
`/var/lib/rancher/k3s/agent/etc/containerd/config.toml` (section
`[plugins."io.containerd.grpc.v1.cri".registry.mirrors]`). Ce fichier est
**régénéré** à chaque démarrage de k3s : on n'y touche jamais, on édite
`registries.yaml` puis `sudo systemctl restart k3s`.

**4. Namespace et Secret de registre.**

```bash
kubectl apply -f ~/lab26/k8s/00-namespace.yaml
kubectl create secret docker-registry registre-lab -n factura \
  --docker-server=10.10.10.14:5000 \
  --docker-username=mathieu --docker-password=labpass
kubectl get secret registre-lab -n factura \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq
```

```json
{
  "auths": {
    "10.10.10.14:5000": {
      "username": "mathieu",
      "password": "labpass",
      "auth": "bWF0aGlldTpsYWJwYXNz"
    }
  }
}
```

`auth` est `base64("mathieu:labpass")` : le mot de passe est lisible deux
fois, en clair et encodé. Le type `kubernetes.io/dockerconfigjson` impose
la clé `.dockerconfigjson` (d'où le `\.` dans le jsonpath).

**5. Premier Deployment de `factura-api:1.0`.**

`~/lab26/l1/api.yaml` (pas de readiness sur `/pret` à ce stade : sans
PostgreSQL elle échouerait et bloquerait le rollout de l'étape 6) :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: factura-api
  namespace: factura
  labels:
    app: factura-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: factura-api
  template:
    metadata:
      labels:
        app: factura-api
    spec:
      imagePullSecrets:
        - name: registre-lab
      containers:
        - name: api
          image: 10.10.10.14:5000/factura-api:1.0
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: DB_HOST
              value: "127.0.0.1"
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: factura-api
  namespace: factura
spec:
  type: ClusterIP
  selector:
    app: factura-api
  ports:
    - name: http
      port: 8080
      targetPort: http
```

```bash
kubectl apply -f ~/lab26/l1/api.yaml
kubectl get pods -n factura -w                # ContainerCreating -> Running
sudo k3s crictl images | grep factura
```

```text
10.10.10.14:5000/factura-api   1.0   3f1c2a9d7b6e4   52.4MB
```

**6. Rollout 1.1, historique, rollback.**

```bash
kubectl set image deploy/factura-api -n factura \
  api=10.10.10.14:5000/factura-api:1.1
kubectl annotate deploy/factura-api -n factura \
  kubernetes.io/change-cause="CHG-4401 : passage en 1.1"
kubectl rollout status deploy/factura-api -n factura
kubectl rollout history deploy/factura-api -n factura
```

```text
deployment "factura-api" successfully rolled out
REVISION  CHANGE-CAUSE
1         <none>
2         CHG-4401 : passage en 1.1
```

```bash
kubectl rollout undo deploy/factura-api -n factura
kubectl annotate deploy/factura-api -n factura --overwrite \
  kubernetes.io/change-cause="CHG-4401 : retour en 1.0 (rollback)"
kubectl rollout history deploy/factura-api -n factura
kubectl port-forward -n factura svc/factura-api 8080:8080 &
curl -s http://127.0.0.1:8080/ ; kill %1
```

```text
REVISION  CHANGE-CAUSE
2         CHG-4401 : passage en 1.1
3         CHG-4401 : retour en 1.0 (rollback)
{"app": "factura-api", "version": "1.0",
 "pod": "factura-api-7d9c8b5f4-x2k9p", "db_ok": false}
```

La révision 1 disparaît de l'historique : un rollback **réutilise** le
ReplicaSet de la révision 1 et le renumérote 3. Il y a bien deux
ReplicaSets (`kubectl get rs -n factura`), l'un à 2 pods, l'autre à 0.

**7. `~/lab26/rapports/rollout.md`.**

```markdown
# Rollout factura-api 1.0 -> 1.1 -> 1.0 (CHG-4401)

Stratégie par défaut : RollingUpdate, maxSurge=25 %, maxUnavailable=25 %.
Pour 2 réplicas : maxSurge = ceil(0,5) = 1 pod en plus au maximum,
maxUnavailable = floor(0,5) = 0 pod en moins au minimum.
Donc : jamais moins de 2 pods disponibles, jamais plus de 3 pods.

Observé (kubectl get pods -w) :
1. factura-api-7d9c8b5f4-x2k9p  1/1  (ancien)   factura-api-7d9c8b5f4-b8n4c 1/1
2. factura-api-6b7f9d8c4-q1z7t  0/1 Pending -> ContainerCreating -> 1/1
3. factura-api-7d9c8b5f4-x2k9p  1/1 Terminating   (un ancien part)
4. factura-api-6b7f9d8c4-w3m8r  0/1 -> 1/1        (deuxième nouveau)
5. factura-api-7d9c8b5f4-b8n4c  1/1 Terminating   (dernier ancien)
Sans readiness probe, « Running » = « disponible » : le contrôleur enchaîne
dès que le conteneur tourne. Avec une readiness, il attend 1/1.
```

**8. Helm : kube-state-metrics.**

```bash
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts
helm repo update
helm show values prometheus-community/kube-state-metrics \
  > ~/lab26/helm/ksm-values-defaut.yaml        # pour lire les clés
cat > ~/lab26/helm/ksm-values.yaml <<'EOF'
replicas: 1
podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
resources:
  requests:
    cpu: 10m
    memory: 32Mi
  limits:
    memory: 128Mi
EOF
helm install ksm prometheus-community/kube-state-metrics \
  -n monitoring --create-namespace -f ~/lab26/helm/ksm-values.yaml
kubectl get pods -n monitoring
kubectl port-forward -n monitoring svc/ksm-kube-state-metrics 8081:8080 &
curl -s http://127.0.0.1:8081/metrics \
  | grep 'kube_deployment_status_replicas_available{namespace="factura"'
kill %1
```

```text
kube_deployment_status_replicas_available{namespace="factura",
  deployment="factura-api"} 2
```

```bash
helm upgrade ksm prometheus-community/kube-state-metrics -n monitoring \
  -f ~/lab26/helm/ksm-values.yaml --set replicas=2
helm history ksm -n monitoring
helm rollback ksm 1 -n monitoring
helm history ksm -n monitoring
kubectl get deploy -n monitoring          # READY 1/1 après rollback
```

```text
REVISION  UPDATED               STATUS      CHART                DESCRIPTION
1         Sep 15 10:12 2026  superseded  kube-state-metrics  Install complete
2         Sep 15 10:15 2026  superseded  kube-state-metrics  Upgrade complete
3         Sep 15 10:16 2026  deployed    kube-state-metrics  Rollback to 1
```

::: pourquoi
Le fil conducteur du lab est le **modèle déclaratif**. `set image` ne
« déploie » rien : il modifie `spec.template` ; le hash du template change,
le contrôleur de Deployment crée un nouveau ReplicaSet et déplace les
réplicas de l'ancien vers le nouveau en respectant `maxSurge` et
`maxUnavailable`. `rollout undo` fait exactement la même chose dans l'autre
sens — c'est pourquoi il est instantané et pourquoi la révision 1 est
« renumérotée » : Kubernetes ne garde pas un historique de commandes mais
des ReplicaSets (`revisionHistoryLimit`, 10 par défaut) et chaque
ReplicaSet porte l'annotation `deployment.kubernetes.io/revision`. Helm
fonctionne pareil à un niveau au-dessus : une *release* est une suite de
révisions stockées dans des Secrets `sh.helm.release.v1.ksm.v1`, `.v2`…
du namespace, et `rollback` crée la révision 3 avec le contenu de la 1.
La séparation `registries.yaml` / config containerd générée illustre la
règle « on édite la source, pas l'artefact ».
:::

::: piege
`sudo kubectl` avec le kubeconfig root marche, mais tout ce que tu crées
ensuite dans `~/lab26/` depuis des redirections (`kubectl ... > f.yaml`)
appartient à root. L'option `--write-kubeconfig-mode 644` du script
d'installation est l'autre solution ; elle expose le certificat admin à
tout utilisateur de la VM, acceptable sur un lab, pas ailleurs.
`kubernetes.io/change-cause` doit être posé **après** la modification :
le contrôleur copie l'annotation du Deployment sur le ReplicaSet courant
à chaque synchronisation ; annotée avant `set image`, elle irait sur
l'ancienne révision. Enfin `helm rollback` ne touche pas aux objets que
le chart ne gère pas (ton Secret, ton namespace) — et un `kubectl edit`
manuel sur un objet Helm sera écrasé au prochain `upgrade` : c'est le
*drift*.
:::

---

### **L26.2** — *Déployer factura : nginx + API + PostgreSQL, TLS, quotas*

*Ticket CHG-4402 : compléter les squelettes de `~/lab26/k8s/` pour obtenir
PostgreSQL en StatefulSet, l'API avec probes et limites, le frontal nginx,
un Ingress TLS sur `factura.lab.local`, une NetworkPolicy, le tout
applicable d'un seul `kubectl apply -f`.*

**1. ConfigMap et Secret.**

```yaml
# 10-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: factura-api-config
  namespace: factura
data:
  DB_HOST: "postgres"
  DB_PORT: "5432"
  FACTURA_PORT: "8080"
```

```yaml
# 11-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-auth
  namespace: factura
type: Opaque
data:
  POSTGRES_USER: ZmFjdHVyYQ==
  POSTGRES_PASSWORD: bGFicGFzcw==
```

(`printf labpass | base64` → `bGFicGFzcw==` ; sans `printf`, `echo`
ajouterait un `\n` encodé dans le mot de passe. La variante `stringData:
{POSTGRES_PASSWORD: labpass}` laisse l'API server encoder.)

```bash
kubectl apply -f ~/lab26/k8s/10-configmap.yaml -f ~/lab26/k8s/11-secret.yaml
kubectl get secret postgres-auth -n factura \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d ; echo
```

**2. PostgreSQL en StatefulSet.**

```yaml
# 20-postgres.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: factura
spec:
  clusterIP: None
  selector:
    app: postgres
  ports:
    - name: pg
      port: 5432
      targetPort: 5432
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: factura
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          ports:
            - containerPort: 5432
              name: pg
          env:
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: postgres-auth
                  key: POSTGRES_USER
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-auth
                  key: POSTGRES_PASSWORD
          readinessProbe:
            exec:
              command: ["pg_isready", "-U", "factura"]
            initialDelaySeconds: 5
            periodSeconds: 10
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              memory: 512Mi
          volumeMounts:
            - name: donnees
              mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
    - metadata:
        name: donnees
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: local-path
        resources:
          requests:
            storage: 1Gi
```

```bash
kubectl apply -f ~/lab26/k8s/20-postgres.yaml
kubectl get pvc,pv -n factura
kubectl get pv -o jsonpath='{.items[0].spec.hostPath.path}' ; echo
sudo ls /var/lib/rancher/k3s/storage/
```

```text
NAME                   STATUS   VOLUME         CAPACITY   STORAGECLASS
donnees-postgres-0     Bound    pvc-3e1f5a7c   1Gi        local-path
(VOLUME abrégé : pvc-3e1f5a7c-91d2-4b6e-8f0a-6c2d9e4b1a77)

/var/lib/rancher/k3s/storage/pvc-3e1f5a7c-91d2-4b6e-8f0a-6c2d9e4b1a77\
_factura_donnees-postgres-0
```

Le PVC s'appelle `<template>-<pod>` (`donnees-postgres-0`) ; le PV est un
`hostPath` créé par `local-path-provisioner` au moment où le pod est
planifié (`volumeBindingMode: WaitForFirstConsumer`).

**3. L'API.**

```yaml
# 30-api.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: factura-api
  namespace: factura
  labels:
    app: factura-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: factura-api
  template:
    metadata:
      labels:
        app: factura-api
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      imagePullSecrets:
        - name: registre-lab
      containers:
        - name: api
          image: 10.10.10.14:5000/factura-api:1.0
          ports:
            - containerPort: 8080
              name: http
          envFrom:
            - configMapRef:
                name: factura-api-config
          livenessProbe:
            httpGet:
              path: /sante
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /pret
              port: http
            periodSeconds: 5
            failureThreshold: 3
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: factura-api
  namespace: factura
spec:
  type: ClusterIP
  selector:
    app: factura-api
  ports:
    - name: http
      port: 8080
      targetPort: http
```

```bash
kubectl apply -f ~/lab26/k8s/30-api.yaml
kubectl get pods -n factura -l app=factura-api
kubectl get endpoints factura-api -n factura
```

```text
NAME                           READY   STATUS    RESTARTS   AGE
factura-api-5c7d9f6b8-4hq2z    1/1     Running   0          40s
factura-api-5c7d9f6b8-tz8kp    1/1     Running   0          40s
NAME          ENDPOINTS                           AGE
factura-api   10.42.0.19:8080,10.42.0.20:8080     40s
```

Si un pod reste `0/1`, `kubectl describe pod` → `Readiness probe failed:
HTTP probe failed with statuscode: 503` : `/pret` répond
`{"pret":false,"raison":"db"}`, donc `DB_HOST` ou PostgreSQL. Si c'est
`ImagePullBackOff`, le Secret `registre-lab` manque (L26.1 étape 4).

**4. Lecture de `40-front.yaml`.** `location /api/ { proxy_pass
http://factura-api:8080/; }` : le `/` final fait que nginx **remplace** le
préfixe `/api/` par `/` — `/api/factures` devient `/factures` côté API.
Sans ce `/`, nginx transmettrait `/api/factures` tel quel et l'API
répondrait 404 `route inconnue`. nginx résout `factura-api` au chargement de
la configuration via le `resolv.conf` du pod (CoreDNS, `search
factura.svc.cluster.local`), donc le Service doit exister **avant** le pod
nginx — sinon `nginx: [emerg] host not found in upstream`, CrashLoopBackOff.

```bash
kubectl apply -f ~/lab26/k8s/40-front.yaml
kubectl get pods -n factura -l app=front
```

**5. TLS et Ingress.**

```bash
kubectl create secret tls factura-tls -n factura \
  --cert=$HOME/lab26/tls/factura.crt --key=$HOME/lab26/tls/factura.key
```

```yaml
# 50-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: factura
  namespace: factura
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - factura.lab.local
      secretName: factura-tls
  rules:
    - host: factura.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: front
                port:
                  number: 80
```

```bash
kubectl apply -f ~/lab26/k8s/50-ingress.yaml
kubectl get ingress -n factura
```

```text
NAME      CLASS     HOSTS               ADDRESS       PORTS     AGE
factura   traefik   factura.lab.local   10.10.10.14   80, 443   12s
```

Sur lab-adm :

```bash
echo '10.10.10.14 factura.lab.local' | sudo tee -a /etc/hosts
curl -k https://factura.lab.local/            # factura front
curl -k https://factura.lab.local/api/factures
curl -k https://factura.lab.local/api/ ; curl -k https://factura.lab.local/api/
openssl s_client -connect 10.10.10.14:443 -servername factura.lab.local \
  </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
```

```text
[{"id": 1, "montant": 100}, {"id": 2, "montant": 200}, {"id": 3, ...}]
{"app": "factura-api", "version": "1.0", "pod": "factura-api-5c7d9f6b8-4hq2z",
 "db_ok": true}
{"app": "factura-api", "version": "1.0", "pod": "factura-api-5c7d9f6b8-tz8kp",
 "db_ok": true}
subject=CN = factura.lab.local
issuer=CN = factura.lab.local
notBefore=Sep 15 08:02:11 2026 GMT
notAfter=Sep 15 08:02:11 2027 GMT
```

Le nom du pod change d'un appel à l'autre : le Service distribue (mode
`iptables`, aléatoire, pas round-robin strict). Sans `-servername`, Traefik
servirait son certificat par défaut `TRAEFIK DEFAULT CERT`.

**6. QoS et consommation réelle.**

```bash
kubectl get pods -n factura \
  -o custom-columns=NOM:.metadata.name,QOS:.status.qosClass
kubectl top pod -n factura --containers
```

```text
NOM                           QOS
factura-api-5c7d9f6b8-4hq2z   Burstable
factura-api-5c7d9f6b8-tz8kp   Burstable
front-77c9d4b6f5-r2x6n        Burstable
postgres-0                    Burstable
POD                           NAME       CPU(cores)   MEMORY(bytes)
factura-api-5c7d9f6b8-4hq2z   api        2m           27Mi
factura-api-5c7d9f6b8-tz8kp   api        2m           26Mi
front-77c9d4b6f5-r2x6n        nginx      0m           4Mi
postgres-0                    postgres   4m           38Mi
```

Tous `Burstable` (requests ≠ limits, pas de limite CPU). L'API consomme
~27 Mi pour une limite de 128 Mi : marge ×4,7, c'est confortable sans être
du gaspillage (la limite ne réserve rien). On garde 128Mi ; on aurait pu
descendre à 96Mi. Pour un `Guaranteed`, il faudrait `limits.cpu` égal à
`requests.cpu` — inutile ici.

**7. NetworkPolicy.**

```yaml
# 70-networkpolicy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgres-depuis-api
  namespace: factura
spec:
  podSelector:
    matchLabels:
      app: postgres
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: factura-api
      ports:
        - protocol: TCP
          port: 5432
```

```bash
kubectl apply -f ~/lab26/k8s/70-networkpolicy.yaml
kubectl run -n factura -it --rm test --image=busybox:1.36 \
  --restart=Never -- nc -zv -w 3 postgres 5432
kubectl get pods -n factura -l app=factura-api        # toujours 1/1
```

```text
nc: postgres (10.42.0.18:5432): Connection timed out
pod "test" deleted
pod factura/test terminated (Error)
```

**8. Tout depuis zéro.**

```bash
kubectl delete ns factura                  # ~30 s, supprime aussi le PVC
date +%T
kubectl apply -f ~/lab26/k8s/
```

```text
namespace/factura created
configmap/factura-api-config created
secret/postgres-auth created
service/postgres created
statefulset.apps/postgres created
deployment.apps/factura-api created
service/factura-api created
configmap/front-config created
deployment.apps/front created
service/front created
ingress.networking.k8s.io/factura created
networkpolicy.networking.k8s.io/postgres-depuis-api created
The CronJob "sauvegarde-pg" is invalid: spec.schedule: Invalid value: ...
```

(La dernière ligne n'apparaît que si `60-cronjob-sauvegarde.yaml` est resté
à l'état de squelette, E26.7 non fait ; `apply` continue avec les autres
fichiers et rend un code de retour non nul.)

L'API reste `ImagePullBackOff` et l'Ingress répond en `TRAEFIK DEFAULT
CERT` : les deux Secrets créés à la main (`registre-lab`, `factura-tls`)
ont disparu avec le namespace. Solution : les mettre dans le dossier sous
forme de fichiers générés une fois :

```bash
kubectl create secret docker-registry registre-lab -n factura \
  --docker-server=10.10.10.14:5000 --docker-username=mathieu \
  --docker-password=labpass --dry-run=client -o yaml \
  > ~/lab26/k8s/12-secret-registre.yaml
kubectl create secret tls factura-tls -n factura \
  --cert=$HOME/lab26/tls/factura.crt --key=$HOME/lab26/tls/factura.key \
  --dry-run=client -o yaml > ~/lab26/k8s/13-secret-tls.yaml
chmod 0600 ~/lab26/k8s/1[123]-secret*.yaml
kubectl delete ns factura && kubectl apply -f ~/lab26/k8s/
until curl -sk --resolve factura.lab.local:443:10.10.10.14 -o /dev/null \
  -w '%{http_code}\n' https://factura.lab.local/api/factures | grep -q 200
do sleep 2; done; date +%T
```

Chronométré : 70 à 100 s, dominés par le démarrage de PostgreSQL
(`initdb`, ~20 s) puis la readiness de l'API (période 5 s). Ces fichiers
contiennent des secrets en clair : `.gitignore` ou, en production, SOPS /
Sealed Secrets / External Secrets (D26).

::: pourquoi
Trois mécanismes à retenir. **StatefulSet** : le pod s'appelle
`postgres-0`, son PVC `donnees-postgres-0`, et un redémarrage ou une mise à
jour recrée *ce* pod avec *ce* PVC : identité stable, contrairement à un
Deployment qui, avec `RollingUpdate`, lancerait un second pod sur le même
volume `ReadWriteOnce` (Pending ou corruption). Le Service headless
(`clusterIP: None`) sert à donner l'entrée DNS `postgres-0.postgres` et,
ici, l'entrée `postgres` qui résout **directement** l'IP du pod (pas de
VIP). **Probes** : la readiness sur `/pret` encode la dépendance à la base :
quand PostgreSQL tombe, l'API sort des Endpoints sans redémarrer, nginx
reçoit 502 — c'est l'échec « propre ». La liveness sur `/sante` ne teste
que le processus. **NetworkPolicy** : un `podSelector` non vide avec
`policyTypes: [Ingress]` passe le pod en *deny by default* en entrée ;
seules les règles listées ouvrent. k3s l'applique via son contrôleur de
policies embarqué (flannel seul ne le ferait pas).
:::

::: piege
La NetworkPolicy casse E26.7 : le Job `pg_dump` n'a pas le label
`app=factura-api`. Ajoute un second `podSelector` (`app: sauvegarde`) et
pose ce label sur le template du Job — ou tu découvriras la panne à 02:30.
Autre piège : `kubectl apply -f dossier/` applique dans l'**ordre
alphabétique** des noms de fichiers, d'où les préfixes `00-`, `10-`… ; un
Deployment appliqué avant son namespace échoue. Enfin `local-path` a
`reclaimPolicy: Delete` : supprimer le namespace supprime les données de la
base, définitivement.
:::

---

### **L26.3** — *Session de debug : cinq manifestes, cinq pannes*

*`kubectl apply -f ~/lab26/k8s/casse/` puis, pour chaque Deployment, trouver
le symptôme, la commande révélatrice, le message, la cause, le correctif ;
finir par un OOMKilled volontaire.*

Point de départ, toujours le même :

```bash
kubectl apply -f ~/lab26/k8s/casse/
kubectl get pods -n casse
kubectl get events -n casse --sort-by=.lastTimestamp | tail -20
```

```text
NAME                         READY   STATUS             RESTARTS      AGE
api-crash-6d8f7b9c5-k2m4p    0/1     CrashLoopBackOff   3 (25s ago)   90s
api-dns-7f9c8d6b4-x8t2q      0/1     Running            0             90s
api-image-5b7d9f8c6-n4w7z    0/1     ImagePullBackOff   0             90s
gourmand-8c6f5d7b9-p3r5s     0/1     Pending            0             90s
```

**1. `gourmand` — Pending, deux causes.**

```bash
kubectl describe pod -n casse -l app=gourmand | tail -5
```

```text
Warning  FailedScheduling  default-scheduler  0/1 nodes are available:
  1 node(s) didn't match Pod's node affinity/selector. preemption: 0/1
  nodes are available: 1 Preemption is not helpful for scheduling.
```

Cause 1 : `nodeSelector: {disque: ssd}` et aucun nœud n'a ce label
(`kubectl get nodes --show-labels`). On retire le `nodeSelector` du
manifeste (« sans toucher au nœud » : pas de `kubectl label node`). Nouvel
apply, nouveau message :

```text
Warning  FailedScheduling  default-scheduler  0/1 nodes are available:
  1 Insufficient cpu, 1 Insufficient memory.
```

Cause 2 : `requests` de 8 CPU / 16 Gi sur un nœud de 2 CPU / 4 Go
(`kubectl describe node lab-ops | grep -A5 Allocatable`). Correctif :

```yaml
          resources:
            requests:
              cpu: 50m
              memory: 32Mi
            limits:
              memory: 64Mi
```

Le scheduler s'arrête au **premier** prédicat qui échoue et ne montre que
lui : c'est pour ça qu'on ne voit qu'une cause à la fois.

**2. `api-image` — ImagePullBackOff.**

```bash
kubectl describe pod -n casse -l app=api-image | grep -A3 'Failed'
```

```text
Warning  Failed  kubelet  Failed to pull image
  "10.10.10.14:5000/factura-api:1.0":
  failed to pull and unpack image "10.10.10.14:5000/factura-api:1.0":
  failed to resolve reference "10.10.10.14:5000/factura-api:1.0":
  unexpected status from HEAD request to
  http://10.10.10.14:5000/v2/factura-api/manifests/1.0: 401 Unauthorized
Warning  Failed  kubelet  Error: ErrImagePull
Normal   BackOff kubelet  Back-off pulling image "10.10.10.14:5000/...
```

`401` = le registre veut un mot de passe ; le kubelet n'en a pas pour ce
pod. Le Secret `registre-lab` existe dans `factura`, pas dans `casse` :

```bash
kubectl create secret docker-registry registre-lab -n casse \
  --docker-server=10.10.10.14:5000 \
  --docker-username=mathieu --docker-password=labpass
```

et dans `02-imagepull.yaml`, sous `spec:` du template :

```yaml
      imagePullSecrets:
        - name: registre-lab
```

Après apply, le nouveau pod tire l'image immédiatement (l'ancien restait en
backoff jusqu'à 5 min entre deux tentatives).

**3. `api-crash` — CrashLoopBackOff.**

```bash
kubectl logs -n casse -l app=api-crash --previous
kubectl describe pod -n casse -l app=api-crash | grep -A6 'Last State'
```

```text
ts=2026-09-15T09:41:02 niveau=info msg="demarrage" version=1.0 port=8080
  db=127.0.0.1:5432 mem_mb=0
FATAL: erreur interne simulee (FACTURA_CRASH_APRES)
    Last State:     Terminated
      Reason:       Error
      Exit Code:    1
      Started:      Mon, 15 Sep 2026 09:41:01 +0200
      Finished:     Mon, 15 Sep 2026 09:41:04 +0200
    Ready:          False
    Restart Count:  4
```

Cause : la variable `FACTURA_CRASH_APRES=3` fait sortir le processus en
code 1 après 3 s. On la retire du manifeste. Dans les événements, le
`Back-off restarting failed container` s'espace : 10 s, 20 s, 40 s, 80 s,
160 s, plafonné à 5 min, remis à zéro après 10 min de fonctionnement.

**4. `api-dns` — Running mais 0/1.**

```bash
kubectl describe pod -n casse -l app=api-dns | grep -A2 Readiness
kubectl run -n casse -it --rm dbg --image=busybox:1.36 --restart=Never \
  -- sh -c 'nslookup postgres; nslookup postgres.factura.svc.cluster.local'
```

```text
  Warning  Unhealthy  kubelet  Readiness probe failed: HTTP probe failed
    with statuscode: 503
Server:    10.43.0.10
** server can't find postgres.casse.svc.cluster.local: NXDOMAIN
Name:      postgres.factura.svc.cluster.local
Address 1: 10.42.0.18 postgres-0.postgres.factura.svc.cluster.local
```

Le nom court `postgres` est complété avec la liste `search` du pod,
qui commence par **son** namespace (`casse.svc.cluster.local`) : NXDOMAIN.
Correctif dans `04-dns.yaml` :

```yaml
          env:
            - name: DB_HOST
              value: "postgres.factura.svc.cluster.local"
```

Si la NetworkPolicy de L26.2 (étape 7) est en place, le pod reste `0/1`
malgré le bon nom : `/pret` répond encore `{"pret":false,"raison":"db"}`
parce que la policy n'autorise que les pods `app=factura-api` **du
namespace `factura`** (un `podSelector` seul ne matche jamais un autre
namespace). Ajoute une règle dans `70-networkpolicy.yaml` :

```yaml
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: casse
      ports:
        - protocol: TCP
          port: 5432
```

**5. `casse` (Ingress) — deux 404.**

```bash
curl -k --resolve casse.lab.local:443:10.10.10.14 \
  https://casse.lab.local/api/factures
```

```text
404 page not found
```

Ce corps en texte brut est celui de **Traefik** : aucune règle ne matche.
`pathType: Exact` avec `path: /api` ne matche que `/api`, pas
`/api/factures`. Premier correctif : `pathType: Prefix`. Nouvel appel :

```text
{"erreur":"route inconnue"}
```

Corps JSON : cette fois c'est **l'API** qui répond 404, car Traefik lui a
transmis `/api/factures` tel quel et elle ne connaît que `/factures`. Un
Ingress ne réécrit pas les chemins (contrairement au `proxy_pass .../` de
nginx). Correctif final, cohérent avec le critère de succès :

```yaml
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api-dns
                port:
                  number: 8080
```

`curl -k --resolve casse.lab.local:443:10.10.10.14
https://casse.lab.local/factures` → 200 et la liste des factures.
(L'alternative qui garde `/api` : une `Middleware` Traefik `stripPrefix`
référencée par l'annotation
`traefik.ingress.kubernetes.io/router.middlewares`.)

**6. OOMKilled volontaire.**

```bash
kubectl set env deploy/api-dns -n casse FACTURA_MEM_MB=200
kubectl set resources deploy/api-dns -n casse --limits=memory=64Mi
kubectl get pods -n casse -l app=api-dns -w
kubectl describe pod -n casse -l app=api-dns | grep -B2 -A4 OOMKilled
```

```text
api-dns-9d7c6b5f8-v2q8k   0/1   OOMKilled          1 (8s ago)    20s
api-dns-9d7c6b5f8-v2q8k   0/1   CrashLoopBackOff   2 (12s ago)   45s
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
```

137 = 128 + 9 (`SIGKILL`) : le noyau a tué le processus quand le cgroup a
dépassé 64 Mi ; l'application n'a rien pu logger. Remise en état :
`kubectl set env deploy/api-dns -n casse FACTURA_MEM_MB-` et
`--limits=memory=128Mi`, puis on reporte ces valeurs dans le manifeste.

**Le rapport `~/lab26/rapports/debug.md`** :

```markdown
| Objet | Symptôme | Commande / message | Cause -> correctif |
|---|---|---|---|
| gourmand | Pending | describe : node selector | nodeSelector ssd -> retiré |
| gourmand | Pending | describe : Insufficient cpu | 8 CPU/16Gi -> 50m/32Mi |
| api-image | ImagePullBackOff | describe : 401 | Secret absent -> créé |
| api-crash | CrashLoopBackOff | logs --previous : FATAL | CRASH_APRES retiré |
| api-dns | Running 0/1 | describe 503, nslookup | DB_HOST court -> FQDN |
| casse | 404 Traefik | curl : page not found | Exact -> Prefix |
| casse | 404 API | curl : route inconnue | /api non réécrit -> path / |
| api-dns | OOMKilled 137 | describe : OOMKilled | 64Mi < 200 Mo -> remis |
```

::: pourquoi
Chaque panne vit à un **étage** différent, et c'est l'étage qui dicte la
commande. `Pending` est une décision du scheduler : elle n'est que dans les
événements du pod (`describe`), il n'y a pas de conteneur, donc pas de
logs. `ImagePullBackOff` est un échec du kubelet avant le démarrage :
événements aussi, avec le code HTTP du registre. `CrashLoopBackOff` est un
processus qui s'est exécuté puis a quitté : la vérité est dans les logs
de l'instance **précédente** (`--previous`), l'actuelle n'a peut-être pas
encore écrit. `0/1` durable est un kubelet qui a décidé que le pod n'est
pas prêt : événement `Unhealthy` + la raison HTTP, et on remonte la
dépendance (ici DNS). Les 404 se distinguent par **qui** répond : Traefik
(texte brut, aucune route) ou l'application (son propre format). OOMKilled
est le noyau : ni logs ni événement applicatif, seulement `Last State`.
:::

::: piege
`kubectl edit`/`set env` corrige l'objet, pas le fichier : au prochain
`apply -f casse/`, tout recasse. C'est le sens de « corriger les
manifestes ». `kubectl logs` sans `--previous` sur un CrashLoop montre
souvent le démarrage de l'instance en cours, rassurant et inutile. Et un
`nodeSelector` qui ne matche pas produit exactement le même `Pending` qu'un
*taint* : lis le message, il dit lequel (`untolerated taint` vs `node
affinity/selector`).
:::

---

### **L26.4** — *Prometheus et Alertmanager : scraper les cinq VM et l'API*

*Ticket CHG-4410 : `node_exporter` sur les quatre autres VM, pile Compose
démarrée, exporters nginx et PostgreSQL, sondes blackbox, découverte des
pods k3s, règles d'enregistrement, onze règles d'alerte, routage page /
ticket avec inhibition, test de bout en bout chronométré.*

**1. `node_exporter` partout.** Depuis lab-adm :

```bash
scp mathieu@10.10.10.14:lab26/bin/installer-node-exporter.sh /tmp/
sudo bash /tmp/installer-node-exporter.sh                 # lab-adm
for ip in 10.10.10.11 10.10.10.12 10.10.10.13; do
  scp /tmp/installer-node-exporter.sh mathieu@$ip:/tmp/
  ssh -t mathieu@$ip sudo bash /tmp/installer-node-exporter.sh
done
ssh mathieu@10.10.10.13 sudo firewall-cmd --list-ports    # 9100/tcp
```

Depuis lab-ops :

```bash
for ip in 10 11 12 13 14; do
  printf '10.10.10.%s : ' $ip
  curl -s -m 3 http://10.10.10.$ip:9100/metrics | grep -c '^node_' 
done
```

```text
10.10.10.10 : 612
10.10.10.11 : 618
10.10.10.12 : 640
10.10.10.13 : 597
10.10.10.14 : 655
```

**2. La pile, et un rechargement à chaud.**

```bash
cd /opt/observabilite && docker compose up -d
docker compose ps --format 'table {{.Name}}\t{{.Status}}'
curl -s http://localhost:9090/api/v1/targets \
  | jq -r '.data.activeTargets[]
           | "\(.labels.job)\t\(.labels.instance)\t\(.health)"'
```

```text
node        lab-adm     up
node        lab-web     up
node        lab-db      up
node        lab-rhel    up
node        lab-ops     up
prometheus  localhost:9090  up
```

Syntaxe cassée puis réparée, sans redémarrer :

```bash
sed -i 's/^scrape_configs:/scrape_configs/' prometheus/prometheus.yml
docker compose exec prometheus promtool check config \
  /etc/prometheus/prometheus.yml
```

```text
Checking /etc/prometheus/prometheus.yml
  FAILED: parsing YAML file /etc/prometheus/prometheus.yml: yaml: line 17:
  could not find expected ':'
```

```bash
sed -i 's/^scrape_configs$/scrape_configs:/' prometheus/prometheus.yml
docker compose exec prometheus promtool check config \
  /etc/prometheus/prometheus.yml    # SUCCESS: ... is valid ... config file
curl -X POST http://localhost:9090/-/reload
docker compose logs --tail=3 prometheus   # Completed loading of config...
```

Un rechargement avec une config invalide est **refusé** (HTTP 500, l'ancienne
reste active) : `curl -i` pour voir le code, et la métrique
`prometheus_config_last_reload_successful` passe à 0.

**3. Exporters nginx et PostgreSQL.** Sur lab-web :

```bash
sudo tee /etc/nginx/conf.d/stub_status.conf >/dev/null <<'EOF'
server {
    listen 127.0.0.1:8080;
    location /stub_status {
        stub_status;
        allow 127.0.0.1;
        deny all;
    }
}
EOF
sudo nginx -t && sudo systemctl reload nginx
curl -s http://127.0.0.1:8080/stub_status
sudo apt install -y prometheus-nginx-exporter
sudo tee /etc/default/prometheus-nginx-exporter >/dev/null <<'EOF'
ARGS="--nginx.scrape-uri=http://127.0.0.1:8080/stub_status"
EOF
sudo systemctl restart prometheus-nginx-exporter
curl -s http://127.0.0.1:9113/metrics | grep nginx_connections_active
```

Sur lab-db :

```bash
sudo -u postgres psql <<'EOF'
CREATE ROLE monitoring LOGIN PASSWORD 'monpass';
GRANT pg_monitor TO monitoring;
EOF
sudo apt install -y prometheus-postgres-exporter
sudo tee /etc/default/prometheus-postgres-exporter >/dev/null <<'EOF'
DATA_SOURCE_NAME="postgresql://monitoring:monpass@127.0.0.1:5432/\
postgres?sslmode=disable"
EOF
sudo systemctl restart prometheus-postgres-exporter
curl -s http://127.0.0.1:9187/metrics | grep '^pg_up'      # pg_up 1
```

Sur lab-ops, `prometheus.yml` reçoit :

```yaml
  - job_name: nginx
    static_configs:
      - targets: ["10.10.10.11:9113"]
        labels: {instance: lab-web}

  - job_name: postgres
    static_configs:
      - targets: ["10.10.10.12:9187"]
        labels: {instance: lab-db}
```

**4. Blackbox.** `/etc/hosts` de lab-ops : `10.10.10.14 factura.lab.local`.
Dans `compose.yaml`, service `blackbox` :

```yaml
    extra_hosts:
      - "factura.lab.local:10.10.10.14"
```

```yaml
  - job_name: blackbox-http
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - http://10.10.10.11/
          - https://factura.lab.local/api/sante
          - http://10.10.10.14:3000/api/health
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox:9115

  - job_name: blackbox-icmp
    metrics_path: /probe
    params:
      module: [icmp]
    static_configs:
      - targets: ["10.10.10.10", "10.10.10.11", "10.10.10.12",
                  "10.10.10.13", "10.10.10.14"]
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox:9115
```

```bash
docker compose up -d blackbox && curl -X POST localhost:9090/-/reload
curl -s 'localhost:9090/api/v1/query?query=probe_success' \
  | jq -r '.data.result[] | "\(.metric.job)\t\(.metric.instance)\t\(.value[1])"'
```

```text
blackbox-http   http://10.10.10.11/                       1
blackbox-http   https://factura.lab.local/api/sante       1
blackbox-http   http://10.10.10.14:3000/api/health        1
blackbox-icmp   10.10.10.10                               1
...
```

**5. Découverte des pods k3s.** `~/lab26/k8s/monitoring-rbac.yaml` :

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-lecture
rules:
  - apiGroups: [""]
    resources: [nodes, nodes/metrics, services, endpoints, pods]
    verbs: [get, list, watch]
  - nonResourceURLs: ["/metrics"]
    verbs: [get]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus-lecture
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus-lecture
subjects:
  - kind: ServiceAccount
    name: prometheus
    namespace: monitoring
---
apiVersion: v1
kind: Secret
metadata:
  name: prometheus-token
  namespace: monitoring
  annotations:
    kubernetes.io/service-account.name: prometheus
type: kubernetes.io/service-account-token
```

```bash
kubectl apply -f ~/lab26/k8s/monitoring-rbac.yaml
kubectl get secret prometheus-token -n monitoring \
  -o jsonpath='{.data.token}' | base64 -d \
  > /opt/observabilite/prometheus/k8s-token
kubectl get secret prometheus-token -n monitoring \
  -o jsonpath='{.data.ca\.crt}' | base64 -d \
  > /opt/observabilite/prometheus/k8s-ca.crt
# le conteneur prometheus tourne en « nobody » (65534) : sans ce chown,
# un 0600 appartenant à mathieu rend le token illisible côté conteneur
sudo chown 65534:65534 /opt/observabilite/prometheus/k8s-token
sudo chmod 0400 /opt/observabilite/prometheus/k8s-token
kubectl auth can-i list pods -A \
  --as=system:serviceaccount:monitoring:prometheus       # yes
```

```yaml
  - job_name: k8s-pods
    honor_labels: true
    kubernetes_sd_configs:
      - role: pod
        api_server: https://10.10.10.14:6443
        authorization:
          credentials_file: /etc/prometheus/k8s-token
        tls_config:
          ca_file: /etc/prometheus/k8s-ca.crt
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"
      - source_labels: [__meta_kubernetes_pod_phase]
        action: keep
        regex: Running
      - source_labels: [__address__,
                        __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
```

```bash
curl -X POST localhost:9090/-/reload
curl -s 'localhost:9090/api/v1/query?query=up{job="k8s-pods"}' \
  | jq -r '.data.result[]
           | "\(.metric.namespace)\t\(.metric.pod)\t\(.value[1])"'
```

```text
factura     factura-api-5c7d9f6b8-4hq2z      1
factura     factura-api-5c7d9f6b8-tz8kp      1
monitoring  ksm-kube-state-metrics-6f8b7d9c5-x4r2t   1
```

**6. Règles d'enregistrement** — `prometheus/rules/lab-enregistrement.yml` :

```yaml
groups:
  - name: lab-enregistrement
    interval: 30s
    rules:
      - record: instance:node_cpu_utilisation:ratio_5m
        expr: >
          1 - avg by (instance)
            (rate(node_cpu_seconds_total{mode="idle"}[5m]))
      - record: instance:node_memory_utilisation:ratio
        expr: >
          1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes
      - record: job:factura_http_requests:rate5m
        expr: sum by (job, code) (rate(factura_http_requests_total[5m]))
      - record: job:factura_http_errors:ratio_rate5m
        expr: >
          sum by (job) (rate(factura_http_requests_total{code=~"5.."}[5m]))
            / sum by (job) (rate(factura_http_requests_total[5m]))
      - record: job:factura_http_request_duration_seconds:p95_5m
        expr: >
          histogram_quantile(0.95, sum by (job, path, le)
            (rate(factura_http_request_duration_seconds_bucket[5m])))
```

La cinquième règle n'est pas demandée mais sert à `ApiLatenceP95` et aux
tableaux de bord : une expression coûteuse évaluée une fois toutes les
30 s plutôt qu'à chaque rafraîchissement de Grafana.

**7. Règles d'alerte** — `prometheus/rules/lab-alertes.yml` :

```yaml
groups:
  - name: lab-alertes
    rules:
      - alert: InstanceDown
        expr: up{job!="k8s-pods"} == 0
        for: 2m
        labels:
          severity: page
        annotations:
          summary: "{{ $labels.instance }} ne répond plus au scrape"
          description: >-
            La cible {{ $labels.instance }} du job {{ $labels.job }}
            est DOWN depuis plus de 2 minutes.
          runbook_url: https://wiki.lab.local/runbooks/instance-down

      - alert: CpuEleve
        expr: instance:node_cpu_utilisation:ratio_5m > 0.85
        for: 10m
        labels:
          severity: ticket
        annotations:
          summary: >-
            CPU à {{ $value | humanizePercentage }} sur
            {{ $labels.instance }}
          description: >-
            Utilisation CPU moyenne sur 5 min supérieure à 85 % depuis 10 min
            sur {{ $labels.instance }} ({{ $value | humanizePercentage }}).
          runbook_url: https://wiki.lab.local/runbooks/cpu-eleve

      - alert: MemoireBasse
        expr: instance:node_memory_utilisation:ratio > 0.90
        for: 5m
        labels:
          severity: ticket
        annotations:
          summary: "Moins de 10 % de mémoire dispo sur {{ $labels.instance }}"
          description: >-
            Mémoire utilisée à {{ $value | humanizePercentage }} sur
            {{ $labels.instance }} depuis 5 min.
          runbook_url: https://wiki.lab.local/runbooks/memoire-basse

      - alert: DisquePleinDans24h
        expr: >
          predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[6h],
                         24 * 3600) < 0
          and node_filesystem_avail_bytes{mountpoint="/"} > 0
        for: 30m
        labels:
          severity: ticket
        annotations:
          summary: "/ de {{ $labels.instance }} sera plein dans moins de 24 h"
          description: >-
            Au rythme des 6 dernières heures, / de {{ $labels.instance }}
            est plein dans moins de 24 h.
          runbook_url: https://wiki.lab.local/runbooks/disque-plein

      - alert: DisquePresquePlein
        expr: >
          1 - node_filesystem_avail_bytes{mountpoint="/"}
              / node_filesystem_size_bytes{mountpoint="/"} > 0.90
        for: 5m
        labels:
          severity: page
        annotations:
          summary: >-
            / de {{ $labels.instance }} à
            {{ $value | humanizePercentage }}
          description: >-
            Le système de fichiers / de {{ $labels.instance }} dépasse 90 %
            ({{ $value | humanizePercentage }}).
          runbook_url: https://wiki.lab.local/runbooks/disque-plein

      - alert: ApiErreurs5xx
        expr: job:factura_http_errors:ratio_rate5m > 0.05
        for: 5m
        labels:
          severity: page
        annotations:
          summary: "factura-api : {{ $value | humanizePercentage }} de 5xx"
          description: >-
            Le ratio de réponses 5xx de factura-api dépasse 5 % depuis 5 min
            ({{ $value | humanizePercentage }}).
          runbook_url: https://wiki.lab.local/runbooks/api-erreurs

      - alert: ApiLatenceP95
        expr: >
          job:factura_http_request_duration_seconds:p95_5m{path="/factures"}
            > 0.5
        for: 10m
        labels:
          severity: ticket
        annotations:
          summary: "p95 de /factures à {{ $value | humanizeDuration }}"
          description: >-
            Le p95 de latence de /factures dépasse 500 ms depuis 10 min
            ({{ $value | humanizeDuration }}).
          runbook_url: https://wiki.lab.local/runbooks/api-latence

      - alert: SondeEchec
        expr: probe_success == 0
        for: 3m
        labels:
          severity: page
        annotations:
          summary: "Sonde {{ $labels.job }} en échec sur {{ $labels.instance }}"
          description: >-
            La sonde {{ $labels.job }} vers {{ $labels.instance }} échoue
            depuis 3 min.
          runbook_url: https://wiki.lab.local/runbooks/sonde-echec

      - alert: CertificatExpire
        expr: probe_ssl_earliest_cert_expiry - time() < 14 * 24 * 3600
        for: 1h
        labels:
          severity: ticket
        annotations:
          summary: "Certificat de {{ $labels.instance }} expire bientôt"
          description: >-
            Le certificat servi par {{ $labels.instance }} expire dans
            {{ $value | humanizeDuration }}.
          runbook_url: https://wiki.lab.local/runbooks/certificat

      - alert: PodEnCrashLoop
        expr: >
          kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}
            == 1
        for: 5m
        labels:
          severity: page
        annotations:
          summary: >-
            {{ $labels.namespace }}/{{ $labels.pod }} en CrashLoopBackOff
          description: >-
            Le conteneur {{ $labels.container }} du pod
            {{ $labels.namespace }}/{{ $labels.pod }} redémarre en boucle
            depuis 5 min.
          runbook_url: https://wiki.lab.local/runbooks/crashloop

      - alert: PostgresDown
        expr: pg_up == 0
        for: 2m
        labels:
          severity: page
        annotations:
          summary: "PostgreSQL injoignable sur {{ $labels.instance }}"
          description: >-
            L'exporter de {{ $labels.instance }} ne parvient plus à se
            connecter à PostgreSQL depuis 2 min.
          runbook_url: https://wiki.lab.local/runbooks/postgres-down
```

```bash
docker compose exec prometheus promtool check rules \
  /etc/prometheus/rules/lab-enregistrement.yml \
  /etc/prometheus/rules/lab-alertes.yml
curl -X POST localhost:9090/-/reload
curl -s localhost:9090/api/v1/rules | jq -r '.data.groups[].name'
```

```text
Checking /etc/prometheus/rules/lab-enregistrement.yml
  SUCCESS: 5 rules found
Checking /etc/prometheus/rules/lab-alertes.yml
  SUCCESS: 11 rules found
exemple
lab-enregistrement
lab-alertes
```

**8. Alertmanager** — `/opt/observabilite/alertmanager/alertmanager.yml` :

```yaml
global:
  resolve_timeout: 5m

route:
  receiver: ticket
  group_by: ["alertname", "instance"]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - matchers: ['severity="page"']
      receiver: page
      group_wait: 30s
      repeat_interval: 1h
    - matchers: ['severity="ticket"']
      receiver: ticket
      repeat_interval: 24h

receivers:
  - name: ticket
    webhook_configs:
      - url: http://webhook:9099/ticket
        send_resolved: true
  - name: page
    webhook_configs:
      - url: http://webhook:9099/page
        send_resolved: true

inhibit_rules:
  - source_matchers: ['alertname="InstanceDown"']
    target_matchers: ['severity="ticket"']
    equal: ["instance"]
```

```bash
docker compose exec alertmanager amtool check-config \
  /etc/alertmanager/alertmanager.yml
curl -X POST localhost:9093/-/reload
docker compose exec alertmanager amtool config routes test \
  --config.file=/etc/alertmanager/alertmanager.yml \
  severity=page alertname=InstanceDown            # page
```

**9. Test de bout en bout.** Comme `CpuEleve` se calcule à partir des
métriques de lab-rhel, il ne peut pas **naître** pendant qu'elles n'arrivent
plus : on lance d'abord la charge, on attend `CpuEleve` en firing (10 min),
puis on coupe l'exporter.

```bash
# sur lab-rhel : charge CPU (2 vCPU)
ssh mathieu@10.10.10.13 'for i in 1 2; do nohup yes >/dev/null 2>&1 & done'
# ~11 min plus tard, sur lab-ops : CpuEleve firing -> [TICKET] dans webhook
date +%T ; ssh mathieu@10.10.10.13 sudo systemctl stop node_exporter
watch -n 5 'curl -s localhost:9090/api/v1/alerts | jq -r ".data.alerts[] \
  | \"\(.labels.alertname)\t\(.labels.instance)\t\(.state)\""'
docker compose logs -f webhook
```

```text
10:40:00  stop node_exporter
10:40:19  InstanceDown lab-rhel  pending   (scrape raté à :14, éval à :19)
10:42:19  InstanceDown lab-rhel  firing
10:42:49  [PAGE] firing InstanceDown instance=lab-rhel  (group_wait 30 s)
          CpuEleve lab-rhel : firing dans Prometheus, "inhibited" dans
          l'UI Alertmanager (http://10.10.10.14:9093), rien dans webhook
10:45:30  CpuEleve devient inactive (plus de série : rate() sans échantillon)
```

```bash
docker compose exec alertmanager amtool silence add instance=lab-rhel \
  --duration=30m --author=mathieu --comment="test CHG-4410"
ssh mathieu@10.10.10.13 'sudo systemctl start node_exporter; pkill yes'
```

```text
10:48:00  start node_exporter ; up=1 au scrape suivant
10:48:19  InstanceDown inactive dans Prometheus ; Prometheus envoie resolved
10:48:19  silence actif : la notification resolved n'est pas envoyée
11:18:00  silence expiré ; plus rien à envoyer (l'alerte est résolue depuis
          30 min) -> pas de "resolved" dans webhook
```

Sans le silence, le `[PAGE] resolved` serait arrivé au tick suivant de
`group_interval` (≤ 5 min après la résolution). Tout ça va dans
`~/lab26/rapports/alerting.md` avec les horodatages réels.

::: pourquoi
Le chemin d'une alerte est **quatre horloges** en cascade : le
`scrape_interval` (15 s : `up` passe à 0), l'`evaluation_interval` (15 s :
la règle voit `up == 0`, état *pending*), le `for` (2 min : *firing*, et
seulement là Prometheus pousse l'alerte à Alertmanager), puis
`group_wait` (30 s : Alertmanager attend d'éventuelles alertes du même
groupe avant la première notification). D'où ~2 min 50 entre la panne et
le webhook : chaque étage est un compromis bruit/réactivité, et on doit
savoir les additionner pour promettre un délai. L'inhibition ne
« supprime » rien : l'alerte reste dans Alertmanager, marquée *inhibited*,
et sera notifiée si la source disparaît avant elle. Le `relabel_configs` de
blackbox est le motif canonique « l'adresse devient un paramètre » :
`__address__` (ce que Prometheus contacte) est remplacé par l'exporter, et
la cible d'origine devient `__param_target` (donc `?target=` de l'URL) et
`instance` (le label visible). Pour k8s, `honor_labels: true` est
indispensable : kube-state-metrics **expose** déjà des labels `namespace`
et `pod` (ceux des objets qu'il décrit) ; sans `honor_labels`, Prometheus
les renommerait `exported_namespace`/`exported_pod` pour imposer ceux de
la cible — et `PodEnCrashLoop` désignerait le pod de kube-state-metrics.
:::

::: piege
`InstanceDown` sur `up == 0` sans filtre attrape aussi les pods du job
`k8s-pods` pendant un rollout (un pod qui s'arrête = cible DOWN 2 min) :
d'où `job!="k8s-pods"`. Le fichier de règles est relu au `reload` mais une
erreur de **syntaxe** fait échouer tout le rechargement : `promtool check
rules` d'abord, toujours. Une alerte dont l'expression devient vide (série
absente) passe silencieusement à *inactive* — c'est le sens du `absent()`
de `00-exemple.yml`. Enfin, `group_by: [alertname, instance]` sépare les
notifications par instance : pratique pour l'inhibition `equal:
[instance]`, mais si 20 VM tombent ensemble, tu reçois 20 pages — un
`group_by: [alertname]` sur la route `page` serait plus humain.
:::

---

### **L26.5** — *Grafana et Loki : voir, corréler, provisionner*

*Ticket CHG-4411 : vérifier le provisioning, importer 1860, créer par fichier `Lab`* `— API factura` *(variable `pod`, cinq panneaux), ajouter le flux Loki des pods k3s dans Alloy, corréler ratio 5xx et logs `code`*`=500`*, ajouter un panneau Logs et une state timeline\* de l'alerte.\**

**1. Provisioning.**

```bash
curl -s -u admin:labpass http://10.10.10.14:3000/api/datasources \
  | jq -r '.[] | "\(.name)\t\(.type)\t\(.url)"'
curl -s -u admin:labpass 'http://10.10.10.14:3000/api/search?type=dash-db' \
  | jq -r '.[] | "\(.folderTitle)\t\(.title)"'
```

```text
Prometheus    prometheus    http://prometheus:9090
Loki          loki          http://loki:3100
Alertmanager  alertmanager  http://alertmanager:9093
Lab   Lab — Nœuds
```

Tel que livré, `provisioning/dashboards/lab.yml` a `allowUiUpdates: true` :
Grafana **accepte** la sauvegarde depuis l'interface… dans sa base SQLite
(volume `grafana-data`), pas dans `noeuds.json` monté en lecture seule. À
la prochaine modification du fichier (ou à la reconstruction du volume),
le fichier gagne et la modification disparaît. Pour un cahier des charges
« tout depuis des fichiers, sans clic », on passe `allowUiUpdates: false` :
Grafana affiche alors *Cannot save provisioned dashboard* et propose *Copy
JSON to clipboard*, ce qui force à reporter la modification dans le
fichier. C'est le réglage retenu ici (`docker compose restart grafana`).

**2. Import de *Node Exporter Full* (1860).** *Dashboards → New → Import*,
ID `1860`, source `Prometheus`. Trois panneaux lisibles : *CPU Basic*
(`sum by (mode) (rate(node_cpu_seconds_total{instance="$node"}[$__rate_interval]))`),
*Memory Basic* (`node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes`
sur `$node`), *Disk Space Used Basic* (`node_filesystem_size_bytes -
node_filesystem_avail_bytes` par `mountpoint`). Panneaux vides : la ligne
*Systemd* (le collecteur `systemd` du paquet Ubuntu est désactivé, aucune
série `node_systemd_*`) et ceux qui reconstruisent l'adresse de la cible
sous la forme `instance=~"$node:$port"` : le tableau suppose `instance` =
`ip:port` alors que le lab l'a relabellisé en `lab-web`, la regex qui
sépare hôte et port ne trouve rien. Le remède serait de garder `instance`
brut et de porter le nom dans un label `nodename`/`host` — ou d'éditer les
variables `node` et `port` du tableau importé.

**3. `Lab — API factura` par fichier.** `~/lab26/grafana/api.json` (copié
dans `/opt/observabilite/grafana/dashboards/api.json`), version finale avec
les deux panneaux de l'étape 6 :

```json
{
 "uid": "lab-api-factura",
 "title": "Lab — API factura",
 "tags": ["lab", "factura"],
 "timezone": "browser",
 "schemaVersion": 39,
 "version": 1,
 "refresh": "30s",
 "time": {"from": "now-1h", "to": "now"},
 "templating": {"list": [{
  "name": "pod", "type": "query",
  "datasource": {"type": "prometheus", "uid": "prometheus"},
  "query": "label_values(factura_http_requests_total, pod)",
  "refresh": 2, "includeAll": true, "multi": true,
  "current": {"text": "All", "value": "$__all"}
 }]},
 "panels": [
  {"id": 1, "type": "timeseries", "title": "Requêtes/s par code",
   "gridPos": {"x": 0, "y": 0, "w": 12, "h": 8},
   "datasource": {"type": "prometheus", "uid": "prometheus"},
   "targets": [{"refId": "A", "legendFormat": "{{code}}",
    "expr": "sum by (code) (rate(factura_http_requests_total{pod=~\"$pod\"}[5m]))"}],
   "fieldConfig": {"defaults": {"unit": "reqps",
    "custom": {"stacking": {"mode": "normal"}, "fillOpacity": 40}},
    "overrides": []}},
  {"id": 2, "type": "timeseries", "title": "Ratio 5xx (5 min)",
   "gridPos": {"x": 12, "y": 0, "w": 12, "h": 8},
   "datasource": {"type": "prometheus", "uid": "prometheus"},
   "targets": [{"refId": "A", "legendFormat": "5xx",
    "expr": "job:factura_http_errors:ratio_rate5m"}],
   "fieldConfig": {"defaults": {"unit": "percentunit", "min": 0, "max": 1,
    "custom": {"thresholdsStyle": {"mode": "line"}},
    "thresholds": {"mode": "absolute", "steps": [
     {"color": "green", "value": null},
     {"color": "orange", "value": 0.01},
     {"color": "red", "value": 0.05}]}}, "overrides": []}},
  {"id": 3, "type": "timeseries", "title": "p95 latence /factures",
   "gridPos": {"x": 0, "y": 8, "w": 12, "h": 8},
   "datasource": {"type": "prometheus", "uid": "prometheus"},
   "targets": [{"refId": "A", "legendFormat": "p95",
    "expr": "job:factura_http_request_duration_seconds:p95_5m{path=\"/factures\"}"}],
   "fieldConfig": {"defaults": {"unit": "s"}, "overrides": []}},
  {"id": 4, "type": "stat", "title": "Pods Ready",
   "gridPos": {"x": 12, "y": 8, "w": 6, "h": 4},
   "datasource": {"type": "prometheus", "uid": "prometheus"},
   "targets": [{"refId": "A", "expr":
    "sum(kube_pod_status_ready{condition=\"true\",pod=~\"factura-api.*\"})"}],
   "fieldConfig": {"defaults": {"thresholds": {"mode": "absolute", "steps": [
     {"color": "red", "value": null},
     {"color": "orange", "value": 1},
     {"color": "green", "value": 2}]}}, "overrides": []}},
  {"id": 5, "type": "stat", "title": "Redémarrages (1 h)",
   "gridPos": {"x": 18, "y": 8, "w": 6, "h": 4},
   "datasource": {"type": "prometheus", "uid": "prometheus"},
   "targets": [{"refId": "A", "expr":
"sum(increase(kube_pod_container_status_restarts_total{container=\"api\"}[1h]))"
   }],
   "fieldConfig": {"defaults": {"thresholds": {"mode": "absolute", "steps": [
     {"color": "green", "value": null},
     {"color": "red", "value": 1}]}}, "overrides": []}},
  {"id": 6, "type": "state-timeline", "title": "Alerte ApiErreurs5xx",
   "gridPos": {"x": 12, "y": 12, "w": 12, "h": 4},
   "datasource": {"type": "prometheus", "uid": "prometheus"},
   "targets": [{"refId": "A", "legendFormat": "{{alertstate}}",
    "expr": "ALERTS{alertname=\"ApiErreurs5xx\"}"}],
   "fieldConfig": {"defaults": {}, "overrides": []}},
  {"id": 7, "type": "logs", "title": "Logs de l'API",
   "gridPos": {"x": 0, "y": 16, "w": 24, "h": 10},
   "datasource": {"type": "loki", "uid": "loki"},
   "targets": [{"refId": "A",
    "expr": "{namespace=\"factura\", pod=~\"$pod\"} | logfmt"}],
   "options": {"showTime": true, "wrapLogMessage": true,
    "sortOrder": "Descending"}}
 ]
}
```

```bash
python3 -m json.tool ~/lab26/grafana/api.json >/dev/null && echo JSON OK
cp ~/lab26/grafana/api.json /opt/observabilite/grafana/dashboards/
cd /opt/observabilite && docker compose restart grafana
curl -s -u admin:labpass 'http://10.10.10.14:3000/api/search?query=factura' \
  | jq -r '.[] | "\(.folderTitle)\t\(.title)\t\(.uid)"'
```

```text
Lab   Lab — API factura   lab-api-factura
```

(Le redémarrage n'est même pas nécessaire : le provider relit le dossier
toutes les 10 s, `updateIntervalSeconds` par défaut.)

**4. Loki : le flux des pods k3s.** Ajout dans
`/opt/observabilite/alloy/config.alloy` :

```text
local.file_match "pods_k3s" {
  path_targets = [{
    "__path__" = "/var/log/pods/*/*/*.log",
    "job"      = "k8s-pods",
    "host"     = "lab-ops",
  }]
}

discovery.relabel "pods_k3s" {
  targets = local.file_match.pods_k3s.targets
  rule {
    source_labels = ["__path__"]
    regex         = "/var/log/pods/([^_]+)_([^_]+)_[^/]+/([^/]+)/.*"
    target_label  = "namespace"
    replacement   = "$1"
  }
  rule {
    source_labels = ["__path__"]
    regex         = "/var/log/pods/([^_]+)_([^_]+)_[^/]+/([^/]+)/.*"
    target_label  = "pod"
    replacement   = "$2"
  }
  rule {
    source_labels = ["__path__"]
    regex         = "/var/log/pods/([^_]+)_([^_]+)_[^/]+/([^/]+)/.*"
    target_label  = "container"
    replacement   = "$3"
  }
}

loki.source.file "pods_k3s" {
  targets    = discovery.relabel.pods_k3s.output
  forward_to = [loki.process.pods_k3s.receiver]
}

loki.process "pods_k3s" {
  stage.cri {}
  forward_to = [loki.write.local.receiver]
}
```

```bash
docker compose restart alloy
docker compose logs --tail=5 alloy            # pas de "permission denied"
curl -s 'http://10.10.10.14:3100/loki/api/v1/label/job/values' | jq -c .data
curl -s 'http://10.10.10.14:3100/loki/api/v1/label/namespace/values' \
  | jq -c .data
```

```text
["k8s-pods","systemd-journal","varlogs"]
["casse","factura","kube-system","monitoring"]
```

Si Alloy affiche `permission denied` sur `/var/log/pods`, les fichiers de
containerd sont en `0640 root` : ajouter `user: "0"` au service `alloy`
du Compose. Dans Explore, `{namespace="factura"}` montre les lignes logfmt
de l'API et celles de nginx et PostgreSQL. `stage.cri {}` retire le
préfixe `2026-09-15T09:41:02.123Z stdout F` du format containerd.

**5. Corrélation.**

```bash
~/lab26/bin/charge-api.sh https://factura.lab.local/api/factures 600 &
sleep 180
kubectl set env deploy/factura-api -n factura FACTURA_TAUX_ERREUR=0.3
```

Explore, *Split* : en haut Prometheus,
`job:factura_http_errors:ratio_rate5m` ; en bas Loki,
`{namespace="factura", container="api"} | logfmt | code="500"`, plage
*Last 15 minutes* synchronisée (icône de chaîne). Ce qu'on voit, à
consigner dans `~/lab26/rapports/grafana.md` : les lignes `code=500`
apparaissent **au moment** du rollout (nouvelles valeurs de `pod` dans les
logs : `set env` a recréé les pods) ; le ratio en haut, lui, met ~2 min à
grimper vers 0,3 parce que `rate[5m]` lisse — et il redescendra 5 min
après la correction. Un `{namespace="factura"} |= "OOM"` ou
`|= "Traceback"` dans le même écran sert pour d'autres incidents.

```bash
kubectl set env deploy/factura-api -n factura FACTURA_TAUX_ERREUR=0
```

**6. Panneaux Logs et State timeline.** Déjà dans le JSON ci-dessus
(`id` 6 et 7). La métrique `ALERTS{alertname="ApiErreurs5xx"}` vaut 1 avec
un label `alertstate` (`pending` puis `firing`) ; la *state timeline*
colore les segments par valeur de légende. Si l'exercice 5 a duré plus de
5 min, on voit `pending` → `firing`, puis le trou après le retour à zéro.

::: pourquoi
Grafana provisionne dans un sens unique, fichier → base : un tableau
provisionné a `provisioned: true` dans ses métadonnées, et Grafana refuse
(ou accepte à perte, selon `allowUiUpdates`) d'écrire dans l'autre sens. La
bonne boucle de travail est : prototyper dans l'UI, *Share → Export → JSON*,
coller dans le fichier versionné, laisser le provider recharger. Les
variables Grafana (`$pod`) s'injectent textuellement dans la requête, d'où
`pod=~"$pod"` avec `=~` : la valeur *All* devient `.*` (ou la liste des
valeurs jointes par `|`) et un `=` ne fonctionnerait pas. Côté Loki, les
labels viennent du **chemin** du fichier, pas du contenu : c'est ce qui
garde la cardinalité basse (un flux par conteneur) et ce que `discovery.
relabel` calcule avant même d'ouvrir le fichier. Le contenu est parsé à la
requête (`| logfmt`), c'est le contrat « index minimal, calcul à la
lecture ».
:::

::: piege
`label_values(factura_http_requests_total, pod)` ne liste que les pods qui
ont produit des métriques dans la fenêtre : un pod neuf n'apparaît qu'après
le premier scrape, un pod mort disparaît au bout de quelques heures. Le
panneau *Logs* avec `pod=~"$pod"` et *All* fonctionne parce que le label
`pod` de Loki (extrait du chemin) et celui de Prometheus (extrait de la
découverte) ont **le même nom** : c'est un choix, pas un hasard, et c'est
ce qui rend la corrélation possible d'un clic. Enfin, monter
`/var/log/pods` dans un conteneur qui tourne en root revient à lui donner
tous les logs de tous les namespaces : acceptable ici, à réfléchir en
production (Alloy en DaemonSet avec RBAC, plutôt qu'en Compose sur l'hôte).
:::

---

## 26.7 Break & Fix

### **BF26.1** — *« L'API répond 502 depuis le déploiement de ce matin »*

*`/` répond `factura front`, `/api/factures` répond `502 Bad Gateway`
(nginx). Pods de l'API `Running`, `1/1`, aucune requête dans leurs logs.
Un collègue a « ajusté un label pour le tri dans Lens ».*

**Diagnostic.**

1. Qui répond ? Le corps est la page 502 de nginx : la requête est arrivée
   au frontal, c'est **l'étape suivante** (nginx → Service `factura-api`)
   qui échoue. Les logs de nginx le confirment :

```bash
kubectl logs -n factura deploy/front --tail=5
```

```text
2026/09/16 08:12:41 [error] 29#29: *17 connect() failed (111: Connection
refused) while connecting to upstream, client: 10.42.0.1, server: ,
request: "GET /api/factures HTTP/1.1", upstream:
"http://10.43.118.7:8080/factures", host: "factura.lab.local"
```

   `Connection refused` sur la ClusterIP `10.43.118.7` : la VIP existe
   mais personne derrière.

2. Le Service et ses Endpoints :

```bash
kubectl get svc,endpoints factura-api -n factura
```

```text
NAME                  TYPE        CLUSTER-IP    PORT(S)    AGE
service/factura-api   ClusterIP   10.43.118.7   8080/TCP   2d
NAME                    ENDPOINTS   AGE
endpoints/factura-api   <none>      2d
```

   `<none>` alors que les pods sont `1/1` : ce n'est pas la readiness
   (Q26.6), c'est le **selector**.

3. Comparer selector et labels :

```bash
kubectl get svc factura-api -n factura -o jsonpath='{.spec.selector}'; echo
kubectl get pods -n factura -l app=factura-api --show-labels
```

```text
{"app":"factura-api","equipe":"compta"}
NAME                          READY   STATUS    LABELS
factura-api-5c7d9f6b8-4hq2z   1/1     Running   app=factura-api,pod-template-...
factura-api-5c7d9f6b8-tz8kp   1/1     Running   app=factura-api,pod-template-...
```

**Cause racine.** Le selector du Service a reçu une clé supplémentaire
`equipe=compta` que les pods n'ont pas. Un selector est un **ET** : aucun
pod ne matche, le contrôleur d'Endpoints vide la liste, kube-proxy installe
une règle `REJECT` pour la VIP, d'où `Connection refused` immédiat → nginx
traduit en 502 (504 aurait été un *timeout*, 404 une route inconnue de
Traefik ou de l'API).

**Correctif.** Retirer la clé, ou réappliquer le manifeste de référence,
maintenant que la cause est connue :

```bash
kubectl patch svc factura-api -n factura --type=json \
  -p='[{"op":"remove","path":"/spec/selector/equipe"}]'
# ou : kubectl apply -f ~/lab26/k8s/30-api.yaml
kubectl get endpoints factura-api -n factura       # 2 adresses
curl -sk --resolve factura.lab.local:443:10.10.10.14 \
  https://factura.lab.local/api/factures             # 200
```

**Prévention.** Un `kubectl diff -f ~/lab26/k8s/` en revue avant tout
`apply` manuel ; interdire les modifications à la main (RBAC `view` pour
les humains, `edit` pour le pipeline) ; une alerte
`kube_endpoint_address_available{namespace="factura"} == 0` (kube-state-
metrics) ou, plus simple, la sonde blackbox `SondeEchec` sur
`/api/sante` qui a dû partir ce matin.

::: pourquoi
Le Service ne connaît pas le Deployment : il ne connaît que des labels. Le
lien Deployment → ReplicaSet → Pod et le lien Service → Pod sont deux
mécanismes indépendants qui ne se rejoignent que si `spec.selector` du
Service est un sous-ensemble des labels du template. Ajouter un label au
**selector** est bien plus dangereux que d'en ajouter un aux pods : les
pods gagnent un label sans conséquence, le Service perd tous ses
endpoints. Et comme le Service a une VIP stable, rien ne « casse »
visiblement dans `get pods` : c'est `get endpoints` qui dit la vérité.
:::

---

### **BF26.2** — *« Le rollout ne finit jamais »*

*`rollout status` bloqué sur `1 out of 2 new replicas have been updated`,
trois pods : deux anciens `1/1`, un nouveau `0/1` `Running`. Le site
fonctionne. L'image n'a pas changé.*

**Diagnostic.**

1. Ce qui a changé entre les deux révisions :

```bash
kubectl rollout history deploy/factura-api -n factura
kubectl rollout history deploy/factura-api -n factura --revision=5 \
  > /tmp/r5 ; kubectl rollout history deploy/factura-api -n factura \
  --revision=6 > /tmp/r6 ; diff /tmp/r5 /tmp/r6
```

```text
<       Readiness:  http-get http://:http/pret delay=0s timeout=1s period=5s
---
>       Readiness:  http-get http://:8081/pret delay=0s timeout=1s period=5s
```

2. Le nouveau pod le confirme :

```bash
kubectl describe pod -n factura -l app=factura-api | grep -A2 'Readiness probe'
```

```text
Warning  Unhealthy  kubelet  Readiness probe failed:
  Get "http://10.42.0.31:8081/pret": dial tcp 10.42.0.31:8081:
  connect: connection refused
```

**Cause racine.** La readiness probe vise le port `8081` au lieu du port
nommé `http` (8080). L'application est saine (la liveness sur `/sante`
passe, pas de restart) mais le kubelet ne la déclare jamais `Ready`. Avec
`maxUnavailable: 25 %` → 0 pod pour 2 réplicas et `maxSurge: 25 %` → 1, le
contrôleur a créé un nouveau pod et **attend** qu'il soit prêt avant de
supprimer un ancien. Il n'ira jamais plus loin : le service est intact
parce que les deux anciens pods restent dans les Endpoints — c'est
exactement le rôle de la readiness dans un rolling update.

**Correctif.** Dans `30-api.yaml`, `readinessProbe.httpGet.port: http`,
puis `kubectl apply -f ~/lab26/k8s/30-api.yaml` : nouvelle révision, le pod
fautif est remplacé, le rollout se termine. (`rollout undo` aurait aussi
marché, mais sans comprendre.)

**Prévention.** `progressDeadlineSeconds: 120` dans `spec` du Deployment :
au bout de 120 s sans progrès, la condition `Progressing` passe à
`False` avec `reason: ProgressDeadlineExceeded` et `rollout status` sort
en erreur (`error: deployment "factura-api" exceeded its progress
deadline`) — code de retour ≠ 0, donc pipeline rouge. Le défaut est 600 s :
« indéfiniment » pour un humain qui regarde, mais le pipeline aurait fini
par échouer après 10 min. Ajouter en plus un test de déploiement (`helm
test` ou un Job) qui appelle `/api/` via l'Ingress.

::: pourquoi
Un rollout bloqué **sans coupure** est le comportement voulu : `maxUnavailable:
0` (l'arrondi vers le bas de 25 % de 2) garantit qu'on ne retire jamais un
pod sain tant que son remplaçant n'est pas prêt. C'est aussi pour ça que le
Deployment ne revient pas seul en arrière (Q26.9) : il ne sait pas si le
blocage est temporaire (image lente à démarrer) ou définitif. `rollout
history --revision=N` affiche le template du ReplicaSet de cette révision ;
un `diff` entre deux révisions est le moyen le plus rapide de voir ce que
« personne n'a touché ».
:::

---

### **BF26.3** — *« L'API redémarre en boucle, le code n'a pas changé »*

*`CrashLoopBackOff`, `RESTARTS` qui grimpe, `logs --previous` montre un
démarrage normal puis plus rien.*

**Diagnostic.**

1. Les logs ne disent rien : un processus tué par `SIGKILL` n'écrit pas.
   La raison est dans l'état du conteneur :

```bash
kubectl describe pod -n factura -l app=factura-api | grep -A6 'Last State'
```

```text
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
      Started:      Wed, 16 Sep 2026 09:02:11 +0200
      Finished:     Wed, 16 Sep 2026 09:02:14 +0200
    Ready:          False
    Restart Count:  7
```

2. Relier à une valeur du manifeste :

```bash
kubectl get deploy factura-api -n factura \
  -o jsonpath='{.spec.template.spec.containers[0].resources}'; echo
```

```text
{"limits":{"memory":"20Mi"},"requests":{"cpu":"50m","memory":"16Mi"}}
```

   `20Mi` de limite (et une request abaissée à `16Mi` pour que l'API
   server accepte l'objet : il refuse `limits < requests`). `kubectl
   rollout history deploy/factura-api -n factura --revision=N` montre la
   révision où ces valeurs sont apparues.

3. Mesurer le besoin réel sur un pod sain (par exemple `api-dns` du
   namespace `casse`, même image, ou un ancien pod encore vivant) :

```bash
kubectl top pod -n casse --containers -l app=api-dns
```

```text
POD                        NAME   CPU(cores)   MEMORY(bytes)
api-dns-9d7c6b5f8-v2q8k    api    2m           27Mi
```

**Cause racine.** `resources.limits.memory` a été abaissée à `20Mi` ;
l'interpréteur Python et le serveur HTTP en consomment ~27 Mi au repos ;
le cgroup tue le processus dès que le *working set* dépasse la limite,
quelques secondes après le démarrage (d'où le « démarrage normal puis plus
rien »).

**Correctif.** Dans `30-api.yaml` : `requests.memory: 64Mi`,
`limits.memory: 128Mi` (≈ 4 à 5 × l'usage observé : de la marge pour les
pics de threads sous charge, sans gaspiller — la limite ne réserve rien).
`kubectl apply`, puis `kubectl get pods -w` jusqu'à `1/1` sans restart.

**Prévention.** Une `LimitRange` dans le namespace qui impose un minimum
(`min.memory: 32Mi`) et un ratio `maxLimitRequestRatio` ; l'alerte
`PodEnCrashLoop` (L26.4) et, plus ciblé,
`kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}` ;
un panneau `container_memory_working_set_bytes /
kube_pod_container_resource_limits{resource="memory"}` pour voir qui frôle
sa limite **avant** l'incident.

::: pourquoi
`OOMKilled` n'est pas une décision de Kubernetes mais du **noyau** : la
limite mémoire est un `memory.max` de cgroup v2, et c'est l'OOM killer du
cgroup qui envoie `SIGKILL` (137 = 128 + 9). Le kubelet ne fait que le
constater et le rapporter dans `Last State`. La request, elle, ne sert
qu'au scheduler ; un pod peut dépasser sa request tant qu'il reste sous sa
limite. Choisir une limite, c'est choisir entre « tuer l'application »
(limite basse) et « laisser une fuite manger le nœud » (limite haute) ;
la seule façon honnête de trancher est de mesurer (`kubectl top`, ou
`container_memory_working_set_bytes` sur une semaine) et de prendre 2 à
4 × le pic.
:::

---

### **BF26.4** — *« Depuis le redémarrage, plus aucun pod ne démarre »*

*Après `rollout restart`, `ErrImagePull` puis `ImagePullBackOff`. Le
`docker pull` avec login fonctionne depuis lab-ops. `casse` n'est pas
affecté.*

**Diagnostic.**

1. Le message exact :

```bash
kubectl get events -n factura --sort-by=.lastTimestamp | grep -i pull | tail -3
```

```text
Warning  Failed  pod/factura-api-7b8c9d6f5-m2k4x  Failed to pull image
"10.10.10.14:5000/factura-api:1.0": ... unexpected status from HEAD request
to http://10.10.10.14:5000/v2/factura-api/manifests/1.0: 401 Unauthorized
```

   `401`, pas `404` ni `connection refused` : le registre répond, l'image
   existe, il manque **l'authentification**.

2. D'où vient l'authentification d'un pull ? Du `imagePullSecrets` du pod,
   qui référence un Secret du **même** namespace :

```bash
kubectl get pod -n factura -l app=factura-api \
  -o jsonpath='{.items[0].spec.imagePullSecrets}'; echo
kubectl get secret registre-lab -n factura
kubectl get secret registre-lab -n casse
```

```text
[{"name":"registre-lab"}]
Error from server (NotFound): secrets "registre-lab" not found
NAME           TYPE                             DATA   AGE
registre-lab   kubernetes.io/dockerconfigjson   1      1d
```

**Cause racine.** Le Secret `registre-lab` a été supprimé du namespace
`factura`. Les pods qui tournaient ne s'en apercevaient pas : le Secret
n'est lu qu'au moment d'un *pull*. Le redémarrage a créé des pods neufs,
et comme le cache d'images du nœud avait été purgé entre-temps (`sudo k3s
crictl images | grep factura` ne renvoie rien : un `crictl rmi --prune`
« pour libérer du disque », ou le ramasse-miettes du kubelet sous pression
disque), `imagePullPolicy: IfNotPresent` n'a pas suffi : le kubelet a dû
tirer l'image, sans identifiant → 401. Le namespace `casse` a toujours son
Secret, d'où l'asymétrie.

**Correctif.** Le recréer, ou le copier depuis `casse` en nettoyant les
champs propres à l'objet :

```bash
kubectl create secret docker-registry registre-lab -n factura \
  --docker-server=10.10.10.14:5000 \
  --docker-username=mathieu --docker-password=labpass
# variante : copie depuis casse
kubectl get secret registre-lab -n casse -o json \
  | jq 'del(.metadata.uid,.metadata.resourceVersion,
            .metadata.creationTimestamp) | .metadata.namespace="factura"' \
  | kubectl apply -f -
kubectl rollout restart deploy/factura-api -n factura  # évite le backoff
kubectl rollout status deploy/factura-api -n factura
```

Pourquoi ça marche sur lab-ops et pas dans le cluster : `docker pull` lit
`~/.docker/config.json` de `mathieu` (le `docker login` du setup) ; le
kubelet, lui, parle à **containerd**, qui n'a aucun identifiant global sur
k3s (`registries.yaml` ne décrit que l'endpoint HTTP) et ne reçoit que
ceux du pod, via `imagePullSecrets`.

**Prévention.** Le Secret dans le dossier de manifestes (L26.2 étape 8) ou
en `secretGenerator` kustomize (D26) pour qu'un `apply` le recrée ; RBAC :
seul le pipeline peut `delete secrets` ; alerte
`kube_pod_container_status_waiting_reason{reason="ImagePullBackOff"} == 1`
2 min → ticket. Éventuellement `configs:` dans `registries.yaml` avec
`auth: {username, password}` pour un identifiant **par nœud** — pratique,
mais alors un mot de passe en clair dans un fichier root de chaque nœud.

::: pourquoi
Un pull d'image est fait par le **nœud**, pas par l'API server : le kubelet
lit le Secret référencé, en extrait l'entrée `auths["10.10.10.14:5000"]` et
la passe à containerd pour cette image précise. Les Secrets étant des
objets de namespace, `imagePullSecrets` ne peut pointer que dans le
namespace du pod — d'où « les Secrets ne traversent pas les namespaces »,
et la nécessité de le dupliquer (ou de l'attacher au ServiceAccount
`default` de chaque namespace : `kubectl patch sa default -p
'{"imagePullSecrets":[{"name":"registre-lab"}]}'`, ce qui évite de le
répéter dans chaque manifeste).
:::

---

### **BF26.5** — *« Toutes les VM sont DOWN dans Prometheus »*

*5 cibles `node` DOWN, `No data` dans Grafana, `InstanceDown` firing ×5,
mais `ssh` et `curl :9100/metrics` fonctionnent.*

**Diagnostic.**

1. L'erreur par cible, sans passer par l'UI :

```bash
curl -s localhost:9090/api/v1/targets | jq -r \
  '.data.activeTargets[] | select(.health=="down")
   | "\(.labels.instance)\t\(.scrapeUrl)\t\(.lastError)"'
```

```text
lab-adm   http://10.10.10.10:9101/metrics  Get "http://10.10.10.10:9101/
          metrics": dial tcp 10.10.10.10:9101: connect: connection refused
lab-web   http://10.10.10.11:9101/metrics  ... connection refused
lab-db    http://10.10.10.12:9101/metrics  ... connection refused
lab-rhel  http://10.10.10.13:9101/metrics  ... connection refused
lab-ops   http://10.10.10.14:9101/metrics  ... connection refused
```

   **`9101`**. Les exporters écoutent sur 9100 (`curl` le prouve). Cinq
   cibles, même erreur, même port : le problème est du côté de celui qui
   scrape, pas des cinq VM.

2. La configuration :

```bash
cd /opt/observabilite && grep -n '9101' prometheus/prometheus.yml
git -C prometheus log --oneline -3 2>/dev/null || ls -l prometheus/
```

**Cause racine.** Les cinq `targets` du job `node` ont été modifiées de
`:9100` en `:9101` (une recherche-remplacement trop large, ou un « on va
déplacer les exporters » jamais fini). Comme `instance` est fixé par un
label explicite (`instance: lab-web`), le nom affiché n'a pas changé — seule
la colonne *Endpoint* de `/targets` montrait le mauvais port.

**Correctif.**

```bash
sed -i 's/:9101"/:9100"/' prometheus/prometheus.yml
docker compose exec prometheus promtool check config \
  /etc/prometheus/prometheus.yml
curl -X POST localhost:9090/-/reload
sleep 20 ; curl -s localhost:9090/api/v1/query?query=up{job=\"node\"} \
  | jq -r '.data.result[] | "\(.metric.instance) \(.value[1])"'
```

`InstanceDown` se résout au cycle d'évaluation suivant, Alertmanager envoie
les `resolved` au prochain `group_interval`.

**Prévention.** `promtool check config` **ne détecte pas** un mauvais port
(la config est valide) : il faut un test fonctionnel après rechargement,
par exemple `curl .../api/v1/targets | jq` dans le pipeline qui livre la
config ; une méta-alerte `count(up{job="node"} == 0) == count(up{job=
"node"})` (« tout est DOWN en même temps → suspecte la supervision, pas
les serveurs ») routée à part ; et versionner `/opt/observabilite` dans
Git pour avoir le `diff`.

L'alerte a été **utile** : elle a signalé en 2 min qu'on ne voyait plus
rien. Elle a été **trompeuse** : son `summary` dit « lab-web ne répond
plus », alors que lab-web va très bien ; `up == 0` mesure « Prometheus
n'arrive pas à scraper », ce qui inclut les pannes de Prometheus lui-même,
de sa config, du réseau et du firewall. Le runbook d'`InstanceDown` doit
commencer par « `curl` la cible depuis le serveur Prometheus ».

::: pourquoi
`up` est la métrique la plus utile et la plus mal comprise de Prometheus :
elle est synthétisée **par le scrapeur** à chaque tentative (1 si la
requête HTTP a réussi et le corps est parsable, 0 sinon), elle ne vient pas
de la cible. Une alerte sur `up` alerte donc sur la *relation* entre
Prometheus et la cible. Le motif « tout tombe en même temps » est un
classificateur puissant en astreinte : cinq VM indépendantes ne meurent pas
à la même seconde ; une config, un switch ou un DNS, si. C'est la première
question du diagnostic : *qu'est-ce que ces cinq-là ont en commun ?*
:::

---

### **BF26.6** — *« L'alerte ne part jamais »*

*lab-rhel injoignable une heure, personne prévenu. `InstanceDown` apparaît
en `pending` et y reste, rien dans `webhook`. Les autres alertes marchent.*

**Diagnostic.**

1. État de l'alerte et **depuis quand** :

```bash
curl -s localhost:9090/api/v1/alerts | jq -r '.data.alerts[]
  | select(.labels.alertname=="InstanceDown")
  | "\(.labels.instance)\t\(.state)\t\(.activeAt)"'
date -u +%FT%TZ
```

```text
lab-rhel   pending   2026-09-16T14:02:19Z
2026-09-16T14:20:41Z
```

   Pending depuis 18 min : le `for` est donc supérieur à 18 min.

2. La règle telle que Prometheus l'a chargée (pas le fichier : ce qu'il a
   **en mémoire**) :

```bash
curl -s localhost:9090/api/v1/rules | jq -r '.data.groups[].rules[]
  | select(.name=="InstanceDown") | "for=\(.duration)s  expr=\(.query)"'
```

```text
for=7200s  expr=up{job!="k8s-pods"} == 0
```

3. Confirmation dans le fichier :

```bash
grep -n -A2 'alert: InstanceDown' \
  /opt/observabilite/prometheus/rules/lab-alertes.yml
```

```text
  - alert: InstanceDown
    expr: up{job!="k8s-pods"} == 0
    for: 2h
```

**Cause racine.** `for: 2h` au lieu de `for: 2m` — une lettre. Une cible
injoignable une heure ne franchit jamais les deux heures, l'alerte reste
*pending* et **Alertmanager n'en entend jamais parler** : Prometheus ne
pousse que les alertes *firing*. Les autres alertes ont leurs propres
`for`, elles ne sont pas concernées.

Sémantique de `for` : l'alerte passe *pending* à la première évaluation où
l'expression renvoie la série ; elle devient *firing* si, à **chaque**
évaluation pendant `for`, la série est encore là. Si à une seule
évaluation l'expression ne renvoie rien (un scrape qui passe, une cible qui
clignote), l'alerte repasse *inactive* et le compteur repart de zéro : un
`for` long n'est pas seulement lent, il est **fragile** face à une panne
intermittente. (L'inverse existe : `keep_firing_for` garde une alerte
firing un moment après que l'expression est redevenue fausse.)

**Correctif.** `for: 2m`, `promtool check rules`, `reload`. L'alerte sur
lab-rhel passe *firing* 2 min après le prochain `pending` — immédiatement
si elle est déjà *pending* depuis plus de 2 min (le `activeAt` est
conservé).

**Prévention.** Un test unitaire de règles,
`/opt/observabilite/prometheus/tests/instance-down_test.yml` :

```yaml
rule_files:
  - ../rules/lab-alertes.yml
  - ../rules/lab-enregistrement.yml

evaluation_interval: 15s

tests:
  - interval: 15s
    input_series:
      - series: 'up{job="node", instance="lab-rhel"}'
        values: '1 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0'
    alert_rule_test:
      # à 1m30 : up=0 depuis 30 s seulement -> pending, donc aucune alerte
      - eval_time: 1m30s
        alertname: InstanceDown
        exp_alerts: []
      # à 3m30 : up=0 depuis 150 s > for 2m -> firing
      - eval_time: 3m30s
        alertname: InstanceDown
        exp_alerts:
          - exp_labels:
              severity: page
              job: node
              instance: lab-rhel
              alertname: InstanceDown
            exp_annotations:
              summary: "lab-rhel ne répond plus au scrape"
              description: >-
                La cible lab-rhel du job node est DOWN depuis plus de 2
                minutes.
              runbook_url: https://wiki.lab.local/runbooks/instance-down
```

```bash
docker compose exec prometheus promtool test rules \
  /etc/prometheus/tests/instance-down_test.yml
```

```text
Unit Testing:  /etc/prometheus/tests/instance-down_test.yml
  SUCCESS
```

Avec `for: 2h`, le second cas (`3m30s`, alerte attendue *firing*) échoue :
`alertname: InstanceDown, time: 3m30s, exp: [...], got: []`. Ce test dans
le pipeline qui livre `/opt/observabilite` aurait bloqué la livraison.

::: pourquoi
`promtool test rules` rejoue les règles sur des séries synthétiques avec
une horloge virtuelle : `values: '1 1 1 1 0 0 ...'` à `interval: 15s`
décrit `up` pendant 6 min, et `eval_time` choisit l'instant où l'on
inspecte les alertes *firing* (les *pending* ne comptent pas, c'est ce qui
rend le test discriminant pour `for`). Les `exp_annotations` sont
comparées **après** rendu des templates : c'est aussi un test de tes
`{{ $labels }}`. Le fichier de test doit vivre **hors** du glob
`rules/*.yml`, sinon Prometheus tenterait de le charger comme un fichier
de règles et refuserait toute la configuration.
:::

---

## 26.8 Défi du module

**D26** — *factura en production : kustomize avec Secrets, PDB, HPA ; SLO
chiffrés ; alertes multi-fenêtre sur burn rate testées ; runbooks ;
tableau SLO ; script de conformité ; exercice d'astreinte et post-mortem.*

**1. Manifestes `~/lab26/prod/`.**

```text
~/lab26/prod/
├── kustomization.yaml
├── namespace.yaml          (00-namespace.yaml de L26.2)
├── configmap.yaml          (10-configmap.yaml)
├── postgres.yaml           (20-postgres.yaml)
├── api.yaml                (30-api.yaml, sans tag d'image figé)
├── front.yaml              (40-front.yaml)
├── ingress.yaml            (50-ingress.yaml)
├── networkpolicy.yaml      (70-networkpolicy.yaml)
├── pdb.yaml
├── hpa.yaml
└── secrets/                (dans .gitignore)
    ├── postgres.env
    ├── dockerconfig.json
    ├── factura.crt
    └── factura.key
```

```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: factura

resources:
  - namespace.yaml
  - configmap.yaml
  - postgres.yaml
  - api.yaml
  - front.yaml
  - ingress.yaml
  - networkpolicy.yaml
  - pdb.yaml
  - hpa.yaml

images:
  - name: 10.10.10.14:5000/factura-api
    newTag: "1.1"

generatorOptions:
  disableNameSuffixHash: true

secretGenerator:
  - name: postgres-auth
    envs: [secrets/postgres.env]
  - name: registre-lab
    type: kubernetes.io/dockerconfigjson
    files: [.dockerconfigjson=secrets/dockerconfig.json]
  - name: factura-tls
    type: kubernetes.io/tls
    files:
      - tls.crt=secrets/factura.crt
      - tls.key=secrets/factura.key
```

```bash
mkdir -p ~/lab26/prod/secrets && cd ~/lab26/prod
printf 'POSTGRES_USER=factura\nPOSTGRES_PASSWORD=labpass\n' \
  > secrets/postgres.env
kubectl create secret docker-registry x --docker-server=10.10.10.14:5000 \
  --docker-username=mathieu --docker-password=labpass \
  --dry-run=client -o jsonpath='{.data.\.dockerconfigjson}' \
  | base64 -d > secrets/dockerconfig.json
cp ~/lab26/tls/factura.{crt,key} secrets/
chmod 0600 secrets/* ; echo 'secrets/' > .gitignore
```

```yaml
# pdb.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: factura-api
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: factura-api
```

```yaml
# hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: factura-api
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: factura-api
  minReplicas: 2
  maxReplicas: 4
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
```

```bash
kubectl kustomize ~/lab26/prod/ | grep -c '^kind:'        # 16 objets
kubectl delete ns factura ; kubectl apply -k ~/lab26/prod/
kubectl get pdb,hpa -n factura
```

```text
NAME                                      MIN AVAILABLE   ALLOWED DISRUPTIONS
poddisruptionbudget.policy/factura-api    1               1
NAME                                        TARGETS      MINPODS  MAXPODS
horizontalpodautoscaler.autoscaling/factura-api   cpu: 4%/60%   2        4
```

Justification du `secretGenerator` : les manifestes versionnés ne
contiennent **aucun** secret, seulement des références à des fichiers
ignorés par Git, fournis par le pipeline (variables CI, coffre) ; un
`.yaml` de Secret dans le dépôt serait du base64 en clair dans l'historique
pour toujours. `disableNameSuffixHash` garde les noms `postgres-auth`,
`registre-lab`, `factura-tls` attendus par les autres manifestes (le
suffixe de hash sert à forcer un rollout à chaque changement de Secret, ce
qu'on ne veut pas pour un mot de passe de base). L'étape suivante, hors
lab : Sealed Secrets ou SOPS pour chiffrer *dans* le dépôt.

**2. `~/lab26/rapports/slo.md`.**

```markdown
# SLO factura-api — fenêtre glissante 30 jours

## SLI 1 — disponibilité
Part des requêtes HTTP (hors /sante, /pret, /metrics) répondues sans 5xx.
    1 - sum(rate(factura_http_requests_total{code=~"5.."}[30d]))
        / sum(rate(factura_http_requests_total[30d]))
SLO : 99,5 %. Budget : 0,5 % des requêtes = 216 min sur 30 j si on
raisonne en indisponibilité totale ; à 2 M req/mois, 10 000 requêtes.

## SLI 2 — latence
Part des requêtes GET /factures servies en moins de 300 ms.
    sum(rate(factura_http_request_duration_seconds_bucket{
          path="/factures", le="0.25"}[30d]))
      / sum(rate(factura_http_request_duration_seconds_count{
          path="/factures"}[30d]))
(bucket 0,25 s : l'histogramme n'a pas de bucket à 0,3 ; on prend le
bucket immédiatement inférieur, plus strict, et on le documente.)
SLO : 99,5 %. Budget : 0,5 % des requêtes /factures, soit ~5 000 sur
1 M/mois.

## Budget restant (0 = épuisé)
    1 - (1 - <SLI 30 j>) / 0.005

## Burn rate sur une fenêtre w
    (1 - <SLI sur w>) / 0.005
1 = on consomme exactement le budget en 30 j ; 14,4 = épuisé en 2 j ;
6 = épuisé en 5 j.
```

**3. `prometheus/rules/slo.yml` et son test.**

```yaml
groups:
  - name: slo-factura
    interval: 30s
    rules:
      - record: slo:factura_errors:ratio_rate5m
        expr: >
          sum(rate(factura_http_requests_total{code=~"5.."}[5m]))
            / sum(rate(factura_http_requests_total[5m]))
      - record: slo:factura_errors:ratio_rate30m
        expr: >
          sum(rate(factura_http_requests_total{code=~"5.."}[30m]))
            / sum(rate(factura_http_requests_total[30m]))
      - record: slo:factura_errors:ratio_rate1h
        expr: >
          sum(rate(factura_http_requests_total{code=~"5.."}[1h]))
            / sum(rate(factura_http_requests_total[1h]))
      - record: slo:factura_errors:ratio_rate6h
        expr: >
          sum(rate(factura_http_requests_total{code=~"5.."}[6h]))
            / sum(rate(factura_http_requests_total[6h]))

      # en plus du cahier des charges : le SLI sur la fenêtre du SLO,
      # pour le tableau de bord (budget restant, disponibilité 30 j)
      - record: slo:factura_errors:ratio_rate30d
        expr: >
          sum(increase(factura_http_requests_total{code=~"5.."}[30d]))
            / sum(increase(factura_http_requests_total[30d]))

      # budget = 1 - 0.995 = 0.005 ; seuil = burn rate x budget
      - alert: FacturaBudgetErreurRapide
        expr: >
          slo:factura_errors:ratio_rate1h > (14.4 * 0.005)
          and slo:factura_errors:ratio_rate5m > (14.4 * 0.005)
        for: 2m
        labels:
          severity: page
          slo: disponibilite
        annotations:
          summary: "factura-api brûle son budget d'erreur 14x trop vite"
          description: >-
            Taux d'erreur 1 h : {{ $value | humanizePercentage }}
            (seuil 7,2 %). À ce rythme le budget de 30 jours est épuisé
            en 2 jours.
          runbook_url: file:///home/mathieu/lab26/runbooks/api-erreurs.md

      - alert: FacturaBudgetErreurLent
        expr: >
          slo:factura_errors:ratio_rate6h > (6 * 0.005)
          and slo:factura_errors:ratio_rate30m > (6 * 0.005)
        for: 15m
        labels:
          severity: ticket
          slo: disponibilite
        annotations:
          summary: "factura-api brûle son budget d'erreur 6x trop vite"
          description: >-
            Taux d'erreur 6 h : {{ $value | humanizePercentage }}
            (seuil 3 %). Budget de 30 jours épuisé en 5 jours.
          runbook_url: file:///home/mathieu/lab26/runbooks/api-erreurs.md
```

`/opt/observabilite/prometheus/tests/slo_test.yml` :

```yaml
rule_files:
  - ../rules/slo.yml

evaluation_interval: 30s

tests:
  # 10 % d'erreurs en continu : page après 1h (rate1h) + for 2m
  - interval: 30s
    input_series:
      - series: 'factura_http_requests_total{code="200",path="/factures"}'
        values: '0+45x300'
      - series: 'factura_http_requests_total{code="500",path="/factures"}'
        values: '0+5x300'
    alert_rule_test:
      - eval_time: 20m
        alertname: FacturaBudgetErreurRapide
        exp_alerts:
          - exp_labels:
              severity: page
              slo: disponibilite
              alertname: FacturaBudgetErreurRapide
            exp_annotations:
              summary: "factura-api brûle son budget d'erreur 14x trop vite"
              description: >-
                Taux d'erreur 1 h : 10%
                (seuil 7,2 %). À ce rythme le budget de 30 jours est épuisé
                en 2 jours.
              runbook_url: file:///home/mathieu/lab26/runbooks/api-erreurs.md

  # 1 % d'erreurs : sous les deux seuils, rien ne part
  - interval: 30s
    input_series:
      - series: 'factura_http_requests_total{code="200",path="/factures"}'
        values: '0+99x300'
      - series: 'factura_http_requests_total{code="500",path="/factures"}'
        values: '0+1x300'
    alert_rule_test:
      - eval_time: 2h
        alertname: FacturaBudgetErreurRapide
        exp_alerts: []
      - eval_time: 2h
        alertname: FacturaBudgetErreurLent
        exp_alerts: []
```

```bash
cd /opt/observabilite
docker compose exec prometheus promtool check rules \
  /etc/prometheus/rules/slo.yml
docker compose exec prometheus promtool test rules \
  /etc/prometheus/tests/slo_test.yml
curl -X POST localhost:9090/-/reload
```

```text
Checking /etc/prometheus/rules/slo.yml
  SUCCESS: 7 rules found
Unit Testing:  /etc/prometheus/tests/slo_test.yml
  SUCCESS
```

(À `eval_time: 20m`, `rate[1h]` ne dispose que de 20 min de données : il
extrapole sur les échantillons présents, et le ratio 5/50 = 10 % est
correct dès les premières minutes — c'est pour ça que le test n'a pas
besoin d'attendre une heure. `$value` rendu par `humanizePercentage` donne
`10%`, d'où la ligne de l'annotation attendue.)

**4. Runbooks.** `~/lab26/runbooks/api-erreurs.md` :

```markdown
# Runbook — FacturaBudgetErreurRapide / ApiErreurs5xx

Symptôme : l'API renvoie des 5xx au-delà du seuil (page : > 7,2 % sur 1 h
et 5 min ; ticket : > 3 % sur 6 h et 30 min).
Impact : les clients du frontal reçoivent des erreurs sur /api/* ; le
budget d'erreur mensuel se consomme 14x (page) ou 6x (ticket) trop vite.

## Premières commandes (5 max)
1. kubectl get pods -n factura -o wide   -> Ready ? restarts ? rollout ?
2. kubectl get events -n factura --sort-by=.lastTimestamp | tail -20
                                         -> OOMKilled, probe failed, image ?
3. Grafana « Lab — API factura » : quels codes ? tous les pods ou un seul ?
4. {namespace="factura", container="api"} | logfmt | code=~"5.."
                                                -> le message d'erreur exact
5. kubectl exec -n factura postgres-0 -- pg_isready -U factura
                                                -> la base répond ?

## Causes connues et correctifs
- PostgreSQL indisponible (raison="db", 503) : kubectl describe pod postgres-0,
  PVC, OOM ; redémarrer le StatefulSet si besoin.
- Rollout d'une version défectueuse : kubectl rollout undo deploy/factura-api.
- FACTURA_TAUX_ERREUR laissé à une valeur > 0 après un test :
  kubectl set env deploy/factura-api FACTURA_TAUX_ERREUR-
- Un seul pod en erreur : kubectl delete pod <nom> (le Deployment le recrée).

## Escalade
Si la cause n'est pas identifiée en 20 min ou si PostgreSQL est corrompue :
astreinte data (lab-db), et passer en mode dégradé (front seul).

## Vérification de la résolution
slo:factura_errors:ratio_rate5m < 0.01 pendant 10 min ; alerte resolved
dans webhook ; noter l'incident pour le post-mortem si > 30 min.
```

`~/lab26/runbooks/instance-down.md`, même plan : symptôme (`up == 0`
2 min), impact (aveugle sur la VM, pas forcément de panne), commandes
(`curl` la cible **depuis lab-ops**, `ssh`, `systemctl status
prometheus-node-exporter` — `node_exporter` sur Rocky —, `ss -ltn | grep 9100`, `firewall-cmd
--list-ports` sur Rocky), causes (exporter arrêté, firewall, VM éteinte,
mauvaise config Prometheus — BF26.5), escalade (VM injoignable en SSH →
console Proxmox), résolution (`up == 1` et alerte resolved).

**5. Tableau `Lab — SLO factura`** — `/opt/observabilite/grafana/
dashboards/slo.json`, mêmes conventions que `api.json`, cinq panneaux :

```json
{
 "uid": "lab-slo-factura",
 "title": "Lab — SLO factura",
 "tags": ["lab", "slo"],
 "schemaVersion": 39, "version": 1, "refresh": "1m",
 "time": {"from": "now-6h", "to": "now"},
 "panels": [
  {"id": 1, "type": "stat", "title": "Budget d'erreur restant (30 j)",
   "gridPos": {"x": 0, "y": 0, "w": 8, "h": 6},
   "datasource": {"type": "prometheus", "uid": "prometheus"},
   "targets": [{"refId": "A",
    "expr": "1 - slo:factura_errors:ratio_rate30d / 0.005"}],
   "fieldConfig": {"defaults": {"unit": "percentunit", "min": 0, "max": 1,
    "thresholds": {"mode": "absolute", "steps": [
     {"color": "red", "value": null},
     {"color": "orange", "value": 0.25},
     {"color": "green", "value": 0.5}]}}, "overrides": []}},
  {"id": 2, "type": "stat", "title": "Disponibilité 30 j",
   "gridPos": {"x": 8, "y": 0, "w": 8, "h": 6},
   "datasource": {"type": "prometheus", "uid": "prometheus"},
   "targets": [{"refId": "A",
    "expr": "1 - slo:factura_errors:ratio_rate30d"}],
   "fieldConfig": {"defaults": {"unit": "percentunit", "decimals": 3,
    "thresholds": {"mode": "absolute", "steps": [
     {"color": "red", "value": null},
     {"color": "green", "value": 0.995}]}}, "overrides": []}},
  {"id": 3, "type": "timeseries", "title": "Burn rate 1 h / 6 h",
   "gridPos": {"x": 0, "y": 6, "w": 16, "h": 8},
   "datasource": {"type": "prometheus", "uid": "prometheus"},
   "targets": [
    {"refId": "A", "legendFormat": "1 h",
     "expr": "slo:factura_errors:ratio_rate1h / 0.005"},
    {"refId": "B", "legendFormat": "6 h",
     "expr": "slo:factura_errors:ratio_rate6h / 0.005"}],
   "fieldConfig": {"defaults": {"unit": "none", "min": 0,
    "custom": {"thresholdsStyle": {"mode": "line+area"}},
    "thresholds": {"mode": "absolute", "steps": [
     {"color": "green", "value": null},
     {"color": "orange", "value": 6},
     {"color": "red", "value": 14.4}]}}, "overrides": []}},
  {"id": 4, "type": "logs", "title": "Réponses 500 (Loki)",
   "gridPos": {"x": 0, "y": 14, "w": 16, "h": 8},
   "datasource": {"type": "loki", "uid": "loki"},
   "targets": [{"refId": "A",
    "expr": "{namespace=\"factura\"} | logfmt | code=\"500\""}],
   "options": {"showTime": true, "sortOrder": "Descending"}}
 ]
}
```

**6. `~/lab26/bin/verif-prod.sh`.**

```bash
#!/usr/bin/env bash
# verif-prod.sh — conformité de factura en production (D26)
set -euo pipefail
PASS=0; FAIL=0
ok() { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
NS=factura; PROM=http://10.10.10.14:9090; GRAF=http://10.10.10.14:3000
OBS=/opt/observabilite
# le « || true » évite qu'un curl en échec ne fasse sortir tout le script
# (set -e) : on veut un [FAIL] lisible, pas un arrêt silencieux
q() { { curl -s "$PROM/api/v1/query" --data-urlencode "query=$1" || true; } \
       | jq -r '.data.result[0].value[1] // "0"'; }

echo "== Conformité factura =="
# pods de l'API : tous Ready, avec limites et probes
PODS=$(kubectl get pods -n $NS -l app=factura-api -o json)
N=$(jq '.items | length' <<<"$PODS")
R=$(jq '[.items[] | select(all(.status.containerStatuses[]; .ready))]
        | length' <<<"$PODS")
[ "$N" -ge 2 ] && [ "$N" -eq "$R" ] \
  && ok "API : $R/$N pods Ready" || ko "API : $R/$N pods Ready"
jq -e '[.items[].spec.containers[0]
       | (.resources.limits.memory and .livenessProbe and .readinessProbe)]
       | all' <<<"$PODS" >/dev/null && ok "API : limites et probes présentes" \
  || ko "API : limite mémoire, liveness ou readiness manquante"
# PDB et HPA
kubectl get pdb factura-api -n $NS >/dev/null 2>&1 \
  && ok "PDB factura-api" || ko "PDB factura-api absent"
kubectl get hpa factura-api -n $NS >/dev/null 2>&1 \
  && ok "HPA factura-api" || ko "HPA factura-api absent"
# Ingress TLS
C=$(curl -sk -o /dev/null -w '%{http_code}' \
      --resolve factura.lab.local:443:10.10.10.14 \
      https://factura.lab.local/api/factures || true)
[ "$C" = 200 ] && ok "Ingress TLS répond 200" || ko "Ingress : HTTP $C"
# cibles node
DOWN=$(q 'count(up{job="node"} == 0)')
[ "$DOWN" = 0 ] && ok "toutes les cibles node UP" \
  || ko "$DOWN cible(s) node DOWN"
# règles SLO chargées
curl -s "$PROM/api/v1/rules" | jq -e '.data.groups[]
  | select(.name=="slo-factura")' >/dev/null \
  && ok "règles slo.yml chargées" || ko "groupe slo-factura absent"
# alertmanager.yml valide
(cd $OBS && docker compose exec -T alertmanager amtool check-config \
  /etc/alertmanager/alertmanager.yml >/dev/null) \
  && ok "alertmanager.yml valide" || ko "alertmanager.yml invalide"
# tableaux provisionnés
for u in lab-api-factura lab-slo-factura; do
  curl -sf -u admin:labpass "$GRAF/api/dashboards/uid/$u" >/dev/null \
    && ok "tableau $u" || ko "tableau $u absent"
done
# aucune page en cours
P=$(curl -s "$PROM/api/v1/alerts" | jq '[.data.alerts[]
     | select(.state=="firing" and .labels.severity=="page")] | length')
[ "$P" = 0 ] && ok "aucune alerte page en cours" \
  || ko "$P alerte(s) page en cours"

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
```

**7. Exercice d'astreinte.**

```bash
~/lab26/bin/charge-api.sh https://factura.lab.local/api/factures 900 &
kubectl set env deploy/factura-api -n factura FACTURA_TAUX_ERREUR=0.5
date +%T                                       # T0
cd /opt/observabilite && docker compose logs -f webhook
```

```text
T0        set env (rollout, ~20 s)
T0+2m     slo:factura_errors:ratio_rate5m ≈ 0,5 (> 0,072 : 1re condition)
T0+~9m    ratio_rate1h > 0,072 : à 50 % d'erreurs il faut ~8,6 min pour
          que la moyenne sur 1 h dépasse 7,2 % (2e condition)
T0+11m    FacturaBudgetErreurRapide firing (for 2m)
T0+11m30  [PAGE] firing FacturaBudgetErreurRapide severity=page
          runbook=file:///home/mathieu/lab26/runbooks/api-erreurs.md
```

Déroulé du runbook : pods `Ready` sans restart (1), pas d'événement (2),
Grafana montre 500 sur tous les pods (3), Loki : `msg="requete"
path=/factures code=500` sans message d'erreur base (4), `pg_isready`
répond (5) → ce n'est pas la base, c'est l'application ; `kubectl get
deploy factura-api -o yaml | grep -A1 TAUX` révèle la variable ; correctif
`kubectl set env deploy/factura-api -n factura FACTURA_TAUX_ERREUR-`.
Résolution : `ratio_rate5m` redescend sous 1 % en ~6 min, et l'alerte se résout à ce moment-là, alors que `ratio_rate1h` reste au-dessus de 0,072 encore ~45 min. C'est précisément le rôle de la fenêtre courte dans le `and` : sans elle, la page resterait active près d'une heure après la correction
(l'évaluation du `and` exige les deux conditions). `resolved` dans webhook au
`group_interval` suivant.

`~/lab26/rapports/postmortem.md` (modèle du module 19) : titre, date,
durée (T0 → T0+17 min), impact (50 % des `/factures` en 500 pendant
17 min, ≈ 2 500 requêtes, 25 % du budget mensuel), chronologie horodatée
(injection, page, prise en charge, diagnostic, correctif, résolution),
cause racine (variable de test laissée en production ; le vrai problème :
une variable de simulation d'erreur **existe** dans l'image de production),
ce qui a bien marché (page en 11 min, runbook suivi en 6 min), ce qui a
manqué (aucun garde-fou sur les variables `FACTURA_*` en prod ; la page
aurait pu partir plus tôt avec une fenêtre 5 min seule), actions : retirer
`FACTURA_ TAUX_ERREUR` de l'image de prod (ou la refuser hors namespace
`casse` via une policy d'admission), ajouter `verif-prod.sh` au pipeline,
revoir les seuils avec l'équipe.

::: pourquoi
Le cœur du défi est l'alerte **multi-fenêtre** : la fenêtre longue (1 h)
garantit que l'incident est significatif (pas un pic de 30 s), la fenêtre
courte (5 min) garantit que l'alerte se **résout** vite une fois le
problème corrigé (sans elle, la page resterait active près d'une heure).
Les seuils 14,4 et 6 viennent du *SRE Workbook* : 14,4 = consommer 2 % du
budget mensuel en 1 h (30 j × 24 h × 2 % = 14,4 h… soit tout le budget en
2 jours) ; 6 = 5 % du budget en 6 h. Ils encodent une politique : on
réveille quelqu'un seulement si, à ce rythme, le mois est fichu dans 2
jours. Tout le reste du dossier (kustomize, PDB, HPA, runbooks, script)
n'est que la mise en forme reproductible de cette politique — un collègue
doit pouvoir la reconstruire et la contester chiffres en main.
:::

::: piege
`kubectl apply -k` avec `namespace: factura` dans la kustomization réécrit
le namespace de **tous** les objets, y compris ceux qui en ont déjà un ;
c'est voulu ici, mais un objet cluster (ClusterRole) n'est pas touché et
un objet d'un autre namespace serait déplacé. Le `secretGenerator`
régénère les Secrets à chaque `apply` : sans `disableNameSuffixHash`, les
noms changent et les références cassent. Le `runbook_url` en `file://`
est un pis-aller de lab : Alertmanager le transmet tel quel, aucun
navigateur ne l'ouvrira depuis une notification — en production c'est une
URL de wiki. Et attention à `increase(...[30d])` dans le tableau SLO : sur
15 jours de rétention (`--storage.tsdb.retention.time=15d`), la fenêtre
est tronquée ; le budget affiché est donc « sur 15 jours au mieux ».
:::
