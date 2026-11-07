<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Partie I — Fondamentaux du shell et du système de fichiers › **Module 06** · corrigé  
[← Module 05](../05-text-processing/corrige.md) · [Énoncé](README.md) · [Module 07 →](../07-bash-scripting/corrige.md)

> [!TIP]
> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, pas avant. Chaque identifiant renvoie à son énoncé.
<!-- nav:fin -->

# Module 06 — Corrigé

## 6.3 Quiz — QCM

<a id="q6-1"></a>**[Q6.1](README.md#q6-1)** — *Sortir d'un fichier en étant certain de ne rien avoir écrit.*

**Réponse : b) `Esc` puis `:q!`**

> [!NOTE]
> **Pourquoi**
>
> Deux gestes, deux rôles. `Esc` ramène **à coup sûr** en mode normal, quel que
> soit l'état de départ : insertion, remplacement, visuel, visuel bloc, ou
> attente d'un mouvement après un opérateur (`d` seul). Tant que tu n'es pas en
> mode normal, le `:` que tu tapes est du texte, pas une commande.
>
> `:q!` est le seul de la liste qui **abandonne** les modifications. Le `!` dit à
> vim de passer outre l'avertissement `E37: No write since last change`. Le
> tampon est jeté, le fichier sur disque n'a jamais été touché — vim n'écrit que
> sur un `:w` explicite ou implicite.
>
> `ZQ` est le raccourci normal équivalent à `:q!`, et il est plus sûr de le
> connaître : deux touches, pas de `:` à viser.

> [!WARNING]
> **Piège**
>
> `ZZ` (proposition c) **écrit** si le tampon est modifié : c'est l'équivalent de
> `:x`. Deux majuscules côte à côte, un doigt qui glisse, et le fichier de
> production part avec ton texte parasite. `Ctrl-C` (d) interrompt bien le mode
> insertion, mais il ne déclenche pas les traitements de fin d'insertion et ne
> garantit pas de sortir d'un opérateur en attente ; ce n'est pas un `Esc`.

---

<a id="q6-2"></a>**[Q6.2](README.md#q6-2)** — *Curseur sur le `s` de `server_name`* `"ancien-frontal…";`*, on tape `ci`*`"`*.*

**Réponse : b)** vim supprime le contenu entre guillemets et passe en insertion.

> [!NOTE]
> **Pourquoi**
>
> Les objets texte « délimiteurs de citation » (`i"`, `a"`, `i'`, `` i` ``) ne se
> comportent pas comme les objets « blocs » (`i(`, `i{`, `i[`). Pour les
> guillemets, vim **analyse la ligne courante de son début** et apparie les
> citations deux par deux. Si le curseur se trouve avant la première citation de
> la ligne, c'est la première paire de la ligne qui est retenue. D'où le résultat :
>
> ```nginx
>     server_name "";        <- curseur entre les guillemets, mode insertion
> ```
>
> C'est ce qui rend `ci"` si rentable en configuration : tu es n'importe où au
> début de la ligne, tu tapes `ci"`, tu écris la nouvelle valeur. Tu n'as ni
> compté de caractères, ni visé un guillemet.

> [!WARNING]
> **Piège**
>
> L'asymétrie est réelle : `ci(` ou `ci{` depuis l'extérieur du bloc échouent, il
> faut être **dans** le bloc ou sur la parenthèse. Autre limite, `i"` ne franchit
> pas la fin de ligne : sur une chaîne coupée sur deux lignes, il ne trouve rien.

---

<a id="q6-3"></a>**[Q6.3](README.md#q6-3)** — *`:%s/opt/srv/g` pour migrer `/opt/factura` vers `/srv/factura`.*

**Réponse : c)** toute occurrence de la sous-chaîne `opt` est remplacée.

> [!NOTE]
> **Pourquoi**
>
> Une substitution vim travaille sur des **sous-chaînes**, pas sur des mots ni sur
> des chemins. `opt` correspond aussi dans `options`, `optimisation`, `adopter` ou
> `/opt/legacy`. Sur le `factura.conf` du lab, les chemins `/opt/legacy` du
> bloc hérité deviendraient `/srv/legacy` alors qu'on voulait les laisser; sur `deploy.sh`, le commentaire historique serait réécrit lui aussi.
>
> Trois façons d'écrire la bonne commande :
>
> ```vim
> :%s#/opt/factura#/srv/factura#g     " délimiteur alternatif, chemin complet
> :%s/\/opt\/factura/\/srv\/factura/g " même chose en échappant, illisible
> :%s/\<opt\>/srv/g                   " limites de mot : ici insuffisant
> ```
>
> La première est la seule à écrire en production : `:s` accepte **n'importe quel
> caractère** non alphanumérique comme délimiteur, juste après le `s`. Avec des
> chemins, `#` ou `|` évitent la forêt d'antislashs.

> [!WARNING]
> **Piège**
>
> Le `/g` final est souvent oublié : sans lui, `:s` ne remplace que la
> **première** occurrence de chaque ligne. Sur une ligne
> `cp /opt/factura/a /opt/factura/b`, tu obtiens un mélange des deux chemins et un
> script qui casse en production.

---

<a id="q6-4"></a>**[Q6.4](README.md#q6-4)** — *Ne garder que les lignes contenant `ERROR`.*

**Réponses : b) `:v/ERROR/d` et c) `:g!/ERROR/d`**

> [!NOTE]
> **Pourquoi**
>
> `:g` (global) prend une plage (tout le fichier par défaut), un motif, et une
> commande ex. Il fonctionne en **deux temps** : d'abord il parcourt la plage et
> **marque** toutes les lignes qui correspondent ; ensuite seulement il exécute la
> commande sur chaque ligne marquée. C'est ce double passage qui permet à
> `:g/DEBUG/d` de supprimer toutes les lignes voulues alors que chaque suppression
> renumérote le fichier : les marques suivent leur ligne, pas leur numéro.
>
> `:v` est l'abréviation de `:g!`, la version inversée : marque les lignes qui
> **ne** correspondent **pas**. Garder les `ERROR` revient donc à supprimer les
> autres.
>
> `:g/ERROR/d` (a) fait exactement l'inverse : il ne laisse que le bruit.

> [!WARNING]
> **Piège**
>
> `:v/ERROR\|WARN/d` garde les deux motifs — le `\|` de vim s'échappe, contrairement
> à `egrep`. Et attention à l'ordre : si tu fais d'abord `:g/DEBUG/d` puis
> `:v/ERROR/d`, le premier passage ne sert à rien, le second suffisait.

---

<a id="q6-5"></a>**[Q6.5](README.md#q6-5)** — *`ci"nouveau.example.org` `Esc`, puis `3j`, puis `.`.*

**Réponse : b)** vim rejoue `ci"nouveau.example.org` sur la ligne courante.

> [!NOTE]
> **Pourquoi**
>
> `.` rejoue la dernière **modification** du tampon, pas la dernière frappe ni la
> dernière commande. Une modification, pour vim, c'est une unité qui va de
> l'entrée en mode insertion (ou de l'opérateur) jusqu'au retour en mode normal.
> Ici l'unité complète est « change-inner-quote + le texte tapé + `Esc` ».
>
> Les déplacements ne sont jamais des modifications : `3j`, `/motif`, `G` ne sont
> pas mémorisés par `.`. C'est précisément ce qui rend le duo
> « déplacement + `.` » aussi efficace : tu navigues librement entre deux
> répétitions.
>
> Le motif de travail à retenir :
>
> ```text
> /server_name          repérer la première occurrence
> ci"factura.lab.local  corriger
> n                     occurrence suivante
> .                     rejouer
> ```

> [!WARNING]
> **Piège**
>
> `.` **ne rejoue pas** une commande ex. Après `:%s/a/b/`, `.` rejoue la dernière
> modification *normale*, pas la substitution. Pour rejouer une substitution, c'est
> `&` (sur la ligne courante) ou `:%&&` (partout, drapeaux conservés).

---

<a id="q6-6"></a>**[Q6.6](README.md#q6-6)** — *`/etc/factura/frontal.conf` ouvert sans sudo, `:w` répond `E45`.*

**Réponse : c) `:w !sudo tee % > /dev/null` puis `:e!`**

> [!NOTE]
> **Pourquoi**
>
> Il faut lire la commande de droite à gauche. `:w !cmd` (avec une espace avant le
> `!`) n'écrit pas dans un fichier : il envoie **le contenu du tampon sur l'entrée
> standard** de `cmd`. `%` est remplacé par le nom du fichier courant. On demande
> donc à `sudo tee /etc/factura/frontal.conf` d'écrire ce flux à cet emplacement —
> et `tee`, lui, tourne en root. Le `> /dev/null` jette la copie que `tee` renvoie
> sur sa sortie standard, sinon tout le fichier s'affiche dans le terminal.
>
> Après l'opération, le fichier sur disque est à jour mais vim l'ignore : son
> tampon est toujours marqué modifié, et il détecte que le fichier a changé sous
> lui. `:e!` le recharge depuis le disque et efface le drapeau « modifié ».
>
> À noter : `:w!` (a) ne fait que forcer la logique interne de vim ; l'appel
> `write()` part quand même sous ton UID et le noyau refuse. `:set noreadonly`
> (b) retire le garde-fou de vim, et tu tombes alors sur l'erreur suivante,
> `E212: Can't open file for writing — Permission denied`. Le problème n'a jamais
> été vim, il est dans les permissions du fichier.

> [!WARNING]
> **Piège**
>
> La vraie bonne pratique reste `sudoedit` (ou `sudo -e`) : il copie le fichier
> dans un temporaire que tu édites avec **ton** éditeur et tes droits, puis le
> replace en root. `sudo vim` fait tourner vim entier en root, avec ton `.vimrc`
> et tes greffons — une surface d'attaque inutile. Garde `:w !sudo tee %` pour le
> jour où tu as déjà fait vingt minutes de travail.

---

<a id="q6-7"></a>**[Q6.7](README.md#q6-7)** — *Le collage qui part en escalier.*

**Réponse : b)** `autoindent`/`smartindent` ré-indente chaque ligne reçue ;
remède : `:set paste`, coller, `:set nopaste`.

> [!NOTE]
> **Pourquoi**
>
> Un collage à la souris n'a rien de spécial pour vim : le terminal lui envoie les
> caractères **comme si tu les tapais**, très vite. Chaque fin de ligne déclenche
> donc le mécanisme d'auto-indentation, qui ajoute l'indentation de la ligne
> précédente ; par-dessus arrivent les espaces déjà présents dans le texte collé.
> L'indentation se cumule à chaque ligne : c'est l'escalier.
>
> `:set paste` neutralise d'un coup tout ce qui réagit à la frappe :
> `autoindent`, `smartindent`, `cindent`, `expandtab`, `textwidth`, les
> abréviations et les raccourcis du mode insertion. `:set nopaste` remet tout.

> [!WARNING]
> **Piège**
>
> Sur un vim 8.2+ dans un terminal moderne, le *bracketed paste* rend souvent
> `:set paste` inutile : le terminal encadre le collage de séquences d'échappement
> que vim reconnaît. Mais ce n'est pas garanti : `vim -u NONE`, une vieille
> session `screen`, un `TERM` exotique, et l'escalier revient. Connaître
> `:set paste` reste indispensable, et `"+p` (quand vim a `+clipboard`) ne pose
> jamais le problème puisqu'il n'y a pas de frappe simulée.

---

<a id="q6-8"></a>**[Q6.8](README.md#q6-8)** — *`E325: ATTENTION / Found a swap file…`*

**Réponses : a) et c)**

> [!NOTE]
> **Pourquoi**
>
> Dès l'ouverture d'un fichier, vim crée `.nomdufichier.swp` **dans le répertoire
> du fichier** (puis dans `~/tmp`, `/var/tmp` ou `/tmp` si le premier est en lecture
> seule : c'est le défaut de l'option `'directory'`). Il y journalise toutes les modifications non enregistrées, avec le nom
> d'hôte et le PID du processus propriétaire. En sortie propre, il l'efface.
>
> Un swap présent signifie donc l'une de deux choses, et le message te dit
> laquelle : le PID est encore vivant (`process ID: 4711 (still running)`) et une
> autre session édite le fichier ; ou il ne l'est plus, et la session a été tuée,
> le terminal fermé, la machine redémarrée — le swap contient alors du travail
> jamais écrit.
>
> La bonne réflexion, dans l'ordre : y a-t-il un processus vivant ? le swap est-il
> plus récent que le fichier ? que contient-il ? Ensuite seulement on choisit dans
> le menu.

> [!WARNING]
> **Piège**
>
> (b) est faux : le fichier sur disque est parfaitement intact, c'est même tout le
> problème — il ne contient pas les dernières modifications. (d) est l'erreur
> coûteuse : `Delete it` sans regarder jette le travail d'un collègue. Le réflexe
> est `vim -r fichier` puis `:w fichier.recovered`, on compare, **puis** on
> supprime le swap.

---

<a id="q6-9"></a>**[Q6.9](README.md#q6-9)** — *`Ctrl-V`, `29j`, `I`, `#` : que manque-t-il ?*

**Réponse : b) appuyer sur `Esc`**

> [!NOTE]
> **Pourquoi**
>
> En mode visuel bloc, `I` (ou `A`) n'insère d'abord que sur la **première** ligne
> du bloc : vim te laisse taper normalement, tu vois ton `#` sur une seule ligne.
> C'est en quittant l'insertion, par `Esc`, que vim **réplique** le texte inséré
> sur toutes les autres lignes du bloc. Le `Esc` n'est pas une politesse de sortie,
> c'est l'ordre d'exécution.
>
> Le geste complet, appliqué au bloc 39-71 de `factura.conf` (33 lignes) :
>
> ```text
> 39G         aller sur la première ligne à commenter
> Ctrl-V      mode bloc
> 32j         étendre jusqu'à la dernière
> I #  Esc    insérer en tête de bloc, puis propager
> ```
>
> Pour décommenter : `Ctrl-V`, `32j`, `x` (ajoute `l` avant `x` seulement si tu avais inséré `#`, dièse et espace).

> [!WARNING]
> **Piège**
>
> `i` (minuscule) en visuel bloc n'est pas une insertion : c'est le début d'un
> objet texte (`i{`, `iw`). C'est `I` qu'il faut. Et si les lignes n'ont pas
> toutes la même longueur, `A` en fin de bloc se comporte différemment de
> `$A` : avec `$`, le bloc s'étend jusqu'à la fin de **chaque** ligne, ce qui est
> presque toujours ce que tu veux.

---

<a id="q6-10"></a>**[Q6.10](README.md#q6-10)** — *`tar -czf /tmp/srv.tgz /srv/factura`, puis extraction depuis `/tmp`.*

**Réponse : b) dans `/tmp/srv/factura/`**

> [!NOTE]
> **Pourquoi**
>
> `tar` refuse par défaut de stocker des chemins absolus : il retire le `/` initial
> et le dit (`Removing leading '/' from member names`). Les membres de l'archive
> s'appellent donc `srv/factura/app/...`, en **relatif**.
>
> À l'extraction, `tar` reconstruit ces chemins relatifs à partir du répertoire
> courant. Depuis `/tmp`, on obtient `/tmp/srv/factura/...`. Ce n'est presque
> jamais ce qu'on voulait, et c'est ce qui fait qu'une restauration « ne marche
> pas » alors que l'archive est parfaite.
>
> La forme correcte pour une archive restaurable où on veut :
>
> ```bash
> tar -czf /tmp/factura.tgz -C /srv factura      # membres : factura/...
> tar -xzf /tmp/factura.tgz -C /srv              # restaure /srv/factura
> ```
>
> `-C` change de répertoire **avant** d'agir, et il peut apparaître plusieurs fois
> dans la même ligne, chaque occurrence s'appliquant aux arguments qui suivent.

> [!WARNING]
> **Piège**
>
> `--absolute-names` (`-P`) désactive ce garde-fou et stocke les `/`. Une archive
> faite ainsi, extraite par mégarde en root, écrase `/etc` sans prévenir. On ne
> l'utilise jamais « pour que ce soit plus simple ». Si tu reçois une archive
> inconnue, `tar -tf` **avant** `tar -xf`, toujours.

---

<a id="q6-11"></a>**[Q6.11](README.md#q6-11)** — *Extraction non privilégiée : les fichiers root deviennent `mathieu`.*

**Réponses : b) et c)**

> [!NOTE]
> **Pourquoi**
>
> L'archive contient bien les propriétaires, `tar` les stocke toujours — la
> réponse a) est fausse, et il suffit d'un `tar -tvf` pour le voir.
>
> Ce qui se passe est une règle du noyau, pas de `tar` : **seul root peut donner
> un fichier à un autre utilisateur** (`chown` vers un UID tiers). Un utilisateur
> ordinaire qui extrait ne peut donc créer que des fichiers lui appartenant.
>
> GNU tar formalise cela avec `--same-owner`, actif par défaut **uniquement quand
> on est root**, et `--no-same-owner`, le défaut pour tout le monde. Idem pour les
> modes : `-p` (`--preserve-permissions`) est implicite en root, et `umask`
> s'applique pour les autres.
>
> La recette d'une restauration fidèle :
>
> ```bash
> sudo tar -xzpf factura.tgz --numeric-owner -C /srv
> ```
>
> `--numeric-owner` dit d'utiliser les UID/GID **numériques** stockés, sans passer
> par les noms. C'est indispensable quand la machine de restauration n'a pas les
> mêmes comptes : sans lui, `tar` cherche l'utilisateur `factura` dans
> `/etc/passwd` et, s'il existe avec un autre UID, tes fichiers changent de
> propriétaire en silence.

> [!WARNING]
> **Piège**
>
> La réponse d) inverse la logique : `-p` ne sert à rien à la **création**, les
> modes sont toujours enregistrés. `-p` s'emploie à l'**extraction**, et seulement
> pour un utilisateur non root, où il demande d'ignorer l'`umask`.

---

<a id="q6-12"></a>**[Q6.12](README.md#q6-12)** — *`tar` renvoie 1 avec `file changed as we read it`.*

**Réponse : b)** l'archive existe mais au moins un fichier y est incohérent.

> [!NOTE]
> **Pourquoi**
>
> Les codes de retour de `tar` sont une échelle à trois niveaux :
>
> | Code | Sens |
> |---|---|
> | 0 | tout s'est bien passé |
> | 1 | avertissement non fatal : une différence, un fichier modifié pendant la lecture |
> | 2 | erreur fatale : archive illisible, écriture impossible, disque plein |
>
> Le message précis vient d'un contrôle de `tar` : avant de lire un fichier il
> note sa taille et son horodatage, après lecture il les compare. S'ils ont bougé,
> ce qu'il vient d'écrire dans l'archive est un mélange de deux états — les
> premiers blocs d'avant l'écriture, les derniers d'après.
>
> L'archive reste exploitable, et les autres fichiers sont corrects. Mais le
> fichier concerné peut être tronqué, dupliqué ou incohérent. Pour un journal, on
> s'en moque. Pour un fichier de données d'une base ou une image disque, c'est une
> sauvegarde qui ne se restaure pas.

> [!WARNING]
> **Piège**
>
> Beaucoup de scripts de sauvegarde se terminent par `tar ... || alerte`. Avec
> `set -e` et une source vivante, ils alertent toutes les nuits, tout le monde
> s'habitue à l'alerte, et le jour où le code passe à 2 personne ne regarde. Teste
> le code précisément : `rc=$?; [ "$rc" -le 1 ] || alerte`.

---

<a id="q6-13"></a>**[Q6.13](README.md#q6-13)** — *`rsync -a /src /dst/` contre `rsync -a /src/ /dst/`.*

**Réponse : b)** la première crée `/dst/src/`, la seconde déverse le contenu.

> [!NOTE]
> **Pourquoi**
>
> Le modèle mental qui ne trompe jamais : **la barre oblique finale à la source
> signifie « le contenu de », son absence signifie « ce répertoire »**. La
> destination, elle, est toujours traitée comme un répertoire d'accueil ; son
> slash ne change rien.
>
> ```text
> rsync -a /src  /dst/   ->  /dst/src/fichiers...
> rsync -a /src/ /dst/   ->  /dst/fichiers...
> ```
>
> L'analogie utile est `cp` : `rsync -a /src /dst/` se comporte comme
> `cp -a /src /dst/`, et `rsync -a /src/ /dst/` comme `cp -a /src/. /dst/`.

> [!WARNING]
> **Piège**
>
> Combine l'oubli du slash avec `--delete` et tu obtiens l'incident classique :
> la destination reçoit un sous-répertoire de plus, et `--delete` efface tout ce
> qui existait à la racine parce que « ça n'est plus à la source ». C'est le
> BF6.3 du module. Deux protections : `--dry-run` systématique avant un
> `--delete`, et l'habitude de toujours écrire les deux chemins avec un slash
> final quand on synchronise des contenus.

---

<a id="q6-14"></a>**[Q6.14](README.md#q6-14)** — *Première commande à taper pour une synchro avec `--delete`.*

**Réponse : b) `rsync -an --delete ~/site/ mathieu@10.10.10.11:/var/www/site/`**

> [!NOTE]
> **Pourquoi**
>
> `-n` (`--dry-run`) fait tout le travail de comparaison et affiche exactement ce
> qui serait transféré et supprimé, sans toucher un octet. C'est la seule façon de
> voir la liste des suppressions **avant** qu'elles n'arrivent. Avec `-v` en plus,
> la sortie se lit ligne à ligne ; les suppressions y apparaissent préfixées de
> `deleting`.
>
> La commande a) est la bonne commande, mais en second. La c) inverse source et
> destination : elle écraserait ton répertoire de travail avec le contenu du
> serveur, et `--delete` y ferait le ménage. La d) ne sait ni supprimer, ni
> comparer, et `*` ne prend pas les fichiers cachés.

> [!WARNING]
> **Piège**
>
> `--dry-run` ne dit pas toute la vérité sur les tailles transférées (rsync ne
> peut pas connaître le résultat du delta sans l'exécuter), mais la **liste** des
> fichiers touchés et supprimés, elle, est exacte. C'est ce qu'on vient vérifier.

---

<a id="q6-15"></a>**[Q6.15](README.md#q6-15)** — *Sauvegarde du mardi avec `--link-dest=../lundi`.*

**Réponse : b)** `du -sh` affiche environ 10 Go, l'espace consommé en plus est
d'environ 100 Mo.

> [!NOTE]
> **Pourquoi**
>
> `--link-dest` compare chaque fichier de la source avec son homologue dans le
> répertoire de référence. S'il est identique (taille, date, et permissions),
> rsync ne le copie pas : il crée un **lien dur** vers l'inode du fichier de
> lundi. Un lien dur n'est pas un raccourci, c'est un second nom pour les mêmes
> blocs de données. Le fichier n'existe donc qu'une fois sur le disque, mais il
> apparaît dans les deux arborescences, avec ses droits et sa date.
>
> Résultat : `~/backup/mardi/` est une arborescence **complète**, parcourable et
> restaurable telle quelle, qui n'occupe en propre que les fichiers modifiés.
>
> ```bash
> du -sh ~/backup/mardi                  # ~10 Go : mesuré seul, tout est compté
> du -sh --total ~/backup/lundi ~/backup/mardi  # ~10,1 Go : du ne compte
>                                               # l'inode partagé qu'une fois
> stat -c '%h %n' ~/backup/mardi/un/fichier/inchange   # 2 liens
> ```
>
> C'est le principe de Time Machine et de `rsnapshot`.

> [!WARNING]
> **Piège**
>
> Deux pièges de production. D'abord, modifier un fichier **dans** une sauvegarde
> ancienne modifie toutes les sauvegardes qui le partagent : un répertoire de
> sauvegarde se monte en lecture seule ou ne se touche pas. Ensuite, le nombre de
> liens durs a une limite (65 000 sur ext4, par inode) : une rotation de plusieurs
> milliers de sauvegardes finit par la heurter.

---

<a id="q6-16"></a>**[Q6.16](README.md#q6-16)** — *Vérifier des morceaux `split` à l'arrivée.*

**Réponses : a) et c)**

> [!NOTE]
> **Pourquoi**
>
> La seule preuve solide est la **somme de contrôle cryptographique de l'objet
> reconstitué**. On concatène dans l'ordre, puis on vérifie :
>
> ```bash
> cat part.* > sauve.tar.zst          # le glob trie en ordre alphabétique
> sha256sum -c sauve.tar.zst.sha256   # -> sauve.tar.zst: OK
> ```
>
> `zstd -t` (ou `gzip -t`) est un second contrôle, d'une autre nature : il
> décompresse le flux en mémoire et vérifie les CRC internes du format. Il prouve
> que le fichier est un flux compressé cohérent et complet ; il ne prouve pas que
> c'est **le bon** fichier. Les deux contrôles sont complémentaires.
>
> Comparer les tailles (b) ne prouve rien : un octet retourné en route donne
> exactement la même taille. Et `tar -tf part.aa` (d) ne peut pas fonctionner :
> un morceau n'est pas une archive, c'est une tranche d'octets.

> [!WARNING]
> **Piège**
>
> `cat part.*` dépend de l'ordre alphabétique des noms. Les suffixes par défaut de
> `split` (`aa`, `ab`, … `az`, `ba`) et ceux de `-d` (`00`, `01`, …) sont conçus
> pour que ce tri soit le bon — tant qu'on ne dépasse pas le nombre de suffixes
> prévu, d'où `-a 3` pour les très gros découpages. Un nom fait à la main du genre
> `part.1 … part.10` casse tout : `part.10` se trie avant `part.2`.

---

<a id="q6-17"></a>**[Q6.17](README.md#q6-17)** — *40 Go de journaux, 8 cœurs, meilleur taux possible, durée libre.*

**Réponse : c) `xz -9 -T0`**

> [!NOTE]
> **Pourquoi**
>
> `xz` (algorithme LZMA2) donne le meilleur taux des quatre sur du texte, souvent
> d'un facteur 2 à 5 par rapport à `gzip`, au prix d'un temps et d'une mémoire
> très supérieurs. `-9` pousse le niveau au maximum, `-T0` utilise tous les cœurs
> disponibles — sans lui, `xz` reste monothread, ce qui est la première cause de
> sauvegardes qui débordent de leur fenêtre.
>
> Ordre de grandeur relevé sur `lab-adm`, sur une archive de 3,8 Mio de journaux
> très répétitifs :
>
> | Outil | Taille | Temps |
> |---|---|---|
> | `gzip -6` | 181 160 o | 0,02 s |
> | `gzip -9` | 175 135 o | 0,05 s |
> | `bzip2 -9` | 54 757 o | 0,96 s |
> | `xz -9` | 6 960 o | 0,73 s |
>
> `bzip2` (b) est le mauvais choix de 2026 : plus lent que `xz` **et** moins
> efficace. `zstd -1` (d) est l'inverse du besoin exprimé : extrêmement rapide,
> taux moyen.

> [!WARNING]
> **Piège**
>
> Le critère oublié est la **décompression**. `xz` décompresse lentement ; le jour
> de la restauration, en cellule de crise, cela compte. C'est pour ça que `zstd`
> s'est imposé en sauvegarde quotidienne : `zstd -19` approche `xz` côté taux, se
> compresse bien plus vite et décompresse d'un ordre de grandeur plus rapidement.
> Règle simple : `zstd` pour ce qu'on restaure, `xz` pour ce qu'on entrepose.

---

<a id="q6-18"></a>**[Q6.18](README.md#q6-18)** — *Envoyer une arborescence à un collègue sous Windows en `zip`.*

**Réponse : b)** `zip` ne conserve ni propriétaires ni liens symboliques, et ses
permissions ne sont pas restituées par l'explorateur Windows.

> [!NOTE]
> **Pourquoi**
>
> `zip` compresse chaque fichier **individuellement** puis les assemble, là où
> `tar` assemble d'abord et compresse le flux entier (d'où son meilleur taux sur
> beaucoup de petits fichiers, et d'où l'impossibilité d'extraire un seul fichier
> d'un `.tar.gz` sans le parcourir).
>
> Son format enregistre un champ « attributs externes » où les outils Unix glissent
> le mode POSIX, mais rien n'oblige un extracteur à le respecter, et l'explorateur
> Windows ne le fait pas. Les propriétaires (UID/GID) ne figurent que dans un champ d'extension propre à Info-ZIP, que seul `unzip` lancé en root restitue et que Windows ignore. Les liens
> symboliques ne sont conservés que par certaines implémentations, et pas par
> l'extracteur intégré de Windows — ils arrivent en fichiers texte contenant le
> chemin, ou suivis et dupliqués.
>
> Pour une livraison à un poste Windows, `zip -r livraison.zip dossier/` reste le
> bon choix pratique ; il faut simplement savoir ce qu'on perd, et ne jamais s'en
> servir pour une sauvegarde système.

> [!WARNING]
> **Piège**
>
> `zip` traverse les liens symboliques par défaut (`-y` les conserve, quand
> l'implémentation le permet) : une arborescence contenant un lien vers `/` se
> transforme en archive gigantesque. Même famille de problème que `tar -h`.

---

## 6.4 Quiz — questions ouvertes

<a id="qo6-1"></a>**[QO6.1](README.md#qo6-1)** — *Pourquoi imposer vim à une équipe qui ne jure que par VS Code ?*

**Réponse attendue** — trois arguments d'exploitation, pas de confort :

1. **Disponibilité**. `vi` est le seul éditeur plein écran garanti par POSIX, présent sur
   toute installation, y compris minimale. En cellule de crise sur une machine
   sans réseau, dans un conteneur de dépannage, sur une appliance, dans un
   initramfs ou un shell de secours, `nano` peut manquer, `vi` non.
2. **Édition à travers un lien lent ou instable**. Un éditeur graphique distant
   (SSHFS, greffon Remote) synchronise en permanence : sur une liaison à 400 ms
   de latence ou qui coupe, il devient inutilisable, et pire, il peut écrire un
   fichier à moitié. Vim ne transmet que des touches.
3. **Traitement de masse sans outil externe**. `:g`, `:v`, `:%s` et le visuel
   bloc font en une commande ce qui demanderait un script `sed`/`awk` à écrire,
   tester et relire — sur un fichier de production, avec un aperçu avant
   validation grâce à `gc`.

Deux situations où aucun autre éditeur n'est disponible : un système démarré en
mode secours (`rescue.target`) pour réparer `/etc/fstab` ; un conteneur
Alpine ou BusyBox, ou une VM cloud minimale, où seul `busybox vi` existe.

> [!NOTE]
> **Pourquoi**
>
> La bonne réponse en entretien ne dit jamais « c'est plus rapide quand on sait ».
> Elle raisonne en **disponibilité de l'outil** et en **risque**. Le corollaire
> honnête, qu'il faut assumer : on n'impose pas vim pour développer, on impose de
> savoir s'en servir pour exploiter. Le seuil utile est bas — modes, `:wq`,
> `/motif`, `dd`, `u`, `:%s` — et s'acquiert en une heure.

---

<a id="qo6-2"></a>**[QO6.2](README.md#qo6-2)** — *Mécanisme de `:g/motif/normal A;` et robustesse de `:g/DEBUG/d`.*

**Réponse attendue** :

`:[plage]g/motif/commande` se déroule en **deux passes** :

1. vim parcourt la plage (le fichier entier par défaut) **une seule fois**, du
   début vers la fin, et pose une marque interne sur chaque ligne dont le motif
   correspond. Aucune modification n'a lieu pendant cette passe ;
2. il exécute ensuite la commande ex sur chaque ligne marquée, dans l'ordre. Le
   curseur est positionné sur la ligne avant chaque exécution.

`normal` est une commande ex qui exécute des touches comme si tu les tapais en
mode normal. `A;` ajoute `;` en fin de ligne et `Esc` est implicite à la fin de
chaque exécution de `:normal`.

`:g/DEBUG/d` ne saute aucune ligne parce que les marques de la première passe
suivent le **contenu** des lignes, pas leur numéro : quand la ligne 10 est
supprimée, la ligne marquée qui était en 11 devient la 10, et vim la retrouve
par sa marque. C'est exactement ce qu'une boucle naïve
« pour i de 1 à n, si ligne i correspond, supprimer » raterait une fois sur deux.

> [!NOTE]
> **Pourquoi**
>
> Ce mécanisme explique aussi pourquoi `:g` est le bon outil pour des
> transformations en lot, et pourquoi la commande exécutée peut elle-même déplacer
> du texte : `:g/^ERROR/m$` déplace toutes les lignes d'erreur en fin de fichier,
> dans leur ordre d'origine, et `:g/motif/t.` duplique chaque ligne trouvée. Le
> couple `:g` + `normal` transforme vim en processeur de flux sur le tampon, sans
> fichier temporaire ni pipeline.

> [!WARNING]
> **Piège**
>
> `:normal` termine de lui-même une insertion restée ouverte (comme un `Esc`) : `:g/x/normal A;` suffit, rien ne déborde sur la ligne suivante. Le vrai piège est double. `:normal` ne comprend pas la notation `<Esc>` : pour enchaîner d'autres touches après une insertion, il faut `:exe "normal A;\<Esc>j"`. Et `:normal` subit
> les remappages de l'utilisateur : dans un script, on écrit `:normal!`.

---

<a id="qo6-3"></a>**[QO6.3](README.md#qo6-3)** — *« vim m'affiche un pavé rouge à chaque ouverture de nginx.conf ».*

**Réponse attendue** :

Le fichier en cause est un **fichier d'échange** (*swap*),
`/etc/nginx/.nginx.conf.swp`. Vim le crée à l'ouverture de tout fichier, y
journalise en continu les modifications non enregistrées, et l'efface en sortie
normale. Sa présence signifie que la sortie n'a pas été normale, ou qu'une autre
session est en cours.

Trois questions avant de choisir dans le menu :

1. **Un processus vit-il encore ?** Le message donne le PID et précise
   `(still running)`. Vérifier : `ps -fp <pid>`, et ne rien faire d'autre avant
   d'avoir parlé à son propriétaire (`w`, `who`).
2. **Le swap est-il plus récent que le fichier ?** `ls -l --time-style=full-iso`
   sur les deux. Si le swap est plus récent, il contient du travail non écrit.
3. **Que contient-il ?** C'est la seule question qui décide vraiment.

Procédure de récupération complète :

```bash
ls -la /etc/nginx/.nginx.conf.sw?          # repérer le ou les swaps
sudo vim -r /etc/nginx/nginx.conf          # ouvre le tampon reconstruit
:w /tmp/nginx.conf.recovered               # on l'écrit ailleurs, jamais
:q                                         #   par-dessus l'original
diff -u /etc/nginx/nginx.conf /tmp/nginx.conf.recovered
# on décide ce qu'on garde, on l'applique, PUIS seulement :
sudo rm /etc/nginx/.nginx.conf.swp
```

> [!NOTE]
> **Pourquoi**
>
> L'ordre compte : on extrait d'abord, on compare ensuite, on supprime en dernier.
> `vim -r` sans argument liste tous les swaps trouvés dans les répertoires
> connus, ce qui sert quand on ne sait plus quel fichier était en cours d'édition.
> Le swap est un format binaire propre à vim ; `strings` permet d'en tirer le texte
> en urgence, mais `vim -r` reconstruit l'ordre des lignes, ce que `strings` ne
> fait pas.

> [!WARNING]
> **Piège**
>
> Sur un serveur, le vrai danger est le swap laissé dans `/etc` par un `sudo vim`
> tué. Il porte les droits de root, reste indéfiniment, et le message effraie
> chaque collègue qui ouvre le fichier ensuite. La parade durable est un
> `~/.vimrc` qui centralise swaps et sauvegardes :
> `set directory=~/.vim/swap//` (le double slash encode le chemin complet dans le
> nom, évitant les collisions).

---

<a id="qo6-4"></a>**[QO6.4](README.md#qo6-4)** — *Pourquoi `tar -czf sauvegarde.tgz /srv/factura` peut mentir.*

**Réponse attendue** :

`tar` parcourt l'arborescence **séquentiellement** et lit chaque fichier l'un
après l'autre, sans aucune notion de transaction. Sur 40 Go, la lecture prend
plusieurs minutes. Pendant ce temps l'application continue : elle écrit, crée,
supprime, renomme.

Conséquences concrètes :

* un fichier lu au début et un fichier lu à la fin reflètent **deux instants
  différents** : l'archive contient un état qui n'a jamais existé ;
* un fichier modifié pendant sa propre lecture est incohérent en interne :
  `tar` le signale (`file changed as we read it`) et sort en 1 ;
* un fichier supprimé après que `tar` l'a listé mais avant de le lire produit
  `File removed before we read it`, également en code 1 ;
* pour une base de données, c'est rédhibitoire : les fichiers de données et le
  journal de transactions sont lus à des instants différents, et la base
  restaurée peut refuser de démarrer.

Trois façons d'obtenir une sauvegarde cohérente :

1. **Arrêter l'application** le temps de l'archivage. Cohérence parfaite,
   indisponibilité proportionnelle à la taille — inacceptable au-delà de
   quelques dizaines de Go.
2. **Utiliser l'outil de sauvegarde applicatif** : `pg_dump` pour PostgreSQL,
   `mysqldump --single-transaction`, l'API de sauvegarde du produit. La
   cohérence est garantie par le moteur lui-même, sans arrêt de service. C'est
   la bonne réponse pour toute donnée gérée par un service.
3. **Figer le système de fichiers** le temps de la copie, par un instantané de
   volume (LVM, ZFS, un instantané de disque côté hyperviseur). L'archivage se
   fait alors sur l'instantané, immobile. Coût : de l'espace, une baisse de
   performance tant qu'il vit, et la nécessité de le détruire ensuite.

> [!NOTE]
> **Pourquoi**
>
> La question qu'il faut savoir poser : « ces données appartiennent-elles à un
> processus vivant ? ». Du code déployé et des fichiers déposés par des
> utilisateurs tolèrent très bien un `tar` à chaud. Une base, une file de
> messages, un dépôt d'index : jamais. La plupart des sauvegardes de production
> combinent les approches — dump applicatif pour la base, `tar`/`rsync` pour les
> fichiers, les deux horodatés pour être recollés à la restauration.

> [!WARNING]
> **Piège**
>
> `--exclude` sur les fichiers volatils (sockets, PID, caches) réduit le bruit
> mais ne règle rien sur le fond : il rend seulement le code retour plus propre,
> ce qui fait croire à une sauvegarde saine. Ne jamais confondre « `tar` a fini en
> 0 » avec « la sauvegarde est cohérente ».

---

<a id="qo6-5"></a>**[QO6.5](README.md#qo6-5)** — *400 Go sur une liaison qui coupe toutes les 20 minutes.*

**Réponse attendue** : `rsync`, sans hésiter.

```bash
rsync -aAX --partial --progress --timeout=60 \
      -e 'ssh -o ServerAliveInterval=15' \
      /donnees/ mathieu@10.10.10.11:/donnees/
```

Justification en trois points :

1. `rsync` est **reprenable**. Il compare source et destination avant de
   transférer : après une coupure, il repart de l'état réel et ne renvoie que ce
   qui manque. `--partial` conserve en plus le fragment du fichier en cours, si
   bien qu'un fichier de 40 Go coupé à 90 % ne recommence pas à zéro.
2. Il est **idempotent** : on peut relancer la même commande autant de fois que
   nécessaire, dans une boucle, jusqu'à ce qu'elle sorte en 0.
3. Il **préserve** droits, dates, liens, et avec `-A`/`-X` les ACL et attributs
   étendus, ce que `scp` ne sait pas faire.

`scp` transfère fichier par fichier, sans état, sans reprise : une coupure à
399 Go recommence tout. `sftp` sait reprendre (`reget`/`reput`) mais fichier par
fichier, manuellement, sans comparaison d'arborescence. Aucun des deux ne
convient.

> [!NOTE]
> **Pourquoi**
>
> Le point que peu de candidats mentionnent, et qui fait la différence : la boucle
> de reprise. En production on écrit
>
> ```bash
> until rsync -aAX --partial --info=progress2 /donnees/ srv:/donnees/; do
>   echo "coupure, reprise dans 30 s" >&2; sleep 30
> done
> ```
>
> Et on vérifie à l'arrivée avec un `rsync -avn --checksum` qui doit ne rien
> proposer. `--checksum` est coûteux, mais c'est la seule vérification qui ne
> repose pas sur les tailles et les dates.

> [!WARNING]
> **Piège**
>
> `-z` est un réflexe à interroger. Sur du texte à travers un lien WAN lent, il
> divise le temps par trois. Sur des données déjà compressées (images, vidéos,
> archives) ou en réseau local à 1 Gb/s, il ne fait que saturer le CPU et ralentir
> le transfert. `scp`, quant à lui, 
> s'appuie sur SFTP depuis OpenSSH 9.0 (le protocole scp historique est déprécié) : cela corrige ses failles, pas son absence de reprise.

---

<a id="qo6-6"></a>**[QO6.6](README.md#qo6-6)** — *La barre oblique finale de `rsync`.*

**Réponse attendue** :

Modèle mental : à la **source**, un slash final veut dire « le contenu de ce
répertoire », son absence veut dire « ce répertoire lui-même ». La destination
est toujours un contenant ; son slash n'a aucun effet.

```text
rsync -a /srv/site  /var/www/     ->  /var/www/site/index.html
rsync -a /srv/site/ /var/www/     ->  /var/www/index.html
```

Incident plausible : le job de nuit synchronise `/srv/site` (sans slash) vers
`/var/www/factura/` avec `--delete`. Résultat : rsync crée
`/var/www/factura/site/` et considère que tout ce qui se trouvait à la racine de
`/var/www/factura/` n'existe pas à la source — donc `--delete` le supprime. Le
site répond 404 : la racine servie par nginx est vide, et le contenu est un
niveau trop bas.

Comment l'éviter :

* `--dry-run` avant tout premier passage et avant toute modification du job ;
* écrire les deux chemins avec un slash final quand on synchronise des contenus,
  et en faire une règle d'équipe relue en revue de code ;
* préférer `--delete-after` sur une cible servie en production : les
  suppressions ont lieu une fois les transferts réussis, ce qui évite de vider
  la cible si le transfert échoue en cours de route.

> [!NOTE]
> **Pourquoi**
>
> La racine du malentendu est que la règle de rsync est copiée sur celle de `cp`,
> mais que la plupart des gens n'ont jamais eu à la formuler pour `cp` non plus —
> ils tapent `cp -r a/ b/` ou `cp -r a b/` au hasard et le résultat leur convient
> parce qu'il n'y a pas de `--delete` derrière. C'est `--delete` qui transforme
> une nuance de confort en incident de production.

---

<a id="qo6-7"></a>**[QO6.7](README.md#qo6-7)** — *`--link-dest` contre une copie complète quotidienne.*

**Réponse attendue** :

| Critère | Copie complète | `--link-dest` |
|---|---|---|
| Mécanisme | recopie tous les octets | lien dur si le fichier n'a pas changé |
| Espace pour 7 jours | 7 × la taille | 1 × la taille + les deltas |
| Temps de sauvegarde | proportionnel à la taille | proportionnel aux changements |
| Restauration | copie directe du répertoire | **identique** : chaque jour est complet |

Le point fort est là : contrairement à une sauvegarde incrémentale classique
(qui exige de rejouer la pleine puis toutes les incrémentales), chaque
répertoire produit par `--link-dest` est une arborescence **complète** et
parcourable. Restaurer un fichier du 12, c'est `cp backup/2026-09-12/le/fichier`.

Trois pièges :

1. `du -sh` sur un seul répertoire annonce la taille pleine : il compte les
   fichiers qu'il voit, sans savoir qu'ils sont partagés. Seul `du -sh --total`
   sur l'ensemble, ou `du -sh` sur la racine des sauvegardes, donne l'occupation
   réelle. On croit avoir 70 Go, on en a 11.
2. **Modifier un fichier dans une sauvegarde ancienne le modifie partout** :
   l'inode est partagé. Un `sed -i` ou un `chmod` dans un répertoire de
   sauvegarde contamine tous les jours qui partagent ce fichier. Les répertoires
   de sauvegarde se montent en lecture seule.
3. La comparaison se fait sur taille + date + droits, pas sur le contenu (sauf
   `--checksum`). Un fichier réécrit à l'identique avec une date préservée est
   considéré inchangé, et un fichier dont seuls les droits changent est
   recopié entièrement.

> [!NOTE]
> **Pourquoi**
>
> Un lien dur est simplement une entrée de répertoire de plus pointant sur le même
> inode. Le compteur de liens de l'inode (`stat -c %h`) passe à 2, 3, 7. Les
> données ne sont libérées que lorsque le dernier nom disparaît : supprimer la
> sauvegarde de lundi ne détruit donc rien tant que mardi en partage les fichiers.
> C'est ce qui rend la rotation sûre et instantanée — un `rm -rf` sur le plus vieux
> répertoire ne libère que ce qui lui était propre.

---

<a id="qo6-8"></a>**[QO6.8](README.md#qo6-8)** — *Que sauvegarder sur un serveur applicatif.*

**Réponse attendue** :

| Élément | Décision | Justification |
|---|---|---|
| Base PostgreSQL | **oui**, par `pg_dump` | seule méthode cohérente à chaud |
| Fichiers déposés | **oui** | irremplaçables, non reproductibles |
| `/etc` du service | **oui** | c'est la configuration réelle, pas celle du dépôt |
| Code déployé | selon | si le déploiement est reproductible depuis Git + CI, non |
| Journaux | **non** (ou archivés à part) | volumineux, faible valeur, rotation propre |
| Caches, `node_modules`, `var/tmp` | **non** | régénérables, gros, bruyants |
| Sockets, PID, `/proc`, `/sys` | **non** | n'ont aucun sens hors du processus vivant |

Rotation simple et défendable : 7 quotidiennes, 4 hebdomadaires, 12 mensuelles.
La règle 3-2-1 reste la référence : 3 copies, sur 2 supports différents, dont 1
hors site. Une copie sur le serveur sauvegardé ne compte pas.

« Une sauvegarde jamais restaurée n'existe pas » : tant que tu n'as pas restauré,
tu ne sais pas si l'archive est complète, si elle est lisible, si tu possèdes
encore la clé de déchiffrement, si la procédure est écrite, combien de temps
elle prend, ni si quelqu'un d'autre que toi sait l'exécuter. Tu ne détiens pas
une sauvegarde, tu détiens une hypothèse. La restauration se teste
périodiquement, sur une machine vierge, chronomètre en main, en suivant la
procédure écrite — et c'est le test qui met à jour la procédure.

> [!NOTE]
> **Pourquoi**
>
> La question sépare deux notions confondues en permanence : la **sauvegarde**
> (revenir à un état antérieur : erreur humaine, corruption, rançongiciel) et la
> **redondance** (rester disponible : RAID, réplication). Un RAID miroir réplique
> instantanément la suppression accidentelle ; ce n'est donc pas une sauvegarde.
> De même, un instantané stocké sur le même volume que les données disparaît avec
> le volume.

> [!WARNING]
> **Piège**
>
> Les deux oublis les plus coûteux, constatés en vrai : les **secrets** (clés,
> certificats, jetons) qui ne sont ni dans Git ni dans la sauvegarde parce que
> « c'est sensible », et la **liste des paquets installés** plus les
> personnalisations manuelles de `/etc`, qui transforment une restauration de
> deux heures en reconstruction de deux jours.

---

## 6.5 Exercices guidés

<a id="e6-1"></a>**[E6.1](README.md#e6-1)** — *Déplacements, marques, premières suppressions dans `notes.txt`.*

```text
:87        ou  87G         aller à la ligne 87
ma                         poser la marque a
G                          fin du fichier
`a                         revenir à la marque, colonne exacte
``                         revenir à la position précédente (avant le saut)
/INCIDENT   puis  n  n     les trois occurrences
:42                        aller ligne 42
d3w                        supprimer les trois mots suivants
u                          annuler
Ctrl-R                     refaire
d/—<Entrée>                supprimer jusqu'avant le tiret cadratin
df—                        supprimer jusqu'au tiret cadratin inclus
```

`` `a `` va à la marque **à la colonne exacte** où elle a été posée ; `'a` va au
**premier caractère non blanc** de cette ligne. Même distinction pour
`` `` '`et`'''.

> [!NOTE]
> **Pourquoi**
>
> Les marques minuscules (`a`–`z`) sont locales au tampon, les majuscules
> (`A`–`Z`) sont globales et pointent un fichier : `mA` dans `nginx.conf` puis
> `` `A `` depuis n'importe quel autre fichier rouvre `nginx.conf` à cet endroit.
> Deux marques sont posées automatiquement et valent de l'or : `` `. `` (dernière
> modification) et `` `" `` (position à la dernière fermeture du fichier).
>
> Sur la suppression : `d` est un opérateur, il attend un **mouvement** qui définit
> l'étendue. `d3w` et `3dw` donnent le même résultat, les compteurs se multiplient.
> `f` (*find*) et `t` (*till*) diffèrent d'un caractère : `df—` inclut le tiret,
> `dt—` s'arrête juste avant.

> [!WARNING]
> **Piège**
>
> `d/motif` supprime jusqu'**avant** la première occurrence, en mode exclusif. Pour
> inclure le motif : `d/motif/e`. Et `dw` sur le dernier mot d'une ligne ne
> supprime pas le saut de ligne, alors que `dW`, `d$` ou `D` se comportent
> différemment encore — c'est pourquoi `daw` (objet texte) est plus prévisible que
> `dw` pour « supprimer ce mot ».

---

<a id="e6-2"></a>**[E6.2](README.md#e6-2)** — *`ci"` puis répétition sur le second bloc.*

```text
/server_name<Entrée>       aller à la première occurrence
ci"factura.lab.local<Esc>  remplacer l'intérieur des guillemets
n                          occurrence suivante
.                          rejouer la même modification
```

> [!NOTE]
> **Pourquoi**
>
> Le second `server_name` du fichier n'a pas de guillemets
> (`server_name legacy.example.org;`) : `ci"` n'y trouve pas de paire et ne fait
> rien — vim émet un bip et laisse la ligne intacte. C'est le bon comportement à
> observer : un objet texte qui ne trouve pas son délimiteur **abandonne**, il
> n'endommage rien. Pour cette ligne, c'est `ciw` (sur le mot) ou
> `ct;` (change jusqu'au point-virgule) qu'il faut.
>
> Le réflexe `n` puis `.` est la boucle la plus rentable de vim : la recherche
> positionne, `.` applique. Sur trente occurrences, c'est trente fois deux touches,
> avec un contrôle visuel entre chaque — là où `:%s` applique tout d'un coup.

---

<a id="e6-3"></a>**[E6.3](README.md#e6-3)** — *Substitution avec plage et confirmation dans `deploy.sh`.*

```vim
:1,11s#/opt/factura#/srv/factura#gc
:16,$s#/opt/factura#/srv/factura#gc
```

puis, pour vérifier :

```vim
:g/\/opt\/factura/p        " affiche les lignes restantes
```

ou depuis le shell : `grep -n '/opt/factura' ~/lab06/edition/deploy.sh`, qui ne
doit plus rendre que la ligne 13 (dans le bloc de commentaires 12 à 15).

Pendant la confirmation, `y` remplace, `n` passe, `a` accepte tout le reste,
`q` arrête, `l` remplace puis arrête.

> [!NOTE]
> **Pourquoi**
>
> Deux plages plutôt qu'un `:%s` et des `n` à la main : on encadre le bloc à
> préserver au lieu de compter sur sa vigilance. `$` désigne la dernière ligne, `.`
> la ligne courante, et on peut écrire des plages relatives (`:.,+10s/…`) ou
> définies par motif (`:/début/,/fin/s/…`), ce qui est plus robuste que des numéros
> quand le fichier bouge.
>
> Le drapeau `c` est le filet de sécurité d'une substitution sur un fichier qu'on
> ne maîtrise pas : il transforme une opération en aveugle en relecture guidée.

> [!WARNING]
> **Piège**
>
> Après une substitution trop large, `u` annule l'**ensemble** de la substitution
> en un seul coup — c'est une seule modification du point de vue de vim. Pas besoin
> de marteler `u` ; à l'inverse, un `u` de trop fait remonter bien plus loin que
> prévu. `:undolist` et `:earlier 5m` (revenir cinq minutes en arrière) existent
> pour ça.

---

<a id="e6-4"></a>**[E6.4](README.md#e6-4)** — *Visuel bloc : commenter, puis ajouter une colonne.*

Commenter les lignes 39 à 71 de `factura.conf` :

```text
:39<Entrée>     aller à la première ligne du bloc
Ctrl-V          mode visuel bloc
32j             étendre la sélection sur 33 lignes au total
I               insérer en tête de bloc
#               le caractère à insérer
Esc             propage sur toutes les lignes
:w
```

Décommenter :

```text
:39<Entrée>  Ctrl-V  32j  x
```

Ajouter une colonne dans `inventaire.csv` :

```text
:2<Entrée>  Ctrl-V  G  $  A  ;actif  Esc
:1<Entrée>  A;etat<Esc>
```

Variante en commande ex, plus robuste :

```vim
:2,$normal A;actif
:1normal A;etat
```

> [!NOTE]
> **Pourquoi**
>
> La version ex survit à tout : elle place le curseur sur chaque ligne et exécute
> `A` (ajouter en fin de **cette** ligne), quelle que soit sa longueur. La version
> visuel bloc dépend de la géométrie : sans le `$`, le bloc est un vrai rectangle
> et le texte s'insère à la colonne du bloc, ce qui décale les lignes courtes ou
> tronque les longues. Le `$` demande explicitement « jusqu'à la fin de chaque
> ligne », et c'est ce qui rend `Ctrl-V G $ A` équivalent à `:2,$normal A`.
>
> Retenir : visuel bloc pour ce qui est réellement rectangulaire (commenter,
> supprimer une colonne alignée) ; `:normal` pour ce qui dépend du contenu de
> chaque ligne.

---

<a id="e6-5"></a>**[E6.5](README.md#e6-5)** — *`:g` et `:g/…/normal` sur `app.log`.*

```vim
:g/DEBUG/d
:g/ERROR/normal A  <-- a traiter
```

Le fichier passe de 145 à **85** lignes (60 lignes `DEBUG` supprimées).
Vérification dans vim : `Ctrl-G` affiche `"app.log" 85 lines`, ou `:$` place le
curseur sur la dernière ligne dont on lit le numéro.

> [!NOTE]
> **Pourquoi**
>
> `:g/ERROR/normal A…` combine les deux mécanismes vus en QO6.2 : marquage puis
> exécution. La commande `A` est en mode normal, elle ajoute en fin de ligne ;
> `:normal` réinjecte un `Esc` implicite à la fin de chaque ligne traitée, ce qui
> évite que l'insertion déborde sur la suivante.
>
> Pour compter sans modifier, `:%s/ERROR//gn` est l'astuce à connaître : le
> drapeau `n` **ne remplace rien** et affiche seulement
> `13 matches on 13 lines` (le journal contient six lignes `ERROR` strictement
> identiques — une d'origine et cinq doublons — que L6.2 dédoublonnera). C'est le `grep -c` de vim.

---

<a id="e6-6"></a>**[E6.6](README.md#e6-6)** — *Registres, second fichier, tampons, fenêtres.*

```text
:10<Entrée>            aller ligne 10
"v25yy                 copier 25 lignes (10 à 34) dans le registre v
:e ~/lab06/edition/vhost-neuf.conf
"vp                    coller le registre v
:w
Ctrl-^                 revenir au fichier précédent (fichier alternatif)
:ls                    lister les tampons ouverts
:vs ~/lab06/edition/vhost-neuf.conf   les deux côte à côte
Ctrl-W w               passer d'une fenêtre à l'autre
```

Autre voie pour la copie de plage, sans compter les lignes :
`:10,34y v` puis `"vp` dans l'autre fichier.

> [!NOTE]
> **Pourquoi**
>
> Les registres nommés (`a`–`z`) survivent aux changements de fichier **dans la
> même session vim** : c'est ce qui fait qu'un copier-coller entre deux fichiers
> n'a pas besoin du presse-papier système. La majuscule (`"Vyy`) **ajoute** au
> registre au lieu de l'écraser, ce qui permet de collecter des lignes éparpillées
> puis de les coller d'un bloc.
>
> Registres particuliers : `""` (dernier effacement ou copie), `"0` (**dernière
> copie uniquement** — il survit à un `dd` qui écraserait `""`), `"%` (nom du
> fichier), `".` (dernier texte inséré), `"+` et `"*` (presse-papier système).
>
> `Ctrl-^` bascule vers le fichier alternatif : sur deux fichiers, c'est le
> déplacement le plus rapide de vim.

> [!WARNING]
> **Piège**
>
> Sur un serveur, `vim --version | grep clipboard` affiche presque toujours
> `-clipboard` : le paquet `vim` d'Ubuntu Server est compilé sans support X. `"+y`
> ne fait alors rien. Deux issues : passer par un registre nommé pour tout ce qui
> reste dans vim, et par la sélection souris du terminal pour sortir du serveur —
> avec `:set mouse=` et `:set nonumber` d'abord, sinon les numéros de ligne
> partent dans la sélection.

---

<a id="e6-7"></a>**[E6.7](README.md#e6-7)** — *`:r` et `:r !` dans `notes.txt`.*

```vim
:1r /etc/os-release
:$r !date -Is
:$r !ip -br a
```

ou, pour tout placer sous la ligne 1 dans l'ordre demandé :

```vim
:1r /etc/os-release
:1r !ip -br a
:1r !date -Is
```

Le piège des caractères spéciaux : sur la ligne de commande de vim, `%` désigne
le fichier courant et `#` le fichier alternatif. Il faut les échapper :

```vim
:r !date "+\%F \%T"                       " sinon %F devient le nom du fichier
:r !echo "\# revu le $(date -I)"          " sinon E194 ou un nom de fichier
```

> [!NOTE]
> **Pourquoi**
>
> `:r fichier` insère le contenu **après** la ligne indiquée (la ligne courante par
> défaut) ; `:0r` insère donc tout en haut du tampon. `:r !commande` exécute la
> commande via le shell de l'option `'shell'` et insère sa sortie standard — la
> sortie d'erreur, elle, arrive à l'écran.
>
> C'est le pont entre l'éditeur et le système : `:r !ss -tulpn` pour documenter un
> incident, `:r !sed -n '1,20p' autre.conf` pour importer un extrait,
> `:.!sort` pour faire passer la ligne courante dans une commande et la remplacer
> par le résultat, `:%!jq .` pour reformater tout le tampon en JSON indenté.

> [!WARNING]
> **Piège**
>
> `:r !cmd` (avec l'espace) **insère** ; `:!cmd` (sans le `r`) exécute la commande
> et n'insère rien ; `:.!cmd` **filtre** la ligne courante, c'est-à-dire qu'il la
> remplace par la sortie. Un `:%!commande-qui-échoue` vide le tampon — `u` répare,
> à condition de ne pas avoir déjà écrit.

---

<a id="e6-8"></a>**[E6.8](README.md#e6-8)** — *Enregistrer `/etc/factura/frontal.conf` ouvert sans `sudo`.*

```text
vim /etc/factura/frontal.conf
/log_level<Entrée>   ciwdebug<Esc>      (ou  A  puis correction)
/workers<Entrée>     f=  w  cw4<Esc>
:w                   -> E45: 'readonly' option is set
:w !sudo tee % > /dev/null
                     -> mot de passe sudo, puis "Press ENTER"
:e!                  recharge depuis le disque
```

Vérification que le tampon et le disque coïncident : `:w` ne doit plus rien
proposer, `:!cat %` montre le contenu réel, et `:w !diff % -` ( le tampon envoyé sur stdin de `diff`) ne doit rien afficher.

> [!NOTE]
> **Pourquoi**
>
> Voir Q6.6 pour le mécanisme du tube. Le `:e!` final est la partie que tout le
> monde oublie : sans lui, vim continue de considérer son tampon comme modifié et
> te proposera d'écrire à la fermeture, ce qui redonne `E45` et laisse croire que
> l'opération a échoué alors que le disque est à jour.
>
> Si `%` ne convient pas (fichier ouvert par un chemin relatif depuis un autre
> répertoire), `:w !sudo tee %:p > /dev/null` force le chemin absolu.

---

<a id="e6-9"></a>**[E6.9](README.md#e6-9)** — *Provoquer et réparer un `.swp`.*

```bash
# terminal 1
vim ~/lab06/edition/notes.txt      # G, o, "sentinelle", Esc — SANS :w
# terminal 2
ls -la ~/lab06/edition/.notes.txt.swp
pkill -9 vim
# terminal 1 (ou 2)
vim ~/lab06/edition/notes.txt      # E325 : choisir (R)ecover
:w ~/lab06/edition/notes.txt.recovered
:q
diff ~/lab06/edition/notes.txt ~/lab06/edition/notes.txt.recovered
rm ~/lab06/edition/.notes.txt.swp
```

Le swap est stocké **dans le répertoire du fichier**, nommé
`.<nom-du-fichier>.swp` (avec le point initial, donc invisible d'un `ls` nu).
S'il existe déjà, vim essaie `.swo`, puis `.swn`, et ainsi de suite.

> [!NOTE]
> **Pourquoi**
>
> L'emplacement est contrôlé par l'option `'directory'`. Le défaut,
> `.,~/tmp,/var/tmp,/tmp`, signifie « d'abord le répertoire du fichier, sinon
> `~/tmp`, sinon `/var/tmp`, sinon `/tmp` ». D'où les swaps qui apparaissent au
> milieu d'une arborescence applicative, et parfois versionnés par erreur — d'où
> la ligne `.*.sw?` dans tous les `.gitignore` sérieux.
>
> `vim -r fichier` ouvre un tampon reconstruit depuis le swap sans écraser quoi
> que ce soit. La règle : écrire sous un autre nom, comparer, décider, puis
> seulement supprimer le swap. Vim ne le supprime pas lui-même après une
> récupération : il ne peut pas savoir si tu as fini.

---

<a id="e6-10"></a>**[E6.10](README.md#e6-10)** — *`~/.vimrc` et le collage en escalier.*

```vim
" ~/.vimrc — configuration minimale de serveur
syntax on                  " coloration : repérer une accolade manquante
set number                 " numéros de ligne : parler d'un incident au tel
set hlsearch               " garde les occurrences surlignées
set incsearch              " déplace le curseur pendant la frappe
set ignorecase             " recherche insensible à la casse...
set smartcase              " ...sauf si le motif contient une majuscule
set expandtab              " des espaces, jamais de tabulation (YAML !)
set tabstop=2 shiftwidth=2 " une indentation = 2 colonnes
set list                   " rend visibles les caractères invisibles
set listchars=tab:»·,trail:·,nbsp:␣   " tabulation, espace final, insécable
set backupdir=~/.vim/backup//
set directory=~/.vim/swap//
set undofile undodir=~/.vim/undo//    " annulation persistante entre sessions
```

```bash
mkdir -p ~/.vim/{backup,swap,undo}
```

Pour le collage :

```text
:set paste
i    (coller à la souris)    Esc
:set nopaste
```

La ligne responsable de l'escalier est `set autoindent` (ou `smartindent`,
`cindent`, ou l'indentation automatique d'un greffon de type de fichier) : elle
réapplique l'indentation de la ligne précédente à chaque nouvelle ligne reçue,
en plus de celle déjà contenue dans le texte collé.

> [!NOTE]
> **Pourquoi**
>
> `set list` mérite sa place : c'est ce qui permet de voir, en une seconde, qu'un
> fichier YAML contient une tabulation (interdite par la spécification) ou qu'une
> ligne de configuration se termine par un espace qui casse la valeur. Et
> `undofile` change la vie sur un serveur : tu peux annuler des modifications
> faites la veille, après avoir fermé vim.
>
> Un `.vimrc` de serveur se juge à ce qu'il **ne** contient **pas** : pas de
> gestionnaire de greffons, pas de dépendance réseau, rien qui puisse empêcher vim
> de démarrer en cellule de crise. `vim -u NONE` reste la porte de sortie quand une
> configuration se met à poser problème.

---

<a id="e6-11"></a>**[E6.11](README.md#e6-11)** — *Aller-retour complet avec `tar`.*

Création :

```bash
cd ~/lab06
tar -czf archives/app.tar.gz \
    --exclude=node_modules --exclude='var/cache' --exclude='*.log' \
    -C arbo factura
tar -tzf archives/app.tar.gz | head
tar -tzf archives/app.tar.gz | wc -l        # nombre d'entrées
```

Extraction partielle avec suppression d'un niveau :

```bash
tar -xzf archives/livraison-2026-09-12.tar.gz \
    -C restauration --strip-components=1 factura/conf
ls restauration/conf/
```

> [!NOTE]
> **Pourquoi**
>
> Trois options portent tout l'exercice.
>
> `-C arbo factura` : `tar` se place dans `arbo` **avant** de commencer, puis
> archive le chemin relatif `factura`. Les membres s'appellent donc
> `factura/app/...`. C'est la seule façon propre de contrôler la racine d'une
> archive.
>
> `--exclude` s'évalue sur le nom du membre, avec les jokers du shell, **sans
> ancrage** : `var/cache` correspond donc à `factura/var/cache` et à tout ce qu'il
> contient. L'option doit être placée **avant** les chemins à archiver sur la
> ligne de commande, sinon GNU tar l'ignore pour les répertoires déjà traités.
>
> `--strip-components=1` retire le premier composant de chaque chemin à
> l'extraction : `factura/conf/factura.conf` devient `conf/factura.conf`. C'est
> l'option qui sauve quand un fournisseur livre une archive avec un niveau
> `monprojet-1.4.2/` dont on ne veut pas.
>
> Le filtrage `factura/conf` en fin de commande limite l'extraction à ce
> sous-arbre : `tar` parcourt toute l'archive mais n'écrit que ce qui correspond.

> [!WARNING]
> **Piège**
>
> `--exclude='*.log'` avec les guillemets : sans eux, le shell développe le joker
> dans le répertoire courant **avant** que `tar` ne le voie, et l'exclusion ne
> porte alors que sur les fichiers qui existent là où tu te trouves. Même règle que
> pour `find -name`.

---

<a id="e6-12"></a>**[E6.12](README.md#e6-12)** — *Comparatif des compresseurs.*

```bash
cd ~/lab06/arbo/factura
tar -cf /tmp/logs.tar logs
TIMEFORMAT='%R s'        # le time intégré de bash : pas besoin du paquet time
for c in "gzip -6" "gzip -9" "bzip2 -9" "xz -9" "zstd -19"; do
  { time $c -c /tmp/logs.tar > /tmp/o.z ; } 2>/tmp/t
  printf '%-10s %10s o  %s\n' "$c" "$(stat -c %s /tmp/o.z)" "$(cat /tmp/t)"
done
```

Relevé sur `lab-adm`, source de 3,8 Mio de journaux très répétitifs :

| Outil | Taille | Temps |
|---|---|---|
| `gzip -6` | 181 160 o | 0,02 s |
| `gzip -9` | 175 135 o | 0,05 s |
| `bzip2 -9` | 54 757 o | 0,96 s |
| `xz -9` | 6 960 o | 0,73 s |

Conclusions : pour une **sauvegarde quotidienne**, `zstd` (niveau 3 à 10, `-T0`)
— le temps de fenêtre et la rapidité de restauration comptent davantage que les
derniers pour-cent de taux. Pour un **archivage à dix ans**, `xz -9 -T0` : on
paie une fois, on stocke longtemps, et le format est stable et documenté.

> [!NOTE]
> **Pourquoi**
>
> Deux enseignements que le tableau rend visibles. D'abord, `gzip -9` coûte deux
> fois plus de temps que `-6` pour 3 % de taille en moins : sur du texte, monter
> les niveaux de `gzip` ne rapporte presque rien. Ensuite, `bzip2` est dominé sur
> les deux axes par `xz` — plus lent **et** près de huit fois moins efficace ici. Il ne
> reste dans les scripts que par habitude.
>
> Ces chiffres dépendent beaucoup des données : sur du binaire déjà compressé
> (images, vidéos, `node_modules` minifiés), les quatre outils rendront à peu près
> la taille d'origine, et la seule décision sensible sera de ne pas compresser.

---

<a id="e6-13"></a>**[E6.13](README.md#e6-13)** — *Préserver modes et propriétaires numériques.*

```bash
cd ~/lab06
tar -czf archives/conf.tar.gz --numeric-owner -C arbo/factura conf
tar -tvzf archives/conf.tar.gz --numeric-owner | grep api.token
#  -rw-r----- 0/1000  36 2026-09-18 19:08 conf/secrets/api.token

mkdir -p restauration/conf-test
tar -xzpf archives/conf.tar.gz -C restauration/conf-test
stat -c '%a %U:%G %n' restauration/conf-test/conf/secrets/api.token
#  640 mathieu:mathieu ...
```

Le mode `640` est bien restitué. Le propriétaire `root`, lui, ne l'est pas : il
faut extraire **en root**, où `--same-owner` est le défaut :

```bash
sudo tar -xzpf archives/conf.tar.gz --numeric-owner -C /srv
```

> [!NOTE]
> **Pourquoi**
>
> Voir Q6.11 pour la règle du noyau. Le point pratique : `--numeric-owner` doit
> être passé **à la création comme à l'extraction**. À la création, il évite que
> `tar` n'enregistre les noms ; à l'extraction, il évite qu'il ne les résolve. Sans
> lui, une archive faite sur une machine où `factura` a l'UID 998 et restaurée sur
> une machine où `factura` a l'UID 1001 donne des fichiers appartenant à 1001 — ce
> qui est parfois voulu, et parfois une faille.
>
> `-p` à l'extraction (`--preserve-permissions`) demande à `tar` d'ignorer
> l'`umask`. Sans `-p` et en tant qu'utilisateur ordinaire, un fichier archivé en
> `666` ressort en `644` avec un `umask 022` — et un fichier `640` peut ressortir
> en `640` par chance. Mets `-p` systématiquement, il n'a aucun inconvénient.

---

<a id="e6-14"></a>**[E6.14](README.md#e6-14)** — *Transferts en flux, sans fichier intermédiaire.*

En local :

```bash
tar -cf - -C ~/lab06/arbo/factura app | tar -xf - -C ~/lab06/depot
```

À travers SSH :

```bash
tar -czf - -C ~/lab06/arbo/factura app \
  | ssh mathieu@10.10.10.11 'tar -xzf - -C /tmp'
```

Compression d'un flux quelconque :

```bash
tar -cf - -C ~/lab06/arbo/factura app | zstd -19 -T0 > /tmp/app.tar.zst
zstd -dc /tmp/app.tar.zst | tar -tf -
```

> [!NOTE]
> **Pourquoi**
>
> Le `-f -` dit à `tar` d'utiliser stdin ou stdout selon le sens. Le tube évite
> trois choses : l'espace disque temporaire (parfois inexistant), une écriture puis
> une relecture inutiles, et le fichier oublié dans `/tmp` avec des données
> sensibles.
>
> Le couple `tar | ssh 'tar'` reste imbattable pour un premier transfert massif :
> il n'écrit rien de temporaire, préserve droits, liens et dates, et va souvent
> plus vite que `rsync` puisqu'il ne compare rien. `rsync` reprend l'avantage dès
> le deuxième passage, où il ne transfère que les différences, et dès qu'il faut
> pouvoir reprendre après coupure.

> [!WARNING]
> **Piège**
>
> Dans un tube, `set -o pipefail` est indispensable : sans lui, le code retour de
> `tar -cf - … | ssh …` est celui du **dernier** élément, et un `tar` de gauche
> qui échoue passe inaperçu. C'est exactement le genre de sauvegarde qui « marche »
> pendant six mois et se révèle vide le jour de la restauration.

---

<a id="e6-15"></a>**[E6.15](README.md#e6-15)** — *Intégrité, découpe, reconstitution.*

```bash
cd ~/lab06/archives
gzip -t livraison-recue.tar.gz
#  gzip: livraison-recue.tar.gz: unexpected end of file        -> code 1
tar -tzf livraison-recue.tar.gz > /dev/null
#  gzip: stdin: unexpected end of file / tar: Unexpected EOF
sha256sum -c livraison-recue.tar.gz.sha256
#  livraison-recue.tar.gz: FAILED
```

Ce que prouve chacun :

| Contrôle | Ce qu'il prouve |
|---|---|
| `gzip -t` | le flux compressé est complet et ses CRC internes sont bons |
| `tar -tzf` | l'archive est structurellement lisible de bout en bout |
| `sha256sum -c` | le fichier est **exactement** celui qui a été envoyé |

Découpe et reconstitution :

```bash
split -b 1M -d -a 2 livraison-2026-09-12.tar.gz livraison.part.
cat livraison.part.* > ~/lab06/restauration/livraison.tar.gz
cmp livraison-2026-09-12.tar.gz ~/lab06/restauration/livraison.tar.gz && \
  echo identique
sha256sum ~/lab06/restauration/livraison.tar.gz
```

> [!NOTE]
> **Pourquoi**
>
> Les trois contrôles ne sont pas redondants, ils sont emboîtés. `gzip -t` valide
> la couche de compression, `tar -tzf` la couche d'archive au-dessus, et la somme
> SHA-256 valide l'octet. Seule la dernière détecte une corruption qui laisserait
> le format valide — ou un fichier entier substitué. C'est pourquoi une chaîne de
> sauvegarde sérieuse stocke la somme **à côté** de l'archive et la vérifie avant
> chaque restauration.
>
> `cmp` est le contrôle le plus direct quand les deux fichiers sont accessibles :
> il compare octet à octet et s'arrête à la première différence, sans calculer de
> somme. Quand ils sont sur deux machines, la somme est la seule option.

---

<a id="e6-16"></a>**[E6.16](README.md#e6-16)** — *`rsync` : exclusions, second passage, suppression, slash final.*

```bash
rsync -avzP --exclude='node_modules/' --exclude='var/cache/' \
      ~/lab06/arbo/factura/ ~/lab06/depot/
```

Le second passage ne transfère quasiment rien : quelques dizaines de
millisecondes, et un récapitulatif à zéro octet transféré.

```bash
rm ~/lab06/arbo/factura/app/tests/test_10.py
rsync -avn --delete --exclude='node_modules/' --exclude='var/cache/' \
      ~/lab06/arbo/factura/ ~/lab06/depot/       # simulation : deleting …
rsync -av  --delete --exclude='node_modules/' --exclude='var/cache/' \
      ~/lab06/arbo/factura/ ~/lab06/depot/       # exécution
```

Sans la barre oblique finale à la source :

```bash
rsync -av ~/lab06/arbo/factura ~/lab06/depot/    # crée ~/lab06/depot/factura/
```

> [!NOTE]
> **Pourquoi**
>
> Le second passage est instantané parce que `rsync` décide fichier par fichier à
> partir d'un **test rapide** : même taille et même date de modification ⇒ le
> fichier est réputé identique, il n'est même pas lu. C'est seulement pour les
> fichiers qui diffèrent qu'il calcule des sommes glissantes par blocs et ne
> transfère que les blocs modifiés (l'algorithme rsync proprement dit).
>
> `--checksum` remplace le test rapide par un hachage complet des deux côtés :
> beaucoup plus lent, mais c'est ce qu'il faut pour vérifier un transfert ou
> rattraper des dates falsifiées.
>
> `-P` vaut `--partial --progress` : il conserve les fragments des fichiers
> interrompus et affiche l'avancement. Sur une liaison instable, c'est ce qui
> transforme une coupure en simple reprise.

> [!WARNING]
> **Piège**
>
> Les motifs de `--exclude` ne sont **pas** des globs de shell. La barre oblique
> finale (`node_modules/`) restreint la correspondance aux répertoires ; un motif
> sans `/` correspond à n'importe quel composant du chemin, à n'importe quelle
> profondeur ; un motif commençant par `/` est ancré sur la racine du transfert,
> pas sur la racine du système. Relis `man rsync`, section
> *ANCHORING INCLUDE/EXCLUDE PATTERNS*, avant d'écrire une règle un peu fine.

---

## 6.6 Labs

### <a id="l6-1"></a>**[L6.1](README.md#l6-1)** — Reprendre un vhost hérité, au clavier uniquement

*Objectif : remettre `~/lab06/edition/factura.conf` d'aplomb, sans souris, et le
reporter dans `/etc/factura/frontal.conf.nouveau`.*

Séquence complète, dans l'ordre :

```vim
" 1. server_name du bloc actif
/server_name<Entrée>
ci"factura.lab.local<Esc>

" 2. migration des chemins, limitée à la partie active
:1,34s#/opt/#/srv/#g

" 3. commenter le bloc hérité (39 à 71) en visuel bloc
:39<Entrée>
Ctrl-V 32j I # Esc
"    équivalent ex :  :39,71s/^/#/   (normal I# insérerait après l'indentation)

" 4. ligne de revue, produite par une commande
:2r !echo "\# revu le $(date -I) par $(id -un) sur $(hostname -s)"

" 5. directive supplémentaire dans le bloc actif
:g/^    index index.html;$/normal o    client_max_body_size 32m;

" 6. plus de lignes vides en double
:%s/\n\{3,}/\r\r/e

" 7. écrire, puis reporter en root
:w
:w !sudo tee /etc/factura/frontal.conf.nouveau > /dev/null
```

```bash
bash check_M06_01.sh
```

> [!NOTE]
> **Pourquoi**
>
> **L'ordre des étapes est le cœur du lab.** Les étapes 2 et 3 s'appuient sur des
> numéros de ligne ; l'étape 4 insère une ligne et décale tout ce qui suit d'un
> cran. Faire l'étape 4 en premier oblige à recalculer toutes les plages. Règle
> générale : les opérations qui **changent le nombre de lignes** passent en
> dernier, ou bien on utilise des plages définies par motif plutôt que par numéro,
> par exemple `:/^# --- bloc hérité/,$s/^/#/`, qui reste juste quoi qu'il
> arrive avant.
>
> L'étape 4 contient le piège des caractères spéciaux : sur la ligne de commande de
> vim, `%` est remplacé par le nom du fichier courant et `#` par celui du fichier
> alternatif. Le `#` du commentaire doit donc s'écrire `\#`, faute de quoi vim
> répond `E194: No alternate file name to substitute for '#'` et n'insère rien —
> en silence si tu ne lis pas la ligne de statut. Même chose pour `date +%F`, à
> écrire `date "+\%F"` ; le plus simple reste `date -I`, qui ne contient aucun
> caractère spécial.
>
> L'étape 6 s'appuie sur une propriété peu connue : dans un motif de `:s`, `\n`
> correspond à la fin de ligne et la substitution peut donc s'étendre sur
> plusieurs lignes. Côté remplacement, en revanche, c'est `\r` qui insère une
> nouvelle ligne — `\n` y insérerait un octet nul. Le drapeau `e` évite l'erreur
> `E486: Pattern not found` quand il n'y a rien à corriger, ce qui rend la
> commande rejouable dans un script.

> [!WARNING]
> **Piège**
>
> Le report vers `/etc` échoue si tu écris `:w! sudo tee …` (le `!` collé au `w`) :
> c'est alors un `:w!` suivi d'un nom de fichier littéral `sudo`, et vim crée un
> fichier nommé `sudo` dans le répertoire courant. L'espace avant le `!` est ce qui
> transforme la destination en commande. Et après un `:w !sudo tee %`, ne pas
> oublier `:e!` : sans lui le tampon reste marqué modifié et tu recevras `E45` à la
> fermeture, en croyant que rien n'a été enregistré.

---

### <a id="l6-2"></a>**[L6.2](README.md#l6-2)** — Ticket INC-4488 : extraire un rapport d'incident

*Objectif : produire `~/lab06/edition/inc-4488.log`, trié, dédoublonné, annoté,
sans `grep` ni `sed`.*

```bash
cp ~/lab06/edition/app.log ~/lab06/edition/inc-4488.log
vim ~/lab06/edition/inc-4488.log
```

```vim
:g/DEBUG/d                                   " 1
:v/ERROR\|WARN/d                             " 2
:g/ERROR/normal A  [INC-4488]                " 3
:%s/\v2026-09-17T04:(\d{2}):\d{2}/04:\1/     " 4
:%s/worker=\d* //                            " 5
:sort u                                      " 6
:0r !echo "\# INC-4488 — extrait genere le $(date -I) sur $(hostname -s)"
:w
```

Résultat attendu : **21 lignes** — l'en-tête, 8 lignes `ERROR` annotées et
12 lignes `WARN`.

```bash
bash check_M06_02.sh
```

> [!NOTE]
> **Pourquoi**
>
> Chaque commande porte une idée.
>
> `:v/ERROR\|WARN/d` : l'alternance de vim s'écrit `\|`, avec l'antislash, dans la
> syntaxe par défaut (« magic »). C'est l'inverse d'`egrep`, et la source d'erreur
> la plus fréquente pour qui vient du shell. `\v` (« very magic ») aligne la
> syntaxe sur celle des expressions rationnelles étendues : `:v/\v(ERROR|WARN)/d`
> se lit alors comme du `egrep`.
>
> Étape 4, la capture : `\(...\)` en magic, `(...)` en very magic, rappelée par
> `\1` dans le remplacement. On capture les minutes, on jette le reste. Les
> accolades de quantification s'écrivent `\{2\}` en magic et `{2}` en very magic —
> raison suffisante pour préférer `\v` dès qu'un motif dépasse trois caractères.
>
> Étape 6, `:sort u` : le `u` supprime les doublons **après** tri, exactement comme
> `sort -u`. Il agit sur la ligne entière ; `:sort u /motif/` trie sur ce qui suit
> le motif, ce qui permet de trier un journal sur le message plutôt que sur
> l'horodatage.
>
> L'en-tête est inséré **en dernier**, après le tri : un `:sort u` exécuté ensuite
> le déplacerait au milieu du fichier.

> [!WARNING]
> **Piège**
>
> L'ordre 1 puis 2 est redondant : `:v/ERROR\|WARN/d` seul aurait suffi, puisqu'il
> supprime aussi les `DEBUG` et les `INFO`. Ce n'est pas une faute — c'est même
> plus prudent de procéder par soustractions successives sur un fichier qu'on
> découvre — mais il faut savoir le dire. Sur un fichier de deux millions de
> lignes, chaque passe coûte, et on cherchera à n'en faire qu'une.

---

### <a id="l6-3"></a>**[L6.3](README.md#l6-3)** — Archiver le serveur applicatif avant migration

*Objectif : une archive complète, exclusions faites, vérifiable, découpée, et
dont la restauration est prouvée.*

```bash
cd ~/lab06/archives
D=$(date +%Y%m%d)

# 1. création
tar -czpf "factura-$D.tar.gz" --numeric-owner \
    --exclude=node_modules --exclude='var/cache' --exclude='*.log' \
    -C ~/lab06/arbo factura

# 2. vérification sans extraire
tar -tzf "factura-$D.tar.gz" | wc -l
tar -tzf "factura-$D.tar.gz" | grep -E 'node_modules|var/cache|\.log$'   # vide
tar -tvzf "factura-$D.tar.gz" --numeric-owner | grep api.token
#  -rw-r----- 0/1000 ... factura/conf/secrets/api.token

# 3. somme de contrôle
sha256sum "factura-$D.tar.gz" > "factura-$D.tar.gz.sha256"
sha256sum -c "factura-$D.tar.gz.sha256"

# 4. découpe en morceaux de 2 Mio
split -b 2M -d -a 2 "factura-$D.tar.gz" "factura-$D.part."

# 5. reconstitution et preuve
cat "factura-$D.part."* > ~/lab06/restauration/"factura-$D.tar.gz"
cd ~/lab06/restauration
sha256sum -c ~/lab06/archives/"factura-$D.tar.gz.sha256"   # OK

# 6. restauration testée
mkdir -p ~/lab06/restauration/test
tar -xzpf ~/lab06/archives/"factura-$D.tar.gz" --numeric-owner \
    -C ~/lab06/restauration/test
diff -r ~/lab06/arbo/factura ~/lab06/restauration/test/factura
#  Only in .../arbo/factura: node_modules
#  Only in .../arbo/factura/var: cache
#  Only in .../arbo/factura/logs: access.log   (etc.)
```

Le propriétaire `root` du fichier de secrets n'est pas restitué parce que
l'extraction a eu lieu sous `mathieu` : le noyau interdit à un utilisateur
ordinaire de donner un fichier à un autre UID. Une restauration fidèle se fait
en `sudo tar -xzpf … --numeric-owner`.

```bash
bash check_M06_03.sh
```

> [!NOTE]
> **Pourquoi**
>
> La partie qui compte pédagogiquement est l'étape 6 : `diff -r` est le seul
> contrôle qui compare l'**arborescence restaurée** à la source, fichier par
> fichier. Une somme de contrôle prouve que l'archive est intacte ; `diff -r`
> prouve que son contenu est celui qu'on croit. Les seules différences attendues
> sont exactement les exclusions — si une autre apparaît, la commande d'archivage
> était fausse.
>
> Sur la découpe : `split -d` produit des suffixes numériques (`00`, `01`…) plutôt
> qu'alphabétiques ; `-a 2` fixe leur longueur. Les deux garanties nécessaires sont
> que le tri par nom corresponde à l'ordre de découpe (`cat part.*` s'appuie sur le
> glob, qui trie), et qu'aucun suffixe ne déborde (`-a 2` plafonne à 100 morceaux).
>
> Enfin, `-p` à la création ne sert à rien mais ne nuit pas ; c'est à l'extraction
> qu'il est déterminant. Beaucoup de scripts l'écrivent des deux côtés par
> habitude, et c'est très bien : une habitude qui ne coûte rien et sauve la moitié
> du temps est une bonne habitude.

> [!WARNING]
> **Piège**
>
> Écrire l'archive **dans** le répertoire qu'on archive est l'erreur du BF6.2 :
> `tar -czf ~/lab06/arbo/factura/sauvegarde.tgz -C ~/lab06/arbo factura` produit
> une archive qui grossit à chaque exécution et un code retour 1. La destination
> d'une archive n'est jamais sous la source.

---

### <a id="l6-4"></a>**[L6.4](README.md#l6-4)** — Sauvegardes incrémentales et transfert

*Objectif : trois sauvegardes datées partageant leurs fichiers inchangés, puis
un transfert reprenable vers `lab-web`.*

```bash
cd ~/lab06
EXCL=(--exclude='node_modules/' --exclude='var/cache/')

# 1. première sauvegarde (simulation puis exécution)
rsync -an  --delete "${EXCL[@]}" arbo/factura/ backup/2026-09-18/
rsync -a   --delete "${EXCL[@]}" arbo/factura/ backup/2026-09-18/
du -sh backup/2026-09-18

# 2. un fichier change, puis sauvegarde du lendemain
printf 'log_level = debug\n' >> arbo/factura/conf/factura.conf
rsync -a --delete "${EXCL[@]}" --link-dest=../2026-09-18 \
      arbo/factura/ backup/2026-09-19/

# 3. preuve du partage
du -sh backup/2026-09-18; du -sh backup/2026-09-19   # ~9 Mo chacun, seuls
du -sh --total backup/2026-09-1[89]             # ~9 Mo au total
stat -c '%h %n' backup/2026-09-1[89]/app/src/mod_01.py   # 2 liens, même inode
stat -c '%i' backup/2026-09-1[89]/app/src/mod_01.py      # inode identique

# 4. le fichier modifié, lui, est distinct
cmp backup/2026-09-18/conf/factura.conf backup/2026-09-19/conf/factura.conf
stat -c '%i' backup/2026-09-1[89]/conf/factura.conf      # inodes différents

# 5. une suppression à la source
rm arbo/factura/app/tests/test_09.py          # test_10 : déjà pris par E6.16
rsync -a --delete "${EXCL[@]}" --link-dest=../2026-09-19 \
      arbo/factura/ backup/2026-09-20/
ls backup/2026-09-18/app/tests/test_09.py     # existe encore
ls backup/2026-09-20/app/tests/test_09.py     # No such file

# 6. transfert reprenable vers lab-web
rsync -aP backup/2026-09-20/ mathieu@10.10.10.11:~/backup-factura/
#   Ctrl-C en cours de route, puis la même commande : elle reprend
```

`~/lab06/backup/NOTES.md` :

```markdown
- rsync -aP : compare avant de transférer, reprend après coupure, sait
  supprimer côté destination, préserve droits et dates.
- scp -r : pas de comparaison, pas de reprise, pas de suppression ;
  une coupure à 99 % renvoie tout (même en mode SFTP, OpenSSH 9+).
- sftp : reprise possible fichier par fichier (reget/reput), mais
  manuelle et sans notion d'arborescence à synchroniser.
```

```bash
bash check_M06_04.sh
```

> [!NOTE]
> **Pourquoi**
>
> Les trois chiffres de l'étape 3 sont ce qu'il faut savoir interpréter, et c'est
> un classique d'entretien. `du -sh` sur un répertoire compte tous les fichiers
> qu'il voit : il annonce la taille pleine, parce qu'il n'a aucun moyen de deviner
> que ces inodes sont partagés avec un répertoire qu'on ne lui a pas demandé de
> regarder. `du -sh --total` sur les deux répertoires à la fois, en revanche, tient
> un registre des inodes déjà comptés et ne les compte qu'une fois : le second répertoire n'affiche plus que ses fichiers propres, et le total est
> l'occupation réelle. C'est pourquoi les deux premières mesures se font dans deux commandes `du` séparées. Et `stat -c %h` donne la preuve directe, inode par inode.
>
> `--link-dest` accepte un chemin relatif **à la destination**, d'où
> `../2026-09-18` depuis `backup/2026-09-19/`. Une valeur erronée ne provoque pas
> d'erreur : rsync se contente de tout recopier. Le contrôle à faire après le
> premier essai est donc `du`, pas le code retour.

> [!WARNING]
> **Piège**
>
> `rsync -a` ne préserve pas les propriétaires quand il tourne sans privilèges
> (même règle que `tar`) : `-o` et `-g` sont inclus dans `-a` mais ignorés faute de
> droits. Pour une sauvegarde système fidèle, `sudo rsync` des deux côtés, ou
> `--fake-super`, qui stocke propriétaires et modes dans des attributs étendus
> lorsque la destination ne peut pas les porter.

---

## 6.7 Break & Fix

### <a id="bf6-1"></a>**[BF6.1](README.md#bf6-1)** — « vim refuse d'ouvrir le fichier de conf »

**Démarche de diagnostic**

```bash
# 1. lire le message en entier, il contient tout
sudo vim /etc/factura/frontal.conf
#  E325: ATTENTION
#  Found a swap file by the name "/etc/factura/.frontal.conf.swp"
#           owned by: root   dated: ...
#          file name: /etc/factura/frontal.conf
#           modified: YES
#          user name: root   host name: lab-adm
#         process ID: 4711 (still running)

# 2. quitter par (Q)uit, ne rien décider dans le menu
# 3. inventorier les swaps
ls -la /etc/factura/.frontal.conf.sw?
# 4. le processus annoncé vit-il vraiment ?
ps -fp 4711
pgrep -af vim
# 5. le swap est-il plus récent que le fichier ?
ls -l --time-style=full-iso /etc/factura/frontal.conf \
                            /etc/factura/.frontal.conf.swp
# 6. que contient-il ?
sudo vim -r /etc/factura/frontal.conf
:w /tmp/frontal.recovered
:q
diff -u /etc/factura/frontal.conf /tmp/frontal.recovered
#  +max_upload_mb = 250
#  +worker_timeout = 120
```

**Cause racine** : une session `vim` lancée par un collègue est **toujours
vivante** (terminal oublié dans un `tmux` détaché) sur `/etc/factura/frontal.conf`.
Elle a modifié le tampon et écrit son journal dans le swap, mais n'a jamais fait
`:w`. Le fichier sur disque est donc dans son état d'origine, et le travail n'existe
que dans `.frontal.conf.swp`. Le `E45` en prime vient d'autre chose : le fichier
appartient à `root` en 644 et tu l'as ouvert sans `sudo`.

**Correctif**

```bash
# 1. récupérer AVANT toute suppression (fait à l'étape 6 ci-dessus)
# 2. prévenir le propriétaire de la session, puis la fermer
ps -fp "$(pgrep -f '^vim .*frontal.conf')"   # ^ : pas le script(1) parent
kill "$(pgrep -f '^vim .*frontal.conf')"           # TERM, pas KILL
# 3. appliquer les deux réglages retrouvés
sudo cp /tmp/frontal.recovered /etc/factura/frontal.conf
# 4. nettoyer le swap devenu orphelin
sudo rm -f /etc/factura/.frontal.conf.sw?
# 5. rouvrir : plus aucun message
sudo vim /etc/factura/frontal.conf
```

**Prévention**

* centraliser les swaps hors des répertoires de configuration :
  `set directory=~/.vim/swap//` dans `/etc/vim/vimrc.local` ;
* utiliser `sudoedit` plutôt que `sudo vim` : le swap est alors créé dans `/tmp`
  sous ton identité, pas dans `/etc` sous celle de root ;
* ne jamais laisser un `vim` ouvert sur un fichier de `/etc` dans un `tmux`
  détaché — la revue de configuration se fait, s'écrit, et se ferme.

> [!NOTE]
> **Pourquoi**
>
> Le point à comprendre est que `E325` **n'est pas une erreur** : c'est une
> information, et la seule question qu'elle pose est « veux-tu ce qui est dans le
> swap ? ». Le menu propose `(O)pen Read-Only`, `(E)dit anyway`, `(R)ecover`,
> `(D)elete it`, `(Q)uit`, `(A)bort`. Les deux seules réponses prudentes sont
> `(Q)uit` — pour aller enquêter en dehors de vim — et `(R)ecover` — pour lire le
> contenu du swap. `(E)dit anyway` ouvre une **seconde** session sur le même
> fichier : les deux écriront l'une par-dessus l'autre, et la dernière à sauver
> gagne. `(D)elete it` détruit le travail de quelqu'un.
>
> `kill` sans `-9` laisse à vim le temps de mettre son swap à jour avant de sortir (`Vim: Caught deadly signal TERM`,
>
> `preserving files`) : rien de ce qui était dans le tampon n'est perdu. Le swap reste sur le disque dans les deux cas, d'où l'étape 4 ; mais `kill -9` ne laisse aucune chance d'y écrire les dernières frappes, et
> c'est ainsi qu'on perd du travail.

---

### <a id="bf6-2"></a>**[BF6.2](README.md#bf6-2)** — « la sauvegarde nocturne grossit sans fin »

**Démarche de diagnostic**

```bash
# 1. lire le script, avant tout
cat /usr/local/bin/factura-backup.sh
#  DEST=/srv/factura/backup
#  tar -czf "$DEST/factura-$STAMP.tar.gz" /srv/factura

# 2. observer les tailles successives
ls -lh /srv/factura/backup/
#  4,1M  factura-2026-09-18-190611.tar.gz
#  8,1M  factura-2026-09-18-190613.tar.gz
#   28M  factura-2026-09-18-190614.tar.gz

# 3. regarder ce qu'il y a DANS l'archive
tar -tzf /srv/factura/backup/factura-...-190614.tar.gz | grep backup/
#  srv/factura/backup/
#  srv/factura/backup/factura-...-190614.tar.gz
#  srv/factura/backup/factura-...-190611.tar.gz
#  srv/factura/backup/factura-...-190613.tar.gz

# 4. reproduire et lire le code retour
sudo /usr/local/bin/factura-backup.sh; echo "code=$?"
#  tar: Removing leading `/' from member names
#  tar: /srv/factura/backup/factura-....tar.gz: file changed as we read it
#  code=1
```

**Cause racine** : la destination des archives, `/srv/factura/backup`, se trouve
**à l'intérieur** de l'arborescence archivée, `/srv/factura`. Chaque exécution
embarque donc toutes les archives précédentes : la taille suit une progression
géométrique, et la durée avec. De plus, l'archive en cours d'écriture est
elle-même lue par `tar`, qui constate que le fichier change pendant sa
lecture et sort en 1.

**Correctif**

```bash
sudo install -d -m 750 /srv/sauvegardes
sudo vim /usr/local/bin/factura-backup.sh
```

```bash
#!/usr/bin/env bash
set -euo pipefail

DEST=/srv/sauvegardes                 # HORS de l'arborescence sauvegardée
STAMP=$(date +%F-%H%M%S)
mkdir -p "$DEST"

RC=0
tar -czf "$DEST/factura-$STAMP.tar.gz" \
    --exclude='*.tar.gz' \
    -C /srv factura || RC=$?          # sinon set -e sort avant le test

[ "$RC" -le 1 ] || exit "$RC"         # 1 = avertissement, 2 = erreur fatale
echo "sauvegarde terminee : $DEST/factura-$STAMP.tar.gz (code $RC)"
```

```bash
sudo rm -rf /srv/factura/backup       # après avoir mis les archives de côté
sudo /usr/local/bin/factura-backup.sh; echo "code=$?"   # 20 s, code 0
```

**Ce que signifie le code 1** : un avertissement non fatal. `tar` a produit une
archive, mais au moins un fichier y est douteux — modifié pendant sa lecture,
ou disparu entre le listage et la lecture. Le code 2, lui, signale une erreur
fatale : rien d'exploitable n'a été produit.

**Prévention**

* la destination d'une sauvegarde n'est **jamais** sous la source : c'est une
  règle, pas une préférence ;
* utiliser `-C /srv factura` plutôt qu'un chemin absolu : l'archive devient
  restaurable n'importe où et le message `Removing leading '/'` disparaît ;
* tester explicitement le code retour au lieu de le propager tel quel ;
* ajouter `--exclude='*.tar.gz'` en ceinture et bretelles.

> [!NOTE]
> **Pourquoi**
>
> GNU `tar` possède bien une protection : il refuse de s'archiver lui-même et
> affiche `archive cannot contain itself; not dumped`. Mais elle ne porte que sur le fichier
> qu'il écrit **lui-même**, identifié par son couple périphérique/inode. Avec `- z`, c'est `gzip` qui écrit l'archive : `tar` ne la reconnaît plus et la lit comme n'importe quel fichier, d'où le `file changed as we read it`. Quant aux
> archives des nuits précédentes, ce sont pour lui des fichiers ordinaires : rien ne
> les distingue de données à sauvegarder. La protection donne donc un faux
> sentiment de sécurité, et c'est précisément ce qui rend cette panne si
> fréquente — elle ne se voit qu'au bout de plusieurs nuits.
>
> Second enseignement : compresser du gzip avec gzip ne gagne rien. Les archives
> imbriquées occupent leur taille pleine, d'où la progression brutale 4 Mo, 8 Mo,
> 28 Mo.

---

### <a id="bf6-3"></a>**[BF6.3](README.md#bf6-3)** — « la synchro du site a tout cassé »

**Démarche de diagnostic**

```bash
# 1. constater
ls -la /var/www/factura/
#  drwxr-xr-x www-data www-data  factura-site/
curl -sI http://10.10.10.11/ | head -1      # 404, si nginx sert ce répertoire

# 2. lire la commande qui a tourné
tail -5 /var/log/factura-sync.log
#  ... commande : rsync -a --delete /srv/factura-site /var/www/factura/

# 3. comparer avec la source de vérité
ls /srv/factura-site/
#  css  img  index.html  js  maintenance.html
```

**Cause racine** : la barre oblique finale manque au chemin **source**.
`rsync -a --delete /srv/factura-site /var/www/factura/` signifie « copie le
répertoire `factura-site` **dans** `/var/www/factura/` », d'où
`/var/www/factura/factura-site/`. Et comme `--delete` supprime à la destination
tout ce qui n'existe pas à la source, les fichiers qui étaient à la racine de
`/var/www/factura/` — dont `index.html` — ont été effacés. La racine servie par
nginx est donc vide : 404.

**Correctif**

```bash
# 1. simuler la bonne commande AVANT de l'exécuter
sudo rsync -avn --delete /srv/factura-site/ /var/www/factura/

# 2. l'exécuter
sudo rsync -av --delete /srv/factura-site/ /var/www/factura/

# 3. le sous-répertoire parasite a été supprimé par --delete ; vérifier
ls /var/www/factura/
#  css  img  index.html  js  maintenance.html
sudo chown -R www-data:www-data /var/www/factura
curl -sI http://10.10.10.11/ | head -1      # 200 OK, même réserve

# 4. corriger le job de nuit (crontab, timer ou script qui porte la commande
#    journalisée) : ajouter le slash final à la source
```

**La précaution qui aurait tout évité** : `--dry-run` sur la première exécution
du job, et sur toute modification ultérieure. La sortie aurait montré
`factura-site/` créé et une série de lignes `deleting index.html`,
`deleting css/style.css` — impossible à manquer.

> [!NOTE]
> **Pourquoi**
>
> Le détail à ne pas rater : `--delete` **répare** ici tout seul. Une fois la
> commande corrigée, le sous-répertoire `factura-site/` n'existe plus à la source,
> donc rsync le supprime à la destination. La même option qui a causé l'incident le
> nettoie — ce qui montre bien que `--delete` n'est pas dangereux en soi : c'est
> l'écart entre ce que tu crois synchroniser et ce que tu synchronises réellement
> qui l'est.
>
> Deux garde-fous complémentaires pour une cible de production :
> `--delete-after` (les suppressions n'ont lieu qu'une fois tous les transferts
> réussis, la cible n'est donc jamais vidée par un transfert qui échoue en cours)
> et `--max-delete=50` (rsync abandonne s'il doit supprimer plus de 50 fichiers,
> ce qui attrape exactement ce type d'erreur).

---

## 6.8 Défi du module

<a id="d6"></a>**[D6](README.md#d6) — Chaîne de sauvegarde et de restauration de `factura`**

Implémentation de référence de `~/bin/factura-backup.sh` :

```bash
#!/usr/bin/env bash
# factura-backup.sh — chaîne de sauvegarde/restauration de factura
set -euo pipefail

SRC="$HOME/lab06/arbo/factura"
BK="$HOME/lab06/backup"
AR="$BK/archives"
LOG="$BK/backup.log"
GARDE=7
# le joker est quoté deux fois : la chaîne passe par eval dans faire()
EXCLUS=(--exclude=node_modules --exclude=var/cache "--exclude='*.log'")
DRY=0; VERB=0; FORCE=0
JOUR=$(date +%F)

usage() {
  cat <<'EOF'
Usage : factura-backup.sh [-n|--dry-run] [-v] [--force] [-h] <mode> [args]

Modes :
  sauver                       archive datée + .sha256, rotation à 7
  miroir                       rsync --link-dest vers backup/<AAAA-MM-JJ>/
  restaurer <archive> <cible>  vérifie la somme PUIS extrait
  verifier                     contrôle toutes les archives présentes
EOF
}

trace()   { [ "$VERB" -eq 1 ] && printf '  %s\n' "$*" >&2 || true; }
mourir()  { printf 'erreur : %s\n' "$*" >&2; exit 1; }
faire()   { if [ "$DRY" -eq 1 ]; then printf '[dry-run] %s\n' "$*"
            else eval "$*"; fi }
journal() { printf '%s %-9s duree=%ss taille=%s rc=%s\n' \
              "$(date -Is)" "$1" "$2" "$3" "$4" >> "$LOG"; }

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run) DRY=1; shift ;;
    -v) VERB=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) mourir "option inconnue : $1" ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || { usage >&2; exit 1; }
MODE="$1"; shift
mkdir -p "$AR" "$BK"

rotation_archives() {
  local n; n=$(ls -1 "$AR"/factura-*.tar.gz 2>/dev/null | wc -l)
  [ "$n" -le "$GARDE" ] && return 0
  ls -1 "$AR"/factura-*.tar.gz | sort -r | tail -n +$((GARDE + 1)) | \
  while IFS= read -r f; do
    trace "rotation : suppression de $(basename "$f")"
    faire "rm -f '$f' '$f.sha256'"
  done
}

verifier_une() {
  local a="$1" d b
  d=$(dirname "$a"); b=$(basename "$a")
  [ -f "$a.sha256" ] || { printf '%s : pas de .sha256\n' "$b" >&2; return 1; }
  ( cd "$d" && sha256sum -c --status "$b.sha256" ) || {
      printf '%s : somme de contrôle invalide\n' "$b" >&2; return 1; }
  gzip -t "$a" 2>/dev/null || {
      printf '%s : flux gzip corrompu\n' "$b" >&2; return 1; }
}

case "$MODE" in
sauver)
  T0=$SECONDS; TGZ="$AR/factura-$JOUR.tar.gz"
  faire "tar -czpf '$TGZ' --numeric-owner ${EXCLUS[*]} \
         -C '$(dirname "$SRC")' '$(basename "$SRC")'"
  if [ "$DRY" -eq 0 ]; then
    ( cd "$AR" && sha256sum "$(basename "$TGZ")" \
        > "$(basename "$TGZ").sha256" )
    TAILLE=$(stat -c %s "$TGZ")
  else TAILLE=0; fi
  rotation_archives
  if [ "$DRY" -eq 0 ]; then journal sauver "$((SECONDS - T0))" "$TAILLE" 0; fi
  printf 'archive : %s (%s octets)\n' "$TGZ" "$TAILLE"
  ;;
miroir)
  command -v rsync >/dev/null 2>&1 || mourir "rsync absent"
  T0=$SECONDS; DEST="$BK/$JOUR"
  PREC=$(ls -1d "$BK"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] 2>/dev/null \
         | grep -v "/$JOUR\$" | sort | tail -1)
  LIEN=""; [ -n "$PREC" ] && LIEN="--link-dest=$PREC"
  OPT="-a --delete --exclude=node_modules --exclude=var/cache"
  if [ "$DRY" -eq 1 ]; then OPT="$OPT --dry-run"; else mkdir -p "$DEST"; fi
  rsync $OPT $LIEN "$SRC/" "$DEST/"
  # rotation : les 7 répertoires datés les plus récents (tri sur le nom)
  ls -1d "$BK"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] 2>/dev/null \
    | sort -r | tail -n +$((GARDE + 1)) | while IFS= read -r d; do
        trace "rotation : suppression de $(basename "$d")"
        faire "rm -rf '$d'"
      done
  if [ "$DRY" -eq 0 ]; then
    journal miroir "$((SECONDS - T0))" "$(du -sh "$DEST" | cut -f1)" 0
    printf 'miroir : %s\n' "$DEST"
  fi
  ;;
restaurer)
  [ $# -eq 2 ] || mourir "usage : restaurer <archive> <cible>"
  A="$1"; CIBLE="$2"; T0=$SECONDS
  [ -f "$A" ] || mourir "archive introuvable : $A"
  verifier_une "$A" || mourir "archive non conforme, restauration annulée"
  if [ -d "$CIBLE" ] && [ -n "$(ls -A "$CIBLE" 2>/dev/null)" ] \
     && [ "$FORCE" -eq 0 ]; then
    mourir "$CIBLE n'est pas vide (--force pour écraser)"
  fi
  faire "mkdir -p '$CIBLE'"
  faire "tar -xzpf '$A' --numeric-owner -C '$CIBLE'"
  if [ "$DRY" -eq 0 ]; then
    N=$(find "$CIBLE" -type f | wc -l)
    journal restaurer "$((SECONDS - T0))" "$N" 0
    printf 'restauré : %s fichiers dans %s\n' "$N" "$CIBLE"
  fi
  ;;
verifier)
  RC=0; N=0
  for a in "$AR"/factura-*.tar.gz; do
    [ -e "$a" ] || continue
    N=$((N + 1))
    if verifier_une "$a"; then printf 'OK    %s\n' "$(basename "$a")"
    else printf 'CASSE %s\n' "$(basename "$a")"; RC=1; break; fi
  done
  journal verifier 0 "$N" "$RC"
  exit "$RC"
  ;;
*) usage >&2; exit 1 ;;
esac
```

```bash
bash check_M06_05.sh
```

> [!NOTE]
> **Pourquoi**
>
> Quatre décisions de conception méritent d'être défendues à l'oral.
>
> **La vérification avant l'extraction.** `restaurer` calcule la somme avant de
> toucher à quoi que ce soit. Une restauration est toujours faite en situation de
> crise, souvent par-dessus des données encore partiellement présentes : extraire
> une archive corrompue transforme une panne en désastre. Le refus d'écrire dans
> un répertoire non vide sans `--force` relève de la même logique.
>
> **Le `--dry-run` qui traverse tout le script.** La fonction `faire()` est le
> point unique où une action destructrice s'exécute. Toute commande qui écrit
> passe par elle, donc `-n` est fiable par construction plutôt que par vigilance.
> Pour `rsync`, on transmet en plus son propre `--dry-run`, puisque c'est lui qui
> décide ce qu'il transfère.
>
> **La rotation qui ne peut pas manger la dernière sauvegarde.** Le tri est fait
> sur le **nom**, pas sur la date de modification du fichier. Les noms sont
> horodatés en `AAAA-MM-JJ`, donc l'ordre lexicographique est l'ordre
> chronologique. Un `touch` malencontreux ou une horloge qui saute ne peut donc pas
> faire passer la sauvegarde du jour pour la plus ancienne — ce qu'un tri sur
> `ls -t` aurait permis.
>
> **La séparation stdout / stderr.** Le compte rendu lisible sort sur stdout, les
> diagnostics (`trace`, `mourir`) sur stderr. C'est ce qui permet demain de
> rediriger l'un vers un rapport et l'autre vers une alerte, sans retoucher le
> script.

> [!WARNING]
> **Piège**
>
> Deux pièges classiques dans ce type de script.
>
> `set -e` **ne protège pas dans un tube** : `tar -cf - … | ssh …` renvoie le code
> du dernier élément. C'est `set -o pipefail` — déjà présent ici via
> `set -euo pipefail` — qui fait remonter l'échec du premier.
>
> `set -u` casse sur `"$1"` quand aucun argument n'est fourni. D'où le
> `[ $# -ge 1 ] || { usage >&2; exit 1; }` **avant** toute lecture de `$1`. Un
> script de sauvegarde qui meurt sur `unbound variable` au lieu d'afficher son
> aide est un script qu'on finit par contourner.

Les livrables `~/lab06/backup/PROCEDURE.md` et `~/.vimrc` sont évalués sur leur
contenu, pas sur leur forme. `PROCEDURE.md` doit répondre à quatre questions :
qu'est-ce qui est sauvegardé et pourquoi ce qui ne l'est pas ne l'est pas ;
comment on restaure, commande exacte comprise ; comment on vérifie l'intégrité ;
et la date du dernier test de restauration réel, avec son résultat. Les trois
premières s'écrivent en dix minutes. C'est la quatrième qui fait la différence
entre une procédure et une intention.

<!-- nav:début -->
---

[← Module 05](../05-text-processing/corrige.md) · [Énoncé](README.md) · [Module 07 →](../07-bash-scripting/corrige.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
