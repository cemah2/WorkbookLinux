# Module 05 — Traitement de texte et flux de données

## 5.0 Objectifs et compétences

::: objectif
À la fin de ce module, je sais :

* manipuler les descripteurs de fichiers à la main (`2>&1`, `&>`, `>&2`, `exec 3>`),
  expliquer pourquoi l'ordre des redirections change le résultat, et alimenter une
  commande avec un here-doc, un here-string ou une substitution de processus ;
* construire un pipeline qui échoue quand il doit échouer (`set -o pipefail`,
  `PIPESTATUS`), le dupliquer avec `tee`, et paralléliser une tâche avec `xargs -P` ;
* découper et recomposer des données tabulaires avec `cut`, `paste`, `join`, `tr`,
  `column`, `split`, et dire quand ces outils ne suffisent plus ;
* trier et dédoublonner proprement : `sort -t -k -n -h -u -s`, `uniq -c/-d/-u`,
  `comm`, et produire un « top N » correct du premier coup ;
* écrire une expression régulière POSIX de base et étendue, choisir entre `grep`,
  `grep -E` et `grep -P`, et exploiter `-o`, `-c`, `-w`, `-v`, `-r`, `-A/-B/-C` ;
* transformer un flux avec `sed` : substitution avec drapeaux, groupes de capture,
  adressage par ligne, par plage et par motif, suppression, insertion, `-i` sauvegardé ;
* écrire un programme `awk` lisible : `BEGIN/END`, champs, `NR`/`FNR`/`NF`/`FS`/`OFS`,
  tableaux associatifs, accumulateurs par clé, `printf` aligné, jointure de deux fichiers ;
* interroger du JSON avec `jq` (sélection, `map`, `select`, `-r`, construction d'objets)
  et du YAML avec `yq`, sans jamais parser du JSON à coups de `grep` ;
* diagnostiquer un problème d'encodage ou de fin de ligne (`file`, `iconv`, CRLF, BOM)
  et comparer deux fichiers avec `diff -u` / `patch` / `comm` ;
* produire, à partir d'un `access.log` ou d'un journal applicatif, un rapport chiffré
  exploitable par un chef de projet en moins de dix minutes.

Temps estimé : 6 h
Prérequis : module 01 (quoting, expansion, redirections de base), module 02 (arborescence).
:::

---

## 5.1 Mise en place

VM concernée : **`lab-adm` (10.10.10.10)**, utilisateur `mathieu`. Aucun service n'est
touché, tout se passe dans `~/lab05`. Aucune commande de ce module ne demande `sudo`,
sauf l'installation des paquets.

```bash
# depuis le shell Proxmox
qm snapshot 9001 avant-lab05
```

```bash
sudo apt update
sudo apt install -y gawk jq yq bsdextrautils dos2unix moreutils \
  coreutils grep sed
```

`bsdextrautils` fournit `column` sur Ubuntu 24.04 ; `moreutils` fournit `sponge`,
utilisé une fois dans le défi.

::: rhel
Sous Rocky 9 : `sudo dnf install -y gawk jq util-linux dos2unix`. Le paquet `yq`
n'existe pas dans les dépôts de base : `sudo dnf install -y python3-pip && pip3 install yq`.
`sponge` vient d'EPEL (`sudo dnf install -y epel-release moreutils`).
:::

::: attention
Sur Ubuntu, `awk` est **mawk** par défaut. Installer `gawk` bascule le lien
`/etc/alternatives/awk` vers gawk. Les corrigés de ce module n'utilisent que des
constructions POSIX communes aux deux, et trient systématiquement les sorties :
tu obtiens donc les mêmes chiffres avec l'un comme avec l'autre. Vérifie avec
`awk -W version 2>&1 | head -1`.
:::

Génération du jeu de données :

```bash
bash ~/workbook/scripts/setup/setup_M05.sh
```

Le script remplit `~/lab05` avec des données **déterministes** (générateur pseudo-aléatoire
à graine fixe) : tous les chiffres annoncés dans les corrigés sont reproductibles chez toi,
au dernier octet près. Il est rejouable à volonté — c'est aussi la procédure de secours
quand un `sed -i` a mal tourné.

| Fichier | Contenu |
|---|---|
| `access.log` | 7200 lignes nginx, format `combined` + `$request_time` |
| `access.log.1.gz` | la rotation précédente, compressée |
| `app.log` | 2847 lignes de journal applicatif Java, piles d'appel comprises |
| `journal-ssh.txt` | 900 lignes extraites de `journalctl -u ssh -o short-iso` |
| `serveurs.csv` | inventaire CMDB, 60 hôtes, 10 colonnes |
| `serveurs-piege.csv` | le même format, avec des virgules **dans** les champs |
| `commandes.csv` | 400 lignes de ventes (calculs `awk`) |
| `api-inventaire.json` | export de l'API CMDB, mêmes 60 hôtes, plus des métriques |
| `services.yaml` | pile applicative (pour `yq`) |
| `passwd.exemple` | copie de travail d'un `/etc/passwd` |
| `hosts-cmdb.txt` / `hosts-supervision.txt` | deux listes triées à réconcilier |
| `sites.csv` | table de correspondance site → datacenter |
| `conf/shop.conf` et `conf/shop-propose.conf` | deux versions d'un vhost (diff/patch) |
| `encodages/` | un fichier latin-1, un script en CRLF, un CSV avec BOM |

Le format exact d'une ligne de `access.log` (retenez la position des champs, tout
le module en dépend) :

```text
198.51.100.12 - - [14/Sep/2026:08:12:03 +0200] "GET /api/v1/orders?page=3
HTTP/1.1" 200 5312 "https://shop.lab.local/" "Mozilla/5.0 ..." 0.142
 $1           $2$3 $4                  $5     $6   $7           $8  $9 $10
```

Découpé par espaces : `$1` IP, `$4` date, `$6` méthode, `$7` URL, `$9` code HTTP,
`$10` octets envoyés, `$NF` temps de réponse en secondes.

---

## 5.2 Rappel express

### Descripteurs et redirections

| Écriture | Effet |
|---|---|
| `> f` / `>> f` / `2> f` | fd 1 écrase / ajoute ; fd 2 vers `f` |
| `> f 2>&1` | fd 1 vers `f`, **puis** fd 2 vers la cible actuelle de fd 1 |
| `2>&1 > f` | fd 2 vers le terminal, fd 1 vers `f` — l'ordre compte |
| `&> f` / `&>> f` | les deux flux, raccourci bash (non POSIX) |
| `echo msg >&2` | écrire volontairement sur stderr |
| `exec 3> f` / `>&3` / `exec 3>&-` | ouvrir, utiliser, fermer un fd durable |
| `cmd < f` / `cmd <<< "$v"` | fichier / chaîne sur stdin |
| `2>/dev/null` | jeter les erreurs (jamais en production sans réfléchir) |

`2>&1` copie la **destination** du fd 1 au moment où bash lit la redirection,
de gauche à droite. Ce n'est pas un alias permanent.

```bash
cat <<EOF          # here-doc : $VAR et $(cmd) sont développés
cible=$CIBLE
EOF
cat <<'EOF'        # quoté : rien n'est développé (mot de passe, $ littéral)
mot=$PASSWORD
EOF
cat <<-EOF         # <<- supprime les TABULATIONS de tête (pas les espaces)
	indenté dans le script, aligné à gauche en sortie
	EOF
diff <(sort a) <(sort b)    # substitution de processus : /dev/fd/63
tee >(gzip > copie.gz) > sortie.txt
```

### Pipelines

| Écriture | Effet |
|---|---|
| `a \| b` | stdout de `a` vers stdin de `b` ; **stderr n'est pas dans le tube** |
| `a 2>&1 \| b` | y compris stderr |
| `${PIPESTATUS[@]}` | codes retour de **tous** les maillons, juste après le pipeline |
| `set -o pipefail` | le pipeline renvoie le dernier code non nul rencontré |
| `\| tee f` / `\| tee -a f` | duplique le flux vers l'écran et le fichier |

@fig(text-pipeline): Un pipeline classique d'analyse de journal, avec la forme des lignes qui circulent entre chaque maillon.

`xargs` : `-n N` (N arguments par appel), `-I{}` (placeholder, implique `-n 1`),
`-P N` (N processus parallèles), `-0` avec `find -print0` (noms à espaces),
`-r` (ne rien lancer si l'entrée est vide), `-t` (trace la commande).

### Découper, recomposer

| Commande | Usage type |
|---|---|
| `cut -d: -f1,7` | champs par délimiteur **mono-caractère**, pas de quoting CSV |
| `cut -c5-12` | par colonnes de caractères |
| `paste -d, a b` | colle deux fichiers côte à côte, ligne à ligne |
| `join -t, -1 9 -2 1 a b` | jointure SQL sur fichiers **triés sur la clé** |
| `tr 'a-z' 'A-Z'` / `tr -d '\r'` / `tr -s ' '` | traduire / supprimer / compresser |
| `column -t -s,` | aligner en colonnes pour l'œil humain |
| `nl -ba` / `rev` / `tac` | numéroter / inverser les caractères / les lignes |
| `split -l 2000 -d f pref-` | découper en morceaux |
| `wc -l/-w/-c/-L` | lignes / mots / octets / longueur max |

### Trier, dédoublonner

```bash
sort -t, -k3,3 -k10,10nr f.csv    # 3e champ asc, puis 10e numérique desc
sort -k2 f                   # ATTENTION : champ 2 -> FIN DE LIGNE
sort -k2,2 f                      # le champ 2 SEUL
sort -h                           # 1K, 2M, 3G  |  sort -V  : 1.10 > 1.9
sort -u                           # dédoublonne sur la clé de tri, pas la ligne
sort -s -k3,3                     # stable : conserve l'ordre d'entrée à égalité
uniq -c / -d / -u            # compte / doublons seuls / uniques seuls
comm -12 a b                      # communs (fichiers triés obligatoirement)
comm -23 a b                      # dans a seulement ; -13 : dans b seulement
```

`uniq` ne compare que des lignes **adjacentes** : sans `sort` devant, il ne sert à rien.
Le top N canonique : `... | sort | uniq -c | sort -rn | head -10`.

### grep

| Option | Effet | Option | Effet |
|---|---|---|---|
| `-E` | regex étendues | `-o` | n'affiche que la partie qui matche |
| `-P` | PCRE (`\d`, `\s`, `+?`, lookahead) | `-c` | compte les **lignes** qui matchent |
| `-v` | inverse | `-w` | mot entier |
| `-i` | ignore la casse | `-x` | ligne entière |
| `-r` / `-l` / `-L` | récursif / fichiers avec / sans match | `-q` | silencieux, pour un `if` |
| `-A n` `-B n` `-C n` | n lignes après / avant / autour | `-F` | motif littéral, pas de regex |

BRE (`grep` nu) : `+ ? { } ( ) |` doivent être échappés (`\+`, `\{2\}`).
ERE (`grep -E`) : ils sont actifs tels quels. Classes portables :
`[[:digit:]] [[:alpha:]] [[:alnum:]] [[:space:]] [[:upper:]] [[:punct:]]`.
Ancres `^ $ \< \> \b`, alternance `a|b`, groupe `(ab)+`, quantifieurs gourmands par défaut
(`.*"` va jusqu'au **dernier** guillemet de la ligne).

### sed

```bash
sed 's/ancien/nouveau/'        # 1re occurrence de chaque ligne
sed 's/a/b/g'                  # toutes ; /2 : la 2e ; /gi : sans la casse
sed -E 's#(/orders)/[0-9]+#\1/:id#g'   # groupes \1..\9, séparateur libre
sed -n '/ERROR/p'              # -n : muet ; p : imprime (= grep)
sed '5d' / sed '2,10d' / sed '/^#/d' / sed '/^$/d'
sed -n '/location \/static/,/}/p'      # plage entre deux motifs
sed -n '10,20p;25q'            # plage de lignes, q pour sortir tôt (rapide)
sed '3a txt' / '3i txt' / '3c txt'   # ajoute / insère / remplace
sed -i.bak -e 's/8m/32m/' -e '/http2/d' f  # en place AVEC sauvegarde f.bak
```

`&` dans le remplacement = tout ce qui a matché. `\1` = premier groupe capturé.
`sed -i` sans suffixe ne sauvegarde rien : sur un fichier de production, jamais sans `.bak`.

### awk

```awk
awk 'motif { action }'    # motif seul -> print $0
                          # action seule -> toutes les lignes
```

| Variable | Sens | Variable | Sens |
|---|---|---|---|
| `$0` / `$1` / `$NF` | ligne / 1er champ / dernier champ | `NF` | nombre de champs |
| `NR` | n° de ligne global | `FNR` | n° de ligne dans le fichier courant |
| `FS` / `OFS` | séparateur d'entrée / de sortie | `FILENAME` | fichier en cours |

```bash
awk -F, -v seuil=200 '$10 > seuil { n++ } END { print n+0 }' serveurs.csv
awk -F, 'NR>1 { s[$2] += $10; c[$2]++ }
         END { for (k in s)
               printf "%-8s %9.2f %3d\n", k, s[k], c[k] }' serveurs.csv
awk 'NR==FNR { m[$1]=$2; next } { print $0, m[$1] }' table.txt donnees.txt
```

`for (k in tab)` renvoie les clés dans un ordre **non défini** : repasse toujours par
`| sort` si l'ordre compte. `n+0` force le contexte numérique (affiche `0` et non vide).

### JSON, YAML, encodages

```bash
jq '.results | length' f.json
jq -r '.results[] | select(.env=="prod") | "\(.hostname) \(.ip)"' f.json
jq '[.results[].specs.ram_go] | add'          # somme
jq '[.results[] | {h: .hostname, d: .metriques.disque_pct}]'   # construction
jq -r '.results[] | [.hostname, .env] | @csv'  # sortie CSV propre
yq -r '.services | keys[]' services.yaml       # yq = jq + lecteur YAML
file -i fichier ; iconv -f ISO-8859-1 -t UTF-8 f > f.utf8
sed -i 's/\r$//' f    # = dos2unix   ;   sed -i '1s/^\xEF\xBB\xBF//' f   (BOM)
diff -u ancien nouveau > p.patch ; patch -p0 < p.patch ; patch -R -p0 < p.patch
```

---

## 5.3 Quiz — QCM

**Q5.1** — Ce pipeline tourne dans un script de production :

```bash
grep 'ERROR' /var/log/app.log | wc -l
```

`grep` ne trouve rien. Quel est le code retour du pipeline, et pourquoi ?

a) 1, car `grep` renvoie 1 quand il ne trouve rien
b) 0, car c'est le code de `wc` qui compte
c) 2, car `grep` considère l'absence de correspondance comme une erreur
d) indéterminé, il faut lire `PIPESTATUS`

**Q5.2** — Tu veux journaliser sortie **et** erreurs d'un script dans un fichier tout
en gardant l'affichage. Deux écritures sont proposées :

```bash
./maj.sh 2>&1 | tee -a maj.log     # A
./maj.sh | tee -a maj.log 2>&1     # B
```

a) A et B sont équivalentes
b) A journalise les deux flux, B seulement stdout
c) B journalise les deux flux, A seulement stdout
d) B est invalide

**Q5.3** — Que renvoie exactement cette ligne ?

```bash
printf 'b\na\nb\na\n' | uniq -c
```

a) `2 a` et `2 b`
b) quatre lignes, chacune préfixée de `1`
c) `1 b`, `1 a`, `1 b`, `1 a`
d) une erreur : `uniq` exige une entrée triée

**Q5.4** — Ces deux commandes ne donnent pas le même ordre sur `serveurs.csv`
(10 colonnes, `site` en 9e position, `cout_eur` en 10e) :

```bash
sort -t, -k9,9 serveurs.csv     # A
sort -t, -k9   serveurs.csv     # B
```

Pourquoi ?

a) aucune différence possible, `-k9,9` est une écriture redondante
b) A trie sur le champ 9 seul ; B trie sur tout ce qui va du champ 9 à la **fin de
   la ligne**, coût compris, et comparé comme du texte
c) B est invalide : `-k` exige toujours une borne de fin
d) A trie numériquement, B lexicographiquement

**Q5.5** — Tu veux compter les requêtes émises par l'adresse `10.10.10.14`, et
seulement par elle. Quelle commande est **rigoureusement** correcte ?

a) `grep -c '10.10.10.14' access.log`
b) `grep -c '10\.10\.10\.14' access.log`
c) `awk '$1 == "10.10.10.14" { n++ } END { print n+0 }' access.log`
d) `grep -cw '10.10.10.14' access.log`

**Q5.6** — Que produit `grep -o 'GET [^ ]*' access.log | head -1` sur la ligne
`... "GET /panier HTTP/1.1" 200 ...` ?

a) la ligne entière
b) `GET /panier`
c) `"GET /panier HTTP/1.1"`
d) `GET`

**Q5.7** — Tu veux remplacer toutes les occurrences de `30s` par `60s` dans un fichier,
en gardant une copie de l'original. Quelle commande ?

a) `sed 's/30s/60s/' -i.bak shop.conf`
b) `sed -i.bak 's/30s/60s/g' shop.conf`
c) `sed -i 's/30s/60s/g' shop.conf.bak`
d) `sed -g -i 's/30s/60s/' shop.conf`

**Q5.8** — Que fait `sed -n '/^server {/,/^}/p' shop.conf` ?

a) affiche la première ligne `server {` et la dernière `}`
b) affiche toutes les lignes entre la première `server {` et la première `}` en début
   de ligne qui suit, bornes incluses
c) supprime le bloc `server`
d) rien : `-n` annule le `p`

**Q5.9** — Sur ce fichier, que vaut la sortie ?

```bash
printf 'a 1\nb 2\na 3\n' | awk '{ s[$1] += $2 } END { print s["a"] }'
```

a) `1` b) `3` c) `4` d) rien, `s` n'est pas déclaré

**Q5.10** — Dans `awk`, quelle différence entre `NR` et `FNR` quand on traite deux
fichiers `a.txt` (3 lignes) puis `b.txt` (2 lignes) ?

a) aucune, ce sont des synonymes
b) à la dernière ligne, `NR` vaut 5 et `FNR` vaut 2
c) à la dernière ligne, `NR` vaut 2 et `FNR` vaut 5
d) `FNR` compte les champs, `NR` les lignes

**Q5.11** — Pourquoi `awk -F, '{ print $2 }' serveurs-piege.csv` renvoie-t-il des
valeurs tronquées comme `"Equipe Paiement` ?

a) parce que `-F,` n'accepte pas les fichiers avec en-tête
b) parce que `awk` ne gère pas les guillemets du format CSV : une virgule dans un
   champ quoté est un séparateur comme les autres
c) parce qu'il manque `-v OFS=,`
d) parce que le fichier est en CRLF

**Q5.12** — Quel filtre `jq` affiche, sans guillemets, le nom des hôtes de production ?

a) `jq '.results[] | select(.env=="prod") | .hostname' f.json`
b) `jq -r '.results[] | select(.env=="prod") | .hostname' f.json`
c) `jq -r '.results | select(.env=="prod") | .hostname' f.json`
d) `jq -r '.results[].hostname | select(.env=="prod")' f.json`

**Q5.13** — Un script livré par un dev sous Windows échoue à la première ligne avec
`$'\r': command not found`. Quelle commande diagnostique le problème le plus vite ?

a) `bash -x script.sh`
b) `file script.sh`
c) `stat script.sh`
d) `head -1 script.sh`

**Q5.14** — À propos de stderr dans un pipeline `cmd1 | cmd2`.
**Deux réponses correctes.**

a) par défaut, stderr de `cmd1` part sur le terminal et ne traverse pas le tube
b) par défaut, stderr de `cmd1` est mélangé à stdout dans le tube
c) `cmd1 2>&1 | cmd2` fait passer les deux flux de `cmd1` dans le tube
d) `cmd1 | cmd2 2>&1` fait passer les deux flux de `cmd1` dans le tube

**Q5.15** — Quelle commande liste les hôtes présents dans `hosts-cmdb.txt` mais
**absents** de `hosts-supervision.txt` (les deux fichiers sont triés) ?

a) `comm -12 hosts-cmdb.txt hosts-supervision.txt`
b) `comm -23 hosts-cmdb.txt hosts-supervision.txt`
c) `comm -13 hosts-cmdb.txt hosts-supervision.txt`
d) `diff hosts-cmdb.txt hosts-supervision.txt | grep '>'`

**Q5.16** — Tu lances :

```bash
find /var/log -name '*.log' -print0 | xargs -0 -n 20 -P 4 gzip
```

Que fait `-P 4` ? **Deux réponses correctes.**

a) limite à 4 fichiers par appel de `gzip`
b) lance jusqu'à 4 `gzip` en parallèle
c) mélange potentiellement les sorties des processus sur le terminal
d) impose l'ordre de traitement des fichiers

**Q5.17** — Dans un here-doc, quelle différence entre `<<EOF` et `<<'EOF'` ?

a) aucune, les quotes sont cosmétiques
b) avec `<<'EOF'`, ni `$VAR` ni `$(cmd)` ne sont développés
c) avec `<<'EOF'`, les tabulations de tête sont supprimées
d) `<<'EOF'` interdit les lignes vides

**Q5.18** — Tu veux comparer les listes de paquets de deux serveurs sans créer de
fichiers temporaires. Quelle écriture ?

a) `diff $(ssh lab-web dpkg -l) $(ssh lab-db dpkg -l)`
b) `diff <(ssh lab-web dpkg -l) <(ssh lab-db dpkg -l)`
c) `diff <<<"$(ssh lab-web dpkg -l)" <<<"$(ssh lab-db dpkg -l)"`
d) `ssh lab-web dpkg -l | diff - <(ssh lab-db dpkg -l)`, mais seulement avec `-`

---

## 5.4 Quiz — questions ouvertes

**QO5.1** — Explique, descripteurs à l'appui, la différence entre
`cmd > f 2>&1` et `cmd 2>&1 > f`. Puis décris un cas réel où la seconde forme est
exactement ce qu'on veut.

::: repondre
lignes: 8
:::

**QO5.2** — *On te demande en entretien* : « Notre script de sauvegarde se termine
toujours en succès, même quand le `pg_dump` plante. Le pipeline est
`pg_dump ... | gzip > dump.sql.gz`. Explique le problème et donne deux corrections
différentes. »

::: repondre
lignes: 8
:::

**QO5.3** — Compare `grep`, `sed` et `awk` pour extraire la troisième colonne d'un
fichier délimité. Donne la commande dans chaque outil, puis explique dans quel cas
chacun est le bon choix — et lequel tu interdirais en revue de code.

::: repondre
lignes: 8
:::

**QO5.4** — On te donne ce pipeline :

```bash
awk '{ print $1 }' access.log | sort | uniq -c | sort -rn | head -10
```

Détaille ce que fait **chaque** maillon et ce qui casse si on retire le premier `sort`.
Estime ensuite le coût : que se passe-t-il sur un fichier de 40 Go, et que
proposerais-tu à la place ?

::: repondre
lignes: 10
:::

**QO5.5** — *On te demande en entretien* : « Un `sort -k2 -n` sur un fichier de logs
donne un ordre incohérent en production alors qu'il est correct sur ton poste.
Cite trois causes possibles et la commande qui tranche pour chacune. »

::: repondre
lignes: 8
:::

**QO5.6** — Explique la différence entre une substitution de commande `$(cmd)`, un
here-string `<<<`, et une substitution de processus `<(cmd)`. Donne pour chacune un
cas où les deux autres ne conviennent pas.

::: repondre
lignes: 8
:::

**QO5.7** — Un développeur veut extraire le champ `"version"` d'un JSON avec
`grep -o '"version":"[^"]*"'`. Explique pourquoi tu refuses en revue de code, en
citant au moins trois cas concrets où ça casse, et ce que tu proposes.

::: repondre
lignes: 8
:::

**QO5.8** — Décris ta démarche complète, commande par commande, pour répondre à
« pourquoi le site a-t-il été lent hier entre 14 h et 16 h ? » avec pour seule
donnée un `access.log` au format `combined` + `$request_time`. Précise, pour chaque
étape, la question à laquelle elle répond.

::: repondre
lignes: 12
:::

**QO5.9** — Explique le mécanisme de `awk 'NR==FNR { ... ; next } { ... }'`.
Pourquoi `next` est-il indispensable ? Que se passe-t-il si le premier fichier est
vide, et comment t'en prémunir ?

::: repondre
lignes: 8
:::

**QO5.10** — Un `.csv` généré par un tableur fait échouer un script qui fonctionnait
jusque-là. Liste cinq causes possibles liées au format (encodage, fins de ligne,
séparateur, quoting, en-tête), et pour chacune la commande de diagnostic et le
correctif en une ligne.

::: repondre
lignes: 10
:::

---

## 5.5 Exercices guidés ★

Tous les exercices se font dans `~/lab05`. Sauf mention contraire, une seule ligne
de commande suffit.

**E5.1** — Affiche les 15 dernières lignes de `access.log` puis reste à l'écoute des
nouvelles lignes. Explique ensuite, en une phrase, pourquoi `tail -f` perd la trace du
fichier après une rotation logrotate et quelle option corrige ça.

**E5.2** — Donne la répartition des codes HTTP de `access.log`, du plus fréquent au
plus rare, sous la forme `nombre code`.

**E5.3** — Donne le top 10 des IP clientes, **en excluant** la sonde de monitoring
`10.10.10.14` et le scanner `203.0.113.242`.

**E5.4** — Combien d'URL **distinctes** ont renvoyé un 404 ? Affiche ensuite les 5 URL
en 404 les plus demandées avec leur nombre de hits.

**E5.5** — À partir de `passwd.exemple` : liste les comptes dont l'UID est compris
entre 1000 et 59999, avec leur shell, triés par UID croissant, en colonnes alignées.
Puis compte les comptes par shell, du plus fréquent au plus rare.

**E5.6** — Dans `serveurs.csv` : affiche les 5 serveurs les plus chers (hostname et
coût uniquement). Puis produis un tri « environnement par ordre alphabétique, et à
l'intérieur de chaque environnement, coût décroissant ».

**E5.7** — Sans utiliser `awk` ni `cut`, extrais toutes les adresses IP clientes de
`access.log` et compte combien d'adresses distinctes apparaissent.

**E5.8** — Combien de requêtes vers `/api/` ont mis plus de 2 secondes ? Affiche la
requête la plus lente du fichier avec son horodatage, son URL et son temps.

**E5.9** — Dans `app.log` : combien d'événements de niveau `ERROR` ? Puis la liste des
types d'exception rencontrés, avec leur nombre d'occurrences, du plus fréquent au
plus rare.

**E5.10** — Affiche la pile d'appel complète de la **première** `OutOfMemoryError` de
`app.log` : la ligne du journal qui la précède, la ligne d'exception, et les 10 lignes
suivantes.

**E5.11** — Les URL de `access.log` contiennent des paramètres et des identifiants
numériques (`/api/v1/orders/12937?x=1`). Normalise-les (suppression de la chaîne de
requête, identifiants remplacés par `:id`) et donne le top 10 des endpoints
normalisés.

**E5.12** — Affiche uniquement le bloc `location /static/ { ... }` de
`conf/shop.conf`, accolade fermante comprise, en utilisant un adressage par plage de
motifs. Puis produis une version de ce fichier sans lignes vides.

**E5.13** — Dans `commandes.csv` : chiffre d'affaires total, puis par région le
nombre de commandes, le total et le panier moyen, alignés en colonnes, régions triées
par chiffre d'affaires décroissant.

**E5.14** — Enrichis `serveurs.csv` avec le datacenter : pour chaque serveur, affiche
`hostname site datacenter` en utilisant `sites.csv` comme table de correspondance, en
un seul `awk`.

**E5.15** — Avec `jq` : liste les hôtes dont le disque dépasse 85 % sous la forme
`hostname ip pourcentage`, puis produis un tableau JSON d'objets
`{"hote": ..., "disque": ...}` pour les mêmes hôtes. Avec `yq` : affiche le nombre
total de replicas déclarés dans `services.yaml`.

**E5.16** — Écris un pipeline qui compte les lignes `ERROR` de `app.log`, écrit le
résultat à l'écran **et** dans `rapports/nb-erreurs.txt`, et qui **échoue** (code
retour non nul) si le motif n'est trouvé nulle part. Prouve-le en cherchant un motif
inexistant, puis affiche les codes retour de chaque maillon.

---

## 5.6 Labs ★★

### **L5.1** — INC-4412 : « le site est lent depuis mardi »

::: contexte
Mardi 15 septembre, le support remonte des lenteurs sur `shop.lab.local`. Le chef de
projet veut « des chiffres, pas des impressions », pour arbitrer entre une montée en
charge et un correctif applicatif. Tu n'as que `~/lab05/access.log` (format combined
+ `$request_time`). Livrable attendu : un fichier texte lisible, chiffré,
`~/lab05/rapports/rapport-acces.txt`.
:::

1. Vérifie d'abord ce que tu manipules : nombre de lignes, période couverte
   (première et dernière date), nombre d'IP distinctes.
2. Répartition des codes HTTP, en valeur absolue **et** en pourcentage du total.
3. Volume par jour, puis par heure toutes journées confondues : identifie l'heure de
   pointe.
4. Top 10 des endpoints **normalisés** (sans chaîne de requête, identifiants
   numériques remplacés par `:id`) par nombre de hits.
5. Pour ces mêmes endpoints normalisés, le temps de réponse **moyen** et le **maximum**,
   en ne gardant que ceux vus au moins 50 fois. Classe par moyenne décroissante.
6. Les 10 requêtes les plus lentes du fichier, avec horodatage, URL et durée.
7. Toutes les réponses 5xx : combien, réparties sur quels endpoints, et à quelles
   heures.
8. Assemble le tout dans `rapports/rapport-acces.txt` avec des titres de section
   lisibles, et termine par trois lignes de conclusion : ce qui est lent, qui en
   souffre, ce que tu proposes.

::: astuce
Pour l'étape 8, un here-doc vers `tee` est plus lisible que quinze `>>` successifs.
Et `exec 3> rapport.txt` permet d'écrire dans le rapport (`>&3`) tout en gardant
l'écran pour tes essais.
:::

::: check
Critère de succès : le rapport existe, contient les huit sections, et les chiffres
correspondent au fichier (le script de vérification les recalcule).

```bash
bash check_M05_01.sh
```
:::

---

### **L5.2** — Réconcilier la CMDB, l'API et la supervision

::: contexte
Trois sources décrivent le même parc et aucune n'est d'accord : `serveurs.csv`
(export CMDB), `api-inventaire.json` (l'API de la CMDB, plus riche : métriques,
tags, état de l'agent) et `hosts-supervision.txt` (ce que la supervision voit
vraiment). L'audit annuel commence dans deux jours ; on te demande la liste des
écarts et un inventaire consolidé.
:::

1. Vérifie que `serveurs.csv` et `api-inventaire.json` décrivent bien les mêmes hôtes,
   sans créer de fichier temporaire.
2. Liste les hôtes **de la CMDB non supervisés**, puis les hôtes **supervisés inconnus
   de la CMDB**. Donne les deux comptes.
3. Depuis le JSON : les hôtes dont l'agent est marqué inactif, et ceux dont le disque
   dépasse 85 %.
4. Produis `rapports/parc-complet.csv` avec l'en-tête
   `hostname,env,role,site,datacenter,cout_eur,disque_pct,supervise` : les six premières
   colonnes viennent du CSV enrichi par `sites.csv`, `disque_pct` vient du JSON,
   `supervise` vaut `oui`/`non` selon la liste de supervision.
5. À partir de ce fichier consolidé : coût mensuel total, coût par environnement, et
   coût des machines **non supervisées** (l'argument qui fait bouger les choses).
6. Affiche le résultat de l'étape 5 aligné en colonnes pour le mettre dans un mail.
7. Écris `rapports/ecarts-parc.txt` : les deux listes d'écarts, les hôtes inactifs,
   les disques pleins, et une ligne de synthèse par point.

::: attention
`serveurs-piege.csv` montre pourquoi `awk -F,` n'est pas un parseur CSV : regarde ce
que donne `awk -F, '{ print $2 }'` dessus avant de généraliser ta méthode.
:::

::: check
```bash
bash check_M05_02.sh
```
:::

---

### **L5.3** — Autopsie d'un journal applicatif multi-lignes

::: contexte
L'application `factura` a passé une mauvaise journée le 18 septembre. Le dev réclame
« la liste des erreurs », mais son journal empile des piles d'appel Java de dix lignes :
un `grep ERROR` ne montre que la pointe de l'iceberg, et un `wc -l` donne un chiffre
faux. Livrable : `~/lab05/rapports/erreurs-app.txt`.
:::

1. Combien de **lignes** dans `app.log` ? Combien d'**événements** de journal
   (les lignes commençant par un horodatage) ? Explique l'écart.
2. Répartition des événements par niveau (`INFO`, `DEBUG`, `WARN`, `ERROR`).
3. Les types d'exception, avec leur nombre, du plus fréquent au plus rare — puis la
   même chose pour les lignes `Caused by:`.
4. Quel couple (exception, cause racine) domine ? Donne le chiffre qui le prouve.
5. Distribution des `ERROR` par heure, et par thread. L'un des threads est-il
   sur-représenté ?
6. Extrais dans `rapports/oom.txt` les événements `OutOfMemoryError` **avec leur pile
   d'appel complète** (de la ligne de journal jusqu'à la dernière ligne `at ...`).
7. Pour les erreurs de paiement : extrais les codes de refus banque
   (`code=NN`) et compte-les.
8. Rédige `rapports/erreurs-app.txt` : les chiffres des étapes 1 à 7 et, en trois
   lignes, ce que tu dis au dev.

::: astuce
Une ligne d'événement commence par `2026-09-18 ` ; une ligne de pile commence par une
tabulation ; une ligne d'exception commence par un nom de classe qualifié. Trois
familles, trois expressions régulières ancrées. `grep -A` et `sed` savent travailler
par plage : `sed -n '/ligne de debut/,/ligne de fin/p'`.
:::

::: check
```bash
bash check_M05_03.sh
```
:::

---

### **L5.4** — Le livrable venu de Windows

::: contexte
Une équipe externe livre un script de déploiement, un export client et un CSV
« corrigé dans Excel ». Rien ne fonctionne : le script refuse de démarrer, les accents
sont illisibles et un `grep` sur l'en-tête du CSV ne trouve rien. Tu as trente minutes
avant la réunion de recette. Travaille dans `~/lab05/encodages/`.
:::

1. Pour chacun des trois fichiers, établis un diagnostic **avec preuve** : quelle
   commande, quelle sortie, quelle conclusion.
2. `deploiement.sh` : lance-le, note le message d'erreur exact, montre le caractère
   fautif de façon visible, puis corrige le fichier sans éditeur interactif. Vérifie
   que le script démarre ensuite.
3. `clients-latin1.csv` : convertis-le en UTF-8 dans `clients-utf8.csv` et prouve la
   conversion avec `file` et un affichage lisible.
4. `export-tableur.csv` : explique pourquoi `grep -c '^hostname' export-tableur.csv`
   renvoie 0 alors que la première ligne commence visiblement par `hostname`. Corrige.
5. Compare `../conf/shop.conf` et `../conf/shop-propose.conf` : produis un diff
   unifié lisible, et dis en une phrase ce que change la proposition.
6. Fabrique un patch `../conf/shop.patch`, applique-le à une copie de `shop.conf`,
   vérifie que le résultat est identique à `shop-propose.conf`, puis annule le patch.
7. Écris `../rapports/recette-livraison.txt` : trois lignes de diagnostic, trois de
   correctif, et la règle que tu imposeras au prestataire pour la prochaine livraison.

::: check
```bash
bash check_M05_04.sh
```
:::

---

### **L5.5** — Brute force SSH : produire une liste de bannissement

::: contexte
`lab-web` prend des tentatives de connexion SSH en continu. Avant d'installer quoi que
ce soit, l'équipe sécurité veut savoir ce qu'on encaisse exactement et une liste d'IP
à bloquer, avec les éléments qui justifient chaque blocage. Source :
`~/lab05/journal-ssh.txt` (extrait de `journalctl -u ssh -o short-iso`).
:::

1. Combien de lignes au total, combien d'échecs d'authentification par mot de passe,
   combien de connexions acceptées ?
2. Top des IP sources d'échec, avec leur nombre. Top des comptes visés.
3. Pour la pire IP : sa première et sa dernière apparition, et la liste des comptes
   qu'elle a essayés.
4. Les connexions **acceptées** : depuis quelles IP, combien de fois ? Vérifie
   qu'aucune IP attaquante ne figure dans cette liste (c'est la question qui compte).
5. Produis `rapports/ips-a-bannir.txt` : une IP par ligne, uniquement celles qui
   totalisent **50 échecs ou plus**, triées par nombre d'échecs décroissant, sans
   compteur dans le fichier (il doit être consommable directement).
6. Produis `rapports/ips-a-bannir.sh` : une ligne `sudo ufw deny from <IP> to any port 22`
   par IP, générée à partir du fichier précédent. Ne l'exécute pas.
7. Fabrique la synthèse dans `rapports/rapport-ssh.txt` : les chiffres, le top 5 des
   IP, le top 5 des comptes, et la phrase que tu mets dans le ticket.

::: astuce
`journal-ssh.txt` mélange plusieurs formulations : `Failed password for root from ...`
et `Failed password for invalid user admin from ...`. Une seule expression régulière
doit couvrir les deux, sinon tes comptes seront faux — et c'est exactement le genre
d'erreur qu'on te reprochera.
:::

::: check
```bash
bash check_M05_05.sh
```
:::

---

## 5.7 Break & Fix ★★★

::: attention
Avant chaque Break & Fix : `qm snapshot 9001 avant-bf05`. Rien ici ne touche au
système : les scripts n'agissent que sur `~/lab05` et sauvegardent ce qu'ils modifient
dans `~/.breakfix-backup/M05/`. En dernier recours, `bash setup_M05.sh` régénère les
données — mais l'utiliser avant d'avoir compris vaut échec de l'exercice.
:::

### **BF5.1** — « Le rapport quotidien est vide, et personne n'a été prévenu »

```bash
bash break_M05_01.sh
```

**Symptôme utilisateur** : le script `~/lab05/bin/rapport-quotidien.sh` tourne chaque
matin en cron. Depuis lundi, `rapports/quotidien.txt` ne contient plus que sa ligne de
titre — aucun chiffre — mais le script se termine avec le code retour 0 : la
supervision n'a rien signalé et personne ne s'en est aperçu pendant trois jours.

**Interdit** : réécrire le script entièrement, régénérer les données.

**Objectif** : trouver pourquoi le rapport est vide, pourquoi le script sort quand
même en 0, corriger les deux problèmes séparément, et dire quelle ligne de bash aurait
évité trois jours de silence.

::: repondre
lignes: 10
:::

### **BF5.2** — « Le déploiement échoue avec une erreur qui n'a aucun sens »

```bash
bash break_M05_02.sh
```

**Symptôme utilisateur** : `~/lab05/bin/livrer.sh` lit sa configuration dans
`~/lab05/conf/livraison.env`, s'arrête en code 2 et affiche un message tronqué et
illisible, du genre `]ible inconnue : [/srv/factura` — comme si le crochet fermant
avait mangé le début de la ligne. La valeur affichée est pourtant la bonne, et un
`cat` du fichier de configuration ne montre rien d'anormal.

**Interdit** : modifier `livrer.sh`, il est correct.

**Objectif** : rendre le fichier de configuration exploitable, expliquer pourquoi la
comparaison échouait alors que `cat` semble donner raison à l'utilisateur, et donner
la commande qui aurait montré le problème en une seconde.

::: repondre
lignes: 8
:::

### **BF5.3** — « Le top 10 des IP compte deux fois la même adresse »

```bash
bash break_M05_03.sh
```

**Symptôme utilisateur** : le script `~/lab05/bin/top-ip.sh` sort un classement où
`198.51.100.12` apparaît trois fois avec trois compteurs différents, et où le total
des compteurs ne correspond plus au nombre de lignes du journal. Le fichier source
n'a pas changé de format, juste de provenance (il vient maintenant d'un agrégateur).

**Interdit** : filtrer manuellement les doublons dans le résultat final.

**Objectif** : identifier ce qui distingue des lignes visuellement identiques,
corriger le pipeline pour que le classement soit juste quelle que soit la provenance
du fichier, et expliquer pourquoi `uniq` n'a pas fait son travail.

::: repondre
lignes: 8
:::

---

## 5.8 Défi du module ★★★

**D5 — Le rapport d'exploitation hebdomadaire, sans ouvrir un tableur**

::: contexte
Tous les lundis, l'équipe passe une demi-journée à copier-coller des chiffres dans un
document. On te demande de produire le rapport de la semaine du 14 au 18 septembre
uniquement avec les outils de ce module, et de livrer **les pipelines** en même temps
que le rapport pour que ce soit rejouable la semaine suivante.
:::

Cahier des charges :

1. Livrable 1 : `~/lab05/rapports/hebdo-2026-S38.md`, en Markdown valide, avec
   exactement ces sections :
   * `## Trafic web` — volume total, volume par jour, heure de pointe, part des 4xx et
     des 5xx en pourcentage à une décimale ;
   * `## Performance` — les 5 endpoints normalisés les plus lents (moyenne et max),
     sur les endpoints vus au moins 50 fois, présentés en **tableau Markdown** ;
   * `## Erreurs applicatives` — nombre d'événements `ERROR`, top 3 des exceptions,
     cause racine dominante ;
   * `## Sécurité` — nombre d'échecs SSH, top 3 des IP, top 3 des comptes visés,
     nombre d'IP au-dessus de 50 échecs ;
   * `## Parc` — nombre d'hôtes, coût mensuel total, coût des hôtes non supervisés,
     nombre d'hôtes avec disque > 85 % ;
   * `## Actions proposées` — trois puces, chacune appuyée sur un chiffre du rapport.
2. Livrable 2 : `~/lab05/rapports/hebdo-pipelines.sh`, un fichier contenant, commenté,
   **un pipeline par chiffre du rapport**. Une ligne de commentaire décrit le chiffre
   produit, la ligne suivante est le pipeline. Pas de fonction, pas de boucle : le
   scripting structuré, c'est le module 07 ; ici on démontre la maîtrise des filtres.
3. Contraintes techniques :
   * aucun fichier temporaire : substitution de processus, here-doc, `tee`, `exec 3>` ;
   * aucun `cat` inutile en tête de pipeline ;
   * chaque pipeline doit être robuste à l'absence de correspondance (utilise
     `set -o pipefail` en tête du fichier de pipelines et justifie ce choix en
     commentaire) ;
   * les nombres décimaux sont formatés avec `printf`, pas laissés bruts.
4. Vérification : les chiffres du rapport doivent être **exacts**. Le script de
   vérification les recalcule indépendamment et compare.

Temps visé : 60 à 90 minutes.

::: check
```bash
bash check_M05_06.sh
```
:::

---

## 5.9 Auto-évaluation

| Compétence | Acquis | À revoir |
|---|---|---|
| Rediriger les fd à la main, prédire l'effet de l'ordre | ☐ | ☐ |
| Here-doc, here-string, substitution de processus | ☐ | ☐ |
| `pipefail`, `PIPESTATUS`, `tee`, `xargs -P/-0/-I` | ☐ | ☐ |
| `cut`, `paste`, `join`, `tr`, `split`, `column` | ☐ | ☐ |
| `sort -t -k` sans me tromper de champ, `uniq -c/-d/-u`, `comm` | ☐ | ☐ |
| Écrire une regex BRE et ERE, choisir `grep -E` ou `-P` | ☐ | ☐ |
| `sed` : substitution, groupes, plages, `-i` sauvegardé | ☐ | ☐ |
| `awk` : tableaux associatifs, `NR`/`FNR`, `printf` | ☐ | ☐ |
| `jq` et `yq` plutôt que `grep` sur du structuré | ☐ | ☐ |
| Diagnostiquer encodage, CRLF, BOM | ☐ | ☐ |
| `diff -u`, `patch`, comparer sans fichier temporaire | ☐ | ☐ |
| Produire un rapport chiffré depuis un access.log | ☐ | ☐ |

Pour aller plus loin :

* Refais L5.1 avec `goaccess` (`sudo apt install goaccess`) et compare : ce que
  l'outil dédié fait mieux, et ce que ton pipeline fait que lui ne fait pas.
* Lis `man 7 regex` en entier une fois, puis `info awk` section « Arrays ».
* Compare les performances de `grep -c`, `awk '/motif/ {n++} END {print n}'` et
  `LC_ALL=C grep -c` sur `access.log` avec `time` : l'écart de locale surprend.
* Reprends E5.11 avec `grep -P` et un lookahead : mesure si le gain en concision vaut
  la perte de portabilité (`grep -P` n'existe pas sur BusyBox ni sur macOS).
