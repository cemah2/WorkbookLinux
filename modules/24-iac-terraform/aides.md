# Aides rédigées — module 24

Aides progressives des fiches interactives qui remplacent, pour l'item
concerné, celles que `tools/gen_fiches.py` tire du corrigé. Une section par
identifiant, les aides séparées par `---`, de la plus vague à la plus précise.

## Q24.7

Il y a **trois** bonnes réponses. `sensitive = true` est un attribut
d'**affichage** : il masque une valeur à l'écran, il ne la chiffre pas.

---

Pour calculer le prochain plan, OpenTofu doit retrouver la valeur quelque
part : où garde-t-il les attributs et les sorties de la dernière exécution ?

---

Essaie-le (E24.15) :

```bash
tofu plan                       # avec puis sans sensitive = true sur l'output
tofu output; tofu output -raw t
grep -n token terraform.tfstate
```
