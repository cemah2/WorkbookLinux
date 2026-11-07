# Journal des modifications

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) ;
versions en [SemVer](https://semver.org/lang/fr/) : majeure = structure du
parcours (modules ajoutés ou renumérotés), mineure = nouveaux items,
correctif = erreurs corrigées. Chaque version publiée produit les PDF dans
les [Releases](https://github.com/cemah2/WorkbookLinux/releases).

## [Non publié]

### Ajouté
- Dépôt GitHub : un dossier par module (`modules/NN-sujet/README.md` pour
  l'énoncé, `corrige.md` pour le corrigé), `projets/`, `docs/`.
- Identifiants cliquables : chaque item de l'énoncé mène à son corrigé, et
  inversement (environ 1 480 liens).
- Navigation générée (`tools/gen_nav.py`) : fil d'Ariane, précédent /
  suivant, scripts du module en tête de chaque énoncé.
- Les 48 schémas TikZ rendus en SVG (`assets/figures/`, `tools/render_figures.sh`).
- `docs/parcours.md` (planning, niveaux, parcours ciblés),
  `docs/a-verifier.md` (points à confirmer sur les VM).
- CI GitHub Actions : cohérence du dépôt, `bash -n`, `shellcheck`,
  `py_compile` ; workflow de publication des PDF sur étiquette `v*`.
- Modèles d'issues (erreur, suggestion) et de pull request.
- `bootstrap-lab.sh` clone le dépôt dans `~/workbook` quand aucune archive
  n'est fournie.

### Modifié
- Les encadrés pandoc (`::: pourquoi`, `::: piege`…) deviennent des alertes
  GitHub avec libellé ; la chaîne PDF les relit (`tools/pdf/gfm2pandoc.py`) :
  le Markdown du dépôt est la seule source.
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
