# Rapport de relecture — seconde passe complète

Relecture croisée de l'intégralité du workbook par 18 relecteurs indépendants (aucun n'avait écrit le
contenu qu'il relisait), selon un protocole écrit (non publié) : exactitude technique de chaque commande et
sortie, justesse des clés de QCM, cohérence énoncé ↔ corrigé, validité des scripts, exactitude des
renvois, forme. Toutes les erreurs ont été corrigées directement dans les sources.

## Corrections appliquées

| Périmètre | Bloquant | Erreur | Mineur | Total |
|---|---|---|---|---|
| M01-M02 | 1 | 10 | 25 | 36 |
| M03-M04 | 3 | 10 | 9 | 22 |
| M05-M06 | 1 | 18 | 17 | 36 |
| M07-M08 | 0 | 8 | 13 | 21 |
| M09-M10 | 1 | 5 | 13 | 19 |
| M11 | 4 | 10 | 11 | 25 |
| M12-M13 | 5 | 13 | 15 | 33 |
| M14-M15 | 5 | 17 | 23 | 45 |
| M16-M17 | 2 | 18 | 18 | 38 |
| M18-M19 | 4 | 23 | 29 | 56 |
| M20-M21 | 4 | 14 | 14 | 32 |
| M22-M23 | 3 | 16 | 10 | 29 |
| M24-M25 | 5 | 14 | 14 | 33 |
| M26-M27 | 2 | 8 | 8 | 18 |
| P1 | 1 | 7 | 7 | 15 |
| P2 | 12 | 14 | 15 | 41 |
| P3 | 5 | 23 | 13 | 41 |
| CH0-ANNEXES-LAB | 2 | 8 | 6 | 16 |
| **Total** | **60** | **236** | **260** | **556** |
**556 corrections**, dont **60 bloquantes** (un lab ou une panne qui ne pouvait pas fonctionner, ou un
script de vérification qui refusait une bonne réponse).

## Contrôles automatiques après correction

| Contrôle | Résultat |
|---|---|
| Identifiants Q/QO/E/L/BF/D appariés énoncé ↔ corrigé | 30 fichiers, 0 manquant |
| Blocs `:::` équilibrés | 0 anomalie |
| Blocs de code fermés | 0 anomalie |
| `bash -n` sur les scripts | 386 / 386 |
| `python3 -m py_compile` | 24 / 24 |
| Blocs YAML/JSON parsés | 152 valides (le seul rejet est le YAML cassé volontairement en Q25.2) |
| Scripts cités dans le texte mais absents | 0 |
| Scripts `check`/`break` jamais cités | 0 |

## Nature des erreurs les plus fréquentes

1. **Scripts de vérification qui ne pouvaient pas passer** : motif de recherche faux, `here-doc` qui
   écrase `stdin`, glob évalué par le mauvais utilisateur, colonne erronée dans un `awk`, virgule
   décimale en locale française. C'est la famille la plus représentée parmi les cas bloquants.
2. **Pannes qui ne produisaient pas leur symptôme** : horloge avancée au lieu d'être retardée,
   `chmod 0770` qui ne retire pas le SGID, variable d'environnement neutralisée par un
   `EnvironmentFile`, slot de réplication qui ne retient aucun WAL.
3. **Incohérences de dimensionnement** : volumes LVM qui ne tenaient pas sur le disque prévu, ports
   publiés sur une IP et testés sur une autre.
4. **Comportements réels différents de ce qui était décrit** : `daemon-reload` depuis systemd 246,
   `Port` dans `sshd_config` avec `ssh.socket` sur Ubuntu 24.04, `dig` qui passe par le stub et lit
   `/etc/hosts`, `netplan try` qui refuse un bridge avec `parameters`.
5. **Renvois obsolètes** après la renumérotation des modules.

## À vérifier sur cible

Ces points ne sont pas vérifiables sans les VM réelles ; ils sont détaillés dans les rapports par
périmètre. Les plus notables :

- **M03** : BF3.1 pourrait renvoyer 404 plutôt que 403 à cause du `try_files … =404` du setup.
- **M06** : `rsync`, `zstd` et `cpio` absents du conteneur de relecture (L6.4, E6.12, E6.16, BF6.3).
- **M12/M13** : flag `ad` DNSSEC attendu sur `www.ubuntu.com` ; écriture de `tcpdump -w` après
  abandon des privilèges ; BF13.4 (PMTU VXLAN) peut ne pas se reproduire sur un noyau 6.8.
- **M14** : BF14.4 dépend de l'ordre des clés dans l'agent ; `check_M14_04` exige une directive
  `GatewayPorts` que l'énoncé demande de retirer.
- **M18/M19** : action de bannissement par défaut de fail2ban sur Ubuntu 24.04 ; chiffres de BF19.5.
- **M20** : type de machine QEMU exact, comportement de `virt-xml --cpu`.
- **M22** : nginx avec `--cap-drop ALL` (E22.4) échouerait sans doute avant le `bind()`.
- **P1** : refus de `rrsync` sur un chemin absolu, score `systemd-analyze security` annoncé.
- **P2** : `ansible-lint`, `yamllint`, `gitleaks` et `tofu` non exécutables depuis le conteneur.
- **P3** : PC.4.3 (Redis en swap sur une VM de 2 Go), resynchronisation NTP de PC.4.2.
- **Annexes** : pondérations LFCS et objectifs EX200 confirmés de mémoire seulement ; version Gitea
  1.27.3 non confirmée (la série 1.27 existe).

Les points « à vérifier sur cible » sont suivis dans [a-verifier.md](a-verifier.md).

## Reconstruction des sources (passage au format GitHub)

Lors de la mise au format GitHub, les sources Markdown disponibles dataient
d'**avant** cette seconde passe : seuls les PDF et l'archive des scripts
portaient les 556 corrections. Les sources ont donc été reconstruites :

1. **Alignement automatique** du texte des PDF sur le Markdown, token à
   token, en s'appuyant sur les polices du PDF pour retrouver le code, le
   gras et l'italique, et sur le Markdown pour lever les ligatures de la
   police de code (`...`, `::`, `&&`, `{{`…). Environ 3 000 zones modifiées
   (texte, lignes de code, cellules de tableau).
2. **Contrôle** : nouvel alignement des fichiers obtenus sur les PDF ; les
   écarts restants ont été relus un par un. Une quarantaine de passages ont
   été repris à la main (blocs de code restructurés, paragraphes ajoutés,
   lignes de tableau insérées).
3. **Cas où le Markdown a été préféré au PDF** : trois passages où le PDF
   lui-même était mal rendu (un tableau du corrigé E7.15, un paragraphe de
   BF13, la ligne qui déborde en bas de la page 671 du volume de corrigés),
   et les caractères que XeTeX transforme dans le code (`<<` et `>>` affichés
   `«` et `»`).
4. **Défauts de rendu de la source elle-même**, corrigés au passage : code
   inline coupé en début de ligne par un `|` (lu comme un tableau), `` \` ``
   dans un code span, tableau dupliqué au chapitre 0.

Le résultat est vérifié à chaque push par `tools/check_repo.py` (identifiants,
liens, scripts, structure) ; l'aller-retour Markdown GitHub → Markdown pandoc
est exact sur les 63 fichiers convertis.
