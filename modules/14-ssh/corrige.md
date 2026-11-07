<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Partie II — Administration système › **Module 14** · corrigé  
[← Module 13](../13-reseau-avance/corrige.md) · [Énoncé](README.md) · [Module 15 →](../15-services-applicatifs/corrige.md)

> [!TIP]
> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, pas avant. Chaque identifiant renvoie à son énoncé.
<!-- nav:fin -->

# Module 14 — Corrigé

## 14.3 Quiz — QCM

<a id="q14-1"></a>**[Q14.1](README.md#q14-1)** — *Choix d'un type de clé pour un compte de déploiement.*

**Réponses : a) et c)**

> [!NOTE]
> **Pourquoi**
>
> `ed25519` est un jeu de paramètres **figé** : la courbe est Curve25519, la
> taille est 256 bits, il n'y a rien à choisir. C'est sa première qualité
> opérationnelle : personne ne peut générer une clé trop courte par distraction,
> alors que `ssh-keygen -t rsa` sans `-b` donne encore 3072 bits et que beaucoup
> de documentations traînent avec `-b 1024`.
>
> Sur le fond cryptographique : une clé `ed25519` de 256 bits offre environ
> 128 bits de sécurité, soit l'équivalent d'un RSA de 3072 bits. RSA 4096 monte à
> ~150 bits — un gain réel mais sans intérêt pratique, payé par des signatures
> plus lentes et une clé publique de 700 octets contre 68. Sur un parc où chaque
> connexion signe, et où `authorized_keys` est lu à chaque tentative, ça se voit.
>
> L'argument décisif est ailleurs : EdDSA produit une signature **déterministe**,
> le nonce est dérivé de la clé privée et du message par hachage. Un générateur
> aléatoire défaillant au moment de la signature ne divulgue donc pas la clé
> privée, alors que c'est exactement le scénario qui a cassé des implémentations
> ECDSA par le passé.
>
> c) reste vrai : OpenSSH ne connaît `ed25519` que depuis la 6.5 (2014). Face à un
> commutateur, un vieil appliance ou un HSM limité, RSA 4096 est le repli.

> [!WARNING]
> **Piège**
>
> b) confond longueur de clé et niveau de sécurité : 256 bits sur courbe
> elliptique ne se comparent pas à 256 bits de RSA. d) est faux, toute clé privée
> OpenSSH peut être chiffrée par une passphrase, quel que soit son type — et
> depuis OpenSSH 7.8 le format de stockage est le format OpenSSH natif avec
> dérivation `bcrypt_pbkdf`, bien plus résistant au cassage hors ligne que
> l'ancien format PEM chiffré en MD5+3DES.

---

<a id="q14-2"></a>**[Q14.2](README.md#q14-2)** — *`UNPROTECTED PRIVATE KEY FILE`, permissions 0644.*

**Réponse : b)** il ignore cette clé et continue avec les autres méthodes.

> [!NOTE]
> **Pourquoi**
>
> Le contrôle est purement local et purement préventif : `ssh` refuse de charger
> une clé privée lisible par d'autres comptes de la machine, parce qu'une clé
> lisible est une clé potentiellement déjà copiée. Il l'écarte de la liste des
> identités à proposer, puis poursuit avec ce qui reste : autres `IdentityFile`,
> clés de l'agent, `keyboard-interactive`, mot de passe.
>
> Conséquence pratique : le symptôme final n'est pas le message d'avertissement,
> c'est un `Permission denied (publickey)` ou une demande de mot de passe
> inattendue. Quand un utilisateur te dit « il me redemande mon mot de passe
> depuis que j'ai restauré mon `/home` », cherche les permissions avant tout le
> reste : une restauration d'archive sans `-p` ou un `cp` depuis Windows remet
> couramment du `0644`.
>
> Correctif : `chmod 600 ~/.ssh/id_ed25519` (et `700` sur `~/.ssh`).

> [!WARNING]
> **Piège**
>
> Le contrôle regarde le mode **et** le propriétaire. Une clé en `0600` mais
> appartenant à root dans le home d'un utilisateur est rejetée de la même façon.
> `ls -l` seul ne suffit donc pas : regarde aussi la colonne propriétaire. Et
> l'avertissement n'apparaît **pas** si la clé est déjà dans l'agent : l'agent
> détient la clé en mémoire, `ssh` n'a pas à lire le fichier.

---

<a id="q14-3"></a>**[Q14.3](README.md#q14-3)** — *`Authentication refused: bad ownership or modes` dans le journal serveur.*

**Réponse : b)** `Permission denied (publickey)`.

> [!NOTE]
> **Pourquoi**
>
> C'est le principe même du protocole : le serveur ne dit jamais **pourquoi** une
> authentification échoue. Il ne dira pas « ce compte n'existe pas », ni « tes
> permissions sont mauvaises », ni « ta clé n'est pas dans le fichier ». Toute
> divulgation de ce genre aiderait un attaquant à énumérer les comptes valides ou
> à cartographier la configuration.
>
> Le client reçoit donc toujours le même refus générique, et la cause réelle
> n'existe que dans le journal du serveur. D'où la règle de diagnostic du module :
> un `Permission denied (publickey)` se diagnostique **sur le serveur**, avec
> `journalctl -u ssh -n 50`, pas en relançant le client dix fois.
>
> Ici la cause est `StrictModes yes` (le défaut) : `sshd` refuse de lire un
> `authorized_keys` dans un répertoire accessible en écriture à d'autres que le
> propriétaire, parce que quiconque peut écrire dans `~/.ssh` peut y ajouter sa
> propre clé et devenir l'utilisateur.

> [!WARNING]
> **Piège**
>
> Le contrôle remonte jusqu'au **home** : un `/home/mathieu` en `0775` avec un
> groupe dont d'autres sont membres suffit à déclencher le refus, même si
> `~/.ssh` est parfait en `700`. Le message du journal nomme alors le répertoire
> fautif — lis-le jusqu'au bout au lieu de corriger `~/.ssh` par réflexe.

---

<a id="q14-4"></a>**[Q14.4](README.md#q14-4)** — *`REMOTE HOST IDENTIFICATION HAS CHANGED` sur `lab-db`.*

**Réponse : c)** vérifier l'empreinte réelle par un canal indépendant de SSH.

> [!NOTE]
> **Pourquoi**
>
> Ce message est le seul moment où SSH te protège d'un attaquant en position
> d'interception. Le supprimer sans réfléchir, c'est désactiver la seule
> protection qui a servi.
>
> La démarche correcte tient en trois temps :
>
> 1. **Constater** : le message donne l'empreinte reçue et la ligne exacte de
>    `~/.ssh/known_hosts` en cause. `ssh-keygen -F lab-db` affiche l'entrée
>    enregistrée.
> 2. **Vérifier hors bande** : console Proxmox de la VM, puis
>    `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`. Autres canaux
>    acceptables : l'inventaire de ton outil de gestion de configuration, un
>    enregistrement SSHFP signé, une capture d'écran de la mise en service. Le
>    canal ne doit pas être SSH vers cette même machine.
> 3. **Trancher** : si les empreintes correspondent, le changement est légitime
>    (réinstallation, restauration, régénération des clés d'hôte) et on met à jour
>    l'entrée. Sinon, on ne se connecte pas et on ouvre un incident.
>
> C'est aussi à ce moment qu'on se demande pourquoi l'incident a pu arriver : un
> parc qui régénère ses clés d'hôte à chaque reconstruction de VM provoque ce
> message en permanence, et les équipes finissent par prendre le réflexe de
> l'ignorer. La vraie réponse est ailleurs : certificats d'hôte signés par une CA.

> [!WARNING]
> **Piège**
>
> a) est ce que fait tout le monde, et c'est ce qui rend l'attaque viable : si le
> réflexe collectif est `ssh-keygen -R`, l'alerte ne sert plus à rien. b) est pire
> encore : `StrictHostKeyChecking=no` ne désactive pas seulement l'alerte de
> changement, il accepte aussi silencieusement n'importe quel hôte inconnu, sur
> toutes les connexions futures couvertes par le bloc. d) détruit la référence
> pour **toutes** les machines : le prochain vrai incident passera inaperçu.

---

<a id="q14-5"></a>**[Q14.5](README.md#q14-5)** — *À quoi sert `ssh -G lab-db` ?*

**Réponse : b)** afficher la configuration effective pour cet alias, sans se
connecter.

> [!NOTE]
> **Pourquoi**
>
> `ssh -G` applique toute la chaîne de résolution — `~/.ssh/config`, les
> `Include`, `/etc/ssh/ssh_config`, les options `-o` de la ligne de commande, les
> blocs `Match` — et imprime le résultat final, une directive par ligne, en
> minuscules. Aucun paquet réseau n'est émis.
>
> C'est l'arbitre de tous les débats sur « mais j'ai bien mis `User` dans mon
> config ». Au lieu de relire le fichier, tu demandes au programme ce qu'il en a
> compris :
>
> ```console
> $ ssh -G lab-db | grep -E '^(user|hostname|port|identityfile|proxyjump)'
> user mathieu
> hostname 10.10.10.12
> port 22
> identityfile ~/.ssh/id_ed25519
> proxyjump bastion
> ```
>
> L'équivalent côté serveur est `sshd -T`. Le couple `ssh -G` / `sshd -T` remplace
> avantageusement `grep` dans 90 % des diagnostics de ce module.

> [!WARNING]
> **Piège**
>
> Attention à `Match exec` : `ssh -G` **exécute** réellement la commande du
> `Match` pour l'évaluer. Une commande lente ou interactive dans un `Match exec`
> rend `ssh -G` (et toutes tes connexions) lent. Et `ssh -G` n'évalue pas les
> `Match` qui dépendent d'informations obtenues après connexion : `Match final`
> est évalué, `Match canonical` dépend de `CanonicalizeHostname`.

---

<a id="q14-6"></a>**[Q14.6](README.md#q14-6)** — *`Host *` placé avant `Host lab-web`.*

**Réponse : b)** `root`, la première valeur rencontrée gagne.

> [!NOTE]
> **Pourquoi**
>
> C'est la règle de lecture la plus contre-intuitive d'OpenSSH, et celle qui coûte
> le plus de temps aux débutants : `ssh_config` n'est pas un fichier où le plus
> précis l'emporte, ni un fichier où la dernière valeur écrase. **Pour chaque
> mot-clé, la première valeur rencontrée en descendant le fichier est retenue, et
> toutes les suivantes sont ignorées.**
>
> Le fichier se lit donc du plus spécifique au plus général, et `Host *` est
> toujours **le dernier bloc**. Un `Include` se place en général tout en haut,
> pour que les fragments spécifiques soient lus avant les réglages globaux.
>
> Vérification immédiate : `ssh -G lab-web | grep '^user'` → `user root`.

> [!WARNING]
> **Piège**
>
> Le même piège existe côté serveur, et il est plus grave : `/etc/ssh/sshd_config`
> sur Ubuntu 24.04 commence par `Include /etc/ssh/sshd_config.d/*.conf`. Les
> fragments sont donc lus **avant** tout le fichier principal et gagnent. C'est la
> raison pour laquelle un `PasswordAuthentication no` écrit à la main dans
> `sshd_config` reste sans effet sur une image cloud : le fragment
> `50-cloud-init.conf` a déjà positionné `yes`. Voir BF14.2.

---

<a id="q14-7"></a>**[Q14.7](README.md#q14-7)** — *`ControlMaster auto` + `ControlPath ~/.ssh/cm/%C` + `ControlPersist 10m`.*

**Réponse : a)** les sessions suivantes réutilisent la connexion et
l'authentification de la première.

> [!NOTE]
> **Pourquoi**
>
> La première connexion devient le **maître** : elle crée une socket UNIX au
> chemin donné par `ControlPath`. Les connexions suivantes vers le même triplet
> (utilisateur, hôte, port) détectent la socket, s'y branchent et ouvrent un
> simple **canal** supplémentaire dans la session TCP déjà chiffrée et déjà
> authentifiée.
>
> Ce qui est économisé à chaque connexion suivante : la poignée de main TCP,
> l'échange de clés (le plus cher, c'est de la cryptographie asymétrique), la
> vérification de `known_hosts`, et toute la phase d'authentification. En pratique
> on passe de 300–500 ms à 10–20 ms par commande. Sur une boucle de 30 machines
> avec 5 commandes chacune, la différence est de l'ordre de la minute.
>
> `ControlPersist 10m` garde le maître vivant 10 minutes après la fermeture de la
> dernière session : la commande suivante est instantanée même si tu as tout
> fermé. C'est exactement le mécanisme qu'Ansible active par défaut.

> [!WARNING]
> **Piège**
>
> c) décrit un vrai risque mais dans le mauvais sens : ce n'est pas la première
> session qui compte, c'est le **processus maître**. Avec `ControlPersist`, le
> maître se détache et survit à la session qui l'a créé. En revanche, tuer le
> maître (`ssh -O exit`, `kill`, reboot du poste) coupe bien **toutes** les
> sessions filles d'un coup.
>
> d) est faux et c'est important : `%C` est un condensat de (hôte local, hôte
> distant, port, utilisateur). Il existe précisément parce que la forme lisible
> `%r@%h:%p` produit des chemins qui dépassent la limite de longueur d'une socket
> UNIX (108 caractères sur Linux) dès que le nom d'hôte est long ou que le home est profond
> — erreur `ControlPath too long`.
>
> Deux autres pièges de production : le répertoire `~/.ssh/cm` doit exister
> (OpenSSH ne le crée pas) et être en `700` ; et un `ControlPath` partagé sur NFS
> ne fonctionne pas, les sockets UNIX ne traversent pas NFS.

---

<a id="q14-8"></a>**[Q14.8](README.md#q14-8)** — *`ForwardAgent yes` sur le bastion.*

**Réponses : b) et c)**

> [!NOTE]
> **Pourquoi**
>
> Le transfert d'agent ne copie rien : il crée sur la machine distante une socket
> UNIX et positionne `SSH_AUTH_SOCK` pour ta session. Toute demande de signature
> écrite dans cette socket remonte le tunnel jusqu'à **ton** agent, qui signe avec
> ta clé privée restée chez toi.
>
> Le problème n'est donc pas le vol de la clé, c'est l'**usage** de la clé.
> N'importe qui capable de lire cette socket — root sur le bastion, ou tout
> processus tournant sous ton compte s'il est compromis — peut demander des
> signatures en ton nom. Autrement dit : pendant toute la durée de ta session,
> root sur le bastion peut se connecter partout où ta clé est déployée, avec ton
> identité, sans laisser d'autre trace qu'une connexion normale de ta part. Et un
> bastion est par construction la machine la plus exposée du parc.
>
> `ProxyJump` (`-J`) répond au même besoin sans ce risque : `ssh` ouvre une
> connexion vers le bastion, y demande une simple redirection d'E/S
> (`-W hôte:port`), et établit **par-dessus** une seconde session SSH complète
> avec la machine finale. L'échange de clés et l'authentification de la session
> finale ont lieu entre ton poste et la machine finale, de bout en bout. Le
> bastion ne voit passer que des octets chiffrés qu'il ne peut pas déchiffrer, et
> ne touche jamais à ton agent.

> [!WARNING]
> **Piège**
>
> a) est l'erreur de compréhension la plus répandue, et elle conduit au mauvais
> raisonnement (« ma clé a une passphrase, donc je suis tranquille » : la
> passphrase protège le fichier, pas l'agent déverrouillé). d) est faux par
> nature : le risque ne vient pas d'une faille du bastion, il vient du modèle
> lui-même.
>
> Si tu ne peux vraiment pas éviter le transfert d'agent, deux atténuations :
> `ssh-add -c` (chaque signature demande une confirmation, tu vois donc les usages
> que tu n'as pas demandés) et `ForwardAgent` posé **par hôte**, jamais dans
> `Host *`.

---

<a id="q14-9"></a>**[Q14.9](README.md#q14-9)** — *`ssh lab-web "echo $HOSTNAME"`.*

**Réponse : b)** `lab-adm`.

> [!NOTE]
> **Pourquoi**
>
> Il y a deux niveaux d'interprétation et il faut savoir où l'on se trouve.
> Les guillemets **doubles** laissent le shell local développer `$HOSTNAME`
> **avant** que `ssh` ne soit lancé. La commande réellement transmise est donc
> `echo lab-adm`. Le serveur distant l'exécute et renvoie `lab-adm`.
>
> Pour que l'expansion ait lieu à distance, il faut des guillemets **simples** :
>
> ```console
> $ ssh lab-web 'echo $HOSTNAME'
> lab-web
> ```
>
> Mécanisme côté serveur : `sshd` ne découpe pas la commande lui-même, il la passe
> au shell de login du compte avec `-c`. C'est donc bien un shell distant qui fait
> l'expansion — mais un shell **non interactif et non login**, qui ne lit ni
> `~/.bashrc` (arrêté par la garde `case $- in *i*`), ni `~/.profile`. D'où les
> `command not found` classiques sur un `PATH` réduit.
>
> Astuce de lecture : s'il y a plusieurs arguments, `ssh` les **concatène avec des
> espaces** avant de les passer au shell distant. `ssh h echo a    b` envoie
> `echo a b`. Ce qui veut dire qu'un argument contenant des espaces doit être
> quoté **deux fois** :
> `ssh h "grep -r 'texte avec espaces' /etc"`.

> [!WARNING]
> **Piège**
>
> Le cas qui fait perdre une heure : `ssh h "rm -rf $DIR/*"`. Si `DIR` n'est pas
> défini localement, la commande transmise est `rm -rf /*`. Toujours vérifier avec
> `echo` d'abord, ou construire la commande avec des quotes simples et passer les
> valeurs par l'environnement : `ssh h "DIR='$DIR' bash -c 'rm -rf \$DIR/*'"` —
> ou, beaucoup plus lisible, `ssh h 'bash -s' <<< "..."`.

---

<a id="q14-10"></a>**[Q14.10](README.md#q14-10)** — *`sudo: a terminal is required` dans un script.*

**Réponse : c)** une règle `NOPASSWD` ciblée dans `sudoers`.

> [!NOTE]
> **Pourquoi**
>
> Trois façons de faire taire ce message, et une seule est correcte en
> automatisation.
>
> `-t` alloue un pseudo-terminal, ce qui permet à `sudo` de lire le mot de passe.
> Mais dans un script non interactif, il n'y a personne pour le taper : on a
> simplement remplacé une erreur immédiate par un blocage jusqu'au timeout. Et
> `-t` a des effets de bord notables : stdout et stderr sont fusionnés sur le même
> flux (impossible de les séparer), les fins de ligne deviennent `\r\n`, et `ssh`
> met le terminal local en mode brut. `-tt` force l'allocation même sans terminal
> local — c'est la rustine qu'on voit dans les pipelines, et elle rend la sortie
> inexploitable.
>
> La vraie réponse est de supprimer le besoin de mot de passe pour **cette
> commande précise** :
>
> ```text
> # /etc/sudoers.d/40-deploy-nginx
> %deploy ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx.service
> ```
>
> Un `NOPASSWD` limité à une commande complète et non paramétrable est une
> décision de sécurité assumée et auditée ; un `-tt` est un contournement qui
> laisse le script fragile. d) est à l'opposé de tout ce que fait ce module.

> [!WARNING]
> **Piège**
>
> `NOPASSWD: /usr/bin/systemctl restart *` est une porte ouverte : `systemctl`
> accepte `--host`, et bien d'autres sous-commandes. Une règle `sudoers` doit
> nommer la commande **et** ses arguments en entier. Et n'oublie pas que `-t`
> reste le bon choix en **interactif** : `ssh -t lab-web 'sudo journalctl -u
> nginx -f'` fonctionne bien, le pager et les couleurs aussi.

---

<a id="q14-11"></a>**[Q14.11](README.md#q14-11)** — *Joindre `10.10.10.12:5432` à travers le bastion.*

**Réponse : b)** `ssh -L 15432:10.10.10.12:5432 mathieu@10.10.10.10`.

> [!NOTE]
> **Pourquoi**
>
> La syntaxe de `-L` se lit dans cet ordre :
> `-L [adresse_locale:]port_local:hôte_cible:port_cible`.
>
> Le point qui piège tout le monde : **`hôte_cible` est résolu et joint depuis le
> serveur SSH**, pas depuis ton poste. C'est le serveur qui ouvre la connexion TCP
> finale vers `10.10.10.12:5432`. Le tunnel a donc exactement le même pouvoir
> d'accès réseau que le bastion lui-même.
>
> Le flux complet :
>
> ```text
> ton client SQL -> 127.0.0.1:15432 (ton poste)
>                      | canal chiffré dans la session SSH
>                   lab-adm (10.10.10.10)
>                      | connexion TCP en clair sur le réseau de lab
>                   lab-db:5432
> ```
>
> a) est le cas où la cible est le serveur SSH lui-même : `127.0.0.1` y désigne la
> boucle locale **du bastion**, donc un PostgreSQL qui tournerait sur `lab-adm`.
> b) inverse le sens (`-R` ouvre le port sur le serveur). d) ouvre un proxy SOCKS,
> ce qui suppose déjà de pouvoir joindre `lab-db` en SSH.

> [!WARNING]
> **Piège**
>
> Par défaut le port local n'est ouvert que sur `127.0.0.1` : ta collègue sur le
> réseau ne pourra pas s'y connecter. Pour l'ouvrir à la machine entière, c'est côté **client** que ça se décide : adresse de bind explicite (
> `-L 0.0.0.0:15432:...` ) ou `-g` ( `GatewayPorts yes` dans `ssh_config` — même nom que la
> directive serveur qui gouverne `-R`, mais autre fichier). À n'utiliser qu'en connaissance de cause : tu viens de créer un
> accès à ta base sans authentification pour tout le monde sur ton réseau.

---

<a id="q14-12"></a>**[Q14.12](README.md#q14-12)** — *`-R 8080:127.0.0.1:3000` et `Connection refused` depuis une autre machine.*

**Réponse : b)** le port distant n'écoute que sur la boucle locale tant que
`GatewayPorts` n'est pas activé.

> [!NOTE]
> **Pourquoi**
>
> C'est le pendant serveur du piège précédent. `sshd` refuse par défaut d'ouvrir
> un port de redirection inverse sur toutes les interfaces : `GatewayPorts no` est
> le défaut, et le port 8080 n'est alors lié qu'à `127.0.0.1` sur `lab-ops`. Un
> `ss -tlnp` sur `lab-ops` le montre :
>
> ```console
> $ ss -tlnp | grep 8080
> LISTEN 0  128  127.0.0.1:8080  0.0.0.0:*
> ```
>
> Depuis `lab-ops` lui-même, `curl http://127.0.0.1:8080/` fonctionne. Depuis
> ailleurs, le paquet arrive sur l'interface `10.10.10.14` où rien n'écoute : la
> pile TCP renvoie un RST, d'où `Connection refused`.
>
> Pour ouvrir, deux valeurs possibles côté serveur :
> `GatewayPorts yes` (le port est lié à `0.0.0.0`, sans discussion) ou
> `GatewayPorts clientspecified`, plus fin : le client choisit l'adresse de bind
> avec `-R 0.0.0.0:8080:127.0.0.1:3000` ou `-R 10.10.10.14:8080:...`.

> [!WARNING]
> **Piège**
>
> Ce n'est pas un détail de confort, c'est une décision de sécurité : un port de
> redirection inverse ouvert sur toutes les interfaces expose un service interne,
> sans authentification ni journalisation, à tout le réseau — et il survit tant
> que la session SSH tient. C'est le mécanisme qu'utilisent les logiciels
> malveillants pour se ménager un accès entrant depuis une machine qui n'accepte
> que du sortant. Sur un serveur de production, la bonne valeur est `no`, et les
> exceptions se traitent par un vrai reverse proxy.

---

<a id="q14-13"></a>**[Q14.13](README.md#q14-13)** — *`Too many authentication failures` avec 8 clés dans l'agent.*

**Réponses : a) et c)**

> [!NOTE]
> **Pourquoi**
>
> Le serveur compte les **tentatives d'authentification**, pas les échecs
> « humains ». Or chaque clé proposée par le client compte pour une tentative :
> `ssh` envoie une requête `publickey` par identité connue, dans l'ordre, jusqu'à
> ce que le serveur en accepte une. Avec 8 clés dans l'agent et
> `MaxAuthTries 6` (le défaut), la session est coupée avant même d'arriver à la
> bonne clé — même si elle est la neuvième et qu'elle est parfaitement valide.
>
> D'où le symptôme déroutant : « ma clé marche pourtant, je la vois dans
> `ssh-add -l` ». Le `ssh -v` le montre noir sur blanc, une ligne
> `Offering public key:` par tentative.
>
> Les deux corrections agissent au même endroit — réduire le nombre d'identités
> proposées :
>
> * `IdentitiesOnly=yes` avec `-i` : `ssh` ne propose **que** la clé nommée, et
>   ignore tout ce que l'agent contient par ailleurs. C'est la bonne réponse
>   durable, à poser par hôte dans `~/.ssh/config`.
> * `ssh-add -D` purge l'agent, puis on recharge la seule clé utile.

> [!WARNING]
> **Piège**
>
> Le piège de a) : `-i` **seul** ne suffit pas. Sans `IdentitiesOnly=yes`, `-i`
> ajoute la clé à la liste, mais `ssh` propose d'abord les identités de l'agent (dans l'ordre de l'agent) et seulement
> ensuite les fichiers qui n'y sont pas — ce que découvre l'apprenant en BF14.4. C'est contre-intuitif et c'est
> documenté : `IdentityFile` est additif, `IdentitiesOnly` est ce qui le rend
> exclusif.
>
> b) traite le symptôme sur le serveur et affaiblit une protection contre le
> bourrinage. d) désinstalle la méthode d'authentification qui doit réussir.

---

<a id="q14-14"></a>**[Q14.14](README.md#q14-14)** — *`Connection refused` contre `Connection timed out`.*

**Réponse : b)** `lab-web` répond mais rien n'écoute sur 22 ; `lab-db` ne répond
pas du tout.

> [!NOTE]
> **Pourquoi**
>
> La distinction est purement TCP et elle oriente tout le diagnostic :
>
> * **`Connection refused`** : ton `SYN` est arrivé, la machine a répondu par un
>   `RST`. Il y a donc quelqu'un au bout du fil, la couche réseau et le routage
>   sont bons. Causes : `sshd` arrêté ou en échec, `sshd` qui écoute sur un autre
>   port, mauvaise `ListenAddress`, ou un filtre configuré en `REJECT`.
> * **`Connection timed out`** : aucune réponse, le client a réémis puis
>   abandonné. Causes : machine éteinte, mauvaise IP, problème de routage ou de
>   VLAN, ou un filtre en `DROP` (le mode par défaut d'un pare-feu bien réglé).
>
> Séquence de tri, dans l'ordre :
>
> ```bash
> ping -c2 10.10.10.11              # la machine répond-elle ?
> nc -vz 10.10.10.11 22             # le port répond-il ? refused ou timeout ?
> ssh -v 10.10.10.11                # où ça bloque exactement
> # et sur la machine, par la console :
> systemctl status ssh ; ss -tlnp '( sport = :22 )'
> ```
>
> Retenir la formule d'entretien : **`refused` est une réponse, `timeout` est un
> silence.** Un silence est presque toujours un filtrage ou une erreur d'adresse.

> [!WARNING]
> **Piège**
>
> Sur Ubuntu 24.04, `sshd` est démarré par activation de socket. `systemctl status
> ssh` peut afficher `inactive (dead)` alors que tout fonctionne : c'est
> `ssh.socket` qui écoute et qui lance `ssh.service` à la première connexion.
> Regarde `systemctl status ssh.socket` et `ss -tlnp` avant de conclure que le
> service est arrêté.

---

<a id="q14-15"></a>**[Q14.15](README.md#q14-15)** — *`PasswordAuthentication no` sans effet.*

**Réponse : b)** `sshd -T | grep -i passwordauthentication`.

> [!NOTE]
> **Pourquoi**
>
> `sshd -T` imprime la configuration **effective** : après lecture du fichier
> principal, de tous les `Include`, et application des valeurs par défaut. C'est
> la seule source de vérité. Une ligne, une réponse :
>
> ```console
> # sshd -T | grep -i passwordauthentication
> passwordauthentication yes
> ```
>
> À partir de là tu sais qu'il y a un autre fichier, et `grep -r` (réponse a)
> devient utile pour le **localiser** — dans l'ordre inverse de ce qu'on fait
> d'habitude : on constate d'abord l'effet, on cherche la cause ensuite. Le
> coupable habituel sur une image cloud Ubuntu :
>
> ```console
> # grep -r PasswordAuthentication /etc/ssh/
> /etc/ssh/sshd_config:PasswordAuthentication no
> /etc/ssh/sshd_config.d/50-cloud-init.conf:PasswordAuthentication yes
> ```
>
> Comme `Include /etc/ssh/sshd_config.d/*.conf` est la **première** ligne utile de
> `sshd_config` et que la première valeur gagne, le `yes` du fragment l'emporte.

> [!WARNING]
> **Piège**
>
> Deuxième cause classique, indépendante de la première : `PasswordAuthentication
> no` ne coupe pas la méthode `keyboard-interactive`. Avec `UsePAM yes` et
> `KbdInteractiveAuthentication yes`, PAM redemande le mot de passe par un autre
> chemin et l'utilisateur ne voit aucune différence. Pour vraiment couper le mot
> de passe, il faut les deux :
>
> ```text
> PasswordAuthentication no
> KbdInteractiveAuthentication no
> ```
>
> Contrôle : `ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no
> mathieu@lab-web` doit répondre `Permission denied (publickey)` sans jamais
> afficher d'invite.

---

<a id="q14-16"></a>**[Q14.16](README.md#q14-16)** — *Valider avant `reload`.*

**Réponse : b)** `sshd -t`.

> [!NOTE]
> **Pourquoi**
>
> `sshd -t` (*test mode*) analyse la configuration, vérifie la syntaxe, contrôle
> les permissions et l'existence des clés d'hôte, puis sort : 0 si tout va bien,
> non nul avec le fichier et le numéro de ligne sinon.
>
> ```console
> # sshd -t
> /etc/ssh/sshd_config.d/60-durcissement.conf: line 7: Bad configuration
> option: AllowGrups
> ```
>
> C'est le réflexe à automatiser :
>
> ```bash
> sudo sshd -t && sudo systemctl reload ssh
> ```
>
> Sans le `&&`, une faute de frappe dans une directive fait échouer le démarrage
> de `sshd`. Sur Ubuntu, `systemctl` `reload` `ssh` lance lui-même `sshd -t` (`ExecReload`) et refuse de recharger; sous Rocky, le `SIGHUP` fait se ré- exécuter `sshd`, qui meurt sur la configuration invalide : plus aucune nouvelle connexion, seules les sessions ouvertes survivent. Et si la faute passe inaperçue, au prochain
> redémarrage de la machine, plus de SSH — l'incident se déclare des semaines
> plus tard, sans lien apparent avec ta modification.
>
> `sshd -T` est le complément : il affiche la configuration effective, mais c'est
> un outil d'inspection, pas de validation (il sort aussi en erreur sur une
> syntaxe invalide, mais il déverse tout le reste au passage).

> [!WARNING]
> **Piège**
>
> `sshd -t` ne détecte que les erreurs de **syntaxe et de cohérence locale**. Il
> ne te dira jamais que ton `AllowUsers` exclut ton propre compte, que le groupe
> cité dans `AllowGroups` n'existe pas encore, ou que tu viens de couper la seule
> méthode d'authentification dont tu disposes. Aucun outil ne remplace la règle
> d'or : une session ouverte pendant le test.
>
> Sur Ubuntu 24.04, `ssh.service` exécute déjà `sshd -t` en `ExecStartPre` : un
> `systemctl restart` avec une configuration invalide échoue proprement au lieu de
> laisser la machine sans SSH. Ne compte pas là-dessus pour autant sous Rocky.

---

<a id="q14-17"></a>**[Q14.17](README.md#q14-17)** — *`Port 2222` sans effet sur Ubuntu 24.04.*

**Réponse : b)** `sshd` est lancé par activation de socket.

> [!NOTE]
> **Pourquoi**
>
> Depuis Ubuntu 22.10, le paquet `openssh-server` installe et active
> `ssh.socket` : c'est systemd qui ouvre et détient le port 22, et qui lance
> `ssh.service` à la première connexion entrante, en lui transmettant le socket déjà ouvert (prise en charge de l'activation par socket ajoutée par Ubuntu à `sshd`). Dans
> ce mode, `sshd` n'ouvre plus lui-même ses ports : un `reload` (ou un `restart` de `ssh.service`) ne change pas l'écoute. Sur 24.04, un générateur systemd ( `sshd``-socket-generator`) traduit `Port` et `ListenAddress` de `sshd_config` en un drop-in de `ssh.` socket — mais seulement au prochain `systemctl daemon-reload`.
>
> Diagnostic :
>
> ```console
> $ systemctl is-enabled ssh.socket
> enabled
> $ systemctl cat ssh.socket | grep ListenStream
> ListenStream=22
> ```
>
> Deux solutions, selon ce qu'on veut :
>
> ```bash
> # 1. rester en activation de socket (méthode Ubuntu 24.04) :
> #    Port 2222 dans sshd_config, puis régénérer l'unité socket
> sudo sshd -t
> sudo systemctl daemon-reload && sudo systemctl restart ssh.socket
> ss -tlnp | grep 2222
>
> # 2. revenir à un sshd démon classique, qui relit Port
> sudo systemctl disable --now ssh.socket
> sudo systemctl enable --now ssh.service
> ```
>
> Sur une version sans ce générateur (22.10), on surchargeait l'unité à la main (`systemctl edit ssh.socket` : `ListenStream=` vide puis `ListenStream=2222`) ; la ligne vide est obligatoire, sans elle on **ajoute** un port
> au lieu de le remplacer et le 22 reste ouvert.

> [!WARNING]
> **Piège**
>
> Ce comportement explique aussi pourquoi `systemctl status ssh` affiche parfois
> `inactive (dead)` sur une machine parfaitement joignable : tant que personne ne s'est connecté depuis le démarrage, seul `ssh.socket` est actif; la première connexion démarre `ssh.` service, qui reste ensuite en place. Sous Rocky 9, rien de tout cela : `sshd.service` est un démon
> classique et `Port` fonctionne comme attendu — avec en revanche SELinux à
> prévenir : `semanage port -a -t ssh_port_t -p tcp 2222`.

---

<a id="q14-18"></a>**[Q14.18](README.md#q14-18)** — *`restrict,from=...,command=...` dans `authorized_keys`.*

**Réponse : b)** la commande forcée est exécutée, la commande demandée est
disponible dans `$SSH_ ORIGINAL_COMMAND`.

> [!NOTE]
> **Pourquoi**
>
> `command="..."` est une **commande forcée**, pas un défaut. Quand cette clé est
> utilisée, `sshd` exécute exclusivement la commande indiquée, quoi que le client
> demande — y compris si le client ne demande rien (session interactive). Ce que
> le client avait demandé n'est pas perdu pour autant : il est placé dans la
> variable d'environnement `SSH_ ORIGINAL_COMMAND`, ce qui permet d'écrire un
> aiguilleur :
>
> ```bash
> #!/usr/bin/env bash
> set -euo pipefail
> case "${SSH_ORIGINAL_COMMAND:-}" in
>   liste)        ls -1 /srv/sauvegarde ;;
>   "depot "*)    cat > "/srv/sauvegarde/${SSH_ORIGINAL_COMMAND#depot }" ;;
>   *) echo "commande refusée" >&2
>      logger -t lab14 "refus: ${SSH_ORIGINAL_COMMAND:-<interactif>}"
>      exit 42 ;;
> esac
> ```
>
> `restrict` coupe en un mot toutes les fonctions annexes : allocation de
> terminal, redirections de port, transfert d'agent, X11, exécution de
> `~/.ssh/rc`. On réactive ensuite au cas par cas (`pty`, `port-forwarding`).
> C'est plus sûr que d'énumérer les `no-*` : une option ajoutée dans une future
> version d'OpenSSH sera interdite par défaut au lieu d'être autorisée par oubli.
>
> `from="10.10.10.14"` limite l'usage de la clé à une origine : une clé volée ne
> sert à rien depuis ailleurs. `sshd` compare l'adresse source réelle de la
> connexion, pas une information fournie par le client.

> [!WARNING]
> **Piège**
>
> Deux erreurs qui vident la protection de son sens :
>
> * le script de commande forcée qui fait
>   `eval "$SSH_ORIGINAL_COMMAND"` « pour plus de souplesse » : on vient de
>   redonner un shell complet à la clé. La validation doit être une liste blanche
>   (`case ... esac`), jamais un `eval`.
> * oublier que `command=` ne protège pas du transfert de port : sans `restrict`
>   ni `no-port-forwarding`, le client peut ouvrir un tunnel **sans jamais
>   exécuter la commande forcée**, avec `ssh -N -L ...`. Le tunnel est établi
>   pendant la phase de session, indépendamment de la commande.

---

## 14.4 Quiz — questions ouvertes

<a id="qo14-1"></a>**[QO14.1](README.md#qo14-1)** — *Ce qui se passe entre `ssh lab-web` et le prompt distant.*

**Réponse**

**Phase 0 — avant tout paquet SSH.** `ssh` lit `~/.ssh/config`, les `Include`,
puis `/etc/ssh/ssh_config`, résout l'alias `lab-web` en `HostName`, `User`,
`Port`, `IdentityFile`, `ProxyJump`. Tout cela est visible avec `ssh -G lab-web`.
Puis résolution DNS (ou `/etc/hosts`) et connexion TCP sur le port 22.

**Phase 1 — transport.** Échange des bannières de version en clair
(`SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.5`), puis `KEXINIT` : chaque camp
annonce ses algorithmes d'échange de clés, de chiffrement, de MAC et de
compression, dans son ordre de préférence. On retient le premier commun. Suit
l'échange de clés proprement dit (aujourd'hui `sntrup761x25519-sha512` ou
`curve25519-sha256`), qui produit un secret partagé dont sont dérivées les clés
symétriques de session — différentes dans chaque sens. À partir du `NEWKEYS`,
tout est chiffré et authentifié.

**Phase 2 — identité de l'hôte.** L'échange de clés est **signé par le serveur
avec sa clé d'hôte privée** (`/etc/ssh/ssh_host_ed25519_key`). Le client vérifie
cette signature avec la clé publique reçue, ce qui prouve que le serveur détient
bien la clé d'hôte. Reste à savoir si cette clé est celle attendue : le client
cherche l'empreinte dans `~/.ssh/known_hosts` puis `/etc/ssh/ssh_known_hosts`.
Absente → question `yes/no/[fingerprint]` (TOFU). Présente et différente →
`REMOTE HOST IDENTIFICATION HAS CHANGED`, refus.

**Phase 3 — authentification.** Le client demande le service `ssh-userauth`. Le
serveur annonce les méthodes acceptées (`publickey,password`). En `publickey`, le
client envoie d'abord la **clé publique** seule, pour demander « celle-ci
t'intéresse-t-elle ? » — ça évite de faire signer inutilement. Si le serveur
répond oui, le client construit un blob contenant l'**identifiant de session**
(dérivé de l'échange de clés, donc unique à cette connexion), le nom
d'utilisateur et la clé publique, et le **signe** avec la clé privée — ou fait
signer par l'agent. Le serveur vérifie la signature avec la clé publique trouvée
dans `authorized_keys`.

**Phase 4 — session.** Ouverture d'un canal, demande de pseudo-terminal, `shell`
ou `exec`, et le prompt apparaît.

> [!NOTE]
> **Pourquoi**
>
> Ce qui circule à la phase 3 est **une signature**, jamais la clé privée. Et
> comme le blob signé contient l'identifiant de session, la signature est liée à
> cette connexion précise : elle ne peut pas être rejouée ailleurs. C'est la
> propriété qui rend l'authentification par clé immune au rejeu, contrairement à
> un mot de passe qui, lui, est transmis tel quel dans le tunnel et arrive en
> clair dans la mémoire du serveur.
>
> C'est aussi ce qui explique le fonctionnement de l'agent : l'agent ne rend jamais
> la clé privée, il rend des signatures. Un client qui a accès à l'agent peut donc
> faire signer ce qu'il veut, mais ne repartira pas avec la clé.

> [!WARNING]
> **Piège**
>
> Erreur fréquente en entretien : dire que le serveur « chiffre un défi avec la
> clé publique et le client le déchiffre ». C'était le fonctionnement du protocole
> SSH-1, abandonné depuis 1999. En SSH-2 c'est une **signature**, pas un
> chiffrement — ce qui est d'ailleurs indispensable, puisque `ed25519` est un
> algorithme de signature qui ne sait pas chiffrer.

---

<a id="qo14-2"></a>**[QO14.2](README.md#qo14-2)** — *Clé contre mot de passe, en entretien.*

**Réponse**

Trois arguments, dans cet ordre :

1. **Rien de réutilisable ne traverse.** Le mot de passe est transmis (dans le
   tunnel, certes) et arrive en clair côté serveur : un serveur compromis le
   capture et il est valable ailleurs, puisque les gens les réutilisent. Avec une
   clé, le serveur ne reçoit qu'une signature liée à l'identifiant de session :
   inutilisable pour se connecter ailleurs, inutilisable une seconde fois.
2. **Le secret ne bouge pas.** La clé privée reste sur le poste, chiffrée par une
   passphrase. Le serveur ne détient que la clé publique.
3. **Résistance au bourrinage.** Une clé de 256 bits ne se devine pas. Un mot de
   passe, même bon, se teste — et les journaux d'un serveur exposé montrent des
   milliers de tentatives par jour.

« Ma clé privée part-elle sur le serveur ? » Non, jamais. Ce qu'on dépose sur le
serveur est le fichier `.pub` — c'est exactement ce que fait `ssh-copy-id`.

« Si quelqu'un vole mon `authorized_keys` ? » Il n'a rien gagné : ce fichier ne
contient que des clés publiques. Le pire qu'il puisse en tirer, c'est
l'information « ces identités-là ont accès à ce compte ». En revanche, s'il peut
**écrire** dedans, il ajoute sa propre clé et devient toi : c'est toute la raison
d'être de `StrictModes` et des permissions `700`/`600`.

> [!NOTE]
> **Pourquoi**
>
> Le bon réflexe d'entretien est de distinguer les trois secrets en jeu : la clé
> privée (chez toi, chiffrée), la clé publique (partout, sans valeur), la
> passphrase (dans ta tête, protège le fichier de clé au repos). La passphrase ne
> protège **pas** une session en cours ni un agent déverrouillé — d'où `ssh-add -t`
> pour borner la durée de vie, et `ssh-add -c` pour les clés sensibles.

> [!WARNING]
> **Piège**
>
> Deux nuances qui font la différence entre une réponse correcte et une bonne
> réponse :
>
> * une clé sans passphrase sur un poste de travail est **moins** sûre qu'un bon
>   mot de passe : n'importe quel processus qui lit ton `$HOME` repart avec un
>   accès permanent à tout le parc. La clé sans passphrase n'a de sens que pour un
>   compte de service, sur une machine dont on maîtrise l'accès, et compensée par
>   `from=` et `command=`.
> * la clé ne résout pas la **révocation** : retirer l'accès à un partant, c'est
>   aller retirer sa clé publique dans le `authorized_keys` de chaque compte de
>   chaque machine. C'est la faiblesse structurelle que les certificats SSH
>   corrigent (voir QO14.9).

---

<a id="qo14-3"></a>**[QO14.3](README.md#qo14-3)** — *`ForwardAgent` sur les bastions, en entretien.*

**Réponse**

« Je ne l'active pas, et voici pourquoi, concrètement. »

**Qui peut faire quoi.** Le transfert d'agent crée sur le bastion une socket
UNIX (`/tmp/ssh-XXXX/agent.NNNN`) et positionne `SSH_AUTH_SOCK` dans ma session.
Tout ce qui peut lire cette socket peut demander une signature à **mon** agent,
sur ma machine, avec ma clé. Concrètement : root sur le bastion, et tout
processus tournant sous mon compte sur le bastion.

**Pendant combien de temps.** Tant que ma session est ouverte. Un attaquant ayant
root sur le bastion n'a même pas besoin d'agir vite : il lui suffit d'attendre
qu'un administrateur se connecte, puis d'utiliser sa socket pour se propager
partout où cette clé est déployée. Et la trace laissée est une connexion
parfaitement normale, avec mon identité et mon empreinte de clé dans les
journaux — ce qui m'incrimine.

**L'alternative.** `ProxyJump` :

```text
Host lab-db
    HostName 10.10.10.12
    ProxyJump bastion
```

Ce qui change dans le chemin : `ssh` ouvre une session vers le bastion et lui
demande uniquement une redirection d'E/S vers `10.10.10.12:22` (mécanisme
`-W hôte:port`). Par-dessus ce tuyau d'octets, il établit une **seconde session
SSH complète** avec `lab-db` : échange de clés, vérification de la clé d'hôte de
`lab-db`, authentification par ma clé — le tout de bout en bout entre mon poste
et `lab-db`. Le bastion transporte des octets qu'il ne peut pas déchiffrer, et
ne voit jamais mon agent.

Bénéfice secondaire souvent oublié : avec `ProxyJump`, `known_hosts` sur mon
poste contient bien la clé d'hôte de `lab-db`, donc **je** vérifie l'identité de
la machine finale. Avec un rebond manuel (`ssh bastion` puis `ssh lab-db`), c'est
le bastion qui la vérifie, avec son propre `known_hosts` que je ne contrôle pas.

> [!NOTE]
> **Pourquoi**
>
> Le point à faire passer : le risque n'est pas le vol de la clé, c'est
> l'**usage** de la clé. Beaucoup répondent « ma clé a une passphrase, donc c'est
> bon » — la passphrase protège le fichier au repos, pas un agent déverrouillé qui
> signe à la demande.

> [!WARNING]
> **Piège**
>
> Si le transfert d'agent est vraiment imposé (un outil qui ne sait pas faire
> autrement), les atténuations acceptables sont : `ssh-add -c` (chaque signature
> demande une confirmation explicite, donc les usages non sollicités deviennent
> visibles), une clé dédiée à durée de vie courte (`ssh-add -t 900`), et
> `ForwardAgent yes` posé **uniquement** dans le bloc de l'hôte concerné, jamais
> dans `Host *`. Et côté serveur, `AllowAgentForwarding no` sur tout ce qui n'en a
> pas strictement besoin.

---

<a id="qo14-4"></a>**[QO14.4](README.md#qo14-4)** — *Trois causes légitimes de changement de clé d'hôte, et la procédure.*

**Réponse**

Causes légitimes, par fréquence décroissante :

1. **Réinstallation ou reconstruction de la VM.** Les clés d'hôte sont générées
   à la première installation du paquet ; une VM recréée depuis un modèle en
   obtient de nouvelles. C'est le cas dominant dans un parc infrastructure-as-code.
2. **Réattribution d'adresse IP.** Le `known_hosts` est indexé par nom **et** par
   adresse. Une IP de DHCP ou de pool cloud récupérée par une autre machine
   provoque exactement le même message, alors que rien n'a été touché.
3. **Régénération volontaire des clés** (`ssh-keygen -A` après un clonage de VM :
   deux machines qui partagent la même clé d'hôte, c'est un défaut à corriger),
   ou restauration d'une sauvegarde système antérieure à une régénération.

À quoi s'ajoutent deux cas particuliers : un répartiteur de charge devant
plusieurs machines SSH aux clés différentes (le message apparaît une fois sur
deux), et le passage par un rebond différent.

Procédure de tri :

```bash
# 1. ce que je connais
ssh-keygen -F lab-web              # l'entrée enregistrée, avec son empreinte
# 2. ce qu'on me présente maintenant  (information, pas décision)
ssh-keyscan -t ed25519 10.10.10.11 | ssh-keygen -lf -
# 3. LA VÉRITÉ, par un canal qui n'est pas SSH vers cette machine :
#    console Proxmox de lab-web ->
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Si l'empreinte de l'étape 3 est égale à celle de l'étape 2 : le changement est
réel et légitime, je mets à jour (`ssh-keygen -R lab-web` puis reconnexion avec
vérification de l'empreinte, ou mise à jour du `known_hosts` de référence de
l'équipe). Si elles diffèrent : quelqu'un s'interpose entre moi et la machine —
je ne me connecte pas, je préviens, j'ouvre un incident.

> [!NOTE]
> **Pourquoi**
>
> La clé de la démarche est le mot **hors bande**. Vérifier l'empreinte avec
> `ssh-keyscan` ne prouve rien : si un attaquant s'interpose, il répondra à
> `ssh-keyscan` exactement comme il a répondu à `ssh`. Le canal de vérification
> doit être indépendant du canal attaqué : console de l'hyperviseur, inventaire
> d'un outil de gestion de configuration, enregistrement SSHFP dans un DNS signé,
> ou un appel téléphonique à la personne qui a réinstallé la machine.

> [!WARNING]
> **Piège**
>
> Le vrai problème d'un parc qui voit ce message une fois par semaine n'est pas le
> message : c'est que les équipes ont pris l'habitude de faire `ssh-keygen -R` sans
> réfléchir. L'alerte ne protège plus personne. La correction structurelle est de
> faire signer les clés d'hôte par une CA SSH et de poser une seule ligne
> `@cert-authority *.lab.local ssh-ed25519 AAAA...` dans `known_hosts` : une VM
> reconstruite reçoit un nouveau certificat signé par la même CA, et aucun client
> ne bronche.

---

<a id="qo14-5"></a>**[QO14.5](README.md#qo14-5)** — *Démarche de diagnostic d'un `Permission denied (publickey)`.*

**Réponse**

Principe directeur : le client ne sait rien, le serveur sait tout. On commence
par la partie qu'on voit, puis on va lire le journal du serveur — et on garde
une session déjà ouverte ou la console pour y accéder.

**Côté client (2 minutes)**

```bash
ssh -G lab-ops | grep -E '^(user|hostname|port|identityfile|identitiesonly)'
```
On cherche : le bon utilisateur ? la bonne machine ? la bonne clé ? Une faute
d'utilisateur est la cause n°1 et ne coûte rien à écarter.

```bash
ssh -v lab-ops 2>&1 | grep -E 'Offering|Will attempt|Authentications that'
```
On cherche : `Offering public key:` apparaît-il ? Si non, aucune clé n'est
proposée — la clé n'est pas trouvée, pas lisible, ou ses permissions sont
mauvaises (chercher alors `UNPROTECTED PRIVATE KEY FILE` plus haut dans la
sortie). Si `Offering` apparaît et que la ligne suivante est
`Authentications that can continue: publickey`, la clé a été proposée et
refusée : le problème est côté serveur.

```bash
ssh-add -l          # l'agent contient-il la clé ? (empreinte à comparer)
ssh-keygen -lf ~/.ssh/id_ed25519.pub
ls -ld ~ ~/.ssh ~/.ssh/id_ed25519
```

**Côté serveur (l'essentiel)**

```bash
sudo journalctl -u ssh -n 50 --no-pager
```
Les messages à reconnaître, et leur cause :

| Message journal | Cause |
|---|---|
| `Authentication refused: bad ownership or modes for ...` | permissions |
| `User mathieu from ... not allowed because not` |  |
| `listed in AllowUsers` | filtrage de comptes |
| `Invalid user mathieu from 10.10.10.10` | le compte n'existe pas |
| `Connection closed by authenticating user ... [preauth]` | aucune clé n'a convenu |
| `error: maximum authentication attempts exceeded` |  |
| `for mathieu ...` | `MaxAuthTries` |

Puis :

```bash
sudo sshd -T | grep -Ei 'pubkeyauth|authorizedkeysfile|allowusers|allowgroups'
sudo ls -ld /home/dev /home/dev/.ssh /home/dev/.ssh/authorized_keys
sudo ssh-keygen -lf /home/dev/.ssh/authorized_keys   # les empreintes présentes
```

La dernière commande est celle qui tranche : elle donne les empreintes des clés
réellement autorisées, à comparer avec celle du client. C'est plus fiable qu'un
`diff` visuel sur des lignes de 700 caractères.

> [!NOTE]
> **Pourquoi**
>
> Les causes, classées par fréquence réelle en exploitation :
>
> 1. mauvais utilisateur (`ssh lab-ops` au lieu de `ssh dev@lab-ops`) ;
> 2. permissions du home, de `~/.ssh` ou de `authorized_keys` côté serveur —
>    typiquement après une restauration de sauvegarde ou un `cp -r` d'un home ;
> 3. la clé n'est pas dans `authorized_keys` (ou y est avec un retour à la ligne
>    au milieu : une clé publique est **une seule ligne**) ;
> 4. `AllowUsers`/`AllowGroups` qui ne couvre pas le compte ;
> 5. trop d'identités proposées, `MaxAuthTries` atteint ;
> 6. `AuthorizedKeysFile` redéfini ailleurs (fréquent avec un outil de gestion
>    centralisée : `/etc/ssh/authorized_keys/%u`).
>
> `LogLevel VERBOSE` change la vie ici : le journal affiche l'empreinte de la clé
> proposée, ce qui permet de dire immédiatement « ce n'est pas la clé que tu
> crois ».

> [!WARNING]
> **Piège**
>
> Ne pas confondre `Permission denied (publickey)` et
> `Permission denied (publickey,password)`. La liste entre parenthèses est celle
> des méthodes que le serveur **acceptait encore**. S'il n'y a que `publickey`,
> l'authentification par mot de passe est désactivée : inutile de chercher un
> problème de mot de passe. Si la liste contient `password` et qu'aucune invite
> n'est apparue, c'est le **client** qui n'a pas essayé — regarde
> `PreferredAuthentications` et `PasswordAuthentication` dans `ssh -G`.

---

<a id="qo14-6"></a>**[QO14.6](README.md#qo14-6)** — *Mécanisme, gains et pièges du multiplexage.*

**Réponse**

**Mécanisme.** Avec `ControlMaster auto`, la première connexion vers un triplet
(utilisateur, hôte, port) s'établit normalement et crée en plus une socket UNIX
locale au chemin `ControlPath`. Les connexions suivantes vers le même triplet
détectent cette socket, s'y branchent et demandent au maître d'ouvrir un
**canal** supplémentaire dans la session SSH existante. Le protocole SSH-2 est
multi-canaux par construction : c'est le même mécanisme qui permet d'avoir un
shell, un `scp` et un tunnel dans une seule session.

Ce qui est économisé par connexion suivante : poignée de main TCP, `KEXINIT`,
échange de clés asymétrique, vérification de `known_hosts`, phase
d'authentification. Il ne reste qu'une ouverture de canal.

**Gains mesurables.**

```console
$ time ( for i in $(seq 5); do ssh -o ControlMaster=no lab-web true; done )
real    0m2,148s
$ time ( for i in $(seq 5); do ssh lab-web true; done )
real    0m0,271s
```

Facteur 8 à 20 selon la latence. C'est décisif pour tout ce qui lance beaucoup
de petites connexions : boucles d'administration, `rsync` répétés, Ansible (qui
active le multiplexage par défaut), pipelines de CI.

**Trois pièges réels.**

1. **Point unique de défaillance.** Tuer le maître (ou perdre le réseau) coupe
   d'un coup toutes les sessions filles, y compris le `tail -f` d'un collègue.
   Et `ControlPersist` laisse traîner un processus `ssh` après la fermeture de
   ton terminal : `ssh -O check`, `ssh -O exit` font partie du vocabulaire.
2. **Longueur du chemin de socket.** Une socket UNIX est limitée à 108
   caractères sur Linux. `ControlPath ~/.ssh/cm/%r@%h:%p` explose avec des noms d'hôtes
   longs : d'où `%C`, un condensat de taille fixe. Le répertoire doit exister
   (OpenSSH ne le crée pas) et être en `700` — quiconque peut écrire dedans peut
   détourner la socket. Et ça ne fonctionne pas sur un home monté en NFS.
3. **Effets de bord invisibles.** Les options d'une connexion sont celles du
   **maître** : ouvrir un premier `ssh` sans `-A`, puis un second `ssh -A`, ne
   donne pas d'agent transféré — la seconde session réutilise le maître. Même
   chose pour `-X`. Il faut alors `-o ControlMaster=no`. À l'inverse, un `-L` ou `-D` demandé par une session fille est confié au maître et lui survit (`ssh -O forward` / `ssh -O cancel` pour les gérer à chaud).

> [!NOTE]
> **Pourquoi**
>
> Le point conceptuel à retenir : le multiplexage ne rend pas SSH plus rapide, il
> **supprime les connexions**. Tout le coût d'une connexion SSH est dans son
> établissement (cryptographie asymétrique + allers-retours réseau) ; une fois
> établie, le débit est celui du réseau. C'est pour ça que le gain est énorme sur
> des milliers de petites commandes et nul sur un gros transfert.

> [!WARNING]
> **Piège**
>
> Un maître oublié maintient une session authentifiée ouverte pendant toute la
> durée de `ControlPersist`. Sur un poste partagé ou une machine de rebond, c'est
> un accès offert à qui prend la main sur ta session locale. Sur un bastion, on
> règle `ControlPersist` court (`1m`) ou on le désactive.

---

<a id="qo14-7"></a>**[QO14.7](README.md#qo14-7)** — *`-L`, `-R`, `-D` comparés.*

**Réponse**

```text
-L port_local:hôte_cible:port_cible     serveur
   J'ÉCOUTE chez moi. Le SERVEUR SSH ouvre la connexion TCP finale.
   moi:15432 ──(canal chiffré)──► lab-adm ──(TCP clair)──► lab-db:5432
   Cas d'usage : brancher un client SQL sur une base qui n'est joignable
   que depuis le réseau de lab.
   Empêché côté serveur par : AllowTcpForwarding no  (ou PermitOpen)

-R port_distant:hôte_cible:port_cible   serveur
   LE SERVEUR ÉCOUTE. C'est MON CLIENT qui ouvre la connexion TCP finale.
   lab-ops:8080 ──(canal chiffré)──► moi ──(TCP local)──► 127.0.0.1:3000
   Cas d'usage : montrer une maquette qui tourne sur mon poste à une
   machine du lab, sans rien publier ni ouvrir de pare-feu entrant.
   Empêché côté serveur par : AllowTcpForwarding no ; limité par GatewayPorts

-D port_local                            serveur
   J'ÉCOUTE chez moi, en parlant SOCKS5. La cible est décidée requête par
   requête par l'application ; le SERVEUR ouvre chaque connexion finale.
   navigateur ──► moi:1080 (SOCKS) ──► lab-adm ──► n'importe quoi du lab
   Cas d'usage : naviguer sur les interfaces d'administration internes
   depuis mon poste, sans monter un tunnel par service.
   Empêché côté serveur par : AllowTcpForwarding no
```

`-L` et `-D` sont des redirections **sortantes** du point de vue du serveur :
elles donnent au client l'accès réseau du serveur. `-R` est **entrante** : elle
donne au serveur l'accès réseau du client. C'est la différence qui compte pour
la sécurité.

> [!NOTE]
> **Pourquoi**
>
> La règle de lecture qui évite toutes les confusions : **le premier port est
> celui qu'on ouvre, et la lettre dit chez qui.** `-L` = Local, le port s'ouvre
> chez moi. `-R` = Remote, le port s'ouvre chez le serveur. Le reste de la ligne
> (`hôte:port`) est toujours la destination finale, vue **depuis la machine qui
> établit la connexion finale** — le serveur pour `-L` et `-D`, le client pour
> `-R`. C'est pourquoi `-L 15432:127.0.0.1:5432` désigne la boucle locale du
> serveur, et `-R 8080:127.0.0.1:3000` la boucle locale du client.

> [!WARNING]
> **Piège**
>
> `-D` a un piège spécifique : la résolution DNS. Si l'application résout le nom
> localement puis demande une IP au proxy, tu fuites tes requêtes DNS et tu
> n'atteins pas les noms internes. Il faut un client SOCKS5 qui délègue la
> résolution : `curl --socks5-hostname` (et non `--socks5`), ou dans Firefox
> l'option « Utiliser un DNS distant ». Le `h` de `socks5h` dans les variables
> d'environnement de proxy signifie exactement ça.
>
> Pour `-R`, le piège est double : le port n'écoute que sur la boucle locale du
> serveur tant que `GatewayPorts` n'est pas activé, et un `-R` laissé en place est
> un canal d'accès entrant permanent vers ton poste.

---

<a id="qo14-8"></a>**[QO14.8](README.md#qo14-8)** — *Les cinq limites de la boucle `for h in ...; do ssh ...; done`.*

**Réponse**

1. **Pas d'idempotence.** `ssh h 'echo "X=1" » /etc/app.conf'` ajoute la ligne
   **à chaque exécution**. La boucle décrit une action, pas un état. Relancer
   après un échec partiel double les modifications sur les machines déjà
   traitées. Un outil de gestion de configuration décrit l'état voulu et ne fait
   que le nécessaire.
2. **Pas de gestion d'erreur exploitable.** Sans précaution, la boucle continue
   après un échec et le code final est celui de la dernière machine. Il faut
   écrire à la main la collecte des codes, la distinction entre « injoignable »
   (255) et « la commande a échoué », et le rapport. Et `set -e` ne sauve pas :
   dans une boucle, il s'applique mal.
3. **Séquentiel.** 200 machines à 0,4 s de connexion, c'est 80 secondes rien que
   d'établissement — avant même le travail. Paralléliser à la main (`xargs -P`,
   jobs bash) introduit l'entrelacement des sorties, la limite de fichiers
   ouverts, et la gestion des signaux.
4. **Pas d'inventaire ni de ciblage.** La liste d'hôtes est en dur dans le
   script. Pas de groupes, pas de variables par machine ou par environnement, pas
   de « toutes les machines de préproduction sauf celles en maintenance ».
5. **Pas de restitution.** Aucune trace de ce qui a changé, aucun mode « à blanc »
   pour voir ce qui serait fait, aucun résumé exploitable. En production, on doit
   pouvoir répondre à « qu'est-ce qui a été modifié, où, quand ».

À quoi s'ajoutent deux problèmes techniques immédiats : `ssh` **consomme stdin**
(une boucle `while read h; do ssh "$h" ...; done < liste` s'arrête après la
première machine — il faut `ssh -n` ou `< /dev/null`), et les commandes distantes
tournent dans un shell non interactif au `PATH` réduit.

> [!NOTE]
> **Pourquoi**
>
> La bonne façon de formuler ça en entretien : la boucle `ssh` décrit **comment
> faire**, un outil de gestion de configuration décrit **ce qui doit être vrai**.
> Tant qu'on est sur trois machines et une commande de lecture, la boucle est la
> bonne réponse — plus simple, plus rapide à écrire, moins de dépendances. Dès
> qu'on modifie un état, qu'on répète, ou qu'on dépasse la dizaine de machines, le
> coût du script maison dépasse celui de l'outil.
>
> C'est exactement pourquoi Ansible s'appuie sur SSH sans le remplacer : il active
> `ControlMaster` par défaut, pousse un module Python et récupère un résultat
> structuré. Tout ce module reste donc valable — le durcissement, les clés, le
> `~/.ssh/config`, le multiplexage : c'est l'infrastructure sur laquelle Ansible
> repose (module 23).

---

<a id="qo14-9"></a>**[QO14.9](README.md#qo14-9)** — *Certificats SSH.*

**Réponse**

**Le problème.** `known_hosts` et `authorized_keys` sont des listes d'accès à
distribuer. Elles ne passent pas l'échelle :

* côté hôtes, chaque VM reconstruite change d'empreinte, et chaque poste de
  chaque administrateur doit être mis à jour. Résultat pratique : tout le monde
  prend le réflexe `ssh-keygen -R`, et l'alerte de sécurité ne protège plus rien.
* côté utilisateurs, accorder un accès c'est ajouter une ligne dans N fichiers
  sur M machines ; le **retirer** au départ d'un collaborateur, c'est refaire le
  même travail, sans garantie de n'avoir rien oublié. Personne ne sait dire avec
  certitude qui a accès à quoi.

**Le principe.** On introduit une autorité de certification : une simple paire de
clés SSH, conservée hors ligne. Elle **signe** des clés publiques en y attachant
des métadonnées : identité, principaux autorisés, date d'expiration, options,
numéro de série.

```bash
# la CA (à garder hors ligne, chiffrée)
ssh-keygen -t ed25519 -f ca_hosts -C "CA hôtes lab.local"
ssh-keygen -t ed25519 -f ca_users -C "CA utilisateurs lab.local"

# certificat d'HÔTE, valable 52 semaines
ssh-keygen -s ca_hosts -I lab-web -h -n lab-web,10.10.10.11 \
  -V +52w /etc/ssh/ssh_host_ed25519_key.pub

# certificat d'UTILISATEUR, valable 8 heures
ssh-keygen -s ca_users -I mathieu -n mathieu,admin \
  -V +8h ~/.ssh/id_ed25519.pub
```

**Ce que ça remplace.**

| Avant | Après |
|---|---|
| N lignes dans `known_hosts` | 1 ligne `@cert-authority *.lab.local ...` |
| N lignes dans `authorized_keys` | `TrustedUserCAKeys /etc/ssh/ca_users.pub` |

Côté serveur : `HostCertificate /etc/ssh/ssh_host_ed25519_key-cert.pub` et
`TrustedUserCAKeys`, plus éventuellement `AuthorizedPrincipalsFile` pour décider
quels *principaux* ont droit à quel compte local. Côté client : le fichier
`id_ed25519-cert.pub` est présenté automatiquement s'il est à côté de la clé.

> [!NOTE]
> **Pourquoi**
>
> Le gain décisif est la **durée de vie**. Un certificat utilisateur de 8 heures
> supprime le problème de la révocation : il n'y a rien à révoquer, ça expire. Le
> départ d'un collaborateur se traite en cessant de lui délivrer des certificats,
> pas en visitant 200 machines. Et le certificat d'hôte supprime le problème du
> TOFU : une VM reconstruite obtient un nouveau certificat signé par la même CA,
> et aucun client ne voit passer d'alerte — alors qu'une vraie interception, elle,
> échouera toujours, faute de signature valide.
>
> En pratique, on ne signe pas à la main : un service d'émission (Vault SSH
> Engine, Teleport, `step-ca`) authentifie la personne auprès du SSO de
> l'entreprise et lui délivre un certificat de quelques heures.

> [!WARNING]
> **Piège**
>
> Trois erreurs classiques de mise en œuvre :
>
> * **oublier `-n`** : un certificat sans principal est valable pour... rien du
>   tout côté hôte, et pour n'importe quel nom d'utilisateur côté utilisateur si
>   le serveur n'utilise pas `AuthorizedPrincipalsFile`. Les principaux sont le
>   cœur du contrôle d'accès.
> * **oublier `-h`** pour un certificat d'hôte : sans lui, on a signé un
>   certificat d'utilisateur qui ne sera jamais accepté comme identité de machine.
> * **garder la clé de CA sur le bastion** : compromettre la CA, c'est
>   compromettre tout le parc, définitivement. Elle vit hors ligne ou dans un HSM,
>   et on prévoit `RevokedKeys` / une KRL (`ssh-keygen -k`) dès le premier jour,
>   parce qu'un certificat long émis par erreur ne s'annule pas autrement.

---

## 14.5 Exercices guidés

<a id="e14-1"></a>**[E14.1](README.md#e14-1)** — *Créer une paire ed25519 commentée, avec passphrase et KDF renforcé.*

```bash
ssh-keygen -t ed25519 -a 100 -C "mathieu@lab-adm-2026-09" \
  -f ~/.ssh/id_ed25519
# Enter passphrase : une phrase longue, pas un mot de passe
ls -l ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub
```

Vérifier que la clé privée est bien chiffrée :

```console
$ head -2 ~/.ssh/id_ed25519
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABD...
$ ssh-keygen -y -P '' -f ~/.ssh/id_ed25519
Load key "/home/mathieu/.ssh/id_ed25519": incorrect passphrase supplied
```

La seconde commande est le test fiable : si une passphrase vide suffisait à
extraire la clé publique, la clé ne serait pas protégée.

> [!NOTE]
> **Pourquoi**
>
> `-a 100` fixe le nombre de tours de la fonction de dérivation `bcrypt_pbkdf`
> appliquée à la passphrase (16 par défaut). Chaque tour coûte du temps à toi
> **une fois** à l'ouverture, et à un attaquant **à chaque essai** de son
> dictionnaire : c'est un facteur 6 sur le coût d'un cassage hors ligne, pour
> environ 0,1 seconde de plus au chargement.
>
> Le commentaire n'a aucun rôle cryptographique, mais il est la seule information
> lisible dans `authorized_keys` : quand tu devras retirer une clé dans deux ans,
> `mathieu@lab-adm-2026-09` te dira de quoi il s'agit, `mathieu@ubuntu` non.
> Convention utile : utilisateur + machine d'origine + date d'émission.
>
> Depuis OpenSSH 7.8, toutes les clés privées sont stockées dans le format
> OpenSSH natif (`BEGIN OPENSSH PRIVATE KEY`) : chiffrement `aes256-ctr`,
> dérivation `bcrypt`. L'ancien format PEM chiffré (`Proc-Type: 4,ENCRYPTED`,
> `DEK-Info: AES-128-CBC`) utilisait une dérivation MD5 à un seul tour, cassable
> très vite. Si tu croises encore une clé à ce format, régénère-la.

> [!WARNING]
> **Piège**
>
> `ssh-keygen -p -f ~/.ssh/id_ed25519` change la passphrase d'une clé existante
> sans changer la clé : la clé publique déployée partout reste valable. C'est ce
> qu'il faut faire quand on découvre une clé sans passphrase, **pas** en générer
> une nouvelle et repartir pour une tournée de déploiement.

---

<a id="e14-2"></a>**[E14.2](README.md#e14-2)** — *Empreintes SHA256, randomart, et clé d'hôte locale.*

```bash
ssh-keygen -lf ~/.ssh/id_ed25519.pub          # empreinte SHA256
ssh-keygen -lvf ~/.ssh/id_ed25519.pub         # + dessin ASCII
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

```console
$ ssh-keygen -lf ~/.ssh/id_ed25519.pub
256 SHA256:8kQ3vN1pW+Rr0Tz9c5aXbLd2Hq7mYfJ4uEsKgVnP1oU
    mathieu@lab-adm-2026-09 (ED25519)
```

> [!NOTE]
> **Pourquoi**
>
> La sortie se lit : taille en bits, algorithme d'empreinte et valeur, commentaire,
> type de clé. Depuis OpenSSH 6.8, le défaut est SHA256 encodé en base64 — sans
> le `=` de bourrage final, ce qui surprend quand on compare à un hachage calculé
> autrement.
>
> Le dessin ASCII (*randomart*) n'existe que pour une raison : un humain compare
> mieux deux images que deux chaînes de 43 caractères. Il est destiné à la
> vérification visuelle d'une empreinte d'hôte affichée à la première connexion.
> Il n'a aucune valeur cryptographique propre : c'est une représentation de
> l'empreinte, pas autre chose.
>
> Point pratique : `ssh-keygen -lf` fonctionne aussi sur un `authorized_keys` ou
> un `known_hosts` entier, et liste alors une empreinte par ligne. C'est la façon
> la plus rapide de répondre à « est-ce que ma clé est bien dans ce fichier ».

---

<a id="e14-3"></a>**[E14.3](README.md#e14-3)** — *Déployer sa clé publique sans `ssh-copy-id`.*

```bash
cat ~/.ssh/id_ed25519.pub | ssh mathieu@10.10.10.11 \
  "umask 077; mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

Variante qui évite les doublons à chaque exécution :

```bash
KEY=$(cat ~/.ssh/id_ed25519.pub)
ssh mathieu@10.10.10.11 "umask 077; mkdir -p ~/.ssh; \
  grep -qxF '$KEY' ~/.ssh/authorized_keys 2>/dev/null || \
  printf '%s\n' '$KEY' >> ~/.ssh/authorized_keys"
```

> [!NOTE]
> **Pourquoi**
>
> Le `umask 077` est le cœur de l'exercice : il fait que **tout** ce qui est créé
> par la suite dans cette commande (le répertoire `.ssh` comme le fichier
> `authorized_keys`) naît en `700` et `600`. Sans lui, `mkdir -p ~/.ssh` crée un
> répertoire en `755` et `sshd` refusera de le lire à cause de `StrictModes`,
> avec pour seul symptôme un `Permission denied (publickey)` côté client.
>
> Le `»` et non `>` : écraser le fichier supprimerait les clés des collègues et
> des outils d'automatisation. C'est une erreur qui coupe l'accès à d'autres
> personnes que soi, donc particulièrement désagréable.
>
> `ssh-copy-id` fait exactement ce travail, en plus rigoureux : il vérifie que la
> clé n'est pas déjà présente, crée les répertoires avec les bons modes, et sait
> prendre les clés depuis l'agent quand on ne lui donne pas de `-i`. La raison de
> le faire à la main une fois est de comprendre qu'il n'y a aucune magie : trois
> opérations de fichier.

> [!WARNING]
> **Piège**
>
> Une clé publique tient sur **une seule ligne**. Un copier-coller à travers un
> éditeur qui replie les lignes longues (ou un traitement de texte) casse la clé
> en deux et produit un `Permission denied (publickey)` inexplicable. Vérification :
> `awk '{print NR, NF, substr($1,1,20)}' ~/.ssh/authorized_keys` — chaque ligne
> doit avoir 3 champs (type, clé, commentaire) et commencer par `ssh-ed25519` ou
> `ssh-rsa`.

---

<a id="e14-4"></a>**[E14.4](README.md#e14-4)** — *Auditer et corriger les permissions de `~/.ssh`.*

```bash
# lister ce qui est trop ouvert
find ~/.ssh -perm /g+rwx,o+rwx -printf '%M %p\n'

# corriger en une passe
chmod 700 ~/.ssh
find ~/.ssh -type f -exec chmod 600 {} +
chmod 644 ~/.ssh/*.pub ~/.ssh/known_hosts 2>/dev/null
chmod go-w ~
```

> [!NOTE]
> **Pourquoi**
>
> `-perm /g+rwx,o+rwx` se lit « au moins un de ces bits est positionné » (le `/`).
> À ne pas confondre avec `-perm -g+rwx` (« tous ces bits sont positionnés ») ni
> `-perm 600` (« exactement ce mode »). C'est la distinction qui fait qu'un audit
> de permissions rend le bon résultat ou passe à côté de la moitié des fichiers.
>
> Le `chmod go-w ~` final est celui qu'on oublie : `StrictModes` remonte jusqu'au
> répertoire personnel. Un home en `775` avec un groupe partagé déclenche le refus
> même si `~/.ssh` est parfait.
>
> Mettre les fichiers publics en `644` n'est pas obligatoire mais c'est propre :
> `known_hosts` et les `.pub` n'ont aucun secret, et les laisser en `600` gêne les
> outils qui les lisent sous un autre compte.

> [!WARNING]
> **Piège**
>
> `chmod -R 600 ~/.ssh` est l'erreur classique : les répertoires perdent leur bit
> `x` et deviennent intraversables, y compris pour toi. D'où le `find -type f`.
> Et un `chmod 700 ~/.ssh` seul ne corrige rien si c'est le fichier de clé qui est
> en `644` : il faut les deux.

---

<a id="e14-5"></a>**[E14.5](README.md#e14-5)** — *Agent, chargement avec durée de vie, inspection.*

```bash
eval "$(ssh-agent -s)"                 # démarre et exporte les variables
ssh-add -t 3600 ~/.ssh/id_ed25519      # 1 h de durée de vie
ssh-add -l                             # empreintes
ssh-add -L                             # clés publiques complètes
```

```console
$ ssh-add -l
256 SHA256:8kQ3vN1pW+Rr0Tz9c5aXbLd2Hq7mYfJ4uEsKgVnP1oU
    mathieu@lab-adm-2026-09 (ED25519)
$ env | grep SSH_
SSH_AUTH_SOCK=/tmp/ssh-XXXX7aBcDe/agent.3412
SSH_AGENT_PID=3413
```

Au bout d'une heure, la clé est retirée automatiquement : `ssh-add -l` répond
`The agent has no identities.` et la connexion suivante redemande la passphrase.

> [!NOTE]
> **Pourquoi**
>
> `eval` est indispensable et souvent mal compris : `ssh-agent -s` ne modifie pas
> ton shell, il **imprime** sur sa sortie standard les commandes `export` à
> exécuter. Sans `eval`, tu vois s'afficher `SSH_AUTH_SOCK=...; export SSH_ AUTH_SOCK;` et rien n'est positionné — l'agent tourne, mais aucun client ne
> sait où le joindre.
>
> Tout le mécanisme tient dans `SSH_AUTH_SOCK` : c'est le chemin de la socket UNIX
> que `ssh` interroge pour demander une signature. C'est aussi ce qui explique le
> risque du transfert d'agent : il suffit de pouvoir lire cette socket pour
> utiliser les clés.
>
> `-t` est la mesure d'hygiène la plus rentable du module : un agent chargé sans
> limite garde tes clés utilisables jusqu'à la fin de la session, y compris quand
> tu t'absentes. Pour une clé de production, `ssh-add -c` ajoute une confirmation
> à chaque usage.

> [!WARNING]
> **Piège**
>
> Sur un bureau Ubuntu, un agent est déjà démarré par la session graphique
> (`gnome-keyring` ou `ssh-agent` via systemd `--user`). Lancer `eval
> "$(ssh-agent -s)"` dans chaque terminal crée alors un agent de plus à chaque
> fois : on se retrouve avec une dizaine de processus `ssh-agent`, dont un seul
> est joignable. Le bon réflexe est de **tester d'abord** :
>
> ```bash
> ssh-add -l >/dev/null 2>&1 || eval "$(ssh-agent -s)"
> ```
>
> Et `AddKeysToAgent yes` dans `~/.ssh/config` évite le `ssh-add` manuel : la clé
> est ajoutée à l'agent la première fois qu'on saisit sa passphrase.

---

<a id="e14-6"></a>**[E14.6](README.md#e14-6)** — *L'agent OpenSSH natif sous Windows.*

Dans un PowerShell **administrateur**, une seule fois :

```powershell
Get-Service ssh-agent
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service ssh-agent
```

Puis dans un PowerShell normal :

```powershell
ssh-add $env:USERPROFILE\.ssh\id_ed25519
ssh-add -l
```

Le fichier de configuration client est `C:\Users\<toi>\.ssh\config`, mêmes
directives et même syntaxe que sous Linux. Les chemins s'y écrivent
`C:\Users\mathieu\.ssh\id_ed25519` ou, plus portable, `~/.ssh/id_ ed25519`.

> [!NOTE]
> **Pourquoi**
>
> Sous Windows, `ssh-agent` n'est pas un processus lancé par le shell : c'est un
> **service Windows**. Deux conséquences qui changent l'usage :
>
> 1. Il n'y a pas de `SSH_AUTH_SOCK` : les clients le joignent par un tube nommé
>    (`\\.\pipe\openssh-ssh-agent`). Rien à exporter, rien à `eval`.
> 2. Les clés ajoutées sont **chiffrées par DPAPI et stockées dans le registre**,
>    liées à ton compte Windows. Elles survivent donc au redémarrage : un
>    `ssh-add` une fois pour toutes, et la passphrase n'est plus jamais demandée.
>    C'est très confortable et c'est aussi un choix de sécurité à assumer — si
>    quelqu'un ouvre ta session Windows, il a tes clés. Sur un poste sensible, on
>    préfère `ssh-add -t`.
>
> Le client OpenSSH est livré avec Windows depuis la version 1809 ; `ssh -V` dans
> PowerShell donne sa version. Rien à installer dans le cas général.

> [!WARNING]
> **Piège**
>
> Deux frottements classiques sur un poste Windows :
>
> * **Permissions NTFS.** Le client refuse une clé privée dont les ACL sont trop
>   larges, avec un message équivalent au `UNPROTECTED PRIVATE KEY FILE` de Linux.
>   Correction : propriétés du fichier → Sécurité → Avancé → désactiver l'héritage,
>   ne laisser que ton compte. En ligne :
>   `icacls .\id_ed25519 /inheritance:r /grant:r "${env: USERNAME}:(R)"`.
> * **PuTTY et Pageant** sont un écosystème séparé : format `.ppk`, agent
>   `pageant.exe`, conversion par `puttygen`. Ils ne parlent pas au service
>   `ssh-agent` de Windows. Si l'équipe utilise WinSCP ou PuTTY, il faut soit
>   convertir les clés, soit configurer WinSCP pour utiliser Pageant — ce n'est
>   pas interchangeable. Pour de nouveaux postes, s'en tenir à OpenSSH natif
>   évite ce doublon.
> * **WSL** ne voit pas non plus l'agent Windows : c'est un autre système. Soit on
>   y installe son propre agent, soit on relaie le tube nommé (`npiperelay`).

---

<a id="e14-7"></a>**[E14.7](README.md#e14-7)** — *Configuration effective pour `lab-db`, sans se connecter.*

```bash
ssh -G lab-db | grep -E \
  '^(user|hostname|port|identityfile|identitiesonly|proxyjump) '
```

```console
user mathieu
hostname 10.10.10.12
port 22
identityfile ~/.ssh/id_ed25519
identitiesonly yes
proxyjump bastion
```

> [!NOTE]
> **Pourquoi**
>
> `ssh -G` est l'outil de diagnostic le plus sous-employé d'OpenSSH. Il applique
> toute la résolution — fichier utilisateur, `Include`, fichier système, options
> `-o` de la ligne de commande, blocs `Match` — et n'émet aucun paquet. Toute
> discussion sur « mais j'ai pourtant écrit `User` » se règle avec cette commande.
>
> Le `-G` sert aussi à écrire des scripts robustes : au lieu de coder une IP en
> dur, on demande `ssh -G "$alias" | awk '/^hostname /{print $2}'`. Le script
> suit alors la configuration au lieu de la dupliquer.
>
> Note de lecture : la sortie est en **minuscules**, quelle que soit la casse
> utilisée dans le fichier, et affiche toutes les directives, y compris celles que
> tu n'as jamais écrites (leurs valeurs par défaut). D'où le `grep`.

---

<a id="e14-8"></a>**[E14.8](README.md#e14-8)** — *Mesurer le gain du multiplexage.*

```bash
mkdir -p ~/.ssh/cm && chmod 700 ~/.ssh/cm
ssh -O exit lab-web 2>/dev/null          # repartir à zéro

# sans multiplexage
time ( for i in 1 2 3 4 5; do ssh -o ControlMaster=no \
       -o ControlPath=none lab-web true; done )

# avec (ControlMaster auto est dans ~/.ssh/config)
ssh -fN lab-web                           # établit le maître
time ( for i in 1 2 3 4 5; do ssh lab-web true; done )
ssh -O check lab-web
```

```console
real    0m1,884s      # sans
real    0m0,193s      # avec
Master running (pid=5120)
```

Rapport observé : environ 10. Sur un réseau distant (latence 30 ms), le rapport
monte à 20 ou 30.

> [!NOTE]
> **Pourquoi**
>
> Le coût d'une connexion SSH est presque entièrement dans son établissement :
> poignée de main TCP (1 aller-retour), échange de bannières, `KEXINIT`, échange
> de clés Diffie-Hellman sur courbe (calcul asymétrique des deux côtés,
> 1 à 2 allers-retours), vérification de `known_hosts`, puis authentification
> (nouvelle signature, encore un aller-retour). Une fois la session établie,
> ouvrir un canal supplémentaire ne coûte qu'un message.
>
> Le multiplexage ne rend donc rien plus rapide : il **supprime** des connexions.
> D'où un gain énorme sur beaucoup de petites commandes, et nul sur un gros
> transfert de fichier.
>
> C'est exactement ce que fait Ansible par défaut (`ssh_args = -o
> ControlMaster=auto -o ControlPersist=60s`), et c'est la première chose à
> vérifier quand un playbook est anormalement lent.

> [!WARNING]
> **Piège**
>
> `-o ControlPath=none` en plus de `ControlMaster=no` : sans lui, le client
> réutilise un maître déjà en place et la mesure « sans multiplexage » est fausse.
> Et `ssh -O exit` avant de commencer, sinon un maître laissé par `ControlPersist`
> fausse la première mesure.

---

<a id="e14-9"></a>**[E14.9](README.md#e14-9)** — *Vérifier une clé d'hôte et supprimer une entrée hachée.*

```bash
# ce que présente le réseau
ssh-keyscan -t ed25519 10.10.10.13 2>/dev/null | ssh-keygen -lf -
# la vérité, sur lab-rhel (console, ou session déjà ouverte)
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
# l'entrée enregistrée chez moi, malgré le hachage
ssh-keygen -F 10.10.10.13
# suppression propre
ssh-keygen -R 10.10.10.13
```

```console
$ ssh-keygen -F 10.10.10.13
# Host 10.10.10.13 found: line 7
|1|Qk9sT2hZ...|R2Vu... ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...
$ ssh-keygen -R 10.10.10.13
# Host 10.10.10.13 found: line 7
/home/mathieu/.ssh/known_hosts updated.
Original contents retained as /home/mathieu/.ssh/known_hosts.old
```

> [!NOTE]
> **Pourquoi**
>
> Le hachage (`HashKnownHosts yes`, défaut Debian/Ubuntu) remplace le nom d'hôte
> en clair par un HMAC-SHA1 salé, propre à chaque ligne. On ne peut donc pas faire
> `grep lab-rhel ~/.ssh/known_hosts` : il faut passer par `ssh-keygen -F`, qui
> recalcule le HMAC avec le sel de chaque ligne pour trouver la bonne.
>
> Raison d'être du hachage : si un poste est compromis, `known_hosts` est une
> carte toute faite du parc — la liste de toutes les machines auxquelles cette
> personne se connecte. Le hachage empêche cette énumération. C'est le même
> raisonnement que pour l'historique du shell.
>
> `ssh-keygen -R` gère le hachage, supprime **toutes** les clés associées à cet
> hôte (`ed25519`, `rsa`, `ecdsa`), et garde une copie du fichier d'origine en
> `.old` — utile quand on s'est trompé de machine.

> [!WARNING]
> **Piège**
>
> `known_hosts` indexe par **nom et par adresse**, séparément. Supprimer
> `ssh-keygen -R lab-rhel` ne supprime pas l'entrée `10.10.10.13`, et l'alerte
> reviendra dès que tu utiliseras l'IP. Il faut les deux, ou lire attentivement la
> ligne `Offending ... key in /home/mathieu/.ssh/known_hosts:7` du message
> d'alerte, qui donne le numéro de ligne exact.
>
> Et `ssh-keyscan` ne **vérifie** rien : il enregistre ce que le réseau lui
> répond. L'utiliser pour « corriger » une alerte de changement de clé revient à
> demander à l'attaquant de confirmer son identité.

---

<a id="e14-10"></a>**[E14.10](README.md#e14-10)** — *Valeurs effectives côté serveur, y compris dans un `Match`.*

```bash
sudo sshd -T | grep -Ei '^(permitrootlogin|maxauthtries) '
sudo sshd -T | grep -Ei '^(passwordauthentication|logingracetime) '
sudo sshd -T | grep -Ei '^allowtcpforwarding '
sudo sshd -T -C user=sauvegarde,host=lab-web,addr=10.10.10.14 \
  | grep -i '^passwordauthentication '
```

```console
permitrootlogin no
passwordauthentication no
maxauthtries 3
logingracetime 20
allowtcpforwarding yes
```

> [!NOTE]
> **Pourquoi**
>
> `sshd -T` imprime la configuration **résolue** : fichier principal, tous les
> `Include`, et valeurs par défaut pour tout ce qui n'a pas été écrit. C'est la
> seule réponse fiable à « qu'est-ce qui s'applique vraiment ». Un `grep` dans
> `sshd_config` ne voit ni les fragments de `sshd_config.d/`, ni les défauts, ni
> l'effet de la règle « première valeur gagnante ».
>
> `-C` (pour *connection specification*) simule une connexion : utilisateur, hôte,
> adresse source, et éventuellement `laddr`/`lport`/`rdomain`. Les blocs `Match`
> sont alors évalués. C'est indispensable dès qu'on a écrit un `Match Group
> sftponly` ou `Match Address` : sans `-C`, `sshd -T` affiche la configuration
> **hors** `Match`, ce qui ne correspond à aucune connexion réelle.

> [!WARNING]
> **Piège**
>
> `sshd -T` doit être lancé en root : il lit les clés d'hôte pour valider la
> configuration et échoue sinon. Et prends l'habitude de l'espace final dans le `grep` (`'^port '`) :
> sans lui, `^port` attrape aussi
> `ports` ... ou toute directive future à préfixe commun, et `^permit` renvoie
> `permitrootlogin`, `permitemptypasswords`, `permittunnel`… La sortie de `sshd -T` est « directive espace valeur », l'espace est le séparateur fiable.

---

<a id="e14-11"></a>**[E14.11](README.md#e14-11)** — *Boucle sur le parc avec délai plafonné et code agrégé.*

```bash
#!/usr/bin/env bash
set -uo pipefail
rc=0
for h in lab-web lab-db lab-rhel lab-ops; do
  cmd='printf "%s %s\n" "$(hostname -s)" "$(cut -d" " -f1-3 /proc/loadavg)"'
  if out=$(ssh -n -o BatchMode=yes -o ConnectTimeout=5 "$h" "$cmd" 2>&1); then
    printf '%-10s OK   %s\n' "$h" "$out"
  else
    printf '%-10s FAIL %s\n' "$h" "${out%%$'\n'*}"
    rc=1
  fi
done
exit "$rc"
```

> [!NOTE]
> **Pourquoi**
>
> Trois options portent tout le poids de ce script :
>
> * **`-n`** redirige stdin depuis `/dev/null`. Sans lui, `ssh` **consomme le flux
>   d'entrée** du script : dans une boucle `while read h; ... done < hotes.txt`,
>   la première invocation avale tout le fichier et la boucle s'arrête après une
>   machine. C'est un des bugs les plus déroutants du scripting SSH, parce que le
>   script « marche » et traite silencieusement une seule ligne. `< /dev/null`
>   fait la même chose.
> * **`BatchMode=yes`** désactive toute invite : pas de demande de passphrase, pas
>   de question `yes/no` sur une clé d'hôte inconnue. Une machine mal configurée
>   échoue immédiatement au lieu de bloquer le script pour l'éternité. Obligatoire
>   dans tout ce qui tourne sans humain.
> * **`ConnectTimeout=5`** plafonne l'attente d'établissement TCP. Sans lui, une
>   machine éteinte fait attendre le temps du `timeout` système, soit plus de deux
>   minutes.
>
> `set -e` est volontairement absent : on veut continuer après un échec et
> agréger. C'est le `if` qui capture le code de retour.

> [!WARNING]
> **Piège**
>
> `ssh` renvoie **255** pour ses propres erreurs (machine injoignable,
> authentification refusée, clé d'hôte invalide) et le code de la commande
> distante sinon. Ce qui crée une ambiguïté : une commande distante qui sort
> légitimement en 255 est indiscernable d'une panne de connexion. Quand ça compte,
> on distingue :
>
> ```bash
> ssh ... "$h" 'cmd; echo "RC=$?"' | tail -1
> ```
>
> ou on enveloppe la commande distante pour qu'elle renvoie un code borné.

---

<a id="e14-12"></a>**[E14.12](README.md#e14-12)** — *Exécuter un script local sur une machine distante.*

```bash
ssh lab-ops 'bash -s' -- --court < ~/lab14/bin/etat.sh
```

> [!NOTE]
> **Pourquoi**
>
> Décomposition :
>
> * `bash -s` dit à bash de lire le script **sur son entrée standard** au lieu
>   d'un fichier ;
> * `<` alimente cette entrée standard depuis le fichier local ; `ssh` transporte
>   le flux jusqu'au processus distant ;
> * `--` sépare et les arguments qui suivent deviennent `$1`, `$2`... du script
>   distant.
>
> Rien n'est écrit sur la machine distante : pas de fichier temporaire à nettoyer,
> pas de question de permissions, pas de version obsolète oubliée dans `/tmp`.
> C'est la façon propre de pousser une procédure ponctuelle sur un parc.
>
> Le même principe avec un interpréteur différent fonctionne :
> `ssh h 'python3 -' < script.py`, `ssh h 'sudo bash -s' < durcir.sh`.

> [!WARNING]
> **Piège**
>
> Le script distant ne peut plus lire l'entrée standard, puisqu'elle contient son
> propre code source. Tout `read` interactif à l'intérieur échoue ou lit une
> portion du script. Si le script a besoin de données, passe-les en argument,
> par variable d'environnement (`ssh h "VAR=x bash -s" < s.sh`) ou via un
> descripteur séparé.
>
> Et `sudo bash -s` demande un mot de passe qu'on ne peut pas taper : il faut soit
> une règle `NOPASSWD`, soit `ssh -t` en interactif.

---

<a id="e14-13"></a>**[E14.13](README.md#e14-13)** — *Tunnel local vers `lab-db`, vérification, fermeture propre.*

```bash
ssh -f -N -o ExitOnForwardFailure=yes \
    -L 15432:10.10.10.12:5432 bastion

ss -tlnp | grep 15432
printf '' | timeout 3 bash -c \
  'exec 3<>/dev/tcp/127.0.0.1/15432; head -1 <&3'
```

```console
LISTEN 0 128 127.0.0.1:15432 0.0.0.0:*  users:(("ssh",pid=7841,fd=5))
LAB14-DB-OK lab-db
```

Fermeture :

```bash
ssh -O cancel -L 15432:10.10.10.12:5432 bastion   # si multiplexage actif
# sinon, le processus dédié :
pkill -f 'ssh -f -N.*15432'
```

> [!NOTE]
> **Pourquoi**
>
> `-f` passe en arrière-plan **après l'authentification** (ce qui permet de saisir
> une passphrase avant), `-N` interdit l'exécution d'une commande distante : on ne
> veut qu'un tuyau, pas un shell. Sans `-N`, `-f` lancerait un shell distant
> détaché, inutile et bruyant dans les journaux.
>
> `ExitOnForwardFailure=yes` est l'option qu'il ne faut jamais oublier. Par
> défaut, si le port local est déjà occupé, `ssh` affiche un avertissement sur
> stderr — que `-f` envoie dans le vide — et **maintient la session**. Tu crois
> avoir un tunnel, tu n'en as pas, et ton client SQL se connecte au service qui
> occupait déjà le port. Avec cette option, `ssh` sort en erreur, bruyamment.
>
> La fermeture propre par `ssh -O cancel` retire la redirection sans couper la
> session maître. `ssh -O exit` ferme tout. Un `kill` fonctionne aussi, mais
> identifier le bon processus dans une liste de tunnels est fastidieux — d'où
> l'intérêt de nommer ses tunnels avec des sockets de contrôle dédiées.

> [!WARNING]
> **Piège**
>
> En session interactive, les **séquences d'échappement** valent la peine d'être
> connues : `~?` affiche l'aide, `~#` liste les connexions redirigées, `~C` ouvre
> une ligne de commande `ssh>` où l'on peut taper `-L 15432:...` pour ajouter un
> tunnel à chaud, `~.` tue la session (le seul moyen de sortir d'une session
> figée). Elles ne fonctionnent qu'en début de ligne, sur une session avec TTY, et
> `~` doit être le premier caractère après un retour à la ligne.

---

<a id="e14-14"></a>**[E14.14](README.md#e14-14)** — *Proxy SOCKS5 et résolution distante.*

```bash
ssh -f -N -D 1080 bastion
curl --socks5-hostname 127.0.0.1:1080 http://lab-web.lab.local/
curl --socks5-hostname 127.0.0.1:1080 http://ifconfig.me/ip
ssh -O exit bastion          # ou pkill -f 'ssh -f -N -D 1080'
```

> [!NOTE]
> **Pourquoi**
>
> `-D` ne fixe aucune destination : il ouvre un proxy **SOCKS5** local. Pour chaque
> connexion, l'application annonce la cible au proxy, et c'est le serveur SSH qui
> ouvre la connexion TCP finale. Un seul tunnel remplace donc autant de `-L` qu'il
> y a de services à joindre.
>
> `--socks5-hostname` et non `--socks5` : c'est toute la différence.
> Avec `--socks5`, `curl` résout le nom **localement** puis demande une IP au
> proxy — donc `lab-web.lab.local`, qui n'existe que dans le DNS du lab, échoue, et
> tes requêtes DNS fuitent vers ton résolveur. Avec `--socks5-hostname`, le nom est
> transmis tel quel et résolu par le serveur SSH. C'est ce que signifie le `h` de
> `socks5h://` dans les variables `ALL_PROXY`.
>
> La seconde commande prouve la sortie : l'adresse publique renvoyée est celle du
> réseau de lab, pas celle de ton poste.

> [!WARNING]
> **Piège**
>
> Dans un navigateur, cocher « Proxy SOCKS v5 » ne suffit pas : il faut aussi
> activer la résolution DNS distante (Firefox : *Utiliser un DNS distant*, ou
> `network.proxy.socks_remote_dns=true`). Sinon les noms internes ne résolvent pas
> et la navigation semble cassée à moitié.
>
> Et un proxy SOCKS ouvert sur `0.0.0.0` (`-D 0.0.0.0:1080`) est un relais ouvert
> vers tout ton réseau interne, sans authentification. Toujours laisser le bind
> par défaut sur la boucle locale.

---

<a id="e14-15"></a>**[E14.15](README.md#e14-15)** — *Restreindre la clé du compte `sauvegarde`.*

Dans `/home/sauvegarde/.ssh/authorized_keys`, **une seule ligne** :

```text
# UNE seule ligne dans le fichier : coupée ici pour l'impression
restrict,from="10.10.10.10",command="/usr/local/bin/lab14-rsync"
  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKf... sauvegarde@lab-adm
```

Le script récupère la commande demandée :

```bash
#!/usr/bin/env bash
# /usr/local/bin/lab14-rsync
set -euo pipefail
cmd="${SSH_ORIGINAL_COMMAND:-}"
logger -t lab14-rsync "demande: ${cmd:-<session interactive>}"
case "$cmd" in
  "rsync --server "*)  exec $cmd ;;
  liste)               exec ls -1 /srv/sauvegarde ;;
  *) echo "commande non autorisée" >&2; exit 42 ;;
esac
```

> [!NOTE]
> **Pourquoi**
>
> Chaque élément de la ligne fait un travail précis :
>
> * `restrict` coupe d'un coup l'allocation de terminal, les redirections de port
>   (locales et distantes), le transfert d'agent, X11, et l'exécution de
>   `~/.ssh/rc`. Formulation « tout interdit, puis j'autorise » : une option
>   ajoutée dans une future version d'OpenSSH sera interdite par défaut. À
>   l'inverse, énumérer `no-pty,no-port-forwarding,. ..` laisse passer tout ce qui
>   n'existe pas encore.
> * `from="10.10.10.10"` limite l'origine. `sshd` compare l'adresse source réelle
>   du socket TCP, pas une donnée fournie par le client : ce n'est pas
>   contournable par le client, seulement par usurpation d'adresse sur le réseau.
>   La liste accepte les motifs et la négation : `from="10.10.10.*,!10.10.10.99"`.
> * `command="..."` force l'exécution, quoi que demande le client, et range la
>   demande d'origine dans `SSH_ ORIGINAL_COMMAND`.
>
> Le `case` est une liste blanche. `rsync --server ...` est la forme qu'`rsync`
> envoie réellement au distant quand on lance `rsync -a src/ h:dst/` — c'est cette
> chaîne-là qu'on autorise, et c'est ce que fait l'outil `rrsync` livré avec
> `rsync` (`/usr/bin/rrsync` sur Ubuntu 24.04), qui en plus impose un
> répertoire racine.

> [!WARNING]
> **Piège**
>
> `eval "$SSH_ORIGINAL_COMMAND"` dans le script de commande forcée annule tout le
> travail : la clé retrouve un shell complet. De même, `exec $cmd` **non quoté**
> comme ci-dessus n'est acceptable que parce que le motif du `case` a déjà
> contraint la forme de la chaîne ; sur une entrée libre, ce serait une injection.
>
> Et sans `restrict`, `command=` ne protège pas des tunnels : `ssh -N -L
> 9999:127.0.0.1:22 sauvegarde@lab-web` ouvre un tunnel **sans jamais exécuter la
> commande forcée**, car la redirection est négociée au niveau de la session, pas
> de la commande.

---

<a id="e14-16"></a>**[E14.16](README.md#e14-16)** — *Lecture d'un `ssh -v`.*

**Réponse**

On est en **phase 3, authentification**. Sont déjà validés : la connexion TCP,
la négociation d'algorithmes, l'échange de clés, et — ligne
`Host '10.10.10.13' is known and matches the ED25519 host key` — l'identité du
serveur. Le problème n'est donc ni réseau, ni `known_hosts`.

La séquence significative est : `Offering public key: ... SHA256:8kQ...` suivi de
`Authentications that can continue: publickey`. Traduction : le client a bien
proposé une clé, avec l'empreinte `SHA256:8kQ...`, et le serveur l'a refusée.
Une seule clé a été proposée, il n'y a donc pas de problème de `MaxAuthTries`.

Trois hypothèses à vérifier **sur le serveur**, dans cet ordre :

1. **Le compte visé.** `ssh -G 10.10.10.13 | grep '^user '` — se connecte-t-on
   au bon utilisateur ? C'est la cause la plus fréquente et la moins chère à
   écarter.
2. **La clé est-elle autorisée pour ce compte ?**
   `sudo ssh-keygen -lf /home/mathieu/.ssh/authorized_keys` et comparer les
   empreintes avec `SHA256:8kQ...`. Une comparaison d'empreintes, pas un `diff`
   visuel.
3. **Permissions et filtrage.** `sudo journalctl -u ssh -n 30` et y chercher
   `Authentication refused: bad ownership or modes`, ou `not allowed because not
   listed in AllowUsers`, puis `sudo sshd -T | grep -Ei
   'pubkeyauth|authorizedkeysfile|allowusers|allowgroups'`.

> [!NOTE]
> **Pourquoi**
>
> La compétence à acquérir est de savoir **s'arrêter de lire**. Un `ssh -vvv`
> produit 200 lignes ; seules quatre comptent :
>
> | Ligne | Ce qu'elle prouve |
> |---|---|
> | `Connecting to ... port 22` | phase 1 commencée, l'adresse utilisée |
> | `is known and matches the ... host key` | phase 2 franchie |
> | `Will attempt key:` / `Offering public key:` | ce que le client propose |
> | `Authentications that can continue:` | ce que le serveur accepte encore |
>
> `Will attempt` liste les identités retenues ; `Offering` marque une tentative
> réellement émise vers le serveur. Si `Offering` n'apparaît jamais, le problème
> est **local** : clé absente, permissions trop larges, agent non joignable. S'il
> apparaît et que le serveur répète `Authentications that can continue`, le
> problème est **distant** : on arrête de jouer avec le client et on va lire le
> journal du serveur.
>
> Le suffixe `agent` en fin de ligne indique que la clé vient de l'agent et non
> d'un fichier : information utile quand on croit utiliser une clé et qu'on en
> utilise une autre.

---

## 14.6 Labs

### <a id="l14-1"></a>**[L14.1](README.md#l14-1)** — *Poser l'accès par clé sur tout le parc*

**Étape 1 — inventaire des clés existantes**

```bash
for f in ~/.ssh/id_*; do
  case "$f" in *.pub) continue;; esac
  printf '%s\n' "--- $f"
  ssh-keygen -lf "$f.pub"
  ssh-keygen -y -P '' -f "$f" >/dev/null 2>&1 \
    && echo "  PAS de passphrase" || echo "  passphrase OK"
done | tee ~/lab14/rapports/cles-avant.md
```

```console
--- /home/mathieu/.ssh/id_rsa
2048 SHA256:Lq7... mathieu@lab-adm (RSA)
  PAS de passphrase
```

**Étape 2 — nouvelle paire**

```bash
ssh-keygen -t ed25519 -a 100 -C "mathieu@lab-adm-2026-09" -f ~/.ssh/id_ed25519
```

**Étape 3 — déploiement**

```bash
for h in 10.10.10.11 10.10.10.12 10.10.10.13 10.10.10.14; do
  ssh-copy-id -i ~/.ssh/id_ed25519.pub "mathieu@$h"
done
for h in 10.10.10.11 10.10.10.12 10.10.10.13 10.10.10.14; do
  ssh -o PasswordAuthentication=no -o BatchMode=yes "mathieu@$h" \
      'echo "$(hostname -s) OK"'
done
```

Les options de la boucle de vérification sont le cœur de l'étape : sans elles,
un repli silencieux sur le mot de passe donnerait l'illusion que la clé
fonctionne.

**Étape 4 — agent**

```bash
ssh-add -l >/dev/null 2>&1 || eval "$(ssh-agent -s)"
ssh-add -t 28800 ~/.ssh/id_ed25519
```

**Étape 5 — retrait de la vieille clé RSA**, en travaillant par empreinte :

```bash
OLD=$(ssh-keygen -lf ~/.ssh/id_rsa.pub | awk '{print $2}')   # SHA256:...
for h in 10.10.10.11 10.10.10.12 10.10.10.13 10.10.10.14; do
  ssh "mathieu@$h" 'cd ~/.ssh && cp authorized_keys authorized_keys.bak &&
    while read -r l; do
      [ -z "$l" ] && continue
      fp=$(printf "%s\n" "$l" | ssh-keygen -lf - | awk "{print \$2}")
      [ "$fp" = "'"$OLD"'" ] || printf "%s\n" "$l"
    done < authorized_keys.bak > authorized_keys'
done
rm -f ~/.ssh/id_rsa ~/.ssh/id_rsa.pub
```

Preuve que la clé n'ouvre plus rien (avant suppression locale) :

```console
$ ssh -o IdentitiesOnly=yes -i ~/.ssh/id_rsa -o BatchMode=yes \
>       mathieu@10.10.10.11 true
mathieu@10.10.10.11: Permission denied (publickey).
```

**Étape 6 — couper le mot de passe sur `lab-web`**

Terminal A (à ne pas fermer) : `ssh mathieu@10.10.10.11`, et on y reste.

Terminal B :

```bash
ssh mathieu@10.10.10.11
sudo tee /etc/ssh/sshd_config.d/60-durcissement.conf >/dev/null <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
EOF
sudo sshd -t && sudo systemctl reload ssh
sudo sshd -T | grep -Ei '^(passwordauthentication|kbdinteractive) '
```

Si `sshd -T` renvoie encore `passwordauthentication yes`, un fragment lu avant le tien l'emporte — `50-cloud-init.conf` sur une image cloud ou une installation Subiquity. Déplace-le hors de `sshd_config.d/` (copie dans `/ root/.m14-backup/`) ou renomme ton fragment `10-durcissement.conf`, puis recharge. La règle est détaillée en L14.3, étape 5. Terminal C, **nouvelle** connexion, avant de fermer A :

```console
$ ssh mathieu@10.10.10.11 true && echo ACCES-OK
ACCES-OK
$ ssh -o PubkeyAuthentication=no mathieu@10.10.10.11
mathieu@10.10.10.11: Permission denied (publickey).
```

> [!NOTE]
> **Pourquoi**
>
> L'ordre des étapes n'est pas cosmétique, c'est la procédure de sécurité :
> déployer la clé **avant** de couper le mot de passe, vérifier la clé avec
> `PasswordAuthentication=no` côté client **avant** de la couper côté serveur, et
> n'utiliser `reload` qu'après `sshd -t`. Chaque inversion de ces étapes est un
> scénario de verrouillage réel.
>
> `reload` plutôt que `restart` : `reload` envoie `SIGHUP` au `sshd` maître, qui
> relit sa configuration et recharge ses écouteurs — les processus enfants qui
> servent les sessions en cours ne sont pas touchés. `restart` fonctionne aussi
> pour les sessions en cours (elles sont portées par des processus séparés), mais
> coupe brièvement l'écoute : si la nouvelle configuration est invalide, plus
> personne n'entre. `reload` est donc le geste par défaut.
>
> `KbdInteractiveAuthentication no` est indispensable : sans lui, PAM continue de
> proposer une invite de mot de passe par un autre chemin et l'utilisateur ne voit
> aucune différence. La vérification par `sshd -T` (et non `grep`) est ce qui
> permet de s'en apercevoir.

> [!WARNING]
> **Piège**
>
> La suppression de la clé RSA se fait **par empreinte**, pas par `grep` sur le
> commentaire : les commentaires sont éditables, dupliqués, parfois absents.
> Travailler sur l'empreinte SHA256 est la seule méthode qui ne se trompe pas de
> clé — et se tromper ici, c'est retirer l'accès de quelqu'un d'autre.
>
> Et on garde toujours une copie (`authorized_keys.bak`) avant de réécrire le
> fichier : c'est l'unique porte d'entrée de la machine.

---

### <a id="l14-2"></a>**[L14.2](README.md#l14-2)** — *Le fichier de configuration client de référence*

`~/.ssh/config` :

```text
# ---- fragments spécifiques (toujours en tête) --------------------
Include ~/.ssh/config.d/*.conf

# ---- le bastion, seule machine jointe directement ----------------
Host bastion lab-adm
    HostName 10.10.10.10
    User mathieu
    Port 22
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

# ---- les serveurs, tous atteints via le bastion -------------------
Host lab-web
    HostName 10.10.10.11
    ProxyJump bastion
Host lab-db
    HostName 10.10.10.12
    ProxyJump bastion
Host lab-rhel
    HostName 10.10.10.13
    ProxyJump bastion
Host lab-ops
    HostName 10.10.10.14
    ProxyJump bastion

# ---- ce qui est commun à toutes les machines du lab ---------------
Host lab-*
    User mathieu
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ForwardAgent no

# ---- réglages globaux, en dernier ---------------------------------
Host *
    ServerAliveInterval 30
    ServerAliveCountMax 3
    ControlMaster auto
    ControlPath ~/.ssh/cm/%C
    ControlPersist 10m
    AddKeysToAgent yes
    HashKnownHosts yes
```

```bash
mkdir -p ~/.ssh/cm ~/.ssh/config.d
chmod 700 ~/.ssh ~/.ssh/cm ~/.ssh/config.d
chmod 600 ~/.ssh/config
```

**Étape 3 — preuve**

```console
$ ssh -G lab-db | grep -E \
>   '^(user|hostname|port|identityfile|identitiesonly|proxyjump) '
user mathieu
hostname 10.10.10.12
port 22
identityfile ~/.ssh/id_ed25519
identitiesonly yes
proxyjump bastion
```

**Étape 4 — l'ordre des blocs**

Avec **ce** fichier, remonter `Host lab-*` et `Host *` en tête ne change rien à `ssh -G lab-db` : aucun mot-clé n'y est défini à la fois dans un bloc générique et
dans un bloc spécifique, et les valeurs communes sont identiques. La différence apparaît dès qu'il y a conflit : les blocs génériques, lus en premier, fixent leurs valeurs
avant les blocs spécifiques. Pour la constater, ajoute `User
root` dans `Host *` : placé en tête, il l'emporte sur le `User mathieu` de `lab-*` et `ssh -G lab-db` affiche `user root` ; placé en dernier, il est ignoré.

Phrase à écrire dans le rapport : *« `ssh_config` retient, pour chaque mot-clé,
la première valeur rencontrée en descendant le fichier ; les blocs vont donc du
plus spécifique au plus général et `Host *` est toujours en dernier. »*

**Étape 5 — externalisation**

`~/.ssh/config.d/lab.conf` reçoit les blocs `bastion` et `lab-web`…`lab-ops`,
`~/.ssh/config` garde l'`Include` en première ligne, puis `Host lab-*` et
`Host *`. `ssh -G lab-db` doit donner exactement la même sortie qu'avant.

**Étape 6 — mesure**

```console
$ ssh -O exit lab-web 2>/dev/null
$ time ( for i in $(seq 10); do ssh -o ControlMaster=no -o ControlPath=none \
         lab-web true; done )
real    0m6,402s
$ ssh -fN lab-web
$ time ( for i in $(seq 10); do ssh lab-web true; done )
real    0m0,381s
```

Rapport ≈ 17. Le rebond par le bastion amplifie le gain : sans multiplexage,
chaque connexion établit **deux** sessions SSH (poste → bastion, poste →
lab-web à travers le bastion).

**Étape 7 — PC Windows**

Fichier `C:\Users\mathieu\.ssh\config`, même syntaxe. Les deux différences à
noter :

1. `ControlMaster`/`ControlPath`/`ControlPersist` **ne fonctionnent pas** avec
   le client OpenSSH pour Windows : le multiplexage repose sur des sockets UNIX.
   Les lignes sont ignorées (ou provoquent un avertissement). Il faut donc
   accepter la perte de performance, ou travailler depuis WSL.
2. L'agent est le service Windows `ssh-agent` (tube nommé, clés stockées
   chiffrées dans le registre) : pas de `SSH_ AUTH_SOCK`, pas d'`eval`, et les
   clés survivent au redémarrage. `AddKeysToAgent yes` fonctionne.

> [!NOTE]
> **Pourquoi**
>
> Le point structurant de ce lab est que `ProxyJump` réfère à un **alias**, pas à
> une adresse : `ProxyJump bastion` fait relire tout le bloc `Host bastion`, avec
> son utilisateur, son port et sa clé. On peut donc changer l'adresse du bastion à
> un seul endroit. C'est la même logique que `Include` : une source de vérité par
> information.
>
> Le bloc `Host lab-*` fonctionne parce que les blocs spécifiques, placés
> au-dessus, ont déjà fixé `HostName` et `ProxyJump` — et que `lab-*` n'y revient
> pas. Il ne pose que ce qui est commun. Noter au passage que `lab-*` matche aussi
> `lab-adm` : comme le bloc `bastion lab-adm` est lu avant, `HostName` et `User`
> sont déjà fixés et rien n'est écrasé. Cette superposition est voulue.
>
> `ServerAliveInterval 30` / `ServerAliveCountMax 3` envoie une sonde **chiffrée,
> dans le canal SSH** toutes les 30 s et coupe après 3 sans réponse. Ça maintient
> les sessions à travers un routeur NAT qui oublie les connexions inactives, et ça
> détecte une coupure réseau en 90 s au lieu de laisser une session fantôme. À ne
> pas confondre avec `TCPKeepAlive`, qui agit au niveau TCP, hors du chiffrement,
> et qu'un intermédiaire peut falsifier.

> [!WARNING]
> **Piège**
>
> `ControlPath ~/.ssh/cm/%C` échoue sans bloquer si `~/.ssh/cm` n'existe pas :
> OpenSSH ne crée pas le répertoire, affiche un simple `unix_listener: cannot bind to path ...` et se connecte quand même,
> sans multiplexage. Le symptôme est « mon multiplexage ne marche pas » alors que la connexion réussit; `ssh -v` montre
> l'échec du bind.
>
> Autre piège : `~/.ssh/config` doit appartenir à l'utilisateur et n'être modifiable ni par le groupe ni par les autres (`600` conseillé, `644` toléré),
> sinon `ssh` refuse de démarrer (`Bad owner or permissions on
> /home/mathieu/.ssh/config`) — plus aucune connexion, alias
> ou pas.

---

### <a id="l14-3"></a>**[L14.3](README.md#l14-3)** — *Durcir le serveur SSH de `lab-web`*

**Étape 3 — le fragment de durcissement**

`/etc/ssh/sshd_config.d/60-durcissement.conf` :

```text
# --- authentification ---------------------------------------------
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes

# --- qui a le droit d'entrer --------------------------------------
AllowGroups ssh-users

# --- résistance au bourrinage -------------------------------------
MaxAuthTries 3
LoginGraceTime 20
MaxSessions 5
MaxStartups 10:30:60

# --- sessions -----------------------------------------------------
ClientAliveInterval 300
ClientAliveCountMax 2

# --- surface d'attaque --------------------------------------------
X11Forwarding no
AllowAgentForwarding no
PermitTunnel no
PermitUserEnvironment no

# --- traçabilité ---------------------------------------------------
LogLevel VERBOSE
```

**Étape 4 — le groupe d'abord**

```bash
sudo groupadd -f ssh-users
sudo usermod -aG ssh-users mathieu
id -nG mathieu | tr ' ' '\n' | grep -qx ssh-users && echo "ok"
sudo sshd -t && sudo systemctl reload ssh
```

Recharger `sshd` **avant** de créer le groupe verrouille la machine : `sshd`
n'accepte plus personne (le groupe n'existe pas, donc `AllowGroups` ne peut être
satisfait par personne), et les sessions en cours sont les seules à survivre.
C'est exactement le scénario de BF14.2.

**Étape 5 — qui gagne dans `sshd_config.d/`**

```console
$ ls -1 /etc/ssh/sshd_config.d/
50-cloud-init.conf
60-durcissement.conf
$ sudo sshd -T | grep -i '^passwordauthentication '
passwordauthentication yes
```

Les fragments sont lus dans l'ordre **lexicographique** du glob, et la première
valeur gagne : `50-cloud-init.conf` est lu avant `60-durcissement.conf`, donc
son `PasswordAuthentication yes` l'emporte (si tu l'as déjà neutralisé en L14.1, `sshd -T` renvoie `no` : le raisonnement reste à écrire). Deux corrections possibles, l'une et
l'autre défendables :

```bash
# a) neutraliser le fragment de cloud-init (il sera régénéré à l'identique
#    au prochain boot si cloud-init est encore actif : à traiter aussi côté
#    cloud-init, /etc/cloud/cloud.cfg.d/)
sudo mv /etc/ssh/sshd_config.d/50-cloud-init.conf \
        /root/.m14-backup/50-cloud-init.conf.desactive
# b) ou nommer le fragment de durcissement pour qu'il passe en premier
sudo mv /etc/ssh/sshd_config.d/60-durcissement.conf \
        /etc/ssh/sshd_config.d/10-durcissement.conf
```

**Étape 7 — algorithmes**

Ajouter au fragment :

```text
KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes256-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
```

et supprimer la clé d'hôte ECDSA si l'on veut un jeu minimal :

```bash
sudo rm -f /etc/ssh/ssh_host_ecdsa_key*
sudo sshd -t && sudo systemctl reload ssh
```

**Étape 8 — preuve dans le journal**

```console
$ sudo journalctl -u ssh -n 5 --no-pager
sshd[8123]: Accepted publickey for mathieu from 10.10.10.10 port 46122 ssh2:
            ED25519 SHA256:8kQ3vN1pW+Rr0Tz9c5aXbLd2Hq7mYfJ4uEsKgVnP1oU
```

> [!NOTE]
> **Pourquoi**
>
> Pourquoi un **fragment** et pas le fichier principal : un fichier séparé se
> versionne, se déploie par outil de configuration, se lit d'un coup d'œil (10
> lignes au lieu de 120), et survit sans conflit à une mise à jour du paquet
> `openssh-server`. La contrepartie est la règle de précédence, qui devient la
> première chose à vérifier — d'où l'étape 5.
>
> Les directives, une par une :
>
> * `LoginGraceTime 20` : au-delà de 20 s sans authentification aboutie, le
>   serveur ferme. C'est ce qui limite les connexions ouvertes non authentifiées,
>   levier classique de saturation. `MaxStartups 10:30:60` va dans le même sens :
>   à partir de 10 connexions en cours d'authentification, 30 % sont rejetées au
>   hasard ; à 60, tout est rejeté.
> * `ClientAliveInterval 300` / `ClientAliveCountMax 2` : le **serveur** sonde le
>   client et ferme après 10 minutes sans réponse. Ça nettoie les sessions
>   fantômes d'un poste éteint brutalement — et ça libère les processus associés.
>   Symétrique de `ServerAliveInterval` côté client. Nuance à connaître : un client vivant mais inactif répond aux sondes et n'est **pas** déconnecté; la vraie déconnexion sur inactivité de l'utilisateur relève du shell (`TMOUT`), pas de `sshd`.
> * `LogLevel VERBOSE` est le meilleur rapport valeur/risque de la liste : il
>   ajoute l'**empreinte de la clé utilisée** à chaque ligne `Accepted publickey`.
>   Sans lui, impossible de répondre à « quelle clé a servi à cette connexion »,
>   donc impossible d'auditer un accès ou de tracer une clé compromise. Il ne
>   journalise aucun secret.
> * `PermitUserEnvironment no` (défaut) : sinon un utilisateur peut poser
>   `LD_PRELOAD` dans `~/.ssh/environment` et détourner l'exécution.
>
> Le jeu d'algorithmes retient les échanges de clés sur Curve25519 (dont
> `sntrup761x25519`, hybride post-quantique, par défaut depuis OpenSSH 9.0), des
> chiffrements authentifiés (AEAD : `chacha20-poly1305`, `aes-gcm`) et des MAC en
> mode **EtM** (*encrypt-then-MAC*, suffixe `-etm`), qui authentifient le
> chiffré — construction saine, contrairement au MAC-then-encrypt historique.
> Les `diffie-hellman-group14-sha1`, `hmac-sha1` et `cbc` disparaissent.

> [!WARNING]
> **Piège**
>
> Sur-durcir coupe des clients légitimes. `Unable to negotiate with 10.10.10.11
> port 22: no matching key exchange method found` est le message qu'on obtient
> depuis un poste plus ancien. Avant de restreindre, on vérifie ce que les clients
> du parc savent faire (`ssh -Q kex`, `ssh -Q cipher`) et on utilise la syntaxe
> additive/soustractive quand c'est plus sûr : `Ciphers -aes128-cbc,3des-cbc`
> retire des algorithmes du jeu par défaut sans figer la liste, ce qui laisse les
> futures versions d'OpenSSH ajouter leurs nouveautés.
>
> Supprimer `ssh_host_ecdsa_key` change l'empreinte présentée aux clients qui
> préféraient ECDSA : ils verront un changement de clé d'hôte. À faire en
> connaissance de cause, avec communication.

> [!IMPORTANT]
> **Variante Rocky / RHEL**
>
> Sous Rocky 9, la politique cryptographique système est incluse par
> `/etc/ssh/sshd_config`.`d/50-redhat.conf` (`Include`
> `/etc/crypto-policies/back-ends/opensshserver.config`). Comme la première valeur gagne, un `Ciphers`, `MACs` ou `KexAlgorithms` écrit dans `sshd_config` ou dans un fragment nommé après `50-` est **sans effet**. Deux voies : un fragment qui passe avant (`40-algos.conf`), ou — préférable — passer la
> machine en politique forte avec `sudo update-crypto-policies --set FUTURE` (ou
> une sous-politique dans `/etc/crypto-policies/policies/``modules/` ), ce qui durcit
> `sshd`, `openssl` et `gnutls` de façon cohérente. (Le `CRYPTO_POLICY=` de `/etc/sysconfig/sshd` est le mécanisme de RHEL 8.) L'unité s'appelle
> `sshd.service`, le journal se lit avec `journalctl -u sshd`.

---

### <a id="l14-4"></a>**[L14.4](README.md#l14-4)** — *Trois tunnels pour trois demandes*

**Ticket 1 — tunnel local**

```bash
ssh -f -N -o ExitOnForwardFailure=yes -L 15432:10.10.10.12:5432 bastion
printf '' | timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/15432; head -1 <&3'
```

```console
LAB14-DB-OK lab-db
```

**Étape 2 — la différence avec `127.0.0.1`**

`-L 15432:127.0.0.1:5432 bastion` ferait ouvrir la connexion finale **par le
bastion, vers lui-même**. `127.0.0.1` est toujours interprété par la machine qui
établit la connexion finale, c'est-à-dire le serveur SSH. On joindrait donc un
PostgreSQL tournant sur `lab-adm`, pas sur `lab-db`.

**Ticket 2 — tunnel inverse**

```bash
ssh -f -N -o ExitOnForwardFailure=yes -R 8080:127.0.0.1:3000 lab-ops
ssh lab-ops 'curl -s http://127.0.0.1:8080/'
```

**Étape 4 — pourquoi ça échoue depuis `lab-web`**

```console
$ ssh lab-web 'curl -s --max-time 3 http://10.10.10.14:8080/'
curl: (7) Failed to connect to 10.10.10.14 port 8080: Connection refused
$ ssh lab-ops "ss -tlnp | grep 8080"
LISTEN 0 128 127.0.0.1:8080 0.0.0.0:*
```

`GatewayPorts no` (défaut) lie le port à la boucle locale de `lab-ops`. Pour
ouvrir, côté serveur :

```text
# /etc/ssh/sshd_config.d/70-lab.conf  sur lab-ops
GatewayPorts clientspecified
```

puis `sudo sshd -t && sudo systemctl reload ssh`, et côté client :

```bash
ssh -f -N -o ExitOnForwardFailure=yes -R 0.0.0.0:8080:127.0.0.1:3000 lab-ops
```

Pourquoi ne pas laisser ça en place : on vient de publier sur tout le réseau de
lab un service qui tournait sur un poste de travail, sans authentification, sans
chiffrement TLS, sans journalisation, et sans que le pare-feu de `lab-ops` n'ait
rien à dire. Le tunnel survit tant que la session tient — y compris la nuit.
C'est le mécanisme exact utilisé par les portes dérobées pour ouvrir un accès
entrant depuis une machine qui n'autorise que le sortant. La bonne réponse
durable est un reverse proxy déclaré, ou une copie du service sur `lab-ops`.

**Ticket 3 — SOCKS**

```bash
ssh -f -N -D 1080 bastion
curl -s --socks5-hostname 127.0.0.1:1080 http://10.10.10.11/ | head -3
curl -s --socks5-hostname 127.0.0.1:1080 http://lab-web.lab.local/ | head -3
```

La seconde commande prouve la résolution distante : `lab-web.lab.local` n'est
résolvable que par le DNS du lab. Avec `--socks5` (sans `-hostname`), elle
échoue en `Could not resolve host`.

**Étape 6 — fermeture**

```bash
ssh -O cancel -L 15432:10.10.10.12:5432 bastion
ssh -O cancel -R 8080:127.0.0.1:3000 lab-ops
pkill -f 'ssh -f -N -D 1080'
ss -tlnp | grep -E ':(15432|1080)\b' || echo "aucun port résiduel"
```

> [!NOTE]
> **Pourquoi**
>
> La règle qui range tout : **le premier port de l'option est celui qu'on ouvre,
> et la lettre dit chez qui.** `-L` ouvre chez le client, `-R` ouvre chez le
> serveur. Le couple `hôte:port` qui suit est la destination finale, toujours
> interprétée depuis la machine qui établit la connexion finale — le serveur SSH
> pour `-L` et `-D`, le client pour `-R`.
>
> Conséquence de sécurité à énoncer clairement dans le rapport : `-L` et `-D`
> donnent au client l'accès réseau du serveur (contournement de segmentation,
> d'où `AllowTcpForwarding no` sur tout ce qui n'est pas un bastion) ; `-R` donne
> au serveur l'accès réseau du client et ouvre un point d'entrée entrant (d'où
> `GatewayPorts no` et, sur les serveurs sensibles,
> `AllowTcpForwarding remote`/`local` pour n'autoriser qu'un sens).
>
> `PermitOpen host:port` mérite d'être connu : il limite les destinations
> accessibles par `-L`/`-D` à une liste blanche. Sur un bastion, c'est ce qui
> transforme « accès à tout le réseau interne » en « accès au port 5432 de
> lab-db ».

> [!WARNING]
> **Piège**
>
> Trois erreurs qui coûtent du temps :
>
> * oublier `ExitOnForwardFailure=yes` avec `-f` : le message
>   `bind: Address already in use` part sur une sortie d'erreur qui n'est plus
>   affichée, la session reste ouverte, et le client se connecte au service qui
>   occupait déjà le port ;
> * croire que fermer le terminal ferme le tunnel : avec `-f`, le processus est
>   détaché, il survit. `ss -tlnp` et `pgrep -af 'ssh -f'` font partie du ménage
>   de fin de journée ;
> * utiliser un tunnel `-L` avec un client qui vérifie le nom du certificat TLS :
>   le client voit `127.0.0.1:15432` et rejettera un certificat émis pour
>   `db.lab.local`. On corrige avec une entrée `/etc/hosts` locale, pas en
>   désactivant la vérification.

---

### <a id="l14-5"></a>**[L14.5](README.md#l14-5)** — *Une clé de service qui ne peut faire qu'une seule chose*

**Étape 1 — la clé, sur `lab-ops`**

```bash
ssh-keygen -t ed25519 -N '' -C "ci-sauvegarde@lab-ops" \
  -f ~/.ssh/id_ci_sauvegarde
```

Justification à écrire dans le rapport : *une clé de service ne peut pas avoir
de passphrase, puisqu'aucun humain n'est là pour la saisir au déclenchement du
job. Ce qui compense : la clé est restreinte à une origine (`from=`), à une
commande (`command=`), sans terminal ni redirection (`restrict`), elle n'ouvre
qu'un compte non privilégié, et elle est renouvelée périodiquement.*

**Étape 2 — le script de commande forcée, sur `lab-web`**

```bash
sudo tee /usr/local/bin/lab14-recevoir >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DEST=/srv/sauvegarde
LOG=/var/log/lab14-recevoir.log
cmd="${SSH_ORIGINAL_COMMAND:-}"
journalise() { printf '%s %s\n' "$(date -Is)" "$1" >> "$LOG"; }

case "$cmd" in
  liste)
      journalise "liste OK"
      ls -1 "$DEST"
      ;;
  "depot "*)
      nom=${cmd#depot }
      case "$nom" in
        *[!A-Za-z0-9._-]*|""|.*)
            journalise "depot REFUSE nom=$nom"; echo "nom invalide" >&2
            exit 3 ;;
      esac
      cat > "$DEST/$nom.part" && mv "$DEST/$nom.part" "$DEST/$nom"
      journalise "depot OK nom=$nom"
      ;;
  *)
      journalise "REFUS cmd=${cmd:-<session interactive>}"
      echo "commande non autorisee" >&2
      exit 42
      ;;
esac
EOF
sudo chmod 755 /usr/local/bin/lab14-recevoir
sudo install -o sauvegarde -g sauvegarde -m 640 /dev/null \
     /var/log/lab14-recevoir.log
```

**Étape 3 — `authorized_keys`**

```bash
# sur lab-web ; le fichier doit contenir UNE seule ligne
sudo install -d -o sauvegarde -g sauvegarde -m 700 /home/sauvegarde/.ssh
OPTS='restrict,from="10.10.10.14",command="/usr/local/bin/lab14-recevoir"'
CLE='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN8x... ci-sauvegarde@lab-ops'
printf '%s %s\n' "$OPTS" "$CLE" \
  | sudo tee /home/sauvegarde/.ssh/authorized_keys >/dev/null
sudo chown sauvegarde:sauvegarde /home/sauvegarde/.ssh/authorized_keys
sudo chmod 600 /home/sauvegarde/.ssh/authorized_keys
```

**Étape 4 — les quatre preuves**

```console
$ ssh -i ~/.ssh/id_ci_sauvegarde sauvegarde@10.10.10.11 liste
sauvegarde-2026-09-17.tar.gz

$ ssh -i ~/.ssh/id_ci_sauvegarde sauvegarde@10.10.10.11 'rm -rf /srv/sauvegarde'
commande non autorisee
$ echo $?
42

$ ssh -i ~/.ssh/id_ci_sauvegarde -f -N -L 9999:127.0.0.1:22 \
>     sauvegarde@10.10.10.11
$ nc -w2 127.0.0.1 9999 </dev/null
channel 2: open failed: administratively prohibited: open failed
# et depuis lab-adm, avec la même clé :
$ ssh -i /tmp/id_ci_sauvegarde sauvegarde@10.10.10.11 liste
sauvegarde@10.10.10.11: Permission denied (publickey).
```

**Étape 5 — la vraie sauvegarde**

```bash
tar -czf - -C /srv/app . | \
  ssh -i ~/.ssh/id_ci_sauvegarde sauvegarde@10.10.10.11 \
      "depot app-$(date +%F).tar.gz"
```

> [!NOTE]
> **Pourquoi**
>
> Le principe est celui du **moindre privilège appliqué à une clé**, pas à un
> compte. Un compte de service classique donne un shell : quiconque met la main
> sur la clé obtient une session sur `lab-web`, et cherche ensuite une élévation.
> Ici, la clé n'ouvre pas de session : elle déclenche un programme, avec un jeu
> d'entrées contraint.
>
> Trois couches se cumulent, et c'est le cumul qui fait la sécurité :
>
> 1. `from=` réduit la surface : la clé volée est inerte ailleurs. `sshd` compare
>    l'adresse source du socket TCP, information que le client ne contrôle pas.
> 2. `restrict` supprime tout ce qui n'est pas la commande : pas de terminal, pas
>    de tunnel, pas d'agent. Sans lui, `command=` laisserait passer
>    `ssh -N -L ...`, qui n'exécute jamais la commande forcée.
> 3. le script valide la demande par **liste blanche**, valide le nom de fichier
>    (pas de `..`, pas de `/`, pas de nom vide ou caché), et journalise chaque
>    refus. Le dépôt passe par un `.part` renommé à la fin : un transfert
>    interrompu ne laisse pas d'archive tronquée qui aurait l'air valable.
>
> La rotation de cette clé : générer la nouvelle paire sur `lab-ops`, **ajouter**
> la nouvelle ligne dans `authorized_keys` (deux clés valides simultanément),
> basculer la CI, vérifier une exécution complète, puis retirer l'ancienne ligne.
> Jamais de remplacement direct : la fenêtre entre les deux est une coupure de
> service.

> [!WARNING]
> **Piège**
>
> Ne pas confondre `from=` et un filtrage par pare-feu : `from=` protège **la
> clé**, pas le service. Les deux sont complémentaires.
>
> Et le piège de journalisation : `journalise` écrit dans un fichier appartenant
> au compte `sauvegarde`. Un attaquant qui obtiendrait ce compte pourrait effacer
> ses traces. Pour un usage réel, on journalise avec `logger` vers `journald`
> (auquel le compte ne peut pas toucher), ou vers un collecteur distant.

> [!IMPORTANT]
> **Variante Rocky / RHEL**
>
> Si `lab-web` était sous Rocky 9, SELinux entrerait en jeu : un
> `authorized_keys` déposé à la main depuis `/tmp` hérite d'un contexte
> `user_tmp_t` et `sshd` ne peut pas le lire — symptôme identique à un problème de
> permissions, `Permission denied (publickey)`, avec un refus visible dans
> `sudo ausearch -m avc -ts recent`. Correction :
> `sudo restorecon -Rv /home/sauvegarde/.ssh`.

---

## 14.7 Break & Fix

### <a id="bf14-1"></a>**[BF14.1](README.md#bf14-1)** — *Permissions de `~/.ssh` cassées côté serveur*

**Démarche de diagnostic**

1. Côté client, confirmer que le problème est bien distant :

```console
$ ssh -v lab-web 2>&1 | grep -E 'Offering|Authentications that'
debug1: Offering public key: /home/mathieu/.ssh/id_ed25519
        ED25519 SHA256:8kQ3vN1... agent
debug1: Authentications that can continue: publickey
```

La clé est proposée et refusée : le client va bien, on arrête de le triturer.

2. Entrer par la console Proxmox de `lab-web` (c'est le seul chemin restant,
   l'authentification par mot de passe étant coupée), puis lire le journal :

```console
# journalctl -u ssh -n 30 --no-pager | grep -i refused
sshd[9012]: Authentication refused: bad ownership or modes for file
            /home/mathieu/.ssh/authorized_keys
```

3. Constater :

```console
# ls -ld /home/mathieu /home/mathieu/.ssh /home/mathieu/.ssh/authorized_keys
drwxrwxr-x 5 mathieu mathieu 4096 sep 18 09:12 /home/mathieu
drwxr-xrwx 2 mathieu mathieu 4096 sep 18 09:12 /home/mathieu/.ssh
-rw-rw-rw- 1 mathieu mathieu  568 sep 18 09:12
           /home/mathieu/.ssh/authorized_keys
```

**Cause racine**

`StrictModes yes` (valeur par défaut) impose que ni le répertoire personnel, ni
`~/.ssh`, ni `authorized_keys` ne soient accessibles en écriture à quelqu'un
d'autre que leur propriétaire. Ici les trois le sont. `sshd` refuse donc de lire
le fichier de clés, et — protocole oblige — ne dit rien au client d'autre que
`Permission denied (publickey)`.

**Correctif**

```bash
chmod 700 /home/mathieu/.ssh
chmod 600 /home/mathieu/.ssh/authorized_keys
chmod go-w /home/mathieu
chown -R mathieu:mathieu /home/mathieu/.ssh
```

Vérification immédiate depuis `lab-adm`, **avant** de fermer la console :

```console
$ ssh -o BatchMode=yes lab-web 'echo OK'
OK
```

**Règle vérifiable par script**

*Le home n'est pas accessible en écriture au groupe ni aux autres ; `~/.ssh` est
en 700 ; `authorized_keys` est en 600 ; tout appartient à l'utilisateur.*

```bash
#!/usr/bin/env bash
set -euo pipefail
u=${1:?utilisateur}
h=$(getent passwd "$u" | cut -d: -f6)
[ "$(stat -c '%U %a' "$h"        | awk '{print $1}')" = "$u" ] || exit 1
[ "$(( 0$(stat -c %a "$h") & 022 ))" -eq 0 ]                   || exit 1
[ "$(stat -c %a "$h/.ssh")" = 700 ]                            || exit 1
[ "$(stat -c %a "$h/.ssh/authorized_keys")" = 600 ]             || exit 1
```

> [!NOTE]
> **Pourquoi**
>
> La raison d'être de `StrictModes` est logique et vaut d'être sue : quiconque
> peut **écrire** dans `~/.ssh` peut y ajouter sa propre clé publique, et devient
> l'utilisateur. Un `~/.ssh` en `777` est donc strictement équivalent à donner son
> mot de passe à toute la machine. Le contrôle remonte au home parce qu'écrire
> dans le home permet de remplacer `.ssh` entièrement.
>
> Le mécanisme de silence du protocole est l'autre leçon : `sshd` ne dira jamais
> au client pourquoi il refuse, pour ne pas aider un attaquant à cartographier la
> machine. D'où la règle de ce module : **un `Permission denied (publickey)` se
> diagnostique sur le serveur**, dans `journalctl -u ssh`.

> [!WARNING]
> **Piège**
>
> Causes habituelles de ce désordre en production, à citer en prévention :
>
> * restauration d'une sauvegarde sans préservation des modes (`tar` sans `-p` en
>   tant que non-root, `cp -r` au lieu de `cp -a`, copie depuis un partage
>   Windows/CIFS qui n'a pas de bits UNIX) ;
> * un `chmod -R 775 /home/projet` passé un peu vite ;
> * un `umask` permissif dans un script de création de comptes.
>
> Et le contre-exemple utile : `authorized_keys` en `644` est **accepté** (il n'y a
> pas de secret dedans), c'est l'écriture par autrui qui est refusée. Ce qui n'est
> pas une raison pour ne pas le mettre en `600`.

---

### <a id="bf14-2"></a>**[BF14.2](README.md#bf14-2)** — *`AllowUsers` déposé dans un fragment*

**Démarche de diagnostic**

1. Le client ne dit rien d'utile — on va tout de suite au journal, via la
   console ou une session restée ouverte :

```console
# journalctl -u ssh -n 30 --no-pager
sshd[9411]: User mathieu from 10.10.10.10 not allowed because not listed in
            AllowUsers
sshd[9411]: Connection closed by invalid user mathieu 10.10.10.10
            port 51234 [preauth]
```

2. La directive n'est pas dans `/etc/ssh/sshd_config` (l'énoncé le dit, et c'est
   vrai). La commande qui donne la réponse en 5 secondes :

```console
# sshd -T | grep -i '^allowusers'
allowusers root deploiement
```

3. Localiser la source :

```console
# grep -rn AllowUsers /etc/ssh/
/etc/ssh/sshd_config.d/00-maintenance.conf:3:AllowUsers root deploiement
```

**Cause racine**

`/etc/ssh/sshd_config` commence par `Include /etc/ssh/sshd_config.d/*.conf`.
Les fragments sont donc lus **avant** le reste du fichier, dans l'ordre
lexicographique, et `sshd` retient pour chaque mot-clé la **première** valeur
rencontrée. Un fragment nommé `00-...` gagne contre tout le reste, y compris
contre un `AllowUsers` écrit dans le fichier principal — et il n'apparaît pas
quand on relit `sshd_config` ligne par ligne.

**Correctif**

On ne réouvre pas la machine à tout le monde : on remplace le filtrage par
utilisateurs, ingérable, par un filtrage par groupe.

```bash
sudo groupadd -f ssh-users
sudo usermod -aG ssh-users mathieu
sudo sed -i 's/^AllowUsers.*/AllowGroups ssh-users/' \
     /etc/ssh/sshd_config.d/00-maintenance.conf
sudo sshd -t && sudo systemctl reload ssh
sudo sshd -T | grep -Ei '^(allowusers|allowgroups) '
```

Puis, **avant de fermer la console** : `ssh lab-web true` depuis `lab-adm`.

**Prévention**

* nommer les fragments selon une convention d'équipe explicite et documentée,
  en réservant les préfixes bas (`00`-`19`) à ce qui doit vraiment primer ;
* interdire `AllowUsers` au profit d'`AllowGroups` : ajouter un administrateur
  devient `usermod -aG`, sans toucher à `sshd` ni le recharger ;
* faire de `sshd -T` le premier réflexe de tout diagnostic, avant `grep`.

> [!NOTE]
> **Pourquoi**
>
> L'ordre d'évaluation complet des filtres de comptes, à connaître :
> `DenyUsers`, puis `AllowUsers`, puis `DenyGroups`, puis `AllowGroups`. Dès
> qu'`AllowUsers` est présent, **tout compte non listé est refusé**, quelles que
> soient ses clés et ses permissions — et le refus a lieu avant toute
> authentification, d'où la rapidité du rejet observée dans le symptôme.
>
> Les motifs acceptent le joker et la forme `utilisateur@hôte` :
> `AllowUsers mathieu@10.10.10.* deploiement@10.10.10.14`, ce qui permet un
> filtrage assez fin sans pare-feu. Attention : la partie hôte est comparée à
> l'adresse source, et la résolution inverse n'est pas fiable — on y met des
> adresses.
>
> Le message `Connection closed by invalid user` est trompeur : l'utilisateur
> existe parfaitement. `sshd` le traite comme « invalide » parce qu'il a été
> écarté avant l'authentification, et bascule dans son mode de traitement des
> comptes inconnus — qui simule des délais pour ne pas permettre l'énumération des
> comptes.

> [!WARNING]
> **Piège**
>
> Recharger `sshd` avec un `AllowGroups` dont le groupe **n'existe pas encore**
> verrouille la machine instantanément : plus personne ne satisfait le filtre, et
> seules les sessions déjà ouvertes survivent. Toujours créer le groupe et vérifier
> `id -nG utilisateur` **avant** le `reload`. Et `usermod -aG` n'affecte pas les
> sessions déjà ouvertes : `sshd` lit les groupes à la connexion, donc c'est la
> **nouvelle** connexion qui compte ici — ce qui joue en ta faveur pour une fois.

---

### <a id="bf14-3"></a>**[BF14.3](README.md#bf14-3)** — *Clé d'hôte changée*

**Démarche de diagnostic**

1. Lire le message en entier. Il contient l'essentiel :

```console
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
The ED25519 host key for lab-web has changed,
and the key for the corresponding IP address 10.10.10.11 is unknown.
The fingerprint for the ED25519 key sent by the remote host is
SHA256:R3wQ1mB7nZ0kL5xY8vC2aT4uJ6hD9sF0gE1pN7rM3iQ.
Offending ED25519 key in /home/mathieu/.ssh/known_hosts:12
```

Deux informations à noter : l'empreinte **présentée maintenant**, et le numéro
de ligne de l'entrée enregistrée.

2. Ce que je connais :

```bash
ssh-keygen -F lab-web | ssh-keygen -lf -
```

3. **La vérification hors bande**, la seule qui décide. Console Proxmox de
   `lab-web` (elle ne passe pas par le réseau, donc pas par un éventuel
   intercepteur) :

```console
# ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
256 SHA256:R3wQ1mB7nZ0kL5xY8vC2aT4uJ6hD9sF0gE1pN7rM3iQ root@lab-web (ED25519)
# ls -l --time-style=full-iso /etc/ssh/ssh_host_*_key
-rw------- 1 root root 399 2026-09-18 11:42:07 ... /etc/ssh/ssh_host_ed25519_key
```

L'empreinte lue sur la machine correspond à celle qu'on m'a présentée : il n'y a
pas d'interception. La date de création des clés donne le moment du changement,
et le journal dit qui l'a provoqué :

```console
# journalctl --since "-2h" | grep -iE 'ssh_host|ssh-keygen|dpkg.*openssh'
```

**Cause racine**

Les clés d'hôte de `lab-web` ont été régénérées (réinstallation du paquet,
reconstruction de la VM, `ssh-keygen -A` après suppression, restauration). Le
changement est réel et légitime ; ce n'est pas une attaque.

**Correctif**

```bash
ssh-keygen -R lab-web
ssh-keygen -R 10.10.10.11        # l'entrée par adresse est distincte
ssh lab-web                       # et on VÉRIFIE l'empreinte proposée
```

```console
The authenticity of host 'lab-web (10.10.10.11)' can't be established.
ED25519 key fingerprint is SHA256:R3wQ1mB7nZ0kL5xY8vC2aT4uJ6hD9sF0gE1pN7rM3iQ.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

On ne tape pas `yes` : on colle l'empreinte relevée sur la console. Si elle
diffère d'un caractère, `ssh` refuse. C'est à ça que sert la troisième option de
l'invite, que presque personne n'utilise.

**Prévention à l'échelle du parc**

Faire signer les clés d'hôte par une CA SSH :

```bash
ssh-keygen -t ed25519 -f ca_hosts -C "CA hotes lab.local"          # une fois
ssh-keygen -s ca_hosts -I lab-web -h -n lab-web,10.10.10.11 \
  -V +52w /etc/ssh/ssh_host_ed25519_key.pub
# sur lab-web : HostCertificate /etc/ssh/ssh_host_ed25519_key-cert.pub
# chez tous les clients, UNE ligne dans known_hosts :
# @cert-authority *.lab.local,10.10.10.* ssh-ed25519 AAAA...
```

Une VM reconstruite reçoit un nouveau certificat signé par la même CA : aucun
client ne voit d'alerte, et une vraie interception échoue toujours faute de
signature valide. Variante plus légère : distribuer un
`/etc/ssh/ssh_known_hosts` géré par l'outil de configuration.

> [!NOTE]
> **Pourquoi**
>
> Pourquoi le canal de vérification doit être indépendant : si un attaquant est en
> position d'interception, il répondra à `ssh-keyscan` exactement comme il a
> répondu à `ssh`. Toute vérification passant par le même chemin réseau ne prouve
> rien. La console de l'hyperviseur, l'inventaire d'un outil de gestion de
> configuration, un enregistrement SSHFP dans un DNS signé (DNSSEC) ou un appel à
> la personne qui a fait l'opération sont des canaux acceptables.
>
> Deuxième point de mécanisme : `known_hosts` indexe **par nom et par adresse**,
> séparément. Le message ci-dessus le dit explicitement (`the key for the
> corresponding IP address 10.10.10.11 is unknown`). Ne traiter qu'une des deux
> entrées fait revenir l'alerte à la première connexion par l'autre forme.

> [!WARNING]
> **Piège**
>
> Le réflexe `ssh-keygen -R` immédiat n'est pas une erreur *technique* : c'est
> d'ailleurs ce qu'on finit par faire. L'erreur est de le faire **avant** la
> vérification, parce qu'on détruit alors la seule preuve dont on disposait —
> l'ancienne empreinte — et qu'on transforme un contrôle de sécurité en formalité.
> Dans une équipe où le geste est automatique, une interception réelle passera
> inaperçue.
>
> `StrictHostKeyChecking=no` est pire : il ne masque pas seulement l'alerte de
> changement, il accepte aussi silencieusement tout hôte inconnu, pour toutes les
> connexions couvertes par le bloc de configuration. En CI, la bonne valeur est
> `accept-new` au minimum, et un `known_hosts` provisionné et vérifié pour les
> accès sensibles.

---

### <a id="bf14-4"></a>**[BF14.4](README.md#bf14-4)** — *`Too many authentication failures`*

**Démarche de diagnostic**

1. Compter les tentatives — la sortie verbeuse est sans ambiguïté :

```console
$ ssh -v lab-web 2>&1 | grep -c 'Offering public key'
3
$ ssh -v lab-web 2>&1 | grep -E 'Offering public key|Received disconnect'
debug1: Offering public key: /home/mathieu/.ssh/legacy/cle1
        ED25519 SHA256:aB1... agent
debug1: Offering public key: /home/mathieu/.ssh/legacy/cle2
        ED25519 SHA256:cD2... agent
debug1: Offering public key: /home/mathieu/.ssh/legacy/cle3
        ED25519 SHA256:eF3... agent
Received disconnect from 10.10.10.11 port 22:2: Too many authentication failures
```

2. Voir d'où viennent ces identités :

```console
$ ssh-add -l | wc -l
6
$ ssh -G lab-web | grep -E '^(identityfile|identitiesonly) '
identityfile ~/.ssh/legacy/cle1
identityfile ~/.ssh/legacy/cle2
...
identityfile ~/.ssh/id_ed25519
identitiesonly no
```

Un bloc `Host *` glissé **en tête** de `~/.ssh/config` : ses `IdentityFile` passent devant, et son `IdentitiesOnly no` gagne sur le `yes` du bloc `lab-*`, lu après (première valeur rencontrée). 3. Regarder ce que compte chaque serveur :

```console
# sur lab-web (durci en L14.3) :  sshd -T | grep -i maxauthtries
maxauthtries 3
# sur lab-db (défaut) :           sshd -T | grep -i maxauthtries
maxauthtries 6
```

**Cause racine**

`MaxAuthTries` compte les **tentatives d'authentification**, et chaque clé
proposée en compte une, même quand elle n'a aucune chance d'aboutir. Avec 5 clés
parasites en tête de liste et `MaxAuthTries 3` sur `lab-web`, le serveur coupe la session après la troisième, bien
avant que la bonne clé — la sixième — ne soit présentée. Sur `lab-db`, resté à `MaxAuthTries 6`, les 5 échecs passent et la sixième tentative réussit : d'où « ça marche encore, mais plus lentement ». L'agent aggrave le
phénomène : ses identités sont proposées en plus de celles du fichier de
configuration.

**Pourquoi `-i` seul n'a pas suffi**

`IdentityFile` est **additif** : `-i ~/.ssh/id_ed25519` ajoute cette clé 
mais ne supprime aucune des autres sources (fichier de configuration, agent).
Et l'ordre ne joue pas en ta faveur : `ssh` propose d'abord les clés de l'agent, puis les fichiers — les parasites chargées dans l'agent passent donc devant la clé désignée par `-i`. Seul `IdentitiesOnly=yes`
rend la liste exclusive.

**Correctif immédiat**

```bash
ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 lab-web
```

**Correctif durable** — dans `~/.ssh/config` :

```text
Host lab-*
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

et nettoyer la source du bruit : retirer les `IdentityFile` parasites du
fichier de configuration, retirer la ligne `ssh-add ~/.ssh/legacy/*` du
`~/.bashrc`, purger l'agent :

```bash
ssh-add -D
ssh-add -t 28800 ~/.ssh/id_ed25519
ssh -G lab-web | grep -c '^identityfile '     # doit valoir 1
```

> [!NOTE]
> **Pourquoi**
>
> Le point conceptuel : `IdentityFile` **ajoute**, `IdentitiesOnly` **restreint**.
> Cette asymétrie est voulue — elle permet d'accumuler des clés sans que chaque
> ajout ne casse les configurations existantes — et elle est la cause de la
> quasi-totalité des `Too many authentication failures`.
>
> Deuxième point, plus subtil : la proposition d'une clé publique n'est pas
> gratuite en information. Chaque `Offering public key` révèle au serveur une clé
> publique que tu détiens. Un serveur hostile peut ainsi collecter la liste de tes
> identités et t'identifier d'un site à l'autre. `IdentitiesOnly yes` par hôte
> n'est donc pas seulement une optimisation, c'est une mesure de cloisonnement.
>
> Troisième point, que confirme le symptôme secondaire de l'énoncé (« `lab-db`
> fonctionne encore, mais plus lentement ») : les 5 tentatives coûtent 5 allers-
> retours avant la bonne. La correction accélère aussi les
> machines qui fonctionnaient.

> [!WARNING]
> **Piège**
>
> Augmenter `MaxAuthTries` côté serveur « pour que ça passe » traite le symptôme
> et affaiblit la machine : cette limite est ce qui rend coûteux le bourrinage par
> clés. La valeur par défaut de 6 est déjà généreuse ; 3 est raisonnable sur un
> serveur en clés uniquement.
>
> Et attention au compteur : il inclut **toutes** les méthodes, pas seulement les
> clés. Sur un serveur acceptant encore le mot de passe, les propositions de clés
> consomment le budget avant que l'invite de mot de passe n'apparaisse — d'où des
> utilisateurs qui n'ont « même pas eu le droit d'essayer leur mot de passe ».

---

## 14.8 Défi du module

<a id="d14"></a>**[D14](README.md#d14) — Faire de `lab-adm` un vrai bastion**

### 1. Configuration client de référence

`~/lab14/conf/ssh_config.reference` :

```text
# Fragments spécifiques au site, chargés en premier.
Include ~/.ssh/config.d/*.conf

# Le bastion : seule machine du parc jointe directement.
Host bastion lab-adm
    HostName 10.10.10.10
    User mathieu
    Port 22
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

# Les serveurs : jamais joints directement, toujours via le bastion.
Host lab-web
    HostName 10.10.10.11
    ProxyJump bastion
Host lab-db
    HostName 10.10.10.12
    ProxyJump bastion
Host lab-rhel
    HostName 10.10.10.13
    ProxyJump bastion
Host lab-ops
    HostName 10.10.10.14
    ProxyJump bastion

# Réglages communs à toutes les machines du lab.
Host lab-*
    User mathieu
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ForwardAgent no

# Pas de multiplexage pour les transferts rsync : un gros transfert
# monopoliserait la session maître et ralentirait les autres sessions.
Match exec "pgrep -x rsync >/dev/null"
    ControlMaster no
    ControlPath none

# Réglages globaux : toujours en dernier, la première valeur gagne.
Host *
    ServerAliveInterval 30
    ServerAliveCountMax 3
    ControlMaster auto
    ControlPath ~/.ssh/cm/%C
    ControlPersist 10m
    AddKeysToAgent yes
    HashKnownHosts yes
    StrictHostKeyChecking ask
```

Adaptation Windows, trois lignes : retirer les trois directives `Control*`
(sockets UNIX indisponibles), écrire les chemins sous la forme
`C:\Users\mathieu\.ssh\id_ed25519` si `~` pose problème, et ne rien changer
d'autre.

> [!NOTE]
> **Pourquoi**
>
> Le bloc `Match exec` est le seul morceau non évident. `Match exec "commande"`
> exécute la commande **localement** au moment de la résolution de configuration
> et applique le bloc si elle sort en 0. Il permet des conditions que `Host` ne
> sait pas exprimer : présence d'un processus, appartenance à un réseau
> (`Match exec "ip route get 10.10.10.1 >/dev/null 2>&1"`), poste professionnel ou
> personnel.
>
> Son coût est réel : la commande est exécutée à **chaque** résolution, y compris
> par `ssh -G` et par la complétion du shell. Elle doit être instantanée et muette.
>
> Note d'honnêteté technique à porter au rapport : ce `Match exec` détecte un
> `rsync` déjà en cours, pas le `rsync` que l'on s'apprête à lancer. La manière
> réellement propre d'exclure un transfert du multiplexage est de le lancer avec
> `rsync -e 'ssh -o ControlMaster=no -o ControlPath=none'`. Le `Match exec` est ici
> un exercice de syntaxe, et savoir dire pourquoi il est imparfait vaut mieux que
> de le recopier.

### 2. Durcissement du bastion

`~/lab14/conf/60-bastion.conf`, déployé dans `/etc/ssh/sshd_config.d/` :

```text
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes

AllowGroups ssh-users

MaxAuthTries 3
LoginGraceTime 20
MaxStartups 10:30:60
ClientAliveInterval 300
ClientAliveCountMax 2

# Un bastion DOIT relayer le TCP : c'est son métier (-J, -L).
AllowTcpForwarding yes
# Mais il ne doit jamais détenir les clés de ses utilisateurs.
AllowAgentForwarding no
X11Forwarding no
PermitTunnel no

LogLevel VERBOSE
```

Application, dans l'ordre :

```bash
sudo groupadd -f ssh-users && sudo usermod -aG ssh-users mathieu
sudo install -m 644 ~/lab14/conf/60-bastion.conf /etc/ssh/sshd_config.d/
sudo sshd -t && sudo systemctl reload ssh
sudo sshd -T -C user=mathieu,host=lab-adm,addr=10.10.10.1 > /tmp/eff.txt
grep -Ei '^(allowgroups|permitrootlogin|passwordauth) ' /tmp/eff.txt
grep -Ei '^(allowtcpforwarding|allowagentforwarding|loglevel) ' /tmp/eff.txt
```

### 3. Provisionnement des empreintes

`~/lab14/bin/known-hosts-parc.sh` :

```bash
#!/usr/bin/env bash
# Construit un known_hosts de référence, en vérifiant chaque empreinte
# contre ~/lab14/conf/empreintes.txt  (format : "hote SHA256:xxxx").
set -euo pipefail

REF=${REF:-$HOME/lab14/conf/empreintes.txt}
OUT=${OUT:-$HOME/lab14/conf/known_hosts.parc}
HOTES=${HOTES:-"10.10.10.11 10.10.10.12 10.10.10.13 10.10.10.14"}
TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT

[ -s "$REF" ] || { echo "référence absente : $REF" >&2; exit 2; }

ecart=0
for h in $HOTES; do
  ligne=$(ssh-keyscan -T 5 -t ed25519 "$h" 2>/dev/null) || {
    echo "INJOIGNABLE  $h" >&2; ecart=1; continue; }
  fp=$(printf '%s\n' "$ligne" | ssh-keygen -lf - | awk '{print $2}')
  att=$(awk -v h="$h" '$1==h {print $2}' "$REF")
  if [ -z "$att" ]; then
    echo "SANS RÉFÉRENCE  $h  $fp" >&2; ecart=1
  elif [ "$fp" != "$att" ]; then
    echo "DIVERGENCE  $h" >&2
    echo "  attendu : $att" >&2
    echo "  reçu    : $fp"  >&2
    ecart=1
  else
    echo "OK  $h  $fp"
    printf '%s\n' "$ligne" >> "$TMP"
  fi
done

if [ "$ecart" -ne 0 ]; then
  echo "écart détecté : $OUT n'est PAS écrit" >&2
  exit 2
fi
install -m 644 "$TMP" "$OUT"
echo "écrit : $OUT"
```

Constitution de la référence, **une fois**, en lisant les clés sur chaque
machine (par la console ou une session de confiance) :

```bash
for h in lab-web lab-db lab-rhel lab-ops; do
  ip=$(ssh -G "$h" | awk '/^hostname /{print $2}')
  fp=$(ssh "$h" 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub' \
       | awk '{print $2}')
  printf '%s %s\n' "$ip" "$fp"
done > ~/lab14/conf/empreintes.txt
```

> [!NOTE]
> **Pourquoi**
>
> Le point qui fait la valeur du script : `ssh-keyscan` **n'authentifie rien**, il
> enregistre ce que le réseau répond. Utilisé seul, il institutionnalise le TOFU
> aveugle. Il ne devient un outil de sécurité que confronté à une référence
> constituée par un autre canal — ici la lecture de la clé sur la machine — et en
> **refusant d'écrire** dès qu'un écart apparaît. Un script qui écrirait quand même
> en affichant un avertissement ne servirait à rien : personne ne lit les
> avertissements d'un job automatique.
>
> Le code de sortie 2 distinct de 1 permet à l'appelant (une CI, par exemple) de
> distinguer « échec technique » de « alerte de sécurité » et de réagir
> différemment.

### 4. Outil de parc

`~/lab14/bin/parc.sh` :

```bash
#!/usr/bin/env bash
# parc.sh [-p N] [-s SCRIPT] [commande...]
set -euo pipefail

HOTES=${HOTES:-"lab-web lab-db lab-rhel lab-ops"}
PAR=1 SCRIPT=""
while getopts ':p:s:h' o; do
  case "$o" in
    p) PAR=$OPTARG ;;
    s) SCRIPT=$OPTARG ;;
    h) echo "usage: parc.sh [-p N] [-s script.sh] [commande]"; exit 0 ;;
    :) echo "option -$OPTARG : argument manquant" >&2; exit 64 ;;
    *) echo "option inconnue : -$OPTARG" >&2; exit 64 ;;
  esac
done
shift $((OPTIND - 1))
CMD="${*:-uptime}"
[ -n "$SCRIPT" ] && [ ! -r "$SCRIPT" ] && \
  { echo "script illisible : $SCRIPT" >&2; exit 64; }

SSHOPT=(-n -o BatchMode=yes -o ConnectTimeout=5
        -o StrictHostKeyChecking=accept-new)
RES=$(mktemp -d); trap 'rm -rf "$RES"' EXIT

lancer() {
  local h=$1 rc=0 out
  # « && rc=0 || rc=$? » : sans ça, set -e tuerait la fonction avant
  # d'avoir enregistré le code de retour de la machine en échec.
  if [ -n "$SCRIPT" ]; then
    out=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$h" 'bash -s' \
          < "$SCRIPT" 2>&1) && rc=0 || rc=$?
  else
    out=$(ssh "${SSHOPT[@]}" "$h" "$CMD" 2>&1) && rc=0 || rc=$?
  fi
  printf '%s\n' "$rc" > "$RES/$h.rc"
  printf '%s\n' "${out%%$'\n'*}" > "$RES/$h.out"
}

n=0
for h in $HOTES; do
  lancer "$h" &
  n=$((n + 1))
  if [ "$n" -ge "$PAR" ]; then wait -n 2>/dev/null || wait; n=$((n - 1)); fi
done
wait

global=0
printf '%-10s %-5s %s\n' HOTE CODE SORTIE
for h in $HOTES; do
  rc=$(cat "$RES/$h.rc"); out=$(cat "$RES/$h.out")
  printf '%-10s %-5s %s\n' "$h" "$rc" "$out"
  case "$rc" in
    0) ;;
    255) [ "$global" -lt 2 ] && global=2 ;;
    *)   [ "$global" -lt 1 ] && global=1 ;;
  esac
done
exit "$global"
```

```console
$ ~/lab14/bin/parc.sh -p 4 'systemctl is-active ssh'
HOTE       CODE  SORTIE
lab-web    0     active
lab-db     0     active
lab-rhel   0     active
lab-ops    0     active
$ echo $?
0
```

> [!NOTE]
> **Pourquoi**
>
> Les choix de conception qui comptent, et qu'il faut savoir défendre :
>
> * **`-n` sur `ssh`** : sans lui, `ssh` consomme l'entrée standard du script.
>   Noter qu'il est retiré dans la branche `-s`, où stdin porte précisément le
>   script à exécuter — les deux usages sont exclusifs, et c'est le genre de
>   détail qui distingue un script qui marche d'un script qui marche par hasard.
> * **`BatchMode=yes`** : aucune invite possible. Un script d'exploitation qui
>   peut demander une passphrase est un script qui bloquera un jour à 3 h du matin.
> * **`StrictHostKeyChecking=accept-new`** : accepte un hôte inconnu (sinon le
>   premier passage échoue partout) mais **refuse** un changement de clé. C'est le
>   compromis raisonnable pour un outil interne ; l'idéal reste un `known_hosts`
>   provisionné par le script de l'étape 3, et alors `yes`.
> * **codes de retour hiérarchisés** : 255 signale une erreur de `ssh` lui-même
>   (injoignable, refusé), donc un problème d'infrastructure, qu'on distingue d'un
>   simple échec de la commande. L'appelant peut réagir différemment.
> * **parallélisme par `wait -n`** : on maintient N tâches en vol sans gestion
>   manuelle de PID. Les sorties sont écrites dans des fichiers séparés puis
>   relues en ordre : sans ça, les sorties concurrentes s'entrelacent et le
>   tableau devient illisible.

> [!WARNING]
> **Piège**
>
> `set -e` et la capture d'un code de retour cohabitent mal, et c'est le piège
> qui fait échouer la moitié des scripts de parc. Écrit naïvement :
>
> ```bash
> out=$(ssh "$h" "$CMD" 2>&1); rc=$?     # FAUX sous set -e
> ```
>
> la substitution de commande échoue, `set -e` termine la fonction **avant** la
> ligne `rc=$?`, et l'hôte en échec n'apparaît jamais dans le tableau. La forme
> correcte place l'affectation dans une liste `&&`/`||`, que `set -e` ignore par
> construction :
>
> ```bash
> out=$(ssh "$h" "$CMD" 2>&1) && rc=0 || rc=$?
> ```
>
> Le `&& rc=0` n'est pas décoratif : sans lui, `rc` garderait la valeur du tour
> précédent quand la commande réussit.
>
> Et `wait -n` n'existe que depuis bash 4.3 — sans importance sur Ubuntu 24.04
> (bash 5.2) et Rocky 9 (bash 5.1), mais à savoir si le script doit tourner
> ailleurs.

### 5. Rapport

`~/lab14/rapports/bastion.md` doit couvrir, au minimum :

* **Schéma d'accès** : poste (Windows ou Linux) → `lab-adm:22` → `ProxyJump` →
  `lab-web`/`lab-db`/`lab-rhel`/`lab-ops`. Préciser que l'authentification de la
  machine finale est de bout en bout et que le bastion ne voit que du chiffré.
* **Ajouter un administrateur** : génération de la clé sur **son** poste
  (`ssh-keygen -t ed25519 -a 100 -C ...`, passphrase obligatoire), envoi de la
  seule clé publique, ajout du compte au groupe `ssh-users` sur le bastion,
  ajout de la clé dans `~/.ssh/authorized_keys` du compte cible, vérification
  par `ssh -o BatchMode=yes`, et contrôle dans le journal que l'empreinte
  enregistrée est bien la sienne (`LogLevel VERBOSE`).
* **Révoquer un départ** : retrait du groupe `ssh-users` (effet immédiat sur les
  nouvelles connexions), puis retrait de la clé de tous les `authorized_keys`
  **par empreinte**, puis fermeture des sessions en cours (`pkill -u`), puis
  vérification par recherche de l'empreinte sur tout le parc. Noter que c'est
  long, faillible et non vérifiable à coup sûr : c'est l'argument des
  certificats.
* **Clé d'hôte changée** : la procédure de BF14.3, avec l'insistance sur la
  vérification hors bande et l'interdiction de `ssh-keygen -R` réflexe.
* **Quand passer aux certificats** : dès que le nombre de machines multiplié par
  le nombre de personnes rend la révocation non vérifiable — en pratique, une
  dizaine de machines et cinq personnes. Ce qui change : un `@cert-authority`
  dans `known_hosts` au lieu de N lignes, `TrustedUserCAKeys` au lieu de N
  `authorized_keys`, des certificats utilisateur de quelques heures délivrés par
  un service adossé au SSO — donc une révocation qui devient « ne plus délivrer »
  au lieu de « aller chercher partout ».

> [!NOTE]
> **Pourquoi**
>
> Ce qui est évalué dans ce défi n'est pas la longueur du script mais trois
> décisions d'architecture :
>
> 1. **Une source de vérité par information.** L'IP d'une machine est dans le
>    fichier de configuration SSH, nulle part ailleurs — d'où l'interdiction des IP
>    en dur dans `parc.sh`, qui doit passer par les alias.
> 2. **Aucune confiance implicite.** `ssh-keyscan` seul ne prouve rien : il est
>    confronté à une référence obtenue autrement, et le script **refuse d'écrire**
>    en cas d'écart.
> 3. **Le bastion relaie mais ne détient rien.** `AllowTcpForwarding yes` (c'est
>    son métier) mais `AllowAgentForwarding no` (il ne doit jamais pouvoir
>    s'authentifier à ta place). Cette paire de directives, opposées en apparence,
>    est le cœur de la conception d'un bastion.

---

<!-- nav:début -->
---

[← Module 13](../13-reseau-avance/corrige.md) · [Énoncé](README.md) · [Module 15 →](../15-services-applicatifs/corrige.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
