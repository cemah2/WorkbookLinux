# Module 16 — Corrigé

## 16.3 Quiz — QCM

**Q16.1** — *`journalctl -b -1` répond `Failed to look up boot -1` après un
redémarrage.*

**Réponse : c)** le journal est volatile, `/var/log/journal` n'existe pas.

::: pourquoi
La clé `Storage=` de `journald.conf` vaut `auto` par défaut, et `auto` signifie
exactement ceci : « persistant **si** le répertoire `/var/log/journal` existe,
volatile sinon ». Sur une image cloud minimale, ce répertoire n'est pas créé : le
journal vit dans `/run/log/journal`, c'est-à-dire un `tmpfs`. Au redémarrage, le
`tmpfs` est recréé vide et l'historique disparaît. `journalctl -b` fonctionne
(le démarrage courant est là), `-b -1` n'a plus rien à lire.

La bascule se fait en deux temps :

```bash
sudo mkdir -p /var/log/journal
sudo systemd-tmpfiles --create --prefix /var/log/journal
sudo systemctl restart systemd-journald
```

`systemd-tmpfiles` est ce qui pose les bons droits (`root:systemd-journal`,
mode `2755`) : sans lui, le répertoire créé à la main fonctionne, mais les
utilisateurs du groupe `systemd-journal` ne pourront pas lire le journal.
Une fois le répertoire en place, `journalctl --flush` recopie ce qui était en
mémoire vers le disque, et les démarrages suivants sont conservés.
:::

::: piege
On croit souvent que `Storage=persistent` est nécessaire. Il ne l'est pas : il
force la persistance en créant le répertoire lui-même. Le poser sans réfléchir a
un effet de bord réel sur une machine à disque lent ou sur une carte SD : le
journal écrit en continu. Sur un serveur, c'est ce qu'on veut. Sur un système
embarqué, non.
:::

---

**Q16.2** — *Isoler les messages envoyés par `logger -p local3.warning`.*

**Réponse : b)** `journalctl SYSLOG_FACILITY=19 -p warning`

::: pourquoi
Les facilités `local0` à `local7` portent les codes **16 à 23**. `local3` vaut
donc 19. journald stocke la facilité dans le champ indexé `SYSLOG_FACILITY`, et
les filtres `CHAMP=valeur` sont la façon native de l'interroger. Depuis systemd 245, `journalctl`
`--facility``=local3 -p warning` est un équivalent lisible (`--facility=help` liste les noms); d) est fausse parce que `-p` n'accepte que des priorités : `Unknown log level local3.warning`.

Vérification immédiate :

```bash
logger -p local3.warning "cache froid"
journalctl SYSLOG_FACILITY=19 -n 5 -o verbose
```

`-o verbose` affiche tous les champs de l'entrée : c'est la carte de ce qu'on
peut filtrer. On y voit `SYSLOG_FACILITY=19`, `PRIORITY=4`,
`SYSLOG_IDENTIFIER=mathieu` (le tag par défaut de `logger`, c'est le nom
d'utilisateur), `_UID`, `_ COMM=logger`.

a) est fausse car `-t` filtre le **tag** (`SYSLOG_IDENTIFIER`), pas la facilité.
b) invente une unité `local3.service` qui n'existe pas.
:::

---

**Q16.3** — *Que fait `journalctl --vacuum-size=200M` ? (deux réponses)*

**Réponses : b) et d)**

::: pourquoi
Le journal est une suite de fichiers. À un instant donné, il y a pour chaque
espace de noms **un fichier actif** (`system.journal`, `user-1000.journal`) dans
lequel journald écrit, et **des fichiers archivés** (`system@<seq>-<hash>.journal`)
qui sont fermés et immuables.

`--vacuum-size`, `--vacuum-time` et `--vacuum-files` ne travaillent que sur les
fichiers **archivés** : ils en suppriment du plus ancien au plus récent jusqu'à
respecter la contrainte. Le fichier actif n'est jamais touché, parce qu'il est
ouvert en écriture et qu'y toucher corromprait le journal.

Conséquence pratique qui surprend : sur une machine où le fichier actif fait à
lui seul 900 Mo, `--vacuum-size=200M` ne fera **rien** ou presque. La parade est
de forcer une rotation d'abord :

```bash
sudo journalctl --rotate            # le fichier actif devient archivé
sudo journalctl --vacuum-size=200M  # puis on purge
```

c) est fausse : la commande est ponctuelle, elle n'écrit rien dans
`journald.conf`. Pour une limite durable, c'est `SystemMaxUse=`.
:::

---

**Q16.4** — *`Suppressed 2381 messages from /system.slice/factura-bruyant.service`.*

**Réponse : a)** les 2381 messages sont définitivement perdus.

::: pourquoi
journald applique un limiteur de débit **par service** (par cgroup, plus
exactement), gouverné par deux clés : `RateLimitIntervalSec` (fenêtre, 30 s par
défaut) et `RateLimitBurst` (nombre de messages autorisés dans la fenêtre,
10 000 par défaut). Quand un service dépasse le quota, journald **jette** les
messages suivants jusqu'à la fin de la fenêtre. Il ne les met pas en file, il ne
les déporte pas : il les jette, et il écrit lui-même une entrée de compte rendu
à la fin de la fenêtre.

C'est une protection contre le déni de service par journalisation : sans elle,
un service en boucle d'erreur remplit `/var` et fait tomber toute la machine.

Le message perdu l'est pour tout le monde en aval, y compris rsyslog lorsqu'il
reçoit via `imjournal` : rsyslog ne voit que ce que journald a bien voulu
garder. d) est donc fausse, et c) aussi — `--flush` ne fait que recopier le
journal de `/run` vers `/var`, il ne ressuscite rien.
:::

::: piege
Le quota est calculé **par unité**. Un service qui parle beaucoup ne fait donc
pas taire les autres : c'est un point qu'on oublie souvent quand on cherche
pourquoi seuls les logs d'une application ont des trous. Et le burst réel est
modulé par l'espace disque disponible : journald l'augmente quand `/var` est
vide et le réduit quand il se remplit.
:::

---

**Q16.5** — *`local5.err /var/log/factura/erreurs.log` : quels messages ?*

**Réponse : d)** `err`, `crit`, `alert` et `emerg`.

::: pourquoi
Dans un sélecteur syslog, `facilité.sévérité` signifie « cette sévérité **et
toutes les plus graves** ». Comme les sévérités vont de 0 (`emerg`) à 7
(`debug`), « plus grave » veut dire « de numéro inférieur ou égal ». `local5.err`
(`err` = 3) attrape donc 3, 2, 1 et 0.

Les trois modificateurs à connaître :

| Écriture | Sens |
|---|---|
| `local5.err` | `err` et plus grave |
| `local5.=err` | **exactement** `err` |
| `local5.!err` | tout sauf `err` et plus grave |

Le cas vraiment utile en production est `*.*;auth,authpriv.none`, qu'on lit
« tout, sauf ce qui vient des facilités d'authentification » : la sévérité
spéciale `none` exclut une facilité d'une règle générale. C'est ce qui évite que
les traces de `sudo` et de `sshd` se retrouvent en double dans `/var/log/syslog`
et dans `/var/log/auth.log`.
:::

---

**Q16.6** — *Envoi vers `lab-ops` avec accusé de réception.*

**Réponse : b)** `*.*  @@10.10.10.14:10514`

::: pourquoi
La notation vient de sysklogd et rsyslog l'a conservée : un `@` = UDP, deux `@@`
= TCP. Rien de plus, rien de moins, et c'est un des rares cas où un caractère
doublé change complètement les garanties de livraison.

* UDP (`@`) : envoi et oubli. Aucun accusé, aucune retransmission. Si le
  collecteur est arrêté, les messages partent dans le vide et **personne ne le
  signale**. Le seul avantage est qu'un collecteur lent ne bloque jamais
  l'émetteur. Datagrammes limités à ~1 Ko sur de vieilles implémentations, d'où
  les messages tronqués.
* TCP (`@@`) : connexion établie, accusés au niveau transport. Si le collecteur
  tombe, rsyslog détecte la rupture, met en file et retente.

Attention : TCP seul ne suffit pas à ne rien perdre. La file par défaut est en
mémoire et limitée ; au-delà, rsyslog jette. La configuration complète est dans
le corrigé de L16.2 : `queue.type="LinkedList"`, `queue.filename`,
`queue.saveOnShutdown="on"`, `action.resumeRetryCount="-1"`.
:::

---

**Q16.7** — *`Ignoring factura because of bad file mode`.*

**Réponse : c)** le fichier de **configuration** est trop permissif.

::: pourquoi
Depuis la version 3.15, `logrotate` refuse de lire un fichier de configuration
qui pourrait être modifié par un autre utilisateur que root. La raison est
évidente dès qu'on y pense : une directive `postrotate` s'exécute **en root**.
Un fichier de conf accessible en écriture au groupe `adm` serait une élévation
de privilèges triviale.

Les deux refus possibles, avec leur message exact :

```text
Ignoring factura because of bad file mode - must be 0644 or 0444.
Ignoring factura because the file owner is wrong (should be root or user
with uid 0).
```

Le piège tient à ce que ce refus n'apparaît **que** dans la sortie de debug ou
dans le journal du service `logrotate`, et qu'il ne fait pas échouer la commande :
`logrotate` continue avec les autres fichiers et sort en 0. Le fichier ne tourne
jamais, la supervision « logrotate a réussi » reste au vert, et on découvre le
problème quand `/var` est plein — c'est exactement BF16.1.

Correctif : `sudo chmod 0644 /etc/logrotate.d/factura` et
`sudo chown root:root /etc/logrotate.d/factura`.
:::

::: piege
a) et d) confondent le fichier **de configuration** avec le fichier **de log**.
Le log, lui, peut appartenir à qui on veut : c'est justement à ça que servent
`su` et `create`. La limite de 2 Go de b) n'existe pas.
:::

---

**Q16.8** — *Le défaut structurel de `copytruncate`.*

**Réponse : b)** les lignes écrites entre la copie et la troncature sont perdues.

::: pourquoi
`copytruncate` procède en deux appels système distincts, sans verrou entre les
deux :

```text
1. copie du contenu de app.log vers app.log.1     (peut durer des secondes)
2. truncate(app.log, 0)                            (instantané)
```

Tout ce que l'application écrit **pendant** l'étape 1 est copié ou non selon
l'instant, puis détruit par l'étape 2. Sur un fichier de 800 Mo, la copie prend
plusieurs secondes : à 200 lignes par seconde, ce sont des milliers de lignes qui
disparaissent — et ce sont précisément les lignes du moment de la rotation, donc
souvent celles qu'on cherchera.

Le mode normal (`create`) n'a pas ce problème parce qu'il utilise `rename()`, qui
est **atomique** : l'inode ne change pas, le descripteur de l'application continue
de pointer dessus, aucune ligne n'est perdue. Le prix à payer est que
l'application continue d'écrire dans l'ancien fichier jusqu'à ce qu'on lui dise
de rouvrir — d'où le `postrotate` avec un `SIGHUP` ou un `systemctl reload`.
:::

---

**Q16.9** — *`copytruncate` sur un fichier ouvert sans `O_APPEND`.*

**Réponse : d)** le fichier réapparaît énorme, rempli d'octets nuls.

::: pourquoi
Un descripteur de fichier porte une **position** (offset). Sans `O_APPEND`,
chaque `write()` écrit à la position courante puis l'avance ; le processus ne
consulte jamais la taille réelle du fichier. Après un `truncate(fd, 0)`, le
fichier fait 0 octet mais la position du processus, elle, vaut toujours
800 000 000. Le prochain `write()` écrit donc à l'octet 800 000 000, et POSIX
impose que la zone non écrite entre la fin du fichier et cette position soit
lue comme des zéros. Le noyau crée un **trou** : le fichier a une taille
apparente énorme et n'occupe presque aucun bloc.

La signature au diagnostic, à connaître :

```console
$ ls -lh acces.log          # taille apparente
-rw-r----- 1 factura adm 801M sept. 18 14:03 acces.log
$ du -h acces.log           # blocs réellement alloués
236K    acces.log
$ wc -l acces.log
4000 acces.log
```

Avec `O_APPEND`, le noyau repositionne à la fin **du fichier** avant chaque
écriture, de façon atomique : après la troncature, l'écriture suivante repart à
l'octet 0 et il n'y a pas de trou. C'est pour cette raison que toute bibliothèque
de log sérieuse ouvre en mode append. C'est BF16.4.
:::

---

**Q16.10** — *Charge 6.02 sur 4 vCPU, `96.0 id`, `2.0 wa`.*

**Réponse : a)** des processus sont bloqués en `D`.

::: pourquoi
La charge moyenne de Linux n'est pas une mesure de CPU. C'est la moyenne
exponentielle du nombre de tâches dans l'état `TASK_RUNNING` (`R`) **plus**
celles dans l'état `TASK_UNINTERRUPTIBLE` (`D`). Ce second terme est une
particularité de Linux : les UNIX historiques ne comptaient que les runnables.

Une charge de 6 avec 96 % d'`idle` ne peut donc venir que de tâches en `D` :
attente disque, attente NFS, attente d'un périphérique. Le `wa` à 2 % ne
contredit rien — `wa` mesure le temps où **le CPU** n'avait rien d'autre à faire
qu'attendre une E/S, pas le nombre de tâches bloquées. Un NFS injoignable donne
souvent `wa = 0` et une charge de 40.

La commande qui tranche en cinq secondes :

```bash
ps -eo state,pid,comm,wchan:24 | awk '$1 ~ /^D/'
```

`wchan` donne la fonction noyau où chaque tâche est bloquée : on y lit
`nfs_wait_bit_killable`, `wait_on_page_bit`, `io_schedule`…
:::

::: piege
Le seuil « charge > nombre de cœurs = saturation » n'est valable **que** pour une
charge à dominante CPU. Sur une machine à dominante E/S, il ne veut rien dire.
D'où la règle du module : la charge est un signal d'appel, jamais une conclusion.
Et en entretien, savoir que `D` compte dans la charge est un marqueur fort.
:::

---

**Q16.11** — *`free 0,3Gi`, `available 6,1Gi` sur 7,7 Gi.*

**Réponse : c)** non, 6,1 Gi sont disponibles.

::: pourquoi
`free` (la colonne) compte la mémoire qui n'est **rien du tout** : ni page de
processus, ni cache. Sur un système sain, cette valeur tend naturellement vers
zéro, parce que le noyau utilise toute la mémoire inoccupée comme cache de
pages : c'est gratuit et récupérable instantanément. De la mémoire libre est de
la mémoire gaspillée.

`available` est un calcul du noyau (`MemAvailable` dans `/proc/meminfo`, ajouté
en 2014) qui estime ce qu'une nouvelle application pourrait obtenir **sans
provoquer de swap** : la mémoire libre, plus la part du cache et des dalles
réellement récupérables, moins les réserves basses du noyau. C'est la seule
valeur à regarder.

La règle d'ops tient en une ligne : **on alerte sur `available` en pourcentage du
total, jamais sur `free`**. Un seuil raisonnable est 15 %, à croiser avec
`si`/`so` de `vmstat`.
:::

---

**Q16.12** — *`st 22.4` dans `top`.*

**Réponse : b)** *steal time* : l'hyperviseur donne du CPU à d'autres VM.

::: pourquoi
Le *steal time* est le temps pendant lequel le vCPU de ta machine virtuelle était
**prêt à exécuter du code mais n'a pas eu de CPU physique**, parce que
l'hyperviseur l'a donné à quelqu'un d'autre. Le noyau invité le sait parce que
l'horloge paravirtualisée lui permet de comparer le temps écoulé au temps
réellement exécuté.

Ce que ça implique, et c'est le point important : **le problème n'est pas dans ta
VM**. Aucune optimisation applicative ne le fera baisser. Les causes sont chez
l'hôte : surallocation de vCPU, voisin bruyant, quota CPU appliqué à la VM
(`cpulimit` chez un hébergeur). Un `st` durablement au-dessus de 5 % justifie un
ticket à l'équipe virtualisation ou à l'hébergeur ; au-dessus de 20 %, la VM
tourne à moins de 80 % de sa capacité nominale.

C'est une métrique à collecter systématiquement sur un parc virtualisé, et elle
n'existe pas sur du matériel physique. Sur Proxmox, on la regarde en face du
*CPU pressure* de l'hôte.
:::

---

**Q16.13** — `%util 99.8`*, `r_await`* `340.00`*, `aqu`*`-sz 28.4`*, 20 IOPS.*

**Réponse : a)** le disque est le goulot d'étranglement.

::: pourquoi
Il faut lire les quatre chiffres ensemble, aucun ne suffit seul :

* `%util` = proportion du temps où au moins une requête était en cours. Il est à
  99,8 : le disque n'a pas eu une milliseconde de repos.
* `aqu-sz` = longueur moyenne de la file. 28 requêtes en attente en permanence,
  c'est un embouteillage.
* `r_await` (et `w_await`) = temps total moyen d'une requête, **file d'attente comprise**.
  340 ms, alors qu'un SSD SATA répond en 0,1 à 1 ms et un disque mécanique en
  5 à 15 ms.
* 20 IOPS pour tout ça : le débit utile est ridicule au regard de l'attente.

Traduction : chaque lecture applicative prend un tiers de seconde. Toute
requête qui touche ce disque est bloquée, les processus s'accumulent en `D`, la
charge grimpe et le CPU reste à l'`idle`. C'est le scénario du Q16.10.

Nuance à connaître : sur les périphériques multi-files (NVMe, RAID, SAN),
`%util` perd son sens — un NVMe à 100 % d'`util` peut encore absorber dix fois
plus de trafic, car il traite plusieurs requêtes en parallèle. Sur ces
supports, on juge sur `await` et sur le débit, pas sur `%util`.
:::

::: piege
b) inverse la lecture de `%util` : un disque « utilisé à 99,8 % » n'est pas
efficace, il est saturé. C'est une confusion fréquente en entretien avec le taux
d'utilisation d'un CPU, où 100 % peut être un régime nominal.
:::

---

**Q16.14** — *`err` ou pire, unité `nginx`, 14 h – 14 h 30, en JSON.*

**Réponse : a)**

```bash
journalctl -u nginx -p 3 --since 14:00 --until 14:30 -o json
```

::: pourquoi
Chaque morceau compte :

* `-p 3` équivaut à `-p err` : priorité 3 **et plus grave** (0 à 3). Une borne
  seule est toujours un « et plus grave ».
* `--since 14:00` sans date : journalctl comprend « aujourd'hui à 14:00 ». Même
  chose pour `--until`. Les formats acceptés sont nombreux : `"2026-09-18
  14:00:00"`, `yesterday`, `today`, `-1h`, `"1 hour ago"`, `@1758196800`.
* `-o json` : une entrée JSON par ligne, donc directement exploitable par
  `jq -c` ou par un pipeline. `json-pretty` est fait pour l'œil humain, pas pour
  un script.

b) est piégeuse : `-p` `err..emerg` est accepté (journalctl remet l' intervalle dans l'ordre
), mais `--today` n'existe pas (`unrecognized option`) et rien
ne borne la fin de la fenêtre — seul `--until` le fait. c) et
d) inventent une syntaxe qui n'existe pas.
:::

---

**Q16.15** — *`si 0 so 0` mais 1,8 Gi de swap `used`.*

**Réponse : d)** des pages inactives ont été parquées, sans activité actuelle.

::: pourquoi
Il faut distinguer un **stock** d'un **débit**.

`swap used` est un stock : la quantité de pages actuellement stockées sur le
périphérique de swap. Elle ne diminue pas toute seule, même quand la pression
mémoire disparaît : tant qu'un processus ne redemande pas une page parquée, le
noyau n'a aucune raison de la ramener. Une machine peut donc afficher 1,8 Gi de
swap `used` pendant des mois, sans le moindre impact.

`si` et `so` (`vmstat`) sont des débits : pages entrées et sorties **par
seconde**. C'est ce qui coûte, parce que chaque page échangée est une E/S disque
sur le chemin critique d'un processus. Un `so` soutenu est le symptôme du
*thrashing* : la machine passe son temps à déplacer de la mémoire au lieu de
travailler.

Règle d'alerte : ne jamais alerter sur `swap used`. Alerter sur `si`/`so` non
nuls en régime établi, ou sur `available` bas. Corollaire : `swapoff -a` pour
« nettoyer » une machine est une mauvaise idée — ça force le rapatriement de
1,8 Gi d'un coup et peut déclencher l'OOM killer.
:::

---

**Q16.16** — *Sur quoi déclencher une astreinte de nuit.*

**Réponse : b)** `latence p99 de /api/paiement > 2 s pendant 5 minutes`.

::: pourquoi
C'est la distinction entre **symptôme** et **cause**, et c'est ce que le module
veut ancrer.

a), c) et d) sont des mesures de ressources. Elles décrivent l'état d'une
machine, pas l'état du service rendu. Un CPU à 85 % peut être parfaitement
nominal (c'est même souhaitable sur un serveur de calcul), une charge de 4 sur
4 cœurs est normale, 70 % de mémoire utilisée est un régime sain. Alerter
dessus produit du bruit, et le bruit produit des astreintes qu'on ignore —
la vraie panne passe alors inaperçue.

b) est un symptôme utilisateur : quelqu'un, en ce moment, n'arrive pas à payer.
Trois qualités à noter :

* c'est une mesure **côté service**, pas côté ressource ;
* c'est un **percentile** (p99) et pas une moyenne — une moyenne à 200 ms peut
  cacher 1 % de requêtes à 30 s ;
* il y a une **durée** (5 minutes), ce qui filtre les pics transitoires.

Les mesures de ressources ne disparaissent pas pour autant : on les collecte,
on les affiche sur les tableaux de bord, et on s'en sert pour **diagnostiquer**
une fois réveillé. Alerter sur les symptômes, diagnostiquer par les causes.
:::

---

**Q16.17** — `sar -u` *: `Cannot`* `open /var/log/sysstat/sa18`*, alors que `sar`* `-u 1 3` *fonctionne.*

**Réponse : b)** `sar -u` sans intervalle relit le fichier du jour, lequel n'existe pas tant que la collecte n'est pas
activée; avec un intervalle, `sar` mesure en direct.

::: pourquoi
`sysstat` a deux visages qu'on confond systématiquement :

* `sar -u 1 3` : trois relevés d'une seconde, **en direct**, sans toucher aux
  fichiers d'historique. Fonctionne toujours.
* `sar -u` (sans intervalle) : relit l'historique du jour, stocké dans
  `/var/log/sysstat/saDD` (Ubuntu) ou `/var/lib/sa/saDD` (Rocky). Ce fichier est
  alimenté par `sysstat-collect.timer`, qui n'est armé que si le paquet est
  activé.

Le message d'erreur cité est donc celui de la seconde forme. Sur Ubuntu, la
collecte est désactivée à l'installation — c'est le piège du §16.1 :

```bash
sudo sed -i 's/^ENABLED=.*/ENABLED="true"/' /etc/default/sysstat
sudo systemctl enable --now sysstat
systemctl list-timers 'sysstat*'
```

L'intérêt de l'historique est considérable : il permet de répondre à « que se
passait-il à 3 h 12 cette nuit » sur une machine où personne ne regardait.
`sar -f /var/log/sysstat/sa17 -s 03:00 -e 04:00 -u` relit un jour précis.
:::

---

**Q16.18** — *`node_filesystem_avail_bytes` dans la grille USE.*

**Réponse : c)** la saturation de la ressource « système de fichiers ».

::: pourquoi
La méthode USE demande, pour **chaque ressource**, trois choses :

| Lettre | Question | Exemple côté disque |
|---|---|---|
| U — utilisation | quelle part du temps la ressource est-elle occupée | `%util` |
| S — saturation | y a-t-il de la file d'attente ou un remplissage | file d'E/S, espace restant |
| E — erreurs | la ressource signale-t-elle des échecs | erreurs SMART, E/S en échec |

Pour un système de fichiers, l'« utilisation » est le débit d'E/S ; la
« saturation », c'est le fait de manquer de place — au-delà de 100 % de
remplissage, plus rien ne fonctionne. `node_filesystem_avail_bytes` (et son
pendant `node_filesystem_files_free` pour les inodes) répond à cette question-là.

En pratique on ne l'utilise jamais brute : on la met en rapport avec
`node_filesystem_size_bytes` pour obtenir un pourcentage, et on la combine avec
`predict_linear()` dans Prometheus pour alerter sur « ce disque sera plein dans
4 heures » plutôt que sur un seuil fixe. Un `/var` à 85 % stable depuis six mois
n'intéresse personne ; un `/var` à 60 % qui monte de 5 points par heure, si.
:::

---

## 16.4 Quiz — questions ouvertes

**QO16.1** — *Trajet d'un `print("erreur base")` jusqu'à `syslog.2.gz`.*

**Réponse attendue** — sept étapes, et trois endroits où l'on perd des messages.

```text
1. l'application écrit sur son fd 1 (stdout)
2. systemd a remplacé ce fd par un socket vers journald (StandardOutput=journal)
3. journald reçoit -> _TRANSPORT=stdout, PRIORITY=6 par défaut
4. journald applique le limiteur de débit, puis écrit dans
   /run/log/journal/... ou /var/log/journal/...
5. si ForwardToSyslog=yes, journald relaie vers le socket
   /run/systemd/journal/syslog
6. rsyslog (module imuxsock/imjournal) applique ses règles
   -> *.*;auth,authpriv.none  -/var/log/syslog
7. logrotate renomme syslog -> syslog.1 -> syslog.2.gz (compression differee)
```

::: pourquoi
Les points de perte, dans l'ordre où on les rencontre en production :

* **étape 3** : la sortie standard n'est pas structurée. Une ligne sans préfixe
  `<N>` arrive en `PRIORITY=6` (`info`), y compris si l'application la destinait
  à stderr — stdout et stderr arrivent tous deux en `_TRANSPORT=stdout`, sans priorité plus
  grave. D'où le conseil : préfixer `<3>` en tête de ligne, ou utiliser
  la bibliothèque systemd.
* **étape 4** : le limiteur de débit (`RateLimitBurst`). Messages jetés, un
  compte rendu `Suppressed N messages` est écrit. C'est BF16.3.
* **étape 4 bis** : le plafond de taille (`SystemMaxUse`). Là, rien n'est perdu
  au présent : ce sont les **anciens** messages qui sont supprimés.
* **étape 6** : une règle rsyslog avec `stop`, ou un `& ~` hérité, écarte
  silencieusement une facilité entière.
* **étape 7** : `copytruncate`, et les générations au-delà de `rotate N` qui
  sont simplement effacées.

Les valeurs de `_TRANSPORT` à connaître : `stdout` (sortie d'un service),
`syslog` (via `/dev/log`), `journal` (API native `sd_journal_print`), `kernel`
(`/dev/kmsg`), `audit` (auditd).
:::

::: piege
Beaucoup croient encore que rsyslog lit `/dev/log`. Sur Ubuntu 24.04, `/dev/log`
est un lien symbolique vers `/run/systemd/journal/dev-log` : c'est **journald**
qui écoute. rsyslog reçoit ensuite de journald. Conséquence : un message limité
par journald n'atteint jamais rsyslog, et couper journald coupe tout.
:::

**QO16.2** — *`/var` plein cette nuit : démarche en dix minutes.*

**Réponse attendue** — quatre temps : mesurer, identifier, libérer, prévenir.

```bash
# 1. de quoi parle-t-on : espace ou inodes ?
df -h /var
df -i /var                       # le /var « plein » à 40 % d'espace

# 2. qui occupe la place, du plus gros au plus petit
du -xh --max-depth=1 /var | sort -h | tail -15
du -xh --max-depth=1 /var/log | sort -h | tail -15

# 3. fichiers supprimés mais encore ouverts (df et du ne s'accordent pas)
lsof +L1 2>/dev/null | awk '$5=="REG" && $8<1 {print}' | head

# 4. le journal systemd, qui n'est pas un fichier .log
journalctl --disk-usage

# 5. les 10 plus gros fichiers, tous types confondus
find /var -xdev -type f -size +100M -printf '%s\t%p\n' 2>/dev/null \
  | sort -rn | head -10
```

::: pourquoi
L'ordre n'est pas décoratif. `df -i` d'abord parce qu'un `/var` « plein » avec
40 % d'espace libre est un épuisement d'inodes : aucun ménage de gros fichiers
n'y changera rien, il faut supprimer des **milliers de petits** fichiers (spool
de mail, sessions PHP, cache).

L'étape 3 traite l'écart le plus déroutant : un fichier supprimé dont un
processus garde le descripteur reste alloué sur le disque jusqu'à la fermeture
du descripteur. `df` le compte, `du` ne le voit plus. La réponse n'est pas de
chercher le fichier — il n'existe plus — mais de recharger le processus qui le
tient (`systemctl reload nginx`), ou de vider le descripteur :
`: > /proc/<pid>/fd/3`.

Remise en service, par ordre de sécurité croissante :

```bash
sudo journalctl --rotate && sudo journalctl --vacuum-size=200M
sudo logrotate -f /etc/logrotate.conf
sudo find /var/log -name '*.gz' -mtime +30 -delete
```

Ne jamais faire : `rm` sur un fichier de log actif. On le vide
(`sudo truncate -s 0 /var/log/gros.log`), sinon l'espace n'est pas rendu tant
que le processus tient le descripteur.

Prévention : une alerte sur l'espace **et** sur les inodes, à 85 %, plus une
vérification que logrotate traite bien tous les fichiers (`logrotate -d` sans
ligne `Ignoring`).
:::

**QO16.3** — *`create` contre `copytruncate`.*

**Réponse attendue**

| | `create` (défaut) | `copytruncate` |
|---|---|---|
| mécanisme | `rename()` puis `open()` | `copy()` puis `truncate()` |
| inode | nouveau fichier, nouvel inode | **même inode**, même fichier |
| fd de l'appli | pointe encore sur l'ancien inode | continue de fonctionner |
| pertes | aucune | les lignes écrites pendant la copie |
| action requise | `SIGHUP`/`reload` en `postrotate` | aucune |

::: pourquoi
`rename()` sur le même système de fichiers est une opération atomique de
l'annuaire : elle change le nom, jamais l'inode. L'application qui détient un
descripteur sur cet inode n'en sait rien et continue d'écrire dedans — dans
`app.log.1`, désormais. D'où le `postrotate` qui lui demande de rouvrir. Tant
que le `SIGHUP` n'est pas arrivé, on ne perd rien : les lignes vont dans le
fichier tourné.

`copytruncate` existe pour le cas, et seulement pour le cas, où l'application ne
sait **pas** rouvrir son fichier : pas de gestionnaire `SIGHUP`, pas de
`reopen`, pas de redémarrage possible sans coupure de service. Logiciel
propriétaire, binaire ancien, JVM mal configurée. C'est un pis-aller assumé, pas
un réglage par défaut.

La bonne réponse en 2026, quand on a le choix : ne pas faire tourner le fichier
du tout, écrire sur la sortie standard et laisser journald s'en charger. C'est
le modèle des conteneurs, et il supprime toute la classe de problèmes.
:::

**QO16.4** — *Charge 12 sur 8 vCPU : trois scénarios.*

**Réponse attendue**

| Scénario | Signature | Commande qui tranche |
|---|---|---|
| saturation CPU réelle | `us`+`sy` proches de 100, `id` ~0 | `vmstat 1 5` |
| blocage E/S | `id` élevé, beaucoup de `D`, `await` haut | `iostat -xz 1` |
| vol de CPU (hyperviseur) | `st` > 5, charge haute, `us` bas | `top` (ligne `%Cpu`) |

::: pourquoi
Un quatrième cas mérite d'être cité en entretien : une avalanche de processus
courts. La charge grimpe parce que la file des runnables est longue, alors
qu'aucun processus ne consomme durablement. `vmstat 1` montre alors une colonne
`r` élevée avec un `cs` (changements de contexte) énorme. C'est typiquement un
`fork` en boucle dans un script, ou un pool de workers mal dimensionné.

La démarche générale, en trois commandes et moins d'une minute :

```bash
vmstat 1 5                         # r, b, wa, st : la répartition
ps -eo state,pid,comm | awk '$1~/^D/' | wc -l   # combien de bloqués
iostat -xz 1 3                     # si b > 0, où ça bloque
```

Ce que l'on ne fait pas : conclure sur la seule valeur de la charge. Elle dit
« quelque chose attend », jamais « quoi ».
:::

**QO16.5** — *`free` contre `available`.*

**Réponse attendue** — « `free` est la mémoire que personne n'utilise, pas même
le noyau comme cache. `available` est ce qu'une nouvelle application peut obtenir
sans faire swapper le système : le libre, plus le cache récupérable, moins les
réserves du noyau. Sur une machine de 16 Go, 200 Mo de `free` est normal et même
souhaitable : le reste sert de cache de pages, ce qui accélère toutes les
lectures. Je ne m'inquiète que si `available` descend sous 10-15 % du total, ou
si `vmstat` montre du `si`/`so` soutenu. »

::: pourquoi
Le calcul de `MemAvailable` par le noyau, pour ceux qui veulent le détail :
mémoire libre, moins la réserve basse (`low watermark`), plus le cache
de pages et les dalles récupérables (`SReclaimable`), chacun diminué du plus petit de deux termes : sa moitié ou la réserve basse. Le noyau suppose ainsi qu'une petite part du cache est indispensable et que la
libérer coûterait des relectures.

L'erreur symétrique existe aussi : croire qu'`available` haut garantit tout.
Une application qui réserve d'un coup 8 Go sur une machine qui en a 6 de
disponibles déclenchera l'OOM killer, quelle que soit la jolie valeur affichée.
:::

::: piege
La version de `free` compte : sur les systèmes antérieurs à procps-ng 3.3.10,
il n'y avait pas de colonne `available` et la ligne `-/+ buffers/cache` jouait
ce rôle. On trouve encore des runbooks qui parlent de cette ligne : ils sont
obsolètes depuis 2014.
:::

**QO16.6** — *4 000 lignes par seconde en rafale : le limiteur.*

**Réponse attendue** — mécanisme, effet, trois remèdes.

::: pourquoi
Mécanisme : journald compte les messages **par unité** (par cgroup) dans une
fenêtre fixe de `RateLimitIntervalSec` (30 s par défaut). Au-delà de
`RateLimitBurst` messages (10 000 par défaut) dans la fenêtre, tout le reste est
**jeté** jusqu'à la fin de la fenêtre, et journald écrit une entrée
`Suppressed N messages from <cgroup>`. Le burst effectif est modulé à la hausse
ou à la baisse selon l'espace libre de `/var`.

Ce qui est perdu : les messages de la **fin** de la fenêtre. Autrement dit,
exactement ceux qui suivent l'événement déclencheur. Une application qui part en
boucle d'erreur perd donc la partie la plus intéressante de sa trace.

Trois remèdes, du meilleur au moins bon :

1. **Réduire le volume à la source** : le niveau `debug` n'a rien à faire en
   production. Aucun coût, aucun risque.
2. **Relever le quota pour ce service seulement**, via un drop-in d'unité :
   `LogRateLimitIntervalSec=0` ou `LogRateLimitBurst=50000`. La protection
   globale de la machine reste en place pour les autres services. C'est ce que
   demande BF16.3.
3. **Relever le quota globalement** dans `journald.conf`. Simple, et c'est le
   plus dangereux : on retire le garde-fou de toute la machine pour un seul
   service fautif.

À écarter : `Storage=none` (on ne journalise plus rien) et l'idée de « passer
par rsyslog pour contourner » — rsyslog reçoit de journald, donc il reçoit
déjà moins.
:::

**QO16.7** — *UDP ou TCP pour 40 serveurs.*

**Réponse attendue** — TCP, avec une file sur disque.

::: pourquoi
Comportement pendant les 30 secondes d'arrêt du collecteur :

* **UDP** : les datagrammes partent vers un port fermé. Au mieux un ICMP
  *port unreachable* revient et rsyslog l'ignore. Les 30 secondes de journaux de
  40 serveurs sont perdues, sans aucune trace nulle part. C'est précisément la
  fenêtre qui intéresse quand le collecteur est tombé à cause d'un incident
  général.
* **TCP** : la connexion se rompt, rsyslog met les messages en file et retente
  selon `action.resumeInterval`. Si la file est pleine, il jette — d'où
  l'importance de la configurer.

La configuration d'émission qui ne perd rien :

```rsyslog
action(type="omfwd"
       target="10.10.10.14" port="10514" protocol="tcp"
       queue.type="LinkedList"
       queue.filename="fwd_lab_ops"        # spool disque
       queue.maxdiskspace="1g"
       queue.saveOnShutdown="on"           # survit a un reboot
       action.resumeRetryCount="-1")       # retente indefiniment
```

`queue.filename` est la clé : sans elle, la file est purement en mémoire
(`queue.size` par défaut, quelques milliers de messages) et un arrêt du service
émetteur la perd. Avec elle, rsyslog écrit dans `/var/spool/rsyslog/` et
reprend là où il en était.

Pour aller plus loin en production : RELP (`omrelp`) ajoute un accusé applicatif
de bout en bout, que TCP seul ne garantit pas — TCP accuse la réception par la
pile réseau, pas l'écriture sur disque du collecteur. Et TLS (`gtls`) si les
journaux traversent un réseau non maîtrisé.
:::

**QO16.8** — *Signaux dorés et USE appliqués à un HTTP lent.*

**Réponse attendue**

Signaux dorés (côté service, dans cet ordre) :

1. **latence** p50/p95/p99 par route — et la latence des requêtes **en échec**
   séparément, sinon les 500 rapides font baisser la moyenne ;
2. **trafic** requêtes/s — la latence a-t-elle monté parce que le trafic a
   monté ?
3. **erreurs** taux de 5xx et de 4xx ;
4. **saturation** taille de la file d'attente applicative, workers occupés sur
   workers totaux, profondeur du pool de connexions base.

USE (côté ressource, pour trouver la cause) :

1. **CPU** : `%us`+`%sy` (utilisation), `r` de `vmstat` et `%st` (saturation),
   erreurs machine (rare) ;
2. **mémoire** : `available` (utilisation), `si`/`so` et compteur OOM
   (saturation), erreurs ECC ;
3. **disque** : `%util` (utilisation), `aqu-sz` et `await` (saturation),
   erreurs d'E/S dans `dmesg`.

::: pourquoi
L'ordre des deux grilles n'est pas interchangeable et c'est tout l'intérêt de la
question. Les signaux dorés répondent à « **est-ce que ça va mal, et pour qui ?** ».
USE répond à « **pourquoi ?** ». Commencer par USE conduit à passer une heure sur
un CPU à 70 % qui n'a jamais gêné personne.

Le quatrième signal doré, la saturation, est le pont entre les deux grilles :
c'est le seul qui soit à la fois une mesure de service (« ma file grandit ») et
un indicateur de ressource. C'est aussi le meilleur prédicteur : la file grandit
avant que la latence n'explose.
:::

**QO16.9** — *Quel format de log recommander à un développeur.*

**Réponse attendue** — cinq points, du point de vue de celui qui exploitera.

::: pourquoi
**1. Les niveaux, et leur contrat.** Un niveau est une promesse faite à
l'exploitant, pas une nuance de style :

| Niveau | Ce qu'il promet |
|---|---|
| `ERROR` | une action utilisateur a échoué, quelqu'un doit regarder |
| `WARN` | anomalie rattrapée, à surveiller si ça se répète |
| `INFO` | événement métier notable (démarrage, déploiement, commande passée) |
| `DEBUG` | trace de développement, **coupé en production** |

Le test qui tranche : si une ligne `ERROR` n'exige aucune action, ce n'est pas
une `ERROR`. Un service qui produit 400 `ERROR` par jour qu'on ignore a
désarmé son propre système d'alerte.

**2. Le format.** JSON sur une ligne, une ligne par événement. Il se filtre
(`jq`), se parse sans expression régulière fragile, et supporte des champs
métier sans casser les outils. Le texte reste acceptable s'il est **stable** :
horodatage en tête, puis niveau, puis champs `clé=valeur`.

**3. L'horodatage.** ISO 8601 avec fuseau explicite
(`2026-09-18T14:03:11.482+02:00`), en UTC si les machines sont réparties.
Précision milliseconde au minimum : deux événements dans la même seconde ne sont
plus ordonnables sinon. Ne jamais compter sur l'horodatage de journald pour
l'ordre applicatif : c'est l'heure de **réception**.

**4. La corrélation.** Un `request_id` (ou `trace_id`) généré à l'entrée, propagé
dans tous les logs de la requête **et** vers les services appelés via un en-tête
`X-Request-ID`. Sans lui, reconstituer une requête dans 40 000 lignes par minute
est impossible. C'est le champ le plus utile de tout le fichier.

**5. Ce qu'on n'écrit jamais.** Mots de passe, jetons, numéros de carte, cookies
de session, contenu d'un corps de requête non filtré. Les journaux sont copiés,
centralisés, sauvegardés et lus par des gens qui n'ont pas accès à la base : ils
sont un vecteur de fuite à part entière, et le RGPD s'y applique aussi.
:::

::: piege
Le piège inverse, moins évoqué : trop de champs. Un log JSON de 40 clés par
ligne multiplie le volume par cinq, sature le limiteur de débit et coûte cher en
stockage centralisé. Le bon réflexe est de journaliser ce qui sert au
diagnostic, et de mettre le reste dans des **métriques** — un compteur coûte
quelques octets par minute, une ligne de log coûte quelques centaines d'octets
par événement.
:::

---

## 16.5 Exercices guidés

**E16.1** — *30 dernières lignes de `ssh.service`, ISO, sans pager ; puis suivi ;
puis texte seul.*

```bash
journalctl -u ssh.service -n 30 -o short-iso --no-pager
journalctl -u ssh.service -f
journalctl -u ssh.service -n 30 -o cat --no-pager
```

::: pourquoi
`-o cat` n'affiche que le champ `MESSAGE` : c'est le format à utiliser quand on
veut rediriger vers `grep`, `awk` ou un comptage, parce qu'il supprime les
colonnes qui décaleraient les champs. `--no-pager` est indispensable dès qu'on
scripte : sans lui, `journalctl` lance `less` et un script s'arrête en attendant
une touche. La variable `SYSTEMD_PAGER=cat` produit le même effet globalement.

Sur Ubuntu 24.04, l'unité s'appelle `ssh.service` ; `sshd.service` est un alias.
Sous Rocky 9, c'est `sshd.service`.
:::

**E16.2** — *`warning` ou pire, démarrage courant puis précédent.*

```bash
journalctl -p warning -b --no-pager
journalctl -p warning -b -1 --no-pager
# si la seconde echoue :
sudo mkdir -p /var/log/journal
sudo systemd-tmpfiles --create --prefix /var/log/journal
sudo systemctl restart systemd-journald
journalctl --list-boots
```

::: pourquoi
`-p warning` équivaut à `-p 4` et retient les priorités 0 à 4. `-b` sans argument
désigne le démarrage courant, `-b -1` le précédent, `-b <ID>` un démarrage
identifié par son `boot_id` (colonne de `--list-boots`).

L'échec de `-b -1` sur une machine fraîchement installée est presque toujours la
persistance manquante — voir Q16.1. Note que l'historique ne commence qu'à
partir du moment où tu actives la persistance : les démarrages antérieurs sont
définitivement perdus.
:::

**E16.3** — *Rendre le journal persistant, mesurer, puis les gros fichiers de
`/var/log`.*

```bash
sudo mkdir -p /var/log/journal
sudo systemd-tmpfiles --create --prefix /var/log/journal
sudo systemctl restart systemd-journald
sudo journalctl --flush
# ou : Storage=persistent dans /etc/systemd/journald.conf.d/10-persistant.conf

ls -ld /var/log/journal /var/log/journal/*/
journalctl --disk-usage
du -sh /var/log/journal

sudo find /var/log -xdev -type f -printf '%s\t%p\n' \
  | sort -rn | head -5 | numfmt --field=1 --to=iec
sudo du -xh --max-depth=1 /var/log | sort -h
```

::: pourquoi
La vérification qui compte est `ls -ld /var/log/journal/*/` : le sous-répertoire
porte le `machine-id` (`cat /etc/machine-id`), et les fichiers `.journal` y sont.
Tant que le journal est volatile, ce répertoire est vide et tout est dans
`/run/log/journal/`.

`journalctl --disk-usage` et `du -sh` ne donnent pas toujours le même chiffre :
le premier ne compte que les fichiers de journal valides, le second compte tout
le contenu du répertoire. Un écart important signale des fichiers corrompus —
`journalctl --verify` les identifie.

Sur la seconde partie : `-printf '%s\t%p\n'` évite d'appeler `ls` ou `stat` une
fois par fichier — `find` a déjà les métadonnées, le tri se fait sur des octets
bruts et `numfmt` n'humanise qu'à la fin, sur cinq lignes. Sur un `/var/log` de
plusieurs dizaines de milliers de fichiers, c'est un facteur dix.

`-xdev` (et `du -x`) empêche de traverser un point de montage : sans lui, un
`/var/log` monté séparément ou un bind-mount fausse complètement le résultat.
Le tri de `du` se fait avec `sort -h`, qui comprend `4,0K < 12M < 1,2G` ; un
`sort -n` classerait `1,2G` avant `12M`.
:::

**E16.4** — *Trois messages de test, retrouvés par facilité puis par tag.*

```bash
logger -p local4.info "demarrage du traitement nocturne"
logger -p local4.err -t factura-test "echec de connexion a la base"
logger -p local4.notice -f /etc/hostname

journalctl SYSLOG_FACILITY=20 -n 10 -o short-iso --no-pager
journalctl -t factura-test -n 10 --no-pager
```

::: pourquoi
`local4` = 16 + 4 = **20**. Le tag (`-t`) alimente `SYSLOG_IDENTIFIER` ; sans
`-t`, `logger` utilise le nom de l'utilisateur courant, ce qui rend les messages
introuvables quand on les cherche par nom de programme.

`logger -f fichier` envoie **une entrée par ligne** du fichier. Utile pour
réinjecter un fichier de log dans le journal, à condition de se souvenir que les
horodatages seront ceux de l'injection, pas ceux du fichier.

Autres options utiles : `logger --journald` (envoi de champs structurés
arbitraires), `logger -n 10.10.10.14 -P 10514 -T` (envoi direct en TCP à un
collecteur, sans passer par le démon local — très pratique pour tester L16.2).
:::

**E16.5** — *Messages émis par l'exécutable `sudo`, dernières 24 h.*

```bash
journalctl _COMM=sudo --since -24h --no-pager
journalctl _COMM=sudo --since -24h -o json --no-pager \
  | jq -r '[(._AUDIT_LOGINUID // "?"), .MESSAGE] | @tsv'
_UID vaudrait 0 : sudo est setuid root. L'utilisateur d'origine est dans _AUDIT_LOGINUID (UID de connexion)
et, en clair, en tête de MESSAGE (mathieu : TTY=pts/1 ; ... ; COMMAND=...).
```

::: pourquoi
`_COMM` est le nom de l'exécutable tel que le noyau le connaît (15 caractères
maximum), et c'est un champ **de confiance** : journald le remplit lui-même à
partir du processus émetteur, l'application ne peut pas le falsifier. Les champs
préfixés d'un `_` (`_PID`, `_UID`, `_GID`, `_COMM`, `_EXE`, `_CMDLINE`,
`_SYSTEMD_UNIT`) sont tous dans ce cas. Ceux sans préfixe (`MESSAGE`,
`SYSLOG_IDENTIFIER`, `PRIORITY`) viennent de l'émetteur et sont donc
manipulables.

C'est la raison pour laquelle on filtre un audit de sécurité sur `_COMM` ou
`_SYSTEMD_UNIT`, jamais sur le tag.
:::

**E16.6** — *Dernière entrée `err` en JSON, puis extraction `jq`.*

```bash
journalctl -p err -n 1 -o json-pretty --no-pager

journalctl -p err -n 1 -o json --no-pager \
  | jq -r '"pid=\(._PID) unite=\(._SYSTEMD_UNIT) cmd=\(._CMDLINE)"'
```

::: pourquoi
Deux pièges de `jq` sur le JSON de journalctl :

* les champs commencent par `_`, ce qui est légal en JSON mais impose
  `._PID` (et non `.PID`) ; s'ils contenaient un tiret il faudrait
  `.["CODE-FILE"]` ;
* un champ absent donne `null` et casse une concaténation. `jq -r '._PID // "?"'`
  fournit une valeur de repli.

`-o json` produit une entrée par ligne (JSON Lines) : c'est le format à envoyer
dans un pipeline. `-o json-pretty` indente et n'est lisible que par un humain.
Pour limiter le volume, `--output-fields=MESSAGE,_PID,_SYSTEMD_UNIT` restreint
les champs extraits à la source, ce qui change tout sur un journal de plusieurs
gigaoctets.
:::

**E16.7** — *Nombre d'entrées par unité, top 10.*

```bash
journalctl -b -o json --no-pager --output-fields=_SYSTEMD_UNIT \
  | jq -r '._SYSTEMD_UNIT // "(hors unite)"' \
  | sort | uniq -c | sort -rn | head -10
```

::: pourquoi
`--output-fields` divise le temps d'exécution par cinq ou dix sur un gros
journal : journald ne désérialise que le champ demandé. Sans `jq`, une variante
plus rapide encore utilise le format `export` :

```bash
journalctl -b -o export --no-pager \
  | awk -F= '/^_SYSTEMD_UNIT=/ {print $2}' \
  | sort | uniq -c | sort -rn | head -10
```

Le résultat est la première chose à regarder quand le journal grossit trop :
dans 90 % des cas, une seule unité produit 80 % du volume, et le correctif est
un niveau de log à baisser, pas un disque à agrandir.
:::

**E16.8** — *Plafonner le journal à 500 Mo durablement.*

```bash
journalctl --disk-usage                       # avant

sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/10-taille.conf >/dev/null <<'EOF'
[Journal]
SystemMaxUse=500M
SystemKeepFree=1G
EOF
sudo systemctl restart systemd-journald

sudo journalctl --rotate
sudo journalctl --vacuum-size=500M
journalctl --disk-usage                       # apres
```

::: pourquoi
Le fichier `/etc/systemd/journald.conf` est livré par le paquet et sera écrasé à
la mise à jour : on passe toujours par un drop-in dans `journald.conf.d/`.
`systemd-analyze cat-config systemd/journald.conf` affiche la configuration
résultante, fragments compris — c'est la commande qui prouve ce qui s'applique
réellement.

Le redémarrage de journald applique la contrainte pour l'**avenir** : la
réduction effective n'a lieu qu'à la prochaine rotation. D'où le
`--rotate` suivi de `--vacuum-size` pour obtenir l'effet immédiatement (voir
Q16.3 : le vacuum ne touche pas le fichier actif).

`SystemKeepFree` est le garde-fou complémentaire : même si `SystemMaxUse`
autorise 500 Mo, journald s'arrête d'écrire pour laisser 1 Go libre sur la
partition. C'est ce qui empêche le journal de participer à la saturation de
`/var`.
:::

**E16.9** — *Facilité `local6` vers `metier.log`, et uniquement là.*

```bash
sudo tee /etc/rsyslog.d/30-factura-metier.conf >/dev/null <<'EOF'
local6.*    /var/log/factura/metier.log
& stop
EOF
sudo systemctl restart rsyslog

logger -p local6.info "facture 2026-0042 emise"
sudo tail -1 /var/log/factura/metier.log
sudo grep -c 'facture 2026-0042' /var/log/syslog    # doit repondre 0
```

::: pourquoi
Deux points de mécanique.

Le `& stop` (syntaxe moderne ; l'ancienne était `& ~`) signifie « pour les
messages qui viennent d'être traités par la règle précédente, arrêter là ». Sans
lui, le message continue son chemin et sera **aussi** attrapé par la règle
`*.*;auth,authpriv.none -/var/log/syslog` de `50-default.conf`. C'est la
réponse à « et uniquement là ».

L'ordre de lecture compte : rsyslog lit `/etc/rsyslog.d/*.conf` par ordre
alphabétique, et les règles s'appliquent dans l'ordre. Un fragment nommé
`30-…` est lu **après** le `50-default.conf` d'Ubuntu ? Non : `30` vient avant
`50`, donc le `stop` s'applique bien avant la règle générale. Si le fragment
s'appelait `90-…`, le message serait déjà dans `syslog` et le `stop` arriverait
trop tard. Le numéro n'est pas décoratif.

Il faut aussi que rsyslog puisse écrire dans `/var/log/factura/` : il tourne en
`syslog:syslog` sur Ubuntu. Soit on lui donne le groupe `adm` sur le répertoire,
soit on ajoute `$FileOwner`/`$FileGroup` autour de la règle.
:::

**E16.10** — *Filtrer `factura-bruyant` côté rsyslog.*

```bash
sudo tee /etc/rsyslog.d/10-factura-bruyant.conf >/dev/null <<'EOF'
:programname, isequal, "factura-bruyant"   stop
EOF
sudo systemctl restart rsyslog

sudo systemctl start factura-bruyant
sleep 5
sudo grep -c factura-bruyant /var/log/syslog   # 0
journalctl -u factura-bruyant -n 5             # les messages sont la
```

::: pourquoi
La numérotation `10-` place le fragment **avant** toutes les règles d'écriture :
le `stop` est évalué en premier, le message est abandonné par rsyslog avant
d'avoir touché le moindre fichier ou la moindre action réseau. C'est ce qui
répond à « ni dans syslog ni dans les fichiers distants ».

Le filtre agit **uniquement sur rsyslog**. journald, lui, a déjà tout stocké :
`journalctl -u factura-bruyant` continue de tout montrer. C'est exactement
l'énoncé — on veut garder la trace localement et cesser de la propager.

Autres formes de filtre, selon ce dont on dispose :

```rsyslog
:programname, startswith, "factura-"  stop
:msg, contains, "trace debug interne"  stop
if $syslogfacility-text == "local7" and $syslogseverity == 7 then stop
```

La dernière est la plus propre quand c'est un **niveau** qui pose problème et non
un programme.
:::

**E16.11** — *Règle logrotate pour `app.log`, dry run puis rotation forcée.*

```bash
sudo tee /etc/logrotate.d/factura >/dev/null <<'EOF'
/var/log/factura/app.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 factura adm
    su root adm
}
EOF
sudo chmod 0644 /etc/logrotate.d/factura
sudo chown root:root /etc/logrotate.d/factura

sudo logrotate -d /etc/logrotate.d/factura      # dry run
sudo logrotate -f /etc/logrotate.conf           # rotation forcee
ls -l /var/log/factura/
```

::: pourquoi
`-d` implique `-v` et surtout **n'écrit rien**, pas même le fichier d'état. C'est
la seule façon de tester sans conséquence. La sortie se lit ligne à ligne :

```text
considering log /var/log/factura/app.log
  Now: 2026-09-18 14:20
  Last rotated at 2026-09-17 06:25
  log needs rotating
```

`-f` force la rotation même si le déclencheur n'est pas atteint, et il écrit,
lui. C'est la commande à utiliser pour valider un `postrotate` — jamais en
production sur un coup de tête, parce qu'elle consomme une génération.

Le couple `compress` + `delaycompress` mérite une phrase : sans
`delaycompress`, `app.log.1` est compressé immédiatement. Or un processus qui
détient encore le descripteur écrit toujours dedans, et on obtiendrait une
archive gzip corrompue. `delaycompress` laisse un tour de battement — d'où
`app.log.1` en clair et `app.log.2.gz` compressé.
:::

**E16.12** — *Prouver la perte de lignes de `copytruncate`.*

Terminal 1 :

```bash
sudo /opt/factura/bin/factura-ecrivain.py \
     --fichier /var/log/factura/test.log --periode 0.01
```

Terminal 2 :

```bash
sudo tee /etc/logrotate.d/test-copy >/dev/null <<'EOF'
/var/log/factura/test.log {
    size 1k
    rotate 2
    copytruncate
    missingok
}
EOF
sudo chmod 0644 /etc/logrotate.d/test-copy
sudo logrotate -f /etc/logrotate.d/test-copy

# derniere ligne avant rotation, premiere ligne apres
tail -1 /var/log/factura/test.log.1
head -1 /var/log/factura/test.log
```

::: pourquoi
La sortie attendue :

```console
$ tail -1 /var/log/factura/test.log.1
2026-09-18T14:31:07+0200 seq=1842 service=factura-acces etat=ok
$ head -1 /var/log/factura/test.log
2026-09-18T14:31:07+0200 seq=1849 service=factura-acces etat=ok
```

Six lignes se sont évaporées : elles ont été écrites après que `cp` a lu la fin
du fichier, et avant que `truncate()` ne soit appelé. Elles ne sont ni dans
l'archive, ni dans le nouveau fichier. Aucun message d'erreur nulle part.

Le trou est proportionnel au temps de copie : quelques lignes sur un fichier de
test, plusieurs milliers sur un fichier de 800 Mo. Pour amplifier le phénomène de
façon démonstrative, `--periode 0.001` sur un fichier de plusieurs centaines de
mégaoctets rend le trou impossible à rater.

Ne pas oublier de retirer `/etc/logrotate.d/test-copy` après l'exercice : un
fichier de test oublié dans `logrotate.d` est une source d'incident classique.
:::

**E16.13** — *Charge, ratio par cœur, puis `%iowait` calculé à la main.*

```bash
awk -v c="$(nproc)" '{printf "1min=%s 5min=%s 15min=%s coeurs=%d ratio=%.2f\n",
  $1, $2, $3, c, $1/c}' /proc/loadavg

lire() { awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8+$9, $6}' /proc/stat; }
read -r T1 W1 < <(lire); sleep 1; read -r T2 W2 < <(lire)
awk -v t1="$T1" -v w1="$W1" -v t2="$T2" -v w2="$W2" \
    'BEGIN {printf "iowait = %.2f %%\n", 100*(w2-w1)/(t2-t1)}'
vmstat 1 2 | tail -1
```

::: pourquoi
`/proc/loadavg` contient cinq champs :
`0.58 0.24 0.12 3/412 5294` — les trois moyennes, puis
`runnables/total de tâches`, puis le dernier PID attribué. Le quatrième champ
est intéressant en soi : un numérateur durablement élevé confirme une file de
runnables, un dénominateur qui explose signale une fuite de processus.

`nproc` respecte l'affinité CPU du processus appelant et les limites de cgroup —
contrairement à `grep -c ^processor /proc/cpuinfo`, qui compte les CPU de la
machine même quand le conteneur n'a droit qu'à deux. Sur une VM, les deux
coïncident ; dans un conteneur, non.

Lecture du ratio : en dessous de 1, aucun processus n'attend en moyenne ; à 1,
la machine est pleine ; au-dessus de 2, il y a deux fois plus de demandeurs que
de ressources — à condition que la charge soit à dominante CPU (Q16.10).

Sur la seconde partie : les compteurs de `/proc/stat` sont **cumulés depuis
le démarrage**, exprimés en centièmes de seconde (`USER_HZ` = 100, quel que soit le `CONFIG_HZ` du noyau). Une seule lecture
donne donc la moyenne depuis le boot, ce qui ne sert à rien : sur une machine
qui tourne depuis trois mois, l'incident d'hier est invisible. Il faut **deux
relevés et une différence**.

L'ordre des colonnes de la ligne `cpu ` :
`user nice system idle iowait irq softirq steal guest guest_nice`. `iowait` est
donc le sixième champ de la ligne, `$6` pour `awk` puisque `$1` vaut `cpu`.

C'est exactement ce que fait `vmstat` en interne, et c'est aussi la raison pour
laquelle `vmstat 1` affiche une **première ligne aberrante** : elle donne la
moyenne depuis le boot. On la jette toujours, d'où le `tail -1` sur `vmstat 1 2`.

Avertissement sur `iowait` : c'est le temps où le CPU était inactif **alors
qu'au moins une E/S était en cours**. Si un autre processus occupe le CPU
pendant l'attente, le temps est compté en `user` et `iowait` reste bas. Un
`iowait` faible ne prouve donc jamais l'absence de problème disque.
:::

**E16.14** — *Le processus qui fait le plus d'E/S, puis de défauts de page.*

```bash
sudo pidstat -d 1 5 | sort -k4 -rn | head -5
sudo pidstat -r 1 5 | sort -k4 -rn | head -5
```

::: pourquoi
`pidstat -d` donne `kB_rd/s`, `kB_wr/s` et `iodelay` par processus : c'est la
réponse directe à « qui martyrise le disque », là où `iostat` dit seulement
« le disque souffre ». `iodelay` (en jiffies) est le temps pendant lequel le
processus a été bloqué en attente d'E/S — c'est lui qui désigne la victime.

`pidstat -r` donne `minflt/s` et `majflt/s`. La distinction est essentielle :

* **minor fault** : la page est en mémoire, il manquait juste l'entrée de table
  de pages. Coût quasi nul, un processus qui démarre en produit des milliers.
* **major fault** : la page doit être lue **sur le disque** (swap ou fichier
  mappé). Coût de l'ordre de la milliseconde. Un `majflt/s` soutenu est le
  symptôme d'un manque de mémoire, même si `free` paraît correct.

`iotop -o` est l'alternative interactive ; `pidstat` a l'avantage d'être
scriptable et de figurer dans `sysstat`, déjà installé pour `sar`.
:::

**E16.15** — *Activer l'historique `sysstat` et relire.*

```bash
sudo sed -i 's/^ENABLED=.*/ENABLED="true"/' /etc/default/sysstat
sudo systemctl enable --now sysstat
systemctl list-timers 'sysstat*' --no-pager

sar -u                                  # CPU moyen du jour
sar -d -s 09:00:00 -e 11:00:00          # activite disque sur la plage
sar -f /var/log/sysstat/sa17 -r         # memoire d'un jour precis
```

::: pourquoi
Deux unités travaillent ensemble : `sysstat-collect.timer` déclenche
`sa1` toutes les 10 minutes (il écrit un relevé dans `/var/log/sysstat/saDD`), et
`sysstat-summary.timer` produit le résumé quotidien `sarDD` à 23 h 53. La
granularité de 10 minutes se règle dans
`/etc/systemd/system/sysstat-collect.timer.d/` — à 1 minute sur une machine
qu'on surveille de près, ce qui reste très peu coûteux.

Les fichiers sont nommés par jour du mois : `sa17` est le 17 du mois courant,
écrasé le 17 du mois suivant. `HISTORY` dans `/etc/sysstat/sysstat` contrôle la
rétention (7 jours par défaut sur Debian/ Ubuntu, 28 dans la version amont).
:::

::: rhel
Sous Rocky 9, les fichiers sont dans `/var/lib/sa/` et la collecte passe aussi par `sysstat-collect.timer`, armé par `sudo systemctl enable --now sysstat`. Il n'y a pas
de fichier `/etc/default/sysstat` ni de variable `ENABLED` : la configuration est dans
`/etc/sysconfig/sysstat`.
:::

**E16.16** — *`node_exporter` : trois métriques précises.*

```bash
sudo apt install -y prometheus-node-exporter
ss -tlnp | grep 9100

curl -s http://localhost:9100/metrics | grep -E '^node_load1 '
curl -s http://localhost:9100/metrics | grep '^node_memory_MemAvailable_bytes'
curl -s http://localhost:9100/metrics \
  | grep '^node_filesystem_avail_bytes' | grep 'mountpoint="/"'
```

::: pourquoi
Le format d'exposition est du texte ligne à ligne :

```text
# HELP node_load1 1m load average.
# TYPE node_load1 gauge
node_load1 0.58
node_filesystem_avail_bytes{device="/dev/sda2",fstype="ext4",\
mountpoint="/"} 1.1610112e+10
```

Les lignes `# HELP` et `# TYPE` sont des métadonnées ; le reste est
`nom{étiquettes} valeur`. Les étiquettes (`mountpoint`, `device`, `cpu`, `mode`)
sont ce qui permet de distinguer plusieurs séries du même nom — d'où le second
`grep` sur `mountpoint="/"`, sans lequel on récupère aussi `/boot`, les
`tmpfs` et les montages de conteneurs.

Les valeurs sont en notation scientifique parce que Prometheus manipule des
flottants 64 bits. `1.1610112e+10` octets = 11,6 Go.

Nom de l'unité sur Ubuntu : `prometheus-node-exporter.service`. Le binaire
officiel du projet, lui, s'installe en général sous `node_exporter.service` —
d'où le double test dans `check_M16_05.sh`.
:::

---

## 16.6 Labs

### **L16.1** — *Ticket INC-4102 : des 502 entre 14 h et 14 h 20.*

**Procédure complète**

```bash
cat ~/lab16/inc-4102/fenetre.txt          # DEBUT= et FIN= du rejeu

# 1. persistance
sudo mkdir -p /var/log/journal
sudo systemd-tmpfiles --create --prefix /var/log/journal
sudo systemctl restart systemd-journald
journalctl --list-boots

# 2. la fenetre, en ISO, dans un fichier
journalctl -u factura-api.service -o short-iso --no-pager \
  --since "2026-09-18 14:02:00" --until "2026-09-18 14:06:00" \
  > ~/lab16/inc-4102/journal-api.log

# 3. tout ce qui est err ou pire sur la fenetre, toutes unites
journalctl -p err --no-pager -o short-iso \
  --since "2026-09-18 14:02:00" --until "2026-09-18 14:06:00"

# 4. cote noyau
journalctl -k --no-pager --since "2026-09-18 14:02:00" \
  | grep -i 'out of memory'

# 5. histogramme des 502 par minute
sudo awk '$9==502 {split($4,a,":"); print a[2]":"a[3]}' \
  /var/log/nginx/access.log | sort | uniq -c

# 6. les trois premieres erreurs en JSON
journalctl -u factura-api.service -p err -o json --no-pager \
  --since "2026-09-18 14:02:00" | head -3 \
  | jq -r '[(.__REALTIME_TIMESTAMP|tonumber/1000000|todate), ._PID,
            .MESSAGE, ._CMDLINE] | @tsv'

# 7. y a-t-il eu des messages supprimes ?
journalctl --since "2026-09-18 14:02:00" -g 'Suppressed' --no-pager
```

**Cause racine attendue** : le traitement par lots `factura-exports` démarre et
réclame les 20 connexions du pool applicatif. Les requêtes web n'en obtiennent
plus, attendent 30 s, et nginx renvoie `502`. La consommation mémoire d'un
worker dérive en parallèle et le noyau finit par le tuer (OOM).
Le batch partage le pool de l'API au lieu d'avoir le sien.

::: pourquoi
Ce qu'il faut avoir compris, au-delà des commandes :

**La chronologie se construit à partir de deux sources qui ne s'accordent pas.**
L'horodatage de journald est celui de la **réception** par le démon ; celui de
`access.log` est écrit par nginx à la **fin** de la requête. Une requête qui a
mis 30 s avant de renvoyer un 502 apparaît dans `access.log` 30 s après avoir
commencé — c'est pour cette raison que la dégradation semble commencer plus tard
côté nginx que côté application. Sur une chronologie d'incident, ce décalage
s'explique, il ne se gomme pas.

**L'ordre d'apparition des erreurs désigne le coupable.** Ici : d'abord
`pool de connexions sature` (niveau `warning`), puis `attente d'une connexion
libre`, puis seulement `echec d'obtention d'une connexion apres 30s`
(niveau `err`). Le premier symptôme est un `warning`, pas une erreur : c'est la
raison pour laquelle un filtre `-p err` seul manque le début de l'incident. On
descend toujours d'un cran (`-p warning`) une fois la fenêtre identifiée.

**L'OOM n'est pas la cause, c'est une conséquence.** La trace noyau est
spectaculaire et attire l'œil, mais elle arrive **après** les timeouts. Confondre
les deux conduit à « ajouter de la RAM », qui n'aurait rien réglé.

**L'absence de trace est une information.** L'étape 7 ne trouve rien : aucun
message n'a été supprimé par le limiteur, donc les journaux de la fenêtre sont
complets et le raisonnement tient. Si elle avait trouvé quelque chose, toute la
chronologie aurait été suspecte. C'est une vérification à faire systématiquement
avant de conclure sur des journaux.
:::

::: piege
Le réflexe qui fait perdre une heure : lancer `journalctl -u factura-api` sans
borne et lire 40 000 lignes. On borne **d'abord** la fenêtre, on filtre **ensuite**
la priorité, on descend **enfin** dans le détail. Et on écrit l'extraction dans
un fichier : une enquête qu'on ne peut pas rejouer n'est pas une enquête.

Deuxième piège : `--since "14:00"` sur une machine dont le fuseau n'est pas celui
de l'incident. `timedatectl` avant toute chose, et l'horodatage ISO
(`-o short-iso`) qui affiche le décalage explicitement.
:::

---

### **L16.2** — *Centralisation `lab-web` → `lab-ops`.*

**Sur `lab-ops` (10.10.10.14)**

```bash
sudo mkdir -p /var/log/central
sudo chown syslog:adm /var/log/central
sudo chmod 0750 /var/log/central

sudo tee /etc/rsyslog.d/05-collecteur.conf >/dev/null <<'EOF'
module(load="imtcp")

template(name="RangementDistant" type="string"
  string="/var/log/central/%HOSTNAME%/%PROGRAMNAME:::secpath-replace%.log")

ruleset(name="reception-reseau") {
    action(type="omfile" dynaFile="RangementDistant"
           fileOwner="syslog" fileGroup="adm"
           fileCreateMode="0640" dirCreateMode="0750"
           createDirs="on")
    stop
}

input(type="imtcp" port="10514" ruleset="reception-reseau")
EOF

sudo systemctl restart rsyslog
ss -tlnp | grep 10514

sudo ufw allow from 10.10.10.0/24 to any port 10514 proto tcp
```

**Sur `lab-web` (10.10.10.11)**

```bash
sudo tee /etc/rsyslog.d/10-factura-bruyant.conf >/dev/null <<'EOF'
:programname, isequal, "factura-bruyant"   stop
EOF

sudo tee /etc/rsyslog.d/90-forward.conf >/dev/null <<'EOF'
action(type="omfwd"
       target="10.10.10.14" port="10514" protocol="tcp"
       queue.type="LinkedList"
       queue.filename="fwd_lab_ops"
       queue.spoolDirectory="/var/spool/rsyslog"
       queue.maxdiskspace="1g"
       queue.saveOnShutdown="on"
       action.resumeRetryCount="-1"
       action.resumeInterval="5")
EOF

sudo systemctl restart rsyslog
logger -p local4.notice "test centralisation depuis lab-web"
```

**Preuve de résilience**

```bash
# sur lab-ops
sudo systemctl stop rsyslog
# sur lab-web
for i in 1 2 3 4 5; do logger -p local4.notice "coupure msg $i"; done
# sur lab-ops
sudo systemctl start rsyslog
sleep 5
sudo grep -c 'coupure msg' /var/log/central/lab-web/*.log   # doit valoir 5
```

::: pourquoi
**Pourquoi un `ruleset` dédié.** Sans lui, les messages reçus par `imtcp`
traversent l'ensemble des règles par défaut de `lab-ops` : ils finissent dans
`/var/log/syslog` local, mélangés aux messages de la machine. Un `input()` avec
`ruleset=` crée un chemin de traitement séparé — les messages réseau ne voient
que les actions du ruleset, et le `stop` final les empêche de retomber dans les
règles globales. C'est la réponse au point 3 de l'énoncé.

**Pourquoi `secpath-replace`.** `%PROGRAMNAME%` vient du message, donc d'une
machine distante, donc d'une source non fiable. Un programme nommé
`../../etc/cron.d/x` écrirait un fichier hors de `/var/log/central`. La propriété
`secpath-replace` remplace les `/` par des `_` et neutralise l'attaque. C'est la
réponse à l'encadré « un collecteur syslog ouvert est une porte d'entrée » : le
filtrage réseau protège du trafic non autorisé, `secpath-replace` protège du
trafic autorisé mais malveillant.

**Pourquoi le port 10514 et pas 514.** Un port inférieur à 1024 exige des
privilèges à l'ouverture — rsyslog les a, mais on évite par principe. Et 514 est
le port historique **UDP** : le laisser fermé évite qu'un équipement mal
configuré déverse en UDP sans qu'on le remarque.

**Pourquoi la file sur disque.** `queue.filename` fait passer la file en mode
« disk-assisted » : tant que le collecteur répond, tout reste en mémoire (rapide) ;
dès qu'il ne répond plus, rsyslog déborde sur `/var/spool/rsyslog` et
`saveOnShutdown` garantit que le spool survit à un redémarrage de l'émetteur.
`action.resumeRetryCount="-1"` signifie « retente indéfiniment » : sans lui,
rsyslog abandonne l'action après quelques échecs et **jette** silencieusement.

**Pourquoi le filtre bruyant en `10-`.** Les fragments sont lus par ordre
alphabétique et les règles s'évaluent dans l'ordre. `10-` est évalué avant le
`90-forward.conf` : le `stop` s'applique donc avant l'action de forward, et rien
ne part sur le réseau. Inverser les numéros suffirait à tout casser.
:::

::: piege
Trois erreurs classiques sur ce lab :

* `createDirs="on"` oublié : rsyslog n'écrit rien et ne le dit que dans son
  propre journal (`journalctl -u rsyslog`), jamais dans un fichier.
* droits de `/var/log/central` : rsyslog tourne en `syslog:syslog` sur Ubuntu.
  Un répertoire `root:root 0700` donne une centralisation silencieusement vide.
* AppArmor : sur Ubuntu, le profil de rsyslog autorise `/var/log/**`. Écrire
  ailleurs (`/srv/logs`, par exemple) provoque un refus visible uniquement dans
  `dmesg | grep DENIED`. C'est la première chose à regarder quand « tout est
  correct mais rien ne s'écrit ».
:::

---

### **L16.3** — *Rotation propre des journaux de `factura`.*

**Configuration attendue**

```bash
sudo tee /etc/logrotate.d/factura >/dev/null <<'EOF'
/var/log/factura/app.log /var/log/factura/erreurs.log {
    daily
    maxsize 100M
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 factura adm
    su root adm
    sharedscripts
    postrotate
        /usr/bin/systemctl kill -s HUP factura-api.service 2>/dev/null || true
    endscript
}

/var/log/factura/acces.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    create 0640 factura adm
    su root adm
    dateext
    dateformat -%Y%m%d
    postrotate
        /usr/bin/systemctl kill -s HUP factura-ecrivain.service \
            2>/dev/null || true
    endscript
}
EOF
sudo chown root:root /etc/logrotate.d/factura
sudo chmod 0644 /etc/logrotate.d/factura
```

**Vérification et rotation**

```bash
sudo lsof /var/log/factura/*.log          # qui tient quoi
# ou sans lsof :
sudo ls -l /proc/*/fd 2>/dev/null | grep factura

sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -A5 factura
sudo logrotate -f /etc/logrotate.conf
sudo logrotate -f /etc/logrotate.conf     # deux fois pour voir le .2.gz

stat -c '%i %n' /var/log/factura/app.log /var/log/factura/app.log.1
ls -l /var/log/factura/
sudo grep factura /var/lib/logrotate/status
```

::: pourquoi
`su root adm`, la ceinture de sécurité. Si le répertoire
des logs est inscriptible par un groupe autre que root (ou par tous), logrotate refuse de le traiter : `error: skipping "/var/log/factura/app.log" because parent directory has insecure permissions (...) Set "su" directive in config file ...`. La
directive `su <user> <group>` lui dit sous quelle identité opérer sur ce bloc. Ici le répertoire est en `factura:adm` `0750`, le contrôle ne se déclenche pas encore; `su` rend le bloc robuste le jour où quelqu'un passe le répertoire en `0770` pour le groupe `adm`.

**`sharedscripts` change le nombre d'exécutions.** Par défaut, `postrotate`
s'exécute **une fois par fichier tourné** — avec deux fichiers dans le bloc, le
service recevrait deux `SIGHUP`. `sharedscripts` regroupe : un seul appel après
que tous les fichiers du bloc ont tourné. C'est le point 3 de l'énoncé, et c'est
ce qui évite de recharger nginx quinze fois d'affilée en production.

**`systemctl kill -s HUP` plutôt qu'un PID.** Un PID écrit en dur devient faux
au premier redémarrage du service, et un `kill $(cat /run/x.pid)` échoue
silencieusement si le fichier PID est périmé — pire, il peut tuer un processus
sans rapport qui a récupéré le numéro. `systemctl kill` vise le cgroup de
l'unité : toujours juste, toujours au bon processus.

`daily` **et `maxsize`** `100M` **ensemble.** Les deux déclencheurs cohabitent : logrotate
tourne le fichier si le jour a changé **ou** si la taille dépasse 100 Mo. C'est
ce qu'on veut en production — un rythme régulier, plus un garde-fou contre la
rafale. Surtout pas `size 100M` : `size` est exclusif des intervalles de temps (la dernière directive l'emporte), `daily` serait ignoré. Ne pas confondre non plus avec `minsize` ( « au
rythme prévu, mais seulement si la taille dépasse »). Et `maxsize` n'est évalué qu'au passage de logrotate, une fois par jour avec le timer par défaut.

**Vérifier l'inode prouve le mécanisme.** Après rotation avec `create`,
`app.log.1` porte l'inode de l'ancien `app.log`, et `app.log` en a un nouveau.
C'est le `rename()` du Q16.8, et c'est la démonstration que l'application écrit
encore dans l'ancien inode tant qu'elle n'a pas reçu son `SIGHUP`.

**Pourquoi pas `copytruncate` ici.** L'application réagit à `SIGHUP` : elle sait
rouvrir. Utiliser `copytruncate` reviendrait à accepter des pertes de lignes sans
aucune contrepartie. On y serait contraint seulement si l'application ne savait
ni rouvrir ni être redémarrée sans coupure — cas d'un binaire propriétaire.
:::

::: piege
`/var/lib/logrotate/status` (Ubuntu) ou `/var/lib/logrotate/logrotate.status` (Rocky) est
l'endroit où logrotate mémorise la date de dernière rotation de **chaque
fichier**. Deux conséquences que l'on découvre douloureusement :

* supprimer cette ligne fait re-tourner le fichier à la prochaine exécution,
  même s'il vient de tourner ;
* restaurer une vieille sauvegarde de ce fichier peut déclencher quatorze
  rotations d'un coup et effacer tout l'historique.

Et un `logrotate -d` n'écrit **jamais** dans ce fichier : c'est ce qui rend le
dry run totalement sûr.
:::

---

### **L16.4** — *Collecte maison et rapport quotidien.*

**`/opt/factura/bin/collecte-metriques.sh`**

```bash
#!/usr/bin/env bash
# collecte-metriques.sh — un releve par execution, en CSV.
set -euo pipefail

CSV="${CSV:-/var/log/factura/metriques.csv}"
# partition/disque sous / (traverse LVM : ubuntu-vg -> sda3)
DISQUE="${DISQUE:-$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" | head -1)}"
COEURS=$(nproc)

# --- CPU : deux releves de /proc/stat, jamais le cumule depuis le boot.
# Les compteurs sont cumulatifs en jiffies : une lecture unique donnerait
# la moyenne depuis le demarrage, inutilisable pour detecter un pic.
lire_cpu() { awk '/^cpu /{print $2,$3,$4,$5,$6,$7,$8,$9}' /proc/stat; }
read -r u1 n1 s1 i1 w1 q1 sq1 st1 < <(lire_cpu)
sleep 1
read -r u2 n2 s2 i2 w2 q2 sq2 st2 < <(lire_cpu)
tot=$(( (u2+n2+s2+i2+w2+q2+sq2+st2) - (u1+n1+s1+i1+w1+q1+sq1+st1) ))
pct() { awk -v d="$1" -v t="$tot" 'BEGIN{printf "%.1f", t?100*d/t:0}'; }
US=$(pct $(( (u2+n2) - (u1+n1) )))
SY=$(pct $(( s2 - s1 )))
WA=$(pct $(( w2 - w1 )))
ST=$(pct $(( st2 - st1 )))

# --- charge
read -r L1 _ _ _ _ < /proc/loadavg
RATIO=$(awk -v l="$L1" -v c="$COEURS" 'BEGIN{printf "%.2f", l/c}')

# --- memoire (en Mo) et swap (Kio/s)
MEMDISPO=$(awk '/^MemAvailable:/{printf "%d", $2/1024}' /proc/meminfo)
read -r SI SO < <(vmstat 1 2 | tail -1 | awk '{print $7, $8}')

# --- disque : %util et await (max de r_await, w_await) du disque systeme
if command -v iostat >/dev/null 2>&1; then
  read -r UTIL AWAIT < <(iostat -xz 1 2 "$DISQUE" 2>/dev/null \
    | awk -v d="$DISQUE" '$1==d {u=$NF; a=($6>$12?$6:$12)}
                          END{print u+0, a+0}')
else
  UTIL=-1; AWAIT=-1
fi

# --- processus bloques en E/S
BLOQ=$(ps -eo state= | grep -c '^D' || true)

HOR=$(date -Is)
if [ ! -s "$CSV" ]; then
  echo "horodatage,charge1,ratio_charge,us,sy,wa,st,mem_dispo_mo,\
swap_in,swap_out,disque_util,disque_await,proc_d" > "$CSV"
fi
printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
  "$HOR" "$L1" "$RATIO" "$US" "$SY" "$WA" "$ST" "$MEMDISPO" \
  "$SI" "$SO" "$UTIL" "$AWAIT" "$BLOQ" >> "$CSV"
```

**`/opt/factura/bin/rapport-quotidien.sh`** (structure attendue)

```bash
#!/usr/bin/env bash
set -euo pipefail
CSV="${CSV:-/var/log/factura/metriques.csv}"
S_RATIO=${S_RATIO:-1.5}; S_WA=${S_WA:-20}; S_MEM=${S_MEM:-15}
S_UTIL=${S_UTIL:-90};    S_ST=${S_ST:-5};  S_D=${S_D:-3}
MEMTOT=$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo)

[ -s "$CSV" ] || { echo "aucune donnee dans $CSV" >&2; exit 1; }

echo "# Rapport d'exploitation — $(hostname -s) — $(date +%F)"
echo
awk -F, -v OFS=' | ' 'NR>1 {n++} END {
  printf "Periode : %s relevés\n", n}' "$CSV"

echo
echo "## Statistiques"
echo
echo "| Metrique | min | moy | max |"
echo "|---|---|---|---|"
for i in 2 4 6 7 8 11; do
  awk -F, -v c="$i" 'NR==1 {nom=$c; next}
    {v=$c+0; if (n++==0||v<mn) mn=v; if (v>mx) mx=v; s+=v}
    END {printf "| %s | %.2f | %.2f | %.2f |\n", nom, mn, s/n, mx}' "$CSV"
done

echo
echo "## À surveiller"
echo
awk -F, -v r="$S_RATIO" -v w="$S_WA" -v st="$S_ST" -v u="$S_UTIL" \
        -v d="$S_D" -v m="$MEMTOT" -v pm="$S_MEM" 'NR>1 {
  if ($3+0 > r)          printf "- %s charge/coeur = %s\n", $1, $3
  if ($6+0 > w)          printf "- %s %%wa = %s\n", $1, $6
  if ($7+0 > st)         printf "- %s %%st = %s (hyperviseur)\n", $1, $7
  if ($8+0 < m*pm/100)   printf "- %s memoire dispo = %s Mo\n", $1, $8
  if ($11+0 > u)         printf "- %s disque util = %s%%\n", $1, $11
  if ($13+0 > d)         printf "- %s %s processus en D\n", $1, $13
}' "$CSV"
```

::: pourquoi
**Le point technique central du lab est le delta CPU.** `/proc/stat` accumule
des jiffies depuis le boot. Sur une machine démarrée il y a trois mois, un pic
de 100 % de CPU pendant dix minutes déplace la moyenne cumulée de 0,02 point :
il est **invisible**. Toute métrique CPU exige deux relevés et une soustraction.
C'est vrai de `/proc/stat`, de `/proc/diskstats`, des compteurs réseau de
`/proc/net/dev`, et de toutes les métriques Prometheus suffixées `_total`.

**`mpstat` et `vmstat` jettent leur première ligne pour la même raison.** D'où
`vmstat 1 2 | tail -1` et `iostat -xz 1 2` : la première itération est le
cumulé, la seconde est le delta sur une seconde. Une erreur très fréquente est
d'écrire `vmstat | tail -1`, qui renvoie la moyenne depuis le boot.

**L'en-tête écrit une seule fois** (`[ ! -s "$CSV" ]`) : un CSV avec une ligne
d'en-tête tous les dix relevés casse tout outil d'analyse, et ce n'est visible
qu'au moment où on en a besoin.

**Le seuil mémoire est un pourcentage, pas une valeur absolue.** 500 Mo
disponibles, c'est confortable sur une machine de 2 Go et alarmant sur une
machine de 64 Go. Tous les seuils de ce type se rapportent à la capacité.

**Conclure sur la ressource limitante** est l'exercice le plus difficile, et le
plus proche du métier. La grille :

| Signature | Ressource limitante |
|---|---|
| `us+sy` proches de 100, `wa` bas, ratio > 1 | CPU |
| `wa` haut, `%util` ~100, `await` haut, proc en `D` | E/S |
| `mem_dispo` bas **et** `swap_out` non nul | mémoire |
| `st` haut, le reste normal | l'hyperviseur, rien à faire dans la VM |
:::

::: piege
L'extraction avec `awk` sur `iostat` est fragile : le nombre de
colonnes a changé entre sysstat 11 et 12 (ajout de `d/s`, `dkB/s` pour les
opérations `discard`, et de `f/s` pour les *flush*), et la colonne `await` unique a disparu au profit de `r_await` (`$6`) et `w_await` (`$12`). D'où `$NF` pour `%util` plutôt qu'un indice fixe, et un test `command -v iostat` pour dégrader proprement — c'est le point
6 du défi. En production, on préfère lire directement `/proc/diskstats`, dont le
format est stable depuis vingt ans.
:::

---

### **L16.5** — *`node_exporter` et la grille de lecture.*

```bash
sudo apt install -y prometheus-node-exporter
systemctl status prometheus-node-exporter

sudo mkdir -p /etc/systemd/system/prometheus-node-exporter.service.d
sudo tee /etc/systemd/system/prometheus-node-exporter.service.d/\
10-ecoute.conf >/dev/null <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/prometheus-node-exporter \
    --web.listen-address=10.10.10.14:9100
EOF
sudo systemctl daemon-reload
sudo systemctl restart prometheus-node-exporter
ss -tlnp | grep 9100

curl -s http://10.10.10.14:9100/metrics | grep -vc '^#'      # series
curl -s http://10.10.10.14:9100/metrics | grep '^# TYPE' | wc -l  # familles

sudo ufw allow from 10.10.10.0/24 to any port 9100 proto tcp
```

::: pourquoi
**Le `ExecStart=` vide n'est pas une coquetterie.** `ExecStart` est une directive
à valeurs multiples : un drop-in qui ajoute une seconde ligne obtient **deux**
commandes de démarrage, et systemd refuse l'unité
(`Service has more than one ExecStart= setting, which is only allowed for
Type=oneshot`). La ligne vide remet la liste à zéro avant de la redéfinir. Le
même mécanisme vaut pour `Environment=`, `ExecStartPre=` — mais pas pour les dépendances ( `After=`, `Wants=`), qu'un drop-in peut seulement compléter.

**Pourquoi restreindre l'écoute.** `/metrics` expose la liste des systèmes de
fichiers, des interfaces, des utilisateurs connectés, la version du noyau et les
noms des unités systemd. C'est une cartographie complète de la machine offerte
sans authentification. Le port 9100 sur `0.0.0.0` est un défaut de configuration
récurrent dans les audits.

**`_total` et les compteurs.** Un nom suffixé `_total` est un **compteur** :
monotone croissant, remis à zéro au redémarrage du processus. Sa valeur brute ne
veut rien dire — `node_network_receive_bytes_total 8.4e+11` signifie seulement
« depuis le boot ». Ce qui a du sens est sa **dérivée** :
`rate(node_network_receive_bytes_total[5m])`, soit des octets par seconde. Les
métriques sans suffixe (`node_load1`, `node_memory_MemAvailable_bytes`) sont des
**jauges** : elles montent et descendent, leur valeur instantanée a un sens.
Afficher un compteur brut sur un tableau de bord donne une droite qui monte
toujours et n'apprend rien.

**Correspondance attendue dans `use-golden.md` :**

| Signal doré | Métrique | Seuil proposé |
|---|---|---|
| latence | `http_request_duration_seconds` (applicatif) | p99 > 2 s / 5 min |
| trafic | `rate(http_requests_total[5m])` | pas de seuil, contexte |
| erreurs | `rate(http_requests_total{code=~"5.."}[5m])` | > 1 % / 5 min |
| saturation | `node_load1` / nb de CPU (`count` des |  |
|  | `node_cpu_seconds_total{mode=` |  |
|  | `"idle"}`), file applicative | > 2 / 15 min |

| Ressource | Utilisation | Saturation |
|---|---|---|
| CPU | `rate(node_cpu_seconds_total{mode!="idle"}[5m])` | `node_load1`, mode `steal` |
| mémoire | `1 - MemAvailable/MemTotal` | `node_vmstat_pswpout`, OOM |
| disque | `rate(node_disk_io_time_seconds_total[5m])` | `node_filesystem_avail_bytes` |

La colonne « erreurs » de USE, souvent oubliée :
`node_network_receive_errs_total`, les erreurs d'E/S du noyau (`dmesg`, SMART : `node_exporter` n'a pas de compteur d'erreurs disque par défaut), et le comptage
des entrées de journal de priorité `err`.

**Ce qui réveille la nuit** : la latence p99 et le taux de 5xx (symptômes
utilisateur), plus le système de fichiers qui sera plein dans moins de deux
heures (irréversible). Tout le reste attend le matin : un CPU à 90 % ou une
charge élevée ne gênent personne tant que le service répond.
:::

---

## 16.7 Break & Fix

### **BF16.1** — *`/var` plein, la rotation ne s'est jamais exécutée.*

**Diagnostic, dans l'ordre**

```bash
# 1. espace ou inodes ?
df -h /var ; df -i /var

# 2. qui occupe
sudo du -xh --max-depth=1 /var/log | sort -h | tail
sudo ls -lh /var/log/factura/

# 3. le timer tourne-t-il vraiment, et que dit-il ?
systemctl list-timers logrotate.timer --no-pager
systemctl status logrotate.service --no-pager
journalctl -u logrotate.service -n 30 --no-pager

# 4. LA commande qui donne la reponse
sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -i -B2 -A2 factura
```

Sortie révélatrice de l'étape 4 :

```text
Ignoring factura because of bad file mode - must be 0644 or 0444.
```

**Cause racine** : `/etc/logrotate.d/factura` est en mode `0666`. logrotate
refuse tout fichier de configuration modifiable par d'autres que root, l'ignore
en silence, **et sort quand même en 0**. Le timer s'exécute correctement toutes
les nuits, le service est vert, et aucun des fichiers de `/var/log/factura/` n'a
jamais tourné.

**Correctif**

```bash
sudo chmod 0644 /etc/logrotate.d/factura
sudo chown root:root /etc/logrotate.d/factura
sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -i ignoring   # plus rien

# rotation immediate, sans perdre le journal du jour
sudo logrotate -f /etc/logrotate.conf
ls -lh /var/log/factura/
df -h /var
```

Si l'espace reste insuffisant pour que la rotation elle-même s'effectue,
on libère d'abord de quoi travailler :

```bash
sudo journalctl --vacuum-size=200M
sudo find /var/log -name '*.gz' -mtime +30 -delete
```

::: pourquoi
Le mécanisme complet, qui est tout l'intérêt de la panne :

1. logrotate parcourt `/etc/logrotate.d/`. Pour chaque fichier, il vérifie le
   mode et le propriétaire **avant** de lire le contenu.
2. Un fichier trop permissif est écarté avec un message de niveau
   « information ». logrotate poursuit avec les autres.
3. Le code de retour global reste **0**. `systemctl status logrotate.service`
   affiche donc `Succeeded`, et `list-timers` montre des exécutions régulières.
4. Toute supervision qui se contente de « le job de rotation a réussi » est
   aveugle à ce problème. C'est le cœur du sujet.

La raison du contrôle est solide : un bloc `postrotate` s'exécute en root. Un
fichier de conf modifiable par le groupe `adm` serait une élévation de
privilèges en une ligne. logrotate préfère ne rien faire plutôt que d'exécuter
du code potentiellement injecté.

Pourquoi `truncate` plutôt que `rm` si l'on doit libérer de l'espace en urgence :
un fichier supprimé dont l'application détient le descripteur reste alloué
jusqu'à la fermeture. `df` ne bouge pas, `du` ne voit plus rien, et on tourne en
rond. `sudo truncate -s 0 /var/log/factura/app.log` rend l'espace immédiatement.
:::

::: piege
**Prévention à mettre en place**, et c'est la vraie question de l'exercice :

```bash
# controle a passer en supervision : aucune ligne ne doit sortir
sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -i 'ignoring\|error'
```

Plus une alerte sur l'âge du plus récent `.1` de chaque répertoire de logs, ou
sur la taille d'un fichier de log individuel (> 500 Mo = quelque chose ne
tourne pas). Surveiller « le job a réussi » ne suffit jamais : on surveille le
**résultat** attendu, pas l'exécution.
:::

---

### **BF16.2** — *Le journal systemd a mangé 4 Go.*

**Diagnostic**

```bash
df -h /var
sudo du -xh --max-depth=1 /var/log | sort -h | tail
journalctl --disk-usage
ls -lh /var/log/journal/*/ | head

# qui a produit tout ca ?
journalctl -b -o export --no-pager \
  | awk -F= '/^_SYSTEMD_UNIT=/ {print $2}' \
  | sort | uniq -c | sort -rn | head

# la configuration reellement appliquee, fragments compris
systemd-analyze cat-config systemd/journald.conf | grep -vE '^\s*#|^$'
```

**Cause racine** : un drop-in
`/etc/systemd/journald.conf.d/99-debug-heritage.conf` relève `SystemMaxUse` à
8 Go et désactive le limiteur de débit (`RateLimitIntervalSec=0`). Laissé après
une session de debug, il a supprimé les deux garde-fous. Un service verbeux a
alors rempli le journal jusqu'au nouveau plafond.

**Correctif**

```bash
# 1. retirer la configuration heritee
sudo rm /etc/systemd/journald.conf.d/99-debug-heritage.conf

# 2. poser une limite durable et raisonnable
sudo tee /etc/systemd/journald.conf.d/10-taille.conf >/dev/null <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=500M
SystemKeepFree=1G
MaxRetentionSec=30day
EOF
sudo systemctl restart systemd-journald

# 3. appliquer tout de suite
sudo journalctl --rotate
sudo journalctl --vacuum-size=500M
journalctl --disk-usage
df -h /var
```

::: pourquoi
**Pourquoi `rm -rf /var/log/journal/*` est une mauvaise idée même quand ça
marche**, en trois points :

1. Le répertoire `/var/log/journal/<machine-id>/` porte des droits particuliers
   (`root:systemd-journal`, mode `2755`, et des ACL posées par
   `systemd-tmpfiles` pour les groupes `adm` et `wheel`). Un `rm -rf` du contenu
   les laisse en place, mais un `rm -rf` du répertoire lui-même les détruit : le
   journal redevient volatile en silence et plus personne ne comprend pourquoi
   `-b -1` a cessé de marcher.
2. Le fichier **actif** est ouvert par journald. Le supprimer ne libère pas
   l'espace tant que le démon ne l'a pas refermé : `df` ne bouge pas, et on
   conclut à tort que le problème est ailleurs.
3. Ça ne traite rien. La configuration fautive est toujours là, le service
   verbeux aussi, et le disque se remplira de nouveau. `--vacuum-size` fait le
   même travail proprement, en respectant le cycle de vie des fichiers.

**Pourquoi `--rotate` avant `--vacuum-size`.** Le vacuum ne supprime que des
fichiers **archivés** (Q16.3). Si l'essentiel du volume est dans le fichier
actif, le vacuum ne rendra presque rien. `--rotate` ferme le fichier actif et
en ouvre un neuf : l'ancien devient éligible.

**Pourquoi `SystemKeepFree` en plus de `SystemMaxUse`.** Les deux contraintes
s'appliquent simultanément et journald retient la plus stricte. `SystemMaxUse`
plafonne le journal dans l'absolu ; `SystemKeepFree` garantit qu'il laissera
toujours 1 Go à `/var`, même si d'autres consommateurs arrivent. Sans la
seconde, un journal de 500 Mo sur une partition qui n'a plus que 200 Mo
participe encore à la saturation.
:::

::: piege
Chercher le coupable **avant** de purger. Une fois le vacuum passé, les données
qui auraient désigné le service verbeux ont disparu. L'ordre correct est :
comptage par unité, puis correction de la configuration, puis purge. Et on note
le résultat du comptage dans le ticket, parce que c'est la seule trace qui
restera.
:::

---

### **BF16.3** — *Les logs du service ont des trous.*

**Diagnostic**

```bash
# 1. constater le trou
journalctl -u factura-api -n 50 -o short-iso --no-pager

# 2. chercher la trace laissee par journald lui-meme
journalctl --since -10min -g 'Suppressed' --no-pager
journalctl -u systemd-journald --since -10min --no-pager | grep -i suppress

# 3. compter les messages perdus
journalctl --since -1h -g 'Suppressed' -o cat --no-pager \
  | grep -o '[0-9]* messages' | awk '{s+=$1} END {print s" messages perdus"}'

# 4. lire la configuration reellement appliquee
systemd-analyze cat-config systemd/journald.conf | grep -i ratelimit
```

Sortie révélatrice :

```text
2026-09-18T14:22:41+0200 lab-web systemd-journald[412]: Suppressed 4873
    messages from /system.slice/factura-api.service
```

**Cause racine** : le drop-in `/etc/systemd/journald.conf.d/90-limite-debit.conf`
fixe `RateLimitIntervalSec=30s` et `RateLimitBurst=50`. Le service émet
largement plus de 50 messages par fenêtre de 30 s : tout ce qui dépasse est
jeté, d'où les trous de 30 secondes.

**Correctif — relever le quota pour ce service seulement**

```bash
sudo mkdir -p /etc/systemd/system/factura-api.service.d
sudo tee /etc/systemd/system/factura-api.service.d/20-journal.conf \
  >/dev/null <<'EOF'
[Service]
LogRateLimitIntervalSec=30s
LogRateLimitBurst=20000
EOF
sudo systemctl daemon-reload
sudo systemctl restart factura-api

# verification : plus aucune suppression pour cette unite
sleep 60
journalctl --since -1min -g 'Suppressed.*factura-api' --no-pager
```

::: pourquoi
**Pourquoi la solution est au niveau de l'unité et pas global.** Les directives
`LogRateLimitIntervalSec=` et `LogRateLimitBurst=` existent dans les fichiers
d'unité depuis systemd 240 et surchargent le réglage global **pour ce cgroup
uniquement**. Relever `RateLimitBurst` dans `journald.conf` réglerait aussi le
symptôme, mais retirerait le garde-fou de toute la machine : le prochain service
qui part en boucle d'erreur remplirait `/var`, ce que le drop-in de durcissement
cherchait précisément à éviter. On corrige au plus près du fautif.

**Pourquoi `systemd-analyze cat-config` plutôt que `cat journald.conf`.** La
configuration effective est la somme de `/etc/systemd/journald.conf`, des
fragments de `journald.conf.d/`, et des valeurs par défaut compilées. Lire le
seul fichier principal — dont toutes les lignes sont commentées sur Ubuntu —
donne la fausse impression que « rien n'est configuré ». C'est une erreur de
diagnostic très commune, et elle vaut pour toute la famille `*.conf.d`.

**Ce qu'on recommande au développeur.** Le correctif technique ne traite que la
conséquence. Une ligne de journal par requête HTTP est un anti-patron : à
1 000 requêtes/s, c'est 1 000 lignes/s, soit des gigaoctets par jour et un coût
de centralisation réel. Le bon geste :

* niveau `INFO` pour les événements **métier** (une facture émise), pas pour
  chaque requête ;
* les requêtes se comptent avec une **métrique** (un compteur Prometheus), pas
  avec des lignes de log — quelques octets par minute au lieu de quelques
  centaines par événement ;
* on ne journalise chaque requête que pour les erreurs, ou par échantillonnage.
:::

::: piege
Le nombre affiché par `Suppressed N messages` est celui de la fenêtre écoulée,
pas un cumul. Pour le total sur une période, il faut additionner toutes les
occurrences — d'où le pipeline de l'étape 3. Et ces entrées sont produites par
`systemd-journald`, pas par le service fautif : `journalctl -u factura-api` seul
**ne les montre pas**. C'est ce qui rend le diagnostic contre-intuitif, et
pourquoi tant d'incidents de ce type finissent en « le serveur perd nos logs ».
:::

---

### **BF16.4** — *Fichier de 800 Mo presque vide.*

**Diagnostic**

```bash
# 1. les deux tailles ne concordent pas
ls -lh /var/log/factura/acces.log        # 800M  (taille apparente)
du -h  /var/log/factura/acces.log        # 240K  (blocs alloues)
wc -l  /var/log/factura/acces.log        # 4000 lignes

# 2. la preuve du trou : la carte des extents
filefrag -v /var/log/factura/acces.log | head
# ou, plus simple :
head -c 200 /var/log/factura/acces.log | od -c | head

# 3. le trou de numerotation
grep -ao 'seq=[0-9]*' /var/log/factura/acces.log | head -1
sudo zgrep -ao 'seq=[0-9]*' /var/log/factura/acces.log.1* | tail -1

# 4. la configuration de rotation
cat /etc/logrotate.d/factura-acces

# 5. comment l'application est lancee et ouvre son fichier
systemctl cat factura-ecrivain     # drop-in : --sans-append, sans --hup
sudo ls -l /proc/$(pgrep -f factura-ecrivain)/fd | grep acces
sudo cat /proc/$(pgrep -f factura-ecrivain)/fdinfo/3   # champ flags
```

**Cause racine** — **deux** anomalies distinctes, une seule origine :

* `copytruncate` dans `/etc/logrotate.d/factura-acces` ;
* l'application ouvre son fichier **sans `O_APPEND`** et conserve son
  descripteur : le drop-in `10-sans-append.conf` la lance avec `--sans-append`, et sans `--hup`.

La première explique le trou de numérotation (lignes écrites pendant la copie,
détruites par la troncature). La seconde explique la taille apparente : après
`truncate()`, la position du descripteur vaut toujours 800 000 000, l'écriture
suivante a lieu à cet offset et le noyau crée un trou de zéros.

**Correctif**

```bash
# 1. relancer l'appli en mode append et avec --hup (sans toucher au code)
sudo rm /etc/systemd/system/factura-ecrivain.service.d/10-sans-append.conf
sudo systemctl daemon-reload
# 1 bis. sortir de copytruncate : l'application sait reagir a SIGHUP
sudo tee /etc/logrotate.d/factura-acces >/dev/null <<'EOF'
/var/log/factura/acces.log {
    daily
    maxsize 100M
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    create 0640 factura adm
    su root adm
    postrotate
        /usr/bin/systemctl kill -s HUP factura-ecrivain.service \
            2>/dev/null || true
    endscript
}
EOF
sudo chmod 0644 /etc/logrotate.d/factura-acces
sudo chown root:root /etc/logrotate.d/factura-acces

# 2. recuperer l'espace apparent et repartir propre
sudo cp --sparse=always /var/log/factura/acces.log \
        /var/log/factura/acces.log.recup
sudo tr -d '\0' < /var/log/factura/acces.log.recup \
     | sudo tee /var/log/factura/acces.log.propre >/dev/null
sudo systemctl stop factura-ecrivain
sudo mv /var/log/factura/acces.log.propre /var/log/factura/acces.log
sudo chown factura:adm /var/log/factura/acces.log
sudo rm -f /var/log/factura/acces.log.recup
sudo systemctl start factura-ecrivain

# 3. verifier
sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -A5 acces
```

::: pourquoi
**Les deux anomalies sont indépendantes et il faut savoir les séparer.**
`copytruncate` sur une application qui utilise `O_APPEND` ne produit **pas** de
fichier creux : elle perd juste des lignes. Une application sans `O_APPEND` dont
le fichier n'est jamais tronqué ne produit pas de trou non plus. C'est la
**combinaison** qui donne le symptôme spectaculaire. En entretien, savoir
décomposer les deux est très discriminant.

**Ce que dit `fdinfo`.** `/proc/<pid>/fdinfo/<fd>` contient une ligne `flags:`
en octal. `O_APPEND` vaut `02000`. Des flags à `0102001` contiennent
`O_APPEND` ; à `0100001`, non. C'est la preuve formelle, meilleure que la
lecture du code.

**Pourquoi `tr -d '\0'` et pas un simple `cp`.** Un `cp` classique lit le trou
comme des zéros et écrit 800 Mo de zéros réels : le remède serait pire que le
mal. `--sparse=always` préserve le caractère creux, et `tr -d '\0'` élimine les
octets nuls pour retrouver un fichier texte normal.

**Ce que l'application devrait faire côté code**, par ordre de préférence :

1. ouvrir en mode **append** (`open(..., O_APPEND)`, `fopen(..., "a")`,
   `logging.FileHandler(mode="a")` en Python) : le noyau repositionne à la fin
   du fichier de façon atomique avant chaque écriture, et le trou devient
   impossible ;
2. mieux encore, **ne pas gérer de fichier du tout** : écrire sur stdout et
   laisser journald ou le runtime de conteneurs s'en charger. Plus de rotation,
   plus de descripteur, plus de problème ;
3. si un fichier est imposé, utiliser une bibliothèque de rotation côté
   application (`WatchedFileHandler` en Python, `logrotate` externe avec
   `SIGHUP`) plutôt que `copytruncate`.
:::

::: piege
Le fichier creux passe inaperçu dans les sauvegardes jusqu'au jour où il ne
passe plus : `tar` et `rsync` sans `--sparse` écrivent les 800 Mo de zéros pour
de bon. Une sauvegarde de 12 Mo devient un fichier de 800 Mo sur la
destination, et on découvre le problème quand la baie de sauvegarde sature. De
même, `cat acces.log | wc -c` lit réellement 800 Mo d'octets nuls.
:::

---

## 16.8 Défi du module

**D16 — Le poste de pilotage d'un serveur applicatif**

**Squelette de `/opt/factura/bin/sante.sh`**

```bash
#!/usr/bin/env bash
# sante.sh — etat de sante d'un serveur applicatif.
# stdout : le rapport. stderr : les diagnostics.
# 0 = rien, 1 = avertissement, 2 = anomalie critique.
set -euo pipefail

S_RATIO=1.5 ; S_WA=20 ; S_MEMPCT=15 ; S_FS=90 ; S_FSCRIT=95
S_INODE=90 ; S_ST=5
AVERT=0 ; CRIT=0
avert() { ANOMALIES+=("AVERTISSEMENT $*"); AVERT=1; }
crit()  { ANOMALIES+=("CRITIQUE      $*"); CRIT=1; }
ANOMALIES=()
dispo() { command -v "$1" >/dev/null 2>&1; }

printf '# Etat de sante — %s — %s\n\n' "$(hostname -f)" "$(date -Is)"

# --- 1. identite ---------------------------------------------------------
COEURS=$(nproc)
printf '* coeurs : %s   uptime : %s\n' "$COEURS" "$(uptime -p)"
printf '* dernier demarrage : %s\n\n' "$(uptime -s)"

# --- 2. charge -----------------------------------------------------------
read -r L1 L5 L15 _ < /proc/loadavg
RATIO=$(awk -v l="$L1" -v c="$COEURS" 'BEGIN{printf "%.2f", l/c}')
printf '## Charge\n\n%s %s %s — ratio/coeur %s\n\n' \
       "$L1" "$L5" "$L15" "$RATIO"
depasse() { awk -v v="$1" -v s="$2" 'BEGIN{exit !(v>s)}'; }
depasse "$RATIO" "$S_RATIO" && avert "charge/coeur = $RATIO" || true

# --- 3. CPU, sur un delta de 2 s ----------------------------------------
lire() { awk '/^cpu /{print $2+$3, $4, $5, $6, $9, $2+$3+$4+$5+$6+$7+$8+$9}' \
         /proc/stat; }
read -r u1 s1 i1 w1 t1 T1 < <(lire)
sleep 2
read -r u2 s2 i2 w2 t2 T2 < <(lire)
D=$((T2-T1))
p() { awk -v a="$1" -v d="$D" 'BEGIN{printf "%.1f", d?100*a/d:0}'; }
US=$(p $((u2-u1))); SY=$(p $((s2-s1))); WA=$(p $((w2-w1))); ST=$(p $((t2-t1)))
printf '## CPU\n\nus=%s sy=%s wa=%s st=%s\n\n' "$US" "$SY" "$WA" "$ST"
depasse "$WA" "$S_WA" && avert "%wa = $WA" || true
depasse "$ST" "$S_ST" && avert "%st = $ST (hyperviseur)" || true

# --- 4. memoire ----------------------------------------------------------
# ... MemTotal / MemAvailable / si-so de vmstat, meme structure

# --- 5. systemes de fichiers : espace ET inodes -------------------------
printf '## Systemes de fichiers\n\n'
df -hP -x tmpfs -x devtmpfs | awk 'NR>1 {print "* "$6" "$5" (espace)"}'
df -iP -x tmpfs -x devtmpfs | awk 'NR>1 {print "* "$6" "$5" (inodes)"}'
while read -r pct pt; do
  if [ "$pct" -ge "$S_FSCRIT" ]; then crit "$pt a $pct% d'espace"
  elif [ "$pct" -ge "$S_FS" ]; then avert "$pt a $pct% d'espace"; fi
done < <(df -P -x tmpfs -x devtmpfs | awk 'NR>1 {gsub("%","",$5);
         print $5, $6}')

# --- 6. sections degradables --------------------------------------------
if dispo iostat; then
  printf '## Disques\n\n'; iostat -xz 1 2 | tail -n +7
else
  printf '## Disques\n\n(section indisponible : sysstat non installe)\n\n' >&2
fi

# --- 7. journal ----------------------------------------------------------
printf '## Journal\n\n'
printf '* taille : %s\n' "$(journalctl --disk-usage 2>/dev/null)"
printf '* entrees err depuis le boot : %s\n\n' \
       "$(journalctl -b -p err --no-pager -q 2>/dev/null | wc -l || true)"
journalctl -b -p err -n 10 -o short-iso --no-pager 2>/dev/null || true

# --- 8. unites en echec --------------------------------------------------
# « || true » DANS la substitution : avec pipefail, une commande qui
# echoue en tete de pipeline suffit a faire sortir le script.
ECHECS=$(systemctl list-units --state=failed --no-legend --no-pager \
         2>/dev/null | wc -l || true)
if [ "$ECHECS" -gt 0 ]; then crit "$ECHECS unite(s) systemd en echec"; fi

# --- 9. verdict ----------------------------------------------------------
# Toujours des if/then ici : « test && action » renvoie 1 quand le test
# est faux ; en derniere commande du script (ou d'une fonction), ce 1
# devient le code retour — « avertissement » alors que tout va bien.
printf '\n## VERDICT\n\n'
if [ "${#ANOMALIES[@]}" -eq 0 ]; then
  echo "Aucune anomalie."
else
  printf '* %s\n' "${ANOMALIES[@]}"
fi
if [ "$CRIT" -eq 1 ]; then exit 2; fi
if [ "$AVERT" -eq 1 ]; then exit 1; fi
exit 0
```

::: pourquoi
**Les cinq points sur lesquels ce défi est réellement évalué.**

**1. Les inodes.** `df -h` et `df -i` mesurent deux épuisements indépendants. Un
`/var` à 40 % d'espace et 100 % d'inodes refuse toute création de fichier avec
`No space left on device` — le message est le même, la cause n'a rien à voir.
C'est un grand classique sur les serveurs de mail, les caches de session et les
répertoires de spool. Un script de santé qui ne regarde que l'espace rate la
moitié des incidents disque.

**2. La dégradation propre.** `set -euo pipefail` fait sortir le script au
premier échec. Avec `iostat` absent, une ligne
`UTIL=$(iostat ... | awk ...)` tue le script au milieu du rapport, et
l'exploitant perd aussi les sections qui fonctionnaient. Le contrat est :
`command -v` avant chaque outil optionnel, message sur **stderr**, section
marquée indisponible, et on continue. Un outil de diagnostic qui meurt quand la
machine va mal n'a aucune valeur.

**3. La séparation des flux.** Le rapport sur stdout, les diagnostics sur
stderr : `sante.sh > /var/log/factura/sante-$(date +%F).md` doit produire un
Markdown propre, et `sante.sh 2>/dev/null | mail -s ...` doit rester lisible.
C'est la même discipline qu'au module 07.

**4. Le code retour.** `0/1/2` permet de brancher le script sur n'importe quel
ordonnanceur ou sonde (Nagios utilise exactement cette convention, avec 3 pour
« inconnu »). Le point délicat en bash : avec `set -e`, une commande qui renvoie
1 dans une condition ne fait pas sortir le script, mais la même commande en fin
de ligne, oui. D'où les tests écrits en `awk 'BEGIN{exit !(...)}' && avert ...`,
qui sont explicites et sûrs.

**5. La portabilité Ubuntu/Rocky.** Les écarts à gérer :
`/var/log/sysstat` contre `/var/lib/sa`, `auth.log` contre `secure`,
`syslog` contre `messages`, `ssh.service` contre `sshd.service`, `adm` contre
`wheel`. Tout ce qui est `/proc`, `systemctl`, `journalctl` et `df` est
identique : c'est pour ça qu'on s'appuie dessus en priorité.

**Le document `pilotage.md`** est noté sur la **justification des seuils**, pas
sur les seuils eux-mêmes. Un seuil sans justification est un seuil copié. Les
justifications attendues, par exemple :

* charge/cœur > 1,5 pendant 15 min : en dessous, les rafales normales
  déclencheraient du bruit ; c'est un avertissement, jamais une astreinte ;
* `available` < 15 % : au-delà, le noyau commence à récupérer du cache et les
  latences disque montent ;
* système de fichiers > 95 % : critique, parce que le franchissement est
  **irréversible** sans intervention et que la plupart des services s'arrêtent
  net à 100 % ;
* `%st` > 5 % : rien à corriger dans la VM, mais un ticket à ouvrir chez
  l'hébergeur — le classer en avertissement, pas en critique, sinon on réveille
  quelqu'un qui ne peut rien faire.

**Les trois alertes Prometheus** à proposer pour le module 26 :

| Alerte | Condition | Astreinte |
|---|---|---|
| `ServiceIndisponibleup` | `== 0` pendant 2 min | oui |
| `LatenceP99Degradeep99` | \> 2 s pendant 5 min | oui |
| `DisquePleinDans4hpredict_linear` | `(avail[6h], 4*3600) < 0` | oui |

Et à ne **pas** mettre en astreinte : `CPUEleve`, `ChargeElevee`,
`MemoireUtilisee` — ce sont des tableaux de bord, pas des réveils.
:::

::: piege
Le piège du défi est le `set -euo pipefail` combiné aux tableaux bash. Un
`${ANOMALIES[@]}` sur un tableau **vide** provoque `unbound variable` sous
`set -u` avec bash antérieur à 4.4. Sur Ubuntu 24.04 (bash 5.2) le cas est
traité, mais un script destiné à tourner ailleurs écrit
`${ANOMALIES[@]+"${ANOMALIES[@]}"}` ou initialise le tableau avec un élément
bidon. C'est typiquement le genre de détail qui fait échouer le script le jour
où tout va bien — donc le jour où personne ne le regarde.
:::
