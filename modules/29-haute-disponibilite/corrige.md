<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Partie V — Expertise système › **Module 29** · corrigé  
[← Module 28](../28-identite-centralisee/corrige.md) · [Énoncé](README.md) · [Module 30 →](../30-sauvegarde-pra/corrige.md)

> [!TIP]
> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, pas avant. Chaque identifiant renvoie à son énoncé.
<!-- nav:fin -->

# Module 29 — Corrigé

## 29.3 Quiz — QCM

<a id="q29-1"></a>**[Q29.1](README.md#q29-1)** — *Disponibilité d'un répartiteur, de deux serveurs web redondants et d'une base.*

**Réponse : c)** environ 99,84 %.

> [!NOTE]
> **Pourquoi**
>
> On réduit le schéma par étapes :
>
> * les deux serveurs web en **parallèle** : indisponibilité 0,01 × 0,01 =
>   0,0001, soit une disponibilité de 99,99 % ;
> * puis les trois étages en **série** : 0,9995 × 0,9999 × 0,999 ≈ 0,99840.
>
> Soit environ 14 heures d'indisponibilité par an, dont la quasi-totalité vient
> de la base unique (8 h 46 min) et du répartiteur (4 h 23 min) : la redondance
> des serveurs web n'a presque rien apporté tant que les deux autres étages
> restent seuls. C'est la leçon de ce calcul : on investit sur le **maillon le
> plus faible**, et un composant unique en série plafonne tout le reste.
>
> Ce calcul suppose des pannes indépendantes et une bascule parfaite. Deux
> serveurs sur le même hyperviseur, ou une bascule qui prend 30 secondes,
> font mentir le résultat.

---

<a id="q29-2"></a>**[Q29.2](README.md#q29-2)** — *Transport des annonces VRRP.*

**Réponse : a)** protocole IP 112, multicast `224.0.0.18`.

> [!NOTE]
> **Pourquoi**
>
> VRRP n'est ni TCP ni UDP : c'est un protocole IP à part entière, numéro 112
> dans `/etc/protocols`, avec un TTL de 255 (un paquet reçu avec un autre TTL
> est rejeté, ce qui garantit qu'il vient du segment local). En IPv6, le
> groupe est `ff02::12`.
>
> Conséquences pratiques :
>
> * un pare-feu doit l'autoriser **par protocole** (`-p 112` ou
>   `ip protocol vrrp`), pas par port ;
> * certains réseaux (clouds publics, certains commutateurs) filtrent le
>   multicast : on passe alors en **unicast** (`unicast_peer`), ce que fait
>   L29.2 ;
> * `tcpdump -ni ens18 vrrp` montre les annonces, avec priorité et
>   intervalle.

---

<a id="q29-3"></a>**[Q29.3](README.md#q29-3)** — *ARP gratuit après une bascule.*

**Réponse : d)** pour mettre à jour les commutateurs et les caches ARP.

> [!NOTE]
> **Pourquoi**
>
> keepalived peut utiliser une adresse MAC virtuelle (`use_vmac`), mais par
> défaut il pose l'IP virtuelle sur l'interface réelle, avec la **MAC du
> nœud**. Après une bascule, l'IP n'a donc plus la même MAC. Les machines du
> segment ont l'ancienne association en cache (de quelques dizaines de
> secondes à plusieurs minutes) et continueraient d'envoyer à l'ancien nœud.
>
> L'ARP gratuit est une réponse ARP non sollicitée (« 10.10.10.20 est à
> `bc:24:11:…` ») diffusée sur le segment : les caches ARP se mettent à jour et
> les commutateurs apprennent sur quel port se trouve désormais cette MAC.
> keepalived en envoie une rafale au passage à l'état maître
> (`vrrp_garp_master_delay`, `vrrp_garp_master_repeat`), puis éventuellement à
> intervalle régulier (`vrrp_garp_master_refresh`) pour les équipements qui
> l'auraient manquée. E29.6 le montre dans le cache ARP de `lab-adm`.

---

<a id="q29-4"></a>**[Q29.4](README.md#q29-4)** — *Script de suivi en échec, `weight -60`.*

**Réponse : b)** `lab-ha1` passe à 90 et `lab-ha2` devient maître.

> [!NOTE]
> **Pourquoi**
>
> Avec un `weight` négatif, l'échec du script **retranche** la valeur à la
> priorité effective : 150 − 60 = 90 < 100. À la prochaine annonce, `lab-ha2`
> voit un maître de priorité inférieure et prend la place (il préempte). Le
> calcul du poids est le point à vérifier : avec `weight -40`, `lab-ha1`
> resterait maître à 110 avec un HAProxy mort.
>
> Sans `weight`, un script en échec met l'instance en état `FAULT` : elle
> relâche l'IP, ce qui marche aussi, mais un nœud en `FAULT` ne peut pas
> reprendre l'IP même si l'autre nœud tombe ensuite. Le poids donne un
> comportement plus nuancé.

---

<a id="q29-5"></a>**[Q29.5](README.md#q29-5)** — *Deux paires keepalived avec le même `virtual_router_id`.*

**Réponse : c)** annonces mélangées et bascules intempestives.

> [!NOTE]
> **Pourquoi**
>
> Le VRID identifie le routeur virtuel sur le segment et fixe sa MAC virtuelle
> (`00:00:5e:00:01:33` pour 51). Deux groupes qui partagent un VRID reçoivent
> les annonces l'un de l'autre. keepalived compare alors des annonces qui ne
> correspondent pas à sa configuration (autres adresses) : il journalise des
> erreurs (`ip address associated with VRID … not present in MASTER
> advert`), et selon les priorités un nœud d'une paire peut se croire
> supplanté par un nœud de l'autre paire.
>
> Règle d'exploitation : un **registre** des VRID par segment, comme on tient
> un registre des adresses IP. L'unicast limite le problème (on n'écoute que
> ses pairs déclarés), mais ne dispense pas de VRID uniques.

---

<a id="q29-6"></a>**[Q29.6](README.md#q29-6)** — *Contrôle TCP ou contrôle HTTP.*

**Réponse : d)** sans `httpchk`, simple connexion TCP ; avec, requête HTTP.

> [!NOTE]
> **Pourquoi**
>
> Un contrôle TCP prouve seulement qu'un processus accepte des connexions sur
> le port. Une application bloquée (base injoignable, threads épuisés,
> `500` sur toutes les pages) passe ce test haut la main, et HAProxy continue
> de lui envoyer du trafic. Le contrôle de niveau 7 envoie une vraie requête
> et exige un code (ici `200` sur `/sante`), ce qui permet aussi à
> l'application de **demander** à sortir du pool (`503` en maintenance, E29.2).
>
> Le revers : un contrôle trop ambitieux peut retirer tous les serveurs d'un
> coup pour une dépendance commune défaillante (QO29.4).

---

<a id="q29-7"></a>**[Q29.7](README.md#q29-7)** — *`bind` sur l'IP virtuelle refusé sur le nœud de secours.*

**Réponse : a)** `net.ipv4.ip_nonlocal_bind = 1`, ou écouter sur `*:80`.

> [!NOTE]
> **Pourquoi**
>
> Le noyau refuse par défaut de lier un socket à une adresse qui n'est pas
> présente sur la machine (`EADDRNOTAVAIL`). Sur le nœud de secours, l'IP
> virtuelle n'existe pas encore. Deux solutions propres :
>
> * `sysctl net.ipv4.ip_nonlocal_bind=1` (persistant dans
>   `/etc/sysctl.d/`) : HAProxy démarre, et il recevra le trafic dès que
>   keepalived posera l'adresse ;
> * `bind :80` (toutes les adresses), comme en L29.1 : plus simple, mais
>   HAProxy répond aussi sur l'adresse propre du nœud, ce qui est souvent
>   utile (contrôle direct d'un nœud).
>
> Démarrer HAProxy seulement sur le maître ajouterait un démarrage à froid au
> temps de bascule et une dépendance fragile au script de notification.

---

<a id="q29-8"></a>**[Q29.8](README.md#q29-8)** — *`systemctl reload haproxy`.*

**Réponse : c)** nouveaux workers, les anciens finissent leurs connexions.

> [!NOTE]
> **Pourquoi**
>
> Sur Ubuntu 24.04 (HAProxy 2.8), le service tourne en mode **maître-worker**
> (`-Ws`). Le `reload` valide d'abord la configuration (`haproxy -c`), puis
> envoie `SIGUSR2` au maître, qui relit la configuration et lance de nouveaux
> workers. Les anciens cessent d'accepter des connexions et se terminent
> quand leurs connexions en cours sont finies (`hard-stop-after` borne cette
> attente). Aucun client ne voit de coupure.
>
> Si la configuration est invalide, le `reload` échoue **sans** toucher au
> service en cours : c'est pourquoi on recharge toujours, et on ne redémarre
> jamais, un répartiteur en production.

---

<a id="q29-9"></a>**[Q29.9](README.md#q29-9)** — *Cluster Corosync de deux nœuds sans arbitre.*

**Réponse : d)** chacun a 1 vote sur 2 et perd le quorum.

> [!NOTE]
> **Pourquoi**
>
> Le quorum exige **strictement plus** de la moitié des votes : 2 sur 2 dans
> un cluster de deux nœuds. Après la coupure, chaque nœud n'en voit qu'un : les
> deux sont sans quorum et, avec la politique par défaut
> (`no-quorum-policy=stop`), arrêtent leurs ressources. Le cluster est
> « sûr », mais une panne d'un seul nœud arrête tout, ce qui contredit son but.
>
> C'est pourquoi `pcs cluster setup` avec deux nœuds active `two_node: 1` dans
> `corosync.conf` : chaque nœud garde le quorum seul (et `wait_for_all`
> l'oblige à avoir vu l'autre au moins une fois au démarrage). Le prix : en cas
> de coupure réseau, les **deux** se croient survivants, et seul le fencing
> départage, par une course où chacun tente d'éteindre l'autre. Le qdevice de
> L29.3 remplace cette course par un arbitrage : 3 votes, une seule partition
> majoritaire.

---

<a id="q29-10"></a>**[Q29.10](README.md#q29-10)** — *Rôle du fencing.*

**Réponse : a)** garantir que le nœud perdu ne fait plus rien.

> [!NOTE]
> **Pourquoi**
>
> Quand un nœud ne répond plus, ses pairs ne savent pas s'il est mort, figé
> (et susceptible de se réveiller), ou seulement injoignable alors qu'il
> continue d'écrire sur un stockage partagé ou de servir une IP. Le fencing
> transforme cette incertitude en certitude : on **éteint** ou isole le nœud
> par un canal indépendant (API de l'hyperviseur, carte IPMI, prise
> électrique pilotée, accès au stockage coupé), et l'on n'agit qu'une fois
> l'opération confirmée.
>
> « Shoot The Other Node In The Head » résume l'esprit : mieux vaut un nœud
> sain éteint par erreur que deux nœuds qui écrivent les mêmes données.

---

<a id="q29-11"></a>**[Q29.11](README.md#q29-11)** — *Contraintes implicites d'un groupe.*

**Réponse : a), b) et c).**

> [!NOTE]
> **Pourquoi**
>
> Un groupe est un raccourci pour une chaîne de contraintes `order` et
> `colocation` entre ses membres, dans l'ordre de déclaration :
>
> * démarrage dans l'ordre (IP, puis service), arrêt dans l'ordre inverse
>   (service, puis IP) ;
> * tous sur le même nœud ; si un membre ne peut pas tourner quelque part, les
>   suivants non plus.
>
> Le groupe ne dit rien du **nœud** choisi : c'est le rôle des contraintes de
> `location` et de l'adhérence (d est faux). Si deux ressources doivent être
> ensemble sans ordre de démarrage, on écrit une contrainte `colocation`
> seule.

---

<a id="q29-12"></a>**[Q29.12](README.md#q29-12)** — *Adhérence 100 contre préférence 50.*

**Réponse : b)** il reste sur `lab-ha2`.

> [!NOTE]
> **Pourquoi**
>
> Pacemaker calcule, pour chaque nœud, la somme des scores applicables à la
> ressource et choisit le plus élevé. Sur `lab-ha2`, où elle tourne :
> adhérence 100. Sur `lab-ha1` : préférence 50. 100 > 50, elle reste.
>
> C'est le comportement voulu en L29.4 : un retour automatique coûte une
> seconde interruption, au moment où l'on ne sait pas encore si `lab-ha1` est
> vraiment sain. On ramène la ressource **quand on l'a décidé**, par un
> `pcs resource move` suivi d'un `pcs resource clear`. Avec une préférence de
> 200, elle reviendrait au contraire dès le retour de `lab-ha1`.

---

<a id="q29-13"></a>**[Q29.13](README.md#q29-13)** — *Effacer un échec passé.*

**Réponse : c)** `pcs resource cleanup batch`.

> [!NOTE]
> **Pourquoi**
>
> Pacemaker garde un **compteur d'échecs** par ressource et par nœud
> (`crm_mon -1f` ou `pcs resource failcount show`). Au-delà de
> `migration-threshold` (défaut : `INFINITY`, donc pas de limite pratique),
> la ressource est bannie du nœud. Le compteur et l'historique servent au
> diagnostic : on les efface **après** avoir compris l'échec, avec
> `cleanup`, qui relance aussi une vérification de l'état réel
> (`probe`).
>
> `failure-timeout` permet d'oublier automatiquement un échec ancien ; un
> redémarrage du nœud ne l'efface pas forcément, l'historique étant dans le
> CIB répliqué.

---

<a id="q29-14"></a>**[Q29.14](README.md#q29-14)** — *Fencing en échec.*

**Réponse : a)** il ne démarre pas les ressources ailleurs.

> [!NOTE]
> **Pourquoi**
>
> Pour Pacemaker, un nœud perdu est `UNCLEAN` tant que son fencing n'a pas
> **réussi**. Ses ressources sont considérées comme possiblement encore
> actives : les démarrer ailleurs, c'est risquer deux instances. Pacemaker
> réessaie le fencing et attend. Le service est arrêté, ce qui est le
> **moindre mal** : une indisponibilité se rattrape, une double facturation
> ou une base corrompue beaucoup moins.
>
> C'est BF29.3. La seule sortie manuelle est `pcs stonith confirm <nœud>`,
> qui affirme à Pacemaker « je garantis que ce nœud est éteint » : à n'utiliser
> qu'après l'avoir constaté par un autre moyen.

---

<a id="q29-15"></a>**[Q29.15](README.md#q29-15)** — *Algorithme de qnetd.*

**Réponse : c)** `ffsplit`.

> [!NOTE]
> **Pourquoi**
>
> `ffsplit` (*fifty-fifty split*) est fait pour les clusters à nombre pair de
> nœuds : en cas de partition en deux moitiés égales, qnetd donne son vote à
> une seule, choisie selon des critères ordonnés (la partition qui a le plus
> de nœuds actifs, puis le départage `tie_breaker`, par défaut le plus petit
> identifiant de nœud). `lms` (*last man standing*) donne le vote à la
> dernière partition survivante, même réduite à un nœud.
>
> `two_node` et `wait_for_all` sont des options de votequorum (Q29.9), pas des
> algorithmes de qnetd.

---

<a id="q29-16"></a>**[Q29.16](README.md#q29-16)** — *keepalived ou Pacemaker.*

**Réponse : c).**

> [!NOTE]
> **Pourquoi**
>
> keepalived porte une IP et suit la santé d'un service par un script, avec un
> protocole simple et une bascule en quelques secondes. Il n'a ni quorum ni
> fencing : si les deux nœuds ne s'entendent plus (BF29.1), **les deux**
> prennent l'IP. Pour des répartiteurs sans état, c'est acceptable (le pire
> est quelques secondes de réponses perdues) et la simplicité est un atout.
>
> Pacemaker est fait pour ce qui ne doit **jamais** tourner deux fois (un
> service par lots, une base sur stockage partagé, un montage) : il compte les
> votes, éteint ce qu'il ne contrôle plus, et sait enchaîner plusieurs
> ressources. Il gère très bien une IP virtuelle (`IPaddr2`), mais au prix
> d'une complexité qui ne se justifie que si l'exclusivité compte.

---

## 29.4 Quiz — questions ouvertes

<a id="qo29-1"></a>**[QO29.1](README.md#qo29-1)** — *De l'extinction de `lab-ha1` à la première réponse via `lab-vip`.*

**Réponse attendue**

1. **t = 0** : `lab-ha1` s'éteint. Les connexions TCP établies vers lui
   sont perdues (pas de RST : le client attend).
2. **Détection** : `lab-ha2` n'entend plus d'annonce VRRP. Il considère le
   maître mort après le *master down interval* : 3 × `advert_int` + un
   décalage dépendant de la priorité, soit un peu plus de 3 s avec
   `advert_int 1`.
3. **Prise de l'IP** : `lab-ha2` passe maître, ajoute `10.10.10.20` à
   `ens18`, envoie la rafale d'ARP gratuits. HAProxy écoute déjà
   (`bind :80`) : rien à démarrer.
4. **Réseau** : le cache ARP de `lab-adm` est corrigé par l'ARP gratuit ;
   les nouvelles connexions arrivent sur `lab-ha2`.
5. **Client** : une requête en cours au moment de la panne attend son
   propre délai (ici le `--max-time` de la sonde) ; les nouvelles passent.
   Mesure typique en L29.2 : 3 à 4 secondes.

Le temps passe surtout dans la **détection**. Pour la réduire :
`advert_int` plus court (keepalived accepte des fractions de seconde en
VRRPv3), ce qui coûte plus de trafic et surtout un risque de **fausses
bascules** sur une machine chargée ou un réseau congestionné, chaque bascule
inutile coupant elle-même des connexions. Côté client, des délais de
connexion courts et une relance automatique rendent la bascule invisible.

---

<a id="qo29-2"></a>**[QO29.2](README.md#qo29-2)** — *Split-brain.*

**Réponse attendue**

Un split-brain est la situation où deux parties d'un système redondant
cessent de communiquer et se croient **chacune** seule responsable : elles
font alors tourner simultanément ce qui ne doit tourner qu'une fois.

Exemples de dégâts :

* deux instances du traitement par lots facturent deux fois les mêmes
  clients ;
* deux nœuds montent le même système de fichiers non partagé (ext4, XFS)
  depuis un disque commun : corruption en quelques secondes ;
* deux bases promues primaires acceptent chacune des écritures : les données
  divergent, la réconciliation est manuelle et parfois impossible ;
* deux nœuds portent la même IP (BF29.1) : connexions coupées au hasard.

Les deux mécanismes de Pacemaker :

1. le **quorum** : seule une partition majoritaire (avec qdevice, une seule
   des deux) a le droit de faire tourner des ressources ; la minorité les
   arrête (`no-quorum-policy=stop`) ;
2. le **fencing** : avant de reprendre les ressources d'un nœud perdu, la
   majorité l'éteint et attend la confirmation. Même un nœud figé qui se
   réveillerait sans savoir qu'il a perdu le quorum ne peut plus nuire.

Le quorum seul ne suffit pas (un nœud figé ne sait pas qu'il a perdu le
quorum avant de reprendre ses écritures), le fencing seul non plus (course
mutuelle à deux nœuds) : on combine les deux.

---

<a id="qo29-3"></a>**[QO29.3](README.md#qo29-3)** — *keepalived, HAProxy + keepalived, Pacemaker.*

**Réponse attendue**

| Dispositif | Bon choix | Erreur |
|---|---|---|
| keepalived seul | IP virtuelle devant deux serveurs DNS ou deux passerelles identiques, sans état | protéger une base primaire : deux maîtres possibles, aucune garantie d'exclusivité |
| HAProxy + keepalived | frontal web devant N serveurs d'application sans état : répartition, contrôles L7, bascule de l'IP du frontal | répartir des écritures vers deux bases « primaires » ; ou un seul serveur derrière (on a ajouté deux points de panne pour rien) |
| Pacemaker | service unique avec état : traitement par lots, stockage partagé, service historique qui ne sait pas tourner à plusieurs | répartiteurs sans état (lourdeur inutile) ; cluster à deux nœuds sans fencing ni arbitre |

Le critère de choix est **l'état** et l'**exclusivité** : sans état, on
multiplie les instances et on répartit ; avec un état qui ne se partage pas,
il faut un arbitre qui garantit l'unicité.

---

<a id="qo29-4"></a>**[QO29.4](README.md#qo29-4)** — *Contrôle de santé superficiel ou profond.*

**Réponse attendue**

* **Superficiel** : le processus répond, ses ressources locales sont saines
  (threads disponibles, disque non plein). Il dit « envoie-moi du trafic, je
  peux le traiter ».
* **Profond** : il interroge aussi la base, le cache, une API partenaire.

Le contrôle profond paraît plus juste, mais il crée une **panne en
cascade** : si la base ralentit, **tous** les serveurs échouent leur
contrôle en même temps, HAProxy les retire **tous**, et le site renvoie
`503` partout, alors que la moitié des pages (statiques, en cache) auraient
pu être servies. Pire, quand la base revient, tous les serveurs reviennent
en même temps et l'afflux la refait tomber.

Règle : le contrôle de santé du répartiteur ne teste que ce qui distingue
**ce** serveur des autres (son processus, ses ressources locales). Les
dépendances communes se surveillent par la **supervision** (module 26) et se
gèrent dans l'application (délais, disjoncteur, mode dégradé). Le `/sante`
doit aussi être rapide et peu coûteux (il est appelé toutes les 2 secondes
par chaque répartiteur), et permettre une mise en maintenance volontaire
(`503`), comme celui de `lab29-app`.

---

<a id="qo29-5"></a>**[QO29.5](README.md#qo29-5)** — *« Deux serveurs, un cluster Pacemaker à deux nœuds. »*

**Réponse attendue**

* Deux nœuds ne peuvent pas distinguer « l'autre est mort » de « je ne le
  vois plus ». Il faut un **troisième vote** : un qdevice sur une troisième
  machine (une petite VM ailleurs suffit), ou un troisième nœud.
* Sans **fencing** fonctionnel et testé, le cluster est plus dangereux
  qu'un serveur seul : il peut produire deux instances. Quel canal de
  fencing ? IPMI, API de l'hyperviseur, prise pilotée, avec des droits
  limités.
* Quelles **ressources** et sont-elles avec état ? Si c'est du web sans
  état, HAProxy + keepalived suffisent. Si c'est une base PostgreSQL, un
  outil dédié (Patroni) fait mieux que Pacemaker générique.
* Les deux serveurs sont-ils **indépendants** (alimentation, hyperviseur,
  réseau, baie) ? Sinon, la redondance est théorique.
* Qui teste les bascules, et quand ? (QO29.8)

---

<a id="qo29-6"></a>**[QO29.6](README.md#qo29-6)** — *Factura en haute disponibilité.*

**Réponse attendue**

| Couche | État | Mécanisme |
|---|---|---|
| Entrée (nginx en reverse proxy, TLS) | sans état | 2 instances, HAProxy ou nginx devant, IP virtuelle keepalived ; certificats identiques déployés par Ansible |
| API Python | sans état si les sessions ne sont pas locales | N instances derrière le répartiteur, contrôle `/sante` superficiel |
| Worker (file Redis) | sans état, mais tâches à traiter une seule fois | N workers : la file garantit qu'une tâche n'est prise qu'une fois ; tâches idempotentes |
| Exports PDF | état sur disque | stockage partagé (NFS en HA, ou objet type S3) au lieu de `/srv/factura/exports` local |
| PostgreSQL | **avec état** | primaire + secondaire en réplication en continu, promotion par Patroni (etcd à 3 nœuds), point d'entrée par HAProxy qui interroge Patroni |
| Redis | avec état (file) | Redis Sentinel (3 sentinelles) ou réplication + bascule ; ou accepter de perdre la file et la reconstruire depuis la base |
| Planificateur par lots | doit être **unique** | Pacemaker (L29.4), ou verrou distribué en base |

Et deux remarques d'expert : les instances doivent être sur des hyperviseurs
différents (sinon la panne d'un nœud Proxmox emporte tout), et la haute
disponibilité ne remplace pas les sauvegardes : une suppression de table est
répliquée instantanément sur le secondaire (module 30).

---

<a id="qo29-7"></a>**[QO29.7](README.md#qo29-7)** — *Maintenance sans couper de requête.*

**Réponse attendue**

Derrière HAProxy :

1. passer le serveur en **`drain`** (socket d'administration ou
   `/sante` en `503` côté application) : plus de nouvelles connexions, les
   sessions en cours continuent ;
2. attendre que ses connexions actives tombent à zéro (`show stat`, colonne
   `scur`) ;
3. passer en `maint`, intervenir, redémarrer ;
4. revenir en `ready` et vérifier qu'il repasse `UP`.

Sur les **deux** répartiteurs, puisque chacun a son état.

Pour un nœud Pacemaker : `pcs node standby lab-ha1` déplace proprement les
ressources (arrêt ordonné, démarrage ailleurs : une interruption courte pour
un service unique, inévitable), on intervient, puis `pcs node unstandby`.
Pour une intervention sur le cluster lui-même (mise à jour de Pacemaker),
`pcs property set maintenance-mode=true` fige le cluster : il ne surveille
plus et ne déplace plus rien, les ressources restent en place.

---

<a id="qo29-8"></a>**[QO29.8](README.md#qo29-8)** — *Le dispositif non testé.*

**Réponse attendue**

Un dispositif de haute disponibilité ajoute des composants (répartiteur,
démons de cluster, configuration à synchroniser) qui peuvent tomber en
panne eux-mêmes et ont leurs propres modes de défaillance (split-brain,
bascules intempestives, fencing d'un nœud sain). S'il n'est jamais testé :

* la bascule échoue le jour J (fencing dont le mot de passe a expiré,
  configuration divergente, secours qui n'a jamais tenu la charge) ;
* l'équipe ne sait pas lire l'état du cluster pendant l'incident ;
* on a payé la complexité sans le bénéfice, avec une fausse confiance.

Programme :

* à chaque modification : test de bascule en préproduction ;
* chaque mois : bascule réelle planifiée de chaque dispositif (arrêt du
  maître), mesurée par une sonde ;
* chaque trimestre : panne brutale (extinction par l'hyperviseur) et
  coupure réseau entre nœuds, fencing vérifié ;
* en continu : supervision de l'état (IP virtuelle portée par un seul nœud,
  serveurs UP, cluster sans échec, fencing disponible) ;
* après chaque test : compte rendu et mise à jour du runbook. Le défi D29
  automatise ce programme.

---

## 29.5 Exercices guidés

<a id="e29-1"></a>**[E29.1](README.md#e29-1)** — *`lab29-app` sur les deux serveurs.*

```bash
# lab-web, lab-ops
systemctl status lab29-app --no-pager | head -3
# lab-adm
for h in lab-web lab-ops; do
  for p in / /sante '/lent?s=2'; do
    curl -s -o /dev/null -w "$h $p : %{http_code} en %{time_total}s\n" "http://$h:8029$p"
  done
done
```

> [!NOTE]
> **Pourquoi**
>
> `-w` (*write-out*) affiche des variables de la requête : code HTTP, temps
> total, mais aussi `%{time_connect}` et `%{time_starttransfer}`, qui
> séparent le temps réseau du temps de traitement. Ce sont les deux nombres à
> regarder dans un diagnostic de lenteur derrière un répartiteur.

---

<a id="e29-2"></a>**[E29.2](README.md#e29-2)** — *Maintenance applicative.*

```bash
# lab-ops
sudo install -d -m 755 /run/lab29 && sudo touch /run/lab29/maintenance
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8029/sante   # 503
sudo rm /run/lab29/maintenance
```

> [!NOTE]
> **Pourquoi**
>
> `/run` est un `tmpfs` : la maintenance disparaît au redémarrage, ce qui est
> le bon comportement (une machine qui redémarre revient dans le pool après
> ses contrôles). Une application qui sait dire « ne m'envoie plus rien » est
> le moyen le plus propre de la sortir d'un répartiteur, parce qu'il ne
> dépend pas de l'outil de répartition.

---

<a id="e29-3"></a>**[E29.3](README.md#e29-3)** — *État des serveurs par le socket.*

```bash
echo "show servers state app" | sudo socat stdio /run/haproxy/admin.sock
echo "show stat" | sudo socat stdio /run/haproxy/admin.sock |
  awk -F, 'NR==1 || $1=="app" {print $2, $18, $37, $38}' | column -t
```

```console
# pxname svname status check_status
FRONTEND ...
app1     UP     L7OK
app2     UP     L7OK
BACKEND  UP
```

> [!NOTE]
> **Pourquoi**
>
> `show stat` renvoie un CSV dont la première ligne nomme les colonnes
> (`svname`, `status`, `check_status`, `scur`…) ; mieux vaut en extraire les
> colonnes par leur nom que par leur numéro, qui change selon les versions.
> `L7OK` : contrôle HTTP réussi ; `L7STS` : mauvais code HTTP ; `L4CON` :
> connexion refusée ; `L4TOUT` : délai dépassé. C'est le premier indice d'un
> diagnostic.

---

<a id="e29-4"></a>**[E29.4](README.md#e29-4)** — *`drain`, puis `ready`.*

```bash
echo "set server app/app2 state drain" | sudo socat stdio /run/haproxy/admin.sock
for i in $(seq 6); do curl -sI http://localhost/ | grep -i x-backend; done  # app1 seulement
echo "set server app/app2 state ready" | sudo socat stdio /run/haproxy/admin.sock
```

> [!NOTE]
> **Pourquoi**
>
> * `drain` : plus de nouvelles connexions **réparties**, mais les sessions
>   persistantes existantes continuent, et les contrôles de santé
>   continuent : on sait si le serveur est sain avant de le remettre.
> * `maint` : le serveur est sorti de tout, contrôles compris ; les
>   connexions en cours sont maintenues, mais rien de nouveau n'y arrive, même
>   les sessions persistantes.
>
> Le changement par le socket est **volatil** : un `reload` revient à la
> configuration. Pour une maintenance longue, on modifie aussi la
> configuration (`disabled`) ou on agit côté application (E29.2).

---

<a id="e29-5"></a>**[E29.5](README.md#e29-5)** — *Qui porte l'IP virtuelle ?*

```bash
ip -br addr show ens18
#   ens18  UP  10.10.10.21/24 10.10.10.20/24 …     (sur le maître)
journalctl -u keepalived --since today | grep -E 'Entering (MASTER|BACKUP|FAULT)' | tail -3
cat /var/log/keepalived-transitions.log
```

> [!NOTE]
> **Pourquoi**
>
> `ip addr` est la seule vérité : un `ifconfig` ancien n'affiche pas les
> adresses secondaires sans libellé (d'où le `label ens18:vip` de L29.2, qui
> les rend aussi visibles dans les outils anciens). Le journal donne
> l'historique et la **raison** d'une transition (script en échec, annonce
> de priorité supérieure, plus d'annonce du maître).

---

<a id="e29-6"></a>**[E29.6](README.md#e29-6)** — *Cache ARP de `lab-adm` avant et après une bascule.*

```bash
# lab-adm
curl -s http://lab-vip/ >/dev/null; ip neigh show 10.10.10.20
#   10.10.10.20 dev ens18 lladdr bc:24:11:aa:00:21 REACHABLE
# lab-ha1 : sudo systemctl stop haproxy   (bascule)
ip neigh show 10.10.10.20
#   10.10.10.20 dev ens18 lladdr bc:24:11:aa:00:22 STALE
ip neigh show 10.10.10.22 # même MAC : celle de lab-ha2
```

> [!NOTE]
> **Pourquoi**
>
> Le changement de MAC sans attendre l'expiration du cache est l'effet de
> l'ARP gratuit (Q29.3). Si une machine du segment gardait l'ancienne MAC
> (équipement qui ignore les ARP gratuits), elle continuerait d'envoyer vers
> `lab-ha1` : c'est la cause d'une bascule « qui marche pour certains clients
> et pas pour d'autres ».

---

<a id="e29-7"></a>**[E29.7](README.md#e29-7)** — *Annonces VRRP capturées.*

```bash
sudo timeout 5 tcpdump -ni ens18 -v 'ip proto 112'
```

```console
10.10.10.21 > 10.10.10.22: vrrp 10.10.10.21 > 10.10.10.22: VRRPv2, Advertisement,
  vrid 29, prio 150, authtype none, intvl 1s, length 20, addrs: 10.10.10.20
```

> [!NOTE]
> **Pourquoi**
>
> En unicast, les annonces vont de l'adresse de `lab-ha1` à celle de
> `lab-ha2` ; en multicast, on verrait `224.0.0.18`. La priorité **annoncée**
> est la priorité effective : si le script de suivi échoue, on la voit
> passer à 90. `tcpdump` capture **avant** netfilter : il voit aussi les
> annonces que le pare-feu jettera ensuite, ce qui est la clé de BF29.1.

---

<a id="e29-8"></a>**[E29.8](README.md#e29-8)** — *État du quorum.*

```bash
sudo corosync-quorumtool -s
sudo pcs quorum status
```

```console
Quorum information
------------------
Nodes:            2
Quorate:          Yes
Votequorum information
----------------------
Expected votes:   3
Highest expected: 3
Total votes:      3
Quorum:           2
Flags:            Quorate Qdevice
Membership information
    Nodeid      Votes    Qdevice Name
         1          1    A,V,NMW lab-ha1 (local)
         2          1    A,V,NMW lab-ha2
         0          1            Qdevice
```

On peut perdre **une** machine sur les trois (un nœud ou l'arbitre) sans
perdre le quorum.

> [!NOTE]
> **Pourquoi**
>
> `A,V,NMW` : le qdevice est *alive*, il *vote* pour ce nœud, et *not master
> wins* (le mode `master_wins` n'est pas utilisé). Si l'arbitre tombe, le
> cluster continue avec 2 votes sur 3 ; si un nœud tombe ensuite, le survivant
> n'a plus qu'1 vote sur 3 et s'arrête. L'arbitre doit donc être supervisé
> comme un composant à part entière.

---

<a id="e29-9"></a>**[E29.9](README.md#e29-9)** — *Propriétés du cluster.*

```bash
sudo pcs property config                   # valeurs non par défaut
sudo pcs property config --all | grep -E 'stonith-enabled|no-quorum-policy'
sudo pcs resource defaults
```

> [!NOTE]
> **Pourquoi**
>
> `stonith-enabled` doit valoir `true` (c'est le défaut) ; s'il apparaît dans
> les valeurs non par défaut à `false`, c'est un signal d'alarme.
> `resource-stickiness` est un défaut **des ressources**, pas une propriété du
> cluster : il se lit avec `pcs resource defaults`. Sur des versions plus
> anciennes de `pcs`, la commande est `pcs property list`.

---

<a id="e29-10"></a>**[E29.10](README.md#e29-10)** — *Contraintes, dont celles d'un `move`.*

```bash
sudo pcs constraint --full
#   Location Constraints:
#     Resource: grp-batch
#       Enabled on: lab-ha1 (score:50) (id:location-grp-batch-lab-ha1-50)
#       Enabled on: lab-ha2 (score:INFINITY) (role:Started) (id:cli-prefer-grp-batch)
sudo pcs resource clear grp-batch           # supprime cli-prefer-grp-batch
# ou : sudo pcs constraint delete cli-prefer-grp-batch
```

> [!NOTE]
> **Pourquoi**
>
> `pcs resource move` crée une contrainte `cli-prefer-…` de score
> `INFINITY` : tant qu'elle existe, la ressource ne peut **jamais** quitter le
> nœud, même si celui-ci tombe. Les versions récentes de `pcs` la retirent
> d'elles-mêmes après le déplacement (option `--autodelete` ou comportement par
> défaut selon la version), mais la vérification reste le réflexe : une
> contrainte oubliée est la cause classique d'un service qui « ne bascule
> plus ».

---

<a id="e29-11"></a>**[E29.11](README.md#e29-11)** — *Standby.*

```bash
sudo pcs node standby lab-ha1
sudo crm_mon -1        # grp-batch : Started lab-ha2
sudo pcs node unstandby lab-ha1
sudo crm_mon -1        # grp-batch reste sur lab-ha2
```

> [!NOTE]
> **Pourquoi**
>
> Le groupe reste sur `lab-ha2` pour la raison de Q29.12 : l'adhérence (100)
> dépasse la préférence pour `lab-ha1` (50). Un nœud qui sort de standby
> redevient **candidat** ; il ne récupère rien tant que les scores ne
> l'imposent pas. C'est ce qui rend le standby sûr pour une maintenance : on
> choisit le moment du retour.

---

<a id="e29-12"></a>**[E29.12](README.md#e29-12)** — *Interruption d'un déplacement Pacemaker.*

```bash
# lab-adm
~/lab29/sonde.sh http://lab-batch:9029/ &
# lab-ha1
sudo pcs resource move grp-batch lab-ha2 && sleep 15 && sudo pcs resource clear grp-batch
# lab-adm
fg   # Ctrl-C : la sonde affiche son bilan
#   interruptions : 1, durée totale 1,4 s, plus longue 1,4 s
```

> [!NOTE]
> **Pourquoi**
>
> Un déplacement est un **arrêt** ordonné sur un nœud (service, puis IP) suivi
> d'un **démarrage** sur l'autre (IP, puis service) : son coût est la somme des
> temps d'arrêt et de démarrage du service, plus quelques centaines de
> millisecondes de décision. Pour un service qui met 30 s à démarrer, chaque
> déplacement coûte 30 s, d'où l'adhérence. La bascule keepalived de L29.2,
> elle, ne démarre rien (HAProxy tourne déjà sur les deux nœuds) : seule la
> détection compte.

---

## 29.6 Labs

### <a id="l29-1"></a>**[L29.1](README.md#l29-1)** — Un répartiteur devant deux serveurs d'application

*Configuration HAProxy identique sur les deux nœuds, contrôles L7, en-tête
de diagnostic, statistiques réservées à `lab-adm`.*

**Étape 1 à 3 — La configuration**

```bash
sudo apt install -y haproxy
sudo cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.orig
```

On garde les sections `global` et `defaults` livrées par Ubuntu (journal
vers `/dev/log`, socket d'administration, utilisateur `haproxy`, chroot) et
on ajoute à la fin de `/etc/haproxy/haproxy.cfg` :

```text
frontend web
    bind :80
    option forwardfor
    default_backend app

backend app
    balance roundrobin
    option httpchk
    http-check send meth GET uri /sante
    http-check expect status 200
    default-server inter 2s fall 3 rise 2
    http-response set-header X-Backend %[srv_name]
    server app1 10.10.10.11:8029 check
    server app2 10.10.10.14:8029 check

listen stats
    bind :8404
    acl depuis_adm src 10.10.10.10
    http-request deny unless depuis_adm
    stats enable
    stats uri /
    stats refresh 5s
```

> [!NOTE]
> **Pourquoi**
>
> * `default-server` factorise les paramètres de contrôle : un troisième
>   serveur hérite des mêmes règles sans risque d'oubli.
> * `%[srv_name]` est un *sample fetch* évalué à chaque réponse : le nom du
>   serveur qui a répondu. C'est un outil de diagnostic précieux en
>   production ; on le restreint souvent aux réseaux internes pour ne pas
>   exposer la topologie.
> * `option forwardfor` ajoute `X-Forwarded-For` : sans lui, les journaux
>   des serveurs ne montrent que l'adresse du répartiteur. L'application ne
>   doit faire confiance à cet en-tête **que** s'il vient d'un répartiteur
>   connu.
> * Les `timeout` des `defaults` d'Ubuntu (`client` et `server` à 50 s)
>   conviennent à `/lent?s=8` ; BF29.2 montre ce qui se passe quand l'un d'eux
>   diverge.

**Étape 4 — Valider, recharger, observer**

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg     # Configuration file is valid
sudo systemctl reload haproxy
# lab-adm
for i in $(seq 6); do curl -s -D - -o /dev/null http://lab-ha1/ | grep -i x-backend; done
#   X-Backend: app1
#   X-Backend: app2
#   …
```

**Étape 5 — Retrait d'un serveur défaillant**

```bash
# lab-adm : sonde sur le nœud directement
~/lab29/sonde.sh http://lab-ha1/ &
# lab-ops
sudo systemctl stop lab29-app
# lab-ha1
sudo journalctl -u haproxy -f | grep app2
#   Server app/app2 is DOWN, reason: Layer4 connection problem, … 2 active and 0 backup servers left
```

Le serveur est retiré après **3 contrôles en échec**, soit environ 4 à
6 secondes (le premier échec peut survenir jusqu'à 2 s après la panne). Les
requêtes perdues pendant ce délai sont peu nombreuses : HAProxy **réessaie**
une connexion refusée sur un autre serveur (`option redispatch` et
`retries` des `defaults` d'Ubuntu). Un serveur qui accepte la connexion mais
répond mal, lui, renvoie ses erreurs au client jusqu'au retrait.

```bash
sudo systemctl start lab29-app      # lab-ops : réintégré après 2 succès
```

**Étape 6 — Identité des deux configurations**

```bash
# lab-ha1
scp /etc/haproxy/haproxy.cfg lab-ha2.lab.local:/tmp/
ssh lab-ha2.lab.local 'sudo install -m 644 /tmp/haproxy.cfg /etc/haproxy/ &&
  sudo haproxy -c -f /etc/haproxy/haproxy.cfg && sudo systemctl reload haproxy'
sha256sum /etc/haproxy/haproxy.cfg; ssh lab-ha2.lab.local sha256sum /etc/haproxy/haproxy.cfg
```

> [!WARNING]
> **Piège**
>
> La copie à la main est acceptable pour un lab ; en production, la
> configuration des deux nœuds vient d'**une** source (dépôt Git + Ansible,
> module 23), déployée par la même tâche. Deux fichiers maintenus séparément
> divergent toujours, et la divergence ne se voit qu'au moment de la bascule
> (BF29.2).

---

### <a id="l29-2"></a>**[L29.2](README.md#l29-2)** — Une IP virtuelle qui bascule

*keepalived en unicast, suivi de HAProxy, journal des transitions, et
trois mesures de bascule.*

**Étapes 1 à 3 — Configuration**

`/etc/keepalived/keepalived.conf` sur `lab-ha1` :

```text
global_defs {
    router_id lab-ha1
    enable_script_security
    script_user root
}

vrrp_script chk_haproxy {
    script "/usr/bin/systemctl is-active --quiet haproxy"
    interval 2
    fall 2
    rise 2
    weight -60
}

vrrp_instance VI_29 {
    state BACKUP
    interface ens18
    virtual_router_id 29
    priority 150
    advert_int 1
    unicast_src_ip 10.10.10.21
    unicast_peer {
        10.10.10.22
    }
    virtual_ipaddress {
        10.10.10.20/24 dev ens18 label ens18:vip
    }
    track_script {
        chk_haproxy
    }
    notify /usr/local/sbin/vrrp-notify.sh
}
```

Sur `lab-ha2`, seules changent `router_id lab-ha2`, `priority 100`,
`unicast_src_ip 10.10.10.22` et le pair `10.10.10.21`.

`/usr/local/sbin/vrrp-notify.sh` (sur les deux, `root:root 0755`) :

```bash
#!/usr/bin/env bash
# appelé par keepalived : $1 = GROUP|INSTANCE, $2 = nom, $3 = MASTER|BACKUP|FAULT|STOP
printf '%s %s %s %s\n' "$(date -Is)" "$(hostname -s)" "$2" "$3" \
  >> /var/log/keepalived-transitions.log
```

```bash
sudo systemctl enable --now keepalived
sudo systemctl restart keepalived
ip -br addr show ens18
```

> [!NOTE]
> **Pourquoi**
>
> * **`state BACKUP` sur les deux** : l'état initial n'est qu'une indication ;
>   la priorité décide. Démarrer les deux en `BACKUP` évite qu'un nœud qui
>   redémarre se déclare maître une fraction de seconde avant d'avoir entendu
>   l'autre.
> * **Unicast** : pas de dépendance au multicast, et un nœud n'écoute que ses
>   pairs déclarés (moins de risque de collision de VRID).
> * **Pas d'`authentication`** : l'authentification par mot de passe de VRRPv2
>   circule en clair et a été retirée de la norme (VRRPv3) ; elle ne protège
>   de rien. La protection réelle est le réseau (VLAN dédié, pare-feu entre
>   nœuds).
> * **`enable_script_security`** : keepalived refuse d'exécuter un script
>   modifiable par un autre utilisateur que celui qui l'exécute. Un script de
>   suivi exécuté en root et modifiable par n'importe qui serait une porte
>   dérobée.

**Étape 4 — Pare-feu**

Les VM `lab-ha*` n'ont pas de pare-feu actif par défaut. Avec ufw, la règle
se pose dans `/etc/ufw/before.rules` (ufw ne nomme pas tous les
protocoles), avant le `COMMIT` de la table `*filter` :

```text
-A ufw-before-input -p 112 -s 10.10.10.21 -d 10.10.10.22 -j ACCEPT
```

(adresses inversées sur `lab-ha1`), puis `sudo ufw reload`.

**Étape 5 — Trois pannes, trois mesures**

```bash
# lab-adm
~/lab29/sonde.sh http://lab-vip/ | tee ~/lab29/sonde-l29-2.log
```

| Panne | Commande | Ce qui se passe | Interruption typique |
|---|---|---|---|
| HAProxy arrêté | `sudo systemctl stop haproxy` (`lab-ha1`) | 2 échecs du script (≈ 4 s), priorité 90, `lab-ha2` préempte | 4 à 5 s |
| keepalived arrêté | `sudo systemctl stop keepalived` (`lab-ha1`) | `lab-ha1` envoie une annonce de priorité 0 en partant : `lab-ha2` prend l'IP aussitôt | < 1 s |
| extinction brutale | `qm stop 9021` (nœud Proxmox) | plus d'annonce : détection en ≈ 3 s | 3 à 4 s |

Les mesures, consignées dans `~/lab29/mesures.md`, ont cette forme :

```markdown
| Panne | Interruption | Requêtes perdues |
|---|---|---|
| HAProxy arrêté | 4,6 s | 46 |
| keepalived arrêté | 0,3 s | 3 |
| qm stop 9021 | 3,5 s | 35 |
```

> [!NOTE]
> **Pourquoi**
>
> Les trois pannes ont des durées différentes parce que la **détection**
> diffère : un arrêt propre de keepalived prévient (annonce de priorité 0),
> une machine éteinte se tait, et un service mort n'est vu qu'au rythme du
> script de suivi (`interval × fall`). C'est ce dernier cas qu'on réduit en
> resserrant le script, au prix d'une sensibilité plus grande aux lenteurs
> passagères.

**Étape 6 — Retour de `lab-ha1`**

Avec la configuration ci-dessus, `lab-ha1` (150) reprend l'IP dès son
retour : **deuxième** interruption, au moment où il n'a peut-être pas fini
de démarrer (HAProxy pas encore prêt, mais le script de suivi n'a pas encore
échoué). Deux choix défendables :

* `preempt_delay 60` (avec `state BACKUP`) : il ne reprend l'IP qu'après
  60 s de bonne santé ; la seconde interruption reste, mais à un moment sûr ;
* `nopreempt` sur les deux nœuds : l'IP reste où elle est, on la ramène à la
  main lors d'une fenêtre de maintenance.

Pour des répartiteurs identiques, **`nopreempt`** est le choix le plus
cohérent : aucun nœud n'est « le bon », et chaque bascule coûte quelques
secondes.

---

### <a id="l29-3"></a>**[L29.3](README.md#l29-3)** — Un cluster qui sait se compter et éteindre un nœud

**Étape 1 — Le cluster**

```bash
# lab-ha1 et lab-ha2
sudo apt install -y pacemaker corosync pcs fence-agents corosync-qdevice
ls /usr/sbin/fence_pve          # sinon : apt-cache search fence-agents
sudo passwd hacluster
sudo systemctl enable --now pcsd
sudo pcs cluster destroy        # le paquet Ubuntu pose un cluster « debian » à un nœud

# lab-ha1 seulement
sudo pcs host auth lab-ha1 addr=10.10.10.21 lab-ha2 addr=10.10.10.22 -u hacluster
sudo pcs cluster setup lab29 lab-ha1 addr=10.10.10.21 lab-ha2 addr=10.10.10.22
sudo pcs cluster start --all
sudo pcs cluster enable --all
sudo pcs status
```

> [!WARNING]
> **Piège**
>
> Sur Ubuntu, l'installation de `pacemaker` démarre aussitôt un cluster à un
> nœud avec un `corosync.conf` par défaut. Sans `pcs cluster destroy`,
> `pcs cluster setup` refuse de continuer (« nodes are already in a cluster »)
> ou, pire avec `--force`, on obtient un mélange de configurations. Le
> `destroy` se fait sur **chaque** nœud, avant la création.
>
> Les adresses explicites (`addr=`) rendent le cluster indépendant du DNS : un
> cluster qui ne se forme plus parce que `dnsmasq` est en panne ajoute une
> panne au lieu d'en absorber une.

**Étape 2 — L'arbitre**

```bash
# lab-adm
sudo apt install -y pcs corosync-qnetd
sudo passwd hacluster
sudo systemctl enable --now pcsd
sudo pcs qdevice setup model net --enable --start
# lab-ha1
sudo pcs host auth lab-adm addr=10.10.10.10 -u hacluster
sudo pcs quorum device add model net host=lab-adm algorithm=ffsplit
sudo corosync-quorumtool -s | grep -E 'Expected|Total|Flags'
#   Expected votes:   3
#   Total votes:      3
#   Flags:            Quorate Qdevice
```

`pcs` retire de lui-même `two_node: 1` de `corosync.conf` quand un qdevice
est ajouté : les deux mécanismes sont incompatibles.

**Étape 3 — L'utilisateur de fencing sur Proxmox**

```bash
# shell du nœud Proxmox
pveum role add Fencing --privs "VM.PowerMgmt VM.Audit"
pveum user add fence@pve --comment "fencing du cluster lab29"
pveum passwd fence@pve
pveum acl modify /vms/9021 --users fence@pve --roles Fencing
pveum acl modify /vms/9022 --users fence@pve --roles Fencing
pveum user permissions fence@pve       # vérifier : rien d'autre que ces deux VM
```

> [!NOTE]
> **Pourquoi**
>
> Le principe du moindre privilège appliqué au fencing : cet utilisateur peut
> allumer, éteindre et lire l'état de **deux** VM, rien d'autre. Si le mot de
> passe fuit (il sera stocké dans la configuration du cluster, lisible par
> root sur les nœuds), l'attaquant peut éteindre `lab-ha1` et `lab-ha2`, pas
> le laboratoire entier. Le royaume `pve` (et non `pam`) évite de créer un
> compte système sur le nœud.

**Étape 4 — L'agent à la main**

```bash
# lab-ha1
sudo fence_pve --ip=10.10.10.1 --username=fence@pve --password='…' \
  --plug=9022 --node-name=pve --ssl-insecure --action=status
#   Status: ON
```

> [!NOTE]
> **Pourquoi**
>
> Tester l'agent **seul** sépare deux sources de panne : l'accès à l'API
> (réseau, certificat, droits) et la configuration du cluster. Un `status`
> qui échoue ici échouera aussi dans le cluster, mais avec un message beaucoup
> moins clair. `--ssl-insecure` accepte le certificat autosigné du nœud :
> acceptable sur le réseau isolé du lab ; en production, on installe la CA
> du cluster Proxmox sur les nœuds.

**Étape 5 — La ressource de fencing**

```bash
sudo pcs stonith create fence-pve fence_pve \
  ip=10.10.10.1 username=fence@pve password='…' \
  node_name=pve ssl_insecure=1 \
  pcmk_host_map="lab-ha1:9021;lab-ha2:9022" \
  op monitor interval=60s
sudo pcs property config --all | grep stonith-enabled     # true
sudo pcs stonith status
```

**Étape 6 — Le test**

```bash
sudo pcs stonith fence lab-ha2
#   Node: lab-ha2 fenced
sudo pcs stonith history show lab-ha2
#   reboot of lab-ha2 successful: delegate=lab-ha1, client=stonith_admin…, origin=lab-ha1,
#   completed='…'
# deux minutes plus tard :
sudo pcs status | grep -A2 'Node List'
#   * Online: [ lab-ha1 lab-ha2 ]
```

> [!NOTE]
> **Pourquoi**
>
> Le test fence un nœud **sain**, en plein jour, pendant qu'on le regarde :
> c'est le seul moment où un fencing qui ne marche pas ne coûte rien. On vérifie
> trois choses : l'opération est confirmée, la **bonne** VM a redémarré (sur
> Proxmox : `qm status 9022`, uptime), et le nœud revient dans le cluster seul
> (grâce à `pcs cluster enable`). Ce test se rejoue après chaque changement de
> mot de passe, de version de Proxmox ou de numéro de VM.

---

### <a id="l29-4"></a>**[L29.4](README.md#l29-4)** — Un service unique, et la preuve qu'il le reste

**Étapes 1 à 3 — Ressources et règles**

```bash
sudo pcs resource defaults update resource-stickiness=100
sudo pcs property set no-quorum-policy=stop

sudo pcs resource create vip-batch ocf:heartbeat:IPaddr2 \
  ip=10.10.10.25 cidr_netmask=24 nic=ens18 \
  op monitor interval=10s --group grp-batch
sudo pcs resource create batch systemd:lab29-batch \
  op monitor interval=15s --group grp-batch
sudo pcs constraint location grp-batch prefers lab-ha1=50
sudo pcs status
#   * Resource Group: grp-batch:
#     * vip-batch  (ocf:heartbeat:IPaddr2):  Started lab-ha1
#     * batch      (systemd:lab29-batch):    Started lab-ha1
```

> [!WARNING]
> **Piège**
>
> L'unité `lab29-batch.service` doit rester **désactivée** dans systemd
> (`systemctl is-enabled` → `disabled`) : c'est Pacemaker qui la démarre. Une
> unité activée démarrerait au boot sur **chaque** nœud, hors du contrôle du
> cluster : exactement la double exécution qu'on veut empêcher. Le setup l'a
> posée désactivée ; un `systemctl enable` « pour qu'elle survive au
> redémarrage » est l'erreur classique.

**Étape 4 — Déplacer, puis retirer la contrainte**

```bash
sudo pcs resource move grp-batch lab-ha2
sudo pcs constraint --full | grep cli-       # contrainte cli-prefer-grp-batch
sudo pcs resource clear grp-batch
sudo crm_mon -1 | grep -A2 grp-batch         # toujours sur lab-ha2
```

Le groupe reste sur `lab-ha2` : une fois la contrainte de déplacement
retirée, l'adhérence (100) l'emporte sur la préférence (50) (Q29.12).

**Étape 5 — Le processus tué**

```bash
sudo pkill -9 -f lab29-batch                  # sur le nœud actif
sleep 20; sudo crm_mon -1f
#   Migration Summary:
#     * Node: lab-ha2:
#       * batch: migration-threshold=1000000 fail-count=1 last-failure=…
sudo pcs resource cleanup batch
```

Pacemaker voit l'échec à la surveillance suivante (≤ 15 s), arrête
proprement ce qui reste et **redémarre sur place** : le compteur d'échecs
(1) est très loin du seuil de migration. Pour qu'un service qui plante en
boucle change de nœud, on fixe `migration-threshold=3` sur la ressource.

**Étape 6 — Coupure réseau**

```bash
# sur le nœud PASSIF (ici lab-ha1, groupe sur lab-ha2)
sudo nft add table inet panne
sudo nft add chain inet panne entree '{ type filter hook input priority 0; }'
sudo nft add chain inet panne sortie '{ type filter hook output priority 0; }'
sudo nft add rule inet panne entree udp dport 5405 drop
sudo nft add rule inet panne sortie udp dport 5405 drop
```

Ce qu'on observe :

1. Corosync de chaque côté constate la perte de l'autre (délai `token`,
   1 à 3 s selon la configuration).
2. qnetd, en `ffsplit`, donne son vote à **une** partition : à nombre égal de
   nœuds, le départage par défaut favorise le plus petit identifiant de nœud,
   donc `lab-ha1` (nœud 1). `lab-ha1` + arbitre : 2 votes sur 3, quorum ;
   `lab-ha2` : 1 vote, plus de quorum.
3. `lab-ha2`, sans quorum, **arrête** `grp-batch` (`no-quorum-policy=stop`).
4. `lab-ha1`, majoritaire, **fence** `lab-ha2` par l'API Proxmox, attend la
   confirmation, puis démarre `grp-batch`.
5. `lab-ha2` redémarre ; les règles nftables, non persistantes, ont disparu :
   il rejoint le cluster.

Service interrompu de la coupure à la confirmation du fencing plus le
démarrage : de l'ordre de 10 à 20 secondes, mesuré par la sonde. En
recommençant sur le nœud **actif** (groupe sur `lab-ha1`, blocage sur
`lab-ha1`), c'est le même nœud 1 qui garde le quorum et qui fence `lab-ha2` :
le service ne bouge pas.

> [!NOTE]
> **Pourquoi**
>
> Le point à retenir : la décision ne dépend pas de « qui a le service », mais
> de « qui a le quorum ». Le départage `ffsplit` peut être orienté
> (`tie_breaker` = un identifiant de nœud, ou les **ressources** :
> `pcs quorum device update heuristics …` permet de faire gagner la partition
> qui réussit un test, par exemple joindre la passerelle). Dans tous les cas,
> l'autre partition est éteinte avant que quoi que ce soit ne redémarre :
> jamais deux instances, même un court instant.

---

## 29.7 Break & Fix

### <a id="bf29-1"></a>**[BF29.1](README.md#bf29-1)** — « Le site répond une fois sur deux »

**Démarche de diagnostic**

```bash
# 1. qui porte l'IP ?
ip -br addr show ens18        # sur lab-ha1 ET sur lab-ha2 : les DEUX ont 10.10.10.20
# 2. que dit keepalived ?
journalctl -u keepalived --since -30min | grep -E 'Entering|MASTER'   # lab-ha2 : MASTER
# 3. lab-ha2 reçoit-il les annonces ?
sudo tcpdump -ni ens18 -c 3 'ip proto 112'      # oui : celles de lab-ha1 arrivent…
# 4. … mais keepalived ne les voit pas : le pare-feu
sudo nft list ruleset | less
#   table inet durcissement {
#     chain entree { type filter hook input priority filter - 10; policy accept;
#       ip protocol vrrp drop
# 5. côté clients
ip neigh show 10.10.10.20      # lab-adm : la MAC change au gré des ARP gratuits
```

**Cause racine** : une table nftables `durcissement` sur `lab-ha2` jette
les paquets VRRP entrants. `lab-ha2` n'entend plus `lab-ha1`, le croit mort
et devient maître : **les deux** nœuds portent l'IP virtuelle. Chacun envoie
ses ARP gratuits ; les machines du segment associent l'IP tantôt à une MAC,
tantôt à l'autre. Les connexions établies vers un nœud sont envoyées à
l'autre au changement suivant, qui répond par un RST ou les ignore : d'où
l'intermittence. HAProxy est sain partout, ce qui égare le diagnostic.

**Correctif**

```bash
sudo nft delete table inet durcissement      # lab-ha2
grep -rl durcissement /etc/nftables.conf /etc/nftables.d/ 2>/dev/null   # persistée ?
journalctl -u keepalived -n 3                # « Entering BACKUP STATE »
ip -br addr show ens18                       # plus de 10.10.10.20 sur lab-ha2
```

**Prévention** : une sonde qui vérifie que l'IP virtuelle est portée par
**un et un seul** nœud. Depuis l'un des nœuds,
`arping -D -c 2 -I ens18 10.10.10.20` répond « dupliqué » si une autre
machine annonce la même adresse ; côté supervision, une alerte sur les
transitions keepalived (`keepalived_exporter`, ou le journal des transitions
de L29.2), et les règles de pare-feu des nœuds gérées par la même source de
configuration que keepalived.

> [!NOTE]
> **Pourquoi**
>
> `tcpdump` capture au niveau du pilote, **avant** netfilter : il voit les
> annonces arriver, ce qui fait conclure à tort que « le réseau est bon ».
> La bonne question devient alors « pourquoi keepalived ne les reçoit-il
> pas ? », et la réponse est entre la carte et le socket : le pare-feu (ou un
> filtre `rp_filter`, ou une mauvaise interface dans `keepalived.conf`). Les
> compteurs de la règle (`nft list ruleset` avec `counter`) le prouvent.
>
> C'est la limite structurelle de keepalived évoquée en Q29.16 : sans quorum,
> une simple perte de communication produit deux maîtres. Pour des
> répartiteurs, c'est une dégradation ; pour un service avec état, ce serait
> une catastrophe.

---

### <a id="bf29-2"></a>**[BF29.2](README.md#bf29-2)** — « Les exports tombent en 504, sauf pendant les tests »

**Démarche de diagnostic**

```bash
# 1. reproduire, et voir quel nœud répond
curl -s -o /dev/null -w '%{http_code} %{time_total}\n' http://lab-vip/lent?s=8   # 504 en ~5 s
ip -br addr show ens18            # la VIP est sur lab-ha1 (le nœud « normal »)
# 2. comparer les deux nœuds directement
curl -s -o /dev/null -w '%{http_code}\n' http://lab-ha1/lent?s=8    # 504
curl -s -o /dev/null -w '%{http_code}\n' http://lab-ha2/lent?s=8    # 200
# 3. comparer les configurations
diff <(ssh lab-ha1.lab.local cat /etc/haproxy/haproxy.cfg) \
     <(ssh lab-ha2.lab.local cat /etc/haproxy/haproxy.cfg)
#   <     timeout server 5s
#   ---
#   >     timeout server 50000
# 4. le journal HAProxy le confirme
sudo journalctl -u haproxy | grep ' 504 ' | tail -2   # état de fin « sH » : délai serveur
```

**Cause racine** : la « mise à jour » a modifié le `timeout server` du
seul `lab-ha1` (5 s au lieu de 50 s). Les exports, qui durent 8 s, dépassent
le délai : HAProxy abandonne et renvoie `504`. Pendant le test de bascule du
matin, l'IP était sur `lab-ha2`, dont la configuration est restée correcte :
tout marchait.

**Correctif** : on ne corrige pas « au bon endroit » à la main, on
**réaligne** : la configuration de référence (celle de `lab-ha2`, validée
par le test) est redéployée sur les deux nœuds, puis on vérifie l'empreinte.

```bash
scp lab-ha2.lab.local:/etc/haproxy/haproxy.cfg /tmp/ref.cfg
sudo haproxy -c -f /tmp/ref.cfg && sudo install -m 644 /tmp/ref.cfg /etc/haproxy/haproxy.cfg
sudo systemctl reload haproxy
sha256sum /etc/haproxy/haproxy.cfg; ssh lab-ha2.lab.local sha256sum /etc/haproxy/haproxy.cfg
curl -s -o /dev/null -w '%{http_code}\n' http://lab-vip/lent?s=8      # 200
```

**Prévention** : la configuration des deux nœuds vient d'un dépôt et d'un
déploiement unique (Ansible, `serial: 1` pour recharger un nœud à la fois
avec `haproxy -c` en validation) ; un contrôle périodique compare les
empreintes et alerte en cas d'écart ; chaque test de bascule fait passer la
**même** batterie de requêtes (dont une requête longue) sur les deux nœuds.

> [!NOTE]
> **Pourquoi**
>
> La colonne d'état de fin de session du journal HAProxy (*termination
> state*, deux lettres) est le meilleur outil de ce diagnostic : `sH` = délai
> dépassé côté serveur (*server timeout*, pendant l'attente des en-têtes),
> `cD` = délai client, `SC` = connexion refusée par le serveur. Elle dit qui a
> abandonné et à quel moment, ce qu'aucun code HTTP ne dit.
>
> Le symptôme « marche pendant les tests » est la signature d'une
> **divergence** entre nœuds redondants : on teste toujours un seul nœud à la
> fois. L'interdiction de toucher aux serveurs d'application empêche le
> mauvais correctif (raccourcir l'export pour qu'il tienne en 5 s).

---

### <a id="bf29-3"></a>**[BF29.3](README.md#bf29-3)** — « lab-ha2 est mort, et le service ne repart pas »

**Démarche de diagnostic**

```bash
sudo pcs status --full
#   Node List:
#     * Node lab-ha2: UNCLEAN (offline)
#   * Resource Group: grp-batch:
#     * vip-batch (ocf:heartbeat:IPaddr2): Started lab-ha2 (UNCLEAN)
#   Failed Fencing Actions:
#     * reboot of lab-ha2 failed: delegate=lab-ha1, client=pacemaker-controld…
sudo pcs stonith history show lab-ha2
sudo journalctl -u pacemaker --since -10min | grep -iE 'fence|stonith' | tail -5
#   fence_pve[…]: Failed: Unable to obtain correct plug status or plug is not available
sudo pcs stonith config fence-pve | grep pcmk_host_map
#   pcmk_host_map=lab-ha1:9021;lab-ha2:9220
# état réel de lab-ha2, par un autre canal
sudo fence_pve --ip=10.10.10.1 --username=fence@pve --password='…' \
  --node-name=pve --ssl-insecure --plug=9022 --action=status    # Status: ON
```

**Cause racine** : le fencing échoue parce que la correspondance
nœud → VM est fausse : `lab-ha2` y est associé à la VM `9220`, qui n'existe
pas (faute de frappe). `lab-ha1` ne peut pas confirmer que `lab-ha2` est
éteint, et Pacemaker refuse, à juste titre, de démarrer `grp-batch`. La VM
9022 est d'ailleurs **toujours allumée** (`Status: ON`) : privé de quorum,
`lab-ha2` a sans doute arrêté son service de lui-même, mais rien ne le prouve
à `lab-ha1`, et un nœud figé ne l'aurait pas fait.

**Correctif**

```bash
sudo pcs stonith update fence-pve pcmk_host_map="lab-ha1:9021;lab-ha2:9022"
# Pacemaker retente le fencing de lui-même ; sinon :
sudo pcs stonith fence lab-ha2
sudo pcs status            # lab-ha2 fencé, grp-batch Started lab-ha1
sudo pcs stonith cleanup
```

**Prévention** : test de fencing réel (L29.3, étape 6) **après chaque
modification** de la ressource de fencing ; une alerte sur l'état de la
ressource `fence-pve` (son `monitor` vérifie l'accès à l'API, mais pas la
correspondance de chaque nœud) ; une revue à deux de toute modification de
`pcmk_host_map`.

> [!NOTE]
> **Pourquoi**
>
> Pourquoi refuser `pcs stonith confirm lab-ha2` : cette commande dit à
> Pacemaker « je garantis que `lab-ha2` est éteint ». Or l'agent vient de
> montrer le contraire : la VM tourne, isolée du cluster mais peut-être
> encore active. Confirmer, c'est démarrer une deuxième instance de
> `lab29-batch`, précisément la double facturation que le cluster existe pour
> empêcher.
>
> `stonith confirm` est légitime dans un seul cas : on a **constaté par un
> autre moyen** que le nœud est éteint (console de l'hyperviseur, quelqu'un
> devant la baie, alimentation coupée à la main) et le fencing automatique
> est impossible (API de l'hyperviseur elle-même en panne). Même alors, on
> l'écrit dans le compte rendu d'incident.
>
> Le monitor de la ressource de fencing était vert pendant toute la panne : il
> vérifie qu'il peut parler à l'API, pas qu'il peut éteindre chacun des
> nœuds. Seul un vrai test le prouve.

---

## 29.8 Défi du module

<a id="d29"></a>**[D29](README.md#d29) — Mesurer la disponibilité, panne par panne**

*Livrable attendu : `chaos.sh`, le rapport daté, `runbook.md`.*

```bash
#!/usr/bin/env bash
# chaos.sh — pannes successives sur le dispositif HA du module 29, avec mesure
# Usage : chaos.sh [--sec]   (à lancer sur lab-adm ; --sec : simulation, rien n'est cassé)
# Prérequis : accès SSH sudo à lab-ha1/lab-ha2/lab-ops, et à root@pve pour qm.
set -euo pipefail

DEFI="$HOME/lab29/defi"; mkdir -p "$DEFI"
RAPPORT="$DEFI/rapport-$(date +%Y%m%d).md"
VIP=http://lab-vip/; BATCH=http://lab-batch:9029/
SEC=0; [ "${1:-}" = --sec ] && SEC=1
SONDE_PID=""

log() { printf '%s %s\n' "$(date +%T)" "$*" >&2; }
sur() { local h=$1; shift; if [ "$SEC" -eq 1 ]; then log "[sec] $h: $*"; else ssh -o BatchMode=yes "$h.lab.local" "$@"; fi; }
pve() { if [ "$SEC" -eq 1 ]; then log "[sec] pve: $*"; else ssh -o BatchMode=yes root@pve "$@"; fi; }

# --- état nominal -----------------------------------------------------------
porteurs_vip() { local n=0; for h in lab-ha1 lab-ha2; do
  ssh "$h.lab.local" ip -br addr show ens18 | grep -q '10.10.10.20/' && n=$((n + 1)); done; echo "$n"; }
nominal() {
  [ "$(porteurs_vip)" -eq 1 ] || { log "IP virtuelle portée par $(porteurs_vip) nœud(s)"; return 1; }
  ssh lab-ha1.lab.local "echo 'show stat' | sudo socat stdio /run/haproxy/admin.sock" |
    awk -F, '$1=="app" && $2 ~ /^app/ && $18!="UP" {exit 1}' || { log "serveur DOWN"; return 1; }
  ssh lab-ha1.lab.local 'sudo crm_mon -1f' | grep -qE 'fail-count|UNCLEAN|Stopped' &&
    { log "cluster non nominal"; return 1; }
  return 0
}
attendre_nominal() { for _ in $(seq 90); do nominal 2>/dev/null && return 0; sleep 2; done; return 1; }

# --- mesure -------------------------------------------------------------------
# une requête / 100 ms sur une URL ; écrit « horodatage_ms code » par ligne
sonde() { while :; do printf '%s %s\n' "$(date +%s%3N)" \
  "$(curl -s -o /dev/null -m 1 -w '%{http_code}' "$1" || true)"; sleep 0.1; done; }
mesurer() {  # mesurer <fichier> -> « interruption_s requêtes_perdues »
  awk '$2!="200"{p++; if(!d)d=$1; f=$1} END{printf "%.1f %d\n", (d?(f-d)/1000+0.1:0), p}' "$1"; }

nettoyer() {
  [ -n "$SONDE_PID" ] && kill "$SONDE_PID" 2>/dev/null || true
  log "remise en état…"
  sur lab-ha1 'sudo systemctl start haproxy keepalived' || true
  sur lab-ops 'sudo rm -f /run/lab29/maintenance' || true
  sur lab-ha1 'sudo pcs node unstandby --all; sudo pcs resource cleanup' || true
  pve 'qm start 9021 2>/dev/null; qm start 9022 2>/dev/null' || true
}
trap nettoyer EXIT INT TERM

# --- les pannes : nom | url mesurée | panne | remise en état ------------------
PANNES=(
  "HAProxy arrêté (lab-ha1)|$VIP|sur lab-ha1 sudo systemctl stop haproxy|sur lab-ha1 sudo systemctl start haproxy"
  "keepalived arrêté (lab-ha1)|$VIP|sur lab-ha1 sudo systemctl stop keepalived|sur lab-ha1 sudo systemctl start keepalived"
  "maintenance applicative (lab-ops)|$VIP|sur lab-ops 'sudo install -d /run/lab29; sudo touch /run/lab29/maintenance'|sur lab-ops sudo rm -f /run/lab29/maintenance"
  "extinction brutale de lab-ha1|$VIP|pve qm stop 9021|pve qm start 9021"
  "coupure Corosync sur lab-ha2|$BATCH|sur lab-ha2 'sudo nft add table inet chaos; sudo nft add chain inet chaos e { type filter hook input priority 0 \\; }; sudo nft add rule inet chaos e udp dport 5405 drop'|sur lab-ha2 'sudo nft delete table inet chaos 2>/dev/null' || true"
  "standby de lab-ha1|$BATCH|sur lab-ha1 sudo pcs node standby lab-ha1|sur lab-ha1 sudo pcs node unstandby lab-ha1"
)

[ "$SEC" -eq 1 ] || nominal || { log "dispositif non nominal au départ : abandon"; exit 1; }
{ echo "# Rapport de pannes — $(date '+%Y-%m-%d %H:%M')"; echo
  echo "| Panne | Interruption | Requêtes perdues | Retour au nominal |"
  echo "|---|---|---|---|"; } > "$RAPPORT"

for p in "${PANNES[@]}"; do
  IFS='|' read -r nom url panne remise <<<"$p"
  log "== $nom"
  mes="$DEFI/.mesure"; : > "$mes"
  sonde "$url" > "$mes" & SONDE_PID=$!
  sleep 3; t0=$(date +%s)
  eval "$panne"
  sleep 20
  eval "$remise"
  if [ "$SEC" -eq 1 ] || attendre_nominal; then retour=$(( $(date +%s) - t0 ))s; else retour="NON"; fi
  kill "$SONDE_PID"; SONDE_PID=""
  read -r duree perdues < <(mesurer "$mes")
  echo "| $nom | ${duree} s | $perdues | $retour |" >> "$RAPPORT"
  [ "$retour" != NON ] || { log "retour au nominal impossible : arrêt"; exit 1; }
done
log "rapport : $RAPPORT"
```

> [!NOTE]
> **Pourquoi**
>
> Les points qui font la valeur d'un tel script :
>
> * **Partir d'un état nominal vérifié** et y revenir entre deux pannes :
>   sinon la deuxième mesure hérite des séquelles de la première et ne veut
>   plus rien dire.
> * **Mesurer côté client**, avec une fréquence (10 requêtes/s) bien
>   supérieure à la durée des phénomènes observés, et un délai par requête
>   (`-m 1`) qui borne l'attente d'une requête perdue.
> * **Un mode simulation** (`--sec`) pour relire le déroulé sans rien casser,
>   et un `trap` qui remet en état même sur `Ctrl-C` : un outil de chaos qui
>   laisse le système cassé quand on l'interrompt est lui-même un incident.
> * **S'arrêter** si le retour au nominal échoue, plutôt qu'empiler les
>   pannes sur un système déjà dégradé.
>
> La conclusion du rapport transforme les mesures en disponibilité, par
> exemple : « hypothèse : une panne de nœud par trimestre et un redémarrage de
> HAProxy par mois ; interruptions mesurées 3,5 s et 4,6 s ; soit environ
> 70 s par an, bien inférieur à ce que coûtent les déploiements, qui
> deviennent le premier poste à traiter ». C'est ce raisonnement qu'on attend
> d'un expert : la haute disponibilité ne se décrète pas, elle se **mesure**.

Le runbook reprend, pour chaque alerte, trois commandes de diagnostic et une
action, par exemple :

```markdown
## IP virtuelle portée par deux nœuds
1. `ip -br addr show ens18` sur lab-ha1 et lab-ha2
2. `journalctl -u keepalived -n 20` : qui est MASTER, depuis quand
3. `sudo nft list ruleset` / `tcpdump -ni ens18 'ip proto 112'`
Action : rétablir la communication VRRP (pare-feu, réseau) ; en urgence,
arrêter keepalived sur le nœud qui ne devrait pas être maître.
```

<!-- nav:début -->
---

[← Module 28](../28-identite-centralisee/corrige.md) · [Énoncé](README.md) · [Module 30 →](../30-sauvegarde-pra/corrige.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
