<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Partie IV — Socle DevOps › **Module 21** · corrigé  
[← Module 20](../20-virtualisation-kvm/corrige.md) · [Énoncé](README.md) · [Module 22 →](../22-docker/corrige.md)

> [!TIP]
> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, pas avant. Chaque identifiant renvoie à son énoncé.
<!-- nav:fin -->

# Module 21 — Corrigé

## 21.3 Quiz — QCM

<a id="q21-1"></a>**[Q21.1](README.md#q21-1)** — *`--amend` qui ne change que le message : que deviennent le SHA du
commit et celui de son tree ?*

**Réponse : b)** le SHA du commit change, le tree reste `f1e0365…`.

```console
$ git log -1 --format='%h %t'          # commit, puis son tree
fb97836 f1e0365
$ git commit --amend -q -m "docs(runbook): procédure de rollback (bis)"
$ git log -1 --format='%h %t'
3566b05 f1e0365                        # SHA neuf (dépend de l'heure)
```

> [!NOTE]
> **Pourquoi**
>
> Un objet commit est un petit texte : `tree <sha>`, `parent <sha>`, `author`,
> `committer`, ligne vide, message. Son SHA-1 est le condensé de **ce texte**.
> Changer le message change le texte, donc le SHA. Le tree, lui, est un objet
> séparé qui ne dépend que du contenu des fichiers : il n'a aucune raison de
> changer. `--amend` ne « modifie » donc rien : il crée un **nouveau** commit
> avec le même tree et le même parent, puis déplace la branche dessus.
> L'ancien commit reste dans `.git/objects` et dans le reflog.

> [!WARNING]
> **Piège**
>
> C'est pour cela qu'un `--amend` sur un commit **déjà poussé** produit ensuite
> un `non-fast-forward` : le distant pointe sur l'ancien SHA, que ton
> historique ne contient plus. Règle : on n'amende que ce qui n'a pas quitté
> son poste.

---

<a id="q21-2"></a>**[Q21.2](README.md#q21-2)** — *`## main...origin/main [ahead 2, behind 3]`.*

**Réponse : a)** deux commits locaux non poussés, trois commits distants non
intégrés : les branches ont divergé.

> [!NOTE]
> **Pourquoi**
>
> `ahead` compte `origin/main..main` (ce que tu as en plus), `behind` compte
> `main..origin/main` (ce qui est arrivé sur le distant depuis ton dernier
> `fetch`). Les deux non nuls = **divergence** : un `push` sera rejeté, un
> `pull` devra fusionner ou rebaser. Ce chiffre ne dit rien de l'état réel du
> serveur : il compare à `origin/main`, la copie locale mise à jour par
> `fetch`. Sans `fetch` récent, il ment.

---

<a id="q21-3"></a>**[Q21.3](README.md#q21-3)** — *Après `git`* `add -p` *d'un seul hunk sur deux, quelles commandes montrent une partie de ta modification?*

**Réponses : a) et b)**

> [!NOTE]
> **Pourquoi**
>
> Le hunk accepté est dans l'index : `git diff --staged` (index ↔ HEAD) le
> montre. Le hunk refusé est resté dans le working directory : `git diff`
> (working dir ↔ index) le montre. `git diff HEAD~1 HEAD` et `git show`
> comparent deux **commits** : rien n'a encore été commité, ils affichent le
> commit précédent, pas ton travail. Retenir : trois zones, et `diff` compare
> toujours **deux** d'entre elles — la question est « lesquelles ? ».

---

<a id="q21-4"></a>**[Q21.4](README.md#q21-4)** — *`logs/` puis `!logs/.gitkeep`.*

**Réponse : b)** rien : impossible de ré-inclure un fichier dont le répertoire
parent est exclu.

```console
$ git check-ignore -v logs/.gitkeep
.gitignore:14:logs/ logs/.gitkeep
```

> [!NOTE]
> **Pourquoi**
>
> Pour des raisons de performance, quand un **répertoire** est exclu, Git ne le
> parcourt pas du tout : les règles `!` sur son contenu ne sont jamais
> évaluées (c'est écrit noir sur blanc dans `man gitignore`). Il faut exclure
> le **contenu** (`logs/*`), ce qui laisse Git entrer dans le répertoire, puis
> ré-inclure le fichier. Avec `logs/*` + `!logs/.gitkeep`, `check-ignore`
> répond bien `!logs/.gitkeep` pour le fichier et `logs/*` pour le reste.

---

<a id="q21-5"></a>**[Q21.5](README.md#q21-5)** — *`*.tfstate` ajouté au `.gitignore` alors que le fichier est
déjà suivi.*

**Réponse : b)** il apparaît toujours comme modifié.

> [!NOTE]
> **Pourquoi**
>
> `.gitignore` ne concerne que les fichiers **non suivis** : il décide ce que
> `git add` et `git status` proposent. Un fichier présent dans l'index est
> suivi, point ; Git continue de comparer son contenu à celui de l'index. Pour
> l'ignorer il faut d'abord le retirer de l'index sans le supprimer du disque :
> `git rm --cached terraform/terraform.tfstate`, commiter la suppression, et
> seulement alors la règle du `.gitignore` s'applique. Le fichier reste dans
> l'**historique** — s'il contient un mot de passe, voir Q21.8.

---

<a id="q21-6"></a>**[Q21.6](README.md#q21-6)** — *`git merge feature/x` sans commit de merge.*

**Réponse : b)** fast-forward.

> [!NOTE]
> **Pourquoi**
>
> Si `main` est un ancêtre direct de `feature/x`, il n'y a rien à
> « fusionner » : Git déplace simplement le pointeur `main` sur le commit de
> `feature/x`. Aucun nouveau commit, historique linéaire, et la branche
> disparaît du graphe comme si elle n'avait jamais existé. `--no-ff` force la
> création d'un commit de merge à deux parents : on garde la trace « ces
> 3 commits formaient une feature », ce qui permet `git revert -m 1` d'un
> coup et une lecture par `--first-parent`.

---

<a id="q21-7"></a>**[Q21.7](README.md#q21-7)** — *Marqueurs pendant un rebase.*

**Réponse : b)** `HEAD` est `main`, `994e070` est ton commit en cours de
rejeu.

> [!NOTE]
> **Pourquoi**
>
> Un rebase se déroule en HEAD **détaché** sur la branche cible : Git se place
> sur `main`, puis applique tes commits un par un comme des patchs. Au moment
> du conflit, « ours » (`HEAD`) est donc la base — `main` — et « theirs » est
> le patch en cours : ton commit. C'est l'inverse d'un merge, où `HEAD` est ta
> branche. Le libellé après `>>>>>>>` le confirme : `994e070 (feat(nginx): écoute en 443…)` est bien le commit d'alice. Résoudre « en gardant HEAD »
> pendant un rebase revient à **jeter son propre travail**.

> [!WARNING]
> **Piège**
>
> `git checkout --ours fichier` et `--theirs` suivent la même inversion.
> Dans le doute, `git status` dit `You are currently rebasing branch 'X' on
> 'Y'` : `HEAD` est `Y`.

---

<a id="q21-8"></a>**[Q21.8](README.md#q21-8)** — *Mot de passe commité, puis `git rm .env` et push.*

**Réponses : a) et c)**

```console
$ git show 1557f83:.env
# conf locale de bob — NE PAS COMMITER
DB_HOST=10.10.10.12
DB_USER=factura
DB_PASSWORD=S3cr3t-Factura-2026!
API_KEY=AKIAIOSFODNN7EXAMPLE
```

> [!NOTE]
> **Pourquoi**
>
> Le commit qui a ajouté `.env` est immuable et référencé par tout commit
> suivant : le blob reste dans le dépôt, sur le serveur et dans chaque clone,
> et `git show <sha>:.env` le lit sans effort. `gc` ne supprime que les objets
> **injoignables** : ici il est joignable depuis `main`. Et quand bien même on
> purgerait l'historique (L21.4), le secret a été **lu** potentiellement par
> n'importe qui pendant l'intervalle : il est compromis, la rotation est
> obligatoire, la purge n'est que de l'hygiène.

---

<a id="q21-9"></a>**[Q21.9](README.md#q21-9)** — *Annuler le dernier commit poussé sur une branche partagée.*

**Réponse : b)** `git revert HEAD` puis `git push`.

> [!NOTE]
> **Pourquoi**
>
> `revert` crée un **nouveau** commit dont le diff est l'inverse : l'historique
> avance, personne n'est perturbé, les clones font un `pull` fast-forward.
> `reset --hard` + `push --force` réécrit une branche que d'autres ont
> déjà tirée : leur prochain `pull` fusionne l'ancien historique avec le
> nouveau et ressuscite le commit « annulé ». `checkout HEAD~1` ne fait que
> détacher `HEAD` ; `restore --source` remet les fichiers mais ne commite rien.

---

<a id="q21-10"></a>**[Q21.10](README.md#q21-10)** — *`reset --soft HEAD~2` puis `commit`.*

**Réponse : b)** les changements des deux commits sont réunis dans un seul
nouveau commit.

> [!NOTE]
> **Pourquoi**
>
> `--soft` ne déplace **que** la branche (et `HEAD`) : index et working
> directory restent tels quels, c'est-à-dire au contenu de l'ancien `HEAD`.
> Par rapport au nouveau `HEAD` (deux commits en arrière), l'index contient
> donc déjà toutes les modifications des deux commits, prêtes à être
> commitées. C'est le « squash manuel » le plus rapide, et rien n'est perdu :
> les deux anciens commits restent dans le reflog.

---

<a id="q21-11"></a>**[Q21.11](README.md#q21-11)** — *Deux commits en HEAD détaché, puis `switch main`.*

**Réponse : c)** dans la base d'objets, atteignables par `git reflog`.

```console
$ git switch main
Warning: you are leaving 2 commits behind, not connected to
any of your branches:

  37969cb docs: note 2
  37118e1 docs: note d'urgence

If you want to keep them by creating a new branch, this may be a good time
to do so with:

 git branch <new-branch-name> 37969cb
```

> [!NOTE]
> **Pourquoi**
>
> Un commit n'a pas besoin de branche pour exister : il est écrit dans
> `.git/objects` au moment du `commit`. Ce qui manque, c'est une
> **référence** qui le rende joignable ; sans elle, `git log` ne le voit pas
> et `gc` finira par le supprimer (après le délai `gc.reflogExpireUnreachable`,
> 30 jours). Le reflog de `HEAD` note chaque déplacement, y compris
> `commit: docs: note 2` : `git branch sauvetage HEAD@{1}` suffit.
> Git prévient d'ailleurs au moment du `switch` — message que l'on ne lit
> jamais.

---

<a id="q21-12"></a>**[Q21.12](README.md#q21-12)** — *Push rejeté `non-fast-forward`.*

**Réponse : b)** `git pull --rebase` puis `git push`.

> [!NOTE]
> **Pourquoi**
>
> Le serveur refuse parce que `origin/main` contient des commits qui ne sont
> pas des ancêtres de ton `main` : accepter écraserait le travail de
> quelqu'un. La seule issue est de **rapatrier** ces commits et de mettre les
> tiens par-dessus (rebase) ou à côté (merge), puis de pousser un historique
> qui contient les deux. `--force` détruit, recloner perd tes commits
> locaux (sauf à les sauver avant), et supprimer la branche distante est
> la même destruction en deux étapes.

---

<a id="q21-13"></a>**[Q21.13](README.md#q21-13)** — *`--force` vs `--force-with-lease`.*

**Réponse : b)**

> [!NOTE]
> **Pourquoi**
>
> `--force-with-lease` envoie au serveur : « remplace `refs/heads/x` par
> mon SHA **à condition** qu'il vaille encore ce que mon `origin/x` dit ».
> Si un collègue a poussé entre-temps, le serveur refuse. C'est le seul push
> forcé acceptable, réservé à **ta** branche de feature après un rebase.
> Attention : un `git fetch` juste avant met à jour `origin/x` et fait
> disparaître la protection — ne pas enchaîner mécaniquement `fetch` puis
> `--force-with-lease`.

---

<a id="q21-14"></a>**[Q21.14](README.md#q21-14)** — *`cat-file -t v0.9.0` → `commit`, `v1.0.0` → `tag`.*

**Réponse : b)**

```console
$ git cat-file -p v1.0.0
object be7970d96a2ecaa7c06f2a1a5a33fe5cd6b87d40
type commit
tag v1.0.0
tagger mathieu <mathieu@lab.local> 1781525700 +0200

Version 1.0.0 — première mise en production
```

> [!NOTE]
> **Pourquoi**
>
> Un tag léger est une simple ligne dans `refs/tags/` qui contient le SHA d'un
> commit : `cat-file -t` renvoie donc le type de ce commit. Un tag annoté
> (`-a`, `-s`) est un **objet** à part entière, avec tagueur, date, message,
> signature éventuelle ; `git rev-parse v1.0.0` donne son SHA propre
> (`be1373…`) et `v1.0.0^{commit}` celui du commit visé. Pour les versions on
> veut l'annoté : `git describe` ne voit que lui par défaut, et il est
> signable.

---

<a id="q21-15"></a>**[Q21.15](README.md#q21-15)** — *8 commits entre `good` et `bad`, combien d'essais bisect ?*

**Réponse : c)** 3.

> [!NOTE]
> **Pourquoi**
>
> Bisect divise l'intervalle par deux à chaque test : ⌈log₂(8)⌉ = 3.
> Git l'annonce lui-même dès `bisect start` : `Bisecting: 3 revisions left to test after this
> (roughly 2 steps)` (E21.16, 7 commits). Avec 1 000 commits, dix essais
> suffisent, ce qui rend `bisect run` rentable dès que le test dure moins
> de quelques minutes.

---

<a id="q21-16"></a>**[Q21.16](README.md#q21-16)** — *`git clean -fdx`.*

**Réponses : a) et c)**

> [!NOTE]
> **Pourquoi**
>
> `clean` ne touche qu'aux fichiers **non suivis** (`b` et `d` sont hors
> sujet). `-d` inclut les répertoires, `-x` inclut aussi les fichiers
> **ignorés** — c'est précisément ce qui fait sa dangerosité sur un dépôt
> Terraform : `terraform.tfstate` est ignoré, donc il part, et avec lui l'état
> de ton infrastructure. D'où la règle : `git clean -ndx` d'abord (`n` =
> dry-run), on lit, on décide.

---

<a id="q21-17"></a>**[Q21.17](README.md#q21-17)** — *Workflow pour un dépôt Ansible déployé plusieurs fois par jour.*

**Réponse : b)**

> [!NOTE]
> **Pourquoi**
>
> De l'infra, on ne « release » pas des versions parallèles maintenues des
> mois : il n'y a qu'un état voulu, celui de `main`. git-flow ajoute des
> branches (`develop`, `release/*`) dont la seule conséquence est de retarder
> l'intégration et de multiplier les conflits. Trunk-based (branches de
> quelques heures, CI, feature flags) ou GitHub flow (branche → PR → merge
> → déploiement) donnent un `main` toujours déployable et une revue par
> changement. Le tag marque ce qui a été déployé.

---

<a id="q21-18"></a>**[Q21.18](README.md#q21-18)** — *Clé SSH privée commitée : après `filter-repo` et push forcé,
que manque-t-il ?*

**Réponses : a) et b)**

> [!NOTE]
> **Pourquoi**
>
> La clé a été lisible par toute personne ayant accès au dépôt : elle est
> compromise, on la révoque (`authorized_keys`, forge, bastion) et on en
> génère une autre — c'est la seule action qui **ferme** la faille. Ensuite,
> chaque clone existant contient encore les anciens objets ; un `git pull`
> depuis l'un d'eux fusionnerait l'ancien historique dans le nouveau et
> repousserait la clé. Tout le monde re-clone, et on vérifie côté serveur
> avec `git grep` sur `rev-list --all`.

---

## 21.4 Quiz — questions ouvertes

<a id="qo21-1"></a>**[QO21.1](README.md#qo21-1)** — *Pourquoi un commit est immuable ; ce que font vraiment
`--amend`, `rebase`, `filter-repo` ; pourquoi le reflog sauve.*

**Réponse attendue :**

Un objet commit est un texte : `tree`, `parent(s)`, `author`, `committer`,
message. Son identifiant est le SHA-1 de ce texte (Git 2.43 gère aussi
SHA-256, même principe). Le tree est lui-même identifié par le condensé de
son listing, qui contient les SHA des blobs et des sous-trees. Changer
n'importe quel octet — un caractère de fichier, une date, un message, un
parent — produit un autre condensé, donc un **autre objet**. Un objet
existant n'est jamais modifié : il est adressé par son contenu.

Conséquences :

* `--amend` crée un nouveau commit (nouveau message ou nouveau tree, même
  parent) et déplace la branche dessus ; l'ancien reste dans `.git/objects`.
* `rebase` recrée **chaque** commit rejoué (nouveau parent → nouveau SHA),
  même si le patch est identique ; d'où `[ahead N, behind N]` après.
* `filter-repo` recrée tous les commits **postérieurs** au premier commit
  touché ; les commits antérieurs gardent leur SHA (dans L21.4, les six
  premiers commits ne changent pas).

Le reflog (`.git/logs/HEAD`, `.git/logs/refs/heads/*`) enregistre chaque
valeur successive de `HEAD` et des branches, indépendamment de la
joignabilité. Tant que l'entrée existe (90 jours pour les commits
joignables, 30 pour les autres — `gc.reflogExpire*`), l'ancien commit est
protégé du `gc` et `git reset --hard HEAD@{n}` ou `git branch x HEAD@{n}`
le ramène. Le reflog est **local** : il ne se pousse pas, un clone frais n'en
a pas.

> [!NOTE]
> **Pourquoi**
>
> C'est le point qui distingue Git d'un système « fichiers + numéros de
> version » : l'intégrité est structurelle. Un serveur ne peut pas altérer un
> commit sans que tous les SHA en aval changent, un tag signé fige donc tout
> l'historique qui le précède. En entretien, l'erreur classique est de dire
> « rebase modifie les commits » : non, il en fabrique de nouveaux, et c'est
> exactement pourquoi il ne faut pas rebaser ce qui est partagé.

---

<a id="qo21-2"></a>**[QO21.2](README.md#qo21-2)** — *Merge ou rebase pour intégrer une feature ?*

**Réponse attendue :**

Les critères :

* **Historique partagé ?** Rebaser réécrit ; si d'autres ont tiré la
  branche, chacun se retrouve avec des doublons. Rebase = branches
  **personnelles** uniquement.
* **Lisibilité** : rebase donne un historique linéaire, où chaque commit
  s'applique proprement sur le précédent ; merge conserve la chronologie
  réelle et la topologie (« ces 4 commits vont ensemble »).
* **Bisect** : un historique linéaire de commits atomiques se bisecte
  parfaitement ; un graphe de merges avec des commits intermédiaires cassés
  (`wip`) donne des « skip » en série.
* **Revue** : la revue se fait sur une branche **rebasée** (diff propre
  contre `main`, conflits déjà résolus par l'auteur, pas par l'intégrateur).
* **Rollback** : un merge `--no-ff` se revert d'un coup (`revert -m 1`) ;
  une feature rebasée puis fast-forwardée demande de reverter N commits.

Règle pour une équipe infra : **rebase avant, merge `--no-ff` après**.
L'auteur rebase sa branche sur `main` (interactif : squash des `wip`,
messages conventionnels), pousse avec `--force-with-lease`, ouvre la MR ;
l'intégration se fait par un merge commit (ou « rebase then merge » de la
forge) pour garder la trace de la feature et permettre un revert atomique.
`main` reste protégée : jamais de push direct.

> [!NOTE]
> **Pourquoi**
>
> Chaque approche seule a un défaut rédhibitoire : « merge partout » donne le
> graphe illisible où `git log --oneline` est à moitié composé de `Merge
> branch 'main' into feature`, « rebase partout » (fast-forward only) perd la
> notion de feature et complique le revert. La combinaison donne un
> `--first-parent` lisible (une ligne par feature) et un détail conservé.

---

<a id="qo21-3"></a>**[QO21.3](README.md#qo21-3)** — *`reset --soft/--mixed/--hard` : effets, usages, interdit.*

**Réponse attendue :**

| Mode | Branche/HEAD | Index | Working dir |
|---|---|---|---|
| `--soft X` | → X | intact | intact |
| `--mixed X` | → X | = X | intact |
| `--hard X` | → X | = X | = X |

Usages : `--soft` pour regrouper N commits en un ; `--mixed` pour
« dé-stager » et refaire le découpage ; `--hard` pour jeter du travail et
revenir à un état connu.

`--soft` : tout ce qui différencie l'ancien HEAD de X reste **indexé** ;
un `commit` refait un commit unique. `--mixed` (défaut) : les changements
restent sur disque mais plus dans l'index ; `git reset` sans argument
(`X = HEAD`) sert à annuler un `git add -A` trop large. `--hard` :
l'index et les fichiers suivis reviennent à X ; les modifications non
commitées sont **perdues** (elles ne sont dans aucun objet, le reflog ne
les connaît pas). Les fichiers non suivis ne sont jamais touchés.

Interdit : `reset` d'une branche **déjà poussée** et partagée, parce qu'il
faudrait ensuite un push forcé qui réécrit l'histoire des autres. On
utilise `revert` (commit inverse) ; pour « défaire » un merge partagé,
`git revert -m 1 <merge>`.

> [!NOTE]
> **Pourquoi**
>
> La question cache une seconde question : « qu'est-ce que le reflog
> sauve ? ». Réponse : tout ce qui a été **commité** (soft/mixed/hard sur des
> commits existants se rattrapent avec `reset --hard HEAD@{1}`), rien de ce
> qui ne l'a jamais été. Un `--hard` avec des modifications non commitées
> est irréversible ; d'où le réflexe `git stash` avant.

---

<a id="qo21-4"></a>**[QO21.4](README.md#qo21-4)** — *Clé API poussée il y a trois jours : procédure et ordre.*

**Réponse attendue :**

1. **Rotation immédiate** de la clé (révocation chez le fournisseur,
   nouvelle clé distribuée par le canal prévu : coffre, variable CI
   masquée). C'est l'étape qui met fin à l'exposition. Trois jours sur un
   dépôt accessible, c'est trois jours de fuite potentielle : on considère
   la clé comme volée.
2. Prévenir l'équipe : gel des push, chacun note ses commits locaux non
   poussés (`git log origin/main..`), et se prépare à re-cloner.
3. Purge dans un clone `--mirror` frais :
   `git filter-repo --invert-paths --path terraform/terraform.tfvars`, ou
   `--replace-text` si le fichier doit rester mais pas la valeur. Vérifier
   avec `git grep <clé> $(git rev-list --all)`.
4. `git push --mirror` (forcé par nature) vers le serveur ; sur le serveur,
   `reflog expire --expire=now - -all` et `gc --prune=now` pour supprimer
   physiquement les anciens objets. Sur une forge, demander en plus la
   purge des caches/PR/forks (GitHub a une procédure dédiée : les commits
   restent accessibles par SHA sinon).
5. Tout le monde re-clone et re-applique ses commits locaux
   (`cherry-pick` ou `format-patch`/`am`).
6. Prévention : `.gitignore` (`*.tfvars` sensibles, `.env`), hook
   `pre-commit` avec `gitleaks`, scan côté CI, secrets injectés par le
   pipeline et jamais lus dans le dépôt.

À « on n'a qu'à supprimer le fichier » : le commit qui l'a ajouté reste
dans l'historique, `git show <sha>:fichier` le lit, et de toute façon la
clé a déjà été exposée — supprimer sans tourner ne protège de rien.

> [!NOTE]
> **Pourquoi**
>
> L'ordre compte parce que chaque étape ferme une porte différente : la
> rotation ferme l'**usage** de la clé ; la purge ferme la **lecture** future
> depuis le dépôt ; le re-clone empêche la **réintroduction** par un vieux
> clone ; la prévention ferme la **récidive**. Inverser rotation et purge,
> c'est passer une heure à nettoyer pendant que la clé est utilisable.

---

<a id="qo21-5"></a>**[QO21.5](README.md#qo21-5)** — *Push rejeté non-fast-forward : explication et pourquoi pas
`--force`.*

**Réponse attendue :**

État : `origin/main` (côté serveur) pointe sur un commit C3 que ton clone
ne connaît pas (ou connaît sans l'avoir dans `main`) ; ton `main` pointe
sur L2 dont l'ancêtre commun avec C3 est C1. Le serveur ne peut pas
déplacer `refs/heads/main` de C3 à L2 par simple avance de pointeur :
C3 n'est pas un ancêtre de L2, il serait **oublié**. D'où le refus. Le
message dit `(fetch first)` si tu n'as même pas C3 localement,
`(non-fast-forward)` si tu l'as dans `origin/main`.

Deux intégrations correctes :

* `git pull --rebase` : rejoue L1, L2 par-dessus C3, historique linéaire,
  nouveaux SHA pour tes commits (non poussés : sans conséquence) ;
* `git pull --no-rebase` (ou `fetch` + `merge origin/main`) : commit de
  merge à deux parents, chronologie conservée.

Puis `git push`, qui devient un fast-forward.

`--force` remplace C3 par L2 : le commit du collègue disparaît du serveur
(il ne reste que dans son clone et le reflog du serveur, si `receive.*`
ne l'interdit pas). Le seul cas légitime : **ta** branche de feature que tu
viens de rebaser, avec `--force-with-lease` qui refuse si quelqu'un a poussé
dessus entre-temps — et jamais sur `main`, que la forge doit protéger.

> [!NOTE]
> **Pourquoi**
>
> L'expression « fast-forward » est littérale : avance rapide du pointeur.
> Le serveur applique une règle simple — la nouvelle valeur doit descendre
> de l'ancienne — et cette règle est ce qui rend un dépôt partagé sûr sans
> verrou. Comprendre ça évite 90 % des « j'ai fait un force parce que Git me
> bloquait ».

---

<a id="qo21-6"></a>**[QO21.6](README.md#qo21-6)** — *`fetch` vs `pull`, `--rebase` ou non, réglage recommandé.*

**Réponse attendue :**

`fetch` télécharge les objets et met à jour `refs/remotes/origin/*` ; il
ne touche ni à tes branches ni à tes fichiers : on peut le lancer n'importe
quand, puis **regarder** (`status -sb`, `log main..origin/main`,
`diff main origin/main`) avant de décider. `pull` = `fetch` + intégration
immédiate dans la branche courante : `merge` par défaut historique,
`rebase` avec `--rebase` ou `pull.rebase=true`.

Sans `--rebase`, un `pull` sur une branche qui a des commits locaux crée un
commit `Merge branch 'main' of …` : bruit inutile, historique en zigzag,
et le commit de merge contient parfois des résolutions de conflit
invisibles en revue. Avec `--rebase`, tes commits locaux sont rejoués sur
`origin/main` : linéaire, et tu résous les conflits commit par commit.

Depuis Git 2.33.1 (simple avertissement depuis 2.27), si `pull.rebase` n'est pas défini et que les branches ont
divergé, `pull` refuse (`Need to specify how to reconcile divergent
branches`) : Git ne veut plus choisir à ta place. Avec `pull.ff=only`,
il refuse aussi dès qu'un fast-forward est impossible (`Not possible to
fast-forward, aborting`) — c'est BF21.3.

Recommandation : `git config --global pull.rebase true` et l'habitude
`fetch` d'abord ; `pull.ff only` seulement sur les machines de déploiement
qui ne doivent jamais avoir de commits locaux (là, un refus est un signal
utile).

> [!NOTE]
> **Pourquoi**
>
> `pull` est la commande la plus dangereuse pour un débutant parce qu'elle
> combine deux actions, dont une modifie l'historique local, sans étape de
> lecture. Séparer `fetch` et l'intégration transforme une surprise en
> décision.

---

<a id="qo21-7"></a>**[QO21.7](README.md#qo21-7)** — *`.gitignore`, `.git/info/exclude`, `core.excludesFile` ; les
deux raisons pour lesquelles un fichier refuse de s'ignorer.*

**Réponse attendue :**

| Fichier | Portée | Versionné | Contenu typique |
|---|---|---|---|
| `.gitignore` (par répertoire) | le projet | oui | artefacts du projet : `.terraform/`, `*.tfstate`, `*.retry` |
| `.git/info/exclude` | ce clone | non | un brouillon local propre à ce dépôt |
| `core.excludesFile` | tous tes dépôts | non | ton éditeur/OS : `*.swp`, `.idea/`, `.DS_Store` |

La règle : ce qui dépend du **projet** va dans le `.gitignore` versionné ;
ce qui dépend de **ta machine** n'a rien à y faire (le `.gitignore` d'un
projet Ansible qui liste `.vscode/` et `.idea/` trahit que personne n'a
configuré `core.excludesFile`).

Un fichier « refuse » de s'ignorer dans deux cas : (1) il est **déjà
suivi** — `.gitignore` ne s'applique qu'aux non suivis, il faut `git rm
--cached` ; (2) la règle est mal écrite — répertoire parent exclu avec
tentative de `!` sur un enfant, patron ancré (`/logs` ne matche pas
`terraform/logs`), ou règle plus spécifique après. `git check-ignore -v
chemin` répond « quelle ligne de quel fichier » ou rien (rc 1) : c'est la
commande qui tranche, avant toute hypothèse.

> [!NOTE]
> **Pourquoi**
>
> Un `.gitignore` est évalué de haut en bas, dernière règle gagnante, et par
> répertoire (un `.gitignore` dans `terraform/` s'applique relativement à
> lui). Sans `check-ignore -v`, on passe une heure à « essayer des patrons » ;
> avec, trente secondes.

---

<a id="qo21-8"></a>**[QO21.8](README.md#qo21-8)** — *`etckeeper` sur les VM du lab.*

**Réponse attendue :**

Ce qu'il apporte : `/etc` devient un dépôt Git ; un commit automatique
avant et après chaque `apt` (hook dans `/etc/apt/apt.conf.d/05etckeeper`)
et un commit quotidien par timer. En incident : `sudo etckeeper vcs log
--stat` montre **qui a changé quoi et quand** dans `/etc` (« depuis quand
`sshd_config` a-t-il `PasswordAuthentication yes` ? »), `git diff` entre
deux dates donne la réponse en une commande, et `git show` permet de
restaurer un fichier. C'est la première chose à regarder quand « rien n'a
changé » et que ça ne marche plus.

Limites : `/etc` contient des secrets (`/etc/shadow`, clés
`/etc/ssl/private`, `sudoers`) — le dépôt hérite des droits de `/etc/.git`
(root, 700) et ne doit **jamais** être poussé vers une forge sans filtrage
(`/etc/.gitignore` géré par etckeeper n' exclut que des fichiers générés — `ld.so.cache`, `mtab`,
`*~`… — pas `shadow` ni les clés) ; Git ne stocke pas les propriétaires/droits
nativement, etckeeper les enregistre dans `.etckeeper` (un script de
`chmod`/`chown`) ; il ne remplace pas la gestion de configuration : il
constate, Ansible prescrit.

Articulation avec `apt` : `etckeeper pre-install` commite l'état avant
l'installation, `post-install` commite les changements apportés par les
paquets avec un message qui liste les paquets. Un `apt upgrade` produit
donc un commit lisible ; les modifications manuelles apparaissent au
prochain commit quotidien ou à `etckeeper commit "raison"`.

> [!NOTE]
> **Pourquoi**
>
> Le mécanisme est celui de tout le module appliqué à un répertoire système :
> un tree par état, un commit par changement, `diff` entre deux commits. Le
> bénéfice principal n'est pas la restauration (Ansible fait mieux) mais
> l'**attribution** : « ce changement a eu lieu mardi à 15 h 02, pendant un
> `apt upgrade` ».

---

<a id="qo21-9"></a>**[QO21.9](README.md#qo21-9)** — *`HEAD detached at 4a34e42` : causes, sauvetage, retour.*

**Réponse attendue :**

Trois causes courantes : (1) `git checkout <sha|tag>` ou `switch --detach`
pour reproduire une version (rollback selon le runbook, inspection) et
oubli de revenir ; (2) un `rebase` ou `bisect` en cours — Git travaille en
HEAD détaché et le message le dit (`interactive rebase in progress`,
`You are currently bisecting`) ; (3) `checkout origin/main` (une branche de
suivi n'est pas une branche locale : Git détache).

Démarche : `git status` (rebase/bisect en cours ? → `--continue`,
`--abort` ou `bisect reset`), puis `git log --oneline -3` pour voir si des
commits ont été faits **depuis** le détachement (ils n'appartiennent à
aucune branche). S'il y en a : `git branch sauvetage` (crée une branche sur
HEAD), puis `git switch main` et `merge`/`cherry-pick` depuis `sauvetage`.
S'il n'y en a pas : `git switch main` directement. Si on est déjà revenu
sur `main` en laissant les commits derrière : `git reflog`, repérer les
lignes `commit:` entre le `checkout: moving from main to …` et le
`checkout: moving from … to main`, et `git branch sauvetage <sha>`.

> [!NOTE]
> **Pourquoi**
>
> Le HEAD détaché n'est pas une erreur : c'est l'état normal quand `HEAD`
> pointe un commit plutôt qu'une branche. Le danger est uniquement de
> commiter dedans puis de partir, parce qu'aucune référence ne suit ces
> commits. Git prévient (`Warning: you are leaving N commits behind`) ; le
> réflexe à acquérir est « commit en détaché ⇒ `git branch` avant de bouger ».

---

## 21.5 Exercices guidés

<a id="e21-1"></a>**[E21.1](README.md#e21-1)** — *Configuration globale, alias, `--show-origin`, `user.name` en
double, `core.autocrlf` sous Windows.*

```bash
git config --global user.name  "Mathieu Teule"
git config --global user.email mathieu@lab.local
git config --global init.defaultBranch main
git config --global pull.rebase true
git config --global push.default simple
git config --global fetch.prune true
git config --global alias.lg "log --oneline --graph --all --decorate"
git config --global alias.st "status -sb"
git config --list --show-origin
```

```console
file:/home/mathieu/.gitconfig   user.name=Mathieu Teule
file:/home/mathieu/.gitconfig   user.email=mathieu@lab.local
file:/home/mathieu/.gitconfig   init.defaultbranch=main
file:/home/mathieu/.gitconfig   pull.rebase=true
file:/home/mathieu/.gitconfig   push.default=simple
file:/home/mathieu/.gitconfig   alias.lg=log --oneline --graph --all --decorate
file:.git/config        core.repositoryformatversion=0
file:.git/config        remote.origin.url=/home/mathieu/lab21/remote/…
file:.git/config        branch.main.remote=origin
file:.git/config        branch.main.merge=refs/heads/main
file:.git/config        user.name=mathieu
file:.git/config        user.email=mathieu@lab.local
```

`user.name` apparaît deux fois parce que `setup_M21.sh` a posé une valeur
**locale** (`git config user.name mathieu` dans `.git/config`) pour garantir
des SHA identiques chez tout le monde. La valeur locale gagne : dans ce
dépôt, tes commits seront signés `mathieu`, pas `Mathieu Teule`.

Windows : `core.autocrlf=true` (CRLF à l'extraction, LF dans le dépôt) ;
Linux/macOS : `input` (jamais de conversion à l'extraction, LF à l'entrée).
Mais le dépôt contient `.gitattributes` avec `* text=auto eol=lf` :
l'attribut **prime** sur `core.autocrlf` et impose LF partout, y compris à
l'extraction sous Windows. C'est la bonne approche : la règle est dans le
dépôt, pas dans la configuration de chacun.

> [!NOTE]
> **Pourquoi**
>
> Trois niveaux, lus dans l'ordre système → global → local, **dernier
> gagnant**. `--show-origin` est la seule commande qui explique une valeur
> surprenante (« mais j'ai mis `pull.rebase=true` ! » — oui, et
> `.git/config` dit `false`). `push.default=simple` pousse la branche
> courante vers sa branche amont si elle porte le **même nom**, et refuse
> sinon : c'est la protection contre le push accidentel de `main` vers
> `feature/x`. `fetch.prune` supprime les `origin/*` dont la branche distante
> a disparu, sinon `git lg` affiche des branches fantômes pendant des mois.

---

<a id="e21-2"></a>**[E21.2](README.md#e21-2)** — *Objets : HEAD, tree, sous-arbre `bin`, blob de README, tag.*

```console
$ git cat-file -t HEAD
commit
$ git cat-file -p HEAD
tree f1e0365a12892d755f379928ba6b5fa7f8d021f4
parent a6736e7a10c5b0ee9c96055dfc54eebe465f36a5
author mathieu <mathieu@lab.local> 1782892800 +0200
committer mathieu <mathieu@lab.local> 1782892800 +0200

docs(runbook): procédure de rollback
$ git cat-file -p HEAD^{tree}
100644 blob aab410065ed78dc286b0723777628fa734c64538	.gitattributes
100644 blob 8263e6028bef039c1a7b63efaf8660f7a0376c1c	.gitignore
100644 blob c075bfe50ae058fa9deb83ea83bcfe91e3da76e2	CHANGELOG.md
100644 blob ac05ef18ab9271fd36e2df7a9330beac4b4c4758	README.md
040000 tree 5915be3997f00e69e615eda04d90ca58eb4e4d89	ansible
040000 tree 5c9fa50eb897c75632ea76cc85a4c8bedb23fc95	bin
040000 tree abe85bec47c1af26f7a72bff64aa6a23f39b437b	docs
040000 tree 70f66d47a021dff3ba5936a958a58edb48be55da	terraform
$ git cat-file -p HEAD:bin
100755 blob 279e69930cf2592af8c0d1d37549ac73b005728f	deploy.sh
100755 blob d958d91e678413903984f6e0721909624ec86356	healthcheck.sh
$ git rev-parse HEAD:README.md ; git hash-object README.md
ac05ef18ab9271fd36e2df7a9330beac4b4c4758
ac05ef18ab9271fd36e2df7a9330beac4b4c4758
$ git rev-parse v1.0.0 v1.0.0^{commit}
be137369d5ed9b3056fcc39d2ba60da6578859a9
be7970d96a2ecaa7c06f2a1a5a33fe5cd6b87d40
```

> [!NOTE]
> **Pourquoi**
>
> Le tree ne contient que des **noms + modes + SHA** : le contenu est dans les
> blobs, et un blob ne connaît pas son nom (renommer un fichier ne crée
> aucun blob). `hash-object` calcule `sha1("blob <taille>\0<contenu>")` : le
> même contenu donne le même SHA partout, dans tous les dépôts du monde —
> c'est ce qui rend `fetch` incrémental et les renommages détectables.
> Le mode `100755` est le seul bit de droits que Git stocke (exécutable ou
> non) : pas de propriétaire, pas de date. `v1.0.0` (l'objet tag, `be1373…`)
> et `v1.0.0^{commit}` (le commit visé, `be7970d`) diffèrent : c'est la preuve
> qu'un tag annoté est un objet à part.

---

<a id="e21-3"></a>**[E21.3](README.md#e21-3)** — *Cinq questions, cinq `git log`.*

```console
$ git log --oneline -S'worker_connections 4096'                  # (a)
4056c82 fix(nginx): worker_connections 1024 -> 4096
$ git log --oneline --author=alice --since=2026-06-20 \
    --until=2026-07-01 main                                        # (b)
a6736e7 feat(nginx): en-têtes de sécurité HSTS et nosniff
0a6f3ae docs: changelog 1.0.0
$ git log --oneline --all -- .env                                  # (c)
53340da fix: retire .env du dépôt et l'ignore
1557f83 chore: ajoute la conf locale de dev
$ git shortlog -sn --all                                           # (d)
    10	alice
     9	mathieu
     6	bob
$ git log --oneline --graph --all --decorate                       # (e)
```

> [!NOTE]
> **Pourquoi**
>
> `-S` (pickaxe) ne cherche pas dans les messages : il ne garde que les commits
> où le **nombre d'occurrences** de la chaîne change — donc le commit qui
> l'introduit ou la retire, pas ceux qui déplacent la ligne. `--since/--until`
> acceptent dates et expressions (`"2 weeks ago"`). `-- .env` après `--`
> restreint aux commits touchant ce chemin ; `--all` est indispensable pour
> un fichier supprimé, sinon Git s'arrête à `HEAD` et ne « voit » que les
> chemins qui existent encore dans l'historique de la branche courante
> (ici ça marche sans, mais pas si le fichier n'a vécu que sur une branche).
> `shortlog -sn` est le `log` groupé par auteur ; `--all` compte aussi les
> branches non fusionnées.

---

<a id="e21-4"></a>**[E21.4](README.md#e21-4)** — *`main..feature` vs `main...feature`.*

```console
$ git diff --stat main..feature/tls-letsencrypt
 .gitattributes                                |  4 ----
 ansible/roles/nginx/tasks_certbot.yml         | 11 +++++++++++
 ansible/roles/nginx/templates/factura.conf.j2 |  6 +++---
 docs/runbook.md                               |  6 ------
 4 files changed, 14 insertions(+), 13 deletions(-)
$ git diff --stat main...feature/tls-letsencrypt
 ansible/roles/nginx/tasks_certbot.yml         | 11 +++++++++++
 ansible/roles/nginx/templates/factura.conf.j2 |  4 +++-
 2 files changed, 14 insertions(+), 1 deletion(-)
```

> [!NOTE]
> **Pourquoi**
>
> Dans `git diff`, `A..B` compare les **trees** de A et B (identique à
> `git diff A B`). Or `main` a avancé depuis la création de la branche
> (`.gitattributes`, HSTS, section rollback du runbook) : vu depuis le tree
> de la feature, ces ajouts apparaissent comme des **suppressions**. `A...B`
> compare la **base commune** (`merge-base`, ici `b344468`) à B : c'est
> exactement « ce que la branche apporte », ce qu'une MR affiche.
> Attention : dans `git log`, la sémantique est différente (`A..B` = commits
> de B pas dans A ; `A...B` = commits de l'un ou l'autre mais pas des deux).

---

<a id="e21-5"></a>**[E21.5](README.md#e21-5)** — *Commiter un hunk sur deux avec `add -p`.*

```console
$ git add -p README.md
(1/2) Stage this hunk [y,n,q,a,d,j,J,g,/,e,?]? y
(2/2) Stage this hunk [y,n,q,a,d,K,g,/,e,?]? n
$ git diff --cached --stat
 README.md | 2 +-
$ git diff --stat
 README.md | 4 ++++
$ git commit -m "docs(readme): titre avec le domaine"
$ git diff HEAD~1 HEAD --stat        # le titre est dans HEAD
 README.md | 2 +-
$ git diff --stat                    # Contact reste dans le working dir
 README.md | 4 ++++
```

> [!NOTE]
> **Pourquoi**
>
> L'index n'est pas un « fichier entier ou rien » : c'est un tree en
> construction, et `add -p` y écrit une **version intermédiaire** du fichier
> (HEAD + le hunk accepté). C'est ce qui permet de séparer une correction
> urgente d'un chantier en cours. Deux hunks trop proches sont proposés
> ensemble : `s` les découpe, `e` édite le patch à la main. À l'inverse,
> `git commit -a` indexe **tout** ce qui est suivi et modifié : incompatible
> avec des commits atomiques.

---

<a id="e21-6"></a>**[E21.6](README.md#e21-6)** — *`--amend`, `[ahead 1]`, `commit -a`, `git mv`.*

```console
$ git log -1 --format=%H
ee98c68e3ee6a43e1a837dab44a03ebcb45dbf79
$ git commit --amend -m "docs(readme): précise le domaine dans le titre"
$ git log -1 --format=%H
5fa9559c592ed867709455adc2811e7ce15a97bd
$ git status -sb | head -1
## main...origin/main [ahead 1]
$ git commit -am "docs(readme): section contact"
$ git switch -c essai/renommage feature/tls-letsencrypt
$ mkdir -p ansible/roles/nginx/tasks
$ git mv ansible/roles/nginx/tasks_certbot.yml \
    ansible/roles/nginx/tasks/main.yml
$ git status --short
R  ansible/roles/nginx/tasks_certbot.yml -> ansible/roles/nginx/tasks/main.yml
$ git commit -m "refactor(nginx): tasks/main.yml, structure de rôle standard"
$ git log -1 --stat --format=%s
 ansible/roles/nginx/{tasks_certbot.yml => tasks/main.yml} | 0
$ git switch main && git branch -D essai/renommage
```

> [!NOTE]
> **Pourquoi**
>
> `[ahead 1]` : un commit local absent d'`origin/main` — le commit amendé est
> un **nouveau** commit ; s'il avait déjà été poussé, tu verrais
> `[ahead 1, behind 1]`, signature d'une réécriture. `git mv` n'est qu'un
> raccourci pour `mv` + `git rm --cached` + `git add` : Git ne stocke pas les
> renommages, il les **détecte** à l'affichage quand un blob supprimé et un
> blob ajouté ont le même contenu (ou > 50 % de similarité, `-M`). Un `mv`
> plus une modification lourde dans le même commit sera vu comme
> suppression + ajout : renommer et modifier en deux commits.

> [!WARNING]
> **Piège**
>
> `commit -a` ne prend pas les fichiers **non suivis** : un nouveau fichier
> oublié est le bug classique du « ça marche chez moi ». `git status` avant
> `commit`, toujours.

---

<a id="e21-7"></a>**[E21.7](README.md#e21-7)** — *`logs/*` + `!logs/.gitkeep`, brouillon ignoré sans toucher le
projet, `check-ignore -v`.*

```bash
printf '\n# journaux locaux : le dossier reste, pas le contenu\n' >> .gitignore
printf 'logs/*\n!logs/.gitkeep\n' >> .gitignore
git add .gitignore logs/.gitkeep
git commit -m "chore(gitignore): ignore logs/ sauf .gitkeep"
# brouillon perso : global (tous mes dépôts) ou .git/info/exclude (ce clone)
git config --global core.excludesFile ~/.gitignore_global
printf 'notes-perso.txt\n*~\n' >> ~/.gitignore_global
```

```console
$ git check-ignore -v --no-index terraform/terraform.tfstate \
    .README.md.swp ansible/notes-perso.txt logs/deploy.log logs/.gitkeep
.gitignore:3:*.tfstate	terraform/terraform.tfstate
.gitignore:10:*.swp	.README.md.swp
/home/mathieu/.gitignore_global:1:notes-perso.txt	ansible/notes-perso.txt
.gitignore:16:logs/*	logs/deploy.log
.gitignore:17:!logs/.gitkeep	logs/.gitkeep
$ git status --short
(vide)
```

> [!NOTE]
> **Pourquoi**
>
> `logs/*` exclut le **contenu**, pas le répertoire : Git y entre et évalue
> `!logs/.gitkeep`. Avec `logs/` (répertoire), la négation serait ignorée
> (Q21.4). `notes-perso.txt` est ton problème, pas celui du projet : le mettre
> dans le `.gitignore` versionné imposerait ta convention à l'équipe et
> polluerait l'historique ; `core.excludesFile` (tous tes dépôts) ou
> `.git/info/exclude` (ce clone) sont faits pour ça. `check-ignore -v`
> affiche `fichier:ligne:règle` — la règle `!` s'affiche aussi, ce qui prouve
> qu'elle est bien évaluée; `--no-index` est nécessaire pour `logs/.gitkeep`, déjà suivi (sans lui, un fichier suivi n'est jamais rapporté).

---

<a id="e21-8"></a>**[E21.8](README.md#e21-8)** — *Merge du hotfix : ordinaire vs `--no-ff`, puis `cherry-pick` et
`branch -d`.*

```console
$ git merge hotfix/ansible-timeout
Merge made by the 'ort' strategy.
 ansible/ansible.cfg | 2 ++
 1 file changed, 2 insertions(+)
$ git log --oneline --graph -4
*   ead5285 Merge branch 'hotfix/ansible-timeout'
|\
| * 9c33a91 fix(ansible): timeout SSH 30 s et 10 forks
* | 4920391 chore(gitignore): ignore logs/ sauf .gitkeep
* | 137c1cc docs(readme): section contact
$ git reset --hard HEAD~1         # 1er parent du merge : main d'avant
$ git merge --no-ff hotfix/ansible-timeout      # même résultat
$ git reset --hard HEAD~1   # et non origin/main (perdrait E21.5 à E21.7)
$ git cherry-pick 9c33a91
$ git branch -d hotfix/ansible-timeout
warning: deleting branch 'hotfix/ansible-timeout' that has been merged to
         'refs/remotes/origin/hotfix/ansible-timeout', but not yet merged
         to HEAD
Deleted branch hotfix/ansible-timeout (was 9c33a91).
```

> [!NOTE]
> **Pourquoi**
>
> Le hotfix part de `v1.0.0` (`be7970d`) ; `main` a reçu dix commits depuis.
> `main` n'est donc pas un ancêtre de `9c33a91` : le fast-forward est
> impossible, Git fabrique un commit de merge à deux parents — `--no-ff` ou
> pas. `--no-ff` ne change quelque chose que quand le fast-forward **est**
> possible. Après `cherry-pick`, `main` contient une **copie** (`8052db1`) du
> commit, pas `9c33a91` lui-même : pour `branch -d`, qui teste « le commit de
> la branche est-il ancêtre de HEAD ? », la branche n'est pas fusionnée. Git
> l'a quand même supprimée parce que `-d` accepte aussi « fusionnée dans sa
> branche amont » (`origin/hotfix/ansible-timeout`, où elle est bien
> poussée) — d'où l'avertissement. Sans branche de suivi, il aurait fallu `-D`.

---

<a id="e21-9"></a>**[E21.9](README.md#e21-9)** — *Rebase interactif sur la base commune.*

```bash
git switch feature/tls-letsencrypt
git merge-base main HEAD           # b34446837acb…
git rebase -i b344468
```

Dans l'éditeur :

```text
pick 994e070 feat(nginx): écoute en 443 avec certificat Let's Encrypt
reword 7d111e5 wip
fixup 450115f fix typo
fixup bf67756 feat(nginx): renouvellement automatique par certbot.timer
```

puis, dans le second éditeur, le nouveau message
`feat(nginx): tâche certbot et renouvellement automatique`.

```console
$ git log --oneline --stat main..HEAD
a7f195e feat(nginx): tâche certbot et renouvellement automatique
 ansible/roles/nginx/tasks_certbot.yml | 11 +++++++++++
 1 file changed, 11 insertions(+)
994e070 feat(nginx): écoute en 443 avec certificat Let's Encrypt
 ansible/roles/nginx/templates/factura.conf.j2 | 4 +++-
 1 file changed, 3 insertions(+), 1 deletion(-)
$ git status -sb | head -1
## feature/tls-letsencrypt...origin/feature/tls-letsencrypt [ahead 1, behind 3]
```

> [!NOTE]
> **Pourquoi**
>
> Le rebase interactif rejoue les commits listés **depuis la base donnée** :
> `994e070` est repris tel quel (même parent, même tree, même message → même
> SHA, Git ne recrée rien). Les trois suivants sont fondus en un seul commit
> neuf, dont le SHA dépend de la date de committer : le tien n'est pas `a7f195e`. `ahead 1, behind 3` : ton nouveau commit n'existe pas sur le distant,
> et les trois anciens (`wip`, `fix typo`, `renouvellement`) n'existent plus
> chez toi — le **contenu** est identique, mais les commits ne le sont pas.
> Rebaser sur la base commune plutôt que sur `main` sépare deux opérations :
> nettoyer l'historique (aucun conflit possible), puis l'actualiser (le
> conflit, s'il y en a un, ne se présente qu'une fois, sur un commit propre).

> [!WARNING]
> **Piège**
>
> `fixup` jette le message du commit absorbé, `squash` le concatène et
> propose l'édition. Pour un `wip`, c'est `fixup`. Et `reword` sans changer
> le contenu recrée quand même le commit — SHA neuf.

---

<a id="e21-10"></a>**[E21.10](README.md#e21-10)** — *Basculer d'urgence avec `stash -u`.*

```console
$ git switch feature/tls-letsencrypt
error: Your local changes to the following files would be overwritten by
checkout:
	README.md
Please commit your changes or stash them before you switch branches.
Aborting
$ git stash push -u -m "brouillon readme + notes"
Saved working directory and index state On main: brouillon readme + notes
$ git status --short
(vide)
$ git stash list
stash@{0}: On main: brouillon readme + notes
$ git switch feature/tls-letsencrypt ; ... ; git switch main
$ git stash pop
Dropped refs/stash@{0} (f538086769b4826b88a540e95eaa2e2aaa9170af)
```

> [!NOTE]
> **Pourquoi**
>
> `switch` refuse quand un fichier **modifié** diffère entre les deux
> branches : il devrait l'écraser. Le stash est un commit (deux, en fait :
> index et working dir ; trois avec `-u` pour les non suivis) rangé sous
> `refs/stash`, et le working dir revient à `HEAD`. Sans `-u`, `brouillon.txt`
> reste en place : Git ne le considère pas comme « à protéger » — et si la
> branche cible contenait un fichier du même nom, le `switch` échouerait, ou
> pire, le fichier serait écrasé au retour. `pop` = `apply` + `drop` ; en cas
> de conflit à l'application, le stash est **conservé** : `stash list` après
> un `pop` qui a râlé.

---

<a id="e21-11"></a>**[E21.11](README.md#e21-11)** — *`cherry-pick 9c33a91` : SHA et dates.*

```console
$ git cherry-pick 9c33a91          # déjà fait en E21.8 : sortie d'alors
[main 8052db1] fix(ansible): timeout SSH 30 s et 10 forks
 Author: bob <bob@lab.local>
 Date: Fri Jun 19 18:22:00 2026 +0200
$ git log --format='%h %ad %cd %an %cn' --date=short -1
8052db1 2026-06-19 2026-09-19 bob mathieu
$ git log --format='%h %ad %cd' --date=short -1 9c33a91
9c33a91 2026-06-19 2026-06-19
```

> [!NOTE]
> **Pourquoi**
>
> Un commit a deux identités : **author** (qui a écrit le patch, quand) et
> **committer** (qui l'a enregistré dans **cet** historique, quand).
> `cherry-pick`, `rebase` et `am` conservent l'auteur et sa date, et posent
> le committer courant à la date courante. Le parent change (c'est `main`),
> donc le SHA change. `-x` ajoute `(cherry picked from commit 9c33a91…)` au
> message : indispensable pour retrouver l'origine d'un correctif porté sur
> plusieurs branches de maintenance.

---

<a id="e21-12"></a>**[E21.12](README.md#e21-12)** — *Tag léger vs annoté, push sélectif, `ls-remote`.*

```console
$ git tag essai
$ git tag -a v1.1.0-rc1 -m "Release candidate 1.1.0"
$ git cat-file -t essai ; git cat-file -t v1.1.0-rc1
commit
tag
$ git push origin v1.1.0-rc1
 * [new tag]         v1.1.0-rc1 -> v1.1.0-rc1
$ git ls-remote --tags origin
53340da7d0012338b3c7702b33399c7283be792b	refs/tags/v0.9.0
be137369d5ed9b3056fcc39d2ba60da6578859a9	refs/tags/v1.0.0
be7970d96a2ecaa7c06f2a1a5a33fe5cd6b87d40	refs/tags/v1.0.0^{}
…	refs/tags/v1.1.0-rc1
…	refs/tags/v1.1.0-rc1^{}
```

> [!NOTE]
> **Pourquoi**
>
> `ls-remote` affiche pour un tag annoté deux lignes : le SHA de l'**objet
> tag** et, suffixé `^{}` (« peeled »), le SHA du **commit** visé — un tag
> léger n'a que la première, égale au commit. `git push` ne pousse aucun tag
> par défaut : on nomme celui qu'on veut (`push origin v1.1.0-rc1`),
> `--tags` pousse tout (y compris `essai`, ce qu'on ne veut pas), et
> `--follow-tags` pousse seulement les tags **annotés** joignables depuis
> ce qu'on pousse — le réglage `push.followTags=true` est le bon compromis.
> `git show v1.1.0-rc1` affiche d'abord le bloc du tag (tagger, date,
> message), puis le commit.

---

<a id="e21-13"></a>**[E21.13](README.md#e21-13)** — *Alice a poussé : `fetch`, constat, `pull --rebase`.*

```console
$ git fetch
From /home/mathieu/lab21/remote/factura-infra
   fb97836..3113475  main       -> origin/main
$ git status -sb | head -1
## main...origin/main [behind 1]
$ git log --oneline main..origin/main
3113475 docs(readme): renvoi vers le runbook
$ git pull --rebase
Updating fb97836..3113475
Fast-forward
 README.md | 2 ++
```

> [!NOTE]
> **Pourquoi**
>
> `fetch` a écrit les objets et déplacé `origin/main` ; `main` n'a pas bougé,
> tes fichiers non plus. `main..origin/main` liste ce qui t'attend. Comme tu
> n'avais aucun commit local, `pull --rebase` n'a rien eu à rejouer : simple
> fast-forward, identique à ce qu'aurait fait un merge (sortie ci-dessus sur un dépôt fraîchement préparé; si tu as gardé tes commits de E21.5 à E21.11, `status` affiche `[ahead N, behind 1]` et `pull --rebase` les rejoue au-dessus de `3113475`). La différence
> n'apparaît qu'avec un commit local : `pull --rebase` le met **après**
> `3113475` (historique linéaire, nouveau SHA), `pull.rebase=false` crée
> `Merge branch 'main' of /home/mathieu/lab21/remote/factura-infra` — un
> commit de merge sans valeur, que la revue devra ignorer.

---

<a id="e21-14"></a>**[E21.14](README.md#e21-14)** — *Le tableau `reset` en vrai, puis retour au point de départ
sans compter.*

```console
$ git log --oneline -4
c3 tmp c / c2 tmp b / c1 tmp a / fb97836 docs(runbook): procédure de rollback
$ git reset --soft HEAD~1 ; git status --short ; git log --oneline -1
A  c
c2 tmp b
$ git reset --mixed HEAD~1 ; git status --short ; git log --oneline -1
?? b
?? c
c1 tmp a
$ git reset --hard HEAD~1 ; git status --short ; git log --oneline -1
?? b
?? c
fb97836 docs(runbook): procédure de rollback
$ git reflog -5
fb97836 HEAD@{0}: reset: moving to HEAD~1
c1      HEAD@{1}: reset: moving to HEAD~1
c2      HEAD@{2}: reset: moving to HEAD~1
c3      HEAD@{3}: commit: tmp c
c2      HEAD@{4}: commit: tmp b
$ git reset --hard HEAD@{6}   # l'entrée juste avant « commit: tmp a »
```

> [!NOTE]
> **Pourquoi**
>
> `--soft` : `c` reste **indexé** (`A `), prêt à être recommité. `--mixed` :
> `b` sort de l'index mais reste sur disque (`??`). `--hard` : le fichier
> `a`, suivi dans `c1`, est supprimé ; `b` et `c`, qui ne sont plus suivis,
> **survivent** — `--hard` ne touche jamais aux fichiers non suivis (c'est
> `clean` qui le fait). Le reflog liste chaque déplacement avec sa cause
> (`commit:`, `reset:`, `checkout:`) : « avant les trois commits » se lit,
> pas ne se compte (`HEAD@{5}` = `commit: tmp a`, donc `HEAD@{6}` = avant) ; `origin/main` ne conviendrait que si `main` n'avait aucun commit local.

---

<a id="e21-15"></a>**[E21.15](README.md#e21-15)** — *Branche supprimée avec `-D` : retrouver le commit.*

```console
$ git branch -D feature/tls-letsencrypt
Deleted branch feature/tls-letsencrypt (was 9d2486c).
$ git reflog | grep feature/tls
fb97836 HEAD@{3}: checkout: moving from feature/tls-letsencrypt to main
bf67756 HEAD@{5}: checkout: moving from main to feature/tls-letsencrypt
$ git fsck --lost-found | head -2
dangling commit 9d2486c07fbee24e32896942fa55963356a3bd1e
dangling commit ead5285bbadc595f887b8e8272d5674ecf4645ba
$ git branch feature/tls-letsencrypt 9d2486c
$ git diff --stat origin/feature/tls-letsencrypt feature/tls-letsencrypt
```

> [!NOTE]
> **Pourquoi**
>
> Supprimer une branche supprime un **fichier de 41 octets** dans
> `.git/refs/heads/` (et son reflog) ; les commits restent. Git affiche
> d'ailleurs le SHA dans le message de suppression — première source. Le
> reflog de `HEAD` retrace les `checkout` vers/depuis la branche : la ligne
> `moving from feature/... to main` donne le commit où l'on était juste
> avant de partir. `fsck --lost-found` liste tout commit que plus rien ne
> référence — plus brutal, mais il marche même sans reflog (dépôt copié,
> clone `--mirror`). Ici la branche recréée diffère d'`origin/…` si tu as fait
> E21.9 (rebase) dessus : même contenu, commits différents — `diff --stat` est vide, `git log origin/feature/tls-letsencrypt...` ne l'est pas.

---

<a id="e21-16"></a>**[E21.16](README.md#e21-16)** — *Bisect piloté par le script, puis `blame`.*

```console
$ git bisect start main v1.0.0      # main sur fb97836 ; sur 3113475 (après
Bisecting: 3 revisions left to test after this (roughly 2 steps)   # E21.13),
[0a6f3ae6859df6bf73b1201848fb30bb70a2f181] docs: changelog 1.0.0   # b344468
$ git bisect run bin/healthcheck.sh
running 'bin/healthcheck.sh'
manquant : ansible/playbooks/web.yaml
Bisecting: 0 revisions left to test after this (roughly 1 step)
[53e598559383fd9e8f95199861b836a22b227124] feat(terraform): bridge vmbr1 …
running 'bin/healthcheck.sh'
manquant : ansible/playbooks/web.yaml
Bisecting: 0 revisions left to test after this (roughly 0 steps)
[4a34e424294ba1b0aca88b3a1ad4d21d045557da] refactor(healthcheck): factorise …
running 'bin/healthcheck.sh'
manquant : ansible/playbooks/web.yaml
4a34e424294ba1b0aca88b3a1ad4d21d045557da is the first bad commit
$ git bisect reset
$ git blame -L 14,15 bin/healthcheck.sh
4a34e424 (bob 2026-06-18 10:40:00 +0200 14) for f in ansible/inventory.ini …
4a34e424 (bob 2026-06-18 10:40:00 +0200 15)   ansible/playbooks/web.yaml …
```

> [!NOTE]
> **Pourquoi**
>
> `bisect run cmd` exécute `cmd` à chaque étape et interprète son code :
> 0 = good, 1–124 ou 126–127 = bad, **125 = skip** (impossible à tester,
> par exemple build cassé). Le healthcheck sort en 1 quand il échoue : il
> est directement utilisable. Sept commits entre `v1.0.0` et `main` sur la
> première ligne de parenté, trois essais. `bisect` teste en HEAD détaché
> et remet la branche en place avec `reset`. `blame` attribue chaque ligne
> au **dernier** commit qui l'a modifiée — ce qui suffit ici, mais un
> reformatage massif « vole » l'attribution : `blame -w` ignore les blancs,
> `-C` suit les déplacements.

---

## 21.6 Labs

### <a id="l21-1"></a>**[L21.1](README.md#l21-1)** — *Intégrer `feature/tls-letsencrypt` : rebase interactif,
conflit, `--no-ff`, tag, suppression de branche.*

**Procédure :**

```bash
cd ~/lab21/factura-infra
git push                                   # 1. rien de local en suspens
git switch feature/tls-letsencrypt
git log --oneline main..HEAD               # 4 commits
git rebase -i "$(git merge-base main HEAD)"   # 2. reword/fixup (E21.9)
git rebase main                            # 3. conflit attendu
```

```console
Auto-merging ansible/roles/nginx/templates/factura.conf.j2
CONFLICT (content): Merge conflict in ansible/roles/nginx/templates/…
error: could not apply 994e070... feat(nginx): écoute en 443 avec …
hint: Resolve all conflicts manually, mark them as resolved with
hint: "git add/rm <conflicted_files>", then run "git rebase --continue".
```

Le fichier :

```text
        listen 443 ssl;
        server_name factura.lab.local;
        root /srv/factura/public;
<<<<<<< HEAD
        add_header Strict-Transport-Security "max-age=31536000" always;
        add_header X-Content-Type-Options nosniff;
=======
        ssl_certificate     /etc/letsencrypt/live/factura/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/factura/privkey.pem;
>>>>>>> 994e070 (feat(nginx): écoute en 443 avec certificat Let's Encrypt)
```

Résolution : garder les quatre lignes, supprimer les trois marqueurs
(les `ssl_*` avant les `add_header`, par lisibilité — l'ordre n'a pas
d'importance pour nginx).

```bash
git diff --check                           # rien = aucun marqueur oublié
git add ansible/roles/nginx/templates/factura.conf.j2
git rebase --continue                      # 4.
git push                                   # rejeté
git push --force-with-lease
git switch main                            # 5.
git merge --no-ff feature/tls-letsencrypt \
  -m "Merge branch 'feature/tls-letsencrypt' (TLS Let's Encrypt)"
git tag -a v1.1.0 -m "Version 1.1.0 — TLS Let's Encrypt"
git push origin main v1.1.0
git push origin --delete feature/tls-letsencrypt     # 6.
git branch -d feature/tls-letsencrypt
git config rerere.enabled true                       # 7.
```

```console
$ git push
 ! [rejected]  feature/tls-letsencrypt -> feature/tls-letsencrypt
   (non-fast-forward)
$ git push --force-with-lease
 + bf67756...f1c31b4 feature/tls-letsencrypt -> feature/tls-letsencrypt
   (forced update)
$ git merge --no-ff feature/tls-letsencrypt -m "..."
Merge made by the 'ort' strategy.
 ansible/roles/nginx/tasks_certbot.yml         | 11 +++++++++++
 ansible/roles/nginx/templates/factura.conf.j2 |  4 +++-
$ git log --oneline --graph -5
*   3883276 Merge branch 'feature/tls-letsencrypt' (TLS Let's Encrypt)
|\
| * f1c31b4 feat(nginx): tâche certbot et renouvellement automatique
| * e3e1455 feat(nginx): écoute en 443 avec certificat Let's Encrypt
|/
* 3113475 docs(readme): renvoi vers le runbook
$ git push origin --delete feature/tls-letsencrypt
 - [deleted]         feature/tls-letsencrypt
```

> [!NOTE]
> **Pourquoi**
>
> Le conflit vient de deux commits qui insèrent des lignes **au même endroit**
> (après `root …`) : Git ne sait pas dans quel ordre les mettre, ni si l'un
> remplace l'autre — c'est une décision humaine, et la seule bonne réponse
> ici est « les deux ». Pendant le rebase, `HEAD` est `main` (Q21.7) : garder
> « ours » aurait jeté le TLS d'alice. `--force-with-lease` est acceptable
> parce que la branche est **personnelle** et que l'option refuse d'écraser
> un commit qu'alice aurait poussé entre-temps ; sur `main`, partagé et
> protégé, un push forcé casserait tous les clones. Le `--no-ff` garde la
> feature visible : `git log --first-parent` montre une ligne « TLS », et
> `git revert -m 1 3883276` l'annulerait d'un coup. `rerere` (« reuse
> recorded resolution ») enregistre la résolution ; si le même conflit
> réapparaît (rebase refait, cherry-pick sur une autre branche), il est
> résolu automatiquement : `Resolved 'factura.conf.j2' using previous
> resolution.` — il faut quand même `add` et vérifier.

> [!WARNING]
> **Piège**
>
> Le SHA du merge commit, du tag et des commits rebasés sont propres à ta
> machine (date de committer) : ne les compare pas au corrigé. Ce qui doit
> coïncider : le contenu du template et la forme du graphe.

---

### <a id="l21-2"></a>**[L21.2](README.md#l21-2)** — *Bisect : localiser et corriger la régression du healthcheck.*

**Procédure :**

```console
$ bin/healthcheck.sh ; echo "rc=$?"
manquant : ansible/playbooks/web.yaml
rc=1
$ git worktree add ../wt-v1 v1.0.0
$ (cd ../wt-v1 && bin/healthcheck.sh) ; git worktree remove ../wt-v1
healthcheck OK
$ git bisect start main v1.0.0 && git bisect run bin/healthcheck.sh
…
4a34e424294ba1b0aca88b3a1ad4d21d045557da is the first bad commit
$ git bisect reset
$ git show 4a34e42 | grep -n 'web.ya'
```

Le refactor de bob a remplacé `ansible/playbooks/web.yml` par `web.yaml`
dans la liste des fichiers à vérifier ; le fichier s'appelle `web.yml`.
Correctif ciblé :

```bash
sed -i 's#ansible/playbooks/web.yaml#ansible/playbooks/web.yml#' \
  bin/healthcheck.sh
bin/healthcheck.sh                     # healthcheck OK
git commit -am "fix(healthcheck): web.yml, pas web.yaml

Régression introduite par 4a34e42 (refactor). Trouvé par bisect run."
git push
```

Rapport `~/lab21/rapports/bisect.md` : `git bisect start main v1.0.0`,
`git bisect run bin/healthcheck.sh`, 3 étapes, SHA `4a34e42`, cause :
faute de frappe dans un nom de fichier, correctif ci-dessus. Prévention :
exécuter le healthcheck en CI sur chaque MR (la régression n'aurait jamais
atteint `main`) ; un `commit-msg` n'aurait rien vu — le message était
correct, c'est le **contenu** qu'il fallait tester.

> [!NOTE]
> **Pourquoi**
>
> Le `worktree` évite le classique « je fais `checkout v1.0.0` pour tester
> et je me retrouve en HEAD détaché avec des modifications » : une seconde
> copie de travail, même `.git`, branche ou tag différent. Bisect suppose
> que la propriété testée est **monotone** (bonne avant, mauvaise après le
> commit fautif) ; avec un test flaky, il désigne n'importe quoi — d'où
> l'importance d'un test déterministe comme celui-ci. On ne revert pas le
> refactor entier : il est correct à une lettre près, et un revert
> réintroduirait la dette qu'il supprimait. On ne renomme pas le playbook
> non plus : ce serait adapter la réalité à un bug.

---

### <a id="l21-3"></a>**[L21.3](README.md#l21-3)** — *Serveur Git minimal sur `lab-adm`, hook `post-receive`.*

**Sur `lab-adm` :**

```bash
sudo groupadd git
sudo usermod -aG git mathieu          # relogin (ou newgrp git)
sudo mkdir -p /srv/git
sudo chgrp git /srv/git && sudo chmod 2775 /srv/git
cd /srv/git
git init --bare --shared=group factura-infra.git
git -C factura-infra.git symbolic-ref HEAD refs/heads/main
git -C factura-infra.git config --list | grep -E 'shared|deny'
```

```console
core.sharedrepository=1
receive.denynonfastforwards=true
```

Hook `/srv/git/factura-infra.git/hooks/post-receive` :

```bash
#!/usr/bin/env bash
# post-receive — déploie la branche main dans /srv/factura-conf
set -euo pipefail
DEST=/srv/factura-conf
while read -r ancien nouveau ref; do
  [ "$ref" = refs/heads/main ] || continue
  echo "deploiement de main : ${ancien:0:7} -> ${nouveau:0:7}"
  git archive "$nouveau" | tar -x -C "$DEST"
  printf '%s %s %s\n' "$(date -Is)" "$nouveau" "$(id -un)" \
    >> "$DEST/.deploy.log"
  echo "ok : $DEST est au niveau ${nouveau:0:7}"
done
```

```bash
chmod +x /srv/git/factura-infra.git/hooks/post-receive
sudo mkdir -p /srv/factura-conf && sudo chown mathieu:git /srv/factura-conf
cd ~/lab21/factura-infra
git remote add lab-adm ssh://mathieu@lab-adm/srv/git/factura-infra.git
git push lab-adm main --tags
```

```console
remote: deploiement de main : 0000000 -> 5fc90ae
remote: ok : /srv/factura-conf est au niveau 5fc90ae
To ssh://lab-adm/srv/git/factura-infra.git
 * [new branch]      main -> main
 * [new tag]         v1.0.0 -> v1.0.0
```

**Sur `lab-ops`** (clé de mathieu déjà déployée, module 14) :

```bash
git clone ssh://mathieu@lab-adm/srv/git/factura-infra.git
cd factura-infra
echo "* test hook depuis lab-ops" >> CHANGELOG.md
git commit -am "docs(changelog): test du hook de déploiement"
git push                          # remote: deploiement de main : 5fc90ae -> …
git switch -c essai && git push -u origin essai      # hook muet
git reset --hard HEAD~1 && git push --force origin essai:main
```

```console
remote: error: denying non-fast-forward refs/heads/main (you should pull first)
 ! [remote rejected] essai -> main (non-fast-forward)
```

> [!NOTE]
> **Pourquoi**
>
> Un dépôt **bare** n'a pas de working directory : c'est le contenu de
> `.git` à la racine, et c'est le seul format acceptable pour un serveur
> (pousser dans un dépôt non-bare sur la branche extraite est refusé par
> défaut : `receive.denyCurrentBranch`). `--shared=group` fait trois choses :
> `core.sharedRepository=group` (les fichiers créés sont `g+w`), le setgid
> sur les répertoires (les nouveaux objets prennent le groupe `git`, pas le
> groupe primaire de celui qui pousse), et `receive.denyNonFastForwards=true`
> — une protection de branche gratuite, qui explique le refus final. Le
> hook `post-receive` reçoit sur stdin **une ligne par référence poussée**
> (`ancien nouveau ref`), avec `0000000…` pour une création ; filtrer sur
> `refs/heads/main` évite de déployer une branche d'essai. `git archive |
> tar -x` extrait un tree sans `.git` ni fichiers ignorés, à l'inverse d'un
> `checkout --work-tree` qui laisse un index à moitié cohérent. Tout ce que
> le hook écrit revient au client préfixé `remote:` : c'est ton journal de
> déploiement côté développeur.

> [!WARNING]
> **Piège**
>
> Un hook côté serveur tourne avec l'identité de **celui qui pousse**
> (connexion SSH `mathieu@lab-adm`) : `/srv/factura-conf` doit être
> inscriptible par tous les membres du groupe `git`, sinon le hook échoue —
> et comme `post-receive` s'exécute **après** l'acceptation du push, l'échec
> n'annule pas le push : `main` avance, rien n'est déployé. Pour refuser un
> push, c'est `pre-receive` (D21).

---

### <a id="l21-4"></a>**[L21.4](README.md#l21-4)** — *Purger le secret : preuve, rotation, `filter-repo`, re-clone,
hook.*

**1–2. Preuve et rotation** (dans le rapport) :

```console
$ git log --oneline --all -- .env
53340da fix: retire .env du dépôt et l'ignore
1557f83 chore: ajoute la conf locale de dev
$ git show 1557f83:.env | grep -E 'PASSWORD|API_KEY'
DB_PASSWORD=S3cr3t-Factura-2026!
API_KEY=AKIAIOSFODNN7EXAMPLE
$ git grep -l S3cr3t $(git rev-list --all)
1557f83fa5280573d92393c3cc2ae285890be472:.env
```

Compromis : le mot de passe PostgreSQL de `factura` sur `lab-db` et la clé
API `AKIA…`. Rotation **avant** tout : `ALTER USER factura PASSWORD …`,
révocation de la clé chez le fournisseur, nouvelles valeurs distribuées par
le coffre — jamais par le dépôt.

**3–6. Réécriture dans un miroir, puis push** :

```bash
cd ~/lab21/factura-infra && git push --all && git push --tags
cd ~/lab21 && git clone --mirror remote/factura-infra.git purge && cd purge
git filter-repo --invert-paths --path .env
git log --all --oneline -- .env               # vide
git grep -l S3cr3t $(git rev-list --all)      # vide
git tag                                       # v0.9.0 v1.0.0 v1.1.0
git push --mirror ~/lab21/remote/factura-infra.git
cd ~/lab21/remote/factura-infra.git
git reflog expire --expire=now --all && git gc --prune=now
git cat-file -e 1557f83fa5280573d92393c3cc2ae285890be472 ; echo "rc=$?"
```

```console
rc=1        # l'objet n'existe plus
```

Variante sans `git-filter-repo` (acceptée, plus lente, plus fragile) :

```bash
FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch --index-filter \
  'git rm --cached --ignore-unmatch .env' --prune-empty \
  --tag-name-filter cat -- --all
git for-each-ref --format='delete %(refname)' refs/original \
  | git update-ref --stdin
git reflog expire --expire=now --all && git gc --prune=now
```

**7. Le clone de travail** :

```console
$ cd ~/lab21/factura-infra && git fetch && git status -sb | head -1
## main...origin/main [ahead 19, behind 17]
```

Ton `main` et `origin/main` n'ont plus que six commits en commun (ceux
d'avant `1557f83`) : tout le reste a été recréé. Un `pull` fusionnerait
les deux historiques et **repousserait** l'ancien `.env`. La bonne réponse
est un clone frais :

```bash
cd ~/lab21 && mv factura-infra factura-infra.old
git clone remote/factura-infra.git factura-infra
git -C factura-infra cat-file -e 1557f83fa5280573d92393c3cc2ae285890be472
# rc=1 : propre
```

(`reset --hard origin/main` + suppression des branches locales + `reflog
expire` + `gc` marche aussi, mais un seul oubli — la branche
`hotfix/ansible-timeout` locale, par exemple — garde l'ancien commit
joignable : le check le détecte.)

**8. Hook `pre-commit`** (`~/lab21/factura-infra/.git/hooks/pre-commit`) :

```bash
#!/usr/bin/env bash
# pre-commit — refuse un commit qui contient un secret évident
set -uo pipefail
motifs='(DB_PASSWORD|PASSWORD|SECRET|API_KEY|AWS_SECRET_ACCESS_KEY)'
motifs="$motifs[[:space:]]*[=:]"
motifs="$motifs|AKIA[0-9A-Z]{16}|BEGIN ([A-Z]+ )?PRIVATE KEY"
rc=0
for f in $(git diff --cached --name-only --diff-filter=AM); do
  case "$f" in *.env|.env|*.pem|*.key|*id_rsa*|*id_ed25519*)
    echo "refusé : $f ne doit jamais être commité" >&2; rc=1; continue;; esac
  if git show ":$f" | grep -nE "$motifs" >/dev/null; then
    echo "refusé : $f contient ce qui ressemble à un secret :" >&2
    git show ":$f" | grep -nE "$motifs" | sed 's/^/    /' >&2
    rc=1
  fi
done
[ "$rc" -eq 0 ] || \
  echo "(contourner en connaissance de cause : git commit --no-verify)" >&2
exit "$rc"
```

```console
$ chmod +x .git/hooks/pre-commit
$ printf 'DB_PASSWORD=Test-2026\n' > test.env && git add -f test.env
$ git commit -m "test"
refusé : test.env ne doit jamais être commité
(contourner en connaissance de cause : git commit --no-verify)
```

> [!NOTE]
> **Pourquoi**
>
> `filter-repo` parcourt tout l'historique, retire `.env` de chaque tree qui
> le contient, supprime les commits devenus vides (`1557f83` et `53340da`
> n'ajoutaient/retiraient que ce fichier), et recrée tous les commits en
> aval — les six premiers gardent leur SHA. Il efface aussi le remote
> `origin` et les reflogs du clone pour empêcher un `push` accidentel vers
> l'ancien historique : d'où le travail dans un `--mirror` jetable. Sur le
> serveur, les anciens objets restent dans `objects/` tant qu'un reflog ou
> `refs/original` les cite ; `reflog expire` + `gc --prune=now` les
> supprime physiquement — c'est `cat-file -e` qui le prouve, pas `git log`.
> Le hook lit `git show ":$f"` (le contenu **indexé**) et non le fichier sur
> disque : ce qui est commité est ce qui est dans l'index, et un `add -p`
> peut avoir indexé une version différente. `gitleaks protect --staged`
> fait la même chose avec 150 règles maintenues.

> [!WARNING]
> **Piège**
>
> Sur une forge, le push forcé ne suffit pas : les commits restent
> accessibles **par SHA** via l'interface (caches, MR, forks) tant que
> l'administrateur n'a pas lancé un `gc` côté serveur. Et les tags annotés
> sont réécrits par `filter-repo` (`--tag-name-filter cat` avec
> `filter-branch`) : `v1.0.0` pointe désormais sur un nouveau commit, la
> signature éventuelle du tag est **invalidée** — à re-signer.

---

### <a id="l21-5"></a>**[L21.5](README.md#l21-5)** — *Gitea sur `lab-ops`.*

**Procédure (binaire + systemd) :**

```bash
sudo adduser --system --group --home /home/git --shell /bin/bash git
sudo mkdir -p /var/lib/gitea/{custom,data,log} /etc/gitea
sudo chown -R git:git /var/lib/gitea && sudo chmod -R 750 /var/lib/gitea
sudo chown root:git /etc/gitea && sudo chmod 770 /etc/gitea
V=1.24.6      # dernière 1.x lue sur https://dl.gitea.com/gitea/
sudo wget -O /usr/local/bin/gitea \
  "https://dl.gitea.com/gitea/$V/gitea-$V-linux-amd64"
sudo chmod +x /usr/local/bin/gitea && gitea --version
```

`/etc/systemd/system/gitea.service` :

```ini
[Unit]
Description=Gitea (forge Git du lab)
After=network.target

[Service]
Type=simple
User=git
Group=git
WorkingDirectory=/var/lib/gitea
Environment=USER=git HOME=/home/git GITEA_WORK_DIR=/var/lib/gitea
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=always
RestartSec=2s

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload && sudo systemctl enable --now gitea.service
ss -tlnp | grep 3000          # LISTEN 0.0.0.0:3000 gitea
```

Écran d'installation (`http://10.10.10.14:3000`) : SQLite3, domaine
`lab-ops.lab.local`, port SSH **2222**, `ROOT_URL http://10.10.10.14:3000/`,
compte administrateur `mathieu`. Puis :

```bash
sudo chmod 750 /etc/gitea && sudo chmod 640 /etc/gitea/app.ini
```

Organisation `infra`, dépôt `infra/factura-infra`, clé SSH dans
*Settings → SSH/GPG Keys*, puis depuis `lab-adm` :

```bash
git remote add gitea ssh://git@10.10.10.14:2222/infra/factura-infra.git
git push gitea --all && git push gitea --tags
```

Protection de `main` (*Settings → Branches → Add rule*) : « Enable push »
décoché, « Enable Merge Whitelist » ou « Required approvals = 1 », « Block
merge on rejected reviews ». Test :

```console
$ git push gitea main
remote: Gitea: Not allowed to push to protected branch main
 ! [remote rejected] main -> main (pre-receive hook declined)
```

Branche `docs/gitea`, push, *New Pull Request*, merge « Rebase then
merge », `git pull` sur `lab-adm`.

> [!NOTE]
> **Pourquoi**
>
> Une forge ne fait rien que ce module n'ait fait à la main : un dépôt bare
> par projet (`/var/lib/gitea/data/gitea-repositories/infra/factura-infra.git`),
> un serveur SSH qui n'autorise que `git-upload-pack`/`git-receive-pack`, et
> des hooks `pre-receive`/`post-receive` **générés** qui implémentent la
> protection de branche et les webhooks. La protection de `main` que tu
> viens de cliquer est exactement le `pre-receive` de D21, en plus fiable et
> avec une interface. Le port SSH 2222 évite de mêler l'authentification Git
> à celle du système ; en production on mettrait plutôt Gitea derrière le
> sshd système avec un utilisateur `git` dédié, ou derrière un reverse
> proxy TLS (module 15).

---

## 21.7 Break & Fix

### <a id="bf21-1"></a>**[BF21.1](README.md#bf21-1)** — *Le rebase d'alice resté en plan.*

**Diagnostic :**

```console
$ git status
interactive rebase in progress; onto beb6e71
Last command done (1 command done):
   pick 3738847 feat(nginx): écoute en 443 avec certificat Let's Encrypt
Next commands to do (2 remaining commands):
   pick 793b5ef feat(nginx): tâche certbot
   pick c55c1b1 wip
You are currently rebasing branch 'feature/tls' on 'beb6e71'.
  (all conflicts fixed: run "git rebase --continue")

Changes to be committed:
	modified:   ansible/roles/nginx/templates/factura.conf.j2
$ git diff --cached --check
ansible/roles/nginx/templates/factura.conf.j2:11: leftover conflict marker
ansible/roles/nginx/templates/factura.conf.j2:14: leftover conflict marker
ansible/roles/nginx/templates/factura.conf.j2:17: leftover conflict marker
$ git log --oneline --graph --all
* beb6e71 docs(readme): renvoi runbook
* 3a6bb4f feat(nginx): en-têtes de sécurité HSTS et nosniff
| * c55c1b1 wip
| * 793b5ef feat(nginx): tâche certbot
| * 3738847 feat(nginx): écoute en 443 avec certificat Let's Encrypt
|/
* 4f40403 chore: dépôt de départ
```

**Cause racine :** alice a lancé `git rebase main`, obtenu le conflit sur
le template, puis fait `git add` du fichier **sans retirer les
marqueurs** — pour Git, un fichier indexé est un conflit « résolu », d'où
le message trompeur `all conflicts fixed`. Un `git rebase --continue`
aurait commité les `<<<<<<<` dans le dépôt, et nginx aurait refusé la
configuration au prochain déploiement.

**Correctif** (le plus sûr : repartir de zéro, la branche n'a pas bougé) :

```bash
git rebase --abort                 # la branche revient sur c55c1b1
git rebase -i main                 # pick / pick / fixup (le wip)
# conflit sur le premier commit : garder HSTS + ssl_*, retirer les marqueurs
git diff --check                   # silence
git add ansible/roles/nginx/templates/factura.conf.j2
git rebase --continue
git push --force-with-lease   # + c55c1b1...797163d feature/tls (forced update)
git log --oneline --graph --all
rm notes-alice.txt
```

```console
* 797163d feat(nginx): tâche certbot            (SHA rejoués : propres à toi)
* bbda1dc feat(nginx): écoute en 443 avec certificat Let's Encrypt
* beb6e71 docs(readme): renvoi runbook
* 3a6bb4f feat(nginx): en-têtes de sécurité HSTS et nosniff
* 4f40403 chore: dépôt de départ
```

Variante sans abandonner : corriger le fichier en place, `git add`,
`--continue`, puis un second `rebase -i` pour absorber `wip`.

**Prévention :** `git diff --check` avant tout `add` de résolution ;
un hook `pre-commit` qui refuse `^(<<<<<<<|=======|>>>>>>>)` ; ne jamais
laisser un rebase ouvert (`--abort` si on n'a pas le temps).

> [!NOTE]
> **Pourquoi**
>
> Un rebase en cours est un **état** dans `.git/rebase-merge/` : la liste
> des commits restants (`git-rebase-todo`), ceux faits (`done`), la branche
> d'origine (`head-name`), et `HEAD` détaché sur le dernier commit rejoué.
> `switch` refuse pour ne pas laisser cet état orphelin ; `rebase --abort`
> remet `HEAD` et la branche là où `orig-head` les note, sans rien perdre.
> Git ne relit **pas** le contenu pour vérifier qu'un conflit est résolu : il
> regarde si l'entrée d'index est passée des trois stades (base/ours/theirs)
> à un seul. C'est pourquoi `diff --check` existe. Supprimer
> `.git/rebase-merge` à la main laisserait `HEAD` détaché et la branche non
> mise à jour : exactement BF21.2.

---

### <a id="bf21-2"></a>**[BF21.2](README.md#bf21-2)** — *Les correctifs de l'astreinte ont disparu.*

**Diagnostic :**

```console
$ git log --oneline --all
b6b4592 docs: prépare 1.0.1
c72eea0 docs(runbook): vérification
4d7ff00 docs: changelog 1.0.0
adc54a2 docs: runbook
36a09f5 chore: dépôt de départ
$ git reflog
b6b4592 HEAD@{0}: commit: docs: prépare 1.0.1
c72eea0 HEAD@{1}: checkout: moving from adc54a2… to main
adc54a2 HEAD@{2}: checkout: moving from main to v1.0.0
c72eea0 HEAD@{3}: checkout: moving from 0c57ce0… to main
0c57ce0 HEAD@{4}: commit: fix(deploy): nginx -t avant le reload
9e4875f HEAD@{5}: commit: fix(deploy): quote les chemins rsync (incident …)
adc54a2 HEAD@{6}: checkout: moving from main to v1.0.0
c72eea0 HEAD@{7}: commit: docs(runbook): vérification
$ git log -g --oneline --grep-reflog=commit        # ou : --grep=incident
```

**Séquence reconstituée** (lue de bas en haut) : `HEAD@{6}` `checkout`
`main → v1.0.0` — l'astreinte s'est placée sur le tag pour reproduire la
production : **HEAD détaché**. `HEAD@{5}` et `HEAD@{4}` : deux commits
faits dans cet état, sur aucune branche. `HEAD@{3}` : retour sur `main`,
avec l'avertissement `you are leaving 2 commits behind` (ignoré). Puis un
nouvel aller-retour et le commit d'alice. Les deux commits existent toujours
(`git fsck --lost-found` : `dangling commit 0c57ce0…`) mais rien ne les
référence.

**Correctif :**

```bash
git branch hotfix/deploy-quotes 0c57ce0        # 0c57ce0 a 9e4875f pour parent
git log --oneline main..hotfix/deploy-quotes   # 2 commits
git switch main
git merge --no-ff hotfix/deploy-quotes -m "Merge hotfix/deploy-quotes"
# ou : git cherry-pick 9e4875f 0c57ce0 (historique linéaire)
grep -n 'rsync' bin/deploy.sh                  # chemins quotés
git branch -d hotfix/deploy-quotes
```

Délai : `gc.reflogExpireUnreachable` = 30 jours pour les entrées de reflog
pointant des commits injoignables, puis `git gc` (lancé automatiquement
par `git gc --auto` après certaines commandes) supprime les objets. Les
entrées du 11 juillet sont expirables dès le 10 août : passé cette date, les commits ne survivent que tant qu'aucun `gc` n'est passé.

**Prévention :** `git branch` **avant** de commiter en détaché, ou
`git switch -c hotfix/... v1.0.0` dès le départ ; lire les avertissements
de `switch` ; `git config --global advice.detachedHead true` (défaut) —
Git explique tout ça au moment du `checkout v1.0.0`.

> [!NOTE]
> **Pourquoi**
>
> Le reflog est l'historique des **valeurs** de `HEAD` (et de chaque
> branche : `git reflog show main`), écrit à chaque commande qui les
> déplace. Il est local, jamais poussé, et périmé après 90 jours
> (joignable) ou 30 jours (injoignable). `git log -g` le parcourt comme un
> historique ; `fsck --lost-found` retrouve les commits orphelins **sans**
> reflog. Le merge choisit `0c57ce0` (le plus récent) : son parent est
> `9e4875f`, donc les deux commits reviennent d'un coup.

---

### <a id="bf21-3"></a>**[BF21.3](README.md#bf21-3)** — *Push rejeté, `pull` refuse.*

**Diagnostic :**

```console
$ git push
 ! [rejected]        main -> main (fetch first)
$ git pull
   c0c0720..a1e949a  main       -> origin/main
hint: Diverging branches can't be fast-forwarded, you need to either:
hint: 	git merge --no-ff    …   or:   git rebase
fatal: Not possible to fast-forward, aborting.
$ git status | head -3
On branch main
Your branch and 'origin/main' have diverged,
and have 2 and 2 different commits each, respectively.
$ git log --oneline --graph --all
* 0a54cc5 feat(bin): rotate-logs.sh
* abf4dd0 feat(ansible): ajoute lab-ops à l'inventaire
| * a1e949a docs(readme): convention
| * f5aca20 feat(ansible): ajoute lab-rhel à l'inventaire
|/
* c0c0720 chore: dépôt de départ
$ git config --show-origin pull.ff
file:.git/config	only
```

**Cause racine :** divergence normale (alice a poussé pendant que tu
travaillais) + réglage **local** `pull.ff=only` qui interdit à `pull` de
merger ou rebaser. `(fetch first)` au premier push : le clone ne connaissait
pas encore les commits d'alice ; après le `fetch` fait par `pull`, le
message deviendrait `(non-fast-forward)`.

**Correctif — stratégie 1, rebase (historique linéaire) :**

```bash
git pull --rebase            # l'option explicite prime sur pull.ff
# CONFLICT (content): Merge conflict in ansible/inventory.ini
```

`inventory.ini` : garder les deux sections `[rhel]` et `[ops]` et les
deux lignes `rhel`/`ops` dans `[lab:children]`, retirer les marqueurs.

```bash
git diff --check && git add ansible/inventory.ini
git rebase --continue         # le 2e commit (rotate-logs) passe seul
git push
git log --oneline --graph
```

```text
* … feat(bin): rotate-logs.sh
* … feat(ansible): ajoute lab-ops à l'inventaire
* a1e949a docs(readme): convention
* f5aca20 feat(ansible): ajoute lab-rhel à l'inventaire
* c0c0720 chore: dépôt de départ
```

**Stratégie 2, merge (chronologie conservée) :** `git merge origin/main`
(ou `git pull --no-rebase`), même résolution, `git commit`, `git push` ;
le graphe garde les deux lignes et un commit `Merge remote-tracking branch
'origin/main'`.

`pull.ff=only` : garder ? Sur un poste de développement, non — il
transforme chaque divergence en erreur, et pousse à taper `--force` par
lassitude. Sur une machine de déploiement qui ne doit jamais avoir de
commits locaux, oui : un refus signale une dérive. Ici :
`git config --unset pull.ff` et `pull.rebase=true` en global.

> [!NOTE]
> **Pourquoi**
>
> Un push est accepté seulement si la nouvelle valeur de la référence
> **descend** de l'ancienne (fast-forward côté serveur). Alice a avancé
> `origin/main` vers `a1e949a`, qui n'est pas dans ton historique : ton
> `0a54cc5` ne descend pas de `a1e949a`, refus. Intégrer = fabriquer un
> commit qui descend des deux. `pull.ff=only` applique la même règle
> **localement** : n'accepter d'avancer `main` que si `origin/main` en
> descend, ce qui est faux ici. Rebase et merge produisent le même
> `inventory.ini` ; ils diffèrent par la forme du graphe et par le fait que
> tes deux commits changent de SHA (rebase) ou non (merge).

---

### <a id="bf21-4"></a>**[BF21.4](README.md#bf21-4)** — *`git status` affiche 2 000 fichiers.*

**Diagnostic :**

```console
$ git status --porcelain -uall | wc -l
2025
$ git status --short -uall | cut -c1-2 | sort | uniq -c
   2024 ??
      1  M                       # terraform/terraform.tfstate
$ ls .gitignore
ls: cannot access '.gitignore': No such file or directory
$ git log --oneline --diff-filter=D --name-only -- .gitignore
76d5965 chore: nettoyage des fichiers cachés
.gitignore
$ git log -1 --format='%an %ad' 76d5965
bob Thu Jul 9 17:45:00 2026 +0200
$ git ls-files
README.md
logs/.gitkeep
terraform/.terraform.lock.hcl
terraform/main.tf
terraform/terraform.tfstate
$ git log -1 --format='%h %an %s' -- terraform/terraform.tfstate
46cd34a bob chore(terraform): partage l'état courant
```

**Causes racines :** (1) bob a supprimé `.gitignore` dans `76d5965`
(« nettoyage des fichiers cachés » — il a pris le fichier pour un
déchet) ; `terraform init` a ensuite rempli `.terraform/` (1 900 fichiers)
et les journaux se sont accumulés. (2) `terraform.tfstate` est **suivi**
depuis `46cd34a` : aucun `.gitignore` ne peut le faire taire tant qu'il
est dans l'index.

**Correctif :**

```bash
git restore --source=76d5965~1 .gitignore    # ou : git revert 76d5965
git rm --cached terraform/terraform.tfstate
git status --short
```

```console
D  terraform/terraform.tfstate
?? .gitignore
```

```bash
git add .gitignore
git commit -m "fix(git): restaure .gitignore, ne suit plus terraform.tfstate"
git status --short                          # (vide)
git check-ignore -v terraform/.terraform.lock.hcl ; echo "rc=$?"   # rc=1
git ls-files | grep -c lock.hcl             # 1 : toujours suivi
```

**Le mot de passe :** `pve_password` est dans `terraform.tfstate` **et
dans l'historique** (`git show 46cd34a: terraform/terraform.tfstate`). Le
retirer de l'index ne change rien à ça : rotation du mot de passe Proxmox,
puis purge de l'historique (`git filter-repo --path
terraform/terraform.tfstate --invert-paths`) comme en L21.4. Et pour la
suite : état Terraform dans un backend distant (S3/MinIO, Consul, Terraform
Cloud) chiffré, jamais dans Git.

> [!NOTE]
> **Pourquoi**
>
> `git status` ne « plante » pas à 2 000 fichiers, mais il rend `add -A`
> inutilisable et cache les vrais changements : c'est un problème de
> signal, pas de performance. `--diff-filter=D` avec `--name-only` retrouve
> en une commande qui a supprimé quoi ; `restore --source=<commit>~1` prend
> le fichier tel qu'il était **juste avant** la suppression — sans réécrire
> un `.gitignore` de mémoire, qui aurait sûrement oublié `crash.log` ou la
> négation `!logs/.gitkeep`. `.terraform.lock.hcl` doit rester suivi : il
> fige les versions des providers pour toute l'équipe ; la règle
> `.terraform/` (avec le slash, un répertoire) ne le matche pas — vérifié par
> `check-ignore` qui répond rc 1.

> [!WARNING]
> **Piège**
>
> `git rm terraform/terraform.tfstate` **sans** `--cached` supprime le
> fichier du disque : l'état Terraform de l'infra, irremplaçable sans
> `terraform import` de chaque ressource. `--cached` retire de l'index
> seulement. Et `git clean -fdx` ici aurait supprimé `.terraform/` (5 min de
> `init` à refaire) et `terraform.tfstate.backup`.

---

## 21.8 Défi du module

<a id="d21"></a>**[D21](README.md#d21)** — *Le dépôt de référence de l'équipe infra.*

**1. Hooks versionnés**

`.githooks/pre-commit` : celui de L21.4, complété par l'analyse statique :

```bash
# … après la boucle sur les secrets :
for f in $(git diff --cached --name-only --diff-filter=AM -- '*.sh'); do
  command -v shellcheck >/dev/null && { shellcheck "$f" || rc=1; }
done
for f in $(git diff --cached --name-only --diff-filter=AM -- '*.yml' '*.yaml')
do
  command -v yamllint >/dev/null && { yamllint -d relaxed "$f" || rc=1; }
done
exit "$rc"
```

`.githooks/commit-msg` :

```bash
#!/usr/bin/env bash
# commit-msg — impose Conventional Commits sur la première ligne
set -uo pipefail
ligne=$(sed -n '1p' "$1")
types='feat|fix|docs|chore|refactor|test|ci|perf|build|revert'
if printf '%s' "$ligne" | grep -qE "^($types)(\([a-z0-9._/-]+\))?!?: .{3,72}$" \
   || printf '%s' "$ligne" | grep -qE '^(Merge|Revert) '; then
  exit 0
fi
cat >&2 <<MSG
refusé : « $ligne »
  format attendu : type(scope): description courte à l'impératif
  types : $types
  exemple : fix(nginx): worker_connections 4096 sur lab-web
MSG
exit 1
```

```bash
chmod +x .githooks/*
git config core.hooksPath .githooks       # local : chaque clone le refait
git add .githooks
git commit -m "chore: hooks pre-commit et commit-msg versionnés"
```

**2. `CONTRIBUTING.md`** (extrait attendu) : workflow **GitHub flow**
(`main` déployable, une branche par ticket `feat/`, `fix/`, `hotfix/`,
MR relue, rebase avant / `--no-ff` à l'intégration — justification :
déploiements quotidiens, pas de versions parallèles, revue obligatoire) ;
Conventional Commits avec la liste des types ; interdits (`.env`, clés,
`*.tfstate`, dumps) et procédure de fuite (rotation → purge → re-clone) ;
release (`CHANGELOG.md`, tag annoté signé, push `lab-adm` + `gitea`) ;
activation : `git config core.hooksPath .githooks`.

**3. `.gitignore` / `.gitattributes`** : ajouter `.env`, `*.pem`, `*.key`,
`*.tfstate`, `*.tfstate.backup`, `crash.log`, `*.retry`, `.terraform/`,
`*.swp`, `*~` ; `.gitattributes` déjà en place (`* text=auto eol=lf`).

**4. Signature SSH**

```bash
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
git config --global tag.gpgsign true
printf 'mathieu@lab.local %s\n' "$(cat ~/.ssh/id_ed25519.pub)" \
  > ~/.ssh/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers
git commit --allow-empty -m "chore: active la signature des commits"
git log -1 --show-signature | head -3
```

```console
Good "git" signature for mathieu@lab.local with ED25519 key SHA256:…
```

`git log --format='%h %G? %s'` : `G` = signature valide, `N` = non signé,
`B` = mauvaise signature, `U` = bonne signature mais signataire inconnu
(pas dans `allowed_signers`).

**5. `pre-receive` sur `lab-adm`** (`/srv/git/factura-infra.git/hooks/`) :

```bash
#!/usr/bin/env bash
# pre-receive — refuse sur main : messages hors convention, fichiers interdits
set -uo pipefail
types='feat|fix|docs|chore|refactor|test|ci|perf|build|revert'
interdits='(^|/)\.env$|\.pem$|\.key$|\.tfstate$|id_rsa|id_ed25519'
rc=0
while read -r ancien nouveau ref; do
  [ "$ref" = refs/heads/main ] || continue
  if [ "$ancien" = 0000000000000000000000000000000000000000 ]; then
    plage=$nouveau; else plage="$ancien..$nouveau"; fi
  while read -r sha sujet; do
    if ! printf '%s' "$sujet" \
         | grep -qE "^($types)(\([^)]+\))?!?: |^(Merge|Revert) "
    then echo "refusé : ${sha:0:7} « $sujet » hors convention" >&2; rc=1; fi
  done < <(git rev-list --no-merges --format='%h %s' "$plage" \
           | grep -v '^commit ')
  if git diff --name-only --diff-filter=A "$ancien" "$nouveau" 2>/dev/null \
     | grep -E "$interdits"; then
    echo "refusé : le push ajoute un fichier interdit (ci-dessus)" >&2; rc=1
  fi
done
exit "$rc"
```

Test depuis un clone : un commit « n'importe quoi » poussé sur `main` →
`! [remote rejected] main -> main (pre-receive hook declined)`, et le
`post-receive` de L21.3 n'est pas exécuté.

**6. Release**

```bash
{ printf '\n## 1.2.0 — %s\n\n' "$(date +%F)"
  git log v1.1.0..HEAD --no-merges --format='* %s (%h)' ; } >> CHANGELOG.md
git commit -am "docs(changelog): 1.2.0"
git tag -s v1.2.0 -m "Version 1.2.0 — gouvernance du dépôt"
git tag -v v1.2.0                     # Good "git" signature …
git push lab-adm main v1.2.0
git push gitea main v1.2.0            # si L21.5
```

**7. Rapport `D21.md`** : GitHub flow (justifié), `--no-ff` pour le revert
atomique, protection de `main` déléguée à Gitea (interface) doublée du
`pre-receive` sur le bare de déploiement (défense en profondeur),
`CODEOWNERS` : `terraform/network* @equipe-reseau`, `ansible/roles/nginx/
@equipe-web`. Rollback : `git switch - -detach v1.1.0` n'est pas un
déploiement — le hook ne réagit qu'à `main` ; la procédure est
`git revert -m 1 <merge>` (ou `revert` de la plage) sur `main`, MR
expresse, push → le hook redéploie ; en urgence absolue, `git push lab-adm
v1.1.0^{commit}:main` avec `receive.denyNonFastForwards` temporairement
désactivé, et un post-mortem. Avec Gitea/GitLab : protection de branche,
approbations, CI obligatoire et `CODEOWNERS` remplacent les hooks maison ;
les hooks de secrets restent côté client (`pre-commit` + `gitleaks`) et
côté CI.

> [!NOTE]
> **Pourquoi**
>
> Chaque contrôle est placé au plus tôt **et** répété au plus tard : le
> `pre-commit` évite à l'auteur de commiter un secret, le `pre-receive` le
> bloque s'il a contourné avec `--no-verify` (les hooks clients sont
> volontaires : `core.hooksPath` doit être activé par chacun, c'est pourquoi
> `CONTRIBUTING.md` le documente et le serveur ne s'y fie pas).
> `pre-receive` reçoit toutes les références du push **avant** toute
> écriture : un `exit 1` refuse tout le push, atomiquement ; `post-receive`
> ne peut plus rien refuser. Le tag signé fige le SHA du commit de release,
> donc tout l'historique en amont : un auditeur qui vérifie `git tag -v
> v1.2.0` a la preuve que rien n'a été réécrit depuis. La signature SSH
> réutilise la clé du module 14 : pas de PGP à gérer, et les forges (Gitea
> 1.17+, GitHub, GitLab) la vérifient. `allowed_signers` est l'équivalent
> local du trousseau : sans lui, `%G?` renvoie `U`, pas `G`.

> [!WARNING]
> **Piège**
>
> `git log v1.1.0..HEAD --format='* %s'` pour le changelog suppose des
> messages conventionnels **depuis** `v1.1.0` : si des `wip` s'y trouvent, le
> changelog les affiche — c'est le moment où l'équipe comprend pourquoi le
> `commit-msg` existe. Et un hook `pre-receive` qui appelle `shellcheck` ou
> lance des tests longs bloque le push de tout le monde : ces contrôles vont
> en CI, le serveur ne garde que les vérifications instantanées.

<!-- nav:début -->
---

[← Module 20](../20-virtualisation-kvm/corrige.md) · [Énoncé](README.md) · [Module 22 →](../22-docker/corrige.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
