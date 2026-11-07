# Mes réponses

Ce dossier est le seul endroit du dépôt où **j'écris** (dans mon *fork*).
Le contenu du workbook (`modules/`, `projets/`, `docs/`) ne bouge pas ; ici
vivent mes démarches, mes scripts, mes rapports, mes post-mortem.

## Rangement

```text
reponses/
  README.md
  M01/ … M27/          un dossier par module (deux chiffres)
    E1.md              les exercices guidés du module, tous dans un fichier
    L1.2.md            un fichier par lab
    BF1.1.md           un fichier par Break & Fix
    D1.md              le défi ; ses livrables à côté, dans D1/
    D1/rotate.sh       scripts, fichiers de conf, rapports du défi
  P1/ P2/ P3/          projets fil rouge : un fichier par jalon + livrables
  carnet/              (optionnel) le carnet de bord, un fichier par module
```

Le nom du fichier est **l'identifiant du workbook**, tel qu'il apparaît
dans les énoncés : `L7.2`, `BF10.1`, `D15`, `E3`. C'est ce qui permet de
retrouver l'énoncé et le corrigé en une recherche (ou en un clic : l'ancre
d'un item est son identifiant en minuscules, points remplacés par des
tirets, par exemple `modules/07-bash-scripting/README.md#l7-2`).

## Le contenu d'une réponse

Le modèle est `M07/L7.2.md`. Quatre parties, dans cet ordre :

1. **En-tête** : identifiant et titre du lab, date, durée réelle, VM.
2. **Démarche** : ce que j'ai fait, dans l'ordre, avec les commandes
   exactes et ce que j'y ai vu. Pas la version idéale : la vraie, y
   compris les impasses (« 20 min sur X, cause : Y »).
3. **Résultat** : le critère de succès du lab et la sortie du `check`.
4. **Ce que j'ai appris / à revoir** : deux à cinq puces. Ce que le
   corrigé m'a appris de plus, ce que je dois réviser.

Les questions ouvertes (`QO`) et les QCM (`Q`) vont dans `E<mod>.md`,
en tête, sous forme de liste (`Q7.3 : b — parce que…`).

## Ce qui n'y va pas

* Le corrigé du workbook recopié. Un lien vers l'identifiant suffit.
* Un secret, même de lab : les fichiers `secrets*` sont ignorés par Git
  (`reponses/**/secrets*`), à utiliser pour les mots de passe de lab ;
  tout le reste est **public** un jour ou l'autre.
* Une IP publique, un nom de client, un nom d'employeur, une capture
  d'un système réel.
* Les fichiers générés ou volumineux (archives, images disque, sauvegardes de lab).

## Commits

Un commit par lab terminé, message en Conventional Commits, portée = le
module : `feat(M07): L7.2 rotation des journaux applicatifs`. Voir
`CONTRIBUTING.md`.
