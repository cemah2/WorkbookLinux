<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Partie V — Expertise système › **Module 32** · corrigé  
[← Module 31](../31-tracage-ebpf-perf/corrige.md) · [Énoncé](README.md) · [Projet C →](../../projets/P3-astreinte/corrige.md)

> [!TIP]
> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, pas avant. Chaque identifiant renvoie à son énoncé.
<!-- nav:fin -->

# Module 32 — Corrigé

## 32.3 Quiz — QCM

<a id="q32-1"></a>**[Q32.1](README.md#q32-1)** — *Écrire, synchroniser, renommer… et l'ancienne version revient.*

**Réponse : b)** `fsync()` sur le répertoire après `rename()`.

> [!NOTE]
> **Pourquoi**
>
> Le renommage modifie le **répertoire** (son entrée `config.json` pointe
> désormais sur un autre inode). Cette modification est une métadonnée du
> répertoire, qui vit dans le cache comme le reste : tant qu'elle n'est pas
> écrite, une coupure peut la faire disparaître, et l'on retrouve l'ancienne
> entrée. POSIX ne garantit la persistance d'une entrée de répertoire qu'après
> `fsync` du répertoire lui-même (on l'ouvre en lecture seule et on appelle
> `fsync` sur son descripteur).
>
> En pratique, ext4 en `data=ordered` rend souvent ce cas invisible (le
> renommage part avec la transaction suivante du journal, quelques secondes plus
> tard), ce qui explique que l'oubli traverse les tests ; XFS, Btrfs ou un
> disque réseau ne font pas la même chose. Le motif complet est celui de
> E32.3 et de L32.1.

---

<a id="q32-2"></a>**[Q32.2](README.md#q32-2)** — *Bloc corrompu relu sur ext4.*

**Réponse : c)** le contenu corrompu est rendu sans erreur.

> [!NOTE]
> **Pourquoi**
>
> ext4 calcule des sommes de contrôle sur ses **métadonnées** (`metadata_csum` :
> superbloc, descripteurs de groupes, inodes, répertoires, journal), pas sur les
> **données** des fichiers. Un bloc de données modifié par le disque, le
> contrôleur, un câble ou une erreur mémoire est relu tel quel. Le disque
> lui-même a des codes correcteurs, mais ils protègent contre les erreurs de
> lecture du support, pas contre une écriture au mauvais endroit ou une donnée
> déjà fausse en arrivant. `e2fsck` vérifie la cohérence de la structure, pas le
> contenu des fichiers. C'est exactement ce que L32.1 démontre.

---

<a id="q32-3"></a>**[Q32.3](README.md#q32-3)** — *Quand ZFS peut réparer un bloc.*

**Réponse : a)** quand une autre copie existe : miroir, RAID-Z ou `copies=2`.

> [!NOTE]
> **Pourquoi**
>
> Chaque bloc ZFS a une somme de contrôle stockée **dans le bloc parent**, pas à
> côté de lui : un bloc ne peut pas « valider » ses propres données fausses. À
> la lecture, ZFS vérifie ; si la somme ne correspond pas et qu'une autre copie
> existe, il la lit, la vérifie, la rend à l'application, et **réécrit** la copie
> fautive (autoréparation). Sans redondance, il ne peut que signaler une erreur
> d'E/S (et la lister dans `zpool status -v`) : c'est déjà mieux que de rendre
> des données fausses en silence, mais la donnée est perdue. `copies=2` sur un
> seul disque protège contre des secteurs défectueux, pas contre la perte du
> disque.

---

<a id="q32-4"></a>**[Q32.4](README.md#q32-4)** — *Fragmentation d'une base ou d'une image de VM sur Btrfs.*

**Réponse : d)** chaque réécriture en place est écrite ailleurs.

> [!NOTE]
> **Pourquoi**
>
> Une base de données réécrit sans cesse les mêmes pages au milieu d'un gros
> fichier. En copie sur écriture, chaque page réécrite part dans un nouvel
> emplacement : après quelques jours, un fichier de 10 Go est composé de
> centaines de milliers de fragments, et les lectures séquentielles deviennent
> aléatoires. Remèdes sur Btrfs : désactiver la copie sur écriture pour ce
> répertoire (`chattr +C` sur un répertoire **vide**, les nouveaux fichiers en
> héritent ; on perd alors les sommes de contrôle et la compression), ou
> défragmenter périodiquement (`btrfs filesystem defragment`, qui casse le
> partage avec les instantanés). ZFS limite le phénomène avec ses
> enregistrements de taille fixe et ses écritures groupées, mais un
> `recordsize` mal choisi aggrave l'amplification (Q32.10).

---

<a id="q32-5"></a>**[Q32.5](README.md#q32-5)** — *`df` et `ENOSPC` sur Btrfs.*

**Réponse : c)** `btrfs filesystem usage`.

> [!NOTE]
> **Pourquoi**
>
> Btrfs alloue l'espace par gros morceaux (*chunks*, typiquement 1 Gio de
> données ou 256 Mio de métadonnées), chacun avec un profil (RAID1, single…).
> `df` ne voit qu'une estimation globale. L'espace peut être « libre » dans des
> morceaux de **données** à moitié vides alors que les **métadonnées** sont
> pleines et qu'il ne reste plus d'espace **non alloué** pour en créer : toute
> écriture échoue. `btrfs filesystem usage` montre données, métadonnées,
> système et non alloué par disque ; la correction est un `btrfs balance
> start -dusage=50` qui regroupe les morceaux de données peu remplis et rend de
> l'espace non alloué.

---

<a id="q32-6"></a>**[Q32.6](README.md#q32-6)** — *`cp --reflink=always`.*

**Réponse : b)** une copie instantanée qui partage les blocs.

> [!NOTE]
> **Pourquoi**
>
> La copie ne fait que créer un nouvel inode dont les étendues pointent sur
> les **mêmes** blocs, avec un compteur de références. Une écriture dans l'une
> des copies alloue un nouveau bloc (copie sur écriture au niveau du fichier),
> l'autre n'est pas touchée. La copie d'un fichier de 20 Go prend quelques
> millisecondes et ne consomme presque rien au départ (E32.4). XFS le permet
> depuis la version 5 du format (`reflink=1`, défaut récent), Btrfs depuis
> toujours ; ext4 ne sait pas le faire. C'est ce qu'utilisent les outils de
> déduplication (`duperemove`) et les clones rapides de VM.

---

<a id="q32-7"></a>**[Q32.7](README.md#q32-7)** — *Pourquoi `/dev/disk/by-id/`.*

**Réponse : b)** l'ordre des `sdX` peut changer, l'identifiant suit le disque.

> [!NOTE]
> **Pourquoi**
>
> Les noms `sda`, `sdb`… sont attribués dans l'ordre de détection, qui dépend
> des contrôleurs, des pilotes et de leur vitesse d'initialisation : l'ajout d'un
> disque, une carte en plus ou une mise à jour du noyau suffit à les permuter.
> ZFS retrouve ses disques par leurs étiquettes au moment de l'import, mais
> `zpool status` affiche alors des noms trompeurs, et un remplacement fait sur
> le mauvais `sdX` est une erreur classique et grave. `by-id` (modèle +
> numéro de série, ou WWN) suit le disque physique : c'est aussi le nom qu'on
> lit sur l'étiquette au moment de le changer.

---

<a id="q32-8"></a>**[Q32.8](README.md#q32-8)** — *Supprimer 1 Go après un instantané.*

**Réponse : a)** l'espace ne change presque pas.

> [!NOTE]
> **Pourquoi**
>
> L'instantané garde la racine de l'arbre au moment où il a été pris : tous les
> blocs du fichier restent référencés, la suppression ne fait que retirer le
> fichier de l'état **actuel**. L'espace ne revient qu'à la destruction du
> **dernier** instantané qui référence ces blocs. `zfs list -o space` le montre
> dans la colonne `USEDSNAP`, et c'est la cause de BF32.1.

---

<a id="q32-9"></a>**[Q32.9](README.md#q32-9)** — *Envoi incrémental.*

**Réponse : d)** la destination possède `@hier`, inchangée depuis.

> [!NOTE]
> **Pourquoi**
>
> Un flux incrémental ne contient que les blocs qui diffèrent entre `@hier` et
> `@aujourdhui`. Il ne peut s'appliquer que sur une destination qui est
> exactement dans l'état `@hier`. Si la destination a été modifiée depuis
> (même un simple montage qui met à jour des métadonnées), `zfs receive` refuse
> (`destination has been modified`), sauf avec `-F` qui revient d'abord à
> `@hier` en perdant ces modifications. D'où `zfs receive -u` (sans monter) et
> `readonly=on` sur la destination, et la règle de ne détruire côté source le
> dernier instantané commun qu'une fois le suivant répliqué (D32).

---

<a id="q32-10"></a>**[Q32.10](README.md#q32-10)** — *`recordsize` pour PostgreSQL.*

**Réponse : c)** `recordsize=8K` ou `16K`.

> [!NOTE]
> **Pourquoi**
>
> PostgreSQL lit et écrit des pages de 8 Kio. Avec le `recordsize` par défaut
> (128 Kio), la modification d'une page oblige ZFS à lire tout l'enregistrement
> de 128 Kio, le modifier et le réécrire : une amplification d'écriture de 16,
> et des lectures inutiles. Avec 8 ou 16 Kio (16 Kio est souvent retenu : la
> compression y est plus efficace et l'amplification reste faible), chaque
> écriture de page touche un seul enregistrement. On combine avec
> `compression=lz4`, `atime=off`, `logbias=throughput` sur les données selon les
> cas. `ashift` est une propriété du **pool** (taille des secteurs), sans rapport
> avec la base ; la déduplication coûte énormément de mémoire et n'a presque
> jamais de sens pour une base.

---

<a id="q32-11"></a>**[Q32.11](README.md#q32-11)** — *Limiter l'ARC sur `lab-db`.*

**Réponse : a)** il peut prendre la moitié de la mémoire, au détriment de PostgreSQL.

> [!NOTE]
> **Pourquoi**
>
> L'ARC (*Adaptive Replacement Cache*) est le cache de lecture de ZFS. Il ne
> fait pas partie du cache de pages du noyau : la mémoire qu'il occupe apparaît
> comme « utilisée » et ne se libère que si ZFS réagit à la pression mémoire,
> parfois trop lentement pour éviter l'OOM killer ou l'écriture en swap. Par
> défaut sous Linux, il peut monter à la moitié de la RAM. Sur une machine qui
> fait tourner une base, qui a son propre cache (`shared_buffers`) et compte
> aussi sur le cache de pages, on le limite (`zfs_arc_max`) et on choisit qui
> cache quoi (par exemple `primarycache=metadata` sur le dataset de la base).

---

<a id="q32-12"></a>**[Q32.12](README.md#q32-12)** — *Btrfs en miroir, un disque perdu, montage impossible.*

**Réponse : d)** monter en `degraded`, puis `btrfs replace`.

> [!NOTE]
> **Pourquoi**
>
> Par sécurité, Btrfs refuse de monter un volume auquel il manque un disque :
> on pourrait sinon fonctionner des semaines sans redondance sans s'en rendre
> compte. `-o degraded` est l'accord explicite de l'administrateur. On remplace
> ensuite le disque absent (`btrfs replace start <devid> <nouveau>`), puis on
> convertit les morceaux écrits pendant la période dégradée, qui ont pu l'être
> en profil `single`, avec un `balance … -dconvert=raid1,soft
> -mconvert=raid1,soft`. `btrfs check --repair` est un dernier recours pour une
> structure corrompue, pas pour un disque absent : utilisé à tort, il peut
> détruire ce qui était récupérable.

---

<a id="q32-13"></a>**[Q32.13](README.md#q32-13)** — *Rendre à l'hyperviseur l'espace libéré dans l'invité.*

**Réponse : a) et b).**

> [!NOTE]
> **Pourquoi**
>
> La chaîne complète : le système de fichiers de l'invité sait quels blocs sont
> libres ; il doit le **dire** (commande TRIM/UNMAP) soit à chaque suppression
> (option de montage `discard`, coût à chaque opération), soit périodiquement
> (`fstrim`, et `fstrim.timer` hebdomadaire sur Ubuntu) ; le disque virtuel
> doit **transmettre** la commande à QEMU (`discard=on` dans Proxmox), et QEMU
> la traduit en libération de blocs dans le volume thin, le fichier qcow2 ou
> le dataset ZFS de l'hôte. Il suffit d'un maillon manquant pour que l'hôte
> garde tout. Un redémarrage n'y change rien. C'est BF32.3.

---

<a id="q32-14"></a>**[Q32.14](README.md#q32-14)** — *Le `scrub`.*

**Réponse : c)** relire tout, vérifier, réparer depuis une copie saine.

> [!NOTE]
> **Pourquoi**
>
> Les données rarement lues peuvent se corrompre pendant des mois sans que
> personne ne s'en aperçoive ; le jour où un disque meurt, on découvre que la
> seule copie restante d'un bloc était elle-même mauvaise. Le `scrub` relit
> **tout** ce qui est alloué, vérifie chaque somme de contrôle et répare depuis
> la copie saine pendant que la redondance existe encore. On le planifie
> (mensuel en général : `zfsutils-linux` installe une tâche mensuelle sur
> Ubuntu ; pour Btrfs, un timer `btrfs-scrub@`) et on surveille son résultat.

---

<a id="q32-15"></a>**[Q32.15](README.md#q32-15)** — *`fio --direct=1`.*

**Réponse : a)** contourner le cache de pages pour mesurer le stockage.

> [!NOTE]
> **Pourquoi**
>
> Sans `O_DIRECT`, les écritures s'arrêtent dans le cache de pages et les
> lectures répétées en sortent : on mesure la mémoire, à des millions d'IOPS
> qui n'ont rien à voir avec le disque. `--direct=1` envoie les E/S au système
> de fichiers puis au périphérique. Deux nuances d'expert : un `fsync` par
> écriture (`--fsync=1`) est ce qui reproduit une base de données, avec ou sans
> `O_DIRECT` ; et ZFS 2.2 (celui d'Ubuntu 24.04) **accepte** `O_DIRECT` mais
> passe quand même par l'ARC, d'où la limitation de l'ARC, un fichier plus
> grand que l'ARC ou `primarycache=metadata` pendant le banc (L32.4).

---

<a id="q32-16"></a>**[Q32.16](README.md#q32-16)** — *RAID 5/6 de Btrfs.*

**Réponse : d)** encore déconseillé pour les données en production.

> [!NOTE]
> **Pourquoi**
>
> Le RAID 5/6 de Btrfs a longtemps souffert du **trou d'écriture** (*write
> hole* : une coupure pendant la mise à jour d'une bande laisse la parité
> incohérente avec les données) et de reconstructions très lentes ; la
> documentation du projet le classe toujours comme non recommandé pour les
> données, même si les métadonnées en RAID1 et les correctifs récents
> améliorent la situation. Le RAID-Z de ZFS évite le trou d'écriture par
> conception (bandes de largeur variable, écriture en copie). Pour de la
> parité sur Linux, on reste sur ZFS RAID-Z ou mdadm + un système de fichiers
> classique.

---

## 32.4 Quiz — questions ouvertes

<a id="qo32-1"></a>**[QO32.1](README.md#qo32-1)** — *Apports et coûts de la copie sur écriture.*

**Réponse attendue**

Apports :

* **cohérence** après coupure sans journal de données ni `fsck` : l'arbre
  bascule d'une racine valide à la suivante ;
* **instantanés** instantanés, lisibles, nombreux, et **réplication
  incrémentale** efficace (les différences entre deux instantanés se
  calculent sans parcourir les fichiers) ;
* **sommes de contrôle** des données et autoréparation avec redondance ;
* **copies légères** (`reflink`, clones) ;
* compression transparente, gestion des volumes intégrée.

Coûts :

* **fragmentation** des fichiers réécrits en place (bases, images de VM) ;
* **amplification** d'écriture (remonter l'arbre à chaque modification) et
  sensibilité à la taille des blocs (`recordsize`) ;
* comportement **pathologique quand c'est plein** : il faut de l'espace pour
  libérer de l'espace (même supprimer écrit de nouvelles métadonnées) ; on
  garde 10 à 20 % de marge ;
* comptabilité de l'espace moins intuitive (instantanés, `df`), plus de
  mémoire (ARC), complexité d'exploitation.

À éviter : base de données très sollicitée en écritures aléatoires sans
réglage (ou alors ZFS bien réglé, ou Btrfs avec `nodatacow`), disque de VM
sur Btrfs CoW, petites machines à mémoire comptée (ZFS), équipe qui ne
saura pas l'exploiter, système qui doit fonctionner rempli à 95 %.

---

<a id="qo32-2"></a>**[QO32.2](README.md#qo32-2)** — *Le disque peut mentir.*

**Réponse attendue**

Sources de corruption silencieuse :

* **écriture perdue** (*lost write*) : le disque confirme une écriture qui
  n'a jamais eu lieu (cache d'écriture sans protection, micrologiciel
  bogué) ;
* **écriture mal dirigée** : le bloc part au mauvais endroit, deux blocs sont
  faux à la fois ;
* **pourrissement** du support (*bit rot*) au-delà de ce que les codes
  correcteurs détectent, notamment sur des données froides ;
* **erreurs en transit** : câble, contrôleur, pilote, mémoire non ECC qui
  altère la donnée avant qu'elle soit écrite ou après qu'elle a été lue ;
* **bogues logiciels** dans la pile (pilote, hyperviseur, système de
  fichiers).

ext4 et XFS font confiance au périphérique pour les données : ils n'ont rien
à comparer. ZFS et Btrfs stockent une somme de contrôle de chaque bloc **dans
son parent**, en remontant jusqu'à la racine (arbre de Merkle) : une donnée
relue qui ne correspond plus à la somme attendue est détectée, quelle que soit
la cause, et réparée depuis une copie saine s'il en existe une. Une écriture
perdue ou mal dirigée laisse un bloc dont la somme ne correspond pas à ce que
le parent attend : elle est donc détectée elle aussi, ce qu'aucune somme
stockée **à côté** des données ne permettrait.

---

<a id="qo32-3"></a>**[QO32.3](README.md#qo32-3)** — *Le fichier de configuration vide après coupure.*

**Réponse attendue**

`open(..., O_TRUNC)` tronque le fichier **immédiatement** ; les nouvelles
données sont dans le cache, écrites plus tard. Une coupure entre les deux
laisse un fichier de taille nulle (ou partiel) : ni l'ancienne version, ni la
nouvelle. L'allocation différée d'ext4 rend la fenêtre longue (jusqu'à
30 secondes avant l'écriture des données). La séquence correcte :

```c
int fd = open("config.json.tmp", O_WRONLY | O_CREAT | O_TRUNC, 0644);
write(fd, données, n);            /* boucler jusqu'à tout écrire, vérifier */
fsync(fd);                        /* les données du fichier temporaire sont sur le support */
close(fd);
rename("config.json.tmp", "config.json");   /* atomique : ancien OU nouveau */
int dfd = open(".", O_RDONLY | O_DIRECTORY);
fsync(dfd);                       /* le renommage lui-même est persistant */
close(dfd);
```

Le fichier temporaire est dans le **même** répertoire (même système de
fichiers : `rename` doit rester atomique et ne pas devenir une copie), et en
cas d'erreur on le supprime. En Python, `os.replace` + `os.fsync` ; en shell,
`sync fichier` puis `mv` puis `sync répertoire` (E32.3).

---

<a id="qo32-4"></a>**[QO32.4](README.md#qo32-4)** — *Instantané CoW, instantané LVM, sauvegarde restic.*

**Réponse attendue**

| | Instantané ZFS/Btrfs | Instantané LVM | Sauvegarde restic |
|---|---|---|---|
| Coût à la création | nul | faible, puis **chaque** écriture coûte une copie | lecture de tout ce qui a changé |
| Nombre raisonnable | centaines | un ou deux, temporaires | autant que la rétention |
| Cohérence | instantané atomique du système de fichiers | idem au niveau bloc | fichier par fichier, sauf si on sauvegarde un instantané |
| Survit à la perte du disque / du pool | **non** | non | oui |
| Survit à root compromis | non (il peut détruire) | non | dépend du dépôt (ajout seul : oui) |

Un instantané protège contre l'**erreur humaine** et la corruption logique
avec un RPO de quelques minutes et une restauration immédiate. Il ne remplace
pas une sauvegarde : il meurt avec le pool, et l'administrateur (ou
l'attaquant) peut le détruire. Les instantanés deviennent une sauvegarde dès
qu'ils sont **répliqués** vers un autre système, idéalement sur un autre site
et avec d'autres droits (D32, et module 30).

---

<a id="qo32-5"></a>**[QO32.5](README.md#qo32-5)** — *Quel système de fichiers pour quoi.*

**Réponse attendue**

* **ext4** : système d'une VM générique, disques de démarrage, cas où la
  simplicité et la robustesse de `e2fsck` priment ; peut se réduire.
* **XFS** : très gros volumes et fichiers, parallélisme d'E/S (groupes
  d'allocation), bases de données et serveurs de fichiers sur matériel
  fiable ; `reflink` ; défaut de RHEL. Ne se réduit pas.
* **Btrfs** : système de poste ou de serveur avec instantanés avant mise à
  jour (Snapper, retour arrière), stockage de conteneurs, miroir à deux
  disques simple à gérer, compression ; défaut de Fedora et openSUSE.
* **ZFS** : stockage de données où l'intégrité prime (serveur de fichiers,
  sauvegardes, stockage de VM avec Proxmox), réplication incrémentale entre
  sites, RAID-Z, gros volumes ; au prix de mémoire et d'un module hors noyau.

Le critère n'est pas « le meilleur » mais ce qu'on veut garantir (intégrité,
performance, simplicité de réparation) et ce que l'équipe sait exploiter à
trois heures du matin.

---

<a id="qo32-6"></a>**[QO32.6](README.md#qo32-6)** — *Un banc d'essai digne de confiance.*

**Réponse attendue**

* **Charge représentative** : taille de bloc, mélange lecture/écriture,
  aléatoire ou séquentiel, synchronisation, profondeur de file **de
  l'application réelle** (relevés avec `biolatency`, `iostat`, ou les
  statistiques de la base).
* **Conditions contrôlées** : caches neutralisés ou maîtrisés (O_DIRECT,
  fichier plus grand que la mémoire, ARC limité), disque préconditionné (un
  SSD neuf ment), machine au repos, même disque pour tous les candidats.
* **Durée** suffisante (60 s au moins, plus pour les SSD), **plusieurs
  passages** (3 à 5), médiane et dispersion.
* **Métriques complètes** : IOPS, débit **et** latence en percentiles (p50,
  p99, p99,9), plus la consommation CPU.
* **Publication** : commandes exactes (fichier de tâche `fio`), versions
  (noyau, système de fichiers, options), matériel, résultats bruts en JSON,
  et les **limites** de la mesure. Un résultat qu'on ne peut pas refaire ne
  vaut rien.

---

<a id="qo32-7"></a>**[QO32.7](README.md#qo32-7)** — *Allocation fine sur l'hyperviseur.*

**Réponse attendue**

Avantages : on n'achète pas d'avance l'espace que les VM n'utilisent pas ;
instantanés et clones peu coûteux (LVM thin, ZFS, qcow2) ; provisionnement
rapide.

Risques : la **sur-allocation** (la somme des disques promis dépasse
l'espace réel) devient une dette. Quand le pool thin est plein, les écritures
des VM échouent ou les VM sont mises en pause ; avec LVM thin, un pool de
métadonnées plein peut corrompre le pool. Et sans TRIM, l'espace libéré par
les invités n'est jamais rendu (BF32.3).

À surveiller : taux de remplissage des données **et** des métadonnées du pool
(`lvs -o lv_name,data_percent,metadata_percent`), avec des alertes bien avant
100 % (80 et 90 %) ; ratio de sur-allocation ; activation de `discard` sur les
disques virtuels et de `fstrim.timer` dans les invités ; extension automatique
(`thin_pool_autoextend_threshold`) si le groupe de volumes a de la réserve.

---

<a id="qo32-8"></a>**[QO32.8](README.md#qo32-8)** — *ZFS, Ubuntu et les autres.*

**Réponse attendue**

ZFS est publié sous licence **CDDL**, que beaucoup de juristes (dont ceux de
la Free Software Foundation) jugent incompatible avec la **GPLv2** du noyau
Linux pour la distribution d'un binaire combiné. Debian, Fedora, RHEL ne
livrent donc pas le module compilé : il est construit sur chaque machine
(DKMS) ou fourni par le projet OpenZFS. Canonical a estimé que livrer le
module séparé était acceptable et le fournit précompilé, signé, avec ses
noyaux.

Conséquences pratiques : avec DKMS, chaque mise à jour du noyau recompile le
module (et une mise à jour du noyau plus rapide que le support d'OpenZFS peut
laisser la machine sans ZFS au redémarrage) ; le module n'est pas signé par la
distribution, ce qui complique le démarrage sécurisé (*Secure Boot*) ; le
support éditeur (Red Hat) ne couvre pas ZFS. Sur Ubuntu, ces points
disparaissent, mais l'équipe dépend d'un choix d'une seule distribution.

---

## 32.5 Exercices guidés

<a id="e32-1"></a>**[E32.1](README.md#e32-1)** — *Les quatre disques.*

```bash
lsblk -d -o NAME,SERIAL,SIZE,DISC-GRAN,DISC-MAX,TYPE | grep -E 'NAME|lab32'
ls -l /dev/disk/by-id/ | grep lab32
cat ~/lab32/disques.env
```

```console
NAME SERIAL   SIZE DISC-GRAN DISC-MAX TYPE
sdd  lab32-3    3G        4K       1G disk
sde  lab32-4    3G        4K       1G disk
…
lrwxrwxrwx 1 root root 9 … scsi-0QEMU_QEMU_HARDDISK_lab32-3 -> ../../sdd
```

> [!NOTE]
> **Pourquoi**
>
> `DISC-MAX` non nul : le disque virtuel accepte les demandes de TRIM (grâce à
> `discard=on`). Le numéro de série posé par Proxmox se retrouve dans le nom
> `by-id` : c'est ce qui permet de désigner sans ambiguïté « le disque
> lab32-4 », quel que soit le nom `sdX` qu'il reçoit à ce démarrage.

---

<a id="e32-2"></a>**[E32.2](README.md#e32-2)** — *Journal d'ext4.*

```bash
. ~/lab32/disques.env
sudo mkfs.ext4 -F -L lab32 "$A"
sudo dumpe2fs -h "$A" 2>/dev/null | grep -E 'features|Journal size|Default mount options'
sudo mount "$A" /srv/lab32/ext4 && findmnt -no OPTIONS /srv/lab32/ext4
#   rw,relatime          -> data=ordered implicite
```

> [!NOTE]
> **Pourquoi**
>
> `data=ordered` n'apparaît pas parce que c'est le défaut. On le vérifie aussi
> dans `/proc/fs/ext4/<périphérique>/options`, qui liste toutes les options
> effectives. Le journal (souvent 64 ou 128 Mio) est une zone de l'ext4
> lui-même, sauf journal externe sur un autre périphérique (`-J device=`).

---

<a id="e32-3"></a>**[E32.3](README.md#e32-3)** — *Mise à jour atomique en shell.*

```bash
f=/srv/lab32/ext4/etat.txt; tmp=$(mktemp "${f%/*}/.etat.XXXXXX")
printf 'valeur=%s\n' "$(date +%s)" > "$tmp"
sync "$tmp"                     # fsync du fichier temporaire
mv -f "$tmp" "$f"               # rename(2), atomique sur le même système de fichiers
sync "${f%/*}"                  # fsync du répertoire
```

> [!NOTE]
> **Pourquoi**
>
> `sync FICHIER` (coreutils ≥ 8.24) appelle `fsync` sur ce fichier, et
> `sync RÉPERTOIRE` sur le répertoire. Un `sync` sans argument vide **tous** les
> systèmes de fichiers de la machine : correct mais brutal, et sans garantie
> d'ordre par rapport au `mv`. `mktemp` dans le même répertoire évite qu'un `mv`
> entre deux systèmes de fichiers devienne une copie suivie d'une suppression,
> qui n'a plus rien d'atomique.

---

<a id="e32-4"></a>**[E32.4](README.md#e32-4)** — *`reflink` sur XFS.*

```bash
sudo umount /srv/lab32/ext4 2>/dev/null
sudo mkfs.xfs -f "$A" && sudo mount "$A" /srv/lab32/xfs
sudo xfs_info /srv/lab32/xfs | grep -o 'reflink=[01]'      # reflink=1
cd /srv/lab32/xfs
sudo dd if=/dev/urandom of=gros.img bs=1M count=1024 status=none
df -m . | tail -1
time sudo cp --reflink=always gros.img copie.img           # quelques millisecondes
df -m . | tail -1                                          # quasi identique
sudo dd if=/dev/urandom of=copie.img bs=1M count=10 seek=100 conv=notrunc status=none
df -m . | tail -1                                          # +10 Mio
```

> [!NOTE]
> **Pourquoi**
>
> Seuls les blocs modifiés sont dupliqués (10 Mio, à la granularité des blocs
> de 4 Kio). `cp` sans option utilise `--reflink=auto` par défaut depuis
> coreutils 9 : sur XFS ou Btrfs, une simple copie est déjà un reflink. C'est
> pratique, et trompeur pour qui veut **vraiment** deux copies physiques (pour
> une sauvegarde sur le même disque, cela ne protège de rien).

---

<a id="e32-5"></a>**[E32.5](README.md#e32-5)** — *Répartition réelle et compression sur Btrfs.*

```bash
sudo btrfs filesystem usage -T /srv/btrfs
sudo compsize /srv/btrfs/@donnees          # apt install btrfs-compsize
#   Type       Perc     Disk Usage   Uncompressed Referenced
#   TOTAL       31%       41M         132M         132M
#   zstd        28%       33M         119M         119M
```

> [!NOTE]
> **Pourquoi**
>
> `usage -T` présente un tableau par disque : en RAID1, chaque Gio de données
> en occupe deux. `compsize` (paquet `btrfs-compsize`) lit les étendues et
> donne le taux réel ; `du` montre la taille **logique** des fichiers. La
> documentation texte de `/usr/share/doc` se compresse à 30 % environ.

---

<a id="e32-6"></a>**[E32.6](README.md#e32-6)** — *Sous-volumes et instantanés.*

```bash
sudo btrfs subvolume list -t -p -q /srv/btrfs
sudo btrfs subvolume list -r /srv/btrfs        # seulement les instantanés en lecture seule
```

> [!NOTE]
> **Pourquoi**
>
> Un sous-volume est un arbre de fichiers indépendant, montable séparément
> (`-o subvol=@donnees`) ; un instantané est un sous-volume qui partage ses
> blocs avec un autre. `-q` affiche l'UUID parent : c'est ce qui relie un
> instantané à sa source, et ce que `btrfs send -p` utilise pour calculer un
> flux incrémental.

---

<a id="e32-7"></a>**[E32.7](README.md#e32-7)** — *Compteurs d'erreurs.*

```bash
sudo btrfs device stats /srv/btrfs
#   [/dev/sde].write_io_errs    0
#   [/dev/sde].corruption_errs  1
sudo btrfs device stats -z /srv/btrfs          # affiche, puis remet à zéro
```

> [!NOTE]
> **Pourquoi**
>
> Les compteurs sont persistants (stockés dans le système de fichiers) : un
> disque qui accumule des `corruption_errs` ou des `read_io_errs` au fil des
> semaines est à changer, même si chaque erreur a été réparée. On les note
> avant de les remettre à zéro, sinon on perd l'historique qui justifie un
> remplacement.

---

<a id="e32-8"></a>**[E32.8](README.md#e32-8)** — *Propriétés de `tank/donnees`.*

```bash
zfs get -s local,received all tank/donnees
#   NAME          PROPERTY     VALUE  SOURCE
#   tank/donnees  compression  zstd   local
#   tank/donnees  atime        off    local
#   tank/donnees  quota        1G     local
```

> [!NOTE]
> **Pourquoi**
>
> La colonne `SOURCE` distingue une valeur posée sur ce dataset (`local`),
> héritée d'un parent (`inherited from tank`), reçue par réplication
> (`received`) ou par défaut. Les propriétés s'héritent : poser
> `compression=zstd` sur `tank` l'applique à tous les datasets créés dessous,
> ce qui est la bonne pratique.

---

<a id="e32-9"></a>**[E32.9](README.md#e32-9)** — *Où est l'espace.*

```bash
zfs list -o space -r tank
#   NAME          AVAIL   USED  USEDSNAP  USEDDS  USEDREFRESERV  USEDCHILD
#   tank          1.95G   612M        0B     96K             0B       612M
#   tank/donnees   624M   412M      38M     374M             0B         0B
#   tank/pg       1.95G   200M        0B     24K           200M         0B
```

> [!NOTE]
> **Pourquoi**
>
> `USEDSNAP` : espace retenu **uniquement** par des instantanés (ce qu'on
> gagnerait en les détruisant tous) ; `USEDDS` : données vivantes ;
> `USEDREFRESERV` : espace réservé non encore utilisé ; `USEDCHILD` : les
> datasets enfants. C'est la commande de BF32.1. L'`AVAIL` de `tank/donnees`
> est borné par son quota.

---

<a id="e32-10"></a>**[E32.10](README.md#e32-10)** — *Cache ARC.*

```bash
arc_summary -s arc | head -20
awk '/^(size|c|c_max|hits|misses) /{print $1, $3}' /proc/spl/kstat/zfs/arcstats
```

> [!NOTE]
> **Pourquoi**
>
> `size` : taille actuelle ; `c` : cible ; `c_max` : plafond (doit valoir
> 268435456 après L32.3). Le taux de réussite = `hits / (hits + misses)`. Un
> taux bas avec un ARC au plafond signale un ensemble de travail plus grand que
> le cache ; un ARC qui ne descend pas alors que la machine manque de mémoire
> signale un plafond mal réglé.

---

<a id="e32-11"></a>**[E32.11](README.md#e32-11)** — *Clone et instantané d'origine.*

```bash
zfs snapshot tank/donnees@pour-clone
zfs clone tank/donnees@pour-clone tank/essai
echo modif | sudo tee /tank/essai/nouveau.txt
zfs destroy tank/donnees@pour-clone
#   cannot destroy 'tank/donnees@pour-clone': snapshot has dependent clones
zfs promote tank/essai          # le clone devient le parent ; l'instantané lui appartient
# ou : zfs destroy tank/essai && zfs destroy tank/donnees@pour-clone
```

> [!NOTE]
> **Pourquoi**
>
> Un clone est un dataset modifiable qui partage ses blocs avec l'instantané
> dont il est issu : l'instantané ne peut pas disparaître tant que le clone
> existe. `zfs promote` inverse la dépendance (utile quand on veut garder le
> clone et jeter l'original, par exemple après un essai de mise à jour réussi
> sur un clone de la production).

---

<a id="e32-12"></a>**[E32.12](README.md#e32-12)** — *Volume thin vu du nœud.*

```bash
# nœud Proxmox
qm config 9003 | grep serial=lab32-3        # repérer le volume : vm-9003-disk-N
lvs -o lv_name,lv_size,data_percent pve | grep 'vm-9003'
# lab-db : remplir puis vider
sudo dd if=/dev/urandom of=/srv/lab32/xfs/remplissage bs=1M count=2000 status=none; sudo rm /srv/lab32/xfs/remplissage
# nœud : Data% a monté et ne redescend pas
# lab-db
sudo fstrim -v /srv/lab32/xfs                # /srv/lab32/xfs: 2.8 GiB (…) trimmed
# nœud : Data% redescend
```

> [!NOTE]
> **Pourquoi**
>
> Les données aléatoires empêchent toute compression ou détection de zéros
> côté hôte. Le `fstrim` annonce comme libres tous les blocs non utilisés du
> système de fichiers (même ceux jamais écrits), d'où un volume « rogné »
> supérieur aux 2 Go supprimés. C'est le mécanisme complet de BF32.3.

---

## 32.6 Labs

### <a id="l32-1"></a>**[L32.1](README.md#l32-1)** — Ce que le disque peut faire dans ton dos

**Étapes 1 et 2 — Le fichier témoin et son emplacement**

```bash
. ~/lab32/disques.env
sudo mkfs.ext4 -F -L lab32 "$A"
sudo mkdir -p /srv/lab32/ext4 && sudo mount "$A" /srv/lab32/ext4
sudo dd if=/dev/urandom of=/srv/lab32/ext4/temoin.bin bs=1M count=32 status=none
sync
sha256sum /srv/lab32/ext4/temoin.bin | tee ~/lab32/temoin.sha256
sudo filefrag -v /srv/lab32/ext4/temoin.bin | head -6
#   Filesystem type is: ef53
#   File size of temoin.bin is 33554432 (8192 blocks of 4096 bytes)
#    ext:     logical_offset:        physical_offset: length:   expected: flags:
#      0:        0..    8191:      34816..     43007:   8192:             last,eof
```

Le fichier occupe une seule étendue, des blocs 34816 à 43007. Le milieu :
bloc 34816 + 4096 = 38912. L'ext4 occupe tout le disque (pas de partition) :
le bloc n du système de fichiers est à l'octet n × 4096 du périphérique.

```bash
sudo umount /srv/lab32/ext4
sudo dd if=/dev/urandom of="$A" bs=4096 seek=38912 count=1 conv=notrunc oflag=direct status=none
```

**Étape 3 — Relire**

```bash
sudo mount "$A" /srv/lab32/ext4
echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
sha256sum /srv/lab32/ext4/temoin.bin; cat ~/lab32/temoin.sha256     # différents
cat /srv/lab32/ext4/temoin.bin > /dev/null && echo "lecture sans erreur"
sudo dmesg | tail -3                                                # rien
sudo umount /srv/lab32/ext4 && sudo e2fsck -fn "$A"
#   lab32: 12/196608 files (0.0% non-contiguous), …   -> propre
```

**Étape 4 — `corruption.md`**

```markdown
# Corruption silencieuse sur ext4 (démonstration du 2026-11-09)
1. temoin.bin (32 Mio aléatoires) écrit sur ext4, SHA-256 noté.
2. 4 Kio écrasés sur le disque brut au milieu du fichier (bloc 38912).
3. Relecture : AUCUNE erreur (ni à la lecture, ni dans dmesg), empreinte
   DIFFÉRENTE. e2fsck -fn : système de fichiers « propre ».
Conclusion : ext4 (comme XFS) ne vérifie pas les données ; une corruption par
le disque, le contrôleur ou la mémoire est rendue à l'application comme une
donnée valide, et se propage dans les sauvegardes. Seul un système à sommes de
contrôle des données (ZFS, Btrfs) la détecte, et la répare s'il a une copie
(L32.2, L32.3). Recommandation : ZFS en miroir pour le serveur de fichiers.
```

**Étape 5 — Les défauts de `lab32-sauve-etat`**

```python
with open(CHEMIN, "w") as f:          # ouvre et TRONQUE le fichier en place
    json.dump(etat, f)
print("état sauvegardé")               # … sans rien garantir
```

1. **Troncature en place** : `open(..., "w")` vide le fichier avant d'écrire
   le nouveau contenu ; une coupure entre les deux laisse un fichier vide ou
   partiel, ni ancien ni nouveau.
2. **Aucune synchronisation** : à la sortie de `with`, les données sont dans
   le cache de pages ; « état sauvegardé » est affiché alors que rien n'est
   sur le disque, et ne le sera qu'une trentaine de secondes plus tard au
   pire.

**Étape 6 — La version corrigée**

```python
#!/usr/bin/env python3
"""sauve-etat-corrige — mise à jour atomique et durable de l'état (module 32, L32.1)."""
import json
import os
import sys
import tempfile
import time

CHEMIN = "/var/lib/lab32/etat.json"
rep = os.path.dirname(CHEMIN)
etat = {"valeur": sys.argv[1] if len(sys.argv) > 1 else "0", "horodatage": time.time()}

fd, tmp = tempfile.mkstemp(dir=rep, prefix=".etat.")   # même répertoire => même FS
try:
    with os.fdopen(fd, "w") as f:
        json.dump(etat, f)
        f.flush()                    # tampon Python -> noyau
        os.fsync(f.fileno())         # noyau -> support
    os.replace(tmp, CHEMIN)          # rename(2) : ancien OU nouveau, jamais un mélange
    dfd = os.open(rep, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(dfd)                # le renommage est persistant
    finally:
        os.close(dfd)
except BaseException:
    try:
        os.unlink(tmp)
    except FileNotFoundError:
        pass
    raise
print("état sauvegardé")             # maintenant, c'est vrai
```

```console
$ sudo strace -f -e trace=openat,write,fsync,rename python3 ~/lab32/sauve-etat-corrige.sh 42
openat(AT_FDCWD, "/var/lib/lab32/.etat.k2j8a1", O_RDWR|O_CREAT|O_EXCL|O_CLOEXEC, 0600) = 3
write(3, "{\"valeur\": \"42\", \"horodatage\": …", 52) = 52
fsync(3)                                = 0
rename("/var/lib/lab32/.etat.k2j8a1", "/var/lib/lab32/etat.json") = 0
openat(AT_FDCWD, "/var/lib/lab32", O_RDONLY|O_DIRECTORY|O_CLOEXEC) = 3
fsync(3)                                = 0
write(1, "état sauvegardé\n", 17)       = 17
```

> [!NOTE]
> **Pourquoi**
>
> L'ordre est la preuve : `fsync` du fichier **avant** `rename`, puis `fsync`
> du répertoire **après**. `f.flush()` est indispensable en Python : sans lui,
> les données sont encore dans le tampon de l'objet fichier au moment du
> `fsync`, qui synchronise alors un fichier vide. `mkstemp` crée le fichier en
> `0600` : si l'état doit être lisible par d'autres, on pose les droits
> (`os.fchmod`) avant le renommage.

---

### <a id="l32-2"></a>**[L32.2](README.md#l32-2)** — Btrfs : miroir, instantanés, panne de disque

**Étape 1 — Le volume**

```bash
. ~/lab32/disques.env
sudo mkfs.btrfs -f -L donnees -d raid1 -m raid1 "$B" "$C"
U=$(sudo blkid -s UUID -o value "$B")
sudo mkdir -p /srv/btrfs
echo "UUID=$U /srv/btrfs btrfs compress=zstd:3,noatime,nofail,x-systemd.device-timeout=15s 0 0" |
  sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount /srv/btrfs
sudo btrfs filesystem show /srv/btrfs
```

Les deux disques ont le **même** UUID de système de fichiers (c'est un seul
volume) ; n'importe lequel suffit à le désigner. `nofail` et le délai
borné évitent qu'un disque absent bloque le démarrage (BF32.2).

**Étape 2 — Sous-volumes et compression**

```bash
sudo btrfs subvolume create /srv/btrfs/@donnees
sudo btrfs subvolume create /srv/btrfs/.instantanes
sudo cp -a /usr/share/doc /srv/btrfs/@donnees/
sudo apt install -y btrfs-compsize && sudo compsize /srv/btrfs/@donnees
```

`.instantanes` est un sous-volume à part : les instantanés de `@donnees` ne
sont pas inclus dans les instantanés de `@donnees` eux-mêmes (un instantané
ne descend pas dans les sous-volumes imbriqués).

**Étape 3 — Instantané et restauration**

```bash
S=/srv/btrfs/.instantanes/@donnees-$(date +%F-%H%M)
sudo btrfs subvolume snapshot -r /srv/btrfs/@donnees "$S"
sudo rm -rf /srv/btrfs/@donnees/doc/bash
sudo cp -a --reflink=always "$S/doc/bash" /srv/btrfs/@donnees/doc/
```

La restauration par `cp --reflink` ne recopie pas les données : elle partage
les blocs de l'instantané.

**Étape 4 — Corruption et autoréparation**

```bash
sudo dd if=/dev/urandom of=/srv/btrfs/@donnees/temoin.bin bs=1M count=32 status=none; sync
sha256sum /srv/btrfs/@donnees/temoin.bin
L=$(sudo filefrag -v /srv/btrfs/@donnees/temoin.bin | awk '$1=="0:"{print $4}' | tr -d '.')
sudo btrfs-map-logical -l $(( (L + 4096) * 4096 )) "$B"
#   mirror 1 logical 1103101952 physical 1094713344 device /dev/sde
#   mirror 2 logical 1103101952 physical 1073741824 device /dev/sdf
sudo dd if=/dev/urandom of="$B" bs=4096 seek=$((1094713344 / 4096)) count=1 conv=notrunc oflag=direct
echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
sha256sum /srv/btrfs/@donnees/temoin.bin        # empreinte INCHANGÉE
sudo dmesg | grep -i btrfs | tail -3
#   BTRFS warning (device sde): csum failed root 256 ino 2581 off 16777216 csum 0x… expected csum 0x… mirror 1
#   BTRFS info (device sde): read error corrected: ino 2581 off 16777216 (dev /dev/sde sector 2138112)
sudo btrfs scrub start -B /srv/btrfs
sudo btrfs device stats /srv/btrfs | grep -v ' 0$'
```

> [!NOTE]
> **Pourquoi**
>
> Sur Btrfs, `filefrag` donne des adresses **logiques** du système de fichiers,
> pas des positions sur un disque : avec un miroir, chaque adresse logique
> existe à deux endroits physiques, sur deux disques. `btrfs-map-logical`
> fait la traduction. On ne corrompt qu'une copie : à la lecture, Btrfs détecte
> l'écart, lit l'autre copie, rend la bonne donnée et réécrit la mauvaise
> (*read repair*). L'application ne voit rien ; seul le journal noyau et les
> compteurs en gardent la trace.

**Étape 5 — Perte d'un disque et remplacement**

```bash
NC=$(basename "$(readlink -f "$C")")
echo 1 | sudo tee /sys/block/"$NC"/device/delete
sudo btrfs filesystem show /srv/btrfs        # *** Some devices missing
sudo umount /srv/btrfs
sudo mount /srv/btrfs                        # échec : refuse de monter sans tous ses disques
sudo mount -o degraded "$B" /srv/btrfs
ID=$(sudo btrfs filesystem show /srv/btrfs | awk '/missing/{print $2}')
sudo btrfs replace start -B "$ID" "$D" /srv/btrfs
sudo btrfs balance start -dconvert=raid1,soft -mconvert=raid1,soft /srv/btrfs
sudo btrfs filesystem usage /srv/btrfs | grep -E 'RAID1|single'
sudo umount /srv/btrfs && sudo mount /srv/btrfs      # remontage normal, sans degraded
# remettre le disque retiré dans la VM (il porte encore l'ancienne signature Btrfs)
echo '- - -' | sudo tee /sys/class/scsi_host/host*/scan >/dev/null
sudo wipefs -a "$C"
```

> [!WARNING]
> **Piège**
>
> Le disque retiré puis redécouvert porte toujours la signature du volume : si
> on le laisse tel quel, `btrfs device scan` le présente comme un membre du
> volume avec des données périmées. On l'efface (`wipefs -a`) avant toute autre
> utilisation. Et l'on ne garde jamais `degraded` dans `fstab` : un volume qui
> démarre sans redondance sans que personne le sache est exactement ce que
> Btrfs cherche à éviter.

**Étape 6 — Réplication par flux**

```bash
S1=/srv/btrfs/.instantanes/@donnees-r1
sudo btrfs subvolume snapshot -r /srv/btrfs/@donnees "$S1"
sudo btrfs send -f ~/lab32/donnees-r1.btrfs "$S1"
echo nouveau | sudo tee /srv/btrfs/@donnees/apres-r1.txt
S2=/srv/btrfs/.instantanes/@donnees-r2
sudo btrfs subvolume snapshot -r /srv/btrfs/@donnees "$S2"
sudo btrfs send -p "$S1" -f ~/lab32/donnees-r2.btrfs "$S2"
ls -lh ~/lab32/donnees-r*.btrfs        # le second est minuscule
# vérification : rejouer les deux flux dans un sous-volume de test
sudo mkdir -p /srv/btrfs/test-recep
sudo btrfs receive -f ~/lab32/donnees-r1.btrfs /srv/btrfs/test-recep
sudo btrfs receive -f ~/lab32/donnees-r2.btrfs /srv/btrfs/test-recep
cat /srv/btrfs/test-recep/@donnees-r2/apres-r1.txt
```

Un flux incrémental ne s'applique que si la destination possède déjà le
parent `@donnees-r1` (même UUID reçu) : c'est la même règle que pour ZFS
(Q32.9).

---

### <a id="l32-3"></a>**[L32.3](README.md#l32-3)** — ZFS : pool, datasets, autoréparation, réplication

**Étape 1 — Démanteler Btrfs, limiter l'ARC**

```bash
sudo umount /srv/btrfs
sudo sed -i '\|/srv/btrfs |d' /etc/fstab
. ~/lab32/disques.env
for d in "$B" "$C" "$D"; do sudo wipefs -a "$d"; done
sudo modprobe zfs
echo 'options zfs zfs_arc_max=268435456' | sudo tee /etc/modprobe.d/zfs.conf
echo 268435456 | sudo tee /sys/module/zfs/parameters/zfs_arc_max
```

**Étape 2 — Les pools**

```bash
sudo zpool create -o ashift=12 -O compression=zstd -O atime=off -O xattr=sa \
  -O acltype=posixacl -m /tank tank mirror "$B" "$C"
sudo zpool create -o ashift=12 -O readonly=on -m none sauve "$D"
zpool status -P tank
```

`-P` affiche les chemins complets : ce sont bien les identifiants `by-id`.
Les options `-O` s'appliquent au dataset racine et s'héritent. `sauve` est en
lecture seule et sans point de montage : il ne sert qu'à recevoir.

**Étape 3 — Datasets**

```bash
sudo zfs create -o quota=1G tank/donnees
sudo zfs create -o recordsize=16K -o compression=lz4 -o reservation=200M tank/pg
sudo cp -a /usr/share/doc /tank/donnees/
zfs get -H -o value compressratio tank/donnees        # ≈ 3.2x
```

Le taux est comparable à celui de Btrfs en zstd (rapport inverse du
pourcentage de `compsize`) ; les deux utilisent zstd, au même ordre de niveau.

**Étape 4 — Corruption en service et autoréparation**

```bash
sudo dd if=/dev/urandom of=/tank/donnees/temoin.bin bs=1M count=400 status=none; sync
sudo dd if=/dev/urandom of="$B-part1" bs=1M seek=64 count=64 conv=notrunc oflag=direct status=none
sudo zpool scrub -w tank
zpool status tank
```

```console
  pool: tank
 state: ONLINE
status: One or more devices has experienced an unrecoverable error.  An
        attempt was made to correct the error.  Applications are unaffected.
action: Determine if the device needs to be replaced, and clear the errors
        using 'zpool clear' or replace the device with 'zpool replace'.
  scan: scrub repaired 63.1M in 00:00:09 with 0 errors on Mon Nov  9 11:42:10 2026
config:
        NAME                                   STATE     READ WRITE CKSUM
        tank                                   ONLINE       0     0     0
          mirror-0                             ONLINE       0     0     0
            scsi-0QEMU_QEMU_HARDDISK_lab32-4   ONLINE       0     0   504
            scsi-0QEMU_QEMU_HARDDISK_lab32-5   ONLINE       0     0     0
errors: No known data errors
```

> [!NOTE]
> **Pourquoi**
>
> On écrase 64 Mio **pendant que le pool est importé**, ce qui n'arrive jamais
> avec un vrai disque… sauf quand un contrôleur ou un disque devient fou : c'est
> le pire cas. ZFS le supporte parce que toutes les copies sont vérifiées : 504
> blocs fautifs détectés sur `lab32-4`, réécrits depuis `lab32-5`, aucune donnée
> perdue (`errors: No known data errors`). On commence à 64 Mio du début de la
> partition pour éviter les étiquettes ZFS (au début et à la fin du disque), et
> le fichier témoin de 400 Mio garantit que la zone écrasée contient des
> données. `zpool clear tank` remet les compteurs à zéro une fois l'incident
> compris.

**Étape 5 — Instantanés et réplication**

```bash
sudo zfs snapshot tank/donnees@s1
sudo zfs send tank/donnees@s1 | sudo zfs receive -u sauve/donnees
echo deux | sudo tee /tank/donnees/s2.txt; sudo zfs snapshot tank/donnees@s2
sudo zfs send -i @s1 tank/donnees@s2 | sudo zfs receive -u sauve/donnees
echo trois | sudo tee /tank/donnees/s3.txt; sudo zfs snapshot tank/donnees@s3
sudo zfs send -i @s2 tank/donnees@s3 | sudo zfs receive -u sauve/donnees
zfs list -t snapshot -o name,used -r tank/donnees sauve/donnees
```

`-u` : la destination n'est pas montée, donc pas modifiée, et le prochain
incrémental s'appliquera. Avec `sauve` en `readonly=on` hérité, même un
montage manuel ne la modifierait pas.

**Étape 6 — Restaurer**

```bash
sudo rm -rf /tank/donnees/doc/bash
ls /tank/donnees/.zfs/snapshot/s3/doc/bash | head -3        # répertoire caché, toujours accessible
sudo cp -a /tank/donnees/.zfs/snapshot/s3/doc/bash/README* /tank/donnees/doc/ 2>/dev/null
sudo zfs rollback tank/donnees@s3                           # tout le dataset revient à s3
ls -d /tank/donnees/doc/bash
```

`.zfs` n'apparaît pas dans `ls -a` (par défaut `snapdir=hidden`), mais on peut
y entrer. `zfs rollback` ne revient qu'au **dernier** instantané ; revenir plus
loin exige `-r`, qui **détruit** les instantanés intermédiaires.

---

### <a id="l32-4"></a>**[L32.4](README.md#l32-4)** — Comparer sans se mentir

**Étape 1 — `banc.sh`**

```bash
#!/usr/bin/env bash
# banc.sh <point_de_montage> <étiquette> — deux charges fio, résultats en JSON (module 32, L32.4)
set -euo pipefail
M=${1:?point de montage} E=${2:?étiquette}
H=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)    # lancé par sudo : pas le HOME de root
OUT=$H/lab32/banc; mkdir -p "$OUT"
commun=(--directory="$M" --direct=1 --runtime=60 --time_based --group_reporting
        --output-format=json --randrepeat=0)
# base de données : 8 Kio aléatoires, chaque écriture synchronisée, une E/S à la fois
fio --name=base --rw=randwrite --bs=8k --size=1G --ioengine=psync --fsync=1 \
    "${commun[@]}" > "$OUT/$E-base-$(date +%s).json"
# sauvegarde : lecture séquentielle de 1 Mio, 8 E/S en vol
fio --name=sauvegarde --rw=read --bs=1M --size=2G --ioengine=libaio --iodepth=8 \
    "${commun[@]}" > "$OUT/$E-sauvegarde-$(date +%s).json"
rm -f "$M"/base.* "$M"/sauvegarde.*
# extrait : IOPS, Mio/s, p99 (ms)
for f in "$OUT/$E"-*.json; do
  jq -r --arg f "$(basename "$f")" '.jobs[0] as $j
    | (if $j.write.io_bytes > 0 then $j.write else $j.read end) as $o
    | [$f, ($o.iops|floor), ($o.bw/1024|floor), (($o.clat_ns.percentile["99.000000"] // 0)/1e6)] | @tsv' "$f"
done
```

**Étape 2 — Les quatre systèmes de fichiers**

```bash
. ~/lab32/disques.env; M=/srv/lab32/banc; sudo mkdir -p "$M"
for fs in ext4 xfs btrfs; do
  sudo wipefs -a "$A"; sudo "mkfs.$fs" -f "$A" 2>/dev/null || sudo mkfs.ext4 -F "$A"
  sudo mount "$A" "$M"
  for i in 1 2 3; do sudo bash ~/lab32/banc.sh "$M" "$fs"; done
  sudo umount "$M"
done
# ZFS : pool d'un disque, cache de données neutralisé pour le banc
sudo wipefs -a "$A"
sudo zpool create -o ashift=12 -O compression=off -O atime=off -O primarycache=metadata \
  -O recordsize=8K -m "$M" banc "$A"
for i in 1 2 3; do sudo bash ~/lab32/banc.sh "$M" zfs-8k; done
sudo zfs set recordsize=1M banc
for i in 1 2 3; do sudo bash ~/lab32/banc.sh "$M" zfs-1m; done
sudo zpool destroy banc
```

> [!NOTE]
> **Pourquoi**
>
> * `compression=off` sur ZFS : `fio` écrit par défaut des données
>   compressibles, que la compression rendrait artificiellement rapides ; les
>   autres systèmes de fichiers ne compressent pas.
> * `primarycache=metadata` : ZFS 2.2 accepte `O_DIRECT` sans le respecter ;
>   sans cela, la charge de lecture viendrait de l'ARC.
> * Deux `recordsize` pour ZFS : 8 Kio pour la base, 1 Mio pour la sauvegarde.
>   Un seul réglage pour les deux charges désavantagerait ZFS sur l'une d'elles,
>   et en production on aurait deux datasets.

**Étape 3 — `banc.md` (exemple de résultats sur le lab)**

```markdown
# Banc ext4 / XFS / Btrfs / ZFS — disque virtuel 3 Go, lab-db, 2026-11-09
Médiane de 3 passages de 60 s (écart max entre passages).
| FS | base : IOPS | base : p99 (ms) | sauvegarde : Mio/s |
|---|---|---|---|
| ext4 | 410 (±4 %) | 4,1 | 690 (±3 %) |
| XFS | 450 (±3 %) | 3,6 | 705 (±2 %) |
| Btrfs | 210 (±9 %) | 9,8 | 640 (±6 %) |
| ZFS (8K / 1M) | 330 (±6 %) | 5,2 | 600 (±5 %) |

Interprétation :
* base (fsync à chaque écriture) : XFS et ext4 n'ont qu'à écrire le bloc et
  une petite transaction de journal. Btrfs paie la copie sur écriture : chaque
  fsync met à jour l'arbre des sommes de contrôle et un journal d'arbre
  (log tree). ZFS passe par son journal d'intention (ZIL) : sans disque de
  journal séparé, il est sur le même disque, d'où une latence intermédiaire.
* sauvegarde (séquentiel 1 Mio) : tous saturent à peu près le disque virtuel ;
  les écarts restent dans le bruit, sauf ZFS sans cache de données.
```

**Étape 4 — Limites**

```markdown
## Limites de la mesure
* disque virtuel sur LVM thin, sur le même SSD que les autres VM : le bruit
  des voisins et le cache de l'hôte faussent les absolus ; seules les
  comparaisons relatives, prises au même moment, ont un sens ;
* un seul fil, une seule VM : rien sur le comportement en parallèle ;
* données aléatoires, sans compression : en conditions réelles, zstd peut
  inverser le classement de ZFS et Btrfs sur des données compressibles ;
* volume quasi vide : ni fragmentation, ni système de fichiers plein à 80 % ;
* 60 s : rien sur le comportement à long terme (préconditionnement, scrubs,
  instantanés qui s'accumulent).
```

> [!NOTE]
> **Pourquoi**
>
> La section des limites est ce qui distingue une mesure d'une publicité : elle
> dit au lecteur ce qu'il **ne doit pas** conclure. Ici, la conclusion honnête
> est « XFS et ext4 sont les plus rapides en écritures synchrones sur ce
> stockage ; le surcoût de ZFS reste modéré et s'achète des sommes de contrôle,
> des instantanés et la réplication ». La décision dépend de ce que l'on veut
> garantir, la mesure de ce qu'elle coûte.

---

## 32.7 Break & Fix

### <a id="bf32-1"></a>**[BF32.1](README.md#bf32-1)** — « J'ai supprimé 1,5 Go, et le disque est toujours plein »

**Démarche de diagnostic**

```bash
df -h /tank/exports; du -sh /tank/exports
zpool list tank                       # CAP proche de 100 %
zfs list -o space -r tank
#   NAME          AVAIL  USED  USEDSNAP  USEDDS …
#   tank/exports     0B  1.9G     1.4G    480M
zfs list -t snapshot -o name,used,refer,creation -r tank/exports
#   tank/exports@avant-nettoyage  1.4G  1.5G  Sun Nov  8 17:02 2026
zfs get -H -o value written@avant-nettoyage tank/exports
```

**Cause racine** : un instantané `tank/exports@avant-nettoyage`, pris
« par prudence » juste avant la suppression, référence encore tous les blocs
de l'export supprimé (1,4 Go en `USEDSNAP`). La suppression a retiré le
fichier de l'état courant, pas du pool. L'application a ensuite comblé le
reste, et ZFS refuse d'écrire au-delà de sa marge de sécurité.

**Correctif** : l'instantané contient peut-être la **seule** copie de
l'export. On ne le détruit qu'après l'avoir mis en sécurité ou obtenu l'accord
du propriétaire :

```bash
sudo zfs send tank/exports@avant-nettoyage | sudo zfs receive -u sauve/exports-archive
sudo zfs destroy tank/exports@avant-nettoyage
zfs list -o space tank/exports                # USEDSNAP 0, AVAIL revenu
```

(Si `sauve` est trop petit, on vérifie d'abord avec le propriétaire que
l'export n'est plus nécessaire.)

**Prévention** :

* des quotas par dataset (`quota` ou `refquota`) pour qu'un seul service ne
  puisse pas remplir le pool, et une réservation pour ceux qui ne doivent
  jamais manquer d'espace ;
* une politique d'instantanés avec rétention automatique (D32), plutôt que
  des instantanés manuels oubliés ;
* une alerte sur la capacité du pool (80 %) et sur `USEDSNAP` par dataset ;
* la consigne : « supprimer pour faire de la place » sur ZFS commence par
  `zfs list -o space`.

> [!NOTE]
> **Pourquoi**
>
> ZFS garde une marge (*slop space*, environ 3 % du pool) que les écritures
> ordinaires ne peuvent pas consommer, pour que les opérations de
> réparation (détruire un instantané, supprimer des fichiers) restent
> possibles sur un pool plein. Sur un système en copie sur écriture, même une
> suppression doit écrire de nouvelles métadonnées : sans cette marge, on ne
> pourrait plus rien supprimer. Un pool rempli au-delà de 80 % devient aussi
> nettement plus lent (allocation plus difficile).

---

### <a id="bf32-2"></a>**[BF32.2](README.md#bf32-2)** — « Le volume de fichiers ne se monte plus »

**Démarche de diagnostic**

```bash
sudo mount /srv/btrfs-bf
#   mount: /srv/btrfs-bf: wrong fs type, bad option, bad superblock on /dev/loop12, missing codepage
#   or helper program, or other error.
sudo dmesg | tail -4
#   BTRFS error (device loop12): devid 2 uuid 6a1c… is missing
#   BTRFS error (device loop12): failed to read the system array: -2
#   BTRFS error (device loop12): open_ctree failed
sudo btrfs filesystem show
#   Label: 'bf32'  uuid: …   Total devices 2 FS bytes used 212.0MiB
#     devid 1 size 1.00GiB used … path /dev/loop12
#     *** Some devices missing
grep btrfs-bf /etc/fstab
#   UUID=… /srv/btrfs-bf btrfs defaults 0 0     <- ni nofail ni délai : arrêt au démarrage
```

**Cause racine** : le volume est un miroir de deux disques, et le second
(devid 2) a disparu lors de l'« intervention ». Btrfs refuse un montage sans
tous ses disques sans accord explicite. La ligne `fstab`, sans `nofail`,
ferait échouer `local-fs.target` au démarrage : la machine s'arrêterait en
mode de secours pour un volume de données.

**Correctif**

```bash
sudo mount -o degraded /dev/loop12 /srv/btrfs-bf           # les données sont lisibles
truncate -s 1G /var/lib/lab32/bf-remplacant.img
R=$(sudo losetup -f --show /var/lib/lab32/bf-remplacant.img)
sudo btrfs replace start -B 2 "$R" /srv/btrfs-bf
sudo btrfs balance start -dconvert=raid1,soft -mconvert=raid1,soft /srv/btrfs-bf
sudo btrfs filesystem show /srv/btrfs-bf                   # 2 disques, plus de « missing »
sudo sed -i 's|\(/srv/btrfs-bf btrfs \)defaults|\1defaults,nofail,x-systemd.device-timeout=15s|' /etc/fstab
sudo systemctl daemon-reload
sudo umount /srv/btrfs-bf && sudo mount /srv/btrfs-bf      # montage normal
```

**Prévention** : `nofail` et un délai borné pour tout volume de données dans
`fstab` ; une alerte sur `btrfs device stats` et sur l'absence d'un disque
(`btrfs filesystem show` ou l'exportateur Prometheus) ; une procédure
d'intervention matérielle qui vérifie l'état du volume avant et après.

> [!NOTE]
> **Pourquoi**
>
> Le message de `mount` est générique : la vraie cause est **toujours** dans
> `dmesg`. Pour les volumes à plusieurs disques, `btrfs filesystem show`
> (sans argument) liste ce que le noyau a trouvé et signale les absents.
>
> On ne met pas `degraded` dans `fstab` : un volume qui se monterait seul sans
> redondance pourrait tourner des mois sur un seul disque. `nofail` laisse la
> machine démarrer, le volume restant démonté : la panne se voit (service
> dépendant en échec, alerte) au lieu d'être silencieuse.

---

### <a id="bf32-3"></a>**[BF32.3](README.md#bf32-3)** — « Le stockage du nœud se remplit tout seul »

**Démarche de diagnostic**

```bash
# nœud Proxmox
lvs -o lv_name,lv_size,data_percent pve | grep vm-9003     # le disque lab32-3 à ~85 %
# lab-db
df -h /srv/lab32/archives                                  # quelques Mo utilisés sur 3 Go
lsblk --discard "$(readlink -f "$A")"                       # DISC-MAX 1G : le disque accepte TRIM
findmnt -no OPTIONS /srv/lab32/archives                    # pas de discard
systemctl is-enabled fstrim.timer; systemctl list-timers fstrim.timer
#   disabled
sudo tune2fs -l "$A" | grep -i 'mount options'
journalctl -u fstrim --since -30d | tail -3                # dernier passage : jamais
```

**Cause racine** : 2,4 Go de données ont été écrites puis supprimées sur
`/srv/lab32/archives`. L'ext4 de l'invité sait que ces blocs sont libres,
mais personne ne l'a dit à l'hôte : le montage n'a pas l'option `discard`, et
le passage hebdomadaire de `fstrim.timer` a été désactivé. Le volume thin de
l'hôte garde donc les 2,4 Go alloués. Le disque virtuel, lui, transmet bien
les TRIM (`discard=on`, `DISC-MAX` non nul) : il suffit de les envoyer.

**Correctif**

```bash
sudo fstrim -v /srv/lab32/archives          # /srv/lab32/archives: 2.9 GiB (…) trimmed
sudo systemctl enable --now fstrim.timer
sudo fstrim -av                             # tous les systèmes de fichiers montés qui le permettent
# nœud : Data% du volume redescend
```

**Prévention** : `fstrim.timer` activé partout (c'est le défaut d'Ubuntu ; le
désactiver doit être un choix documenté), `discard=on` sur tous les disques
virtuels en allocation fine (gabarit Proxmox), `autotrim=on` sur les pools
ZFS des invités, et sur l'hôte une alerte sur le remplissage du pool thin
(QO32.7).

> [!NOTE]
> **Pourquoi**
>
> `fstrim` périodique plutôt que `discard` au montage : chaque suppression avec
> `discard` envoie une commande TRIM synchrone, qui peut ralentir les
> suppressions massives et, sur certains SSD, bloquer la file d'E/S ; un
> passage hebdomadaire regroupe tout pour un coût négligeable. Sur un
> hyperviseur dont les disques sont en allocation fine, l'écart entre ce que
> les invités croient utiliser et ce que l'hôte a alloué est une dette qui
> grossit en silence jusqu'au jour où le pool est plein et où **toutes** les VM
> s'arrêtent en même temps.

---

## 32.8 Défi du module

<a id="d32"></a>**[D32](README.md#d32) — Instantanés automatiques, restauration en libre-service, réplication**

*Livrable attendu : `instantanes.sh`, ses unités, la documentation utilisateur.*

```bash
#!/usr/bin/env bash
# instantanes.sh <dataset> [destination] — instantanés ZFS automatiques, rétention,
# réplication incrémentale (module 32, D32)
# Ne touche JAMAIS à un instantané dont le nom ne commence pas par « auto- ».
set -euo pipefail
SRC=${1:?dataset source, ex. tank/donnees}
DST=${2:-sauve/${SRC#*/}}
PREFIXE=auto-
VERROU=/run/lock/instantanes-${SRC//\//_}.lock
log() { logger -t instantanes -- "$*"; printf '%s %s\n' "$(date +%T)" "$*" >&2; }

exec 9>"$VERROU"
flock -n 9 || { log "déjà en cours pour $SRC"; exit 0; }

# --- 1. instantané récursif ---------------------------------------------------
NOM="$PREFIXE$(date +%Y%m%d-%H%M)"
zfs snapshot -r "$SRC@$NOM"
log "instantané $SRC@$NOM"

# --- 2. rétention : 4 quarts d'heure, 24 heures, 7 jours, 4 semaines ----------
# on garde, parmi les auto-, le plus récent de chaque tranche
mapfile -t TOUS < <(zfs list -H -t snapshot -o name -s creation -d 1 "$SRC" |
                    sed -n "s|^${SRC}@\(${PREFIXE}[0-9]\{8\}-[0-9]\{4\}\)$|\1|p")
declare -A GARDE=()
garde_tranche() {   # garde_tranche <format date> <nombre>
  local fmt=$1 n=$2 vu=() s cle
  for (( i=${#TOUS[@]}-1; i>=0; i-- )); do
    s=${TOUS[i]#"$PREFIXE"}
    cle=$(date -d "${s:0:8} ${s:9:2}:${s:11:2}" +"$fmt")
    if [[ ! " ${vu[*]} " == *" $cle "* ]]; then
      vu+=("$cle"); GARDE[${TOUS[i]}]=1
      [ "${#vu[@]}" -ge "$n" ] && break
    fi
  done
}
garde_tranche '%Y%m%d%H%M' 4      # chaque instantané : les 4 derniers quarts d'heure
garde_tranche '%Y%m%d%H'   24     # le plus récent de chaque heure
garde_tranche '%Y%m%d'     7      # … de chaque jour
garde_tranche '%G%V'       4      # … de chaque semaine ISO

# --- 3. réplication incrémentale ------------------------------------------------
# dernier instantané (de n'importe quel nom) présent des deux côtés, du plus récent au plus ancien
COMMUN=""
if zfs list -H "$DST" >/dev/null 2>&1; then
  mapfile -t DSTS < <(zfs list -H -t snapshot -o name -d 1 "$DST" | sed 's|.*@||')
  while read -r s; do
    if printf '%s\n' "${DSTS[@]}" | grep -qxF -- "$s"; then COMMUN=$s; break; fi
  done < <(zfs list -H -t snapshot -o name -S creation -d 1 "$SRC" | sed 's|.*@||')
  [ -n "$COMMUN" ] || { log "ERREUR : $DST existe sans instantané commun avec $SRC"; exit 1; }
  # -R -F : la destination reproduit la liste d'instantanés de la source
  # (ceux que la rétention a détruits à la source disparaissent aussi en face)
  zfs send -R -I "@$COMMUN" "$SRC@$NOM" | zfs receive -u -F "$DST"
  log "réplication incrémentale $COMMUN -> $NOM vers $DST"
else
  zfs send -R "$SRC@$NOM" | zfs receive -u "$DST"
  log "réplication complète $NOM vers $DST"
fi

# --- 4. rétention côté source (après la réplication : l'instantané commun survit) --
for s in "${TOUS[@]}"; do
  [ -n "${GARDE[$s]:-}" ] && continue
  [ "$s" = "$NOM" ] && continue
  zfs destroy -r "$SRC@$s" && log "rétention : $SRC@$s détruit"
done
```

```ini
# /etc/systemd/system/instantanes@.service
[Unit]
Description=Instantanés ZFS automatiques de %I
OnFailure=notifier@%n.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/instantanes.sh %I

# /etc/systemd/system/instantanes@.timer
[Unit]
Description=Instantanés de %I tous les quarts d'heure

[Timer]
OnCalendar=*:0/15
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl enable --now 'instantanes@tank-donnees.timer'   # %I = tank/donnees (le - devient /)
```

> [!NOTE]
> **Pourquoi**
>
> * **Préfixe `auto-`** : le script ne détruit que ce qu'il a créé. Les
>   instantanés manuels (« avant mise à jour ») échappent à la rétention ; c'est
>   à leur auteur de les supprimer, et c'est la leçon de BF32.1.
> * **Le dernier commun d'abord** : la réplication part du plus récent
>   instantané présent des deux côtés (quel que soit son nom : ceux de L32.3
>   servent de point de départ), et `-I` envoie tous les instantanés
>   intermédiaires, de sorte que la destination garde le même historique. Sans
>   instantané commun, le script s'arrête au lieu d'écraser la destination.
> * **Les destructions viennent après la réplication** : on ne détruit jamais
>   côté source l'instantané commun avant que le suivant soit arrivé.
> * **`-R -u -F` côté destination** : non monté, ramené de force au dernier
>   instantané commun s'il avait divergé (la destination est une copie, jamais
>   un lieu de travail), et, avec un flux `-R`, débarrassé des instantanés qui
>   n'existent plus à la source : la rétention se propage au passage suivant.
> * **`flock`** : un passage plus long que 15 minutes (premier envoi complet) ne
>   doit pas être doublé par le suivant.
> * Le nom d'instance `tank-donnees` utilise l'échappement systemd : `%I`
>   restitue `tank/donnees`.
>
> **sanoid/syncoid** font tout cela, en plus robuste (gestion des reprises,
> compression du flux, SSH) : c'est ce qu'on utilise en production. L'écrire
> une fois soi-même permet de savoir ce que ces outils garantissent.

Extrait de `restaurer-un-fichier.md` :

```markdown
# Retrouver une ancienne version d'un fichier

Chaque dossier partagé conserve automatiquement ses versions passées :
toutes les 15 minutes de la dernière heure, chaque heure du dernier jour,
chaque jour de la dernière semaine, chaque semaine du dernier mois.

1. Va dans le dossier caché `.zfs/snapshot/` à la racine du partage
   (il n'apparaît pas dans `ls -a`, tape son nom).
2. Chaque sous-dossier porte une date : `auto-20261109-1415` = le 9 novembre
   à 14 h 15. Il contient le partage tel qu'il était à cette heure-là.
3. Copie le fichier voulu à sa place : `cp .zfs/snapshot/auto-…/rapport.odt ./`

Tu ne peux PAS modifier ou supprimer une version passée (elles sont en
lecture seule), ni retrouver un fichier créé et supprimé entre deux versions.
Pour une restauration plus ancienne qu'un mois, demande à l'équipe
d'exploitation (copie sur le serveur de sauvegarde).
```

<!-- nav:début -->
---

[← Module 31](../31-tracage-ebpf-perf/corrige.md) · [Énoncé](README.md) · [Projet C →](../../projets/P3-astreinte/corrige.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
