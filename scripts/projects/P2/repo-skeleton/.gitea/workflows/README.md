`ci.yaml` (PB.6 : lint → tests → build → scan → push, puis déploiement
staging en PB.7), `cd-prod.yaml` (PB.7 : promotion manuelle),
`restore-test.yaml` (PB.9 : restauration hebdomadaire).
Le runner attendu porte le label `ops-host` (act_runner en mode hôte sur
lab-ops, module 25).
