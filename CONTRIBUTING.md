# Contribuer

Deux façons de travailler avec ce dépôt, qui ne se mélangent pas :

* **Apprendre** : tu suis le workbook dans ton *fork* et tu ranges tes
  réponses dans `reponses/`. Tu ne touches pas au contenu.
* **Améliorer le workbook** : tu corriges une erreur, tu précises une
  explication, tu ajoutes un exercice. Ça passe par une issue ou une
  *pull request* sur le dépôt principal.

## Signaler une erreur

Ouvre une issue avec le modèle **« Erreur dans le workbook »** et donne :

* l'**identifiant** de l'item (`L7.2`, `BF11.3`, `Q18.4`…) ou le fichier ;
* la distribution et la version (`Ubuntu 24.04`, `Rocky 9.4`…), la VM ;
* ce que dit le workbook, ce que tu observes (la sortie exacte), et si
  possible la correction.

Un script `check_*.sh` qui refuse une réponse correcte est une erreur du
workbook : signale-la avec ta solution et la sortie du script.

Avant d'ouvrir une issue, regarde [docs/a-verifier.md](docs/a-verifier.md) :
certains points sont déjà connus et attendent une vérification sur les VM.

## Proposer une modification

1. Fork, puis une branche par sujet : `fix/m11-lvextend`, `feat/m28-ldap`.
2. Respecte [CONVENTIONS.md](CONVENTIONS.md) : structure des modules,
   identifiants, encadrés, longueur des lignes de code, ton.
3. Avant de pousser :

   ```bash
   make check        # identifiants, liens, schémas, scripts cités, structure
   make lint         # bash -n, shellcheck, py_compile
   make nav          # si tu as ajouté ou renommé un module
   ```

4. Un commit = une modification cohérente, message en
   [Conventional Commits](https://www.conventionalcommits.org/fr/) :

   ```text
   fix(M11): L11.3 — lvextend -r redimensionne aussi le système de fichiers

   Le corrigé lançait resize2fs après lvextend -r, ce qui ne fait rien de
   plus et trompe le lecteur sur ce que fait -r.
   ```

   Types : `fix` (erreur), `feat` (nouvel item, nouveau module), `docs`
   (documentation du dépôt), `refactor` (réorganisation sans changement de
   fond), `chore` (outillage, CI). Portée : le module (`M11`), le projet
   (`P2`), ou `lab`, `ci`, `pdf`.

5. Ouvre la pull request : la CI vérifie la cohérence du dépôt et les
   scripts. Si tu as modifié un schéma TikZ, régénère son SVG
   (`bash tools/render_figures.sh nom-du-schema`).

### Ce qui fait une bonne correction

* Une commande **réellement exécutée** sur Ubuntu 24.04 ou Rocky 9, avec
  sa vraie sortie.
* Un énoncé et son corrigé modifiés **ensemble** : la clé d'un QCM, le
  `check` d'un lab et l'explication du corrigé doivent rester cohérents.
* Pas de reformulation de goût : on corrige ce qui est faux, imprécis ou
  ambigu.

## Ranger ses réponses (dans son fork)

Le dossier [`reponses/`](reponses/) est à toi : un fichier par lab, nommé
par l'identifiant (`reponses/M07/L7.2.md`), sur le modèle de
`reponses/M07/L7.2.md`. Jamais de secret : les fichiers `secrets*` y sont
ignorés par Git. Les règles détaillées sont dans
[reponses/README.md](reponses/README.md).

Commits de réponses, sur le même modèle :
`feat(M07): L7.2 rotation des journaux applicatifs`. Un commit par lab
terminé, pas de `wip`.

## Licence des contributions

En proposant une modification, tu acceptes qu'elle soit diffusée sous la
licence du dépôt : CC BY-NC-SA 4.0 pour le contenu, MIT pour les scripts
et outils.
