<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Partie II — Administration système › **Module 12** · corrigé  
[← Module 11](../11-stockage-lvm/corrige.md) · [Énoncé](README.md) · [Module 13 →](../13-reseau-avance/corrige.md)

> [!TIP]
> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, pas avant. Chaque identifiant renvoie à son énoncé.
<!-- nav:fin -->

# Module 12 — Corrigé

## 12.3 Quiz — QCM

<a id="q12-1"></a>**[Q12.1](README.md#q12-1)** — *`ip -br a` : `lo UNKNOWN`, `ens18 UP 10.10.10.10/24 fe80::…/64`.*

**Réponse : c)** `ens18` est active, avec une IPv4 et une IPv6 link-local.

> [!NOTE]
> **Pourquoi**
>
> Trois choses à lire dans cette sortie.
>
> L'état `UNKNOWN` de `lo` n'est pas une anomalie. Le champ affiché par `ip -br`
> est l'**état opérationnel** (`IF_OPER_*`, RFC 2863), qui décrit la détection de
> porteuse au niveau du lien. Une interface virtuelle n'a pas de porteuse à
> détecter : le pilote ne renseigne rien, le noyau affiche `UNKNOWN`. Ce qui
> compte pour `lo`, c'est le drapeau administratif `UP`, visible avec
> `ip link show lo` (`<LOOPBACK,UP,LOWER_UP>`).
>
> `fe80::5054:ff:fe1a:2b3c/64` est une adresse **link-local**, du préfixe
> `fe80::/10`. Elle est générée automatiquement dès qu'IPv6 est actif sur une
> interface, elle n'est jamais routée au-delà du segment, et sa présence ne dit
> strictement rien sur la connectivité IPv6 réelle. Le motif `ff:fe` inséré au
> milieu trahit une adresse dérivée de la MAC (EUI-64) : ici MAC
> `52:54:00:1a:2b:3c`, avec le bit U/L inversé, `52` → `50`.
>
> Enfin, `ip -br a` ne montre **aucune** route : la passerelle par défaut ne peut
> pas se déduire de cette sortie, il faut `ip r`. C'est le piège de la réponse d).

---

<a id="q12-2"></a>**[Q12.2](README.md#q12-2)** — *Adresse de diffusion de `192.168.42.130/26`.*

**Réponse : b)** `192.168.42.191`.

> [!NOTE]
> **Pourquoi**
>
> Méthode mentale, sans binaire. Un `/26` laisse 6 bits d'hôte, donc des blocs de
> `2^6 = 64` adresses. Le masque est `255.255.255.192`, et le pas dans le dernier
> octet vaut `256 - 192 = 64`. Les frontières de blocs sont donc `.0`, `.64`,
> `.128`, `.192`.
>
> `130` tombe entre `128` et `191` : le réseau est `192.168.42.128/26`, la
> diffusion est l'adresse juste avant le bloc suivant, soit `192.168.42.191`.
> Plage utilisable : `.129` à `.190`, 62 hôtes.
>
> Le réflexe à installer : **on ne calcule pas, on trouve le bloc**. Pas du masque,
> frontière inférieure, frontière supérieure. Ça tient en cinq secondes de tête et
> ça ne se trompe jamais.

> [!WARNING]
> **Piège**
>
> a) `192.168.42.255` est la diffusion du `/24`, pas celle du `/26` : c'est
> l'erreur de quelqu'un qui n'a pas regardé le préfixe. Elle est lourde en
> production : configurer `.255` comme diffusion sur un `/26` fait que les paquets
> de diffusion ne sont pas reçus par les hôtes du segment, avec des symptômes
> erratiques sur DHCP, ARP gratuit et découverte de services.

---

<a id="q12-3"></a>**[Q12.3](README.md#q12-3)** — *Adresses utilisables dans un `/21`.*

**Réponse : b)** 2046.

> [!NOTE]
> **Pourquoi**
>
> `32 - 21 = 11` bits d'hôte, soit `2^11 = 2048` adresses totales. On retire
> l'adresse de réseau (tous les bits d'hôte à 0) et l'adresse de diffusion (tous à
> 1) : **2046** hôtes utilisables.
>
> À mémoriser, c'est le tableau qui revient en entretien :
>
> | Préfixe | Total | Utilisables |
> |---|---|---|
> | `/24` | 256 | 254 |
> | `/23` | 512 | 510 |
> | `/22` | 1024 | 1022 |
> | `/21` | 2048 | 2046 |
>
> Exception à connaître : le `/31` (RFC 3021) sur les liaisons point à point n'a ni
> réseau ni diffusion, ses **2** adresses sont utilisables. Et un `/32` désigne un
> hôte unique (route d'hôte, adresse de bouclage de service).

---

<a id="q12-4"></a>**[Q12.4](README.md#q12-4)** — *Une interface en `169.254.12.88/16`.*

**Réponse : b)** le DHCP n'a pas répondu, la machine s'est auto-attribué une
adresse link-local IPv4 (APIPA, RFC 3927).

> [!NOTE]
> **Pourquoi**
>
> `169.254.0.0/16` est réservée à l'auto-configuration en l'absence de serveur
> DHCP. Voir cette plage sur une interface, c'est un diagnostic en soi : le client
> DHCP a émis, n'a rien reçu, et a replié sur une adresse tirée au hasard dans
> cette plage après test de conflit par ARP.
>
> Ce que ça t'apprend immédiatement : la couche 2 fonctionne (l'interface est
> montée, elle a pu faire de l'ARP), mais aucune réponse DHCP ne revient. Les
> causes réelles, dans l'ordre de fréquence : mauvais VLAN sur le port du
> commutateur, relais DHCP absent sur le segment, pool DHCP épuisé, serveur DHCP
> arrêté.
>
> La commande qui confirme : `journalctl -u systemd-networkd -n 50` (ou
> `-u NetworkManager` sur Rocky), qui montre les tentatives DHCPv4 sans réponse.
> Et `sudo tcpdump -ni ens18 'port 67 or port 68'` pour voir les `DHCPDISCOVER` partir sans `DHCPOFFER` en retour (`dhclient` n'est plus installé par défaut sur Ubuntu 24.04).

> [!WARNING]
> **Piège**
>
> Ne « corrige » pas ça en posant une IP statique au hasard sur le segment. Tu
> masques une panne d'infrastructure, et tu risques le conflit d'adresses avec un
> bail DHCP attribué plus tard. On répare le DHCP, ou on décide explicitement de
> passer la machine en statique dans la configuration persistante.

---

<a id="q12-5"></a>**[Q12.5](README.md#q12-5)** — *Ce qu'apporte `ip route get 9.9.9.9` par rapport à `ip r` (deux réponses).*

**Réponses : a) et b)**

> [!NOTE]
> **Pourquoi**
>
> `ip r` affiche la table `main`, brute. `ip route get` fait autre chose : il
> demande au noyau de **résoudre réellement** la destination, exactement comme il
> le ferait pour un vrai paquet. Le noyau applique dans l'ordre : les règles
> (`ip rule`), la table sélectionnée, la route la plus spécifique, puis les
> métriques en cas d'égalité de préfixe.
>
> Le résultat contient une information qu'aucune autre commande ne donne
> directement : `src 10.10.10.10`, l'**adresse source** que la pile choisira. Sur
> une machine à plusieurs adresses ou plusieurs interfaces, c'est très souvent là
> que se trouve le bug : le paquet part par la bonne interface mais avec la
> mauvaise source, et la réponse ne revient jamais (ou se fait jeter par un
> filtrage en amont, ou par `rp_filter`).
>
> La mention `cache` signale seulement une route calculée pour cette destination ( le cache de routage IPv4 a disparu en 3.6),
> pas que la destination est joignable. `ip route get` **n'envoie aucun paquet** :
> c'est une question posée à la table de routage, pas un test d'accessibilité.
> D'où la fausseté de c).

> [!WARNING]
> **Piège**
>
> Sur une machine avec deux interfaces, le réflexe « je ping depuis la bonne
> interface avec `-I` » ne prouve rien sur ce que fera l'application, qui elle
> utilisera la source par défaut. `ip route get <dst>` d'abord, `ping -I` ensuite
> pour confirmer l'hypothèse.

---

<a id="q12-6"></a>**[Q12.6](README.md#q12-6)** — *`/etc/resolv.conf` contient `nameserver 127.0.0.53`.*

**Réponse : b)** c'est le stub de `systemd-resolved` ; le vrai serveur est dans
`resolvectl status`.

> [!NOTE]
> **Pourquoi**
>
> Sur Ubuntu 24.04, `/etc/resolv.conf` est un lien symbolique :
>
> ```console
> $ ls -l /etc/resolv.conf
> lrwxrwxrwx 1 root root 39 ... /etc/resolv.conf ->
>                                 ../run/systemd/resolve/stub-resolv.conf
> ```
>
> `systemd-resolved` écoute sur `127.0.0.53:53` (et sur `127.0.0.54` pour le mode
> «proxy », qui relaie sans traitement local). Toutes les requêtes des applications qui lisent `resolv.conf`
> arrivent donc au stub local, qui décide ensuite : cache, serveur amont par lien
> réseau, domaine de recherche, DNSSEC, DNS-over-TLS.
>
> La conséquence pratique, celle qui compte en incident : **la liste des vrais
> serveurs DNS n'est pas dans `/etc/resolv.conf`**. Elle est par interface :
>
> ```console
> $ resolvectl status
> Global
>        Protocols: -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
> Link 2 (ens18)
>     Current Scopes: DNS
>          Protocols: +DefaultRoute
> Current DNS Server: 10.10.10.10
>        DNS Servers: 10.10.10.10 9.9.9.9
>         DNS Domain: lab.local
> ```
>
> Il existe un second fichier, `/run/systemd/resolve/resolv.conf`, qui contient
> lui les serveurs réels : il sert aux logiciels qui refusent de passer par le
> stub. Certains résolveurs embarqués (JVM, Go dans certains modes) lisent
> `resolv.conf` sans passer par `getaddrinfo()` et se retrouvent à parler au stub
> ou à le contourner : c'est une source classique d'écarts de comportement entre
> `dig`, `ping` et l'application.

---

<a id="q12-7"></a>**[Q12.7](README.md#q12-7)** — *`ping` dit `10.10.10.99`, `dig +short` dit `10.10.10.11`.*

**Réponse : b)** une entrée dans `/etc/hosts`, car `files` précède `dns` dans
`/etc/nsswitch.conf`.

> [!NOTE]
> **Pourquoi**
>
> C'est **le** classique du module, et la raison d'être de BF12.4.
>
> `ping`, `curl`, `ssh` et toute application normale résolvent via
> `getaddrinfo()`, qui suit la ligne `hosts:` de `/etc/nsswitch.conf` :
>
> ```text
> hosts: files dns
> ```
>
> `files` = `/etc/hosts`. Il est consulté **en premier**, et s'il contient une
> correspondance, la recherche s'arrête là. Le DNS n'est jamais interrogé.
>
> `dig`, lui, ne passe **pas** par NSS. C'est un client DNS pur : il lit
> `/etc/resolv.conf` pour savoir à qui parler et envoie une requête DNS. Il ne
> lit jamais `/etc/hosts` lui-même. Attention sur Ubuntu : sans `@serveur`, il parle au stub `127.0.0.53`, et `systemd-resolved` sert **aussi** les entrées de `/etc/hosts` (`ReadEtcHosts=yes`). Pour voir le DNS seul, on interroge le serveur explicitement : `dig @10.10.10.10`.
>
> D'où la règle de diagnostic : quand `dig` et le reste du système ne sont pas
> d'accord, le problème n'est **pas** dans le DNS. Il est dans NSS, donc dans
> `/etc/hosts` ou dans l'ordre de `nsswitch.conf`. La commande qui tranche en une
> ligne est `getent hosts <nom>` : elle emprunte exactement le même chemin que les
> applications.

> [!WARNING]
> **Piège**
>
> a) est tentant mais faux : un cache périmé donnerait la même réponse à `dig` et
> à `ping` (tous deux verraient l'ancienne valeur, ou `dig` la nouvelle si on
> l'interroge avec `@serveur`), pas deux valeurs incohérentes de façon stable dans
> le temps. d) est faux aussi : `ping` n'a pas de serveur DNS à lui, il utilise
> NSS. Et attention, sur Ubuntu la ligne réelle est souvent
> `hosts: files mdns4_minimal [NOTFOUND=return] dns` : le `[NOTFOUND=return]`
> signifie que si mDNS répond « ce nom n'existe pas » pour un `.local`, la
> recherche s'arrête **sans** interroger le DNS. Un domaine de lab nommé
> `lab.local` peut se faire piéger par ce mécanisme.

---

<a id="q12-8"></a>**[Q12.8](README.md#q12-8)** — *`dig` renvoie `status: SERVFAIL`.*

**Réponse : b)** le serveur interrogé a tenté de répondre et a échoué.

> [!NOTE]
> **Pourquoi**
>
> Les quatre `status` à savoir distinguer, parce qu'ils désignent quatre pannes
> différentes et quatre interlocuteurs différents :
>
> | `status` | Sens | Où chercher |
> |---|---|---|
> | `NOERROR` | réponse valide | vérifier `ANSWER: 0` = nom existe, pas ce type |
> | `NXDOMAIN` | le nom n'existe pas | faute de frappe, zone, enregistrement absent |
> | `SERVFAIL` | le serveur a échoué | **le serveur interrogé**, ou son amont |
> | `REFUSED` | refus de répondre | ACL, récursion interdite, mauvais serveur |
>
> `SERVFAIL` est le plus mal interprété. Il ne dit pas « le nom n'existe pas », il
> dit « je n'ai pas pu conclure ». Causes réelles, dans l'ordre : le serveur
> récursif n'arrive pas à joindre les serveurs faisant autorité (panne réseau en
> amont, filtrage du port 53 sortant), la zone est cassée côté serveur autoritaire,
> ou la validation DNSSEC a échoué (signature expirée : cas très fréquent et très
> déroutant, car le nom existe bel et bien).
>
> Le test qui isole : `dig @8.8.8.8 <nom>` et `dig @<serveur-interne> <nom>`.
> Si l'un répond `NOERROR` et l'autre `SERVFAIL`, le fautif est désigné. Pour
> écarter DNSSEC : `dig +cd <nom>` (`cd` = checking disabled). Si `+cd` répond et
> pas la requête normale, c'est DNSSEC.
>
> Et `NOERROR` avec `ANSWER: 0` est un piège courant : le nom existe, mais pas
> pour le type demandé. C'est ce qu'on obtient en demandant un `AAAA` à un nom qui
> n'a qu'un `A`.

---

<a id="q12-9"></a>**[Q12.9](README.md#q12-9)** — *`127.0.0.1:8099` en LISTEN, `curl` distant échoue en code 7.*

**Réponse : b)** le service n'écoute que sur la boucle locale.

> [!NOTE]
> **Pourquoi**
>
> Un socket en écoute est lié à un couple (adresse, port). L'adresse détermine
> **par quelles interfaces** les connexions sont acceptées :
>
> | Adresse d'écoute | Accessible depuis |
> |---|---|
> | `127.0.0.1:8099` | la machine elle-même, uniquement |
> | `10.10.10.11:8099` | le réseau, via cette adresse seulement |
> | `0.0.0.0:8099` | toutes les interfaces IPv4 |
> | `[::]:8099` | toutes les interfaces IPv6, et v4 si `bindv6only=0` |
>
> Quand un paquet arrive sur `ens18` à destination de `10.10.10.11:8099`, la pile
> cherche un socket lié à cette adresse ou à `0.0.0.0`. Elle n'en trouve pas — le
> socket existant est lié à `127.0.0.1`, qui n'est atteignable que par `lo`. Sans
> socket correspondant, le noyau répond immédiatement par un **`RST`**. `curl`
> traduit ce `RST` en `Connection refused`, code de retour **7**, sans délai.
>
> C'est cette absence de délai qui est diagnostique : un filtrage par `DROP`
> aurait donné un timeout (code 28) après plusieurs dizaines de secondes. La
> réponse instantanée dit « quelque chose a répondu non », pas « personne n'a
> répondu ».

> [!WARNING]
> **Piège**
>
> c) est faux : 8099 est bien au-dessus de 1024, il n'a rien de privilégié. Et
> attention au cas inverse, tout aussi fréquent : un socket sur `[::]:8099`
> **sans** `0.0.0.0` correspondant. Si `net.ipv6.bindv6only=1`, les clients IPv4
> sont refusés alors que `ss` montre bien un LISTEN. Toujours lire l'adresse, pas
> seulement le port.

---

<a id="q12-10"></a>**[Q12.10](README.md#q12-10)** — *4 000 connexions en `CLOSE-WAIT`.*

**Réponse : c)** c'est un bug applicatif : le programme n'appelle pas `close()`.

> [!NOTE]
> **Pourquoi**
>
> `CLOSE-WAIT` est l'état d'une socket **locale** qui a reçu le `FIN` du pair et
> ne lui a pas encore répondu par son propre `FIN`. Autrement dit : le client a
> raccroché, le noyau local en a pris acte, il attend maintenant que
> l'application appelle `close()` sur le descripteur.
>
> Le noyau ne peut rien faire de plus. Il n'a pas le droit de fermer à la place du
> programme : il ne sait pas si celui-ci a encore des données à écrire. Tant que
> le descripteur reste ouvert, la socket reste en `CLOSE-WAIT`, **sans limite de
> durée**. Il n'existe aucun `sysctl` pour purger ces états, et c'est logique :
> le seul correctif est dans le code.
>
> Conséquence opérationnelle : chaque `CLOSE-WAIT` consomme un descripteur de
> fichier. À 4 000, on approche du `LimitNOFILE` par défaut de beaucoup d'unités
> systemd (1024 ou 65536 selon la configuration). Le symptôme suivant est brutal :
> `accept: Too many open files` dans les journaux, et le service cesse d'accepter
> toute nouvelle connexion alors qu'il est toujours `active (running)`.
>
> Le diagnostic qui accompagne le ticket développeur :
>
> ```bash
> ss -tan state close-wait | wc -l
> ss -tanp state close-wait | head           # quel processus
> ls -l /proc/<PID>/fd | wc -l               # combien de descripteurs
> cat /proc/<PID>/limits | grep 'open files'
> ```
>
> En attendant le correctif, le contournement est un redémarrage périodique du
> service. Ce n'est pas une solution, c'est un sursis à documenter dans le ticket.

> [!WARNING]
> **Piège**
>
> a), b) et d) visent toutes le mauvais état. `tcp_fin_timeout` gouverne
> `FIN-WAIT-2`, `tcp_tw_reuse` gouverne la réutilisation des `TIME-WAIT` : ni l'un
> ni l'autre n'a le moindre effet sur `CLOSE-WAIT`. Ce sont les réponses de
> quelqu'un qui a lu un article « optimisation TCP » sans comprendre quel côté
> ferme la connexion.

---

<a id="q12-11"></a>**[Q12.11](README.md#q12-11)** — *20 000 `TIME-WAIT` côté client (deux réponses).*

**Réponses : a) et c)**

> [!NOTE]
> **Pourquoi**
>
> `TIME-WAIT` est l'état du côté qui exécute la **fermeture active**, c'est-à-dire
> qui envoie le premier `FIN`. Sur un frontal qui ouvre beaucoup de connexions
> sortantes courtes vers un backend, c'est le frontal qui ferme : il accumule donc
> les `TIME-WAIT`. C'est le fonctionnement **normal** de TCP, pas une fuite.
>
> Sa durée est de `2 × MSL`, soit **60 secondes sous Linux**, valeur compilée
> (`TCP_TIMEWAIT_LEN`) et non réglable par `sysctl`. Sa raison d'être est double :
> absorber les paquets retardataires de la connexion qui vient de se fermer pour
> qu'ils ne soient pas livrés à une nouvelle connexion réutilisant le même
> quadruplet, et garantir que le dernier `ACK` puisse être retransmis si le `FIN`
> du pair est réémis.
>
> Le vrai risque est l'épuisement de ports éphémères : avec
> `ip_local_port_range = 32768 60999`, on dispose d'environ 28 000 ports source par couple (IP source, IP : port de destination) — le quadruplet doit rester unique. Vers une
> seule IP:port de destination, 20 000 `TIME-WAIT` mettent donc réellement en
> danger la capacité à ouvrir de nouvelles connexions. Le symptôme est
> `connect: Cannot assign requested address` (EADDRNOTAVAIL).
>
> Les leviers, dans l'ordre de pertinence :
>
> 1. **Connexions persistantes** (keep-alive HTTP, pool de connexions). C'est le
>    vrai correctif : on ne ferme plus 20 000 fois, on garde 50 connexions.
> 2. `net.ipv4.tcp_tw_reuse=1` : autorise la réutilisation d'un `TIME-WAIT`
>    **sortant** quand l'horodatage TCP garantit qu'il n'y a pas d'ambiguïté. La
>    valeur par défaut sur les noyaux récents est `2` = activé pour la boucle
>    locale seulement.
> 3. Élargir `ip_local_port_range`, ou répartir sur plusieurs IP sources.

> [!WARNING]
> **Piège**
>
> d) est l'erreur qui circule dans tous les billets de blog : `tcp_fin_timeout`
> ne contrôle **pas** `TIME-WAIT`, il contrôle `FIN-WAIT-2`. Le baisser ne change
> rien au problème posé. Et `net.ipv4.tcp_tw_recycle`, souvent cité dans les
> mêmes billets, a été **supprimé** du noyau en 4.12 : il cassait le NAT de façon
> spectaculaire et silencieuse. Si tu le vois dans un `sysctl.conf`, c'est une
> configuration copiée-collée qui date, à nettoyer.

---

<a id="q12-12"></a>**[Q12.12](README.md#q12-12)** — *`curl` renvoie le code 6, sans sortie.*

**Réponse : b)** résolution de noms impossible.

> [!NOTE]
> **Pourquoi**
>
> Les codes de retour de `curl` sont un instrument de diagnostic à part entière :
> ils désignent l'étage avant même qu'on lise le message.
>
> | Code | Signification | Étage |
> |---|---|---|
> | 6 | `Couldn't resolve host` | résolution de noms |
> | 7 | `Failed to connect` | transport : RST, ou route absente |
> | 28 | `Operation timed out` | transport : paquets jetés en silence |
> | 35 | erreur de connexion TLS | TLS : version, ciphers, handshake |
> | 60 | certificat non vérifiable | TLS : chaîne, nom, date |
> | 52 | réponse vide du serveur | applicatif : le serveur ferme sans répondre |
>
> Vérification :
>
> ```console
> $ curl -sS https://www.lab.local/ ; echo "rc=$?"
> curl: (6) Could not resolve host: www.lab.local
> rc=6
> ```
>
> La suite du diagnostic est mécanique : `getent hosts www.lab.local` (chaîne
> NSS), `dig www.lab.local` (DNS pur), `resolvectl status` (quel serveur est
> réellement utilisé). Si `dig` répond et que `getent` ne répond pas, le problème
> est dans `nsswitch.conf` ou dans `systemd-resolved`, pas dans le DNS.

---

<a id="q12-13"></a>**[Q12.13](README.md#q12-13)** — *Tester un vhost avant bascule DNS.*

**Réponse : b)** `curl --resolve shop.lab.local:443:10.10.10.11 https://shop.lab.local/`

> [!NOTE]
> **Pourquoi**
>
> `--resolve` injecte une entrée dans le résolveur **interne** de `curl` pour
> cette exécution seulement. Le triplet est `nom:port:adresse`, et le port doit
> correspondre à celui de l'URL, sinon l'entrée est ignorée sans avertissement.
>
> Ce que ça donne, et c'est ce qui le rend irremplaçable : la connexion TCP part
> vers `10.10.10.11`, mais **tout le reste croit parler à `shop.lab.local`** —
> l'en-tête `Host:`, et surtout le **SNI** du handshake TLS. Le serveur sélectionne
> donc le bon vhost et présente le bon certificat, et la vérification du nom dans
> le certificat réussit.
>
> ```console
> $ curl -s -o /dev/null -w '%{http_code} %{remote_ip}\n' \
>     --resolve www.exemple.lab:8099:127.0.0.1 http://www.exemple.lab:8099/
> 200 127.0.0.1
> ```
>
> C'est l'outil de la bascule : on valide le nouveau frontal en conditions
> réelles, avec le bon nom, avant de toucher au DNS public — et sans polluer le
> `/etc/hosts` de sa machine, qu'on oublie ensuite de nettoyer.

> [!WARNING]
> **Piège**
>
> a) `-H 'Host: ...'` sélectionne bien le vhost en HTTP, mais en **HTTPS** il ne
> change pas le SNI : le serveur présente le certificat par défaut, la
> vérification échoue, et on est tenté d'ajouter `-k`, qui masque justement ce
> qu'on voulait tester. c) `-k` désactive la vérification du certificat : jamais
> dans un test de validation, uniquement pour isoler volontairement un problème de
> chaîne de confiance. d) `dig @10.10.10.11` interroge `10.10.10.11` comme serveur
> DNS, ce qui n'a aucun rapport : c'est un serveur web.

---

<a id="q12-14"></a>**[Q12.14](README.md#q12-14)** — *SSH se connecte puis gèle sur `ls -lR /usr`, `ping` passe.*

**Réponse : b)** MTU inadapté sur le tunnel, avec les ICMP « fragmentation
needed » filtrés.

> [!NOTE]
> **Pourquoi**
>
> La signature est très reconnaissable : **les petits paquets passent, les gros
> non**. L'établissement de session SSH, la négociation, la bannière, la saisie au
> clavier : tout cela tient dans quelques centaines d'octets. Le premier transfert
> volumineux remplit des segments à la taille maximale, et ceux-là sont jetés.
>
> Le mécanisme complet :
>
> 1. La pile TCP annonce un MSS calculé sur le MTU de l'interface locale : 1500 -
>    20 (IP) - 20 (TCP) = 1460.
> 2. Les segments de 1460 octets de données partent, atteignent l'entrée du
>    tunnel, qui doit leur ajouter son propre en-tête (60 à 80 octets pour
>    WireGuard). Le paquet dépasse alors le MTU du lien physique.
> 3. Le paquet porte le bit **DF** (Don't Fragment), posé par la découverte de MTU
>    de chemin, qui est active par défaut (`net.ipv4.ip_no_pmtu_disc=0`). Le
>    routeur ne peut ni fragmenter ni transmettre : il **jette** le paquet.
> 4. Il devrait renvoyer un ICMP type 3 code 4 « fragmentation needed », qui
>    contient le MTU utilisable. L'émetteur ajusterait son MSS et tout repartirait.
> 5. Mais un pare-feu quelque part bloque « les ICMP » en bloc. Le message n'arrive
>    jamais. L'émetteur ne sait pas que ses paquets sont jetés : il retransmet, en
>    boucle, à la même taille. La session **gèle** sans jamais échouer proprement.
>
> C'est ce qu'on appelle un **trou noir PMTUD**. Le diagnostic tient en deux
> commandes : `ping -M do -s 1472` (échoue) puis dichotomie vers le bas pour
> trouver la taille qui passe.
>
> Deux corrections : baisser le MTU de l'interface du tunnel (`ip link set dev
> wg0 mtu 1380`), ce qui fait annoncer d'emblée un MSS plus petit ; ou, côté
> routeur, réécrire le MSS à la volée (`TCPMSS --clamp-mss-to-pmtu`) — technique
> détaillée au module 18. Et bien sûr : arrêter de bloquer les ICMP type 3.

> [!WARNING]
> **Piège**
>
> Le réflexe « je bloque tous les ICMP, c'est plus sûr » est la cause première de
> ce genre de panne. ICMP type 3 (destination unreachable) et type 11 (time
> exceeded) sont indispensables au fonctionnement de TCP et de `traceroute`. Ce
> qu'on peut limiter, c'est l'echo (type 8), et encore, au prix de la perte d'un
> outil de diagnostic.

---

<a id="q12-15"></a>**[Q12.15](README.md#q12-15)** — *Capture filtrée sur hôte + port, sans résolution, 100 paquets.*

**Réponse : a)** `tcpdump -i ens18 -nn -c 100 host 10.10.10.11 and port 443`

> [!NOTE]
> **Pourquoi**
>
> Les trois éléments à vérifier dans une commande `tcpdump` :
>
> * `-nn` : pas de résolution d'IP **ni** de ports. Un seul `-n` ne désactive que
>   la résolution des IP ; `443` continuerait de s'afficher `https`. Au-delà du
>   confort, c'est un point de robustesse : sur une machine dont le DNS est en
>   panne — ce qui est souvent le cas quand on capture — chaque paquet déclenche
>   une requête de résolution inverse qui expire. La capture devient inutilisable
>   et, pire, `tcpdump` génère lui-même le trafic qu'on cherche à observer.
> * `-c 100` : arrêt après 100 paquets. `--count` (d) n'existe pas dans ce sens (il compte les paquets d'un fichier relu); b) résout les noms et ne capture qu'un seul sens (`dst`).
> * Le filtre BPF `host X and port Y` : la syntaxe correcte. On peut le mettre
>   entre apostrophes, c'est même conseillé dès qu'il contient des parenthèses ou
>   des caractères interprétés par le shell.
>
> c) est faux sur deux points : `net 10.10.10.11` désigne un réseau, pas un hôte
> (il faut `host`), et le `or` capture tout ce qui touche au port 443 **ou** à ce
> réseau, soit bien plus large que demandé. La confusion `and`/`or` est l'erreur
> de filtre la plus fréquente.

> [!WARNING]
> **Piège**
>
> `-i any` est pratique mais trompeur : le pseudo-périphérique `any` capture en
> mode « Linux cooked », les en-têtes Ethernet ne sont pas réels, et certains
> filtres de couche 2 ne fonctionnent plus. Sur une machine avec des conteneurs,
> `-i any` voit aussi le trafic des `veth`, ce qui double chaque paquet. Nomme
> l'interface quand tu la connais.

---

<a id="q12-16"></a>**[Q12.16](README.md#q12-16)** — *Appliquer un changement Netplan sur une machine distante.*

**Réponse : b)** `sudo netplan try`, puis confirmer dans les 120 s.

> [!NOTE]
> **Pourquoi**
>
> `netplan try` applique la nouvelle configuration, puis attend une confirmation
> au clavier. Sans confirmation dans le délai (120 s par défaut, réglable avec
> `--timeout`), il **restaure automatiquement** la configuration précédente.
>
> C'est exactement le filet dont on a besoin en SSH : si ta modification te coupe
> la connexion, tu ne peux plus confirmer, donc la machine revient d'elle-même à
> l'état qui marchait. Deux minutes de coupure au lieu d'un déplacement en salle
> serveur ou d'une console de secours.
>
> ```console
> $ sudo netplan try
> Do you want to keep these settings?
>
> Press ENTER before the timeout to accept the new configuration
>
> Changes will revert in 120 seconds
> Configuration accepted.
> ```
>
> `netplan apply` (a) applique sans filet : correct en local ou via une console,
> dangereux à distance. `systemctl restart systemd-networkd` (c) est pire : il ne
> relit pas les fichiers Netplan, qui doivent d'abord être **traduits** en
> configuration `networkd` par `netplan generate` (`/run/systemd/network/*`). On
> obtient alors un état incohérent entre ce qu'on a écrit et ce qui tourne.
>
> La séquence complète et sûre :
>
> ```bash
> sudo netplan generate          # traduit le YAML, valide la syntaxe
> sudo netplan try               # applique avec rollback automatique
> ip -br a && ip r               # vérifie côté noyau
> ```

> [!WARNING]
> **Piège**
>
> `netplan try` ne protège pas de tout : il ne teste que la configuration réseau.
> Si ta modification est syntaxiquement valide et applicable mais fonctionnellement
> fausse (mauvaise passerelle, par exemple), la connexion tombe, le rollback a bien
> lieu — mais toute session applicative en cours a été coupée pendant deux minutes.
> Et `try` (comme `apply`) avertit si des fichiers Netplan sont en mode trop
> permissif : l' avertissement n'est pas bloquant, mais il faut le traiter, pas l' ignorer.

---

<a id="q12-17"></a>**[Q12.17](README.md#q12-17)** — *Adresse persistante sur Rocky 9 (deux réponses).*

**Réponses : a) et c)**

> [!NOTE]
> **Pourquoi**
>
> Rocky 9 n'utilise ni Netplan (spécifique à Ubuntu) ni, pour les nouvelles connexions, les anciens
> `ifcfg-*` (dépréciés depuis RHEL 9 : NetworkManager les lit encore, mais crée désormais tout au format keyfile). La configuration vit dans des fichiers
> **keyfile** :
>
> ```text
> /etc/NetworkManager/system-connections/lab-ens18.nmconnection   (mode 0600)
> ```
>
> Deux chemins équivalents pour la modifier :
>
> * `nmcli con mod` écrit directement dans le keyfile. C'est la voie scriptable et
>   celle qu'on utilise en production :
>
> ```bash
> sudo nmcli con mod lab-ens18 \
>   ipv4.method manual \
>   ipv4.addresses 10.10.10.13/24 \
>   ipv4.gateway 10.10.10.1 \
>   ipv4.dns "10.10.10.10 9.9.9.9" \
>   ipv4.dns-search lab.local
> sudo nmcli con up lab-ens18
> ```
>
> * Éditer le fichier à la main, puis `nmcli con reload` (relire les fichiers) et
>   `nmcli con up <nom>` (ré-appliquer). L'oubli du `reload` est l'erreur classique :
>   on modifie, on redémarre la connexion, et NetworkManager ré-applique ce qu'il
>   a en mémoire.
>
> b) `ip a add` est **volatile** : rien n'est écrit, tout disparaît au
> redémarrage de l'interface ou de la machine. C'est un outil de test, pas de
> configuration.

> [!WARNING]
> **Piège**
>
> `nmcli con mod` ne prend effet qu'après `nmcli con up`. Beaucoup de tickets
> « ma modification n'a rien changé » viennent de là : `nmcli con show lab-ens18`
> montre bien la nouvelle valeur (configuration enregistrée) alors que `ip a`
> montre l'ancienne (état actif). Les deux vues sont différentes, il faut les lire
> toutes les deux. `nmcli dev status` et `nmcli -p con show --active` donnent
> l'état réel.

---

<a id="q12-18"></a>**[Q12.18](README.md#q12-18)** — *`ip neigh` : `10.10.10.11 dev ens18 FAILED`.*

**Réponse : b)** aucune réponse ARP : hôte éteint, sur un autre VLAN, ou IP libre.

> [!NOTE]
> **Pourquoi**
>
> Les états de la table de voisinage décrivent le cycle de vie d'une entrée ARP :
>
> | État | Signification |
> |---|---|
> | `INCOMPLETE` | requête ARP envoyée, aucune réponse encore |
> | `REACHABLE` | adresse MAC connue et confirmée récemment (~30 s) |
> | `STALE` | MAC connue mais non confirmée : normal, pas une panne |
> | `DELAY` / `PROBE` | vérification en cours avant expiration |
> | `FAILED` | la résolution a échoué : **personne ne répond à cette IP** |
> | `PERMANENT` | entrée statique posée à la main |
>
> `FAILED` est un verdict de **couche 2** : la requête ARP a été diffusée sur le
> segment et rien n'est revenu. Ça élimine d'emblée toutes les hypothèses de
> couche 3 et au-dessus. Les causes réelles : machine éteinte, interface non
> montée, machine sur un autre VLAN (donc un autre domaine de diffusion malgré une
> IP du même réseau), adresse tout simplement non attribuée, ou masque incorrect
> faisant croire à tort que la destination est sur le segment local.
>
> Attention à l'inverse : une entrée `STALE` n'a rien d'alarmant. Le noyau
> n'entretient pas activement les entrées inutilisées ; il les revalide au
> prochain usage. Voir `STALE` partout dans `ip neigh` est normal sur une machine
> peu bavarde.
>
> Le test qui confirme, quand `arping` est disponible :
>
> ```bash
> sudo arping -I ens18 -c 3 10.10.10.11      # sollicite directement en ARP
> sudo arping -D -I ens18 -c 3 10.10.10.10   # -D : détection de conflit d'IP
> ```
>
> Deux réponses à un `arping -D` avec deux MAC différentes = **conflit d'adresse**.
> Symptôme côté utilisateur : connectivité intermittente, qui « marche une fois sur
> deux », selon l'entrée ARP que chaque machine a mémorisée.

---

## 12.4 Quiz — questions ouvertes

<a id="qo12-1"></a>**[QO12.1](README.md#qo12-1)** — *Chemin complet de `curl https://www.lab.local/`, étape par étape.*

**Réponse attendue** — sept étapes, chacune avec son fichier et sa commande de
vérification.

| Étape | Composant | Commande de vérification |
|---|---|---|
| 1. résolution | `nsswitch`, `hosts`, stub | `getent hosts www.lab.local` |
| 2. route | table de routage | `ip route get 10.10.10.11` |
| 3. ARP | table de voisinage | `ip neigh show 10.10.10.11` |
| 4. TCP | poignée de main | `nc -zv 10.10.10.11 443` |
| 5. TLS | handshake, SNI, certificat | `openssl s_client -connect ...` |
| 6. HTTP | requête, vhost | `curl -v` |
| 7. serveur | nginx, backend | `journalctl -u nginx` |

Le détail :

1. `curl` appelle `getaddrinfo("www.lab.local", "443")`. La glibc lit
   `/etc/nsswitch.conf`, ligne `hosts:`. `files` → `/etc/hosts`. Si rien,
   `dns` → `/etc/resolv.conf` → `127.0.0.53` → `systemd-resolved` → cache, sinon
   serveur amont `10.10.10.10`. Réponse : `CNAME` vers `lab-web.lab.local`, puis
   `A 10.10.10.11`. Si l'hôte a aussi un `AAAA`, il est essayé **en premier**
   (RFC 6724).
2. La pile consulte la table de routage pour `10.10.10.11`. Destination sur le
   réseau local (`10.10.10.0/24`, `scope link`) : pas de passerelle, envoi direct.
   Source choisie : `10.10.10.10`.
3. Pour émettre la trame, il faut la MAC de `10.10.10.11`. Consultation du cache
   de voisinage, sinon requête ARP diffusée sur le segment.
4. Poignée de main TCP vers le port 443 : `SYN`, `SYN-ACK`, `ACK`. Port éphémère
   local tiré dans `ip_local_port_range`.
5. Handshake TLS : `ClientHello` avec **SNI = www.lab.local**, le serveur
   sélectionne le vhost et présente le certificat correspondant. `curl` vérifie
   la chaîne contre `/etc/ssl/certs/`, le nom (SAN) et les dates.
6. Requête HTTP avec `Host: www.lab.local`. nginx sélectionne le `server` dont
   le `server_name` correspond.
7. nginx sert le fichier ou relaie vers le backend, et renvoie le statut.

> [!NOTE]
> **Pourquoi**
>
> L'intérêt de cette décomposition n'est pas encyclopédique : c'est qu'**à chaque
> étape correspond une panne différente et une commande différente**. Savoir la
> réciter, c'est savoir diagnostiquer sans tâtonner.
>
> Les correspondances panne → étape, dans l'ordre de fréquence réelle :
> `/etc/hosts` fantôme (1), serveur DNS injoignable (1), route par défaut absente
> (2), VLAN ou hôte éteint (3), service non démarré ou lié à `127.0.0.1` (4),
> certificat expiré ou SNI absent (5), vhost par défaut qui répond à la place du
> bon (6), backend en erreur (7).
>
> La double sélection par le nom est le point que beaucoup ratent : `www.lab.local`
> sert **deux fois**, au SNI (étape 5) et à l'en-tête `Host:` (étape 6). C'est
> pour ça que `-H 'Host: ...'` seul ne suffit pas en HTTPS, et que `--resolve`,
> qui préserve les deux, est le bon outil.

---

<a id="qo12-2"></a>**[QO12.2](README.md#qo12-2)** — *Entretien : « ça marche avec l'IP mais pas avec le nom », cinq causes.*

**Réponse attendue** :

| Cause | Commande qui confirme |
|---|---|
| Entrée `/etc/hosts` erronée ou obsolète | `getent hosts X` vs `dig +short @<serveur> X` |
| Serveur DNS injoignable ou en `SERVFAIL` | `dig @<serveur> X` |
| Nom inexistant / faute de frappe | `dig X` → `status: NXDOMAIN` |
| Domaine de recherche absent (nom court) | `resolvectl status`, `dig X.lab.local` |
| AAAA résolu mais IPv6 cassé | `curl -4 X` réussit, `curl -6 X` échoue |

Formulation d'entretien : « Je commence par séparer ce que voit le système de ce
que dit le DNS : `getent hosts` d'un côté, `dig` `@<serveur>` de l'autre. S'ils divergent, le
problème est local — `hosts` ou `nsswitch`. S'ils convergent et que ça ne marche
toujours pas, je regarde la famille d'adresses : un `AAAA` qui répond sur un
réseau sans IPv6 fonctionnelle donne exactement ce symptôme. »

> [!NOTE]
> **Pourquoi**
>
> La question teste une seule chose : sais-tu que **le DNS n'est qu'une des
> sources de noms** ? Le candidat moyen part sur « je vérifie le DNS » et reste
> bloqué quand `dig` répond correctement.
>
> Les deux causes qui font la différence en entretien sont la quatrième et la
> cinquième. Le domaine de recherche : `ping lab-db` échoue alors que
> `ping lab-db.lab.local` fonctionne, parce que `search lab.local` n'est pas
> configuré. Et la bascule IPv6 : `getaddrinfo()` trie les résultats selon la
> RFC 6724, qui préfère IPv6 quand une adresse IPv6 globale est disponible
> localement. Si l'hôte publie un `AAAA` et que le chemin v6 est filtré ou que la
> route v6 est absente, toutes les applications qui résolvent par nom partent en
> v6 et échouent, alors que l'accès direct par IPv4 fonctionne. `curl -4` contre
> `curl -6` tranche en deux secondes.

> [!WARNING]
> **Piège**
>
> Le contournement « j'ajoute une ligne dans `/etc/hosts` » est la dette technique
> la plus fréquente de l'exploitation. Elle marche le jour même et devient la
> panne du trimestre suivant, quand l'IP change côté DNS et que plus personne ne
> se souvient de cette ligne — c'est exactement BF12.4. Si tu dois le faire en
> urgence, mets un commentaire daté avec le numéro de ticket au-dessus.

---

<a id="qo12-3"></a>**[QO12.3](README.md#qo12-3)** — *`TIME-WAIT` contre `CLOSE-WAIT`.*

**Réponse attendue** :

| | `TIME-WAIT` | `CLOSE-WAIT` |
|---|---|---|
| Qui ferme | nous (fermeture active) | le pair (fermeture passive) |
| Sens | on a envoyé le premier `FIN` | on a reçu un `FIN`, pas répondu |
| Durée | 60 s fixes (2×MSL) | **illimitée**, tant que pas de `close()` |
| Verdict | normal | bug applicatif |

`TIME-WAIT` : normal sur tout client qui ferme ses connexions. Devient un
problème seulement à volume élevé vers une même destination (épuisement des
ports éphémères, `EADDRNOTAVAIL`). Correctifs : connexions persistantes,
`tcp_tw_reuse`, élargissement de `ip_local_port_range`.

`CLOSE-WAIT` : toujours anormal au-delà de quelques unités transitoires.
L'application n'appelle pas `close()` sur le descripteur. Correctif : le code.

Ce qu'il ne faut pas faire : pour `TIME-WAIT`, toucher à `tcp_fin_timeout` (qui
gouverne `FIN-WAIT-2`) ou activer `tcp_tw_recycle` (supprimé du noyau en 4.12,
cassait le NAT). Pour `CLOSE-WAIT`, chercher un `sysctl` : il n'y en a pas, et
redémarrer le service en boucle n'est qu'un sursis.

> [!NOTE]
> **Pourquoi**
>
> Le fil conducteur : **regarder de quel côté part le premier `FIN`**. Tout
> découle de là. Celui qui ferme en premier finit en `TIME-WAIT` ; celui qui reçoit
> passe par `CLOSE-WAIT` puis `LAST-ACK`. Si tu tiens ce fil, tu n'as plus rien à
> mémoriser.
>
> La séquence complète, à savoir tracer :
>
> ```text
> actif (ferme)            passif (reçoit)
> ESTAB                    ESTAB
>  --FIN-->  FIN-WAIT-1
>            <--ACK--      CLOSE-WAIT   <- l'appli doit appeler close()
>  FIN-WAIT-2
>            <--FIN--      LAST-ACK
>  --ACK-->  TIME-WAIT (60 s)
>            CLOSED        CLOSED
> ```
>
> Une accumulation de `CLOSE-WAIT` se lit directement sur ce schéma : le pair est
> passé à `FIN-WAIT-2`, nous sommes bloqués en `CLOSE-WAIT`, et la connexion ne se
> terminera jamais. Chaque descripteur reste consommé, jusqu'à
> `Too many open files`.

---

<a id="qo12-4"></a>**[QO12.4](README.md#qo12-4)** — *Entretien : « la VM ping sa passerelle mais pas internet ».*

**Réponse attendue** — sept étapes, dans l'ordre, chacune avec ce qu'on lit :

```bash
ip r                       # 1. y a-t-il une route par défaut ?
ip route get 9.9.9.9       # 2. quelle route, quelle source réellement ?
ping -c2 9.9.9.9           # 3. IP brute : réseau ou DNS ?
ping -c2 www.google.com    # 4. si 3 passe et 4 non -> DNS
ip neigh show 10.10.10.1   # 5. la passerelle répond-elle en ARP ?
traceroute -n 9.9.9.9      # 6. où ça s'arrête
sudo tcpdump -i ens18 -nn icmp   # 7. les paquets sortent-ils ?
```

Ce qu'on lit à chaque étape :

1. Absence de ligne `default` = la cause est trouvée, on s'arrête là.
2. `src` : la bonne adresse source ? `dev` : la bonne interface ?
3. `Network is unreachable` immédiat = pas de route. Timeout = ça part, rien ne
   revient. `Destination Host Unreachable` = ARP échoue au premier saut.
4. Ping IP OK + ping nom KO = **le réseau va bien**, c'est du DNS.
5. `REACHABLE` = la passerelle est vivante. `FAILED` = problème de couche 2.
6. Le dernier saut qui répond localise la coupure ; des `* * *` dès le premier
   saut signalent souvent un filtrage plutôt qu'une coupure.
7. Si les `echo request` partent et que rien ne revient, le problème est en
   amont, pas sur la machine — information décisive pour escalader.

> [!NOTE]
> **Pourquoi**
>
> Ce que l'examinateur évalue, ce n'est pas la liste des commandes : c'est que tu
> **dichotomises**. À chaque étape tu élimines une moitié de l'espace des causes.
>
> La distinction la plus discriminante est celle de l'étape 3 : le message de
> `ping` change selon l'étage fautif, et il faut savoir le lire.
>
> | Message | Étage | Cause |
> |---|---|---|
> | `Network is unreachable` (immédiat) | routage local | pas de route |
> | `Destination Host Unreachable` | couche 2 locale | ARP sans réponse |
> | rien, puis 100 % perte | en amont | filtrage ou coupure |
> | `Name or service not known` | résolution | DNS, pas réseau |
>
> L'immédiateté est l'information : un refus instantané vient de **ta** machine
> (elle sait déjà qu'elle ne peut pas). Un délai vient du réseau.
>
> Mention qui fait la différence en entretien : « et je vérifie aussi que le
> problème n'est pas symétrique — le retour. Un `tcpdump` côté serveur qui voit
> arriver les `SYN` alors que le client ne voit jamais de `SYN-ACK` déplace tout
> le diagnostic vers la route de retour ou une source mal choisie. »

---

<a id="qo12-5"></a>**[QO12.5](README.md#qo12-5)** — *Netplan, nmcli, ifupdown : laquelle est active ?*

**Réponse attendue** — procédure en quatre commandes :

```bash
ls /etc/netplan/*.yaml 2>/dev/null           # Ubuntu 18.04+
systemctl is-active NetworkManager systemd-networkd networking
nmcli dev status 2>/dev/null                 # "unmanaged" = pas NM
cat /etc/network/interfaces 2>/dev/null      # héritage ifupdown
```

Lecture :

* Ubuntu 24.04 serveur par défaut : fichiers dans `/etc/netplan/`,
  `systemd-networkd` actif, `NetworkManager` absent. Netplan **génère**
  `/run/systemd/network/*` : c'est `networkd` qui applique, mais on édite le YAML.
* Rocky 9 : `NetworkManager` actif, keyfiles dans
  `/etc/NetworkManager/system-connections/`, pas de Netplan.
* Debian ancien / machine héritée : `networking.service` actif,
  `/etc/network/interfaces` non vide.

Si deux mécanismes coexistent : chacun croit gérer l'interface. Symptômes réels :
adresse qui revient toute seule après suppression, deux routes par défaut,
adresse perdue après un `nmcli con up`, comportement différent au redémarrage et
à chaud. Le cas le plus courant est une machine migrée où `/etc/network/interfaces`
a survécu à l'installation de Netplan.

La règle : **un seul gestionnaire par interface**. Netplan sait déléguer à
NetworkManager (`renderer: NetworkManager`) — c'est la bonne façon de faire
cohabiter les deux, pas de les laisser se disputer.

> [!NOTE]
> **Pourquoi**
>
> La question qui fait le tri en entretien : « qui applique, et qui décrit ? »
> Netplan ne configure rien lui-même. C'est un **générateur** : il traduit le YAML
> en configuration `systemd-networkd` (ou NetworkManager) dans `/run`, puis
> déclenche l'application. D'où deux conséquences que beaucoup ignorent :
>
> * modifier directement `/etc/systemd/network/*.network` sur Ubuntu ne sert à
>   rien : le prochain `netplan apply` régénère par-dessus ;
> * `netplan get` montre la configuration **fusionnée** de tous les fichiers, ce
>   qui n'est pas forcément le contenu d'un fichier donné.
>
> Ordre de fusion : les fichiers de `/etc/netplan/` sont lus par ordre
> lexicographique et **fusionnés**, pas remplacés. `01-lab.yaml` est lu avant
> `50-cloud-init.yaml`, et en cas de clé identique, c'est le **dernier lu** qui
> gagne. C'est pourquoi on nomme ses fichiers avec un préfixe numérique élevé, ou
> qu'on neutralise `cloud-init` avec
> `/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg`.

---

<a id="qo12-6"></a>**[QO12.6](README.md#qo12-6)** — *Tunnel VXLAN, sessions qui gèlent sur les gros transferts.*

**Réponse attendue** — mécanisme en six temps :

1. L'application écrit 100 Ko. TCP découpe en segments de MSS = 1460 (calculé
   sur le MTU local de 1500 : 1500 - 20 IP - 20 TCP).
2. Le paquet IP fait 1500 octets et porte le bit **DF**, posé par la découverte
   de MTU de chemin, active par défaut.
3. À l'entrée du tunnel, VXLAN encapsule : + 8 (VXLAN) + 8 (UDP) + 20 (IP
   externe) + 14 (Ethernet interne) ≈ **50 octets**. Le paquet ferait 1550
   octets sur un lien à MTU 1500.
4. Le routeur ne peut ni fragmenter (DF) ni transmettre : il **jette**.
5. Il devrait renvoyer un **ICMP type 3 code 4** contenant le MTU utilisable
   (1450). L'émetteur réduirait son MSS et tout repartirait en une
   milliseconde. Mais un pare-feu bloque « les ICMP » : le message n'arrive pas.
6. L'émetteur ne sait rien. Il retransmet à l'identique, indéfiniment. La
   session **gèle** sans erreur — c'est un trou noir PMTUD.

Pourquoi la session s'établit : `SYN`, `SYN-ACK`, `ACK` et les premiers échanges
font quelques dizaines d'octets. Ils passent. Seuls les segments pleins sont
jetés.

Diagnostic :

```bash
ping -M do -s 1472 -c 2 10.20.0.5     # 1472+28 = 1500 -> échoue
ping -M do -s 1422 -c 2 10.20.0.5     # 1422+28 = 1450 -> passe
tracepath 10.20.0.5                   # affiche « pmtu 1450 »
```

Corrections, dans l'ordre de préférence :

1. Aligner le MTU de l'interface du tunnel : `ip link set dev vxlan0 mtu 1450`,
   puis le figer dans la configuration persistante. L'émetteur annonce alors
   d'emblée MSS = 1410.
2. Réécrire le MSS sur le routeur (`TCPMSS --clamp-mss-to-pmtu`) — détaillé au
   module 18. Utile quand on ne maîtrise pas les machines des deux côtés.
3. Et dans tous les cas : cesser de filtrer ICMP type 3.

> [!NOTE]
> **Pourquoi**
>
> Le point conceptuel : **TCP ne découvre pas le MTU du chemin, il le déduit des
> ICMP**. Retire les ICMP, et la découverte devient aveugle. Le noyau a bien un
> repli, `net.ipv4.tcp_mtu_probing`, qui sonde par dichotomie quand il détecte des
> retransmissions répétées. Il est désactivé par défaut (`0`) sur la plupart des
> distributions ; le passer à `1` est un contournement utile sur des machines
> exposées à des chemins mal maîtrisés, pas un correctif.
>
> Les surcharges à connaître de tête, parce que c'est ce qu'on te demandera :
> VXLAN 50, GENEVE ~50, WireGuard 60 (v4) à 80 (v6), IPsec ESP 50-73, GRE 24,
> PPPoE 8. D'où les MTU usuels : 1450 pour VXLAN, 1420 pour WireGuard, 1492 pour
> PPPoE (le fameux MTU ADSL).

---

<a id="qo12-7"></a>**[QO12.7](README.md#qo12-7)** — *`dig`, `getent hosts`, `resolvectl query`.*

**Réponse attendue** :

| Outil | Ce qu'il consulte | Ce qu'il ignore |
|---|---|---|
| `getent hosts` | toute la chaîne NSS | rien : c'est la vérité système |
| `dig @serveur` | le DNS seul, ce serveur-là | `/etc/hosts`, `nsswitch`, NSS |
| `resolvectl query` | `systemd-resolved` : `hosts` + cache + amont | — |

Sans `@`, `dig` parle au stub `127.0.0.53`, qui sert aussi `/etc/hosts` : il
voit alors ce que voit `resolvectl query`, pas le DNS seul.

Pour prouver que le problème vient du DNS : `dig @<serveur-autoritaire> <nom>`.
Si le serveur faisant autorité répond correctement et que `getent` répond autre
chose, le DNS est hors de cause : le problème est local.

Cas où les trois commandes donnent trois réponses : un nom `www.lab.local` présent dans `/etc/hosts`
avec `10.10.10.99`, dont l'enregistrement DNS vient de passer de `10.10.10.12` à `10.10.10.11` sur le serveur, un
cache de `systemd-resolved` qui contient encore `10.10.10.12`
( TTL non expiré), et `ReadEtcHosts=no` dans `resolved.conf` (sinon `resolved` sert lui aussi `/etc/hosts`, en priorité, y compris à `dig` via le stub).

* `getent hosts` → `10.10.10.99` (fichier, gagne)
*; `resolvectl query` → `10.10.10.12` (`Data from:` cache)
*; un `dig +short` sans `@`, via le stub, donnerait la même chose ; `dig @10.10.10.10 +short` → `10.10.10.11` (le serveur, sans aucun cache).

> [!NOTE]
> **Pourquoi**
>
> La hiérarchie à retenir : `getent` est la **référence**, parce qu'il emprunte
> exactement le chemin des applications. `dig` est l'**instrument de mesure** du
> DNS seul. `resolvectl query` montre ce que le résolveur systemd a en tête,
> cache compris, et affiche explicitement la provenance :
>
> ```console
> $ resolvectl query www.lab.local
> www.lab.local: 10.10.10.11                     -- link: ens18
> -- Information acquired via protocol DNS in 1.2ms.
> -- Data from: cache
> ```
>
> La ligne `Data from: cache` ou `network` est l'information la plus utile de
> toute la sortie : elle répond en un mot à « est-ce que je lis du cache ? ».
>
> Un dernier écart, subtil mais fréquent : `dig lab-db` **n'ajoute pas** le domaine
> de recherche (il faut `+search`, désactivé par défaut) :
> avec un nom court la requête part telle quelle et échoue ( `NXDOMAIN` ou pas de réponse),
> alors que `getent hosts lab-db` réussit grâce à `search lab.local`. Le réflexe :
> tester les noms courts avec `getent`, les FQDN avec `dig`.

---

<a id="qo12-8"></a>**[QO12.8](README.md#qo12-8)** — *`ip a add` marche, puis tout casse après redémarrage.*

**Réponse attendue** : `ip a add` parle directement au noyau via netlink. Le
noyau garde l'état en mémoire, **rien n'est écrit sur disque**. Au redémarrage,
la pile réseau repart vide, puis `systemd-networkd` (piloté par Netplan) applique
la configuration des fichiers. L'adresse ajoutée à la main n'y figure pas : elle
disparaît. Même effet, sans redémarrage, après `netplan apply`, `nmcli con up`,
ou un `ip link set dev ens18 down/up`.

La bonne méthode :

```bash
# 1. tester à chaud, vérifier que la cible est atteinte
sudo ip a add 10.10.20.10/24 dev ens18
# ... validation fonctionnelle ...
sudo ip a del 10.10.20.10/24 dev ens18      # on nettoie

# 2. écrire la configuration persistante
sudoedit /etc/netplan/01-lab.yaml
sudo netplan generate && sudo netplan try   # filet de 120 s

# 3. prouver la persistance
sudo reboot && ip -br a
```

> [!NOTE]
> **Pourquoi**
>
> La distinction **état** / **configuration** structure toute l'administration
> système, et le réseau en est l'illustration la plus nette. `ip`, `ss`, `sysctl -w`
> manipulent l'état vivant du noyau. Netplan, `nmcli`, `/etc/sysctl.d/` décrivent
> l'intention, et quelque chose doit la ré-appliquer au démarrage.
>
> Les deux erreurs symétriques, également coûteuses :
>
> * modifier uniquement l'état : ça marche, jusqu'au prochain redémarrage — c'est
>   la panne du lundi matin après la fenêtre de patch, six semaines plus tard,
>   quand personne ne fait plus le lien ;
> * modifier uniquement la configuration : ça ne marche pas tout de suite, on croit
>   s'être trompé, on empile d'autres changements, et on se retrouve avec un
>   fichier qu'on ne comprend plus.
>
> La discipline : on teste à chaud, on nettoie, on écrit, on applique avec un
> filet, on prouve par un redémarrage. La preuve par redémarrage n'est pas du zèle :
> c'est le seul test qui valide vraiment la configuration persistante.

---

<a id="qo12-9"></a>**[QO12.9](README.md#qo12-9)** — *`iperf3` : 940 Mbit/s avec `Retr 0` contre 210 Mbit/s avec `Retr 4213`.*

**Réponse attendue** : la colonne `Retr` compte les **segments TCP retransmis**
pendant l'intervalle. Une retransmission signifie qu'un segment a été perdu (ou
son accusé de réception), ce qui déclenche le contrôle de congestion : réduction
de la fenêtre, effondrement du débit. 4213 retransmissions sur 10 secondes n'est
pas un ajustement, c'est de la perte de paquets soutenue.

Les trois causes à vérifier en priorité :

1. **Couche physique / lien** : erreurs CRC, câble, duplex négocié en `half`,
   port de commutateur dégradé.
   `ip -s link show ens18` (colonnes `errors`, `dropped`), `ethtool -S ens18`
   (compteurs `rx_crc_errors`, `rx_missed_errors`), `ethtool ens18` (vitesse et
   duplex réels).
2. **MTU / fragmentation** : un MTU incohérent sur le chemin produit exactement
   ce profil, gros débit théorique et perte massive. `ping -M do -s` par
   dichotomie, `tracepath`.
3. **Saturation ou mise en file** : lien partagé, limitation de débit, file
   d'attente pleine sur un équipement intermédiaire. `mtr -rwc 100` montre où la
   perte apparaît ; `ss -ti` donne `retrans`, `rtt`, `cwnd` par connexion.

Le rapport à écrire : débit, `Retr`, et le compteur d'erreurs d'interface
**avant et après** le test. Un `Retr` élevé sans erreur d'interface oriente vers
le chemin ; avec erreurs d'interface, vers le lien local.

> [!NOTE]
> **Pourquoi**
>
> Ce qu'on teste ici, c'est la capacité à ne pas s'arrêter au chiffre de débit.
> Un débit seul ne dit rien : c'est la **conséquence**. `Retr` en dit la cause.
>
> À savoir lire aussi dans la sortie `iperf3` :
>
> * `Cwnd` : la fenêtre de congestion. Une `Cwnd` qui s'effondre puis remonte en
>   dents de scie est la signature du contrôle de congestion face à de la perte.
> * Un lien à forte latence (`BDP` = débit × RTT) peut plafonner sans aucune perte,
>   simplement parce que la fenêtre ne suffit pas à remplir le tuyau. C'est le cas
>   typique d'un lien transcontinental : 1 Gbit/s à 150 ms de RTT demande environ
>   18 Mo de fenêtre. `iperf3 -P 8` (8 flux parallèles) le met en évidence : si le
>   cumul des flux dépasse nettement le flux unique **sans** que `Retr` augmente,
>   le problème est la fenêtre, pas la perte.
> * `iperf3 -R` (sens inverse) : indispensable, beaucoup de liens sont
>   asymétriques, et certaines limitations ne s'appliquent que dans un sens.
> * `iperf3 -u -b 900M` : en UDP, on lit directement `Lost/Total Datagrams` et la
>   gigue — utile quand on soupçonne une limitation de débit qui ne se voit pas en
>   TCP.

---

## 12.5 Exercices guidés

<a id="e12-1"></a>**[E12.1](README.md#e12-1)** — *Interfaces `UP` et adresses IPv4 uniquement.*

```bash
ip -4 -br a show up
```

Sortie attendue sur `lab-adm` :

```console
$ ip -4 -br a show up
lo               UNKNOWN        127.0.0.1/8
ens18            UP             10.10.10.10/24
```

> [!NOTE]
> **Pourquoi**
>
> Trois options qui se combinent et qu'on utilise en permanence :
>
> * `-4` restreint à la famille IPv4 (`-6` pour IPv6). Sans elle, les link-local
>   IPv6 encombrent toutes les sorties.
> * `-br` (bref) : une ligne par interface, colonnes fixes. C'est le format à
>   utiliser dès qu'on veut lire vite ou traiter avec `awk`.
> * `show up` filtre sur le drapeau administratif `UP`.
>
> Pour ne garder que les interfaces physiques et exclure la boucle :
>
> ```bash
> ip -4 -br a show up scope global
> ```
>
> `scope global` élimine `lo` (dont l'adresse est de portée `host`) et les
> link-local. C'est le filtre le plus propre pour un script d'inventaire.

---

<a id="e12-2"></a>**[E12.2](README.md#e12-2)** — *Adresse secondaire à chaud, deux preuves, puis suppression.*

```bash
sudo ip a add 10.10.20.10/24 dev ens18

# preuve 1 : l'adresse est dans la table du noyau
ip -4 -br a show dev ens18

# preuve 2 : elle est fonctionnelle, la pile l'utilise comme source
ping -c1 -I 10.10.20.10 10.10.20.10
ip route get 10.10.20.99

sudo ip a del 10.10.20.10/24 dev ens18
ip -4 -br a show dev ens18
```

```console
$ ip -4 -br a show dev ens18
ens18            UP             10.10.10.10/24 10.10.20.10/24
$ ip route get 10.10.20.99
10.10.20.99 dev ens18 src 10.10.20.10 uid 1000
    cache
```

> [!NOTE]
> **Pourquoi**
>
> `ip a add` **ajoute** une adresse, il ne remplace pas : une interface Linux peut
> porter autant d'adresses IP qu'on veut, de réseaux différents. C'est une
> différence de modèle majeure avec l'ancien `ifconfig`, qui ne connaissait qu'une
> adresse principale et des alias numérotés (`eth0:0`, `eth0:1`) — une fiction
> d'espace utilisateur, pas une réalité du noyau.
>
> Point remarquable de la sortie de `ip route get` : dès que `10.10.20.10/24` est
> posée, le noyau crée automatiquement une route `10.10.20.0/24 dev ens18
> proto kernel scope link src 10.10.20.10`. C'est le `proto kernel` de `ip r` : la
> route n'a été ajoutée par personne, elle découle de la configuration d'adresse.
> D'où la source choisie pour `10.10.20.99`.
>
> Pour remplacer réellement une adresse : `ip a replace`, ou `ip a flush dev ens18`
> puis `add`. Attention avec `flush` à distance : il supprime aussi l'adresse par
> laquelle tu es connecté.

---

<a id="e12-3"></a>**[E12.3](README.md#e12-3)** — *Chemin vers `9.9.9.9` et vers `10.10.10.12`, sans émettre de paquet.*

```bash
ip route get 9.9.9.9
ip route get 10.10.10.12
```

```console
$ ip route get 9.9.9.9
9.9.9.9 via 10.10.10.1 dev ens18 src 10.10.10.10 uid 1000
    cache
$ ip route get 10.10.10.12
10.10.10.12 dev ens18 src 10.10.10.10 uid 1000
    cache
```

> [!NOTE]
> **Pourquoi**
>
> L'écart tient en un mot : `via`. Il est présent dans la première réponse,
> absent dans la seconde.
>
> `10.10.10.12` appartient à `10.10.10.0/24`, réseau directement connecté (route
> `scope link` créée par le noyau avec l'adresse). La machine peut joindre cette
> destination **directement**, par ARP sur le segment : elle demande la MAC de
> `10.10.10.12` et émet la trame vers elle. Pas de passerelle.
>
> `9.9.9.9` ne correspond à aucune route plus spécifique que la route par défaut.
> Le noyau retient `default via 10.10.10.1`, et la trame sera adressée à la **MAC
> de la passerelle**, avec l'IP de destination toujours `9.9.9.9`. C'est le point
> que beaucoup n'ont jamais formulé : le routage change l'adresse MAC de
> destination à chaque saut, jamais l'adresse IP de destination.
>
> Aucun paquet n'est émis par `ip route get` : c'est une interrogation de la table,
> pas un test. D'où son utilité quand ICMP est filtré et que `ping` ne dit rien.

---

<a id="e12-4"></a>**[E12.4](README.md#e12-4)** — *Traduire quatre lignes de `net-tools`.*

```bash
# ifconfig eth0 192.168.1.5 netmask 255.255.255.0 up
ip a add 192.168.1.5/24 dev eth0
ip link set dev eth0 up

# route add -net 10.20.0.0 netmask 255.255.0.0 gw 192.168.1.1
ip r add 10.20.0.0/16 via 192.168.1.1

# arp -an
ip neigh

# netstat -tulpn | grep 8080
ss -tulpn 'sport = :8080'
```

Ce que l'ancienne commande ne savait pas faire :

1. `ifconfig` écrase l'adresse au lieu d'en ajouter une, ne comprend pas la
   notation CIDR, et gère mal plusieurs adresses (alias `eth0:0` fictifs).
2. `route` ne connaît qu'une table de routage, ignore `ip rule`, les métriques
   fines, `src`, `scope` et le routage par politique.
3. `arp` ne montre pas les états du voisinage (`REACHABLE`, `STALE`, `FAILED`)
   ni IPv6 (NDP), alors que `ip neigh` unifie les deux.
4. `netstat` lit `/proc/net/*` en texte et le re-analyse : plusieurs secondes sur
   une machine à 100 000 sockets. `ss` interroge netlink (`sock_diag`) et
   **filtre côté noyau**, d'où le filtre `sport = :8080` qui évite le `grep`.

> [!NOTE]
> **Pourquoi**
>
> Au-delà de la table, la raison de fond : `net-tools` n'évolue quasiment plus (dernière version en 2021) et reflète un modèle réseau qui n'est plus celui du noyau. `iproute2` est
> l'interface de référence de l'équipe réseau du noyau ; toute fonctionnalité
> nouvelle y apparaît, et nulle part ailleurs.
>
> Le piège de migration : les sorties n'ont pas le même format, donc **tout script
> qui grep une sortie de `ifconfig` ou `netstat` doit être réécrit**, pas
> simplement redirigé. Et si tu dois vraiment traiter une sortie par programme,
> `ip -j` (JSON) existe et évite l'analyse fragile :
>
> ```bash
> ip -j -4 a show dev ens18 | jq -r '.[0].addr_info[0].local'
> ```
>
> Enfin, sur les machines où `net-tools` n'est pas installé — c'est le cas par
> défaut sur Ubuntu 24.04 et Rocky 9 — un vieux script de supervision échoue avec
> `ifconfig: command not found`. Installer `net-tools` pour le faire taire est le
> mauvais réflexe : c'est le moment de le réécrire.

---

<a id="e12-5"></a>**[E12.5](README.md#e12-5)** — *Cinq calculs de sous-réseaux.*

| Adresse | Réseau | Diffusion | Utilisables |
|---|---|---|---|
| `192.168.42.130/26` | `192.168.42.128` | `192.168.42.191` | `.129`–`.190` (62) |
| `172.16.5.200/21` | `172.16.0.0` | `172.16.7.255` | `.0.1`–`.7.254` (2046) |
| `203.0.113.77/28` | `203.0.113.64` | `203.0.113.79` | `.65`–`.78` (14) |
| `10.42.7.99/22` | `10.42.4.0` | `10.42.7.255` | `.4.1`–`.7.254` (1022) |
| `192.168.100.37/27` | `192.168.100.32` | `192.168.100.63` | `.33`–`.62` (30) |

Masques : `/26` = 255.255.255.192, `/21` = 255.255.248.0, `/28` =
255.255.255.240, `/22` = 255.255.252.0, `/27` = 255.255.255.224.

Vérification :

```bash
python3 -c 'import ipaddress as i,sys
for c in sys.argv[1:]:
    n=i.ip_interface(c).network; h=list(n.hosts())
    print(f"{c:20} {n} bc={n.broadcast_address} {h[0]}-{h[-1]} ({len(h)})")' \
  192.168.42.130/26 172.16.5.200/21 203.0.113.77/28 10.42.7.99/22 \
  192.168.100.37/27
```

> [!NOTE]
> **Pourquoi**
>
> La méthode qui marche de tête, sans binaire, en trois temps.
>
> **1. Trouver l'octet significatif.** Le préfixe te dit combien d'octets sont
> entièrement fixés : `/21` → 2 octets pleins (16 bits) + 5 bits dans le
> troisième. L'octet significatif est donc le **troisième**.
>
> **2. Calculer le pas.** `pas = 256 - valeur du masque dans cet octet`. Pour `/21`,
> le masque du troisième octet est 248, donc pas = 8. Les frontières sont 0, 8, 16,
> 24… Pour `/22` : masque 252, pas 4 → 0, 4, 8, 12.
>
> **3. Encadrer.** Pour `172.16.5.200/21`, troisième octet = 5, frontières 0 et 8 :
> le réseau est `172.16.0.0`, le suivant `172.16.8.0`, donc la diffusion est
> `172.16.7.255`.
>
> Le tableau des masques à connaître par cœur, c'est celui des valeurs possibles
> d'un octet de masque : 128, 192, 224, 240, 248, 252, 254, 255 — et leurs pas
> respectifs 128, 64, 32, 16, 8, 4, 2, 1. Huit valeurs, c'est tout ce qu'il y a à
> mémoriser pour ne plus jamais se tromper.

> [!WARNING]
> **Piège**
>
> L'erreur la plus fréquente sur `/21` et `/22` : oublier que le pas s'applique au
> **troisième** octet, et calculer comme si on était sur un `/24`. `10.42.7.99/22`
> n'est pas dans `10.42.7.0`, il est dans `10.42.4.0` — parce que 7 tombe dans le
> bloc `[4, 8[`. Toujours identifier l'octet significatif **avant** de calculer.

---

<a id="e12-6"></a>**[E12.6](README.md#e12-6)** — *Découper `10.10.10.0/24` en quatre.*

Quatre sous-réseaux égaux = 2 bits empruntés = `/26`, pas de 64 :

| Préfixe | Utilisables | Diffusion |
|---|---|---|
| `10.10.10.0/26` | `.1` – `.62` | `10.10.10.63` |
| `10.10.10.64/26` | `.65` – `.126` | `10.10.10.127` |
| `10.10.10.128/26` | `.129` – `.190` | `10.10.10.191` |
| `10.10.10.192/26` | `.193` – `.254` | `10.10.10.255` |

`10.10.10.130` tombe dans le **troisième** bloc, `10.10.10.128/26`.

```bash
python3 -c 'import ipaddress as i
[print(s, list(s.hosts())[0], list(s.hosts())[-1], s.broadcast_address)
 for s in i.ip_network("10.10.10.0/24").subnets(new_prefix=26)]'
```

> [!NOTE]
> **Pourquoi**
>
> La règle : pour obtenir `2^n` sous-réseaux, on emprunte `n` bits au champ hôte.
> 4 sous-réseaux → 2 bits → `/24 + 2 = /26`. 8 sous-réseaux → 3 bits → `/27`.
>
> Le coût est réel et se calcule : découper un `/24` (254 hôtes) en quatre `/26`
> donne `4 × 62 = 248` hôtes utilisables. On a **perdu 6 adresses**, parce que
> chaque sous-réseau consomme sa propre paire réseau/diffusion. Plus on découpe
> fin, plus on perd : seize `/28` ne laissent que `16 × 14 = 224` adresses.
>
> C'est l'argument à avoir en tête quand on discute segmentation : la
> micro-segmentation a un prix en adresses, et sur un `/24` unique elle sature
> vite. Sur du `10.0.0.0/8`, le prix est négligeable — d'où l'usage massif de cette
> plage en interne.

---

<a id="e12-7"></a>**[E12.7](README.md#e12-7)** — *Route statique à chaud, vérification, suppression.*

```bash
sudo ip r add 10.10.20.0/24 via 10.10.10.1 dev ens18
ip r | grep 10.10.20
ip route get 10.10.20.7
sudo ip r del 10.10.20.0/24
ip r | grep -c 10.10.20        # doit afficher 0
```

```console
$ ip r | grep 10.10.20
10.10.20.0/24 via 10.10.10.1 dev ens18
$ ip route get 10.10.20.7
10.10.20.7 via 10.10.10.1 dev ens18 src 10.10.10.10 uid 1000
    cache
```

> [!NOTE]
> **Pourquoi**
>
> Deux niveaux de vérification à distinguer, et c'est l'objet de l'exercice.
> `ip r | grep` prouve que **l'entrée existe** dans la table. `ip route get` prouve
> qu'elle est **effectivement sélectionnée** pour la destination visée — ce qui est
> une autre affirmation, car une route plus spécifique, une règle `ip rule` ou une
> métrique plus basse pourraient la supplanter.
>
> Sur `ip r del`, le préfixe suffit dans le cas simple. S'il existe plusieurs
> routes vers le même préfixe (multipath, métriques différentes), il faut
> désigner celle qu'on veut : `ip r del 10.10.20.0/24 via 10.10.10.1 metric 100`.
> Sinon le noyau supprime la première correspondance, qui n'est pas forcément la
> bonne.
>
> Enfin `ip r flush cache` n'existe plus utilement depuis le noyau 3.6 : le cache
> de routage global a été supprimé. La mention `cache` de `ip route get` n'est qu' un
> marqueur de route calculée, pas une table à vider. Les commandes de « vidage du cache de
> routage » qui circulent encore sur les forums ne font rien.

---

<a id="e12-8"></a>**[E12.8](README.md#e12-8)** — *Sockets TCP IPv4 en écoute, avec processus, sans résolution.*

```bash
sudo ss -4 -tlpn
```

```console
$ sudo ss -4 -tlpn
State  Recv-Q Send-Q Local Address:Port Peer Address:Port Process
LISTEN 0      511      0.0.0.0:80      0.0.0.0:*  users:(("nginx",pid=744))
LISTEN 0      5      127.0.0.1:8099    0.0.0.0:*  users:(("python3",pid=912))
LISTEN 0      128      0.0.0.0:22      0.0.0.0:*  users:(("sshd",pid=701))
```

Exposés depuis l'extérieur : ceux liés à `0.0.0.0` ou à `10.10.10.11`, donc 80
et 22. Le 8099 sur `127.0.0.1` ne l'est pas.

```bash
sudo ss -4 -tlpn | awk 'NR>1 && $4 !~ /^127\./ {print}'
```

> [!NOTE]
> **Pourquoi**
>
> Décomposition des options : `-4` famille IPv4, `-t` TCP, `-l` en écoute (LISTEN)
> uniquement, `-p` processus propriétaire (nécessite `sudo`, sinon la colonne est
> vide sans erreur), `-n` numérique.
>
> Ce qu'il faut savoir lire dans cette sortie au-delà du port :
>
> * **`Local Address`** : `0.0.0.0` = toutes les interfaces, `127.0.0.1` = boucle
>   seule, `10.10.10.11` = cette interface seulement. C'est la colonne qui décide
>   de l'accessibilité, pas le port.
> * **`Send-Q`** sur une ligne `LISTEN` ne contient pas des octets en attente :
>   c'est la **taille de la file d'accept**, c'est-à-dire le `backlog` effectif
>   (`min(backlog demandé par listen(), net.core.somaxconn)`). nginx demande 511,
>   il l'obtient ; le serveur Python (`http.server`) ne demande que 5, valeur par défaut de `socketserver` : une file minuscule, à
>   surveiller sous charge.
> * **`Recv-Q`** sur `LISTEN` : le nombre de connexions **en attente d'accept**.
>   Une valeur durablement non nulle signale une application qui n'accepte pas
>   assez vite, et annonce des `SYN` jetés.
>
> Sans `sudo`, tu vois les sockets mais pas le nom des processus des autres
> utilisateurs : c'est la cause du « `ss -tulpn` ne montre rien dans la colonne
> Process » qui revient sans cesse.

---

<a id="e12-9"></a>**[E12.9](README.md#e12-9)** — *50 requêtes, puis comptage par état.*

```bash
for i in $(seq 50); do curl -s -o /dev/null http://10.10.10.11/; done
ss -tan | awk 'NR>1 {print $1}' | sort | uniq -c | sort -rn
ss -s
```

```console
$ ss -tan | awk 'NR>1 {print $1}' | sort | uniq -c | sort -rn
     50 TIME-WAIT
      3 ESTAB
      2 LISTEN
```

Les 50 `TIME-WAIT` sont **côté client** (`lab-adm`) : c'est `curl` qui ferme la
connexion en premier, donc qui exécute la fermeture active.

> [!NOTE]
> **Pourquoi**
>
> L'expérience rend visible ce que le QCM énonce. `curl` sans keep-alive ouvre une
> connexion, la ferme, recommence. Chaque fermeture laisse un `TIME-WAIT` de 60 s
> côté client. Serveur : rien, ou presque — il subit la fermeture, passe par
> `CLOSE-WAIT` et `LAST-ACK` en quelques millisecondes.
>
> Pour le vérifier des deux côtés en même temps, sur `lab-web` :
>
> ```bash
> watch -n1 "ss -tan state time-wait | wc -l; ss -tan state close-wait | wc -l"
> ```
>
> Et pour voir l'effet du keep-alive, qui est la vraie leçon opérationnelle :
>
> ```bash
> # 50 requêtes sur UNE connexion réutilisée
> curl -s -o /dev/null http://10.10.10.11/{1..50} 2>/dev/null
> ss -tan state time-wait | wc -l     # une seule, au lieu de 50
> ```
>
> C'est exactement ce que fait un client HTTP correctement configuré (pool de
> connexions, `Connection: keep-alive`), et c'est pourquoi le réglage de
> `tcp_tw_reuse` arrive **après** la question « pourquoi mon application ouvre-t-elle
> une connexion par requête ? ».
>
> Note pratique : `ss -s` donne un résumé instantané, mais son compteur `timewait`
> inclut les sockets de toutes les familles. Pour un comptage exact,
> `ss -tan state time-wait | wc -l` (moins la ligne d'en-tête si présente).

---

<a id="e12-10"></a>**[E12.10](README.md#e12-10)** — *Deux commandes pour identifier le propriétaire du port 8099.*

```bash
sudo ss -tlpn 'sport = :8099'
sudo lsof -i :8099 -P -n
```

```console
$ sudo ss -tlpn 'sport = :8099'
State  Recv-Q Send-Q Local Address:Port Peer Address:Port Process
LISTEN 0      5      127.0.0.1:8099    0.0.0.0:*  users:(("python3",pid=912))

$ sudo lsof -i :8099 -P -n
COMMAND PID     USER FD TYPE DEVICE SIZE/OFF NODE NAME
python3 912 factura  3u IPv4  28451      0t0  TCP 127.0.0.1:8099 (LISTEN)
```

Compléments : `ps -p 912 -o pid,user,cmd`, `readlink /proc/912/exe`,
`systemctl status 912` (remonte à l'unité systemd).

> [!NOTE]
> **Pourquoi**
>
> `ss` et `lsof` partent de deux bouts opposés. `ss` interroge netlink : il part du
> **socket** et remonte au processus. `lsof` parcourt `/proc/*/fd` : il part des
> **descripteurs de fichiers** et redescend vers les sockets. D'où deux
> informations complémentaires : `ss` donne le `fd` et l'état du socket, `lsof`
> donne l'utilisateur effectif du processus, ce que `ss` n'affiche pas.
>
> Sur une machine chargée, `ss` est un ordre de grandeur plus rapide et sait
> filtrer côté noyau (`sport = :8099`), là où `lsof` doit tout parcourir.
>
> La commande qui manque souvent au raisonnement est la troisième :
>
> ```console
> $ systemctl status 912
> ● factura-api.service - Factura API (lab12)
>      Loaded: loaded (/etc/systemd/system/factura-api.service; enabled)
>      Active: active (running) since ...
> ```
>
> Elle fait le pont entre « un processus écoute » et « voilà l'unité qui l'a
> démarré, donc le fichier à modifier ». Sans elle, on trouve le PID et on ne sait
> toujours pas où changer la configuration.
>
> Note : `readlink /proc/<PID>/exe` reste la seule façon fiable d'obtenir le
> binaire réellement exécuté — `ps` affiche `argv[0]`, qu'un programme peut
> réécrire à sa guise.

---

<a id="e12-11"></a>**[E12.11](README.md#e12-11)** — *`dig` : valeur brute, serveur explicite, TTL, résolution inverse.*

```bash
dig +short lab-web.lab.local                 # valeur brute
dig @10.10.10.10 lab-web.lab.local           # serveur explicite
dig lab-web.lab.local | grep -A1 'ANSWER SEC' ; sleep 5
dig lab-web.lab.local | grep -A1 'ANSWER SEC'   # TTL plus bas
dig -x 10.10.10.11 +short                    # résolution inverse
```

```console
$ dig +short lab-web.lab.local
10.10.10.11
$ dig -x 10.10.10.11 +short
lab-web.lab.local.
```

Entre deux requêtes, le TTL **décroît** : la réponse vient du cache du résolveur,
qui décompte le temps restant. La deuxième requête n'est jamais partie sur le
réseau.

> [!NOTE]
> **Pourquoi**
>
> `+short` ne donne que les données de la section `ANSWER` : c'est la forme
> scriptable, mais elle **cache le `status`**. Un `NXDOMAIN` et un `NOERROR` avec
> zéro réponse donnent tous deux une sortie vide. En script, teste le code de
> retour de `dig` ou utilise `+noall +answer`.
>
> `@10.10.10.10` contourne complètement `/etc/resolv.conf` et donc le stub
> `systemd-resolved`. C'est la commande qui prouve qu'un serveur donné détient bien
> la bonne information, indépendamment de ce que le résolveur local raconte.
>
> `dig -x 10.10.10.11` construit en réalité une requête `PTR` sur
> `11.10.10.10.in-addr.arpa.` — octets inversés, suffixe spécial. Le `-x` fait
> juste la conversion. Point important : le sens inverse est une **zone séparée**,
> qui n'est pas automatiquement cohérente avec le sens direct. Un `A` correct avec
> un `PTR` absent ou contradictoire est une situation courante, et elle casse
> concrètement certaines applications : vérification de courrier électronique,
> journaux de serveurs, authentifications qui font une résolution croisée.
>
> Le TTL est le seul indicateur fiable de cache dans une sortie `dig` : une valeur
> qui décroît entre deux requêtes prouve qu'on lit un cache. Pour l'écarter :
> `dig +nocache` n'existe pas, mais `@serveur-autoritaire` ou
> `resolvectl flush-caches` font le travail.

---

<a id="e12-12"></a>**[E12.12](README.md#e12-12)** — *Types d'enregistrements et délégation.*

```bash
dig +short CNAME www.lab.local
dig +short MX lab.local
dig +short TXT lab.local
dig +short SRV _http._tcp.lab.local
dig +trace www.iana.org            # délégation depuis la racine
```

```console
$ dig +short CNAME www.lab.local
lab-web.lab.local.
$ dig +short MX lab.local
10 lab-adm.lab.local.
$ dig +short TXT lab.local
"v=spf1 ip4:10.10.10.0/24 -all"
$ dig +short SRV _http._tcp.lab.local
10 10 80 lab-web.lab.local.
```

> [!NOTE]
> **Pourquoi**
>
> Lecture des formats, qui sont tous de la forme « priorité puis cible » :
>
> * `MX` : `10 lab-adm.lab.local.` → priorité 10 (plus bas = préféré), serveur de
>   courrier. Plusieurs `MX` de priorités différentes = repli.
> * `SRV` : `10 10 80 lab-web.lab.local.` → priorité, poids, **port**, cible. C'est
>   le seul type qui publie un numéro de port : c'est ce qui permet la découverte
>   de services (Kerberos, LDAP, SIP, contrôleurs de domaine).
> * `TXT` : texte libre, usage conventionnel (SPF, DKIM, validation de propriété
>   de domaine).
> * `CNAME` : alias. Contrainte forte à connaître : un nom qui porte un `CNAME` ne
>   peut porter **aucun autre enregistrement**. C'est pourquoi on ne met jamais de
>   `CNAME` à l'apex d'un domaine (`lab.local` lui-même), qui doit porter `SOA` et
>   `NS`.
>
> `+trace` désactive la récursion et interroge lui-même, de proche en proche : les
> serveurs racine, puis les serveurs du TLD, puis ceux de la zone. On voit la
> **chaîne de délégation** complète, avec les `NS` à chaque étage. C'est l'outil
> pour diagnostiquer une délégation cassée ou un `NS` obsolète — et c'est ce qui
> distingue un candidat qui a déjà réellement débogué du DNS.
>
> `+trace` ne fonctionne pas sur `lab.local` : la zone est locale à `dnsmasq`, elle
> n'est déléguée depuis aucune racine. C'est normal, et c'est justement une bonne
> illustration de la différence entre une zone interne et une zone publique.

---

<a id="e12-13"></a>**[E12.13](README.md#e12-13)** — *Diagnostic `curl` : code + temps, en-têtes, vhost.*

```bash
curl -s -o /dev/null -w '%{http_code} %{time_total}\n' http://10.10.10.11/
curl -sI http://10.10.10.11/
curl -s -o /dev/null -w '%{http_code}\n' \
  --resolve shop.lab.local:80:10.10.10.11 http://shop.lab.local/
```

```console
$ curl -s -o /dev/null -w '%{http_code} %{time_total}\n' http://10.10.10.11/
200 0.004775
$ curl -sI http://10.10.10.11/
HTTP/1.1 200 OK
Server: nginx/1.24.0 (Ubuntu)
Content-Type: text/html
Content-Length: 612
```

> [!NOTE]
> **Pourquoi**
>
> La combinaison `-s -o /dev/null -w` est la forme canonique du test automatisé :
> `-s` supprime la barre de progression, `-o /dev/null` jette le corps, `-w`
> n'imprime que ce qu'on demande. Une ligne, analysable, sans bruit.
>
> Les variables `-w` qui servent vraiment, et ce qu'elles isolent :
>
> | Variable | Mesure |
> |---|---|
> | `%{http_code}` | code de statut HTTP |
> | `%{time_namelookup}` | fin de la résolution DNS |
> | `%{time_connect}` | fin de la poignée de main TCP |
> | `%{time_appconnect}` | fin du handshake TLS |
> | `%{time_starttransfer}` | premier octet de réponse (TTFB) |
> | `%{time_total}` | total |
> | `%{remote_ip}` | adresse réellement contactée |
>
> Ces temps sont **cumulatifs** : les différences successives donnent la durée de
> chaque phase. Un `time_namelookup` à 5 s avec un `time_total` à 5,01 s désigne le
> DNS sans ambiguïté ; un `time_starttransfer` très supérieur à `time_connect`
> désigne l'application. C'est le moyen le plus rapide de répondre à « le site est
> lent » avec un chiffre par étage.
>
> `-I` envoie un `HEAD` : en-têtes seuls, pas de corps. Attention, certains
> serveurs et beaucoup d'API traitent `HEAD` différemment de `GET` (ou le
> refusent) ; en cas de doute, `curl -s -D - -o /dev/null` fait un vrai `GET` en
> n'affichant que les en-têtes.

---

<a id="e12-14"></a>**[E12.14](README.md#e12-14)** — *Test de plusieurs ports TCP, port fermé contre port filtré.*

```bash
for p in 22 80 443 8099; do
  nc -z -w2 10.10.10.11 "$p" && echo "$p ouvert" || echo "$p KO"
done
# ou en une commande : nc (openbsd) accepte une liste ou une plage (22-80)
nc -zv -w2 10.10.10.11 22 80 443 8099
```

```console
$ nc -zv 127.0.0.1 8099
Connection to 127.0.0.1 8099 port [tcp/*] succeeded!
$ nc -zv 127.0.0.1 8098
nc: connect to 127.0.0.1 port 8098 (tcp) failed: Connection refused
```

| Comportement | Ce que ça signifie |
|---|---|
| succès immédiat | `SYN-ACK` : un socket écoute |
| `Connection refused` immédiat | `RST` : personne n'écoute, mais l'hôte répond |
| aucune réponse jusqu'au timeout | paquet jeté en silence (`DROP`) ou hôte muet |

> [!NOTE]
> **Pourquoi**
>
> La distinction **refusé** / **filtré** est le cœur de l'exercice, et elle se lit
> au **délai**, pas au message.
>
> Un `RST` immédiat est une réponse : la machine existe, elle est joignable, la
> pile TCP fonctionne, simplement rien n'écoute sur ce port. Le problème est donc
> le **service**, pas le réseau.
>
> Un silence jusqu'au timeout signifie que le `SYN` est parti et que rien n'est
> revenu : soit un filtrage en `DROP` (le mode par défaut d'un pare-feu bien
> configuré), soit une machine éteinte, soit une route de retour absente. Le
> problème est le **chemin**, pas le service.
>
> `-w2` limite l'attente à 2 secondes : sans lui, un port filtré fait attendre le
> timeout TCP complet, plusieurs dizaines de secondes (`tcp_syn_retries`, 6 par
> défaut, donne environ 130 s).
>
> Les alternatives quand `nc` n'est pas installé — et c'est fréquent sur un serveur
> minimal :
>
> ```bash
> timeout 2 bash -c '</dev/tcp/10.10.10.11/443' && echo ouvert || echo KO
> curl -s -o /dev/null --connect-timeout 2 telnet://10.10.10.11:443
> ```
>
> La première n'utilise que bash (`/dev/tcp` est une fonctionnalité du shell, pas
> un vrai fichier). `telnet`, lui, est obsolète comme client de test : pas de
> timeout réglable, sortie difficile (`Ctrl-]` puis `quit`), et absent par défaut.
> Son seul avantage résiduel est de permettre de taper un protocole texte à la
> main, ce que `nc` fait aussi bien.

---

<a id="e12-15"></a>**[E12.15](README.md#e12-15)** — *Capturer 20 paquets HTTP et identifier la poignée de main.*

Terminal 1 :

```bash
sudo tcpdump -i ens18 -nn -c 20 -w /srv/captures/e15.pcap \
  'host 10.10.10.11 and tcp port 80'
```

Terminal 2 :

```bash
curl -s -o /dev/null http://10.10.10.11/
```

Relecture :

```bash
sudo tcpdump -nn -r /srv/captures/e15.pcap | head -5
```

```console
$ sudo tcpdump -nn -r /srv/captures/e15.pcap | head -5
10:14:02.118 IP 10.10.10.10.51234 > 10.10.10.11.80: Flags [S],
    seq 1829461201, win 64240, length 0
10:14:02.119 IP 10.10.10.11.80 > 10.10.10.10.51234: Flags [S.],
 seq 3471028311, ack 1829461202, win 65160, length 0
10:14:02.119 IP 10.10.10.10.51234 > 10.10.10.11.80: Flags [.],
    ack 1, win 502, length 0
10:14:02.119 IP 10.10.10.10.51234 > 10.10.10.11.80: Flags [P.],
    seq 1:78, ack 1, length 77: HTTP: GET / HTTP/1.1
10:14:02.120 IP 10.10.10.11.80 > 10.10.10.10.51234: Flags [P.],
    seq 1:850, ack 78, length 849: HTTP: HTTP/1.1 200 OK
```

Poignée de main = les trois premières lignes : `[S]`, `[S.]`, `[.]`.

> [!NOTE]
> **Pourquoi**
>
> Le codage des drapeaux dans `tcpdump` est compact et se lit sans hésitation une
> fois qu'on a compris que le **point représente `ACK`** :
>
> | Notation | Drapeaux | Rôle |
> |---|---|---|
> | `[S]` | SYN | demande d'ouverture |
> | `[S.]` | SYN, ACK | acceptation |
> | `[.]` | ACK seul | acquittement, fin de la poignée |
> | `[P.]` | PSH, ACK | données utiles |
> | `[F.]` | FIN, ACK | fermeture ordonnée |
> | `[R]` / `[R.]` | RST | rejet brutal |
>
> Deux détails de la sortie qui servent en diagnostic réel :
>
> * les numéros de séquence sont **relatifs** par défaut (le premier vaut 1) :
>   c'est plus lisible, mais `-S` donne les valeurs absolues quand on veut
>   corréler avec une autre capture.
> * `length 0` sur un `[.]` confirme un acquittement pur, sans donnée.
>
> Un `[R]` juste après un `[S]` est la signature exacte du « connexion refusée » :
> c'est ce que voit `curl` quand il renvoie le code 7. Une répétition de `[S]`
> sans réponse, toutes les 1, 2, 4, 8 secondes (repli exponentiel), est la
> signature du filtrage `DROP`. Ces deux motifs se reconnaissent d'un coup d'œil
> et remplacent dix minutes de raisonnement.
>
> Sur l'écriture : avec `-w`, `tcpdump` n'affiche rien à l'écran — c'est normal,
> il écrit en binaire. Ajouter `--print` pour avoir les deux. Et le fichier
> appartient à root : `chown` ou `-Z <user>` pour pouvoir le relire ensuite sans
> privilèges.

---

<a id="e12-16"></a>**[E12.16](README.md#e12-16)** — *MTU du chemin par dichotomie.*

```bash
ping -M do -s 1472 -c 2 10.10.10.11     # 1472 + 8 + 20 = 1500 -> passe
ping -M do -s 1473 -c 2 10.10.10.11     # -> message too long, mtu=1500
ip link show ens18 | grep -o 'mtu [0-9]*'
```

```console
$ ping -M do -s 1473 -c 2 10.10.10.11
PING 10.10.10.11 (10.10.10.11) 1473(1501) bytes of data.
ping: local error: message too long, mtu=1500
--- 10.10.10.11 ping statistics ---
2 packets transmitted, 0 received, +2 errors, 100% packet loss
```

MTU du chemin = `1472 + 8 (en-tête ICMP) + 20 (en-tête IP) = 1500`, cohérent
avec le MTU de l'interface.

> [!NOTE]
> **Pourquoi**
>
> Le calcul, à ne jamais confondre : `-s` désigne la taille des **données ICMP**,
> pas celle du paquet. Il faut ajouter 8 octets d'en-tête ICMP et 20 d'en-tête IP.
> D'où la règle : `MTU = valeur de -s + 28`.
>
> `-M do` positionne le bit DF (Don't Fragment). Sans lui, le noyau fragmente
> gentiment et le test ne prouve rien. Les trois modes : `do` (ne jamais
> fragmenter), `want` (fragmenter si besoin, défaut), `dont` (ignorer la découverte
> de MTU).
>
> Deux messages d'erreur différents, et la différence est diagnostique :
>
> * `local error: message too long, mtu=1500` : c'est **ta propre pile** qui
>   refuse, parce que le paquet dépasse le MTU de ton interface de sortie. Le
>   paquet n'est jamais parti.
> * `From 10.10.10.1 icmp_seq=1 Frag needed and DF set (mtu = 1450)` : un routeur
>   **en chemin** a jeté le paquet et te l'a dit, en donnant le MTU utilisable.
>   C'est la découverte de MTU de chemin qui fonctionne correctement.
>
> Le cas pathologique est le troisième : **aucun message**, 100 % de perte, timeout
> silencieux. C'est le trou noir PMTUD, et c'est exactement ce que la dichotomie
> sert à caractériser.
>
> Plus rapide que la dichotomie manuelle :
>
> ```bash
> tracepath 10.10.10.11        # affiche « pmtu 1500 » et le saut où il change
> ```
>
> `tracepath` fait la découverte automatiquement, sans privilèges, et indique à
> quel saut le MTU se réduit. C'est l'outil à dégainer en premier ; la dichotomie
> `ping -M do` reste utile pour prouver un point précis ou quand `tracepath` est
> absent.

---

## 12.6 Labs

### <a id="l12-1"></a>**[L12.1](README.md#l12-1)** — Plan d'adressage et manipulation à chaud

*Découper `10.10.10.0/24`, proposer une DMZ, tester à chaud, nettoyer.*

**Étape 1 — les quatre sous-réseaux**

| Segment | Préfixe | Utilisables | Diffusion |
|---|---|---|---|
| 1 administration | `10.10.10.0/26` | `.1` – `.62` | `.63` |
| 2 applicatif | `10.10.10.64/26` | `.65` – `.126` | `.127` |
| 3 bases | `10.10.10.128/26` | `.129` – `.190` | `.191` |
| 4 réserve | `10.10.10.192/26` | `.193` – `.254` | `.255` |

Masque commun : `255.255.255.192`. 62 hôtes par segment, 248 au total (contre
254 avant découpage : six adresses perdues en frontières).

**Étape 2 — placement des VM**

| VM | IP actuelle | Segment cible | Verdict |
|---|---|---|---|
| `lab-adm` | 10.10.10.10 | 1 administration | conforme |
| `lab-web` | 10.10.10.11 | 2 applicatif | **à renuméroter** (→ .65) |
| `lab-db` | 10.10.10.12 | 3 bases | **à renuméroter** (→ .129) |
| `lab-rhel` | 10.10.10.13 | 1 administration | conforme |
| `lab-ops` | 10.10.10.14 | 2 applicatif | **à renuméroter** (→ .66) |
| `lab-git` | 10.10.10.15 | 2 applicatif | **à renuméroter** (→.67) |
| `lab-virt` | 10.10.10.16 | 1 administration | conforme |

**Étape 3 — DMZ de 62 hôtes**

62 hôtes → `/26`. Hors de `10.10.10.0/24`, dans `10.10.0.0/16` : par exemple
`10.10.50.0/26` (utilisables `.1` à `.62`, diffusion `.63`).

Preuve d'absence de chevauchement :

```bash
python3 -c 'import ipaddress as i
a=i.ip_network("10.10.10.0/24"); b=i.ip_network("10.10.50.0/26")
print("chevauchement:", a.overlaps(b))'
```

**Étapes 4 à 6 — manipulation à chaud**

```bash
sudo ip a add 10.10.20.10/24 dev ens18
sudo ip r add 10.10.30.0/24 via 10.10.10.1 dev ens18

ip route get 10.10.30.5      # via 10.10.10.1, src 10.10.10.10
ip route get 10.10.20.99     # direct dev ens18, src 10.10.20.10
ip route get 9.9.9.9         # via 10.10.10.1, src 10.10.10.10

sudo ip r del 10.10.30.0/24
sudo ip a del 10.10.20.10/24 dev ens18
ip -br a show dev ens18 && ip r      # preuve du nettoyage
```

> [!NOTE]
> **Pourquoi**
>
> Les trois `ip route get` de l'étape 5 illustrent les trois cas de figure du
> routage, et c'est tout l'intérêt de les faire à la suite.
>
> `10.10.30.5` : route statique explicite, donc `via 10.10.10.1`. Mais la source
> reste `10.10.10.10`, car elle est déterminée par l'**adresse de l'interface de
> sortie** sur le réseau de la passerelle, pas par la destination.
>
> `10.10.20.99` : dès qu'on ajoute `10.10.20.10/24`, le noyau crée automatiquement
> la route `10.10.20.0/24 dev ens18 proto kernel scope link src 10.10.20.10`. La
> destination est donc directement connectée : pas de `via`, et la source est
> `10.10.20.10`. On voit ici que **configurer une adresse configure aussi une
> route** — c'est le `proto kernel`.
>
> `9.9.9.9` : aucune route spécifique, la route par défaut s'applique.
>
> Sur le nettoyage : supprimer l'adresse `10.10.20.10/24` supprime **aussi**
> automatiquement la route `proto kernel` associée. Le noyau garde la cohérence
> entre adresses et routes connectées. En revanche, la route statique `10.10.30.0/24`
> doit être supprimée explicitement : elle a été posée par toi, elle ne dépend
> d'aucune adresse.

> [!WARNING]
> **Piège**
>
> Renuméroter `lab-web` de `.11` vers `.65` (et de même `lab-db`, `lab-ops`, `lab-git`) n'est pas une opération anodine : tout
> ce qui référence l'ancienne IP casse — `/etc/hosts` des autres machines, zone
> DNS, configurations de reverse proxy, règles de pare-feu, chaînes de connexion
> applicatives. C'est pourquoi un plan d'adressage se décide **avant** le
> déploiement. Sur un parc existant, on renumérote par lots avec une fenêtre, en
> s'appuyant sur les noms DNS et jamais sur les IP en dur. La bonne réponse au
> point 2 n'est pas seulement « ces quatre VM changent d'IP », c'est « et voici
> l'impact et l'ordre des opérations ».

---

### <a id="l12-2"></a>**[L12.2](README.md#l12-2)** — La même configuration, trois fois

*Netplan sur Ubuntu, `nmcli` sur Rocky, `/etc/network/interfaces` en héritage.*

**Étape 1 — Netplan sur `lab-adm`**

```yaml
# /etc/netplan/01-lab.yaml   (mode 0600, root:root)
network:
  version: 2
  renderer: networkd
  ethernets:
    ens18:
      dhcp4: false
      dhcp6: false
      addresses:
        - 10.10.10.10/24
        - 10.10.20.10/24
      routes:
        - to: default
          via: 10.10.10.1
          metric: 100
      nameservers:
        addresses: [10.10.10.10, 9.9.9.9]
        search: [lab.local]
```

```bash
sudo chmod 600 /etc/netplan/01-lab.yaml
sudo netplan generate          # valide la syntaxe, écrit /run/systemd/network/
sudo netplan try               # applique avec rollback à 120 s
```

**Étape 3 — trois vues de vérification**

```bash
sudo netplan get                       # vue Netplan : conf fusionnée
ip -br a && ip r && resolvectl status  # vue noyau + résolveur
networkctl status ens18                # vue systemd-networkd
```

**Étape 4 — fichiers pris en compte**

```bash
ls -l /etc/netplan/
```

Tous les `*.yaml` de `/etc/netplan/` sont lus par ordre **lexicographique** et
**fusionnés**. En cas de clé identique, le dernier lu gagne : `50-cloud-init.yaml`
l'emporte sur `01-lab.yaml`. Neutralisation de cloud-init :

```bash
echo 'network: {config: disabled}' | \
  sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
sudo rm /etc/netplan/50-cloud-init.yaml
```

**Étape 5 — la même chose sur `lab-rhel` (Rocky 9)**

```bash
sudo nmcli con mod lab-ens18 \
  ipv4.method manual \
  ipv4.addresses "10.10.10.13/24,10.10.20.13/24" \
  ipv4.gateway 10.10.10.1 \
  ipv4.dns "10.10.10.10 9.9.9.9" \
  ipv4.dns-search lab.local \
  ipv6.method disabled
sudo nmcli con up lab-ens18
nmcli -p con show lab-ens18 | head -20
sudo ls -l /etc/NetworkManager/system-connections/lab-ens18.nmconnection
```

Le fichier généré (mode `0600`, sinon NetworkManager l'ignore) :

```ini
[connection]
id=lab-ens18
type=ethernet
interface-name=ens18

[ipv4]
method=manual
address1=10.10.10.13/24,10.10.10.1
address2=10.10.20.13/24
dns=10.10.10.10;9.9.9.9;
dns-search=lab.local;
```

**Étape 6 — équivalent `/etc/network/interfaces`**

```ini
auto ens18
iface ens18 inet static
    address 10.10.10.10/24
    gateway 10.10.10.1
    dns-nameservers 10.10.10.10 9.9.9.9
    dns-search lab.local

auto ens18:0
iface ens18:0 inet static
    address 10.10.20.10/24
```

Activation / désactivation : `ifup ens18` / `ifdown ens18`, ou
`systemctl restart networking`.

**Étape 7 — identifier le gestionnaire actif**

```bash
ls /etc/netplan/*.yaml 2>/dev/null && echo "-> Netplan"
systemctl is-active NetworkManager systemd-networkd networking
nmcli dev status 2>/dev/null
```

> [!NOTE]
> **Pourquoi**
>
> Le point à comprendre, et il est structurant : **Netplan ne configure rien**.
> C'est un générateur. `netplan generate` traduit le YAML en fichiers
> `systemd-networkd` dans `/run/systemd/network/` (ou en connexions NetworkManager
> selon le `renderer`), puis `netplan apply` déclenche la relecture par le démon.
>
> Trois conséquences concrètes :
>
> 1. Éditer `/etc/systemd/network/*.network` sur Ubuntu est inutile : le prochain
>    `netplan apply` régénère par-dessus. On édite le YAML, toujours.
> 2. `netplan get` affiche la configuration **fusionnée** de tous les fichiers, qui
>    ne correspond au contenu d'aucun fichier pris isolément. C'est la vue à
>    utiliser pour savoir ce qui sera réellement appliqué.
> 3. Une erreur de syntaxe est détectée par `netplan generate`, avant toute
>    application. C'est la commande à lancer systématiquement en premier.
>
> Sur les droits : depuis Ubuntu 23.10, Netplan avertit que les fichiers ne doivent
> pas être lisibles par tous, parce qu'ils peuvent contenir des secrets (clés
> WPA, mots de passe de tunnel). `chmod 600` supprime l'avertissement et ferme une
> vraie fuite d'information. Même logique côté NetworkManager, qui **refuse** de
> charger un keyfile dont les droits sont trop ouverts.
>
> Le `ens18:0` de `/etc/network/interfaces` est un vestige : le noyau ne connaît
> pas les alias d'interface. `ip a` montrera une seule interface `ens18` portant
> deux adresses. La notation `:0` n'existe que dans `ifupdown`, et c'est
> exactement ce qu'`iproute2` a rendu obsolète.

> [!WARNING]
> **Piège**
>
> La double configuration est l'incident classique de ce lab : Netplan **et** un
> `/etc/network/interfaces` non vide avec `networking.service` actif. Chacun pose
> son adresse, chacun pose sa route par défaut. Résultat : deux `default` dans
> `ip r`, sélection imprévisible, comportement qui change après chaque redémarrage.
> La commande qui le révèle en une ligne : `ip r | grep -c '^default'`. Si le
> résultat est supérieur à 1 sans configuration multi-lien voulue, tu tiens ta
> panne.

---

### <a id="l12-3"></a>**[L12.3](README.md#l12-3)** — Ticket INC-3307 : « le nouveau site répond par intermittence »

*Rétablir la vérité dans la chaîne de résolution.*

**Étape 1 — la réponse faisant autorité**

```bash
dig @10.10.10.10 www.lab.local
```

```console
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 51204
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 2, AUTHORITY: 0, ADDITIONAL: 1

;; ANSWER SECTION:
www.lab.local.       300 IN CNAME lab-web.lab.local.
lab-web.lab.local.   300 IN A     10.10.10.11
```

`CNAME` vers `lab-web.lab.local`, qui vaut `10.10.10.11`. TTL 300 s.
`status: NOERROR`, drapeau `aa` : réponse faisant autorité.

**Étape 2 — comparaison des trois vues**

```bash
getent hosts www.lab.local        # -> 10.10.10.99   (!)
dig +short @10.10.10.10 www.lab.local   # -> 10.10.10.11
resolvectl query www.lab.local          # -> 10.10.10.99, Data from: synthetic
dig +short www.lab.local                # -> 10.10.10.99 (stub 127.0.0.53)
```

Écart : `getent` passe par NSS donc par `/etc/hosts` ; `dig` `@10.10.10.10` interroge le serveur du lab
directement.

`systemd-resolved` lit lui aussi `/etc/hosts` (`ReadEtcHosts=yes`) et le sert en priorité, à `resolvectl` comme à `dig` sans `@` : seul le serveur interrogé explicitement dit la vérité du DNS.

**Étape 3 — l'entrée fautive**

```bash
grep -n lab.local /etc/hosts
grep '^hosts:' /etc/nsswitch.conf
```

```console
$ grep -n lab.local /etc/hosts
12:10.10.10.99   www.lab.local www
$ grep '^hosts:' /etc/nsswitch.conf
hosts:          files dns
```

Démonstration en deux commandes qui divergent :

```bash
getent hosts www.lab.local ; dig +short @10.10.10.10 www.lab.local
```

**Étape 4 — correction**

```bash
sudo cp /etc/hosts /root/.m12-backup/hosts.$(date +%F)
sudo sed -i '/www\.lab\.local/d' /etc/hosts
getent hosts www.lab.local        # -> 10.10.10.11
```

`/etc/hosts` ne doit garder que `127.0.0.1 localhost`, la ligne du nom de la
machine elle-même, et les entrées IPv6 standard.

**Étape 5 — preuve du cache**

```bash
resolvectl query lab-web.lab.local     # noter le TTL et « Data from: »
sleep 10
resolvectl query lab-web.lab.local     # TTL plus bas, cache
sudo resolvectl flush-caches
resolvectl query lab-web.lab.local     # TTL plein, « Data from: network »
resolvectl statistics                  # taux de succès du cache
```

**Étape 6 — domaine de recherche**

```yaml
      nameservers:
        addresses: [10.10.10.10, 9.9.9.9]
        search: [lab.local]
```

```bash
sudo netplan apply
resolvectl status | grep -i 'DNS Domain'
ping -c1 lab-db          # résout lab-db.lab.local
```

`search lab.local` : les noms courts sont complétés par ce suffixe.
`domain lab.local` (syntaxe `resolv.conf` historique) équivaut à un `search`
à un seul élément. `search` accepte plusieurs suffixes, essayés dans l'ordre —
au prix d'une requête par suffixe en cas d'échec, d'où la lenteur quand la liste
est longue et que le nom n'existe pas.

**Étape 7 — inventaire de la zone**

```bash
for h in lab-adm lab-web lab-db lab-rhel lab-ops lab-git lab-virt; do
  printf '%-10s %s\n' "$h" "$(dig +short "$h.lab.local")"
done
dig +short CNAME www.lab.local
dig +short MX    lab.local
dig +short TXT   lab.local
dig +short SRV   _http._tcp.lab.local
dig +short -x    10.10.10.11
```

**Étape 8 — cohabitation `dnsmasq` / `systemd-resolved`**

```bash
sudo ss -ulpn 'sport = :53'
```

```console
State  Recv-Q Send-Q Local Address:Port Peer Address:Port Process
UNCONN 0      0  127.0.0.53%lo:53 0.0.0.0:* users:(("systemd-resolve",pid=620))
UNCONN 0      0     127.0.0.54:53 0.0.0.0:* users:(("systemd-resolve",pid=620))
UNCONN 0      0    10.10.10.10:53 0.0.0.0:* users:(("dnsmasq",pid=1104))
```

Aucun conflit : les deux démons écoutent sur le port 53 mais sur des **adresses
différentes**. `systemd-resolved` est lié à `127.0.0.53`, `dnsmasq` à
`10.10.10.10`, grâce à `bind-interfaces` et `listen-address=10.10.10.10` dans sa
configuration.

> [!NOTE]
> **Pourquoi**
>
> Le mécanisme central du lab : **un socket est lié à un couple (adresse, port)**,
> pas à un port seul. Deux processus peuvent écouter sur le port 53 tant que leurs
> adresses diffèrent. C'est exactement le même principe que celui qui rend
> `127.0.0.1:8099` inaccessible de l'extérieur en BF12.3 — vu sous l'autre angle.
>
> Le piège de `dnsmasq` est son comportement par défaut : sans `bind-interfaces`,
> il utilise `bind-dynamic` ou se lie à `0.0.0.0:53`, ce qui **entre en conflit**
> avec `systemd-resolved` déjà lié à `127.0.0.53:53`. Le service échoue au
> démarrage avec `failed to create listening socket: Address already in use`. Les
> deux directives qui résolvent la cohabitation :
>
> ```ini
> bind-interfaces
> listen-address=10.10.10.10
> ```
>
> Sur le cache : `systemd-resolved` respecte le TTL des enregistrements. Un TTL de
> 300 s signifie qu'une correction DNS peut mettre jusqu'à 5 minutes à se propager
> sur les clients — d'où la pratique d'abaisser le TTL à 60 s **avant** une
> migration planifiée, puis de le remonter après. `resolvectl flush-caches` vide le
> cache local, mais pas ceux des autres machines ni ceux des résolveurs
> intermédiaires.
>
> Dernier point, souvent raté : `resolvectl statistics` donne le taux de succès du
> cache. Un taux très bas sur une machine qui fait beaucoup de requêtes signale des
> TTL trop courts côté zone, ou une application qui contourne le cache.

> [!WARNING]
> **Piège**
>
> Le domaine `lab.local` est mal choisi dans la vraie vie : `.local` est réservé à
> mDNS (Bonjour/Avahi) par la RFC 6762. Sur Ubuntu, la ligne `hosts:` de
> `nsswitch.conf` contient souvent `mdns4_minimal [NOTFOUND=return]` **avant**
> `dns` : pour un nom en `.local`, mDNS répond « inconnu », et le
> `[NOTFOUND=return]` **arrête la recherche** sans jamais interroger le DNS.
> Symptôme : `dig` répond, `ping` non. Le correctif propre est de choisir un
> domaine interne valide (`lab.internal`, ou un sous-domaine d'un domaine qu'on
> possède), pas de bricoler `nsswitch.conf`.

---

### <a id="l12-4"></a>**[L12.4](README.md#l12-4)** — Audit des sockets et lecture des états TCP

*Inventaire, exposition, reverse proxy, états TCP, `sysctl`.*

**Étapes 1 et 2 — inventaire automatisé**

```bash
#!/usr/bin/env bash
# ~/lab12/bin/inventaire-sockets.sh
set -euo pipefail
printf '| Proto | Écoute | Processus | Unité |\n|---|---|---|---|\n'
ss -H -tulpn | while read -r netid _ _ _ local _ proc; do
  pid=$(printf '%s' "$proc" | grep -o 'pid=[0-9]*' | cut -d= -f2 | head -1)
  name=$(printf '%s' "$proc" | sed -n 's/.*(("\([^"]*\)".*/\1/p')
  unit=$(systemctl status "$pid" 2>/dev/null | head -1 |
         awk '{print $2}') || unit='-'
  expo='local'
  case "$local" in
    0.0.0.0:*|'[::]:'*|10.10.10.*) expo='EXPOSÉ' ;;
  esac
  printf '| %s | %s (%s) | %s[%s] | %s |\n' \
    "$netid" "$local" "$expo" "${name:--}" "${pid:--}" "${unit:--}"
done
```

```bash
sudo bash ~/lab12/bin/inventaire-sockets.sh > ~/lab12/rapports/sockets.md
```

Critère d'exposition : l'adresse d'écoute. `0.0.0.0` ou `[::]` = toutes les
interfaces ; `10.10.10.11` = joignable sur le LAN ; `127.0.0.1` ou `[::1]` =
boucle locale uniquement.

**Étape 3 — vérification depuis `lab-adm`**

```bash
for p in 22 80 443 8099; do
  nc -z -w2 10.10.10.11 "$p" ; printf '%s -> rc=%s\n' "$p" "$?"
done
```

Attendu : 22 et 80 → `rc=0` ; 8099 → `rc=1` (`Connection refused`, socket sur
`127.0.0.1`) ; 443 → `rc=1` si aucun TLS n'est configuré.

**Étape 4 — exposer l'API par reverse proxy**

Le bloc `location` va **dans le vhost existant** `lab-web` (celui qui porte `default_server` sur le port 80) : un second `server { listen 80; server_name _; }` ne recevrait jamais les requêtes adressées à `10.10.10.11`, qui tombent sur le `default_server` (404 sur `/api/`).

```nginx
# /etc/nginx/sites-available/lab-web, dans le bloc server existant
location /api/ {
    proxy_pass http://127.0.0.1:8099/;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

```bash
sudoedit /etc/nginx/sites-available/lab-web
sudo nginx -t && sudo systemctl reload nginx
curl -s http://10.10.10.11/api/health        # depuis lab-adm
```

**Étape 5 — états TCP sous charge**

```bash
# sur lab-adm
for i in $(seq 200); do curl -s -o /dev/null http://10.10.10.11/; done
ss -tan | awk 'NR>1{print $1}' | sort | uniq -c | sort -rn
# sur lab-web, en parallèle
watch -n1 'ss -tan | awk "NR>1{print \$1}" | sort | uniq -c'
```

Le **client** accumule les `TIME-WAIT` : c'est `curl` qui ferme en premier.
Le serveur n'en a quasiment pas.

**Étape 6 — provoquer un `CLOSE-WAIT`**

```bash
python3 ~/lab12/bin/mauvais-serveur.py &      # accepte et ne ferme jamais
curl -s --max-time 2 http://127.0.0.1:8100/ || true
ss -tanp state close-wait
```

Ticket à écrire : « le service `mauvais-serveur` conserve les descripteurs de
socket après le `FIN` du client. N sockets en `CLOSE-WAIT`, en croissance
monotone, aucune décroissance observée après 10 minutes. Impact : épuisement de
`LimitNOFILE` puis `accept: Too many open files`. Correctif attendu : appel à
`close()` (ou usage d'un `with`) sur chaque connexion terminée. »

**Étape 7 — `sysctl`**

```bash
sysctl net.core.somaxconn net.ipv4.ip_local_port_range net.ipv4.tcp_tw_reuse
echo 'net.core.somaxconn = 8192' | \
  sudo tee /etc/sysctl.d/90-lab12.conf
sudo sysctl --system
sysctl net.core.somaxconn
```

| Paramètre | Limite | Symptôme si trop bas |
|---|---|---|
| `net.core.somaxconn` | file d'accept | `SYN` jetés, `Recv-Q` élevé en LISTEN |
| `ip_local_port_range` | ports sortants | `Cannot assign requested address` |
| `tcp_tw_reuse` | réemploi des `TIME-WAIT` | idem, sous forte charge sortante |

> [!NOTE]
> **Pourquoi**
>
> Le point 4 est le cœur pédagogique du lab. Pourquoi un reverse proxy plutôt
> qu'un simple changement d'adresse d'écoute vers `0.0.0.0` ?
>
> Parce que `127.0.0.1` n'est pas un accident, c'est souvent une décision de
> conception. Un service applicatif interne n'a ni TLS, ni authentification
> robuste, ni limitation de débit, ni journalisation d'accès exploitable. Le
> mettre directement sur le réseau l'expose tel quel. Le reverse proxy ajoute, en
> un seul point : terminaison TLS, en-têtes de sécurité, limitation de débit,
> journaux d'accès homogènes, filtrage par chemin, et la possibilité de basculer
> le backend sans rien changer côté client.
>
> C'est aussi ce qui explique le `proxy_set_header X-Forwarded-For` : sans lui,
> l'application ne voit plus que `127.0.0.1` comme adresse cliente, et ses journaux
> comme ses limitations par IP deviennent inutiles.
>
> Sur `somaxconn` : la valeur effective du backlog est
> `min(backlog demandé par listen(), net.core.somaxconn)`. Augmenter `somaxconn`
> ne sert à rien si l'application demande 128 — il faut agir des deux côtés
> (`listen 0.0.0.0:80 backlog=8192;` chez nginx, `--backlog` chez gunicorn). Et le
> symptôme d'une file saturée est lisible directement : `Recv-Q` durablement non
> nul sur une ligne `LISTEN` de `ss -tln`.
>
> Un fichier dans `/etc/sysctl.d/` est préférable à l'édition de
> `/etc/sysctl.conf` : il survit aux mises à jour du paquet, il est traçable dans
> la gestion de configuration, et son nom dit à quoi il sert. `sysctl --system`
> relit l'ensemble des répertoires dans l'ordre standard.

> [!WARNING]
> **Piège**
>
> Une ligne `LISTEN` sur `[::]:80` **sans** `0.0.0.0:80` correspondant n'est pas
> forcément un problème : si `net.ipv6.bindv6only=0` (le défaut), le socket IPv6
> accepte aussi les connexions IPv4 via les adresses mappées `::ffff:10.10.10.10`.
> Mais si le paramètre vaut `1`, ou si l'application ouvre explicitement un socket
> `IPV6_V6ONLY`, les clients IPv4 sont refusés alors que `ss` montre bien un
> LISTEN sur le port 80. Symptôme déroutant : « ça écoute, mais ça refuse ».
> Le test qui tranche : `curl -4` contre `curl -6`.

---

### <a id="l12-5"></a>**[L12.5](README.md#l12-5)** — Capture, MTU et bande passante

*Capturer, lire une capture d'incident, mesurer le MTU, mesurer le débit.*

**Étapes 1 et 2 — capture et lecture**

```bash
mkdir -p ~/lab12/captures
sudo tcpdump -i ens18 -nn -w ~/lab12/captures/http.pcap \
  'host 10.10.10.11 and tcp port 80' &
curl -s -o /dev/null http://10.10.10.11/
sudo pkill tcpdump
sudo chown "$USER" ~/lab12/captures/http.pcap
tcpdump -nn -r ~/lab12/captures/http.pcap
```

| Paquet | Drapeaux | Rôle |
|---|---|---|
| 1 | `[S]` | SYN client → serveur |
| 2 | `[S.]` | SYN-ACK serveur → client |
| 3 | `[.]` | ACK client : connexion établie |
| 4 | `[P.]` | `GET / HTTP/1.1` |
| 5 | `[P.]` | `HTTP/1.1 200 OK` + corps |
| 6-8 | `[F.]`, `[.]`, `[F.]` | fermeture ordonnée |

**Étape 3 — analyse de `/srv/captures/incident.pcap`**

```bash
tcpdump -nn -r /srv/captures/incident.pcap
tcpdump -nn -r /srv/captures/incident.pcap 'tcp[tcpflags] & tcp-rst != 0'
tcpdump -nn -r /srv/captures/incident.pcap | awk '{print $3, $5}' | sort -u
```

Conclusion type à écrire dans `capture.md` :

```text
Adresses : 10.10.10.10:<éphémère> -> 10.10.10.11:8199
Tentatives : 5 connexions successives, ports sources différents
Issue : chaque SYN reçoit un RST immédiat (Flags [R.]) du serveur
Délai : < 1 ms entre SYN et RST -> réponse locale, pas de filtrage réseau
Diagnostic : aucun socket en écoute sur 10.10.10.11:8199 (service arrêté,
ou lié à 127.0.0.1 uniquement). Ce n'est pas un problème de pare-feu :
un DROP se traduirait par des SYN répétés sans réponse.
```

**Étape 4 — MTU du chemin**

```bash
ping -M do -s 1472 -c 2 10.10.10.11    # passe
ping -M do -s 1473 -c 2 10.10.10.11    # échoue
ip link show ens18 | grep -o 'mtu [0-9]*'
tracepath 10.10.10.11
```

MTU = 1472 + 28 = **1500**, cohérent avec l'interface.

**Étapes 5 et 6 — simuler un tunnel**

```bash
sudo ip link set dev ens18 mtu 1400
ping -M do -s 1372 -c 2 10.10.10.11    # 1372 + 28 = 1400 -> passe
ping -M do -s 1373 -c 2 10.10.10.11    # -> local error, mtu=1400
curl -s -o /dev/null -w '%{time_total}\n' http://10.10.10.11/gros.bin
sudo ip link set dev ens18 mtu 1500
```

Ici le transfert **fonctionne quand même** : les deux extrémités sont sur le même
segment, la pile locale connaît son MTU et annonce un MSS de 1360. Le blocage du
monde réel survient quand le MTU réduit se trouve **en chemin** et que les ICMP
sont filtrés — l'émetteur n'apprend jamais qu'il doit réduire.

**Étapes 7 et 8 — `iperf3`**

```bash
# sur lab-web
iperf3 -s -D
# sur lab-adm
iperf3 -c 10.10.10.11 -t 10
iperf3 -c 10.10.10.11 -t 10 -P 4
iperf3 -c 10.10.10.11 -t 10 -R
```

```console
[ ID] Interval        Transfer    Bitrate         Retr  Cwnd
[  5] 0.00-10.00 sec  1.09 GBytes  938 Mbits/sec   0    1.18 MBytes
```

Rapport type : débit unique ≈ 938 Mbit/s avec `Retr 0` sur un lien gigabit ; 4
flux parallèles ne dépassent pas ce plafond (le lien est le facteur limitant, pas
la fenêtre) ; sens inverse comparable si le lien est symétrique ; avec MTU 1400,
débit légèrement inférieur (plus de paquets pour le même volume, donc plus
d'interruptions et d'en-têtes).

> [!NOTE]
> **Pourquoi**
>
> Trois mécanismes distincts, à ne pas confondre — c'est tout l'objet du lab.
>
> **Le `RST` de l'étape 3.** Un `RST` en réponse à un `SYN` est une réponse
> **active** : la machine existe, sa pile TCP fonctionne, elle refuse. Le délai
> inférieur à la milliseconde le confirme. Un filtrage en `DROP` produirait tout
> autre chose : des `SYN` répétés à 1, 2, 4, 8 secondes (repli exponentiel de
> `tcp_syn_retries`) et **aucune** réponse. Savoir lire cette différence dans une
> capture, c'est éliminer ou confirmer le pare-feu en dix secondes, sans y toucher.
>
> **Le MTU de l'étape 5.** L'expérience montre volontairement un cas où réduire le
> MTU **ne casse rien**, et c'est le point pédagogique : la pile locale connaît son
> propre MTU et adapte son MSS en conséquence dès le `SYN`. Le problème n'apparaît
> que lorsque la réduction est **en chemin**, invisible des extrémités, et que
> l'ICMP « fragmentation needed » n'arrive pas. On ne peut pas reproduire fidèlement
> un trou noir PMTUD entre deux machines du même segment : il y faut un routeur
> intermédiaire et un filtrage. D'où l'importance de comprendre le mécanisme plutôt
> que de le constater.
>
> **Le débit de l'étape 7.** 938 Mbit/s sur un lien gigabit est le maximum
> théorique atteignable : les en-têtes Ethernet, IP et TCP consomment le reste.
> `Retr 0` signifie aucune perte. Que 4 flux parallèles ne dépassent pas ce chiffre
> prouve que le facteur limitant est le **lien**, pas la fenêtre TCP — sur un lien
> à forte latence, le cumul des flux parallèles dépasserait largement le flux
> unique, et ce serait la signature d'une limitation par le produit
> débit × latence.

> [!WARNING]
> **Piège**
>
> Un `iperf3` entre deux VM du même hyperviseur ne mesure pas un réseau : il mesure
> le bridge logiciel et la vitesse des copies mémoire, souvent plusieurs dizaines
> de Gbit/s. Le chiffre est vrai mais ne dit rien de la production. Et penser à
> arrêter le serveur `iperf3` après le test (`pkill iperf3`) : laissé en écoute sur
> `0.0.0.0:5201`, il apparaîtra comme un socket exposé au prochain audit de
> sécurité — celui de L12.4.

---

## 12.7 Break & Fix

### <a id="bf12-1"></a>**[BF12.1](README.md#bf12-1)** — « Plus d'internet, mais le lab fonctionne »

*Le LAN répond, `ping 9.9.9.9` renvoie `Network is unreachable` instantanément.*

**Démarche de diagnostic**

```bash
# 1. le message est immédiat : la décision vient de la machine elle-même
ping -c1 9.9.9.9
#    -> connect: Network is unreachable

# 2. la table de routage : y a-t-il une route par défaut ?
ip r
#    10.10.10.0/24 dev ens18 proto kernel scope link src 10.10.10.10
#    -> aucune ligne "default"

# 3. confirmation par la commande qui simule un vrai paquet
ip route get 9.9.9.9
#    RTNETLINK answers: Network is unreachable

# 4. et le LAN, lui, fonctionne bien : route connectée présente
ip route get 10.10.10.11
```

**Cause racine** : la route par défaut a été supprimée de la table du noyau
(`ip r del default`). La configuration persistante n'est pas touchée : Netplan
contient toujours la bonne passerelle.

**Correctif immédiat** (session en cours) :

```bash
sudo ip r add default via 10.10.10.1 dev ens18
ping -c2 9.9.9.9
```

**Correctif durable** : vérifier que la configuration persistante est correcte
et la ré-appliquer, ce qui reposera la route au prochain démarrage.

```bash
sudo netplan get ethernets.ens18.routes
sudo netplan generate && sudo netplan apply
ip r | grep '^default'
```

> [!NOTE]
> **Pourquoi**
>
> Toute la démarche tient dans l'**immédiateté** du message, et c'est ce que
> l'énoncé demande d'expliquer.
>
> `Network is unreachable` est produit par l'appel système `connect()` — donc par
> **ta propre pile**, avant qu'aucun paquet ne soit émis. Le noyau consulte sa
> table de routage, ne trouve aucune route correspondant à `9.9.9.9`, et renvoie
> `ENETUNREACH` immédiatement. Zéro paquet sur le fil.
>
> Comparaison des trois symptômes, qui désignent trois étages :
>
> | Symptôme | Délai | Étage |
> |---|---|---|
> | `Network is unreachable` | instantané | routage **local** |
> | `Destination Host Unreachable` | ~1 s | ARP, couche 2 locale |
> | 100 % perte, aucun message | timeout | réseau **en amont** |
>
> Avant même la première commande de diagnostic, l'immédiateté avait donc déjà
> donné la réponse : le problème est sur cette machine, dans sa table de routage.
> C'est ce genre de lecture qui fait la différence entre dix secondes et dix
> minutes de diagnostic.
>
> Sur la distinction entre les deux correctifs : `ip r add` modifie l'**état** du
> noyau, en mémoire. `netplan apply` ré-applique la **configuration**, qui est la
> source de vérité au démarrage. Les deux sont nécessaires : le premier rétablit le
> service tout de suite, le second garantit que le prochain redémarrage ne
> reproduira pas la panne. Rétablir seulement l'un des deux est une faute classique
> — et la seconde moitié de la panne réapparaît des semaines plus tard, sans que
> personne ne fasse le lien.

> [!WARNING]
> **Piège**
>
> Le réflexe `sudo systemctl restart systemd-networkd` aurait « réparé » la panne
> par effet de bord, en ré-appliquant la configuration — sans jamais te dire ce
> qui s'était passé. C'est précisément ce que l'énoncé interdit. En production, une
> panne réparée sans cause identifiée est une panne qui revient. Et si la cause
> avait été une **suppression persistante** dans le YAML, le redémarrage du démon
> n'aurait rien réparé du tout, ce qui aurait fait perdre encore plus de temps.

> [!CAUTION]
> **Attention**
>
> **Prévention.** Une supervision qui ne teste que le LAN ne voit pas cette panne.
> Un test synthétique minimal, exécuté toutes les minutes sur chaque machine :
> `ip r | grep -q '^default' || alerte`, complété par un `curl -s -o /dev/null
> --max-time 5 https://<cible-externe>/`. Deux lignes qui couvrent les deux moitiés
> du problème.

---

### <a id="bf12-2"></a>**[BF12.2](README.md#bf12-2)** — « Tout est lent, puis plus rien ne résout »

*`curl` par IP instantané, `curl` par nom échoue après une dizaine de secondes.*

**Démarche de diagnostic**

```bash
# 1. IP contre nom : le réseau est hors de cause
curl -sS -o /dev/null http://10.10.10.11/ ; echo $?     # 0
curl -sS -o /dev/null http://www.lab.local/ ; echo $?   # 6

# 2. quel est le serveur réellement utilisé ?
cat /etc/resolv.conf
ls -l /etc/resolv.conf
#    -rw-r--r-- 1 root root ... /etc/resolv.conf   <- fichier réel, plus un lien
#    nameserver 10.10.10.250

# 3. ce serveur répond-il ?
dig @10.10.10.250 lab-web.lab.local        # timeout
dig @10.10.10.10  lab-web.lab.local        # NOERROR, 10.10.10.11

# 4. que dit le résolveur systemd ?
resolvectl status | head -20
systemctl status systemd-resolved
```

**Cause racine** : `/etc/resolv.conf` n'est plus le lien symbolique vers
`../run/systemd/resolve/stub-resolv.conf`. Il a été remplacé par un fichier
réel pointant vers `10.10.10.250`, une adresse où aucun serveur DNS ne répond.

**Correctif durable**

```bash
sudo rm /etc/resolv.conf
sudo ln -s ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
ls -l /etc/resolv.conf
sudo systemctl restart systemd-resolved
resolvectl status
getent hosts www.lab.local
```

Et on vérifie que le serveur du lab est bien déclaré dans la configuration
persistante :

```bash
sudo netplan get ethernets.ens18.nameservers
```

**Le délai de dix secondes**

`/etc/resolv.conf` applique par défaut `timeout:5` et `attempts:2` : deux
tentatives de 5 secondes vers le seul serveur déclaré, soit **10 secondes** avant
l'abandon. Avec deux serveurs déclarés, ce serait 20 secondes. C'est réglable :

```text
options timeout:2 attempts:1
```

> [!NOTE]
> **Pourquoi**
>
> Le mécanisme : `getaddrinfo()` envoie une requête UDP au serveur listé, attend
> `timeout` secondes, réessaie `attempts` fois, puis passe au serveur suivant s'il
> y en a un. Un serveur qui ne répond **pas du tout** (paquets jetés) coûte donc le
> timeout complet à chaque résolution — d'où la lenteur généralisée : `apt`, `ssh`,
> toute commande qui résout un nom devient interminable.
>
> À comparer avec un serveur qui **refuse activement** (port 53 fermé, `ICMP port
> unreachable` en retour) : l'échec serait immédiat. Là encore, le **délai** est
> l'information. Dix secondes d'attente = paquets jetés. Échec instantané = refus
> actif ou absence de route.
>
> Pourquoi le lien symbolique est la vraie correction : `systemd-resolved` gère le
> contenu de `/run/systemd/resolve/stub-resolv.conf` à partir des serveurs déclarés
> par Netplan, par DHCP ou par VPN. Écrire un fichier réel à la place du lien
> **gèle** la configuration DNS hors de tout mécanisme de gestion : elle ne suivra
> plus les changements, et sera silencieusement fausse le jour où le serveur
> change. C'est exactement ce que fait le script de panne.
>
> Trois fichiers à distinguer, et c'est ce qui embrouille tout le monde :
>
> | Fichier | Contenu |
> |---|---|
> | `/run/systemd/resolve/stub-resolv.conf` | `nameserver 127.0.0.53` (le stub) |
> | `/run/systemd/resolve/resolv.conf` | les **vrais** serveurs amont |
> | `/etc/resolv.conf` | lien vers l'un des deux |
>
> Pointer `/etc/resolv.conf` vers le second est un choix valide et documenté : il
> contourne le stub et donc le cache local, pour les logiciels qui gèrent mal
> `127.0.0.53`. Ce n'est pas une erreur, c'est un arbitrage.

> [!WARNING]
> **Piège**
>
> Variante qu'on rencontre en production : `/etc/resolv.conf` est un fichier réel
> **et** porte l'attribut immuable (`chattr +i`), posé par un admin excédé de voir
> ses modifications écrasées. Symptôme déroutant : `rm` échoue avec
> `Operation not permitted` alors qu'on est root. Diagnostic : `lsattr
> /etc/resolv.conf` montre le `i`. Correctif : `chattr -i` avant toute chose. La
> bonne façon de figer une configuration DNS n'est pas là : c'est
> `systemd-resolved` avec des serveurs déclarés dans Netplan, ou
> `resolvconf` selon la distribution.

> [!CAUTION]
> **Attention**
>
> **Prévention.** Un test de supervision qui résout un nom connu et compare le
> résultat attendu, avec un timeout court :
> `timeout 3 getent hosts lab-web.lab.local | grep -q 10.10.10.11 || alerte`.
> Et surveiller la **nature** de `/etc/resolv.conf` : `test -L /etc/resolv.conf`.

---

### <a id="bf12-3"></a>**[BF12.3](README.md#bf12-3)** — « L'API répond sur le serveur mais pas depuis le poste d'admin »

*`curl localhost:8099` fonctionne, `curl 10.10.10.11:8099` échoue en code 7.*

**Démarche de diagnostic**

```bash
# 1. depuis lab-adm : refus immédiat, pas un timeout
curl -sS --max-time 5 http://10.10.10.11:8099/health ; echo $?   # 7
nc -zv -w2 10.10.10.11 8099
#    nc: connect to 10.10.10.11 port 8099 (tcp) failed: Connection refused

# 2. le pare-feu est hors de cause (on le vérifie une fois, on passe)
ssh lab-web 'sudo systemctl is-active nftables ufw firewalld 2>/dev/null'

# 3. LA commande décisive, sur lab-web
sudo ss -tlpn 'sport = :8099'
#    LISTEN 0 5 127.0.0.1:8099 ... users:(("python3",pid=912,fd=3))
#                  ^^^^^^^^^ voilà la cause

# 4. d'où vient cette adresse d'écoute ?
systemctl cat factura-api.service
```

**Cause racine** : le service est lié à `127.0.0.1:8099` au lieu de `0.0.0.0:8099`.
Un drop-in systemd a modifié la variable d'environnement d'adresse d'écoute.

```console
$ systemctl cat factura-api.service
# /etc/systemd/system/factura-api.service.d/override.conf
[Service]
Environment=FACTURA_BIND=127.0.0.1
```

**Correctif**

```bash
sudo rm /etc/systemd/system/factura-api.service.d/override.conf
sudo rmdir --ignore-fail-on-non-empty \
  /etc/systemd/system/factura-api.service.d
sudo systemctl daemon-reload
sudo systemctl restart factura-api
sudo ss -tlpn 'sport = :8099'        # doit montrer 0.0.0.0:8099
# depuis lab-adm
curl -s http://10.10.10.11:8099/health
```

**Codes 7 et 28 de `curl`**

| Code | Message | Ce qui s'est passé | Ce que ça élimine |
|---|---|---|---|
| 7 | `Failed to connect` | un `RST` est revenu | le filtrage `DROP` |
| 28 | `Operation timed out` | rien n'est revenu | le « service arrêté » |

Ici, le code **7** disait dès la première commande que la machine était joignable
et répondait activement : le problème était donc le **socket**, pas le réseau ni
un pare-feu. Un code 28 aurait au contraire orienté vers un filtrage ou une route
de retour absente.

> [!NOTE]
> **Pourquoi**
>
> Le mécanisme, au niveau du noyau. Un socket est lié à un couple (adresse, port).
> Quand un segment `SYN` arrive sur `ens18` à destination de `10.10.10.11:8099`, la
> pile cherche un socket en écoute correspondant à cette adresse **ou** au joker
> `0.0.0.0`. Le seul socket existant est lié à `127.0.0.1`, adresse atteignable
> uniquement via l'interface `lo`. Aucune correspondance : le noyau répond par un
> `RST`, immédiatement. `curl` traduit en `Connection refused`, code 7.
>
> Depuis la machine elle-même, `curl localhost:8099` emprunte `lo`, l'adresse de
> destination est bien `127.0.0.1`, la correspondance est trouvée : ça marche. D'où
> le symptôme « ça marche en local, pas à distance », qui est la signature exacte
> de cette configuration.
>
> Ce que le code 7 permet d'éliminer d'emblée : un pare-feu en `DROP` ne renvoie
> rien, il produit un timeout (code 28). Un `REJECT` renverrait un ICMP
> `port unreachable`, que `curl` traduit aussi en code 7 — c'est la seule
> ambiguïté, et elle se lève en regardant la capture : `RST` TCP contre ICMP type 3.
> D'où la vérification unique du pare-feu à l'étape 2, qui coûte cinq secondes et
> ferme la question.
>
> Pourquoi ne pas simplement passer à `0.0.0.0` et considérer l'affaire close :
> l'énoncé demande la cause exacte. Un drop-in systemd ne s'écrit pas tout seul, il
> y a eu une intention derrière — peut-être un durcissement délibéré, avec un
> reverse proxy prévu devant (c'est L12.4). Corriger sans comprendre, c'est
> potentiellement annuler une décision de sécurité.

> [!WARNING]
> **Piège**
>
> Deux variantes du même symptôme, à reconnaître :
>
> * l'application écoute sur `[::1]:8099` (boucle IPv6 seule) : `curl localhost`
>   fonctionne parce que `localhost` résout en `::1` en premier, mais
>   `curl 127.0.0.1` échoue. Déroutant au possible.
> * l'application écoute sur `10.10.10.11:8099` explicitement : ça marche depuis le
>   réseau mais **pas** en `localhost`, symptôme exactement inverse, qui casse les
>   sondes de santé locales et les scripts de déploiement.
>
> Dans les deux cas, la même commande tranche : `ss -tlpn`, et on **lit l'adresse**,
> pas seulement le port.

> [!CAUTION]
> **Attention**
>
> **Prévention.** Toute sonde de santé doit tester le service **par l'adresse que
> les clients utilisent**, pas par `localhost`. Une supervision qui ne teste que
> `curl localhost:8099/health` déclare le service sain pendant toute la durée de
> cette panne.

---

### <a id="bf12-4"></a>**[BF12.4](README.md#bf12-4)** — « Cette machine-là voit un autre site que les autres »

*`dig` donne la bonne IP, `curl` par nom échoue, `curl` par IP fonctionne.*

**Démarche de diagnostic**

```bash
# 1. l'écart est entre le DNS et le système : on le prouve en une ligne
getent hosts www.lab.local ; dig +short @10.10.10.10 www.lab.local
#    10.10.10.12    www.lab.local
#    10.10.10.11

# 2. d'où vient la valeur du système ?
grep -n 'www\.lab\.local' /etc/hosts
#    23:10.10.10.12  www.lab.local www

# 3. et l'ordre des sources
grep '^hosts:' /etc/nsswitch.conf
#    hosts: files dns

# 4. confirmation applicative
curl -sS -v http://www.lab.local/ 2>&1 | grep -i 'trying\|connect'
#    * Trying 10.10.10.12:80...
#    * connect to 10.10.10.12 port 80 failed: Connection refused
```

**Cause racine** : une entrée dans `/etc/hosts` associe `www.lab.local` à
`10.10.10.12` (`lab-db`, qui existe mais n'a aucun serveur web : d'où le `RST` immédiat). Comme `files` précède `dns` dans
`nsswitch.conf`, toutes les applications utilisent cette valeur et le DNS n'est
jamais interrogé. `dig` `@10.10.10.10`, qui ne passe pas par NSS et interroge le serveur directement, continue d'afficher la bonne
réponse — d'où la confusion. (Sans `@`, `dig` passe par le stub `127.0.0.53`, et `systemd-resolved` lui servirait la même entrée de `/etc/hosts`.)

**Correctif**

```bash
sudo cp /etc/hosts /root/.breakfix-backup/hosts.avant-fix
sudo sed -i '/^10\.10\.10\.12[[:space:]].*www\.lab\.local/d' /etc/hosts
getent hosts www.lab.local        # -> 10.10.10.11
curl -sI http://www.lab.local/ | head -1
```

**Règle générale**

`/etc/nsswitch.conf` définit l'ordre des sources de noms, et la **première qui
répond gagne** : la recherche s'arrête là. `files` (donc `/etc/hosts`) est
consulté avant `dns` sur toutes les distributions par défaut. Donc :

* une entrée dans `/etc/hosts` **prime toujours** sur le DNS, sans exception ;
* `dig` et `nslookup` ne lisent pas `/etc/hosts` : ce sont des clients DNS purs — mais s'ils interrogent le stub `127.0.0.53`, `systemd-resolved` leur sert `/etc/hosts` : pour voir le DNS seul, `dig @serveur` ;
* la seule commande qui dit la vérité du point de vue des applications est
  `getent hosts`.

> [!NOTE]
> **Pourquoi**
>
> La divergence `dig` / `getent` est la signature la plus fiable du module, et elle
> mérite d'être mémorisée comme telle : **quand `dig` et le système ne sont pas
> d'accord, le problème n'est pas dans le DNS**.
>
> Le chemin exact : `curl` appelle `getaddrinfo()`, qui consulte
> `/etc/nsswitch.conf`. La ligne `hosts: files dns` déclenche les modules dans
> l'ordre. Le module `files` lit `/etc/hosts`, trouve `www.lab.local`, retourne
> `10.10.10.12` avec le statut `SUCCESS`. L'action par défaut associée à
> `SUCCESS` est `return` : la chaîne s'arrête, le module `dns` n'est jamais appelé.
>
> C'est aussi pourquoi `resolvectl flush-caches` ne change rien ici — et pourquoi
> l'énoncé l'interdit explicitement. Le cache DNS n'est pas en cause : le DNS
> n'est pas interrogé du tout.
>
> Pourquoi cette panne est fréquente en vrai : quelqu'un a testé une migration en
> posant une ligne dans `/etc/hosts` — geste légitime et courant — et a oublié de
> la retirer. Six semaines plus tard, l'IP change côté DNS, et cette seule machine
> part vers l'ancienne adresse. Le diagnostic est difficile précisément parce que
> `dig` répond correctement et que tout le monde regarde le DNS.
>
> La discipline qui évite ça : toute entrée temporaire dans `/etc/hosts` porte un
> commentaire daté au-dessus, avec le numéro de ticket et la date de péremption.
>
> ```text
> # INC-3307 - test bascule www - à retirer avant le 2026-10-01 - mathieu
> 10.10.10.12  www.lab.local
> ```

> [!WARNING]
> **Piège**
>
> Variante plus retorse, qui produit le même symptôme sans qu'aucune ligne suspecte
> n'apparaisse dans `/etc/hosts` : l'ordre de `nsswitch.conf` inversé en
> `hosts: dns files`, ou la présence de `mdns4_minimal [NOTFOUND=return]` avant
> `dns` sur un domaine en `.local`. Dans ce dernier cas, mDNS répond « inconnu »
> pour un nom en `.local`, le `[NOTFOUND=return]` arrête la chaîne, et le DNS n'est
> jamais interrogé — alors que `dig` fonctionne parfaitement. Toujours lire la
> ligne `hosts:` **en entier**, pas seulement chercher `files` et `dns`.

> [!CAUTION]
> **Attention**
>
> **Prévention.** Mettre `/etc/hosts` et `/etc/nsswitch.conf` sous gestion de
> configuration (Ansible, module 23), avec un contenu déclaré. Toute dérive est
> alors détectée au prochain passage, et le fichier est remis en conformité
> automatiquement.

---

## 12.8 Défi du module

<a id="d12"></a>**[D12](README.md#d12) — `netdiag.sh`**

*Diagnostic réseau ordonné couche par couche, rapport Markdown, verdict par étage.*

**Solution de référence**

```bash
#!/usr/bin/env bash
# netdiag.sh — diagnostic réseau ordonné, couche par couche
set -euo pipefail

PORT=""; FAM=""; CIBLE=""; SCHEME="http"
KO=0

usage() { echo "usage: $0 [-p port] [-4|-6] <cible|url>" >&2; exit 2; }

while getopts ':p:46h' o; do
  case "$o" in
    p) PORT="$OPTARG" ;;
    4) FAM="-4" ;;
    6) FAM="-6" ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || usage

# --- normalisation de la cible ----------------------------------------
CIBLE="$1"
case "$CIBLE" in
  https://*) SCHEME=https; CIBLE="${CIBLE#https://}" ;;
  http://*)  SCHEME=http;  CIBLE="${CIBLE#http://}" ;;
esac
CIBLE="${CIBLE%%/*}"
[ -n "$CIBLE" ] || usage
[ -n "$PORT" ] || { [ "$SCHEME" = https ] && PORT=443 || PORT=80; }

log()  { printf '%s\n' "$*" >&2; }
row()  { printf '| %s | %s | %s | %s |\n' "$1" "$2" "$3" "$4"; }
bad()  { KO=$((KO + 1)); }

printf '# Diagnostic réseau — %s:%s\n\n' "$CIBLE" "$PORT"
printf 'Date : %s — depuis %s\n\n' "$(date '+%F %T')" "$(hostname)"
printf '| Couche | Test | Verdict | Détail |\n|---|---|---|---|\n'

# --- 1. L2/L3 local ----------------------------------------------------
IFACE=$(ip -o -4 route show default | awk '{print $5; exit}')
if [ -n "$IFACE" ]; then
  MTU=$(cat "/sys/class/net/$IFACE/mtu")
  row L2 interface OK "$IFACE, mtu $MTU"
else
  row L2 interface KO "aucune interface avec route par defaut"; bad
fi

GW=$(ip -o -4 route show default | awk '{print $3; exit}')
if [ -n "$GW" ]; then
  row L3 "route par defaut" OK "via $GW"
else
  row L3 "route par defaut" KO "absente : ip r n'a aucune ligne default"; bad
fi

if [ -n "$GW" ]; then
  ping -c1 -W1 "$GW" >/dev/null 2>&1 || true
  ST=$(ip neigh show "$GW" 2>/dev/null | awk '{print $NF}')
  case "$ST" in
    REACHABLE|STALE|DELAY|PROBE) row L2 "arp passerelle" OK "$ST" ;;
    '')                          row L2 "arp passerelle" SKIP "pas d'entree" ;;
    *)                           row L2 "arp passerelle" KO "$ST"; bad ;;
  esac
fi

# --- 2. résolution ------------------------------------------------------
if printf '%s' "$CIBLE" | grep -qE '^[0-9.]+$'; then
  IP="$CIBLE"
  row DNS resolution SKIP "cible deja numerique"
else
  IP_HOSTS=$(getent hosts "$CIBLE" 2>/dev/null | awk '{print $1; exit}') || true
  NS=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf 2>/dev/null) \
    || true
  # le stub 127.0.0.53 sert aussi /etc/hosts ; 127.0.0.54 (proxy) non
  [ "${NS:-}" = 127.0.0.53 ] && NS=127.0.0.54
  IP_DNS=$(dig +short +time=2 +tries=1 ${NS:+@$NS} A "$CIBLE" 2>/dev/null |
           grep -E '^[0-9.]+$' | head -1) || true
  IP="${IP_HOSTS:-$IP_DNS}"
  if [ -z "$IP" ]; then
    row DNS resolution KO "aucune adresse (ni NSS ni DNS)"; bad
  elif [ -n "$IP_DNS" ] && [ -n "$IP_HOSTS" ] && [ "$IP_DNS" != "$IP_HOSTS" ]
  then
    row DNS resolution KO "divergence: hosts=$IP_HOSTS dns=$IP_DNS"; bad
  else
    row DNS resolution OK "$IP"
  fi
fi

# --- 3. route vers la cible --------------------------------------------
if [ -n "${IP:-}" ]; then
  R=$(ip route get "$IP" 2>/dev/null | head -1) && \
    row L3 route OK "$(printf '%s' "$R" | cut -c1-60)" || \
    { row L3 route KO "pas de route vers $IP"; bad; }
fi

# --- 4. accessibilité L3 ------------------------------------------------
if [ -n "${IP:-}" ]; then
  if ping -c2 -W1 ${FAM:-} "$IP" >/dev/null 2>&1; then
    row L3 ping OK "reponse ICMP"
  else
    row L3 ping SKIP "pas de reponse ICMP (filtrage possible)"
  fi
fi

# --- 5. transport -------------------------------------------------------
if [ -n "${IP:-}" ]; then
  T0=$(date +%s%N)
  if timeout 5 bash -c "</dev/tcp/$IP/$PORT" 2>/dev/null; then
    row L4 "tcp/$PORT" OK "connexion acceptee"
  else
    DT=$(( ($(date +%s%N) - T0) / 1000000 ))
    if [ "$DT" -lt 1000 ]; then
      row L4 "tcp/$PORT" KO "refus immediat (RST) : rien n'ecoute"; bad
    else
      row L4 "tcp/$PORT" KO "timeout ${DT}ms : paquets jetes (filtrage)"; bad
    fi
  fi
fi

# --- 6. application -----------------------------------------------------
URL="$SCHEME://$CIBLE:$PORT/"
OUT=$(curl -sS ${FAM:-} -o /dev/null --max-time 10 \
        -w '%{http_code} %{time_total} %{size_download}' "$URL" 2>/dev/null) \
  && row L7 http OK "$OUT" \
  || { row L7 http KO "curl rc=$? sur $URL"; bad; }

HDR=$(curl -sSI ${FAM:-} --max-time 10 "$URL" 2>/dev/null |
      grep -iE '^(server|location):' | tr -d '\r' | paste -sd' ' -) || true
[ -n "$HDR" ] && row L7 entetes OK "$HDR"

if [ "$SCHEME" = https ]; then
  EXP=$(echo | timeout 5 openssl s_client -connect "$CIBLE:$PORT" \
          -servername "$CIBLE" 2>/dev/null |
        openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2) || true
  [ -n "$EXP" ] && row TLS certificat OK "expire $EXP" \
                || { row TLS certificat KO "handshake impossible"; bad; }
fi

# --- 7. MTU -------------------------------------------------------------
if [ -n "${IP:-}" ]; then
  LO=0; HI=1472; BEST=0
  while [ "$LO" -le "$HI" ]; do
    MID=$(( (LO + HI) / 2 ))
    if ping -M do -s "$MID" -c1 -W1 "$IP" >/dev/null 2>&1; then
      BEST="$MID"; LO=$((MID + 1))
    else
      HI=$((MID - 1))
    fi
  done
  if [ "$BEST" -eq 0 ]; then
    row MTU pmtu SKIP "ICMP indisponible, mesure impossible"
  elif [ "$((BEST + 28))" -lt 1500 ]; then
    row MTU pmtu KO "$((BEST + 28)) octets (< 1500)"; bad
  else
    row MTU pmtu OK "$((BEST + 28)) octets"
  fi
fi

# --- diagnostic ---------------------------------------------------------
printf '\n## Diagnostic\n\n'
if [ "$KO" -eq 0 ]; then
  printf 'Tous les etages repondent. Si le service est percu comme KO,\n'
  printf "chercher cote application (journaux, backend, code HTTP).\n"
else
  printf '%s etage(s) en echec. Traiter le premier KO du tableau :\n' "$KO"
  printf 'un etage bas en echec explique tous les etages au-dessus.\n'
fi

[ "$KO" -eq 0 ] && exit 0 || exit 1
```

**Validation sur les quatre pannes**

| Panne | Premier `KO` attendu | Diagnostic |
|---|---|---|
| BF12.1 | `L2 / interface` puis `L3 / route par` |  |
|  | `defaut` | route par défaut absente |
| BF12.2 | `DNS / resolution` | aucune adresse obtenue |
| BF12.3 | `L4 / tcp/8099` | refus immédiat, rien n'écoute |
| BF12.4 | `DNS / resolution` | divergence `hosts` ≠ `dns` |

> [!NOTE]
> **Pourquoi**
>
> Quatre décisions de conception méritent d'être expliquées, parce que ce sont
> elles qui font la différence entre un script qui affiche des commandes et un
> outil de diagnostic.
>
> **1. L'ordre est la valeur ajoutée.** Un étage bas en échec explique tous les
> étages au-dessus. Sans ordre, on obtient sept lignes rouges et aucune
> information ; avec l'ordre, le premier `KO` **est** le diagnostic. C'est pourquoi
> la section finale dit « traite le premier KO » plutôt que d'énumérer.
>
> **2. `SKIP` n'est pas `KO`.** Un `ping` sans réponse ne prouve rien : ICMP est
> filtré sur la moitié des réseaux d'entreprise. En faire un échec produit des faux
> positifs, et un outil qui crie au loup n'est plus lu. Même logique pour le MTU
> quand ICMP est indisponible.
>
> **3. La mesure du délai distingue refusé et filtré.** C'est le point le plus
> fin du script. Un échec de connexion en moins d'une seconde signifie qu'un `RST`
> est revenu : la machine est là, rien n'écoute. Un échec après plusieurs secondes
> signifie que les paquets sont jetés : filtrage ou route de retour absente. Deux
> causes radicalement différentes, distinguées par un chronomètre.
>
> **4. La divergence `hosts` / `dns` est signalée comme anomalie.** C'est BF12.4
> transformé en test automatique. Aucun outil du commerce ne le fait, et c'est
> pourtant une des causes les plus fréquentes et les plus coûteuses à diagnostiquer.
>
> Sur la technique : `</dev/tcp/$IP/$PORT` évite de dépendre de `nc`, absent de
> beaucoup d'images minimales — c'est une fonctionnalité de bash, pas un fichier.
> La dichotomie MTU en 11 itérations couvre 0-1472 octets, soit environ une seconde
> avec `-W1`, contre plusieurs minutes pour un balayage linéaire.
>
> Sur la séparation stdout / stderr, exigée par le cahier des charges : le rapport
> Markdown sur stdout, la trace sur stderr. C'est ce qui permet
> `netdiag.sh cible > rapport.md` sans post-traitement, et l'intégration dans une
> sonde de supervision qui ne lit que le code de retour.

> [!WARNING]
> **Piège**
>
> Le piège d'implémentation classique dans ce genre de script : `set -euo pipefail`
> combiné à des commandes dont l'échec est **attendu** (un `ping` qui ne répond pas,
> un `curl` en erreur). Sans `|| true` ou sans capture explicite du code de retour,
> le script meurt au premier test négatif — c'est-à-dire exactement dans le cas
> qu'il est censé diagnostiquer. C'est l'ironie de l'exercice, et la raison des
> `|| true` et des `if` explicites dans la solution de référence.
>
> Deuxième piège : `ip route get` sur une cible sans route renvoie un code non nul
> **et** écrit sur stderr. Sans redirection, le message parasite le rapport
> Markdown. D'où le `2>/dev/null` et le test du code de retour.

<!-- nav:début -->
---

[← Module 11](../11-stockage-lvm/corrige.md) · [Énoncé](README.md) · [Module 13 →](../13-reseau-avance/corrige.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
