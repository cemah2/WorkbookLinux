# Module 05 — Corrigé

Tous les chiffres de ce corrigé ont été obtenus sur le jeu de données produit par
`setup_M05.sh`. Il est déterministe : tu dois trouver **exactement** les mêmes.
Si un chiffre diffère, c'est ta commande qui est en cause, pas le hasard.

---

## 5.3 Quiz — QCM

**Q5.1 — b)** Le pipeline renvoie 0.

::: pourquoi
Le code retour d'un pipeline est, par défaut, celui de son **dernier** maillon.
`grep` renvoie bien 1 (« rien trouvé »), mais `wc -l` s'exécute sans problème,
affiche `0` et sort en 0. C'est le mécanisme qui fait qu'un script de sauvegarde
« réussit » toujours. Deux façons de voir la vérité :

```bash
grep 'ERROR' /var/log/app.log | wc -l
echo "${PIPESTATUS[@]}"      # -> 1 0
set -o pipefail              # le pipeline renvoie alors 1
```

`PIPESTATUS` est un tableau volatil : il est écrasé par la commande suivante, donc
il faut le lire **immédiatement** après le pipeline.
:::

**Q5.2 — b)** A journalise les deux flux, B seulement stdout.

::: pourquoi
Le tube est construit avant que bash n'interprète les redirections du dernier
maillon. Dans A, `2>&1` est appliqué à `./maj.sh` : son stderr est dupliqué vers
son stdout, qui est déjà le tube. Dans B, `2>&1` porte sur `tee` : ça redirige
stderr **de tee** vers le terminal, ce qui ne change rien à `maj.sh`, dont les
erreurs continuent d'aller à l'écran sans passer par le fichier.
:::

**Q5.3 — c)** Quatre lignes : `1 b`, `1 a`, `1 b`, `1 a`.

::: pourquoi
`uniq` ne compare que des lignes **adjacentes** : c'est un filtre à une ligne de
mémoire, pas un moteur de déduplication globale. Aucune ligne n'est identique à sa
voisine ici, donc chaque groupe a un effectif de 1. Avec `sort` devant, on obtient
`2 a` et `2 b`. C'est pour ça que le top N s'écrit toujours
`… | sort | uniq -c | sort -rn | head`.
:::

**Q5.4 — b)** `-k9` va du champ 9 à la fin de la ligne.

::: pourquoi
`-kN` sans borne de fin signifie « de la position N jusqu'à la fin de
l'enregistrement ». Sur `serveurs.csv`, `-k9` fabrique donc la clé
`francfort,153.60` et compare l'ensemble comme du texte : à site égal, les serveurs
sortent classés par coût **lexicographique** (`153.60` avant `168.00`). Avec
`-k9,9` la clé est `francfort` seul, et à égalité GNU sort applique sa comparaison
de dernier recours sur la ligne entière : le classement se fait alors par hostname.
Vérifie :

```bash
diff <(sort -t, -k9,9 serveurs.csv) <(sort -t, -k9 serveurs.csv)   # non vide
```
:::

::: piege
Le second piège de ce fichier est son en-tête, trié avec les données. Avec `-nr`,
la ligne `hostname,env,…` vaut 0 et finit en bas, ce qui passe inaperçu — jusqu'au
jour où tu tries en ordre croissant. Prends l'habitude de `tail -n +2 fichier`.
:::

**Q5.5 — c)** `awk '$1 == "10.10.10.14" { n++ } END { print n+0 }'`.

::: pourquoi
C'est la seule forme qui compare le **champ** attendu à une valeur exacte. Les trois
autres cherchent une sous-chaîne n'importe où dans la ligne — or une IP peut aussi
apparaître dans le referer ou dans l'URL. En prime, dans a) et d) les points ne sont
pas échappés : ce sont des méta-caractères qui matchent n'importe quel caractère,
donc `10x10y10z14` conviendrait. Sur notre jeu de données les quatre renvoient 1212,
et c'est exactement ce qui rend l'erreur dangereuse : elle ne se voit pas.
:::

**Q5.6 — b)** `GET /panier`.

::: pourquoi
`-o` n'affiche que la portion de ligne qui correspond au motif, une occurrence par
ligne de sortie. Le motif `GET [^ ]*` commence au `G` (le guillemet qui précède n'en
fait pas partie) et `[^ ]*` s'arrête au premier espace. C'est la combinaison qui
sert à extraire un champ quand la position varie :
`grep -oE 'from [0-9.]+'` sur un journal SSH, par exemple.

À ne pas confondre avec `-c`, qui compte les **lignes** contenant au moins une
correspondance : une ligne portant `ERROR ERROR` compte pour 1. Pour compter les
occurrences, c'est `grep -o motif | wc -l`.
:::

**Q5.7 — b)** `sed -i.bak 's/30s/60s/g' shop.conf`.

::: pourquoi
`-i` prend son suffixe **collé** (`-i.bak`, jamais `-i .bak` sous GNU sed), et le
drapeau `g` est indispensable pour remplacer toutes les occurrences d'une ligne, pas
seulement la première. La réponse a) oublie `g`. La c) modifie le fichier de
sauvegarde. La d) invente une option inexistante.
:::

::: piege
`sed -i` sans suffixe réécrit le fichier **en place et sans filet** : le fichier
d'origine n'existe plus, et si ton expression est fausse, tu l'apprends en
production. Sur un fichier que tu ne peux pas régénérer, teste toujours sans `-i`
d'abord, puis applique avec `-i.bak`.
:::

**Q5.8 — b)** Les lignes entre `server {` et la première `}` en début de ligne,
bornes incluses.

::: pourquoi
`sed` accepte un adressage `/motif1/,/motif2/` : la plage s'ouvre sur la ligne qui
correspond à `motif1` et se referme sur la **première** ligne suivante qui
correspond à `motif2`, les deux incluses. `-n` coupe l'affichage automatique et `p`
n'imprime que la plage. Si `motif2` n'apparaît jamais, la plage court jusqu'à la fin
du fichier — c'est le comportement, pas un bug.
:::

**Q5.9 — c)** `4`.

::: pourquoi
`s` est un tableau associatif indexé par la valeur du premier champ. Les lignes
`a 1` et `a 3` alimentent la même case : `s["a"] = 1 + 3 = 4`. En awk, un tableau ni
une variable ne se déclarent : toute case inconnue vaut la chaîne vide, qui vaut 0
en contexte numérique. C'est ce mécanisme qui rend l'accumulateur par clé aussi
court à écrire — et c'est la structure la plus utile de tout le module.
:::

**Q5.10 — b)** `NR` vaut 5, `FNR` vaut 2.

::: pourquoi
`NR` compte les enregistrements depuis le début de l'exécution, tous fichiers
confondus ; `FNR` repart à 1 à chaque nouveau fichier. L'égalité `NR == FNR` n'est
donc vraie que pendant la lecture du **premier** fichier : c'est le test qui permet
de charger une table de correspondance avant de traiter les données.
:::

**Q5.11 — b)** `awk` ne connaît pas le quoting CSV.

::: pourquoi
`-F,` découpe sur chaque virgule, sans savoir qu'une virgule entre guillemets fait
partie de la valeur. Sur `serveurs-piege.csv` :

```bash
awk -F, '{ print $2 }' serveurs-piege.csv
proprietaire
"Equipe Paiement
"Equipe Data"
"Equipe Front
```

Pour du CSV réellement quoté, il faut un vrai parseur (`python3 -c 'import csv…'`,
`mlr --icsv`, `csvcut` du paquet `csvkit`). `awk -F,` reste parfait pour du CSV
**que tu génères toi-même** et dont tu garantis qu'aucun champ ne contient de
virgule — ce qui est le cas de `serveurs.csv`.
:::

**Q5.12 — b)** `jq -r '.results[] | select(.env=="prod") | .hostname' f.json`.

::: pourquoi
`.results[]` itère sur les éléments du tableau ; sans les crochets (réponse c), on
applique `select` à un tableau et non à chaque objet. La réponse d) applique le
`select` à une chaîne, qui n'a pas de champ `.env`. `-r` (raw) supprime les
guillemets de sortie : indispensable dès que le résultat alimente une autre
commande.
:::

**Q5.13 — b)** `file script.sh`.

::: pourquoi
`file` répond `Bourne-Again shell script, ASCII text executable, with CRLF line
terminators` : le diagnostic tient en une ligne. `bash -x` montre l'erreur mais pas
sa cause, `head -1` n'affiche rien de visible (le `\r` est invisible), `stat` ne dit
rien du contenu. L'autre commande qui tranche est `cat -A`, qui affiche `^M` en fin
de ligne.
:::

**Q5.14 — a) et c)** stderr ne traverse pas le tube ; `cmd1 2>&1 | cmd2` l'y fait
entrer.

::: pourquoi
Un tube relie le fd 1 de gauche au fd 0 de droite. Le fd 2 reste attaché à sa
destination d'origine, en général le terminal. Pour capturer les erreurs, il faut
les dupliquer vers le fd 1 **de la commande de gauche** : `cmd1 2>&1 | cmd2`.
Dans la réponse d), la redirection porte sur `cmd2` : elle ne change rien à ce que
`cmd1` envoie dans le tube.
:::

**Q5.15 — b)** `comm -23 hosts-cmdb.txt hosts-supervision.txt`.

::: pourquoi
`comm` produit trois colonnes : ce qui est propre au fichier 1, ce qui est propre au
fichier 2, ce qui est commun. Les options **suppriment** les colonnes : `-23`
supprime les colonnes 2 et 3, il ne reste que « propre au fichier 1 ». `-13` donne
l'inverse, `-12` les communs. Condition absolue : les deux fichiers doivent être
triés avec le **même** ordre de tri, sinon `comm` produit des résultats faux en
silence (il se contente d'avertir sur stderr).
:::

**Q5.16 — b) et c)** `-P 4` lance jusqu'à 4 processus en parallèle, et leurs sorties
peuvent s'entremêler.

::: pourquoi
`-n 20` fixe le nombre d'arguments par appel, `-P 4` le nombre d'appels simultanés.
Les deux se combinent : 4 `gzip` tournent en même temps, chacun sur 20 fichiers.
L'ordre de traitement n'est plus garanti, et si les commandes écrivent sur stdout,
les lignes de plusieurs processus peuvent se mélanger. Sur du calcul pur, `-P
$(nproc)` divise le temps d'exécution par le nombre de cœurs ; sur du disque, ça
peut au contraire tout ralentir.
:::

**Q5.17 — b)** Avec `<<'EOF'`, rien n'est développé.

::: pourquoi
Quoter le délimiteur (`<<'EOF'`, `<<"EOF"` ou `<<\EOF`) désactive l'expansion des
variables, des substitutions de commande et de l'arithmétique dans le corps du
here-doc. C'est ce qu'on veut pour écrire un script, une configuration contenant des
`$variables` littérales, ou un mot de passe. La suppression des tabulations de tête,
c'est `<<-`, et ça ne marche qu'avec de vraies tabulations, pas des espaces.
:::

**Q5.18 — b)** `diff <(ssh lab-web dpkg -l) <(ssh lab-db dpkg -l)`.

::: pourquoi
`diff` attend des **chemins de fichiers**. `$(cmd)` remplace la commande par sa
sortie, que `diff` interprète alors comme des noms de fichiers : réponse a) exclue.
`<<<` alimente stdin, dont `diff` n'a qu'un exemplaire : réponse c) exclue. La
substitution de processus `<(cmd)` crée un descripteur `/dev/fd/63` que `diff`
ouvre comme un fichier ordinaire. La réponse d) fonctionne aussi, mais elle mélange
deux styles et n'accepte qu'un seul flux via `-`.
:::

---

## 5.4 Quiz — questions ouvertes

**QO5.1** — *Différence entre `cmd > f 2>&1` et `cmd 2>&1 > f`.*

Bash lit les redirections **de gauche à droite** et les applique dans l'ordre.

```text
cmd > f 2>&1        cmd 2>&1 > f
  1: terminal -> f     1: terminal
  2: terminal          2: terminal -> copie de la cible de 1 = terminal
  puis 2 -> cible      puis 1 -> f
     actuelle de 1 = f
  résultat : 1 -> f, 2 -> f     résultat : 1 -> f, 2 -> terminal
```

::: pourquoi
`2>&1` ne signifie pas « fusionne 2 et 1 » mais « fais pointer le fd 2 vers la
destination **actuelle** du fd 1 ». C'est une copie de descripteur (`dup2`) faite au
moment de la lecture, pas un lien permanent : changer le fd 1 après coup ne change
pas le fd 2.

Cas réel où `cmd 2>&1 > f` est exactement ce qu'on veut : un traitement dont la
sortie utile est volumineuse et doit aller dans un fichier, pendant que les
avertissements doivent rester visibles pour l'opérateur (ou être capturés par un
autre pipeline). Exemple : `pg_dump base 2>&1 > dump.sql | mail -s 'erreurs' ops@`
envoie le dump dans le fichier et les erreurs dans le tube.
:::

**QO5.2** — *« Notre sauvegarde se termine toujours en succès. »*

Le pipeline `pg_dump … | gzip > dump.sql.gz` renvoie le code de `gzip`. Si
`pg_dump` échoue, il écrit une erreur sur stderr et sort en 1, mais `gzip` compresse
sans broncher les zéro octet qu'il reçoit et sort en 0 : le script « réussit » et
produit une archive vide de 20 octets.

Correction 1 :

```bash
set -o pipefail
pg_dump base | gzip > dump.sql.gz
```

Correction 2, sans `pipefail` (utile en `sh` POSIX) :

```bash
pg_dump base | gzip > dump.sql.gz
codes=( "${PIPESTATUS[@]}" )
[ "${codes[0]}" -eq 0 ] || { echo "pg_dump a échoué" >&2; exit 1; }
```

::: pourquoi
La troisième protection, complémentaire, est de vérifier le **résultat** et pas
seulement le code retour : taille minimale de l'archive, `gzip -t` pour tester
l'intégrité, et restauration périodique. Un code retour ne prouve pas qu'une
sauvegarde est restaurable.
:::

**QO5.3** — *Extraire la troisième colonne : `grep`, `sed` ou `awk` ?*

```bash
cut -d, -f3 f.csv                  # le plus simple, séparateur fixe
awk -F, '{ print $3 }' f.csv       # tolère -F'[,;]', filtre, calcule
sed -E 's/^([^,]*,){2}([^,]*).*/\2/' f.csv   # possible, illisible
grep -oE '^([^,]*,){2}[^,]*' f.csv # extrait 3 colonnes, pas LA 3e
```

::: pourquoi
`grep` n'est pas un extracteur de colonnes : il travaille sur des correspondances,
pas sur une structure, et il faut se battre pour isoler un champ. `sed` sait le
faire avec des groupes, mais l'expression devient illisible dès qu'on change de
numéro de colonne. `awk` a été écrit pour ça : les champs sont une notion native,
le code reste lisible, et on peut filtrer et calculer dans la même passe. En revue
de code, j'interdis la version `sed` à groupes multiples : elle est juste, mais
personne ne saura la modifier dans six mois.
:::

**QO5.4** — *Décortiquer `awk '{print $1}' | sort | uniq -c | sort -rn | head -10`.*

| Maillon | Rôle |
|---|---|
| `awk '{ print $1 }'` | ne garde que l'IP, une par ligne |
| `sort` | regroupe les lignes identiques (prérequis de `uniq`) |
| `uniq -c` | remplace chaque groupe par `effectif valeur` |
| `sort -rn` | classe par effectif numérique décroissant |
| `head -10` | ne garde que les dix premiers |

Sans le premier `sort`, `uniq -c` ne voit que des voisins et compte des groupes de
1 : le résultat ressemble au journal d'origine, avec un `1` devant chaque ligne.

::: pourquoi
Coût : `sort` doit matérialiser l'ensemble des clés, il déborde sur disque
(`/tmp`) au-delà de sa mémoire tampon, ce qui écroule les performances sur 40 Go.
Alternatives : compter directement en mémoire avec un tableau associatif — une
seule passe, mémoire proportionnelle au nombre d'IP distinctes et non au nombre de
lignes :

```bash
awk '{ n[$1]++ } END { for (k in n) print n[k], k }' access.log \
  | sort -rn | head
```

Et si le volume l'impose : `LC_ALL=C sort -S 2G --parallel=4`, ou un outil
distribué. `LC_ALL=C` seul accélère souvent `sort` et `grep` d'un facteur 2 à 5,
parce qu'on sort des comparaisons UTF-8.

Dans la même logique, on n'ouvre jamais un pipeline par `cat fichier |` : `grep`,
`awk` et `sort` savent ouvrir un fichier. Le `cat` ajoute un processus et un tube,
fait perdre à `grep` le nom du fichier dans ses messages, et sur plusieurs
gigaoctets recopie inutilement toutes les données en espace utilisateur.
:::

**QO5.5** — *Un `sort -k2 -n` incohérent en production.*

1. **La locale.** `LC_ALL` diffère entre ton poste et le serveur : l'ordre de
   collation change, les séparateurs de milliers aussi. Commande qui tranche :
   `locale` sur les deux machines, puis comparer `sort` et `LC_ALL=C sort`.
2. **La borne de clé.** `-k2` va du champ 2 à la fin de ligne ; si les données de
   production ont une colonne de plus, la clé n'est plus la même. Commande :
   `awk '{ print NF }' fichier | sort -u`.
3. **Le séparateur.** Sans `-t`, `sort` découpe sur des suites de blancs et ignore
   les blancs de tête ; un fichier aligné à la tabulation et un fichier aligné à
   l'espace ne donnent pas les mêmes champs. Commande : `cat -A fichier | head`.

::: pourquoi
Un quatrième suspect classique : des valeurs non numériques dans la colonne (`N/A`,
champ vide, `1,5` avec une virgule décimale). `sort -n` les traite comme 0 et les
regroupe en tête, sans avertissement. `grep -vE '^[0-9.]+$'` sur la colonne les
débusque. En script, fixe explicitement `LC_ALL=C` : c'est la seule locale
reproductible.
:::

**QO5.6** — *`$(cmd)`, `<<<`, `<(cmd)`.*

| Forme | Ce qu'elle produit | Cas où elle est seule possible |
|---|---|---|
| `$(cmd)` | une **chaîne** substituée dans la ligne | `v=$(date +%F)` : on veut une valeur |
| `<<< "$v"` | un **flux** sur stdin | `read a b <<< "$ligne"` : on nourrit stdin |
| `<(cmd)` | un **chemin** `/dev/fd/63` | `diff <(a) <(b)` : deux fichiers en même temps |

::: pourquoi
`$(cmd)` ne convient pas à `diff` : une commande qui attend un nom de fichier
recevrait le contenu. `<<<` ne convient pas non plus, car une commande n'a qu'un
stdin. Inversement, `<(cmd)` ne convient pas quand on veut une valeur dans une
variable. Deux détails qui font la différence en entretien : `$(cmd)` supprime les
retours à la ligne finaux, et `<<< "$v"` ajoute un `\n` final. `<(…)` est du bash,
pas du POSIX : sous `dash`, il faut des fichiers temporaires ou des FIFO.
:::

**QO5.7** — *Pourquoi refuser `grep -o '"version":"[^"]*"'` sur du JSON.*

Trois cas concrets qui cassent :

1. Le JSON est reformaté : `"version": "2.7.1"` avec une espace après les deux
   points, ou réparti sur deux lignes — `grep` travaille ligne à ligne, plus rien
   ne correspond.
2. Le mot `version` apparaît ailleurs : `"agent_version"`, `"version_min"`, ou dans
   une chaîne de description. Le motif matche tout.
3. La valeur n'est pas une chaîne (`"version": 3`) ou contient un guillemet
   échappé (`"nom": "jeu \"pro\""`) : `[^"]*` s'arrête au mauvais endroit.

Proposition : `jq -r '.version'`, ou `jq -r '.results[].agent.version'` si c'est
imbriqué.

::: pourquoi
La règle générale : un format structuré se lit avec un outil qui connaît sa
grammaire. `grep` et `sed` ne voient que des lignes de texte, et tout format qui
autorise des retours à la ligne libres, des espaces libres et de l'échappement leur
échappe. Cela vaut pour JSON (`jq`), YAML (`yq`), XML (`xmlstarlet`), CSV quoté
(`csvkit`, `mlr`). Le jour où l'API change son indentation, le script à `grep`
tombe en panne sans erreur : il renvoie du vide, et le vide se propage.
:::

**QO5.8** — *Démarche pour « pourquoi le site était lent hier entre 14 h et 16 h ».*

```bash
cd ~/lab05
# 1. le volume a-t-il augmenté ? (pic de trafic ?)
awk '{ print substr($4, 14, 2) }' access.log | sort | uniq -c | sort -k2,2
# 2. quels endpoints, sur la tranche concernée ?
awk '$4 ~ /:1[45]:/ { u = $7; sub(/\?.*/, "", u); print u }' access.log \
  | sort | uniq -c | sort -rn | head
# 3. lesquels sont lents ? (moyenne et max par endpoint)
awk '$4 ~ /:1[45]:/ { u = $7; sub(/\?.*/, "", u)
       n[u]++; s[u] += $NF; if ($NF > m[u]) m[u] = $NF }
     END { for (k in n) if (n[k] > 20)
             printf "%7.3f %7.3f %5d %s\n",
               s[k]/n[k], m[k], n[k], k }' access.log \
  | sort -rn | head
# 4. est-ce corrélé à des erreurs ? (5xx par heure)
awk '$9 ~ /^5/ { print substr($4, 14, 2) }' access.log | sort | uniq -c
# 5. un client unique est-il responsable ? (top IP sur la tranche)
awk '$4 ~ /:1[45]:/ { print $1 }' access.log \
  | sort | uniq -c | sort -rn | head -5
# 6. le volume de données a-t-il explosé ? (octets par heure)
awk '{ o[substr($4, 14, 2)] += $10 }
     END { for (h in o)
             printf "%s %.1f Mio\n", h, o[h]/1048576 }' access.log | sort
```

::: pourquoi
Chaque étape répond à une question et élimine une hypothèse : (1) charge, (2)
périmètre, (3) latence, (4) erreurs, (5) abus d'un client, (6) bande passante.
L'ordre compte : on cherche d'abord à savoir si le problème vient de la demande
(plus de trafic) ou de l'offre (même trafic, temps de réponse dégradé). Le
`$request_time` est la donnée décisive — sans lui, un `access.log` ne dit rien sur
la performance, et c'est pourquoi on l'ajoute au `log_format` de nginx avant d'en
avoir besoin.
:::

**QO5.9** — *Le mécanisme de `awk 'NR==FNR { … ; next } { … }'`.*

`NR` compte toutes les lignes lues, `FNR` repart à 1 par fichier : l'égalité n'est
vraie que pour le premier fichier. On y charge une table en mémoire, puis on traite
le second fichier en consultant la table.

```bash
awk -F, 'NR == FNR { dc[$1] = $2; next }
         { print $1, dc[$9] }' sites.csv serveurs.csv
```

::: pourquoi
`next` est indispensable : sans lui, les lignes du premier fichier tomberaient aussi
dans le second bloc (qui n'a pas de motif, donc s'applique à toutes les lignes) et
produiraient des sorties parasites. `next` passe immédiatement à l'enregistrement
suivant, comme un `continue` de boucle.

Si le premier fichier est **vide**, `NR == FNR` n'est jamais vraie et la condition
se comporte correctement… mais la table reste vide, et chaque consultation renvoie
la chaîne vide, silencieusement. Prémunition : vérifier en `END` que la table a été
chargée (`if (!(cle in dc)) print "correspondance manquante: " $9 > "/dev/stderr"`),
ou tester la taille du fichier avant. Autre piège : si les deux fichiers sont le
**même** fichier, `NR == FNR` reste vraie tout du long.
:::

**QO5.10** — *Cinq causes de panne d'un CSV venu d'un tableur.*

| Cause | Diagnostic | Correctif |
|---|---|---|
| Fins de ligne CRLF | `file f.csv` / `cat -A f.csv` | `sed -i 's/\r$//' f.csv` |
| Encodage latin-1 | `file -i f.csv` | `iconv -f ISO-8859-1 -t UTF-8 f.csv > g.csv` |
| BOM UTF-8 en tête | `head -c3 f.csv \| od -An -tx1` | `sed -i '1s/^\xEF\xBB\xBF//' f.csv` |
| Séparateur `;` | `head -1 f.csv` | `awk -F';'` ou `tr ';' ','` |
| Champs quotés à virgules | `grep '"' f.csv` | parseur CSV réel, pas `awk -F,` |

::: pourquoi
Les trois premières causes sont invisibles à l'œil nu : `cat` affiche exactement la
même chose avant et après correction. C'est ce qui les rend coûteuses en temps. Le
réflexe à acquérir est de commencer toute analyse d'un fichier reçu par
`file fichier` puis `head -3 fichier | cat -A`. Deux commandes, cinq secondes, et
la moitié des incidents de ce type disparaît. En sortie, impose la règle inverse :
tout ce que tu produis est en UTF-8 sans BOM, en LF, et documenté.
:::

---

## 5.5 Exercices guidés

**E5.1** — *15 dernières lignes puis suivi ; pourquoi `-f` perd le fichier après
rotation.*

```bash
tail -n 15 -F ~/lab05/access.log
```

::: pourquoi
`tail -f` suit un **descripteur de fichier**. Quand logrotate renomme
`access.log` en `access.log.1` et crée un nouveau `access.log`, le descripteur
ouvert continue de pointer sur l'ancien inode : `tail` reste branché sur un fichier
que plus personne n'alimente, sans le moindre message. `-F` (équivalent de
`--follow=name --retry`) suit le **nom** : il détecte que le fichier a été remplacé,
rouvre le nouveau et affiche `tail: 'access.log' has been replaced`. Sur un serveur,
c'est toujours `-F` qu'on veut. À combiner avec `grep --line-buffered` pour filtrer
en direct sans subir la bufferisation :
`tail -F access.log | grep --line-buffered ' 500 '`.
:::

**E5.2** — *Répartition des codes HTTP.*

```bash
awk '{ print $9 }' access.log | sort | uniq -c | sort -rn
```

```text
   5906 200
    491 304
    353 404
    176 403
    139 401
     52 500
     35 502
     33 410
     15 503
```

::: pourquoi
Le triptyque `sort | uniq -c | sort -rn` est la structure de base de toute analyse
de log. Le premier `sort` regroupe, `uniq -c` compte, le second `sort -rn` classe.
Version en une seule passe, sans le double tri, utile sur les gros fichiers :
`awk '{ n[$9]++ } END { for (k in n) print n[k], k }' access.log | sort -rn`.
:::

**E5.3** — *Top 10 des IP, hors sonde et hors scanner.*

```bash
grep -vE '^(10\.10\.10\.14|203\.0\.113\.242) ' access.log \
  | awk '{ print $1 }' | sort | uniq -c | sort -rn | head -10
```

```text
    685 198.51.100.12
    680 203.0.113.5
    363 198.51.100.150
    356 192.0.2.99
    348 203.0.113.42
    348 192.0.2.14
    342 192.0.2.201
    339 198.51.100.104
    338 198.51.100.31
    323 203.0.113.19
```

::: pourquoi
L'ancre `^` et l'espace final ne sont pas décoratifs : sans eux, on exclurait aussi
les lignes où ces adresses apparaissent dans le referer ou l'URL. Les points sont
échappés pour qu'ils ne matchent pas n'importe quel caractère. Variante sans `grep`,
en une passe :
`awk '$1 != "10.10.10.14" && $1 != "203.0.113.242" { n[$1]++ } END { … }'`.
:::

::: piege
Filtrer les sondes de monitoring **avant** de calculer des moyennes est
indispensable : ici `/health` représente 991 requêtes à 2 ms. Les laisser dans le
calcul divise le temps de réponse moyen global par deux et te fait conclure que
« tout va bien » pendant que les vrais clients attendent.
:::

**E5.4** — *URL distinctes en 404, et top 5.*

```bash
awk '$9 == 404 { print $7 }' access.log | sort -u | wc -l        # -> 91
awk '$9 == 404 { print $7 }' access.log | sort | uniq -c | sort -rn | head -5
```

```text
     46 /phpmyadmin/index.php
     41 /.git/config
     39 /vendor/phpunit/phpunit/eval-stdin.php
     36 /wp-login.php
     35 /admin/config.php
```

::: pourquoi
`sort -u` dédoublonne sans compter, `sort | uniq -c` compte. Les 91 URL distinctes
se répartissent entre six chemins d'attaque très demandés et une longue traîne de
`/produit/<id>` inexistants. Un top 5 de 404 dominé par `/wp-login.php` et `/.env`
sur un site qui n'est ni WordPress ni PHP, c'est la signature d'un scanner
automatique : ce n'est pas un problème applicatif, c'est du bruit de fond d'internet.
:::

**E5.5** — *Comptes humains de `passwd.exemple` et comptage par shell.*

```bash
awk -F: '$3 >= 1000 && $3 < 60000 { printf "%-18s %5d %s\n", $1, $3, $7 }' \
  passwd.exemple | sort -k2,2n
cut -d: -f7 passwd.exemple | sort | uniq -c | sort -rn
```

```text
mathieu             1000 /bin/bash
sabrina             1001 /bin/bash
karim               1002 /bin/bash
elodie              1003 /bin/zsh
...
appmail             1602 /bin/false

     13 /usr/sbin/nologin
     12 /bin/bash
      2 /bin/false
      1 /bin/zsh
      1 /bin/sync
      1 /bin/sh
```

::: pourquoi
La borne haute (`< 60000`) exclut `nobody` (65534), qui a un UID « humain » par
accident historique. `printf` dans awk permet d'aligner sans dépendre de `column`.
Le tri `-k2,2n` porte sur la seule colonne UID : sans la borne de fin, la clé
inclurait le shell et l'ordre changerait à UID égal. Pour un audit réel, la question
utile n'est pas « qui est humain » mais « qui peut ouvrir un shell » :
`awk -F: '$7 ~ /sh$/' passwd.exemple`.
:::

**E5.6** — *Tris sur `serveurs.csv`.*

```bash
sort -t, -k10,10nr serveurs.csv | head -5 | cut -d, -f1,10
tail -n +2 serveurs.csv | sort -t, -k2,2 -k10,10nr | cut -d, -f1,2,10 | head -8
```

```text
web-pre-58,505.60
proxy-pro-09,472.00
proxy-pro-17,457.60
web-pro-35,457.60
proxy-dev-27,452.80

proxy-dev-27,dev,452.80
worker-dev-36,dev,388.80
worker-dev-14,dev,345.60
cache-dev-41,dev,331.20
api-dev-46,dev,328.00
```

::: pourquoi
Deux clés successives : `-k2,2` trie d'abord par environnement en ordre
alphabétique (dev, preprod, prod), puis `-k10,10nr` départage à environnement égal
par coût numérique décroissant. Les options de type (`n`, `r`) se collent à la clé
concernée : écrites globalement (`sort -nr -k2,2 -k10,10`), elles s'appliqueraient
aux deux clés et le tri par environnement deviendrait numérique — donc nul, puisque
`dev` vaut 0. Le `tail -n +2` écarte l'en-tête.
:::

**E5.7** — *Extraire les IP sans `awk` ni `cut`.*

```bash
grep -oE '^([0-9]{1,3}\.){3}[0-9]{1,3}' access.log | sort -u | wc -l    # -> 17
grep -oE '^([0-9]{1,3}\.){3}[0-9]{1,3}' access.log | wc -l         # -> 7200
```

::: pourquoi
`-o` n'affiche que la partie correspondante, `-E` active les regex étendues, ce qui
permet le groupe répété `([0-9]{1,3}\.){3}`. L'ancre `^` garantit qu'on prend l'IP
cliente en début de ligne et pas une adresse quelconque ailleurs. Le second compte
(7200 = nombre de lignes) sert de contrôle : si `grep -o` renvoie moins de lignes
que le fichier n'en contient, c'est que des lignes ne correspondent pas au format
attendu, et il faut comprendre pourquoi avant d'aller plus loin.
:::

**E5.8** — *Requêtes API de plus de 2 secondes, et la plus lente.*

```bash
awk '$7 ~ /^\/api\// && $NF > 2' access.log | wc -l          # -> 181
awk '{ printf "%s %s %s\n", $NF, substr($4, 2), $7 }' access.log \
  | sort -rn | head -1
```

```text
9.683 14/Sep/2026:17:21:04 /api/v1/cart/items
```

::: pourquoi
`$NF` désigne le dernier champ, ce qui évite de compter les colonnes du format
combined — et surtout de se tromper quand un user-agent contient des espaces (il en
contient toujours). La comparaison `$NF > 2` force le contexte numérique. Le tri
final se fait sur `$NF` placé en tête de ligne, parce que `sort -rn` compare le
début de la ligne : c'est le réflexe « mets la clé devant » qui évite de jongler
avec `-k`.
:::

**E5.9** — *Erreurs et exceptions de `app.log`.*

```bash
grep -cE '^2026-09-18 [0-9:.]+ ERROR ' app.log                # -> 145
grep -oE '^[a-z][a-zA-Z.]*(Exception|Error)' app.log | sort | uniq -c | sort -rn
```

```text
     63 java.sql.SQLTransientConnectionException
     46 java.lang.NullPointerException
     23 fr.lab.factura.error.PaiementRefuseException
     13 java.lang.OutOfMemoryError
```

::: pourquoi
L'ancre `^` est essentielle : sans elle, `grep -c ERROR` compterait aussi les lignes
de pile qui mentionnent une classe `ErrorHandler`, et le motif d'exception
attraperait les `at …Exception…` des piles d'appel. Ici les lignes d'exception
commencent en colonne 1 par un nom de paquet en minuscules, les piles par une
tabulation, les événements par une date : trois familles, trois ancres. C'est la
méthode générale pour un journal multi-lignes — identifier la grammaire avant de
filtrer.
:::

**E5.10** — *Pile de la première `OutOfMemoryError`.*

```bash
grep -m1 -B1 -A10 'OutOfMemoryError' app.log
```

```text
(première ligne repliée ici pour la mise en page)
2026-09-18 07:35:06.671 ERROR [kafka-consumer-0]
   fr.lab.factura.service.PaiementService - echec de la requete 45320
java.lang.OutOfMemoryError: Java heap space
	at fr.lab.factura.web.CommandeController.traiter(CommandeController.java:375)
	at fr.lab.factura.service.PaiementService.executer(PaiementService.java:358)
	...
```

::: pourquoi
`-m1` arrête `grep` à la première correspondance (utile sur un fichier énorme),
`-B1` donne la ligne de journal qui précède — celle qui porte l'horodatage et le
thread — et `-A10` les dix suivantes. Ajoute `-n` pour avoir les numéros de ligne et
pouvoir y revenir avec `sed -n '509,520p'`. Attention : `-A10` est un nombre
arbitraire ; les piles de ce journal font de 4 à 8 cadres, plus un éventuel
`Caused by:`. Quand la longueur varie, `grep -A` ne suffit plus, il faut raisonner
par plage (voir L5.3).
:::

**E5.11** — *Normaliser les URL et top 10.*

```bash
awk '{ print $7 }' access.log \
  | sed -E 's/\?.*//; s#/[0-9]+$#/:id#' \
  | sort | uniq -c | sort -rn | head -10
```

```text
    991 /health
    609 /catalogue
    460 /api/v1/orders
    446 /api/v1/auth/login
    423 /recherche
    303 /api/v1/orders/:id
    296 /favicon.ico
    279 /api/v1/customers
    274 /static/img/banniere.jpg
    273 /static/js/app.js
```

::: pourquoi
Sans normalisation, `/api/v1/orders/12937` et `/api/v1/orders/10974` sont deux
endpoints différents : le top est noyé sous des milliers d'URL vues une fois, et
aucune moyenne de temps de réponse n'a de sens. Deux substitutions suffisent :
la première coupe tout ce qui suit le `?` (les paramètres), la seconde remplace un
segment final entièrement numérique par `:id`. Le séparateur `#` évite d'échapper
les `/`. `sed -E` active les regex étendues, donc `+` sans antislash.
:::

::: piege
`s/\?.*//` doit venir **avant** `s#/[0-9]+$#…#` : appliquée d'abord, la seconde ne
verrait jamais de segment numérique en fin de ligne puisque la chaîne de requête
occupe la fin. L'ordre des expressions `sed` est l'ordre d'application, ligne par
ligne.
:::

**E5.12** — *Bloc `location /static/` et suppression des lignes vides.*

```bash
sed -n '/location \/static\//,/^    }/p' conf/shop.conf
sed '/^$/d' conf/shop.conf
```

```text
    location /static/ {
        root /srv/factura/public;
        expires 7d;
    }
```

::: pourquoi
La plage `/motif1/,/motif2/` s'ouvre sur la première ligne correspondante et se
ferme sur la première correspondance suivante de `motif2`. Le motif de fin est ancré
sur l'indentation (`^    }`) pour ne pas se refermer sur l'accolade d'un bloc
imbriqué. `-n` supprime l'affichage automatique, `p` imprime la plage. Le fichier
passe de 21 à 17 lignes après suppression des lignes vides. Pour enlever aussi les
commentaires : `sed -E '/^\s*#/d; /^$/d'`.
:::

**E5.13** — *Chiffre d'affaires par région.*

```bash
awk -F, 'NR > 1 { total += $6 } END { printf "%.2f\n", total }' commandes.csv
awk -F, 'NR > 1 { s[$2] += $6; n[$2]++ }
         END { for (r in s)
               printf "%-8s %4d %12.2f %9.2f\n",
                 r, n[r], s[r], s[r]/n[r] }' \
  commandes.csv | sort -k3,3nr
```

```text
1756923.34

idf       135    553716.88   4101.61
est        74    403679.47   5455.13
sud        75    334943.41   4465.91
ouest      70    279687.13   3995.53
nord       46    184896.45   4019.49
```

::: pourquoi
Deux tableaux associatifs indexés par la même clé : un pour la somme, un pour
l'effectif ; la moyenne se calcule en `END`. `NR > 1` saute l'en-tête. Le `sort`
final est indispensable : `for (k in tableau)` parcourt les clés dans un ordre
**non spécifié**, qui diffère entre mawk et gawk et peut même changer d'une version
à l'autre. Toute sortie d'un `for (k in …)` destinée à être lue ou comparée doit
passer par `sort`. Lecture des chiffres : l'Île-de-France fait le plus gros volume,
mais l'Est a le meilleur panier moyen (5455 EUR) — deux conclusions opposées selon
la colonne qu'on regarde.
:::

**E5.14** — *Jointure `serveurs.csv` × `sites.csv`.*

```bash
awk -F, 'NR == FNR { dc[$1] = $2; next } FNR > 1 { print $1, $9, dc[$9] }' \
  sites.csv serveurs.csv | head -5
```

```text
api-dev-01 lyon DC-LYS-1
worker-pro-02 francfort DC-FRA-2
web-dev-03 paris DC-PAR-3
api-pro-04 paris DC-PAR-3
api-pro-05 paris DC-PAR-3
```

::: pourquoi
`NR == FNR` n'est vrai que pendant la lecture du premier fichier : on y construit la
table `dc[site] = datacenter`, puis `next` empêche ces lignes de tomber dans le bloc
suivant. Le second bloc s'applique au second fichier, où `FNR > 1` saute l'en-tête.
L'alternative `join` impose de trier les deux fichiers sur la clé et de les
réordonner (`join -t, -1 9 -2 1`), ce qui casse l'ordre d'origine : dès qu'il y a
plus de deux colonnes ou un en-tête, `awk` est plus simple et plus sûr.
:::

**E5.15** — *`jq` et `yq`.*

```bash
jq -r '.results[] | select(.metriques.disque_pct > 85)
       | "\(.hostname) \(.ip) \(.metriques.disque_pct)"' api-inventaire.json
jq '[.results[] | select(.metriques.disque_pct > 85)
     | {hote: .hostname, disque: .metriques.disque_pct}]' api-inventaire.json
yq -r '[.services[].replicas] | add' services.yaml     # -> 10
```

```text
proxy-pro-11 10.23.0.50 91
web-pro-12 10.20.5.154 97
worker-dev-14 10.22.1.151 96
cache-pre-32 10.22.1.183 94
proxy-pre-37 10.22.3.169 90
proxy-pro-39 10.20.4.70 90
proxy-dev-48 10.20.1.198 86
```

::: pourquoi
`.results[]` déroule le tableau, `select(condition)` laisse passer les objets qui
satisfont la condition, `"\(expression)"` interpole dans une chaîne, et `-r` sort le
texte sans guillemets. Les crochets englobants `[ … ]` recollectent le flux d'objets
en tableau JSON : sans eux, `jq` produirait une suite d'objets indépendants, ce qui
n'est pas un document JSON valide. `yq` de Debian/Ubuntu est un **wrapper autour de
jq** : la syntaxe des filtres est celle de `jq`, seule la lecture du format change.
Le `yq` écrit en Go (mikefarah), qu'on installe parfois à la main, a une syntaxe
différente : vérifie toujours avec `yq --version` sur quelle implémentation tu es.
:::

**E5.16** — *Pipeline qui échoue quand le motif est absent.*

```bash
set -o pipefail
grep -c 'ERROR' app.log | tee rapports/nb-erreurs.txt
echo "maillons : ${PIPESTATUS[*]} / pipeline : $?"
```

```text
145
maillons : 0 0 / pipeline : 0
```

Avec un motif inexistant :

```bash
grep -c 'ZZZZ' app.log | tee rapports/nb-erreurs.txt
echo "maillons : ${PIPESTATUS[*]} / pipeline : $?"
```

```text
0
maillons : 1 0 / pipeline : 1
```

::: pourquoi
Sans `pipefail`, le code du pipeline est celui de `tee`, toujours 0 : l'échec de
`grep` est invisible. Avec `pipefail`, bash renvoie le code du dernier maillon non
nul, ici celui de `grep`. `PIPESTATUS` donne le détail maillon par maillon et se
lit **immédiatement** après le pipeline : la commande suivante l'écrase. Noter que
`${PIPESTATUS[*]}` et `$?` peuvent figurer dans le même `echo`, parce que bash
développe tous les arguments avant d'exécuter la commande.
:::

::: piege
`set -e` ne protège pas d'un pipeline : seul le dernier maillon est pris en compte
pour décider de l'arrêt. `set -euo pipefail` en tête de script est la formule
complète, et c'est exactement ce qui manquait dans BF5.1.
:::

---

## 5.6 Labs

### L5.1 — INC-4412, analyse de `access.log`

*Produire un rapport chiffré à partir du seul journal d'accès.*

**Étape 1 — périmètre**

```bash
wc -l < access.log                                    # 7200
head -1 access.log | awk '{ print substr($4, 2) }'    # 14/Sep/2026:00:03:05
tail -1 access.log | awk '{ print substr($4, 2) }'    # 18/Sep/2026:11:54:22
awk '{ print $1 }' access.log | sort -u | wc -l       # 17
```

**Étape 2 — codes HTTP avec pourcentages**

```bash
awk '{ c[$9]++; t++ }
     END { for (k in c) printf "%s %6d %6.2f%%\n", k, c[k], 100 * c[k] / t }' \
  access.log | sort -k2,2nr
```

```text
200   5906  82.03%
304    491   6.82%
404    353   4.90%
403    176   2.44%
401    139   1.93%
500     52   0.72%
502     35   0.49%
410     33   0.46%
503     15   0.21%
```

**Étape 3 — volume par jour et par heure**

```bash
awk '{ print substr($4, 2, 11) }' access.log | uniq -c
awk '{ print substr($4, 14, 2) }' access.log \
  | sort | uniq -c | sort -rn | head -3
```

```text
   1671 14/Sep/2026
   1671 15/Sep/2026
   1664 16/Sep/2026
   1667 17/Sep/2026
    527 18/Sep/2026

    513 18
    505 19
    498 20
```

**Étape 4 — top 10 des endpoints normalisés** : voir E5.11, résultat identique.

**Étape 5 — moyenne et maximum par endpoint (au moins 50 hits)**

```bash
awk '{ u = $7; sub(/\?.*/, "", u); sub(/\/[0-9]+$/, "/:id", u)
       n[u]++; s[u] += $NF; if ($NF > m[u]) m[u] = $NF }
     END { for (k in n) if (n[k] >= 50)
             printf "%-28s %5d %8.3f %8.3f\n", k, n[k], s[k]/n[k], m[k] }' \
  access.log | sort -k3,3nr | head -8
```

```text
/api/v1/reports/export         122    3.908    9.107
/api/v1/customers              279    0.806    9.240
/api/v1/cart/items             170    0.714    9.683
/api/v1/orders                 460    0.498    9.677
/api/v1/products               253    0.450    8.792
/api/v1/auth/login             446    0.446    0.748
/api/v1/orders/:id             303    0.440    9.435
/catalogue                     609    0.176    0.338
```

**Étape 6 — les 10 requêtes les plus lentes**

```bash
awk '{ printf "%8.3f s  %s  %s\n", $NF, substr($4, 2), $7 }' access.log \
  | sort -rn | head -10
```

```text
   9.683 s  14/Sep/2026:17:21:04  /api/v1/cart/items
   9.677 s  14/Sep/2026:14:08:42  /api/v1/orders?page=3
   9.668 s  15/Sep/2026:13:16:04  /api/v1/orders?page=5
   9.435 s  14/Sep/2026:18:17:05  /api/v1/orders/11504
   9.288 s  17/Sep/2026:03:28:19  /api/v1/orders/10974
```

**Étape 7 — les 5xx**

```bash
awk '$9 ~ /^5/' access.log | wc -l          # 102
awk '$9 ~ /^5/ { u = $7; sub(/\?.*/, "", u)
                sub(/\/[0-9]+$/, "/:id", u); print u }' \
  access.log | sort | uniq -c | sort -rn
```

```text
     28 /api/v1/customers
     22 /api/v1/orders
     14 /api/v1/orders/:id
     14 /api/v1/cart/items
     13 /api/v1/products
     11 /api/v1/reports/export
```

**Étape 8 — assemblage du rapport**

```bash
exec 3> rapports/rapport-acces.txt
{
  printf '=== Rapport INC-4412 ===\n\n1. PERIMETRE\n'
  printf '   lignes analysees : %s\n' "$(wc -l < access.log)"
  # … une section par étape ; le bloc { } n'ouvre le fd qu'une fois
} >&3
exec 3>&-
bash check_M05_01.sh
```

::: pourquoi
`exec 3> fichier` ouvre le fichier **une seule fois** et garde le descripteur
ouvert : chaque `>&3` écrit à la suite sans rouvrir ni tronquer, contrairement à une
série de `>>` qui ouvre et ferme le fichier à chaque ligne. `exec 3>&-` referme
proprement. Le regroupement `{ … } >&3` applique la redirection à tout le bloc.

Conclusion à écrire, appuyée sur les chiffres : `/api/v1/reports/export` est lent
(3,908 s de moyenne sur 122 appels, contre 0,176 s pour `/catalogue`), les 102
erreurs 5xx sont **toutes** sur `/api`, et le pic de trafic est à 18 h. Aucun
argument ne justifie une montée en charge : ce n'est pas le volume qui pose
problème (1670 requêtes par jour), c'est un endpoint synchrone qui mobilise un
worker pendant quatre secondes.
:::

::: piege
Deux fautes classiques dans ce lab. Ne pas normaliser les URL : les moyennes de
temps de réponse sont alors calculées sur des échantillons de 1 et le classement
n'a aucun sens. Et calculer un temps de réponse moyen **global** en incluant
`/health` (991 requêtes à 2 ms) et les assets statiques : la moyenne tombe à 0,2 s
et tu conclus que tout va bien.
:::

---

### L5.2 — Réconcilier la CMDB, l'API et la supervision

*Comparer trois sources et produire un inventaire consolidé.*

**Étape 1 — les deux sources décrivent-elles les mêmes hôtes ?**

```bash
diff <(awk -F, 'NR > 1 { print $1 }' serveurs.csv | sort) \
     <(jq -r '.results[].hostname' api-inventaire.json | sort) \
  && echo identiques
```

**Étape 2 — écarts avec la supervision**

```bash
comm -23 hosts-cmdb.txt hosts-supervision.txt      # 8 hôtes non supervisés
comm -13 hosts-cmdb.txt hosts-supervision.txt      # 4 hôtes inconnus de la CMDB
```

```text
api-dev-16 cache-dev-41 db-pro-33 proxy-dev-56
proxy-pro-17 web-dev-55 web-pro-50 worker-pro-24

bastion-pro-93 mail-pro-92 nas-pro-94 vpn-pro-91
```

**Étape 3 — état des agents et disques**

```bash
jq -r '.results[] | select(.actif == false) | .hostname' api-inventaire.json
jq -r '.results[] | select(.metriques.disque_pct > 85)
       | "\(.hostname) \(.metriques.disque_pct)"' api-inventaire.json
```

```text
cache-pre-21  proxy-dev-38  proxy-dev-59

proxy-pro-11 91   web-pro-12 97   worker-dev-14 96   cache-pre-32 94
proxy-pre-37 90   proxy-pro-39 90  proxy-dev-48 86
```

**Étape 4 — le fichier consolidé, en un seul `awk` à quatre entrées**

```bash
awk -F, -v OFS=, '
  FNR == 1 { f++ }
  f == 1 { dc[$1] = $2; next }                    # sites.csv
  f == 2 { sup[$1] = 1; next }                    # hosts-supervision.txt
  f == 3 { disque[$1] = $2; next }                # hostname,disque_pct (jq)
  f == 4 && FNR == 1 {
      print "hostname","env","role","site","datacenter","cout_eur",
            "disque_pct","supervise"; next }
  f == 4 { print $1, $2, $3, $9, dc[$9], $10, disque[$1],
                 (sup[$1] ? "oui" : "non") }
' sites.csv hosts-supervision.txt \
  <(jq -r '.results[]
        | "\(.hostname),\(.metriques.disque_pct)"' api-inventaire.json) \
  serveurs.csv > rapports/parc-complet.csv
```

```text
hostname,env,role,site,datacenter,cout_eur,disque_pct,supervise
api-dev-01,dev,api,lyon,DC-LYS-1,131.20,68,oui
worker-pro-02,prod,worker,francfort,DC-FRA-2,288.00,12,oui
```

**Étapes 5 et 6 — coûts, alignés**

```bash
awk -F, 'NR > 1 { t += $6; e[$2] += $6; if ($8 == "non") ns += $6 }
         END { printf "%-10s %10.2f\n", "TOTAL", t
               for (k in e) printf "%-10s %10.2f\n", k, e[k]
               printf "%-10s %10.2f\n", "NON SUPERV", ns }' \
  rapports/parc-complet.csv | sort
```

```text
NON SUPERV    1872.00
TOTAL        14998.40
dev           5600.00
preprod       2224.00
prod          7174.40
```

::: pourquoi
Le compteur `f`, incrémenté à chaque `FNR == 1`, identifie le fichier en cours de
lecture. C'est la généralisation de `NR == FNR` à plus de deux entrées, et c'est
portable — contrairement à `ARGIND`, qui n'existe que dans gawk. Les trois premiers
fichiers alimentent des tables, le quatrième produit la sortie.

La substitution de processus `<(jq …)` fait passer une commande pour un fichier :
`awk` l'ouvre comme les autres et `FNR` y fonctionne normalement. Aucun fichier
temporaire, donc rien à nettoyer et pas de course entre deux exécutions.

Le chiffre qui fait bouger les choses n'est pas « 8 hôtes non supervisés » mais
« 1872,00 EUR par mois de machines dont personne ne sait si elles tournent », dont
`db-pro-33` et `worker-pro-24` en production. Convertis toujours un écart technique
en euros ou en risque avant de l'envoyer à un décideur.
:::

::: piege
`comm` exige deux fichiers triés **avec le même ordre**. Si l'un a été trié en
`fr_FR.UTF-8` et l'autre en `C`, les résultats sont faux sans erreur visible. En
script : `LC_ALL=C sort` partout. Et `grep -Ff liste fichier` n'est pas équivalent à
`comm` : il cherche des sous-chaînes, donc `web-pro-5` matcherait `web-pro-50`.
Pour ce lab, `-x` (ligne entière) ou `-w` protège.
:::

---

### L5.3 — Autopsie d'un journal multi-lignes

*Séparer les événements des piles d'appel et produire des chiffres exacts.*

**Étapes 1 et 2 — lignes, événements, niveaux**

```bash
wc -l < app.log                                      # 2847 lignes
grep -cE '^2026-09-18 [0-9]{2}:' app.log             # 1400 événements
awk '/^2026-09-18 [0-9][0-9]:/ { print $3 }' app.log | sort | uniq -c | sort -rn
```

```text
    836 INFO
    271 DEBUG
    148 WARN
    145 ERROR
```

L'écart (1447 lignes) correspond aux lignes d'exception, aux cadres `at …` et aux
`Caused by:` : ce ne sont pas des événements, et les compter fausse tout ratio.

**Étapes 3 et 4 — exceptions et causes racines**

```bash
grep -oE '^[a-z][a-zA-Z.]*(Exception|Error)' app.log | sort | uniq -c | sort -rn
grep '^Caused by:' app.log | sed 's/^Caused by: //; s/:.*//' \
  | sort | uniq -c | sort -rn
```

```text
     63 java.sql.SQLTransientConnectionException
     46 java.lang.NullPointerException
     23 fr.lab.factura.error.PaiementRefuseException
     13 java.lang.OutOfMemoryError

     63 java.net.SocketTimeoutException
     23 java.io.IOException
```

Couple dominant : `SQLTransientConnectionException` → `SocketTimeoutException`,
63 occurrences, soit 43 % des 145 erreurs. Les deux comptes coïncident exactement :
toutes les erreurs de pool ont la même cause racine.

**Étape 5 — répartition des ERROR**

```bash
awk '$3 == "ERROR" { print substr($2, 1, 2) }' app.log | sort | uniq -c
awk '$3 == "ERROR" { print $4 }' app.log | sort | uniq -c | sort -rn
```

```text
06:16  07:20  08:12  09:15  10:8  11:19  12:24  13:20  14:11

     37 [http-nio-8080-exec-2]
     32 [scheduler-1]
     29 [http-nio-8080-exec-1]
     27 [http-nio-8080-exec-3]
     20 [kafka-consumer-0]
```

Aucun thread n'est réellement sur-représenté : 37 contre 27 sur cinq threads, c'est
du bruit. La bonne réponse à la question posée est « non », et il faut le dire.

**Étape 6 — extraire les `OutOfMemoryError` avec leur pile**

```bash
awk '/OutOfMemoryError/ { print prev; print; oom = 1; next }
     oom && /^\t/       { print; next }
     { oom = 0; prev = $0 }' app.log > rapports/oom.txt
wc -l rapports/oom.txt                        # 101 lignes, 13 blocs
```

**Étape 7 — codes de refus banque**

```bash
grep -oE 'code=[0-9]+' app.log | sort | uniq -c | sort -rn
```

```text
      8 code=54
      7 code=51
      4 code=55
      3 code=52
      1 code=53
```

::: pourquoi
Le cœur du lab est l'étape 6. `grep -A` ne convient pas : le nombre de cadres varie
de 4 à 8 et un `-A8` couperait certaines piles tout en débordant sur l'événement
suivant pour d'autres. L'automate `awk` suit la **structure** du journal :

* `prev` mémorise en permanence la dernière ligne d'événement vue ;
* quand une ligne contient `OutOfMemoryError`, on imprime `prev` puis la ligne, et
  on lève le drapeau `oom` ;
* tant que `oom` est levé, toute ligne commençant par une tabulation (un cadre de
  pile) est imprimée ;
* la première ligne qui ne commence pas par une tabulation abaisse le drapeau et
  redevient le nouveau `prev`.

C'est le patron général pour tout format multi-lignes : identifier ce qui ouvre un
enregistrement, ce qui le continue, ce qui le ferme. Il s'applique tel quel aux
traces Python, aux blocs `systemd`, aux réponses SMTP multi-lignes.
:::

::: piege
`wc -l app.log` ne répond pas à « combien d'erreurs » : 2847 lignes pour 1400
événements et 145 erreurs. Donner 2847 au développeur, c'est se décrédibiliser en
une phrase. De même, `grep -c Exception` compterait aussi les cadres de pile qui
citent une classe d'exception : il faut ancrer sur `^`.
:::

---

### L5.4 — Le livrable venu de Windows

*Diagnostiquer trois fichiers malades, puis comparer deux configurations.*

**Étape 1 — diagnostic**

```bash
file encodages/*
```

```text
clients-latin1.csv: ISO-8859 text
deploiement.sh:     Bourne-Again shell script, ASCII text executable,
                    with CRLF line terminators
export-tableur.csv: CSV Unicode text, UTF-8 (with BOM) text
```

**Étape 2 — le script en CRLF**

```bash
bash encodages/deploiement.sh
# -> ./deploiement.sh: line 2: set: pipefail: invalid option name
cat -A encodages/deploiement.sh | head -2
# -> #!/usr/bin/env bash^M$
sed -i 's/\r$//' encodages/deploiement.sh       # ou dos2unix
bash encodages/deploiement.sh                   # fonctionne
```

**Étape 3 — le latin-1**

```bash
iconv -f ISO-8859-1 -t UTF-8 encodages/clients-latin1.csv \
  > encodages/clients-utf8.csv
file encodages/clients-utf8.csv           # -> Unicode text, UTF-8 text
head -2 encodages/clients-utf8.csv
```

```text
client;ville;commentaire
1042;Orléans;règlement différé
```

**Étape 4 — le BOM**

```bash
head -c3 encodages/export-tableur.csv | od -An -tx1     # -> ef bb bf
sed -i '1s/^\xEF\xBB\xBF//' encodages/export-tableur.csv
grep -c '^hostname' encodages/export-tableur.csv        # -> 1
```

**Étapes 5 et 6 — diff et patch**

```bash
diff -u conf/shop.conf conf/shop-propose.conf
diff -u conf/shop.conf conf/shop-propose.conf > conf/shop.patch
cp conf/shop.conf /tmp/essai.conf
patch -p0 /tmp/essai.conf < conf/shop.patch
diff -q /tmp/essai.conf conf/shop-propose.conf     # silence = identiques
patch -R -p0 /tmp/essai.conf < conf/shop.patch     # annulation
```

La proposition ajoute l'écoute TLS et les certificats, passe
`client_max_body_size` de 8m à 32m, ajoute `X-Forwarded-Proto`, double le
`proxy_read_timeout` (30s → 60s) et allonge le cache des assets (7d → 30d).

::: pourquoi
Les trois pathologies sont invisibles avec `cat` : le `\r` ne s'affiche pas, un
octet latin-1 isolé donne un caractère de remplacement selon le terminal, et le BOM
est un préfixe de trois octets que rien n'affiche. D'où le réflexe `file` puis
`cat -A`.

Mécanisme du CRLF : bash lit la ligne `set -euo pipefail\r` et considère `pipefail\r`
comme le nom de l'option. Toute variable affectée depuis un tel fichier porte un
`\r` final, ce qui casse silencieusement toutes les comparaisons (voir BF5.2).

Mécanisme du BOM : `EF BB BF` est un caractère (U+FEFF) placé avant le premier `h`
de `hostname`. L'ancre `^` de `grep` est donc suivie de ce caractère invisible, et
`^hostname` ne correspond plus. Même effet avec `awk '$1 == "hostname"'`, ou avec
un `#!/bin/bash` précédé d'un BOM : le noyau ne reconnaît plus le shebang.

`diff -u` renvoie **1** quand les fichiers diffèrent : sous `set -e`, un
`diff -u a b > f` interrompt le script alors que tout va bien. C'est une des rares
commandes où un code non nul n'est pas une erreur.
:::

---

### L5.5 — Brute force SSH

*Chiffrer l'attaque, produire une liste de bannissement consommable.*

**Étape 1 — volumétrie**

```bash
wc -l < journal-ssh.txt                        # 900
grep -c 'Failed password' journal-ssh.txt      # 623
grep -c 'Accepted publickey' journal-ssh.txt   # 76
```

**Étapes 2 et 3 — qui attaque, et quoi**

```bash
grep 'Failed password' journal-ssh.txt \
  | grep -oE 'from [0-9]+(\.[0-9]+){3}' | awk '{ print $2 }' \
  | sort | uniq -c | sort -rn
grep 'Failed password' journal-ssh.txt \
  | sed -E 's/.* for (invalid user )?([^ ]+) from .*/\2/' \
  | sort | uniq -c | sort -rn
```

```text
    249 45.155.205.14        185 root
    144 185.220.101.7         80 test
     94 141.98.11.62          76 mathieu
     80 92.63.197.5           74 oracle
     56 218.92.0.31           73 admin
                              70 ubuntu
                              65 postgres
```

Pour la pire IP :

```bash
grep '45.155.205.14' journal-ssh.txt | head -1 | cut -d' ' -f1
# -> 2026-09-17T00:12:33+0200
grep '45.155.205.14' journal-ssh.txt | tail -1 | cut -d' ' -f1
# -> 2026-09-17T22:17:53+0200
```

Soit 249 tentatives en 22 heures, sur sept comptes différents (77 sur `root`).

**Étape 4 — les connexions acceptées**

```bash
grep 'Accepted publickey' journal-ssh.txt \
  | grep -oE 'from [0-9]+(\.[0-9]+){3}' | awk '{ print $2 }' \
  | sort | uniq -c | sort -rn
```

```text
     32 10.10.10.14
     23 198.51.100.12
     21 10.10.10.10
```

Aucune IP attaquante n'y figure, et toutes les acceptations sont par clef publique :
pas de compromission.

**Étapes 5 et 6 — livrables**

```bash
grep 'Failed password' journal-ssh.txt \
  | grep -oE 'from [0-9]+(\.[0-9]+){3}' | awk '{ print $2 }' \
  | sort | uniq -c | sort -rn \
  | awk '$1 >= 50 { print $2 }' > rapports/ips-a-bannir.txt

sed 's|^|sudo ufw deny from |; s|$| to any port 22|' rapports/ips-a-bannir.txt \
  > rapports/ips-a-bannir.sh
```

```text
45.155.205.14
185.220.101.7
141.98.11.62
92.63.197.5
218.92.0.31

sudo ufw deny from 45.155.205.14 to any port 22
sudo ufw deny from 185.220.101.7 to any port 22
...
```

::: pourquoi
Le point qui fait la différence est le motif d'extraction du compte. Le journal
mélange deux formulations :

```text
Failed password for root from 45.155.205.14 port 41537 ssh2
Failed password for invalid user admin from 185.220.101.7 port 52218 ssh2
```

Un `awk '{ print $6 }'` donnerait `root` dans un cas et `user` dans l'autre : le
compte `invalid` devient le plus attaqué et le rapport est faux. Le groupe optionnel
`(invalid user )?` de l'expression `sed` absorbe la variante, et `\2` capture le
nom réel dans les deux cas.

Deuxième point : le `awk '$1 >= 50 { print $2 }'` final applique le seuil **et**
supprime le compteur, en conservant l'ordre produit par `sort -rn`. Le fichier est
donc directement consommable par une boucle ou par `xargs` — c'est la différence
entre un rapport et un livrable.
:::

::: piege
`grep -oE '[0-9]+(\.[0-9]+){3}'` sans le `from ` capturerait aussi l'adresse du
serveur si elle figurait sur la ligne, et le numéro de port n'étant pas une IP, il
passerait à travers. Toujours ancrer l'extraction sur le mot-clé qui donne le sens
(`from`), pas seulement sur la forme de la donnée.
:::

---

## 5.7 Break & Fix

### BF5.1 — Rapport vide, code retour 0

**Diagnostic**

```bash
bash ~/lab05/bin/rapport-quotidien.sh ; echo "code : $?"
cat ~/lab05/rapports/quotidien.txt        # -> une seule ligne de titre
bash -x ~/lab05/bin/rapport-quotidien.sh 2>&1 | head -5
```

```text
+ JOUR=2026-09-18
+ grep -F 2026-09-18 /root/lab05/access.log
```

```bash
head -1 ~/lab05/access.log | cut -d' ' -f4      # -> [14/Sep/2026:00:03:05
```

**Cause racine** : deux défauts indépendants.

1. Le motif de recherche a été « harmonisé » au format ISO (`2026-09-18`) alors que
   nginx écrit ses dates au format `18/Sep/2026`. `grep` ne trouve plus rien.
2. Le pipeline `grep | awk | sort | uniq -c | sort -rn` renvoie le code de son
   dernier maillon, toujours 0. Ni `set -e` ni la supervision ne voient l'échec.

**Correctif**

```bash
sed -i 's|JOUR="${1:-2026-09-18}"|JOUR="${1:-18/Sep/2026}"|' \
  ~/lab05/bin/rapport-quotidien.sh
sed -i 's|grep -F "\$JOUR"|grep -F "[$JOUR"|' ~/lab05/bin/rapport-quotidien.sh
sed -i 's/^set -eu$/set -eu\nset -o pipefail/' ~/lab05/bin/rapport-quotidien.sh
bash ~/lab05/bin/rapport-quotidien.sh ; echo "code : $?"
```

```text
== Rapport du 18/Sep/2026 ==
    439 200
     31 304
     19 404
     17 403
     10 401
      4 500
      3 502
      2 503
      2 410
```

Preuve que l'alerte fonctionne désormais :

```bash
bash ~/lab05/bin/rapport-quotidien.sh 01/Jan/2026 ; echo "code : $?"   # -> 1
```

::: pourquoi
La ligne de bash qui aurait évité trois jours de silence est `set -o pipefail`.
Sans elle, `set -e` est inopérant sur un pipeline : bash n'examine que le code du
dernier maillon, et `sort -rn` réussit toujours, même avec une entrée vide.

Le crochet du motif (`grep -F "[$JOUR"`) n'est pas cosmétique : il ancre la
recherche sur le champ date du format combined. Sans lui, la chaîne `18/Sep/2026`
pourrait aussi apparaître dans une URL ou un referer.

Prévention : un rapport quotidien doit contrôler son propre résultat. Une garde
explicite vaut mieux qu'un code retour subtil :
`[ "$(wc -l < "$OUT")" -gt 1 ] || { echo "rapport vide" >&2; exit 1; }`.
:::

::: piege
La tentation est de corriger seulement le motif : le rapport redevient correct et
l'incident est « résolu ». Mais le jour où la source change de nom, le script
retombera silencieusement dans le même trou. On corrige la panne **et** le
mécanisme qui l'a rendue invisible.
:::

### BF5.2 — La cible existe, le script la refuse

**Diagnostic**

```bash
bash ~/lab05/bin/livrer.sh ; echo "code : $?"
# -> ]ible inconnue : [/srv/factura      (affichage mutilé)
bash ~/lab05/bin/livrer.sh 2>&1 | od -c | head -3
```

```text
0000000   c   i   b   l   e       i   n   c   o   n   n   u   e       :
0000020       [   /   s   r   v   /   f   a   c   t   u   r   a  \r   ]
```

```bash
file ~/lab05/conf/livraison.env     # -> ASCII text, with CRLF line terminators
cat -A ~/lab05/conf/livraison.env   # -> CIBLE=/srv/factura^M$
```

**Cause racine** : le fichier de configuration est revenu d'un poste Windows en
CRLF. `.` (source) affecte donc `CIBLE=/srv/factura\r`. La comparaison
`[ "$CIBLE" != "/srv/factura" ]` est vraie : les deux chaînes diffèrent d'un octet
invisible.

**Correctif**

```bash
sed -i 's/\r$//' ~/lab05/conf/livraison.env     # ou dos2unix
bash ~/lab05/bin/livrer.sh      # -> livraison de 2.7.1 vers /srv/factura
```

::: pourquoi
Le `\r` explique aussi l'affichage mutilé, et c'est le meilleur indice : le
terminal interprète le retour chariot comme « reviens en colonne 1 ». Le message
`cible inconnue : [/srv/factura\r]` s'affiche donc entièrement, puis le `]` final
écrase le premier caractère — d'où `]ible inconnue : [`. Chaque fois qu'une sortie
semble tronquée ou écrasée par la fin d'elle-même, pense `\r`.

La commande qui montre le problème en une seconde : `cat -A fichier` (ou
`file fichier`). `cat` seul ne montre rien, puisqu'il envoie les octets tels quels
au terminal, qui exécute le retour chariot au lieu de l'afficher.

Prévention : un contrôle en CI (`file conf/*.env | grep -q CRLF && exit 1`), un
`.gitattributes` avec `* text=auto eol=lf`, et le réflexe de sourcer les fichiers de
configuration après normalisation.
:::

### BF5.3 — La même IP à trois rangs différents

**Diagnostic**

```bash
bash ~/lab05/bin/top-ip.sh | head -6
```

```text
== Top 10 des IP de access-agrege.log ==
   1440 
    710 10.10.10.14
    420 203.0.113.5
    419 198.51.100.12
    259 203.0.113.242
    259 	10.10.10.14
```

```bash
head -3 ~/lab05/access-agrege.log | cat -A | cut -c1-40
```

```text
 198.51.100.104 - - [14/Sep/2026:00:03:0
^I10.10.10.14 - - [14/Sep/2026:00:07:16
198.51.100.12 - - [14/Sep/2026:00:11:36
```

**Cause racine** : l'agrégateur indente une partie des lignes, tantôt avec une
espace, tantôt avec une tabulation, et termine tout en CRLF. Le script découpe avec
`cut -d' ' -f1` : sur une ligne préfixée d'une espace, le premier champ est
**vide** (d'où les 1440 lignes sans adresse en tête du classement) ; sur une ligne
préfixée d'une tabulation, le premier champ est `\t10.10.10.14`, qui n'est pas la
même chaîne que `10.10.10.14`.

**Correctif**

```bash
tr -d '\r' < ~/lab05/access-agrege.log \
  | awk '{ print $1 }' | sort | uniq -c | sort -rn | head -5
```

```text
   1212 10.10.10.14
    685 198.51.100.12
    680 203.0.113.5
    406 203.0.113.242
    363 198.51.100.150
```

Chiffres identiques à ceux du fichier d'origine, et somme des compteurs égale aux
7200 lignes.

::: pourquoi
`uniq` a parfaitement fait son travail : `10.10.10.14`, `\t10.10.10.14` et la chaîne
vide **sont** trois chaînes différentes. Le défaut est en amont, dans l'extraction.

`cut -d' '` prend le délimiteur au pied de la lettre : un seul caractère, pas de
regroupement des blancs consécutifs, pas de tabulation. `awk` sans `-F` utilise le
séparateur par défaut, qui est « une suite quelconque de blancs (espaces et
tabulations), les blancs de tête étant ignorés » : il absorbe les trois cas d'un
coup. C'est la raison principale de préférer `awk '{ print $1 }'` à
`cut -d' ' -f1` sur des données dont tu ne maîtrises pas la mise en forme.

Le `tr -d '\r'` ne change rien au premier champ, mais il normalise le dernier :
c'est la bonne habitude — on nettoie l'entrée **une fois**, en tête de pipeline,
plutôt que de rustiner symptôme par symptôme.
:::

---

## 5.8 Défi du module

**D5 — Rapport d'exploitation hebdomadaire**

Les deux livrables attendus sont `rapports/hebdo-2026-S38.md` et
`rapports/hebdo-pipelines.sh`. Voici le second, qui produit tous les chiffres du
premier ; le rapport n'est que leur mise en forme.

```bash
#!/usr/bin/env bash
# hebdo-pipelines.sh — un pipeline par chiffre du rapport hebdomadaire.
# pipefail : sans lui, un maillon en échec (grep sans correspondance, fichier
# absent) est masqué par le succès du dernier maillon, et le rapport sort faux
# sans que personne ne le sache.
set -o pipefail
cd ~/lab05 || exit 1

# nombre total de requêtes de la semaine                        -> 7200
wc -l < access.log

# volume par jour                                 -> 1671/1671/1664/1667/527
awk '{ print substr($4, 2, 11) }' access.log | uniq -c

# heure de pointe                                               -> 18 h, 513
awk '{ print substr($4, 14, 2) }' access.log \
  | sort | uniq -c | sort -rn | head -1

# part des 4xx et des 5xx                            -> 4xx 9.7 %  5xx 1.4 %
awk '{ t++ } $9 ~ /^4/ { q++ } $9 ~ /^5/ { c++ }
     END { printf "4xx %.1f%%  5xx %.1f%%\n", 100*q/t, 100*c/t }' access.log

# 5 endpoints les plus lents, vus au moins 50 fois
awk '{ u = $7; sub(/\?.*/, "", u); sub(/\/[0-9]+$/, "/:id", u)
       n[u]++; s[u] += $NF; if ($NF > m[u]) m[u] = $NF }
     END { for (k in n) if (n[k] >= 50)
             printf "%.3f %.3f %d %s\n",
               s[k]/n[k], m[k], n[k], k }' access.log \
  | sort -rn | head -5

# événements de niveau ERROR                                      -> 145
grep -cE '^2026-09-18 [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3} ERROR ' app.log

# top 3 des exceptions                                     -> 63 / 46 / 23
grep -oE '^[a-z][a-zA-Z.]*(Exception|Error)' app.log \
  | sort | uniq -c | sort -rn | head -3

# cause racine dominante                 -> 63 java.net.SocketTimeoutException
grep '^Caused by:' app.log | sed 's/^Caused by: //; s/:.*//' \
  | sort | uniq -c | sort -rn | head -1

# échecs d'authentification par mot de passe                       -> 623
grep -c 'Failed password' journal-ssh.txt

# top 3 des IP sources                               -> 249 / 144 / 94
grep 'Failed password' journal-ssh.txt | grep -oE 'from [0-9]+(\.[0-9]+){3}' \
  | awk '{ print $2 }' | sort | uniq -c | sort -rn | head -3

# top 3 des comptes visés               -> root 185, test 80, mathieu 76
grep 'Failed password' journal-ssh.txt \
  | sed -E 's/.* for (invalid user )?([^ ]+) from .*/\2/' \
  | sort | uniq -c | sort -rn | head -3

# nombre d'IP au-dessus de 50 échecs                                 -> 5
grep 'Failed password' journal-ssh.txt | grep -oE 'from [0-9]+(\.[0-9]+){3}' \
  | awk '{ print $2 }' | sort | uniq -c | awk '$1 >= 50' | wc -l

# nombre d'hôtes et coût mensuel total            -> 60 hôtes, 14998.40 EUR
awk -F, 'NR > 1 { n++; t += $10 }
         END { printf "%d hotes  %.2f EUR\n", n, t }' serveurs.csv

# coût des hôtes non supervisés                             -> 1872.00 EUR
grep -Ff <(comm -23 hosts-cmdb.txt hosts-supervision.txt) serveurs.csv \
  | awk -F, '{ t += $10 } END { printf "%.2f EUR\n", t }'

# hôtes dont le disque dépasse 85 %                                  -> 7
jq -r '.results[] | select(.metriques.disque_pct > 85) | .hostname' \
  api-inventaire.json | wc -l
```

Extrait du rapport attendu (section Performance, en tableau Markdown) :

```markdown
| Endpoint | Hits | Moyenne (s) | Max (s) |
|---|---:|---:|---:|
| /api/v1/reports/export | 122 | 3.908 | 9.107 |
| /api/v1/customers | 279 | 0.806 | 9.240 |
| /api/v1/cart/items | 170 | 0.714 | 9.683 |
| /api/v1/orders | 460 | 0.498 | 9.677 |
| /api/v1/products | 253 | 0.450 | 8.792 |
```

Et les trois actions, chacune adossée à un chiffre :

* sortir `/api/v1/reports/export` du chemin synchrone — 3,908 s de moyenne, 22 fois
  plus lent que `/catalogue` (0,176 s), pour 122 appels seulement ;
* traiter le timeout réseau vers la base — 63 des 145 erreurs applicatives, soit
  43 %, viennent d'un seul `SocketTimeoutException` ;
* superviser les 8 hôtes hors radar avant l'audit — 1872,00 EUR par mois, dont deux
  machines de production.

::: pourquoi
Trois points font la différence entre un rapport qui sert et un rapport qu'on
archive.

**Les chiffres sont reproductibles.** Livrer les pipelines avec le rapport permet à
n'importe qui de refaire le calcul la semaine suivante, et de contester une valeur
en montrant la commande. C'est la version « exploitation » de la reproductibilité.

**Chaque action est adossée à un chiffre du rapport.** « L'API est lente » n'engage
personne ; « 3,908 s de moyenne sur 122 appels, 22 fois les pages HTML » donne un
ordre de grandeur, un volume et un point de comparaison, donc une décision possible.

**Aucun fichier temporaire.** `<(comm -23 …)` fournit la liste des hôtes non
supervisés directement à `grep -F`, sans passer par `/tmp`. Un fichier temporaire
oublié, c'est une exécution concurrente qui se marche dessus et un rapport faux une
fois sur dix — le pire des cas, parce qu'il est crédible.
:::

::: piege
Deux pièges attendent dans ce défi. Le premier est `for (k in tableau)` sans `sort`
derrière : l'ordre des endpoints changera entre mawk et gawk, et ton tableau
Markdown ne sera pas reproductible. Le second est le calcul des pourcentages en
arithmétique shell : `$(( 102 * 100 / 7200 ))` vaut **1**, pas 1.4 — bash ne fait
que de l'entier. Tout ratio se calcule dans `awk` avec `printf "%.1f"`.
:::

---

## Annexe — les six patrons à réutiliser

Ce module tient dans six structures. Le reste n'est que de l'habillage.

**1. Le top N.** Compter des occurrences et classer.

```bash
awk '{ print $1 }' fichier | sort | uniq -c | sort -rn | head -10
```

Version une passe quand le fichier est gros (mémoire proportionnelle au nombre de
clés distinctes, pas au nombre de lignes) :

```bash
awk '{ n[$1]++ } END { for (k in n) print n[k], k }' fichier \
  | sort -rn | head -10
```

**2. L'accumulateur par clé.** Somme, effectif, moyenne, maximum en une lecture.

```bash
awk -F, 'NR > 1 { s[$2] += $6; n[$2]++; if ($6 > m[$2]) m[$2] = $6 }
         END { for (k in s)
                 printf "%-10s %4d %10.2f %10.2f\n",
                   k, n[k], s[k], s[k]/n[k] }' fichier.csv | sort -k3,3nr
```

**3. La jointure de fichiers.** Charger une table, puis traiter les données.

```bash
awk 'NR == FNR { table[$1] = $2; next }
     { print $0, table[$1] }' reference.txt donnees.txt
```

Au-delà de deux fichiers, remplacer `NR == FNR` par un compteur `FNR == 1 { f++ }`
et tester `f == 1`, `f == 2`, etc. — c'est portable, `ARGIND` ne l'est pas.

**4. L'automate multi-lignes.** Un enregistrement qui s'étale sur plusieurs lignes.

```bash
awk '/DEBUT/          { garde = 1 }
     garde            { print }
     garde && /FIN/   { garde = 0 }' fichier
```

Identifier ce qui **ouvre** l'enregistrement, ce qui le **continue**, ce qui le
**ferme**. S'applique aux piles Java, aux traces Python, aux blocs de configuration.

**5. La normalisation avant comptage.** Sans elle, tout classement est faux.

```bash
tr -d '\r' < fichier \
  | awk '{ print $7 }' \
  | sed -E 's/\?.*//; s#/[0-9]+$#/:id#' \
  | sort | uniq -c | sort -rn
```

Nettoyer **une fois**, en tête de pipeline : CR, blancs de tête, casse, paramètres,
identifiants volatils. Jamais symptôme par symptôme en fin de chaîne.

**6. Le pipeline qui dit la vérité.** Un rapport silencieux est pire qu'une panne.

```bash
set -euo pipefail
grep -F "$MOTIF" "$SRC" | awk '{ print $9 }' | sort | uniq -c | sort -rn
echo "maillons : ${PIPESTATUS[*]}"
```

---

## Vérification globale

```bash
cd ~/lab05
bash check_M05_01.sh && bash check_M05_02.sh && bash check_M05_03.sh \
  && bash check_M05_04.sh && bash check_M05_05.sh && bash check_M05_06.sh
```

Si un contrôle échoue, son message indique la piste, jamais la commande. Et si tes
données ont été abîmées par un `sed -i` malheureux, `bash setup_M05.sh` les régénère
à l'identique : c'est l'intérêt d'un générateur déterministe.
