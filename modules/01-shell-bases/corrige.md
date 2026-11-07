<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Partie I — Fondamentaux du shell et du système de fichiers › **Module 01** · corrigé  
[Énoncé](README.md) · [Module 02 →](../02-filesystem-fhs/corrige.md)

> [!TIP]
> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, pas avant. Chaque identifiant renvoie à son énoncé.
<!-- nav:fin -->

# Module 01 — Corrigé

## 1.3 Quiz — QCM

<a id="q1-1"></a>**[Q1.1](README.md#q1-1)** — *`n=5` puis `echo {1..$n}` : qu'affiche la commande ?*

**Réponse : b) `{1..5}`**

> [!NOTE]
> **Pourquoi**
>
> L'expansion des accolades est la **toute première** étape du traitement d'une ligne,
> avant l'expansion des paramètres. Quand bash regarde `{1..$n}`, il voit un mot qui
> ressemble à une séquence mais dont les bornes ne sont pas deux entiers : `$n` est
> encore un texte de deux caractères. Une séquence invalide n'est pas une erreur, bash
> laisse le mot **tel quel**. L'étape suivante, l'expansion des paramètres, remplace
> alors `$n` par `5`, et il ne reste plus personne pour re-traiter les accolades :
> bash ne repasse jamais une deuxième fois sur le résultat d'une expansion.
> La sortie est donc la chaîne littérale `{1..5}`.
>
> Pour obtenir la séquence à partir d'une variable, il faut forcer une seconde passe
> avec `eval "echo {1..$n}"` (à manier avec précaution) ou, bien plus sain, utiliser
> `seq 1 "$n"` ou une boucle `for ((i=1; i<=n; i++))`.

> [!WARNING]
> **Piège**
>
> Le même piège frappe `{a..$lettre}` et surtout les scripts de génération de noms :
> `for i in {1..$NB}` produit une seule itération dont la valeur est la chaîne
> `{1..12}`. Le symptôme classique est un fichier littéralement nommé `sauvegarde-{1..12}.tar`.

---

<a id="q1-2"></a>**[Q1.2](README.md#q1-2)** — *`f="rapport final.log"` puis `rm $f` dans un répertoire ne contenant que ce fichier.*

**Réponse : b)** `rm` échoue deux fois :

```text
rm: cannot remove 'rapport': No such file or directory
rm: cannot remove 'final.log': No such file or directory
```

> [!NOTE]
> **Pourquoi**
>
> La variable est correctement affectée : `f` contient bien `rapport final.log` en un
> seul morceau, parce que les guillemets protègent l'espace au moment de
> l'affectation. Le problème survient à l'**usage**. `$f` non quoté subit l'étape 4
> du traitement, le **découpage des mots** : bash coupe le résultat de l'expansion sur
> les caractères de `$IFS` (espace, tabulation, saut de ligne par défaut) et produit
> deux arguments distincts. `rm` reçoit donc `argv = [rm, rapport, final.log]` et
> cherche deux fichiers qui n'existent pas.
>
> `rm "$f"` supprime le fichier : les guillemets suppriment l'étape 4 pour ce mot.
> Le découpage ne s'applique **qu'aux résultats d'expansion non quotés**, jamais au
> texte littéral que tu as tapé.

> [!WARNING]
> **Piège**
>
> Le corollaire utile : les noms produits par le **globbing** ne sont jamais découpés,
> parce que le globbing (étape 5) a lieu *après* le découpage (étape 4). C'est pourquoi
> `wc -l *.log` fonctionne parfaitement avec des espaces dans les noms, alors que
> `wc -l $(ls *.log)` casse.

---

<a id="q1-3"></a>**[Q1.3](README.md#q1-3)** — *Avec `alias ll='ls -alF'`, quelles affirmations sont vraies ? (deux réponses)*

**Réponses : b) et c)**

```console
$ type ll
ll is aliased to `ls -alF'
$ command -v ll
alias ll='ls -alF'
$ which ll
$ echo $?
1
```

> [!NOTE]
> **Pourquoi**
>
> `which` est un **programme externe** (`/usr/bin/which`, paquet `debianutils` sur
> Ubuntu). Un programme externe s'exécute dans un processus fils : il n'a aucun accès
> aux alias, fonctions et builtins du shell parent, qui ne sont que des structures de
> données internes à bash et ne sont pas transmises dans l'environnement. Tout ce que
> `which` sait faire, c'est parcourir les répertoires de `PATH`.
>
> `type` et `command -v` sont des **builtins** : ils interrogent les tables internes
> du shell dans l'ordre exact de résolution des commandes, à savoir alias, puis mot
> réservé, puis fonction, puis builtin, puis fichier du `PATH`. Ils te disent donc ce
> qui va *réellement* s'exécuter.
>
> En script, préfère `command -v` : il est POSIX, sa sortie est simple à tester, et
> il renvoie 1 quand la commande n'existe pas. `type -a` est l'outil de diagnostic
> interactif, parce qu'il montre **toutes** les résolutions possibles, y compris les
> doublons dans `PATH`.

---

<a id="q1-4"></a>**[Q1.4](README.md#q1-4)** — *`./deploy.sh 2>&1 > deploy.log` : pourquoi les erreurs ne sont pas dans le fichier ?*

**Réponse : b)** stdout va dans `deploy.log`, stderr reste sur le terminal.

> [!NOTE]
> **Pourquoi**
>
> Le shell traite les redirections **de gauche à droite**, et `2>&1` ne veut pas dire
> « fusionne les deux flux » mais « fais pointer le descripteur 2 vers la destination
> **actuelle** du descripteur 1 ». C'est une copie de destination, pas un lien.
>
> État des descripteurs, pas à pas :
>
> ```text
> au départ        fd1 -> /dev/pts/0      fd2 -> /dev/pts/0
> après 2>&1       fd1 -> /dev/pts/0      fd2 -> /dev/pts/0   (copie, sans effet)
> après > log      fd1 -> deploy.log      fd2 -> /dev/pts/0
> ```
>
> Le fd 2 a été dupliqué **avant** que le fd 1 ne change de cible : il reste donc sur
> le terminal. L'écriture correcte est `./deploy.sh > deploy.log 2>&1`, ou le
> raccourci bash `./deploy.sh &> deploy.log`.

> [!WARNING]
> **Piège**
>
> La forme `2>&1 > fichier` n'est pas une erreur : elle a un usage légitime, séparer
> les deux flux quand on veut envoyer stdout dans un fichier et stderr dans un pipe.
> `cmd 2>&1 > fichier | traitement` fait exactement ça. Ne la corrige donc pas
> mécaniquement dans le code des autres avant d'avoir compris l'intention.

---

<a id="q1-5"></a>**[Q1.5](README.md#q1-5)** — *`ssh mathieu@10.10.10.11 'echo $PATH'` : quel fichier influence le résultat ?*

**Réponse : b)** `~/.bashrc`, mais il s'arrête à la garde d'interactivité.

> [!NOTE]
> **Pourquoi**
>
> Trois mécanismes se superposent, et c'est ce qui rend la question discriminante en
> entretien.
>
> 1. `ssh hôte 'commande'` ne demande pas de TTY : le shell distant est **non
>    interactif** et **non login**. Il ne lit donc ni `/etc/profile`, ni
>    `~/.bash_profile`, ni `~/.profile`.
> 2. Bash a néanmoins un comportement historique particulier : quand il détecte qu'il
>    est lancé par un démon distant (stdin branché sur une socket réseau, `SSH_CLIENT`
>    présent), il lit `~/.bashrc` même non interactif. C'est documenté dans
>    `man bash`, section INVOCATION.
> 3. Mais le `~/.bashrc` livré par Ubuntu commence par :
>
> ```bash
> case $- in
>     *i*) ;;
>       *) return;;
> esac
> ```
>
> `$-` contient les options actives du shell ; le `i` n'y est que si le shell est
> interactif. Un shell non interactif exécute donc `return` à la troisième ligne.
>
> Conclusion pratique : `~/.bashrc` **est** lu, mais tout ce que tu as écrit après la
> garde est ignoré. Si tu veux qu'une variable soit vue par `ssh hôte 'commande'`,
> place-la **au-dessus** de la garde — ou, mieux, dans `/etc/environment`, qui est
> injecté par PAM pour toutes les sessions.

---

<a id="q1-6"></a>**[Q1.6](README.md#q1-6)** — *Dans des guillemets simples, quels caractères restent spéciaux ?*

**Réponse : d) aucun**

> [!NOTE]
> **Pourquoi**
>
> Le guillemet simple est le quoting le plus fort de bash : entre deux `'`, chaque
> caractère est littéral, y compris `$`, `` ` ``, `\`, `!`, `*` et le saut de ligne.
> La seule chose impossible dans une chaîne en guillemets simples est… un guillemet
> simple : il n'existe aucune séquence d'échappement. On ferme, on échappe, on rouvre :
> `'aujourd'\''hui'`.
>
> Les guillemets doubles sont plus faibles : ils suppriment le découpage des mots et
> le globbing, mais laissent vivre l'expansion des paramètres (`$var`), la substitution
> de commande (`$(...)` et les backquotes), l'arithmétique et le backslash devant
> `$`, `` ` ``, `"`, `\` ou un saut de ligne.

> [!WARNING]
> **Piège**
>
> Conséquence directe : `awk '{print $1}'` doit être en guillemets simples, sinon bash
> remplace `$1` par le premier argument positionnel du script (vide, en général) et
> `awk` reçoit `{print }`. Même logique pour les expressions `grep` avec `$` final et
> pour les mots de passe contenant `$`.

---

<a id="q1-7"></a>**[Q1.7](README.md#q1-7)** — *Éviter qu'une commande contenant un mot de passe entre dans l'historique.*

**Réponse : b)** `HISTCONTROL=ignorespace` puis préfixer la commande d'une espace.

> [!NOTE]
> **Pourquoi**
>
> `HISTCONTROL` accepte des valeurs combinables par `:` :
>
> * `ignorespace` : une ligne commençant par une ou plusieurs espaces n'est pas
>   enregistrée ;
> * `ignoredups` : une ligne identique à la précédente n'est pas enregistrée ;
> * `ignoreboth` : les deux (c'est la valeur du `~/.bashrc` par défaut d'Ubuntu); `erasedups` : efface de l'historique toutes les occurrences antérieures.
>
> C'est le seul mécanisme **sélectif** : tu gardes un historique complet et utile, et
> tu exclus ponctuellement une ligne. `HISTSIZE=0` vide l'historique en mémoire de la
> session en cours, et `unset HISTFILE` fait perdre toute la session à la
> déconnexion : deux façons de perdre de l'information dont tu auras besoin pendant
> un incident.
>
> Vérifie que c'est actif avant d'y compter : `echo "$HISTCONTROL"` doit contenir
> `ignorespace` ou `ignoreboth`. Sur une machine où ce n'est pas configuré, l'espace
> initial ne protège rien.

> [!WARNING]
> **Piège**
>
> L'historique bash n'est pas un secret gardé : le mot de passe reste visible dans
> `/proc/<pid>/cmdline` pendant l'exécution, donc dans `ps aux` pour tout le monde.
> La vraie réponse d'exploitation est de ne jamais passer un secret en argument :
> variable d'environnement, fichier en `0600`, ou lecture sur stdin.

---

<a id="q1-8"></a>**[Q1.8](README.md#q1-8)** — *`ls *.gz` dans un répertoire sans fichier `.gz`.*

**Réponse : b)** `ls: cannot access '*.gz': No such file or directory`

> [!NOTE]
> **Pourquoi**
>
> Par défaut, quand un motif de globbing ne correspond à **aucun** fichier, bash
> laisse le motif tel quel et le passe littéralement à la commande. C'est `ls` qui
> échoue ensuite, en cherchant un fichier nommé littéralement `*.gz`. Le message
> d'erreur vient donc de `ls`, pas du shell, et le code retour est celui de `ls` (2).
>
> Deux options de shell changent ce comportement :
>
> * `shopt -s nullglob` : un motif sans correspondance devient une **chaîne vide**,
>   donc `ls *.gz` devient `ls` tout court, ce qui liste le répertoire courant.
>   Piège différent, pas forcément meilleur.
> * `shopt -s failglob` : bash refuse d'exécuter la commande et affiche l'erreur
>   lui-même. C'est le plus sûr en script interactif, mais ça surprend.
>
> En script, le réflexe est de tester avant : `[ -e "$f" ] || continue` en tête de
> boucle, pour ne pas traiter le motif non développé comme un nom de fichier.

---

<a id="q1-9"></a>**[Q1.9](README.md#q1-9)** — *`mois=$(date +%m)` le 18 septembre, puis `echo $(( mois + 1 ))`.*

**Réponse : b)** `bash: 09: value too great for base (error token is "09")`

> [!NOTE]
> **Pourquoi**
>
> `date +%m` renvoie le mois sur deux chiffres avec un zéro de tête : `09`.
> Dans un contexte arithmétique `$(( ))`, bash applique les conventions de notation
> du langage C : un nombre commençant par `0` est interprété en **octal**. Or en
> octal, les chiffres valides vont de 0 à 7 : `08` et `09` sont des littéraux
> invalides, d'où l'erreur. Le bug ne se manifeste donc que deux mois par an, en août
> et en septembre — et les huitième et neuvième jours du mois pour `date +%d`, et pour `date +%j` chaque jour de 001 à 099 qui contient un 8 ou un 9 (`008`, `009`, `018`, `019`… puis tout de `080` à `099`). C'est un classique des scripts de
> rotation de logs qui tombent en panne « sans raison » chaque mois d'août.
>
> La correction est le préfixe de base explicite de bash :
>
> ```bash
> mois=$(date +%m)
> echo $(( 10#$mois + 1 ))
> ```
>
> `10#` force la base 10 quel que soit le zéro de tête. Alternative : demander à
> `date` de ne pas remplir, avec `date +%-m` (extension GNU).

> [!WARNING]
> **Piège**
>
> Le même piège existe en dehors de `$(( ))` dès qu'un outil interprète l'octal, et
> il ne provoque pas toujours une erreur : `printf '%d' 010` affiche `8` sans rien
> signaler. Une erreur bruyante vaut mieux qu'un résultat faux silencieux.

---

<a id="q1-10"></a>**[Q1.10](README.md#q1-10)** — *Ajouter `~/bin` au `PATH` depuis `~/.bashrc` (deux réponses).*

**Réponses : b) et d)**

> [!NOTE]
> **Pourquoi**
>
> b) `export PATH="$HOME/bin:$PATH"` est la forme canonique : `$HOME` est développé
> correctement, l'ancien `PATH` est conservé, et l'ajout se fait en tête, donc tes
> scripts prennent le pas sur ceux du système.
>
> c) `PATH="$HOME/bin:$PATH"` sans `export` fonctionne **aussi**, et c'est la subtilité
> de la question : l'attribut d'export d'une variable est une propriété persistante de
> la variable, pas de l'affectation. `PATH` est déjà exporté par le processus parent
> (sshd, login) ; une réaffectation conserve cet attribut. Vérifie-le avec
> `declare -p PATH`, qui affiche `declare -x PATH=...` : le `-x` est l'attribut
> d'export. Écrire `export` reste une bonne pratique, parce que ça documente
> l'intention et parce que ça protège le jour où la variable n'était pas déjà exportée.
>
> d) `PATH=~/bin` écrase tout le `PATH` : c'est exactement la panne du Break & Fix BF1.1.
> Le tilde est bien développé ici (l'expansion du tilde a lieu après `=` dans une
> affectation), mais il ne reste plus que `~/bin` dans le chemin de recherche.
>
> e) `export PATH="$PATH:."` ajoute le répertoire courant. C'est une faille : il suffit
> qu'un utilisateur dépose un fichier exécutable nommé `ls` ou `sudo` dans un
> répertoire où tu passes (`/tmp`, un dépôt Git cloné) pour qu'il s'exécute à ta place,
> avec tes droits.

---

<a id="q1-11"></a>**[Q1.11](README.md#q1-11)** — *Documentation du format de `/etc/fstab`.*

**Réponse : b) `man 5 fstab`**

> [!NOTE]
> **Pourquoi**
>
> Les pages de manuel sont réparties en sections numérotées, et le même nom peut
> exister dans plusieurs :
>
> | Section | Contenu |
> |---|---|
> | 1 | commandes utilisateur (`ls`, `crontab`) |
> | 5 | **formats de fichiers** (`fstab`, `crontab`, `passwd`, `sshd_config`) |
> | 8 | commandes d'administration (`mount`, `sshd`, `useradd`) |
>
> Sans numéro, `man fstab` affiche la première section trouvée dans l'ordre configuré,
> ce qui donne ici la bonne page par chance, mais pas pour `crontab` ni `passwd` :
> `man passwd` donne la commande de changement de mot de passe, `man 5 passwd` donne
> le format du fichier. Le réflexe professionnel est de nommer la section.
>
> `man -k fstab` (= `apropos`) ne donne pas la page, il **liste** les pages dont la
> description contient le mot, avec leur section : c'est l'outil pour trouver le bon
> numéro quand on ne le connaît pas. `whatis fstab` donne la ligne de résumé de
> chaque section existante.

---

<a id="q1-12"></a>**[Q1.12](README.md#q1-12)** — *Script `#!/bin/sh` avec `[[ ]]` et `source`, qui échoue sur Ubuntu.*

**Réponse : a)** sur Ubuntu, `/bin/sh` est un lien symbolique vers `dash`.

```console
$ ls -l /bin/sh
lrwxrwxrwx 1 root root 4 Mar 31  2024 /bin/sh -> dash
```

> [!NOTE]
> **Pourquoi**
>
> Ubuntu utilise `dash` comme `/bin/sh` depuis 2006, Debian depuis 2011, pour une raison de
> performance : `dash` démarre environ cinq fois plus vite que bash, ce qui compte sur
> les milliers d'appels des scripts d'init et de `postinst`. `dash` implémente le
> standard POSIX et rien de plus. Sur macOS et sur RHEL/Rocky, `/bin/sh` est bash
> (en mode POSIX sur RHEL), ce qui masque le problème côté développeur : le script
> « marche sur ma machine » parce que bash en mode `sh` tolère encore ses propres
> extensions de syntaxe.
>
> Ce qui casse ici :
>
> * `[[ ... ]]` est un mot réservé de bash/ksh/zsh, absent de POSIX. Message :
>   `[[: not found`. L'équivalent POSIX est `[ ... ]`, avec les guillemets obligatoires.
> * `source` est un synonyme bash de `.`. Message : `source: not found`. L'équivalent
>   POSIX est `. /opt/app/lib.sh`.
>
> Autres absences fréquentes de `dash` : les tableaux `arr=(a b c)`, `${var//a/b}`,
> `local` (présent en pratique mais non POSIX), `echo -e`, `+=`, `$'...'`,
> `function nom()`, `<<<` (here-string), `((...))`, `&>`, `PIPESTATUS`.

> [!WARNING]
> **Piège**
>
> La règle d'exploitation est simple : le shebang est un **contrat**. Si le script
> utilise des extensions bash, le shebang doit être `#!/usr/bin/env bash`. Mettre
> `#!/bin/sh` « parce que c'est plus portable » sur un script qui ne l'est pas ne rend
> rien portable, ça déplace juste la panne sur la machine de production.

---

<a id="q1-13"></a>**[Q1.13](README.md#q1-13)** — *Un script contenant `alias ll='ls -l'` puis `ll`, exécuté par `bash maj.sh`.*

**Réponse : b)** `ll: command not found` — les alias ne sont pas développés dans un
shell non interactif.

> [!NOTE]
> **Pourquoi**
>
> L'option de shell `expand_aliases` est **activée par défaut en interactif,
> désactivée en non interactif**. La définition de l'alias est acceptée sans erreur,
> elle entre bien dans la table des alias, mais la ligne suivante n'est jamais
> substituée.
>
> Il y a une deuxième raison, plus subtile, qui frappe même si tu actives
> `shopt -s expand_aliases` : les alias sont développés à la **lecture** de la ligne,
> pas à son exécution. Bash lit le fichier par blocs ; un alias défini et utilisé dans
> le même bloc de lecture (par exemple à l'intérieur d'une même fonction, d'un même
> `{ ... }` ou d'une même boucle) ne sera pas développé, parce que la ligne d'usage a
> déjà été analysée quand la définition s'exécute.
>
> D'où la règle : **en script, on n'utilise pas d'alias, on utilise des fonctions.**
> Une fonction est résolue à l'exécution, accepte des arguments, gère un code retour,
> et fonctionne aussi bien en interactif qu'en non interactif.
>
> ```bash
> ll() { ls -l "$@"; }
> ```

---

<a id="q1-14"></a>**[Q1.14](README.md#q1-14)** — *`./maj.sh | tee -a ~/lab01/logs/maj.log` : que manque-t-il pour capter stderr ?*

**Réponse : b) `./maj.sh 2>&1 | tee -a ~/lab01/logs/maj.log`**

> [!NOTE]
> **Pourquoi**
>
> Un tube (`|`) ne connecte que le **descripteur 1** de la commande de gauche au
> descripteur 0 de celle de droite. Le descripteur 2 continue d'aller sur le terminal :
> tu vois les erreurs à l'écran, mais elles n'entrent jamais dans `tee`, donc jamais
> dans le fichier. Il faut donc rediriger le fd 2 vers le fd 1 **avant** le tube, ce
> que fait `2>&1` placé à gauche du `|`.
>
> Bash propose le raccourci `|&`, strictement équivalent à `2>&1 |` :
> `./maj.sh |& tee -a maj.log`. Il n'est pas POSIX.
>
> La réponse d) `| tee -a ... 2>&1` redirige la sortie d'erreur de **`tee`** vers la
> sortie standard de `tee`, ce qui n'a aucun rapport avec les erreurs de `maj.sh`.
> La réponse c) n'est pas une syntaxe valide : `&>` attend un nom de fichier, pas une
> commande.

> [!WARNING]
> **Piège**
>
> Avec un tube, `$?` est le code de la **dernière** commande, donc celui de `tee`,
> qui réussit presque toujours. Un script qui teste `if ./maj.sh 2>&1 | tee log; then`
> croira toujours que la mise à jour a réussi. Récupère le vrai code avec
> `${PIPESTATUS[0]}` (bash) ou active `set -o pipefail`.

---

<a id="q1-15"></a>**[Q1.15](README.md#q1-15)** — *Deux sessions, `histappend` désactivé, fermées l'une après l'autre.*

**Réponse : b)** seul l'historique de la dernière session fermée subsiste.

> [!NOTE]
> **Pourquoi**
>
> Sans `histappend`, bash **écrit** (`>`) l'historique en mémoire dans `~/.bash_history`
> à la sortie, ce qui tronque le fichier puis le remplit. Chaque session a chargé le
> fichier à son ouverture et y a ajouté ses propres commandes en mémoire ; la première
> session fermée écrit son contenu, la seconde écrase avec le sien — qui ne contient
> pas les commandes de la première, puisqu'elle ne les a jamais vues.
>
> Avec `shopt -s histappend`, bash **ajoute** (`»`) au fichier au lieu de l'écraser :
> les deux sessions coexistent, dans l'ordre de fermeture.
>
> Pour aller plus loin, le réglage classique des postes d'admin partagés écrit
> l'historique après **chaque** commande plutôt qu'à la sortie :
>
> ```bash
> shopt -s histappend
> PROMPT_COMMAND="history -a; ${PROMPT_COMMAND:-}"
> ```
>
> `history -a` ajoute au fichier les lignes de la session non encore écrites. C'est ce
> qui sauve l'historique quand une session SSH tombe brutalement : sans ça, une
> coupure réseau fait perdre toute la session de diagnostic.

---

<a id="q1-16"></a>**[Q1.16](README.md#q1-16)** — *Revenir de `/etc/nginx` à `/var/log` (deux réponses).*

**Réponses : a) `cd -` et c) `cd "$OLDPWD"`**

> [!NOTE]
> **Pourquoi**
>
> À chaque `cd` réussi, bash place l'ancien répertoire dans la variable `OLDPWD` et le
> nouveau dans `PWD`. `cd -` est exactement un raccourci pour `cd "$OLDPWD"`, avec une
> différence de forme : `cd -` affiche le répertoire d'arrivée sur stdout, ce qui peut
> polluer un script.
>
> Il existe une troisième écriture valable, qui vient de l'expansion du tilde :
> `cd ~-` est développé en `$OLDPWD`. De même, `~+` vaut `$PWD`. Ces formes sont utiles
> au milieu d'un chemin : `cp fichier ~-/sauvegarde/`.
>
> b) `cd ..` remonte au parent, ici `/etc`, pas au précédent.
> c) `cd ~` ramène à `$HOME`, comme `cd` sans argument.
>
> Pour naviguer entre plus de deux répertoires, `cd -` ne suffit plus : il alterne
> entre deux valeurs. C'est le rôle de la pile `pushd` / `popd` / `dirs -v`.

---

<a id="q1-17"></a>**[Q1.17](README.md#q1-17)** — *`for f in $(ls /var/log)` contre `for f in /var/log/*`.*

**Réponse : c)** seule la forme B est correcte.

> [!NOTE]
> **Pourquoi**
>
> La forme A enchaîne deux mécanismes destructeurs. D'abord, `$(ls)` produit une seule
> chaîne contenant tous les noms séparés par des sauts de ligne ; comme elle n'est pas
> quotée, elle subit le **découpage des mots** sur `$IFS`, qui contient l'espace : le
> fichier `rapport final.log` devient deux itérations. Ensuite, chacun des morceaux
> obtenus subit le **globbing** : un fichier réellement nommé `donnees?.csv` ou
> `[old]notes.txt` serait remplacé par les fichiers qui correspondent au motif, ou
> laissé tel quel s'il n'y a pas de correspondance.
>
> La forme B fait faire le travail au shell lui-même : le globbing (étape 5) a lieu
> **après** le découpage des mots (étape 4), donc les noms produits par `/var/log/*`
> ne sont jamais re-découpés, quels que soient les espaces qu'ils contiennent.
> En prime, `f` contient un chemin complet, utilisable directement.
>
> Deux précautions à garder dans la forme B :
>
> ```bash
> for f in /var/log/*; do
>   [ -e "$f" ] || continue     # cas du répertoire vide : le motif est littéral
>   wc -l -- "$f"               # -- protège des noms commençant par un tiret
> done
> ```

> [!WARNING]
> **Piège**
>
> « Ne parse jamais la sortie de `ls` » est un principe, pas une coquetterie : `ls`
> formate pour l'humain (colonnes, couleurs, troncatures, caractères non imprimables
> remplacés par `?`). Pour des critères que le globbing ne couvre pas (âge, taille,
> récursivité), l'outil est `find -print0` couplé à `xargs -0` ou `-exec`.

---

## 1.4 Quiz — questions ouvertes

<a id="qo1-1"></a>**[QO1.1](README.md#qo1-1)** — *Détailler l'ordre des expansions de `echo ~/lab01/logs/*.log "$(date +%F)" $((7 * 24))`.*

Déroulé attendu :

1. **Accolades** : aucune dans la ligne, rien à faire. (L'étape a quand même lieu.)
2. **Tilde** : `~/lab01/logs/*.log` devient `/home/mathieu/lab01/logs/*.log`.
   Le tilde n'est développé qu'en **début de mot** et non quoté.
3. **Paramètres, arithmétique, substitution de commande**, de gauche à droite :
   `"$(date +%F)"` devient `2026-09-18`, `$((7 * 24))` devient `168`.
4. **Découpage des mots** : `2026-09-18` est protégé par des guillemets, donc épargné.
   `168` n'est pas quoté mais ne contient aucun caractère d'`IFS`, donc reste un mot.
5. **Globbing** : `/home/mathieu/lab01/logs/*.log` est remplacé par la liste triée
   des fichiers correspondants, chacun formant un argument distinct même s'il
   contient des espaces.
6. **Suppression des quotes** : les `"` autour de la date sont retirés ; `echo` ne les
   voit jamais.

Pourquoi l'ordre « paramètres avant globbing » est indispensable :

```bash
rep=/home/mathieu/lab01/logs
ls "$rep"/*.log
```

Le motif à développer n'est connu qu'après le remplacement de `$rep`. Si le globbing
avait lieu avant, bash chercherait un fichier littéralement nommé `$rep/*.log`, qui
n'existe pas, et passerait la chaîne telle quelle à `ls`. Toute construction de
chemin dynamique serait impossible.

> [!NOTE]
> **Pourquoi**
>
> La vraie leçon est qu'il y a **une seule passe**. Le résultat d'une expansion n'est
> jamais réexaminé par les étapes précédentes : c'est pourquoi un nom de fichier
> contenant `*` ne provoque pas de second globbing (heureusement), et pourquoi
> `n=5; echo {1..$n}` échoue (Q1.1). Le seul moyen de forcer une seconde passe est
> `eval`, et c'est précisément pour ça qu'`eval` est dangereux sur des données non
> maîtrisées : tout ce qui vient d'un fichier, d'une API ou d'un nom de fichier se
> retrouve réinterprété comme du code.

---

<a id="qo1-2"></a>**[QO1.2](README.md#qo1-2)** — *`~/.bashrc` contre `~/.bash_profile` ; où poser `export JAVA_HOME` ?*

Réponse attendue :

`~/.bash_profile` est lu par les shells de **login** (SSH avec TTY, `su -`, console,
`login`), une seule fois au début de la session. C'est l'endroit des réglages qui
décrivent la **session** : variables d'environnement, `PATH`, `umask`, agent SSH.

`~/.bashrc` est lu par les shells **interactifs non-login** : chaque nouveau
terminal, chaque `bash` tapé dans un shell existant, chaque panneau de `tmux`. C'est
l'endroit des réglages qui décrivent l'**interaction** : prompt, alias, fonctions,
complétion, options d'historique.

Sur Ubuntu, il n'y a pas de `~/.bash_profile` par défaut ; c'est `~/.profile` qui
joue ce rôle, et il contient un `. "$HOME/.bashrc"`. C'est ce pont qui fait que les
alias apparaissent aussi en session de login.

Les trois cas demandés :

| Situation | Ce qui est lu | Où poser `JAVA_HOME` |
|---|---|---|
| SSH interactif | `/etc/profile`, `~/.profile` → `~/.bashrc` | n'importe lequel des trois |
| `ssh lab-web 'cmd'` | `~/.bashrc`, coupé à la garde `case $-` | au-dessus de la garde |
| cron | aucun fichier bash | `/etc/environment` ou le `crontab` |

Réponse d'entretien en une phrase : **`/etc/environment`**, parce qu'il est lu par
PAM (`pam_env`) à l'ouverture de toute session — SSH, `su`, et cron sur Debian/Ubuntu
dont `/etc/pam.d/cron` charge `pam_env` — et qu'il ne dépend donc d'aucun shell.
Sa syntaxe est `CLÉ=valeur`, sans `export`, sans expansion de variable.

> [!NOTE]
> **Pourquoi**
>
> Le raisonnement à montrer en entretien n'est pas « je connais la liste des fichiers »
> mais « je sais d'où vient l'environnement ». Un processus hérite son environnement de
> son père. Les fichiers de démarrage de bash ne sont qu'**un** des endroits où cet
> environnement est construit ; les autres sont PAM (`/etc/environment`,
> `/etc/security/pam_env.conf`), systemd (`Environment=` et `EnvironmentFile=` dans
> l'unité, `systemctl set-environment`), le `crontab` lui-même, et le Dockerfile pour
> un conteneur. Un service systemd ne lira jamais ton `~/.bashrc`, quoi que tu y mettes.

> [!WARNING]
> **Piège**
>
> `~/.pam_environment` était la réponse habituelle pour les variables par utilisateur.
> Il est **déprécié depuis Ubuntu 22.04 et supprimé du chemin par défaut** ; ne le
> propose plus. Pour un besoin par utilisateur qui doit survivre à cron, la solution
> est de définir la variable dans le `crontab` de l'utilisateur, en haut du fichier.

---

<a id="qo1-3"></a>**[QO1.3](README.md#qo1-3)** — *`which python3` donne `/usr/bin/python3` mais un autre binaire démarre.*

Trois causes, et la commande qui tranche pour chacune :

1. **Un alias ou une fonction masque la commande.** `which` ne les voit pas.
   Commande qui tranche : `type -a python3`. Si la première ligne dit `aliased to`
   ou `is a function`, c'est réglé. Contournement immédiat : `command python3` ou
   `\python3` (le backslash inhibe l'expansion d'alias).
2. **Un autre `python3` est plus tôt dans le `PATH`** que celui vu par `which` —
   typiquement parce que `which` a été lancé dans un contexte où `PATH` différait
   (script, `sudo` avec `secure_path`, `env -i`). Commande qui tranche :
   `type -a python3` là encore, qui liste **tous** les chemins correspondants dans
   l'ordre, ou `echo "$PATH" | tr : '\n'` pour lire l'ordre.
3. **Le cache de hachage de bash est périmé.** Bash mémorise le chemin complet de
   chaque commande déjà exécutée ; si le binaire a été déplacé ou si un nouveau est
   apparu plus tôt dans le `PATH`, bash continue d'appeler l'ancien. Commande qui
   tranche : `hash -t python3` affiche le chemin mémorisé ; `hash -r` vide le cache.

Bonus souvent attendu : un environnement virtuel Python ou `pyenv` actif, qui a
inséré un répertoire de shims en tête de `PATH` et défini `VIRTUAL_ENV`.
Commande qui tranche : `echo "$VIRTUAL_ENV"` et `readlink -f "$(command -v python3)"`.

> [!NOTE]
> **Pourquoi**
>
> L'ordre de résolution d'une commande par bash est fixe, et le connaître répond à la
> question en une seule étape :
>
> ```text
> alias -> mot réservé -> fonction -> builtin -> table de hachage -> PATH
> ```
>
> `type -a` parcourt cette chaîne et affiche tout ce qu'il trouve, dans l'ordre.
> C'est pour ça qu'il est l'outil de diagnostic, alors que `command -v` (qui ne montre
> que le vainqueur) est l'outil de script.

---

<a id="qo1-4"></a>**[QO1.4](README.md#qo1-4)** — *`cmd > f 2>&1` contre `cmd 2>&1 > f`.*

Les redirections sont appliquées de gauche à droite, chacune agissant sur l'état
courant de la table des descripteurs.

```text
cmd > f 2>&1
  initial :  fd1 -> tty        fd2 -> tty
  > f     :  fd1 -> f          fd2 -> tty
  2>&1    :  fd1 -> f          fd2 -> f        (dup de la cible actuelle de fd1)
  résultat : tout dans f

cmd 2>&1 > f
  initial :  fd1 -> tty        fd2 -> tty
  2>&1    :  fd1 -> tty        fd2 -> tty      (dup sans effet visible)
  > f     :  fd1 -> f          fd2 -> tty
  résultat : stdout dans f, stderr sur le terminal
```

> [!NOTE]
> **Pourquoi**
>
> Au niveau système, `2>&1` correspond à l'appel `dup2(1, 2)` : le noyau fait pointer
> l'entrée 2 de la table des descripteurs du processus vers la **même description de
> fichier ouvert** que l'entrée 1 à cet instant. C'est une copie de pointeur, pas un
> lien symbolique : si l'entrée 1 change ensuite de cible, l'entrée 2 ne suit pas.
>
> Corollaire utile : comme les deux descripteurs partagent alors la même description
> ouverte, ils partagent aussi l'**offset d'écriture**. C'est pourquoi
> `cmd > f 2>&1` produit un fichier cohérent, alors que `cmd > f 2> f` — deux
> ouvertures indépendantes du même fichier, deux offsets — fait que les deux flux
> s'écrasent mutuellement.

---

<a id="qo1-5"></a>**[QO1.5](README.md#qo1-5)** — *Script qui marche à la main mais échoue en cron avec `command not found`.*

Démarche attendue, dans l'ordre :

1. **Lire le message exact et le journal.** `journalctl -u cron -n 50` ou le mail
   local de cron. Le message `ll: command not found` et `docker: command not found`
   ne sont pas la même panne : le premier est un alias, le second un `PATH`.
2. **Reproduire l'environnement de cron**, sans attendre la prochaine occurrence :

```bash
env -i /bin/bash --noprofile --norc /chemin/du/script.sh
```

   Si ça échoue de la même façon, c'est confirmé : c'est l'environnement, pas le code.
3. **Comparer les deux environnements.** Ajouter temporairement en tête du script
   `env > /tmp/env-cron.txt`, puis `diff <(env | sort) <(sort /tmp/env-cron.txt)`.
   On voit immédiatement que cron fournit un `PATH` minimal
   (`/usr/bin:/bin` sur Debian/Ubuntu) et pas grand-chose d'autre.
4. **Corriger les deux causes séparément.** \*
   * `ll` : c'est un alias de `~/.bashrc`, jamais lu par cron, et de toute façon les
     alias ne sont pas développés en non interactif. On le remplace par la vraie
     commande `ls -l`, ou par une fonction définie dans le script. \*
   * `docker` : il est dans `/usr/bin/docker`, donc en principe trouvable, mais si le
     binaire est ailleurs (`/usr/local/bin`), on déclare le `PATH` **en tête du
     script** — pas dans le `crontab`, pour que le script reste autonome :
     `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`
     ou, plus radical, on appelle les binaires par chemin absolu.
5. **Vérifier le shell.** Le `crontab` utilise `/bin/sh` par défaut : si le script
   est appelé via `SHELL=/bin/sh`, il faut soit un shebang bash explicite sur le
   script, soit `SHELL=/bin/bash` en tête du `crontab`.

> [!NOTE]
> **Pourquoi**
>
> La cause racine unique derrière les deux symptômes : **cron ne lance ni un shell de
> login, ni un shell interactif**. Il n'y a donc ni `/etc/profile`, ni `~/.profile`,
> ni `~/.bashrc` (ou plutôt : `~/.bashrc` n'est même pas tenté), ni `expand_aliases`.
> Un script d'exploitation doit être écrit pour ne rien supposer de son environnement :
> shebang explicite, `PATH` déclaré ou chemins absolus, aucune dépendance aux alias,
> `cd` explicite plutôt que de compter sur le répertoire courant.

> [!WARNING]
> **Piège**
>
> Le second effet classique du `PATH` minimal de cron n'est pas un `command not found`
> mais une **mauvaise version** exécutée silencieusement : si tu as `/usr/local/bin/terraform`
> en 1.9 et `/usr/bin/terraform` en 1.5, ton shell prend la 1.9 et cron la 1.5. Aucun
> message d'erreur, juste un comportement différent en production.

---

<a id="qo1-6"></a>**[QO1.6](README.md#qo1-6)** — *Pourquoi `rm -rf $CIBLE/*` est une bombe.*

Trois façons distinctes dont cette ligne détruit la machine :

1. **`CIBLE` vide ou non définie** : la ligne devient `rm -rf /*`. Avec `set -u`
   activé le script s'arrêterait, mais `set -u` n'est presque jamais actif dans les
   scripts d'exploitation hérités.
2. **`CIBLE` contient un espace** : `CIBLE="/srv/mon app"` donne
   `rm -rf /srv/mon app/*`, qui supprime `/srv/mon` (s'il existe) et échoue
   bruyamment sur le reste — ou pire, réussit à moitié.
3. **`CIBLE` contient un glob ou commence par un tiret** : `rm` interprète.

Écriture blindée :

```bash
: "${CIBLE:?CIBLE non définie}"      # 1. abandonne si vide ou absente
case "$CIBLE" in
  /|/usr|/etc|/var|/home) echo "refus: $CIBLE" >&2; exit 1 ;;   # 2. liste noire
esac
[ -d "$CIBLE" ] || { echo "pas un répertoire" >&2; exit 1; }    # 3. contrôle
rm -rf -- "$CIBLE"/*                                     # 4. quoting + --
```

Ce que chaque protection empêche :

* `${CIBLE:?message}` : le cas variable vide ou non définie. Le shell affiche le
  message et sort immédiatement, avant toute suppression.
* la liste noire : le cas où la variable est correctement remplie mais avec une
  valeur catastrophique (erreur de configuration, pas erreur de syntaxe).
* `[ -d ... ]` : le cas où la cible est un fichier, un lien mort, ou n'existe pas.
* les guillemets autour de `"$CIBLE"` : le découpage des mots sur les espaces.
* le `--` : le cas d'une valeur commençant par un tiret, interprétée comme option.

> [!NOTE]
> **Pourquoi**
>
> `${VAR:?message}` est la construction la plus sous-utilisée de bash pour ce cas
> précis. Elle échoue **à l'expansion**, c'est-à-dire avant que `rm` ne soit même
> lancé, et elle fonctionne dans tous les shells POSIX, y compris `dash`. La variante
> `${VAR?message}` ne teste que l'absence, `${VAR:?message}` teste aussi la chaîne
> vide — c'est cette dernière qu'on veut presque toujours.

> [!WARNING]
> **Piège**
>
> `rm -rf "$CIBLE/"` avec le slash final ne protège de rien si `CIBLE` est vide : la
> ligne devient `rm -rf /`. Les versions modernes de GNU coreutils refusent
> explicitement `rm -rf /` (protection `--preserve-root`, active par défaut), mais
> elles ne refusent **pas** `rm -rf /*`, qui est développé par le shell en une liste
> de chemins d'un niveau plus bas. La protection de `rm` ne te sauve donc pas ici.

---

<a id="qo1-7"></a>**[QO1.7](README.md#qo1-7)** — *Quatre constructions bash absentes de `dash`, et comment vérifier avant la prod.*

Constructions bash non POSIX (quatre suffisaient, en voici les plus courantes) :

| Construction bash | Équivalent POSIX |
|---|---|
| `[[ -n "$x" && -f "$f" ]]` | `[ -n "$x" ] && [ -f "$f" ]` |
| `arr=(a b c)` ; `${arr[1]}` | une chaîne + `set --`, ou fichier temporaire |
| `${var//motif/rempl}` | `printf '%s' "$var" \| sed 's/motif/rempl/g'` |
| `echo -e "a\tb"` | `printf 'a\tb\n'` |
| `source f` | `. f` |
| `$((...))` avec `++`, `**` | arithmétique simple uniquement |
| `«<"chaîne"` | `printf '%s\n' "chaîne" \|` |
| `&> f` | `> f 2>&1` |
| `${PIPESTATUS[0]}` | `set -o pipefail` absent aussi |

Vérification avant la production, dans l'ordre de coût croissant :

1. **`shellcheck script.sh`** : il lit le shebang et signale chaque construction non
   compatible avec le code `SC2039` / `SC3xxx` (« In POSIX sh, X is undefined »).
   C'est la méthode de référence, intégrable en CI.
2. **Exécution réelle sous `dash`** : `dash -n script.sh` vérifie la syntaxe sans
   exécuter, `dash script.sh` exécute pour de vrai dans un environnement de test.
   `-n` attrape les erreurs de syntaxe, pas les commandes absentes (`[[`).
3. **`checkbashisms script.sh`** (paquet `devscripts`), l'outil que Debian utilise
   pour ses propres scripts d'empaquetage.

> [!NOTE]
> **Pourquoi**
>
> Le point important à formuler : `dash -n` et `shellcheck` ne détectent pas les mêmes
> choses. `[[` est une **commande introuvable** pour `dash`, pas une erreur de syntaxe :
> `dash -n` passe sans rien dire, et la panne n'apparaît qu'à l'exécution, souvent
> dans une branche `if` rarement empruntée — c'est-à-dire en production, six mois plus
> tard. C'est pour ça que l'analyse statique (`shellcheck`) est indispensable en plus
> du test syntaxique.

---

<a id="qo1-8"></a>**[QO1.8](README.md#qo1-8)** — *Trouver l'option `--one-file-system` sans internet, sans se souvenir de la commande.*

Démarche :

1. **Chercher par mot-clé dans les descriptions** :
   `man -k archive` ou `apropos "archiv"`. La sortie contient `tar (1) - an
   archiving utility` et `cpio (1)`, `dar (1)` selon l'installation.
2. **Chercher dans le texte complet des pages**, si l'index le permet :
   `man -K one-file-system` (majuscule K) balaie le corps de toutes les pages. C'est
   lent mais c'est exactement l'outil pour « je connais l'option, pas la commande ».
3. **Ouvrir la page et sauter à l'option** : `man 1 tar`, puis `/--one-file-system`
   puis Entrée ; `n` pour l'occurrence suivante, `N` pour la précédente, `q` pour
   quitter.
4. **Si la page man est un simple renvoi** (fréquent sur les outils GNU, dont la
   doc de référence est en Texinfo) : `info tar` puis la recherche `s`, ou
   `tar --help | less`.
5. **Documentation empaquetée** : `ls /usr/share/doc/tar/` contient `README`,
   `NEWS`, `changelog.Debian.gz`, parfois des exemples. `zless` pour les `.gz`.
6. **Mémo rapide** si `tldr` est installé : `tldr tar` donne les cinq formes
   réellement utilisées, avec des exemples copiables.

Réponse de fond : `--one-file-system` demande à `tar` (et à `du`, `rsync`, `cp`,
`find -xdev`) de ne pas franchir les points de montage. En sauvegarde de `/`, c'est
ce qui évite d'archiver `/proc`, `/sys`, `/run` et les partages NFS.

> [!NOTE]
> **Pourquoi**
>
> La hiérarchie à retenir pour la doc locale : `man` pour la référence exhaustive,
> `--help` pour la syntaxe rapide, `info` pour les outils GNU dont la page man est
> tronquée (`coreutils`, `tar`, `gawk`, `make`), `/usr/share/doc` pour les fichiers de
> configuration d'exemple et les notes d'empaquetage propres à la distribution, `tldr`
> pour l'usage courant. Sur une machine de production sans réseau, cette chaîne est
> tout ce dont tu disposes, et elle est presque toujours suffisante.

---

## 1.5 Exercices guidés

<a id="e1-1"></a>**[E1.1](README.md#e1-1)** — *Ré-exécuter une commande `apt` de l'historique de deux façons.*

```bash
# 1. recherche incrémentale
Ctrl-R puis taper : apt
#    Ctrl-R à nouveau : occurrence précédente
#    Entrée : exécute      flèche droite : édite avant d'exécuter
#    Ctrl-G : abandonne

# 2. expansion de l'historique
!apt        # dernière commande COMMENÇANT par apt
!?apt?      # dernière commande CONTENANT apt
!apt:p      # l'affiche sans l'exécuter, et l'ajoute à l'historique
```

> [!NOTE]
> **Pourquoi**
>
> `Ctrl-R` et `!` ne cherchent pas pareil : `!motif` n'accepte qu'un préfixe,
> `!?motif?` cherche n'importe où dans la ligne. L'expansion de l'historique a lieu
> **avant toutes les autres expansions**, dès la lecture de la ligne, ce qui explique
> pourquoi `echo "!!"` se fait développer alors qu'on est dans des guillemets doubles :
> le `!` est un cas particulier, seuls les guillemets simples le protègent.

> [!WARNING]
> **Piège**
>
> `!apt` exécute immédiatement, sans confirmation. Sur un historique contenant
> `apt purge`, ça fait mal. Le réflexe d'exploitation est `!apt:p` d'abord — la
> commande s'affiche et devient la dernière de l'historique, il suffit alors de faire
> flèche haut puis Entrée pour la lancer en connaissance de cause. Ou active
> `shopt -s histverify`, qui place systématiquement la ligne développée dans le tampon
> d'édition au lieu de l'exécuter.

---

<a id="e1-2"></a>**[E1.2](README.md#e1-2)** — *Créer `deploy/{blue,green}/{bin,conf,logs}` en une commande.*

```bash
mkdir -p ~/lab01/deploy/{blue,green}/{bin,conf,logs}
```

> [!NOTE]
> **Pourquoi**
>
> L'expansion des accolades est un produit cartésien : deux listes de 2 et 3 éléments
> donnent 6 mots, générés dans l'ordre lexicographique des accolades de gauche à
> droite. `mkdir` reçoit donc six arguments d'un coup, et `-p` crée les parents
> communs sans se plaindre qu'ils existent déjà. Vérifie avec `tree ~/lab01/deploy`
> ou, sans `tree`, `find ~/lab01/deploy -type d`.
>
> Le mécanisme n'a rien à voir avec les fichiers : `echo {a,b}{1,2}` affiche
> `a1 a2 b1 b2` même si rien n'existe sur le disque. C'est de la génération de texte,
> et c'est pour ça qu'elle passe avant tout le reste.

---

<a id="e1-3"></a>**[E1.3](README.md#e1-3)** — *Afficher `PATH` un répertoire par ligne, sans `tr` ni `sed`.*

```bash
printf '%s\n' "${PATH//:/$'\n'}"
```

> [!NOTE]
> **Pourquoi**
>
> `${var//motif/remplacement}` remplace **toutes** les occurrences (`/` simple n'en
> remplacerait qu'une). `$'\n'` est le quoting ANSI-C de bash : il produit un vrai
> caractère de saut de ligne, là où `"\n"` produirait les deux caractères `\` et `n`.
> Les guillemets autour de l'expansion sont indispensables : sans eux, le découpage
> des mots transformerait les sauts de ligne en séparateurs d'arguments et
> `printf '%s\n'` produirait… le même résultat par accident. Garde l'habitude de
> quoter, l'accident ne se reproduit pas avec un autre format.
>
> Variante lisible par tableau (bash uniquement, `dash` n'a ni tableau ni here-string) :
>
> ```bash
>    IFS=: read -ra dirs <<< "$PATH"
> printf '%s\n' "${dirs[@]}"
> ```

---

<a id="e1-4"></a>**[E1.4](README.md#e1-4)** — *Quatre sorties avec `APP=facturation`.*

```bash
APP=facturation
echo "$APP"         # facturation  -> doubles : expansion + protection
echo '$APP'         # $APP         -> simples : rien n'est interprété
echo \$APP          # $APP         -> backslash : échappe le caractère suivant
echo "${APP}-prod"  # facturation-prod
```

> [!NOTE]
> **Pourquoi**
>
> Les accolades de `${APP}` ne sont **pas** de l'expansion d'accolades : c'est la
> syntaxe explicite de l'expansion de paramètre. Elles délimitent le nom de la
> variable. Ici elles sont facultatives (`-` ne peut pas faire partie d'un nom de
> variable), mais elles deviennent obligatoires dès que le caractère suivant pourrait
> en faire partie : `echo "$APP_prod"` cherche une variable nommée `APP_prod`, alors
> que `echo "${APP}_prod"` donne `facturation_prod`. Prends l'habitude systématique
> des accolades dans les chaînes composées : ça élimine toute une classe de bugs
> silencieux.

---

<a id="e1-5"></a>**[E1.5](README.md#e1-5)** — *Supprimer un fichier nommé `-fichier-bizarre.txt`.*

```bash
rm -- -fichier-bizarre.txt        # 1. fin des options
rm ./-fichier-bizarre.txt         # 2. le nom ne commence plus par un tiret
```

> [!NOTE]
> **Pourquoi**
>
> Le shell ne joue aucun rôle ici : il passe `-fichier-bizarre.txt` tel quel à `rm`.
> C'est `rm`, via `getopt`, qui voit un mot commençant par `-` et le traite comme un
> groupe d'options courtes : `-f` et `-i` sont des options valides, `rm` continue d'analyser et bute sur `c`, d'où `rm: invalid option -- 'c'`. Avec un nom comme `-rf`, il n'y aurait même pas d'erreur : `rm` attendrait simplement des opérandes.
>
> `--` est la convention POSIX universelle : tout ce qui suit est un opérande, jamais
> une option. Elle est respectée par toutes les commandes GNU. La seconde méthode
> contourne le problème autrement, en changeant le nom vu par la commande : `./` ne
> modifie pas le chemin résolu mais élimine le tiret initial.
>
> En script, mets systématiquement `--` avant une variable qui contient un nom de
> fichier : `rm -- "$f"`, `mv -- "$src" "$dst"`, `grep -- "$motif" fichier`.

> [!WARNING]
> **Piège**
>
> La technique `rm ./-fichier` ne fonctionne évidemment pas pour les commandes qui
> n'attendent pas un chemin (`grep -- "$motif"`), et `--` ne fonctionne pas avec les
> quelques commandes non conformes (`tar` historique, `dd`, `find` dont les options
> précèdent les chemins). Quand `--` est refusé, retombe sur le préfixe `./`.

---

<a id="e1-6"></a>**[E1.6](README.md#e1-6)** — *Compter les lignes de tous les `.log`, y compris `rapport final.log`.*

```bash
cd ~/lab01/logs
wc -l -- ./*.log
```

> [!NOTE]
> **Pourquoi**
>
> C'est le point le plus contre-intuitif du module et il mérite d'être vérifié soi-même :
> **les résultats du globbing ne sont pas soumis au découpage des mots**. Le globbing
> est l'étape 5, le découpage l'étape 4. `./*.log` produit donc une liste d'arguments
> déjà correctement séparés, dont l'un contient une espace, et `wc` reçoit
> `argv = [wc, -l, - -, ./access.log, ./app.log, ./rapport final.log, ...]`.
>
> Aucun quoting n'est nécessaire, et il serait même nuisible : `"./*.log"` empêcherait
> le globbing et chercherait un fichier littéralement nommé `*.log`.
>
> Le `./` et le `--` protègent du cas où un fichier commencerait par un tiret ;
> le `--` seul suffirait, les deux ne coûtent rien.

> [!WARNING]
> **Piège**
>
> Ce qui casse, c'est de faire transiter la liste par une variable ou une substitution
> de commande : `wc -l $(ls *.log)` refait passer les noms par l'étape 4 et casse.
> De même `fichiers=$(ls *.log); wc -l $fichiers`. Dès qu'une liste de chemins doit
> être stockée, il faut un tableau bash (`fichiers=(./*.log)`, puis
> `wc -l -- "${fichiers[@]}"`) ou `find -print0 | xargs -0`.

---

<a id="e1-7"></a>**[E1.7](README.md#e1-7)** — *Jours écoulés depuis le début de l'année, avec le piège du zéro de tête.*

```bash
jour=$(date +%j)              # 261 aujourd'hui, mais 008 le 8 janvier
echo $(( 10#$jour ))
```

> [!NOTE]
> **Pourquoi**
>
> Voir Q1.9 : dans `$(( ))`, un littéral commençant par `0` est lu en base 8, et `08`
> comme `09` sont invalides en octal. Le préfixe `10#` de bash force la base 10 pour
> le littéral qui suit. Il s'applique à un littéral, pas à une variable entière :
> `10#$jour` est correct, `10#jour` ne l'est pas.
>
> Vérification du piège sans attendre janvier :
>
> ```bash
> jour=008; echo $(( jour + 1 ))      # bash: 008: value too great for base
> jour=008; echo $(( 10#$jour + 1 ))  # 9
> ```
>
> Alternative sans arithmétique : `date +%-j` supprime le remplissage (extension GNU,
> absente de BSD/macOS).

---

<a id="e1-8"></a>**[E1.8](README.md#e1-8)** — *Nature de `ls`, `cd`, `ll`, `[`, `command`.*

```console
$ type -a ls cd ll '[' command
ls is aliased to `ls --color=auto'
ls is /usr/bin/ls
ls is /bin/ls
cd is a shell builtin
ll is aliased to `ls -alF'
[ is a shell builtin
[ is /usr/bin/[
[ is /bin/[
command is a shell builtin
```

| Nom | Nature réelle |
|---|---|
| `ls` | alias (Ubuntu) masquant le fichier `/usr/bin/ls` |
| `cd` | builtin, et **obligatoirement** builtin |
| `ll` | alias de `~/.bashrc` |
| `[` | builtin, doublé par un vrai binaire `/usr/bin/[` |
| `command` | builtin |
| (`/bin/ls` et `/usr` | `/bin/ls` sont le même fichier : `/bin` est un lien vers `usr/bin` depuis la fusion de `/usr`, et le |
| `PATH` d'Ubuntu contient | les deux.) |

> [!NOTE]
> **Pourquoi**
>
> Deux points méritent l'attention.
>
> `cd` **doit** être un builtin : le répertoire courant est un attribut du processus.
> Un `/usr/bin/cd` changerait le répertoire de son propre processus, puis mourrait, et
> le shell parent n'aurait pas bougé. Même raisonnement pour `export`, `ulimit`,
> `umask`, `source`.
>
> `[` existe à la fois en builtin et en binaire pour des raisons historiques et de
> conformité POSIX : le standard exige qu'un exécutable `/usr/bin/[` soit présent pour
> que `find -exec [ ... ] \;` fonctionne. En pratique, le builtin gagne toujours, sauf
> si tu écris `/usr/bin/[` explicitement. C'est pour ça que `[` est une **commande**,
> d'où l'obligation d'espaces autour : `[ -f "$f" ]` et jamais `[-f "$f"]`.

---

<a id="e1-9"></a>**[E1.9](README.md#e1-9)** — *Fonction `mkcd`, disponible dans tous les shells interactifs.*

Dans `~/.bashrc`, **après** la garde d'interactivité :

```bash
mkcd() {
  mkdir -p -- "$1" && cd -- "$1"
}
```

Vérifications :

```bash
. ~/.bashrc
mkcd ~/lab01/essai/un/deux && pwd
ssh mathieu@localhost 'echo OK'    # doit afficher exactement : OK
```

> [!NOTE]
> **Pourquoi**
>
> Trois détails qui font la différence entre une fonction de blog et une fonction
> d'exploitation :
>
> * `"$1"` entre guillemets : sinon `mkcd "mon dossier"` crée deux répertoires.
> * `--` avant l'argument : protège d'un nom commençant par un tiret.
> * `&&` plutôt que `;` : si `mkdir` échoue (droits, disque plein), on ne tente pas un
>   `cd` qui laisserait l'utilisateur dans un état incohérent, et le code retour de la
>   fonction reflète l'échec.
>
> Une fonction, pas un alias : un alias ne peut pas recevoir d'argument au milieu de
> sa définition, et n'est pas développé en non interactif (Q1.13).
>
> Si la fonction doit aussi servir dans des scripts appelés depuis ce shell,
> `export -f mkcd` la transmet aux bash fils — mais pas à `dash`, ni aux processus
> non-bash. En script, mieux vaut sourcer un fichier de bibliothèque commun.

---

<a id="e1-10"></a>**[E1.10](README.md#e1-10)** — *Configuration complète de l'historique.*

Dans `~/.bashrc`, après la garde d'interactivité :

```bash
HISTSIZE=10000
HISTFILESIZE=50000
HISTCONTROL=ignoreboth
HISTTIMEFORMAT='%F %T '
shopt -s histappend
PROMPT_COMMAND="history -a; ${PROMPT_COMMAND:-}"
```

> [!NOTE]
> **Pourquoi**
>
> Ligne par ligne :
>
> * `HISTSIZE` = lignes gardées **en mémoire** pendant la session. `HISTFILESIZE` =
>   lignes gardées dans le fichier. Le second doit être supérieur ou égal au premier,
>   sinon le fichier est tronqué à chaque écriture et tu perds l'historique ancien.
> * `ignoreboth` = `ignorespace` + `ignoredups`. `ignoredups` ne supprime que les
>   doublons **consécutifs** ; `erasedups` (à mettre à la place) supprime toutes les
>   occurrences antérieures identiques, au prix d'une réécriture du fichier.
> * `HISTTIMEFORMAT` a un double effet : il change l'affichage de `history`, et il
>   fait écrire dans le fichier une ligne `#1758196931` avant chaque commande. Ces
>   lignes de commentaire sont écrites **dès que la variable est définie**, donc un
>   fichier existant sans horodatage se retrouve partiellement horodaté — c'est normal
>   et sans conséquence.
> * `histappend` : sans lui, la dernière session fermée écrase les autres (Q1.15).
> * `history -a` dans `PROMPT_COMMAND` : écrit après chaque commande, pas seulement à
>   la déconnexion. C'est ce qui sauve l'historique quand la session SSH tombe. La
>   forme `"history -a; ${PROMPT_COMMAND:-}"` préserve un `PROMPT_COMMAND` déjà défini
>   (par `debian_chroot`, par un thème de prompt) au lieu de l'écraser.

> [!WARNING]
> **Piège**
>
> Ne pas ajouter `history -c; history -r` (recharger l'historique des autres sessions
> à chaque prompt) sans y réfléchir : ça rend la flèche haut imprévisible, parce que
> ton historique local est remplacé par celui des autres terminaux entre deux
> commandes. La plupart des gens qui copient cette recette la retirent au bout d'une
> semaine.

---

<a id="e1-11"></a>**[E1.11](README.md#e1-11)** — *`systemctl status ssh` à l'écran et dans un fichier, stderr inclus.*

```bash
systemctl status ssh --no-pager 2>&1 | tee ~/lab01/logs/ssh-status.log
```

> [!NOTE]
> **Pourquoi**
>
> Trois éléments :
>
> * `2>&1` **avant** le tube, pour que le fd 2 soit déjà redirigé vers le fd 1 quand le
>   tube est mis en place (Q1.14).
> * `--no-pager` : `systemctl status` invoque `less` quand sa sortie est un terminal.
>   Dans un tube ce n'est plus le cas, donc ce n'est pas strictement nécessaire ici,
>   mais c'est le réflexe à garder pour tous les appels `systemctl` en script, où un
>   pager bloqué fige un job de CI sans message d'erreur.
> * `tee` sans `-a` écrase le fichier ; avec `-a` il ajoute.
>
> Attention au code retour : `systemctl status` renvoie 3 pour un service arrêté, et
> le tube masque ce code au profit de celui de `tee`. Si tu testes l'état d'un service
> en script, utilise `systemctl is-active --quiet ssh` et son code retour, pas `status`.

> [!WARNING]
> **Piège**
>
> Sur Ubuntu 24.04, l'unité s'appelle `ssh.service` ; `sshd` n'est qu'un alias fourni
> par le paquet. Sur Rocky 9, l'unité s'appelle réellement `sshd.service` et `ssh`
> n'existe pas. Écris `systemctl status ssh` sur Ubuntu, `sshd` sur Rocky.

---

<a id="e1-12"></a>**[E1.12](README.md#e1-12)** — *Rendre une commande totalement muette, et prouver la différence.*

```bash
commande > /dev/null 2>&1      # portable (POSIX), silence total
commande &> /dev/null          # raccourci bash, strictement équivalent

# démonstration de la différence avec la forme piégeuse
ls /inexistant > /dev/null 2>&1     # rien du tout
ls /inexistant 2>&1 > /dev/null     # ls: cannot access '/inexistant': ...
```

> [!NOTE]
> **Pourquoi**
>
> `/dev/null` est un périphérique caractère fourni par le noyau : toute écriture y est
> acceptée et jetée, toute lecture renvoie immédiatement la fin de fichier. C'est donc
> aussi la façon de fournir une entrée vide : `commande < /dev/null` évite qu'un
> programme se bloque en attendant une saisie dans un contexte non interactif — un
> classique des jobs de CI qui « ne se terminent jamais ».
>
> La troisième ligne prouve l'ordre de traitement de Q1.4 : dans `2>&1 > /dev/null`,
> le fd 2 est dupliqué sur le terminal avant que le fd 1 ne parte vers `/dev/null`,
> donc l'erreur reste visible.
>
> `&>` est une extension bash (et zsh). Dans un script en `#!/bin/sh`, elle n'a pas la
> même signification : `dash` lit `cmd &` (arrière-plan) suivi de `> /dev/null`, ce qui
> lance la commande en tâche de fond et redirige… une commande vide. Aucune erreur,
> comportement totalement différent. C'est la raison de préférer `> f 2>&1`.

---

<a id="e1-13"></a>**[E1.13](README.md#e1-13)** — *`CDPATH` pour `cd sites-enabled` et `cd nginx` depuis n'importe où.*

Dans `~/.bashrc` :

```bash
CDPATH=.:/etc:/etc/nginx:/var/log
```

> [!NOTE]
> **Pourquoi**
>
> `cd` avec un argument **relatif** (ne commençant ni par `/`, ni par `./`, ni par
> `../`) cherche dans chaque répertoire listé dans `CDPATH`, de gauche à droite, et
> s'arrête au premier succès. `cd nginx` trouve `/etc/nginx` grâce à l'entrée `/etc` ;
> `cd sites-enabled` trouve `/etc/nginx/sites-enabled` grâce à l'entrée `/etc/nginx`.
>
> `.` doit figurer **en premier**, sinon le comportement normal de `cd` est altéré :
> si tu es dans `/srv/app` et qu'il existe à la fois `/srv/app/nginx` et `/etc/nginx`,
> un `CDPATH` sans `.` en tête t'envoie dans `/etc/nginx` alors que tu voulais le
> sous-répertoire local. C'est très déroutant et ça passe inaperçu longtemps.
>
> Quand `cd` utilise `CDPATH`, il **affiche** le chemin d'arrivée sur stdout. C'est
> une aide en interactif et une pollution en script.

> [!WARNING]
> **Piège**
>
> N'exporte jamais `CDPATH`. Exporté, il est hérité par tous les scripts que tu lances,
> et un `cd config` dans un script se retrouve à changer de répertoire ailleurs que
> prévu, tout en écrivant une ligne parasite sur stdout qui casse
> `resultat=$(cd config && pwd)`. `CDPATH` est une commodité de session : on le définit
> dans `~/.bashrc`, sans `export`.

---

<a id="e1-14"></a>**[E1.14](README.md#e1-14)** — *Documentation du format de `/etc/fstab`, recherche de `nofail`.*

```bash
man 5 fstab
# dans le pager less :
/nofail     puis Entrée    -> saute à la première occurrence
n                          -> occurrence suivante
N                          -> occurrence précédente
q                          -> quitter

tldr mount                 # comparaison : 5 exemples, 10 secondes
```

> [!NOTE]
> **Pourquoi**
>
> Le pager par défaut de `man` est `less`, ce qui veut dire que tous les raccourcis de
> `less` sont disponibles dans une page de manuel : `/` et `?` pour chercher en avant
> et en arrière, `g` et `G` pour le début et la fin, `Espace` et `b` pour la page
> suivante et précédente, `-i` pour rendre la recherche insensible à la casse.
>
> `man -k` / `apropos` cherche uniquement dans les **descriptions** d'une ligne ;
> `man -K` cherche dans le **corps** de toutes les pages (lent). `whatis fstab` affiche
> la ligne de résumé de chaque section où le nom existe : c'est le moyen le plus rapide
> de savoir quelles sections existent.
>
> `tldr` n'est pas un remplaçant de `man`, c'est un complément : il donne les cinq
> usages réels d'une commande, `man` donne la vérité exhaustive. Pour une option
> obscure ou un format de fichier, `man` est le seul recours.

---

<a id="e1-15"></a>**[E1.15](README.md#e1-15)** — *Variable exportée contre variable de shell.*

```bash
PROXY_URL=http://10.10.10.1:3128           # variable de shell
export HTTPS_PROXY=http://10.10.10.1:3128  # variable d'environnement

env                       # ne montre que HTTPS_PROXY
export -p                 # ne montre que les variables exportées
set                       # montre les deux (shell + environnement + fonctions)
declare -p PROXY_URL HTTPS_PROXY
```

Sortie de `declare -p` :

```console
declare -- PROXY_URL="http://10.10.10.1:3128"
declare -x HTTPS_PROXY="http://10.10.10.1:3128"
```

> [!NOTE]
> **Pourquoi**
>
> L'attribut `-x` dans la sortie de `declare -p` est la marque de l'export. C'est la
> façon la plus fiable de trancher : `env | grep` ne dit pas si une variable absente
> n'existe pas ou existe sans être exportée.
>
> Mécanisme sous-jacent : l'environnement d'un processus est un simple tableau de
> chaînes `CLÉ=valeur` copié par le noyau lors de l'appel `execve()`. `export` marque
> une variable pour qu'elle soit incluse dans ce tableau lors du prochain `exec`. Une
> variable de shell non exportée n'existe que dans la mémoire de bash : elle disparaît
> pour tout processus fils, y compris un script que tu lances.
>
> Vérification en une ligne :
>
> ```bash
> bash -c 'echo "shell=[$PROXY_URL] env=[$HTTPS_PROXY]"'
> # shell=[] env=[http://10.10.10.1:3128]
> ```

> [!WARNING]
> **Piège**
>
> Les variables de proxy ne sont pas standardisées : `curl` et `wget` lisent
> `http_proxy` en **minuscules** (et `HTTPS_PROXY` en majuscules pour curl),
> `apt` a sa propre configuration dans `/etc/apt/apt.conf.d/`, et `sudo` efface par
> défaut l'environnement de l'utilisateur (`env_reset` dans `/etc/sudoers`). D'où le
> grand classique : « le proxy marche pour moi mais pas avec `sudo apt update` ».
> Réponse : `sudo -E`, ou `Defaults env_keep += "http_proxy https_proxy no_proxy"`.

---

<a id="e1-16"></a>**[E1.16](README.md#e1-16)** — *Pile de répertoires.*

```bash
cd ~
pushd /etc/nginx        # /etc/nginx ~  -> affiche la pile
pushd /var/log          # /var/log /etc/nginx ~
dirs -v                 # pile numérotée
#  0  /var/log
#  1  /etc/nginx
#  2  ~
popd                    # revient dans /etc/nginx
dirs -c                 # vide la pile
```

> [!NOTE]
> **Pourquoi**
>
> `pushd rep` empile le répertoire courant et se déplace ; `popd` dépile et se déplace
> vers le sommet. `dirs -v` numérote, ce qui permet `pushd +2` pour faire tourner la
> pile jusqu'à l'entrée 2 sans dépiler, et `popd +1` pour retirer une entrée du milieu.
>
> L'intérêt réel en exploitation : tu pars de `/var/log` pour diagnostiquer, tu
> descends dans trois répertoires de configuration, et tu reviens exactement où tu
> étais sans avoir à retaper un chemin ni à te souvenir duquel. `cd -` ne gère que
> deux niveaux.
>
> `pushd` et `popd` sont des builtins bash, absents de `dash`. En script POSIX, on
> utilise un sous-shell : `( cd /etc/nginx && faire_le_travail )` — le répertoire du
> shell parent n'est jamais modifié, ce qui est plus propre qu'une pile.

---

## 1.6 Labs

### <a id="l1-1"></a>**[L1.1](README.md#l1-1)** — Standardiser le shell du poste d'admin

*Produire un `~/.bashrc` de référence sur `lab-adm` : prompt informatif, éditeur,
pager, historique, `~/bin` dans le `PATH`, sans casser les shells non interactifs.*

Bloc à ajouter dans `~/.bashrc`, **après** la garde `case $- in *i*)` :

```bash
# --- prompt : code retour affiché uniquement si != 0 -------------------
__prompt_rc() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then RC_TAG="[$rc] "; else RC_TAG=""; fi
  return 0
}
PROMPT_COMMAND="__prompt_rc; history -a; ${PROMPT_COMMAND:-}"
PS1='${RC_TAG}\u@\h:\w\$ '

# --- éditeur et pager --------------------------------------------------
export EDITOR=vim
export VISUAL=vim
export PAGER=less
export LESS='-R -X -F'

# --- options de shell --------------------------------------------------
shopt -s histappend checkwinsize

# --- historique --------------------------------------------------------
HISTSIZE=10000
HISTFILESIZE=50000
HISTCONTROL=ignoreboth
HISTTIMEFORMAT='%F %T '

# --- PATH, idempotent --------------------------------------------------
case ":$PATH:" in
  *":$HOME/bin:"*) ;;
  *) PATH="$HOME/bin:$PATH" ;;
esac
export PATH
```

`~/bin/hostinfo` :

```bash
#!/usr/bin/env bash
set -euo pipefail
printf 'hote    : %s\n' "$(hostname -f)"
printf 'ip      : %s\n' "$(hostname -I | cut -d' ' -f1)"
printf 'uptime  : %s\n' "$(uptime -p)"
```

```bash
chmod +x ~/bin/hostinfo
```

Vérification finale :

```bash
cd /tmp && hostinfo
ssh mathieu@localhost 'echo OK'      # doit afficher exactement : OK
bash check_M01_01.sh
```

> [!NOTE]
> **Pourquoi**
>
> Les points qui font qu'un `.bashrc` tient en production :
>
> **`PS1` en guillemets simples.** `PS1='${RC_TAG}...'` stocke la chaîne
> `${RC_TAG}` telle quelle ; bash la développe **à chaque affichage du prompt**. Avec
> des guillemets doubles, `${RC_TAG}` serait développé une seule fois, au chargement du
> fichier, et figé à sa valeur d'alors (vide). C'est l'erreur la plus fréquente sur les
> prompts dynamiques.
>
> **`local rc=$?` en toute première ligne de la fonction.** `$?` est écrasé par la
> moindre commande. Si tu mets un `printf` avant, tu captures le code de `printf`, pas
> celui de la commande de l'utilisateur. Et le `return 0` final évite que la fonction
> de prompt devienne elle-même la « commande précédente » en échec.
>
> **`PROMPT_COMMAND` en concaténation.** Écrire `PROMPT_COMMAND=__prompt_rc` écraserait
> ce qu'Ubuntu ou un outil tiers y a déjà mis (mise à jour du titre de fenêtre, par
> exemple). La forme `"nouveau; ${PROMPT_COMMAND:-}"` compose au lieu d'écraser.
>
> **`checkwinsize`** fait relire `LINES` et `COLUMNS` après chaque commande. Sans lui,
> redimensionner la fenêtre du terminal pendant une session SSH laisse bash avec
> l'ancienne largeur, et le texte du prompt se recouvre lui-même après un `Ctrl-R`.
>
> **`LESS='-R -X -F'`** : `-R` laisse passer les séquences de couleur ANSI (sinon
> `systemctl status` affiche `ESC[0;32m`), `-X` n'efface pas l'écran en sortie (la
> sortie reste visible dans le scrollback), `-F` quitte immédiatement si le contenu
> tient sur un écran.
>
> **`PATH` idempotent.** Le test `case ":$PATH:" in *":$HOME/bin:"*)` encadre `PATH` de
> `:` pour que la première et la dernière entrée soient testées comme les autres.
> Sans ce test, un `. ~/.bashrc` répété trois fois pendant la mise au point laisse
> `~/bin` trois fois dans le `PATH`.

> [!WARNING]
> **Piège**
>
> Le piège qui coûte une heure : écrire le bloc **avant** la garde
> `case $- in *i*) ;; *) return;; esac`. Tout ce qui affiche quelque chose (un
> `echo "Bienvenue"`, une bannière, un `hostinfo`) placé avant la garde casse
> `scp`, `rsync` et `sftp` — ces protocoles attendent un flux binaire propre sur
> stdout et interprètent ta bannière comme un paquet de protocole. Le symptôme est un
> `scp` ou un `sftp` qui échoue avec `Received message too long` `1114795883`,
> sans aucun rapport apparent avec le `.bashrc`. Seules les affectations de variables
> d'environnement ont leur place au-dessus de la garde.

---

### <a id="l1-2"></a>**[L1.2](README.md#l1-2)** — Ticket INC-2214 : wrapper de journalisation

*Écrire `sauvegarde-wrap.sh` qui journalise stdout et stderr de `sauvegarde.sh`,
affiche à l'écran, préserve le code retour et gère un mode silencieux.*

Étape 1, identifier les flux :

```bash
~/lab01/bin/sauvegarde.sh 2>/dev/null    # ne reste que stdout
~/lab01/bin/sauvegarde.sh 1>/dev/null    # ne reste que stderr
```

`~/lab01/bin/sauvegarde-wrap.sh` :

```bash
#!/usr/bin/env bash
set -uo pipefail

CIBLE="$HOME/lab01/bin/sauvegarde.sh"
LOG="$HOME/lab01/logs/sauvegarde.log"
mkdir -p -- "$(dirname -- "$LOG")"

printf '=== %s début ===\n' "$(date '+%F %T')" >> "$LOG"

if [ "${SILENCIEUX:-0}" = "1" ]; then
  "$CIBLE" >> "$LOG" 2>&1
  rc=$?
else
  "$CIBLE" 2>&1 | tee -a -- "$LOG"
  rc=${PIPESTATUS[0]}
fi

printf '=== %s fin (code %d) ===\n' "$(date '+%F %T')" "$rc" >> "$LOG"
exit "$rc"
```

```bash
chmod +x ~/lab01/bin/sauvegarde-wrap.sh
~/lab01/bin/sauvegarde-wrap.sh; echo "code=$?"
SILENCIEUX=1 ~/lab01/bin/sauvegarde-wrap.sh; echo "code=$?"
bash check_M01_02.sh
```

> [!NOTE]
> **Pourquoi**
>
> **`${PIPESTATUS[0]}` est le cœur du lab.** Dans un tube, `$?` est le code de la
> **dernière** commande. `tee` réussit presque toujours, donc `$?` vaut 0 même quand la
> sauvegarde a échoué : le job de supervision croit que tout va bien. `PIPESTATUS` est
> un tableau bash contenant le code de chaque étage du tube, indexé de gauche à droite.
> Il est écrasé par la commande suivante : il faut le lire **immédiatement**, sur la
> ligne qui suit le tube, avant même un `echo`.
>
> Alternative POSIX si le script devait tourner sous `dash` : `set -o pipefail`
> n'existe pas non plus, il faut passer par un fichier temporaire pour le code retour,
> ou par un tube nommé (`mkfifo`); la substitution de processus `>(tee ...)` est, elle aussi, une extension bash.
>
> **`set -euo pipefail` amputé de `-e`.** Ici on veut explicitement continuer après
> l'échec du script cible, pour écrire la ligne de fin et sortir avec son code. Avec
> `-e`, le script mourrait avant. C'est un des rares cas où retirer `-e` est le bon
> choix — et il mérite un commentaire dans le code pour que le prochain lecteur ne le
> remette pas « par bonne pratique ».
>
> **`2>&1 | tee`** et pas `| tee ... 2>&1` : voir Q1.14, le tube ne transporte que le
> fd 1, la fusion doit avoir lieu avant.
>
> **Le mode silencieux utilise `»` et non** `> /dev/null` : on veut la trace complète
> dans le fichier, seul l'affichage écran disparaît. D'où deux branches plutôt qu'une
> redirection conditionnelle.

> [!WARNING]
> **Piège**
>
> Deux défauts fréquents dans les copies :
>
> * `tee` sans `-a` : chaque exécution écrase le journal de la précédente, ce qui est
>   exactement le problème du ticket.
> * faire tourner ce wrapper depuis cron avec une sortie non redirigée : cron envoie
>   toute sortie par mail local. Un wrapper qui affiche tout produit un mail par nuit.
>   En cron, on appelle la variante `SILENCIEUX=1`, ou on redirige l'appel dans le
>   `crontab`.

---

### <a id="l1-3"></a>**[L1.3](README.md#l1-3)** — Livraison avec des noms de fichiers hostiles

*Normaliser `~/lab01/livraison/` sans perdre de fichier.*

```bash
cd ~/lab01/livraison

# 1. lister sans ambiguïté
ls -b          # affiche les espaces sous forme \  et les caractères spéciaux
ls -Q          # chaque nom entre guillemets
printf '[%s]\n' ./*

# 2. compter, et comparer avec la méthode fautive
ls -A | wc -l                       # nombre réel de fichiers
set -- $(ls); echo $#               # nombre après découpage : plus élevé

# 3. renommer : espaces -> souligné
for f in ./*\ *; do
  [ -e "$f" ] || continue
  mv -- "$f" "${f// /_}"
done

# 4. supprimer le fichier à tiret initial
rm -- ./-rapport-2026.txt

# 5. afficher le fichier dont le nom contient un ?
ls -l -- 'donnees?.csv'
cat -- 'donnees?.csv'

# 6. archiver et vérifier
tar -czf ~/lab01/livraison.tar.gz -C ~/lab01 livraison
tar -tzf ~/lab01/livraison.tar.gz | wc -l

bash check_M01_03.sh
```

> [!NOTE]
> **Pourquoi**
>
> **Étape 1.** `ls` remplace par défaut les caractères non imprimables par `?` quand la
> sortie est un terminal, ce qui rend un nom contenant une tabulation indiscernable
> d'un nom contenant un `?`. `ls -b` (échappement style C) et `ls -Q` (guillemets)
> lèvent l'ambiguïté. `printf '[%s]\n' ./*` est la méthode la plus fiable : les
> crochets encadrent exactement le nom, espaces compris.
>
> **Étape 2.** L'écart entre les deux comptages est la démonstration pratique de
> Q1.17 : `$(ls)` produit une chaîne, le découpage des mots la coupe sur chaque espace,
> et un fichier `rapport final.log` devient deux « fichiers ».
>
> **Étape 3.** `for f in ./*\ *` est un glob qui sélectionne exactement les noms
> contenant une espace : `*` puis une espace échappée puis `*`. Le `[ -e "$f" ]`
> protège du cas « aucune correspondance », où le motif arrive littéralement.
> `${f// /_}` remplace toutes les espaces par des soulignés — c'est de l'expansion de
> paramètre, aucun processus externe n'est créé.
>
> **Étape 5.** Le `?` du nom est un métacaractère de globbing : sans quoting,
> `ls donnees?.csv` chercherait aussi `donnees1.csv`, `donneesX.csv`. Les guillemets
> simples empêchent le globbing (étape 5 de l'expansion) et `ls` reçoit le nom exact.
> Note l'asymétrie : le quoting protège du globbing à l'aller, mais si le fichier
> n'existait pas, le motif quoté ne serait pas non plus développé — l'erreur serait
> alors claire au lieu d'être silencieuse.
>
> **Étape 6.** `tar -C ~/lab01 livraison` archive avec des chemins relatifs à partir
> de `~/lab01`, donc l'archive contient `livraison/...` et non
> `home/mathieu/lab01/livraison/...`. Sans `-C`, `tar` affiche
> `tar: Removing leading '/' from member names` et produit une arborescence
> inexploitable à la restauration.

> [!WARNING]
> **Piège**
>
> La boucle `for f in ./*\ *` ne traite qu'un seul passage : si un fichier s'appelle
> `rapport final v2.log`, `${f// /_}` remplace bien les deux espaces en une fois (c'est
> `//`, global). En revanche, si deux fichiers différents donnent le même nom après
> remplacement, `mv` écrase silencieusement le premier. En production, utilise
> `mv -n --` (no-clobber) et traite les collisions à la main.

---

### <a id="l1-4"></a>**[L1.4](README.md#l1-4)** — Cartographier les environnements

*Instrumenter les fichiers de démarrage, produire la cartographie, poser
`JAVA_HOME` au bon endroit.*

Étape 1, la trace. En tête de `~/.profile`, de `~/.bashrc` et de
`~/.bash_profile` s'il existe :

```bash
{ mkdir -p "$HOME/lab01/logs" && \
  printf '%s %s\n' "$(date +%T)" "$HOME/.bashrc"; } \
  >> "$HOME/lab01/logs/startup.log" 2>&1
```

(adapte le nom du fichier dans chaque copie)

Étape 2, déclencher les quatre cas :

```bash
: > ~/lab01/logs/startup.log
ssh mathieu@localhost        # puis exit          -> login interactif
bash                         # puis exit          -> interactif non-login
ssh mathieu@localhost 'true' #                    -> non interactif distant
bash -c true                 #                    -> non interactif local
cat ~/lab01/logs/startup.log
```

Étape 3, `~/lab01/cartographie.md` :

| Situation | Fichiers lus | Ordre |
|---|---|---|
| Login interactif (SSH avec TTY) | `/etc/profile`, `/etc/profile.d/*`, `~/.profile`, `~/.bashrc` | `.profile` source `.bashrc` |
| Interactif non-login (`bash`) | `/etc/bash.bashrc`, `~/.bashrc` | `.profile` non lu |
| `ssh hôte 'cmd'` | `~/.bashrc` seulement, coupé à la garde `case $-` | rien d'autre |
| `bash -c true` | aucun | `$BASH_ENV` si défini |

Étape 4-5, poser la variable :

```bash
# solution couvrant les quatre cas, système, nécessite sudo :
echo 'JAVA_HOME=/opt/jdk21' | sudo tee -a /etc/environment

# solution shell seule (couvre les cas shell, y compris bash -c lancé depuis
# ce shell qui hérite de l'export ; ne couvre pas cron) :
# tout en HAUT de ~/.bashrc, AVANT la garde case $- :
export JAVA_HOME=/opt/jdk21
```

```bash
ssh mathieu@localhost 'echo $JAVA_HOME'     # /opt/jdk21
bash check_M01_04.sh
```

> [!NOTE]
> **Pourquoi**
>
> **Pourquoi `.profile` et pas `.bash_profile` sur Ubuntu.** Bash cherche, dans l'ordre,
> `~/.bash_profile`, `~/.bash_login`, `~/.profile`, et s'arrête au **premier trouvé**.
> Ubuntu ne livre que `~/.profile` (depuis `/etc/skel`), qui contient :
>
> ```bash
> if [ -n "$BASH_VERSION" ]; then
>     if [ -f "$HOME/.bashrc" ]; then
>         . "$HOME/.bashrc"
>     fi
> fi
> ```
>
> C'est ce pont qui donne l'illusion que `~/.bashrc` est toujours lu. Créer un
> `~/.bash_profile` casse le pont, et c'est exactement la panne BF1.3.
>
> **Pourquoi `bash -c true` ne lit rien.** Un shell non interactif ne lit que le
> fichier désigné par `$BASH_ENV`, s'il est défini et si le shell n'est pas en mode
> POSIX. Il n'y a aucun fichier par défaut. Le cas `ssh hôte 'cmd'` est une exception
> documentée : bash détecte qu'il est lancé par un démon distant et lit `~/.bashrc`
> malgré tout — d'où le comportement différent entre les deux cas non interactifs,
> qui est la vraie découverte du lab.
>
> **Pourquoi `/etc/environment` est la bonne réponse pour « les quatre cas ».**
> Ce n'est pas un script shell : c'est un fichier de paires `CLÉ=valeur` lu par le
> module PAM `pam_env`, au moment où la session est créée — donc **avant** que le
> moindre shell ne démarre. La variable est alors dans l'environnement hérité, quel que
> soit le shell, quel que soit son mode, et y compris pour cron sur Debian/Ubuntu dont
> `/etc/pam.d/cron` charge `pam_env`. Il n'y a ni `export`, ni expansion de variable,
> ni commande possible dans ce fichier : `PATH=$PATH:/opt/bin` y est littéral et casse
> le `PATH` de toutes les sessions.
>
> **Pourquoi la trace doit écrire sur un fichier et rien sur stdout.** Voir le piège de
> L1.1 : la moindre sortie dans un fichier de démarrage casse `scp` et `rsync`. Le
> `2>&1` dans le bloc de trace évite aussi qu'un `mkdir` en échec écrive sur stderr.

> [!WARNING]
> **Piège**
>
> Après avoir instrumenté, **retire les traces**. Un `date` exécuté à chaque ouverture
> de shell n'est pas grave, mais le réflexe de laisser du code de debug dans un fichier
> de démarrage finit par coûter cher : ces fichiers sont exécutés des milliers de fois
> par jour sur un bastion, et personne ne les relit jamais.

---

## 1.7 Break & Fix

### <a id="bf1-1"></a>**[BF1.1](README.md#bf1-1)** — « Plus aucune commande ne marche »

*Après reconnexion, toute commande répond `command not found`, y compris `sudo`.*

**Diagnostic pas à pas**

```bash
echo $PATH
# /opt/outils-maison/bin          <- une seule entrée, inexistante
```

`echo` fonctionne encore parce que c'est un **builtin** : il ne passe pas par le
`PATH`. C'est le premier indice, et il oriente immédiatement : si le shell répond
mais qu'aucun binaire ne se lance, le problème est le `PATH`, pas les permissions ni
le système de fichiers.

```bash
type -a ls        # bash: type: ls: not found   -> confirme
```

**Remise en service immédiate (session en cours)**

```bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
hash -r
ls /etc          # ça remarche
```

Si tu ne te souviens pas du `PATH` par défaut, il est dans `/etc/environment` :

```bash
while read -r ligne; do echo "$ligne"; done < /etc/environment
```

(`while read` est un builtin, il fonctionne sans `PATH`.)
Alternative en une commande, par chemin absolu : `/bin/cat /etc/environment`.

**Correction durable**

```bash
/usr/bin/vim ~/.bashrc
# repérer la ligne fautive :
#   export PATH=/opt/outils-maison/bin
# la remplacer par :
#   export PATH="/opt/outils-maison/bin:$PATH"
. ~/.bashrc
echo $PATH
```

**Pourquoi `sudo` était inaccessible**

`sudo` est `/usr/bin/sudo`, un exécutable comme les autres : sans `/usr/bin` dans le
`PATH`, bash ne le trouve pas. Ce n'est pas une question de droits. `/usr/bin/sudo`
en chemin absolu fonctionne parfaitement.

> [!NOTE]
> **Pourquoi**
>
> Le mécanisme : bash cherche une commande non qualifiée (sans `/`) uniquement dans les
> répertoires de `PATH`, dans l'ordre, et via sa table de hachage pour celles déjà
> exécutées. Écraser `PATH` au lieu d'y ajouter supprime tout accès aux binaires
> système. Les builtins (`cd`, `echo`, `export`, `read`, `type`, `hash`, `pwd`, `test`)
> restent disponibles : ce sont eux le canot de sauvetage, avec les chemins absolus.
>
> Le `hash -r` est important : après avoir réparé `PATH`, bash peut encore avoir en
> cache des chemins obsolètes ou avoir mémorisé des échecs. Le builtin vide la table.

> [!WARNING]
> **Piège**
>
> La prévention tient en une règle : **on n'écrit jamais `PATH=` sans `$PATH` dedans.**
> Toute ligne de la forme `export PATH=quelque_chose` sans référence à l'ancien `PATH`
> est un bug, sauf dans un script qui veut délibérément un environnement minimal — et
> dans ce cas elle doit énumérer explicitement `/usr/bin:/bin`.
>
> Deuxième prévention, valable pour tous les fichiers de démarrage : après modification,
> on ne se déconnecte **jamais** avant d'avoir validé dans une **seconde** session.
> Garde toujours une session SSH ouverte pendant que tu testes la nouvelle dans un
> autre terminal. C'est ce qui distingue une erreur de cinq secondes d'un déplacement
> en salle serveur.

---

### <a id="bf1-2"></a>**[BF1.2](README.md#bf1-2)** — « `df` raconte n'importe quoi sur tous les comptes »

*`df -h` affiche `usage: df [-h]` sur tous les comptes, mais `/bin/df -h` fonctionne.*

**Diagnostic pas à pas**

```bash
type -a df
# df is a function
# df ()
# {
#     echo "usage: df [-h]"
# }
# df is /usr/bin/df
# df is /bin/df
```

Une seule commande a suffi : `type -a` liste toutes les résolutions dans l'ordre, et
la fonction gagne toujours contre le fichier du `PATH`. `which df` aurait répondu
`/usr/bin/df` et envoyé sur une fausse piste.

**À quel niveau ?** Le symptôme touche tous les comptes, y compris root : ce n'est
donc ni `~/.bashrc`, ni `~/.profile`. Les candidats système sont `/etc/bash.bashrc`,
`/etc/profile` et `/etc/profile.d/*.sh`.

```bash
grep -rn 'df *()' /etc/profile /etc/profile.d/ /etc/bash.bashrc 2>/dev/null
# /etc/profile.d/zz-metrics.sh:3:df() {
```

**Exécuter la vraie commande malgré le masquage**

```bash
command df -h      # ignore alias et fonctions, garde les builtins
/usr/bin/df -h     # chemin absolu
env df -h          # env n'est pas bash, il ne connaît pas la fonction
```

(`\df` ne suffit **pas** : le backslash inhibe les alias, pas les fonctions.)

**Correctif**

```bash
sudo rm /etc/profile.d/zz-metrics.sh
# ou, si le fichier a une raison d'être, renommer la fonction :
sudo sed -i 's/^df()/metrics_df()/' /etc/profile.d/zz-metrics.sh

unset -f df        # retire la fonction de la session en cours
type -a df         # df is /usr/bin/df
```

Les sessions déjà ouvertes gardent la fonction jusqu'à `unset -f df` ou reconnexion :
un fichier de profil est lu une seule fois, au démarrage du shell.

> [!NOTE]
> **Pourquoi**
>
> Ordre de résolution d'une commande par bash :
>
> ```text
> alias -> mot réservé -> fonction -> builtin -> hachage -> PATH
> ```
>
> Une fonction prime sur un builtin, qui prime sur un fichier. C'est une fonctionnalité,
> pas un défaut : elle permet d'instrumenter une commande (journalisation, garde-fou)
> sans toucher au binaire. C'est aussi un vecteur d'attaque classique en escalade de
> privilèges, quand un script exécuté par root hérite d'un environnement où une
> fonction a été exportée avec `export -f`.
>
> Les trois échappatoires ne sont pas équivalentes :
>
> * `command df` saute alias et fonctions, mais **garde** les builtins. C'est la forme
>   à utiliser à l'intérieur d'une fonction qui porte le même nom que la commande
>   qu'elle enrobe, pour éviter la récursion infinie.
> * `\df` ou `'df'` n'inhibent que l'**alias**, parce que l'expansion d'alias
>   n'intervient que sur un mot non quoté. Sans effet sur une fonction.
> * le chemin absolu contourne tout, y compris les builtins.

> [!WARNING]
> **Piège**
>
> `/etc/profile.d/*.sh` n'est lu que par les shells de **login**. Un fichier fautif
> posé là ne se manifeste donc pas quand on tape `bash` dans une session existante,
> mais frappe à la prochaine connexion SSH, éventuellement des jours plus tard, et sur
> tous les comptes à la fois. Quand un symptôme est global et différé, c'est le premier
> répertoire à inspecter, avec `/etc/bash.bashrc` (lu, lui, par les shells interactifs
> non-login).

---

### <a id="bf1-3"></a>**[BF1.3](README.md#bf1-3)** — « Mes alias et mon prompt ont disparu en SSH »

*Prompt redevenu celui par défaut du système en SSH, alias absents, mais `bash` après connexion restaure tout. `~`*`/. bashrc` *est correct et ne doit pas être modifié.* (Sur Ubuntu, le prompt de repli est `mathieu@lab-adm:~$`, posé par `/etc/bash.bashrc` que `/etc/profile` source encore; sur Rocky, `/etc/profile` source de même `/etc/bashrc`, et on retombe sur `[mathieu@lab-rhel ~]$`.)

**Diagnostic pas à pas**

Le symptôme décrit lui-même la panne : ce qui change entre les deux situations, c'est
le **type de shell**. SSH ouvre un shell de login, `bash` ouvre un shell interactif
non-login. Le second lit `~/.bashrc`, le premier passe par les fichiers de profil.
Le problème est donc dans la chaîne de login.

```bash
ls -la ~/.bash_profile ~/.bash_login ~/.profile
# -rw-r--r-- 1 mathieu mathieu   87 sep 18 14:07 /home/mathieu/.bash_profile
# -rw-r--r-- 1 mathieu mathieu  807 mar 31  2024 /home/mathieu/.profile

cat ~/.bash_profile
# # ajout outillage interne - ne pas modifier
# export PATH="/opt/outils-maison/bin:$PATH"
```

Le fichier ne contient aucun appel à `~/.bashrc`.

**Correctif**

```bash
cat >> ~/.bash_profile <<'EOF'

# pont vers la configuration interactive
if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
EOF
```

Ou, si le contenu du fichier n'a pas de raison d'être séparé, déplacer la ligne
`export PATH` dans `~/.profile` et supprimer `~/.bash_profile`.

Vérification :

```bash
ssh mathieu@localhost
# le prompt personnalisé doit revenir immédiatement
```

**Règle générale à retenir**

Bash ne lit qu'**un seul** fichier de profil pour un shell de login : le premier
existant parmi `~/.bash_profile`, `~/.bash_login`, `~/.profile`. Dès que tu crées un
`~/.bash_profile`, tu deviens responsable de sourcer `~/.bashrc` toi-même. La
formule canonique est celle ci-dessus.

> [!NOTE]
> **Pourquoi**
>
> Ce n'est pas un défaut de conception, c'est le contrat historique : `.profile` est le
> fichier commun à tous les shells Bourne, `.bash_profile` est la version spécifique à
> bash. Bash préfère la version spécifique quand elle existe, comme `zsh` lit `. zprofile` et ignore `.profile`. Le mécanisme de « premier trouvé » évite qu'un utilisateur ayant
> les deux fichiers voie ses réglages appliqués deux fois.
>
> Le piège est aggravé par le fait que la panne est **asymétrique et différée** : un
> outil d'installation (agent de supervision, SDK, gestionnaire de versions) crée
> `~/.bash_profile` pour ajouter une ligne de `PATH`, personne ne remarque rien
> pendant la session en cours, et la configuration disparaît à la prochaine connexion.
> Les symptômes rapportés — « mon prompt a changé tout seul », « mes alias ont disparu »
> — ne mentionnent jamais l'installation faite trois jours plus tôt.
>
> Prévention : dans les scripts d'installation maison, ne jamais créer
> `~/.bash_profile`. Ajouter à `~/.profile` s'il existe, ou déposer un fichier dans
> `/etc/profile.d/` pour une modification système.

---

## 1.8 Défi du module

<a id="d1"></a>**[D1](README.md#d1) — Audit et durcissement de l'environnement shell**

*Écrire `~/bin/audit-shell.sh`, portable Ubuntu/Rocky, produisant un rapport
Markdown sur stdout, signalant cinq anomalies et sortant en 1 si l'une est présente.*

```bash
#!/usr/bin/env bash
# audit-shell.sh — audit de l'environnement shell de l'utilisateur courant
# Rapport Markdown sur stdout, diagnostic sur stderr, 0 = RAS, 1 = anomalies.
set -euo pipefail

ANOMALIES=()
note() { ANOMALIES+=("$1"); }
log()  { printf '[audit] %s\n' "$1" >&2; }

# --- 1. identité du shell ---------------------------------------------
log "collecte des informations de shell"
SH_REEL=$(readlink -f /bin/sh)
case "$-" in *i*) INTERACTIF=oui ;; *) INTERACTIF=non ;; esac
case "$0" in -*) LOGIN=oui ;; *) LOGIN=non ;; esac

printf '# Audit shell — %s@%s\n\n' "${USER:-$(id -un)}" "$(hostname -s)"
printf 'Date : %s\n\n' "$(date '+%F %T')"

printf '## Shell\n\n'
printf -- '- shell courant : `%s`\n' "${SHELL:-inconnu}"
printf -- '- version bash : `%s`\n' "${BASH_VERSION:-non bash}"
printf -- '- /bin/sh pointe sur : `%s`\n' "$SH_REEL"
printf -- '- interactif : %s (preuve : $- = `%s`)\n' "$INTERACTIF" "$-"
printf -- '- login : %s (preuve : $0 = `%s`)\n\n' "$LOGIN" "$0"

# --- 2. fichiers de démarrage -----------------------------------------
printf '## Fichiers de démarrage\n\n'
for f in /etc/profile /etc/bash.bashrc "$HOME/.bash_profile" \
         "$HOME/.bash_login" "$HOME/.profile" "$HOME/.bashrc"; do
  if [ -f "$f" ]; then
    printf -- '- `%s` — %s octets\n' "$f" "$(stat -c %s "$f")"
  fi
done
printf '\n'

if [ -f "$HOME/.bash_profile" ] &&
   ! grep -qE '(^|[^#])[.[:space:]]+.*\.bashrc|source.*\.bashrc' \
        "$HOME/.bash_profile"; then
  note '`~/.bash_profile` existe mais ne source pas `~/.bashrc`'
fi

# --- 3. PATH -----------------------------------------------------------
printf '## PATH\n\n'
# le ':' ajouté fait apparaître une entrée vide finale (PATH=/usr/bin:)
IFS=':' read -ra PARTS <<< "$PATH:"
for d in "${PARTS[@]}"; do
  if [ -z "$d" ]; then
    printf -- '- `(vide)` — **entrée vide = répertoire courant**\n'
    note 'entrée vide dans PATH (équivaut à `.`)'
  elif [ "$d" = "." ]; then
    printf -- '- `.` — **répertoire courant**\n'
    note '`.` présent dans PATH'
  elif [ -d "$d" ]; then
    printf -- '- `%s` — existe\n' "$d"
  else
    printf -- '- `%s` — **inexistant**\n' "$d"
    note "répertoire inexistant dans PATH : $d"
  fi
done
printf '\n'

# --- 4. masquages -------------------------------------------------------
# Un script exécuté n'hérite ni des alias ni des fonctions du shell
# appelant : on interroge un shell de login interactif pour les obtenir.
NOMS=$(bash -lic 'alias -p; declare -F' 2>/dev/null |
       sed -n -e 's/^alias \([^=]*\)=.*/\1/p' \
              -e 's/^declare -f[a-zA-Z]* //p' | sort -u)

printf '## Alias et fonctions masquant une commande du PATH\n\n'
MASQUES=0
while read -r nom; do
  [ -n "$nom" ] || continue
  cible=$(PATH="$PATH" command -v -- "$nom" 2>/dev/null) || continue
  case "$cible" in
    /*) printf -- '- `%s` masque `%s`\n' "$nom" "$cible"
        MASQUES=$((MASQUES+1)) ;;
  esac
done <<< "$NOMS"
[ "$MASQUES" -eq 0 ] && printf 'Aucun.\n'
printf '\n'

# --- 5. réglages --------------------------------------------------------
# Même problème : HISTSIZE et consorts ne sont pas exportés. Si la
# variable n'est pas visible ici, on la lit dans un shell de login
# interactif, qui est l'environnement que l'utilisateur voit vraiment.
vue() {
  local v="${!1:-}"
  if [ -n "$v" ]; then printf '%s' "$v"
  else bash -lic "printf %s \"\${$1:-}\"" 2>/dev/null; fi
}
opt() {
  if shopt -q "$1" || bash -lic "shopt -q $1" 2>/dev/null
  then echo on; else echo off; fi
}

HC=$(vue HISTCONTROL); HA=$(opt histappend); CW=$(opt checkwinsize)

printf '## Réglages\n\n'
printf -- '- HISTSIZE = `%s`\n'       "$(vue HISTSIZE)"
printf -- '- HISTFILESIZE = `%s`\n'   "$(vue HISTFILESIZE)"
printf -- '- HISTCONTROL = `%s`\n'    "$HC"
printf -- '- HISTTIMEFORMAT = `%s`\n' "$(vue HISTTIMEFORMAT)"
printf -- '- EDITOR = `%s`\n'         "$(vue EDITOR)"
printf -- '- PAGER = `%s`\n'          "$(vue PAGER)"
printf -- '- histappend : %s\n'       "$HA"
printf -- '- checkwinsize : %s\n\n'  "$CW"

case "$HC" in
  *ignorespace*|*ignoreboth*) ;;
  *) note 'HISTCONTROL ne contient pas ignorespace' ;;
esac
[ "$HA" = on ] || note 'histappend désactivé'

# --- 6. synthèse --------------------------------------------------------
printf '## Anomalies\n\n'
if [ "${#ANOMALIES[@]}" -eq 0 ]; then
  printf 'Aucune anomalie détectée.\n'
  log "0 anomalie"
  exit 0
fi
for a in "${ANOMALIES[@]}"; do printf -- '- %s\n' "$a"; done
log "${#ANOMALIES[@]} anomalie(s)"
exit 1
```

Génération du livrable :

```bash
chmod +x ~/bin/audit-shell.sh
~/bin/audit-shell.sh > ~/lab01/audit-lab-adm.md   # stderr reste à l'écran
echo "code=$?"
bash check_M01_05.sh
```

> [!NOTE]
> **Pourquoi**
>
> Les décisions de conception qui font la valeur de ce script :
>
> **Séparation stdout / stderr.** Le rapport part sur stdout, la trace de diagnostic
> sur stderr via `log()`. C'est ce qui rend `audit-shell.sh > rapport.md` utilisable
> tel quel : la redirection ne capture que le Markdown, et tu continues de voir la
> progression à l'écran. C'est la convention Unix de base, et elle vaut pour tout
> script d'exploitation.
>
> **`$-` pour l'interactivité, `$0` pour le login.** Ce sont les deux seules preuves
> fiables. `$-` contient les options du shell, dont `i` si interactif. Un shell de
> login est lancé avec un `argv[0]` commençant par un tiret (`-bash`), convention
> héritée de `login(1)` ; `case "$0" in -*)` la teste. `shopt -q login_shell` est
> l'équivalent bash, plus lisible mais non portable.
>
> `IFS=':' read -ra PARTS <<< "$PATH:"` découpe proprement, y compris les entrées
> vides (`PATH=/usr/bin::/bin` contient une entrée vide, qui vaut `.` et constitue la
> même faille). Le `:` ajouté en fin de chaîne est nécessaire : `read` supprime un champ vide final, et `PATH=/usr/bin:` passerait sinon inaperçu. Un `for d in ${PATH//:/ }` casserait sur un répertoire contenant une
> espace.
>
> **`command -v` pour détecter les masquages.** Pour chaque alias et chaque fonction,
> on demande à `command -v` ce que le nom résout dans le `PATH` ; le `case "$cible" in
> /*)` ne retient que les cibles absolues, c'est-à-dire les noms pour lesquels un vrai
> fichier exécutable existe. Un alias `ll` ne masque rien (aucun binaire `ll` n'existe),
> mais un alias `ls` ou une fonction `df` masquent une commande réelle, et c'est
> exactement ce qu'on veut signaler — c'est la panne BF1.2 détectée automatiquement.
>
> **`set -euo pipefail` avec un tableau d'anomalies.** Sous `set -u`, un tableau vide
> posait problème dans les bash antérieurs à 4.4 ; sur Ubuntu 24.04 (bash 5.2) et
> Rocky 9 (bash 5.1), `"${ANOMALIES[@]}"` sur un tableau vide est sûr. Le code retour
> 1 en cas d'anomalie rend le script utilisable directement en CI ou dans un job
> Ansible.

> [!WARNING]
> **Piège**
>
> Le piège central du défi, et la raison pour laquelle la plupart des copies
> rendent un rapport faux : **un script exécuté n'hérite ni des alias, ni des
> fonctions, ni des variables de shell non exportées** de la session qui le lance.
> Un `audit-shell.sh` naïf rapporte donc `HISTCONTROL = non défini`, `histappend :
> off` et « aucun alias masquant » sur une machine parfaitement configurée. Il ne
> décrit pas ton environnement, il décrit le sien.
>
> Trois issues possibles, par ordre de qualité croissante :
>
> * **sourcer** le script (`. ~/bin/audit-shell.sh`) : il s'exécute alors dans ta
>   session et voit tout — mais chaque `exit` ferme ton terminal. Il faudrait
>   remplacer les `exit` par un `return` quand `[ "${BASH_SOURCE[0]}" != "$0" ]` ;
> * **exporter** les variables à auditer : ça fausse justement ce qu'on mesure ;
> * **interroger un shell de login interactif** (`bash -lic`), comme le font les
>   fonctions `vue()` et `opt()` ci-dessus. Le script reste exécutable normalement,
>   redirigeable, utilisable en CI, et rapporte l'environnement réel de
>   l'utilisateur. C'est la solution retenue.
>
> Limite qui subsiste, à assumer dans le livrable : le script décrit l'environnement
> **d'une session de login**, pas celui de cron ni celui d'un service systemd. Pour
> auditer celui de cron, il faut le lancer depuis cron, ou simuler son dépouillement
> avec `env -i /bin/bash --noprofile --norc ~/bin/audit-shell.sh`.

<!-- nav:début -->
---

[Énoncé](README.md) · [Module 02 →](../02-filesystem-fhs/corrige.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
