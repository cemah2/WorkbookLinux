# Contribuer (à soi-même)

Ce dépôt a un seul contributeur régulier : moi. Les règles servent à ce
que le dépôt reste lisible dans six mois, par moi ou par un recruteur.

## Où écrire

| Je veux… | Où |
|---|---|
| répondre à un lab, un défi, un Break & Fix | `reponses/MXX/<identifiant>.md` |
| garder un script réutilisable | `scripts/mes/` (+ `shellcheck` propre) |
| corriger une coquille du workbook | `src/` — commit `fix(src): …` séparé |
| noter un mot de passe de lab | `reponses/MXX/secrets.md` (ignoré par Git) |

Jamais de réponse dans `src/`, jamais de PDF commité, jamais de secret.

## Commits

* **Un commit = un lab terminé** (ou un défi, un Break & Fix, un jalon de
  projet). Pas de `wip`.
* Format Conventional Commits : `type(portée): sujet`, impératif,
  minuscules, sans point final, ≤ 72 caractères. Le corps dit *pourquoi*.
* Types : `feat` (un livrable), `fix` (une réponse corrigée), `docs`
  (carnet, README, post-mortem), `chore` (outillage), `refactor`.
* Portée : le module (`M07`) ou le projet (`P2`).

```text
feat(M10): L10.3 extension du VG avec sdc et pvmove

Le VG était plein : lvextend refusait. Corrigé avec pvcreate + vgextend ;
le corrigé ajoute pvmove pour libérer sdb, fait aussi.
```

## Branches

* Modules 01 à 16 : commits directement sur `main`.
* À partir du module 17 : une branche par module (`m17-git`), fusionnée
  par pull request dans Gitea à la fin du module.

## Avant de pousser

```bash
make check-ids            # si src/ a été touché
shellcheck scripts/mes/*.sh
git diff --stat src/      # doit être vide, sauf correction volontaire
git log --oneline -5      # les messages sont-ils au format ?
```
