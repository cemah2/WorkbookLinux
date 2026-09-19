# Module 11 — Réseau Linux et diagnostic

## 11.0 Objectifs et compétences

::: objectif
À la fin de ce module, je sais :

* calculer de tête un sous-réseau IPv4 (adresse de réseau, diffusion, première et
  dernière adresse utilisable, nombre d'hôtes) et découper un `/24` en blocs
  égaux sans me tromper d'une adresse ;
* lire et modifier à chaud adresses, routes et table de voisinage avec `iproute2`,
  et traduire n'importe quelle commande d'un vieux runbook `ifconfig`/`route`/
  `netstat` vers son équivalent moderne ;
* écrire la même configuration réseau statique de trois façons — Netplan sur
  Ubuntu 24.04, `nmcli` sur Rocky 9, `/etc/network/interfaces` en héritage — et
  dire laquelle est réellement active sur une machine inconnue ;
* expliquer le chemin complet d'une résolution de nom (`nsswitch` → `hosts` →
  stub `127.0.0.53` → serveur amont) et dire à quelle étape ça casse quand
  « ça marche avec l'IP mais pas avec le nom » ;
* interpréter une sortie `dig` section par section (flags, `status`, TTL,
  `AUTHORITY`) et distinguer un `NXDOMAIN` d'un `SERVFAIL` d'un timeout ;
* inventorier les sockets d'une machine avec `ss` et `lsof`, dire ce que révèlent
  `TIME-WAIT` et `CLOSE-WAIT`, et diagnostiquer un service qui n'écoute pas là
  où on croit ;
* tester un service de bout en bout avec `ping`, `traceroute`/`mtr`, `nc -zv` et
  `curl` en mode diagnostic (`-v`, `-I`, `-w`, `--resolve`) ;
* capturer du trafic avec `tcpdump`, écrire un filtre correct, relire une capture
  et y reconnaître une poignée de main, un `RST` et une retransmission ;
* diagnostiquer un MTU cassé sur un tunnel avec `ping -M do -s` et expliquer
  pourquoi « la connexion s'établit puis gèle » ;
* dérouler une checklist ordonnée, couche par couche, face à un
  « le site ne répond pas », et savoir quelle commande tranche à chaque étage.

Temps estimé : 7 h
Prérequis : modules 01 (shell), 08 (processus et systemd). Le pare-feu est traité
au module 15, SSH au module 12 : ici on les suppose ouverts et fonctionnels.
:::

---

## 11.1 Mise en place

VM concernées : **`lab-adm` (10.10.10.10)** et **`lab-web` (10.10.10.11)** pour
l'essentiel, **`lab-rhel` (10.10.10.13)** pour les blocs Rocky.

```bash
# depuis le shell Proxmox, avant de commencer
qm snapshot 9001 avant-lab11
qm snapshot 9002 avant-lab11
```

Paquets nécessaires sur `lab-adm` et `lab-web` :

```bash
sudo apt update
sudo apt install -y iproute2 iputils-ping iputils-tracepath dnsutils \
  traceroute mtr-tiny tcpdump lsof netcat-openbsd curl wget iperf3 \
  ethtool bind9-dnsutils nginx dnsmasq
```

::: rhel
Sous Rocky 9 : `sudo dnf install -y iproute iputils bind-utils traceroute mtr \
tcpdump lsof nmap-ncat curl wget iperf3 ethtool nginx dnsmasq`.
Le paquet `net-tools` (qui fournit `ifconfig`, `route`, `netstat`) n'est installé
par défaut ni sur Ubuntu 24.04 ni sur Rocky 9 : c'est voulu, voir §11.2.
:::

Script de préparation (idempotent, à lancer sur `lab-adm` **et** sur `lab-web`) :

```bash
sudo bash ~/workbook/scripts/setup/setup_M11.sh
```

Il installe un serveur DNS de lab (`dnsmasq` sur `lab-adm`, zone `lab.local`),
publie un vhost `www.lab.local` sur `lab-web`, déploie un faux service applicatif
`factura-api` sur le port 8099, prépare `~/lab11/` et une capture à analyser dans
`/srv/captures/`.

::: attention
Le module modifie la configuration réseau et la résolution de noms. Une erreur
de Netplan peut te couper ta session SSH : utilise `sudo netplan try` (rollback
automatique au bout de 120 s) et garde une console Proxmox ouverte
(`qm terminal 9001`) pendant les labs 11.2 et suivants.
:::

---

## 11.2 Rappel express

### Les couches, vues du diagnostic

| Couche | Ce qui casse | La commande qui tranche |
|---|---|---|
| 1-2 lien | câble, VLAN, MTU, ARP | `ip -br link`, `ip neigh`, `ethtool` |
| 3 IP | adresse, masque, route | `ip a`, `ip route get <ip>` |
| 4 transport | port fermé, filtré | `ss -tulpn`, `nc -zv` |
| 7 application | DNS, vhost, TLS, 5xx | `dig`, `curl -v`, journaux |

Règle : on ne monte d'un étage qu'une fois l'étage du dessous **prouvé**.

### iproute2 — l'essentiel

```bash
ip -br a                    # une ligne par interface, lisible
ip a show dev ens18         # détail d'une interface
ip -4 -br a                 # IPv4 seulement
ip link set dev ens18 up    # monter l'interface
ip a add 10.10.20.10/24 dev ens18       # adresse secondaire, volatile
ip a del 10.10.20.10/24 dev ens18
ip r                        # table de routage principale
ip r add 10.10.20.0/24 via 10.10.10.1 dev ens18
ip r del 10.10.20.0/24
ip route get 9.9.9.9        # LA commande : quelle route, quelle source
ip neigh                    # table ARP / voisinage
ip neigh flush dev ens18
ip -s link show ens18       # compteurs, erreurs, drops
```

`ip a add` et `ip r add` ne survivent **pas** au redémarrage : elles servent au
diagnostic et aux tests, jamais à la configuration définitive.

### net-tools est mort, voici la table de conversion

| Ancien (`net-tools`) | Moderne (`iproute2`) |
|---|---|
| `ifconfig` | `ip a` / `ip -br a` |
| `ifconfig eth0 up` | `ip link set dev eth0 up` |
| `route -n` | `ip r` |
| `route add default gw X` | `ip r add default via X` |
| `arp -an` | `ip neigh` |
| `netstat -tulpn` | `ss -tulpn` |
| `netstat -rn` | `ip r` |
| `netstat -i` | `ip -s link` |

`net-tools` n'est plus maintenu depuis 2011, ne connaît ni les multiples
adresses par interface, ni les tables de routage multiples, ni correctement
IPv6, et lit `/proc/net/*` en texte quand `iproute2` parle à `netlink`.
Sur une machine chargée, `netstat -anp` peut prendre plusieurs secondes là où
`ss -anp` répond instantanément.

### Adressage IPv4 en dix lignes

| Préfixe | Masque | Hôtes utilisables | Usage courant |
|---|---|---|---|
| `/24` | 255.255.255.0 | 254 | LAN standard |
| `/25` | 255.255.255.128 | 126 | demi-LAN |
| `/26` | 255.255.255.192 | 62 | petit segment |
| `/27` | 255.255.255.224 | 30 | DMZ |
| `/30` | 255.255.255.252 | 2 | liaison point à point |
| `/31` | 255.255.255.254 | 2 | liaison PtP (RFC 3021) |

Méthode : `hôtes = 2^(32-préfixe) - 2`. L'adresse de réseau a tous les bits hôte
à 0, la diffusion tous à 1. Le « pas » dans le dernier octet significatif vaut
`256 - dernier octet du masque` : pour un `/26`, pas de 64 → blocs `.0`, `.64`,
`.128`, `.192`.

Plages privées (RFC 1918) : `10.0.0.0/8`, `172.16.0.0/12` (soit `172.16` à
`172.31`), `192.168.0.0/16`. À part : `127.0.0.0/8` boucle locale,
`169.254.0.0/16` link-local (une IP dans cette plage = le DHCP a échoué),
`100.64.0.0/10` CGNAT.

### IPv6, la page qui évite les surprises

* Notation : 8 groupes de 16 bits en hexadécimal, zéros de tête omis, **une
  seule** séquence de groupes nuls remplaçable par `::`.
  `2001:0db8:0000:0000:0000:0000:0000:0001` → `2001:db8::1`.
* `/64` est la taille standard d'un segment. Un site reçoit typiquement un `/56`.
* `fe80::/10` **link-local** : présente sur toute interface IPv6 active, jamais
  routée. Une adresse link-local seule s'utilise avec la zone :
  `ping fe80::1%ens18`, `ssh user@[fe80::1%ens18]`.
* `fd00::/8` ULA, l'équivalent des adresses privées. `::1` boucle locale.
* Ce qui mord : la résolution renvoie **AAAA avant A** (RFC 6724). Si l'hôte a
  une IPv6 mais que le chemin v6 est cassé ou filtré, `curl monsite` échoue alors
  que `curl 10.10.10.11` marche. `curl -4` / `dig A` / `dig AAAA` tranchent.
  Ne « désactive » pas IPv6 par réflexe : corrige le filtrage ou force la famille.

### Résolution de noms — le chemin réel

```text
getaddrinfo()
   └─> /etc/nsswitch.conf   ligne "hosts: files dns" (ou resolve/myhostname)
         ├─ files  -> /etc/hosts        (gagne toujours s'il matche)
         └─ dns    -> /etc/resolv.conf  -> 127.0.0.53 (stub systemd-resolved)
                                            └─> serveur amont réel
```

| Commande | Ce qu'elle interroge |
|---|---|
| `getent hosts www.lab.local` | **toute** la chaîne NSS (donc `/etc/hosts`) |
| `dig www.lab.local` | le DNS uniquement, ignore `/etc/hosts` |
| `resolvectl query www.lab.local` | le résolveur systemd, avec le cache |
| `resolvectl status` | serveurs par lien, domaines de recherche, DNSSEC |
| `resolvectl flush-caches` | vide le cache de `systemd-resolved` |

Sur Ubuntu 24.04, `/etc/resolv.conf` est un lien symbolique vers
`../run/systemd/resolve/stub-resolv.conf` et contient `nameserver 127.0.0.53`.
Ce n'est **pas** le vrai serveur : c'est le stub local. Le vrai serveur est
dans `resolvectl status`. Écrire en dur dans `/etc/resolv.conf` fonctionne
jusqu'au prochain redémarrage, puis le lien est recréé.

### Lire une réponse `dig`

```text
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 42315
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
;; ANSWER SECTION:
www.lab.local.    300  IN  CNAME  lab-web.lab.local.
lab-web.lab.local. 300 IN  A      10.10.10.11
```

`status` : `NOERROR` (réponse valide, même vide), `NXDOMAIN` (le nom n'existe
pas), `SERVFAIL` (le serveur a essayé et échoué : amont injoignable, DNSSEC),
`REFUSED` (le serveur refuse de répondre). Pas de ligne du tout = timeout.
Flags : `aa` réponse faisant autorité, `rd` récursion demandée, `ra` récursion
disponible. Le TTL (la colonne `300`) **décroît** à chaque lecture depuis un
cache : c'est comme ça qu'on prouve qu'on lit du cache.

Types utiles : `A` (IPv4), `AAAA` (IPv6), `CNAME` (alias), `MX` (mail, avec
priorité), `TXT` (SPF, validations), `SRV` (service, `_service._proto.nom`),
`PTR` (inverse), `NS`, `SOA`.

### Sockets et ports

```bash
ss -tulpn          # TCP+UDP, en écoute, numérique, avec processus (sudo)
ss -tanp           # toutes les connexions TCP
ss -s              # résumé par état
ss -t state time-wait
ss -tn 'dport = :443'
ss -tp dst 10.10.10.11
lsof -i :8099      # qui ouvre ce port
lsof -i -P -n      # tous les sockets, sans résolution
```

Poignée de main : `SYN` → `SYN,ACK` → `ACK`. Fermeture : `FIN` → `ACK` →
`FIN` → `ACK`.

| État | Signification | Ce qu'il révèle |
|---|---|---|
| `LISTEN` | socket serveur ouvert | le service est bien démarré |
| `SYN-SENT` | SYN parti, rien en retour | filtrage ou hôte mort |
| `ESTAB` | connexion établie | — |
| `TIME-WAIT` | **nous** avons fermé en premier | normal ; 60 s fixes |
| `CLOSE-WAIT` | le pair a fermé, **pas nous** | bug applicatif : pas de `close()` |

`ss` écrit les états avec des tirets (`TIME-WAIT`, `ESTAB`), `netstat` avec des
soulignés (`TIME_WAIT`, `ESTABLISHED`) : ça compte quand tu grep.

Ports < 1024 : réservés à root (ou à `CAP_NET_BIND_SERVICE`, ou via
`net.ipv4.ip_unprivileged_port_start`). Ports éphémères sortants :
`net.ipv4.ip_local_port_range`, par défaut `32768 60999`.

### Tests, du plus bas au plus haut

```bash
ping -c 3 10.10.10.11               # ICMP : joignable ? latence ?
ping -c 3 -I 10.10.20.10 10.10.10.11   # forcer la source
traceroute -n 9.9.9.9               # UDP par défaut ; -I = ICMP, -T = TCP
mtr -rwc 20 9.9.9.9                 # traceroute + statistiques, rapport
nc -zv 10.10.10.11 80               # le port TCP répond-il ? (z = scan)
curl -sS -o /dev/null -w '%{http_code} %{time_total}\n' http://10.10.10.11/
curl -I https://www.lab.local/      # en-têtes seuls
curl --resolve www.lab.local:443:10.10.10.11 https://www.lab.local/
tcpdump -i ens18 -nn -c 20 'host 10.10.10.11 and tcp port 80'
```

Codes de retour de `curl` à connaître : **6** nom non résolu, **7** connexion
refusée ou impossible, **28** timeout, **35** erreur TLS, **60** certificat non
vérifiable. Ils disent *à quel étage* ça casse, avant même de lire le message.

### Capture

| Option `tcpdump` | Rôle |
|---|---|
| `-i ens18` / `-i any` | interface (obligatoire en pratique) |
| `-nn` | ne résout ni les IP ni les ports |
| `-c 50` | s'arrête après 50 paquets |
| `-w f.pcap` / `-r f.pcap` | écrire / relire |
| `-A` / `-X` | payload en ASCII / hexa |
| `-s0` | capture le paquet entier (défaut moderne) |

Filtres BPF : `host 10.10.10.11`, `net 10.10.10.0/24`, `port 443`,
`src host X and dst port 80`, `tcp[tcpflags] & tcp-syn != 0`, `icmp`.
Dans la sortie, `Flags [S]` = SYN, `[S.]` = SYN-ACK, `[.]` = ACK, `[P.]` =
PSH-ACK (données), `[F.]` = FIN, `[R]` = RESET.

### MTU et fragmentation

MTU Ethernet standard : 1500. Un tunnel ajoute des en-têtes : VXLAN ~50 o
(→ 1450), WireGuard 60-80 o (→ 1420), IPsec 50-70 o. Test :

```bash
ping -M do -s 1472 -c 2 10.10.10.11    # 1472 + 8 (ICMP) + 20 (IP) = 1500
```

`-M do` interdit la fragmentation. Si ça passe à 1472 et échoue à 1473, le MTU
du chemin est 1500. Symptôme d'un MTU cassé : la connexion **s'établit** (petits
paquets), puis gèle dès qu'il y a du volume — parce que les ICMP
« fragmentation needed » (type 3 code 4) sont filtrés quelque part et que la
découverte de MTU de chemin est aveugle.

### Routage et forwarding

```bash
ip r                                 # table main
ip r show table all                  # toutes les tables
ip rule                              # règles de sélection de table
sysctl net.ipv4.ip_forward           # 0 = la machine ne route pas
```

Une route `default via 10.10.10.1 dev ens18 proto static metric 100` : plus la
`metric` est basse, plus la route est préférée. Deux routes par défaut avec la
même métrique = comportement aléatoire, c'est un incident, pas une redondance.
Le NAT côté Linux (`MASQUERADE`) et le filtrage sont au module 15 : ici, retiens
qu'une machine ne relaie **rien** tant que `net.ipv4.ip_forward=1` n'est pas posé.

### Les cinq `sysctl` réseau qui servent vraiment

| Paramètre | Valeur type | Quand y toucher |
|---|---|---|
| `net.ipv4.ip_forward` | 0 → 1 | routeur, NAT, conteneurs |
| `net.core.somaxconn` | 4096 | file d'accept saturée (SYN drops) |
| `net.ipv4.ip_local_port_range` | 32768 60999 | épuisement de ports sortants |
| `net.ipv4.tcp_tw_reuse` | 2 (loopback) | réutiliser des `TIME-WAIT` sortants |
| `net.ipv4.tcp_syncookies` | 1 | protection SYN flood, à laisser à 1 |

Lecture : `sysctl net.ipv4.ip_forward` ou `cat /proc/sys/net/ipv4/ip_forward`
(les deux voient la même chose). Écriture volatile : `sysctl -w`. Persistante :
un fichier dans `/etc/sysctl.d/` puis `sysctl --system`.

### Checklist « le site ne répond pas »

1. Le nom résout-il, et vers quoi ? `getent hosts X` puis `dig X`. Écart entre
   les deux = `/etc/hosts` ou `nsswitch`.
2. L'IP est-elle joignable ? `ping`, et si ICMP est filtré, `ip route get X`
   pour au moins vérifier qu'une route existe.
3. Le port répond-il ? `nc -zv X 443`. Refusé = rien n'écoute. Timeout = filtré.
4. Sur le serveur : est-ce que ça écoute, et **sur quelle adresse** ?
   `ss -tulpn | grep :443`. `127.0.0.1:443` ≠ `0.0.0.0:443`.
5. La couche applicative répond-elle ? `curl -v`, code HTTP, en-têtes, TLS.
6. Le service est-il sain ? `systemctl status`, `journalctl -u`, journaux d'accès.
7. Si tout paraît bon mais que ça gèle : MTU et capture `tcpdump`.

---

## 11.3 Quiz — QCM

**Q11.1** — Sur `lab-adm`, `ip -br a` affiche :

```text
lo     UNKNOWN  127.0.0.1/8 ::1/128
ens18  UP       10.10.10.10/24 fe80::5054:ff:fe1a:2b3c/64
```

Que peux-tu affirmer ?

a) l'interface `lo` est en panne, son état est `UNKNOWN`
b) `ens18` a une adresse IPv6 routable
c) `ens18` est active, avec une IPv4 et une IPv6 link-local
d) la passerelle par défaut est `10.10.10.1`

**Q11.2** — L'adresse `192.168.42.130/26`. Quelle est l'adresse de diffusion ?

a) `192.168.42.255`
b) `192.168.42.191`
c) `192.168.42.159`
d) `192.168.42.130`

**Q11.3** — Combien d'adresses **utilisables** dans un `/21` ?

a) 2048
b) 2046
c) 1022
d) 510

**Q11.4** — Une machine affiche `169.254.12.88/16` sur son interface principale.
Quelle est la cause la plus probable ?

a) l'administrateur a configuré une adresse privée non standard
b) le serveur DHCP n'a pas répondu, la machine s'est auto-attribué une link-local
c) l'interface est en IPv6 uniquement
d) le masque `/16` est incompatible avec cette plage

**Q11.5** — Tu tapes `ip route get 9.9.9.9` et obtiens :

```text
9.9.9.9 via 10.10.10.1 dev ens18 src 10.10.10.10 uid 1000
    cache
```

Qu'apprends-tu de plus qu'avec `ip r` ? **Deux réponses correctes.**

a) l'adresse source qui sera réellement utilisée pour ce paquet
b) que le paquet sortira par `ens18` via `10.10.10.1` après application de toutes
   les règles et métriques
c) que la destination `9.9.9.9` répond au ping
d) que la route est de type statique

**Q11.6** — Sur Ubuntu 24.04, `cat /etc/resolv.conf` affiche
`nameserver 127.0.0.53`. Tu en conclus :

a) que le serveur DNS de l'entreprise est mal configuré
b) que `systemd-resolved` expose un stub local ; le vrai serveur est visible avec
   `resolvectl status`
c) que la machine n'a pas de DNS et résout tout par `/etc/hosts`
d) qu'un `dnsmasq` local écoute sur cette adresse

**Q11.7** — `ping www.lab.local` répond `10.10.10.99`, mais
`dig +short www.lab.local` répond `10.10.10.11`. Quelle est la cause ?

a) le cache de `systemd-resolved` est périmé
b) une entrée dans `/etc/hosts` : `files` passe avant `dns` dans `nsswitch.conf`
c) `dig` ne sait pas résoudre les CNAME
d) `ping` utilise un serveur DNS différent de `dig`

**Q11.8** — `dig lab-inconnu.lab.local` renvoie `status: SERVFAIL`.
Qu'est-ce que ça signifie ?

a) le nom n'existe pas
b) le serveur interrogé a tenté de répondre et a échoué (amont injoignable,
   zone cassée, DNSSEC en erreur)
c) le serveur refuse de te répondre, tu n'es pas dans sa liste d'ACL
d) la requête n'est jamais arrivée, c'est un timeout

**Q11.9** — `ss -tulpn` sur `lab-web` :

```text
Netid State  Local Address:Port Peer Address:Port Process
tcp   LISTEN 127.0.0.1:8099     0.0.0.0:*  users:(("python3",pid=912))
tcp   LISTEN 0.0.0.0:80         0.0.0.0:*  users:(("nginx",pid=744))
```

Depuis `lab-adm`, `curl http://10.10.10.11:8099/` échoue avec le code de retour 7.
Pourquoi ?

a) le service n'est pas démarré
b) il écoute uniquement sur la boucle locale, inaccessible depuis l'extérieur
c) le port 8099 est un port privilégié
d) nginx occupe déjà le port

**Q11.10** — Un serveur accumule 4 000 connexions en `CLOSE-WAIT`. Que fais-tu ?

a) tu augmentes `net.ipv4.tcp_fin_timeout`
b) tu actives `net.ipv4.tcp_tw_reuse`
c) tu remontes le bug à l'équipe applicative : le programme ne ferme pas ses
   descripteurs après le `FIN` du client
d) tu redémarres le réseau

**Q11.11** — 20 000 sockets en `TIME-WAIT` côté client sur un frontal qui fait
beaucoup de requêtes sortantes. **Deux réponses correctes.**

a) c'est l'état normal du côté qui ferme la connexion en premier
b) c'est le signe d'une fuite de descripteurs dans l'application
c) `net.ipv4.tcp_tw_reuse` et l'usage de connexions persistantes (keep-alive)
   sont les leviers pertinents
d) il faut passer `net.ipv4.tcp_fin_timeout` à 5 pour vider la table

**Q11.12** — `curl https://www.lab.local/` renvoie le code de retour 6, sans
aucune sortie. À quel étage est le problème ?

a) TLS : le certificat n'est pas valide
b) résolution de noms : `curl` n'a pas pu obtenir d'adresse
c) transport : le port 443 est fermé
d) applicatif : le serveur renvoie une erreur 500

**Q11.13** — Tu veux tester la nouvelle IP `10.10.10.11` d'un vhost
`shop.lab.local` **avant** de basculer le DNS public. Quelle commande ?

a) `curl -H 'Host: shop.lab.local' https://10.10.10.11/`
b) `curl --resolve shop.lab.local:443:10.10.10.11 https://shop.lab.local/`
c) `curl -k https://10.10.10.11/`
d) `dig @10.10.10.11 shop.lab.local`

**Q11.14** — Un tunnel WireGuard est monté. `ssh` se connecte, la bannière
s'affiche, puis la session gèle dès qu'on lance `ls -lR /usr`. `ping` passe
parfaitement. Quelle piste ?

a) la charge CPU du serveur
b) un MTU inadapté sur le tunnel, avec les ICMP « fragmentation needed » filtrés
c) le serveur SSH est saturé
d) la route par défaut est manquante

**Q11.15** — Quelle commande capture uniquement les paquets échangés avec
`10.10.10.11` sur le port 443, sans résolution DNS, en s'arrêtant après
100 paquets ?

a) `tcpdump -i ens18 -nn -c 100 host 10.10.10.11 and port 443`
b) `tcpdump -i ens18 -c 100 dst 10.10.10.11 port 443`
c) `tcpdump -nn -c 100 -i any 'net 10.10.10.11 or port 443'`
d) `tcpdump -i ens18 -n --count 100 'ip 10.10.10.11:443'`

**Q11.16** — Sur Ubuntu 24.04, tu as modifié `/etc/netplan/01-lab.yaml`. Quelle
séquence est la plus sûre sur une machine à laquelle tu accèdes en SSH ?

a) `sudo netplan apply` puis vérifier
b) `sudo netplan try` puis confirmer dans les 120 s
c) `sudo systemctl restart systemd-networkd`
d) `sudo reboot`

**Q11.17** — Sur `lab-rhel` (Rocky 9), quelle commande fixe l'adresse de façon
persistante ? **Deux réponses correctes.**

a) `nmcli con mod lab-ens18 ipv4.method manual ipv4.addresses 10.10.10.13/24`
b) `ip a add 10.10.10.13/24 dev ens18`
c) éditer `/etc/NetworkManager/system-connections/lab-ens18.nmconnection`
   puis `nmcli con reload && nmcli con up lab-ens18`
d) éditer `/etc/netplan/01-lab.yaml` puis `netplan apply`

**Q11.18** — `ip neigh` affiche :

```text
10.10.10.1 dev ens18 lladdr 52:54:00:aa:bb:cc REACHABLE
10.10.10.11 dev ens18  FAILED
```

Que conclus-tu pour `10.10.10.11` ?

a) le service web de cette machine est arrêté
b) aucune réponse ARP : l'hôte est éteint, sur un autre VLAN, ou l'IP est libre
c) la route par défaut est cassée
d) le cache ARP doit être vidé, l'entrée est juste périmée

---

## 11.4 Quiz — questions ouvertes

**QO11.1** — Décris le chemin **complet** parcouru par `curl https://www.lab.local/`
depuis `lab-adm`, de l'appel `getaddrinfo()` jusqu'au premier octet de réponse.
Nomme à chaque étape le fichier ou le composant impliqué, et cite pour chacune
la commande qui permet de vérifier qu'elle s'est bien passée.

::: repondre
lignes: 12
:::

**QO11.2** — *On te demande en entretien* : « Un utilisateur dit : ça marche avec
l'IP mais pas avec le nom. Donne-moi cinq causes possibles et, pour chacune, la
commande qui la confirme en une seule ligne. »

::: repondre
lignes: 10
:::

**QO11.3** — Explique la différence entre `TIME-WAIT` et `CLOSE-WAIT` : qui ferme,
à quel moment, combien de temps, et ce que chacun t'apprend sur le code de
l'application. Termine par ce qu'il ne faut **pas** faire dans chaque cas.

::: repondre
lignes: 10
:::

**QO11.4** — *On te demande en entretien* : « Une VM ping sa passerelle mais pas
internet. Déroule ton diagnostic. » Donne les commandes dans l'ordre, et à chaque
étape ce que tu regardes exactement dans la sortie.

::: repondre
lignes: 10
:::

**QO11.5** — Trois façons de configurer la même IP statique (Netplan, `nmcli`,
`/etc/network/interfaces`). Sur une machine inconnue, comment détermines-tu en
moins d'une minute laquelle est **réellement** active ? Explique aussi ce qui se
passe si deux d'entre elles sont installées en même temps.

::: repondre
lignes: 10
:::

**QO11.6** — Un tunnel VXLAN relie deux sites. Les sessions s'établissent puis
gèlent sur les gros transferts. Explique le mécanisme complet : où sont ajoutés
les octets d'en-tête, pourquoi le paquet est jeté, quel message ICMP aurait dû
revenir, pourquoi il ne revient pas, et les deux corrections possibles.

::: repondre
lignes: 10
:::

**QO11.7** — Compare `dig`, `getent hosts` et `resolvectl query` : que consulte
chacun, dans quel ordre, et lequel utilises-tu pour prouver qu'un problème vient
du DNS plutôt que de la configuration locale ? Donne un cas où les trois donnent
trois réponses différentes.

::: repondre
lignes: 8
:::

**QO11.8** — `ip a add 10.10.20.10/24 dev ens18` fonctionne, le service répond,
puis tout casse après le redémarrage. Explique pourquoi, et décris comment tu
aurais dû procéder pour que ce soit à la fois testable sans risque et persistant.

::: repondre
lignes: 8
:::

**QO11.9** — Deux serveurs identiques, même application. Un `iperf3` entre eux
donne 940 Mbit/s avec `Retr 0`, un autre donne 210 Mbit/s avec `Retr 4213`.
Qu'est-ce que la colonne `Retr` mesure, et quelles sont les trois causes physiques
ou logiques que tu vas vérifier en priorité ?

::: repondre
lignes: 8
:::

---

## 11.5 Exercices guidés ★

**E11.1** — Affiche en une ligne par interface, sur `lab-adm`, uniquement les
interfaces qui sont `UP` et uniquement leurs adresses IPv4.

**E11.2** — Ajoute à chaud l'adresse secondaire `10.10.20.10/24` sur l'interface
principale de `lab-adm`, prouve qu'elle est active (deux preuves différentes),
puis supprime-la proprement. Explique pourquoi `ip a add` n'écrase pas
l'adresse existante.

**E11.3** — Sans faire un seul paquet vers l'extérieur, détermine par quelle
interface, via quelle passerelle et avec quelle adresse source `lab-adm` joindrait
`9.9.9.9`, puis `10.10.10.12`. Explique l'écart entre les deux réponses.

**E11.4** — Un vieux runbook de l'équipe contient ces quatre lignes. Traduis-les
en `iproute2`, et dis pour chacune ce que l'ancienne commande ne savait pas faire.

```bash
ifconfig eth0 192.168.1.5 netmask 255.255.255.0 up
route add -net 10.20.0.0 netmask 255.255.0.0 gw 192.168.1.1
arp -an
netstat -tulpn | grep 8080
```

**E11.5** — Pour chacune de ces adresses, donne : adresse de réseau, masque en
notation décimale, adresse de diffusion, première et dernière adresse utilisable,
nombre d'hôtes. Fais-le **à la main** d'abord, vérifie ensuite avec `ipcalc` ou
un `python3 -c`.

```text
192.168.42.130/26
172.16.5.200/21
203.0.113.77/28
10.42.7.99/22
192.168.100.37/27
```

**E11.6** — Découpe `10.10.10.0/24` en quatre sous-réseaux égaux. Donne pour
chacun le préfixe CIDR, la plage utilisable et l'adresse de diffusion. Puis dis
dans lequel tombe `10.10.10.130`.

**E11.7** — Ajoute à chaud une route vers `10.10.20.0/24` via `10.10.10.1`,
vérifie qu'elle est prise en compte pour la destination `10.10.20.7`, puis
supprime-la. Vérifie ensuite qu'il ne reste **aucune** trace dans la table.

**E11.8** — Liste tous les sockets TCP IPv4 en écoute sur `lab-web`, avec le nom
et le PID du processus, sans aucune résolution de nom ni de port. Isole ceux qui
écoutent sur une adresse joignable depuis l'extérieur.

**E11.9** — Sur `lab-adm`, lance 50 requêtes `curl` successives vers
`http://10.10.10.11/`, puis compte les sockets par état TCP. Combien sont en
`TIME-WAIT`, et de quel côté de la connexion es-tu ?

**E11.10** — Le port 8099 est occupé sur `lab-web`. Donne deux commandes
différentes qui identifient le processus propriétaire, son utilisateur et le
chemin de son exécutable.

**E11.11** — Avec `dig` : obtiens l'IPv4 de `lab-web.lab.local` en une seule
valeur brute ; interroge explicitement le serveur `10.10.10.10` ; relance deux
fois la même requête et explique ce qui change dans la sortie ; enfin, fais la
résolution inverse de `10.10.10.11`.

**E11.12** — Toujours avec `dig` sur le domaine `lab.local` : affiche le `CNAME`
de `www`, l'enregistrement `MX`, le `TXT` du domaine et le `SRV` de
`_http._tcp.lab.local`. Puis, sur un nom public, montre la délégation complète
depuis la racine.

**E11.13** — Produis une ligne unique qui affiche, pour `http://10.10.10.11/`,
le code HTTP et le temps total séparés par une espace, sans aucun autre affichage.
Puis récupère uniquement les en-têtes de réponse. Puis teste le vhost
`shop.lab.local` sur `10.10.10.11` sans toucher au DNS ni à `/etc/hosts`.

**E11.14** — Vérifie en une commande si les ports 22, 80, 443 et 8099 de
`lab-web` acceptent une connexion TCP, sans transférer de données. Explique la
différence de sortie entre un port fermé et un port filtré.

**E11.15** — Capture 20 paquets de la conversation HTTP entre `lab-adm` et
`lab-web`, sans résolution, dans `/srv/captures/e15.pcap`, pendant qu'un `curl`
tourne. Relis ensuite la capture et identifie les trois paquets de la poignée de
main.

**E11.16** — Détermine par dichotomie le plus grand paquet ICMP que `lab-adm`
peut envoyer à `lab-web` sans fragmentation. Déduis-en le MTU du chemin et
compare avec le MTU affiché sur l'interface.

---

## 11.6 Labs ★★

### **L11.1** — Plan d'adressage et manipulation à chaud

::: contexte
L'équipe infra veut segmenter le lab : un segment pour les serveurs applicatifs,
un pour les bases, un pour l'administration, un en réserve. On te donne
`10.10.10.0/24` et on te demande le plan d'adressage, puis une validation à chaud
sur `lab-adm` avant de figer quoi que ce soit.
:::

Travaille sur `lab-adm`, livrable dans `~/lab11/rapports/plan-adressage.md`.

1. Découpe `10.10.10.0/24` en **quatre** sous-réseaux égaux. Pour chacun :
   préfixe CIDR, masque décimal, adresse de réseau, première et dernière adresse
   utilisable, adresse de diffusion, nombre d'hôtes.
2. Attribue : segment 1 = administration, 2 = applicatif, 3 = bases, 4 = réserve.
   Place les cinq VM du lab dans le bon segment en respectant leurs IP actuelles,
   et signale explicitement celles qui devraient changer d'adresse.
3. On te demande ensuite un segment de **62 hôtes maximum** pour une DMZ, pris
   dans `10.10.0.0/16` sans chevaucher `10.10.10.0/24`. Propose-le et prouve
   l'absence de chevauchement.
4. Sur `lab-adm`, ajoute **à chaud** l'adresse `10.10.20.10/24` sur l'interface
   principale et une route vers `10.10.30.0/24` via `10.10.10.1`.
5. Prouve, sans envoyer de paquet, quelle source et quelle interface seraient
   utilisées pour joindre `10.10.30.5`, puis `10.10.20.99`, puis `9.9.9.9`.
   Note les trois réponses dans le rapport et explique les écarts.
6. Nettoie : l'adresse et la route ajoutées doivent avoir disparu, et tu dois
   pouvoir le prouver.

::: astuce
`ip route get` applique toutes les règles, métriques et routes plus spécifiques :
c'est la seule commande qui répond « voilà ce que le noyau ferait vraiment ».
:::

::: check
Critère de succès : le rapport contient les quatre sous-réseaux avec des valeurs
exactes, la proposition de DMZ, et les trois sorties de `ip route get`. Aucune
adresse ni route de test ne subsiste sur l'interface.

```bash
bash check_M11_01.sh
```
:::

---

### **L11.2** — La même configuration, trois fois : Netplan, nmcli, ifupdown

::: contexte
Le parc est hétérogène : Ubuntu 24.04 en majorité, quelques Rocky 9, et deux
vieilles machines Debian encore en `/etc/network/interfaces`. On te demande une
fiche de référence qui donne **la même configuration** dans les trois formalismes,
et son application réelle sur `lab-adm` et `lab-rhel`.
:::

Livrable écrit : `~/lab11/rapports/reseau-3-formalismes.md`.
La configuration cible, identique partout :

```text
interface principale : ens18
adresse              : celle de la VM, en /24
passerelle           : 10.10.10.1
DNS                  : 10.10.10.10 puis 9.9.9.9
domaine de recherche : lab.local
adresse secondaire   : 10.10.20.<dernier octet>/24
```

1. Sur `lab-adm`, écris `/etc/netplan/01-lab.yaml` complet (version 2, renderer
   `networkd`, pas de DHCP). Attention aux droits du fichier : `netplan` doit
   cesser de râler.
2. Applique-le avec `sudo netplan try` depuis une console Proxmox, pas depuis ta
   session SSH. Explique dans ton rapport ce que fait `try` que `apply` ne fait
   pas, et ce qui se passe si tu ne confirmes pas.
3. Vérifie le résultat de trois façons : la vue de `netplan` lui-même, la vue du
   noyau, et la vue du démon qui a appliqué la configuration.
4. Neutralise la configuration concurrente éventuelle : liste tous les fichiers
   pris en compte par `netplan` et dis lequel gagne en cas de doublon.
5. Sur `lab-rhel` (Rocky 9), obtiens exactement la même chose avec `nmcli` :
   méthode manuelle, adresse, passerelle, DNS, domaine de recherche, adresse
   secondaire. Montre le fichier généré et ses droits.
6. Écris dans le rapport l'équivalent `/etc/network/interfaces` de cette
   même configuration (tu ne l'appliques pas), et indique les deux commandes
   qui l'activent et la désactivent.
7. Conclus par une procédure en trois lignes : « sur une machine inconnue,
   comment je détermine quel outil pilote réellement le réseau ».

::: attention
Une erreur dans `01-lab.yaml` peut te couper de la machine. `netplan try` ramène
la configuration précédente après 120 s sans confirmation : c'est ton filet.
Ne lance jamais `netplan apply` à l'aveugle sur une machine distante.
:::

::: check
Critère de succès : `lab-adm` a ses deux adresses, sa route par défaut et son
domaine de recherche après un redémarrage complet, le fichier Netplan est en
`0600`, et le rapport contient les trois formalismes.

```bash
bash check_M11_02.sh
```
:::

---

### **L11.3** — Ticket INC-3307 : « le nouveau site répond par intermittence »

::: contexte
Un dev signale que `www.lab.local` répond parfois l'ancienne application, parfois
la nouvelle, « selon la machine ». Le DNS du lab (`dnsmasq` sur `lab-adm`) a été
mis à jour hier. Ta mission : établir la vérité, expliquer chaque comportement
observé, et remettre de l'ordre dans la chaîne de résolution.
:::

Travaille depuis `lab-adm`, puis vérifie depuis `lab-web`.

1. Établis la réponse **faisant autorité** : interroge directement le serveur du
   lab pour `www.lab.local`. Note le type d'enregistrement, la cible, le TTL, et
   le `status` de la réponse.
2. Compare avec ce que voit réellement le système (`getent hosts`) et avec ce que
   voit le résolveur systemd. Les trois doivent-ils donner la même chose ? Si ce
   n'est pas le cas, explique précisément pourquoi.
3. Inspecte `/etc/hosts` et `/etc/nsswitch.conf`. Identifie l'entrée qui
   court-circuite le DNS, et démontre son effet avec deux commandes qui donnent
   deux réponses différentes pour le même nom.
4. Corrige : le DNS doit faire foi pour tout ce qui est en `lab.local`.
   `/etc/hosts` ne doit plus contenir que ce qui est indispensable au démarrage.
5. Prouve la présence d'un cache : interroge deux fois le même nom via
   `systemd-resolved` et montre la variation du TTL. Vide le cache et refais la
   mesure.
6. Configure le domaine de recherche pour que `ping lab-db` fonctionne sans
   suffixe. Montre la différence entre `search` et `domain`, et prouve le
   fonctionnement.
7. Inventorie les enregistrements de la zone : `A` des cinq VM, `CNAME` de `www`,
   `MX`, `TXT`, `SRV` de `_http._tcp`, et le `PTR` de `10.10.10.11`. Mets-les
   dans `~/lab11/rapports/zone-lab-local.md` avec, pour chacun, la commande qui
   l'obtient.
8. Enfin : `dnsmasq` écoute sur `10.10.10.10:53` alors que `systemd-resolved`
   occupe `127.0.0.53:53` sur la même machine. Explique comment les deux
   cohabitent sans conflit, preuve `ss` à l'appui.

::: check
Critère de succès : `getent hosts www.lab.local` et `dig +short www.lab.local`
donnent la même adresse, `ping -c1 lab-db` fonctionne sans suffixe, et le rapport
de zone contient les six types d'enregistrements.

```bash
bash check_M11_03.sh
```
:::

---

### **L11.4** — Audit des sockets et lecture des états TCP

::: contexte
Avant une revue de sécurité, on te demande l'inventaire exact de ce qui écoute
sur `lab-web` : quel port, quelle adresse, quel processus, quelle unité systemd,
et si c'est joignable depuis l'extérieur. Dans la foulée, l'équipe applicative se
plaint d'un « problème réseau » sur son API : à toi de démontrer ce qu'il en est.
:::

1. Produis dans `~/lab11/rapports/sockets.md` un tableau à quatre colonnes :
   protocole, adresse:port en écoute, processus (nom + PID), unité systemd.
   Génère-le par script, pas à la main.
2. Marque dans ce tableau les sockets **exposés** (joignables depuis
   `10.10.10.0/24`) et ceux qui ne le sont pas. Justifie le critère que tu
   utilises pour trancher.
3. Depuis `lab-adm`, vérifie ton tableau : pour chaque port marqué exposé, prouve
   l'accessibilité TCP ; pour chaque port marqué local, prouve l'inverse. Note le
   code de retour obtenu à chaque fois.
4. Le service `factura-api` écoute sur `127.0.0.1:8099`. Sans modifier le code de
   l'application, rends-le joignable depuis `lab-adm` sur le port 80, chemin
   `/api/`. Explique pourquoi c'est préférable à un simple changement d'adresse
   d'écoute.
5. États TCP : depuis `lab-adm`, lance 200 requêtes courtes vers `lab-web`, puis
   compte les sockets par état des deux côtés. Explique quel côté accumule des
   `TIME-WAIT` et pourquoi.
6. Reproduis un `CLOSE-WAIT` : `~/lab11/bin/mauvais-serveur.py` accepte les
   connexions et ne les ferme jamais. Lance-le, connecte-toi, déconnecte le
   client, et observe. Explique ce que tu vois et ce que tu écrirais dans le
   ticket adressé aux développeurs.
7. Relève et interprète `net.core.somaxconn`, `net.ipv4.ip_local_port_range` et
   `net.ipv4.tcp_tw_reuse` sur `lab-web`. Pour chacun : valeur actuelle, ce qu'il
   limite, et le symptôme observable quand il est trop bas. Pose une valeur
   persistante pour `somaxconn` via `/etc/sysctl.d/`.

::: astuce
`systemctl status <PID>` remonte du PID à l'unité systemd : c'est le chaînon qui
manque souvent entre `ss -tulpn` et « qui a démarré ça ».
:::

::: check
Critère de succès : le rapport existe et est cohérent avec la réalité de la
machine, `curl http://10.10.10.11/api/` répond depuis `lab-adm`, et
`somaxconn` est réglé de façon persistante.

```bash
bash check_M11_04.sh
```
:::

---

### **L11.5** — Capture, MTU et bande passante

::: contexte
Une équipe monte un tunnel entre deux sites. Les sessions s'ouvrent, puis
« gèlent au hasard » sur les gros transferts. En parallèle, on te demande de
mesurer et de documenter la bande passante réelle entre `lab-adm` et `lab-web`.
On te demande une analyse écrite, pas une intuition.
:::

1. Capture sur `lab-adm` l'échange HTTP complet avec `lab-web` pendant qu'un
   `curl` récupère `http://10.10.10.11/`. Écris la capture dans
   `~/lab11/captures/http.pcap`, sans résolution, filtre limité au strict
   nécessaire.
2. Relis la capture et identifie, en citant les lignes : les trois paquets de la
   poignée de main, la requête `GET`, le premier paquet de données de réponse, et
   la fermeture. Note ce que tu déduis des drapeaux à chaque étape.
3. Analyse `/srv/captures/incident.pcap`, fournie par le setup. Réponds : quelles
   adresses et ports sont en jeu, combien de tentatives de connexion, comment
   elles se terminent, et quelle est la panne. Écris ta conclusion en cinq lignes
   dans `~/lab11/rapports/capture.md`.
4. Détermine le MTU du chemin `lab-adm` → `lab-web` par dichotomie ICMP. Donne la
   valeur, la méthode, et le calcul qui la relie au MTU de l'interface.
5. Simule le tunnel : abaisse le MTU de l'interface de `lab-adm` à 1400. Refais
   la dichotomie, puis un transfert volumineux vers `lab-web`. Documente ce qui
   se passe et ce qui ne se passe pas.
6. Remets le MTU à 1500 et vérifie que tout est revenu à la normale.
7. Bande passante : lance `iperf3` en serveur sur `lab-web`, mesure depuis
   `lab-adm` en TCP sur 10 secondes, puis avec 4 flux parallèles, puis en sens
   inverse. Reporte débit et colonne `Retr` pour chaque essai dans
   `~/lab11/rapports/debit.md`, et explique les écarts.
8. Refais une mesure `iperf3` avec le MTU à 1400 et compare. Conclusion en deux
   lignes.

::: attention
Baisser le MTU d'une interface coupe parfois les sessions SSH en cours sur les
gros transferts. Fais l'étape 5 depuis la console Proxmox ou accepte de
reconnecter ta session.
:::

::: check
Critère de succès : les deux captures existent et sont lisibles, les rapports
`capture.md` et `debit.md` sont renseignés, le MTU de l'interface est revenu à
1500.

```bash
bash check_M11_05.sh
```
:::

---

## 11.7 Break & Fix ★★★

::: attention
Avant chaque Break & Fix : `qm snapshot 9001 avant-bf11` (et `9002` pour BF11.3).
Le snapshot de secours reste `snap-clean` (`qm rollback 9001 snap-clean`), mais
l'utiliser vaut échec de l'exercice : l'objectif est de réparer, pas de rembobiner.
Les Break & Fix de ce module cassent le réseau : garde une console Proxmox ouverte.
:::

### **BF11.1** — « Plus d'internet, mais le lab fonctionne »

```bash
sudo bash break_M11_01.sh
```

**Symptôme utilisateur** : sur `lab-adm`, `ping 10.10.10.11` répond parfaitement,
`ssh lab-web` fonctionne, mais `apt update` reste bloqué puis échoue, et
`ping 9.9.9.9` répond `Network is unreachable` **immédiatement** — pas après un
délai.

**Interdit** : redémarrer la machine, relancer `netplan apply`, toucher au
pare-feu.

**Objectif** : rétablir la sortie, d'abord dans la session en cours puis de façon
durable. Explique dans ta réponse pourquoi le message arrive instantanément et
ce que ça t'a appris avant même de lancer la moindre commande de diagnostic.

::: repondre
lignes: 10
:::

### **BF11.2** — « Tout est lent, puis plus rien ne résout »

```bash
sudo bash break_M11_02.sh
```

**Symptôme utilisateur** : sur `lab-adm`, `curl http://10.10.10.11/` répond
instantanément, mais `curl http://www.lab.local/` attend une dizaine de secondes
puis échoue avec `Could not resolve host`. `apt update` est devenu interminable.
`ping 9.9.9.9` fonctionne.

**Interdit** : réinstaller un paquet, éditer `/etc/hosts` pour contourner.

**Objectif** : rétablir la résolution de noms de façon durable — c'est-à-dire qui
survive à un redémarrage — et expliquer pourquoi le délai est d'environ dix
secondes et pas d'une seconde ni d'une minute.

::: repondre
lignes: 10
:::

### **BF11.3** — « L'API répond sur le serveur mais pas depuis le poste d'admin »

```bash
# à lancer sur lab-web
sudo bash break_M11_03.sh
```

**Symptôme utilisateur** : sur `lab-web`, `curl http://localhost:8099/health`
répond `{"status": "ok", ...}`. Depuis `lab-adm`, `curl http://10.10.10.11:8099/health`
échoue immédiatement, code de retour 7. Le service est `active (running)`, les
journaux ne montrent aucune erreur, et l'équipe applicative jure n'avoir rien
changé.

**Interdit** : toucher au pare-feu (il est désactivé, vérifie-le une fois et
passe à autre chose), modifier le code de l'application.

**Objectif** : identifier la cause exacte avec une seule commande décisive,
rétablir l'accès depuis `lab-adm`, et expliquer la différence entre les codes de
retour 7 et 28 de `curl` — et ce que chacun t'aurait appris ici.

::: repondre
lignes: 10
:::

### **BF11.4** — « Cette machine-là voit un autre site que les autres »

```bash
sudo bash break_M11_04.sh
```

**Symptôme utilisateur** : depuis `lab-adm`, `curl http://www.lab.local/` renvoie
`Connection refused`. Depuis `lab-web` et `lab-db`, le même site répond
normalement. `dig +short www.lab.local` depuis `lab-adm` renvoie pourtant la
bonne adresse, `10.10.10.11`, et `curl http://10.10.10.11/` fonctionne.

**Interdit** : vider le cache DNS en espérant que ça passe, modifier le serveur
DNS du lab.

**Objectif** : expliquer l'écart entre `dig` et le comportement réel du client,
en donnant la commande qui le prouve en une ligne, corriger, et énoncer la règle
générale à retenir sur l'ordre de consultation des sources de noms.

::: repondre
lignes: 8
:::

---

## 11.8 Défi du module ★★★

**D11 — `netdiag.sh` : le diagnostic réseau ordonné, couche par couche**

::: contexte
L'astreinte reçoit trop souvent des tickets « le site ne répond pas » sans aucune
information exploitable. On te demande l'outil qui produit, en une exécution et
en moins de trente secondes, le rapport que tu aurais écrit à la main : ordonné
par couche, avec un verdict clair à chaque étage et un premier diagnostic.
Livrable : un script plus un rapport d'exemple.
:::

Cahier des charges :

1. Écris `~/bin/netdiag.sh`, en bash, commençant par `#!/usr/bin/env bash` et
   `set -euo pipefail`, sans dépendance hors des paquets du §11.1, exécutable
   par un utilisateur non privilégié (les tests qui exigent `sudo` sont ignorés
   proprement avec une mention, jamais une erreur fatale).
2. Usage : `netdiag.sh [-p port] [-4|-6] <cible>` où `<cible>` est un nom ou une
   URL. Par défaut : port 443 si l'URL est en `https`, 80 sinon.
3. Le script déroule **dans cet ordre** et s'arrête au premier étage
   définitivement bloquant, en le disant :
   * **L2/L3 local** : interfaces `UP`, adresses, MTU, route par défaut présente,
     passerelle joignable en ARP (`ip neigh`) ;
   * **résolution** : ce que dit `/etc/hosts`, ce que dit le DNS, et si les deux
     divergent — c'est une anomalie à signaler, pas une erreur fatale ;
   * **route** : `ip route get` vers l'IP retenue, interface et source utilisées ;
   * **accessibilité L3** : ping, avec mention explicite si l'ICMP semble filtré ;
   * **transport** : ouverture TCP sur le port, avec distinction refusé / filtré ;
   * **application** : code HTTP, temps total, taille, en-têtes `Server` et
     `Location`, et pour HTTPS la date d'expiration du certificat ;
   * **MTU** : plus grand paquet non fragmenté vers la cible, et alerte si
     inférieur à 1500.
4. Sortie : un rapport Markdown sur stdout avec une ligne de verdict par étage au
   format `| couche | test | OK/KO/SKIP | détail |`, suivi d'une section
   « Diagnostic » de trois lignes maximum qui nomme l'étage fautif et la cause la
   plus probable. Toute la trace de débogage part sur stderr :
   `netdiag.sh www.lab.local > rapport.md` doit produire un Markdown propre.
5. Code de retour : 0 si tous les étages sont OK, 1 si un étage est KO, 2 si la
   cible est inutilisable (argument invalide).
6. Le script doit donner un diagnostic **correct** sur les quatre pannes du §11.7.
   Rejoue-les une à une et vérifie que la section « Diagnostic » nomme le bon
   étage à chaque fois. Consigne les quatre sorties dans
   `~/lab11/rapports/netdiag-validation.md`.
7. Livre `~/lab11/rapports/netdiag-www.md`, généré par le script sur
   `www.lab.local` avec le lab en état nominal.

Temps visé : 60 à 90 minutes.

::: astuce
Écris d'abord les sept fonctions de test avec un verdict en dur, vérifie la mise
en forme et le code de retour, puis remplis les tests un par un. Tu éviteras de
déboguer en même temps la logique et l'affichage.
:::

::: check
```bash
bash check_M11_06.sh
```
:::

---

## 11.9 Auto-évaluation

| Compétence | Acquis | À revoir |
|---|---|---|
| Calculer un sous-réseau sans outil | ☐ | ☐ |
| Découper un bloc en sous-réseaux égaux | ☐ | ☐ |
| Lire et modifier adresses et routes avec `iproute2` | ☐ | ☐ |
| Traduire un runbook `net-tools` vers `iproute2` | ☐ | ☐ |
| Écrire une conf Netplan complète et l'appliquer sans risque | ☐ | ☐ |
| Faire la même chose avec `nmcli` sur Rocky 9 | ☐ | ☐ |
| Décrire la chaîne de résolution et trouver où elle casse | ☐ | ☐ |
| Interpréter une sortie `dig` (status, flags, TTL) | ☐ | ☐ |
| Inventorier les sockets et lire les états TCP | ☐ | ☐ |
| Diagnostiquer avec `nc`, `curl -v`, codes de retour | ☐ | ☐ |
| Capturer et relire du trafic avec `tcpdump` | ☐ | ☐ |
| Diagnostiquer un MTU cassé | ☐ | ☐ |
| Dérouler la checklist « le site ne répond pas » | ☐ | ☐ |

Pour aller plus loin :

* Relis une capture `tcpdump` dans Wireshark (`File > Open`, puis
  `Statistics > Conversations` et `Follow > TCP Stream`). Transfère le `.pcap`
  avec `scp` : on capture sur le serveur, on analyse sur son poste.
* Monte une seconde table de routage avec `ip rule add from 10.10.20.10 table 100`
  et une route par défaut dans cette table : c'est le mécanisme derrière le
  routage par politique et les configurations multi-liens.
* Compare `traceroute` (UDP), `traceroute -I` (ICMP) et `traceroute -T -p 443`
  (TCP) vers la même destination : les résultats diffèrent, et cet écart est
  lui-même une information sur le filtrage du chemin.
