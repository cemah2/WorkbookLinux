# Module 13 — Journalisation et supervision système

## 13.0 Objectifs et compétences

::: objectif
À la fin de ce module, je sais :

* dire **qui écrit quoi** sur une machine moderne (application → journald →
  rsyslog → fichier), et nommer la facilité et la sévérité syslog d'un message
  donné ;
* interroger le journal systemd comme un outil d'enquête : filtrer par unité, par
  priorité, par fenêtre de temps, par PID, par exécutable, et en sortir du JSON
  exploitable ;
* rendre le journal persistant, mesurer ce qu'il consomme, le purger de façon
  contrôlée, et reconnaître un message perdu à cause du limiteur de débit ;
* configurer rsyslog pour trier les messages par facilité et sévérité, filtrer un
  service bruyant, et **centraliser** les journaux de plusieurs machines vers un
  collecteur en TCP ;
* écrire une règle `logrotate` complète pour une application maison, la tester en
  dry run, et expliquer pourquoi `copytruncate` perd des lignes ;
* diagnostiquer un fichier de log qui ne tourne pas, un `/var` qui sature, un
  journal qui a mangé plusieurs gigaoctets ;
* localiser et lire les journaux applicatifs classiques (nginx, PostgreSQL,
  `auth.log`, `dmesg`, cloud-init, `unattended-upgrades`) ;
* interpréter les métriques essentielles d'un serveur : charge moyenne par
  rapport au nombre de cœurs, répartition CPU `us/sy/wa/st`, mémoire `available`
  contre `free`, `%util` et `await` disque ;
* utiliser `top`, `vmstat`, `iostat -xz`, `pidstat`, `sar` et `/proc` pour passer
  d'un symptôme à une cause, en appliquant les quatre signaux dorés et la méthode
  USE ;
* installer `node_exporter`, lire son `/metrics`, et dire quelle métrique répond
  à quelle question d'exploitation.

Temps estimé : 6 h
Prérequis : modules 05 (filtres texte), 07 (scripting bash), 08 (processus et
systemd). Le module 14 traite la planification (cron, timers), le module 22 monte
la pile Prometheus/Grafana complète.
:::

---

## 13.1 Mise en place

VM concernées : **`lab-web` (10.10.10.11)** pour l'essentiel, et **`lab-ops`
(10.10.10.14)** pour la centralisation (L13.2) et `node_exporter` (L13.5).

```bash
# depuis le shell Proxmox, avant de commencer
qm snapshot 9002 avant-lab13
qm snapshot 9005 avant-lab13
```

Paquets, sur `lab-web` :

```bash
sudo apt update
sudo apt install -y rsyslog logrotate sysstat nginx lsof jq python3 curl
```

Sur `lab-ops` :

```bash
sudo apt install -y rsyslog sysstat jq curl prometheus-node-exporter
```

::: rhel
Sous Rocky 9 : `sudo dnf install -y rsyslog logrotate sysstat nginx jq`.
`rsyslog` est installé par défaut mais **pas démarré** sur une installation
minimale : `sudo systemctl enable --now rsyslog`. Le journal d'authentification
s'appelle `/var/log/secure` et non `/var/log/auth.log`, et le journal général
`/var/log/messages` et non `/var/log/syslog`. `node_exporter` n'est pas
empaqueté : récupère le binaire officiel (voir L13.5).
:::

`sysstat` n'enregistre rien tant qu'on ne l'active pas — c'est le piège classique
de `sar` (« commande introuvable » ou « aucune donnée ») :

```bash
sudo sed -i 's/^ENABLED=.*/ENABLED="true"/' /etc/default/sysstat
sudo systemctl enable --now sysstat
```

Préparation du terrain (idempotent, à relancer sans crainte) :

```bash
sudo bash ~/workbook/scripts/setup/setup_M13.sh
```

Il installe l'application de démonstration `factura` (`/opt/factura/bin`), ses
unités systemd, génère une semaine d'historique dans `/var/log/factura/`, des
échantillons de journaux nginx et d'authentification dans
`~/lab13/echantillons/`, et crée le bac à sable `~/lab13/`.

::: attention
Les Break & Fix de ce module remplissent volontairement `/var`. `BF13.2` crée
plusieurs gigaoctets de fichiers : vérifie d'abord que la VM a au moins 8 Go
libres (`df -h /var`). Le snapshot `avant-lab13` est ta sortie de secours, mais
l'utiliser vaut échec de l'exercice.
:::

---

## 13.2 Rappel express

### Qui écrit quoi

```text
  app systemd (stdout/stderr) ─┐
  app via syslog(3) → /dev/log ─┼→ journald ──→ /run/log/journal (volatile)
  noyau (/dev/kmsg) ───────────┘      │         /var/log/journal (persistant)
                                      │
                                      └─ ForwardToSyslog=yes ─→ rsyslog
                                                                  │
                                            /var/log/syslog, auth.log, ...
                                            @@collecteur:10514 (réseau)
                                                                  │
                                                              logrotate
```

Points à retenir : journald est **toujours** le premier récepteur sur une machine
systemd ; rsyslog ne lit plus `/dev/log` sur Ubuntu, il reçoit de journald via le
module `imjournal` ou le socket de forward. `logrotate` ne concerne **que** les
fichiers plats : le journal binaire se gère avec `journalctl --vacuum-*`.

### Facilités syslog

| Code | Nom | Usage typique |
|---|---|---|
| 0 | `kern` | messages du noyau (via `/dev/kmsg`) |
| 1 | `user` | messages utilisateur génériques, `logger` par défaut |
| 2 | `mail` | Postfix, Exim |
| 3 | `daemon` | démons système sans facilité dédiée |
| 4 | `auth` | authentification (`login`, `su`) |
| 5 | `syslog` | messages internes du démon syslog |
| 6 | `lpr` | impression |
| 7 | `news`, 8 `uucp` | historiques, inutilisés |
| 9 | `cron` | planificateur |
| 10 | `authpriv` | authentification **privée** (sshd, sudo, PAM) |
| 11 | `ftp`, 12 `ntp` | services dédiés |
| 13 | `security`, 14 `console`, 15 `solaris-cron` | usage marginal |
| 16–23 | `local0` … `local7` | **réservées aux applications maison** |

### Sévérités syslog

| Code | Nom | Sens opérationnel |
|---|---|---|
| 0 | `emerg` | système inutilisable, diffusé à tous les terminaux |
| 1 | `alert` | action immédiate requise |
| 2 | `crit` | condition critique (matériel, corruption) |
| 3 | `err` | erreur : le traitement a échoué |
| 4 | `warning` | anomalie sans échec |
| 5 | `notice` | événement normal mais notable (démarrage, reload) |
| 6 | `info` | déroulement nominal |
| 7 | `debug` | trace de développement |

Une règle rsyslog `daemon.err` signifie « facilité `daemon`, sévérité `err`
**et plus grave** ». Pour une seule sévérité, on écrit `daemon.=err`.

### journalctl

| Option | Effet |
|---|---|
| `-u nginx.service` | une unité (`--user-unit` pour les unités utilisateur) |
| `-f` / `-n 50` | suivi temps réel / 50 dernières lignes |
| `--since`, `--until` | `"2026-09-18 14:00"`, `yesterday`, `-1h`, `09:00` |
| `-p err` / `-p 3..4` | priorité maximale / intervalle |
| `-b` / `-b -1` / `--list-boots` | démarrage courant / précédent / liste |
| `-k` | messages du noyau uniquement (= `dmesg`) |
| `_PID=`, `_UID=`, `_COMM=` | filtres sur champs indexés |
| `_SYSTEMD_UNIT=`, `_TRANSPORT=` | unité réelle, origine (`stdout`, `syslog`, `kernel`) |
| `-o short-iso`, `-o cat`, `-o json` | format de sortie |
| `-g motif` (`--grep`) | filtre PCRE sur le message, `--case-sensitive=` |
| `--disk-usage` | taille occupée par le journal |
| `--vacuum-size=200M`, `--vacuum-time=14d` | purge les journaux **archivés** |
| `--no-pager`, `-q`, `--output-fields=` | sortie scriptable |
| `--verify`, `--flush`, `--rotate` | intégrité, bascule run → var, rotation |

`journalctl -o json | jq` donne accès à tous les champs, y compris ceux que le
format court n'affiche pas : `_SOURCE_REALTIME_TIMESTAMP`, `_CMDLINE`,
`CODE_FILE`, et les champs métier ajoutés par l'application.

### journald.conf — les clés qui comptent

```ini
[Journal]
Storage=persistent        # volatile | persistent | auto (défaut) | none
SystemMaxUse=1G           # plafond global, sinon 10 % de la partition
SystemKeepFree=2G         # espace toujours laissé libre
SystemMaxFileSize=128M    # taille d'un fichier avant rotation
MaxRetentionSec=30day     # âge maximal conservé
RateLimitIntervalSec=30s  # fenêtre du limiteur
RateLimitBurst=10000      # messages autorisés par fenêtre et par service
ForwardToSyslog=yes       # relais vers rsyslog
```

`Storage=auto` (le défaut) : persistant **si** `/var/log/journal` existe, volatile
sinon. D'où le `sudo mkdir -p /var/log/journal` suivi de
`sudo systemctl restart systemd-journald` pour survivre à un redémarrage.

Quand le limiteur frappe, journald écrit lui-même la trace :
`Suppressed 2381 messages from /system.slice/factura-bruyant.service`.

### rsyslog

```text
/etc/rsyslog.conf            règles globales, modules
/etc/rsyslog.d/*.conf        fragments, lus par ordre alphabétique
```

```rsyslog
auth,authpriv.*            /var/log/auth.log
*.*;auth,authpriv.none     -/var/log/syslog     # le - = écriture asynchrone
:programname, isequal, "factura-bruyant"   stop
*.*  @10.10.10.14:514      # UDP, sans garantie
*.*  @@10.10.10.14:10514   # TCP, avec accusé de réception
```

Un `@` = UDP, deux `@@` = TCP. `stop` arrête le traitement du message : placé
dans un fragment à numéro bas, il court-circuite tout ce qui suit.

### logrotate

| Directive | Effet |
|---|---|
| `daily` / `weekly` / `size 100M` | déclencheur de rotation |
| `rotate 14` | nombre d'anciennes copies conservées |
| `compress` / `delaycompress` | gzip / ne compresse qu'au tour suivant |
| `missingok` / `notifempty` | pas d'erreur si absent / ne tourne pas si vide |
| `create 0640 factura adm` | recrée le fichier vide avec ces droits |
| `su root adm` | identité prise pour tourner ce répertoire |
| `copytruncate` | copie puis tronque **en place** (voir le piège) |
| `postrotate … endscript` | commande après rotation (`sharedscripts` = une fois) |
| `dateext` / `dateformat` | suffixe `-20260918` au lieu de `.1` |

```bash
logrotate -d /etc/logrotate.d/factura   # dry run, ne touche à rien
sudo logrotate -f /etc/logrotate.conf   # force, ignore les déclencheurs
cat /var/lib/logrotate/status           # dernière rotation par fichier
```

::: piege
`logrotate` **ignore en silence** tout fichier de configuration accessible en
écriture au groupe ou aux autres, ou qui n'appartient pas à root. Le mode 0644,
propriétaire `root:root`, n'est pas un détail cosmétique. En debug (`-d`), il le
dit : `Ignoring factura because of bad file mode - must be 0644 or 0444`.
:::

### Métriques essentielles

| Signal | Où le lire | Ce qui doit t'alerter |
|---|---|---|
| charge | `/proc/loadavg`, `uptime` | > nombre de cœurs, et qui monte |
| CPU | `top`, `vmstat 1`, `mpstat -P ALL` | `wa` élevé = E/S, `st` = vol par l'hyperviseur |
| mémoire | `free -h`, `/proc/meminfo` | `available` qui fond, `si/so` non nuls |
| disque | `iostat -xz 1` | `%util` ~100 avec `await` qui explose |
| réseau | `sar -n DEV 1`, `ss -s` | saturation d'interface, `retrans` |

Sous Linux, la charge moyenne compte les processus en état `R` **et** en état `D`
(attente d'E/S ininterruptible). Une charge de 40 avec 2 % de CPU utilisé n'est
pas un problème de CPU : c'est du stockage bloqué.

`free -h` : la seule colonne à regarder est **`available`** — elle estime ce
qu'une nouvelle application peut obtenir sans swapper, cache récupérable inclus.
`free` bas + `available` haut = machine en bonne santé.

| Colonne `vmstat 1` | Ce qu'elle dit |
|---|---|
| `r` / `b` | processus prêts à tourner / bloqués en E/S |
| `si` / `so` | pages lues depuis / écrites vers le swap, **par seconde** |
| `bi` / `bo` | blocs lus / écrits sur les disques |
| `us sy id wa st` | répartition du temps CPU, `st` = temps volé par l'hôte |

`swap used` élevé mais `si/so` à zéro : ce sont des pages inactives parquées,
sans impact. C'est `si`/`so` qui font mal, pas `used`.

### Fichiers `/proc` à connaître par cœur

```bash
cat /proc/loadavg   # 0.58 0.24 0.12 3/412 5294
                    #  1m   5m  15m  runnables/total  dernier PID
cat /proc/stat      # cpu  user nice system idle iowait irq softirq steal ...
                    # valeurs en jiffies CUMULÉES : il faut deux relevés
grep -E 'MemTotal|MemAvailable|Dirty|SwapFree' /proc/meminfo
cat /proc/pressure/{cpu,memory,io}   # PSI : le temps perdu à attendre
```

### Les quatre signaux dorés et USE

* **Signaux dorés** (vue utilisateur, SRE Google) : latence, trafic, taux
  d'erreur, saturation. On alerte là-dessus.
* **USE** (vue ressource, Brendan Gregg) : pour chaque ressource — Utilisation,
  Saturation, Erreurs. On diagnostique là-dessus.

Règle : on **alerte sur le symptôme** (« la page de paiement répond en 8 s »), on
**diagnostique par la cause** (« `%util` du disque à 100 avec `await` à 400 ms »).
Une alerte « CPU > 80 % » réveille pour rien ; une alerte « latence p99 > 2 s
pendant 5 min » réveille pour quelque chose.

---

## 13.3 Quiz — QCM

**Q13.1** — Sur `lab-web` (Ubuntu 24.04), tu redémarres la VM et
`journalctl -b -1` répond `Failed to look up boot -1`. Pourquoi ?

a) l'option `-b` n'accepte pas de valeur négative sous Ubuntu
b) il faut être root pour lire les démarrages précédents
c) le journal est volatile : `/var/log/journal` n'existe pas, tout est perdu au
   redémarrage
d) `--list-boots` doit être exécuté avant pour construire l'index

**Q13.2** — Un développeur envoie ses messages avec
`logger -p local3.warning "cache froid"`. Quelle commande les isole ?

a) `journalctl -p warning -t local3`
b) `journalctl SYSLOG_FACILITY=19 -p warning`
c) `journalctl -u local3.service -p 4`
d) `journalctl --facility=local3`

**Q13.3** — Que fait exactement `journalctl --vacuum-size=200M` ?
**Deux réponses correctes.**

a) tronque le fichier de journal actif à 200 Mo
b) supprime les fichiers de journal **archivés** les plus anciens jusqu'à
   redescendre sous 200 Mo
c) modifie durablement la configuration de journald
d) ne touche jamais au fichier `system.journal` actif

**Q13.4** — Cette ligne apparaît dans `journalctl -u factura-bruyant` :

```text
sept. 18 14:03:11 lab-web systemd-journald[412]: Suppressed 2381 messages
    from /system.slice/factura-bruyant.service
```

Quelle affirmation est vraie ?

a) les 2381 messages sont définitivement perdus, journald ne les a jamais écrits
b) ils sont dans `/var/log/syslog`, journald les a seulement déportés
c) ils sont récupérables avec `journalctl --flush`
d) c'est rsyslog qui a limité le débit, pas journald

**Q13.5** — Dans `/etc/rsyslog.d/10-factura.conf` tu écris
`local5.err  /var/log/factura/erreurs.log`. Quels messages atterrissent dans ce
fichier ?

a) uniquement les messages `local5` de sévérité exactement `err`
b) les messages `local5` de sévérité `err`, `warning`, `notice`, `info`, `debug`
c) tous les messages `local5`, la sévérité n'est qu'indicative
d) les messages `local5` de sévérité `err`, `crit`, `alert` et `emerg`

**Q13.6** — Tu veux envoyer les journaux de `lab-web` vers `lab-ops` avec accusé
de réception et sans perte en cas de coupure brève. Quelle ligne ?

a) `*.*  @10.10.10.14:514`
b) `*.*  @@10.10.10.14:10514`
c) `*.*  >10.10.10.14:10514`
d) `*.*  |/dev/tcp/10.10.10.14/10514`

**Q13.7** — Un fichier `/var/log/factura/app.log` fait 4 Go et ne tourne jamais.
`/etc/logrotate.d/factura` existe et son contenu est correct. `logrotate -d
/etc/logrotate.conf` affiche `Ignoring factura because of bad file mode`.
Quelle est la cause ?

a) le fichier de log appartient à `factura` et non à `root`
b) `logrotate` refuse les fichiers de plus de 2 Go
c) le fichier de **configuration** est accessible en écriture au groupe ou aux
   autres, ou n'appartient pas à root
d) le répertoire `/var/log/factura` n'a pas le bit `setgid`

**Q13.8** — `copytruncate` est utilisé pour un service qui garde son fichier de
log ouvert. Quel est le défaut structurel de cette directive ?

a) elle empêche la compression
b) les lignes écrites entre la copie et la troncature sont perdues
c) elle double l'espace disque utilisé de façon permanente
d) elle ne fonctionne pas si le fichier dépasse 100 Mo

**Q13.9** — Un service écrit dans son log **sans** `O_APPEND` et garde le
descripteur ouvert. Après un `copytruncate`, que constate-t-on ?

a) le fichier repart de zéro proprement
b) le processus se termine avec une erreur d'écriture
c) rien de particulier, `copytruncate` gère ce cas
d) le fichier réapparaît avec une taille énorme, rempli d'octets nuls jusqu'à la
   position où en était le processus

**Q13.10** — `uptime` affiche `load average: 6.02, 5.88, 5.31` sur une VM à 4
vCPU, et `top` montre `0.7 us, 1.1 sy, 96.0 id, 2.0 wa`. Que conclus-tu ?

a) des processus sont bloqués en état `D` (E/S), la charge les compte alors
   qu'ils ne consomment pas de CPU
b) la machine sature en CPU, il faut ajouter des vCPU
c) la charge moyenne est un bug connu des noyaux 6.x sous KVM
d) `top` ment, il faut croire `uptime`

**Q13.11** — `free -h` affiche `total 7,7Gi`, `used 1,2Gi`, `free 0,3Gi`,
`buff/cache 6,2Gi`, `available 6,1Gi`. Faut-il s'inquiéter ?

a) oui, il ne reste que 0,3 Gi de mémoire libre
b) oui, `buff/cache` à 6,2 Gi signale une fuite mémoire du noyau
c) non, 6,1 Gi sont disponibles : le cache est récupérable à la demande
d) impossible à dire sans regarder le swap

**Q13.12** — `top` affiche une ligne CPU avec `st 22.4`. Que signifie cette
colonne et que fais-tu ?

a) `st` = *stopped*, des processus sont suspendus, tu les reprends avec `fg`
b) `st` = *steal*, l'hyperviseur donne du CPU à d'autres VM : le problème est
   côté hôte, pas dans ta VM
c) `st` = *system time*, c'est du temps noyau, tu regardes les appels système
d) `st` = *storage*, c'est de l'attente disque, équivalent de `wa`

**Q13.13** — `iostat -xz 1` donne pour `sdb` : `%util 99.8`, `await 340.00`,
`aqu-sz 28.4`, `r/s 12.0`, `w/s 8.0`. Quelle lecture est correcte ?

a) le disque traite 20 opérations par seconde à saturation, chacune attend 340 ms
   dans la file : le disque est le goulot
b) le disque est très rapide puisqu'il est utilisé à 99,8 %
c) `await` à 340 est normal pour un SSD
d) il faut d'abord regarder le CPU, `iostat` ne prouve rien

**Q13.14** — Tu veux tous les messages de priorité `err` ou pire, du service
`nginx`, entre 14 h et 14 h 30 aujourd'hui, en JSON. Quelle commande ?

a) `journalctl -u nginx -p 3 --since 14:00 --until 14:30 -o json`
b) `journalctl -u nginx -p err..emerg --since "14:00:00" -o json-pretty --today`
c) `journalctl nginx err 14:00 14:30 json`
d) `journalctl -u nginx --priority=error --from 14:00 --to 14:30 --json`

**Q13.15** — `vmstat 1` affiche en régime établi `si 0  so 0` mais `free -h`
montre 1,8 Gi de swap `used`. Que conclus-tu ?

a) la machine swappe activement, il faut ajouter de la RAM
b) `vmstat` ne mesure pas le swap, la colonne est décorative
c) le swap est corrompu
d) des pages inactives ont été parquées en swap par le passé, sans activité
   actuelle : ce n'est pas un problème

**Q13.16** — Sur laquelle de ces conditions vaut-il mieux déclencher une astreinte
de nuit ?

a) `CPU > 85 %` pendant 2 minutes
b) `latence p99 de /api/paiement > 2 s pendant 5 minutes`
c) `load average > 4`
d) `mémoire utilisée > 70 %`

**Q13.17** — `sar -u 1 3` répond `Cannot open /var/log/sysstat/sa18: No such file
or directory`. Pourquoi ?

a) `sar` en temps réel exige que la collecte historique soit activée
b) la commande est correcte ; c'est `sar -u` **sans** intervalle qui lit le
   fichier du jour, lequel n'existe pas tant que la collecte n'est pas activée
c) le paquet `sysstat` est corrompu
d) il faut lancer `sar` en root

**Q13.18** — `node_exporter` expose `node_filesystem_avail_bytes`. À quelle
question d'exploitation cette métrique répond-elle, dans la grille USE ?

a) l'utilisation du CPU
b) le taux d'erreur du disque
c) la saturation d'une ressource « système de fichiers »
d) la latence des requêtes HTTP

---

## 13.4 Quiz — questions ouvertes

**QO13.1** — Décris le trajet complet d'un message produit par un service systemd
qui fait `print("erreur base")` sur sa sortie standard, jusqu'à son arrivée
éventuelle dans `/var/log/syslog` puis dans `/var/log/syslog.2.gz`. Nomme chaque
composant traversé, le champ `_TRANSPORT` correspondant, et dis à quel endroit un
message peut être perdu.

::: repondre
lignes: 12
:::

**QO13.2** — *On te demande en entretien* : « Notre `/var` s'est rempli cette
nuit et l'application est tombée. Donne-moi ta démarche, dans l'ordre, pour
identifier le coupable et remettre le service en ligne en moins de dix minutes,
sans supprimer un fichier au hasard. » Réponds en listant les commandes.

::: repondre
lignes: 12
:::

**QO13.3** — Compare `logrotate` avec `create` et `logrotate` avec
`copytruncate` : pour chacun, explique ce qui arrive au descripteur de fichier
détenu par l'application, ce que devient l'inode, et dans quel cas précis on est
contraint d'utiliser `copytruncate`.

::: repondre
lignes: 10
:::

**QO13.4** — La charge moyenne d'un serveur applicatif à 8 vCPU est de 12.
Explique les trois scénarios de cause radicalement différents qui peuvent
produire ce chiffre, et pour chacun la commande qui tranche en moins d'une minute.

::: repondre
lignes: 10
:::

**QO13.5** — *On te demande en entretien* : « Quelle est la différence entre
`free` et `available` dans la sortie de `free -h` ? Et si je te dis que `free`
est à 200 Mo sur une machine de 16 Go, c'est grave ? » Réponds comme en entretien.

::: repondre
lignes: 8
:::

**QO13.6** — Un service maison écrit 4 000 lignes de log par seconde en rafale au
démarrage. Explique le mécanisme de `RateLimitIntervalSec` / `RateLimitBurst`,
ce qui est perdu exactement, les trois façons d'y remédier, et les conséquences
de chacune.

::: repondre
lignes: 10
:::

**QO13.7** — On te demande de centraliser les journaux de 40 serveurs.
Argumente le choix entre UDP (`@`) et TCP (`@@`) : que se passe-t-il dans chaque
cas si le collecteur redémarre pendant 30 secondes, et quelle configuration de
file d'attente côté émetteur protège les journaux ?

::: repondre
lignes: 8
:::

**QO13.8** — Explique la différence entre les quatre signaux dorés et la méthode
USE, puis applique les deux à un service HTTP qui répond lentement : cite trois
métriques « signaux dorés » et trois métriques « USE » que tu regarderais, dans
l'ordre.

::: repondre
lignes: 10
:::

**QO13.9** — Un développeur te demande quel format de log adopter pour sa nouvelle
application. Rédige ta réponse d'ops : niveaux à utiliser et ce qui va dans
chacun, format, horodatage, identifiant de corrélation, et ce qu'il ne faut
**jamais** écrire dans un log.

::: repondre
lignes: 10
:::

---

## 13.5 Exercices guidés ★

**E13.1** — Affiche les 30 dernières lignes du journal de `ssh.service`, en
horodatage ISO, sans pager, puis suis en temps réel les nouvelles entrées de la
même unité. Enfin, montre uniquement le texte des messages, sans horodatage ni
nom d'hôte.

**E13.2** — Sors toutes les entrées de priorité `warning` ou pire produites
depuis le début du démarrage courant, puis les mêmes pour le démarrage précédent.
Si la seconde commande échoue, corrige la cause durablement.

**E13.3** — Rends le journal persistant sur `lab-web`, vérifie où il est
réellement stocké après l'opération, et mesure l'espace qu'il occupe. Enchaîne
avec les cinq plus gros fichiers de `/var/log` (sous-répertoires compris, taille
lisible) et la taille totale par sous-répertoire de premier niveau : tu dois
pouvoir dire en trois commandes qui mange `/var/log` sur cette machine.

**E13.4** — Envoie trois messages de test : un en `local4.info`, un en
`local4.err` avec le tag `factura-test`, et un lu depuis un fichier. Retrouve les
trois dans le journal en filtrant sur la facilité, puis sur le tag.

**E13.5** — Trouve tous les messages du journal émis par l'exécutable `sudo`,
toutes unités confondues, sur les dernières 24 heures. Donne ensuite la même
information en n'affichant que le champ `MESSAGE` et l'utilisateur d'origine.

**E13.6** — Affiche en JSON indenté la dernière entrée de priorité `err` du
journal, et extrais avec `jq` le PID, l'unité systemd et la ligne de commande
complète du processus émetteur.

**E13.7** — Compte, pour le démarrage courant, le nombre d'entrées par unité
systemd, classées par volume décroissant. Les dix premières suffisent.

**E13.8** — Le journal occupe trop de place. Plafonne-le à 500 Mo de façon
durable, applique immédiatement la contrainte sans redémarrer la machine, et
prouve le résultat avant/après.

**E13.9** — Configure rsyslog pour écrire toutes les entrées de facilité `local6`
dans `/var/log/factura/metier.log`, et **uniquement** celles-là. Vérifie que les
mêmes messages ne polluent plus `/var/log/syslog`.

**E13.10** — Le service `factura-bruyant` inonde `/var/log/syslog`. Filtre-le
côté rsyslog pour qu'il n'écrive plus rien dans `syslog` ni dans les fichiers
distants, sans toucher au service lui-même et sans perdre ses messages du
journal systemd.

**E13.11** — Écris `/etc/logrotate.d/factura` pour `/var/log/factura/app.log` :
rotation quotidienne, 14 générations, compression différée d'un tour, pas de
rotation si le fichier est vide, fichier recréé en `0640 factura adm`. Teste-le
en dry run **sans rien modifier**, puis force une rotation et montre le résultat.

**E13.12** — Prouve avec deux terminaux que `copytruncate` perd des lignes :
lance un générateur qui écrit une ligne numérotée par seconde, force une rotation
avec `copytruncate`, puis montre le trou dans la numérotation.

**E13.13** — Relève en une seule commande la charge à 1, 5 et 15 minutes, le
nombre de cœurs de la VM, et le ratio charge/cœur avec deux décimales. Puis
prends deux relevés de `/proc/stat` à une seconde d'intervalle et calcule, en
bash, le pourcentage de temps CPU passé en `iowait` entre les deux relevés.
Compare ta valeur à celle de `vmstat 1 2`.

**E13.14** — Identifie le processus qui génère le plus d'E/S disque sur la
machine, puis celui qui provoque le plus de défauts de page, avec `pidstat`.
Deux commandes distinctes.

**E13.15** — Active la collecte historique `sysstat`, attends un cycle, puis
affiche l'utilisation CPU moyenne du jour et l'activité disque entre 09:00 et
11:00 depuis les données enregistrées.

**E13.16** — Installe `node_exporter` sur `lab-ops`, vérifie qu'il écoute, et
extrais de `/metrics` les trois métriques qui te donnent : la charge à 1 minute,
la mémoire disponible en octets, et l'espace libre du système de fichiers monté
sur `/`.

---

## 13.6 Labs ★★

### **L13.1** — Ticket INC-4102 : « des 502 entre 14 h et 14 h 20 »

::: contexte
Le support a reçu douze appels hier après-midi : la page de facturation renvoyait
`502 Bad Gateway`. Ce matin tout fonctionne. Aucun monitoring n'est branché sur
`lab-web`. On te demande une chronologie factuelle de l'incident et une cause
racine, uniquement à partir des journaux.
:::

Le setup a rejoué l'incident : les entrées de service sont dans le journal
systemd, la dégradation vue côté frontal est dans `/var/log/nginx/access.log` et
`/var/log/factura/app.log`. La fenêtre exacte du rejeu est écrite dans
`~/lab13/inc-4102/fenetre.txt` — commence par la lire, tout le lab s'y réfère.

1. Rends le journal persistant s'il ne l'est pas encore, et vérifie que les
   démarrages précédents sont interrogeables (`journalctl --list-boots`).
2. Extrais toutes les entrées de `factura-api.service` sur la fenêtre indiquée
   par `fenetre.txt`, en horodatage ISO, dans
   `~/lab13/inc-4102/journal-api.log`.
3. Isole dans cette fenêtre les entrées de priorité `err` ou pire, toutes unités
   confondues. Note l'ordre d'apparition : qui échoue en premier ?
4. Cherche dans le journal du noyau (`-k`) un événement contemporain. S'il y en a
   un, donne le processus concerné et la mémoire réclamée.
5. Compte les réponses `502` dans `/var/log/nginx/access.log` par tranche de
   minute, et construis l'histogramme texte (minute, nombre). Les 40 minutes qui
   précèdent la fenêtre du journal y sont couvertes : dis à quelle minute la
   dégradation commence, bien **avant** l'arrêt du service.
6. Sors en JSON les trois premières entrées `err` de `factura-api.service` et
   extrais avec `jq` : horodatage lisible, PID, message et `_CMDLINE`.
7. Vérifie s'il manque des messages : cherche une trace de suppression par le
   limiteur de débit dans la même fenêtre.
8. Rédige `~/lab13/inc-4102/rapport.md` : chronologie minute par minute, cause
   racine, preuve (commande + extrait), impact utilisateur, et **deux** actions
   correctives dont au moins une de supervision.

::: astuce
`journalctl --since "2026-09-18 13:50" --until "2026-09-18 14:30"` accepte aussi
`-1h`, `yesterday`, `"09:00"`. Pour une extraction reproductible, écris les dates
en entier : tu relis ton rapport six mois plus tard. Rappel utile : journald
horodate au moment où il reçoit le message, pas au moment où l'application dit
l'avoir produit — d'où l'écart possible avec l'horodatage interne aux fichiers.
:::

::: check
Critère de succès : le journal est persistant, `~/lab13/inc-4102/journal-api.log`
contient la fenêtre demandée, et le rapport cite la cause racine avec sa preuve.

```bash
bash check_M13_01.sh
```
:::

---

### **L13.2** — Centraliser les journaux de `lab-web` vers `lab-ops`

::: contexte
Après l'incident INC-4102, la direction technique demande que les journaux ne
vivent plus uniquement sur la machine qui les produit : « quand la VM tombe, on
perd la preuve ». Tu montes un collecteur sur `lab-ops` et tu y raccordes
`lab-web`. Contrainte : le service `factura-bruyant` ne doit **pas** traverser le
réseau, il génère 90 % du volume.
:::

Partie 1 — le collecteur, sur `lab-ops` (10.10.10.14) :

1. Active la réception TCP sur le port **10514** (module `imtcp`), pas sur 514 :
   on ne veut pas de port privilégié ni d'UDP.
2. Écris `/etc/rsyslog.d/05-collecteur.conf` avec un template qui range les
   messages reçus dans
   `/var/log/central/<nom-d-hote>/<programme>.log`.
3. Les messages **locaux** de `lab-ops` ne doivent pas atterrir dans
   `/var/log/central/` : sépare-les avec un `ruleset` dédié à l'entrée réseau.
4. Ouvre le port au pare-feu uniquement depuis `10.10.10.0/24`.
5. Crée `/var/log/central` avec des droits corrects et vérifie que rsyslog peut y
   écrire.

Partie 2 — l'émetteur, sur `lab-web` (10.10.10.11) :

6. Écris `/etc/rsyslog.d/90-forward.conf` qui envoie **tout** vers
   `10.10.10.14:10514` en TCP.
7. Ajoute une file d'attente sur disque (`LinkedList`, répertoire de spool,
   reprise après coupure) pour ne rien perdre si le collecteur redémarre.
8. Avant la règle de forward, filtre `factura-bruyant` : ses messages ne partent
   pas sur le réseau, mais restent dans le journal local.
9. Teste : `logger -p local4.notice "test centralisation depuis lab-web"` doit
   apparaître dans `/var/log/central/lab-web/` en moins de deux secondes.
10. Preuve de résilience : arrête rsyslog sur `lab-ops` 30 secondes, envoie
    5 messages depuis `lab-web`, redémarre le collecteur, et montre que les 5
    messages sont arrivés.

::: attention
Un collecteur syslog ouvert est une porte d'entrée : n'écoute jamais sur
`0.0.0.0` sans filtrage réseau. Ici, le pare-feu limite à `10.10.10.0/24`.
:::

::: check
Critère de succès : `/var/log/central/lab-web/` existe et se remplit,
`factura-bruyant` n'y apparaît pas, et les messages émis pendant l'arrêt du
collecteur ont été rattrapés.

```bash
bash check_M13_02.sh     # à lancer sur lab-ops
```
:::

---

### **L13.3** — Rotation propre des journaux de `factura`

::: contexte
`/var/log/factura/` contient quatre fichiers qui n'ont jamais tourné depuis la
mise en production. Le plus gros fait plusieurs centaines de mégaoctets. Le
développeur prévient : « l'application garde le fichier ouvert, elle ne sait pas
rouvrir toute seule, mais elle réagit à `SIGHUP` ». On te demande une rotation
propre, testée, et un rapport qui justifie tes choix.
:::

1. Inventorie ce qu'il y a dans `/var/log/factura/` : taille, propriétaire,
   droits, et quel processus détient chaque fichier ouvert (`lsof` ou
   `/proc/*/fd`).
2. Écris `/etc/logrotate.d/factura`, avec deux blocs distincts :
   * `app.log` et `erreurs.log` : quotidien, 14 générations, compression
     différée, `notifempty`, `missingok`, fichier recréé `0640 factura adm`,
     rotation déclenchée aussi si le fichier dépasse 100 Mo ;
   * `acces.log` : hebdomadaire, 8 générations, suffixe daté au lieu de `.1`.
3. Ajoute un `postrotate` qui fait relire le fichier à l'application (`SIGHUP` au
   service, pas au PID en dur), exécuté **une seule fois** pour les deux fichiers
   du premier bloc.
4. Donne au bloc l'identité nécessaire pour tourner des fichiers appartenant à
   `factura` dans un répertoire qui ne lui appartient pas.
5. Vérifie ta configuration **sans rien modifier**, corrige jusqu'à ce que la
   sortie de debug ne montre plus d'erreur ni de fichier ignoré.
6. Force une rotation. Montre que : l'inode d'`app.log` a changé, l'application
   écrit bien dans le nouveau fichier, le `.1` n'est pas encore compressé et le
   `.2.gz` l'est.
7. Explique par écrit dans `~/lab13/rotation.md` pourquoi tu n'as **pas** utilisé
   `copytruncate` ici, et dans quel cas tu y serais contraint.
8. Vérifie l'état enregistré de la rotation et donne la date de dernière rotation
   d'`app.log` telle que `logrotate` la connaît.

::: check
Critère de succès : `logrotate -d /etc/logrotate.conf` ne signale ni erreur ni
fichier ignoré pour `factura`, une rotation forcée produit `app.log.1` et
`app.log.2.gz`, l'application continue d'écrire dans le nouveau fichier, et
`rotation.md` existe.

```bash
bash check_M13_03.sh
```
:::

---

### **L13.4** — Collecte maison et rapport quotidien

::: contexte
Avant de déployer Prometheus (module 22), l'équipe veut une base de mesures
exploitable dès maintenant sur `lab-web`, et un rapport lisible qu'on puisse
coller dans le compte rendu d'exploitation du matin. Livrable : deux scripts et
un rapport.
:::

1. Écris `/opt/factura/bin/collecte-metriques.sh` (`#!/usr/bin/env bash`,
   `set -euo pipefail`) qui produit **une ligne CSV** par exécution dans
   `/var/log/factura/metriques.csv`, avec au minimum :
   horodatage ISO, charge 1 min, ratio charge/cœur, `%us`, `%sy`, `%wa`, `%st`,
   mémoire disponible en Mo, swap in/out par seconde, `%util` du disque système,
   `await`, nombre de processus en état `D`.
2. Contraintes : aucune dépendance en dehors de `sysstat` et des coreutils ;
   l'en-tête CSV n'est écrit qu'à la création du fichier ; le script est
   idempotent et ne dure pas plus de 3 secondes.
3. Les valeurs CPU doivent venir d'un **delta** entre deux relevés, pas du
   cumulé depuis le boot : justifie ta méthode en commentaire.
4. Écris `/opt/factura/bin/rapport-quotidien.sh` qui lit le CSV et produit sur
   stdout un rapport Markdown : période couverte, nombre de relevés, pour chaque
   métrique le min/moyenne/max, la liste horodatée des dépassements de seuil, et
   une section « À surveiller » qui ne contient que les anomalies réelles.
5. Seuils à appliquer : charge/cœur > 1,5 ; `%wa` > 20 ; mémoire disponible
   < 15 % du total ; `%util` disque > 90 ; `%st` > 5 ; plus de 3 processus en
   `D`. Ces seuils sont paramétrables en tête de script.
6. Génère de la matière : lance une charge CPU et une charge d'E/S pendant
   quelques minutes pendant que la collecte tourne (une exécution toutes les
   10 secondes suffit pour le lab — la planification propre est le sujet du
   module 14).
7. Produis `~/lab13/rapport-quotidien.md` et vérifie que les dépassements
   correspondent bien à la période de charge.
8. Le rapport doit répondre à cette question en une phrase : **le serveur
   a-t-il été limité par le CPU, par les E/S ou par la mémoire ?**

::: astuce
Pour la charge : `for i in 1 2 3 4; do timeout 180 sh -c 'while :; do :; done' &
done` pour le CPU, et `dd if=/dev/zero of=/var/tmp/io.tmp bs=1M count=4096
oflag=direct` pour les E/S. Pense à supprimer le fichier temporaire ensuite.
:::

::: check
Critère de succès : le CSV contient un en-tête et au moins 20 relevés cohérents,
`rapport-quotidien.sh` sort du Markdown valide sur stdout et rien sur stderr, et
le rapport identifie la bonne ressource limitante.

```bash
bash check_M13_04.sh
```
:::

---

### **L13.5** — `node_exporter` : brancher la supervision

::: contexte
Le module 22 montera Prometheus et Grafana. Avant ça, on veut valider sur
`lab-ops` qu'un exportateur de métriques tourne, qu'il est lisible, et surtout
que l'équipe sait **quelle métrique répond à quelle question**. C'est un lab de
lecture, pas de déploiement.
:::

1. Installe et démarre `node_exporter` sur `lab-ops`. Vérifie qu'il écoute et
   sous quel utilisateur il tourne.
2. Restreins son écoute à l'adresse de lab (`10.10.10.14`) et non à toutes les
   interfaces, via un drop-in systemd — sans modifier le fichier d'unité livré
   par le paquet.
3. Récupère `/metrics` et compte le nombre de séries exposées, puis le nombre de
   familles de métriques distinctes.
4. Retrouve dans la sortie, et note la valeur : charge 1 min, mémoire disponible,
   octets libres sur `/`, nombre de secondes CPU en `iowait`, compteur d'octets
   reçus sur l'interface principale, nombre de descripteurs ouverts.
5. Explique ce que signifie le suffixe `_total` sur une métrique et pourquoi on
   n'affiche jamais un compteur brut sur un tableau de bord.
6. Vérifie depuis `lab-web` que le `/metrics` est joignable, puis **ferme** l'accès
   à tout le monde sauf `10.10.10.0/24` et re-teste.
7. Remplis dans `~/lab13/use-golden.md` deux tableaux :
   * quatre signaux dorés : signal, métrique `node_exporter` ou applicative
     correspondante, seuil d'alerte que tu proposerais ;
   * méthode USE pour trois ressources (CPU, mémoire, disque) : la métrique
     d'utilisation, celle de saturation, celle d'erreurs.
8. Conclus en une phrase : quelles alertes de cette liste réveillent quelqu'un la
   nuit, et lesquelles attendent le matin.

::: check
Critère de succès : `node_exporter` répond sur `10.10.10.14:9100/metrics`, n'écoute
pas sur `0.0.0.0`, le drop-in existe sous `/etc/systemd/system/`, et
`use-golden.md` contient les deux tableaux remplis.

```bash
bash check_M13_05.sh     # à lancer sur lab-ops
```
:::

---

## 13.7 Break & Fix ★★★

::: attention
Avant chaque Break & Fix : `qm snapshot 9002 avant-bf13`. Le snapshot de secours
reste `avant-lab13` (`qm rollback 9002 avant-lab13`), mais l'utiliser vaut échec
de l'exercice : l'objectif est de réparer, pas de rembobiner.
`BF13.2` écrit plusieurs gigaoctets : vérifie `df -h /var` avant.
:::

### **BF13.1** — « `/var` est plein et l'application refuse d'écrire »

```bash
sudo bash break_M13_01.sh
```

**Symptôme utilisateur** : l'application `factura` renvoie des erreurs 500 depuis
cette nuit. `df -h` montre `/` à 97 %. Les journaux de `/var/log/factura/`
occupent plusieurs gigaoctets alors qu'une rotation quotidienne est « en place »
depuis six mois et que `systemctl status logrotate.timer` répond `active`.

**Interdit** : supprimer les fichiers de log à la main sans diagnostic, réinstaller
`logrotate`, redémarrer la VM.

**Objectif** : expliquer pourquoi la rotation ne s'est jamais exécutée pour ce
fichier alors que le timer tourne, la remettre en service, récupérer l'espace
disque sans perdre les journaux du jour, et dire quelle vérification tu ajoutes
pour que ça ne se reproduise pas silencieusement.

::: repondre
lignes: 12
:::

### **BF13.2** — « Le journal systemd a mangé 4 Go »

```bash
sudo bash break_M13_02.sh
```

**Symptôme utilisateur** : `df -h /var` affiche moins de 1 Go libre.
`du -sh /var/log/*` désigne `/var/log/journal` comme premier consommateur.
Aucun fichier `.log` n'est anormalement gros. Un collègue propose
`rm -rf /var/log/journal/*` : tu refuses.

**Interdit** : `rm` dans `/var/log/journal`, arrêter `systemd-journald`,
rollback de snapshot.

**Objectif** : mesurer précisément ce que consomme le journal, ramener sa taille
sous 500 Mo par la méthode prévue pour ça, expliquer pourquoi `rm -rf` est une
mauvaise idée même quand ça « marche », et poser une limite durable qui empêche
la situation de revenir.

::: repondre
lignes: 10
:::

### **BF13.3** — « Les logs de ce service ont des trous »

```bash
sudo bash break_M13_03.sh
```

**Symptôme utilisateur** : le développeur de `factura-api` affirme que son
application écrit une ligne par requête. `journalctl -u factura-api` en montre
quelques-unes, puis plus rien pendant 20 secondes, puis reprend. Aucune erreur
dans l'application, aucune erreur dans `systemctl status`. Le développeur accuse
« le serveur ».

**Interdit** : modifier le code de l'application, désactiver complètement la
journalisation.

**Objectif** : prouver par le journal lui-même que des messages ont été supprimés,
donner le nombre exact, identifier le mécanisme et sa configuration, le corriger
pour ce service **sans** désactiver la protection globale de la machine, et dire
ce que tu aurais recommandé au développeur.

::: repondre
lignes: 10
:::

### **BF13.4** — « Le fichier de log fait 800 Mo mais il est presque vide »

```bash
sudo bash break_M13_04.sh
```

**Symptôme utilisateur** : `ls -lh /var/log/factura/acces.log` affiche 800 Mo,
`du -h` du même fichier affiche 12 Mo, `wc -l` compte 4 000 lignes, et les
numéros de séquence des lignes présentent un trou de plusieurs centaines
d'entrées après chaque rotation. `less` affiche des `^@` en pagaille.

**Interdit** : modifier le code de l'application (le développeur est en congé),
supprimer le fichier.

**Objectif** : expliquer les deux anomalies distinctes (la taille apparente et le
trou de numérotation), nommer le mécanisme en cause dans la configuration de
rotation, corriger durablement, et dire ce que l'application devrait faire côté
code pour que le problème disparaisse à la source.

::: repondre
lignes: 12
:::

---

## 13.8 Défi du module ★★★

**D13 — Le poste de pilotage d'un serveur applicatif**

::: contexte
Tu récupères l'exploitation de `lab-web`. Aucune convention, aucun rapport,
aucune alerte. On te demande un ensemble cohérent : journaux maîtrisés, rotation
garantie, mesures collectées, et un outil unique qui dit en trente secondes si la
machine va bien. Livrable : une configuration, un script, un rapport.
:::

Cahier des charges :

1. **Journalisation** — le journal systemd est persistant, plafonné à 500 Mo,
   avec une rétention maximale de 30 jours ; les messages de facilité `local6`
   de l'application vont dans `/var/log/factura/metier.log` et nulle part
   ailleurs ; `factura-bruyant` n'écrit plus dans `/var/log/syslog`.
2. **Rotation** — tous les fichiers de `/var/log/factura/` tournent, avec au
   moins une règle basée sur la taille. `logrotate -d /etc/logrotate.conf` ne
   signale aucun fichier ignoré et aucune erreur, sur **toute** la configuration
   de la machine, pas seulement la tienne.
3. **Collecte** — `/opt/factura/bin/collecte-metriques.sh` alimente
   `/var/log/factura/metriques.csv`, et ce CSV est lui-même géré par logrotate
   (sinon tu réinventes le problème que tu viens de corriger).
4. **Outil de diagnostic** — écris `/opt/factura/bin/sante.sh`,
   `#!/usr/bin/env bash`, `set -euo pipefail`, exécutable sans argument par
   `mathieu` avec `sudo`, qui affiche sur stdout un rapport structuré :
   * identité de la machine, uptime, nombre de cœurs, date du dernier boot ;
   * charge à 1/5/15 min **et** le ratio charge/cœur ;
   * répartition CPU `us/sy/wa/st` mesurée sur 2 secondes ;
   * mémoire : total, disponible, pourcentage disponible, swap `si/so` ;
   * pour chaque système de fichiers monté en écriture : usage en %, et usage
     des **inodes** en % (le piège classique du `/var` « plein » à 40 %) ;
   * top 5 des processus par CPU et top 5 par RSS ;
   * les 5 plus gros consommateurs d'espace sous `/var/log` ;
   * taille du journal systemd et nombre d'entrées de priorité `err` ou pire
     depuis le dernier boot ;
   * unités systemd en échec ;
   * les 10 dernières lignes de priorité `err` du journal, horodatées.
5. **Sortie et code retour** — le rapport part sur stdout, les diagnostics
   internes sur stderr. Le script se termine par une section `VERDICT` qui liste
   les anomalies détectées selon les seuils du L13.4. Code retour : `0` si rien,
   `1` s'il y a au moins un avertissement, `2` s'il y a au moins une anomalie
   critique (`/` ou `/var` > 95 %, inodes > 90 %, swap actif, unité en échec).
6. **Robustesse** — le script tourne aussi sur `lab-ops` et sur `lab-rhel` sans
   modification. Il ne doit jamais planter parce qu'un outil optionnel est absent
   (`iostat`, `sar`) : il dégrade la section concernée et le dit.
7. **Livrable écrit** — `~/lab13/pilotage.md` : ce que tu as configuré, les
   seuils retenus **avec leur justification**, ce que ton script ne couvre pas,
   et les trois alertes que tu brancherais en premier sur Prometheus au
   module 22, avec pour chacune : condition, durée, gravité, et pourquoi elle
   mérite (ou non) une astreinte de nuit.

Temps visé : 60 à 90 minutes.

::: check
```bash
bash check_M13_06.sh
```
:::

---

## 13.9 Auto-évaluation

| Compétence | Acquis | À revoir |
|---|---|---|
| Décrire le trajet app → journald → rsyslog → fichier | ☐ | ☐ |
| Nommer facilités et sévérités syslog, écrire un sélecteur | ☐ | ☐ |
| Filtrer le journal par unité, priorité, temps, champ | ☐ | ☐ |
| Rendre le journal persistant, le mesurer, le purger | ☐ | ☐ |
| Reconnaître et corriger une suppression par RateLimit | ☐ | ☐ |
| Centraliser des journaux en TCP avec file d'attente | ☐ | ☐ |
| Écrire et tester une règle logrotate complète | ☐ | ☐ |
| Expliquer `create` contre `copytruncate` | ☐ | ☐ |
| Diagnostiquer un `/var` saturé sans supprimer au hasard | ☐ | ☐ |
| Interpréter charge, `us/sy/wa/st`, `available`, `%util` | ☐ | ☐ |
| Passer d'un symptôme à une cause avec vmstat/iostat/pidstat | ☐ | ☐ |
| Appliquer les 4 signaux dorés et la méthode USE | ☐ | ☐ |

Pour aller plus loin :

* Lis `man 5 journald.conf` en entier une fois, puis `man 8 logrotate` à la
  section CONFIGURATION FILE DIRECTIVES. Tout le module tient en dix pages.
* Explore `/proc/pressure/` (PSI) : `some avg10` sur `io` et `memory` détecte une
  saturation naissante bien avant que `%util` ou `available` ne bougent.
* Regarde ce que fait `journalctl --output=verbose` sur une seule entrée : tous
  les champs indexés y sont, c'est la carte de ce que tu peux filtrer.
