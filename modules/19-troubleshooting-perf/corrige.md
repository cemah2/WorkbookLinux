<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Partie III — Exploitation, sécurité et incidents › **Module 19** · corrigé  
[← Module 18](../18-securite/corrige.md) · [Énoncé](README.md) · [Projet A →](../../projets/P1-factura/corrige.md)

> [!TIP]
> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, pas avant. Chaque identifiant renvoie à son énoncé.
<!-- nav:fin -->

# Module 19 — Corrigé

## 19.3 Quiz — QCM

<a id="q19-1"></a>**[Q19.1](README.md#q19-1)** — *Charge à 38, `%idle` à 96 % : que conclure ?*

**Réponse : b)** les processus sont bloqués en attente d'E/S.

> [!NOTE]
> **Pourquoi**
>
> Sous Linux — et uniquement sous Linux — la charge moyenne ne compte pas
> seulement les processus qui veulent du CPU (`R`), mais aussi ceux qui sont en
> attente **ininterruptible** (`D`), c'est-à-dire bloqués dans un appel système sur
> une E/S disque, un montage NFS ou un périphérique qui ne répond pas. La
> définition historique d'UNIX, elle, ne compte que les *runnables*.
>
> Conséquence pratique : `load average` seul ne dit jamais « le CPU est saturé ».
> Il dit « il y a N tâches qui n'avancent pas ». La question suivante est toujours
> « pourquoi n'avancent-elles pas ? », et la réponse est dans `%idle` et `%iowait`.
>
> Ici, `%idle` à 96 % élimine le CPU. Il reste à compter les `D` :
>
> ```bash
> ps -eo state,pid,comm,wchan:30 | awk '$1 ~ /^D/'
> vmstat 1 5          # la colonne b
> cat /proc/pressure/io
> ```
>
> La colonne `wchan` donne la fonction noyau dans laquelle la tâche est bloquée :
> `io_schedule`, `nfs_wait_bit_killable`, `md_write_start`… C'est là que se trouve
> le nom du sous-système en panne.

> [!WARNING]
> **Piège**
>
> c) est faux : `mpstat` compte bien le temps noyau, c'est `%sys`. d) est faux :
> un zombie ne consomme rien et ne pèse pas sur la charge — il n'occupe qu'une
> entrée dans la table des processus. Et a) est l'erreur de raisonnement la plus
> coûteuse : déclarer une métrique « fausse » parce qu'elle contredit une
> intuition. La métrique a raison, c'est l'interprétation qui était mauvaise.

---

<a id="q19-2"></a>**[Q19.2](README.md#q19-2)** — *Sortie `vmstat` : `b=7`, `si=312`, `so=980`, `wa=85`.*

**Réponses : a) et c)**

> [!NOTE]
> **Pourquoi**
>
> Trois signaux concordent dans cette sortie.
>
> `si` et `so` (swap in / swap out, en Ko/s) ne sont pas nuls : la machine
> **déplace activement** des pages entre la RAM et le swap. C'est la définition du
> thrash. Attention à la nuance qui fait la différence entre un junior et un
> senior : `swpd` (512 Mo de swap occupés) ne prouve rien du tout — du swap
> occupé, c'est souvent de la mémoire froide rangée là il y a trois semaines et
> parfaitement inoffensive. Ce sont `si` et `so` qui comptent.
>
> `b=7` : sept processus en attente ininterruptible. Cohérent avec `wa=85` : 85 %
> du temps CPU est passé à attendre des E/S. Et ces E/S, ici, ce sont
> majoritairement les E/S de swap : le disque est occupé à paginer au lieu de
> servir l'application.
>
> `us=4` et `sy=9` : le CPU ne calcule quasiment rien. Le CPU n'est pas le
> problème, il est la victime.
>
> La suite logique : trouver qui mange la mémoire.
>
> ```bash
> ps -eo pid,comm,rss --sort=-rss | head
> for p in /proc/[0-9]*; do
>   printf '%8d %8s %s\n' "${p##*/}" \
>     "$(awk '/VmSwap/ {print $2}' "$p/status" 2>/dev/null)" \
>     "$(tr -d '\0' < "$p/comm" 2>/dev/null)"
> done | sort -k2 -n | tail
> ```

> [!WARNING]
> **Piège**
>
> d) est le piège classique de `free` : « `free` est bas donc la mémoire va
> bien / va mal ». Ni l'un ni l'autre. Ce qui compte est `available`, et ici
> l'activité de swap tranche à elle seule.

---

<a id="q19-3"></a>**[Q19.3](README.md#q19-3)** — *`%st` à 24 % sur une VM Proxmox.*

**Réponse : b)** du temps de CPU volé par l'hyperviseur.

> [!NOTE]
> **Pourquoi**
>
> `%steal` est le pourcentage de temps pendant lequel le vCPU de la VM **était
> prêt à exécuter du code** mais n'a pas obtenu de temps physique, parce que
> l'hyperviseur servait une autre VM. C'est l'hôte qui arbitre, la VM ne peut rien
> y faire : elle subit.
>
> À 24 %, un quart de la capacité annoncée n'existe pas. Tout ce que tu mesures
> dans cette VM est faussé : les temps de réponse s'allongent, les timeouts
> sautent, et les tests de performance ne veulent plus rien dire.
>
> Le diagnostic se poursuit **sur l'hôte Proxmox**, pas dans la VM :
>
> ```bash
> # sur l'hôte
> pvesh get /nodes/$(hostname)/status --output-format json | head
> cat /proc/pressure/cpu
> qm list                     # combien de vCPU alloués au total ?
> ```
>
> La cause habituelle est la surallocation : 40 vCPU distribués sur 16 cœurs
> physiques, ou une VM voisine qui boucle. Les correctifs sont côté hôte :
> réduire le nombre de vCPU (souvent contre-intuitif mais efficace : moins de
> vCPU à ordonnancer, moins d'attente), ajuster les `cpuunits`, épingler les
> cœurs, ou déplacer une VM.

> [!WARNING]
> **Piège**
>
> Le réflexe fatal est d'« optimiser l'application » parce que la VM répond mal.
> Tant que `%st` est élevé, aucune optimisation interne ne sera mesurable : tu
> vas passer trois jours à profiler du code pendant que le problème est à
> l'étage du dessus. Première règle du diagnostic en environnement virtualisé :
> regarder `%st` avant tout le reste.

---

<a id="q19-4"></a>**[Q19.4](README.md#q19-4)** — *`free -m` : `free` à 118 Mo, `available` à 2740 Mo.*

**Réponse : c)** non, `available` est à 2740 Mo.

> [!NOTE]
> **Pourquoi**
>
> Linux se sert de toute la RAM inutilisée comme cache de pages, parce qu'une RAM
> vide ne sert à rien. `free` (la colonne) mesure donc la RAM *gaspillée*, pas la
> RAM disponible. Sur un serveur en bonne santé qui tourne depuis une semaine,
> `free` est toujours bas ; c'est le signe que le cache fonctionne.
>
> `available` est calculé par le noyau (`MemAvailable` dans `/proc/meminfo`) : il
> estime ce qu'une nouvelle application pourrait obtenir sans provoquer de swap,
> en tenant compte de la part du cache réellement récupérable et des seuils de
> maintien (`watermark`). C'est la seule valeur à surveiller, et c'est elle qu'il
> faut mettre dans les alertes.
>
> ```bash
> free -m
> awk '/MemTotal|MemFree|MemAvailable|Cached|SwapTotal|SwapFree/' /proc/meminfo
> ```
>
> Règle d'alerte utilisable : `available` sous 10 % de `MemTotal` **et** `si/so`
> non nuls. L'un sans l'autre ne mérite pas de réveiller quelqu'un.

---

<a id="q19-5"></a>**[Q19.5](README.md#q19-5)** — *Trace `dmesg` de l'OOM killer.*

**Réponses : a) et c)**

> [!NOTE]
> **Pourquoi**
>
> La première ligne, `vitrine-api invoked oom-killer`, nomme le processus **qui a
> demandé une allocation** au moment où le noyau n'avait plus de page à donner.
> Elle ne désigne pas le coupable : c'est simplement celui qui a eu la
> malchance de demander en dernier. Sur une machine saturée par un processus A,
> c'est très souvent le processus B, innocent, qui déclenche l'OOM.
>
> La ligne `Killed process 2244 (vitrine-api)` nomme la **victime**, choisie par
> le noyau après calcul d'un score sur tous les candidats. Ici c'est le même
> processus, ce qui est fréquent (le gros consommateur alloue souvent), mais ce
> n'est pas une règle.
>
> Le score (`oom_badness`) est grossièrement proportionnel à la mémoire *utilisée*
> par la tâche — RSS anonyme + swap + tables de pages — et corrigé par
> `oom_score_adj` (de -1000 à +1000), qui ajoute un pourcentage de la mémoire
> totale. `oom_score_adj=0` signifie donc « aucun réglage particulier », pas
> « protégé ». Pour lire les scores avant l'incident :
>
> ```bash
> for p in /proc/[0-9]*; do
>   printf '%6s %5s %s\n' "${p##*/}" "$(cat "$p/oom_score" 2>/dev/null)" \
>     "$(tr -d '\0' < "$p/comm" 2>/dev/null)"
> done | sort -k2 -n | tail -5
> ```
>
> Entre le déclencheur et la victime, la trace contient le tableau complet des
> tâches (`Tasks state`) avec leur RSS : c'est **là** qu'on trouve le vrai
> coupable, celui qui avait accumulé la mémoire.

> [!WARNING]
> **Piège**
>
> d) est l'erreur de lecture la plus fréquente. `oom_score_adj=-1000` rend une
> tâche intuable par l'OOM killer ; `0` est la valeur par défaut de tout le monde.
> Et protéger la mauvaise tâche a des conséquences : mettre
> `OOMScoreAdjust=-1000` sur ta base de données garantit que le noyau ira tuer
> autre chose — parfois `sshd`, et tu perds la machine.

---

<a id="q19-6"></a>**[Q19.6](README.md#q19-6)** — *`df` à 100 %, `du` à 3,2 Go sur 20 Go.*

**Réponse : b)** `lsof +L1`.

> [!NOTE]
> **Pourquoi**
>
> `du` parcourt l'**arborescence** : il additionne la taille des fichiers qui ont
> encore un nom. `df` interroge le **système de fichiers** : il compte les blocs
> réellement alloués. L'écart vient de ce qui consomme des blocs sans avoir de
> nom, c'est-à-dire un fichier supprimé (`unlink`) dont un processus garde un
> descripteur ouvert. Le noyau ne libère les blocs qu'au dernier `close()`.
>
> `lsof +L1` liste exactement ces fichiers : `+L1` signifie « ceux dont le nombre
> de liens est inférieur à 1 ».
>
> ```bash
> sudo lsof +L1 | head
> # COMMAND PID  USER FD  TYPE DEVICE SIZE/OFF    NLINK NODE NAME
> # nginx   1841 root 5w  REG  253,1  16903041024 0     1573 \
> #   /var/log/nginx/access.log (deleted)
> ```
>
> a) est utile mais donne la même réponse que `du` : rien. c) répond à une autre
> question (les inodes, quand `df` montre de la place mais que l'écriture échoue).
> b) ne trouve que des fichiers *existants*.

> [!WARNING]
> **Piège**
>
> Deuxième cause d'écart, plus sournoise : un répertoire monté **par-dessus** des
> données. Si `/var/log` contenait 12 Go avant qu'on y monte un volume, ces 12 Go
> sont toujours là, cachés sous le point de montage, comptés par `df` du système
> de fichiers parent et invisibles pour `du`. On les retrouve en montant la
> racine ailleurs : `mount --bind / /mnt && du -xsh /mnt/var/log`.

---

<a id="q19-7"></a>**[Q19.7](README.md#q19-7)** — *Récupérer l'espace sans redémarrer `nginx`.*

**Réponses : b) et c)**

> [!NOTE]
> **Pourquoi**
>
> Le fichier n'a plus de nom : on ne peut donc pas le désigner par un chemin. En
> revanche, `/proc/<pid>/fd/<n>` est un lien vers l'inode encore ouvert, et
> écrire à travers ce lien agit sur le fichier réel.
>
> ```bash
> sudo lsof +L1 | grep nginx            # -> PID 1841, FD 5w
> sudo truncate -s 0 /proc/1841/fd/5    # ou : sudo sh -c ': > /proc/1841/fd/5'
> df -h /var                            # l'espace est rendu immédiatement
> ```
>
> Les deux formes font la même chose : ouvrir le fichier via le lien de `/proc`
> en mode troncature. Le processus continue d'écrire dans le même inode, sans
> rien remarquer, et l'espace est libéré à l'instant.
>
> Effet de bord à connaître : si le processus écrivait avec un descripteur en mode
> `O_APPEND`, tout va bien ; sinon son offset interne reste là où il était, et le
> fichier redevient « grand » (un fichier creux, avec un trou au début). Les blocs
> du trou ne sont pas alloués : l'espace reste récupéré, mais `ls -l` affiche de
> nouveau une taille énorme. C'est normal, `du` le confirme.
>
> La vraie correction reste de recharger le service pour qu'il rouvre ses
> fichiers (`nginx -s reopen`, `systemctl reload`, `kill -USR1`) et de réparer la
> rotation de logs qui a supprimé au lieu de tourner (`copytruncate` ou
> `postrotate` manquant).

> [!WARNING]
> **Piège**
>
> d) ne libère pas un octet : `drop_caches` vide le cache de pages, qui n'occupe
> pas d'espace disque. C'est la commande « magique » qu'on lit sur les forums,
> elle ne fait qu'aggraver les performances pendant quelques minutes, le temps que
> le cache se reconstruise.

---

<a id="q19-8"></a>**[Q19.8](README.md#q19-8)** — *`w_await 480 ms`, `aqu-sz 12.8`, `%util 99.9`.*

**Réponse : b)** disque saturé en écriture.

> [!NOTE]
> **Pourquoi**
>
> Les colonnes à lire dans `iostat -xz 1`, dans cet ordre :
>
> | Colonne | Ce qu'elle dit |
> |---|---|
> | `r_await` / `w_await` | latence moyenne vue par l'application, en ms |
> | `aqu-sz` | profondeur moyenne de la file d'attente |
> | `r/s`, `w/s`, `rkB/s`, `wkB/s` | le volume réellement demandé |
> | `%util` | part du temps où au moins une requête est en vol |
>
> Ici `r_await` à 0,4 ms est excellent : les lectures sortent du cache. Les
> écritures, elles, attendent presque une demi-seconde avec une file de 12,8
> requêtes. Traduction métier : « chaque écriture de l'application attend
> 480 ms ». C'est cela qu'on remonte, pas des pourcentages.
>
> La suite : qui écrit ?
>
> ```bash
> sudo iotop -oPa          # ou :
> sudo pidstat -d 1 5      # kB_wr/s par processus
> ```

> [!WARNING]
> **Piège**
>
> c) est la confusion la plus répandue. `%util` mesure le temps pendant lequel la
> file n'était pas vide. Sur un disque mécanique à une seule tête, 100 % veut bien
> dire saturé. Sur un SSD NVMe capable de traiter 32 requêtes en parallèle, on
> peut être à 100 % de `%util` avec 5 % de la capacité réelle utilisée : la
> métrique n'a plus de sens. Sur du stockage moderne, on juge sur `await` et sur
> le débit, jamais sur `%util` seul.

---

<a id="q19-9"></a>**[Q19.9](README.md#q19-9)** — *`Cannot assign requested address` sur les appels sortants.*

**Réponse : b)** plage de ports éphémères épuisée.

> [!NOTE]
> **Pourquoi**
>
> `EADDRNOTAVAIL` (errno 99) au moment d'un `connect()` signifie que le noyau n'a
> pas trouvé de port source libre pour créer le quadruplet (IP source, port
> source, IP destination, port destination). Chaque connexion sortante consomme un
> port éphémère, et ce port reste immobilisé en `TIME_WAIT` pendant 60 secondes
> après la fermeture (valeur figée dans le noyau Linux, `TCP_TIMEWAIT_LEN`).
>
> Le calcul de capacité à savoir faire de tête :
>
> ```bash
> sysctl net.ipv4.ip_local_port_range     # 32768 60999 -> 28 232 ports
> ss -tan state time-wait | wc -l         # combien sont immobilisés
> ss -s                                   # vue d'ensemble
> ```
>
> 28 232 ports / 60 s de `TIME_WAIT` = environ **470 nouvelles connexions par
> seconde** vers une même destination, au maximum. Au-delà, ça casse. Une
> application qui ouvre une connexion par requête HTTP au lieu de réutiliser un
> pool atteint ce plafond très vite.
>
> Correctifs, du meilleur au moins bon : réutiliser les connexions côté
> application (keep-alive, pool) ; élargir la plage
> (`net.ipv4.ip_local_port_range = 10240 65535`) ; activer
> `net.ipv4.tcp_tw_reuse=1`, qui autorise la réutilisation d'un `TIME_WAIT` pour
> une nouvelle connexion **sortante** (sans danger, contrairement à l'option
> `tcp_tw_recycle` qui n'existe plus depuis le noyau 4.12 parce qu'elle cassait
> le NAT).

> [!WARNING]
> **Piège**
>
> a) et c) donnent d'autres erreurs : `EAI_NONAME` / `Name or service not known`
> pour le DNS, `ETIMEDOUT` ou `ECONNREFUSED` pour un pare-feu. Lire le **numéro
> d'errno** avant de supposer est ce qui fait gagner vingt minutes.

---

<a id="q19-10"></a>**[Q19.10](README.md#q19-10)** — *`nf_conntrack: table full, dropping packet`.*

**Réponse : b)** les nouvelles connexions échouent, les anciennes passent.

> [!NOTE]
> **Pourquoi**
>
> Le suivi de connexions (`conntrack`) maintient une entrée par flux pour que
> Netfilter sache faire du `ESTABLISHED,RELATED` et du NAT. Quand la table est
> pleine, les paquets qui créeraient une **nouvelle** entrée sont jetés. Les flux
> déjà suivis continuent de passer : d'où un symptôme partiel et déroutant, « ça
> marche pour ceux qui sont déjà connectés ».
>
> ```bash
> sudo conntrack -C                                   # entrées utilisées
> sysctl net.netfilter.nf_conntrack_max               # capacité
> sudo conntrack -L | awk '{print $1,$3}' | sort | uniq -c | sort -rn | head
> dmesg -T | grep -i conntrack
> ```
>
> Correctifs : augmenter `nf_conntrack_max` (et les *buckets* :
> `nf_conntrack_buckets = nf_conntrack_max / 4`), réduire les délais
> (`nf_conntrack_tcp_timeout_established`, 5 jours par défaut, ce qui est
> absurde), ou exclure du suivi les flux qui n'en ont pas besoin
> (`iptables -t raw ... -j NOTRACK`). Chaque entrée coûte environ 300 octets :
> 262 144 entrées, c'est 80 Mo de RAM noyau, ce qui se décide, pas se subit.

---

<a id="q19-11"></a>**[Q19.11](README.md#q19-11)** — *`start request repeated too quickly`.*

**Réponse : a)** `reset-failed` puis relance, et remonter au vrai crash.

> [!NOTE]
> **Pourquoi**
>
> `start-limit-hit` n'est pas une panne : c'est un **garde-fou**. systemd compte
> les démarrages sur une fenêtre (`StartLimitIntervalSec`, 10 s par défaut) et
> refuse d'aller plus loin au-delà de `StartLimitBurst` (5 par défaut). Il te dit
> « ton service a échoué cinq fois de suite, je m'arrête pour ne pas boucler ».
>
> Le message affiché est donc le **dernier** événement, celui qui masque la cause.
> Tout l'art consiste à remonter au premier :
>
> ```bash
> systemctl reset-failed vitrine-api          # remet le compteur à zéro
> journalctl -u vitrine-api -b --no-pager | head -60   # les premiers messages
> journalctl -u vitrine-api --since '10 min ago' -o short-precise
> systemctl status vitrine-api -l --no-pager
> ```
>
> Le vrai message est presque toujours dans les premières lignes de la boucle :
> `Address already in use`, `Permission denied`, `No such file or directory`,
> `Failed to parse config`.

> [!WARNING]
> **Piège**
>
> b) est le pansement qui transforme un service cassé en service cassé **qui
> consomme du CPU en boucle**, et qui remplit le disque de journaux — on a vu des
> incidents de disque plein causés par une boucle de redémarrage laissée une nuit.
> Si tu dois vraiment stabiliser dans l'urgence, augmente `RestartSec` (espacer
> les tentatives), pas `StartLimitBurst`.

---

<a id="q19-12"></a>**[Q19.12](README.md#q19-12)** — *Processus bloqué depuis 10 minutes sans CPU.*

**Réponse : b)** `/proc` d'abord, `strace` ensuite et brièvement.

> [!NOTE]
> **Pourquoi**
>
> L'ordre est dicté par le coût. Tout ce qui est dans `/proc` est gratuit : c'est
> le noyau qui l'expose, il n'y a ni interception ni ralentissement.
>
> ```bash
> grep -E 'State|Threads|voluntary' /proc/PID/status
> cat /proc/PID/wchan; echo          # fonction noyau où ça bloque
> sudo cat /proc/PID/stack           # pile noyau complète (root)
> ls -l /proc/PID/fd | tail          # sur quel fichier / socket
> sudo cat /proc/PID/syscall         # appel système en cours + arguments
> ```
>
> `State: D (disk sleep)` + `wchan` à `io_schedule` = attente disque.
> `State: S (sleeping)` + un `wchan` réseau = attente d'un pair qui ne répond
> pas. Dans les deux cas on a la réponse en dix secondes, sans toucher au
> processus.
>
> `strace -p` ne vient qu'après, et quelques secondes seulement : il attache
> `ptrace`, ce qui arrête le processus à chaque appel système. Sur un processus
> **bloqué**, il n'affichera d'ailleurs rien d'autre que l'appel en cours — ce
> qui est déjà une information, mais que `/proc/PID/syscall` donne gratuitement.

> [!WARNING]
> **Piège**
>
> c) est faux : `SIGQUIT` ne produit un vidage mémoire que si l'application le
> prévoit (c'est une convention de la JVM, pas une règle Unix) et il **tue** le
> processus si le cœur n'est pas configuré. d) fige le processus pendant toute la
> session `gdb` : sur un service de production, c'est une indisponibilité. `gdb`
> en mode `-batch` reste une excellente option, mais en dernier recours et en
> sachant ce qu'on paie.

---

<a id="q19-13"></a>**[Q19.13](README.md#q19-13)** — *`active (running)` mais `Connection refused`.*

**Réponses : a) et b)**

> [!NOTE]
> **Pourquoi**
>
> `active (running)` signifie seulement que le processus principal existe encore.
> systemd ne sait rien de ce que fait ce processus : avec `Type=simple`, l'unité
> est déclarée active dès le `fork()`, bien avant que l'application ait ouvert son
> socket — et même si elle ne l'ouvre jamais.
>
> Les deux commandes qui tranchent :
>
> ```bash
> ss -tulpn | grep 8080
> # rien -> le processus n'écoute pas du tout
> # 127.0.0.1:8080 -> il écoute, mais seulement sur la boucle locale
> journalctl -u vitrine-api -n 50 --no-pager
> # "Permission denied", "config parse error", "waiting for database"...
> ```
>
> Trois causes couvrent 90 % des cas : l'application écoute sur `127.0.0.1` alors
> qu'on l'interroge depuis l'extérieur ; elle est encore en train d'initialiser
> (migration de schéma, chargement d'index) ; elle a échoué silencieusement après
> le démarrage et tourne en boucle d'erreur sans sortir.

> [!WARNING]
> **Piège**
>
> `systemctl cat` (d) est utile pour **comprendre** la configuration, mais ne dit
> rien de l'état courant. Et `ping 127.0.0.1` (c) teste la pile IP locale, qui
> n'est jamais en cause : `Connection refused` prouve déjà que le paquet est
> arrivé jusqu'à la pile TCP de la machine et que personne n'écoutait.

---

<a id="q19-14"></a>**[Q19.14](README.md#q19-14)** — *Où lire la limite réellement appliquée ?*

**Réponse : c)** `cat /proc/<pid>/limits`.

> [!NOTE]
> **Pourquoi**
>
> Les limites sont des attributs **du processus**, hérités à sa création. Elles
> ne changent pas quand tu modifies un fichier de configuration, et celles de ton
> shell n'ont aucun rapport avec celles d'un démon lancé par systemd il y a trois
> semaines.
>
> ```bash
> PID=$(systemctl show vitrine-api -p MainPID --value)
> grep -E 'Max open files|Max processes' /proc/$PID/limits
> ls -1 /proc/$PID/fd | wc -l        # combien sont réellement ouverts
> ```
>
> La chaîne complète de provenance, à connaître :
>
> * pour un service systemd : `LimitNOFILE=` de l'unité, sinon
>   `DefaultLimitNOFILE=` de `/etc/systemd/system.conf`. **`limits.conf` n'est pas
>   lu du tout** : c'est un module PAM, et un service systemd ne passe pas par PAM.
> * pour une session interactive : `pam_limits` lit `/etc/security/limits.conf` et
>   `/etc/security/limits.d/`.
> * `fs.file-max` (d) est le plafond **global de la machine**, pas celui du
>   processus. Le dépasser donne `ENFILE` (`Too many open files in system`), un
>   message différent de `EMFILE`.

> [!WARNING]
> **Piège**
>
> Sur Ubuntu 24.04, la limite souple par défaut d'un service est de 1024 alors que
> la limite dure est à 524 288. Beaucoup d'applications réclament donc
> explicitement `LimitNOFILE=65535` — et beaucoup d'administrateurs éditent
> `limits.conf`, redémarrent le service, constatent que rien n'a changé, et
> concluent que « ça ne marche pas ». Ça marche très bien : ce n'est simplement
> pas le bon fichier.

---

<a id="q19-15"></a>**[Q19.15](README.md#q19-15)** — *`emergency mode` après le retrait d'un disque listé dans `fstab`.*

**Réponse : b)** ajouter `nofail` et une temporisation courte.

> [!NOTE]
> **Pourquoi**
>
> systemd génère une unité `.mount` par ligne de `fstab`. Par défaut, ces unités
> sont exigées par `local-fs.target`, lui-même requis par le démarrage normal :
> un montage qui échoue fait donc échouer la cible et bascule la machine en mode
> `emergency`, console série ou rien du tout.
>
> ```ini
> # /etc/fstab
> UUID=1c3f...  /srv/data  ext4  defaults,nofail,x-systemd.device-timeout=5s  0 2
> ```
>
> `nofail` transforme l'échec en avertissement : le boot continue sans le
> montage. `x-systemd.device-timeout=5s` évite en plus d'attendre 90 secondes que
> le périphérique apparaisse. C'est le réglage à mettre sur **tout montage non
> vital** : volumes de données secondaires, NFS, disques de sauvegarde.
>
> Quand on est déjà tombé en mode `emergency` : on tape le mot de passe root, le
> système de fichiers racine est monté en lecture seule, donc
>
> ```bash
> mount -o remount,rw /
> vi /etc/fstab            # corriger ou commenter la ligne fautive
> systemctl daemon-reload
> systemctl default        # repartir sans redémarrer
> ```

> [!WARNING]
> **Piège**
>
> a) et c) « marchent » mais suppriment une information : le jour où le disque
> revient, plus personne ne sait qu'il devait être monté, ni où. `noauto` oblige à
> une action manuelle après chaque redémarrage, ce qui finit toujours par être
> oublié un dimanche. `nofail` garde l'intention documentée dans `fstab` tout en
> rendant le boot robuste. Et d) désactive une vérification de sécurité pour
> cacher un symptôme : c'est comment on perd un système de fichiers.

---

<a id="q19-16"></a>**[Q19.16](README.md#q19-16)** — *`systemd-analyze blame` : `cloud-init.service` à 32 s.*

**Réponse : b)** rien directement, il faut `critical-chain`.

> [!NOTE]
> **Pourquoi**
>
> `blame` trie les unités par **durée d'exécution**, sans tenir compte du
> parallélisme. Une unité peut avoir duré 32 secondes en arrière-plan pendant que
> tout le reste démarrait, sans avoir retardé le boot d'une seconde.
>
> ```bash
> systemd-analyze                     # total, décomposé noyau / userspace
> systemd-analyze blame | head -10    # les plus longues
> systemd-analyze critical-chain      # celles qui ont réellement retardé
> systemd-analyze critical-chain multi-user.target
> systemd-analyze plot > /tmp/boot.svg   # la vue la plus parlante
> ```
>
> Dans `critical-chain`, `@` donne l'instant où l'unité est devenue active et `+`
> sa durée. Seules les unités affichées dans cette chaîne sont sur le chemin
> critique : optimiser les autres ne gagne rien.

> [!WARNING]
> **Piège**
>
> Sur une VM cloud, les suspects récurrents du chemin critique sont
> `systemd-networkd-wait-online.service` (attend une interface qui n'obtiendra
> jamais d'adresse) et les montages réseau sans `nofail`. Là, on gagne
> réellement 30 à 120 secondes, et pas en désactivant `cloud-init` au hasard.

---

<a id="q19-17"></a>**[Q19.17](README.md#q19-17)** — *Avant un redémarrage demandé en urgence.*

**Réponses : a), b) et d)**

> [!NOTE]
> **Pourquoi**
>
> Un redémarrage détruit presque toutes les preuves : la mémoire, la table des
> processus, les sockets, les descripteurs ouverts, le contenu de `/tmp`, les
> journaux non persistants (`journald` en mode `volatile`). Après, il ne restera
> que des suppositions — et un incident qui se reproduira parce qu'on n'aura
> jamais su pourquoi.
>
> La collecte tient en deux minutes, et deux minutes sont toujours négociables :
>
> ```bash
> D=/var/tmp/preuves-$(date +%F-%H%M%S); mkdir -p "$D"
> ps auxf            > "$D/ps.txt"
> ss -tanp           > "$D/sockets.txt"
> free -m            > "$D/memoire.txt"
> { df -h; df -i; } > "$D/disque.txt"
> dmesg -T           > "$D/dmesg.txt"
> { uptime; top -b -n1; } > "$D/charge.txt"
> systemctl --failed > "$D/unites.txt"
> journalctl --since '-30 min' > "$D/journal.txt"
> tar czf "$D.tar.gz" "$D" && scp "$D.tar.gz" mathieu@10.10.10.10:/srv/preuves/
> ```
>
> Le point d) n'est pas cosmétique : horodater la décision de redémarrer, et
> l'annoncer, c'est ce qui permet ensuite de corréler la chronologie des
> journaux avec ce qu'ont vu les utilisateurs. Sans cette marque, la chronologie
> du post-mortem est invérifiable.

> [!WARNING]
> **Piège**
>
> c) est l'erreur inverse, tout aussi coûteuse : retarder le rétablissement pour
> collecter « encore un peu ». Trente minutes de `strace` pendant que le site est
> à terre ne se justifient jamais. La règle : quelques minutes de captures à
> faible coût, puis on rétablit, puis on analyse les captures à froid.

---

<a id="q19-18"></a>**[Q19.18](README.md#q19-18)** — *Formulation acceptable dans un post-mortem blameless.*

**Réponse : b)**

> [!NOTE]
> **Pourquoi**
>
> La formulation b) décrit un **mécanisme** (un changement est passé sans
> validation) et désigne la faiblesse du système (la validation n'était pas
> obligatoire sur cette branche). Elle débouche naturellement sur une action
> corrective vérifiable : rendre la validation obligatoire.
>
> a) et c) désignent des personnes ou des équipes : le résultat est que la
> prochaine fois, l'information remontera plus tard, ou pas du tout. Un
> post-mortem qui blâme apprend à l'organisation à cacher les incidents.
>
> b) est pire, parce qu'elle a l'air professionnelle : « erreur humaine » n'est
> jamais une cause racine, c'est l'endroit où l'analyse s'est arrêtée. Et « rappel
> des consignes » n'est pas une action corrective : rien n'a changé dans le
> système, la même erreur reste possible demain.
>
> Le test à appliquer à chaque phrase d'un post-mortem : *si la personne
> concernée avait été en vacances ce jour-là, l'incident aurait-il pu se
> produire quand même ?* Si oui, la cause n'est pas la personne.

---

<a id="q19-19"></a>**[Q19.19](README.md#q19-19)** — *`%util` à 98 %, `w_await` 3 ms, `aqu-sz` 0,31 : saturé ?*

**Réponse : b)**

> [!NOTE]
> **Pourquoi**
>
> `%util` est le pourcentage du temps pendant lequel le périphérique avait
> **au moins une** requête en vol. Sur un disque qui ne sait traiter qu'une
> requête à la fois (un HDD sans NCQ), 100 % voulait dire saturé. Sur un
> SSD, un NVMe, une baie ou un disque virtuel Proxmox adossé à un SSD, le
> périphérique en traite des dizaines en parallèle : il peut être « occupé »
> 100 % du temps avec une seule requête en cours et en accepter vingt de plus
> sans ralentir. Ce sont `await` (la latence vue par le demandeur) et
> `aqu-sz` (combien attendent) qui mesurent la **saturation**. Ici 3 ms et
> 0,31 : chaque écriture est servie presque aussitôt ; le disque encaisse
> 95 Mo/s en gros blocs (97 280 / 95 ≈ 1 Mo par requête) sans souffrir.
> Q19.8 montrait l'inverse : `w_await 480`, `aqu-sz 12.8` — là, saturé.

> [!WARNING]
> **Piège**
>
> La page de manuel d'`iostat` le dit elle-même : « Device saturation occurs
> when this value is close to 100 % **for devices serving requests
> serially** ». Arrêter la sauvegarde sur la foi de `%util` (a) est l'erreur
> type d'une lecture à une seule colonne. Et `wareq-sz` manque dans le
> tableau parce que l'énoncé l'a coupé, pas parce que les écritures sont
> aléatoires : `wkB/s ÷ w/s` le recalcule.

---

<a id="q19-20"></a>**[Q19.20](README.md#q19-20)** — *PSI mémoire : `full avg10=21.05`.*

**Réponse : b)**

> [!NOTE]
> **Pourquoi**
>
> PSI (*Pressure Stall Information*) mesure du **temps perdu**, pas de
> l'occupation. `some` : fraction du temps où au moins une tâche était bloquée
> à attendre la ressource ; `full` : fraction du temps où **toutes** les
> tâches non inactives l'étaient — la machine entière piétine. `avg10` est la
> moyenne glissante sur dix secondes. Pour la mémoire, un `full` non nul
> signifie que le noyau passe son temps à récupérer des pages (écriture vers
> le swap, éviction de cache puis relecture) : c'est la définition du
> thrash, et `vmstat` doit le confirmer par `si`/`so` non nuls et `wa` en
> hausse. `total` est un compteur cumulé en microsecondes : sa dérivée donne
> la pression instantanée, c'est ce que trace un agent de supervision.

> [!WARNING]
> **Piège**
>
> d) était vrai pour `/proc/pressure/cpu` jusqu'au noyau 5.13 : la ligne
> `full` n'y existait pas (il y a toujours au moins une tâche qui tourne sur
> le CPU). Depuis, elle est présente mais reste à zéro au niveau système et
> n'a de sens que par cgroup. Pour la mémoire et l'E/S, `full` a toujours
> existé. PSI exige `CONFIG_PSI=y` — le cas d'Ubuntu et de Rocky.

---

<a id="q19-21"></a>**[Q19.21](README.md#q19-21)** — *`perf` ne montre que `_PyEval_EvalFrameDefault` (deux
réponses).*

**Réponse : b) et c)**

> [!NOTE]
> **Pourquoi**
>
> `perf` échantillonne des adresses machine et les résout avec les symboles
> des binaires : pour un programme interprété, l'adresse est toujours dans la
> boucle d'évaluation de l'interpréteur, quelle que soit la fonction Python en
> cours. CPython 3.12 a ajouté `-X perf` (ou `PYTHONPERFSUPPORT=1`) : il
> génère à la volée un petit trampoline par fonction Python et écrit
> `/tmp/perf-PID.map`, la table que `perf` utilise pour les symboles JIT.
> `perf report` affiche alors `py::chercher_client:/home/…/rapport-tva.py`
> avec la pile d'appels. `cProfile` est l'approche par le langage : exact
> par fonction, mais il instrumente chaque appel (surcoût de 30 à 100 %) et ne
> voit pas le temps passé dans le C ou le noyau. Les deux se complètent :
> `perf` pour la vue système, `cProfile` pour confirmer au niveau du code.

> [!WARNING]
> **Piège**
>
> d) `strace -c` compte les **appels système**, pas les fonctions : un
> programme CPU-bound fait très peu d'appels système et `strace -c` affiche
> un tableau vide de sens — tout en le ralentissant. Le choix de l'outil suit
> le diagnostic : `top` dit CPU utilisateur à 100 % → profileur (`perf`) ;
> `top` dit `wa` ou `sy` → traceur (`strace`, `perf trace`).

---

<a id="q19-22"></a>**[Q19.22](README.md#q19-22)** — *`r` = 9, `us` = 92, deux vCPU à 100 %.*

**Réponse : c)**

> [!NOTE]
> **Pourquoi**
>
> `r` compte les tâches **prêtes** à tourner (en cours ou en attente d'un
> cœur) : neuf pour deux vCPU, en continu, c'est une file d'attente de sept.
> `b` = 0 exclut les E/S bloquantes, `wa` = 0 exclut l'attente disque, `st` = 0
> exclut l'hyperviseur, `us` = 92 dit que le temps part en espace utilisateur,
> donc dans du code applicatif, pas dans le noyau. Le goulot est le CPU, la
> saturation est mesurable (`r` − vCPU, ou `/proc/pressure/cpu`), et la
> suite est « qui » (`pidstat -u 1`, `top` trié par `P`) puis « où dans le
> code » (`perf top -p PID`, ou `perf record -g`).

> [!WARNING]
> **Piège**
>
> La charge moyenne aurait donné le même chiffre (≈ 9) sans dire si c'était
> du CPU ou du disque : c'est exactement l'ambiguïté que `vmstat` (`r`
> contre `b`) et PSI lèvent. Et un `us` élevé avec un seul vCPU à 100 % dans
> `mpstat -P ALL` (l'autre libre) est un autre diagnostic : un programme
> mono-thread, que plus de cœurs n'aideront pas.

---

## 19.4 Quiz — questions ouvertes

<a id="qo19-1"></a>**[QO19.1](README.md#qo19-1)** — *Méthode de diagnostic appliquée à « depuis ce matin le site est
lent ».*

**Réponse attendue**

Les quatre questions de délimitation, avant même de se connecter :

1. **Depuis quand exactement ?** « Ce matin » n'est pas une donnée. On cherche
   une heure, et on la recoupe avec les métriques. Une bascule nette à 08 h 42
   pointe un changement ; une dégradation progressive depuis 06 h pointe une
   accumulation (fuite, remplissage, saturation).
2. **Pour qui ?** Tous les utilisateurs, ou certains ? Depuis le réseau
   interne ou depuis internet ? Une seule page ou toutes ? Cela sépare
   immédiatement un problème applicatif d'un problème réseau ou DNS.
3. **Qu'est-ce qui a changé ?** Déploiement, mise à jour de paquets, changement
   de configuration, purge de cache, opération sur l'hyperviseur, augmentation
   du trafic. La réponse est presque toujours « rien », et elle est presque
   toujours fausse : on vérifie soi-même (`journalctl --since`, historique de
   paquets, historique git de la configuration).
4. **Est-ce que ça marchait vraiment avant ?** Existe-t-il une mesure d'avant ?
   Sans baseline, « lent » n'est pas falsifiable.

Les six étapes ensuite :

1. **Formuler le symptôme de façon mesurable** : « la page produits répond en
   5,1 s au 95e centile, contre 180 ms hier à la même heure ». On ne travaille
   jamais sur « c'est lent ».
2. **Reproduire** : `curl -w` depuis `lab-ops`, puis depuis la machine
   elle-même. Si ce n'est pas reproductible, le périmètre change (réseau, un
   seul client, un cache intermédiaire).
3. **Trier les ressources** : la checklist des 60 secondes. On cherche à
   **éliminer** trois ressources sur quatre.
4. **Bisection** : couper le chemin en deux et mesurer au milieu. Client →
   reverse proxy → application → base → dépendance externe. Mesurer à chaque
   étage divise le périmètre par deux à chaque fois.
5. **Hypothèse → test → conclusion** : « si le temps part dans la résolution
   DNS, alors `curl -w %{time_namelookup}` doit montrer 5 s ». Le test doit
   pouvoir **infirmer** l'hypothèse, sinon ce n'est pas un test.
6. **Corriger une chose à la fois, vérifier, noter.** Après chaque
   modification, on remesure la métrique du point 1. Ce qui n'a rien changé est
   remis en état.

> [!NOTE]
> **Pourquoi**
>
> Ce qui distingue un diagnostic d'un tâtonnement, ce n'est pas la connaissance
> des commandes : c'est la falsifiabilité. Une hypothèse comme « c'est peut-être
> le réseau » ne se teste pas. « Le temps de connexion TCP dépasse 1 s vers
> 10.10.10.12 » se teste en une commande, et le résultat fait avancer quel que
> soit le verdict.
>
> L'autre différence est la trace écrite. Au bout de 40 minutes d'incident, sans
> notes, personne ne sait plus quelles hypothèses ont été éliminées ni quelles
> modifications sont encore en place. C'est ainsi qu'on « répare » un incident en
> laissant derrière soi trois changements non documentés qui causeront le
> suivant.

---

<a id="qo19-2"></a>**[QO19.2](README.md#qo19-2)** — *USE contre les quatre signaux dorés.*

**Réponse attendue**

**USE** part des ressources : pour chacune (CPU, mémoire, disque, réseau, et
aussi les ressources logicielles : descripteurs, ports, conntrack, threads), on
mesure l'utilisation, la saturation et les erreurs. C'est une méthode
d'**inventaire** : elle garantit qu'on n'oublie pas une ressource.

Les **quatre signaux dorés** (latence, trafic, erreurs, saturation) partent du
service tel que l'utilisateur le vit. C'est une méthode de **priorisation** :
elle dit s'il faut réveiller quelqu'un.

Exemple où les deux divergent : une dépendance externe (une API de paiement)
répond en 8 s. Les signaux dorés hurlent — latence x40, taux d'erreur en
hausse, utilisateurs bloqués. USE ne voit **rien** : le CPU est à 3 %, la
mémoire est libre, le disque dort, le réseau est vide. La machine va très bien,
le service est mort.

Exemple inverse : un disque se remplit à 94 % et son `await` triple. USE
alerte ; les signaux dorés sont au vert parce que le cache absorbe encore tout.
Il reste peut-être deux heures avant la panne — c'est exactement le moment où
il faut agir, et seul USE le voit.

* USE est aveugle à tout ce qui se passe **hors de la machine** : dépendances,
  DNS, certificats expirés, erreurs de logique applicative, files d'attente
  côté client.
* Les signaux dorés sont aveugles aux problèmes **qui n'ont pas encore
  d'impact** : ils constatent, ils n'anticipent pas.

En pratique on alerte sur les signaux dorés (impact utilisateur) et on
diagnostique avec USE (cause). L'alerte réveille ; USE oriente.

> [!WARNING]
> **Piège**
>
> La saturation apparaît dans les deux méthodes, et c'est volontaire : c'est la
> métrique la plus prédictive et la plus souvent absente des tableaux de bord. On
> mesure partout des moyennes d'utilisation (« CPU à 60 % »), presque jamais des
> files d'attente (`runq-sz`, `aqu-sz`, longueur du pool de connexions, backlog
> d'acceptation). Or c'est la file qui explose en premier.

---

<a id="qo19-3"></a>**[QO19.3](README.md#qo19-3)** — *« 60 secondes sur un serveur de production qui rame. »*

**Réponse attendue**

```bash
uptime              # 1, 5, 15 min : ça monte, ça descend, ou c'est stable ?
dmesg -T | tail -40 # OOM, erreurs I/O, reset de carte, MCE : les faits durs
vmstat 1 5          # r et b (files), si/so (swap actif), us/sy/wa/st
mpstat -P ALL 1 3   # un coeur saturé ou tous ? %st = problème hyperviseur
pidstat 1 3         # QUI consomme, en CPU et en changements de contexte
iostat -xz 1 3      # await et %util : le disque suit-il ?
free -m             # available (pas free), et le swap
sar -n DEV 1 3      # débit par interface, erreurs, drops
ss -s               # nombre de sockets, time-wait, orphelines
top -b -n1 | head   # vue d'ensemble, RES et %CPU, pour recouper
```

En une phrase par commande, ce qu'on cherche :

* `uptime` : la **tendance**. Charge à 12/6/3 = ça empire, on est au début de
  l'incident. 3/6/12 = le pic est passé.
* `dmesg -T` : les faits que le noyau a constatés. C'est la seule source qui
  ne ment pas et la plus vite oubliée.
* `vmstat 1 5` : la ligne la plus dense de Linux. `r` > nombre de cœurs = file
  d'exécution CPU. `b` non nul = attente d'E/S. `si/so` = thrash.
* `mpstat -P ALL` : distinguer « un cœur à 100 % » (processus mono-thread) de
  « tous à 100 % » (charge globale). Et surveiller `%st`.
* `pidstat 1 3` : passer de « le système consomme » à « ce processus consomme ».
* `iostat -xz 1 3` : `await` élevé = le stockage est le goulot.
* `free -m` : `available` près de zéro = pression mémoire réelle.
* `sar -n DEV` : saturation d'interface ou erreurs de lien.
* `ss -s` : explosion de `TIME_WAIT` ou de sockets orphelines = problème de
  gestion des connexions.
* `top` : recoupement final, et repérage d'un processus en `D` ou en `Z`.

On termine par une phrase de synthèse : « CPU et mémoire éliminés, le disque
`sdb` est à 480 ms de latence d'écriture, le processus `postgres` PID 1841
écrit 300 Mo/s ; hypothèse : une requête d'export non bornée ».

> [!NOTE]
> **Pourquoi**
>
> Ce qui est évalué en entretien, ce n'est pas la liste (elle est publique, c'est
> la checklist de Brendan Gregg), c'est ce que le candidat dit de chaque sortie.
> Réciter dix commandes sans savoir ce qu'on y lit se remarque en trente
> secondes. Et la bonne réponse mentionne toujours `%st` sur une infrastructure
> virtualisée : c'est le détail qui montre qu'on a déjà diagnostiqué une VM.

---

<a id="qo19-4"></a>**[QO19.4](README.md#qo19-4)** — *RSS d'un `java` qui monte de 40 Mo par heure depuis trois jours.*

**Réponse attendue**

**Prouver que c'est une fuite.** Une croissance n'est pas une fuite : un cache
qui se remplit croît aussi, mais il **plafonne**. Trois éléments de preuve :

1. La courbe ne plafonne pas et la croissance est linéaire dans le temps, pas
   corrélée au trafic. On échantillonne :

   ```bash
   PID=$(pgrep -f monapp.jar)
   while :; do
     printf '%s %s %s\n' "$(date +%FT%T)" \
       "$(awk '/VmRSS/{print $2}' /proc/$PID/status)" \
       "$(awk '/MemAvailable/{print $2}' /proc/meminfo)"
     sleep 60
   done >> ~/suivi-rss.csv
   ```

2. La mémoire ne redescend pas après une période creuse (la nuit). Un cache,
   lui, est libéré sous pression ou expire.
3. Pour une JVM, on distingue tas et hors-tas : `jcmd $PID GC.heap_info`,
   `jcmd $PID VM.native_memory summary` (si `NativeMemoryTracking` est activé).
   Si le tas est stable et que le RSS monte, la fuite est hors-tas : threads,
   buffers directs, JNI, métaspace.

**Ce qu'on fournit au développeur** : la série temporelle de RSS, le nombre de
threads (`/proc/PID/status`, `Threads:`), un ou deux vidages de tas espacés de
plusieurs heures (`jcmd $PID GC.heap_dump /var/tmp/h1.hprof`) — c'est la
comparaison des deux qui montre quelle classe accumule —, la liste des
descripteurs ouverts s'ils croissent aussi, et la version exacte du runtime et
de l'application.

**Ce qu'on met en place en attendant**, sans réveiller personne :

```ini
# /etc/systemd/system/monapp.service.d/10-memoire.conf
[Service]
MemoryHigh=3G
MemoryMax=3.5G
Restart=on-failure
RuntimeMaxSec=86400        # redémarrage quotidien assumé et documenté
```

`MemoryHigh` freine le processus (reclaim agressif) avant que `MemoryMax` ne
déclenche l'OOM du cgroup, qui tue **ce** service et lui seul, sans menacer la
base de données ni `sshd`. Le redémarrage préventif est une dette assumée : on
l'écrit dans le ticket, avec la date de suppression prévue.

On ajoute l'alerte qui manquait : RSS > 80 % de `MemoryMax`, et non « mémoire
de la machine > 90 % ».

> [!WARNING]
> **Piège**
>
> L'erreur classique est de poser un `cron` de redémarrage nocturne et de fermer
> le ticket. Le symptôme disparaît, la fuite reste, et six mois plus tard elle
> double de vitesse après un déploiement : le redémarrage nocturne ne suffit
> plus, personne ne se souvient pourquoi il existe, et l'incident revient un
> dimanche. Une mesure d'atténuation se documente et se date.

---

<a id="qo19-5"></a>**[QO19.5](README.md#qo19-5)** — *L'OOM killer : déclenchement, score, `oom_score_adj`, `MemoryMax`.*

**Réponse attendue**

**Quand.** Le noyau ne tue pas quand la mémoire est « pleine » : il tue quand
une allocation ne peut plus être satisfaite après avoir tout tenté — récupérer
du cache, écrire des pages sales, paginer vers le swap, compacter. L'OOM killer
est le dernier recours. C'est pour cela qu'une machine peut être à 99 % de RAM
utilisée pendant des semaines sans incident, puis tomber en trois secondes.

**Le score.** `oom_badness()` évalue chaque tâche, en pages : RSS anonyme +
mémoire de swap + tables de pages. Autrement dit, la mémoire qu'on récupérerait
en la tuant. Puis `oom_score_adj` (de -1000 à +1000) est ajouté sous forme d'un
pourcentage de la mémoire totale : +100 revient à ajouter 10 % de la RAM de la
machine au score, -1000 rend la tâche intuable. Le noyau tue la tâche au score
le plus élevé — donc la plus grosse, presque toujours.

**Ce que fait `MemoryMax=`.** Il ne change pas ce calcul global : il crée une
limite **par cgroup**. Quand le cgroup du service dépasse sa limite, le noyau
déclenche un OOM **local au cgroup** : il tue une tâche de ce service, et
personne d'autre sur la machine n'est menacé. C'est la différence majeure entre
subir l'OOM killer et le domestiquer.

**Pourquoi la victime n'est pas le coupable.** Le score récompense la
consommation absolue, pas la responsabilité. Une base de données qui utilise
légitimement 6 Go de RAM depuis toujours a un score bien plus élevé qu'un script
Python qui vient de fuir 2 Go en dix minutes. Le noyau tue donc la base.

**Sur une machine où PostgreSQL a été tué à la place de l'application** :

```ini
# l'application, cadrée
[Service]
MemoryHigh=1G
MemoryMax=1.2G

# la base, protégée mais pas immortelle
[Service]
OOMScoreAdjust=-800
```

et côté noyau, on évite le surengagement délirant :

```bash
sysctl vm.overcommit_memory   # 0 = heuristique (défaut), 2 = strict
sysctl vm.overcommit_ratio
```

`vm.overcommit_memory=2` avec un ratio calculé fait échouer les `malloc()`
excessifs **à l'allocation** (l'application reçoit une erreur propre) plutôt que
plus tard, au hasard, sur un processus tiers. C'est plus prévisible, mais cela
casse les applications qui réservent de grandes zones sans les utiliser (la JVM,
Redis avec `fork()` pour la persistance) : à réserver aux machines dédiées.

> [!WARNING]
> **Piège**
>
> `OOMScoreAdjust=-1000` sur une base de données est très tentant et parfois
> catastrophique : la tâche devient intuable, donc quand c'est elle qui fuit, le
> noyau va tuer tout le reste jusqu'à `sshd` et la machine devient inaccessible
> sans console. -800 protège fortement tout en gardant une porte de sortie.

---

<a id="qo19-6"></a>**[QO19.6](README.md#qo19-6)** — *« `df` dit 100 %, `du` dit 40 %. »*

**Réponse attendue**

`du` compte les fichiers qui ont un nom ; `df` compte les blocs alloués. Un
fichier supprimé (`unlink`) dont un processus garde un descripteur ouvert a
perdu son nom mais garde ses blocs : le noyau ne les libère qu'au dernier
`close()`, ou à la mort du processus.

```bash
sudo lsof +L1                      # NLINK à 0, avec la taille et le PID
sudo lsof +L1 | awk '{s+=$7} END {print s/1024/1024 " Mo retenus"}'
sudo truncate -s 0 /proc/<pid>/fd/<n>
df -h /var                         # espace rendu immédiatement
```

Puis la cause : presque toujours une rotation de logs mal faite. Le fichier a
été supprimé ou déplacé sans que le service soit prévenu, donc il continue
d'écrire dans un inode fantôme. Correctif durable : `copytruncate` dans
`logrotate`, ou une directive `postrotate` qui envoie le bon signal
(`systemctl reload nginx`, `kill -USR1`).

**Si on avait fait `rm` au lieu de `truncate`** : rien ne se passe. Le fichier
n'a déjà plus de nom, il n'y a rien à supprimer — `rm` ne peut même pas le
désigner. L'espace reste bloqué jusqu'à ce que le processus ferme le
descripteur, c'est-à-dire jusqu'au redémarrage du service. C'est précisément le
piège : on croit avoir agi, `df` n'a pas bougé, et on conclut à tort qu'il faut
redémarrer.

> [!NOTE]
> **Pourquoi**
>
> Le mécanisme sous-jacent est le compteur de liens de l'inode. Un fichier existe
> tant que (nombre de liens durs > 0) **ou** (nombre de descripteurs ouverts > 0).
> `unlink()` décrémente le premier compteur ; `close()` le second. Les blocs ne
> retournent au système de fichiers que lorsque les deux sont à zéro. C'est aussi
> ce mécanisme qui permet la technique du fichier temporaire sûr : créer, ouvrir,
> supprimer, et continuer d'écrire dans un fichier qu'aucun autre processus ne
> peut ouvrir.

---

<a id="qo19-7"></a>**[QO19.7](README.md#qo19-7)** — *`strace`, `perf top`, `/proc` : coût et ordre d'emploi.*

**Réponse attendue**

| Outil | Observe | Rate | Coût |
|---|---|---|---|
| `/proc` | états, compteurs, limites, fd | ce qui se passe entre 2 lectures | nul |
| `perf top` | où le CPU brûle (échantillonnage) | ce qui ne consomme pas de CPU | 1 à 5 % |
| `strace` | chaque appel système, exact | tout ce qui est en espace utilisateur | x10 à x100 |

`strace` utilise `ptrace` : le processus est **arrêté deux fois par appel
système** (entrée et sortie), avec un aller-retour vers le traceur. Sur un
service qui fait 20 000 appels par seconde, la latence explose. C'est un outil
d'atelier, pas de surveillance.

`perf` échantillonne les piles à fréquence fixe (4 000 Hz par défaut, 99 Hz avec `-F 99`) via les
compteurs de performance du processeur : le coût est proportionnel à la
fréquence, pas au travail du processus. C'est l'outil qu'on peut lancer en
production.

L'ordre d'emploi sur un serveur qui sert encore du trafic :

1. `/proc` et les compteurs : gratuit, immédiat, souvent suffisant
   (`/proc/PID/status`, `syscall`, `wchan`, `io`, `stack`).
2. `perf top -p PID` pendant 10 à 30 s si le processus consomme du CPU.
3. `strace`, borné dans le temps et filtré, en dernier :

   ```bash
   sudo timeout 10 strace -f -c -p "$PID"          # compteurs agrégés
   sudo timeout 10 strace -f -T -e trace=network -p "$PID"
   sudo timeout 10 strace -f -T -e trace=openat,stat -p "$PID" 2>&1 \
     | awk '$NF ~ /<[0-9]/' | sort -t'<' -k2 -rn | head
   ```

`timeout 10` n'est pas une coquetterie : c'est ce qui garantit que l'outil se
détache même si ta session SSH meurt. `-c` donne le tableau récapitulatif
(nombre d'appels, temps total, erreurs par appel) : c'est le mode le moins
verbeux et le plus informatif pour commencer.

> [!WARNING]
> **Piège**
>
> Deux dangers réels de `strace` en production. D'abord, si tu perds ta session
> pendant un `strace` sans `timeout`, le processus reste tracé et ralenti.
> Ensuite, `strace` sur un processus qui gère des signaux peut modifier son
> comportement : certains appels rendent `EINTR` là où ils ne le faisaient pas.
> Sur une base de données chargée, attacher `strace` a déjà provoqué des
> basculements de cluster.

---

<a id="qo19-8"></a>**[QO19.8](README.md#qo19-8)** — *5,1 s de réponse, 0,2 % de CPU : où passe le temps ?*

**Réponse attendue**

0,2 % de CPU pour 5 secondes de réponse veut dire une chose : le processus
**attend**. Reste à savoir quoi.

1. **Décomposer la requête côté client** — c'est la mesure la moins chère :

   ```bash
   cat > /tmp/fmt.txt <<'EOF'
   dns:%{time_namelookup} tcp:%{time_connect} tls:%{time_appconnect}
   ttfb:%{time_starttransfer} total:%{time_total}
   EOF
   curl -w '@/tmp/fmt.txt' -o /dev/null -s http://10.10.10.11:8080/produits
   ```

   Si `time_namelookup` vaut 5 s, c'est le DNS et l'enquête est finie. Si tout
   le temps est entre `time_connect` et `time_starttransfer`, le serveur a
   accepté la connexion et met 5 s à produire le premier octet : c'est dans
   l'application ou dans ce qu'elle appelle.

2. **Regarder ce que le processus attend**, gratuitement :

   ```bash
   PID=$(systemctl show vitrine-api -p MainPID --value)
   cat /proc/$PID/status | grep -E 'State|Threads'
   sudo cat /proc/$PID/syscall     # ex. : recvfrom sur le fd 7
   ls -l /proc/$PID/fd/7           # -> socket:[12345]
   ss -tanp | grep 12345           # -> l'adresse du pair !
   ```

   En quatre commandes, sans rien perturber, on a le nom de la dépendance.

3. **Confirmer par les appels système**, dix secondes :

   ```bash
   sudo timeout 10 strace -f -T -p "$PID" 2>&1 | awk '$NF ~ /<[1-9]/'
   ```

   On cherche la ligne dont la durée entre chevrons est de l'ordre de 5 s :
   `connect(...)  <5.004>`, `recvfrom(...) <5.001>`, `poll(...) <5.000>`.

4. **Confirmer sur le réseau**, indépendamment :

   ```bash
   sudo timeout 20 tcpdump -ni any -w /tmp/lent.pcap \
     'port 53 or port 5432 or port 8081'
   tcpdump -r /tmp/lent.pcap -nn -tttt | head -40
   ```

   Deux outils indépendants qui disent la même chose, c'est une preuve. Un
   seul, c'est une hypothèse.

Les trois suspects par ordre de fréquence : une résolution DNS qui attend son
délai d'expiration (durée très régulière : 5 s, 10 s, 20 s — la régularité est
la signature), une base de données ou une API interne lente, un verrou ou un
pool de connexions saturé (le temps est passé à attendre un jeton, sans aucun
trafic réseau : `strace` ne montre alors que des `futex` interminables).

> [!NOTE]
> **Pourquoi**
>
> La chaîne `/proc/PID/syscall` → `fd` → `socket:[inode]` → `ss` est la plus
> élégante du métier : elle transforme « le processus attend » en « le processus
> attend une réponse de 10.10.10.12:5432 » sans aucun outil intrusif et sans
> privilège autre que root en lecture. Elle marche aussi quand `strace` est
> interdit par la politique de sécurité (`kernel.yama.ptrace_scope`).

---

<a id="qo19-9"></a>**[QO19.9](README.md#qo19-9)** — *Conduire un incident majeur à quatre personnes.*

**Réponse attendue**

**Les rôles**, annoncés explicitement dès la deuxième minute :

* **Responsable d'incident** : il décide, il ne tape rien. Il tient la
  chronologie, arbitre, et protège les autres des interruptions. C'est la règle
  la plus violée et la plus importante : quelqu'un qui débogue perd la vue
  d'ensemble en cinq minutes, et quelqu'un qui répond à la direction ne débogue
  pas.
* **Opérateur(s) technique(s)** : une ou deux personnes maximum qui touchent la
  machine. Toute commande qui modifie l'état est annoncée à voix haute ou dans
  le canal **avant** d'être lancée.
* **Communication** : une personne qui parle aux métiers et à la direction, et
  qui ne pose aucune question technique dans le canal de résolution.
* **Scribe** (peut être le responsable) : horodate tout.

**Le canal** : un seul, écrit, horodaté, dédié à cet incident. Tout ce qui se
dit en visio se réécrit dans le canal — sinon le post-mortem n'aura pas de
matière.

**La cadence** : un point toutes les 15 minutes même s'il n'y a rien de neuf.
« Pas d'évolution, prochaine mise à jour à 18 h 15 » est une information
précieuse : elle empêche cinq personnes de venir demander où ça en est.

**L'arbitrage rétablir / comprendre.** Quatre critères :

1. l'impact court : chaque minute coûte-t-elle des commandes, des données, de
   la sécurité ?
2. la réversibilité : un redémarrage est-il réversible, ou détruit-il l'état
   qu'on ne saura pas reconstituer ?
3. la probabilité de récidive : si on rétablit sans comprendre, ça revient dans
   combien de temps — une heure ou six mois ?
4. la qualité des preuves déjà collectées : si tout est capturé, rétablir ne
   coûte plus rien.

La règle pratique : **on collecte les preuves, puis on rétablit, puis on
comprend à froid**. La collecte coûte deux à trois minutes ; comprendre en
direct peut coûter une heure d'indisponibilité.

**Les preuves à collecter avant tout redémarrage** :

```bash
D=/var/tmp/preuves-$(date +%F-%H%M%S); mkdir -p "$D"
uptime                        > "$D/uptime.txt"
ps auxf                       > "$D/ps.txt"
top -b -n1                    > "$D/top.txt"
free -m                       > "$D/memoire.txt"
{ df -h; echo; df -i; }       > "$D/disque.txt"
ss -tanp                      > "$D/sockets.txt"
dmesg -T                      > "$D/dmesg.txt"
systemctl --failed            > "$D/unites.txt"
journalctl --since '-60 min' --no-pager > "$D/journal.txt"
sudo lsof -p "$PID"           > "$D/fd.txt"      # si un processus est visé
sudo cat /proc/$PID/status /proc/$PID/limits > "$D/proc.txt"
tar czf "$D.tar.gz" "$D"
scp "$D.tar.gz" mathieu@10.10.10.10:/srv/preuves/   # hors de la machine !
```

Le `scp` est la partie qu'on oublie : des preuves restées sur une machine qu'on
va réinstaller ne sont pas des preuves.

> [!WARNING]
> **Piège**
>
> Le piège humain le plus fréquent est le « héros » : la personne la plus
> expérimentée prend le clavier, ne parle plus pendant vingt minutes, corrige, et
> personne ne sait ce qu'elle a fait. L'incident est clos, aucune connaissance
> n'est transmise, et deux changements non documentés restent sur la machine.
> Le rôle de responsable d'incident existe précisément pour empêcher cela.

---

<a id="qo19-10"></a>**[QO19.10](README.md#qo19-10)** — *Les cinq pourquoi sur « `/var` plein, 40 minutes d'arrêt ».*

**Réponse attendue**

1. **Pourquoi le site est-il tombé ?** Parce que l'application ne pouvait plus
   écrire : `/var` était plein à 100 %.
2. **Pourquoi `/var` était-il plein ?** Parce que `/var/log/app/debug.log` avait
   atteint 34 Go.
3. **Pourquoi ce fichier a-t-il atteint 34 Go ?** Parce que le niveau de
   journalisation était resté sur `debug` depuis l'investigation du 12 août, et
   que la rotation n'était pas configurée pour ce fichier.
4. **Pourquoi personne ne l'a-t-il vu venir ?** Parce qu'il n'y avait aucune
   alerte sur le taux de remplissage des systèmes de fichiers : on ne
   surveillait que la disponibilité HTTP.
5. **Pourquoi n'y avait-il pas d'alerte ?** Parce que la supervision est
   déployée manuellement à la mise en service et que cette machine, créée en
   urgence en juin, n'est jamais passée par le modèle standard. **Cause
   systémique.**

L'action corrective efficace est au niveau 4 et 5 : une alerte sur le
remplissage à 80 % pour *toutes* les machines, et une mise en service qui ne
peut pas se terminer sans supervision (intégrée au modèle de VM et vérifiée par
un contrôle automatique). On ajoute au niveau 3 une rotation par défaut dans le
modèle applicatif, et une procédure qui remet le niveau de journalisation à
`info` à la fin d'une investigation.

S'arrêter au niveau 1 (« on a purgé les logs, c'est réglé ») garantit la
récidive : la cause — une machine sans supervision et un `debug` oublié —
n'a pas bougé d'un millimètre. Le même incident reviendra sur la même machine,
ou sur la prochaine machine créée en urgence.

> [!NOTE]
> **Pourquoi**
>
> Les cinq pourquoi ne sont pas un rituel : ils servent à sortir du niveau
> technique immédiat pour atteindre le niveau **organisationnel**, seul endroit
> où l'on peut empêcher une classe entière d'incidents. Le signe qu'on est allé
> assez loin : la dernière réponse ne parle plus d'un fichier ni d'une machine,
> mais d'un processus (mise en service, revue, automatisation, alerte).
>
> Deux garde-fous : cinq n'est pas un dogme (parfois trois suffisent, parfois il
> en faut sept), et une même branche peut se diviser — un incident a souvent
> plusieurs causes parallèles, pas une chaîne unique. Si la réponse à un
> « pourquoi » est un nom de personne, c'est qu'on s'est trompé de question.

---

<a id="qo19-11"></a>**[QO19.11](README.md#qo19-11)** — *Profiler un service Python à 100 % de CPU, de la baseline à
la correction.*

**Réponse attendue**

1. **Baseline.** Avant de toucher à quoi que ce soit : la latence du service
   telle que l'utilisateur la voit (`curl -w '%{time_total}'` sur 50 à 200
   requêtes, moyenne/médiane/p95), la consommation (`pidstat -u -r 1` sur le
   PID, `perf stat` si on peut relancer), et, pour un batch, `/usr/bin/time
   -v` sur trois exécutions. Le tout dans un fichier daté dans le dépôt du
   ticket : sans « avant », il n'y aura pas d'« après ».
2. **Qualifier.** `top` : `us` élevé (CPU applicatif) ou `sy`/`wa` (noyau,
   E/S) ? `vmstat 1`, `mpstat -P ALL 1` (un seul cœur = mono-thread).
   Ici : 100 % d'un cœur en `us` → c'est du calcul, donc un **profileur**,
   pas un traceur. `strace` ralentirait le processus ×10 et ne montrerait
   que des appels système rares ; il ne répond pas à « quelle fonction ».
3. **`perf top -p PID`** d'abord (en direct, gratuit, sans fichier) pour
   voir si le temps part dans une bibliothèque C (`libssl`, `libz`, une
   regex) ou dans l'interpréteur. Puis **`perf record -F 99 -g -p PID --
   sleep 20`** pour figer une preuve avec les piles d'appels, et `perf
   report --no-children`.
4. **Si tout est dans `_PyEval_EvalFrameDefault`** : relancer avec
   `python3 -X perf` (3.12+) ou `PYTHONPERFSUPPORT=1` pour voir les
   fonctions Python dans `perf` ; sinon `py-spy top --pid PID`
   (échantillonneur externe, sans relancer) ; en dernier recours
   `cProfile` en relançant, en acceptant son surcoût.
5. **De la fonction à la ligne.** Déplier la pile dans `perf report` pour
   savoir *qui* l'appelle et combien de fois ; lire la fonction ; compter
   les opérations (une boucle dans une boucle = N × M) ; instrumenter
   localement (`time.perf_counter()` autour de la ligne suspecte, ou
   `line_profiler`) si la fonction est longue.
6. **Corriger le minimum** : une structure de données (liste → dict, set),
   un cache, une requête sortie d'une boucle. Une seule modification.
7. **Prouver** : mêmes mesures qu'en 1, même sortie fonctionnelle (hash du
   résultat, tests), facteur de gain écrit, et `perf record` de nouveau
   pour montrer que la fonction a disparu du haut du classement. Le critère
   n'est pas « ça a l'air plus rapide » mais « p95 de 5 100 ms à 40 ms sur
   200 requêtes, sortie identique ».
8. **Refuser** : optimiser sans baseline, plusieurs changements à la fois,
   « réécrire dans un autre langage » avant d'avoir mesuré, toucher à
   `sysctl` ou au nombre de workers en espérant un miracle, et laisser
   `strace` attaché à un processus de production.

> [!NOTE]
> **Pourquoi**
>
> Le profilage est une démarche d'incident comme les autres : symptôme
> mesuré, hypothèse falsifiable (« si c'est cette fonction, la retirer du
> classement doit faire tomber la latence »), un changement, une mesure. La
> règle des 80/20 est presque toujours vraie : une fonction, souvent une
> ligne, porte l'essentiel du coût, et la trouver coûte dix minutes de
> `perf`. Réécrire en Go une recherche linéaire donne une recherche linéaire
> rapide — toujours quadratique, toujours condamnée quand le volume double.

---

## 19.5 Exercices guidés

<a id="e19-1"></a>**[E19.1](README.md#e19-1)** — *Charge CPU sur deux cœurs : prouver que la charge vient du CPU.*

```bash
stress-ng --cpu 2 --timeout 60s &
uptime                      # load average qui monte vers 2
mpstat -P ALL 1 3           # %usr proche de 100, %iowait et %steal à 0
```

> [!NOTE]
> **Pourquoi**
>
> Deux commandes suffisent parce qu'elles répondent à deux questions
> complémentaires : `uptime` dit *combien* de tâches n'avancent pas, `mpstat` dit
> *pourquoi*. Une charge de 2 avec `%usr` à 100 % et `%iowait` à 0 ne laisse
> aucune ambiguïté : les tâches veulent du CPU et le CPU est pris.
>
> La valeur de référence est le nombre de cœurs : `nproc`. Une charge de 2 sur
> 2 vCPU, c'est 100 % ; la même charge sur 32 cœurs, c'est du repos. Toute alerte
> sur la charge doit être normalisée : `charge / nproc`.

---

<a id="e19-2"></a>**[E19.2](README.md#e19-2)** — *Charge d'E/S : la charge monte, `%idle` reste élevé.*

```bash
stress-ng --hdd 2 --hdd-bytes 1G --timeout 60s &
uptime                                   # la charge monte quand même
vmstat 1 5                               # colonne b non nulle, wa élevé
ps -eo state,pid,comm,wchan:25 | awk '$1 ~ /^D/'
```

La colonne `b` de `vmstat` compte les processus en attente ininterruptible, et
`ps` les montre en état `D` avec la fonction noyau où ils bloquent
(`io_schedule`, `wait_on_page_bit`).

> [!NOTE]
> **Pourquoi**
>
> C'est la démonstration expérimentale de Q19.1 : la charge de Linux est une file
> d'attente globale, pas un indicateur de CPU. Sur cette machine, `%idle` peut
> rester au-dessus de 80 % pendant que la charge atteint 4 : personne ne calcule,
> tout le monde attend le disque.
>
> Application immédiate : une alerte « charge > 4 » sans contexte réveille pour
> rien la moitié du temps. L'alerte utile associe la charge à `%iowait` ou aux
> indicateurs PSI (`cat /proc/pressure/io`), qui distinguent nativement les deux
> situations.

---

<a id="e19-3"></a>**[E19.3](README.md#e19-3)** — *Top 10 CPU et top 10 mémoire, avec RSS en Mo et commande complète.*

```bash
ps -eo pid,user,pcpu,rss,args --sort=-pcpu | head -11
ps -eo pid,user,pcpu,rss,args --sort=-rss  | head -11 | \
  awk 'NR==1 {print; next} {$4=int($4/1024)"M"; print}'
```

Plus lisible, avec un formatage propre :

```bash
ps -eo pid,user,pcpu,pmem,rss:8,comm --sort=-rss | head -11
```

> [!WARNING]
> **Piège**
>
> `ps aux | sort -k4 -rn` fonctionne mais trie `%MEM` (arrondi à 0,1 %) et casse
> dès qu'un nom d'utilisateur est long : les colonnes se décalent. `--sort=` de
> `ps` trie sur la vraie valeur numérique, sans découpage. Et `args` doit toujours
> être la **dernière** colonne demandée, sinon les espaces de la ligne de commande
> décalent tout le reste.

---

<a id="e19-4"></a>**[E19.4](README.md#e19-4)** — *Processus à 100 % : trouver où il brûle le temps.*

```bash
PID=$(ps -eo pid,pcpu --sort=-pcpu --no-headers | head -1 | awk '{print $1}')
sudo perf top -p "$PID"                 # q pour quitter
# ou, non interactif :
sudo perf record -F 99 -g -p "$PID" -- sleep 10
sudo perf report --stdio | head -30

for i in 1 2 3 4 5; do
  echo "--- capture $i"; sudo cat /proc/"$PID"/stack; sleep 1
done
```

> [!NOTE]
> **Pourquoi**
>
> Les deux outils répondent à deux questions différentes. `perf top` échantillonne
> les piles **utilisateur et noyau** et donne un classement par fonction : c'est
> ce qui dit « 62 % du temps dans `json_decode` ». Les captures répétées de
> `/proc/PID/stack` ne montrent que la pile **noyau** ; si le processus tourne en
> espace utilisateur, on n'y verra quasiment rien. La méthode reste utile quand le
> processus est bloqué : cinq captures identiques prouvent qu'il est coincé au
> même endroit.
>
> C'est le « poor man's profiler » : échantillonner à la main des piles suffit
> souvent à trouver le point chaud, sans installer `perf` (parfois indisponible
> dans une VM parce que le paquet `linux-tools-$(uname -r)` ne correspond pas au
> noyau).

---

<a id="e19-5"></a>**[E19.5](README.md#e19-5)** — *Tout savoir d'un processus, uniquement depuis `/proc`.*

```bash
PID=$(systemctl show vitrine-api -p MainPID --value)
grep -E '^(State|VmRSS|Threads)' /proc/$PID/status
grep 'Max open files' /proc/$PID/limits
ls -1 /proc/$PID/fd | wc -l
sudo tr '\0' '\n' < /proc/$PID/environ
```

> [!NOTE]
> **Pourquoi**
>
> `/proc/PID/environ` contient l'environnement **au moment du démarrage** du
> processus, séparé par des octets nuls — d'où le `tr`. C'est la seule source
> fiable pour répondre à « le service voit-il vraiment la variable que j'ai mise
> dans son `EnvironmentFile` ? ». Modifier le fichier après coup ne change rien à
> ce qui est là : il faut relancer le service.
>
> `/proc/PID/limits` se lit en trois colonnes : limite souple, limite dure, unité.
> C'est la limite souple qui déclenche `EMFILE`.

---

<a id="e19-6"></a>**[E19.6](README.md#e19-6)** — *Mémoire réellement disponible, avant et après vidage du cache.*

```bash
free -m
awk '/MemAvailable/ {print $2/1024 " Go disponibles"}' /proc/meminfo
sync; echo 3 | sudo tee /proc/sys/vm/drop_caches
free -m
```

Après le vidage, `free` (colonne) bondit et `buff/cache` s'effondre, mais
`available` bouge à peine : le cache était déjà compté comme disponible.

> [!WARNING]
> **Piège**
>
> `drop_caches` est un outil de **laboratoire**. En production, il vide un cache
> qui se reconstruira à coups de lectures disque, et provoque une dégradation
> mesurable pendant plusieurs minutes. Il ne « libère » pas de mémoire utile : il
> transforme de la mémoire utile en mémoire vide. Le seul usage légitime est la
> mesure comparative à froid d'une commande de lecture.

---

<a id="e19-7"></a>**[E19.7](README.md#e19-7)** — *Swappe-t-elle en ce moment ? Qui a swappé ?*

```bash
vmstat 1 5 | awk 'NR>2 {print "si="$7" so="$8}'
```

`si`/`so` non nuls et persistants = pagination active. Puis le classement :

```bash
for p in /proc/[0-9]*; do
  s=$(awk '/VmSwap/ {print $2}' "$p/status" 2>/dev/null)
  [ -n "$s" ] && [ "$s" -gt 0 ] && \
    printf '%8s Ko  %s\n' "$s" "$(tr -d '\0' < "$p/comm")"
done | sort -rn | head
```

> [!NOTE]
> **Pourquoi**
>
> `free` affiche du swap *occupé*, ce qui ne dit rien de la santé de la machine.
> `vmstat` affiche du swap *en mouvement*, ce qui est un symptôme grave : chaque
> page qui revient du swap est une attente disque au milieu d'un calcul. Une
> machine peut vivre des mois avec 2 Go de swap occupés ; elle devient
> inutilisable avec 50 Mo/s de `si`.
>
> `/proc/PID/status` expose `VmSwap` par processus, ce que ne donne aucune
> commande standard : c'est le seul moyen simple de savoir *qui* a été poussé
> dans le swap.

---

<a id="e19-8"></a>**[E19.8](README.md#e19-8)** — *Qualifier un système de fichiers en quatre commandes.*

```bash
df -h  /srv/vitrine/data
df -i  /srv/vitrine/data
du -xh --max-depth=1 /srv/vitrine/data | sort -h | tail -5
sudo lsof +L1 | grep /srv/vitrine/data
```

> [!NOTE]
> **Pourquoi**
>
> Le `-x` de `du` (`--one-file-system`) est indispensable : sans lui, le parcours
> descend dans les points de montage imbriqués (`/sys/fs/cgroup`, les couches
> `overlay` de conteneurs, un NFS monté plus bas) et le total ne veut plus rien
> dire — quand il ne bloque pas une heure sur un montage réseau injoignable.
>
> `df -i` répond à une panne qui ressemble à s'y méprendre à un disque plein :
> message `No space left on device` alors que `df -h` montre de la place. Les
> inodes sont alloués à la création du système de fichiers et ne peuvent pas être
> augmentés ensuite sur ext4 : la seule issue est de supprimer des fichiers ou de
> reformater.

---

<a id="e19-9"></a>**[E19.9](README.md#e19-9)** — *Baseline d'E/S avec `fio` et `iostat`.*

```bash
# terminal 1
sudo fio --name=base --directory=/srv/vitrine/data --size=200M \
  --rw=randwrite --bs=4k --numjobs=2 --runtime=30 --time_based \
  --group_reporting
# terminal 2
iostat -xz 1 | tee ~/lab19/rapports/iostat-charge.txt
```

On relève au repos puis en charge, pour le périphérique concerné :

| Mesure | Au repos | En charge |
|---|---|---|
| `w_await` (ms) | 0,3 | 18,4 |
| `aqu-sz` | 0,00 | 3,2 |
| `%util` | 0 | 98 |

> [!NOTE]
> **Pourquoi**
>
> Une baseline n'a d'intérêt que si elle est prise **avant** l'incident et dans
> les mêmes conditions. Sans elle, « `await` à 18 ms » ne signifie rien : c'est
> excellent pour un disque réseau, médiocre pour un NVMe local. La bonne pratique
> est de stocker ces mesures avec le reste de la documentation de la machine, et
> de les refaire après chaque changement d'infrastructure.

---

<a id="e19-10"></a>**[E19.10](README.md#e19-10)** — *`strace` pendant dix secondes, agrégé puis filtré.*

```bash
PID=$(systemctl show vitrine-api -p MainPID --value)
sudo timeout 10 strace -f -c -p "$PID"
sudo timeout 10 strace -f -T -e trace=network -p "$PID"
```

> [!NOTE]
> **Pourquoi**
>
> `-c` agrège : un tableau final avec le nombre d'appels, le temps total et les
> erreurs par type. C'est le mode qui perturbe le moins la lecture (rien ne
> défile) et qui répond le plus vite à « où passe le temps ? ».
>
> `-f` suit les processus et threads fils : sans lui, on rate tout le travail
> d'un serveur multi-thread. `-T` affiche entre chevrons la durée de chaque
> appel : c'est ce qui permet de repérer visuellement un `connect` à `<5.004>`.
> `-e trace=network` réduit le bruit aux appels réseau ; on dispose aussi de
> `file`, `process`, `signal`, `desc`, `memory`.
>
> Et `timeout 10` protège la production : quoi qu'il arrive à ta session, la trace
> s'arrête.

---

<a id="e19-11"></a>**[E19.11](README.md#e19-11)** — *Bloqué ou occupé ? Trois sources.*

```bash
ps -o pid,state,wchan:25,comm -p "$PID"
grep -E 'ctxt_switches' /proc/$PID/status
sudo cat /proc/$PID/stack
```

* `state` : `R` = exécutable, `S` = attente courte, `D` = attente
  ininterruptible, `T` = arrêté, `Z` = zombie.
* `voluntary_ctxt_switches` qui augmente = le processus attend (il rend la main
  volontairement). `nonvoluntary_ctxt_switches` qui augmente = il est préempté,
  donc il travaille et se bat pour du CPU.
* la pile noyau nomme la fonction où il est coincé.

> [!NOTE]
> **Pourquoi**
>
> Les compteurs de changements de contexte sont le discriminateur le plus rapide
> et le moins connu. Deux relevés à dix secondes d'intervalle suffisent : si le
> compteur volontaire explose, le processus fait des appels bloquants (réseau,
> disque, verrou) ; si c'est le compteur involontaire, il consomme du CPU et
> l'ordonnanceur le préempte. On sait où chercher avant même d'avoir lancé le
> moindre outil intrusif.

---

<a id="e19-12"></a>**[E19.12](README.md#e19-12)** — *Fichiers ouverts, et qui tient un montage.*

```bash
sudo lsof -p "$PID"
sudo lsof +D /srv/vitrine/data        # tout ce qui est ouvert sous ce chemin
sudo fuser -vm /srv/vitrine/data      # qui empêche le démontage
```

> [!WARNING]
> **Piège**
>
> `lsof +D` descend récursivement et peut être très long sur une grosse
> arborescence. Pour la question « pourquoi mon `umount` refuse ? », `fuser -vm`
> est immédiat : il travaille au niveau du **montage**, pas du chemin, et voit
> donc aussi les répertoires courants (`cwd`) et les exécutables mappés, qui sont
> les causes les plus fréquentes de `target is busy` — un shell root resté dans le
> répertoire suffit.

---

<a id="e19-13"></a>**[E19.13](README.md#e19-13)** — *Sockets en écoute, résumé, `TIME_WAIT`, plage de ports.*

```bash
ss -tulpn
ss -s
ss -tan state time-wait | wc -l
sysctl net.ipv4.ip_local_port_range
```

> [!NOTE]
> **Pourquoi**
>
> Le rapprochement de ces deux dernières valeurs est le calcul de capacité de
> Q19.9 : 28 232 ports disponibles par défaut, chacun immobilisé 60 s après
> fermeture, soit environ 470 connexions sortantes par seconde vers une même
> destination. Au-delà, `EADDRNOTAVAIL`.
>
> Le quadruplet compte : la limite s'applique **par destination** (IP + port).
> Deux services distants différents ne se partagent pas la contrainte — ce qui
> explique pourquoi seuls certains appels échouent.

---

<a id="e19-14"></a>**[E19.14](README.md#e19-14)** — *Piles de tous les threads d'un processus figé.*

```bash
sudo gdb -p "$PID" -batch -ex 'thread apply all bt' \
  > ~/lab19/preuves/gdb-$(date +%F-%H%M%S).txt 2>&1
```

> [!WARNING]
> **Piège**
>
> `gdb` **arrête** le processus pendant toute la durée de la commande : sur un
> service qui sert du trafic, c'est une micro-indisponibilité (quelques centaines
> de millisecondes à plusieurs secondes si les symboles sont lourds à charger).
> C'est acceptable sur un processus déjà figé — il ne servait plus rien — et
> discutable sur un processus lent mais vivant. On annonce toujours l'opération
> avant de la lancer, et on garde la sortie : elle sera la seule preuve utilisable
> par les développeurs si on redémarre ensuite.
>
> Si `ptrace` est refusé (`kernel.yama.ptrace_scope=1`), il faut être root ou
> ajuster temporairement le paramètre — ce qui se note dans le journal
> d'incident et se remet en place après.

---

<a id="e19-15"></a>**[E19.15](README.md#e19-15)** — *Baseline de latence sur 200 requêtes.*

```bash
mkdir -p ~/lab19/rapports
for i in $(seq 1 200); do
  curl -s -o /dev/null -w '%{time_total}\n' http://127.0.0.1:8080/produits
done | sort -n > /tmp/lat.txt

{
  echo "baseline /produits, 200 requetes, $(date '+%F %T')"
  awk '{s+=$1} END {printf "moyenne : %.3f s\n", s/NR}' /tmp/lat.txt
  awk 'NR==100 {printf "mediane : %.3f s\n", $1}'       /tmp/lat.txt
  awk 'NR==190 {printf "p95     : %.3f s\n", $1}'       /tmp/lat.txt
  tail -1 /tmp/lat.txt | awk '{printf "maximum : %.3f s\n", $1}'
} | tee ~/lab19/rapports/baseline.txt
```

> [!NOTE]
> **Pourquoi**
>
> Trier les valeurs avant de calculer permet d'obtenir médiane et centiles sans
> outil supplémentaire. Et c'est la médiane et le p95 qui comptent, pas la
> moyenne : une moyenne de 200 ms peut cacher 190 requêtes à 40 ms et 10 à 3 s.
> Les utilisateurs ne vivent pas la moyenne, ils vivent la queue de distribution.

---

<a id="e19-16"></a>**[E19.16](README.md#e19-16)** — *Historique avec `sar`.*

```bash
sar -q -f /var/log/sysstat/sa$(date -d yesterday +%d)      # charge d'hier
sar -d -p -f /var/log/sysstat/sa$(date -d yesterday +%d)   # E/S d'hier
sar -r -s 09:00:00 -e 11:00:00                             # mémoire aujourd'hui
```

> [!IMPORTANT]
> **Variante Rocky / RHEL**
>
> Sous Rocky 9, les fichiers sont dans `/var/log/sa/saJJ` et la collecte est
> assurée par `sysstat-collect.timer` (toutes les 10 minutes).

Si `sar` répond `Cannot open /var/log/sysstat/sa18: No such file or directory`,
la collecte n'a jamais tourné : `ENABLED="true"` dans `/etc/default/sysstat`
puis `systemctl enable --now sysstat`.

> [!NOTE]
> **Pourquoi**
>
> `sar` est le seul outil du socle qui répond à « et avant ? ». Sans historique,
> toute mesure prise pendant un incident est incomparable : on ne saura jamais si
> 150 Mo/s d'écriture est anormal ou quotidien. C'est cinq minutes de
> configuration à la mise en service, et c'est ce qui sépare un diagnostic d'une
> conjecture.

---

<a id="e19-17"></a>**[E19.17](README.md#e19-17)** — *Trois commandes sur le démarrage.*

```bash
systemd-analyze
systemd-analyze blame | head -10
systemd-analyze critical-chain
```

La première donne le total (noyau + initrd + espace utilisateur), la deuxième
les unités les plus longues, la troisième celles qui ont **réellement** retardé
le démarrage — les seules qu'il serve à optimiser.

---

<a id="e19-18"></a>**[E19.18](README.md#e19-18)** — *Capturer le trafic DNS et repérer les requêtes sans réponse.*

```bash
sudo timeout 20 tcpdump -ni any -w /tmp/dns.pcap 'udp port 53'
tcpdump -r /tmp/dns.pcap -nn -tttt | head -40
tcpdump -r /tmp/dns.pcap -nn | awk '{print $NF, $0}' | sort | head
```

Une requête sans réponse se repère à l'œil : une ligne sortante vers le port 53
sans ligne entrante correspondante dans les secondes qui suivent, souvent
suivie d'une **retransmission** de la même requête (même identifiant) après le
délai d'expiration.

> [!NOTE]
> **Pourquoi**
>
> `-w` écrit le fichier brut sans afficher ni résoudre : c'est la forme la moins
> coûteuse et la seule acceptable sur un lien chargé. L'analyse se fait ensuite à
> froid avec `-r`, autant de fois qu'on veut, et le fichier peut être transmis à
> quelqu'un d'autre. `-nn` désactive la résolution des noms et des services :
> indispensable ici, sinon `tcpdump` fait lui-même des requêtes DNS pour afficher
> sa sortie… alors qu'on diagnostique le DNS.

---

<a id="e19-19"></a>**[E19.19](README.md#e19-19)** — *`iotop -oPa` : qui fait des E/S, en cumul.*

```bash
cd /srv/vitrine/data
stress-ng --hdd 1 --hdd-bytes 512M --timeout 90s &
fio --name=lect --rw=randread --bs=4k --size=200M --runtime=90 \
  --time_based --directory=/srv/vitrine/data >/dev/null &
sudo iotop -oPa -b -n 6 -d 1 | tail -8
# Total DISK READ:  18.42 M/s | Total DISK WRITE: 96.10 M/s
# Current DISK READ: 18.40 M/s | Current DISK WRITE: 95.88 M/s
#   PID  PRIO  USER   DISK READ  DISK WRITE  SWAPIN   IO>    COMMAND
#  7412 be/4  mathieu   0.00 B    480.51 M   0.00 %  61.2 %  stress-ng-hdd
#  7420 be/4  mathieu  92.10 M      0.00 B   0.00 %  38.4 %  fio
pidstat -d 1 3 | tail -4
# 12:01:03  UID  PID  kB_rd/s  kB_wr/s  kB_ccwr/s  iodelay  Command
# 12:01:03 1000 7412     0.00  98304.0       0.00       12  stress-ng-hdd
# 12:01:03 1000 7420 18944.00      0.00       0.00        3  fio
```

`stress-ng-hdd` écrit, `fio` lit. `-o` cache les processus sans E/S,
`-P` agrège les threads par processus (sinon `fio` apparaît en plusieurs
lignes), `-a` affiche le **cumul** depuis le lancement d'`iotop` au lieu du
débit instantané ; `-b -n 6 -d 1` = mode batch, six itérations d'une
seconde. `DISK READ`/`DISK WRITE` sont les octets réellement échangés avec
le périphérique (par processus, via le comptage `taskstats` du noyau) ;
`SWAPIN` est le pourcentage de temps passé à attendre du swap-in, et `IO>`
le pourcentage de temps passé à attendre une E/S, quelle qu'elle soit —
c'est la colonne qui désigne le processus **qui souffre**, pas seulement
celui qui produit du trafic.

> [!NOTE]
> **Pourquoi**
>
> `iostat` dit *combien* le disque travaille, `iotop` et `pidstat -d` disent
> *pour qui*. `iotop` exige root (interface `taskstats` du noyau) et le
> paquet `iotop` ; `pidstat -d` (sysstat) lit `/proc/PID/io` sans privilège
> et se scripte mieux (`-p PID`, sortie tabulaire). `kB_ccwr/s` compte les
> écritures annulées (fichier écrit puis tronqué avant le flush) et
> `iodelay` les ticks passés bloqué en E/S : deux colonnes uniques à
> `pidstat`.

---

<a id="e19-20"></a>**[E19.20](README.md#e19-20)** — *`iostat -xz 1` colonne par colonne.*

```bash
df /srv/vitrine/data          # /dev/loop0 → image sur /dev/sda
iostat -xz 1 6 | grep -E '^(Device|sda|loop0)' | tail -6
```

| Colonne | `fio` (lecture 4k aléatoire) | `stress-ng --hdd` (écriture 1 Mo séq.) |
|---|---|---|
| `r/s` / `w/s` | ≈ 4 600 | ≈ 95 |
| `rkB/s` / `wkB/s` | ≈ 18 400 | ≈ 97 000 |
| `rareq-sz` / `wareq-sz` | 4,0 Kio | ≈ 1 024 Kio |
| `r_await` / `w_await` | ≈ 0,8 ms | ≈ 9 ms |
| `aqu-sz` | ≈ 4 (les deux ensemble) | |
| `%util` | ≈ 100 % | |

`fio` fait des **petites lectures aléatoires** (`rareq-sz` 4 Kio, IOPS
élevés, débit faible) ; `stress-ng` des **grosses écritures séquentielles**
(`wareq-sz` ≈ 1 Mio, IOPS faibles, débit fort). La latence d'écriture est la
plus mauvaise : chaque requête de 1 Mio occupe le disque plus longtemps, et
les écritures passent par le cache de pages puis sont vidées par rafales
(`Dirty` dans `/proc/meminfo`), ce qui crée des files d'attente. `%util` à
100 % dit seulement que le disque n'a jamais été inactif pendant la
seconde ; `aqu-sz` ≈ 4 et des `await` de quelques millisecondes disent
qu'il **suit** : chargé, pas saturé (Q19.19). Au repos (E19.9),
`await` < 1 ms et `%util` < 5 %.

> [!NOTE]
> **Pourquoi**
>
> Chaque paire de colonnes répond à une question : `r/s`+`w/s` → combien de
> requêtes (à comparer aux IOPS annoncés du support) ; `rkB/s`+`wkB/s` →
> combien d'octets (à comparer au débit) ; `rareq-sz`/`wareq-sz` → quel
> motif (4 Kio = base de données ou métadonnées, ≥ 512 Kio = flux) ;
> `await` → ce que **subit** l'application ; `aqu-sz` → combien attendent
> derrière. Une base de données se moque du débit et souffre de `r_await` ;
> une sauvegarde se moque de `r_await` et veut du `wkB/s`. Lire les neuf
> colonnes ensemble évite le contresens de l'une prise seule.

---

<a id="e19-21"></a>**[E19.21](README.md#e19-21)** — *`mpstat -P ALL`, `pidstat -u -r`, PSI CPU.*

```bash
stress-ng --cpu 1 --timeout 60s &
mpstat -P ALL 1 3 | tail -4
# Average:  CPU   %usr  %nice  %sys  %iowait  %irq  %soft  %steal  %idle
# Average:  all  50.12   0.00  0.34     0.00  0.00   0.08    0.00  49.46
# Average:    0  99.67   0.00  0.33     0.00  0.00   0.00    0.00   0.00
# Average:    1   0.67   0.00  0.34     0.00  0.00   0.17    0.00  98.82
pidstat -u -r 1 3 | grep -E 'stress|Command' | tail -3
# … UID  PID  %usr %system %guest %wait %CPU CPU  Command
# … 1000 7601 99.00   0.00   0.00  0.00 99.00  0  stress-ng-cpu
# … UID  PID minflt/s majflt/s  VSZ   RSS %MEM  Command
# … 1000 7601   0.00     0.00 74112 6144 0.15  stress-ng-cpu
cat /proc/pressure/cpu       # some avg10=0.30 … : presque rien n'attend
```

La moyenne `all` à 50 % cache un cœur à 100 % et un cœur libre : un
programme **mono-thread** sature son cœur, et « la machine est à 50 % » est
faux pour lui — il ne peut pas aller plus vite. Avec `--cpu 2` :

```bash
stress-ng --cpu 2 --timeout 60s &
mpstat -P ALL 1 3 | tail -3          # les deux vCPU à ~100 %, all ≈ 100 %
sleep 5; cat /proc/pressure/cpu      # some avg10=2.10 … puis monte
```

`some` monte avec deux workers parce que la file d'attente CPU n'est plus
vide : les tâches du système (`sshd`, `mpstat` lui-même, `vitrine-api`)
doivent **attendre** un cœur derrière les deux `stress-ng`. Avec un seul
worker, le second cœur les servait tout de suite : `%idle` bas sur un
cœur n'est pas de la saturation ; du temps d'attente en est.

> [!NOTE]
> **Pourquoi**
>
> Utilisation (`%usr`) et saturation (`some` de PSI, `r` de `vmstat`, `%wait`
> de `pidstat`) sont deux axes de USE : on peut être à 100 % sans que
> personne n'attende (un seul demandeur), ou à 60 % avec une file d'attente
> (rafales). `pidstat -u` ajoute `%wait` par processus — le temps où **ce**
> processus était prêt et n'avait pas de cœur — et `CPU` (sur quel cœur il
> tourne), utile pour vérifier une affinité. `-r` donne `minflt/s` et
> `majflt/s` : des fautes majeures en continu signalent un processus qui
> relit son code ou ses données depuis le disque, souvent parce que la
> mémoire manque.

---

<a id="e19-22"></a>**[E19.22](README.md#e19-22)** — *Pression mémoire seconde par seconde.*

```bash
stress-ng --vm 2 --vm-bytes 75% --vm-keep --timeout 60s &
vmstat 1 15
free -m ; cat /proc/pressure/memory        # en boucle, terminal 2 :
watch -n1 'free -m | head -2; cat /proc/pressure/memory; uptime'
```

Chronologie typique sur `lab-web` (2 Go, 2 Go de swap) :

| Seconde | `available` | `si` / `so` | PSI `some` / `full` |
|---|---|---|---|
| 0 | 1 500 Mo | 0 / 0 | 0 / 0 |
| 2 | 400 Mo | 0 / 0 | 0,5 / 0 |
| 4 | 60 Mo | 0 / 3 200 | 12 / 4 |
| 6-30 | < 50 Mo | 800 / 4 100 | 45 / 25 |
| 60+ | 1 500 Mo | 0 / 0 | `avg10` redescend |

La charge moyenne, elle, part de 0,3, ne dépasse 1 qu'après une dizaine de
secondes, monte jusqu'à 3-4 pendant le thrash et met plusieurs minutes à
redescendre après la fin.

Ordre de réaction : **`available`** d'abord (il chute dès l'allocation) ;
puis **`so`** (le noyau évacue vers le swap quand le cache ne suffit plus) ;
**PSI `some`** monte en même temps que le swap (des tâches attendent) et
**`full`** quand tout le monde attend ; **`b`** de `vmstat` monte (tâches en
`D` bloquées sur le swap) ; et la **charge moyenne**, qui est une moyenne
exponentielle sur une minute, arrive en dernier et redescend en dernier.
`wa` monte avec le swap (c'est de l'E/S disque). `r` reste bas : ce n'est
pas le CPU qui manque.

> [!NOTE]
> **Pourquoi**
>
> La charge moyenne est l'indicateur le plus lent et le plus ambigu ;
> `available` est le plus précoce mais ne dit pas si ça fait mal ; `si`/`so`
> disent que le noyau souffre ; PSI dit combien de temps les **applications**
> perdent — c'est l'indicateur qui correspond à ce que ressent l'utilisateur.
> C'est pourquoi `systemd-oomd` et les orchestrateurs modernes se fondent sur
> PSI et non sur `free`. `--vm-keep` empêche `stress-ng` de libérer et
> réallouer : la pression est constante, ce qui rend la lecture plus simple.

> [!WARNING]
> **Piège**
>
> Sans swap, la séquence est différente : `available` tombe, puis l'OOM
> killer tue un worker `stress-ng` presque tout de suite, sans phase de
> thrash : PSI `full` reste faible, la machine ne rame pas — elle tue. Le
> swap n'est pas « mauvais » : il transforme une mort brutale en
> ralentissement, ce qui est souhaitable pour un poste et discutable pour
> un serveur de production.

---

<a id="e19-23"></a>**[E19.23](README.md#e19-23)** — `/proc/meminfo`*, `free`, `slabtop`, et 100 000 inodes.*

```bash
grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|Shmem|Dirty)' \
  /proc/meminfo
grep -E '^(AnonPages|Slab|SReclaimable|SUnreclaim|SwapTotal|SwapFree)' \
  /proc/meminfo
free -m
```

Réconciliation (`free` en Mio = lignes de `meminfo` ÷ 1024) : `total` =
`MemTotal` ; `free` = `MemFree` ; `shared` = `Shmem` ; `buff/cache` =
`Buffers` + `Cached` + `SReclaimable` ; `available` = `MemAvailable` ;
`used` = `MemTotal` − `MemAvailable`
(procps 4, Ubuntu 24.04; avec procps 3.3 c'était `MemTotal` − `MemFree` − `buff/` cache). L'écart de quelques Mio vient
des instants de lecture différents.

```bash
sudo slabtop -o -s c | head -12
#  Active / Total Objects … 
#   OBJS ACTIVE  USE OBJ SIZE  SLABS OBJ/SLAB CACHE SIZE NAME
#  61200  58116  94%    0.19K   2925       21     11700K dentry
#  38900  35120  90%    1.06K   1300       30     41600K ext4_inode_cache
#  …                                                    kmalloc-1k
#  …                                                    buffer_head
#  …                                                    inode_cache
```

`dentry`, `ext4_inode_cache`, `inode_cache`, `buffer_head` sont des caches
**récupérables** (ils apparaissent dans `SReclaimable` : le noyau les
laisse grossir et les vide sous pression) ; `kmalloc-*` et `task_struct`
sont dans `SUnreclaim` : de la mémoire noyau réellement utilisée.

```bash
df -i /srv/vitrine/data                # ~32 000 inodes : trop petit
mkdir -p /var/tmp/inodes-test && cd /var/tmp/inodes-test
grep -E '^(Slab|SReclaimable)' /proc/meminfo
seq 1 100000 | xargs -P4 -n2000 touch
grep -E '^(Slab|SReclaimable)' /proc/meminfo          # + 60 à 120 Mo
sudo slabtop -o -s c | sed -n 8p                      # ext4_inode_cache en tête
sync ; echo 2 | sudo tee /proc/sys/vm/drop_caches     # 2 = dentries + inodes
grep -E '^(Slab|SReclaimable)' /proc/meminfo          # revenu
cd / && rm -rf /var/tmp/inodes-test
```

> [!NOTE]
> **Pourquoi**
>
> Le cache de pages n'est pas la seule mémoire « cachée » : chaque fichier
> touché laisse une entrée `dentry` (nom → inode) et un `inode` en cache
> slab. Un serveur qui manipule des millions de petits fichiers (cache
> d'application, files de mails, `/var/lib/docker/overlay2`) peut avoir
> plusieurs Go de `Slab`, comptés dans `buff/cache` et récupérables — mais
> qui font croire à une fuite quand on ne lit que `used`. `slabtop -o`
> (une passe) `-s c` (tri par taille de cache) est la commande qui nomme le
> coupable ; `drop_caches` n'est qu'un outil de **démonstration** : en
> production, le noyau récupère tout seul, et vider les caches ne fait que
> ralentir tout le monde.

---

<a id="e19-24"></a>**[E19.24](README.md#e19-24)** — *`perf trace`, `wchan`, `ltrace` sur `vitrine-api`.*

```bash
/opt/vitrine/bin/vitrine-charge.sh /produits 5 60 &
PID=$(systemctl show vitrine-api -p MainPID --value)
sudo timeout -s INT 5 perf trace -s -p "$PID" 2>&1 | head -25
#  vitrine-api (2143), 3120 events, 100.0%
#    syscall     calls  errors  total   min   avg   max   stddev
#                              (msec) (msec) (msec) (msec)   (%)
#    poll          412      0  4602.1  0.002  11.17 205.4   9.8 %
#    recvfrom      618      0    12.4  0.004   0.02   0.9   3.1 %
#    sendto        410      0    18.9  0.010   0.05   1.2   4.4 %
#    accept4       205      0     3.1  …
#    read          380      0     …
for i in 1 2 3 4 5; do cat /proc/$PID/wchan; echo; sleep 1; done
# poll_schedule_timeout  (x4)  /  0 (x1 : il tournait à l'instant)
ps -o pid,stat,wchan:24,args -p "$PID"
sudo timeout -s INT 5 ltrace -c -p "$PID" 2>&1 | head -10
# % time     seconds  usecs/call     calls      function
#  38.12    0.412873         218      1893 memcpy
#  21.40    0.231774         104      2221 strlen
#  12.05    0.130501         640       204 malloc
#   9.87    …                                  free
```

Coût mesuré en parallèle (`for i in $(seq 20); do curl -so /dev/null -w
'%{time_total}\n' http://127.0.0.1:8080/sante; done | sort -n | tail -1`) :
`perf trace` : latence max ≈ inchangée (+ 5 %) ; `strace -f` (E19.10) : ×5 à
×10 ; `ltrace` : ×20 à ×50, et le processus peut rester figé quelques
secondes au détachement.

> [!NOTE]
> **Pourquoi**
>
> Trois outils, trois couches. `perf trace` regarde les **appels système**
> comme `strace`, mais via les points de trace du noyau (`tracepoints`) et un
> tampon partagé : le processus n'est pas arrêté à chaque appel, d'où un coût
> de quelques pour cent — c'est l'outil qu'on attache en production.
> `wchan` (*wait channel*) est gratuit : il donne la fonction noyau où le
> processus dort — `poll_schedule_timeout` = il attend des connexions, c'est
> un serveur qui **n'a rien à faire** ou qui attend un client lent ;
> `io_schedule` = disque ; `nfs_wait_bit` = NFS ; `0` = il tourne. Cinq
> lectures espacées valent un profil grossier. `ltrace` intercepte les appels
> aux **bibliothèques partagées** (PLT) : utile pour voir qu'un programme
> appelle `SSL_read` ou `getaddrinfo` en boucle, mais son coût le réserve
> aux environnements de test et aux processus qu'on peut sacrifier.

> [!WARNING]
> **Piège**
>
> `ltrace -p` sur un binaire lié statiquement (Go, Rust par défaut) ne montre
> rien : il n'y a pas de PLT à intercepter. Et sur un processus Python, il
> montre les appels de `libpython` et de `libc` (`memcpy`, `strlen`), pas les
> fonctions Python : pour ça, c'est `perf` avec `-X perf` (L19.6) ou
> `py-spy`.

---

## 19.6 Labs

### <a id="l19-1"></a>**[L19.1](README.md#l19-1)** — Les 60 premières secondes (INC-3301)

**Le script de triage**

```bash
#!/usr/bin/env bash
# ~/lab19/bin/triage.sh — checklist des 60 secondes, lecture seule.
set -uo pipefail
SORTIE="$HOME/lab19/rapports/triage-$(date +%F-%H%M%S).txt"
mkdir -p "$(dirname "$SORTIE")"

titre() { printf '\n===== %s =====\n' "$1"; }

{
  printf 'triage de %s, %s\n' "$(hostname)" "$(date '+%F %T %Z')"
  printf 'noyau %s, %s vCPU\n' "$(uname -r)" "$(nproc)"

  titre "1. charge (tendance)";        uptime
  titre "2. noyau (40 dernieres)";     dmesg -T 2>/dev/null | tail -40
  titre "3. vmstat 1 5";               vmstat 1 5
  titre "4. cpu par coeur";            mpstat -P ALL 1 3
  titre "5. cpu par processus";        pidstat 1 3
  titre "6. disques";                  iostat -xz 1 3
  titre "7. memoire";                  free -m
  titre "8. reseau";                   sar -n DEV 1 3
  titre "9. sockets";                  ss -s
  titre "10. top";                     top -b -n1 | head -20
  titre "11. unites en echec";         systemctl --failed --no-pager
  titre "12. espace disque";           df -h; echo; df -i
} > "$SORTIE" 2>&1

echo "rapport : $SORTIE"
```

**Lecture des trois pistes**

| Piste | Signature | Ce qu'on lit |
|---|---|---|
| A (`--cpu`) | charge ≈ 2, `%usr` ≈ 100 | `%iowait` et `%steal` à 0 |
| B (`--hdd`) | charge élevée, `%idle` haut | `b` > 0, `wa` haut, `await` haut |
| C (`--vm`) | `available` s'effondre | `si`/`so` actifs, cache écrasé |

Identification du coupable :

```bash
pidstat 1 3 | sort -k8 -rn | head -5      # par CPU
ps -eo pid,rss,args --sort=-rss | head -5 # par mémoire
sudo iotop -oPa                           # par E/S
ps -eo pid,args -p "$PID"                 # ligne de commande complète
```

**Le rapport `triage.md`** contient quatre parties : le symptôme mesurable
(« charge 4,2 sur 2 vCPU, `%iowait` à 78 % depuis 06 h 05 »), la ressource
incriminée, les trois lignes de sortie recopiées telles quelles, et
l'hypothèse suivante (« si un processus écrit massivement, `pidstat -d` doit
montrer plus de 100 Mo/s pour un seul PID »).

> [!NOTE]
> **Pourquoi**
>
> Un script de triage doit être **en lecture seule** : aucun `restart`, aucun
> `kill`. C'est ce qui permet de le lancer sans autorisation, dès la première
> minute, y compris par quelqu'un qui n'a pas le contexte. Dès qu'un outil de
> diagnostic modifie l'état, plus personne n'ose l'exécuter en urgence, et il ne
> sert plus à rien.
>
> Deuxième propriété : il capture **tout**, y compris ce qui est normal. Les trois
> ressources saines sont ce qui rend la quatrième convaincante, et elles évitent
> la deuxième session de diagnostic quand l'hypothèse initiale s'effondre.

> [!WARNING]
> **Piège**
>
> `vmstat 1 5` prend 5 secondes, `mpstat -P ALL 1 3` trois, `iostat -xz 1 3`
> trois, `sar -n DEV 1 3` trois : le total tient sous 30 s. Si tu écris
> `vmstat 1 60`, ton script devient inutilisable en situation réelle. Et la
> **première ligne** de `vmstat` et `iostat` est une moyenne depuis le démarrage
> de la machine : elle ne décrit pas l'instant présent. C'est pour cela qu'on
> demande plusieurs itérations et qu'on lit à partir de la deuxième.

---

### <a id="l19-2"></a>**[L19.2](README.md#l19-2)** — Mémoire : fuite, OOM, et garde-fou (INC-3312)

**2. La mesure répétée**

```bash
#!/usr/bin/env bash
# ~/lab19/bin/suivi-rss.sh
set -uo pipefail
CSV=~/lab19/rapports/rss.csv
PID=$(systemctl show vitrine-api -p MainPID --value)
[ -f "$CSV" ] || echo "horodatage,rss_mo,dispo_mo" > "$CSV"
for _ in $(seq 1 36); do
  PID=$(systemctl show vitrine-api -p MainPID --value)   # il peut changer
  RSS=$(awk '/VmRSS/ {print int($2/1024)}' "/proc/$PID/status" 2>/dev/null)
  DISPO=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
  printf '%s,%s,%s\n' "$(date +%FT%T)" "${RSS:-0}" "$DISPO" >> "$CSV"
  sleep 5
done
```

Extrait attendu :

```text
horodatage,rss_mo,dispo_mo
2026-09-18T14:18:05,48,1602
2026-09-18T14:18:10,108,1541
2026-09-18T14:18:15,168,1481
...
2026-09-18T14:20:35,1788,131
2026-09-18T14:20:40,52,1598      <- le processus a été tué et relancé
```

**3. Fuite ou cache ?**

```bash
grep VmRSS /proc/$PID/status      # monte de 60 Mo toutes les 5 s, linéaire
free -m                           # buff/cache s'effondre au lieu de monter
```

Un cache qui se remplit **plafonne** et laisse `available` stable, parce qu'il
est récupérable. Ici `VmRSS` (mémoire anonyme du processus) croît linéairement
et `available` diminue d'autant : la mémoire n'est pas récupérable, c'est une
fuite. La ligne qui fait foi est `VmRSS` de `/proc/<pid>/status` — la même
information que `RES` dans `top`, mais lisible par un script.

**4. La trace OOM**

```bash
dmesg -T | grep -iA 25 'invoked oom-killer' | tail -40
journalctl -k --since '-15 min' | grep -i 'out of memory'
```

```text
[Fri Sep 18 14:20:41 2026] vitrine-api invoked oom-killer:
  gfp_mask=0x140cca(GFP_HIGHUSER_MOVABLE|__GFP_COMP), order=0,
  oom_score_adj=0
[Fri Sep 18 14:20:41 2026] Tasks state (memory values in pages):
[Fri Sep 18 14:20:41 2026] [ pid ] uid tgid total_vm rss ... name
[Fri Sep 18 14:20:41 2026] [ 2244] 997 2244  471235 452118 ... vitrine-api
[Fri Sep 18 14:20:41 2026] Out of memory: Killed process 2244 (vitrine-api)
  total-vm:1884940kB, anon-rss:1808472kB, file-rss:0kB, shmem-rss:0kB,
  UID:997 pgtables:3632kB oom_score_adj:0
```

Lecture ligne à ligne : le **déclencheur** est `vitrine-api` (c'est lui qui
demandait de la mémoire) ; le tableau `Tasks state` liste tous les candidats
avec leur RSS en **pages** (4 Ko) ; la **victime** est le PID 2244 ; `anon-rss`
(1,8 Go) est la mémoire anonyme réellement récupérée par le noyau en le tuant ;
`oom_score_adj:0` indique qu'aucun ajustement n'avait été posé.

**5. Le garde-fou**

```bash
sudo systemctl edit vitrine-api
```

```ini
[Service]
MemoryHigh=200M
MemoryMax=256M
Restart=on-failure
RestartSec=5s
```

```bash
sudo systemctl daemon-reload
sudo systemctl restart vitrine-api
systemctl show vitrine-api -p MemoryMax -p MemoryHigh
cat /sys/fs/cgroup"$(systemctl show vitrine-api -p ControlGroup \
  --value)"/memory.max        # 268435456
journalctl -k | grep -i 'memory cgroup out of memory'
```

> [!NOTE]
> **Pourquoi**
>
> `MemoryHigh` et `MemoryMax` ne jouent pas le même rôle. `MemoryHigh` est un
> **frein** : au-delà, le noyau met le cgroup sous pression de récupération et
> ralentit ses allocations, sans tuer personne. `MemoryMax` est un **mur** :
> au-delà, l'OOM killer du cgroup tue une tâche du service — et uniquement de ce
> service. C'est toute la différence avec l'OOM global : la base de données et
> `sshd` ne sont plus menacés par la fuite d'une application.
>
> L'événement apparaît dans le journal du noyau sous la forme `Memory cgroup out of
> memory: Killed process ...` (et systemd note dans celui de l'unité `A process of this unit has been killed by the OOM killer`), ce qui est aussi un point de détection idéal pour
> une alerte.

> [!WARNING]
> **Piège**
>
> Poser `MemoryMax` trop bas transforme une fuite lente en indisponibilité
> immédiate : mesure d'abord la consommation normale (ici environ 45 Mo au
> démarrage), puis fixe la limite à deux ou trois fois cette valeur. Et une
> limite mémoire n'est pas un correctif : c'est une **atténuation** qui se
> documente, se date, et se retire quand le développeur a corrigé la fuite.

---

### <a id="l19-3"></a>**[L19.3](README.md#l19-3)** — Disque : plein, lent, ou en erreur (INC-3327)

**1. Le script de qualification**

```bash
#!/usr/bin/env bash
# ~/lab19/bin/verif-disque.sh <point_de_montage>
set -uo pipefail
PM="${1:?usage: verif-disque.sh <point_de_montage>}"
RC=0
alerte() { echo "  ANOMALIE : $1"; RC=2; }
avert()  { echo "  AVERTISSEMENT : $1"; [ "$RC" -lt 1 ] && RC=1; }

mountpoint -q "$PM" || { echo "$PM n'est pas un point de montage"; exit 2; }
DEV=$(findmnt -n -o SOURCE --target "$PM")
OPT=$(findmnt -n -o OPTIONS --target "$PM")
echo "== $PM ($DEV)"

USE=$(df  --output=pcent  "$PM" | tail -1 | tr -dc '0-9')
IUSE=$(df -i --output=ipcent "$PM" | tail -1 | tr -dc '0-9')
echo "  occupation : ${USE}%   inodes : ${IUSE}%"
[ "$USE"  -ge 95 ] && alerte "espace disque a ${USE}%"
[ "$USE"  -ge 85 ] && [ "$USE" -lt 95 ] && avert "espace a ${USE}%"
[ "$IUSE" -ge 95 ] && alerte "inodes a ${IUSE}%"

echo "  montage : $OPT"
case ",$OPT," in *,ro,*) alerte "monte en LECTURE SEULE" ;; esac

if command -v lsof >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
  RET=$(lsof +L1 2>/dev/null | awk -v p="$PM" '$0 ~ p {s+=$7} END \
    {printf "%d", s/1048576}')
  echo "  fichiers supprimes encore ouverts : ${RET} Mo retenus"
  [ "${RET:-0}" -ge 100 ] && alerte "${RET} Mo retenus par des fichiers \
supprimes (lsof +L1)"
else
  echo "  fichiers supprimes : controle impossible (root + lsof requis)"
fi

ERR=$(dmesg -T 2>/dev/null | grep -icE "I/O error.*$(basename "$DEV")|\
EXT4-fs error.*$(basename "$DEV")")
echo "  erreurs d'E/S recentes dans dmesg : $ERR"
[ "$ERR" -gt 0 ] && alerte "$ERR erreur(s) d'E/S dans le journal du noyau"

exit "$RC"
```

**2. Le fichier supprimé encore ouvert**

```bash
sudo lsof +L1 | grep /srv/vitrine/data
# sleep 8312 root 9w REG 7,3 419430400 0 13 .../gros.tmp (deleted)
sudo truncate -s 0 /proc/8312/fd/9
df -h /srv/vitrine/data          # l'espace revient immédiatement
```

Le processus continue de tourner : on n'a tué personne, on a simplement vidé
l'inode qu'il tenait ouvert.

**3. Épuisement des inodes**

```bash
sudo dd if=/dev/zero of=/var/tmp/inodes.img bs=1M count=32
sudo mkfs.ext4 -q -N 256 /var/tmp/inodes.img       # 256 inodes seulement
sudo mkdir -p /mnt/inodes && sudo mount -o loop /var/tmp/inodes.img /mnt/inodes
sudo sh -c 'i=0; while :; do : > /mnt/inodes/f$i || break; i=$((i+1)); done'
# sh: 1: cannot create /mnt/inodes/f244: No space left on device
df -h /mnt/inodes    # 1% utilisé
df -i /mnt/inodes    # 100% d'inodes utilisés
```

Même message d'erreur, cause opposée. La seule commande qui tranche est
`df -i`.

**4. La lenteur**

```bash
sudo fio --name=lent --directory=/srv/vitrine/data --size=200M \
  --rw=randwrite --bs=4k --numjobs=4 --runtime=30 --time_based \
  --group_reporting
iostat -xz 1        # dans un autre terminal
```

Formulation exploitable par un non-technicien : « le volume de données traite
au mieux 120 écritures par seconde ; l'export nocturne en demande 900. Il ne
peut pas tenir dans la fenêtre, quelle que soit l'application. »

> [!NOTE]
> **Pourquoi**
>
> Les trois tickets se ressemblent (« ça ne marche plus ») et se traitent avec
> trois commandes différentes. C'est exactement ce qu'un script de qualification
> apporte : il pose les trois questions **dans le même ordre, à chaque fois**, y
> compris à 4 h du matin. Le code retour à trois niveaux permet ensuite de
> l'appeler depuis la supervision sans le réécrire.

> [!WARNING]
> **Piège**
>
> `lsof +L1` sans droits root ne voit que tes propres processus, et rend donc
> « tout va bien » sur une machine dont `/var` est retenu par `nginx`. Un script
> de diagnostic doit **dire** quand il n'a pas pu vérifier, au lieu de conclure au
> vert. Un contrôle silencieusement inapplicable est pire qu'un contrôle absent :
> il rassure à tort.

---

### <a id="l19-4"></a>**[L19.4](README.md#l19-4)** — Une application lente : trouver où part le temps (INC-3340)

**1 et 2. Mesurer et décomposer**

```bash
cat > /tmp/fmt.txt <<'EOF'
dns=%{time_namelookup} tcp=%{time_connect} ttfb=%{time_starttransfer}
total=%{time_total}\n
EOF
curl -w '@/tmp/fmt.txt' -o /dev/null -s http://10.10.10.11:8080/produits
# dns=0.000019 tcp=0.000312 ttfb=5.012440
# total=5.012502
curl -w '@/tmp/fmt.txt' -o /dev/null -s http://10.10.10.11:8080/sante
# dns=0.000018 tcp=0.000287 ttfb=0.001204
# total=0.001255
```

Enseignement immédiat : le temps n'est **pas** dans la résolution du client ni
dans la connexion TCP au serveur, mais entre la connexion et le premier octet —
donc dans le traitement serveur. Et `/sante`, qui ne fait aucun appel externe,
est instantané : le serveur lui-même va bien, c'est ce qu'il appelle qui traîne.

**3. Les appels système**

```bash
PID=$(systemctl show vitrine-api -p MainPID --value)
sudo timeout 10 strace -f -T -p "$PID" 2>&1 | grep -B2 '<[1-9]'
```

```text
[pid 2244] socket(AF_INET, SOCK_DGRAM, IPPROTO_IP) = 8 <0.000021>
[pid 2244] sendto(8, "\0\27\1\0\0\1..."  , 42, 0, {AF_INET,
           sin_port=htons(53), sin_addr=inet_addr("127.0.0.77")}, 16)
           = 42 <0.000035>
[pid 2244] poll([{fd=8, events=POLLIN}], 1, 5000) = 0 (Timeout) <5.004812>
```

La ligne est sans appel : un `poll` de 5 000 ms qui expire sur une socket UDP
vers le port 53. C'est une requête DNS qui n'a jamais reçu de réponse.

**4. Le réseau, en confirmation indépendante**

```bash
sudo timeout 20 tcpdump -ni any -w /tmp/dns.pcap 'udp port 53'
curl -s -o /dev/null http://127.0.0.1:8080/produits
tcpdump -r /tmp/dns.pcap -nn -tttt
# 14:31:02.114 IP 127.0.0.1.41288 > 127.0.0.77.53: 5891+ A? api-interne...
# (aucune réponse, puis la requête suivante 5 s plus tard)
```

**5. La configuration de résolution**

```bash
cat /etc/resolv.conf
# nameserver 127.0.0.77
# nameserver 10.10.10.1
# options timeout:5 attempts:1
grep api-interne /etc/hosts        # ligne commentée
```

**6 et 7. Correctif et vérification**

```bash
sudo sed -i '/^nameserver 127.0.0.77/d' /etc/resolv.conf
sudo sed -i 's/^#\(.*api-interne\)/\1/' /etc/hosts
getent hosts api-interne.lab.local
curl -w '@/tmp/fmt.txt' -o /dev/null -s http://10.10.10.11:8080/produits
# dns=0.000019 tcp=0.000301 ttfb=0.002110
# total=0.002174
```

Mesure de fond, à écrire dans `latence.md` : au moins deux serveurs de noms
fonctionnels, `options timeout:1 attempts:2` pour que l'échec coûte 2 s et non
10, un cache local **qui répond** (`systemd-resolved`, `dnsmasq`), et une
supervision de la résolution elle-même (`getent hosts` chronométré), pas
seulement de la disponibilité HTTP.

> [!NOTE]
> **Pourquoi**
>
> La régularité du délai est la signature d'un **délai d'expiration**, jamais
> d'une saturation. Une ressource saturée donne des temps dispersés (2,3 s ;
> 6,8 s ; 1,1 s) ; un timeout donne 5,004 s, 5,002 s, 5,006 s. Dès qu'on voit
> une distribution aussi serrée, on cherche une valeur de configuration — 5 s
> (résolveur), 30 s (connexion HTTP par défaut de beaucoup de bibliothèques),
> 120 s (TCP `connect` par défaut).

> [!WARNING]
> **Piège**
>
> Corriger uniquement `/etc/hosts` fait disparaître le symptôme sur *cette*
> application et laisse la machine avec un résolveur muet en première position :
> la prochaine application qui résoudra un autre nom subira les mêmes 5 secondes.
> Corriger uniquement `resolv.conf` est plus juste, mais les deux ensemble sont
> nécessaires ici. Règle générale : traiter la cause au niveau où elle est
> partagée, pas au niveau où elle a été vue.

---

### <a id="l19-5"></a>**[L19.5](README.md#l19-5)** — Conduire l'incident, pas seulement le réparer (INC-3355)

**3. Le script de collecte de preuves**

```bash
#!/usr/bin/env bash
# ~/lab19/bin/preuves.sh [destination] — capture avant réparation.
set -uo pipefail
# Par défaut ~/lab19/preuves (de l'utilisateur, même lancé par sudo),
# hors de /var/log et du volume de données ; si le disque de l'incident
# est plein, on tente /dev/shm (en RAM).
H=$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)
BASE="${1:-$H/lab19/preuves}"
if ! df --output=avail "$BASE" 2>/dev/null | tail -1 | \
     awk '{exit !($1 > 51200)}'; then
  echo "moins de 50 Mo libres sur $BASE, bascule sur /dev/shm" >&2
  BASE=/dev/shm
fi
D="$BASE/$(hostname -s)-$(date +%F-%H%M%S)"
mkdir -p "$D" || exit 1

c() { printf '\n### %s\n' "$*" >> "$D/$FIC"; "$@" >> "$D/$FIC" 2>&1; }

FIC=systeme.txt ; c uptime; c free -m; c vmstat 1 3
FIC=processus.txt; c ps auxf; c top -b -n1
FIC=reseau.txt   ; c ss -tanp; c ss -s; c ip -s link
FIC=disque.txt   ; c df -h; c df -i; c findmnt
FIC=noyau.txt    ; c dmesg -T
FIC=unites.txt   ; c systemctl --failed; c systemctl list-units --state=failed
journalctl --since '-30 min' --no-pager > "$D/journal.txt" 2>&1
[ "$(id -u)" -eq 0 ] && lsof -n > "$D/lsof.txt" 2>&1

tar czf "$D.tar.gz" -C "$(dirname "$D")" "$(basename "$D")"
echo "preuves : $D.tar.gz"
echo "pense a le sortir de la machine :"
echo "  scp $D.tar.gz mathieu@10.10.10.10:/srv/preuves/"
```

**4. Les trois messages**

```text
T+0  (17h42) Le site marchand est inaccessible depuis 17h38. Nous avons
     identifié le problème et travaillons dessus. Prochain point à 17h57.
     Aucune action n'est requise de votre côté.

T+15 (17h57) Le site est toujours indisponible. L'origine est un
     dysfonctionnement d'un composant serveur, identifié ; la remise en
     service est en cours. Les commandes passées avant 17h38 ne sont pas
     affectées. Prochain point à 18h12.

T+30 (18h12) Le site est rétabli depuis 18h09. Nous surveillons la
     stabilité pendant une heure. Une analyse détaillée sera publiée sous
     48 h. Les commandes en cours au moment de l'incident sont à
     re-saisir : 14 clients concernés, contactés par le support.
```

**5. L'arbitrage écrit**

```text
17h58 — Décision : je rétablis maintenant.
  Critères : (1) impact commercial direct, 20 min écoulées ;
  (2) preuves déjà collectées (archive preuves-17h44.tar.gz, sortie hors
      machine) ; (3) hypothèse plausible mais non prouvée ;
  (4) le redémarrage est réversible, il ne détruit pas de données.
  Ce que je fais pour ne pas perdre les preuves : copie de /var/log/vitrine
  et de la sortie de `ps`, `ss`, `lsof` avant l'action.
```

**7. Le post-mortem** : rempli à partir du modèle, sans aucun nom de personne,
avec cinq pourquoi qui descendent jusqu'à une cause systémique et trois actions
datées dont une de **prévention** et une de **détection**.

> [!NOTE]
> **Pourquoi**
>
> Le point 3 est le seul du lab qui soit vraiment technique, et c'est le plus
> souvent bâclé. Trois détails le distinguent d'un script naïf : il écrit dans `~`
> `/lab19/preuves` (hors de `/var/log` et du volume de données, qui sont peut-être justement pleins),
> il bascule sur `/dev/shm` si l'espace manque — écrire des preuves en RAM est
> acceptable le temps de les copier ailleurs —, et il **rappelle de sortir
> l'archive de la machine**. Des preuves restées sur la machine qu'on va
> réinstaller n'existent pas.
>
> Sur le fond : ce qui transforme un incident en apprentissage, c'est la trace
> écrite pendant, pas la mémoire d'après. Personne ne se souvient à 20 h de
> l'ordre exact des actions de 17 h 45.

> [!WARNING]
> **Piège**
>
> La tentation permanente est de ne pas écrire pendant qu'on répare, « parce
> qu'on n'a pas le temps ». Le journal coûte dix secondes par action et fait
> gagner une heure de post-mortem. Il évite surtout les deux accidents les plus
> fréquents : oublier de retirer une modification temporaire (une règle de
> pare-feu ouverte, un service désactivé), et réappliquer un correctif déjà testé
> sans effet.

---

### <a id="l19-6"></a>**[L19.6](README.md#l19-6)** — Profiler avant d'optimiser (INC-3362)

**1. Baseline**

```bash
cd ~/lab19/perf
for i in 1 2 3; do /usr/bin/time -v python3 rapport-tva.py >/dev/null; done \
  2>&1 | grep -E 'Elapsed|User time|Maximum resident' \
  | tee ~/lab19/rapports/perf-avant.txt
# Elapsed (wall clock) time (h:mm:ss or m:ss): 0:06.42
# User time (seconds): 6.31
# Maximum resident set size (kbytes): 38912
python3 rapport-tva.py | md5sum | tee -a ~/lab19/rapports/perf-avant.txt
# 5442db6eef2755d458ef9a4d9f43fb74  -      (= /opt/vitrine/perf/sortie.md5)
```

Sur `lab-web` (2 vCPU), 5 à 8 s. Le hash de la sortie est le **contrat** :
toute optimisation qui le change est fausse.

**2. Qualifier**

```bash
python3 rapport-tva.py >/dev/null & pidstat -u 1 3 -p $!
# %usr 99.0  %system 0.3        ← CPU, en espace utilisateur
vmstat 1 3                       # r=1, b=0, wa=0 : rien d'autre ne bloque
sudo perf stat -e task-clock,context-switches,page-faults \
  python3 rapport-tva.py >/dev/null
#  6 380,12 msec task-clock      #  0,998 CPUs utilized
#         42     context-switches
#      9 812     page-faults
```

Un seul cœur, 99,8 % du temps à calculer, presque pas de changements de
contexte, pas d'E/S (les deux CSV font 1,3 Mo et sont lus en quelques ms) :
**programme limité par le CPU, mono-thread**. Ni disque, ni mémoire, ni
réseau : un profileur, pas un traceur.

**3. Profiler**

```bash
sudo perf record -F 99 -g -o perf-avant.data -- python3 rapport-tva.py \
  >/dev/null
sudo perf report -i perf-avant.data --stdio --no-children 2>/dev/null | head -20
#  62.4%  python3  python3.12  [.] _PyEval_EvalFrameDefault
#  11.8%  python3  python3.12  [.] PyDict_GetItem…
#   8.1%  python3  python3.12  [.] unicode_compare_eq
#   …
```

Tout est dans l'interpréteur : on sait que c'est du Python, pas quelle
fonction. Avec la carte de symboles de 3.12 :

```bash
sudo perf record -F 99 -g -o perf-avant.data -- python3 -X perf \
  rapport-tva.py >/dev/null
sudo perf report -i perf-avant.data --stdio --no-children 2>/dev/null \
  | grep -m5 'py::'
#  88.7%  python3  perf-8123.map  [.] py::chercher_client:/home/…/rapport-tva.py
#   6.2%  python3  perf-8123.map  [.] py::calculer:/home/…/rapport-tva.py
#   1.1%  python3  perf-8123.map  [.] py::charger_factures:…
sudo perf report -i perf-avant.data --stdio --no-children -g caller \
  2>/dev/null | grep -A6 'chercher_client' | head -8
#   … py::chercher_client
#        |--py::calculer          ← l'appelant, 40 000 fois
#           py::main
python3 -m cProfile -s tottime rapport-tva.py 2>/dev/null | head -12
#    ncalls  tottime  percall  cumtime  percall filename:lineno(function)
#     40000    8.911    0.000    8.911    0.000 rapport-tva.py:22(chercher_cli…)
#         1    0.180    0.180    9.184    9.184 rapport-tva.py:34(calculer)
#     46002    0.091    0.000    0.160    0.000 csv.py:107(__next__)
```

`chercher_client` : ≈ 90 % du temps, appelée 40 000 fois depuis `calculer`.
Les deux outils sont d'accord ; `cProfile` a coûté 40 % de temps en plus,
`perf` moins de 5 %.

**4. Comprendre**

```python
def chercher_client(clients, ident):
    for client in clients:          # parcourt la LISTE des 6 000 clients
        if client["id"] == ident:   # … jusqu'à trouver : 3 000 en moyenne
            return client
```

Pour N factures et M clients : N × M / 2 comparaisons de chaînes, soit
40 000 × 3 000 = 120 millions. C'est une complexité **O(N × M)** : doubler
les factures double le temps, doubler les clients aussi, doubler les deux
le quadruple. Le problème n'est pas Python — un `for` sur une liste est
linéaire en C aussi ; c'est la **structure de données** : une liste
parcourue là où il faut un index.

**5. Corriger** (diff minimal)

```diff
 def main():
     …
     clients = charger_clients(cli)
+    index = {c["id"]: c for c in clients}     # construit UNE fois : O(M)
     factures = charger_factures(fact)
-    totaux = calculer(clients, factures)
+    totaux = calculer(index, factures)

-def calculer(clients, factures):
+def calculer(index, factures):
     totaux = {}
     for facture in factures:
-        client = chercher_client(clients, facture["client"])
+        client = index[facture["client"]]      # O(1)
```

`chercher_client` peut rester (inutilisée) ou être supprimée ; la sortie
ne change pas.

**6. Prouver**

```bash
python3 rapport-tva.py | md5sum          # 5442db6e… identique
for i in 1 2 3; do /usr/bin/time -v python3 rapport-tva.py >/dev/null; done \
  2>&1 | grep -E 'Elapsed|User time|Maximum resident' \
  | tee ~/lab19/rapports/perf-apres.txt
# Elapsed (wall clock) time (h:mm:ss or m:ss): 0:00.24
# User time (seconds): 0.21
# Maximum resident set size (kbytes): 40120
sudo perf record -F 99 -g -o perf-apres.data -- python3 -X perf \
  rapport-tva.py >/dev/null
sudo perf report -i perf-apres.data --stdio --no-children 2>/dev/null \
  | grep -m3 'py::'
#  31.0%  … py::charger_factures     ← désormais dans la lecture CSV
#  22.4%  … py::calculer
#   9.8%  … py::charger_clients
# facteur : 6,42 / 0,24 ≈ 27
{ cat factures.csv; tail -n +2 factures.csv; } > factures-x2.csv
/usr/bin/time -f '%e s' python3 rapport-tva.py factures-x2.csv clients.csv \
  >/dev/null                                            # 0.46 s : linéaire
```

Gain ×25 à ×30 ; +1 Mo de RSS pour l'index (6 000 entrées). Le profil après
correction est **plat** : le temps se répartit entre lecture CSV, calcul
et tri, aucune fonction ne domine — c'est le signe qu'on a fini. Sur le jeu
doublé, 0,46 s contre 0,24 : linéaire. L'ancien code doublait aussi (O(N × M) est linéaire en N à M fixe) : c'est en doublant **aussi** les clients qu'il aurait quadruplé, alors que le nouveau ne ferait que doubler.

**7. Décider** (`profilage.md`, points attendus) : baseline 6,4 s / hash ;
CPU mono-thread (`pidstat`, `perf stat`) ; `perf record -g` +
`-X perf` → `chercher_client` 89 %, appelée par `calculer` ; cause :
recherche linéaire O(N × M) ; correctif : un dictionnaire, 3 lignes ; gain
×27, sortie identique, linéaire au doublement. Réponse au développeur :
réécrire en Go une recherche linéaire aurait donné un programme peut-être
20× plus rapide **et toujours quadratique** — avec le volume doublé et les
clients doublés, il aurait fallu recommencer. Une réécriture se justifie
quand le profil est plat et que le temps restant est encore inacceptable :
ce sera à mesurer à ce moment-là, avec la même méthode.

> [!NOTE]
> **Pourquoi**
>
> Le lab tient en une règle : **le profil désigne, la mesure décide**. Sans
> `perf`, on aurait pu soupçonner la lecture CSV, le `float()`, le tri, le
> `print` — et optimiser pendant des heures des fonctions qui pèsent 2 %.
> Avec, une commande donne la cible, une lecture donne la cause, trois lignes
> donnent ×27. La preuve (même hash, `time` avant/après, profil plat) est ce
> qui permet de dire non à une réécriture : pas par principe, mais parce que
> le chiffre est là. Et `-X perf` est l'un des vrais progrès récents de
> CPython pour l'exploitation : le même outil sert au noyau, au C et au
> Python, sans agent ni relance instrumentée.

> [!WARNING]
> **Piège**
>
> Trois pièges pratiques. `perf record` sans `-g` donne la fonction mais
> pas l'appelant : on voit `chercher_client`, pas qu'elle est appelée 40 000
> fois par `calculer` — et c'est l'appelant qu'on corrige. `perf report`
> sans `--no-children` classe par temps **cumulé** : `main` et `calculer` à
> 99 % en tête, ce qui ne désigne rien ; le temps propre (`Self`) désigne.
> Enfin, mesurer une seule exécution : la première paie le cache de fichiers
> et la compilation du bytecode (`__pycache__`) ; on en prend trois et on
> garde la meilleure ou la médiane, jamais la première.

---

## 19.7 Break & Fix

Chaque corrigé suit le même plan : la démarche, commande par commande, avec ce
qu'on lit dans la sortie ; la cause racine ; le correctif ; la prévention.

---

### <a id="bf19-1"></a>**[BF19.1](README.md#bf19-1)** — *L'application meurt toutes les nuits (cycles de deux minutes).*

**Démarche**

```bash
systemctl status vitrine-api
# Active: active (running) since Fri 2026-09-18 14:20:41 CEST; 37s ago
```

Premier fait : « since 37 s » alors que le service tourne depuis ce matin. Le
service **redémarre**. On le confirme et on le chiffre :

```bash
systemctl show vitrine-api -p NRestarts
# NRestarts=14
journalctl -u vitrine-api -n 30 --no-pager
# vitrine-api.service: Main process exited, code=killed, status=9/KILL
# vitrine-api.service: Failed with result 'signal'.
# vitrine-api.service: Scheduled restart job, restart counter is at 14.
```

`status=9/KILL` est un `SIGKILL`. Personne ne tape `kill -9` toutes les deux
minutes : le suspect est le noyau.

```bash
dmesg -T | grep -i -B2 -A20 'oom-killer' | tail -40
# vitrine-api invoked oom-killer: gfp_mask=0x140cca, order=0, oom_score_adj=0
# Out of memory: Killed process 2244 (vitrine-api) total-vm:1884940kB,
#   anon-rss:1808472kB, file-rss:0kB, shmem-rss:0kB, UID:997 oom_score_adj:0
```

Confirmation. On mesure maintenant la croissance, chiffre à l'appui :

```bash
PID=$(systemctl show vitrine-api -p MainPID --value)
for _ in $(seq 1 6); do
  awk -v d="$(date +%T)" '/VmRSS/ {print d, int($2/1024) " Mo"}' \
    /proc/$PID/status; sleep 5
done
# 14:22:03 48 Mo
# 14:22:08 108 Mo
# 14:22:13 168 Mo   -> +12 Mo/s, strictement linéaire
```

Une croissance linéaire, indépendante du trafic (on peut le vérifier en
arrêtant toute requête : elle continue), est une fuite, pas un cache.

Enfin, d'où vient la configuration :

```bash
systemctl cat vitrine-api
# ... /etc/systemd/system/vitrine-api.service.d/90-m16-01.conf
# [Service]
# Environment=VITRINE_FUITE=12
# MemoryMax=infinity
```

**Cause racine** : un drop-in active un mode de l'application qui alloue 12 Mo
par seconde sans jamais les rendre, et lève toute limite mémoire du cgroup. La
VM a 2 Go : au bout d'environ 150 secondes, l'OOM killer choisit le plus gros
consommateur — le service lui-même — et le tue. `Restart=always` le relance, et
le cycle recommence.

**Pourquoi c'est ce processus qui est tué** : le score de l'OOM killer est
proportionnel au RSS anonyme. Avec 1,8 Go, `vitrine-api` a le score le plus
élevé de la machine, très loin devant `sshd` (6 Mo) ou `systemd-journald`
(40 Mo). Le noyau tue toujours le plus gros, pas le responsable — ici les deux
coïncident, ce qui n'est pas la règle.

**Correctif** (sans correctif applicatif, comme demandé)

```bash
sudo rm /etc/systemd/system/vitrine-api.service.d/90-m16-01.conf
sudo systemctl edit vitrine-api      # le garde-fou qui reste
```

```ini
[Service]
MemoryHigh=200M
MemoryMax=256M
Restart=on-failure
RestartSec=5s
```

```bash
sudo systemctl daemon-reload
sudo systemctl reset-failed vitrine-api
sudo systemctl restart vitrine-api
systemctl show vitrine-api -p MemoryMax -p NRestarts
sleep 300; systemctl status vitrine-api      # « since » ne bouge plus
```

**Ce qu'on transmet au développeur** : la courbe de RSS (fichier CSV
horodaté), le débit de fuite mesuré (12 Mo/s), la trace OOM complète, la
version exacte du service, et la période exacte des incidents. Pas « ça fuit » :
« le RSS croît de 12 Mo/s de façon linéaire et indépendante du trafic, y compris
au repos ; ci-joint 40 minutes de mesures ».

> [!NOTE]
> **Pourquoi**
>
> Trois enseignements se superposent dans cette panne.
>
> D'abord, `active (running)` ne veut pas dire « en bonne santé » : c'est le
> champ `since` et le compteur `NRestarts` qui racontent la vérité. Un service qui
> redémarre toutes les deux minutes est « actif » 99 % du temps et inutilisable.
>
> Ensuite, `status=9/KILL` est une signature. `SIGKILL` ne vient que de trois
> endroits : un humain, un superviseur (systemd sur `TimeoutStopSec`), ou le
> noyau (OOM). Dans le journal, `Killed process` de `dmesg` tranche en une
> seconde.
>
> Enfin, `MemoryMax` change la nature de l'incident : au lieu d'un OOM global qui
> tue la plus grosse tâche de la machine — potentiellement la base de données —,
> on obtient un OOM de cgroup qui ne touche que le service fautif, journalisé
> proprement sous `Memory cgroup out of memory`. La fuite reste, mais elle
> n'emporte plus le reste de la machine.

> [!WARNING]
> **Piège**
>
> Deux réflexes coûteux. Ajouter de la RAM à la VM : la fuite étant linéaire et
> sans borne, on repousse l'échéance de quelques minutes et on aggrave l'incident
> (la victime suivante sera plus grosse à recharger). Mettre
> `OOMScoreAdjust=-1000` sur le service pour qu'il « ne soit plus tué » : le
> noyau ira tuer autre chose — `sshd` par exemple — et tu perdras l'accès à la
> machine pendant que la fuite continue.

---

### <a id="bf19-2"></a>**[BF19.2](README.md#bf19-2)** — *« Passé 200 utilisateurs, tout casse » (`Errno 24`).*

**Démarche**

```bash
bash /opt/vitrine/bin/vitrine-charge.sh /rapport 5 30
journalctl -u vitrine-api -n 20 --no-pager
# OSError: [Errno 24] Too many open files (fd ouverts: 123)
```

`EMFILE` : la limite **par processus** est atteinte. On vérifie les deux
nombres qui comptent, jamais l'un sans l'autre :

```bash
PID=$(systemctl show vitrine-api -p MainPID --value)
ls -1 /proc/$PID/fd | wc -l
# 126
grep 'Max open files' /proc/$PID/limits
# Max open files            128     128     files
```

126 sur 128 : la cause immédiate est établie. Deux questions restent : d'où
vient la limite, et pourquoi le compte monte-t-il ?

```bash
systemctl show vitrine-api -p LimitNOFILE -p LimitNOFILESoft
# LimitNOFILE=128
systemctl cat vitrine-api | grep -A3 m16-02
# LimitNOFILE=128
# Environment=VITRINE_FD=3
ls -l /proc/$PID/fd | tail -5
# 3 -> /dev/null      (des dizaines d'entrées identiques)
```

Les descripteurs ouverts pointent tous vers le même fichier : l'application ne
referme pas ce qu'elle ouvre à chaque requête. La limite basse ne fait
qu'avancer la date de l'incident.

**Cause racine** : deux causes qui se composent. Un drop-in impose
`LimitNOFILE=128`, très en dessous du défaut Ubuntu (1024 souple / 524 288
dur) ; et l'application garde trois descripteurs par requête. À trois fuites
par requête, 42 requêtes suffisent.

**Correctif**

```bash
sudo rm /etc/systemd/system/vitrine-api.service.d/90-m16-02.conf
sudo systemctl edit vitrine-api
```

```ini
[Service]
LimitNOFILE=65535
Environment=VITRINE_FD=0
```

```bash
sudo systemctl daemon-reload
sudo systemctl restart vitrine-api
PID=$(systemctl show vitrine-api -p MainPID --value)
grep 'Max open files' /proc/$PID/limits     # 65535
bash /opt/vitrine/bin/vitrine-charge.sh /rapport 5 30
ls -1 /proc/$PID/fd | wc -l                 # stable
```

**Détection anticipée** — la mesure qui aurait évité l'incident :

```bash
#!/usr/bin/env bash
# taux d'utilisation des descripteurs d'un service
PID=$(systemctl show "$1" -p MainPID --value)
U=$(ls -1 /proc/$PID/fd | wc -l)
M=$(awk '/Max open files/ {print $4}' /proc/$PID/limits)
echo "$1 : $U / $M ($(( U * 100 / M )) %)"
[ $(( U * 100 / M )) -lt 80 ]
```

Une alerte à 80 % du plafond prévient des heures avant la panne, avec une
courbe qui monte : c'est exactement le genre de dérive lente qu'aucune alerte
de disponibilité ne verra jamais.

> [!NOTE]
> **Pourquoi**
>
> La leçon centrale est la provenance des limites. Un service systemd **ne passe
> pas par PAM** : `/etc/security/limits.conf` ne le concerne pas, quoi qu'en
> disent la moitié des réponses trouvées en ligne. La chaîne est
> `LimitNOFILE=` de l'unité, puis `DefaultLimitNOFILE=` de
> `/etc/systemd/system.conf`. La preuve définitive, celle qu'on montre en
> réunion, est `/proc/<pid>/limits` : elle décrit le processus qui tourne, pas
> une intention de configuration.
>
> Autre détail instructif : quand les descripteurs sont épuisés, l'application ne
> peut même plus ouvrir son propre fichier de journal. Les messages n'existent que
> sur la sortie standard, donc dans `journalctl`. Un incident de descripteurs est
> souvent invisible dans les logs applicatifs habituels — ce qui fait perdre un
> temps considérable à qui ne regarde pas le journal systemd.

> [!WARNING]
> **Piège**
>
> « Un redémarrage règle le problème » est vrai et trompeur : il remet le compteur
> à zéro sans toucher à la fuite ni à la limite. Beaucoup d'équipes finissent par
> programmer un redémarrage horaire et considérer l'affaire close. Le jour où le
> trafic double, l'heure devient vingt minutes, et l'incident revient avec
> l'ancienneté en plus.

---

### <a id="bf19-3"></a>**[BF19.3](README.md#bf19-3)** — *Disque plein alors que `du` ne trouve rien.*

**Démarche**

```bash
curl -s http://127.0.0.1:8080/commande
# ecriture impossible: [Errno 28] No space left on device
df -h  /srv/vitrine/data     # 477M utilisés sur 488M, 100%
df -i  /srv/vitrine/data     # 16/32768 inodes : ce n'est PAS un problème
                             # d'inodes
du -xsh /srv/vitrine/data    # 24K
```

Écart de 477 Mo entre ce que compte le système de fichiers et ce que compte
l'arborescence. Un seul mécanisme produit cela :

```bash
sudo lsof +L1 | grep /srv/vitrine/data
# python3 8312 root 3w REG 7,3 499122176 0 13
#   /srv/vitrine/data/rotation-en-cours.tmp (deleted)
```

`NLINK` à 0 : le fichier n'a plus de nom mais occupe toujours 476 Mo. Le
processus 8312 le garde ouvert sur son descripteur 3.

```bash
ps -p 8312 -o pid,etime,args --no-headers
# 8312 00:06:41 python3 /usr/local/sbin/vitrine-rotation /srv/vitrine/data
sudo ls -l /proc/8312/fd/3
# l-wx------ 1 root root 64 ... /proc/8312/fd/3 ->
#   /srv/vitrine/data/rotation-en-cours.tmp (deleted)
```

**Cause racine** : l'agent d'archivage ouvre un fichier de travail, le remplit,
le supprime du répertoire, et continue de l'utiliser par son descripteur. Le
noyau ne libère les blocs qu'au dernier `close()` : tant que le processus vit,
l'espace reste consommé et invisible.

**Correctif, sans tuer personne**

```bash
sudo truncate -s 0 /proc/8312/fd/3
df -h /srv/vitrine/data          # 452M disponibles, immédiatement
curl -s http://127.0.0.1:8080/commande
# commande enregistree dans /srv/vitrine/data/cmd-1789753506735.txt
ps -p 8312 -o pid,args --no-headers   # toujours vivant
```

`truncate` à travers `/proc/<pid>/fd/<n>` agit sur l'inode réel : les blocs
sont rendus au système de fichiers sans que le processus soit interrompu.

**Prévention**

* Corriger l'agent : ne pas supprimer un fichier encore en cours d'écriture, ou
  le borner (rotation par taille).
* Superviser `lsof +L1` : une alerte « plus de 500 Mo retenus par des fichiers
  supprimés » détecte la classe entière de problèmes, y compris la version la
  plus courante, `logrotate` qui supprime au lieu de tronquer.
* Configurer `logrotate` avec `copytruncate` ou un `postrotate` qui envoie le
  bon signal au service.
* Alerter sur le remplissage à 80 %, pas à 100 % : ici, 476 Mo se sont
  accumulés progressivement, l'alerte aurait eu des heures d'avance.

> [!NOTE]
> **Pourquoi**
>
> Le mécanisme tient en une phrase : un inode vit tant que (liens durs > 0) **ou**
> (descripteurs ouverts > 0). `rm` ne décrémente que le premier compteur. Tant que
> le second n'est pas à zéro, les blocs restent alloués, et aucune commande
> travaillant sur les **noms** de fichiers — `du`, `find`, `ls`, `rm` — ne peut
> les voir. Seules les commandes qui travaillent sur les **descripteurs**
> (`lsof`, `/proc/*/fd`) les atteignent.

> [!WARNING]
> **Piège**
>
> Le réflexe « je redémarre le service, ça libère » fonctionne et détruit la
> preuve : tu ne sauras jamais quel fichier retenait l'espace ni pourquoi, donc
> tu ne pourras pas empêcher la récidive. Et si le processus fautif n'est pas
> celui qu'on croit — ce qui est fréquent —, le redémarrage ne libère rien et on
> conclut à tort à un autre problème. Trente secondes de `lsof +L1` donnent le
> nom, le PID, le descripteur et la taille : on répare **et** on sait.

---

### <a id="bf19-4"></a>**[BF19.4](README.md#bf19-4)** — *Le serveur rame, « on ne voit rien dans le top ».*

**Démarche**

```bash
uptime
# load average: 4.31, 3.98, 2.44      (sur 2 vCPU)
mpstat -P ALL 1 3
# all  %usr 97.2  %sys 1.1  %iowait 0.0  %steal 0.0  %idle 1.7
```

Les deux cœurs sont saturés en espace utilisateur : ce n'est ni le disque
(`%iowait` à 0) ni l'hyperviseur (`%steal` à 0). Reste à trouver qui :

```bash
pidstat 1 3 | sort -k8 -rn | head -6
ps -eo pid,pcpu,etime,args --sort=-pcpu --no-headers | head -5
# 3921 66.4 00:12:03 /usr/local/sbin/vitrine-reindex 3
# 3922 65.9 00:12:03 /usr/local/sbin/vitrine-reindex 3
# 3923 64.8 00:12:03 /usr/local/sbin/vitrine-reindex 3
```

Trois processus, chacun à environ 65 % : dans `top` trié par défaut, aucun
n'atteint 100 % et on passe à côté. `etime` à 12 minutes correspond exactement
au début des plaintes — la corrélation temporelle est la moitié de la preuve.

Qui les maintient en vie ?

```bash
systemctl status 3921
# vitrine-reindex.service - Vitrine — reconstruction de l'index de recherche
#   Loaded: loaded (/etc/systemd/system/vitrine-reindex.service; enabled)
systemd-cgls -u vitrine-reindex.service
cat /etc/systemd/system/vitrine-reindex.service
# ExecStart=/usr/local/sbin/vitrine-reindex 3
# Restart=always
```

Preuve que c'est la cause et non la conséquence :

```bash
curl -w '%{time_total}\n' -o /dev/null -s http://127.0.0.1:8080/produits
# 2.431
sudo systemctl stop vitrine-reindex
curl -w '%{time_total}\n' -o /dev/null -s http://127.0.0.1:8080/produits
# 0.002        <- retour à la baseline
uptime                                        # la charge redescend
```

**Cause racine** : une unité `vitrine-reindex.service` lance trois boucles de
calcul dont la condition d'arrêt n'est jamais atteinte. `Restart=always` la
relance à chaque arrêt : tuer les PID ne sert à rien, ils reviennent en deux
secondes.

**Correctif**

```bash
sudo systemctl stop vitrine-reindex
sudo systemctl disable vitrine-reindex        # ne repartira pas au boot
sudo systemctl mask vitrine-reindex           # si un autre outil la relance
pgrep -af vitrine-reindex                     # plus rien
```

Si l'unité doit exister (le travail d'indexation est légitime mais le code
boucle), on la borne au lieu de la supprimer :

```ini
[Service]
CPUQuota=25%
Nice=19
RuntimeMaxSec=600
```

**Prévention** : une alerte sur `charge / nproc > 1` soutenue pendant 5 minutes ;
`CPUQuota=` sur toute unité de traitement par lots, pour qu'un batch fou ne
puisse jamais dégrader le service en ligne ; et une revue des unités déployées
(`systemctl list-unit-files --state=enabled`) après chaque livraison.

> [!NOTE]
> **Pourquoi**
>
> Deux réflexes à acquérir. Le premier : `systemctl status <PID>` répond à
> « à quelle unité appartient ce processus ? ». C'est immédiat et cela remplace
> toute enquête sur l'arborescence des processus ; `systemd-cgls` donne la même
> information sous forme d'arbre. Le second : on ne tue jamais un processus
> supervisé, on arrête son unité. Un `kill` sur un service `Restart=always`
> donne l'illusion d'agir pendant deux secondes.
>
> Sur « on ne voit rien dans top » : trois processus à 65 % pèsent plus que deux
> processus à 95 %, mais aucun ne ressort visuellement. Il faut trier
> (`top` puis `P`, ou `ps --sort=-pcpu`) et surtout **sommer** — c'est ce que fait
> `mpstat`, qui montrait déjà 97 % de `%usr` toutes tâches confondues.

> [!WARNING]
> **Piège**
>
> `pkill -f vitrine` sur ce genre de panne est une double faute : le motif
> correspond aussi à `vitrine-api`, donc on tue le service qu'on essaie de sauver ;
> et `pkill -f` peut correspondre à **sa propre ligne de commande** quand elle est
> lancée depuis un script dont le nom contient le motif. Toujours vérifier avec
> `pgrep -af motif` avant de tuer quoi que ce soit.

---

### <a id="bf19-5"></a>**[BF19.5](README.md#bf19-5)** — *`Cannot assign requested address` une fois sur deux.*

**Démarche**

```bash
bash /opt/vitrine/bin/vitrine-charge.sh /produits 10 30
# ok=312 ko=88
journalctl -u vitrine-api --since '-2 min' | grep -c 'Errno 99'
# 3025
```

`EADDRNOTAVAIL` au moment du `connect()` : il n'y a plus de port source
disponible. On mesure la capacité et la consommation :

```bash
sysctl net.ipv4.ip_local_port_range
# net.ipv4.ip_local_port_range = 32768   32778      -> 11 ports !
ss -s
# TCP:  1043 (estab 6, closed 1021, timewait 1019)
ss -tan state time-wait | wc -l
# 1019
sysctl net.ipv4.tcp_fin_timeout          # 120 au lieu de 60
cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null   # 256
```

Onze ports éphémères pour plus de mille sockets en `TIME_WAIT` : le verdict est
arithmétique. On cherche d'où vient le réglage :

```bash
grep -rn 'ip_local_port_range' /etc/sysctl.conf /etc/sysctl.d/
# /etc/sysctl.d/99-m16-05-reseau.conf:2:
#   net.ipv4.ip_local_port_range = 32768 32778
head -1 /etc/sysctl.d/99-m16-05-reseau.conf
# durcissement reseau - ticket CHG-1187
```

**Cause racine** : un fichier `sysctl.d` déposé lors d'un « durcissement
réseau » réduit la plage de ports éphémères de 28 232 à 11, double le
`tcp_fin_timeout` (qui allonge `FIN_WAIT_2`, pas `TIME_WAIT`, figé à 60 s) et ramène la
table de suivi de connexions à 256 entrées. Tant que le trafic est faible, rien
ne se voit ; dès que l'application ouvre plusieurs connexions sortantes par
seconde, elle épuise la plage.

**Correctif**

```bash
sudo rm /etc/sysctl.d/99-m16-05-reseau.conf
# sysctl --system ne remet PAS les défauts des clés qu'aucun fichier ne
# définit : on repose à la main les valeurs par défaut du noyau
sudo sysctl -w net.ipv4.ip_local_port_range="32768 60999" \
  net.ipv4.tcp_fin_timeout=60 net.netfilter.nf_conntrack_max=65536
sysctl net.ipv4.ip_local_port_range   # 32768 60999
```

Si un durcissement doit vraiment exister, il s'écrit avec des valeurs
défendables et un commentaire qui les justifie :

```ini
# /etc/sysctl.d/99-reseau.conf — CHG-1187, revu le 2026-09-18
net.ipv4.ip_local_port_range = 10240 65535   # 55 295 ports ephemeres
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1                    # reutilisation en sortie
net.netfilter.nf_conntrack_max = 131072
```

Vérification :

```bash
bash /opt/vitrine/bin/vitrine-charge.sh /produits 10 30   # ko=0
journalctl -u vitrine-api --since '-1 min' | grep -c 'Errno 99'   # 0
```

**Pourquoi un redémarrage aurait « réglé » le problème pendant une heure** : au
redémarrage, le processus ferme toutes ses sockets et le trafic retombe à zéro
le temps que les clients reviennent. Les entrées `TIME_WAIT` expirent en
arrière-plan et la poignée de ports disponibles redevient libre. Le symptôme
disparaît donc réellement — jusqu'à ce que le trafic remonte et ré-épuise les
onze ports. C'est le pire des cas : un correctif apparent qui empêche de
chercher la cause.

**Prévention** : superviser le rapport `sockets en TIME_WAIT / taille de la
plage` ; interdire les `sysctl` sans justification écrite et sans revue ;
côté application, réutiliser les connexions (keep-alive, pool) — c'est le seul
correctif qui supprime le problème au lieu d'en repousser le seuil.

> [!NOTE]
> **Pourquoi**
>
> Le calcul de capacité mérite d'être su par cœur : (nombre de ports de la plage)
> divisé par la durée de `TIME_WAIT` (60 s, valeur figée dans le noyau) donne le
> nombre maximal de nouvelles connexions par seconde **vers une même
> destination**. Avec les valeurs par défaut : 28 232 / 60 ≈ 470/s. Avec la plage
> cassée de cet exercice : 11 / 60 ≈ 0,18/s. C'est ce genre de calcul qui
> transforme « le réseau déconne » en « nous sommes limités à 0,18 connexion par
> seconde ».
>
> Le quadruplet explique aussi pourquoi le symptôme est intermittent et
> destination-dépendante : la contrainte s'applique par couple (IP, port) distant.
> Certains appels passent, d'autres non, ce qui ressemble à s'y méprendre à un
> problème réseau aléatoire.

> [!WARNING]
> **Piège**
>
> `net.ipv4.tcp_tw_recycle` traîne encore dans tous les billets de blog des
> années 2010. Il a été **supprimé du noyau en 4.12** parce qu'il cassait
> silencieusement les connexions venant d'un même NAT. S'il apparaît dans un
> fichier `sysctl.d` sur une machine moderne, il est ignoré — mais il signale un
> fichier copié sans compréhension, donc probablement d'autres réglages douteux
> dans le même fichier : lis-le en entier.

---

### <a id="bf19-6"></a>**[BF19.6](README.md#bf19-6)** — *Tout est lent, exactement lent (5 secondes).*

**Démarche**

```bash
for i in 1 2 3; do
  curl -o /dev/null -s -w '%{time_total}\n' http://127.0.0.1:8080/produits
done
# 5.009
# 5.008
# 5.010
curl -o /dev/null -s -w '%{time_total}\n' http://127.0.0.1:8080/sante
# 0.001
```

Trois mesures à quatre millisecondes près : ce n'est pas de la contention,
c'est un **délai d'expiration**. Et `/sante`, qui n'appelle rien à l'extérieur,
est instantané : le problème est dans une dépendance, pas dans le serveur.

Vérification que rien n'est saturé (indispensable pour éliminer, et pour ne pas
avoir à y revenir) :

```bash
uptime; free -m; iostat -xz 1 2; mpstat 1 2
# tout au repos
```

Où part le temps, côté appels système :

```bash
PID=$(systemctl show vitrine-api -p MainPID --value)
sudo timeout 15 strace -f -T -p "$PID" 2>&1 | awk '$NF ~ /<[1-9]/' &
curl -s -o /dev/null http://127.0.0.1:8080/produits
# poll([{fd=8, events=POLLIN}], 1, 5000) = 0 (Timeout) <5.004812>
sudo ls -l /proc/$PID/fd/8
# 8 -> socket:[48213]
ss -anp | grep 48213
# udp UNCONN 0 0 127.0.0.1:41288 127.0.0.77:53
```

Une socket UDP vers le port 53 : c'est du DNS. Confirmation indépendante par le
réseau :

```bash
sudo timeout 20 tcpdump -ni any -w /tmp/dns.pcap 'udp port 53' &
curl -s -o /dev/null http://127.0.0.1:8080/produits
tcpdump -r /tmp/dns.pcap -nn -tttt
# 14:31:02.114 IP 127.0.0.1.41288 > 127.0.0.77.53: 5891+ A?
#   api-interne.lab.local. (39)
# (aucune réponse)
```

La configuration :

```bash
cat /etc/resolv.conf
# nameserver 127.0.0.77          <- en tête
# nameserver 10.10.10.1
# options timeout:5 attempts:1
grep -n api-interne /etc/hosts
# 7:#127.0.0.1  api-interne.lab.local api-interne     <- commentée
ss -lunp | grep ':53'
# UNCONN 0 0 127.0.0.77:53 users:(("python3",pid=8381,fd=3))
systemctl status dns-cache-local
# Cache DNS local (agent de resolution) — active (running)
```

**Cause racine** : un « agent de cache DNS » déployé la veille écoute sur
127.0.0.77:53 et ne répond jamais. Il a été placé en **première** position dans
`/etc/resolv.conf`, avec `timeout:5 attempts:1`. Dans le même changement,
l'entrée `api-interne.lab.local` de `/etc/hosts` a été retirée « puisque le DNS
s'en charge ». Résultat : chaque résolution attend 5 secondes le résolveur muet
avant de passer au suivant. L'application a un repli codé en dur sur
`127.0.0.1`, donc elle finit par répondre — ce qui explique que rien ne soit en
erreur et que tout soit simplement lent.

**Correctif**

```bash
sudo systemctl disable --now dns-cache-local
sudo sed -i '/^nameserver 127.0.0.77/d' /etc/resolv.conf
sudo sed -i 's/^#\(.*api-interne\.lab\.local\)/\1/' /etc/hosts
sudo sed -i 's/^options .*/options timeout:1 attempts:2/' /etc/resolv.conf

getent hosts api-interne.lab.local        # 127.0.0.1 api-interne.lab.local
curl -o /dev/null -s -w '%{time_total}\n' http://127.0.0.1:8080/produits
# 0.002
```

Durabilité : sur une machine où `/etc/resolv.conf` est un lien vers
`/run/systemd/resolve/stub-resolv.conf` ou géré par `netplan`, l'édition
directe sera écrasée au prochain redémarrage. La configuration doit alors être
posée dans `/etc/systemd/resolved.conf` (`DNS=`, `FallbackDNS=`) ou dans le
fichier `netplan` correspondant, suivi de `netplan apply`.

**Prévention** : deux serveurs de noms fonctionnels minimum, `timeout:1
attempts:2` pour que l'échec coûte 2 s au lieu de 10, un test de résolution
chronométré dans la supervision (`getent hosts` avec seuil), et une règle de
changement : un composant qui s'insère dans le chemin critique se déploie
derrière les résolveurs existants, jamais devant, tant qu'il n'est pas validé.

> [!NOTE]
> **Pourquoi**
>
> La régularité du délai est le meilleur indice du métier. Une ressource saturée
> produit des temps dispersés ; un délai d'expiration produit des temps quasi
> identiques. Quand tu vois 5,00 s trois fois de suite, cherche une valeur de
> configuration : 5 s (`options timeout` du résolveur), 10 s, 30 s (client HTTP),
> 120 s (`connect` TCP par défaut).
>
> Second point : le repli codé en dur dans l'application est ce qui rend
> l'incident insidieux. Aucune erreur, aucun code 500, aucune alerte — juste un
> service 2 500 fois plus lent. C'est le cas typique où les quatre signaux dorés
> (latence) voient tout et où USE ne voit rien : aucune ressource de la machine
> n'est sollicitée.

> [!WARNING]
> **Piège**
>
> `ping api-interne.lab.local` pour « tester le DNS » est trompeur : `ping`
> résout lui aussi en 5 secondes, mais l'affichage de la latence ICMP (0,04 ms)
> est ce qu'on lit, et on conclut que « le réseau va bien ». Pour chronométrer
> une résolution, il faut mesurer la résolution :
> `time getent hosts api-interne.lab.local`, ou `dig +time=1 +tries=1`.

---

### <a id="bf19-7"></a>**[BF19.7](README.md#bf19-7)** — *Le service tourne mais n'écrit plus rien (`Errno 30`).*

**Démarche**

```bash
curl -s http://127.0.0.1:8080/commande
# ecriture impossible: [Errno 30] Read-only file system
findmnt --target /srv/vitrine/data
# TARGET            SOURCE     FSTYPE OPTIONS
# /srv/vitrine/data /dev/loop3 ext4   ro,relatime,errors=remount-ro
```

Le montage est passé en lecture seule. Ce n'est jamais spontané : le noyau l'a
décidé.

```bash
dmesg -T | tail -20
# blk_update_request: I/O error, dev loop3, sector 208896 op 0x1
# EXT4-fs warning (device loop3): ext4_end_bio: I/O error 10
# EXT4-fs error (device loop3): ext4_journal_check_start:
# EXT4-fs (loop3): Remounting filesystem read-only
journalctl -k --since '-30 min' | grep -iE 'I/O error|EXT4-fs error'
```

La chaîne est complète : erreur d'E/S sur le périphérique → erreur ext4 →
remontage automatique en lecture seule. C'est l'option `errors=remount-ro` du
montage qui a fait ce choix, et c'est un **comportement voulu** : devant une
erreur d'écriture, ext4 préfère arrêter d'écrire plutôt que corrompre
davantage. `errors=continue` aurait laissé l'application écrire dans un système
de fichiers en train de se corrompre ; `errors=panic` aurait figé la machine.

Le remontage simple ne suffira pas :

```bash
sudo mount -o remount,rw /srv/vitrine/data
# mount: /srv/vitrine/data: cannot remount /var/lib/vitrine/data.img
#        read-write, is write-protected.
sudo blockdev --getro /dev/loop3
# 1
cat /sys/block/loop3/ro
# 1
```

La protection est **au niveau bloc**, pas au niveau du système de fichiers :
tant que le périphérique refuse les écritures, aucun remontage en écriture ne
peut réussir. C'est exactement ce que fait un disque réel qui bascule en lecture
seule sur défaillance.

**Correctif**

```bash
# 1. libérer le montage
sudo systemctl stop vitrine-api
sudo fuser -vm /srv/vitrine/data          # qui tient encore le montage ?
sudo umount /srv/vitrine/data

# 2. vérifier le système de fichiers
#    ATTENTION : avec un montage par image loop, le démontage détache le
#    loop ; e2fsck doit alors travailler sur le FICHIER image.
losetup -a | grep vitrine                 # plus rien : loop détaché
sudo e2fsck -fy /var/lib/vitrine/data.img
# vitrine-data: 16/32768 files (0.0% non-contiguous), 6358/131072 blocks

# 3. remonter
sudo mount /srv/vitrine/data
findmnt -n -o SOURCE,OPTIONS --target /srv/vitrine/data
# /dev/loop3  rw,relatime,errors=remount-ro
sudo blockdev --getro "$(findmnt -n -o SOURCE --target /srv/vitrine/data)"
# 0

# 4. vérifier
sudo systemctl start vitrine-api
curl -s http://127.0.0.1:8080/commande
# commande enregistree dans /srv/vitrine/data/cmd-....txt
```

Sur un **vrai disque** (`/dev/sdb1`, qui ne disparaît pas au démontage), la
séquence est la même avec deux différences : `sudo blockdev --setrw /dev/sdb`
pour retirer le drapeau lecture seule, et surtout un contrôle matériel avant de
remettre en service :

```bash
sudo smartctl -a /dev/sdb | grep -iE 'result|reallocated|pending|offline'
sudo smartctl -t short /dev/sdb
```

Un `Reallocated_Sector_Ct` ou un `Current_Pending_Sector` qui augmente signifie
que le disque est en train de mourir : on remonte en écriture pour évacuer les
données, on ne remet pas le service dessus.

**Prévention**

* `smartd` activé, avec alerte par courriel sur les attributs SMART.
* Une alerte sur le journal du noyau : `I/O error`, `EXT4-fs error`,
  `Remounting filesystem read-only` — trois motifs, une alerte critique.
* Une sonde de supervision qui **écrit** réellement un fichier de test, et pas
  seulement un `GET` sur une page d'accueil : un système de fichiers en lecture
  seule laisse tous les contrôles en lecture au vert.
* `nofail` sur les montages secondaires pour ne pas bloquer un redémarrage.

> [!NOTE]
> **Pourquoi**
>
> Trois notions se recoupent ici. D'abord `errors=remount-ro` : ce n'est pas une
> panne, c'est une protection — la connaître évite de la contourner en aveugle.
> Ensuite la distinction entre lecture seule du **système de fichiers** (visible
> dans `findmnt`, corrigible par `remount,rw`) et lecture seule du
> **périphérique bloc** (visible dans `blockdev --getro` et
> `/sys/block/*/ro`, insensible à `remount`). Enfin, le fait qu'un remontage sans
> vérification laisse les incohérences éventuelles du journal ext4 en place :
> `e2fsck` après une erreur d'E/S n'est pas facultatif.

> [!WARNING]
> **Piège**
>
> Le piège technique de cet exercice : avec une image montée en `loop`, `umount`
> détache automatiquement le périphérique. Un `e2fsck -fy /dev/loop3` lancé après
> le démontage travaille sur un périphérique vide et affiche
> `Bad magic number in super-block` — ce qui fait croire à une corruption grave et
> conduit à des décisions catastrophiques (reformater). Toujours vérifier avec
> `losetup -a` sur quoi on va lancer `e2fsck`, et travailler sur le fichier image
> quand le loop a disparu.
>
> Piège humain : redémarrer la VM. Au redémarrage, le montage repart proprement,
> tout a l'air réparé, et la trace de l'erreur d'E/S se perd (`dmesg` est vidé,
> `journalctl -k -b -1` la garde si le journal est persistant). Si un vrai disque
> est en cause, on aura remis en production une machine qui va retomber.

---

### <a id="bf19-8"></a>**[BF19.8](README.md#bf19-8)** — *Le service clignote, puis `start-limit-hit`.*

**Démarche**

```bash
systemctl status vitrine-api
# Active: failed (Result: start-limit-hit) since ...
#   vitrine-api.service: Start request repeated too quickly.
#   vitrine-api.service: Failed with result 'start-limit-hit'.
```

Ce message est le **dernier** de la boucle, jamais la cause. On remonte au
premier événement :

```bash
journalctl -u vitrine-api -b --no-pager -o short-precise | head -40
# 17:02:11.204 Started Vitrine — frontal HTTP.
# 17:02:11.318 vitrine-api[4412]: en ecoute sur 0.0.0.0:8080
# 17:02:16.205 vitrine-api.service: Service reached runtime time limit.
#              Stopping.
# 17:02:16.210 vitrine-api.service: Failed with result 'timeout'.
# 17:02:16.211 vitrine-api.service: Scheduled restart job, restart counter
#              is at 1.
# ...
# 17:02:36.402 vitrine-api.service: Start request repeated too quickly.
```

L'information décisive est là : **`Service reached runtime time limit.
Stopping.`** L'application n'a pas planté — elle a démarré, écouté, et c'est
systemd qui l'a arrêtée au bout de 5 secondes exactement. Qui a arrêté quoi
est la première question à trancher dans une boucle de redémarrage.

```bash
systemctl show vitrine-api -p RuntimeMaxUSec -p Restart -p RestartUSec \
  -p StartLimitBurst -p StartLimitIntervalUSec
# RuntimeMaxUSec=5s
# Restart=always
# RestartUSec=1s
# StartLimitBurst=5
# StartLimitIntervalUSec=1min
systemctl cat vitrine-api | tail -12
# /etc/systemd/system/vitrine-api.service.d/90-m16-08.conf
# RuntimeMaxSec=5
```

**Cause racine** : un drop-in pose `RuntimeMaxSec=5`, dans l'idée d'« ajouter un
timeout de 5 secondes sur les requêtes ». Or `RuntimeMaxSec` est la durée de vie
maximale **du service**, pas d'une requête : systemd arrête l'unité 5 secondes
après chaque démarrage. Combiné à `Restart=always` et `RestartSec=1s`, cela
produit un cycle de 6 secondes ; au bout de 5 démarrages en moins de
`StartLimitIntervalSec=60`, le garde-fou `StartLimitBurst=5` bloque tout.

**Le rôle exact des quatre directives**

| Directive | Rôle |
|---|---|
| `Restart=` | quand relancer (`no`, `on-failure`, `always`, …) |
| `RestartSec=` | délai d'attente avant chaque relance |
| `StartLimitIntervalSec=` | largeur de la fenêtre d'observation |
| `StartLimitBurst=` | nombre de démarrages tolérés dans cette fenêtre |

Le compteur est remis à zéro par un démarrage réussi qui dure plus longtemps
que la fenêtre, ou manuellement par `systemctl reset-failed`.

**Correctif**

```bash
sudo rm /etc/systemd/system/vitrine-api.service.d/90-m16-08.conf
sudo systemctl daemon-reload
sudo systemctl reset-failed vitrine-api
sudo systemctl start vitrine-api
systemctl show vitrine-api -p RuntimeMaxUSec     # infinity
sleep 120; systemctl status vitrine-api          # since ne bouge plus
systemctl show vitrine-api -p NRestarts          # stable
```

Mesure d'urgence acceptable, si on doit stabiliser avant d'avoir compris : on
augmente `RestartSec` (espacer les tentatives, par exemple 30 s) pour cesser de
remplir le journal et de consommer du CPU, **jamais** `StartLimitBurst`, qui ne
fait que masquer l'échec. Et on l'écrit dans le journal d'incident comme
temporaire.

Le vrai timeout de requête, lui, se règle dans l'application ou dans le reverse
proxy (`proxy_read_timeout` côté nginx), pas dans l'unité systemd.

**Prévention** : relecture obligatoire des drop-ins (`systemctl cat` fait partie
de la vérification après tout changement) ; une alerte sur `NRestarts` en
croissance, qui détecte toutes les boucles de redémarrage avant qu'elles
n'atteignent la limite ; et la connaissance des directives de durée, qui se
ressemblent et ne font pas du tout la même chose : `TimeoutStartSec`,
`TimeoutStopSec`, `RuntimeMaxSec`, `WatchdogSec`.

> [!NOTE]
> **Pourquoi**
>
> `start-limit-hit` n'est pas un bug de systemd, c'est un disjoncteur. Sans lui,
> un service qui échoue au démarrage boucle indéfiniment : il consomme du CPU,
> remplit le disque de journaux (on a vu des `/var` remplis en une nuit par une
> boucle de redémarrage) et masque les autres événements du journal.
>
> La méthode générale sur toute boucle : `reset-failed` pour repartir proprement,
> puis `journalctl -u <unité> -b -o short-precise | head`. Les vingt premières
> lignes contiennent la cause dans la quasi-totalité des cas, alors que les mille
> dernières ne contiennent que le bruit du disjoncteur.

> [!WARNING]
> **Piège**
>
> La confusion `RuntimeMaxSec` / `TimeoutStartSec` / `TimeoutStopSec` est
> fréquente et coûteuse :
>
> * `TimeoutStartSec` : délai accordé **pour démarrer** (surtout utile avec
>   `Type=notify` ou `forking`) ;
> * `TimeoutStopSec` : délai avant que systemd envoie `SIGKILL` à l'arrêt ;
> * `RuntimeMaxSec` : durée de vie maximale du service, arrêt inconditionnel ;
> * `WatchdogSec` : délai maximal entre deux signaux de vie envoyés par
>   l'application (`sd_notify(WATCHDOG=1)`).
>
> Poser `RuntimeMaxSec` sur un service permanent en croyant limiter une requête
> transforme un service sain en service clignotant. Le seul usage légitime est
> volontaire et documenté : un redémarrage quotidien assumé face à une fuite
> connue, par exemple `RuntimeMaxSec=86400`.

---

## 19.8 Défi du module

<a id="d19"></a>**[D19](README.md#d19) — Examen blanc : cinq pannes, 90 minutes**

### Stratégie attendue

**Phase 1 — inventaire (10 minutes, aucune réparation).** L'erreur qui coûte
l'examen est de commencer à réparer la première anomalie rencontrée. Cinq pannes
simultanées interagissent : un volume en lecture seule fait échouer
l'écriture des preuves, un disque plein empêche le journal de s'écrire, une
saturation CPU rend toutes les mesures de latence ininterprétables.

```bash
date                                      # l'heure de début, dans le journal
bash ~/lab19/bin/preuves.sh               # les preuves, AVANT toute action
uptime; nproc
systemctl --failed
systemctl list-units 'vitrine*' 'dns*'
dmesg -T | tail -40
df -h; df -i
findmnt --target /srv/vitrine/data
free -m; vmstat 1 3
ss -s; sysctl net.ipv4.ip_local_port_range
for r in /sante /produits /commande /rapport; do
  printf '%-10s %s\n' "$r" \
    "$(curl -o /dev/null -s -w '%{http_code} %{time_total}s' \
       --max-time 12 http://127.0.0.1:8080$r)"
done
systemctl cat vitrine-api | grep -n 'conf$'   # tous les drop-ins actifs
```

Cette dernière commande vaut à elle seule plusieurs minutes : trois des huit
pannes du module passent par un drop-in de `vitrine-api`.

**Phase 2 — ordre de traitement.** Du plus bloquant au moins bloquant :

1. système de fichiers en lecture seule et disque plein (ils empêchent tout le
   reste, y compris la collecte de preuves) ;
2. service qui ne tient pas en place (boucle de redémarrage) : sans service
   vivant, aucune mesure applicative n'est possible ;
3. saturation CPU ou mémoire (elles faussent toutes les mesures de temps) ;
4. réseau et résolution de noms ;
5. descripteurs de fichiers (visible seulement sous charge, donc en dernier).

**Phase 3 — une modification à la fois.** Après chaque correctif : la commande
de vérification correspondante, et une ligne dans le journal. Un correctif non
vérifié n'en est pas un.

**Phase 4 — vérification finale.**

```bash
sudo bash check_M19_06.sh
```

### Grille de correction

| Critère | Points | Comment le vérifier |
|---|---|---|
| Pannes réparées (5 x 10) | 50 | axes sains de `check_M19_06.sh` |
| Cause racine identifiée (5 x 4) | 20 | `examen-synthese.md`, relecture |
| Journal tenu en continu | 10 | horodatages réguliers, pas de trou |
| Preuves avant réparation | 5 | archive antérieure au 1er correctif |
| Synthèse claire et complète | 5 | 5 lignes par panne |
| Vérification après correctif | 5 | une commande de contrôle par panne |
| Aucune modification parasite | 5 | `systemctl cat`, `sysctl.d/`, `fstab` |

Pénalités : -10 par rollback de snapshot, -5 par redémarrage non justifié, -5
par panne « réparée » sans cause comprise, -10 si plusieurs modifications
simultanées empêchent d'attribuer l'effet.

Seuil de réussite : 70 points.

### Modèle d'une entrée de synthèse

```markdown
### Panne 3 — écriture impossible sur /srv/vitrine/data

- Symptôme : `/commande` renvoie 500, journal applicatif
  « OSError: [Errno 28] No space left on device » ; `df` 100 %, `du` 24 Ko.
- Commande qui a tranché : `sudo lsof +L1 | grep /srv/vitrine/data`
  -> PID 8312, fd 3, 476 Mo retenus par un fichier supprimé.
- Cause racine : l'agent `vitrine-rotation` supprime son fichier de travail
  sans le fermer ; le noyau ne libère les blocs qu'au dernier close().
- Correctif : `sudo truncate -s 0 /proc/8312/fd/3` (sans tuer le processus).
- Vérification : `df -h` -> 1 % ; `curl /commande` -> 200 ; contrôle que le
  PID 8312 tourne toujours.
```

### Erreurs les plus fréquentes en situation d'examen

* Réparer sans mesurer d'abord : on ne sait plus si le correctif a servi.
* Oublier `systemctl daemon-reload` après avoir supprimé un drop-in — la
  configuration en mémoire reste l'ancienne, et on croit que la suppression n'a
  rien changé.
* Oublier `systemctl reset-failed` après un `start-limit-hit` : le service
  refuse de démarrer alors que la cause est corrigée.
* Corriger un `sysctl` avec `sysctl -w` sans toucher au fichier de
  `/etc/sysctl.d/` : tout revient au prochain redémarrage.
* Laisser derrière soi des modifications de confort (une limite relevée « pour
  voir », un service arrêté, une règle de pare-feu) non documentées.
* Tenir le journal à la fin : cela se voit immédiatement (horodatages trop
  réguliers, pas de fausse piste, aucune hypothèse abandonnée).

> [!NOTE]
> **Pourquoi**
>
> Un examen blanc n'évalue pas la connaissance des commandes — elles sont toutes
> dans ce module — mais la **méthode sous contrainte de temps**. Ce qui distingue
> les candidats, dans l'ordre : avoir fait l'inventaire avant de toucher à quoi
> que ce soit ; avoir traité les pannes dans un ordre qui tient compte de leurs
> interactions ; avoir vérifié chaque correctif ; avoir gardé une trace
> exploitable.
>
> C'est aussi ce que mesure une astreinte réelle. Un incident majeur comporte
> presque toujours plusieurs causes simultanées ou un enchaînement : la panne
> d'origine, les dégâts collatéraux, et les traces laissées par les premières
> tentatives de réparation.

> [!WARNING]
> **Piège**
>
> Le piège de fin d'examen : « tout est réparé » alors que `systemctl --failed`
> est vide uniquement parce qu'une unité a été masquée, ou que la latence est
> bonne parce que plus personne n'appelle la dépendance. La vérification
> fonctionnelle bout en bout — les quatre routes, avec leur code HTTP et leur
> temps de réponse — est la seule qui prouve quelque chose. C'est aussi pour cela
> que `check_M19_06.sh` la fait en dernier.

<!-- nav:début -->
---

[← Module 18](../18-securite/corrige.md) · [Énoncé](README.md) · [Projet A →](../../projets/P1-factura/corrige.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
