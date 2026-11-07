<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Partie V — Expertise système › **Module 31** · corrigé  
[← Module 30](../30-sauvegarde-pra/corrige.md) · [Énoncé](README.md) · [Module 32 →](../32-fs-avances/corrige.md)

> [!TIP]
> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, pas avant. Chaque identifiant renvoie à son énoncé.
<!-- nav:fin -->

# Module 31 — Corrigé

## 31.3 Quiz — QCM

<a id="q31-1"></a>**[Q31.1](README.md#q31-1)** — *Pourquoi `-F 99` plutôt que 100 Hz.*

**Réponse : d)** pour ne pas tomber en phase avec une activité périodique.

> [!NOTE]
> **Pourquoi**
>
> Beaucoup d'activités du système sont cadencées à des fréquences rondes
> (minuteries à 100 ou 1 000 Hz, tâches toutes les 10 ms). Échantillonner
> exactement à la même fréquence risque de tomber **toujours au même moment**
> de leur cycle : l'activité est alors soit surreprésentée, soit invisible.
> 99 Hz glisse lentement par rapport à ces cycles et les échantillonne
> uniformément (*lockstep sampling* évité).
>
> 99 Hz est aussi un bon ordre de grandeur : sur 30 s et 2 CPU, environ
> 6 000 échantillons, assez pour un profil, pour un surcoût négligeable. On
> monte à 999 ou 4 999 Hz pour une analyse courte et fine.

---

<a id="q31-2"></a>**[Q31.2](README.md#q31-2)** — *Axe horizontal d'un flame graph.*

**Réponse : c)** rien de temporel ; tri alphabétique, largeur = proportion d'échantillons.

> [!NOTE]
> **Pourquoi**
>
> Le flame graph agrège les piles identiques : chaque case est une fonction
> dans un contexte de pile donné, sa largeur est le nombre d'échantillons
> où cette pile apparaissait. Les cases d'un même niveau sont triées par
> ordre alphabétique pour que les piles communes fusionnent, ce qui détruit
> toute notion d'ordre temporel. Pour voir l'évolution dans le temps, on
> utilise une autre représentation (*flame chart*, ou les tracés de
> `perf script` avec horodatage, ou des outils comme Firefox Profiler).

---

<a id="q31-3"></a>**[Q31.3](README.md#q31-3)** — *Piles réduites à une fonction puis `[unknown]`.*

**Réponse : a)** compilé sans pointeurs de cadre, déroulé par pointeurs de cadre.

> [!NOTE]
> **Pourquoi**
>
> `perf record -g` déroule la pile en suivant la chaîne des pointeurs de cadre
> (registre `rbp` sur x86-64) : chaque cadre contient l'adresse du cadre
> appelant. Un code compilé avec `-fomit-frame-pointer` (défaut de `-O2`
> pendant des années) utilise `rbp` comme registre ordinaire : la chaîne est
> cassée dès le premier cadre. Solutions :
>
> * recompiler avec `-fno-omit-frame-pointer` (ce que fait le setup) ;
> * `--call-graph dwarf` : `perf` copie une partie de la pile à chaque
>   échantillon et la déroule après coup avec les informations `.eh_frame` ;
>   marche sans recompiler, mais coûte beaucoup plus (fichiers volumineux) ;
> * `--call-graph lbr` sur processeurs Intel récents (registres de dernières
>   branches), limité en profondeur.
>
> Ubuntu 24.04 compile désormais ses paquets avec les pointeurs de cadre
> (Q31.13), ce qui rend `-g` fiable pour le système ; les programmes maison
> restent à la charge de leurs auteurs.

---

<a id="q31-4"></a>**[Q31.4](README.md#q31-4)** — *IPC de 0,3.*

**Réponse : c)** le processeur attend beaucoup, mémoire ou branches.

> [!NOTE]
> **Pourquoi**
>
> Un cœur moderne peut retirer 4 instructions ou plus par cycle quand tout va
> bien. À 0,3, il passe l'essentiel de ses cycles **bloqué** : défauts de
> cache (une lecture en mémoire vive coûte une centaine de cycles), branches
> mal prédites (pipeline vidé, une quinzaine de cycles perdus chaque fois),
> dépendances entre instructions. `perf stat -e cache-misses,branch-misses` ou
> `perf stat -d` dit laquelle.
>
> L'IPC dit si le code est **efficace**, pas s'il est utile : un algorithme
> naïf peut avoir un excellent IPC en faisant cent fois trop de travail
> (L31.1). Les appels système, eux, se voient en temps système, pas dans
> l'IPC.

---

<a id="q31-5"></a>**[Q31.5](README.md#q31-5)** — *300 ms de latence, 2 % de CPU.*

**Réponse : a)** `offcputime-bpfcc`.

> [!NOTE]
> **Pourquoi**
>
> Un profil CPU n'échantillonne que ce qui **s'exécute**. Un processus qui
> attend un disque, un verrou, une réponse réseau ou un `sleep` n'y apparaît
> pas, quelle que soit la durée de l'attente. `offcputime` instrumente
> l'ordonnanceur : à chaque fois qu'un thread quitte le CPU, il note sa pile et
> l'heure ; quand il y revient, il ajoute la durée à cette pile. Le résultat
> montre **où** le thread attendait (par exemple `fsync` → `jbd2` → attente
> d'E/S), pondéré par le temps. C'est L31.3.

---

<a id="q31-6"></a>**[Q31.6](README.md#q31-6)** — *Surcoût de `strace` contre `bpftrace`.*

**Réponse : d)** `ptrace` arrête le processus à chaque appel ; eBPF s'exécute dans le noyau.

> [!NOTE]
> **Pourquoi**
>
> Avec `ptrace`, chaque appel système provoque deux arrêts du processus
> (entrée et sortie), deux réveils de `strace`, des lectures de registres et de
> mémoire par d'autres appels système, puis la reprise. Pour un programme qui
> fait des millions d'appels, cela multiplie la durée par dix, cent ou plus
> (L31.2). Un programme eBPF attaché au tracepoint d'entrée s'exécute dans le
> contexte du processus, en quelques dizaines de nanosecondes, et ne fait que
> mettre à jour une map : le processus ne s'arrête jamais.
>
> `strace` reste précieux pour **lire** les arguments en clair d'un processus
> peu actif ; pour compter ou mesurer, on prend `perf trace -s` ou
> `bpftrace`.

---

<a id="q31-7"></a>**[Q31.7](README.md#q31-7)** — *Garanties du vérificateur eBPF.*

**Réponse : a), b) et d).**

> [!NOTE]
> **Pourquoi**
>
> Le vérificateur simule toutes les branches du programme avant de l'accepter :
>
> * **terminaison** : pas de boucle non bornée (les boucles bornées sont
>   acceptées depuis le noyau 5.3) ;
> * **mémoire** : chaque accès est vérifié (pointeur non nul, dans les bornes
>   d'une map, de la pile de 512 octets ou du contexte) ; lire la mémoire du
>   noyau passe par des fonctions d'aide contrôlées ;
> * **taille et complexité** : un million d'instructions vérifiées au plus ;
> * seules les fonctions d'aide autorisées pour ce type de programme sont
>   appelables.
>
> Le langage source n'importe pas (c faux) : bpftrace génère le bytecode
> lui-même, d'autres partent de C, de Rust ou de Go. Le vérificateur est la
> raison pour laquelle on peut charger du code dans le noyau en production
> sans risquer de le planter, ce qu'un module noyau ne garantit pas.

---

<a id="q31-8"></a>**[Q31.8](README.md#q31-8)** — *Tracepoint plutôt que kprobe.*

**Réponse : a)** interface stable, contre fonction interne qui change.

> [!NOTE]
> **Pourquoi**
>
> Un tracepoint est un point d'instrumentation **écrit** dans le code du noyau,
> avec des arguments documentés (`bpftrace -lv`), maintenu d'une version à
> l'autre. Une kprobe s'attache à l'entrée de n'importe quelle fonction ; mais
> une fonction peut être renommée, changer d'arguments, être intégrée dans
> l'appelant par le compilateur (et disparaître), entre deux versions du
> noyau. Un outil fondé sur des kprobes doit donc être revérifié à chaque
> mise à jour du noyau. On utilise les kprobes quand aucun tracepoint ne
> répond à la question.

---

<a id="q31-9"></a>**[Q31.9](README.md#q31-9)** — *Rôle de `/sys/kernel/btf/vmlinux`.*

**Réponse : c)** il décrit les types du noyau (BTF), base de CO-RE.

> [!NOTE]
> **Pourquoi**
>
> BTF (*BPF Type Format*) est une description compacte de tous les types du
> noyau en cours : structures, champs, décalages. Avec lui :
>
> * `bpftrace` peut écrire `args.filename` ou `curtask->mm->...` sans
>   en-têtes de compilation installés ;
> * un programme compilé une fois peut être relogé au chargement selon la
>   disposition réelle des structures du noyau courant (*Compile Once, Run
>   Everywhere*), au lieu d'être recompilé sur chaque machine comme le faisait
>   BCC avec LLVM.
>
> Les noyaux d'Ubuntu, Rocky 9 et des grandes distributions sont compilés avec
> `CONFIG_DEBUG_INFO_BTF=y`.

---

<a id="q31-10"></a>**[Q31.10](README.md#q31-10)** — *Charge de 8, CPU inactif à 95 %.*

**Réponse : d)** des tâches en état `D`, comptées dans la charge.

> [!NOTE]
> **Pourquoi**
>
> Sous Linux, la charge est la moyenne exponentielle du nombre de tâches
> **exécutables ou en attente non interruptible** (`TASK_UNINTERRUPTIBLE`,
> état `D`). Ce choix, fait en 1993 pour refléter la demande de ressources au
> sens large, signifie qu'une machine dont huit processus attendent un disque
> lent ou un serveur NFS injoignable affiche une charge de 8 sans consommer de
> CPU. C'est BF31.3. La pression (PSI) distingue CPU, mémoire et E/S, et dit
> en pourcentage de temps ce que la charge mélange en un nombre.
>
> Les zombies (e) ne comptent pas : ils ont terminé et attendent seulement
> que leur parent lise leur code de sortie.

---

<a id="q31-11"></a>**[Q31.11](README.md#q31-11)** — *`@lat = hist(x)`.*

**Réponse : b)** histogramme en puissances de 2, dans une map, affiché à la fin.

> [!NOTE]
> **Pourquoi**
>
> L'agrégation se fait **dans le noyau** : chaque événement incrémente une
> case de la map, et seul le résultat agrégé remonte à la fin (ou à chaque
> `print`). C'est ce qui rend eBPF si peu coûteux comparé à un outil qui
> copierait chaque événement vers l'espace utilisateur. `lhist(x, 0, 100, 10)`
> donne des cases linéaires, plus lisibles quand on connaît la plage.

---

<a id="q31-12"></a>**[Q31.12](README.md#q31-12)** — *Arbre des fonctions du noyau pendant un `openat`.*

**Réponse : b)** `trace-cmd record -p function_graph -g do_sys_openat2`.

> [!NOTE]
> **Pourquoi**
>
> Le traceur `function_graph` de ftrace instrumente l'entrée et la sortie de
> chaque fonction du noyau appelée à partir de la fonction donnée (`-g`), et
> affiche l'arbre indenté avec la durée de chaque appel. C'est l'outil pour
> **comprendre un chemin** du noyau (quelles fonctions, dans quel ordre,
> laquelle est lente), là où `bpftrace` sert à **agréger** sur des sondes
> choisies. `strace -T` donne la durée de l'appel système vu de l'extérieur,
> sans rien de ce qui se passe dedans.

---

<a id="q31-13"></a>**[Q31.13](README.md#q31-13)** — *Piles complètes dans la glibc sur Ubuntu 24.04.*

**Réponse : c)** les paquets sont compilés avec les pointeurs de cadre.

> [!NOTE]
> **Pourquoi**
>
> À partir d'Ubuntu 24.04 (et de Fedora 38), les paquets de la distribution
> sont compilés avec `-fno-omit-frame-pointer` sur x86-64. Le coût en
> performances est faible (de l'ordre de 1 % en moyenne, parfois plus sur du
> code très spécifique), et le bénéfice considérable : `perf record -g` et les
> profileurs eBPF déroulent les piles à travers la glibc, OpenSSL, Python,
> sans DWARF ni recompilation. C'était un débat ancien ; il a été tranché en
> faveur de l'observabilité.

---

<a id="q31-14"></a>**[Q31.14](README.md#q31-14)** — *`/proc/pressure/io`, ligne `some`.*

**Réponse : d)** pourcentage du temps où au moins une tâche était bloquée sur des E/S.

> [!NOTE]
> **Pourquoi**
>
> PSI (*Pressure Stall Information*, noyau 4.20+) mesure le temps perdu à
> attendre une ressource :
>
> * `some` : part du temps où **au moins une** tâche était retardée ;
> * `full` : part du temps où **toutes** les tâches non inactives étaient
>   retardées en même temps (la machine ne faisait rien d'utile).
>
> Les moyennes sur 10, 60 et 300 s et le cumul en microsecondes (`total`)
> permettent des alertes directes (« plus de 20 % du temps en attente d'E/S
> depuis une minute »). Chaque cgroup a ses propres fichiers
> (`io.pressure`, `cpu.pressure`, `memory.pressure`), ce qui permet de
> désigner le service responsable (BF31.3).

---

<a id="q31-15"></a>**[Q31.15](README.md#q31-15)** — *uprobe : `could not resolve symbol`.*

**Réponse : a)** le binaire est dépouillé de sa table des symboles.

> [!NOTE]
> **Pourquoi**
>
> Une uprobe s'attache à une **adresse** dans le fichier ; `bpftrace` traduit
> le nom de fonction en adresse grâce à la table des symboles (`.symtab`) ou
> aux symboles dynamiques (`.dynsym`). Une fonction `static` d'un exécutable
> n'existe que dans `.symtab`, que `strip` supprime. Solutions : un binaire non
> dépouillé, ou ses informations de débogage séparées (BF31.1), ou s'attacher
> par adresse (`uprobe:/chemin:0x1234`) relevée sur une copie non dépouillée.
>
> Le programme n'a pas besoin de tourner pour qu'on pose une uprobe : elle
> s'appliquera à tous les processus qui exécutent ce fichier.

---

<a id="q31-16"></a>**[Q31.16](README.md#q31-16)** — *Fonctions d'un langage interprété ou compilé à la volée.*

**Réponse : b)** une table adresse → fonction publiée par l'environnement d'exécution.

> [!NOTE]
> **Pourquoi**
>
> Le code Python ou Java exécuté est soit interprété (la pile montre la boucle
> de l'interpréteur, `_PyEval_EvalFrameDefault`), soit compilé à la volée dans
> une mémoire anonyme sans symboles. `perf` sait lire un fichier
> `/tmp/perf-<PID>.map` qui associe des plages d'adresses à des noms :
>
> * Python 3.12+ : `python3 -X perf script.py` (ou `PYTHONPERFSUPPORT=1`)
>   crée de petits trampolines par fonction Python et publie la table ;
> * Java : `-XX:+PreserveFramePointer` et un agent (`perf-map-agent`, ou
>   l'option `-XX:+DumpPerfMapAtExit`) ; ou `async-profiler` ;
> * Node.js : `--perf-basic-prof`.

---

## 31.4 Quiz — questions ouvertes

<a id="qo31-1"></a>**[QO31.1](README.md#qo31-1)** — *Le diagnostic en 60 secondes.*

**Réponse attendue**

La liste de Brendan Gregg, à dérouler dans l'ordre, chaque commande
apportant un indice :

| Commande | Ce qu'on cherche |
|---|---|
| `uptime` | la charge et sa tendance (1, 5, 15 min) : ça monte, ça descend ? |
| `dmesg -T \| tail` | erreurs noyau : OOM killer, erreurs disque, TCP |
| `vmstat 1` | `r` (file d'exécution) > nombre de CPU ? `b` (état D) ? `si/so` (swap) ? `us/sy/wa/st` |
| `mpstat -P ALL 1` | un seul CPU à 100 % (programme monothread) ? |
| `pidstat 1` | quel processus consomme |
| `iostat -xz 1` | `r_await/w_await`, `aqu-sz`, `%util` par disque |
| `free -m` | mémoire disponible, cache |
| `sar -n DEV 1` | débit réseau proche du maximum de l'interface ? |
| `sar -n TCP,ETCP 1` | connexions, retransmissions |
| `top` | vue d'ensemble pour confirmer |

Ajouts modernes : `cat /proc/pressure/*` (PSI), et pour creuser un indice,
les outils eBPF : `execsnoop` (processus courts invisibles dans `top`),
`biolatency`, `runqlat`, `offcputime`, `tcpretrans`. La méthode : on ne
cherche pas « ce qui est anormal » au hasard, on vérifie pour chaque
ressource son **utilisation**, sa **saturation** et ses **erreurs** (USE).
D31 automatise cette liste.

---

<a id="qo31-2"></a>**[QO31.2](README.md#qo31-2)** — *De `bpftrace -e '…'` à l'affichage.*

**Réponse attendue**

1. **Analyse** : `bpftrace` lit le programme, résout la sonde
   (`tracepoint:syscalls:sys_enter_openat` existe-t-il ? quels arguments ?
   grâce à tracefs et BTF), et vérifie les types.
2. **Génération** : il produit du bytecode eBPF (via LLVM) : à chaque
   événement, lire le nom du processus courant (`bpf_get_current_comm`),
   chercher la clé dans une map de hachage, incrémenter.
3. **Création de la map** (`bpf()`, `BPF_MAP_CREATE`) : une table
   clé = nom (16 octets), valeur = compteur par CPU.
4. **Chargement** (`BPF_PROG_LOAD`) : le **vérificateur** contrôle le
   programme, puis le compilateur à la volée (JIT) le traduit en code
   machine natif.
5. **Attachement** au tracepoint (`perf_event_open` ou lien BPF) : à partir
   de là, chaque appel `openat` de n'importe quel processus exécute le
   programme dans le noyau, en quelques dizaines de nanosecondes.
6. **`Ctrl-C`** : `bpftrace` détache la sonde, lit toute la map depuis
   l'espace utilisateur, additionne les valeurs par CPU, trie et affiche ;
   le programme et la map sont libérés à la fermeture des descripteurs.

À aucun moment un événement individuel ne remonte à l'espace utilisateur :
seul l'agrégat. C'est la différence de fond avec `strace`.

---

<a id="qo31-3"></a>**[QO31.3](README.md#qo31-3)** — *Profil sur CPU et hors CPU.*

**Réponse attendue**

* **Sur CPU** : on échantillonne périodiquement ce qui s'exécute ; la
  largeur d'une pile = temps de calcul passé dans ce chemin. Il ne voit pas
  le temps où le thread ne tourne pas.
* **Hors CPU** : on instrumente les changements de contexte ; la largeur =
  temps passé **bloqué** dans ce chemin (E/S, verrous, sommeil, attente
  réseau, attente de CPU). Il ne voit pas le calcul, et il est bruité par les
  attentes normales (threads de pool inactifs, boucles d'événements qui
  attendent du travail), qu'il faut filtrer.

Une requête lente est la somme des deux : 2 ms de calcul + 8 ms d'attente de
`fsync` font 10 ms. Le profil CPU désigne les 2 ms, le profil hors CPU les
8 ms. Pour une latence, on regarde les deux, ou une vue combinée
(*wakeup*/*off-wake time* : qui a réveillé le thread et pourquoi
l'attendait-il).

---

<a id="qo31-4"></a>**[QO31.4](README.md#qo31-4)** — *De l'adresse au nom de fonction.*

**Réponse attendue**

`perf` sait dans quel fichier tombe l'adresse grâce aux projections mémoire
du processus (`/proc/PID/maps`, enregistrées dans `perf.data`), soustrait
l'adresse de chargement, puis cherche dans les symboles du fichier
(`.symtab`, sinon `.dynsym`) la fonction qui contient ce décalage. Pour le
noyau, il lit `/proc/kallsyms`.

| Échec | Correction |
|---|---|
| binaire dépouillé (`strip`) : plus de `.symtab` | informations de débogage séparées (`-dbgsym`, `.build-id`, `perf buildid-cache`), ou debuginfod |
| `kernel.kptr_restrict=2` : adresses du noyau masquées | le remettre à 0 ou 1 (lecture par root), le temps de l'analyse |
| code produit à la volée (JIT : Java, Node, Python 3.12) | fichier `/tmp/perf-PID.map` publié par l'environnement (Q31.16) |
| binaire remplacé ou supprimé depuis l'enregistrement | `perf buildid-cache` garde une copie par identifiant de build ; analyser sur la même machine, tout de suite |
| processus dans un conteneur | `perf` doit voir les fichiers du conteneur : lancer `perf report` avec `--symfs`, ou depuis l'hôte avec les chemins dans `/proc/PID/root` |

Sur Ubuntu 24.04, `perf` et `gdb` interrogent automatiquement
`debuginfod.ubuntu.com` (variable `DEBUGINFOD_URLS`) pour récupérer les
symboles des paquets officiels à partir de leur identifiant de build.

---

<a id="qo31-5"></a>**[QO31.5](README.md#qo31-5)** — *Tracer en production.*

**Réponse attendue**

* **Prévenir** l'équipe et l'astreinte : on intervient sur un système
  sollicité.
* **Outil le plus léger d'abord** : compteurs et histogrammes eBPF
  (agrégation dans le noyau), `perf stat`, PSI ; jamais `strace` sur un
  processus très actif.
* **Durée courte** et **bornée par la commande** (`timeout 30`,
  `-- sleep 10`) : un outil oublié dans un `tmux` tourne des jours.
* **Fréquence raisonnable** (99 Hz) et **filtres** dès la sonde (PID, nom du
  processus, seuil de latence) plutôt qu'après coup.
* **Volume** : estimer la taille de sortie (`perf record` peut écrire des
  centaines de Mo), écrire sur un disque qui n'est pas celui qu'on observe
  ou qui est déjà saturé.
* **Mesurer son propre surcoût** (temps CPU de l'outil, débit du service
  avant/pendant) ; s'arrêter si le service se dégrade.
* **Garder les traces** avec leur contexte (commande exacte, heure, version
  du noyau) pour l'analyse et le post-mortem.

---

<a id="qo31-6"></a>**[QO31.6](README.md#qo31-6)** — *Moyennes et histogrammes.*

**Réponse attendue**

Une moyenne écrase la **forme** de la distribution. 990 E/S à 0,2 ms et 10 E/S
à 200 ms donnent une moyenne de 2,2 ms, chiffre qui ne correspond à aucune
E/S réelle et cache que 1 % des requêtes sont mille fois plus lentes que les
autres. Pour un utilisateur dont la page fait 50 requêtes, la probabilité
d'en subir au moins une lente est de 40 % : la queue de distribution **est**
l'expérience utilisateur.

L'histogramme montre :

* les distributions **bimodales** (cache touché ou non, deux disques, deux
  chemins de code) ;
* la **queue** (p99, p99,9) et les valeurs aberrantes ;
* l'effet réel d'un correctif (la bosse lente a-t-elle disparu ?).

D'où les échelles en puissances de 2 de `hist()` et `biolatency` : elles
couvrent des microsecondes aux secondes sur une seule ligne d'écran.

---

<a id="qo31-7"></a>**[QO31.7](README.md#qo31-7)** — *eBPF hors de l'observation.*

**Réponse attendue**

* **Réseau** : XDP (filtrage et répartition de paquets au niveau du pilote,
  protection contre les dénis de service), Cilium (réseau, politiques et
  répartition de charge de Kubernetes sans iptables), équilibreurs comme
  Katran.
* **Sécurité** : détection d'exécution (Falco, Tetragon : alerter ou bloquer
  à l'exécution d'un shell dans un conteneur), LSM BPF (règles de contrôle
  d'accès programmables), `seccomp` (filtres d'appels système, en cBPF).
* **Ordonnancement et ressources** : `sched_ext` (ordonnanceurs écrits en
  eBPF, noyau 6.12+), contrôle des cgroups.
* **Profilage continu** : Parca, Pyroscope.

Risques : un programme eBPF privilégié lit **toute** la mémoire du noyau
qu'on lui laisse lire (secrets, données d'autres conteneurs) : charger eBPF
équivaut à root, d'où `kernel.unprivileged_bpf_disabled` ; et le
vérificateur lui-même a eu des failles, qui en font une surface d'attaque à
tenir à jour.

---

<a id="qo31-8"></a>**[QO31.8](README.md#qo31-8)** — *Tracer un processus dans un conteneur.*

**Réponse attendue**

* **PID** : le processus a un PID dans son espace de noms (souvent 1) et un
  autre sur l'hôte. Les outils eBPF et `perf` lancés sur l'hôte voient le
  PID de l'hôte (`docker inspect -f '{{.State.Pid}}'`, `crictl inspect`) ;
  `bpftrace` filtre aussi par cgroup (`cgroup == cgroupid("/sys/fs/cgroup/…")`).
* **Chemins** : le binaire est dans le système de fichiers du conteneur ;
  depuis l'hôte, on l'atteint par `/proc/<PID>/root/usr/bin/…` (pour une
  uprobe, ou `perf report --symfs`).
* **Symboles** : l'image contient rarement les informations de débogage ;
  il faut les ajouter à l'image de diagnostic ou les fournir à part par
  identifiant de build.
* **Où lancer les outils** : depuis l'**hôte** (ou un conteneur privilégié
  qui partage l'espace de noms PID de l'hôte, ce que font les outils de
  diagnostic de Kubernetes) : un conteneur ordinaire n'a ni les capacités
  (`CAP_BPF`, `CAP_PERFMON`, `CAP_SYS_ADMIN`) ni la vue sur le noyau
  nécessaires, et c'est voulu.

---

## 31.5 Exercices guidés

<a id="e31-1"></a>**[E31.1](README.md#e31-1)** — *Compteurs matériels et `perf_event_paranoid`.*

```bash
sudo perf list hw
sudo perf stat -e cycles,instructions sleep 1
sysctl kernel.perf_event_paranoid
```

```console
 Performance counter stats for 'sleep 1':
           812 341      cycles
           634 920      instructions              #    0,78  insn per cycle
       1,001289541 seconds time elapsed
kernel.perf_event_paranoid = 4
```

> [!NOTE]
> **Pourquoi**
>
> Si `perf list hw` est vide ou que `cycles` est `<not supported>`, la VM
> n'expose pas l'unité de mesure des performances du processeur (type de CPU
> autre que `host`) : `perf record` se rabat alors sur l'événement logiciel
> `cpu-clock`, suffisant pour profiler, pas pour mesurer l'IPC.
>
> `perf_event_paranoid` : −1 tout permis, 0 pas de traces brutes du noyau,
> 1 pas de profil noyau, 2 pas de profil hors de ses propres processus. La
> valeur **4** est propre à Ubuntu : **aucun** accès pour un utilisateur sans
> `CAP_PERFMON`. Root n'est pas concerné. On ne l'abaisse pas globalement en
> production ; on donne `CAP_PERFMON` à un binaire ou un groupe dédié si un
> non-root doit profiler.

---

<a id="e31-2"></a>**[E31.2](README.md#e31-2)** — *Fonctions chaudes en direct.*

```bash
sudo systemctl start lab31-calcul
sudo timeout 10 perf top -p "$(pgrep -x lab31-calcul)"
#   Overhead  Shared Object   Symbol
#     97,12%  lab31-calcul    [.] compte_naif
#      1,03%  [kernel]        [k] native_irq_return_iret
```

> [!NOTE]
> **Pourquoi**
>
> `[.]` désigne une fonction de l'espace utilisateur, `[k]` du noyau.
> `perf top` ne garde rien sur disque : c'est l'outil du premier coup d'œil.
> Pour un profil à conserver ou comparer, on enregistre (L31.1).

---

<a id="e31-3"></a>**[E31.3](README.md#e31-3)** — *Appels système par processus.*

```bash
sudo timeout 10 bpftrace -e 'tracepoint:raw_syscalls:sys_enter { @[comm] = count(); }'
```

> [!NOTE]
> **Pourquoi**
>
> `raw_syscalls:sys_enter` se déclenche pour **tous** les appels système (un
> seul point d'attache) ; `syscalls:sys_enter_*` existe par appel, avec ses
> arguments nommés. Pour savoir **quels** appels fait un processus :
> `@[comm, ksym(*(kaddr("sys_call_table") + args.id * 8))]`, ou plus simplement
> `@[comm, args.id] = count()` puis la table des numéros (`ausyscall --dump`).

---

<a id="e31-4"></a>**[E31.4](README.md#e31-4)** — *Tracepoints de `block`.*

```bash
sudo bpftrace -l 'tracepoint:block:*'
sudo bpftrace -lv tracepoint:block:block_rq_issue
#   dev_t dev; sector_t sector; unsigned int nr_sector; unsigned int bytes;
#   char rwbs[8]; char comm[16]; __data_loc char[] cmd;
```

> [!NOTE]
> **Pourquoi**
>
> `-lv` affiche les arguments **tels que le noyau en cours les définit** :
> c'est la documentation à jour, et la raison de préférer les tracepoints
> (Q31.8). `rwbs` code le type d'E/S (`R` lecture, `W` écriture, `S`
> synchrone, `F` vidage, `M` métadonnées).

---

<a id="e31-5"></a>**[E31.5](README.md#e31-5)** — *Processus créés par une connexion SSH.*

```bash
sudo execsnoop-bpfcc -T
```

```console
TIME     PCOMM            PID     PPID    RET ARGS
10:12:01 sshd             41022   1203      0 /usr/sbin/sshd -D -R
10:12:01 sh               41024   41023     0 /bin/sh -c /usr/bin/env -i PATH=… run-parts --lsbsysinit /etc/update-motd.d
10:12:01 50-landscape-s   41027   41025     0 /etc/update-motd.d/50-landscape-sysinfo
10:12:01 bash             41035   41023     0 /bin/bash
```

> [!NOTE]
> **Pourquoi**
>
> Une simple connexion lance des dizaines de processus éphémères (scripts du
> message d'accueil, `lesspipe`, `dircolors`, invite…), invisibles dans `top`.
> C'est le même mécanisme qui explique une charge CPU « sans processus
> gourmand » : des milliers de processus courts par seconde (un script en
> boucle, une sonde de supervision trop fréquente). `execsnoop` les montre
> tous, puisqu'il trace l'appel `execve` lui-même.

---

<a id="e31-6"></a>**[E31.6](README.md#e31-6)** — *Ouvertures en échec.*

```bash
sudo timeout 20 opensnoop-bpfcc -x
```

> [!NOTE]
> **Pourquoi**
>
> Beaucoup d'échecs sont **normaux** : la recherche d'une bibliothèque dans
> plusieurs répertoires (`ENOENT` en série par l'éditeur de liens),
> l'essai de fichiers de configuration optionnels, la recherche dans le
> `PATH`. Ce qui doit alerter : un échec répété des centaines de fois par
> seconde sur le même fichier (un cache qui n'existe plus), un `EACCES`
> (problème de droits), un `EMFILE` (plus de descripteurs).

---

<a id="e31-7"></a>**[E31.7](README.md#e31-7)** — *Latences disque avec et sans `lab31-journal`.*

```bash
sudo biolatency-bpfcc 10 1
sudo systemctl start lab31-journal
sudo biolatency-bpfcc -D 10 1          # -D : par disque
sudo systemctl stop lab31-journal
```

> [!NOTE]
> **Pourquoi**
>
> Au repos, quelques E/S réparties. Avec `lab31-journal`, une bosse très
> nette d'écritures synchrones, autour de la milliseconde sur le stockage du
> lab : chaque `fsync` attend la fin d'une écriture **et** le vidage du cache
> d'écriture du disque. La largeur de la bosse donne la latence que chaque
> requête paie.

---

<a id="e31-8"></a>**[E31.8](README.md#e31-8)** — *Attente de CPU.*

```bash
sudo runqlat-bpfcc 10 1                                    # une instance
for i in 1 2 3; do /usr/local/bin/lab31-calcul >/dev/null & done
sudo runqlat-bpfcc 10 1                                    # quatre instances sur 2 vCPU
kill %1 %2 %3
```

> [!NOTE]
> **Pourquoi**
>
> Avec une seule instance, l'attente reste de quelques microsecondes : il y a
> toujours un CPU libre. Avec quatre tâches pour deux CPU, la distribution
> s'étale jusqu'à plusieurs millisecondes (la tranche de temps de
> l'ordonnanceur) : chaque tâche attend son tour. C'est la mesure directe de la
> **saturation** CPU, que l'utilisation (100 % dans les deux cas pour les CPU
> occupés) ne distingue pas.

---

<a id="e31-9"></a>**[E31.9](README.md#e31-9)** — *Pression CPU et E/S.*

```bash
cat /proc/pressure/cpu /proc/pressure/io
# avec lab31-calcul ×4 et lab31-journal en marche, une minute plus tard :
cat /proc/pressure/cpu /proc/pressure/io
#   cpu  some avg10=48.20 …     <- la moitié du temps, au moins une tâche attendait un CPU
#   io   some avg10=21.70 …  full avg10=3.10 …
```

`some` : au moins une tâche retardée ; `full` : toutes les tâches actives
retardées en même temps. Pour le CPU, `full` au niveau du système n'a pas de
sens défini (il est toujours à 0 en dehors des cgroups).

---

<a id="e31-10"></a>**[E31.10](README.md#e31-10)** — *Chemin noyau d'un `openat`.*

```bash
sudo trace-cmd record -p function_graph -g do_sys_openat2 -F cat /etc/hostname
sudo trace-cmd report | head -30
```

```console
 cat-4211 [001]  do_sys_openat2() {
 cat-4211 [001]    getname() { … }
 cat-4211 [001]    get_unused_fd_flags() { … }
 cat-4211 [001]    do_filp_open() {
 cat-4211 [001]      path_openat() {
 cat-4211 [001]        link_path_walk.part.0() { … }
 cat-4211 [001]        do_open() { … }
 cat-4211 [001]  ! 112.410 us |  }
```

> [!NOTE]
> **Pourquoi**
>
> `-F` limite la trace au processus lancé par la commande : sans lui, tous les
> `openat` de la machine s'y retrouvent. Le `!` signale une durée supérieure à
> 100 µs. On voit l'architecture d'un appel : résolution du chemin
> (`link_path_walk`, composant par composant, avec le cache des entrées de
> répertoire), réservation du descripteur, ouverture par le système de
> fichiers.

---

<a id="e31-11"></a>**[E31.11](README.md#e31-11)** — *uprobe sur `compte_naif`.*

```bash
sudo bpftrace -e 'uprobe:/usr/local/bin/lab31-calcul:compte_naif { @appels = count(); }
                  interval:s:1 { print(@appels); clear(@appels); }'
#   @appels: 22
```

Le compte correspond au débit affiché dans le journal (une passe = un appel).

---

<a id="e31-12"></a>**[E31.12](README.md#e31-12)** — *Surcoût de `strace` et de `bpftrace`.*

```bash
time /usr/local/bin/lab31-ecrit                       # ≈ 0,5 s
time sudo strace -c -o /tmp/strace.txt /usr/local/bin/lab31-ecrit    # ≈ 30 à 60 s
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_write /comm == "lab31-ecrit"/ { @ = count(); }' &
sleep 3; time /usr/local/bin/lab31-ecrit; sudo kill -INT %1   # ≈ 0,6 s
```

> [!NOTE]
> **Pourquoi**
>
> 2 millions d'appels `write` : `strace` multiplie la durée par 50 à 100 (deux
> arrêts par appel), `bpftrace` ajoute une dizaine de pourcents (un petit
> programme exécuté deux millions de fois). C'est le chiffre à retenir pour ne
> jamais lancer `strace` sur un service de production chargé, et pour se
> méfier des mesures faites **sous** `strace`.

---

## 31.6 Labs

### <a id="l31-1"></a>**[L31.1](README.md#l31-1)** — Où passe le CPU ?

**Étape 1 — Débit de départ**

```bash
sudo systemctl start lab31-calcul
journalctl -u lab31-calcul -f
#   naif : 22.5 passes/s (0 occurrences par passe)
```

**Étape 2 — Compteurs**

```bash
P=$(pgrep -x lab31-calcul)
sudo perf stat -e cycles,instructions,branches,branch-misses,cache-references,cache-misses \
  -p "$P" -- sleep 10
```

```console
    25 980 114 233      cycles
    61 112 902 117      instructions              #    2,35  insn per cycle
    19 871 006 552      branches
       912 334 101      branch-misses             #    4,59% of all branches
        14 220 811      cache-references
         1 102 554      cache-misses              #    7,75 % of all cache refs
```

> [!NOTE]
> **Pourquoi**
>
> Un IPC élevé et peu de défauts de cache : le processeur travaille à plein…
> mais à quoi ? Le texte (8 Mo) tient en grande partie dans les caches et se
> lit séquentiellement, le préchargement matériel fonctionne. Les défauts de
> branche (près de 5 %) viennent de la comparaison caractère par caractère sur
> un texte aléatoire. Le code est **efficace**, c'est l'**algorithme** qui fait
> trop de travail : `perf stat` seul ne le dit pas, le profil va le montrer.

**Étape 3 — Profil avec piles**

```bash
sudo perf record -F 99 -g -p "$P" -o ~/lab31/naif.data -- sleep 30
sudo perf report -i ~/lab31/naif.data --stdio --no-children | grep -v '^$' | head -12
sudo perf report -i ~/lab31/naif.data --stdio --children | grep -E '^ +[0-9]' | head -8
```

```console
# --no-children (temps propre)
    98.91%  lab31-calcul  lab31-calcul  [.] compte_naif
     0.37%  lab31-calcul  [kernel]      [k] __irqentry_text_end
# --children (temps cumulé : la fonction et tout ce qu'elle appelle)
   100.00%   0.00%  lab31-calcul  libc.so.6     [.] __libc_start_call_main
   100.00%   0.00%  lab31-calcul  lab31-calcul  [.] main
   100.00%   0.00%  lab31-calcul  lab31-calcul  [.] boucle
    99.10%   0.00%  lab31-calcul  lab31-calcul  [.] traite_documents
    99.10%   0.00%  lab31-calcul  lab31-calcul  [.] analyse
    98.91%  98.91%  lab31-calcul  lab31-calcul  [.] compte_naif
```

**Étape 4 — Flame graph et annotation**

```bash
sudo perf script -i ~/lab31/naif.data | ~/FlameGraph/stackcollapse-perf.pl \
  | ~/FlameGraph/flamegraph.pl --title "lab31-calcul (naïf)" > ~/lab31/cpu-naif.svg
sudo perf annotate -i ~/lab31/naif.data --stdio -s compte_naif | head -30
```

Le flame graph est une tour unique `_start → __libc_start_main → main →
boucle → traite_documents → analyse → compte_naif`, avec un plateau qui
occupe toute la largeur au sommet. `perf annotate` place l'essentiel des
échantillons sur la comparaison `texte[i + j] == motif[j]` et le saut qui la
suit.

**Étape 5 — L'explication et le correctif**

`compte_naif` compare le motif à **chaque** position du texte. Le motif
commence par onze `a`, et le texte contient deux tiers de `a` : à chaque
position, la comparaison avance en moyenne de plusieurs caractères avant
d'échouer, et recommence à la position suivante en relisant les mêmes
caractères. `memmem()` de la glibc utilise un algorithme qui exploite
l'information des comparaisons déjà faites (décalages calculés sur le
motif, bascule vers l'algorithme *Two-Way* en cas de comportement
quadratique) et saute plusieurs positions d'un coup.

```bash
sudo systemctl edit lab31-calcul
#   [Service]
#   ExecStart=
#   ExecStart=/usr/local/bin/lab31-calcul --rapide
sudo systemctl restart lab31-calcul
```

Le `ExecStart=` vide **efface** la ligne héritée de l'unité d'origine ;
sans lui, systemd refuse deux `ExecStart` pour un service qui n'est pas
`oneshot`.

**Étape 6 — Nouvelles mesures et rapport**

```markdown
# lab31-calcul : naïf contre memmem()
| Mesure | naïf | rapide |
|---|---|---|
| débit | 22,5 passes/s | 90,1 passes/s (×4) |
| IPC | 2,35 | 1,9 |
| défauts de branche | 4,6 % | 1,2 % |
| fonction dominante | compte_naif 98,9 % | __memmem_… (glibc) 96 % |
Conclusion : le gain vient de l'algorithme (moins d'instructions par passe :
−80 %), pas d'une meilleure efficacité par instruction (l'IPC baisse même un
peu). Le temps est désormais dans la glibc, qui n'est plus à optimiser ici.
```

> [!NOTE]
> **Pourquoi**
>
> L'IPC peut **baisser** alors que le programme va quatre fois plus vite : il
> exécute cinq fois moins d'instructions. C'est la leçon principale : on
> compare des **débits** et des **instructions par unité de travail**, pas un
> indicateur d'efficacité isolé.

---

### <a id="l31-2"></a>**[L31.2](README.md#l31-2)** — Les appels système, sans ralentir personne

**Étapes 1 et 2 — Chronométrer, compter**

```bash
time /usr/local/bin/lab31-ecrit                        # real 0m0,55s, sys 0m0,44s
time sudo perf trace -s /usr/local/bin/lab31-ecrit 2>&1 | tail -8
#   write   2097152   …   avg 0.000 ms
#   real 0m2,1s
time sudo strace -c /usr/local/bin/lab31-ecrit 2>&1 | tail -5
#   % time  seconds  usecs/call  calls    errors syscall
#   99.98   1.902    0           2097152         write
#   real 0m41s
```

`perf trace` multiplie la durée par 4, `strace` par 75. Le temps est presque
tout en `sys` : le programme passe sa vie dans les transitions vers le noyau.

**Étape 3 — Histogrammes**

```bash
sudo bpftrace -e '
tracepoint:syscalls:sys_enter_write /comm == "lab31-ecrit"/ { @taille = hist(args.count); @t[tid] = nsecs; }
tracepoint:syscalls:sys_exit_write /@t[tid]/ { @duree_ns = hist(nsecs - @t[tid]); delete(@t[tid]); }' &
sleep 3; /usr/local/bin/lab31-ecrit; sudo kill -INT %1
```

```console
@taille:
[1]              2097152 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
@duree_ns:
[128, 256)       1861007 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[256, 512)        225018 |@@@@@@                                              |
[512, 1K)           9871 |                                                    |
```

**Étape 4 — Le coût d'un appel système**

Un appel système fait passer le processeur du mode utilisateur au mode
noyau (instruction `syscall`), sauvegarde les registres, applique les
atténuations des failles de type Spectre et Meltdown (changement de tables de
pages avec KPTI, barrières, vidages de tampons de prédiction selon le
processeur), exécute le service (ici : verrouiller le fichier, copier un
octet dans le cache de pages, mettre à jour la taille), puis revient.
Chaque appel coûte quelques centaines de nanosecondes, presque tout en
**surcoût fixe** : 0,44 s de temps système / 2 097 152 appels ≈ 210 ns par
`write` d'un octet.

**Étape 5 — La bonne taille**

```bash
for n in 1 512 4096 65536 1048576; do
  /usr/bin/time -f "$n : %e s" /usr/local/bin/lab31-ecrit --tampon "$n" >/dev/null
done
#   1 : 0,55 s   512 : 0,003 s   4096 : 0,001 s   65536 : 0,001 s   1048576 : 0,002 s
```

Au-delà de quelques Kio, le surcoût fixe devient négligeable devant la copie
des données ; au-delà de 64 Kio, plus rien ne bouge (et un très gros tampon
coûte de la mémoire et du cache). C'est pour cela que la glibc (`stdio`)
tamponne par défaut sur 4 Kio, que `cp` utilise 128 Kio, et qu'un
`fprintf` caractère par caractère n'est pas un problème… tant qu'on ne vide
pas le tampon (`fflush`, `setvbuf(_IONBF)`, sortie vers un terminal ligne
par ligne).

**Étape 6 — `ecritures.bt`**

```text
#!/usr/bin/env bpftrace
/*
 * ecritures.bt — write() par processus, toutes les 5 s (module 31, L31.2)
 * Surcoût mesuré : < 1 % d'un CPU à 50 000 write/s (une mise à jour de map
 * par appel). À 2 M write/s, compter ~10 % sur le processus observé.
 */
tracepoint:syscalls:sys_exit_write
/args.ret > 0/
{
    @appels[comm, pid] = count();
    @octets[comm, pid] = sum(args.ret);
}

interval:s:5
{
    time("--- %H:%M:%S ---\n");
    print(@appels, 0, 0);
    print(@octets, 0, 0);
    clear(@appels);
    clear(@octets);
}
```

Le seuil « moins de 100 écritures » se règle au moment de l'affichage. Avec
`bpftrace` 0.20, le plus simple est de filtrer la sortie (`awk '$NF >= 100'`)
ou, dans le script, de ne retenir que les processus dépassant le seuil à
l'aide d'une seconde map remplie dans `interval` ; la version ci-dessus
affiche tout, trié, et laisse le filtrage à l'affichage.

> [!WARNING]
> **Piège**
>
> On compte sur `sys_exit_write` avec `args.ret > 0` plutôt que sur l'entrée
> avec `args.count` : un `write` peut écrire **moins** que demandé (tube
> plein, signal) ou échouer. Mesurer ce qui est demandé au lieu de ce qui est
> fait est une erreur classique d'instrumentation.

---

### <a id="l31-3"></a>**[L31.3](README.md#l31-3)** — Lent, et pourtant le CPU dort

**Étapes 1 et 2 — Constat**

```bash
sudo systemctl start lab31-journal
journalctl -u lab31-journal -n 2
#   102 requêtes/s, latence moyenne 9.712 ms, pire 31.40 ms (fsync toutes les 1)
P=$(pgrep -x lab31-journal)
sudo timeout 10 perf top -p "$P"           # calcul 60 %, quelques fonctions noyau : rien qui dure 10 ms
cat /proc/pressure/io                       # some avg10 ≈ 40-90
ps -L -o pid,tid,stat,wchan:32,comm -p "$P"
#   PID   TID  STAT WCHAN                            COMMAND
#   7311  7311 D    jbd2_log_wait_commit            lab31-journal
```

L'état `D` et le canal d'attente `jbd2_log_wait_commit` disent déjà
l'essentiel : le processus attend que le journal ext4 ait validé une
transaction sur le disque.

**Étape 3 — Flame graph hors CPU**

```bash
sudo offcputime-bpfcc -df -p "$P" 10 > ~/lab31/offcpu.folded
~/FlameGraph/flamegraph.pl --color=io --title="lab31-journal hors CPU" \
  --countname=us < ~/lab31/offcpu.folded > ~/lab31/offcpu.svg
```

La tour dominante : `main → enregistre → fsync → __x64_sys_fsync →
ext4_sync_file → jbd2_complete_transaction → jbd2_log_wait_commit →
schedule`. Plus de 95 % du temps hors CPU est dans `fsync`.

**Étape 4 — La couche disque**

```bash
sudo biolatency-bpfcc 10 1
sudo ext4slower-bpfcc 1          # opérations de plus de 1 ms
#   TIME     COMM           PID    T BYTES   OFF_KB   LAT(ms) FILENAME
#   10:31:04 lab31-journal  7311   S 0       0           8.71 journal.log
```

`T = S` : *sync*. Chaque `fsync` attend une écriture des données, puis du
bloc de validation du journal ext4, puis un vidage du cache du disque
(*flush*) : plusieurs aller-retours vers le stockage par requête.

**Étape 5 — Pourquoi c'est indispensable**

Le programme annonce « commande acceptée » après `fsync` : la ligne est
alors **sur le support**, et une coupure de courant juste après ne la fait
pas perdre. Sans `fsync`, elle serait seulement dans le cache de pages, écrite
quelques secondes plus tard par le noyau : une coupure ferait perdre des
commandes déjà confirmées au client. C'est la même raison pour laquelle
PostgreSQL attend le `fsync` du WAL avant de valider une transaction
(module 30).

**Étape 6 — Le compromis**

```bash
for g in 1 10 100; do
  sudo systemctl stop lab31-journal
  sudo systemd-run --unit=lab31-journal-g$g /usr/local/bin/lab31-journal --groupe $g
  sleep 12; journalctl -u lab31-journal-g$g -n 1 --no-pager; sudo systemctl stop lab31-journal-g$g
done
```

| `--groupe` | Débit | Latence moyenne | Pire latence | Commandes perdues sur coupure |
|---|---|---|---|---|
| 1 | ≈ 100/s | ≈ 10 ms | ≈ 30 ms | 0 |
| 10 | ≈ 1 000/s | ≈ 1 ms | ≈ 30 ms | jusqu'à 9 |
| 100 | ≈ 10 000/s | ≈ 0,1 ms | ≈ 30 ms | jusqu'à 99 |

```markdown
# Choix : --groupe 1 conservé
Le programme confirme chaque commande AVANT le fsync de son groupe : avec
--groupe 10, une coupure peut faire perdre jusqu'à 9 commandes déjà
confirmées. Pour des commandes clients, c'est inacceptable. Le vrai
« group commit » regroupe les requêtes CONCURRENTES et ne confirme chacune
qu'après le fsync commun : même gain de débit, sans perte. Il faut le coder
(file d'attente + un thread d'écriture), pas l'obtenir par ce paramètre.
```

> [!NOTE]
> **Pourquoi**
>
> Ce que fait `--groupe N` ici est l'équivalent de
> `synchronous_commit = off` de PostgreSQL : on confirme avant d'être
> durable. C'est acceptable pour des données qu'on peut reconstituer
> (statistiques, journaux de navigation), jamais pour des engagements envers
> un client. Le *group commit* véritable (`commit_delay` de PostgreSQL, ou le
> regroupement naturel de ext4/XFS) amortit un `fsync` sur plusieurs
> transactions **qui attendent toutes** : la latence ne baisse pas pour chacune,
> mais le débit global monte.
>
> La pire latence ne bouge pas : c'est toujours la durée d'un `fsync`, que
> paie la requête qui déclenche le vidage. Une moyenne qui baisse peut cacher
> une queue identique (QO31.6).

---

### <a id="l31-4"></a>**[L31.4](README.md#l31-4)** — Tes propres sondes

**`latence-open.bt`**

```text
#!/usr/bin/env bpftrace
/*
 * latence-open.bt [nom] — latence de openat() par processus, en µs, toutes les 10 s
 * (module 31, L31.4). Sans argument : tous les processus.
 * Surcoût mesuré : ~0,3 % d'un CPU à 20 000 openat/s (deux sondes par appel).
 */
tracepoint:syscalls:sys_enter_openat
/ $# == 0 || comm == str($1) /
{
    @debut[tid] = nsecs;
}

tracepoint:syscalls:sys_exit_openat
/ @debut[tid] /
{
    @us[comm] = hist((nsecs - @debut[tid]) / 1000);
    delete(@debut[tid]);
}

interval:s:10
{
    time("--- %H:%M:%S ---\n");
    print(@us);
    clear(@us);
}

END
{
    clear(@debut);
}
```

`$#` est le nombre d'arguments passés au script, `str($1)` le premier en
chaîne. La map `@debut` est indexée par **thread** (`tid`) : deux threads
d'un même processus qui ouvrent un fichier en même temps ne s'écrasent pas.

**`processus-courts.bt`**

```text
#!/usr/bin/env bpftrace
/*
 * processus-courts.bt — processus qui vivent moins de 100 ms (module 31, L31.4)
 * Surcoût mesuré : négligeable (< 0,1 % d'un CPU à 500 processus/s).
 */
tracepoint:sched:sched_process_exec
{
    @debut[pid] = nsecs;
    @cmd[pid] = str(args.filename);
}

tracepoint:sched:sched_process_exit
/ @debut[pid] && args.pid == args.tgid /
{
    $vie_ms = (nsecs - @debut[pid]) / 1000000;
    if ($vie_ms < 100) {
        printf("%-16s pid=%-7d ppid=%-7d %4d ms  %s\n",
               comm, pid, curtask->real_parent->tgid, $vie_ms, @cmd[pid]);
    }
    delete(@debut[pid]);
    delete(@cmd[pid]);
}

END { clear(@debut); clear(@cmd); }
```

On part de `exec` (et non de `fork`) pour ne compter que les programmes
lancés, et l'on ne retient la sortie que pour le thread principal
(`pid == tgid`) : la fin d'un thread secondaire n'est pas la fin du
processus. `curtask->real_parent->tgid` lit le parent dans la structure du
noyau grâce à BTF.

**`compte-naif.bt`**

```text
#!/usr/bin/env bpftrace
/*
 * compte-naif.bt — latence de compte_naif() dans lab31-calcul (module 31, L31.4)
 * Surcoût : deux uprobes par appel (~2 µs chacune, piège + retour au noyau),
 * négligeable à 20 appels/s ; à proscrire sur une fonction appelée 1 M fois/s.
 */
uprobe:/usr/local/bin/lab31-calcul:compte_naif
{
    @debut[tid] = nsecs;
}

uretprobe:/usr/local/bin/lab31-calcul:compte_naif
/ @debut[tid] /
{
    @ms = hist((nsecs - @debut[tid]) / 1000000);
    delete(@debut[tid]);
}

END { clear(@debut); }
```

En mode `--rapide`, la fonction n'est plus appelée : le script se charge,
s'attache… et n'affiche rien, parce qu'aucun événement ne survient. Une sonde
silencieuse ne prouve donc rien sans vérifier qu'elle **peut** se déclencher
(compter les appels, E31.11).

> [!NOTE]
> **Pourquoi**
>
> Une uprobe est bien plus coûteuse qu'un tracepoint : elle remplace la
> première instruction de la fonction par un point d'arrêt, ce qui provoque une
> exception, un passage dans le noyau pour exécuter le programme eBPF, puis le
> retour. Quelques microsecondes par appel, acceptables pour une fonction
> appelée vingt fois par seconde, ruineuses pour `malloc` appelée des millions
> de fois. D'où la ligne de surcoût exigée en tête de chaque script : elle dit
> à l'astreinte quand l'outil est utilisable.

---

## 31.7 Break & Fix

### <a id="bf31-1"></a>**[BF31.1](README.md#bf31-1)** — « Le profil ne montre que des adresses »

**Démarche de diagnostic**

```bash
B=/usr/local/bin/lab31-calcul
file "$B"
#   ELF 64-bit LSB pie executable, x86-64, … BuildID[sha1]=4c1f…, stripped
nm "$B" 2>&1 | head -1                  # nm: …: no symbols
readelf -n "$B" | grep 'Build ID'       # identifiant de build
ls /usr/local/lib/lab31/
#   lab31-calcul.debug
readelf -n /usr/local/lib/lab31/lab31-calcul.debug | grep 'Build ID'   # le même
objdump -d "$B" --start-address=… | head    # plus aucun « push %rbp ; mov %rsp,%rbp »
sysctl kernel.kptr_restrict                 # 2
sudo head -3 /proc/kallsyms                 # 0000000000000000 … : adresses masquées, même pour root
grep -r kptr_restrict /etc/sysctl.d/
```

**Causes** : trois, qui s'additionnent.

1. **Binaire dépouillé** (`stripped`) : plus de table des symboles, les
   fonctions du programme apparaissent en adresses.
2. **Compilé sans pointeurs de cadre** : même avec des symboles, les piles
   s'arrêtent au premier cadre.
3. **`kernel.kptr_restrict = 2`** (fichier de « durcissement » dans
   `/etc/sysctl.d/`) : `/proc/kallsyms` renvoie des adresses nulles à tout le
   monde, root compris ; `perf` ne peut plus nommer les fonctions du noyau.

**Correctif**

```bash
# 1. symboles : déclarer le fichier de débogage là où les outils le cherchent
id=$(readelf -n /usr/local/bin/lab31-calcul | awk '/Build ID/{print $3}')
sudo install -D -m 644 /usr/local/lib/lab31/lab31-calcul.debug \
  "/usr/lib/debug/.build-id/${id:0:2}/${id:2}.debug"
# 2. piles : dérouler par DWARF (.eh_frame est présent même dans un binaire dépouillé)
P=$(pgrep -x lab31-calcul)
sudo perf record -F 99 --call-graph dwarf -p "$P" -o /tmp/bf31.data -- sleep 10
# 3. noyau : le temps de l'analyse (et discuter du réglage permanent)
sudo sysctl kernel.kptr_restrict=1
sudo perf report -i /tmp/bf31.data --stdio --no-children | head
#   98.7%  lab31-calcul  lab31-calcul  [.] compte_naif
```

> [!NOTE]
> **Pourquoi**
>
> * `/usr/lib/debug/.build-id/xx/yyyy….debug` est l'emplacement standard où
>   `perf`, `gdb` et `bpftrace` cherchent les informations de débogage
>   séparées, par **identifiant de build** : c'est ainsi que fonctionnent les
>   paquets `-dbgsym` d'Ubuntu, et debuginfod les télécharge à la volée pour
>   les paquets officiels. L'identifiant garantit que les symboles
>   correspondent exactement au binaire. `perf buildid-cache --add` fait la
>   même chose dans le cache de `perf`.
> * `--call-graph dwarf` contourne l'absence de pointeurs de cadre sans
>   recompiler, au prix de fichiers 10 à 50 fois plus gros : on réduit la
>   durée et la fréquence.
> * `kptr_restrict` : 0 = adresses visibles, 1 = visibles seulement avec
>   `CAP_SYSLOG` (root), 2 = jamais. La valeur 1 est le bon compromis sur un
>   serveur : elle protège contre un utilisateur non privilégié qui
>   chercherait des adresses du noyau pour contourner l'ASLR noyau, sans
>   aveugler l'administrateur. Le « durcissement » à 2 doit être un choix
>   documenté, avec la procédure pour l'abaisser pendant un diagnostic.

---

### <a id="bf31-2"></a>**[BF31.2](README.md#bf31-2)** — « Le flame graph ment »

**Démarche de diagnostic**

```bash
sudo perf script -i ~/lab31/apres.data | head -20
#   lab31-calcul  7712 … cycles:
#       55d1c0a1243b compte_naif+0x2b (/usr/local/bin/lab31-calcul)
#       55d1c0a1259e analyse+0x1e
#       55d1c0a125c4 traite_documents+0x14
#       55d1c0a12640 boucle+0x50
#                                     <- plus rien : ni main, ni __libc_start_main, ni _start
sudo perf script -i ~/lab31/apres.data | awk 'NF==0{print n; n=0; next} /^ /{n++}' | sort | uniq -c
#   5981 4                            <- toutes les piles ont exactement 4 cadres
sysctl kernel.perf_event_max_stack       # 4
grep -r perf_event_max_stack /etc/sysctl.d/
```

**Cause racine** : `kernel.perf_event_max_stack` a été abaissé à 4 (défaut
127) par un fichier de `/etc/sysctl.d/` qui prétend « réduire la mémoire des
profils ». Le noyau ne collecte plus que les 4 cadres les plus profonds de
chaque pile : tout ce qui est en dessous disparaît. Dans le flame graph, les
tours commencent à `boucle` au lieu de `_start`, et toute analyse en temps
cumulé (`--children`) devient fausse.

**Correctif**

```bash
sudo rm /etc/sysctl.d/99-perf-memoire.conf
sudo sysctl kernel.perf_event_max_stack=127
sudo perf record -F 99 -g -p "$(pgrep -x lab31-calcul)" -o /tmp/ok.data -- sleep 10
sudo perf script -i /tmp/ok.data | head -12      # jusqu'à _start
```

**Reconnaître un profil tronqué** : dans un flame graph sain d'un processus,
**toutes** les tours partent d'une même base (`_start`, `__libc_start_main`,
`main`, ou `clone3`/`start_thread` pour les threads). Des tours qui
commencent à des hauteurs différentes ou à une fonction intermédiaire, et une
profondeur maximale identique pour toutes les piles, signalent une
troncature (ce réglage, `--max-stack` de `perf report`, une limite de
`bpftrace`, ou une pile cassée par l'absence de pointeurs de cadre).

> [!NOTE]
> **Pourquoi**
>
> Un profil tronqué est plus dangereux qu'un profil illisible : il **semble**
> juste. Ici le temps propre de `compte_naif` reste exact (c'est le cadre du
> sommet), mais tous les chiffres cumulés sont faux, et sur un programme aux
> piles profondes (un serveur Java, une application Python), les fonctions
> d'en haut et leurs appelants n'ont plus aucun lien visible. Le réflexe à
> prendre : vérifier que la base des piles est complète avant d'interpréter.

---

### <a id="bf31-3"></a>**[BF31.3](README.md#bf31-3)** — « Charge à 8, et la machine ne fait rien »

**Démarche de diagnostic**

```bash
uptime                                     # load average: 6.02, 5.71, 3.90
vmstat 1 5
#   procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
#    r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
#    0  6      0 812004  …                  0     0     0   256  220  410  0  1 92  7  0
#        ^ six tâches bloquées (b), r = 0 : personne n'attend le CPU
ps -eo stat,pid,ppid,wchan:28,cmd | awk '$1 ~ /^D/'
#   D  9121  9115  blkcg_iolatency_… ou io_schedule   dd if=/dev/zero of=/var/tmp/lab31-archive-1 …
cat /proc/pressure/io                      # some avg10=95.0 full avg10=…
sudo cat /proc/9121/stack                  # … submit_bio … blk_throtl … io_schedule
systemctl status "$(ps -o unit= -p 9121)"
#   lab31-archiveur.service - Archivage des journaux
cat /sys/fs/cgroup/system.slice/lab31-archiveur.service/io.max
#   8:0 rbps=max wbps=262144 riops=max wiops=max
cat /sys/fs/cgroup/system.slice/lab31-archiveur.service/io.pressure
systemctl cat lab31-archiveur.service | grep -i bandwidth
#   IOWriteBandwidthMax=/var/tmp 256K
```

**Cause racine** : le service d'« archivage » lance six écritures directes
(`dd … oflag=direct`) en parallèle, et son unité limite son débit d'écriture
à 256 Kio/s (`IOWriteBandwidthMax`). Le cgroup v2 retient les requêtes au
niveau de la couche bloc ; chaque `dd` attend la fin de son E/S en état `D`.
Six tâches en `D` en permanence : charge ≈ 6, sans aucun calcul. Le disque
lui-même n'est pas saturé, ce qui explique que le reste de la machine
réponde normalement.

**Correctif**

```bash
sudo systemctl stop lab31-archiveur.service
uptime                                   # la charge redescend (moyenne exponentielle : quelques minutes)
```

Si l'archivage est légitime, on corrige sa **conception** : un seul flux,
écritures tamponnées plutôt que directes, et une limitation par **poids**
(`IOWeight=`) plutôt que par plafond fixe, pour qu'il prenne la bande
passante libre sans bloquer en permanence :

```ini
# systemctl edit lab31-archiveur.service
[Service]
IOWriteBandwidthMax=
IOWeight=20
Nice=10
```

**Alerte plus juste** : alerter sur la **pression** plutôt que sur la charge :
`/proc/pressure/io` `some avg60 > 30` (et `/proc/pressure/cpu`, `memory`
séparément), par cgroup pour désigner le service. Prometheus l'expose
(`node_pressure_io_waiting_seconds_total` du node exporter). La charge reste
un indicateur de tendance, jamais une alerte isolée.

> [!NOTE]
> **Pourquoi**
>
> La charge Linux mélange deux choses : la demande de CPU (`r`) et les tâches
> bloquées en attente non interruptible (`b`). Les distinguer prend une
> seconde avec `vmstat 1` : c'est la première commande à lancer devant une
> charge anormale. L'état `D` désigne une attente qu'aucun signal ne peut
> interrompre (E/S disque, certaines attentes NFS ou FUSE) : même `kill -9`
> attend la fin de l'E/S, ce qui explique les processus « intuables » d'un
> serveur NFS injoignable.
>
> PSI répond exactement à la question que la charge pose mal : « quelle part
> du temps a-t-on perdue à attendre quelle ressource ? », et par cgroup,
> « à cause de quel service ? ».

---

## 31.8 Défi du module

<a id="d31"></a>**[D31](README.md#d31) — Le diagnostic en soixante secondes, outillé**

*Livrable attendu : `diag60.sh` et deux rapports commentés.*

```bash
#!/usr/bin/env bash
# diag60.sh — diagnostic de performance en 60 s : USE + eBPF (module 31, D31)
# Usage : sudo diag60.sh [répertoire]   -> rapport Markdown daté
# Contraintes : 60 s au plus, faible surcoût, dégradation propre si un outil manque.
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer en root" >&2; exit 1; }
DIR=${1:-$HOME/lab31/defi}; mkdir -p "$DIR"
R="$DIR/diag-$(hostname -s)-$(date +%Y%m%d-%H%M%S).md"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
NCPU=$(nproc)
CONSTATS=()
constat() { CONSTATS+=("$1"); }
outil() { command -v "$1" >/dev/null 2>&1; }

# --- 1. collectes de fond, 10 s chacune, en parallèle ---------------------------
lance() {  # lance <nom> <commande…> : sortie dans $T/<nom>, ou trace de l'absence
  local nom=$1; shift
  if outil "$1"; then timeout 12 "$@" > "$T/$nom" 2>/dev/null & else echo "absent : $1" > "$T/$nom"; fi
}
lance execsnoop  execsnoop-bpfcc
lance opensnoop  opensnoop-bpfcc -x
lance biolat     biolatency-bpfcc 10 1
lance runqlat    runqlat-bpfcc 10 1
lance tcpretrans tcpretrans-bpfcc
lance profil     profile-bpfcc -F 49 -f 10

# --- 2. USE, pendant ce temps --------------------------------------------------
vmstat 1 10 > "$T/vmstat"
read -r _ cpu_some <<<"$(awk '/^some/{split($2,a,"="); print "x", a[2]}' /proc/pressure/cpu)"
read -r _ io_some  <<<"$(awk '/^some/{split($2,a,"="); print "x", a[2]}' /proc/pressure/io)"
read -r _ mem_some <<<"$(awk '/^some/{split($2,a,"="); print "x", a[2]}' /proc/pressure/memory)"
etatD=$(ps -eo stat=,pid=,comm= | awk '$1 ~ /^D/' )
dmesg -T --level=err,crit,alert,emerg 2>/dev/null | tail -5 > "$T/dmesg"
free -m > "$T/free"; df -hP -x tmpfs -x devtmpfs > "$T/df"
ss -s > "$T/ss"; ip -s link > "$T/iplink"
wait

# --- 3. règles -------------------------------------------------------------------
rq=$(awk 'NR>2{s+=$1;n++} END{printf "%.1f", s/n}' "$T/vmstat")
bq=$(awk 'NR>2{s+=$2;n++} END{printf "%.1f", s/n}' "$T/vmstat")
awk -v r="$rq" -v n="$NCPU" 'BEGIN{exit !(r > 2*n)}' && constat "CPU saturé : file d'exécution moyenne $rq pour $NCPU CPU"
awk -v v="$cpu_some" 'BEGIN{exit !(v > 20)}' && constat "pression CPU : some avg10 = $cpu_some %"
awk -v v="$io_some"  'BEGIN{exit !(v > 10)}' && constat "pression E/S : some avg10 = $io_some %"
awk -v v="$mem_some" 'BEGIN{exit !(v > 5)}'  && constat "pression mémoire : some avg10 = $mem_some %"
[ -n "$etatD" ] && constat "$(wc -l <<<"$etatD") tâche(s) en état D (moyenne b = $bq) : $(awk '{print $3}' <<<"$etatD" | sort | uniq -c | xargs)"
if grep -q '^absent' "$T/biolat"; then :; else
  # lignes « 65536 -> 131071 : 3 | … » : borne basse en µs, puis le nombre d'E/S
  lent=$(awk -F'[ :>-]+' '/->/ && $2+0 >= 65536 {s+=$4} END{print s+0}' "$T/biolat")
  [ "$lent" -gt 0 ] && constat "$lent E/S disque de plus de 64 ms en 10 s"
fi
n_exec=$(grep -vc '^PCOMM\|^absent' "$T/execsnoop" 2>/dev/null || echo 0)
[ "$n_exec" -gt 1000 ] && constat "$((n_exec / 10)) processus lancés par seconde (execsnoop)"
n_ret=$(grep -vc '^TIME\|^absent' "$T/tcpretrans" 2>/dev/null || echo 0)
[ "$n_ret" -gt 0 ] && constat "$n_ret retransmission(s) TCP en 10 s"
[ -s "$T/dmesg" ] && constat "erreurs noyau récentes (dmesg)"

# --- 4. rapport ---------------------------------------------------------------------
{
  echo "# Diagnostic $(hostname -s) — $(date '+%F %T')"; echo
  echo "## Constats"
  if [ "${#CONSTATS[@]}" -eq 0 ]; then echo "* aucun seuil franchi"; else printf '* %s\n' "${CONSTATS[@]}"; fi
  echo; echo "## USE"; echo '```'; cat "$T/vmstat"; echo; cat /proc/pressure/{cpu,io,memory}; cat "$T/free" "$T/df"; echo '```'
  for f in biolat runqlat; do echo; echo "## $f"; echo '```'; cat "$T/$f"; echo '```'; done
  echo; echo "## Processus en état D"; echo '```'; echo "${etatD:-aucun}"; echo '```'
  echo; echo "## Processus lancés (extrait)"; echo '```'; head -20 "$T/execsnoop"; echo '```'
  echo; echo "## Ouvertures en échec (extrait)"; echo '```'; head -20 "$T/opensnoop"; echo '```'
  echo; echo "## Profil CPU : 15 piles les plus fréquentes"; echo '```'
  if grep -q '^absent' "$T/profil"; then cat "$T/profil"; else sort -k2 -nr -t' ' "$T/profil" | head -15 | cut -c1-200; fi
  echo '```'
  echo; echo "## Erreurs noyau"; echo '```'; cat "$T/dmesg"; echo '```'
} > "$R"
echo "rapport : $R"
```

> [!NOTE]
> **Pourquoi**
>
> Les choix qui comptent :
>
> * **Parallélisme** : les outils eBPF tournent tous ensemble pendant les
>   mêmes 10 secondes, pendant que la partie USE collecte `vmstat` : le
>   diagnostic tient en une quinzaine de secondes, et toutes les mesures
>   portent sur la **même** fenêtre, ce qui permet de les croiser.
> * **Faible surcoût** : agrégations dans le noyau (histogrammes), profil à
>   49 Hz, aucun `strace`, aucun `perf record` avec DWARF.
> * **Règles explicites** en tête du rapport : la personne d'astreinte lit
>   trois lignes, pas trois cents. Les seuils sont des points de départ, à
>   ajuster à chaque parc.
> * **Dégradation propre** : un outil absent est signalé dans la section
>   correspondante, le reste du rapport est produit. Un outil de diagnostic
>   qui échoue entièrement parce qu'il manque `tcpretrans` ne sert à rien le
>   jour où l'on en a besoin.

Sur BF31.3 rejouée, les constats attendus sont « pression E/S : some avg10 =
9x % » et « 6 tâche(s) en état D : 6 dd », sans constat CPU. Sur quatre
`lab31-calcul` et `lab31-journal`, « CPU saturé : file d'exécution
moyenne 4,x pour 2 CPU », « pression CPU » et « pression E/S » modérée, la
section profil montrant `compte_naif` en tête.

<!-- nav:début -->
---

[← Module 30](../30-sauvegarde-pra/corrige.md) · [Énoncé](README.md) · [Module 32 →](../32-fs-avances/corrige.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
