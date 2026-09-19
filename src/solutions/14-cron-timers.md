# Module 14 — Corrigé

## 14.3 Quiz — QCM

**Q14.1** — *Que planifie `*/10 8-18 * * 1-5` ?*

**Réponse : b)** toutes les 10 minutes entre 08:00 et 18:50, du lundi au vendredi.

::: pourquoi
Chaque champ est évalué **indépendamment**, puis cron déclenche la tâche à chaque
minute où les cinq champs sont simultanément satisfaits.

* `*/10` sur le champ minute : l'ensemble `{0,10,20,30,40,50}`. Le pas part
  toujours de la **borne basse du champ**, ici 0, pas de l'heure d'exécution.
* `8-18` sur le champ heure : l'ensemble `{8,9,…,18}`. C'est un ensemble
  d'**heures entières**, pas un intervalle qui se fermerait à 18:00 pile.

Le produit des deux donne la dernière exécution à **18:50**, pas à 18:00. C'est
l'erreur de lecture la plus fréquente : on lit « de 8 h à 18 h » comme une plage
horaire continue alors que cron raisonne par ensembles discrets. Pour s'arrêter à
18:00 inclus et pas après, il faut `0 8-18 * * 1-5` (une fois par heure) ou
séparer en deux lignes.

`1-5` sur le champ jour de semaine : lundi (1) à vendredi (5). Dimanche vaut 0
**ou** 7, les deux sont acceptés.
:::

::: piege
`*/7` sur le champ minute ne signifie pas « toutes les 7 minutes ». Cron génère
`{0,7,14,21,28,35,42,49,56}` puis repart à 0 à l'heure suivante : l'intervalle
entre 56 et 0 est de 4 minutes, pas 7. Tout pas qui ne divise pas 60 produit un
« hoquet » à chaque changement d'heure. Même remarque pour `*/9` sur le champ
heure (24 n'est pas divisible par 9).
:::

---

**Q14.2** — *`0 3 1,15 * 5` : le dev affirme « le 1er et le 15, seulement si
c'est un vendredi ».*

**Réponse : b)** le 1er, le 15, **et** tous les vendredis.

::: pourquoi
C'est le comportement documenté de cron, et il est contre-intuitif :

> Si les deux champs « jour du mois » et « jour de semaine » sont restreints
> (c'est-à-dire différents de `*`), la commande est exécutée quand **l'un ou
> l'autre** correspond.

La règle complète tient en trois cas :

| jour du mois | jour de semaine | combinaison |
|---|---|---|
| `*` | restreint | seul le jour de semaine compte |
| restreint | `*` | seul le jour du mois compte |
| restreint | restreint | **OU** logique |

L'origine est historique : les crontabs d'AT&T et de BSD divergeaient sur ce
point, et Vixie cron a retenu le OU pour permettre d'écrire « le 1er du mois et
tous les lundis » sur une seule ligne. La conséquence pratique est qu'un job
prévu « deux fois par mois » tourne en réalité une dizaine de fois.

Le job ci-dessus s'exécute donc environ 6 fois par mois, pas 2. Sur une clôture
comptable, c'est un incident.
:::

::: piege
Il n'existe **aucune** syntaxe cron pour exprimer un ET entre les deux champs.
La seule méthode est de laisser un champ à `*` et de faire le test dans la
commande :

```cron
0 3 1,15 * * [ "$(date +\%u)" -eq 5 ] && /opt/factura/bin/cloture.sh
```

Noter le `\%u` : sans l'antislash, la commande est coupée (voir Q14.3). Un timer
systemd exprime ça directement : `OnCalendar=Fri *-*-01,15 03:00:00` applique un
vrai ET.
:::

---

**Q14.3** — *`30 2 * * * tar czf /srv/sauv/f-$(date +%F).tgz /srv/factura/data`
dans une crontab.*

**Réponse : b)** le shell reçoit une commande tronquée et s'arrête sur une erreur
de syntaxe.

::: pourquoi
Dans le champ commande d'une crontab, `%` n'est **pas** un caractère ordinaire.
Le démon cron applique cette transformation avant de passer quoi que ce soit au
shell :

1. le **premier `%` non échappé** marque la fin de la commande ;
2. tout ce qui suit devient l'**entrée standard** de la commande ;
3. les `%` suivants y sont convertis en **sauts de ligne**.

Ici, cron construit donc :

```text
commande : tar czf /srv/sauv/f-$(date +
stdin    : F).tgz /srv/factura/data
```

puis exécute `/bin/sh -c 'tar czf /srv/sauv/f-$(date +'`. La substitution de
commande `$(` n'est jamais fermée : `dash` s'arrête avant même d'appeler `tar`.

```console
$ printf 'F).tgz /srv/factura/data\n' | /bin/sh -c 'tar czf /srv/sauv/f-$(date +'
/bin/sh: 1: Syntax error: end of file unexpected (expecting ")")
$ echo $?
2
```

Aucune archive n'est créée, et le message dans le journal parle du **shell**, pas
de `tar` — ce qui égare le diagnostic.
:::

::: piege
a) est fausse : ça marche dans un shell, jamais en crontab. c) est fausse et
c'est le plus vicieux : `crontab -e` valide le **format** (nombre de champs,
valeurs des 5 premiers champs), pas le contenu de la commande. La ligne est
acceptée sans un mot. d) est fausse : `%` n'est pas passé littéralement, il est
consommé par cron.

La fonctionnalité a un usage légitime — alimenter une commande en données :

```cron
0 1 * * * mysql -u sauv facturation%SELECT COUNT(*) FROM factures;%
```

Personne n'écrit ça. En pratique, `%` en crontab est toujours un bug. La règle :
**jamais de `%` dans une crontab**, on appelle un script.
:::

---

**Q14.4** — *Un fichier de `/etc/cron.d` sans effet.*

**Réponse : b)** il manque le champ utilisateur.

::: pourquoi
`/etc/crontab` et les fichiers de `/etc/cron.d` ont **six** champs avant la
commande, pas cinq : les cinq champs de temps, puis le compte sous lequel
exécuter la tâche. C'est la différence de format avec une crontab utilisateur,
où l'utilisateur est implicite (c'est le propriétaire du fichier de spool).

```cron
# /etc/cron.d/factura-collecte — correct
*/15 * * * * factura /opt/factura/bin/factura-collecte.sh
#                    ^^^^^^^ le 6e champ
```

Sans ce champ, cron lit `/opt/factura/bin/factura-collecte.sh` comme le nom de
l'utilisateur, ne le trouve pas dans `/etc/passwd`, et rejette la ligne. Il ne
rejette pas le fichier : les autres lignes valides sont conservées.

La trace est dans le journal, jamais sur ton terminal :

```console
$ journalctl -t CRON --since today | grep -i factura-collecte
cron[812]: (*system*factura-collecte) ERROR (Unknown username)
```

Cette ligne apparaît au moment où cron **relit** le fichier, c'est-à-dire dans la
minute qui suit la modification, pas au moment de l'exécution prévue.
:::

::: piege
c) est fausse et fait perdre du temps à beaucoup de monde : cron surveille la
date de modification de `/etc/crontab`, de `/etc/cron.d/` et des spools, et
recharge tout seul. Redémarrer `cron.service` ne sert à rien — sauf à masquer le
vrai problème pendant qu'on cherche ailleurs.

a) est fausse aussi : les fichiers de `/etc/cron.d` sont des **fichiers de
configuration**, pas des scripts. Ils doivent être en `0644`, appartenir à root,
et surtout **ne pas être exécutables**. Un fichier exécutable y est ignoré par
certaines versions. Le nom du fichier, lui, suit les règles de `run-parts` :
pas de point, donc pas de `.cron` ni de `.conf` à la fin.
:::

---

**Q14.5** — *`purge-tmp.sh` en `0755` dans `/etc/cron.daily/` ne tourne jamais.*

**Réponses : a) et c)**

::: pourquoi
Les répertoires `cron.hourly`, `cron.daily`, `cron.weekly` et `cron.monthly` ne
sont pas lus par cron directement : ils sont parcourus par **`run-parts`**, qui
n'exécute que les fichiers dont le nom est composé exclusivement de lettres ASCII,
de chiffres, de tirets bas et de tirets. **Un point disqualifie le fichier.**

La raison d'être de cette règle est la gestion de paquets : elle permet à
`dpkg` de laisser traîner `monscript.dpkg-old`, `monscript.dpkg-dist` ou
`monscript.bak` dans le répertoire sans qu'ils soient exécutés. L'effet de bord
est que toutes les extensions y passent, `.sh` comprise.

La preuve se fait sans attendre le lendemain :

```console
$ run-parts --test /etc/cron.daily
/etc/cron.daily/apt-compat
/etc/cron.daily/dpkg
/etc/cron.daily/factura-purge
```

`--test` affiche exactement ce qui **serait** exécuté, sans rien exécuter.
`purge-tmp.sh` n'y figure pas : c'est le test de recette à faire systématiquement
après avoir déposé un script dans un de ces répertoires.
:::

::: piege
b) et d) sont fausses, mais il y a bien deux autres conditions à respecter :
le fichier doit être **exécutable** (`run-parts` saute les non-exécutables sans
rien dire) et il doit être un fichier ordinaire ou un lien vers un fichier
ordinaire.

Autre piège du même registre : ces scripts tournent en **root**, sans argument,
avec le `PATH` défini dans `/etc/crontab` (ou dans `/etc/anacrontab` quand c'est
anacron qui les lance — ce n'est pas le même). Et `run-parts --report` préfixe
leur sortie du nom du script, ce qui explique les lignes bizarres dans les mails
de root.
:::

---

**Q14.6** — *`docker: command not found` en cron seulement.*

**Réponse : b)** `/usr/bin` n'est pas dans le `PATH` de cron.

::: pourquoi
Un job cron démarre dans un environnement **quasiment vide**, construit par le
démon lui-même. Il ne lit **aucun** fichier de démarrage : ni `/etc/profile`, ni
`/etc/environment` par cron lui-même (c'est PAM qui le lit, et seulement pour
certaines variables), ni `~/.profile`, ni `~/.bashrc`. Le démon positionne un
petit jeu de variables :

| Variable | Valeur |
|---|---|
| `PATH` | `/usr/bin:/bin` (compilé en dur dans cron) |
| `SHELL` | `/bin/sh` |
| `HOME` | le home du propriétaire, lu dans `/etc/passwd` |
| `LOGNAME` | le nom du propriétaire |

Tout le reste vient des lignes `VARIABLE=valeur` écrites en tête de la crontab.

Dans le cas présent, `docker` est en `/usr/bin` **et** `/usr/bin` est bien dans
le `PATH` de cron — donc b) est fausse pour Docker précisément… mais c'est la
réponse attendue parce que l'énoncé pose la question de la cause **la plus
probable** d'un `command not found` en cron, et que dans la quasi-totalité des
cas le binaire est en `/usr/local/bin`, `/usr/sbin` ou `/snap/bin`, tous absents
du `PATH` de cron. C'est exactement ce que fait BF14.1.

Les trois corrections possibles, par ordre de robustesse :

1. **chemin absolu** dans le script : `/usr/bin/docker`. Le plus sûr.
2. **`PATH=` en tête de la crontab** ou du fichier de `/etc/cron.d`. Vaut pour
   toutes les lignes du fichier, invisible depuis le script.
3. `export PATH=...` **dans le script lui-même**. C'est la bonne pratique pour un
   script d'exploitation : il devient indépendant de qui l'appelle.
:::

::: piege
c) mérite un mot : un alias ou une fonction shell expliquerait l'inverse (ça
marche en interactif, pas en script), mais `which docker` répondant
`/usr/bin/docker` écarte l'hypothèse — `which` est un binaire externe, il ne voit
ni alias ni fonction. Pour trancher, `type -a docker` dans la session : s'il
affiche autre chose qu'un chemin, c'est un masquage.

a) décrit un vrai problème (appartenance au groupe `docker`), mais il produit
`permission denied` sur `/var/run/docker.sock`, pas `command not found`. Lire
le message d'erreur **exact** évite une heure d'enquête.
:::

---

**Q14.7** — *Interprétation d'un dump `env` issu de cron.*

**Réponses : a) et b)**

::: pourquoi
Ce dump est la première chose à produire devant un « ça marche à la main ».
Deux conclusions en sortent immédiatement.

**a) `PATH=/usr/bin:/bin`** : `ss` est installé en `/usr/sbin/ss` sur Ubuntu.
Il est introuvable. Même chose pour `ip`, `iptables`, `service`, `useradd`,
`tcpdump` : tous les outils d'administration vivent dans les `sbin`, absents du
`PATH` de cron. C'est pour ça que les jobs cron de root échouent aussi, alors
qu'un shell root a bien les `sbin` dans son `PATH`.

**b) `SHELL=/bin/sh`** : sur Ubuntu, `/bin/sh` est un lien vers `dash`. Si la
commande de la crontab contient `[[ ]]`, `source`, `function`, `local` hors
fonction, des tableaux, `$'...'` ou `{1..5}`, elle échoue avec
`[[: not found` ou `Bad substitution`. Attention à la portée : `SHELL` ne
concerne que la **commande de la crontab**, pas le script appelé — un script
avec `#!/usr/bin/env bash` est bien exécuté par bash. Le piège n'existe que si
le test `[[ ]]` est écrit directement dans la ligne de crontab, ou si le script
a un shebang `#!/bin/sh`.

Correctif : `SHELL=/bin/bash` en tête de crontab, ou mieux, ne rien mettre de
complexe dans une crontab.
:::

::: piege
c) est fausse : cron fait un `chdir()` vers `$HOME` avant d'exécuter, pas vers
`/`. Le dump le confirme (`PWD=/home/mathieu`). C'est `run-parts` appelé depuis
`/etc/crontab` qui travaille dans `/` — d'où le `cd /` explicite dans la ligne
d'Ubuntu. Un script qui utilise des chemins relatifs se comporte donc
différemment selon qu'il est en crontab utilisateur ou en `cron.daily`.

d) est fausse : `LOGNAME` est bien positionné par cron, on le voit dans le dump.
:::

---

**Q14.8** — *Trois lignes sur stdout, aucun MTA installé.*

**Réponse : b)** rien n'est livré, et le journal enregistre la perte.

::: pourquoi
Le modèle de cron date d'une époque où la messagerie locale était le canal de
supervision. À chaque exécution, cron capture stdout **et** stderr de la
commande. Si la sortie est vide, il ne se passe rien. Si elle ne l'est pas, cron
construit un mail à destination de `$MAILTO`, ou à défaut du propriétaire de la
crontab, et le remet au binaire pointé par `sendmail`.

Sur un serveur moderne, aucun MTA n'est installé. Le démon Debian journalise
alors :

```console
$ journalctl -t CRON --since today | tail -2
cron[1204]: (mathieu) CMD (/opt/factura/bin/factura-rapport.sh)
cron[1204]: (CRON) info (No MTA installed, discarding output)
```

La deuxième ligne est précieuse : elle prouve que **la commande a produit de la
sortie**, donc probablement une erreur, même si son contenu est définitivement
perdu. Beaucoup d'administrateurs la voient sans la comprendre.

Trois façons de sortir de ce modèle :

```cron
MAILTO=""                                         # je ne veux pas de mail
30 2 * * * /opt/factura/bin/sauv.sh >> /var/log/factura/sauv.log 2>&1
30 2 * * * /opt/factura/bin/sauv.sh 2>&1 | logger -t factura-sauv
```
:::

::: piege
`MAILTO=""` ne supprime pas la production de la sortie, il supprime son envoi.
La sortie est toujours lue et jetée. Si ton job écrit 200 Mo sur stdout, cron les
lira quand même. Et surtout : `MAILTO=""` **sans redirection** transforme chaque
échec en échec silencieux. C'est précisément le scénario de L14.5.

Les variables de crontab n'obéissent pas au shell : `MAILTO=""` et
`MAILTO=` sont équivalents, mais `MAILTO="$ADMIN"` ne fait aucune substitution,
la valeur est prise littéralement.
:::

---

**Q14.9** — *`flock -n /var/lock/collecte.lock cmd` alors qu'une instance tourne.*

**Réponse : b)** `flock` sort immédiatement en code 1 sans lancer la commande.

::: pourquoi
`flock` fait trois choses, dans cet ordre :

1. il **ouvre** (en créant au besoin) le fichier passé en argument ;
2. il appelle `flock(2)` sur le descripteur obtenu, en mode exclusif ;
3. si le verrou est acquis, il `exec()` la commande, qui **hérite du descripteur
   ouvert et donc du verrou**.

L'option `-n` (`--nonblock`) change le comportement de l'étape 2 : au lieu
d'attendre, `flock(2)` échoue immédiatement avec `EWOULDBLOCK`, et l'outil sort
en **1** (ou en la valeur donnée à `-E`) sans rien exécuter.

Le verrou est **associé à la description de fichier ouverte**, pas au processus,
pas au contenu du fichier. Il est donc libéré automatiquement quand le dernier
descripteur qui le porte est fermé, c'est-à-dire à la mort du processus — quelle
qu'en soit la cause, `kill -9`, panne de courant ou `OOM killer` compris. C'est
la propriété qui rend `flock` supérieur à tout fichier de PID écrit à la main.

Les trois formes à connaître :

```bash
flock -n /var/lock/x.lock cmd        # refuse si déjà pris
flock    /var/lock/x.lock cmd        # attend indéfiniment
flock -w 5 /var/lock/x.lock cmd      # attend 5 s puis abandonne
```
:::

::: piege
d) est fausse : `flock` crée le fichier s'il n'existe pas. Mais il faut que le
**répertoire** existe et soit accessible en écriture par l'utilisateur du job —
piège classique quand le job tourne sous un compte de service et que le verrou
est en `/var/lock` (mode `0755`, propriété root). Utilise `/run/lock/` avec un
sous-répertoire créé par `RuntimeDirectory=` ou `tmpfiles.d`, ou un chemin sous
`/var/lib/<app>/`.

Piège numéro deux : le verrou est **consultatif**. Il ne bloque que les
processus qui demandent eux-mêmes le verrou. Un administrateur qui lance le
script à la main sans `flock` passera à travers. La discipline doit être dans le
script, pas dans la crontab, si on veut qu'elle s'applique à tout le monde.

Piège numéro trois : `flock` ne fonctionne pas sur NFS ancien ni sur certains
montages réseau. Pour un verrou partagé entre machines, il faut un service dédié
(Consul, etcd, une table SQL avec contrainte d'unicité).
:::

---

**Q14.10** — *Machine éteinte à 06:25, `anacron` installé.*

**Réponse : c)** la ligne de `/etc/crontab` ne fait rien, c'est `anacron` qui
lance les scripts peu après le démarrage.

::: pourquoi
Il faut lire la ligne d'Ubuntu en entier :

```cron
25 6 * * * root test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.daily )
```

Le `||` est un court-circuit : si `test -x /usr/sbin/anacron` **réussit** (donc
si anacron est installé), la partie droite n'est jamais évaluée. La ligne est
donc un aiguillage : « lance les scripts quotidiens **sauf si** anacron s'en
charge ». Cela répond aussi à d) : il n'y a jamais double exécution, c'est
précisément ce que cette construction empêche.

Ce que fait anacron ensuite, à partir de `/etc/anacrontab` :

```text
# période (jours)  délai (min)  identifiant   commande
1                  5            cron.daily    run-parts --report /etc/cron.daily
7                  10           cron.weekly   run-parts --report /etc/cron.weekly
@monthly           15           cron.monthly  run-parts --report /etc/cron.monthly
```

Pour chaque entrée, anacron compare la date du jour au contenu de
`/var/spool/anacron/cron.daily` (un fichier qui contient une date au format
`AAAAMMJJ`). Si l'écart est supérieur ou égal à la période, il attend le délai
indiqué — pour ne pas saturer une machine qui vient de démarrer — puis exécute,
puis réécrit l'horodatage.

Réponse à b) : cron **ne rattrape rien**, jamais. Il ne conserve aucun état entre
deux exécutions. C'est toute la raison d'être d'anacron.
:::

::: piege
Conséquence pratique trop souvent ignorée : sur un serveur allumé en permanence,
`cron.daily` ne tourne **pas** à 06:25 mais à l'heure décidée par anacron, qui
est déclenché soit au démarrage, soit par `anacron.timer`. Le décalage désoriente
quand on cherche la trace d'une rotation de logs. La commande qui tranche :
`systemctl list-timers anacron.timer` et `cat /var/spool/anacron/cron.daily`.

anacron a une granularité en **jours**. Il ne sait rien faire de plus fin, et il
ignore complètement `cron.hourly` — d'où le fait que `cron.hourly` est le seul
répertoire encore lancé directement par cron sur une machine avec anacron.
:::

---

**Q14.11** — *Sortie de `systemd-analyze calendar` montrant le 28 puis le 30 mars.*

**Réponse : b)** l'exécution du dimanche 29 mars est sautée : 02:30 n'existe pas.

::: pourquoi
En 2026, le passage à l'heure d'été en zone `Europe/Paris` a lieu le dimanche
29 mars : à 02:00 CET, les horloges avancent d'un coup à 03:00 CEST. **Les minutes
de 02:00:00 à 02:59:59 n'existent pas ce jour-là.**

`OnCalendar=*-*-* 02:30:00` demande une date locale précise. Le 29 mars, cette
date locale ne correspond à aucun instant réel : systemd ne peut donc pas la
programmer, et passe à l'occurrence suivante. Le saut est visible dans la sortie
de `systemd-analyze calendar`, et c'est précisément pour ça qu'on l'exécute avant
de mettre un timer en production :

```console
$ systemd-analyze calendar --iterations=3 --base-time="2026-03-27 12:00:00" \
    "*-*-* 02:30:00"
Normalized form: *-*-* 02:30:00
    Next elapse: Sat 2026-03-28 02:30:00 CET
   Iteration #2: Mon 2026-03-30 02:30:00 CEST
   Iteration #3: Tue 2026-03-31 02:30:00 CEST
```

L'option `--base-time` permet de se placer n'importe quand : c'est l'outil pour
vérifier un comportement au changement d'heure sans attendre mars.

Ce comportement diffère de celui de cron, qui **rattrape** au contraire les jobs
à heure fixe sautés par un bond en avant (voir QO14.6).
:::

::: piege
d) mérite une correction : systemd n'a pas « basculé en UTC ». La ligne
`(in UTC)` est un simple affichage de confort. Un `OnCalendar` sans suffixe est
interprété dans le **fuseau local de la machine**, tel que `timedatectl` le
rapporte. Pour figer le comportement, on ajoute explicitement le fuseau :

```ini
OnCalendar=*-*-* 02:30:00 UTC
```

Cette forme est acceptée depuis systemd 252 ; Ubuntu 24.04 embarque systemd 255,
elle est donc disponible.
:::

---

**Q14.12** — *Machine éteinte de 02 h à 08 h, timer à 04:00.*

**Réponse : b)** `Persistent=true`.

::: pourquoi
Sans `Persistent=`, un timer `OnCalendar` ne connaît que l'avenir : au démarrage,
systemd calcule la prochaine occurrence de l'expression et s'endort jusque-là.
L'échéance de 04:00 est simplement passée.

`Persistent=true` ajoute un état sur disque. systemd écrit, à chaque
déclenchement, un fichier vide dont la **date de modification** porte
l'information :

```console
$ ls -l --time-style=full-iso /var/lib/systemd/timers/
-rw-r--r-- 1 root root 0 2026-09-18 04:00:03 stamp-factura-rapport.timer
```

Au démarrage du timer, systemd compare cet horodatage à la dernière occurrence
théorique de l'expression. Si une occurrence est tombée entre les deux, il
déclenche l'unité **immédiatement**, puis reprend le rythme normal.

C'est l'équivalent systemd d'anacron, avec deux avantages : la granularité n'est
pas limitée au jour, et le mécanisme s'applique à n'importe quel timer plutôt
qu'aux seuls répertoires `cron.*`.
:::

::: piege
a) `OnBootSec=5min` déclencherait la tâche à **chaque** démarrage, y compris
quand aucune échéance n'a été ratée : un serveur redémarré trois fois dans la
journée produirait trois rapports. Les deux directives se combinent d'ailleurs
très bien, mais elles ne répondent pas à la même question.

c) `RemainAfterElapse=` (défaut `yes`) décide si le timer reste chargé après son
dernier déclenchement ; il ne rattrape rien. d) `AccuracySec=1h` élargit la
fenêtre de tir, ce qui ne sert à rien quand la machine est éteinte.

Piège pratique : `Persistent=true` n'a d'effet qu'avec `OnCalendar=`. Avec les
déclencheurs monotones (`OnBootSec`, `OnUnitActiveSec`), la directive est
silencieusement ignorée.
:::

---

**Q14.13** — *`systemctl enable --now factura-sauv.service` au lieu du timer.*

**Réponse : b)** le service démarre tout de suite et à chaque démarrage, sans
aucune planification.

::: pourquoi
`enable` ne fait qu'une chose : créer les liens symboliques décrits par la
section `[Install]` de l'unité. Ici, `WantedBy=multi-user.target` produit

```text
/etc/systemd/system/multi-user.target.wants/factura-sauv.service
  -> /etc/systemd/system/factura-sauv.service
```

ce qui signifie « démarre ce service quand on atteint `multi-user.target` »,
c'est-à-dire à chaque démarrage de la machine. Le `--now` ajoute un `start`
immédiat. À aucun moment le fichier `.timer` n'est consulté : systemd n'établit
**aucun lien automatique** entre `x.service` et `x.timer` au moment de `enable`.
Le lien ne joue que dans l'autre sens, à l'exécution : un timer déclenche par
défaut l'unité de même nom suffixée `.service`.

La bonne séquence est donc :

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now factura-sauv.timer
systemctl list-timers factura-sauv.timer
```

On active le **timer**, on surveille le **timer**, et on lit le journal du
**service**.
:::

::: piege
La conséquence est pire qu'une simple absence de planification : la sauvegarde
tourne maintenant à chaque redémarrage, à un moment imprévisible, potentiellement
pendant une intervention. Et comme le timer n'est pas activé, elle ne tourne
jamais la nuit. Le symptôme rapporté est « la sauvegarde tourne quand elle veut ».

Règle à appliquer partout : **un service déclenché par timer n'a pas de section
`[Install]`**. Sans elle, `systemctl enable factura-sauv.service` échoue avec
`The unit files have no installation config`, ce qui transforme l'erreur en
message clair au lieu d'un comportement silencieux. C'est une protection gratuite.
:::

---

**Q14.14** — *300 machines, même `OnCalendar=*-*-* 03:00:00`, dépôt saturé.*

**Réponse : b)** `RandomizedDelaySec=30min`.

::: pourquoi
`RandomizedDelaySec=` ajoute à chaque déclenchement un délai **tiré au hasard**
entre 0 et la valeur donnée. Sur 300 machines, les exécutions s'étalent
uniformément sur la fenêtre : la charge instantanée est divisée par un facteur
proche du nombre de minutes de la fenêtre.

C'est exactement ce que fait Debian pour `apt-daily.timer` :

```ini
[Timer]
OnCalendar=*-*-* 6,18:00
RandomizedDelaySec=12h
Persistent=true
```

Le tirage est refait à chaque échéance. Si l'on veut au contraire un décalage
**stable pour une machine donnée** — utile pour corréler des journaux ou étaler
sans réordonner — on ajoute `FixedRandomDelay=true` : le délai est alors dérivé
de l'identifiant machine (`/etc/machine-id`) et reste identique d'un jour à
l'autre.

Avantage décisif sur la solution manuelle (mettre une heure différente dans
chaque fichier) : les 300 unités restent **strictement identiques**, donc
gérables par un gestionnaire de configuration sans logique par hôte.
:::

::: piege
a) `AccuracySec=1h` est souvent confondu avec la réponse. Ce n'est pas un
décalage : c'est une **fenêtre de regroupement**. systemd s'autorise à déclencher
n'importe quand dans l'intervalle pour aligner l'exécution sur d'autres réveils
et économiser l'énergie — ce qui est un objectif de portable, pas de serveur. Sur
300 machines indépendantes, rien ne garantit l'étalement : plusieurs peuvent tirer
le même instant. Sa valeur par défaut est `1min`, et `AccuracySec=1us` est la
façon d'obtenir un déclenchement à la seconde près.

c) `OnUnitActiveSec=1d` remplacerait l'horaire fixe par une cadence glissante :
l'heure d'exécution dériverait chaque jour. d) `Persistent=true` ne concerne que
le rattrapage.
:::

---

**Q14.15** — *Timer toutes les 5 minutes, collecte qui dure 12 minutes.*

**Réponse : b)** systemd ne démarre pas de seconde instance ; les échéances
intermédiaires ne produisent rien.

::: pourquoi
C'est la différence la plus utile entre un timer et une ligne de cron, et elle
tient à la nature même de systemd : une **unité** est un objet unique, avec un
seul état. `factura-collecte.service` ne peut pas être « actif deux fois ».

Quand le timer arrive à échéance, il soumet un job `start` sur l'unité. Le
gestionnaire de jobs examine l'état :

* si un job `start` est déjà en cours d'exécution pour cette unité, le nouveau y
  est **fusionné** — il n'y a jamais deux démarrages concurrents ;
* si l'unité est déjà `active`, la demande est satisfaite immédiatement sans
  rien relancer.

Résultat : avec une collecte de 12 minutes et un timer à 5 minutes, il n'y a
jamais qu'une collecte à la fois. Les échéances tombées pendant l'exécution sont
absorbées.

Cron, lui, n'a aucune notion d'unité : il `fork()` sans se demander si la
précédente est finie. Trois collectes tournent en parallèle, et c'est BF14.3.
:::

::: piege
Deux réserves à connaître.

Première réserve : ce n'est pas une file d'attente. Les trois échéances absorbées
ne produisent **pas** trois exécutions différées ; elles disparaissent. Si ton
traitement doit impérativement s'exécuter autant de fois qu'il y a d'échéances,
le modèle est faux — il faut une file de messages.

Seconde réserve : la garantie ne vaut que pour **une même unité sur une même
machine**. Des unités instanciées (`collecte@1.service`, `collecte@2.service`)
sont des unités distinctes et tournent en parallèle. Et rien ne protège de deux
machines qui écrivent dans le même fichier partagé : là, il faut un verrou
réseau.

Enfin, pour éviter qu'une collecte bloquée n'empêche toutes les suivantes
indéfiniment, on ajoute `RuntimeMaxSec=` au service : systemd la tue au-delà du
délai et le cycle repart.
:::

---

**Q14.16** — *`30 2 * * *` en `Europe/Paris`, le 25 octobre 2026.*

**Réponse : a)** rien de particulier, une seule exécution.

::: pourquoi
Le 25 octobre 2026, à 03:00 CEST, les horloges reculent à 02:00 CET : l'intervalle
02:00–02:59 est vécu **deux fois**. Sans précaution, un job à 02:30 s'exécuterait
donc deux fois.

Le cron de Debian et d'Ubuntu traite explicitement le cas. La page `crontab(5)`
le documente :

> Les changements d'heure locale de moins de trois heures, comme ceux causés par
> l'heure d'été, sont traités de façon particulière. Cela ne concerne que les
> tâches qui s'exécutent à une heure précise et celles dont la granularité est
> supérieure à une heure. Les tâches plus fréquentes sont planifiées normalement.
> Si l'heure a avancé, les tâches qui auraient dû s'exécuter dans l'intervalle
> sauté sont exécutées immédiatement. Si l'heure a reculé, on prend soin de ne
> pas exécuter les tâches deux fois.

`30 2 * * *` est une tâche à heure précise : elle bénéficie de la protection.
**Une seule exécution.**

Le comportement symétrique est le plus surprenant : au passage à l'heure d'été
(29 mars 2026), la même ligne **est exécutée** — immédiatement après le bond, donc
vers 03:00 — alors qu'un timer systemd `OnCalendar=*-*-* 02:30:00` **saute** la
journée (Q14.11). Deux ordonnanceurs, deux philosophies : cron garantit
l'exécution, systemd garantit l'horaire.
:::

::: piege
La protection ne s'applique **pas** aux tâches de granularité inférieure à
l'heure. `*/10 * * * *` suit bêtement l'horloge murale : le 25 octobre elle
tourne 6 fois de plus, le 29 mars 6 fois de moins. Pour un job de facturation à
la minute, c'est un écart de comptage réel.

Elle ne s'applique pas non plus si le décalage dépasse trois heures — cas d'un
serveur dont on corrige le fuseau après coup, ou d'une VM dont l'horloge a dérivé
puis a été resynchronisée d'un coup.

La seule configuration qui supprime définitivement le problème :
**`sudo timedatectl set-timezone UTC` sur tous les serveurs**. UTC n'a pas d'heure
d'été. On convertit en heure locale au moment de l'affichage, pas au moment de
l'ordonnancement.
:::

---

**Q14.17** — *Savoir si le service déclenché cette nuit a réussi.*

**Réponses : a) et b)**

::: pourquoi
Toute la valeur des timers est là : la sortie du script n'est pas un mail
hypothétique, c'est un flux journalisé attaché à une unité.

`systemctl status factura-sauv.service` donne l'état consolidé : résultat de la
dernière exécution, code de sortie du processus principal, durée, et les dix
dernières lignes de journal.

```console
$ systemctl status factura-sauv.service
● factura-sauv.service - Factura — sauvegarde nocturne
     Loaded: loaded (/etc/systemd/system/factura-sauv.service; static)
     Active: inactive (dead) since Fri 2026-09-18 02:34:19 CEST; 17h ago
TriggeredBy: ● factura-sauv.timer
    Process: 3182 ExecStart=/opt/factura/bin/factura-sauvegarde-nuit.sh
             (code=exited, status=0/SUCCESS)
   Main PID: 3182 (code=exited, status=0/SUCCESS)
```

Trois choses à savoir lire : `TriggeredBy:` confirme que le timer est bien
branché, `status=0/SUCCESS` donne le code retour réel du script, et
`inactive (dead)` est l'état **normal** d'un `oneshot` terminé, pas une anomalie.

`journalctl -u factura-sauv.service --since yesterday` donne l'historique complet
avec toutes les lignes produites par le script — sans avoir eu besoin de
rediriger quoi que ce soit dans la crontab. Pour un traitement en boucle :
`journalctl -u factura-sauv.service -f`.

En script de supervision, la forme exploitable est :

```bash
systemctl show factura-sauv.service -p Result --value        # success / exit-code
systemctl show factura-sauv.service -p ExecMainStatus --value
systemctl show factura-sauv.timer -p LastTriggerUSec --value
```
:::

::: piege
c) est fausse et c'est le réflexe à corriger : le `.timer` ne sait rien de
l'exécution, il ne connaît que les dates de déclenchement. Son journal contient
« Started … » et rien d'autre. Toute la matière est côté `.service`.

d) est fausse aussi : `systemctl list-timers` affiche `LAST` et `PASSED`,
c'est-à-dire **quand** le timer s'est déclenché pour la dernière fois, jamais le
résultat de l'exécution. Un timer qui déclenche fidèlement un service qui échoue
tous les jours affiche exactement la même chose qu'un timer dont tout va bien.
Surveiller les timers ne remplace pas surveiller les services.
:::

---

**Q14.18** — *Relancer un import une seule fois dans 40 minutes, sans crontab.*

**Réponses : a) et b)**

::: pourquoi
`at` est fait pour ça, et fait une chose que beaucoup ignorent : il **mémorise
l'environnement complet** de la session qui l'a appelé et le restaure au moment
de l'exécution. C'est l'exact inverse de cron.

```console
$ echo /opt/factura/bin/import.sh | at now + 40 minutes
warning: commands will be executed using /bin/sh
job 7 at Fri Sep 18 20:22:00 2026
$ atq
7       Fri Sep 18 20:22:00 2026 a mathieu
$ at -c 7 | tail -3        # le job tel qu'il sera exécuté
```

`atrm 7` annule. Le démon `atd` doit tourner (`systemctl enable --now atd`), et
l'utilisateur doit être autorisé par `/etc/at.allow` / `/etc/at.deny`.

`systemd-run --on-active=40min` fait la même chose sous forme d'**unité
transitoire** : systemd crée à la volée une paire timer + service, non
persistante (elle disparaît au redémarrage).

```console
$ sudo systemd-run --on-active=40min --unit=import-ponctuel \
    /opt/factura/bin/import.sh
Running timer as unit: import-ponctuel.timer
Will run service as unit: import-ponctuel.service
```

On la surveille avec `systemctl list-timers`, on la lit avec
`journalctl -u import-ponctuel`, on l'annule avec
`systemctl stop import-ponctuel.timer`. Elle hérite au passage de tout systemd :
`--property=MemoryMax=1G`, `--property=User=factura`, `-p OnFailure=…`.
:::

::: piege
c) est un piège récurrent : `sleep 2400 && cmd &` est rattaché à ta session SSH.
Si la connexion tombe — ou simplement si tu te déconnectes — bash relaie `SIGHUP`
à ses jobs et le `sleep` meurt. Il faudrait `nohup`, `setsid` ou `tmux`, et
surtout on perd toute trace de ce qui a été planifié : personne ne peut savoir
qu'un import est prévu. Ce n'est pas exploitable en équipe.

d) est fausse pour deux raisons : `@reboot` ne se déclenche qu'au démarrage, pas
dans 40 minutes, et l'énoncé interdit de toucher aux crontabs.

Différence de fond entre `at` et `systemd-run` : `at` restaure l'environnement de
l'appelant (utile pour un one-shot interactif, dangereux pour de la production),
`systemd-run` part d'un environnement propre et contrôlé.
:::

---

## 14.4 Quiz — questions ouvertes

**QO14.1** — *Le OU entre jour du mois et jour de semaine.*

**Réponse attendue.**

La règle, en trois cas :

| jour du mois | jour de semaine | résultat |
|---|---|---|
| `*` | restreint | ET trivial : le jour de semaine décide |
| restreint | `*` | ET trivial : le jour du mois décide |
| restreint | restreint | **OU** : l'un **ou** l'autre suffit |

Les deux expressions demandées :

```cron
# le 1er du mois, seulement si c'est un vendredi
0 3 1 * *  [ "$(date +\%u)" -eq 5 ] && /opt/factura/bin/cloture.sh
# le premier vendredi du mois
0 3 1-7 * 5  /opt/factura/bin/cloture.sh    # FAUX : c'est un OU
0 3 1-7 * *  [ "$(date +\%u)" -eq 5 ] && /opt/factura/bin/cloture.sh   # correct
```

::: pourquoi
Le mécanisme est dans la fonction de correspondance de cron. Le démon construit
cinq masques de bits à partir de la ligne, un par champ, et note séparément si
les champs 3 et 5 sont « étoilés ». Chaque minute, il teste :

```text
minute ET heure ET mois ET (
    ( jour_du_mois_étoilé OU jour_de_semaine_étoilé )
        ? ( jour_du_mois ET jour_de_semaine )
        : ( jour_du_mois OU jour_de_semaine )
)
```

Le basculement ET/OU dépend donc uniquement de la **présence d'une étoile**, pas
des valeurs. Écrire `1-31` au lieu de `*` change le comportement : `1-31` est
« restreint » au sens de cron, donc réactive le OU, alors que l'ensemble couvert
est identique. C'est une source de bugs authentique.

L'astuce `1-7 * *` + test sur `date +\%u` fonctionne parce que le premier vendredi
du mois tombe forcément entre le 1er et le 7. Même logique pour le dernier
vendredi : `0 3 24-31 * *` avec le même test.
:::

::: piege
Deux erreurs d'écriture reviennent tout le temps. D'abord `%u` non échappé, qui
tronque la commande (Q14.3). Ensuite l'oubli que `&&` dans une crontab est
interprété par `/bin/sh` : si la condition est fausse, le code retour de la
ligne est non nul, et cron considère que la tâche a échoué — ce qui génère un
mail si `MAILTO` est positionné. Terminer la ligne par `|| true` évite le bruit.

En timer systemd, tout ceci disparaît : `OnCalendar=Fri *-*-01..07 03:00:00`
exprime directement « le premier vendredi du mois », avec un vrai ET, vérifiable
en une commande :

```console
$ systemd-analyze calendar --iterations=3 "Fri *-*-01..07 03:00:00"
```
:::

---

**QO14.2** — *Démarche face à « ça marche à la main, pas en cron ».*

**Réponse attendue — cinq étapes.**

1. **Confirmer que la tâche est déclenchée.** `journalctl -t CRON --since today
   | grep <script>`. Si la ligne `CMD (...)` n'apparaît pas, le problème est dans
   la planification (syntaxe, champ utilisateur, fichier non relu), pas dans le
   script. On s'arrête là.
2. **Récupérer le message d'erreur.** Il est très probablement perdu : c'est le
   vrai problème. On le capture en ajoutant `>> /tmp/diag.log 2>&1` à la ligne,
   ou `2>&1 | logger -t diag`.
3. **Capturer l'environnement réel**, une bonne fois :
   ```cron
   * * * * * env > /tmp/cronenv.txt 2>&1
   ```
4. **Reproduire immédiatement**, sans attendre la prochaine minute :
   ```bash
   env -i $(grep -E '^[A-Z_]+=' /tmp/cronenv.txt | xargs) \
     /bin/sh -c '/opt/factura/bin/mon-script.sh'
   ```
5. **Corriger au bon endroit** : chemins absolus ou `PATH=` dans le script
   (pas dans la crontab), et vérifier les hypothèses implicites du script
   (répertoire courant, `umask`, variables applicatives, terminal).

::: pourquoi
L'ordre n'est pas décoratif. Il sépare trois causes qui donnent le même symptôme
mais se corrigent à trois endroits différents : la tâche n'est pas déclenchée, la
tâche est déclenchée mais échoue, la tâche réussit mais ne fait pas ce qu'on
croit.

L'étape 4 est celle qui distingue un administrateur méthodique : `env -i` vide
l'environnement avant d'exécuter, et on le reconstruit à l'identique. En une
seconde, on a exactement le comportement de cron, avec le message d'erreur sous
les yeux, et on peut itérer. Sans elle, chaque hypothèse coûte une minute
d'attente, et on finit par modifier trois choses à la fois.

Les cinq différences qui expliquent 95 % des cas :

| Ce qui manque en cron | Symptôme typique |
|---|---|
| `PATH` réduit à `/usr/bin:/bin` | `command not found` |
| `/bin/sh` = `dash`, pas bash | `[[: not found`, `Bad substitution` |
| aucun `~/.bashrc` lu | variables applicatives vides |
| pas de terminal | `tput: No value for $TERM`, `stty` échoue |
| répertoire courant = `$HOME` | chemins relatifs pointant ailleurs |
:::

::: piege
Le réflexe à ne **pas** avoir : ajouter `. /etc/profile` ou `. ~/.bashrc` en tête
de la ligne de crontab. Ça semble marcher, et ça crée une dépendance invisible
entre un job de production et le fichier de configuration interactif d'un compte
humain. Le jour où quelqu'un ajoute un `echo` ou un `read` dans son `.bashrc`, le
job casse — et la garde `case $- in *i*) ;; *) return;; esac` en tête du `.bashrc`
d'Ubuntu fait de toute façon que rien n'est lu.

Le correctif propre est **dans le script** : il déclare son `PATH`, ses variables
et son répertoire de travail, et devient exécutable de façon identique depuis
cron, systemd, Ansible ou un shell.
:::

---

**QO14.3** — *Entretien : qu'apporte la migration vers systemd, et quand garder
cron ?*

**Réponse attendue — quatre critères, puis le cas de cron.**

**1. Dépendances et ordonnancement.** Cron ne connaît que l'heure. Un timer
déclenche une unité qui peut exiger `After=network-online.target`,
`Requires=postgresql.service`, `After=srv-sauvegardes.mount`. Le job ne démarre
pas dans un système à moitié prêt.

**2. Journalisation.** Cron capture la sortie et tente un mail. Un service écrit
dans le journal, avec unité, horodatage, PID, priorité : `journalctl -u x` donne
l'historique, `systemctl status x` donne le dernier code retour.

**3. Contrôle des ressources.** Chaque service a son cgroup :
`CPUQuota=50%`, `MemoryMax=512M`, `IOWeight=`, `Nice=`, plus le durcissement
(`PrivateTmp=`, `ProtectSystem=strict`, `User=`). Un `mysqldump` qui dérape ne
met plus la production à genoux. Et `RuntimeMaxSec=30min` tue une tâche bloquée.

**4. Gestion d'échec.** `OnFailure=alerte@%n.service` déclenche une action
**automatique** en cas d'échec, sans écrire de `if` ni de `||` dans le script.
Avec `Restart=on-failure` et `RestartSec=`, on obtient même du réessai.

**Quand garder cron** : pour une tâche simple, sans dépendance, sur une machine
où d'autres personnes doivent pouvoir lire la planification en trois secondes ;
pour une crontab **utilisateur** que l'intéressé gère lui-même sans `sudo` ;
sur un système sans systemd (conteneur, BSD, équipement embarqué) ; et pour ne
pas réécrire trente lignes qui fonctionnent depuis six ans sans incident.

::: pourquoi
Ce qu'on évalue dans cette question, ce n'est pas la connaissance de systemd,
c'est la capacité à **justifier une migration par des besoins** plutôt que par la
mode. Le piège classique est de répondre « c'est plus moderne » ou « cron c'est
dépassé » : les deux sont des réponses éliminatoires.

La réponse forte cite un incident que chaque critère aurait évité :

* dépendances — la sauvegarde de 02:30 qui a archivé un point de montage NFS vide
  parce qu'elle a démarré avant le montage ;
* journalisation — l'échec silencieux découvert onze jours plus tard ;
* ressources — le `tar` de 04:00 qui a saturé les E/S et fait tomber la latence
  de l'API ;
* échec — l'expiration de certificat un samedi.

Mentionner le coût est aussi un signe de maturité : deux fichiers au lieu d'une
ligne, une syntaxe à apprendre, un `daemon-reload` à ne pas oublier, et une
équipe à former.
:::

::: piege
Deux affirmations fausses à éviter absolument en entretien.

« Les timers remplacent cron, cron va disparaître » : faux, cron est empaqueté et
maintenu partout, y compris sur les distributions les plus systemd-centrées.

« Les timers sont plus précis » : c'est l'inverse par défaut. `AccuracySec=` vaut
**1 minute** pour un timer, alors que cron déclenche à la seconde près au début
de la minute. Il faut `AccuracySec=1s` pour obtenir une précision comparable. Le
savoir, et le dire, marque la différence entre avoir lu la documentation et avoir
exploité des timers.
:::

---

**QO14.4** — *`Persistent=true` contre `anacron`.*

**Réponse attendue.**

| | anacron | `Persistent=true` |
|---|---|---|
| état | `/var/spool/anacron/<id>` | `/var/lib/systemd/timers/stamp-<unit>.timer` |
| forme | une date `AAAAMMJJ` dans le fichier | la **mtime** du fichier, vide |
| granularité | le **jour**, minimum 1 | l'expression `OnCalendar`, jusqu'à la seconde |
| décision | au lancement d'anacron (boot + timer) | au démarrage de l'unité timer |

Ce que l'un fait et pas l'autre : anacron applique un **délai** paramétrable
(colonne 2 de `/etc/anacrontab`) pour ne pas écrouler une machine qui vient de
démarrer, et sait qu'une tâche « mensuelle » doit tourner une fois par mois même
si la machine n'a été allumée que trois jours. `Persistent=` sait rattraper une
échéance **infra-journalière** (un job horaire raté à cause d'un redémarrage de
20 minutes), ce dont anacron est totalement incapable.

::: pourquoi
Le mécanisme de `Persistent=` mérite d'être décrit précisément parce qu'il
surprend. systemd ne stocke pas « la liste des échéances ratées » : il stocke un
seul horodatage, celui du dernier déclenchement, dans la **date de modification**
d'un fichier vide.

```console
$ ls -l --time-style=full-iso /var/lib/systemd/timers/
-rw-r--r-- 1 root root 0 2026-09-17 02:30:07 stamp-factura-sauv.timer
```

Au démarrage du timer (boot, `daemon-reload`, `systemctl start x.timer`), systemd
calcule la dernière occurrence théorique de l'expression. Si elle est postérieure
à l'horodatage, il déclenche **une fois**, tout de suite, puis réécrit le fichier.
Trois jours d'arrêt ne produisent donc pas trois exécutions, mais une seule.
C'est exactement le comportement d'anacron, et c'est presque toujours ce qu'on
veut pour une sauvegarde ou une rotation.

Conséquence pratique très utile en test : falsifier la date du fichier
(`touch -d '-2 days'`) permet de simuler une échéance ratée sans éteindre la
machine (E14.14).
:::

::: piege
Piège d'exploitation : supprimer `/var/lib/systemd/timers/stamp-*.timer` fait
croire à systemd que le timer n'a jamais tourné. Au prochain
`systemctl start x.timer`, il déclenche immédiatement. Des scripts de « nettoyage »
un peu zélés ont déjà lancé des sauvegardes complètes en pleine journée comme ça.

Piège de conception : `Persistent=` est ignoré sans `OnCalendar=`. Et sur une
machine qui redémarre souvent, `Persistent=true` combiné à un `OnCalendar`
fréquent produit une exécution à chaque démarrage — ce qui est correct, mais
inattendu si on n'y a pas pensé.

Enfin, ne pas confondre avec `RemainAfterElapse=` : celui-là décide seulement si
l'unité timer reste chargée après sa dernière échéance, il ne rattrape rien.
:::

---

**QO14.5** — *Mécanisme de `flock`.*

**Réponse attendue.**

Le verrou porte sur la **description de fichier ouverte** (l'objet noyau créé par
`open()`), pas sur le nom du fichier ni sur son contenu. `flock` ouvre le fichier,
pose `LOCK_EX` dessus, puis `exec()` la commande, qui hérite du descripteur — et
donc du verrou — pour toute sa durée de vie.

Il est **consultatif** : le noyau ne l'impose à personne. Il ne bloque que les
processus qui appellent eux-mêmes `flock(2)` sur le même fichier. N'importe quel
autre processus peut lire et écrire le fichier verrouillé sans rien remarquer.

C'est le noyau qui libère, à la fermeture du dernier descripteur portant le
verrou. Un `kill -9`, un OOM killer, une panne de courant : le processus meurt,
ses descripteurs sont fermés par le noyau, le verrou tombe. **Il n'y a rien à
nettoyer.**

::: pourquoi
La comparaison avec le fichier de PID écrit à la main est le cœur de la question.
Un `if [ -f /var/run/x.pid ]; then exit; fi` cumule trois défauts structurels :

1. **Il n'est pas atomique.** Entre le test et la création du fichier, il y a une
   fenêtre pendant laquelle un second processus fait le même test et le réussit
   aussi. Les deux démarrent. La fenêtre est petite, donc le bug est rare, donc
   il tombe en production à 3 h du matin.
2. **Il ne survit pas à une mort brutale.** Le script tué par `kill -9` laisse son
   fichier de PID. Toutes les exécutions suivantes refusent de démarrer — panne
   silencieuse jusqu'à ce que quelqu'un remarque l'absence de sauvegardes.
3. **Le PID est réutilisable.** Vérifier que le PID stocké tourne encore
   (`kill -0`) ne suffit pas : les PID bouclent, et un autre processus peut
   parfaitement occuper le numéro.

`flock` n'a aucun de ces défauts parce que l'atomicité et le nettoyage sont pris
en charge par le noyau. C'est exactement le genre de problème qu'on ne
réimplémente pas.

Les deux formes à maîtriser :

```bash
# 1. depuis la crontab : flock enveloppe la commande
*/5 * * * * flock -n /run/lock/collecte.lock /opt/factura/bin/collecte.sh
# 2. dans le script lui-même : il se protège tout seul
exec 9>/run/lock/collecte.lock
flock -n 9 || { echo "déjà en cours" >&2; exit 0; }
```

La forme 2 est supérieure en exploitation : la protection s'applique aussi quand
un humain lance le script à la main.
:::

::: piege
Le code de sortie de la forme 1 mérite réflexion. `flock -n` sort en 1 quand le
verrou est pris : cron considère donc que la tâche a **échoué** et envoie un mail
à chaque collision. Sur un job fréquent, la boîte de root explose. Deux parades :
`flock -n -E 0` (sortir en 0 si le verrou est pris) quand la collision est
normale, ou journaliser explicitement l'événement quand c'est une anomalie.

Autre piège : verrouiller le fichier de **données** au lieu d'un fichier de
verrou dédié. Si le script tronque le fichier de données, ou le remplace par un
`mv` atomique, l'inode change et le verrou ne porte plus sur le même objet. Le
fichier de verrou doit être un fichier séparé que personne ne recrée jamais.

Enfin, `flock` ne fonctionne pas de façon fiable sur NFSv3 ni sur certains
systèmes de fichiers réseau. Pour coordonner plusieurs machines, il faut un
verrou distribué réel.
:::

---

**QO14.6** — *Job à 02:30 et changement d'heure, cron et systemd.*

**Réponse attendue.**

| Événement | cron (Debian/Ubuntu) | timer systemd |
|---|---|---|
| Printemps, 02:30 n'existe pas | exécuté **immédiatement après** le bond | **sauté** |
| Automne, 02:30 existe deux fois | exécuté **une seule fois** | exécuté une seule fois |

Recommandation pour la production : **`timedatectl set-timezone UTC` sur tous les
serveurs**, et planification en UTC. UTC n'a pas d'heure d'été, donc aucune de ces
questions ne se pose. Pour un rapport qui doit être daté en heure locale, on
sépare les deux préoccupations : l'**ordonnancement** est en UTC, la **mise en
forme** convertit au moment de l'écriture (`TZ='Europe/Paris' date '+%F %T %Z'`
dans le script, ou `Environment=TZ=Europe/Paris` dans l'unité).

::: pourquoi
La divergence entre les deux ordonnanceurs traduit deux contrats différents.

Cron a un contrat de **fréquence** : « cette tâche tourne une fois par jour ».
Quand une occurrence est escamotée par un bond en avant de moins de trois heures,
il la rattrape pour tenir le contrat. C'est ce que veut une facturation
quotidienne : mieux vaut tourner à 03:05 que ne pas tourner.

systemd a un contrat d'**horaire** : « cette tâche tourne à 02:30 heure locale ».
Le 29 mars, aucun instant ne porte ce nom : il n'y a rien à déclencher.
`systemd-analyze calendar` le montre noir sur blanc, et on peut décider en
connaissance de cause (déplacer à 01:30, passer en UTC, ou ajouter
`Persistent=true`, qui rattrapera au démarrage suivant si la machine redémarre).

Vérification, sans attendre mars :

```console
$ systemd-analyze calendar --iterations=3 --base-time="2026-03-27 12:00" \
    "*-*-* 02:30:00"
    Next elapse: Sat 2026-03-28 02:30:00 CET
   Iteration #2: Mon 2026-03-30 02:30:00 CEST     # le 29 est absent
```

Et l'état du serveur :

```console
$ timedatectl
               Local time: Fri 2026-09-18 19:42:11 CEST
           Universal time: Fri 2026-09-18 17:42:11 UTC
                Time zone: Europe/Paris (CEST, +0200)
System clock synchronized: yes
```
:::

::: piege
La fenêtre 02:00–03:00 est la **pire** plage horaire pour planifier quoi que ce
soit, et c'est pourtant la plus utilisée. Déplacer les tâches critiques à 01:30
ou 04:00 supprime le problème sans changer de fuseau : ces heures existent une
fois et une seule dans l'année.

Autre piège : les tâches de granularité fine (`*/10 * * * *`) ne bénéficient
d'aucune protection côté cron et tournent 6 fois de plus en octobre, 6 fois de
moins en mars. Un compteur de facturation à la minute produit donc un écart réel,
deux fois par an, que personne ne relie jamais au changement d'heure.

Dernier point souvent oublié : changer le fuseau d'une machine en production
**ne redémarre pas cron**, mais systemd recalcule bien ses timers. Après un
`timedatectl set-timezone`, vérifie `systemctl list-timers` et redémarre
`cron.service` pour être certain que les deux sont d'accord.
:::

---

**QO14.7** — *La sauvegarde arrêtée depuis onze jours, sans alerte.*

**Réponse attendue.**

La supervision « alerter quand le job échoue » est **conditionnée à l'exécution du
job**. Elle ne peut structurellement rien détecter quand le job ne tourne plus :
il n'y a pas d'échec, il n'y a rien. Un timer désactivé, une crontab effacée, un
`atd` arrêté, une machine éteinte produisent tous le même signal, à savoir aucun.
C'est le point aveugle par construction.

Deux mécanismes qui le couvrent :

**1. Témoin de fraîcheur local** (sans outil externe). Le job touche un fichier
témoin **uniquement en cas de succès**. Une seconde tâche, indépendante, vérifie
périodiquement l'âge du témoin et échoue s'il dépasse un seuil. C'est L14.5.

```bash
age=$(( ($(date +%s) - $(stat -c %Y /var/lib/factura/derniere-sauvegarde)) / 3600 ))
[ "$age" -le 26 ] || { echo "sauvegarde vieille de ${age} h" >&2; exit 1; }
```

**2. Dead man's switch externe** (*healthcheck*). En fin de succès, le job émet un
**ping sortant** vers un service tiers. Le service alerte quand le ping **manque**
au-delà du délai configuré.

```bash
curl -fsS -m 10 --retry 3 "https://hc-ping.com/$UUID" >/dev/null
```

::: pourquoi
La différence essentielle entre les deux est **l'endroit où vit la décision
d'alerter**.

Avec le témoin local, le raisonnement reste sur la machine surveillée. Ça couvre
le timer désactivé, la crontab effacée, le script en erreur, le disque plein.
Ça ne couvre **pas** la machine éteinte, le noyau bloqué, le réseau coupé ni la
VM supprimée : le veilleur meurt avec ce qu'il veille.

Avec le healthcheck, la décision est déportée chez un tiers qui n'a aucune
dépendance avec la machine. Le seul événement observé est l'**arrivée** d'un ping,
et l'absence d'arrivée déclenche l'alerte. Une machine éteinte cesse de pinguer :
alerte. C'est le principe du « homme mort » ferroviaire, d'où le nom.

En pratique on combine les deux : le témoin local pour un diagnostic riche (âge
exact, dernier code retour, journal), le ping sortant pour la garantie de
détection. Et le ping se place **après** la vérification de succès, jamais au
début du script : sinon on signale « tout va bien » avant de savoir si c'est vrai.

Variante sans service externe : le job pousse une métrique
`job_last_success_timestamp` via le *textfile collector* de node_exporter, et
l'alerte Prometheus s'écrit
`time() - job_last_success_timestamp > 93600`. Même logique, même point fort :
la métrique qui cesse d'être mise à jour est elle-même le signal.
:::

::: piege
Trois erreurs de conception à éviter.

Toucher le témoin **au début** du script : il prouve alors que le script a
démarré, pas qu'il a réussi. Un script qui plante systématiquement à mi-parcours
maintient un témoin parfaitement frais.

Faire porter la veille par le **même** ordonnanceur que le job surveillé : si
quelqu'un désactive le timer de la sauvegarde, il y a de bonnes chances qu'il
désactive aussi celui de la veille, et on ne détecte rien. Au minimum, mettre la
veille dans une unité séparée ; idéalement, sur une autre machine.

Régler le seuil trop serré : un job quotidien avec un seuil à 24 h alerte au
moindre décalage de `RandomizedDelaySec`. Le seuil doit valoir environ 1,5 fois
la période. Pour un job quotidien : 26 à 36 heures.
:::

---

**QO14.8** — *Pourquoi `> /dev/null 2>&1` partout est une mauvaise pratique.*

**Réponse attendue.**

Ce qu'on perd exactement : le message d'erreur, et lui seul. Le code retour n'est
pas affecté, le job échoue exactement pareil — mais plus personne ne saura
**pourquoi**. Comme cron n'enregistre que « la commande a été lancée », le journal
d'un job muet est indiscernable de celui d'un job qui réussit. Le diagnostic
devient une reconstitution a posteriori.

Les trois écritures correctes :

```cron
MAILTO=""
# 1. la sortie doit finir dans un fichier
30 2 * * * factura /opt/factura/bin/sauv.sh >> /var/log/factura/sauv.log 2>&1
# 2. la sortie doit finir dans le journal système
30 2 * * * factura /opt/factura/bin/sauv.sh 2>&1 | logger -t factura-sauv
# 3. on ne veut que les erreurs, et rien en cas de succès
30 2 * * * factura /opt/factura/bin/sauv.sh > /dev/null
```

::: pourquoi
La forme 3 est la réponse exacte à l'intention du runbook : on jette **stdout**
(le bavardage de progression) et on laisse **stderr** remonter. Comme cron
n'envoie un mail que s'il y a de la sortie, un job qui réussit reste silencieux et
un job qui échoue produit un mail contenant l'erreur. C'est le modèle cron d'origine,
et il est correct — à condition qu'un MTA soit installé, sinon on retombe sur
`No MTA installed, discarding output` (Q14.8).

La forme 2 est la meilleure sur un serveur moderne : tout est dans le journal,
horodaté, avec une étiquette permettant `journalctl -t factura-sauv --since
yesterday`, soumis à la même rotation et à la même remontée centralisée que le
reste. Rien à gérer, pas de fichier qui grossit.

La forme 1 reste pertinente quand le volume est important ou qu'un outil
d'analyse attend un fichier — avec une rotation `logrotate` associée, sinon on
déplace simplement le problème.

Un point de détail qui a son importance : dans `>> fichier 2>&1`, l'ordre compte.
`2>&1 >> fichier` ferait pointer stderr vers le terminal (donc vers le mail) et
stdout vers le fichier. C'est la redirection la plus mal écrite du métier.
:::

::: piege
La pire variante, très répandue, combine les deux erreurs :

```cron
MAILTO=""
30 2 * * * /opt/factura/bin/sauv.sh > /dev/null 2>&1
```

Aucun mail, aucun journal, aucune trace. Le job peut échouer tous les jours
pendant un an. C'est exactement le scénario de QO14.7, et c'est la cause racine la
plus fréquente des incidents « on n'avait pas de sauvegarde ».

Deuxième piège : rediriger dans un fichier **sans rotation**. Un job à la minute
qui écrit trois lignes remplit le disque en quelques mois, et le job qui plante
pour cause de disque plein est celui qui écrivait le journal. `logger` évite ça
gratuitement.

Troisième piège : croire que le silence prouve le succès. Il faut le vérifier
activement — c'est tout l'objet du témoin de fraîcheur de L14.5.
:::

---

## 14.5 Exercices guidés

**E14.1** — *Traduire quatre expressions cron.*

| Expression | Traduction |
|---|---|
| `0 */4 * * *` | toutes les 4 heures, à la minute 0 (00:00, 04:00, … 20:00) |
| `15 3 * * 0` | tous les dimanches à 03:15 |
| `*/5 9-17 * * 1-5` | toutes les 5 min de 09:00 à 17:55, du lundi au vendredi |
| `0 0 1 1,4,7,10 *` | le 1er janvier, avril, juillet et octobre à minuit |

Équivalents systemd, vérifiés :

```bash
systemd-analyze calendar --iterations=3 "*-*-* 00/4:00:00"
systemd-analyze calendar --iterations=3 "Sun *-*-* 03:15:00"
systemd-analyze calendar --iterations=3 "Mon..Fri *-*-* 09..17:00/5:00"
systemd-analyze calendar --iterations=3 "*-01,04,07,10-01 00:00:00"
```

::: pourquoi
Deux différences de syntaxe à intégrer.

Côté **pas**, cron écrit `*/4` sur le champ heure, systemd écrit `00/4` : la
valeur avant le `/` est le **point de départ**, ce qui est plus explicite et plus
souple (`03/6` donne 03:00, 09:00, 15:00, 21:00, impossible à écrire en cron sans
lister les quatre heures).

Côté **plage**, cron utilise `-` et systemd `..`. Le `-` est réservé au séparateur
de date dans systemd (`2026-09-18`), d'où le choix de `..`. Noter que
`systemd-analyze calendar` accepte quand même `Mon-Fri` et le normalise en
`Mon..Fri` : c'est une tolérance, pas la forme canonique.

Dernier point : `*-01,04,07,10-01` se lit « n'importe quelle année, mois 1/4/7/10,
jour 1 ». La forme normalisée affichée par l'outil complète les zéros.
:::

---

**E14.2** — *Trois expressions à écrire.*

```cron
# toutes les 10 min, 08:00 à 20:00, du lundi au vendredi
*/10 8-19 * * 1-5     # 08:00 -> 19:50
0 20 * * 1-5          # + l'occurrence de 20:00 pile

# à 23:45 le dernier jour de chaque trimestre civil
45 23 31 3,12 *
45 23 30 6,9 *

# toutes les 2 heures les nuits de week-end, 00:00 à 06:00
0 0-6/2 * * 6,0
```

::: pourquoi
Chacune illustre une limite de cron.

La première : « de 08:00 à 20:00 » n'est pas exprimable en une ligne, parce que
`8-20` inclut 20:10, 20:20… jusqu'à 20:50. Il faut soit accepter la dérive, soit
deux lignes. En systemd, une seule expression suffit :
`OnCalendar=Mon..Fri *-*-* 08..20:00/10:00` — mais elle a le même défaut ; la
forme exacte demande `Mon..Fri *-*-* 08..19:00/10,20:00`.

La deuxième : cron ne connaît pas « le dernier jour du mois ». Il faut énumérer,
et distinguer les mois de 31 et de 30 jours. C'est fragile et illisible. systemd
a l'opérateur `~`, compté depuis la fin du mois :

```console
$ systemd-analyze calendar --iterations=2 "*-03,06,09,12-~01 23:45:00"
    Next elapse: Wed 2026-09-30 23:45:00 CEST
   Iteration #2: Thu 2026-12-31 23:45:00 CET
```

Une seule expression, correcte en février, correcte les années bissextiles.

La troisième : `0-6/2` donne `{0,2,4,6}`, et `6,0` couvre samedi et dimanche
(0 = dimanche, 7 aussi). Attention, `6,0` **n'est pas** « samedi soir et dimanche
matin » : le job de samedi 00:00 correspond à la nuit de vendredi à samedi.
Cette ambiguïté « nuit de » est une source classique de malentendu avec les
équipes métier — il faut la lever par écrit.
:::

---

**E14.3** — *Job à la minute qui horodate un fichier.*

```bash
crontab -e
```

```cron
MAILTO=""
* * * * * date '+\%F \%T' >> $HOME/lab14/logs/horodatage.log
```

Vérification puis retrait :

```bash
sleep 120; cat ~/lab14/logs/horodatage.log
crontab -l > ~/lab14/sauv/avant-retrait.cron   # toujours sauvegarder
crontab -e                                      # on retire la ligne
```

::: pourquoi
Deux points de méthode.

Le format `%F %T` donne `2026-09-18 22:14:01`, mais les **deux** `%` doivent être
échappés : le premier coupe la commande, le second serait converti en saut de
ligne. Sans échappement, la commande devient `date '+` — qui affiche une ligne
vide et sort en 0, donc sans la moindre alerte. C'est le pire cas : un bug muet.

`$HOME` est bien substitué, parce que c'est le **shell** appelé par cron qui fait
la substitution, et que cron positionne `HOME`. En revanche, `~` ne fonctionne
pas de façon fiable et `$USER` n'est pas défini (c'est `LOGNAME` que cron pose).
Dans le doute, chemin absolu.
:::

::: piege
`crontab -r` supprime la crontab **entière**, sans confirmation et sans
sauvegarde. La touche `r` est voisine de `e` sur un clavier azerty comme qwerty,
et l'accident est célèbre. Prends le réflexe :

```bash
crontab -l > ~/sauv-$(date +%F).cron
```

Et si l'accident arrive, la crontab est un simple fichier de
`/var/spool/cron/crontabs/<user>` : une restauration de sauvegarde système ou un
snapshot Proxmox la récupère.
:::

---

**E14.4** — *Comparer l'environnement de cron et celui de la session.*

```cron
* * * * * env > $HOME/lab14/logs/cron-env.txt 2>&1
```

```bash
env > ~/lab14/logs/shell-env.txt
sort ~/lab14/logs/cron-env.txt > /tmp/c.s
sort ~/lab14/logs/shell-env.txt > /tmp/s.s
diff /tmp/c.s /tmp/s.s
# ou, pour ne voir que les noms de variables absentes de cron :
comm -13 <(cut -d= -f1 /tmp/c.s) <(cut -d= -f1 /tmp/s.s)
```

Sortie typique sur `lab-web` :

```text
SHELL=/bin/sh
PWD=/home/mathieu
LOGNAME=mathieu
HOME=/home/mathieu
LANG=fr_FR.UTF-8
PATH=/usr/bin:/bin
```

::: pourquoi
Cinq variables. Une session SSH interactive en compte trente à cinquante.
Ce fichier est la pièce à conviction de tous les diagnostics du module : garde-le.

L'absence la plus lourde de conséquences est `PATH`. Les suivantes sont
`LANG`/`LC_ALL` — un script qui trie avec `sort` ou compare des dates formatées
ne produit pas le même résultat en `C` et en `fr_FR.UTF-8` — et toutes les
variables applicatives (`JAVA_HOME`, `NVM_DIR`, `KUBECONFIG`, `AWS_PROFILE`,
`DOCKER_HOST`) que le `.bashrc` posait.

Noter aussi ce qui n'est **pas** là : `TERM`. Tout script appelant `tput`,
`clear`, `dialog` ou un outil qui teste `isatty()` se comporte différemment.
:::

---

**E14.5** — *Reproduire l'échec avec `env -i`.*

```bash
env -i PATH=/usr/bin:/bin HOME="$HOME" SHELL=/bin/sh LOGNAME="$USER" \
  /bin/sh -c "$HOME/lab14/bin/rapport.sh"
```

```console
PATH vu par le script : /usr/bin:/bin
/home/mathieu/lab14/bin/rapport.sh: line 5: factura-inventaire: command not found
```

::: pourquoi
`env -i` démarre une commande avec un environnement **entièrement vide**, puis
n'y met que les affectations qu'on lui donne. C'est la seule façon fiable de
reproduire un environnement minimal : un simple `PATH=/usr/bin:/bin monscript`
laisserait passer les quarante autres variables de ta session.

L'intérêt est le cycle de correction : une seconde au lieu d'une minute
d'attente. On modifie, on relance, on observe. Sur un job quotidien, ce n'est pas
un gain de confort, c'est la différence entre corriger en dix minutes et corriger
en trois jours.

Ici, `factura-inventaire` est en `/usr/local/bin`, absent du `PATH` de cron.
Le script marche en session parce que `/usr/local/bin` est dans le `PATH` par
défaut d'Ubuntu, et il marche sous `sudo -u factura` parce que le `secure_path`
de sudo contient également `/usr/local/bin`. C'est ce qui rend BF14.1 si
déroutant : **les deux façons naturelles de tester reproduisent un environnement
qui n'est pas celui de cron.**
:::

::: astuce
Le même principe pour systemd, qui a son propre environnement :

```bash
sudo systemd-run --pty --wait --unit=diag --property=User=factura \
  /opt/factura/bin/factura-collecte.sh
```

L'unité transitoire s'exécute exactement dans les conditions d'un service, et
`--pty` te rend la sortie à l'écran.
:::

---

**E14.6** — *Tâche livrable par fichier, exécutée en tant que `factura`.*

```ini
# /etc/cron.d/factura-collecte   (droits 0644, root:root)
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=""
*/15 * * * * factura /opt/factura/bin/factura-collecte.sh 2>&1 | logger -t factura-collecte
```

Preuve de prise en compte :

```bash
sudo journalctl -t CRON --since '-2min' | grep factura-collecte
sudo journalctl -t factura-collecte --since '-20min'
```

::: pourquoi
Trois raisons de préférer `/etc/cron.d` à `crontab -u factura -e` :

1. **C'est un fichier**, donc versionnable, déployable par Ansible, relisible
   dans une revue de code. Une crontab utilisateur vit dans
   `/var/spool/cron/crontabs/`, un répertoire que personne ne sauvegarde.
2. **On peut y poser `PATH=`**, qui s'applique à toutes les lignes du fichier.
3. Le fichier est **relu automatiquement** : cron surveille la mtime du
   répertoire. Aucun `systemctl restart` n'est nécessaire, contrairement à ce que
   suggèrent beaucoup de tutoriels.

Contraintes à respecter, toutes vérifiées par le check :
le **champ utilisateur** en 6e position ; le nom du fichier **sans point** (règle
`run-parts`) ; les droits **0644** et le propriétaire **root** ; une tâche sur
**une seule ligne physique**, cron ne connaissant pas la continuation par `\`.
:::

---

**E14.7** — *Script effectivement exécuté depuis `/etc/cron.daily/`.*

```bash
sudo tee /etc/cron.daily/factura-purge >/dev/null <<'EOF'
#!/bin/sh
find /var/log/factura -name '*.log.*' -mtime +14 -delete 2>/dev/null
exit 0
EOF
sudo chmod 0755 /etc/cron.daily/factura-purge
```

```console
$ run-parts --test /etc/cron.daily
/etc/cron.daily/apt-compat
/etc/cron.daily/dpkg
/etc/cron.daily/factura-purge
$ sudo run-parts --report /etc/cron.daily
```

::: pourquoi
Le nom **sans extension** est la seule chose qui compte pour la sélection :
`factura-purge` passe, `factura-purge.sh` non. Les tirets et les chiffres sont
autorisés ; le point ne l'est pas.

`--test` liste sans exécuter : c'est le test de recette. `--report` exécute en
préfixant la sortie du nom du script, ce qui rend les mails de root lisibles
quand une dizaine de scripts tournent à la suite.

Le `exit 0` final n'est pas cosmétique : `find` peut sortir en 1 s'il rencontre
un répertoire illisible, ce qui ferait remonter un échec pour rien.
:::

::: rhel
La chaîne d'appel diffère. Sous Rocky 9, `/etc/crontab` ne lance rien : c'est
`/etc/cron.d/0hourly` qui contient `01 * * * * root run-parts /etc/cron.hourly`,
et `/etc/cron.hourly/0anacron` qui appelle `anacron -s`. C'est donc anacron qui
lance `cron.daily`, `cron.weekly` et `cron.monthly`, à partir de
`/etc/anacrontab`, avec `RANDOM_DELAY=45` et `START_HOURS_RANGE=3-22`.

Conséquence : sur Rocky, un script de `cron.daily` ne tourne jamais avant 03:00 ni
après 22:00, et jamais à heure fixe. Chercher la trace au mauvais moment fait
conclure à tort que le script n'a pas tourné.
:::

---

**E14.8** — *Sortie d'un script vers le journal, sous étiquette.*

```bash
/opt/factura/bin/factura-rapport.sh 2>&1 | logger -t factura-rapport -p user.info
journalctl -t factura-rapport --since '-10min'
```

Variante qui sépare les niveaux — stdout en `info`, stderr en `err` :

```bash
/opt/factura/bin/factura-rapport.sh \
  1> >(logger -t factura-rapport -p user.info) \
  2> >(logger -t factura-rapport -p user.err)
```

::: pourquoi
`logger` écrit dans le journal via le socket `/dev/log`. `-t` fixe le
`SYSLOG_IDENTIFIER`, qui devient le critère de recherche de `journalctl -t`.
`-p facility.level` fixe la priorité : `journalctl -p err` filtre ensuite sur la
gravité, et une remontée centralisée peut router selon la facility.

La variante à substitution de processus (`>(…)`) est la forme propre quand on
veut conserver la distinction stdout/stderr — ce que `2>&1 | logger` détruit
définitivement. Elle demande bash, pas `dash` : elle a donc sa place dans un
script, pas dans une ligne de crontab.

Avantage décisif sur un fichier : rotation, compression et purge sont gérées par
`journald` (`SystemMaxUse=` dans `/etc/systemd/journald.conf`). Aucun
`logrotate` à écrire, aucun disque plein à 3 h du matin.
:::

::: astuce
`systemd-cat -t factura-rapport /opt/factura/bin/factura-rapport.sh` fait la même
chose en une commande, en préservant les niveaux, mais suppose systemd. `logger`
est POSIX et fonctionne partout, y compris en conteneur sans systemd.
:::

---

**E14.9** — *Deux exécutions concurrentes sous verrou.*

```bash
# terminal 1
flock -n /var/lock/factura.lock /opt/factura/bin/factura-lent.sh 60
# terminal 2, pendant que le premier tourne
flock -n /var/lock/factura.lock /opt/factura/bin/factura-lent.sh 5
echo $?          # 1, rien n'a été exécuté
```

Variante « attendre au maximum 5 secondes » :

```bash
flock -w 5 /var/lock/factura.lock /opt/factura/bin/factura-lent.sh 5
echo $?          # 1 si le verrou n'a pas été obtenu en 5 s
```

::: pourquoi
Les trois modes couvrent trois intentions distinctes, et les confondre coûte cher.

`-n` : « si c'est déjà en cours, ce n'est pas la peine ». C'est le bon choix pour
une tâche idempotente et fréquente (collecte, synchronisation) : l'occurrence
manquée sera rattrapée par la suivante.

Sans option : « il faut que ça passe, quand ce sera possible ». Attente
indéfinie. À éviter en cron : un job bloqué accumule les instances en attente,
et on se retrouve avec 300 processus endormis sur le même verrou.

`-w N` : le compromis. On accepte un petit retard, on renonce au-delà. C'est le
bon choix quand un léger décalage est tolérable mais pas l'empilement.

Dans tous les cas le verrou est libéré par le noyau à la mort du processus : il
n'y a jamais de verrou résiduel à nettoyer après un `kill -9` ou un crash.
:::

---

**E14.10** — *Exécution unique avec `at`.*

```console
$ echo /opt/factura/bin/factura-rapport.sh | at now + 3 minutes
warning: commands will be executed using /bin/sh
job 4 at Fri Sep 18 19:55:00 2026
$ atq
4       Fri Sep 18 19:55:00 2026 a mathieu
$ at -c 4 | head -20
$ atrm 4
```

`at` a **enregistré tout l'environnement** de la session qui l'a appelé, et le
restaure au moment de l'exécution.

::: pourquoi
`at -c <id>` affiche le script que `atd` exécutera. On y trouve une centaine de
lignes `export VARIABLE=valeur` avant la commande : `at` a sérialisé
l'environnement complet, plus le répertoire courant et l'`umask`.

```bash
#!/bin/sh
# atrun uid=1000 gid=1000
# mail mathieu 0
umask 22
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; export PATH
LANG=fr_FR.UTF-8; export LANG
...
cd /home/mathieu || { echo 'Execution directory inaccessible' >&2; exit 1; }
/opt/factura/bin/factura-rapport.sh
```

C'est l'opposé exact de cron, et ça explique pourquoi une commande qui marche en
`at` peut échouer une fois transposée en crontab. Pratique pour un one-shot
interactif ; **dangereux en production**, parce que le comportement de la tâche
dépend de qui l'a planifiée et de l'état de son shell à ce moment-là.

`atq` liste, `atrm` supprime, `batch` est la variante qui attend que la charge
moyenne repasse sous 1,5 avant d'exécuter. Les fichiers vivent dans
`/var/spool/cron/atjobs`, ce qui permet de voir les jobs de tous les utilisateurs.
:::

::: piege
`atd` doit tourner : `systemctl enable --now atd`. Sans lui, `at` accepte le job
sans broncher et rien ne se produit jamais.

Et un job `at` ne survit pas à une désinstallation du paquet ni à un changement de
machine : il n'est visible ni dans `systemctl list-timers`, ni dans les crontabs.
C'est une source classique de « tâche fantôme » que personne ne retrouve — d'où
son inclusion dans l'inventaire de L14.1.
:::

---

**E14.11** — *Le même résultat en unité transitoire.*

```console
$ sudo systemd-run --on-active=3min --unit=rapport-ponctuel \
    /opt/factura/bin/factura-rapport.sh
Running timer as unit: rapport-ponctuel.timer
Will run service as unit: rapport-ponctuel.service
$ systemctl list-timers rapport-ponctuel.timer
$ journalctl -u rapport-ponctuel -f
$ sudo systemctl stop rapport-ponctuel.timer      # annulation
```

::: pourquoi
`systemd-run` crée des unités **transitoires** : elles n'existent que dans la
mémoire du gestionnaire, aucun fichier n'est écrit dans `/etc/systemd/system`, et
elles disparaissent au redémarrage. `--on-active=` crée la paire timer + service,
`--unit=` leur donne un nom stable (sinon systemd génère `run-r4f3a….service`).

L'intérêt par rapport à `at` : on hérite de tout systemd en une ligne.

```bash
sudo systemd-run --on-active=3min --unit=rapport \
  --property=User=factura \
  --property=MemoryMax=256M \
  --property=RuntimeMaxSec=600 \
  /opt/factura/bin/factura-rapport.sh
```

La sortie va au journal, sans redirection. L'état est interrogeable avec les
mêmes commandes que n'importe quel service. Et `--on-calendar=` permet un
transitoire récurrent, utile pour un contournement temporaire pendant un
incident, qu'on est sûr de ne pas oublier en place puisqu'il meurt au reboot.
:::

::: piege
Justement : « il meurt au reboot » est une arme à double tranchant. Une tâche
qu'on croyait planifiée disparaît au premier redémarrage. `systemd-run` est fait
pour le ponctuel et le temporaire ; une tâche durable s'écrit dans un fichier.

`systemctl stop x.timer` suffit à annuler : le timer transitoire est alors
déchargé. Pour un service déjà en cours, il faut aussi `systemctl stop x.service`.
:::

---

**E14.12** — *Paire `.service` + `.timer` validée avant installation.*

```ini
# ~/lab14/unites/factura-rapport.service
[Unit]
Description=Factura - rapport quotidien
After=network-online.target

[Service]
Type=oneshot
User=factura
Group=factura
ExecStart=/opt/factura/bin/factura-rapport.sh
```

```ini
# ~/lab14/unites/factura-rapport.timer
[Unit]
Description=Declenche le rapport quotidien factura

[Timer]
OnCalendar=*-*-* 06:15:00
Persistent=true
AccuracySec=1min

[Install]
WantedBy=timers.target
```

```console
$ systemd-analyze calendar --iterations=3 "*-*-* 06:15:00"
Normalized form: *-*-* 06:15:00
    Next elapse: Sat 2026-09-19 06:15:00 CEST
       (in UTC): Sat 2026-09-19 04:15:00 UTC
       From now: 10h left
$ systemd-analyze verify ~/lab14/unites/factura-rapport.timer
$ echo $?
0
```

::: pourquoi
Les deux validations ne testent pas la même chose et sont complémentaires.

`systemd-analyze calendar` interprète l'expression et donne les prochaines
échéances **réelles**, fuseau compris. C'est le seul moyen de vérifier qu'on a
bien compris ce qu'on a écrit — et de découvrir les sauts de changement d'heure
(Q14.11).

`systemd-analyze verify` charge l'unité **et ses dépendances** hors du
gestionnaire : il signale les directives inconnues, les sections mal nommées, les
exécutables absents, les unités référencées introuvables. Une sortie vide et un
code 0 signifient « rien à signaler ». Passer le chemin du `.timer` entraîne la
vérification du `.service` associé.

Le service n'a **pas** de section `[Install]` : il est déclenché, jamais activé
(Q14.13). Le timer en a une, avec `WantedBy=timers.target`, la cible qui
rassemble tous les timers.
:::

::: piege
`systemd-analyze verify` a une limite qu'il faut connaître : une **clé inconnue**
produit un avertissement, mais le code retour reste **0**.

```console
$ systemd-analyze verify ./bad.service
/tmp/bad.service:7: Unknown key name 'Persistant' in section 'Service', ignoring.
$ echo $?
0
```

Une faute de frappe (`Persistant` pour `Persistent`, `ExecStartPre` mal placé)
passe donc le test. En script de CI, il faut vérifier que la **sortie est vide**,
pas seulement le code retour :

```bash
[ -z "$(systemd-analyze verify ./x.timer 2>&1)" ] || exit 1
```

Autre piège : `verify` sur un fichier dans un répertoire quelconque fonctionne,
mais les chemins relatifs doivent commencer par `./`, sinon systemd cherche une
unité installée du même nom.
:::

---

**E14.13** — *Timer 2 min après le boot, puis toutes les 30 min après la fin.*

```ini
[Timer]
OnBootSec=2min
OnUnitInactiveSec=30min
Unit=factura-collecte.service
```

Ce n'est pas `OnUnitActiveSec=30min` parce que celui-ci compte à partir du
**démarrage** de la dernière exécution : si la collecte dure 25 minutes, la
suivante part 5 minutes après la fin de la précédente, pas 30.

::: pourquoi
Les quatre déclencheurs monotones, et leur point de référence :

| Directive | Compté depuis |
|---|---|
| `OnBootSec=` | le démarrage du noyau |
| `OnStartupSec=` | le démarrage du gestionnaire (systemd lui-même) |
| `OnUnitActiveSec=` | le dernier **démarrage** de l'unité déclenchée |
| `OnUnitInactiveSec=` | la dernière **fin** de l'unité déclenchée |

`OnUnitActiveSec` donne une **cadence** : une exécution toutes les 30 minutes,
quelle que soit sa durée. C'est ce qu'on veut pour un relevé régulier.
`OnUnitInactiveSec` donne un **repos** : 30 minutes de calme entre deux
traitements, quelle que soit leur durée. C'est ce qu'on veut pour un traitement
lourd, dont on ne veut pas qu'il enchaîne sans répit.

Plusieurs déclencheurs dans un même `[Timer]` sont en **OU** : le timer se
déclenche dès que l'un d'eux est satisfait. `OnBootSec` amorce le cycle,
`OnUnitInactiveSec` l'entretient. Sans `OnBootSec`, un timer purement
`OnUnitInactiveSec` ne se déclencherait jamais, l'unité n'ayant jamais été
inactive après avoir été active.
:::

::: piege
Les déclencheurs monotones n'ont **aucune mémoire** : `Persistent=true` est
ignoré avec eux. Après un redémarrage, le compteur repart de zéro.

Et `OnUnitActiveSec` avec une valeur inférieure à la durée d'exécution ne produit
pas d'accumulation : systemd ne démarre jamais deux instances (Q14.15), les
échéances sont absorbées. Le rythme réel devient celui de la durée d'exécution.
:::

---

**E14.14** — *Prouver `Persistent=true` sans éteindre la VM.*

```bash
sudo systemctl stop factura-rapport.timer
ls -l --time-style=full-iso /var/lib/systemd/timers/
sudo touch -d '2 days ago' \
  /var/lib/systemd/timers/stamp-factura-rapport.timer
sudo systemctl start factura-rapport.timer
journalctl -u factura-rapport.service --since '-2min'
```

Le service démarre **immédiatement**, sans attendre 06:15.

::: pourquoi
Toute l'information de persistance tient dans la **mtime** d'un fichier vide.
Au démarrage de l'unité timer, systemd lit cette date, calcule la dernière
occurrence théorique de l'expression `OnCalendar`, et compare. Occurrence
postérieure à l'horodatage ⇒ déclenchement immédiat, puis réécriture du fichier.

Antidater le fichier simule donc exactement une machine restée éteinte deux
jours, sans rien éteindre. C'est **la** technique de recette d'un timer
`Persistent=true` : on ne livre pas un rattrapage qu'on n'a jamais vu
fonctionner.

Le `stop` avant modification est nécessaire : sur un timer déjà actif, systemd a
l'horodatage en mémoire et ne relit pas le fichier.
:::

::: piege
Ne fais jamais ça sur une machine de production : le rattrapage déclenche une
sauvegarde complète ou une purge en pleine journée. Et surtout ne **supprime**
pas le fichier pour « repartir propre » — systemd conclut que le timer n'a jamais
tourné et déclenche aussitôt, ce qui est rarement l'effet recherché.
:::

---

**E14.15** — *Tous les timers, dernière exécution la plus ancienne.*

```bash
systemctl list-timers --all
```

```console
NEXT                        LEFT     LAST                        PASSED  UNIT
Sat 2026-09-19 00:00:00 CEST 4h 17min Fri 2026-09-18 00:00:11 CEST 19h ago logrotate.timer
Sat 2026-09-19 06:15:00 CEST 10h      Fri 2026-09-18 06:15:02 CEST 13h ago factura-rapport.timer
-                            -        -                           -       factura-orphelin.timer
```

Le dernier résultat de l'unité déclenchée :

```bash
systemctl show factura-rapport.service -p Result -p ExecMainStatus --value
journalctl -u factura-rapport.service -n 20 --no-pager
```

::: pourquoi
Les colonnes se lisent ainsi : `NEXT`/`LEFT` = prochaine échéance et délai
restant ; `LAST`/`PASSED` = dernier déclenchement et ancienneté ; `UNIT` = le
timer ; `ACTIVATES` (à droite, souvent coupée) = le service déclenché.

`--all` est indispensable : sans lui, la commande masque les timers **inactifs**,
c'est-à-dire précisément ceux qui ne tournent plus. Un timer désactivé est donc
invisible dans la sortie par défaut — c'est exactement le piège de BF14.2.

La sortie est déjà triée par prochaine échéance. Les tirets dans toutes les
colonnes signalent un timer chargé mais non actif.

Une ligne avec un `LAST` très ancien et un `NEXT` normal signale un timer qui
fonctionne mais dont le service échoue, ou qui vient d'être installé. Une ligne
sans `NEXT` signale un timer arrêté. Les deux méritent une alerte, et c'est ce
que détecte le script du défi.
:::

::: piege
Rappel de Q14.17 : `list-timers` ne dit **rien** du résultat des exécutions. Un
timer parfait déclenchant un service qui échoue tous les jours affiche exactement
la même ligne qu'un timer dont tout va bien. Pour balayer l'état réel :

```bash
systemctl list-units --failed
systemctl list-timers --all | awk 'NR>1 && $1=="-" {print "arrêté :", $0}'
```
:::

---

**E14.16** — *Clôture à 22:00 UTC sur trois continents.*

```bash
sudo timedatectl set-timezone UTC       # sur tous les serveurs
timedatectl                              # vérification
```

```ini
[Timer]
OnCalendar=*-*-* 22:00:00 UTC
```

Preuve sur un serveur resté en `Europe/Paris` :

```console
$ systemd-analyze calendar --iterations=2 "*-*-* 22:00:00 UTC"
Normalized form: *-*-* 22:00:00 UTC
    Next elapse: Sat 2026-09-19 00:00:00 CEST
       (in UTC): Fri 2026-09-18 22:00:00 UTC
```

L'affichage local change (minuit à Paris en été, 23:00 en hiver) mais l'**instant
absolu** est identique partout.

::: pourquoi
Deux leviers, à ne pas confondre.

Le **fuseau système** (`timedatectl set-timezone`) détermine l'interprétation par
défaut de toute expression `OnCalendar` et de toute ligne de crontab. C'est le
réglage de fond : UTC sur les serveurs, point.

Le **suffixe de fuseau** dans l'expression (`22:00:00 UTC`,
`09:00:00 Europe/Paris`) verrouille l'interprétation de cette expression-là,
indépendamment du réglage système. Disponible depuis systemd 252, donc sur
Ubuntu 24.04 (systemd 255). C'est la ceinture par-dessus les bretelles : l'unité
reste correcte même si quelqu'un change le fuseau de la machine.

Cron n'a **aucun** équivalent. Une crontab suit le fuseau système, sans
alternative. Sur une flotte multi-fuseaux, c'est un argument de migration à lui
seul.

Pour la mise en forme locale, on fixe `TZ` au niveau de l'exécution :

```ini
[Service]
Environment=TZ=Europe/Paris
```

Le job s'ordonnance en UTC et date ses rapports en heure de Paris. Les deux
préoccupations sont séparées, comme il se doit.
:::

---

## 14.6 Labs

### **L14.1** — Inventaire des tâches planifiées

**Procédure de référence.**

```bash
# 1. crontabs de TOUS les comptes
for u in $(getent passwd | cut -d: -f1); do
  out=$(sudo crontab -u "$u" -l 2>/dev/null) || continue
  [ -n "$out" ] && printf '\n=== crontab de %s ===\n%s\n' "$u" "$out"
done

# 2. tâches système
cat /etc/crontab
for f in /etc/cron.d/*; do echo "--- $f"; cat "$f"; done
for d in hourly daily weekly monthly; do
  echo "--- /etc/cron.$d (ce que run-parts exécutera)"
  run-parts --test "/etc/cron.$d"
  echo "    présents mais ignorés :"
  comm -23 <(ls -1 "/etc/cron.$d" | sort) \
           <(run-parts --test "/etc/cron.$d" | xargs -n1 basename | sort)
done

# 3. tâches at
atq                                  # les tiennes
sudo ls -l /var/spool/cron/atjobs/   # celles de tout le monde

# 4. timers
systemctl list-timers --all --no-pager
systemctl list-unit-files --type=timer
```

Anomalies attendues sur `lab-web` après `setup_M14.sh` :

| Anomalie | Où | Symptôme |
|---|---|---|
| `factura-stats.sh` | `/etc/cron.daily/` | nom à point : jamais exécuté |
| crontab de `factura` | spool | `> /dev/null 2>&1` : trace détruite |
| `factura-archives` | `/etc/cron.d/` | pas de champ utilisateur |
| `factura-orphelin.timer` | systemd | déclenche une unité inexistante |

::: pourquoi
Le point de méthode est l'**exhaustivité**. Une tâche planifiée peut vivre à sept
endroits différents, et un inventaire qui en oublie un donne une fausse
assurance. C'est précisément dans l'endroit oublié que se trouve la tâche qui
cause l'incident.

Deux subtilités de la procédure.

`getent passwd` plutôt que `cat /etc/passwd` : il interroge **toutes** les
sources NSS, donc LDAP ou SSSD si la machine y est raccordée. Un compte annuaire
peut parfaitement avoir une crontab locale.

`comm -23` entre la liste des fichiers et la sortie de `run-parts --test` donne
exactement les scripts **présents mais ignorés**. C'est la seule façon fiable de
les trouver : ils sont visibles dans un `ls`, ils sont exécutables, ils ont l'air
en place, et ils ne tournent jamais.

Pour `factura-orphelin.timer`, la colonne `ACTIVATES` de `list-timers` nomme
l'unité déclenchée. La vérification qui tranche :

```bash
systemctl show factura-orphelin.timer -p Unit --value
systemctl cat factura-orphelin.service   # "No files found" -> orphelin
```
:::

::: piege
Trois oublis classiques dans un inventaire.

Les **timers utilisateur** : `systemctl --user list-timers`, qui ne tournent que
si une session de l'utilisateur est ouverte — sauf si `loginctl enable-linger` a
été positionné. Un timer qui ne tourne « qu'une fois sur deux » est souvent ça.

Les tâches **dans les conteneurs**. `docker exec <c> crontab -l` : une crontab
dans une image est totalement invisible depuis l'hôte.

Les tâches **ailleurs que sur la machine** : un runner CI planifié, un
scheduler applicatif (Celery beat, Quartz, pg_cron), un ordonnanceur
d'entreprise. L'inventaire doit le mentionner, même s'il ne peut pas l'énumérer.
:::

---

### **L14.2** — Sauvegarde nocturne en cron, faite proprement

**Le script.**

```bash
#!/usr/bin/env bash
# /opt/factura/bin/factura-sauvegarde-nuit.sh
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

SRC=/srv/factura/data
DST=/srv/factura/backups
RETENTION=7
TEMOIN=/var/lib/factura/derniere-sauvegarde

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }
err() { printf '%s ERREUR %s\n' "$(date '+%F %T')" "$*" >&2; }

log "debut de la sauvegarde de $SRC"

if [ ! -d "$SRC" ] || [ -z "$(ls -A "$SRC" 2>/dev/null)" ]; then
  err "source absente ou vide : $SRC"
  exit 2
fi

mkdir -p "$DST"
ARCH="$DST/factura-$(date '+%Y%m%d-%H%M%S').tgz"

if ! tar czf "$ARCH.tmp" -C "$(dirname "$SRC")" "$(basename "$SRC")"; then
  err "echec de l'archivage vers $ARCH"
  rm -f "$ARCH.tmp"
  exit 1
fi
mv "$ARCH.tmp" "$ARCH"
log "archive creee : $ARCH ($(du -h "$ARCH" | cut -f1))"

# rétention : on garde les RETENTION plus récentes
ls -1t "$DST"/factura-*.tgz 2>/dev/null | tail -n +$((RETENTION + 1)) \
  | while read -r vieux; do
      log "purge : $vieux"
      rm -f "$vieux"
    done

touch "$TEMOIN"           # témoin de succès (préparé pour L14.5)
log "sauvegarde terminee"
exit 0
```

**La planification.**

```ini
# /etc/cron.d/factura-sauvegarde   (0644, root:root)
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=""
30 2 * * * factura flock -n /run/lock/factura-sauv.lock /opt/factura/bin/factura-sauvegarde-nuit.sh 2>&1 | logger -t factura-sauv
```

**La recette.**

```bash
# exactement ce que cron fera
sudo runuser -u factura -- env -i PATH=/usr/bin:/bin HOME=/srv/factura \
  SHELL=/bin/sh /opt/factura/bin/factura-sauvegarde-nuit.sh
# les deux exécutions simultanées
sudo runuser -u factura -- flock -n /run/lock/factura-sauv.lock \
  /opt/factura/bin/factura-sauvegarde-nuit.sh &
sudo runuser -u factura -- flock -n /run/lock/factura-sauv.lock \
  /opt/factura/bin/factura-sauvegarde-nuit.sh ; echo "second : $?"
```

::: pourquoi
Six décisions de conception méritent d'être justifiées.

**`export PATH` dans le script.** C'est le correctif durable. Le `PATH=` de la
crontab ne protège que les lignes de ce fichier ; le script, lui, sera un jour
appelé par systemd, par Ansible, par un humain. Un script d'exploitation déclare
son environnement.

**Écriture en `.tmp` puis `mv`.** `mv` sur le même système de fichiers est un
`rename(2)`, donc **atomique**. Une archive n'apparaît sous son nom définitif que
lorsqu'elle est complète : un script de restauration ou de purge ne peut jamais
tomber sur un fichier à moitié écrit. C'est la même discipline qu'en BF14.3.

**Trois codes de sortie.** 0 succès, 1 échec d'archivage, 2 source absente ou
vide. Le 2 est essentiel : archiver un répertoire vide produit une archive
valide de 45 octets qui écrase les précédentes par rotation. C'est le scénario
« on avait des sauvegardes, elles étaient toutes vides ».

**`ls -1t | tail -n +8`** trie par date de modification décroissante et saute les
7 premières : il reste exactement les archives à supprimer. Robuste tant que les
noms ne contiennent pas de saut de ligne, ce qui est garanti ici par le format du
nom.

**`flock -n` dans la crontab.** Le `-n` fait échouer immédiatement la seconde
exécution. Comme `flock` sort en 1 et que la sortie passe par `logger`, la
collision laisse une trace datée dans le journal.

**`2>&1 | logger -t`.** Tout, sur un seul canal, étiqueté. `MAILTO=""` évite le
mail. Aucun `/dev/null` nulle part.
:::

::: piege
Deux erreurs très fréquentes sur ce type de script.

`tar czf "$ARCH" /srv/factura/data` (chemin absolu) produit un avertissement
`Removing leading '/'` et une archive dont l'extraction recrée l'arborescence
complète depuis le répertoire courant. La forme `-C parent base` donne une
archive propre, extractible où l'on veut.

`set -e` **ne protège pas** dans un `if`, dans un `&&`, ni à gauche d'un pipe.
D'où le `if ! tar …` explicite plutôt que de compter sur `set -e`. Et dans
`cmd | logger`, le code retour de la ligne est celui de `logger`, toujours 0 :
si la valeur de retour compte, il faut `set -o pipefail` — ce qui n'est pas
possible dans une crontab, puisque le shell est `dash`. Le contrôle du résultat
se fait donc côté service systemd (L14.3), qui voit le vrai code.
:::

---

### **L14.3** — Migration vers un timer systemd

```ini
# /etc/systemd/system/factura-sauv.service
[Unit]
Description=Factura - sauvegarde nocturne
Documentation=https://wiki.interne/exploitation/factura
After=srv-factura.mount network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=factura
Group=factura
ExecStart=/opt/factura/bin/factura-sauvegarde-nuit.sh

# contraintes de ressources
CPUQuota=50%
MemoryMax=512M
RuntimeMaxSec=30min

# durcissement, gratuit
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
NoNewPrivileges=true
ReadWritePaths=/srv/factura /var/log/factura /var/lib/factura
```

```ini
# /etc/systemd/system/factura-sauv.timer
[Unit]
Description=Declenche la sauvegarde nocturne factura

[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true
RandomizedDelaySec=10min
AccuracySec=1min
Unit=factura-sauv.service

[Install]
WantedBy=timers.target
```

```bash
systemd-analyze calendar --iterations=3 "*-*-* 02:30:00" \
  | tee -a ~/lab14/rapports/validation.txt
systemd-analyze verify /etc/systemd/system/factura-sauv.timer \
  2>&1 | tee -a ~/lab14/rapports/validation.txt
sudo systemctl daemon-reload
sudo systemctl enable --now factura-sauv.timer
systemctl list-timers factura-sauv.timer
sudo systemctl start factura-sauv.service      # essai manuel
systemctl status factura-sauv.service
```

Neutralisation réversible de la version cron :

```bash
sudo sed -i 's|^30 2|#MIGRE-VERS-TIMER-2026-09-18 30 2|' \
  /etc/cron.d/factura-sauvegarde
```

Réponse au point 7 : si le timer se déclenche alors que le service tourne encore,
**rien ne se passe**. systemd ne démarre jamais deux instances d'une même unité ;
la demande est fusionnée avec le job en cours (Q14.15). `RuntimeMaxSec=30min`
garantit qu'un blocage ne gèle pas le cycle indéfiniment.

::: pourquoi
Chaque directive répond à une demande explicite de l'exploitation.

**`After=srv-factura.mount`** est une dépendance d'**ordre** seulement : si le
montage n'est pas demandé par ailleurs, il ne sera pas monté, mais l'ordre est
respecté s'il l'est. Pour exiger le montage, il faudrait `Requires=` en plus —
et accepter qu'un échec de montage fasse échouer la sauvegarde, ce qui est
précisément le comportement souhaitable : mieux vaut un échec visible qu'une
archive d'un répertoire vide.

**`Wants=network-online.target`** avec `After=` : `network-online.target` n'est
tiré dans la transaction que si quelqu'un le demande. `Wants=` le demande sans en
faire une condition bloquante.

**`CPUQuota=50%`** se traduit par `cpu.max` dans le cgroup du service : le
processus ne peut pas consommer plus d'un demi-cœur, quel que soit le nombre de
threads. **`MemoryMax=512M`** est une limite dure : au-delà, le cgroup déclenche
l'OOM killer sur le service seul, sans toucher au reste de la machine.

**`RuntimeMaxSec=30min`** est ce que cron ne sait pas faire du tout : au-delà,
systemd envoie `SIGTERM` puis `SIGKILL`, et l'unité passe en `failed` avec
`Result=timeout` — donc `OnFailure=` se déclenche.

**`ProtectSystem=strict`** monte tout le système de fichiers en lecture seule
pour ce service ; `ReadWritePaths=` rouvre précisément ce qu'il doit écrire. Un
bug de chemin dans le script ne peut plus toucher `/etc` ou `/usr`. Quatre lignes,
aucun coût.
:::

::: piege
Erreur de migration numéro un : **laisser la ligne cron active**. On se retrouve
avec deux sauvegardes concurrentes, et comme le verrou `flock` protège le script
mais pas le service, la seconde échoue bruyamment. D'où la neutralisation
commentée, réversible, et visible en `grep MIGRE /etc/cron.d/*`.

Erreur numéro deux : oublier `systemctl daemon-reload`. systemd garde les unités
en cache ; une modification non rechargée donne des comportements inexplicables.
`systemctl status` affiche alors l'avertissement
`Warning: The unit file … changed on disk`.

Erreur numéro trois : `ProtectSystem=strict` sans `ReadWritePaths=` complet. Le
service échoue en `status=1` avec un `Read-only file system` déroutant, parfois
des jours plus tard quand une branche rare du script s'exécute. Teste toutes les
branches, y compris les chemins d'erreur.
:::

---

### **L14.4** — Vérification de certificat avec alerte automatique

```bash
#!/usr/bin/env bash
# /opt/factura/bin/factura-cert-check.sh <certificat> <jours>
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

CERT="${1:?usage: $0 <certificat> <jours>}"
JOURS="${2:-30}"
SECONDES=$((JOURS * 86400))

[ -r "$CERT" ] || { echo "certificat illisible : $CERT" >&2; exit 1; }

FIN=$(openssl x509 -in "$CERT" -noout -enddate | cut -d= -f2)
if openssl x509 -in "$CERT" -noout -checkend "$SECONDES" >/dev/null; then
  echo "OK : $CERT valide au-dela de $JOURS jours (expire le $FIN)"
  exit 0
fi
echo "ALERTE : $CERT expire dans moins de $JOURS jours (le $FIN)" >&2
exit 1
```

```ini
# /etc/systemd/system/factura-cert.service
[Unit]
Description=Factura - controle d'expiration du certificat du portail
OnFailure=factura-alerte@%n.service

[Service]
Type=oneshot
ExecStart=/opt/factura/bin/factura-cert-check.sh \
          /etc/factura/tls/portail.crt 30
```

```ini
# /etc/systemd/system/factura-cert.timer
[Unit]
Description=Declenche le controle de certificat

[Timer]
OnCalendar=*-*-* 07:00:00
AccuracySec=1h
Persistent=true

[Install]
WantedBy=timers.target
```

```ini
# /etc/systemd/system/factura-alerte@.service
[Unit]
Description=Alerte sur echec de %i

[Service]
Type=oneshot
ExecStart=/opt/factura/bin/factura-alerte.sh %i
```

```bash
#!/usr/bin/env bash
# /opt/factura/bin/factura-alerte.sh <unite>
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
UNITE="${1:?unite attendue}"
LOG=/var/log/factura/alertes.log
{
  printf '=== %s ALERTE sur %s ===\n' "$(date '+%F %T')" "$UNITE"
  printf 'resultat : %s / code : %s\n' \
    "$(systemctl show "$UNITE" -p Result --value)" \
    "$(systemctl show "$UNITE" -p ExecMainStatus --value)"
  journalctl -u "$UNITE" -n 10 --no-pager -o cat
  printf '\n'
} >> "$LOG"
```

Test du chemin d'échec :

```bash
sudo systemctl edit --runtime factura-cert.service   # seuil à 3650
sudo systemctl start factura-cert.service
sudo tail -20 /var/log/factura/alertes.log
sudo systemctl revert factura-cert.service
```

::: pourquoi
Le mécanisme d'`OnFailure=` est le cœur du lab.

Quand une unité entre dans l'état `failed` — code de sortie non nul, signal,
dépassement de `RuntimeMaxSec`, `TimeoutStartSec` —, systemd démarre les unités
listées dans `OnFailure=`. C'est **déclaratif** : aucun `if`, aucun `||`, aucun
`trap` dans le script. Le script se contente de sortir en 1 ; la politique de
réaction vit dans l'unité et peut changer sans toucher au code.

Les **spécificateurs** font le lien. `%n` vaut le nom complet de l'unité en échec
(`factura-cert.service`) ; il est substitué dans `OnFailure=factura-alerte@%n.service`,
qui devient `factura-alerte@factura-cert.service.service`. Côté modèle, `%i` vaut
la partie entre `@` et `.service`, donc le nom de l'unité en échec. C'est ce qui
permet d'écrire **une seule** unité d'alerte pour tous les jobs de la machine :

```ini
OnFailure=factura-alerte@%n.service
```

`AccuracySec=1h` est ici un vrai choix : un contrôle de certificat n'a aucune
raison d'être ponctuel à la seconde, et la fenêtre large permet à systemd de
grouper les réveils.

Réponse au point 6 : lancé à la main, le script n'est pas une unité. systemd
n'observe rien, `OnFailure=` ne se déclenche pas. Seul `systemctl start`, ou un
déclenchement par le timer, met le mécanisme en jeu. C'est pour cela que la
recette doit passer par `systemctl start`, jamais par un appel direct.

Si l'unité d'alerte échoue elle-même, systemd le journalise et **s'arrête là** :
`OnFailure=` n'est pas récursif par défaut. Une unité d'alerte qui se déclencherait
sur son propre échec créerait une boucle — d'où l'intérêt de la garder
extrêmement simple : écrire dans un fichier local, pas d'appel réseau, pas de
dépendance.
:::

::: piege
Piège numéro un : `OnFailure=` va dans la section **`[Unit]`**, pas `[Service]`.
Placée au mauvais endroit, la directive produit un avertissement
`Unknown key name` que `systemd-analyze verify` signale… avec un code retour 0
(E14.12). Elle est silencieusement ignorée.

Piège numéro deux : `Type=oneshot` avec `SuccessExitStatus=` mal réglé. Par
défaut, seul 0 est un succès, ce qui est le comportement voulu ici. Mais un
script qui sort en 1 « par convention » pour dire « rien à faire » déclencherait
une alerte à chaque exécution.

Piège numéro trois : mettre une notification **réseau** dans l'unité d'alerte
sans garde-fou. Le jour où la panne est réseau, l'alerte échoue aussi. Écrire
d'abord localement, puis tenter l'envoi, est l'ordre correct.
:::

---

### **L14.5** — Savoir qu'un job n'a pas tourné

```bash
#!/usr/bin/env bash
# /opt/factura/bin/factura-veille.sh [heures]
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

SEUIL="${1:-26}"
TEMOIN=/var/lib/factura/derniere-sauvegarde

# point 6 : pas d'alerte dans les 10 min qui suivent un demarrage
UPTIME=$(cut -d. -f1 /proc/uptime)
if [ "$UPTIME" -lt 600 ]; then
  echo "machine demarree depuis ${UPTIME}s : controle differe"
  exit 0
fi

if [ ! -e "$TEMOIN" ]; then
  echo "ALERTE : aucun temoin de sauvegarde ($TEMOIN)" >&2
  exit 1
fi

AGE=$(( ( $(date +%s) - $(stat -c %Y "$TEMOIN") ) / 3600 ))
if [ "$AGE" -gt "$SEUIL" ]; then
  echo "ALERTE : derniere sauvegarde reussie il y a ${AGE} h (seuil ${SEUIL} h)" >&2
  exit 1
fi
echo "OK : derniere sauvegarde reussie il y a ${AGE} h"
exit 0
```

```ini
# /etc/systemd/system/factura-veille.service
[Unit]
Description=Factura - veille sur la fraicheur des sauvegardes
OnFailure=factura-alerte@%n.service

[Service]
Type=oneshot
ExecStart=/opt/factura/bin/factura-veille.sh 26
```

```ini
# /etc/systemd/system/factura-veille.timer
[Unit]
Description=Declenche la veille de fraicheur

[Timer]
OnCalendar=hourly
RandomizedDelaySec=5min
Persistent=true

[Install]
WantedBy=timers.target
```

Épreuve du dispositif :

```bash
sudo touch -d '40 hours ago' /var/lib/factura/derniere-sauvegarde
sudo systemctl start factura-veille.service
sudo tail -15 /var/log/factura/alertes.log     # l'alerte est là
sudo touch /var/lib/factura/derniere-sauvegarde
sudo systemctl reset-failed factura-veille.service
sudo systemctl start factura-veille.service
systemctl show factura-veille.service -p Result --value   # success
```

::: pourquoi
Trois décisions structurent ce lab.

**Le témoin est touché en fin de script, après succès.** C'est la seule position
qui donne au fichier le sens « la dernière sauvegarde a réussi ». Touché au
début, il signifierait « le script a démarré », ce qui n'a aucune valeur : un
script qui plante systématiquement au milieu maintiendrait un témoin
parfaitement frais.

**Le seuil est 26 h pour un job quotidien**, pas 24. Il faut absorber la
variation normale : `RandomizedDelaySec`, une exécution qui dure, un redémarrage.
Un seuil trop serré produit des faux positifs, et une alerte qui crie au loup est
rapidement ignorée — ce qui la rend pire qu'aucune alerte. Règle : environ 1,5
fois la période.

**La garde sur l'uptime** traite un faux positif réel. Après un redémarrage, la
veille peut s'exécuter avant la sauvegarde ; le témoin est alors légitimement
vieux, mais il n'y a pas d'incident. Dix minutes de grâce suffisent.
`ConditionUptime=` n'existe pas comme directive systemd — la condition se teste
dans le script, via `/proc/uptime`.

Réponse au point 5 : **non**, le dispositif ne détecte pas une machine éteinte.
Le veilleur est sur la machine veillée : machine éteinte, pas de veille, pas
d'alerte. C'est exactement le point aveugle que corrige un healthcheck externe
(QO14.7) : le job pousse un ping sortant après succès, un service tiers alerte
quand le ping **manque**. L'absence de signal devient elle-même le signal, et
aucune panne locale ne peut la supprimer.
:::

::: piege
Piège de conception majeur : mettre la veille dans le **même** timer, ou dans le
même fichier de crontab, que le job surveillé. Celui qui désactive l'un désactive
l'autre, et on ne détecte plus rien. Deux unités séparées au minimum ; sur une
autre machine dans l'idéal.

Piège d'implémentation : `stat -c %Y` donne la mtime en epoch, mais `touch` sans
argument met la date **courante**, alors que `touch -d '40 hours ago'` antidate.
Ne pas confondre pendant les tests.

Piège de supervision : une veille qui échoue en boucle (unité `failed`) ne
redéclenche `OnFailure=` qu'à chaque nouvelle exécution — donc une alerte par
heure. Prévoir une dé-duplication côté destination, ou ajouter un état
« déjà alerté » dans le script d'alerte.
:::

---

## 14.7 Break & Fix

### **BF14.1** — « La collecte de nuit ne produit plus rien »

**Diagnostic, dans l'ordre.**

```bash
# 1. la tâche est-elle déclenchée ?
sudo journalctl -t CRON --since '-20min' | grep factura-collecte
#    -> cron[…]: (factura) CMD (/opt/factura/bin/factura-collecte.sh …)
#    OUI : la planification est bonne, le problème est à l'exécution.

# 2. y a-t-il une trace de l'erreur ?
sudo journalctl -t factura-collecte --since '-20min'
#    -> factura-collecte.sh: line 8: factura-inventaire: command not found

# 3. où est ce binaire, et qui le voit ?
command -v factura-inventaire        # /usr/local/bin/factura-inventaire
sudo -u factura sh -c 'echo $PATH'   # secure_path de sudo : contient /usr/local/bin

# 4. quel PATH cron applique-t-il vraiment ?
sudo cat /etc/cron.d/factura-collecte
#    -> PATH=/usr/bin:/bin
```

**Cause racine.** Le fichier `/etc/cron.d/factura-collecte` porte la ligne
`PATH=/usr/bin:/bin`. Le script appelle `factura-inventaire` sans chemin absolu ;
ce binaire est en `/usr/local/bin`, hors de ce `PATH`. Le script sort en 127.

**Correctif** (interdit de toucher au script) :

```bash
sudo sed -i 's|^PATH=.*|PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin|' \
  /etc/cron.d/factura-collecte
# vérification sans attendre 5 minutes
sudo runuser -u factura -- env -i PATH=/usr/local/bin:/usr/bin:/bin \
  HOME=/srv/factura /opt/factura/bin/factura-collecte.sh
tail -2 /var/log/factura/collecte.log
```

**Prévention.** Le script déclare son propre `PATH` (`export PATH=…` en tête), ce
qui le rend indépendant de son appelant. À défaut, chemins absolus.

::: pourquoi
Pourquoi `sudo -u factura` ne reproduisait pas le problème : `sudo` **remplace**
le `PATH` par la valeur de `secure_path` définie dans `/etc/sudoers`.

```console
$ sudo grep secure_path /etc/sudoers
Defaults    secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
```

`/usr/local/bin` y figure. Les deux méthodes naturelles de test — lancer le script
dans son shell, le lancer sous `sudo -u` — donnent donc toutes les deux un `PATH`
riche. Aucune ne reproduit l'environnement de cron. C'est ce qui rend ce type de
panne si déroutant, et c'est pourquoi E14.5 insiste sur `env -i`.

Sur le code 127 : c'est la valeur conventionnelle de « commande introuvable »,
renvoyée par le shell. 126 signifie « trouvée mais non exécutable » (bit `x`
manquant, ou shebang pointant un interpréteur absent). Distinguer les deux fait
gagner dix minutes.

Ordre de robustesse des correctifs, du meilleur au pire :

1. `export PATH=…` en tête du script — le script devient autonome ;
2. chemins absolus dans le script — sûr mais verbeux ;
3. `PATH=` dans le fichier de `/etc/cron.d` — correct, mais invisible depuis le
   script et non reporté si la tâche migre vers systemd ;
4. `. /etc/profile` dans la crontab — à proscrire (QO14.2).
:::

::: piege
L'erreur classique de résolution consiste à ajouter `/usr/local/bin` au `PATH`
**global** (`/etc/environment`) en espérant que cron le lise. Cron ne lit pas
`/etc/environment` ; c'est PAM qui le fait, via `pam_env`, et la configuration
PAM de cron sur Debian ne charge pas nécessairement l'environnement utilisateur
complet. Le correctif semble marcher sur certaines machines et pas sur d'autres,
ce qui est le pire des deux mondes.

Deuxième piège : conclure que « cron est cassé » parce que `systemctl status cron`
est vert et que la tâche ne produit rien. Cron fait exactement son travail :
il lance la commande, qui échoue. L'étape 1 du diagnostic (vérifier la ligne
`CMD` dans le journal) tranche cette question en dix secondes et évite d'aller
chercher dans la mauvaise direction.
:::

---

### **BF14.2** — « Le rapport hebdo n'arrive plus, mais rien n'est en erreur »

**La commande qui prouve, en une ligne :**

```console
$ systemctl list-timers --all | grep factura-hebdo
-  -  -  -  factura-hebdo.timer  factura-hebdo.service
```

Que des tirets : le timer est chargé mais **inactif**. Aucune échéance n'est
programmée. La tâche n'est plus planifiée.

**Diagnostic.**

```bash
systemctl is-enabled factura-hebdo.timer      # disabled   <- la cause
systemctl is-enabled factura-hebdo.service    # enabled    <- le leurre
systemctl is-active  factura-hebdo.timer      # inactive
journalctl -u factura-hebdo.timer --since '-30d' | tail
ls -l /var/lib/systemd/timers/                # pas de stamp- pour hebdo
```

**Cause racine.** Quelqu'un a activé le **service** au lieu du **timer**, puis,
constatant qu'il tournait à chaque démarrage, a désactivé le timer. Résultat :
plus aucune planification, et `systemctl is-enabled factura-hebdo` — sans suffixe,
donc résolu en `.service` — répond `enabled`, ce qui rassure à tort.

**Remise en service.**

```bash
sudo systemctl disable factura-hebdo.service    # il n'a rien à faire là
sudo systemctl enable --now factura-hebdo.timer
systemctl list-timers factura-hebdo.timer       # NEXT et LEFT renseignés
sudo systemctl start factura-hebdo.service      # on rattrape à la main
```

**Supervision qui aurait levé l'alerte en 24 h** : la veille de fraîcheur de
L14.5 sur un témoin touché par le rapport, ou une alerte sur
`LastTriggerUSec` du timer trop ancien — c'est la sixième détection du défi D14.

::: pourquoi
Cette panne est instructive parce qu'elle est **silencieuse par construction**.
Aucun des réflexes habituels ne la révèle :

* `systemctl status factura-hebdo.service` affiche `inactive (dead)` — ce qui est
  l'état **normal** d'un `oneshot` terminé, indiscernable d'un service jamais
  lancé ;
* `systemctl list-units --failed` est vide, puisque rien n'a échoué ;
* `journalctl` ne contient rien d'anormal, puisqu'il ne s'est rien passé.

Il n'y a pas d'erreur à trouver : il y a une **absence** à constater. C'est
exactement la classe de panne décrite en QO14.7, et le seul outil qui la montre
directement est `systemctl list-timers --all`. Sans `--all`, la ligne n'apparaît
même pas : les timers inactifs sont masqués par défaut.

Le leurre de `is-enabled factura-hebdo` mérite d'être compris : quand aucun
suffixe n'est donné, `systemctl` ajoute `.service`. La commande interroge donc le
service, pas le timer. Discipline à adopter : **toujours suffixer explicitement**
les commandes touchant à des timers.
:::

::: piege
Le piège d'après-coup : « je remets le timer en route, l'affaire est classée ».
Non. Le service est resté `enabled`, donc il tournera encore à chaque démarrage,
en plus des lundis. Il faut le `disable`, et supprimer la section `[Install]` du
fichier `.service` pour que l'erreur ne puisse pas être refaite — `enable` sur ce
service échouera alors avec un message clair.

Autre piège : croire que `Persistent=true` aurait rattrapé les trois semaines
manquées. Non : `Persistent=` n'agit qu'au **démarrage du timer**. Un timer
désactivé n'est pas démarré, il ne rattrape rien. Et au moment de la réactivation,
il ne rattrape qu'**une** occurrence, pas trois.
:::

---

### **BF14.3** — « Le compteur de factures est incohérent une nuit sur trois »

**Reproduction à la demande.**

```bash
cat /srv/factura/etat/compteur.txt; echo
sudo runuser -u factura -- env FACTURA_LENTEUR=4 \
  /opt/factura/bin/factura-compteur.sh &
sleep 4.1
sudo runuser -u factura -- env FACTURA_LENTEUR=0 \
  /opt/factura/bin/factura-compteur.sh
wait; cat /srv/factura/etat/compteur.txt; echo
```

```console
19:40:06 compteur : 4820 -> 5020
19:40:06 compteur :  -> 200
502 0200          <- deux écritures entremêlées
```

**Mécanisme.** Le script fait une séquence **lecture → calcul → troncature →
écriture** non atomique, et la planification (`* * * * *`) est plus rapide que la
durée du traitement (75 s). Deux instances se chevauchent systématiquement :

| Instant | Instance A | Instance B |
|---|---|---|
| t+0 | lit 4820 | — |
| t+60 | traite | lit 4820 |
| t+75 | tronque, écrit 5020 | traite |
| t+135 | — | tronque, écrit 5020 |

Trois symptômes selon l'entrelacement : **incrément perdu** (les deux lisent la
même valeur), **lecture vide** (l'une lit pendant la fenêtre de troncature de
l'autre, `valeur` vaut la chaîne vide, l'arithmétique la traite comme 0), et
**nombres collés** (deux écritures qui se suivent dans un fichier tronqué une
seule fois).

**Correctif — verrou, dans la planification.**

```ini
# /etc/cron.d/factura-compteur
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
MAILTO=""
* * * * * factura flock -n /run/lock/factura-compteur.lock /opt/factura/bin/factura-compteur.sh 2>&1 | logger -t factura-compteur
```

Et, sur le fond, la cadence est fausse : un traitement de 75 s ne se planifie pas
toutes les minutes. `*/5 * * * *` avec le verrou est la vraie réponse.

**Trois serveurs sur le même fichier** : `flock` ne suffit plus. Il faut un verrou
partagé (table SQL avec contrainte d'unicité, `etcd`, Consul), ou faire porter
l'écriture par un seul nœud élu.

::: pourquoi
Le nom exact du mécanisme est **race condition sur lecture-modification-écriture**
(*lost update*). Il apparaît dès que deux processus lisent une valeur, calculent
à partir d'elle, et la réécrivent, sans exclusion mutuelle entre la lecture et
l'écriture.

Deux propriétés expliquent les trois symptômes.

La première est l'absence d'**exclusion mutuelle** : rien n'empêche deux
instances d'être simultanément entre la lecture et l'écriture. C'est ce que
`flock` corrige.

La seconde est l'absence d'**atomicité de l'écriture** : `: > fichier` puis
`printf >> fichier` laisse une fenêtre pendant laquelle le fichier est vide ou
partiel. Un lecteur qui tombe dedans lit une chaîne vide. La parade, quand on ne
peut pas verrouiller les lecteurs, est l'écriture atomique par renommage :

```bash
printf '%d' "$nouvelle" > "$F.tmp" && mv "$F.tmp" "$F"
```

`mv` sur le même système de fichiers est un `rename(2)` : le fichier passe de
l'ancien contenu au nouveau **sans état intermédiaire observable**. C'est la même
discipline que pour l'archive de L14.2.

Le code retour reste 0 dans tous les cas : chaque instance fait exactement ce
qu'on lui a demandé, sans erreur. Aucune supervision fondée sur les codes retour
ne peut voir ce bug. C'est la corruption de données qui le révèle, souvent des
semaines plus tard.
:::

::: piege
La correction insuffisante consiste à mettre `flock` **sans** `-n`. Le verrou
empêche bien la corruption, mais chaque instance attend la précédente : avec une
cadence d'une minute pour un traitement de 75 secondes, la file grossit
indéfiniment, et on finit avec des centaines de processus endormis. Le
`-n` (refuser) est le bon choix pour un traitement idempotent et fréquent.

La correction cosmétique consiste à ralentir la cadence sans poser de verrou. Ça
réduit la probabilité sans supprimer la cause : le jour où le traitement dure
plus longtemps que prévu — volume de données, disque lent, machine chargée — le
bug revient, et il est d'autant plus difficile à diagnostiquer qu'il est devenu
rare.

Enfin, il ne faut pas confondre ce cas avec le verrou **consultatif** : `flock`
ne protège que les processus qui le demandent. Un administrateur qui lance le
script à la main court-circuite tout. La protection définitive s'écrit **dans le
script**, avec `exec 9>lock ; flock -n 9 || exit 0`.
:::

---

### **BF14.4** — « L'archivage ne produit plus rien depuis la simplification »

**La ligne fautive :**

```cron
*/2 * * * * factura tar czf /srv/factura/backups/data-$(date +%F).tgz /srv/factura/data 2>&1 | logger -t factura-archivage
```

**Le mécanisme, caractère par caractère.** Avant de passer quoi que ce soit au
shell, cron traite le champ commande :

```text
… /srv/factura/backups/data-$(date +%F).tgz /srv/factura/data …
                                    ↑
                          premier % non échappé
```

1. Le **premier `%`** termine la commande. Elle devient :
   `tar czf /srv/factura/backups/data-$(date +`
2. Tout ce qui suit devient l'**entrée standard** : `F).tgz /srv/factura/data 2>&1 | logger …`
3. Un éventuel `%` suivant y serait converti en saut de ligne.

Cron exécute alors `/bin/sh -c 'tar czf /srv/factura/backups/data-$(date +'`.
La substitution `$(` n'est jamais refermée :

```console
$ sudo journalctl -t CRON --since '-5min' | tail -2
cron[1533]: (factura) CMD (tar czf /srv/factura/backups/data-$(date +)
cron[1533]: (CRON) info (No MTA installed, discarding output)
$ /bin/sh -c 'tar czf /srv/factura/backups/data-$(date +'
/bin/sh: 1: Syntax error: end of file unexpected (expecting ")")
```

Noter que le pipe vers `logger` fait lui aussi partie de ce qui est passé sur
stdin : l'erreur ne part donc **pas** dans le journal étiqueté, seulement dans le
mail — inexistant. D'où le silence.

**Correctif dans la crontab :**

```cron
*/2 * * * * factura tar czf /srv/factura/backups/data-$(date +\%F).tgz /srv/factura/data 2>&1 | logger -t factura-archivage
```

**Règle générale** : aucun `%` dans une crontab. La commande va dans un script,
la crontab n'appelle que le script. On supprime du même coup le problème de
longueur de ligne, de quoting, et de lisibilité.

::: pourquoi
La raison d'être de ce comportement est documentée dans `crontab(5)` : `%`
permet d'alimenter la commande en données, la première ligne après le `%` devenant
stdin. C'était une commodité de l'époque où l'on écrivait des requêtes SQL ou des
courriers directement dans la crontab.

En 2026, ce n'est plus qu'un piège, pour trois raisons.

D'abord, `crontab -e` **ne le signale pas**. La validation syntaxique porte sur
le format (nombre de champs, plages valides), jamais sur le contenu de la
commande. La ligne est acceptée sans un mot.

Ensuite, la commande **fonctionne parfaitement** quand on la copie-colle dans un
shell. Impossible de reproduire l'erreur par le test naturel — c'est la même
famille de piège que BF14.1.

Enfin, le message d'erreur parle du **shell** et non de `tar`, ce qui oriente le
diagnostic dans la mauvaise direction. Le vrai indice est la ligne `CMD` du
journal : elle montre la commande **telle que cron l'a réellement lancée**, donc
tronquée. Un coup d'œil à cette ligne et le mécanisme saute aux yeux.

Formes correctes de l'échappement :

```cron
0 2 * * * cmd $(date +\%F)          # dans une substitution
0 2 * * * cmd `date +\%Y\%m\%d`     # chaque % s'échappe séparément
0 2 * * * printf '100\%% termine\n' # un % littéral s'écrit \%
```
:::

::: piege
L'échappement partiel est le piège d'après. Écrire `date +\%Y%m%d` n'échappe que
le premier `%` : les deux suivants coupent quand même. **Chaque** `%` doit porter
son antislash, sans exception.

Deuxième piège : `%` dans une variable **n'est pas** protégé. Si la crontab
contient `FORMAT=+%F` en tête, la ligne `cmd $(date $FORMAT)` fonctionne, parce
que la substitution a lieu dans le shell après le traitement de cron — mais le
`%` de la ligne `FORMAT=` est, lui, traité normalement par cron dans les lignes
de **commande** seulement, pas dans les lignes d'affectation. Cette subtilité
suffit à disqualifier l'approche.

Troisième piège, dans l'autre sens : `systemd` n'a pas ce problème avec `%`, mais
il a le sien — `%` y est le caractère des **spécificateurs** (`%n`, `%i`, `%H`).
Un `ExecStart=` contenant un `%` littéral doit l'écrire `%%`. Le mécanisme est
différent, la vigilance est la même.
:::

---

## 14.8 Défi du module

**D14 — Refonte et audit de la planification d'un hôte**

**Squelette de référence de `~/bin/audit-planif.sh`.**

```bash
#!/usr/bin/env bash
# audit-planif.sh — inventaire et audit des tâches planifiées d'un hôte.
# stdout : rapport Markdown. stderr : trace de diagnostic. 0 = RAS, 1 = anomalies.
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ANOMALIES=()
trace() { printf '[audit] %s\n' "$*" >&2; }
anomalie() { ANOMALIES+=("$1"); }

# --- portabilité Ubuntu / Rocky ---------------------------------------
if systemctl list-unit-files 2>/dev/null | grep -q '^crond\.service'; then
  CRON_UNIT=crond.service
else
  CRON_UNIT=cron.service
fi
trace "service cron : $CRON_UNIT"

printf '# Audit de la planification — %s\n\n' "$(hostname -f)"
printf '_Généré le %s_\n\n' "$(date '+%F %T %Z')"

printf '## Tâches planifiées\n\n'
printf '| Source | Planification | Commande | Utilisateur | Dernière |\n'
printf '|---|---|---|---|---|\n'

# --- 1. crontabs utilisateurs -----------------------------------------
while IFS=: read -r u _; do
  crontab -u "$u" -l 2>/dev/null | grep -vE '^[[:space:]]*(#|$)' \
  | while read -r ligne; do
      case "$ligne" in [A-Z]*=*) continue;; esac
      plan=$(echo "$ligne" | awk '{print $1,$2,$3,$4,$5}')
      cmd=$(echo "$ligne"  | cut -d' ' -f6-)
      printf '| crontab %s | `%s` | `%s` | %s | — |\n' "$u" "$plan" "$cmd" "$u"
      case "$cmd" in
        *%*) [ "${cmd%%\\%*}" = "$cmd" ] && \
             anomalie "crontab $u : % non échappé — \`$cmd\`" ;;
      esac
      case "$cmd" in
        *'/dev/null'*) anomalie "crontab $u : sortie jetée — \`$cmd\`" ;;
      esac
    done
done < <(getent passwd)

# --- 2. /etc/crontab et /etc/cron.d -----------------------------------
# (mêmes contrôles, plus : champ utilisateur présent ?)
# --- 3. cron.hourly/daily/weekly/monthly ------------------------------
for d in hourly daily weekly monthly; do
  rep="/etc/cron.$d"
  [ -d "$rep" ] || continue
  actifs=$(run-parts --test "$rep" | xargs -r -n1 basename | sort)
  tous=$(ls -1 "$rep" 2>/dev/null | sort)
  for f in $(comm -23 <(echo "$tous") <(echo "$actifs")); do
    anomalie "$rep/$f : jamais exécuté (run-parts ignore ce nom)"
  done
done
# --- 4. timers --------------------------------------------------------
# ACTIVATES inexistant ? LastTriggerUSec > 2x intervalle ?
# --- 5. verrous -------------------------------------------------------
# tâche de période < 15 min sans flock / run-one ?

printf '\n## Anomalies\n\n'
if [ "${#ANOMALIES[@]}" -eq 0 ]; then
  printf 'Aucune anomalie détectée.\n'
  exit 0
fi
for a in "${ANOMALIES[@]}"; do printf -- '- %s\n' "$a"; done
exit 1
```

::: pourquoi
Quatre points de conception font la différence entre un script qui « affiche des
trucs » et un outil d'audit exploitable.

**Séparation stdout / stderr.** Le rapport sur stdout, la trace sur stderr. C'est
ce qui permet `audit-planif.sh > rapport.md` sans post-traitement, et
`audit-planif.sh 2>/dev/null` en usage silencieux. Un outil qui mélange les deux
n'est pas scriptable.

**Code retour signifiant.** 0 = rien à signaler, 1 = anomalies. Le script devient
utilisable dans un pipeline CI, dans un contrôle de conformité, ou dans un timer
avec `OnFailure=`. C'est exactement ce que fait le check du défi.

**Portabilité par détection, pas par supposition.** `crond.service` sous Rocky,
`cron.service` sous Ubuntu. La détection se fait sur l'existence de l'unité, pas
sur `/etc/os-release` : c'est plus robuste face aux dérivés.

**Détection des anomalies, pas seulement inventaire.** Un inventaire brut ne se
lit pas ; personne ne relira 60 lignes de tâches. La section « Anomalies »
concentre la valeur : c'est elle qu'on met dans le ticket.

Sur la détection du `%` non échappé, la subtilité est de ne pas signaler un `\%`
légitime. Le test doit chercher un `%` **non précédé d'un antislash** :

```bash
printf '%s' "$cmd" | grep -qP '(?<!\\)%'
```

Avec `grep -P` (PCRE) le regard arrière est direct. Sans PCRE, on supprime
d'abord les `\%` puis on cherche un `%` résiduel :

```bash
printf '%s' "${cmd//\\%/}" | grep -q '%'
```

Pour la détection « dernière exécution trop ancienne », la source est :

```bash
systemctl show "$t" -p LastTriggerUSec --value
systemctl show "$t" -p TimersCalendar --value
```

Un `LastTriggerUSec` vide signifie « jamais déclenché » — à signaler aussi.
:::

::: piege
Piège numéro un : parser les crontabs avec `awk '{print $6}'` sans traiter les
lignes d'affectation (`PATH=`, `MAILTO=`, `SHELL=`) ni les raccourcis `@daily`,
`@reboot`, qui n'ont **pas** cinq champs de temps. Un audit qui plante sur
`@reboot` rate justement les tâches les plus faciles à oublier.

Piège numéro deux : oublier les timers **utilisateur**
(`systemctl --user list-timers`, et `loginctl list-users` pour savoir qui a le
*linger* activé). Ils sont invisibles depuis l'inventaire système.

Piège numéro trois : `set -euo pipefail` combiné à `crontab -u "$u" -l`, qui sort
en **1** quand l'utilisateur n'a pas de crontab. Sans `|| true` ou sans redirection
du code retour, l'audit s'arrête au premier compte système. C'est l'erreur la
plus fréquente sur ce script.

Piège numéro quatre : une boucle `while … | while read` crée un **sous-shell**, et
un tableau `ANOMALIES` rempli dedans est perdu à la sortie du pipe. Il faut une
substitution de processus (`done < <(…)`), ou écrire les anomalies dans un
fichier temporaire. Le squelette ci-dessus utilise `< <(getent passwd)` pour la
boucle externe, mais le `| while` interne a ce défaut : c'est un exercice de le
corriger.
:::

---

::: astuce
**Aide-mémoire de fin de module** — les six commandes qui résolvent 90 % des
incidents de planification :

```bash
journalctl -t CRON --since today          # la tâche a-t-elle été lancée ?
journalctl -u <unite>.service -n 50       # qu'a-t-elle produit ?
systemctl list-timers --all               # qu'est-ce qui est planifié ?
systemd-analyze calendar "<expression>"   # ai-je bien compris mon expression ?
run-parts --test /etc/cron.daily          # ce script tournera-t-il ?
env -i PATH=/usr/bin:/bin sh -c '<cmd>'   # reproduire l'environnement de cron
```
:::
