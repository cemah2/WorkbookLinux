# Module 08 — Corrigé

## 8.3 Quiz — QCM

**Q8.1** — *Une entrée `Z ... <defunct>` dans `ps aux` : comment la faire disparaître ?*

**Réponse : c)** faire en sorte que le père appelle `wait()`, ou tuer le père.

::: pourquoi
Un zombie n'est pas un processus vivant : son image mémoire, ses descripteurs et
sa pile ont déjà été libérés. Ce qui reste est une **entrée dans la table des
processus** (`task_struct`) conservée par le noyau dans un seul but : garder le
code de retour et les statistiques d'utilisation jusqu'à ce que le père les lise
avec `wait()` / `waitpid()`.

On ne tue pas un mort. `kill -9` envoie un signal à un processus qui n'exécute
plus aucune instruction : le signal est simplement ignoré. Deux issues possibles :

* le père finit par appeler `wait()` — l'entrée disparaît immédiatement ;
* le père meurt — le zombie devient orphelin, il est **ré-adopté par PID 1**, et
  systemd, qui appelle `wait()` en boucle, le récolte aussitôt.

C'est pourquoi tuer le père fait toujours disparaître ses zombies : ce n'est pas
le zombie qu'on traite, c'est le bug de programmation du père.
:::

::: piege
Un zombie isolé ne coûte quasiment rien. Ce qui tue une machine, c'est une
**fuite** : un père qui crée des fils en boucle sans jamais les récolter finit
par épuiser `kernel.pid_max` (par défaut 4 194 304 sur un noyau 64 bits récent,
32 768 sur les configurations plus anciennes). À partir de là, plus aucun `fork()`
ne réussit sur la machine, y compris celui de ton shell : la sortie classique est
`bash: fork: retry: Resource temporarily unavailable`. Compte-les avec
`ps -eo stat | grep -c '^Z'` et surveille cette valeur.
:::

---

**Q8.2** — *Processus en `D` depuis 20 minutes sur un montage NFS injoignable (deux réponses).*

**Réponses : a) et b)**

::: pourquoi
`D` est l'état `TASK_UNINTERRUPTIBLE` du noyau : le processus est bloqué à
l'intérieur d'un appel système, en attente d'un événement matériel ou réseau.
Les signaux ne sont **pas perdus**, ils sont mis en file d'attente — mais ils ne
sont examinés qu'au retour en espace utilisateur. Or le processus n'y revient
jamais tant que l'appel système n'a pas rendu la main. `SIGKILL` inclus : c'est
le seul cas sous Linux où `kill -9` n'a aucun effet immédiat.

Deuxième point, moins connu et très discriminant en entretien : sous Linux, la
**charge moyenne compte les processus en `R` *et* en `D`**, contrairement à la
définition historique d'UNIX qui ne compte que les runnables. Une machine avec
`load average: 40` et 2 % de CPU utilisé n'a pas un problème de CPU : elle a
quarante processus bloqués en attente d'E/S. C'est le signe d'un stockage, d'un
NFS ou d'un multipath en panne.

Ce qu'on fait vraiment : `cat /proc/PID/wchan` (la fonction noyau où ça bloque),
`cat /proc/PID/stack` (root requis), `dmesg -T | grep -i 'blocked for more than'`
qui affiche les traces du `hung task detector` après 120 s, et on répare la
couche du dessous. Un `umount -f -l` du montage NFS libère parfois les processus.
:::

::: piege
c) et d) sont fausses pour la même raison : elles traitent le symptôme au lieu de
la cause. `renice` agit sur l'ordonnanceur CPU, or le processus ne demande pas de
CPU. Et un `D` n'a rien d'un zombie : il est bien vivant, simplement bloqué. Sur
certains chemins de code, le noyau utilise `TASK_KILLABLE` (visible aussi en `D`)
qui, lui, accepte `SIGKILL` — d'où les cas où le `-9` finit par passer.
:::

---

**Q8.3** — *`./migration.sh &` puis fermeture de la fenêtre SSH.*

**Réponse : b)** le script meurt, tué par `SIGHUP`.

::: pourquoi
La chaîne exacte, à savoir citer en entretien :

1. Tu fermes la fenêtre ou la connexion tombe. `sshd` ferme le côté maître du
   pseudo-terminal.
2. Le noyau détecte la fermeture du terminal de contrôle et envoie **`SIGHUP` au
   chef de session** — c'est-à-dire à ton shell de login, pas à tes jobs.
3. Bash, en tant que shell interactif avec contrôle de tâches, réagit à `SIGHUP`
   en **relayant `SIGHUP` à tous les jobs** qu'il connaît, puis sort.
4. `migration.sh` n'a pas de gestionnaire pour `SIGHUP` : l'action par défaut est
   la terminaison. Le script meurt.

`&` ne détache de rien : le job reste dans le même groupe de processus, la même
session, et le même terminal de contrôle. Il change juste de groupe de processus
de premier plan.
:::

---

**Q8.4** — *Quelles commandes font survivre le script (trois réponses) ?*

**Réponses : a), b) et c)**

::: pourquoi
Les trois agissent à des étapes différentes de la chaîne ci-dessus.

`nohup` agit à l'étape 4 : il positionne le gestionnaire de `SIGHUP` à `SIG_IGN`
**avant** le `execve()`, et cette disposition est héritée. Le signal arrive, il
est ignoré. Effet de bord : si stdout est un terminal, `nohup` le redirige vers
`./nohup.out` (ou `$HOME/nohup.out`), parce qu'écrire sur un terminal disparu
provoquerait un `SIGTTOU` ou une erreur d'E/S.

`disown -h %1` agit à l'étape 3 : il marque le job pour que **bash ne lui relaie
pas** le `SIGHUP`. Le job reste dans la table des jobs (contrairement à `disown`
sans option, qui l'en retire complètement). Attention : ça ne protège que du
`SIGHUP` **de bash**, pas de celui que le noyau enverrait au groupe de processus
de premier plan si le processus y était encore.

`systemd-run --unit=migration` ne joue à aucune de ces étapes : il demande à PID 1
de créer une **unité transitoire**. Le processus est démarré par systemd, dans un
cgroup à lui, sans aucun lien avec ta session ni avec ton terminal. C'est la
seule des trois qui survit aussi à un `kill` de ta session entière.

d) `renice` ne touche qu'à la priorité d'ordonnancement. Aucun rapport.
:::

::: piege
`setsid cmd` marche aussi (nouvelle session, plus de terminal de contrôle), mais
avec un piège : sans redirection, le processus garde les descripteurs 0, 1 et 2
ouverts sur le terminal mort, et se prendra une erreur `EIO` à la première
écriture. La forme réellement utilisable est
`setsid --fork cmd </dev/null >/tmp/cmd.log 2>&1`.
:::

---

**Q8.5** — *`Type=simple` et un `ExecStart` avec une faute de frappe.*

**Réponse : b)** `systemctl start` rend la main sans erreur, puis le service
tombe en `failed` avec `status=203/EXEC`.

```console
$ systemctl status factura-api
     Active: failed (Result: exit-code) since Fri 2026-09-18 11:04:02 CEST
    Process: 4711 ExecStart=/opt/factura/bin/factura-api.pyy (code=exited,
             status=203/EXEC)
```

::: pourquoi
C'est le comportement le plus contre-intuitif de systemd, et la raison d'être de
`Type=exec`. Avec `Type=simple`, systemd considère le service **démarré dès qu'il
a réussi le `fork()`**, c'est-à-dire avant même de savoir si le `execve()` va
aboutir. Le `fork()` réussit toujours (sauf épuisement de PID). Le job `start`
est donc rapporté comme réussi, et `systemctl start` sort en 0.

Le `execve()` échoue une fraction de seconde plus tard, dans le processus fils.
Le code d'aide de systemd sort alors avec le code **203**, qui signifie
`EXIT_EXEC` : « impossible d'exécuter le binaire ». C'est systemd qui produit ce
code, pas ton programme. Les principaux :

| Code | Nom | Cause |
|---|---|---|
| `200` | `EXIT_CHDIR` | `WorkingDirectory=` inexistant |
| `203` | `EXIT_EXEC` | binaire absent, non exécutable, mauvais shebang |
| `216` | `EXIT_GROUP` | `Group=` inconnu |
| `217` | `EXIT_USER` | `User=` inconnu |
| `226` | `EXIT_NAMESPACE` | isolation impossible (voir Q8.17) |

Conséquence d'exploitation : un script de déploiement qui se contente de tester
le code retour de `systemctl start` **ne détecte pas la panne**. Il faut soit
`Type=exec`, soit un contrôle explicite après coup (`systemctl is-active`).
:::

---

**Q8.6** — *`Type=exec` au lieu de `Type=simple`.*

**Réponse : b)** `systemctl start` échoue immédiatement et rapporte `203/EXEC`.

::: pourquoi
`Type=exec` est arrivé avec systemd 240 précisément pour corriger le défaut de
`simple`. Le mécanisme : systemd n'annonce le service démarré qu'**après** avoir
constaté que le `execve()` a réussi. Techniquement, il garde un descripteur
ouvert avec le fils (marqué `CLOEXEC`) : si `execve()` réussit, le descripteur se
ferme tout seul, ce que systemd interprète comme « le binaire tourne » ; si
`execve()` échoue, le fils écrit l'erreur avant de sortir.

Ce que `Type=exec` **ne** garantit **pas** : que l'application soit prête à
servir. Le binaire a démarré, c'est tout. Pour la disponibilité réelle, il faut
`Type=notify` (l'application dit « je suis prête ») ou une sonde côté client.

Règle simple : pour un service qui reste au premier plan, `Type=exec` par défaut,
`Type=notify` si l'application sait faire `sd_notify`. `Type=simple` n'a plus de
raison d'être sur une machine moderne.
:::

---

**Q8.7** — *Un démon qui se détache seul, déclaré `Type=simple`.*

**Réponse : b)** systemd voit le processus principal sortir aussitôt, considère
que le service s'est terminé, et nettoie le cgroup.

::: pourquoi
Avec `Type=simple`, systemd désigne comme **processus principal** celui qu'il a
lancé lui-même. `factura-legacy.sh` fait son `fork()`, écrit le fichier de PID,
puis sort en 0. Du point de vue de systemd, le processus principal vient de se
terminer : le service passe en `inactive (dead)`.

Et parce que le `KillMode` par défaut est `control-group`, systemd ne se contente
pas de constater : il **tue tout ce qui reste dans le cgroup du service**. Le
démon détaché, qui est resté dans ce cgroup, reçoit un `SIGTERM` puis un
`SIGKILL`. Le service ne survit pas, quelle que soit la qualité du démon.

C'est ce confinement par cgroup qui distingue radicalement systemd de SysVinit :
un service ne peut plus « s'échapper » de son unité en se détachant. C'est une
excellente propriété — mais elle rend `Type=` obligatoire à choisir correctement.

La bonne réponse ici est `Type=forking` avec `PIDFile=`, qui dit à systemd :
« attends que le processus initial sorte, et considère comme principal le PID
que tu trouveras dans ce fichier ». Mieux encore, quand l'application le permet :
lui demander de rester au premier plan (`--foreground`, `-D`, `daemon off;`…) et
utiliser `Type=exec`.
:::

---

**Q8.8** — *Unité créée à la main, puis `systemctl start` directement.*

**Réponse : b)** il manque `systemctl daemon-reload`.

::: pourquoi
systemd ne relit pas les fichiers d'unités à chaque commande. Il maintient en
mémoire un graphe d'objets (unités, dépendances, jobs) construit au démarrage et
mis à jour uniquement sur demande. `daemon-reload` est cette demande : il
réanalyse `/etc/systemd/system`, `/run/systemd/system` et
`/usr/lib/systemd/system`, reconstruit le graphe, **sans** toucher aux services
en cours d'exécution.

Symptôme sans `daemon-reload` : `Failed to start factura-api.service: Unit
factura-api.service not found.` — et, si l'unité existait déjà et que tu l'as
modifiée, systemd te prévient au `status` suivant :

```text
Warning: The unit file, source configuration file or drop-ins of
factura-api.service changed on disk. Run 'systemctl daemon-reload' to reload
units.
```

À retenir : `daemon-reload` recharge la **configuration de systemd** ;
`systemctl reload <unité>` recharge la configuration **de l'application**. Ce
sont deux choses sans rapport, et les confondre est l'erreur de débutant la plus
fréquente sur ce module.
:::

---

**Q8.9** — *Faut-il un `daemon-reload` après `systemctl edit` ?*

**Réponse : b)** non, `systemctl edit` le fait ; mais il faut redémarrer le
service pour que la nouvelle valeur s'applique au processus en cours.

::: pourquoi
`systemctl edit factura-api` ouvre `$EDITOR` sur un fichier temporaire, et à la
fermeture : il écrit
`/etc/systemd/system/factura-api.service.d/override.conf`, puis déclenche
lui-même un `daemon-reload`. Si tu refermes l'éditeur sans rien enregistrer, il
supprime le fichier vide et ne fait rien.

En revanche, la plupart des directives de `[Service]` ne sont lues qu'au
**lancement du processus** : `User=`, `LimitNOFILE=`, `Environment=`,
`ProtectSystem=`, `ExecStart=`. Modifier la configuration d'une unité ne change
rien au processus déjà en cours d'exécution. Il faut `systemctl restart`.

Exception notable : les directives de ressources cgroup (`MemoryMax=`,
`CPUQuota=`, `TasksMax=`) sont appliquées **à chaud** par systemd, parce qu'il
lui suffit d'écrire dans les fichiers du cgroup existant. Un `daemon-reload`
suffit alors, sans redémarrage — ce qui en fait le levier de mitigation d'urgence
sur un service qui part en vrille.
:::

---

**Q8.10** — *`disable` contre `mask`.*

**Réponse : b)**

::: pourquoi
Ce sont deux mécanismes totalement différents, qui agissent à deux niveaux.

`enable` / `disable` manipulent des **liens symboliques d'activation** décrits
par la section `[Install]` de l'unité. `enable` crée
`/etc/systemd/system/multi-user.target.wants/factura-api.service →
/etc/systemd/system/factura-api.service`. `disable` supprime ce lien. Résultat :
le service ne démarre plus **au boot**, mais `systemctl start` fonctionne
parfaitement, et une autre unité qui le déclare en `Wants=` le démarrera.

`mask` remplace l'unité par un **lien vers `/dev/null`** dans
`/etc/systemd/system`. Comme ce répertoire a la précédence la plus haute, systemd
charge un fichier vide et considère l'unité comme non chargeable :

```console
$ sudo systemctl start factura-rapports
Failed to start factura-rapports.service: Unit factura-rapports.service is
masked.
```

Aucun démarrage n'est plus possible : ni manuel, ni au boot, ni **par
dépendance** d'un autre service. C'est l'outil qu'on utilise pour neutraliser
définitivement un service qu'un paquet réactive à chaque mise à jour. C'est aussi
un excellent moyen de laisser derrière soi une panne incompréhensible (BF8.3).

`systemctl list-unit-files --state=masked` donne la liste complète en une
commande. À faire en arrivant sur une machine dont on hérite.
:::

---

**Q8.11** — *Drop-in qui redéfinit `ExecStart=` sans le vider.*

**Réponse : b)** le service échoue sur
`Service has more than one ExecStart= setting, which is only allowed for
Type=oneshot services.`

::: pourquoi
systemd distingue deux familles de directives. Les directives **scalaires**
(`User=`, `Type=`, `Restart=`, `MemoryMax=`) : la dernière affectation lue gagne,
et un drop-in écrase donc naturellement l'unité de base. Les directives
**de type liste** (`ExecStart=`, `ExecStartPre=`, `Environment=`,
`ReadWritePaths=`, `After=`, `Wants=`) : chaque affectation **ajoute** à la liste.

Pour remplacer une liste, la convention est de l'**écraser avec la chaîne vide**,
ce qui la remet à zéro, puis de la redéfinir :

```ini
[Service]
ExecStart=
ExecStart=/opt/factura/bin/factura-api.py --port 9090
```

Le même motif s'applique à `Environment=`, `ReadWritePaths=`, `After=`. C'est
exactement la raison pour laquelle `systemctl edit` d'un service avec `ExecStart`
est une source d'erreur permanente, et pourquoi `systemctl cat` est la seule
réponse fiable à la question « qu'est-ce qui est réellement appliqué ? ».
:::

::: piege
`Type=oneshot` accepte plusieurs `ExecStart=`, exécutés **dans l'ordre** et de
façon séquentielle : c'est la seule exception. D'où le message d'erreur, qui
parle de `oneshot` alors que tu n'as rien demandé de tel.
:::

---

**Q8.12** — *Application à 1024 descripteurs malgré `limits.conf`.*

**Réponse : b)**

::: pourquoi
`/etc/security/limits.conf` n'est pas un fichier du noyau : c'est la
configuration du module PAM `pam_limits.so`. Il n'est donc lu que lorsqu'une
**session PAM** est ouverte — c'est-à-dire par `login`, `sshd`, `su`, `sudo -i`,
et les gestionnaires de session graphique. Vérifiable :
`grep pam_limits /etc/pam.d/*`.

Un service lancé par systemd n'ouvre **aucune session PAM** (sauf si l'unité
déclare explicitement `PAMName=`). Il hérite des limites de PID 1, ajustées par
`/etc/systemd/system.conf` (`DefaultLimitNOFILE=`) puis par la directive
`LimitNOFILE=` de l'unité. Sur Ubuntu 24.04, la valeur par défaut pour les
services est `1024:524288` — souple à 1024, stricte à 524 288 — justement pour ne
pas casser les vieux programmes qui bouclent sur `getdtablesize()`.

La conséquence pratique : la même application plantera à 1024 descripteurs quand
elle est lancée par systemd, et tiendra 65 536 quand tu la lances à la main dans
ton SSH. « Ça marche quand je le lance à la main » a ici une explication
parfaitement rationnelle.

La correction est dans l'unité :

```ini
[Service]
LimitNOFILE=65536
```

et la vérification se fait sur le processus réel, jamais sur le fichier :

```bash
PID=$(systemctl show -p MainPID --value factura-api)
grep 'Max open files' /proc/$PID/limits
```
:::

::: piege
Écrire `* hard nofile 65536` sans la ligne `soft` correspondante ne change rien :
la limite **souple** reste à 1024, et c'est elle que le noyau applique. La ligne
`hard` ne fait qu'autoriser le processus à monter jusque-là de lui-même avec
`setrlimit()`. Beaucoup de documentations en ligne oublient ce détail.
:::

---

**Q8.13** — *`Restart=always` et `EnvironmentFile=` supprimé.*

**Réponse : b)** `failed` avec `Result: start-limit-hit`.

::: pourquoi
systemd embarque un limiteur de débit sur les démarrages, pour éviter qu'une
unité en échec ne consomme la machine en boucle. Deux directives, dans la section
**`[Unit]`** et non `[Service]` — c'est un piège classique :

| Directive | Défaut |
|---|---|
| `StartLimitIntervalSec=` | 10 s |
| `StartLimitBurst=` | 5 |

Au-delà de 5 démarrages en 10 secondes, systemd refuse et affiche :

```text
factura-collecte.service: Start request repeated too quickly.
factura-collecte.service: Failed with result 'start-limit-hit'.
```

À partir de là, l'unité est verrouillée : `systemctl start` et `restart`
échouent immédiatement, **sans même tenter** de lancer le binaire. Il faut
`systemctl reset-failed factura-collecte` pour remettre le compteur à zéro. Le
compteur se réinitialise aussi tout seul après `StartLimitIntervalSec` sans
nouvelle tentative, mais l'état `failed` du service, lui, persiste.

C'est un mécanisme de protection, pas un bug : sans lui, un service en boucle à
100 ms noierait le journal et saturerait un cœur.
:::

---

**Q8.14** — *`Type=oneshot` + `RemainAfterExit=yes` après une exécution réussie.*

**Réponse : b) `active (exited)`**

::: pourquoi
`Type=oneshot` dit à systemd d'attendre la **fin** du processus avant de
considérer le démarrage terminé. Sans plus, l'unité retomberait aussitôt en
`inactive (dead)` : le traitement est fini, il n'y a plus de processus.

`RemainAfterExit=yes` change l'interprétation : l'unité reste considérée comme
**active** après la sortie du processus, avec le sous-état `exited` (actif, mais
sans processus). C'est ce qui permet :

* de savoir d'un coup d'œil que le traitement a été fait sur cette machine ;
* de rendre `systemctl stop` significatif (il déclenche `ExecStop=`) ;
* d'utiliser l'unité comme cible de dépendance : `After=factura-collecte.service`
  a alors un sens durable.

C'est le patron canonique des unités de configuration initiale : montage,
migration de schéma de base, chargement de règles pare-feu.
:::

::: piege
`Restart=always` et `Restart=on-success` sont **refusés** avec `Type=oneshot` :
systemd affiche `Service has Restart= set to either always or on-success, which
isn't allowed for Type=oneshot services. Refusing.` La relance d'un traitement
ponctuel se gère avec un timer (module 14), pas avec `Restart=`.
:::

---

**Q8.15** — *Lecture d'un `systemctl status ssh` (deux réponses).*

**Réponses : a) et b)**

::: pourquoi
Décorticage de la ligne `Loaded:`, mot à mot :

```text
Loaded: loaded (/usr/lib/systemd/system/ssh.service; disabled; preset: enabled)
        |        |                                  |         |
        |        chemin du fichier réellement chargé |         |
        l'unité est chargée en mémoire              |         |
                                    état d'activation au boot |
                                              ce que le paquet recommandait
```

* `loaded` : systemd a lu et analysé l'unité. Une unité masquée affiche
  `masked`, une unité absente `not-found`.
* le **chemin** dit d'où vient la définition. `/usr/lib/systemd/system` = fournie
  par le paquet. `/etc/systemd/system` = écrite ou surchargée localement. C'est
  pourquoi d) est faux.
* `disabled` : aucun lien dans un `*.target.wants`. Le service ne redémarrera pas
  au boot — d'où b).
* `preset: enabled` : la **recommandation** du paquet, lue dans
  `/usr/lib/systemd/system-preset/*.preset`. Elle n'est appliquée qu'à
  l'installation ou sur `systemctl preset`. Un écart entre `preset` et l'état
  réel signale une intervention humaine, mais ne la prouve pas.

La ligne `Active: active (running)` répond à a). Les deux lignes sont
**indépendantes** : un service peut tourner sans être activé au boot (a + b,
exactement notre cas), ou être activé au boot sans tourner.
:::

---

**Q8.16** — *`Requires=` sans `After=`.*

**Réponse : b)** les deux unités démarrent en parallèle.

::: pourquoi
systemd sépare strictement deux dimensions que SysVinit confondait :

* **la dépendance de besoin** : `Wants=`, `Requires=`, `BindsTo=`, `Requisite=`.
  Elle répond à « faut-il que l'autre unité soit là ? » ;
* **l'ordonnancement** : `After=`, `Before=`. Il répond à « dans quel ordre ? ».

Aucune des deux n'implique l'autre. `Requires=postgresql.service` demande à
systemd de démarrer PostgreSQL en même temps, et d'échouer si PostgreSQL ne
démarre pas. Mais sans `After=postgresql.service`, les deux jobs sont poussés
dans la file au même instant, et l'application peut très bien ouvrir sa
connexion avant que la base n'écoute.

Le symptôme en production est le pire qui soit : ça marche en général, et ça
échoue **une fois sur dix au boot**, selon la charge de la machine et la vitesse
du disque. Ces pannes-là se cherchent pendant des semaines.

L'écriture correcte est toujours la paire :

```ini
[Unit]
Requires=postgresql.service
After=postgresql.service
```

Et même là, « PostgreSQL est démarré » ne veut pas dire « PostgreSQL accepte les
connexions » : seul un `Type=notify` côté base, ou une boucle de réessai côté
application, le garantit vraiment. La résilience au démarrage se code dans
l'application, l'ordonnancement ne fait que réduire la fenêtre.
:::

---

**Q8.17** — *`ProtectSystem=strict` casse l'écriture du journal (deux réponses).*

**Réponses : a) et b)**

::: pourquoi
`ProtectSystem=` a trois niveaux, de plus en plus stricts :

| Valeur | Ce qui passe en lecture seule |
|---|---|
| `yes` | `/usr`, `/boot`, `/efi` |
| `full` | idem + `/etc` |
| `strict` | **toute** l'arborescence, sauf `/dev`, `/proc`, `/sys` |

Le mécanisme est un **espace de noms de montage** (mount namespace) privé au
service : systemd remonte les chemins concernés en lecture seule dans cet espace,
sans rien changer pour le reste de la machine. L'écriture échoue donc avec
`EROFS`, pas avec `EACCES` — les permissions du fichier sont intactes.

Deux façons de rouvrir un chemin :

* `ReadWritePaths=/var/log/factura` : perce un trou dans le remontage lecture
  seule. Le répertoire doit **déjà exister**, sinon le service échoue au
  démarrage avec `226/NAMESPACE`.
* `LogsDirectory=factura` : systemd **crée** `/var/log/factura`, lui donne le
  propriétaire du service et le mode `LogsDirectoryMode=` (0755 par défaut), et
  l'ouvre automatiquement en écriture. Même famille :
  `StateDirectory=` (`/var/lib/`), `CacheDirectory=` (`/var/cache/`),
  `RuntimeDirectory=` (`/run/`, effacé à l'arrêt),
  `ConfigurationDirectory=` (`/etc/`).

C'est `LogsDirectory=` qu'il faut préférer : une seule directive, le répertoire
est créé avec les bons droits, et l'unité devient auto-suffisante — elle
fonctionne sur une machine neuve sans `mkdir` préalable.

c) et d) sont hors sujet : `ProtectHome` ne concerne que `/home`, `/root` et
`/run/user`, et `PrivateTmp` que `/tmp` et `/var/tmp`.
:::

---

**Q8.18** — *Lecture d'une ligne de l'OOM killer dans le journal du noyau.*

**Réponse : b)**

::: pourquoi
Quand le noyau ne peut plus satisfaire une demande d'allocation et qu'il ne
trouve plus rien à récupérer, il déclenche le *OOM killer* : il parcourt les
processus, calcule pour chacun un score de « nuisance » (`oom_score`, visible
dans `/proc/PID/oom_score`) essentiellement proportionnel à la mémoire
**anonyme** consommée, puis envoie un `SIGKILL` au plus mauvais élève.

`SIGKILL`, donc : aucun gestionnaire de signal, aucun `finally`, aucun flush de
tampon, aucun fichier de verrou nettoyé. C'est pour ça qu'un OOM laisse presque
toujours derrière lui un fichier de lock orphelin ou une base à réparer.

Le levier d'administration est `/proc/PID/oom_score_adj`, entre **-1000 et
1000**. Il est ajouté au score en millièmes de la mémoire totale : `+1000` rend
le processus certain d'être choisi, `-1000` l'exclut totalement du massacre. Côté
unité, cela s'écrit `OOMScoreAdjust=` — on met `-500` sur une base de données et
`+500` sur un traitement batch sacrifiable.

Comment savoir après coup qu'il est passé :

```bash
journalctl -k --since '-1 day' | grep -iE 'out of memory|killed process'
dmesg -T | grep -i 'killed process'
systemctl status factura-api          # Result: oom-kill si c'est un service
```

c) est faux ici : un dépassement de `MemoryMax=` déclenche l'OOM killer **du
cgroup**, qui produit une ligne mentionnant le cgroup et fait apparaître
`Result: oom-kill` dans `systemctl status`. Le message donné est celui de l'OOM
killer global, machine entière.
:::

::: piege
Ubuntu 24.04 active aussi `systemd-oomd`, un tueur **en espace utilisateur** qui
s'appuie sur les métriques PSI (`/proc/pressure/memory`) et frappe *avant* le
noyau, à l'échelle du cgroup. Ses décisions apparaissent dans
`journalctl -u systemd-oomd`, pas dans `dmesg`. Si tu ne trouves rien côté noyau
alors qu'un processus a disparu, regarde là.
:::

---

## 8.4 Quiz — questions ouvertes

**QO8.1** — *Naissance et mort d'un processus ; ce qu'est un `<defunct>`.*

Réponse attendue :

1. **`fork()`** est appelé par le **père**. Il crée un fils qui est une copie
   quasi conforme : même code, même mémoire (partagée en copie-sur-écriture),
   mêmes descripteurs ouverts, même répertoire courant. Ce qui change : le PID,
   le PPID (celui du père), les compteurs de temps, et la valeur de retour de
   `fork()` — 0 chez le fils, le PID du fils chez le père. C'est la seule façon
   de créer un processus sous Linux.
2. **`execve()`** est appelé par le **fils**, juste après. Il remplace l'image
   mémoire du processus par un autre programme, **sans changer de PID**. Ce qui
   survit : PID, PPID, descripteurs non marqués `CLOEXEC`, répertoire courant,
   `umask`, limites, et l'environnement passé en argument.
3. Le fils se termine par `exit(code)`. Le noyau libère sa mémoire et ses
   descripteurs, mais **conserve son entrée dans la table des processus** pour y
   garder le code de retour et les statistiques.
4. Le père appelle `wait()` / `waitpid()` et récupère ce code. L'entrée
   disparaît. On dit que le père « récolte » (*reap*) son fils.

Une entrée `<defunct>` est donc exactement l'étape 3 qui dure : le fils est mort,
le père ne l'a pas récolté.

**Orphelin** : cas symétrique. Le père meurt avant le fils. Le fils est
immédiatement **ré-adopté** — son PPID devient 1 (ou celui du plus proche
ancêtre déclaré *subreaper* via `prctl(PR_SET_CHILD_SUBREAPER)`, ce que fait
`systemd --user`). Un orphelin est parfaitement sain, il tourne toujours.

::: pourquoi
Pourquoi un zombie est un problème alors qu'il ne coûte presque rien : le coût
unitaire est d'environ un `task_struct`, quelques kilo-octets, **et un numéro de
PID**. C'est le PID qui est la ressource rare. Un père buggé qui `fork()` en
boucle sans récolter épuise l'espace des PID de la machine ; à partir de là,
plus **aucun** processus ne peut être créé, y compris ceux dont tu as besoin pour
diagnostiquer. C'est une panne à échelle système causée par une ligne manquante
dans un seul programme.

Un zombie est donc moins un problème qu'un **symptôme** : il signale un `wait()`
manquant ou un gestionnaire de `SIGCHLD` absent. On ne « nettoie » pas les
zombies, on corrige le père. Et dans un conteneur, le père est souvent le PID 1
applicatif, qui n'a pas été écrit pour être un init : d'où les options
`--init` de Docker et `tini`/`dumb-init`, dont le seul rôle est d'appeler
`wait()` en boucle.
:::

---

**QO8.2** — *Pourquoi le senior fait la grimace devant `kill -9`.*

Réponse d'entretien attendue, en trois temps.

**Ce que `SIGTERM` déclenche dans une application correctement écrite.** Le
signal est **attrapable** : l'application a installé un gestionnaire. Elle
enchaîne alors ce qu'on appelle un arrêt gracieux :

1. elle cesse d'accepter de nouvelles connexions ou de nouveaux messages ;
2. elle laisse se terminer les requêtes en cours (drainage) ;
3. elle vide ses tampons d'écriture sur disque ;
4. elle ferme proprement ses connexions de base de données, valide ou annule les
   transactions en cours ;
5. elle supprime ses fichiers de verrou, ses sockets UNIX, son fichier de PID ;
6. elle se désinscrit du load balancer ou du registre de services ;
7. elle sort avec le code 0.

**Ce que `SIGKILL` empêche.** Rien de tout cela. `SIGKILL` (comme `SIGSTOP`) ne
peut être ni attrapé, ni bloqué, ni ignoré : le noyau détruit le processus sans
lui rendre la main. Conséquences concrètes : données en tampon perdues,
transactions à moitié écrites, fichiers `.lock` et `.pid` orphelins qui
empêcheront le redémarrage, connexions clientes coupées en plein vol, fils
survivants échappés du contrôle du père.

**Ce que fait `systemctl stop`.** Exactement la bonne séquence, automatiquement :

1. `KillSignal=` (par défaut `SIGTERM`) est envoyé — avec le `KillMode=`
   par défaut `control-group`, à **tous** les processus du cgroup du service ;
2. systemd attend `TimeoutStopSec=` (90 s par défaut, `DefaultTimeoutStopSec=`
   dans `/etc/systemd/system.conf`) ;
3. à l'expiration, et seulement là, `SIGKILL` sur tout ce qui reste
   (`SendSIGKILL=yes` par défaut) ;
4. `systemctl status` affiche alors `Result: timeout`, ce qui laisse une trace.

**La conclusion à formuler** : `kill -9` est un aveu d'échec parce qu'il court-
circuite un mécanisme qui existe déjà et qui fait mieux. Si un service ne s'arrête
pas sur `SIGTERM`, il y a un bug — dans l'application, qui n'écoute pas le signal,
ou dans l'unité, dont le `TimeoutStopSec` est trop long. Le réflexe correct est de
regarder **pourquoi** il ne s'arrête pas (`cat /proc/PID/wchan`, `journalctl -u`),
pas de forcer.

::: piege
Le cas où `kill -9` est légitime existe : un processus en boucle infinie sans
point de sortie, un interpréteur qui a perdu son gestionnaire de signaux, ou un
arrêt d'urgence sur un service non critique dont on assume la perte de données.
Mais on le fait **en connaissance de cause** et on trace la raison. La différence
entre un junior et un senior n'est pas d'interdire `-9`, c'est de savoir ce qu'on
détruit en l'utilisant.
:::

---

**QO8.3** — *`Wants=`, `Requires=`, `BindsTo=`, `After=` : différences et cas réel.*

| Directive | Si l'autre ne démarre pas | Si l'autre s'arrête ensuite | Ordonne ? |
|---|---|---|---|
| `Wants=` | on démarre quand même | rien | non |
| `Requires=` | on ne démarre pas | on est arrêté | non |
| `BindsTo=` | on ne démarre pas | on est arrêté, **quelle qu'en soit la cause** | non |
| `After=` | — | — | oui |

* `Requisite=` complète la famille : n'essaie même pas de démarrer l'autre,
  échoue immédiatement s'il n'est pas déjà actif.
* `PartOf=` propage uniquement `stop` et `restart` du parent vers l'enfant. C'est
  ce qui permet à `systemctl restart nginx` de ne pas redémarrer la moitié de la
  machine.

**Cas réel à raconter en entretien** : un service applicatif qui lit ses données
sur un volume NFS monté par `srv-donnees.mount`.

* Avec `Requires=srv-donnees.mount` : si le montage échoue au boot, le service ne
  démarre pas. Bien. Mais si le NFS **disparaît** plus tard et que le montage
  passe en `inactive`, le comportement dépend de la façon dont le montage a été
  arrêté.
* Avec `BindsTo=srv-donnees.mount` + `After=srv-donnees.mount` : dès que l'unité
  de montage cesse d'être active, **pour n'importe quelle raison**, y compris un
  `umount` sauvage ou la disparition du serveur NFS, le service est arrêté. C'est
  ce qu'on veut : mieux vaut un service arrêté et visible dans le monitoring
  qu'un service qui tourne en écrivant dans un répertoire vide.

`BindsTo=` est aussi le bon choix pour un service attaché à un périphérique
(`.device`) : débrancher le matériel arrête le service.

::: pourquoi
Le point qu'il faut absolument formuler : **la dépendance et l'ordre sont
orthogonaux**. `Requires=` sans `After=` démarre les deux en parallèle (Q8.16), ce
qui est presque toujours un bug. Inversement, `After=` sans `Requires=`/`Wants=`
est parfaitement légitime : « si l'autre est là, passe après lui ; s'il n'est pas
là, tant pis ». C'est ce qu'on écrit pour `After=network-online.target` quand on
sait tolérer un réseau absent.

Piège à ne pas oublier : `After=` s'inverse à l'arrêt. `A After=B` signifie « A
démarre après B » **et** « A s'arrête avant B ». systemd déduit l'ordre d'arrêt
de l'ordre de démarrage, sans qu'on ait à l'écrire.
:::

---

**QO8.4** — *Démon auto-détaché déclaré `Type=simple` ; matrice des cinq `Type=`.*

Ce qui se passe : voir Q8.7 — le processus initial sort, systemd croit le service
terminé, et le `KillMode=control-group` par défaut tue le démon détaché qui est
resté dans le cgroup. Le service est mort avant même d'avoir servi.

Matrice de décision :

| `Type=` | Le démarrage est terminé quand… | Pour quelle application |
|---|---|---|
| `simple` | le `fork()` a réussi | historique ; à ne plus utiliser |
| `exec` | le `execve()` a réussi | tout programme qui reste au premier plan |
| `forking` | le processus **initial** sort | démon historique qui se détache |
| `oneshot` | le processus a **fini** | traitement ponctuel, migration, init |
| `notify` | l'application a envoyé `READY=1` | service qui a une phase d'init longue |

Détails qui font la différence :

* `forking` exige `PIDFile=` en pratique : sans lui, systemd devine le processus
  principal en inspectant le cgroup, et se trompe dès qu'il y a plusieurs
  processus. Le chemin doit être sous `/run/`, et `RuntimeDirectory=` est le
  moyen propre de faire créer ce répertoire par systemd.
* `oneshot` va presque toujours avec `RemainAfterExit=yes`, accepte plusieurs
  `ExecStart=` séquentiels, et refuse `Restart=always`.
* `notify` exige que l'application appelle `sd_notify(0, "READY=1")`. Une variante
  `Type=notify-reload` (systemd 253+) fait la même chose pour `reload`.
  `NotifyAccess=main` (défaut) n'accepte la notification que du processus
  principal ; `NotifyAccess=all` l'accepte de n'importe quel processus du cgroup.

::: pourquoi
La vraie question derrière `Type=` est : **comment systemd sait-il que le service
est prêt ?** Cette information ne sert pas qu'à l'affichage : elle conditionne le
déclenchement de toutes les unités qui déclarent `After=`. Un `Type=` mal choisi
ne casse donc pas seulement ce service, il casse l'ordonnancement de tout ce qui
en dépend.

Démonstration reproductible : avec `FACTURA_DELAI_PRET=10`, en `Type=exec`,
`systemctl start` rend la main en 50 ms et une unité `After=` démarre aussitôt —
alors que le port n'est pas encore ouvert. En `Type=notify`, `systemctl start`
prend 10 secondes et ne rend la main qu'une fois `READY=1` reçu : l'unité
suivante trouve un service réellement opérationnel. C'est toute la différence
entre « le processus tourne » et « le service est disponible ».
:::

---

**QO8.5** — *Méthode complète de diagnostic d'un service qui ne démarre pas.*

Démarche attendue, dans l'ordre, avec ce qu'on cherche :

1. **`systemctl status <unité> -l --no-pager`** — la commande qui répond à 80 %
   des cas. Ce qu'on lit :
   * ligne `Loaded:` — `not-found` (nom ou `daemon-reload` oublié), `masked`
     (BF8.3), `bad-setting` (directive invalide) ; et le **chemin** du fichier
     chargé ;
   * ligne `Active:` — `failed (Result: exit-code)`, `(Result: timeout)`,
     `(Result: start-limit-hit)`, `(Result: oom-kill)`, `(Result: resources)` :
     chacun oriente vers une famille de causes différente ;
   * ligne `Process:` — le `code=exited, status=NNN` : `203/EXEC`, `200/CHDIR`,
     `217/USER`, `226/NAMESPACE`, ou un code applicatif ;
   * les dernières lignes de journal affichées en dessous.
2. **`systemctl cat <unité>`** — la configuration **réellement appliquée**,
   drop-ins compris, chaque fragment précédé de son chemin en commentaire. C'est
   l'étape que tout le monde saute et qui révèle les surcharges oubliées (BF8.4).
   Complément : `systemctl show <unité>` pour la valeur effective d'une directive,
   et `systemd-delta` pour l'inventaire des surcharges de la machine.
3. **`journalctl -u <unité> -n 50 --no-pager`** (ou `-b` pour le boot courant) —
   le message de l'application elle-même, celui que `status` tronque. Le module 13
   traite le reste.
4. **`systemd-analyze verify /etc/systemd/system/<unité>`** — syntaxe, directives
   inconnues ou mal orthographiées, dépendances vers des unités inexistantes.
   Point capital : une directive mal orthographiée est **ignorée en silence** par
   systemd au chargement ; `verify` est le seul moyen de l'attraper.
5. **Reproduire à l'identique** — et non « lancer la commande dans mon shell »,
   qui ne prouve rien puisque l'environnement diffère :

```bash
sudo systemd-run --uid=factura --gid=factura --pty \
  --property=EnvironmentFile=/etc/factura/api.env \
  /opt/factura/bin/factura-api.py
```

6. **Les causes classiques, dans l'ordre de fréquence** :
   * `daemon-reload` oublié → `Unit not found` ;
   * unité **masquée** → `Unit is masked`, confirmé par
     `systemctl list-unit-files --state=masked` ;
   * binaire absent, non exécutable, ou shebang invalide → `203/EXEC` ;
     `ls -l`, `head -1`, `file` sur le binaire ;
   * `User=` inexistant → `217/USER` ; `getent passwd factura` ;
   * `WorkingDirectory=` absent → `200/CHDIR` ;
   * `EnvironmentFile=` manquant → `Failed to load environment files`,
     `Result: resources` ; corrigé par le préfixe `-` si l'absence est tolérable ;
   * **port déjà pris** → l'application sort d'elle-même ;
     `ss -tulpn | grep :8080` donne le coupable, souvent l'instance précédente
     lancée à la main dans un `tmux` ;
   * **isolation trop stricte** → `226/NAMESPACE`, ou une erreur d'écriture
     `Read-only file system` ; on bissecte en commentant les directives
     `Protect*` une à une, ou en les neutralisant dans un drop-in temporaire ;
   * droits : `namei -l /srv/factura/data`, `sudo -u factura test -w <chemin>`.
7. **Boucler** : après correction, `systemctl reset-failed <unité>` (obligatoire
   si `start-limit-hit`), puis `systemctl start`, puis `systemctl is-active`.

::: pourquoi
Ce qui structure cette méthode, c'est qu'elle va du **plus général au plus
précis**, et surtout qu'elle sépare trois questions qu'on mélange sous pression :

* *quelle configuration s'applique ?* → `systemctl cat`, `systemctl show`
* *qu'a tenté systemd ?* → `systemctl status`, le code de sortie
* *qu'a dit l'application ?* → `journalctl -u`

Les trois répondent à des choses différentes, et 90 % des diagnostics qui
s'enlisent viennent d'avoir répondu à la deuxième en croyant répondre à la
première. Un code `203/EXEC` ne vient pas de l'application : elle n'a jamais
démarré. Un code `1` vient d'elle : inutile de relire l'unité.
:::

---

**QO8.6** — *`nohup`/`disown` contre `tmux` contre `systemd-run`.*

| Critère | `nohup` / `disown` | `tmux` | `systemd-run` |
|---|---|---|---|
| Survit au `SIGHUP` | oui | oui | oui (sans rapport) |
| Sorties | `nohup.out` ou redirection | dans le terminal virtuel | journal systemd |
| Reprendre la main | non | oui, `tmux attach` | non (lecture seule) |
| Visible par un tiers | `ps` seulement | `tmux ls` du même compte | `systemctl status` |
| Limites de ressources | héritées de la session | héritées de la session | cgroup dédié |

**Ce qui survit exactement** :

* `nohup` : le processus ignore `SIGHUP`. Il reste dans la session de ton shell.
  Si quelqu'un tue la session (`pkill -s <SID>`), il meurt.
* `tmux` : le serveur `tmux` est lui-même détaché (il tourne dans sa propre
  session, lancé au premier `tmux new`). Tes processus sont ses enfants. Ton SSH
  peut mourir cent fois, le serveur `tmux` ne le sait même pas.
* `systemd-run` : le processus n'est pas ton enfant du tout. C'est PID 1 qui l'a
  lancé, dans une unité transitoire nommée. Il a son cgroup, ses limites, ses
  journaux, et il survit à tout sauf à l'arrêt de la machine.

**Choix d'exploitation** :

* opération **interactive** (une migration qui pose des questions, un `psql`, un
  `apt dist-upgrade` qui demande confirmation) → `tmux`, sans hésiter. C'est la
  seule méthode qui permet de reprendre la main ;
* opération **non interactive** qui doit laisser une trace auditable, être visible
  par toute l'équipe et se comporter comme un service → `systemd-run` ;
* `nohup` → dépannage rapide sur une machine où `tmux` n'est pas installé. Pas une
  méthode de production.

::: pourquoi
La différence de fond n'est pas « qui survit » — les trois survivent — mais
**qui est le père**. Avec `nohup`, le père est ton shell : tu restes dans le même
arbre de processus, la même session, le même cgroup de session utilisateur (donc
les mêmes limites, et une purge du cgroup de session t'emporte). Avec `tmux`, le
père est le serveur `tmux`, qui appartient à ton compte. Avec `systemd-run`, le
père est PID 1.

Vérifie-le toi-même : `ps -o pid,ppid,sid,cmd -p <pid>` avant et après. Le
changement de `SID` (identifiant de session) est la signature du détachement
réel. C'est aussi pourquoi `systemd-run` est la seule méthode qui rende
l'opération visible et pilotable par un collègue : elle existe dans le référentiel
de systemd, pas seulement dans ta session.
:::

---

**QO8.7** — *Diagnostic d'une limite de descripteurs.*

Démarche :

1. **Confirmer la limite effective du processus en cours** — jamais celle de ton
   shell :

```bash
PID=$(systemctl show -p MainPID --value factura-api)
grep 'Max open files' /proc/$PID/limits
# Max open files    1024    524288    files
#                   souple  stricte
```

2. **Compter ce qu'il consomme réellement** :

```bash
ls /proc/$PID/fd | wc -l
lsof -p $PID | wc -l          # inclut aussi les fichiers mappés
```

   Un écart croissant dans le temps signale une **fuite de descripteurs** ; une
   valeur stable proche du plafond signale une limite mal dimensionnée. Ce n'est
   pas la même panne et ce n'est pas le même correctif.

3. **Poser la limite au bon endroit**, selon le lanceur :

| Lancé par | Où poser la limite |
|---|---|
| session SSH / `login` | `/etc/security/limits.conf` (`soft` **et** `hard`) |
| cron | `ulimit -n` en tête du script, ou `systemd-run` |
| systemd | `LimitNOFILE=65536` dans l'unité |
| conteneur | `--ulimit nofile=65536:65536`, ou le `LimitNOFILE` du démon |

4. **Pourquoi `ulimit -n 65536` dans ton shell ne change rien** : `setrlimit()`
   agit sur le **processus appelant** et est hérité par ses enfants — uniquement
   par ses enfants. Ton shell n'est pas l'ancêtre du service : c'est PID 1 qui l'a
   lancé. Tu modifies les limites de ton shell et de ce que tu lances depuis lui,
   rien d'autre. C'est exactement pour cela que « ça marche quand je le lance à la
   main » : à la main, le processus hérite **de ta session**.

::: pourquoi
Le mécanisme sous-jacent est celui de l'héritage : chaque processus hérite des
`rlimit` de son père au moment du `fork()`, et `execve()` les conserve. Il n'y a
aucun endroit central où « la limite de la machine » serait définie. Il y a
autant de limites que de chaînes d'héritage :

```text
noyau
 └─ PID 1 (systemd ; DefaultLimitNOFILE de system.conf)
     ├─ services            -> LimitNOFILE= de chaque unité
     └─ sshd
         └─ session PAM     -> pam_limits, limits.conf
             └─ ton shell   -> et tout ce que tu lances depuis lui
```

Poser la limite au mauvais endroit de cet arbre ne change rien, et c'est
indétectable tant qu'on lit des fichiers de configuration au lieu de lire
`/proc/PID/limits`. La règle : **on ne conclut jamais d'un fichier de conf, on
conclut du processus**.
:::

---

**QO8.8** — *Ce que protège chaque directive de durcissement.*

| Directive | Mécanisme | Ce qu'elle empêche |
|---|---|---|
| `NoNewPrivileges=yes` | `prctl(PR_SET_NO_NEW_PRIVS)` | l'exécution d'un binaire SUID/SGID ou porteur de capabilities ne donne plus rien : le compte de service compromis ne peut plus passer root via `sudo`, `pkexec` ou un SUID oublié |
| `ProtectSystem=strict` | espace de noms de montage en lecture seule | l'écriture d'une porte dérobée dans `/usr/local/bin`, la modification d'un binaire, l'ajout d'une clé dans `/etc` |
| `PrivateTmp=yes` | `/tmp` et `/var/tmp` privés (tmpfs) | les attaques par lien symbolique sur fichier temporaire prévisible, et la fuite de données entre services via `/tmp` |
| `DynamicUser=yes` | UID alloué à la volée (61184–65519) | tout ce qui reposerait sur un UID stable : pas de fichier persistant possédé par le service, pas de porte dérobée qui survit au redémarrage |
| `CapabilityBoundingSet=` | vide l'ensemble de capabilities | même en tournant en root, le service ne peut plus charger de module, changer d'UID, ouvrir un port privilégié ou lire un fichier arbitraire |

Ce que mesure `systemd-analyze security` : il inspecte une quarantaine de
directives d'isolation, attribue à chacune un poids selon l'exposition qu'elle
laisse ouverte, et en tire un score de 0.0 (isolé) à 10.0 (exposé), assorti d'une
appréciation (`OK`, `MEDIUM`, `EXPOSED`, `UNSAFE`). Il fonctionne aussi
hors-ligne sur un fichier, avec `--offline=true`.

Pourquoi le score seul ne suffit pas :

* c'est une mesure de **surface d'attaque**, pas de risque. Un service inoffensif
  noté 9.0 est moins grave qu'un service exposé sur Internet noté 4.0 ;
* certaines directives font chuter le score sans rien protéger dans le contexte
  réel (`ProtectHome` sur une machine sans utilisateurs humains) ;
* la directive qui compte le plus n'est pas notée : ce que fait l'application ;
* et un durcissement mal testé casse le service. `226/NAMESPACE` un dimanche à
  3 h du matin coûte plus cher que trois points de score.

::: pourquoi
Le mécanisme commun à `ProtectSystem`, `ProtectHome`, `PrivateTmp`,
`ProtectProc` et `RuntimeDirectory` est le même : systemd crée pour le service un
**espace de noms de montage** privé (`CLONE_NEWNS`), y remonte certains chemins en
lecture seule ou les remplace par du vide, puis exécute le binaire dedans. Rien
n'est modifié pour le reste du système : deux services peuvent avoir deux vues
différentes du même disque. C'est la même primitive noyau que celle qu'utilisent
les conteneurs — systemd la rend simplement accessible par une ligne de
configuration.

`NoNewPrivileges` et `CapabilityBoundingSet` relèvent d'une autre famille : ils
ne cachent rien, ils **retirent des droits de façon irréversible** pour le
processus et toute sa descendance. C'est pourquoi ils ne coûtent rien en
performance et ne cassent presque jamais rien : on peut les poser d'abord, et
s'attaquer aux `Protect*` ensuite.
:::

---

**QO8.9** — *45 s d'arrêt à chaque restart, boot passé de 12 à 70 s.*

Le lien : à l'arrêt de la machine, systemd arrête **toutes** les unités en
respectant l'ordre inverse de `After=`. Un service qui met 45 s à s'arrêter met
45 s à s'arrêter au shutdown aussi, et si d'autres unités attendent derrière lui
dans la chaîne d'ordonnancement, le temps s'additionne. Un boot qui semble lent
est souvent un **shutdown** lent du cycle précédent, ou une unité qui bloque la
chaîne critique au démarrage.

Directives en cause :

* `TimeoutStopSec=` (défaut : `DefaultTimeoutStopSec=90s` dans
  `/etc/systemd/system.conf`). Une valeur de 45 s exactement sent le
  `TimeoutStopSec=45` explicite ; une valeur de 90 s pile sent le défaut atteint.
* `KillSignal=` / `KillMode=` : si `KillMode=none` ou `process`, les fils ne
  reçoivent rien et traînent jusqu'au `SIGKILL` final.
* `ExecStop=` qui lance une commande qui ne rend pas la main.
* `Restart=` + `RestartSec=` élevé, qui allonge un `restart` sans rapport avec
  l'arrêt.

Démarche pour trancher :

```bash
systemd-analyze                  # firmware, loader, kernel, userspace
systemd-analyze blame | head -20 # les unités les plus lentes
systemd-analyze critical-chain   # la chaîne qui a vraiment compté
systemctl show -p TimeoutStopUSec,KillMode,ExecStop factura-api
time systemctl stop factura-api     # mesure directe
journalctl -u factura-api | grep -i 'stop\|timeout\|killed'
```

Ce qu'on cherche : la ligne
`factura-api.service: State 'stop-sigterm' timed out. Killing.` prouve que
l'application n'a pas répondu au `SIGTERM` et que systemd a attendu le timeout
entier. La cause est alors dans l'application (pas de gestionnaire de signal), pas
dans l'unité — baisser `TimeoutStopSec` ne ferait que masquer le problème en
détruisant les données plus tôt.

::: pourquoi
Distinction essentielle que `blame` ne fait pas : il liste les unités par durée
d'initialisation, y compris celles qui se sont initialisées **en parallèle** et
n'ont donc rien retardé du tout. `critical-chain` montre au contraire la chaîne de
dépendances qui a réellement déterminé la durée du boot, avec les temps cumulés
(`+` = durée propre, `@` = instant d'achèvement). C'est sur cette chaîne, et sur
elle seule, qu'il faut travailler.

`systemd-analyze blame` est le graphique qu'on montre au chef ;
`critical-chain` est celui sur lequel on agit.
:::

---

## 8.5 Exercices guidés

**E8.1** — *Les 10 processus les plus gourmands en mémoire résidente.*

```bash
ps -eo pid,ppid,user,stat,ni,rss,args --sort=-rss | head -11
```

::: pourquoi
`--sort=-rss` est une extension de `ps` procps : le tri est fait par `ps`
lui-même, sur la valeur numérique, avant le formatage. Passer par
`sort -k6 -rn` casse dès qu'une ligne de commande contient des espaces ou que la
colonne se décale — et ça arrive tout le temps.

`head -11` et non `head -10` : la première ligne est l'en-tête. Pour un usage en
script, `--no-headers` supprime l'en-tête et on revient à `head -10`.

`args` (synonyme `cmd`) donne la **ligne de commande complète**, lue dans
`/proc/PID/cmdline`. `comm` donne le nom court du binaire, lu dans
`/proc/PID/stat`, tronqué à 15 caractères — c'est pourquoi tous tes scripts
Python apparaissent comme `python3` avec `comm`, et sont indiscernables. Pour
identifier un processus, c'est toujours `args`.
:::

::: piege
`RSS` (*resident set size*) compte les pages réellement en RAM, **y compris les
pages partagées**, et les compte **pour chaque processus qui les partage**.
Additionner les `RSS` de 40 processus `nginx` donne un total très supérieur à la
mémoire réellement consommée. Pour une vraie mesure par service, il faut
`systemd-cgtop` ou `memory.current` du cgroup, qui comptent une page une seule
fois. `smem` ou `/proc/PID/smaps_rollup` donnent le `PSS`, qui répartit les pages
partagées au prorata.
:::

---

**E8.2** — *Tout savoir sur le processus qui écoute sur 8080, uniquement via `/proc`.*

```bash
PID=$(ss -tlnp 'sport = :8080' | awk -F'pid=' 'NR>1 {print $2+0}')
tr '\0' ' ' < /proc/$PID/cmdline; echo      # ligne de commande lisible
ls -l /proc/$PID/cwd                        # répertoire courant
ls -l /proc/$PID/exe                        # binaire réellement exécuté
ls /proc/$PID/fd | wc -l                    # descripteurs ouverts
```

::: pourquoi
`/proc/PID/cmdline` contient les arguments séparés par des octets **nuls**, pas
par des espaces : c'est le tableau `argv` tel que le noyau l'a reçu. `cat` affiche
donc tout collé. `tr '\0' ' '` (ou `tr '\0' '\n'` pour un argument par ligne) le
rend lisible. L'avantage sur `ps` : aucune troncature, aucun reformatage.

`exe` et `cwd` sont des **liens symboliques magiques** : le noyau les résout à la
volée vers l'inode réel. Deux conséquences très utiles en incident :

* si le binaire a été supprimé ou remplacé pendant que le processus tournait,
  `ls -l /proc/PID/exe` affiche `/opt/factura/bin/factura-api.py (deleted)` —
  c'est la preuve qu'un déploiement a eu lieu sans redémarrage du service ;
* on peut **récupérer** un binaire supprimé mais encore en cours d'exécution avec
  `cp /proc/PID/exe /tmp/recup`. Même chose pour un fichier de log supprimé encore
  ouvert : `cp /proc/PID/fd/3 /tmp/recup.log`, ce qui sauve la journée quand
  quelqu'un a fait `rm` sur un journal actif.

`/proc/PID/environ` complète le tableau, avec le même séparateur nul : c'est là
qu'on vérifie qu'un `EnvironmentFile=` a bien été pris en compte. Il n'est
lisible que par le propriétaire du processus et par root.
:::

---

**E8.3** — *Ascendance complète du `sshd` de ta session.*

```bash
pstree -paus $$
```

Sortie typique sur `lab-web` :

```text
systemd,1
  └─sshd,912
      └─sshd,4188
          └─sshd,4271,mathieu
              └─bash,4272
                  └─pstree,4410 -paus 4272
```

::: pourquoi
Les options : `-p` affiche les PID, `-a` les arguments, `-u` signale les
**changements d'utilisateur** (c'est le `,mathieu` dans la sortie), et `-s`
remonte l'ascendance au lieu de descendre. `$$` est le PID du shell courant.

Ce que l'arbre raconte : trois `sshd` empilés, et c'est normal. Le premier (912)
est le démon d'écoute, lancé par systemd, qui tourne en root. Le deuxième (4188)
est le processus **privilégié** qui gère la connexion. Le troisième (4271) est le
processus **non privilégié** qui a abandonné ses droits après authentification —
d'où le `,mathieu` que `-u` met en évidence. C'est la *privilege separation*
d'OpenSSH : le code qui parle au réseau ne tourne jamais en root.

L'utilité en incident : un processus dont l'ascendance remonte à `cron` ou à
`systemd` directement n'a pas le même environnement qu'un processus lancé depuis
un shell interactif. `pstree -s` répond en une commande à « qui a lancé ça ? »,
là où `ps -ef` oblige à remonter les `PPID` à la main.
:::

---

**E8.4** — *Compter les processus par état.*

```bash
ps -eo stat --no-headers | cut -c1 | sort | uniq -c | sort -rn
```

```text
    142 S
      9 I
      3 R
      1 Z
```

::: pourquoi
`cut -c1` ne garde que le **premier caractère** de la colonne `STAT`, parce que
`ps` y accole des modificateurs qui ne sont pas des états : `Ssl` = *sleeping*,
*session leader*, *multi-threaded* ; `R+` = *running* dans le groupe de premier
plan ; `S<` = *sleeping* avec un nice négatif. Sans le `cut`, on compterait
séparément `S`, `Ss`, `Ssl` et `S<`, ce qui n'a aucun intérêt.

Ce qu'on regarde vraiment dans cette sortie : le nombre de `D` et de `Z`. Une
poignée de `R` est normale ; `S` domine toujours. Un `D` persistant ou un `Z`
qui augmente sont les deux seuls signaux d'alarme.

`I` (*idle kernel thread*) est apparu avec les noyaux 4.14 : ce sont des threads
noyau au repos, comptés à part précisément pour ne plus polluer la charge
moyenne. Ils ne t'intéressent jamais.
:::

---

**E8.5** — *Fabriquer un zombie, constater, faire disparaître.*

```bash
/opt/factura/bin/factura-zombie.py 120 &
# pere=5120  fils zombie=5121  (pendant 120s)

ps -o pid,ppid,stat,comm -p 5121
#   PID  PPID STAT COMMAND
#  5121  5120 Z    python3

kill -9 5121 ; sleep 1 ; ps -o pid,stat -p 5121   # toujours Z

kill 5120                                        # on tue le PERE
sleep 1 ; ps -o pid -p 5121                       # plus rien
```

::: pourquoi
Le `-9` sur 5121 ne produit rien parce qu'il n'y a plus personne pour le
recevoir : le processus 5121 n'exécute plus une seule instruction depuis son
`exit(0)`. Le noyau accepte le signal, le met en file, et la file ne sera jamais
lue.

Tuer le père produit l'effet en **deux temps**, qu'il faut savoir raconter :

1. le père meurt, le zombie devient orphelin ;
2. le noyau le **ré-adopte** immédiatement : son PPID passe à 1 ;
3. systemd, dont la boucle principale appelle `waitpid()` en permanence, le
   récolte dans la milliseconde.

Ce n'est donc pas la mort du père qui « nettoie » le zombie, c'est le fait que
PID 1 devienne son nouveau père et fasse le travail que le vrai père ne faisait
pas. Vérification en direct : `kill -STOP <pere>` puis `ps -o ppid -p <zombie>`
avant et après la mort du père.
:::

---

**E8.6** — *Déprioriser une charge CPU en cours, puis tenter de remonter.*

```bash
/opt/factura/bin/factura-charge.sh 2 &
pgrep -af factura-charge.sh
for p in $(pgrep -f factura-charge.sh); do renice -n 15 -p "$p"; done
top -o %CPU          # colonne NI : 15 ; colonne PR : 35
renice -n 0 -p <pid>
# renice: failed to set priority for 5200 (process ID): Permission denied
```

::: pourquoi
Trois mécanismes à comprendre ici.

**Pourquoi il faut renicer chaque processus** : `renice -p` agit sur un PID. Les
fils déjà créés ont hérité du nice du père **au moment de leur `fork()`** ;
changer le nice du père après coup ne les suit pas. Pour traiter un arbre entier :
`renice -n 15 -g <PGID>` (groupe de processus) ou `renice -n 15 -u factura`.

**Les colonnes de `top`** : `NI` est la valeur de politesse, de -20 à 19.
`PR` est la priorité interne de l'ordonnanceur, qui vaut `20 + NI` pour les tâches
normales — d'où `PR=35` pour `NI=15`. `PR=rt` signale une tâche temps réel, qui
passe avant toutes les autres.

**Pourquoi on ne peut pas remonter** : le nice est une valeur à **cliquet**. Un
processus non privilégié ne peut qu'augmenter sa propre valeur (devenir plus
poli), jamais la diminuer, même pour revenir à une valeur qu'il avait avant.
Seul root, ou un processus disposant de `CAP_SYS_NICE`, peut descendre. La raison
est évidente : sans cela, n'importe quel utilisateur se mettrait en `-20` et
monopoliserait la machine. La limite par utilisateur se règle dans
`limits.conf` (`priority`) ou par unité (`Nice=`).
:::

::: piege
Sous l'ordonnanceur CFS, le nice n'est **pas** un pourcentage de CPU : c'est un
poids. Chaque niveau multiplie le poids par environ 1,25, soit un facteur 10 entre
deux processus séparés de 10 niveaux. Et surtout, le nice n'a d'effet **qu'en cas
de contention** : sur une machine qui a du CPU libre, un processus en `NI=19`
consomme autant qu'un processus en `NI=0`. Renicer un processus sur une machine
non saturée ne change strictement rien, ce qui déçoit beaucoup de monde.
:::

---

**E8.7** — *Classe d'E/S « idle » et ordonnanceur de bloc.*

```bash
PID=$(pgrep -f factura-charge.sh | head -1)
sudo ionice -c3 -p "$PID"
ionice -p "$PID"
# idle
cat /sys/block/sda/queue/scheduler
# none [mq-deadline]
```

::: pourquoi
`ionice` pose une classe et une priorité d'E/S sur le processus :

| Classe | Nom | Effet |
|---|---|---|
| 1 | *realtime* | sert en premier, peut affamer le reste (root seulement) |
| 2 | *best-effort* | classe par défaut, priorité 0 (haute) à 7 (basse) |
| 3 | *idle* | ne sert que quand plus personne ne demande d'E/S |

Le point que la plupart des gens ignorent : **cette classe n'est respectée que par
certains ordonnanceurs de bloc**. Historiquement, seul CFQ l'honorait ;
aujourd'hui, c'est **BFQ**. `mq-deadline` et `none` — ce dernier étant le défaut
sur NVMe et sur la plupart des VM — **ignorent complètement** `ionice`.

Sur `lab-web`, avec `mq-deadline`, ta commande `ionice` réussit, la classe est
bien enregistrée sur le processus… et n'a aucun effet observable. Pour la rendre
effective :

```bash
echo bfq | sudo tee /sys/block/sda/queue/scheduler
```

La bonne réponse moderne pour limiter les E/S d'un service n'est d'ailleurs plus
`ionice` mais le contrôleur `io` de cgroup v2, exposé par systemd :
`IOWeight=`, `IOReadBandwidthMax=/dev/sda 10M`, `IOReadIOPSMax=`. Ce sont des
limites dures, indépendantes de l'ordonnanceur.
:::

---

**E8.8** — *`SIGHUP` puis `SIGTERM` sur l'API, et le cas `FACTURA_SOURD=1`.*

```bash
sudo -u factura /opt/factura/bin/factura-api.py &
PID=$(curl -s http://127.0.0.1:8080/sante | sed 's/.*pid=\([0-9]*\).*/\1/')
kill -HUP  "$PID"
kill -TERM "$PID"
tail -4 /var/log/factura/api.log
```

```text
2026-09-18 14:22:03 [6120] en ecoute sur 0.0.0.0:8080
2026-09-18 14:22:31 [6120] SIGHUP recu — rechargement de la configuration
2026-09-18 14:22:44 [6120] SIGTERM recu — arret demande
2026-09-18 14:22:44 [6120] arret propre, sortie 0
```

Avec `FACTURA_SOURD=1` :

```text
2026-09-18 14:25:10 [6230] SIGTERM recu — IGNORE (FACTURA_SOURD=1)
```

Le processus reste vivant. Seul `kill -9` en vient à bout, sans ligne « arret
propre » dans le journal.

::: pourquoi
La différence entre les deux exécutions est **dans l'application**, pas dans le
signal. `SIGTERM` est attrapable : l'application choisit ce qu'elle en fait. Dans
le premier cas, elle arrête d'accepter les connexions, vide ses tampons et sort
en 0. Dans le second, son gestionnaire se contente de journaliser et de rendre la
main : l'exécution continue.

C'est exactement ce que fait une application mal écrite qui « ne s'arrête pas ».
Vue de systemd, la séquence devient : `SIGTERM` → rien ne bouge → attente de
`TimeoutStopSec` → `SIGKILL` → `Result: timeout` dans le status. Le service finit
par s'arrêter, mais violemment, et 20 à 90 secondes plus tard.

Deux détails qui comptent : `SIGHUP` n'a de sens de « recharge la configuration »
que par **convention** — rien dans le noyau ne l'impose, c'est une tradition
héritée de l'époque où un démon n'avait plus de terminal et pouvait donc
réutiliser librement ce signal. Et `ExecReload=/bin/kill -HUP $MAINPID` dans une
unité ne fait rien d'autre que ce que tu viens de taper à la main.
:::

---

**E8.9** — *`SIGHUP` à tous les `factura-api` de l'utilisateur `factura`.*

```bash
pgrep -a -u factura -f 'factura-api'        # d'abord VOIR
sudo pkill --signal HUP -u factura -f 'factura-api'
```

::: pourquoi
`pgrep` et `pkill` partagent exactement la même syntaxe de sélection : c'est
volontaire, et c'est le seul garde-fou fiable. On écrit la sélection avec
`pgrep -a` (qui affiche la ligne de commande complète), on lit la liste, puis on
remplace `pgrep` par `pkill` sans toucher aux critères.

Les options de sélection à connaître : `-u` par utilisateur **effectif**
(`-U` pour l'utilisateur réel), `-f` pour chercher dans la **ligne de commande
complète** et non dans le seul nom du binaire, `-x` pour exiger une
correspondance exacte, `-n`/`-o` pour le plus récent / le plus ancien,
`-P` par PID du père.

`-f` est indispensable ici : sans lui, `pgrep` ne compare qu'au nom court du
processus, tronqué à 15 caractères — pour un script Python, ce nom est `python3`,
et tu ne peux rien distinguer.
:::

::: piege
`pkill -f java` est la commande qui a fait tomber le plus de productions de
l'histoire. `-f` cherche une **sous-chaîne** dans la ligne de commande complète :
elle correspond à toutes les JVM de la machine, et aussi à `vim /tmp/java.conf`
et à l'éditeur du collègue. Trois protections cumulables : `pgrep -a` d'abord,
toujours ; `-x` ou une expression ancrée (`pkill -f '^/opt/factura/bin/'`) ; et
sur un service, ne pas utiliser `pkill` du tout mais `systemctl kill -s HUP
factura-api`, qui ne touche que le cgroup du service.
:::

---

**E8.10** — *Cycle complet des jobs du shell.*

```bash
sleep 600                 # premier plan
# Ctrl-Z
# [1]+  Stopped                 sleep 600
bg %1                     # reprend en arriere-plan
jobs -l
# [1]+  6401 Running                 sleep 600 &
fg %1                     # ramene au premier plan
# Ctrl-C  (ou, sans le ramener : kill %1)

sleep 600 &
disown -h %1              # survit a la fermeture du shell
# ou, des le depart :
setsid --fork sleep 600 </dev/null >/dev/null 2>&1
```

::: pourquoi
Ce qui se passe réellement à chaque étape, en termes de **groupes de processus** :

* `Ctrl-Z` fait envoyer par le pilote de terminal un `SIGTSTP` au groupe de
  processus **de premier plan**. Le processus passe en état `T`.
* `bg %1` envoie `SIGCONT` et laisse le groupe en arrière-plan. Il tourne, mais
  s'il tente de **lire** sur le terminal il recevra `SIGTTIN` et se rendormira.
* `fg %1` envoie `SIGCONT` **et** redonne au groupe le statut de groupe de premier
  plan du terminal, via `tcsetpgrp()`.
* `kill %1` : le `%1` est développé par bash en `-<PGID>`, donc le signal part au
  **groupe entier**, pas au seul processus principal. C'est pour ça que `kill %1`
  tue toute une pipeline alors que `kill <pid>` n'en tuerait qu'un maillon.

`jobs` n'existe que dans le shell qui a créé les jobs : la table est en mémoire,
propre à ce bash. Un autre terminal ne la voit pas, et `jobs` ne sert donc à rien
en script.

`disown -h %1` marque le job « ne pas lui relayer `SIGHUP` » mais le laisse dans
la table ; `disown %1` l'en retire complètement (il devient invisible de `jobs` et
de `fg`) ; `disown -a` traite tous les jobs.
:::

---

**E8.11** — *Session `tmux` détachable entre `lab-adm` et `lab-web`.*

```bash
# sur lab-adm
ssh mathieu@10.10.10.11

# sur lab-web
tmux new -s migration
/opt/factura/bin/factura-charge.sh 1
ps -o pid,ppid,sid,cmd -p $(pgrep -f factura-charge.sh | head -1)
# Ctrl-b puis d           -> detache

exit                      # on coupe le SSH

# depuis lab-adm, on revient
ssh mathieu@10.10.10.11
tmux ls
# migration: 1 windows (created Fri Sep 18 15:02:11 2026)
tmux attach -t migration
```

::: pourquoi
Le PPID du processus ne change pas entre avant et après la coupure : il reste
celui du shell de `tmux`. Ce qui change, c'est que ce shell n'a **jamais** eu ton
`sshd` pour ancêtre. Le premier `tmux new` a démarré un **serveur `tmux`**, un
démon détaché qui tourne dans sa propre session (`setsid`), et le client `tmux`
de ton terminal ne fait que lui parler par une socket UNIX dans
`/run/user/1000/tmux-1000/`.

Quand ton SSH tombe, seul le **client** meurt. Le serveur, ses fenêtres et tes
processus n'ont rien vu passer : ils n'ont pas de terminal de contrôle lié à ta
connexion, donc aucun `SIGHUP` ne leur parvient.

Vérifie l'ancestralité : `pstree -s <pid>` remonte à `tmux: server` puis à
`systemd`, jamais à `sshd`. C'est la preuve visuelle du découplage.

Les trois raccourcis à connaître, préfixe `Ctrl-b` : `d` détache, `c` crée une
fenêtre, `"` et `%` divisent le panneau. Et `tmux new -s nom` plutôt que `tmux`
tout court : une session nommée se retrouve, une session anonyme s'appelle `0` et
se perd dès qu'il y en a deux.
:::

---

**E8.12** — *Limite effective de descripteurs du processus `factura-api`.*

```bash
PID=$(systemctl show -p MainPID --value factura-api)
grep 'Max open files' /proc/$PID/limits
# Max open files            65536      65536      files
ulimit -Sn ; ulimit -Hn
# 1024
# 1048576
ls /proc/$PID/fd | wc -l
```

::: pourquoi
Les deux colonnes de `/proc/PID/limits` sont la limite **souple** et la limite
**stricte**. Seule la souple est appliquée ; la stricte est le plafond que le
processus peut atteindre lui-même avec `setrlimit()`, et que seul root peut
relever.

L'écart avec ton shell (1024 / 1048576 sur Ubuntu 24.04) illustre exactement
QO8.7 : ton shell a hérité des limites de la session PAM ouverte par `sshd` ; le
service a hérité de celles de PID 1, modifiées par le `LimitNOFILE=` de l'unité.
Deux chaînes d'héritage indépendantes.

`LimitNOFILE=65536` pose les deux valeurs d'un coup. Pour les dissocier, la
syntaxe est `LimitNOFILE=souple:stricte`, par exemple `LimitNOFILE=8192:65536`.

`ls /proc/$PID/fd | wc -l` compte les descripteurs réellement ouverts : c'est la
mesure qui permet de distinguer une limite trop basse (valeur stable près du
plafond) d'une fuite (valeur qui monte sans redescendre).
:::

---

**E8.13** — *Rendre un processus prioritaire pour l'OOM killer, et prouver un passage.*

```bash
PID=$(pgrep -f factura-gourmand.py | head -1)
echo 900 | sudo tee /proc/$PID/oom_score_adj
cat /proc/$PID/oom_score_adj      # 900
cat /proc/$PID/oom_score          # score final, recalculé en continu

# après coup, prouver qu'un OOM est passé :
journalctl -k --since '-1 day' | grep -iE 'out of memory|killed process'
dmesg -T | grep -i 'killed process'
systemctl status factura-api | grep -i 'oom\|Result'
journalctl -u systemd-oomd --since '-1 day'
```

::: pourquoi
`oom_score_adj` va de **-1000 à 1000**, et s'additionne au score calculé par le
noyau en **millièmes de la mémoire totale de la machine**. Concrètement :
`+900` équivaut à déclarer « ce processus consomme 90 % de la RAM en plus de ce
qu'il consomme vraiment ». `-1000` est un cas spécial : il rend le processus
**totalement immunisé**.

Pour un service, la forme durable est la directive d'unité :

```ini
[Service]
OOMScoreAdjust=500
```

Les deux endroits où chercher la preuve, après coup, ne sont pas les mêmes :

* `journalctl -k` / `dmesg` pour l'OOM killer du **noyau** : la ligne
  `Out of memory: Killed process ...` avec `total-vm` et `anon-rss` ;
* `journalctl -u systemd-oomd` pour `systemd-oomd`, actif par défaut sur Ubuntu
  24.04, qui décide **avant** le noyau à partir des métriques de pression mémoire
  (PSI) et tue à l'échelle du cgroup entier.

Si un processus a disparu sans trace et que `dmesg` est muet, c'est presque
toujours `systemd-oomd`. Et `systemctl status` d'un service tué de cette façon
affiche `Result: oom-kill`, ce qui est la preuve la plus rapide à obtenir.
:::

---

**E8.14** — *Unités en échec, unités masquées, unités `ssh` activées.*

```bash
systemctl list-units --type=service --state=failed
systemctl list-unit-files --state=masked
systemctl list-unit-files --state=enabled '*ssh*'
```

::: pourquoi
La distinction entre les deux sous-commandes est constamment confondue et c'est
une vraie question d'entretien :

* **`list-units`** liste les unités **chargées en mémoire** — celles que systemd
  connaît parce qu'elles tournent, ont tourné, ou sont référencées par une autre.
  C'est l'état **d'exécution**. `--all` y ajoute les unités chargées mais
  inactives.
* **`list-unit-files`** liste les **fichiers présents sur le disque**, qu'ils
  soient chargés ou non, avec leur état d'activation au boot. C'est l'état
  **d'installation**.

Une unité masquée ou jamais démarrée n'apparaît donc pas dans `list-units` : elle
n'est visible que par `list-unit-files`. C'est exactement le piège de BF8.3 —
chercher un service absent avec `list-units` ne donne rien, et on conclut à tort
qu'il n'existe pas.

`systemctl --failed` est le raccourci de la première commande, et fait partie des
trois ou quatre commandes à taper en arrivant sur une machine inconnue.
:::

---

**E8.15** — *Définition réellement appliquée de `ssh.service` et valeurs effectives.*

```bash
systemctl cat ssh.service
systemctl show -p Restart,RestartUSec,LimitNOFILE ssh.service
```

```text
# /usr/lib/systemd/system/ssh.service
[Unit]
Description=OpenBSD Secure Shell server
...
# /etc/systemd/system/ssh.service.d/10-nofile.conf
[Service]
LimitNOFILE=16384
```

::: pourquoi
`systemctl cat` affiche le fichier de base **et chaque drop-in**, chacun précédé
d'une ligne de commentaire donnant son **chemin complet**, dans l'ordre exact
d'application. C'est la seule réponse fiable à « qu'est-ce qui est configuré sur
ce service ? ». Lire `/usr/lib/systemd/system/ssh.service` avec `cat` ou `vim`
donne une réponse fausse dès qu'un drop-in existe — c'est précisément la panne
BF8.4.

`systemctl show -p` va un cran plus loin : il donne la valeur **effective après
fusion**, résolue par systemd, dans son unité interne (microsecondes pour les
durées, octets pour les tailles). C'est ce qu'il faut utiliser en script, avec
`--value` pour n'obtenir que la valeur sans le `CLÉ=`.

Complément utile sur une machine héritée : `systemd-delta` liste **toutes** les
unités du système qui sont surchargées, masquées ou étendues, en un seul écran.
C'est l'inventaire des dettes techniques laissées par les prédécesseurs.
:::

---

**E8.16** — *Dépendances et analyse du boot.*

```bash
systemctl list-dependencies --reverse network-online.target
systemctl list-dependencies ssh.service
systemd-analyze blame | head -10
systemd-analyze critical-chain
```

::: pourquoi
`list-dependencies <unité>` descend l'arbre de ce dont l'unité a besoin.
`--reverse` l'inverse : ce qui a besoin de cette unité — c'est la question qu'on
se pose vraiment avant d'arrêter quelque chose. Deux autres modes existent et sont
souvent plus utiles que les deux premiers : `--before` et `--after`, qui montrent
l'**ordonnancement** et non les besoins. Rappel de QO8.3 : ce sont deux choses
différentes.

`systemd-analyze blame` trie les unités par durée d'initialisation. Le piège est
qu'une unité lente qui s'initialise **en parallèle** n'a retardé personne :
`blame` ne dit pas ce qui a coûté du temps au boot, il dit ce qui a été lent.

`critical-chain` répond à la vraie question : il affiche la chaîne de dépendances
qui a réellement déterminé la durée du démarrage.

```text
multi-user.target @8.421s
└─ssh.service @8.390s +29ms
  └─network-online.target @8.388s
    └─systemd-networkd-wait-online.service @3.102s +5.285s
```

`@` = l'instant où l'unité a fini de démarrer, `+` = sa durée propre. Ici,
l'attente du réseau consomme 5,3 s des 8,4 s du boot : c'est là, et nulle part
ailleurs, qu'il faut travailler.
:::

---

## 8.6 Labs

### **L8.1** — *Triage de `lab-web` qui rame.*

Déroulé attendu.

**1. Charge et nombre de cœurs**

```bash
uptime
# load average: 2.34, 1.88, 0.94
nproc
# 2
```

Avec 2 vCPU, une charge de 2,34 signifie que la machine est **saturée** : autant
de tâches demandent du CPU (ou attendent une E/S) qu'il n'y a de cœurs, plus un
peu. La règle de lecture : on compare toujours la charge au nombre de cœurs, une
charge de 8 sur 16 cœurs est confortable, une charge de 3 sur 2 cœurs ne l'est
pas. Et l'ordre des trois valeurs donne la tendance : 2,34 / 1,88 / 0,94 dit que
la situation **se dégrade**.

**2. Répartition du temps CPU dans `top`**

```text
%Cpu(s): 92.3 us,  4.1 sy,  0.0 ni,  2.6 id,  0.7 wa,  0.0 hi,  0.3 si,  0.0 st
```

| Champ | Sens | Ce qu'il faut en conclure |
|---|---|---|
| `us` | espace utilisateur | du code applicatif tourne : c'est le cas ici |
| `sy` | noyau | beaucoup d'appels système, d'E/S, de réseau |
| `ni` | processus reniçés | portion de `us` pour les nice > 0 |
| `id` | inactif | ce qui reste |
| `wa` | attente d'E/S | disque ou réseau saturé, CPU disponible mais inutile |
| `st` | *steal* | l'hyperviseur t'a pris du temps : problème **hors** de la VM |

Ici `us` domine largement : le problème est un programme qui calcule, pas un
disque. Un `wa` élevé aurait envoyé vers le stockage ; un `st` élevé aurait envoyé
vers Proxmox et non vers la VM.

**3. Coupables**

```bash
ps -eo pid,ppid,user,ni,pcpu,rss,args --sort=-pcpu | head -5
ps -eo pid,ppid,user,ni,pcpu,rss,args --sort=-rss  | head -5
```

Deux listes, deux coupables distincts : `factura-charge.sh` en tête du CPU,
`factura-gourmand.py` en tête de la mémoire. Les confondre est l'erreur classique
du triage.

**4. `VSZ` contre `RSS`**

```bash
ps -o pid,vsz,rss,args -p $(pgrep -f factura-gourmand.py)
#   PID    VSZ    RSS ARGS
#  7120 512884 498220 .../factura-gourmand.py 60 1
```

`VSZ` est l'espace d'adressage **virtuel réservé** : il inclut les bibliothèques
partagées mappées, les zones allouées mais jamais touchées, et les fichiers
mappés. `RSS` est ce qui occupe réellement de la RAM. Pour une JVM, `VSZ` dépasse
couramment 10 Go pour 800 Mo de `RSS` : seul `RSS` compte pour savoir si la
machine va tomber.

**5. Mitigation sans tuer**

```bash
for p in $(pgrep -f factura-charge.sh); do sudo renice -n 15 -p "$p"; done
GPID=$(pgrep -f factura-gourmand.py | head -1)
echo 800 | sudo tee /proc/$GPID/oom_score_adj
```

**6. États des processus**

```bash
ps -eo stat --no-headers | cut -c1 | sort | uniq -c | sort -rn
```

En présence d'un `D` : `cat /proc/<pid>/wchan` donne la fonction noyau où ça
bloque, et `dmesg -T | grep -i 'blocked for more than'` sort les traces du
détecteur de tâches bloquées.

::: pourquoi
Ce qu'il faut avoir compris de ce lab, c'est que **la charge moyenne ne dit pas
quoi faire**. Elle dit seulement « il se passe quelque chose ». Le diagnostic
utile vient de la décomposition qui suit :

```text
charge haute + us haut  -> un programme calcule -> ps --sort=-pcpu
charge haute + wa haut  -> le stockage souffre  -> iostat, processus en D
charge haute + st haut  -> l'hyperviseur        -> rien a corriger dans la VM
charge basse + lenteur  -> memoire, swap        -> free -h, RSS, journal OOM
```

Et la mitigation choisie ici est délibérément **non destructive** : `renice` et
`oom_score_adj` sont réversibles, ne coupent aucun service, et n'exigent pas
d'accord. Ils achètent le temps nécessaire pour trouver la vraie cause. C'est
exactement ce qu'on attend d'un premier niveau : stabiliser sans casser.
:::

::: piege
La mitigation de fond, celle qui va dans le rapport, n'est ni `renice` ni
`kill` : c'est une **limite systemd chiffrée**, `MemoryMax=256M` et
`CPUQuota=50%` sur l'unité. Un `renice` ne survit pas au redémarrage du processus
et ne protège rien la nuit suivante ; une limite de cgroup est déclarative,
versionnée avec l'unité, et appliquée à chaque démarrage.
:::

---

### **L8.2** — *Servicifier `factura-api`.*

```ini
# /etc/systemd/system/factura-api.service
[Unit]
Description=Factura — API de facturation (HTTP)
Documentation=man:factura-api(8)
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=factura
Group=factura
WorkingDirectory=/srv/factura
EnvironmentFile=/etc/factura/api.env
ExecStart=/opt/factura/bin/factura-api.py
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s
TimeoutStopSec=20s

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemd-analyze verify /etc/systemd/system/factura-api.service
sudo systemctl daemon-reload
sudo systemctl enable --now factura-api
systemctl status factura-api
curl -s http://127.0.0.1:8080/sante
bash check_M08_02.sh
```

::: pourquoi
Chaque choix, et le mécanisme derrière :

**`After=` + `Wants=network-online.target`** : les deux sont nécessaires et ne
font pas la même chose. `Wants=` demande que la cible soit atteinte, `After=`
impose l'ordre. Et attention : `network.target` ne signifie **que** « la gestion
du réseau a démarré », pas « une IP est configurée ». Seul
`network-online.target`, tiré par `systemd-networkd-wait-online.service`, attend
une adresse utilisable. Un service qui fait un `bind()` sur une IP précise a
besoin du second.

**`Type=exec`** : le point 4 de l'énoncé est un test, pas une formalité. Avec
`Type=simple` et un `ExecStart` fautif, `systemctl start` sort en 0 et le service
échoue derrière (Q8.5). Avec `Type=exec`, `systemctl start` échoue tout de suite
en affichant `203/EXEC`. Fais le test, c'est la démonstration la plus parlante du
module.

**`EnvironmentFile=`** : les valeurs vivent dans un fichier que l'exploitation
peut modifier sans toucher à l'unité, donc sans `daemon-reload` ni risque de
casser la syntaxe systemd. Attention à la syntaxe du fichier : `CLÉ=valeur`, pas
d'`export`, pas d'expansion shell, pas de substitution — `PORT=$AUTRE` sera passé
littéralement.

**`ExecReload=/bin/kill -HUP $MAINPID`** : `$MAINPID` est une variable de
**systemd**, remplacée par le PID du processus principal au moment de l'exécution.
Sans `ExecReload=`, `systemctl reload` répond
`Job type reload is not applicable for unit factura-api.service.`
Le test qui compte est que le PID ne change pas : un reload qui change le PID est
un restart déguisé, et il coupe les connexions en cours.

**`Restart=on-failure`** et non `always` : `on-failure` relance sur code de sortie
non nul, signal non attendu, timeout ou OOM — mais **pas** après un
`systemctl stop`, ni après une sortie en 0. Avec `always`, ton `systemctl stop`
serait suivi d'un redémarrage immédiat, ce qui rend toute intervention
impossible.

**`TimeoutStopSec=20s`** : au lieu des 90 s par défaut. C'est un compromis
explicite — on donne 20 secondes à l'application pour drainer ses requêtes, après
quoi on accepte le `SIGKILL`. Le choisir consciemment fait partie du travail ; le
laisser à 90 s par défaut allonge d'autant chaque redémarrage et chaque arrêt de
la machine.

**`[Install] WantedBy=multi-user.target`** : sans cette section, `enable` répond
`The unit files have no installation config`. C'est elle qui indique où créer le
lien symbolique, en l'occurrence
`/etc/systemd/system/multi-user.target.wants/factura-api.service`.
:::

::: piege
`Documentation=man:factura-api(8)` est cosmétique mais utile : la ligne apparaît
dans `systemctl status` et donne au collègue de garde le point d'entrée. Ce qui
n'est pas cosmétique : ne jamais mettre les valeurs de configuration dans
`Environment=` de l'unité. Le jour où il faut changer le port à 3 h du matin, il
faudra éditer une unité, `daemon-reload`, puis `restart`, au lieu d'éditer un
fichier `.env` et de faire un `reload`.
:::

---

### **L8.3** — *Le bon `Type=` pour trois services.*

**`factura-collecte.service`**

```ini
[Unit]
Description=Factura — collecte ponctuelle de metriques

[Service]
Type=oneshot
RemainAfterExit=yes
User=factura
Group=factura
Environment=FACTURA_DUREE=3
Environment=FACTURA_DATA=/srv/factura/data
Environment=FACTURA_LOG=/var/log/factura/collecte.log
ExecStartPre=/usr/bin/test -d /srv/factura/data
ExecStart=/opt/factura/bin/factura-collecte.sh

[Install]
WantedBy=multi-user.target
```

**`factura-legacy.service`**

```ini
[Unit]
Description=Factura — demon historique (auto-detache)

[Service]
Type=forking
PIDFile=/run/factura/legacy.pid
User=factura
Group=factura
RuntimeDirectory=factura
Environment=FACTURA_PIDFILE=/run/factura/legacy.pid
Environment=FACTURA_LOG=/var/log/factura/legacy.log
ExecStart=/opt/factura/bin/factura-legacy.sh
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

**Symptômes observés avec `Type=simple` (point 3)**

| Service | Symptôme avec `Type=simple` |
|---|---|
| `factura-collecte` | `active (running)` une seconde, puis `inactive (dead)` : aucune trace qu'il a tourné, et un `After=` sur cette unité ne garantit rien |
| `factura-legacy` | `systemctl start` réussit, puis `ps` ne montre **plus rien** : systemd a tué le démon détaché avec tout le cgroup |

**Point 4 — `Type=notify`** : avec `FACTURA_DELAI_PRET=10`,

```bash
time sudo systemctl start factura-api      # Type=exec   : real 0m0.061s
time sudo systemctl start factura-api      # Type=notify : real 0m10.104s
```

::: pourquoi
**Pourquoi `ExecStartPre=` plutôt qu'un test dans le script** : `ExecStartPre=`
est exécuté par systemd, avec le même `User=`, le même environnement et la même
isolation que `ExecStart=`. S'il échoue, le service n'est **jamais** lancé et
l'échec est visible dans `systemctl status` comme un `ExecStartPre` en erreur —
pas noyé dans les logs applicatifs. On peut en enchaîner plusieurs ; le préfixe
`-` (`ExecStartPre=-/usr/bin/...`) rend l'échec non bloquant.

**Pourquoi `RuntimeDirectory=factura` plutôt qu'un `mkdir` dans le script** :
systemd crée `/run/factura` avec le propriétaire du service et le mode
`RuntimeDirectoryMode=` (0755), **et le supprime à l'arrêt**. Le script n'a donc
besoin d'aucun privilège pour écrire dans `/run`, et rien ne traîne après l'arrêt.
C'est aussi ce qui rend l'unité fonctionnelle sur une machine neuve, où `/run` est
un tmpfs vide à chaque démarrage.

**Le sens réel de `Type=notify`** : la différence de 10 secondes n'est pas un
détail de confort. Elle change ce que signifie « le service est démarré » pour
toutes les unités qui déclarent `After=factura-api.service`. En `Type=exec`,
elles démarrent alors que le port n'est pas encore ouvert — et si l'une d'elles
tente une connexion au démarrage, elle échoue une fois sur deux selon la charge
de la machine. En `Type=notify`, elles ne démarrent qu'après le `READY=1`,
c'est-à-dire après l'appel à `listen()`. C'est le seul `Type=` qui fasse
correspondre l'état systemd à la disponibilité réelle du service.
:::

::: piege
Avec `Type=forking`, si `PIDFile=` est absent ou pointe vers un fichier jamais
écrit, systemd émet `Supervising process N which is not our child. We'll most
likely not notice when it exits.` Traduction : systemd a deviné un PID en
inspectant le cgroup, il n'en est pas le père, et il ne recevra donc pas de
`SIGCHLD` à sa mort. Le service restera affiché `active (running)` alors que le
démon est mort depuis des heures. C'est la panne la plus vicieuse de `forking` :
le monitoring est vert et rien ne tourne.
:::

---

### **L8.4** — *Durcissement et override par drop-in.*

**Partie 1 — l'unité durcie**

```ini
# /etc/systemd/system/factura-api.service
[Unit]
Description=Factura — API de facturation (HTTP)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60s
StartLimitBurst=5

[Service]
Type=exec
User=factura
Group=factura
WorkingDirectory=/srv/factura
EnvironmentFile=/etc/factura/api.env
ExecStart=/opt/factura/bin/factura-api.py
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s
TimeoutStopSec=20s

# --- repertoires geres par systemd ---
LogsDirectory=factura
LogsDirectoryMode=0750
StateDirectory=factura
RuntimeDirectory=factura
ReadWritePaths=/srv/factura/data

# --- isolation ---
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=yes
ProtectProc=invisible
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=yes
RestrictSUIDSGID=yes
LockPersonality=yes
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM
SystemCallArchitectures=native
CapabilityBoundingSet=
AmbientCapabilities=
UMask=0027

# --- limites de ressources ---
LimitNOFILE=65536
MemoryMax=256M
CPUQuota=50%
TasksMax=64

[Install]
WantedBy=multi-user.target
```

```console
$ systemd-analyze security factura-api.service | tail -1
→ Overall exposure level for factura-api.service: 1.9 OK :-)
```

Preuves du durcissement (point 5) :

```bash
sudo systemd-run --uid=factura --pty \
  --property=ProtectSystem=strict touch /etc/preuve
# touch: cannot touch '/etc/preuve': Read-only file system

ls /tmp/preuve-a-moi                       # existe dans ton /tmp
sudo systemctl show -p ControlGroup factura-api
cat /sys/fs/cgroup/system.slice/factura-api.service/memory.max
# 268435456
cat /sys/fs/cgroup/system.slice/factura-api.service/cpu.max
# 50000 100000
```

**Partie 2 — l'override de `ssh.service`**

```bash
sudo systemctl edit ssh.service
```

```ini
### /etc/systemd/system/ssh.service.d/override.conf
[Unit]
Description=OpenSSH — durci par l'equipe infra

[Service]
LimitNOFILE=16384
```

```bash
systemctl cat ssh.service                       # base + drop-in, avec chemins
systemctl show -p LimitNOFILE --value ssh.service    # 16384
sudo systemctl revert ssh.service               # annule proprement
systemctl show -p LimitNOFILE --value ssh.service    # valeur d'origine
```

::: pourquoi
**La règle de précédence**, à écrire dans le rapport :

```text
/etc/systemd/system/     <- local, priorite MAXIMALE (tes unites, tes masques)
/run/systemd/system/     <- transitoire, disparait au reboot (systemd-run)
/usr/lib/systemd/system/ <- fourni par les paquets, ECRASE a chaque mise a jour
```

Sur Ubuntu 24.04, `/lib` est un lien vers `/usr/lib` (*merged usr*) :
`/lib/systemd/system` et `/usr/lib/systemd/system` sont le même répertoire.

Un **fichier** de même nom dans un répertoire plus prioritaire remplace
entièrement celui du dessous. Les **drop-ins** (`unité.service.d/*.conf`) sont
cumulatifs : tous sont lus, dans l'ordre lexicographique de leur nom, et **tous
ceux des trois répertoires s'appliquent**, ceux d'`/etc` en dernier. D'où la
convention de nommage numérotée `10-`, `50-`, `90-`.

**`systemctl edit` contre `systemctl edit --full`** : le premier crée un drop-in,
c'est-à-dire un fragment qui se superpose. Les mises à jour du paquet continuent
de s'appliquer à tout ce que tu n'as pas surchargé. Le second **copie** l'unité
entière dans `/etc/systemd/system` et te la donne à éditer : tu la gèles dans son
état actuel, et tu ne bénéficieras plus jamais des corrections de l'éditeur.
Préfère toujours le drop-in ; `--full` se justifie uniquement quand il faut
changer une directive de type liste de façon massive.

**`systemctl revert`** supprime d'un coup tous les drop-ins et toute copie locale
d'une unité, et fait le `daemon-reload`. C'est la commande d'annulation propre —
bien plus sûre qu'un `rm` manuel qui oublie un fichier.

**Pourquoi `LogsDirectory=` plutôt que `ReadWritePaths=/var/log/factura`** : les
deux marchent, mais `LogsDirectory=` **crée** le répertoire avec le bon
propriétaire et le bon mode. L'unité devient auto-suffisante. `ReadWritePaths=`
exige que le chemin existe déjà, sinon le service échoue en `226/NAMESPACE` sur
une machine neuve — le genre de panne qu'on découvre le jour de la reconstruction
du serveur.

**`DynamicUser=yes`**, la variante du point 6 : systemd alloue un UID à la volée
dans la plage 61184–65519, différent à chaque démarrage. Il implique
automatiquement `ProtectSystem=strict`, `ProtectHome=read-only`, `PrivateTmp=yes`
et `RemoveIPC=yes`. Conséquence directe : **aucun fichier persistant ne peut lui
appartenir**. Les fichiers déjà possédés par `factura` deviennent illisibles. Les
seuls chemins où le service peut écrire durablement sont ceux gérés par
`StateDirectory=`, `LogsDirectory=` et `CacheDirectory=`, dont systemd ajuste la
propriété à chaque démarrage. `DynamicUser` est excellent pour un service sans
état, impraticable pour un service qui possède des données existantes.
:::

::: piege
`ProtectSystem=strict` sans `ReadWritePaths=` ni `*Directory=` produit un service
qui démarre puis échoue à la première écriture, avec un message trompeur :
`Read-only file system` alors que `ls -l` montre des droits d'écriture parfaits.
Le réflexe est de corriger les permissions — et de ne rien corriger du tout. La
bonne question n'est pas « qui possède le fichier » mais « le service voit-il ce
montage en écriture », et la réponse est dans `systemctl cat`, pas dans `ls`.
:::

---

### **L8.5** — *Une migration de 40 minutes en SSH instable.*

Tableau attendu :

| Méthode | Survit ? | Sorties | Reprise en main |
|---|---|---|---|
| `cmd &` | **non** | terminal, perdues | non |
| `nohup cmd &` | oui | `nohup.out` ou redirection | non |
| `tmux` | oui | terminal virtuel conservé | **oui** |
| `systemd-run` | oui | journal systemd | non (lecture seule) |

Et vu depuis un autre compte : `ps` pour les deux premières, `tmux ls` du même
compte pour la troisième, `systemctl status migration` pour la dernière — seule
méthode réellement partagée avec l'équipe.

Commandes de référence :

```bash
# 1. naïf
/opt/factura/bin/factura-charge.sh 1 &
ps -o pid,ppid,sid,cmd -p $!        # PPID = le bash de la session SSH

# 2. nohup
nohup /opt/factura/bin/factura-charge.sh 1 >/tmp/migration.log 2>&1 &
# après coupure : PPID = 1 (orphelin ré-adopté), le processus vit

# 3. tmux
tmux new -s migration
/opt/factura/bin/factura-charge.sh 1
# Ctrl-b d ; couper le SSH ; se reconnecter
tmux attach -t migration

# 4. systemd-run
sudo systemd-run --unit=migration --property=CPUQuota=50% \
  /opt/factura/bin/factura-charge.sh 1
systemctl status migration
systemd-cgls /system.slice/migration.service
journalctl -u migration -f
sudo systemctl stop migration
sudo systemctl reset-failed migration     # si elle a fini en echec
```

::: pourquoi
Le mécanisme, déjà vu en Q8.3, mérite d'être **observé** et pas seulement récité.
Le marqueur à regarder est le **SID** (identifiant de session), colonne `sid` de
`ps` :

* `cmd &` : même SID que ton shell. La session meurt, tout meurt.
* `nohup` : même SID, mais `SIGHUP` ignoré. Le PPID passe à 1 après la mort du
  shell — c'est la ré-adoption par PID 1, pas un détachement.
* `tmux` : SID du serveur `tmux`, créé par un `setsid()` au premier lancement.
  Ton SSH n'a jamais été dans cette session.
* `systemd-run` : SID de PID 1. Le processus n'a jamais été à toi.

**Ce qu'on retient pour la production** : `systemd-run`. Raisons, dans l'ordre
d'importance :

1. **traçabilité** — l'opération apparaît dans `systemctl list-units` et ses
   sorties sont dans le journal, horodatées, consultables par toute l'équipe, et
   conservées après la fin de l'opération ;
2. **isolation** — l'opération a son cgroup, donc ses limites ; une migration qui
   dérape ne peut pas emporter la machine si on a posé `MemoryMax=` ;
3. **reprise d'astreinte** — un collègue qui prend le relais tape
   `systemctl status migration`, pas « à ton avis, dans quel `tmux` de quel compte
   il l'a lancé ? ».

`tmux` reste le bon choix dès que l'opération est **interactive**, et c'est la
seule des quatre qui permette de reprendre la main. Beaucoup d'équipes utilisent
les deux : `tmux` pour piloter, `systemd-run` pour ce qui doit durer.
:::

::: piege
Une unité transitoire créée par `systemd-run` **ne disparaît pas toute seule si
elle échoue** : elle reste en `failed` dans `systemctl list-units --failed`, et
un second `systemd-run --unit=migration` se heurte à
`Unit migration.service already exists.` Le réflexe est
`systemctl reset-failed migration`. Ajouter `--collect` à la commande initiale
demande à systemd de nettoyer l'unité même en cas d'échec.
:::

---

## 8.7 Break & Fix

### **BF8.1** — *90 secondes puis échec, alors que le service répondait.*

**Démarche de diagnostic**

```bash
systemctl status factura-import
```

```text
     Loaded: loaded (/etc/systemd/system/factura-import.service; disabled)
     Active: failed (Result: timeout) since Fri 2026-09-18 16:12:03 CEST
    Process: 8123 ExecStart=/opt/factura/bin/factura-api.py (code=killed,
             signal=TERM)
systemd[1]: factura-import.service: start operation timed out. Terminating.
systemd[1]: factura-import.service: Failed with result 'timeout'.
```

Trois indices convergent et suffisent :

1. `Result: timeout`, et non `exit-code` : systemd **attendait** quelque chose.
2. `code=killed, signal=TERM` : ce n'est pas l'application qui a échoué, c'est
   systemd qui l'a tuée à l'expiration du délai.
3. L'application répondait pendant l'attente — donc le binaire fonctionne.

```bash
systemctl cat factura-import | grep -E 'Type|PIDFile'
# Type=forking
# PIDFile=/run/factura/import.pid
ls -l /run/factura/import.pid
# ls: cannot access '/run/factura/import.pid': No such file or directory
```

**Cause racine** : l'unité déclare `Type=forking`, ce qui dit à systemd
« le processus que je lance va se dupliquer puis **sortir**, et le vrai démon sera
celui dont tu trouveras le PID dans `PIDFile=` ». Or `factura-api.py` ne se
détache pas : il reste au premier plan, comme tout serveur moderne. Le processus
initial ne sort donc jamais. systemd attend la sortie pendant tout
`TimeoutStartSec=` (90 s par défaut), puis déclare l'échec du démarrage et
envoie `SIGTERM` — d'où un service parfaitement fonctionnel pendant 90 secondes,
puis tué par son propre superviseur.

**Correctif**

```bash
sudo systemctl edit --full factura-import
```

```ini
[Service]
Type=exec
# PIDFile= supprimé : il n'a de sens qu'avec Type=forking
```

```bash
sudo systemctl daemon-reload
sudo systemctl reset-failed factura-import
time sudo systemctl start factura-import     # real 0m0.05s
curl -s http://127.0.0.1:8090/sante
```

::: pourquoi
Il faut bien voir que **l'application n'a rien fait de mal**. Elle a démarré,
ouvert son port, servi des requêtes. C'est le **contrat** décrit par `Type=` qui
était faux : l'unité promettait à systemd un comportement de démon historique que
le programme n'a pas.

La conséquence « le service répondait pendant 90 secondes » est le détail qui
égare tout le monde. On vérifie que l'application marche, on conclut que le
problème vient d'ailleurs, et on cherche du côté du réseau ou des droits. Le bon
réflexe est de lire le **résultat** annoncé par systemd : `Result: timeout` ne
parle jamais de l'application, il parle toujours de ce que systemd attendait.

Table de correspondance à mémoriser :

| `Result:` | Ce que systemd te dit |
|---|---|
| `exit-code` | l'application est sortie avec un code non nul |
| `timeout` | systemd attendait un événement qui n'est jamais venu |
| `signal` | l'application a été tuée par un signal (souvent externe) |
| `oom-kill` | le tueur mémoire est passé |
| `start-limit-hit` | trop de tentatives (BF8.2) |
| `resources` | systemd n'a pas pu préparer l'exécution (fichier, namespace) |
:::

::: piege
La tentation « il suffit d'augmenter `TimeoutStartSec` » est explicitement
interdite par l'énoncé, et pour une bonne raison : avec `TimeoutStartSec=0`
(infini), le service resterait **éternellement en `activating`**. Tout ce qui
déclare `After=factura-import.service` ne démarrerait jamais, et le boot de la
machine se bloquerait. Un timeout n'est jamais la cause d'une panne, c'est
toujours le symptôme d'une attente mal posée.
:::

**Prévention** : `systemd-analyze verify` ne détecte pas ce cas — la syntaxe est
valide. La seule prévention est une règle d'équipe : `Type=forking` uniquement si
le programme documente explicitement qu'il se détache, et toujours accompagné d'un
`PIDFile=` dont on vérifie l'existence après le premier démarrage. En cas de
doute, `Type=exec` : au pire le service est déclaré prêt trop tôt, jamais bloqué.

---

### **BF8.2** — *Boucle de redémarrage puis abandon.*

**Démarche de diagnostic**

```bash
systemctl status factura-collecte
```

```text
     Active: failed (Result: start-limit-hit) since ...
systemd[1]: factura-collecte.service: Failed to load environment files:
            No such file or directory
systemd[1]: factura-collecte.service: Failed to spawn 'start' task:
            No such file or directory
systemd[1]: factura-collecte.service: Failed with result 'resources'.
systemd[1]: factura-collecte.service: Scheduled restart job, restart
            counter is at 5.
systemd[1]: factura-collecte.service: Start request repeated too quickly.
systemd[1]: factura-collecte.service: Failed with result 'start-limit-hit'.
```

La lecture se fait **de bas en haut** : le dernier message (`start-limit-hit`)
est la conséquence, le premier (`Failed to load environment files`) est la cause.

```bash
systemctl cat factura-collecte | grep Environment
# EnvironmentFile=/etc/factura/collecte.env
ls -l /etc/factura/collecte.env
# ls: cannot access ... : No such file or directory
```

**Cause racine** : le fichier référencé par `EnvironmentFile=` a disparu. systemd
ne peut pas construire l'environnement du processus : il échoue **avant même de
tenter le `fork()`**, d'où `Result: resources` et l'absence totale de code de
sortie applicatif. Avec `Restart=always` et `RestartSec=1s`, il réessaie
immédiatement, atteint 5 tentatives en moins de 10 secondes, et le limiteur de
démarrage verrouille l'unité.

**Correctif**

```bash
sudo install -o root -g factura -m 0640 /dev/null /etc/factura/collecte.env
sudo tee /etc/factura/collecte.env >/dev/null <<'EOF'
FACTURA_PORT=8091
FACTURA_DATA=/srv/factura/data
FACTURA_LOG=/var/log/factura/collecte.log
EOF
sudo systemctl reset-failed factura-collecte     # OBLIGATOIRE
sudo systemctl start factura-collecte
systemctl is-active factura-collecte
```

**La modification d'une seule ligne demandée** :

```ini
EnvironmentFile=-/etc/factura/collecte.env
```

::: pourquoi
**Pourquoi `restart` seul ne suffisait plus.** Le limiteur de démarrage
(`StartLimitIntervalSec=10s`, `StartLimitBurst=5`, tous deux dans `[Unit]`) est un
**verrou d'état** posé sur l'unité, pas une temporisation. Tant qu'il est actif,
`systemctl start` et `systemctl restart` échouent **sans rien tenter** : systemd
ne lance même pas le binaire. Seul `systemctl reset-failed` remet le compteur et
l'état à zéro. C'est la commande qu'on oublie et qui fait croire que « la panne
persiste alors que je l'ai corrigée ».

**Ce que fait le préfixe `-`.** Devant un chemin de `EnvironmentFile=`, il signifie
« si ce fichier n'existe pas ou n'est pas lisible, continue quand même ». Le
service démarre alors avec les valeurs par défaut de l'application, au lieu de
refuser de démarrer. C'est le comportement de toutes les unités de distribution :
`EnvironmentFile=-/etc/default/nginx`, `-/etc/sysconfig/...`. Le même préfixe
fonctionne sur `ExecStartPre=`, `ExecStop=` et les autres directives `Exec*`, où
il rend l'échec de la commande non bloquant.

Le compromis est réel et mérite d'être formulé : avec le `-`, un fichier
d'environnement effacé par erreur donne un service qui **démarre avec une mauvaise
configuration** — sur le mauvais port, avec le mauvais répertoire de données — au
lieu d'un service en panne visible. Panne bruyante contre dérive silencieuse. Pour
une configuration facultative, mets le `-` ; pour une configuration qui contient
le mot de passe de la base, ne le mets pas.
:::

::: piege
Le message `Failed to load environment files` n'apparaît **pas** dans
`systemctl status` si le service a rebouclé depuis : `status` n'affiche que les
dernières lignes, et elles sont toutes occupées par le `start-limit-hit`. Il faut
remonter avec `journalctl -u factura-collecte -n 50`, ou mieux
`journalctl -u factura-collecte --since '-10min'`. Lire uniquement les cinq
dernières lignes d'un service en boucle, c'est ne lire que la conséquence.
:::

**Prévention** : deux réflexes. Poser `RestartSec=` à une valeur qui laisse le
temps de voir passer les choses (5 s plutôt que 1 s), et faire figurer les
fichiers d'environnement dans le même dépôt de configuration que les unités, avec
un contrôle d'existence dans le script de déploiement.

---

### **BF8.3** — *Le service refuse de démarrer, sans aucune erreur.*

**Démarche de diagnostic**

```bash
sudo systemctl start factura-rapports
# Failed to start factura-rapports.service: Unit factura-rapports.service
# is masked.

systemctl status factura-rapports
```

```text
     Loaded: masked (Reason: Unit factura-rapports.service is masked.)
     Active: inactive (dead)
```

Le mot-clé est dans la ligne `Loaded:` : **`masked`**, et non `loaded`. C'est la
première ligne du `status`, celle qu'on saute quand on cherche une erreur
d'exécution.

La preuve par la liste, demandée par l'énoncé :

```bash
systemctl list-unit-files --state=masked
# UNIT FILE                   STATE   PRESET
# factura-rapports.service    masked  enabled

ls -l /etc/systemd/system/factura-rapports.service
# lrwxrwxrwx 1 root root 9 ... /etc/systemd/system/factura-rapports.service
#   -> /dev/null
```

**Cause racine** : l'unité est masquée. Un lien symbolique vers `/dev/null` a été
posé dans `/etc/systemd/system/`, qui a la précédence la plus haute. systemd
charge donc un fichier vide et considère l'unité comme non démarrable, quel que
soit le contenu parfaitement correct de
`/usr/lib/systemd/system/factura-rapports.service`.

**Correctif**

```bash
sudo systemctl unmask factura-rapports
sudo systemctl daemon-reload
sudo systemctl start factura-rapports
systemctl status factura-rapports       # active (exited)
```

::: pourquoi
**Pourquoi il n'y a « aucune erreur »** : c'est exact, et c'est la signature du
masque. Aucun processus n'a été lancé, donc aucun code de sortie, aucun
`Process:`, aucune ligne applicative dans le journal. Le refus a lieu **avant**
toute exécution, au moment du chargement de l'unité. Chercher l'erreur dans les
logs applicatifs ne peut rien donner — ils n'existent pas.

**La différence avec `disable`**, à formuler précisément :

| | `disable` | `mask` |
|---|---|---|
| Mécanisme | supprime les liens `*.wants` | lien de l'unité vers `/dev/null` |
| Démarrage au boot | non | non |
| `systemctl start` manuel | **oui** | non |
| Démarrage par dépendance d'un autre service | **oui** | non |
| Visible dans | `list-unit-files --state=disabled` | `--state=masked` |

`mask` est l'outil qu'on utilise quand un paquet réactive son service à chaque
mise à jour, ou quand on veut garantir qu'un service ne démarrera **jamais**,
même tiré par une dépendance. C'est un outil légitime — mais il doit être
documenté, parce qu'il laisse une panne muette derrière lui.

**La variante qui fait perdre encore plus de temps** : `systemctl mask --runtime`
pose le lien dans `/run/systemd/system/`, qui est un tmpfs. Le masque disparaît au
redémarrage. Symptôme : « le service ne démarre pas, on reboote, il remarche, et
trois semaines plus tard ça recommence ». Vérifie toujours les deux chemins :

```bash
ls -l /etc/systemd/system/*.service /run/systemd/system/*.service 2>/dev/null \
  | grep /dev/null
```
:::

::: piege
Chercher l'unité avec `systemctl list-units | grep rapports` ne donne **rien** :
`list-units` ne liste que les unités chargées, et une unité masquée n'est pas
chargeable. On en conclut qu'elle n'existe pas, et on part la recréer — ce que
l'énoncé interdit justement. La commande qui voit tout est
`systemctl list-unit-files`, qui regarde le disque (E8.14).
:::

**Prévention** : `systemctl list-unit-files --state=masked` fait partie des cinq
commandes à taper en prenant en main une machine dont on hérite, avec
`systemctl --failed`, `systemd-delta`, `systemd-analyze blame` et
`systemctl list-timers`. Et côté équipe : tout masque doit être accompagné d'un
commentaire dans le dépôt de configuration expliquant qui, quand et pourquoi.

---

### **BF8.4** — *L'API plante dès qu'il y a du monde.*

**Démarche de diagnostic**

```bash
curl -s 'http://127.0.0.1:8080/charge?n=200'
# erreur apres 123 fd: [Errno 24] Too many open files: '/dev/null'

PID=$(systemctl show -p MainPID --value factura-api)
grep 'Max open files' /proc/$PID/limits
# Max open files            128        128        files
```

La limite effective du processus est 128, alors que le fichier d'unité dit
65536. Il y a donc quelque chose **entre** le fichier et le processus.

```bash
systemctl cat factura-api
```

```text
# /etc/systemd/system/factura-api.service
...
LimitNOFILE=65536
...

# /etc/systemd/system/factura-api.service.d/10-local.conf
[Unit]
Description=Factura — API de facturation (instance lab-web)

# /etc/systemd/system/factura-api.service.d/90-tuning.conf
# Ajusté le 12/03 suite au ticket INC-2980 (fuite de descripteurs).
[Service]
LimitNOFILE=128
```

Confirmation par la valeur effective :

```bash
systemctl show -p LimitNOFILE --value factura-api
# 128
```

**Cause racine** : un drop-in oublié,
`/etc/systemd/system/factura-api.service.d/90-tuning.conf`, abaisse
`LimitNOFILE` à 128. Il a été posé pour contenir une fuite de descripteurs sur un
ancien incident, et jamais retiré. Comme `LimitNOFILE=` est une directive
scalaire, la dernière valeur lue gagne — et les drop-ins sont lus **après**
l'unité de base, dans l'ordre lexicographique : `90-tuning.conf` passe après
`10-local.conf` et après l'unité.

**Correctif** (sans toucher au fichier d'unité, comme demandé)

```bash
sudo rm /etc/systemd/system/factura-api.service.d/90-tuning.conf
sudo systemctl daemon-reload
sudo systemctl restart factura-api
systemctl show -p LimitNOFILE --value factura-api      # 65536
grep 'Max open files' /proc/$(systemctl show -p MainPID --value \
  factura-api)/limits
curl -s 'http://127.0.0.1:8080/charge?n=200'
# 200 descripteurs ouverts, total 200
```

Alternative si le drop-in doit être conservé pour d'autres raisons : le neutraliser
avec un drop-in plus prioritaire, `95-nofile.conf`, contenant `LimitNOFILE=65536`.
Moins propre : on empile de la dette au lieu de la retirer.

::: pourquoi
**La phrase à retenir** : le contenu d'un fichier d'unité ne répond pas à la
question « quelle est la configuration de ce service ». La configuration effective
est la **fusion** de l'unité de base et de tous les drop-ins des trois répertoires
de recherche, et seuls `systemctl cat` (pour voir d'où vient quoi) et
`systemctl show` (pour la valeur finale) y répondent.

C'est pour cette raison que le diagnostic doit toujours partir du **processus**,
pas du fichier. `/proc/PID/limits` est la vérité terrain : il donne ce que le
noyau applique réellement, après toutes les fusions, héritages et surcharges.
Quand `/proc/PID/limits` et le fichier d'unité se contredisent, c'est toujours le
fichier qui a tort — ou plutôt, c'est toujours qu'on n'a pas lu tous les fichiers.

**Pourquoi `ulimit -n` du shell d'admin est trompeur** : il affiche 1024 (ou la
valeur de `limits.conf` sur ta session PAM), qui n'a aucun rapport avec la limite
du service. Le développeur qui « jure que ça marche sur son poste » a raison :
chez lui, l'application est lancée depuis un terminal et hérite de la session PAM.
Deux chaînes d'héritage, deux limites (QO8.7).

**Ordre d'application des drop-ins** : tri **lexicographique** du nom de fichier,
pas chronologique. `90-tuning.conf` gagne sur `10-local.conf`, et `100-x.conf`
passe **avant** `99-y.conf` parce que `1` < `9` en tri de chaîne. D'où la
convention stricte des préfixes à deux chiffres.
:::

::: piege
Un drop-in peut aussi se trouver dans `/usr/lib/systemd/system/<unité>.d/`
(livré par un paquet) ou dans `/run/systemd/system/<unité>.d/` (posé à chaud,
disparaît au reboot). Et un drop-in `top-level` peut viser tous les services d'un
coup via `/etc/systemd/system/service.d/*.conf`. `systemctl cat` les affiche
tous ; un `ls` d'un seul répertoire, non. `systemd-delta` donne l'inventaire
complet des surcharges de la machine.
:::

**Prévention** : versionner `/etc/systemd/system` dans Git (ou le gérer par
Ansible, module 20), et faire du `systemctl cat` — pas du `cat` — le réflexe de
première lecture d'un service. Le script de conformité du défi D8 formalise
exactement ça : il compare la liste des drop-ins appliqués à une liste attendue.

---

## 8.8 Défi du module

**D8 — Livrer `factura-api` comme un service de production**

**1. L'unité**

Reprendre l'unité durcie de L8.4, avec deux changements imposés par le cahier
des charges :

```ini
EnvironmentFile=-/etc/factura/api.env
```

et un durcissement poussé sous 2.5 — en pratique, l'unité de L8.4 atteint déjà
1.9 avec `SystemCallFilter=@system-service`, `CapabilityBoundingSet=` vide,
`ProtectProc=invisible` et `RestrictAddressFamilies=`.

**2. Le drop-in de préproduction**

```ini
### /etc/systemd/system/factura-api.service.d/10-preprod.conf
[Service]
Environment=FACTURA_PORT=8081
MemoryMax=128M
```

```bash
sudo systemctl daemon-reload
sudo systemctl restart factura-api
systemctl show -p Environment,MemoryMax --value factura-api
curl -s http://127.0.0.1:8081/sante
```

**3. Le runbook** (structure attendue, le contenu est à rédiger)

```markdown
# Runbook — factura-api

## Exploitation courante
sudo systemctl start|stop|restart factura-api
sudo systemctl reload factura-api     # SIGHUP : relit la conf, PID inchangé,
                                      # connexions en cours preservees
sudo systemctl restart factura-api    # coupe le service ~1 s

## Le service ne demarre pas — les cinq commandes
1. systemctl status factura-api   -> lignes Loaded: et Active:, code de sortie
2. systemctl cat factura-api      -> la conf REELLE, drop-ins compris
3. journalctl -u factura-api -n 50 -> le message de l'application
4. systemd-analyze verify /etc/systemd/system/factura-api.service
5. ss -tulpn | grep :8081         -> le port est-il deja pris ?

## Codes de sortie rencontres
| 200/CHDIR | WorkingDirectory absent |
| 203/EXEC  | binaire absent ou non executable |
| 217/USER  | User= inconnu |
| 226/NAMESPACE | isolation impossible (ReadWritePaths, ProtectSystem) |

## Changer le port en production
1. editer FACTURA_PORT dans /etc/factura/api.env
2. sudo systemctl restart factura-api   (un reload ne rouvre pas la socket)
3. curl -s http://127.0.0.1:<port>/sante
4. verifier le pare-feu et le reverse proxy en amont

## Le service ne s'arrete pas
systemd envoie SIGTERM a tout le cgroup, attend TimeoutStopSec=20s,
puis SIGKILL. Le SIGKILL final coupe l'ecriture en cours : tampons
non vidus, fichiers de verrou laisses en place. Si ca arrive, verifier
/srv/factura/data et supprimer les .lock avant le redemarrage.
```

**4. Le script de conformité** — squelette attendu

```bash
#!/usr/bin/env bash
# verif-factura.sh — conformité du service factura-api
set -euo pipefail
UNIT=factura-api.service
PORT_ATTENDU=8081
DROPINS_ATTENDUS="10-preprod.conf"
PASS=0; FAIL=0
ok() { printf '[ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko() { printf '[FAIL] %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
val() { systemctl show -p "$1" --value "$UNIT"; }

[ "$(systemctl is-active  "$UNIT")" = active ]  \
  && ok "actif"   || ko "inactif"
[ "$(systemctl is-enabled "$UNIT")" = enabled ] \
  && ok "active au boot" || ko "non active au boot"
[ "$(val Type)" = exec ] && ok "Type=exec" || ko "Type=$(val Type)"
[ "$(val User)" = factura ] && ok "User=factura" || ko "User=$(val User)"
[ "$(val Restart)" = on-failure ] \
  && ok "Restart=on-failure" || ko "Restart=$(val Restart)"

PID=$(val MainPID)
NOF=$(awk '/Max open files/ {print $4}' "/proc/$PID/limits")
[ "$NOF" -ge 65536 ] && ok "nofile=$NOF" || ko "nofile=$NOF (< 65536)"

[ "$(val MemoryMax)" = 134217728 ] \
  && ok "MemoryMax=128M" || ko "MemoryMax=$(val MemoryMax)"

curl -fsS --max-time 4 "http://127.0.0.1:$PORT_ATTENDU/sante" >/dev/null \
  && ok "repond sur $PORT_ATTENDU" || ko "muet sur $PORT_ATTENDU"

TROUVES=$(ls /etc/systemd/system/"$UNIT".d/*.conf 2>/dev/null \
          | xargs -r -n1 basename | sort | tr '\n' ' ')
[ "$(echo "$TROUVES")" = "$DROPINS_ATTENDUS " ] \
  && ok "drop-ins conformes" || ko "drop-ins inattendus : $TROUVES"

SCORE=$(systemd-analyze security "$UNIT" \
        | awk '/exposure level/ {for (i=1;i<=NF;i++) \
               if ($i ~ /^[0-9]+\.[0-9]$/) print $i}' | tail -1)
awk -v s="$SCORE" 'BEGIN {exit !(s < 2.5)}' \
  && ok "exposition $SCORE" || ko "exposition $SCORE (>= 2.5)"

printf '%d contrôles OK, %d en échec\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

::: pourquoi
Les trois idées que le défi cherche à ancrer.

**Le drop-in comme mécanisme d'environnement.** L'unité de base décrit le service
« en général » ; le drop-in décrit ce qui est propre à **cette machine**. C'est
exactement le modèle que reprennent Ansible, Kubernetes et les fichiers
`docker-compose.override.yml` : une définition commune, une surcharge par
environnement. Le jour où il faut promouvoir la préproduction en production, on
supprime un fichier au lieu de relire toute une unité.

**Le contrôle doit lire l'état effectif, jamais la configuration.** Le script ne
lit **aucun** fichier d'unité : il interroge `systemctl show` pour les valeurs
fusionnées et `/proc/PID/limits` pour ce que le noyau applique. C'est la leçon de
BF8.4 transformée en code. Un script qui ferait
`grep LimitNOFILE /etc/systemd/system/factura-api.service` passerait au vert sur
une machine cassée.

**Le contrôle des drop-ins inattendus est le cœur du script.** C'est lui qui
détecte la panne de BF8.4 **avant** l'incident : il compare la liste réelle à une
liste attendue et alerte sur tout fichier en trop. Cette idée — déclarer
l'attendu et détecter la dérive — est le fondement de toute la gestion de
configuration, et c'est ce qui distingue un script de vérification d'un simple
script de démarrage.

Le runbook, enfin, n'est pas un exercice de style : la question « quelle est la
différence entre `reload` et `restart` **pour ce service précis** » n'a pas de
réponse générique. Ici, `reload` envoie un `SIGHUP` que l'application traite en
relisant sa configuration, sans fermer la socket d'écoute ni couper les
connexions ; `restart` ferme la socket, tue le processus et en relance un autre.
Conséquence directe et non évidente : **un changement de port exige un `restart`**,
parce que la socket d'écoute n'est ouverte qu'au démarrage. C'est ce genre de
détail, spécifique au service, qui fait la valeur d'un runbook à 3 h du matin.
:::
