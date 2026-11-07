# Module 13 — Corrigé

## 13.3 Quiz — QCM

**Q13.1** — *`ip netns add c1` puis `ping 127.0.0.1` dans `c1` : « Network is
unreachable ».*

**Réponse : b)** `lo` existe mais est `DOWN`.

::: pourquoi
Un namespace réseau neuf ne contient qu'une seule interface, `lo`, et le noyau
la crée à l'état administratif `DOWN`. Tant qu'elle n'est pas montée, aucune
route n'existe dans le namespace (la route `127.0.0.0/8 dev lo` de la table
`local` n'est posée par le noyau qu'au moment où l'interface passe `UP`).
`ping` cherche une route vers `127.0.0.1`, n'en trouve pas, et `connect()`
échoue avec `ENETUNREACH` : c'est le message affiché.

`ip -n c1 link set lo up` règle le problème. C'est la première chose que fait
`docker run` (ou plutôt le runtime `runc`) dans le namespace d'un conteneur,
et la première chose qu'oublie tout le monde à la main.
:::

::: piege
a) est presque vrai (il n'y a pas de route) mais inverse la cause et l'effet :
la route manque **parce que** `lo` est down. c) : aucun filtrage n'existe par
défaut dans un netns, le jeu de règles nftables y est vide. d) : `nsenter` et
`ip netns exec` font strictement la même chose (`setns()` sur
`/run/netns/c1`).
:::

---

**Q13.2** — *`eth0@if6` dans `ip -n c1 link`.*

**Réponse : b)** un bout de veth dont le pair a l'index 6 dans un autre namespace.

::: pourquoi
Les interfaces ont un index par namespace. Une paire veth est deux interfaces
liées ; quand l'une est déplacée dans un autre netns, `ip link` affiche
`nom@ifN` où `N` est l'index du pair **dans son namespace à
lui** (namespace désigné, lui, par `link-netnsid`). `ip -d link show eth0` dans `c1` ajoute `link-netnsid 0` (le namespace
du pair, vu depuis `c1`), et `ip link | grep '@if'` dans le netns racine montre
l'autre bout, `veth-c1@if5` : les deux indices se répondent.

C'est ainsi qu'on retrouve, sur un hôte Docker, quel `vethXXXX` du bridge
appartient à quel conteneur : `docker exec c1 cat /sys/class/net/eth0/iflink`
donne l'index du pair côté hôte, `ip link | grep '^6:'` donne son nom.
:::

---

**Q13.3** — *Depuis `c1` : `ping 172.20.0.12` OK, `ping 10.10.10.11` OK,
`ping 172.20.0.1` muet.*

**Réponse : b)** le trafic vers l'adresse du bridge est du trafic `input` du
netns racine.

::: pourquoi
Il faut distinguer trois chemins pour un paquet qui sort de `c1` :

* vers `172.20.0.12` : commutation L2 par le bridge, port à port. Le netns
  racine ne voit ce paquet qu'en tant que commutateur (sauf si `br_netfilter`
  est chargé). Aucune règle IP ne s'applique.
* vers `10.10.10.11` : le paquet arrive sur le bridge, dont l'adresse
  `172.20.0.1` est la passerelle ; le netns racine prend une décision de
  routage, ce n'est pas pour lui → chaîne **`forward`**, puis `postrouting`
  (masquerade), puis `ens18`.
* vers `172.20.0.1` : la destination **est** une adresse locale du netns
  racine → chaîne **`input`**, pas `forward`.

Un jeu de règles typique (module 18, ou celui de E13.11 privé de sa règle ICMP) a une chaîne `input`
en `policy drop` qui n'autorise pas ICMP depuis `172.20.0.0/24`, alors que la
chaîne `forward` accepte tout ce qui part de `br-lab`. Résultat : le bridge
relaie, mais ne répond pas lui-même. `nft list chain inet filter input` et un
`counter` sur la règle de `drop` finale le prouvent en dix secondes.
:::

::: piege
a) : bridge `DOWN`, rien ne passerait, même pas `c1` ↔ `c2`. c) :
`masquerade` ne s'applique qu'en `postrouting` sur les paquets **sortant** par
l'interface indiquée (`oifname "ens18"`), jamais à du trafic `input`.
b) : `172.20.0.1` est dans `172.20.0.0/24`, la route connectée suffit.
:::

---

**Q13.4** — *Règle `from 10.10.12.2 lookup gw2`, table `gw2` = `default via
10.10.12.1 dev eth2`, destination `10.10.12.50` sur le segment direct.*

**Réponse : a)** via `10.10.12.1`.

::: pourquoi
L'algorithme du noyau : parcourir les règles par priorité croissante ; à la
première qui matche, faire la recherche dans la table désignée ; **si la table
contient une route qui matche la destination, la décision est prise**, on
n'examine plus les règles suivantes. La règle `100` matche (source
`10.10.12.2`), la table `gw2` contient une route par défaut, qui matche tout,
y compris `10.10.12.50`. Le paquet part donc vers la passerelle, qui le
renverra sur le même segment (avec un ICMP redirect si `send_redirects` est
actif chez elle). Ça fonctionne, mais c'est un détour idiot, et sur un vrai
routeur ça peut être jeté par une politique anti-spoofing.

On ne retombe sur `main` **que** si la table ne contient aucune route pour la
destination (`lookup` échoue → règle suivante). D'où la règle d'or du policy
routing : une table dédiée doit contenir **aussi les routes connectées** de
l'interface concernée :

```bash
ip route add 10.10.12.0/24 dev eth2 src 10.10.12.2 table gw2
ip route add default via 10.10.12.1 dev eth2 table gw2
```

Ou, plus simple, une règle `to 10.10.12.0/24 lookup main` de priorité
inférieure à 100.
:::

::: piege
b) décrit ce qu'on aimerait et ce que beaucoup croient : ce n'est pas le
comportement. c) : « unreachable » ne se produit que si **aucune** table
consultée n'a de route, ce qui n'est pas le cas ici. d) : `rp_filter` s'applique
aux paquets **reçus**, pas émis.
:::

---

**Q13.5** — *Chaîne de base vs chaîne régulière.*

**Réponse : a) et b).**

::: pourquoi
Une chaîne de base est déclarée avec `type <filter|nat|route> hook <hook>
priority <n>` (et éventuellement `policy`) : le noyau l'enregistre sur le hook
netfilter correspondant et lui donne chaque paquet qui y passe. Plusieurs
chaînes de base peuvent partager un hook (Docker, ufw et toi) ; elles sont
alors parcourues par priorité croissante, et un `drop` dans l'une est
définitif tandis qu'un `accept` ne fait que passer à la chaîne de base
suivante du même hook.

Une chaîne régulière (`nft add chain inet filter mes_services` sans `type`)
n'est rattachée à rien : elle ne s'exécute que quand une règle fait `jump
mes_services` (avec retour) ou `goto mes_services` (sans retour). Elle sert à
organiser : une chaîne par service, par zone, par locataire. Elle accepte
tous les verdicts, dans toute table.
:::

---

**Q13.6** — *`forward` en `policy drop` avec seulement `iifname "br-lab"
oifname "ens18" accept` ; le SYN part, le SYN-ACK arrive sur `ens18`, `curl`
expire.*

**Réponse : b)** il manque `ct state established,related accept`.

::: pourquoi
Le SYN va de `br-lab` vers `ens18` : la règle l'accepte. Le SYN-ACK revient
par `ens18` et doit être relayé vers `br-lab` : aucune règle ne matche
(`iifname` est `ens18`), la politique `drop` s'applique. Le client réémet son
SYN toutes les 1, 2, 4… secondes, sans jamais voir de réponse : timeout.

`tcpdump -i ens18` voit le SYN-ACK parce que la capture se fait **avant**
netfilter (au niveau du pilote, via AF_PACKET). Voir un paquet dans
`tcpdump` ne prouve jamais qu'il a traversé le pare-feu ; un `counter` sur la
règle de `drop`, ou `nft monitor trace`, le prouve.

`ct state established,related accept` en première règle laisse passer tout
paquet appartenant à un flux déjà vu **dans l'autre sens** : le SYN-ACK est
`established` (conntrack a vu le SYN sortir, le flux existe ; dès qu'un paquet
revient, il est `established`). C'est la règle qui rend un pare-feu stateful.
:::

::: piege
a) : sans masquerade, le SYN partirait avec la source `172.20.0.x`, `lab-web`
répondrait vers cette adresse qu'il ne sait pas router — mais alors on ne
verrait **pas** de SYN-ACK arriver sur `ens18`. d) : sans `ip_forward`, le SYN
ne sortirait même pas.
:::

---

**Q13.7** — *Ligne `conntrack -L` avec deux tuples différents.*

**Réponse : a) et b).**

::: pourquoi
Une entrée conntrack contient deux tuples : le tuple **original** (tel que vu
au premier paquet : `172.20.0.11:40312 → 10.10.10.11:80`) et le tuple de
**réponse** (ce que le pare-feu attend dans l'autre sens :
`10.10.10.11:80 → 10.10.10.10:40312`). Quand ils ne sont pas symétriques, il y
a une traduction : ici la source a été réécrite en `10.10.10.10`, c'est un
SNAT/masquerade. C'est exactement ce que le NAT « mémorise » pour réécrire les
retours sans relire les règles.

`431999` est le temps restant en secondes avant expiration si aucun paquet ne
passe : `nf_conntrack_tcp_timeout_established` vaut 432 000 s = 5 jours par
défaut. `[ASSURED]` signifie que le flux a été vu dans les deux sens avec des
données : ces entrées ne sont jamais victimes de l'« early drop » quand la table
est pleine, contrairement aux entrées non assurées.
:::

::: piege
c) : l'état conntrack est `ESTABLISHED`, pas `TIME_WAIT` — conntrack a sa
propre machine à états, distincte de celle du socket TCP. d) : conntrack ne
sait rien des verdicts ; un flux tracé peut très bien finir en `drop`.
:::

---

**Q13.8** — *`nf_conntrack: table full, dropping packet`.*

**Réponse : b)** augmenter `nf_conntrack_max` (et les buckets), puis chercher
ce qui remplit.

::: pourquoi
Quand la table atteint `nf_conntrack_max`, le noyau tente d'abord un « early
drop » d'une entrée non assurée ; s'il n'en trouve pas, il jette le paquet qui
créerait une nouvelle entrée. Les flux existants ont leur entrée : ils
continuent. C'est le motif « les sessions ouvertes marchent, les nouvelles
échouent » — à mémoriser, il pointe directement vers conntrack.

Correctif immédiat : `sysctl -w net.netfilter.nf_conntrack_max=262144` (et
`nf_conntrack_buckets` à `max/4` via `/sys/module/nf_conntrack/parameters/
hashsize`, sinon les listes chaînées s'allongent). Puis chercher la cause :
`conntrack -L | awk '{for(i=1;i<=NF;i++) if($i~/^src=/){print $i; next}}' | sort | uniq -c | sort -rn | head` (par
source), ou par état (`conntrack -L | grep -c UNREPLIED`). Beaucoup d'UDP non
répondus = scan ou DNS en boucle ; beaucoup de `TIME_WAIT` = serveur web très
sollicité, on peut abaisser `nf_conntrack_tcp_timeout_time_wait`.
:::

::: piege
a) `conntrack -F` vide aussi les entrées des sessions NATées en cours : leurs
paquets suivants n'ont plus de traduction, ils partent avec la mauvaise adresse
et les sessions **meurent**. Sur un pare-feu stateful, ils deviennent
`invalid`. C'est le geste qui transforme un incident partiel en incident
total. d) : sans conntrack, plus de NAT du tout.
:::

---

**Q13.9** — *DNAT en `prerouting` : marche depuis `lab-web`, `Connection
refused` depuis `lab-adm` lui-même.*

**Réponse : b)** les paquets locaux passent par `output`, pas `prerouting`.

::: pourquoi
Le hook `prerouting` n'est traversé que par les paquets **reçus** sur une
interface. Un paquet généré par un processus local part de la couche socket,
passe par la décision de routage puis par `output`, puis `postrouting`. Il ne
touche jamais `prerouting`. Le `curl` local vers `10.10.10.10:8080` arrive donc
tel quel sur la pile locale, où rien n'écoute sur 8080 : `RST`, « Connection
refused ».

Correctif :

```bash
nft add chain ip nat output '{ type nat hook output priority -100; }'
nft add rule ip nat output ip daddr 10.10.10.10 tcp dport 8080 \
    dnat to 172.20.0.11:8000
```

Docker fait exactement ça : sa chaîne `DOCKER` de la table `nat` est appelée
depuis `PREROUTING` **et** depuis `OUTPUT` (avec `! --dst 127.0.0.0/8`).
:::

---

**Q13.10** — *`vxlan0` laissé en MTU 1500 au-dessus d'`ens18` en 1500.*

**Réponse : b)** ça marche pour les petits paquets, ça gèle sur les gros.

::: pourquoi
VXLAN ajoute 50 octets (14 Ethernet externe + 20 IP + 8 UDP + 8 VXLAN) devant
la trame interne. Une trame interne de 1500 octets de charge IP devient un
paquet externe de 1550 octets, plus grand que le MTU d'`ens18`. Deux issues
possibles : fragmentation IP de l'externe (par défaut, `df unset`), qui
fonctionne tant que rien ne jette les fragments mais coûte cher et casse au
premier pare-feu qui les filtre ; ou perte pure si le DF externe est posé et
que l'ICMP « fragmentation needed » n'est pas relayé au flux interne.

Les petits paquets (`ping` à 56 octets, poignée de main SSH, requêtes HTTP)
tiennent sous 1450 : tout paraît normal. Le premier segment TCP plein (MSS
1460 → 1500 octets) déclenche le problème. Le noyau **calcule** bien un MTU de
1450 quand on crée `vxlan0` avec `dev ens18`, mais un `ip link set mtu 1500` ou
une configuration Netplan avec `mtu: 1500` l'écrase.
:::

---

**Q13.11** — *`AllowedIPs` dans WireGuard.*

**Réponse : a) et b).**

::: pourquoi
WireGuard n'a pas de notion de « client » ou de « serveur », seulement des
pairs identifiés par clé publique. `AllowedIPs` est la clé de voûte du
*cryptokey routing* : en **émission**, un paquet est envoyé au pair dont
`AllowedIPs` contient la destination (c'est une table de routage interne, et
`wg-quick` pose aussi les routes noyau correspondantes) ; en **réception**, un
paquet déchiffré n'est accepté que si sa source est dans les `AllowedIPs` du
pair qui l'a envoyé, sinon il est jeté silencieusement.

`AllowedIPs = 0.0.0.0/0` côté client = « tout passe par ce pair » (VPN
complet). `AllowedIPs = 10.99.0.2/32` = seul ce pair est joignable par ce
pair. Deux pairs ne peuvent pas avoir des `AllowedIPs` qui se chevauchent sur
une même interface.
:::

::: piege
c) : l'adresse locale est `Address` dans `[Interface]`. d) : `DNS =` existe,
mais dans `[Interface]`, et c'est `wg-quick` qui l'applique via `resolvconf`,
pas le protocole.
:::

---

**Q13.12** — *`/proc/net/bonding/bond0` : actif `ens20`, `ens19` `down`,
`Link Failure Count: 1`.*

**Réponse : b)** `ens19` a perdu sa porteuse une fois, le bond a basculé.

::: pourquoi
En `active-backup`, un seul esclave transmet. `miimon` (100 ms) interroge la
porteuse de chaque esclave ; à la première perte, `Link Failure Count` de
l'esclave s'incrémente et le bond promeut un autre esclave `up`. La MAC du bond
est reprogrammée sur le nouvel actif (`fail_over_mac=none` par défaut) et un
ARP gratuit est envoyé pour que les commutateurs apprennent le nouveau port :
le trafic reprend en moins d'une seconde.

Quand `ens19` revient, le bond y retourne **si** `primary ens19` est défini et
`primary_reselect=always` (défaut) ; sinon il reste sur `ens20`.
:::

---

**Q13.13** — *Sous-interface VLAN 10 créée, mais rien ne revient : `tcpdump`* `-e vlan 10` *ne montre que les ARP sortants.*

**Réponse : b)** vérifier que `vmbr1` est VLAN-aware et que le port n'est pas
en mode access.

::: pourquoi
Un bridge Linux **non** VLAN-aware laisse passer les trames taguées telles
quelles… en principe ; mais Proxmox, sur un `vmbr` non VLAN-aware, filtre ou
retague selon la configuration du port. Avec `bridge-vlan-aware yes`, le
bridge maintient une table de VLAN par port (`bridge vlan show` sur l'hôte) :
par défaut un port n'a que le VLAN 1 non tagué (PVID) et **jette** tout tag
non autorisé. Il faut soit `bridge-vids 2-4094` sur `vmbr1` (trunk vers la
VM, elle tague elle-même), soit `tag=10` sur le port de la VM (mode access :
le bridge tague/détague, la VM ne doit **pas** créer de sous-interface).

Les deux à la fois (`tag=10` **et** `ens18.10` dans la VM) donnent du double
tag : la trame sort de la VM avec le tag 10, le bridge ajoute un second tag 10
(QinQ), et rien ne répond. C'est l'erreur classique.
:::

---

**Q13.14** — *`aa` sur `lab.local`, `REFUSED` sur un nom public.*

**Réponse : b)** un serveur faisant autorité, `recursion no`.

::: pourquoi
Le flag `aa` (authoritative answer) n'est posé que par un serveur qui sert la
zone depuis ses propres fichiers. `REFUSED` sur un nom hors zone est la réponse
correcte d'un autoritaire configuré avec `recursion no` (BIND) : il ne va pas
chercher ailleurs et le dit. Un récursif aurait répondu `NOERROR` avec le flag
`ra` et sans `aa` ; un forwarder avec un amont mort aurait répondu `SERVFAIL`
après un délai.

C'est la bonne pratique : un autoritaire exposé ne doit jamais faire de
récursion (amplification DDoS, empoisonnement de cache). Unbound et BIND
récursif restent derrière un `access-control`.
:::

---

**Q13.15** — *Enregistrement ajouté et rechargé sur le primaire, invisible sur
le secondaire trente minutes après, sans erreur.*

**Réponse : b)** serial non incrémenté.

::: pourquoi
Le secondaire n'a qu'un seul critère pour décider de transférer : le serial du
`SOA` du primaire est-il **strictement supérieur** au sien (arithmétique
modulo 2^32) ? Après un `NOTIFY` ou à chaque `refresh`, il interroge `SOA
lab.local`, compare, et s'il est égal conclut « je suis à jour » — ce n'est pas
une erreur, donc rien dans les journaux. Le primaire, lui, sert immédiatement
le nouveau fichier.

`dig +short SOA lab.local @10.10.10.14` et `@10.10.10.10` : deux serials
identiques avec des contenus différents = diagnostic fait. Correctif :
incrémenter le serial, `rndc reload`, le secondaire reçoit un NOTIFY, compare,
transfère. Prévention : format `AAAAMMJJnn`, ou `rndc` avec des zones
dynamiques où BIND gère le serial lui-même.
:::

::: piege
a) : `allow-transfer` se configure sur le **primaire** ; mal réglé, le
secondaire journalise `transfer ... failed: REFUSED`, ce serait visible.
b) : AXFR passe en **TCP** ; et un filtrage donnerait aussi une erreur.
:::

---

**Q13.16** — *Trois serveurs DNS sur le port 53 de la même machine.*

**Réponse : b)** chacun est lié à une adresse précise.

::: pourquoi
Un socket est identifié par (protocole, adresse, port). `127.0.0.53:53`,
`10.10.10.53:53` et `10.10.10.14:53` sont trois sockets distincts ; le noyau
route chaque datagramme vers celui dont l'adresse correspond à la destination.
Le conflit n'apparaît que si l'un d'eux demande `0.0.0.0:53` (`INADDR_ANY`),
qui « recouvre » toutes les adresses : `bind()` échoue alors avec
`EADDRINUSE` (Unbound : `can't bind socket: Address already in use`, BIND :
`could not listen on UDP socket`).

D'où les directives `interface:` (Unbound) et `listen-on { ...; }` (BIND)
explicites dans le lab, et le piège classique : installer `bind9` sur une
machine avec `systemd-resolved` sans toucher `listen-on` — BIND démarre
malgré tout (il se lie adresse par adresse, et `127.0.0.53` n'est l'adresse d'aucune interface), mais il prend alors aussi `10.10.10.53:53` avant Unbound; et `dnsmasq` **sans**
`bind-interfaces` (socket joker) échoue.
:::

---

**Q13.17** — *`ip -6 neigh` : `STALE`.*

**Réponse : b)** connue mais non confirmée récemment.

::: pourquoi
Neighbor Discovery (ND, RFC 4861) remplace ARP et ajoute une machine à états
par voisin : `INCOMPLETE` (résolution en cours), `REACHABLE` (confirmé il y a
moins de `base_reachable_time`, 30 s), `STALE` (l'entrée existe, on l'utilisera
mais on la re-vérifiera au prochain envoi), `DELAY`/`PROBE` (vérification en
cours), `FAILED`. IPv4 utilise la même machine (`ip neigh` montre aussi
`STALE`), simplement on la remarque moins.

`STALE` est l'état **normal** d'un voisin qu'on n'a pas contacté depuis
30 secondes. Ce n'est pas une panne ; `FAILED` en est une.
:::

---

**Q13.18** — *Interdire à `10.10.10.0/24` d'atteindre les ports publiés par
Docker, de façon durable.*

**Réponse : b)** dans `DOCKER-USER`.

::: pourquoi
Docker crée et **réécrit** ses chaînes (`DOCKER`, `DOCKER-ISOLATION-STAGE-*`)
à chaque démarrage et à chaque création de conteneur ; ce que tu y ajoutes
disparaît. `DOCKER-USER` est appelée en tête de `FORWARD`, avant tout le
reste, et Docker s'engage à ne jamais la modifier : c'est l'endroit prévu pour
les règles de l'administrateur.

```bash
iptables -I DOCKER-USER -s 10.10.10.0/24 -i ens18 -m conntrack \
  --ctstate NEW -j DROP
```

Les ports publiés sont du trafic **relayé** (DNAT vers l'IP du conteneur, puis
`FORWARD`), pas du trafic `INPUT` : c'est pour cela qu'`ufw`, qui ne filtre
qu'`INPUT`, ne les protège pas — sujet du module 22.
:::

---

## 13.4 Quiz — questions ouvertes

**QO13.1** — *Ce que fait `docker run -p 8080:80 nginx` côté réseau, sans
parler de Docker.*

**Réponse.** Au démarrage du démon, puis à chaque `run` :

1. **Un bridge** `docker0` (`172.17.0.1/16`), monté, dans le netns de l'hôte.
   À la main : `ip link add docker0 type bridge; ip addr add 172.17.0.1/16 dev
   docker0; ip link set docker0 up`.
2. **Forwarding** : `sysctl -w net.ipv4.ip_forward=1`, et chargement de
   `br_netfilter` pour que le trafic entre conteneurs passe aussi par
   `forward` (c'est ce qui permet l'isolation entre réseaux).
3. **NAT de sortie** : `nft add rule ip nat POSTROUTING ip saddr 172.17.0.0/16 oifname != "docker0" masquerade` (Docker l'écrit via
   `iptables-nft`, c'est la même chose).
4. **Chaînes de filtrage** : `FORWARD` → `DOCKER-USER` (vide, pour toi),
   `DOCKER-ISOLATION-STAGE-1/2`, `DOCKER`, puis `established,related accept`
   et `iifname docker0 oifname != docker0 accept`. Politique `FORWARD` mise à
   `DROP`.
5. À `docker run` : un **netns** (anonyme, pas dans `/run/netns` — d'où
   `nsenter -t $(docker inspect -f '{{.State.Pid}}' c) -n`), une **paire veth**
   (`vethXXXX` côté hôte, `eth0` dans le netns), le bout hôte mis `master
   docker0`, `lo` monté, adresse `172.17.0.2/16`, route par défaut via
   `172.17.0.1`. À la main : `ip netns add c; ip link add veth-c type veth peer
   name eth0 netns c; ip link set veth-c master docker0 up; ip -n c link set lo
   up; ip -n c addr add 172.17.0.2/16 dev eth0; ip -n c link set eth0 up; ip -n
   c route add default via 172.17.0.1`.
6. `-p 8080:80` : dans `nat`, `DOCKER` reçoit `tcp dport 8080 dnat to
   172.17.0.2:80`, appelée depuis `PREROUTING` (trafic entrant) **et**
   `OUTPUT` (trafic local, hors `127.0.0.0/8`) ; dans `filter`, `DOCKER` reçoit
   `ip daddr 172.17.0.2 tcp dport 80 ct state new accept` ; en `POSTROUTING`,
   un `masquerade` pour le hairpin (`ip saddr 172.17.0.2 ip daddr 172.17.0.2
   tcp dport 80`). Et `docker-proxy` écoute sur `0.0.0.0:8080` en secours
   (pour `localhost` en IPv6 et les cas sans NAT).

::: pourquoi
Rien de tout cela n'est spécifique à Docker : ce sont les primitives du noyau
que ce module manipule. La valeur ajoutée de Docker est de faire tout ça de
façon cohérente, idempotente et de le défaire au `stop`. Savoir le rejouer à
la main, c'est savoir lire `docker network inspect` et `nft list ruleset`
quand un port publié ne répond pas, et c'est exactement ce qu'un CNI
Kubernetes (bridge, flannel) fait aussi, avec en plus un overlay pour joindre
les autres nœuds.
:::

---

**QO13.2** — *Chemin d'un paquet TCP entrant sur `ens18` vers un netns via
DNAT.*

**Réponse.**

1. Le paquet (`10.10.10.11:40000 → 10.10.10.10:8080`) arrive sur `ens18`,
   pilote, puis hook **`prerouting`**. Priorité `-200` : **conntrack** le
   regarde ; aucune entrée → il crée une entrée provisoire en état `new`.
   Priorité `-100` (`dstnat`) : la chaîne `prerouting` de la table `nat` est
   consultée **uniquement pour ce premier paquet du flux** ; la règle `dnat to
   172.20.0.11:8000` matche, la destination est réécrite, et la traduction est
   enregistrée dans l'entrée conntrack (tuple de réponse : `172.20.0.11:8000
   → 10.10.10.11:40000`).
2. **Décision de routage** sur la destination réécrite : `172.20.0.11` est
   dans `172.20.0.0/24 dev br-lab` → ce n'est pas pour moi → hook
   **`forward`**. Là, la chaîne `forward` de `filter` : `ct status dnat
   accept` (ou `established,related` pour les paquets suivants) laisse passer.
3. Hook **`postrouting`** : conntrack confirme l'entrée ; `srcnat` (100) : la
   règle `masquerade` ne matche pas (`oifname` est `br-lab`, pas `ens18`),
   la source reste `10.10.10.11`. Le paquet est commuté par le bridge vers
   `veth-c1`, arrive dans `c1` sur `eth0`, où le serveur écoute sur 8000.
4. Retour : `c1` répond `172.20.0.11:8000 → 10.10.10.11:40000`, route par
   défaut via `172.20.0.1`, arrive sur `br-lab` côté racine → `prerouting`
   : conntrack retrouve l'entrée (c'est le tuple de réponse), état
   `established`, et applique **l'inverse** de la traduction : source réécrite
   en `10.10.10.10:8080`. Pas de consultation des règles `nat`. Routage →
   `forward` (`established,related accept`) → `postrouting` → `ens18`.
5. Tous les paquets suivants, dans les deux sens, sont traduits par conntrack
   seul : les règles `nat` ne sont plus lues. `nft monitor trace` le montre :
   pour le deuxième paquet, la chaîne `nat prerouting` n'apparaît pas.

::: pourquoi
Deux idées à retenir : le **DNAT se fait avant le routage** (sinon le noyau
déciderait « c'est pour moi » et enverrait le paquet en `input`), le **SNAT
après** (sinon on ne connaîtrait pas l'interface de sortie) ; et le NAT est
une **propriété du flux** stockée dans conntrack, pas une règle appliquée à
chaque paquet. C'est pourquoi `conntrack -F` casse le NAT, et pourquoi une
règle `nat` modifiée n'affecte pas les flux en cours.
:::

---

**QO13.3** — *Deux interfaces, deux passerelles : ping OK, TCP échoue.*

**Réponse.** Mécanisme : un client de B envoie un SYN à l'adresse de
l'interface B du serveur. Le serveur répond, et pour choisir la sortie il
consulte sa table `main` : une seule route par défaut, via la passerelle A.
Le SYN-ACK sort donc par l'interface A avec la source « adresse B ». Trois
choses cassent alors, selon le réseau :

* la passerelle A ne sait pas router vers B (réseau isolé) → réponse perdue,
  le client ré-émet, timeout ;
* la passerelle A route bien, mais le **pare-feu stateful** de B voit un
  SYN-ACK arriver par un chemin où il n'a jamais vu le SYN : `invalid`, jeté.
  Le `ping` passe parce qu'ICMP echo est souvent autorisé sans état, ou parce
  qu'il emprunte un autre chemin ;
* le serveur lui-même, avec `rp_filter=1`, jette les paquets reçus sur B si
  sa route vers la source pointe sur A.

Correctif (réponse par l'interface d'arrivée) :

```bash
sudo mkdir -p /etc/iproute2/rt_tables.d
echo "200 viab" | sudo tee /etc/iproute2/rt_tables.d/lab.conf
ip route add 10.10.12.0/24 dev eth2 src 10.10.12.2 table viab
ip route add default via 10.10.12.1 dev eth2 table viab
ip rule add from 10.10.12.2 table viab priority 100
```

Preuve sans paquet : `ip route get 192.168.2.10 from 10.10.12.2`
doit répondre `via 10.10.12.1 dev eth2`, alors que `ip route
get 192.168.2.10` (source par défaut) répond `via 10.10.11.1 dev eth1`. Pas de `iif` ici : la réponse est émise **localement**; `from <adresse locale> iif eth2` simulerait un paquet **reçu** portant l'adresse de la machine en source, que le noyau refuse (erreur `RTNETLINK answers: ...`).

::: pourquoi
La règle `from` fait le lien entre l'adresse **source** du paquet de réponse
(qui est l'adresse de l'interface par laquelle la requête est arrivée, puisque
le socket répond avec l'adresse à laquelle on lui a parlé) et la table qui
mène à la passerelle de ce côté. Persistant sous Netplan : `routes:` avec
`table: 200` et `routing-policy: - from: 10.10.12.2 / table: 200`.
:::

---

**QO13.4** — *`established,related accept` vs règle sans état, `related`,
`invalid`, perte de la table conntrack.*

**Réponse.** Une règle sans état `tcp sport 80 accept` laisse entrer **tout**
paquet dont le port source est 80, y compris un SYN forgé par un attaquant qui
a choisi ce port source : c'est une porte ouverte sur tous les ports locaux.
`ct state established` n'accepte que les paquets qui **appartiennent à un flux
que cette machine a vu s'initier** (dans le bon sens), quel que soit le port.
Le pare-feu devient directionnel : « je décide qui initie, les réponses
suivent ».

`related` couvre les paquets d'un **nouveau** flux logiquement lié à un flux
existant : les erreurs ICMP (`destination unreachable`, `fragmentation
needed`, `time exceeded`) qui citent un flux tracé — indispensable pour la
découverte de MTU —, et les flux secondaires reconnus par un *helper*
(FTP-data, SIP/RTP, TFTP), que `nf_conntrack_helper` doit avoir chargés.

`invalid` : un paquet que conntrack ne peut rattacher à rien de cohérent :
ACK sans connexion (souvent des restes après reboot du pare-feu), segment
hors fenêtre TCP, ICMP d'erreur qui ne cite aucun flux, en-tête tronqué. On
les jette explicitement (`ct state invalid drop`) avant les règles `accept`
larges, sinon un `tcp dport 80 accept` les laisserait passer.

Perte de la table : un flux **NATé** dépend de l'entrée conntrack pour la
réécriture ; sans elle, le paquet suivant part avec l'adresse privée, ou
arrive sans être traduit → session morte. Un flux **non NATé** traversant un
pare-feu stateful est jeté comme `invalid` jusqu'à ce que TCP réémette… mais
`nf_conntrack_tcp_loose=1` (défaut) permet à conntrack de « recoller » un flux
en cours à partir d'un ACK, donc il reprend. Un flux non NATé sur une machine
sans pare-feu ne remarque rien.

::: pourquoi
Le pare-feu stateful transforme un problème de « quels ports autoriser dans
chaque sens » en « qui a le droit d'initier ». C'est la seule façon d'écrire
une politique lisible avec des ports éphémères. Le prix : une table en mémoire
(`nf_conntrack_max`), des timeouts à connaître, et une sensibilité aux chemins
asymétriques (QO13.3).
:::

---

**QO13.5** — *DNAT qui marche de l'extérieur, pas depuis le LAN interne :
hairpin.*

**Réponse.** Situation : client `172.20.0.12` (même segment que le serveur
`172.20.0.11`), DNAT `10.10.10.10:8080 → 172.20.0.11:8000` sur le routeur.

* SYN : `172.20.0.12 → 10.10.10.10:8080`, envoyé au routeur (adresse hors
  segment). `prerouting` : DNAT → `172.20.0.12 → 172.20.0.11:8000`, routage
  → `forward` → renvoyé sur le **même** bridge vers le serveur. Source
  inchangée.
* SYN-ACK : le serveur voit une connexion venant de `172.20.0.12`, qui est
  sur son segment : il répond **directement**, `172.20.0.11:8000 →
  172.20.0.12`, sans passer par le routeur. Le client reçoit un SYN-ACK de
  `172.20.0.11:8000` alors qu'il a parlé à `10.10.10.10:8080` : aucun socket ne
  correspond, il répond `RST`. Le routeur, lui, n'a jamais vu le retour : son
  entrée conntrack reste `UNREPLIED`.

Solutions :

1. **SNAT de retour** (hairpin NAT) : en `postrouting`, pour les paquets
   DNATés dont source et destination sont sur le segment interne, réécrire la
   source en celle du routeur : `ip saddr 172.20.0.0/24 ip daddr 172.20.0.11
   tcp dport 8000 ct status dnat masquerade`. Le serveur répond alors au
   routeur, qui détraduit les deux adresses. Prix : le serveur ne voit plus
   l'adresse réelle du client.
2. **Split-horizon DNS** : les clients internes résolvent le nom vers
   `172.20.0.11` directement (vue interne), les externes vers `10.10.10.10`.
   Pas de NAT en boucle, adresses réelles conservées ; c'est la solution propre
   quand on contrôle le DNS.

::: pourquoi
Le DNAT ne réécrit que la destination ; il suppose que le retour repassera par
le routeur, ce qui n'est vrai que si le serveur ne peut pas joindre le client
directement. Docker ajoute la règle de hairpin systématiquement (`MASQUERADE`
avec `-s 172.17.0.2 -d 172.17.0.2`), Kubernetes l'expose sous le nom
`hairpinMode` dans le CNI bridge.
:::

---

**QO13.6** — *VXLAN, GRE, IPIP, WireGuard : comparaison et lien avec
Kubernetes.*

**Réponse.**

| Tunnel | Encapsule | Porteur / surcoût | Chiffré |
|---|---|---|---|
| VXLAN | trame Ethernet (L2) | UDP 4789, 50 o | non |
| GRE | paquet IP (ou autre, L3) | IP proto 47, 24 o | non |
| IPIP | paquet IPv4 seulement | IP proto 4, 20 o | non |
| WireGuard | paquet IP (L3) | UDP, 60-80 o | oui (ChaCha20) |

Usages : VXLAN pour étendre un L2 (VM qui migrent, multi-locataire avec
16 M de VNI, overlay Kubernetes) ; GRE pour transporter du multicast ou du
non-IP entre routeurs, ou comme support d'un IPsec ; IPIP quand on veut le
surcoût minimal entre deux hôtes IPv4 (Calico par défaut) ; WireGuard pour
tout ce qui traverse un réseau non fiable (VPN, liaisons inter-sites, Cilium
et Calico en mode chiffré).

Kubernetes : avec flannel en backend `vxlan`, chaque nœud a une interface
`flannel.1` de type VXLAN (VNI 1, port 8472 chez flannel), un bridge `cni0`
pour ses pods (`10.244.N.0/24`), et une route `10.244.M.0/24 via 10.244.M.0
dev flannel.1 onlink` par nœud distant. flannel remplit `bridge fdb` et `ip
neigh` de `flannel.1` avec la MAC et l'IP de chaque nœud (pas de multicast ni
d'apprentissage : tout vient de l'API). Le MTU de `cni0` et des pods est 1450
parce que le MTU du nœud est 1500 et que VXLAN prend 50 octets ; un pod qui
envoie 1500 fabriquerait des paquets externes de 1550, fragmentés ou jetés —
c'est le lab L13.3 en plus grand.

::: pourquoi
Comprendre qu'un CNI n'est qu'un script qui crée ces objets (et un agent qui
maintient les tables) désacralise Kubernetes : `ip -d link show flannel.1`,
`bridge fdb show dev flannel.1` et `ip route` sur un nœud racontent tout.
:::

---

**QO13.7** — *Autoritaire, récursif, forwarder, cache ; qui répond à quoi dans
le lab.*

**Réponse.**

* **Autoritaire** : détient les données d'une zone, répond avec `aa`, ne
  cherche jamais ailleurs, ne fait pas de récursion (`ra` absent, `REFUSED`
  ou réponse de délégation pour le reste).
* **Récursif** : reçoit une question avec `rd`, part des serveurs racine
  (`root hints`), suit les délégations (`.com` → `ubuntu.com` → réponse),
  valide DNSSEC, met tout en cache, répond avec `ra` et sans `aa`.
* **Forwarder** : accepte des requêtes récursives mais les délègue à un autre
  récursif au lieu de résoudre lui-même ; il cache aussi. Moins de trafic
  sortant, dépendance à l'amont.
* **Cache** : n'importe lequel des précédents, vu par la décroissance du TTL ;
  le stub `systemd-resolved` est un cache pur devant le serveur configuré.

`www.ubuntu.com` depuis `lab-web` : `getaddrinfo` → stub `127.0.0.53` (cache ?)
→ Unbound `10.10.10.53` (cache ?) → racine (`.`), puis un serveur de `com.`,
puis un serveur autoritaire de `ubuntu.com` → réponse, cachée par Unbound puis
par le stub. `dig @10.10.10.53 www.ubuntu.com` : `qr rd ra`, pas de `aa`,
éventuellement `ad` si la zone est signée ; deuxième appel : TTL plus bas.
`dig +trace` reproduit la descente.

`lab-db.lab.local` : stub → Unbound → **stub-zone** `lab.local` → `ns1`
(`10.10.10.14`) ou `ns2` (`10.10.10.10`), autoritaires → réponse `aa` du
côté de BIND, relayée sans `aa` par Unbound (`dig @10.10.10.14` montre `aa`,
`dig @10.10.10.53` non). `dig +trace lab-db.lab.local` **échoue** : la racine
ne connaît pas `local`, ce nom n'existe que dans notre îlot.

::: pourquoi
CoreDNS reproduit cette architecture dans un seul processus : plugin `kubernetes`
= autoritaire pour `cluster.local`, plugin `forward` = forwarder vers
`/etc/resolv.conf` du nœud (donc vers Unbound ici), plugin `cache`. Quand un
pod ne résout pas un nom externe, la question est « qui est l'amont de CoreDNS
et répond-il » — exactement BF13.6.
:::

---

**QO13.8** — *Transfert de zone : mécanisme, expiration, erreurs silencieuses.*

**Réponse.** Mécanisme :

1. Le primaire charge une zone dont le serial a changé → envoie un **NOTIFY**
   (UDP 53) aux NS de la zone et aux `also-notify`.
2. Le secondaire répond, puis interroge `SOA` chez le primaire, compare le
   serial reçu au sien. Supérieur → il demande **AXFR** (TCP 53, zone
   entière) ou **IXFR** (incrémental, si le primaire tient un journal). Égal
   ou inférieur → rien.
3. Sans NOTIFY, le secondaire vérifie de lui-même toutes les `refresh` s
   (3600 dans notre SOA) ; si le primaire ne répond pas, il réessaie toutes les
   `retry` s (900) ; si ça dure plus de `expire` s (1 209 600 = 14 jours), le
   secondaire **cesse de servir la zone** et répond `SERVFAIL` : mieux vaut ne
   rien dire que servir des données peut-être fausses.

Primaire absent deux semaines : jusqu'à `expire`, le secondaire sert la
dernière copie (c'est tout l'intérêt d'un secondaire) ; après, `SERVFAIL`.
D'où les valeurs d'`expire` longues (2 à 4 semaines) sur les zones critiques.

Trois erreurs silencieuses :

* serial non incrémenté (Q13.15) ;
* `allow-transfer` absent ou mauvaise IP : le NOTIFY arrive, l'AXFR est
  `REFUSED`, mais c'est le secondaire qui le journalise, pas le primaire — on
  ne regarde jamais le bon journal ;
* `notify explicit` sans `also-notify`, ou NS de la zone pointant vers des
  adresses où le secondaire n'écoute pas : le secondaire ne sera à jour qu'au
  prochain `refresh`, ce qui ressemble à « ça marche, avec une heure de retard ».

Bonus : répertoire de destination non inscriptible pour l'utilisateur `bind`
(`/etc/bind/` au lieu de `/var/cache/bind/`) — AppArmor refuse, le transfert
est reçu puis perdu, `journalctl -u named` le dit.

::: pourquoi
Un secondaire n'est pas une copie « temps réel » : c'est un cache avec un
protocole de rafraîchissement dont les paramètres sont **dans la zone
elle-même** (le SOA). Lire un SOA, c'est lire le contrat de réplication.
:::

---

**QO13.9** — *« Désactiver IPv6 partout ».*

**Réponse.** Sans aucune configuration, un hôte Linux : fabrique une adresse
link-local `fe80::/64` sur chaque interface (dérivée de la MAC ou aléatoire),
rejoint les groupes multicast de sollicitation, fait de la découverte de
voisins (ND, `ip -6 neigh`), écoute les Router Advertisements (`accept_ra=1`)
et, s'il en reçoit, se configure une adresse globale par SLAAC et une route
par défaut. Sans routeur v6, il n'a que sa link-local : inoffensif, et utile.

Utile à quoi : Docker et Kubernetes en dual-stack, mais aussi des services
qui écoutent sur `::` (`ss -tlnp` montre `*:22` en v6, qui accepte aussi le v4
grâce aux adresses mappées), `localhost` qui résout en `::1` en premier, les
tests `curl` qui essaient AAAA avant A. Avec `disable_ipv6=1` : `::1`
disparaît, tout ce qui se lie à `::1` échoue (`bind: Cannot assign requested
address` dans nginx, PostgreSQL, sshd si `ListenAddress ::`), `localhost`
ne résout plus qu'en v4, certains tests d'intégration tombent, et des
`sysctl` v6 posés plus tard sont ignorés. Le paramètre est aussi remis à 0 par
certains outils réseau au redémarrage d'interface.

À la place : laisser IPv6 actif ; si le réseau n'a pas de v6 routé, ne pas
s'en préoccuper ; s'il faut de l'adressage interne, un ULA (`fd00:10:10:10::/64`)
posé par Netplan ; sur un serveur exposé, `accept_ra=0` (on ne prend pas ses
routes de n'importe quel RA) et un pare-feu `inet` qui traite v4 et v6 dans
les mêmes règles — c'est précisément l'intérêt de la famille `inet` dans
nftables.

::: pourquoi
« On ne s'en sert pas » est presque toujours faux : le système s'en sert.
Désactiver une pile entière pour ne pas la comprendre remplace un risque
maîtrisable (filtrer v6 comme v4) par des pannes surprenantes.
:::

---

**QO13.10** — *9,4 Gbit/s direct, 5,1 en VXLAN, 1,8 en WireGuard : d'où
viennent les écarts.*

**Réponse.**

* **Direct** : virtio-net avec TSO/GSO/GRO : le noyau envoie des « super
  paquets » de 64 ko au pilote, qui les découpe (ou l'hôte le fait) ; peu
  d'interruptions, peu de copies. `ethtool -k ens18` les montre `on`.
* **VXLAN** : chaque trame est encapsulée (copie d'en-têtes, calcul de somme
  UDP), et surtout la segmentation ne peut plus être déléguée telle quelle :
  sans offload « tunnel-aware » (`tx-udp_tnl-segmentation`), le noyau segmente
  en logiciel à 1450 octets, d'où quatre fois plus de paquets à traiter par
  CPU. `top` montre la colonne `si` (softirq) qui grimpe, `ethtool -S` et
  `nstat` montrent le nombre de paquets exploser. MTU 1450 au lieu de 1500 :
  3 % de charge utile en moins, marginal. On regagne beaucoup avec des jumbo
  frames sur l'underlay (`ens18` à 9000, `vxlan0` à 8950) : les VM du lab le
  permettent si `vmbr1` est à 9000.
* **WireGuard** : chiffrement ChaCha20-Poly1305 de chaque paquet, sur un seul
  cœur par flux (le lab a 2 vCPU), plus la même perte d'offloads, plus un MTU
  de 1420. `top` montre un `kworker`/`wg-crypt` saturé. On gagne avec plus de
  cœurs, plusieurs flux parallèles (`iperf3 -P 4`), et AES-NI ne sert à rien
  (WireGuard n'utilise pas AES).

Confirmer : `iperf3` avec `-P 4` (le débit WireGuard monte si c'est le CPU),
`mpstat -P ALL 1` pendant le test, `ethtool -S ens18 | grep -i -E 'tso|gso'`,
et `nstat -az IpOutRequests` avant/après pour compter les paquets réellement
émis.

Réglages sans changer de technologie : jumbo frames sur l'underlay,
`ethtool -K` pour vérifier que GRO/GSO restent actifs sur l'interface tunnel,
plus de vCPU, RSS/multiqueue virtio (`ethtool -l ens18`), et pour WireGuard
accepter le coût ou ne chiffrer que ce qui en a besoin.

::: pourquoi
Le débit d'un tunnel n'est pas limité par le « réseau » mais par le nombre de
paquets par seconde que le CPU peut encapsuler ou chiffrer. C'est pour cela
que les CNI proposent des modes sans overlay (Calico BGP, Cilium native
routing) quand l'infrastructure le permet.
:::

---

## 13.5 Exercices guidés

**E13.1** — *Compteurs détaillés, offloads, anneaux, files d'`ens18`.*

```bash
ip -s -s link show ens18        # deux -s : sous-compteurs RX errors
sudo ethtool -S ens18           # statistiques du pilote
ethtool -k ens18                # offloads (tso, gso, gro, rx-checksum...)
sudo ethtool -g ens18           # tailles d'anneaux RX/TX
sudo ethtool -l ens18           # nombre de files (combined)
ethtool ens18                   # vitesse, duplex, lien
```

Sur virtio : `ethtool ens18` répond `Speed: Unknown!` et `Duplex: Unknown!`
(pas de couche physique à interroger), et `ethtool -S` n'a que des compteurs
par file (`rx_queue_0_packets`…), pas de `rx_missed`. `ethtool -g` et `-l`
fonctionnent (anneaux de 256, `combined` égal au nombre de vCPU au mieux).

::: pourquoi
`ip -s -s link` distingue `errors` (trame corrompue), `dropped` (jetée par le
noyau faute de buffer), `missed` (jetée par la carte, anneau plein) et
`overrun`. Un `rx_missed` qui grimpe = anneau trop petit ou CPU qui ne vide
pas assez vite les softirq : `ethtool -G ens18 rx 1024` et/ou plus de files.
Les offloads expliquent des captures étranges : avec TSO, `tcpdump` sur
l'émetteur montre des segments de 64 ko et des sommes de contrôle
« incorrect » (calculées plus tard par la carte). Ce n'est pas une panne.
:::

---

**E13.2** — *200 ms et 10 % de perte sur `lo`, prouver, retirer.*

```bash
sudo tc qdisc add dev lo root netem delay 200ms loss 10%
ping -c 20 127.0.0.1          # rtt ~400 ms, ~2 paquets perdus
sudo tc -s qdisc show dev lo  # compteurs dropped
sudo tc qdisc del dev lo root
ping -c 3 127.0.0.1           # rtt ~0.03 ms
```

::: pourquoi
`netem` est une discipline de file d'attente (qdisc) posée à la **sortie**
d'une interface. Sur `lo`, l'aller et le retour sortent tous deux par `lo` :
chaque sens prend 200 ms, le RTT observé est 400 ms, et la perte de 10 % par
sens donne environ 19 % de pertes au total (`1 - 0,9²`). C'est le piège de
tout test sur `lo` ou sur une paire veth dont on dégrade les deux bouts.

`tc qdisc del dev lo root` remet la qdisc par défaut (`noqueue` sur `lo`,
`fq_codel` sur une carte). `netem` sait aussi faire `delay 100ms 20ms
distribution normal`, `reorder 25%`, `corrupt 1%`, `rate 10mbit` : c'est
l'outil pour reproduire en lab un lien WAN pourri et voir comment
l'application réagit avant que la prod ne le fasse à ta place.
:::

---

**E13.3** — *Deux netns reliés par veth, et preuve d'isolation.*

```bash
sudo ip netns add bleu; sudo ip netns add rouge
sudo ip link add v-bleu type veth peer name v-rouge
sudo ip link set v-bleu netns bleu; sudo ip link set v-rouge netns rouge
sudo ip -n bleu addr add 10.0.0.1/24 dev v-bleu
sudo ip -n rouge addr add 10.0.0.2/24 dev v-rouge
for n in bleu rouge; do sudo ip -n $n link set lo up; done
sudo ip -n bleu link set v-bleu up; sudo ip -n rouge link set v-rouge up
sudo ip netns exec bleu ping -c 2 10.0.0.2
# isolation
sudo ip -n bleu link          # lo + v-bleu, pas d'ens18
sudo ip -n bleu route         # une seule ligne : 10.0.0.0/24 dev v-bleu
sudo ip netns exec bleu nft list ruleset    # vide, même si l'hôte en a
sudo ip netns exec bleu ss -tlnp            # vide, pas de sshd
```

::: pourquoi
Un netns est une copie vierge de toute la pile réseau : la liste
d'interfaces, la table de routage, les règles `ip rule`, netfilter et
conntrack, la table de voisinage, les sockets, et même `/proc/sys/net`
(`ip netns exec bleu sysctl net.ipv4.ip_forward` est indépendant). Ce qui
n'est **pas** isolé : les processus (tu vois le `ping` dans `ps` de l'hôte),
les fichiers, les utilisateurs. `ip netns exec` fait un `setns()` puis
monte un `/etc/netns/bleu/` éventuel par-dessus `/etc/` (utile pour un
`resolv.conf` différent par namespace).

Une veth transmet une trame d'un bout à l'autre sans passer par aucun
bridge : c'est un câble. L'état `LOWER_UP` d'un bout dépend de l'autre :
tant que `v-rouge` est down, `v-bleu` affiche `NO-CARRIER`.
:::

---

**E13.4** — *`nsenter`, serveur HTTP dans `bleu`, retrouver son namespace.*

```bash
sudo nsenter --net=/run/netns/bleu \
  python3 -m http.server 8000 --bind 10.0.0.1 >/dev/null 2>&1 &
sudo ip netns exec rouge curl -s http://10.0.0.1:8000/ | head -3
ss -tlnp | grep 8000                        # rien dans le netns racine
PID=$(pgrep -f 'http.server 8000')
sudo readlink /proc/$PID/ns/net             # net:[4026532xxx]
sudo stat -L -c %i /run/netns/bleu /proc/$PID/ns/net   # inodes identiques
sudo ip netns identify $PID                 # bleu
sudo ip netns pids bleu                     # liste des PID dedans
```

::: pourquoi
`/run/netns/bleu` est un **bind mount** du fichier `/proc/<pid>/ns/net` du
processus qui a créé le namespace ; il garde le namespace vivant même sans
processus dedans. `nsenter --net=<fichier>` et `ip netns exec` appellent tous
deux `setns()` sur ce descripteur. Un netns Docker n'est pas dans
`/run/netns/` (Docker le garde dans `/var/run/docker/netns/`), d'où
`nsenter -t <pid du conteneur> -n` pour y entrer.

Comparer les inodes (`stat -L -c %i`) est la preuve formelle qu'un processus
est dans tel namespace ; `lsns -t net` fait la synthèse.
:::

---

**E13.5** — *Bridge `br-lab`, trois netns, table de transfert.*

```bash
sudo ip link add br-lab type bridge
sudo ip addr add 172.20.0.1/24 dev br-lab; sudo ip link set br-lab up
for i in 1 2 3; do
  sudo ip netns add c$i
  sudo ip link add veth-c$i type veth peer name eth0 netns c$i
  sudo ip link set veth-c$i master br-lab up
  sudo ip -n c$i link set lo up
  sudo ip -n c$i addr add 172.20.0.1$i/24 dev eth0
  sudo ip -n c$i link set eth0 up
  sudo ip -n c$i route add default via 172.20.0.1
done
sudo ip netns exec c1 ping -c 2 172.20.0.12
bridge link show                    # veth-c1 state forwarding ...
bridge fdb show br br-lab | grep -v permanent
```

Sortie typique de la `fdb` : `xx:xx:xx:xx:xx:xx dev veth-c1 master br-lab`
(MAC de `eth0` de `c1`, apprise sur le port `veth-c1`), idem pour `c2`, avec
un `ageing` (délai avant oubli, 300 s). Les entrées `permanent` sont les MAC
propres des ports et du bridge.

::: pourquoi
Le bridge Linux est un commutateur apprenant : à chaque trame reçue sur un
port, il note « cette MAC source est derrière ce port » (`fdb`, *forwarding
database*), et pour une destination inconnue il inonde tous les ports
(*flooding*). `bridge link show` donne l'état STP de chaque port
(`forwarding`) ; STP est désactivé par défaut (`stp_state 0`) : sur un bridge
sans boucle physique il ne sert à rien, et l'activer ajoute 30 s de
convergence à chaque nouveau port (c'est pourquoi Proxmox le laisse à `off`
et pourquoi Docker aussi).

`peer name eth0 netns c1` crée le second bout directement dans `c1` : on
évite l'étape `ip link set ... netns` et la collision de noms (`eth0` existe
dans chaque netns, jamais dans le racine).
:::

---

**E13.6** — *Depuis `c1`, joindre `lab-web` : forwarding, NAT, capture,
conntrack.*

Symptôme 1 : `ip netns exec c1 ping 10.10.10.11` est muet. Sur `lab-adm`,
`tcpdump -i br-lab icmp` montre les requêtes arriver, `tcpdump -i ens18 icmp`
ne montre rien : le routeur ne relaie pas.

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

Symptôme 2 : `tcpdump -i ens18 icmp` montre maintenant `172.20.0.11 >
10.10.10.11` partir, mais aucune réponse : `lab-web` répond vers
`172.20.0.11`, adresse qu'il route vers sa passerelle `10.10.10.1`, qui la
jette.

```bash
sudo nft add table ip nat
sudo nft add chain ip nat postrouting \
  '{ type nat hook postrouting priority 100; }'
sudo nft add rule ip nat postrouting ip saddr 172.20.0.0/24 \
  oifname "ens18" masquerade
sudo tcpdump -i ens18 -nn icmp -c 4   # 10.10.10.10 > 10.10.10.11 : réécrit
sudo conntrack -L -p icmp
```

Entrée conntrack : `icmp 1 29 src=172.20.0.11 dst=10.10.10.11 type=8 code=0
id=1234 src=10.10.10.11 dst=10.10.10.10 type=0 code=0 id=1234`. Premier
tuple : le paquet original ; second : la réponse attendue, adressée à
`10.10.10.10` — la preuve du NAT.

::: pourquoi
Deux conditions indépendantes pour qu'un Linux serve de routeur NAT :
**relayer** (`ip_forward`, décision noyau, sinon le paquet est jeté en
silence après `prerouting`) et **traduire** (`masquerade`, sinon le retour
n'a pas de chemin). L'ordre des symptômes est toujours le même : d'abord
« rien ne sort », puis « ça sort, rien ne revient ». `masquerade` choisit
comme nouvelle source l'adresse de l'interface de sortie au moment du
paquet (utile en DHCP) ; `snat to 10.10.10.10` fait pareil avec une adresse
fixe et coûte un peu moins.
:::

---

**E13.7** — *Toutes les tables, la table `local`, routes `onlink`.*

```bash
ip route show table all
ip route show table local
```

Trois lignes de `local` :

* `local 10.10.10.10 dev ens18 proto kernel scope host src 10.10.10.10` : « cette
  adresse est à moi », c'est ce qui envoie le paquet en `input` ;
* `broadcast 10.10.10.255 dev ens18 proto kernel scope link src 10.10.10.10` :
  destination de diffusion du segment ;
* `local 127.0.0.0/8 dev lo proto kernel scope host src 127.0.0.1` : **tout**
  `127.x.y.z` est local, pas seulement `127.0.0.1` (d'où `127.0.0.53`).

```bash
sudo ip route add 10.10.30.0/24 via 10.10.10.99 dev ens18
# accepté : 10.10.10.99 est dans un réseau connecté, même s'il n'existe pas
sudo ip route add 10.10.31.0/24 via 192.0.2.1 dev ens18
# RTNETLINK answers: Network is unreachable (192.0.2.1 hors réseau connecté)
sudo ip route add 10.10.31.0/24 via 192.0.2.1 dev ens18 onlink
# accepté : onlink = "fais-moi confiance, il est sur ce lien"
ip route get 10.10.30.5      # via 10.10.10.99 ; l'ARP échouera plus tard
sudo ip route del 10.10.30.0/24; sudo ip route del 10.10.31.0/24
```

::: pourquoi
Le noyau ne vérifie **pas** qu'une passerelle répond, seulement qu'elle est
joignable en L2, c'est-à-dire qu'une route connectée (`scope link`) la
couvre. `onlink` désactive cette vérification : indispensable quand la
passerelle est sur le lien mais hors du préfixe (liaisons `/32` chez certains
hébergeurs, routes de flannel `via 10.244.2.0 dev flannel.1 onlink`). La table
`local` est gérée par le noyau seul ; c'est elle qui explique pourquoi une
adresse ajoutée par `ip addr add` est immédiatement « locale » sans que `ip
route` (table `main`) ne change de façon visible.
:::

---

**E13.8** — *Table `secours`, marque `0x5`, routage par marque.*

```bash
sudo mkdir -p /etc/iproute2/rt_tables.d
echo "150 secours" | sudo tee /etc/iproute2/rt_tables.d/secours.conf
sudo ip route add default via 172.20.0.13 dev br-lab table secours
sudo ip rule add fwmark 0x5 table secours priority 100
sudo nft add table inet mangle
sudo nft add chain inet mangle output \
  '{ type route hook output priority -150; }'
sudo nft add rule inet mangle output ip daddr 198.51.100.0/24 \
  meta mark set 0x5
ip route get 198.51.100.7 mark 0x5    # via 172.20.0.13 dev br-lab
ip route get 198.51.100.7             # via 10.10.10.1 dev ens18 (sans marque)
ip route get 9.9.9.9 mark 0x5         # via 172.20.0.13 aussi : la règle ne
                                      # regarde que la marque, pas la dest.
ping -c1 -W1 198.51.100.7             # part vers c3 (qui ne relaie pas : muet)
# nettoyage
sudo nft delete table inet mangle
sudo ip rule del fwmark 0x5 table secours
sudo ip route flush table secours
sudo rm /etc/iproute2/rt_tables.d/secours.conf
```

::: pourquoi
`ip route get` accepte `mark` pour simuler un paquet marqué : c'est la seule
façon de tester une politique par marque sans trafic. La chaîne est de type
**`route`** sur le hook `output` : après un changement de marque, le noyau
refait la décision de routage (sinon la marque posée après le routage
initial n'aurait aucun effet sur le trafic local). Pour du trafic **relayé**,
on marque en `prerouting` (type `filter` suffit, le routage vient après).
`ip route get 9.9.9.9 mark 0x5` rappelle que la règle `fwmark` est aveugle :
c'est la règle nftables qui porte la sélectivité, pas `ip rule`.
:::

---

**E13.9** — *VLAN 20 sur `ens18`, tag visible au `tcpdump`, Netplan.*

```bash
sudo ip link add link ens18 name ens18.20 type vlan id 20
sudo ip addr add 10.10.20.10/24 dev ens18.20
sudo ip link set ens18.20 up
ip -d link show ens18.20        # vlan protocol 802.1Q id 20 <REORDER_HDR>
sudo tcpdump -i ens18 -nn -e -c 2 vlan 20 &
ping -c 2 -W1 10.10.20.99
```

Sortie `tcpdump` : `bc:24:11:.. > ff:ff:ff:ff:ff:ff, ethertype 802.1Q
(0x8100), length 46: vlan 20, p 0, ethertype ARP (0x0806), Request who-has
10.10.20.99 tell 10.10.20.10`.

```yaml
# /etc/netplan/60-vlan.yaml
network:
  version: 2
  vlans:
    ens18.20:
      id: 20
      link: ens18
      addresses: [10.10.20.10/24]
```

```bash
sudo ip link del ens18.20
```

::: pourquoi
La sous-interface insère un en-tête 802.1Q (4 octets : TPID `0x8100`, PCP,
VID) entre l'adresse source et l'ethertype : `-e` le rend visible, et le
filtre `vlan 20` ne matche que les trames taguées 20. Capturer sur `ens18`
(parent) montre le tag ; capturer sur `ens18.20` montre la trame déjà
détaguée. Attention avec un offload `rx-vlan-offload on` : la carte retire
le tag avant le noyau, et `tcpdump -i ens18` ne le montre plus (il apparaît
dans les métadonnées, `tcpdump -e` le reconstruit) — virtio ne le fait pas.
Sans réponse du côté Proxmox (`vmbr1` non VLAN-aware ou port en `tag=`), les
trames partent mais rien ne revient : voir Q13.13.
:::

---

**E13.10** — *VXLAN point à point, `fdb`, capture, MTU.*

```bash
# lab-web
sudo ip link add vxlan0 type vxlan id 42 local 10.10.10.11 \
  remote 10.10.10.12 dstport 4789 dev ens18
sudo ip addr add 192.168.42.11/24 dev vxlan0
sudo ip link set vxlan0 up
ip -d link show vxlan0            # vxlan id 42 remote 10.10.10.12 ... mtu 1450
# lab-db : idem avec local .12 remote .11 et 192.168.42.12/24
ping -c 2 192.168.42.12
bridge fdb show dev vxlan0   # 00:00:00:00:00:00 dst 10.10.10.12 self permanent
sudo tcpdump -i ens18 -nn -c 2 -v 'udp port 4789'
```

Capture : `IP 10.10.10.11.41234 > 10.10.10.12.4789: VXLAN, flags [I] (0x08),
vni 42` puis, indentée, la trame interne : `bc:24:11:.. > bc:24:11:.., ethertype
IPv4, ... 192.168.42.11 > 192.168.42.12: ICMP echo request`.

```bash
ping -M do -s 1422 -c 1 192.168.42.12     # 1422 + 8 + 20 = 1450 : passe
ping -M do -s 1423 -c 1 192.168.42.12     # "message too long, mtu=1450"
```

::: pourquoi
Créé avec `dev ens18`, le VXLAN hérite du MTU du porteur moins 50 : 1450, sans
rien préciser. L'entrée `fdb` `00:00:00:00:00:00 dst 10.10.10.12` est la
« route par défaut L2 » du tunnel : toute MAC inconnue est envoyée à ce VTEP
(*VXLAN Tunnel EndPoint*). Avec plusieurs pairs on ajoute des entrées
`bridge fdb append 00:00:00:00:00:00 dev vxlan0 dst <ip>` (réplication
unicast, ce que fait flannel) ou on utilise un groupe multicast. Le VNI (24
bits, 16 M de valeurs) sépare les locataires sur un même port UDP.
:::

---

**E13.11** — *Jeu de règles stateful minimal, chargé sans perdre SSH.*

```text
# ~/lab13/nft/input.nft
flush ruleset
table inet filter {
  set admin {
    type ipv4_addr
    flags interval
    elements = { 10.10.10.0/24 }
  }
  chain input {
    type filter hook input priority 0; policy drop;
    iif "lo" accept
    ct state established,related accept
    ct state invalid counter drop
    ip saddr @admin tcp dport 22 ct state new accept
    icmp type echo-request limit rate 10/second accept
    icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, echo-request } accept
    limit rate 5/minute log prefix "in-drop: " counter drop
  }
}
```

```bash
sudo nft -c -f ~/lab13/nft/input.nft     # -c : vérifie sans charger
sudo nft -f ~/lab13/nft/input.nft        # la session SSH survit (established)
# depuis lab-web : nc -zv -w1 10.10.10.10 8099
sudo journalctl -k --since -2min | grep in-drop
sudo nft list ruleset | grep counter
sudo nft flush ruleset
```

::: pourquoi
La session SSH en cours survit parce que son flux est `established` et que
la règle qui l'accepte précède la politique `drop`. Le `limit rate` sur `log`
évite qu'un scan remplisse le journal (et `dmesg`). `flags interval` permet
des préfixes dans un set. La règle ICMPv6 ND est le rappel que la famille
`inet` filtre aussi IPv6 : sans elle, la machine perd ses voisins v6 dès que
la politique est `drop`. `nft -c` (check) est le `netplan try` de nftables :
toujours avant `-f` sur une machine distante.
:::

---

**E13.12** — *`iptables-translate` sur trois règles.*

```bash
iptables-translate -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED \
  -j ACCEPT
# nft 'add rule ip filter INPUT ct state related,established counter accept'
iptables-translate -t nat -A POSTROUTING -s 172.17.0.0/16 ! -o docker0 \
  -j MASQUERADE
# nft 'add rule ip nat POSTROUTING oifname != "docker0" ip saddr 172.17.0.0/16
#      counter masquerade'
iptables-translate -t nat -A PREROUTING -p tcp --dport 8080 \
  -j DNAT --to 172.17.0.2:80
# nft 'add rule ip nat PREROUTING tcp dport 8080 counter dnat to 172.17.0.2:80'
```

Ce que chaque traduction ajoute : un `counter` (iptables compte toujours,
nftables seulement sur demande), la famille `ip` (iptables ne connaît que
IPv4 ; `ip6tables` donne `ip6`), et les noms de chaînes en majuscules dans
une table `filter`/`nat` de la famille `ip` — celles que crée `iptables-nft`,
distinctes de tes tables `inet filter`.

::: pourquoi
Sur Ubuntu 24.04 comme sur Rocky 9, `iptables` est `iptables-nft` : il
écrit dans nftables, dans des tables `ip filter`, `ip nat`… avec des chaînes
de base aux priorités classiques. Tes propres tables `inet` s'accrochent aux
**mêmes hooks** : pour un même paquet, les deux jeux sont parcourus par
priorité, et un `drop` dans l'un l'emporte sur un `accept` de l'autre. Deux
administrateurs, deux outils, une contradiction invisible depuis chacun des
deux : seul `nft list ruleset` montre l'ensemble. `iptables-restore-translate
-f regles.v4` convertit un fichier complet (`/etc/iptables/rules.v4`) d'un coup.
:::

---

**E13.13** — *`nftrace` et `nft monitor trace` sur le port 8080.*

```bash
# insert, pas add : un dnat qui matche termine la chaîne nat, une règle
# ajoutée derrière ne serait jamais évaluée
sudo nft insert rule ip nat prerouting tcp dport 8080 meta nftrace set 1
sudo nft monitor trace        # terminal 1
# terminal 2, depuis lab-web : curl -s http://10.10.10.10:8080/ >/dev/null
```

Trace (résumée) pour le SYN :

```text
trace id 3a7f ip nat prerouting packet: iif "ens18" ... tcp dport 8080
trace id 3a7f ip nat prerouting rule tcp dport 8080 meta nftrace set 1
    (verdict continue)
trace id 3a7f ip nat prerouting rule tcp dport 8080 dnat to 172.20.0.11:8000
    (verdict accept)
trace id 3a7f inet filter forward packet: iif "ens18" oif "br-lab"
    ip daddr 172.20.0.11 tcp dport 8000
trace id 3a7f inet filter forward rule ct status dnat accept (verdict accept)
trace id 3a7f ip nat postrouting packet: ... (verdict continue)
trace id 3a7f ip nat postrouting policy accept
```

```bash
sudo nft -a list chain ip nat prerouting   # repérer le handle
sudo nft delete rule ip nat prerouting handle <N>
```

::: pourquoi
La marque `nftrace` est posée sur le **paquet** (pas le flux) par la première
règle qui matche ; ensuite chaque chaîne de base, chaque règle qui matche et
chaque verdict sont envoyés en netlink à `nft monitor trace`. On voit donc
l'ordre réel de traversée, la destination avant/après DNAT, et l'endroit
exact d'un `drop`. C'est l'équivalent d'un `strace` pour netfilter : plus
fiable que d'empiler des `log`, et sans rien changer aux verdicts. Les
paquets suivants du flux ne passent plus par `nat prerouting` (le NAT est
mémorisé) : la trace ne les montre qu'à partir de `forward`.
:::

---

**E13.14** — *Unbound : récursion complète, cache, purge ciblée.*

```bash
sudo unbound-control list_forwards        # vide : aucun forwarder
sudo unbound-control list_stubs           # lab.local et la zone inverse
sudo tcpdump -i ens18 -nn 'udp port 53 and not host 10.10.10.14' -c 20
# on voit des requêtes vers 198.41.0.4 (a.root-servers.net), puis les
# serveurs de .com, puis ceux de la zone : c'est la récursion.
sudo unbound-control stats_noreset | grep -E 'total.num.(cachehits|cachemiss)'
dig @10.10.10.53 www.debian.org +short; dig @10.10.10.53 www.debian.org +short
sudo unbound-control stats_noreset | grep -E 'total.num.(cachehits|cachemiss)'
sudo unbound-control flush_zone debian.org
```

::: pourquoi
Un forwarder n'émettrait des requêtes que vers son amont, un seul serveur ;
un récursif parle à des dizaines de serveurs différents, en commençant par
la racine (`unbound-control dump_infra` montre les serveurs contactés et
leurs RTT). `stats` remet les compteurs à zéro à chaque appel ;
`stats_noreset` non. `flush_zone` supprime tout ce qui est sous un nom ;
`flush` un seul nom ; `flush_negative` les réponses `NXDOMAIN` en cache —
le bon geste quand on vient de créer un enregistrement que le résolveur a
déjà mémorisé comme inexistant (TTL négatif du SOA, 300 s dans notre zone).
:::

---

**E13.15** — *SRV, TXT, validation, rechargement, propagation.*

Dans `/etc/bind/zones/db.lab.local` (serial `2026091901` → `2026091902`) :

```text
@             IN  TXT  "v=spf1 mx -all"
_ldap._tcp    IN  SRV  10 50 389 lab-adm.lab.local.
```

```bash
sudo named-checkzone lab.local /etc/bind/zones/db.lab.local
# zone lab.local/IN: loaded serial 2026091902 ; OK
sudo rndc reload lab.local
date +%T; dig +short SRV _ldap._tcp.lab.local @10.10.10.14
sleep 2; dig +short SRV _ldap._tcp.lab.local @10.10.10.10
dig +short SOA lab.local @10.10.10.14; dig +short SOA lab.local @10.10.10.10
```

Sur `lab-adm`, `journalctl -u named -n 5` : `zone lab.local/IN: transferred
serial 2026091902` puis `transfer of 'lab.local/IN' from 10.10.10.14#53:
Transfer completed: 1 messages, 20 records`. Délai : une à deux secondes
(NOTIFY immédiat).

::: pourquoi
`named-checkzone` charge la zone comme le ferait `named` : il attrape les
erreurs de syntaxe, un `CNAME` à l'apex, un `MX` vers un `CNAME`, mais pas un
serial oublié ni un point final manquant (syntaxiquement valides). `rndc
reload <zone>` ne recharge que cette zone, envoie le NOTIFY, et le
secondaire, voyant un serial supérieur, transfère (AXFR ici : sans journal
IXFR, la zone entière, 20 enregistrements, ce n'est rien). Le format `SRV` :
priorité (plus bas préféré), poids (répartition à priorité égale), port,
cible (jamais une adresse, jamais un CNAME).
:::

---

**E13.16** — *ULA sur `lab-adm` et `lab-web`, voisinage v6, serveur v6 only.*

```bash
# lab-adm
sudo ip -6 addr add fd00:10:10:10::10/64 dev ens18
# lab-web
sudo ip -6 addr add fd00:10:10:10::11/64 dev ens18
python3 -m http.server 8000 --bind fd00:10:10:10::11 &
# lab-adm
ping -6 -c 2 fd00:10:10:10::11
ip -6 neigh show dev ens18     # fd00:10:10:10::11 lladdr bc:24:11:.. REACHABLE
                               # fe80::be24:11ff:fe.. lladdr ... STALE
ip neigh show dev ens18        # 10.10.10.11 lladdr bc:24:11:.. REACHABLE
curl -6 "http://[fd00:10:10:10::11]:8000/" | head -2
ss -6 -tlnp                    # sur lab-web : [fd00:10:10:10::11]:8000
```

```yaml
# Netplan, lab-adm
      addresses: [10.10.10.10/24, "fd00:10:10:10::10/64"]
```

::: pourquoi
La table `ip -6 neigh` contient deux entrées pour le même voisin : son ULA et
sa link-local `fe80::` (dérivée de la MAC, motif `ff:fe`), parce que ND
utilise la link-local pour ses propres échanges. Les états sont les mêmes
qu'en v4 (`REACHABLE`, `STALE`), et le noyau utilise en fait la même
machine à états pour ARP. Une adresse v6 littérale dans une URL va entre
crochets. Sans routeur v6 sur `vmbr1`, pas de RA, donc pas de SLAAC ni de
route par défaut v6 : les ULA posés à la main suffisent pour un `/64`
connecté, et c'est exactement ce que `radvd` ou un routeur ajouterait avec
un RA (préfixe + `default via fe80::1`).
:::

---

## 13.6 Labs

### **L13.1** — Mini-Docker à la main

*Trois netns sur un bridge, NAT de sortie, publication d'un port, hairpin,
trace, comparaison avec Docker.*

**Étapes 1 et 8 — le script.** `~/lab13/bin/minidocker.sh` :

```bash
#!/usr/bin/env bash
# minidocker.sh — up | down | status : trois netns sur un bridge, NAT, DNAT
set -euo pipefail
BR=br-lab; NET=172.20.0; WAN=ens18
NFT=/home/mathieu/lab13/nft/minidocker.nft
WWW=/home/mathieu/lab13/www
STATE=/run/minidocker.ipfwd

up() {
  ip link show "$BR" >/dev/null 2>&1 || ip link add "$BR" type bridge
  ip addr show dev "$BR" | grep -q "$NET.1/24" \
    || ip addr add "$NET.1/24" dev "$BR"
  ip link set "$BR" up
  for i in 1 2 3; do
    ns=c$i
    [ -e "/run/netns/$ns" ] || ip netns add "$ns"
    ip -n "$ns" link show eth0 >/dev/null 2>&1 \
      || ip link add "veth-$ns" type veth peer name eth0 netns "$ns"
    ip link set "veth-$ns" master "$BR" up
    ip -n "$ns" link set lo up
    ip -n "$ns" addr show dev eth0 | grep -q "$NET.1$i/24" \
      || ip -n "$ns" addr add "$NET.1$i/24" dev eth0
    ip -n "$ns" link set eth0 up
    ip -n "$ns" route show default | grep -q . \
      || ip -n "$ns" route add default via "$NET.1"
  done
  [ -f "$STATE" ] || sysctl -n net.ipv4.ip_forward > "$STATE"
  sysctl -qw net.ipv4.ip_forward=1
  nft -f "$NFT"
  # serveur HTTP publié dans c1
  if ! ip netns pids c1 | xargs -r ps -o comm= -p | grep -q python3; then
    ip netns exec c1 sh -c \
      "cd $WWW && nohup python3 -m http.server 8000 >/dev/null 2>&1 &"
  fi
  echo "up : $BR $NET.0/24, c1..c3, NAT via $WAN, 8080 -> c1:8000"
}

down() {
  for i in 1 2 3; do
    ns=c$i
    ip netns pids "$ns" 2>/dev/null | xargs -r kill 2>/dev/null || true
    ip netns del "$ns" 2>/dev/null || true      # emporte eth0 et son pair
  done
  ip link del "$BR" 2>/dev/null || true
  nft list table ip nat >/dev/null 2>&1 && nft delete table ip nat
  nft list table inet filter >/dev/null 2>&1 && nft delete table inet filter
  if [ -f "$STATE" ]; then
    sysctl -qw "net.ipv4.ip_forward=$(cat "$STATE")"; rm -f "$STATE"
  fi
  echo "down : tout est retiré"
}

status() {
  echo "== netns";        ip netns list
  echo "== bridge";       bridge link show
  echo "== fdb";          bridge fdb show br "$BR" | grep -v permanent || true
  echo "== ip_forward";   sysctl -n net.ipv4.ip_forward
  echo "== nat";          nft list table ip nat 2>/dev/null || echo "(aucune)"
}

case "${1:-}" in
  up) up ;; down) down ;; status) status ;;
  *) echo "usage: $0 up|down|status" >&2; exit 2 ;;
esac
```

**Étape 2 — isolation.** `ip netns exec c1 ping -c1 172.20.0.12` répond ;
`ip netns exec c1 ping -c1 -W1 10.10.10.11` : « 1 packets transmitted, 0
received » sans message. Le paquet sort de `c1`, arrive sur `br-lab` (visible
avec `tcpdump -i br-lab icmp`), et le netns racine, `ip_forward=0`, le jette
après `prerouting` — jamais vu sur `ens18`.

**Étapes 3, 4, 5 et 7 — le jeu de règles.** `~/lab13/nft/minidocker.nft`,
version finale :

```text
#!/usr/sbin/nft -f
# minidocker.nft — NAT de sortie, publication 8080 -> c1:8000, hairpin
table ip nat {}          # crée la table si absente (idempotent)
table inet filter {}
flush table ip nat       # puis la vide : le fichier remplace tout, d'un bloc
flush table inet filter

table ip nat {
  chain prerouting {
    type nat hook prerouting priority -100; policy accept;
    iifname != "lo" tcp dport 8080 counter dnat to 172.20.0.11:8000
  }
  chain output {
    type nat hook output priority -100; policy accept;
    # trafic émis par lab-adm lui-même vers son port publié (étape 5)
    ip daddr 10.10.10.10 tcp dport 8080 dnat to 172.20.0.11:8000
  }
  chain postrouting {
    type nat hook postrouting priority 100; policy accept;
    ip saddr 172.20.0.0/24 oifname "ens18" counter masquerade
    # hairpin : un conteneur qui parle au port publié (étape 5)
    ip saddr 172.20.0.0/24 ip daddr 172.20.0.11 tcp dport 8000 \
        ct status dnat masquerade
  }
}

table inet filter {
  chain forward {
    type filter hook forward priority 0; policy drop;
    ct state established,related accept
    ct state invalid counter drop
    iifname "br-lab" oifname "ens18" accept
    iifname "br-lab" oifname "br-lab" accept       # trafic routé en épingle
    ct status dnat ip daddr 172.20.0.11 tcp dport 8000 accept
    limit rate 5/minute log prefix "fwd-drop: " counter drop
  }
}
```

`flush table` échoue si la table n'existe pas : la déclaration vide
`table ip nat {}` juste avant la crée si besoin (et ne touche à rien si elle
existe), ce qui rend le fichier rechargeable à volonté. Tout le fichier est
appliqué en une transaction : soit tout, soit rien. Côté script, le test d'existence d'un netns se fait sur `/run/netns/<nom>` : `ip netns list` affiche `c1 (id: 0)` dès qu'un pair veth y a été déplacé, un `grep -x c1` échouerait au second `up`.

Vérifications :

```bash
sudo ip netns exec c1 curl -s http://10.10.10.11/ | head -1     # étape 3
# depuis lab-web
curl -s http://10.10.10.10:8080/                                 # étape 4
# depuis lab-adm
curl -s http://10.10.10.10:8080/                                 # étape 5
sudo ip netns exec c2 curl -s http://10.10.10.10:8080/           # hairpin
sudo nft list chain ip nat postrouting                            # compteurs
sudo conntrack -L -p tcp --dport 8000
```

Entrée conntrack du flux publié (depuis `lab-web`) :
`tcp 6 ... ESTABLISHED src=10.10.10.11 dst=10.10.10.10 sport=51234 dport=8080
src=172.20.0.11 dst=10.10.10.11 sport=8000 dport=51234 [ASSURED]`. Premier
tuple : ce que le client a envoyé. Second : ce que le serveur renvoie
(`172.20.0.11:8000 → 10.10.10.11`), que conntrack retraduira en
`10.10.10.10:8080` à la sortie. Seule la destination a changé : c'est un DNAT.

**Étape 6 — trace.** Voir E13.13 : `nat prerouting` (règle DNAT, `accept`),
`filter forward` (`ct status dnat ... accept`), `nat postrouting`
(`continue`, aucune règle). Pour le hairpin depuis `c2`, `nat postrouting`
montre en plus la règle `masquerade` matcher.

**Étape 9 — Docker.** `docker network inspect bridge` : `"Subnet":
"172.17.0.0/16"` = ton `172.20.0.0/24` sur `br-lab` ; `"Gateway":
"172.17.0.1"` = l'adresse posée sur le bridge ; `"com.docker.network.bridge.
name": "docker0"` = `br-lab` ; chaque `"IPv4Address": "172.17.0.2/16"` dans
`Containers` = ton `ip -n c1 addr add`. `"com.docker.network.bridge.enable_
ip_masquerade": "true"` = ta règle `masquerade`.

::: pourquoi
Le point délicat est le **hairpin** (étape 5). Depuis `lab-adm` : le paquet
local ne passe pas par `prerouting`, il faut le DNAT en `output`. Depuis
`c2` : le DNAT en `prerouting` fonctionne (`c2` → bridge → netns racine),
mais le serveur `c1` verrait une source `172.20.0.12` sur son propre segment
et répondrait **directement** par le bridge, sans repasser par le routeur :
`c2` recevrait un SYN-ACK de `172.20.0.11:8000` pour une connexion ouverte
vers `10.10.10.10:8080` et enverrait un `RST`. Le `masquerade` conditionné à
`ct status dnat` force la réponse à revenir vers `172.20.0.1`, où conntrack
détraduit les deux adresses. Docker pose exactement ces deux règles
(`DOCKER` en `OUTPUT`, `MASQUERADE` avec `-s X -d X`).

La règle `forward` `br-lab → br-lab` couvre le trafic **routé** qui ressort
par le bridge d'où il vient (le hairpin : `c2` parle à l'adresse du bridge,
qui relaie vers `c1`). Le trafic **commuté** `c1 ↔ c2` ne passe pas par
`forward`… sauf si `br_netfilter` est chargé (Docker le charge) : cette même
règle le couvre alors aussi, sans quoi installer Docker plus tard casserait
la communication entre tes netns.
:::

::: piege
`ip netns del` détruit les veth dont un bout est dans le netns, mais pas le
bridge ni les règles : `down` doit tout faire, sinon le `check` échoue sur des
restes. Et un `nft flush ruleset` global dans `down` effacerait aussi les
règles d'un autre outil (ufw…) : on supprime **ses** tables par leur nom.
:::

---

### **L13.2** — Policy routing, deux passerelles

*Maquette netns, reproduction de la panne, correction par source puis par
marque, `rp_filter`, Netplan.*

**Étape 1 — construction.**

```bash
for ns in c-bur gw1 dual gw2 c-prod; do
  sudo ip netns add $ns; sudo ip -n $ns link set lo up
done
link() { # link <ns1> <if1> <ip1> <ns2> <if2> <ip2>
  sudo ip link add "$2" netns "$1" type veth peer name "$5" netns "$4"
  sudo ip -n "$1" addr add "$3" dev "$2"; sudo ip -n "$1" link set "$2" up
  sudo ip -n "$4" addr add "$6" dev "$5"; sudo ip -n "$4" link set "$5" up
}
link c-bur  eth0 192.168.1.10/24  gw1  lan  192.168.1.1/24
link gw1    wan  10.10.11.1/24    dual eth1 10.10.11.2/24
link c-prod eth0 192.168.2.10/24  gw2  lan  192.168.2.1/24
link gw2    wan  10.10.12.1/24    dual eth2 10.10.12.2/24
sudo ip -n c-bur  route add default via 192.168.1.1
sudo ip -n c-prod route add default via 192.168.2.1
sudo ip -n dual   route add default via 10.10.11.1
for gw in gw1 gw2; do
  sudo ip netns exec $gw sysctl -qw net.ipv4.ip_forward=1
done
```

**Étape 2 — la panne.** `ip netns exec c-prod ping -c2 10.10.12.2` : muet.
Aller : `192.168.2.10 → 10.10.12.2` via `gw2`, arrive dans `dual` par `eth2`.
Retour :

```bash
sudo ip -n gw2 route get 10.10.12.2 from 192.168.2.10 iif lan
# 10.10.12.2 from 192.168.2.10 dev wan   -- aller : relayé par gw2
sudo ip -n dual route get 192.168.2.10 from 10.10.12.2
# 192.168.2.10 from 10.10.12.2 via 10.10.11.1 dev eth1   -- retour
sudo ip netns exec gw1 tcpdump -i wan -nn icmp -c 2
# IP 10.10.12.2 > 192.168.2.10: ICMP echo reply   -- arrive dans gw1
```

`gw1` n'a pas de route vers `192.168.2.0/24` : il jette la réponse et renvoie
au mieux un ICMP `net unreachable` à `10.10.12.2`, que `c-prod` ne verra
jamais. Le client voit un timeout, pas une erreur : la route asymétrique est
silencieuse par nature. Depuis `c-bur`, tout fonctionne (aller et retour par
`gw1`) : « ça marche pour la bureautique, pas pour la prod ».

**Étape 3 — « intermittent ».** Dans un vrai réseau, les deux passerelles
se connaissent : on relie `gw1` et `gw2`, chacune apprend l'autre réseau, et
le `ping` passe — par un chemin **asymétrique** (aller via `gw2`, retour via
`gw1` puis `gw2`) :

```bash
link gw1 inter 10.10.99.1/30 gw2 inter 10.10.99.2/30
sudo ip -n gw1 route add 192.168.2.0/24 via 10.10.99.2
sudo ip -n gw2 route add 192.168.1.0/24 via 10.10.99.1
sudo ip netns exec c-prod ping -c 2 10.10.12.2      # répond
```

Puis le pare-feu stateful de la bureautique, sur `gw1`, comme dans le ticket
(fichier `~/lab13/nft/gw1.nft`) :

```text
table inet fw {
  chain forward {
    type filter hook forward priority 0; policy drop;
    ct state established,related accept
    ip protocol icmp accept
    iifname "lan" accept
  }
}
```

```bash
sudo ip netns exec gw1 nft -f ~/lab13/nft/gw1.nft
sudo ip netns exec dual nc -l 9000 &
sudo ip netns exec c-prod nc -zv -w 3 10.10.12.2 9000   # timeout
sudo ip netns exec c-prod ping -c 2 10.10.12.2           # répond toujours
```

Le SYN va `c-prod → gw2 → dual` : `gw1` ne l'a jamais vu. Le SYN-ACK de `dual`
arrive dans `gw1` par `wan` : pour conntrack, un SYN-ACK **sans SYN
préalable** est `invalid` (la machine à états TCP refuse de créer une entrée
sur un SYN-ACK), donc ni `established` ni `new` ; `iifname "lan"` ne matche
pas ; politique `drop`. Les ICMP passent grâce à la règle sans état.
« Intermittent » dans le ticket : les flux qui tombent sur un chemin
symétrique (ou une passerelle sans état) passent, les autres non.

**Étape 4 — correction.**

```bash
sudo mkdir -p /etc/iproute2/rt_tables.d
echo "200 prod" | sudo tee /etc/iproute2/rt_tables.d/lab.conf
sudo ip -n dual route add 10.10.12.0/24 dev eth2 src 10.10.12.2 table prod
sudo ip -n dual route add default via 10.10.12.1 dev eth2 table prod
sudo ip -n dual rule add from 10.10.12.2 table prod priority 100
sudo ip -n dual route get 192.168.2.10 from 10.10.12.2
# 192.168.2.10 from 10.10.12.2 via 10.10.12.1 dev eth2
sudo ip netns exec c-prod nc -zv 10.10.12.2 9000     # succeeded
```

**Étape 5 — par marque.**

```bash
sudo ip -n dual rule del from 10.10.12.2 table prod
sudo ip -n dual rule add fwmark 0x2 table prod priority 100
sudo ip netns exec dual nft -f - <<'EOF'
table inet mangle {
  chain prerouting {
    type filter hook prerouting priority -150; policy accept;
    iifname "eth2" ct state new ct mark set 0x2
  }
  chain output {
    type route hook output priority -150; policy accept;
    ct mark 0x2 meta mark set ct mark
  }
}
EOF
```

À l'arrivée d'un nouveau flux par `eth2`, la **connexion** est marquée ; à la
sortie, chaque paquet de réponse récupère la marque de sa connexion, et la
chaîne `route` refait le routage vers la table `prod`. On préfère la marque
quand le critère n'est pas une simple adresse source : interface d'entrée,
port, utilisateur (`meta skuid`), ou quand on veut router le trafic
**relayé** selon l'interface par laquelle la requête est entrée.

**Étape 6 — `rp_filter`.** Sans la règle de policy routing, `sysctl -w
net.ipv4.conf.all.rp_filter=1` dans `dual` : les paquets de `192.168.2.10`
arrivant par `eth2` sont jetés à l'entrée, parce que la route de retour vers
`192.168.2.10` (table `main`) pointe sur `eth1` — `ip netns exec dual` `nstat -az` `TcpExtIPReversePathFilter` s'incrémente. Avec `2` (loose), le
noyau vérifie seulement qu'**une** route vers la source existe, par n'importe
quelle interface : c'est la valeur pour un routeur multi-liens ou un hôte
policy-routé (Ubuntu 24.04 met déjà `2` par défaut via
`/usr/lib/sysctl.d/50-default.conf`).

**Étape 7 — Netplan** (`lab-web`, seconde NIC) :

```yaml
network:
  version: 2
  ethernets:
    ens19:
      addresses: [10.10.11.11/24]
      routes:
        - to: 10.10.11.0/24
          scope: link
          table: 200
        - to: default
          via: 10.10.11.1
          table: 200
      routing-policy:
        - from: 10.10.11.11
          table: 200
```

::: pourquoi
Le fond du problème : la table de routage classique ne regarde que la
**destination**. Un hôte à deux pattes doit répondre « par où le paquet est
entré », information qui n'existe que dans la **source** de la réponse (ou
dans une marque de connexion). `ip rule` ajoute cette dimension. Trois
règles d'or : une table par interface secondaire, avec ses routes connectées
**et** sa passerelle ; une règle `from <adresse de l'interface>` ; et
`rp_filter=2`. Tout ce que `ip route get ... from ...` ne valide pas ne
marchera pas en production.
:::

::: piege
Oublier la route connectée dans la table dédiée (Q13.4) envoie le trafic
local du segment à la passerelle. Et une règle `from` sans `priority` reçoit la plus petite priorité existante moins un : elle passe **devant** `main` (32766) et devant les règles ajoutées avant elle. L'ordre
d'ajout compte : des numéros explicites évitent les surprises.
:::

---

### **L13.3** — VXLAN, WireGuard, mesures

**Étape 1 — VXLAN.** Voir E13.10 pour la création. MTU : `ens18` = 1500,
moins 14 (Ethernet interne) + 20 (IP) + 8 (UDP) + 8 (VXLAN) = 50 → 1450. Le
noyau le pose seul si `dev ens18` est indiqué.

**Étape 2 — Netplan** (`lab-web`) :

```yaml
network:
  version: 2
  tunnels:
    vxlan0:
      mode: vxlan
      id: 42
      link: ens18
      local: 10.10.10.11
      remote: 10.10.10.12
      port: 4789
      mtu: 1450
      addresses: [192.168.42.11/24]
```

`sudo ip link del vxlan0` (celle faite à la main) puis `sudo netplan try`.
`ip -d link show vxlan0` doit donner les mêmes attributs ; Netplan génère
`/run/systemd/network/10-netplan-vxlan0.netdev` avec `[VXLAN]`.

**Étape 3 — multicast.**

```bash
sudo ip link add vxlan1 type vxlan id 43 group 239.1.1.1 dstport 4789 \
  dev ens18 ttl 5
sudo ip addr add 192.168.43.11/24 dev vxlan1; sudo ip link set vxlan1 up
bridge fdb show dev vxlan1      # 00:00:00:00:00:00 dst 239.1.1.1 via ens18
sudo tcpdump -i ens18 -nn 'udp port 4789 and dst 239.1.1.1' -c 2
```

Le premier paquet vers une MAC inconnue (ARP en broadcast, ou tout paquet
vers une MAC non encore dans la `fdb`) part vers le **groupe multicast** ;
tous les VTEP abonnés le reçoivent, celui qui répond est appris dans la `fdb`
(`bridge fdb show dev vxlan1` montre alors `<mac> dst 10.10.10.12`), et les
suivants partent en unicast. En unicast point à point, il n'y a rien à
apprendre : tout part vers `remote`. `vmbr1` doit laisser passer le
multicast (bridge Linux : oui par défaut, `multicast_snooping` peut le
filtrer).

**Étape 4 — WireGuard.**

```bash
# sur chaque machine
sudo sh -c 'umask 077; wg genkey > /etc/wireguard/privatekey'
sudo sh -c 'wg pubkey < /etc/wireguard/privatekey > /etc/wireguard/publickey'
```

```ini
# /etc/wireguard/wg0.conf sur lab-adm (chmod 600)
[Interface]
Address = 10.99.0.1/24
ListenPort = 51820
PrivateKey = <contenu de /etc/wireguard/privatekey de lab-adm>

[Peer]
PublicKey = <contenu de /etc/wireguard/publickey de lab-ops>
AllowedIPs = 10.99.0.2/32
Endpoint = 10.10.10.14:51820
PersistentKeepalive = 25
```

Sur `lab-ops` : `Address = 10.99.0.2/24`, `PrivateKey` de `lab-ops`, `Peer`
avec la clé publique de `lab-adm`, `AllowedIPs = 10.99.0.1/32`, `Endpoint =
10.10.10.10:51820`.

```bash
sudo systemctl enable --now wg-quick@wg0
sudo wg show      # latest handshake: 3 seconds ago, transfer: ...
ip -d link show wg0     # mtu 1420
ping -c 2 10.99.0.2
```

**Étape 5 — mesures** (valeurs typiques sur un hôte Proxmox modeste, 2 vCPU
par VM ; les tiennes diffèrent, les rapports comptent) :

| Chemin | Débit TCP | `Retr` |
|---|---|---|
| direct lab-web → lab-db | 9 à 20 Gbit/s | 0 à quelques dizaines |
| VXLAN | 3 à 6 Gbit/s | souvent plus élevé |
| direct lab-adm → lab-ops | idem direct | — |
| WireGuard | 1 à 2,5 Gbit/s | faible |

UDP `-u -b 0` sur le VXLAN : le récepteur affiche un pourcentage de pertes
et un jitter ; à débit forcé, les pertes traduisent un CPU récepteur
saturé (softirq), pas le « réseau ».

**Étape 6.** `top` : `si` monte à 30-60 % sur un vCPU pendant la mesure
VXLAN ; `ethtool -S ens18` : `tx_packets` grimpe quatre fois plus vite que
pour le même volume en direct (segments de 1450 au lieu de super-paquets
TSO de 64 ko).

**Étape 7 — MTU cassé.** `ip link set vxlan0 mtu 1500` sur `lab-web` :
`ping -M do -s 1472 192.168.42.12` → plus de « message too long » local (le
paquet tient dans 1500) ; sur `lab-db`, `tcpdump -i ens18 -nn 'udp port 4789 or (ip[6:2] & 0x1fff != 0)'` montre des paquets `length 1514` suivis de
fragments `frag 0x...:...@1480` : l'externe de 1550 a été fragmenté en deux.
Ça fonctionne (lentement) tant que rien ne filtre les fragments ; BF13.4
montre ce qui arrive sinon. `ip link set vxlan0 mtu 1450`.

**Étape 8.** `tc qdisc add dev ens18 root netem delay 50ms loss 1%` sur
`lab-db` : le débit VXLAN tombe à quelques dizaines de Mbit/s (1 % de perte
avec 50 ms de RTT en plus — `netem` n'agit que dans le sens émis par `lab-db` — tue le contrôle de congestion TCP : `Retr` explose) ;
`tc qdisc del dev ens18 root`.

**Étape 9 — conclusion type.** VXLAN : L2 étendu, sans chiffrement, coût CPU
modéré, à réserver à un underlay de confiance ; c'est flannel `vxlan`,
Calico `vxlanMode`, Cilium `tunnel: vxlan`. WireGuard : L3, chiffré, coût
CPU élevé sur peu de cœurs ; c'est Cilium `encryption: wireguard`, Calico
`wireguardEnabled`. Sans overlay (Calico BGP, Cilium native routing) on garde
le débit direct, mais il faut que le réseau physique sache router les
préfixes des pods. Recommandation : native routing quand on contrôle le
réseau, VXLAN sinon, WireGuard seulement pour ce qui traverse une zone non
fiable, et des jumbo frames sur l'underlay dès que possible.

::: pourquoi
Les deux tunnels résument les deux familles d'overlay : VXLAN transporte des
**trames** et se comporte comme un commutateur distribué (apprentissage de
MAC, multicast ou réplication unicast), WireGuard transporte des **paquets**
et se comporte comme un routeur chiffrant (cryptokey routing). Le MTU est la
seule chose qu'ils ont en commun à ne jamais négliger, et `iperf3` est le
seul juge de paix pour choisir.
:::

---

### **L13.4** — Le DNS du lab

**Étape 1 — adresse de service** (`lab-ops`, `/etc/netplan/01-lab.yaml`) :

```yaml
      addresses: [10.10.10.14/24, 10.10.10.53/24]
```

`netplan try`, `ip -br a show ens18`. Une adresse de service séparée
permet de déplacer le résolveur (autre VM, cluster keepalived) sans
reconfigurer un seul client, et de séparer proprement les rôles
(autoritaire sur `.14`, récursif sur `.53`) sans jouer avec les ports.

**Étape 2 — BIND9 primaire.** `/etc/bind/named.conf.options` :

```text
options {
    directory "/var/cache/bind";
    listen-on { 10.10.10.14; };
    listen-on-v6 { none; };
    recursion no;
    allow-query { any; };
    allow-transfer { none; };
    dnssec-validation no;
    notify explicit;
};
```

`/etc/bind/named.conf.local` :

```text
zone "lab.local" {
    type primary;
    file "/etc/bind/zones/db.lab.local";
    allow-transfer { 10.10.10.10; };
    also-notify { 10.10.10.10; };
};
zone "10.10.10.in-addr.arpa" {
    type primary;
    file "/etc/bind/zones/db.10.10.10";
    allow-transfer { 10.10.10.10; };
    also-notify { 10.10.10.10; };
};
```

`/etc/bind/zones/db.lab.local` :

```text
$TTL 3600
$ORIGIN lab.local.
@       IN  SOA  ns1.lab.local. hostmaster.lab.local. (
            2026091901 ; serial AAAAMMJJnn
            3600       ; refresh
            900        ; retry
            1209600    ; expire (14 j)
            300 )      ; TTL négatif
        IN  NS   ns1.lab.local.
        IN  NS   ns2.lab.local.
        IN  MX   10 mail.lab.local.
        IN  TXT  "v=spf1 mx -all"
ns1     IN  A    10.10.10.14
ns2     IN  A    10.10.10.10
lab-adm  IN  A    10.10.10.10
lab-web  IN  A    10.10.10.11
lab-db   IN  A    10.10.10.12
lab-rhel IN  A    10.10.10.13
lab-ops  IN  A    10.10.10.14
lab-git  IN  A    10.10.10.15
lab-virt IN  A    10.10.10.16
lab-adm  IN  AAAA fd00:10:10:10::10
lab-web  IN  AAAA fd00:10:10:10::11
lab-db   IN  AAAA fd00:10:10:10::12
lab-rhel IN  AAAA fd00:10:10:10::13
lab-ops  IN  AAAA fd00:10:10:10::14
lab-git  IN  AAAA fd00:10:10:10::15
lab-virt IN  AAAA fd00:10:10:10::16
mail    IN  A    10.10.10.11
www     IN  CNAME lab-web.lab.local.
_http._tcp  IN  SRV  0 5 80 lab-web.lab.local.
```

`/etc/bind/zones/db.10.10.10` :

```text
$TTL 3600
$ORIGIN 10.10.10.in-addr.arpa.
@   IN  SOA  ns1.lab.local. hostmaster.lab.local. (
        2026091901 3600 900 1209600 300 )
    IN  NS   ns1.lab.local.
    IN  NS   ns2.lab.local.
10  IN  PTR  lab-adm.lab.local.
11  IN  PTR  lab-web.lab.local.
12  IN  PTR  lab-db.lab.local.
13  IN  PTR  lab-rhel.lab.local.
14  IN  PTR  lab-ops.lab.local.
15  IN  PTR  lab-git.lab.local.
16  IN  PTR  lab-virt.lab.local.
```

```bash
sudo mkdir -p /etc/bind/zones
sudo named-checkconf -z
sudo named-checkzone lab.local /etc/bind/zones/db.lab.local
sudo named-checkzone 10.10.10.in-addr.arpa /etc/bind/zones/db.10.10.10
sudo systemctl enable --now named       # alias de bind9.service
sudo ss -ulnp | grep :53                # 10.10.10.14:53 named
```

**Étape 3.** `dig @10.10.10.14 lab-web.lab.local` : `flags: qr aa rd`
(pas de `ra`) ; `dig @10.10.10.14 -x 10.10.10.11` : `lab-web.lab.local.` ;
`dig @10.10.10.14 www.ubuntu.com` : `status: REFUSED` — correct, un
autoritaire ne résout pas pour les autres (Q13.14).

**Étape 4 — secondaire** (`lab-adm`, `/etc/bind/named.conf.options` avec
`listen-on { 10.10.10.10; }; listen-on-v6 { none; }; recursion no;
allow-transfer { none; };`), `/etc/bind/named.conf.local` :

```text
zone "lab.local" {
    type secondary;
    primaries { 10.10.10.14; };
    file "db.lab.local";              # relatif à /var/cache/bind
};
zone "10.10.10.in-addr.arpa" {
    type secondary;
    primaries { 10.10.10.14; };
    file "db.10.10.10";
};
```

```bash
sudo systemctl disable --now dnsmasq 2>/dev/null   # module 12, si présent
sudo named-checkconf && sudo systemctl enable --now named
sudo rndc retransfer lab.local                      # ou attendre le NOTIFY
sudo journalctl -u named | grep -E 'Transfer completed|transferred serial'
dig +short SOA lab.local @10.10.10.14 ; dig +short SOA lab.local @10.10.10.10
dig @10.10.10.14 lab.local AXFR          # depuis lab-adm : zone complète
```

Depuis `lab-web`, `dig @10.10.10.14 lab.local AXFR` donne `Transfer
failed.` et le primaire journalise `zone transfer 'lab.local/AXFR/IN' denied`
: `allow-transfer` n'autorise que `10.10.10.10`. Un transfert de zone est un
inventaire complet du réseau ; on ne l'ouvre qu'aux secondaires.

**Étape 5 — Unbound.** `/etc/unbound/unbound.conf.d/lab.conf` :

```text
server:
    interface: 127.0.0.1
    interface: 10.10.10.53
    access-control: 127.0.0.0/8 allow
    access-control: 10.10.10.0/24 allow
    do-ip6: no
    prefetch: yes
    qname-minimisation: yes
    hide-identity: yes
    hide-version: yes
    # zones privées non signées, servies par nos autoritaires
    domain-insecure: "lab.local"
    domain-insecure: "10.in-addr.arpa"
    local-zone: "10.in-addr.arpa." nodefault
    private-domain: "lab.local"
    private-address: 10.0.0.0/8
    private-address: 172.16.0.0/12
    private-address: 192.168.0.0/16
    private-address: fd00::/8

stub-zone:
    name: "lab.local"
    stub-addr: 10.10.10.14
    stub-addr: 10.10.10.10

stub-zone:
    name: "10.10.10.in-addr.arpa"
    stub-addr: 10.10.10.14
    stub-addr: 10.10.10.10
```

La validation DNSSEC est déjà active par le paquet Ubuntu
(`/etc/unbound/unbound.conf.d/root-auto-trust-anchor-file.conf`), le
contrôle par socket aussi (`remote-control.conf`).

```bash
sudo unbound-checkconf
sudo systemctl enable --now unbound
sudo ss -ulnp | grep :53   # 127.0.0.53 resolved, .53 unbound, .14 named
dig @10.10.10.53 www.ubuntu.com          # flags: qr rd ra ad  (zone signée)
dig @10.10.10.53 lab-db.lab.local        # 10.10.10.12, pas de aa
dig @10.10.10.53 -x 10.10.10.12          # lab-db.lab.local.
dig @10.10.10.53 +dnssec dnssec-failed.org   # status: SERVFAIL
dig @10.10.10.53 +cd dnssec-failed.org   # +cd : sans validation, NOERROR
```

`dnssec-failed.org` est une zone volontairement mal signée : un résolveur
validant **doit** répondre `SERVFAIL` plutôt que servir des données non
authentifiables. `+cd` (checking disabled) montre que les données existent.

**Étape 6.** Deux `dig` : TTL décroissant ; `unbound-control stats_noreset |
grep -E 'total.num.cachehits|total.num.cachemiss'` ; `unbound-control
flush_zone ubuntu.com` puis le `dig` suivant repart avec le TTL plein.

**Étape 7 — migration.** Netplan sur chaque VM Ubuntu :

```yaml
      nameservers:
        addresses: [10.10.10.53]
        search: [lab.local]
```

```bash
sudo netplan try && resolvectl status ens18     # DNS Servers: 10.10.10.53
                                                # DNS Domain: lab.local
sudo sed -i '/lab\.local/{/'"$(hostname -s)"'/!d}' /etc/hosts
getent hosts lab-db ; dig +short lab-db.lab.local
```

::: rhel
`sudo nmcli con mod ens18 ipv4.dns 10.10.10.53 ipv4.dns-search lab.local
ipv4.ignore-auto-dns yes && sudo nmcli con up ens18`. Rocky n'a pas de stub
`systemd-resolved` par défaut : `/etc/resolv.conf` est écrit directement par
NetworkManager.
:::

**Étape 8 — journalisation.** BIND, dans `named.conf.options` (ou un fichier
`named.conf.logging` inclus) :

```text
logging {
    channel queries_log {
        file "/var/log/named/queries.log" versions 3 size 5m;
        severity info; print-time yes;
    };
    category queries { queries_log; };
};
```

`sudo mkdir -p /var/log/named && sudo chown bind:bind /var/log/named`
(AppArmor autorise `/var/log/named/**`), `rndc reconfig`, puis `rndc
querylog on` bascule dynamiquement (sans le canal, les requêtes vont dans le
journal système). Unbound : `log-queries: yes` (+ `verbosity: 1`), visibles
dans `journalctl -u unbound`. Ligne BIND : `client @0x... 10.10.10.53#41232
(lab-db.lab.local): query: lab-db.lab.local IN A -E(0) (10.10.10.14)`. On
désactive ensuite (`rndc querylog off`, `log-queries: no`) : en production,
un résolveur fait des milliers de requêtes par seconde, le journal sature le
disque et contient des données personnelles.

**Étape 9.** `dig +trace lab-web.lab.local` : la racine répond `NXDOMAIN` pour
`local.` (avec preuve NSEC) — le nom n'existe pas sur Internet, seul notre
Unbound sait où le trouver grâce à sa stub-zone. `dig +trace www.ubuntu.com`
descend racine → `com.` → `ubuntu.com.` → réponse. `dig +norecurse
@10.10.10.53 www.debian.org` : réponse pleine si en cache (avec TTL réduit),
sinon `NOERROR` **sans section ANSWER** (le serveur ne va pas chercher) :
c'est le moyen de sonder un cache sans le remplir.

**Étape 10.** Ajouter `grafana IN CNAME lab-ops.lab.local.`, serial
`2026091902`, `rndc reload lab.local`, `dig +short SOA lab.local
@10.10.10.10` passe au nouveau serial en 1-2 s. Unbound peut répondre
`NXDOMAIN` pendant jusqu'à 300 s (TTL négatif du SOA) s'il a déjà été
interrogé pour ce nom : `unbound-control flush_negative` ou `flush_zone
lab.local` règle ça sans redémarrer.

**Étape 11 — split-horizon et DoT.** BIND : deux `view` (`match-clients {
10.10.10.0/24; }` et `any`), chacune avec sa propre copie de la zone — les
zones doivent être déclarées dans **toutes** les vues, y compris les
secondaires. Unbound : `local-data: "www.lab.local. A 172.20.0.11"` dans un
`view:` associé par `access-control-view: 10.10.10.0/24 interne`. DoT : une
`forward-zone: name: "." forward-addr: 9.9.9.9@853#dns.quad9.net
forward-tls-upstream: yes` avec `tls-cert-bundle:
/etc/ssl/certs/ca-certificates.crt` : Unbound devient forwarder chiffré
(plus de récursion, plus de contact avec la racine ; les requêtes ne sont
plus lisibles par le FAI, mais Quad9 voit tout).

::: pourquoi
Trois rôles, trois adresses, trois comportements observables avec `dig` :
`aa` sur l'autoritaire, `ra` + `ad` sur le récursif, `REFUSED` de l'un sur
ce qui est le métier de l'autre. La stub-zone est le pont : elle dit au
récursif « pour ce nom, ne cherche pas dans l'Internet, demande à ces
serveurs ». `domain-insecure` est indispensable parce que le récursif,
validant, essaierait sinon de prouver que `lab.local` est signé ou
qu'il est délégué de façon non signée depuis `local.` — ce qui est impossible,
`local.` n'existant pas dans la racine — et répondrait `SERVFAIL`.
`local-zone: "10.in-addr.arpa." nodefault` retire le blocage par défaut des
zones inverses privées (Unbound répond `NXDOMAIN` localement pour toutes les
plages RFC 1918, par hygiène).
:::

::: piege
`.local` est réservé à mDNS (RFC 6762). `systemd-resolved` envoie
`*.local` en multicast et **pas** au DNS unicast, sauf si `local` (ou
`lab.local`) est un domaine de recherche/routage du lien — c'est le rôle de
`search: [lab.local]` ici. Pour un vrai réseau, préfère `lab.internal` ou
`home.arpa`. Deuxième piège : `listen-on` de BIND par défaut est `any` : il se lie à toutes les adresses de la VM, dont `10.10.10.53`, et Unbound ne peut plus démarrer sur la même VM.
:::

---

### **L13.5** — Bonding actif/passif

**Étapes 1 et 2.**

```bash
# lab-db
ip -br link                      # ens19, ens20 apparaissent (MAC différentes)
sudo ip link add bond0 type bond mode active-backup miimon 100 primary ens19
sudo ip link set ens19 down; sudo ip link set ens19 master bond0
sudo ip link set ens20 down; sudo ip link set ens20 master bond0
sudo ip addr add 172.31.0.12/24 dev bond0; sudo ip link set bond0 up
# lab-web
sudo ip addr add 172.31.0.11/24 dev ens19; sudo ip link set ens19 up
ping -c 2 172.31.0.12
```

`primary` s'écrit au moment du `add` ; sinon `echo ens19 | sudo tee
/sys/class/net/bond0/bonding/primary`.

**Étape 3.** `cat /proc/net/bonding/bond0` :

```text
Bonding Mode: fault-tolerance (active-backup)
Primary Slave: ens19 (primary_reselect always)
Currently Active Slave: ens19
MII Status: up
MII Polling Interval (ms): 100
Slave Interface: ens19
MII Status: up
Link Failure Count: 0
Permanent HW addr: bc:24:11:aa:00:19
Slave Interface: ens20
MII Status: up
Link Failure Count: 0
Permanent HW addr: bc:24:11:aa:00:20
```

`ip link` montre `ens19`, `ens20` et `bond0` avec **la même** MAC (celle du
premier esclave) : en active-backup avec `fail_over_mac=none`, le bond impose
sa MAC à l'esclave actif pour que les commutateurs voient une seule adresse
qui « bouge » de port à la bascule (annoncée par ARP gratuit). `Permanent HW
addr` garde la MAC d'origine de chaque carte.

**Étape 4 — bascule.**

```bash
# Proxmox
qm set 9003 --net1 "$(qm config 9003 | awk '/^net1:/{print $2}'),link_down=1"
# lab-db
cat /proc/net/bonding/bond0 | grep -E 'Active|Failure'
journalctl -k -n 5     # bond0: link status definitely down for interface
                       # ens19, disabling it ; making interface ens20 the
                       # new active one
```

Le `ping -i 0.2` perd 0 à 2 paquets (détection en ≤ 100 ms + `updelay`).
Retour : `link_down=0` → `Link Failure Count: 1`, et le bond **revient** sur
`ens19` après `updelay` parce que `primary ens19` et `primary_reselect
always`. Avec `primary_reselect failure`, il ne reviendrait qu'à la panne de
`ens20` — on l'utilise quand une bascule coûte plus que le déséquilibre.

**Étape 5 — Netplan** (`lab-db`, `/etc/netplan/60-bond.yaml`) :

```yaml
network:
  version: 2
  ethernets:
    ens19: {dhcp4: false}
    ens20: {dhcp4: false}
  bonds:
    bond0:
      interfaces: [ens19, ens20]
      addresses: [172.31.0.12/24]
      parameters:
        mode: active-backup
        primary: ens19
        mii-monitor-interval: 100
```

Supprimer d'abord le bond fait à la main (`ip link del bond0`) puis `netplan
try`, `reboot`, `cat /proc/net/bonding/bond0`.

**Étape 6.** Un `iperf3 -t 30` pendant la bascule : un creux d'un intervalle
(~1 s) à `0 bits/sec` ou un débit réduit, quelques `Retr`, puis reprise. TCP
absorbe la coupure : la session n'a pas bougé (même IP, même MAC).

**Étape 7 — LACP.**

```yaml
      parameters:
        mode: 802.3ad
        lacp-rate: fast
        transmit-hash-policy: layer3+4
        mii-monitor-interval: 100
```

Le commutateur doit configurer un *port-channel* / LAG en LACP actif sur
les deux ports (même vitesse, même VLAN) ; les deux ports doivent aller au
même commutateur ou à une pile (MLAG). Sans partenaire LACP, le bond reste
en « négociation », un seul esclave passe le trafic, et `/proc/net/bonding/
bond0` montre `Partner Mac Address: 00:00:00:00:00:00`. `vmbr1` est un
bridge Linux sans LACP : impossible à tester ici (Open vSwitch sur l'hôte
saurait le faire).

**Étape 8.** `qm set 9003 --delete net1 --delete net2`, `qm set 9002 --delete
net1`, supprimer `60-bond.yaml` et l'adresse sur `lab-web`.

::: pourquoi
`active-backup` est le mode qu'on déploie quand on ne contrôle pas les
commutateurs (ou qu'ils sont deux, sans MLAG) : aucune coopération requise,
un seul chemin actif, bascule en une fraction de seconde. Le prix : la
bande passante d'un seul lien. LACP agrège **et** tolère, mais un flux donné
(un couple IP/port) reste sur un seul lien — `transmit-hash-policy` décide
comment les flux se répartissent ; un `iperf3` mono-flux ne dépassera jamais
le débit d'une carte. `miimon` surveille la porteuse : il ne détecte pas un
commutateur dont le port est up mais qui ne relaie plus (`arp_interval` /
`arp_ip_target` pour ça).
:::

---

## 13.7 Break & Fix

### **BF13.1** — « Les conteneurs ne sortent plus, mais ils se parlent »

*`c1` joint `c2` et le bridge, plus rien au-delà ; le port publié expire ;
les règles sont intactes ; « durcissement sysctl standard ».*

**Diagnostic.**

1. Périmètre : `c1 → c2` (commutation L2) et `c1 → 172.20.0.1` (input local)
   marchent ; seul le trafic **relayé** casse, dans les deux sens. Ça exclut
   le bridge, les veth, les adresses.
2. `sudo tcpdump -i br-lab -nn icmp` pendant `ip netns exec c1 ping
   10.10.10.11` : les requêtes arrivent. `sudo tcpdump -i ens18 -nn icmp` :
   rien ne sort. Le paquet meurt **entre** l'entrée et la sortie du netns
   racine.
3. `sudo nft list chain inet filter forward` : les compteurs de la règle de
   `log`/`drop` ne bougent pas ; `journalctl -k | grep fwd-drop` est vide. Le
   pare-feu ne le jette donc pas — il ne le **voit** même pas.
4. Un paquet relayé qui n'atteint pas `forward` : la décision de routage l'a
   jeté. `sysctl net.ipv4.ip_forward` → `0`.
5. `grep -r ip_forward /etc/sysctl.d/ /etc/sysctl.conf` →
   `/etc/sysctl.d/99-durcissement.conf: net.ipv4.ip_forward = 0`.

**Cause racine.** Le fichier de durcissement (module 18, ou celui du script)
impose `ip_forward=0`, appliqué par `sysctl --system`. Sans forwarding, le
noyau détruit tout paquet dont la destination n'est pas locale, juste après
`prerouting`, silencieusement (compteur `IpForwDatagrams` figé,
`IpInDiscards`... pas même incrémenté selon les versions).

**Correctif.**

```bash
sudo sysctl -w net.ipv4.ip_forward=1
printf 'net.ipv4.ip_forward = 1\n' | sudo tee /etc/sysctl.d/99-minidocker.conf
sudo sysctl --system | grep ip_forward     # la dernière valeur lue gagne
```

Le fichier `99-minidocker.conf` trie **après** `99-durcissement.conf`
(ordre lexical) et l'emporte ; mieux : retirer la ligne du fichier de
durcissement et documenter que cette machine est un routeur.

**Prévention.** Un `minidocker.sh status` qui affiche `ip_forward` (c'est
fait), et un test dans `check` ; côté durcissement, ne jamais appliquer un
profil générique à une machine qui route (Docker, K8s, VPN) — c'est la
première ligne que Docker remet à 1 à son démarrage, et la première chose
qui casse quand on l'arrête.

::: pourquoi
Le chemin §13.2 : `prerouting` → **décision de routage** → `forward`. Le
flag `ip_forward` est testé au moment de la décision de routage : « pas pour
moi » et « forwarding interdit » = destruction immédiate, sans ICMP, sans
compteur netfilter. C'est pourquoi le pare-feu paraît innocent : il l'est.
Le réflexe à installer : quand un routeur Linux ne relaie plus **rien** et
que les règles n'ont pas bougé, `sysctl net.ipv4.ip_forward` avant toute
autre commande. Par netns : `ip netns exec rtr sysctl net.ipv4.ip_forward`,
chaque namespace a le sien.
:::

---

### **BF13.2** — « Le routeur accepte une connexion sur trois »

*Nouvelles connexions échouent aléatoirement, sessions existantes intactes,
CPU nul.*

**Diagnostic.**

1. Le motif « existantes OK, nouvelles KO » désigne conntrack (Q13.8).
   `sudo dmesg | tail` ou `journalctl -k -n 20` : `nf_conntrack: nf_conntrack:
   table full, dropping packet` répété.
2. `sysctl net.netfilter.nf_conntrack_max net.netfilter.nf_conntrack_count` :
   `max = 128`, `count = 128`. Une valeur de `max` ridicule.
3. Qui remplit ? `sudo conntrack -L | awk '{print $1, $4}' | sort | uniq -c |
   sort -rn | head` : une centaine d'entrées `udp` `src=10.10.10.10` vers
   des ports variés, en `UNREPLIED`. `sudo conntrack -L -p udp | head -3` :
   timeout restant ~3 500 s alors qu'un UDP sans réponse devrait expirer en
   30 s. `sysctl net.netfilter.nf_conntrack_udp_timeout` → `3600`.
4. `grep -r nf_conntrack /etc/sysctl.d/` : `99-conntrack.conf` avec
   `nf_conntrack_max = 128` et `nf_conntrack_udp_timeout = 3600`.

**Cause racine.** Table dimensionnée à 128 entrées, et durée de vie des
flux UDP non répondus portée à une heure : une centaine de datagrammes vers
des ports morts suffit à saturer la table pour une heure. Tout nouveau flux
(SSH, HTTP, DNAT) est jeté au premier paquet, au hasard des expirations.

**Correctif.**

```bash
sudo rm /etc/sysctl.d/99-conntrack.conf
sudo sysctl -w net.netfilter.nf_conntrack_max=65536
sudo sysctl -w net.netfilter.nf_conntrack_udp_timeout=30
# purger seulement les entrées fautives, pas la table
sudo conntrack -D -p udp -s 10.10.10.10
sudo sysctl -w net.netfilter.nf_conntrack_buckets=16384
```

Persistance : `/etc/sysctl.d/90-conntrack.conf` avec `net.netfilter.
nf_conntrack_max = 262144` sur un routeur NAT chargé (~300 o par entrée :
80 Mo), et `nf_conntrack_buckets` à `max/4` (paramètre du module :
`options nf_conntrack hashsize=65536` dans `/etc/modprobe.d/`).

**Prévention.** Superviser `nf_conntrack_count / nf_conntrack_max` (node
exporter l'expose : `node_nf_conntrack_entries`), alerter à 80 %. Ne jamais
allonger les timeouts UDP « pour aider les applications » sans mesurer.

::: pourquoi
Les sessions existantes ne souffrent pas parce que leur entrée existe déjà :
le noyau ne refuse que la **création** d'entrées. `conntrack -F` aurait
« réparé » en trente secondes... et coupé toutes les sessions NATées (le
port publié, les sorties des conteneurs) : `-D` avec un filtre est le geste
précis. `nf_conntrack_max` par défaut est calculé sur la RAM
(un multiple fixe de `nf_conntrack_buckets`, de l'ordre de 65 536 à 131 072 sur 2 Go selon le noyau) ; Docker et Kubernetes
le montent eux-mêmes (kube-proxy : 131 072 par cœur).
:::

---

### **BF13.3** — « Le SYN part, la réponse ne revient jamais »

*SYN-ACK visible sur `ens18`, `ping` OK, DNAT : le SYN entre dans `c1`
mais rien ne ressort.*

**Diagnostic.**

1. `tcpdump` voit le SYN-ACK **avant** netfilter : ça ne prouve rien (Q13.6).
   Deux flux cassés dans deux directions (sortie de `c1`, port publié), un
   point commun : le paquet de **retour** d'une connexion TCP, dans le sens
   inverse de l'initiation. Le `ping` passe : ICMP est traité différemment.
2. `sudo nft -a list chain inet filter forward` :

   ```text
   ct state invalid counter packets 0 bytes 0 drop # handle 12
   ip protocol icmp accept # handle 21
   iifname "br-lab" oifname "ens18" ct state new accept # handle 22
   ct status dnat ip daddr 172.20.0.11 tcp dport 8000 accept # handle 15
   limit rate 5/minute burst 5 packets log prefix "fwd-drop: " \
       counter packets 47 bytes 3196 drop # handle 16
   ```

   La règle `ct state established,related accept` **a disparu** ; la règle
   de sortie ne laisse plus passer que les paquets `new` ; une règle ICMP sans
   état a été ajoutée (« on a gardé le ping pour la supervision ») ; et le
   compteur du `drop` final monte à chaque tentative.
3. `sudo journalctl -k | grep fwd-drop | tail -2` : `IN=ens18 OUT=br-lab
   SRC=10.10.10.11 DST=172.20.0.11 ... PROTO=TCP SPT=80 DPT=40312 ... ACK SYN`
   — le SYN-ACK de `lab-web`, jeté en `forward` sur le chemin du retour.
   Pour le port publié : `IN=br-lab OUT=ens18 SRC=172.20.0.11 DST=10.10.10.11
   SPT=8000 ... ACK SYN` (la source ne sera retraduite en `10.10.10.10:8080`
   qu'en `postrouting`) : jeté aussi, il n'est pas `new`.
4. Dans `c1`, `ss -tan state syn-sent` montre la connexion qui attend.

**Cause racine.** Quelqu'un a « nettoyé les règles qui acceptent tout » :
la règle stateful supprimée, la règle de sortie restreinte à `new`. Sans
`established,related`, la chaîne n'accepte que le **premier** sens de chaque
flux ; toute réponse TCP est jetée. ICMP survit grâce à sa règle sans état.

**Correctif immédiat** (une commande, en tête de chaîne) :

```bash
sudo nft insert rule inet filter forward ct state established,related accept
```

`insert` place la règle en **première** position ; `add` la mettrait en fin,
après le `drop`, donc jamais atteinte. Vérifier : `curl` depuis `c1` et
depuis `lab-web`, compteur du `drop` figé. Puis remettre la ligne dans
`minidocker.nft` et recharger avec `nft -f` pour que `up` la rétablisse ; la
restriction `ct state new` sur la règle de sortie peut rester, elle est même
plus propre.

**Prévention.** Le fichier nftables est la source de vérité (chargé par
`nftables.service` depuis `/etc/nftables.conf` en production) ; toute
modification manuelle est perdue au prochain rechargement, c'est voulu. Un
commentaire dans le fichier : `# NE PAS SUPPRIMER : rend le pare-feu
stateful`. Et un test de non-régression : `curl` à travers le NAT après
chaque changement de règles.

::: pourquoi
Un pare-feu où seul le sens « initiateur » est autorisé laisse partir le
SYN et bloque le SYN-ACK : la connexion reste en `SYN-SENT` côté client, qui
réémet 6 fois (1, 2, 4, 8, 16, 32 s) puis abandonne — 2 minutes d'attente.
Le paquet est bien reçu par la machine (`tcpdump` le voit), et pour le
flux masqueradé la destination est bien retraduite par conntrack avant
`forward` (le journal montre `DST=172.20.0.11` : la traduction inverse d'un
SNAT se fait en `prerouting`, celle d'un DNAT en `postrouting`), puis jeté
en `forward`. Les compteurs `counter` et le `log` désignent la règle fautive
sans avoir à raisonner : c'est pour cela qu'un jeu de règles sérieux se
termine toujours par une règle de `drop` **explicite et comptée**, jamais
par la seule politique de chaîne, invisible.
:::

---

### **BF13.4** — « Le tunnel marche, sauf pour les vrais fichiers »

*`ping` et `ssh` par le VXLAN OK, `scp`/`iperf3` de `lab-web` vers `lab-db`
gelés, l'autre sens fonctionne.*

**Diagnostic.**

1. Asymétrique et dépendant de la taille : MTU (module 12). Sur `lab-web` :
   `ping -M do -s 1422 192.168.42.12` → OK ; `-s 1423` → **pas** de
   « message too long », juste un timeout. Un timeout au lieu de l'erreur
   locale signifie que l'interface accepte le paquet : `ip -d link show
   vxlan0` → `mtu 1500`. Anomalie 1.
2. Sur `lab-db`, `sudo tcpdump -i ens18 -nn -v 'host 10.10.10.11 and (udp port 4789 or ip[6:2] & 0x1fff != 0)'` pendant un `ping -M do -s 1472` (paquet interne de 1500 octets) :
   `IP (flags [+], proto UDP) 10.10.10.11 > 10.10.10.12: udp` puis `IP (frag 12345:50@1480)` — le paquet externe de 1550 octets arrive en **deux
   fragments**. Ils arrivent, mais le tunnel ne les voit pas : `tcpdump -i
   vxlan0` sur `lab-db` ne montre rien pour ce `ping`.
3. Des fragments qui arrivent sur `ens18` et n'atteignent pas la pile :
   `sudo nft list ruleset` sur `lab-db` → une table `inet sitefw` avec une
   chaîne `raw_in` (hook `prerouting`, priorité `-450`) et la règle `ip frag-off & 0x3fff != 0 counter drop`, compteur non nul. Anomalie 2 : « le pare-feu du site jette
   les fragments », à une priorité qui précède le réassemblage (`-400`).
4. Dans l'autre sens, `lab-db` a gardé `vxlan0` à 1450 : ses paquets
   externes font au plus 1500, jamais de fragment, donc rien à jeter.

**Cause racine.** Deux erreurs indépendantes qui ne se voient qu'ensemble :
un MTU d'overlay trop grand sur `lab-web` (qui provoque la fragmentation de
l'externe) et un filtrage des fragments sur `lab-db` (qui la rend fatale).
En production, la seconde est presque toujours un équipement intermédiaire
qu'on ne contrôle pas ; d'où la règle : **le MTU de l'overlay doit être
juste**, on ne compte jamais sur la fragmentation.

**Correctif.**

```bash
# lab-web
sudo ip link set vxlan0 mtu 1450          # et mtu: 1450 dans Netplan
# lab-db
sudo nft delete table inet sitefw
```

Après le premier correctif seul, tout refonctionne (plus de fragments) : la
règle de `lab-db` reste un piège pour plus tard, on la retire aussi — ou on
la garde en la documentant, car jeter les fragments non sollicités est une
politique défendable, **à condition** que les tunnels aient le bon MTU.

**Pourquoi `ping` sans option ne voit rien.** 56 octets de données : le
paquet externe fait ~150 octets. Pourquoi aucun ICMP « fragmentation
needed » : personne n'a refusé de fragmenter — `lab-web` a fragmenté
l'externe **sans DF**, légalement ; `lab-db` a jeté les fragments
silencieusement (un pare-feu ne renvoie pas d'ICMP pour un `drop`). Le
paquet interne, lui, avait DF (`-M do`) mais tenait dans le MTU 1500 de
`vxlan0` : aucun étage n'avait de raison de se plaindre. La PMTU découverte
est aveugle par construction ici.

**Prévention.** `mtu: 1450` explicite dans Netplan sur les deux extrémités ;
un test `ping -M do -s 1422` dans la procédure de mise en service d'un
tunnel ; et pour les CNI, `--iface-mtu`/`mtu:` dans la configuration plutôt
que l'auto-détection quand l'underlay a des tunnels imbriqués.

::: pourquoi
L'asymétrie est la signature : un MTU incohérent ne touche que le sens où
l'émetteur croit disposer de plus de place que le chemin n'en offre. C'est
aussi la raison pour laquelle les tests unidirectionnels (« j'ai fait un
`iperf3` depuis le serveur, ça marche ») ne prouvent rien : toujours tester
`-R` (reverse) ou depuis les deux côtés.
:::

---

### **BF13.5** — « Le secondaire DNS vit dans le passé »

*`monitoring.lab.local` connu du primaire, `NXDOMAIN` sur le secondaire,
réponse aléatoire du résolveur.*

**Diagnostic.**

1. La valeur à comparer : le serial.

   ```bash
   dig +short SOA lab.local @10.10.10.14   # ns1.lab.local. ... 2026091902 ...
   dig +short SOA lab.local @10.10.10.10   # ns1.lab.local. ... 2026091902 ...
   ```

   Identiques. Or les contenus diffèrent : le primaire a rechargé une zone
   modifiée **sans** changer le serial.
2. Sur `lab-ops`, `grep -c monitoring /etc/bind/zones/db.lab.local` → 1,
   `journalctl -u named | tail` : `zone lab.local/IN: loaded serial
   2026091902` (le même qu'avant), précédé de l'avertissement
   `zone serial (2026091902) unchanged. zone may fail to transfer to secondaries`,
   puis `sending notifies`. Sur `lab-adm` : `received notify for zone 'lab.local'`
   puis `zone lab.local/IN: notify from 10.10.10.14#...: zone is up to date`.
   Le secondaire a vérifié et a
   conclu, correctement d'après le protocole, qu'il n'y avait rien à
   transférer.
3. Le « parfois » du résolveur : Unbound a deux `stub-addr` (`ns1`, `ns2`)
   et répartit ses requêtes selon les RTT mesurés (`unbound-control
   dump_infra`), puis met en cache. Selon le serveur interrogé, la réponse
   est `A` ou `NXDOMAIN` — et le `NXDOMAIN` est mis en cache 300 s (TTL
   négatif), d'où des périodes entières d'échec.

**Cause racine.** Modification de zone sans incrément du serial. BIND
recharge quand même le fichier (il ne compare pas le serial au sien pour
un `reload`), donc le primaire est à jour, et les secondaires jamais.

**Correctif.**

```bash
# lab-ops : serial 2026091902 -> 2026091903 dans db.lab.local
sudo named-checkzone lab.local /etc/bind/zones/db.lab.local
sudo rndc reload lab.local
# lab-adm, 2 s plus tard
dig +short SOA lab.local @10.10.10.10     # 2026091903
dig +short monitoring.lab.local @10.10.10.10
# lab-ops : purger le NXDOMAIN en cache
sudo unbound-control flush_negative
```

Si le NOTIFY ne suffisait pas : `sudo rndc refresh lab.local` sur le
secondaire (déclenche la vérification SOA), ou `rndc retransfer lab.local`
(force l'AXFR sans comparer — le marteau, à réserver aux cas où le serial a
**reculé**, par exemple après une restauration).

**Prévention.** Serial au format date `AAAAMMJJnn` et procédure « éditer →
`named-checkzone` → serial → `rndc reload` → vérifier le serial sur le
secondaire » ; ou zones dynamiques (`nsupdate`) où BIND gère le serial ; ou
un test dans la CI qui compare le serial du fichier à celui servi. Beaucoup
d'équipes ajoutent un `pre-commit` : si `db.*` change, le serial doit
changer.

::: pourquoi
Le serial est le **seul** signal de réplication du DNS : ni horodatage de
fichier, ni somme de contrôle, ni contenu. « Serial identique = données
identiques » est le contrat que le primaire vient de violer. Le protocole
n'a aucun moyen de le détecter, donc aucune erreur nulle part : c'est la
panne DNS la plus fréquente et la plus longue à voir si on ne sait pas
comparer deux `dig +short SOA`.
:::

---

### **BF13.6** — « Le DNS ne marche plus, sauf pour le lab »

*`lab.local` résout, tout le reste `SERVFAIL` en 2-3 s, Unbound en bonne
santé apparente.*

**Diagnostic.**

1. L'indice principal : `lab.local` est servi par les **stub-zones** (ns1,
   ns2, joignables) ; tout le reste par la récursion. Ce qui casse, c'est la
   résolution « Internet » d'Unbound, pas Unbound lui-même ni le réseau
   (`ping 9.9.9.9` passe).
2. `sudo unbound-control list_forwards` → `. IN forward 10.10.10.99`.
   Unbound n'est plus récursif : il **relaie tout** à `10.10.10.99`, qui
   n'existe pas. `list_stubs` montre toujours `lab.local` : cohérent.
3. `sudo tcpdump -i ens18 -nn 'udp port 53 and host 10.10.10.99'` pendant un
   `dig @10.10.10.53 www.ubuntu.com` : trois ou quatre requêtes vers
   `10.10.10.99`, aucune réponse, puis `SERVFAIL`. `ip neigh show
   10.10.10.99` → `FAILED`.
4. `grep -rn forward /etc/unbound/unbound.conf.d/` →
   `99-forward.conf: forward-zone: name: "." forward-addr: 10.10.10.99`.

**Cause racine.** Un fichier de configuration ajouté (« on a mis le DNS de
l'entreprise en amont ») qui transforme le récursif en forwarder vers une
adresse morte. `unbound-checkconf` ne peut pas le savoir : la syntaxe est
correcte.

**Correctif.**

```bash
sudo rm /etc/unbound/unbound.conf.d/99-forward.conf
sudo unbound-checkconf && sudo unbound-control reload
sudo unbound-control list_forwards        # vide
dig @10.10.10.53 www.ubuntu.com           # NOERROR, flag ad
```

Si un forwarder est réellement voulu, il faut une adresse qui répond et,
idéalement, deux : `forward-addr: 9.9.9.9` et `forward-addr: 149.112.112.112`,
plus `forward-first: yes` pour retomber sur la récursion si les forwarders
échouent.

**Pourquoi 2-3 s et non 30 s.** Unbound ne fait pas un `timeout` unique : il
estime le RTT de chaque serveur (`infra-cache`), commence à ~376 ms, double
à chaque échec et abandonne après quelques tentatives (limite `infra-host-
ttl`, et « serveur marqué down » après 6 échecs), puis rend `SERVFAIL`
plutôt que de faire attendre le client. Le stub `systemd-resolved`, lui,
relaie le `SERVFAIL` immédiatement. Un client `resolv.conf` classique avec
`timeout:5 attempts:2` aurait attendu 10 s ; c'est la différence avec BF12.2.

**Prévention.** Surveiller `unbound-control stats` (`num.answer.rcode.
SERVFAIL`), un test synthétique `dig @10.10.10.53 www.ubuntu.com` dans la
supervision, et une revue des fichiers `unbound.conf.d/` dans la
configuration gérée (Ansible, module 23) : tout fichier inconnu est une
dérive.

::: pourquoi
Récursif et forwarder se ressemblent de l'extérieur (`rd`, `ra`, cache)
jusqu'au jour où l'amont tombe. Le forwarder hérite de la disponibilité de
son amont ; le récursif ne dépend que de la racine et des autoritaires de
chaque zone, qui sont redondants par construction. C'est pour cela que
CoreDNS dans Kubernetes n'est jamais récursif (il *forwarde* au résolveur
du nœud) et que ce résolveur-là, lui, doit être solide : c'est le
`10.10.10.53` de ton lab.
:::

---

## 13.8 Défi du module

**D13 — `minicloud.sh`**

*Deux locataires sur deux bridges, un routeur en namespace, double NAT,
publication par map, DNS, isolation, tests.*

**Topologie et adressage.**

```text
 lab (ens18 10.10.10.10)
   |  masquerade (netns racine)
 tr-root 10.100.0.1/30 ===== tr-rtr 10.100.0.2/30        [netns rtr]
                               |  masquerade vers tr-rtr, forward filtré
              br-t1 10.100.1.1 ----------- br-t2 10.100.2.1   (bridges racine,
               |         |                  |        |      ports : veth de rtr)
            t1-web .11  t1-db .12        t2-web .11  t2-db .12 (+ netem 30 ms)
```

Les bridges vivent dans le netns racine (comme les `vmbr` de Proxmox ou
`br-int` d'OpenStack) mais **sans adresse** : la passerelle de chaque
locataire est l'interface du netns `rtr` raccordée au bridge, exactement le
`qrouter-<uuid>` d'OpenStack Neutron.

**Script** (extrait des fonctions clés ; la structure `up/down/status/test`
et l'idempotence reprennent `minidocker.sh`) :

```bash
#!/usr/bin/env bash
set -euo pipefail
WAN=ens18; NFT_ROOT=/home/mathieu/lab13/nft/minicloud-root.nft
NFT_RTR=/home/mathieu/lab13/nft/minicloud-rtr.nft
WWW=/home/mathieu/lab13/www; ZONE=/home/mathieu/lab13/dns/minicloud.zone.inc

ns_add() { [ -e "/run/netns/$1" ] || ip netns add "$1"
           ip -n "$1" link set lo up; }
veth_ns() { # veth_ns <ns> <ifname dans ns> <ip/len> <bridge racine>
  ip -n "$1" link show "$2" >/dev/null 2>&1 || {
    ip link add "v-$1-$2" type veth peer name "$2" netns "$1"
    ip link set "v-$1-$2" master "$4" up
  }
  ip -n "$1" addr show dev "$2" | grep -q "$3" \
    || ip -n "$1" addr add "$3" dev "$2"
  ip -n "$1" link set "$2" up
}

up() {
  for b in br-t1 br-t2; do
    ip link show "$b" >/dev/null 2>&1 || ip link add "$b" type bridge
    ip link set "$b" up
  done
  ns_add rtr
  veth_ns rtr t1 10.100.1.1/24 br-t1
  veth_ns rtr t2 10.100.2.1/24 br-t2
  ip -n rtr link show tr >/dev/null 2>&1 || {
    ip link add tr-root type veth peer name tr netns rtr
    ip addr add 10.100.0.1/30 dev tr-root; ip link set tr-root up
    ip -n rtr addr add 10.100.0.2/30 dev tr; ip -n rtr link set tr up
  }
  ip -n rtr route show default | grep -q . \
    || ip -n rtr route add default via 10.100.0.1
  ip netns exec rtr sysctl -qw net.ipv4.ip_forward=1
  for t in 1 2; do
    for h in web:11 db:12; do
      n="t$t-${h%%:*}"; ns_add "$n"
      veth_ns "$n" eth0 "10.100.$t.${h##*:}/24" "br-t$t"
      ip -n "$n" route show default | grep -q . \
        || ip -n "$n" route add default via "10.100.$t.1"
    done
    ip route show 10.100.$t.0/24 | grep -q . \
      || ip route add "10.100.$t.0/24" via 10.100.0.2 dev tr-root
    ip netns exec "t$t-web" sh -c "cd $WWW/t$t && nohup python3 -m \
      http.server 8000 >/dev/null 2>&1 &"
  done
  ip netns exec t2-db tc qdisc replace dev eth0 root netem delay 30ms
  sysctl -qw net.ipv4.ip_forward=1
  nft -f "$NFT_ROOT"; ip netns exec rtr nft -f "$NFT_RTR"
  printf 't1-web.cloud IN A 10.100.1.11\nt1-db.cloud  IN A 10.100.1.12\n' \
    > "$ZONE"
  printf 't2-web.cloud IN A 10.100.2.11\nt2-db.cloud  IN A 10.100.2.12\n' \
    -> "$ZONE"
}
```

`minicloud-root.nft` (netns racine : NAT vers le lab, publication par map) :

```text
table ip minicloud {}
flush table ip minicloud
table ip minicloud {
  map publish {
    type inet_service : ipv4_addr . inet_service
    elements = { 8081 : 10.100.1.11 . 8000, 8082 : 10.100.2.11 . 8000 }
  }
  chain prerouting {
    type nat hook prerouting priority -100; policy accept;
    iifname "ens18" dnat to tcp dport map @publish
  }
  chain postrouting {
    type nat hook postrouting priority 100; policy accept;
    ip saddr 10.100.0.0/16 oifname "ens18" counter masquerade
  }
}
```

`minicloud-rtr.nft` (dans `rtr` : isolation entre locataires, NAT de sortie) :

```text
table inet minicloud {}
flush table inet minicloud
table inet minicloud {
  chain forward {
    type filter hook forward priority 0; policy drop;
    ct state established,related accept
    ct state invalid drop
    iifname "t1" oifname "t2" counter drop      # isolation
    iifname "t2" oifname "t1" counter drop
    iifname { "t1", "t2" } oifname "tr" accept  # sortie
    # ports publiés : PAS "ct status dnat" ici, le DNAT a eu lieu dans le
    # conntrack du netns racine, pas dans celui de rtr (voir ci-dessous)
    iifname "tr" ip daddr { 10.100.1.11, 10.100.2.11 } tcp dport 8000 \
        ct state new accept
  }
  chain postrouting {
    type nat hook postrouting priority 100; policy accept;
    oifname "tr" masquerade
  }
}
```

La route de retour côté racine (`10.100.1.0/24 via 10.100.0.2`) est
indispensable au DNAT : après réécriture vers `10.100.1.11`, le netns racine
doit savoir que ce préfixe est derrière `rtr`. Sans elle, `ip route get
10.100.1.11` répond `via 10.10.10.1 dev ens18` et le paquet part vers le lab.

**Double NAT, vu par `nft monitor trace`** (paquet de `lab-web` vers
`10.10.10.10:8082`) : dans le netns racine, `ip minicloud prerouting` →
`dnat to 10.100.2.11:8000` (via la map), `forward` (aucune table filter :
accept), `postrouting` (pas de masquerade, `oifname` est `tr-root`). Dans
`rtr` (`ip netns exec rtr nft monitor trace` avec une règle `nftrace` sur
`tcp dport 8000`) : `forward` → on serait tenté d'écrire `iifname "tr" ct status dnat accept`…
**non** : dans `rtr`, le paquet n'a pas été DNATé (c'est le netns racine qui
l'a fait, chaque netns a son conntrack) : `ct status dnat` est faux dans
`rtr`, et le paquet tomberait sur le `drop`. D'où la règle du fichier ci-dessus : `iifname "tr" ip daddr {
10.100.1.11, 10.100.2.11 } tcp dport 8000 ct state new accept`. C'est le
piège du défi, et la raison de l'astuce « `conntrack -L` dans chaque
netns ».

**`test`** (extrait) :

```bash
t() { if "$@" >/dev/null 2>&1; then echo "OK   $*"; else echo "KO   $*"; fi; }
t ip netns exec t1-web ping -c1 -W1 10.100.1.12
! ip netns exec t1-web ping -c1 -W1 10.100.2.12 >/dev/null 2>&1 \
  && echo "OK   isolation t1 -> t2" || echo "KO   isolation t1 -> t2"
t ip netns exec t1-web curl -s -m 3 http://10.10.10.11/
t ssh mathieu@10.10.10.11 curl -s -m 3 http://10.10.10.10:8081/
t ssh mathieu@10.10.10.11 curl -s -m 3 http://10.10.10.10:8082/
lat=$(ip netns exec t2-web ping -c3 10.100.2.12 | awk -F/ 'END{print $5}')
awk -v l="$lat" 'BEGIN{exit !(l>30)}' && echo "OK   latence $lat ms" \
  || echo "KO   latence $lat ms"
t dig +short t1-web.cloud.lab.local @10.10.10.53
```

**DNS.** Dans `db.lab.local`, après les enregistrements : `$INCLUDE
/home/mathieu/lab13/dns/minicloud.zone.inc` — AppArmor n'autorise pas `named`
à lire `/home` : copier le fragment dans `/etc/bind/zones/` (le script peut
le faire avec `install -m 644`), incrémenter le serial, `rndc reload`.
`$INCLUDE` conserve l'`$ORIGIN` courant : `t1-web.cloud` devient
`t1-web.cloud.lab.local.`.

**`down`.** Tuer les processus de chaque netns (`ip netns pids`), supprimer
les cinq netns (les veth suivent), `ip link del br-t1` puis `ip link del br-t2` (`tr-root`
disparaît avec `rtr`), `nft delete table ip minicloud`, les routes vers
`10.100.x.0/24` (elles disparaissent avec `tr-root`), `ip_forward` restauré.

**Parallèle** (rapport) : OpenStack Neutron crée un netns `qrouter-*` par
routeur virtuel, avec une patte par réseau de locataire et une vers le
réseau externe, du NAT et des IP flottantes (= DNAT 1:1) ; les bridges
`brq-*`/`br-int` sont les `br-t1`/`br-t2`. Kubernetes : un bridge `cni0` par
nœud, les pods en netns derrière, `masquerade` en sortie (`--ip-masq`), un
Service NodePort = une règle DNAT sur tous les nœuds, et les NetworkPolicies
= les règles `forward` d'isolation. Ce que tu viens d'écrire à la main, un
CNI l'écrit avec une map par Service.

::: pourquoi
Le défi force à raisonner **par namespace** : chaque netns a ses routes,
son conntrack, ses règles. Le DNAT est fait à l'entrée du netns racine ; le
NAT de sortie des locataires est fait dans `rtr` ; les deux tables conntrack
ne se parlent pas. Un paquet publié subit donc un DNAT (racine) à l'aller et
aucune traduction dans `rtr` ; un paquet sortant subit un SNAT dans `rtr`
puis un second SNAT dans le racine. Savoir dessiner ces deux étages, c'est
savoir lire n'importe quel « ça marche depuis le nœud mais pas depuis
l'extérieur » dans un cluster.
:::
