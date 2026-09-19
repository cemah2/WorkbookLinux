# Module 07 — Scripting Bash de niveau production

## 7.0 Objectifs et compétences

::: objectif
À la fin de ce module, je sais :

* écrire un script qui s'exécute de la même façon depuis un terminal, un
  `ssh hôte 'commande'` et un planificateur, et expliquer ce que changent
  `./script`, `bash script`, `source script` et `exec` ;
* manipuler les variables spéciales (`$0 $1 $@ $* $# $? $$ $!`), citer sans
  hésiter la différence entre `"$@"` et `"$*"`, et transmettre des arguments
  contenant des espaces sans jamais les casser ;
* remplacer un `sed`/`cut` par une **substitution de paramètre**
  (`${v:-def}`, `${v:?msg}`, `${v#pat}`, `${v%pat}`, `${v//a/b}`, `${v:i:n}`)
  et savoir laquelle assigne, laquelle échoue, laquelle est la plus rapide ;
* choisir entre `[ ]`, `[[ ]]` et `(( ))` en justifiant le choix, et
  reconnaître les tests qui renvoient vrai alors qu'ils devraient échouer ;
* lire un fichier ligne à ligne sans perdre la dernière ligne, sans manger les
  espaces de tête et sans interpréter les antislashs ;
* écrire des fonctions qui retournent un **code** et produisent un **résultat**,
  et dire pourquoi `local` n'est pas un détail de confort ;
* utiliser des tableaux indexés et associatifs pour compter, regrouper et
  itérer proprement (`${arr[@]}`, `${!arr[@]}`, `${#arr[@]}`) ;
* rendre un script robuste : `set -euo pipefail` **et ses trois limites
  connues**, `trap` sur EXIT/ERR/INT/TERM, `mktemp`, verrou `flock`,
  idempotence, codes de sortie conventionnels ;
* offrir une interface : `--help`, parsing manuel `while/case/shift`,
  `getopts`, journalisation horodatée sur stderr et vers syslog ;
* déboguer un script avec `bash -x`, `set -x`, `PS4`, et faire de
  **shellcheck** un passage obligatoire avant toute mise en production ;
* énoncer un critère concret pour arrêter bash et passer à Python ou Ansible.

Temps estimé : 7 h
Prérequis : module 01 (expansions, quoting, redirections), module 02 (FHS),
module 05 (grep/sed/awk utilisés ici comme outils, pas comme sujet).
:::

---

## 7.1 Mise en place

VM concernée : **`lab-adm` (10.10.10.10)**, utilisateur `mathieu`. Les trois
Break & Fix demandent `sudo` pour installer la panne, jamais pour la réparer.

```bash
# depuis le shell Proxmox, avant de commencer
qm snapshot 9001 avant-lab07
```

Paquets nécessaires :

```bash
sudo apt update
sudo apt install -y shellcheck bash-completion util-linux
```

`util-linux` fournit `flock` et `logger` ; il est déjà présent sur une Ubuntu
24.04 standard, la ligne est là pour les images minimales.

::: rhel
Sous Rocky 9, `ShellCheck` (attention à la casse) vient d'EPEL :

```bash
sudo dnf install -y epel-release
sudo dnf install -y ShellCheck util-linux
```
:::

Vérifie que shellcheck répond, c'est un outil du module, pas un bonus :

```bash
shellcheck --version
```

Préparation du terrain de jeu (idempotent, relançable) :

```bash
bash ~/workbook/scripts/setup/setup_M07.sh
```

Il crée `~/lab07/` : des journaux applicatifs (dont un au nom contenant une
espace), un inventaire CSV **sans saut de ligne final**, des archives datées,
un dépôt à sauvegarder et deux scripts volontairement mal écrits.

::: astuce
Travaille avec deux terminaux : l'un pour éditer, l'autre pour exécuter.
Et ajoute dès maintenant à ton éditeur un raccourci qui lance
`shellcheck %` sur le fichier courant — tu vas t'en servir des dizaines de
fois dans ce module.
:::

---

## 7.2 Rappel express

### Anatomie et modes d'exécution

| Invocation | Processus | Effets sur le shell courant |
|---|---|---|
| `./script.sh` | fils, shebang obligatoire + bit `x` | aucun |
| `bash script.sh` | fils, shebang ignoré, `x` inutile | aucun |
| `source script.sh` (`.`) | **le shell courant** | variables, `cd`, `exit` |
| `exec ./script.sh` | remplace le shell courant | le shell disparaît |

`#!/usr/bin/env bash` cherche bash dans le `PATH` (portable, indispensable dès
qu'un bash récent est installé ailleurs que `/bin/bash`) ; `#!/bin/bash` fige
le chemin. Un shebang sans bit `x` donne `Permission denied` ; un fichier avec
des fins de ligne Windows donne `bad interpreter: No such file or directory`.

@fig(bash-anatomie): Squelette d'un script robuste, bloc par bloc, et ce que chaque bloc protège.

### Variables spéciales

| Variable | Contenu |
|---|---|
| `$0` | nom du script tel qu'invoqué (`${0##*/}` pour le basename) |
| `$1`…`$9`, `${10}` | arguments positionnels |
| `$#` | nombre d'arguments |
| `"$@"` | **chaque argument = un mot**, quoting préservé |
| `"$*"` | **tous les arguments = un seul mot**, joints par `${IFS:0:1}` |
| `$?` | code de la dernière commande terminée |
| `$$` / `$!` | PID du shell / PID du dernier processus lancé en arrière-plan |
| `${PIPESTATUS[@]}` | codes de **chaque** étage du dernier pipeline |

Règle : `"$@"` partout, sauf quand tu veux explicitement une seule chaîne
(un message de journal, par exemple).

### Substitutions de paramètres

| Forme | Effet |
|---|---|
| `${v:-def}` | `def` si `v` vide/non défini — **n'assigne pas** |
| `${v:=def}` | idem **et** affecte `def` à `v` |
| `${v:?msg}` | sort du script avec `msg` sur stderr si vide/non défini |
| `${v:+x}` | `x` seulement si `v` est **non** vide |
| `${#v}` / `${#arr[@]}` | longueur de la chaîne / nombre d'éléments |
| `${v#pat}` / `${v##pat}` | coupe le plus court/long préfixe |
| `${v%pat}` / `${v%%pat}` | coupe le plus court/long suffixe |
| `${v/a/b}` / `${v//a/b}` | remplace la 1re / toutes les occurrences |
| `${v:3:5}` | sous-chaîne, offset 3, longueur 5 |
| `${v^^}` / `${v,,}` | majuscules / minuscules |

```bash
f=/var/log/nginx/access.log.1
echo "${f##*/}"      # access.log.1   (basename)
echo "${f%/*}"       # /var/log/nginx (dirname)
echo "${f%.*}"       # ...access.log  (retire la dernière extension)
```

### Tests : trois syntaxes, trois usages

| Construction | Nature | À utiliser pour |
|---|---|---|
| `[ ... ]` | builtin POSIX (`test`) | scripts `#!/bin/sh`, portabilité |
| `[[ ... ]]` | mot-clé bash | tout le reste : `&&`, `\|\|`, `=~`, motifs |
| `(( ... ))` | arithmétique | comparaisons et calculs sur entiers |

```bash
[[ $nom == web-* ]]         # motif glob, pas de quotes autour du motif
[[ $ip =~ ^10\.10\.10\.[0-9]+$ ]]   # regex ERE, jamais de quotes à droite
(( n > 10 && n < 100 ))     # pas de $ nécessaire, comparateurs usuels
[ "$a" = "$b" ]  [ "$n" -eq 3 ]  [ -f f ] [ -d d ] [ -s f ] [ -r f ] [ -x f ]
[ -z "$v" ] / [ -n "$v" ]   # vide / non vide — TOUJOURS quoter dans [ ]
```

Dans `[[ ]]`, les variables ne subissent ni découpage ni globbing : le quoting
est facultatif. Dans `[ ]`, il est **obligatoire** : `[ -n $v ]` avec `v` vide
devient `[ -n ]`, qui est vrai. `-eq` compare des **entiers** : `[ "$v" -eq 1 ]`
avec `v="1.0"` ou `v="prod"` échoue avec `integer expression expected`.

### Boucles et lecture de fichiers

```bash
for f in "$REP"/*.log; do ... done          # glob : jamais de découpage
for ((i = 0; i < 10; i++)); do ... done      # style C
while IFS= read -r ligne; do ... done < "$f" # LA forme correcte
while IFS=';' read -r a b c reste; do ... done < "$f"
while IFS= read -r -d '' f; do ... done < <(find . -print0)
case "$1" in --env) ...;; -h|--help) ...;; *) ...;; esac
```

`IFS=` empêche de perdre les espaces de tête et de fin ; `-r` empêche
l'interprétation des antislashs ; le dernier champ de `read` reçoit **tout le
reste** de la ligne. Une dernière ligne sans `\n` final est perdue, sauf avec
`while ... || [ -n "$ligne" ]`. Et un `while read` **à droite d'un pipe** tourne
dans un sous-shell : les variables modifiées dedans sont perdues à la sortie.

### Fonctions, portée, tableaux

```bash
traiter() {
  local hote=$1 rc=0            # local : sinon la variable est globale
  local sortie
  sortie=$(ssh "$hote" uptime) || rc=$?   # PAS local sortie=$(...)
  printf '%s\n' "$sortie"       # le RÉSULTAT sort sur stdout
  return "$rc"                  # le CODE sort par return (0-255)
}
res=$(traiter lab-web) || echo "échec code $?"

declare -a liste=(a b c)           ; liste+=(d)
declare -A par_env                 ; par_env[prod]=4
echo "${liste[@]}" "${#liste[@]}"  # éléments, nombre
echo "${!par_env[@]}"              # les CLÉS d'un tableau associatif
for k in "${!par_env[@]}"; do echo "$k=${par_env[$k]}"; done
```

`local sortie=$(cmd)` masque le code de retour de `cmd` : `local` est une
commande, c'est **son** code qui devient `$?`. Déclare d'abord, affecte ensuite.

### Robustesse

| Option | Ce qu'elle fait | Ce qu'elle ne fait pas |
|---|---|---|
| `set -e` | quitte si une commande sort ≠ 0 | ignoré dans `if`, `while`, `&&`, `!`, et dans toute fonction appelée en condition |
| `set -u` | erreur sur variable non définie | ne détecte pas une variable **vide** |
| `set -o pipefail` | le pipeline prend le pire code | ne dit pas **quel** étage a échoué (`${PIPESTATUS[@]}`) |

```bash
trap 'rm -rf -- "$TRAVAIL"' EXIT           # nettoyage garanti
trap 'echo "échec ligne $LINENO : $BASH_COMMAND" >&2' ERR
trap 'echo interrompu >&2; exit 130' INT
TRAVAIL=$(mktemp -d)                       # jamais /tmp/monscript.tmp
exec 9>"$LOCK"; flock -n 9 || exit 9       # une seule instance
```

Codes de sortie : `0` succès, `1` erreur générique, `2` usage incorrect,
`126` non exécutable, `127` commande introuvable, `128+n` tué par le signal
`n` (`130` = Ctrl-C, `143` = SIGTERM). Choisis tes propres codes métier entre
3 et 113 et **documente-les dans l'aide**.

### Débogage

```bash
bash -x script.sh                  # trace tout
set -x ... set +x                  # trace une zone précise
export PS4='+ ${BASH_SOURCE##*/}:$LINENO:${FUNCNAME[0]:-main}() '
bash -n script.sh                  # analyse syntaxique, sans exécuter
shellcheck -x script.sh            # l'analyseur statique, non négociable
```

### Les sept pièges qui reviennent en production

1. `$var` non quoté → découpage sur les espaces **et** globbing.
2. `for f in $(ls)` → casse sur les espaces, à remplacer par un glob ou `find -print0`.
3. `cd $rep` sans test → la suite s'exécute dans le mauvais répertoire.
4. `rm -rf "$dir/"` avec `dir` vide → `rm -rf /`. `set -u` + `${dir:?}` sauvent.
5. `[ "$s" -eq 0 ]` sur une chaîne → erreur silencieuse et test faux.
6. `set -e` + pipeline sans `pipefail` → l'échec du premier étage est invisible.
7. Fichier temporaire à nom fixe → collision, écrasement, lien symbolique piégé.

---

## 7.3 Quiz — QCM

**Q7.1** — Le script `args.sh` contient :

```bash
#!/usr/bin/env bash
compte() { echo "$#"; }
compte "$@"
compte "$*"
```

Tu l'appelles avec `./args.sh un "deux trois"`. Qu'affiche-t-il ?

a) `2` puis `2`
b) `2` puis `1`
c) `3` puis `1`
d) `1` puis `2`

**Q7.2** — Un script commence par `set -e` (sans `pipefail`) :

```bash
set -e
grep -q ERREUR /etc/hostname | tee /tmp/r.txt
echo "on continue"
```

`grep` ne trouve rien et sort en 1. Que se passe-t-il ?

a) le script s'arrête avant `echo`
b) `on continue` est affiché, le script poursuit
c) le script s'arrête avec le code 1 après `echo`
d) bash affiche un avertissement puis s'arrête

**Q7.3** — Dans un script avec `set -u`, quelle ligne **échoue** si `CIBLE`
n'est pas définie ? **Deux réponses correctes.**

a) `echo "${CIBLE:-/srv/defaut}"`
b) `echo "$CIBLE"`
c) `echo "${CIBLE:?cible obligatoire}"`
d) `echo "${CIBLE:+actif}"`

**Q7.4** — `f=""` puis :

```bash
if [ -n $f ]; then echo "non vide"; else echo "vide"; fi
```

Qu'affiche-t-on, et pourquoi ?

a) `vide`, le test est correct
b) `non vide`, parce que `$f` non quoté disparaît et `[ -n ]` teste la chaîne `-n`
c) une erreur `unary operator expected`
d) `vide`, mais `[[ -n $f ]]` afficherait `non vide`

**Q7.5** — Ce fragment compte les lignes d'erreur :

```bash
n=0
grep ERROR ~/lab07/logs/app-2026-09-16.log | while read -r l; do
  n=$((n + 1))
done
echo "$n"
```

Qu'affiche le `echo` final ?

a) 44
b) 0
c) 1
d) le nombre de lignes du fichier entier

**Q7.6** — Dans une fonction :

```bash
verifier() {
  local taille=$(du -sb "$1" | cut -f1)
  return $?
}
```

Quel est le problème principal ?

a) `du -sb` n'existe pas
b) `$?` contient le code de `local`, toujours 0 : l'échec de `du` est masqué
c) `local` ne fonctionne pas avec une substitution de commande
d) il manque `declare -i`

**Q7.7** — Après `tar -cf - /srv | gzip > a.gz` où `tar` échoue et `gzip`
réussit, avec `set -euo pipefail` actif :

a) le script s'arrête, le pipeline sort en 2
b) le script continue, le pipeline sort en 0
c) `${PIPESTATUS[0]}` vaut 0 et `${PIPESTATUS[1]}` vaut 2
d) `gzip` n'est pas exécuté

**Q7.8** — Le répertoire `~/lab07/logs` contient 8 fichiers, dont
`rapport final.log`. Combien d'itérations font ces deux boucles ?

```bash
for f in $(ls ~/lab07/logs); do n=$((n+1)); done      # A
for f in ~/lab07/logs/*; do m=$((m+1)); done          # B
```

a) A = 8, B = 8
b) A = 9, B = 8
c) A = 8, B = 9
d) A = 9, B = 9

**Q7.9** — `declare -A par_env; par_env[prod]=4; par_env[dev]=1`.
Quelle commande affiche `dev prod` (les clés) ?

a) `echo "${par_env[@]}"`
b) `echo "${!par_env[@]}"`
c) `echo "${#par_env[@]}"`
d) `echo "${par_env[*]:0}"`

**Q7.10** — Un script crée son espace de travail avec
`TRAVAIL=$(mktemp -d)` puis installe `trap 'rm -rf "$TRAVAIL"' EXIT`.
L'utilisateur fait `Ctrl-C` pendant l'exécution. Que se passe-t-il ?

a) rien n'est nettoyé, `EXIT` ne couvre pas les signaux
b) le répertoire est supprimé : `INT` non intercepté termine le shell, ce qui
   déclenche le trap `EXIT`
c) le trap `EXIT` se déclenche deux fois
d) `rm` échoue car `$TRAVAIL` n'est plus défini

**Q7.11** — `while getopts ':d:s:vh' opt; do` — que signifie le **premier**
deux-points, celui qui est en tête de la chaîne ?

a) que `-d` attend un argument
b) que les erreurs sont silencieuses : à toi de traiter `?` et `:` dans le `case`
c) que `getopts` accepte les options longues
d) qu'il faut au moins une option

**Q7.12** — `charge="4.00"` puis `if [ "$charge" -gt 2 ]; then ...`. Résultat ?

a) le test est vrai, 4.00 > 2
b) `bash: [: 4.00: integer expression expected`, et le test est faux
c) le test est faux silencieusement
d) bash convertit automatiquement en entier : 4 > 2, donc vrai

**Q7.13** — `f="factura-2026-09-18.tar.gz"`. Que vaut `"${f%%.*}"` ?

a) `factura-2026-09-18.tar`
b) `factura-2026-09-18`
c) `gz`
d) `tar.gz`

**Q7.14** — Une fonction doit rendre une valeur calculée à l'appelant.
**Deux réponses sont correctes.**

a) `return "$valeur"` puis `res=$?`
b) `printf '%s\n' "$valeur"` puis `res=$(fonction)`
c) affecter une variable globale déclarée par l'appelant
d) `exit "$valeur"` puis `res=$?`

**Q7.15** — `exec 9>"$LOCK"; flock -n 9 || exit 9`. Que se passe-t-il si le
script est tué par `kill -9` en plein travail ?

a) le verrou reste posé, plus aucune exécution n'est possible
b) le noyau libère le verrou à la fermeture du descripteur, donc à la mort du
   processus
c) il faut supprimer le fichier de verrou à la main
d) le verrou expire au bout de 60 secondes

**Q7.16** — Tu lis un fichier de mots de passe généré ailleurs :

```bash
while read ligne; do echo "[$ligne]"; done < creds.txt
```

Sur la ligne `  admin\test  `, qu'affiche le script ?

a) `[  admin\test  ]`
b) `[admin\test]`
c) `[admintest]`
d) `[  admintest  ]`

**Q7.17** — Un script `deploy.sh` fait `cd /srv/app` puis `rm -rf ./cache`.
Le répertoire `/srv/app` a été renommé. Que se passe-t-il **sans** `set -e` ?

a) rien, `rm` échoue proprement
b) `cd` échoue, le script continue dans le répertoire courant et supprime
   `./cache` là où il se trouve
c) bash s'arrête sur l'échec du `cd`
d) `rm -rf` refuse de s'exécuter sur un chemin relatif

**Q7.18** — Tu veux qu'un script définisse `PROXY` dans ton shell interactif
courant. Quelle invocation ? **Deux réponses correctes.**

a) `./env.sh`
b) `bash env.sh`
c) `source env.sh`
d) `. env.sh`

---

## 7.4 Quiz — questions ouvertes

**QO7.1** — Explique, en raisonnant sur ce que reçoit le programme appelé,
la différence entre `"$@"`, `$@`, `"$*"` et `$*`. Donne un cas de production où
la confusion détruit silencieusement un déploiement.

::: repondre
lignes: 8
:::

**QO7.2** — *On te demande en entretien* : « `set -euo pipefail` en tête de
script, c'est suffisant pour parler de script robuste ? » Réponds en citant
**trois** situations concrètes où chacune des trois options ne protège pas, et
ce que tu ajoutes pour combler chaque trou.

::: repondre
lignes: 12
:::

**QO7.3** — Compare `[ ]`, `[[ ]]` et `(( ))` : nature de chacun, ce qui est
permis dans l'un et pas dans l'autre, et ce que tu utilises dans un script
`#!/bin/sh` livré à un client. Illustre avec un test qui donne un résultat
différent selon la syntaxe.

::: repondre
lignes: 8
:::

**QO7.4** — Décris précisément les quatre pièges de la lecture d'un fichier
ligne à ligne en bash (le pipe, `IFS`, `-r`, la dernière ligne) et donne la
forme canonique qui les évite tous. Pourquoi `for ligne in $(cat f)` est-il
pire que tout ?

::: repondre
lignes: 8
:::

**QO7.5** — *On te demande en entretien* : « Un script de purge a supprimé
toute une arborescence de production la nuit dernière. Il contenait
`rm -rf "$BASE/$SOUS"/*`. Explique ce qui a pu se passer et liste les gardes
que tu aurais mises. » Réponds comme en entretien : cause, preuve, gardes.

::: repondre
lignes: 10
:::

**QO7.6** — Explique le mécanisme de `flock` : sur quoi porte réellement le
verrou, pourquoi `exec 9>fichier` puis `flock -n 9` plutôt que `flock fichier
commande`, et ce qui libère le verrou quand le script meurt brutalement.
Compare avec l'approche « fichier PID » et dis pourquoi elle est inférieure.

::: repondre
lignes: 8
:::

**QO7.7** — Tu reprends un script de 400 lignes qui « marche quand on le lance
à la main mais échoue en automatique ». Décris ta démarche de diagnostic dans
l'ordre, en citant les outils (`bash -x`, `PS4`, `shellcheck`, journalisation)
et ce que tu cherches dans chaque sortie.

::: repondre
lignes: 10
:::

**QO7.8** — Donne **trois critères concrets et mesurables** qui te font dire :
« ce script bash doit devenir du Python ou de l'Ansible ». Pour chaque critère,
explique ce que bash fait mal et ce que l'autre outil fait mieux.

::: repondre
lignes: 8
:::

---

## 7.5 Exercices guidés ★

Sauf mention contraire, travaille dans `~/lab07`. Chaque script que tu écris
doit passer `shellcheck` sans avertissement : c'est la règle du module.

**E7.1** — `~/lab07/bin/bonjour.sh` existe mais `./bonjour.sh` répond
`Permission denied`. Fais-le fonctionner de **trois** manières différentes :
une sans modifier le fichier, une en le modifiant, une en changeant
l'interpréteur invoqué. Explique pour chacune ce qui s'exécute réellement.

**E7.2** — Lance `~/lab07/bin/portee.sh` successivement avec `./`, avec `bash`
et avec `source`. Après chaque essai, affiche `$PWD`, `$MARQUEUR` et `$$` dans
ton shell. Produis un tableau à trois colonnes qui résume ce qui a changé.

**E7.3** — Écris `~/lab07/bin/args.sh` qui affiche, dans cet ordre : le nom du
script sans son chemin, le nombre d'arguments, chaque argument numéroté sur sa
propre ligne, et le PID du script. Vérifie-le avec
`./args.sh un "deux trois" 'quatre  cinq'` : il doit annoncer 3 arguments.

**E7.4** — À partir de `f=/var/log/nginx/access.log.1`, obtiens avec des
**substitutions de paramètres uniquement** (aucun appel externe) : le nom de
fichier seul, le répertoire, le nom sans le suffixe `.1`, le nom sans aucune
extension, et la chaîne en majuscules.

**E7.5** — Écris un fragment qui affecte à `DEST` la valeur de `$1` si elle est
fournie, sinon `/srv/factura`, **et** qui interrompt le script avec un message
explicite si `$1` vaut la chaîne vide `""` explicitement passée. Montre la
différence entre `${1-def}` et `${1:-def}` dans ce cas précis.

**E7.6** — Toujours sans appel externe, écris une fonction `extension` qui,
pour `factura-2026-09-18.tar.gz`, renvoie `gz`, et une fonction `souche` qui
renvoie `factura-2026-09-18`. Teste-les sur un nom sans extension.

**E7.7** — Écris trois tests qui échouent tous en `[ ]` non quoté mais
réussissent en `[[ ]]` ou avec un quoting correct : un sur une variable vide,
un sur une variable contenant une espace, un sur une comparaison numérique
avec une valeur non entière. Montre la sortie d'erreur de chacun.

**E7.8** — Compte les lignes de `~/lab07/data/serveurs.txt` avec
`while read -r`. Tu vas trouver 6 au lieu de 7. Corrige la boucle pour
récupérer la dernière ligne, sans modifier le fichier.

**E7.9** — Affiche, à partir de `~/lab07/data/inventaire.csv`, uniquement les
hôtes dont l'environnement est `prod`, au format `hote (ip)`. L'en-tête ne doit
pas apparaître et le rôle `frontal web` ne doit pas être découpé.

**E7.10** — Lis `~/lab07/conf/seuils.conf` et charge chaque `clé=valeur` dans
un tableau associatif `SEUILS`, en ignorant les commentaires et les lignes
vides. Affiche ensuite `disque_max=85` en lisant le tableau.

**E7.11** — Écris une fonction `pair_impair` qui prend un entier, affiche
`pair` ou `impair` sur stdout et renvoie `0` pour pair, `1` pour impair.
Appelle-la dans un `if` puis récupère sa sortie dans une variable. Explique
pourquoi les deux usages ne se mélangent pas.

**E7.12** — Construis un tableau indexé avec les noms des journaux de
`~/lab07/logs` (le nom à espace compris), affiche son nombre d'éléments, son
troisième élément, puis parcours-le en affichant l'indice et la valeur.

**E7.13** — Écris un script qui crée un répertoire temporaire avec `mktemp -d`,
y écrit un fichier, puis sort en erreur au milieu. Prouve, avec et sans `trap`,
que le répertoire survit dans un cas et pas dans l'autre.

**E7.14** — Écris `~/lab07/bin/essai-signaux.sh` qui boucle en affichant un
point toutes les secondes, intercepte `INT` pour afficher `arrêt demandé` et
sortir en 130, et `TERM` pour sortir en 143. Vérifie les deux codes avec
`echo $?` puis avec `kill -TERM`.

**E7.15** — Relis `~/lab07/casse/compte-erreurs.sh`. Sans l'exécuter, liste par
écrit **cinq** défauts distincts, puis fais-les confirmer par `shellcheck` et
note le code `SCxxxx` associé à chacun.

**E7.16** — Réécris `~/lab07/casse/menage.sh` pour qu'il soit sûr : refus de
s'exécuter sans argument, refus d'une cible hors de `/tmp/travail`, `cd` testé,
et aucun `rm -rf` sur une variable non validée. Prouve qu'il refuse
`./menage.sh ""` et `./menage.sh ../../etc`.

---

## 7.6 Labs ★★

### **L7.1** — Squelette de script de service : rapport d'erreurs

::: contexte
L'exploitation reçoit chaque matin un mail illisible fabriqué par un `grep`
lancé à la main. On te demande le script de référence de l'équipe : interface
propre, journalisation séparée du résultat, codes de sortie exploitables par le
superviseur. C'est ce squelette que tous les scripts du service reprendront.
:::

Écris `~/lab07/bin/rapport-erreurs.sh`.

1. Shebang `#!/usr/bin/env bash`, `set -euo pipefail`, bit d'exécution.
2. Options traitées par **`getopts`** :
   * `-d <répertoire>` : répertoire des journaux (défaut `$HOME/lab07/logs`) ;
   * `-s <seuil>` : seuil d'alerte (défaut `25`) ;
   * `-v` : trace détaillée ; `-h` : aide sur stdout, sortie `0`.
3. Fonctions `log_info`, `log_warn`, `log_error` qui écrivent sur **stderr**,
   horodatées au format ISO (`2026-09-18T14:02:11+02:00`). Le **rapport**, lui,
   sort sur **stdout** et nulle part ailleurs.
4. Le rapport : une ligne `nom_du_fichier;nombre_d_erreurs` par fichier `*.log`
   du répertoire, trié par nombre décroissant. `rapport final.log` doit
   apparaître avec son espace, sur une seule ligne.
5. Codes de sortie : `0` aucun fichier au-dessus du seuil, `1` au moins un
   dépassement, `2` usage incorrect (option inconnue, seuil non numérique),
   `3` répertoire inexistant.
6. `shellcheck -x` ne doit rien signaler.
7. Vérifie que `rapport-erreurs.sh > rapport.csv` produit un CSV propre, sans
   la moindre ligne de journal.

::: check
Critère de succès : `./rapport-erreurs.sh -s 25 > /tmp/r.csv` renvoie 1, la
première ligne de `/tmp/r.csv` est `app-2026-09-16.log;44`, et
`./rapport-erreurs.sh -s 100` renvoie 0.

```bash
bash check_M07_01.sh
```
:::

---

### **L7.2** — Exploiter l'inventaire CSV du parc

::: contexte
L'inventaire du parc est un CSV exporté par un outil tiers :
séparateur `;`, un champ contenant des espaces, une ligne avec un champ
surnuméraire (`a-decommissionner`) et — cadeau de l'exportateur — **pas de
saut de ligne à la fin du fichier**. Trois personnes ont déjà écrit un script
qui compte 9 machines au lieu de 10.
:::

Écris `~/lab07/bin/inventaire.sh` qui lit `~/lab07/data/inventaire.csv`.

1. Lecture ligne à ligne avec `while IFS=';' read -r ...`, en ignorant la ligne
   d'en-tête et en récupérant la dernière ligne malgré l'absence de `\n`.
2. Compte les hôtes par environnement dans un **tableau associatif**.
3. Collecte dans un **tableau indexé** les hôtes dont le 5e champ est non vide
   (les machines à décommissionner).
4. Produit exactement cette structure, les environnements triés par ordre
   alphabétique :

```text
== Hôtes par environnement ==
dev;1
outillage;2
prod;4
recette;3
== À décommissionner ==
cache-01
== Total ==
10
```

5. Le même contenu, à l'identique, est écrit dans
   `~/lab07/rapports/inventaire.txt` **et** affiché à l'écran, en une seule
   passe de lecture.
6. Options : `-f <csv>`, `-o <rapport>`, `-h`. Code `4` si le CSV est
   introuvable. Deux exécutions successives donnent le même résultat.

::: astuce
`read` affecte **tout le reste de la ligne** à sa dernière variable. Choisis
donc bien le nombre de variables si tu veux distinguer « 4 champs » de
« 5 champs ».
:::

::: check
Critère de succès : la sortie contient `outillage;2` et `10` — pas `outillage;1`
ni `9`.

```bash
bash check_M07_02.sh
```
:::

---

### **L7.3** — Collecte robuste : verrou, espace jetable, nettoyage garanti

::: contexte
Le script de collecte des journaux tourne toutes les 15 minutes. Deux fois par
mois, une exécution déborde sur la suivante : deux instances écrivent dans le
même fichier temporaire et l'archive produite est inutilisable. On trouve aussi
des dizaines de `/tmp/collecte.XXXX` abandonnés, parce que le script sort par
cinq chemins différents et n'en nettoie qu'un.
:::

Écris `~/lab07/bin/collecte.sh`.

1. Options **longues**, en parsing manuel `while/case/shift` (pas `getopts`) :
   `--source REP` (défaut `$HOME/lab07/logs`), `--dest REP`
   (défaut `$HOME/lab07/archives`), `--dry-run`, `--verbeux`, `--help`.
2. Exécution unique garantie par `flock -n` sur
   `$HOME/lab07/var/run/collecte.lock`. Une seconde instance ne travaille pas :
   elle écrit un message sur stderr et sort avec le code **9**.
3. Espace de travail créé par `mktemp -d`, supprimé par un `trap` sur `EXIT`,
   **quel que soit le chemin de sortie** (succès, erreur, `--dry-run`, source
   absente, signal).
4. `trap` sur `ERR` qui journalise le numéro de ligne et la commande fautive.
5. Collecte de tous les `*.log` du répertoire source, y compris les noms
   contenant une espace, vers `<dest>/collecte-AAAA-MM-JJ.tar.gz`.
   L'archive est d'abord écrite dans l'espace de travail puis déplacée :
   à aucun moment l'archive finale ne doit exister à moitié écrite.
6. `--dry-run` annonce ce qui serait fait et ne crée rien. Codes : `0`, `2`
   (usage), `3` (source absente), `9` (verrou).
7. Deux exécutions de suite doivent réussir toutes les deux.

::: attention
Pour tester le verrou sans attendre le hasard, ouvre un second terminal et
prends-le à la main :
`( exec 9>~/lab07/var/run/collecte.lock; flock -n 9 && sleep 60 )`
puis lance le script dans le premier.
:::

::: check
Critère de succès : l'archive du jour contient les 8 journaux dont
`rapport final.log`, `ls -d /tmp/collecte.*` ne renvoie rien après une série
d'exécutions réussies **et** ratées, et le script sort en 9 quand le verrou est
déjà pris.

```bash
bash check_M07_03.sh
```
:::

---

### **L7.4** — Enveloppe d'exécution : journalisation, codes, signaux

::: contexte
Tous les jobs du service sont lancés par des mécanismes différents, chacun avec
sa propre façon de journaliser — ou pas. On te demande une enveloppe unique :
elle exécute n'importe quelle commande, trace son début et sa fin dans un
journal local **et** dans syslog, rend exactement le code de la commande, et se
comporte correctement quand l'ordonnanceur envoie `SIGTERM`.
:::

Écris `~/lab07/bin/exec-tracee.sh`.

1. Interface : `exec-tracee.sh [-t tag] [-f fichier] -- commande [args...]`.
   Tout ce qui suit `--` est la commande. Sans commande : usage sur stderr,
   code `2`.
2. Les arguments sont transmis **intacts** : `exec-tracee.sh -- printf
   '[%s]\n' 'a b' c` doit afficher exactement deux lignes, `[a b]` et `[c]`.
3. Journal local (défaut `$HOME/lab07/var/exec.log`) et stderr : une ligne de
   début et une ligne de fin, horodatées ISO, avec le code de retour et la
   durée. La sortie de la commande, elle, n'est ni préfixée ni réordonnée.
4. Chaque évènement part aussi vers syslog avec `logger -t <tag>`, en
   `user.info` si succès, `user.err` si échec. Vérifie avec
   `journalctl -t factura -n 10`.
5. Le code de sortie de l'enveloppe est **exactement** celui de la commande :
   `exec-tracee.sh -- sh -c 'exit 7'` renvoie 7.
6. `INT` et `TERM` sont interceptés : l'enveloppe tue la commande fille, trace
   l'interruption, et sort en `130` / `143`. Aucun processus fils ne survit.

::: astuce
Pour pouvoir attraper un signal pendant l'exécution, la commande fille doit
tourner en arrière-plan et l'enveloppe l'attendre : `"$@" &` puis `wait "$!"`.
Un `wait` interrompu par un signal rend la main au gestionnaire de trap.
:::

::: check
Critère de succès : `exec-tracee.sh -- sh -c 'exit 7'; echo $?` affiche 7, et
un `kill -TERM` sur l'enveloppe pendant `-- sleep 30` donne 143 sans laisser de
`sleep` orphelin.

```bash
bash check_M07_04.sh
```
:::

---

## 7.7 Break & Fix ★★★

::: attention
Avant chaque Break & Fix : `qm snapshot 9001 avant-bf07`. Le snapshot de
secours reste `snap-clean`, mais l'utiliser vaut échec : ici, on répare du
**code**, pas un système. Dans les trois cas, le script fautif est livré tel
quel dans `~/lab07/bin/` : c'est lui qu'il faut lire, comprendre et corriger.
:::

### **BF7.1** — « La purge nocturne a tout effacé »

```bash
sudo bash break_M07_01.sh
```

**Symptôme utilisateur** : la purge nocturne
(`~/lab07/bin/purge-archives.sh`) devait ne toucher qu'au sous-répertoire
`prod` et n'y supprimer que les archives de plus de 7 jours. Au matin,
`~/lab07/bf1/archives` est **entièrement vide** : `prod` et `recette` ont
disparu, y compris l'archive d'hier. Le script n'a affiché aucune erreur et
s'est terminé sur `purge terminee` avec le code 0.

**Interdit** : restaurer les archives depuis une sauvegarde externe, réécrire
le script depuis zéro (on veut un correctif ligne à ligne, justifiable en
revue de code), modifier `purge.conf` pour contourner le problème.

**Objectif** : remettre le jeu de données à zéro avec
`bash ~/lab07/bf1/restaure-jeu.sh`, identifier **la** ligne qui a causé
l'effacement total, expliquer pourquoi ni le shell ni le script n'ont protesté,
corriger, puis prouver que le script ne supprime plus que les fichiers de plus
de 7 jours du seul sous-répertoire visé. Le script corrigé doit aussi traiter
correctement `dump du soir.tar.gz` — vérifie ce qu'il en fait avant ta
correction. Enfin, liste les trois gardes que tu ajoutes pour qu'un `$SOUS`
vide ne puisse plus jamais produire cet effet.

::: repondre
lignes: 12
:::

### **BF7.2** — « La sauvegarde dit OK tous les matins, et pourtant »

```bash
sudo bash break_M07_02.sh
```

**Symptôme utilisateur** : `~/lab07/bin/sauve-conf.sh` affiche
`SAUVEGARDE OK` et sort en 0 chaque nuit. Mais la restauration de l'archive
produite dans `~/lab07/bf2/coffre/` ne rend pas l'arborescence complète : il
manque des fichiers. Le journal de la dernière exécution est dans
`~/lab07/bf2/derniere-execution.log`.

**Interdit** : modifier les droits du fichier source qui pose problème (il est
géré par une autre équipe et doit rester en `0600 root`), supprimer ce fichier,
lancer le script en root.

**Objectif** : expliquer pourquoi `set -e` n'a pas arrêté le script alors qu'une
commande a bel et bien échoué — il y a **trois** mécanismes distincts à
identifier, pas un seul. Corriger le script pour qu'il détecte l'échec, sorte
en code non nul, et n'écrive pas d'archive incomplète dans le coffre. La
sauvegarde doit ensuite se terminer proprement en excluant le fichier illisible,
avec un avertissement explicite dans le journal.

::: repondre
lignes: 12
:::

### **BF7.3** — « Le déploiement ne rend plus la main »

```bash
sudo bash break_M07_03.sh
```

**Symptôme utilisateur** : `~/lab07/bin/deploy-conf.sh` ne déploie plus rien
et sort quand même en 0.

* avec `--verbeux`, il ne rend jamais la main et occupe 100 % d'un cœur ;
* sans `--verbeux`, il affiche `[: 2.1: integer expression expected` ;
* il n'arrive pas à écrire son fichier temporaire : `Permission denied` ;
* avec le modèle `~/lab07/bf3/modeles/conf de secours.ini`, `grep` cherche
  trois fichiers inexistants et le hook `post-deploy.sh` annonce recevoir
  4 arguments au lieu de 2.

**Interdit** : supprimer `/tmp/deploy-conf.tmp` à la main comme correctif
définitif (tu peux le faire pour reproduire, mais la solution ne peut pas être
« passer derrière tous les matins »), renommer les modèles pour enlever les
espaces.

**Objectif** : traiter les quatre symptômes un par un. Pour chacun : la ligne
fautive, le mécanisme bash en cause, le correctif. Le script corrigé doit
déployer `conf de secours.ini` vers `recette`, transmettre exactement deux
arguments au hook, ne laisser aucun fichier temporaire derrière lui, et sortir
en code non nul quand le déploiement échoue.

::: repondre
lignes: 12
:::

---

## 7.8 Défi du module ★★★

**D7 — Un script de sauvegarde que tu accepterais de mettre en production**

::: contexte
Le dépôt `~/lab07/depot` contient la configuration et les données de
l'application factura. On te demande le script de sauvegarde officiel du
service : celui qui tournera toutes les nuits sur les cinq VM du lab, dont
personne ne devra se méfier, et qui passera la revue de code d'une équipe
qui a déjà vécu BF7.1, BF7.2 et BF7.3.
:::

Cahier des charges de `~/lab07/bin/sauvegarde.sh` :

1. `#!/usr/bin/env bash`, `set -euo pipefail`, exécutable, **shellcheck muet**.
2. Interface :
   * `--source REP` (défaut `$HOME/lab07/depot`) ;
   * `--dest REP` (défaut `$HOME/lab07/archives`) ;
   * `--retention N` (défaut : la valeur de `retention_jours` lue dans
     `~/lab07/conf/seuils.conf`, sinon 7) ;
   * `--dry-run`, `--verbeux`, `-h|--help`.
3. L'aide liste les **codes de sortie** : `0` succès, `1` échec de sauvegarde,
   `2` usage, `3` source introuvable, `9` instance déjà en cours. Une rétention
   non numérique sort en 2.
4. Exécution unique par `flock -n`. Espace de travail `mktemp -d` nettoyé par
   `trap EXIT` ; `trap ERR` qui journalise ligne et commande ; `trap INT/TERM`
   qui sort en 130/143 sans laisser d'archive partielle.
5. L'archive `factura-AAAA-MM-JJ.tar.gz` est produite dans l'espace de travail,
   **relue** (`tar -tzf`) pour validation, puis publiée par un `mv`. Si `tar`
   échoue ou si la relecture échoue : code 1, rien n'est publié.
6. Purge de rétention : uniquement les `factura-*.tar.gz` de la destination
   plus vieux que N jours. Un fichier nommé `export final.tar.gz` doit
   survivre. Utilise `find -print0` et `while IFS= read -r -d ''`.
7. Journalisation : `log_info`/`log_warn`/`log_error` horodatés ISO sur stderr,
   et un envoi vers syslog avec `logger -t factura-sauvegarde` à la bonne
   priorité. **Aucune** ligne de journal sur stdout.
8. Rapport Markdown `~/lab07/rapports/sauvegarde-AAAA-MM-JJ.md` : source,
   archive et taille, nombre de fichiers, rétention appliquée, nombre
   d'archives purgées, hôte, code de retour.
9. `--dry-run` n'écrit **rien** : ni archive, ni rapport, ni purge.
10. Idempotent : deux exécutions à la suite réussissent, la seconde remplace
    proprement l'archive du jour.

Livrable : le script, plus un court `~/lab07/rapports/sauvegarde-notes.md` qui
justifie tes choix sur trois points — l'ordre `tar` → vérification → `mv`, la
gestion du verrou, et ce que tu ferais différemment si le dépôt faisait 800 Go.

Temps visé : 60 à 90 minutes.

::: check
```bash
bash check_M07_05.sh
```
:::

---

## 7.9 Auto-évaluation

| Compétence | Acquis | À revoir |
|---|---|---|
| Choisir entre `./script`, `bash script`, `source` | ☐ | ☐ |
| Expliquer `"$@"` vs `"$*"` et transmettre des arguments | ☐ | ☐ |
| Utiliser les substitutions de paramètres au lieu d'un `cut` | ☐ | ☐ |
| Choisir `[ ]`, `[[ ]]` ou `(( ))` à bon escient | ☐ | ☐ |
| Lire un fichier ligne à ligne sans perdre de données | ☐ | ☐ |
| Écrire une fonction avec code de retour **et** résultat | ☐ | ☐ |
| Compter et regrouper avec des tableaux associatifs | ☐ | ☐ |
| Citer les limites de `set -euo pipefail` | ☐ | ☐ |
| Garantir le nettoyage avec `trap` et `mktemp` | ☐ | ☐ |
| Garantir l'exécution unique avec `flock` | ☐ | ☐ |
| Proposer une interface `--help` + codes de sortie documentés | ☐ | ☐ |
| Journaliser sur stderr et vers syslog sans polluer stdout | ☐ | ☐ |
| Déboguer avec `bash -x`, `PS4` et shellcheck | ☐ | ☐ |

Pour aller plus loin :

* Lis la section **SHELL BUILTIN COMMANDS** de `man bash` pour `trap`, `wait`,
  `read` et `getopts` : trois pages qui couvrent la moitié de ce module.
* Fais passer `shellcheck` sur tous les scripts déjà en place sur `lab-ops`
  (`find /usr/local/bin /opt -name '*.sh'`) et classe les avertissements par
  gravité réelle. Tu découvriras que `SC2086` est presque toujours un vrai bug.
* Compare ton `sauvegarde.sh` avec un rôle Ansible équivalent : compte les
  lignes, le temps d'écriture, et ce que tu perds ou gagnes en lisibilité.
* Installe `bats` (Bash Automated Testing System) et écris trois tests
  unitaires pour les fonctions de ton défi. Un script testable est un script
  bien découpé.
