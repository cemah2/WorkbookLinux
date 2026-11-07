<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Partie V — Expertise système › **Module 30** · corrigé  
[← Module 29](../29-haute-disponibilite/corrige.md) · [Énoncé](README.md) · [Module 31 →](../31-tracage-ebpf-perf/corrige.md)

> [!TIP]
> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, pas avant. Chaque identifiant renvoie à son énoncé.
<!-- nav:fin -->

# Module 30 — Corrigé

## 30.3 Quiz — QCM

<a id="q30-1"></a>**[Q30.1](README.md#q30-1)** — *Perdre au plus 15 minutes, être rétabli en moins d'une heure.*

**Réponse : b)** RPO 15 min, RTO 1 h.

> [!NOTE]
> **Pourquoi**
>
> * **RPO** (*Recovery Point Objective*) : l'âge maximal des données qu'on
>   accepte de perdre, donc l'écart maximal entre deux points de sauvegarde
>   exploitables. Il fixe la **fréquence** (ou la continuité) des sauvegardes.
> * **RTO** (*Recovery Time Objective*) : la durée maximale d'interruption,
>   de la panne au service rétabli. Il fixe la **méthode** de restauration
>   (copie de fichiers, VM entière, secondaire prêt à prendre le relais) et
>   l'entraînement de l'équipe.
>
> MTBF et MTTR mesurent la fiabilité observée (module 29) ; SLA et SLO sont
> des engagements de service. Les deux chiffres de l'énoncé sont des
> **objectifs** : le module apprend à mesurer ce qui est réellement atteint,
> qui est souvent très différent.

---

<a id="q30-2"></a>**[Q30.2](README.md#q30-2)** — *Protection contre un `DROP TABLE`.*

**Réponse : d)** archivage continu des WAL vers un autre serveur + sauvegarde de base.

> [!NOTE]
> **Pourquoi**
>
> * Le RAID et la réplique synchrone recopient fidèlement l'erreur, en
>   quelques millisecondes : ils protègent contre une panne matérielle, pas
>   contre une décision humaine.
> * L'instantané LVM horaire marche… jusqu'à ce que le groupe de volumes
>   meure, avec ses instantanés. Il fait perdre jusqu'à une heure (RPO) et
>   dégrade les performances d'écriture (copie sur écriture) : c'est un outil
>   de retour arrière pour une intervention, pas une sauvegarde.
> * L'archivage des WAL sur une autre machine permet de rejouer l'activité
>   jusqu'à la seconde qui précède le `DROP` (L30.3), et survit à la perte de
>   `lab-db`.

---

<a id="q30-3"></a>**[Q30.3](README.md#q30-3)** — *`restic forget` sans `--prune`.*

**Réponse : a)** retire les instantanés de la liste ; la place n'est libérée qu'au `prune`.

> [!NOTE]
> **Pourquoi**
>
> Dans un dépôt dédupliqué, un bloc de données peut appartenir à des
> centaines d'instantanés. `forget` supprime seulement les fichiers
> d'instantanés (petits) qui sortent de la politique. `prune` parcourt ensuite
> tout le dépôt, repère les blocs que **plus aucun** instantané ne référence,
> et réécrit les paquets qui en contiennent : opération longue, gourmande en
> entrées-sorties, et qui prend un verrou exclusif.
>
> On sépare souvent les deux : `forget` à chaque sauvegarde, `prune` une fois
> par semaine. `restic forget --dry-run` (E30.4) montre ce qu'une politique
> garderait avant de rien toucher.

---

<a id="q30-4"></a>**[Q30.4](README.md#q30-4)** — *Découpage en blocs de taille variable.*

**Réponse : c)** une insertion ne décale pas tous les blocs suivants.

> [!NOTE]
> **Pourquoi**
>
> Avec des blocs de taille fixe (4 Mo, par exemple), ajouter un octet au début
> d'un fichier de 10 Go décale toutes les frontières : chaque bloc est
> « nouveau », la déduplication ne reconnaît plus rien. Le découpage **défini
> par le contenu** (*content-defined chunking*) calcule une empreinte glissante
> (Rabin chez restic, buzhash chez borg) et coupe là où elle vérifie une
> condition : les frontières suivent le contenu et se resynchronisent juste
> après la modification. Seuls un ou deux blocs changent.
>
> C'est ce qui permet de garder des centaines d'instantanés quotidiens d'une
> machine pour à peine plus que la place d'une copie (E30.5).

---

<a id="q30-5"></a>**[Q30.5](README.md#q30-5)** — *`borg delete` contre un dépôt en ajout seul.*

**Réponse : c)** la suppression est enregistrée, les données restent, on peut revenir en arrière.

> [!NOTE]
> **Pourquoi**
>
> En mode ajout seul, `borg serve` n'écrit jamais rien d'autre que des
> **nouveaux** segments : une suppression d'archive devient une transaction
> supplémentaire qui dit « cette archive n'existe plus », mais les segments
> qui contiennent les données ne sont ni réécrits ni compactés (`borg compact`
> n'efface rien, sans même le signaler). Le fichier `transactions` du dépôt garde l'historique daté de
> chaque transaction : l'administrateur du serveur supprime les segments
> postérieurs à l'attaque et retrouve le dépôt tel qu'il était (L30.2).
>
> La suppression du dépôt entier est, elle, refusée (`… is in append-only
> mode`). Le prix du mode : la place
> ne diminue jamais d'elle-même ; un administrateur doit compacter
> périodiquement, depuis le serveur, avec un accès qui n'est pas en ajout seul.

---

<a id="q30-6"></a>**[Q30.6](README.md#q30-6)** — *Ce que garantit `archive_command`.*

**Réponse : d)** un 0 menteur fait recycler un segment qui n'est pas en sécurité.

> [!NOTE]
> **Pourquoi**
>
> PostgreSQL appelle `archive_command` pour chaque segment terminé, et
> attend : code 0, le segment est réputé archivé, et il pourra être recyclé
> ou supprimé après le prochain point de contrôle ; code non nul, il réessaie
> plus tard (toutes les minutes environ) et **garde** le segment dans
> `pg_wal` (d'où BF30.2). Une commande qui « réussit » sans avoir copié (un
> `cp` vers un montage absent qui écrit dans un répertoire vide local, un
> script sans `set -e`) produit une archive trouée qu'on découvre le jour de
> la restauration.
>
> La commande tourne sous l'identité du serveur (`postgres`), jamais root : ses
> clés SSH, ses droits sur le stockage d'archive sont ceux de `postgres`.

---

<a id="q30-7"></a>**[Q30.7](README.md#q30-7)** — *Minimum nécessaire pour un PITR.*

**Réponse : a)** une sauvegarde de base antérieure et **tous** les WAL jusqu'à l'instant visé.

> [!NOTE]
> **Pourquoi**
>
> La sauvegarde de base est une copie des fichiers de l'instance prise
> pendant qu'elle tourne, donc incohérente en elle-même. Elle note dans
> `backup_label` le point des WAL à partir duquel il faut rejouer. Au
> démarrage, PostgreSQL rejoue **chaque** segment depuis ce point jusqu'à la
> cible : un seul segment manquant arrête la restauration à cet endroit, sans
> possibilité d'aller au-delà.
>
> D'où les deux règles d'exploitation : surveiller l'archivage en continu
> (aucun trou), et garder les WAL au moins depuis la plus ancienne sauvegarde
> de base qu'on conserve (`pg_archivecleanup` sait supprimer ce qui précède).

---

<a id="q30-8"></a>**[Q30.8](README.md#q30-8)** — *Démarrer en restauration d'archive depuis PostgreSQL 12.*

**Réponse : b)** un fichier vide `recovery.signal`, les paramètres dans la configuration.

> [!NOTE]
> **Pourquoi**
>
> `recovery.conf` a disparu en PostgreSQL 12 : sa présence empêche même le
> démarrage. Les paramètres (`restore_command`, `recovery_target_*`) sont des
> paramètres de configuration ordinaires (`postgresql.conf`, un fichier de
> `conf.d/` sur Debian, ou `postgresql.auto.conf`), et deux fichiers vides
> choisissent le mode :
>
> * `recovery.signal` : restauration d'archive, puis fin de la restauration
>   (promotion, pause ou arrêt selon `recovery_target_action`) ;
> * `standby.signal` : réplique, qui reste en restauration indéfiniment.
>
> Une fois promue, l'instance supprime `recovery.signal`.

---

<a id="q30-9"></a>**[Q30.9](README.md#q30-9)** — *`pg_dump` ou `pg_basebackup`.*

**Réponse : c).**

> [!NOTE]
> **Pourquoi**
>
> | | `pg_dump` | `pg_basebackup` (+ WAL) |
> |---|---|---|
> | Nature | logique (SQL / format personnalisé) | physique (fichiers de l'instance) |
> | Portée | une base, tables choisies | l'instance entière (toutes les bases) |
> | Version | restaurable dans une version **plus récente** | même version majeure, même architecture |
> | Point de restauration | l'instant du dump | n'importe quel instant couvert par les WAL |
> | Durée de restauration | longue (index et contraintes recréés) | proportionnelle à la taille, + rejeu |
>
> Les deux sont complémentaires : la sauvegarde physique pour le PITR et le
> RTO, le dump pour les restaurations partielles (une table), les migrations de
> version et une copie indépendante du format physique.

---

<a id="q30-10"></a>**[Q30.10](README.md#q30-10)** — *Cohérence d'un `vzdump` en mode `snapshot`.*

**Réponse : d)** l'agent invité QEMU gèle les systèmes de fichiers.

> [!NOTE]
> **Pourquoi**
>
> En mode `snapshot`, la VM continue de tourner ; `vzdump` lit son disque
> pendant que QEMU redirige les nouvelles écritures. Sans précaution, l'image
> obtenue est celle d'une machine qu'on aurait débranchée : cohérente au
> niveau du bloc, mais avec des tampons non écrits (« *crash-consistent* »).
> Avec l'option agent activée et `qemu-guest-agent` dans l'invité, `vzdump`
> demande un `fs-freeze` : l'invité vide ses tampons et suspend les écritures
> le temps de démarrer la sauvegarde, puis `fs-thaw`. Le journal de la tâche
> le montre (L30.4).
>
> Pour une base de données, le gel donne un système de fichiers propre, mais
> la base reste « arrêtée brutalement » de son point de vue : elle rejouera
> ses WAL au démarrage. C'est sûr, pas équivalent à une sauvegarde de base
> applicative.

---

<a id="q30-11"></a>**[Q30.11](README.md#q30-11)** — *`qmrestore --unique 1`.*

**Réponse : a)** de nouvelles adresses MAC, pour ne pas entrer en conflit avec l'originale.

> [!NOTE]
> **Pourquoi**
>
> Sans `--unique`, la VM restaurée reprend la configuration à l'identique,
> adresses MAC comprises. Démarrée sur le même pont que l'originale, elle
> présente la même MAC et, avec cloud-init, la même adresse IP : le pont voit
> la même adresse sur deux ports et achemine le trafic tantôt vers l'une,
> tantôt vers l'autre. C'est BF30.3. `--unique` régénère aussi l'UUID SMBIOS
> de la VM. Il ne suffit pas à rendre un exercice sûr : la copie a toujours
> la même IP, d'où le pont isolé `vmbr9`.

---

<a id="q30-12"></a>**[Q30.12](README.md#q30-12)** — *La phrase de passe restic n'existe que sur `lab-web`.*

**Réponse : c)** les sauvegardes sont illisibles.

> [!NOTE]
> **Pourquoi**
>
> restic chiffre tout le dépôt avec une clé maîtresse, elle-même chiffrée par
> la phrase de passe (dérivation scrypt). Sans phrase, la clé est
> inaccessible : ni restic, ni l'administrateur de `lab-ops`, ni personne ne
> peut lire les données. C'est voulu (le serveur de sauvegarde n'a pas à voir
> le contenu), et c'est le piège le plus cruel des sauvegardes chiffrées : la
> seule copie du secret était sur la machine perdue.
>
> La phrase (et pour borg, la clé exportée) se range **avec** le PRA, hors de
> toute machine sauvegardée, en au moins deux exemplaires (QO30.6).

---

<a id="q30-13"></a>**[Q30.13](README.md#q30-13)** — *`restic check --read-data-subset=10%`.*

**Réponse : d)** il relit réellement 10 % des données.

> [!NOTE]
> **Pourquoi**
>
> `restic check` seul vérifie la **structure** : les index, les instantanés et
> les arbres sont cohérents, chaque bloc référencé est censé exister dans un
> paquet. Il ne lit pas le contenu des paquets, qui peut être corrompu
> (disque défaillant, copie tronquée) sans que la structure le montre.
> `--read-data` télécharge et vérifie l'empreinte de **tous** les paquets ;
> `--read-data-subset=10%` en vérifie une fraction (aléatoire, ou
> `n/t` pour une tranche déterminée), ce qui permet de tout relire en dix
> passages sans payer le coût d'un coup. Sur un stockage distant facturé au
> téléchargement, c'est le compromis classique.

---

<a id="q30-14"></a>**[Q30.14](README.md#q30-14)** — *Le serveur de sauvegarde tire les données.*

**Réponse : a)** la machine sauvegardée n'a aucun accès aux sauvegardes.

> [!NOTE]
> **Pourquoi**
>
> En mode **poussé**, la machine sauvegardée possède des identifiants qui
> écrivent sur le stockage de sauvegarde : un attaquant root sur cette
> machine les utilise pour effacer ou chiffrer les sauvegardes avant de
> frapper. En mode **tiré**, c'est le serveur de sauvegarde qui se connecte, et
> la machine sauvegardée ne connaît aucun secret du stockage. La sauvegarde de
> base de L30.3 suit ce modèle.
>
> Le mode tiré a son revers : le serveur de sauvegarde devient une machine qui
> a accès à **tout** le parc, à protéger d'autant plus (accès d'administration
> restreint, pas de service exposé). Le mode ajout seul (borg) ou l'objet
> verrouillé (S3 *object lock*) donne la même garantie en mode poussé.

---

<a id="q30-15"></a>**[Q30.15](README.md#q30-15)** — *RPO réel avec `archive_timeout = 300`.*

**Réponse : b)** environ 5 minutes au plus en régime normal.

> [!NOTE]
> **Pourquoi**
>
> Un segment WAL (16 Mo) n'est archivé qu'une fois **plein**, ou au bout de
> `archive_timeout` secondes s'il y a eu de l'activité depuis le dernier
> changement. Sur une base peu active, sans `archive_timeout`, un segment
> pourrait rester des heures dans `pg_wal` : sa perte (disque de `lab-db`
> détruit) ferait perdre tout ce qu'il contient. Avec 300 s, la perte est
> bornée à environ 5 minutes plus le temps de copie. La table témoin de L30.3
> le mesure.
>
> Pour descendre sous la minute, `archive_timeout` devient coûteux (un segment
> par changement forcé, même quasi vide : d'où la compression) ; on passe
> alors à `pg_receivewal`, qui reçoit les WAL en continu par le protocole de
> réplication, avec un RPO de quelques secondes.

---

<a id="q30-16"></a>**[Q30.16](README.md#q30-16)** — *Restauration réussie, reprise ratée.*

**Réponse : c)** un plan de reprise d'activité écrit.

> [!NOTE]
> **Pourquoi**
>
> La restauration est une étape technique ; la **reprise** est une opération
> d'équipe : qui décide de déclencher, dans quel ordre on remonte les
> composants (la base avant l'API, le cache avant les workers…), comment on
> valide que c'est bon (critères métier, pas « ça démarre »), qui on prévient
> et quand, comment on revient à la normale. Sans document, chacun improvise
> sous pression, et le RTO explose bien au-delà de la durée des restaurations.
> D30 produit ce document.

---

## 30.4 Quiz — questions ouvertes

<a id="qo30-1"></a>**[QO30.1](README.md#qo30-1)** — *Concevoir la sauvegarde d'un service.*

**Réponse attendue**

On part de la **restauration**, pas de la sauvegarde :

1. **Inventaire** : quelles données ont de la valeur (base, fichiers
   déposés, configuration, secrets, code ?), lesquelles se recréent
   (paquets, caches, images de conteneur reconstructibles), où elles vivent.
2. **Objectifs** par donnée, avec le métier : RPO et RTO, et la durée de
   rétention (obligations légales : factures conservées dix ans, par
   exemple ; droit à l'effacement pour les données personnelles).
3. **Menaces** couvertes : panne de disque, perte de machine, erreur
   humaine, rançongiciel, perte du site. Chacune dicte une propriété
   (hors machine, historique, immuable, hors site).
4. **Méthodes** : choisies pour tenir le RTO (une base de 500 Go ne se
   restaure pas d'un dump en 30 minutes) et le RPO (archivage continu ou
   quotidien).
5. **Mise en œuvre** : 3-2-1-1-0, chiffrement, clés rangées hors des
   machines, comptes de dépôt restreints, supervision (âge de la dernière
   sauvegarde, taille, échecs).
6. **Tests de restauration** planifiés, mesurés, documentés dans un PRA.

La phrase à retenir : « personne ne veut de sauvegardes ; tout le monde veut
des restaurations ».

---

<a id="qo30-2"></a>**[QO30.2](README.md#qo30-2)** — *Root sur `lab-db` : que peut-il détruire ?*

**Réponse attendue**

| Sauvegarde | Ce que l'attaquant peut faire depuis `lab-db` | Pour aller plus loin |
|---|---|---|
| restic de `lab-web` (poussé depuis `lab-web`) | rien directement : aucun secret de ce dépôt sur `lab-db`. Mais s'il rebondit sur `lab-web`, la clé SSH du compte `restic` permet d'effacer les fichiers du dépôt par SFTP | `rest-server --append-only`, ou un second dépôt copié par `lab-ops` vers un stockage que `lab-web` ne voit pas |
| borg de `lab-db` (ajout seul) | ajouter de fausses archives, « supprimer » les existantes (réversible), lire ses propres archives (il a la clé) ; il ne peut ni effacer les segments ni supprimer le dépôt | surveiller les transactions inattendues (suppression hors de la rétention), compacter rarement et après vérification, garder une copie hors site |
| WAL archivés (poussés) | écrire des segments (`rrsync -wo`), donc remplir le disque ou déposer des segments piégés sous de nouveaux noms ; pas lire ni effacer | quota sur `/srv/pgwal`, alerte sur les volumes anormaux |
| sauvegardes de base (tirées) | rien : il ne connaît pas `lab-ops`. Il peut seulement saboter les **prochaines** (base chiffrée, données corrompues, mot de passe du rôle changé) | garder plusieurs générations, alerte si une sauvegarde échoue ou change brutalement de taille |

Et dans tous les cas : il peut corrompre les données **avant** qu'elles soient
sauvegardées, et attendre que la rétention fasse disparaître les bonnes
copies. D'où une rétention longue (mensuelles sur 6 mois et plus) et des
contrôles métier sur les restaurations (D30).

---

<a id="qo30-3"></a>**[QO30.3](README.md#qo30-3)** — *Mécanique du PITR.*

**Réponse attendue**

* PostgreSQL écrit chaque modification d'abord dans le **WAL** (journal
  d'écriture anticipée), en segments de 16 Mo, puis, plus tard, dans les
  fichiers de données. En cas d'arrêt brutal, il rejoue le WAL depuis le
  dernier point de contrôle : c'est la reprise après incident.
* La **sauvegarde de base** est une copie des fichiers de données faite à
  chaud. `pg_basebackup` marque le début (point de contrôle, LSN écrit dans
  `backup_label`) et la fin ; entre les deux, les fichiers changent sous la
  copie.
* Les **WAL archivés** contiennent toutes les modifications depuis.
* Au démarrage avec `recovery.signal`, l'instance part des fichiers de la
  sauvegarde, lit `backup_label`, réclame chaque segment par
  `restore_command` et rejoue les modifications dans l'ordre. Une fois passé
  le point de fin de sauvegarde, l'état est cohérent ; elle continue jusqu'à
  la cible (`recovery_target_*`) ou jusqu'à la fin des archives, puis se
  promeut.
* La promotion crée une **nouvelle timeline** (2, puis 3…) : les WAL écrits
  ensuite portent un nouveau préfixe (`00000002…`) et un fichier
  `00000002.history` note l'embranchement. Sans cela, les WAL de l'instance
  restaurée et ceux de l'ancienne histoire porteraient les mêmes noms et
  s'écraseraient dans l'archive : on ne pourrait plus restaurer ni l'une ni
  l'autre. C'est aussi pourquoi l'instance de restauration de L30.3 ne doit
  pas archiver dans le même dépôt.

---

<a id="qo30-4"></a>**[QO30.4](README.md#qo30-4)** — *« Zéro perte, zéro interruption. »*

**Réponse attendue**

On traduit en chiffres et en coûts, sans dire non :

* **Zéro perte** (RPO = 0) exige une écriture synchrone sur au moins deux
  sites avant de confirmer chaque transaction (réplication synchrone) : chaque
  écriture devient plus lente (aller-retour réseau), et si le second site
  tombe, il faut choisir entre bloquer les écritures et accepter une perte.
  Et cela ne protège toujours pas contre une erreur humaine, qui est
  répliquée : il faut **en plus** l'archivage (RPO de quelques minutes pour
  ce cas).
* **Zéro interruption** n'existe pas ; on parle de « nines » (module 29).
  Chaque neuf supplémentaire multiplie le coût (matériel en double, second
  site, astreinte, tests).
* On propose des paliers chiffrés : « RPO 5 min / RTO 1 h pour X € par mois
  (archivage + restauration testée) ; RPO 0 / RTO 5 min pour un second site
  en réplication synchrone et une équipe d'astreinte, soit 10 X ». Le
  métier choisit en connaissant le coût d'une heure d'arrêt et d'une heure de
  données perdues.

---

<a id="qo30-5"></a>**[QO30.5](README.md#qo30-5)** — *Un test de restauration réussi.*

**Réponse attendue**

Critères :

* la restauration se fait **sur une autre machine**, avec la documentation
  du PRA et les clés rangées hors site, pas avec la mémoire de l'auteur ;
* elle se termine sans erreur, et les **contrôles métier** passent (nombre
  de lignes, dernière facture, page d'accueil servie, fichier critique
  présent et valide), pas seulement « le service démarre » ;
* le **RPO réel** (donnée la plus récente restaurée) et le **RTO réel**
  (durée totale) sont mesurés et comparés aux objectifs ;
* les écarts donnent lieu à une action.

Fréquence indicative :

| Sauvegarde | Fréquence du test |
|---|---|
| contrôle automatique de l'archive (`restic check`, `borg check`) | à chaque sauvegarde ou chaque semaine |
| restauration automatique d'un échantillon (fichier témoin, base complète en instance jetable) | chaque semaine (D30) |
| restauration complète d'une VM ou d'un service en réseau isolé | chaque trimestre |
| exercice de PRA avec l'équipe | chaque année, et après tout changement majeur |

---

<a id="qo30-6"></a>**[QO30.6](README.md#qo30-6)** — *Ranger les clés de sauvegarde.*

**Réponse attendue**

* Jamais seulement sur la machine sauvegardée, ni seulement dans le
  coffre-fort de secrets **qui est lui-même sauvegardé par ce système**
  (dépendance circulaire : pour restaurer le coffre, il faut la clé qui est
  dans le coffre).
* Au moins deux exemplaires, dans deux lieux : un coffre-fort de secrets
  d'équipe (accès nominatif, journalisé), **et** une copie hors ligne (clé
  borg exportée au format papier, enveloppe scellée dans un coffre physique,
  ou support chiffré confié à la direction).
* Le PRA dit où sont les clés et qui y a accès, sans les contenir.
* Au départ d'un administrateur qui les connaissait : pour restic,
  `restic key add` puis `restic key remove` de l'ancienne (la clé maîtresse
  ne change pas, mais l'ancienne phrase ne l'ouvre plus) ; pour borg,
  `borg key change-passphrase`. Les données déjà sauvegardées restent
  chiffrées par la même clé maîtresse : si l'on soupçonne une copie de la
  clé maîtresse elle-même, il faut un nouveau dépôt.
* Tester la restauration **avec** les clés du coffre, pas avec celles déjà
  présentes sur la machine.

---

<a id="qo30-7"></a>**[QO30.7](README.md#qo30-7)** — *Copier `/var/lib/postgresql/16/main` à chaud.*

**Réponse attendue**

Les fichiers de données changent pendant la copie : restic lit le fichier
de la table A à 10:00:01 et celui de son index à 10:00:40, chacun dans un
état différent, et une partie des modifications n'est encore que dans les
tampons ou dans le WAL. Le résultat est un mélange d'instants que PostgreSQL
ne sait pas réparer sans le WAL correspondant : au mieux il refuse de
démarrer, au pire il démarre avec des données silencieusement corrompues.

Une copie de fichiers est acceptable :

* instance **arrêtée** proprement (copie froide) ;
* ou instantané **atomique** de tout le système de fichiers qui contient les
  données **et** `pg_wal` (LVM, ZFS, gel de la VM), restauré tel quel : la
  base redémarre comme après une coupure et rejoue son WAL ;
* ou dans le cadre d'une sauvegarde de base (`pg_backup_start` /
  `pg_backup_stop`), avec l'archivage des WAL, ce que fait `pg_basebackup`.

C'est pourquoi L30.2 sauvegarde un `pg_dump` avec borg, et pas le répertoire
de données.

---

<a id="qo30-8"></a>**[QO30.8](README.md#qo30-8)** — *Quel outil pour quoi sur Factura.*

**Réponse attendue**

* **PostgreSQL** : archivage des WAL + sauvegardes de base (ou pgBackRest)
  pour le PITR et le RTO ; `pg_dump` quotidien en plus, pour les
  restaurations d'une table et l'indépendance vis-à-vis du format physique.
* **Fichiers** (`/srv/factura/exports`, configuration, certificats) :
  restic ou borg, dédupliqués, chiffrés, historisés ; un dépôt en ajout seul
  ou immuable hors site.
* **VM entières** (`vzdump`, ou Proxmox Backup Server pour l'incrémental) :
  pour reconstruire vite une machine dont la configuration n'est pas
  entièrement décrite par le code ; inutile pour les machines recréées par
  OpenTofu + Ansible (projet B), dont le code dans Git **est** la
  sauvegarde.
* **Git** (code, inventaire, rôles Ansible) : la forge elle-même est
  sauvegardée (`gitea dump`), et chaque poste a un clone.

Un seul outil pour tout serait soit incapable du PITR (outil de fichiers),
soit trop lourd pour restaurer un fichier (image de VM). Chaque niveau
répond à un RPO, un RTO et une granularité différents.

---

## 30.5 Exercices guidés

<a id="e30-1"></a>**[E30.1](README.md#e30-1)** — *Le témoin s'alimente.*

```bash
sudo -u postgres psql -d lab30 -c \
  "SELECT t FROM pra.temoin ORDER BY t DESC LIMIT 3;"
sudo -u postgres psql -d lab30 -Atc \
  "SELECT now() - max(t) FROM pra.temoin;"     # moins d'une minute
systemctl list-timers lab30-temoin.timer
```

> [!NOTE]
> **Pourquoi**
>
> Une ligne datée écrite chaque minute est le moyen le plus simple de mesurer
> un RPO : dans une restauration, `max(t)` dit jusqu'où les données vont. Le
> même principe s'applique aux fichiers (un fichier témoin réécrit chaque
> heure) et se retrouve dans D30.

---

<a id="e30-2"></a>**[E30.2](README.md#e30-2)** — *Instantanés et contenu, sans restaurer.*

```bash
sudo -i
set -a; . /etc/restic/lab-web.env; set +a
restic snapshots
restic ls latest /etc/nginx
```

> [!NOTE]
> **Pourquoi**
>
> `set -a` exporte toutes les variables lues dans le fichier d'environnement,
> qui est le même que celui de l'unité systemd (`EnvironmentFile=`) : une seule
> source de configuration pour le timer et pour l'administrateur.
> `restic ls` lit l'arbre de l'instantané dans le dépôt sans rien écrire sur
> le disque local.

---

<a id="e30-3"></a>**[E30.3](README.md#e30-3)** — *Où est `nginx.conf`, et ce qui a changé.*

```bash
restic find nginx.conf
restic snapshots --compact | tail -3
restic diff <avant-dernier> <dernier>
#   M    /etc/nginx/sites-available/lab30
#   +    /var/www/lab30/nouveau.html
#   Files: 1 new, 0 removed, 1 changed
```

> [!NOTE]
> **Pourquoi**
>
> `restic diff` compare les arbres, pas les données : il est rapide, et
> `--metadata` montre aussi les changements de droits ou de propriétaire.
> C'est l'outil d'enquête après incident (« qu'est-ce qui a changé dans
> `/etc` entre mardi et mercredi ? ») autant que de restauration.

---

<a id="e30-4"></a>**[E30.4](README.md#e30-4)** — *Ce que garderait une politique de rétention.*

```bash
restic forget --dry-run --keep-daily 7 --keep-weekly 4
```

> [!NOTE]
> **Pourquoi**
>
> La sortie liste, par groupe (hôte + chemins), les instantanés gardés avec la
> **raison** (`daily snapshot`, `weekly snapshot`) et ceux qui seraient
> retirés. Les règles se cumulent : un instantané gardé comme quotidien peut
> aussi compter comme hebdomadaire. Toujours essayer une politique en
> `--dry-run` avant de la mettre dans un timer : une faute de frappe
> (`--keep-last 1`) efface l'historique au premier passage.

---

<a id="e30-5"></a>**[E30.5](README.md#e30-5)** — *Place réelle et volume restauré.*

```bash
restic stats --mode raw-data           # octets réellement stockés (compressés, dédupliqués)
restic stats --mode restore-size       # ce que donnerait la restauration de tous les instantanés
```

> [!NOTE]
> **Pourquoi**
>
> Avec dix instantanés quasi identiques de 300 Mo, `restore-size` affiche
> environ 3 Go et `raw-data` un peu plus de 100 Mo : la déduplication stocke
> une seule fois chaque bloc commun, et la compression (format de dépôt v2,
> restic ≥ 0.14) réduit encore. L'écart est le bénéfice de la déduplication ;
> une **chute** brutale de `restore-size` entre deux sauvegardes est un
> signal d'alerte (BF30.1).

---

<a id="e30-6"></a>**[E30.6](README.md#e30-6)** — *Archives borg et statistiques.*

```bash
sudo -i
set -a; . /etc/borg/lab-db.env; set +a
borg list
borg info ::"$(borg list --last 1 --short)"
#   Original size      Compressed size    Deduplicated size
#   This archive:   52.31 MB      9.87 MB      214.02 kB
#   All archives:  261.40 MB     49.30 MB     11.06 MB
```

> [!NOTE]
> **Pourquoi**
>
> La dernière colonne de la ligne *This archive* est ce que l'archive a
> **ajouté** au dépôt : quelques centaines de ko pour une journée où peu de
> choses ont changé. La ligne *All archives* donne la taille totale du dépôt.
> C'est ce chiffre qui doit croître lentement ; une archive qui ajoute soudain
> autant que l'originale signale des données devenues illisibles pour la
> déduplication (fichiers chiffrés par un rançongiciel, par exemple).

---

<a id="e30-7"></a>**[E30.7](README.md#e30-7)** — *Clé borg au format papier.*

```bash
borg key export --paper :: /root/borg-cle-lab-db.papier
cat /root/borg-cle-lab-db.papier       # lignes de 6 groupes avec somme de contrôle
```

> [!NOTE]
> **Pourquoi**
>
> Le format `--paper` découpe la clé en lignes courtes, chacune avec une somme
> de contrôle : on peut la ressaisir à la main (`borg key import --paper`) et
> une faute de frappe est détectée ligne par ligne. Elle va dans le coffre
> physique du PRA ; le fichier sur `lab-db` est ensuite supprimé
> (`shred -u`). Avec `repokey`, la clé est aussi **dans le dépôt**, chiffrée
> par la phrase : l'export protège contre la corruption de cette copie, la
> phrase reste indispensable.

---

<a id="e30-8"></a>**[E30.8](README.md#e30-8)** — *État de l'archivage, changement de segment.*

```bash
sudo -u postgres psql -x -c "SELECT archived_count, last_archived_wal,
  last_archived_time, failed_count, last_failed_wal FROM pg_stat_archiver;"
sudo -u postgres psql -Atc "SELECT pg_walfile_name(pg_switch_wal());"
#   000000010000000000000021
# lab-ops, quelques secondes plus tard :
ls -l /srv/pgwal/000000010000000000000021.zst
```

> [!NOTE]
> **Pourquoi**
>
> `pg_switch_wal()` termine le segment en cours, ce qui déclenche son
> archivage : c'est la manière de vérifier la chaîne de bout en bout sans
> attendre `archive_timeout`, et de « fermer » proprement l'archive avant une
> opération risquée. Le segment forcé est presque vide : compressé, il pèse
> quelques dizaines de ko au lieu de 16 Mo.

---

<a id="e30-9"></a>**[E30.9](README.md#e30-9)** — *LSN, segment, contenu de `pg_wal`.*

```bash
sudo -u postgres psql -Atc \
  "SELECT pg_current_wal_lsn(), pg_walfile_name(pg_current_wal_lsn());"
#   0/22A4F1E8|000000010000000000000022
sudo ls /var/lib/postgresql/16/main/pg_wal | grep -c '^0000'
```

> [!NOTE]
> **Pourquoi**
>
> Le nom d'un segment code la timeline (8 chiffres hexadécimaux), puis le LSN
> découpé en « fichier logique » et numéro de segment de 16 Mo. Le nombre de
> segments présents est normalement borné par `max_wal_size` et
> `wal_keep_size` ; s'il croît sans cesse, quelque chose les retient :
> archivage en échec (BF30.2) ou emplacement de réplication abandonné.

---

<a id="e30-10"></a>**[E30.10](README.md#e30-10)** — *`backup_label` sans tout extraire.*

```bash
cd /srv/pgbase/"$(ls -1 /srv/pgbase | tail -1)"
tar -xzOf base.tar.gz backup_label
#   START WAL LOCATION: 0/1F000028 (file 00000001000000000000001F)
#   CHECKPOINT LOCATION: 0/1F000060
#   BACKUP METHOD: streamed
#   START TIME: 2026-11-09 10:15:02 CET
```

> [!NOTE]
> **Pourquoi**
>
> `START WAL LOCATION` est le premier segment nécessaire : tout ce qui le
> précède dans `/srv/pgwal` est inutile **pour cette sauvegarde**. Si elle est
> la plus ancienne conservée, `pg_archivecleanup -x .zst /srv/pgwal
> 00000001000000000000001F` supprime ce qui précède. Avec `-Xs`, les segments
> couverts par la sauvegarde elle-même sont aussi dans `pg_wal.tar.gz` : la
> sauvegarde est restaurable seule, sans archive, jusqu'à sa propre fin.

---

<a id="e30-11"></a>**[E30.11](README.md#e30-11)** — *Sauvegardes `vzdump` de `lab-web`.*

```bash
pvesm list local --content backup --vmid 9002
pvesh get /nodes/pve/storage/local/content --content backup --vmid 9002 \
  --output-format json | jq -r '.[] | "\(.volid)  \(.size/1048576|floor) Mo  \(.notes // "")"'
```

> [!NOTE]
> **Pourquoi**
>
> Les notes (`--notes-template`) sont la seule façon de distinguer « la
> sauvegarde d'avant la mise à jour » de la quotidienne au moment où l'on en a
> besoin. `pvesh` interroge l'API, ce qui donne une sortie JSON exploitable,
> la même que celle d'un outil d'automatisation.

---

<a id="e30-12"></a>**[E30.12](README.md#e30-12)** — *RPO réel depuis le témoin.*

```bash
# sur l'instance restaurée de L30.3 (lab-ops, port 5439)
sudo -u postgres psql -p 5439 -d lab30 -Atc "SELECT max(t) FROM pra.temoin;"
```

Le RPO réel est l'écart entre ce `max(t)` et l'instant où l'on aurait perdu
`lab-db` (pour L30.3 : l'accident). Il dépasse `archive_timeout` pour deux
raisons : le dernier segment est archivé au plus `archive_timeout` après sa
première écriture, **plus** le temps de copie ; et la restauration s'arrête
à une transaction validée, pas à une seconde quelconque. Avec une cible
précise (L30.3), le RPO est en fait de quelques secondes **pour cet
incident**, puisque l'archive continuait de recevoir les WAL après
l'accident.

---

## 30.6 Labs

### <a id="l30-1"></a>**[L30.1](README.md#l30-1)** — Les fichiers de lab-web, chiffrés, hors de lab-web

**Étape 1 — Le compte `restic` en prison (lab-ops)**

```bash
sudo install -d -o root -g root -m 755 /srv/restic
sudo install -d -o restic -g restic -m 700 /srv/restic/lab-web
sudo install -d -o restic -g restic -m 700 /home/restic/.ssh
sudo tee /etc/ssh/sshd_config.d/30-restic.conf >/dev/null <<'EOF'
Match User restic
    ChrootDirectory /srv/restic
    ForceCommand internal-sftp
    AllowTcpForwarding no
    AllowAgentForwarding no
    X11Forwarding no
    PermitTTY no
    PasswordAuthentication no
EOF
sudo sshd -t && sudo systemctl reload ssh
sudo sshd -T -C user=restic,host=lab-web,addr=10.10.10.11 | grep -Ei 'chroot|forcecommand'
```

> [!NOTE]
> **Pourquoi**
>
> * **`ChrootDirectory`** enferme la session dans `/srv/restic` : le compte ne
>   voit que ce répertoire. OpenSSH exige que le répertoire de prison et tous
>   ses parents appartiennent à root et ne soient pas inscriptibles par un
>   autre utilisateur ; d'où `root:root 755` pour `/srv/restic`, et un
>   sous-répertoire à `restic` pour les données.
> * **`internal-sftp`** est le serveur SFTP intégré à `sshd` : pas besoin de
>   binaire ni de bibliothèque dans la prison, et aucune commande ne peut être
>   exécutée.
> * `sshd -T -C …` affiche la configuration **effective** pour une connexion
>   donnée, blocs `Match` compris : c'est la vérification à faire avant de
>   se convaincre qu'une règle s'applique.

**Étape 2 — La clé de root@lab-web**

```bash
# lab-web
sudo ssh-keygen -t ed25519 -N '' -C 'root@lab-web restic' -f /root/.ssh/id_restic
sudo tee -a /root/.ssh/config >/dev/null <<'EOF'
Host lab-ops.lab.local
    IdentityFile /root/.ssh/id_restic
    IdentitiesOnly yes
EOF
sudo ssh-keyscan lab-ops.lab.local | sudo tee -a /root/.ssh/known_hosts
# vérifier l'empreinte obtenue contre celle de lab-ops (ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub)
# lab-ops : autoriser la clé
cat id_restic.pub | sudo tee -a /home/restic/.ssh/authorized_keys
sudo chown restic: /home/restic/.ssh/authorized_keys && sudo chmod 600 /home/restic/.ssh/authorized_keys
# lab-web : un shell est refusé, SFTP fonctionne
sudo ssh restic@lab-ops.lab.local            # This service allows sftp connections only.
echo 'ls /' | sudo sftp -b - restic@lab-ops.lab.local   # lab-web
```

**Étape 3 — Phrase, environnement, exclusions, dépôt**

```bash
sudo install -d -m 700 /etc/restic
sudo sh -c 'umask 077; head -c 32 /dev/urandom | base64 > /etc/restic/mot-de-passe'
sudo tee /etc/restic/lab-web.env >/dev/null <<'EOF'
RESTIC_REPOSITORY=sftp:restic@lab-ops.lab.local:/lab-web
RESTIC_PASSWORD_FILE=/etc/restic/mot-de-passe
RESTIC_CACHE_DIR=/var/cache/restic
EOF
sudo tee /etc/restic/exclusions >/dev/null <<'EOF'
# caches et fichiers temporaires
/var/www/**/cache
*.tmp
*.swp
EOF
sudo -i bash -c 'set -a; . /etc/restic/lab-web.env; set +a; restic init'
```

Le chemin du dépôt est `/lab-web` et non `/srv/restic/lab-web` : dans la
prison, `/srv/restic` **est** la racine.

**Étape 4 — Unité et timer**

```ini
# /etc/systemd/system/restic-sauvegarde.service
[Unit]
Description=Sauvegarde restic de lab-web vers lab-ops
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/restic/lab-web.env
ExecStart=/usr/bin/restic backup /etc /var/www --exclude-file=/etc/restic/exclusions --tag quotidien
ExecStart=/usr/bin/restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
ExecStart=/usr/bin/restic check
Nice=10
IOSchedulingClass=idle
```

```ini
# /etc/systemd/system/restic-sauvegarde.timer
[Unit]
Description=Sauvegarde restic quotidienne

[Timer]
OnCalendar=*-*-* 01:15
RandomizedDelaySec=20min
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now restic-sauvegarde.timer
sudo systemctl start restic-sauvegarde.service
journalctl -u restic-sauvegarde.service -n 15 --no-pager
```

> [!NOTE]
> **Pourquoi**
>
> Plusieurs `ExecStart=` dans une unité `oneshot` s'exécutent **dans l'ordre**,
> et le premier qui échoue arrête la suite : pas de rétention si la sauvegarde
> a échoué, ce qui évite d'effacer d'anciennes copies au moment où la nouvelle
> manque. `Nice` et `IOSchedulingClass=idle` laissent la priorité au service
> web. `Persistent=true` rattrape une exécution manquée (machine éteinte à
> 1 h 15).

**Étape 5 — Restaurer et comparer**

```bash
sudo -i bash -c 'set -a; . /etc/restic/lab-web.env; set +a;
  restic restore latest --target /tmp/restau --include /etc/nginx'
sudo diff -r /etc/nginx /tmp/restau/etc/nginx && echo IDENTIQUE
sudo rm -rf /tmp/restau
```

**Étape 6 — La phrase hors de `lab-web`**

`~/lab30/cles.md` (sur `lab-adm`) dit **où** sont les secrets, pas ce qu'ils
sont :

```markdown
| Secret | Exemplaire 1 | Exemplaire 2 |
|---|---|---|
| phrase restic lab-web | coffre-fort d'équipe, entrée « restic/lab-web » | enveloppe scellée, coffre physique, armoire B |
| clé + phrase borg lab-db | coffre-fort d'équipe, entrée « borg/lab-db » | impression `--paper`, même enveloppe |
```

> [!WARNING]
> **Piège**
>
> Le réflexe dangereux est de « mettre la phrase dans le dépôt Git de la
> configuration » ou dans la variable d'environnement d'un outil de CI : elle
> y est lisible par tous ceux qui lisent le dépôt et survit dans l'historique.
> Le second piège est de ne garder que la copie de `lab-web` : Q30.12.

---

### <a id="l30-2"></a>**[L30.2](README.md#l30-2)** — Une sauvegarde que lab-db ne peut pas effacer

**Étape 1 — Le dump quotidien (lab-db)**

```bash
sudo install -d -o postgres -g postgres -m 750 /var/backups/pg
sudo tee /etc/systemd/system/pg-dump-lab30.service >/dev/null <<'EOF'
[Unit]
Description=pg_dump quotidien de lab30

[Service]
Type=oneshot
User=postgres
ExecStart=/bin/sh -c 'pg_dump -Fc -d lab30 -f /var/backups/pg/lab30-$(date +%%Y%%m%%d).dump'
ExecStart=/usr/bin/find /var/backups/pg -name 'lab30-*.dump' -mtime +3 -delete
EOF
sudo tee /etc/systemd/system/pg-dump-lab30.timer >/dev/null <<'EOF'
[Timer]
OnCalendar=*-*-* 00:45
Persistent=true
[Install]
WantedBy=timers.target
EOF
sudo systemctl daemon-reload && sudo systemctl enable --now pg-dump-lab30.timer
sudo systemctl start pg-dump-lab30.service && ls -l /var/backups/pg
```

Dans une unité systemd, `%` introduit un spécificateur : `%%` produit un `%`
littéral pour `date`.

**Étape 2 — La clé restreinte (lab-ops)**

```bash
# lab-db
sudo ssh-keygen -t ed25519 -N '' -C 'root@lab-db borg' -f /root/.ssh/id_borg
# lab-ops
sudo install -d -o borg -g borg -m 700 /srv/borg/lab-db /home/borg/.ssh
echo "command=\"borg serve --append-only --restrict-to-path /srv/borg/lab-db\",restrict $(cat id_borg.pub)" |
  sudo tee /home/borg/.ssh/authorized_keys
sudo chown borg: /home/borg/.ssh/authorized_keys; sudo chmod 600 /home/borg/.ssh/authorized_keys
```

> [!NOTE]
> **Pourquoi**
>
> * `command="…"` : quoi que demande le client, `sshd` exécute **cette**
>   commande. Le client ne peut lancer que `borg serve`, avec les options
>   choisies par le serveur.
> * `--append-only` est posé **côté serveur** : le client ne peut pas le
>   retirer, même en le demandant.
> * `--restrict-to-path` limite le client à son dépôt : une clé volée ne donne
>   pas accès aux dépôts des autres machines.
> * `restrict` désactive en bloc redirections de ports, d'agent, X11 et
>   terminal, et toute fonctionnalité future d'OpenSSH qui serait ajoutée.

**Étape 3 — Dépôt, phrase, clé exportée (lab-db)**

```bash
sudo install -d -m 700 /root/.config/borg /etc/borg
sudo sh -c 'umask 077; head -c 32 /dev/urandom | base64 > /root/.config/borg/phrase'
sudo tee /etc/borg/lab-db.env >/dev/null <<'EOF'
BORG_REPO=ssh://borg@lab-ops.lab.local/srv/borg/lab-db
BORG_PASSCOMMAND="cat /root/.config/borg/phrase"
BORG_RSH="ssh -i /root/.ssh/id_borg -o BatchMode=yes"
EOF
sudo -i bash -c 'set -a; . /etc/borg/lab-db.env; set +a;
  borg init --encryption=repokey-blake2;
  borg key export --paper :: /root/borg-cle-lab-db.papier'
# copier /root/borg-cle-lab-db.papier et la phrase vers lab-adm (puis coffre), puis :
sudo shred -u /root/borg-cle-lab-db.papier
```

Les guillemets du fichier d'environnement sont indispensables : il est lu à
la fois par systemd (`EnvironmentFile=`, qui les retire) et par bash
(`set -a; . fichier`). Sans eux, bash comprend
`BORG_PASSCOMMAND=cat /root/.config/borg/phrase` comme « lancer
`/root/.config/borg/phrase` avec la variable `BORG_PASSCOMMAND=cat` » :
*Permission denied*, puis `borg` qui demande la phrase.

**Étape 4 — Unité et timer**

```ini
# /etc/systemd/system/borg-sauvegarde.service
[Unit]
Description=Sauvegarde borg de lab-db vers lab-ops (ajout seul)
Wants=network-online.target
After=network-online.target pg-dump-lab30.service

[Service]
Type=oneshot
EnvironmentFile=/etc/borg/lab-db.env
ExecStart=/usr/bin/borg create --stats --compression zstd,6 \
    ::{hostname}-{now:%%Y-%%m-%%dT%%H:%%M} /etc /var/backups/pg
ExecStart=/usr/bin/borg prune --list --keep-daily 7 --keep-weekly 4 --keep-monthly 6
Nice=10
```

Le timer est celui de L30.1, à 1 h 30. Premier passage :
`sudo systemctl start borg-sauvegarde.service`.

**Étape 5 — L'attaque**

```bash
# lab-ops : place occupée avant
sudo du -s /srv/borg/lab-db; sudo tail -3 /srv/borg/lab-db/transactions
# lab-db, en attaquant
sudo -i bash -c 'set -a; . /etc/borg/lab-db.env; set +a;
  for a in $(borg list --short); do borg delete ::"$a"; done; borg list'   # plus rien
sudo -i bash -c 'set -a; . /etc/borg/lab-db.env; set +a; borg compact'
#   (aucun message, code 0)                               # l'attaquant croit avoir tout effacé
# lab-ops : place occupée après
sudo du -s /srv/borg/lab-db                               # pas moins qu'avant
sudo tail -3 /srv/borg/lab-db/transactions                # les transactions de l'attaque
```

En ajout seul, `borg compact` ne signale rien et n'efface rien : le serveur
enregistre une transaction de plus, sans supprimer un seul segment. Les
suppressions d'archives ne font qu'ajouter des enregistrements « supprimé »
au journal ; les données sont toujours là.

**Étape 6 — Le retour arrière (administrateur de lab-ops)**

```bash
cd /srv/borg/lab-db
sudo cat transactions
#   transaction 5, UTC time 2026-11-09T00:30:12.441022   <- sauvegarde de la nuit
#   transaction 9, UTC time 2026-11-09T09:12:40.018237   <- sauvegarde manuelle de 9 h 12
#   transaction 13, UTC time 2026-11-09T10:41:03.552910  <- suppressions de l'attaque
#   transaction 17, UTC time 2026-11-09T10:41:04.371620
#   transaction 20, UTC time 2026-11-09T10:41:05.103377  <- son « borg compact »
```

On repère la dernière transaction **légitime** (ici 9, la sauvegarde de
9 h 12), puis, en tant que `borg` et sans client connecté :

```bash
sudo -u borg bash -c '
  cd /srv/borg/lab-db
  ls data/0/                                    # segments numérotés
  for f in data/*/*; do n=$(basename "$f"); [ "$n" -gt 9 ] && rm -v "$f"; done
  rm -fv hints.* index.* integrity.*            # seront reconstruits
  borg check --repository-only /srv/borg/lab-db'
```

Côté `lab-db`, le client a mémorisé un état du dépôt **plus récent** que
celui qu'on vient de restaurer et refuse de continuer, ce qui est une
protection contre le rejeu d'un vieux dépôt par un attaquant. Une fois la
manœuvre faite en connaissance de cause :

```bash
# lab-db : le refus
sudo -i bash -c 'set -a; . /etc/borg/lab-db.env; set +a; borg list'
#   Cache, or information obtained from the security directory is newer than repository -
#   this is either an attack or unsafe (multiple repos with same ID)
# lab-ops : l'identifiant du dépôt (borg config ne fonctionne qu'en local)
sudo -u borg borg config /srv/borg/lab-db id
#   d6ad3639df07a1651dde691c324da22d17a5d94e1d27f6bfe9794a24465409a3
# lab-db : oublier l'état mémorisé de CE dépôt, et seulement de lui
id=d6ad3639df07a1651dde691c324da22d17a5d94e1d27f6bfe9794a24465409a3
sudo cat /root/.config/borg/security/$id/location     # ssh://borg@lab-ops.lab.local/srv/borg/lab-db
sudo rm -rf /root/.cache/borg/$id /root/.config/borg/security/$id
sudo -i bash -c 'set -a; . /etc/borg/lab-db.env; set +a; borg list; borg check'   # les archives sont revenues
```

> [!NOTE]
> **Pourquoi**
>
> Un segment borg est un journal en ajout seul : chaque transaction écrit de
> nouveaux segments et un point de validation. Revenir à la transaction N
> revient à oublier tout ce qui a été écrit après : les segments de numéro
> supérieur à N, et les fichiers d'index (`index.M`, `hints.M`,
> `integrity.M`) qui décrivent l'état M > N et que `borg` reconstruit en
> relisant les segments. Le fichier `transactions` est la pièce maîtresse :
> il n'existe qu'en mode ajout seul, et c'est l'administrateur du **serveur**,
> pas le client compromis, qui décide jusqu'où revenir.
>
> Il faut vérifier, avant de supprimer quoi que ce soit, que la transaction
> choisie est bien antérieure à toute action de l'attaquant : une archive
> « sauvegardée » après la compromission peut contenir des données déjà
> altérées.

> [!WARNING]
> **Piège**
>
> Le mode ajout seul ne vaut que si la clé de la machine sauvegardée est la
> **seule** à pouvoir écrire, et si personne ne compacte le dépôt
> automatiquement : un `borg compact` lancé chaque nuit depuis le serveur, sans
> vérification, efface définitivement les données « supprimées » la veille par
> l'attaquant. On compacte rarement, à la main, après avoir vérifié le fichier
> `transactions`.

---

### <a id="l30-3"></a>**[L30.3](README.md#l30-3)** — Revenir à la seconde qui précède l'erreur

**Étape 1 — La clé de `postgres` en écriture seule**

```bash
# lab-db
sudo -u postgres ssh-keygen -t ed25519 -N '' -C 'postgres@lab-db archive' \
  -f /var/lib/postgresql/.ssh/id_archive
sudo -u postgres sh -c 'ssh-keyscan lab-ops.lab.local >> ~/.ssh/known_hosts'
# lab-ops
echo "command=\"/usr/bin/rrsync -wo /srv/pgwal\",restrict $(cat id_archive.pub)" |
  sudo tee /home/pgwal/.ssh/authorized_keys
sudo chown pgwal: /home/pgwal/.ssh/authorized_keys; sudo chmod 600 /home/pgwal/.ssh/authorized_keys
```

`rrsync -wo` (fourni avec rsync) n'accepte qu'un rsync **en écriture**,
confiné à `/srv/pgwal` : la clé ne permet ni de lire, ni de lister, ni
d'exécuter quoi que ce soit.

**Étape 2 — La commande d'archivage**

```bash
sudo tee /usr/local/bin/archive-wal >/dev/null <<'EOF'
#!/bin/bash
# archive-wal %p %f — archive un segment WAL sur lab-ops (module 30, L30.3)
# Appelé par PostgreSQL (utilisateur postgres). Code 0 = segment en sécurité.
set -euo pipefail
trap 'exit 1' ERR   # tout échec = code 1 (au-delà de 125, PostgreSQL relance l'archiveur)
src=$1 nom=$2
tmp=/var/lib/postgresql/archive-tmp
mkdir -p "$tmp"
zstd -q -f -3 "$src" -o "$tmp/$nom.zst"
rsync -a --ignore-existing --chmod=F640 \
  -e 'ssh -i /var/lib/postgresql/.ssh/id_archive -o BatchMode=yes -o ConnectTimeout=10' \
  "$tmp/$nom.zst" pgwal@lab-ops.lab.local:
rm -f "$tmp/$nom.zst"
EOF
sudo chmod 755 /usr/local/bin/archive-wal
sudo tee /etc/postgresql/16/main/conf.d/30-archivage.conf >/dev/null <<'EOF'
archive_mode = on
archive_command = '/usr/local/bin/archive-wal %p %f'
archive_timeout = 300
log_statement = 'ddl'
EOF
sudo systemctl restart postgresql@16-main
sudo -u postgres psql -Atc "SELECT pg_switch_wal();"
sleep 5; sudo -u postgres psql -x -c "SELECT * FROM pg_stat_archiver;"
```

> [!NOTE]
> **Pourquoi**
>
> * `set -euo pipefail` : chaque étape qui échoue fait sortir le script avec
>   un code non nul, et PostgreSQL garde le segment pour réessayer.
> * `trap 'exit 1' ERR` ramène tout échec au code 1. Sans lui, un échec SSH
>   de `rsync` sort avec le code 255 : au-delà de 125, PostgreSQL considère que
>   la commande a été tuée, journalise un `FATAL` et relance tout le processus
>   d'archivage. Le segment est gardé quand même, mais le journal devient
>   trompeur.
> * `--ignore-existing` : on n'écrase jamais un segment déjà archivé. La
>   documentation de PostgreSQL recommande même d'échouer si le fichier existe
>   avec un contenu différent ; avec une clé en écriture seule, on ne peut pas
>   relire l'existant pour comparer, d'où ce compromis.
> * `--chmod=F640` : les segments sont créés lisibles par le groupe `pgwal`, où
>   l'on mettra `postgres` sur `lab-ops` pour la restauration.
> * `log_statement = 'ddl'` journalise chaque `CREATE`, `ALTER`, `DROP` : c'est
>   ce qui permet de dater un accident comme celui de l'étape 4.
> * `archive_mode` exige un redémarrage ; `archive_command` et
>   `archive_timeout` se rechargent.

**Étape 3 — La sauvegarde de base, tirée par `lab-ops`**

```bash
# lab-db
sudo -u postgres psql -c "CREATE ROLE sauvegarde_pg WITH LOGIN REPLICATION PASSWORD '…';"
echo 'host replication sauvegarde_pg 10.10.10.14/32 scram-sha-256' |
  sudo tee -a /etc/postgresql/16/main/pg_hba.conf
sudo -u postgres psql -Atc "SHOW listen_addresses;"    # doit inclure 10.10.10.12 ou '*'
sudo systemctl reload postgresql@16-main
sudo ufw allow from 10.10.10.14 to any port 5432 proto tcp    # si ufw est actif (module 18)
# lab-ops
sudo apt install -y postgresql-16 zstd
sudo pg_dropcluster --stop 16 main          # instance par défaut inutile ici
sudo usermod -aG pgwal postgres
sudo install -d -o postgres -g postgres -m 700 /srv/pgbase
sudo -u postgres sh -c 'umask 077; echo "lab-db.lab.local:5432:replication:sauvegarde_pg:…" > ~/.pgpass'
sudo -u postgres pg_basebackup -h lab-db.lab.local -U sauvegarde_pg \
  -D /srv/pgbase/"$(date +%Y%m%d-%H%M)" -Ft -z -Xs -c fast -P
ls -l /srv/pgbase/*/
#   backup_manifest  base.tar.gz  pg_wal.tar.gz
```

**Étape 4 — L'accident**

```bash
date +'%F %T'                                   # 2026-11-09 10:42:05
sudo -u postgres psql -d lab30 -c 'DROP TABLE factures;'
```

**Étape 5 — Dater précisément l'accident**

```bash
# lab-db : le journal (log_statement = 'ddl')
sudo grep 'DROP TABLE factures' /var/log/postgresql/postgresql-16-main.log
#   2026-11-09 10:42:17.481 CET [24113] postgres@lab30 LOG:  statement: DROP TABLE factures;
sudo -u postgres psql -Atc "SELECT pg_switch_wal();"    # pousser le segment de l'accident
# lab-ops : la transaction dans les WAL archivés (postgres est dans le groupe pgwal)
sudo -u postgres bash -c 'mkdir -p /tmp/wal && cd /srv/pgwal &&
  for f in *.zst; do zstd -q -d -f "$f" -o /tmp/wal/"${f%.zst}"; done'
segs=$(sudo -u postgres ls /tmp/wal | grep -E '^[0-9A-F]{24}$')
sudo -u postgres /usr/lib/postgresql/16/bin/pg_waldump -p /tmp/wal \
  "$(head -1 <<<"$segs")" "$(tail -1 <<<"$segs")" 2>/dev/null | grep 'COMMIT.*rels:'
#   rmgr: Transaction len (rec/tot): 405/405, tx: 1071, lsn: 0/24015F30, prev 0/24015EF0,
#   desc: COMMIT 2026-11-09 10:42:17.502314 CET; rels: base/16388/16391 base/16388/16394 …
```

La validation (*COMMIT*) qui **supprime des fichiers de relations**
(`rels:`) est celle du `DROP TABLE` : transaction 1071, LSN `0/24015F30`.

`pg_waldump` reçoit le premier **et** le dernier segment : avec un seul
segment, il s'arrête à la fin de celui-ci. Les fichiers `.backup` et
`.history` de l'archive ne sont pas des segments, d'où le filtre sur les
24 caractères hexadécimaux.

**Étape 6 — Restaurer sur `lab-ops`**

```bash
sudo pg_createcluster 16 restau -p 5439
D=/var/lib/postgresql/16/restau
B=/srv/pgbase/$(ls -1 /srv/pgbase | tail -1)
sudo -u postgres bash -c "
  rm -rf $D/* &&
  tar -xzf $B/base.tar.gz -C $D &&
  tar -xzf $B/pg_wal.tar.gz -C $D/pg_wal &&
  touch $D/recovery.signal"
sudo -u postgres tee /etc/postgresql/16/restau/conf.d/restauration.conf >/dev/null <<'EOF'
restore_command = 'zstd -q -d -c /srv/pgwal/%f.zst > %p'
recovery_target_xid = '1071'
recovery_target_inclusive = off
recovery_target_action = 'promote'
archive_mode = off
EOF
sudo systemctl start postgresql@16-restau
sudo tail -5 /var/log/postgresql/postgresql-16-restau.log
#   LOG:  recovery stopping before commit of transaction 1071, time 2026-11-09 10:42:17.502314+01
#   LOG:  selected new timeline ID: 2
#   LOG:  database system is ready to accept connections
sudo -u postgres psql -p 5439 -d lab30 -Atc "SELECT pg_is_in_recovery(), count(*) FROM factures;"
#   f|1000
```

Dans le journal, des lignes `zstd: can't stat /srv/pgwal/00000002.history.zst`
sont normales : avant de choisir une nouvelle ligne temporelle, PostgreSQL
demande à `restore_command` des fichiers d'historique qui n'existent pas, et
un échec de la commande signifie simplement « pas dans l'archive ».

> [!NOTE]
> **Pourquoi**
>
> * `recovery_target_xid` + `recovery_target_inclusive = off` : arrêter le
>   rejeu **juste avant** la validation de la transaction 1071. Avec une
>   heure (`recovery_target_time = '2026-11-09 10:42:17'`), on obtient
>   presque le même résultat, mais une heure prise dans un journal est
>   arrondie, et une autre transaction validée dans la même seconde pourrait
>   tomber du mauvais côté. Un identifiant de transaction ou un LSN est exact.
> * `archive_mode = off` sur l'instance restaurée : sinon, après sa promotion,
>   elle archiverait ses propres WAL (timeline 2) et son fichier
>   `00000002.history` dans l'archive de la production, ce qui peut tromper une
>   future restauration. Une instance de restauration ne doit jamais écrire
>   dans l'archive dont elle vient.
> * La restauration se fait sur `lab-ops` : la production continue de tourner
>   (les autres données de la journée y sont toujours) et l'on ne prend aucun
>   risque de l'abîmer davantage.

**Étape 7 — RPO et RTO**

```bash
sudo -u postgres psql -p 5439 -d lab30 -Atc "SELECT max(t) FROM pra.temoin;"
#   2026-11-09 10:42:00.112+01    -> 17 s avant l'accident : RPO de l'incident
```

Le RTO se mesure de la décision de restaurer à l'instance utilisable
(`ready to accept connections` + la vérification) : quelques minutes ici,
dominées par l'extraction et le rejeu. Sur une base de 500 Go, ce serait
plusieurs heures : c'est ce chiffre qui justifie, ou non, un secondaire
retardé (`recovery_min_apply_delay`) prêt à servir.

**Étape 8 — Réinjecter la table en production**

```bash
# lab-ops -> lab-db, sans écraser ce qui existe
sudo -u postgres pg_dump -p 5439 -d lab30 -t factures -Fc -f /tmp/factures.dump
scp /tmp/factures.dump lab-db.lab.local:/tmp/
# lab-db
sudo -u postgres pg_restore -d lab30 /tmp/factures.dump
sudo -u postgres psql -d lab30 -Atc "SELECT count(*) FROM factures;"     # 1000
```

La table n'existe plus en production : la restaurer ne remplace rien. Si
l'accident avait été un `DELETE` partiel, on aurait restauré la table sous un
autre nom (`factures_restau`) et réinséré les seules lignes manquantes en
SQL, après accord du métier.

---

### <a id="l30-4"></a>**[L30.4](README.md#l30-4)** — Restaurer une VM entière, à l'écart de la production

**Étape 1 — Le pont isolé**

```bash
cat >> /etc/network/interfaces <<'EOF'

auto vmbr9
iface vmbr9 inet manual
        bridge-ports none
        bridge-stp off
        bridge-fd 0
#réseau isolé des exercices de reprise (module 30)
EOF
ifreload -a
ip -br link show vmbr9
```

Pas d'adresse sur le nœud, pas de port physique, pas de NAT : une VM
branchée ici ne peut parler qu'aux autres VM de `vmbr9`.

**Étape 2 — La sauvegarde**

```bash
vzdump 9002 --storage local --mode snapshot --compress zstd \
  --notes-template '{{guestname}} — avant exercice PRA'
grep -E 'fs-freeze|fs-thaw' /var/lib/vz/dump/vzdump-qemu-9002-*.log | tail -2
#   INFO: issuing guest-agent 'fs-freeze' command
#   INFO: issuing guest-agent 'fs-thaw' command
```

Si ces lignes manquent, l'agent invité n'est pas activé dans la configuration
de la VM (`qm set 9002 --agent enabled=1`) ou ne tourne pas dans l'invité.

**Étape 3 — Rétention**

```bash
pvesh create /cluster/backup --vmid 9002 --schedule 'sun 02:00' \
  --storage local --mode snapshot --compress zstd \
  --prune-backups keep-last=3,keep-weekly=1 --enabled 1 \
  --notes-template '{{guestname}} — hebdomadaire'
pvesh get /cluster/backup --output-format json-pretty
pvesm prune-backups local --vmid 9002 --keep-last 3 --keep-weekly 1 --dry-run 1
```

La rétention de la tâche planifiée ne s'applique qu'à ses propres passages ;
`pvesm prune-backups` permet de l'appliquer ou de la simuler à la main.

**Étape 4 — Restauration chronométrée**

```bash
F=$(ls -1t /var/lib/vz/dump/vzdump-qemu-9002-*.vma.zst | head -1)
time qmrestore "$F" 9102 --unique 1 --storage local-lvm
qm set 9102 --name lab-web-pra --onboot 0 --net0 virtio,bridge=vmbr9
qm config 9002 | grep net0; qm config 9102 | grep net0    # MAC différentes
```

**Étape 5 — Vérifier sans réseau**

```bash
qm start 9102
sleep 40
qm guest exec 9102 -- systemctl is-active nginx
#   { "exitcode" : 0, "out-data" : "active\n", … }
qm guest exec 9102 -- sha256sum /etc/nginx/nginx.conf
ssh lab-web sha256sum /etc/nginx/nginx.conf               # même empreinte
```

> [!NOTE]
> **Pourquoi**
>
> L'agent invité passe par un canal série virtio entre QEMU et la VM, pas par
> le réseau : on vérifie une machine isolée sans lui donner aucune
> connectivité. C'est le bon outil pour un exercice de PRA : la copie ne peut
> ni répondre à la place de la production, ni envoyer de mails, ni consommer
> une file de messages, ni écrire dans la vraie base.

**Étape 6 — Le RTO**

```markdown
# RTO mesuré — restauration de lab-web (2026-11-09)
| Étape | Durée |
|---|---|
| repérer la bonne sauvegarde | 1 min |
| qmrestore (20 Go, zstd, local-lvm) | 2 min 40 s |
| démarrage jusqu'à nginx actif | 45 s |
| vérifications (nginx, configuration, contenu) | 3 min |
| **total (hors bascule du trafic)** | **≈ 7 min 30 s** |
Non compté : bascule réseau (vmbr9 -> vmbr1, IP), DNS, mise à jour de la
journée perdue (RPO = âge de la sauvegarde).
```

---

## 30.7 Break & Fix

### <a id="bf30-1"></a>**[BF30.1](README.md#bf30-1)** — « La sauvegarde est verte, et /etc/nginx n'y est pas »

**Démarche de diagnostic**

```bash
sudo -i
set -a; . /etc/restic/lab-web.env; set +a
restic snapshots --compact
restic ls latest /etc/nginx                    # seulement l'en-tête « snapshot … filtered by [/etc/nginx] »
for s in $(restic snapshots --json | jq -r '.[].short_id'); do
  printf '%s ' "$s"; restic ls "$s" /etc/nginx/nginx.conf 2>/dev/null | grep -cxF /etc/nginx/nginx.conf
done                                           # 1 1 1 … 0 : depuis quand ça manque
restic diff <dernier-bon> <premier-mauvais> | grep nginx | head -3
#   -    /etc/nginx/
#   -    /etc/nginx/nginx.conf
systemctl cat restic-sauvegarde.service | grep exclude-file
cat /etc/restic/exclusions
#   # journaux volumineux (demande OPS-2207)
#   nginx
ls -l --time-style=full-iso /etc/restic/exclusions     # modifié quand ?
```

**Cause racine** : une ligne `nginx` ajoutée au fichier d'exclusions, avec
l'intention d'exclure les journaux de nginx. Un motif sans `/` s'applique
au **nom** de chaque élément, à n'importe quelle profondeur : il exclut aussi
`/etc/nginx`, `/var/www/…/nginx`, tout ce qui s'appelle `nginx`. La sauvegarde
réussit (elle a fait ce qu'on lui a demandé), `restic check` aussi (le dépôt
est sain) : aucun contrôle ne regardait le **contenu**.

**Correctif**

```bash
sed -i 's|^nginx$|/var/log/nginx|' /etc/restic/exclusions   # l'intention réelle (hors périmètre d'ailleurs)
restic restore <dernier-bon> --target /tmp/restau --include /etc/nginx   # l'état d'hier demandé
systemctl start restic-sauvegarde.service
restic ls latest /etc/nginx/nginx.conf
```

**Prévention** : un contrôle de **contenu** après chaque sauvegarde, lancé
par l'unité elle-même :

```bash
sudo tee /usr/local/sbin/restic-verifie >/dev/null <<'EOF'
#!/bin/bash
# restic-verifie — échoue si un fichier témoin manque dans le dernier instantané (module 30, BF30.1)
# Lancé par restic-sauvegarde.service (ExecStartPost), avec l'environnement du dépôt.
set -uo pipefail
manque=0
for f in /etc/nginx/nginx.conf /etc/ssh/sshd_config /var/www/lab30/index.html; do
  # restic ls écrit d'abord une ligne d'en-tête : on cherche la ligne EXACTE du fichier
  restic ls latest "$f" 2>/dev/null | grep -qxF "$f" || { echo "ABSENT DE LA SAUVEGARDE : $f" >&2; manque=1; }
done
exit "$manque"
EOF
sudo chmod 755 /usr/local/sbin/restic-verifie
sudo systemctl edit restic-sauvegarde.service     # [Service] ExecStartPost=/usr/local/sbin/restic-verifie
```

> [!WARNING]
> **Piège**
>
> `restic ls latest "$f" | grep -q .` semble faire l'affaire, mais `restic ls`
> écrit toujours une ligne d'en-tête (`snapshot … filtered by […]`) sur sa
> sortie standard, même quand le fichier est absent : le contrôle serait
> toujours vert. Et une boucle shell écrite directement dans `ExecStartPost=`
> se heurte à la substitution de variables de systemd (`$f` devrait s'écrire
> `$$f`) : un script à part est plus simple à tester.

plus une alerte sur la variation de taille d'un instantané à l'autre
(`restic stats latest --json` comparé au précédent : −20 % = alerte), et le
fichier d'exclusions versionné et relu comme du code.

> [!NOTE]
> **Pourquoi**
>
> « Le travail est vert » prouve qu'un programme s'est terminé avec le code 0,
> rien de plus. Une sauvegarde se juge sur ce qu'elle **contient** : une liste
> de fichiers témoins dont l'absence fait échouer le travail, et la tendance
> de sa taille. Ce sont les deux contrôles qui auraient alerté le premier jour.
>
> La syntaxe des motifs d'exclusion est un piège commun à restic, borg, rsync
> et `.gitignore` : sans `/`, le motif vise un nom n'importe où ; avec un `/`
> en tête, un chemin depuis la racine. On teste un fichier d'exclusions avec
> `restic backup --dry-run -vv`, qui liste ce qui serait sauvegardé.

---

### <a id="bf30-2"></a>**[BF30.2](README.md#bf30-2)** — « Le disque de lab-db fond, et rien dans les journaux applicatifs »

**Démarche de diagnostic**

```bash
df -h /var/lib/postgresql
sudo du -sh /var/lib/postgresql/16/main/pg_wal          # plusieurs centaines de Mo, croissant
sudo ls /var/lib/postgresql/16/main/pg_wal/archive_status | grep -c '\.ready$'
sudo -u postgres psql -x -c "SELECT last_archived_wal, last_archived_time,
  failed_count, last_failed_wal, last_failed_time FROM pg_stat_archiver;"
#   last_archived_time | 2026-11-08 17:05:12      <- hier
#   failed_count       | 1214
sudo grep -B2 'archive command failed' /var/log/postgresql/postgresql-16-main.log | tail -4
#   Warning: Identity file /var/lib/postgresql/.ssh/id_archive not accessible: No such file or directory.
#   pgwal@lab-ops.lab.local: Permission denied (publickey).
#   LOG:  archive command failed with exit code 1
#   DETAIL:  The failed archive command was: /usr/local/bin/archive-wal pg_wal/0000000100000000000000A5 …
sudo ls -l /var/lib/postgresql/.ssh/ /var/lib/postgresql/.ssh/ancien/
```

**Cause racine** : la « rotation des clés » a déplacé la clé privée
d'archivage dans `~postgres/.ssh/ancien/` sans en installer de nouvelle ni
mettre à jour `archive-wal`. Chaque appel échoue ; PostgreSQL, comme prévu,
**garde** chaque segment non archivé (`.ready`) et réessaie. `pg_wal` grossit
de toute l'activité depuis hier.

**Correctif**

```bash
sudo -u postgres mv /var/lib/postgresql/.ssh/ancien/id_archive* /var/lib/postgresql/.ssh/
sudo -u postgres /usr/local/bin/archive-wal \
  /var/lib/postgresql/16/main/pg_wal/"$(sudo ls /var/lib/postgresql/16/main/pg_wal/archive_status |
  sed -n 's/\.ready$//p' | sort | head -1)" test-manuel && echo "commande OK"   # test à la main
# PostgreSQL rattrape seul, au rythme d'un segment par appel :
watch -n 5 "sudo -u postgres psql -Atc 'SELECT failed_count, last_archived_wal FROM pg_stat_archiver;';
  sudo ls /var/lib/postgresql/16/main/pg_wal/archive_status | grep -c ready"
sudo -u postgres psql -c 'CHECKPOINT;'        # les segments archivés deviennent recyclables
```

Après le point de contrôle, `pg_wal` cesse de grossir mais ne maigrit pas
forcément tout de suite : PostgreSQL renomme les segments recyclables pour
les réutiliser (dans la limite de `max_wal_size`) et ne supprime que
l'excédent, au fil des points de contrôle suivants.

Le test manuel écrit un fichier `test-manuel.zst` dans l'archive : on le
supprime ensuite sur `lab-ops`. Si la clé avait réellement fuité (raison
d'une rotation), on en génère une nouvelle, on l'autorise sur `lab-ops` et
on retire l'ancienne de `authorized_keys`.

**Ce qu'aurait coûté la suppression proposée** : les segments de `pg_wal`
non encore pris en compte par un point de contrôle sont nécessaires à la
**reprise après incident** de l'instance elle-même : les supprimer peut
l'empêcher de redémarrer (`could not locate a valid checkpoint record`).
Ceux qui ne sont pas archivés sont les **seules** copies de l'activité depuis
hier : l'archive aurait un trou définitif, et aucune restauration ne pourrait
dépasser 17 h 05 hier ; il faudrait une nouvelle sauvegarde de base pour
repartir. On ne touche jamais à `pg_wal` à la main.

**Prévention** : alerte sur `pg_stat_archiver` (`failed_count` qui augmente,
`now() - last_archived_time > 2 × archive_timeout`), alerte sur le nombre de
fichiers `.ready`, et une procédure de rotation de clés qui **teste** la
nouvelle clé (un `pg_switch_wal()` puis vérification) avant de retirer
l'ancienne.

> [!NOTE]
> **Pourquoi**
>
> Ce comportement de PostgreSQL est une **sécurité** : plutôt que de perdre
> des WAL, il remplit le disque. C'est aussi un danger : si `pg_wal` remplit
> le système de fichiers, PostgreSQL s'arrête en urgence (*PANIC: could not
> write to file*). D'où l'importance de surveiller l'archivage comme un
> service à part entière, et de donner à `pg_wal` assez de marge (ou son propre
> volume) pour tenir le temps d'une intervention.

---

### <a id="bf30-3"></a>**[BF30.3](README.md#bf30-3)** — « Depuis l'exercice de PRA, lab-web décroche »

**Démarche de diagnostic**

```bash
# lab-adm : la MAC de 10.10.10.11 ne change pas… parce que c'est la même
ip neigh show 10.10.10.11
# nœud Proxmox : qui d'autre a cette adresse ?
qm list | grep -v stopped
#   9103 lab-web-test   running  2048  20.00  …
MAC=$(qm config 9002 | sed -n 's/^net0: virtio=\([^,]*\),.*/\1/p')
grep -l "$MAC" /etc/pve/qemu-server/*.conf
#   /etc/pve/qemu-server/9002.conf
#   /etc/pve/qemu-server/9103.conf
bridge fdb show br vmbr1 | grep -i "$MAC"     # appris tantôt sur tap9002i0, tantôt sur tap9103i0
bridge monitor fdb | grep -i "$MAC"            # le va-et-vient en direct
qm config 9103 | grep -E 'net0|ipconfig0'     # même MAC, même pont, même IP
```

**Cause racine** : le collègue a restauré la sauvegarde de `lab-web` dans
la VM 9103 **sans** `--unique` et l'a démarrée sur `vmbr1`. Elle a la même
adresse MAC, la même IP (cloud-init) et les mêmes clés d'hôte SSH que la
production. Le pont associe la MAC au dernier port où il l'a vue : les trames
partent tantôt vers la production, tantôt vers la copie. Les connexions
établies sont coupées à chaque bascule ; `ssh-keyscan` ne voit rien, puisque
les deux machines ont la même clé. Le vrai `lab-web` ne voit rien d'anormal :
il reçoit simplement moins de paquets.

**Correctif**

```bash
qm stop 9103
qm set 9103 --net0 virtio,bridge=vmbr9 --name lab-web-test --onboot 0   # nouvelle MAC aléatoire
qm start 9103                                  # l'exercice continue, isolé
# lab-adm
sudo ip neigh flush 10.10.10.11
ssh lab-web uptime                             # stable
```

**Prévention** : la règle écrite dans le PRA, puis rendue technique :

* tout exercice de restauration se fait avec `--unique 1` **et** sur
  `vmbr9` ; la procédure le dit en première ligne ;
* une vérification automatique (tâche planifiée sur le nœud, ou script de
  crochet `hookscript` en phase `pre-start`) refuse de démarrer une VM dont
  une MAC est déjà utilisée par une autre VM :

```bash
#!/bin/bash
# /var/lib/vz/snippets/mac-unique.sh — hookscript Proxmox : refuse un doublon de MAC
vmid=$1 phase=$2
[ "$phase" = pre-start ] || exit 0
for mac in $(grep -oiE '([0-9a-f]{2}:){5}[0-9a-f]{2}' /etc/pve/qemu-server/"$vmid".conf); do
  autres=$(grep -li "$mac" /etc/pve/qemu-server/*.conf | grep -v "/$vmid.conf")
  [ -z "$autres" ] || { echo "MAC $mac déjà utilisée par : $autres" >&2; exit 1; }
done
```

(`qm set <vmid> --hookscript local:snippets/mac-unique.sh` pour chaque VM
concernée.)

> [!NOTE]
> **Pourquoi**
>
> Deux machines avec la même MAC sur un même pont ne produisent ni erreur ni
> journal : un commutateur, physique ou Linux, apprend simplement la dernière
> position vue. C'est pour cela que la panne est si trompeuse. Le cas réel le
> plus fréquent n'est pas un exercice raté mais une **vraie** reprise où la
> machine d'origine, qu'on croyait morte, revient (redémarrage tardif d'un
> hyperviseur) : la règle « la copie ne rejoint le réseau de production
> qu'après avoir vérifié que l'originale est éteinte » est la même que celle
> du fencing (module 29).

---

## 30.8 Défi du module

<a id="d30"></a>**[D30](README.md#d30) — Un exercice de reprise chronométré, et le PRA qui va avec**

*Livrable attendu : `exercice-pra.sh`, son rapport, `pra.md`, le timer.*

```bash
#!/usr/bin/env bash
# exercice-pra.sh — exercice de reprise automatique (module 30, D30)
# À lancer en root sur lab-ops. Ne touche à aucune donnée de production :
# tout est restauré dans des emplacements jetables, détruits à la fin.
# Sortie : 0 si tout est restauré, vérifié, et chaque RPO ≤ 10 min.
set -euo pipefail

DEFI=/root/lab30/defi; mkdir -p "$DEFI"
RAPPORT="$DEFI/rapport-$(date +%Y%m%d-%H%M).md"
RPO_MAX=600
DEBUT=$(date +%s); DEBUT_ISO=$(date -Is)
TMP=$(mktemp -d /var/tmp/pra.XXXXXX)
INSTANCE=exercice; PORT=5440
# secrets : fichiers root 0600, jamais dans le script
export RESTIC_PASSWORD_FILE=/root/.config/pra/restic-lab-web
PHRASE_BORG=/root/.config/pra/borg-lab-db
ECHEC=0

log()  { printf '%s %s\n' "$(date +%T)" "$*" >&2; }
ligne(){ printf '| %s | %s | %s | %s |\n' "$@" >> "$RAPPORT"; }
echoue(){ log "ÉCHEC : $*"; ECHEC=1; }
nettoyer() {
  pg_ctlcluster 16 "$INSTANCE" stop -m immediate 2>/dev/null || true
  pg_dropcluster 16 "$INSTANCE" 2>/dev/null || true
  rm -rf "$TMP"
}
trap nettoyer EXIT

{ echo "# Exercice de reprise — $DEBUT_ISO"; echo
  echo "| Étape | RTO | RPO | Vérification |"; echo "|---|---|---|---|"; } > "$RAPPORT"

# --- 1. PostgreSQL : dernière base + tous les WAL -----------------------------
t0=$(date +%s)
BASE=/srv/pgbase/$(ls -1 /srv/pgbase | tail -1)
pg_dropcluster --stop 16 "$INSTANCE" 2>/dev/null || true
pg_createcluster 16 "$INSTANCE" -p "$PORT" >/dev/null
D=/var/lib/postgresql/16/$INSTANCE
sudo -u postgres bash -c "rm -rf $D/* && tar -xzf $BASE/base.tar.gz -C $D &&
  tar -xzf $BASE/pg_wal.tar.gz -C $D/pg_wal && touch $D/recovery.signal"
cat > /etc/postgresql/16/$INSTANCE/conf.d/restauration.conf <<'EOF'
restore_command = 'zstd -q -d -c /srv/pgwal/%f.zst > %p'
recovery_target_action = 'promote'
archive_mode = off
EOF
pg_ctlcluster 16 "$INSTANCE" start
for _ in $(seq 120); do
  [ "$(sudo -u postgres psql -p "$PORT" -Atc 'SELECT pg_is_in_recovery()' 2>/dev/null)" = f ] && break
  sleep 2
done
q() { sudo -u postgres psql -p "$PORT" -d lab30 -Atc "$1" 2>/dev/null; }
n=$(q 'SELECT count(*) FROM factures' || echo 0)
age=$(q "SELECT round(extract(epoch FROM (timestamptz '$DEBUT_ISO' - max(t)))) FROM pra.temoin" || echo 999999)
rto=$(( $(date +%s) - t0 ))
verif="factures : $n lignes"; [ "$n" -ge 1000 ] || { echoue "factures = $n"; verif="$verif (KO)"; }
[ "$age" -le "$RPO_MAX" ] || echoue "RPO PostgreSQL $age s > $RPO_MAX s"
ligne "PostgreSQL (base $(basename "$BASE") + WAL)" "${rto} s" "${age} s" "$verif"

# --- 2. restic : /etc/nginx de lab-web -------------------------------------------
t0=$(date +%s)
R=(restic --no-lock -r /srv/restic/lab-web)     # lecture seule : aucun verrou écrit dans le dépôt
"${R[@]}" restore latest --target "$TMP/restic" --include /etc/nginx >/dev/null
snap=$("${R[@]}" snapshots --latest 1 --json | jq -r '.[-1].time')
age=$(( DEBUT - $(date -d "$snap" +%s) ))
rto=$(( $(date +%s) - t0 ))
if [ -s "$TMP/restic/etc/nginx/nginx.conf" ] && ls "$TMP/restic/etc/nginx/sites-enabled/"* >/dev/null 2>&1; then
  verif="nginx.conf + $(ls "$TMP/restic/etc/nginx/sites-enabled" | wc -l) site(s)"
else echoue "nginx incomplet dans l'instantané"; verif="nginx incomplet (KO)"; fi
ligne "restic lab-web (/etc/nginx)" "${rto} s" "${age} s" "$verif"

# --- 3. borg : dernier dump de lab-db ----------------------------------------------
t0=$(date +%s)
# borg tourne sous l'identité borg ; il lit une copie de la phrase qui lui appartient
install -m 600 -o borg "$PHRASE_BORG" "$TMP/phrase-borg"; chmod 711 "$TMP"
borg_() { sudo -u borg env BORG_PASSCOMMAND="cat $TMP/phrase-borg" borg "$@"; }
arch=$(borg_ list --last 1 --short /srv/borg/lab-db)
dump=$(borg_ list --short "/srv/borg/lab-db::$arch" | grep 'lab30-.*\.dump$' | sort | tail -1)
borg_ extract --stdout "/srv/borg/lab-db::$arch" "$dump" > "$TMP/lab30.dump"
quand=$(borg_ info --json "/srv/borg/lab-db::$arch" | jq -r '.archives[0].start')
age=$(( DEBUT - $(date -d "$quand" +%s) ))
rto=$(( $(date +%s) - t0 ))
if pg_restore --list "$TMP/lab30.dump" | grep -q 'TABLE DATA public factures'; then
  verif="dump lisible, données de factures présentes"
else echoue "dump borg illisible ou sans factures"; verif="dump KO"; fi
ligne "borg lab-db ($dump)" "${rto} s" "${age} s (quotidien)" "$verif"

# --- bilan -----------------------------------------------------------------------
total=$(( $(date +%s) - DEBUT ))
{ echo; echo "Durée totale : ${total} s. RPO maximal toléré pour PostgreSQL : ${RPO_MAX} s.";
  [ "$ECHEC" -eq 0 ] && echo "**Résultat : réussi.**" || echo "**Résultat : ÉCHEC** (voir le journal)."; } >> "$RAPPORT"
log "rapport : $RAPPORT"
exit "$ECHEC"
```

> [!NOTE]
> **Pourquoi**
>
> Les choix qui font de ce script un vrai exercice :
>
> * **Il part des mêmes éléments qu'une vraie reprise** : la dernière
>   sauvegarde de base, l'archive des WAL, les dépôts restic et borg, et des
>   secrets rangés pour l'équipe de reprise (`/root/.config/pra/`, `0600`),
>   pas ceux des machines de production.
> * **Vérifications métier** : un nombre de lignes, des sites activés, des
>   données présentes dans le dump. Un service qui démarre sur une base vide
>   est un échec.
> * **RPO mesuré** à partir du témoin (PostgreSQL) et des dates des
>   instantanés (restic, borg), et comparé à un seuil : la sortie non nulle
>   permet au timer de notifier.
> * **Rien ne survit à l'exercice** : instance jetable sur un autre port,
>   répertoire temporaire, `trap` de nettoyage même en cas d'échec.
> * **borg est lancé sous l'identité `borg`** : un `borg list` en root sur le
>   dépôt créerait des fichiers de verrou et de cache appartenant à root, que
>   le compte `borg` ne pourrait plus modifier à la sauvegarde suivante.
>
> Le timer hebdomadaire réutilise le modèle du module 17, avec
> `OnFailure=notifier@%n.service` pour qu'un exercice raté réveille quelqu'un.

Extrait de `pra.md` attendu :

```markdown
# PRA — plateforme lab (version 2026-11-09)

## Objectifs et mesures
| Composant | RPO visé | RPO mesuré | RTO visé | RTO mesuré | Méthode |
|---|---|---|---|---|---|
| PostgreSQL lab30 | 5 min | 17 s (D30) | 1 h | 3 min | base + WAL (lab-ops) |
| lab-web (VM) | 24 h | 24 h | 1 h | 7 min 30 | vzdump + restauration sur vmbr9 |
| /etc, /var/www | 24 h | 24 h | 30 min | 2 min | restic (lab-ops) |

## Ordre de reprise
1. réseau, DNS (dnsmasq du nœud)  2. PostgreSQL  3. Redis  4. API, worker
5. nginx  6. vérifications métier  7. bascule du trafic  8. communication

## Où sont les sauvegardes et les clés
… (renvoi à cles.md : coffre-fort d'équipe + coffre physique)

## Risques non couverts
* tout tourne sur **un seul** nœud Proxmox : sa perte détruit production ET
  sauvegardes (lab-ops) ; il faut une copie hors site (second PBS, S3 avec
  verrouillage d'objet) ;
* …

## Exercices
Automatique chaque lundi (exercice-pra.sh), complet chaque trimestre.
```

<!-- nav:début -->
---

[← Module 29](../29-haute-disponibilite/corrige.md) · [Énoncé](README.md) · [Module 31 →](../31-tracage-ebpf-perf/corrige.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
