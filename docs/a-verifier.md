# Points à vérifier sur les VM

La seconde relecture du workbook (voir [rapport-relecture.md](rapport-relecture.md))
a corrigé 556 erreurs, mais quelques points ne peuvent être tranchés qu'en
exécutant la commande sur les vraies VM du laboratoire. Ils sont listés ici
pour que personne ne perde vingt minutes à croire que l'erreur vient de lui.

Si tu fais l'un de ces items : note ce que tu observes réellement (commande,
sortie, version) et ouvre une
[issue « erreur dans le workbook »](https://github.com/cemah2/WorkbookLinux/issues/new/choose),
même si tout fonctionne comme écrit — c'est ce qui permet de cocher la ligne.

| Module | Item | Ce qui reste à vérifier |
|---|---|---|
| [03](../modules/03-permissions/README.md) | BF3.1 | le serveur peut renvoyer **404** plutôt que 403 à cause du `try_files … =404` posé par le setup |
| [06](../modules/06-vim-archives/README.md) | L6.4, E6.12, E6.16, BF6.3 | comportement exact de `rsync`, `zstd` et `cpio` (absents de l'environnement de relecture) |
| [12](../modules/12-reseau/README.md) / [13](../modules/13-reseau-avance/README.md) | — | drapeau `ad` (DNSSEC) attendu sur `www.ubuntu.com` ; écriture de `tcpdump -w` après abandon des privilèges |
| [13](../modules/13-reseau-avance/README.md) | BF13.4 | la panne de PMTU sur VXLAN peut ne pas se reproduire sur un noyau 6.8 |
| [14](../modules/14-ssh/README.md) | BF14.4 | le symptôme dépend de l'ordre des clés dans l'agent |
| [14](../modules/14-ssh/README.md) | L14.4 | `check_M14_04.sh` exige une directive `GatewayPorts` que l'énoncé demande de retirer |
| [18](../modules/18-securite/README.md) | — | action de bannissement par défaut de fail2ban sur Ubuntu 24.04 |
| [19](../modules/19-troubleshooting-perf/README.md) | BF19.5 | chiffres exacts de la panne |
| [20](../modules/20-virtualisation-kvm/README.md) | — | type de machine QEMU exact ; comportement de `virt-xml --cpu` |
| [22](../modules/22-docker/README.md) | E22.4 | nginx avec `--cap-drop ALL` échoue sans doute avant le `bind()` |
| [Projet A](../projets/P1-factura/README.md) | — | refus de `rrsync` sur un chemin absolu ; score `systemd-analyze security` annoncé |
| [Projet B](../projets/P2-factura-devops/README.md) | — | `ansible-lint`, `yamllint`, `gitleaks` et `tofu` non exécutés pendant la relecture |
| [Projet C](../projets/P3-astreinte/README.md) | PC.4.3, PC.4.2 | Redis en swap sur une VM de 2 Go ; resynchronisation NTP |
| [Annexes](annexes.md) | B | pondérations LFCS et objectifs EX200 vérifiés de mémoire ; version Gitea 1.27.x à confirmer |

## Après vérification

Une ligne vérifiée sort de ce tableau dans le même commit que la
correction éventuelle, avec un message du type :

```text
fix(M14): L14.4 — check_M14_04 n'exige plus GatewayPorts

Vérifié sur lab-adm (Ubuntu 24.04, OpenSSH 9.6p1) : …
```
