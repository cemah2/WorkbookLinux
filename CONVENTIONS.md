# CONVENTIONS — Workbook Linux / DevOps

Document de référence **obligatoire** pour tous les rédacteurs de modules.
Langue : **français** (termes techniques en anglais quand c'est l'usage : *pipeline*, *runner*, *rollback*).
Public : administrateur/dev **niveau intermédiaire** visant un poste DevOps. Pas de blabla débutant,
pas de « qu'est-ce qu'un ordinateur ». On suppose acquis : se connecter en SSH, `cd`, `ls`, éditer un fichier.

---

## 1. Infrastructure de lab (identique dans tous les modules)

Hyperviseur **Proxmox VE 8** de l'apprenant. Réseau de lab dédié sur le bridge `vmbr1`.

| VM | VMID | OS | vCPU/RAM/Disque | IP fixe | Rôle |
|---|---|---|---|---|---|
| `lab-adm` | 9001 | Ubuntu Server 24.04 LTS | 2 / 2 Go / 20 Go | 10.10.10.10 | Poste d'admin, bastion, nœud de contrôle Ansible |
| `lab-web` | 9002 | Ubuntu Server 24.04 LTS | 2 / 2 Go / 20 Go | 10.10.10.11 | Frontal web / reverse proxy / app |
| `lab-db` | 9003 | Ubuntu Server 24.04 LTS | 2 / 2 Go / 30 Go | 10.10.10.12 | Base de données, disques supplémentaires pour LVM |
| `lab-rhel` | 9004 | Rocky Linux 9 | 2 / 2 Go / 20 Go | 10.10.10.13 | Variantes RHEL (dnf, firewalld, SELinux) |
| `lab-ops` | 9005 | Ubuntu Server 24.04 LTS | 2 / 4 Go / 40 Go | 10.10.10.14 | Docker, CI runner, monitoring, registre |
| `lab-git` | 9006 | Ubuntu Server 24.04 LTS | 1 / 1 Go / 15 Go | 10.10.10.15 | Forge Gitea (binaire + SQLite) : dépôt du workbook, portfolio ; réutilisable par les modules 21 et 25 |
| `lab-virt` | 9007 | Ubuntu Server 24.04 LTS | 4 (cpu=host, virtualisation imbriquée) / 6 Go / 40 Go | 10.10.10.16 | Virtualisation KVM/QEMU/libvirt (module 20) |

* Réseau : `10.10.10.0/24`, passerelle `10.10.10.1`, DNS `10.10.10.1` (ou 9.9.9.9 en sortie).
* Domaine de lab : `lab.local`. Noms courts résolus par `/etc/hosts` (module 11 fait mieux).
* Utilisateur standard sur toutes les VM : **`mathieu`**, membre de `sudo` (Ubuntu) / `wheel` (Rocky), clé SSH publique déployée.
* Disques additionnels sur `lab-db` : `/dev/sdb` (5 Go) et `/dev/sdc` (5 Go), non formatés, pour les labs LVM.
* Snapshot de référence sur chaque VM : **`snap-clean`**. Règle d'or : `qm snapshot <vmid> avant-labXX` avant un lab destructeur,
  `qm rollback <vmid> snap-clean` pour repartir propre.

**Distribution** : Ubuntu 24.04 est la distribution de référence de tout le workbook.
Chaque fois qu'une commande diffère sous RHEL/Rocky, ajouter un bloc `::: rhel` (voir §4).
Justification à ne PAS répéter dans les modules (elle est en intro) : Ubuntu domine le marché cloud/CI,
Rocky couvre l'entreprise et les certifications RHCSA.

Pour les apprenants sans Proxmox disponible, l'annexe propose Multipass/Vagrant : ne pas en parler dans les modules.

---

## 2. Arborescence des livrables

Chaque module produit **deux fichiers Markdown** :

```
src/labs/MXX-slug.md          <- énoncés (quiz, exercices, labs, break&fix, défi)
src/solutions/MXX-slug.md     <- corrigés + explications
```

et, si le module l'exige, des scripts :

```
scripts/setup/setup_MXX.sh          <- prépare l'environnement du module (idempotent)
scripts/check/check_MXX_YY.sh       <- vérifie l'exercice/lab YY du module XX
scripts/break/break_MXX_YY.sh       <- casse volontairement pour un Break & Fix
```

`XX` = numéro de module sur 2 chiffres (`07`), `YY` = numéro d'item sur 2 chiffres (`03`).

---

## 3. Structure imposée d'un fichier `src/labs/MXX-slug.md`

Un seul `#` (titre du module). Les sections suivantes, dans cet ordre, en `##` :

```markdown
# Module 07 — Scripting Bash

## 7.0 Objectifs et compétences
## 7.1 Mise en place
## 7.2 Rappel express
## 7.3 Quiz — QCM
## 7.4 Quiz — questions ouvertes
## 7.5 Exercices guidés ★
## 7.6 Labs ★★
## 7.7 Break & Fix ★★★
## 7.8 Défi du module ★★★
## 7.9 Auto-évaluation
```

Détail attendu :

* **7.0 Objectifs** : 6 à 10 puces « À la fin de ce module, je sais… », formulées comme des compétences vérifiables.
  Ajouter une ligne `Temps estimé : Xh` et `Prérequis : modules ...`.
* **7.1 Mise en place** : VM concernée(s), snapshot à prendre, paquets à installer, commande de lancement du script de setup.
* **7.2 Rappel express** : **maximum 2 pages**. Tableaux de commandes/options, schéma en texte si utile, pièges classiques.
  Ce n'est pas un cours : c'est une antisèche pour attaquer les exercices. Densité maximale, zéro remplissage.
* **7.3 QCM** : **12 à 18 questions**, 4 propositions (a/b/c/d), parfois plusieurs bonnes réponses (le préciser dans l'énoncé).
  Viser le niveau d'un entretien technique : cas concrets, sorties de commandes à interpréter, pas de récitation.
* **7.4 Questions ouvertes** : **6 à 10 questions** qui demandent d'expliquer un mécanisme, comparer deux approches,
  ou décrire une démarche de diagnostic. Inclure au moins 2 questions « on te demande en entretien… ».
* **7.5 Exercices guidés ★** : **10 à 16 exercices** courts, une commande ou un script de quelques lignes.
  Énoncé orienté résultat (« affiche les 5 plus gros fichiers de /var »), jamais « tape telle commande ».
* **7.6 Labs ★★** : **3 à 5 scénarios** en plusieurs étapes numérotées, ancrés dans un contexte réaliste
  (ticket d'exploitation, demande d'un dev, audit). Chaque lab se termine par un critère de succès observable
  et, quand c'est pertinent, la commande `bash check_MXX_YY.sh`.
* **7.7 Break & Fix ★★★** : **2 à 4 pannes**. Format : contexte, symptôme observé par l'utilisateur, ce qui est interdit
  (ex. « interdit de réinstaller le paquet »), objectif de remise en service, et la commande qui casse
  (`sudo bash break_MXX_YY.sh`). Toujours rappeler le snapshot de secours.
* **7.8 Défi** : **1 exercice long** (30–90 min) qui combine tout le module, avec cahier des charges et livrable
  (un script, un fichier de conf, un rapport).
* **7.9 Auto-évaluation** : tableau de 8 à 12 compétences avec cases `☐ Acquis ☐ À revoir`, plus 2 ou 3 « pour aller plus loin ».

### Identifiants
Numérotation **stricte**, elle sert de pont entre les deux PDF :

| Type | Format | Exemple |
|---|---|---|
| QCM | `Q<mod>.<n>` | `Q7.1` |
| Question ouverte | `QO<mod>.<n>` | `QO7.3` |
| Exercice guidé | `E<mod>.<n>` | `E7.12` |
| Lab | `L<mod>.<n>` | `L7.2` |
| Break & Fix | `BF<mod>.<n>` | `BF7.1` |
| Défi | `D<mod>` | `D7` |

Les identifiants sont mis en **gras** en début de ligne : `**Q7.1** — Que fait ...`

---

## 4. Structure imposée d'un fichier `src/solutions/MXX-slug.md`

Mêmes identifiants, même ordre. Titre : `# Module 07 — Corrigé`.
Sections `##` : `7.3 Quiz — QCM`, `7.4 Quiz — questions ouvertes`, `7.5 Exercices guidés`, `7.6 Labs`,
`7.7 Break & Fix`, `7.8 Défi du module`.

Pour **chaque** item :

1. La **réponse** (lettre du QCM, commande exacte, script complet, procédure).
2. Un bloc **`::: pourquoi`** : l'explication du mécanisme sous-jacent. C'est le cœur du PDF de corrigés —
   on doit apprendre quelque chose même quand on avait juste. 5 à 15 lignes.
3. Quand c'est utile, un bloc **`::: piege`** : l'erreur classique, pourquoi les autres réponses sont fausses,
   ce qui casse en production.

Pour les Break & Fix, le corrigé donne : la démarche de diagnostic pas à pas (quelles commandes, dans quel ordre,
et ce qu'on cherche dans la sortie), la cause racine, le correctif, et la prévention.

Le corrigé doit être **autoportant** : on doit pouvoir le lire seul, sans avoir l'énoncé sous les yeux,
donc rappeler l'énoncé en une ligne en italique avant la réponse.

---

## 5. Blocs spéciaux (fenced divs pandoc)

À utiliser tels quels, la syntaxe est convertie en encadrés colorés dans le PDF :

```markdown
::: objectif
Contenu
:::
```

| Classe | Usage | Rendu |
|---|---|---|
| `objectif` | encadré d'objectifs en début de module | bleu |
| `astuce` | raccourci, bonne pratique | vert |
| `attention` | danger, action destructrice | rouge |
| `rhel` | variante Rocky/RHEL d'une commande Ubuntu | violet |
| `contexte` | mise en situation d'un lab | gris |
| `pourquoi` | explication (PDF corrigés uniquement) | bleu clair |
| `piege` | erreur classique (PDF corrigés uniquement) | orange |
| `repondre` | zone de réponse à remplir (PDF énoncés uniquement) | cadre pointillé |
| `check` | critère de succès / commande de vérification | vert bordé |

Exemple complet :

```markdown
::: rhel
Sous Rocky 9 : `sudo dnf install -y nginx` et `sudo firewall-cmd --add-service=http --permanent`.
:::
```

`::: repondre` s'emploie après les questions ouvertes et les Break & Fix pour laisser de la place à l'écrit.
Le contenu du bloc est le nombre de lignes souhaité, écrit ainsi : `lignes: 6`.

---

## 6. Règles d'écriture

* **Tutoiement**, ton direct et professionnel. Pas d'emoji. Pas de « Bien sûr ! », pas de conclusion pompeuse.
* Les commandes vont dans des blocs ```` ```bash ```` ; les fichiers de conf dans des blocs avec le bon langage
  (```` ```ini ````, ```` ```yaml ````, ```` ```nginx ````, ```` ```systemd ```` → utiliser `ini`).
* Toujours donner des **commandes réellement exécutables** sur l'infra du §1, avec les vrais noms d'hôtes et IP.
* Jamais de sortie de commande inventée de façon approximative : si tu montres une sortie, qu'elle soit plausible
  et cohérente avec Ubuntu 24.04 / Rocky 9.
* Les chemins, paquets et unités systemd doivent être exacts (`nginx.service`, `/etc/nginx/sites-available/`,
  `postgresql@16-main.service`, etc.).
* Pas de `sudo` sur les commandes qui n'en ont pas besoin.
* Les scripts fournis commencent par `#!/usr/bin/env bash` et `set -euo pipefail` (sauf raison pédagogique explicite).
* Longueur des lignes de code : **80 colonnes max** (sinon ça déborde dans le PDF). Couper avec `\`.
* Pas de tableau de plus de 4 colonnes (débordement PDF).
* Ne pas écrire « comme vu au module X » sans donner l'information minimale : chaque module doit rester utilisable seul.

## 7. Scripts de vérification

Contrat d'un `check_MXX_YY.sh` :

```bash
#!/usr/bin/env bash
# check_M07_02.sh — vérifie le lab L7.2
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification L7.2 =="
# ... tests ...
echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
```

Les tests doivent vérifier **le résultat**, pas la méthode (peu importe comment l'apprenant y est arrivé).
Chaque `ko()` donne un indice, pas la solution : `ko "le service n'écoute pas sur 8080 (vérifie ss -tulpn)"`.

Contrat d'un `break_MXX_YY.sh` : idempotent, sauvegarde ce qu'il casse dans `/root/.breakfix-backup/`,
affiche en fin d'exécution le symptôme attendu et rien d'autre (surtout pas la cause).

## 8. Volume attendu

Chaque module fait **8 à 14 pages A4** en énoncés et **10 à 18 pages** en corrigés. On ne bride pas : mieux vaut
trop d'exercices que trop peu. Mais chaque exercice doit apporter quelque chose de nouveau — pas de variations
cosmétiques du même exercice.
