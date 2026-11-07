# Journal des modifications

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) ;
versions en [SemVer](https://semver.org/lang/fr/) : majeure = structure du
parcours (modules ajoutés ou renumérotés), mineure = nouveaux items,
correctif = erreurs corrigées.

## [Non publié]

### Ajouté
- **Partie V — Expertise système**, six modules entre le projet B et le
  projet C (62 h) : 28 identité centralisée (LDAP, Kerberos, SSSD,
  FreeIPA), 29 haute disponibilité (HAProxy, keepalived, Pacemaker,
  Corosync), 30 sauvegarde et reprise (restic, borg, PITR PostgreSQL,
  Proxmox), 31 observer le noyau (perf, flame graphs, ftrace, eBPF),
  32 systèmes de fichiers avancés (intégrité, Btrfs, ZFS, `fio`),
  33 construire et distribuer (paquets `.deb` et `.rpm`, dépôts signés,
  DKMS). Chacun : 16 QCM, 8 questions ouvertes, 12 exercices, 4 labs,
  3 Break & Fix, un défi, et ses scripts (6 `setup`, 24 `check`,
  18 `break`).
- Mémo (sections 28 à 33), grille de progression, correspondance avec les
  examens EX362, EX436, EX442 et LPIC-3 306, planning en 22 étapes,
  besoins du laboratoire pour la Partie V (nœuds `lab-ha1`/`lab-ha2`).
- CI : validation des diagrammes Mermaid (`tools/check_mermaid.mjs`).
- Dépôt GitHub : un dossier par module (`modules/NN-sujet/README.md` pour
  l'énoncé, `corrige.md` pour le corrigé), `projets/`, `docs/`.
- Identifiants cliquables : chaque item de l'énoncé mène à son corrigé, et
  inversement (environ 1 480 liens).
- Navigation générée (`tools/gen_nav.py`) : fil d'Ariane, précédent /
  suivant, scripts du module en tête de chaque énoncé.
- Les 48 schémas rendus en SVG (`assets/figures/`, sources dans
  `assets/figures/src/`) ; les nouveaux schémas sont en Mermaid.
- `docs/parcours.md` (planning, niveaux, parcours ciblés),
  `docs/a-verifier.md` (points à confirmer sur les VM).
- CI GitHub Actions : cohérence du dépôt, navigation à jour, `bash -n`,
  `shellcheck`, `py_compile`.
- Modèles d'issues (erreur, suggestion) et de pull request.
- `bootstrap-lab.sh` clone le dépôt dans `~/workbook` quand aucune archive
  n'est fournie.

### Modifié
- Le workbook devient un dépôt **100 % Markdown GitHub** : les encadrés
  pandoc (`::: pourquoi`, `::: piege`…) deviennent des alertes GitHub avec
  libellé, les schémas des images SVG ou des diagrammes Mermaid.

### Supprimé
- La version PDF et toute sa chaîne de production (pandoc, LaTeX, gabarits,
  polices, workflows de publication), ainsi que les zones de réponse
  invisibles qui ne servaient qu'au PDF : les réponses s'écrivent dans
  `reponses/`.
- Licence : CC BY-NC-SA 4.0 pour le contenu, MIT pour les scripts et outils
  (l'ancienne licence « usage personnel » interdisait la publication des
  corrigés).
- Chapitre 0 : récupération du workbook par `git clone`, versionnement à
  partir du dépôt GitHub.

### Corrigé
- Réintégration des 556 corrections de la seconde relecture, absentes des
  sources Markdown (voir [docs/rapport-relecture.md](docs/rapport-relecture.md)).
- Scripts : version corrigée de 140 scripts `setup`/`check`/`break`.
- Défauts de rendu présents dans la source (code inline lu comme tableau,
  échappements dans les code spans, tableau dupliqué au chapitre 0).

## [1.0.0] — 2026-09-20

Version d'origine : 27 modules, 3 projets, trois PDF (énoncés, corrigés,
mémo), dépôt hébergé sur la forge Gitea du laboratoire.
