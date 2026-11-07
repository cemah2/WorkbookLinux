# Module 10 — Corrigé

## 10.3 Quiz — QCM

**Q10.1** — `apt-get upgrade` *affiche « The following packages have been kept back ».*

**Réponse : b)** leur mise à jour exigerait d'installer ou de supprimer d'autres
paquets, ce qu'`upgrade` s'interdit.

::: pourquoi
`apt-get upgrade` a un contrat très précis, et c'est ce contrat qui produit le
message : **il ne supprime jamais un paquet installé et n'en installe jamais un
nouveau**. Il ne fait que remplacer une version par une autre, paquet pour
paquet.

Le cas typique est le méta-paquet `linux-generic`. Sa nouvelle version dépend de
`linux-image-6.8.0-52-generic`, qui n'est pas installé. Mettre à jour
`linux-generic` obligerait donc à **installer** un paquet supplémentaire.

`apt-get`
`upgrade` refuse, et signale le paquet comme *kept back*. `apt full-upgrade`,
qui a le droit d'installer et de supprimer, passe sans broncher. Nuance à connaître : la commande `apt upgrade` (sans `-get`) est un peu plus permissive — elle **accepte d'installer** de nouveaux paquets (c'est `apt-get upgrade --with-new-pkgs`), mais **refuse toujours d'en supprimer**. Avec `apt upgrade`, le même noyau serait donc monté; un *kept back* sous `apt upgrade` signale une suppression nécessaire (changement de nom de bibliothèque) ou un déploiement progressif (voir le piège).

Comment on tranche en trois secondes :

```bash
apt-mark showhold                   # vide ? ce n'est pas un hold
apt-get -s full-upgrade | head -30  # que faudrait-il installer/supprimer ?
```

Si `showhold` est vide et que `full-upgrade` propose des installations, c'est
bien le mécanisme ci-dessus.
:::

::: piege
a) est le piège classique : `hold` et *kept back* produisent le même symptôme
apparent mais ont des causes opposées. Un `hold` est une **décision humaine**
enregistrée dans la base dpkg ; un *kept back* est une **conséquence
arithmétique** du refus d'`upgrade` de toucher à la liste des paquets installés.
Sur les noyaux, il existe un troisième cas depuis Ubuntu 21.04 : le
**déploiement progressif** (*phased updates*), qui affiche
`The following upgrades have been deferred due to phasing:`. Celui-là se lève
tout seul en quelques jours, et on ne le force pas sans raison.
:::

---

**Q10.2** — *`apt-get dist-upgrade` contre `apt full-upgrade`.*

**Réponse : b)** aucune : ce sont deux noms de la même opération.

::: pourquoi
`full-upgrade` a été introduit par la commande `apt` en 2014 pour une raison
purement pédagogique : `dist-upgrade` faisait croire à « changer de version de
distribution », ce qu'il n'a jamais fait. Les deux appellent exactement le même
solveur avec la même autorisation : *tu peux installer et supprimer des paquets
pour arriver à l'état cible*.

Changer de version d'Ubuntu, c'est `do-release-upgrade` (paquet
`ubuntu-release-upgrader-core`), qui fait bien autre chose : il réécrit les
sources, gère les paquets obsolètes, applique des *quirks* par version et prend
un instantané des services à redémarrer. Confondre les deux en entretien est
rédhibitoire.
:::

---

**Q10.3** — *Un paquet en état `rc`.*

**Réponse : b)** le paquet est supprimé, mais ses fichiers de configuration sont
conservés.

::: pourquoi
Les deux premières lettres de `dpkg -l` sont **l'état désiré** et **l'état réel** :

* `r` = *remove* : on a demandé la suppression du paquet ;
* `c` = *config-files* : il ne reste que les conffiles.

Concrètement, `/usr/sbin/nginx` a disparu, `/etc/nginx/nginx.conf` est toujours
là, et l'entrée existe toujours dans `/var/lib/dpkg/status`. C'est voulu : si tu
réinstalles nginx demain, tu retrouves ta configuration.

Pour finir le travail :

```bash
sudo apt purge nginx          # ou : sudo dpkg --purge nginx
dpkg -l | grep '^rc'          # liste tous les résidus de ce type
sudo apt purge $(dpkg -l | awk '/^rc/ {print $2}')
```

Dans un audit, la colonne `rc` est intéressante : elle raconte l'histoire de la
machine. Un `rc` sur `apache2` et un `ii` sur `nginx`, c'est une migration qui a
eu lieu, avec la vieille configuration encore sur le disque.
:::

::: piege
Un paquet en `rc` **n'est pas** compté comme installé par la plupart des scripts
d'inventaire — mais `dpkg -l` l'affiche. D'où la consigne de L10.1 : compter avec
`dpkg-query -f '${db:Status-Abbrev}'` et filtrer, jamais avec `dpkg -l | wc -l`.
:::

---

**Q10.4** — *Quel paquet fournit `/usr/sbin/nginx` alors que nginx n'est pas
installé ?*

**Réponse : c)** `apt-file search /usr/sbin/nginx`.

::: pourquoi
La distinction est fondamentale et revient tout le temps en entretien :

* `dpkg -S` interroge `/var/lib/dpkg/info/*.list`, c'est-à-dire la liste des
  fichiers des paquets **installés sur cette machine**. Sur un paquet absent, il
  répond `dpkg-query: no path found matching pattern /usr/sbin/nginx`.
* `apt-file` interroge les index `Contents-<arch>.gz` téléchargés depuis les
  dépôts, qui décrivent le contenu de **tous les paquets disponibles**, installés
  ou non.

```bash
sudo apt install -y apt-file && sudo apt-file update
apt-file search /usr/sbin/nginx     # -> nginx: /usr/sbin/nginx
apt-file list nginx           # inverse : fichiers d'un paquet non installé
```

Attention à un détail qui piège : sur un système à `/usr` fusionné (`/bin` est un lien vers `/usr/bin`), la base dpkg n'enregistre qu'**un** des deux chemins pour chaque fichier — celui que le paquet a livré. Selon le paquet, `dpkg -S /bin/ls` ou `dpkg -S` `/usr``/bin``/ls` peut répondre `no path found matching pattern`. Le réflexe est d'essayer les deux formes, ou
`dpkg -S "$(readlink -f "$(command -v ls)")"` puis la forme courte.
:::

::: rhel
Équivalent exact sous Rocky : `dnf provides /usr/sbin/nginx`. Pas de paquet
supplémentaire à installer, les métadonnées de fichiers sont dans les dépôts.
`rpm -qf` correspond à `dpkg -S` et ne marche que sur l'installé.
:::

---

**Q10.5** — *`NO_PUBKEY` sur un dépôt tiers.*

**Réponses : b) et c)**

::: pourquoi
Décodons le message, parce que c'est tout l'exercice :

```text
W: GPG error: ... InRelease: The following signatures couldn't be verified
   because the public key is not available: NO_PUBKEY 7EA0A9C3F273FCD8
E: The repository '...' is not signed.
```

Le dépôt **est** signé : le fichier `InRelease` contient une signature valide.
Ce qu'apt dit, c'est qu'il ne possède aucune clé publique capable de la
vérifier. `7EA0A9C3F273FCD8` est l'identifiant long de la clé qui a signé.
Le `E:` final est la conséquence : apt traite un dépôt non vérifiable comme un
dépôt non signé, et refuse de s'en servir.

La conduite correcte est en trois temps :

```bash
curl -fsSL https://apt.exemple.fr/gpg -o /tmp/exemple.asc
gpg --show-keys --with-fingerprint /tmp/exemple.asc   # 1. on regarde
# 2. on compare l'empreinte à celle publiée par l'éditeur, hors du même canal
sudo install -m 0755 -d /etc/apt/keyrings
sudo gpg --dearmor -o /etc/apt/keyrings/exemple.gpg /tmp/exemple.asc
sudo chmod a+r /etc/apt/keyrings/exemple.gpg          # 3. on restreint
```

puis `Signed-By: /etc/apt/keyrings/exemple.gpg` dans la source.

L'étape 2 est celle que tout le monde saute et c'est la seule qui apporte de la
sécurité : télécharger une clé depuis le serveur dont on veut vérifier
l'authenticité et lui faire confiance parce qu'on vient de la télécharger, c'est
un raisonnement circulaire.
:::

::: piege
a) `[trusted=yes]` **désactive toute vérification** pour ce dépôt : apt accepte
n'importe quel contenu, signé ou non, modifié en route ou non. C'est exactement
la porte d'entrée d'une attaque sur le chemin. On le voit pourtant partout dans
les scripts de CI.

b) `apt-key adv --recv-keys` cumule deux fautes : la commande est dépréciée
depuis Ubuntu 22.04 (`Warning: apt-key is deprecated`), et surtout elle installe
la clé dans le trousseau **global**, où elle vaut pour tous les dépôts. Voir
Q10.6.
:::

---

**Q10.6** — *Pourquoi `apt-key add` est mort.*

**Réponse : b)** parce qu'une clé ajoutée ainsi vaut pour **tous** les dépôts de
la machine.

::: pourquoi
Avant `Signed-By`, apt avait un trousseau unique : `/etc/apt/trusted.gpg` et
`/etc/apt/trusted.gpg.d/*.gpg`. La vérification d'un dépôt était « la signature
de ce `InRelease` est-elle faite par **une** des clés du trousseau ? ». Pas
« par **la** clé de ce dépôt ».

Conséquence concrète : tu ajoutes la clé d'un petit dépôt tiers pour un outil de
monitoring. Cet éditeur est compromis, ou simplement malveillant. Il lui suffit
de publier un paquet `libc6` version 99 signé de sa clé, et de s'arranger pour
que ton apt le voie — un DNS empoisonné, un miroir, un dépôt à lui déclaré plus
prioritaire. Ton système accepte la signature : elle est dans le trousseau.

`Signed-By` change le modèle : chaque source déclare **quelle clé, et rien
d'autre**, peut signer son `InRelease`. Compromettre le dépôt de monitoring ne
donne plus le droit de fournir `libc6`. C'est du moindre privilège appliqué à la
distribution logicielle.

Deuxième raison, plus prosaïque : `apt-key` reposait sur un format de trousseau
GnuPG hérité (`pubring.gpg`) qui n'est plus celui de GnuPG 2.2+, et personne ne
savait plus quelle clé venait d'où ni quand elle expirait.
:::

---

**Q10.7** — *`Installed: 1.2.0`, `Candidate: 1.0.0`, priorité 1001.*

**Réponse : b)** rétrograder le paquet en 1.0.0.

::: pourquoi
Deux notions différentes se lisent dans cette sortie, et il faut les séparer :

* la **version candidate** est celle qu'apt installerait si tu tapais
  `apt install outil-lab` sans préciser de version. Elle est choisie par la plus
  haute priorité, pas par le plus grand numéro de version ;
* la ligne `*** 1.2.0 100` marque la version **installée**.

Ici, l'épinglage donne 1001 à la 1.0.0. Une priorité **strictement supérieure à
1000** a une propriété unique : elle autorise apt à **descendre** une version.
En dessous, apt considère qu'une rétrogradation est forcément une erreur et
refuse.

La simulation le confirme, mot pour mot :

```console
$ apt-get -s install outil-lab
The following packages will be DOWNGRADED:
  outil-lab
0 upgraded, 0 newly installed, 1 downgraded, 0 to remove and 1 not upgraded.
Inst outil-lab [1.2.0] (1.0.0 LabInterne:stable [all])
```
:::

::: piege
La frontière 1000 est la question d'entretien classique sur `apt_preferences`,
et l'erreur est toujours la même : écrire `Pin-Priority: 999` en pensant
« presque le maximum ». À 999, apt **garde** la 1.0.0 si elle est déjà installée,
mais **refuse** de redescendre depuis la 1.2.0. Le fichier a l'air correct, il
passe la relecture, et il ne sert à rien le jour où on en a besoin. C'est
exactement ce que teste L10.3.
:::

---

**Q10.8** — *`Package: *` / `Pin: release a=noble` / `Pin-Priority: 1001`.*

**Réponse : b)** apt propose de rétrograder tout ce qui a été installé depuis
`noble-updates` ou `noble-security`.

::: pourquoi
Trois mots font les dégâts, et chacun mérite qu'on s'y arrête.

`Package: *` : l'épinglage s'applique à **tous** les paquets de la machine.

`Pin: release a=noble` : `a=` est l'**archive**, c'est-à-dire la suite. Sur
Ubuntu 24.04, la suite `noble` est l'archive **figée au jour de la sortie** :
elle ne bouge plus jamais. Les correctifs vivent dans les archives *séparées*
`noble-updates` et `noble-security`. Viser `a=noble` revient donc à viser
« l'état du 25 avril 2024 ».

`Pin-Priority: 1001` : au-dessus de 1000, donc rétrogradation autorisée.

Résultat, sur une machine à jour :

```console
$ sudo apt upgrade
The following packages will be DOWNGRADED:
  apt base-files binutils bsdutils coreutils curl dpkg e2fsprogs
  git gnupg gzip less libc6 ... (plusieurs centaines)
```

Y compris `apt`, `dpkg` et `libc6`. Si l'opérateur répond `y`, la machine repart
à l'état de la release, perd tous ses correctifs de sécurité, et il est très
possible qu'un `apt` rétrogradé pendant que `dpkg` l'est aussi laisse la
transaction à moitié faite.

L'intention de l'auteur était probablement « ne pas prendre de nouveautés ».
La bonne écriture est l'inverse : on ne rétrograde pas, on **empêche de
monter**, et on ne vise pas `*` :

```ini
Package: postgresql* 
Pin: version 16*
Pin-Priority: 1001
```
:::

::: piege
Confusion `a=` / `o=` / `n=` : `a=noble-security` est l'archive (la suite),
`o=Ubuntu` l'origine (l'éditeur), `n=noble` le nom de code, `l=Ubuntu` le label,
`c=main` le composant. `apt-cache policy` sans argument imprime la ligne
`release v=24.04,o=Ubuntu,a=noble-security,n=noble,l=Ubuntu,c=main,b=amd64`
pour chaque dépôt : c'est là qu'on lit les valeurs réellement utilisables, et
nulle part ailleurs.
:::

---

**Q10.9** — *`apt install` propose de supprimer 40 paquets dont `ubuntu-server`.*

**Réponse : b)** un conflit de dépendances avec un dépôt tiers qui fournit une
bibliothèque système dans une version incompatible.

::: pourquoi
Le solveur d'apt n'a pas de notion de « paquet important ». Il cherche un état
cohérent qui satisfait ta demande, et si le seul chemin passe par la suppression
de quarante paquets, il te le propose. Le scénario réel est presque toujours le
même :

1. un dépôt tiers (un éditeur, un PPA, un miroir interne) publie sa propre
   version d'une bibliothèque très partagée — `libssl`, `libicu`, `libstdc++` ;
2. son paquet applicatif dépend strictement de **sa** version ;
3. sa version entre en conflit avec celle de la distribution ;
4. pour satisfaire la demande, apt doit retirer tout ce qui dépend de la
   version distribution — c'est-à-dire la moitié du système, dont les
   méta-paquets `ubuntu-server` ou `ubuntu-minimal`.

Le réflexe est de **lire la sortie avant de répondre**, et de chercher d'où
vient le paquet fautif :

```bash
apt-get -s install <paquet> | sed -n '/REMOVED/,/^[0-9]/p'
apt-cache policy <paquet-en-conflit>       # quel dépôt le fournit ?
apt-cache policy | grep -B1 -A2 '500 http' # qui a quelle priorité ?
```

Et la règle de production : **la présence d'un méta-paquet dans la liste des
suppressions est un signal d'arrêt**. On n'appuie pas sur `y`.
:::

::: piege
c) « la base dpkg est corrompue » est la mauvaise piste favorite. Une base dpkg
cassée ne produit pas ce message, elle produit `E: dpkg was interrupted...` ou
des erreurs de parsing. Le solveur, lui, fonctionne parfaitement : il fait
exactement ce qu'on lui a demandé, sur des données qui sont contradictoires.
:::

---

**Q10.10** — *Prompt de conffile, réponse `N`.*

**Réponse : a)** ta version reste en place, celle du paquet est écrite en
`.dpkg-dist`.

::: pourquoi
Le mécanisme complet, qui vaut la peine d'être su par cœur :

dpkg enregistre, pour chaque conffile, la **somme MD5 telle qu'elle était à
l'installation** (visible avec `dpkg -s <paquet>`, section `Conffiles:`). Lors
d'une mise à jour, il compare trois choses :

| Comparaison | Décision |
|---|---|
| fichier sur disque = ancien MD5 | tu n'as rien touché → remplacement silencieux |
| nouveau paquet = ancien MD5 | le mainteneur n'a rien changé → on ne touche à rien |
| les deux ont changé | **conflit** → le prompt |

Le nommage des sauvegardes suit la logique « le fichier qui reste garde le nom
d'origine, l'autre prend un suffixe » :

* `N` (garder le tien) → le nouveau est déposé à côté en **`.dpkg-dist`** ;
* `Y` (prendre celui du paquet) → le tien est sauvegardé en **`.dpkg-old`**.

Et le travail d'après-mise-à-jour, que personne ne fait :

```bash
sudo find /etc -name '*.dpkg-dist' -o -name '*.dpkg-old' -o -name '*.ucf-dist'
diff -u /etc/ssh/sshd_config /etc/ssh/sshd_config.dpkg-dist
```

Un `.dpkg-dist` sur `sshd_config` peut contenir une directive de durcissement
que tu n'auras jamais si tu ne la relis pas. Le prompt ne protège que le présent.
:::

---

**Q10.11** — *Mise à jour non interactive d'un parc.*

**Réponses : b) et c)**

::: pourquoi
La combinaison de production est :

```bash
sudo DEBIAN_FRONTEND=noninteractive apt-get -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  upgrade
```

`--force-confold` : en cas de conflit, garde le fichier existant. C'est la
décision sûre : on ne perd jamais une configuration locale sans intervention
humaine, et on récupère la version du mainteneur dans le `.dpkg-dist` pour la
relire plus tard.

`--force-confdef` : accepte l'action par défaut **quand dpkg en propose une**.
Sans lui, certains cas (un conffile supprimé localement, par exemple) restent
bloquants même avec `--force-confold`. Les deux se mettent toujours ensemble ;
`confdef` d'abord, parce qu'il traite les cas où il y a un défaut, et `confold`
tranche le reste.

`DEBIAN_FRONTEND=noninteractive` complète le dispositif côté `debconf`, qui est
un autre mécanisme de question (celui des écrans bleus).
:::

::: piege
a) `--force-confnew` écrase silencieusement toutes les configurations locales du
parc. Sur 200 serveurs, c'est un incident majeur découvert au redémarrage d'un
service.

b) `--force-all` est le bouton rouge : il désactive **toutes** les protections
de dpkg, y compris les vérifications de dépendances et les refus d'écraser les
fichiers d'un autre paquet. Il existe pour sortir d'une situation désespérée,
manuellement, en sachant ce qu'on fait — jamais dans un automate.
:::

---

**Q10.12** — *`E: dpkg was interrupted...`*

**Réponse : a)** apt a détecté une transaction dpkg non terminée et refuse de
lancer une nouvelle transaction par-dessus.

::: pourquoi
Le mécanisme est très concret. dpkg journalise ses transactions en écrivant des
fichiers **dont le nom est une suite de chiffres** dans `/var/lib/dpkg/updates/`.
En fonctionnement normal, ces fichiers sont créés puis consommés, et le
répertoire est vide entre deux transactions.

Au démarrage, apt appelle `debSystem::CheckUpdates()` : si un fichier au nom
numérique traîne là, c'est qu'une transaction a été interrompue — coupure de
courant, `kill -9`, disque plein, conteneur arrêté en plein `apt`. apt refuse
alors de poser son verrou et affiche ce message unique.

Le correctif est littéralement celui que le message donne :

```bash
sudo dpkg --configure -a
```

`--configure -a` reprend **tous** les paquets déballés mais non configurés,
rejoue le journal et vide `/var/lib/dpkg/updates/`. Si un `postinst` échoue à
nouveau, dpkg le dit et il faut traiter la cause — c'est exactement BF10.1.

À ne pas confondre avec le verrou :
`E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 1234`
qui signale un `apt` **en cours d'exécution** ailleurs (souvent
`unattended-upgrades`, souvent au démarrage de la machine). Dans ce cas on
attend, on ne supprime pas le fichier de verrou.
:::

---

**Q10.13** — *Revenir en arrière sur Rocky 9.*

**Réponse : b)** `dnf history list`, puis `dnf history undo <id>`.

::: pourquoi
C'est la différence la plus visible entre les deux écosystèmes, et elle mérite
d'être comprise plutôt que récitée.

`dnf` tient une base de transactions dans `/var/lib/dnf/history.sqlite`. Chaque
`install`, `upgrade`, `remove` reçoit un numéro, une date, l'utilisateur, la
ligne de commande et la liste exacte des RPM entrés et sortis.

```bash
dnf history list                 # les dernières transactions
dnf history info 42              # détail de la 42 : paquets, versions, commande
sudo dnf history undo 42         # annule exactement cette transaction
sudo dnf history rollback 41     # remonte l'état jusqu'à la fin de la 41
```

`undo` annule **une** transaction ; `rollback` rejoue à l'envers toutes les
transactions postérieures à celle indiquée.

Ce que `undo` ne sait **pas** faire, et qu'il faut dire en entretien :

* il ne restaure pas les **données** : une base migrée par un `postinstall`
  reste migrée ;
* il ne restaure pas les fichiers de configuration modifiés après coup ;
* il échoue si l'ancien RPM n'est plus disponible dans un dépôt ou dans le cache
  (`keepcache=1` dans `/etc/dnf/dnf.conf` change tout, ici) ;
* il ne défait pas un `dnf module enable`.

C'est donc un filet de sécurité sur les **paquets**, pas un retour arrière du
système. La vraie garantie reste le snapshot de machine ou de volume.
:::

::: piege
c) `rpm -e --rollback` a existé (avec `--repackage`), n'a jamais fonctionné de
façon fiable et est abandonné depuis longtemps. Le citer signale qu'on a lu une
documentation de 2007.
:::

---

**Q10.14** — *`rpm -V httpd`.*

**Réponse : b)** la configuration a été modifiée, ce qui est normal ; le journal
a disparu, ce qui l'est aussi.

::: pourquoi
`rpm -V` compare l'état du disque aux métadonnées stockées dans la base RPM
locale (`/var/lib/rpm`), sans réseau. Neuf colonnes, un `.` quand l'attribut est
conforme :

```text
S.5....T.  c /etc/httpd/conf/httpd.conf
SM5DLUGTP
|||||||||
||||||||`- P : capabilities
|||||||`-- T : mtime
||||||`--- G : groupe
|||||`---- U : propriétaire
||||`----- L : cible du lien symbolique
|||`------ D : numéros majeur/mineur d'un périphérique
||`------- 5 : somme de contrôle du contenu
|`-------- M : mode (permissions + type)
`--------- S : taille
```

La lettre après les neuf colonnes est le **type de fichier** : `c` = conffile,
`d` = documentation, `l` = licence, `g` = fichier « fantôme » (créé à
l'exécution, jamais livré), rien = fichier ordinaire.

Donc `S.5....T. c /etc/httpd/conf/httpd.conf` se lit : « le fichier de
configuration a changé de taille, de contenu et de date ». C'est exactement ce
qu'on attend d'un serveur configuré. Et `missing /var/log/httpd/error_log` est
un `%ghost` : le RPM déclare le chemin pour en fixer les permissions, mais le
fichier est créé par le service et supprimé par logrotate.

L'usage sérieux de `rpm -V`, c'est de chercher les **binaires** modifiés :

```bash
rpm -Va --noconfig --noghost 2>/dev/null
rpm -Va | awk '$2 != "c" && $1 ~ /5/'   # contenu modifié hors conffile
```

Un `5` sur `/usr/sbin/httpd`, là, c'est un incident de sécurité.
:::

::: piege
d) est faux et important : `rpm -V` est **hors ligne**. Il compare au contenu de
la base locale, pas au dépôt. Corollaire désagréable : si un attaquant a accès à
root, il peut modifier `/var/lib/rpm` et rendre `rpm -V` menteur. Un contrôle
d'intégrité sérieux se fait avec une base de référence externe (AIDE, ou les
sommes du dépôt).
:::

---

**Q10.15** — *`dnf install nodejs` installe la 16 au lieu de la 20.*

**Réponse : b)** aucun flux n' est activé : les versions modulaires sont filtrées, `dnf` installe le paquet non modulaire (16).

::: pourquoi
Les **modules** (AppStream, RHEL 8 et 9) permettent au dépôt de contenir
plusieurs versions majeures du même logiciel. Chaque version majeure est un
**flux** (*stream*). Sur RHEL/Rocky 9, la version initiale (Node.js 16) est livrée en RPM **non modulaire**, les suivantes (18, 20, 22) en flux, **sans flux par défaut**. Tant qu'aucun flux n'est activé, les paquets modulaires sont filtrés : `dnf install nodejs` ne voit que la 16. Et à l'inverse, **activer un flux masque tout le reste**, y compris pour les dépendances.

```bash
dnf module list nodejs
# Name     Stream   Profiles          Summary
# nodejs   18       common [d], ...   Javascript runtime
# nodejs   20       common [d], ...   Javascript runtime
# nodejs   22       common [d], ...   Javascript runtime
#   [e] = enabled, [d] = default, [x] = disabled, [i] = installed

sudo dnf module reset nodejs        # on repart de zéro
sudo dnf module enable nodejs:20    # on choisit explicitement
sudo dnf install nodejs
```

Le symptôme le plus déroutant n'est pas celui-ci, c'est
`No match for argument: nodejs` alors que `dnf search nodejs` le trouve : un
flux a été **désactivé** (`dnf module disable`), et le paquet devient invisible
sans que rien n'explique pourquoi. Le premier réflexe sur RHEL devant un paquet
« qui n'existe pas » est `dnf module list <nom>`.

À savoir pour le contexte : la modularité est en voie de retrait côté Red Hat
(RHEL 10 ne la reconduit pas de la même façon), mais RHEL/Rocky 8 et 9 sont
déployés pour dix ans. On la rencontrera longtemps.
:::

---

**Q10.16** — *`sudo make install` dans `/usr` sur un serveur de production.*

**Réponses : a), b) et d)**

::: pourquoi
Les trois objections sont de nature différente, et il faut savoir les formuler
séparément :

**a) Traçabilité.** `make install` copie des fichiers. Rien ne l'enregistre :
ni `dpkg -S`, ni `rpm -qf`, ni aucun inventaire ne retrouveront ces fichiers.
Six mois plus tard, personne ne sait d'où vient `/usr/bin/redis-server` ni quelle
version c'est. Sur un audit de vulnérabilité, ce binaire est invisible : les
scanners travaillent sur la liste des paquets.

**b) Collision.** `/usr` appartient au gestionnaire de paquets. Le jour où la
distribution livre son propre `redis-server`, dpkg refuse d'écraser un fichier
qu'il ne connaît pas (`trying to overwrite '/usr/bin/redis-server', which is
also in package ...`), ou pire, l'écrase et ton binaire disparaît sans
avertissement.

**d) Désinstallation.** `make uninstall` n'est pas une obligation : c'est une
convention que beaucoup de projets ne respectent pas, et quand elle existe, elle
n'est valable que si l'arborescence de build est encore là, configurée
exactement pareil. En pratique, on désinstalle à la main, à partir d'une liste
qu'on n'a pas.

Ce qui *n'est pas* une objection : c) `make install` fonctionne parfaitement en
root, c'est même le cas nominal.

La réponse professionnelle est de compiler puis d'**empaqueter** — c'est L10.4 :

```bash
./configure --prefix=/usr/local
make
make install DESTDIR="$PWD/staging"   # racine factice, rien sur le système
# on ajoute staging/DEBIAN/control, puis :
dpkg-deb --build --root-owner-group staging monoutil_1.4-1_amd64.deb
```

Trente secondes de travail en plus, et l'outil rentre dans l'inventaire, se
désinstalle, se déploie avec Ansible et se retrouve dans `dpkg -S`.
:::

::: piege
`checkinstall` promettait exactement ça en automatique : il exécute
`make install` sous surveillance et fabrique un paquet à partir des fichiers
touchés. Il n' est quasiment plus maintenu (dernière version publiée en 2010, encore présent dans `universe` sous forme d'instantané Git),
il rate les fichiers créés indirectement, produit des métadonnées bancales et
tourne en root sur du code de build arbitraire. On cite son existence, on ne
s'en sert pas. Les outils actuels sont `fpm`, `nfpm`, ou `dpkg-deb` à la main
comme ci-dessus.
:::

---

**Q10.17** — *`error: externally-managed-environment`.*

**Réponse : b)** paquet apt s'il existe, sinon venv, sinon `pipx`.

::: pourquoi
Ce message vient de la PEP 668. Ubuntu 24.04 dépose un fichier
`/usr/lib/python3.12/EXTERNALLY-MANAGED` qui dit à pip : « cet interpréteur
appartient au gestionnaire de paquets système, ne le modifie pas ».

Le problème qu'il résout est réel et grave : `sudo pip install` écrit dans
`/usr/local/lib/python3.12/dist-packages`, qui passe **avant** `/usr/lib/python3/dist-packages` ( où apt a installé ses paquets) dans `sys.path`. pip ne
connaît pas dpkg ; il masque ou remplace une bibliothèque dont dépend un outil système écrit
en Python — sur Ubuntu, cela inclut `apt_pkg`, `netplan`, `cloud-init`,
`unattended-upgrades`. On casse alors le gestionnaire de paquets avec le
gestionnaire de paquets d'un autre langage, et on ne peut plus réparer avec apt.

Les trois bonnes réponses, dans l'ordre de préférence :

```bash
sudo apt install python3-requests       # 1. le paquet distribution existe
python3 -m venv ~/app/.venv             # 2. une application : son venv à elle
~/app/.venv/bin/pip install requests
sudo apt install pipx && pipx install httpie   # 3. un outil CLI : pipx
```

`pipx` crée un venv par outil et expose juste l'exécutable : c'est le bon modèle
pour `ansible`, `httpie`, `black` sur un poste d'admin.

Même raisonnement côté Node : `npm install -g` sur un serveur partagé installe
dans `/usr/lib/node_modules` sans aucune trace pour le gestionnaire de paquets,
et la première mise à jour de `nodejs` par apt règle le problème à sa façon.
:::

::: piege
a) et c) « fonctionnent » — et c'est bien le problème. `--break-system-packages`
a été nommé ainsi exprès : le nom **est** l'avertissement. Sur un poste de dev
jetable, pourquoi pas. Sur un serveur, c'est la ligne qu'on retrouvera dans le
post-mortem.
:::

---

**Q10.18** — *Reproductibilité à six mois d'intervalle.*

**Réponses : a), b) et d)**

::: pourquoi
Le point à comprendre : **`apt install nginx` n'est pas une commande
déterministe**. Elle veut dire « la version que mon dépôt juge candidate
aujourd'hui ». Rejouée dans six mois sur le même dépôt, elle installe autre
chose. Trois leviers, du plus faible au plus fort :

**a) Épingler les versions.** Contrôle fin, paquet par paquet, mais ne protège
que ce que tu as pensé à épingler. Les dépendances transitives bougent quand
même.

**b) Figer le dépôt.** C'est le seul levier qui donne une vraie garantie, parce
qu'il fige *tout* l'ensemble cohérent. Trois formes :

```text
snapshot.ubuntu.com     miroir daté officiel : URI figée à une date
apt-mirror / aptly      miroir local, snapshots nommés et promus
un registre interne     seul le dépôt validé est déclaré sur les machines
```

**d) Le manifeste.** Ce n'est pas une garantie mais une **preuve** :

```bash
dpkg-query -W -f '${Package}=${Version}\n' | sort > manifeste-$(date +%F).txt
diff manifeste-2026-03-01.txt manifeste-2026-09-01.txt
```

Sans manifeste, quand l'application casse après un déploiement, on ne sait même
pas *ce qui* a changé. C'est la première chose qu'on met en place, parce qu'elle
coûte une ligne.

**c)** est l'inverse de la reproductibilité : `apt upgrade -y` au démarrage
rend l'état de la machine dépendant de l'heure à laquelle elle a démarré. Deux
machines du même groupe divergent. C'est précisément le problème que le module
cherche à résoudre.
:::

---

## 10.4 Quiz — questions ouvertes

**QO10.1** — *La chaîne complète d'un `sudo apt install nginx`.*

**Réponse attendue**

1. **Lecture de la configuration.** apt lit `/etc/apt/apt.conf`,
   `/etc/apt/apt.conf.d/*`, `/etc/apt/preferences` et
   `/etc/apt/preferences.d/*`, puis `/etc/apt/sources.list` et
   `/etc/apt/sources.list.d/*.{list,sources}`.
2. **Verrouillage.** apt prend `/var/lib/dpkg/lock-frontend`, et vérifie
   `/var/lib/dpkg/updates/` (transaction interrompue ?).
3. **Résolution.** À partir des index locaux
   (`/var/lib/apt/lists/*_Packages`), apt calcule la version candidate par les
   priorités, puis l'ensemble des dépendances à installer. Rien n'est
   téléchargé à ce stade.
4. **Téléchargement.** Les `.deb` arrivent dans
   `/var/cache/apt/archives/partial/` puis `/var/cache/apt/archives/`. Chaque
   fichier est vérifié par sa **somme SHA256 lue dans l'index** — l'index, lui,
   ayant été validé par la signature GPG au moment du `apt update`.
5. **Passage à dpkg.** apt appelle `dpkg --unpack` pour chaque paquet, dans un
   ordre calculé pour respecter les `Pre-Depends`, puis `dpkg --configure`.
6. **Déballage.** dpkg extrait `data.tar.*`, écrit les fichiers, enregistre la
   liste dans `/var/lib/dpkg/info/nginx.list` et les sommes des conffiles
   dans `/var/lib/dpkg/status`.
7. **Configuration.** dpkg exécute `postinst`, qui déclenche `debconf` si
   besoin, crée l'utilisateur système, active l'unité systemd
   (`nginx.service`) via les *triggers* et la démarre.
8. **Traces.** `/var/log/apt/history.log` (transaction, ligne de commande,
   utilisateur), `/var/log/apt/term.log` (sortie brute de dpkg),
   `/var/log/dpkg.log` (une ligne par changement d'état), `journalctl -u nginx`
   pour le service.

::: pourquoi
Ce qu'il faut retenir de cette chaîne, c'est **où se fait la sécurité**. Beaucoup
croient que chaque `.deb` est signé : c'est faux dans le monde Debian. Ce qui est
signé, c'est le fichier `InRelease` du dépôt. Il contient les sommes des fichiers
`Packages`, qui contiennent les sommes des `.deb`. La confiance se propage par
cette chaîne de hachages. Conséquence pratique et non intuitive : un `.deb`
téléchargé à la main et installé avec `dpkg -i` **n'est vérifié par rien**.

Deuxième point, la séparation `unpack` / `configure`. Elle existe parce que des
paquets ont des dépendances circulaires à la configuration : dpkg déballe tout,
puis configure dans un ordre qui satisfait les contraintes. C'est aussi ce qui
rend l'état `iU` possible — déballé, pas configuré — et donc réparable par
`dpkg --configure -a` sans rien retélécharger.
:::

---

**QO10.2** — *`apt upgrade` ou `apt full-upgrade` en production ?*

**Réponse attendue**

`apt upgrade` ne fait que remplacer des versions : il ne supprime
jamais de paquet (et `apt-get upgrade`, plus strict, n'en installe pas non plus de nouveau). `apt full-upgrade` (alias `dist-upgrade`) a le droit d'installer et de supprimer pour atteindre l'état cible.

Exemple concret : une bibliothèque qui change de nom de paquet à
la montée de version (`libssl3` → `libssl3t64` lors de la transition `time64` de 24.04). Installer la nouvelle exige de
**supprimer** l'ancienne : `upgrade` refuse et affiche *kept back* ;
`full-upgrade` fait la transition. Autre exemple, propre à `apt-get upgrade` : un nouveau `linux-image-*` tiré par `linux-generic`, qui exige d'**installer** un paquet.

En production : `upgrade` dans l'automate, `full-upgrade` à la main. Un
automate qui a le droit de supprimer des paquets finit un jour par supprimer le
mauvais, et personne ne sera là à 3 h du matin pour lire la liste.

::: pourquoi
La raison profonde est une question de **surface de décision**. `upgrade` a une
propriété vérifiable : l'ensemble des paquets installés est invariant. On peut
donc le laisser tourner sans supervision et savoir exactement ce qui peut
arriver. `full-upgrade` n'a pas cette propriété : son résultat dépend de l'état
des dépôts au moment de l'exécution. C'est le même raisonnement qui fait qu'on
autorise un déploiement automatique et pas une migration de schéma automatique.

Corollaire honnête, qu'il faut donner : sur une machine qui ne fait jamais que
des `upgrade`, les paquets *kept back* s'accumulent ( les noyaux, si c'est `apt-get upgrade` qui tourne; les transitions de bibliothèques dans tous les cas). Il faut
donc une revue périodique — c'est exactement ce que produit le script du défi D10.
:::

---

**QO10.3** — *Ajouter le dépôt Docker correctement.*

**Réponse attendue**

```bash
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /tmp/docker.asc

# on REGARDE la clé avant de lui faire confiance
gpg --show-keys --with-fingerprint /tmp/docker.asc
# empreinte attendue, publiée par Docker :
# 9DC8 5822 9FC7 DD38 854A  E2D8 8D81 803C 0EBF CD88

sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg /tmp/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.gpg

cat <<EOF | sudo tee /etc/apt/sources.list.d/docker.sources
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.gpg
EOF

sudo apt update
apt-cache policy docker-ce | head -5    # on vérifie l'origine
```

Ce qu'on vérifie avant de faire confiance : l'**empreinte** de la clé, comparée
à celle publiée par l'éditeur sur un canal distinct de celui du téléchargement
(documentation officielle, dépôt Git signé, annonce). Et on note la date
d'expiration de la clé : une clé qui expire, c'est un `apt update` qui casse un
matin sans que rien n'ait changé chez toi.

::: pourquoi
Trois détails techniques que les tutoriels ratent :

**`install -m 0755 -d` plutôt que `mkdir -p`** : `/etc/apt/keyrings` doit être
traversable par l'utilisateur `_apt`, qui n'est pas root. Un `umask` restrictif
sur une machine durcie produit un répertoire en 0700 et un
`Could not open file ... Permission denied` incompréhensible.

**`chmod a+r` sur le trousseau** : même raison. apt lâche ses privilèges vers
`_apt` pour télécharger. C'est une mesure de défense en profondeur, et c'est
elle qui rend les permissions du keyring importantes.

**`--dearmor`** : le fichier publié est en ASCII armuré (`-----BEGIN PGP PUBLIC
KEY BLOCK-----`). apt sait lire les deux formats, à condition que l'extension
corresponde : `.asc` pour l'armuré, `.gpg` pour le binaire. Un fichier armuré
nommé `.gpg` produit `The following signatures couldn't be verified` — une
erreur particulièrement pénible à diagnostiquer parce qu'elle ressemble à un
`NO_PUBKEY`.
:::

---

**QO10.4** — *Un épinglage `Package: *` / `Pin: version 16*`.*

**Réponse attendue**

Ce fichier dit : « pour **tous les paquets** de la machine, toute version
commençant par 16 reçoit la priorité 1001 ». Il ne parle pas de PostgreSQL du
tout — il parle de tout ce qui a un numéro de version commençant par `16`. Sur
Ubuntu 24.04, cela touche des dizaines de paquets sans rapport, et comme 1001 >
1000, apt est autorisé à les **rétrograder**.

Détection :

```bash
grep -r . /etc/apt/preferences.d/ /etc/apt/preferences 2>/dev/null
apt-cache policy | head -20              # priorités réellement appliquées
apt-cache policy <un-paquet-au-hasard>   # 1001 là où on n'attend rien ?
apt-get -s upgrade | grep -i downgrade
```

Écriture correcte :

```ini
# /etc/apt/preferences.d/50-postgresql.pref
# Gel PostgreSQL 16 — ticket CHG-2201 — revue le 2026-12-01
Package: postgresql postgresql-16 postgresql-client-16 postgresql-common
Pin: version 16*
Pin-Priority: 1001
```

::: pourquoi
Trois règles se déduisent de cet exemple, et elles couvrent la quasi-totalité
des incidents d'épinglage :

1. **`Package: *` ne s'écrit presque jamais.** Le champ `Package:` accepte une
   liste de noms et des globs. On nomme les paquets. Si on ne sait pas les
   nommer, c'est qu'on ne sait pas ce qu'on gèle.
2. **Un épinglage est daté et justifié.** Deux lignes de commentaire avec le
   ticket et la date de revue. Un gel sans date devient permanent, et c'est comme
   ça qu'on se retrouve avec une faille non corrigée pendant onze semaines.
3. **On vérifie l'effet, pas l'intention.** `apt-cache policy` sur plusieurs
   paquets *hors périmètre* est le seul contrôle valable. Le fichier n'a jamais
   l'air faux ; c'est son effet qui l'est.
:::

::: piege
Subtilité de `Pin: version` : la comparaison est faite sur la chaîne avec des
jokers `*`, **pas** avec les règles de comparaison de versions Debian. `16*`
attrape `16.1`, mais aussi `16abc` et `160.2`. Pour un vrai encadrement, on
épingle sur la release (`Pin: release a=noble`) ou on nomme la version exacte.
:::

---

**QO10.5** — *`apt-mark hold` contre l'épinglage.*

**Réponse attendue**

| | `apt-mark hold` | épinglage |
|---|---|---|
| Stockage | base dpkg (`/var/lib/dpkg/status`, champ `Status: hold`) | fichiers texte `/etc/apt/preferences.d/` |
| Se voit avec | `apt-mark showhold`, `dpkg --get-selections` | `grep -r . /etc/apt/preferences.d/` |
| Granularité | tout ou rien sur un paquet | version, release, origine, glob |
| Effet | interdit tout changement d'état du paquet | change la **version candidate** |
| `apt upgrade` | ignore le paquet | prend la candidate, donc ne bouge pas |
| `apt install -y p=1.2` | `E: Held packages were changed and -y was used without --allow-change-held-packages.` | fonctionne : la demande explicite prime |
| Sauvegardé par | rien de standard | `/etc/` est dans la sauvegarde et le Git de conf |
| Survit à `purge` + réinstall | non | oui, le fichier reste |

Critère de choix : `hold` pour un gel **court et manuel** (« ne touche pas à ça
pendant la maintenance de ce soir »). Épinglage pour une **politique** qui doit
être versionnée, déployée par Ansible, relue et auditée.

::: pourquoi
La différence de fond est *où vit l'information*. Un `hold` vit dans la base
dpkg : il est invisible dans une sauvegarde de `/etc`, invisible dans le dépôt
Git de configuration, invisible dans une revue de code. Il est posé en une
commande, sur une machine, par une personne — et il survit aux redémarrages, aux
mises à jour et au départ de cette personne. C'est exactement le scénario du
défi D10 : onze semaines de faille parce que personne ne savait qu'un `hold`
traînait.

L'épinglage vit dans `/etc`. Il entre dans la sauvegarde, dans le Git, dans la
revue, et Ansible peut le poser et le retirer de façon déclarative.

Nuance importante pour l'entretien : **aucun des deux n'est une interdiction
absolue**. Le `hold` bloque les opérations en lot et les commandes `-y`, mais
`apt install outil-lab=1.2.0` en interactif affiche simplement
`Do you want to continue? [Y/n]`. L'épinglage, lui, ne fait que déplacer la
candidate : une demande de version explicite passe outre. Pour un vrai blocage,
il faut une priorité **négative** (`Pin-Priority: -1`), qui rend la version
non installable.
:::

---

**QO10.6** — *Politique de mise à jour sur 200 serveurs.*

**Réponse attendue**

Ce qu'on automatise :

* le rafraîchissement des index, tous les jours ;
* l'application des mises à jour **de sécurité uniquement**
  (`${distro_id}:${distro_codename}-security`), sur des fenêtres décalées par
  groupe pour ne pas mettre tout le parc à jour au même instant ;
* la collecte quotidienne d'un manifeste
  (`dpkg-query -W -f '${Package}=${Version}\n'`) centralisé.

Ce qu'on n'automatise jamais :

* `full-upgrade` / `dist-upgrade` ;
* le changement de version de distribution ;
* les paquets applicatifs métier (liste d'exclusion explicite et documentée) ;
* le **redémarrage**.

Le redémarrage : `unattended-upgrades` avec `Automatic-Reboot "false"`, et on
s'appuie sur `/var/run/reboot-required` (+ `/var/run/reboot-required.pkgs`) pour
alimenter un indicateur de supervision. Les redémarrages se font en fenêtre
planifiée, par vagues, avec vérification de service entre chaque vague.
`needrestart` liste les services qui tournent encore sur une bibliothèque
remplacée et évite un redémarrage complet dans bien des cas.

Le lendemain matin, on sait ce qui a bougé grâce à trois sources :

```bash
grep -h '^Start-Date\|^Commandline\|^Upgrade' /var/log/apt/history.log
zgrep -h 'Upgrade:' /var/log/apt/history.log.*.gz
diff manifeste-hier.txt manifeste-aujourdhui.txt
journalctl -u unattended-upgrades --since yesterday
```

::: pourquoi
Le point central, celui qui distingue une vraie réponse d'une récitation :
**automatiser la mise à jour ne suffit pas, il faut automatiser la détection de
ce qui n'a pas été mis à jour**. Une machine dont `unattended-upgrades` échoue
depuis six semaines ne produit aucune alerte : elle est simplement silencieuse.
D'où l'inversion du contrôle : on ne surveille pas « la mise à jour a-t-elle
réussi », on surveille « existe-t-il encore des correctifs de sécurité en
attente sur cette machine, et depuis combien de temps ». C'est une métrique, elle
a un seuil, elle déclenche une alerte.

Le second point est le **décalage des fenêtres**. Mettre 200 serveurs à jour à
3 h du matin le même jour, c'est transformer un paquet défectueux publié en
amont en panne générale. On passe par vagues : un groupe témoin, puis 10 %, puis
le reste, avec un délai suffisant pour qu'un incident se voie.
:::

---

**QO10.7** — *« Je compile redis depuis les sources ».*

**Réponse attendue**

Quand il a raison :

* la version du dépôt est réellement trop ancienne pour un besoin fonctionnel
  précis, et aucun dépôt amont officiel (`packages.redis.io`), aucun backport et
  aucun conteneur ne couvre le cas ;
* il faut une option de compilation absente du paquet
  (module, allocateur, `--enable-` particulier) ;
* le logiciel n'est distribué que sous forme de sources.

Quand c'est une faute : quand c'est le premier réflexe. Sur un serveur de
production, un `make install` non empaqueté n'a ni traçabilité, ni mise à jour
de sécurité, ni désinstallation, ni inventaire.

Solution intermédiaire, dans l'ordre :

1. le **dépôt amont officiel** de l'éditeur, ajouté proprement avec
   `Signed-By` — c'est le cas de Redis, Docker, PostgreSQL, HashiCorp ;
2. le **backport** de la distribution (`-t noble-backports`) ;
3. le **conteneur**, si l'application s'y prête ;
4. compiler et **empaqueter soi-même** (L10.4), avec un numéro de version qui
   ordonne correctement face au paquet officiel, et un dépôt interne pour le
   distribuer.

::: pourquoi
Ce que le développeur n'a pas en tête, et qu'il faut lui dire sans agressivité :
compiler n'est pas la partie difficile. La partie difficile arrive dans dix-huit
mois, quand une CVE sort sur la version compilée. Avec un paquet, il existe une
chaîne — un mainteneur, un correctif, un `apt upgrade`, un inventaire qui dit
quelles machines sont concernées. Sans paquet, la chaîne est « quelqu'un se
souvient d'avoir compilé ça sur ce serveur ». C'est un argument d'exploitation,
pas de puriste, et c'est celui qui porte.

Contre-argument légitime qu'il faut savoir accepter : sur un poste de
développement ou une machine de calcul jetable, compiler est parfaitement
raisonnable et beaucoup plus rapide. La règle n'est pas « jamais compiler »,
c'est « rien de non empaqueté sur une machine que quelqu'un devra exploiter ».
:::

---

**QO10.8** — *« `apt install` propose de supprimer `ubuntu-server` ».*

**Réponse attendue**

```bash
# 1. lire la proposition en entier, sans l'exécuter
apt-get -s install <paquet> | sed -n '/REMOVED/,/upgraded/p'

# 2. qu'est-ce qui a changé depuis hier ?
ls -lt /etc/apt/sources.list.d/ /etc/apt/preferences.d/
grep -h '^Start-Date\|^Commandline' /var/log/apt/history.log | tail -20

# 3. quels dépôts, avec quelles priorités
apt-cache policy

# 4. le paquet qui bloque, et d'où il vient
apt-cache policy <bibliotheque-en-conflit>
apt-cache rdepends --installed <bibliotheque-en-conflit>

# 5. demander à un autre solveur : il explique mieux
sudo aptitude install <paquet>      # propose des solutions alternatives
```

Ce qu'on cherche, sortie par sortie : dans (1), le **nom du paquet pivot** —
celui qui apparaît comme conflit ou comme dépendance non satisfaite ; dans (2),
un dépôt ou un épinglage ajouté récemment ; dans (3), un dépôt tiers avec une
priorité élevée ou un `Pin-Priority` anormal ; dans (4), l'origine réelle de la
bibliothèque en cause ; dans (5), la formulation du conflit, qu'`aptitude`
énonce bien plus clairement qu'apt.

Correctif habituel : retirer ou dé-prioriser le dépôt tiers, épingler sa
bibliothèque à la version distribution, et si le paquet applicatif l'exige
vraiment, l'isoler dans un conteneur.

::: pourquoi
La discipline à acquérir tient en une phrase : **`-s` avant tout**. `apt-get -s`
et `apt-get --dry-run` calculent le plan complet sans toucher au disque. Sur une
machine de production, toute commande apt non triviale se lance d'abord en `-s`.

Le second réflexe, moins connu, est d'installer `aptitude` uniquement pour
diagnostiquer. Son résolveur est différent : au lieu de déclarer une impasse, il
propose des solutions successives (« ne pas installer X », « rétrograder Y »,
« supprimer Z ») qu'on parcourt avec `n`. On n'applique pas forcément sa
solution, mais la lecture de ses propositions dit **quel est le vrai conflit** en
trente secondes, là où on passerait une heure à lire des `Depends:`.
:::

---

**QO10.9** — *Ce qu'apporte `dnf history`, et l'équivalent Debian.*

**Réponse attendue**

Ce que `dnf history` apporte : une base de transactions
(`/var/lib/dnf/history.sqlite`) numérotée, interrogeable
(`dnf history info <id>`) et **annulable** (`undo`, `rollback`). L'annulation est
une opération de premier ordre, pas une reconstitution manuelle.

Ce qu'il ne sait pas faire : restaurer des données migrées, restaurer une
configuration modifiée après coup, annuler un `dnf module enable`, et il échoue
si les anciens RPM ne sont plus disponibles (dépôt purgé, cache vidé).

Côté Debian, il n'existe **pas** d'équivalent. On reconstitue :

```bash
# ce qui a été fait, et exactement quelles versions
grep -A3 '^Start-Date' /var/log/apt/history.log | tail -40
zgrep 'Upgrade:' /var/log/apt/history.log.*.gz

# revenir à une version précise, si elle est encore disponible
apt-cache madison <paquet>
sudo apt install --allow-downgrades <paquet>=<ancienne-version>
```

et on met en place ce qui donne la vraie garantie : conserver les `.deb`
(`Binary::apt::APT::Keep-Downloaded-Packages "true";`), un miroir interne ou un
dépôt gelé, un manifeste par déploiement, et surtout un **snapshot de machine ou
de volume** avant toute opération sensible.

::: pourquoi
Il faut savoir dire la conclusion honnête : sur ce point précis, RHEL a un
avantage réel et Debian n'a pas de réponse native. Prétendre le contraire en
entretien se voit immédiatement.

Mais il faut aussi savoir relativiser : `undo` ne défait que des paquets. Dans
un incident réel, le problème est rarement « le binaire a changé » — c'est « le
schéma de base a été migré », « le format du fichier de configuration a changé »,
« le protocole réseau n'est plus compatible avec l'autre moitié du cluster ».
Aucun gestionnaire de paquets ne revient en arrière là-dessus. La seule stratégie
de retour arrière qui tienne à l'échelle, c'est le snapshot d'infrastructure,
ou le déploiement immuable : on ne répare pas la machine, on en redéploie une
avec le manifeste précédent. `dnf history undo` est un confort appréciable sur
une machine unique ; ce n'est pas une stratégie.
:::

---

## 10.5 Exercices guidés

**E10.1** — *Nombre de paquets réellement installés.*

```bash
dpkg-query -f '${db:Status-Abbrev}\n' -W | grep -c '^.i '
```

::: pourquoi
`dpkg -l | wc -l` est faux deux fois : il compte les cinq lignes d'en-tête, et
il compte les paquets en état `rc` (supprimés, conffiles conservés) comme
installés. Le motif `^.i` retient tout paquet dont l'**état réel** (deuxième caractère) est `i`, y compris ceux retenus par `hold` (`hi`), qui sont bien installés. `dpkg-query -W` ne sort que des données, une ligne par paquet, et
`${db:Status-Abbrev}` donne les trois caractères d'état. C'est la forme
scriptable, et son format est stable — contrairement à l'affichage de `dpkg -l`,
qui tronque les noms selon la largeur du terminal.
:::

::: piege
`dpkg -l` tronque : sur un terminal de 80 colonnes, `linux-image-6.8.0-52-generic`
devient `linux-image-6.8.0-52-gene`. Un script qui lit `dpkg -l` dans un pipe
(donc sans terminal) ne tronque pas, mais le même script lancé à la main
tronque. Ce genre de bogue coûte une soirée.
:::

---

**E10.2** — *Paquet fournissant `/usr/bin/ss`, puis ses fichiers de conf.*

```bash
dpkg -S /usr/bin/ss            # iproute2: /usr/bin/ss
dpkg -L iproute2 | grep '^/etc'
```

::: pourquoi
`dpkg -S` cherche dans les listes de fichiers de `/var/lib/dpkg/info/*.list`.
`dpkg -L` lit `/var/lib/dpkg/info/iproute2.list`. Tout est local, aucun réseau,
et cela fonctionne donc sur une machine coupée du monde — c'est précisément
l'usage.

Variante utile : `dpkg -s iproute2 | sed -n '/^Conffiles:/,/^[A-Z]/p'` donne
les **conffiles déclarés** avec leur MD5 d'origine. Ce n'est pas la même chose
que « les fichiers sous `/etc` » : un paquet peut livrer sous `/etc` des fichiers
qu'il ne déclare pas comme conffiles (ils seront alors écrasés sans prompt).
:::

---

**E10.3** — *`/usr/sbin/nft` alors que le paquet n'est pas installé.*

```bash
sudo apt install -y apt-file && sudo apt-file update
apt-file search /usr/sbin/nft      # nftables: /usr/sbin/nft
```

::: pourquoi
Voir Q10.4. Le point à retenir : `apt-file update` télécharge les index
`Contents-amd64.gz`, qui pèsent plusieurs dizaines de méga-octets et ne sont pas
récupérés par `apt update`. C'est pour cela qu'`apt-file` a sa propre commande de
mise à jour, et qu'il est inutilisable sur une machine sans accès aux dépôts.
:::

---

**E10.4** — *Paquets demandés explicitement contre dépendances.*

```bash
apt-mark showmanual | wc -l
apt-mark showauto   | wc -l
apt-mark showmanual | sort > ~/lab10/rapports/manuels.txt
```

::: pourquoi
apt marque chaque paquet `manual` ou `auto` dans
`/var/lib/apt/extended_states`. Un paquet installé par toi est `manual` ; un
paquet tiré comme dépendance est `auto`. C'est ce marquage, et lui seul, qui
permet à `apt autoremove` de savoir quoi retirer : un paquet `auto` dont plus
rien ne dépend est un orphelin.

Utilité concrète en migration : la liste des `manual` est la **description
minimale de la machine**. Sur une nouvelle installation,
`xargs apt install < manuels.txt` reconstitue le même système, dépendances
comprises, sans traîner les orphelins accumulés.

Corollaire : `apt-mark auto <paquet>` est l'outil pour « je ne veux plus de ce
paquet mais je ne veux pas le supprimer maintenant » — il partira au prochain
`autoremove` si plus rien n'en dépend.
:::

---

**E10.5** — *Paquets dont l'état n'est pas `ii`.*

```bash
dpkg-query -f '${db:Status-Abbrev} ${binary:Package} ${Version}\n' -W \
  | grep -v '^ii '
```

::: pourquoi
Un état différent de `ii` est toujours une anomalie à traiter, et la lettre dit
laquelle :

| État | Signification | Action |
|---|---|---|
| `iU` | déballé, pas configuré | `sudo dpkg --configure -a` |
| `iF` | configuration à moitié faite (postinst en échec) | lire l'erreur, corriger, reconfigurer |
| `iH` | déballage à moitié fait | `sudo apt install -f` |
| `rc` | supprimé, conffiles restants | `sudo apt purge <paquet>` |
| `hi` | retenu et installé | décision humaine : `apt-mark showhold` |

C'est la première commande à passer sur une machine dont on hérite. Elle prend
une seconde et raconte les incidents non terminés.
:::

---

**E10.6** — *Fichiers de `/etc` modifiés par rapport au paquet.*

```bash
sudo dpkg -V 2>/dev/null | awk '$2 == "c" && $1 ~ /5/ {print $3}'
```

ou, sans filtrer sur le type :

```bash
sudo dpkg -V | grep '^..5' | grep ' /etc/'
```

::: pourquoi
`dpkg -V` (sans argument) vérifie **tous** les paquets, en comparant les fichiers
du disque aux sommes enregistrées. Sortie :

```text
??5?????? c /etc/bash.bashrc
```

Les `?` marquent les attributs que dpkg ne vérifie pas (dpkg ne stocke que la
somme de contrôle, contrairement à RPM qui stocke taille, mode, propriétaire,
mtime). Le `5` signale un contenu différent, le `c` que c'est un conffile.

Le code retour de `dpkg -V` est **1** quand il trouve des écarts : sous
`set -e`, il faut `|| true`. C'est le piège du script de L10.1.

Alternative plus complète : le paquet `debsums` vérifie aussi les fichiers
**hors** `/etc` à partir des `.md5sums`, avec `debsums -c` pour lister les
fichiers modifiés et `debsums -e` pour se limiter aux conffiles.
:::

---

**E10.7** — *Conffiles déclarés de `openssh-server`, avec leurs empreintes.*

```bash
dpkg-query -W -f '${Conffiles}\n' openssh-server
```

::: pourquoi
`${Conffiles}` sort directement le champ de la base, une ligne par fichier :
chemin puis MD5 **d'origine**. Comparer ce MD5 au `md5sum` actuel du fichier
donne exactement ce que fait `dpkg -V`, et permet de répondre à la question
« ce fichier a-t-il été touché depuis l'installation ? » sans outil
supplémentaire :

```bash
dpkg-query -W -f '${Conffiles}\n' openssh-server \
  | while read -r f md5 _; do
      [ -f "$f" ] || { echo "ABSENT   $f"; continue; }
      a=$(md5sum "$f" | cut -d' ' -f1)
      [ "$a" = "$md5" ] && echo "intact   $f" || echo "MODIFIE  $f"
    done
```

Un troisième champ `obsolete` apparaît parfois : le conffile a été retiré par
une version ultérieure du paquet mais reste sur le disque. C'est du ménage à
faire.
:::

---

**E10.8** — *Versions de `curl` disponibles, et priorités des dépôts.*

```bash
apt-cache madison curl
apt-cache policy curl
apt-cache policy            # sans argument : toutes les priorités
```

::: pourquoi
Trois outils, trois usages, et il faut les distinguer :

* `apt-cache madison curl` : la liste brute « version | dépôt », une ligne par
  version disponible. C'est la commande à réflexe quand on cherche « quelle
  version puis-je installer ? ».
* `apt-cache policy curl` : la même information **plus** la version installée,
  la candidate, et la priorité de chaque version. C'est la commande de
  diagnostic d'épinglage.
* `apt-cache policy` sans argument : le tableau des dépôts avec leur priorité et
  leur ligne `release o=...,a=...,n=...,l=...,c=...`. Ce sont **ces valeurs** que
  l'on réutilise dans un `Pin: release ...`. On ne les devine pas, on les lit ici.

```console
$ apt-cache policy
 500 http://security.ubuntu.com/ubuntu noble-security/main amd64 Packages
     release v=24.04,o=Ubuntu,a=noble-security,n=noble,l=Ubuntu,c=main,b=amd64
     origin security.ubuntu.com
 100 http://archive.ubuntu.com/ubuntu noble-backports/main amd64 Packages
     release v=24.04,o=Ubuntu,a=noble-backports,n=noble,l=Ubuntu,c=main,b=amd64
```

On y voit que `noble-backports` est à **100** et non 500 : c'est pour cela qu'un
paquet de backports ne s'installe jamais tout seul et exige `-t noble-backports`.
:::

---

**E10.9** — *Télécharger `tree` sans l'installer, puis l'inspecter.*

```bash
cd ~/lab10/paquets && apt download tree
dpkg-deb -c tree_*.deb          # contenu (liste des fichiers)
dpkg-deb -f tree_*.deb Depends  # un champ précis du control
dpkg-deb -I tree_*.deb          # control complet + scripts présents
```

::: pourquoi
Un `.deb` est une archive `ar` contenant trois membres : `debian-binary` (le
numéro de format, `2.0`), `control.tar.*` (métadonnées et scripts de
mainteneur), `data.tar.*` (les fichiers à installer). `dpkg-deb` sait lire les
trois sans rien installer :

| Option | Ce qu'elle lit |
|---|---|
| `-c` / `--contents` | `data.tar.*` : la liste des fichiers |
| `-f` / `--field` | un champ de `control` |
| `-I` / `--info` | tout `control.tar.*`, scripts compris |
| `-x` / `-R` | extrait les données / les données + les métadonnées |

`dpkg-deb -I` est ce qu'on regarde **avant** d'installer un `.deb` venu d'un
tiers : il montre les scripts `preinst`/`postinst`, c'est-à-dire le code
arbitraire qui s'exécutera en root sur ta machine.

Et le rappel qui va avec : `apt download` ne vérifie rien de plus que la somme
de l'index. Un `.deb` récupéré à la main sur un site web, lui, n'est vérifié par
absolument rien.
:::

---

**E10.10** — *`dpkg -i` d'un paquet à dépendance manquante.*

```bash
cd ~/lab10/paquets
sudo dpkg -i agent-lab_2.0.0_all.deb
```

```console
dpkg: dependency problems prevent configuration of agent-lab:
 agent-lab depends on libmetric3 (>= 3.2); however:
  Package libmetric3 is not installed.

dpkg: error processing package agent-lab (--install):
 dependency problems - leaving unconfigured
Errors were encountered while processing:
 agent-lab
```

État obtenu, puis remise en ordre :

```bash
dpkg -l agent-lab              # iU agent-lab 2.0.0
sudo apt-get -f install        # apt constate et propose de le retirer
# ou, directement :
sudo dpkg --purge agent-lab
```

::: pourquoi
Ce message dit tout du partage des rôles. dpkg **sait lire** le champ `Depends`
et **refuse de configurer** un paquet dont les dépendances ne sont pas
satisfaites — mais il ne sait pas aller les chercher. Il déballe quand même les
fichiers et laisse le paquet en `iU`.

`apt-get -f install` (« fix broken ») lit la base dpkg, constate les dépendances
non satisfaites, et propose la seule solution qu'il trouve : ici, comme
`libmetric3` n'existe dans aucun dépôt, il propose de **supprimer** `agent-lab`.

```console
Correcting dependencies... Done
The following packages will be REMOVED:
  agent-lab
```

C'est le mécanisme complet de « dpkg -i d'un paquet téléchargé sur internet, puis
apt propose de supprimer des choses ». La bonne pratique est l'inverse :
`sudo apt install ./agent-lab_2.0.0_all.deb` — avec le `./`, apt traite le
fichier local **et** résout ses dépendances depuis les dépôts.
:::

---

**E10.11** — *Simuler `apt autoremove`.*

```bash
apt-get -s autoremove
apt-mark showauto > /tmp/auto.txt
# pour un paquet donné, qui le retient encore ?
apt-cache rdepends --installed --no-recommends --no-suggests <paquet>
```

::: pourquoi
Un paquet est candidat à `autoremove` si et seulement si **deux** conditions
sont réunies : il est marqué `auto` dans `/var/lib/apt/extended_states`, et plus
aucun paquet installé n'en dépend. `apt-cache rdepends --installed` donne la
seconde moitié de la réponse.

Le cas qui fait peur en production : un paquet installé à la main il y a
longtemps avec `apt install`, puis re-marqué `auto` par une transaction
ultérieure — il disparaît à un `autoremove` que personne n'a relié à lui.
`apt-mark manual <paquet>` sur les paquets qui comptent (agents de supervision,
outils d'exploitation) est une protection simple et sous-utilisée.

Et le classique des noyaux : `autoremove` supprime les anciens
`linux-image-*` devenus orphelins. C'est souhaitable (ils remplissent `/boot`),
à condition de ne pas retirer celui qui tourne — apt le protège, mais un
`autoremove --purge` lancé juste après une mise à jour de noyau **avant
redémarrage** mérite qu'on lise la liste.
:::

---

**E10.12** — *Installer un paquet depuis `noble-backports` uniquement.*

```bash
# la suite est déjà déclarée dans /etc/apt/sources.list.d/ubuntu.sources
grep -n 'backports' /etc/apt/sources.list.d/ubuntu.sources
sudo apt update
apt-cache policy <paquet>                    # vérifier qu'il y est
sudo apt install -t noble-backports <paquet>
```

::: pourquoi
`-t` (`--target-release`) donne à la suite visée une priorité de **990** le
temps de la commande, ce qui la fait passer devant les 500 des dépôts normaux et
devant les 100 des backports. Rien n'est modifié durablement : c'est une
décision par commande.

Pourquoi les backports sont à 100 et pas à 500 : à 100, un paquet de backports
n'est jamais choisi spontanément, ni à l'installation ni à la mise à jour. Il
faut le demander. Mais **une fois installé**, ses mises à jour au sein des
backports, elles, suivent. C'est le compromis voulu : tu choisis d'entrer dans
les backports pour un paquet précis, et tu y restes pour celui-là.

L'alternative durable, si l'on veut qu'un paquet vienne toujours des backports :

```ini
# /etc/apt/preferences.d/60-backports-nginx.pref
   Package: nginx nginx-common
Pin: release a=noble-backports
Pin-Priority: 600
```
:::

---

**E10.13** — *Retenir `openssh-server`, vérifier de deux façons, libérer.*

```bash
sudo apt-mark hold openssh-server      # openssh-server set on hold.
apt-mark showhold                      # openssh-server
dpkg --get-selections openssh-server   # openssh-server    hold
sudo apt-mark unhold openssh-server    # Canceled hold on openssh-server.
```

::: pourquoi
Les deux commandes de vérification interrogent **la même donnée** par deux
chemins différents. `apt-mark hold` n'est qu'une façade : elle écrit le champ
`Status: hold ok installed` dans `/var/lib/dpkg/status`. C'est pour cela que
`dpkg --get-selections` le voit, et c'est pour cela qu'un `hold` n'est pas dans
`/etc` (voir QO10.5).

La forme historique, encore utilisée dans de vieux scripts et qu'il faut savoir
lire :

```bash
echo "openssh-server hold" | sudo dpkg --set-selections
```

Elle fait exactement la même chose. En audit, chercher les `hold` avec
`apt-mark showhold` **et** `dpkg --get-selections | grep -w hold` : sur une
machine où `/var/lib/dpkg/status` a été bricolé, les deux peuvent diverger.
:::

---

**E10.14** — *`editor` sur `vim`, en mode manuel, puis retour en auto.*

```bash
update-alternatives --display editor
sudo update-alternatives --set editor /usr/bin/vim.basic
update-alternatives --query editor | grep -E '^(Status|Value):'
#   Status: manual
#   Value: /usr/bin/vim.basic
sudo update-alternatives --auto editor
```

::: pourquoi
Le système d'alternatives est une couche de liens symboliques à deux étages :

```text
/usr/bin/editor -> /etc/alternatives/editor -> /usr/bin/vim.basic
```

Le premier lien est livré par un paquet et ne bouge jamais. Le second est géré
par `update-alternatives`, et c'est lui qu'on change. L'état est dans
`/var/lib/dpkg/alternatives/editor`.

Le mode compte autant que la valeur :

* **auto** : le lien pointe sur le candidat de plus haute **priorité** parmi
  ceux installés. Installer un paquet mieux prioritaire change le lien tout seul.
* **manual** : ton choix est gelé. Il survit à l'installation d'un autre éditeur.

D'où la question d'exploitation : « pourquoi `editor` est-il redevenu `nano`
après une mise à jour ? » Parce que le groupe était en `auto` et que le paquet
retiré était celui qui gagnait. `--set` (et non `--config`, qui fait la même
chose interactivement) passe en `manual` et fige le choix.

Un groupe d'alternatives entraîne aussi ses **esclaves** : changer `editor`
change `editor.1.gz` vers la bonne page de manuel. C'est pour cela qu'on ne
remplace jamais ces liens à la main avec `ln -sf`.
:::

---

**E10.15** — *Compiler avec un préfixe, sans rien installer sur le système.*

```bash
cd ~/lab10/sources
tar xzf horodate-1.4.tar.gz && cd horodate-1.4
./configure --prefix=/opt/horodate-1.4
make
make install DESTDIR="$PWD/racine"
find racine -type f -printf '%M %p\n'
```

```console
$ ./configure --prefix=/opt/horodate-1.4
checking for a C compiler... cc
checking for time.h... yes
configure: creating Makefile
  prefix = /opt/horodate-1.4
  bindir = /opt/horodate-1.4/bin

$ find racine -type f -printf '%M %p\n'
-rwxr-xr-x racine/opt/horodate-1.4/bin/horodate
```

::: pourquoi
Il faut séparer deux notions que tout le monde confond :

* **`--prefix`** est passé au moment de la *configuration* et se retrouve
  **compilé dans le binaire** : c'est là que le programme ira chercher ses
  données, ses bibliothèques, sa locale. Le changer après coup ne suffit pas.
* **`DESTDIR`** est passé au moment de l'*installation* et n'est qu'un préfixe
  de **copie**. Le programme croit toujours vivre en `/opt/horodate-1.4` ; les
  fichiers sont simplement écrits ailleurs.

Conséquence pratique : `DESTDIR` sert à **empaqueter** (on installe dans une
racine factice, on emballe), pas à relocaliser un logiciel. Un binaire compilé
avec `--prefix=/usr/local` puis copié dans `/opt` cherchera ses fichiers dans
`/usr/local` et échouera.

C'est la convention GNU, respectée par autotools, CMake (`DESTDIR` y fonctionne
aussi) et Meson. Un projet qui ne respecte pas `DESTDIR` est un projet qu'on ne
peut pas empaqueter proprement — c'est un critère de qualité à part entière.
:::

---

**E10.16** — *venv et pipx.*

```bash
python3 -m venv ~/lab10/venv-outil
~/lab10/venv-outil/bin/pip install --quiet requests
~/lab10/venv-outil/bin/python -c 'import requests; print(requests.__file__)'
# /home/mathieu/lab10/venv-outil/lib/python3.12/site-packages/requests/
#   __init__.py

# preuve que le système n'a pas bougé
python3 -c 'import requests' 2>&1 | tail -1
dpkg -V python3-minimal ; echo "code retour : $?"

sudo apt install -y pipx
pipx install httpie
command -v http          # ~/.local/bin/http
pipx list
```

::: pourquoi
Un venv n'est pas une machine virtuelle : c'est un répertoire contenant un
`pyvenv.cfg`, un `bin/` avec des liens vers l'interpréteur système, et un
`lib/pythonX.Y/site-packages/` à lui. Activer un venv ne fait rien d'autre que
mettre son `bin/` en tête de `PATH` — d'où le fait qu'appeler
`~/lab10/venv-outil/bin/python` directement fonctionne sans `activate`. C'est
d'ailleurs la forme à privilégier dans les unités systemd et les cron : pas
d'activation, un chemin absolu.

`pipx` applique le même principe à un outil : un venv dédié par outil, et
seulement l'exécutable exposé dans `~/.local/bin`. Deux outils qui exigent des
versions incompatibles de la même bibliothèque cohabitent sans se voir.

La preuve par `dpkg -V python3-minimal` est le vrai objet de l'exercice : on
démontre que l'arborescence système n'a pas été touchée. C'est exactement ce que
`sudo pip install` ne permet pas de démontrer.
:::

---

## 10.6 Labs

### **L10.1** — Inventaire logiciel avant migration

*Produire un rapport d'inventaire reproductible sur toutes les VM Ubuntu.*

**Script attendu** (`~/lab10/bin/inventaire.sh`)

```bash
#!/usr/bin/env bash
# inventaire.sh — état des lieux logiciel d'une machine Debian/Ubuntu.
# Lecture seule. Rapport Markdown sur stdout.
set -uo pipefail

etat() { dpkg-query -f \
  '${db:Status-Abbrev} ${binary:Package} ${Version}\n' -W 2>/dev/null; }

printf '# Inventaire logiciel — %s — %s\n\n' "$(hostname -f)" "$(date +%F)"

printf '## Paquets installés\n\n'
INST=$(etat | grep -c '^.i ')        # ii et hi : installés
RC=$(etat | grep -c '^rc ')
printf -- '- installés (ii, hi) : **%d**\n' "$INST"
printf -- '- supprimés avec conffiles restants (rc) : %d\n\n' "$RC"

printf '## Installés manuellement\n\n'
MAN=$(apt-mark showmanual 2>/dev/null | wc -l)
AUT=$(apt-mark showauto   2>/dev/null | wc -l)
printf -- '- demandés explicitement : **%d**\n' "$MAN"
printf -- '- tirés comme dépendances : %d\n\n' "$AUT"
printf 'Liste de reconstruction (à rejouer sur la cible) :\n\n'
printf '```text\n'; apt-mark showmanual | sort | paste -sd' ' -
printf '\n```\n\n'

printf '## États anormaux\n\n'
ANO=$(etat | grep -v '^ii ' || true)
if [ -z "$ANO" ]; then
  printf 'Aucun. Tous les paquets sont en état `ii`.\n\n'
else
  printf '```text\n%s\n```\n\n' "$ANO"
fi

printf '## Hors dépôt officiel\n\n'
printf 'Paquets installés dont la version ne figure dans aucun dépôt\n'
printf 'configuré : ils ne seront PAS réinstallés automatiquement.\n\n'
HORS=$(etat | awk '/^.i / {print $2}' \
  | while read -r p; do
      apt-cache policy "$p" 2>/dev/null | awk -v P="$p" '
        /^ \*\*\*/      {vu=1; next}
        vu && /Packages/ {ok=1}
        vu && /^     /   {vu=0}
        END {if (!ok) print P}'
    done)
if [ -z "$HORS" ]; then
  printf 'Aucun.\n\n'
else
  printf '```text\n%s\n```\n\n' "$HORS"
fi

printf '## Conffiles modifiés\n\n'
MOD=$(dpkg -V 2>/dev/null | awk '$2 == "c" {print $3}' || true)
if [ -z "$MOD" ]; then
  printf 'Aucun conffile modifié.\n\n'
else
  printf '```text\n%s\n```\n\n' "$MOD"
fi

printf 'Fichiers laissés par des mises à jour précédentes :\n\n'
printf '```text\n'
find /etc \( -name '*.dpkg-dist' -o -name '*.dpkg-old' \
          -o -name '*.ucf-dist' \) 2>/dev/null
printf '```\n'
```

Génération du livrable :

```bash
chmod +x ~/lab10/bin/inventaire.sh
~/lab10/bin/inventaire.sh > ~/lab10/rapports/inventaire.md
bash check_M10_01.sh
```

::: pourquoi
La section qui fait la valeur du rapport est **« Hors dépôt officiel »**, et
elle mérite qu'on explique son mécanisme.

`apt-cache policy <paquet>` affiche une table de versions où la version
installée est marquée `***`. Juste en dessous, indentées, figurent les
**origines** de cette version. Deux cas :

```text
 *** 1.2.0 500
           500 http://127.0.0.1:8099 ./ Packages   <- vient d'un dépôt
        100 /var/lib/dpkg/status
```

```text
 *** 1.3.0 100
        100 /var/lib/dpkg/status                 <- seulement la base locale
```

Dans le second cas, aucun dépôt ne propose cette version : le paquet a été posé
par `dpkg -i`, ou il a été retiré du dépôt depuis, ou son dépôt tiers n'est plus
déclaré. Le script cherche donc, sous la ligne `***`, s'il existe au moins une
ligne d'origine autre que `/var/lib/dpkg/status`.

C'est **la** liste qui sauve une migration. Sur la nouvelle machine,
`apt install` rejouera tout ce qui vient des dépôts ; ces paquets-là, personne
ne les remettra, et on s'en aperçoit trois semaines plus tard quand l'agent de
sauvegarde ne tourne plus.

Deuxième point de méthode : le script est en **lecture seule** et sort du
Markdown sur stdout. On peut donc le lancer sur les autres VM depuis `lab-adm` :

```bash
for h in 10.10.10.11 10.10.10.12 10.10.10.14; do
  ssh "mathieu@$h" 'bash -s' < ~/lab10/bin/inventaire.sh \
    > ~/lab10/rapports/inventaire-$h.md
done
```

Un script d'audit qui écrit sur le système qu'il audite n'est pas un script
d'audit.
:::

::: piege
`dpkg -V` sort en **code 1** quand il trouve des différences — c'est-à-dire
quasiment toujours. Sous `set -e`, le script meurt en silence au milieu du
rapport. D'où le `set -uo pipefail` sans `-e` ici, ou les `|| true` explicites.
C'est le genre de détail qui fait qu'un script « marche chez moi » et produit un
rapport tronqué sur les autres machines.
:::

---

### **L10.2** — Publier le dépôt interne de l'équipe

*Intégrer le dépôt signé `/srv/depot-lab` sans toucher au trousseau global.*

**Procédure complète**

```bash
# 1. regarder la clé AVANT de lui faire confiance
gpg --show-keys --with-fingerprint /srv/depot-lab/depot-lab.asc
```

```console
pub   rsa3072 2026-09-18 [SCEA]
      B92E A8B6 8C03 11BE 89F5  9CED 70D3 F6C8 4D69 95D5
uid                      Depot Lab Interne <depot@lab.local>
```

(La clé est générée par `setup_M10.sh` : l'empreinte et l'identifiant ci-dessus
sont des valeurs d'exemple, les tiens seront différents.)

```bash
# 2. installer la clé, dé-armurée, lisible par _apt
sudo install -m 0755 -d /etc/apt/keyrings
sudo gpg --dearmor -o /etc/apt/keyrings/depot-lab.gpg \
     /srv/depot-lab/depot-lab.asc
sudo chmod 0644 /etc/apt/keyrings/depot-lab.gpg

# 3. déclarer la source, en deb822, restreinte à cette clé
sudo tee /etc/apt/sources.list.d/depot-lab.sources >/dev/null <<'EOF'
# Signed-By restreint cette cle a CE depot : une cle posee dans
# /etc/apt/trusted.gpg.d signerait valablement n'importe quel paquet.
Types: deb
URIs: http://127.0.0.1:8099
Suites: ./
Signed-By: /etc/apt/keyrings/depot-lab.gpg
EOF

# 4. rafraîchir : aucune ligne W: ni E: pour ce dépôt
sudo apt update

# 5. installer PAR APT et vérifier l'origine
sudo apt install -y outil-lab
apt-cache policy outil-lab
```

```console
outil-lab:
  Installed: 1.2.0
  Candidate: 1.2.0
  Version table:
 *** 1.2.0 500
        500 http://127.0.0.1:8099 ./ Packages
        100 /var/lib/dpkg/status
     1.0.0 500
        500 http://127.0.0.1:8099 ./ Packages
```

```bash
# 6. vérification par la négative
sudo mv /etc/apt/keyrings/depot-lab.gpg /root/depot-lab.gpg.bak
sudo rm -f /var/lib/apt/lists/*8099*
sudo apt update
```

```console
W: GPG error: http://127.0.0.1:8099 ./ InRelease: The following signatures
   couldn't be verified because the public key is not available:
   NO_PUBKEY 70D3F6C84D6995D5
E: The repository 'http://127.0.0.1:8099 ./ InRelease' is not signed.
```

```bash
sudo mv /root/depot-lab.gpg.bak /etc/apt/keyrings/depot-lab.gpg
sudo apt update
sudo bash check_M10_02.sh
```

::: pourquoi
Quatre points de mécanisme, dans l'ordre où ils piègent.

**Un dépôt « plat » n'a pas de `dists/`.** Les dépôts classiques ont une
hiérarchie `dists/<suite>/<composant>/binary-<arch>/Packages`. Un dépôt plat met
`Packages`, `Release` et `InRelease` à la racine. On le déclare avec une suite
qui se termine par `/` — ici `./` — et **aucun composant**. En deb822, cela
s'écrit `Suites: ./` sans ligne `Components:`. Si tu ajoutes un composant, apt
cherche `dists/./main/...` et tu obtiens un 404.

**La chaîne de confiance.** `InRelease` est un fichier texte signé en clair
(`clearsign`) qui contient les sommes SHA256 de `Packages`. `Packages` contient
les sommes SHA256 de chaque `.deb`. Vérifier la signature de `InRelease` suffit
donc à garantir tout le reste. `Release` + `Release.gpg` est la forme détachée,
plus ancienne ; apt essaie `InRelease` d'abord.

**Pourquoi `_apt` doit lire le trousseau.** apt lâche ses privilèges vers
l'utilisateur non privilégié `_apt` pour tout ce qui touche au réseau. Un
trousseau en `0600 root:root` produit un échec de vérification déroutant, alors
que le fichier est parfaitement valide.

**Le message lui-même.** Il contient deux lignes distinctes, qu'il faut savoir
lire séparément : le `W:` dit *pourquoi* (pas de clé pour cet identifiant), le
`E:` dit *ce qu'apt en conclut* (dépôt traité comme non signé, donc écarté). Et
le comportement change selon qu'un index valide existe déjà en cache : dans ce
cas, apt affiche `An error occurred during the signature verification. The
repository is not updated and the previous index files will be used.` et
**continue à fonctionner avec l'ancien index**. C'est pour cela que l'étape 6
supprime les listes : sans ça, le symptôme est atténué et on croit que tout va
bien.
:::

::: piege
`[trusted=yes]` et une clé dans `/etc/apt/trusted.gpg.d/` « réparent » les deux
le symptôme. Le premier désactive toute vérification pour ce dépôt : le
`InRelease` peut être remplacé en vol, apt s'en moque. Le second donne à la clé
du lab le droit de signer valablement `libc6`, `sudo` et `openssh-server`.
Aucun des deux ne se voit dans une revue rapide — ce sont les deux lignes qu'un
audit de sécurité cherche en priorité dans `/etc/apt`.
:::

---

### **L10.3** — Ticket INC-3390 : revenir en 1.0.0 et y rester

*Rétrograder `outil-lab`, geler par épinglage, documenter la procédure.*

**Procédure**

```bash
# 1. état des lieux
apt-cache policy outil-lab
apt-cache madison outil-lab
```

```console
 outil-lab |      1.2.0 | http://127.0.0.1:8099 ./ Packages
 outil-lab |      1.0.0 | http://127.0.0.1:8099 ./ Packages
```

```bash
# 2. rétrograder
sudo apt install --allow-downgrades outil-lab=1.0.0
```

```bash
# 3. geler par épinglage
sudo tee /etc/apt/preferences.d/50-outil-lab.pref >/dev/null <<'EOF'
# Gel outil-lab 1.0.0 — INC-3390 — la 1.2.0 casse la facturation.
# Revue : 2026-12-01, a lever des la validation de la 1.2.1.
Package: outil-lab
Pin: version 1.0.0
Pin-Priority: 1001
EOF

# 4. preuve
apt-cache policy outil-lab
apt-get -s upgrade | grep -i 'outil-lab\|downgrad' || echo "rien à signaler"
```

```console
outil-lab:
  Installed: 1.0.0
  Candidate: 1.0.0
  Version table:
     1.2.0 500
        500 http://127.0.0.1:8099 ./ Packages
 *** 1.0.0 1001
        500 http://127.0.0.1:8099 ./ Packages
        100 /var/lib/dpkg/status
```

```bash
# 5. comparaison avec hold
sudo rm /etc/apt/preferences.d/50-outil-lab.pref && sudo apt update
sudo apt-mark hold outil-lab
apt list --upgradable | grep outil-lab
#   outil-lab/stable 1.2.0 all [upgradable from: 1.0.0]   <- visible !
sudo apt install -y outil-lab=1.2.0
#   E: Held packages were changed and -y was used without
#      --allow-change-held-packages.
sudo apt-mark unhold outil-lab
# puis on remet l'épinglage, qui est la solution retenue
```

**Rapport attendu** (`~/lab10/rapports/figer.md`) — structure minimale :

```markdown
# Gel de outil-lab en 1.0.0 — INC-3390

## Procédure de gel
1. `sudo apt install --allow-downgrades outil-lab=1.0.0`
2. créer /etc/apt/preferences.d/50-outil-lab.pref (Pin-Priority: 1001)
3. contrôle : `apt-cache policy outil-lab` -> Candidate: 1.0.0
4. contrôle : `apt-get -s upgrade` ne mentionne plus outil-lab

## Procédure de dégel
1. `sudo rm /etc/apt/preferences.d/50-outil-lab.pref`
2. `sudo apt update && apt-cache policy outil-lab`
3. `sudo apt install outil-lab` puis tests applicatifs

## Revue mensuelle des gels
    grep -r . /etc/apt/preferences.d/ ; apt-mark showhold

## hold contre épinglage
| | apt-mark hold | épinglage |
...
```

::: pourquoi
Trois mécanismes se recoupent ici, et c'est leur différence qui fait le lab.

**Pourquoi `--allow-downgrades` existe.** apt considère par défaut qu'installer
une version plus ancienne est une erreur, parce que les scripts de mainteneur ne
sont écrits que pour monter : un `postinst` de la 1.0.0 ne sait pas défaire ce
que le `postinst` de la 1.2.0 a fait (migration de schéma, changement de format
de fichier). Une rétrogradation peut donc laisser des données dans un format que
le code ancien ne relit pas. L'option n'est pas un caprice d'ergonomie : c'est
un aveu de risque, et c'est le moment de vérifier si le paquet en question
migre des données.

**Pourquoi 1001 et pas 999.** Une priorité > 1000 est la seule qui autorise apt
à descendre. Mais il y a plus subtil : une fois la 1.0.0 installée, un
`Pin-Priority: 999` suffirait à la maintenir, puisque la candidate serait quand
même la 1.0.0. L'écart se voit seulement le jour où une machine est déjà en
1.2.0 et qu'on veut appliquer la même politique partout. Un fichier de politique
doit être **idempotent quel que soit l'état de départ** : c'est ça, la vraie
raison de 1001.

**Ce que l'épinglage ne fait pas.** Il déplace la candidate, il n'interdit rien.
`apt install outil-lab=1.2.0` fonctionne toujours. Pour une interdiction réelle,
il faut une priorité **négative** :

```ini
Package: outil-lab
Pin: version 1.2.0
Pin-Priority: -1
```

À `-1`, la version n'est jamais installable, même demandée explicitement. C'est
l'outil correct pour « cette version précise est bannie du parc ».
:::

::: piege
L'épinglage sans date de revue est le vrai danger, et c'est la raison des deux
lignes de commentaire imposées. Un gel posé pendant un incident survit au
correctif, à la personne qui l'a posé et à la version suivante. La commande de
revue mensuelle — `grep -r . /etc/apt/preferences.d/` **et** `apt-mark showhold`,
les deux, parce qu'ils ne stockent pas au même endroit — doit être dans un
runbook, pas dans une bonne intention.
:::

---

### **L10.4** — L'outil qui n'existe dans aucun dépôt

*Compiler `horodate`, l'empaqueter, l'installer comme un vrai paquet.*

**Procédure**

```bash
cd ~/lab10/sources
tar xzf horodate-1.4.tar.gz && cd horodate-1.4

# 1-2. configurer et compiler
./configure --prefix=/usr/local
make
./horodate --version                  # horodate 1.4

# 3. installer dans une racine factice
rm -rf ~/lab10/build/horodate-pkg
make install DESTDIR="$HOME/lab10/build/horodate-pkg"
find ~/lab10/build/horodate-pkg -type f
#   /home/mathieu/lab10/build/horodate-pkg/usr/local/bin/horodate

# 4. transformer la racine factice en paquet
cd ~/lab10/build/horodate-pkg
mkdir -p DEBIAN
cat > DEBIAN/control <<'EOF'
Package: horodate-lab
Version: 1.4-1
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Mathieu <mathieu@lab.local>
Description: Horodatage local (construit depuis les sources amont 1.4)
 Paquet construit en interne a partir du tarball du prestataire.
 Installe dans /usr/local conformement au FHS.
EOF
cd ~/lab10/build
dpkg-deb --build --root-owner-group horodate-pkg \
         ~/lab10/paquets/horodate-lab_1.4-1_amd64.deb

# 5. installer et prouver
sudo dpkg -i ~/lab10/paquets/horodate-lab_1.4-1_amd64.deb
dpkg -S /usr/local/bin/horodate     # horodate-lab: /usr/local/bin/horodate
dpkg -L horodate-lab
horodate --version                  # horodate 1.4

# 6. désinstaller, vérifier, réinstaller
sudo apt purge -y horodate-lab
ls /usr/local/bin/horodate 2>&1     # No such file or directory
sudo dpkg -i ~/lab10/paquets/horodate-lab_1.4-1_amd64.deb

sudo bash check_M10_04.sh
```

::: pourquoi
**Pourquoi `/usr/local` et pas `/usr`.** Le FHS est explicite : `/usr/local` est
« réservé à l'administrateur local lorsqu'il installe des logiciels ». C'est une
frontière de propriété, pas une préférence esthétique. Aucun paquet de la
distribution n'écrit dans `/usr/local` ; aucun de tes outils n'écrit dans
`/usr`. La conséquence est qu'une mise à jour de la distribution ne peut jamais
entrer en collision avec ce que tu as installé, et que `/usr/local` est le
premier endroit qu'on regarde quand on hérite d'une machine et qu'on cherche ce
qui a été ajouté à la main. Le `PATH` par défaut d'Ubuntu place d'ailleurs
`/usr/local/bin` **avant** `/usr/bin` : ton binaire l'emporte, ce qui est
cohérent avec l'idée que l'administrateur local décide en dernier.

**Ce que le paquet apporte, concrètement.** Il fait entrer l'outil dans la base
dpkg. À partir de là, et seulement à partir de là :

```bash
dpkg -S /usr/local/bin/horodate    # d'où vient ce fichier ?
dpkg -l | grep horodate            # quelle version sur quelle machine ?
sudo apt purge horodate-lab        # désinstallation complète et fiable
dpkg -V horodate-lab               # le binaire a-t-il été modifié ?
```

Ces quatre questions sont exactement celles qu'un audit, un incident de sécurité
ou une migration posent. Avec `make install`, aucune n'a de réponse.

**Le numéro de version.** `1.4-1` : `1.4` est la version **amont**, `-1` la
révision du **paquet**. Reconstruire le paquet sans changer le code donne
`1.4-2`. Cette convention n'est pas décorative : elle permet la comparaison de
versions Debian, donc les mises à jour, donc `apt upgrade`. Si le prestataire
livre `1.5`, ton `1.5-1` sera bien supérieur à `1.4-1` et apt fera son travail.

**`--root-owner-group`.** Sans cette option, `dpkg-deb` enregistre l'UID/GID de
l'utilisateur qui construit. Le paquet installe alors des fichiers appartenant à
`mathieu` (UID 1000) dans `/usr/local/bin` — et sur une machine où l'UID 1000
est quelqu'un d'autre, tu viens de donner à cette personne le droit d'écrire un
binaire exécuté en root. L'option force `root:root`, ce qui est le comportement
attendu.
:::

::: piege
La tentation, à l'étape 4, est de construire le paquet **depuis la racine
factice contenant déjà `DEBIAN/`** en oubliant que `dpkg-deb --build` prend le
répertoire parent comme contenu. Autre piège fréquent : laisser des fichiers
appartenant à l'utilisateur dans l'arborescence, ou oublier `Architecture:`.
Un `Architecture: all` sur un binaire compilé est une faute silencieuse : le
paquet s'installera sur ARM et le binaire ne s'exécutera pas. Ici, `amd64`.
:::

---

### **L10.5** — Le même travail sous Rocky 9

*Inventaire, dépôt signé, `dnf history`, modules, EPEL, `dnf-automatic`.*

**1. Inventaire**

```bash
rpm -qa | wc -l                       # nombre de paquets
rpm -qf /usr/sbin/sshd                # openssh-server-8.7p1-...
rpm -ql chrony                        # fichiers livrés
rpm -Va 2>/dev/null | awk '$2 == "c"' # conffiles modifiés
```

**2. Dépôt interne signé**

```bash
sudo rpm --import http://127.0.0.1:8099/RPM-GPG-KEY-lab
rpm -q gpg-pubkey --qf '%{VERSION}-%{RELEASE} %{SUMMARY}\n' | grep lab

sudo tee /etc/yum.repos.d/depot-lab.repo >/dev/null <<'EOF'
[depot-lab]
name=Depot interne du lab
baseurl=http://127.0.0.1:8099/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=http://127.0.0.1:8099/RPM-GPG-KEY-lab
EOF

sudo dnf clean metadata
dnf repolist
```

**3-4-5. Installer, historiser, annuler**

```bash
sudo dnf install -y outil-lab
dnf repoquery --installed --qf '%{name} %{from_repo}' outil-lab
#   outil-lab depot-lab

dnf history list | head -5
sudo dnf history info 12
sudo dnf history undo 12
rpm -q outil-lab                      # package outil-lab is not installed
sudo dnf install -y outil-lab
dnf history list | head -3
```

**6. Modules**

```bash
dnf module list nodejs
sudo dnf module reset nodejs
sudo dnf module enable -y nodejs:20
dnf module list nodejs | grep '\[e\]'
sudo dnf module reset nodejs
```

**7. EPEL, avec précaution**

```bash
dnf list available | wc -l            # avant
sudo dnf install -y epel-release
dnf list available | wc -l            # après
# paquets installés qu'EPEL propose en version supérieure :
dnf list --upgrades --disablerepo='*' --enablerepo='epel'
```

**8. `dnf-automatic`, sécurité seulement**

```bash
sudo dnf install -y dnf-automatic
sudo sed -i \
  -e 's/^upgrade_type = .*/upgrade_type = security/' \
  -e 's/^download_updates = .*/download_updates = yes/' \
  -e 's/^apply_updates = .*/apply_updates = yes/' \
  -e 's/^reboot = .*/reboot = never/' \
  /etc/dnf/automatic.conf
sudo systemctl enable --now dnf-automatic.timer
systemctl list-timers dnf-automatic.timer
sudo bash check_M10_05.sh
```

::: pourquoi
**`gpgcheck` et `repo_gpgcheck` ne sont pas la même chose**, et c'est la
première subtilité à comprendre. `gpgcheck=1` vérifie la signature de **chaque
RPM** — RPM signe les paquets individuellement, contrairement à Debian qui signe
l'index. `repo_gpgcheck=1` vérifie en plus la signature des **métadonnées** du
dépôt (`repomd.xml.asc`). Le modèle Debian n'a besoin que du second parce que
tout découle de l'index ; le modèle RPM permet les deux, et la configuration
sûre les active tous les deux.

**`rpm --import` alimente une pseudo-base.** Les clés importées apparaissent
comme des paquets `gpg-pubkey-<keyid>-<date>`. On les liste avec
`rpm -q gpg-pubkey --qf '%{SUMMARY}\n'`, et on en supprime une avec
`rpm -e gpg-pubkey-xxxxxxxx-yyyyyyyy`. C'est déroutant la première fois, et
c'est la réponse à « comment je sais quelles clés cette machine accepte ? ».

**`from_repo` est la preuve d'origine.** `rpm -q` ne dit que la version.
`dnf repoquery --installed --qf '%{from_repo}'` dit **d'où le paquet vient**.
Un `@commandline` ou un `@System` signale un `rpm -i` manuel — exactement
l'équivalent de la section « Hors dépôt officiel » de L10.1.

**Le risque EPEL.** EPEL est un dépôt communautaire, non supporté par Red Hat,
dont la priorité est la même que celle des dépôts de base. Deux conséquences :
un paquet d'EPEL peut **remplacer** un paquet de base lors d'une mise à jour, et
l'ajouter en production sans protection est la cause classique des « ma machine
RHEL a des paquets que le support refuse de dépanner ». La protection se pose
avec l'option native `priority=` du fichier `.repo` (une valeur plus grande est **moins** prioritaire : `priority=1` sur BaseOS/AppStream, EPEL au défaut 99) ou en excluant
explicitement ce qui doit rester en version distribution :

```ini
[epel]
...
excludepkgs=nginx*,postgresql*
```

**`reboot = never`** dans `automatic.conf` : même raisonnement qu'en QO10.6. On
applique les correctifs, on ne décide pas de l'arrêt du service à la place de
l'exploitant.
:::

::: piege
`dnf history undo` échoue avec `Package ... not available` si l'ancien RPM n'est
plus ni dans le dépôt ni dans le cache. Sur une machine où l'on veut vraiment
pouvoir revenir en arrière, on met `keepcache=1` dans `/etc/dnf/dnf.conf` — et
on surveille la taille de `/var/cache/dnf`. Sans cela, `history` garde la trace
de ce qui a été fait mais ne peut plus le défaire : on a le journal, pas le
retour arrière.
:::

---

## 10.7 Break & Fix

### **BF10.1** — « Plus rien ne s'installe sur cette machine »

**Démarche de diagnostic**

```bash
# 1. lire le message en entier : il contient le correctif
sudo apt install tree
#   E: dpkg was interrupted, you must manually run 'dpkg --configure -a'
#      to correct the problem.

# 2. avant d'obéir, comprendre : qu'est-ce qui est en attente ?
dpkg --audit
sudo ls -la /var/lib/dpkg/updates/

# 3. quels paquets ne sont pas en ii ?
dpkg-query -f '${db:Status-Abbrev} ${binary:Package}\n' -W | grep -v '^ii '
#   iF  outil-lab
```

```console
$ dpkg --audit
The following packages are only half configured, probably due to problems
configuring them the first time.  The configuration should be retried using
dpkg --configure <package> or the configure menu option in dselect:
 outil-lab            Outillage interne du lab (module 10)
```

**Cause racine — il y en a deux**

1. **Le journal dpkg.** Un fichier au nom numérique (`0042`) traîne dans
   `/var/lib/dpkg/updates/`. apt appelle `debSystem::CheckUpdates()` au
   démarrage, y voit la trace d'une transaction interrompue, et refuse de poser
   son verrou. C'est ce qui produit le message, **avant même** toute résolution
   de dépendances.
2. **Le paquet en `iF`.** `outil-lab` 1.3.0 a été déballé, mais son `postinst`
   a échoué : il exige `/etc/outil-lab/licence.key`, qui n'existe pas.

Le premier bloque apt ; le second empêche `dpkg --configure -a` de finir.

**Correctif**

```bash
# étape 1 : rejouer le journal et reprendre les configurations en attente
sudo dpkg --configure -a
```

```console
Setting up outil-lab (1.3.0) ...
outil-lab: /etc/outil-lab/licence.key manquant
dpkg: error processing package outil-lab (--configure):
 installed outil-lab package post-installation script subprocess returned
 error exit status 1
Errors were encountered while processing:
 outil-lab
```

```bash
# étape 2 : le message dit exactement ce qui manque. On le fournit.
sudo touch /etc/outil-lab/licence.key
sudo dpkg --configure -a
#   Setting up outil-lab (1.3.0) ...

# étape 3 : contrôle
dpkg -l outil-lab | tail -1
#   ii  outil-lab  1.3.0  all  Outillage interne du lab (module 10)
sudo apt install -y tree      # fonctionne
```

::: pourquoi
Le mécanisme complet, dans l'ordre où il se déroule.

**Déballage et configuration sont deux phases distinctes.** dpkg
`--unpack` écrit les fichiers et enregistre l'état `iU` ; `--configure` exécute
le `postinst` et passe en `ii`. Entre les deux, le paquet est sur le disque mais
inactif. Cette séparation existe pour gérer les dépendances circulaires à la
configuration.

**`iU` contre `iF`.** `iU` = déballé, configuration pas encore tentée.
`iF` = configuration tentée et **échouée** en cours de route. Ici c'est `iF`,
parce que le `postinst` a bien démarré et a rendu un code d'erreur. La
distinction compte pour le diagnostic : `iF` veut dire « lis la sortie du
postinst », `iU` veut dire « la transaction a été coupée ».

**Le journal `/var/lib/dpkg/updates/`.** dpkg y écrit des fichiers numérotés
pendant qu'il modifie `status`. En fonctionnement normal, ils sont consommés et
le répertoire est vide. apt ne regarde que le **nom** : une suite de chiffres
suffit à déclencher le refus. `dpkg --configure -a` rejoue le journal et le vide
— même quand la configuration d'un paquet échoue, comme on le voit ici : après
la première commande, apt fonctionne à nouveau, mais `outil-lab` reste en `iF`.

**Pourquoi on ne purge pas.** La solution de facilité serait
`dpkg --purge --force-all outil-lab`. Elle « marche », et elle supprime la seule
information intéressante : *pourquoi* le postinst a échoué. En production, ce
postinst existe pour une raison — un fichier de licence, une base à créer, un
certificat. Le purger, c'est déplacer l'incident au prochain déploiement.
:::

::: piege
Deux erreurs classiques sur cette panne :

**Supprimer `/var/lib/dpkg/updates/*` à la main.** Ça fait disparaître le
message, et sur une vraie transaction interrompue, ça abandonne des changements
de `status` non appliqués — la base devient incohérente avec le disque. Le
journal se rejoue, il ne se supprime pas.

**Restaurer `/var/lib/dpkg/status-old`.** C'est la copie précédente du fichier
d'état. La restaurer fait oublier à dpkg tout ce qui a été installé depuis. Ce
fichier est utile en dernier recours sur un `status` réellement corrompu (avec
une copie de `status` avant toute manipulation), jamais sur une transaction
interrompue.
:::

---

### **BF10.2** — « Le dépôt de l'équipe ne marche plus »

**Démarche de diagnostic**

```bash
# 1. le dépôt répond-il ? (on élimine le réseau)
curl -sI http://127.0.0.1:8099/InRelease | head -1     # HTTP/1.0 200 OK
curl -s  http://127.0.0.1:8099/Packages | head -3      # contenu correct

# 2. que dit apt exactement ?
sudo apt update 2>&1 | grep -A2 8099
```

```console
W: GPG error: http://127.0.0.1:8099 ./ InRelease: The following signatures
   couldn't be verified because the public key is not available:
   NO_PUBKEY 70D3F6C84D6995D5
E: The repository 'http://127.0.0.1:8099 ./ InRelease' is not signed.
```

```bash
# 3. comment la source est-elle déclarée ?
grep -r . /etc/apt/sources.list.d/ | grep 8099
#   /etc/apt/sources.list.d/depot-lab.list:deb http://127.0.0.1:8099 ./
#   -> format une-ligne, AUCUN signed-by

# 4. la clé est-elle quelque part ?
ls -la /etc/apt/keyrings/ /etc/apt/trusted.gpg.d/
# 5. qui a signé ? l'identifiant est dans le message : 70D3F6C84D6995D5
gpg --show-keys --with-fingerprint /srv/depot-lab/depot-lab.asc
```

**Cause racine**

La source a été réécrite au format une-ligne sans `signed-by=`, et la clé
publique a été retirée de `/etc/apt/keyrings`. apt reçoit un `InRelease`
correctement signé mais ne possède aucune clé pour en vérifier la signature.
Il en conclut que le dépôt n'est pas authentifiable, l'écarte entièrement, et
les paquets qu'il publie deviennent introuvables — d'où le
`E: Unable to locate package outil-lab` alors que `curl` fonctionne.

**Correctif**

```bash
# 1. récupérer la clé et VÉRIFIER son empreinte avant de l'installer
gpg --show-keys --with-fingerprint /srv/depot-lab/depot-lab.asc
#   B92E A8B6 8C03 11BE 89F5  9CED 70D3 F6C8 4D69 95D5
#   les 16 derniers hexa = 70D3F6C84D6995D5, l'identifiant du message. OK.

# 2. l'installer, dé-armurée, lisible par _apt
sudo install -m 0755 -d /etc/apt/keyrings
sudo gpg --dearmor -o /etc/apt/keyrings/depot-lab.gpg \
     /srv/depot-lab/depot-lab.asc
sudo chmod 0644 /etc/apt/keyrings/depot-lab.gpg

# 3. réécrire la source en deb822, restreinte à cette clé
sudo rm /etc/apt/sources.list.d/depot-lab.list
sudo tee /etc/apt/sources.list.d/depot-lab.sources >/dev/null <<'EOF'
Types: deb
URIs: http://127.0.0.1:8099
Suites: ./
Signed-By: /etc/apt/keyrings/depot-lab.gpg
EOF

# 4. contrôle
sudo apt update          # aucune ligne W: ni E: pour 8099
sudo apt install -y outil-lab
apt-cache policy outil-lab
```

**Prévention**

* proscrire `[trusted=yes]` par une règle de revue, et le chercher
  automatiquement : `grep -rn 'trusted=yes' /etc/apt/` dans le script d'audit ;
* déployer les dépôts par gestion de configuration (Ansible), jamais à la main
  pendant une astreinte ;
* surveiller la **date d'expiration** des clés de dépôt : `gpg --show-keys`
  l'affiche, et une clé expirée casse `apt update` un matin sans prévenir.

::: pourquoi
Il faut savoir décomposer le message, parce que c'est ce qu'on demandera de
faire à voix haute.

`NO_PUBKEY 70D3F6C84D6995D5` : l'identifiant long (64 bits) de la clé qui a
**effectivement** signé le fichier. apt l'extrait de la signature elle-même.
C'est une information exploitable : elle permet de vérifier que la clé qu'on
s'apprête à installer est bien celle qui a signé, et pas une autre clé du même
éditeur.

`The repository ... is not signed.` : formulation trompeuse. Le dépôt **est**
signé. apt veut dire « je ne peux pas établir qu'il l'est », et sa politique par
défaut (`Acquire::AllowInsecureRepositories "false"`) est de traiter les deux cas
de la même manière — ce qui est la bonne politique.

**Le comportement change s'il existe un index en cache.** Avec un
`/var/lib/apt/lists/` déjà rempli pour ce dépôt, apt affiche
`W: An error occurred during the signature verification. The repository is not
updated and the previous index files will be used.` et continue de fonctionner
sur les anciennes données. C'est le pire des cas en exploitation : le symptôme
est un simple avertissement, et la machine installe silencieusement des paquets
depuis un index qui n'est plus rafraîchi. C'est pour cela qu'un script d'audit
doit traiter tout `W: GPG error` comme une erreur.

**Ce qu'aurait fait `[trusted=yes]`.** apt aurait cessé de vérifier quoi que ce
soit sur ce dépôt : plus de signature, plus de garantie d'intégrité. Un attaquant
capable de répondre à la place de `127.0.0.1:8099` — ou, dans la vraie vie,
d'intercepter le HTTP vers un dépôt interne — aurait pu faire installer
n'importe quel paquet en root. Le symptôme aurait disparu, et c'est exactement ce
qui rend l'option dangereuse : elle est efficace.
:::

---

### **BF10.3** — « La mise à jour de sécurité ne passe pas »

**Démarche de diagnostic**

```bash
# 1. le dépôt propose-t-il vraiment la 1.2.0 ?
sudo apt update
apt-cache madison outil-lab
#   outil-lab | 1.2.0 | ...
#   outil-lab | 1.0.0 | ...

# 2. pourquoi apt ne la prend-il pas ?
apt-cache policy outil-lab
```

```console
outil-lab:
  Installed: 1.0.0
  Candidate: 1.0.0            <- la candidate n'est PAS la plus récente
  Version table:
     1.2.0 500
        500 http://127.0.0.1:8099 ./ Packages
 *** 1.0.0 1001               <- priorite 1001 : un epinglage
        500 http://127.0.0.1:8099 ./ Packages
        100 /var/lib/dpkg/status
```

```bash
# 3. les deux endroits où un gel peut se cacher
apt-mark showhold
#   outil-lab
grep -r . /etc/apt/preferences.d/ /etc/apt/preferences 2>/dev/null
#   /etc/apt/preferences.d/80-outil-lab-gel.pref:Package: outil-lab
#   /etc/apt/preferences.d/80-outil-lab-gel.pref:Pin: version 1.0.0
#   /etc/apt/preferences.d/80-outil-lab-gel.pref:Pin-Priority: 1001

# 4. confirmation du hold par l'autre chemin
dpkg --get-selections outil-lab
#   outil-lab       hold
```

**Cause racine**

Deux mécanismes **indépendants** sont en place :

1. un `apt-mark hold`, stocké dans `/var/lib/dpkg/status` — il fait échouer
   `apt install -y` avec
   `E: Held packages were changed and -y was used without
   --allow-change-held-packages.` ;
2. un épinglage `Pin-Priority: 1001` sur la 1.0.0 dans
   `/etc/apt/preferences.d/80-outil-lab-gel.pref` — il rend la 1.0.0
   **candidate**, ce qui explique que `apt list --upgradable` ne propose rien.

Chacun seul suffirait à bloquer la montée, mais avec des symptômes différents.
C'est pour cela qu'en lever un ne change rien de visible, et qu'on croit s'être
trompé de piste.

**Correctif**

```bash
# 1. lever l'épinglage (le fichier est daté d'un incident clos)
sudo rm /etc/apt/preferences.d/80-outil-lab-gel.pref
sudo apt update
apt-cache policy outil-lab         # Candidate: 1.2.0
apt list --upgradable | grep outil-lab
#   outil-lab/stable 1.2.0 all [upgradable from: 1.0.0]   <- réapparu

# 2. lever la retenue
sudo apt-mark unhold outil-lab     # Canceled hold on outil-lab.
apt-mark showhold                  # (vide)

# 3. appliquer
sudo apt install -y outil-lab
dpkg -l outil-lab | tail -1        # ii  outil-lab  1.2.0
```

**Commande d'audit qui aurait évité l'incident**

```bash
#!/usr/bin/env bash
# audit-gels.sh — à passer en revue mensuelle sur tout le parc
set -uo pipefail
echo "== Retenues apt-mark =="
apt-mark showhold | sed 's/^/  /' || true
echo "== Épinglages =="
grep -rns '^Package:\|^Pin:\|^Pin-Priority:' \
     /etc/apt/preferences /etc/apt/preferences.d/ 2>/dev/null \
  | sed 's/^/  /'
echo "== Versions supérieures disponibles mais non candidates =="
apt-cache dumpavail >/dev/null 2>&1
dpkg-query -f '${binary:Package}\n' -W | while read -r p; do
  pol=$(apt-cache policy "$p" 2>/dev/null)
  inst=$(printf '%s' "$pol" | awk '/Installed:/ {print $2}')
  cand=$(printf '%s' "$pol" | awk '/Candidate:/ {print $2}')
  dispo=$(apt-cache madison "$p" 2>/dev/null \
          | awk -F'|' 'NR==1 {gsub(/ /,"",$2); print $2}')
  [ -n "$dispo" ] && [ "$cand" = "$inst" ] && [ "$dispo" != "$inst" ] \
    && printf '  %s : installe %s, dispo %s, candidate %s\n' \
              "$p" "$inst" "$dispo" "$cand"
done
```

::: pourquoi
Le point pédagogique de cette panne est qu'**un symptôme identique peut avoir
deux causes situées à deux endroits différents du système**, et que les
commandes de diagnostic ne les voient pas toutes les deux.

`apt-mark showhold` ne voit **que** la base dpkg. Un ingénieur qui s'arrête là
lève le hold, relance `apt upgrade`, ne voit toujours rien bouger, et conclut
que le dépôt est en cause.

`apt-cache policy` ne voit **que** le calcul de candidate. Un ingénieur qui
s'arrête là supprime l'épinglage, relance `apt install -y`, tombe sur
`E: Held packages were changed...` et conclut qu'il a mal supprimé le fichier.

La règle à retenir tient en une ligne : **les deux mécanismes de gel se
vérifient toujours ensemble**, parce qu'ils ne se stockent pas au même endroit.
`apt-mark showhold` **et** `grep -r . /etc/apt/preferences.d/`.

Nuance à connaître sur les effets exacts :

| | `hold` | épinglage 1001 sur 1.0.0 |
|---|---|---|
| `apt list --upgradable` | montre la 1.2.0 | ne montre rien |
| `apt upgrade` | ignore le paquet | rien à faire (candidate = installée) |
| `apt install -y p=1.2.0` | `E: Held packages...` | fonctionne |
| `apt install p=1.2.0` interactif | demande confirmation, puis passe | fonctionne |

Le `hold` n'est donc **pas** une interdiction : il protège des opérations en lot
et des commandes non interactives. C'est exactement ce qu'on veut d'un gel de
maintenance, et ce n'est pas ce qu'on veut d'une politique de sécurité.
:::

::: piege
La tentation, sous pression du responsable sécurité, est le `dpkg -i` du paquet
récupéré à la main. Il « passe » : dpkg ignore les épinglages, qui sont un
concept d'apt, et le hold n'empêche pas dpkg d'agir. Mais on se retrouve avec un
paquet installé hors dépôt (donc dans la section « Hors dépôt officiel » de
L10.1), un hold toujours actif qui bloquera la mise à jour suivante, et un
épinglage toujours en place qui rétrogradera le paquet au prochain
`apt install`. On a déplacé l'incident, pas résolu.
:::

---

### **BF10.4** — « apt veut désinstaller la moitié du serveur »

**Démarche de diagnostic**

```bash
# 1. LIRE avant de répondre. Et simuler, jamais exécuter.
sudo apt-get -s upgrade | head -20
```

```console
Calculating upgrade...
The following packages will be DOWNGRADED:
  apt base-files binutils binutils-common bsdutils bzip2 coreutils
  curl dbus dpkg dpkg-dev e2fsprogs git gnupg gzip less libc6 ...
```

```bash
# 2. « DOWNGRADED » : le mot-clé oriente tout le diagnostic.
#    Une rétrogradation de masse ne peut venir que d'une priorité > 1000.
apt-cache policy libc6
```

```console
libc6:
  Installed: 2.39-0ubuntu8.4
  Candidate: 2.39-0ubuntu8
  Version table:
 *** 2.39-0ubuntu8.4 500
        500 http://archive.ubuntu.com/ubuntu noble-updates/main amd64
        500 http://security.ubuntu.com/ubuntu noble-security/main amd64
        100 /var/lib/dpkg/status
     2.39-0ubuntu8 1001            <- 1001 sur un paquet quelconque
       1001 http://archive.ubuntu.com/ubuntu noble/main amd64 Packages
```

```bash
# 3. 1001 sur un paquet pris au hasard => l'épinglage est global.
grep -rns . /etc/apt/preferences /etc/apt/preferences.d/ 2>/dev/null
```

```console
/etc/apt/preferences.d/00-socle-fige.pref:4:Package: *
/etc/apt/preferences.d/00-socle-fige.pref:5:Pin: release a=noble
/etc/apt/preferences.d/00-socle-fige.pref:6:Pin-Priority: 1001
```

**Cause racine**

Trois erreurs cumulées dans un seul fichier :

* `Package: *` — l'épinglage vise **tous** les paquets ;
* `Pin: release a=noble` — `a=` désigne l'**archive**, et `noble` est l'archive
  figée au jour de la sortie. Les correctifs vivent dans les archives séparées
  `noble-updates` et `noble-security`, que ce pin ne couvre pas ;
* `Pin-Priority: 1001` — au-dessus de 1000, donc autorisation de rétrograder.

Résultat : tout ce qui a été mis à jour depuis la sortie voit la version
d'origine devenir candidate avec une priorité écrasante, et apt propose de
revenir à l'état d'avril 2024 — `apt`, `dpkg` et `libc6` compris.

**Correctif, en conservant l'intention initiale**

L'auteur voulait « rester sur la release, ne pas prendre les nouveautés ». La
traduction correcte n'est pas de rétrograder, c'est de **ne pas monter** vers
les backports et les dépôts tiers, tout en gardant la sécurité :

```bash
sudo rm /etc/apt/preferences.d/00-socle-fige.pref
sudo apt update
sudo apt-get -s upgrade | head -5      # plus aucun DOWNGRADED
```

```bash
# si l'on veut vraiment exprimer l'intention, sans la faute :
sudo tee /etc/apt/preferences.d/00-socle.pref >/dev/null <<'EOF'
# Intention CHG-4402 : pas de backports automatiques.
# La securite (noble-security) et les correctifs (noble-updates)
# restent a leur priorite normale : ce sont eux qu'on VEUT.
Package: *
Pin: release a=noble-backports
Pin-Priority: 100
EOF
```

**Contrôle qu'aucune rétrogradation n'a eu lieu**

```bash
sudo apt-get -s upgrade | grep -ci downgrad        # 0
apt-cache policy | head -12                        # priorités normales
dpkg-query -W -f '${Package}=${Version}\n' | sort \
  > ~/lab10/rapports/manifeste-$(date +%F).txt
# comparer avec le manifeste de la veille s'il existe
```

::: pourquoi
Il faut savoir **remonter d'un symptôme à la bonne famille de causes**, et c'est
là toute la valeur de cette panne.

Le mot `DOWNGRADED` dans une sortie apt ne peut avoir qu'une seule origine :
une priorité **strictement supérieure à 1000**. C'est la seule situation où apt
s'autorise à descendre une version. Il n'est donc pas nécessaire de chercher au
hasard : on sait d'emblée qu'il existe un `Pin-Priority` > 1000 quelque part, et
il n'y a que deux endroits possibles, `/etc/apt/preferences` et
`/etc/apt/preferences.d/`.

Le deuxième réflexe — `apt-cache policy` sur un paquet **au hasard**, sans
rapport avec le sujet — est ce qui distingue un diagnostic d'une devinette. Si
`libc6` est épinglé à 1001, l'épinglage est global. Si `libc6` est normal, il est
ciblé et on cherche ailleurs. Une commande, une bifurcation.

Et le point de fond, qui dépasse apt : **`a=noble` n'est pas « Ubuntu 24.04 »,
c'est « Ubuntu 24.04 tel qu'il était le jour de sa sortie »**. La confusion vient
de ce que le nom de code sert à la fois de nom de version (`n=noble`) et de nom
d'archive (`a=noble`). Sur Ubuntu, le modèle est :

```text
noble             figé le jour de la sortie, ne bouge plus jamais
noble-updates     corrections de bogues post-sortie
noble-security    corrections de sécurité (URI et infrastructure séparées)
noble-backports   versions récentes rétroportées, priorité 100
```

Épingler `a=noble` revient donc à s'interdire toute correction. C'est le
contraire de ce que voulait l'auteur du fichier, et c'est la raison pour
laquelle le correctif ne consiste pas seulement à supprimer le fichier : il faut
traduire correctement son intention, sinon quelqu'un le réécrira dans six mois.
:::

::: piege
Deux erreurs de réparation à ne pas commettre.

**Baisser la priorité à 999 au lieu de supprimer.** Les rétrogradations
disparaissent — mais les paquets de `noble-updates` et `noble-security` restent
derrière `noble` à 999 contre 500. Les mises à jour de sécurité ne sont plus
proposées du tout, et cette fois **sans aucun symptôme visible**. On a transformé
une panne bruyante en faille silencieuse, ce qui est strictement pire.

**Supprimer le fichier sans rien dire.** Son auteur avait une intention, portée
par un ticket de changement. Si on se contente de supprimer, le même fichier
réapparaîtra. Le correctif complet comprend la traduction correcte de
l'intention et un mot dans le ticket.
:::

---

## 10.8 Défi du module

**D10 — Politique de mise à jour du parc**

*Livrables : un script d'audit, une configuration `unattended-upgrades`, une
politique écrite.*

### Le script `~/lab10/bin/etat-paquets.sh`

```bash
#!/usr/bin/env bash
# etat-paquets.sh — état des mises à jour et des gels d'une machine.
# Rapport Markdown sur stdout, diagnostic sur stderr.
# Sortie : 0 = conforme, 1 = au moins une derive.
set -euo pipefail

DERIVE=0
trace() { printf '[%s] %s\n' "$(date +%T)" "$*" >&2; }
signaler() { DERIVE=1; }

trace "collecte de l'état dpkg"
etat() { dpkg-query -f \
  '${db:Status-Abbrev} ${binary:Package} ${Version}\n' -W 2>/dev/null; }

printf '# État des paquets — %s — %s\n\n' "$(hostname -f)" "$(date +%F' '%T)"
printf 'Définition d une **dérive** : paquet en état autre que `ii`, mise à\n'
printf 'jour de sécurité en attente, retenue `apt-mark hold`, épinglage de\n'
printf 'portée globale, fichier `.dpkg-dist`/`.dpkg-old` non traité, ou\n'
printf 'redémarrage requis.\n\n'

# --- 1. volumétrie -----------------------------------------------------
printf '## Paquets\n\n'
INST=$(etat | grep -c '^ii ' || true)
SEC=$(apt-cache policy 2>/dev/null | grep -c 'a=[a-z]*-security' || true)
printf -- '- installés : **%d**\n' "$INST"
printf -- '- dépôts de sécurité configurés : %d\n\n' "$SEC"

# --- 2. mises à jour en attente ----------------------------------------
trace "calcul des mises à jour en attente"
printf '## Mises à jour en attente\n\n'
UPG=$(apt list --upgradable 2>/dev/null | tail -n +2 || true)
SECU=$(printf '%s\n' "$UPG" | grep -i 'security' || true)
AUTRES=$(printf '%s\n' "$UPG" | grep -iv 'security' | grep . || true)
NSEC=$(printf '%s' "$SECU" | grep -c . || true)
printf -- '- sécurité : **%d**\n' "$NSEC"
printf -- '- autres : %d\n\n' "$(printf '%s' "$AUTRES" | grep -c . || true)"
[ "$NSEC" -gt 0 ] && { signaler; printf '```text\n%s\n```\n\n' "$SECU"; }

# --- 3. paquets retenus ------------------------------------------------
trace "recherche des retenues apt-mark"
printf '## Paquets retenus (apt-mark hold)\n\n'
HOLDS=$(apt-mark showhold 2>/dev/null || true)
if [ -z "$HOLDS" ]; then
  printf 'Aucun.\n\n'
else
  signaler
  printf '| paquet | installée | disponible |\n|---|---|---|\n'
  while read -r p; do
    i=$(dpkg-query -f '${Version}' -W "$p" 2>/dev/null || echo '?')
    d=$(apt-cache madison "$p" 2>/dev/null \
        | awk -F'|' 'NR==1 {gsub(/ /,"",$2); print $2}')
    printf '| %s | %s | %s |\n' "$p" "$i" "${d:-inconnue}"
  done <<< "$HOLDS"
  printf '\n'
fi

# --- 4. épinglages -----------------------------------------------------
trace "analyse des épinglages"
printf '## Épinglages\n\n'
FICHIERS=$(ls -1 /etc/apt/preferences.d/ 2>/dev/null || true)
[ -f /etc/apt/preferences ] && FICHIERS="preferences"$'\n'"$FICHIERS"
if [ -z "$FICHIERS" ]; then
  printf 'Aucun fichier d épinglage.\n\n'
else
  printf '| fichier | Package: | priorité | portée |\n|---|---|---|---|\n'
  while read -r f; do
    [ -n "$f" ] || continue
    c="/etc/apt/preferences.d/$f"
    [ "$f" = preferences ] && c=/etc/apt/preferences
    pk=$(awk -F': *' '/^Package:/ {print $2; exit}' "$c")
    pr=$(awk -F': *' '/^Pin-Priority:/ {print $2; exit}' "$c")
    if [ "$pk" = '*' ]; then portee='**GLOBALE**'; signaler
    else portee="$(printf '%s' "$pk" | wc -w) paquet(s)"; fi
    printf '| %s | %s | %s | %s |\n' "$f" "$pk" "$pr" "$portee"
    [ "${pr:-0}" -gt 1000 ] 2>/dev/null && signaler
  done <<< "$FICHIERS"
  printf '\n'
fi

# --- 5. états anormaux et conffiles ------------------------------------
trace "vérification des états dpkg et des conffiles"
printf '## États anormaux\n\n'
ANO=$(etat | grep -v '^ii ' || true)
if [ -z "$ANO" ]; then printf 'Aucun.\n\n'
else signaler; printf '```text\n%s\n```\n\n' "$ANO"; fi

printf '## Conffiles et résidus\n\n'
MOD=$(dpkg -V 2>/dev/null | awk '$2 == "c" {print $3}' || true)
NMOD=$(printf '%s' "$MOD" | grep -c . || true)
printf -- '- conffiles modifiés : %d\n' "$NMOD"
RES=$(find /etc \( -name '*.dpkg-dist' -o -name '*.dpkg-old' \
                -o -name '*.ucf-dist' \) 2>/dev/null || true)
if [ -n "$RES" ]; then
  signaler
  printf -- '- résidus à traiter :\n\n```text\n%s\n```\n\n' "$RES"
else
  printf -- '- aucun résidu `.dpkg-dist` / `.dpkg-old`\n\n'
fi

# --- 6. redémarrage ----------------------------------------------------
printf '## Redémarrage\n\n'
if [ -f /var/run/reboot-required ]; then
  signaler
  printf 'Redémarrage **requis**. Paquets concernés :\n\n```text\n'
  cat /var/run/reboot-required.pkgs 2>/dev/null || echo '(liste absente)'
  printf '```\n\n'
else
  printf 'Aucun redémarrage requis.\n\n'
fi

trace "terminé, dérive=$DERIVE"
exit "$DERIVE"
```

```bash
chmod +x ~/lab10/bin/etat-paquets.sh
~/lab10/bin/etat-paquets.sh > ~/lab10/rapports/etat-$(date +%F).md
echo "code retour : $?"
```

### La configuration `unattended-upgrades`

```bash
sudo apt install -y unattended-upgrades

sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

sudo tee /etc/apt/apt.conf.d/52unattended-upgrades-local >/dev/null <<'EOF'
// Reglages locaux du lab — CHG-4501.
// Volontairement dans un fichier separe : 50unattended-upgrades est un
// conffile du paquet unattended-upgrades. Y ecrire declencherait le
// prompt dpkg a chaque mise a jour du paquet, et nos reglages seraient
// perdus ou sauvegardes en .dpkg-old selon la reponse de l operateur.
// Les fichiers de /etc/apt/apt.conf.d sont lus par ordre alphabetique :
*/ 52 passe apres 50, donc nos valeurs simples gagnent. Les LISTES, elles,
*/ s'ajoutent a celles de 50 : #clear les vide avant de les redefinir.
#clear Unattended-Upgrade::Allowed-Origins;

Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

// Paquets applicatifs exclus : toute entree porte un ticket et une date
// de revue. Liste vide = point de rendez-vous documente, pas un oubli.
Unattended-Upgrade::Package-Blacklist {
//  "outil-lab";   // INC-3390 — revue 2026-12-01
};

Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Mail "";
Unattended-Upgrade::SyslogEnable "true";
EOF

sudo unattended-upgrade --dry-run --debug 2>&1 \
  | tee ~/lab10/rapports/uu-dry-run.log | tail -20
systemctl list-timers apt-daily.timer apt-daily-upgrade.timer
sudo bash check_M10_06.sh
```

### Le rapport `~/lab10/rapports/politique-maj.md`

Structure attendue : politique en une page (automatisé / jamais automatisé),
traitement du redémarrage, procédure d'exclusion temporaire avec date de revue,
stratégie de rollback et ses limites, revue mensuelle des gels.

::: pourquoi
Trois idées que le défi cherche à ancrer, et une quatrième qu'on découvre en le
faisant.

**Ne pas écrire dans le conffile d'un paquet.** `50unattended-upgrades` est
déclaré comme conffile par le paquet `unattended-upgrades`. Le modifier garantit
un prompt dpkg à chaque mise à jour du paquet, sur chaque machine du parc, en
plein `unattended-upgrades` — c'est-à-dire sans personne pour répondre. Selon
l'option `--force-conf*` du parc, soit la configuration locale est écrasée
silencieusement, soit la nouvelle version du mainteneur atterrit en
`.dpkg-dist` et n'est jamais relue. Le bon réflexe, valable bien au-delà d'apt,
est : **un fichier à soi dans un répertoire `.d`, nommé pour passer après**.
`/etc/apt/apt.conf.d/` est lu dans l'ordre alphabétique, d'où le `52`. Piège propre à apt : une valeur simple est remplacée, mais une **liste** (`Allowed-Origins`) se cumule avec celle de `50unattended-upgrades` — d'où le `#clear` qui la vide avant de la redéfinir.

**Le rapport sur stdout, la trace sur stderr.** Ce n'est pas une coquetterie :
c'est ce qui rend le script composable. `etat-paquets.sh > rapport.md` produit un
Markdown propre, `etat-paquets.sh 2>/dev/null | mail -s ...` marche, et la
trace reste visible en interactif. Un script qui mélange les deux n'est
utilisable qu'à la main.

**Le code retour porte l'information.** `0` conforme, `1` dérive. C'est ce qui
permet de le brancher dans une supervision (`check_by_ssh`, un `ExecStart` de
service systemd, une tâche Ansible avec `failed_when`). Un script d'audit qui ne
sort jamais qu'en 0 ne peut pas être supervisé — et un audit qu'on ne supervise
pas n'est pas un audit, c'est une bonne intention.

**La quatrième idée, celle qu'on découvre en écrivant le script :** définir
« dérive » est plus difficile que la coder. Un paquet retenu est-il une dérive ?
Oui s'il traîne depuis six semaines, non s'il a été posé ce matin pour la
maintenance de ce soir. Un conffile modifié ? C'est le cas normal d'un serveur
configuré. Un `.dpkg-dist` ? Toujours une dérive : il signifie qu'une nouvelle
version d'un fichier de configuration attend d'être relue, et personne ne l'a
fait. C'est pour cela que l'énoncé impose d'écrire la définition **dans le
rapport** : elle est la partie discutable du travail, et elle doit être exposée
à la critique, pas enfouie dans un `if`.
:::

::: piege
`Unattended-Upgrade::Remove-Unused-Dependencies "true"` est piégeux : il fait
tourner l'équivalent d'un `autoremove` sans supervision. Sur une machine où un
agent d'exploitation a été installé comme dépendance puis est devenu orphelin, il
disparaît une nuit et personne ne fait le lien. On le laisse à `false`, et on
traite les orphelins en revue.

`Remove-Unused-Kernel-Packages "true"`, en revanche, est utile et sûr : `/boot`
est une petite partition, et un `/boot` plein bloque la mise à jour de noyau
suivante avec un `dpkg: error processing package linux-image-...` en plein
`unattended-upgrades`. C'est un des incidents les plus fréquents sur les parcs
Ubuntu.
:::
