# Module 18 — Corrigé

## 18.3 Quiz — QCM

**Q18.1** — *`iptables -S` et `nft list ruleset` montrent les mêmes règles ufw.*

**Réponse : b)** `iptables` est `iptables-nft` : un frontal qui parle la syntaxe
iptables et écrit dans nftables.

::: pourquoi
Il n'y a qu'un seul moteur de filtrage dans un noyau Linux moderne : **netfilter**,
piloté par la couche **nftables** depuis le noyau 3.13. Ce qui a survécu de
l'ancien monde, ce sont les **commandes**.

Sur Ubuntu 24.04 comme sur Rocky 9, `/usr/sbin/iptables` est un lien géré par
`update-alternatives` qui pointe sur `iptables-nft`. Cette commande accepte la
syntaxe historique (`-A INPUT -p tcp --dport 22 -j ACCEPT`) et la traduit en
objets nftables, rangés dans une table `ip filter` avec des chaînes portant les
noms iptables. `iptables -V` le dit explicitement :

```console
$ iptables -V
iptables v1.8.10 (nf_tables)
```

`ufw` ne parle pas nftables : il génère des fichiers de règles au format
`iptables-restore` (`/etc/ufw/*.rules`) et les charge avec `iptables-restore`,
donc via `iptables-nft`. D'où la superposition : `ufw status` est la vue de ufw,
`iptables -S` la vue de compatibilité, `nft list ruleset` la vérité du noyau.

Retenir la hiérarchie de confiance quand ça ne marche pas :
`nft list ruleset` > `iptables -S` > `ufw status`. Les deux derniers ne montrent
que ce que leur propre outil a écrit ; le premier montre tout, y compris ce qu'un
autre outil (firewalld, Docker, un collègue, un script d'attaque) a ajouté.
:::

::: piege
Le vrai danger est le mélange. `iptables-legacy` existe encore et écrit dans
l'**ancien** sous-système, invisible de `nft list ruleset`. Une machine où
quelqu'un a lancé `iptables-legacy -I INPUT -j DROP` a deux jeux de règles
empilés, tous les deux appliqués, et un seul visible. Vérifie avec
`iptables-legacy -S` et `update-alternatives --display iptables` avant de perdre
une journée. Même famille de problème avec Docker, qui ajoute sa chaîne `DOCKER`
en amont des règles ufw : ufw ne protège pas les ports publiés par Docker.
:::

---

**Q18.2** — *`ufw allow 5432/tcp` puis `ufw allow from 10.10.10.11 ... port 5432`.*

**Réponse : b)** tout le monde peut se connecter au port 5432.

::: pourquoi
ufw évalue ses règles **de haut en bas, premier match gagnant**, et ajoute toute
nouvelle règle **à la fin** de la liste. L'ordre de saisie est donc l'ordre
d'évaluation.

La première règle, `allow 5432/tcp`, est une règle sans source : elle vaut
`from any`. Tout paquet à destination du port 5432 y correspond, quelle que soit
son origine, et il est accepté. La deuxième règle, plus restrictive, est
**atteignable mais inutile** : aucun paquet ne lui parvient.

`ufw status numbered` montre l'ordre réel, et c'est la seule commande à utiliser
pour relire une politique :

```console
$ sudo ufw status numbered
[ 1] 5432/tcp      ALLOW IN    Anywhere
[ 2] 5432/tcp      ALLOW IN    10.10.10.11
```

Correctif : `sudo ufw delete 1`. La règle 2 devient alors la seule, et la
politique par défaut `deny incoming` refuse tout le reste.
:::

::: piege
La politique par défaut ne « rattrape » jamais une règle trop large : elle
n'est consultée qu'**après** l'échec de toutes les règles. Un `default deny
incoming` accompagné d'un `allow 5432/tcp` ouvre le port au monde entier, et
c'est exactement de cette façon que des bases PostgreSQL et Redis se retrouvent
sur Shodan. Règle d'hygiène : sur un service interne, **aucune règle sans
`from`**.
:::

---

**Q18.3** — *`DENY IN 22/tcp` en position 1, `ALLOW IN 22/tcp from 10.10.10.10` en 3.*

**Réponse : b)** la connexion est refusée : la règle 1 est évaluée en premier.

::: pourquoi
Même mécanisme que Q18.2, dans l'autre sens, et c'est la façon dont on se coupe
soi-même. ufw n'a **aucune notion de spécificité** : il ne compare pas les
préfixes réseau, il ne trie pas, il n'optimise pas. La liste affichée par
`ufw status numbered` est littéralement l'ordre des règles `ufw-user-input` dans
le noyau.

Le correctif ne consiste pas à ajouter une règle (elle irait encore à la fin),
mais à **replacer** la bonne règle avant la mauvaise :

```bash
sudo ufw delete 3
sudo ufw insert 1 allow from 10.10.10.10 to any port 22 proto tcp
```

`ufw insert N` est la seule commande qui positionne. Après tout changement
d'ordre, `ufw status numbered` de nouveau : les numéros ont bougé.
:::

::: piege
Corollaire à retenir : **supprime toujours par numéro en partant du plus grand**.
Si tu lances `ufw delete 2` puis `ufw delete 3`, la deuxième commande ne supprime
pas ce que tu croyais — les numéros ont été renumérotés après la première
suppression. Et `ufw delete` accepte aussi la règle en toutes lettres
(`ufw delete allow 80/tcp`), ce qui est plus sûr en script.
:::

---

**Q18.4** — *`firewall-cmd --add-port=8080/tcp` perdu au reboot.*

**Réponses : a) et c)**

::: pourquoi
firewalld maintient **deux configurations distinctes** :

* le **runtime** : ce que le noyau applique en ce moment. Toute commande sans
  `--permanent` agit ici, avec effet immédiat, et disparaît au `--reload`, au
  `restart` du service et au reboot ;
* le **permanent** : les fichiers XML de `/etc/firewalld/zones/`. Toute commande
  avec `--permanent` écrit ici, **sans aucun effet immédiat**.

C'est un choix de conception, pas un bug : il permet de tester une règle
dangereuse en sachant qu'un reboot te rendra la main. On l'exploite d'ailleurs
avec `--timeout=` : `firewall-cmd --add-port=8080/tcp --timeout=5m` pose une
règle qui s'auto-supprime au bout de cinq minutes.

Les deux réponses correctes correspondent aux deux façons de faire durer :

* écrire dans le permanent puis recharger : `--permanent --add-port=8080/tcp`
  suivi de `--reload` ;
* ou, après avoir testé en runtime et validé que ça marche,
  `--runtime-to-permanent`, qui recopie l'état courant dans les fichiers. C'est
  la méthode que je recommande en production : on ne fige que ce qui est prouvé.

b) est correcte sur le fond, mais c'est **deux** commandes ; elle reste bonne
réponse. d) est fausse : `enable` fait démarrer firewalld au boot, il ne change
rien au contenu de la configuration chargée.
:::

::: piege
La symétrie de l'erreur : `--permanent` **sans** `--reload` ne fait rien
aujourd'hui. Tu écris la règle, tu testes, ça ne marche pas, tu cherches ailleurs
pendant une demi-heure. La commande de contrôle est
`firewall-cmd --list-all` (runtime) comparée à
`firewall-cmd --permanent --list-all` (fichier) : quand les deux diffèrent, tu
sais exactement dans quel état tu es.
:::

---

**Q18.5** — *Service ajouté à la zone `internal`, aucune interface dans cette zone.*

**Réponse : b)** la zone n'est jamais évaluée, le port 80 reste fermé.

::: pourquoi
Une zone firewalld n'est pas un groupe de règles global : c'est un jeu de règles
**attaché à des interfaces et/ou à des sources**. Le noyau range chaque paquet
entrant dans exactement une zone, selon cet ordre de décision :

1. la **source** du paquet correspond-elle à une source déclarée dans une zone
   (`--add-source=10.10.10.10/32`) ? Si oui, c'est cette zone.
2. sinon, l'**interface** d'entrée est-elle assignée à une zone
   (`--add-interface=ens18`) ? Si oui, c'est celle-là.
3. sinon, c'est la **zone par défaut** (`--get-default-zone`).

La source l'emporte sur l'interface : c'est ce qui permet d'écrire « tout le
monde arrive en `public`, sauf 10.10.10.10 qui arrive en `internal` ».

Ici, `internal` n'a ni interface ni source : aucun paquet n'y entre jamais. Les
services qu'on y déclare sont de la décoration. `firewall-cmd --get-active-zones`
ne liste d'ailleurs que les zones effectivement utilisées — c'est la commande de
diagnostic, et elle affichait bien `public` seul.

Pour que ce soit utile :

```bash
sudo firewall-cmd --permanent --zone=internal \
     --add-source=10.10.10.0/24
sudo firewall-cmd --reload
```
:::

---

**Q18.6** — *312 correspondances en `fail2ban-regex`, 0 échec dans la jail.*

**Réponse : a)** les lignes sont plus anciennes que `findtime`.

::: pourquoi
Deux outils, deux logiques, et c'est la source de confusion numéro un avec
fail2ban.

`fail2ban-regex` est un **banc d'essai d'expression régulière**. Il lit tout le
fichier, applique `failregex`, et compte les correspondances. Il se moque
complètement des dates : son travail est de te dire « ta regex attrape ces
lignes-là ».

Le démon, lui, fait de la **corrélation temporelle**. Pour chaque ligne qui
correspond, il extrait l'horodatage (d'où l'importance du `datepattern`), et il
n'incrémente le compteur d'une IP que si cet horodatage tombe dans la fenêtre
`[maintenant - findtime, maintenant]`. Un journal d'attaque vieux de la veille
produit donc 312 correspondances au test et 0 échec en fonctionnement : les
événements sont réels, mais périmés.

C'est aussi ce qui explique le comportement au démarrage : fail2ban relit le
journal depuis sa dernière position connue (stockée dans
`/var/lib/fail2ban/fail2ban.sqlite3`), et écarte tout ce qui est hors fenêtre.
Sans quoi un redémarrage du service bannirait rétroactivement la moitié
d'internet.

Pour tester pour de vrai : génère du trafic **maintenant** (six `curl` vers
`/.env` depuis `lab-db`) et regarde `fail2ban-client status nginx-scan` grimper.
:::

::: piege
d) contient une vraie erreur à connaître : sans `enabled = true`, la jail
n'existe pas du tout pour le démon, et elle **n'apparaît pas** dans
`fail2ban-client status`. Si tu vois ta jail dans la liste, la question de
`enabled` est déjà réglée. Et `fail2ban-client get nginx-scan logpath` te dit
quel fichier est réellement suivi : c'est le second contrôle à faire.
:::

---

**Q18.7** — *Se débannir sans redémarrer.*

**Réponse : b)** `sudo fail2ban-client set sshd unbanip 10.10.10.10`.

::: pourquoi
`fail2ban-client set <jail> unbanip <ip>` fait deux choses en une : il exécute
l'`actionunban` de la jail (donc retire la règle du pare-feu ou l'élément du set
nftables) **et** il purge l'IP de la base interne. C'est la seule commande qui
laisse le système cohérent.

Pourquoi les autres échouent :

* a) `reload` relit la configuration, mais restaure aussi les bannissements en
  cours depuis la base : tu restes banni ;
* c) `iptables -F` vide les chaînes du pare-feu — donc ton bannissement, mais
  aussi **toute ta politique de filtrage**, et fail2ban croira toujours l'IP
  bannie, ce qui empêchera un futur bannissement de la même IP ;
* d) `stop sshd` arrête la jail et, effectivement, retire les bans — mais tu
  perds la protection, ce que la question excluait.

À connaître aussi : `fail2ban-client unban --all` (toutes les jails, fail2ban
0.10+) et `fail2ban-client banned` qui liste tout ce qui est banni, jail par
jail.
:::

---

**Q18.8** — *`mv` depuis `/home`, 403 sur ce seul fichier.*

**Réponse : b)** le fichier a gardé son contexte SELinux d'origine.

::: pourquoi
C'est LE classique SELinux, et il tient à une différence d'appel système.

`mv` à l'intérieur d'un même système de fichiers est un `rename()` : aucune
donnée n'est copiée, seule l'entrée de répertoire change. Les attributs étendus,
dont `security.selinux` qui porte le contexte, sont **attachés à l'inode**. Le
fichier arrive donc dans `/var/www/html` en conservant l'étiquette qu'il avait
dans `/home/mathieu` : `user_home_t`.

`cp`, lui, crée un **nouvel inode**. La politique SELinux applique alors la règle
de transition de type par défaut, qui donne au nouveau fichier le contexte
attendu du répertoire parent : `httpd_sys_content_t`. D'où la formule à retenir :
**`cp` répare, `mv` casse**.

Le processus nginx tourne dans le domaine `httpd_t`. La politique l'autorise à
lire `httpd_sys_content_t`, `httpd_sys_rw_content_t` et quelques autres types ;
elle lui interdit explicitement `user_home_t`, précisément pour qu'une faille
dans nginx ne permette pas de lire les répertoires personnels. Le refus est donc
un fonctionnement **correct** de SELinux face à un fichier mal étiqueté.

Ce qui rend le diagnostic facile une fois qu'on connaît le réflexe :

```console
$ ls -Z /var/www/html/
unconfined_u:object_r:user_home_t:s0      index.html
system_u:object_r:httpd_sys_content_t:s0  autres.html
```
:::

::: piege
Le symptôme trompe : `Permission denied` dans `error.log` fait penser aux droits
Unix, et les droits Unix sont parfaits. Le réflexe qui fait gagner vingt minutes
sur Rocky : dès qu'un service refuse un accès dont les droits POSIX sont bons,
`ausearch -m AVC -ts recent` **avant** toute autre hypothèse. Et si
`setroubleshoot-server` est installé, `sealert -a /var/log/audit/audit.log`
donne le diagnostic en français, avec la commande de correction.
:::

---

**Q18.9** — *Correction durable du contexte.*

**Réponse : b)** `restorecon -v /var/www/html/index.html`.

::: pourquoi
Il faut distinguer trois outils qui semblent faire la même chose :

* **`chcon`** change l'étiquette d'un fichier **à la main**, sans rien déclarer.
  Le changement est réel mais non déclaré : le premier `restorecon -R`, le premier
  réétiquetage complet, la première restauration de sauvegarde l'écrasent. C'est
  un dépannage, jamais une configuration.
* **`restorecon`** relit la **politique** pour savoir quel contexte est attendu à
  ce chemin, et l'applique. C'est la bonne réponse ici, parce que
  `/var/www/html(/.*)?` est **déjà** déclaré dans la politique par défaut comme
  `httpd_sys_content_t` : il n'y a rien à déclarer, juste à réappliquer.
* **`semanage fcontext -a`** ajoute une **règle** dans la base des contextes
  attendus. C'est ce qu'il faut pour un chemin que la politique ne connaît pas
  (`/srv/api`, `/data/www`…), et il faut ensuite un `restorecon` pour l'appliquer
  aux fichiers existants : `semanage` déclare, `restorecon` exécute.

d) est donc fausse par redondance : déclarer ce qui est déjà déclaré n'apporte
rien (et `semanage fcontext -l | grep '/var/www'` le montre). a) n'est pas un
correctif, c'est un renoncement.

La commande qui répond à « quel contexte **devrait** avoir ce fichier ? » :

```console
$ matchpathcon /var/www/html/index.html
/var/www/html/index.html  system_u:object_r:httpd_sys_content_t:s0
```
:::

---

**Q18.10** — *AVC `name_connect` pour `httpd_t`.*

**Réponse : a)** `setsebool -P httpd_can_network_connect on`.

::: pourquoi
La politique SELinux « targeted » de RHEL/Rocky est volontairement paramétrable
sur les comportements légitimes mais risqués. Ces interrupteurs sont les
**booléens**, et ils sont conçus pour être manipulés : c'est l'interface
d'administration prévue, pas un contournement.

Par défaut, `httpd_t` n'a pas le droit d'ouvrir une connexion réseau sortante.
C'est délibéré : la majorité des exploitations de faille web commencent par un
`curl` vers l'extérieur (reverse shell, exfiltration, téléchargement de charge).
Interdire les connexions sortantes au serveur web casse cette étape. Mais un
reverse proxy, un client d'API ou un connecteur base de données distant en a
légitimement besoin, d'où le booléen.

`getsebool -a | grep httpd_` liste la trentaine de booléens du domaine web, et
`semanage boolean -l` affiche en plus une description en clair et la différence
entre valeur courante et valeur persistante.

`-P` signifie « persistant » : la valeur est écrite dans la politique et survit
au reboot. Sans `-P`, le changement est perdu au redémarrage — variante SELinux
du piège `--permanent` de firewalld.

b) fonctionnerait, mais on générerait un module de politique maison pour
reproduire un booléen déjà existant : plus de code, plus de dette, aucun gain.
d) se trompe de problème : `semanage port` sert quand un service **écoute** sur
un port inhabituel, pas quand il se connecte.
:::

---

**Q18.11** — *Retour de `disabled` à `enforcing` après six mois.*

**Réponse : b)** il faut un réétiquetage complet, sinon la machine peut ne pas
redémarrer correctement.

::: pourquoi
En mode `disabled`, le noyau ne charge aucune politique et n'écrit **aucun**
attribut `security.selinux` sur les fichiers créés. Six mois de `dnf update`,
de logs, de fichiers applicatifs : tout cela est né sans étiquette.

Au redémarrage en `enforcing`, la politique s'applique à des objets dont le
contexte est absent ou vaut `unlabeled_t`. Or presque aucun domaine n'a le droit
d'accéder à `unlabeled_t`. Conséquence typique : `systemd` ne peut plus lire ses
unités, `sshd` ne peut plus lire ses clés d'hôte, la machine démarre en mode
dégradé ou pas du tout, et sans console tu es enfermé dehors.

La procédure correcte :

```bash
sudo sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
sudo touch /.autorelabel
sudo reboot        # le réétiquetage complet a lieu au boot, c'est long
# on vérifie ensuite ausearch -m AVC -ts boot, on corrige,
# et seulement après on passe en enforcing
sudo setenforce 1 && sudo sed -i 's/^SELINUX=.*/SELINUX=enforcing/' \
     /etc/selinux/config
```

`permissive` d'abord : le noyau applique la politique, journalise tous les refus,
mais n'en bloque aucun. Tu obtiens la liste exhaustive de ce qui casserait, sans
rien casser. C'est l'intérêt même du mode, et la raison pour laquelle
`permissive` est acceptable en transition alors que `disabled` ne l'est jamais :
`disabled` ne journalise rien, donc ne prépare rien.
:::

::: piege
Depuis RHEL 9 / Rocky 9, `SELINUX=disabled` dans `/etc/selinux/config` n'est plus
la méthode officielle de désactivation : le noyau démarre quand même la
politique, seul le mode change. La vraie désactivation demande le paramètre de
démarrage `selinux=0`. Résultat : des machines qu'on croit « SELinux désactivé »
tournent en réalité en permissive et remplissent `audit.log` de refus jamais lus.
:::

---

**Q18.12** — *Profil AppArmor en mode `complain`.*

**Réponse : b)** les violations sont journalisées mais autorisées.

::: pourquoi
AppArmor a deux modes par profil :

* **enforce** : ce que le profil n'autorise pas est refusé, et journalisé
  (`apparmor="DENIED"`) ;
* **complain** (dit aussi « learning ») : tout est autorisé, mais chaque accès
  qui **aurait été** refusé est journalisé (`apparmor="ALLOWED"` avec le détail
  de l'opération).

C'est l'équivalent exact du `permissive` de SELinux, à la granularité du profil
près — et c'est un avantage réel d'AppArmor : on peut mettre **un seul** service
en observation pendant que le reste du système reste protégé. SELinux, lui, ne
propose le permissive que globalement, sauf à écrire un domaine permissif
(`semanage permissive -a httpd_t`), ce qui est possible mais moins connu.

Le cycle de travail complet :

```bash
sudo aa-complain /etc/apparmor.d/usr.sbin.nginx   # observation
# on fait tourner l'application dans toutes ses fonctions
sudo aa-logprof                                    # propose des règles
sudo aa-enforce /etc/apparmor.d/usr.sbin.nginx     # on referme
```

`aa-logprof` relit le journal, affiche chaque accès observé et propose de
l'autoriser, de le refuser ou de le généraliser en glob. C'est de la génération
de politique assistée : le vrai atout ergonomique d'AppArmor.
:::

---

**Q18.13** — *`/tmp` en `noexec,nosuid,nodev`.*

**Réponse : b)** les outils qui extraient puis exécutent un binaire dans `/tmp`
échoueront ; il faut leur fournir un `TMPDIR`.

::: pourquoi
Les trois options sont des garde-fous classiques, et chacun a un sens précis :

* `noexec` : le noyau refuse `execve()` sur tout fichier de ce montage. C'est une
  gêne pour l'attaquant, qui dépose très souvent sa charge dans `/tmp` (seul
  répertoire garanti inscriptible par tous) ;
* `nosuid` : les bits SUID/SGID sont ignorés. Un binaire SUID root déposé là ne
  donne plus rien ;
* `nodev` : les fichiers spéciaux de périphérique y sont ignorés. Empêche de
  recréer un `/dev/sda` accessible en écriture.

La contrepartie est réelle. Les installeurs `.run`, certains paquets avec
scripts `postinst` compilés, `dkms`, quelques scripts d'installation d'éditeurs
et parfois `apt` lui-même extraient un exécutable temporaire et le lancent.
Symptôme : `Permission denied` sur un chemin en `/tmp/xxxx`, alors que les droits
affichent `-rwxr-xr-x`.

Le contournement propre, au cas par cas, sans retirer `noexec` :

```bash
sudo mkdir -m 0700 /var/tmp/install
sudo TMPDIR=/var/tmp/install ./installeur.run
```

Et pour apt, `Dir::Cache` ou l'option `APT::ExtractTemplates::TempDir`.

Sous Ubuntu, deux implémentations possibles : une ligne `fstab` avec `tmpfs`
(`/tmp` en RAM, vidé au reboot, limité par la RAM) ou l'unité systemd fournie
(`cp /usr/share/systemd/tmp.mount /etc/systemd/system/` puis
`systemctl enable --now tmp.mount`). La seconde est plus propre sur une machine
gérée par systemd ; la première est plus lisible en audit.
:::

---

**Q18.14** — *`kernel.kptr_restrict = 2`.*

**Réponse : b)** masque les adresses noyau, pour tous les utilisateurs y compris
root.

::: pourquoi
Les exploits noyau ont besoin de connaître l'adresse de structures et de
fonctions internes pour contourner le KASLR (la randomisation de l'espace
d'adressage du noyau). Or ces adresses fuitaient librement par `/proc/kallsyms`,
`/proc/modules`, `dmesg` et de nombreuses traces.

`kptr_restrict` contrôle l'affichage des pointeurs noyau formatés `%pK` :

* `0` : affichage complet pour tout le monde ;
* `1` : affiché uniquement aux processus ayant `CAP_SYSLOG` (grossièrement :
  root) ;
* `2` : **jamais** affiché, quel que soit l'appelant. C'est la valeur des
  référentiels de durcissement, y compris CIS.

Effet de bord à connaître avant de l'appliquer : `perf`, certains profileurs et
la résolution de symboles dans les traces d'appel deviennent inutilisables. Sur
une machine de production applicative, c'est sans conséquence ; sur une machine
de débogage noyau, c'est bloquant.

Les distracteurs correspondent à d'autres clés, qu'il faut savoir distinguer :
`kernel.dmesg_restrict` (c) réserve `dmesg` aux privilégiés,
`kernel.randomize_va_space` (d) pilote l'ASLR des processus (valeur 2 = pile,
tas et bibliothèques randomisés), `kernel.modules_disabled` (a) interdit
définitivement le chargement de modules jusqu'au prochain reboot.
:::

---

**Q18.15** — *Secret poussé puis supprimé par un commit.*

**Réponses : a) et c)**

::: pourquoi
Git est un stockage **par instantanés immuables**. Un commit qui supprime un
fichier ajoute un nouvel objet arbre qui ne le référence plus ; l'objet blob
contenant le secret, lui, reste dans la base d'objets et reste atteignable par
n'importe quel commit antérieur. `git log -p --all -- .env`,
`git show <commit>:.env` ou un simple `git clone` puis recherche dans
l'historique le retrouvent en dix secondes. Sur une forge, il reste également
dans les caches, les forks, les pull requests, les artefacts de CI, les
sauvegardes, et dans les clones de tous ceux qui avaient déjà tiré.

D'où la seule conclusion correcte : **un secret exposé est un secret compromis**.
Le nettoyage de l'historique (`git filter-repo`, l'ancien `filter-branch`, ou
l'outil de purge de la forge) est utile pour ne pas rejouer la fuite, mais il
arrive après la bataille et ne peut pas révoquer ce qui a déjà été cloné. La
seule action qui rétablit la sécurité, c'est la **rotation** : nouveau mot de
passe, nouvelle clé, nouveau jeton, et vérification des journaux d'accès sur la
période d'exposition.

d) inverse la logique : `.gitignore` n'agit que sur les fichiers **non suivis**.
Un fichier déjà indexé continue d'être suivi malgré `.gitignore` — il faut un
`git rm --cached .env` pour le désindexer, ce qui, encore une fois, ne touche pas
à l'historique.
:::

::: piege
Le réflexe qui évite tout ça : un hook `pre-commit` avec `gitleaks` ou
`git-secrets`, plus un contrôle en CI sur la branche par défaut. Coût : dix
minutes. Et `.env` dans `.gitignore` **dès la création du dépôt**, avec un
`.env.example` versionné contenant les clés et des valeurs bidon — c'est ce
fichier d'exemple qui documente les variables attendues.
:::

---

**Q18.16** — *Certificat auto-signé sans SAN.*

**Réponse : b)** il manque le `subjectAltName`.

::: pourquoi
Historiquement, le nom d'hôte était vérifié dans le `CN` (Common Name) du sujet.
Cet usage est **déprécié depuis la RFC 2818 (2000)** et abandonné dans les faits :
Chrome ne le regarde plus depuis 2017, Firefox depuis 2018, OpenSSL et curl
suivent la même logique via `X509_check_host()`. Aujourd'hui, un certificat sans
`subjectAltName` n'identifie **aucun** nom d'hôte, quel que soit son `CN`.

L'erreur typique côté curl :

```console
$ curl https://app.lab.local
curl: (60) SSL: no alternative certificate subject name matches
      target host name 'app.lab.local'
```

La forme correcte en une commande, avec OpenSSL 3 :

```bash
openssl req -x509 -newkey rsa:2048 -nodes -keyout srv.key -out srv.crt \
  -days 397 -subj "/CN=app.lab.local" \
  -addext "subjectAltName=DNS:app.lab.local,IP:10.10.10.11" \
  -addext "extendedKeyUsage=serverAuth"
```

Vérification systématique après émission :

```bash
openssl x509 -in srv.crt -noout -ext subjectAltName
```

Les autres propositions : `rsa:2048` reste parfaitement accepté (2048 bits est le
minimum des autorités publiques) ; `-nodes` signifie « no DES », c'est-à-dire clé
privée non chiffrée — exactement ce qu'il faut pour un serveur qui doit démarrer
sans saisie de phrase de passe ; et OpenSSL 3 signe en SHA-256 par défaut.
:::

---

**Q18.17** — *`Verify return code: 21` mais cadenas vert dans le navigateur.*

**Réponse : b)** il manque le certificat intermédiaire dans le fichier servi.

::: pourquoi
Une chaîne de confiance complète comporte trois maillons : le certificat du
serveur, un ou plusieurs certificats **intermédiaires**, et le certificat racine.
Seule la racine est dans le magasin du client. Le serveur doit donc envoyer le
sien **et** les intermédiaires, pour que le client puisse remonter jusqu'à une
racine qu'il connaît.

`ssl_certificate` de nginx n'est pas « le certificat » mais « le certificat suivi
de la chaîne », dans l'ordre feuille → intermédiaire(s). C'est exactement ce que
contient le `fullchain.pem` de Let's Encrypt, et c'est pour cela qu'on ne met
**jamais** `cert.pem` dans nginx.

Pourquoi le navigateur pardonne : il met en cache les intermédiaires rencontrés
sur d'autres sites, et il sait aller les chercher via l'extension *Authority
Information Access* du certificat (AIA fetching). `curl`, les clients mobiles,
les bibliothèques HTTP des langages et les webhooks ne font ni l'un ni l'autre.
D'où le grand classique : « ça marche dans mon navigateur, mais l'API partenaire
n'arrive pas à nous appeler ».

Le contrôle qui tranche, sans navigateur :

```bash
openssl s_client -connect 10.10.10.11:443 -servername app.lab.local \
  -showcerts </dev/null 2>/dev/null | grep -c 'BEGIN CERTIFICATE'
```

Si le compte vaut 1 alors que la CA a un intermédiaire, la chaîne est incomplète.
:::

---

**Q18.18** — *`/proc/2481/exe -> /tmp/.x (deleted)`.*

**Réponses : a) et c)**

::: pourquoi
Sous Linux, un fichier ouvert reste accessible tant qu'un descripteur le
référence, même si son entrée de répertoire a été supprimée. Un processus dont le
binaire a été effacé continue donc de tourner, et `/proc/PID/exe` le signale par
le suffixe `(deleted)`.

Trois indices s'accumulent ici, et c'est leur conjonction qui fait le signal :
l'exécutable était dans `/tmp`, son nom commence par un point (masqué d'un `ls`
ordinaire), et il a été effacé après lancement. C'est le mode opératoire standard
d'une charge malveillante : déposer, exécuter, effacer pour ne rien laisser à
l'analyse antivirus et à l'admin.

Et c'est justement pourquoi c) est capital : **le seul exemplaire du binaire
existant encore est celui que le noyau tient ouvert**. `cp /proc/2481/exe` en
fait une copie exploitable (hash, `strings`, analyse). Tuer le processus avant,
c'est détruire la seule preuve.

Ordre de travail : geler ce qui est volatil, puis agir.

```bash
sudo cp /proc/2481/exe    /preuves/bin.$(date +%s)
sudo cp /proc/2481/cmdline /preuves/cmdline
sudo ls -l /proc/2481/cwd /proc/2481/fd
sudo ss -tunp | grep 2481         # avec qui il parle
sudo lsof -p 2481
```

b) est faux : une mise à jour de paquet laisse bien des processus avec un binaire
`(deleted)` — c'est même normal après un `apt upgrade` — mais le chemin est alors
`/usr/sbin/nginx (deleted)`, pas `/tmp/.x`. Savoir distinguer les deux cas évite
autant les faux positifs que les angles morts.

d) est l'erreur de débutant sous stress : tuer détruit la preuve, alerte
l'attaquant, et ne traite ni la persistance (cron, unité systemd, clé SSH
ajoutée) ni le vecteur d'entrée. Le processus reviendra dans cinq minutes.
:::

---

## 18.4 Quiz — questions ouvertes

**QO18.1** — *Pourquoi `default deny incoming` ne casse pas les réponses aux
requêtes sortantes.*

**Réponse attendue**

Parce que le filtrage n'est pas fait paquet par paquet isolément, mais **par
connexion**, grâce au suivi de connexion du noyau — *conntrack*.

Le chemin : un paquet entrant traverse les hooks netfilter dans l'ordre
`prerouting`, décision de routage, puis `input` s'il est destiné à la machine.
Avant même `prerouting`, le module `nf_conntrack` examine le paquet et lui
attribue un état :

| État | Signification |
|---|---|
| `NEW` | premier paquet d'une connexion inconnue (un SYN entrant) |
| `ESTABLISHED` | appartient à une connexion déjà vue dans les deux sens |
| `RELATED` | connexion distincte mais liée (ICMP d'erreur, canal FTP data) |
| `INVALID` | ne correspond à rien de cohérent |

La politique `deny incoming` ne s'applique donc réellement qu'aux paquets `NEW`.
Quand ta machine ouvre une connexion vers 9.9.9.9:443, conntrack enregistre le
quadruplet ; la réponse entrante est classée `ESTABLISHED` et acceptée par une
règle placée **tout en haut**.

Chez ufw, cette règle est dans `/etc/ufw/before.rules`, donc bien avant les
règles utilisateur, et invisible de `ufw status` :

```text
-A ufw-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A ufw-before-input -m conntrack --ctstate INVALID -j ufw-logging-deny
```

L'équivalent nftables s'écrit `ct state established,related accept`.

::: pourquoi
Deux conséquences qu'on attend d'un candidat :

1. C'est ce mécanisme qui rend un pare-feu « à état » utilisable : sans lui, il
   faudrait ouvrir en entrée toute la plage de ports éphémères
   (`net.ipv4.ip_local_port_range`, 32768-60999), ce qui reviendrait à ne rien
   filtrer.
2. conntrack a une **table de taille finie**
   (`net.netfilter.nf_conntrack_max`). Sous fort trafic ou sous attaque, elle
   sature : `nf_conntrack: table full, dropping packet` dans `dmesg`, et la
   machine se met à jeter des connexions parfaitement légitimes. C'est une panne
   d'exploitation classique, et la surveillance associée est
   `sysctl net.netfilter.nf_conntrack_count` comparé à `nf_conntrack_max`.
:::

---

**QO18.2** — *ufw contre firewalld sur un parc de 200 serveurs.*

**Réponse attendue**

| Axe | ufw | firewalld |
|---|---|---|
| Modèle | liste de règles à plat, premier match | zones, une par contexte réseau |
| État | un seul, appliqué immédiatement | runtime + permanent séparés |
| API | CLI seulement | CLI, D-Bus, fichiers XML |
| Terrain | Debian/Ubuntu | RHEL/Rocky/SUSE |

ufw est un **simplificateur d'iptables** : il produit des règles à plat, dans
l'ordre de saisie, avec une syntaxe proche du langage naturel. Sa qualité est sa
lisibilité ; son défaut est qu'à partir d'une trentaine de règles, l'ordre
devient un sujet à lui tout seul.

firewalld est un **modèle de données** : des zones, chacune décrivant un niveau
de confiance, auxquelles on rattache des interfaces et des sources. La question
n'est plus « dans quel ordre sont mes règles » mais « d'où vient ce paquet, donc
dans quelle zone tombe-t-il ». Ça monte mieux en charge conceptuellement, c'est
plus verbeux au démarrage, et le couple runtime/permanent est une source
d'erreurs permanente pour qui ne l'a pas intégré.

Pour 200 serveurs, la vraie réponse en entretien : **ni l'un ni l'autre ne se
pilote à la main**. On choisit celui qui est natif sur la distribution du parc
(ufw sur un parc Ubuntu, firewalld sur un parc RHEL), et on le gère par Ansible
(`ansible.posix.firewalld`, `community.general.ufw`) depuis un dépôt Git où la
politique est décrite une fois, testée, et déployée par rôle. Ce qui compte
alors, c'est que le module Ansible soit idempotent et gère le permanent — les
deux le font.

::: piege
Piège d'entretien fréquent : répondre « firewalld est plus moderne car il utilise
nftables ». C'est vrai pour le backend, mais ufw sur Ubuntu 24.04 aboutit lui
aussi dans nftables via `iptables-nft`. La différence n'est pas le moteur, c'est
le modèle de configuration. Et sur une machine où l'on veut vraiment du nftables
natif, on écrit directement `/etc/nftables.conf` sans frontal : c'est ce que font
les firewalls d'infrastructure.
:::

---

**QO18.3** — *« La règle est là mais le trafic ne passe pas. »*

**Réponse attendue** — une démarche qui descend les couches, en vérifiant à
chaque étage plutôt qu'en devinant :

```bash
# 1. le service écoute-t-il, et sur quelle adresse ?
ss -tlnp | grep 5432          # 0.0.0.0 ou 127.0.0.1 ? tout est là
# 2. le trafic arrive-t-il jusqu'à la machine ?
sudo tcpdump -ni any port 5432 -c 20
# 3. que dit VRAIMENT le noyau, pas le frontal ?
sudo nft list ruleset | less
sudo iptables -S | grep 5432
sudo iptables-legacy -S 2>/dev/null   # le jeu de règles fantôme
# 4. quelle règle compte des paquets ?
sudo iptables -L -n -v --line-numbers
# 5. qui refuse, et où ?
sudo tail -f /var/log/ufw.log
sudo journalctl -f -u firewalld
# 6. côté applicatif
sudo tail -f /var/log/postgresql/postgresql-16-main.log
```

Les trois causes qui couvrent 90 % des cas :

1. le service n'écoute que sur `127.0.0.1` — le pare-feu n'y est pour rien ;
2. une règle de refus placée **avant** la règle d'autorisation, ou une règle
   posée hors du frontal (dans `before.rules`, par Docker, par un autre outil) ;
3. le blocage n'est pas à l'entrée mais **ailleurs** : pare-feu de la machine
   source, filtrage sur le chemin, ou un `pg_hba.conf` / une conf applicative qui
   refuse après que le TCP a été accepté.

Le test qui discrimine entre 2 et 3 : `tcpdump` sur la destination. Si tu vois le
SYN arriver et aucune réponse, c'est un `DROP` local. Si tu vois le SYN et un
RST, quelque chose a refusé activement (règle `REJECT` ou service qui ferme). Si
tu ne vois rien du tout, le paquet n'arrive pas — cherche en amont.

::: pourquoi
Les compteurs de paquets sont l'outil le plus sous-utilisé du pare-feu.
`iptables -L -n -v` affiche, pour chaque règle, le nombre de paquets et d'octets
qui l'ont traversée. Une règle d'autorisation à `0 packets` alors que le client
tente de se connecter prouve que le paquet est traité avant elle ; une règle de
refus dont le compteur s'incrémente exactement au rythme de tes tentatives
désigne la coupable sans ambiguïté. Remets les compteurs à zéro avec
`iptables -Z` avant le test pour lire proprement.
:::

---

**QO18.4** — *De « ça marche en permissive » à un correctif propre.*

**Réponse attendue** — la méthode en cinq temps :

**1. Confirmer que SELinux est bien en cause**, sans y passer la journée :

```bash
sudo ausearch -m AVC,USER_AVC,SELINUX_ERR -ts recent
sudo setenforce 0 && <reproduire> && sudo setenforce 1
```

Si le comportement change entre les deux modes, c'est SELinux. Sinon, ce n'était
pas la piste.

**2. Collecter proprement.** On repart d'une base saine :

```bash
sudo setenforce 0
sudo truncate -s 0 /var/log/audit/audit.log   # ou noter la date de départ
# exercer TOUTES les fonctions de l'application, pas juste la page d'accueil
sudo ausearch -m AVC -ts recent | audit2allow -l
```

Exercer toutes les fonctions est le point que tout le monde rate : un chemin de
code jamais emprunté pendant la collecte produira un refus en production trois
semaines plus tard.

**3. Lire chaque refus et le classer.** `audit2why` traduit et, surtout, indique
si un **booléen** couvre le cas :

```console
$ sudo ausearch -m AVC -ts recent | audit2why
        Was caused by:
        One of the following booleans was set incorrectly.
        Allow httpd to can network connect
        Allow access by executing: setsebool -P httpd_can_network_connect 1
```

Classement des causes, par ordre de fréquence :

| Cause | Correctif |
|---|---|
| Fichier mal étiqueté | `restorecon`, ou `semanage fcontext` + `restorecon` |
| Port non déclaré | `semanage port -a -t <type> -p tcp <port>` |
| Comportement optionnel | `setsebool -P <booléen> on` |
| Vrai besoin non prévu | module de politique ciblé |

**4. `audit2allow` en dernier recours, et jamais en aveugle.** Bon usage : quand
les trois premières lignes du tableau ne s'appliquent pas, et après avoir **lu**
les règles générées :

```bash
sudo ausearch -m AVC -ts recent -c monapp | audit2allow -M monapp
cat monapp.te          # ON LIT. Toujours.
sudo semodule -i monapp.pp
```

Mauvais usage, et c'est la faute grave : `ausearch -m AVC -ts today |
audit2allow -M tout && semodule -i tout.pp`. Ce module accorde **tout ce qui a
été refusé sur la machine**, y compris les refus provenant d'un scan en cours ou
d'un autre service mal configuré. On a vu passer des modules générés ainsi qui
donnaient à `httpd_t` le droit d'écrire dans `/etc/shadow`.

**5. Vérifier et documenter.** Repasser en `enforcing`, rejouer le scénario
complet, confirmer `ausearch -m AVC -ts recent` vide, et écrire les commandes
appliquées dans le dépôt de configuration — un correctif SELinux non versionné
sera refait à la main sur la machine suivante.

::: piege
Deux subtilités qui font gagner du temps :

* certains refus sont masqués par des règles `dontaudit` de la politique. Si le
  service échoue et qu'`audit.log` est vide, `sudo semodule -DB` désactive
  temporairement les `dontaudit` et fait apparaître les refus cachés
  (`semodule -B` rétablit) ;
* pour ne mettre en permissive qu'**un** service au lieu de toute la machine :
  `sudo semanage permissive -a httpd_t`. Le reste du système reste protégé
  pendant le diagnostic. `semanage permissive -d httpd_t` pour refermer.
:::

---

**QO18.5** — *fail2ban protège-t-il contre le bruteforce SSH ?*

**Réponse attendue**

Ce que ça fait réellement : fail2ban lit des journaux, détecte des motifs
d'échec, et ajoute une règle de pare-feu temporaire contre l'IP source. C'est
donc un outil **réactif**, **par IP**, et **postérieur à l'attaque**. Il réduit
le bruit dans les journaux, freine les scanners automatisés opportunistes, et
limite la consommation de ressources due au bruteforce. C'est utile, et c'est
tout.

Quatre situations où il ne sert à rien :

1. **Attaque distribuée** : 5 000 IP qui tentent trois mots de passe chacune ne
   déclenchent jamais un `maxretry` de 4. C'est le mode opératoire standard des
   botnets depuis dix ans.
2. **Identifiants valides** : un mot de passe volé ou une clé compromise donne un
   succès dès la première tentative. Aucun échec, aucun bannissement — et c'est
   par là qu'arrivent les vraies intrusions.
3. **Derrière un proxy ou un load balancer** : le journal contient l'IP du proxy.
   Soit fail2ban ne bannit personne d'utile, soit il bannit le proxy et coupe
   tout le trafic. Il faut alors lire `X-Forwarded-For`, avec la difficulté que
   cet en-tête est falsifiable s'il n'est pas réécrit par un équipement de
   confiance.
4. **Fenêtre de course** : entre la tentative et le bannissement, il y a le délai
   d'écriture du log, le cycle de lecture de fail2ban et l'application de la
   règle — quelques secondes pendant lesquelles rien n'est bloqué. Un outil qui
   ouvre 200 connexions parallèles en profite largement.

Ce qui protège vraiment SSH, par ordre d'efficacité :

* **authentification par clé uniquement** (`PasswordAuthentication no`) : le
  bruteforce de mot de passe devient sans objet, c'est le module 14 ;
* **filtrage réseau** : SSH accessible seulement depuis le bastion, ce qu'on a
  fait en L18.1 — un port fermé ne se bruteforce pas ;
* **MFA** pour les accès humains hors bastion ;
* et seulement ensuite fail2ban, comme réducteur de bruit.

::: pourquoi
La formulation qui marque en entretien : « fail2ban n'est pas un contrôle
d'accès, c'est un **modérateur de journal**. Le contrôle d'accès, c'est le
pare-feu et l'authentification. » Un candidat qui met fail2ban en première ligne
de défense montre qu'il raisonne en symptômes ; celui qui le place en complément
montre qu'il raisonne en surface d'attaque.
:::

---

**QO18.6** — *AppArmor contre SELinux.*

**Réponse attendue**

| Axe | AppArmor | SELinux |
|---|---|---|
| Modèle | chemins d'accès | étiquettes sur inodes |
| Couverture | seulement ce qui a un profil | tout le système |
| Fichier déplacé | suit le nouveau chemin | garde son étiquette |
| Diagnostic | `aa-status`, `aa-logprof` | `ausearch`, `audit2why`, `sealert` |

**Modèle.** AppArmor écrit `/usr/sbin/nginx { /var/www/** r, }` : la politique
parle de chemins. SELinux attache une étiquette à l'inode et écrit des règles
entre types (`allow httpd_t httpd_sys_content_t:file read`). Ça change tout au
quotidien : chez AppArmor, un lien symbolique ou un point de montage peut
contourner une règle de chemin ; chez SELinux, l'étiquette voyage avec l'inode,
ce qui est plus robuste — et c'est aussi ce qui produit le piège du `mv`.

**Couverture par défaut.** Ubuntu charge une trentaine de profils, essentiellement
pour des démons exposés. Un binaire maison déposé dans `/opt` tourne **sans aucun
confinement**. Rocky étiquette l'intégralité du système de fichiers et confine
tous les services lancés par systemd ; un binaire maison hérite d'un domaine, au
pire `unconfined_t`, mais il est étiqueté.

**Coût d'exploitation.** AppArmor est lisible : un profil est un fichier texte
d'une vingtaine de lignes qu'on écrit à la main. Une politique SELinux est un
objet compilé qu'on ne lit pas directement, et dont on ne manipule que la
périphérie (contextes, ports, booléens). À charge de travail égale, AppArmor
s'apprend en une journée, SELinux en une semaine.

**Diagnostic.** `aa-logprof` est meilleur que tout ce qu'offre SELinux pour
construire une politique : il propose, tu valides. Côté SELinux, `sealert` donne
des explications en clair très utiles, mais il faut installer
`setroubleshoot-server` et savoir que `ausearch` existe.

**Le choix.** Pour un serveur applicatif maison : le MAC natif de la
distribution, activé, sans exception. Le meilleur des deux est celui qui reste
allumé. En pratique, sur Ubuntu je garde AppArmor et j'écris un profil pour
l'application exposée ; sur Rocky je garde SELinux en enforcing et je gère
contextes et booléens. Le seul mauvais choix est de désactiver celui qui est
fourni.

---

**QO18.7** — *Le secret « masqué » dans une variable de CI.*

**Réponse attendue** — au moins cinq vecteurs de fuite malgré le masquage :

1. **Le job lui-même** : le secret est en clair dans l'environnement du runner.
   `env`, `printenv`, un `set -x` qui déroule une commande, un cœur de vidage, un
   `curl -v` qui affiche l'en-tête `Authorization` — et c'est dans les logs.
2. **Le masquage est un filtre de chaîne de caractères**, appliqué à la sortie
   texte. `echo $SECRET | base64`, `echo $SECRET | rev`, ou l'affichage caractère
   par caractère passent à travers. Il ne masque que l'occurrence exacte.
3. **Le runner**. Sur un runner partagé, tout job peut lire l'espace de travail
   des autres, et sur un runner en shell, le cache et `/tmp` survivent d'un job à
   l'autre. Un runner compromis expose tous les secrets qui y transitent.
4. **Les artefacts et les images**. Un `.env` copié dans une image Docker reste
   dans une couche même si un `RUN rm` le supprime ensuite. Un dump de
   configuration joint comme artefact est téléchargeable par toute l'équipe.
5. **Les droits sur le projet**. Toute personne pouvant modifier le pipeline peut
   écrire un job qui exfiltre la variable. C'est trivial, indétectable dans une
   revue rapide, et c'est le vecteur d'attaque par chaîne d'approvisionnement.
6. Sans oublier les **forks et les branches** : selon la configuration, une merge
   request depuis un fork peut déclencher un pipeline avec accès aux variables.

Architecture réaliste à proposer, par ordre de maturité :

* court terme : variables **protégées** (branches protégées uniquement) et
  **masquées**, droits de modification du pipeline restreints, revue obligatoire
  sur le fichier de CI, `gitleaks` en pre-commit et en CI ;
* moyen terme : les secrets ne sont plus dans la CI mais dans un coffre
  (**HashiCorp Vault**, AWS Secrets Manager, Azure Key Vault) ; le pipeline
  s'authentifie par OIDC — pas de secret stocké, un jeton de courte durée émis à
  l'exécution ;
* pour les fichiers versionnés (valeurs de déploiement, `.env` de référence) :
  **SOPS** avec age ou KMS, ou `ansible-vault` pour un parc Ansible. Le fichier
  chiffré est dans Git, la clé ne l'est pas ;
* dans tous les cas : **rotation** périodique et automatique, et rotation
  immédiate à tout départ ou tout soupçon. Un secret qui n'a jamais tourné est un
  secret dont personne ne sait qui le connaît.

Et côté fichiers `.env` sur les serveurs : propriétaire le compte de service,
`chmod 0600` (ou `0640` avec un groupe dédié), jamais dans un répertoire servi
par nginx, jamais dans une sauvegarde non chiffrée, chargés par
`EnvironmentFile=` dans l'unité systemd plutôt que par un `export` dans un script
lisible.

::: piege
`ansible-vault` chiffre le **contenu du fichier**, pas les noms de variables ni
l'historique : un `ansible-playbook -vvv` affiche les valeurs déchiffrées dans la
sortie. Et un `no_log: true` sur les tâches qui manipulent des secrets n'est pas
optionnel — sans lui, Ansible affiche joyeusement le mot de passe dans le
résultat de la tâche en cas d'erreur.
:::

---

**QO18.8** — *La chaîne de confiance TLS.*

**Réponse attendue**

Un certificat X.509 contient : un **sujet** (dont le `CN`, décoratif aujourd'hui),
la **clé publique**, les **SAN** (les noms réellement couverts), une période de
validité (`notBefore`/`notAfter`), l'**émetteur**, des extensions
(`basicConstraints`, `keyUsage`, `extendedKeyUsage`, AIA, points de CRL) et la
**signature de l'émetteur** sur tout ce qui précède.

Ce que le client vérifie, dans l'ordre :

1. le **nom** demandé figure dans les SAN (sinon : erreur de nom d'hôte) ;
2. la **date** courante est dans la fenêtre de validité ;
3. la **chaîne** remonte : la signature du certificat serveur est valide avec la
   clé publique de l'intermédiaire, celle de l'intermédiaire avec la clé de la
   racine, et la racine est **présente dans le magasin local** ;
4. les **usages** sont cohérents (`extendedKeyUsage = serverAuth`,
   `basicConstraints CA:TRUE` sur les maillons intermédiaires) ;
5. la **révocation**, quand elle est vérifiée (OCSP, agrafage, CRL) ;
6. et seulement ensuite la poignée de main prouve que le serveur détient la
   **clé privée** correspondant à la clé publique du certificat.

Ce que nginx doit servir : `ssl_certificate` = certificat serveur **suivi** des
intermédiaires (le `fullchain.pem`), `ssl_certificate_key` = la clé privée seule,
non chiffrée, lisible uniquement par root.

Pourquoi l'erreur passe inaperçue dans un navigateur : cache d'intermédiaires et
récupération automatique via l'extension AIA (voir Q18.17). `curl`, Java,
Python `requests`, les clients mobiles et les webhooks ne font ni l'un ni
l'autre : une chaîne incomplète leur est fatale. Le contrôle de référence reste
`openssl s_client -showcerts` et le décompte des certificats présentés, ou un
`curl -v` depuis une machine qui n'a jamais visité le site.

---

**QO18.9** — *Connexion SSH réussie du compte `postgres` à 03h14.*

**Réponse attendue** — la conduite à tenir, dans l'ordre.

**Ce qu'on ne fait pas** : redémarrer la machine (on perd la mémoire et les
processus), « nettoyer » tout de suite (on détruit les preuves), couper
brutalement sans décision (on alerte l'attaquant et on peut déclencher un
mécanisme destructeur), et se fier aux binaires de la machine (`ps`, `ls`,
`netstat` peuvent être remplacés).

**0-5 min — qualifier.** Est-ce vraiment anormal ? `postgres` doit avoir
`/usr/sbin/nologin` comme shell : s'il a un shell valide, c'est déjà une
anomalie de configuration.

```bash
sudo lastlog -u postgres ; last -F postgres | head
sudo journalctl -u ssh --since "03:00" --until "03:30" -o short-iso
sudo grep -E 'Accepted|Failed|session opened' /var/log/auth.log \
     | grep -i postgres
getent passwd postgres          # shell, home
```

Ce qu'on cherche : la méthode d'authentification (`Accepted publickey` ou
`Accepted password` — pas du tout le même incident), l'IP source, l'empreinte de
la clé utilisée.

**5-15 min — isoler sans détruire.** Décision prise avec l'astreinte : soit on
isole au niveau réseau (règle de pare-feu entrante/sortante, ou on débranche
l'interface virtuelle côté hyperviseur), soit on laisse tourner sous
surveillance. On n'éteint pas. Un **snapshot Proxmox** est ici le meilleur des
deux mondes : il fige le disque **et** la RAM, et c'est une preuve.

**15-30 min — chercher ce qui a été fait.** Les signaux, dans cet ordre :

```bash
sudo ss -tunp                                   # connexions sortantes
ls -l /proc/*/exe 2>/dev/null | grep deleted    # binaire effacé
sudo find / -xdev -perm -4000 -type f | \
     diff - ~/lab18/baseline-suid.txt           # nouveaux SUID
sudo find /etc/cron* /var/spool/cron -newermt '-3 days' -ls
sudo systemctl list-units --type=service --state=running
sudo find /home /root -name authorized_keys -newermt '-3 days' -ls
sudo awk -F: '($3<1000){print}' /etc/passwd | tail  # comptes créés
sudo ausearch -m USER_LOGIN,ADD_USER,USER_CMD -ts today
```

Puis : que contenait le `.bash_history` du compte, que dit `aureport`, quels
fichiers ont été modifiés dans `/etc` depuis la date d'intrusion
(`find /etc -newermt ...`), et quelles données étaient accessibles depuis ce
compte (pour PostgreSQL : toute la base).

**Et ensuite.** Prévenir (responsable, RSSI, et le métier si des données
personnelles sont concernées — le délai de notification RGPD est de 72 h),
**tourner tous les secrets** accessibles depuis cette machine, et réinstaller
plutôt que nettoyer : on ne sait jamais prouver qu'on a tout enlevé. La
réinstallation ne vaut que si l'on a compris le **vecteur d'entrée**, sinon
l'intrusion recommence sur la machine neuve.

::: pourquoi
La hiérarchie de la volatilité des preuves, à connaître : mémoire vive et
processus (perdus à l'arrêt) > connexions réseau (idem) > fichiers temporaires >
disque > sauvegardes. On collecte toujours du plus volatil vers le moins
volatil. C'est l'ordre de la RFC 3227, et c'est exactement pour ça qu'on ne
redémarre pas « pour voir si ça revient ».
:::

---

**QO18.10** — *CIS Benchmark, niveaux, « scored », et pourquoi pas 100 %.*

**Réponse attendue**

Un **CIS Benchmark** est un référentiel de configuration publié par le Center for
Internet Security, produit par consensus de praticiens, pour un produit précis et
une version précise (« CIS Ubuntu Linux 24.04 LTS Benchmark »). Chaque
recommandation donne : la justification, l'impact, la procédure d'audit et la
procédure de remédiation. C'est ce que l'auditeur aura sous les yeux.

**Niveau 1** : mesures applicables à la majorité des systèmes, avec un impact
fonctionnel faible ou nul. C'est la base attendue partout.
**Niveau 2** : durcissement en profondeur, pour les environnements où la sécurité
prime sur la commodité. Impact assumé : perte de fonctionnalités, complexité
d'exploitation (par exemple `/var` sur une partition dédiée avec `noexec`, ou
l'interdiction totale des modules noyau).

**Scored / Not Scored** (nommés depuis 2021 *Automated* / *Manual*) : les
recommandations *automated* sont vérifiables par un script et comptent dans le
score ; les *manual* demandent un jugement humain (« vérifier que seuls les
comptes nécessaires existent ») et ne sont pas comptées.

Pourquoi viser 100 % sur un serveur applicatif existant est une mauvaise idée :

* certaines recommandations **cassent l'application** (montages `noexec`,
  suppression de modules, durcissement de `umask`, désactivation de protocoles
  utilisés par un client) ;
* le benchmark est générique et ne connaît pas ton contexte : un contrôle sans
  objet sur ta machine (serveur d'impression, X11, IPv6 désactivé alors que tu
  l'utilises) fait baisser le score sans qu'il y ait de risque réel ;
* courir après le score fait **appliquer sans comprendre**, et une conformité de
  façade est plus dangereuse qu'un écart documenté ;
* le coût marginal devient absurde : les vingt derniers pourcents demandent plus
  d'efforts que les quatre-vingts premiers, pour un gain de risque marginal.

La pratique professionnelle : appliquer le niveau 1 intégralement, examiner le
niveau 2 point par point, et tenir un **registre des écarts** — pour chaque
contrôle non appliqué, la raison, le risque résiduel accepté, et qui l'a accepté.
C'est ce registre que l'auditeur veut voir, pas un score de 100 %.

Outillage : `oscap xccdf eval --profile cis_level1_server` avec
`scap-security-guide` (Rocky), les rôles Ansible `ansible-lockdown`, et `lynis`
pour un avis rapide et non normatif.

---

## 18.5 Exercices guidés

**E18.1** — *Règles réellement chargées dans le noyau, avec compteurs.*

```bash
sudo nft -a list ruleset
sudo nft list chain inet filter input      # si la table est en inet
sudo nft list table ip filter              # ufw écrit ici via iptables-nft
```

Pour voir les compteurs, il faut que les règles en aient : celles générées par
ufw en ont (`counter packets 12 bytes 720`). La chaîne qui reçoit les paquets
destinés à la machine est celle déclarée `type filter hook input`.

::: pourquoi
`nft -a` ajoute le **handle** de chaque règle (`# handle 7`), qui est
l'identifiant à donner à `nft delete rule <table> <chaîne> handle 7`. C'est la
seule façon de supprimer une règle précise en nftables : il n'y a pas de numéro
de ligne comme en iptables.

Les hooks disponibles pour une chaîne `filter` sont `prerouting`, `input`,
`forward`, `output` et `postrouting` ; le `priority` détermine l'ordre entre
plusieurs chaînes accrochées au même hook (plus la valeur est basse, plus c'est
tôt). C'est ainsi que firewalld s'insère avant ou après d'autres jeux de règles.
:::

---

**E18.2** — *Prouver qu'`iptables` est `iptables-nft`.*

```bash
iptables -V
# iptables v1.8.10 (nf_tables)
update-alternatives --display iptables
```

::: pourquoi
La mention `(nf_tables)` entre parenthèses est la preuve directe. Le second
affichage montre les deux implémentations installées
(`/usr/sbin/iptables-nft` et `/usr/sbin/iptables-legacy`) et laquelle est
sélectionnée. Si tu hérites d'une machine où quelqu'un a basculé sur
`iptables-legacy`, tu as deux jeux de règles indépendants, tous deux actifs,
et `nft list ruleset` n'en montre qu'un. C'est le contrôle à faire sur toute
machine dont le filtrage « fait n'importe quoi ».
:::

---

**E18.3** — *Activer ufw sans se couper.*

```bash
sudo ufw allow from 10.10.10.10 to any port 22 proto tcp   # 1. la porte
sudo ufw default deny incoming                              # 2. la politique
sudo ufw default allow outgoing
sudo ufw status numbered                                    # 3. on relit
sudo ufw enable                                             # 4. on arme
```

::: pourquoi
L'ordre est la seule chose qui compte. `ufw enable` applique immédiatement la
politique par défaut ; si aucune règle n'autorise ton SSH à ce moment-là, ta
session en cours est coupée net — les connexions déjà établies sont certes
acceptées par la règle `ESTABLISHED` de `before.rules`, mais tu ne pourras pas
te reconnecter, et le moindre incident réseau te met dehors définitivement.

`ufw enable` affiche d'ailleurs l'avertissement
`Command may disrupt existing ssh connections. Proceed with operation (y|n)?` :
c'est exactement de ça qu'il parle.

Filet de sécurité complémentaire, à connaître pour les interventions distantes
sur une machine sans console : programmer le retour en arrière **avant** de
prendre le risque.

```bash
echo 'ufw disable' | sudo at now + 5 minutes
# si tout va bien : sudo atrm <num>
```
:::

---

**E18.4** — *Ouvrir 80 et 443 avec un profil d'application.*

```bash
sudo ufw app list
sudo ufw app info 'Nginx Full'
sudo ufw allow 'Nginx Full'
```

```console
$ sudo ufw app info 'Nginx Full'
Profile: Nginx Full
Title: Web Server (Nginx, HTTP + HTTPS)
Ports:
  80,443/tcp
```

::: pourquoi
Les profils sont de simples fichiers INI dans `/etc/ufw/applications.d/`,
déposés par les paquets. Leur intérêt n'est pas d'éviter de taper « 80 » : c'est
que la règle **suit le logiciel**. Si une version future de nginx ajoute un port,
la mise à jour du profil suffit, et `ufw app update nginx` recharge les règles
qui s'y réfèrent.

Leur limite : un profil ne porte que des ports, pas de source. Pour une règle
sourcée, on combine :
`sudo ufw allow from 10.10.10.0/24 to any app 'Nginx Full'`.
:::

---

**E18.5** — *SSH depuis `lab-adm` seulement, règle bien placée.*

```bash
sudo ufw allow from 10.10.10.10 to any port 22 proto tcp
sudo ufw status numbered
# si elle est mal placée :
sudo ufw delete 5
sudo ufw insert 1 allow from 10.10.10.10 to any port 22 proto tcp
```

::: pourquoi
`ufw insert N` est la seule commande de positionnement ; toute autre commande
ajoute en fin de liste. Après chaque insertion ou suppression, les numéros sont
recalculés : on relit systématiquement `ufw status numbered` avant l'action
suivante, et on supprime **du plus grand numéro vers le plus petit** quand il y
en a plusieurs.
:::

---

**E18.6** — *Limiter SSH à 6 connexions par 30 s.*

```bash
sudo ufw limit 22/tcp
sudo nft list ruleset | grep -A4 'recent\|limit'
sudo iptables -S | grep -i recent
```

```console
-A ufw-user-input -p tcp --dport 22 -m conntrack --ctstate NEW \
   -m recent --set --name DEFAULT --mask 255.255.255.255 --rsource
-A ufw-user-input -p tcp --dport 22 -m conntrack --ctstate NEW \
   -m recent --update --seconds 30 --hitcount 6 --name DEFAULT \
   --rsource -j ufw-user-limit
```

::: pourquoi
`ufw limit` s'appuie sur le module `recent` de xtables : une première règle
**enregistre** l'IP source de chaque nouvelle connexion dans une liste nommée,
une seconde **compte** les enregistrements des 30 dernières secondes pour cette
IP et saute vers `ufw-user-limit` (qui journalise puis rejette) au-delà de 6.

Deux limites à connaître avant de s'en servir comme protection :

* le seuil est **codé en dur** dans ufw (6 en 30 s) ; le changer demande d'éditer
  `/etc/ufw/user.rules` à la main, ce qu'un `ufw` ultérieur peut écraser ;
* c'est du comptage par IP source : sans effet sur une attaque distribuée, et
  susceptible de bloquer un NAT légitime (tout un bureau derrière une IP
  publique). Sur du SSH interne accessible seulement depuis le bastion, `limit`
  est superflu ; sur du SSH exposé, c'est un pansement — la vraie réponse reste
  l'authentification par clé.
:::

---

**E18.7** — *Journalisation ufw et extraction d'un refus.*

```bash
sudo ufw logging medium
# depuis lab-adm : nc -zv 10.10.10.11 3306
sudo grep 'UFW BLOCK' /var/log/ufw.log | tail -5
sudo grep 'UFW BLOCK' /var/log/ufw.log | tail -1 | \
  grep -oE 'SRC=[0-9.]+|DPT=[0-9]+'
```

```console
SRC=10.10.10.10
DPT=3306
```

::: pourquoi
ufw journalise via le noyau (cible `LOG` de netfilter) vers `kern.*`, que rsyslog
range dans `/var/log/ufw.log` grâce à `/etc/rsyslog.d/20-ufw.conf`. Sans
rsyslog, tout reste dans le journal : `journalctl -k | grep 'UFW BLOCK'`.

Les niveaux : `low` journalise les paquets bloqués par la politique par défaut,
`medium` y ajoute les paquets `INVALID` et les nouvelles connexions refusées,
`high` ajoute tout le reste avec limitation de débit, `full` ne limite plus rien
— et remplit un disque en quelques heures sur une machine exposée. `medium` est
le réglage d'exploitation raisonnable.
:::

---

**E18.8** — *Zone active, services, ouverture HTTPS sur Rocky.*

```bash
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --list-all
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

```console
$ sudo firewall-cmd --list-all
public (active)
  target: default
  interfaces: ens18
  sources:
  services: cockpit dhcpv6-client ssh
  ports:
  masquerade: no
  rich rules:
```

::: pourquoi
`--list-all` sans `--zone` porte sur la zone **par défaut**, pas sur la zone
active — les deux coïncident le plus souvent, mais pas toujours. En cas de doute,
`--get-default-zone` et `--get-active-zones` répondent séparément aux deux
questions.

Un « service » firewalld n'est pas un service systemd : c'est un fichier XML de
`/usr/lib/firewalld/services/` qui nomme un ou plusieurs ports (et parfois des
modules conntrack). `firewall-cmd --get-services` les liste,
`--info-service=https` détaille. Nommer les services plutôt que les ports rend la
configuration lisible en audit — c'est l'avantage principal de firewalld.
:::

---

**E18.9** — *Rich rule PostgreSQL depuis 10.10.10.11 seulement.*

```bash
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" \
  source address="10.10.10.11/32" port port="5432" protocol="tcp" accept'
sudo firewall-cmd --reload
sudo firewall-cmd --list-all | grep -A2 'rich rules'
```

::: pourquoi
Les rich rules sont le niveau au-dessus des `--add-service` / `--add-port` : elles
combinent source, destination, port, action, journalisation et limitation de
débit dans une seule expression. Tout ce qui demande « ce port, mais seulement
pour cette source » passe par là, parce que `--add-port` ne sait pas exprimer de
source.

Deux variantes utiles à connaître :

```text
rule family="ipv4" source address="10.0.0.0/8" service name="ssh" \
  log prefix="ssh-lan " level="info" limit value="3/m" accept
rule family="ipv4" source address="192.0.2.0/24" drop
```

L'alternative « zone » (ranger 10.10.10.11 dans une zone `internal` qui autorise
PostgreSQL) est plus élégante quand les sources se regroupent naturellement par
niveau de confiance, et plus lourde pour une exception unique. On choisit selon
le nombre d'exceptions : au-delà de trois ou quatre rich rules, la zone gagne.
:::

---

**E18.10** — *`jail.local` minimal et fonctionnel.*

```ini
# /etc/fail2ban/jail.local
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 4
ignoreip = 127.0.0.1/8 ::1 10.10.10.10

[sshd]
enabled = true
```

```bash
sudo systemctl reload fail2ban      # ou fail2ban-client reload
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

::: pourquoi
On n'édite **jamais** `/etc/fail2ban/jail.conf` : il est remplacé à chaque mise à
jour du paquet. `jail.local` est lu **après** et surcharge clé par clé ; les
fichiers de `jail.d/` sont lus ensuite, par ordre alphabétique. La section
`[DEFAULT]` fournit les valeurs héritées par toutes les jails, chaque section de
jail ne redéfinissant que ses écarts.

`ignoreip` est la ligne qui évite l'incident : elle doit contenir le bastion, les
sondes de supervision et les IP d'astreinte. fail2ban n'y déclenche aucune
action, même si les échecs correspondent.

Sur Ubuntu 24.04, le paquet active déjà la jail `sshd` via
`/etc/fail2ban/jail.d/defaults-debian.conf` : la déclarer dans `jail.local` est
explicite et sans effet de bord — et rend la configuration lisible pour le
suivant.
:::

---

**E18.11** — *Tester le filtre `sshd` sur le journal d'attaque.*

```bash
fail2ban-regex ~/lab18/logs/auth-attaque.log \
               /etc/fail2ban/filter.d/sshd.conf
```

```console
Results
=======
Failregex: 132 total
|-  #) [# of hits] regular expression
|   1) [128] ^Failed \w+ for invalid user <F-USER>...
|   2) [4]   ^Failed \w+ for <F-USER>...
Lines: 162 lines, 0 ignored, 132 matched, 30 missed
```

Les IP qui seraient bannies s'obtiennent avec `--print-all-matched`, ou plus
simplement :

```bash
grep -E 'Failed (password|publickey)' ~/lab18/logs/auth-attaque.log \
  | grep -oE 'from [0-9.]+' | sort | uniq -c | sort -rn | head
```

::: pourquoi
Lire la sortie de `fail2ban-regex` correctement :

* **matched** : lignes attrapées par au moins une `failregex` ;
* **ignored** : lignes attrapées par `failregex` **puis** écartées par
  `ignoreregex` — c'est là qu'on voit un `ignoreregex` trop large ;
* **missed** : lignes non reconnues. Un nombre élevé n'est pas forcément un
  problème (un journal contient beaucoup de lignes normales), mais un `missed`
  qui contient des lignes d'attaque signale une regex trop étroite. L'option
  `--print-all-missed` les affiche.

C'est l'outil à utiliser **avant** de mettre une jail en service : écrire une
`failregex` directement dans `jail.local` et espérer, c'est se condamner à
déboguer à l'aveugle sur un système en production.
:::

---

**E18.12** — *Contextes SELinux : fichier, processus, booléen.*

```bash
ls -Zd /var/www/html
ps -eZ | grep nginx
getsebool httpd_can_network_connect
```

```console
system_u:object_r:httpd_sys_content_t:s0  /var/www/html
system_u:system_r:httpd_t:s0    1834 ?  00:00:00 nginx
httpd_can_network_connect --> off
```

::: pourquoi
Les trois commandes couvrent les trois faces d'une décision SELinux : le
**sujet** (le processus et son domaine), l'**objet** (le fichier et son type), et
les **conditions** (les booléens qui activent ou non certaines règles). Une
décision SELinux est toujours de la forme « le domaine D a-t-il le droit de faire
l'action A sur un objet de type T ». Quand ça refuse, la réponse est dans l'un de
ces trois éléments — et l'AVC te dit lequel.

`id -Z` complète pour l'utilisateur interactif (`unconfined_u:unconfined_r:
unconfined_t:s0` sur un compte d'admin standard).
:::

---

**E18.13** — *nginx sur le port 8088 avec SELinux en enforcing.*

```bash
sudo sed -i 's/listen       80;/listen       8088;/' /etc/nginx/nginx.conf
sudo semanage port -a -t http_port_t -p tcp 8088
sudo systemctl restart nginx
sudo semanage port -l | grep '^http_port_t'
```

```console
http_port_t   tcp   8088, 80, 81, 443, 488, 8008, 8009, 8443, 9000
```

::: pourquoi
SELinux contrôle aussi les **ports**, via un étiquetage du numéro de port par
protocole. Le domaine `httpd_t` a le droit de faire un `name_bind` sur
`http_port_t`, et sur rien d'autre. Se lier à 8088, qui n'est étiqueté nulle
part, est refusé — nginx échoue au démarrage avec un `Permission denied` sur le
bind, ce qui ne ressemble pas du tout à un problème SELinux au premier regard.

`semanage port -a` ajoute une étiquette, `-m` **modifie** une étiquette
existante. Erreur fréquente : sur un port déjà étiqueté pour un autre type,
`-a` échoue avec `ValueError: Port tcp/8080 already defined` — il faut alors
`-m`, ou choisir un autre port.

Et c'est l'occasion de rappeler que le pare-feu est une couche indépendante :
SELinux autorise le bind, il faut encore `firewall-cmd --add-port=8088/tcp` pour
que quelqu'un d'autre puisse s'y connecter.
:::

---

**E18.14** — *Surface d'écoute.*

```bash
sudo ss -tulpnH
sudo ss -tulpnH | grep -vE '127\.0\.0\.1|\[::1\]'
```

```console
tcp LISTEN 0 511  0.0.0.0:80   0.0.0.0:*  users:(("nginx",pid=912,fd=6))
tcp LISTEN 0 128  0.0.0.0:22   0.0.0.0:*  users:(("sshd",pid=744,fd=3))
```

::: pourquoi
La surface d'attaque réseau d'une machine, c'est exactement cette liste. Tout ce
qui écoute sur `0.0.0.0` ou `::` est joignable depuis le réseau, indépendamment
du pare-feu — et si le pare-feu tombe, ou si l'attaquant est déjà dans le même
segment, c'est ce qui l'accueille.

Les options : `-t` TCP, `-u` UDP, `-l` en écoute, `-p` le processus (nécessite
root), `-n` sans résolution de noms (indispensable : sinon la commande se bloque
sur un DNS lent), `-H` sans ligne d'en-tête pour scripter.

Le réflexe de durcissement : pour chaque ligne non locale, se demander « ce
service a-t-il besoin d'être joignable de l'extérieur ? ». Si non, on le
restreint dans sa propre configuration (`bind_address`, `listen_addresses`,
`bindIp`), ce qui est bien plus solide qu'une règle de pare-feu — un service qui
n'écoute que sur la boucle locale ne peut pas être exposé par erreur.
:::

---

**E18.15** — *sysctl de durcissement.*

```bash
sudo tee /etc/sysctl.d/99-durcissement.conf >/dev/null <<'EOF'
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.tcp_syncookies = 1
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.randomize_va_space = 2
kernel.yama.ptrace_scope = 1
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
EOF
sudo sysctl --system
sysctl net.ipv4.conf.all.rp_filter kernel.kptr_restrict
```

::: pourquoi
`sysctl --system` relit **tous** les répertoires dans l'ordre de priorité :
`/etc/sysctl.d/`, `/run/sysctl.d/`, `/usr/lib/sysctl.d/`, puis
`/etc/sysctl.conf`. Le préfixe numérique donne l'ordre, le dernier lu gagne :
`99-` passe donc après les fichiers de la distribution, ce qui est l'intention.

Ce que fait chaque clé, en une phrase :

| Clé | Effet |
|---|---|
| `rp_filter` | jette les paquets dont la source n'est pas routable par l'interface d'arrivée (anti-usurpation) |
| `accept_redirects` | ignore les ICMP redirect, qui permettent de détourner le routage |
| `log_martians` | journalise les paquets à adresse impossible : signal d'attaque |
| `yama.ptrace_scope` | interdit à un processus d'attacher `ptrace` sur un autre processus non enfant (bloque le vol de secrets en mémoire) |
| `protected_symlinks` | empêche les attaques par lien symbolique dans `/tmp` |

Attention à `rp_filter` sur une machine multi-attachée ou en routage asymétrique
(deux interfaces, VPN, VRRP) : la valeur `1` (stricte) casse le trafic légitime.
La valeur `2` (mode lâche, RFC 3704) est le compromis dans ces cas-là.
:::

---

**E18.16** — *Autorité de certification de lab.*

```bash
mkdir -p ~/lab18/pki && cd ~/lab18/pki
openssl genrsa -out ca.key 4096
chmod 600 ca.key
openssl req -x509 -new -key ca.key -sha256 -days 3650 \
  -subj "/C=FR/O=Lab Local/CN=Lab Local CA" -out ca.crt
openssl x509 -in ca.crt -noout -subject -dates
```

```console
subject=C = FR, O = Lab Local, CN = Lab Local CA
notBefore=Sep 18 17:34:09 2026 GMT
notAfter=Sep 16 17:34:09 2036 GMT
```

::: pourquoi
`openssl req -x509` fait deux choses d'un coup : il crée une demande et
l'auto-signe. Les extensions d'une CA — `basicConstraints = critical,CA:TRUE` et
`keyUsage = keyCertSign, cRLSign` — sont ajoutées automatiquement par OpenSSL 3
dans ce mode ; on peut les imposer avec `-addext` pour être explicite.

`chmod 600` immédiatement, avant toute autre commande : une clé de CA est le
secret le plus critique de l'infrastructure. Quiconque l'obtient peut émettre un
certificat valide pour n'importe quel nom, et tous tes clients lui feront
confiance. Dans une vraie PKI, cette clé vit hors ligne ou dans un HSM, et on ne
s'en sert que pour signer des **intermédiaires**, jamais des certificats
serveurs.

10 ans pour une racine de lab est raisonnable : elle doit survivre à tous les
certificats qu'elle signe, et son renouvellement impose de redistribuer le
magasin de confiance sur toutes les machines.
:::

---

**E18.17** — *Certificat serveur signé par la CA, avec SAN.*

```bash
cd ~/lab18/pki
openssl genrsa -out app.key 2048
chmod 600 app.key
openssl req -new -key app.key -out app.csr \
  -subj "/C=FR/O=Lab Local/CN=app.lab.local"
cat > app.ext <<'EOF'
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:app.lab.local, DNS:lab-web.lab.local, IP:10.10.10.11
EOF
openssl x509 -req -in app.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out app.crt -days 397 -sha256 -extfile app.ext
openssl verify -CAfile ca.crt app.crt
openssl x509 -in app.crt -noout -ext subjectAltName
```

```console
app.crt: OK
X509v3 Subject Alternative Name:
    DNS:app.lab.local, DNS:lab-web.lab.local, IP Address:10.10.10.11
```

::: pourquoi
Trois points de méthode :

**Le fichier d'extensions est obligatoire.** `openssl x509 -req` ne recopie
**aucune** extension de la CSR par défaut. Sans `-extfile`, tu obtiens un
certificat sans SAN, sans `extendedKeyUsage`, donc inutilisable par un client
moderne — c'est exactement le piège de Q18.16, et il se produit ici même quand la
CSR contenait un SAN correct.

**`-CAcreateserial`** crée `ca.srl`, le compteur de numéros de série. Deux
certificats émis par la même CA avec le même numéro de série cassent la
révocation et font hurler certains clients. Le fichier doit être conservé avec la
CA.

**397 jours**, pas 3650 : c'est la durée maximale acceptée par les navigateurs
depuis septembre 2020 pour un certificat serveur public. Ta CA de lab n'y est pas
soumise techniquement, mais prendre l'habitude évite de produire, sur un vrai
projet, un certificat que Safari refusera.
:::

---

**E18.18** — *« Ce certificat expire-t-il dans moins de 30 jours ? »*

```bash
openssl x509 -in app.crt -noout -checkend 2592000
echo $?     # 0 = encore bon, 1 = expire dans la fenêtre (ou déjà expiré)
```

Depuis un service en écoute plutôt qu'un fichier :

```bash
openssl s_client -connect 10.10.10.11:443 -servername app.lab.local \
  </dev/null 2>/dev/null | openssl x509 -noout -checkend 2592000
```

::: pourquoi
`-checkend N` répond « le certificat sera-t-il encore valide dans N secondes ? »
par un code retour : 0 pour oui, 1 pour non. C'est précisément ce qu'attend une
sonde de supervision, un job cron ou un test en CI — pas besoin d'analyser une
date au format `notAfter=Oct 20 17:34:09 2027 GMT`, avec les pièges de la locale
et du fuseau que ça comporte.

Vérifier depuis le **service en écoute** plutôt que depuis le fichier est
supérieur pour un cas très concret : le certificat a bien été renouvelé sur le
disque, mais nginx n'a pas été rechargé et sert toujours l'ancien en mémoire. Le
test sur fichier dit « tout va bien », les clients voient un certificat expiré.
:::

---

**E18.19** — *Règle auditd sur `/etc/passwd` et `/etc/shadow`.*

```bash
sudo tee /etc/audit/rules.d/50-identite.rules >/dev/null <<'EOF'
-w /etc/passwd -p wa -k identite
-w /etc/shadow -p wa -k identite
EOF
sudo augenrules --load
sudo auditctl -l
sudo useradd -M -s /usr/sbin/nologin cobaye   # on déclenche
sudo ausearch -k identite -i | tail -20
```

::: pourquoi
Décomposition de la règle : `-w` pose une **surveillance** sur un chemin, `-p wa`
la limite aux accès en écriture (`w`) et aux changements d'attributs (`a` pour
*attribute*, pas *append*), `-k` attribue une **clé** qui servira à retrouver les
événements. Sans clé, on ne retrouve rien dans un `audit.log` de plusieurs
centaines de mégaoctets.

`augenrules --load` compile les fichiers de `/etc/audit/rules.d/` dans
`/etc/audit/audit.rules` puis les charge : c'est la commande qui rend les règles
**persistantes**. `auditctl -w ...` en direct fonctionne aussi, mais disparaît au
redémarrage. Et `systemctl restart auditd` est refusé sur RHEL/Rocky
(`Operation refused, unit auditd.service may be requested by dependency only`) :
il faut `service auditd restart` ou `augenrules --load`.

`ausearch -i` (*interpret*) traduit les UID en noms, les codes syscall en noms
d'appels système et les horodatages en dates lisibles. Sans `-i`, c'est
illisible.
:::

::: piege
auditd journalise **beaucoup**. Une règle trop large, du type
`-a always,exit -F arch=b64 -S all`, sature le disque en quelques minutes et
peut, selon `--backlog_wait_time` et la politique `failure_mode`, bloquer la
machine entière. On surveille des chemins sensibles et des appels système ciblés,
jamais « tout ». Et on vérifie `auditctl -s` (perdus, backlog) après mise en
place.
:::

---

**E18.20** — *Audit lynis.*

```bash
sudo lynis audit system
sudo grep -E '^(hardening_index|suggestion)=' /var/log/lynis-report.dat \
  | head -6
```

Le rapport lisible est en fin de sortie et dans `/var/log/lynis.log` (détail
complet) ; la version exploitable par script est `/var/log/lynis-report.dat`,
au format `clé=valeur`.

::: pourquoi
L'indice de durcissement (`hardening_index`) est un chiffre sur 100 qui n'a de
valeur que **relative** : il sert à mesurer une progression sur une même machine,
pas à comparer deux serveurs, encore moins à afficher un objectif contractuel.
Une machine de CI et un serveur de base de données n'ont pas la même cible.

Le vrai contenu utile, ce sont les suggestions et les avertissements, chacun avec
un identifiant (`KRNL-5820`, `SSH-7408`…) documenté sur le site du projet. La
bonne pratique consiste à traiter les suggestions une par une, et à consigner
celles qu'on écarte avec leur justification — le registre des écarts de QO18.10.

Lynis n'est pas un outil de conformité normatif : il ne certifie rien, il ne
suit aucun référentiel officiel. Pour du CIS formel, c'est OpenSCAP avec
`scap-security-guide`. Lynis est l'avis rapide qu'on lance en dix minutes sur
une machine inconnue, et il est excellent dans ce rôle.
:::

---

## 18.6 Labs

### **L18.1** — Politique de pare-feu de l'infrastructure

*Appliquer la matrice de flux sur les quatre machines, ufw d'un côté, firewalld de
l'autre, et prouver le résultat.*

**Étape 1 — `lab-web` (10.10.10.11)**

```bash
sudo ufw allow from 10.10.10.10 to any port 22 proto tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 'Nginx Full'
sudo ufw status numbered      # on relit AVANT d'armer
sudo ufw enable
sudo ufw logging medium
```

```console
$ sudo ufw status numbered
Status: active
     To                         Action      From
     --                         ------      ----
[ 1] 22/tcp                     ALLOW IN    10.10.10.10
[ 2] Nginx Full                 ALLOW IN    Anywhere
[ 3] Nginx Full (v6)            ALLOW IN    Anywhere (v6)
```

**Étape 2 — `lab-db` (10.10.10.12)**

```bash
sudo ufw allow from 10.10.10.10 to any port 22 proto tcp
sudo ufw allow from 10.10.10.11 to any port 5432 proto tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
```

**Étape 3 — `lab-adm` (10.10.10.10)**

```bash
sudo ufw allow from 10.10.10.0/24 to any port 22 proto tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
```

**Étape 4 — `lab-rhel` (10.10.10.13), firewalld**

```bash
sudo firewall-cmd --permanent --zone=public --add-service=http
sudo firewall-cmd --permanent --zone=public --add-service=https
sudo firewall-cmd --permanent --zone=public --remove-service=ssh
sudo firewall-cmd --permanent --zone=internal --add-source=10.10.10.10/32
sudo firewall-cmd --permanent --zone=internal --add-service=ssh
sudo firewall-cmd --reload
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --zone=internal --list-all
sudo systemctl enable --now firewalld
```

```console
$ sudo firewall-cmd --get-active-zones
internal
  sources: 10.10.10.10/32
public
  interfaces: ens18
```

**Étape 5 — la matrice, testée depuis `lab-adm`**

```bash
test_flux() {   # test_flux <ip> <port> <attendu: ouvert|ferme>
  if timeout 3 bash -c "</dev/tcp/$1/$2" 2>/dev/null; then
    r=ouvert; else r=ferme; fi
  printf '%-14s %-6s attendu=%-7s observe=%-7s %s\n' \
    "$1" "$2" "$3" "$r" \
    "$([ "$r" = "$3" ] && echo OK || echo ECHEC)"
}
test_flux 10.10.10.11 443  ouvert
test_flux 10.10.10.11 22   ouvert
test_flux 10.10.10.12 22   ouvert
test_flux 10.10.10.12 5432 ferme     # lab-adm n'est pas lab-web
test_flux 10.10.10.13 80   ouvert
test_flux 10.10.10.13 3306 ferme
```

| Source | Destination:port | Attendu |
|---|---|---|
| lab-adm | lab-web:443 | ouvert |
| lab-adm | lab-db:5432 | fermé |
| lab-web | lab-db:5432 | ouvert |
| lab-db | lab-web:22 | fermé |

**Étape 6 — la preuve dans le journal**

```bash
sudo grep 'UFW BLOCK' /var/log/ufw.log | tail -3
```

::: pourquoi
Trois décisions de conception structurent ce lab.

**La règle d'autorisation SSH passe en premier, avant `enable`.** C'est le seul
ordre qui ne coupe pas la session en cours. Les connexions déjà établies
survivraient (règle `ESTABLISHED` de `before.rules`), mais toute reconnexion
serait impossible : sur une machine distante sans console, c'est une intervention
sur site.

**`deny incoming` + `allow outgoing` est la politique de départ standard.**
Filtrer la sortie a du sens sur un serveur exposé (ça freine l'exfiltration et le
rappel vers un serveur de commande), mais ça casse les mises à jour, le DNS, le
NTP et la supervision si on le fait sans préparation. Pour un premier jeu de
règles, on ferme l'entrée et on documente la sortie comme un chantier séparé.

**Côté Rocky, on n'ouvre pas SSH dans `public`, on range la source dans
`internal`.** C'est le mode de pensée firewalld : on ne décrit pas des exceptions
par port, on décrit des **niveaux de confiance** auxquels on rattache des
sources. La source l'emporte sur l'interface dans la décision de zone, donc
10.10.10.10 arrive en `internal` (qui autorise SSH) et tout le reste en `public`
(qui ne l'autorise pas). Ajouter un second administrateur devient
`--zone=internal --add-source=…`, sans toucher aux services.

Le test `</dev/tcp/ip/port` est un `connect()` bash sans dépendance : il
fonctionne là où `nc` n'est pas installé, et le `timeout 3` distingue les deux
comportements de refus — `DROP` (silence, donc timeout) et `REJECT` (refus
immédiat). C'est exactement l'information dont tu as besoin pour savoir si le
paquet a été jeté par un pare-feu ou refusé par une machine.
:::

::: piege
Deux pièges attendent à ce lab.

**IPv6.** ufw applique les règles aux deux familles quand `IPV6=yes` dans
`/etc/default/ufw` (défaut sur Ubuntu). Une règle `from 10.10.10.10` n'a par
construction pas d'équivalent v6 : si la machine a une adresse IPv6 joignable,
tu as ouvert un chemin non filtré. Contrôle : `sudo ip -6 addr` et
`sudo ufw status numbered` où les règles `(v6)` apparaissent explicitement.

**Docker sur `lab-ops`.** Docker écrit ses propres règles dans la chaîne
`DOCKER-USER` et dans le `nat`, **en amont** des chaînes ufw. Un conteneur lancé
avec `-p 5432:5432` est joignable depuis tout le réseau malgré `ufw default deny
incoming`. Le contrôle est `sudo iptables -S DOCKER-USER` et le correctif est de
publier sur `127.0.0.1:5432:5432` ou d'ajouter des règles dans `DOCKER-USER`.
C'est la principale cause de bases de données exposées par accident.
:::

---

### **L18.2** — fail2ban : jail SSH et filtre nginx maison

*Configurer fail2ban, écrire un filtre `nginx-scan`, le tester, bannir puis
débannir.*

**Étapes 1 et 2 — `jail.local` et le `logpath` réel**

```ini
# /etc/fail2ban/jail.local
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 4
ignoreip = 127.0.0.1/8 ::1 10.10.10.10
banaction = ufw

[sshd]
enabled = true
backend = systemd
```

```bash
sudo fail2ban-client get sshd logpath     # ce que la jail suit vraiment
sudo systemctl reload fail2ban
sudo fail2ban-client status sshd
```

**Étape 3 — le filtre**

```ini
# /etc/fail2ban/filter.d/nginx-scan.conf
[Definition]
cible = (?:wp-login\.php|\.env|admin\.php|phpmyadmin/|\.git/config)
failregex = ^<HOST> -[^"]*"[A-Z]+ /%(cible)s\S*[^"]*" (?:403|404) 
ignoreregex =
datepattern = ^[^\[]*\[({DATE})
```

**Étape 4 — le test**

```bash
fail2ban-regex ~/lab18/logs/acces-scan.log \
               /etc/fail2ban/filter.d/nginx-scan.conf
```

```console
Lines: 192 lines, 0 ignored, 60 matched, 132 missed
```

Soit 20 correspondances pour chacune des trois IP de scan. Les lignes
« missed » sont les requêtes légitimes (`/index.html`, `/sante`) et les
chemins de scan que le filtre ne couvre volontairement pas
(`/wp-admin/`, `/vendor/…`, `/config.json`) : à toi de décider si tu les
ajoutes, en pesant le risque de faux positif.

**Étape 5 — la jail**

```ini
# /etc/fail2ban/jail.local (suite)
[nginx-scan]
enabled  = true
port     = http,https
filter   = nginx-scan
logpath  = /var/log/nginx/access.log
maxretry = 6
findtime = 5m
bantime  = 2h
```

**Étapes 6 et 7 — bannir puis débannir**

```bash
# depuis lab-db :
for i in $(seq 1 8); do curl -s -o /dev/null http://10.10.10.11/.env; done
# sur lab-web :
sudo fail2ban-client status nginx-scan
sudo nft list ruleset | grep -A5 'f2b\|ufw-user-input'
sudo fail2ban-client set nginx-scan unbanip 10.10.10.12
```

```console
$ sudo fail2ban-client status nginx-scan
Status for the jail: nginx-scan
|- Filter
|  |- Currently failed: 0
|  |- Total failed:     8
|  `- File list:        /var/log/nginx/access.log
`- Actions
   |- Currently banned: 1
   `- Banned IP list:   10.10.10.12
```

::: pourquoi
**La regex, morceau par morceau.**

* `^<HOST>` : fail2ban remplace `<HOST>` par un motif d'adresse IPv4/IPv6 encadré
  d'un groupe nommé. C'est ce groupe qui fournit l'IP à bannir : il doit se
  trouver là où l'adresse se trouve réellement dans la ligne — ici en première
  position, puisque le format `combined` commence par `$remote_addr`.
* ` -[^"]*"` : on saute l'identité, l'utilisateur et l'horodatage sans écrire de
  `.*` gourmand. `[^"]*` ne peut pas déborder au-delà du premier guillemet, ce
  qui évite qu'un `User-Agent` malveillant contenant `/wp-login.php` déclenche un
  faux positif — attaque réelle, qui permet de faire bannir l'IP d'autrui.
* `(?:…)` : groupes **non capturants**. Un groupe capturant supplémentaire
  perturbe la récupération des champs `<F-…>` de fail2ban ; on prend l'habitude.
* `%(cible)s` : les fichiers de fail2ban sont lus par le `ConfigParser` de
  Python, qui sait interpoler une clé définie plus haut dans la même
  section. On sort ainsi la liste des chemins du corps de la regex, ce qui
  la rend relisible et modifiable sans y toucher — c'est exactement ce que
  fait `jail.conf` avec `%(__prefix_line)s`.
* `(?:403|404) ` avec l'espace final : le code de statut est le champ qui suit la
  requête. Sans lui, on bannirait aussi les requêtes réussies — donc les tiens.

**Le `datepattern`.** Le format `combined` place la date entre crochets après
l'IP. fail2ban sait le reconnaître seul dans la plupart des cas, mais le déclarer
supprime toute ambiguïté et évite le message `no date pattern matched`. Sans date
exploitable, fail2ban utilise l'heure de lecture de la ligne : ça marche en
temps réel et fausse tout rejeu de journal.

**`banaction = ufw`.** Par défaut, fail2ban insère ses propres règles
`iptables-multiport` dans une chaîne `f2b-*`. Sur une machine pilotée par ufw,
deux jeux de règles coexistent alors, et `ufw status` n'en montre qu'un — ce qui
est précisément la panne BF18.4. Déclarer `banaction = ufw` fait passer les
bannissements par `ufw insert 1 deny from <ip>`, donc visibles dans
`ufw status numbered`. Plus lisible en exploitation, au prix d'une réécriture du
jeu de règles à chaque ban.

**Ce que la configuration ne verra pas (étape 8)** — les trois réponses
attendues :

1. un scan **distribué** sur 500 IP à raison de deux requêtes chacune : jamais
   6 échecs en 5 minutes pour une même IP ;
2. un scan **lent** (une requête toutes les dix minutes) : chaque requête sort de
   la fenêtre `findtime` avant que la suivante n'arrive ;
3. un scan qui n'obtient que des **200** — par exemple l'énumération de contenus
   qui existent réellement, ou un scan derrière un reverse proxy, où le
   `$remote_addr` journalisé est celui du proxy et non celui de l'attaquant.
:::

::: piege
Sur Ubuntu 24.04, la jail `sshd` peut ne rien voir si tu la laisses en
`backend = auto` sur une machine où rsyslog n'écrit plus `/var/log/auth.log`
(configuration journal seul). Symptôme : la jail est active,
`Currently failed: 0` en permanence, et `fail2ban-client get sshd logpath`
renvoie une liste vide. Le correctif est `backend = systemd`, qui fait lire le
journal systemd directement ; `logpath` devient alors sans objet.
:::

---

### **L18.3** — SELinux : mettre une application en production sans le désactiver

*Servir `/srv/api/public` sur le port 8088 avec un `proxy_pass` sortant, en
enforcing.*

**Étape 1 — état des lieux**

```bash
getenforce                 # mode COURANT
sestatus                   # mode courant ET mode configuré au boot
```

```console
SELinux status:                 enabled
Current mode:                   enforcing
Mode from config file:          enforcing
```

**Étapes 2 et 3 — le port**

```bash
sudo mkdir -p /srv/api/public
echo '<h1>API lab</h1>' | sudo tee /srv/api/public/index.html
sudo sed -i 's/listen       80;/listen       8088;/' /etc/nginx/nginx.conf
sudo systemctl start nginx            # echec
sudo journalctl -u nginx -n 20 --no-pager
sudo ausearch -m AVC -ts recent | tail -20
sudo semanage port -a -t http_port_t -p tcp 8088
sudo systemctl start nginx            # OK
```

```console
nginx: [emerg] bind() to 0.0.0.0:8088 failed (13: Permission denied)
type=AVC msg=audit(...): avc:  denied  { name_bind } for  pid=2114
  comm="nginx" src=8088 scontext=system_u:system_r:httpd_t:s0
  tcontext=system_u:object_r:unreserved_port_t:s0 tclass=tcp_socket
```

**Étapes 4 et 5 — le contexte du contenu**

```bash
ls -Zd /srv/api/public /usr/share/nginx/html
sudo semanage fcontext -a -t httpd_sys_content_t "/srv/api(/.*)?"
sudo restorecon -Rv /srv/api
ls -Zd /srv/api/public
```

```console
unconfined_u:object_r:var_t:s0            /srv/api/public
system_u:object_r:httpd_sys_content_t:s0  /usr/share/nginx/html
...
Relabeled /srv/api from unconfined_u:object_r:var_t:s0 to
          unconfined_u:object_r:httpd_sys_content_t:s0
```

**Étape 6 — l'appel sortant**

```nginx
location /api/ {
    proxy_pass http://10.10.10.11/;
    proxy_set_header Host $host;
}
```

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -s -o /dev/null -w '%{http_code}\n' http://10.10.10.13:8088/api/  # 502
sudo ausearch -m AVC -ts recent | audit2why
sudo setsebool -P httpd_can_network_connect on
curl -s -o /dev/null -w '%{http_code}\n' http://10.10.10.13:8088/api/  # 200
```

::: pourquoi
Ce lab fait passer par les **trois** familles de correctifs SELinux, dans l'ordre
où on les rencontre en vrai.

**Le port (`semanage port`).** SELinux étiquette les numéros de port. `httpd_t`
peut se lier à `http_port_t` et à rien d'autre. 8088 n'étant étiqueté nulle part,
il tombe dans `unreserved_port_t`, et le `name_bind` est refusé. Le symptôme
(`bind() failed (13: Permission denied)`) ressemble trait pour trait à un port
déjà occupé ou à un manque de privilège : seul l'AVC tranche.

**Le contexte (`semanage fcontext` + `restorecon`).** `/srv` n'est pas un chemin
que la politique par défaut connaît pour du contenu web ; tout y hérite de
`var_t`. `chcon -t httpd_sys_content_t -R /srv/api` aurait « marché » — jusqu'au
prochain `restorecon -R /`, au prochain réétiquetage, ou à la prochaine
restauration de sauvegarde, qui rendraient le type `var_t` puisque c'est ce que
dit la politique. `semanage fcontext` modifie **la politique**, donc la vérité de
référence ; `restorecon` l'applique à l'existant. Le couple est indissociable :
`semanage` seul ne change rien aux fichiers déjà là.

**Le booléen (`setsebool -P`).** L'interdiction faite au serveur web d'ouvrir des
connexions sortantes est une des meilleures protections de la politique targeted :
elle casse l'étape « rappel vers le serveur de commande » de la quasi-totalité des
exploitations web. Un reverse proxy en a légitimement besoin, donc un booléen
existe. `-P` écrit la valeur dans la politique (persistante) ; sans `-P`, elle
est perdue au reboot — et ta prod retombe en panne au redémarrage suivant, trois
mois plus tard, sans que personne ne fasse le lien.

**La procédure à rendre (étape 7)** tient en quatre commandes, aucune ne touchant
au mode SELinux :

```bash
sudo semanage port -a -t http_port_t -p tcp 8088
sudo semanage fcontext -a -t httpd_sys_content_t "/srv/api(/.*)?"
sudo restorecon -Rv /srv/api
sudo setsebool -P httpd_can_network_connect on
```
:::

::: piege
Pourquoi `audit2allow -a -M tout` était la mauvaise porte, concrètement : sur
cette machine, `ausearch -m AVC -ts today` contient les refus de ce lab **et**
tout ce qui a été refusé par ailleurs. Un module généré en bloc accorderait à
`httpd_t` le `name_bind` sur `unreserved_port_t` — c'est-à-dire sur **tous** les
ports non attribués de la machine, pas seulement 8088 — en plus du reste. On
remplace un contrôle précis par une autorisation large, et on perd le bénéfice
de SELinux tout en gardant son coût. `audit2allow` se justifie pour un besoin
qu'aucun booléen ni étiquetage ne couvre, après lecture du `.te` généré.
:::

---

### **L18.4** — Mini-PKI et HTTPS correct sur `lab-web`

*CA de lab, certificat serveur, déploiement nginx, confiance côté client,
surveillance d'expiration.*

**Étapes 1 à 3 — la PKI** (voir E18.16 et E18.17 pour le détail des commandes)

```bash
openssl x509 -in app.crt -noout -subject -issuer -dates
openssl x509 -in app.crt -noout -ext subjectAltName
openssl x509 -in app.crt -noout -modulus | openssl sha256
openssl rsa  -in app.key -noout -modulus | openssl sha256   # doit être égal
openssl verify -CAfile ca.crt app.crt
```

**Étape 4 — déploiement sur `lab-web`**

```bash
scp app.crt ca.crt mathieu@10.10.10.11:/tmp/
scp app.key mathieu@10.10.10.11:/tmp/
# sur lab-web
sudo install -o root -g root -m 0644 /tmp/app.crt /etc/ssl/certs/
sudo install -o root -g ssl-cert -m 0640 /tmp/app.key /etc/ssl/private/
sudo install -o root -g root -m 0644 /tmp/ca.crt \
     /usr/local/share/ca-certificates/lab-local-ca.crt
sudo update-ca-certificates
shred -u /tmp/app.key
```

**Étape 5 — nginx**

```nginx
# /etc/nginx/sites-available/app.lab.local
server {
    listen 80;
    server_name app.lab.local lab-web.lab.local;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name app.lab.local lab-web.lab.local;

    ssl_certificate     /etc/ssl/certs/app.crt;
    ssl_certificate_key /etc/ssl/private/app.key;

    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    add_header Strict-Transport-Security
               "max-age=63072000; includeSubDomains" always;

    root /var/www/html;
    index index.html;
}
```

::: piege
Deux détails de syntaxe qui coûtent un `nginx -t` en échec. Un fichier de
configuration nginx **n'accepte pas le `\` de continuation de ligne** :
une directive s'étale sur plusieurs lignes sans rien ajouter, seul le
`;` final la termine. Et `listen 443 ssl http2;` est la forme valable
pour nginx 1.24 (Ubuntu 24.04) et les versions antérieures ; à partir de
nginx 1.25, cette forme est dépréciée au profit d'une directive séparée
`http2 on;`. Vérifie ta version avec `nginx -v` avant de recopier une
configuration trouvée en ligne.
:::

```bash
sudo ln -sf /etc/nginx/sites-available/app.lab.local \
            /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

**Étapes 6 et 7 — la confiance et la vérification**

```bash
# sur lab-adm
echo '10.10.10.11 app.lab.local lab-web.lab.local' | sudo tee -a /etc/hosts
sudo install -m 0644 ~/lab18/pki/ca.crt \
     /usr/local/share/ca-certificates/lab-local-ca.crt
sudo update-ca-certificates
curl -sI https://app.lab.local | head -3
openssl s_client -connect 10.10.10.11:443 -servername app.lab.local \
  </dev/null 2>/dev/null | grep -E 'Protocol|Verify return code|subject='
```

```console
HTTP/2 200
strict-transport-security: max-age=63072000; includeSubDomains
Verify return code: 0 (ok)
```

**Étape 8 — `~/lab18/bin/verif-certs.sh`**

```bash
#!/usr/bin/env bash
# verif-certs.sh — surveille l'expiration des certificats TLS
# usage : verif-certs.sh hote:port [hote:port ...]
# sortie : 0 tout va bien, 1 expire sous 30 j, 2 expire sous 15 j
set -uo pipefail

SEUIL_CRIT=$((15 * 86400))
SEUIL_AVER=$((30 * 86400))
rc=0

for cible in "$@"; do
  hote=${cible%%:*}; port=${cible##*:}
  cert=$(echo | timeout 5 openssl s_client -connect "$hote:$port" \
         -servername "$hote" 2>/dev/null | \
         openssl x509 2>/dev/null) || cert=""

  if [ -z "$cert" ]; then
    printf '%-28s INJOIGNABLE\n' "$cible"; rc=2; continue
  fi

  fin=$(printf '%s\n' "$cert" | openssl x509 -noout -enddate | cut -d= -f2)
  sujet=$(printf '%s\n' "$cert" | openssl x509 -noout -subject)
  reste=$(( ( $(date -d "$fin" +%s) - $(date +%s) ) / 86400 ))

  if printf '%s\n' "$cert" | \
       openssl x509 -noout -checkend "$SEUIL_CRIT" >/dev/null; then
    if printf '%s\n' "$cert" | \
         openssl x509 -noout -checkend "$SEUIL_AVER" >/dev/null; then
      etat=OK
    else
      etat=AVERTISSEMENT; [ "$rc" -lt 1 ] && rc=1
    fi
  else
    etat=CRITIQUE; rc=2
  fi

  printf '%-28s %-14s %4s j   %s\n' "$cible" "$etat" "$reste" "$sujet"
done
exit "$rc"
```

```console
$ ~/lab18/bin/verif-certs.sh app.lab.local:443 10.10.10.13:443
app.lab.local:443            OK              396 j   subject=CN = app.lab.local
10.10.10.13:443              CRITIQUE          6 j   subject=CN = lab-rhel
```

::: pourquoi
**Pourquoi interroger le service et non le fichier.** Le script se connecte et
lit ce qui est **réellement servi**. C'est la seule mesure qui attrape le cas le
plus fréquent en production : certificat renouvelé sur le disque, service jamais
rechargé, clients en erreur. Un contrôle sur `/etc/ssl/certs/*.crt` aurait dit
que tout allait bien.

**Les droits sur la clé.** `0640 root:ssl-cert` sur Ubuntu : nginx démarre en
root, lit la clé, puis ses processus de travail abandonnent leurs privilèges pour
`www-data`. La clé n'a donc pas besoin d'être lisible par `www-data` — et ne doit
surtout pas l'être : une faille de traversée de répertoire dans l'application
donnerait la clé privée. Le groupe `ssl-cert` existe pour les services qui, eux,
lisent la clé après avoir abandonné leurs privilèges.

**HSTS.** L'en-tête `Strict-Transport-Security` demande au navigateur de ne plus
jamais contacter ce nom en clair pendant `max-age` secondes, ce qui neutralise
l'attaque de rétrogradation (l'utilisateur tape `app.lab.local`, un attaquant
intercepte la requête HTTP avant la redirection). Deux précautions : il n'a
d'effet qu'en HTTPS (le navigateur ignore l'en-tête reçu en clair), et il est
**irrévocable côté client** pour la durée annoncée — si tu poses
`max-age=63072000` puis que tu perds ton certificat, les navigateurs qui ont vu
l'en-tête refuseront de se connecter pendant deux ans. On monte le `max-age`
progressivement (300, puis 86400, puis deux ans) quand la chaîne est stable.
`includeSubDomains` étend cette contrainte à tous les sous-domaines : à ne poser
que si tous sont effectivement en HTTPS.

**`ssl_session_tickets off`.** Les tickets de session sont chiffrés par une clé
que nginx garde en mémoire et ne fait pas tourner par défaut : un attaquant qui
obtient cette clé peut déchiffrer les sessions passées, ce qui annule la
confidentialité persistante. Sans reprise de session par cluster, le cache
partagé (`shared:SSL:10m`) suffit.

**Let's Encrypt, en une phrase** : en environnement réel, tout ceci se résume à
`sudo certbot --nginx -d app.example.com`, qui obtient le certificat, modifie la
configuration nginx, et installe un timer systemd (`certbot.timer`) qui renouvelle
deux fois par jour dès qu'il reste moins de 30 jours. `certbot renew --dry-run`
vérifie que le renouvellement fonctionnera. Ce qui ne change pas, c'est la
surveillance : le timer peut être masqué, la validation peut échouer, et
`verif-certs.sh` reste ton filet.
:::

---

### **L18.5** — Durcissement et audit de `lab-ops`

*État des lieux, durcissement, avant/après chiffré.*

**Étape 1 — état des lieux**

```bash
{
  echo '## Ports en écoute'; sudo ss -tulpn
  echo; echo '## Services actifs'
  systemctl list-units --type=service --state=running --no-pager
  echo; echo '## Comptes avec shell valide'
  awk -F: '$7 !~ /(nologin|false)$/ {print $1, $3, $7}' /etc/passwd
  echo; echo '## Comptes sans mot de passe'
  sudo awk -F: '($2==""){print $1}' /etc/shadow
  echo; echo '## Comptes UID 0'
  awk -F: '($3==0){print $1}' /etc/passwd
  echo; echo '## SUID/SGID'
  sudo find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null
  echo; echo '## Cron'
  sudo ls -l /etc/cron.d /etc/cron.daily /var/spool/cron/crontabs 2>/dev/null
} > ~/lab18/etat-initial.md
```

**Étape 2 — lynis avant**

```bash
sudo lynis audit system --quiet
grep '^hardening_index=' /var/log/lynis-report.dat
sudo cp /var/log/lynis-report.dat ~/lab18/lynis-avant.dat
```

**Étape 3 — le durcissement**

```bash
# mises à jour de sécurité automatiques
sudo dpkg-reconfigure -plow unattended-upgrades
sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
sudo unattended-upgrade --dry-run -d | tail -5

# sysctl (voir E18.15)
sudo sysctl --system

# /tmp en noexec via l'unité systemd
sudo cp /usr/share/systemd/tmp.mount /etc/systemd/system/
sudo sed -i 's/^Options=.*/Options=mode=1777,strictatime,nosuid,nodev,noexec/' \
     /etc/systemd/system/tmp.mount
sudo systemctl daemon-reload && sudo systemctl enable --now tmp.mount
findmnt /tmp

# modules noyau
sudo tee /etc/modprobe.d/99-durcissement.conf >/dev/null <<'EOF'
install usb-storage /bin/true
install firewire-core /bin/true
install cramfs /bin/true
install dccp /bin/true
install sctp /bin/true
EOF

# umask et mots de passe
sudo sed -i 's/^UMASK.*/UMASK 027/' /etc/login.defs
sudo sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS 365/;
             s/^PASS_WARN_AGE.*/PASS_WARN_AGE 14/' /etc/login.defs
sudo sed -i 's/^# minlen.*/minlen = 12/' /etc/security/pwquality.conf

# bannière
sudo tee /etc/issue.net >/dev/null <<'EOF'
Acces reserve aux personnes autorisees. Toute activite est journalisee
et susceptible d'etre controlee. Deconnectez-vous immediatement si vous
n'etes pas autorise.
EOF
```

**Étape 5 — auditd**

```bash
sudo tee /etc/audit/rules.d/99-lab.rules >/dev/null <<'EOF'
-w /etc/passwd            -p wa -k identite
-w /etc/shadow            -p wa -k identite
-w /etc/sudoers           -p wa -k privileges
-w /etc/sudoers.d/        -p wa -k privileges
-w /etc/ssh/sshd_config   -p wa -k acces-distant
-a always,exit -F path=/usr/bin/passwd -F perm=x \
   -F auid>=1000 -F auid!=unset -k exec-passwd
EOF
sudo augenrules --load
sudo auditctl -l
sudo auditctl -s | head -3
```

**Étape 6 — lynis après**

```bash
sudo lynis audit system --quiet
grep '^hardening_index=' /var/log/lynis-report.dat
```

::: pourquoi
**`install <module> /bin/true` plutôt que `blacklist <module>`.** `blacklist`
n'empêche que le chargement **automatique** par udev ; un `modprobe usb-storage`
explicite fonctionne toujours, et un périphérique dont un autre module dépend
peut le tirer. La directive `install`, elle, remplace la commande de chargement
par `/bin/true` : le module ne se charge dans aucun cas. C'est la forme retenue
par les référentiels CIS et ANSSI.

**`/tmp` par `tmp.mount` plutôt que par `fstab`.** L'unité est fournie par
systemd (`/usr/share/systemd/tmp.mount`), elle ordonne correctement le montage
par rapport aux `local-fs.target` et aux services, et elle est plus facile à
désactiver proprement en cas d'incident (`systemctl disable tmp.mount`). Sur une
machine gérée intégralement par systemd, c'est la forme idiomatique. `fstab`
reste parfaitement valable et se lit mieux en audit : les deux choix se
défendent, l'important est de savoir pourquoi on a choisi.

**`auid` dans la règle auditd.** `auid` est l'identité **d'origine** de la
session, conservée à travers `su` et `sudo` : c'est ce qui permet de savoir que
c'est `mathieu` qui a exécuté la commande en tant que root. `-F auid>=1000
-F auid!=unset` limite la règle aux vrais utilisateurs humains et écarte le bruit
des démons.

**La bannière** doit être affichée **avant** authentification (`Banner
/etc/issue.net` dans `sshd_config`, voir module 14). Son intérêt n'est pas
technique mais juridique : dans plusieurs juridictions, poursuivre un accès non
autorisé suppose d'avoir averti. `/etc/issue` sert les consoles locales,
`/etc/issue.net` le réseau.

**L'avant/après lynis** est l'objet du livrable, et pas le score absolu. Trois
suggestions typiques qu'on écarte avec justification : le durcissement du
compilateur (`gcc` est nécessaire sur une machine de CI), le partitionnement
séparé de `/var` (impossible sans réinstallation, risque accepté et consigné), la
désactivation d'IPv6 (utilisée par le réseau de conteneurs). C'est ce registre
des écarts, pas le chiffre, que l'auditeur lira.
:::

::: piege
`/tmp` en `noexec` casse silencieusement des choses. Teste **avant** de
considérer l'étape finie :

```bash
printf '#!/bin/sh\necho ok\n' > /tmp/t.sh && chmod +x /tmp/t.sh && /tmp/t.sh
# attendu : /tmp/t.sh: Permission denied
```

Et surveille ensuite les paquets qui échouent à l'installation avec un
`Permission denied` sur `/tmp/…` : la réponse est `TMPDIR=/var/tmp/install`, pas
le retrait de l'option. Enfin, `noexec` n'est pas une barrière absolue :
`/lib64/ld-linux-x86-64.so.2 /tmp/binaire` exécute le binaire malgré le montage,
en le chargeant explicitement par l'éditeur de liens. C'est une gêne, pas un mur.
:::

---

## 18.7 Break & Fix

### **BF18.1** — « Le pare-feu est bon, pourtant la base est injoignable »

**Démarche de diagnostic**

```bash
# 1. le service écoute-t-il ? (il écoute, l'énoncé le dit, on confirme)
sudo ss -tlnp | grep 5432
# 2. le paquet arrive-t-il ?
sudo tcpdump -ni any port 5432 -c 5      # depuis lab-web : nc -zv ... 5432
# -> on voit les SYN arriver, aucune réponse : DROP local
# 3. la vue du frontal
sudo ufw status numbered                  # la règle ALLOW est bien là
# 4. LA commande qui tranche : la vue du noyau
sudo iptables -L -n -v --line-numbers | head -40
sudo nft list ruleset | less
```

```console
Chain ufw-before-input (1 references)
 pkts bytes target     prot opt in     out     source    destination
   47  2820 DROP    tcp  --  *   *   0.0.0.0/0  0.0.0.0/0  tcp dpt:5432
```

**Cause racine** : une règle de refus a été ajoutée dans
`/etc/ufw/before.rules`, donc dans la chaîne `ufw-before-input`, qui est
traversée **avant** `ufw-user-input`. `ufw status` n'affiche que les règles
utilisateur : la règle fautive lui est structurellement invisible.

**Correctif**

```bash
sudo cp /etc/ufw/before.rules /root/before.rules.casse
sudo sed -i '/--dport 5432 -j DROP/d' /etc/ufw/before.rules
sudo ufw reload
sudo iptables -L ufw-before-input -n -v | grep 5432   # plus rien
```

**Prévention** : toute modification de `before.rules` / `after.rules` doit être
versionnée et commentée — ces fichiers échappent au `ufw status` que tout le
monde consulte. En exploitation, le réflexe à acquérir est de ne jamais conclure
sur `ufw status` : la commande de vérité est `iptables -L -n -v` (avec les
compteurs) ou `nft list ruleset`.

::: pourquoi
Le chemin complet d'un paquet dans le jeu de règles ufw, qu'il faut avoir en tête
pour comprendre pourquoi la règle utilisateur n'a jamais été atteinte :

```text
INPUT
 └─ ufw-before-logging-input
 └─ ufw-before-input        <- conntrack, loopback, ICMP, ET LA RÈGLE FAUTIVE
 └─ ufw-user-input          <- ce que montre « ufw status »
 └─ ufw-after-input
 └─ ufw-after-logging-input
 └─ ufw-reject-input
 └─ ufw-track-input
```

`before.rules` existe pour les règles qui doivent primer sur tout (acceptation du
trafic établi, de la boucle locale, du DHCP). C'est donc, par construction,
l'endroit idéal pour cacher un blocage — volontairement, ou par une modification
maladroite d'un collègue qui « voulait juste bloquer temporairement ».

**La commande qui aurait fait gagner vingt minutes** : `iptables -L -n -v`. Les
compteurs de paquets désignent immédiatement la règle qui absorbe le trafic. Une
règle `DROP` dont le compteur augmente exactement au rythme de tes tentatives ne
laisse aucune place à l'interprétation.
:::

::: piege
Variante du même piège, à connaître parce qu'elle est plus fréquente encore en
entreprise : **Docker**. Le démon insère ses règles dans `DOCKER-USER` et dans la
table `nat`, en amont des chaînes ufw, et fait du DNAT avant que `ufw-user-input`
ne soit consulté. Conséquence : un conteneur publié avec `-p 5432:5432` est
joignable depuis tout le réseau **malgré** `ufw default deny incoming`, et
`ufw status` n'en dit rien. Même méthode de diagnostic, même conclusion :
regarder le noyau, pas le frontal.
:::

---

### **BF18.2** — « Le site renvoie 403 sur une seule page »

**Démarche de diagnostic**

```bash
# 1. les droits POSIX : parfaits, on écarte
ls -l /usr/share/nginx/html/rapport.html
# 2. un seul fichier concerné, les autres marchent -> propriété du FICHIER
ls -Z /usr/share/nginx/html/
# 3. confirmation par l'AVC
sudo ausearch -m AVC -ts recent -c nginx | tail -20
sudo sealert -a /var/log/audit/audit.log | head -30   # si installé
```

```console
$ ls -Z /usr/share/nginx/html/
unconfined_u:object_r:user_home_t:s0      rapport.html
system_u:object_r:httpd_sys_content_t:s0  index.html

type=AVC msg=audit(...): avc: denied { read } for pid=1122 comm="nginx"
  name="rapport.html" scontext=system_u:system_r:httpd_t:s0
  tcontext=unconfined_u:object_r:user_home_t:s0 tclass=file
```

**Cause racine** : le fichier a été déplacé depuis `/home` avec `mv`. `mv` sur le
même système de fichiers est un `rename()` : l'inode ne change pas, donc
l'attribut étendu `security.selinux` non plus. Le fichier est arrivé dans le
docroot avec le type `user_home_t`, que le domaine `httpd_t` n'a pas le droit de
lire.

**Correctif niveau 1 — ce fichier**

```bash
sudo restorecon -v /usr/share/nginx/html/rapport.html
curl -s -o /dev/null -w '%{http_code}\n' http://localhost/rapport.html   # 200
```

**Correctif niveau 2 — que ça ne se reproduise plus**

```bash
sudo semanage fcontext -a -t httpd_sys_content_t \
     "/usr/share/nginx/html(/.*)?"     # ici déjà couvert par la politique
sudo restorecon -Rv /usr/share/nginx/html
# et surtout, l'automatisme :
sudo systemctl enable --now restorecond     # paquet policycoreutils-restorecond
```

**Prévention** : `restorecond` surveille une liste de chemins
(`/etc/selinux/restorecond.conf`) et réétiquette automatiquement tout fichier qui
y apparaît avec un mauvais contexte. C'est le filet pour les répertoires
alimentés par des humains. Côté procédure, la règle à faire connaître est simple :
on ne dépose pas de contenu web avec `mv` depuis un home, on utilise `cp` (ou
`install`, ou `rsync --context`), qui prend le contexte du répertoire de
destination ; et on termine par `restorecon -Rv` sur le docroot.

::: pourquoi
La différence `cp` / `mv` tient aux appels système, et c'est ce qu'il faut savoir
expliquer :

| Commande | Appel système | Inode | Contexte |
|---|---|---|---|
| `mv` (même FS) | `rename()` | conservé | **conservé** |
| `mv` (autre FS) | `copy` + `unlink` | nouveau | hérité de la destination |
| `cp` | `open(O_CREAT)` | nouveau | hérité de la destination |
| `cp -a`, `cp --preserve=context` | idem | nouveau | **copié de la source** |

D'où le comportement déroutant : le même `mv` produit le bon contexte quand il
traverse deux systèmes de fichiers, et le mauvais quand il reste sur le même.
Sur une machine où `/home` est une partition séparée, la panne ne se produit
même pas — ce qui explique le « chez moi ça marche » du collègue.

Les deux niveaux de correction sont une distinction d'exploitation, pas une
subtilité SELinux : le premier remet le service en état (traitement du symptôme),
le second traite la classe de problème (traitement de la cause). On livre
toujours les deux, en les nommant.
:::

---

### **BF18.3** — « HTTPS ne marche plus depuis ce matin »

**Démarche de diagnostic**

```bash
# 1. depuis le fichier servi
openssl x509 -in /etc/ssl/certs/app.crt -noout -subject -dates
# 2. depuis le service réellement en écoute (les deux peuvent différer !)
openssl s_client -connect 127.0.0.1:443 -servername app.lab.local \
  </dev/null 2>/dev/null | openssl x509 -noout -dates
```

```console
notBefore=Jan  1 00:00:00 2025 GMT
notAfter=Sep  1 00:00:00 2025 GMT
```

**Cause racine** : le certificat servi a dépassé sa date `notAfter`. nginx ne
vérifie **jamais** la validité temporelle du certificat qu'il sert : il le charge,
il le présente, et c'est le client qui refuse. D'où un `systemctl status nginx`
parfaitement vert pendant que tous les clients échouent — ce qui explique aussi
pourquoi aucune supervision basée sur l'état du service n'a rien vu.

**Correctif**

```bash
cd ~/lab18/pki           # sur lab-adm, là où vit la CA
openssl req -new -key app.key -out app.csr \
  -subj "/C=FR/O=Lab Local/CN=app.lab.local"
openssl x509 -req -in app.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out app.crt -days 397 -sha256 -extfile app.ext
openssl x509 -in app.crt -noout -dates
scp app.crt mathieu@10.10.10.11:/tmp/
# sur lab-web
sudo install -o root -g root -m 0644 /tmp/app.crt /etc/ssl/certs/app.crt
sudo nginx -t && sudo systemctl reload nginx
openssl s_client -connect 127.0.0.1:443 </dev/null 2>/dev/null | \
  openssl x509 -noout -dates
```

La clé privée **ne change pas** : on réémet un certificat pour la même clé. La CA
n'est pas touchée, donc rien à redistribuer côté clients.

**Prévention — le mécanisme qui aurait alerté quinze jours avant**

```bash
# /etc/cron.d/verif-certs  (ou un timer systemd)
0 7 * * * root /usr/local/bin/verif-certs.sh app.lab.local:443 \
          || logger -p auth.warning "certificat TLS proche expiration"
```

avec `verif-certs.sh` de L18.4, qui sort en 1 sous 30 jours et en 2 sous 15
jours. Une sonde Nagios/Prometheus (`check_ssl_cert`, `blackbox_exporter` avec
`probe_ssl_earliest_cert_expiry`) fait la même chose dans une infrastructure
outillée. Le point non négociable : **la sonde interroge le port, pas le
fichier** — sinon elle rate le cas « renouvelé mais pas rechargé », qui est la
moitié des incidents TLS.

::: pourquoi
Pourquoi l'expiration est le premier incident TLS mondial, et pourquoi elle
surprend toujours : elle n'est corrélée à aucun changement. Personne n'a rien
déployé, rien modifié, rien redémarré. Le déclencheur est le calendrier, et le
symptôme apparaît à une heure arbitraire — souvent sur l'API partenaire avant le
navigateur, parce que les clients automatiques n'ont ni cache d'intermédiaires ni
tolérance.

Les trois automatismes qui règlent définitivement la question :

1. **renouvellement automatique** (certbot et son timer, ou l'ACME de ton
   reverse proxy), avec `certbot renew --dry-run` testé une fois ;
2. **rechargement automatique après renouvellement** — le `--deploy-hook` de
   certbot, sans quoi tu as renouvelé pour rien ;
3. **supervision indépendante** du renouvellement, qui interroge le port. Les
   deux premiers automatismes tombent en panne silencieusement (timer masqué,
   validation HTTP-01 cassée par une redirection) ; seul le troisième te le dit.
:::

---

### **BF18.4** — « Je n'arrive plus à me connecter en SSH, sauf depuis le bastion »

**Démarche de diagnostic**

```bash
# 1. la vue du frontal : impeccable, donc ce n'est pas là qu'il faut regarder
sudo ufw status numbered
# 2. la vue du noyau : la vérité
sudo nft list ruleset | grep -B4 -A8 f2b
sudo iptables -L -n -v | grep -A5 f2b
# 3. et la confirmation immédiate
sudo fail2ban-client status
sudo fail2ban-client status sshd
sudo fail2ban-client banned
```

```console
Chain f2b-sshd (1 references)
 pkts bytes target  prot opt in  out  source        destination
   28  1680 REJECT  all  --  *   *    10.10.10.10   0.0.0.0/0

Status for the jail: sshd
`- Actions
   |- Currently banned: 1
   `- Banned IP list:   10.10.10.10
```

**Cause racine** : fail2ban a banni 10.10.10.10. La chaîne `f2b-sshd` est
insérée par fail2ban **en tête de la chaîne INPUT**, avant les chaînes ufw : le
paquet est rejeté avant même d'atteindre `ufw-user-input`, où figure pourtant la
règle `ALLOW 22/tcp from 10.10.10.10`. `ufw status` ne peut rien en montrer,
puisque ce n'est pas ufw qui a posé la règle.

L'origine du bannissement : un script de supervision ou une boucle de
reconnexion sur `lab-adm` a produit plus de `maxretry` échecs dans la fenêtre
`findtime` — et `ignoreip` ne contenait pas le bastion.

**Correctif immédiat**

```bash
sudo fail2ban-client set sshd unbanip 10.10.10.10
sudo fail2ban-client status sshd      # Currently banned: 0
```

**Correctif durable**

```ini
# /etc/fail2ban/jail.local
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 10.10.10.10 10.10.10.14
bantime  = 1h
findtime = 10m
maxretry = 4
banaction = ufw
```

```bash
sudo fail2ban-client reload
sudo fail2ban-client get sshd ignoreip
```

**Prévention** : `ignoreip` contient le bastion, les sondes de supervision et
les IP d'astreinte — cette ligne s'écrit **avant** d'activer la première jail,
pas après le premier incident. Et `banaction = ufw` rend les bannissements
visibles dans `ufw status numbered`, ce qui supprime définitivement le décalage
entre ce que montre le frontal et ce qu'applique le noyau.

::: pourquoi
Le mécanisme complet, qui est l'objet même de cette panne : fail2ban n'écrit pas
« dans ufw ». Avec l'action par défaut `iptables-multiport`, il crée sa propre
chaîne `f2b-<jail>` et l'accroche par un `-I INPUT 1`, c'est-à-dire **en première
position**. Tout paquet est donc examiné par fail2ban avant toute règle ufw.
Deux systèmes de filtrage indépendants cohabitent sur la même machine, chacun
avec sa vue partielle :

```text
INPUT
 ├─ f2b-sshd            <- fail2ban, position 1, invisible de « ufw status »
 ├─ ufw-before-input
 ├─ ufw-user-input      <- ALLOW 22 from 10.10.10.10, jamais atteint
 └─ ...
```

C'est la même leçon que BF18.1, par une autre porte : le frontal ne montre que
ses propres règles. Sur une machine de production, il y a souvent **trois**
écrivains dans netfilter — ufw, fail2ban et Docker — et un seul endroit où voir
le résultat : `nft list ruleset`.

Quant au verrouillage hors de sa propre machine, c'est le risque professionnel de
ce module. Les trois garde-fous à systématiser : `ignoreip` renseigné dès le
départ, un `bantime` fini (jamais `-1` sur la jail SSH d'une machine distante),
et un accès console indépendant du réseau — ici la console Proxmox, en
production l'IPMI/iDRAC.
:::

---

## 18.8 Défi du module

**D18 — Rapport de conformité et durcissement de l'infrastructure**

*Livrable attendu : `audit-securite.sh` portable Ubuntu/Rocky, rapport Markdown
sur stdout, diagnostic sur stderr, score sur 100, code retour 0/1/2.*

```bash
#!/usr/bin/env bash
# audit-securite.sh — audit de sécurité en lecture seule (module 18)
# stdout = rapport Markdown, stderr = trace. Ne modifie RIEN.
# Retour : 0 aucun critique, 1 avertissements, 2 au moins un critique
set -uo pipefail

BASELINE="${BASELINE:-$HOME/lab18/baseline-suid.txt}"
OK=0; AVERT=0; CRIT=0
declare -a SYNTHESE

log()  { printf '[%s] %s\n' "$(date +%T)" "$*" >&2; }
verdict() {           # verdict <etat> <controle> <detail>
  case "$1" in
    OK)        OK=$((OK+1)) ;;
    AVERT*)    AVERT=$((AVERT+1)) ;;
    CRITIQUE)  CRIT=$((CRIT+1)) ;;
  esac
  SYNTHESE+=("$1|$2|$3")
  printf '* **%s** — %s : %s\n' "$1" "$2" "$3"
}

# --- détection de la plateforme ---------------------------------------
. /etc/os-release
case "$ID" in
  ubuntu|debian) FAMILLE=deb ;;
  rocky|rhel|centos|almalinux) FAMILLE=rpm ;;
  *) FAMILLE=inconnu ;;
esac
log "plateforme détectée : $ID ($FAMILLE)"

printf '# Audit de sécurité — %s\n\n' "$(hostname -f 2>/dev/null \
  || hostname)"
printf '%s %s — noyau %s — up %s\n\n' "$PRETTY_NAME" "$(uname -m)" \
  "$(uname -r)" "$(uptime -p 2>/dev/null | sed 's/^up //')"

# --- 1. pare-feu -------------------------------------------------------
printf '## Pare-feu\n\n'
if command -v ufw >/dev/null && [ "$FAMILLE" = deb ]; then
  if ufw status 2>/dev/null | grep -q '^Status: active'; then
    pol=$(ufw status verbose 2>/dev/null | grep '^Default:')
    nb=$(ufw status numbered 2>/dev/null | grep -c '^\[')
    case "$pol" in
      *"deny (incoming)"*) verdict OK "ufw" "actif, $nb règles, $pol" ;;
      *) verdict CRITIQUE "ufw" "politique entrante non restrictive : $pol" ;;
    esac
  else
    verdict CRITIQUE "ufw" "installé mais inactif (ufw enable)"
  fi
elif command -v firewall-cmd >/dev/null; then
  if firewall-cmd --state >/dev/null 2>&1; then
    z=$(firewall-cmd --get-default-zone)
    s=$(firewall-cmd --list-services 2>/dev/null)
    verdict OK "firewalld" "actif, zone $z, services : ${s:-aucun}"
  else
    verdict CRITIQUE "firewalld" "installé mais arrêté"
  fi
else
  verdict CRITIQUE "pare-feu" "aucun frontal détecté"
fi
nbrules=$(nft list ruleset 2>/dev/null | grep -c '^\s*\(tcp\|udp\|ip\)')
printf '\nRègles nftables chargées : %s\n\n' "${nbrules:-0}"

# --- 2. surface d'écoute ----------------------------------------------
printf '## Surface d écoute\n\n| Proto | Adresse | Processus |\n'
printf -- '|---|---|---|\n'
ss -tulpnH 2>/dev/null | grep -vE '127\.0\.0\.1|\[::1\]' | \
  awk '{printf "| %s | %s | %s |\n", $1, $5, $7}'
printf '\n'
nbexpo=$(ss -tulnH 2>/dev/null | grep -vcE '127\.0\.0\.1|\[::1\]')
[ "${nbexpo:-0}" -le 3 ] \
  && verdict OK "écoute" "$nbexpo sockets exposés" \
  || verdict AVERTISSEMENT "écoute" "$nbexpo sockets exposés, à revoir"

# --- 3. contrôle d accès obligatoire -----------------------------------
printf '\n## MAC\n\n'
if command -v getenforce >/dev/null; then
  cur=$(getenforce)
  conf=$(awk -F= '/^SELINUX=/{print $2}' /etc/selinux/config 2>/dev/null)
  case "$cur" in
    Enforcing) verdict OK "SELinux" "enforcing (config : $conf)" ;;
    Permissive) verdict AVERTISSEMENT "SELinux" "permissive : refus \
journalisés mais non bloqués" ;;
    *) verdict CRITIQUE "SELinux" "désactivé" ;;
  esac
elif command -v aa-status >/dev/null; then
  ch=$(aa-status --profiled 2>/dev/null)
  cp=$(aa-status --complaining 2>/dev/null)
  [ "${ch:-0}" -gt 0 ] \
    && verdict OK "AppArmor" "$ch profils chargés, $cp en complain" \
    || verdict CRITIQUE "AppArmor" "aucun profil chargé"
else
  verdict CRITIQUE "MAC" "ni SELinux ni AppArmor"
fi

# --- 4. comptes --------------------------------------------------------
printf '\n## Comptes\n\n'
uid0=$(awk -F: '($3==0){print $1}' /etc/passwd | tr '\n' ' ')
[ "$uid0" = "root " ] \
  && verdict OK "UID 0" "root uniquement" \
  || verdict CRITIQUE "UID 0" "plusieurs comptes UID 0 : $uid0"
vides=$(sudo -n awk -F: '($2==""){print $1}' /etc/shadow 2>/dev/null \
        | tr '\n' ' ')
[ -z "$vides" ] \
  && verdict OK "mots de passe" "aucun mot de passe vide" \
  || verdict CRITIQUE "mots de passe" "comptes sans mot de passe : $vides"

# --- 5. mises à jour ---------------------------------------------------
printf '\n## Mises à jour\n\n'
if [ "$FAMILLE" = deb ]; then
  n=$(apt-get -s upgrade 2>/dev/null | grep -ci '^Inst.*security')
  auto=$(grep -rhs 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/ | wc -l)
else
  n=$(dnf -q updateinfo list security 2>/dev/null | grep -c .)
  auto=$(systemctl is-enabled dnf-automatic.timer 2>/dev/null \
         | grep -c enabled)
fi
[ "${n:-0}" -eq 0 ] \
  && verdict OK "correctifs" "aucune mise à jour de sécurité en attente" \
  || verdict CRITIQUE "correctifs" "$n mises à jour de sécurité en attente"
[ "${auto:-0}" -gt 0 ] \
  && verdict OK "automatisation" "mises à jour automatiques activées" \
  || verdict AVERTISSEMENT "automatisation" "aucune mise à jour automatique"

# --- 6. sysctl ---------------------------------------------------------
printf '\n## Paramètres noyau\n\n'
attendu="net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.tcp_syncookies=1
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.randomize_va_space=2
kernel.yama.ptrace_scope=1
fs.protected_symlinks=1"
ecarts=0
while IFS='=' read -r cle val; do
  lu=$(sysctl -n "$cle" 2>/dev/null) || continue
  [ "$lu" = "$val" ] || { printf '* `%s` = %s (attendu %s)\n' \
    "$cle" "$lu" "$val"; ecarts=$((ecarts+1)); }
done <<< "$attendu"
[ "$ecarts" -eq 0 ] \
  && verdict OK "sysctl" "les 10 clés sont conformes" \
  || verdict AVERTISSEMENT "sysctl" "$ecarts écarts (détail ci-dessus)"

# --- 7. SUID -----------------------------------------------------------
printf '\n## SUID / SGID\n\n'
tmp=$(mktemp); find / -xdev \( -perm -4000 -o -perm -2000 \) -type f \
  2>/dev/null | sort > "$tmp"
if [ -r "$BASELINE" ]; then
  nouveaux=$(comm -23 "$tmp" "$BASELINE")
  if [ -z "$nouveaux" ]; then
    verdict OK "SUID" "identique à la base de référence"
  else
    printf '%s\n' "$nouveaux" | sed 's/^/* hors référence : /'
    verdict CRITIQUE "SUID" "$(printf '%s\n' "$nouveaux" | wc -l) \
binaire(s) SUID/SGID hors référence"
  fi
else
  verdict AVERTISSEMENT "SUID" "pas de base de référence ($BASELINE)"
fi
rm -f "$tmp"

# --- 8. TLS ------------------------------------------------------------
printf '\n## Certificats TLS\n\n'
trouve=0
for c in /etc/ssl/certs/*.crt /etc/pki/tls/certs/*.crt; do
  [ -f "$c" ] || continue
  case "$c" in */ca-certificates.crt|*/ca-bundle.crt) continue ;; esac
  openssl x509 -in "$c" -noout -checkend 0 >/dev/null 2>&1 || {
    verdict CRITIQUE "TLS" "$c est EXPIRÉ"; trouve=1; continue; }
  if ! openssl x509 -in "$c" -noout -checkend 2592000 >/dev/null 2>&1; then
    verdict AVERTISSEMENT "TLS" "$c expire sous 30 jours"; trouve=1
  fi
done
[ "$trouve" -eq 0 ] && verdict OK "TLS" "aucun certificat proche expiration"

# --- 9. fail2ban -------------------------------------------------------
printf '\n## fail2ban\n\n'
if command -v fail2ban-client >/dev/null \
   && fail2ban-client ping >/dev/null 2>&1; then
  jails=$(fail2ban-client status | awk -F: '/Jail list/{print $2}')
  bannis=$(fail2ban-client banned 2>/dev/null | grep -o '[0-9.]\{7,\}' \
           | wc -l)
  verdict OK "fail2ban" "actif — jails :${jails:- aucune} — $bannis bannis"
else
  verdict AVERTISSEMENT "fail2ban" "absent ou arrêté"
fi

# --- synthèse ----------------------------------------------------------
total=$((OK + AVERT + CRIT))
score=$(( total > 0 ? (OK * 100 + AVERT * 50) / total : 0 ))
printf '\n## Synthèse\n\n| Verdict | Contrôle | Détail |\n|---|---|---|\n'
for l in "${SYNTHESE[@]:-}"; do
  [ -n "$l" ] && printf '| %s | %s | %s |\n' \
    "${l%%|*}" "$(echo "$l" | cut -d'|' -f2)" "${l##*|}"
done
printf '\n**Score : %s/100** — %s OK, %s avertissements, %s critiques\n' \
  "$score" "$OK" "$AVERT" "$CRIT"

[ "$CRIT" -gt 0 ] && exit 2
[ "$AVERT" -gt 0 ] && exit 1
exit 0
```

```bash
~/lab18/bin/audit-securite.sh > ~/lab18/rapport-lab-web.md
echo $?
for h in 10.10.10.11 10.10.10.12 10.10.10.13 10.10.10.14; do
  ssh "mathieu@$h" 'bash -s' < ~/lab18/bin/audit-securite.sh \
    >> ~/lab18/rapport-T3.md
done
```

::: pourquoi
Les décisions de conception qui font la valeur du livrable :

**Séparation stdout / stderr.** Le rapport sur stdout, la trace sur stderr. C'est
ce qui rend `audit-securite.sh > rapport.md` utilisable tel quel, et
`ssh hôte 'bash -s' < audit-securite.sh >> rapport-global.md` utilisable pour
auditer tout un parc **sans rien installer sur les machines cibles**. Le script
voyage par stdin, s'exécute, et renvoie son rapport : c'est le mode d'emploi d'un
auditeur qui n'a pas de droit de dépôt.

**Le script ne modifie rien.** Aucun `sysctl -w`, aucun `systemctl`, aucune
écriture hors `mktemp`. Un outil d'audit qui répare devient impossible à faire
tourner sur un système en production sans autorisation de changement, et surtout
il fausse sa propre mesure : au second passage, tout est vert parce qu'il a
corrigé lui-même.

**Trois niveaux de verdict plutôt que deux.** `OK` / `AVERTISSEMENT` /
`CRITIQUE` correspond à trois actions différentes : rien à faire, à planifier,
à traiter aujourd'hui. Un booléen conforme/non conforme force à trancher
arbitrairement et produit soit du bruit, soit des angles morts. Le code retour
suit la même logique (0/1/2), ce qui permet à une tâche planifiée de n'alerter
que sur le 2 et à une CI d'échouer sur le 1.

**Le score est calculé, pas déclaré.** `(OK * 100 + AVERT * 50) / total` donne
un chiffre qui bouge quand l'état change et qui ne dépend d'aucune pondération
arbitraire. Il sert à mesurer une tendance sur une machine, pas à comparer deux
machines — exactement la nuance de QO18.10 sur l'indice lynis.

**La détection de plateforme par `/etc/os-release`.** C'est le seul mécanisme
présent partout et normalisé (systemd). Tester `command -v ufw` seul ne suffit
pas : ufw est installable sur Rocky et n'y est jamais le bon frontal. On détecte
la famille, puis on teste la présence de l'outil.

**La base de référence SUID.** Un audit qui liste 32 binaires SUID ne dit rien :
c'est normal. Ce qui est actionnable, c'est le **delta** avec une base prise
quand la machine était saine — d'où le `comm -23` et le fichier
`~/lab18/baseline-suid.txt` produit par le script de setup. C'est aussi ce qui
transforme le script en détecteur d'intrusion rudimentaire, cf. QO18.9.
:::

::: piege
Trois pièges dans lesquels tombent la plupart des copies :

**`set -e` et les commandes qui échouent normalement.** `grep -c` renvoie 1 quand
il ne trouve rien, `apt-get -s upgrade` peut sortir en erreur sans dépôt
accessible, `sudo -n` échoue si le script n'est pas privilégié. Sous
`set -euo pipefail`, chacun de ces cas tue le script au milieu du rapport. D'où
le `set -uo pipefail` **sans `-e`** ici, les `|| true` et les `2>/dev/null`
ciblés : dans un outil d'audit, l'échec d'un contrôle ne doit jamais empêcher les
suivants — il doit être **rapporté** comme un contrôle non concluant.

**Le script sans privilèges.** `ss -p` n'affiche les processus que pour root,
`/etc/shadow` n'est pas lisible, `find /` remonte des erreurs de permission. Le
script doit fonctionner dans les deux cas et **dire** ce qu'il n'a pas pu
vérifier, plutôt que d'afficher un faux `OK`. Un audit qui renvoie « aucun mot de
passe vide » parce qu'il n'a pas pu lire `/etc/shadow` est pire qu'un audit qui
n'a pas tourné.

**Le tableau vide sous `set -u`.** `"${SYNTHESE[@]}"` sur un tableau vide était
une erreur fatale avant bash 4.4 ; sur Ubuntu 24.04 (bash 5.2) et Rocky 9 (bash
5.1) c'est sûr, mais la forme `"${SYNTHESE[@]:-}"` reste l'habitude à prendre
pour un script qui doit tourner aussi sur des systèmes plus anciens.
:::
