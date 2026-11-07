# Module 07 — Corrigé

## 7.3 Quiz — QCM

**Q7.1** — *`compte "$@"` puis `compte "$*"`, appelé avec `un "deux trois"`.*

**Réponse : b) `2` puis `1`**

::: pourquoi
`"$@"` et `"$*"` contiennent les mêmes caractères, mais bash ne les découpe pas
pareil, et c'est le découpage qui décide de ce que reçoit le programme appelé.

* `"$@"` est développé en **autant de mots que d'arguments**, chacun conservant
  son quoting d'origine : `compte` reçoit `argv = [compte, un, deux trois]`,
  donc `$#` vaut 2.
* `"$*"` est développé en **un seul mot**, obtenu en joignant les arguments avec
  le premier caractère d'`IFS` (une espace par défaut) : `compte` reçoit
  `argv = [compte, "un deux trois"]`, donc `$#` vaut 1.

C'est la seule construction de bash qui produit plusieurs mots à partir d'une
expansion **quotée** ; elle est là exactement pour ça.
:::

::: piege
Sans quotes, `$@` et `$*` sont strictement équivalents : tous deux subissent le
découpage de mots, et `deux trois` devient deux arguments. Un script qui fait
`autre-script $@` semble fonctionner jusqu'au jour où un chemin contient une
espace. La règle tient en un caractère : **`"$@"`, toujours avec les quotes**.
L'exception légitime est le message de journal, où l'on veut une seule chaîne :
`log_info "$*"`.
:::

---

**Q7.2** — *`set -e` sans `pipefail`, `grep -q ... | tee` où grep échoue.*

**Réponse : b)** `on continue` est affiché, le script poursuit.

::: pourquoi
`set -e` déclenche l'arrêt sur le code de retour de la **commande**, et le code
de retour d'un pipeline est par définition celui de son **dernier** étage.
Ici `grep` sort en 1, mais `tee` sort en 0 : le pipeline sort en 0, `set -e`
n'a rien à signaler.

`set -o pipefail` change cette définition : le pipeline prend le code du
**dernier étage qui a échoué**, et le script s'arrête alors comme attendu. Pour
savoir *quel* étage a fauté, seul `${PIPESTATUS[@]}` répond :

```bash
tar -cf - /srv | gzip > a.gz
echo "${PIPESTATUS[@]}"      # ex. « 2 0 » : tar a échoué, gzip non
```
:::

::: piege
C'est le mécanisme exact de BF7.2. Il frappe surtout les pipelines de
sauvegarde (`tar | gzip`, `mysqldump | gzip`, `pg_dump | ssh`), où le producteur
échoue et le consommateur écrit joyeusement un fichier tronqué. Une sauvegarde
qui « réussit » tous les jours pendant six mois et se révèle vide le jour de la
restauration, c'est presque toujours cette ligne-là.
:::

---

**Q7.3** — *Avec `set -u`, quelles formes échouent si `CIBLE` n'est pas définie ?*

**Réponses : b) et c)**

```console
$ bash -c 'set -u; echo "${CIBLE:-/srv/defaut}"'   # OK  -> /srv/defaut
$ bash -c 'set -u; echo "$CIBLE"'
bash: CIBLE: unbound variable
$ bash -c 'set -u; echo "${CIBLE:?obligatoire}"'   # bash: CIBLE: obligatoire
$ bash -c 'set -u; echo "${CIBLE:+actif}"'         # OK  -> (ligne vide)
```

::: pourquoi
`set -u` fait échouer toute référence à une variable **non définie**, sauf
lorsque la substitution fournit elle-même une valeur de repli : `${v:-def}` et
`${v:+x}` sont des expressions complètes, elles ne « lisent » pas une variable
manquante, elles calculent un résultat.

`${v:?msg}` échoue **volontairement** : c'est l'assertion de pré-condition la
plus courte de bash. `: "${CIBLE:?cible obligatoire}"` en tête de script remplace
dix lignes de `if [ -z ... ]`.
:::

::: piege
`set -u` ne protège **pas** contre une variable définie mais **vide** :
`CIBLE=""` passe sans broncher, et `rm -rf "$CIBLE/"` devient `rm -rf /`.
Seules les formes à deux-points (`:-`, `:=`, `:?`, `:+`) traitent « vide » et
« non défini » de la même façon. Sans deux-points (`${v-def}`), seule l'absence
compte.
:::

---

**Q7.4** — *`f=""` puis `if [ -n $f ]`.*

**Réponse : b)** `non vide`, parce que `$f` non quoté disparaît et `[ -n ]`
teste la chaîne `-n`.

::: pourquoi
`[` est une **commande** qui reçoit des arguments. Bash développe `$f` en une
chaîne vide non quotée, qui est ensuite éliminée par le découpage de mots : il
ne reste rien du tout. `[` reçoit donc `argv = [ "[", "-n", "]" ]`, c'est-à-dire
un test à **un seul argument**.

POSIX est formel : `test` avec un seul argument est vrai si cet argument est une
chaîne non vide. `-n` est une chaîne non vide, donc le test est vrai. Ce n'est
pas un bug, c'est la conséquence mécanique du découpage des mots.
:::

::: piege
La forme correcte est `[ -n "$f" ]`, ou `[[ -n $f ]]`. Dans `[[ ]]`, les
variables ne subissent ni découpage ni globbing : le mot-clé reçoit la
construction syntaxique, pas une liste d'arguments. C'est pourquoi `[[ ]]` est
beaucoup plus difficile à casser — et pourquoi il faut quand même quoter dans
`[ ]`, qui reste la seule forme disponible en `#!/bin/sh`.
:::

---

**Q7.5** — *Compteur incrémenté dans un `while read` à droite d'un pipe.*

**Réponse : b) 0**

::: pourquoi
Chaque étage d'un pipeline s'exécute dans un **sous-shell**, c'est-à-dire un
processus fils. La boucle `while` incrémente donc `n` dans un autre processus
que celui qui exécutera le `echo` final. À la fin du pipeline, le sous-shell
meurt et emporte ses variables : le shell parent n'a jamais vu `n` changer, il
affiche la valeur initiale, 0.

Trois façons correctes d'écrire ça :

```bash
n=$(grep -c ERROR fichier)                       # le plus simple
while read -r l; do n=$((n+1)); done < <(grep ERROR f)   # subst. de processus
shopt -s lastpipe                                 # bash, hors mode interactif
```
:::

::: piege
Le symptôme trompe : la boucle fonctionne, les `echo` à l'intérieur affichent
les bonnes valeurs, seul le résultat final est faux. C'est un des rares cas où
l'on peut « voir » le sous-shell : ajoute `echo "dedans: $BASHPID"` dans la
boucle et `echo "dehors: $BASHPID"` après, les PID diffèrent.
:::

---

**Q7.6** — *`local taille=$(du -sb "$1" | cut -f1)` puis `return $?`.*

**Réponse : b)** `$?` contient le code de `local`, toujours 0.

::: pourquoi
`local` (comme `declare`, `export`, `readonly`, `typeset`) est une **commande**
à part entière. Bash évalue d'abord la substitution de commande, puis exécute
`local` avec le résultat. Le code de retour visible dans `$?` est donc celui de
`local` — qui échoue seulement si on l'appelle hors d'une fonction. L'échec de
`du` ou de `cut` est purement et simplement perdu, et `set -e` ne voit rien non
plus.

```console
$ f(){ local t=$(false); echo "apres local: $?"; }; f
apres local: 0
$ g(){ local t; t=$(false); echo "declare puis affecte: $?"; }; g
declare puis affecte: 1
```

La règle : **déclarer d'abord, affecter ensuite**, dès que la valeur vient d'une
substitution de commande. C'est exactement ce que signale `SC2155` de
shellcheck.
:::

---

**Q7.7** — *`tar | gzip` avec `set -euo pipefail`, `tar` échoue.*

**Réponse : a)** le script s'arrête, le pipeline sort en 2.

::: pourquoi
Avec `pipefail`, le code du pipeline devient celui du dernier étage à avoir
échoué — ici `tar`, qui sort en 2 sur une erreur de lecture. `set -e` voit un
code non nul et arrête le script. Sans `pipefail`, on retombe sur Q7.2.

La proposition c) inverse les indices : `PIPESTATUS` est ordonné **de gauche à
droite**, donc `${PIPESTATUS[0]}` est le code de `tar` (2) et
`${PIPESTATUS[1]}` celui de `gzip` (0). Attention, `PIPESTATUS` est écrasé par
la commande suivante : copie-le tout de suite si tu en as besoin
(`codes=("${PIPESTATUS[@]}")`).
:::

---

**Q7.8** — *8 fichiers dont un au nom à espace : itérations de `$(ls)` et du glob.*

**Réponse : b) A = 9, B = 8**

::: pourquoi
`for f in $(ls ...)` : la substitution de commande produit une seule chaîne
contenant tous les noms séparés par des sauts de ligne. Cette chaîne n'étant pas
quotée, elle subit le **découpage de mots** sur `$IFS`, qui contient l'espace :
`rapport final.log` devient deux mots. D'où 9 itérations pour 8 fichiers — et,
pire, deux itérations sur des noms de fichiers qui n'existent pas.

`for f in rep/*` : le **globbing** produit directement une liste de mots, un par
nom de fichier, et cette liste n'est **jamais** re-découpée. Le globbing a lieu
après le découpage de mots dans l'ordre des expansions, ce qui le rend immunisé.
D'où 8 itérations, correctes, quels que soient les noms.
:::

::: piege
Le glob a deux défauts à connaître : il inclut le chemin (`rep/nom`, d'où
`${f##*/}` pour le basename) et, si aucun fichier ne correspond, il est passé
**littéralement** (`rep/*.log`) au lieu de produire une liste vide. D'où
`shopt -s nullglob` dans les scripts sérieux. Pour une descente récursive ou des
critères (âge, taille), c'est `find ... -print0` avec
`while IFS= read -r -d ''` qui prend le relais.
:::

---

**Q7.9** — *Afficher les clés d'un tableau associatif.*

**Réponse : b) `echo "${!par_env[@]}"`**

::: pourquoi
Le `!` devant un nom de tableau demande les **indices** (ou les clés pour un
tableau associatif) plutôt que les valeurs. `${par_env[@]}` donne les valeurs
(`4 1`), `${#par_env[@]}` le nombre d'éléments (2), et `${!par_env[@]}` les clés
(`dev prod`, dans un ordre de hachage non garanti — trie si tu veux une sortie
stable).

Le patron canonique du comptage par catégorie :

```bash
declare -A par_env
par_env["$env"]=$(( ${par_env["$env"]:-0} + 1 ))     # :-0 pour le 1er passage
for e in $(printf '%s\n' "${!par_env[@]}" | sort); do
  printf '%s;%s\n' "$e" "${par_env[$e]}"
done
```
:::

::: piege
`declare -A` est **obligatoire** avant usage : sans lui, `par_env[prod]=4`
crée un tableau **indexé** et `prod` est évalué comme une expression
arithmétique, qui vaut 0. Tout finit alors dans la case 0 et le compteur est
faux sans le moindre message d'erreur.
:::

---

**Q7.10** — *`trap ... EXIT` puis Ctrl-C pendant l'exécution.*

**Réponse : b)** le répertoire est supprimé.

::: pourquoi
Le pseudo-signal `EXIT` se déclenche à **chaque** sortie du shell : fin normale,
`exit` explicite, arrêt par `set -e`, et aussi terminaison provoquée par un
signal non intercepté. Bash exécute le gestionnaire `EXIT` avant de rendre la
main. Un `trap 'rm -rf "$TRAVAIL"' EXIT` couvre donc Ctrl-C sans qu'on ait à
piéger `INT` explicitement.

On intercepte tout de même `INT` et `TERM` séparément quand on veut faire plus
que nettoyer : journaliser l'interruption, tuer un processus fils, ou sortir
avec le code conventionnel `130` / `143` (`128 + n`) au lieu du code par défaut.
:::

::: piege
Deux limites réelles. D'abord `SIGKILL` (`kill -9`) ne déclenche **rien** : le
processus est supprimé par le noyau, aucun trap ne tourne. Ensuite, si tu
interceptes `INT` toi-même et que tu sors par `exit`, le trap `EXIT` se déclenche
**aussi** : d'où le `trap - EXIT` avant d'appeler le nettoyage à la main, si tu
ne veux pas nettoyer deux fois.
:::

---

**Q7.11** — *Le deux-points en tête de `getopts ':d:s:vh'`.*

**Réponse : b)** les erreurs sont silencieuses, à toi de traiter `?` et `:`.

::: pourquoi
En mode « silencieux », `getopts` n'écrit plus ses propres messages
`illegal option` sur stderr. À la place :

* option inconnue → `opt` vaut `?` et `OPTARG` contient la lettre fautive ;
* argument manquant → `opt` vaut `:` et `OPTARG` contient la lettre concernée.

Tu contrôles alors entièrement le message, sa destination (stderr) et le code de
sortie (2 par convention) :

```bash
while getopts ':d:s:vh' opt; do
  case "$opt" in
    d) REP=$OPTARG ;;
    :)  log_error "option -$OPTARG : argument manquant"; exit 2 ;;
    \?) log_error "option inconnue : -$OPTARG";          exit 2 ;;
  esac
done
shift $((OPTIND - 1))
```

Le `shift $((OPTIND - 1))` final est obligatoire : il retire les options
traitées pour que `"$@"` ne contienne plus que les arguments positionnels.
:::

::: piege
`getopts` ne connaît **pas** les options longues : `--verbose` lui apparaît
comme l'option `-` suivie de bruit. Dès qu'il te faut `--dry-run`, c'est parsing
manuel `while [ $# -gt 0 ]; do case "$1" in ... shift ...` — et le `shift` dans
**chaque** branche, sinon boucle infinie (BF7.3).
:::

---

**Q7.12** — *`charge="4.00"` puis `[ "$charge" -gt 2 ]`.*

**Réponse : b)** message `integer expression expected` sur stderr, test faux.

::: pourquoi
`-eq`, `-ne`, `-lt`, `-le`, `-gt`, `-ge` sont des comparateurs d'**entiers**.
`4.00` n'est pas un entier pour bash, qui n'a pas de type flottant. `test`
signale l'erreur sur stderr et renvoie **2** — ni 0 ni 1. Comme `if` ne teste
que « zéro ou pas zéro », la branche `then` n'est pas prise : le script continue
avec un test silencieusement faux, et un message d'erreur qui finit souvent dans
`/dev/null`.

Pour comparer des chaînes, `=` et `!=` (ou `==` dans `[[ ]]`). Pour comparer des
décimaux, il faut sortir de bash :

```bash
awk -v a="$charge" -v b=2 'BEGIN{ exit !(a > b) }' && echo "dépassement"
```
:::

::: piege
Le cousin du même piège : `[ "$mois" -eq 9 ]` avec `mois=09` fonctionne dans
`test`, mais `$((09 + 1))` échoue avec `value too great for base` parce que le
zéro initial fait basculer en octal. `10#$mois` force la base 10.
:::

---

**Q7.13** — *`f="factura-2026-09-18.tar.gz"`, que vaut `${f%%.*}` ?*

**Réponse : b) `factura-2026-09-18`**

::: pourquoi
`%` coupe un **suffixe**, `#` coupe un **préfixe** ; doubler le caractère
demande la correspondance la plus **longue** au lieu de la plus courte.
Le motif `.*` se lit ici comme un glob (point suivi de n'importe quoi), pas
comme une regex.

```bash
f=factura-2026-09-18.tar.gz
echo "${f%.*}"    # factura-2026-09-18.tar   (plus court suffixe)
echo "${f%%.*}"   # factura-2026-09-18       (plus long suffixe)
echo "${f#*.}"    # tar.gz                   (plus court préfixe)
echo "${f##*.}"   # gz                       (plus long préfixe)
```

Moyen mnémotechnique : sur un clavier, `#` est à gauche de `%`, comme le préfixe
est à gauche du suffixe.
:::

::: piege
`${f%%.*}` sur un chemin complet coupe trop : `/var/log/nginx/access.log.1`
devient `/var/log/nginx/access`. Prends d'abord le basename avec `${f##*/}`,
puis retire l'extension. Et si le nom ne contient pas le motif, la substitution
rend la chaîne **inchangée** — pas une chaîne vide.
:::

---

**Q7.14** — *Comment une fonction rend-elle une valeur calculée ?*

**Réponses : b) et c)**

::: pourquoi
Une fonction bash a deux canaux, et ils n'ont pas le même rôle :

* le **code de retour** (`return`), un entier de 0 à 255, qui répond à « ça
  s'est bien passé ? » et alimente `$?`, `if`, `&&`, `||` ;
* la **sortie standard**, qui porte le **résultat** et se récupère par
  substitution de commande : `res=$(fonction)`.

La variante c) — la fonction écrit dans une variable dont l'appelant a choisi le
nom (`declare -n` ou une globale convenue) — est plus rapide (pas de sous-shell)
et permet de rendre un tableau, ce que stdout ne sait pas faire proprement.

a) est faux dès que la valeur dépasse 255 ou n'est pas un entier : `return 300`
donne 44 (300 modulo 256). d) est pire : `exit` termine le script entier.
:::

::: piege
`res=$(fonction)` crée un sous-shell : tout ce que la fonction modifie
(variables, `cd`) est perdu au retour. Le code, lui, est bien transmis — sauf si
l'affectation est préfixée par `local` ou `declare`, qui imposent alors le leur
(Q7.6). Pour traiter les deux explicitement : `res=$(fonction) || rc=$?`.
:::

---

**Q7.15** — *Le script tenant `flock -n 9` est tué par `kill -9`.*

**Réponse : b)** le noyau libère le verrou à la fermeture du descripteur.

::: pourquoi
`flock(2)` pose un verrou consultatif **associé à la description de fichier
ouverte**, pas au fichier lui-même ni à son contenu. Le verrou disparaît quand
la dernière référence à cette description est fermée — ce que le noyau fait
d'office quand le processus meurt, y compris sur `SIGKILL`, y compris sur une
coupure de courant côté processus. Il n'y a donc **rien à nettoyer** : le
fichier de verrou peut rester en place indéfiniment, il ne bloque personne.

C'est toute la supériorité sur le « fichier PID » : un PID écrit dans
`/var/run/monscript.pid` survit à la mort du processus, et le script suivant
refuse de démarrer jusqu'à intervention humaine — ou, pire, teste un PID qui a
été recyclé par un processus sans rapport.
:::

::: piege
Le verrou est hérité par les **fils** : si ton script lance
`( exec 9>lock; flock -n 9 && sleep 3600 )`, tuer le shell ne libère rien tant
que le `sleep` vit, puisqu'il détient une copie du descripteur. C'est la cause
classique du « verrou fantôme » : cherche les processus fils avec
`fuser -v fichier.lock` ou `lsof fichier.lock` avant d'accuser flock.
:::

---

**Q7.16** — *`while read ligne` sur la ligne `  admin\test  `.*

**Réponse : c) `[admintest]`**

::: pourquoi
Deux mécanismes distincts frappent la même ligne.

1. `read` découpe la ligne selon `IFS` et **supprime les blancs de tête et de
   fin** avant d'affecter. Les deux espaces au début et à la fin disparaissent.
2. Sans `-r`, `read` traite l'antislash comme un caractère d'échappement :
   `\t` devient un `t` littéral, l'antislash est consommé.

D'où `admintest`. La forme canonique neutralise les deux :

```bash
while IFS= read -r ligne; do printf '[%s]\n' "$ligne"; done < creds.txt
```

`IFS=` (vide, en préfixe de commande, donc seulement pour ce `read`) désactive
le découpage et la suppression des blancs ; `-r` rend l'antislash littéral.
:::

::: piege
Sur des mots de passe ou des chemins, cette double mutilation est
catastrophique et silencieuse : l'authentification échoue « sans raison ».
Retiens `while IFS= read -r ligne` comme un bloc indivisible, au même titre que
`#!/usr/bin/env bash`.
:::

---

**Q7.17** — *`cd /srv/app` puis `rm -rf ./cache`, le répertoire a été renommé.*

**Réponse : b)** `cd` échoue, le script continue et supprime `./cache` là où il
se trouve.

::: pourquoi
Sans `set -e`, l'échec d'une commande n'interrompt rien : bash affiche
`bash: cd: /srv/app: No such file or directory` sur stderr et passe à la ligne
suivante. Le répertoire courant est resté celui du lancement — le `$HOME` de
l'utilisateur, `/` pour un service, ou n'importe quoi en automatique. `rm -rf
./cache` s'exécute donc **ailleurs**, et le fait sans se plaindre s'il trouve
une victime.

Les trois écritures sûres :

```bash
cd /srv/app || exit 3
cd /srv/app || { echo "répertoire absent" >&2; exit 3; }
pushd /srv/app >/dev/null || exit 3   # ... popd à la fin
```

C'est le sens de `SC2164` (« Use `cd ... || exit` in case `cd` fails »).
:::

::: piege
`set -e` sauve ce cas précis, mais pas si le `cd` est dans une condition
(`if cd /srv/app; then`) ou suivi de `&&`. Et il ne sauve rien du tout si le
`cd` **réussit** vers un répertoire inattendu, par exemple parce que `$APP` est
vide et que `cd /srv/$APP` t'envoie dans `/srv`. La vraie garde est de
travailler en **chemins absolus** : `rm -rf -- "$APP_DIR/cache"` avec `APP_DIR`
validé, plutôt que `cd` + chemin relatif.
:::

---

**Q7.18** — *Faire définir `PROXY` dans le shell interactif courant.*

**Réponses : c) et d)**

::: pourquoi
`source fichier` et son synonyme POSIX `. fichier` font lire le fichier **par le
shell courant** : aucune création de processus, donc les variables, fonctions,
alias, `cd` et même `exit` affectent ta session.

`./env.sh` et `bash env.sh` lancent un **processus fils**. Un fils hérite de
l'environnement de son père, jamais l'inverse : ses variables meurent avec lui.
C'est ce qui explique pourquoi les scripts d'activation d'environnement
(`. venv/bin/activate`, `. /etc/profile.d/proxy.sh`) se sourcent toujours.

| Invocation | Processus | Shebang | / bit `x` | Effet sur le shell |
|---|---|---|---|---|
| `./s.sh` | fils | requis / | requis | aucun |
| `bash s.sh` | fils | ignoré / | inutile | aucun |
| `source s.sh` | courant | ignoré / | inutile | total |
:::

::: piege
Sourcer un script écrit pour être exécuté est dangereux : chaque `exit` ferme
**ta session**, chaque `set -e` devient permanent, chaque `cd` te déplace. Un
script destiné à être sourcé ne contient ni `exit` ni `set -e`, et se protège
souvent par `return 1` (qui n'est légal que dans une fonction ou un fichier
sourcé — c'est d'ailleurs le test le plus simple pour savoir comment on a été
appelé : `(return 0 2>/dev/null) && echo "sourcé" || echo "exécuté"`).
:::

---

## 7.4 Quiz — questions ouvertes

**QO7.1** — *`"$@"`, `$@`, `"$*"`, `$*` : différences et dégât en production.*

**Réponse de référence**

| Forme | Résultat | Nombre de mots |
|---|---|---|
| `"$@"` | chaque argument, quoting préservé | `$#` |
| `$@` | chaque argument, puis **re-découpé** sur `$IFS` | ≥ `$#` |
| `"$*"` | tous les arguments joints par `${IFS:0:1}` | 1 |
| `$*` | la même chaîne, puis re-découpée | ≥ 1 |

Le cas de production : une enveloppe de déploiement qui relaie ses arguments.

```bash
# deploy.sh --fichier "conf de secours.ini" --env recette
"$HOOK" $*        # le hook reçoit 4 arguments : conf, de, secours.ini, recette
"$HOOK" "$@"      # le hook reçoit 2 arguments, corrects
```

Avec `$*`, le hook copie un fichier nommé `conf`, n'échoue pas forcément (il
peut exister), et le déploiement part avec le mauvais contenu. Rien dans les
journaux ne le signale : les deux exécutions « réussissent ».

::: pourquoi
Le point à retenir pour l'entretien : `"$@"` est la **seule** expansion quotée de
bash qui produit plusieurs mots. Le shell la traite comme un cas spécial
précisément pour permettre de relayer une ligne de commande sans la dénaturer.
Tout le reste (`$@`, `$*`, `${arr[*]}`) repasse par le découpage de mots.
:::

---

**QO7.2** — *`set -euo pipefail` suffit-il ? Trois trous et leurs bouchons.*

**Réponse de référence**

**1. `set -e` est désactivé dans tout contexte de test.** Une commande qui
échoue dans un `if`, un `while`, après `&&`, `||` ou `!` n'arrête rien — et la
règle se propage : **toute fonction appelée depuis une condition perd `set -e`
pour l'intégralité de son corps**.

```bash
verifier() { faux_binaire; rm -rf "$CACHE"; }   # exécuté malgré l'échec
if verifier; then ...                            # set -e neutralisé ici
```

Bouchon : tester explicitement (`cmd || mourir 1 "..."`), ajouter
`trap '...' ERR`, ne pas mettre de logique destructive dans une fonction
appelée en condition.

**2. `set -u` ne voit que l'absence, pas le vide.** `CIBLE=""` puis
`rm -rf "$CIBLE/"` passe. Bouchon : `: "${CIBLE:?cible obligatoire}"`, plus une
validation métier (`[ -d "$CIBLE" ]`, préfixe attendu).

**3. `pipefail` ne dit pas quel étage a échoué**, et ne couvre pas les
substitutions de commande masquées (`local x=$(cmd)`), ni `cmd &` suivi d'un
`wait` non testé. Bouchon : `${PIPESTATUS[@]}`, déclaration séparée de
l'affectation, `wait "$pid" || rc=$?`.

::: pourquoi
Ce qu'on attend d'un candidat, ce n'est pas la récitation des trois options,
c'est de savoir qu'elles sont un **filet**, pas une ceinture de sécurité. Le
script robuste ajoute : des pré-conditions explicites, un `trap EXIT` qui
nettoie, des codes de sortie documentés, un verrou d'exécution unique, et
l'idempotence. C'est tout le programme de D7.
:::

::: piege
Deux effets de bord de `set -e` qui surprennent en revue : `((i++))` renvoie 1
quand `i` valait 0 (l'arithmétique rend le code de la valeur), ce qui arrête le
script — écris `((i++)) || true` ou `i=$((i+1))`. Et `set -e` ne s'applique pas
au corps d'une fonction dont l'appel est suivi de `|| true`.
:::

---

**QO7.3** — *`[ ]` vs `[[ ]]` vs `(( ))`.*

**Réponse de référence**

* `[ ]` est un **builtin POSIX** (et un vrai binaire, `/usr/bin/[`). Il reçoit
  des **arguments** : tout ce qui n'est pas quoté est découpé et globé avant
  qu'il ne voie quoi que ce soit. Disponible partout, y compris `dash`.
* `[[ ]]` est un **mot-clé bash** analysé par le parseur : pas de découpage, pas
  de globbing des variables, opérateurs `&&`, `||`, `<`, `>`, motifs glob avec
  `==`, regex ERE avec `=~`, et `BASH_REMATCH` en prime.
* `(( ))` évalue une **expression arithmétique** et renvoie 0 si le résultat est
  non nul (attention à l'inversion, très logique côté C, contre-intuitive côté
  shell). `$` facultatif sur les variables.

Le test qui diverge :

```bash
v="a b"
[ $v = "a b" ]    # bash: [: too many arguments   (découpage)
[[ $v = "a b" ]]  # vrai
[ "$v" = "a b" ]  # vrai
```

Dans un script `#!/bin/sh` livré à un client : **`[ ]` uniquement**, avec
quoting systématique, et `case` plutôt que `=~` pour les motifs.

::: pourquoi
La différence de nature explique tout le reste : `[ ]` est une commande, donc
soumise aux expansions ; `[[ ]]` est de la syntaxe, donc protégée. C'est aussi
pourquoi `[[ $v == a* ]]` fait un motif alors que `[[ $v == "a*" ]]` fait une
comparaison littérale : les quotes **à droite** désactivent l'interprétation du
motif. Même règle pour `=~` : un motif entre quotes devient une chaîne.
:::

---

**QO7.4** — *Les quatre pièges de la lecture ligne à ligne.*

**Réponse de référence**

1. **Le pipe** : `cmd | while read ...` exécute la boucle dans un sous-shell,
   les variables modifiées sont perdues (Q7.5). Remède : redirection `< fichier`
   ou substitution de processus `< <(cmd)`.
2. **`IFS`** : `read` supprime les blancs de tête et de fin. Remède : `IFS=` en
   préfixe de la commande `read`.
3. **`-r`** : sans lui, les antislashs sont interprétés et disparaissent.
   Remède : toujours `-r`.
4. **La dernière ligne sans `\n`** : `read` renvoie un code non nul quand il
   atteint EOF sans séparateur, mais **a déjà affecté la variable**. La boucle
   `while read` s'arrête donc juste avant de traiter cette ligne. Remède :
   `while IFS= read -r ligne || [ -n "$ligne" ]; do`.

Forme canonique :

```bash
while IFS= read -r ligne || [ -n "$ligne" ]; do
  traiter "$ligne"
done < "$fichier"
```

`for ligne in $(cat f)` cumule tous les défauts **et** en ajoute deux : il
découpe sur les espaces (donc sur les **mots**, pas les lignes), et il glob le
résultat — une ligne contenant `*` est remplacée par la liste des fichiers du
répertoire courant. Il charge de plus tout le fichier en mémoire.

::: piege
Piège bonus : à l'intérieur de la boucle, toute commande qui lit stdin
(`ssh`, `mysql`, `ffmpeg`) **consomme le fichier** et la boucle s'arrête après
une itération. Remèdes : `ssh -n`, `mysql < /dev/null`, ou lire sur un autre
descripteur : `while IFS= read -r -u 3 l; do ...; done 3< "$f"`.
:::

---

**QO7.5** — *`rm -rf "$BASE/$SOUS"/*` a détruit la production.*

**Réponse de référence**

**Cause** : `$SOUS` était vide. Le chemin construit devient `"$BASE/"/*`,
c'est-à-dire tout le contenu de `$BASE`. Les quotes ne protègent pas de ça :
elles empêchent le découpage, pas le fait qu'une variable vide s'efface de la
chaîne. `$SOUS` peut être vide parce que la clé lue dans le fichier de
configuration a été renommée, parce que la commande qui la calcule a échoué
(sans `pipefail`, sans test), ou parce que l'appelant a oublié un argument.

**Preuve à apporter en post-mortem** : relire la ligne du journal qui affiche le
chemin ciblé (`purge de /srv/archives/ (> 7 jours)` — le nom du sous-répertoire
manque), et rejouer le script avec `bash -x` sur un jeu de données de test.

**Les gardes, par ordre d'efficacité :**

```bash
set -euo pipefail                       # 1. la variable non définie échoue
: "${SOUS:?sous-répertoire obligatoire}" # 2. la variable vide échoue aussi
CIBLE="$BASE/$SOUS"
[ -d "$CIBLE" ] || exit 3               # 3. la cible doit exister
case "$CIBLE" in "$BASE"/?*) ;; *) exit 3 ;; esac   # 4. et rester sous $BASE
find "$CIBLE" -maxdepth 1 -type f -mtime +"$JOURS" -print0 \
  | xargs -0 -r rm -f                   # 5. supprimer des FICHIERS ciblés
```

La cinquième est la plus importante : on ne supprime jamais « un répertoire et
tout ce qu'il contient » quand l'intention est « les fichiers de plus de N
jours ». Le `-r` de `xargs` évite d'appeler `rm` sans argument. Et en
production, un `--dry-run` par défaut plus une option `--go` explicite.

::: pourquoi
L'erreur de conception sous-jacente : le script exprimait *comment* supprimer
(`rm -rf` sur un chemin) au lieu d'exprimer *quoi* supprimer (des fichiers
répondant à un critère d'âge). Un `find` avec critères est auto-limitant ; un
`rm -rf` sur une variable est une bombe dont l'amorce est la valeur de la
variable.
:::

---

**QO7.6** — *Mécanisme de `flock`, `exec 9>` et comparaison au fichier PID.*

**Réponse de référence**

Le verrou porte sur la **description de fichier ouverte** (l'objet noyau créé
par `open`), pas sur le nom du fichier ni sur son contenu : le fichier de verrou
reste vide et sa persistance sur disque n'a aucune importance. Le verrou est
**consultatif** : il ne bloque que les processus qui demandent eux aussi un
`flock` sur le même fichier.

```bash
exec 9>"$LOCK"          # ouvre une fois, pour toute la durée du script
flock -n 9 || exit 9    # tente de verrouiller, échoue immédiatement si pris
```

Pourquoi cette forme plutôt que `flock "$LOCK" commande` : le descripteur 9
reste ouvert pendant **toute** la vie du script, donc le verrou couvre tout, y
compris les commandes lancées plus loin ; on garde la main sur le code de sortie
(9 chez nous) et sur le message ; et on peut choisir `-n` (échec immédiat) ou
`-w 30` (attente bornée) selon qu'une exécution manquée est acceptable ou non.

Libération : à la fermeture du dernier descripteur pointant la description,
c'est-à-dire à la mort du processus — y compris `kill -9`, panique, OOM killer.
Aucune trace à nettoyer.

Le fichier PID, lui, doit être écrit, relu, comparé à `/proc/$pid`, supprimé à
la sortie — et chaque étape peut échouer : PID recyclé, fichier laissé par un
crash, condition de concurrence entre le test et l'écriture. `flock` délègue
tout ça au noyau, atomiquement.

::: piege
Les fils héritent du descripteur et donc du verrou : un démon détaché lancé par
le script garde le verrou après la mort du script. Si tu lances un processus qui
doit survivre, ferme-lui le descripteur (`exec 9>&-` dans le sous-shell) ou
utilise `flock` sur un descripteur non hérité. Et vérifie que `$LOCK` est sur un
système de fichiers local : `flock` sur NFS a une histoire compliquée.
:::

---

**QO7.7** — *Démarche de diagnostic d'un script « qui marche à la main ».*

**Réponse de référence**

1. **Lire avant d'exécuter** : `shellcheck -x script.sh`. Trois minutes, et il
   trouve souvent la cause (SC2086 non quoté, SC2164 `cd` non testé, SC2155
   `local` masquant, SC2012 `ls` parsé).
2. **Comparer les deux environnements**, car c'est la différence qui cause la
   panne. Dans le script, temporairement : `env | sort > /tmp/env.$$`, puis
   diff entre l'exécution manuelle et l'exécution automatique. Cible principale :
   `PATH`, `HOME`, `LANG`/`LC_ALL`, `TERM`, `SHELL`, et l'absence de TTY.
3. **Rejouer dans les mêmes conditions** : `env -i /bin/bash --noprofile
   --norc ./script.sh` reproduit un environnement nu. Si ça casse là, c'est un
   problème d'environnement, pas de logique.
4. **Tracer** : `bash -x script.sh 2> /tmp/trace.log`, avec un `PS4` utile :

```bash
export PS4='+ ${BASH_SOURCE##*/}:$LINENO:${FUNCNAME[0]:-main}() '
```

   On lit la trace à l'envers, depuis la dernière ligne exécutée. Pour un script
   long, `set -x` / `set +x` autour de la zone suspecte évite 4 000 lignes.
5. **Vérifier les hypothèses implicites** : commandes absentes du `PATH` réduit
   (`command -v docker`), répertoire courant supposé, fichiers relatifs,
   interactivité (`[ -t 0 ]`), variables venant de `~/.bashrc` — qui n'est pas lu
   en non-interactif.
6. **Corriger durablement** : chemins absolus ou `PATH` fixé en tête de script,
   pré-conditions explicites, journalisation horodatée sur stderr redirigée vers
   un fichier, et un mode `--verbeux` permanent pour ne plus avoir à instrumenter
   la prochaine fois.

::: pourquoi
La question n'est pas « sais-tu utiliser `bash -x` » mais « sais-tu que le
problème est presque toujours une différence d'environnement ». Le réflexe qui
distingue un candidat : commencer par comparer les environnements, pas par lire
le code ligne à ligne.
:::

---

**QO7.8** — *Trois critères pour passer de bash à Python ou Ansible.*

**Réponse de référence**

1. **Le script manipule des structures de données.** Dès qu'il faut un tableau
   de dictionnaires, du JSON ou du YAML autre qu'un `jq` d'une ligne, bash n'a
   pas les types : tout est chaîne, les tableaux ne s'imbriquent pas, et le
   passage par variables devient du quoting acrobatique. Python a des types, des
   exceptions et une bibliothèque standard.
   *Seuil mesurable* : plus d'un appel à `jq` ou plus de deux tableaux
   associatifs corrélés.

2. **Le script décrit un état désiré plutôt qu'une suite d'actions.**
   « Le paquet nginx installé, ce fichier de conf en place, ce service démarré »
   est de l'idempotence à réécrire à la main à chaque fois en bash (tester avant
   d'agir, gérer le cas déjà-fait, recharger seulement si changement). Ansible
   fait ça nativement, avec `--check`, `--diff` et un rapport de changement.
   *Seuil mesurable* : plus de trois blocs `if ... déjà fait ... else ... fi`,
   ou le script doit tourner sur plus de deux machines.

3. **Le script dépasse ~300 lignes, ou doit être testé.** Au-delà, bash devient
   difficile à découper (pas de modules, pas d'espaces de noms), les tests
   unitaires demandent `bats`, la gestion d'erreur reste rudimentaire, et la
   moindre reprise par un collègue coûte cher.
   *Seuil mesurable* : 300 lignes, ou plus de 5 fonctions partagées entre
   plusieurs scripts, ou une exigence de tests unitaires.

Critère inverse, tout aussi important : **reste en bash** tant que le script
enchaîne des commandes système, tient en une page, et n'a pas d'état. Réécrire
un `tar | ssh` en Python n'apporte rien et ajoute une dépendance.

::: pourquoi
Ce qu'on évalue ici, c'est le jugement d'ingénierie, pas la préférence. Une
réponse « bash c'est sale, Python c'est mieux » vaut zéro : bash est le plus
court chemin pour orchestrer des processus, et c'est le seul langage garanti
présent sur toutes les machines. Le passage se justifie par les **données**,
l'**idempotence** et la **taille**, pas par le goût.
:::

---

## 7.5 Exercices guidés

**E7.1** — *Faire fonctionner `bonjour.sh` livré sans bit d'exécution.*

```bash
cd ~/lab07/bin
./bonjour.sh                  # bash: ./bonjour.sh: Permission denied

bash bonjour.sh               # 1. on lance l'interpréteur, le script est
                              #    un simple fichier de données lu par bash
chmod +x bonjour.sh && ./bonjour.sh   # 2. le noyau peut enfin l'exécuter
source bonjour.sh             # 3. lu par le shell courant, aucun fils
```

::: pourquoi
`./bonjour.sh` demande au **noyau** d'exécuter le fichier : il vérifie le bit
`x`, lit le shebang, et lance `/usr/bin/env bash ./bonjour.sh`. Sans bit `x`,
l'appel système `execve` échoue avec `EACCES`, d'où `Permission denied` — le
message vient du shell, mais la décision vient du noyau.

`bash bonjour.sh` contourne complètement l'affaire : on exécute `/bin/bash`
(qui, lui, est exécutable) en lui passant un nom de fichier à lire. Le shebang
n'est alors qu'un commentaire, et le bit `x` est inutile. C'est pour ça que
`bash script.sh` reste la façon la plus robuste de lancer un script qu'on vient
de récupérer.
:::

---

**E7.2** — *`./portee.sh` vs `bash portee.sh` vs `source portee.sh`.*

```bash
cd ~/lab07/bin
echo "avant: pwd=$PWD pid=$$ marqueur=${MARQUEUR:-(vide)}"
./portee.sh      ; echo "après ./     : pwd=$PWD marqueur=${MARQUEUR:-(vide)}"
bash portee.sh   ; echo "après bash   : pwd=$PWD marqueur=${MARQUEUR:-(vide)}"
source portee.sh ; echo "après source : pwd=$PWD marqueur=${MARQUEUR:-(vide)}"
```

| Invocation | PID affiché | `$PWD` après | `MARQUEUR` après |
|---|---|---|---|
| `./portee.sh` | différent | inchangé | vide |
| `bash portee.sh` | différent | inchangé | vide |
| `source portee.sh` | **le tien** | `/tmp` | défini |

::: pourquoi
Les deux premières formes créent un processus fils : il hérite de
l'environnement, mais ses modifications (variables, répertoire courant, options
`set`) meurent avec lui. La troisième fait lire le fichier par le shell courant,
sans `fork` : `$$` est inchangé, le `cd /tmp` te déplace réellement, et
`MARQUEUR` reste défini.

D'où la règle : un script qui doit **modifier ta session** (activation
d'environnement, chargement de variables) se source ; tout le reste s'exécute.
Et un script destiné à être sourcé ne doit contenir ni `exit` (il fermerait ta
session) ni `set -e` (il resterait actif après).
:::

---

**E7.3** — *`args.sh` : nom, nombre, arguments numérotés, PID.*

```bash
#!/usr/bin/env bash
set -euo pipefail
printf 'script   : %s\n' "${0##*/}"
printf 'arguments: %d\n' "$#"
i=1
for a in "$@"; do
  printf '  $%d = [%s]\n' "$i" "$a"
  i=$((i + 1))
done
printf 'pid      : %d\n' "$$"
```

```console
$ ./args.sh un "deux trois" 'quatre  cinq'
script   : args.sh
arguments: 3
  $1 = [un]
  $2 = [deux trois]
  $3 = [quatre  cinq]
pid      : 24817
```

::: pourquoi
`${0##*/}` retire le plus long préfixe finissant par `/` : c'est un `basename`
sans processus externe. `for a in "$@"` itère sur les arguments **tels que
reçus** : les crochets dans le `printf` rendent visibles les espaces conservés,
y compris les deux espaces de `quatre  cinq`. Avec `$*` ou `$@` non quoté, tu
verrais 5 arguments au lieu de 3.
:::

---

**E7.4** — *Substitutions de paramètres sur `/var/log/nginx/access.log.1`.*

```bash
f=/var/log/nginx/access.log.1
echo "${f##*/}"          # access.log.1        nom seul
echo "${f%/*}"           # /var/log/nginx      répertoire
echo "${f%.1}"           # /var/log/nginx/access.log   sans le suffixe .1
n=${f##*/}; echo "${n%%.*}"   # access          nom sans aucune extension
echo "${f^^}"            # /VAR/LOG/NGINX/ACCESS.LOG.1
```

::: pourquoi
Les quatre opérateurs de découpe se lisent avec deux règles : `#` travaille par
la **gauche**, `%` par la **droite** ; doublé, l'opérateur prend la
correspondance la plus **longue**. Aucun de ces calculs ne lance de processus,
contrairement à `basename`/`dirname`/`cut`/`sed` : dans une boucle sur 50 000
fichiers, la différence est de l'ordre de la minute.

Noter l'étape en deux temps pour « le nom sans extension » : appliquer
directement `${f%%.*}` au chemin complet couperait aussi le répertoire s'il
contenait un point.
:::

---

**E7.5** — *`DEST` valorisé, et différence `${1-def}` / `${1:-def}`.*

```bash
DEST=${1-/srv/factura}           # ABSENT seulement -> /srv/factura
: "${DEST:?destination vide}"    # "" passé explicitement -> arrêt + message
Avec ${1:-/srv/factura}, le "" explicite serait remplacé par le défaut et le :? suivant ne se déclencherait
jamais : c'est bien la forme sans deux-points qu'il faut ici.
```

```console
$ set -- ""            # on passe explicitement une chaîne vide
$ echo "[${1-def}]"    # []      : l'argument EXISTE, il est juste vide
$ echo "[${1:-def}]"   # [def]   : le deux-points couvre aussi le cas vide
```

::: pourquoi
Toutes les substitutions par défaut existent en deux variantes. Sans
deux-points, bash ne teste que l'**existence** de la variable ; avec, il teste
« non définie **ou** vide ». En script d'exploitation, c'est presque toujours la
forme avec deux-points qu'on veut : une variable vide est une erreur, pas une
valeur.

`${v:=def}` va plus loin : il **affecte** la valeur de repli, ce qui évite de
répéter le défaut plus bas. Il ne fonctionne pas sur les paramètres positionnels
(`${1:=x}` est une erreur), d'où l'affectation explicite à `DEST`.
:::

---

**E7.6** — *Fonctions `extension` et `souche`, sans appel externe.*

```bash
extension() {
  local nom=${1##*/}
  case "$nom" in
    *.*) printf '%s\n' "${nom##*.}" ;;
    *)   printf '\n' ;;              # pas d'extension : chaîne vide
  esac
}

souche() {
  local nom=${1##*/}
  printf '%s\n' "${nom%%.*}"
}
```

```console
$ extension factura-2026-09-18.tar.gz ; souche factura-2026-09-18.tar.gz
gz
factura-2026-09-18
$ extension LISEZMOI ; echo "(vide ci-dessus)"
(vide ci-dessus)
```

::: piege
Sans le `case`, `${nom##*.}` sur un nom **sans** point renvoie le nom entier :
`extension LISEZMOI` dirait `LISEZMOI`. Une substitution dont le motif ne
correspond pas rend la chaîne inchangée — jamais une chaîne vide. C'est la
source classique du fichier renommé `LISEZMOI.LISEZMOI`.
:::

---

**E7.7** — *Trois tests qui échouent en `[ ]` non quoté.*

```console
$ v=""    ; [ -n $v ] && echo vrai || echo faux
vrai                                   # attendu : faux  (voir Q7.4)
$ v="a b" ; [ $v = "a b" ] && echo vrai
bash: [: too many arguments            # 4 arguments au lieu de 3
$ v="4.00"; [ $v -gt 2 ] && echo vrai || echo faux
bash: [: 4.00: integer expression expected
faux
```

Versions correctes :

```bash
[ -z "$v" ] && echo "vide"
[[ $v == "a b" ]] && echo "égal"
awk -v a="$v" 'BEGIN{ exit !(a > 2) }' && echo "supérieur"
```

::: pourquoi
Les trois erreurs ont trois causes différentes, et c'est ce qui les rend
instructives : la première vient du **découpage** qui fait disparaître un
argument, la deuxième du découpage qui en **ajoute** un, la troisième d'une
**incompatibilité de type**. Seule la première est silencieuse — et c'est la
plus dangereuse.
:::

---

**E7.8** — *Récupérer la dernière ligne de `serveurs.txt`.*

```bash
f=~/lab07/data/serveurs.txt
n=0; while read -r l;                do n=$((n+1)); done < "$f"
m=0; while read -r l || [ -n "$l" ]; do m=$((m+1)); done < "$f"
echo "naïf=$n corrigé=$m"        # naïf=6 corrigé=7
```

::: pourquoi
`read` renvoie un code non nul quand il rencontre la fin de fichier **avant** un
séparateur de ligne. Mais avant de renvoyer ce code, il a déjà rempli la
variable avec ce qu'il a lu. La condition `|| [ -n "$l" ]` rattrape exactement
ce cas : si `read` a échoué mais que la variable n'est pas vide, on fait un tour
de boucle de plus.

Vérifier le symptôme sur le fichier : `tail -c 1 fichier | xxd` — pas de `0a`
final. Beaucoup d'exportateurs (tableurs, API, `printf` mal fini) produisent ce
genre de fichier, et l'erreur est invisible tant qu'on ne compte pas.
:::

---

**E7.9** — *Hôtes de production au format `hote (ip)`.*

```bash
{
  read -r _                       # on consomme l'en-tête
  while IFS=';' read -r hote ip role env reste || [ -n "$hote" ]; do
    [ "$env" = prod ] || continue
    printf '%s (%s)\n' "$hote" "$ip"
  done
} < ~/lab07/data/inventaire.csv
```

```console
lab-adm (10.10.10.10)
lab-web (10.10.10.11)
lab-db (10.10.10.12)
cache-01 (10.10.10.31)
```

::: pourquoi
`IFS=';'` en préfixe de `read` ne vaut que pour cette commande : le découpage se
fait sur le point-virgule et **pas** sur les espaces, donc `frontal web` reste un
seul champ. Le `read -r _` initial consomme l'en-tête sans `if` ni compteur ; le
`_` est une variable comme une autre, mais la convention signale « je jette ».

Le regroupement `{ ... } < fichier` redirige le bloc entier : le `read`
d'en-tête et la boucle lisent le **même** descripteur, donc la boucle reprend là
où l'en-tête s'est arrêté.
:::

---

**E7.10** — *Charger `seuils.conf` dans un tableau associatif.*

```bash
declare -A SEUILS
while IFS='=' read -r cle valeur || [ -n "$cle" ]; do
  cle=${cle// /}                       # on retire les espaces autour
  case "$cle" in ''|\#*) continue ;; esac   # vide ou commentaire
  SEUILS["$cle"]=${valeur// /}
done < ~/lab07/conf/seuils.conf

echo "disque_max=${SEUILS[disque_max]}"      # disque_max=85
echo "clés : ${!SEUILS[*]}"
```

::: pourquoi
`IFS='='` découpe sur le premier `=`, et comme `read` met **tout le reste** dans
la dernière variable, une valeur contenant elle-même un `=` reste intacte.
`${cle// /}` supprime toutes les espaces (substitution globale avec un
remplacement vide), ce qui tolère `cle = valeur`.

Le `case` filtre commentaires et lignes vides en deux mots, là où un `if` avec
`grep` lancerait un processus par ligne.
:::

::: piege
Ne **jamais** charger un fichier de configuration avec `source` s'il n'est pas
sous ton contrôle exclusif : une ligne `retention_jours=7; rm -rf /` serait
exécutée. Le parsing explicite, lui, ne peut rien exécuter.
:::

---

**E7.11** — *Fonction `pair_impair` : résultat sur stdout, code par `return`.*

```bash
pair_impair() {
  local n=$1
  if (( n % 2 == 0 )); then
    echo pair
    return 0
  fi
  echo impair
  return 1
}

if pair_impair 4 > /dev/null; then echo "4 est pair"; fi
mot=$(pair_impair 7); echo "sortie=$mot code=$?"   # sortie=impair code=1
```

::: pourquoi
Les deux canaux ne se mélangent pas parce qu'ils ne voyagent pas ensemble.
Utilisée en condition, la fonction est évaluée pour son **code** et sa sortie
part sur le terminal (d'où le `> /dev/null`). Capturée par `$( )`, sa sortie est
récupérée dans la variable, et `$?` reste celui de la fonction — parce que le
code de retour d'une affectation simple est celui de sa substitution de
commande.

Ce confort disparaît dès que l'affectation est préfixée par une commande :
`local mot=$(pair_impair 7)` donne `$?` = 0, celui de `local` (Q7.6). C'est
pourquoi on écrit `local mot` puis `mot=$(pair_impair 7)`.

Pour traiter explicitement l'échec : `mot=$(pair_impair 7) || rc=$?`. C'est aussi pourquoi
une fonction ne doit jamais écrire ses messages de journal sur stdout : ils
finiraient dans la variable de l'appelant. Journal sur **stderr**, résultat sur
**stdout**.
:::

---

**E7.12** — *Tableau des noms de journaux.*

```bash
shopt -s nullglob
journaux=()
for f in ~/lab07/logs/*.log; do journaux+=("${f##*/}"); done
shopt -u nullglob

echo "nombre  : ${#journaux[@]}"     # 8
echo "3e      : ${journaux[2]}"      # les indices commencent à 0
for i in "${!journaux[@]}"; do
  printf '%2d : %s\n' "$i" "${journaux[$i]}"
done
```

::: pourquoi
`journaux+=("$x")` ajoute **un** élément, quotes comprises ; `journaux+=($x)`
en ajouterait autant que de mots. `${!journaux[@]}` donne les indices, ce qui
est plus sûr que `for ((i=0; i<${#journaux[@]}; i++))` dès que le tableau est
creux (un `unset journaux[2]` laisse un trou sans décaler les autres).

`shopt -s nullglob` évite l'élément fantôme `~/lab07/logs/*.log` quand le
répertoire est vide.
:::

---

**E7.13** — *Répertoire temporaire, avec et sans `trap`.*

```bash
# version sans filet
cat > /tmp/sans-trap.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
T=$(mktemp -d -t essai.XXXX); echo "$T"
echo data > "$T/f"
faux_binaire            # échec : le script meurt ici
rm -rf "$T"             # jamais atteint
EOF

# version avec filet : une seule ligne de différence
cat > /tmp/avec-trap.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
T=$(mktemp -d -t essai.XXXX); echo "$T"
trap 'rm -rf -- "$T"' EXIT
echo data > "$T/f"
faux_binaire
EOF

rm -rf /tmp/essai.*
bash /tmp/sans-trap.sh ; echo "rc=$?"
bash /tmp/avec-trap.sh ; echo "rc=$?"
ls -d /tmp/essai.* 2>/dev/null     # seul reste celui de la version sans trap
```

```console
/tmp/essai.0skN
/tmp/sans-trap.sh: line 5: faux_binaire: command not found
rc=127
/tmp/essai.RGfd
/tmp/avec-trap.sh: line 6: faux_binaire: command not found
rc=127
/tmp/essai.0skN
```

::: pourquoi
La leçon n'est pas « mettre un `rm` à la fin » — on en met toujours un, et il
n'est jamais atteint le jour où ça compte. `trap ... EXIT` déplace le nettoyage
d'un **point** du code vers un **évènement** : il s'exécute quel que soit le
chemin de sortie, y compris `exit 3` au milieu, `set -e`, ou Ctrl-C.

Deux précautions : poser le trap **juste après** la création (pas avant, `$T`
serait vide), et écrire le nettoyage de façon défensive
(`[ -n "$T" ] && [ -d "$T" ] && rm -rf -- "$T"`), parce qu'un trap qui échoue
masque le code de sortie réel.
:::

---

**E7.14** — *`essai-signaux.sh` : 130 sur INT, 143 sur TERM.*

```bash
#!/usr/bin/env bash
set -uo pipefail
trap 'echo; echo "arrêt demandé (INT)" >&2; exit 130' INT
trap 'echo; echo "arrêt demandé (TERM)" >&2; exit 143' TERM
while true; do printf '.'; sleep 1; done
```

```console
$ ./essai-signaux.sh
...^C
arrêt demandé (INT)
$ echo $?
130
$ ./essai-signaux.sh & sleep 3; kill -TERM %1; wait %1; echo $?
143
```

::: pourquoi
La convention `128 + numéro_de_signal` vient du shell lui-même : quand une
commande est tuée par le signal `n`, bash rapporte `128+n` dans `$?`. En la
reproduisant explicitement, ton script reste lisible par tout ce qui l'appelle
(supervision, ordonnanceur, `make`) : 130 = interrompu au clavier, 143 = arrêt
demandé par systemd ou un `kill` propre, 137 = tué en SIGKILL (souvent l'OOM
killer, à reconnaître d'un coup d'œil).

Sans trap, le comportement par défaut donne les mêmes codes, mais sans message
ni nettoyage. Le trap sert à faire quelque chose **avant** de partir.
:::

---

**E7.15** — *Cinq défauts de `~/lab07/casse/compte-erreurs.sh`.*

Le script livré :

```bash
DIR=$1
for f in `ls $DIR`
do
  n=`grep -c ERROR $DIR/$f`
  if [ $n > 10 ]; then
    echo "$f : beaucoup d'erreurs ($n)"
  fi
done
```

| # | Défaut | Code shellcheck |
|---|---|---|
| 1 | `` for f in `ls $DIR` `` : casse sur les espaces | SC2045 / SC2006 |
| 2 | `$DIR` et `$f` non quotés | SC2086 |
| 3 | `` `…` `` au lieu de `$(…)` | SC2006 |
| 4 | `[ $n > 10 ]` : `>` **redirige**, ne compare pas | SC2071 / SC2086 |
| 5 | `$1` non vérifié : `ls` liste le répertoire courant | SC2154 (esprit) |

Version corrigée :

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR=${1:?usage: compte-erreurs.sh <répertoire>}
[ -d "$DIR" ] || { echo "répertoire introuvable : $DIR" >&2; exit 3; }
shopt -s nullglob
for f in "$DIR"/*.log; do
  n=$(grep -c 'ERROR' -- "$f" || true)
  if [ "$n" -gt 10 ]; then
    printf '%s : beaucoup d'\''erreurs (%s)\n' "${f##*/}" "$n"
  fi
done
```

::: piege
Le quatrième défaut est le plus vicieux : `[ $n > 10 ]` ne provoque **aucune**
erreur. Le shell voit une redirection, crée un fichier nommé `10` dans le
répertoire courant, et `[ $n ]` est vrai dès que `$n` est non vide — donc la
condition est toujours vraie. Le script « marche », il alerte simplement sur
tous les fichiers. Et il sème des fichiers nommés `10` partout.
:::

---

**E7.16** — *Réécrire `menage.sh` sans danger.*

```bash
#!/usr/bin/env bash
# menage.sh — vide un sous-répertoire de /tmp/travail, et rien d'autre.
set -euo pipefail

RACINE=/tmp/travail
CIBLE_REL=${1:?usage: menage.sh <sous-répertoire>}

# 1. aucun chemin qui remonte, aucun chemin absolu
case "$CIBLE_REL" in
  ''|*/../*|*/..|../*|..|/*) echo "cible invalide : $CIBLE_REL" >&2; exit 2 ;;
esac

CIBLE="$RACINE/$CIBLE_REL"

# 2. la cible doit exister et être un répertoire
[ -d "$CIBLE" ] || { echo "répertoire introuvable : $CIBLE" >&2; exit 3; }

# 3. et rester sous la racine, chemin RÉSOLU (liens symboliques compris)
REEL=$(readlink -f -- "$CIBLE")
case "$REEL" in
  "$RACINE"/?*) ;;
  *) echo "hors périmètre : $REEL" >&2; exit 2 ;;
esac

# 4. on supprime des FICHIERS ciblés, pas une arborescence par son chemin
find "$REEL" -mindepth 1 -maxdepth 1 -print0 | xargs -0 -r rm -rf --
echo "ménage fait dans $REEL"
```

```console
$ ./menage.sh ""
./menage.sh: line 6: 1: usage: menage.sh <sous-répertoire>
$ ./menage.sh ../../etc
cible invalide : ../../etc
```

::: pourquoi
Quatre gardes, quatre familles d'attaque. Le `${1:?}` traite l'argument absent
**et** vide, ce qui neutralise le `rm -rf "$CIBLE/*"` sur racine vide. Le
premier `case` rejette la traversée de répertoires (`../`). Le `readlink -f`
résout les liens symboliques **avant** de vérifier le périmètre : sans lui, un
`ln -s / /tmp/travail/piege` suffirait à sortir de la zone. Enfin, `find` +
`xargs -0 -r` ne supprime que ce qui a été listé, et `-r` évite d'appeler `rm`
sans argument si la liste est vide.
:::

---

## 7.6 Labs

### **L7.1** — *Rapport d'erreurs : squelette de script de service.*

```bash
#!/usr/bin/env bash
# rapport-erreurs.sh — compte les ERROR de chaque journal d'un répertoire.
# Sortie : rapport CSV sur stdout, journal de service sur stderr.
# Codes : 0 sous le seuil, 1 seuil dépassé, 2 usage, 3 répertoire.
set -euo pipefail

REP="$HOME/lab07/logs"
SEUIL=25
VERBEUX=0
PROG=${0##*/}

usage() {
  cat <<EOF
usage: $PROG [-d répertoire] [-s seuil] [-v] [-h]

  -d répertoire  répertoire des journaux (défaut : \$HOME/lab07/logs)
  -s seuil       nombre d'erreurs à partir duquel on alerte (défaut : 25)
  -v             journalisation verbeuse sur stderr
  -h             affiche cette aide et sort

Sortie standard : une ligne "nom;nb_erreurs" par journal, la plus
bruyante d'abord. Code 1 si au moins un journal dépasse le seuil.
EOF
}

horodate()  { date +%Y-%m-%dT%H:%M:%S%:z; }
log_info()  { printf '%s [INFO] %s\n'  "$(horodate)" "$*" >&2; }
log_warn()  { printf '%s [WARN] %s\n'  "$(horodate)" "$*" >&2; }
log_error() { printf '%s [ERROR] %s\n' "$(horodate)" "$*" >&2; }
log_debug() {
  [ "$VERBEUX" -eq 1 ] || return 0
  printf '%s [DEBUG] %s\n' "$(horodate)" "$*" >&2
}

while getopts ':d:s:vh' opt; do
  case "$opt" in
    d) REP=$OPTARG ;;
    s) SEUIL=$OPTARG ;;
    v) VERBEUX=1 ;;
    h) usage; exit 0 ;;
    :)  log_error "option -$OPTARG : argument manquant"; usage >&2; exit 2 ;;
    \?) log_error "option inconnue : -$OPTARG"; usage >&2; exit 2 ;;
    *)  usage >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

[ "$#" -eq 0 ] || { log_error "argument en trop : $1"; usage >&2; exit 2; }

case "$SEUIL" in
  '' | *[!0-9]*) log_error "seuil non numérique : $SEUIL"; exit 2 ;;
esac

[ -d "$REP" ] || { log_error "répertoire introuvable : $REP"; exit 3; }

log_info "analyse de $REP (seuil $SEUIL)"

depasse=0
lignes=()
shopt -s nullglob
for f in "$REP"/*.log; do
  n=$(grep -c 'ERROR' -- "$f" || true)
  log_debug "$f -> $n"
  lignes+=("$n;${f##*/}")
  if [ "$n" -ge "$SEUIL" ]; then
    log_warn "${f##*/} dépasse le seuil : $n erreurs"
    depasse=1
  fi
done
shopt -u nullglob

if [ "${#lignes[@]}" -eq 0 ]; then
  log_warn "aucun fichier .log dans $REP"
  exit 0
fi

printf '%s\n' "${lignes[@]}" \
  | sort -t';' -k1,1nr -k2,2 \
  | while IFS=';' read -r n nom; do
      printf '%s;%s\n' "$nom" "$n"
    done

log_info "${#lignes[@]} journaux analysés, dépassement=$depasse"
exit "$depasse"
```

```console
$ ./rapport-erreurs.sh -s 25 2>/dev/null
app-2026-09-16.log;44
app-2026-09-14.log;31
app-2026-09-12.log;12
app-2026-09-17.log;9
app-2026-09-15.log;7
rapport final.log;6
app-2026-09-13.log;3
app-2026-09-18.log;2
$ echo $?
1
```

::: pourquoi
Trois décisions de conception portent tout le script.

**Le canal de sortie.** Le rapport va sur stdout, le journal sur stderr. C'est
ce qui rend `rapport-erreurs.sh > rapport.csv` utilisable directement dans une
chaîne de traitement, tout en gardant les messages visibles à l'écran. La
convention UNIX est constante : stdout porte le **résultat exploitable**, stderr
porte le **récit de l'exécution**.

**Le tri.** On construit les lignes dans l'ordre `nombre;nom` pour pouvoir trier
numériquement sur le premier champ (`sort -k1,1nr`), puis on inverse les champs
à la sortie avec un `while IFS=';' read`. Comme `read` affecte tout le reste de
la ligne à sa dernière variable, un nom contenant un `;` ne casserait pas la
relecture.

**Le stockage en tableau.** `lignes+=("$n;${f##*/}")` accumule en mémoire au
lieu d'écrire dans un fichier temporaire : pas de nettoyage à prévoir, pas de
course entre instances, et le quoting protège le nom à espace de bout en bout.

Le code de sortie, enfin, est `$depasse` : 0 ou 1, directement exploitable par
une sonde de supervision (`0 = OK`, `1 = WARNING`), les codes 2 et 3 étant
réservés aux erreurs d'invocation.
:::

::: piege
`grep -c` renvoie **1** quand il ne compte rien, ce qui tue le script sous
`set -e`. Le `|| true` neutralise ce cas particulier sans masquer une vraie
erreur de lecture (qui renverrait 2). Autre piège évité : `shopt -s nullglob`,
sans lequel un répertoire sans `.log` produirait une itération sur la chaîne
littérale `rep/*.log` et un `grep` sur un fichier inexistant.
:::

---

### **L7.2** — *Exploiter l'inventaire CSV.*

```bash
#!/usr/bin/env bash
# inventaire.sh — synthèse de l'inventaire CSV de parc.
# Codes : 0 ok, 2 usage, 4 fichier introuvable.
set -euo pipefail

CSV="$HOME/lab07/data/inventaire.csv"
RAPPORT="$HOME/lab07/rapports/inventaire.txt"
PROG=${0##*/}

usage() {
  cat <<EOF
usage: $PROG [-f csv] [-o rapport] [-h]

  -f csv      inventaire source
              (défaut : \$HOME/lab07/data/inventaire.csv)
  -o rapport  fichier de sortie
              (défaut : \$HOME/lab07/rapports/inventaire.txt)
  -h          affiche cette aide
EOF
}

log_error() {
  printf '%s [ERROR] %s\n' "$(date +%Y-%m-%dT%H:%M:%S%:z)" "$*" >&2
}

while getopts ':f:o:h' opt; do
  case "$opt" in
    f) CSV=$OPTARG ;;
    o) RAPPORT=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

[ -f "$CSV" ] || { log_error "inventaire introuvable : $CSV"; exit 4; }

declare -A par_env
declare -a a_sortir
total=0
premiere=1

# IFS=';' découpe les champs ; -r n'interprète pas les antislashs ;
# le test final récupère la dernière ligne quand elle n'a pas de \n.
while IFS=';' read -r hote _ip _role env reste || [ -n "$hote" ]; do
  if [ "$premiere" -eq 1 ]; then
    premiere=0
    continue                       # en-tête
  fi
  [ -n "$hote" ] || continue
  total=$((total + 1))
  par_env["$env"]=$(( ${par_env["$env"]:-0} + 1 ))
  [ -z "$reste" ] || a_sortir+=("$hote")
done < "$CSV"

mkdir -p "$(dirname "$RAPPORT")"

{
  echo "== Hôtes par environnement =="
  for e in $(printf '%s\n' "${!par_env[@]}" | sort); do
    printf '%s;%s\n' "$e" "${par_env[$e]}"
  done
  echo "== À décommissionner =="
  if [ "${#a_sortir[@]}" -gt 0 ]; then
    printf '%s\n' "${a_sortir[@]}"
  fi
  echo "== Total =="
  printf '%s\n' "$total"
} | tee "$RAPPORT"
```

::: pourquoi
Quatre mécanismes se combinent, un par piège de l'énoncé.

**`IFS=';' read -r ... reste`** : cinq variables pour quatre champs attendus.
Comme `read` verse **tout le reste de la ligne** dans sa dernière variable,
`reste` est vide pour les lignes normales et contient `a-decommissionner` pour
`cache-01`. C'est donc le test `[ -z "$reste" ]` qui détecte le champ
surnuméraire — sans compter les champs, sans `awk`.

**`|| [ -n "$hote" ]`** : `runner-01` est la dernière ligne et n'a pas de `\n`
final. `read` remplit les variables puis renvoie un code non nul ; la condition
de secours force un dernier tour de boucle. Sans elle, le total est 9 et
`outillage` vaut 1. C'est l'écart que les trois collègues de l'énoncé n'avaient
pas vu.

**`${par_env["$env"]:-0}`** : à la première rencontre d'un environnement, la
case n'existe pas ; `:-0` fournit la valeur de départ. Sans elle, l'arithmétique
sur une chaîne vide fonctionnerait par chance, mais `set -u` la refuserait.

**Le regroupement `{ ... } | tee`** : une seule construction du rapport,
envoyée simultanément à l'écran et au fichier. Pas de double logique, pas de
risque de divergence entre ce qu'on voit et ce qu'on archive.
:::

::: piege
La redirection `< "$CSV"` est posée sur le `done`, donc la boucle s'exécute dans
le **shell courant** : `par_env` et `total` survivent. Écrit
`cat "$CSV" | while ... done`, le même code afficherait 0 partout (Q7.5). C'est
la faute la plus fréquente sur ce type de script, et elle est indétectable à la
lecture rapide puisque la boucle « marche ».
:::

---

### **L7.3** — *Collecte robuste : verrou, espace jetable, nettoyage garanti.*

```bash
#!/usr/bin/env bash
# collecte.sh — collecte les journaux du jour dans une archive datée.
# Exécution unique garantie par flock, espace de travail jetable, nettoyage
# garanti par trap.
# Codes : 0 ok, 2 usage, 3 source absente, 9 déjà en cours.
set -euo pipefail

SOURCE="$HOME/lab07/logs"
DEST="$HOME/lab07/archives"
LOCK="$HOME/lab07/var/run/collecte.lock"
BLANC=0
VERBEUX=0
TRAVAIL=""
PROG=${0##*/}

usage() {
  cat <<EOF
usage: $PROG [--source REP] [--dest REP] [--dry-run] [--verbeux] [--help]
EOF
}

horodate()  { date +%Y-%m-%dT%H:%M:%S%:z; }
log_info()  { printf '%s [INFO] %s\n'  "$(horodate)" "$*" >&2; }
log_warn()  { printf '%s [WARN] %s\n'  "$(horodate)" "$*" >&2; }
log_error() { printf '%s [ERROR] %s\n' "$(horodate)" "$*" >&2; }
log_debug() {
  [ "$VERBEUX" -eq 1 ] || return 0
  printf '%s [DEBUG] %s\n' "$(horodate)" "$*" >&2
}

nettoyer() {
  local rc=$?
  if [ -n "$TRAVAIL" ] && [ -d "$TRAVAIL" ]; then
    rm -rf -- "$TRAVAIL"
    log_debug "espace de travail supprimé : $TRAVAIL"
  fi
  return "$rc"
}

sur_erreur() {
  trap - ERR                       # pas de cascade : une erreur, un message
  log_error "échec ligne $1 : $2"
}

# sortie volontaire : on désarme ERR pour ne pas polluer le diagnostic
mourir() {
  local code=$1
  shift
  trap - ERR
  log_error "$*"
  exit "$code"
}

sur_signal() {
  log_warn "interruption reçue ($1), on nettoie"
  trap - EXIT
  nettoyer
  exit $((128 + $2))
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      SOURCE=$2; shift 2 ;;
    --dest)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      DEST=$2; shift 2 ;;
    --dry-run) BLANC=1; shift ;;
    --verbeux) VERBEUX=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    *) log_error "option inconnue : $1"; usage >&2; exit 2 ;;
  esac
done

mkdir -p "$(dirname "$LOCK")"
exec 9>"$LOCK"
if ! flock -n 9; then
  printf '%s [ERROR] %s\n' "$(horodate)" \
    "une autre instance de $PROG tourne déjà (verrou $LOCK)" >&2
  exit 9
fi

TRAVAIL=$(mktemp -d -t collecte.XXXXXXXX)
trap 'nettoyer' EXIT
trap 'sur_erreur "$LINENO" "$BASH_COMMAND"' ERR
trap 'sur_signal INT 2' INT
trap 'sur_signal TERM 15' TERM
mkdir -p "$TRAVAIL/contenu"
log_debug "espace de travail : $TRAVAIL"

[ -d "$SOURCE" ] || mourir 3 "source introuvable : $SOURCE"

STAMP=$(date +%F)
ARCHIVE="$DEST/collecte-$STAMP.tar.gz"

if [ "$BLANC" -eq 1 ]; then
  log_info "[dry-run] archiverait $SOURCE dans $ARCHIVE"
  exit 0
fi

mkdir -p "$DEST"
log_info "collecte de $SOURCE"

# find -print0 / read -d '' : le seul duo qui survit à tous les noms
nb=0
while IFS= read -r -d '' f; do
  cp -p -- "$f" "$TRAVAIL/contenu/"
  nb=$((nb + 1))
done < <(find "$SOURCE" -maxdepth 1 -type f \
           -name '*.log' -print0)

if [ "$nb" -eq 0 ]; then
  log_warn "aucun journal à collecter dans $SOURCE"
  exit 0
fi

# on écrit à côté puis on renomme : pas d'archive à moitié écrite
tar -czf "$TRAVAIL/archive.tar.gz" -C "$TRAVAIL/contenu" .
mv -f -- "$TRAVAIL/archive.tar.gz" "$ARCHIVE"

log_info "$nb journaux archivés dans $ARCHIVE"
```

::: pourquoi
**Le verrou avant tout le reste.** `exec 9>"$LOCK"` ouvre le descripteur pour la
durée du script ; `flock -n 9` échoue immédiatement si une autre instance le
détient. Placer cette séquence **avant** la création de l'espace de travail
évite qu'une instance refusée ne crée puis ne supprime un répertoire pour rien.
Rien à nettoyer ensuite : le noyau libère le verrou à la mort du processus,
`kill -9` compris.

**Le trap posé juste après `mktemp`.** L'ordre est critique : entre la création
et la pose du trap, une interruption laisserait un orphelin. Et `nettoyer`
commence par `local rc=$?` afin de **préserver le code de sortie** : sans cette
ligne, le `rm -rf` réussi écraserait un code d'erreur par 0.

**Le `mourir` qui désarme `ERR`.** `exit 3` ne déclenche pas lui-même le trap `ERR` (et `[ -d ... ] ||` non plus : un test suivi de `||` est exempté), et sans `set -E` le trap `ERR` n'est même pas hérité par les fonctions. Le `trap - ERR` est donc une précaution, utile dès qu'on ajoute `set -E` : un échec secondaire dans `mourir` produirait sinon un second message « échec ligne N » qui noierait le vrai diagnostic.

**L'archive écrite à côté puis déplacée.** `mv` dans le même système de fichiers
est un `rename(2)`, donc atomique : l'archive finale n'existe jamais dans un
état partiel. Un consommateur qui surveille `$DEST` ne verra jamais un fichier
en cours d'écriture. C'est le même patron que pour les fichiers de
configuration : écrire à côté, `mv` par-dessus.

**Le duo `find -print0` / `read -r -d ''`.** L'octet nul est le seul caractère
interdit dans un nom de fichier : c'est donc le seul séparateur sûr. La
substitution de processus `< <(...)` garde la boucle dans le shell courant —
avec un pipe, `nb` resterait à 0.
:::

::: piege
Deux erreurs classiques que cette version évite. D'abord `tar` qui archive le
répertoire dans lequel il écrit son propre fichier : GNU tar se plaint
(`file changed as we read it`) et sort en 1 — d'où le sous-répertoire `contenu`
séparé. Ensuite `--dry-run` qui « ne fait presque rien » : ici il sort avant le
moindre `mkdir` sur la destination, ce que le contrôle `check_M07_03.sh` vérifie
explicitement.
:::

---

### **L7.4** — *Enveloppe d'exécution : journalisation, codes, signaux.*

```bash
#!/usr/bin/env bash
# shellcheck disable=SC2317  # sur_signal n'est appelée que par trap
# exec-tracee.sh — enveloppe d'exécution : journalise, propage, gère les
# signaux. La sortie de la commande n'est ni modifiée ni réordonnée.
# Codes : celui de la commande, 128+n si signal, 2 en cas d'usage incorrect.
set -uo pipefail

TAG=factura
FICHIER="$HOME/lab07/var/exec.log"
PROG=${0##*/}
ENFANT=0

usage() {
  cat <<EOF
usage: $PROG [-t tag] [-f fichier] -- commande [arguments...]
EOF
}

horodate() { date +%Y-%m-%dT%H:%M:%S%:z; }

journaliser() {
  local niveau=$1
  shift
  local ligne
  ligne="$(horodate) [$niveau] $*"
  printf '%s\n' "$ligne" >&2
  printf '%s\n' "$ligne" >> "$FICHIER"
  case "$niveau" in
    ERROR) logger -t "$TAG" -p user.err  -- "$*" 2>/dev/null || true ;;
    *)     logger -t "$TAG" -p user.info -- "$*" 2>/dev/null || true ;;
  esac
}

sur_signal() {
  local nom=$1 num=$2
  journaliser WARN "signal $nom reçu, arrêt de la commande (pid $ENFANT)"
  # toujours TERM : un fils lancé avec & par un shell non interactif
  # IGNORE SIGINT (hérité à l'exec), un kill -INT ne le toucherait pas
  [ "$ENFANT" -ne 0 ] && kill -TERM "$ENFANT" 2>/dev/null
  wait "$ENFANT" 2>/dev/null
  journaliser ERROR "fin sur signal $nom, code $((128 + num))"
  exit $((128 + num))
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -t) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; TAG=$2; shift 2 ;;
    -f) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; FICHIER=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) printf 'option inconnue : %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) break ;;
  esac
done

[ "$#" -gt 0 ] || { echo "aucune commande à exécuter" >&2; usage >&2; exit 2; }

mkdir -p "$(dirname "$FICHIER")"
trap 'sur_signal INT 2' INT
trap 'sur_signal TERM 15' TERM

journaliser INFO "début : $* (pid $$)"
debut=$SECONDS

# "$@" et rien d'autre : chaque argument reste un argument
"$@" &
ENFANT=$!
rc=0
wait "$ENFANT" || rc=$?

duree=$((SECONDS - debut))
if [ "$rc" -eq 0 ]; then
  journaliser INFO "fin : code 0 en ${duree}s"
else
  journaliser ERROR "fin : code $rc en ${duree}s"
fi
exit "$rc"
```

```console
$ ./exec-tracee.sh -- printf '[%s]\n' 'a b' c 2>/dev/null
[a b]
[c]
$ ./exec-tracee.sh -- sh -c 'exit 7' >/dev/null 2>&1; echo $?
7
$ ./exec-tracee.sh -- sleep 30 & sleep 1; kill -TERM %1; wait %1; echo $?
143
$ journalctl -t factura -n 3 --no-pager
```

::: pourquoi
**Pourquoi la commande tourne en arrière-plan.** Si l'enveloppe exécutait
`"$@"` au premier plan, elle resterait bloquée dans `execve`/`wait` interne et
ne pourrait pas traiter son propre trap avant la fin de la commande. Avec
`"$@" &` puis `wait "$ENFANT"`, un signal interrompt le `wait`, bash exécute le
gestionnaire, qui peut alors tuer proprement le fils, tracer et sortir avec le
bon code. C'est le patron standard de tout script d'enveloppe (`entrypoint.sh`
de conteneur, wrapper d'ordonnanceur).

**Pourquoi le gestionnaire envoie `TERM` même sur `INT`.** Dans un shell non interactif, une commande lancée avec `&` démarre avec `SIGINT` **ignoré** (règle POSIX), et cette disposition survit à l'`exec` : `kill -INT "$ENFANT"` ne ferait rien, le `wait` bloquerait jusqu'à la fin naturelle de la commande et le Ctrl-C paraîtrait « sans effet ». `TERM`, lui, n'est jamais ignoré d'office. **Pourquoi `set`** `-e` **est absent.** Ici, l'échec de la commande encapsulée est un
**résultat**, pas une erreur du script : il faut le journaliser et le propager,
pas interrompre l'enveloppe. On garde `set -u` et `pipefail`, qui protègent le
code de l'enveloppe elle-même. Choisir ses options selon le rôle du script fait
partie du métier ; `set -euo pipefail` n'est pas un réflexe aveugle.

**Pourquoi `wait "$ENFANT" || rc=$?`.** `wait` renvoie le code du processus
attendu. Le `|| rc=$?` capture ce code sans laisser `set -u`/`pipefail`
interférer, et surtout sans que la ligne suivante n'écrase `$?`.

**Pourquoi le journal va sur stderr.** L'enveloppe doit être transparente : ce
que produit la commande sur stdout doit rester exactement ce qu'un appelant
attend. `exec-tracee.sh -- mysqldump ... > dump.sql` doit produire un dump
propre, pas un dump précédé d'une ligne d'horodatage.

**`logger`** envoie la même information à syslog avec une étiquette
(`-t`) et une priorité (`-p user.info` / `user.err`), ce qui la rend visible à
`journalctl -t factura` et exploitable par une collecte centralisée, sans que le
script ait à connaître la destination finale.
:::

::: piege
`kill "$ENFANT"` ne tue que le processus direct. Si la commande encapsulée lance
elle-même des fils (un `make -j`, un pipeline), ils survivent. La parade
complète consiste à créer un groupe de processus (`set -m`, puis
`kill -TERM -"$ENFANT"` avec le signe moins), ou à déléguer à
`systemd-run --scope`. À mentionner en revue de code : l'enveloppe simple couvre
le cas courant, pas les arbres de processus.
:::

---

## 7.7 Break & Fix

### **BF7.1** — *La purge nocturne a tout effacé.*

**Cause racine** : la clé lue dans `purge.conf` a été renommée
(`sous_dossier` → `sous_repertoire`) sans que le script soit adapté.
`SOUS=$(grep sous_dossier $CONF | cut -d= -f2)` ne trouve plus rien et vaut la
chaîne vide. La dernière ligne du script,
`rm -rf $BASE/archives/$SOUS/*`, devient alors
`rm -rf /home/mathieu/lab07/bf1/archives//*` : le glob ne porte plus sur les
fichiers d'un sous-répertoire mais sur **tout le contenu de `archives`**, donc
sur `prod` **et** `recette`, récursivement, sans condition d'âge.

**Diagnostic pas à pas :**

```bash
# 1. remettre le terrain en état avant toute expérimentation
bash ~/lab07/bf1/restaure-jeu.sh

# 2. lire la première ligne de sortie du script : le chemin y est affiché
bash ~/lab07/bin/purge-archives.sh | head -1
# purge de /home/mathieu/lab07/bf1/archives/ (> 7 jours)
#                                          ^ le sous-répertoire manque

# 3. confirmer que la variable est vide. ATTENTION : bash -x EXÉCUTE le
#    script (le jeu est déjà vide après l'étape 2, c'est sans risque ici ;
#    sur un vrai incident, on copie le script et on remplace rm par echo)
bash -x ~/lab07/bin/purge-archives.sh 2>&1 | grep -E 'SOUS=|rm '
# + SOUS=
# + rm -rf '/home/mathieu/lab07/bf1/archives//*'   (jeu déjà vide)

# 4. remonter à la source : la clé n'existe plus sous ce nom
grep -n 'sous' ~/lab07/bf1/purge.conf
# 3:sous_repertoire=prod

# 5. vérifier le second symptôme, le nom à espace
bash ~/lab07/bf1/restaure-jeu.sh
( cd ~/lab07/bf1/archives/prod && for f in $(ls); do echo "[$f]"; done )
# [export] et [final.tar.gz] : deux entrées pour un seul fichier
```

**Correctif** (le script complet, corrigé ligne à ligne) :

```bash
#!/usr/bin/env bash
# purge-archives.sh — purge des archives, version corrigée.
# Codes : 0 ok, 2 configuration invalide, 3 cible introuvable.
set -euo pipefail

BASE=${BASE:-$HOME/lab07/bf1}
CONF="$BASE/purge.conf"

lire_cle() {              # lire_cle <clé> <fichier>
  local cle valeur
  while IFS='=' read -r cle valeur; do
    cle=${cle// /}
    [ "$cle" = "$1" ] || continue
    printf '%s\n' "${valeur// /}"
    return 0
  done < "$2"
  return 1
}

[ -f "$CONF" ] || { echo "configuration absente : $CONF" >&2; exit 2; }

SOUS=$(lire_cle sous_repertoire "$CONF") || {
  echo "clé sous_repertoire absente de $CONF" >&2; exit 2; }
JOURS=$(lire_cle retention_jours "$CONF") || JOURS=7

# la garde décisive : une valeur vide arrête tout, elle n'est pas « rien »
: "${SOUS:?sous-répertoire vide : refus de purger}"
case "$JOURS" in
  '' | *[!0-9]*) echo "rétention non numérique : $JOURS" >&2; exit 2 ;;
esac

CIBLE="$BASE/archives/$SOUS"
[ -d "$CIBLE" ] || { echo "cible introuvable : $CIBLE" >&2; exit 3; }

echo "purge de $CIBLE (> $JOURS jours)"
n=0
while IFS= read -r -d '' f; do
  echo "  supprimé : ${f##*/}"
  rm -f -- "$f"
  n=$((n + 1))
done < <(find "$CIBLE" -maxdepth 1 -type f -mtime +"$JOURS" -print0)

echo "purge terminée : $n fichier(s) supprimé(s)"
```

```console
$ bash ~/lab07/bf1/restaure-jeu.sh && ~/lab07/bin/purge-archives.sh
purge de /home/mathieu/lab07/bf1/archives/prod (> 7 jours)
  supprimé : factura-2026-08-20.tar.gz
  supprimé : export final.tar.gz
  supprimé : factura-2026-09-03.tar.gz
purge terminée : 3 fichier(s) supprimé(s)
$ ls ~/lab07/bf1/archives/prod
factura-2026-09-14.tar.gz  factura-2026-09-17.tar.gz
```

**Les trois gardes demandées :**

1. `set -euo pipefail` — une variable non définie devient une erreur fatale.
2. `: "${SOUS:?...}"` — une variable **vide** aussi, ce que `set -u` ne couvre
   pas. C'est la garde qui aurait empêché l'incident.
3. `find ... -mtime +N -print0` + `rm -f` fichier par fichier — on supprime des
   **fichiers sélectionnés par un critère**, plus jamais une arborescence
   désignée par un chemin construit.

::: pourquoi
Le mécanisme exact de la catastrophe mérite d'être énoncé lentement. Les quotes
ne servent à rien ici : `"$BASE/$SOUS"/*` avec `SOUS` vide donne bien
`"$BASE/"/*`, et le shell développe le glob sur le contenu de `$BASE`. Le
problème n'est pas le quoting, c'est qu'**une variable vide s'efface sans laisser
de trace** dans une chaîne. Un chemin construit par concaténation n'est jamais
sûr tant que chacun de ses composants n'a pas été validé.

Le second symptôme (le nom à espace) est indépendant : `for f in $(ls)` découpe
`export final.tar.gz` en deux mots, et le `find -name "$f"` qui suit ne trouve
ni `export` ni `final.tar.gz`. Le fichier n'était donc jamais **signalé** comme
vieux — mais il était bel et bien supprimé par le `rm -rf` final, ce qui montre
qu'un script peut être faux sur son diagnostic et destructeur en même temps.
:::

::: piege
Prévention à porter en revue de code : un script de suppression doit avoir un
mode `--dry-run` **par défaut** et ne détruire que sur option explicite ; il doit
journaliser le chemin ciblé **avant** d'agir (c'est ce qui a permis le
diagnostic en une ligne ici) ; et il ne doit jamais utiliser `rm -rf` sur un
chemin contenant une variable non validée. Le trio `set -u` + `${v:?}` +
`find -print0` couvre 90 % des incidents de ce type.
:::

---

### **BF7.2** — *La sauvegarde dit OK tous les matins.*

**Cause racine** : trois mécanismes se cumulent pour transformer un échec réel
en succès annoncé.

1. **`set -e` et le pipeline.** `tar -cf - -C "$SRC" . | gzip -9 > "$ARCHIVE"`
   échoue côté `tar` (le fichier `etc/deploy.key` est en `0600 root`,
   illisible), qui sort en 2. `gzip` reçoit ce qu'il a reçu, le compresse et sort
   en 0. Sans `set -o pipefail`, le code du pipeline est celui du **dernier**
   étage : 0. `set -e` n'a rien à arrêter, et l'archive publiée est incomplète.
2. **`local taille=$(du -h ...)`.** `local` est une commande : c'est son code de
   retour qui devient `$?`, jamais celui de `du`. Toute erreur de mesure est
   invisible.
3. **`[ "$taille" -eq 0 ]` sur `120K`.** `-eq` attend un entier ; `du -h` produit
   `120K`. `test` écrit `integer expression expected` et renvoie **2**, ce qui
   n'est pas 0 : la branche `ATTENTION archive vide` n'est jamais prise. Et
   comme cette comparaison est dans une fonction appelée en condition
   (`if verifier_archive; then`), `set -e` y est **désactivé pour tout le corps
   de la fonction** : même une commande en échec ne l'arrêterait pas.

**Diagnostic pas à pas :**

```bash
# 1. lire le journal de la dernière exécution : tout y est déjà
cat ~/lab07/bf2/derniere-execution.log
# tar: ./etc/deploy.key: Cannot open: Permission denied
# tar: Exiting with failure status due to previous errors
# /home/mathieu/lab07/bin/sauve-conf.sh: line 15: [: 120K: integer expression...
# SAUVEGARDE OK (...)          <- le verdict contredit les deux lignes du dessus

# 2. comparer le contenu de l'archive à la source
tar -tzf ~/lab07/bf2/coffre/factura-$(date +%F).tar.gz \
  | grep -v '/$' | sort > /tmp/dans      # sans les répertoires
( cd ~/lab07/bf2/source && find . -type f | sort ) > /tmp/attendu
diff /tmp/attendu /tmp/dans
# < ./etc/deploy.key

# 3. isoler le mécanisme du pipeline, hors du script
bash -c 'set -e; false | true; echo "atteint, code=$?"'
# atteint, code=0
bash -c 'set -eo pipefail; false | true; echo "jamais atteint"'; echo "code=$?"
# code=1

# 4. confirmer le masquage par local
bash -c 'f(){ local t=$(false); echo "code apres local: $?"; }; f'
# code apres local: 0
```

**Correctif :**

```bash
#!/usr/bin/env bash
# sauve-conf.sh — sauvegarde de la configuration, version corrigée.
# Codes : 0 succès, 1 échec de sauvegarde.
set -euo pipefail

BF=${BF:-$HOME/lab07/bf2}
SRC="$BF/source"
DEST="$BF/coffre"
STAMP=$(date +%F)
ARCHIVE="$DEST/factura-$STAMP.tar.gz"

TRAVAIL=$(mktemp -d -t sauve-conf.XXXXXXXX)
trap 'rm -rf -- "$TRAVAIL"' EXIT

mkdir -p "$DEST"
EXCLUS="$TRAVAIL/exclus.lst"

# les fichiers qu'on ne peut pas lire sont exclus EXPLICITEMENT et signalés
find "$SRC" -type f ! -readable -printf './%P\n' > "$EXCLUS"
if [ -s "$EXCLUS" ]; then
  while IFS= read -r x; do
    printf 'ATTENTION : %s illisible, exclu de la sauvegarde\n' "$x" >&2
  done < "$EXCLUS"
fi

echo "sauvegarde de $SRC"
if ! tar -czf "$TRAVAIL/a.tgz" -C "$SRC" --exclude-from="$EXCLUS" .; then
  echo "SAUVEGARDE EN ECHEC : tar a échoué" >&2
  exit 1
fi

# vérification : l'archive est relue, et sa taille comparée à un ENTIER
gzip -t "$TRAVAIL/a.tgz"
taille=$(stat -c '%s' "$TRAVAIL/a.tgz")
if [ "$taille" -lt 1024 ]; then
  echo "SAUVEGARDE EN ECHEC : archive suspecte ($taille octets)" >&2
  exit 1
fi

mv -f -- "$TRAVAIL/a.tgz" "$ARCHIVE"
printf 'SAUVEGARDE OK (%s, %s octets)\n' "$ARCHIVE" "$taille"
```

```console
$ ~/lab07/bin/sauve-conf.sh
ATTENTION : ./etc/deploy.key illisible, exclu de la sauvegarde
sauvegarde de /home/mathieu/lab07/bf2/source
SAUVEGARDE OK (.../bf2/coffre/factura-2026-09-18.tar.gz, 120484 octets)
$ echo $?
0
```

::: pourquoi
Le correctif ne se contente pas d'ajouter `pipefail` : il supprime le pipeline.
`tar -czf fichier` fait la compression lui-même, il n'y a plus deux codes de
retour à réconcilier. Quand un pipeline est inévitable
(`mysqldump | gzip | ssh`), `set -o pipefail` plus `${PIPESTATUS[@]}` restent la
réponse.

Le fichier illisible n'est plus une surprise : il est **détecté avant**
(`find ! -readable`), **signalé** dans le journal, et **exclu explicitement**.
Différence essentielle avec l'original : la sauvegarde est désormais
volontairement partielle et le dit, au lieu d'être accidentellement partielle et
de se taire.

La vérification finale compare un **entier** (`stat -c '%s'`, des octets) à un
entier, et relit l'archive avec `gzip -t` avant publication. Le `mv` n'a lieu
qu'après ces deux contrôles : le coffre ne contient jamais d'archive non
vérifiée.
:::

::: piege
Prévention : une sauvegarde qui ne se restaure pas n'existe pas. Le contrôle
minimal est `tar -tzf` (l'archive est lisible de bout en bout) plus une taille
plancher ; le contrôle sérieux est une restauration périodique dans un
répertoire jetable, comparée à la source par `diff -r`. Et la supervision doit
surveiller la **taille** et la **date** de l'archive produite, pas seulement le
code de retour du script — c'est ce qui aurait levé l'alerte ici dès le premier
matin.
:::

---

### **BF7.3** — *Le déploiement ne rend plus la main.*

**Quatre symptômes, quatre mécanismes distincts.**

**1. La boucle infinie.** Dans le `case` d'analyse des options, la branche
`--verbeux` positionne `VERBEUX=1` mais ne fait **pas** de `shift`. `$1` reste
`--verbeux` indéfiniment, `$#` ne décroît jamais, la condition
`[ $# -gt 0 ]` reste vraie. Symptôme : 100 % d'un cœur, aucune sortie.

```bash
timeout 3 ~/lab07/bin/deploy-conf.sh --env prod \
  --fichier ~/lab07/bf3/modeles/app.ini --verbeux; echo "code=$?"
# code=124  (timeout a dû l'abattre)
bash -x ~/lab07/bin/deploy-conf.sh ... --verbeux 2>&1 | head -20
# + VERBEUX=1   répété à l'infini : la trace montre la boucle
```

**2. `[: 2.1: integer expression expected`.** `VERSION` vaut `2.1`, comparé avec
`-eq`, un opérateur d'entiers. `test` renvoie 2 et le message part sur stderr.
Le script continue, la branche est simplement ignorée.

**3. `Permission denied` sur le fichier temporaire.** `TMP=/tmp/deploy-conf.tmp`
est un nom **fixe**. Un autre compte (ici root) a laissé ce fichier en `0600`.
L'utilisateur courant ne peut plus ni l'écraser ni le lire.

```bash
ls -l /tmp/deploy-conf.tmp
# -rw------- 1 root root 34 ... /tmp/deploy-conf.tmp
```

C'est aussi un trou de sécurité classique : un nom prévisible dans `/tmp`
permet à un tiers d'y déposer un lien symbolique vers un fichier sensible que le
script écrasera avec ses propres droits.

**4. Le hook reçoit 4 arguments.** `"$HOOK" $FICHIER $ENVIRONNEMENT` :
`$FICHIER` non quoté vaut `.../conf de secours.ini`, découpé en trois mots.
Le même défaut fait échouer `grep ^version $FICHIER`, qui cherche trois fichiers
inexistants.

**Correctif :**

```bash
#!/usr/bin/env bash
# deploy-conf.sh — rend un modèle de conf et le pousse, version corrigée.
# Codes : 0 succès, 1 échec, 2 usage.
set -euo pipefail

BF=${BF:-$HOME/lab07/bf3}
HOOK="$BF/post-deploy.sh"
ENVIRONNEMENT=""
FICHIER=""
VERBEUX=0
PROG=${0##*/}

usage() {
  cat <<AIDE
usage: $PROG --env <prod|recette> --fichier <modele> [--verbeux]
AIDE
}

journal() { printf '[%s] %s\n' "$(date +%T)" "$*" >&2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      ENVIRONNEMENT=$2; shift 2 ;;
    --fichier)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      FICHIER=$2; shift 2 ;;
    --verbeux)
      VERBEUX=1; shift ;;            # le shift qui manquait
    -h|--help)
      usage; exit 0 ;;
    *)
      printf 'option inconnue : %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$ENVIRONNEMENT" ] || { echo "--env est obligatoire" >&2; exit 2; }
[ -n "$FICHIER" ]       || { echo "--fichier est obligatoire" >&2; exit 2; }
[ -r "$FICHIER" ]       || { echo "modèle illisible : $FICHIER" >&2; exit 1; }

case "$ENVIRONNEMENT" in
  prod|recette) ;;
  *) echo "environnement inconnu : $ENVIRONNEMENT" >&2; exit 2 ;;
esac

CIBLE="$BF/cible/$ENVIRONNEMENT"
[ -d "$CIBLE" ] || { echo "cible absente : $CIBLE" >&2; exit 1; }

TRAVAIL=$(mktemp -d -t deploy-conf.XXXXXXXX)
trap 'rm -rf -- "$TRAVAIL"' EXIT

VERSION=$(grep '^version' -- "$FICHIER" | cut -d= -f2)
# comparaison de CHAÎNE : une version n'est pas un entier
case "$VERSION" in
  2.*) journal "modèle en version 2 ($VERSION), rendu standard" ;;
  *)   journal "version inattendue : $VERSION" ;;
esac

sed "s/@ENV@/$ENVIRONNEMENT/" -- "$FICHIER" > "$TRAVAIL/rendu.ini"
install -m 644 "$TRAVAIL/rendu.ini" "$CIBLE/app.ini"

[ "$VERBEUX" -eq 0 ] || journal "rendu installé dans $CIBLE/app.ini"
journal "déploiement de $FICHIER vers $ENVIRONNEMENT"

# "$@" : deux arguments restent deux arguments
"$HOOK" "$FICHIER" "$ENVIRONNEMENT"
```

```console
$ ~/lab07/bin/deploy-conf.sh --env recette \
    --fichier ~/lab07/bf3/modeles/'conf de secours.ini' --verbeux
[19:10:34] modèle en version 2 (2.1), rendu standard
[19:10:34] rendu installé dans .../cible/recette/app.ini
[19:10:34] déploiement de .../modeles/conf de secours.ini vers recette
hook appelé avec 2 argument(s) :
  $1 = [/home/mathieu/lab07/bf3/modeles/conf de secours.ini]
  $2 = [recette]
$ echo $?
0
```

::: pourquoi
Le point commun des quatre défauts : **le script faisait confiance à ses
entrées**. L'option qui ne consomme pas d'argument, la version qu'on suppose
entière, le répertoire temporaire qu'on suppose libre, le chemin qu'on suppose
sans espace. La version corrigée remplace chaque supposition par une
vérification explicite, et chaque construction fragile par sa variante sûre :
`shift` dans toutes les branches, `case` pour les motifs de chaîne, `mktemp -d`
plus `trap`, quoting systématique.

Le passage de `cp` à `install -m 644` mérite d'être noté : il pose les droits en
une opération, ce qui évite la fenêtre pendant laquelle le fichier déployé
existe avec les droits hérités du `umask`.
:::

::: piege
Prévention : `shellcheck` ne détecte en une seconde que le défaut de quoting
(SC2086 sur `$FICHIER`, `$TMP` et `$HOOK`), qui couvre le quatrième symptôme. Les trois autres lui échappent : `-eq` sur une variable quotée dont il ne connaît pas la valeur, le nom temporaire fixe, et le `shift` manquant — ce dernier ne se voit qu'à l'exécution, mais un test de non-régression d'une ligne
(`timeout 5 ./deploy-conf.sh --verbeux ... || echo "boucle ?"`) le détecte. La
règle d'équipe qui en découle : aucun script ne part en production sans passer
shellcheck **et** sans un essai avec chaque option documentée.
:::

---

## 7.8 Défi du module

**D7 — Script de sauvegarde de qualité production**

```bash
#!/usr/bin/env bash
# shellcheck disable=SC2317  # fonctions appelées par trap (faux positif)
# sauvegarde.sh — sauvegarde datée + purge de rétention.
# Qualité production : verrou, espace jetable, vérification, rapport.
#
# Codes de sortie :
#   0  succès
#   1  échec de la sauvegarde (archive non produite ou non vérifiable)
#   2  usage incorrect
#   3  source introuvable ou illisible
#   9  une autre instance tourne déjà
#
# Dépendances : bash >= 4, tar, gzip, find, flock, logger (facultatif).
set -euo pipefail

PROG=${0##*/}
SOURCE="$HOME/lab07/depot"
DEST="$HOME/lab07/archives"
CONF="$HOME/lab07/conf/seuils.conf"
RAPPORTS="$HOME/lab07/rapports"
LOCK="$HOME/lab07/var/run/sauvegarde.lock"
TAG=factura-sauvegarde
RETENTION=""
BLANC=0
VERBEUX=0
TRAVAIL=""
PURGEES=0

usage() {
  cat <<EOF
usage: $PROG [options]

  --source REP     arborescence à sauvegarder (défaut : \$HOME/lab07/depot)
  --dest REP       destination des archives (défaut : \$HOME/lab07/archives)
  --retention N    jours de conservation (défaut : retention_jours de
                   $CONF, ou 7)
  --dry-run        affiche ce qui serait fait, ne modifie rien
  --verbeux        trace détaillée sur stderr
  -h, --help       affiche cette aide

Codes : 0 succès, 1 échec, 2 usage, 3 source, 9 déjà en cours.
EOF
}

horodate() { date +%Y-%m-%dT%H:%M:%S%:z; }
emettre()  {
  local niveau=$1
  shift
  printf '%s [%s] %s\n' "$(horodate)" "$niveau" "$*" >&2
  case "$niveau" in
    ERROR) logger -t "$TAG" -p user.err  -- "$*" 2>/dev/null || true ;;
    WARN)  logger -t "$TAG" -p user.warning -- "$*" 2>/dev/null || true ;;
    *)     logger -t "$TAG" -p user.info -- "$*" 2>/dev/null || true ;;
  esac
}
log_info()  { emettre INFO  "$*"; }
log_warn()  { emettre WARN  "$*"; }
log_error() { emettre ERROR "$*"; }
log_debug() {
  [ "$VERBEUX" -eq 1 ] || return 0
  printf '%s [DEBUG] %s\n' "$(horodate)" "$*" >&2
}

nettoyer() {
  local rc=$?
  if [ -n "$TRAVAIL" ] && [ -d "$TRAVAIL" ]; then
    rm -rf -- "$TRAVAIL"
    log_debug "espace de travail supprimé : $TRAVAIL"
  fi
  return "$rc"
}

sur_erreur() {
  trap - ERR
  log_error "échec ligne $1 : commande « $2 »"
}

sur_signal() {
  local nom=$1 num=$2
  trap - EXIT ERR
  log_warn "signal $nom reçu : arrêt propre, pas d'archive partielle"
  nettoyer || true
  exit $((128 + num))
}

mourir() {
  local code=$1
  shift
  trap - ERR
  log_error "$*"
  exit "$code"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source)
      [ "$#" -ge 2 ] || { echo "--source attend un argument" >&2; exit 2; }
      SOURCE=$2; shift 2 ;;
    --dest)
      [ "$#" -ge 2 ] || { echo "--dest attend un argument" >&2; exit 2; }
      DEST=$2; shift 2 ;;
    --retention)
      [ "$#" -ge 2 ] || { echo "--retention attend un argument" >&2; exit 2; }
      RETENTION=$2; shift 2 ;;
    --dry-run) BLANC=1; shift ;;
    --verbeux) VERBEUX=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    *) printf 'option inconnue : %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[ "$#" -eq 0 ] || {
  printf 'argument en trop : %s\n' "$1" >&2
  exit 2
}

# rétention : argument > fichier de conf > valeur par défaut
if [ -z "$RETENTION" ] && [ -f "$CONF" ]; then
  while IFS='=' read -r cle valeur; do
    cle=${cle// /}
    [ "$cle" = "retention_jours" ] || continue
    RETENTION=${valeur// /}
  done < "$CONF"
fi
RETENTION=${RETENTION:-7}

case "$RETENTION" in
  '' | *[!0-9]*)
    echo "rétention non numérique : $RETENTION" >&2
    exit 2 ;;
esac

mkdir -p "$(dirname "$LOCK")"
exec 9>"$LOCK"
if ! flock -n 9; then
  printf '%s [ERROR] instance déjà en cours (verrou %s)\n' \
    "$(horodate)" "$LOCK" >&2
  exit 9
fi

TRAVAIL=$(mktemp -d -t sauvegarde.XXXXXXXX)
trap 'nettoyer' EXIT
trap 'sur_erreur "$LINENO" "$BASH_COMMAND"' ERR
trap 'sur_signal INT 2' INT
trap 'sur_signal TERM 15' TERM

[ -d "$SOURCE" ] || mourir 3 "source introuvable : $SOURCE"
[ -r "$SOURCE" ] || mourir 3 "source illisible : $SOURCE"

STAMP=$(date +%F)
ARCHIVE="$DEST/factura-$STAMP.tar.gz"
RAPPORT="$RAPPORTS/sauvegarde-$STAMP.md"

log_info "source=$SOURCE dest=$DEST rétention=${RETENTION}j dry-run=$BLANC"

NB_FICHIERS=$(find "$SOURCE" -type f | wc -l)

if [ "$BLANC" -eq 1 ]; then
  log_info "[dry-run] archiverait $NB_FICHIERS fichiers dans $ARCHIVE"
  log_info "[dry-run] purgerait $DEST/factura-*.tar.gz de plus de" \
           "$RETENTION jours"
  exit 0
fi

mkdir -p "$DEST" "$RAPPORTS"

# On écrit dans l'espace jetable, on vérifie, puis on publie par un mv :
# à aucun moment $ARCHIVE n'est une archive à moitié écrite.
log_info "archivage de $NB_FICHIERS fichiers"
if ! tar -czf "$TRAVAIL/archive.tar.gz" -C "$SOURCE" .; then
  mourir 1 "tar a échoué, archive non publiée"
fi

if ! tar -tzf "$TRAVAIL/archive.tar.gz" >/dev/null 2>&1; then
  mourir 1 "archive illisible à la relecture, publication annulée"
fi

mv -f -- "$TRAVAIL/archive.tar.gz" "$ARCHIVE"
TAILLE=$(du -h "$ARCHIVE" | cut -f1)
log_info "archive publiée : $ARCHIVE ($TAILLE)"

# -print0 / read -d '' : aucun nom de fichier ne peut casser la boucle.
while IFS= read -r -d '' vieille; do
  log_info "purge : ${vieille##*/}"
  rm -f -- "$vieille"
  PURGEES=$((PURGEES + 1))
done < <(find "$DEST" -maxdepth 1 -type f -name 'factura-*.tar.gz' \
           -mtime +"$RETENTION" -print0)

log_info "$PURGEES archive(s) purgée(s) au-delà de $RETENTION jours"

{
  printf '# Sauvegarde factura — %s\n\n' "$STAMP"
  printf '* source       : %s\n' "$SOURCE"
  printf '* archive      : %s (%s)\n' "$ARCHIVE" "$TAILLE"
  printf '* fichiers     : %s\n' "$NB_FICHIERS"
  printf '* rétention    : %s jours\n' "$RETENTION"
  printf '* purgées      : %s\n' "$PURGEES"
  printf '* hôte         : %s\n' "$(hostname)"
  printf '* code retour  : 0\n'
} > "$RAPPORT"

log_info "rapport écrit : $RAPPORT"
exit 0
```

::: pourquoi
**L'ordre `tar` → vérification → `mv`.** C'est la seule séquence qui garantit
qu'aucun consommateur ne verra jamais une archive invalide. `tar` écrit dans un
répertoire jetable ; `tar -tzf` la relit intégralement (une archive tronquée ou
corrompue échoue ici) ; `mv` la publie par un `rename(2)`, opération **atomique**
tant que source et destination sont sur le même système de fichiers. Si le
script meurt entre les deux premières étapes, le `trap EXIT` supprime le
brouillon et la destination conserve l'archive de la veille — dégradation
acceptable, jamais de corruption.

**Le verrou.** `exec 9>"$LOCK"` puis `flock -n 9` est posé avant toute action
et couvre la totalité de l'exécution, purge comprise : deux instances ne peuvent
pas se marcher dessus au moment où l'une publie et l'autre purge. Le choix de
`-n` (échec immédiat, code 9) plutôt que `-w` (attente) se justifie par le
contexte : une sauvegarde manquée est visible dans la supervision, alors qu'une
file d'attente d'instances masque le problème et finit par saturer la machine.

**La séparation des flux.** Le rapport est un fichier, le journal va sur stderr
et dans syslog, stdout reste vide. Le script est donc utilisable tel quel par un
ordonnanceur qui capture stdout, par un humain qui lit stderr, et par une
collecte centralisée qui suit `journalctl -t factura-sauvegarde`.

**La rétention en cascade** (option > fichier de conf > défaut codé en dur) est
le patron habituel de configuration : elle permet de surcharger ponctuellement
sans modifier la conf, tout en gardant un comportement défini si la conf
disparaît. Sa validation (`case ... *[!0-9]*`) évite qu'une valeur aberrante
n'arrive dans `find -mtime`, où `-mtime +abc` serait une erreur de syntaxe au
milieu du traitement.

**L'idempotence** tient à deux détails : l'archive du jour porte un nom déduit
de la date, donc une seconde exécution la **remplace** au lieu d'accumuler ; et
la purge est exprimée par un critère (`-mtime +N`) qui donne le même résultat
qu'on l'applique une ou dix fois.
:::

::: piege
Les limites à documenter — c'est ce qu'on attend dans
`sauvegarde-notes.md`. `tar -czf` sur 800 Go monopolise un cœur pendant des
heures : on passerait à `zstd -T0` ou à une sauvegarde incrémentale
(`--listed-incremental`), voire à un outil dédié (restic, borg) qui fait la
déduplication et le chiffrement. Le `mv` n'est atomique que **dans le même
système de fichiers** : si la destination est un point de montage distinct,
`mv` devient une copie, et la fenêtre de corruption revient — il faut alors un
fichier temporaire **dans la destination** puis un `mv` local. Enfin le script
ne vérifie pas l'espace disponible avant d'archiver : `df --output=avail` sur la
destination, comparé à la taille de la source, est la pré-condition qui manque
le jour où le disque est plein.
:::

::: astuce
Pour le contrôle final, `bash check_M07_05.sh` exécute le script sur une
destination temporaire, y dépose une archive de 40 jours, une de 2 jours et un
`export final.tar.gz` de 90 jours, puis vérifie que seule la première a disparu.
C'est le test de non-régression minimal à garder quand tu adapteras le motif de
purge.
:::
