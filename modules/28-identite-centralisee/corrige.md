<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Partie V — Expertise système › **Module 28** · corrigé  
[← Projet B](../../projets/P2-factura-devops/corrige.md) · [Énoncé](README.md) · [Module 29 →](../29-haute-disponibilite/corrige.md)

> [!TIP]
> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, pas avant. Chaque identifiant renvoie à son énoncé.
<!-- nav:fin -->

# Module 28 — Corrigé

## 28.3 Quiz — QCM

<a id="q28-1"></a>**[Q28.1](README.md#q28-1)** — *RDN de `uid=alice,cn=users,cn=accounts,dc=lab,dc=local`.*

**Réponse : b)** `uid=alice`.

> [!NOTE]
> **Pourquoi**
>
> Le DN se lit de gauche à droite, de la feuille vers la racine. Son premier
> composant est le **RDN** (*relative distinguished name*) : le nom de l'entrée
> parmi ses sœurs, unique sous un même parent. Le reste
> (`cn=users,cn=accounts,dc=lab,dc=local`) est le DN du parent. Toute entrée a
> un RDN, feuille ou non.
>
> Le suffixe `dc=lab,dc=local` est la base de l'arbre, dérivée du domaine DNS
> par FreeIPA. Renommer une entrée (`modrdn`) change son RDN ; la déplacer
> change son parent. Dans les deux cas, son DN change, ce qui explique
> pourquoi les références internes de FreeIPA (`member`, `memberOf`) sont
> maintenues par des greffons de l'annuaire (*referential integrity*,
> *memberOf*) et jamais à la main.

---

<a id="q28-2"></a>**[Q28.2](README.md#q28-2)** — *Recherche anonyme : l'entrée revient sans `memberOf`.*

**Réponse : c)** le bind anonyme n'a pas le droit de lire cet attribut.

> [!NOTE]
> **Pourquoi**
>
> 389-DS applique des **ACI** (*access control instructions*) attribut par
> attribut. FreeIPA les génère à partir de ses *permissions gérées* : la
> permission *System: Read User Standard Attributes* accorde à **tout le monde,
> anonymes compris** la lecture de `uid`, `cn`, `uidNumber`, `gidNumber`,
> `homeDirectory`, `loginShell`… ; la permission *System: Read User Membership*
> (qui couvre `memberOf`) est réservée aux clients **authentifiés**.
>
> La recherche anonyme ne renvoie donc pas d'erreur : elle renvoie l'entrée
> **amputée** des attributs interdits. C'est le comportement normal d'un
> annuaire, et la source de bien des scripts qui « marchent chez moi » parce
> que leur auteur était authentifié.
>
> ```bash
> ipa permission-show 'System: Read User Membership'    # bindtype : all
> ipa permission-show 'System: Read User Standard Attributes'   # anonymous
> ```
>
> En production, on resserre souvent l'accès anonyme
> (`ipa config-mod --addattr=…` ou `nsslapd-allow-anonymous-access: rootdse`)
> pour qu'un inconnu sur le réseau ne puisse pas lister les comptes.

---

<a id="q28-3"></a>**[Q28.3](README.md#q28-3)** — *Usage du TGT.*

**Réponse : c)** le présenter au TGS pour obtenir des tickets de service.

> [!NOTE]
> **Pourquoi**
>
> Le TGT est chiffré avec la clé du principal `krbtgt/LAB.LOCAL@LAB.LOCAL`,
> que seul le KDC connaît : le client ne peut ni le lire ni le modifier. Ce
> qu'il connaît, c'est la **clé de session** livrée à côté du TGT, dans la
> partie de la réponse chiffrée avec sa propre clé (dérivée de son mot de
> passe). Les dates d'expiration que montre `klist` viennent de cette partie,
> pas du TGT lui-même.
>
> Pour joindre `sshd` sur `lab-db`, le client envoie au TGS : le TGT + un
> **authentifiant** (son nom et l'heure, chiffrés avec la clé de session). Le
> TGS lui renvoie un ticket pour `host/lab-db.lab.local`, chiffré avec la clé
> de ce service. C'est ce ticket-là qui va au serveur, jamais le TGT.
>
> Conséquence de sécurité : le mot de passe ne sert qu'une fois par journée
> (`kinit`), et ne transite jamais, même chiffré.

---

<a id="q28-4"></a>**[Q28.4](README.md#q28-4)** — *Tolérance d'horloge.*

**Réponse : a)** 5 minutes.

> [!NOTE]
> **Pourquoi**
>
> Chaque authentifiant contient l'heure du client. Le serveur le refuse s'il
> s'écarte de plus de `clockskew` (300 s par défaut) de sa propre horloge, et
> garde en mémoire les authentifiants récents pour refuser un rejeu. C'est ce
> couple « horodatage + cache de rejeu » qui empêche quelqu'un ayant capturé un
> échange de le rejouer plus tard.
>
> Le paramètre existe côté KDC (`kdc.conf`) et côté bibliothèque cliente
> (`krb5.conf`, section `[libdefaults]`), mais l'augmenter est un pansement :
> la correction est une synchronisation horaire fiable sur **toutes** les
> machines (chrony, module 12), et une supervision de l'écart. BF28.1 en fait
> la démonstration.

---

<a id="q28-5"></a>**[Q28.5](README.md#q28-5)** — *Droits du keytab.*

**Réponse : d)** il contient les clés longues du principal.

> [!NOTE]
> **Pourquoi**
>
> Les clés Kerberos d'un principal sont dérivées de son mot de passe (ou tirées
> au hasard pour un hôte ou un service). Le keytab stocke ces clés **en
> clair** pour qu'un processus puisse s'authentifier sans humain : `kinit -k`,
> `sshd` qui déchiffre les tickets qu'on lui présente, `sssd` qui valide les
> TGT de ses utilisateurs. Copier `/etc/krb5.keytab` d'un serveur, c'est
> pouvoir se faire passer pour lui auprès de tout le domaine et déchiffrer les
> tickets qui lui sont destinés.
>
> Ni `kinit` ni le KDC ne vérifient les droits du fichier : c'est à
> l'administrateur de les poser (`0600`, propriétaire = le compte du service),
> de ne jamais le mettre dans un dépôt, une image disque ou une sauvegarde non
> chiffrée, et de le **régénérer** si une copie a pu fuiter, ce qui invalide
> l'ancien.

---

<a id="q28-6"></a>**[Q28.6](README.md#q28-6)** — *`getent passwd` sans argument.*

**Réponse : c)** l'énumération est désactivée par défaut.

> [!NOTE]
> **Pourquoi**
>
> Avec `enumerate = False` (le défaut, et la bonne valeur), SSSD répond aux
> demandes **nominatives** (`getent passwd alice`, `id alice`, une connexion)
> mais pas aux demandes de liste. Énumérer un annuaire de 50 000 comptes sur
> chaque machine à chaque `ls -l` serait ruineux pour le serveur et pour le
> client.
>
> Les outils à connaître pour lister quand même :
>
> ```bash
> getent passwd alice bruno             # nominatif : fonctionne
> ipa user-find --sizelimit=0           # côté annuaire, avec un ticket
> sssctl user-show alice                # ce que SSSD a en cache pour alice
> ```
>
> Si `getent passwd alice` échouait aussi, on regarderait alors SSSD (arrêté ?)
> et `nsswitch.conf` (`sss` absent ?) : réponses a) et b), qui donnent un
> symptôme différent.

---

<a id="q28-7"></a>**[Q28.7](README.md#q28-7)** — *sssd refuse de démarrer après une modification.*

**Réponse : a)** `/etc/sssd/sssd.conf` en `0600`, propriété de root.

> [!NOTE]
> **Pourquoi**
>
> Le fichier peut contenir des secrets (mot de passe de bind pour un
> fournisseur LDAP générique, par exemple), alors SSSD refuse tout fichier de
> configuration lisible par d'autres. Le message dans le journal :
>
> ```console
> $ sudo journalctl -u sssd -b | tail -3
> sssd[2241]: [sssd] [confdb_init_db] (0x0020): File ownership and permissions check failed. Expected root:root and 0600.
> sssd[2241]: [sssd] [main] (0x0010): Unable to read config file /etc/sssd/sssd.conf
> ```
>
> Le piège classique : éditer le fichier avec un outil qui le recrée (un
> `cp` depuis un modèle, un `tee`, un déploiement Ansible sans `mode:`), qui
> pose les droits par défaut `0644`. `sssctl config-check` détecte ce cas, et
> les modules Ansible (module 23) doivent toujours préciser `mode: "0600"`.
> Les versions récentes de SSSD (2.10 et plus) acceptent aussi `0640` avec le
> groupe `sssd` ; Ubuntu 24.04 et Rocky 9 exigent `0600`.

---

<a id="q28-8"></a>**[Q28.8](README.md#q28-8)** — *Après la désactivation d'`allow_all`, sans autre règle.*

**Réponse : c) et d)** `mathieu` et `root` en local.

> [!NOTE]
> **Pourquoi**
>
> Le HBAC est appliqué par `pam_sss`, dans la phase *account* de PAM, **pour
> les seuls comptes que SSSD gère**. Pour un compte présent dans `/etc/passwd`,
> `pam_sss` répond « utilisateur inconnu » et la pile PAM d'Ubuntu poursuit
> avec `pam_unix`, qui l'autorise. Les comptes locaux sont donc hors d'atteinte
> du HBAC : c'est la porte de secours qu'on garde ouverte pendant tout le
> module.
>
> Sans aucune règle active, **aucun** compte du domaine n'entre, `admin`
> compris : FreeIPA ne lui fait aucune exception. D'où l'ordre de L28.3 :
> règles de remplacement, `hbactest`, **puis** désactivation. Et d'où la règle
> explicite pour `admin`.

---

<a id="q28-9"></a>**[Q28.9](README.md#q28-9)** — *`ipa hbactest`.*

**Réponse : d)** il évalue les règles et dit laquelle accorderait l'accès.

> [!NOTE]
> **Pourquoi**
>
> `hbactest` exécute côté serveur le même moteur d'évaluation que SSSD
> (`libipa_hbac`) sur les règles de l'annuaire. Il ne touche à rien, ne se
> connecte nulle part, et répond :
>
> ```console
> $ ipa hbactest --user=bruno --host=lab-db.lab.local --service=sshd
> --------------------
> Access granted: False
> --------------------
>   Not matched rules: admins-partout
>   Not matched rules: auditeurs-serveurs
>   Not matched rules: devs-web
> ```
>
> Deux options utiles : `--rules=<règle>` pour tester une règle **désactivée**
> avant de l'activer, et `--disabled` pour inclure toutes les règles
> désactivées. C'est l'équivalent pour l'accès de `nft -c` pour le pare-feu
> (module 18) : on teste avant d'appliquer.

---

<a id="q28-10"></a>**[Q28.10](README.md#q28-10)** — *Clé publique d'alice absente de `authorized_keys`.*

**Réponse : a)** `AuthorizedKeysCommand /usr/bin/sss_ssh_authorizedkeys`.

> [!NOTE]
> **Pourquoi**
>
> `ipa-client-install` ajoute à la configuration de `sshd` :
>
> ```text
> AuthorizedKeysCommand /usr/bin/sss_ssh_authorizedkeys
> AuthorizedKeysCommandUser nobody
> ```
>
> À chaque tentative par clé, `sshd` lance cette commande avec le nom de
> l'utilisateur ; elle interroge SSSD, qui lit l'attribut `ipaSshPubKey` de
> l'entrée et le garde en cache. Le fichier `~/.ssh/authorized_keys` reste
> consulté **aussi** : les deux sources s'additionnent.
>
> Bénéfice : une clé publiée ou retirée dans l'annuaire prend effet sur toutes
> les machines, sans rien copier. Revers : une clé qui traîne dans un
> `authorized_keys` local échappe à l'annuaire, d'où la recherche de traces
> du défi D28.

---

<a id="q28-11"></a>**[Q28.11](README.md#q28-11)** — *Serveur FreeIPA éteint.*

**Réponse : c)** ceux qui se sont déjà connectés sur la machine, grâce au cache.

> [!NOTE]
> **Pourquoi**
>
> Avec `cache_credentials = True` (posé par `ipa-client-install`), SSSD garde
> une empreinte salée du mot de passe après chaque authentification **en
> ligne** réussie. Hors ligne, il compare le mot de passe saisi à cette
> empreinte : l'utilisateur entre, mais **sans ticket Kerberos** (il n'y a pas
> de KDC pour en délivrer). Un utilisateur qui ne s'est jamais connecté sur
> cette machine n'a pas d'empreinte : refus.
>
> Avec `krb5_store_password_if_offline = True`, SSSD garde aussi le mot de
> passe pour demander un TGT automatiquement quand le serveur revient.
> `offline_credentials_expiration` (en jours, 0 = sans limite) borne la durée
> pendant laquelle un cache permet d'entrer. C'est l'argument pour **deux
> serveurs FreeIPA au moins** (réplica, voir « Pour aller plus loin ») : le
> mode hors ligne dépanne, il ne remplace pas la redondance.

---

<a id="q28-12"></a>**[Q28.12](README.md#q28-12)** — *`curl --negotiate` vers une adresse IP.*

**Réponse : c)** le principal demandé est `HTTP/10.10.10.11`.

> [!NOTE]
> **Pourquoi**
>
> Le client construit le nom du service à partir de **ce qu'on lui a donné** :
> `HTTP/<hôte>@ROYAUME`. Avec une adresse IP, il demande au KDC un ticket pour
> `HTTP/10.10.10.11`, principal qui n'existe pas :
> `Server not found in Kerberos database`. Avec un nom court (`lab-web`), même
> problème, sauf si la bibliothèque le canonicalise par le DNS
> (`dns_canonicalize_hostname`, désactivé par défaut par FreeIPA pour des
> raisons de sécurité).
>
> Règle d'exploitation : en environnement Kerberos, **on ne s'adresse aux
> services que par leur nom pleinement qualifié**, et le DNS direct et inverse
> doit être juste. C'est la même raison pour laquelle `ssh 10.10.10.12` ne fait
> pas de GSSAPI.

---

<a id="q28-13"></a>**[Q28.13](README.md#q28-13)** — *`ipa-getkeytab` sur le principal d'un utilisateur.*

**Réponse : b)** ses clés sont régénérées, son mot de passe ne marche plus.

> [!NOTE]
> **Pourquoi**
>
> `ipa-getkeytab` demande au serveur de **tirer de nouvelles clés** pour le
> principal, d'incrémenter son numéro de version (kvno) et d'écrire ces clés
> dans le keytab. Les anciennes clés, et donc le mot de passe dont elles
> dérivaient, ne sont plus reconnues par le KDC. Un service dont on régénère
> le keytab perd de même l'ancien : il faut redéployer le nouveau partout où il
> servait.
>
> C'est exactement ce qu'on veut pour un compte de service (L28.4) : aucun
> mot de passe utilisable, seulement un keytab. C'est une catastrophe sur un
> compte humain. L'option `-r` (*retrieve*) récupère les clés existantes au
> lieu d'en créer, à condition que l'administrateur y soit autorisé
> (`ipa service-allow-retrieve-keytab`), pour déployer le même keytab sur
> plusieurs serveurs d'une grappe.

---

<a id="q28-14"></a>**[Q28.14](README.md#q28-14)** — *Groupe ajouté pendant une session ouverte.*

**Réponse : d)** la liste des groupes est calculée à l'ouverture de session.

> [!NOTE]
> **Pourquoi**
>
> Au login, `sshd` (via PAM et NSS) appelle `initgroups()`, qui interroge SSSD
> et pose la liste des groupes supplémentaires du processus avec
> `setgroups()`. Cette liste est héritée par tous les descendants et n'est
> plus jamais recalculée : le noyau ne connaît pas LDAP. La session de 9 h a
> la liste de 9 h.
>
> Deux délais s'additionnent pour une **nouvelle** session : le cache SSSD
> (`entry_cache_timeout`, 5 400 s par défaut, même si un login en ligne force
> en pratique un rafraîchissement des groupes de l'utilisateur) et le cache
> mémoire rapide de NSS (`memcache_timeout`, 300 s). `sss_cache -u alice` vide
> le premier pour un utilisateur ; une nouvelle connexion règle le reste. Ce
> mécanisme joue **dans les deux sens** : BF28.3 montre l'effet d'un retrait
> qui tarde à s'appliquer.

---

<a id="q28-15"></a>**[Q28.15](README.md#q28-15)** — *`passwd: files systemd sss`.*

**Réponse : a)** un compte local masque un compte de même nom dans l'annuaire.

> [!NOTE]
> **Pourquoi**
>
> La glibc interroge les sources **dans l'ordre** et s'arrête à la première
> qui répond (comportement par défaut `[SUCCESS=return]`). Si `/etc/passwd`
> contient un `alice` local, l'`alice` de l'annuaire est invisible sur cette
> machine : `id alice` montre l'UID local, `pam_sss` ne voit pas l'utilisateur,
> et les règles HBAC ou sudo du domaine ne s'appliquent pas.
>
> C'est voulu (les comptes système et la porte de secours restent locaux),
> et c'est un piège lors d'une migration vers l'annuaire : on supprime les
> comptes locaux homonymes après avoir réattribué leurs fichiers
> (`find / -xdev -uid <ancien> -exec chown <nouveau> {} +`, module 03).

---

<a id="q28-16"></a>**[Q28.16](README.md#q28-16)** — *Émission des certificats.*

**Réponse : b)** Dogtag.

> [!NOTE]
> **Pourquoi**
>
> Les rôles dans FreeIPA :
>
> | Composant | Rôle |
> |---|---|
> | 389-DS | annuaire LDAP, stocke **tout**, y compris les clés Kerberos et la configuration |
> | KDC MIT | Kerberos, avec un greffon qui lit les principaux dans 389-DS |
> | Dogtag | autorité de certification : certificats des hôtes, des services, des utilisateurs |
> | certmonger | sur chaque machine, **demande** et **renouvelle** les certificats auprès de la CA |
> | Apache + `ipa` | interface web et API JSON-RPC, que la commande `ipa` utilise |
> | SSSD | côté client (et sur le serveur lui-même) |
>
> certmonger n'émet rien : il suit les certificats (`getcert list`) et les
> renouvelle avant expiration. Un certificat expiré du serveur lui-même
> (celui d'Apache ou de 389-DS) est l'une des pannes FreeIPA les plus
> redoutées : `getcert list` et `ipa-healthcheck` en préviennent.

---

## 28.4 Quiz — questions ouvertes

<a id="qo28-1"></a>**[QO28.1](README.md#qo28-1)** — *De la saisie du mot de passe à l'invite de commande.*

**Réponse attendue**

1. **`sshd`** reçoit la connexion de `lab-adm`, négocie le chiffrement,
   puis demande l'utilisateur. Il vérifie qu'`alice` existe : appel NSS
   `getpwnam("alice")`, `nsswitch.conf` consulte `files` (absent), puis
   `sss` ; **SSSD** répond depuis son cache ou interroge LDAP.
2. Méthode `publickey` d'abord si alice a une clé : `sshd` lance
   `sss_ssh_authorizedkeys alice`. Sinon, mot de passe par
   `keyboard-interactive`, qui passe par **PAM** (service `sshd`).
3. Phase **auth** de PAM : `pam_sss` transmet le mot de passe au répondeur
   PAM de SSSD, qui lance `krb5_child` : demande d'un **TGT** au KDC de
   `lab-rhel` (AS-REQ avec pré-authentification). Réponse déchiffrée avec la
   clé dérivée du mot de passe : le mot de passe est juste. SSSD **valide**
   le TGT en demandant un ticket pour `host/lab-web.lab.local` et en le
   déchiffrant avec `/etc/krb5.keytab` : cela prouve que la réponse vient du
   vrai KDC et pas d'un usurpateur. Empreinte du mot de passe mise en cache.
4. Phase **account** : `pam_sss` demande l'autorisation ; le fournisseur
   d'accès `ipa` évalue les règles **HBAC** (alice, `lab-web`, `sshd`),
   vérifie que le compte n'est ni désactivé ni expiré, et le mot de passe
   non expiré (sinon, changement forcé).
5. Phase **session** : `pam_mkhomedir` crée `/home/alice` depuis
   `/etc/skel` au premier passage, `pam_systemd` enregistre la session
   auprès de logind (unité `user@<uid>.service`), le ticket est écrit dans
   le cache d'alice et `KRB5CCNAME` est exporté.
6. `sshd` appelle `initgroups()` (groupes via SSSD), change d'identité
   (`setgid`, `setgroups`, `setuid`) et exécute le shell de connexion
   indiqué par `loginShell` : invite de commande, avec `klist` non vide.

Ce qu'on attend en plus d'un expert : savoir **où regarder** à chaque étape
quand ça casse (`/var/log/sssd/sssd_pam.log`, `krb5_child.log`,
`sssd_lab.local.log`, `journalctl -u ssh`) et que les étapes 3 et 4 sont
distinctes : un mot de passe juste (auth OK) peut être refusé par le HBAC
(account KO), avec un message différent dans le journal
(`Access denied for user alice: 6 (Permission denied)`).

---

<a id="qo28-2"></a>**[QO28.2](README.md#qo28-2)** — *LDAP, Kerberos, SSSD, FreeIPA : qui fait quoi ?*

**Réponse attendue**

* **LDAP** est un **annuaire** : un protocole et une base arborescente pour
  stocker et chercher des informations (qui existe, quels groupes, quel
  shell, quelles clés SSH, quelles règles). Il sait vérifier un mot de passe
  (bind simple), mais c'est un effet de bord.
* **Kerberos** est un protocole d'**authentification** : il prouve une
  identité une fois (TGT), puis délivre des tickets pour chaque service,
  sans que le mot de passe circule, avec une authentification mutuelle et
  une session unique (SSO). Il ne stocke aucune information de profil.
* **SSSD** est le **client** côté machine : il consomme LDAP (identité,
  NSS) et Kerberos (authentification, PAM), applique le contrôle d'accès,
  garde un cache pour le mode hors ligne, et présente tout cela aux
  interfaces classiques (NSS, PAM, sudo, sshd).
* **FreeIPA** est la **solution intégrée** côté serveur : 389-DS + KDC +
  CA + DNS optionnel + API + interface web, avec des objets de haut niveau
  (utilisateur, hôte, règle sudo, règle HBAC) qui orchestrent tout cela de
  façon cohérente.

Pourquoi ne pas tout faire en LDAP : un bind simple envoie le mot de passe
au serveur **à chaque** authentification et sur **chaque** machine, ce qui
multiplie les points où il peut être intercepté ou journalisé ; il n'y a pas
d'authentification unique (chaque service redemande le mot de passe) ni
d'authentification du serveur auprès du client sans TLS correctement
configuré. Kerberos règle ces trois points. Les deux sont complémentaires :
Active Directory est d'ailleurs exactement cette combinaison.

---

<a id="qo28-3"></a>**[QO28.3](README.md#qo28-3)** — *Bind simple sur 389.*

**Réponse attendue**

Un bind simple envoie le DN et le mot de passe **en clair** dans la requête
LDAP. Sur le port 389 sans chiffrement, toute personne qui voit passer le
trafic (machine compromise sur le même réseau, miroir de port, capture
`tcpdump` oubliée) récupère le mot de passe. Le mot de passe arrive aussi en
clair dans le serveur, où il peut finir dans un journal d'audit mal réglé.

Corrections :

1. **chiffrer le transport** : `ldaps://` sur 636, ou StartTLS sur 389
   (`ldapsearch -ZZ`, qui échoue si TLS n'est pas négocié), avec
   vérification du certificat (`TLS_CACERT /etc/ipa/ca.crt` dans
   `/etc/ldap/ldap.conf`). Côté serveur, imposer le chiffrement
   (`nsslapd-require-secure-binds: on`, *minimum SSF*) pour qu'un client mal
   réglé échoue au lieu de fuir ;
2. **ne plus envoyer de mot de passe** : SASL/GSSAPI (`ldapsearch -Y
   GSSAPI`), qui présente un ticket Kerberos.

Ce que Kerberos apporte de plus qu'un LDAP chiffré : le mot de passe n'est
saisi qu'une fois et ne quitte jamais le poste (seule une preuve dérivée
circule) ; le **serveur** prouve aussi son identité (authentification
mutuelle) ; un ticket a une durée de vie limitée et est propre à un service,
ce qui limite l'intérêt d'en voler un ; et le même mécanisme sert à SSH,
HTTP, NFS, PostgreSQL… (SSO).

---

<a id="qo28-4"></a>**[QO28.4](README.md#qo28-4)** — *Le serveur d'identité tombe un lundi à 9 h.*

**Réponse attendue**

Continue de marcher :

* les **sessions ouvertes** et les tickets déjà délivrés, jusqu'à leur
  expiration (24 h par défaut pour un TGT) ;
* les connexions des utilisateurs **déjà connectés** sur une machine
  (cache des empreintes de mot de passe), mais sans nouveau ticket ;
* `id`, `ls -l`, les règles sudo et HBAC **en cache** ;
* les connexions par clé SSH si la clé est en cache SSSD ;
* tous les comptes locaux.

Casse :

* première connexion d'un utilisateur sur une machine, nouvel arrivant,
  changement de mot de passe, déverrouillage ;
* toute authentification Kerberos vers un service (SSO HTTP, NFS krb5, SSH
  GSSAPI entre machines, comptes de service par keytab : les sauvegardes de
  la nuit) ;
* l'inscription de nouvelles machines, l'émission et le renouvellement de
  certificats ;
* les modifications de droits (un départ ne peut pas être traité).

Ce qu'on prévoit :

* **au moins deux serveurs** FreeIPA répliqués (`ipa-replica-install`),
  dans deux zones de panne différentes, avec la CA et le KDC sur les deux,
  et des clients qui en connaissent deux (`ipa_server = _srv_` avec des
  enregistrements SRV, ou une liste explicite) ;
* **sauvegarde** (`ipa-backup`, complète et données) testée par une
  restauration (module 30), le serveur stockant les clés de tout le domaine ;
* **supervision** : `ipa-healthcheck` (certificats, réplication, services),
  expiration des certificats, écart d'horloge, état de la réplication ;
* une **procédure dégradée** documentée : comptes locaux de secours sur les
  serveurs critiques, accès console, et la liste de ce qui ne marchera pas.

---

<a id="qo28-5"></a>**[QO28.5](README.md#qo28-5)** — *Départ d'un administrateur.*

**Réponse attendue**

Dans l'ordre :

1. **Bloquer les nouvelles authentifications** : `ipa user-disable <login>`.
   Le KDC refuse tout nouveau TGT, SSSD refuse les connexions en ligne.
   On **désactive** plutôt que de supprimer : l'UID n'est pas réattribué,
   les fichiers et les journaux restent attribuables (ou `ipa user-del
   --preserve`, qui le déplace dans les comptes conservés).
2. **Relever les traces avant d'effacer** : empreintes de ses clés SSH
   (`ipa user-show --all`), liste de ses groupes et rôles, appartenance
   aux règles sudo et HBAC nominatives.
3. **Retirer les droits** : clés SSH (`--sshpubkey=`), groupes, rôles
   FreeIPA (`ipa role-remove-member`), règles sudo et HBAC qui le citent.
4. **Couper l'existant** sur chaque machine : `loginctl terminate-user`,
   processus restants (`pkill -u`), tâches `crontab` et `at`, puis
   `sss_cache -E` pour que le cache ne serve plus les anciens droits.
   Les tickets déjà délivrés restent valides jusqu'à leur expiration auprès
   des services qui ne recontactent pas le KDC : couper les sessions ne
   suffit pas, il faut aussi que ses tickets meurent (24 h au plus).

Ce que FreeIPA ne voit pas, et qu'il faut traiter à part :

* clés posées dans les `authorized_keys` d'**autres** comptes (root,
  comptes de service, `mathieu`) ;
* comptes **locaux** qu'il aurait créés, entrées dans `/etc/sudoers.d/` ;
* **secrets partagés** qu'il connaissait : mots de passe du Directory
  Manager et d'`admin`, comptes root locaux, coffres-forts, clés d'API,
  jetons de CI, accès console Proxmox. Tous à **changer** ;
* accès hors domaine : forge Git, supervision, fournisseurs cloud, VPN ;
* ses keytabs de services personnels, s'il en avait.

Puis on **vérifie** (tentative de connexion, `hbactest`, recherche de ses
empreintes de clés) et on trace l'opération. C'est l'objet de D28.

---

<a id="qo28-6"></a>**[QO28.6](README.md#qo28-6)** — *FreeIPA, AD + SSSD, OpenLDAP nu.*

**Réponse attendue**

| | FreeIPA | AD + `realmd`/SSSD | OpenLDAP + `pam_ldap` |
|---|---|---|---|
| Parc visé | majoritairement Linux | majoritairement Windows, Linux en invité | parc minimal, besoin très spécifique |
| Kerberos, SSO | intégré | intégré (AD est un KDC) | à construire à côté |
| sudo, HBAC, clés SSH | objets natifs | GPO limitées ; sudo via schéma ou fichiers | à construire (schéma sudo, scripts) |
| CA, certificats | intégrée (Dogtag) | AD CS | à côté |
| Hors ligne | SSSD | SSSD | rien (`nscd` au mieux) |
| Coût d'exploitation | moyen | dépend de l'équipe Windows | élevé : tout est manuel |

* **FreeIPA** quand l'équipe Linux maîtrise son identité et veut sudo,
  HBAC, clés SSH et certificats gérés au même endroit. Possible de
  l'**approuver** avec un AD existant (*trust*) pour que les comptes AD
  entrent sur les serveurs Linux selon les règles FreeIPA.
* **AD + SSSD** (`realm join`) quand l'entreprise a déjà un AD qui fait
  foi : on ne crée pas une seconde source de vérité pour les personnes.
* **OpenLDAP nu** : rarement un bon choix aujourd'hui pour authentifier des
  machines. `pam_ldap`/`nss_ldap` sont abandonnés au profit de SSSD (ou
  `nslcd`), et il faut tout reconstruire. Reste pertinent comme annuaire
  applicatif (carnet d'adresses, back-end d'une application).

---

<a id="qo28-7"></a>**[QO28.7](README.md#qo28-7)** — *Plages d'UID élevées.*

**Réponse attendue**

FreeIPA tire au hasard, à l'installation, une plage de 200 000 identifiants
au-delà de 1 000 000 (visible avec `ipa idrange-find`). But : **ne jamais
entrer en collision** avec les comptes locaux (UID 1000 et plus attribués par
`useradd`) ni avec les plages d'un autre domaine avec lequel on pourrait
établir une relation d'approbation plus tard.

Avec NFS en `sec=sys` (AUTH_SYS, sans Kerberos), le serveur fait confiance à
l'**UID numérique** envoyé par le client. Si `mathieu` a l'UID 1001 sur une
machine et `bruno` l'UID 1001 sur une autre, chacun lit les fichiers de
l'autre sur le partage. Les comptes du domaine règlent ce problème parce
qu'ils ont le **même UID partout**.

Pendant une migration, les fichiers existants appartiennent encore aux
anciens UID locaux : il faut les réattribuer (`chown` après inventaire par
`find -uid`) avant de supprimer les comptes locaux. Et pour vraiment
sécuriser NFS, on passe en `sec=krb5p` : le serveur vérifie un ticket au lieu
de croire un numéro.

---

<a id="qo28-8"></a>**[QO28.8](README.md#qo28-8)** — *Règles d'exploitation d'un compte de service par keytab.*

**Réponse attendue**

* **Stockage** : un fichier par service et par machine, hors des
  répertoires de l'application et des dépôts, jamais dans une image ou un
  conteneur construit ; `0600`, propriétaire = le compte qui l'utilise, et
  idéalement une unité systemd qui le charge (`LoadCredential=`) plutôt
  qu'un chemin lisible par tout le processus.
* **Périmètre** : un compte par usage (pas un `svc-tout`), une règle HBAC
  qui ne lui ouvre que la machine et le service nécessaires, une règle sudo
  réduite à **une** commande exacte avec ses arguments, `!authenticate`
  seulement là.
* **Rotation** : régénérer périodiquement (`ipa-getkeytab` sans `-r`) et à
  chaque soupçon de fuite ou départ d'un administrateur qui y avait accès.
  La régénération invalide l'ancien keytab partout : planifier le
  redéploiement.
* **Pas de mot de passe** : le compte n'en a jamais eu, ou il est devenu
  inutilisable à la première génération du keytab.
* **Surveillance** : journal des authentifications du principal sur le KDC
  (`/var/log/krb5kdc.log`) et des connexions sur la cible ; une alerte si le
  principal s'authentifie depuis une machine qui n'est pas la sienne.
* **Inventaire** : qui possède quel keytab, où, pour quoi, depuis quand
  (`ipa service-find`, `ipa user-find --desc=service`), revu
  périodiquement.

---

## 28.5 Exercices guidés

<a id="e28-1"></a>**[E28.1](README.md#e28-1)** — *Prérequis du serveur en quatre commandes.*

```bash
hostnamectl --static                # lab-rhel.lab.local
getent ahostsv4 lab-rhel.lab.local  # 10.10.10.13, pas 127.0.0.1
getent hosts 10.10.10.13            # 10.10.10.13  lab-rhel.lab.local lab-rhel
chronyc tracking | grep -E 'Leap status|System time'
```

Si le nom est court : `sudo hostnamectl set-hostname lab-rhel.lab.local`, et
empêcher cloud-init de le remettre au prochain démarrage :

```bash
echo 'preserve_hostname: true' | sudo tee /etc/cloud/cloud.cfg.d/99-fqdn.cfg
```

> [!NOTE]
> **Pourquoi**
>
> `ipa-server-install` refuse de continuer si le nom n'est pas pleinement
> qualifié ou s'il se résout vers une adresse de boucle locale : les
> principaux Kerberos (`host/lab-rhel.lab.local`, `ldap/…`, `HTTP/…`) et les
> certificats sont **construits sur ce nom**. Le changer après coup revient à
> réinstaller le serveur.
>
> `getent` plutôt que `dig` : `getent` suit `nsswitch.conf` (donc
> `/etc/hosts`, puis le DNS), comme le feront les logiciels ; `dig` interroge
> le DNS seul. Les deux doivent être d'accord : l'installateur vérifie les
> deux. Une ligne `127.0.1.1 lab-rhel.lab.local` ajoutée par une image cloud
> dans `/etc/hosts` est la cause d'échec la plus fréquente.

---

<a id="e28-2"></a>**[E28.2](README.md#e28-2)** — *Ticket `admin`, cache, destruction.*

```bash
kinit admin
klist -e
kdestroy
klist                    # klist: No credentials cache found
```

```console
$ klist -e
Ticket cache: KCM:0:51234
Default principal: admin@LAB.LOCAL

Valid starting       Expires              Service principal
11/09/2026 10:02:11  11/10/2026 09:41:30  krbtgt/LAB.LOCAL@LAB.LOCAL
	Etype (skey, tkt): aes256-cts-hmac-sha384-192, aes256-cts-hmac-sha384-192
```

> [!NOTE]
> **Pourquoi**
>
> Trois informations à lire : le **type de cache** (`KCM:` sur Rocky 9 : le
> cache est tenu par le démon `sssd-kcm` et survit aux redémarrages de session ;
> `FILE:/tmp/krb5cc_<uid>` ou `KEYRING:` ailleurs), la **durée de vie**
> (24 h maximum dans FreeIPA, renouvelable 7 jours), et les **types de
> chiffrement** : `skey` est celui de la clé de session, `tkt` celui du ticket
> lui-même. Les familles AES-SHA2 (RFC 8009) remplacent AES-SHA1 sur les
> versions récentes ; DES et RC4 sont désactivés et doivent le rester.
>
> `kdestroy` en fin d'intervention est une bonne habitude sur une machine
> partagée : un cache `admin` laissé ouvert 24 h est une session root sur
> l'annuaire.

---

<a id="e28-3"></a>**[E28.3](README.md#e28-3)** — *Utilisateur `bruno` et groupe `devs` en ligne de commande.*

```bash
ipa group-add devs --desc="Développeurs"
ipa user-add bruno --first=Bruno --last=Lefèvre --password
ipa group-add-member devs --users=bruno
ipa user-show bruno | grep -i 'member of groups'
#   Member of groups: ipausers, devs
```

> [!NOTE]
> **Pourquoi**
>
> `--password` demande le mot de passe deux fois sur le terminal (rien dans
> l'historique). Un mot de passe posé par un administrateur est **expiré
> d'emblée** : bruno devra le changer à sa première connexion. C'est le
> comportement voulu par FreeIPA : l'administrateur ne doit pas connaître le
> mot de passe que l'utilisateur utilise réellement.
>
> `ipausers` est le groupe par défaut de tous les utilisateurs ; il est
> non-POSIX (pas de GID), donc absent de `id bruno`. En script, `--random` à
> la place de `--password` génère un mot de passe initial et l'affiche une
> seule fois (D28).

---

<a id="e28-4"></a>**[E28.4](README.md#e28-4)** — *`ldapsearch` anonyme puis GSSAPI.*

```bash
ldapsearch -LLL -x -H ldap://lab-rhel.lab.local \
  -b cn=users,cn=accounts,dc=lab,dc=local '(uid=alice)'
kinit alice
ldapsearch -LLL -Y GSSAPI -H ldap://lab-rhel.lab.local \
  -b cn=users,cn=accounts,dc=lab,dc=local '(uid=alice)' memberOf
```

```console
SASL/GSSAPI authentication started
SASL username: alice@LAB.LOCAL
SASL SSF: 256
dn: uid=alice,cn=users,cn=accounts,dc=lab,dc=local
memberOf: cn=ipausers,cn=groups,cn=accounts,dc=lab,dc=local
memberOf: cn=admins-lab,cn=groups,cn=accounts,dc=lab,dc=local
memberOf: ipaUniqueID=4f3e…,cn=sudorules,cn=sudo,dc=lab,dc=local
```

DN complet d'un groupe : `cn=admins-lab,cn=groups,cn=accounts,dc=lab,dc=local`.

> [!NOTE]
> **Pourquoi**
>
> La recherche anonyme montre les attributs « publics » (`uid`, `cn`,
> `uidNumber`, `homeDirectory`, `loginShell`…), pas `memberOf` ni `mail` (Q28.2).
> En GSSAPI, `SASL SSF: 256` indique que la session LDAP est **chiffrée** par la
> couche SASL elle-même, sans TLS : la négociation GSSAPI fournit une
> protection d'intégrité et de confidentialité.
>
> `memberOf` liste aussi les **règles sudo et HBAC** dont l'entrée est
> membre directement. `-LLL` retire les commentaires et la version LDIF, pour
> une sortie exploitable en script. Si `-Y GSSAPI` échoue avec `No such
> mechanism`, il manque le greffon SASL : paquet
> `libsasl2-modules-gssapi-mit`.

---

<a id="e28-5"></a>**[E28.5](README.md#e28-5)** — *Configuration écrite par `ipa-client-install`.*

```bash
sudo cat /etc/sssd/sssd.conf
cat /etc/krb5.conf
```

```ini
[domain/lab.local]
id_provider = ipa
ipa_server = lab-rhel.lab.local
ipa_domain = lab.local
ipa_hostname = lab-web.lab.local
auth_provider = ipa
chpass_provider = ipa
access_provider = ipa
cache_credentials = True
ldap_tls_cacert = /etc/ipa/ca.crt
krb5_store_password_if_offline = True

[sssd]
services = nss, pam, ssh, sudo
domains = lab.local
```

| Option | Rôle |
|---|---|
| `id_provider = ipa` | les identités (NSS) viennent de FreeIPA, avec son schéma et ses extensions (HBAC, sudo, clés SSH) |
| `ipa_server` | serveur à contacter ; `_srv_` (découverte DNS) en tête de liste pour basculer automatiquement |
| `cache_credentials` | garder l'empreinte du mot de passe pour le mode hors ligne |
| `default_realm` | royaume utilisé quand un principal est donné sans `@ROYAUME` (`kinit alice`) |
| `dns_lookup_kdc` | chercher les KDC par enregistrements SRV ; `false` ici puisque le serveur est donné explicitement |

> [!NOTE]
> **Pourquoi**
>
> `ipa-client-install` pose aussi dans `krb5.conf` `udp_preference_limit = 0`
> (Kerberos toujours en TCP : les tickets FreeIPA, avec leur PAC, dépassent
> souvent la taille d'un datagramme) et `dns_canonicalize_hostname = false`
> (Q28.12). Le fichier est **géré** : le modifier à la main est légitime pour
> un réglage local (BF28.3), mais une réinscription l'écrasera. Le noter dans
> la documentation de la machine.

---

<a id="e28-6"></a>**[E28.6](README.md#e28-6)** — *État du domaine et autorisation de `sshd` pour alice.*

```bash
sudo sssctl domain-status lab.local
sudo sssctl user-checks alice -s sshd -a acct
```

```console
Online status: Online
Active servers:
IPA: lab-rhel.lab.local
Discovered IPA servers:
- lab-rhel.lab.local

user: alice
action: acct
service: sshd
SSSD nss user lookup result:
 - user name: alice
 - user id: 1186400003
 - home directory: /home/alice
pam_acct_mgmt: Success
```

> [!NOTE]
> **Pourquoi**
>
> `user-checks` rejoue la pile PAM du service choisi, sans ouvrir de session
> ni créer de répertoire. Avec `-a acct`, on teste exactement ce qui échoue
> quand le HBAC refuse : `Permission denied` ici signifie « mot de passe pas en
> cause, c'est l'autorisation ». Avec `-a auth`, la commande demande le mot de
> passe. C'est l'outil à utiliser avant d'accuser le réseau, le pare-feu ou
> `sshd`.

---

<a id="e28-7"></a>**[E28.7](README.md#e28-7)** — *Politique de mots de passe.*

```bash
ipa pwpolicy-mod --minlength=12 --minclasses=3 --maxlife=90 \
  --history=5 --maxfail=5 --failinterval=60 --lockouttime=900
ipa pwpolicy-show
```

> [!NOTE]
> **Pourquoi**
>
> `maxlife` est en **jours**, `lockouttime` et `failinterval` en **secondes** :
> 5 échecs en 60 s verrouillent pendant 15 minutes. Le verrouillage est tenu
> par le KDC (attributs `krbLoginFailedCount`, `krbLastFailedAuth`), donc il
> compte les échecs Kerberos quelle que soit leur origine (SSH, `kinit`,
> interface web).
>
> On peut créer des politiques **par groupe** (`ipa pwpolicy-add admins-lab
> --priority=1 --minlength=16`), la plus petite priorité gagnant. Une
> politique d'expiration à 90 jours est discutée aujourd'hui (le NIST la
> déconseille sans indice de compromission) : en faire un choix argumenté,
> pas un réflexe.

---

<a id="e28-8"></a>**[E28.8](README.md#e28-8)** — *Verrouillage et déverrouillage de `bruno`.*

```bash
# lab-adm : cinq échecs volontaires
for i in 1 2 3 4 5; do echo 'mauvais' | kinit bruno >/dev/null 2>&1; done
echo 'mauvais' | kinit bruno
# kinit: Client's credentials have been revoked while getting initial credentials

kinit admin
ipa user-status bruno
ipa user-unlock bruno
```

```console
-----------------------
Account disabled: False
-----------------------
  Server: lab-rhel.lab.local
  Failed logins: 5
  Last successful authentication: 20261109101503Z
  Last failed authentication: 20261109102211Z
  Time now: 2026-11-09T10:22:14Z
```

> [!NOTE]
> **Pourquoi**
>
> `credentials have been revoked` est le message du KDC pour un compte
> verrouillé (ou désactivé). `user-status` interroge **chaque serveur** : avec
> des réplicas, les compteurs d'échecs sont locaux à chaque serveur et ne sont
> pas répliqués, et l'état affiché diffère d'un serveur à l'autre. C'est pour
> cela que la commande s'appelle *status* et liste les serveurs.
>
> Un verrouillage automatique est aussi un outil de **déni de service** : qui
> connaît un login peut le verrouiller en boucle. Ce compromis justifie un
> `lockouttime` court plutôt qu'un verrouillage définitif.

---

<a id="e28-9"></a>**[E28.9](README.md#e28-9)** — *Clé SSH dans l'annuaire.*

```bash
# lab-adm
ipa user-mod alice --sshpubkey="$(cat ~/lab28/cles/alice.pub)"
# lab-web
sss_ssh_authorizedkeys alice
sudo ls -la /home/alice/.ssh 2>/dev/null || echo "pas de ~/.ssh"
sudo sshd -T | grep -i authorizedkeyscommand
# lab-adm
ssh -i ~/lab28/cles/alice -o IdentitiesOnly=yes alice@lab-web.lab.local id
```

> [!NOTE]
> **Pourquoi**
>
> `sss_ssh_authorizedkeys` affiche ce que `sshd` recevra. Plusieurs clés
> s'ajoutent en répétant `--sshpubkey` (la commande **remplace** la liste à
> chaque appel : `ipa user-mod alice --sshpubkey=` vide tout). `IdentitiesOnly`
> évite que l'agent SSH de `mathieu` ne propose d'abord ses propres clés et
> n'épuise le nombre d'essais autorisés (`MaxAuthTries`).

---

<a id="e28-10"></a>**[E28.10](README.md#e28-10)** — *`kinit` tracé.*

```bash
KRB5_TRACE=/dev/stderr kinit alice 2>&1 | grep -E 'Sending|TCP|etype|error|Received'
```

```console
[3021] 1762683000.1: Sending request (192 bytes) to LAB.LOCAL
[3021] 1762683000.2: Resolving hostname lab-rhel.lab.local
[3021] 1762683000.3: Initiating TCP connection to stream 10.10.10.13:88
[3021] 1762683000.4: Received answer (334 bytes) from stream 10.10.10.13:88
[3021] 1762683000.5: Response was from primary KDC
[3021] 1762683000.6: Received error from KDC: -1765328359/Additional pre-authentication required
[3021] 1762683000.7: Selected etype info: etype aes256-sha2, salt "…", params ""
```

> [!NOTE]
> **Pourquoi**
>
> Lecture : le royaume, le KDC trouvé dans `krb5.conf` (`kdc =`), le transport
> (**TCP**, à cause de `udp_preference_limit = 0`), puis le premier échange
> volontairement « en erreur » : le KDC exige une pré-authentification et
> indique le type de chiffrement et le sel à utiliser pour dériver la clé du
> mot de passe. Le client répond avec un horodatage chiffré (ou un mécanisme
> plus récent comme SPAKE), d'où l'importance de l'horloge.
>
> `KRB5_TRACE` fonctionne avec **tout** programme lié à la bibliothèque MIT
> (`ssh`, `curl --negotiate`, `ldapsearch -Y GSSAPI`) : c'est le premier
> réflexe devant une erreur Kerberos opaque.

---

<a id="e28-11"></a>**[E28.11](README.md#e28-11)** — *Ticket de service et kvno.*

```bash
# lab-adm
kinit alice
kvno host/lab-db.lab.local
# host/lab-db.lab.local@LAB.LOCAL: kvno = 1
klist | grep host/
# lab-db
sudo klist -k /etc/krb5.keytab | grep host/
#    1 host/lab-db.lab.local@LAB.LOCAL   (une ligne par type de chiffrement)
```

> [!NOTE]
> **Pourquoi**
>
> Le kvno du ticket (version de la clé avec laquelle le KDC l'a chiffré) doit
> correspondre à une clé présente dans le keytab du serveur. Si quelqu'un a
> régénéré le keytab de `lab-db` sur le serveur sans le redéployer, le KDC
> chiffre avec le kvno 2 et le keytab ne contient que le 1 : `sshd` ne peut
> pas déchiffrer, GSSAPI échoue, et le journal du serveur parle de
> `Key version number for principal in key table is incorrect`. Comparer les
> deux kvno est le diagnostic de cette panne.

---

<a id="e28-12"></a>**[E28.12](README.md#e28-12)** — *Groupe ajouté, cache, session ouverte.*

```bash
# lab-adm
ipa group-add-member devs --users=alice
# lab-web
id alice                         # pas de devs : réponse en cache
sudo sss_cache -u alice
id alice                         # devs apparaît
```

> [!NOTE]
> **Pourquoi**
>
> `sss_cache -u alice` **marque comme expirées** les entrées d'alice : la
> prochaine demande ira à l'annuaire. On ne supprime jamais
> `/var/lib/sss/db/*` sur une machine en service : on perd aussi les
> empreintes de mots de passe (plus de mode hors ligne) et le cache peut se
> retrouver incohérent si `sssd` tourne.
>
> La session SSH déjà ouverte d'alice garde la liste de groupes posée par
> `setgroups()` à sa connexion (Q28.14) : `id` dans cette session, sans
> argument, lit la liste du processus et ne montre pas `devs`. Elle doit se
> reconnecter. `newgrp devs` ouvrirait un sous-shell avec le groupe, mais
> c'est un contournement, pas une application de la politique.

---

## 28.6 Labs

### <a id="l28-1"></a>**[L28.1](README.md#l28-1)** — Le serveur d'identité de l'équipe

*Prérequis vérifiés, installation non interactive sans DNS intégré, pare-feu,
comptes importés depuis un fichier.*

**Étape 1 — Prérequis**

```bash
sudo hostnamectl set-hostname lab-rhel.lab.local
echo 'preserve_hostname: true' | sudo tee /etc/cloud/cloud.cfg.d/99-fqdn.cfg
grep -E 'lab-rhel' /etc/hosts      # 10.10.10.13 lab-rhel.lab.local lab-rhel
getent ahostsv4 lab-rhel.lab.local | head -1
getent hosts 10.10.10.13
chronyc tracking | grep 'Leap status'          # Normal
free -h | awk '/Mem:/{print $2}'               # ~3,6Gi après qm set --memory 4096
sudo bash ~/workbook/scripts/setup/setup_M28.sh   # bilan des prérequis
```

**Étape 2 — Installation**

```bash
sudo dnf install -y ipa-server
sudo ipa-server-install --unattended \
  --realm=LAB.LOCAL --domain=lab.local --hostname=lab-rhel.lab.local \
  --ds-password="$(read -rsp 'Directory Manager : ' p; echo "$p")" \
  --admin-password="$(read -rsp 'admin : ' p; echo "$p")" \
  --no-ntp
```

Compter une quinzaine de minutes. L'installateur se termine par la liste
des ports à ouvrir et un rappel : sans DNS intégré, les enregistrements SRV
du domaine ne sont pas publiés (il les écrit dans
`/tmp/ipa.system.records.*.db` pour qui voudrait les ajouter au DNS).

> [!NOTE]
> **Pourquoi**
>
> `--no-ntp` garde la configuration chrony du chapitre 0 (le nœud Proxmox
> comme référence). Sans cette option, l'installateur réécrit `chrony.conf`
> vers un serveur public, ce qui n'est pas souhaitable sur un réseau isolé.
>
> Les mots de passe sont lus au clavier (`read -s`) et passés en argument : ils
> n'apparaissent pas dans l'historique, mais restent visibles dans `ps`
> pendant l'installation. Sur une machine partagée, on préfère le mode
> interactif. Le **Directory Manager** est le super-utilisateur de 389-DS,
> au-dessus de toutes les ACI : il ne sert qu'en cas de réparation de
> l'annuaire. `admin` est le compte d'administration de FreeIPA au quotidien.

**Étape 3 — Pare-feu**

```bash
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --permanent --zone=public --add-service=freeipa-4
sudo firewall-cmd --reload
sudo firewall-cmd --zone=public --list-services
```

`freeipa-4` regroupe HTTP/HTTPS (80, 443), Kerberos (88), kpasswd (464),
LDAP/LDAPS (389, 636). La zone est `public` parce que c'est celle des
clients ; la zone `internal` du module 18 ne contient que `lab-adm`.

**Étape 4 — État et premier ticket**

```bash
sudo ipactl status
kinit admin
ipa user-find --sizelimit=0 | grep 'User login'
```

```console
Directory Service: RUNNING
krb5kdc Service: RUNNING
kadmin Service: RUNNING
httpd Service: RUNNING
ipa-custodia Service: RUNNING
pki-tomcatd Service: RUNNING
ipa-otpd Service: RUNNING
ipa: INFO: The ipactl command was successful
```

**Étape 5 — Import des comptes**

```bash
cat ~/lab28/utilisateurs.csv
# login;prenom;nom;groupes
# alice;Alice;Martin;admins-lab
# bruno;Bruno;Lefèvre;devs
# chloe;Chloé;Bernard;auditeurs
# david;David;Moreau;devs,auditeurs

for g in admins-lab devs auditeurs; do
  ipa group-show "$g" >/dev/null 2>&1 || ipa group-add "$g"
done

tail -n +2 ~/lab28/utilisateurs.csv |
while IFS=';' read -r login prenom nom groupes; do
  if ! ipa user-show "$login" >/dev/null 2>&1; then
    ipa user-add "$login" --first="$prenom" --last="$nom" --random |
      awk -v u="$login" '/Random password/{print u" : "$3}' >> ~/lab28/secrets.md
  fi
  IFS=',' read -ra gs <<< "$groupes"
  for g in "${gs[@]}"; do
    ipa group-add-member "$g" --users="$login" >/dev/null || true
  done
done
chmod 600 ~/lab28/secrets.md
ipa group-show admins-lab devs auditeurs 2>/dev/null | grep -E 'Group name|Member users'
```

> [!NOTE]
> **Pourquoi**
>
> La boucle est **idempotente** : relancée, elle ne recrée pas les comptes et
> `group-add-member` sur un membre existant échoue sans conséquence (d'où le
> `|| true`). Les mots de passe aléatoires vont dans un fichier `0600` non
> versionné, jamais à l'écran d'un terminal partagé. Ils sont expirés : chaque
> utilisateur choisit le sien à sa première connexion.
>
> `IFS=';' read -r` découpe la ligne sans interpréter les antislashs ; le
> `IFS=','` du second `read` découpe la liste des groupes en tableau. C'est le
> modèle de toute importation de comptes depuis un export RH (module 06).

**Étape 6 — Interface web**

```bash
# sur ton poste : un proxy SOCKS à travers lab-adm (Host lab-adm du §0.4)
ssh -D 1080 -N lab-adm
```

Dans Firefox : proxy SOCKS v5 `127.0.0.1:1080`, case « Utiliser un DNS
distant » cochée, puis `https://lab-rhel.lab.local/`.

> [!NOTE]
> **Pourquoi**
>
> Un simple `ssh -L 8443:lab-rhel.lab.local:443` ne suffit pas : l'interface
> redirige vers son nom canonique `https://lab-rhel.lab.local/ipa/ui/`, que le
> navigateur ne sait pas résoudre, et vérifie l'en-tête `Referer`. Le proxy
> SOCKS avec DNS distant fait résoudre le nom **par lab-adm**, qui connaît
> `lab.local`.
>
> L'avertissement du navigateur vient de ce que le certificat d'Apache est
> signé par la **CA du domaine** (`CN=Certificate Authority,O=LAB.LOCAL`), que
> le navigateur ne connaît pas. La correction propre est d'importer
> `/etc/ipa/ca.crt` comme autorité de confiance dans le navigateur, pas
> d'accepter l'exception : c'est la même CA qui signera les certificats de
> tous les services du domaine.

---

### <a id="l28-2"></a>**[L28.2](README.md#l28-2)** — Inscrire les serveurs Ubuntu

*Inscription interactive de `lab-web`, inventaire des modifications, puis
inscription reproductible par mot de passe à usage unique.*

**Étape 1 — `lab-web`**

```bash
sudo DEBIAN_FRONTEND=noninteractive apt install -y freeipa-client \
  sssd-tools ldap-utils krb5-user libsasl2-modules-gssapi-mit
echo 'preserve_hostname: true' | sudo tee /etc/cloud/cloud.cfg.d/99-fqdn.cfg
sudo ipa-client-install --domain=lab.local --realm=LAB.LOCAL \
  --server=lab-rhel.lab.local --hostname=lab-web.lab.local \
  --mkhomedir --no-ntp --principal=admin
```

**Étape 2 — Ce qui a changé**

| Fichier | Modification | Ce qu'elle permet |
|---|---|---|
| `/etc/sssd/sssd.conf` | domaine `lab.local`, fournisseurs `ipa` | identités, authentification et accès par FreeIPA |
| `/etc/krb5.conf` | royaume `LAB.LOCAL`, KDC `lab-rhel` | `kinit`, validation des TGT, GSSAPI |
| `/etc/krb5.keytab` | clés de `host/lab-web.lab.local` | la machine prouve son identité (SSSD vers LDAP, `sshd` GSSAPI) |
| `/etc/nsswitch.conf` | `sss` sur `passwd`, `group`, `shadow`, `sudoers`… | les comptes du domaine existent pour la glibc et pour sudo |
| `/etc/pam.d/common-*` | `pam_sss`, `pam_mkhomedir` (par `pam-auth-update`) | authentification, HBAC, création du `$HOME` |
| configuration `sshd` | `GSSAPIAuthentication yes`, `AuthorizedKeysCommand` | SSO Kerberos, clés SSH de l'annuaire |
| configuration client `ssh` | `GlobalKnownHostsFile` + proxy `sss_ssh_knownhostsproxy` | clés d'hôte vérifiées par l'annuaire |
| `/etc/ipa/` | `default.conf`, `ca.crt` | commande `ipa`, confiance dans la CA du domaine |

```bash
sudo pam-auth-update --enable mkhomedir   # sans effet si déjà actif
grep -l pam_mkhomedir /etc/pam.d/common-session
sudo sshd -T | grep -Ei 'gssapiauth|authorizedkeyscommand'
```

**Étape 3 — Vérifications**

```bash
id alice
getent passwd alice
# lab-adm :
ssh alice@lab-web.lab.local      # changement du mot de passe initial demandé
#   puis dans la session :
pwd; klist; exit
# lab-web :
ls -ld /home/alice
```

**Étape 4 — Inscription reproductible de `lab-db` et `lab-adm`**

Côté serveur (ou depuis toute machine avec un ticket `admin`), l'hôte est
déclaré avec un mot de passe à usage unique :

```bash
kinit admin
ipa host-add lab-db.lab.local --random
#   Random password: Wq3…   (à usage unique)
```

`~/lab28/inscription.sh`, lancé sur le client avec ce mot de passe :

```bash
#!/usr/bin/env bash
# inscription.sh — inscrit la machine dans lab.local (module 28, L28.2)
# Usage : sudo ./inscription.sh   (le mot de passe à usage unique est demandé)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

FQDN="$(hostname -s).lab.local"
read -rsp "Mot de passe à usage unique de $FQDN : " OTP; echo

DEBIAN_FRONTEND=noninteractive apt-get install -y -q freeipa-client \
  sssd-tools ldap-utils krb5-user libsasl2-modules-gssapi-mit >/dev/null
echo 'preserve_hostname: true' > /etc/cloud/cloud.cfg.d/99-fqdn.cfg

ipa-client-install --unattended --domain=lab.local --realm=LAB.LOCAL \
  --server=lab-rhel.lab.local --hostname="$FQDN" \
  --mkhomedir --no-ntp --password="$OTP"

pam-auth-update --enable mkhomedir
sssctl domain-status lab.local | head -1
id alice
```

> [!NOTE]
> **Pourquoi**
>
> Le mot de passe à usage unique (OTP d'inscription) ne sert **qu'à**
> l'inscription de cet hôte précis, et ne donne aucun droit d'administration :
> même intercepté, il ne permet rien d'autre, et il est invalidé dès qu'il a
> servi. C'est la méthode à utiliser en automatisation (cloud-init, Ansible :
> le module `freeipa.ansible_freeipa.ipaclient` fait la même chose), plutôt
> que le mot de passe d'`admin` qui finirait dans une variable ou un journal.

**Étape 5 — L'hôte vu par le serveur**

```bash
ipa host-show lab-db.lab.local
#   Host name: lab-db.lab.local
#   Principal name: host/lab-db.lab.local@LAB.LOCAL
#   SSH public key fingerprint: SHA256:… (ssh-ed25519), SHA256:… (ecdsa-sha2-nistp256)
#   Keytab: True
#   Managed by: lab-db.lab.local
```

```console
mathieu@lab-adm:~$ ssh-keygen -R lab-db.lab.local    # oublie l'ancienne clé apprise
mathieu@lab-adm:~$ ssh lab-db.lab.local
mathieu@lab-db:~$                                     # aucune question sur la clé d'hôte
```

> [!NOTE]
> **Pourquoi**
>
> À l'inscription, le client publie ses **clés d'hôte SSH** dans son entrée.
> Sur toute machine inscrite (dont `lab-adm`), le client SSH les obtient de
> SSSD (`/var/lib/sss/pubconf/known_hosts`) : plus de question « *The
> authenticity of host … can't be established* » à la première connexion, et
> une clé d'hôte qui change sans réinscription est détectée **contre
> l'annuaire** au lieu d'être acceptée par habitude. C'est la fin du TOFU
> (*trust on first use*), l'un des points faibles de SSH dans un parc
> (module 14).

---

### <a id="l28-3"></a>**[L28.3](README.md#l28-3)** — Sudo et accès aux machines, centralisés

*Groupes d'hôtes, règles sudo par groupes, règles HBAC testées avant de
désactiver `allow_all`.*

**Étape 1 — Groupes d'hôtes et règles sudo**

```bash
kinit admin
ipa hostgroup-add serveurs --desc="Serveurs du lab"
ipa hostgroup-add-member serveurs --hosts=lab-web.lab.local --hosts=lab-db.lab.local
ipa hostgroup-add postes-admin --desc="Postes d'administration"
ipa hostgroup-add-member postes-admin --hosts=lab-adm.lab.local

# commandes et groupe de commandes
ipa sudocmd-add '/usr/bin/systemctl restart nginx'
ipa sudocmd-add '/usr/bin/journalctl --no-pager -u nginx'
ipa sudocmdgroup-add nginx-exploitation
ipa sudocmdgroup-add-member nginx-exploitation \
  --sudocmds='/usr/bin/systemctl restart nginx' \
  --sudocmds='/usr/bin/journalctl --no-pager -u nginx'

# admins-lab : tout, sur les serveurs
ipa sudorule-add admins-serveurs --cmdcat=all --runasusercat=all --runasgroupcat=all
ipa sudorule-add-user admins-serveurs --groups=admins-lab
ipa sudorule-add-host admins-serveurs --hostgroups=serveurs

# devs : nginx sur lab-web
ipa sudorule-add devs-nginx
ipa sudorule-add-user devs-nginx --groups=devs
ipa sudorule-add-host devs-nginx --hosts=lab-web.lab.local
ipa sudorule-add-allow-command devs-nginx --sudocmdgroups=nginx-exploitation

# admin : partout, tout
ipa sudorule-add admin-dernier-recours --hostcat=all --cmdcat=all \
  --runasusercat=all --runasgroupcat=all
ipa sudorule-add-user admin-dernier-recours --users=admin
```

> [!WARNING]
> **Piège**
>
> `journalctl -u nginx` lancé par sudo sur un terminal ouvre son **pager**
> (`less`) **en root**. Dans `less`, `!sh` lance un shell : la règle « lire le
> journal de nginx » devient une règle « shell root ». D'où
> `--no-pager` dans la commande autorisée : sudo compare la ligne de commande
> **exacte**, et `journalctl -u nginx` sans l'option ne correspond plus à rien.
> Même famille de piège avec `systemctl status` (pager aussi), `vi`, `less`,
> `man`, `find -exec`, `tar --to-command` : toute commande capable de lancer
> une autre commande est un shell déguisé. GTFOBins en tient l'inventaire.

**Étape 2 — Règles HBAC**

```bash
ipa hbacsvcgroup-show Sudo          # contient sudo et sudo-i

ipa hbacrule-add admins-partout
ipa hbacrule-add-user admins-partout --groups=admins-lab
ipa hbacrule-add-host admins-partout --hostgroups=serveurs --hostgroups=postes-admin
ipa hbacrule-add-service admins-partout --hbacsvcs=sshd --hbacsvcgroups=Sudo

ipa hbacrule-add devs-web
ipa hbacrule-add-user devs-web --groups=devs
ipa hbacrule-add-host devs-web --hosts=lab-web.lab.local
ipa hbacrule-add-service devs-web --hbacsvcs=sshd --hbacsvcgroups=Sudo

ipa hbacrule-add auditeurs-serveurs
ipa hbacrule-add-user auditeurs-serveurs --groups=auditeurs
ipa hbacrule-add-host auditeurs-serveurs --hostgroups=serveurs
ipa hbacrule-add-service auditeurs-serveurs --hbacsvcs=sshd

ipa hbacrule-add admin-partout --hostcat=all --servicecat=all
ipa hbacrule-add-user admin-partout --users=admin
```

> [!NOTE]
> **Pourquoi**
>
> `admins-lab` reçoit le service `sudo` aussi sur `lab-adm`, où il n'a pourtant
> aucune règle sudo : c'est sans effet (sudo refusera faute de règle) et ça
> garde une règle lisible par groupe. À l'inverse, `auditeurs` n'a **pas** le
> service `sudo` : même si une règle sudo les visait par erreur demain, le
> HBAC la bloquerait. Deux contrôles indépendants valent mieux qu'un.
>
> Sans le groupe de services `Sudo` dans les règles, la désactivation
> d'`allow_all` casse sudo pour tous les comptes du domaine avec un message
> trompeur : `sudo: account validation failure, is your account locked?`

**Étape 3 — Tester avant d'appliquer**

```bash
t() { printf '%-8s %-20s %-6s ' "$1" "$2" "$3"
      ipa hbactest --user="$1" --host="$2" --service="$3" | awk '/Access granted/{print $3}'; }
t alice lab-adm.lab.local sshd     # True
t alice lab-db.lab.local  sudo     # True
t bruno lab-web.lab.local sshd     # True
t bruno lab-web.lab.local sudo     # True
t bruno lab-db.lab.local  sshd     # False  (attendu)
t chloe lab-db.lab.local  sshd     # True
t chloe lab-web.lab.local sudo     # False  (attendu)
t chloe lab-adm.lab.local sshd     # False  (attendu)
t admin lab-rhel.lab.local sshd    # True
```

`allow_all` étant encore active, tout répond `True` à ce stade si on ne
l'exclut pas : on teste les **nouvelles règles seules** avec
`--rules=admins-partout --rules=devs-web --rules=auditeurs-serveurs
--rules=admin-partout` ajouté à chaque appel.

**Étape 4 — Désactivation et vérification réelle**

```bash
ipa hbacrule-disable allow_all
# lab-adm, garder une session mathieu ouverte sur chaque client
ssh bruno@lab-web.lab.local true && echo "bruno -> lab-web : OK"
ssh bruno@lab-db.lab.local true  || echo "bruno -> lab-db : refusé (attendu)"
ssh chloe@lab-db.lab.local 'sudo -l'
#   Sorry, user chloe may not run sudo on lab-db.
```

Le refus de bruno sur `lab-db` apparaît côté serveur dans
`/var/log/sssd/sssd_lab.local.log` : `Access denied by HBAC rules`.

**Étape 5 — Ce que voit sudo sur `lab-web`**

```bash
sudo -l -U bruno
#   User bruno may run the following commands on lab-web:
#       (root) /usr/bin/systemctl restart nginx, /usr/bin/journalctl --no-pager -u nginx
sudo grep -rE 'devs|admins-lab' /etc/sudoers /etc/sudoers.d/ || echo "aucune règle locale"
```

> [!NOTE]
> **Pourquoi**
>
> Les règles viennent de l'annuaire par SSSD (`sudoers: files sss` dans
> `nsswitch.conf`) et sont mises en cache : rafraîchissement « intelligent »
> (règles modifiées) toutes les 15 minutes, complet toutes les 6 heures. Une
> nouvelle règle n'est donc pas instantanée sur les clients ;
> `sss_cache -R` force le rechargement des règles sudo sur une machine.

---

### <a id="l28-4"></a>**[L28.4](README.md#l28-4)** — Une sauvegarde sans mot de passe ni clé privée

*Compte de service, keytab, règle sudo à une commande, script et timer
systemd en GSSAPI.*

**Étape 1 — Compte et HBAC**

```bash
kinit admin
ipa user-add svc-sauvegarde --first=Service --last=Sauvegarde \
  --shell=/bin/bash --desc="Compte de service : sauvegarde nginx (L28.4)"
ipa hbacrule-add svc-sauvegarde-web
ipa hbacrule-add-user svc-sauvegarde-web --users=svc-sauvegarde
ipa hbacrule-add-host svc-sauvegarde-web --hosts=lab-web.lab.local
ipa hbacrule-add-service svc-sauvegarde-web --hbacsvcs=sshd --hbacsvcs=sudo
ipa hbactest --user=svc-sauvegarde --host=lab-db.lab.local --service=sshd   # False
```

**Étape 2 — Keytab sur `lab-db`**

```bash
# lab-db
kinit admin
sudo ipa-getkeytab -s lab-rhel.lab.local -p svc-sauvegarde@LAB.LOCAL \
  -k /etc/svc-sauvegarde.keytab
sudo chown svc-sauvegarde: /etc/svc-sauvegarde.keytab
sudo chmod 600 /etc/svc-sauvegarde.keytab
sudo klist -k /etc/svc-sauvegarde.keytab
kdestroy
```

> [!NOTE]
> **Pourquoi**
>
> L'utilisateur a été créé sans mot de passe : il n'avait pas de clés.
> `ipa-getkeytab` lui en **génère** au hasard, que personne ne connaît, et les
> écrit dans le fichier. S'il avait eu un mot de passe, il ne fonctionnerait
> plus (Q28.13). Le keytab devient la seule façon de s'authentifier comme
> `svc-sauvegarde`, et il est sur une seule machine.
>
> Vérifier aussi l'expiration : selon la version et la politique de mots de
> passe, `krbPasswordExpiration` peut s'appliquer aux clés posées ainsi
> (`ipa user-show svc-sauvegarde --all | grep -i expiration`). Le jour où
> elles expirent, `kinit -k` échoue avec `Password has expired`. La parade est
> la rotation planifiée (QO28.8), pas une politique « jamais ».

**Étape 3 — Sudo à une commande sur `lab-web`**

```bash
kinit admin
ipa sudocmd-add '/usr/bin/tar -C /etc -czf - nginx'
ipa sudorule-add sauvegarde-nginx
ipa sudorule-add-user sauvegarde-nginx --users=svc-sauvegarde
ipa sudorule-add-host sauvegarde-nginx --hosts=lab-web.lab.local
ipa sudorule-add-allow-command sauvegarde-nginx \
  --sudocmds='/usr/bin/tar -C /etc -czf - nginx'
ipa sudorule-add-option sauvegarde-nginx --sudooption='!authenticate'
```

**Étape 4 — Le script**

```bash
sudo install -d -o svc-sauvegarde -g svc-sauvegarde -m 750 /srv/sauvegardes/nginx
sudo tee /usr/local/sbin/sauvegarde-nginx.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
# sauvegarde-nginx.sh — rapatrie /etc/nginx de lab-web par SSH Kerberos
# (module 28, L28.4). Lancé par sauvegarde-nginx.service, User=svc-sauvegarde.
set -euo pipefail

KEYTAB=/etc/svc-sauvegarde.keytab
PRINCIPAL=svc-sauvegarde@LAB.LOCAL
CIBLE=lab-web.lab.local
DEST=/srv/sauvegardes/nginx
GARDE=7

# cache de tickets privé, dans le RuntimeDirectory de l'unité
export KRB5CCNAME="FILE:${RUNTIME_DIRECTORY:-/tmp}/krb5cc_sauvegarde"
horo=$(date +%Y%m%d-%H%M%S)
partiel="$DEST/.nginx-$horo.tar.gz.part"
trap 'rm -f "$partiel"; kdestroy -q 2>/dev/null || true' EXIT

kinit -k -t "$KEYTAB" "$PRINCIPAL"

ssh -o BatchMode=yes \
    -o GSSAPIAuthentication=yes \
    -o PreferredAuthentications=gssapi-with-mic \
    -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=yes \
    "svc-sauvegarde@$CIBLE" \
    sudo -n /usr/bin/tar -C /etc -czf - nginx > "$partiel"

gzip -t "$partiel"                    # archive complète et lisible ?
mv "$partiel" "$DEST/nginx-$horo.tar.gz"

# rotation : on garde les $GARDE plus récentes
ls -1t "$DEST"/nginx-*.tar.gz | tail -n +"$((GARDE + 1))" | xargs -r rm -f --
echo "sauvegarde OK : $DEST/nginx-$horo.tar.gz ($(stat -c %s "$DEST/nginx-$horo.tar.gz") octets)"
EOF
sudo chmod 755 /usr/local/sbin/sauvegarde-nginx.sh
```

> [!NOTE]
> **Pourquoi**
>
> * **`KRB5CCNAME` explicite** : un service systemd n'a pas de session de
>   connexion, et les caches `KEYRING:persistent` ou `KCM:` se comportent mal
>   hors session. Un fichier dans le `RuntimeDirectory` de l'unité (créé à
>   l'exécution en `0700`, supprimé à l'arrêt) est privé et éphémère.
> * **`PreferredAuthentications=gssapi-with-mic` + `BatchMode=yes`** : si
>   Kerberos échoue, le script échoue tout de suite au lieu d'attendre un mot
>   de passe que personne ne tapera.
> * **`UserKnownHostsFile=/dev/null` + `StrictHostKeyChecking=yes`** : le
>   compte n'a pas de `$HOME` sur `lab-db` (aucune connexion PAM, donc pas de
>   `mkhomedir`). La clé d'hôte de `lab-web` est vérifiée par le fichier
>   global que SSSD alimente depuis l'annuaire (L28.2, étape 5) : vérification
>   stricte sans fichier personnel.
> * **`.part` puis `mv`** : une archive interrompue n'a jamais le nom d'une
>   archive valide ; `gzip -t` vérifie avant de la promouvoir. Le `trap`
>   nettoie dans tous les cas.
> * **La commande distante** est exactement celle de la règle sudo, mot pour
>   mot : sudo compare les arguments.

**Étape 5 — Service et timer**

```ini
# /etc/systemd/system/sauvegarde-nginx.service
[Unit]
Description=Sauvegarde de /etc/nginx de lab-web (Kerberos)
Wants=network-online.target
After=network-online.target sssd.service

[Service]
Type=oneshot
User=svc-sauvegarde
Group=svc-sauvegarde
RuntimeDirectory=sauvegarde-nginx
RuntimeDirectoryMode=0700
ExecStart=/usr/local/sbin/sauvegarde-nginx.sh
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/srv/sauvegardes/nginx
PrivateTmp=yes
```

```ini
# /etc/systemd/system/sauvegarde-nginx.timer
[Unit]
Description=Sauvegarde quotidienne de /etc/nginx

[Timer]
OnCalendar=*-*-* 02:30
RandomizedDelaySec=15min
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now sauvegarde-nginx.timer
sudo systemctl start sauvegarde-nginx.service
journalctl -u sauvegarde-nginx.service -n 5 --no-pager
ls -l /srv/sauvegardes/nginx/
# lab-web
sudo journalctl -u ssh --since -10min | grep svc-sauvegarde
#   Accepted gssapi-with-mic for svc-sauvegarde from 10.10.10.12 port 51122 ssh2
```

> [!NOTE]
> **Pourquoi**
>
> `User=` d'un service systemd ne passe **pas** par PAM : aucun contrôle HBAC
> sur `lab-db` (le compte n'y a d'ailleurs aucune règle), pas de
> `mkhomedir`. C'est voulu : le HBAC protège les **connexions**, et c'est sur
> `lab-web` que le compte se connecte. `After=sssd.service` évite que systemd
> cherche à résoudre `svc-sauvegarde` avant que SSSD ne réponde, ce qui
> donnerait `status=217/USER` au démarrage de la machine.

**Étape 6 — Fin de l'ancienne clé**

```bash
# lab-web : empreinte de l'ancienne clé
ssh-keygen -lf ~/lab28/ancienne-cle/id_sauvegarde.pub
#   256 SHA256:Xy… sauvegarde-legacy (ED25519)
# depuis lab-adm, sur chaque machine : où est-elle autorisée ?
for h in lab-web lab-db lab-adm lab-rhel; do
  echo "== $h"
  ssh "$h.lab.local" 'sudo sh -c "for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
      [ -f \"\$f\" ] && ssh-keygen -lf \"\$f\" | sed \"s|^|\$f: |\"; done"' | grep -F 'SHA256:Xy' || true
done
```

On retire la ligne dans chaque fichier trouvé
(`sed -i '/sauvegarde-legacy/d' …`, après avoir vérifié qu'elle ne sert à
rien d'autre), on détruit la paire de clés partout où elle traîne
(`shred -u ~/lab28/ancienne-cle/id_sauvegarde*` sur `lab-web`), et on
relance la recherche, qui ne doit plus rien trouver. On
vérifie aussi que `sshd -T | grep authorizedkeysfile` ne désigne pas
d'autre emplacement, et que la clé n'a pas été publiée dans l'annuaire
(`ipa user-find --all | grep -i 'SHA256:Xy'`).

> [!TIP]
> **Critère de succès**
>
> `check_M28_04.sh` vérifie sur `lab-db` le keytab (propriétaire, droits,
> principal, `kinit` possible), le timer et une archive du jour valide ; sur
> `lab-web`, la règle sudo du compte de service, la trace de la connexion
> GSSAPI, et la disparition de l'ancienne clé.

---

## 28.7 Break & Fix

### <a id="bf28-1"></a>**[BF28.1](README.md#bf28-1)** — « Plus personne ne peut se connecter sur le frontal »

**Démarche de diagnostic**

```bash
# 1. ce que dit SSSD de son domaine
sudo sssctl domain-status lab.local
#   Online status: Offline           <- premier indice
# 2. pourquoi hors ligne ? journal du domaine et du processus LDAP
sudo grep -iE 'skew|offline|ldap_child' /var/log/sssd/sssd_lab.local.log | tail -5
sudo tail -5 /var/log/sssd/ldap_child.log
#   Failed to initialize credentials using keytab [MEMORY:/etc/krb5.keytab]:
#   Clock skew too great.
# 3. l'heure, enfin (à comparer avec « date » sur lab-db)
date
timedatectl
systemctl status chrony --no-pager
```

**Cause racine** : l'horloge de `lab-web` a 12 minutes d'avance, et `chrony`
est arrêté et désactivé. Au-delà de 5 minutes d'écart, le KDC refuse les
demandes de `lab-web` : SSSD n'obtient plus le TGT de l'hôte qui lui sert à
s'authentifier auprès de LDAP, et passe **hors ligne**. Hors ligne, il
répond encore à `id` depuis son cache et laisse entrer, par empreinte de mot
de passe, ceux qui s'étaient déjà connectés sur cette machine (sans ticket :
pas de KDC joignable à ses yeux). Les autres sont refusés.

**Correctif**

```bash
sudo timedatectl set-ntp true
sudo systemctl enable --now chrony
sudo chronyc makestep          # saute à l'heure juste au lieu de dériver
chronyc tracking | grep -E 'System time|Leap'
sudo pkill -USR2 sssd          # « repasse en ligne » sans attendre
sudo sssctl domain-status lab.local | head -1    # Online
```

**Prévention** : `chrony` activé et **supervisé** (l'exportateur Prometheus
du module 26 expose `node_timex_offset_seconds` : alerte au-delà de
1 seconde, bien avant les 300 s de Kerberos), un contrôle de l'état de SSSD
(`sssctl domain-status` en ligne), et la configuration de la synchronisation
horaire tenue par Ansible (module 23) pour qu'un service désactivé à la main
soit réactivé au prochain passage.

> [!NOTE]
> **Pourquoi**
>
> Le symptôme est trompeur parce que tout **semble** marcher : `id` répond,
> certains utilisateurs entrent, `lab-db` va bien, l'interface web est verte.
> C'est la signature du **mode hors ligne** de SSSD. Les indices qui y mènent :
> une session ouverte sans ticket (`klist` vide), et la règle
> « les anciens entrent, les nouveaux non ».
>
> Pourquoi `chronyc makestep` : par défaut, chrony corrige une dérive en
> **ralentissant** ou accélérant l'horloge (slew) pour ne pas faire reculer le
> temps sous les pieds des applications ; il ne fait un saut (step) qu'au
> démarrage (`makestep 1 3` : si l'écart dépasse 1 s pendant les 3 premières
> mesures). Pour 12 minutes, la dérive prendrait des heures. `makestep` force
> le saut, ce qui est acceptable ici parce que l'heure **avance** et revient
> en arrière d'un coup : à faire en connaissance de cause sur un serveur de
> base de données.
>
> `SIGUSR2` demande à SSSD de se considérer en ligne et de retenter tout de
> suite ; sans lui, il réessaie de lui-même au bout de quelques dizaines de
> secondes à quelques minutes.

> [!WARNING]
> **Piège**
>
> Corriger avec `date -s` à la main, sans réactiver chrony : la machine repart
> en dérive (une VM dérive vite quand l'hôte est chargé ou après une
> suspension) et la panne revient dans quelques semaines. L'autre fausse piste
> classique : augmenter `clockskew` dans `krb5.conf`, qui affaiblit la
> protection contre le rejeu pour masquer une horloge fausse qui cassera aussi
> TLS, les journaux et les sauvegardes.

---

### <a id="bf28-2"></a>**[BF28.2](README.md#bf28-2)** — « Les comptes du domaine n'existent plus sur lab-db »

**Démarche de diagnostic**

```bash
id alice                                # no such user
systemctl status sssd --no-pager        # failed
sudo journalctl -u sssd -b --no-pager | tail -5
#   File ownership and permissions check failed. Expected root:root and 0600.
ls -l /etc/sssd/sssd.conf               # -rw-r--r-- : modification n° 1
sudo sssctl config-check
grep -E '^(passwd|group|shadow|sudoers)' /etc/nsswitch.conf
#   passwd: files systemd                <- modification n° 2 : sss a disparu
#   group:  files systemd
#   sudoers: files                       <- modification n° 3
diff <(sudo cat /root/.breakfix-backup/M28_02.nsswitch.conf) /etc/nsswitch.conf
```

**Cause racine** : trois modifications cumulées. `sssd.conf` en `0644`
empêche SSSD de démarrer ; `sss` retiré de `passwd`, `group` (et `shadow`)
fait que la glibc ne demanderait plus rien à SSSD même s'il tournait ; `sss`
retiré de `sudoers` ferait disparaître silencieusement les règles sudo du
domaine une fois les deux premières corrigées. Le timer de sauvegarde
échoue parce que systemd ne peut plus résoudre `svc-sauvegarde`
(`status=217/USER`).

**Correctif**

```bash
sudo chown root:root /etc/sssd/sssd.conf
sudo chmod 600 /etc/sssd/sssd.conf
sudo sssctl config-check
sudo sed -i -E '/^(passwd|group|shadow|netgroup|sudoers|services|automount):/{/\bsss\b/!s/$/ sss/}' \
  /etc/nsswitch.conf
grep -E '^(passwd|group|shadow|sudoers)' /etc/nsswitch.conf
sudo systemctl restart sssd
id alice
sudo -l -U alice | tail -2              # règles du domaine de retour
sudo systemctl start sauvegarde-nginx.service && ls -lt /srv/sauvegardes/nginx | head -2
```

**Prévention** : un contrôle qui aurait parlé avant les utilisateurs :
supervision de `systemctl is-active sssd` et d'une résolution
`getent passwd svc-sauvegarde` sur chaque client ; `sssctl config-check`
dans la procédure de modification ; `nsswitch.conf` et `sssd.conf` tenus par
la gestion de configuration avec `mode: "0600"`. Le timer en échec aurait dû
alerter aussi : `OnFailure=` vers une unité de notification (module 17).

> [!NOTE]
> **Pourquoi**
>
> Le diagnostic doit séparer les **deux chemins** : NSS (la glibc lit
> `nsswitch.conf` puis charge `libnss_sss`, qui parle au démon) et le démon
> lui-même. Corriger seulement les droits relance SSSD, `sssctl user-show
> alice` répond… et `id alice` échoue toujours, parce que la glibc ne demande
> plus rien à SSSD. Corriger seulement `nsswitch.conf` laisse une glibc qui
> appelle un démon absent. D'où l'énoncé : « il y en a plus d'une ».
>
> La troisième modification est la plus perverse parce que rien ne la
> révèle : `id alice` marche, la connexion marche, seules les règles sudo de
> l'annuaire ont disparu. On ne la trouve qu'en **comparant** le fichier à
> une référence (sauvegarde, dépôt Ansible, autre machine du même rôle), ce
> qui est la vraie leçon : on ne diagnostique pas une configuration par
> relecture, on la compare.

---

### <a id="bf28-3"></a>**[BF28.3](README.md#bf28-3)** — « Elle a été retirée du groupe, et elle fait toujours sudo »

**Démarche de diagnostic**

```bash
# lab-rhel : la source de vérité est à jour
ipa group-show admins-lab | grep 'Member users'     # plus d'alice
# lab-web : ce que SSSD croit
sudo sssctl user-show alice | grep -iE 'expir|cache'
#   Cache entry expiration time: <demain>
sudo grep -nE 'timeout|refresh' /etc/sssd/sssd.conf
#   entry_cache_timeout = 86400
#   ldap_sudo_smart_refresh_interval = 86400
#   ldap_sudo_full_refresh_interval = 86400
# et la session d'alice
loginctl list-sessions | grep alice
sudo cat /proc/"$(pgrep -u alice -n bash)"/status | grep Groups
```

**Cause racine** : deux couches de mémoire distinctes.

1. Un « réglage de performance » a passé la durée de validité des entrées
   SSSD à 24 heures. SSSD ne redemande les groupes d'alice à l'annuaire
   qu'à l'expiration de l'entrée : jusque-là, pour `id`, pour `sudo -l -U`
   lancé par root et pour le répondeur sudo, alice est toujours dans
   `admins-lab`.
2. La session ouverte avant le retrait garde dans le **noyau** la liste de
   groupes posée à sa connexion (Q28.14), et sudo s'appuie par défaut sur
   cette liste pour évaluer les règles qui visent un groupe. Aucun cache
   vidé ne la change.

**Correctif immédiat**

```bash
sudo sss_cache -u alice              # sur chaque client (ou -E : tout)
sudo -l -U alice                     # plus de (ALL) ALL
sudo loginctl terminate-user alice   # ferme les sessions ouvertes
```

**Correctif de configuration** : délai maximal de 5 minutes

```ini
# /etc/sssd/sssd.conf, section [domain/lab.local]
entry_cache_timeout = 300
refresh_expired_interval = 240
# les intervalles sudo reviennent à leurs valeurs par défaut :
# lignes ldap_sudo_*_refresh_interval supprimées
```

```bash
sudo chmod 600 /etc/sssd/sssd.conf && sudo systemctl restart sssd
```

**Prévention** : la procédure de retrait de droits (D28) vide les caches et
termine les sessions sur tous les clients ; toute modification de
`sssd.conf` passe par revue (les délais de cache sont une décision de
sécurité, pas seulement de performance).

> [!NOTE]
> **Pourquoi**
>
> Chiffrer le compromis :
>
> * **Sécurité** : 5 minutes au plus entre un retrait de droits dans
>   l'annuaire et son effet sur une **nouvelle** demande, contre 24 h. Le cache
>   mémoire de NSS (`memcache_timeout`, 300 s par défaut) borne `id` au même
>   ordre de grandeur. Les sessions déjà ouvertes restent hors de portée de
>   toute configuration : seul un `terminate-user` les règle.
> * **Charge** : chaque client redemande les entrées actives toutes les
>   5 minutes au lieu de toutes les 90 (défaut) ou 1 440 (réglage cassé).
>   Ordre de grandeur pour 1 000 clients avec 20 comptes actifs chacun :
>   20 000 rafraîchissements / 300 s ≈ 70 requêtes LDAP par seconde,
>   supportable par un serveur 389-DS, à surveiller avec des réplicas.
>   `refresh_expired_interval` fait ces mises à jour en tâche de fond, pour
>   que l'utilisateur ne paie pas l'aller-retour.
> * **Mode hors ligne** : intact. Une entrée expirée reste servie quand le
>   serveur est injoignable ; l'expiration décide seulement **quand**
>   redemander, pas quand oublier.
>
> Les intervalles `ldap_sudo_*` ne jouent pas ici (la règle sudo n'a pas
> changé, seule l'appartenance a changé), mais ils retardent l'arrivée d'une
> règle **nouvelle ou modifiée** : 15 min et 6 h par défaut, à ne pas
> allonger.

---

## 28.8 Défi du module

<a id="d28"></a>**[D28](README.md#d28) — Arrivée et départ d'un administrateur, sans rien oublier**

*Livrable attendu : `arrivee.sh`, `depart.sh`, `runbook.md` et la trace de la
preuve sur `eve`.*

```bash
#!/usr/bin/env bash
# arrivee.sh — fait arriver un administrateur dans lab.local (module 28, D28)
# Usage : arrivee.sh <login> "<Prénom Nom>" <groupe> <fichier.pub>
# Prérequis : ticket admin (kinit admin). Aucun mot de passe en argument.
set -euo pipefail

JOURNAL="${JOURNAL:-$HOME/lab28/defi/journal.log}"
log() { printf '%s arrivee %s\n' "$(date -Is)" "$*" | tee -a "$JOURNAL" >&2; }
die() { log "ÉCHEC : $*"; exit 1; }
usage() { sed -n '2,4s/^# \{0,1\}//p' "$0"; }

[ "${1:-}" = --help ] && { usage; exit 0; }
[ $# -eq 4 ] || { usage >&2; exit 2; }
login=$1 nomcomplet=$2 groupe=$3 cle=$4
prenom=${nomcomplet%% *} nom=${nomcomplet#* }

[[ $login =~ ^[a-z][a-z0-9-]{1,31}$ ]] || die "login invalide : $login"
[ -r "$cle" ] && ssh-keygen -lf "$cle" >/dev/null 2>&1 || die "clé illisible : $cle"
klist -s || die "pas de ticket Kerberos : kinit admin"
mkdir -p "$(dirname "$JOURNAL")"

# accès attendus par groupe : machine -> accès sshd attendu
declare -A ATTENDU
case $groupe in
  admins-lab) ATTENDU=([lab-adm.lab.local]=True [lab-web.lab.local]=True [lab-db.lab.local]=True) ;;
  devs)       ATTENDU=([lab-adm.lab.local]=False [lab-web.lab.local]=True [lab-db.lab.local]=False) ;;
  auditeurs)  ATTENDU=([lab-adm.lab.local]=False [lab-web.lab.local]=True [lab-db.lab.local]=True) ;;
  *) die "groupe inconnu : $groupe (admins-lab, devs, auditeurs)" ;;
esac

ipa group-show "$groupe" >/dev/null 2>&1 || die "le groupe $groupe n'existe pas"
if ipa user-show "$login" >/dev/null 2>&1; then
  die "$login existe déjà : rien n'est modifié"
fi

sortie=$(ipa user-add "$login" --first="$prenom" --last="$nom" --random \
           --sshpubkey="$(cat "$cle")") || die "création de $login"
mdp=$(awk '/Random password/{print $3}' <<<"$sortie")
log "compte $login créé (clé $(ssh-keygen -lf "$cle" | awk '{print $2}'))"

ipa group-add-member "$groupe" --users="$login" >/dev/null || die "ajout à $groupe"
log "$login ajouté à $groupe"

erreurs=0
for hote in "${!ATTENDU[@]}"; do
  obtenu=$(ipa hbactest --user="$login" --host="$hote" --service=sshd |
             awk '/Access granted/{print $3}')
  if [ "$obtenu" = "${ATTENDU[$hote]}" ]; then
    log "hbactest $hote : $obtenu (attendu)"
  else
    log "hbactest $hote : $obtenu, attendu ${ATTENDU[$hote]}"; erreurs=$((erreurs + 1))
  fi
done

# le mot de passe : à l'écran, une fois, jamais dans le journal
printf '\nMot de passe initial de %s (à changer à la première connexion) : %s\n\n' \
  "$login" "$mdp" > /dev/tty
[ "$erreurs" -eq 0 ] || die "$erreurs accès non conformes : vérifier les règles HBAC"
log "arrivée de $login terminée"
```

```bash
#!/usr/bin/env bash
# depart.sh — fait partir un administrateur de lab.local (module 28, D28)
# Usage : depart.sh <login>
# Prérequis : ticket admin (kinit admin) ; admin a sudo sur toutes les machines.
set -euo pipefail

JOURNAL="${JOURNAL:-$HOME/lab28/defi/journal.log}"
log() { printf '%s depart %s\n' "$(date -Is)" "$*" | tee -a "$JOURNAL" >&2; }
die() { log "ÉCHEC : $*"; exit 1; }
[ "${1:-}" = --help ] && { sed -n '2,4s/^# \{0,1\}//p' "$0"; exit 0; }
[ $# -eq 1 ] || { echo "usage : $0 <login>" >&2; exit 2; }
login=$1
[ "$login" != admin ] || die "on ne fait pas partir le compte de dernier recours"
klist -s || die "pas de ticket Kerberos : kinit admin"
ipa user-show "$login" >/dev/null 2>&1 || die "$login inconnu"
mkdir -p "$(dirname "$JOURNAL")"
echec=0

# 1. relever les traces AVANT d'effacer
fps=$(ipa user-show "$login" --all --raw | awk '/sshpubkeyfp:/{print $2}')
groupes=$(ipa user-show "$login" --raw --all |
            sed -n 's/^ *memberof: cn=\([^,]*\),cn=groups,.*/\1/p' | grep -vx ipausers || true)
log "empreintes : ${fps:-aucune} ; groupes : ${groupes:-aucun}"

# 2. bloquer les nouvelles authentifications (désactiver, pas supprimer)
ipa user-disable "$login" >/dev/null 2>&1 || log "déjà désactivé"
log "$login désactivé"

# 3. retirer les droits portés par l'annuaire
ipa user-mod "$login" --sshpubkey= >/dev/null 2>&1 || true
for g in $groupes; do
  ipa group-remove-member "$g" --users="$login" >/dev/null && log "retiré de $g" ||
    { log "retrait de $g impossible"; echec=1; }
done
for r in $(ipa sudorule-find --users="$login" --pkey-only --raw | awk '/cn:/{print $2}'); do
  log "ATTENTION : règle sudo nominative $r"; echec=1
done
for r in $(ipa hbacrule-find --users="$login" --pkey-only --raw | awk '/cn:/{print $2}'); do
  log "ATTENTION : règle HBAC nominative $r"; echec=1
done

# 4. sur chaque machine du domaine : couper, purger les caches, chercher les traces
# script exécuté à distance (root via sudo) ; $1 = login, $2 = empreintes séparées par des virgules
read -r -d '' DISTANT <<'FIN' || true
set -u
login=$1; IFS=, read -ra fps <<<"${2:-}"
loginctl terminate-user "$login" 2>/dev/null || true
pkill -KILL -u "$login" 2>/dev/null || true
sss_cache -E 2>/dev/null || true
pgrep -u "$login" >/dev/null && echo "TRACE processus restants"
for f in /var/spool/cron/crontabs/"$login" /var/spool/cron/"$login"; do
  [ -e "$f" ] && echo "TRACE crontab $f"
done
grep -rlw -- "$login" /etc/sudoers.d/ 2>/dev/null | sed 's/^/TRACE sudoers /'
grep -q -- "^$login:" /etc/passwd && echo "TRACE compte local $login"
for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
  [ -f "$f" ] || continue
  for fp in "${fps[@]}"; do
    ssh-keygen -lf "$f" 2>/dev/null | grep -qF "$fp" && echo "TRACE clé $fp dans $f"
  done
done
exit 0
FIN
fps_csv=$(paste -sd, <<<"$fps")   # SHA256:… sans espace : passe tel quel par ssh

hotes=$(ipa host-find --sizelimit=0 --pkey-only --raw | awk '/fqdn:/{print $2}')
for h in $hotes; do
  if ! sortie=$(ssh -o BatchMode=yes -o ConnectTimeout=5 \
        -o PreferredAuthentications=gssapi-with-mic "admin@$h" \
        sudo -n bash -s -- "$login" "$fps_csv" <<<"$DISTANT" 2>&1); then
    log "$h : injoignable ou refus ($sortie)"; echec=1; continue
  fi
  if grep -q '^TRACE' <<<"$sortie"; then
    grep '^TRACE' <<<"$sortie" | while read -r l; do log "$h : $l"; done
    echec=1
  else
    log "$h : sessions coupées, cache purgé, aucune trace"
  fi
done

[ "$echec" -eq 0 ] && log "départ de $login terminé" ||
  { log "départ de $login terminé AVEC des points à traiter (voir ci-dessus)"; exit 1; }
```

> [!NOTE]
> **Pourquoi**
>
> Les choix qui comptent dans ces deux scripts :
>
> * **Désactiver, pas supprimer.** Un compte supprimé libère son UID, qu'un
>   futur compte pourrait recevoir et avec lui la propriété des anciens
>   fichiers. Désactivé (ou conservé par `user-del --preserve`), il reste
>   attribuable dans les journaux.
> * **Relever avant d'effacer.** Les empreintes des clés SSH servent à
>   chercher leurs copies dans les `authorized_keys` locaux, que l'annuaire
>   ne voit pas ; une fois retirées de l'annuaire, on ne les connaîtrait plus.
> * **Agir partout avec l'identité d'`admin`, en Kerberos.** Le script se
>   connecte à chaque hôte en GSSAPI avec le ticket de l'opérateur : aucun
>   secret stocké, et la liste des hôtes vient de l'annuaire, donc une
>   nouvelle machine est couverte sans modifier le script.
> * **Ne jamais s'arrêter au premier hôte injoignable**, mais finir en échec
>   pour qu'un départ incomplet ne passe pas pour réussi.
> * **Le mot de passe initial va sur `/dev/tty`**, ni dans le journal, ni sur
>   stdout (qui pourrait être redirigée vers un fichier ou un ticket).
> * **Les règles nominatives** (sudo ou HBAC qui citent la personne) sont
>   signalées plutôt que modifiées : elles trahissent une politique mal
>   construite qu'il faut corriger à la main.
>
> Le runbook doit lister ce qui reste **hors de portée** des scripts :
> secrets partagés à changer (Directory Manager, `admin`, comptes root
> locaux, coffres, jetons de CI), accès hors domaine (forge, supervision,
> Proxmox, cloud), keytabs qu'il a pu copier, et ses tickets encore valides
> jusqu'à 24 h. Le retour arrière d'un départ par erreur :
> `ipa user-enable`, réajout aux groupes depuis le journal, republication de
> la clé.

**Preuve attendue**

```console
$ ~/lab28/defi/arrivee.sh eve "Eve Durand" devs ~/lab28/cles/eve.pub
2026-11-09T14:02:11+01:00 arrivee compte eve créé (clé SHA256:k9…)
2026-11-09T14:02:12+01:00 arrivee eve ajouté à devs
2026-11-09T14:02:13+01:00 arrivee hbactest lab-web.lab.local : True (attendu)
2026-11-09T14:02:13+01:00 arrivee hbactest lab-adm.lab.local : False (attendu)
2026-11-09T14:02:14+01:00 arrivee hbactest lab-db.lab.local : False (attendu)

Mot de passe initial de eve (à changer à la première connexion) : 7Hq…

$ ssh -i ~/lab28/cles/eve eve@lab-web.lab.local 'tmux new -d -s long "sleep 3600"'
$ ~/lab28/defi/depart.sh eve
…  depart lab-web.lab.local : sessions coupées, cache purgé, aucune trace
…  depart départ de eve terminé
$ ssh lab-web.lab.local 'pgrep -u eve || echo "aucun processus"'
aucun processus
$ ssh -i ~/lab28/cles/eve -o BatchMode=yes eve@lab-web.lab.local true
eve@lab-web.lab.local: Permission denied (publickey,gssapi-with-mic,keyboard-interactive).
$ ipa user-show eve | grep -i disabled
  Account disabled: True
```

<!-- nav:début -->
---

[← Projet B](../../projets/P2-factura-devops/corrige.md) · [Énoncé](README.md) · [Module 29 →](../29-haute-disponibilite/corrige.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
