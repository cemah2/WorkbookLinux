<!-- nav:début -->
[Accueil](../../README.md) › [Parcours](../../docs/parcours.md) › Projet C — Une semaine d'astreinte › **Projet C**  
[← Module 32](../../modules/32-fs-avances/README.md) · [Corrigé](corrige.md)

<details><summary>Scripts du module (37)</summary>

Sur la VM indiquée en section « Mise en place », depuis `~/workbook/scripts/` (voir [chapitre 0](../../docs/00-mise-en-place.md)).

| Script | Rôle |
|---|---|
| [`setup_P3.sh`](../../scripts/projects/P3/setup_P3.sh) | prépare le module |
| [`check_PC_1_1.sh`](../../scripts/projects/P3/check_PC_1_1.sh) | vérifie PC.1.1 |
| [`check_PC_1_2.sh`](../../scripts/projects/P3/check_PC_1_2.sh) | vérifie PC.1.2 |
| [`check_PC_1_3.sh`](../../scripts/projects/P3/check_PC_1_3.sh) | vérifie PC.1.3 |
| [`check_PC_1_4.sh`](../../scripts/projects/P3/check_PC_1_4.sh) | vérifie PC.1.4 |
| [`check_PC_2_1.sh`](../../scripts/projects/P3/check_PC_2_1.sh) | vérifie PC.2.1 |
| [`check_PC_2_2.sh`](../../scripts/projects/P3/check_PC_2_2.sh) | vérifie PC.2.2 |
| [`check_PC_2_3.sh`](../../scripts/projects/P3/check_PC_2_3.sh) | vérifie PC.2.3 |
| [`check_PC_2_4.sh`](../../scripts/projects/P3/check_PC_2_4.sh) | vérifie PC.2.4 |
| [`check_PC_3_1.sh`](../../scripts/projects/P3/check_PC_3_1.sh) | vérifie PC.3.1 |
| [`check_PC_3_2.sh`](../../scripts/projects/P3/check_PC_3_2.sh) | vérifie PC.3.2 |
| [`check_PC_3_3.sh`](../../scripts/projects/P3/check_PC_3_3.sh) | vérifie PC.3.3 |
| [`check_PC_4_1.sh`](../../scripts/projects/P3/check_PC_4_1.sh) | vérifie PC.4.1 |
| [`check_PC_4_2.sh`](../../scripts/projects/P3/check_PC_4_2.sh) | vérifie PC.4.2 |
| [`check_PC_4_3.sh`](../../scripts/projects/P3/check_PC_4_3.sh) | vérifie PC.4.3 |
| [`check_PC_4_4.sh`](../../scripts/projects/P3/check_PC_4_4.sh) | vérifie PC.4.4 |
| [`check_PC_5_1.sh`](../../scripts/projects/P3/check_PC_5_1.sh) | vérifie PC.5.1 |
| [`check_PC_5_2.sh`](../../scripts/projects/P3/check_PC_5_2.sh) | vérifie PC.5.2 |
| [`check_PC_5_3.sh`](../../scripts/projects/P3/check_PC_5_3.sh) | vérifie PC.5.3 |
| [`break_PC_1_1.sh`](../../scripts/projects/P3/break_PC_1_1.sh) | installe la panne PC.1.1 |
| [`break_PC_1_2.sh`](../../scripts/projects/P3/break_PC_1_2.sh) | installe la panne PC.1.2 |
| [`break_PC_1_3.sh`](../../scripts/projects/P3/break_PC_1_3.sh) | installe la panne PC.1.3 |
| [`break_PC_1_4.sh`](../../scripts/projects/P3/break_PC_1_4.sh) | installe la panne PC.1.4 |
| [`break_PC_2_1.sh`](../../scripts/projects/P3/break_PC_2_1.sh) | installe la panne PC.2.1 |
| [`break_PC_2_2.sh`](../../scripts/projects/P3/break_PC_2_2.sh) | installe la panne PC.2.2 |
| [`break_PC_2_3.sh`](../../scripts/projects/P3/break_PC_2_3.sh) | installe la panne PC.2.3 |
| [`break_PC_2_4.sh`](../../scripts/projects/P3/break_PC_2_4.sh) | installe la panne PC.2.4 |
| [`break_PC_3_1.sh`](../../scripts/projects/P3/break_PC_3_1.sh) | installe la panne PC.3.1 |
| [`break_PC_3_2.sh`](../../scripts/projects/P3/break_PC_3_2.sh) | installe la panne PC.3.2 |
| [`break_PC_3_3.sh`](../../scripts/projects/P3/break_PC_3_3.sh) | installe la panne PC.3.3 |
| [`break_PC_4_1.sh`](../../scripts/projects/P3/break_PC_4_1.sh) | installe la panne PC.4.1 |
| [`break_PC_4_2.sh`](../../scripts/projects/P3/break_PC_4_2.sh) | installe la panne PC.4.2 |
| [`break_PC_4_3.sh`](../../scripts/projects/P3/break_PC_4_3.sh) | installe la panne PC.4.3 |
| [`break_PC_4_4.sh`](../../scripts/projects/P3/break_PC_4_4.sh) | installe la panne PC.4.4 |
| [`break_PC_5_1.sh`](../../scripts/projects/P3/break_PC_5_1.sh) | installe la panne PC.5.1 |
| [`break_PC_5_2.sh`](../../scripts/projects/P3/break_PC_5_2.sh) | installe la panne PC.5.2 |
| [`break_PC_5_3.sh`](../../scripts/projects/P3/break_PC_5_3.sh) | installe la panne PC.5.3 |

</details>
<!-- nav:fin -->

# Projet C — Une semaine d'astreinte

## C.0 Présentation et règles du jeu

> [!NOTE]
> **Objectifs**
>
> Ce projet est l'**examen final** de la partie exploitation. Il ne t'apprend
> presque aucune commande nouvelle : il te met en situation de t'en servir sous
> pression, pendant cinq jours d'astreinte fictifs sur la plateforme **Factura**.
> À la fin, tu sais :
>
> * prendre un ticket écrit par un non-technicien, en extraire le **symptôme
>   mesurable**, le **périmètre** et les **contraintes**, avant de toucher un
>   clavier ;
> * traiter aussi bien une **demande de changement** (vhost, ouverture de port,
>   compte restreint, purge planifiée) qu'un **incident** (certificat expiré,
>   base saturée, disque plein, intrusion, DNS cassé…) ;
> * respecter des **interdictions d'exploitation** (« pas de reboot », « pas de
>   rollback de snapshot », « pas de redémarrage du service ») et savoir quand,
>   exceptionnellement, les lever — en le traçant ;
> * **communiquer** pendant un incident (message de statut) et **après**
>   (post-mortem blameless) ;
> * mesurer la **disponibilité** d'un service contre un **SLO**, raisonner en
>   **budget d'erreur**, et transformer chaque incident en action d'amélioration
>   **automatisée**.
>
> **Temps estimé** : 12 à 16 h (étalées, comme une vraie semaine d'astreinte).
>
> **Prérequis** : toute la partie système, en particulier les modules 08 (systemd),
> 12 (réseau), 14 (SSH), 16 (logs), 17 (timers), 18 (sécurité) et **19 (dépannage, performance, gestion d'incident)**, dont ce projet est le
> prolongement appliqué. Les huit pannes du module 19 ne sont **pas** rejouées
> ici : les scénarios sont tous différents.

### La plateforme Factura

Tu reprends l'astreinte d'une petite plateforme de facturation. Architecture
supposée en place (les scénarios la déploient dans un état minimal suffisant) :

```text
        Internet / partenaires
                 |
        [lab-web 10.10.10.11]  nginx (443, TLS) --> factura-api (systemd, :8081)
                 |
        [lab-db 10.10.10.12]   PostgreSQL 16 (base factura) + Redis
                 |
        [lab-ops 10.10.10.14]  rsyslog, sauvegardes (timer), NFS,
                               dépôt Git, conteneur factura-worker (Docker)
        [lab-adm 10.10.10.10]  ton poste d'astreinte / bastion
```

Le compte d'astreinte est **`mathieu`** (sudo). Un compte **`deploy`** sert à
la CI. Les secrets applicatifs sont dans `/etc/factura/api.env` sur `lab-web`.

### Mise en place

> [!CAUTION]
> **Attention**
>
> Avant toute chose, snapshot des VM concernées depuis Proxmox. Le rollback
> `qm rollback <vmid> snap-clean` reste le filet de sécurité, mais **l'utiliser
> pendant un scénario vaut échec** : l'objectif est de réparer une machine qu'on
> ne peut pas rembobiner, ce qui est exactement la situation en production.
>
> ```bash
> qm snapshot 9002 avant-P3   # lab-web
> qm snapshot 9003 avant-P3   # lab-db
> qm snapshot 9005 avant-P3   # lab-ops
> ```

Le script de préparation déploie l'état minimal **selon le hostname** (ou
`--role`). Lance-le sur chaque VM que le scénario du jour concerne :

```bash
sudo bash ~/workbook/scripts/projects/P3/setup_P3.sh          # rôle auto
sudo bash ~/workbook/scripts/projects/P3/setup_P3.sh --role db # ou forcé
```

Il installe et démarre : sur **web**, nginx + un certificat signé par la CA de
lab + `factura-api.service` + le compte `deploy` + ufw ; sur **db**, PostgreSQL
16 (base `factura` peuplée) + Redis ; sur **ops**, rsyslog récepteur, le timer
de sauvegarde, un export NFS local, un dépôt Git et — si Docker est présent —
le conteneur `factura-worker`. Chaque scénario est **jouable seul** : tu n'as
besoin que de la VM qu'il désigne.

Vérifie que la plateforme répond :

```bash
curl -s --resolve factura.lab.local:443:127.0.0.1 \
  https://factura.lab.local/sante
```

### Comment se joue un ticket

Chaque scénario est un **vrai ticket** : horodatage, canal (alerte Prometheus,
mail d'un utilisateur, message Slack d'un dev, appel du dirigeant), texte tel
qu'un non-technicien l'écrirait, **priorité**, **contraintes** (fenêtre de
temps, interdictions), et la commande qui installe la situation :

```bash
sudo bash break_PC_X_Y.sh      # met en place le scénario PC.X.Y
```

Tu tiens un **journal de bord** dans `~/astreinte/journal/PC-X-Y.md` : heure,
symptôme, hypothèse, commande, résultat, conclusion. Tu valides la remise en
service avec (les `check` lisent des fichiers réservés à root, d'où `sudo`) :

```bash
sudo bash check_PC_X_Y.sh
```

> [!TIP]
> **Astuce**
>
> Garde **deux sessions SSH** ouvertes sur la VM concernée en permanence. Quand
> une machine part en swap, épuise ses descripteurs ou sature ses inodes, ouvrir
> une nouvelle session devient impossible — celle qui est déjà ouverte tient.

### Règle du jeu et priorités

| Priorité | Sens | Attendu |
|---|---|---|
| P1 | service à l'arrêt | on rétablit d'abord, on comprend ensuite |
| P2 | dégradé / risque | on tranche vite, on trace |
| P3 | gênant, pas urgent | on planifie proprement |

Trois règles non négociables, héritées du module 19 : **une seule modification
à la fois**, **on note tout**, **on préserve les preuves avant de réparer** un
incident majeur. Chaque journée se clôt par un **rapport de fin de journée**
(modèle `~/astreinte/modeles/rapport-journee.md`). La semaine se clôt par la
**revue** (C.6).

---

## C.1 Lundi

*Prise d'astreinte 08:00. SLO du service Factura : 99,5 % sur le mois. Tu
démarres la semaine avec 43 minutes de budget d'erreur déjà consommées ce
mois-ci sur les 216 disponibles.*

### <a id="pc-1-1"></a>[PC.1.1](corrige.md#pc-1-1) — Le site n'est plus en HTTPS

> **Contexte**
>
> **03:14** — canal : alerte Prometheus `SSLCertExpired` (page).
> **08:02** — mail de la responsable commerciale : « Bonjour, ce matin quand je
> vais sur le site des factures mon navigateur affiche un gros avertissement rouge
> "votre connexion n'est pas privée" et refuse d'afficher la page. Les clients
> vont paniquer. C'est urgent, on a une démo à 10h. Merci !! »
>
> Priorité : **P1**. Fenêtre : avant 10:00.
> Interdit : redémarrer la VM.

```bash
sudo bash break_PC_1_1.sh
```

Objectif : rétablir un HTTPS **valide** (chaîne de confiance de la CA de lab
intacte, pas un auto-signé bricolé), sans reboot, et poser la mesure qui fait
qu'un certificat n'expire plus jamais en silence.

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_1_1.sh
> ```

### <a id="pc-1-2"></a>[PC.1.2](corrige.md#pc-1-2) — « Plus personne n'arrive à se connecter à l'appli »

> **Contexte**
>
> **09:36** — Slack, canal #support : « les utilisateurs ont "erreur base de
> données" quand ils se connectent. Moi aussi. Ça marchait hier. » Un peu plus
> tard : « le message exact c'est *FATAL : remaining connection slots are reserved for roles with the SUPERUSER attribute*. »
>
> Priorité : **P1**. Interdit : redémarrer PostgreSQL **hors** de la fenêtre de
> maintenance 12:30–13:00 (une coupure en pleine matinée est refusée par le
> métier).

```bash
sudo bash break_PC_1_2.sh
```

Objectif : rendre l'accès aux utilisateurs **sans** redémarrer la base en
matinée, trouver **qui** mange les connexions, distinguer le réglage de fond du
symptôme, et poser un garde-fou contre les transactions abandonnées.

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_1_2.sh
> ```

### <a id="pc-1-3"></a>[PC.1.3](corrige.md#pc-1-3) — Demande : publier le site de documentation

> **Contexte**
>
> **11:10** — ticket de Julie (dev) : « On a fini la doc de l'API. Les fichiers
> sont dans `/srv/www/docs` sur lab-web. Est-ce que tu peux la mettre en ligne sur
> `docs.factura.lab.local` (en HTTPS bien sûr) avant la fin de journée ? Pas
> pressé, c'est pour la démo de demain. »
>
> Priorité : **P3** (changement). Fenêtre : avant 17:00.
> Contrainte : ne pas casser le vhost principal ; respecter le moindre privilège
> sur les droits de fichiers (la livraison arrive avec des droits douteux).

```bash
sudo bash break_PC_1_3.sh
```

Objectif : nouveau vhost `docs.factura.lab.local` en HTTPS (certificat couvrant
le nom), redirection HTTP→HTTPS, `factura.lab.local` intact, aucun fichier
world-writable dans la racine servie.

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_1_3.sh
> ```

### <a id="pc-1-4"></a>[PC.1.4](corrige.md#pc-1-4) — 502 partout après le déploiement de 15 h

> **Contexte**
>
> **15:12** — appel du dirigeant : « On vient de mettre en ligne la nouvelle
> version et là plus rien ne marche, tout affiche *502 Bad Gateway*. Julie dit que
> son code est bon. Répare, on perd des commandes ! »
> **15:13** — Slack de Julie : « `systemctl status factura-api` dit pourtant
> *active (running)*, je comprends pas. »
>
> Priorité : **P1**. Interdit : **rollback** de la version applicative (le métier
> veut garder la 2.4.0, qui corrige un autre bogue) et reboot de la VM.

```bash
sudo bash break_PC_1_4.sh
```

Objectif : comprendre pourquoi nginx renvoie 502 alors que l'API tourne,
réconcilier la configuration sans revenir à l'ancienne version, et remettre le
service en ligne.

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_1_4.sh
> ```

**Fin de journée :** remplis `~/astreinte/rapports/lundi.md` à partir du modèle.

---

## C.2 Mardi

*Journée « stockage et sauvegardes ». Tu commences avec le budget d'erreur
entamé lundi.*

### <a id="pc-2-1"></a>[PC.2.1](corrige.md#pc-2-1) — lab-db à 95 %

> **Contexte**
>
> **07:48** — alerte Prometheus `DiskSpaceLow` sur lab-db (85 % → 95 % en trois
> heures). Aucun utilisateur ne se plaint encore : la base tourne toujours.
>
> Priorité : **P2** (avant que ça devienne P1). Interdit : reboot, et surtout
> **ne jamais** supprimer de fichiers dans `pg_wal/` à la main.

```bash
sudo bash break_PC_2_1.sh
```

Objectif : identifier **les trois** sources qui remplissent le disque (une
journalisation trop bavarde, un slot de réplication orphelin qui retient le WAL,
de vieux journaux non tournés), récupérer l'espace proprement, et poser la
rotation qui manquait — sans redémarrer PostgreSQL.

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_2_1.sh
> ```

### <a id="pc-2-2"></a>[PC.2.2](corrige.md#pc-2-2) — L'export nocturne est figé

> **Contexte**
>
> **09:05** — mail de la compta : « L'export des archives vers le serveur de
> fichiers n'a pas fini cette nuit, il est toujours "en cours" ce matin. Et quand
> j'essaie de regarder le dossier, mon terminal se fige complètement. »
> Sur lab-ops, `df -h` ne rend jamais la main ; la charge monte, le CPU est au
> repos.
>
> Priorité : **P2**. Interdit : reboot de la VM (d'autres jobs tournent dessus).

```bash
sudo bash break_PC_2_2.sh
```

Objectif : comprendre pourquoi un montage NFS injoignable fige `df` et les
processus (état `D`), rétablir l'accès, et rendre le montage incapable de
bloquer le boot et les jobs à l'avenir.

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_2_2.sh
> ```

### <a id="pc-2-3"></a>[PC.2.3](corrige.md#pc-2-3) — « La sauvegarde marche mais l'archive est vide »

> **Contexte**
>
> **14:20** — appel du dirigeant, tendu : « La compta m'a demandé de restaurer une
> facture de la semaine dernière. On est allés chercher la sauvegarde de la nuit :
> elle est **vide**. Mais le rapport dit "Sauvegarde OK" tous les matins depuis des
> semaines ! Comment c'est possible ?! »
> `systemctl list-timers` confirme que `factura-backup.timer` tourne chaque nuit.
>
> Priorité : **P2** (aucune interruption, mais risque majeur). Interdit : aucun,
> mais tu ne dois **pas** te contenter de relancer la sauvegarde.

```bash
sudo bash break_PC_2_3.sh
```

Objectif : trouver pourquoi une sauvegarde « réussit » avec une archive vide
(source déplacée, code de retour menteur), corriger le script pour qu'il
**échoue** quand il n'archive rien, purger les fausses archives, et vérifier une
restauration.

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_2_3.sh
> ```

### <a id="pc-2-4"></a>[PC.2.4](corrige.md#pc-2-4) — Demande : purge automatique des exports

> **Contexte**
>
> **16:40** — ticket de la compta : « Le dossier des exports CSV grossit sans
> arrêt sur lab-ops. Peux-tu mettre en place un nettoyage automatique ? On veut
> garder **30 jours** d'exports, mais **surtout ne jamais toucher** aux fichiers
> légaux (ceux dont le nom finit par `-legal.csv` et tout ce qui est dans
> `archives-legales/`). »
>
> Priorité : **P3** (changement). Contrainte : purge planifiée (timer, dimanche),
> qui **journalise** ce qu'elle supprime et propose un mode simulation.

```bash
sudo bash break_PC_2_4.sh
```

Objectif : un timer systemd + un script de purge sûr (n'efface que les `.csv`
de plus de 30 jours, épargne les fichiers légaux, trace ses suppressions, a un
`--dry-run`).

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_2_4.sh
> ```

**Fin de journée :** `~/astreinte/rapports/mardi.md`.

---

## C.3 Mercredi

*Journée « accès, réseau et sécurité ». Elle se termine par ton premier
exercice de communication.*

### <a id="pc-3-1"></a>[PC.3.1](corrige.md#pc-3-1) — Alerte : connexion réussie après des échecs répétés

> **Contexte**
>
> **06:20** — le SIEM lève une alerte sur lab-web : « connexion SSH réussie sur le
> compte `deploy` après une série d'échecs, depuis une IP externe ». Personne dans
> l'équipe ne reconnaît cette connexion.
>
> Priorité : **P1** (sécurité). Interdit : détruire les preuves. Tu **collectes
> avant de nettoyer**. Le déploiement légitime (clé de la CI) ne doit pas être
> cassé par ta remédiation.

```bash
sudo bash break_PC_3_1.sh
```

Objectif : confirmer ou infirmer la compromission à partir de `auth.log` et des
artefacts (crontab de `deploy`, `authorized_keys`), **contenir** (couper l'accès
de l'attaquant, verrouiller le compte, désactiver l'auth par mot de passe),
**préserver les preuves**, et remédier sans casser la CI.

> [!CAUTION]
> **Attention**
>
> C'est un exercice d'analyse sur un jeu de données de lab (le script pose des
> lignes de journal factices et une fausse clé, l'IP est une adresse de
> documentation). On ne « pirate » rien : on apprend à **lire** une compromission
> et à réagir proprement.

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_3_1.sh
> ```

### <a id="pc-3-2"></a>[PC.3.2](corrige.md#pc-3-2) — Le déploiement échoue : Permission denied (publickey)

> **Contexte**
>
> **10:30** — Slack de Julie : « Mon déploiement plante à l'étape "redémarrer
> l'API". Le job affiche `deploy@lab-web: Permission denied (publickey)`. Je n'ai
> rien changé de mon côté ! » En creusant : les clés SSH de la CI ont été
> « tournées » hier soir pour la sécurité.
>
> Priorité : **P2**. Interdit : réactiver l'authentification par mot de passe
> comme contournement.

```bash
sudo bash break_PC_3_2.sh
```

Objectif : comprendre qu'une **rotation de clé** a été faite à moitié (ancienne
clé publique retirée de `deploy`, mais la CI utilise encore l'ancienne privée),
rétablir un déploiement par clé cohérent, sans jamais repasser au mot de passe.

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_3_2.sh
> ```

### <a id="pc-3-3"></a>[PC.3.3](corrige.md#pc-3-3) — « La base est injoignable » (mais elle répond)

> **Contexte**
>
> **13:55** — Slack #support : « L'appli dit "base de données injoignable" depuis
> midi. Mais l'admin de la base jure qu'elle tourne, et il arrive à s'y connecter
> en tapant l'IP directement. » `/sante` renvoie 503 avec
> `could not translate host name "lab-db" to address`.
>
> Priorité : **P1**. Interdit : coder une IP en dur dans `api.env` (corrige la
> **résolution**, pas le symptôme).

```bash
sudo bash break_PC_3_3.sh
```

Objectif : montrer que la panne est une **résolution de nom** cassée (entrée
retirée de `/etc/hosts`), la rétablir au bon endroit, et remettre `/sante` au
vert.

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_3_3.sh
> ```

### <a id="pc-3-4"></a>[PC.3.4](corrige.md#pc-3-4) — Exercice de communication : message de statut

> **Contexte**
>
> Rejoue mentalement l'incident PC.3.3 (site inaccessible depuis 12:00, détecté à
> 13:55). Le dirigeant demande « qu'on prévienne les utilisateurs ». Tu n'as pas
> encore la cause à 14:00.

Rédige les **trois messages** de la cadence 15 minutes, pour un public **non
technique** (clients + interne), dans
`~/astreinte/communication/PC-3-4-statuts.md` :

1. **T+0 (14:00)** — constat : ce qui est touché, ce qui marche encore, ce que
   l'utilisateur doit faire (ou ne pas faire), quand on redonne des nouvelles.
2. **T+15 (14:15)** — piste : on a identifié la zone, sans jargon ni promesse de
   délai que tu ne tiendras pas.
3. **T+30 (14:30)** — rétablissement : service rétabli, ce qu'il faut vérifier
   côté utilisateur, un mot sur la suite (postmortem à venir).

Contraintes : pas de jargon (« résolution DNS » → « annuaire interne »), pas
d'accusation, pas de délai chiffré non garanti, une action claire par message.

**Fin de journée :** `~/astreinte/rapports/mercredi.md`.

---

## C.4 Jeudi

*Journée « demandes de changement et incidents insidieux ».*

### <a id="pc-4-1"></a>[PC.4.1](corrige.md#pc-4-1) — Demande : ouvrir un port pour un partenaire

> **Contexte**
>
> **08:30** — ticket du dirigeant, avec justification métier : « On signe avec
> **Comptaflux**. Leur plateforme (IP `203.0.113.42`) doit pouvoir récupérer nos
> données sur le port `9443` de lab-web. Leur intégrateur veut que ce soit ouvert
> pour vendredi. Fais le nécessaire, mais je ne veux pas qu'on ouvre la porte à
> tout Internet. »
>
> Priorité : **P3** (changement). Contrainte : **moindre privilège** — le port
> n'est joignable que depuis l'IP du partenaire, en TCP ; les accès existants (22,
> 80, 443) restent intacts.

```bash
sudo bash break_PC_4_1.sh
```

Objectif : une règle de pare-feu restreinte à `203.0.113.42` sur `9443/tcp`,
rien de plus ouvert, service partenaire joignable.

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_4_1.sh
> ```

### <a id="pc-4-2"></a>[PC.4.2](corrige.md#pc-4-2) — TLS échoue, sans qu'on ait touché aux certificats

> **Contexte**
>
> **11:20** — Slack d'un dev : « Nos appels HTTPS vers l'API depuis lab-web échouent avec `certificate is not yet valid`. Et les horodatages dans les logs
> sont bizarres, genre en retard de plusieurs heures. On n'a pourtant **rien** changé aux
> certificats. » (Seul le renouvellement automatique posé lundi a tourné cette nuit.)
>
> Priorité : **P2**. Interdit : régénérer les certificats (ce n'est pas le
> problème), reboot.

```bash
sudo bash break_PC_4_2.sh
```

Objectif : relier l'erreur TLS et les horodatages en retard à une **horloge
dérivée** (synchro NTP coupée, horloge en retard de trois heures : le certificat renouvelé cette nuit n'est pas encore « valide » pour elle), la
resynchroniser, et réactiver la synchro au démarrage.

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_4_2.sh
> ```

### <a id="pc-4-3"></a>[PC.4.3](corrige.md#pc-4-3) — Redis rame et la VM db swappe

> **Contexte**
>
> **14:45** — alerte `NodeSwapUsage` sur lab-db, et Slack #support : « le site est
> lent quand on filtre les factures ». `vmstat` montre du swap **en mouvement**
> (si/so non nuls), Redis répond mollement, `info memory` affiche un
> `used_memory` énorme.
>
> Priorité : **P2**. Interdit : reboot de la VM, `redis-cli FLUSHALL` à l'aveugle
> (tu perdrais les sessions actives).

```bash
sudo bash break_PC_4_3.sh
```

Objectif : montrer que Redis grossit sans borne (pas de `maxmemory`, politique
`noeviction`), poser une limite mémoire et une politique d'éviction adaptées,
persister le réglage, et faire cesser le swap.

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_4_3.sh
> ```

### <a id="pc-4-4"></a>[PC.4.4](corrige.md#pc-4-4) — Le conteneur worker clignote

> **Contexte**
>
> **16:30** — Slack de Julie : « Le worker n'arrête pas de redémarrer. `docker ps`
> le montre tantôt *health: starting*, tantôt *unhealthy*, et il ne traite plus
> aucun lot. On n'a rien déployé pourtant. » (En fait, la sonde de santé a été
> resserrée hier.)
>
> Priorité : **P3**. Interdit : supprimer purement et simplement le healthcheck
> (garde une vraie sonde), reboot.

```bash
sudo bash break_PC_4_4.sh
```

Objectif : comprendre qu'un `--health-timeout` plus court que le temps de
réponse de la sonde (avec une seule tentative) condamne le conteneur, détendre
le healthcheck au bon endroit, et retrouver un conteneur `healthy` stable.

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_4_4.sh
> ```
>
> Si Docker n'est pas disponible sur ta VM, ce ticket est **facultatif** : le
> `break` te le dira et tu peux passer.

**Fin de journée :** `~/astreinte/rapports/jeudi.md`.

---

## C.5 Vendredi

*Dernière journée : dette technique, pièges classiques, puis le post-mortem de
la semaine.*

### <a id="pc-5-1"></a>[PC.5.1](corrige.md#pc-5-1) — Demande : accès lecture seule pour l'audit

> **Contexte**
>
> **09:00** — ticket, avec justification : « Le cabinet **Revizor** démarre son
> audit annuel. Ils ont besoin de lire la base `factura` pendant **2 semaines**,
> depuis lab-adm uniquement. Lecture seule stricte : ils ne doivent **rien**
> pouvoir modifier. »
>
> Priorité : **P3** (changement). Contrainte : moindre privilège — pas de
> superutilisateur, pas d'écriture, date d'expiration, accès réseau restreint.

```bash
sudo bash break_PC_5_1.sh
```

Objectif : un rôle PostgreSQL `LOGIN` en lecture seule sur `factura`, sans droit
d'administration, avec `VALID UNTIL`, une limite de connexions, et un `pg_hba`
qui ne s'ouvre pas à tout Internet.

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_5_1.sh
> ```

### <a id="pc-5-2"></a>[PC.5.2](corrige.md#pc-5-2) — Après les mises à jour de nuit, le site a disparu

> **Contexte**
>
> **08:10** — alerte `ProbeFailed` sur `https://factura.lab.local`, et mail :
> « Le site ne répond plus du tout en HTTPS ce matin. Sur le port normal, on
> tombe sur une page "Welcome to nginx". L'API a l'air de tourner pourtant. »
> La fenêtre de mises à jour automatiques a tourné cette nuit.
>
> Priorité : **P1**. Interdit : reboot avant d'avoir compris ; ne pas réinstaller
> nginx « pour repartir propre ».

```bash
sudo bash break_PC_5_2.sh
```

Objectif : découvrir qu'une mise à jour de paquet a **remplacé** le vhost
personnalisé (mis de côté en `.dpkg-old`) par une conf par défaut, restaurer la
configuration Factura (TLS + proxy), et proposer de quoi détecter/éviter la
récidive (conf versionnée).

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_5_2.sh
> ```

### <a id="pc-5-3"></a>[PC.5.3](corrige.md#pc-5-3) — « No space left » mais le disque est vide

> **Contexte**
>
> **11:40** — Slack de Julie : « Le cache de sessions sur lab-ops renvoie *No space
> left on device* à chaque écriture, mais `df -h` dit que le volume est **quasi
> vide** ! On y comprend rien. »
>
> Priorité : **P2**. Interdit : reboot, agrandir le volume (ce n'est pas un
> problème de taille).

```bash
sudo bash break_PC_5_3.sh
```

Objectif : montrer que ce sont les **inodes** qui sont épuisés (des milliers de
petits fichiers), pas l'espace ; arrêter le processus qui les crée, libérer, et
poser une surveillance des inodes (pas seulement de l'espace).

> [!TIP]
> **Critère de succès**
>
> ```bash
>    sudo bash check_PC_5_3.sh
> ```

### <a id="pc-5-4"></a>[PC.5.4](corrige.md#pc-5-4) — Exercice : post-mortem complet

> **Contexte**
>
> Choisis **l'incident P1 de la semaine qui t'a le plus appris** (PC.1.1, PC.1.4,
> PC.3.1, PC.3.3 ou PC.5.2). Tu vas en écrire le post-mortem **blameless** complet,
> destiné à la direction et à l'équipe.

Remplis le modèle `~/astreinte/modeles/postmortem.md` dans
`~/astreinte/rapports/postmortem-<incident>.md`. Exigences :

* résumé lisible par la direction ; impact chiffré (durée, utilisateurs) ;
* chronologie factuelle **sans aucun nom de personne** ;
* **cinq pourquoi** qui descendent jusqu'à une cause **systémique** (pas « on a
  renouvelé le certificat ») ;
* section « ce qui a bien marché » (obligatoire) ;
* **trois actions correctives** dont au moins une **de détection** et une **de
  prévention**, chacune avec responsable, échéance, et **comment on l'automatise**.

**Fin de journée :** `~/astreinte/rapports/vendredi.md`, puis passe à la revue.

---

## C.6 Revue de la semaine

Rédige `~/astreinte/rapports/revue-semaine.md`.

### 1. Tableau récapitulatif

Une ligne par ticket : identifiant, type (changement / incident), priorité,
durée d'indisponibilité imputable (min), cause racine en une ligne, action
d'amélioration retenue.

| Ticket | Type | P | Indispo (min) | Cause racine | Amélioration |
|---|---|---|---|---|---|
| PC.1.1 | incident | 1 | | | |
| … | | | | | |

### 2. Disponibilité contre le SLO

* **SLO** : 99,5 % sur 30 jours. Fenêtre de référence : 30 jours =
  **43 200 minutes**. Budget d'erreur mensuel : **216 minutes**.
* Additionne les minutes d'indisponibilité **réelles** (P1 surtout ; un
  changement bien mené ne compte pas) de ta semaine.
* Calcule la disponibilité de la semaine et le **budget d'erreur consommé**
  (semaine + les 43 min déjà consommées avant lundi).

### 3. Budget d'erreur : décision

Si le budget est **dépassé ou presque**, quelle est la règle d'équipe ? (Gel des
déploiements non essentiels, priorité à la fiabilité.) Justifie en trois lignes
ce que tu recommandes pour la semaine suivante.

### 4. Trois actions d'amélioration et leur automatisation

Choisis les **trois** améliorations à plus fort effet de levier de la semaine.
Pour chacune : le problème récurrent qu'elle supprime, **l'automatisation
concrète** (timer, alerte Prometheus, contrôle CI, hook Git…), le responsable,
l'échéance, et **comment on saura qu'elle marche**.

| # | Problème | Automatisation | Responsable | Échéance | Preuve d'efficacité |
|---|---|---|---|---|---|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |

---

## C.7 Grille d'évaluation

Chaque **ticket** est noté sur **5** :

| Critère | Points |
|---|---|
| Diagnostic (bonnes commandes, bonne cause racine, preuves lues) | 2 |
| Correctif (durable, au bon endroit, service rétabli — `check` au vert) | 2 |
| Prévention **ou** communication (selon le ticket) | 1 |

Modulateurs :

* **Bonus vitesse** : +0,5 si le ticket P1 est rétabli dans sa fenêtre avec un
  journal propre.
* **Malus interdiction** : −2 si une interdiction est violée. Le `check` le
  détecte quand c'est possible (par ex. `boot_id` changé ⇒ reboot ; uptime de
  service réinitialisé ⇒ redémarrage interdit ; `PasswordAuthentication yes`
  laissé ; IP en dur ; healthcheck supprimé).
* **Malus méthode** : −1 si plusieurs modifications simultanées empêchent de
  savoir laquelle a corrigé, ou si un incident est « réparé » sans cause comprise.

Les deux exercices de communication (PC.3.4, PC.5.4) et la revue (C.6) sont
notés sur **10** chacun (clarté, exactitude, absence de blâme, actions
**automatisées** et datées).

Barème global indicatif : 18 tickets × 5 = 90, + 3 × 10 = 30, soit **120
points**. Seuil de réussite : **84** (70 %). En dessous de 60, refais les
journées une par une.

> [!CAUTION]
> **Attention**
>
> Un `check` au vert ne suffit pas à la note maximale : la **trace écrite** (ton
> journal de bord et tes rapports) est évaluée autant que la remise en service.
> Un service remis en route sans explication n'obtient pas les points de
> diagnostic.

---

## C.8 Pour l'entretien

Ces questions reprennent les scénarios de la semaine. Réponds à voix haute,
comme en entretien, en 2 à 3 minutes chacune.

1. « Un certificat TLS expire à 3 h du matin. Tu fais quoi dans l'heure, et
   qu'est-ce que tu mets en place pour que ça n'arrive plus jamais ? »
2. « `FATAL: sorry, too many clients already` sur PostgreSQL, interdiction de
   redémarrer la base en journée. Déroule ta démarche. »
3. « nginx renvoie 502 mais `systemctl status` dit que l'API est *active*.
   Cite au moins trois causes possibles et comment tu tranches. »
4. « On te dit "la base est injoignable" et l'admin répond "elle marche, je m'y
   connecte par IP". Où regardes-tu en premier ? »
5. « Une sauvegarde affiche *OK* tous les jours mais l'archive est vide.
   Qu'est-ce qui a pu se passer, et comment tu conçois une sauvegarde qui **ne
   ment pas** ? »
6. « Explique la différence entre "le disque est plein" version espace et
   version inodes. Quelle commande tranche ? »
7. « Un partenaire demande l'ouverture d'un port. Quelles questions tu poses
   **avant** d'ouvrir quoi que ce soit, et comment tu appliques le moindre
   privilège ? »
8. « TLS échoue par intermittence, personne n'a touché aux certificats. Donne
   trois hypothèses ; laquelle tu testes en premier et comment ? »
9. « On te demande de prévenir les utilisateurs pendant une panne dont tu ne
   connais pas encore la cause. Qu'est-ce que tu écris, qu'est-ce que tu
   n'écris **pas** ? »
10. « C'est quoi un budget d'erreur, et qu'est-ce que tu proposes quand il est
    épuisé au milieu du mois ? »

---

## Auto-évaluation

| Compétence | Acquis | À revoir |
|---|---|---|
| Extraire symptôme, périmètre et contraintes d'un ticket non technique | ☐ | ☐ |
| Traiter une demande de changement au moindre privilège | ☐ | ☐ |
| Renouveler/surveiller un certificat TLS | ☐ | ☐ |
| Diagnostiquer une saturation de connexions PostgreSQL | ☐ | ☐ |
| Récupérer de l'espace disque (WAL, logs, inodes) sans reboot | ☐ | ☐ |
| Débloquer un montage NFS et le sécuriser (nofail, timeout) | ☐ | ☐ |
| Concevoir une sauvegarde qui échoue quand elle n'archive rien | ☐ | ☐ |
| Lire une compromission dans auth.log et contenir proprement | ☐ | ☐ |
| Réparer un déploiement cassé par une rotation de clé SSH | ☐ | ☐ |
| Relier une panne à la résolution de noms ou à l'horloge | ☐ | ☐ |
| Borner Redis (maxmemory, éviction) et diagnostiquer le swap | ☐ | ☐ |
| Régler un healthcheck de conteneur | ☐ | ☐ |
| Rédiger un message de statut et un post-mortem blameless | ☐ | ☐ |
| Raisonner en disponibilité, SLO et budget d'erreur | ☐ | ☐ |

<!-- nav:début -->
---

[← Module 32](../../modules/32-fs-avances/README.md) · [Corrigé](corrige.md) · [Parcours](../../docs/parcours.md) · [Accueil](../../README.md)
<!-- nav:fin -->
