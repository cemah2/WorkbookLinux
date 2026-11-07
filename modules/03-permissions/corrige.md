<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Partie I — Fondamentaux du shell et du système de fichiers › **Module 03** · corrigé  
[← Module 02](../02-filesystem-fhs/corrige.md) · [Énoncé](README.md) · [Module 04 →](../04-users-groups-sudo/corrige.md)

> [!TIP]
> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, pas avant. Chaque identifiant renvoie à son énoncé.
<!-- nav:fin -->

# Module 03 — Corrigé

## 3.3 Quiz — QCM

<a id="q3-1"></a>**[Q3.1](README.md#q3-1)** — *Fichier `-rw-r--r--`, propriétaire `mathieu`, groupe `dev`, `mathieu`
membre de `dev`. Quels droits réels pour `mathieu` ?*

**Réponse : a) `rw-`, parce qu'il est le propriétaire.**

> [!NOTE]
> **Pourquoi**
>
> Le noyau évalue les triades **dans l'ordre** et s'arrête à la **première** qui
> correspond. Il pose trois questions : « es-tu le propriétaire (même UID) ? » — si
> oui, seuls les bits `u` comptent, point final. Sinon « es-tu membre du groupe
> propriétaire ? » — si oui, seuls les bits `g` comptent. Sinon les bits `o`. Comme
> `mathieu` **est** le propriétaire, l'évaluation s'arrête à la triade `u` = `rw-`.
> Son appartenance à `dev` n'est jamais consultée pour ce fichier. Il n'y a pas
> d'union des droits : c'est un « premier match gagne », pas un « ou logique ».

> [!WARNING]
> **Piège**
>
> Le corollaire surprend : si un fichier est en `----rwxrwx` (mode `077`) et que tu
> en es le propriétaire, tu n'as **aucun** droit dessus alors que tout le monde en a.
> Le propriétaire n'est jamais évalué comme « group » ni « other ». Pour te redonner
> accès, il faut modifier la triade `u` (`chmod u+rw`).

---

<a id="q3-2"></a>**[Q3.2](README.md#q3-2)** — *Répertoire en `444`, t'appartient. Que fait `ls -l docs/` ?*

**Réponse : b)** les noms s'affichent, mais chaque ligne donne `Permission denied`
sur les détails.

> [!NOTE]
> **Pourquoi**
>
> Sur un répertoire, `r` et `x` ont des rôles distincts. Le bit `r` autorise à **lire
> la liste des noms** contenus dans le répertoire : `ls docs/` fonctionne. Le bit `x`
> autorise à **traverser** le répertoire, c'est-à-dire à accéder à l'inode de chaque
> entrée pour en lire les métadonnées (taille, propriétaire, dates). Un `ls -l` a
> besoin des deux : `r` pour obtenir les noms, `x` pour aller chercher les détails de
> chacun. Avec `r--` seul, `ls` liste les noms mais échoue dès qu'il tente de faire un
> `stat()` sur chaque entrée :
>
> ```console
> $ ls -l docs/
> ls: cannot access 'docs/a.txt': Permission denied
> ls: cannot access 'docs/b.txt': Permission denied
> total 0
> -????????? ? ? ? ?            ? a.txt
> -????????? ? ? ? ?            ? b.txt
> ```

> [!WARNING]
> **Piège**
>
> La situation inverse (`--x`, mode `111`) est tout aussi contre-intuitive : `ls`
> échoue (`Permission denied`) mais `cat docs/fichier-connu` marche si tu connais le
> nom exact. C'est le fondement du répertoire « opaque » : traversable mais non
> listable, utilisé pour les homes en `711`.

---

<a id="q3-3"></a>**[Q3.3](README.md#q3-3)** — *Fichier `444` dans un répertoire à toi en `rwx`. Peux-tu le supprimer ?*

**Réponse : c) oui**, la suppression dépend du `w` sur le **répertoire**, pas sur le
fichier.

> [!NOTE]
> **Pourquoi**
>
> Supprimer un fichier, c'est retirer une entrée (nom → inode) de la table du
> répertoire qui le contient. Cette opération modifie le **répertoire**, pas le
> fichier. Il te faut donc `w` **et** `x` sur le répertoire parent, et les droits du
> fichier lui-même n'entrent pas en compte. Un fichier en lecture seule, voire en
> `000`, se supprime sans difficulté si tu possèdes le répertoire.
>
> ```console
> $ chmod 444 secret.txt
> $ rm secret.txt
> rm: remove write-protected regular file 'secret.txt'? y
> $ 
> ```
>
> `rm` pose une question de confirmation (le fichier est en lecture seule) mais
> l'efface bien : `rm -f` la supprime.

> [!WARNING]
> **Piège**
>
> L'exception est le **sticky bit** sur le répertoire (`/tmp` en `1777`) : là,
> même avec `w` sur le répertoire, tu ne peux supprimer que les fichiers dont **tu es
> propriétaire**. C'est ce qui empêche un utilisateur d'effacer les fichiers d'un
> autre dans un répertoire partagé en écriture.

---

<a id="q3-4"></a>**[Q3.4](README.md#q3-4)** — *`umask 027`, `touch f` et `mkdir d`. Modes ?*

**Réponse : a) `f` en 640, `d` en 750.**

> [!NOTE]
> **Pourquoi**
>
> Le umask **retire** des bits par un ET avec son complément. Les bases sont `666`
> pour un fichier (jamais de x demandé) et `777` pour un répertoire :
>
> ```text
> fichier    : 666 & ~027 = 666 & 750 = 640   (rw- r-- ---)
> répertoire : 777 & ~027 = 777 & 750 = 750   (rwx r-x ---)
> ```
>
> Détail du complément : `umask 027` = `000 010 111` en binaire pour les bits à
> retirer. `~027` = `111 101 000` = `750`. On applique le ET bit à bit. Le chiffre
> `7` du umask (dernière triade, `other`) retire `rwx`, d'où `---` pour other dans
> les deux cas.

---

<a id="q3-5"></a>**[Q3.5](README.md#q3-5)** — *`755` aux répertoires et `644` aux fichiers, en un seul chmod.*

**Réponse : c) `chmod -R u=rwX,go=rX /var/www/site`.**

> [!NOTE]
> **Pourquoi**
>
> Le `X` **majuscule** est la clé : il ajoute le bit `x` **uniquement** si la cible
> est un répertoire, **ou** si le fichier a déjà au moins un bit `x`. Sur une arbo web
> où aucun fichier n'est exécutable, il ne touche donc que les répertoires. Résultat :
> répertoires en `rwxr-xr-x` (755), fichiers en `rw-r--r--` (644).
>
> La réponse a) `chmod -R 755` est le piège classique : elle rend **tous** les
> fichiers exécutables (`.html`, `.css`, `.png` en `755`), ce qui est à la fois sale
> et un mauvais signal de sécurité. La b) casse la traversée des répertoires (644 =
> pas de x, plus rien n'est accessible). La d) ouvre tout en écriture au monde.

> [!WARNING]
> **Piège**
>
> `X` regarde l'état **au moment où chmod traite chaque fichier**. Si tu enchaînes
> `chmod -R a+x` puis `chmod -R u=rwX`, le premier a déjà mis x partout et le second
> le conservera : l'ordre compte. La méthode `find -type d`/`-type f` est plus
> explicite et recommandée quand tu veux être certain du résultat.

---

<a id="q3-6"></a>**[Q3.6](README.md#q3-6)** — *`/usr/bin/passwd` en `-rwsr-xr-x root root`. Le `s` ?*

**Réponse : c) SUID** : passwd s'exécute avec l'UID root pour écrire dans
`/etc/shadow`.

> [!NOTE]
> **Pourquoi**
>
> Le `s` à la place du `x` dans la triade **propriétaire** est le bit SUID (Set User
> ID). Quand un utilisateur ordinaire lance `passwd`, le processus prend l'UID
> **effectif** du propriétaire du fichier — ici root — le temps de son exécution.
> C'est indispensable : `/etc/shadow` est en `640 root:shadow`, illisible et
> inécrivable par un simple utilisateur, mais chacun doit pouvoir changer **son**
> mot de passe. Le SUID root permet à `passwd` d'ouvrir `/etc/shadow` en écriture,
> tout en contrôlant dans son code qu'on ne modifie que la ligne de l'appelant.

> [!WARNING]
> **Piège**
>
> Ne confonds pas les positions : `s` dans la 1re triade = SUID, `s` dans la 2e triade
> = SGID, `t` dans la 3e = sticky. Et `s` minuscule = bit spécial **avec** x ;
> `S`/`T` majuscule = bit spécial **sans** x sous-jacent, souvent le signe d'une
> erreur de `chmod`.

---

<a id="q3-7"></a>**[Q3.7](README.md#q3-7)** — *`/srv/partage` en `2770` groupe `facturation`, un membre y crée un
fichier. Son groupe ?*

**Réponse : b) `facturation`**, hérité du répertoire grâce au SGID.

> [!NOTE]
> **Pourquoi**
>
> Le bit SGID (`2` en tête, le `s` dans la triade groupe) a un effet **spécifique aux
> répertoires** : tout fichier ou sous-répertoire créé dedans hérite du **groupe
> propriétaire du répertoire**, et non du groupe primaire de l'utilisateur qui crée.
> Sans SGID, un fichier créé par `mathieu` (groupe primaire `mathieu`) aurait pour
> groupe `mathieu`, et les autres membres de `facturation` ne l'auraient pas dans leur
> triade `g`. Avec SGID, il est en groupe `facturation`, donc partageable. Un
> sous-répertoire créé hérite en plus **du bit SGID lui-même**, ce qui propage
> l'héritage en profondeur.

> [!WARNING]
> **Piège**
>
> Le SGID règle le **groupe**, pas les **droits `w` de groupe** sur les fichiers
> créés : ceux-ci dépendent du umask de chaque utilisateur (souvent `022`, qui retire
> `w` au groupe). D'où le fichier en groupe `facturation` mais en `rw-r--r--` :
> lisible par le groupe, pas modifiable. Pour garantir le `w` de groupe, il faut une
> **ACL par défaut** (voir L3.1) ou un umask de groupe `002`.

---

<a id="q3-8"></a>**[Q3.8](README.md#q3-8)** — *Pourquoi `/tmp` en `1777` et pas `777` ?*

**Réponse : b)** le `t` (sticky) empêche un utilisateur de supprimer les fichiers
des autres.

> [!NOTE]
> **Pourquoi**
>
> `/tmp` doit être inscriptible par tout le monde : n'importe quel processus y crée
> des fichiers temporaires. Mais `777` seul serait catastrophique : le `w` sur le
> répertoire autoriserait n'importe qui à **supprimer ou renommer** les fichiers de
> n'importe qui d'autre (la suppression dépend du `w` du répertoire, cf. Q3.3). Le
> sticky bit (`1` en tête, `t` final) restreint cette règle : dans un répertoire
> sticky, **seul le propriétaire d'un fichier** (ou le propriétaire du répertoire, ou
> root) peut le supprimer ou le renommer. Chacun gère ses fichiers, personne ne touche
> à ceux des autres. C'est exactement le besoin d'un espace temporaire partagé.

---

<a id="q3-9"></a>**[Q3.9](README.md#q3-9)** — *`find / -perm -4000 -type f`. Que cherches-tu ?*

**Réponse : c)** tous les fichiers ayant **au moins** le bit SUID positionné.

> [!NOTE]
> **Pourquoi**
>
> Le tiret devant le mode (`-4000`) change complètement la sémantique de `-perm`.
> Trois formes existent :
>
> * `-perm 4000` : mode **exactement** égal à 4000 (aucun autre bit) — quasi inutile.
> * `-perm -4000` : **tous** les bits de 4000 sont présents (ET), les autres bits
>   peuvent valoir n'importe quoi. C'est « a le SUID, peu importe le reste ».
> * `-perm /4000` : **au moins un** des bits de 4000 est présent (OU).
>
> Pour un audit SUID on veut `-perm -4000` : il attrape `-rwsr-xr-x`, `-rwsr-s---`,
> etc. La combinaison `-perm -4000 -type f` est la commande canonique d'inventaire des
> SUID, à lancer avec `2>/dev/null` pour masquer les `Permission denied` sur les
> répertoires qu'on ne peut pas traverser.

> [!WARNING]
> **Piège**
>
> Oublier le tiret (`-perm 4000`) ne renvoie presque rien, parce qu'aucun binaire réel
> n'a un mode strictement égal à `4000` (il faut au moins un `x`). C'est une erreur
> d'audit fréquente qui fait croire à tort qu'un système n'a aucun SUID.

---

<a id="q3-10"></a>**[Q3.10](README.md#q3-10)** — *ACL avec `mask::r--`, entrée `u:webdev:rwx #effective:r--`. webdev
peut-il écrire ?*

**Réponse : b) non** : le masque `r--` plafonne son droit effectif à `r--`.

> [!NOTE]
> **Pourquoi**
>
> Dans une ACL POSIX, le **masque** (`mask::`) est un plafond appliqué à toutes les
> entrées « nommées » (utilisateurs et groupes autres que le propriétaire) **et** au
> groupe propriétaire. Le droit réellement accordé est l'**intersection** entre
> l'entrée nominale et le masque. Ici : `u:webdev = rwx` ∩ `mask = r--` = `r--`.
> `getfacl` le rend explicite avec la colonne `#effective:r--`. Même si l'entrée dit
> `rwx`, `webdev` ne peut que lire.
>
> Le masque existe pour donner un moyen simple de **restreindre d'un coup** tous les
> droits étendus sans réécrire chaque entrée : baisser le masque à `r--` met tout le
> monde en lecture seule instantanément.

> [!WARNING]
> **Piège**
>
> `setfacl` **recalcule automatiquement** le masque à chaque `-m` sur une entrée
> nommée, en prenant l'union des droits demandés. C'est pourquoi un masque à `r--`
> apparu « tout seul » vient presque toujours d'un `chmod` fait **après** la pose de
> l'ACL : `chmod g-w` sur un fichier avec ACL modifie en fait le **masque**, pas le
> groupe propriétaire. Pour figer un masque, utilise `setfacl -n` (ne pas recalculer)
> ou pose-le explicitement avec `-m mask::rwx`.

---

<a id="q3-11"></a>**[Q3.11](README.md#q3-11)** — *Faire que tout nouveau fichier de `/srv/data` donne `rX` au groupe
`webdev` automatiquement.*

**Réponse : c) `setfacl -d -m g:webdev:rX /srv/data`.**

> [!NOTE]
> **Pourquoi**
>
> L'option `-d` pose une ACL **par défaut** (default ACL) sur le répertoire. Une ACL
> par défaut ne s'applique **pas** au répertoire lui-même : c'est un **patron** que le
> noyau copie comme ACL d'accès sur chaque fichier ou sous-répertoire **créé ensuite**
> dans ce répertoire. C'est le seul mécanisme qui rend l'attribution automatique et
> persistante sans relancer `setfacl`.
>
> La réponse a) (`setfacl -m`, sans `-d`) donne le droit sur le répertoire **actuel**
> mais pas aux futurs fichiers. La b) (`-R`) applique sur tout l'**existant** mais rien
> sur le futur. En pratique on combine souvent les deux : `setfacl -R -m ... ` pour
> l'existant **et** `setfacl -d -m ...` pour le futur.

> [!WARNING]
> **Piège**
>
> Une ACL par défaut n'a de sens que sur un répertoire. Le `X` majuscule dans
> `g:webdev:rX` reste utile : sur les fichiers créés il donnera `r--`, sur les
> sous-répertoires créés il donnera `r-x` (traversable). Poser `rwx` en défaut
> donnerait des fichiers exécutables, ce qu'on ne veut pas.

---

<a id="q3-12"></a>**[Q3.12](README.md#q3-12)** — *`chattr +i /etc/resolv.conf`, puis `echo > ...` en root.*

**Réponse : b) `Operation not permitted`**, il faut d'abord `chattr -i`.

> [!NOTE]
> **Pourquoi**
>
> L'attribut `i` (immuable) est géré par le **système de fichiers**, en dessous du
> modèle de permissions ugo, et il s'applique **y compris à root**. Un fichier immuable
> ne peut être ni modifié, ni renommé, ni supprimé, ni lié en dur, et son contenu ne
> peut être ouvert en écriture — quel que soit l'UID. La seule façon de le toucher est
> de retirer d'abord l'attribut avec `chattr -i` (ce qui nécessite la capability
> `CAP_LINUX_IMMUTABLE`, que root a par défaut mais qu'on peut retirer à un conteneur).
>
> ```console
> # echo "nameserver 9.9.9.9" > /etc/resolv.conf
> bash: /etc/resolv.conf: Operation not permitted
> # chattr -i /etc/resolv.conf
> # echo "nameserver 9.9.9.9" > /etc/resolv.conf   # ok maintenant
> ```

> [!WARNING]
> **Piège**
>
> C'est une cause classique de « le déploiement échoue mystérieusement en root ».
> `ls -l` ne montre **rien** d'anormal (les permissions sont ordinaires) : seul
> `lsattr` révèle le `----i---------e-------`. Réflexe : devant un `Operation not
> permitted` en root sur un fichier ordinaire, penser `lsattr`.

---

<a id="q3-13"></a>**[Q3.13](README.md#q3-13)** — *Écouter sur le port 80 sans tourner en root, méthode la plus sûre.*

**Réponse : c) `setcap cap_net_bind_service=+ep /opt/app/api`.**

> [!NOTE]
> **Pourquoi**
>
> Les ports en dessous de 1024 sont « privilégiés » : les lier exige la capability
> `CAP_NET_BIND_SERVICE`. La bonne pratique moderne est d'accorder **cette seule
> capability** au binaire, et rien d'autre. Le processus tourne alors sous un compte
> non privilégié, ne possède que le pouvoir de binder un port bas, et rien de plus :
> s'il est compromis, l'attaquant n'hérite pas des pouvoirs de root.
>
> `=+ep` positionne la capability dans les ensembles **effective** et **permitted**
> du fichier, ce qui la rend active dès le lancement sans que le programme ait à la
> demander lui-même.

> [!WARNING]
> **Piège**
>
> Les réponses a) et d) (SUID root) fonctionnent mais accordent **tous** les pouvoirs
> de root au binaire : une faille dans l'application donne un shell root complet. La
> b) (tourner en root) est encore pire. Sur systemd, l'équivalent déclaratif est
> `AmbientCapabilities=CAP_NET_BIND_SERVICE` dans l'unité, souvent préférable car il
> ne marque pas le fichier sur disque.

---

<a id="q3-14"></a>**[Q3.14](README.md#q3-14)** — *ssh refuse la clé : `Permissions 0644 ... are too open`.*

**Réponse : b)** ssh exige que la clé privée soit lisible seulement par son
propriétaire (600).

> [!NOTE]
> **Pourquoi**
>
> `ssh` **refuse volontairement** d'utiliser une clé privée si son groupe ou les
> autres ont le moindre droit dessus. Une clé en `644` est lisible par tout le monde
> sur la machine : n'importe quel utilisateur local pourrait la copier et usurper ton
> identité. Le client ssh vérifie ce point au démarrage et abandonne plutôt que de
> prendre le risque. La correction est `chmod 600 ~/.ssh/id_ed25519` (voire `400`).
>
> ```console
> $ chmod 600 ~/.ssh/id_ed25519
> $ ssh lab-web    # fonctionne maintenant
> ```

> [!WARNING]
> **Piège**
>
> Le même contrôle s'applique au répertoire `~/.ssh` (attendu `700`) et au fichier
> `~/.ssh/authorized_keys` côté serveur : si `~/.ssh` ou le home sont inscriptibles
> par le groupe, `sshd` peut refuser l'authentification par clé (option
> `StrictModes yes`, activée par défaut). Le diagnostic se lit dans `journalctl -u ssh` (ou
> `/var/log/auth.log` si rsyslog est installé) : `Authentication refused: bad ownership or modes`.

---

<a id="q3-15"></a>**[Q3.15](README.md#q3-15)** — *`Permission denied` sur un fichier en `644` : outil le plus direct ?*

**Réponse : b) `namei -l /srv/factura/exports/rapport.csv`.**

> [!NOTE]
> **Pourquoi**
>
> `namei -l` déroule le chemin **composant par composant** depuis la racine et affiche
> les droits, le propriétaire et le groupe de **chaque** répertoire traversé, plus le
> fichier final. Comme un accès exige le bit `x` sur **tous** les répertoires parents,
> c'est l'outil qui montre d'un coup lequel bloque :
>
> ```console
> $ namei -l /srv/factura/exports/rapport.csv
> f: /srv/factura/exports/rapport.csv
>  drwxr-xr-x root    root     /
>  drwxr-xr-x root    root     srv
>  drw-r--r-- root    facturation  factura     <- pas de x : bloque tout
>  drwxrwx--- root    facturation  exports
>  -rw-r--r-- root    facturation  rapport.csv
> ```
>
> Ici le fichier est bien en `644`, mais `factura` a perdu son bit `x` : impossible de
> traverser, donc `Permission denied` sur tout ce qui est en dessous.

> [!WARNING]
> **Piège**
>
> Réflexe à ancrer : un `Permission denied` sur un fichier aux droits corrects vient
> **presque toujours d'un répertoire parent**, pas du fichier. `cat` (a) reproduit le
> symptôme sans expliquer, `chmod 777` (c) est un pansement dangereux qui masque la
> vraie cause, `stat` (d) ne montre que le fichier final. `namei -l` est chirurgical.

---

<a id="q3-16"></a>**[Q3.16](README.md#q3-16)** — *`drwxr-x---+` : le `+` final ?*

**Réponse : b)** une ACL POSIX étendue est présente.

> [!NOTE]
> **Pourquoi**
>
> Le `+` en fin de la chaîne de permissions dans `ls -l` signale que le fichier ou le
> répertoire porte une **ACL étendue** — c'est-à-dire des entrées au-delà des trois
> triades ugo standard (des `user:nom:` ou `group:nom:` nommés, ou un masque). Les
> neuf bits affichés par `ls -l` ne racontent alors qu'une partie de l'histoire : il
> faut `getfacl` pour voir l'ensemble des droits réels. Un `.` à la place (`drwxr-x---.`
> sur RHEL) indiquerait un contexte SELinux mais pas d'ACL.

---

<a id="q3-17"></a>**[Q3.17](README.md#q3-17)** — *Binaire en `-rwSr--r--`. Le `S` majuscule ?*

**Réponse : b) SUID positionné mais sans bit `x` sur le propriétaire** — donc
inopérant, et généralement le signe d'une erreur.

> [!NOTE]
> **Pourquoi**
>
> La casse du caractère spécial encode la présence du bit `x` sous-jacent :
>
> * `s` minuscule = bit spécial **+** `x` présent → le SUID est effectif.
> * `S` majuscule = bit spécial **sans** `x` → le bit est posé mais ne sert à rien,
>   puisqu'il n'y a pas d'exécution à détourner.
>
> Un `-rwSr--r--` révèle typiquement un `chmod 4644` maladroit (on voulait `4755`) ou
> un `chmod u-x` sur un binaire déjà SUID. Ce n'est pas exploitable en l'état, mais
> c'est un signal d'audit : quelqu'un a manipulé les bits spéciaux sans comprendre.

---

<a id="q3-18"></a>**[Q3.18](README.md#q3-18)** — *Service systemd sans `UMask=`, shell en `umask 077`. Quel umask pour le
fichier créé par le service ?*

**Réponse : b) `022`, la valeur par défaut de systemd.**

> [!NOTE]
> **Pourquoi**
>
> Un service lancé par systemd **n'hérite pas** du umask de ton shell interactif : il
> n'y a aucun lien de parenté entre ta session et le processus démarré par le
> gestionnaire de services. Le umask d'un service est celui du manager, soit `0022`
> par défaut, sauf si l'unité déclare explicitement `UMask=` dans sa section
> `[Service]`. C'est pourquoi un fichier écrit par un démon apparaît souvent en `644`
> même si tu as durci ton propre shell à `077`.
>
> Pour qu'un service crée des fichiers restreints, il faut le lui dire dans l'unité :
>
> ```ini
> [Service]
> UMask=0027
> ```

> [!WARNING]
> **Piège**
>
> Ce découplage explique une confusion fréquente : « j'ai mis `umask 077` dans
> `/etc/profile`, pourquoi mes logs de service sont-ils en 644 ? ». `/etc/profile`
> n'est lu que par les shells de login interactifs, jamais par systemd. Pour un umask
> système appliqué **aussi** aux sessions PAM, il faut `pam_umask` et `/etc/login.defs`
> (`UMASK`), et pour les services, la directive `UMask=` unité par unité.

---

## 3.4 Quiz — questions ouvertes

<a id="qo3-1"></a>**[QO3.1](README.md#qo3-1)** — *Pourquoi le propriétaire d'un fichier en `077` n'y a-t-il aucun accès
alors que les autres oui ?*

Le noyau évalue les triades dans l'ordre **propriétaire → groupe → autres** et
s'arrête à la première catégorie qui correspond à l'appelant. Le propriétaire tombe
toujours dans la triade `u` **et nulle part ailleurs** : ses droits sont ceux de
`u`, ici `---`, donc aucun. Un membre du groupe utilise la triade `g` = `rwx`, un
tiers la triade `o` = `rwx`. Le propriétaire n'est jamais « rattrapé » par les
triades suivantes, même si elles sont plus larges.

> [!NOTE]
> **Pourquoi**
>
> Principe général : le contrôle d'accès Unix est un **premier match**, pas un cumul.
> La catégorie la plus spécifique gagne, et « propriétaire » est plus spécifique que
> « groupe », qui est plus spécifique que « autres ». Le cas paradoxal `077` sert de
> test : si on croyait à une union des droits, le propriétaire aurait `rwx` ; le fait
> qu'il n'ait rien prouve la règle du premier match. Correction : `chmod u+rw`.

---

<a id="qo3-2"></a>**[QO3.2](README.md#qo3-2)** — *Calcul complet pour `umask 007`, et pourquoi un umask n'ajoute jamais
le x d'un fichier.*

```text
umask 007  ->  bits retirés : ------rwx  (dernière triade complète)
fichier    : 666 & ~007 = 666 & 770 = 660   (rw- rw- ---)
répertoire : 777 & ~007 = 777 & 770 = 770   (rwx rwx ---)
```

> [!NOTE]
> **Pourquoi**
>
> Le umask ne **soustrait** pas, il **masque** : c'est un ET logique entre le mode
> « demandé » par le programme créateur et le complément du umask. Un fichier créé par
> `touch`, `>` ou `open()` demande au maximum `666` (rw pour les trois triades) : le
> bit `x` n'est **jamais** dans le mode demandé pour un fichier ordinaire, car ni le
> noyau ni ces outils ne réclament l'exécution. Or un ET ne peut qu'**éteindre** des
> bits, jamais en allumer. Donc aucun umask ne peut rendre un fichier exécutable à la
> création : le `x` doit être posé explicitement ensuite (`chmod +x`). Les répertoires,
> eux, sont demandés en `777` (la traversée est nécessaire), d'où leur `x` conservé.

> [!WARNING]
> **Piège**
>
> `umask 002` (courant sur les serveurs collaboratifs) donne des répertoires `775` et
> des fichiers `664` : parfait pour un partage de groupe, mais dangereux si le groupe
> primaire de chaque utilisateur est un groupe partagé — chaque fichier devient
> modifiable par tout le groupe. D'où la pratique des « user private groups » (chaque
> utilisateur a son propre groupe primaire) qui rend `umask 002` sûr.

---

<a id="qo3-3"></a>**[QO3.3](README.md#qo3-3)** — *SGID fichier vs SGID répertoire, cas d'usage réel du second.*

Sur un **fichier** exécutable, SGID (`2000`) fait tourner le programme avec le
**GID effectif du groupe propriétaire** du fichier, comme SUID le fait pour l'UID.
Exemple : `/usr/bin/wall` ou `/usr/bin/write` sont SGID `tty` pour écrire sur les
terminaux. Sur un **répertoire**, SGID a un tout autre effet : les fichiers et
sous-répertoires créés dedans **héritent du groupe** du répertoire (pas du groupe
primaire du créateur), et les sous-répertoires héritent aussi du bit SGID.

> [!NOTE]
> **Pourquoi**
>
> Cas d'usage réel du SGID sur répertoire : un espace de travail partagé
> `/srv/projet` en groupe `equipe-projet`, mode `2775`. Sans SGID, chaque membre y
> crée des fichiers dans **son** groupe primaire, illisibles pour les collègues ; il
> faudrait un `chgrp` manuel après chaque création. Avec SGID, tout fichier déposé est
> automatiquement en groupe `equipe-projet` : le partage fonctionne sans intervention.
> C'est le mécanisme de base de tout répertoire collaboratif, souvent complété par une
> ACL par défaut pour garantir en plus le `w` de groupe.

> [!WARNING]
> **Piège**
>
> Le SGID répertoire ne donne **que** l'héritage du groupe, pas les droits d'écriture.
> Beaucoup s'arrêtent à `2775` et s'étonnent que les fichiers déposés (en `664` si
> umask `002`, ou `644` si umask `022`) ne soient pas modifiables par le groupe. La
> réponse complète associe SGID **et** un umask/ACL adapté.

---

<a id="qo3-4"></a>**[QO3.4](README.md#qo3-4)** — *Rôle du masque ACL, entrée `rwx` qui ne donne que `r--`, recalcul.*

Le **masque** (`mask::`) est un plafond de droits appliqué à toutes les entrées ACL
nommées (utilisateurs et groupes autres que le propriétaire) et au groupe
propriétaire. Le droit **effectif** d'une entrée est l'intersection (ET) entre les
droits déclarés de l'entrée et le masque. Une entrée `u:webdev:rwx` avec un masque
`r--` n'accorde donc que `r--`, ce que `getfacl` annote `#effective:r--`.

> [!NOTE]
> **Pourquoi**
>
> `setfacl` **recalcule** le masque à chaque modification d'une entrée nommée (`-m`),
> en le fixant à l'union des droits de toutes les entrées, afin de ne jamais bloquer
> un droit qu'on vient d'accorder. Un masque trop restrictif apparaît donc rarement
> par `setfacl` ; il vient presque toujours d'un `chmod` postérieur : sur un fichier
> porteur d'ACL, `chmod g-w` modifie en réalité le **masque**, pas le groupe
> propriétaire — un piège majeur. Pour figer un masque à une valeur précise :
> `setfacl -m mask::rwx fichier`, ou `setfacl -n -m ...` pour empêcher le recalcul
> automatique lors des modifications suivantes.

---

<a id="qo3-5"></a>**[QO3.5](README.md#qo3-5)** — *SUID root vulnérable : ce qu'un attaquant local en fait, et pourquoi
une capability aurait limité les dégâts.*

Un binaire SUID root s'exécute avec l'UID effectif root, quel que soit l'appelant.
Si l'attaquant local trouve une faille — injection de commande, débordement, chemin
relatif exploitable, variable d'environnement dangereuse (`PATH`, `LD_PRELOAD` sur
un binaire mal protégé) — il détourne l'exécution **avec les pleins pouvoirs de
root** : il peut lire `/etc/shadow`, créer un shell SUID root à lui, modifier
n'importe quel fichier, charger un module noyau. Une simple vulnérabilité dans un
outil anodin devient une **compromission totale de la machine**.

> [!NOTE]
> **Pourquoi**
>
> Une capability limite le pouvoir accordé à **un seul privilège précis**. Un binaire
> avec `cap_net_bind_service` compromis ne peut que binder des ports bas : il ne peut
> ni lire `/etc/shadow`, ni écrire hors de ses droits normaux, ni escalader vers root.
> La surface d'attaque passe de « tout » à « une action ». C'est le principe du
> moindre privilège appliqué au niveau du binaire. En entretien, cite aussi les
> protections complémentaires : `PATH` absolu dans le code, `secure_getenv`, et
> `nosuid` sur les montages où l'on ne veut aucun SUID.

---

<a id="qo3-6"></a>**[QO3.6](README.md#qo3-6)** — *Groupe+SGID contre ACL pour un partage à trois, limite du groupe que
l'ACL résout.*

(a) **Groupe + SGID + `g+w`** : on crée un groupe, on y met les trois utilisateurs,
on met le répertoire en `2775` (ou `2770`), et un umask `002` garantit le `w` de
groupe. Simple, lisible, performant, standard. C'est la bonne réponse quand les
trois personnes forment une **équipe stable** et qu'on peut créer/administrer un
groupe.

(b) **ACL POSIX** : on pose `setfacl -m u:alice:rwx,u:bob:rwx,u:carol:rX` (+ défaut).
C'est la bonne réponse quand on **ne peut pas** créer de groupe (droits admin
absents, politique de séparation), quand les droits **diffèrent par personne**
(Carol en lecture seule, les autres en écriture), ou quand un fichier doit être
partagé avec quelqu'un **en plus** d'un partage de groupe existant.

> [!NOTE]
> **Pourquoi**
>
> Limite concrète du modèle par groupe que les ACL résolvent : un fichier n'a **qu'un
> seul** groupe propriétaire. Si `rapport.csv` doit être modifiable par l'équipe
> `facturation` **et** lisible par l'équipe `audit`, le modèle ugo est coincé : une
> seule triade `g`. Il faudrait dupliquer le fichier ou fusionner les groupes. Les ACL
> permettent d'empiler autant d'entrées `group:` et `user:` que nécessaire sur le même
> objet, avec des droits distincts — c'est leur raison d'être.

---

<a id="qo3-7"></a>**[QO3.7](README.md#qo3-7)** — *Démarche complète face à un `Permission denied` sur un fichier « en
644 ».*

1. Reproduire et localiser : `sudo -u <user> cat /chemin/fichier` pour confirmer que
   ça échoue bien pour **cet** utilisateur (et pas seulement dans un contexte
   particulier).
2. Dérouler le chemin : `namei -l /chemin/complet/fichier` — c'est le pivot. On
   cherche un répertoire parent **sans `x`** pour l'utilisateur : la traversée exige
   `x` à **chaque** étage.
3. Vérifier l'identité réelle : `id <user>` — l'utilisateur est-il bien dans le
   groupe qu'on croit ? Un ajout de groupe récent n'est effectif qu'après
   reconnexion (les groupes sont fixés à l'ouverture de session).
4. Regarder le fichier lui-même : `ls -l` et `getfacl` — une ACL restrictive ou un
   masque peut refuser un droit que les 9 bits laissent croire ouvert (un `+` en fin
   de `ls -l` l'annonce).
5. Écarter les attributs : `lsattr` sur le fichier (un `+i`/`+a` bloque l'écriture).
6. Écarter le MAC : `getenforce` (SELinux, RHEL) doit être `Permissive`/`Disabled`
   ou le contexte cohérent ; `aa-status` (AppArmor, Ubuntu) pour voir si un profil
   confine le processus. Les logs : `ausearch -m avc` / `dmesg | grep DENIED`.

> [!NOTE]
> **Pourquoi**
>
> L'ordre n'est pas cosmétique : `namei -l` en deuxième position parce que le
> répertoire parent est la cause dans la grande majorité des cas, avant même de
> suspecter ACL ou MAC. On ne passe à SELinux/AppArmor qu'**après** avoir épuisé le
> modèle DAC (ugo + ACL + attributs), sinon on perd des heures à traquer un profil
> alors qu'il manquait un `x` sur `/srv`. Réflexe transversal : un `Permission denied`
> en **root** sur un fichier ordinaire oriente d'emblée vers `lsattr` (immuable) ou un
> montage `ro`/`nosuid`, pas vers les permissions.

---

<a id="qo3-8"></a>**[QO3.8](README.md#qo3-8)** — *`chattr +i` et `+a` : usages et piège de `+i`.*

`chattr +i` (immuable) : le fichier ne peut être ni modifié, ni renommé, ni
supprimé, ni lié, **même par root**. Usage : figer un fichier de conf critique qu'un
outil réécrit à tort (`/etc/resolv.conf` écrasé par un client DHCP ou
`systemd-resolved`), ou verrouiller un binaire sensible contre l'altération.

`chattr +a` (append-only) : on ne peut qu'**ajouter** en fin de fichier, jamais
réécrire ni tronquer ni supprimer. Usage : un journal d'audit qu'on veut protéger
contre l'effacement de traces par un attaquant, tout en continuant à écrire dedans.

> [!NOTE]
> **Pourquoi**
>
> Le piège de `+i` : il casse **silencieusement** les mises à jour. Un `apt upgrade`
> qui doit remplacer un fichier immuable échoue, un déploiement Ansible/CI qui réécrit
> la conf s'arrête sur `Operation not permitted`, et rien dans `ls -l` n'explique
> pourquoi — seul `lsattr` le révèle. Règle : documenter tout `+i` posé, et prévoir la
> levée (`chattr -i`) dans la procédure de mise à jour. C'est une protection puissante
> mais qui doit rester tracée, sinon elle se retourne contre l'exploitant lui-même.

---

## 3.5 Exercices guidés

<a id="e3-1"></a>**[E3.1](README.md#e3-1)** — *Prédire puis vérifier une suite de chmod à partir de `600`.*

```bash
chmod 600 f          # rw-------  (600)
chmod g+r,o+r f      # rw-r--r--  (644)
chmod g=u f          # rw-rw-r--  (664) : g copie la triade u actuelle (rw-)
chmod o= f           # rw-rw----  (660)
```

> [!NOTE]
> **Pourquoi**
>
> `g=u` copie les droits **courants** de `u` (à cet instant `rw-`) vers `g`, ce n'est
> pas un lien : si tu changes `u` ensuite, `g` ne bouge pas. `o=` (rien après le `=`)
> vide entièrement la triade `other`. Prédire avant de taper est l'exercice qui ancre
> la mécanique symbolique.

---

<a id="e3-2"></a>**[E3.2](README.md#e3-2)** — *Répertoire privé strict et répertoire de groupe en lecture/traversée.*

```bash
mkdir -p ~/lab03/prive ~/lab03/depot
chmod 700 ~/lab03/prive     # rwx------  toi seul
chmod 750 ~/lab03/depot     # rwxr-x---  groupe : lister + traverser, pas écrire
```

> [!NOTE]
> **Pourquoi**
>
> `700` : personne d'autre ne peut ni lister (`r`) ni entrer (`x`). `750` : le groupe
> a `r-x` (lister et traverser) mais pas `w` (pas de création/suppression), et `other`
> est totalement exclu. C'est le duo de base de tout cloisonnement par répertoire.

---

<a id="e3-3"></a>**[E3.3](README.md#e3-3)** — *`755`/`644` sur une arbo mixte, sans puis avec `find`.*

```bash
# sans find : X majuscule
chmod -R u=rwX,go=rX ~/lab03/mixte

# avec find : séparation par type
find ~/lab03/mixte -type d -exec chmod 755 {} +
find ~/lab03/mixte -type f -exec chmod 644 {} +
```

> [!NOTE]
> **Pourquoi**
>
> `X` n'ajoute `x` que sur les répertoires (et les fichiers déjà exécutables), donc les
> `.txt` restent en `644`. La version `find` est plus explicite et ne dépend pas de
> l'état préalable des bits `x` : c'est celle à privilégier quand des fichiers pouvaient
> déjà être exécutables et qu'on veut un résultat déterministe. `-exec ... {} +`
> regroupe les fichiers en un minimum d'appels à `chmod` (plus rapide que `\;`).

> [!WARNING]
> **Piège**
>
> `chmod -R 755` (sans `X`) rendrait les `.txt` et `.sh` tous exécutables : c'est
> l'erreur que l'exercice fait éviter.

---

<a id="e3-4"></a>**[E3.4](README.md#e3-4)** — *Répertoire `x` sans `r` : accès par nom mais pas de listing.*

```bash
chmod 111 ~/lab03/lecture
cat ~/lab03/lecture/connu.txt     # OK : x permet de traverser vers un nom connu
ls ~/lab03/lecture                # échoue : r manquant pour lister les noms
# ls: cannot open directory '.../lecture': Permission denied
```

> [!NOTE]
> **Pourquoi**
>
> `x` seul = « traversable mais opaque » : tu atteins un fichier si tu connais son nom
> exact, mais tu ne peux pas découvrir ce qu'il y a dedans. C'est exactement le
> principe d'un home en `711` : les autres peuvent accéder à `~/public_html/index.html`
> sans pouvoir fouiller ton home. Confirme le mécanisme de la Q3.2 par la pratique.

---

<a id="e3-5"></a>**[E3.5](README.md#e3-5)** — *Droits de chaque composant du chemin.*

```bash
namei -l /srv/factura/exports/rapport.csv
```

> [!NOTE]
> **Pourquoi**
>
> `namei -l` affiche une ligne par composant (`/`, `srv`, `factura`, `exports`, le
> fichier) avec mode, propriétaire et groupe. C'est **l'**outil de diagnostic des
> `Permission denied` : il montre le premier répertoire qui n'a pas le `x` requis pour
> la traversée.

---

<a id="e3-6"></a>**[E3.6](README.md#e3-6)** — *SGID sur `~/lab03/partage`, preuve d'héritage de groupe.*

```bash
sudo chgrp facturation ~/lab03/partage
chmod 2775 ~/lab03/partage           # le 2 = SGID
touch ~/lab03/partage/test
ls -l ~/lab03/partage/test    # groupe facturation, pas ton groupe primaire
# -rw-r--r-- 1 mathieu facturation 0 ... test
```

> [!NOTE]
> **Pourquoi**
>
> Sans SGID, `test` serait en groupe `mathieu` (groupe primaire du créateur). Le bit
> SGID sur le **répertoire** force le groupe hérité à celui du répertoire,
> `facturation`. Vérifie que le `s` apparaît bien dans la triade groupe du répertoire :
> `drwxrwsr-x`.

---

<a id="e3-7"></a>**[E3.7](README.md#e3-7)** — *Reproduire `/tmp` en `1777`.*

```bash
mkdir ~/lab03/commun
chmod 1777 ~/lab03/commun            # drwxrwxrwt
echo "Le sticky bit empêche un utilisateur de supprimer ou renommer un \
fichier dont il n'est pas propriétaire, même si le répertoire est en écriture \
pour tous." > ~/lab03/commun-note.txt
```

> [!NOTE]
> **Pourquoi**
>
> Le `1` en tête pose le sticky bit, visible par le `t` final. Sans lui, `rwxrwxrwx`
> laisserait n'importe qui effacer les fichiers d'autrui, puisque la suppression
> dépend du `w` du répertoire. Le sticky restreint la suppression au propriétaire du
> fichier : c'est ce qui rend un répertoire mondialement inscriptible utilisable sans
> sabotage.

---

<a id="e3-8"></a>**[E3.8](README.md#e3-8)** — *Inventaire SUID trié + justification de trois d'entre eux.*

```bash
find / -perm -4000 -type f 2>/dev/null | sort
cat > ~/lab03/suid-note.txt <<'EOF'
passwd : doit écrire dans /etc/shadow (640 root:shadow) pour changer un mot
         de passe -> SUID root indispensable.
sudo   : doit passer à l'UID cible (souvent root) pour exécuter la commande
         demandée après vérification -> SUID root par conception.
mount  : monter un système de fichiers est une opération privilégiée réservée
         à root -> SUID root pour les montages autorisés dans /etc/fstab (user).
EOF
```

> [!NOTE]
> **Pourquoi**
>
> Ces trois-là sont SUID root **par nécessité fonctionnelle** : ils accomplissent une
> opération privilégiée pour le compte d'un utilisateur ordinaire, après un contrôle
> interne de ce qui est permis. La compétence d'audit consiste à distinguer ces cas
> légitimes des SUID **superflus** (un script métier, un binaire maison) qui, eux,
> sont des portes d'entrée à supprimer.

---

<a id="e3-9"></a>**[E3.9](README.md#e3-9)** — *Donner `rX` à `webdev` sur `exports` via ACL, sans groupe ni `other`.*

```bash
sudo setfacl -m u:webdev:rX /srv/factura/exports
getfacl /srv/factura/exports
# user:webdev:r-x
```

> [!NOTE]
> **Pourquoi**
>
> `setfacl -m u:webdev:rX` ajoute une entrée nominale pour `webdev` sans toucher aux
> bits `other` (qui restent `---`) ni exiger de l'ajouter à un groupe. C'est le cœur du
> cas d'usage ACL : un droit ciblé sur une personne, sans effet de bord sur le reste
> du monde. Le `+` apparaît maintenant dans `ls -ld`.

---

<a id="e3-10"></a>**[E3.10](README.md#e3-10)** — *ACL par défaut sur `incoming` pour le groupe `webdev`.*

```bash
sudo setfacl -d -m g:webdev:rw /srv/factura/incoming
# test : un fichier créé par facturation hérite de l'ACL
sudo -u facturation touch /srv/factura/incoming/nouveau
getfacl /srv/factura/incoming/nouveau
# group:webdev:rw-  (hérité de la default ACL)
```

> [!NOTE]
> **Pourquoi**
>
> L'option `-d` pose une ACL **par défaut** : elle ne change rien à `incoming`
> lui-même, mais sert de patron copié sur chaque nouvel objet. Le fichier `nouveau`
> naît donc avec l'entrée `group:webdev:rw-` sans qu'on ait relancé `setfacl`. C'est le
> seul mécanisme qui automatise l'héritage de droits fins.

---

<a id="e3-11"></a>**[E3.11](README.md#e3-11)** — *Corriger le masque pour rendre `webdev:rwx` effectif.*

```bash
# situation de départ (énoncé) : masque explicite, donc non recalculé
sudo setfacl -m u:webdev:rwx,m::r /srv/factura/exports
sudo setfacl -m mask::rwx /srv/factura/exports
getfacl /srv/factura/exports
# user:webdev:rwx    (plus de #effective restrictif)
```

> [!NOTE]
> **Pourquoi**
>
> Le droit effectif est l'intersection entre l'entrée et le masque. En remontant le
> masque à `rwx`, l'entrée `u:webdev:rwx` s'applique pleinement, **sans** toucher à
> l'entrée nominale. C'est la façon propre de « débloquer » une ACL dont le masque a
> été rabaissé par un `chmod g-w` accidentel (cf. Q3.10).

---

<a id="e3-12"></a>**[E3.12](README.md#e3-12)** — *Rendre `immuable.conf` inaltérable même par root.*

```bash
sudo chattr +i ~/lab03/immuable.conf
echo test | sudo tee -a ~/lab03/immuable.conf   # Operation not permitted
sudo chattr -i ~/lab03/immuable.conf            # on lève la protection
```

> [!NOTE]
> **Pourquoi**
>
> `+i` bloque écriture, renommage et suppression pour **tout le monde**, root compris ;
> seul `chattr -i` (qui exige `CAP_LINUX_IMMUTABLE`) le lève. `lsattr` montre le `i`.
> Retenir : `ls -l` ne trahit rien, seul `lsattr` révèle l'attribut.

---

<a id="e3-13"></a>**[E3.13](README.md#e3-13)** — *Journal append-only.*

```bash
sudo chattr +a ~/lab03/audit.log
echo "ligne" | sudo tee -a ~/lab03/audit.log    # OK (append)
echo "ecrase" | sudo tee ~/lab03/audit.log      # Operation not permitted (>)
sudo rm ~/lab03/audit.log                        # Operation not permitted
sudo chattr -a ~/lab03/audit.log                 # pour nettoyer ensuite
```

> [!NOTE]
> **Pourquoi**
>
> `+a` autorise **uniquement** l'ajout en fin (`>>`), et interdit la troncature (`>`),
> le renommage et la suppression, y compris pour root. C'est la protection d'un journal
> d'audit contre l'effacement de traces : un attaquant qui prend la main ne peut pas
> réécrire l'historique tant qu'il n'a pas `CAP_LINUX_IMMUTABLE`.

---

<a id="e3-14"></a>**[E3.14](README.md#e3-14)** — *Capability `cap_net_bind_service` sur une copie de `sleep`.*

```bash
cp /bin/sleep ~/lab03/bindtest
sudo setcap cap_net_bind_service=+ep ~/lab03/bindtest
getcap ~/lab03/bindtest
# .../bindtest cap_net_bind_service=ep
sudo setcap -r ~/lab03/bindtest      # retire toutes les capabilities
```

> [!NOTE]
> **Pourquoi**
>
> `=+ep` place la capability dans les ensembles effective et permitted **du fichier** :
> elle est active au lancement sans que le programme la réclame. `setcap -r` la retire
> proprement. C'est la mécanique de base derrière le remplacement d'un SUID.

---

<a id="e3-15"></a>**[E3.15](README.md#e3-15)** — *Durcir `~/lab03/secrets/`.*

```bash
chmod 700 ~/lab03/secrets
chmod 600 ~/lab03/secrets/id_ed25519
chmod 644 ~/lab03/secrets/config
# Une clé privée en 644 est lisible par le groupe et par tous : le client ssh
# refuse de l'utiliser (contrôle intégré au client, sans rapport avec
# StrictModes qui est côté sshd) car tout utilisateur local pourrait la copier.
```

> [!NOTE]
> **Pourquoi**
>
> `ssh` applique un contrôle strict sur les clés privées : au moindre droit accordé au
> groupe ou aux autres, il abandonne avec `Permissions 0644 ... are too open`. Le
> répertoire `~/.ssh` doit être en `700` et la clé en `600` (ou `400`). Le fichier
> `config`, non secret, peut rester `644`.

---

<a id="e3-16"></a>**[E3.16](README.md#e3-16)** — *umask persistant pour fichiers `640` / répertoires `750`.*

```bash
echo 'umask 027' >> ~/.bashrc     # + ~/.profile pour les shells de login
umask 027
# fichier : 666 & ~027 = 640 ; répertoire : 777 & ~027 = 750
```

> [!NOTE]
> **Pourquoi**
>
> `umask 027` donne exactement `640`/`750` (cf. Q3.4). Pour couvrir shells interactifs
> **et** de login, pose-le dans `~/.bashrc` **et** `~/.profile` (ou, système entier,
> dans `/etc/login.defs` + `pam_umask`). Sur Ubuntu, le `~/.profile` par défaut source `~/.bashrc` pour bash; le poser aussi dans `~/.profile` couvre
> les shells de login non bash et un `~/.profile` qui ne sourcerait plus `~/.bashrc`.

---

## 3.6 Labs

### <a id="l3-1"></a>**[L3.1](README.md#l3-1)** — *Répertoire partagé pour l'équipe facturation.*

**Procédure de référence :**

```bash
# 1. groupe et appartenances (le setup les crée déjà)
sudo groupadd -f facturation
sudo usermod -aG facturation mathieu
sudo usermod -aG facturation webdev
id mathieu    # doit lister le groupe facturation

# 2. répertoire de groupe, SGID
sudo chgrp facturation /srv/factura/exports
sudo chmod 2770 /srv/factura/exports        # drwxrws--- 

# 3. ACL par défaut : rw au groupe sur tout nouveau fichier
sudo setfacl -m g:facturation:rwx /srv/factura/exports
sudo setfacl -d -m g:facturation:rw /srv/factura/exports

# 4. preuve : webdev crée, mathieu modifie
sudo -u webdev touch /srv/factura/exports/depot-webdev.csv
ls -l /srv/factura/exports/depot-webdev.csv   # groupe facturation
sudo -u mathieu sh -c 'echo x >> /srv/factura/exports/depot-webdev.csv'  # OK

# 5. other exclu
ls -ld /srv/factura/exports    # ...--- pour other
```

> [!NOTE]
> **Pourquoi**
>
> Deux mécanismes se complètent. Le **SGID** (`2` de `2770`) garantit que tout fichier
> déposé hérite du groupe `facturation` : sans lui, chacun créerait dans son groupe
> primaire et les collègues seraient exclus de la triade `g`. Mais le SGID ne donne
> **pas** le `w` de groupe sur les fichiers : le umask des utilisateurs (souvent `022`)
> retire `w` à `g`, produisant des fichiers `644` lisibles mais non modifiables par le
> groupe. L'**ACL par défaut** `default:group:facturation:rw` comble ce trou : elle est
> copiée sur chaque fichier créé, qui naît donc avec `group:facturation:rw` effectif.
> La combinaison SGID + ACL par défaut est le patron canonique du répertoire
> collaboratif réellement fonctionnel.

> [!WARNING]
> **Piège**
>
> S'arrêter à `2770` sans ACL (ni umask `002`) est l'erreur la plus fréquente : le
> groupe est bon mais les fichiers restent `rw-r- -r--`, et « on ne peut pas modifier
> le fichier du collègue » alors que « pourtant on est dans le bon groupe ». Le
> symptôme trompe : le groupe est correct, ce sont les **bits `w`** qui manquent.

---

### <a id="l3-2"></a>**[L3.2](README.md#l3-2)** — *Lecture seule pour un auditeur via ACL.*

**Procédure de référence :**

```bash
# 1. état initial : webdev est un auditeur externe, hors du groupe
sudo gpasswd -d webdev facturation        # s'il y avait été mis en L3.1
sudo -u webdev ls /srv/factura/exports    # Permission denied

# 2 & 3. ACL d'accès (existant) + ACL par défaut (futur), récursif
sudo setfacl -R -m u:webdev:rX /srv/factura
sudo setfacl -R -d -m u:webdev:rX /srv/factura

# 4. vérifs
sudo -u webdev cat /srv/factura/exports/rapport.csv   # OK, lecture
sudo -u webdev touch /srv/factura/exports/x    # Permission denied (pas de w)
getfacl /srv/factura | grep webdev    # user:webdev + default:user:webdev
ls -ld /srv/factura                                   # other à ---
```

> [!NOTE]
> **Pourquoi**
>
> Le `X` majuscule est essentiel dans une pose récursive : il donne `x` (traversée) aux
> répertoires et l'omet sur les fichiers, exactement ce qu'il faut pour « lire une
> arborescence » sans rendre les fichiers exécutables. `-R -m` couvre l'existant,
> `-R -d -m` installe le patron pour tout ce qui sera créé plus tard. `webdev` obtient
> `r-x` sur les répertoires (lister + traverser) et `r- -` sur les fichiers, jamais de
> `w` : lecture stricte. `other` reste `---`, donc personne d'autre n'est exposé.

> [!WARNING]
> **Piège**
>
> La mauvaise réponse aurait été `chmod -R o+rX /srv/factura` : elle ouvre l'accès à
> **tout le monde**, pas seulement à l'auditeur, ce qui viole le besoin. C'est
> précisément le cas d'école où l'ACL (droit ciblé sur une personne) bat le modèle ugo
> (la triade `other` est « tout ou rien »). Autre piège : oublier `-d`, et les fichiers
> créés après l'audit deviennent invisibles à `webdev`.

---

### <a id="l3-3"></a>**[L3.3](README.md#l3-3)** — *Audit des binaires SUID/SGID.*

**Procédure de référence :**

```bash
# 1. inventaire trié
sudo find / \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null \
  -exec ls -l {} + | sort -k9 > ~/lab03/rapports/suid-inventaire.txt

# 3. le suspect
ls -l /usr/local/bin/factura-backup   # -rwsr-xr-x : SUID root injustifié

# 4. neutralisation
sudo chmod u-s /usr/local/bin/factura-backup
find / -perm -4000 -type f 2>/dev/null | grep factura-backup   # plus rien

# 5. les légitimes intacts
ls -l /usr/bin/passwd /usr/bin/sudo /usr/bin/mount   # toujours -rws...
```

> [!NOTE]
> **Pourquoi**
>
> `factura-backup` est SUID root sans raison fonctionnelle. Le risque d'escalade est
> concret : s'il appelle une commande **sans chemin absolu** (`tar` au lieu de
> `/bin/tar`), un attaquant place un faux `tar` en tête de `PATH` et le fait exécuter
> **en root**. S'il est **modifiable** par un non-root (droits trop larges), on y
> injecte directement du code. S'il lit un fichier contrôlé par l'utilisateur, on
> exploite le parsing. Retirer le bit SUID (`chmod u-s`) supprime le pouvoir sans
> supprimer l'outil : il continue de fonctionner, mais avec les droits de l'appelant.
> La règle : un binaire n'est SUID que si son rôle **exige** un privilège pour le
> compte d'autrui, et il doit alors être audité (chemins absolus, environnement
> neutralisé, non modifiable).

> [!WARNING]
> **Piège**
>
> `-perm 4000` (sans tiret) ne trouverait presque rien : aucun binaire n'a un mode
> strictement `4000` (il faut au moins un `x`). L'inventaire doit utiliser `-perm
> -4000`. Second piège : supprimer le binaire au lieu de retirer le bit — l'énoncé
> demande de le conserver. Nuance technique : `factura-backup` est un **script** (shebang). Le noyau Linux ignore le bit SUID des scripts interprétés, donc ce fichier précis ne s'exécute pas en root. C'est quand même un écart d'audit (un bit qui n'a rien à faire là, et qui deviendrait exploitable le jour où l'outil est réécrit en binaire compilé) : le scénario de `PATH` hijacking décrit plus haut vaut pour un ELF.

---

### <a id="l3-4"></a>**[L3.4](README.md#l3-4)** — *Bind sur le port 80 sans root via capability.*

**Procédure de référence :**

```bash
# 0. nginx tient déjà le port 80 sur lab-web : on le libère le temps du lab
sudo systemctl stop nginx
# 1. échec en non-root
sudo -u facturation /usr/local/bin/factura-api --port 80
# bind: Permission denied (port < 1024 réservé)

# 3. capability au lieu de SUID
sudo setcap cap_net_bind_service=+ep /usr/local/bin/factura-api
getcap /usr/local/bin/factura-api
# .../factura-api cap_net_bind_service=ep

# 4. preuve : bind OK en non-root
sudo -u facturation /usr/local/bin/factura-api --port 80 &
ss -tlnp | grep ':80 '     # LISTEN, processus non root
kill %1 ; sudo systemctl start nginx     # on rend le port à nginx
```

> [!NOTE]
> **Pourquoi**
>
> `CAP_NET_BIND_SERVICE` est exactement le privilège qui manque pour lier un port <
> 1024, et rien de plus. En l'accordant au binaire, le processus tourne sous
> `facturation` (compte non privilégié) tout en pouvant binder le port 80. Comparé à un
> SUID root, la surface d'attaque est réduite d'« un shell root complet en cas de
> faille » à « pouvoir binder un port bas » : le principe du moindre privilège appliqué
> au binaire. Sur un service systemd, l'équivalent déclaratif —
> `AmbientCapabilities=CAP_NET_BIND_SERVICE` et `User=facturation` — est encore
> préférable car il ne marque pas le fichier sur disque et se versionne avec l'unité.

> [!WARNING]
> **Piège**
>
> `chmod u+s` (SUID root) « marcherait » aussi mais donnerait tous les pouvoirs de root
> au binaire : une faille dans l'API = compromission totale. Autre piège : `setcap` est
> effacé si le binaire est remplacé (mise à jour, redéploiement) — il faut le
> réappliquer, d'où l'intérêt de la forme systemd pour un service en production.

---

## 3.7 Break & Fix

### <a id="bf3-1"></a>**[BF3.1](README.md#bf3-1)** — *nginx renvoie 403 sur tout le site.*

**Cause racine :** un répertoire parent de la racine web (`/var/www` ou
`/var/www/factura`) a perdu son bit `x`. nginx, tournant sous `www-data`, ne peut
plus **traverser** le chemin jusqu'aux fichiers HTML, alors que ceux-ci sont en
`644`. Le noyau refuse l'accès et nginx traduit en `403 Forbidden`.

**Diagnostic pas à pas :**

```bash
# 1. lire le vrai message côté serveur
sudo tail /var/log/nginx/error.log
# ... "Permission denied" ... open() "/var/www/factura/index.html" failed

# 2. l'outil décisif : dérouler le chemin composant par composant
sudo -u www-data namei -l /var/www/factura/index.html
# f: /var/www/factura/index.html
#  drwxr-xr-x root root  /
#  drwxr-xr-x root root  var
# drwxr-xr-- root root www      <- other sans x : www-data ne traverse pas
#                      factura - Permission denied

# 3. confirmer que le fichier lui-même est bon
ls -l /var/www/factura/index.html    # 644, rien à corriger ici
```

**Correctif (au bon niveau, bon mode) :**

```bash
sudo chmod o+x /var/www          # rétablit la traversée pour www-data (et tous)
# ou, propre et déterministe sur toute l'arbo web :
sudo find /var/www/factura -type d -exec chmod 755 {} +
sudo find /var/www/factura -type f -exec chmod 644 {} +
curl -s -o /dev/null -w '%{http_code}\n' http://10.10.10.11/   # 200
```

> [!NOTE]
> **Pourquoi**
>
> C'est l'illustration parfaite du point « r/w/x sur un répertoire ». Des fichiers en
> `644` sont lisibles **à condition** de pouvoir atteindre leur inode, ce qui exige le
> bit `x` (traversée) sur **chaque** répertoire du chemin. Un seul `x` manquant sur un
> parent rend tout le sous-arbre inaccessible, quels que soient les droits des fichiers.
> nginx ne distingue pas « fichier absent » de « chemin non traversable » côté client :
> les deux deviennent un `403`/`404`. `namei -l` lancé **en tant que `www-data`** est
> l'outil qui pointe le répertoire fautif en une ligne.

> [!WARNING]
> **Piège**
>
> La tentation est `chmod -R 777 /var/www` : ça « répare » mais ouvre le site en
> écriture au monde entier et rend tous les fichiers exécutables — une faute de
> sécurité. Le bon geste est `o+x` sur le seul répertoire fautif, ou la paire
> `find -type d/-type f` qui remet des modes propres. Prévention : ne jamais faire de
> `chmod` récursif à l'aveugle sur `/var/www`, et surveiller les déploiements qui
> « resserrent » les droits d'un parent.

---

### <a id="bf3-2"></a>**[BF3.2](README.md#bf3-2)** — *Écriture impossible dans exports, groupe qui ne suit plus.*

**Cause racine :** le bit **SGID** a été retiré de `/srv/factura/exports` (repassé de
`2770` à `0770`) et/ou l'**ACL par défaut** a été effacée. Résultat : les nouveaux
fichiers n'héritent plus du groupe `facturation` (ils prennent le groupe primaire du
créateur) et n'ont plus le `w` de groupe. Les collègues, absents de la triade `g`, ne
peuvent plus modifier.

**Diagnostic pas à pas :**

```bash
# 1. état du répertoire : le s de SGID est-il là ?
ls -ld /srv/factura/exports
# drwxrwx--- ... facturation    <- 'x' au lieu de 's' : SGID absent !

# 2. l'ACL par défaut existe-t-elle encore ?
getfacl /srv/factura/exports | grep default
# (aucune ligne default: -> le patron d'héritage a disparu)

# 3. reproduire le symptôme (mathieu est membre de facturation)
touch /srv/factura/exports/t
ls -l /srv/factura/exports/t
# -rw-r--r-- 1 mathieu mathieu ...  <- groupe mathieu, pas facturation, g sans w
```

**Correctif :**

```bash
sudo chmod 2770 /srv/factura/exports                         # remet le SGID
sudo setfacl -d -m g:facturation:rw /srv/factura/exports   # ACL défaut
sudo setfacl -m g:facturation:rwx /srv/factura/exports
# fichiers déjà mal créés : réaligner groupe et droits
sudo chgrp -R facturation /srv/factura/exports
sudo chmod -R g+rw /srv/factura/exports
```

> [!NOTE]
> **Pourquoi**
>
> Deux mécanismes distincts assurent un partage de groupe fonctionnel, et la panne a
> cassé l'un ou les deux. Le **SGID** (`2` de `2770`, le `s` dans la triade groupe)
> force l'héritage du **groupe** ; sans lui, chaque fichier naît dans le groupe primaire
> du créateur, hors de portée des collègues. L'**ACL par défaut** garantit le **`w` de
> groupe** sur les fichiers créés ; sans elle, le umask les fait naître en `644`. La
> règle à énoncer : « répertoire partagé = SGID **plus** (ACL par défaut *ou* umask
> 002), les deux sont nécessaires ». Vérifier l'un sans l'autre laisse un partage à
> moitié cassé.

> [!WARNING]
> **Piège**
>
> Symptôme trompeur : « on est pourtant dans le bon groupe ». Oui, mais le **fichier**
> n'est pas dans le bon groupe (SGID retiré), ou il l'est sans `w` de groupe (ACL
> retirée). Toujours vérifier `ls -ld` (chercher le `s`) **et** `getfacl ... | grep
> default`, pas seulement l'appartenance des utilisateurs.

---

### <a id="bf3-3"></a>**[BF3.3](README.md#bf3-3)** — *resolv.conf figé, root bloqué.*

**Cause racine :** le fichier `/etc/resolv.conf` porte l'attribut **immuable**
(`chattr +i`). L'attribut est géré par le système de fichiers, sous le modèle de
permissions, et s'applique **y compris à root** : toute écriture, tout renommage,
toute suppression échoue avec `Operation not permitted`, sans que `ls -l` ne montre
quoi que ce soit d'anormal.

**Diagnostic pas à pas :**

```bash
# 1. les permissions ont l'air normales
ls -l /etc/resolv.conf
# -rw-r--r-- 1 root root ...   <- rien de suspect ici

# 2. réflexe "Operation not permitted en root" -> lsattr
lsattr /etc/resolv.conf
# ----i---------e------- /etc/resolv.conf   <- l'attribut immuable !

# 3. confirmer l'échec
echo "nameserver 9.9.9.9" | sudo tee /etc/resolv.conf
# tee: /etc/resolv.conf: Operation not permitted
```

**Correctif :**

```bash
sudo chattr -i /etc/resolv.conf
echo "nameserver 9.9.9.9" | sudo tee /etc/resolv.conf    # fonctionne
lsattr /etc/resolv.conf                                  # plus de i
```

> [!NOTE]
> **Pourquoi**
>
> Le modèle ugo/rwx n'est pas la seule couche de contrôle : les attributs étendus
> (`chattr`) s'appliquent **en dessous** et priment sur l'identité, root inclus. `+i`
> verrouille totalement le fichier ; seul `chattr -i` (capability
> `CAP_LINUX_IMMUTABLE`) le libère. Cas légitime de cette protection : empêcher un
> `resolv.conf` d'être écrasé par `systemd-resolved` ou un client DHCP quand on veut
> figer une résolution DNS. Mais posé sans documentation, `+i` casse tout déploiement
> qui réécrit le fichier — d'où l'échec du pipeline. Réflexe à graver : un `Operation
> not permitted` **en root** sur un fichier ordinaire → `lsattr` avant tout.

> [!WARNING]
> **Piège**
>
> Chercher la cause dans les permissions (`ls -l`), le propriétaire ou un montage `ro`
> fait perdre du temps : ici tout est normal de ce côté. L'attribut est invisible sauf
> à `lsattr`. Prévention : documenter tout `chattr +i` posé en production, et inclure
> un `chattr -i` en préambule des procédures qui doivent réécrire le fichier. Note Ubuntu : sur `lab-web`, `/etc/resolv.conf` est normalement un lien vers `/run/systemd/resolve/stub-resolv.conf` ; le script de panne l'a remplacé par un fichier réel pour que `chattr` ait prise. Une fois l'exercice terminé, rétablis le lien : `sudo ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf`.

---

## 3.8 Défi du module

<a id="d3"></a>**[D3](README.md#d3) — Durcissement des permissions d'un service applicatif.**

*Livrable : `~/lab03/bin/durcir-factura.sh` + `~/lab03/rapports/durcissement-factura.md`.*

**Script de référence :**

```bash
#!/usr/bin/env bash
# durcir-factura.sh — audit + remédiation des droits du service factura.
# Idempotent. Rapport Markdown sur stdout, trace sur stderr, exit 0 si conforme.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

WEB=/var/www/factura
CONF=/etc/factura/factura.conf
SECRETS=/etc/factura/secrets
EXPORTS=/srv/factura/exports
API=/usr/local/bin/factura-api
anomalies=0      # ce qui était mauvais avant correction (pour le rapport)
restantes=0      # ce qui n'a pas pu être corrigé (code de retour)

log()  { printf '   %s\n' "$*" >&2; }
note() { printf '- %s\n' "$*"; }          # va dans le rapport (stdout)

echo "# Durcissement factura — $(date -Is)"
echo
echo "## Anomalies détectées"

# --- arborescence web : 755/644, www-data, aucun exécutable parasite --------
if [ -n "$(find "$WEB" -type f -perm /111 -print -quit)" ]; then
  note "fichiers exécutables parasites sous $WEB"; anomalies=1
fi
log "normalisation de $WEB"
find "$WEB" -type d -exec chmod 755 {} +
find "$WEB" -type f -exec chmod 644 {} +
chown -R www-data:www-data "$WEB"

# --- conf : 640 root:facturation --------------------------------------------
if [ "$(stat -c '%a %U:%G' "$CONF")" != "640 root:facturation" ]; then
  note "conf $CONF n'était pas en 640 root:facturation"; anomalies=1
fi
chown root:facturation "$CONF"; chmod 640 "$CONF"

# --- secrets : 700 dir, 600 fichiers, facturation ---------------------------
if [ -d "$SECRETS" ]; then
  chown -R facturation "$SECRETS"
  chmod 700 "$SECRETS"
  find "$SECRETS" -type f -exec chmod 600 {} +
else
  note "répertoire de secrets $SECRETS absent"; anomalies=1; restantes=1
fi

# --- exports : 2770 groupe facturation + ACL par défaut ---------------------
chgrp facturation "$EXPORTS"; chmod 2770 "$EXPORTS"
if command -v setfacl >/dev/null; then
  setfacl -m  g:facturation:rwx "$EXPORTS"
  setfacl -d -m g:facturation:rw "$EXPORTS"
else
  note "setfacl absent : impossible de garantir le w de groupe hérité"
  anomalies=1; restantes=1
fi

# --- SUID parasite sous /usr/local/bin --------------------------------------
while IFS= read -r f; do
  note "SUID inutile retiré : $f"; chmod u-s "$f"; anomalies=1
done < <(find /usr/local/bin -maxdepth 1 -perm -4000 -type f 2>/dev/null)

# --- capability à la place d'un éventuel SUID sur l'API ----------------------
if [ -x "$API" ]; then
  chmod u-s "$API" 2>/dev/null || true
  if command -v setcap >/dev/null; then
    setcap cap_net_bind_service=+ep "$API"
    log "capability posée sur $API : $(getcap "$API")"
  fi
fi

echo
echo "## État après remédiation"
note "web      : $(stat -c '%a %U:%G' "$WEB")"
note "conf     : $(stat -c '%a %U:%G' "$CONF")"
[ -d "$SECRETS" ] && note "secrets  : $(stat -c '%a %U:%G' "$SECRETS")"
note "exports  : $(stat -c '%a %U:%G' "$EXPORTS")"
[ -x "$API" ] && note "api caps : $(getcap "$API" 2>/dev/null || echo none)"

echo
if [ "$restantes" -eq 0 ]; then
  echo "Conforme ($anomalies anomalie(s) corrigée(s))."
else
  echo "Non conforme : une anomalie nécessite une action manuelle."
fi
exit "$restantes"
```

> [!NOTE]
> **Pourquoi**
>
> Le défi combine tout le module et impose les **bonnes méthodes**, pas seulement les
> bons résultats. Points clés du corrigé :
>
> * l'arbo web est normalisée par `find -type d/-type f` et non par `chmod -R 755`,
>   pour ne pas rendre les fichiers exécutables (BF3.1) ;
> * la conf en `640 root:facturation` : root propriétaire (personne d'autre n'écrit),
>   groupe `facturation` en lecture (le service lit), `other` exclu — le patron d'un
>   fichier de conf sensible ;
> * les secrets en `700`/`600` propriété du compte de service : c'est le niveau que
>   `ssh` et la plupart des démons **exigent** avant de démarrer (Q3.14) ;
> * les exports en `2770` + ACL par défaut : SGID pour l'héritage de groupe, ACL pour
>   le `w` de groupe (L3.1, BF3.2) ;
> * les SUID parasites sont retirés (`u-s`), et l'API reçoit une **capability** plutôt
>   qu'un SUID (L3.4) ;
> * séparation stricte stdout (rapport) / stderr (trace) et code de sortie exploitable,
>   pour intégration en CI : `0` dès que l'état final est conforme, même si des anomalies ont été corrigées au passage; `1` seulement s'il en reste une hors de portée du script (cahier des charges, point 4).
>
> Le tout est **idempotent** : relançable sans effet de bord, ce qu'exige un script de
> remédiation qui tournera à chaque déploiement.

> [!WARNING]
> **Piège**
>
> Trois erreurs classiques que le barème sanctionne : (1) `chmod -R 755` sur `/var/www`
> qui rend tout exécutable ; (2) oublier l'ACL par défaut sur exports, laissant un
> partage à moitié cassé ; (3) laisser un SUID root sur l'API « parce que ça marche »
> au lieu de la capability. Un script qui pose les bons modes mais par les mauvaises
> méthodes ne durcit pas : il déplace le problème.

<!-- nav:début -->
---

[← Module 02](../02-filesystem-fhs/corrige.md) · [Énoncé](README.md) · [Module 04 →](../04-users-groups-sudo/corrige.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
