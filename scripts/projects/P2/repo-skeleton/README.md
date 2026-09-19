# factura — mono-repo infra + application (Projet B, Factura v2)

| Répertoire | Contenu | Jalon |
|---|---|---|
| `app/` | API Flask, worker, Dockerfiles, compose de dev | PB.4 |
| `infra/` | OpenTofu (Proxmox, cloud-init), monitoring | PB.2, PB.8 |
| `ansible/` | inventaire généré, rôles baseline et déploiement | PB.3, PB.5 |
| `.gitea/workflows/` | pipelines CI et CD | PB.6, PB.7 |
| `k8s/` | manifestes k3s de l'API | PB.10 |
| `docs/` | runbooks, rapport de reconstruction, comparaison | PB.9, PB.10 |

Conventions de commit : `type(scope): sujet` (Conventional Commits).
Types acceptés : feat, fix, chore, docs, ci, infra, refactor, test.
