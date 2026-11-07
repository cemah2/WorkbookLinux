# Aides rédigées — module 01

Aides progressives des fiches interactives qui remplacent, pour l'item
concerné, celles que `tools/gen_fiches.py` tire du corrigé. Une section par
identifiant, les aides séparées par `---`, de la plus vague à la plus précise.
Ne jamais y écrire la réponse elle-même : c'est le rôle du corrigé.

## QO1.4

Les redirections sont appliquées **de gauche à droite**, chacune sur l'état
*actuel* de la table des descripteurs du processus.

---

`2>&1` ne veut pas dire « fd 2 suit fd 1 pour toujours » : c'est une **copie**
de la cible de fd 1 *à cet instant* (l'appel système `dup2(1, 2)`).

---

Dessine un tableau à deux colonnes (fd 1, fd 2), une ligne par redirection,
en partant de `fd1 -> tty`, `fd2 -> tty`. Fais-le pour les deux commandes et
compare la dernière ligne. Pour vérifier :

```bash
ls /existe /absent > f 2>&1; cat f
ls /existe /absent 2>&1 > f; cat f
```
