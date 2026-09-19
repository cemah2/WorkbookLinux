# Module 23 — Corrigé

## 23.3 Quiz — QCM

**Q23.1** — *`sudo pip install requests` répond `externally-managed-environment`.*

**Réponse : b)** `apt install python3-requests` pour un besoin système, sinon
un venv du projet.

::: pourquoi
Depuis la PEP 668, Debian et Ubuntu marquent le Python système comme « géré
de l'extérieur » : un fichier `EXTERNALLY-MANAGED` dans
`/usr/lib/python3.12/` fait refuser `pip` hors venv. La raison est
mécanique : `apt` et `pip` écriraient dans le même `site-packages`. Le jour
où `apt upgrade` remplace `python3-requests` et que `pip` avait posé une
autre version par-dessus, les fichiers se mélangent, et c'est `apt` (donc
`cloud-init`, `unattended-upgrades`, `ufw`…) qui casse.

Règle à trois tiroirs : le système par `apt`, le projet par `venv`, l'outil
par `pipx`. `--break-system-packages` existe pour les conteneurs jetables,
pas pour un serveur.
:::

::: piege
`pip install --user` (c) contourne le message mais installe dans
`~/.local/lib/python3.12/site-packages`, que le Python système **charge
aussi** : on retrouve le même conflit, en plus discret. Et depuis 24.04,
`--user` est lui aussi bloqué par la PEP 668.
:::

---

**Q23.2** — *Timer systemd, shebang `#!/usr/bin/env python3`, module du venv.*

**Réponse : b)** `ModuleNotFoundError`.

::: pourquoi
`#!/usr/bin/env python3` demande à `env` de chercher `python3` dans le
`PATH` du processus. Sous systemd, ce `PATH` est celui de l'unité
(`/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`), pas celui
de ton shell où `activate` avait mis `~/lab23/venv/bin` en tête. `env`
trouve donc `/usr/bin/python3`, qui ne connaît que `/usr/lib/python3` et
`dist-packages`. Le venv n'est jamais « activé » par magie : c'est un
répertoire avec un interpréteur et un `pyvenv.cfg`, et c'est **l'interpréteur
qu'on appelle** qui décide des modules visibles.

Le correctif est une ligne : `ExecStart=/home/mathieu/lab23/venv/bin/python
/home/mathieu/lab23/bin/sante.py`. Le shebang reste utile pour l'usage
interactif.
:::

---

**Q23.3** — *`def ajouter(nom, liste=[])` appelé deux fois.*

**Réponse : b)** `['lab-web', 'lab-db']`.

::: pourquoi
La valeur par défaut d'un paramètre est évaluée **une seule fois**, à la
définition de la fonction, et l'objet obtenu est stocké dans
`ajouter.__defaults__`. Chaque appel sans argument reçoit **le même objet
liste** ; `append` le modifie en place ; le second appel voit donc ce que le
premier a ajouté. Ce n'est pas un bug de CPython, c'est la sémantique : les
défauts sont des objets, pas des expressions rejouées.

Idiome : `liste: list[str] | None = None` puis `if liste is None: liste = []`.
`ruff` le signale (`B006`), c'est un des premiers réglages à activer.
:::

---

**Q23.4** — *`shell=True` et un chemin avec une espace.*

**Réponses : a) et b)**

::: pourquoi
Avec `shell=True`, Python passe la chaîne à `/bin/sh -c`. Le shell la
découpe sur les espaces : `tar` reçoit `/srv/rapport` puis `final`, deux
fichiers inexistants. `tar` sort en 2, mais `subprocess.run` sans
`check=True` se contente de renvoyer un `CompletedProcess` dont personne ne
regarde `.returncode` : le script continue et affiche « archive écrite ».

La chaîne est aussi une **injection** : un fichier nommé `x; rm -rf ~` fait
exécuter `rm` par le shell. La bonne forme est une liste, où chaque élément
devient exactement un argument, sans passage par un shell :
`subprocess.run(["tar", "-czf", dest, "--", rep], check=True)`.
:::

::: piege
Mettre des guillemets dans la f-string (`f'tar -czf "{dest}" "{rep}"'`)
repousse le problème jusqu'au premier nom contenant un guillemet ou un `$`.
`shlex.quote()` protège correctement, mais si tu en as besoin, c'est que tu
n'aurais pas dû passer par un shell.
:::

---

**Q23.5** — *Lancer `systemctl is-active nginx` avec exception sur échec.*

**Réponse : b)** `subprocess.run(["systemctl", "is-active", "nginx"],
check=True)`.

::: pourquoi
Sans `shell=True`, le premier argument est une liste : `argv[0]` est le
programme (cherché dans `PATH`), les suivants sont ses arguments, tels quels.
`check=True` transforme un code de retour non nul en
`subprocess.CalledProcessError`, qui porte `.returncode`, `.stdout` et
`.stderr`. La proposition a) passe une chaîne sans `shell=True` : Python
cherche un exécutable nommé littéralement `systemctl is-active nginx`, avec
les espaces, et lève `FileNotFoundError`. c) a le même défaut dans une liste
à un seul élément. d) est une erreur de syntaxe.
:::

---

**Q23.6** — *`except: pass` puis `sys.exit(0)` sur un site injoignable.*

**Réponse : b)** rien, code 0.

::: pourquoi
`urlopen` lève `URLError` ; l'`except` nu l'attrape et `pass` l'oublie ;
le script atteint `sys.exit(0)`. Pour le superviseur, la sonde a réussi. Le
défaut est double : attraper trop large, et ne rien faire de l'exception. Un
`except` doit toujours faire au moins une chose : journaliser, changer un
état, relever. Ici : `except urllib.error.URLError as exc:
log.error("%s : %s", url, exc); return False`.
:::

---

**Q23.7** — *`UnicodeDecodeError` sous le timer, pas dans le shell.*

**Réponse : b)** l'encodage par défaut dépend de la locale.

::: pourquoi
`open()` sans `encoding=` utilise `locale.getpreferredencoding()`. Dans ton
shell, `LANG=fr_FR.UTF-8` donne UTF-8. Sous systemd, `LANG` n'est pas
défini ; Python 3.7+ coerce alors la locale C vers `C.UTF-8`… sauf si l'unité
ou le système fixe `LC_ALL=C` ou une locale non UTF-8 (`Environment=` hérité
d'un vieux modèle d'unité, `/etc/default/locale` d'une image minimale).
Le point à retenir : **le comportement dépend de l'environnement**, donc il
n'est pas reproductible. `encoding="utf-8"` (et `errors="replace"` pour un
journal) fige le contrat. `python3 -X warn_default_encoding` liste les
`open()` fautifs.
:::

---

**Q23.8** — *3 000 fichiers ouverts d'un coup.*

**Réponse : b)** ouvrir dans un `with` à l'intérieur de la boucle.

::: pourquoi
Chaque `open()` consomme un descripteur du processus, plafonné par
`ulimit -n` (1024 par défaut sur Ubuntu). La liste en compréhension ouvre
tout avant de lire quoi que ce soit : au 1 021e fichier, le noyau refuse
(`EMFILE`). Le `with` ferme le descripteur à la sortie du bloc ; on ne garde
en mémoire que le compte. a) déplace le mur ; c) ne libère que ce qui n'est
plus référencé, et la liste référence tout ; d) `read_text` ouvre bien un
fichier, mais le ferme immédiatement — ce serait correct dans la boucle, pas
en gardant les handles.
:::

---

**Q23.9** — *Rapport lu par une sonde, jamais tronqué.*

**Réponse : b)**

::: pourquoi
`open(cible, "w")` tronque le fichier à 0 octet **avant** d'écrire : une
lecture entre les deux voit un fichier vide ou partiel. `rename(2)` est
atomique sur un même système de fichiers : les lecteurs voient soit
l'ancien inode, soit le nouveau, jamais un intermédiaire. D'où la séquence :
temporaire créé par `mkstemp` **dans le répertoire de la cible** (même
système de fichiers, sinon `os.replace` échoue avec `EXDEV`), écriture,
`flush` + `fsync` (les données sont sur le disque avant que le nom ne les
désigne), puis `os.replace`.
:::

---

**Q23.10** — *`requests.get` renvoie 401 sans `raise_for_status`.*

**Réponse : b)** le corps d'erreur, et le script continue.

::: pourquoi
`requests` ne lève **jamais** sur un code HTTP : un 401 est une réponse
valide du point de vue transport. `r.ok` est faux, `r.status_code` vaut 401,
`r.json()` décode ce que l'API a renvoyé (Proxmox : `{"data": null}`).
`r.raise_for_status()` lève `requests.HTTPError` pour tout 4xx/5xx. Sans
lui, un token expiré donne un inventaire vide « normal » et un script qui
sort en 0. Il n'y a pas de retry par défaut (d) : c'est `HTTPAdapter` +
`urllib3.util.Retry` qui l'ajoutent.
:::

---

**Q23.11** — *Affirmation fausse sur `logging`.*

**Réponse : d)**

::: pourquoi
`print(..., file=sys.stderr)` écrit toujours, sans niveau, sans horodatage,
sans nom de logger, sans possibilité de rediriger vers syslog ou un fichier
sans toucher au code. `logging` sépare **l'émission** (le code appelle
`log.info`) de **la destination et du format** (configurés une fois par
l'entrée du programme). C'est exactement ce qui permet à un même module de
tourner en CLI (stderr) et sous systemd (journal) sans modification.
:::

---

**Q23.12** — *Valeur d'une série Prometheus.*

**Réponse : b)** `float(...["value"][1])`.

::: pourquoi
L'API Prometheus renvoie `value: [timestamp, "valeur"]` : le timestamp est un
nombre, la valeur est une **chaîne** (pour transporter `NaN`, `+Inf` sans
ambiguïté JSON). Comparer `"1" == 1` en Python est faux sans lever d'erreur :
un test `if valeur == 0` ne verra jamais une cible tombée. `float()` est
obligatoire.
:::

---

**Q23.13** — *`pytest`, affirmations vraies.*

**Réponses : a) et b)**

::: pourquoi
`tmp_path` est un `pathlib.Path` unique par test, sous
`/tmp/pytest-of-<user>/`, purgé par rotation. `monkeypatch` annule ses
modifications à la fin du test, quel que soit son résultat. c) est faux :
`logging` n'écrit pas dans `sys.stderr` capturé par `capsys` quand le
gestionnaire a été installé avant (et pytest installe le sien) — c'est
`caplog.text` qui contient les messages. d) : les fonctions collectées sont
`test_*` dans des fichiers `test_*.py` ou `*_test.py`.
:::

---

**Q23.14** — *`dates[-n:]` avec `n = 0`.*

**Réponse : b)** toute la liste.

::: pourquoi
`-0` vaut `0` : `dates[-0:]` est `dates[0:]`, la copie complète. Une
politique « garder 0 quotidiennes » qui garde tout est le genre de bug qu'un
test unitaire attrape en une ligne et qu'une relecture ne voit jamais. La
forme sûre : `dates[-n:] if n > 0 else []`.
:::

---

**Q23.15** — *`[project.scripts]` après `pip install .`.*

**Réponse : b)**

::: pourquoi
`pip` génère dans le `bin/` de l'environnement cible un petit lanceur dont
le shebang pointe sur **le python de ce venv** et qui importe
`pilotage.cli` puis appelle `main()`. Il embarque donc son interpréteur et
ses dépendances : c'est ce chemin absolu qu'on met dans `ExecStart=`. Rien
n'est écrit hors du venv ; `pipx install .` fait la même chose dans un venv
privé et ajoute un lien dans `~/.local/bin`.
:::

---

**Q23.16** — *Inventaire Proxmox croisé avec Gitea, issues à ouvrir.*

**Réponse : b)** Python.

::: pourquoi
Deux API à interroger avec authentification, deux structures à croiser
(ensembles, dictionnaires), une logique de décision qu'on veut tester sans
réseau, et des effets de bord (ouvrir une issue) qu'on veut pouvoir simuler
en `--dry-run`. Bash + `jq` tiendrait vingt lignes pour le cas nominal et
deux cents pour gérer les erreurs ; Ansible n'a pas de boucle de décision
naturelle et ce n'est pas un état à converger.
:::

---

**Q23.17** — *Comparer avec l'expiration d'un certificat.*

**Réponse : d)** b et c.

::: pourquoi
`ssl.cert_time_to_seconds("Sep 18 12:00:00 2027 GMT")` rend un timestamp
POSIX (secondes depuis l'epoch, UTC). On le compare à `time.time()`, ou à
`datetime.now(UTC).timestamp()`, qui sont la même chose. `datetime.now()`
sans fuseau est **naïf** : le comparer à un `datetime` aware lève
`TypeError`, et le convertir en timestamp suppose l'heure locale — faux dès
que le serveur est en UTC et l'exploitant à Paris.
:::

---

**Q23.18** — *`print` qui apparaît après la sortie d'une commande.*

**Réponse : b)**

::: pourquoi
Quand stdout n'est pas un terminal (pipe, fichier, journald), Python le
bufferise par blocs de 8 Ko : `print` écrit dans un tampon, vidé à la fin ou
quand il est plein. stderr, lui, est toujours écrit immédiatement. La
commande fille écrit directement sur le descripteur 2 pendant que ton
« étape 1 » attend dans le tampon. `PYTHONUNBUFFERED=1` dans l'unité, ou
`print(..., flush=True)`, ou mieux : `logging` sur stderr pour tout ce qui
est chronologie.
:::

---

## 23.4 Quiz — questions ouvertes

**QO23.1** — *`activate`, timers, `python3 -m pip`.*

**Réponse de référence**

`source venv/bin/activate` fait trois choses : il préfixe `PATH` avec
`venv/bin`, exporte `VIRTUAL_ENV`, et modifie le prompt. C'est tout. Aucun
module n'est « chargé » : c'est parce que `python` est maintenant
`venv/bin/python` que les imports voient `venv/lib/python3.12/site-packages`.
L'interpréteur du venv se reconnaît grâce au fichier `pyvenv.cfg` à côté de
lui, pas grâce à une variable.

Conséquence : un timer n'a rien à activer. Il suffit d'appeler
l'interpréteur par son chemin :
`ExecStart=/opt/factura/venv/bin/python /opt/factura/bin/sante.py`, ou le
lanceur `[project.scripts]` : `ExecStart=/opt/factura/venv/bin/sante`.

`pip install x` exécute **le premier `pip` du PATH**, qui peut appartenir à
un autre interpréteur que celui qui exécutera le script. `python3 -m pip
install x` exécute le module `pip` **de ce `python3`-là** : l'installation
atterrit là où l'import aura lieu. Même logique pour `python3 -m pytest`,
`python3 -m venv`, `python3 -m json.tool`.

::: pourquoi
Ce qu'on évalue : comprendre que le venv est une propriété de
l'interpréteur appelé, pas de l'environnement du shell. Un candidat qui
propose `source activate` dans `ExecStart` ou dans un wrapper bash n'a pas
compris le mécanisme (et `activate` n'est même pas un exécutable).
:::

---

**QO23.2** — *Reprise d'un script à `shell=True` partout.*

**Réponse de référence**

Je commence par `grep -n "shell=True" script.py` et, pour chaque ligne, je
regarde **d'où vient la chaîne** : constante (tolérable, à convertir quand
même) ou construite à partir d'un argument, d'un nom de fichier, d'une
réponse d'API (dangereux). Le danger tient en deux mécanismes du shell :
le **découpage des mots** (une espace dans un nom = deux arguments) et
les **métacaractères** (`;`, `|`, `$( )`, `*`, `>`), qui transforment une
donnée en commande — c'est l'injection.

Correctif ligne à ligne, sans réécriture : remplacer la chaîne par une liste
d'arguments (`["tar", "-czf", dest, "--", src]`), supprimer `shell=True`,
ajouter `check=True` (sinon l'échec est silencieux), `timeout=` (sinon un
`ssh` bloqué bloque le job), `capture_output=True, text=True` si la sortie
est lue. Quand la ligne utilisait vraiment le shell (un pipe, une
redirection), je la remplace par deux `Popen` chaînés ou, plus simplement,
par un traitement Python de la sortie. `shlex.split()` aide à convertir
une commande littérale en liste ; `shlex.quote()` est le dernier recours si
un shell est incontournable.

Je finis par un test avec un nom de fichier contenant une espace et un `;`,
que j'ajoute à la suite de tests.

::: pourquoi
La question mesure si tu sais **nommer** les mécanismes (découpage,
métacaractères, code de retour ignoré) et si tu as une méthode incrémentale
défendable en revue. « Je réécris tout en Python propre » n'est pas une
réponse : c'est un risque de régression sans test.
:::

---

**QO23.3** — *`except:`, `except Exception:`, `except (OSError, ValueError):`.*

**Réponse de référence**

Toutes les exceptions héritent de `BaseException`. `Exception` en est un
sous-arbre : les erreurs « normales » (`OSError`, `ValueError`, `KeyError`,
`requests.RequestException`…). Hors de ce sous-arbre, directement sous
`BaseException`, vivent `SystemExit` (levée par `sys.exit()`),
`KeyboardInterrupt` (Ctrl-C, SIGINT) et `GeneratorExit`.

* `except:` attrape **tout**, y compris `SystemExit` et `KeyboardInterrupt`.
  Un `sys.exit(2)` placé dans le `try` est avalé : le script continue et
  sort en 0. Ctrl-C ne fait plus rien. Un `SIGTERM` de systemd, lui, n'est
  pas une exception : le processus meurt sans `finally`.
* `except Exception:` laisse passer l'arrêt volontaire et Ctrl-C, mais
  attrape encore trop : une faute de frappe (`NameError`), un bug de type
  (`TypeError`) sont masqués comme si c'étaient des aléas d'exploitation.
* `except (OSError, ValueError) as exc:` dit **ce qu'on sait gérer**. Tout
  le reste remonte avec sa trace, et c'est ce qu'on veut : un bug doit
  planter bruyamment.

Dans un timer, un `except:` transforme une panne en succès : la supervision
voit un code 0, l'incident est découvert des semaines plus tard.

::: pourquoi
Le bon réflexe s'exprime ainsi : « j'attrape ce que je sais réparer ou
signaler ; je laisse remonter ce que je ne comprends pas ». Et jamais un
`except` sans corps utile : au minimum `log.exception(...)`.
:::

---

**QO23.4** — *Lecture en flux, `.gz`, stdin, latin-1.*

**Réponse de référence**

`f.read()` charge tout le fichier en une chaîne (8 Go de fichier = plus de
8 Go de RAM, car les chaînes Python sont décodées et indexables), puis
`splitlines()` en crée une seconde copie sous forme de liste : le noyau
finit par tuer le processus (OOM). `for ligne in f:` utilise le protocole
d'itération de l'objet fichier : il lit par blocs (tampon de 8 Ko) et ne
garde qu'une ligne en mémoire à la fois. La consommation est constante,
quelle que soit la taille.

Le même code fonctionne sur n'importe quel objet qui itère des lignes :
`gzip.open(p, "rt", encoding="utf-8")` décompresse à la volée ;
`sys.stdin` itère aussi, ligne par ligne, ce qui permet
`zcat *.gz | script.py -`.

Sans `encoding=`, Python décode avec la locale. Un fichier latin-1 contient
des octets comme `0xE9` (`é`) invalides en UTF-8 : `UnicodeDecodeError` à la
première ligne accentuée — et au milieu d'un run nocturne. Trois réponses
selon le cas : `encoding="latin-1"` si on connaît la source ;
`errors="replace"` pour un journal où perdre un caractère est acceptable ;
mode binaire et détection si on ne sait pas.

::: pourquoi
L'objet fichier Python est un itérateur paresseux : c'est le concept à
nommer. Un candidat qui connaît `readlines()` mais pas `for ligne in f`
écrira des scripts qui marchent sur ses tests et meurent en production.
:::

---

**QO23.5** — *Rétention qui a supprimé une mensuelle.*

**Réponse de référence**

1. **Séparer la décision de l'action.** `selection(dates, politique)`
   reçoit des dates et rend l'ensemble à garder : aucune E/S. `appliquer()`
   supprime. On peut donc tester la décision avec des dates fabriquées,
   sans disque, en millisecondes.
2. **Tests unitaires de la sélection** : 7 quotidiennes exactes ; une
   hebdomadaire par semaine ISO et c'est la dernière ; une mensuelle par
   mois et c'est la première ; les recouvrements ne comptent qu'une fois ;
   `n = 0` garde zéro (le piège `[-0:]`).
3. **Le test de l'incident** : je reconstruis exactement le jeu de la
   nuit fautive (120 dates, la mensuelle du mois précédent) et j'affirme
   qu'elle est gardée. Ce test échoue sur l'ancien code, passe sur le
   nouveau, et empêche toute régression future : c'est la définition d'un
   test de non-régression.
4. **`--dry-run` par défaut dans le timer pendant une semaine**, avec le
   bilan en JSON dans le journal ; on compare avec ce qu'on attend avant de
   retirer l'option.
5. La date vient du **nom** du fichier, pas du mtime, qu'une restauration
   ou un `cp` modifie.

::: pourquoi
Ce qu'on attend : que la réponse à « comment tu t'assures » soit un test
qui **reproduit l'incident**, pas « je ferai plus attention ». Et que la
testabilité découle d'un découpage (pur / effets), pas d'un outil.
:::

---

**QO23.6** — *Écriture atomique.*

**Réponse de référence**

`open(cible, "w")` appelle `open(2)` avec `O_TRUNC` : le fichier est vidé
immédiatement, puis rempli au rythme des `write`. Entre les deux, tout
lecteur voit un fichier vide ou partiel. Si le processus meurt au milieu,
le fichier reste tronqué : l'ancien contenu est perdu **et** le nouveau
n'est pas là.

Écriture atomique : créer un fichier temporaire avec `tempfile.mkstemp(dir=
cible.parent)` (nom unique, ouvert en `O_EXCL`), y écrire, `flush()` puis
`os.fsync(fd)` pour forcer les données sur le support, fermer, puis
`os.replace(tmp, cible)`. `rename(2)` remplace l'entrée de répertoire de
façon atomique : un lecteur ouvre soit l'ancien inode, soit le nouveau. Un
lecteur qui avait déjà l'ancien ouvert continue de le lire jusqu'au bout.

Le temporaire doit être **dans le même répertoire** (ou au moins le même
système de fichiers) : `/tmp` est souvent un `tmpfs` distinct, et
`os.replace` entre deux systèmes de fichiers échoue (`EXDEV`) — ou, avec
`shutil.move`, retombe sur copie + suppression, qui n'est plus atomique. En
bonus, on pose les droits voulus (`os.chmod`) avant le `replace`, puisque
`mkstemp` crée en `0600`.

---

**QO23.7** — *`urllib.request` contre `requests` pour Proxmox.*

**Réponse de référence**

| Besoin | `urllib.request` | `requests` |
|---|---|---|
| en-tête token | `Request(url, headers={...})` | `session.headers[...]` une fois |
| timeout | `urlopen(req, timeout=5)` : un seul délai | `timeout=(connexion, lecture)` |
| 4xx/5xx | `HTTPError` levée automatiquement | rien sans `raise_for_status()` |
| retries | à écrire à la main | `HTTPAdapter(max_retries=Retry(...))` |
| JSON | `json.load(rep)` | `r.json()` |
| TLS privé | `ssl.create_default_context(cafile=...)` | `verify="/chemin/ca.crt"` |

`urllib` lève sur 4xx/5xx, `requests` non : c'est le piège inverse dans
chaque camp. Je reste sur la bibliothèque standard quand le script doit
tourner **sans venv** (une sonde déposée sur 50 machines, un hook
`cloud-init`), qu'il fait un ou deux GET, et que je n'ai pas besoin de
session ni de retries. Dès qu'il y a une session authentifiée, du POST JSON,
des retries ou plusieurs API, `requests` économise cinquante lignes et des
bugs.

---

**QO23.8** — *Cinq critères bash / Python.*

**Réponse de référence**

1. **Données** — `inventaire.py` croise deux appels API et produit du YAML
   imbriqué. En bash : `jq` en cascade, tableaux associatifs non
   imbriquables, quoting acrobatique pour une liste de listes.
2. **Idempotence** — hors périmètre de Python comme de bash : c'est
   Ansible (L19). Mais un script Python qui rend un état (`sante.py`,
   JSON) s'intègre à Ansible comme *fact*.
3. **Taille** — `sante.sh` du module 13 : 200 lignes, un `set -e`
   désamorcé partout par `|| true`. `pilotage` fait la même chose en trois
   fichiers de 100 lignes, chacun testé.
4. **Testabilité** — `rotate_backups.py` a un test qui reproduit
   l'incident ; en bash, il aurait fallu `bats`, des répertoires temporaires
   et des `find` réels — lent, fragile, rarement écrit.
5. **Long-running** — `factura_exporter.py` tourne des semaines, gère
   `SIGTERM`, sert du HTTP en threads. Bash n'a ni serveur HTTP, ni
   threads, ni structure pour garder un état.

Critère inverse, toujours valable : `regen-sauvegardes.sh` et
`logstats.awk` restent en bash — une suite de commandes, une page, aucun
état. Et une boucle `for h in $(cat hotes); do ssh "$h" uptime; done` n'a
pas besoin de Python.

::: pourquoi
La réponse attendue croise les critères du module 07 avec deux critères
nouveaux (tests, durée de vie) **et** garde le critère inverse. Un candidat
qui ne sait pas dire quand rester en bash n'a pas de jugement, il a une
préférence.
:::

---

## 23.5 Exercices guidés

**E23.1** — *Ce que change l'activation du venv.*

```console
$ which python3 ; python3 -c 'import sys; print(sys.prefix)' ; pip --version
/usr/bin/python3
/usr
pip 24.0 from /usr/lib/python3/dist-packages/pip (python 3.12)
$ source ~/lab23/venv/bin/activate
(venv) $ which python3 ; python3 -c 'import sys; print(sys.prefix)'
/home/mathieu/lab23/venv/bin/python3
/home/mathieu/lab23/venv
(venv) $ deactivate
$ ~/lab23/venv/bin/python -c 'import yaml; print(yaml.__file__)'
/home/mathieu/lab23/venv/lib/python3.12/site-packages/yaml/__init__.py
```

::: pourquoi
Le seul effet observable de `activate` est `PATH` (et `VIRTUAL_ENV`).
L'appel direct `venv/bin/python` fonctionne sans activation parce que
l'interpréteur lit le `pyvenv.cfg` situé à côté de lui et en déduit son
`sys.prefix`, donc son `site-packages`. C'est cette propriété qui rend les
timers et les crons simples : un chemin absolu, rien d'autre.
:::

---

**E23.2** — *`ruff` via `pip` et via `pipx`.*

```bash
pip install ruff          # dans le venv actif
which ruff                # ~/lab23/venv/bin/ruff
pipx install ruff         # venv privé ~/.local/pipx/venvs/ruff
pipx list
pip uninstall -y ruff ; hash -r ; which ruff   # ~/.local/bin/ruff
```

::: pourquoi
`ruff` est un **outil** : on veut la même version sur tous les projets et
on ne l'importe jamais. `pipx` le met dans un venv privé et expose un lien
dans `~/.local/bin`. `requests` est une **dépendance** : chaque projet peut
en vouloir une version différente, et le code l'importe — il va dans le venv
du projet, épinglé dans `requirements.txt`. Mettre `ruff` dans chaque venv
n'est pas faux (certaines équipes l'épinglent en `dev`), c'est juste
redondant.
:::

---

**E23.3** — *Épingler et reproduire.*

```bash
~/lab23/venv/bin/pip freeze > ~/lab23/requirements.txt
head -3 ~/lab23/requirements.txt      # certifi==2025.8.3 ... requests==2.32.5
python3 -m venv ~/lab23/venv2 && ~/lab23/venv2/bin/pip install -q \
  -r ~/lab23/requirements.txt
diff <(~/lab23/venv/bin/pip list --format=freeze) \
     <(~/lab23/venv2/bin/pip list --format=freeze) && echo identiques
```

::: pourquoi
`requirements.in` dit ce qu'on **veut** (`requests>=2.32,<3`) ;
`requirements.txt` dit ce qu'on **a** (`requests==2.32.5`, plus ses
dépendances transitives `urllib3`, `certifi`, `idna`, `charset-normalizer`).
Sans épinglage, deux déploiements à un mois d'intervalle installent des
versions différentes, et l'incident « ça marchait hier » commence. Les deux
fichiers se committent ; on met à jour `requirements.txt` volontairement,
en relançant les tests.
:::

---

**E23.4** — *`hotes.py` : fixture, dataclass, compréhension.*

```python
#!/usr/bin/env python3
import json
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Vm:
    nom: str
    vmid: int
    statut: str


def charger(chemin: Path) -> list[Vm]:
    with chemin.open(encoding="utf-8") as f:
        data = json.load(f)
    return sorted(
        (Vm(r["name"], r["vmid"], r["status"]) for r in data["resources"]
         if r["type"] == "qemu" and r["status"] == "running"),
        key=lambda v: v.nom,
    )


def main() -> int:
    for vm in charger(Path(sys.argv[1])):
        print(f"{vm.nom:<16}{vm.vmid:>6}  {vm.statut}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

::: pourquoi
`frozen=True` rend l'objet immuable et hachable (utilisable dans un `set`),
et génère `__init__`, `__repr__`, `__eq__`. L'expression génératrice entre
parenthèses ne construit pas de liste intermédiaire : `sorted` la consomme.
`f"{vm.nom:<16}"` aligne à gauche sur 16 colonnes, `{vm.vmid:>6}` à droite :
c'est le `printf '%-16s%6d'` de bash, sans l'appel externe.
:::

---

**E23.5** — *Mutable par défaut, compter.*

```console
$ python3 casse/mutable.py
prod    : ['lab-web', 'lab-db']
recette : ['lab-web', 'lab-db']
```

```python
def ajouter_hote(nom: str, liste: list[str] | None = None) -> list[str]:
    if liste is None:
        liste = []
    liste.append(nom)
    return liste

def compter(mots: list[str]) -> dict[str, int]:
    n: dict[str, int] = {}
    for m in mots:
        n[m] = n.get(m, 0) + 1
    return n

from collections import Counter

def compter2(mots: list[str]) -> dict[str, int]:
    return dict(Counter(mots))

# Counter(mots).most_common(3) : le « top 3 » gratuit
```

::: pourquoi
Les deux variables `prod` et `recette` sont **le même objet** : `prod is
recette` vaut `True`. La liste par défaut a été créée une fois à la
définition. `Counter` est un `dict` spécialisé ; `most_common(n)` remplace
`sort | uniq -c | sort -rn | head -n`.
:::

---

**E23.6** — *`purge.py` sans `os.system`.*

```python
#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path


def main() -> int:
    p = argparse.ArgumentParser(description="Supprime les *.tmp d'un rép.")
    p.add_argument("repertoire", type=Path)
    p.add_argument("-n", "--dry-run", action="store_true")
    a = p.parse_args()
    if not a.repertoire.is_dir():
        print(f"{a.repertoire} : pas un répertoire", file=sys.stderr)
        return 2
    n = 0
    for f in sorted(a.repertoire.glob("*.tmp")):
        print(("supprimerait " if a.dry_run else "supprime ") + str(f))
        if not a.dry_run:
            f.unlink()
        n += 1
    print(f"{n} fichier(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

```console
$ mkdir -p "/tmp/rép avec espace" && touch "/tmp/rép avec espace/x.tmp"
$ ./purge.py "/tmp/rép avec espace" ; ls casse/tmp   # important.txt intact
```

::: pourquoi
`os.system("rm -f " + rep + "/*.tmp")` passe par un shell : une espace dans
`rep` découpe la commande, un `rep` vide donne `rm -f /*.tmp`, et le glob
est interprété par le shell, pas par Python. `Path.glob` rend des objets
`Path` qu'on supprime un par un, sans shell, et un `--dry-run` devient
trivial puisque la décision et l'action sont séparées.
:::

---

**E23.7** — *Encodages : latin-1 et BOM.*

```console
$ python3 casse/lecture.py data/clients-latin1.csv
UnicodeDecodeError: 'utf-8' codec can't decode byte 0xe9 in position 22...
```

```python
#!/usr/bin/env python3
import csv
import sys

chemin = sys.argv[1]
enc = "latin-1" if "latin1" in chemin else "utf-8-sig"
with open(chemin, encoding=enc, newline="") as f:
    for ligne in csv.DictReader(f, delimiter=";"):
        print(ligne.get("ville") or ligne.get("ip"))
```

::: pourquoi
`0xE9` est `é` en latin-1 ; en UTF-8, `é` s'écrit `0xC3 0xA9`, et `0xE9`
seul est un début de séquence invalide. `utf-8-sig` lit un fichier UTF-8
avec ou sans BOM (`EF BB BF`) : sans lui, le BOM se retrouve collé au nom de
la première colonne (`﻿hote`) et `ligne["hote"]` lève `KeyError` —
l'erreur classique après un export Excel. `csv.DictReader` gère les champs
entre guillemets contenant le séparateur, ce qu'un `split(";")` ne fait pas ;
`newline=""` est exigé par le module `csv`.
:::

---

**E23.8** — *`ssh-check.py` depuis stdin.*

```python
#!/usr/bin/env python3
import socket
import sys
import time


def tester(hote: str, port: int = 22, timeout: float = 2.0) -> tuple:
    debut = time.monotonic()
    try:
        with socket.create_connection((hote, port), timeout=timeout):
            ok = True
    except OSError:
        ok = False
    return ok, int((time.monotonic() - debut) * 1000)


def main() -> int:
    echecs = 0
    for ligne in sys.stdin:
        hote = ligne.split("#", 1)[0].strip()
        if not hote:
            continue
        ok, ms = tester(hote)
        echecs += not ok
        print(f"{hote} {'OK' if ok else 'KO'} {ms}")
    return 1 if echecs else 0


if __name__ == "__main__":
    sys.exit(main())
```

::: pourquoi
Lire `sys.stdin` ligne à ligne rend le script composable : `< hotes.txt`,
`| tee`, ou une sortie d'`inventaire.py`. `socket.create_connection` fait la
résolution DNS et l'essai TCP ; toutes ses erreurs (refus, délai, nom
inconnu) sont des `OSError`, une seule clause suffit. `time.monotonic()` ne
recule jamais, contrairement à `time.time()` en cas de réglage NTP.
:::

---

**E23.9** — *`stock.py` avec `logging` et syslog.*

```python
#!/usr/bin/env python3
import argparse
import logging
import sys
import time
from logging.handlers import SysLogHandler

log = logging.getLogger("stock")


def traiter(lot: int) -> None:
    log.info("traitement du lot %d", lot)
    if lot % 3 == 0:
        log.error("lot %d corrompu", lot)
    time.sleep(0.2)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("-v", "--verbose", action="store_true")
    a = p.parse_args()
    logging.basicConfig(
        level=logging.INFO if a.verbose else logging.WARNING,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        stream=sys.stderr,
    )
    try:
        sl = SysLogHandler(address="/dev/log")
        sl.setFormatter(logging.Formatter("stock: %(levelname)s %(message)s"))
        logging.getLogger().addHandler(sl)
    except OSError as exc:              # pas de socket syslog (conteneur)
        log.warning("syslog indisponible : %s", exc)
    for lot in range(1, 7):
        traiter(lot)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

```console
$ ./stock.py > /dev/null          # les ERROR restent visibles (stderr)
$ journalctl -t stock -n 5        # les mêmes, dans le journal
```

::: pourquoi
Trois destinations, une seule ligne de code métier : `log.error(...)`.
`basicConfig` installe le gestionnaire stderr ; `SysLogHandler` sur
`/dev/log` parle au socket de journald/rsyslog, avec la priorité déduite du
niveau (`ERROR` → `err`). Le nom `stock:` en tête du message sert
d'identifiant (`-t stock`). `print` n'aurait offert ni le niveau, ni le
filtrage `-v`, ni syslog.
:::

---

**E23.10** — *`exec-tracee.py`.*

```python
#!/usr/bin/env python3
import argparse
import logging
import subprocess
import sys
import time

log = logging.getLogger("exec-tracee")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("-t", "--tag", default="exec")
    p.add_argument("--timeout", type=float)
    p.add_argument("commande", nargs=argparse.REMAINDER)
    a = p.parse_args()
    cmd = a.commande[1:] if a.commande[:1] == ["--"] else a.commande
    if not cmd:
        p.error("commande manquante après --")
    logging.basicConfig(level=logging.INFO, stream=sys.stderr,
                        format=f"%(asctime)s [{a.tag}] %(message)s")
    log.info("début : %s", " ".join(cmd))
    debut = time.monotonic()
    try:
        rc = subprocess.run(cmd, timeout=a.timeout).returncode
    except FileNotFoundError:
        log.error("commande introuvable : %s", cmd[0])
        return 127
    except subprocess.TimeoutExpired:
        log.error("délai dépassé (%s s)", a.timeout)
        return 124
    log.info("fin : code %d, %.2f s", rc, time.monotonic() - debut)
    return rc


if __name__ == "__main__":
    sys.exit(main())
```

::: pourquoi
`nargs=argparse.REMAINDER` récupère tout ce qui suit, y compris des options
destinées à la commande fille. Sans `capture_output`, la commande hérite de
stdout/stderr : sa sortie n'est ni réordonnée ni préfixée, comme dans
`exec-tracee.sh`. Le code est transmis **tel quel** ; `127` et `124` sont
les conventions de bash et de `timeout(1)`, réutilisées volontairement.
Chaque argument de la liste arrive intact : `'a b'` reste un seul argument.
:::

---

**E23.11** — *Dates, fuseaux, naïf contre aware.*

```python
#!/usr/bin/env python3
from datetime import UTC, date, datetime
from zoneinfo import ZoneInfo

maintenant = datetime.now(UTC)
print(maintenant.isoformat(timespec="seconds"))
print(maintenant.astimezone(ZoneInfo("Europe/Paris")).isoformat())
d = datetime.strptime("18/Sep/2026:14:02:11 +0200", "%d/%b/%Y:%H:%M:%S %z")
print(d, "->", d.astimezone(UTC))
prochain = date(date.today().year + 1, 1, 1)
print((prochain - date.today()).days, "jours avant le 1er janvier")
try:
    _ = datetime.now() < maintenant
except TypeError as exc:
    print("naïf vs aware :", exc)
```

::: pourquoi
Un `datetime` **aware** porte un `tzinfo` ; un naïf n'en a pas et Python
refuse de les comparer (`can't compare offset-naive and offset-aware
datetimes`). La règle en exploitation : tout en UTC en interne
(`datetime.now(UTC)`), conversion en `Europe/Paris` uniquement à
l'affichage. `%z` lit `+0200` ; `%b` lit `Sep` — en locale C, ce que
`strptime` utilise par défaut. `zoneinfo` lit `/usr/share/zoneinfo` : le
paquet `tzdata` doit être présent (il l'est sur Ubuntu).
:::

---

**E23.12** — *Empreintes SHA-256, écriture atomique, diff.*

```python
#!/usr/bin/env python3
import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path

rep = Path(sys.argv[1])
cible = rep / "empreintes.json"
anciennes = json.loads(cible.read_text("utf-8")) if cible.exists() else {}
nouvelles = {}
for f in sorted(p for p in rep.iterdir() if p.is_file() and p != cible):
    with f.open("rb") as fh:
        nouvelles[f.name] = hashlib.file_digest(fh, "sha256").hexdigest()
for nom, h in nouvelles.items():
    if nom in anciennes and anciennes[nom] != h:
        print("modifié :", nom)
fd, tmp = tempfile.mkstemp(dir=rep, prefix=".empreintes-")
with os.fdopen(fd, "w", encoding="utf-8") as out:
    json.dump(nouvelles, out, indent=2)
    out.flush()
    os.fsync(out.fileno())
os.replace(tmp, cible)
```

::: pourquoi
`hashlib.file_digest` (3.11+) lit par blocs : un fichier de 4 Go ne passe
pas en mémoire. La séquence `mkstemp` dans le **même répertoire** →
`fsync` → `os.replace` garantit qu'un lecteur concurrent voit toujours un
JSON complet. Le temporaire commence par `.` pour ne pas être pris pour un
fichier à hacher lors d'une exécution simultanée.
:::

---

**E23.13** — *Prometheus avec `urllib.request`.*

```python
#!/usr/bin/env python3
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

base = "http://10.10.10.14:9090/api/v1/query?"
url = base + urllib.parse.urlencode({"query": "up"})
try:
    with urllib.request.urlopen(url, timeout=5) as rep:
        d = json.load(rep)
except urllib.error.HTTPError as exc:      # réponse reçue, code >= 400
    print(f"HTTP {exc.code} : {exc.reason}", file=sys.stderr)
    sys.exit(1)
except urllib.error.URLError as exc:       # pas de réponse du tout
    print(f"injoignable : {exc.reason}", file=sys.stderr)
    sys.exit(1)
for serie in d["data"]["result"]:
    print(serie["metric"].get("instance", "?"), float(serie["value"][1]))
```

```console
$ ./prom.py          # lab-ops éteint
injoignable : [Errno 111] Connection refused
```

::: pourquoi
`urlencode` encode la requête PromQL (espaces, accolades, guillemets) :
construire l'URL à la main casse dès le premier `{job="node"}`. `HTTPError`
**hérite** de `URLError` : il faut l'attraper en premier, sinon la clause
générique le prend et on perd le code. La valeur est une chaîne : `float()`.
:::

---

**E23.14** — *`requests`, `Session`, retries, Gitea.*

```python
#!/usr/bin/env python3
import os
import sys

import requests
from requests.adapters import HTTPAdapter
from urllib3.util import Retry

s = requests.Session()
retry = Retry(total=3, backoff_factor=0.5, status_forcelist=[502, 503, 504],
              allowed_methods=["GET"])
s.mount("http://", HTTPAdapter(max_retries=retry))
s.mount("https://", HTTPAdapter(max_retries=retry))
try:
    r = s.get("http://10.10.10.14:9090/api/v1/query",
              params={"query": "up"}, timeout=(3.05, 10))
    r.raise_for_status()
    for serie in r.json()["data"]["result"]:
        print(serie["metric"].get("instance"), float(serie["value"][1]))
    tok = os.environ["GITEA_TOKEN"]
    r = s.get("http://10.10.10.14:3000/api/v1/repos/search",
              params={"q": "factura"}, timeout=10,
              headers={"Authorization": f"token {tok}"})
    r.raise_for_status()
    for depot in r.json()["data"]:
        print(depot["full_name"], depot["updated_at"])
except KeyError:
    print("GITEA_TOKEN manquant", file=sys.stderr)
    sys.exit(2)
except requests.RequestException as exc:
    print(f"API : {exc}", file=sys.stderr)
    sys.exit(1)
```

::: pourquoi
`timeout=(3.05, 10)` distingue le délai de **connexion** (3,05 s, un peu
plus qu'un multiple de 3 s, le retransmit TCP) et de **lecture** (10 s
entre deux octets). `Retry` avec `backoff_factor=0.5` attend 0, 1, 2 s ;
`status_forcelist` ne réessaie que sur les erreurs de passerelle — jamais
sur un 401 ou un 404, qui ne changeront pas. Gitea attend `Authorization:
token <valeur>` (le mot `token`, pas `Bearer`, même si les deux passent
sur les versions récentes). Le token vient de l'environnement : un token
dans le code finit dans Git.
:::

---

**E23.15** — *API Proxmox contre `pvesh`.*

```python
#!/usr/bin/env python3
import argparse
import os
import sys

import requests

p = argparse.ArgumentParser()
p.add_argument("--url", default="https://10.10.10.1:8006")
p.add_argument("--ca", help="certificat CA de Proxmox")
p.add_argument("--insecure", action="store_true")
a = p.parse_args()
tok = os.environ.get("PVE_TOKEN") or sys.exit("PVE_TOKEN manquant")
s = requests.Session()
s.headers["Authorization"] = f"PVEAPIToken={tok}"
s.verify = a.ca if a.ca else not a.insecure
try:
    r = s.get(f"{a.url}/api2/json/cluster/resources",
              params={"type": "vm"}, timeout=(3.05, 10))
    r.raise_for_status()
except requests.RequestException as exc:
    sys.exit(f"API Proxmox : {exc}")      # message sur stderr, code 1
for vm in sorted(r.json()["data"], key=lambda v: v["vmid"]):
    print(f"{vm['vmid']:>6} {vm['name']:<18} {vm['status']:<8} "
          f"{vm.get('tags', '')}")
```

```bash
# sur l'hyperviseur
pvesh get /cluster/resources --type vm --output-format json | jq '.[].name'
```

::: pourquoi
Deux différences à noter. **Authentification** : `pvesh` tourne en root sur
le nœud et n'a besoin de rien ; l'API REST exige un token
`user@realm!id=uuid` dont les droits (`VM.Audit`) sont **plus étroits** que
root — c'est ce qu'on veut pour un script d'inventaire. **Format** : `pvesh`
sort le tableau directement ; l'API l'enveloppe dans `{"data": [...]}`. Le
certificat de Proxmox est auto-signé : `verify=` vers le CA exporté
(`/etc/pve/pve-root-ca.pem`) est la bonne réponse, `--insecure` doit rester
un choix explicite et visible.
:::

---

**E23.16** — *Projet minimal installable.*

```text
monoutil/
  pyproject.toml            # copie de pyproject.example.toml, name=monoutil
  src/monoutil/__init__.py  # vide
  src/monoutil/cli.py
  tests/test_cli.py
```

```python
# src/monoutil/cli.py
import sys

def bonjour(nom: str = "monde") -> str:
    return f"bonjour {nom}"

def main() -> int:
    print(bonjour(*sys.argv[1:2]))
    return 0
```

```python
# tests/test_cli.py
from monoutil.cli import bonjour

def test_bonjour():
    assert bonjour("ops") == "bonjour ops"
```

```bash
cd ~/lab23/monoutil && pip install -e . && cd / && monoutil ops
cd ~/lab23/monoutil && ruff check . && ruff format --check . && pytest -q
```

::: pourquoi
La disposition `src/` empêche d'importer le paquet par accident depuis le
répertoire courant : les tests s'exécutent contre la version **installée**,
comme en production. `pip install -e .` (éditable) pose un lien vers `src/`
dans le venv : on modifie le code sans réinstaller. `[project.scripts]`
crée `venv/bin/monoutil`. C'est le squelette de D23, en miniature.
:::

---

## 23.6 Labs

### **L23.1** — `logstats.py`

*Analyse d'un access.log nginx : top IP, codes, latences, en flux.*

**`~/lab23/bin/logstats.py`**

```python
#!/usr/bin/env python3
"""logstats.py — statistiques d'un access.log nginx (combined + temps).

Lit le journal ligne par ligne (fichier, .gz ou stdin), sans le charger en
mémoire, et produit : top des IP, répartition des codes HTTP, latences
(moyenne, p50, p95, p99, max) et top des URL en erreur 5xx.

Usage : logstats.py [--top N] [--json] [--since ISO] FICHIER|-
Codes de sortie : 0 ok, 1 fichier illisible, 2 usage, 3 aucune ligne valide.
"""

from __future__ import annotations

import argparse
import gzip
import json
import logging
import math
import re
import sys
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import IO

log = logging.getLogger("logstats")

# combined + " $request_time" : on ne capture que ce qu'on exploite.
LIGNE = re.compile(
    r"^(?P<ip>\S+) \S+ \S+ \[(?P<date>[^\]]+)\] "
    r'"(?P<methode>[A-Z]+) (?P<url>\S+) [^"]*" '
    r'(?P<code>\d{3}) (?P<octets>\d+|-) "[^"]*" "[^"]*" '
    r"(?P<duree>\d+\.\d+)$"
)
FORMAT_DATE = "%d/%b/%Y:%H:%M:%S %z"


@dataclass
class Stats:
    """Accumulateur : on ne garde que les compteurs et la liste des durées."""

    lignes: int = 0
    rejetees: int = 0
    ips: Counter = field(default_factory=Counter)
    codes: Counter = field(default_factory=Counter)
    urls_5xx: Counter = field(default_factory=Counter)
    durees: list[float] = field(default_factory=list)

    def ajouter(self, m: re.Match) -> None:
        self.lignes += 1
        self.ips[m["ip"]] += 1
        code = m["code"]
        self.codes[code] += 1
        if code.startswith("5"):
            self.urls_5xx[m["url"]] += 1
        self.durees.append(float(m["duree"]))


def ouvrir(chemin: str) -> IO[str]:
    """Rend un flux texte : stdin pour '-', gzip transparent pour '.gz'."""
    if chemin == "-":
        return sys.stdin
    p = Path(chemin)
    if p.suffix == ".gz":
        return gzip.open(p, "rt", encoding="utf-8", errors="replace")
    return p.open(encoding="utf-8", errors="replace")


def analyser(flux: IO[str], depuis: datetime | None = None) -> Stats:
    """Consomme le flux ligne à ligne : un log de 10 Go tient en RAM."""
    st = Stats()
    for ligne in flux:
        m = LIGNE.match(ligne.rstrip("\n"))
        if m is None:
            st.rejetees += 1
            log.debug("ligne rejetée : %s", ligne[:80])
            continue
        if depuis is not None:
            quand = datetime.strptime(m["date"], FORMAT_DATE)
            if quand < depuis:
                continue
        st.ajouter(m)
    st.durees.sort()
    return st


def percentile(valeurs: list[float], p: float) -> float:
    """Rang le plus proche (nearest-rank) sur une liste TRIÉE."""
    if not valeurs:
        return 0.0
    k = max(1, math.ceil(p / 100 * len(valeurs)))
    return valeurs[k - 1]


def resume(st: Stats, top: int) -> dict:
    d = st.durees
    return {
        "lignes": st.lignes,
        "rejetees": st.rejetees,
        "top_ip": st.ips.most_common(top),
        "codes": dict(sorted(st.codes.items())),
        "latence": {
            "moyenne": round(sum(d) / len(d), 3) if d else 0.0,
            "p50": percentile(d, 50),
            "p95": percentile(d, 95),
            "p99": percentile(d, 99),
            "max": d[-1] if d else 0.0,
        },
        "top_5xx": st.urls_5xx.most_common(top),
    }


def afficher(r: dict) -> None:
    print(f"lignes : {r['lignes']}  (rejetées : {r['rejetees']})")
    print("\n== Top IP ==")
    for ip, n in r["top_ip"]:
        print(f"{n:>7}  {ip}")
    print("\n== Codes HTTP ==")
    for code, n in r["codes"].items():
        pct = 100 * n / r["lignes"]
        print(f"{code}  {n:>7}  {pct:5.1f} %")
    lat = r["latence"]
    print("\n== Latence (s) ==")
    print(
        f"moyenne {lat['moyenne']:.3f}  p50 {lat['p50']:.3f}  "
        f"p95 {lat['p95']:.3f}  p99 {lat['p99']:.3f}  max {lat['max']:.3f}"
    )
    if r["top_5xx"]:
        print("\n== URL en 5xx ==")
        for url, n in r["top_5xx"]:
            print(f"{n:>7}  {url}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Statistiques d'un access.log nginx.",
        epilog="Codes de sortie : 0 ok, 1 fichier illisible, 3 aucune ligne.",
    )
    p.add_argument("fichier", help="access.log, .gz, ou - pour stdin")
    p.add_argument("--top", type=int, default=10, help="taille des tops")
    p.add_argument("--json", action="store_true", help="sortie JSON")
    p.add_argument(
        "--since", metavar="ISO", help="ignorer avant cette date (ISO 8601)"
    )
    p.add_argument("-v", "--verbose", action="store_true")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
        stream=sys.stderr,
    )
    depuis = None
    if args.since:
        depuis = datetime.fromisoformat(args.since)
        if depuis.tzinfo is None:
            depuis = depuis.astimezone()  # heure locale du serveur
    try:
        with ouvrir(args.fichier) as flux:
            st = analyser(flux, depuis)
    except OSError as exc:
        log.error("impossible de lire %s : %s", args.fichier, exc)
        return 1
    if st.lignes == 0:
        log.error("aucune ligne valide dans %s", args.fichier)
        return 3
    r = resume(st, args.top)
    if args.json:
        json.dump(r, sys.stdout, indent=2)
        print()
    else:
        afficher(r)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

**`~/lab23/tests/test_logstats.py`**

```python
"""Tests de logstats.py."""

import io

import pytest

import logstats

LIGNE = (
    '198.51.100.12 - - [18/Sep/2026:14:02:11 +0200] "GET /api/v1/x HTTP/1.1"'
    ' {code} 512 "-" "curl/8.5.0" {duree}\n'
)


def flux(*couples):
    return io.StringIO(
        "".join(LIGNE.format(code=c, duree=d) for c, d in couples)
    )


def test_percentile_nearest_rank():
    assert logstats.percentile([0.1, 0.2, 0.3, 0.4], 50) == 0.2
    assert logstats.percentile([0.1, 0.2, 0.3, 0.4], 95) == 0.4
    assert logstats.percentile([], 95) == 0.0


def test_analyser_compte_et_trie():
    st = logstats.analyser(
        flux((200, "0.010"), (500, "1.500"), (200, "0.020"))
    )
    assert st.lignes == 3 and st.rejetees == 0
    assert st.codes == {"200": 2, "500": 1}
    assert st.durees == [0.010, 0.020, 1.500]
    assert st.urls_5xx == {"/api/v1/x": 1}


def test_analyser_rejette_sans_planter():
    st = logstats.analyser(
        io.StringIO("n'importe quoi\n" + LIGNE.format(code=200, duree="0.1"))
    )
    assert (st.lignes, st.rejetees) == (1, 1)


def test_ouvrir_gz(tmp_path):
    import gzip

    p = tmp_path / "a.log.gz"
    with gzip.open(p, "wt") as f:
        f.write(LIGNE.format(code=200, duree="0.3"))
    with logstats.ouvrir(str(p)) as f:
        assert logstats.analyser(f).lignes == 1


@pytest.mark.parametrize("chemin, code", [("/nexiste/pas", 1)])
def test_main_erreurs(chemin, code):
    assert logstats.main([chemin]) == code


def test_main_fichier_vide(tmp_path):
    p = tmp_path / "vide.log"
    p.write_text("")
    assert logstats.main([str(p)]) == 3
```

**Comparaison avec `bin/logstats.awk`** (`rapports/logstats-comparaison.md`)

```console
$ time bin/logstats.awk data/gros.log > /dev/null
real    0m1.9s
$ time bin/logstats.py data/gros.log > /dev/null
real    0m2.6s
$ /usr/bin/time -v bin/logstats.py data/gros.log 2>&1 | grep Maximum
        Maximum resident set size (kbytes): 38000
```

Trois observations : (1) sur 216 000 lignes, awk + sort reste un peu plus
rapide — `sort` est du C optimisé, la regex Python coûte ~10 µs par ligne ;
(2) Python calcule **tous** les indicateurs en une seule passe là où le
pipeline relit le fichier trois fois, et l'écart se réduit quand on ajoute
un indicateur ; (3) le p95 par URL, la sortie JSON et `--since` sont dix
lignes en Python, une réécriture du pipeline en awk. La mémoire reste
constante dans les deux cas : c'est le point qu'il fallait vérifier.

::: pourquoi
**La regex compilée avec des groupes nommés** remplace le comptage de
colonnes d'awk (`$1`, `$9`, `$NF`) par des noms : `m["code"]`. Elle est
aussi le **validateur** — une ligne qui ne matche pas est comptée, pas
plantée, ce qu'aucun `awk '{print $9}'` ne fait.

**La lecture en flux** : `for ligne in flux` fonctionne à l'identique sur
un fichier ouvert en texte, un `gzip.open(..., "rt")` et `sys.stdin`. La
fonction `analyser()` ne sait pas d'où viennent les lignes : c'est ce qui
la rend testable avec un `io.StringIO`.

**Le percentile nearest-rank** : on trie une seule fois, à la fin, puis
l'index `ceil(p/100 × n) − 1` donne la valeur. Sur 7 200 lignes, l'index 95
est 6 840, donc `durees[6839]` = 0,537 — la même valeur que le
`int(NR*0.95)` d'awk sur une liste 1-indexée. Le tri est O(n log n) mais ne
se fait qu'une fois ; un `heapq` ou un histogramme seraient nécessaires
au-delà de quelques dizaines de millions de lignes.

**L'accumulateur `dataclass`** avec `Counter` : `most_common(n)` est le
`sort | uniq -c | sort -rn | head` ; `field(default_factory=Counter)` évite
le piège du mutable partagé entre instances.

**`resume()` rend un dict** : le texte et le JSON sont deux rendus de la
même donnée. C'est le découpage qui permet `--json` sans dupliquer la
logique, et le test sur le dict sans parser une sortie texte.
:::

::: piege
`--since` compare un `datetime` aware (celui de la ligne, `%z`) à celui
passé par l'utilisateur ; s'il est naïf, `astimezone()` sans argument le
place dans le fuseau du serveur. Sans cela : `TypeError` à la première
ligne. Autre piège : `errors="replace"` sur un journal — sans lui, un seul
octet invalide dans 45 Mo arrête l'analyse.
:::

---

### **L23.2** — `inventaire.py`

*Inventaire Ansible généré depuis l'API Proxmox, avec mode fixture.*

**`~/lab23/bin/inventaire.py`**

```python
#!/usr/bin/env python3
"""inventaire.py — inventaire Ansible généré depuis l'API Proxmox.

Deux sources :
  --fixture FICHIER.json   réponses figées de l'API (travail hors ligne)
  --url https://10.10.10.1:8006 + variable PVE_TOKEN (user@realm!id=uuid)

Règles : seules les VM qemu sont prises ; les templates sont ignorés ; les
VM arrêtées sont ignorées sauf --all ; un groupe par tag Proxmox ; l'adresse
vient de ipconfig0 (cloud-init), à défaut de la résolution DNS de
<nom>.lab.local, à défaut la VM est signalée et omise.

Codes de sortie : 0 ok, 1 erreur API/fichier, 2 usage, 4 aucune VM.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import logging
import os
import socket
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Protocol

log = logging.getLogger("inventaire")


# --- modèle ----------------------------------------------------------------
@dataclass(frozen=True)
class Machine:
    nom: str
    vmid: int
    node: str
    statut: str
    adresse: str | None
    tags: tuple[str, ...] = field(default_factory=tuple)


# --- sources : même interface, deux implémentations -----------------------
class Source(Protocol):
    def ressources(self) -> list[dict[str, Any]]: ...

    def config(self, node: str, vmid: int) -> dict[str, Any]: ...


class Fixture:
    """Lit un JSON qui imite les deux appels API."""

    def __init__(self, chemin: Path) -> None:
        with chemin.open(encoding="utf-8") as f:
            self.data = json.load(f)

    def ressources(self) -> list[dict[str, Any]]:
        return self.data["resources"]

    def config(self, node: str, vmid: int) -> dict[str, Any]:
        return self.data["configs"].get(str(vmid), {})


class ApiProxmox:
    """Appels REST authentifiés par token (Authorization: PVEAPIToken=...)."""

    def __init__(self, url: str, token: str, verify: bool | str) -> None:
        import requests  # import tardif : le mode --fixture n'en a pas besoin

        self.base = url.rstrip("/") + "/api2/json"
        self.s = requests.Session()
        self.s.headers["Authorization"] = f"PVEAPIToken={token}"
        self.s.verify = verify

    def _get(self, chemin: str, **params: Any) -> Any:
        r = self.s.get(self.base + chemin, params=params, timeout=(3.05, 15))
        r.raise_for_status()  # 401/403/5xx -> exception, jamais un faux vide
        return r.json()["data"]

    def ressources(self) -> list[dict[str, Any]]:
        return self._get("/cluster/resources", type="vm")

    def config(self, node: str, vmid: int) -> dict[str, Any]:
        return self._get(f"/nodes/{node}/qemu/{vmid}/config")


# --- logique métier (pure : testable sans réseau) --------------------------
def adresse_depuis_ipconfig(ipconfig: str | None) -> str | None:
    """'ip=10.10.10.11/24,gw=10.10.10.1' -> '10.10.10.11' ; dhcp -> None."""
    if not ipconfig:
        return None
    for champ in ipconfig.split(","):
        cle, _, val = champ.partition("=")
        if cle == "ip" and val != "dhcp":
            try:
                return str(ipaddress.ip_interface(val).ip)
            except ValueError:
                log.warning("ipconfig0 illisible : %r", val)
    return None


def resoudre(nom: str, domaine: str) -> str | None:
    try:
        return socket.gethostbyname(f"{nom}.{domaine}")
    except OSError:
        return None


def collecter(
    src: Source, inclure_arretees: bool, domaine: str
) -> list[Machine]:
    machines: list[Machine] = []
    for r in src.ressources():
        if r.get("type") != "qemu" or r.get("template"):
            continue
        if r.get("status") != "running" and not inclure_arretees:
            continue
        conf = src.config(r["node"], r["vmid"])
        adresse = adresse_depuis_ipconfig(conf.get("ipconfig0"))
        if adresse is None:
            adresse = resoudre(r["name"], domaine)
        tags = tuple(t for t in (r.get("tags") or "").split(";") if t)
        if adresse is None:
            log.warning(
                "%s (vmid %s) : aucune adresse, omise", r["name"], r["vmid"]
            )
            continue
        machines.append(
            Machine(
                r["name"], r["vmid"], r["node"], r["status"], adresse, tags
            )
        )
    return sorted(machines, key=lambda m: m.nom)


def par_groupe(machines: list[Machine]) -> dict[str, list[Machine]]:
    groupes: dict[str, list[Machine]] = {}
    for m in machines:
        for t in m.tags or ("sans_tag",):
            groupes.setdefault(t, []).append(m)
    return dict(sorted(groupes.items()))


def rendre_ini(machines: list[Machine]) -> str:
    lignes = ["[all]"]
    lignes += [
        f"{m.nom} ansible_host={m.adresse} vmid={m.vmid}" for m in machines
    ]
    for groupe, membres in par_groupe(machines).items():
        lignes += ["", f"[{groupe}]"] + [m.nom for m in membres]
    return "\n".join(lignes) + "\n"


def rendre_yaml(machines: list[Machine]) -> str:
    import yaml  # PyYAML : pip install PyYAML

    doc = {
        "all": {
            "hosts": {
                m.nom: {
                    "ansible_host": m.adresse,
                    "vmid": m.vmid,
                    "proxmox_node": m.node,
                }
                for m in machines
            },
            "children": {
                g: {"hosts": {m.nom: None for m in membres}}
                for g, membres in par_groupe(machines).items()
            },
        }
    }
    return yaml.safe_dump(doc, sort_keys=False, allow_unicode=True)


# --- interface ---------------------------------------------------------------
def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--fixture", type=Path, help="JSON de réponses API")
    src.add_argument("--url", help="ex. https://10.10.10.1:8006")
    p.add_argument("--format", choices=("ini", "yaml"), default="ini")
    p.add_argument(
        "--all", action="store_true", help="inclure les VM arrêtées"
    )
    p.add_argument("--domaine", default="lab.local")
    p.add_argument("--ca", help="chemin du CA à faire confiance")
    p.add_argument(
        "--insecure",
        action="store_true",
        help="ne pas vérifier le certificat (lab uniquement)",
    )
    p.add_argument("-o", "--output", type=Path, help="fichier de sortie")
    p.add_argument("-v", "--verbose", action="store_true")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
        stream=sys.stderr,
    )
    try:
        if args.fixture:
            src: Source = Fixture(args.fixture)
        else:
            token = os.environ.get("PVE_TOKEN")
            if not token:
                log.error("PVE_TOKEN absent (user@realm!id=uuid)")
                return 2
            verify: bool | str = args.ca if args.ca else not args.insecure
            src = ApiProxmox(args.url, token, verify)
        machines = collecter(src, args.all, args.domaine)
    except (OSError, ValueError, KeyError) as exc:
        # requests.RequestException hérite d'OSError : réseau, HTTP 4xx/5xx,
        # fichier absent et JSON invalide finissent tous ici, sans traceback.
        log.error("source injoignable ou illisible : %s", exc)
        return 1
    if not machines:
        log.error("aucune VM retenue")
        return 4
    texte = (
        rendre_yaml(machines)
        if args.format == "yaml"
        else rendre_ini(machines)
    )
    if args.output:
        args.output.write_text(texte, encoding="utf-8")
        log.info("%d hôtes écrits dans %s", len(machines), args.output)
    else:
        sys.stdout.write(texte)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

```console
$ bin/inventaire.py --fixture fixtures/proxmox-qemu.json | head -8
WARNING: lab-sandbox (vmid 9120) : aucune adresse, omise
[all]
lab-adm ansible_host=10.10.10.10 vmid=9001
lab-db ansible_host=10.10.10.12 vmid=9003
lab-ops ansible_host=10.10.10.14 vmid=9005
lab-rhel ansible_host=10.10.10.13 vmid=9004
lab-web ansible_host=10.10.10.11 vmid=9002

$ bin/inventaire.py --fixture fixtures/proxmox-qemu.json -o inv.ini
$ ansible-inventory -i inv.ini --graph | head -6
@all:
  |--@ungrouped:
  |--@adm:
  |  |--lab-adm
  |--@db:
  |  |--lab-db
```

::: pourquoi
**Une interface, deux sources.** `Source` est un `Protocol` : toute classe
qui fournit `ressources()` et `config()` convient, sans héritage. `Fixture`
lit un JSON, `ApiProxmox` fait les appels HTTP. La logique (`collecter`)
ne connaît que l'interface : on la teste avec la fixture, et le jour où
l'API change, seule `ApiProxmox` bouge. C'est le principe de l'injection
de dépendance, sans framework.

**`raise_for_status()` avant `.json()["data"]`** : un token expiré renvoie
un 401 avec `{"data": null}` ; sans l'appel, `None` déclencherait un
`TypeError` plus loin, ou pire, un inventaire vide accepté. Avec lui, on
obtient `HTTPError`, qui hérite de `RequestException`, qui hérite
d'`OSError` : une seule clause `except OSError` en bout de chaîne couvre le
fichier absent, le JSON invalide (`ValueError`), la connexion refusée et
l'erreur HTTP, chacun avec son message et sans Traceback.

**`ipaddress.ip_interface("10.10.10.11/24").ip`** parse et valide en une
fois : une valeur `10.10.10.300/24` lève `ValueError`, qu'on journalise. Le
`str.partition("=")` sur chaque champ de `ipconfig0` évite une regex.

**Les tags Proxmox** sont séparés par `;` et peuvent être absents
(`r.get("tags") or ""`) : un `split` sur `None` planterait. Le `tuple` de
tags garde l'objet `Machine` hachable (`frozen=True`).

**Les imports tardifs** de `requests` et `yaml` dans les fonctions qui les
utilisent permettent au mode `--fixture --format ini` de tourner sans
aucune dépendance : utile sur une machine sans venv, et rend explicite ce
qui dépend de quoi.
:::

::: piege
`yaml.safe_dump` avec `sort_keys=False` conserve l'ordre d'insertion ; par
défaut il trie les clés, et `ansible_host` passe après `vmid` — inoffensif
pour Ansible, déroutant en relecture. Et `yaml.dump` sans `safe_` écrirait
des tags `!!python/object` pour tout objet non natif : `safe_` dans les
deux sens, toujours.
:::

---

### **L23.3** — `sante.py`

*Sonde multi-services, JSON, code Nagios, écriture atomique, timer.*

**`~/lab23/bin/sante.py`**

```python
#!/usr/bin/env python3
"""sante.py — santé multi-services : rapport JSON, code de sortie Nagios.

Types de vérification (fichier YAML, clé `verifications`) :
  tcp      hote, port                      le port accepte une connexion
  http     url, [attendu=200], [contient]  code HTTP attendu (+ texte)
  tls      hote, port, [jours_min=14]      certificat valide, non expirant
  disque   chemin, [pct_max=90]            usage du système de fichiers
  commande argv (liste), [timeout]         code de retour 0

Codes de sortie (convention Nagios) : 0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN.
stdout : le rapport (JSON, ou texte avec --text). stderr : le journal.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

log = logging.getLogger("sante")

OK, WARNING, CRITICAL, UNKNOWN = 0, 1, 2, 3
LIBELLE = {
    OK: "OK",
    WARNING: "WARNING",
    CRITICAL: "CRITICAL",
    UNKNOWN: "UNKNOWN",
}


@dataclass
class Resultat:
    nom: str
    type: str
    code: int
    detail: str
    duree_ms: int = 0

    @property
    def statut(self) -> str:
        return LIBELLE[self.code]


# --- une fonction par type : (spec, timeout) -> (code, détail) -------------
def verif_tcp(spec: dict[str, Any], timeout: float) -> tuple[int, str]:
    hote, port = spec["hote"], int(spec["port"])
    try:
        with socket.create_connection((hote, port), timeout=timeout):
            return OK, f"{hote}:{port} accepte les connexions"
    except OSError as exc:  # refus, timeout, DNS : tous des OSError
        return CRITICAL, f"{hote}:{port} injoignable ({exc})"


def verif_http(spec: dict[str, Any], timeout: float) -> tuple[int, str]:
    url, attendu = spec["url"], int(spec.get("attendu", 200))
    req = urllib.request.Request(url, headers={"User-Agent": "sante.py"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as rep:
            code = rep.status
            corps = rep.read(65536).decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:  # réponse reçue, code >= 400
        code, corps = exc.code, ""
    except (urllib.error.URLError, OSError, ValueError) as exc:
        return CRITICAL, f"{url} : {exc}"
    if code != attendu:
        return CRITICAL, f"{url} : code {code}, attendu {attendu}"
    if (motif := spec.get("contient")) and motif not in corps:
        return WARNING, f"{url} : {code} mais sans {motif!r}"
    return OK, f"{url} : {code}"


def verif_tls(spec: dict[str, Any], timeout: float) -> tuple[int, str]:
    hote, port = spec["hote"], int(spec.get("port", 443))
    jours_min = int(spec.get("jours_min", 14))
    ctx = ssl.create_default_context()
    if spec.get("ca"):
        ctx.load_verify_locations(spec["ca"])
    try:
        with (
            socket.create_connection((hote, port), timeout=timeout) as s,
            ctx.wrap_socket(s, server_hostname=hote) as tls,
        ):
            cert = tls.getpeercert()
    except ssl.SSLCertVerificationError as exc:
        return CRITICAL, f"{hote}:{port} certificat refusé : {exc.reason}"
    except OSError as exc:
        return CRITICAL, f"{hote}:{port} injoignable ({exc})"
    if not cert or "notAfter" not in cert:
        return UNKNOWN, f"{hote}:{port} certificat sans date d'expiration"
    fin = ssl.cert_time_to_seconds(str(cert["notAfter"]))
    restant = (fin - time.time()) / 86400
    if restant < 0:
        return CRITICAL, f"{hote}:{port} certificat expiré"
    if restant < jours_min:
        return WARNING, f"{hote}:{port} expire dans {restant:.0f} j"
    return OK, f"{hote}:{port} expire dans {restant:.0f} j"


def verif_disque(spec: dict[str, Any], timeout: float) -> tuple[int, str]:
    chemin, pct_max = spec["chemin"], float(spec.get("pct_max", 90))
    try:
        u = shutil.disk_usage(chemin)
    except OSError as exc:
        return UNKNOWN, f"{chemin} : {exc}"
    pct = 100 * u.used / u.total
    detail = f"{chemin} utilisé à {pct:.1f} % ({u.free // 2**20} Mo libres)"
    if pct >= pct_max:
        return CRITICAL, detail
    if pct >= pct_max - 10:
        return WARNING, detail
    return OK, detail


def verif_commande(spec: dict[str, Any], timeout: float) -> tuple[int, str]:
    argv = spec["argv"]
    if isinstance(argv, str) or not all(isinstance(a, str) for a in argv):
        # une chaîne = un seul mot, pas un shell ; et YAML lit `true`
        # comme un booléen : on exige une liste de chaînes, rien d'autre.
        return UNKNOWN, "argv doit être une liste de chaînes"
    try:
        p = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=spec.get("timeout", timeout),
        )
    except FileNotFoundError:
        return UNKNOWN, f"{argv[0]} introuvable"
    except subprocess.TimeoutExpired:
        return CRITICAL, f"{argv[0]} : délai dépassé"
    sortie = (p.stdout or p.stderr).strip().splitlines()
    premiere = sortie[0] if sortie else ""
    if p.returncode != 0:
        return CRITICAL, f"{' '.join(argv)} -> {p.returncode} {premiere}"
    return OK, f"{' '.join(argv)} -> 0 {premiere}"


VERIFS: dict[str, Callable[[dict[str, Any], float], tuple[int, str]]] = {
    "tcp": verif_tcp,
    "http": verif_http,
    "tls": verif_tls,
    "disque": verif_disque,
    "commande": verif_commande,
}


# --- orchestration ---------------------------------------------------------
def executer(spec: dict[str, Any], timeout: float) -> Resultat:
    nom, type_ = spec.get("nom", "?"), spec.get("type", "?")
    debut = time.monotonic()
    fonction = VERIFS.get(type_)
    if fonction is None:
        code, detail = UNKNOWN, f"type inconnu : {type_}"
    else:
        try:
            code, detail = fonction(spec, timeout)
        except KeyError as exc:  # clé manquante dans le YAML
            code, detail = UNKNOWN, f"paramètre manquant : {exc}"
    duree = int((time.monotonic() - debut) * 1000)
    log.info("%-8s %-24s %s (%d ms)", LIBELLE[code], nom, detail, duree)
    return Resultat(nom, type_, code, detail, duree)


def charger_config(chemin: Path) -> dict[str, Any]:
    import yaml

    with chemin.open(encoding="utf-8") as f:
        conf = yaml.safe_load(f) or {}
    if not isinstance(conf.get("verifications"), list):
        raise ValueError("clé 'verifications' absente ou invalide")
    return conf


def rapport(resultats: list[Resultat]) -> dict[str, Any]:
    pire = max((r.code for r in resultats), default=UNKNOWN)
    return {
        "horodatage": datetime.now(UTC).isoformat(timespec="seconds"),
        "hote": socket.gethostname(),
        "statut": LIBELLE[pire],
        "code": pire,
        "nb": {
            lib: sum(1 for r in resultats if r.code == c)
            for c, lib in LIBELLE.items()
        },
        "verifications": [asdict(r) | {"statut": r.statut} for r in resultats],
    }


def ecrire_atomique(chemin: Path, texte: str) -> None:
    """Écrit dans un temporaire du MÊME répertoire, puis rename atomique."""
    fd, tmp = tempfile.mkstemp(dir=chemin.parent, prefix=".sante-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(texte)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o644)
        os.replace(tmp, chemin)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def rendre_texte(rap: dict[str, Any]) -> str:
    lignes = [f"{rap['statut']} — {rap['hote']} — {rap['horodatage']}"]
    lignes += [
        f"  [{v['statut']:8}] {v['nom']}: {v['detail']}"
        for v in rap["verifications"]
    ]
    return "\n".join(lignes) + "\n"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument(
        "-c", "--config", type=Path, default=Path("/etc/factura/sante.yaml")
    )
    p.add_argument("--only", metavar="NOM", help="une seule vérification")
    p.add_argument("--timeout", type=float, default=3.0)
    p.add_argument("--text", action="store_true", help="sortie lisible")
    p.add_argument(
        "-o", "--output", type=Path, help="écrire le JSON ici (atomiquement)"
    )
    p.add_argument("-v", "--verbose", action="store_true")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stderr,
    )
    try:
        conf = charger_config(args.config)
    except (OSError, ValueError) as exc:
        log.error("configuration %s : %s", args.config, exc)
        print(
            json.dumps(
                {"statut": "UNKNOWN", "code": UNKNOWN, "detail": str(exc)}
            )
        )
        return UNKNOWN
    specs = conf["verifications"]
    if args.only:
        specs = [s for s in specs if s.get("nom") == args.only]
    timeout = float(conf.get("timeout", args.timeout))
    resultats = [executer(s, timeout) for s in specs]
    rap = rapport(resultats)
    texte = json.dumps(rap, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        ecrire_atomique(args.output, texte)
    sys.stdout.write(rendre_texte(rap) if args.text else texte)
    return rap["code"]


if __name__ == "__main__":
    sys.exit(main())
```

**`~/lab23/tests/test_sante.py`**

```python
"""Tests de sante.py : aucun réseau, tout est simulé avec monkeypatch."""

import socket
import subprocess
from collections import namedtuple

import sante

Usage = namedtuple("Usage", "total used free")


def test_tcp_ok(monkeypatch):
    class FauxSocket:
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

    monkeypatch.setattr(
        socket, "create_connection", lambda *a, **k: FauxSocket()
    )
    code, _ = sante.verif_tcp({"hote": "lab-web", "port": 22}, 1.0)
    assert code == sante.OK


def test_tcp_refuse(monkeypatch):
    def refuse(*a, **k):
        raise ConnectionRefusedError(111, "Connection refused")

    monkeypatch.setattr(socket, "create_connection", refuse)
    code, detail = sante.verif_tcp({"hote": "lab-web", "port": 22}, 1.0)
    assert code == sante.CRITICAL and "22" in detail


def test_disque_seuils(monkeypatch):
    monkeypatch.setattr(
        sante.shutil, "disk_usage", lambda p: Usage(100, 95, 5)
    )
    assert sante.verif_disque({"chemin": "/"}, 1.0)[0] == sante.CRITICAL
    monkeypatch.setattr(
        sante.shutil, "disk_usage", lambda p: Usage(100, 85, 15)
    )
    assert sante.verif_disque({"chemin": "/"}, 1.0)[0] == sante.WARNING
    monkeypatch.setattr(
        sante.shutil, "disk_usage", lambda p: Usage(100, 10, 90)
    )
    assert sante.verif_disque({"chemin": "/"}, 1.0)[0] == sante.OK


def test_commande_simulee(monkeypatch):
    appels = []

    def faux_run(argv, **kw):
        appels.append((argv, kw))
        return subprocess.CompletedProcess(argv, 3, "", "inactive\n")

    monkeypatch.setattr(subprocess, "run", faux_run)
    code, detail = sante.verif_commande(
        {"argv": ["systemctl", "is-active", "nginx"]}, 2.0
    )
    assert code == sante.CRITICAL and "inactive" in detail
    assert appels[0][0] == ["systemctl", "is-active", "nginx"]
    assert appels[0][1]["timeout"] == 2.0 and "shell" not in appels[0][1]


def test_commande_refuse_une_chaine():
    code, _ = sante.verif_commande({"argv": "rm -rf /"}, 1.0)
    assert code == sante.UNKNOWN


def test_executer_type_inconnu_et_cle_manquante():
    assert sante.executer({"nom": "x", "type": "zzz"}, 1).code == sante.UNKNOWN
    r = sante.executer({"nom": "x", "type": "tcp", "hote": "h"}, 1)
    assert r.code == sante.UNKNOWN and "port" in r.detail


def test_rapport_prend_le_pire():
    rs = [
        sante.Resultat("a", "tcp", sante.OK, ""),
        sante.Resultat("b", "tcp", sante.WARNING, ""),
    ]
    assert sante.rapport(rs)["statut"] == "WARNING"
    assert sante.rapport([])["code"] == sante.UNKNOWN


def test_ecrire_atomique(tmp_path):
    cible = tmp_path / "sante.json"
    sante.ecrire_atomique(cible, "{}\n")
    assert cible.read_text() == "{}\n"
    assert [p.name for p in tmp_path.iterdir()] == ["sante.json"]


def test_main_config_absente(tmp_path, capsys):
    assert sante.main(["-c", str(tmp_path / "nope.yaml")]) == sante.UNKNOWN
    assert '"UNKNOWN"' in capsys.readouterr().out
```

**Déploiement**

```bash
sudo mkdir -p /etc/factura /var/lib/factura
sudo cp ~/lab23/conf/sante.yaml /etc/factura/sante.yaml
sudo tee /etc/systemd/system/sante.service > /dev/null <<'EOF'
[Unit]
Description=Sonde de santé multi-services (sante.py)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/home/mathieu/lab23/venv/bin/python \
  /home/mathieu/lab23/bin/sante.py -c /etc/factura/sante.yaml \
  -o /var/lib/factura/sante.json
Environment=PYTHONUNBUFFERED=1 LANG=C.UTF-8
StandardOutput=null
StandardError=journal
SyslogIdentifier=sante
SuccessExitStatus=1 2 3
EOF
sudo tee /etc/systemd/system/sante.timer > /dev/null <<'EOF'
[Unit]
Description=Sonde de santé toutes les 5 minutes

[Timer]
OnCalendar=*:0/5
RandomizedDelaySec=30
Persistent=true

[Install]
WantedBy=timers.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now sante.timer
sudo systemctl start sante.service
jq '.statut, .nb' /var/lib/factura/sante.json
journalctl -t sante -n 5
```

::: pourquoi
**Une fonction par type, un dict de dispatch.** `VERIFS[type_]` remplace
une chaîne de `if type == "tcp" elif ...` ; ajouter un type, c'est écrire
une fonction et une entrée. Chaque fonction a la même signature
`(spec, timeout) -> (code, détail)` et ne lève jamais : elle **rend** un
code. `executer()` enveloppe l'appel, chronomètre, et convertit un
`KeyError` (paramètre manquant dans le YAML) en `UNKNOWN`. Un type inconnu
donne aussi `UNKNOWN` : la sonde ne plante pas parce qu'un collègue a fait
une faute de frappe dans la configuration.

**Le pire code gagne.** `max(r.code for r in resultats)` est exactement la
convention Nagios : OK < WARNING < CRITICAL < UNKNOWN. Un `--only` qui ne
matche rien donne une liste vide, donc `UNKNOWN` — pas un faux OK.

**`urllib.error.HTTPError` avant `URLError`** : la première hérite de la
seconde. Un 503 est une réponse (on lit `exc.code`), une connexion refusée
n'en est pas une.

**TLS** : `ssl.create_default_context()` vérifie la chaîne et le nom
(`server_hostname=`) ; `getpeercert()` ne rend le dictionnaire que si la
vérification a réussi. `cert_time_to_seconds` convertit le `notAfter`
(`Sep 18 12:00:00 2027 GMT`) en timestamp ; on le compare à `time.time()`.

**`subprocess.run` en liste, avec `timeout`** — et le refus explicite d'une
chaîne ou d'une liste contenant autre chose que des chaînes : YAML lit
`[true]` comme `[True]` et `subprocess` lèverait un `TypeError` obscur.

**`ecrire_atomique`** : `mkstemp` dans le répertoire de la cible, `fsync`,
`chmod 644` (car `mkstemp` crée en 600), `os.replace`. Le `except
BaseException` qui supprime le temporaire couvre aussi `KeyboardInterrupt`
— c'est l'un des rares usages légitimes de `BaseException`.

**Le timer** : `SuccessExitStatus=1 2 3`, sinon chaque WARNING met l'unité
en `failed` et déclenche les alertes systemd pour rien ; `StandardOutput=
null` parce que le JSON va dans le fichier ; `-o` plutôt qu'une redirection
shell, qui ne serait pas atomique.
:::

::: piege
Le test `test_commande_simulee` vérifie que `subprocess.run` reçoit une
**liste** et un **timeout** et pas de `shell` : c'est un test de contrat,
pas de résultat. Si quelqu'un « simplifie » en `shell=True`, le test casse
avant la revue. Et `caplog`, pas `capsys`, pour lire les messages de
`logging` sous pytest.
:::

---

### **L23.4** — `rotate_backups.py`

*Rétention GFS pure et testée, avec `--dry-run`.*

**`~/lab23/rotate/rotate_backups.py`**

```python
#!/usr/bin/env python3
"""rotate_backups.py — rétention GFS (grand-père, père, fils) d'archives.

Les archives se nomment <prefixe>-AAAA-MM-JJ.<ext>. La date est lue dans le
NOM, jamais dans le mtime (une copie ou une restauration le modifie).

Politique par défaut : garder les 7 dernières quotidiennes, la dernière
archive de chacune des 4 dernières semaines ISO, la première archive de
chacun des 6 derniers mois. Tout le reste est supprimé — sauf en --dry-run.

Codes de sortie : 0 ok, 1 répertoire illisible, 2 usage.
"""

from __future__ import annotations

import argparse
import json
import logging
import re
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path

log = logging.getLogger("rotate")


@dataclass(frozen=True)
class Politique:
    quotidiennes: int = 7
    hebdomadaires: int = 4
    mensuelles: int = 6


@dataclass(frozen=True)
class Archive:
    chemin: Path
    quand: date


def motif(prefixe: str) -> re.Pattern[str]:
    return re.compile(
        rf"^{re.escape(prefixe)}-(\d{{4}})-(\d{{2}})-(\d{{2}})\.[\w.]+$"
    )


def inventorier(rep: Path, prefixe: str) -> list[Archive]:
    """Ne retient que les fichiers au bon format ; les autres sont ignorés."""
    rx = motif(prefixe)
    archives = []
    for p in rep.iterdir():
        m = rx.match(p.name)
        if not m or not p.is_file():
            log.debug("ignoré : %s", p.name)
            continue
        try:
            quand = date(int(m[1]), int(m[2]), int(m[3]))
        except ValueError:
            log.warning("date invalide dans le nom : %s", p.name)
            continue
        archives.append(Archive(p, quand))
    return sorted(archives, key=lambda a: a.quand)


def selection(dates: list[date], pol: Politique) -> dict[date, str]:
    """Rend {date: raison} pour les dates à conserver. Fonction pure."""
    dates = sorted(set(dates))
    garder: dict[date, str] = {}

    def derniers(n: int, seq: list) -> list:
        # PIÈGE : seq[-0:] rend TOUTE la liste, pas une liste vide.
        return seq[-n:] if n > 0 else []

    # fils : les N dates les plus récentes
    for d in derniers(pol.quotidiennes, dates):
        garder.setdefault(d, "quotidienne")

    # pères : la DERNIÈRE archive de chaque semaine ISO, N semaines
    par_semaine: dict[tuple[int, int], date] = {}
    for d in dates:
        an, sem, _ = d.isocalendar()
        par_semaine[(an, sem)] = d  # la liste est triée : la dernière gagne
    for _, d in derniers(pol.hebdomadaires, sorted(par_semaine.items())):
        garder.setdefault(d, "hebdomadaire")

    # grands-pères : la PREMIÈRE archive de chaque mois, N mois
    par_mois: dict[tuple[int, int], date] = {}
    for d in dates:
        par_mois.setdefault((d.year, d.month), d)  # la première reste
    for _, d in derniers(pol.mensuelles, sorted(par_mois.items())):
        garder.setdefault(d, "mensuelle")
    return garder


def appliquer(
    archives: list[Archive], pol: Politique, dry_run: bool
) -> dict[str, list[str]]:
    garder = selection([a.quand for a in archives], pol)
    bilan: dict[str, list[str]] = {"gardees": [], "supprimees": []}
    for a in archives:
        if a.quand in garder:
            log.debug("garde   %s (%s)", a.chemin.name, garder[a.quand])
            bilan["gardees"].append(a.chemin.name)
            continue
        bilan["supprimees"].append(a.chemin.name)
        if dry_run:
            log.info("[dry-run] supprimerait %s", a.chemin.name)
        else:
            log.info("supprime %s", a.chemin.name)
            a.chemin.unlink()
    return bilan


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("repertoire", type=Path)
    p.add_argument("--prefix", default="factura")
    p.add_argument("--daily", type=int, default=7)
    p.add_argument("--weekly", type=int, default=4)
    p.add_argument("--monthly", type=int, default=6)
    p.add_argument("-n", "--dry-run", action="store_true")
    p.add_argument("--json", action="store_true")
    p.add_argument("-v", "--verbose", action="store_true")
    a = p.parse_args(argv)
    if min(a.daily, a.weekly, a.monthly) < 0:
        p.error("les rétentions sont des entiers positifs ou nuls")
    return a


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
        stream=sys.stderr,
    )
    if not args.repertoire.is_dir():
        log.error("%s n'est pas un répertoire", args.repertoire)
        return 1
    pol = Politique(args.daily, args.weekly, args.monthly)
    try:
        archives = inventorier(args.repertoire, args.prefix)
        bilan = appliquer(archives, pol, args.dry_run)
    except OSError as exc:
        log.error("%s", exc)
        return 1
    if args.json:
        json.dump(bilan | {"dry_run": args.dry_run}, sys.stdout, indent=2)
        print()
    else:
        print(
            f"{len(bilan['gardees'])} gardée(s), "
            f"{len(bilan['supprimees'])} supprimée(s)"
            f"{' (simulation)' if args.dry_run else ''}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

**`~/lab23/rotate/pytest.ini`** — pour que les tests importent le module :

```ini
[pytest]
pythonpath = .
testpaths = tests
```

**`~/lab23/rotate/tests/test_rotate_backups.py`**

```python
"""Tests de rotate_backups.py — lancer avec : pytest -q tests/"""

from datetime import date, timedelta
from pathlib import Path

import pytest

import rotate_backups as rb


def jours(n: int, fin: date = date(2026, 9, 18)) -> list[date]:
    """n dates consécutives se terminant le 18/09/2026."""
    return [fin - timedelta(days=i) for i in range(n)][::-1]


def creer(rep: Path, dates: list[date], prefixe: str = "factura") -> None:
    for d in dates:
        (rep / f"{prefixe}-{d.isoformat()}.tar.gz").write_bytes(b"x")


def test_selection_garde_7_quotidiennes():
    garder = rb.selection(jours(30), rb.Politique(7, 0, 0))
    assert sorted(garder) == jours(7)
    assert set(garder.values()) == {"quotidienne"}


def test_selection_hebdo_prend_la_derniere_de_chaque_semaine():
    garder = rb.selection(jours(60), rb.Politique(0, 4, 0))
    assert len(garder) == 4
    # le 18/09/2026 est un vendredi : dernière archive de sa semaine ISO
    assert date(2026, 9, 18) in garder
    # les trois autres sont des dimanches (fin de semaine ISO)
    dimanches = [d for d in garder if d != date(2026, 9, 18)]
    assert all(d.isoweekday() == 7 for d in dimanches)


def test_selection_mensuelle_prend_la_premiere_du_mois():
    garder = rb.selection(jours(200), rb.Politique(0, 0, 6))
    assert len(garder) == 6
    assert date(2026, 9, 1) in garder and date(2026, 4, 1) in garder


def test_selection_union_sur_120_jours():
    garder = rb.selection(jours(120), rb.Politique())
    # 7 + 4 + 6 moins les recouvrements (le 18/09 est à la fois fils et père)
    assert 12 <= len(garder) <= 17
    assert date(2026, 9, 18) in garder


def test_inventorier_ignore_les_intrus(tmp_path):
    creer(tmp_path, jours(3))
    (tmp_path / "export final.tar.gz").write_bytes(b"x")
    (tmp_path / "factura-2026-13-45.tar.gz").write_bytes(b"x")  # date fausse
    (tmp_path / "autre-2026-09-01.tar.gz").write_bytes(b"x")
    noms = [a.chemin.name for a in rb.inventorier(tmp_path, "factura")]
    assert noms == [f"factura-{d.isoformat()}.tar.gz" for d in jours(3)]


def test_dry_run_ne_supprime_rien(tmp_path):
    creer(tmp_path, jours(40))
    bilan = rb.appliquer(
        rb.inventorier(tmp_path, "factura"), rb.Politique(), dry_run=True
    )
    assert len(bilan["supprimees"]) > 0
    assert len(list(tmp_path.iterdir())) == 40


def test_appliquer_supprime_et_garde_l_intrus(tmp_path):
    creer(tmp_path, jours(40))
    intrus = tmp_path / "export final.tar.gz"
    intrus.write_bytes(b"x")
    bilan = rb.appliquer(
        rb.inventorier(tmp_path, "factura"), rb.Politique(), dry_run=False
    )
    restants = {p.name for p in tmp_path.iterdir()}
    assert intrus.name in restants
    assert restants - {intrus.name} == set(bilan["gardees"])
    assert not (restants & set(bilan["supprimees"]))


def test_main_repertoire_absent(tmp_path, caplog):
    # le message part par logging, pas par print : caplog, pas capsys
    assert rb.main([str(tmp_path / "nope")]) == 1
    assert "pas un répertoire" in caplog.text


@pytest.mark.parametrize("args", [["--daily", "-1"], ["--weekly", "x"]])
def test_main_usage_incorrect(tmp_path, args):
    with pytest.raises(SystemExit) as exc:
        rb.main([str(tmp_path), *args])
    assert exc.value.code == 2
```

```console
$ python rotate_backups.py --dry-run -v data/sauvegardes 2>&1 | grep garde
DEBUG: garde   factura-2026-05-22.tar.gz (mensuelle)
DEBUG: garde   factura-2026-06-01.tar.gz (mensuelle)
...
DEBUG: garde   factura-2026-09-06.tar.gz (hebdomadaire)
DEBUG: garde   factura-2026-09-12.tar.gz (quotidienne)
...
14 gardée(s), 106 supprimée(s) (simulation)
$ pytest -q
.........                                                          [100%]
9 passed in 0.05s
```

::: pourquoi
**Pure d'abord.** `selection()` ne touche ni disque ni horloge : elle
reçoit des dates, rend un dict `{date: raison}`. C'est pourquoi les tests
tiennent en quelques lignes et s'exécutent en 50 ms — et pourquoi le test
de l'incident (« le 1er du mois précédent est gardé ») est écrit en trois
lignes.

**Semaine ISO et mois.** `date.isocalendar()` rend `(année, semaine,
jour)` : on regroupe par `(année, semaine)` — pas par `semaine` seule,
sinon la semaine 1 de 2027 écraserait celle de 2026. Comme la liste est
triée, écrire `par_semaine[cle] = d` à chaque tour laisse la **dernière**
date de la semaine ; `setdefault` sur les mois garde la **première**. Deux
idiomes de dict, deux politiques.

**`setdefault(d, raison)`** pour l'union : une date déjà gardée comme
quotidienne n'est pas re-étiquetée hebdomadaire ; le compte est juste et le
`-v` dit pourquoi chaque fichier survit.

**Le piège `[-0:]`** : `dates[-0:]` est toute la liste. Une politique
`--daily 0` aurait tout gardé ; `derniers(n, seq)` le neutralise et le test
`test_selection_garde_7_quotidiennes` avec `Politique(7, 0, 0)` l'aurait
attrapé — c'est d'ailleurs comme ça qu'il a été trouvé en écrivant ce
corrigé.

**La date dans le nom** : `re.escape(prefixe)` protège un préfixe
contenant un point ; `date(int, int, int)` valide (`2026-13-45` lève
`ValueError`, journalisé, ignoré). Un `mtime` aurait été modifié par le
`cp` de la restauration — c'est la cause de l'incident du contexte.
:::

::: piege
`pytest` ne trouve pas `rotate_backups` sans `pythonpath = .` (ou un
`conftest.py` vide à la racine, ou la disposition `src/` + `pip install
-e .`). Et un fichier nommé `rotate-backups.py` n'est pas importable : le
tiret n'est pas valide dans un nom de module. Nommer les fichiers comme des
modules dès le départ évite un renommage le jour où les tests arrivent.
:::

---

### **L23.5** — Exporter Prometheus métier

*Métriques métier depuis un CSV ou PostgreSQL, format texte, SIGTERM.*

**`~/lab23/bin/factura_exporter.py`**

```python
#!/usr/bin/env python3
"""factura_exporter.py — exporter Prometheus « métier » sans dépendance.

Expose sur /metrics le nombre et le montant des factures par statut, lus à
CHAQUE scrape (modèle pull : la valeur est fraîche, jamais mise en cache)
depuis un CSV ou, avec [source].dsn, depuis PostgreSQL (psycopg 3).

Configuration TOML (défaut /etc/factura/exporter.toml) :
    [http]
    port = 9105
    [source]
    csv = "/srv/factura/data/factures.csv"    # ou dsn = "host=... dbname=..."

Le format d'exposition texte est écrit à la main : c'est volontaire, pour
voir ce que prometheus_client produit. En production, prends la bibliothèque.
"""

from __future__ import annotations

import argparse
import csv
import logging
import signal
import sys
import time
import tomllib
from collections import Counter, defaultdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

log = logging.getLogger("exporter")
STATUTS = ("brouillon", "emise", "payee", "annulee")


# --- collecte ----------------------------------------------------------------
def lire_csv(chemin: Path) -> list[dict[str, str]]:
    with chemin.open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f, delimiter=";"))


def lire_postgres(dsn: str) -> list[dict[str, str]]:
    import psycopg  # pip install "psycopg[binary]"

    with psycopg.connect(dsn, connect_timeout=3) as conn:
        rows = conn.execute("SELECT statut, montant FROM factures").fetchall()
    return [{"statut": s, "montant": str(m)} for s, m in rows]


def agreger(lignes: list[dict[str, str]]) -> dict[str, dict[str, float]]:
    nb: Counter[str] = Counter()
    montant: defaultdict[str, float] = defaultdict(float)
    for ligne in lignes:
        statut = ligne.get("statut", "inconnu")
        nb[statut] += 1
        try:
            montant[statut] += float(ligne.get("montant", "0"))
        except ValueError:
            log.warning("montant illisible : %r", ligne)
    return {"nb": dict(nb), "montant": dict(montant)}


def exposition(
    agg: dict[str, dict[str, float]], duree: float, ok: bool
) -> str:
    """Format texte Prometheus : # HELP, # TYPE, puis une ligne par série."""
    lignes = [
        "# HELP factura_factures_total Nombre de factures par statut.",
        "# TYPE factura_factures_total gauge",
    ]
    for statut in sorted(set(STATUTS) | set(agg["nb"])):
        lignes.append(
            f'factura_factures_total{{statut="{statut}"}} '
            f"{agg['nb'].get(statut, 0)}"
        )
    lignes += [
        "# HELP factura_montant_euros Montant cumulé par statut.",
        "# TYPE factura_montant_euros gauge",
    ]
    for statut, m in sorted(agg["montant"].items()):
        lignes.append(f'factura_montant_euros{{statut="{statut}"}} {m:.2f}')
    lignes += [
        "# HELP factura_collecte_duree_seconds Durée de la lecture.",
        "# TYPE factura_collecte_duree_seconds gauge",
        f"factura_collecte_duree_seconds {duree:.4f}",
        "# HELP factura_collecte_ok 1 si la source a répondu, 0 sinon.",
        "# TYPE factura_collecte_ok gauge",
        f"factura_collecte_ok {int(ok)}",
    ]
    return "\n".join(lignes) + "\n"


def collecter(conf: dict[str, Any]) -> str:
    debut = time.monotonic()
    ok = True
    try:
        src = conf["source"]
        lignes = (
            lire_postgres(src["dsn"])
            if src.get("dsn")
            else lire_csv(Path(src["csv"]))
        )
    except Exception as exc:  # noqa: BLE001 — l'exporter doit rester vivant
        log.error("collecte impossible : %s", exc)
        lignes, ok = [], False
    return exposition(agreger(lignes), time.monotonic() - debut, ok)


# --- serveur HTTP ------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    conf: dict[str, Any] = {}

    def do_GET(self) -> None:  # noqa: N802 — nom imposé par http.server
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return
        corps = collecter(self.conf).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def log_message(self, fmt: str, *args: Any) -> None:
        log.debug(fmt, *args)  # sinon http.server écrit sur stderr


def charger(chemin: Path) -> dict[str, Any]:
    with chemin.open("rb") as f:  # tomllib exige le mode binaire
        conf = tomllib.load(f)
    if "source" not in conf or not (
        conf["source"].get("csv") or conf["source"].get("dsn")
    ):
        raise ValueError("[source] doit définir csv ou dsn")
    return conf


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument(
        "-c", "--config", type=Path, default=Path("/etc/factura/exporter.toml")
    )
    p.add_argument(
        "--once",
        action="store_true",
        help="afficher les métriques et sortir (test)",
    )
    p.add_argument("-v", "--verbose", action="store_true")
    args = p.parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stderr,
    )
    try:
        conf = charger(args.config)
    except (OSError, ValueError, tomllib.TOMLDecodeError) as exc:
        log.error("configuration : %s", exc)
        return 1
    if args.once:
        sys.stdout.write(collecter(conf))
        return 0
    port = int(conf.get("http", {}).get("port", 9105))
    Handler.conf = conf
    srv = ThreadingHTTPServer(("0.0.0.0", port), Handler)

    def arreter(signum: int, frame: Any) -> None:
        log.info("signal %d reçu, arrêt", signum)
        raise SystemExit(0)  # SystemExit : le with/finally s'exécutent

    signal.signal(signal.SIGTERM, arreter)
    log.info("exporter à l'écoute sur :%d/metrics", port)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

```console
$ bin/factura_exporter.py -c conf/exporter.toml --once | head -6
# HELP factura_factures_total Nombre de factures par statut.
# TYPE factura_factures_total gauge
factura_factures_total{statut="annulee"} 61
factura_factures_total{statut="brouillon"} 58
factura_factures_total{statut="emise"} 108
factura_factures_total{statut="payee"} 173
```

**Variante avec `prometheus_client`** (`bin/factura_exporter_lib.py`) —
le collecteur personnalisé lit la source **au moment du scrape**, comme la
version manuelle :

```python
#!/usr/bin/env python3
import sys
import time
from pathlib import Path

from prometheus_client import start_http_server
from prometheus_client.core import GaugeMetricFamily
from prometheus_client.registry import Collector, REGISTRY

from factura_exporter import agreger, charger, lire_csv  # même logique


class FacturaCollector(Collector):
    def __init__(self, conf):
        self.conf = conf

    def collect(self):
        agg = agreger(lire_csv(Path(self.conf["source"]["csv"])))
        nb = GaugeMetricFamily("factura_factures_total",
                               "Nombre de factures par statut.",
                               labels=["statut"])
        for statut, n in agg["nb"].items():
            nb.add_metric([statut], n)
        yield nb
        m = GaugeMetricFamily("factura_montant_euros",
                              "Montant cumulé par statut.", labels=["statut"])
        for statut, v in agg["montant"].items():
            m.add_metric([statut], v)
        yield m


conf = charger(Path(sys.argv[1]))
REGISTRY.register(FacturaCollector(conf))
start_http_server(9106)          # expose /metrics dans un thread
while True:
    time.sleep(3600)
```

Pour des valeurs mises à jour par le programme lui-même (compteurs
d'événements), l'API directe suffit : `Counter("x_total", "aide",
["etiquette"]).labels(etiquette="a").inc()` et `Gauge(...).set(v)`. Et pour
un cron, `prometheus_client.write_to_textfile("/var/lib/node_exporter/
factura.prom", registry)` alimente le *textfile collector* de node_exporter,
sans serveur HTTP.

**Déploiement**

```ini
# /etc/systemd/system/factura-exporter.service
[Unit]
Description=Exporter Prometheus métier factura
After=network-online.target

[Service]
DynamicUser=yes
ExecStart=/home/mathieu/lab23/venv/bin/python \
  /home/mathieu/lab23/bin/factura_exporter.py -c /etc/factura/exporter.toml
Environment=PYTHONUNBUFFERED=1
Restart=on-failure
RestartSec=5
StandardError=journal
SyslogIdentifier=factura-exporter

[Install]
WantedBy=multi-user.target
```

```yaml
# lab-ops : /etc/prometheus/prometheus.yml, bloc scrape_configs
  - job_name: factura
    static_configs:
      - targets: ["10.10.10.10:9105"]
```

```bash
sudo ss -tlnp | grep 9105
curl -s 'http://10.10.10.14:9090/api/v1/query' \
  --data-urlencode 'query=sum(factura_factures_total{statut="emise"})' | jq .
```

**Bonus PostgreSQL** (sur `lab-db`) :

```sql
CREATE TABLE IF NOT EXISTS factures (id serial PRIMARY KEY,
  statut text NOT NULL, montant numeric(10,2) NOT NULL);
INSERT INTO factures (statut, montant) VALUES ('emise', 120.50),
  ('payee', 980.00), ('brouillon', 10.00);
```

`pip install "psycopg[binary]"` dans le venv, puis
`dsn = "host=10.10.10.12 dbname=factura user=factura password=..."` dans
`exporter.toml` (fichier en `0640`, propriétaire du service).

::: pourquoi
**Pull, pas push.** Prometheus vient chercher les valeurs ; l'exporter
doit donc **calculer au scrape** (`collecter()` dans `do_GET`) et non
mettre en cache une valeur calculée au démarrage. C'est ce que vérifie le
check : on ajoute une ligne au CSV, la valeur change au scrape suivant.

**Le format texte** est trivial à écrire, et le faire une fois apprend ce
que `prometheus_client` génère : une ligne `# HELP`, une `# TYPE`, puis
`nom{etiquette="valeur"} nombre`. Les noms suivent la convention
`<domaine>_<mesure>_<unité>` : `factura_montant_euros`,
`factura_collecte_duree_seconds`. Le `Content-Type: text/plain;
version=0.0.4` est celui que Prometheus attend.

**Un exporter ne meurt pas parce que sa source est en panne.** Le `except
Exception` dans `collecter()` est ici légitime — et commenté : il protège
la boucle de service, journalise, et **expose l'échec** comme une métrique
(`factura_collecte_ok 0`) sur laquelle on alerte. Un 500 aurait été aussi
détectable (`up == 0`), mais aurait perdu les métriques encore valides.

**`ThreadingHTTPServer`** sert plusieurs scrapes en parallèle (Prometheus
+ un `curl` de diagnostic). **`signal.signal(SIGTERM, ...)`** lève
`SystemExit` depuis le gestionnaire : `serve_forever()` s'interrompt, le
`finally` ferme le socket, le code est 0 — systemd voit un arrêt propre,
pas un `killed`. Sans lui, `SIGTERM` tue le processus sans passer par
`finally`.

**`tomllib`** est dans la bibliothèque standard depuis 3.11, en lecture
seule, et exige un fichier ouvert en **binaire** — le module décode
lui-même en UTF-8, comme l'exige la spécification TOML.
:::

::: piege
`DynamicUser=yes` crée un utilisateur éphémère : il ne peut pas lire
`~/mathieu/lab23/data/factures.csv` si le répertoire est en `0750`. En
production, les données vont dans `/srv/factura` et le code dans
`/opt/factura`, avec des droits explicites — le lab tolère un
`User=mathieu` le temps de vérifier le reste.
:::

---

## 23.7 Break & Fix

### **BF23.1** — « Ça marche chez moi, pas sous le timer »

*`export-rapport.py` fonctionne dans le shell, échoue sous
`export-rapport.timer`.*

**Diagnostic**

```console
$ systemctl status export-rapport.service | tail -3
$ journalctl -u export-rapport.service -n 20 --no-pager
python3[4123]: Traceback (most recent call last):
python3[4123]:   File "/home/mathieu/lab23/bf1/export-rapport.py", line 7
python3[4123]: import yaml
python3[4123]: ModuleNotFoundError: No module named 'yaml'
```

Première différence : **l'interpréteur**. `ExecStart=/usr/bin/python3` est
le Python système, `yaml` est dans le venv. On corrige l'unité
(`ExecStart=/home/mathieu/lab23/venv/bin/python /home/.../export-rapport.py`),
`daemon-reload`, `systemctl start export-rapport.service`, et on relit :

```text
FileNotFoundError: [Errno 2] No such file or directory: 'conf/export.yaml'
```

Deuxième différence : **le répertoire courant**. Dans le shell, on lançait
depuis `~/lab23/bf1` ; systemd démarre dans `/`. Deux correctifs
complémentaires : `WorkingDirectory=/home/mathieu/lab23/bf1` dans l'unité,
**et** dans le script des chemins ancrés sur le fichier lui-même
(`BASE = Path(__file__).resolve().parent`) — le script ne doit pas dépendre
de l'endroit d'où on l'appelle. On relance :

```text
FileNotFoundError: [Errno 2] No such file or directory: 'notifier'
```

Troisième différence : **le `PATH`**. `notifier` est dans `~/.local/bin`,
que ton `.profile` ajoute au `PATH` de ta session ; l'unité a le `PATH`
minimal de systemd. On appelle le notifieur par chemin absolu (ou on le
déplace dans `/usr/local/bin`, ou `Environment=PATH=...` dans l'unité).

**Script corrigé** (les lignes changées) :

```python
from pathlib import Path
BASE = Path(__file__).resolve().parent
NOTIFIER = Path.home() / ".local/bin/notifier"     # ou /usr/local/bin

with (BASE / "conf/export.yaml").open(encoding="utf-8") as f:
    conf = yaml.safe_load(f)
sortie = BASE / f"rapports/rapport-{date.today()}.md"
with sortie.open("w", encoding="utf-8") as f:
    f.write("\n".join(lignes) + "\n")
subprocess.run([str(NOTIFIER), f"rapport écrit : {sortie}"], check=True,
               timeout=30)
```

**Unité corrigée** :

```ini
[Service]
Type=oneshot
User=mathieu
WorkingDirectory=/home/mathieu/lab23/bf1
ExecStart=/home/mathieu/lab23/venv/bin/python \
  /home/mathieu/lab23/bf1/export-rapport.py
Environment=PYTHONUNBUFFERED=1 LANG=C.UTF-8
```

```bash
sudo systemctl daemon-reload && sudo systemctl start export-rapport.service
ls ~/lab23/bf1/rapports/ && journalctl -t notifier -n 1
```

::: pourquoi
Un service systemd n'hérite **de rien** de ta session : pas de `PATH`
enrichi, pas de `LANG`, pas de `VIRTUAL_ENV`, pas de répertoire courant,
pas de `~/.bashrc`. `HOME`, `USER` et `LOGNAME` sont posés d'après `User=`,
`PATH` vaut la valeur compilée dans systemd. Tout ce qui « marchait » grâce
à l'environnement interactif doit devenir explicite : interpréteur en
chemin absolu, chemins ancrés sur `__file__` ou en configuration,
exécutables externes en chemin absolu, encodage déclaré. La méthode :
`journalctl -u`, corriger **une** cause, relancer, jusqu'au succès — chaque
Traceback pointe la suivante.

`PYTHONUNBUFFERED=1` : sans terminal, stdout est bufferisé ; le `print("OK
...")` final n'apparaîtrait dans le journal qu'à la sortie, après les
messages de `notifier`. Pour un script qui tourne des minutes, c'est
l'impression qu'il est bloqué.
:::

**Prévention** : `systemd-run --uid=mathieu --pty --wait
/home/mathieu/lab23/venv/bin/python script.py` reproduit l'environnement
d'un service avant d'écrire l'unité ; et `systemctl show export-rapport
-p Environment -p WorkingDirectory` répond en une commande à « qu'est-ce
que le service voit ».

---

### **BF23.2** — « L'archive est incomplète et tar râle »

*`archiver.py` construit une commande `tar` en chaîne, avec `shell=True`.*

**Diagnostic**

```console
$ ~/lab23/bf2/archiver.py ~/lab23/bf2/logs ~/lab23/bf2/archives/logs.tar.gz
tar: /home/mathieu/lab23/bf2/logs/rapport: Cannot stat: No such file...
tar: final.log: Cannot stat: No such file or directory
tar: /home/mathieu/lab23/bf2/logs/export: Cannot stat: No such file...
/bin/sh: 1: date.log: not found
tar: Exiting with failure status due to previous errors
archive écrite : /home/mathieu/lab23/bf2/archives/logs.tar.gz
$ echo $? ; tar -tzf ~/lab23/bf2/archives/logs.tar.gz | wc -l
0
4
```

La chaîne passée à `sh -c` est
`tar -czf ... .../app-2026-09-14.log ... .../rapport final.log .../export;date.log`.
Le shell découpe `rapport final.log` en deux arguments, et le `;` **termine
la commande `tar`** : `date.log` est exécuté comme une seconde commande —
c'est la « commande bizarre ». Avec un fichier nommé `x; rm -rf ~`, le
`rm` aurait tourné. Et `subprocess.run` sans `check=True` ignore le code 2
de `tar` : « archive écrite », code 0.

**Correctif**

```python
#!/usr/bin/env python3
"""archiver.py — archive les journaux d'un répertoire : REP DEST."""
import subprocess
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: archiver.py REP DEST", file=sys.stderr)
        return 2
    rep, dest = Path(sys.argv[1]), Path(sys.argv[2])
    fichiers = sorted(p.name for p in rep.glob("*.log"))
    if not fichiers:
        print(f"aucun .log dans {rep}", file=sys.stderr)
        return 3
    try:
        subprocess.run(
            ["tar", "-czf", str(dest), "-C", str(rep), "--", *fichiers],
            check=True, timeout=600,
        )
    except subprocess.CalledProcessError as exc:
        print(f"tar a échoué (code {exc.returncode})", file=sys.stderr)
        return 1
    print(f"archive écrite : {dest} ({len(fichiers)} fichiers)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

```console
$ ./archiver.py logs archives/logs.tar.gz && tar -tzf archives/logs.tar.gz
archive écrite : archives/logs.tar.gz (6 fichiers)
app-2026-09-14.log
...
export;date.log
rapport final.log
```

::: pourquoi
Sans `shell=True`, `subprocess` appelle `execve` directement avec la liste :
chaque élément devient un argument, quels que soient les caractères qu'il
contient — il n'y a **personne** pour interpréter `;`, `$`, `*` ou une
espace. `--` termine les options de `tar` : un fichier nommé `-x.log` ne
sera pas lu comme une option. `-C rep` archive des chemins relatifs, ce
qu'on veut pour restaurer ailleurs. `check=True` transforme le code 2 de
`tar` en `CalledProcessError`, qu'on convertit en message et en code 1.
`timeout` protège d'un `tar` bloqué sur un NFS mort.
:::

**Prévention** : `ruff` avec la règle `S602` (`shell=True`) via le jeu
`flake8-bandit` (`select = ["S"]`) refuse la construction en CI ; un test
avec un fichier `x; echo PWNED.log` dans `tmp_path` prouve que rien n'est
exécuté.

---

### **BF23.3** — « Too many open files »

*`compte-erreurs.py` ouvre 1 500 fichiers avant d'en lire un.*

**Diagnostic**

```console
$ ulimit -n
1024
$ ~/lab23/bf3/compte-erreurs.py ~/lab23/bf3/logs & sleep 0.2
$ ls /proc/$!/fd | wc -l           # avant le plantage
1021
OSError: [Errno 24] Too many open files: '.../svc-1022.log'
$ python3 -X dev ~/lab23/bf3/compte-erreurs.py ~/lab23/bf3/logs 2>&1 \
  | grep -m1 ResourceWarning
ResourceWarning: unclosed file <_io.TextIOWrapper name='.../svc-0001.log'...
```

Le dict `ouverts` garde une référence sur chaque objet fichier : aucun
n'est fermé tant que le dict vit, et le dict vit jusqu'à la fin. Au
1 022e `open`, le noyau refuse (`EMFILE`) : 1 024 descripteurs moins
stdin/stdout/stderr.

**Correctif**

```python
#!/usr/bin/env python3
import sys
from pathlib import Path

rep = Path(sys.argv[1])
total = 0
nb = 0
for p in sorted(rep.glob("*.log")):
    with p.open(encoding="utf-8", errors="replace") as f:  # fermé à la sortie
        total += sum(1 for ligne in f if "ERROR" in ligne)
    nb += 1
print(f"{nb} fichiers, {total} erreurs")
```

```console
$ ./compte-erreurs.py logs & sleep 0.1; ls /proc/$!/fd | wc -l ; wait
4
1500 fichiers, 1500 erreurs
```

::: pourquoi
Un descripteur est une ressource du **noyau**, pas de Python : le
ramasse-miettes ne le libère que quand plus rien ne référence l'objet
fichier. `with` appelle `close()` à la sortie du bloc, quoi qu'il arrive
(exception comprise). Le nombre de descripteurs reste à 4 (les trois
standard plus le fichier en cours) : c'est la preuve demandée.

`open(p).read()` sans `with` « marche » en CPython parce que le compteur de
références tombe à zéro immédiatement et que le destructeur ferme le
fichier. Mais c'est un détail d'implémentation (PyPy ne le garantit pas),
une exception entre `open` et `read` laisse le descripteur ouvert jusqu'au
prochain passage du GC, et `-X dev` le signale comme `ResourceWarning`. En
revue, c'est une faute.
:::

**Prévention** : `python3 -X dev` dans la CI (il active
`ResourceWarning`), et la règle `ruff` `SIM115` (« use a context manager
for opening files »).

---

### **BF23.4** — « La supervision dit OK, le site est mort »

*`verif-site.py` : `except:` nu, `sys.exit` dans le `try`, faux OK.*

**Diagnostic**

```console
$ ~/lab23/bf4/verif-site.py ~/lab23/bf4/sites.txt ; echo $?
OK http://10.10.10.11/
OK http://10.10.10.14:3000/
tous les sites OK
0
```

Deux URL n'apparaissent même pas : `urlopen` a levé `URLError`, l'`except:`
l'a avalée, `pass` n'a rien dit. Pire : le `sys.exit(2)` prévu pour un code
≠ 200 est **dans** le `try` — `SystemExit` est une exception, l'`except:`
nu l'attrape aussi, et la sortie en 2 n'a jamais lieu. Même chose pour
Ctrl-C (`KeyboardInterrupt`) : avalé, le script continue.

**Correctif**

```python
#!/usr/bin/env python3
"""verif-site.py — vérifie que les sites de sites.txt répondent en 200."""
import logging
import sys
import urllib.error
import urllib.request

log = logging.getLogger("verif-site")


def verifier(url: str, timeout: float = 3.0) -> bool:
    """Rend True si l'URL répond 200. Ne sort JAMAIS du programme."""
    try:
        with urllib.request.urlopen(url, timeout=timeout) as rep:
            code = rep.status
    except urllib.error.HTTPError as exc:
        log.error("%s : HTTP %d", url, exc.code)
        return False
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        log.error("%s : injoignable (%s)", url, exc)
        return False
    if code != 200:
        log.error("%s : code %d", url, code)
        return False
    log.info("%s : OK", url)
    return True


def main() -> int:
    logging.basicConfig(level=logging.INFO, stream=sys.stderr,
                        format="%(levelname)s %(message)s")
    with open(sys.argv[1], encoding="utf-8") as f:
        urls = [x.strip() for x in f if x.strip() and not x.startswith("#")]
    resultats = [verifier(u) for u in urls]
    ko = resultats.count(False)
    print(f"{len(urls) - ko}/{len(urls)} sites OK")
    return 2 if ko else 0


if __name__ == "__main__":
    sys.exit(main())
```

**Le test qui aurait détecté la régression** (`tests/test_verif_site.py`) :

```python
import urllib.error
import urllib.request

import verif_site


def test_site_injoignable_est_ko(monkeypatch, caplog):
    def refuse(url, timeout):
        raise urllib.error.URLError("Connection refused")

    monkeypatch.setattr(urllib.request, "urlopen", refuse)
    assert verif_site.verifier("http://10.10.10.99/") is False
    assert "injoignable" in caplog.text


def test_main_rend_2_si_un_site_tombe(tmp_path, monkeypatch):
    (tmp_path / "s.txt").write_text("http://a/\nhttp://b/\n")
    monkeypatch.setattr(verif_site, "verifier",
                        lambda u, timeout=3.0: u == "http://a/")
    monkeypatch.setattr("sys.argv", ["x", str(tmp_path / "s.txt")])
    assert verif_site.main() == 2
```

::: pourquoi
Trois principes violés, trois corrections. **Attraper précisément** :
`HTTPError` (réponse reçue), `URLError`/`OSError` (pas de réponse) — et
laisser passer `SystemExit`, `KeyboardInterrupt`, et les bugs. **Une
fonction rend un résultat, elle ne termine pas le programme** : `sys.exit`
n'a sa place que dans `main()` (ou plutôt `return code` depuis `main`, et
`sys.exit(main())` à la fin). C'est ce qui rend `verifier()` testable sans
attraper `SystemExit` dans les tests. **Un `except` fait quelque chose** :
ici, journaliser et rendre `False`.

Le test simule `urlopen` avec `monkeypatch` : aucun réseau, aucune attente,
et la régression « site mort = OK » est impossible à réintroduire sans
casser la suite.
:::

**Prévention** : `ruff` règle `E722` (bare except) et `BLE001` (blind
except) en CI ; en revue, tout `except` sans `log` ni `raise` est refusé.

---

## 23.8 Défi du module

**D23 — `sante.sh` réécrit en Python : projet `pilotage`**

*Même interface que le `sante.sh` du module 13 : Markdown sur stdout,
diagnostics sur stderr, code 0/1/2 ; paquet installable, tests, timer.*

**`~/lab23/pilotage/pyproject.toml`**

```toml
[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[project]
name = "pilotage"
version = "1.0.0"
description = "État de santé d'un serveur (réécriture de sante.sh)"
requires-python = ">=3.12"
dependencies = []

[project.optional-dependencies]
dev = ["pytest>=8", "ruff>=0.5", "mypy>=1.10"]

[project.scripts]
sante-serveur = "pilotage.cli:main"

[tool.setuptools.packages.find]
where = ["src"]

[tool.ruff]
line-length = 79
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "W", "I", "UP", "B", "SIM"]

[tool.pytest.ini_options]
testpaths = ["tests"]
```

**`src/pilotage/__init__.py`**

```python
"""pilotage — état de santé d'un serveur, en Python, même interface que
sante.sh : rapport Markdown sur stdout, diagnostics sur stderr, code 0/1/2."""

__version__ = "1.0.0"
```

**`src/pilotage/collecte.py`**

```python
"""Lecture des sources système. Chaque fonction accepte le TEXTE brut en
paramètre optionnel pour être testable sans /proc ni commandes."""

from __future__ import annotations

import logging
import os
import shutil
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path

log = logging.getLogger("pilotage")

FS_IGNORES = {
    "tmpfs",
    "devtmpfs",
    "squashfs",
    "overlay",
    "proc",
    "sysfs",
    "cgroup2",
    "efivarfs",
    "fuse.lxcfs",
}


@dataclass(frozen=True)
class Cpu:
    us: float
    sy: float
    wa: float
    st: float


@dataclass(frozen=True)
class Memoire:
    total_mo: int
    dispo_mo: int

    @property
    def pct_dispo(self) -> float:
        return 100 * self.dispo_mo / self.total_mo if self.total_mo else 0.0


@dataclass(frozen=True)
class SystemeFichiers:
    point: str
    pct_espace: float
    pct_inodes: float


def lire(chemin: str) -> str:
    return Path(chemin).read_text(encoding="utf-8")


def charge(texte: str | None = None) -> tuple[float, float, float]:
    l1, l5, l15, *_ = (texte or lire("/proc/loadavg")).split()
    return float(l1), float(l5), float(l15)


def _cpu_brut(texte: str) -> tuple[int, int, int, int, int]:
    """Rend (user+nice, system, iowait, steal, total) en jiffies."""
    for ligne in texte.splitlines():
        if ligne.startswith("cpu "):
            v = [int(x) for x in ligne.split()[1:]]
            v += [0] * (8 - len(v))
            return v[0] + v[1], v[2], v[4], v[7], sum(v[:8])
    raise ValueError("ligne 'cpu ' absente de /proc/stat")


def cpu(
    avant: str | None = None, apres: str | None = None, delai: float = 2.0
) -> Cpu:
    """Delta entre deux lectures : /proc/stat cumule depuis le boot."""
    if avant is None or apres is None:
        avant = lire("/proc/stat")
        time.sleep(delai)
        apres = lire("/proc/stat")
    u1, s1, w1, t1, tot1 = _cpu_brut(avant)
    u2, s2, w2, t2, tot2 = _cpu_brut(apres)
    d = (tot2 - tot1) or 1
    pct = lambda a, b: round(100 * (b - a) / d, 1)  # noqa: E731
    return Cpu(pct(u1, u2), pct(s1, s2), pct(w1, w2), pct(t1, t2))


def memoire(texte: str | None = None) -> Memoire:
    val: dict[str, int] = {}
    for ligne in (texte or lire("/proc/meminfo")).splitlines():
        cle, _, reste = ligne.partition(":")
        val[cle] = int(reste.split()[0])  # en ko
    return Memoire(val["MemTotal"] // 1024, val["MemAvailable"] // 1024)


def swap_actif(texte: str | None = None) -> bool:
    for ligne in (texte or lire("/proc/swaps")).splitlines()[1:]:
        champs = ligne.split()
        if len(champs) >= 4 and int(champs[3]) > 0:
            return True
    return False


def systemes_fichiers(
    mounts: str | None = None, statvfs=os.statvfs
) -> list[SystemeFichiers]:
    """Un enregistrement par montage rw réel, espace ET inodes."""
    resultats = []
    for ligne in (mounts or lire("/proc/mounts")).splitlines():
        _, point, fstype, options, *_ = ligne.split()
        if fstype in FS_IGNORES or "ro" in options.split(","):
            continue
        try:
            st = statvfs(point)
        except OSError as exc:
            log.warning("statvfs %s : %s", point, exc)
            continue
        utilise = st.f_blocks - st.f_bfree
        if utilise + st.f_bavail == 0:
            continue
        # comme df : utilisé / (utilisé + disponible pour un non-root)
        pct_e = 100 * utilise / (utilise + st.f_bavail)
        pct_i = 100 * (1 - st.f_favail / st.f_files) if st.f_files else 0.0
        resultats.append(
            SystemeFichiers(point, round(pct_e, 1), round(pct_i, 1))
        )
    return resultats


def commande(argv: list[str], timeout: float = 10) -> str | None:
    """stdout de la commande, ou None si absente/en échec (dégradation)."""
    if shutil.which(argv[0]) is None:
        log.warning("%s absent : section dégradée", argv[0])
        return None
    try:
        p = subprocess.run(
            argv, capture_output=True, text=True, timeout=timeout, check=True
        )
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
        log.warning("%s : %s", " ".join(argv), exc)
        return None
    return p.stdout


def top_processus(n: int = 5) -> tuple[list[str], list[str]]:
    par_cpu = commande(["ps", "-eo", "pid,pcpu,rss,comm", "--sort=-pcpu"])
    par_rss = commande(["ps", "-eo", "pid,pcpu,rss,comm", "--sort=-rss"])
    couper = lambda s: s.splitlines()[1 : n + 1] if s else []  # noqa: E731
    return couper(par_cpu), couper(par_rss)


def gros_fichiers(
    racine: str = "/var/log", n: int = 5
) -> list[tuple[int, str]]:
    tailles = []
    for rep, _, fichiers in os.walk(racine):
        for f in fichiers:
            p = os.path.join(rep, f)
            try:
                tailles.append((os.lstat(p).st_size, p))
            except OSError:
                continue
    return sorted(tailles, reverse=True)[:n]


def unites_en_echec(texte: str | None = None) -> list[str]:
    if texte is None:
        texte = commande(
            [
                "systemctl",
                "list-units",
                "--state=failed",
                "--no-legend",
                "--plain",
                "--no-pager",
            ]
        )
    return [x.split()[0] for x in (texte or "").splitlines() if x.strip()]


def journal() -> tuple[str, int, list[str]]:
    taille = commande(["journalctl", "--disk-usage"]) or "indisponible"
    err = (
        commande(
            [
                "journalctl",
                "-b",
                "-p",
                "err",
                "-q",
                "--no-pager",
                "-o",
                "short-iso",
            ]
        )
        or ""
    )
    lignes = err.splitlines()
    return taille.strip(), len(lignes), lignes[-10:]
```

**`src/pilotage/cli.py`**

```python
"""Point d'entrée : rapport Markdown sur stdout, journal sur stderr,
code 0 (rien), 1 (avertissement), 2 (critique)."""

from __future__ import annotations

import argparse
import logging
import os
import socket
import sys
from dataclasses import dataclass, field
from datetime import datetime

from pilotage import __version__, collecte

log = logging.getLogger("pilotage")


@dataclass
class Seuils:
    ratio: float = 1.5
    wa: float = 20
    mem_pct: float = 15
    fs: float = 90
    fs_crit: float = 95
    inodes: float = 90
    st: float = 5


@dataclass
class Verdict:
    avertissements: list[str] = field(default_factory=list)
    critiques: list[str] = field(default_factory=list)

    def avert(self, msg: str) -> None:
        self.avertissements.append(msg)

    def crit(self, msg: str) -> None:
        self.critiques.append(msg)

    @property
    def code(self) -> int:
        return 2 if self.critiques else 1 if self.avertissements else 0


def evaluer(
    s: Seuils,
    charge: tuple[float, float, float],
    coeurs: int,
    cpu: collecte.Cpu,
    mem: collecte.Memoire,
    swap: bool,
    fs: list[collecte.SystemeFichiers],
    echecs: list[str],
) -> Verdict:
    """Toute la logique de décision, pure : c'est elle qu'on teste."""
    v = Verdict()
    ratio = charge[0] / coeurs
    if ratio > s.ratio:
        v.avert(f"charge/cœur = {ratio:.2f}")
    if cpu.wa > s.wa:
        v.avert(f"%wa = {cpu.wa}")
    if cpu.st > s.st:
        v.avert(f"%st = {cpu.st} (hyperviseur)")
    if mem.pct_dispo < s.mem_pct:
        v.avert(f"mémoire disponible {mem.pct_dispo:.0f} %")
    if swap:
        v.crit("swap actif")
    for f in fs:
        if f.pct_espace >= s.fs_crit and f.point in ("/", "/var"):
            v.crit(f"{f.point} à {f.pct_espace} % d'espace")
        elif f.pct_espace >= s.fs:
            v.avert(f"{f.point} à {f.pct_espace} % d'espace")
        if f.pct_inodes >= s.inodes:
            v.crit(f"{f.point} à {f.pct_inodes} % d'inodes")
    if echecs:
        v.crit(
            f"{len(echecs)} unité(s) systemd en échec : " + ", ".join(echecs)
        )
    return v


def rapport(delai: float) -> tuple[str, int]:
    s = Seuils()
    out: list[str] = []
    p = out.append
    coeurs = os.cpu_count() or 1
    p(
        f"# État de santé — {socket.getfqdn()} — "
        f"{datetime.now().astimezone().isoformat(timespec='seconds')}\n"
    )
    p(f"* cœurs : {coeurs}   pilotage {__version__}")
    with open("/proc/uptime", encoding="utf-8") as fu:
        secondes = float(fu.read().split()[0])
    p(f"* uptime : {secondes / 3600:.1f} h\n")

    ch = collecte.charge()
    p("## Charge\n")
    p(f"{ch[0]} {ch[1]} {ch[2]} — ratio/cœur {ch[0] / coeurs:.2f}\n")

    cpu = collecte.cpu(delai=delai)
    p("## CPU\n")
    p(f"us={cpu.us} sy={cpu.sy} wa={cpu.wa} st={cpu.st}\n")

    mem = collecte.memoire()
    swap = collecte.swap_actif()
    p("## Mémoire\n")
    p(
        f"total {mem.total_mo} Mo, disponible {mem.dispo_mo} Mo "
        f"({mem.pct_dispo:.0f} %), swap {'ACTIF' if swap else 'inactif'}\n"
    )

    fs = collecte.systemes_fichiers()
    p("## Systèmes de fichiers\n")
    for f in fs:
        p(f"* {f.point} : {f.pct_espace} % espace, {f.pct_inodes} % inodes")
    p("")

    par_cpu, par_rss = collecte.top_processus()
    p("## Processus\n")
    p("```\n" + "\n".join(par_cpu) + "\n```\n")
    p("```\n" + "\n".join(par_rss) + "\n```\n")

    p("## /var/log\n")
    for octets, chemin in collecte.gros_fichiers():
        p(f"* {octets // 2**20} Mo  {chemin}")
    p("")

    taille, nb_err, dernieres = collecte.journal()
    p("## Journal\n")
    p(f"* {taille}")
    p(f"* entrées err depuis le boot : {nb_err}\n")
    p("```\n" + "\n".join(dernieres) + "\n```\n")

    echecs = collecte.unites_en_echec()
    p("## Unités en échec\n")
    p("\n".join(f"* {u}" for u in echecs) or "aucune")
    p("")

    v = evaluer(s, ch, coeurs, cpu, mem, swap, fs, echecs)
    p("## VERDICT\n")
    if not v.avertissements and not v.critiques:
        p("Aucune anomalie.")
    for c in v.critiques:
        p(f"* CRITIQUE      {c}")
    for a in v.avertissements:
        p(f"* AVERTISSEMENT {a}")
    return "\n".join(out) + "\n", v.code


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="sante-serveur", description=__doc__.split("\n")[0]
    )
    ap.add_argument(
        "--delai",
        type=float,
        default=2.0,
        help="secondes entre les deux lectures CPU",
    )
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--version", action="version", version=__version__)
    args = ap.parse_args(argv)
    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(levelname)s %(message)s",
        stream=sys.stderr,
    )
    texte, code = rapport(args.delai)
    sys.stdout.write(texte)
    return code


if __name__ == "__main__":
    sys.exit(main())
```

**`tests/test_pilotage.py`**

```python
"""Tests de pilotage : aucune lecture réelle de /proc, aucune commande."""

import subprocess
from collections import namedtuple

import pytest

from pilotage import cli, collecte

STAT1 = "cpu  100 0 50 800 20 0 0 5\ncpu0 1 2 3 4 5 6 7 8\n"
STAT2 = "cpu  200 0 100 900 60 0 0 15\ncpu0 1 2 3 4 5 6 7 8\n"
MEMINFO = (
    "MemTotal:       2048000 kB\nMemFree:  10 kB\nMemAvailable:    204800 kB\n"
)
MOUNTS = (
    "/dev/sda1 / ext4 rw,relatime 0 0\n"
    "tmpfs /run tmpfs rw,nosuid 0 0\n"
    "/dev/sdb1 /srv xfs rw 0 0\n"
    "/dev/sr0 /media iso9660 ro 0 0\n"
)
Vfs = namedtuple("Vfs", "f_blocks f_bfree f_bavail f_files f_favail")


def test_cpu_delta():
    c = collecte.cpu(STAT1, STAT2)
    # delta total = 300 ; user 100, system 50, iowait 40, steal 10
    assert (c.us, c.sy, c.wa, c.st) == (33.3, 16.7, 13.3, 3.3)


def test_cpu_sans_ligne_cpu():
    with pytest.raises(ValueError):
        collecte.cpu("rien\n", "rien\n")


def test_memoire_et_pourcentage():
    m = collecte.memoire(MEMINFO)
    assert (m.total_mo, m.dispo_mo) == (2000, 200)
    assert m.pct_dispo == pytest.approx(10.0)


def test_systemes_fichiers_filtre_et_inodes():
    def faux_statvfs(point):
        # f_blocks, f_bfree, f_bavail, f_files, f_favail
        return {
            "/": Vfs(100, 4, 4, 1000, 950),
            "/srv": Vfs(100, 50, 50, 1000, 50),
        }[point]

    fs = collecte.systemes_fichiers(MOUNTS, statvfs=faux_statvfs)
    assert [f.point for f in fs] == ["/", "/srv"]  # ni tmpfs ni ro
    assert fs[0].pct_espace == 96.0 and fs[0].pct_inodes == 5.0
    assert fs[1].pct_inodes == 95.0


def test_commande_absente(monkeypatch):
    monkeypatch.setattr(collecte.shutil, "which", lambda x: None)
    assert collecte.commande(["iostat", "-x"]) is None


def test_commande_echec_simule(monkeypatch):
    def faux_run(argv, **kw):
        raise subprocess.CalledProcessError(1, argv)

    monkeypatch.setattr(collecte.shutil, "which", lambda x: "/bin/x")
    monkeypatch.setattr(subprocess, "run", faux_run)
    assert collecte.commande(["systemctl", "list-units"]) is None


def test_unites_en_echec_parse():
    texte = (
        "nginx.service loaded failed failed A\n"
        "foo.timer loaded failed failed B\n"
    )
    assert collecte.unites_en_echec(texte) == ["nginx.service", "foo.timer"]
    assert collecte.unites_en_echec("") == []


def test_evaluer_codes():
    s = cli.Seuils()
    cpu = collecte.Cpu(10, 5, 1, 0)
    mem = collecte.Memoire(2000, 1000)
    sain = cli.evaluer(s, (0.5, 0.5, 0.5), 2, cpu, mem, False, [], [])
    assert sain.code == 0
    lent = cli.evaluer(s, (4.0, 1, 1), 2, cpu, mem, False, [], [])
    assert lent.code == 1 and "charge" in lent.avertissements[0]
    fs = [collecte.SystemeFichiers("/var", 40.0, 99.0)]
    plein = cli.evaluer(s, (0.5, 1, 1), 2, cpu, mem, False, fs, [])
    assert plein.code == 2 and "inodes" in plein.critiques[0]
    casse = cli.evaluer(s, (0.5, 1, 1), 2, cpu, mem, True, [], ["x.service"])
    assert casse.code == 2 and len(casse.critiques) == 2
```

**`systemd/sante-serveur.service`** et **`systemd/sante-serveur.timer`**

```ini
[Unit]
Description=État de santé du serveur (pilotage, Python)
After=network-online.target

[Service]
Type=oneshot
User=root
# Le venv est appelé par son chemin absolu : rien à « activer ».
ExecStart=/opt/factura/venv/bin/sante-serveur --delai 2
# stdout (le rapport) va dans un fichier, stderr (les diagnostics) au journal.
StandardOutput=append:/var/log/factura/sante-serveur.md
StandardError=journal
SyslogIdentifier=sante-serveur
Environment=PYTHONUNBUFFERED=1 LANG=C.UTF-8
# Un code 1 ou 2 est un verdict, pas un plantage.
SuccessExitStatus=1 2
```

```ini
[Unit]
Description=Rapport de santé toutes les 15 minutes

[Timer]
OnBootSec=3min
OnUnitActiveSec=15min
RandomizedDelaySec=60
Persistent=true

[Install]
WantedBy=timers.target
```

**Déploiement et vérification**

```bash
cd ~/lab23/pilotage
ruff check . && ruff format --check . && mypy src && pytest -q
sudo mkdir -p /var/log/factura
sudo python3 -m venv /opt/factura/venv
sudo /opt/factura/venv/bin/pip install --quiet ~/lab23/pilotage
sudo /opt/factura/venv/bin/sante-serveur > /tmp/rapport.md ; echo $?
sudo cp systemd/sante-serveur.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now sante-serveur.timer
sudo systemctl start sante-serveur.service
systemctl list-timers sante-serveur.timer
tail -5 /var/log/factura/sante-serveur.md
journalctl -t sante-serveur -n 5
```

```console
$ pytest -q
........                                                           [100%]
8 passed in 0.02s
$ sudo /opt/factura/venv/bin/sante-serveur | tail -4 ; echo "code $?"
## VERDICT

Aucune anomalie.
code 0
```

**`~/lab23/rapports/pilotage-notes.md`** — les points attendus :

1. **Le delta CPU** : `awk '/^cpu /...'` lancé deux fois avec `read` de six
   variables, contre `_cpu_brut(texte)` appelée sur deux chaînes ; le calcul
   des pourcentages passe d'un `awk -v a= -v d=` par valeur à une lambda.
2. **Les inodes et l'espace** : deux `df` et un `while read` en bash ;
   `os.statvfs` rend les deux en un appel, et `/proc/mounts` remplace le
   filtrage `-x tmpfs -x devtmpfs`.
3. **La dégradation** : `dispo iostat && ... || echo indisponible >&2` à
   chaque outil ; une seule fonction `commande()` avec `shutil.which`,
   `timeout` et `check=True`, qui rend `None` — et `set -e` n'a plus à être
   désamorcé par des `|| true`.
4. **Le verdict** : un tableau bash et deux drapeaux, avec le piège
   `test && action` sous `set -e` ; un `dataclass Verdict` dont `.code` est
   une propriété.
5. **Les tests** : impossibles sur `sante.sh` sans `bats` et une VM ; ici,
   8 tests sans `/proc` ni commande, en 20 ms.

Ce qui reste plus simple en bash : `journalctl -b -p err -n 10` ou
`ps --sort=-pcpu | head`, c'est-à-dire **appeler une commande et montrer
sa sortie** — et le Python le fait d'ailleurs en appelant ces commandes.
Ajouter une vérification : une fonction dans `collecte.py` qui accepte le
texte brut, un test dans `tests/`, une ligne dans `evaluer()` et une section
dans `rapport()`.

::: pourquoi
**Ce qui est évalué.** (1) L'interface est **identique** : quelqu'un qui
avait `sante.sh > rapport.md ; echo $?` dans un cron ne voit aucune
différence. C'est le contrat d'une réécriture. (2) La **séparation** lecture
/ décision / rendu : `collecte.py` lit, `evaluer()` décide, `rapport()`
écrit. Chaque lecteur accepte le texte brut en paramètre — c'est ce qui
rend les tests possibles sans `/proc`, et c'est le choix de conception le
plus important du défi. (3) La **dégradation** : `commande()` centralise
`which`, `timeout`, `check` et le journal ; sur `lab-rhel` sans `sysstat`,
rien ne plante. (4) Le **packaging** : `pip install` dans un venv dédié
sous `/opt`, sans dépendance externe (la bibliothèque standard suffit —
c'est aussi ce qui rend le paquet déployable sur Rocky 9 avec
`python3.12`). (5) L'**unité** : `SuccessExitStatus=1 2` parce que
1 et 2 sont des verdicts ; stdout dans un fichier, stderr dans le journal
avec un `SyslogIdentifier` pour `journalctl -t`.

`/proc/stat` cumule depuis le boot : sans delta, un serveur qui a chargé
pendant une heure il y a un mois affiche encore cette charge. `time.sleep`
entre les deux lectures est le seul « temps mort » du programme ; `--delai`
le rend réglable, et les tests l'évitent en passant les deux textes.

`os.statvfs` : `f_bavail` (blocs disponibles pour un non-root) et non
`f_bfree` (dont les 5 % réservés à root) — c'est ce que `df` affiche, et
c'est ce qui compte pour l'application. `f_favail`/`f_files` donne les
inodes : le `/var` « plein à 40 % » du module 13 est ici une ligne.
:::

::: piege
`mypy` signale une variable réutilisée avec un autre type (`f` fichier puis
`f` système de fichiers) : les annotations trouvent des bugs de relecture
avant qu'ils n'en soient. Et `os.cpu_count()` peut rendre `None` dans un
conteneur restreint : `or 1` évite une division par zéro dans le ratio.
:::
