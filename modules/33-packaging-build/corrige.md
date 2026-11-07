<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Partie V — Expertise système › **Module 33** · corrigé  
[← Module 32](../32-fs-avances/corrige.md) · [Énoncé](README.md) · [Projet C →](../../projets/P3-astreinte/corrige.md)

> [!TIP]
> Règle des 20 minutes : ouvre un corrigé après vingt minutes de recherche honnête, pas avant. Chaque identifiant renvoie à son énoncé.
<!-- nav:fin -->

# Module 33 — Corrigé

## 33.3 Quiz — QCM

<a id="q33-1"></a>**[Q33.1](README.md#q33-1)** — *Préparer les fichiers d'un paquet sans toucher au système.*

**Réponse : a)** `make PREFIX=/usr DESTDIR="$PWD/transit" install`.

> [!NOTE]
> **Pourquoi**
>
> `PREFIX=/usr` : le programme est compilé et configuré pour vivre dans `/usr`
> (il cherchera sa configuration dans `/etc`, ses données dans `/usr/share`).
> `DESTDIR` : au moment de la copie, tous les chemins sont **préfixés** par la
> racine de transit ; rien n'est écrit dans le vrai `/usr`, et l'on obtient
> l'arborescence exacte que le paquet installera. Ni `sudo` ni root ne sont
> nécessaires. C'est ce que font `dh_auto_install` (avec
> `DESTDIR=debian/<paquet>`) et `%make_install` (avec `DESTDIR=%{buildroot}`).

---

<a id="q33-2"></a>**[Q33.2](README.md#q33-2)** — *`PREFIX` pointé sur le répertoire de transit.*

**Réponse : c)** les chemins de transit seraient compilés dans le programme.

> [!NOTE]
> **Pourquoi**
>
> `PREFIX` n'est pas seulement une destination de copie : beaucoup de
> programmes **compilent** des chemins à partir de lui (ici
> `-DCONFIG="$(SYSCONFDIR)/lab33-sante.conf"`, et l'unité systemd reçoit
> `ExecStart=$(BINDIR)/lab33-sante`). Avec `PREFIX=/home/mathieu/transit`, le
> programme installé chercherait sa configuration dans
> `/home/mathieu/transit/etc/…` sur tous les serveurs. `DESTDIR` existe
> précisément pour séparer « où le programme croira être » de « où on copie les
> fichiers maintenant ». L33.2 montre une variante plus sournoise : un `PREFIX`
> différent entre la compilation et l'installation.

---

<a id="q33-3"></a>**[Q33.3](README.md#q33-3)** — *`3ubuntu2` dans `1:2.4.1-3ubuntu2`.*

**Réponse : d)** la révision de l'empaquetage.

> [!NOTE]
> **Pourquoi**
>
> Une version Debian se lit `[époque:]version_amont[-révision_debian]`. La
> partie après le **dernier** tiret est la révision : `3` = troisième version de
> l'empaquetage Debian de la 2.4.1, `ubuntu2` = deuxième modification
> d'Ubuntu par-dessus. Quand Debian publie `-4`, Ubuntu reprend `-4ubuntu1`.
> Le suffixe permet à chaque distribution dérivée d'ordonner ses versions sans
> collision avec celles de Debian. Un paquet maison suit souvent la même
> logique (`1.1-1lab1`).

---

<a id="q33-4"></a>**[Q33.4](README.md#q33-4)** — *L'époque.*

**Réponse : a)** forcer l'ordre quand le schéma de version change.

> [!NOTE]
> **Pourquoi**
>
> Si l'amont passe de la version `2024.11` à `5.0`, `5.0` paraît **plus
> ancienne** pour dpkg et rpm : les mises à jour ne se feraient plus.
> L'époque, comparée en premier, règle le problème : `1:5.0` > `2024.11`
> (époque implicite 0). Elle est définitive : une fois posée, elle ne peut plus
> être retirée sans que la version suivante paraisse plus ancienne. On
> l'utilise le moins possible, et elle n'apparaît pas dans les noms de
> fichiers des paquets.

---

<a id="q33-5"></a>**[Q33.5](README.md#q33-5)** — *`dh $@` dans `debian/rules`.*

**Réponse : c)** la séquence standard de debhelper, chaque étape surchargeable.

> [!NOTE]
> **Pourquoi**
>
> `debian/rules` est un `Makefile`. La règle générique `%:` attrape toutes les
> cibles (`build`, `binary`, `clean`…) et appelle `dh` avec ce nom ; `dh`
> déroule alors une liste de commandes : `dh_auto_configure`, `dh_auto_build`,
> `dh_auto_test`, `dh_auto_install`, `dh_installsystemd`,
> `dh_installsysusers`, `dh_installman`, `dh_strip`, `dh_compress`,
> `dh_shlibdeps`, `dh_gencontrol`, `dh_builddeb`… Une cible
> `override_dh_auto_build:` remplace une étape (L33.2) ; `execute_after_…`
> ajoute après. La plupart des paquets tiennent en quelques lignes de
> `rules` parce que les `dh_auto_*` savent piloter `make`, autotools, CMake,
> Meson, Python…

---

<a id="q33-6"></a>**[Q33.6](README.md#q33-6)** — *La dépendance sur `libc6` déduite automatiquement.*

**Réponse : d)** `dh_shlibdeps` remplit `${shlibs:Depends}`.

> [!NOTE]
> **Pourquoi**
>
> `dh_shlibdeps` appelle `dpkg-shlibdeps` sur chaque binaire : il lit les
> bibliothèques liées (`NEEDED` dans l'en-tête ELF), trouve le paquet qui les
> fournit et la version minimale nécessaire d'après les symboles utilisés
> (fichiers `symbols` de chaque bibliothèque), et produit la variable
> `${shlibs:Depends}`, que `debian/control` référence. Côté RPM, le
> générateur automatique de dépendances fait la même chose (`Requires:
> libc.so.6(GLIBC_2.34)(64bit)`, E33.8). On n'écrit à la main que les
> dépendances que l'outil ne peut pas deviner (un programme appelé par un
> script, un service réseau…).

---

<a id="q33-7"></a>**[Q33.7](README.md#q33-7)** — *`conffile` modifié des deux côtés.*

**Réponse : b)** dpkg demande quoi faire.

> [!NOTE]
> **Pourquoi**
>
> Pour chaque `conffile`, dpkg compare trois versions : celle que le paquet
> avait installée (empreinte gardée dans `/var/lib/dpkg/status`), celle du
> disque, celle du nouveau paquet. Modifiée localement **et** dans le paquet,
> il pose la question (garder, remplacer, voir la différence, ouvrir un shell).
> En automatique, on répond d'avance : `--force-confdef` (prendre le choix par
> défaut quand il existe) et `--force-confold` (garder le fichier local) ; la
> nouvelle version est alors déposée en `.dpkg-dist` pour comparaison. Tout
> fichier installé sous `/etc` par debhelper est automatiquement un
> `conffile`.

---

<a id="q33-8"></a>**[Q33.8](README.md#q33-8)** — *`%config(noreplace)`.*

**Réponse : c)** le fichier local est gardé, la nouvelle version écrite en `.rpmnew`.

> [!NOTE]
> **Pourquoi**
>
> RPM ne pose jamais de question : il choisit. Avec `%config(noreplace)`, un
> fichier modifié localement est gardé, et la version du nouveau paquet est
> écrite à côté en `.rpmnew` ; c'est à l'administrateur de fusionner. Avec
> `%config` simple, c'est l'inverse : le fichier est remplacé et l'ancien
> sauvegardé en `.rpmsave`. `noreplace` est presque toujours le bon choix pour
> une configuration. Un outil comme `rpmconf` aide à traiter les `.rpmnew`
> après une mise à jour.

---

<a id="q33-9"></a>**[Q33.9](README.md#q33-9)** — *Pourquoi `apt-key add` est déprécié.*

**Réponse : a)** une clé ajoutée était approuvée pour **tous** les dépôts.

> [!NOTE]
> **Pourquoi**
>
> `apt-key add` ajoutait la clé au trousseau global
> (`/etc/apt/trusted.gpg`), dont toutes les clés peuvent signer **n'importe
> quel** dépôt configuré. La clé d'un petit dépôt tiers devenait capable de
> valider un faux `openssh-server` servi par un miroir compromis. Avec
> `Signed-By:`, chaque dépôt n'accepte que la ou les clés désignées, rangées
> dans `/etc/apt/keyrings/` (ou `/usr/share/keyrings/` quand c'est un paquet
> qui les installe). `apt-key` a été retiré d'apt 2.9 (Ubuntu 24.10 et Debian
> 13) ; Ubuntu 24.04 l'affiche comme déprécié.

---

<a id="q33-10"></a>**[Q33.10](README.md#q33-10)** — *Ce qu'on signe dans un dépôt apt.*

**Réponse : d)** le fichier `Release`, qui fixe les empreintes des index, qui fixent celles des `.deb`.

> [!NOTE]
> **Pourquoi**
>
> La signature porte sur un seul petit fichier, `Release` (signé à part en
> `Release.gpg`, ou en ligne dans `InRelease`). Il contient les empreintes
> SHA-256 des index `Packages` et `Sources` ; chaque index contient
> l'empreinte de chaque `.deb`. Une seule signature vérifiée garantit ainsi
> toute la chaîne, jusqu'au dernier octet de chaque paquet (QO33.2). Les
> `.deb` eux-mêmes ne sont normalement pas signés individuellement côté
> Debian, contrairement aux RPM.

---

<a id="q33-11"></a>**[Q33.11](README.md#q33-11)** — *`gpgcheck=1` et `repo_gpgcheck=1`.*

**Réponse : b)** chaque paquet **et** les métadonnées du dépôt.

> [!NOTE]
> **Pourquoi**
>
> * `gpgcheck=1` : chaque RPM porte sa propre signature dans son en-tête,
>   vérifiée avant installation ; un RPM copié à la main reste vérifiable.
> * `repo_gpgcheck=1` : `repomd.xml`, qui fixe les empreintes de tous les
>   autres fichiers de métadonnées, est vérifié grâce à sa signature détachée
>   `repomd.xml.asc`. Sans cela, un miroir malveillant pourrait servir des
>   métadonnées anciennes (et donc une version vulnérable, mais correctement
>   signée, d'un paquet) ou cacher une mise à jour de sécurité.
>
> Les deux sont complémentaires ; beaucoup de dépôts tiers n'activent que le
> premier.

---

<a id="q33-12"></a>**[Q33.12](README.md#q33-12)** — *Séparer station de signature et serveur web.*

**Réponse : a)** le serveur exposé est le plus attaquable.

> [!NOTE]
> **Pourquoi**
>
> Le serveur web est joignable par tous les clients, il exécute nginx et ses
> modules, il reçoit des connexions de l'extérieur : c'est la machine la plus
> exposée de la chaîne. Si la clé de signature s'y trouvait, sa compromission
> permettrait de signer et de distribuer un paquet malveillant que tous les
> clients installeraient en root, en toute confiance. Avec la signature faite
> ailleurs, un attaquant du serveur web peut au pire supprimer ou geler le
> dépôt (déni de service, ou rejeu de métadonnées anciennes, limité par la
> date de validité de `Release`), pas fabriquer un paquet accepté. En
> production, la clé vit dans un HSM ou une machine de signature dédiée, et la
> CI soumet des demandes de signature sans jamais voir la clé (QO33.8).

---

<a id="q33-13"></a>**[Q33.13](README.md#q33-13)** — *Changement de clé, clients non prévenus.*

**Réponse : d)** une erreur de signature (`NO_PUBKEY`), et le dépôt est ignoré.

> [!NOTE]
> **Pourquoi**
>
> apt ne connaît que les clés désignées par `Signed-By`. Un `InRelease` signé
> par une autre clé est, pour lui, signé par un inconnu : `NO_PUBKEY
> <identifiant>` ; apt rejette ce nouvel `InRelease` et garde les anciens index
> (« The repository is not updated and the previous index files will be
> used ») : plus aucune mise à jour de ce dépôt n'arrive. C'est le
> comportement voulu (sinon n'importe qui pourrait signer à la place du dépôt),
> et c'est BF33.1 : publier la nouvelle clé **sur le dépôt lui-même** ne sert
> à rien, puisque rien ne dit au client de lui faire confiance.

---

<a id="q33-14"></a>**[Q33.14](README.md#q33-14)** — *Fichier livré par deux paquets.*

**Réponse : b)** `Replaces:` (et `Breaks:`), ou ne plus livrer le fichier en double.

> [!NOTE]
> **Pourquoi**
>
> Un fichier ne peut appartenir qu'à un paquet. Quand il change de paquet (un
> programme déplacé de `lab33-sante` vers `lab33-outils`), le nouveau paquet
> déclare `Replaces: lab33-sante (<< 1.2)` (il a le droit d'écraser les
> fichiers de ces versions) et `Breaks: lab33-sante (<< 1.2)` (forcer la mise à
> jour de l'ancien en même temps). Quand c'est une erreur (deux programmes
> différents qui portent le même nom), on renomme. `--force-overwrite` sur les
> clients masque le problème, et la prochaine désinstallation de l'un des deux
> paquets supprimera le fichier de l'autre. C'est BF33.2.

---

<a id="q33-15"></a>**[Q33.15](README.md#q33-15)** — *DKMS et un nouveau noyau.*

**Réponse : c)** il recompile et installe automatiquement les modules enregistrés.

> [!NOTE]
> **Pourquoi**
>
> DKMS garde les **sources** du module dans `/usr/src/<module>-<version>/`.
> Les paquets de noyau et d'en-têtes appellent ses crochets
> (`/etc/kernel/postinst.d/dkms`, `/etc/kernel/header_postinst.d/dkms`) : pour
> chaque module marqué `AUTOINSTALL="yes"`, DKMS le compile contre les en-têtes
> du nouveau noyau et l'installe dans `/lib/modules/<version>/updates/dkms/`.
> Sans les en-têtes (`linux-headers-…`), rien ne peut être compilé : le module
> manque au redémarrage. D'où la dépendance des paquets `-dkms` envers les
> en-têtes, et la surveillance de `dkms status` après chaque mise à jour du
> noyau.

---

<a id="q33-16"></a>**[Q33.16](README.md#q33-16)** — *Module DKMS refusé avec Secure Boot.*

**Réponse : b)** le noyau exige un module signé par une clé de confiance (MOK).

> [!NOTE]
> **Pourquoi**
>
> Avec Secure Boot, le noyau d'Ubuntu (mode *lockdown* en intégrité) refuse
> les modules non signés par une clé qu'il approuve : celles de la
> distribution, ou une **MOK** (*Machine Owner Key*) enregistrée dans le
> micrologiciel par `mokutil --import`, avec une confirmation à la console au
> redémarrage suivant. Le paquet `dkms` d'Ubuntu génère une telle clé
> (`/var/lib/shim-signed/mok/`) et signe automatiquement les modules qu'il
> construit ; reste à l'enregistrer une fois par machine, ce qui ne
> s'automatise pas à distance par conception. Les VM du laboratoire démarrent
> en BIOS (SeaBIOS), sans Secure Boot : la question ne s'y pose pas.

---

## 33.4 Quiz — questions ouvertes

<a id="qo33-1"></a>**[QO33.1](README.md#qo33-1)** — *Une archive de sources à installer sur trente serveurs.*

**Réponse attendue**

1. **Lire** : licence, dépendances, `README`, système de construction ;
   chercher si un paquet existe déjà (distribution, dépôt officiel de
   l'éditeur, EPEL) : c'est presque toujours la meilleure réponse.
2. **Construire une fois**, sur une machine de construction (ou dans un
   environnement propre : `sbuild`, `mock`, conteneur), avec les options de
   durcissement de la distribution, et **jamais** sur les serveurs.
3. **Empaqueter** (`.deb` ou `.rpm`) : fichiers listés, configuration
   protégée, unité systemd, utilisateur dédié, dépendances déclarées,
   version et révision. Le paquet sait se mettre à jour et se désinstaller.
4. **Publier** dans un dépôt signé interne.
5. **Déployer** par le gestionnaire de paquets, piloté par Ansible
   (module 23) : `apt: name=lab33-sante state=present` sur trente serveurs,
   idempotent, avec un déploiement progressif (`serial`).
6. **Suivre** : qui met à jour quand l'amont publie un correctif de
   sécurité ? Le paquet maison devient une dépendance de l'équipe ; il faut
   un responsable et une veille.

Ce qu'on ne fait pas : `scp` de l'archive et `make install` sur chaque
serveur (pas de traçabilité, pas de désinstallation, compilateurs sur les
serveurs de production, versions différentes partout).

---

<a id="qo33-2"></a>**[QO33.2](README.md#qo33-2)** — *La chaîne de confiance d'un `apt install`.*

**Réponse attendue**

1. Le client possède la **clé publique** du dépôt (`Signed-By:`), obtenue par
   un canal de confiance (paquet de trousseau, gestion de configuration,
   empreinte vérifiée).
2. `apt update` télécharge `InRelease`, vérifie sa signature avec **cette
   clé seulement** (via `gpgv`) : authenticité et intégrité de `Release`.
3. `Release` contient les empreintes SHA-256 des index (`Packages`,
   `Sources`, par architecture et composant) ; apt télécharge les index et
   rejette tout fichier dont l'empreinte diffère.
4. Chaque entrée de `Packages` contient la taille et l'empreinte SHA-256 du
   `.deb` ; au téléchargement, apt vérifie le `.deb` avant de le passer à
   dpkg.

Contre le **rejeu** d'une vieille version (un miroir qui servirait un
`InRelease` ancien, valablement signé, listant une version vulnérable) :
`Release` porte une date (`Date:`) et une limite (`Valid-Until:`) ; apt
refuse un `Release` expiré et un `Release` plus ancien que celui qu'il a déjà
vu. reprepro pose `Valid-Until` avec l'option `ValidFor:`. Sans cette
option, un dépôt interne n'est pas protégé contre le gel.

---

<a id="qo33-3"></a>**[QO33.3](README.md#qo33-3)** — *Paquet natif, conteneur, binaire statique, Flatpak/Snap.*

**Réponse attendue**

* **Paquet natif** : logiciel d'infrastructure intégré au système (services,
  outils d'administration, agents, modules noyau), qui doit suivre les mises
  à jour de sécurité de la distribution et partager ses bibliothèques.
* **Conteneur** : application de service avec ses dépendances figées,
  déployée par un orchestrateur (module 22, 26), mise à jour par
  reconstruction de l'image ; on y perd les mises à jour automatiques des
  bibliothèques, qu'il faut remplacer par une reconstruction régulière.
* **Binaire statique** (Go, Rust avec musl) : outil autonome distribué
  partout sans dépendance (CLI, agent) ; simple à copier, mais chaque faille
  d'une bibliothèque embarquée impose de le recompiler, et il reste préférable
  de l'empaqueter pour l'installer et le suivre.
* **Flatpak / Snap** : applications de bureau, ou logiciels qui veulent leur
  propre cycle de mise à jour indépendamment de la distribution, avec un
  confinement ; peu adaptés aux serveurs et aux outils système.

Le choix suit la question « qui met à jour ce logiciel et ses dépendances,
et comment ? ».

---

<a id="qo33-4"></a>**[QO33.4](README.md#qo33-4)** — *Rotation de la clé de signature.*

**Réponse attendue**

Rotation **planifiée** (clé ancienne, non compromise) :

1. générer la nouvelle clé bien avant l'expiration de l'ancienne ;
2. distribuer la **nouvelle clé publique** aux clients pendant que l'ancienne
   fait encore foi : idéalement par un paquet `lab33-archive-keyring` qui
   installe les **deux** clés dans `/usr/share/keyrings/`, publié et signé
   par l'ancienne clé (les clients le reçoivent par une mise à jour
   normale), ou par la gestion de configuration ;
3. attendre que tous les clients aient le nouveau trousseau (inventaire) ;
4. basculer la signature sur la nouvelle clé (ou signer avec les deux
   pendant une période : `InRelease` accepte plusieurs signatures) ;
5. plus tard, retirer l'ancienne clé du trousseau par une nouvelle version du
   paquet de clés.

Clé **compromise** :

* la **révoquer** (certificat de révocation préparé à la création de la
  clé) et la retirer des trousseaux **sans délai**, par un canal qui ne
  dépend pas du dépôt (gestion de configuration, SSH) ;
* signer avec une nouvelle clé dont l'empreinte est diffusée par un canal
  authentifié ;
* considérer comme suspect tout paquet signé depuis la date de compromission
  possible : reconstruire depuis des sources vérifiées, auditer les clients
  qui ont installé quelque chose dans l'intervalle ;
* trouver comment la clé a fuité avant de la remplacer par une autre au même
  endroit.

---

<a id="qo33-5"></a>**[QO33.5](README.md#qo33-5)** — *Constructions reproductibles.*

**Réponse attendue**

Une construction est **reproductible** si, à partir des mêmes sources et du
même environnement déclaré, n'importe qui obtient un binaire **identique à
l'octet près**. Intérêt : on peut vérifier qu'un paquet distribué correspond
bien aux sources publiées ; un attaquant qui compromet la machine de
construction (et y injecte du code) est détecté par une reconstruction
indépendante qui ne donne pas le même résultat. C'est la réponse aux attaques
de la chaîne d'approvisionnement du type SolarWinds ou xz-utils (partiellement
pour ce dernier, dont la porte dérobée était dans l'archive source elle-même).

Ce qui casse la reproductibilité : horodatages (dans les archives, la
documentation, les binaires : `__DATE__`), chemins de construction compilés
dans les binaires et les informations de débogage, ordre de parcours des
répertoires, valeurs aléatoires, variables d'environnement (langue, fuseau),
versions d'outils différentes. Remèdes : `SOURCE_DATE_EPOCH`, options
`-ffile-prefix-map`, tri explicite, environnement de construction déclaré
(`.buildinfo` de Debian), et des outils comme `reprotest` et `diffoscope`.
Les archives amont du setup sont construites ainsi (`tar --sort=name
--mtime=…`).

---

<a id="qo33-6"></a>**[QO33.6](README.md#qo33-6)** — *Scriptlets de paquet.*

**Réponse attendue**

Ce qu'ils doivent faire : le strict nécessaire que des fichiers ne peuvent
pas exprimer : activer ou redémarrer un service (macros fournies),
recharger systemd, créer un utilisateur (aujourd'hui de préférence par
`sysusers.d`, déclaratif), migrer une configuration à la mise à jour.

Ce qu'ils ne doivent jamais faire : télécharger quoi que ce soit, poser des
questions (sauf `debconf` côté Debian), modifier des fichiers d'**autres**
paquets ou la configuration de l'administrateur, supprimer des données
utilisateur à la désinstallation (seulement au `purge`), supposer qu'ils
tournent dans un système complet (ils s'exécutent aussi dans des chroots,
des images, à l'installation initiale), échouer pour une raison anodine (un
scriptlet qui échoue laisse le paquet à moitié installé).

Idempotents parce qu'ils sont rejoués : réinstallation, mise à jour,
reprise après un échec (`dpkg --configure -a`), et parce qu'ils reçoivent des
arguments différents selon le cas (`configure`, `upgrade`, `remove`…, ou `$1`
= 1 ou 2 côté RPM) : créer un utilisateur qui existe déjà ne doit pas
échouer, activer un service déjà activé non plus.

---

<a id="qo33-7"></a>**[QO33.7](README.md#qo33-7)** — *DKMS en production.*

**Réponse attendue**

Pourquoi DKMS : un module noyau est lié à une version **précise** du noyau
(ABI interne non stable). Un module compilé une fois et copié ne se chargera
plus après la prochaine mise à jour du noyau (« invalid module format ») ;
DKMS le recompile automatiquement pour chaque noyau installé.

Risques :

* la compilation peut **échouer** sur un nouveau noyau (API interne
  changée) : le serveur redémarre sans le module (pilote réseau ou stockage
  manquant : machine injoignable) ; on surveille `dkms status` et le
  journal de construction après chaque mise à jour du noyau, et on garde
  l'ancien noyau dans le menu de démarrage ;
* il faut les **en-têtes** et un **compilateur** sur les serveurs de
  production, ce qui agrandit la surface d'attaque ;
* **Secure Boot** : signature par une MOK, enregistrement manuel par
  machine (Q33.16) ;
* temps de mise à jour du noyau allongé.

Alternatives : module empaqueté précompilé par version de noyau (ce que font
les distributions pour certains pilotes), noyaux et modules gérés ensemble
dans une image (immuable), ou un module intégré à la branche principale du
noyau quand c'est possible.

---

<a id="qo33-8"></a>**[QO33.8](README.md#qo33-8)** — *Construction et publication en CI, sans exposer la clé.*

**Réponse attendue**

* La CI (module 25) **construit et teste** : à chaque étiquette `v*`,
  construction dans un conteneur propre (Debian et Rocky), `lintian`,
  `rpmlint`, tests, installation d'essai dans un conteneur, artefacts
  `.deb` / `.rpm`.
* Elle **ne signe pas** avec la clé du dépôt : les artefacts sont envoyés à
  un service de signature (machine dédiée, HSM, ou outil comme `obs-signd`,
  Sigstore) qui vérifie leur provenance (étiquette signée, empreinte
  attendue, journal de la CI) et signe ; ou la signature reste une étape
  manuelle sur la station de signature, avec la phrase de passe tapée par un
  humain, pour un petit dépôt.
* La publication vers le serveur web se fait avec une clé SSH qui n'a le
  droit que d'**écrire** dans le dépôt (`rrsync -wo`), pas de signer.
* Si la CI doit vraiment signer, on lui donne une **sous-clé** de signature
  dédiée, révocable, avec une expiration courte, stockée dans le gestionnaire
  de secrets de la CI et disponible seulement pour les étiquettes protégées,
  jamais la clé principale.

---

## 33.5 Exercices guidés

<a id="e33-1"></a>**[E33.1](README.md#e33-1)** — *Contenu de l'archive et variables du `Makefile`.*

```bash
tar tzf ~/lab33/amont/lab33-sante-1.0.tar.gz
tar xzOf ~/lab33/amont/lab33-sante-1.0.tar.gz lab33-sante-1.0/Makefile | grep -E '\?='
#   PREFIX ?= /usr/local   BINDIR ?=   MANDIR ?=   SYSCONFDIR ?=   UNITDIR ?=   SYSUSERSDIR ?=   CFLAGS ?=
```

> [!NOTE]
> **Pourquoi**
>
> `?=` n'affecte la variable que si elle n'est pas déjà définie (par la ligne
> de commande `make VAR=…` ou par l'environnement) : c'est ce qui rend ces
> chemins et options surchargeables par l'empaqueteur. `CPPFLAGS +=` ajoute à
> ce que l'environnement fournit déjà (les options de durcissement de
> `dpkg-buildflags`). Le `Makefile` n'a **pas** de cible `uninstall` : le cas
> classique (L33.1, étape 2).

---

<a id="e33-2"></a>**[E33.2](README.md#e33-2)** — *Bibliothèques, PIE, protections.*

```bash
cd ~/lab33/src/lab33-sante-1.0 && make
ldd ./lab33-sante
readelf -h ./lab33-sante | grep Type             # DYN (Position-Independent Executable file)
readelf -d ./lab33-sante | grep -E 'FLAGS|BIND_NOW'
readelf -lW ./lab33-sante | grep GNU_RELRO
nm -D ./lab33-sante | grep -E '__stack_chk_fail|__.*_chk'
```

> [!NOTE]
> **Pourquoi**
>
> `Type: DYN` : exécutable indépendant de la position (PIE), chargé à une
> adresse aléatoire (ASLR). `GNU_RELRO` seul : RELRO partiel ; avec
> `BIND_NOW` (`-Wl,-z,now`), RELRO complet : la table des fonctions externes
> (GOT) est en lecture seule après le chargement. `__stack_chk_fail` : canari
> de pile (`-fstack-protector-strong`) ; les fonctions `__*_chk` (ici
> `__printf_chk`) : `_FORTIFY_SOURCE`, qui exige une optimisation (`-O`).
>
> Sur Ubuntu, même un simple `make` produit un binaire PIE, `BIND_NOW`, avec
> canari et `_FORTIFY_SOURCE=3` : le GCC d'Ubuntu active ces options **par
> défaut** (`echo | gcc -O2 -dM -E - | grep FORTIFY`). Ce n'est pas le cas du
> GCC de Debian ni de clang, d'où l'intérêt de `dpkg-buildflags` (L33.1,
> étape 4). Le paquet `devscripts` fournit `hardening-check`, qui résume tout
> cela.

---

<a id="e33-3"></a>**[E33.3](README.md#e33-3)** — *Chemins compilés selon `PREFIX`.*

```bash
make clean && make PREFIX=/usr
strings lab33-sante | grep lab33-sante.conf      # /etc/lab33-sante.conf
make clean && make                               # PREFIX=/usr/local par défaut
strings lab33-sante | grep lab33-sante.conf      # /usr/local/etc/lab33-sante.conf
grep ExecStart systemd/lab33-sante.service       # /usr/local/bin/lab33-sante
```

> [!NOTE]
> **Pourquoi**
>
> Le chemin de la configuration est **dans le binaire**, figé à la
> compilation, comme celui du programme dans l'unité générée. Un `make` sans
> `PREFIX` suivi d'un `make PREFIX=/usr install` installerait dans `/usr` un
> programme qui lit `/usr/local/etc` et une unité qui lance
> `/usr/local/bin/…` : `make install` ne régénère pas ce qui est déjà construit.
> C'est le piège de L33.2.

---

<a id="e33-4"></a>**[E33.4](README.md#e33-4)** — *Options de compilation de la distribution.*

```bash
dpkg-buildflags --get CFLAGS
#   -g -O2 -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer -ffile-prefix-map=…
#   -flto=auto -ffat-lto-objects -fstack-protector-strong -fstack-clash-protection
#   -Wformat -Werror=format-security -fcf-protection
dpkg-buildflags --get CPPFLAGS          # -Wdate-time -D_FORTIFY_SOURCE=3
dpkg-buildflags --get LDFLAGS           # -Wl,-Bsymbolic-functions -flto=auto … -Wl,-z,relro
DEB_BUILD_MAINT_OPTIONS=hardening=+all dpkg-buildflags --get LDFLAGS   # + -Wl,-z,now
```

> [!NOTE]
> **Pourquoi**
>
> On retrouve les pointeurs de cadre activés par défaut depuis Ubuntu 24.04
> (module 31), `_FORTIFY_SOURCE=3` (vérifications de taille plus complètes que
> le niveau 2), la protection contre les débordements de pile par sauts
> (`-fstack-clash-protection`) et contre le détournement du flot de contrôle
> (`-fcf-protection`, CET sur les processeurs Intel et AMD récents).
> `hardening=+all` ajoute `-z now` (RELRO complet) : on l'active dans
> `debian/rules`. Le GCC d'Ubuntu ferait déjà l'essentiel par défaut, mais un
> paquet ne doit pas dépendre des réglages implicites d'un compilateur : les
> options passées explicitement valent aussi pour un autre compilateur, une
> autre distribution, et elles apparaissent dans le journal de construction.

---

<a id="e33-5"></a>**[E33.5](README.md#e33-5)** — *En-têtes, contenu et conffiles du `.deb`.*

```bash
cd ~/lab33/deb
dpkg-deb -I lab33-sante_1.1-1_amd64.deb
dpkg-deb -c lab33-sante_1.1-1_amd64.deb
dpkg-deb -e lab33-sante_1.1-1_amd64.deb /tmp/ctrl && cat /tmp/ctrl/conffiles /tmp/ctrl/postinst
```

> [!NOTE]
> **Pourquoi**
>
> `-I` montre les champs de contrôle **générés** : `Depends: libc6 (>= 2.34)`
> remplie par `dh_shlibdeps`, `Installed-Size`, le mainteneur. `conffiles` liste
> `/etc/lab33-sante.conf` (ajouté par `dh_installdeb` pour tout fichier sous
> `/etc`). Le `postinst` contient les fragments générés par debhelper (bloc
> `# Automatically added by dh_installsysusers` puis `dh_installsystemd`, avec
> `deb-systemd-helper enable 'lab33-sante.timer'`) :
> c'est la raison de ne pas écrire ces scriptlets à la main.

---

<a id="e33-6"></a>**[E33.6](README.md#e33-6)** — *À qui appartient un fichier, conffiles modifiés.*

```bash
dpkg -S /usr/bin/ssh                     # openssh-client: /usr/bin/ssh
dpkg-query -W -f='${Conffiles}\n' openssh-server
sudo dpkg --verify openssh-server         # ??5?????? c /etc/ssh/sshd_config  -> modifié
```

> [!NOTE]
> **Pourquoi**
>
> `dpkg --verify` compare chaque fichier à l'empreinte enregistrée à
> l'installation : `5` à la troisième position = somme MD5 différente, `c` =
> fichier de configuration. C'est l'outil pour savoir ce qu'un administrateur a
> modifié sur une machine héritée, ou pour détecter un binaire remplacé
> (côté RPM : `rpm -V`).

---

<a id="e33-7"></a>**[E33.7](README.md#e33-7)** — *Macros RPM.*

```bash
rpm --eval '%{_bindir} %{_sysconfdir} %{_unitdir} %{_sysusersdir} %{?dist}'
#   /usr/bin /etc /usr/lib/systemd/system /usr/lib/sysusers.d .el9
rpm --eval '%{optflags}'
```

> [!NOTE]
> **Pourquoi**
>
> Un `.spec` n'écrit jamais `/usr/bin` en dur : les macros portent les
> conventions de la distribution (et `%{?dist}` le suffixe `.el9` qui distingue
> les constructions par version de distribution). `%{optflags}` est
> l'équivalent RPM de `dpkg-buildflags`, avec les options de durcissement de
> Red Hat.

---

<a id="e33-8"></a>**[E33.8](README.md#e33-8)** — *Dépendances et scriptlets du RPM.*

```bash
rpm -qp --requires ~/rpmbuild/RPMS/x86_64/lab33-sante-1.1-1.el9.x86_64.rpm
#   libc.so.6()(64bit)  libc.so.6(GLIBC_2.34)(64bit)  rtld(GNU_HASH) …
rpm -qp --scripts ~/rpmbuild/RPMS/x86_64/lab33-sante-1.1-1.el9.x86_64.rpm
```

> [!NOTE]
> **Pourquoi**
>
> Les dépendances de bibliothèque sont générées par `rpmbuild` à partir des
> binaires (comme `dh_shlibdeps`). Les scriptlets montrent l'expansion des
> macros systemd (`systemctl preset`, `systemctl --no-reload disable --now` à la
> désinstallation) et de `%sysusers_create_compat` (un appel à `useradd`
> généré à partir du fichier `sysusers`). Lire les scriptlets d'un paquet tiers
> avant de l'installer est un réflexe de sécurité : ils s'exécutent en root.

---

<a id="e33-9"></a>**[E33.9](README.md#e33-9)** — *La clé du dépôt.*

```bash
gpg --list-keys --keyid-format long --with-subkey-fingerprints 'Dépôt lab33'
#   pub   rsa4096/1A2B3C4D5E6F7A8B 2026-11-09 [C] [expire : 2028-11-08]
#         9F3E…1A2B3C4D5E6F7A8B
#   uid                 [  ultime ] Dépôt lab33 <depot@lab.local>
#   sub   rsa3072/0C1D2E3F4A5B6C7D 2026-11-09 [S] [expire : 2028-11-08]
```

> [!NOTE]
> **Pourquoi**
>
> La clé principale n'a que la capacité **C** (certifier : signer d'autres
> clés et ses propres sous-clés) ; la sous-clé a **S** (signer des données).
> On signe les dépôts avec la sous-clé : si elle fuit, on la révoque et on en
> crée une autre sous la même clé principale, que les clients connaissent
> déjà. La clé principale peut alors être gardée hors ligne. L'expiration force
> à revoir la clé périodiquement : elle se prolonge (`gpg --quick-set-expire`)
> tant qu'elle n'est pas compromise.

---

<a id="e33-10"></a>**[E33.10](README.md#e33-10)** — *D'où vient le paquet, et vérifier `InRelease` à la main.*

```bash
apt-cache policy lab33-sante
#   Candidat : 1.1-1
#   *** 1.1-1 500
#         500 http://lab-web.lab.local:8033/debian lab33/main amd64 Packages
curl -fsS -o /tmp/InRelease http://lab-web.lab.local:8033/debian/dists/lab33/InRelease
gpgv --keyring /etc/apt/keyrings/lab33.gpg /tmp/InRelease
#   gpgv: Bonne signature de « Dépôt lab33 <depot@lab.local> »
```

> [!NOTE]
> **Pourquoi**
>
> `gpgv` est le vérificateur minimal qu'apt utilise : il ne connaît que le
> trousseau qu'on lui donne, sans base de confiance ni réseau. C'est la façon
> de reproduire exactement le jugement d'apt lors d'un diagnostic de
> signature (BF33.1).

---

<a id="e33-11"></a>**[E33.11](README.md#e33-11)** — *Signature d'un RPM, clés importées.*

```bash
rpm -K lab33-sante-1.1-1.el9.x86_64.rpm         # digests signatures OK
rpm -q gpg-pubkey --qf '%{NAME}-%{VERSION}-%{RELEASE}\t%{SUMMARY}\n'
#   gpg-pubkey-5e6f7a8b-6aee8d9d   gpg(Dépôt lab33 <depot@lab.local>)
```

> [!NOTE]
> **Pourquoi**
>
> Les clés publiques importées dans RPM apparaissent comme de pseudo-paquets
> `gpg-pubkey`, dont la version est l'identifiant court de la clé **principale**
> (les huit derniers chiffres de son empreinte, même si c'est une sous-clé qui
> signe) et la révision sa date de création. On retire une clé avec
> `rpm -e gpg-pubkey-<id>`. `rpm -K` sans la clé importée affiche
> `digests SIGNATURES NOT OK` (signature présente, clé inconnue) ; un paquet
> sans signature affiche seulement `digests OK` (BF33.3).

---

<a id="e33-12"></a>**[E33.12](README.md#e33-12)** — *État DKMS du module.*

```bash
dkms status
#   lab33-compteur/1.0, 6.8.0-48-generic, x86_64: installed
modinfo lab33_compteur | grep -E 'filename|version|vermagic'
#   filename: /lib/modules/6.8.0-48-generic/updates/dkms/lab33_compteur.ko.zst
#   version:  1.0
#   vermagic: 6.8.0-48-generic SMP preempt mod_unload modversions
less "/var/lib/dkms/lab33-compteur/1.0/$(uname -r)/x86_64/log/make.log"
```

> [!NOTE]
> **Pourquoi**
>
> `updates/dkms/` est prioritaire sur les modules livrés avec le noyau (ordre
> de `depmod`). `vermagic` doit correspondre exactement au noyau qui le charge.
> DKMS compresse le module comme le noyau compresse les siens (`.ko.zst` sur
> Ubuntu 24.04). Après une construction réussie, le journal est rangé sous
> `<noyau>/<arch>/log/make.log` ; après un **échec**, il reste dans
> `/var/lib/dkms/lab33-compteur/1.0/build/make.log`, que DKMS cite dans son
> message d'erreur : c'est le premier endroit à lire quand une construction
> échoue après une mise à jour du noyau.

---

## 33.6 Labs

### <a id="l33-1"></a>**[L33.1](README.md#l33-1)** — Compiler proprement

**Étape 1 — Compiler et essayer**

```bash
mkdir -p ~/lab33/src && cd ~/lab33/src
tar xzf ~/lab33/amont/lab33-sante-1.0.tar.gz && cd lab33-sante-1.0
make
cat > /tmp/essai.conf <<'EOF'
web     lab-web.lab.local  80
base    lab-db.lab.local   5432
inconnu lab-db.lab.local   9999
EOF
./lab33-sante -c /tmp/essai.conf; echo "code $?"
#   OK web (lab-web.lab.local:80)
#   OK base (lab-db.lab.local:5432)        (ou KO si le pare-feu de lab-db filtre lab-adm)
#   KO inconnu (lab-db.lab.local:9999) : Connection refused
#   2/3 services joignables
#   code 1
```

**Étape 2 — Installer dans `/usr/local`, puis désinstaller**

```bash
sudo make install                           # PREFIX=/usr/local par défaut
ls /usr/local/etc/lab33-sante.conf
/usr/local/bin/lab33-sante --version
```

Le `Makefile` n'a pas de cible `uninstall`. On reconstitue la liste exacte
des fichiers par une installation de transit, puis on supprime ces seuls
fichiers :

```bash
make DESTDIR=/tmp/liste install
( cd /tmp/liste && find . -type f -o -type l ) | sed 's|^\.||' | sudo xargs -r rm -v
sudo rmdir -p --ignore-fail-on-non-empty /usr/local/lib/sysusers.d /usr/local/lib/systemd/system 2>/dev/null || true
rm -rf /tmp/liste
```

> [!NOTE]
> **Pourquoi**
>
> C'est exactement le problème qu'un paquet résout : savoir **ce qui a été
> installé** pour pouvoir l'enlever. Les outils comme GNU Stow (chaque logiciel
> dans son répertoire `/usr/local/stow/<nom>`, avec des liens symboliques) ou
> `checkinstall` (qui fabrique un paquet rudimentaire à partir d'un `make
> install`) en sont des contournements ; la vraie réponse est L33.2.

**Étape 3 — Installation de transit**

```bash
make clean
make PREFIX=/usr
make PREFIX=/usr DESTDIR="$HOME/lab33/transit" install
find ~/lab33/transit -type f | sort
#   /home/mathieu/lab33/transit/etc/lab33-sante.conf
#   /home/mathieu/lab33/transit/usr/bin/lab33-sante
#   /home/mathieu/lab33/transit/usr/lib/systemd/system/lab33-sante.service
#   /home/mathieu/lab33/transit/usr/lib/systemd/system/lab33-sante.timer
#   /home/mathieu/lab33/transit/usr/lib/sysusers.d/lab33-sante.conf
#   /home/mathieu/lab33/transit/usr/share/man/man1/lab33-sante.1
```

**Étape 4 — Durcissement**

```bash
hardening-check lab33-sante            # compilation par défaut (étape 3)
#   Position Independent Executable: yes   Stack protected: yes
#   Fortify Source functions: yes          Read-only relocations: yes
#   Immediate binding: yes                 Control flow integrity: yes
make clean && make CFLAGS='-O0 -g' && hardening-check lab33-sante | grep Fortify
#   Fortify Source functions: no, only unprotected functions found!
make clean
eval "$(DEB_BUILD_MAINT_OPTIONS=hardening=+all dpkg-buildflags --export=sh)"
make PREFIX=/usr
readelf -d lab33-sante | grep -E 'BIND_NOW|FLAGS'  # FLAGS BIND_NOW, FLAGS_1 NOW PIE
hardening-check lab33-sante
```

Surprise : sur Ubuntu, la compilation par défaut est **déjà** durcie. Le GCC
d'Ubuntu active PIE, `-z now`, le canari de pile, `_FORTIFY_SOURCE=3`, la
protection contre les sauts de pile et CET dès qu'on compile (et
`_FORTIFY_SOURCE` dès qu'on optimise : `-O0` le perd). Les options de
`dpkg-buildflags` ajoutent LTO, les pointeurs de cadre, les chemins neutres
(`-ffile-prefix-map`), `-Werror=format-security`, et surtout les rendent
**explicites** : elles valent avec le GCC de Debian (qui n'active rien de
tout cela par défaut), avec clang, et quel que soit le `CFLAGS` du
`Makefile` amont.

`dpkg-buildflags --export=sh` produit des `export CFLAGS=…` que `eval` place
dans l'environnement ; le `Makefile`, avec ses `?=` et `+=`, les reprend.

**Étape 5 — `compilation.md`**

```markdown
# lab33-sante 1.0 — compilation
* Dépendances d'exécution : libc.so.6 seulement (ldd).
* Fichiers installés (PREFIX=/usr) : binaire, configuration /etc, page de
  manuel, unité et minuteur systemd, déclaration sysusers (6 fichiers).
* Protections avec dpkg-buildflags (hardening=+all) : PIE, RELRO complet
  (BIND_NOW), canari de pile, FORTIFY_SOURCE=3, CET. Le GCC d'Ubuntu les
  active déjà par défaut ; FORTIFY disparaît en -O0. Les options explicites
  protègent du compilateur ou du Makefile qui ne le ferait pas.
* Pourquoi jamais `make install` dans /usr : on écrase des fichiers gérés
  par dpkg sans qu'il le sache, rien ne permet de désinstaller ni de mettre à
  jour proprement, et la machine n'a plus d'état connu. /usr/local pour un
  essai, un paquet pour tout le reste.
```

---

### <a id="l33-2"></a>**[L33.2](README.md#l33-2)** — Un paquet Debian digne de ce nom

**Étape 1 — Le paquet source**

```bash
mkdir -p ~/lab33/deb && cd ~/lab33/deb
cp ~/lab33/amont/lab33-sante-1.0.tar.gz lab33-sante_1.0.orig.tar.gz
tar xzf lab33-sante_1.0.orig.tar.gz && cd lab33-sante-1.0
mkdir -p debian/source
echo '3.0 (quilt)' > debian/source/format
export DEBFULLNAME="Mathieu" DEBEMAIL="mathieu@exemple.invalid"
dch --create --package lab33-sante -v 1.0-1 -D noble "Premier empaquetage."
```

`debian/control` :

```text
Source: lab33-sante
Section: admin
Priority: optional
Maintainer: Mathieu <mathieu@exemple.invalid>
Build-Depends: debhelper-compat (= 13), dh-sequence-installsysusers
Standards-Version: 4.6.2
Homepage: https://github.com/cemah2/WorkbookLinux
Rules-Requires-Root: no

Package: lab33-sante
Architecture: any
Depends: ${shlibs:Depends}, ${misc:Depends}
Description: vérifie que des services TCP répondent
 lab33-sante lit une liste de services (nom, hôte, port) et tente une
 connexion TCP vers chacun ; le code de retour signale les services
 injoignables. Un minuteur systemd le lance toutes les cinq minutes.
```

`debian/rules` (exécutable) :

```make
#!/usr/bin/make -f
export DEB_BUILD_MAINT_OPTIONS = hardening=+all

%:
	dh $@

# le même PREFIX à la compilation ET à l'installation
override_dh_auto_build:
	dh_auto_build -- PREFIX=/usr

override_dh_auto_install:
	dh_auto_install -- PREFIX=/usr

# seul le minuteur est activé ; le service est déclenché par lui
override_dh_installsystemd:
	dh_installsystemd lab33-sante.timer
```

`debian/copyright` (format lisible par machine) :

```text
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: lab33-sante
Source: https://github.com/cemah2/WorkbookLinux

Files: *
Copyright: 2026 Workbook Linux
License: MIT

Files: debian/*
Copyright: 2026 Mathieu <mathieu@exemple.invalid>
License: MIT

License: MIT
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software, to deal in the Software without restriction.
 .
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
```

> [!WARNING]
> **Piège**
>
> Sans les surcharges `dh_auto_build -- PREFIX=/usr`, debhelper lance `make`
> (compilation avec `PREFIX=/usr/local` par défaut) puis l'installation
> seule avec le `PREFIX` qu'on lui aurait donné : le binaire chercherait
> `/usr/local/etc/lab33-sante.conf` et l'unité lancerait
> `/usr/local/bin/lab33-sante`, qui n'existe pas. Le paquet s'installerait
> sans erreur, `lintian` ne dirait rien, et le minuteur échouerait toutes les
> cinq minutes. On vérifie toujours le résultat (`strings`, `systemctl cat`),
> pas seulement la construction.

**Étape 2 — Utilisateur système**

L'archive amont installe déjà unité, minuteur et déclaration `sysusers`.
Mais installer un fichier dans `/usr/lib/sysusers.d/` ne crée personne : il
faut que le `postinst` appelle `systemd-sysusers`. C'est le travail de
`dh_installsysusers`, qui lit `debian/<paquet>.sysusers` :

```bash
cp systemd/lab33-sante.sysusers debian/lab33-sante.sysusers
```

> [!WARNING]
> **Piège**
>
> Avec debhelper 13 (Ubuntu 24.04), `dh_installsysusers` n'est **pas** dans la
> séquence par défaut (il le sera au niveau de compatibilité 14) : sans
> `dh-sequence-installsysusers` dans `Build-Depends`, le fichier est livré, le
> paquet se construit sans un mot, et l'utilisateur `lab33` n'est jamais créé.
> Le minuteur échoue alors avec `status=217/USER`. On vérifie toujours le
> `postinst` généré (E33.5) :
>
> ```text
> # Automatically added by dh_installsysusers/13.14.1ubuntu5
>    systemd-sysusers ${DPKG_ROOT:+--root="$DPKG_ROOT"} lab33-sante.conf
> ```

L'unité amont contient déjà `User=lab33` ; `dh_installsystemd` détecte
l'unité et le minuteur installés dans `usr/lib/systemd/system/`.

**Étape 3 — Construire et `lintian`**

```bash
dpkg-buildpackage -us -uc
ls ..      # .orig.tar.gz, .debian.tar.xz, .dsc (paquet source), .deb, -dbgsym….ddeb, .buildinfo, .changes
lintian -i -I --pedantic ../lab33-sante_1.0-1_amd64.changes
#   W: lab33-sante: initial-upload-closes-no-bugs [usr/share/doc/lab33-sante/changelog.Debian.gz:1]
#   I: lab33-sante source: debian-watch-file-is-missing
```

Avec le `control` et le `rules` ci-dessus, il ne reste que deux remarques,
toutes deux propres à l'archive Debian :

| Remarque | Signification | Traitement |
|---|---|---|
| `initial-upload-closes-no-bugs` (W) | un premier envoi dans Debian doit fermer un rapport *ITP* | sans objet pour un paquet interne : surcharge |
| `debian-watch-file-is-missing` (I) | pas de `debian/watch` pour `uscan` | information ; à écrire si l'amont publie ses archives à une adresse stable |

Les remarques qu'on rencontre en chemin, si l'on part d'un `control`
minimal : `no-homepage-field` (champ `Homepage:`), `extended-description-is-empty`
(la description longue), `debian-rules-not-executable`,
`dir-or-file-in-usr-local` (on a oublié `PREFIX=/usr` à l'installation),
`systemd-service-file-missing-documentation-key` (amont : `Documentation=`).

```bash
echo 'initial-upload-closes-no-bugs' > debian/lab33-sante.lintian-overrides
dpkg-buildpackage -us -uc && lintian ../lab33-sante_1.0-1_amd64.changes   # plus rien
```

Le `.ddeb` contient les symboles de débogage séparés (BF31.1) : Ubuntu les
publie sur `ddebs.ubuntu.com` ; on ne les met pas dans le dépôt apt ordinaire.

**Étape 4 — Installation sur `lab-db`**

```bash
scp ~/lab33/deb/lab33-sante_1.0-1_amd64.deb lab-db.lab.local:/tmp/
# lab-db
sudo apt install /tmp/lab33-sante_1.0-1_amd64.deb
#   Creating user 'lab33' (lab33-sante) with UID 995 and GID 995.
#   Created symlink /etc/systemd/system/timers.target.wants/lab33-sante.timer → /usr/lib/systemd/system/lab33-sante.timer.
dpkg -L lab33-sante
getent passwd lab33                       # lab33:x:995:995:lab33-sante:/nonexistent:/usr/sbin/nologin
systemctl list-timers lab33-sante.timer
sudo systemctl start lab33-sante.service; journalctl -u lab33-sante -n 4 --no-pager
systemctl show -p User lab33-sante.service
```

**Étape 5 — Mise à jour 1.1 et configuration modifiée**

```bash
# lab-db : modification locale
echo 'cache lab-db.lab.local 6379' | sudo tee -a /etc/lab33-sante.conf
# lab-adm : version 1.1 à partir de la nouvelle archive amont
cd ~/lab33/deb
cp ~/lab33/amont/lab33-sante-1.1.tar.gz lab33-sante_1.1.orig.tar.gz
tar xzf lab33-sante_1.1.orig.tar.gz
cp -a lab33-sante-1.0/debian lab33-sante-1.1/
cd lab33-sante-1.1 && dch -v 1.1-1 "Nouvelle version amont : sortie --json, délai réglable."
dpkg-buildpackage -us -uc && scp ../lab33-sante_1.1-1_amd64.deb lab-db.lab.local:/tmp/
# lab-db, interactif
sudo apt install /tmp/lab33-sante_1.1-1_amd64.deb
#   Configuration file '/etc/lab33-sante.conf'
#    ==> Modified (by you or by a script) since installation.
#    ==> Package distributor has shipped an updated version.
#      What would you like to do about it ?  Your options are:
#       Y or I  : install the package maintainer's version
#       N or O  : keep your currently-installed version
#         D     : show the differences between the versions
```

En mode non interactif, en gardant la version locale :

```bash
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
  /tmp/lab33-sante_1.1-1_amd64.deb
#    ==> Keeping old config file as default.
ls /etc/lab33-sante.conf*        # /etc/lab33-sante.conf  /etc/lab33-sante.conf.dpkg-dist
sudo dpkg --verify lab33-sante   # ??5?????? c /etc/lab33-sante.conf
```

**Étape 6 — `remove` et `purge`**

```bash
sudo apt remove lab33-sante
dpkg -l lab33-sante | tail -1     # rc  lab33-sante  1.1-1  … : retiré, configuration conservée
ls /etc/lab33-sante.conf*         # toujours là (avec le .dpkg-dist)
sudo apt purge lab33-sante
ls /etc/lab33-sante.conf*         # disparu (le .dpkg-dist aussi)
getent passwd lab33               # l'utilisateur reste
sudo apt install /tmp/lab33-sante_1.1-1_amd64.deb   # pour la suite du module
```

> [!NOTE]
> **Pourquoi**
>
> `remove` retire les programmes mais garde la configuration (état `rc`) :
> réinstaller retrouve les réglages. `purge` supprime aussi les `conffiles`.
> L'utilisateur système, lui, n'est jamais supprimé : des fichiers lui
> appartenant peuvent subsister ailleurs (journaux, données), et réattribuer
> plus tard son UID à un autre compte lui donnerait ces fichiers. C'est la
> politique de Debian pour tous les utilisateurs système.

---

### <a id="l33-3"></a>**[L33.3](README.md#l33-3)** — Le même logiciel en RPM

**Étape 1 — Arborescence et sources**

```bash
rpmdev-setuptree
cp ~/lab33/amont/lab33-sante-1.0.tar.gz ~/rpmbuild/SOURCES/
tar xzOf ~/lab33/amont/lab33-sante-1.0.tar.gz lab33-sante-1.0/systemd/lab33-sante.sysusers \
  > ~/rpmbuild/SOURCES/lab33-sante.sysusers
```

**Étape 2 — Le `.spec`**

```text
Name:           lab33-sante
Version:        1.0
Release:        1%{?dist}
Summary:        Vérifie que des services TCP répondent
License:        MIT
URL:            https://github.com/cemah2/WorkbookLinux
Source0:        %{name}-%{version}.tar.gz
Source1:        %{name}.sysusers

BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  systemd-rpm-macros
%{?sysusers_requires_compat}

%description
lab33-sante lit une liste de services (nom, hôte, port) et tente une
connexion TCP vers chacun. Un minuteur systemd le lance toutes les cinq
minutes.

%prep
%autosetup

%build
%set_build_flags
%make_build PREFIX=%{_prefix}

%install
%make_install PREFIX=%{_prefix} UNITDIR=%{_unitdir} SYSUSERSDIR=%{_sysusersdir}

%check
make check

%pre
%sysusers_create_compat %{SOURCE1}

%post
%systemd_post %{name}.timer

%preun
%systemd_preun %{name}.timer

%postun
%systemd_postun_with_restart %{name}.timer

%files
%license LICENSE
%doc README CHANGELOG
%{_bindir}/%{name}
%config(noreplace) %{_sysconfdir}/%{name}.conf
%{_mandir}/man1/%{name}.1*
%{_unitdir}/%{name}.service
%{_unitdir}/%{name}.timer
%{_sysusersdir}/%{name}.conf

%changelog
* Mon Nov 09 2026 Mathieu <mathieu@exemple.invalid> - 1.0-1
- Premier empaquetage.
```

> [!NOTE]
> **Pourquoi**
>
> * `%set_build_flags` exporte `CFLAGS`, `LDFLAGS` et compagnie avec les
>   options de la distribution (sur EL9, ce n'est pas encore automatique dans
>   `%build`) ; le `Makefile` les reprend grâce à ses `?=`. Même piège que côté
>   Debian : `PREFIX` est passé à la compilation **et** à l'installation.
> * `%sysusers_create_compat` lit le fichier `sysusers` **à la construction** et
>   génère un `%pre` qui crée l'utilisateur avec `useradd` s'il n'existe pas :
>   d'où `Source1`, disponible à ce moment-là, plutôt que le fichier de
>   l'archive.
> * `%{_mandir}/man1/%{name}.1*` : `rpmbuild` compresse les pages de manuel ;
>   l'étoile accepte l'extension `.gz`.
> * `%files` est exhaustif : un fichier installé dans `%{buildroot}` mais absent
>   de la liste fait échouer la construction (*Installed (but unpackaged)
>   file(s) found*), ce qui garantit qu'on sait ce que livre le paquet.

**Étape 3 — Construire, `rpmlint`**

```bash
rpmbuild -ba ~/rpmbuild/SPECS/lab33-sante.spec
rpmlint ~/rpmbuild/SPECS/lab33-sante.spec ~/rpmbuild/RPMS/x86_64/lab33-sante-1.0-1.el9.x86_64.rpm
#   lab33-sante.x86_64: W: invalid-url URL: https://github.com/cemah2/WorkbookLinux <urlopen error …>
#   2 packages and 1 specfiles checked; 0 errors, 1 warnings.
```

L'avertissement `invalid-url` vient de l'absence d'accès à Internet pendant
la vérification, pas de l'empaquetage. `rpmbuild` produit aussi
`lab33-sante-debuginfo` et `-debugsource` (symboles séparés, le mécanisme
vu en BF31.1).

**Étape 4 — Installer, vérifier**

```bash
sudo dnf install -y ~/rpmbuild/RPMS/x86_64/lab33-sante-1.0-1.el9.x86_64.rpm
rpm -ql lab33-sante; getent passwd lab33
systemctl is-enabled lab33-sante.timer        # selon le preset ; sinon :
sudo systemctl enable --now lab33-sante.timer
ls -Z /usr/bin/lab33-sante                    # system_u:object_r:bin_t:s0
```

> [!NOTE]
> **Pourquoi**
>
> `%systemd_post` applique les **presets** de la distribution
> (`systemctl preset`) : sur RHEL, la politique par défaut est de ne **pas**
> activer les services installés, sauf liste explicite
> (`/usr/lib/systemd/system-preset/`). Debian, lui, active ce que
> `dh_installsystemd` déclare. C'est une différence de philosophie à
> connaître : sur Rocky, l'activation est une décision de l'administrateur (ou
> d'un fichier de preset livré par le paquet, `90-lab33.preset`).
>
> Le binaire reçoit le contexte SELinux `bin_t` grâce aux règles par défaut de
> `/usr/bin` : rien à faire. Un binaire installé dans `/opt` ou
> `/usr/local/bin` peut demander une règle `semanage fcontext` (module 18).

**Étape 5 — 1.1 et `.rpmnew`**

```bash
echo 'cache lab-db.lab.local 6379' | sudo tee -a /etc/lab33-sante.conf
cp ~/lab33/amont/lab33-sante-1.1.tar.gz ~/rpmbuild/SOURCES/
sed -i 's/^Version:.*/Version:        1.1/' ~/rpmbuild/SPECS/lab33-sante.spec
rpmdev-bumpspec -c "Nouvelle version amont : sortie --json, délai réglable." \
  ~/rpmbuild/SPECS/lab33-sante.spec      # ajoute l'entrée au %changelog
sed -i 's/^Release:.*/Release:        1%{?dist}/' ~/rpmbuild/SPECS/lab33-sante.spec
rpmbuild -ba ~/rpmbuild/SPECS/lab33-sante.spec
sudo dnf upgrade -y ~/rpmbuild/RPMS/x86_64/lab33-sante-1.1-1.el9.x86_64.rpm
#   warning: /etc/lab33-sante.conf created as /etc/lab33-sante.conf.rpmnew
```

---

### <a id="l33-4"></a>**[L33.4](README.md#l33-4)** — Des dépôts signés pour tout le parc

**Étape 1 — La clé**

```bash
# lab-adm
export GPG_TTY=$(tty)
gpg --quick-generate-key 'Dépôt lab33 <depot@lab.local>' rsa4096 cert 2y   # phrase de passe demandée
FPR=$(gpg --list-keys --with-colons 'Dépôt lab33' | awk -F: '/^fpr/{print $10; exit}')
gpg --quick-add-key "$FPR" rsa3072 sign 2y
SUB=$(gpg --list-keys --with-colons "$FPR" | awk -F: '/^sub/{s=1} s&&/^fpr/{print $10; exit}')
echo "FPR=$FPR SUB=$SUB" > ~/lab33/cle.env
mkdir -p ~/lab33/publication
gpg --armor --export "$FPR" > ~/lab33/publication/lab33.asc
gpg --export "$FPR" > ~/lab33/publication/lab33.gpg
ls ~/.gnupg/openpgp-revocs.d/          # <FPR>.rev : certificat de révocation, créé avec la clé
```

> [!NOTE]
> **Pourquoi**
>
> RSA plutôt qu'Ed25519 : compatibilité garantie avec RPM 4.16 (EL9) et tous
> les outils de la chaîne. `GPG_TTY` permet à `pinentry` de demander la phrase
> de passe dans un terminal SSH. GnuPG crée un certificat de révocation en même
> temps que la clé, dans `~/.gnupg/openpgp-revocs.d/` : on le copie **hors
> ligne** (clé USB au coffre, gestionnaire de secrets) et on l'efface de la
> station. Le jour où la clé est perdue, on ne pourrait plus le créer ; le jour
> où la station est compromise, l'attaquant ne doit pas pouvoir révoquer la
> clé à notre place.

**Étape 2 — Dépôt apt avec reprepro**

```bash
mkdir -p ~/lab33/reprepro/conf
. ~/lab33/cle.env
cat > ~/lab33/reprepro/conf/distributions <<EOF
Origin: lab33
Label: Depot lab33
Codename: lab33
Architectures: amd64 source
Components: main
Description: Paquets maison du workbook (module 33)
SignWith: $SUB
ValidFor: 14d
EOF
cat > ~/lab33/reprepro/conf/options <<'EOF'
outdir +b/../publication/debian
verbose
EOF
R="reprepro -b $HOME/lab33/reprepro"
$R includedeb lab33 ~/lab33/deb/lab33-sante_1.0-1_amd64.deb
$R includedsc lab33 ~/lab33/deb/lab33-sante_1.0-1.dsc
$R includedeb lab33 ~/lab33/deb/lab33-sante_1.1-1_amd64.deb
$R includedsc lab33 ~/lab33/deb/lab33-sante_1.1-1.dsc
$R list lab33
#   lab33|main|amd64: lab33-sante 1.1-1
#   lab33|main|source: lab33-sante 1.1-1
ls ~/lab33/publication/debian/dists/lab33/     # InRelease  Release  Release.gpg  main/
```

`reprepro` ne garde **qu'une** version par paquet, distribution et
composant : la 1.1-1 a remplacé la 1.0-1 (l'option `Limit:` de reprepro 5.4
permet d'en garder plusieurs). `outdir +b/../publication/debian` sépare la
configuration et la base (`conf/`, `db/`), qui restent privées, de ce qui
est publié. `ValidFor: 14d` pose `Valid-Until` dans `Release` : un dépôt figé
plus de deux semaines (rejeu, serveur compromis qui sert d'anciens fichiers)
sera refusé par les clients ; il faut donc republier (`reprepro export`) au
moins tous les quinze jours.

**Étape 3 — Dépôt RPM**

```bash
D=~/lab33/publication/rpm/el9/x86_64; mkdir -p "$D"
scp lab-rhel.lab.local:'rpmbuild/RPMS/x86_64/lab33-sante-1.1-1.el9.x86_64.rpm' "$D/"
. ~/lab33/cle.env
rpmsign --define "_gpg_name $SUB" --addsign "$D"/*.rpm
createrepo_c "$D"
gpg --batch --yes --local-user "$SUB!" --detach-sign --armor "$D/repodata/repomd.xml"
mkdir -p ~/lab33/rpmdb && rpmkeys --dbpath ~/lab33/rpmdb --import ~/lab33/publication/lab33.asc
rpmkeys --dbpath ~/lab33/rpmdb -K "$D"/*.rpm      # … digests signatures OK
gpg --verify "$D/repodata/repomd.xml.asc" "$D/repodata/repomd.xml"
```

Le `!` après l'identifiant force `gpg` à utiliser **cette** sous-clé
précisément. La base RPM privée (`--dbpath`) permet de vérifier les
signatures sur `lab-adm` sans toucher à la base système (Ubuntu n'en a pas
l'usage).

**Étape 4 — Publication vers `lab-web`**

```bash
# lab-adm
ssh-keygen -t ed25519 -N '' -C 'mathieu@lab-adm publication' -f ~/.ssh/id_depot
# lab-web (en mathieu, avec sudo)
echo "command=\"/usr/bin/rrsync -wo /srv/depot\",restrict $(cat id_depot.pub)" |
  sudo tee /home/depot/.ssh/authorized_keys
sudo chown depot: /home/depot/.ssh/authorized_keys && sudo chmod 600 /home/depot/.ssh/authorized_keys
# lab-adm
rsync -a --delete --delay-updates -e 'ssh -i ~/.ssh/id_depot' ~/lab33/publication/ depot@lab-web.lab.local:
curl -fsS http://lab-web.lab.local:8033/debian/dists/lab33/InRelease | head -3
curl -fsSI http://lab-web.lab.local:8033/rpm/el9/x86_64/repodata/repomd.xml.asc | head -1
```

> [!NOTE]
> **Pourquoi**
>
> `--delay-updates` copie tous les fichiers à côté et ne les met en place qu'à
> la fin : un client qui lit le dépôt pendant la publication ne voit pas un
> `InRelease` neuf qui annonce des index pas encore arrivés (erreur *Hash Sum
> mismatch*). Pour une publication vraiment atomique, on publie dans un
> répertoire neuf et on bascule un lien symbolique (ce que fait aptly).

**Étape 5 — Client apt (`lab-db`)**

```bash
curl -fsS http://lab-web.lab.local:8033/lab33.gpg -o /tmp/lab33.gpg
gpg --show-keys --with-fingerprint /tmp/lab33.gpg       # comparer avec FPR noté sur lab-adm
sudo install -D -m 644 /tmp/lab33.gpg /etc/apt/keyrings/lab33.gpg
sudo tee /etc/apt/sources.list.d/lab33.sources >/dev/null <<'EOF'
Types: deb
URIs: http://lab-web.lab.local:8033/debian
Suites: lab33
Components: main
Signed-By: /etc/apt/keyrings/lab33.gpg
EOF
sudo apt update
sudo apt remove -y lab33-sante && sudo apt install -y lab33-sante
apt-cache policy lab33-sante | head -4
```

> [!WARNING]
> **Piège**
>
> Télécharger la clé **depuis le serveur qu'elle est censée authentifier** ne
> prouve rien : un attaquant qui contrôle le serveur web y aurait mis la sienne.
> L'empreinte se compare à une source indépendante (ici, ce qu'affiche `gpg`
> sur `lab-adm` ; en entreprise, la documentation interne, ou mieux, la clé
> distribuée par la gestion de configuration). HTTP sans TLS est acceptable
> pour le **transport** des paquets puisque tout est signé ; il ne l'est pas
> pour la première obtention de la clé.

**Étape 6 — Client dnf (`lab-rhel`)**

```bash
sudo tee /etc/yum.repos.d/lab33.repo >/dev/null <<'EOF'
[lab33]
name=Dépôt lab33
baseurl=http://lab-web.lab.local:8033/rpm/el9/x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=http://lab-web.lab.local:8033/lab33.asc
EOF
sudo dnf makecache --repo lab33
#   Importing GPG key 0x5E6F7A8B:
#    Userid     : "Dépôt lab33 <depot@lab.local>"
#    Fingerprint: 9F3E …                  <- à comparer à FPR, puis « y »
sudo dnf upgrade -y lab33-sante || sudo dnf install -y lab33-sante
dnf info lab33-sante | grep -E 'Version|Release|Repo'
```

**Étape 7 — `publier.sh`**

```bash
#!/usr/bin/env bash
# publier.sh paquet.deb|paquet.rpm … — ajoute au dépôt, signe, vérifie, publie (module 33)
# Usage : publier.sh [--sans-paquet] fichiers…   (--sans-paquet : ré-exporte et publie seulement)
set -euo pipefail
# shellcheck source=/dev/null
. ~/lab33/cle.env                                   # FPR, SUB
PUB=~/lab33/publication
REP="reprepro -b $HOME/lab33/reprepro"
RPMD=$PUB/rpm/el9/x86_64
RPMDB=~/lab33/rpmdb
GPG_TTY=$(tty 2>/dev/null || true); export GPG_TTY
rpm_touche=0

for f in "$@"; do
  case "$f" in
    --sans-paquet) ;;
    *.deb) $REP includedeb lab33 "$f" ;;
    *.dsc) $REP includedsc lab33 "$f" ;;
    *.rpm)
      cp "$f" "$RPMD/"
      rpmsign --define "_gpg_name $SUB" --addsign "$RPMD/$(basename "$f")" >/dev/null
      rpm_touche=1 ;;
    *) echo "type inconnu : $f" >&2; exit 2 ;;
  esac
done
$REP export lab33                                   # renouvelle InRelease (Valid-Until)
if [ "$rpm_touche" -eq 1 ] || [ ! -f "$RPMD/repodata/repomd.xml.asc" ]; then
  createrepo_c --update "$RPMD" >/dev/null
  gpg --batch --yes --local-user "$SUB!" --detach-sign --armor "$RPMD/repodata/repomd.xml"
fi

# --- vérifications AVANT publication -------------------------------------------
gpgv --keyring "$PUB/lab33.gpg" "$PUB/debian/dists/lab33/InRelease" 2>/dev/null \
  || { echo "InRelease : signature invalide" >&2; exit 1; }
gpgv --keyring "$PUB/lab33.gpg" "$RPMD/repodata/repomd.xml.asc" "$RPMD/repodata/repomd.xml" 2>/dev/null \
  || { echo "repomd.xml : signature invalide" >&2; exit 1; }
for r in "$RPMD"/*.rpm; do
  out=$(rpmkeys --dbpath "$RPMDB" -K "$r")
  grep -q 'signatures OK' <<<"$out" || { echo "RPM non signé ou mal signé : $out" >&2; exit 1; }
done

rsync -a --delete --delay-updates -e 'ssh -i ~/.ssh/id_depot' "$PUB/" depot@lab-web.lab.local:
echo "publié : $(date -Is)"
```

> [!NOTE]
> **Pourquoi**
>
> L'ordre est la garantie : on **signe**, on **vérifie avec la clé publique
> que recevront les clients** (`gpgv` sur le trousseau publié, `rpmkeys -K` sur
> une base qui ne contient que la clé du dépôt), et on ne publie que si tout
> est bon. Une erreur de signature est ainsi bloquée sur `lab-adm` au lieu
> d'être découverte par trente clients (BF33.3). `reprepro export` à chaque
> publication renouvelle la date de validité de `InRelease`.

---

## 33.7 Break & Fix

### <a id="bf33-1"></a>**[BF33.1](README.md#bf33-1)** — « apt update refuse notre dépôt »

**Démarche de diagnostic**

```bash
# lab-db
sudo apt update 2>&1 | grep lab-web
#   W: An error occurred during the signature verification. The repository is not updated
#      and the previous index files will be used. GPG error: http://lab-web.lab.local:8033/debian
#      lab33 InRelease: The following signatures couldn't be verified because the public key
#      is not available: NO_PUBKEY 7E1F0A9B3C5D2E46
gpg --show-keys --keyid-format long /etc/apt/keyrings/lab33.gpg | grep -E 'pub|sub'
#   pub rsa4096/1A2B3C4D5E6F7A8B …   sub rsa3072/0C1D2E3F4A5B6C7D [S]   <- rien en 7E1F0A9B3C5D2E46
curl -fsS http://lab-web.lab.local:8033/ | grep -o 'lab33-[0-9]*\.asc'
#   lab33-2027.asc                                                     <- la « nouvelle clé publiée »
# lab-adm
grep SignWith ~/lab33/reprepro/conf/distributions
gpg --list-secret-keys --keyid-format long 'Dépôt lab33'
#   sec rsa4096/1A2B3C4D5E6F7A8B … [C]    Dépôt lab33 <depot@lab.local>      (+ ssb … [S])
#   sec rsa3072/7E1F0A9B3C5D2E46 … [SC]   Dépôt lab33 (2027) <depot@lab.local>
KG=$(gpg --list-secret-keys --with-colons 'Dépôt lab33 (2027)' | awk -F: '/^grp/{print $10; exit}')
gpg-connect-agent "KEYINFO $KG" /bye
#   S KEYINFO 2E14…32CB D - - - C - - -      <- C : en clair, sans phrase de passe (P : protégée)
```

**Cause racine** : le collègue a créé une **nouvelle** clé (indépendante, pas
une sous-clé de la clé existante), a basculé `SignWith` dessus et ré-exporté
le dépôt. Les clients ne connaissent que l'ancienne clé, désignée par
`Signed-By` : l'`InRelease` est signé par un inconnu, apt l'ignore. Publier
la nouvelle clé publique sur le serveur ne change rien : rien n'autorise les
clients à lui faire confiance (et c'est heureux). Bonus : la nouvelle clé n'a
**pas de phrase de passe**.

**Correctif immédiat** : revenir à la clé connue des clients, et republier.

```bash
# lab-adm
. ~/lab33/cle.env
sed -i "s/^SignWith:.*/SignWith: $SUB/" ~/lab33/reprepro/conf/distributions
~/lab33/publier.sh --sans-paquet
# lab-db
sudo apt update                                  # plus d'erreur
```

**La rotation propre**, si une nouvelle clé est réellement voulue :

1. ajouter une **sous-clé** de signature à la clé existante
   (`gpg --quick-add-key "$FPR" rsa3072 sign 2y`), exporter la clé publique
   mise à jour et la **distribuer** aux clients (trousseau mis à jour par la
   gestion de configuration, ou un paquet `lab33-archive-keyring` signé par la
   clé actuelle) ; les clients reçoivent la nouvelle sous-clé **par une voie
   qu'ils approuvent déjà** ;
2. vérifier que tout le parc a le nouveau trousseau ;
3. basculer `SignWith` sur la nouvelle sous-clé ;
4. plus tard, révoquer l'ancienne sous-clé et redistribuer.

Avec une sous-clé de la même clé principale, l'étape 1 se résume même à
redistribuer la clé publique à jour : `Signed-By` désigne le **trousseau**,
qui contient la clé principale et toutes ses sous-clés valides.

Reste à traiter la clé « 2027 » : sans phrase de passe, elle a pu être
copiée ; on la supprime (`gpg --delete-secret-and-public-key`), on retire
`lab33-2027.asc` de la publication, et `publier.sh` aurait bloqué l'erreur
dès le départ : il vérifie `InRelease` avec le trousseau **publié**
(`lab33.gpg`, l'ancienne clé), et la signature par la nouvelle clé aurait
échoué avant toute publication.

```bash
gpg --batch --yes --delete-secret-and-public-key 7E1F0A9B3C5D2E46…   # empreinte complète en mode batch
rm ~/lab33/publication/lab33-2027.asc && ~/lab33/publier.sh --sans-paquet
```

> [!NOTE]
> **Pourquoi**
>
> La confiance d'apt est **locale et explicite** : elle ne vient ni du serveur,
> ni de HTTPS, ni d'un tiers, mais du trousseau installé sur chaque client.
> C'est ce qui rend la chaîne sûre, et ce qui rend toute rotation de clé
> dépendante d'un canal de distribution vers les clients. La meilleure
> préparation est de choisir dès le départ une clé principale durable avec des
> sous-clés de signature remplaçables : la rotation d'une sous-clé ne demande
> qu'une mise à jour du trousseau, jamais une nouvelle relation de confiance.
>
> Supprimer l'erreur avec `[trusted=yes]` ou en ajoutant la nouvelle clé sans
> vérifier son origine accepterait n'importe quel dépôt signé par n'importe
> qui : c'est précisément l'attaque que la signature empêche.

---

### <a id="bf33-2"></a>**[BF33.2](README.md#bf33-2)** — « Le nouveau paquet d'outils ne s'installe pas »

**Démarche de diagnostic**

```bash
# lab-db
sudo apt install lab33-outils
#   Unpacking lab33-outils (1.0-1) ...
#   dpkg: error processing archive /var/cache/apt/archives/lab33-outils_1.0-1_all.deb (--unpack):
#    trying to overwrite '/usr/bin/lab33-sante', which is also in package lab33-sante 1.1-1
#   E: Sub-process /usr/bin/dpkg returned an error code (1)
sudo apt --fix-broken install                    # 0 upgraded, 0 newly installed… : rien à réparer côté client
dpkg -S /usr/bin/lab33-sante                     # lab33-sante: /usr/bin/lab33-sante
apt-get download lab33-outils && dpkg-deb -c lab33-outils_1.0-1_all.deb
#   ./usr/bin/lab33-journaux
#   ./usr/bin/lab33-sante                         <- un script enveloppe du même nom
dpkg-deb -f lab33-outils_1.0-1_all.deb Depends Replaces Breaks
```

**Cause racine** : `lab33-outils` livre un script `/usr/bin/lab33-sante`
(une enveloppe qui appelle l'outil avec une autre configuration), au même
chemin que le binaire du paquet `lab33-sante`. dpkg refuse qu'un paquet
écrase silencieusement un fichier d'un autre paquet, et annule le
dépaquetage : il n'y a rien de « cassé » à réparer sur le client, d'où
l'inefficacité de `--fix-broken`. Il ne s'agit pas d'un déplacement voulu (le
binaire doit rester dans `lab33-sante`) mais d'une collision de noms.
L'enveloppe appelle d'ailleurs `/usr/bin/lab33-sante.bin`, comme si
quelqu'un avait prévu de déplacer le vrai binaire par `dpkg-divert` : rien de
tel n'existe.

**Correctif** (empaquetage) : renommer l'enveloppe, déclarer la dépendance
réelle, nouvelle révision.

```bash
# lab-adm
cd ~/lab33/outils
rm racine/usr/bin/lab33-sante
cat > racine/usr/bin/lab33-sante-tous <<'EOF'
#!/bin/bash
# lab33-sante-tous — vérifie la liste complète de l'équipe
exec /usr/bin/lab33-sante -c /etc/lab33-outils/tous.conf "$@"
EOF
chmod 755 racine/usr/bin/lab33-sante-tous
sed -i -e 's/^Version: .*/Version: 1.0-2/' \
       -e 's/^Depends: .*/Depends: lab33-sante (>= 1.1)/' racine/DEBIAN/control
dpkg-deb --root-owner-group --build racine lab33-outils_1.0-2_all.deb
~/lab33/publier.sh lab33-outils_1.0-2_all.deb     # reprepro remplace 1.0-1 par 1.0-2
# lab-db
sudo apt update && sudo apt install -y lab33-outils
ls -l /usr/bin/lab33-sante*         # lab33-sante (binaire, paquet lab33-sante) et lab33-sante-tous
```

La liste `/etc/lab33-outils/tous.conf` reste à livrer : avec `dpkg-deb`, un
fichier de configuration n'est protégé que s'il est déclaré dans
`DEBIAN/conffiles` (debhelper le fait seul) ; c'est une raison de plus de
passer ce paquet à debhelper.

Si le fichier devait **vraiment** changer de paquet, la nouvelle version de
`lab33-outils` déclarerait `Replaces: lab33-sante (<< 1.2)` et
`Breaks: lab33-sante (<< 1.2)`, et `lab33-sante` 1.2 cesserait de le livrer.

**Prévention** : avant publication, vérifier qu'aucun fichier d'un nouveau
paquet n'appartient déjà à un paquet publié (une étape de `publier.sh` qui
compare `dpkg-deb -c` avec les listes du dépôt, ou des tests d'installation
dans un conteneur propre en CI), et construire même les petits paquets avec
debhelper et `lintian`.

> [!NOTE]
> **Pourquoi**
>
> `--force-overwrite` « marcherait » : le script remplacerait le binaire, le
> minuteur de `lab33-sante` lancerait l'enveloppe, et la désinstallation de
> `lab33-outils` supprimerait `/usr/bin/lab33-sante` en laissant `lab33-sante`
> installé mais sans programme. La base dpkg ne reflèterait plus la réalité.
> La seule bonne correction est dans le paquet, une fois, au lieu d'une
> intervention fragile sur chaque client.

---

### <a id="bf33-3"></a>**[BF33.3](README.md#bf33-3)** — « dnf refuse d'installer notre paquet »

**Démarche de diagnostic**

```bash
# lab-rhel
sudo dnf install lab33-sante
#   Le paquet lab33-sante-1.1-1.el9.x86_64.rpm n'est pas signé
#   Erreur : Échec de la vérification GPG
sudo dnf download lab33-sante && rpm -K lab33-sante-1.1-1.el9.x86_64.rpm
#   lab33-sante-1.1-1.el9.x86_64.rpm: digests OK          <- aucune signature
# lab-adm
rpm -qpi ~/lab33/publication/rpm/el9/x86_64/lab33-sante-1.1-1.el9.x86_64.rpm | grep Signature
#   Signature   : (none)          (signé : RSA/SHA512, <date>, Key ID 0c1d2e3f4a5b6c7d)
gpgv --keyring ~/lab33/publication/lab33.gpg ~/lab33/publication/rpm/el9/x86_64/repodata/repomd.xml{.asc,}
#   Bonne signature                                          <- les métadonnées, elles, sont signées
```

**Cause racine** : la republication « depuis un poste de secours » a remis
dans le dépôt un RPM **sans signature** (ici, la signature a été retirée),
puis a régénéré et signé correctement les métadonnées. `repo_gpgcheck`
passe, `gpgcheck` refuse le paquet. C'est le comportement voulu : un dépôt
dont les métadonnées sont signées peut contenir un paquet que personne n'a
signé.

**Correctif**

```bash
# lab-adm : on repasse le RPM par la seule voie de publication
~/lab33/publier.sh --sans-paquet
#   RPM non signé ou mal signé : …lab33-sante-1.1-1.el9.x86_64.rpm: digests OK   <- le contrôle bloque
cp ~/lab33/publication/rpm/el9/x86_64/lab33-sante-1.1-1.el9.x86_64.rpm /tmp/
~/lab33/publier.sh /tmp/lab33-sante-1.1-1.el9.x86_64.rpm
#   (copie, rpmsign, createrepo_c --update, signature de repomd.xml, vérifications, rsync)
# lab-rhel
sudo dnf clean metadata && sudo dnf install -y lab33-sante
```

Signer le RPM change son contenu (son en-tête) donc son empreinte : il faut
**toujours** régénérer les métadonnées après une signature, sinon dnf
rejetterait le fichier (*checksum doesn't match*). `publier.sh` le fait dès
qu'il ajoute un RPM.

**Prévention** : la boucle `rpmkeys -K` de `publier.sh` (« RPM non signé ou
mal signé ») aurait refusé la publication. Elle doit être **la seule** voie de
publication : pas de rsync à la main « depuis un poste de secours », et les
droits du compte `depot` réservés à la clé SSH de la station de signature.

> [!NOTE]
> **Pourquoi**
>
> Signer chaque RPM et signer les métadonnées protègent contre deux choses
> différentes : la signature du paquet le suit partout (copie, cache, autre
> dépôt, installation manuelle) et prouve son origine ; la signature des
> métadonnées protège la cohérence et la fraîcheur du dépôt (Q33.11). Une
> vérification qui ne regarde que l'une laisse passer les erreurs de l'autre.

---

## 33.8 Défi du module

<a id="d33"></a>**[D33](README.md#d33) — Un module noyau livré par le dépôt, recompilé tout seul**

*Livrable attendu : le paquet `lab33-compteur-dkms` publié et installé, et
`dkms.md`.*

On part du squelette fourni, dans un répertoire nommé comme le veut le
paquet source :

```bash
mkdir -p ~/lab33/dkms && cp -a ~/lab33/amont/lab33-compteur ~/lab33/dkms/lab33-compteur-1.0
```

**Le module** (`~/lab33/dkms/lab33-compteur-1.0/lab33_compteur.c`) :

```c
// lab33_compteur — /proc/lab33_compteur renvoie le nombre de lectures (module 33, D33)
#include <linux/atomic.h>
#include <linux/module.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>

static atomic_t lectures = ATOMIC_INIT(0);

static int montre(struct seq_file *m, void *v)
{
	seq_printf(m, "%d\n", atomic_inc_return(&lectures));
	return 0;
}

static int ouvre(struct inode *inode, struct file *file)
{
	return single_open(file, montre, NULL);
}

static const struct proc_ops ops = {
	.proc_open    = ouvre,
	.proc_read    = seq_read,
	.proc_lseek   = seq_lseek,
	.proc_release = single_release,
};

static int __init debut(void)
{
	if (!proc_create("lab33_compteur", 0444, NULL, &ops))
		return -ENOMEM;
	pr_info("lab33_compteur : chargé\n");
	return 0;
}

static void __exit fin(void)
{
	remove_proc_entry("lab33_compteur", NULL);
	pr_info("lab33_compteur : déchargé après %d lectures\n", atomic_read(&lectures));
}

module_init(debut);
module_exit(fin);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Compteur de lectures de /proc/lab33_compteur");
MODULE_VERSION("1.0");
```

**`dkms.conf`** :

```bash
PACKAGE_NAME="lab33-compteur"
PACKAGE_VERSION="1.0"
BUILT_MODULE_NAME[0]="lab33_compteur"
DEST_MODULE_LOCATION[0]="/updates/dkms"
MAKE[0]="make -C ${kernel_source_dir} M=${dkms_tree}/${PACKAGE_NAME}/${PACKAGE_VERSION}/build modules"
CLEAN="make -C ${kernel_source_dir} M=${dkms_tree}/${PACKAGE_NAME}/${PACKAGE_VERSION}/build clean"
AUTOINSTALL="yes"
```

**Le paquet** : `debian/control`

```text
Source: lab33-compteur
Section: kernel
Priority: optional
Maintainer: Mathieu <mathieu@exemple.invalid>
Build-Depends: debhelper-compat (= 13), dh-sequence-dkms
Standards-Version: 4.6.2
Rules-Requires-Root: no

Package: lab33-compteur-dkms
Architecture: all
Depends: ${misc:Depends}
Description: compteur de lectures /proc (module noyau, DKMS)
 Module noyau de démonstration du workbook : /proc/lab33_compteur renvoie
 le nombre de lectures depuis le chargement. Les sources sont compilées par
 DKMS pour chaque noyau installé.
```

`debian/rules` :

```make
#!/usr/bin/make -f
%:
	dh $@

# Le Makefile compile contre le noyau qui tourne : rien à compiler ici,
# DKMS le fera sur chaque machine, pour chaque noyau.
override_dh_auto_build override_dh_auto_clean override_dh_auto_install:
```

`debian/install` : `lab33_compteur.c Makefile usr/src/lab33-compteur-1.0/` ;
`debian/lab33-compteur-dkms.dkms` : une copie de `dkms.conf` (installée par
`dh_dkms` en `/usr/src/lab33-compteur-1.0/dkms.conf`, qui génère aussi les
scriptlets `dkms add/build/install` et la dépendance sur `dkms`) ; plus
`debian/source/format`, `debian/copyright` comme en L33.2.

```bash
cd ~/lab33/dkms
tar czf lab33-compteur_1.0.orig.tar.gz lab33-compteur-1.0      # avant de créer debian/
cd lab33-compteur-1.0      # … écrire debian/control, rules, install, .dkms, copyright, source/format
dch --create --package lab33-compteur -v 1.0-1 -D noble "Premier empaquetage."
dpkg-buildpackage -us -uc && lintian ../lab33-compteur-dkms_1.0-1_all.deb
~/lab33/publier.sh ../lab33-compteur-dkms_1.0-1_all.deb
# lab-db
sudo apt update && sudo apt install -y lab33-compteur-dkms
#   Loading new lab33-compteur-1.0 DKMS files...
#   Building for 6.8.0-48-generic
#   Building initial module for 6.8.0-48-generic
#   Done.
sudo modprobe lab33_compteur && cat /proc/lab33_compteur /proc/lab33_compteur   # 1 puis 2
dkms status
```

**Un autre noyau**

```bash
apt-cache search --names-only '^linux-headers-6\.[0-9]+\.0-[0-9]+-generic$' | sort -V | tail -3
sudo apt install -y linux-headers-6.8.0-49-generic     # une version autre que celle en cours
dkms status
#   lab33-compteur/1.0, 6.8.0-48-generic, x86_64: installed
#   lab33-compteur/1.0, 6.8.0-49-generic, x86_64: installed
```

> [!NOTE]
> **Pourquoi**
>
> L'installation des en-têtes d'un noyau déclenche le crochet
> `/etc/kernel/header_postinst.d/dkms`, qui compile **tous** les modules DKMS
> marqués `AUTOINSTALL` pour ce noyau. Le jour où le paquet `linux-image` de ce
> noyau sera installé et démarré, le module sera déjà prêt dans
> `/lib/modules/6.8.0-49-generic/updates/dkms/`. Le paquet `-dkms` est
> `Architecture: all` : il ne livre que des sources, compilées sur chaque
> machine.
>
> `dkms.md` doit dire : où lire l'échec (`/var/lib/dkms/<module>/<version>/build/make.log`,
> cité par le message d'erreur, et `dkms status` qui affiche `added` ou `built`
> au lieu d'`installed`) ; quoi
> faire si le module ne compile plus sur un nouveau noyau (démarrer l'ancien
> noyau, corriger le source, publier une nouvelle version du paquet) ; et ce
> qu'il faudrait avec Secure Boot (clé MOK générée par `dkms`, enregistrement
> par `mokutil --import` et confirmation à la console, Q33.16).

<!-- nav:début -->
---

[← Module 32](../32-fs-avances/corrige.md) · [Énoncé](README.md) · [Projet C →](../../projets/P3-astreinte/corrige.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
