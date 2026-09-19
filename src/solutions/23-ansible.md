# Module 23 — Corrigé

## 23.3 Quiz — QCM

**Q23.1** — *`shell: systemctl restart nginx` relancée trois fois sur un hôte
sain : que rapporte Ansible ?*

**Réponse : b) `changed` aux trois exécutions**

::: pourquoi
`command` et `shell` n'ont aucun moyen de savoir si la commande a modifié
quelque chose : ils lancent un processus, lisent `rc`, `stdout`, `stderr`, et
c'est tout. Par construction, ils rapportent **toujours** `changed` dès que
`rc == 0`, et `failed` sinon. Ici `systemctl restart` réussit à chaque fois,
donc `changed` trois fois — et nginx est réellement redémarré trois fois,
avec trois coupures de service.

Un module « intelligent » comme `ansible.builtin.systemd_service` compare
l'état voulu (`state: started`) à l'état réel avant d'agir, et ne rapporte
`changed` que s'il a dû agir. Mais même lui, avec `state: restarted`, agit à
chaque fois : « redémarré » n'est pas un état, c'est une action. La seule
écriture idempotente d'un redémarrage est un *handler*, notifié par la tâche
qui change la configuration.
:::

::: piege
La réponse d) tente : `shell` pilote très bien systemd, c'est justement le
problème — il le fait sans discernement. Si tu vois un `shell: systemctl
restart` dans un playbook, c'est un redémarrage de production à chaque
passage de la CI.
:::

---

**Q23.2** — *`command -a 'ls /var/lib/postgresql/*/main | wc -l'` échoue avec
`ls: cannot access '|'`.*

**Réponse : b)** `command` n'invoque pas de shell : ni glob, ni pipe.

::: pourquoi
Le module `command` découpe la chaîne en arguments (comme `shlex.split`) et
appelle directement `execve()` avec `ls`, `/var/lib/postgresql/*/main`, `|`,
`wc`, `-l`. Aucun shell n'intervient : l'astérisque n'est pas développé (d'où
le premier message, le chemin littéral n'existe pas), le `|` est un argument
comme un autre (d'où le second), et `wc` n'est jamais lancé. Tout ce qui est
du ressort du shell — glob, pipe, redirection, `$VAR`, `&&`, `~` — exige
`ansible.builtin.shell`.

C'est aussi ce qui rend `command` plus sûr : pas d'injection possible via une
variable qui contiendrait `; rm -rf /`. La règle : `command` par défaut,
`shell` seulement quand tu as besoin d'une fonctionnalité du shell, et dans
les deux cas `changed_when`/`creates` pour l'idempotence.
:::

::: piege
`-b` (réponse c) n'aurait rien changé : le message n'est pas
`Permission denied`. Lis toujours le texte de l'erreur avant de sortir
`sudo` : ici, c'est `'|': No such file or directory` qui trahit l'absence de
shell.
:::

---

**Q23.3** — *`become = True` dans `ansible.cfg`, `ping` répond
`Missing sudo password`. Deux réponses.*

**Réponses : a) et b)**

::: pourquoi
Avec `become = True`, même un simple `ping` s'exécute via `sudo`. Sur les
cibles, `mathieu` est dans `sudo`/`wheel` mais sans `NOPASSWD` : `sudo`
demande un mot de passe, Ansible n'en a pas, et il ne peut pas le demander
interactivement au milieu d'une connexion SSH sans tty. D'où le message.

Deux issues : fournir le mot de passe (`-K`, `--ask-become-pass`, ou la
variable `ansible_become_password` — dans un vault) ou ne plus en avoir
besoin (`mathieu ALL=(ALL) NOPASSWD: ALL` dans `/etc/sudoers.d/`, ou un
compte de service dédié comme celui de L23.1). En production, c'est presque
toujours la seconde : un compte `ansible` avec `NOPASSWD`, une clé dédiée, et
des journaux `sudo` qui tracent chaque commande.
:::

::: piege
c) `remote_user = root` contourne le problème en ouvrant SSH à root, ce que
le module 14 et la baseline de ce module interdisent (`PermitRootLogin no`).
d) `host_key_checking` concerne les clés d'hôte SSH, pas `sudo` : mélanger
les deux est un classique de l'entretien.
:::

---

**Q23.4** — *`/bin/sh: /usr/bin/python3: No such file or directory`,
`rc: 127` sur `lab-rhel`. Quelle tâche peut encore s'exécuter ?*

**Réponse : b)** `ansible.builtin.raw: dnf install -y python3` avec
`gather_facts: false`.

::: pourquoi
Tous les modules Ansible (sauf deux) sont des programmes Python envoyés sur
la cible et exécutés par `ansible_python_interpreter`. Sans Python, `dnf`,
`package`, `apt`, `ping`, et même la collecte de facts (`setup`) échouent
avant de commencer. `rc: 127` est le code « commande introuvable » du shell
distant : `/bin/sh` n'a pas trouvé `python3`.

Les deux exceptions sont `raw` et `script` : ils envoient une commande brute
par SSH, sans wrapper Python. Il faut aussi `gather_facts: false` sur le
play, sinon `setup` est lancé avant la première tâche et échoue. Le play de
réparation canonique :

```yaml
- name: Amorcer Python sur les hôtes nus
  hosts: rhel
  become: true
  gather_facts: false
  tasks:
    - name: Installer python3 sans module Python
      ansible.builtin.raw: dnf install -y python3
      changed_when: true
```
:::

---

**Q23.5** — *Le template change mais nginx n'est jamais rechargé :
`notify: reload nginx` contre `name: Reload nginx`.*

**Réponse : b)** la comparaison du nom respecte la casse.

::: pourquoi
`notify` fait correspondre une chaîne au `name` (ou au `listen`) d'un
handler, par égalité stricte. `reload nginx` et `Reload nginx` sont deux
chaînes différentes ; la notification part vers un handler qui n'existe pas.
Le recap montre `changed=1` (le template) et rien d'autre.

Deux parades : la constante `listen` (plusieurs handlers peuvent écouter le
même « topic », et le nom exact du handler devient secondaire), et
`ansible-lint`, qui signale un `notify` sans handler correspondant.
:::

::: piege
Depuis ansible-core 2.15, un `notify` vers un handler inexistant est une
erreur fatale (`The requested handler 'reload nginx' was not found`) — mais
seulement si la tâche est `changed`. Sur une version plus ancienne, ou si le
template est `ok`, tu ne verras rien. Et non, l'ordre de déclaration
(réponse d) est indifférent : les handlers sont résolus après l'analyse
complète du play.
:::

---

**Q23.6** — *`lab-db` est dans `@ungrouped`, `group_vars/db.yml` définit
`pg_version: 16`. Que vaut `pg_version` sur `lab-db` ?*

**Réponse : b)** indéfinie : `lab-db` n'est dans aucun groupe `db`.

::: pourquoi
`group_vars/<nom>.yml` s'applique aux hôtes membres du groupe `<nom>`, et
uniquement à eux. Le graphe montre qu'aucun groupe `db` n'existe dans cet
inventaire : le fichier `group_vars/db.yml` est donc chargé (Ansible ne se
plaint pas d'un fichier orphelin) mais ne s'applique à personne.
`ansible-inventory --host lab-db` ne montrera pas `pg_version`, et un
template qui l'utilise échouera avec `'pg_version' is undefined`.

C'est un cas fréquent après une réorganisation d'inventaire : on renomme un
groupe, et ses variables restent dans un fichier qui porte l'ancien nom.
Réflexe : `ansible-inventory --graph` puis `--host` pour vérifier qu'une
variable arrive bien là où on la croit.
:::

---

**Q23.7** — *Ordre de précédence croissant correct.*

**Réponse : b)** `defaults/main.yml` < `group_vars` < `host_vars` < `vars:`
du play < `-e`.

::: pourquoi
La logique est « du plus général au plus spécifique, puis l'humain qui
lance ». Les `defaults` d'un rôle sont des valeurs que l'auteur du rôle
propose et s'attend à voir surchargées. L'inventaire les précise, d'abord
par groupe, puis par hôte (un hôte est plus spécifique qu'un groupe). Le play
qui les utilise peut fixer une valeur (`vars:`). Et les extra vars `-e`
gagnent toujours : c'est le mécanisme prévu pour « cette fois-ci, avec cette
valeur ».

Entre `group_vars`, l'ordre est `all` d'abord, puis les groupes parents,
puis les enfants (un enfant surcharge son parent) ; à profondeur égale,
ordre alphabétique — d'où le conseil de ne pas définir la même variable dans
deux groupes frères.
:::

---

**Q23.8** — *`serial: 1`, `max_fail_percentage: 0`, la santé échoue sur
`lab-web`.*

**Réponse : b)** le play s'arrête, `lab-rhel` n'est jamais touché.

::: pourquoi
`serial: 1` découpe les hôtes du play en lots d'un seul hôte, et rejoue
**toutes** les tâches du play sur le lot avant de passer au suivant.
`max_fail_percentage: 0` signifie : si plus de 0 % des hôtes du lot ont
échoué à la fin du lot, abandonner le play. Avec un lot d'un hôte, le
moindre échec est 100 % > 0 %. Ansible affiche `NO MORE HOSTS LEFT` et
passe au recap, où `lab-rhel` n'a même pas d'entrée `ok`.

Sans `max_fail_percentage` (ni `any_errors_fatal`), Ansible retire
simplement l'hôte en échec et **continue** avec le lot suivant : c'est la
réponse a), et c'est ce qu'on ne veut pas dans un rolling update, où un
échec doit figer le parc dans un état où il reste des frontaux sains.
:::

::: piege
Ansible n'annule rien (réponse d) : il n'y a pas de transaction. `lab-web`
reste dans l'état où l'échec l'a laissé — d'où l'importance de vérifier la
santé **avant** de passer au suivant et de savoir revenir en arrière (voir
la stratégie de rollback demandée par D23).
:::

---

**Q23.9** — *Écrire un rapport une seule fois sur le nœud de contrôle.
Deux réponses.*

**Réponses : a) et c)**

::: pourquoi
`delegate_to: localhost` déplace l'**exécution** de la tâche sur le nœud de
contrôle, tout en gardant les variables et facts de l'hôte courant. Sans
autre précaution, la tâche tourne une fois **par hôte** du play. `run_once:
true` la limite au premier hôte du lot, et le résultat (`register`) est
copié vers tous les autres. C'est la forme canonique.

c) obtient le même résultat à la main : `when: inventory_hostname ==
play_hosts[0]` ne laisse passer que le premier hôte. C'est plus verbeux et
`play_hosts` est déprécié au profit de `ansible_play_hosts`, mais ça marche
et on le voit dans des playbooks anciens.
:::

::: piege
b) `local_action` est l'ancienne syntaxe de `delegate_to: localhost` : seule,
elle tourne encore N fois. d) `connection: local` sur chaque hôte transforme
tous les hôtes en « localhost » pour **toutes** les tâches du play, ce qui
n'a aucun sens ici.
:::

---

**Q23.10** — *Liste des IP des hôtes du groupe `web`.*

**Réponse : b)**
`{{ groups['web'] | map('extract', hostvars, 'ansible_host') | list }}`

::: pourquoi
`groups['web']` est une **liste de noms** d'hôtes (`['lab-web',
'lab-rhel']`), pas une liste de dictionnaires : `map(attribute=...)` (a) n'a
rien sur quoi lire un attribut. Les variables d'un hôte vivent dans
`hostvars[<nom>]`. Le filtre `extract` fait exactement ce pont : pour chaque
élément `h` de la liste, il renvoie `hostvars[h]['ansible_host']`. Le `|
list` final matérialise le générateur Jinja2 en liste (sinon tu affiches
`<generator object ...>`).

Écriture équivalente, plus lisible dans un template :

```jinja
{% for h in groups['web'] %}
{{ hostvars[h]['ansible_host'] }}
{% endfor %}
```
:::

---

**Q23.11** — *`--check` : `'dict object' has no attribute 'stdout'` sur une
tâche qui lit `r.stdout` après `register: r` d'un `command`.*

**Réponse : b)** en `--check`, `command` n'est pas exécuté et `r` n'a pas de
`stdout`.

::: pourquoi
En mode simulation, `command`/`shell` sont sautés (`skipped`), sauf si la
tâche porte `check_mode: false`. La variable enregistrée existe quand même,
mais avec le contenu d'un résultat *skipped* : `{"changed": false,
"skipped": true, "skip_reason": "..."}`. La tâche suivante fait
`r.stdout` → l'attribut n'existe pas → erreur de variable indéfinie.

Trois façons propres de gérer ça : `check_mode: false` sur le `command` s'il
est en lecture seule (un `cat`, un `sha256sum`), `when: r.stdout is
defined` sur la tâche consommatrice, ou `r.stdout | default('')`. La
première est la bonne dans 90 % des cas : une commande qui ne modifie rien
peut tourner en `--check`, et c'est souvent elle qui décide de la suite.
:::

---

**Q23.12** — *Quelle tâche est idempotente **et** signale correctement les
changements ?*

**Réponse : c)** `command: useradd deploy` avec `creates: /home/deploy`.

::: pourquoi
`creates:` demande à `command` de regarder si le chemin existe **avant**
d'exécuter : s'il existe, la tâche est `skipped` (ni `changed` ni `failed`)
et la commande ne tourne pas. Première passe : le home n'existe pas,
`useradd` tourne, `changed`. Seconde passe : `skipped`. C'est exactement le
comportement attendu. (`removes:` est le symétrique : n'exécuter que si le
chemin existe.)

a) `|| true` masque l'erreur mais reste `changed` à chaque fois. b)
`ignore_errors` laisse la tâche en `failed... ignoring` dans le recap et
reste `changed` la première fois seulement par hasard. d) `changed_when:
false` ment : la première exécution crée bien l'utilisateur et devrait le
dire.
:::

::: piege
La vraie bonne réponse en production est `ansible.builtin.user: name=deploy`
— ce QCM porte sur `command` parce que c'est le cas de BF23.1. Chaque fois
qu'un module existe pour l'action, `creates`/`changed_when` ne sont qu'un
pansement.
:::

---

**Q23.13** — *`Decryption failed (no vault secrets were found that could
decrypt)`.*

**Réponse : b)** un mot de passe a été fourni, mais aucun ne déchiffre ce
fichier.

::: pourquoi
Ansible a deux messages distincts et il faut les connaître par cœur :

* `Attempting to decrypt but no vault secrets found` : le fichier est
  chiffré et **aucun** mot de passe n'est disponible (pas de
  `vault_password_file`, pas de `--ask-vault-pass`, pas de `--vault-id`).
* `Decryption failed (no vault secrets were found that could decrypt)` :
  au moins un mot de passe a été chargé, tous ont été essayés, aucun ne
  convient.

Dans le second cas, le fichier est bien un vault (sinon Ansible ne tenterait
rien) et il n'est très probablement pas corrompu (le format est vérifié
avant le déchiffrement). Reste : mauvais mot de passe, ou fichier chiffré
avec un autre mot de passe que celui de l'équipe — le scénario de BF23.3.
:::

---

**Q23.14** — *`get_url` avec `force: true`, `changed` à chaque fois. Deux
corrections.*

**Réponses : a) et b)**

::: pourquoi
`get_url` est idempotent par défaut : si `dest` existe, il ne télécharge pas
(sauf `force: true`, qui retélécharge et compare ensuite). Retirer `force`
et garder un `dest` stable suffit à ne plus rien retélécharger. Mais on ne
sait alors pas si le fichier local est bon.

`checksum: "sha256:<empreinte>"` (ou `sha256:<URL d'un fichier de sommes>`)
ajoute la vérification : le fichier présent est haché **avant** tout
téléchargement ; s'il correspond, `ok` sans contact réseau ; sinon
téléchargement, puis échec si le fichier reçu ne correspond pas non plus.
C'est la forme demandée dans L23.1 : intégrité **et** idempotence.
:::

::: piege
c) `changed_when: false` cache le symptôme sans supprimer le téléchargement
à chaque passage. d) `wget` dans un `shell` perd tout : idempotence,
checksum, gestion des proxys et des certificats. Le « pour être sûr d'avoir
la dernière version » est le vrai problème : une version doit être une
variable épinglée, pas « la dernière ».
:::

---

**Q23.15** — *`defaults/main.yml` : 80, `vars/main.yml` : 8080, `-e
nginx_port=443`.*

**Réponse : c) 443**

::: pourquoi
Les extra vars sont au sommet de la précédence : elles gagnent sur tout,
y compris sur `vars/main.yml` du rôle, qui est pourtant lui-même très haut
(au-dessus de `group_vars`, `host_vars` et des `vars:` du play). Sans `-e`,
le template aurait reçu 8080, et c'est justement le piège de `vars/main.yml`
: une valeur qui y est écrite est quasiment impossible à surcharger depuis
l'inventaire, ce qui rend le rôle inutilisable ailleurs (QO23.6).
:::

---

**Q23.16** — *Avertissement « discovered Python interpreter at
/usr/bin/python3.9 » sur `lab-rhel`.*

**Réponse : a)** `interpreter_python = auto_silent` dans `ansible.cfg`, ou
`ansible_python_interpreter` dans l'inventaire.

::: pourquoi
Par défaut (`interpreter_python = auto`), Ansible cherche un interpréteur
Python sur la cible dans une liste de chemins, l'utilise, et t'avertit que
ce choix pourrait changer si un autre Python était installé. `auto_silent`
fait la même découverte sans l'avertissement. Fixer
`ansible_python_interpreter: /usr/bin/python3` dans `group_vars` est encore
mieux : le chemin est explicite, versionné, et identique d'une exécution à
l'autre — c'est ce que fait le setup du module dans `ubuntu.yml` et
`rhel.yml`.

b) installer Python 3.12 ne ferait qu'ajouter un candidat. c)
`gather_facts: false` cache l'avertissement sur la collecte, mais il
réapparaît à la première tâche. d) `-vvv` n'est pas une correction.
:::

---

**Q23.17** — *Affirmation fausse sur `--check`.*

**Réponse : c)** « les handlers notifiés sont exécutés pour de vrai » est
faux.

::: pourquoi
En `--check`, toute la chaîne reste en simulation : les tâches qui
supportent le mode *check* (`template`, `copy`, `file`, `apt`, `user`,
`systemd_service`...) prédisent `changed` sans agir, les handlers qu'elles
notifient sont bien déclenchés à la fin du play, mais **eux aussi** en mode
*check* : un `service: state: reloaded` affiche `changed` sans recharger
quoi que ce soit.

a), b) et d) sont exactes : `--diff` montre le diff prédit des fichiers,
`command`/`shell` sont sautés sauf `check_mode: false`, et `apt` compare la
liste demandée au cache local sans rien installer.
:::

---

**Q23.18** — *Play sur `web`, tâche avec `loop: "{{ groups['db'] }}"` et
`delegate_to: "{{ item }}"`.*

**Réponse : b)** sur `lab-db`, une fois par hôte du groupe `web`, avec les
facts et variables de l'hôte `web` courant, sauf les variables de connexion.

::: pourquoi
`delegate_to` change **où** la tâche s'exécute (la connexion SSH est ouverte
vers l'hôte délégué, avec ses `ansible_host`, `ansible_user`, `ansible_port`)
mais pas **pour qui** : `inventory_hostname`, `ansible_facts`, `hostvars`
et les variables d'inventaire restent celles de l'hôte courant du play.
Le play tourne sur `lab-web` puis `lab-rhel` ; pour chacun, la boucle
délègue à chaque hôte de `db` (un seul : `lab-db`). Total : deux exécutions
sur `lab-db`, l'une « au nom de » `lab-web`, l'autre « au nom de »
`lab-rhel`.

C'est le patron d'une tâche « déclarer ce frontal dans la conf du
répartiteur » ou « ouvrir le pare-feu de la base pour ce frontal » : on
utilise `ansible_facts['default_ipv4']['address']` du frontal, exécuté sur la
base. Pour obtenir les facts de l'hôte délégué, il faut `delegate_facts:
true` (et une collecte) ou lire `hostvars[item]`.
:::

---

## 23.4 Quiz — questions ouvertes

**QO23.1** — *Mécanique d'une tâche `apt` : connexion, transfert, exécution,
retour ; rôle de `pipelining` ; effet de `become`.*

**Réponse**

1. **Connexion** : `ansible-playbook` ouvre une session SSH vers
   `ansible_host` en tant que `remote_user` (`mathieu`), avec la clé
   `private_key_file`. `ControlMaster=auto` / `ControlPersist=60s` gardent
   cette connexion ouverte 60 s pour les tâches suivantes.
2. **Assemblage** : sur le nœud de contrôle, Ansible construit un
   « AnsiballZ » : un script Python autonome qui contient le code du module
   `apt`, ses dépendances (`module_utils`), et les paramètres de la tâche
   sérialisés en JSON.
3. **Transfert et exécution, sans pipelining** (trois allers-retours) :
   `mkdir -p ~/.ansible/tmp/ansible-tmp-<id>/` sur la cible ; `sftp`/`scp`
   du script ; puis `python3 ~/.ansible/tmp/.../AnsiballZ_apt.py`. À la fin,
   un `rm -rf` du répertoire temporaire (souvent joint à l'exécution).
4. **Avec `pipelining = True`** (une seule connexion) : le script est envoyé
   sur l'**entrée standard** de `python3` lancé directement par SSH ; plus
   de répertoire temporaire, plus de transfert de fichier. Une tâche coûte
   une exécution SSH au lieu de trois. Contrainte : `sudo` doit pouvoir
   tourner sans tty (`requiretty` désactivé, c'est le défaut sur Ubuntu et
   Rocky).
5. **Retour** : le module écrit sur stdout un **unique document JSON**
   (`changed`, `msg`, `rc`, `invocation`...), Ansible le lit, l'interprète
   (`failed_when`, `changed_when`, `register`) et décide de notifier les
   handlers.
6. **`become`** : la commande distante devient `sudo -H -S -n -u root
   /bin/sh -c 'echo BECOME-SUCCESS-<aléa>; python3 ...'`. Le marqueur
   `BECOME-SUCCESS` sert à repérer dans le flux où finit la sortie de `sudo`
   et où commence celle du module. Sans `NOPASSWD` ni `-K`, `sudo -n` échoue
   immédiatement : `Missing sudo password`. Sans pipelining, `become` vers
   un utilisateur non-root impose en plus de rendre le fichier temporaire
   lisible par lui (d'où le besoin du paquet `acl`, voir L23.3).

::: pourquoi
Comprendre ce cheminement explique quatre erreurs du module : `UNREACHABLE`
(étape 1), `python3: not found` (étape 3, d'où `raw` qui saute
l'assemblage), `Missing sudo password` (étape 6), et `Failed to set
permissions on the temporary files` (étape 3 sans pipelining avec
`become_user` non-root). `-vvv` montre chacune de ces étapes : la commande
SSH complète, le chemin du temporaire, la ligne `sudo`.
:::

---

**QO23.2** — *Entretien : « un script bash avec `set -e` et des `if [ -f ]`
est aussi idempotent qu'un playbook ». Réponds.*

**Réponse**

Définition opérationnelle : une opération est idempotente si l'exécuter N
fois produit le même état que l'exécuter une fois, **et** si elle sait dire
si elle a changé quelque chose. Le second point est ce que bash n'a pas
gratuitement : un `if [ -f ]` évite une erreur, il ne compare pas un état
voulu à un état réel.

Deux cas où bash y arrive difficilement :

* **Le contenu, pas l'existence.** `[ -f /etc/nginx/vhost.conf ] || cp ...`
  ne remet pas le fichier d'équerre s'il existe avec un contenu faux. Pour
  l'obtenir, il faut hacher, comparer, remplacer, et ne redémarrer nginx que
  dans ce cas — soit réécrire `template` + handler. Idem pour `useradd` :
  l'utilisateur existe, mais avec le mauvais uid, le mauvais shell, le
  mauvais groupe ; `if id deploy` ne le verra jamais.
* **Le multi-hôte et le multi-OS.** Le script doit gérer la boucle SSH,
  les échecs partiels, le parallélisme, `apt` contre `dnf`, `www-data`
  contre `nginx`, puis rapporter « 3 changés, 1 injoignable ». C'est
  exactement ce qu'Ansible fournit : inventaire, `forks`, facts, recap,
  `--check`.

Un cas où bash reste le bon choix : une **action** ponctuelle, locale, avec
une logique procédurale riche (rotation de sauvegardes avec calcul de dates,
parsing de sortie, boucle avec conditions imbriquées) — le `sauvegarde.sh`
du module 07. Ansible modélise des **états**, pas des algorithmes ; forcer
un algorithme dans du YAML donne des playbooks illisibles. La bonne réponse
en entretien combine les deux : le script bash pour la logique, un rôle
Ansible pour le déployer et le planifier.

::: pourquoi
Ce qu'on teste, c'est la capacité à définir l'idempotence autrement que par
« ça ne plante pas la deuxième fois ». La différence entre *ne pas échouer*
et *converger vers un état* est le cœur de la gestion de configuration, et
`changed=0` en seconde passe en est la preuve mesurable.
:::

---

**QO23.3** — *`lineinfile` vs `blockinfile` vs `template` pour
`/etc/ssh/sshd_config.d/50-baseline.conf` ; divergence ; apport de
`validate:`.*

**Réponse**

* `lineinfile` gère **une ligne** : avec `regexp`, il remplace la dernière
  occurrence qui correspond (ou ajoute la ligne si aucune ne correspond) ;
  sans `regexp`, il ajoute `line` si elle est absente, littéralement. Il ne
  sait rien du reste du fichier.
* `blockinfile` gère **un bloc** délimité par deux marqueurs
  (`# BEGIN/END ANSIBLE MANAGED BLOCK`) : il remplace tout ce qui est entre
  les marqueurs, laisse le reste. Un fichier peut avoir plusieurs blocs si
  `marker` est personnalisé.
* `template` gère **tout le fichier** : ce qui n'est pas dans le template
  n'existe pas dans le fichier. C'est la seule des trois qui garantit que
  l'état réel est exactement l'état décrit.

Pourquoi plusieurs `lineinfile` divergent : chacun ne connaît que sa ligne.
Une directive ajoutée à la main reste ; une directive retirée du playbook
reste aussi (le `lineinfile` qui l'écrivait a disparu, personne ne
l'efface) ; deux `regexp` trop larges se marchent dessus ; un doublon
(`PasswordAuthentication yes` plus haut dans le fichier, ajouté par un
outil) fait que la « dernière occurrence » n'est pas celle qui compte pour
`sshd`, qui lui prend la **première**. Au bout de six mois, aucun hôte n'a
le même fichier et `--check` ne le voit pas.

`validate: sshd -t -f %s` fait exécuter la commande sur le **fichier
temporaire** avant de le mettre en place : si `sshd -t` refuse la syntaxe,
le fichier de destination n'est pas touché, la tâche échoue, le handler
n'est pas notifié, et `sshd` continue de tourner avec l'ancienne
configuration. C'est un filet contre la faute de frappe ; il ne protège pas
d'une configuration valide qui t'enferme dehors (`AllowGroups` sans ton
groupe).

::: pourquoi
La règle : `lineinfile` pour une ligne dans un fichier que tu ne possèdes
pas (`/etc/fstab`, `/etc/hosts` d'un autre outil), `blockinfile` pour une
section dans un fichier partagé, `template` dès que tu possèdes le fichier.
Le mécanisme `sshd_config.d/` a justement été conçu pour que tu **possèdes**
un fichier entier sans toucher `sshd_config`.
:::

---

**QO23.4** — *Cycle de vie d'un handler.*

**Réponse**

1. **Notification** : une tâche `changed` dont le `notify:` cite le `name`
   (ou le `listen`) d'un handler marque ce handler comme « à exécuter » pour
   cet hôte. Une tâche `ok`, `skipped` ou `failed` ne notifie pas.
2. **Exécution** : à la **fin du play** (après la dernière tâche de
   `tasks`, puis de nouveau après `post_tasks`), dans l'ordre de déclaration
   des handlers, pas dans l'ordre des notifications.
3. **Une seule fois** par hôte et par play, quel que soit le nombre de
   tâches qui l'ont notifié. Avec `serial`, une fois par lot.
4. **Ce qui l'empêche** : une tâche en échec sur l'hôte (les handlers de
   cet hôte sont abandonnés, sauf `force_handlers`), un `when` sur le
   handler qui s'évalue faux, un nom qui ne correspond pas, `--check`
   (exécuté en simulation), et une tâche qui a `changed_when: false`.
5. **Forcer** : `ansible.builtin.meta: flush_handlers` exécute immédiatement
   les handlers en attente ; `--force-handlers` (ou `force_handlers = True`)
   les exécute même pour un hôte en échec.

Cas de production où `flush_handlers` est indispensable : le rolling update
de L23.4. On déploie le nouveau vhost, on notifie `Reload nginx`, puis on
**vérifie** avec `uri` que la nouvelle version est servie. Sans
`flush_handlers` entre les deux, la vérification interroge l'ancien nginx,
passe (ou échoue) pour de mauvaises raisons, et le rechargement n'a lieu
qu'après — c'est-à-dire sans contrôle. Autre cas : installer une base,
modifier `listen_addresses`, notifier un restart, puis créer un utilisateur
via le réseau : sans flush, la connexion réseau arrive avant le redémarrage.

::: pourquoi
Le regroupement en fin de play est une optimisation : dix templates qui
changent ne coûtent qu'un `reload`. Mais cette optimisation a un coût de
lisibilité — l'ordre réel diffère de l'ordre lu — que `flush_handlers`
rend explicite. Quand tu lis un playbook, cherche les `notify` et
demande-toi : « qu'est-ce qui s'exécute entre cette notification et le
handler ? ».
:::

---

**QO23.5** — *Entretien : mettre à jour 40 frontaux derrière un répartiteur
sans interruption.*

**Réponse**

```yaml
- name: Rolling update des frontaux
  hosts: web
  become: true
  serial: "10%"                # 4 hôtes par lot, ou [1, 5, "100%"]
  max_fail_percentage: 0       # un échec dans un lot arrête tout
  pre_tasks:
    - name: Retirer l'hôte du répartiteur
      community.general.haproxy:   # ou une API, exécutée SUR le LB
        state: disabled
        host: "{{ inventory_hostname }}"
        backend: web
      delegate_to: "{{ item }}"
      loop: "{{ groups['lb'] }}"
    - name: Attendre la fin des connexions en cours
      ansible.builtin.wait_for:
        port: 443
        state: drained
        timeout: 60
  tasks:
    - name: Déployer la nouvelle version
      ansible.builtin.template:
        src: vhost.conf.j2
        dest: /etc/nginx/sites-enabled/app.conf
        mode: "0644"
      notify: Reload nginx
    - name: Recharger maintenant, pas en fin de play
      ansible.builtin.meta: flush_handlers
  post_tasks:
    - name: Vérifier la santé de l'hôte
      ansible.builtin.uri:
        url: "https://{{ ansible_host }}/health"
        return_content: true
      register: r
      until: r.status == 200 and app_version in r.content
      retries: 5
      delay: 2
    - name: Remettre l'hôte dans le répartiteur
      community.general.haproxy:
        state: enabled
        host: "{{ inventory_hostname }}"
        backend: web
      delegate_to: "{{ item }}"
      loop: "{{ groups['lb'] }}"
  handlers:
    - name: Reload nginx
      ansible.builtin.systemd_service:
        name: nginx
        state: reloaded
```

Rôle de chaque mot-clé dans le scénario :

* `serial` : taille du lot ; les 36 autres frontaux servent pendant qu'un
  lot est en cours. Une liste (`[1, 5, "100%"]`) fait un canari, puis un
  lot moyen, puis le reste.
* `max_fail_percentage: 0` : dès qu'un hôte d'un lot échoue, le play
  s'arrête ; le reste du parc reste sur l'ancienne version, saine.
* `pre_tasks`/`post_tasks` : ce qui doit encadrer le déploiement (sortir du
  LB / y revenir), y compris quand le déploiement est fait par un rôle.
* `delegate_to` : la commande « retire ce frontal » s'exécute **sur le
  répartiteur**, avec les variables du frontal courant.
* `uri` + `until` : la vérification de santé, avec délai, sur la **nouvelle**
  version (contenu ou en-tête), avant de rendre l'hôte au trafic.
* `flush_handlers` : le rechargement doit avoir eu lieu **avant** la
  vérification et avant de remettre l'hôte dans le pool.

::: pourquoi
Ce que l'entretien mesure, c'est si tu sais que « sans interruption » se
joue au répartiteur (drain, health check) et pas dans nginx. Un candidat qui
ne cite que `serial` a compris le mécanisme Ansible mais pas le problème
d'exploitation. Bonus attendu : la stratégie de rollback (redéployer la
version N-1 avec le même playbook, `-e app_version=...`), et le fait que
`serial: 1` sur 40 hôtes est trop lent — d'où les pourcentages.
:::

---

**QO23.6** — *Précédence des variables sur sept niveaux ; pourquoi rien
d'ajustable dans `vars/main.yml`.*

**Réponse**

Ordre croissant (le suivant écrase le précédent) :

1. `roles/<r>/defaults/main.yml` — les valeurs proposées par l'auteur du
   rôle, prévues pour être surchargées.
2. `inventory/group_vars/all` — le parc entier.
3. `inventory/group_vars/<groupe>` — un sous-ensemble (`web`, `rhel`) ;
   entre groupes, parent < enfant, puis ordre alphabétique.
4. `inventory/host_vars/<hôte>` — une machine précise.
5. `vars:` du play (et `vars_files`) — fixé par celui qui écrit le playbook.
6. `roles/<r>/vars/main.yml` — les **constantes** du rôle.
7. `-e` (extra vars) — la ligne de commande, toujours gagnante.

Le niveau 6 est au-dessus de tout l'inventaire et du play : une valeur
écrite dans `vars/main.yml` ne peut être changée que par `-e`. Si tu y mets
`nginx_port: 80`, aucun `group_vars/web.yml` ne pourra dire `8080` ; le rôle
devient inutilisable dans un autre contexte sans modifier son code. Un rôle
bien conçu réserve `vars/main.yml` aux valeurs qui **ne doivent pas**
changer (noms internes de paquets par OS, chemins imposés par l'application)
— et encore, on préfère `vars/Debian.yml` chargés par `include_vars` — et
met **tout** ce qui est ajustable dans `defaults/main.yml`, documenté dans
`argument_specs.yml`.

::: pourquoi
La précédence complète d'Ansible compte 22 niveaux ; ces sept couvrent la
pratique. Le moyen mnémotechnique : « défauts < inventaire (large → précis)
< play < constantes du rôle < humain ». Et le test : si tu hésites à
changer une valeur sans toucher au code du rôle, elle est au mauvais
endroit.
:::

---

**QO23.7** — *`UNREACHABLE` sur `lab-rhel` uniquement, ce matin. Démarche et
cinq causes avec leur signature `-vvv`.*

**Réponse**

Démarche, dans l'ordre :

1. Reproduire au plus simple, sur le seul hôte :
   `ansible lab-rhel -m ansible.builtin.ping` — puis lire le `msg` complet
   du `UNREACHABLE` (il cite la sortie de `ssh`).
2. Isoler Ansible : `ssh -v mathieu@10.10.10.13 true`, avec la même clé
   (`-i ~/.ssh/id_ed25519`). Si ça passe, le problème est dans la config
   Ansible (utilisateur, clé, `ssh_args`, inventaire) ; sinon, c'est SSH ou
   le réseau.
3. Réseau : `ping 10.10.10.13`, `nc -zv 10.10.10.13 22`. Depuis la console
   Proxmox : la VM est-elle démarrée, `sshd` actif, `firewalld` avec
   `ssh` ?
4. `ansible lab-rhel -m ansible.builtin.ping -vvv` : lire la ligne
   `<10.10.10.13> SSH: EXEC ssh -vvv ...` (quels utilisateur, clé, port sont
   réellement utilisés — c'est souvent là que la surprise se trouve : mauvais
   `ansible_host`, `remote_user` différent après L23.1) et les lignes
   `debug1:` de `ssh` qui suivent.
5. Ce qui a changé depuis hier : `git log -p inventory/ ansible.cfg`,
   `journalctl -u sshd` sur la cible, `last`, un rollback de snapshot.

Cinq causes fréquentes et leur signature dans `-vvv` :

| Cause | Signature |
|---|---|
| clé refusée (compte, clé, `authorized_keys`, droits) | `Permission denied (publickey)` |
| clé d'hôte changée (VM réinstallée, rollback) | `REMOTE HOST IDENTIFICATION HAS CHANGED` |
| `sshd` arrêté ou pare-feu | `Connection refused` / `Connection timed out` |
| mauvais utilisateur ou hôte (inventaire, `remote_user`) | `Authenticating to 10.10.10.13:22 as 'ansible'` puis `Permission denied` |
| SELinux ou droits sur `~/.ssh` côté cible | `Permission denied` ; `journalctl -u sshd` : `bad ownership or modes` |

::: pourquoi
`UNREACHABLE` signifie « Ansible n'a pas pu obtenir un shell » : c'est
**toujours** un problème SSH/réseau/compte, jamais un problème de module ou
de Python (ceux-là donnent `FAILED`). Le réflexe « `ssh -v` à la main avec
la même clé et le même utilisateur » tranche en dix secondes entre « c'est
Ansible » et « c'est la machine ». Sur Rocky, ajoute `restorecon -Rv
~/.ssh` à la liste : un `authorized_keys` copié avec `cp` depuis `/tmp`
garde le mauvais contexte SELinux et `sshd` refuse de le lire.
:::

---

**QO23.8** — *Organisation d'un dépôt d'infra propre ; où va le mot de passe
du vault ; comment le runner CI l'obtient.*

**Réponse**

```text
infra/
  ansible.cfg            # inventory, roles_path, vault_password_file
  site.yml               # import_playbook dans l'ordre
  requirements.yml       # collections et rôles externes, versions épinglées
  .ansible-lint  .yamllint  .gitignore  .gitlab-ci.yml  Makefile  README.md
  inventory/
    hosts.yml
    group_vars/all/{vars.yml,vault.yml}   # vault.yml chiffré
    group_vars/<g>/{vars.yml,vault.yml}
    host_vars/<h>.yml
  playbooks/*.yml        # un par domaine, importés par site.yml
  roles/<r>/{defaults,tasks,handlers,templates,files,meta}/
  docs/RUNBOOK.md
```

* **Chiffré** : tout fichier `vault.yml`, éventuellement des fichiers
  entiers (`files/tls/*.key` via `ansible-vault encrypt`). Convention
  `vault_*` + référence en clair dans `vars.yml`, pour que `git grep` et
  `ansible-inventory --host` restent utiles.
* **Ignoré par Git** : `.vault_pass`, `*.retry`, `.cache/` (ansible-lint),
  `collections/ansible_collections/` (installées par `requirements.yml`),
  tout fichier de facts en cache.
* **En CI avant fusion** : `yamllint .`, `ansible-lint` (profil
  `production`), `ansible-playbook site.yml --syntax-check`, puis
  `--check --diff` contre un environnement de staging ou des conteneurs
  Molecule pour les rôles. Un job qui vérifie que chaque `vault.yml`
  commence par `$ANSIBLE_VAULT` (pas de secret commité en clair par
  accident), et `git grep` de motifs interdits (`password:`, `BEGIN
  PRIVATE KEY`).
* **Mot de passe du vault** : jamais dans le dépôt ; sur les postes, dans un
  gestionnaire de mots de passe d'équipe, écrit dans `.vault_pass` (0600).
  Mieux : `vault_password_file` pointant sur un **script** exécutable qui
  interroge le gestionnaire (`pass show infra/vault`, `op read`, `bw get`).
* **Sur le runner CI** : une variable *masked* et *protected* du projet
  (`ANSIBLE_VAULT_PASSWORD`), lue par le job et écrite dans un fichier
  temporaire (`printf '%s' "$ANSIBLE_VAULT_PASSWORD" > .vault_pass`,
  supprimé en fin de job) ou fournie via un script `vault_password_file`
  qui fait `echo "$ANSIBLE_VAULT_PASSWORD"`. Le masquage empêche
  l'affichage dans les journaux ; `no_log: true` sur les tâches qui
  manipulent le secret empêche Ansible de le montrer en `-v` ; et pas de
  `set -x` ni d'`echo` du secret dans le script de job.

::: pourquoi
Un dépôt d'infra se juge à deux questions : « un nouveau peut-il l'appliquer
en clonant et en lisant le README ? » et « si le dépôt fuit, qu'est-ce qui
fuit ? ». La réponse à la seconde doit être : des noms de variables et des
blobs `$ANSIBLE_VAULT`, rien d'exploitable. Le mot de passe lui-même n'a
qu'un seul lieu de vie durable, le gestionnaire de secrets ; partout
ailleurs il est transitoire.
:::

---

**QO23.9** — *Terraform vs Ansible : ce que chacun modélise, l'état
Terraform, l'enchaînement pour une VM Proxmox.*

**Réponse**

Terraform modélise des **ressources** exposées par une API (une VM Proxmox,
un enregistrement DNS, un bucket, un groupe de sécurité) et leur **cycle de
vie** : créer, modifier, détruire. Ansible modélise l'**état d'un système**
existant (paquets, fichiers, services, comptes) qu'il rejoint par SSH.

L'**état Terraform** (`terraform.tfstate`) est la mémoire de ce que
Terraform a créé : l'association entre chaque ressource déclarée et
l'identifiant réel dans l'API (VMID 9002, ID de zone DNS...). Il sert à
calculer le *plan* (diff entre déclaré et réel), à modifier la bonne
ressource, et à **détruire** ce qui a disparu du code. Sans état, Terraform
ne saurait pas qu'une VM lui appartient.

Ansible n'a pas d'état parce qu'il n'en a pas besoin : l'état, c'est la
machine. Chaque module lit l'état réel (le paquet est-il installé ? le
fichier a-t-il ce hash ?) au moment de l'exécution et converge. La
contrepartie : Ansible ne sait pas **supprimer** ce que tu retires du
playbook (une tâche `user: alice` effacée ne supprime pas alice — il faut
`state: absent` explicitement), et il ne sait pas ce qu'il a créé
hier.

Enchaînement pour une VM Proxmox :

1. `terraform apply` avec le provider `bpg/proxmox` : clone du template
   cloud-init `lab-web`, IP fixe, clé SSH de `mathieu` injectée via
   cloud-init, enregistrement DNS. Terraform attend que la VM réponde.
2. Terraform génère l'inventaire (un `local_file` rendu depuis ses outputs,
   ou un inventaire dynamique `community.general.proxmox` qui lit l'API).
3. `ansible-playbook site.yml --limit lab-web` applique la baseline, le
   rôle nginx, etc.
4. Pour supprimer : `terraform destroy -target=...` ; Ansible n'est pas
   impliqué (la machine disparaît, son état avec).

::: pourquoi
La frontière est : **ce qui a une API de création** → Terraform ; **ce qui
se configure à l'intérieur** → Ansible. Les cas gris (un utilisateur dans
une base, un dépôt Git) se tranchent par « qui doit savoir le détruire ».
Un `provisioner "remote-exec"` Terraform qui lance apt est le signe qu'on
a mélangé les deux ; un `community.general.proxmox_kvm` qui crée des VM
sans état pour les détruire, aussi.
:::

---

## 23.5 Exercices guidés

Toutes les commandes se lancent depuis `~/lab23` sur `lab-adm`, en tant que
`mathieu`. Le `ansible.cfg` du setup n'active pas `become` globalement : les
playbooks qui en ont besoin portent `become: true` au niveau du play, et tant
que L23.1 n'est pas fait, on ajoute `-K`. Les `group_vars` du projet vivent
sous `inventory/group_vars/` (à côté de `hosts.yml`, c'est là qu'Ansible les
cherche) : quand l'énoncé écrit `group_vars/all/vars.yml`, lis
`inventory/group_vars/all/vars.yml`.

**E23.1** — *Arbre de l'inventaire, variables résolues de `lab-db` en JSON,
provenance de trois variables.*

```bash
cd ~/lab23
ansible-inventory --graph
ansible-inventory --host lab-db
```

```text
@all:
  |--@ungrouped:
  |--@web:
  |  |--lab-web
  |  |--lab-rhel
  |--@db:
  |  |--lab-db
  |--@ops:
  |  |--lab-ops
  |--@ubuntu:
  |  |--lab-web
  |  |--lab-db
  |  |--lab-ops
  |--@rhel:
  |  |--lab-rhel
```

```json
{
    "admin_user": "mathieu",
    "ansible_host": "10.10.10.12",
    "ansible_python_interpreter": "/usr/bin/python3",
    "lab_domain": "lab.local",
    "monitoring_token": "{{ vault_monitoring_token }}",
    "prometheus_host": "10.10.10.14",
    "sudo_group": "sudo",
    "vault_monitoring_token": "tok-lab23-3f9a1c7e"
}
```

* de `group_vars/all/vars.yml` : `lab_domain`, `admin_user`,
  `prometheus_host`, `monitoring_token` ;
* de `group_vars/ubuntu.yml` : `sudo_group`, `ansible_python_interpreter` ;
* de `hosts.yml` : `ansible_host`.

::: pourquoi
`ansible-inventory` charge l'inventaire exactement comme `ansible-playbook`
le ferait, `group_vars`/`host_vars` compris, sans se connecter à aucun hôte.
`--host` affiche les variables **après** fusion de tous les niveaux
(`all` < `ubuntu` < `db` < host), mais **avant** rendu Jinja2 : c'est
pourquoi `monitoring_token` apparaît sous sa forme `{{ ... }}`, alors que
`vault_monitoring_token` est déjà en clair — le vault a été déchiffré au
chargement grâce à `vault_password_file`. Les variables « magiques »
(`inventory_hostname`, `group_names`, `groups`) n'apparaissent pas : elles
sont calculées à l'exécution.
:::

::: piege
`--host` ne dit pas **d'où** vient une variable. Quand deux fichiers
définissent la même clé, seule la valeur gagnante s'affiche. Pour tracer une
origine, `grep -rn nom_variable inventory/` reste le plus rapide.
:::

---

**E23.2** — *Uptime des quatre hôtes avec `command`, puis nombre de `*.conf`
dans `/etc` : erreur, explication, forme qui marche.*

```bash
ansible all -m ansible.builtin.command -a 'uptime'
```

```text
lab-web | CHANGED | rc=0 >>
 09:12:41 up 3 days,  2:07,  1 user,  load average: 0.00, 0.00, 0.00
...
```

Tentative avec `command` :

```bash
ansible all -m ansible.builtin.command -a 'ls /etc/*.conf | wc -l'
```

```text
lab-web | FAILED | rc=2 >>
ls: cannot access '/etc/*.conf': No such file or directory
ls: cannot access '|': No such file or directory
ls: cannot access 'wc': No such file or directory
ls: cannot access '-l': No such file or directory
```

Forme qui marche :

```bash
ansible all -m ansible.builtin.shell -a 'ls /etc/*.conf | wc -l'
# ou, sans shell ni glob, en laissant find faire le filtrage :
ansible all -m ansible.builtin.shell \
  -a "find /etc -maxdepth 1 -name '*.conf' | wc -l"
```

::: pourquoi
`command` exécute le binaire directement avec la liste d'arguments
découpée : le glob `*.conf` n'est pas développé (c'est le shell qui fait
ça), et `|`, `wc`, `-l` deviennent des arguments de `ls`, d'où quatre
messages `cannot access`. `shell` passe la chaîne entière à `/bin/sh -c`,
qui développe le glob et construit le pipeline.

L'`uptime` passe avec `command` parce qu'il n'a besoin d'aucune
fonctionnalité du shell. Note que les deux réponses sont `CHANGED` en jaune
: `command` et `shell` ne savent pas qu'ils n'ont rien modifié. En ad hoc
c'est sans conséquence ; dans un playbook, ce sera `changed_when: false`.
:::

---

**E23.3** — *Distribution, version, famille d'OS de chaque hôte, puis vCPU et
RAM, sans playbook.*

```bash
ansible all -m ansible.builtin.setup -a \
  'filter=ansible_distribution,ansible_distribution_version,ansible_os_family'
ansible all -m ansible.builtin.setup \
  -a 'filter=ansible_processor_vcpus,ansible_memtotal_mb'
```

```text
lab-rhel | SUCCESS => {
    "ansible_facts": {
        "ansible_distribution": "Rocky",
        "ansible_distribution_version": "9.5",
        "ansible_os_family": "RedHat"
    },
    "changed": false
}
lab-db | SUCCESS => {
    "ansible_facts": {
        "ansible_memtotal_mb": 1963,
        "ansible_processor_vcpus": 2
    },
    "changed": false
}
```

::: pourquoi
`setup` est le module que `gather_facts: true` appelle en début de play. Il
renvoie plusieurs centaines de clés ; `filter=` accepte une liste de motifs
`fnmatch` séparés par des virgules (`ansible_distribution*` aurait aussi
donné `ansible_distribution_release`, `_major_version`...). Les facts sont
ensuite disponibles dans les playbooks sous deux formes : `ansible_facts
['distribution']` (forme canonique, sans préfixe) et `ansible_distribution`
(variable injectée, forme historique). Les deux valent `Rocky` ; la première
est celle qu'`ansible-lint` préfère.

`ansible_os_family` (`Debian`/`RedHat`) est le fact à utiliser dans les
`when` : il regroupe Ubuntu et Debian d'un côté, Rocky, Alma, RHEL, Fedora
de l'autre, ce qui correspond exactement à `apt` contre `dnf`.
:::

---

**E23.4** — *Déployer `/etc/motd` en ad hoc : simulation avec diff, pour de
vrai, puis une troisième fois.*

```bash
MOTD='Parc géré par Ansible - ne pas modifier à la main'
ansible all -b -K -m ansible.builtin.copy \
  -a "content='$MOTD\n' dest=/etc/motd mode=0644" --check --diff
ansible all -b -K -m ansible.builtin.copy \
  -a "content='$MOTD\n' dest=/etc/motd mode=0644"
ansible all -b -K -m ansible.builtin.copy \
  -a "content='$MOTD\n' dest=/etc/motd mode=0644"
```

Première exécution (`--check --diff`), en jaune, avec le diff prédit :

```text
--- before: /etc/motd
+++ after: /home/mathieu/.ansible/tmp/ansible-local-.../tmpxyz
@@ -0,0 +1 @@
+Parc géré par Ansible - ne pas modifier à la main
lab-web | CHANGED => {"changed": true, ...}
```

Deuxième, en jaune, `CHANGED` : le fichier est écrit. Troisième, en vert,
`SUCCESS` avec `"changed": false` : rien à faire.

::: pourquoi
`copy` calcule le sha1 du contenu voulu et celui du fichier existant : s'ils
sont égaux et que `owner`/`group`/`mode` correspondent, il ne touche à rien.
C'est le mécanisme de l'idempotence côté module : comparer avant d'agir.
En `--check`, `copy` fait cette comparaison mais s'arrête avant l'écriture,
et `--diff` montre ce qu'il **aurait** écrit. Le code couleur (jaune =
`changed`, vert = `ok`, rouge = `failed`, violet = `unreachable`, cyan =
`skipped`) est le même dans les playbooks.

Le `\n` dans `content=` est interprété par l'analyseur `clé=valeur` d'Ansible
: sans lui, `/etc/motd` n'a pas de saut de ligne final et le prompt de
connexion colle au texte. `mode=0644` est explicite pour ne pas dépendre
de l'`umask` de la cible (et `ansible-lint` l'exige dans les playbooks).
:::

---

**E23.5** — *`playbooks/paquets.yml` : `htop vim curl tree` sur Ubuntu et
Rocky, un seul play, une seule tâche d'installation, `changed=0` en seconde
passe, pas de mise à jour du cache apt à chaque `--check`.*

```yaml
---
# playbooks/paquets.yml — outils de base sur tout le parc
- name: Outils de base sur tout le parc
  hosts: all
  become: true
  vars:
    outils_base:
      - htop
      - vim
      - curl
      - tree

  tasks:
    - name: Rafraîchir le cache apt (au plus une fois par heure)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['pkg_mgr'] == 'apt'

    - name: Installer les outils de base
      ansible.builtin.package:
        name: "{{ outils_base }}"
        state: present
```

```bash
ansible-playbook -K playbooks/paquets.yml
ansible-playbook -K playbooks/paquets.yml        # changed=0 partout
ansible-playbook -K playbooks/paquets.yml --check
yamllint playbooks/paquets.yml && ansible-lint playbooks/paquets.yml
```

::: pourquoi
`ansible.builtin.package` est un module « générique » : il lit le fact
`ansible_facts['pkg_mgr']` (`apt` ou `dnf`) et délègue au vrai module. Les
quatre noms de paquets sont identiques sur Ubuntu et Rocky, ce qui rend la
tâche unique possible ; dès qu'un nom diffère (`python3-psycopg2` vs
`python3-psycopg2` ici, mais `apache2` vs `httpd` ailleurs), il faut une
variable par famille d'OS.

`package` ne connaît pas `update_cache`/`cache_valid_time`, qui sont propres
à `apt` : d'où la tâche séparée, conditionnée par `pkg_mgr`. `cache_valid
_time: 3600` compare l'âge de `/var/lib/apt/lists/` à une heure et ne lance
`apt-get update` que si nécessaire — sans elle, la tâche serait `changed` à
chaque passage (le cache est « mis à jour ») et briserait le `changed=0`
promis. En `--check`, `apt` n'exécute pas la mise à jour mais prédit
correctement l'installation en consultant le cache local.
:::

::: piege
Passer une liste à `name:` en une seule tâche est important : `apt` fait
alors **une** transaction. Avec `loop:` sur la liste, tu obtiens quatre
transactions, quatre fois plus lent, et `ansible-lint` le signale
(`package-latest`/`no-loop-on-package`).
:::

---

**E23.6** — *`ntp_servers` : liste dans `group_vars/all`, redéfinie pour
`rhel` et pour `lab-db` ; preuve par `ansible-inventory --host`, par un
playbook `debug`, puis surcharge par `-e`.*

```yaml
# inventory/group_vars/all/vars.yml (ajout)
ntp_servers:
  - 0.ubuntu.pool.ntp.org
  - 1.ubuntu.pool.ntp.org
```

```yaml
# inventory/group_vars/rhel.yml (ajout)
ntp_servers:
  - 0.rocky.pool.ntp.org
  - 1.rocky.pool.ntp.org
```

```yaml
# inventory/host_vars/lab-db.yml
---
ntp_servers:
  - 10.10.10.1
```

```yaml
---
# playbooks/ntp-debug.yml
- name: Afficher les serveurs NTP résolus par hôte
  hosts: all
  gather_facts: false
  tasks:
    - name: Serveurs NTP de cet hôte
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }} -> {{ ntp_servers | join(' ') }}"
```

```bash
ansible-inventory --host lab-db  | grep -A2 ntp_servers    # 10.10.10.1
ansible-inventory --host lab-rhel | grep -A2 ntp_servers   # rocky
ansible-inventory --host lab-web | grep -A2 ntp_servers    # ubuntu
ansible-playbook playbooks/ntp-debug.yml
ansible-playbook playbooks/ntp-debug.yml \
  -e '{"ntp_servers": ["10.10.10.99"]}'                    # partout
```

::: pourquoi
Trois niveaux, trois portées : `group_vars/all` touche tout le monde,
`group_vars/rhel` surcharge pour les membres de `rhel` (plus spécifique
qu'`all`), `host_vars/lab-db` surcharge pour un seul hôte (plus spécifique
qu'un groupe). `lab-db` est aussi dans `ubuntu`, mais `ubuntu.yml` ne
définit pas `ntp_servers`, donc rien ne se dispute. L'extra var `-e` passe
au-dessus de tout.

Pour une **liste** en `-e`, la forme `clé=valeur` ne convient pas
(`-e ntp_servers=10.10.10.99` donne la **chaîne** `"10.10.10.99"`, et
`join` la découperait en caractères) : on passe du JSON, ou `-e @fichier.yml`.
:::

---

**E23.7** — *`/etc/hosts` complet généré par template à partir de
`hostvars`, identique sur les quatre hôtes, `ok` en seconde passe.*

```jinja
# playbooks/templates/hosts.j2
# Managed by Ansible - ne pas modifier a la main
127.0.0.1 localhost
::1       localhost ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters

# Parc {{ lab_domain }}
{% for h in groups['all'] | sort %}
{{ hostvars[h]['ansible_host'] }} {{ h }}.{{ lab_domain }} {{ h }}
{% endfor %}
```

```yaml
---
# playbooks/hosts.yml — /etc/hosts du parc, généré depuis l'inventaire
- name: Générer /etc/hosts depuis l'inventaire
  hosts: all
  become: true
  gather_facts: false
  tasks:
    - name: Déployer /etc/hosts
      ansible.builtin.template:
        src: templates/hosts.j2
        dest: /etc/hosts
        owner: root
        group: root
        mode: "0644"
```

```bash
ansible-playbook -K playbooks/hosts.yml --check --diff
ansible-playbook -K playbooks/hosts.yml
ansible-playbook -K playbooks/hosts.yml          # ok=1 changed=0
ansible all -m ansible.builtin.command -a 'md5sum /etc/hosts'  # 4 fois le même
```

::: pourquoi
`groups['all']` est la liste des noms d'hôtes de l'inventaire ; `hostvars[h]`
donne accès aux variables de chacun, y compris `ansible_host`, **sans**
collecte de facts (d'où `gather_facts: false` possible : tout vient de
l'inventaire). Le `| sort` fixe l'ordre : sans lui, l'ordre est celui de
l'inventaire, stable en pratique mais pas garanti. Le fichier ne contient
rien de propre à l'hôte (pas de ligne `127.0.1.1 <hostname>`), donc il est
identique partout — et le nom de chaque machine se résout par sa vraie IP
grâce à la boucle. `template` compare le rendu au fichier présent :
seconde passe `ok`.
:::

::: piege
Le fichier de template commence par un commentaire `#` : c'est du texte pour
Jinja2, pas une directive. En revanche un `{#` ouvre un commentaire Jinja2
— évite d'écrire `{# ` par accident dans un fichier de conf. Et
`lab-adm` n'est pas dans l'inventaire : si les cibles doivent le résoudre,
ajoute-le comme hôte (sans le mettre dans les groupes de déploiement) ou
comme ligne fixe dans le template.
:::

---

**E23.8** — *`sha256sum /etc/hosts` sur chaque hôte, afficher seulement
l'empreinte, jamais `changed`, `failed` si l'empreinte n'est pas
hexadécimale.*

```yaml
---
# playbooks/empreinte.yml
- name: Empreinte de /etc/hosts
  hosts: all
  gather_facts: false
  tasks:
    - name: Calculer l'empreinte
      ansible.builtin.command: sha256sum /etc/hosts
      register: r
      changed_when: false
      failed_when: r.stdout is not match('^[0-9a-f]{64} ')
      check_mode: false

    - name: Afficher l'empreinte seule
      ansible.builtin.debug:
        msg: "{{ inventory_hostname }} {{ r.stdout.split()[0] }}"
```

::: pourquoi
`changed_when: false` transforme un `command` en lecture pure : le recap ne
comptera jamais cette tâche comme un changement. `failed_when` remplace le
critère par défaut (`rc != 0`) par ton expression : ici, le test Jinja2
`match` applique la regex au **début** de `stdout` (`search` chercherait
n'importe où). `check_mode: false` autorise la commande en `--check`, ce qui
évite l'erreur de Q23.11 sur la tâche `debug` qui suit.

`r.stdout` est la sortie complète (`<hash>  /etc/hosts`) ; `.split()[0]` est
du Python appelé depuis Jinja2, ce qui marche pour une chaîne. On évite
ainsi le `debug: var=r` qui déverse tout le dictionnaire (`cmd`, `delta`,
`invocation`...).
:::

---

**E23.9** — *`vm.swappiness = 10` sur Ubuntu : d'abord `blockinfile` dans
`/etc/sysctl.d/90-lab.conf`, puis `ansible.posix.sysctl`. Comparer `sysctl
vm.swappiness`.*

Étape 1, `blockinfile` :

```yaml
---
# playbooks/sysctl-bloc.yml
- name: Swappiness via blockinfile
  hosts: ubuntu
  become: true
  tasks:
    - name: Bloc sysctl du lab
      ansible.builtin.blockinfile:
        path: /etc/sysctl.d/90-lab.conf
        create: true
        mode: "0644"
        marker: "# {mark} ANSIBLE MANAGED BLOCK lab23"
        block: |
          vm.swappiness = 10
```

```bash
ansible-playbook -K playbooks/sysctl-bloc.yml
ansible ubuntu -m ansible.builtin.command -a 'sysctl vm.swappiness'
# vm.swappiness = 60   <- le fichier est écrit, le noyau n'a rien vu
```

Étape 2, le module `sysctl` (on retire d'abord le bloc pour ne pas laisser
deux gestionnaires sur le même fichier) :

```yaml
---
# playbooks/sysctl.yml
- name: Swappiness via ansible.posix.sysctl
  hosts: ubuntu
  become: true
  tasks:
    - name: Retirer l'ancien bloc géré par blockinfile
      ansible.builtin.blockinfile:
        path: /etc/sysctl.d/90-lab.conf
        marker: "# {mark} ANSIBLE MANAGED BLOCK lab23"
        state: absent

    - name: vm.swappiness = 10, écrit et appliqué
      ansible.posix.sysctl:
        name: vm.swappiness
        value: "10"
        sysctl_file: /etc/sysctl.d/90-lab.conf
        sysctl_set: true
        reload: true
        state: present
```

```bash
ansible-playbook -K playbooks/sysctl.yml
ansible ubuntu -m ansible.builtin.command -a 'sysctl vm.swappiness'
# vm.swappiness = 10
```

::: pourquoi
`blockinfile` est un module de **fichier** : il écrit un bloc entre deux
marqueurs, et c'est tout. Le réglage ne sera appliqué qu'au prochain
redémarrage (ou à un `sysctl --system` que personne n'a lancé). Le module
`ansible.posix.sysctl` connaît la **sémantique** : il écrit la ligne dans
`sysctl_file`, et avec `sysctl_set: true` il applique aussi la valeur en
mémoire (`sysctl -w`) ; `reload: true` relance `sysctl -p <fichier>` pour
valider la syntaxe. Il compare valeur du fichier **et** valeur courante,
donc il est `changed` si l'un des deux diverge — c'est la définition même
d'un module qui gère un état.

Sortir `blockinfile` avant d'introduire `sysctl` évite un fichier à deux
propriétaires : le second réécrirait la ligne hors des marqueurs, et on
finirait avec `vm.swappiness` deux fois.
:::

---

**E23.10** — *Installer `nginx-ultra` dans un `block`, capturer l'échec dans
`rescue`, journaliser dans `always` sur le nœud de contrôle, `failed=0`.*

```yaml
---
# playbooks/block-rescue.yml
- name: Paquet inexistant, capture et journal
  hosts: all
  become: true
  tasks:
    - name: Installation encadrée
      block:
        - name: Installer nginx-ultra
          ansible.builtin.package:
            name: nginx-ultra
            state: present

        - name: Marquer le succès
          ansible.builtin.set_fact:
            statut: ok
      rescue:
        - name: Afficher la cause de l'échec
          ansible.builtin.debug:
            msg: "{{ ansible_failed_result.msg }}"

        - name: Marquer l'échec
          ansible.builtin.set_fact:
            statut: echec
      always:
        - name: Journaliser sur le nœud de contrôle
          ansible.builtin.lineinfile:
            path: "{{ playbook_dir }}/../rapports/paquets.log"
            create: true
            mode: "0644"
            line: >-
              {{ inventory_hostname }} ;
              {{ ansible_facts['date_time']['iso8601'] }} ;
              {{ statut }}
          delegate_to: localhost
          become: false
```

```bash
ansible-playbook -K playbooks/block-rescue.yml
cat rapports/paquets.log
# lab-web ; 2026-09-19T07:14:02Z ; echec
```

Recap attendu : `ok=4 changed=0 ... failed=0 rescued=1` par hôte.

::: pourquoi
`block/rescue/always` est le `try/except/finally` d'Ansible. Une tâche qui
échoue dans le `block` interrompt le bloc, exécute `rescue`, puis `always`,
et l'hôte n'est **pas** compté `failed` (il est `rescued`). Dans `rescue`,
`ansible_failed_task` et `ansible_failed_result` contiennent la tâche et son
résultat, d'où le `.msg` (`No package matching 'nginx-ultra' is available`
sur Ubuntu, `Failed to install some of the specified packages` sur Rocky).

`always` tourne dans tous les cas, y compris si le `rescue` échoue lui-même.
`delegate_to: localhost` avec `become: false` écrit sur `lab-adm` sans
`sudo` ; `playbook_dir` évite de dépendre du répertoire courant. La date
vient des facts de la cible (`ansible_facts['date_time']`), collectés en
début de play — pratique, mais c'est l'heure de la cible, pas du contrôleur.
:::

::: piege
Un `rescue` ne « répare » rien tout seul : si tu ne mets pas une action de
remédiation ou un `set_fact` dedans, tu as juste transformé une erreur
visible en erreur silencieuse. Et `set_fact` dans le `block` ne s'exécute
pas si la tâche précédente a échoué : `statut` n'est défini que par le
chemin réellement suivi, c'est bien ce qu'on veut.
:::

---

**E23.11** — *Sur `lab-web` : port 22 (`wait_for`), puis `uri` sur
`http://10.10.10.11/` avec 10 tentatives espacées de 3 s, `debug` « web
indisponible » ou code HTTP, sans échec du play.*

```yaml
---
# playbooks/sante-web.yml
- name: Santé de lab-web
  hosts: lab-web
  gather_facts: false
  tasks:
    - name: Le port SSH répond
      ansible.builtin.wait_for:
        host: "{{ ansible_host }}"
        port: 22
        timeout: 10

    - name: Interroger le frontal HTTP
      ansible.builtin.uri:
        url: "http://{{ ansible_host }}/"
        status_code: [200]
      register: r
      until: r.status == 200
      retries: 10
      delay: 3
      ignore_errors: true

    - name: Verdict
      ansible.builtin.debug:
        msg: >-
          {{ 'web indisponible' if r.status | default(-1) != 200
             else 'HTTP ' ~ r.status }}
```

::: pourquoi
`wait_for` sans `state` attend qu'un port soit **ouvert** (il boucle jusqu'à
`timeout`). `uri` avec `until`/`retries`/`delay` rejoue la requête tant que
la condition est fausse : sans nginx, chaque tentative renvoie
`status: -1` et `msg: Connection refused`. Après la dernière tentative, la
tâche est en échec — `ignore_errors: true` l'affiche en rouge `...ignoring`
mais laisse le play continuer, ce qui permet au `debug` de rendre le
verdict. Le recap montre `ignored=1`, pas `failed`.

La sortie `debug` utilise l'opérateur `~` (concaténation Jinja2, qui
convertit `r.status` en chaîne) et `default(-1)` par sécurité si `r` n'a pas
de `status`.
:::

::: piege
`failed_when: false` à la place d'`ignore_errors` casse la logique
d'`until` : chaque tentative est considérée réussie, la boucle s'arrête
dès la première, et tu n'as jamais tes 10 tentatives. `ignore_errors` agit
**après** l'épuisement des tentatives, c'est le bon niveau.
:::

---

**E23.12** — *`rapports/noyaux.txt` sur le nœud de contrôle, en une tâche
déléguée exécutée une fois, une ligne par hôte du play, à partir des facts.*

```yaml
---
# playbooks/noyaux.yml
- name: Rapport des noyaux du parc
  hosts: all
  tasks:
    - name: Écrire le rapport une seule fois sur lab-adm
      ansible.builtin.copy:
        content: |
          {% for h in ansible_play_hosts %}
          {{ h }} {{ hostvars[h]['ansible_facts']['kernel'] }} {{
            hostvars[h]['ansible_facts']['distribution'] }}
          {% endfor %}
        dest: "{{ playbook_dir }}/../rapports/noyaux.txt"
        mode: "0644"
      delegate_to: localhost
      run_once: true
      become: false
```

```bash
ansible-playbook playbooks/noyaux.yml && cat rapports/noyaux.txt
# lab-web 6.8.0-45-generic Ubuntu
# lab-db 6.8.0-45-generic Ubuntu
# lab-rhel 5.14.0-503.14.1.el9_5.x86_64 Rocky
# lab-ops 6.8.0-45-generic Ubuntu
```

::: pourquoi
Les facts de **tous** les hôtes sont collectés au début du play (un `setup`
par hôte, en parallèle) et rangés dans `hostvars[<hôte>]['ansible_facts']`.
Une tâche exécutée sur un seul hôte peut donc lire ceux des autres :
`run_once` la limite au premier hôte, `delegate_to: localhost` la fait
tourner sur `lab-adm`, et `ansible_play_hosts` liste les hôtes encore actifs
dans le play (ceux qui sont `UNREACHABLE` en sont retirés — le rapport
n'aura pas de ligne vide pour eux). Le `content:` de `copy` est un template
Jinja2 comme n'importe quelle valeur, boucles comprises.
:::

---

**E23.13** — *`encrypt_string` pour `vault_api_token`, affichage en clair,
`-v`, `no_log`, puis `ansible-vault view` du vault du setup.*

```bash
ansible-vault encrypt_string --name vault_api_token 'Sup3r-Secret'
```

```text
vault_api_token: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          36376138363330303935626633363537...
```

On colle ce bloc dans `inventory/group_vars/all/vars.yml`, avec la
référence en clair `api_token: "{{ vault_api_token }}"`, puis :

```yaml
---
# playbooks/secret.yml
- name: Secret et journaux
  hosts: lab-web
  gather_facts: false
  tasks:
    - name: Afficher le secret (démonstration, à ne pas garder)
      ansible.builtin.debug:
        var: api_token

    - name: Utiliser le secret dans une commande
      ansible.builtin.command: echo "{{ api_token }}"
      changed_when: false
      no_log: true
```

```bash
ansible-playbook playbooks/secret.yml
ansible-playbook playbooks/secret.yml -v       # puis -vvv
ansible-vault view inventory/group_vars/all/vault.yml
# vault_monitoring_token: "tok-lab23-3f9a1c7e"
```

::: pourquoi
`encrypt_string` chiffre **une valeur** et produit un scalaire YAML avec le
tag `!vault` : le fichier reste en clair, lisible, et seule cette valeur
est chiffrée — pratique pour un secret isolé, mais on préfère le fichier
`vault.yml` entier dès qu'il y en a plusieurs. Le mot de passe est lu depuis
`vault_password_file` d'`ansible.cfg`, d'où l'absence de prompt.

En `-v`, `debug` n'affiche rien de plus que son message. Mais la tâche
`command` sans `no_log` montre en `-v` le dictionnaire de résultat complet
: `cmd`, `stdout`, et `invocation.module_args` — le secret y figure trois
fois, et donc trois fois dans le journal de la CI. `no_log: true` remplace
tout par `the output has been hidden due to the fact that 'no_log: true'
was specified for this result`, à tous les niveaux de verbosité. Règle :
`no_log` sur **toute** tâche dont un paramètre ou une sortie contient un
secret (`user: password`, `uri: headers`, `postgresql_user`).
:::

::: piege
`no_log` cache aussi le message d'erreur en cas d'échec. Pour déboguer, on
passe temporairement `no_log: "{{ not debug_secrets | default(false) }}"` et
`-e debug_secrets=true` — jamais en supprimant la ligne dans un commit.
:::

---

**E23.14** — *`paquets.yml` + tâche `debug` taguée `info` : lister, filtrer
par tag, limiter, démarrer à une tâche ; compter les tâches exécutées.*

Ajout au playbook :

```yaml
    - name: Afficher la version du système
      ansible.builtin.debug:
        msg: "{{ ansible_facts['distribution'] }} \
              {{ ansible_facts['distribution_version'] }}"
      tags: [info]
```

```bash
ansible-playbook playbooks/paquets.yml --list-tasks
ansible-playbook playbooks/paquets.yml --list-tags
ansible-playbook -K playbooks/paquets.yml -t info
ansible-playbook -K playbooks/paquets.yml --skip-tags info
ansible-playbook -K playbooks/paquets.yml --limit lab-rhel
ansible-playbook -K playbooks/paquets.yml \
  --start-at-task 'Afficher la version du système'
```

| Cas | Tâches exécutées (hors `Gathering Facts`) |
|---|---|
| complet | 3 (cache apt, package, debug) ; cache `skipped` sur `lab-rhel` |
| `-t info` | 1 (debug) |
| `--skip-tags info` | 2 |
| `--limit lab-rhel` | 3 sur un seul hôte, cache apt `skipped` |
| `--start-at-task` | 1 (debug) |

::: pourquoi
Les tags sélectionnent des tâches, `--limit` sélectionne des hôtes,
`--start-at-task` saute jusqu'à un nom exact puis exécute tout ce qui
suit ; les trois se combinent. `Gathering Facts` porte le tag implicite
`always` : il tourne dans tous les cas, sauf `gather_facts: false`. Une
tâche `skipped` par un `when` compte comme « visitée » mais pas comme
exécutée : c'est la différence entre `ok` et `skipped` dans le recap.

`--list-tasks` et `--list-tags` ne se connectent à rien : ce sont les
premiers outils à sortir devant un playbook inconnu, avant même
`--check`.
:::

---

**E23.15** — *Rôle `motd` généré par `ansible-galaxy`, épuré, texte
paramétrable ; `community.general` épinglée dans `requirements.yml`,
installée, listée.*

```bash
cd ~/lab23
ansible-galaxy role init roles/motd
rm -r roles/motd/{tests,vars,files,handlers,meta}
tree roles/motd
# roles/motd
# ├── README.md
# ├── defaults/main.yml
# └── tasks/main.yml
```

```yaml
---
# roles/motd/defaults/main.yml
motd_text: "Parc géré par Ansible - ne pas modifier à la main"
```

```yaml
---
# roles/motd/tasks/main.yml
- name: Déployer /etc/motd
  ansible.builtin.copy:
    content: "{{ motd_text }}\n"
    dest: /etc/motd
    owner: root
    group: root
    mode: "0644"
```

```yaml
---
# playbooks/motd.yml
- name: Bannière du parc
  hosts: all
  become: true
  roles:
    - motd
```

```yaml
---
# collections/requirements.yml
collections:
  - name: ansible.posix
    version: ">=1.5.0,<3.0.0"
  - name: community.crypto
    version: ">=2.16.0,<3.0.0"
  - name: community.postgresql
    version: ">=3.4.0,<4.0.0"
  - name: community.general
    version: ">=9.0.0,<11.0.0"
```

```bash
ansible-galaxy collection install -r collections/requirements.yml
ansible-galaxy collection list
ansible-playbook -K playbooks/motd.yml -e motd_text='Bienvenue sur le lab'
```

```text
# /home/mathieu/lab23/collections/ansible_collections
Collection           Version
-------------------- -------
ansible.posix        2.0.0
community.crypto     2.26.1
community.general    10.7.0
community.postgresql 3.14.1
```

::: pourquoi
`ansible-galaxy role init` génère huit répertoires ; un rôle n'a besoin que
de ceux qu'il utilise, et un répertoire vide trompe le lecteur (`vars/`
suggère des constantes, `handlers/` un service à recharger). `tasks/
main.yml` est le seul obligatoire. Le rôle est trouvé grâce à `roles_path =
roles` dans `ansible.cfg`, et sa variable `motd_text` est surchargeable à
tous les niveaux au-dessus de `defaults` (ici par `-e`).

Épingler une collection (`>=9,<11`) fixe le comportement du dépôt : une
mise à jour majeure d'une collection peut renommer un module ou changer un
défaut. `collections_path = collections` fait installer dans le projet, pas
dans `~/.ansible/`, ce qui permet de l'ignorer dans Git et de le réinstaller
en CI avec la même commande.
:::

---

**E23.16** — *Depuis `comptes` : noms des admins, `alice,carol`, YAML
indenté, uid de `bob` sans boucle.*

```yaml
---
# playbooks/comptes-debug.yml
- name: Manipuler un dictionnaire de comptes sans boucle
  hosts: lab-web
  gather_facts: false
  vars:
    admins: >-
      {{ comptes | dict2items | selectattr('value.admin')
         | map(attribute='key') | list }}
  tasks:
    - name: Liste des admins
      ansible.builtin.debug:
        var: admins

    - name: Chaîne alice,carol
      ansible.builtin.debug:
        msg: "{{ admins | join(',') }}"

    - name: Variable entière en YAML
      ansible.builtin.debug:
        msg: "{{ comptes | to_nice_yaml(indent=2) }}"

    - name: uid de bob
      ansible.builtin.debug:
        msg: "{{ comptes['bob']['uid'] }}"
```

```text
ok: [lab-web] => {"admins": ["alice", "carol"]}
ok: [lab-web] => {"msg": "alice,carol"}
ok: [lab-web] => {"msg": "alice:\n  admin: true\n  shell: /bin/bash\n ..."}
ok: [lab-web] => {"msg": "2002"}
```

::: pourquoi
`dict2items` transforme `{alice: {...}, bob: {...}}` en liste
`[{key: alice, value: {...}}, ...]`, la forme sur laquelle `selectattr` et
`map` savent travailler. `selectattr('value.admin')` sans opérateur garde
les éléments dont l'attribut est « vrai » ; `map(attribute='key')` extrait
les noms ; `| list` matérialise. Tout le pipeline s'écrit une fois dans
`vars:` et se réutilise. `comptes['bob']['uid']` (ou `comptes.bob.uid`)
est un accès direct : un dictionnaire n'a pas besoin de boucle pour être
lu par clé.

`to_nice_yaml` et `to_nice_json` servent à écrire des fichiers de conf
structurés depuis un template (`{{ config | to_nice_yaml }}` dans un
`.j2`), ce qui évite de reproduire à la main la syntaxe YAML cible.
:::

---

## 23.6 Labs

### **L23.1** — Baseline commune du parc

*Compte de service `ansible`, paquets, fuseau et chrony, mises à jour
automatiques, sshd durci, pare-feu, node_exporter 1.9.1 ; `changed=0` en
seconde passe, `ansible-lint` muet.*

**Préalable** : le module `community.general.timezone` (et `ini_file`, `ufw`)
vient de `community.general`, absente du setup jusqu'à E23.15. Si ce n'est
pas déjà fait, ajoute-la à `collections/requirements.yml` et installe :

```bash
cd ~/lab23
ansible-galaxy collection install -r collections/requirements.yml
```

**Variables par groupe** (ajouts) :

```yaml
# inventory/group_vars/ubuntu.yml
---
sudo_group: sudo
ansible_python_interpreter: /usr/bin/python3
ssh_service_name: ssh
chrony_service_name: chrony
```

```yaml
# inventory/group_vars/rhel.yml
---
sudo_group: wheel
ansible_python_interpreter: /usr/bin/python3
ssh_service_name: sshd
chrony_service_name: chronyd
```

**Templates** :

```jinja
{# playbooks/templates/50-baseline.conf.j2 #}
# Managed by Ansible - baseline sshd du parc {{ lab_domain }}
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
MaxAuthTries 3
X11Forwarding no
AllowGroups sudo wheel
```

```jinja
{# playbooks/templates/node_exporter.service.j2 #}
# Managed by Ansible
[Unit]
Description=Prometheus node_exporter {{ node_exporter_version }}
After=network-online.target
Wants=network-online.target

[Service]
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter \
  --web.listen-address={{ node_exporter_listen }}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

**Le playbook**, découpé en plays par thème (un seul fichier, un seul
`ansible-playbook`) :

```yaml
---
# playbooks/baseline.yml — baseline commune du parc (Ubuntu 24.04, Rocky 9)
# 1re exécution : ansible-playbook -K playbooks/baseline.yml
# ensuite      : remote_user = ansible dans ansible.cfg, plus jamais de -K
- name: Prérequis par famille d'OS
  hosts: all
  become: true
  tasks:
    - name: Rocky | bindings SELinux pour copy/template/file
      ansible.builtin.dnf:
        name: python3-libselinux
        state: present
      when: ansible_facts['os_family'] == 'RedHat'

    - name: Ubuntu | cache apt frais (au plus une fois par heure)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'

- name: Compte de service ansible
  hosts: all
  become: true
  tasks:
    - name: Utilisateur ansible (uid 900, bash, groupe sudo/wheel)
      ansible.builtin.user:
        name: ansible
        uid: 900
        shell: /bin/bash
        groups: "{{ sudo_group }}"
        append: true
        create_home: true

    - name: Clé publique de mathieu@lab-adm
      ansible.posix.authorized_key:
        user: ansible
        key: "{{ lookup('ansible.builtin.file', '~/.ssh/id_ed25519.pub') }}"
        state: present

    - name: sudo sans mot de passe, validé par visudo
      ansible.builtin.copy:
        content: "ansible ALL=(ALL) NOPASSWD: ALL\n"
        dest: /etc/sudoers.d/ansible
        owner: root
        group: root
        mode: "0440"
        validate: visudo -cf %s

- name: Paquets, fuseau, heure, mises à jour automatiques
  hosts: all
  become: true
  vars:
    baseline_packages:
      - htop
      - vim
      - curl
      - tree
      - acl
      - chrony
  tasks:
    - name: Tronc commun de paquets
      ansible.builtin.package:
        name: "{{ baseline_packages }}"
        state: present

    - name: Ubuntu | unattended-upgrades
      ansible.builtin.apt:
        name: unattended-upgrades
        state: present
      when: ansible_facts['os_family'] == 'Debian'

    - name: Rocky | dnf-automatic
      ansible.builtin.dnf:
        name: dnf-automatic
        state: present
      when: ansible_facts['os_family'] == 'RedHat'

    - name: Fuseau Europe/Paris
      community.general.timezone:
        name: Europe/Paris

    - name: Chrony actif et activé (chrony vs chronyd)
      ansible.builtin.systemd_service:
        name: "{{ chrony_service_name }}"
        state: started
        enabled: true

    - name: Ubuntu | activer les mises à jour automatiques
      ansible.builtin.copy:
        dest: /etc/apt/apt.conf.d/20auto-upgrades
        content: |
          // Managed by Ansible
          APT::Periodic::Update-Package-Lists "1";
          APT::Periodic::Unattended-Upgrade "1";
        owner: root
        group: root
        mode: "0644"
      when: ansible_facts['os_family'] == 'Debian'

    - name: Rocky | dnf-automatic applique les mises à jour
      community.general.ini_file:
        path: /etc/dnf/automatic.conf
        section: commands
        option: apply_updates
        value: "yes"
        no_extra_spaces: false
        mode: "0644"
      when: ansible_facts['os_family'] == 'RedHat'

    - name: Rocky | timer dnf-automatic actif
      ansible.builtin.systemd_service:
        name: dnf-automatic.timer
        state: started
        enabled: true
      when: ansible_facts['os_family'] == 'RedHat'

- name: Durcissement sshd
  hosts: all
  become: true
  tasks:
    - name: Fichier de durcissement, validé par sshd -t
      ansible.builtin.template:
        src: templates/50-baseline.conf.j2
        dest: /etc/ssh/sshd_config.d/50-baseline.conf
        owner: root
        group: root
        mode: "0600"
        validate: sshd -t -f %s
      notify: Restart sshd
  handlers:
    - name: Restart sshd
      ansible.builtin.systemd_service:
        name: "{{ ssh_service_name }}"
        state: restarted

- name: Pare-feu
  hosts: all
  become: true
  tasks:
    - name: Ubuntu | ufw installé
      ansible.builtin.apt:
        name: ufw
        state: present
      when: ansible_facts['os_family'] == 'Debian'

    - name: Ubuntu | SSH autorisé avant toute activation
      community.general.ufw:
        rule: allow
        port: "22"
        proto: tcp
      when: ansible_facts['os_family'] == 'Debian'

    - name: Ubuntu | node_exporter depuis lab-ops seulement
      community.general.ufw:
        rule: allow
        port: "9100"
        proto: tcp
        from_ip: "{{ prometheus_host }}"
      when: ansible_facts['os_family'] == 'Debian'

    - name: Ubuntu | ufw actif, politique entrante deny
      community.general.ufw:
        state: enabled
        policy: deny
        direction: incoming
      when: ansible_facts['os_family'] == 'Debian'

    - name: Rocky | firewalld actif
      ansible.builtin.systemd_service:
        name: firewalld
        state: started
        enabled: true
      when: ansible_facts['os_family'] == 'RedHat'

    - name: Rocky | service ssh
      ansible.posix.firewalld:
        service: ssh
        permanent: true
        immediate: true
        state: enabled
      when: ansible_facts['os_family'] == 'RedHat'

    - name: Rocky | 9100/tcp depuis lab-ops seulement (rich rule)
      ansible.posix.firewalld:
        rich_rule: >-
          rule family="ipv4" source address="{{ prometheus_host }}/32"
          port port="9100" protocol="tcp" accept
        permanent: true
        immediate: true
        state: enabled
      when: ansible_facts['os_family'] == 'RedHat'

- name: Node exporter
  hosts: all
  become: true
  vars:
    node_exporter_version: "1.9.1"
    node_exporter_listen: "0.0.0.0:9100"
    node_exporter_base_url: >-
      https://github.com/prometheus/node_exporter/releases/download
    node_exporter_archive: >-
      node_exporter-{{ node_exporter_version }}.linux-amd64.tar.gz
    node_exporter_dir: >-
      /opt/node_exporter-{{ node_exporter_version }}.linux-amd64
  tasks:
    - name: Utilisateur système sans shell
      ansible.builtin.user:
        name: node_exporter
        system: true
        shell: /usr/sbin/nologin
        create_home: false

    - name: Archive vérifiée par sha256sums.txt (rien si déjà bonne)
      ansible.builtin.get_url:
        url: "{{ node_exporter_base_url }}/v{{ node_exporter_version }}/\
              {{ node_exporter_archive }}"
        dest: "/opt/{{ node_exporter_archive }}"
        checksum: "sha256:{{ node_exporter_base_url }}/v\
                   {{ node_exporter_version }}/sha256sums.txt"
        mode: "0644"

    - name: Extraction dans /opt (une seule fois)
      ansible.builtin.unarchive:
        src: "/opt/{{ node_exporter_archive }}"
        dest: /opt
        remote_src: true
        creates: "{{ node_exporter_dir }}/node_exporter"

    - name: Binaire dans /usr/local/bin (copie, pas lien, SELinux)
      ansible.builtin.copy:
        src: "{{ node_exporter_dir }}/node_exporter"
        dest: /usr/local/bin/node_exporter
        remote_src: true
        owner: root
        group: root
        mode: "0755"
      notify: Restart node_exporter

    - name: Unité systemd
      ansible.builtin.template:
        src: templates/node_exporter.service.j2
        dest: /etc/systemd/system/node_exporter.service
        owner: root
        group: root
        mode: "0644"
      notify: Restart node_exporter

    - name: Service actif et activé
      ansible.builtin.systemd_service:
        name: node_exporter
        daemon_reload: true
        state: started
        enabled: true
  handlers:
    - name: Restart node_exporter
      ansible.builtin.systemd_service:
        name: node_exporter
        daemon_reload: true
        state: restarted
```

**Exécution** :

```bash
cd ~/lab23
yamllint playbooks/baseline.yml && ansible-lint playbooks/baseline.yml
ansible-playbook -K playbooks/baseline.yml --check --diff --limit lab-ops
ansible-playbook -K playbooks/baseline.yml --limit lab-ops
ansible-playbook -K playbooks/baseline.yml
# bascule sur le compte de service
sed -i 's/^remote_user *=.*/remote_user        = ansible/' ansible.cfg
sed -i 's/^# become = True.*/become = True/' ansible.cfg
ansible all -m ansible.builtin.ping                      # sans -K
ansible-playbook playbooks/baseline.yml                  # changed=0
ansible-playbook playbooks/baseline.yml --check --diff   # aucun diff
ansible all -b -m ansible.builtin.shell \
  -a 'sshd -T | grep -i passwordauth; curl -s localhost:9100/metrics | head -1'
bash ~/workbook/scripts/check/check_M23_01.sh
```

::: pourquoi
**Ordre des plays.** `python3-libselinux` est installé en premier, par `dnf`
(qui n'en a pas besoin), parce que `authorized_key`, `copy` et `template`
en ont besoin sur un Rocky *enforcing*. Le compte de service vient ensuite
pour qu'en cas d'échec plus loin, la bascule `remote_user = ansible` soit
déjà possible. SSH et le pare-feu sont en fin de parcours, chacun dans son
play, pour pouvoir être testés séparément avec `--limit`.

**Idempotence des points sensibles.** `user` compare uid, shell, groupes.
`authorized_key` lit la clé depuis `lab-adm` via `lookup('file')` (exécuté
sur le contrôleur) et ne réécrit pas une ligne déjà présente. `copy` avec
`validate: visudo -cf %s` teste le fichier temporaire avant de le poser :
un sudoers cassé ne sort jamais du répertoire temporaire. `timezone`,
`systemd_service`, `ufw`, `firewalld` comparent l'état voulu à l'état réel.
`get_url` avec `checksum: sha256:<URL>` télécharge d'abord la petite liste
de sommes, y cherche la ligne du fichier `dest`, et hache le fichier local :
s'il correspond, rien n'est retéléchargé. `unarchive` avec `creates` et
`copy remote_src` (compare les sommes) complètent la chaîne.

**Handlers par play.** Un handler n'est visible que dans le play qui le
déclare : `Restart sshd` est dans le play sshd, `Restart node_exporter`
dans le play node_exporter. Le `daemon_reload: true` du handler garantit
que systemd relit l'unité avant de redémarrer.

**Pare-feu.** Sur ufw, `rule: allow` avant `state: enabled` : ufw applique
la politique `deny` au moment de l'activation, et une session SSH en cours
survit (conntrack) mais pas la suivante. Sur firewalld, `ssh` est dans la
zone `public` par défaut, mais on le déclare quand même : la baseline doit
être vraie même sur un firewalld reconfiguré. `permanent + immediate`
écrit la règle **et** l'applique sans `--reload`.
:::

::: piege
**`AllowGroups sudo wheel`** : si ton compte n'est ni dans `sudo` ni dans
`wheel`, `sshd -t` accepte et tu es dehors. Sur ce parc, `mathieu` et
`ansible` sont dans le bon groupe, mais c'est le genre de ligne à tester
avec `--limit lab-ops` et une console ouverte.

**`checksum: sha256:<URL>`** : la liste `sha256sums.txt` de node_exporter
contient plusieurs lignes ; Ansible cherche celle dont le nom de fichier
correspond au **basename de `dest`**. Si tu nommes le fichier `ne.tar.gz`
(comme dans Q23.14), aucune ligne ne correspond et la tâche échoue avec
`Unable to find a checksum for file`. D'où le `dest` qui garde le nom
d'origine.

**`ssh.service` sur Ubuntu 24.04** est activé par socket (`ssh.socket`).
`state: restarted` sur `ssh.service` fonctionne, mais si tu changes le port
dans la conf, c'est le socket qu'il faut reconfigurer.
:::

---

### **L23.2** — Frontal nginx : vhost templaté et TLS

*Variables `web`/`ubuntu`/`rhel`, nginx + `python3-cryptography`, clé, CSR
et certificat auto-signé sur la cible, vhost 80 → 443 templaté avec en-tête
`X-Vitrine-Version`, `index.html`, handler `Reload nginx`, pare-feu,
vérification `uri`.*

**Variables** :

```yaml
# inventory/group_vars/web.yml
---
vitrine_server_name: vitrine.lab.local
vitrine_root: /srv/vitrine
vitrine_tls_dir: /etc/nginx/tls
vitrine_version: "1.0.0"
```

```yaml
# inventory/group_vars/ubuntu.yml (ajouts)
nginx_vhost_dir: /etc/nginx/sites-enabled
nginx_user: www-data
```

```yaml
# inventory/group_vars/rhel.yml (ajouts)
nginx_vhost_dir: /etc/nginx/conf.d
nginx_user: nginx
```

**Templates** :

```jinja
{# playbooks/templates/vitrine.conf.j2 #}
# Managed by Ansible - vhost vitrine ({{ inventory_hostname }})
server {
    listen 80;
    server_name {{ vitrine_server_name }} {{ ansible_host }};
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name {{ vitrine_server_name }} {{ ansible_host }};

    ssl_certificate     {{ vitrine_tls_dir }}/vitrine.crt;
    ssl_certificate_key {{ vitrine_tls_dir }}/vitrine.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    root {{ vitrine_root }};
    index index.html;
    add_header X-Vitrine-Version "{{ vitrine_version }}" always;
    access_log /var/log/nginx/vitrine.access.log;
    error_log  /var/log/nginx/vitrine.error.log;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

```jinja
{# playbooks/templates/index.html.j2 #}
<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><title>vitrine</title></head>
<body>vitrine {{ vitrine_version }} sur {{ inventory_hostname }}</body>
</html>
```

**Le playbook** :

```yaml
---
# playbooks/nginx.yml — frontal vitrine en HTTPS (Ubuntu et Rocky)
- name: Frontal nginx vitrine
  hosts: web
  become: true

  tasks:
    - name: nginx et bindings cryptographiques Python
      ansible.builtin.package:
        name:
          - nginx
          - python3-cryptography
        state: present

    - name: Rocky | outils SELinux (semanage) pour sefcontext
      ansible.builtin.dnf:
        name: policycoreutils-python-utils
        state: present
      when: ansible_facts['os_family'] == 'RedHat'

    - name: Ubuntu | retirer le vhost par défaut
      ansible.builtin.file:
        path: /etc/nginx/sites-enabled/default
        state: absent
      when: ansible_facts['os_family'] == 'Debian'
      notify: Reload nginx

    - name: Répertoire TLS
      ansible.builtin.file:
        path: "{{ vitrine_tls_dir }}"
        state: directory
        owner: root
        group: root
        mode: "0750"

    - name: Clé privée (générée sur la cible, jamais copiée)
      community.crypto.openssl_privatekey:
        path: "{{ vitrine_tls_dir }}/vitrine.key"
        type: RSA
        size: 2048
        owner: root
        group: root
        mode: "0600"

    - name: CSR avec CN et SAN DNS + IP
      community.crypto.openssl_csr:
        path: "{{ vitrine_tls_dir }}/vitrine.csr"
        privatekey_path: "{{ vitrine_tls_dir }}/vitrine.key"
        common_name: "{{ vitrine_server_name }}"
        subject_alt_name:
          - "DNS:{{ vitrine_server_name }}"
          - "DNS:{{ inventory_hostname }}.{{ lab_domain }}"
          - "IP:{{ ansible_host }}"
        owner: root
        group: root
        mode: "0644"

    - name: Certificat auto-signé
      community.crypto.x509_certificate:
        path: "{{ vitrine_tls_dir }}/vitrine.crt"
        csr_path: "{{ vitrine_tls_dir }}/vitrine.csr"
        privatekey_path: "{{ vitrine_tls_dir }}/vitrine.key"
        provider: selfsigned
        selfsigned_not_after: "+365d"
        owner: root
        group: root
        mode: "0644"
      notify: Reload nginx

    - name: Racine du site
      ansible.builtin.file:
        path: "{{ vitrine_root }}"
        state: directory
        owner: "{{ nginx_user }}"
        group: "{{ nginx_user }}"
        mode: "0755"

    - name: Page d'accueil
      ansible.builtin.template:
        src: templates/index.html.j2
        dest: "{{ vitrine_root }}/index.html"
        owner: "{{ nginx_user }}"
        group: "{{ nginx_user }}"
        mode: "0644"

    - name: Rocky | contexte SELinux de la racine du site
      community.general.sefcontext:
        target: "{{ vitrine_root }}(/.*)?"
        setype: httpd_sys_content_t
        state: present
      when: ansible_facts['os_family'] == 'RedHat'

    - name: Rocky | appliquer le contexte (changed seulement si relabel)
      ansible.builtin.command: restorecon -Rv {{ vitrine_root }}
      register: restorecon
      changed_when: "'Relabeled' in restorecon.stdout"
      when: ansible_facts['os_family'] == 'RedHat'

    # validate: nginx -t -c %s ne marche pas ici : %s est un fichier qui ne
    # contient qu'un bloc server {}, or nginx -t exige une configuration
    # complète (events {}, http {}). Le fichier est donc déployé, puis la
    # configuration globale est testée par une tâche dédiée : si elle
    # échoue, le play s'arrête et le handler Reload nginx ne tourne pas.
    - name: Vhost vitrine
      ansible.builtin.template:
        src: templates/vitrine.conf.j2
        dest: "{{ nginx_vhost_dir }}/vitrine.conf"
        owner: root
        group: root
        mode: "0644"
      notify: Reload nginx

    - name: Configuration nginx globale valide
      ansible.builtin.command: nginx -t
      changed_when: false

    - name: Service actif et activé
      ansible.builtin.systemd_service:
        name: nginx
        state: started
        enabled: true

    - name: Ubuntu | ufw 80 et 443
      community.general.ufw:
        rule: allow
        port: "{{ item }}"
        proto: tcp
      loop: ["80", "443"]
      when: ansible_facts['os_family'] == 'Debian'

    - name: Rocky | firewalld http et https
      ansible.posix.firewalld:
        service: "{{ item }}"
        permanent: true
        immediate: true
        state: enabled
      loop: [http, https]
      when: ansible_facts['os_family'] == 'RedHat'

    - name: Recharger avant de vérifier
      ansible.builtin.meta: flush_handlers

    - name: Le site répond en HTTPS avec la bonne version
      ansible.builtin.uri:
        url: "https://{{ ansible_host }}/"
        validate_certs: false
        return_content: true
      register: vitrine
      failed_when: >-
        vitrine.status != 200 or vitrine_version not in vitrine.content
      delegate_to: localhost
      become: false

  handlers:
    - name: Reload nginx
      ansible.builtin.systemd_service:
        name: nginx
        state: reloaded
```

```bash
cd ~/lab23
yamllint playbooks/nginx.yml && ansible-lint playbooks/nginx.yml
ansible-playbook playbooks/nginx.yml --check --diff
ansible-playbook playbooks/nginx.yml
ansible-playbook playbooks/nginx.yml            # changed=0
curl -sk -H 'Host: vitrine.lab.local' https://10.10.10.11/
curl -sk -H 'Host: vitrine.lab.local' https://10.10.10.13/
curl -skI https://10.10.10.11/ | grep -i x-vitrine
bash ~/workbook/scripts/check/check_M23_02.sh
```

::: pourquoi
**Portabilité par variables.** Tout ce qui diffère entre Ubuntu et Rocky est
une variable de groupe (`nginx_vhost_dir`, `nginx_user`) ou une tâche
conditionnée par `os_family`. Le template, lui, est unique : c'est
l'objectif « pas recopié à la main entre les deux distributions ».

**TLS sur la cible.** `openssl_privatekey`, `openssl_csr` et
`x509_certificate` sont idempotents : ils relisent le fichier existant et
ne le régénèrent que si un paramètre a changé (taille, CN, SAN). La clé ne
transite jamais par `lab-adm`. `python3-cryptography` est la bibliothèque
que ces modules utilisent **sur la cible**. Le SAN `IP:{{ ansible_host }}`
permet à `curl -k` comme à `uri` de dialoguer sur l'IP sans erreur de nom
(le `-k`/`validate_certs: false` reste nécessaire : la CA n'est pas
connue).

**Pourquoi pas `validate:` sur le vhost.** `nginx -t -c fichier` charge
`fichier` comme configuration **principale** ; un fragment `server {}`
sans `events {}` est refusé (`"server" directive is not allowed here`).
On teste donc la configuration globale après dépôt : si elle est
invalide, la tâche échoue, l'hôte sort du play, et ses handlers ne
tournent pas — nginx reste sur l'ancienne configuration valide. C'est un
compromis : le fichier faux est bien déposé sur le disque, mais pas
appliqué.

**`flush_handlers` avant `uri`.** Sans lui, `Reload nginx` tournerait
après la vérification, qui interrogerait l'ancien nginx (ou aucun, au
premier passage). Voir QO23.4.

**SELinux.** `sefcontext` enregistre la règle (`semanage fcontext`), et
`restorecon` l'applique ; `changed_when` sur la présence de `Relabeled`
dans la sortie garde la tâche idempotente. Sans ça, nginx sur Rocky répond
`403` avec `avc: denied { read }` dans `/var/log/audit/audit.log`.
:::

::: piege
Sur Ubuntu, `sites-enabled/default` écoute en `default_server` sur 80 :
s'il reste, un `curl http://10.10.10.11/` sans en-tête Host tombe sur lui.
Sur Rocky, le `server` par défaut de `nginx.conf` est aussi `default_server`
sur 80 : ne mets pas `default_server` dans le vhost, tu obtiendrais
`duplicate default server`. Les deux redirections vers 443 fonctionnent
grâce au `server_name` qui inclut l'IP.

`uri` délégué à `localhost` s'exécute avec `become: false` : sans lui,
Ansible tenterait `sudo` sur `lab-adm` avec le compte `mathieu`, et
demanderait un mot de passe que `-K` ne fournit pas au bon endroit.
:::

---

### **L23.3** — PostgreSQL : instance, base, utilisateur, accès réseau

*Paquets, `listen_addresses` par `postgresql_set`, base `vitrine` et rôle
`vitrine_app` (mot de passe en vault, `no_log`), `pg_hba` depuis
`10.10.10.11`, `ufw` 5432 depuis `lab-web`, vérification `psql` déléguée.*

**Secrets et variables** (`db.yml` n'existe pas encore : on crée le
répertoire `db/`) :

```bash
cd ~/lab23
mkdir -p inventory/group_vars/db
ansible-vault create inventory/group_vars/db/vault.yml
# dans l'éditeur :
# ---
# vault_vitrine_db_password: "Vitr1ne-Db-2026"
```

```yaml
# inventory/group_vars/db/vars.yml
---
vitrine_db_name: vitrine
vitrine_db_user: vitrine_app
vitrine_db_password: "{{ vault_vitrine_db_password }}"
vitrine_db_client: 10.10.10.11
pg_version: 16
pg_conf_dir: "/etc/postgresql/{{ pg_version }}/main"
pg_service: "postgresql@{{ pg_version }}-main.service"
```

**Le playbook** :

```yaml
---
# playbooks/postgresql.yml — base vitrine sur lab-db, accès depuis lab-web
- name: PostgreSQL pour la vitrine
  hosts: db
  become: true

  tasks:
    - name: Paquets (acl pour become_user postgres sans pipelining)
      ansible.builtin.apt:
        name:
          - postgresql
          - postgresql-contrib
          - python3-psycopg2
          - acl
        state: present
        update_cache: true
        cache_valid_time: 3600

    - name: Service actif et activé
      ansible.builtin.systemd_service:
        name: postgresql.service
        state: started
        enabled: true

    - name: listen_addresses (redémarrage requis, pas un reload)
      community.postgresql.postgresql_set:
        name: listen_addresses
        value: "localhost,10.10.10.12"
      become_user: postgres
      notify: Restart postgresql

    - name: Rôle applicatif
      community.postgresql.postgresql_user:
        name: "{{ vitrine_db_user }}"
        password: "{{ vitrine_db_password }}"
        state: present
      become_user: postgres
      no_log: true

    - name: Base vitrine, propriété du rôle applicatif
      community.postgresql.postgresql_db:
        name: "{{ vitrine_db_name }}"
        encoding: UTF-8
        template: template0
        owner: "{{ vitrine_db_user }}"
        state: present
      become_user: postgres

    - name: Tous les privilèges sur la base
      community.postgresql.postgresql_privs:
        db: "{{ vitrine_db_name }}"
        type: database
        roles: "{{ vitrine_db_user }}"
        privs: ALL
        state: present
      become_user: postgres

    - name: Entrée pg_hba pour lab-web
      community.postgresql.postgresql_pg_hba:
        dest: "{{ pg_conf_dir }}/pg_hba.conf"
        contype: host
        databases: "{{ vitrine_db_name }}"
        users: "{{ vitrine_db_user }}"
        source: "{{ vitrine_db_client }}/32"
        method: scram-sha-256
        state: present
      become_user: postgres
      notify: Reload postgresql

    - name: ufw 5432/tcp depuis lab-web seulement
      community.general.ufw:
        rule: allow
        port: "5432"
        proto: tcp
        from_ip: "{{ vitrine_db_client }}"

  handlers:
    - name: Restart postgresql
      ansible.builtin.systemd_service:
        name: "{{ pg_service }}"
        state: restarted

    - name: Reload postgresql
      ansible.builtin.systemd_service:
        name: "{{ pg_service }}"
        state: reloaded

- name: Vérification depuis le frontal
  hosts: lab-web
  become: true

  tasks:
    - name: Client PostgreSQL
      ansible.builtin.apt:
        name: postgresql-client
        state: present
        update_cache: true
        cache_valid_time: 3600

    - name: SELECT 1 via le réseau avec le compte applicatif
      ansible.builtin.command: >-
        psql -h {{ hostvars['lab-db']['ansible_host'] }}
        -U {{ hostvars['lab-db']['vitrine_db_user'] }}
        -d {{ hostvars['lab-db']['vitrine_db_name'] }} -tAc 'SELECT 1'
      environment:
        PGPASSWORD: "{{ hostvars['lab-db']['vitrine_db_password'] }}"
        PGCONNECT_TIMEOUT: "5"
      register: pg_check
      changed_when: false
      failed_when: pg_check.rc != 0 or pg_check.stdout != '1'
      no_log: true
```

```bash
cd ~/lab23
ansible-playbook playbooks/postgresql.yml
ansible-playbook playbooks/postgresql.yml               # changed=0
grep -rn vault_vitrine_db_password inventory/group_vars  # 1 réf en clair
ansible-vault view inventory/group_vars/db/vault.yml
# refus attendu depuis lab-adm (pas dans pg_hba, et ufw bloque) :
psql -h 10.10.10.12 -U vitrine_app -d vitrine -c 'select 1'
bash ~/workbook/scripts/check/check_M23_03.sh
```

::: pourquoi
**`postgresql_set`** modifie le paramètre par `ALTER SYSTEM`, dans
`postgresql.auto.conf`, et rapporte si un redémarrage est nécessaire ;
`listen_addresses` est un paramètre `postmaster` : redémarrage obligatoire,
d'où le handler `Restart` et non `Reload`. Aucun `lineinfile` sur
`postgresql.conf` : le fichier reste intact, `pg_conftool`/`SHOW` voient la
valeur, et un `ALTER SYSTEM RESET` annule proprement.

**Unités systemd.** Sur Ubuntu, `postgresql.service` est une unité
« parapluie » (`Type=oneshot`, `ExecReload=/bin/true`) qui tire
`postgresql@16-main.service`, la vraie instance. On **active**
`postgresql.service` (pour le démarrage) mais on **recharge/redémarre**
`postgresql@16-main.service`.

**Ordre rôle → base → privilèges.** `postgresql_db` avec `owner` exige que
le rôle existe. Le propriétaire de la base possède aussi le schéma
`public` (PostgreSQL 15+, via `pg_database_owner`) : `vitrine_app` peut
créer des tables. `postgresql_privs` sur `type: database` ajoute CONNECT,
CREATE, TEMP — redondant pour un propriétaire mais explicite, et
idempotent.

**`become_user: postgres`** : les modules `community.postgresql` se
connectent par socket Unix en `peer`, ce qui exige d'être l'utilisateur
`postgres`. Passer de `root` (become) à `postgres` (non privilégié)
impose à Ansible de rendre son fichier temporaire lisible par un autre
utilisateur : `setfacl` (paquet `acl`) ou pipelining. Le playbook a les
deux.

**Vérification déléguée.** Le play 2 tourne **sur** `lab-web` (pas de
`delegate_to` nécessaire : c'est un play dédié), lit les variables de
`lab-db` par `hostvars` (le vault est déchiffré pour tout l'inventaire),
passe le mot de passe par `environment:` (jamais sur la ligne de commande,
visible dans `ps`), et `no_log: true` empêche `-v` de montrer
`environment`. Le refus depuis `lab-adm` prouve que `pg_hba` et `ufw`
filtrent bien : `no pg_hba.conf entry for host "10.10.10.10"` si ufw
laissait passer, sinon `Connection timed out`.
:::

::: piege
`no_log: true` sur la tâche `psql` cache aussi le **message d'échec**. Si
le `SELECT 1` échoue, relance avec `-e debug_secrets=true` et `no_log: "{{
not (debug_secrets | default(false)) }}"` ; ou teste la connexion à la main
depuis `lab-web` avec `PGPASSWORD` lu via `ansible-vault view`.

`encoding: UTF-8` avec `template: template0` : `template1` peut avoir une
locale différente, et `CREATE DATABASE ... ENCODING` refuse alors
(`new encoding (UTF8) is incompatible with the encoding of the template
database`).
:::

---

### **L23.4** — Rolling update avec vérification de santé

*`serial: 1`, `max_fail_percentage: 0`, `assert` sur la version,
déploiement des templates de L23.2, `flush_handlers`, `uri` avec `until`,
contrôle de l'en-tête, journal `deploiements.log`, preuve en cas d'échec.*

```yaml
---
# playbooks/rolling.yml — mise à jour de la vitrine, un frontal à la fois
# usage : ansible-playbook playbooks/rolling.yml -e vitrine_version=2.1.0
- name: Rolling update de la vitrine
  hosts: web
  become: true
  serial: 1
  max_fail_percentage: 0

  pre_tasks:
    - name: La version respecte X.Y.Z
      ansible.builtin.assert:
        that:
          - vitrine_version is match('^[0-9]+\.[0-9]+\.[0-9]+$')
        fail_msg: "vitrine_version={{ vitrine_version }} n'est pas X.Y.Z"
        quiet: true

    - name: Annonce
      ansible.builtin.debug:
        msg: >-
          Mise à jour de {{ inventory_hostname }} vers {{ vitrine_version }}

  tasks:
    - name: Page d'accueil versionnée
      ansible.builtin.template:
        src: templates/index.html.j2
        dest: "{{ vitrine_root }}/index.html"
        owner: "{{ nginx_user }}"
        group: "{{ nginx_user }}"
        mode: "0644"

    - name: Vhost (l'en-tête X-Vitrine-Version change aussi)
      ansible.builtin.template:
        src: templates/vitrine.conf.j2
        dest: "{{ nginx_vhost_dir }}/vitrine.conf"
        owner: root
        group: root
        mode: "0644"
      notify: Reload nginx

    - name: Configuration nginx valide
      ansible.builtin.command: nginx -t
      changed_when: false

    - name: Recharger maintenant, avant la vérification
      ansible.builtin.meta: flush_handlers

  post_tasks:
    - name: Santé, code 200 et version dans le corps
      ansible.builtin.uri:
        url: "https://{{ ansible_host }}/"
        validate_certs: false
        return_content: true
      register: sante
      until: sante.status == 200 and vitrine_version in sante.content
      retries: 5
      delay: 2
      delegate_to: localhost
      become: false

    - name: L'en-tête annonce la bonne version
      ansible.builtin.assert:
        that:
          - sante.x_vitrine_version == vitrine_version
        fail_msg: "en-tête {{ sante.x_vitrine_version | default('absent') }}"
        quiet: true

    - name: Journal des déploiements (une ligne par lot)
      ansible.builtin.lineinfile:
        path: "{{ playbook_dir }}/../rapports/deploiements.log"
        create: true
        mode: "0644"
        line: >-
          {{ lookup('ansible.builtin.pipe', 'date -Is') }}
          {{ vitrine_version }}
          {{ ansible_play_batch | join(',') }}
      delegate_to: localhost
      run_once: true
      become: false

  handlers:
    - name: Reload nginx
      ansible.builtin.systemd_service:
        name: nginx
        state: reloaded
```

```bash
cd ~/lab23
ansible-playbook playbooks/rolling.yml --list-hosts
ansible-playbook playbooks/rolling.yml -e vitrine_version=2.1.0
curl -sk https://10.10.10.11/ ; curl -sk https://10.10.10.13/
cat rapports/deploiements.log
# preuve en cas d'échec : la racine n'existe pas, le template échoue
ansible-playbook playbooks/rolling.yml \
  -e vitrine_version=9.9.9 -e vitrine_root=/srv/inexistant
# -> fatal: [lab-web] ... Destination directory /srv/inexistant does not
#    exist ; NO MORE HOSTS LEFT ; lab-rhel absent du recap
curl -skI https://10.10.10.13/ | grep -i x-vitrine   # toujours 2.1.0
ansible-playbook playbooks/rolling.yml -e vitrine_version=2.1.0
bash ~/workbook/scripts/check/check_M23_04.sh
```

::: pourquoi
**Lot par lot.** Avec `serial: 1`, l'ensemble `pre_tasks → tasks →
handlers → post_tasks → handlers` est rejoué pour `lab-web`, puis pour
`lab-rhel`. `max_fail_percentage: 0` arrête tout dès qu'un lot a un échec.
`ansible_play_batch` liste les hôtes du lot courant (ici un seul), et
`run_once` s'applique **par lot** : le journal reçoit bien une ligne par
frontal, ce que demande l'énoncé.

**Handler avant vérification.** Le `Reload nginx` notifié par le vhost
serait, par défaut, exécuté après `tasks` — donc avant `post_tasks`,
en fait. Mais deux raisons de mettre `flush_handlers` explicitement : la
vérification pourrait un jour être déplacée dans `tasks`, et le
`nginx -t` doit avoir lieu **entre** le dépôt et le reload. L'ordre lisible
vaut mieux que l'ordre implicite.

**`uri` + `until`.** Le module renvoie les en-têtes de la réponse comme
attributs en minuscules avec `_` : `X-Vitrine-Version` devient
`sante.x_vitrine_version`. `until` rejoue jusqu'à 5 fois espacées de 2 s :
nginx peut mettre quelques centaines de millisecondes à recharger.
`return_content: true` est nécessaire pour `sante.content`.

**Preuve de l'échec.** `-e vitrine_root=/srv/inexistant` surcharge la
variable de groupe (extra vars gagnent) : `template` refuse d'écrire dans
un répertoire absent, `lab-web` échoue à la première tâche, le lot est à
100 % d'échec, le play s'arrête. `lab-rhel` n'a pas été touché, il sert
encore `2.1.0`. Et `lab-web` ? Son vhost n'a pas été modifié non plus (la
tâche a échoué avant) : il sert aussi encore `2.1.0`. C'est la bonne
propriété : l'échec le plus précoce possible, avant tout changement.
:::

::: piege
La version dans `vars:` de play ou dans `group_vars/web.yml` (`1.0.0`)
serait **écrasée** par `-e`. Après le déploiement de `2.1.0`, mets à jour
`group_vars/web.yml` : sinon, le prochain `nginx.yml` sans `-e` ramènera
`1.0.0` et rapportera `changed`. La source de vérité d'une version est le
dépôt, `-e` n'est que le geste de déploiement.
:::

---

### **L23.5** — Un rôle `node_exporter` réutilisable

*Rôle généré, épuré, `defaults` complets, `tasks` découpés, `include_tasks`
dynamique par famille d'OS, template, handler, `meta/main.yml`,
`argument_specs.yml`, README, `monitoring.yml`, preuve de la validation.*

```bash
cd ~/lab23
ansible-galaxy role init roles/node_exporter
rm -r roles/node_exporter/{tests,vars,files}
```

Arborescence finale :

```text
roles/node_exporter/
├── README.md
├── defaults/main.yml
├── handlers/main.yml
├── meta/main.yml
├── meta/argument_specs.yml
├── tasks/main.yml
├── tasks/install.yml
├── tasks/service.yml
├── tasks/firewall_Debian.yml
├── tasks/firewall_RedHat.yml
└── templates/node_exporter.service.j2
```

```yaml
---
# roles/node_exporter/defaults/main.yml
node_exporter_version: "1.9.1"
node_exporter_listen: "0.0.0.0:9100"
node_exporter_user: node_exporter
node_exporter_allowed_cidr: "10.10.10.14/32"
node_exporter_manage_firewall: true
node_exporter_extra_args: []
node_exporter_base_url: >-
  https://github.com/prometheus/node_exporter/releases/download
node_exporter_install_dir: /opt
node_exporter_bin: /usr/local/bin/node_exporter
```

```yaml
---
# roles/node_exporter/tasks/main.yml
- name: Installation
  ansible.builtin.include_tasks: install.yml

- name: Service
  ansible.builtin.include_tasks: service.yml

- name: Pare-feu selon la famille d'OS
  ansible.builtin.include_tasks: "firewall_{{ ansible_facts['os_family'] }}.yml"
  when: node_exporter_manage_firewall | bool
```

```yaml
---
# roles/node_exporter/tasks/install.yml
- name: Utilisateur système sans shell
  ansible.builtin.user:
    name: "{{ node_exporter_user }}"
    system: true
    shell: /usr/sbin/nologin
    create_home: false

- name: Archive vérifiée par sha256sums.txt
  ansible.builtin.get_url:
    url: "{{ node_exporter_base_url }}/v{{ node_exporter_version }}/\
          node_exporter-{{ node_exporter_version }}.linux-amd64.tar.gz"
    dest: "{{ node_exporter_install_dir }}/\
           node_exporter-{{ node_exporter_version }}.linux-amd64.tar.gz"
    checksum: "sha256:{{ node_exporter_base_url }}/v\
               {{ node_exporter_version }}/sha256sums.txt"
    mode: "0644"

- name: Extraction
  ansible.builtin.unarchive:
    src: "{{ node_exporter_install_dir }}/\
          node_exporter-{{ node_exporter_version }}.linux-amd64.tar.gz"
    dest: "{{ node_exporter_install_dir }}"
    remote_src: true
    creates: "{{ node_exporter_install_dir }}/\
              node_exporter-{{ node_exporter_version }}.linux-amd64/\
              node_exporter"

- name: Binaire en place (copie, contexte SELinux du binaire)
  ansible.builtin.copy:
    src: "{{ node_exporter_install_dir }}/\
          node_exporter-{{ node_exporter_version }}.linux-amd64/\
          node_exporter"
    dest: "{{ node_exporter_bin }}"
    remote_src: true
    owner: root
    group: root
    mode: "0755"
  notify: Restart node_exporter
```

```yaml
---
# roles/node_exporter/tasks/service.yml
- name: Unité systemd
  ansible.builtin.template:
    src: node_exporter.service.j2
    dest: /etc/systemd/system/node_exporter.service
    owner: root
    group: root
    mode: "0644"
  notify: Restart node_exporter

- name: Service actif et activé
  ansible.builtin.systemd_service:
    name: node_exporter
    daemon_reload: true
    state: started
    enabled: true
```

```yaml
---
# roles/node_exporter/tasks/firewall_Debian.yml
- name: ufw | port node_exporter depuis le CIDR autorisé
  community.general.ufw:
    rule: allow
    port: "{{ node_exporter_listen | split(':') | last }}"
    proto: tcp
    from_ip: "{{ node_exporter_allowed_cidr }}"
```

```yaml
---
# roles/node_exporter/tasks/firewall_RedHat.yml
- name: firewalld | rich rule node_exporter depuis le CIDR autorisé
  ansible.posix.firewalld:
    rich_rule: >-
      rule family="ipv4" source address="{{ node_exporter_allowed_cidr }}"
      port port="{{ node_exporter_listen | split(':') | last }}"
      protocol="tcp" accept
    permanent: true
    immediate: true
    state: enabled
```

```yaml
---
# roles/node_exporter/handlers/main.yml
- name: Restart node_exporter
  ansible.builtin.systemd_service:
    name: node_exporter
    daemon_reload: true
    state: restarted
```

```jinja
{# roles/node_exporter/templates/node_exporter.service.j2 #}
# Managed by Ansible (role node_exporter)
[Unit]
Description=Prometheus node_exporter {{ node_exporter_version }}
After=network-online.target
Wants=network-online.target

[Service]
User={{ node_exporter_user }}
Group={{ node_exporter_user }}
ExecStart={{ node_exporter_bin }} \
  --web.listen-address={{ node_exporter_listen }} \
  {{ node_exporter_extra_args | join(' ') }}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```yaml
---
# roles/node_exporter/meta/main.yml
galaxy_info:
  role_name: node_exporter
  author: mathieu
  description: Installe et supervise Prometheus node_exporter
  license: MIT
  min_ansible_version: "2.15"
  platforms:
    - name: Ubuntu
      versions: [jammy, noble]
    - name: Debian
      versions: [bookworm]
    - name: EL
      versions: ["9"]
  galaxy_tags: [monitoring, prometheus]
dependencies: []
```

```yaml
---
# roles/node_exporter/meta/argument_specs.yml
argument_specs:
  main:
    short_description: Installe node_exporter depuis GitHub, en service.
    options:
      node_exporter_version:
        type: str
        default: "1.9.1"
        description: Version publiée sur GitHub (sans le v).
      node_exporter_listen:
        type: str
        default: "0.0.0.0:9100"
        description: Adresse et port d'écoute (--web.listen-address).
      node_exporter_user:
        type: str
        default: node_exporter
        description: Utilisateur système qui exécute le service.
      node_exporter_allowed_cidr:
        type: str
        default: "10.10.10.14/32"
        description: Source autorisée à joindre le port par le pare-feu.
      node_exporter_manage_firewall:
        type: bool
        default: true
        description: Ouvre le port avec ufw (Debian) ou firewalld (RedHat).
      node_exporter_extra_args:
        type: list
        elements: str
        default: []
        description: Options supplémentaires passées au binaire.
      node_exporter_base_url:
        type: str
        description: Base des URL de téléchargement (miroir interne).
      node_exporter_install_dir:
        type: str
        default: /opt
        description: Répertoire d'extraction des archives.
      node_exporter_bin:
        type: str
        default: /usr/local/bin/node_exporter
        description: Chemin du binaire installé.
```

```markdown
# node_exporter

Installe Prometheus node_exporter (archive GitHub vérifiée par sha256),
crée un utilisateur système, une unité systemd, et ouvre le port pour un
CIDR donné (ufw ou firewalld).

## Prérequis
- Debian 12 / Ubuntu 22.04+ / Rocky 9 ; accès HTTPS à github.com (ou
  `node_exporter_base_url` vers un miroir) ; collections `community.general`
  et `ansible.posix`.

## Variables (defaults/main.yml)
| Variable | Défaut | Rôle |
|---|---|---|
| `node_exporter_version` | `1.9.1` | version à installer |
| `node_exporter_listen` | `0.0.0.0:9100` | adresse d'écoute |
| `node_exporter_allowed_cidr` | `10.10.10.14/32` | source autorisée |
| `node_exporter_manage_firewall` | `true` | gérer le pare-feu |
| `node_exporter_extra_args` | `[]` | options du binaire |

## Exemple
    - hosts: all
      become: true
      roles:
        - role: node_exporter
          vars:
            node_exporter_extra_args: ["--collector.systemd"]
```

```yaml
---
# playbooks/monitoring.yml
- name: Node exporter sur tout le parc
  hosts: all
  become: true
  roles:
    - role: node_exporter
      vars:
        node_exporter_allowed_cidr: "{{ prometheus_host }}/32"
```

Dans `baseline.yml`, le play « Node exporter » devient :

```yaml
- name: Node exporter
  hosts: all
  become: true
  roles:
    - role: node_exporter
      vars:
        node_exporter_allowed_cidr: "{{ prometheus_host }}/32"
```

```bash
cd ~/lab23
ansible-lint roles/node_exporter
ansible-playbook playbooks/monitoring.yml
ansible-playbook playbooks/monitoring.yml          # changed=0
ansible-playbook playbooks/monitoring.yml -e node_exporter_manage_firewall=oui
bash ~/workbook/scripts/check/check_M23_05.sh
```

Message attendu avec la valeur `oui` :

```text
TASK [node_exporter : Validating arguments against arg spec 'main'] ****
fatal: [lab-web]: FAILED! => {"argument_errors": ["argument
'node_exporter_manage_firewall' is of type <class 'str'> and we were
unable to convert to bool: The value 'oui' is not a valid boolean.  Valid
booleans include: 'y', 'on', '1', 'false', 't', 'yes', 'true', 'no', 'off',
'n', 'f', '0'"], "changed": false, "msg": "Validation of arguments failed"}
```

::: pourquoi
**Rien qui dépende de l'inventaire.** Le rôle ne connaît ni `lab-ops` ni
`prometheus_host` : il expose `node_exporter_allowed_cidr` avec un défaut
raisonnable, et c'est le **playbook** qui fait le lien avec l'inventaire
(`"{{ prometheus_host }}/32"`). L'autre équipe passera son propre CIDR.
Idem pour l'URL de base (miroir interne) et les chemins.

**`include_tasks` dynamique.** `firewall_{{ ansible_facts['os_family']
}}.yml` sélectionne le fichier à l'exécution ; un OS non prévu (`Suse`)
échoue avec un message clair (`Could not find or access
'firewall_Suse.yml'`), ce qui est préférable à un `when` silencieux.
`include_tasks` (dynamique) plutôt qu'`import_tasks` (statique) parce que
le nom dépend d'un fact, inconnu au moment de l'analyse.

**`argument_specs.yml`** est validé **avant** la première tâche du rôle,
par une tâche automatique `Validating arguments against arg spec`. Le
typage (`bool`, `list`/`elements: str`) convertit les valeurs acceptables
(`-e node_exporter_manage_firewall=false` devient un booléen) et rejette les
autres avec la liste des valeurs valides. Sans `argument_specs`, `oui`
aurait été une chaîne non vide, donc **vraie** dans `when:` — le pare-feu
aurait été géré, contrairement à ce que l'appelant croyait demander.

**`ansible-galaxy role init` a créé `tests/` et `vars/`** : le premier est
un vestige (Molecule le remplace), le second est le piège de QO23.6.
:::

::: piege
Le `when: node_exporter_manage_firewall | bool` sur l'`include_tasks` est
une double sécurité : même sans `argument_specs`, une chaîne `"false"`
serait convertie. Et `split(':') | last` extrait le port de
`node_exporter_listen` quel que soit l'hôte d'écoute — mais pas pour une
adresse IPv6 entre crochets ; documente cette limite dans le README plutôt
que de la découvrir en production.
:::

---

## 23.7 Break & Fix

### **BF23.1** — « Le playbook de Julien marche, mais il faut le lancer deux fois »

*`casse/prepa-deploy.yml` : échoue sur `lab-rhel`, échoue au second passage
sur `lab-web`, puis `changed` à chaque fois et `sudoers.d/deploy` qui
s'allonge. Réécrire tâche par tâche, sans supprimer d'intention.*

**Diagnostic pas à pas**

```bash
cd ~/lab23
cat casse/prepa-deploy.yml
ansible-lint casse/prepa-deploy.yml        # avant même de lancer
ansible-playbook casse/prepa-deploy.yml --check --diff --limit lab-web
ansible-playbook casse/prepa-deploy.yml
ansible-playbook casse/prepa-deploy.yml    # 2e passage
ansible web -b -m ansible.builtin.command -a 'cat /etc/sudoers.d/deploy'
```

Ce qu'on lit :

* `ansible-lint` : `no-changed-when` sur cinq tâches `shell`, `command-
  instead-of-shell`, `command-instead-of-module` (`useradd`, `mkdir`,
  `chown`, `systemctl`), `risky-file-permissions` sur le `copy`,
  `name[casing]`. Le diagnostic est déjà là.
* Passage 1, `lab-rhel` : `fatal: ... apt ... Failed to find required
  executable "apt-get"` (le module `apt` sur un `dnf`). Sur `lab-web`,
  tout est `changed` (7 tâches).
* Passage 2, `lab-web` : `useradd: user 'deploy' already exists` (rc=9),
  puis, une fois commentée, `mkdir: cannot create directory '/srv/deploy':
  File exists`.
* Passage 3 et suivants : `chown`, `echo >>` et `systemctl restart`
  réussissent toujours, donc `changed` toujours, et une ligne de plus dans
  `/etc/sudoers.d/deploy` — qui n'est d'ailleurs jamais validé et pas en
  `0440`.

**Cause racine** : chaque intention est exprimée comme une **action** shell
(« crée », « ajoute », « redémarre ») au lieu d'un **état** (« existe avec
ces attributs », « contient exactement ceci », « tourne »). Les actions
échouent quand l'état est déjà atteint, ou réussissent sans rien changer en
le disant quand même. Plus un module non portable (`apt`) et un chemin
propre à Ubuntu (`/var/www/html`).

**Correctif** — `casse/prepa-deploy.yml` réécrit :

```yaml
---
# prepa-deploy.yml — prépare les frontaux pour l'appli vitrine
# Réécriture idempotente et portable ; l'intention de chaque tâche
# d'origine est conservée, le commentaire dit ce qui la rendait fragile.
- name: Préparation des frontaux
  hosts: web
  become: true
  vars:
    # fragile : /var/www/html n'existe que sur Debian/Ubuntu
    nginx_html_dir: >-
      {{ '/usr/share/nginx/html' if ansible_facts['os_family'] == 'RedHat'
         else '/var/www/html' }}

  tasks:
    # fragile : module apt -> échec sur Rocky ; update_cache sans
    # cache_valid_time -> changed à chaque passage
    - name: Nginx installé
      ansible.builtin.package:
        name: nginx
        state: present

    # non idempotent : useradd échoue (rc 9) si le compte existe déjà
    - name: Compte deploy
      ansible.builtin.user:
        name: deploy
        shell: /bin/bash
        create_home: true

    # non idempotent : mkdir sans -p échoue si le dossier existe ;
    # la tâche « droits » séparée était toujours changed -> fusionnées
    - name: Dossier de release avec ses droits
      ansible.builtin.file:
        path: /srv/deploy
        state: directory
        owner: deploy
        group: deploy
        mode: "0750"

    # non idempotent : echo >> ajoute une ligne à chaque passage ;
    # jamais validé par visudo, mode non maîtrisé
    - name: Sudo pour deploy (reload nginx seulement)
      ansible.builtin.copy:
        content: "deploy ALL=(ALL) NOPASSWD: /bin/systemctl reload nginx\n"
        dest: /etc/sudoers.d/deploy
        owner: root
        group: root
        mode: "0440"
        validate: visudo -cf %s

    # fragile : dest codé pour Ubuntu, mode absent (dépend de l'umask)
    - name: Page de maintenance
      ansible.builtin.copy:
        src: maintenance.html
        dest: "{{ nginx_html_dir }}/maintenance.html"
        owner: root
        group: root
        mode: "0644"

    # non idempotent : shell systemctl restart = redémarrage à chaque
    # passage. Intention conservée : nginx tourne, et il est redémarré
    # seulement si sa configuration change (handler).
    - name: Nginx actif et activé
      ansible.builtin.systemd_service:
        name: nginx
        state: started
        enabled: true

  handlers:
    - name: Restart nginx
      ansible.builtin.systemd_service:
        name: nginx
        state: restarted
```

```bash
ansible-lint casse/prepa-deploy.yml          # muet
ansible-playbook casse/prepa-deploy.yml      # changed sur les 2 hôtes
ansible-playbook casse/prepa-deploy.yml      # changed=0 sur les 2 hôtes
ansible web -b -m ansible.builtin.command -a 'visudo -cf /etc/sudoers.d/deploy'
```

**Prévention** : `ansible-lint` en pre-commit et en CI avec le profil
`production` (il refuse `shell` sans `changed_when`, les commandes qui ont
un module, les `copy` sans `mode`) ; la règle « un `shell` doit justifier
en commentaire pourquoi aucun module ne convient » ; et un test
d'idempotence systématique (deux passages, le second `changed=0`) dans la
CI, ce que Molecule fait nativement.

::: pourquoi
Le handler `Restart nginx` n'est notifié par aucune tâche de ce playbook :
c'est voulu. Aucune des tâches ne touche à la configuration de nginx (la
page de maintenance est du contenu, pas de la conf). L'intention « nginx
redémarré » de Julien était en réalité « nginx tourne après mon playbook »,
ce que `state: started` exprime ; le handler est là pour le jour où une
tâche de configuration sera ajoutée — et pour satisfaire l'objectif « ne
redémarre nginx que si sa configuration a changé ».

Le `nginx_html_dir` calculé dans `vars:` avec une expression conditionnelle
Jinja2 évite deux tâches `copy` avec deux `when`. En dépôt propre, cette
valeur irait dans `group_vars/ubuntu.yml` et `group_vars/rhel.yml`, comme
`nginx_vhost_dir` de L23.2.
:::

::: piege
« Commenter les tâches qui gênent » (ce que Julien a fait) est la mauvaise
réponse par excellence : le playbook ne crée plus l'utilisateur sur une
machine neuve, et personne ne le sait avant la prochaine réinstallation.
`ignore_errors: true` a le même effet en plus discret. La question à poser
devant une tâche qui échoue au second passage n'est pas « comment la faire
taire » mais « quel état veut-elle obtenir ».
:::

---

### **BF23.2** — « Le groupe db a disparu »

*`ansible db -m ping` : `Could not match supplied host pattern` ; `all` ne
ping que `localhost`. Interdit : restaurer l'ancien fichier.*

**Diagnostic pas à pas**

```bash
cd ~/lab23
ansible all -m ansible.builtin.ping 2>&1 | head -20
```

```text
[WARNING]:  * Failed to parse /home/mathieu/lab23/inventory/hosts.yml with
yaml plugin: We were unable to read either as JSON nor YAML, these are the
errors we saw: ... found character '\t' that cannot start any token
  in "<unicode string>", line 30, column 1
[WARNING]:  * Failed to parse /home/mathieu/lab23/inventory/hosts.yml with
ini plugin: Invalid host pattern 'all:' supplied, ending in ':' is not
allowed, this character is reserved to provide a port.
[WARNING]: Unable to parse /home/mathieu/lab23/inventory/hosts.yml as an
inventory source
[WARNING]: No inventory was parsed, only implicit localhost is available
[WARNING]: provided hosts list is empty, only localhost is available. Note
that the implicit localhost does not match 'all'
```

Le **premier** avertissement est le seul qui compte : le plugin `yaml`
n'a pas pu lire le fichier, et il dit où (`line 30, column 1`, un
caractère `\t`). Les suivants sont des conséquences : Ansible essaie les
autres plugins d'inventaire (`ini`, `toml`...), tous échouent sur un
fichier YAML, puis il tombe sur l'inventaire implicite `localhost`.

```bash
yamllint inventory/hosts.yml
# 30:1  error  syntax error: found character '\t' that cannot start any
#              token (syntax)
grep -nP '\t' inventory/hosts.yml           # ligne 30 : la tabulation
python3 -c 'import yaml,sys; yaml.safe_load(open("inventory/hosts.yml"))'
```

Après correction de la tabulation, second contrôle :

```bash
ansible-inventory --graph
```

```text
@all:
  |--@ungrouped:
  |--@web:
  |  |--lab-web
  |  |--lab-rhel
  |--@db:
  |  |--lab_db
  ...
```

`db` contient `lab_db` (souligné) : un **nouvel** hôte, sans `ansible_host`,
créé par la faute de frappe, alors que `lab-db` est retombé dans
`ungrouped`. `ansible db -m ping` répondrait maintenant `UNREACHABLE` sur
`lab_db` (nom non résoluble). Deuxième erreur trouvée.

**Cause racine** : deux erreurs d'édition. Une tabulation en début de ligne
(`\tlab-db:` sous `ubuntu.hosts`), interdite par YAML pour l'indentation,
qui **empêche l'analyse du fichier entier** ; et `lab_db` au lieu de
`lab-db` dans le groupe `db`, syntaxiquement valide, sémantiquement
fausse.

**Correctif** (sans réécrire le fichier) :

```bash
sed -i 's/^\tlab-db:/        lab-db:/' inventory/hosts.yml   # 8 espaces
sed -i 's/^        lab_db:$/        lab-db:/' inventory/hosts.yml
yamllint inventory/hosts.yml
ansible-inventory --graph
ansible db -m ansible.builtin.ping      # lab-db | SUCCESS
ansible all -m ansible.builtin.ping     # 4 SUCCESS, aucun WARNING
```

**Pourquoi une seule ligne fausse fait disparaître tout l'inventaire** :
une source d'inventaire est un **fichier** analysé en une fois par un
plugin. Le plugin `yaml` charge le document YAML entier ; une erreur de
syntaxe n'est pas localisée à une clé, c'est le document qui n'existe pas.
Ansible n'a alors **aucun** hôte, pas « tous sauf un groupe ». Le
fallback est l'inventaire implicite : `localhost`, qui n'appartient pas à
`all` — d'où le dernier avertissement.

**Prévention** : `yamllint inventory/` en pre-commit (il refuse les
tabulations et les incohérences d'indentation) ; `ansible-inventory
--graph` dans la CI, avec une comparaison au nombre d'hôtes attendu
(`ansible-inventory --list | jq '._meta.hostvars | length'` doit valoir 4)
; un éditeur configuré pour insérer des espaces sur les fichiers YAML
(`.editorconfig` : `indent_style = space`).

::: pourquoi
Les avertissements d'inventaire sont émis dans l'ordre des tentatives :
plugin par plugin, dans l'ordre d'`enable_plugins`. Le message du plugin
`ini` (`Invalid host pattern 'all:'`) est un faux indice tentant : il
décrit comment un fichier YAML ressemble à un mauvais INI. Lire le
**premier** avertissement, celui du plugin correspondant au format réel
du fichier, et s'arrêter là, fait gagner dix minutes.
:::

::: piege
Le trait d'union contre le souligné est invisible dans un `--graph` lu trop
vite. Les noms d'hôtes Ansible sont libres (le souligné est accepté), donc
aucune erreur n'est levée : seul `ansible_host` manquant trahit le nouvel
hôte, par un `UNREACHABLE` sur un nom que le DNS ne connaît pas. Un
`host_vars/lab-db.yml` (E23.6) ne s'appliquerait plus non plus.
:::

---

### **BF23.3** — « Le vault ne s'ouvre plus »

*`Attempting to decrypt but no vault secrets found`, puis, après un
bricolage, `Decryption failed`. Un mail de Julien dans `casse/`. Rechiffrer
avec le mot de passe d'équipe, remettre `ansible.cfg` en état.*

**Diagnostic pas à pas**

```bash
cd ~/lab23
ansible all -m ansible.builtin.ping
# ERROR! Attempting to decrypt but no vault secrets found
grep -n vault ansible.cfg
# 10:# vault_password_file = .vault_pass      <- commentée
ls -l .vault_pass                             # présent, 0600
head -1 inventory/group_vars/all/vault.yml    # $ANSIBLE_VAULT;1.1;AES256
```

Premier message : `group_vars/all/vault.yml` est chargé pour **tout** hôte
(groupe `all`), il est chiffré, et Ansible n'a **aucun** mot de passe à
essayer parce que la ligne `vault_password_file` a été commentée. Même un
`ping` a besoin des variables de l'inventaire, donc même un `ping` échoue.

On rétablit la ligne (le « bricolage » de l'énoncé) :

```bash
sed -i 's/^# *vault_password_file/vault_password_file/' ansible.cfg
ansible all -m ansible.builtin.ping
# ERROR! Decryption failed (no vault secrets were found that could decrypt)
ansible-vault view inventory/group_vars/all/vault.yml     # même erreur
cat casse/mail-julien.txt
```

Second message : cette fois un mot de passe **a été fourni** (celui de
`.vault_pass`), il a été essayé, il ne déchiffre pas. Le fichier a donc été
chiffré avec un autre mot de passe. Le mail de Julien le confirme et le
donne : `Julien-Temp-2026!`.

**Cause racine** : un membre de l'équipe a rechiffré (`ansible-vault
rekey`) un fichier partagé avec un mot de passe personnel, et a commenté
`vault_password_file` dans le `ansible.cfg` **du dépôt** pour son confort
local.

**Correctif** : rouvrir avec le mot de passe de Julien, rechiffrer avec
celui de l'équipe, sans jamais écrire le mot de passe de Julien sur le
disque :

```bash
cd ~/lab23
ansible-vault view --vault-id julien@prompt \
  inventory/group_vars/all/vault.yml           # prompt : Julien-Temp-2026!
# vault_monitoring_token: "tok-lab23-3f9a1c7e"    <- les valeurs sont là
ansible-vault rekey --vault-id julien@prompt \
  --new-vault-password-file .vault_pass \
  inventory/group_vars/all/vault.yml
# Rekey successful
ansible-vault view inventory/group_vars/all/vault.yml   # avec .vault_pass
ansible all -m ansible.builtin.ping                     # 4 SUCCESS
grep -n '^vault_password_file' ansible.cfg              # rétabli
```

**Prévention** — la règle à proposer :

* le mot de passe du vault est celui de l'**équipe**, stocké dans le
  gestionnaire de mots de passe ; `.vault_pass` est dans `.gitignore`, et
  chacun le recrée localement — on ne « teste depuis un portable perso »
  qu'avec ce mot de passe, jamais avec un autre ;
* si plusieurs mots de passe sont légitimes (prod / lab, ou par équipe),
  on utilise des **vault IDs** (`ansible-vault encrypt --vault-id
  prod@prompt`, en-tête `$ANSIBLE_VAULT;1.2;AES256;prod`), déclarés dans
  `ansible.cfg` par `vault_identity_list = prod@.vault_prod, lab@.vault_lab`
  : Ansible sait alors **quel** mot de passe correspond à quel fichier ;
* un test CI qui fait `ansible-vault view` de chaque `vault.yml` avec le
  mot de passe d'équipe : un rekey sauvage casse le pipeline avant le
  week-end, pas le lundi ;
* `ansible.cfg` est versionné : toute modification passe par une revue.

::: pourquoi
`rekey` déchiffre avec l'ancien secret et rechiffre avec le nouveau, en
place ; il ne modifie pas les valeurs. `--vault-id julien@prompt` demande
le mot de passe à l'écran et l'étiquette `julien` ; `--new-vault-password-
file .vault_pass` fournit le nouveau. Le fichier résultant porte l'en-tête
`1.1` (sans étiquette) parce que le nouveau secret n'a pas d'ID : c'est
exactement l'état de départ du setup.

La différence entre les deux messages est un outil de diagnostic à part
entière (Q23.13) : le premier dit « configure un mot de passe », le second
dit « ce n'est pas le bon » — et donc « qui l'a changé, quand » : `git log
-p inventory/group_vars/all/vault.yml` montre la date du rekey (le blob
change entièrement), ce qui, en dépôt, aurait désigné Julien sans mail.
:::

::: piege
Écrire le mot de passe de Julien dans un fichier (`echo ... > /tmp/j`)
puis `--vault-password-file /tmp/j` marche, mais laisse une trace sur le
disque et dans l'historique du shell (`~/.bash_history`). `@prompt` évite
les deux. Si tu l'as fait quand même : `history -d`, `shred -u /tmp/j`, et
Julien change son mot de passe personnel (le mail le prévoyait).
:::

---

### **BF23.4** — « On change le vhost, nginx ne bouge pas »

*`casse/vhost-update.yml` change `X-Vitrine-Version` : fichier modifié sur
les deux hôtes, `curl -skI` montre l'ancienne version, `lab-web` en erreur,
`lab-rhel` sans erreur. Trois mécanismes distincts.*

**Diagnostic pas à pas**

```bash
cd ~/lab23
cat casse/vhost-update.yml
ansible-lint casse/vhost-update.yml
ansible-playbook casse/vhost-update.yml -v
```

Ce qu'on lit dans la sortie :

```text
TASK [Deployer le vhost] ******************************************
ok: [lab-web]                 <- le fichier change, mais « ok » ?
ok: [lab-rhel]
TASK [Verifier que le vhost est bien en place] *********************
fatal: [lab-web]: FAILED! => {"cmd": ["grep", "-q", "X-Vitrine-Version",
"/etc/nginx/conf.d/vitrine.conf"], "rc": 2, "stderr": "grep:
/etc/nginx/conf.d/vitrine.conf: No such file or directory"}
ok: [lab-rhel]
PLAY RECAP
lab-rhel : ok=3 changed=0 ... failed=0
lab-web  : ok=2 changed=0 ... failed=1
```

Aucune ligne `RUNNING HANDLER`. Pourtant, avec `-v` ou un `--diff`, on voit
que le template a bien été réécrit (et `ansible web -b -m command -a 'grep
X-Vitrine /etc/nginx/sites-enabled/vitrine.conf /etc/nginx/conf.d/vitrine.
conf'` confirme `1.0.1` sur les deux). Trois mécanismes se superposent :

1. **Commun aux deux hôtes** : `changed_when: false` sur la tâche
   `template`. La tâche est forcée à `ok` même quand elle écrit le
   fichier ; une tâche `ok` ne **notifie pas**. C'est la raison pour
   laquelle il n'y a aucun `RUNNING HANDLER` nulle part.
2. **`lab-web`** : la tâche de vérification `grep` cible
   `/etc/nginx/conf.d/vitrine.conf`, chemin Rocky ; sur Ubuntu le vhost
   est dans `/etc/nginx/sites-enabled/`. La tâche échoue, l'hôte sort du
   play, et les handlers d'un hôte en échec ne sont **jamais** exécutés
   (sauf `--force-handlers`). Même sans le mécanisme 1, `lab-web` n'aurait
   pas rechargé.
3. **`lab-rhel`** : le handler porte `when: "'ubuntu' in group_names"`.
   `lab-rhel` est dans `rhel`, pas dans `ubuntu` : le handler serait
   `skipped` même s'il était notifié. Même sans le mécanisme 1, `lab-rhel`
   n'aurait pas rechargé.

Le fichier est modifié dans les deux cas parce que `changed_when` ne change
que le **rapport**, pas l'action.

**Cause racine** : trois erreurs indépendantes, chacune suffisante à faire
taire le handler sur au moins un hôte : un `changed_when: false` posé sur
une tâche qui change réellement quelque chose (probablement pour « avoir
un recap propre »), un chemin codé en dur au lieu de la variable de groupe
`nginx_vhost_dir`, et une condition sur le handler qui ne correspond pas
aux hôtes du play.

**Correctif** — `casse/vhost-update.yml` :

```yaml
---
# vhost-update.yml — change la version annoncée par le vhost vitrine
# usage : ansible-playbook casse/vhost-update.yml -e vitrine_version=1.0.2
- name: Mise à jour du vhost vitrine
  hosts: web
  become: true

  tasks:
    - name: Déployer le vhost
      ansible.builtin.template:
        src: ../playbooks/templates/vitrine.conf.j2
        dest: "{{ nginx_vhost_dir }}/vitrine.conf"
        owner: root
        group: root
        mode: "0644"
      # plus de changed_when: false -> la tâche notifie quand elle écrit
      notify: Reload nginx

    - name: Vérifier que le vhost est bien en place
      ansible.builtin.command:
        cmd: grep -q X-Vitrine-Version {{ nginx_vhost_dir }}/vitrine.conf
      changed_when: false

    - name: Configuration nginx valide
      ansible.builtin.command: nginx -t
      changed_when: false

  handlers:
    - name: Reload nginx
      ansible.builtin.systemd_service:
        name: nginx
        state: reloaded
      # plus de when: le handler doit tourner sur tout hôte modifié
```

Preuve demandée :

```bash
ansible-playbook casse/vhost-update.yml -e vitrine_version=1.0.2
# RUNNING HANDLER [Reload nginx] : changed: [lab-web] changed: [lab-rhel]
curl -skI https://10.10.10.11/ | grep -i x-vitrine     # 1.0.2
curl -skI https://10.10.10.13/ | grep -i x-vitrine     # 1.0.2
ansible-playbook casse/vhost-update.yml -e vitrine_version=1.0.2
# template ok, aucun RUNNING HANDLER, changed=0
ansible-playbook casse/vhost-update.yml -e vitrine_version=1.0.0 \
  --limit lab-web
# handler une seule fois, sur lab-web seulement
```

(Le `vars: vitrine_version` du fichier d'origine a été retiré : la version
vient de `group_vars/web.yml` ou de `-e`, comme dans L23.4. Remets ensuite
`group_vars/web.yml` en cohérence avec ce qui est déployé.)

**Prévention** : `ansible-lint` signale `no-handler`, les `when` sur
handlers sont un signal d'alerte en revue (un handler conditionnel est
presque toujours une tâche conditionnelle déguisée), et les chemins
propres à une distribution doivent venir de `group_vars`, jamais d'une
tâche. Test d'acceptation dans la CI : après un déploiement, `curl -I`
doit montrer la version attendue — c'est la vérification `uri` de L23.4,
qui aurait attrapé les trois mécanismes en une tâche.

::: pourquoi
Le cycle de vie d'un handler (QO23.4) tient en trois conditions : une
tâche **`changed`** (mécanisme 1), sur un hôte **sans échec** (mécanisme
2), avec un handler **dont les conditions sont vraies** (mécanisme 3).
Ce Break & Fix casse chacune des trois, et le symptôme est identique : le
fichier change, le service ne suit pas. La seule façon de les distinguer
est de lire la sortie tâche par tâche : `ok` là où on attendait `changed`,
`fatal` sur un hôte, absence de `RUNNING HANDLER`.

`changed_when: false` est légitime sur `command`/`shell` en lecture seule
(`grep`, `nginx -t`), jamais sur un module qui sait déjà dire s'il a
changé quelque chose. Un template `changed_when: false` est un mensonge,
et les handlers ne se déclenchent que sur la vérité.
:::

::: piege
Un `--force-handlers` aurait fait tourner le handler sur `lab-web` malgré
l'échec du `grep` — mais pas avec `changed_when: false`, et pas sur
`lab-rhel`. Il ne corrige qu'un mécanisme sur trois, tout en masquant une
erreur réelle. Le réflexe « `state: restarted` en fin de playbook pour
être sûr » (interdit par l'énoncé) masque les trois et redémarre nginx à
chaque passage : c'est Q23.1.
:::

---

## 23.8 Défi du module

**D23 — Le dépôt d'infra de référence**

*Un dépôt `~/lab23/factura-infra` : `site.yml` qui importe tout, quatre
rôles paramétrés, secrets en vault, `make lint/check/deploy`, README,
runbook, Git, et un rapport `D23-notes.md`.*

**Mise en place et arborescence**

```bash
mkdir -p ~/lab23/factura-infra && cd ~/lab23/factura-infra
git init -b main
mkdir -p inventory/group_vars/{all,web,db,ubuntu,rhel} inventory/host_vars \
  playbooks/templates roles docs
cp ~/lab23/.yamllint ~/lab23/.ansible-lint .
cp ~/lab23/inventory/hosts.yml inventory/
cp ~/lab23/.vault_pass .
for r in common nginx_vitrine postgresql_vitrine; do
  ansible-galaxy role init roles/$r && rm -r roles/$r/{tests,vars,files}
done
cp -r ~/lab23/roles/node_exporter roles/
```

```text
factura-infra/
  ansible.cfg  site.yml  requirements.yml  .ansible-lint  .yamllint
  .gitignore   README.md  Makefile
  inventory/hosts.yml
  inventory/group_vars/all/{vars.yml,vault.yml}
  inventory/group_vars/web/vars.yml
  inventory/group_vars/db/{vars.yml,vault.yml}
  inventory/group_vars/ubuntu/vars.yml
  inventory/group_vars/rhel/vars.yml
  playbooks/{baseline,nginx,postgresql,rolling,monitoring}.yml
  roles/common/{defaults,tasks,handlers,templates,meta}/  README.md
  roles/nginx_vitrine/{defaults,tasks,handlers,templates,meta}/  README.md
  roles/postgresql_vitrine/{defaults,tasks,handlers,meta}/  README.md
  roles/node_exporter/...
  docs/RUNBOOK.md
```

**Fichiers de tête**

```ini
# ansible.cfg
[defaults]
inventory          = inventory/hosts.yml
remote_user        = ansible
private_key_file   = ~/.ssh/id_ed25519
interpreter_python = auto_silent
forks              = 10
roles_path         = roles
collections_path   = collections
callback_result_format = yaml
vault_password_file = .vault_pass
retry_files_enabled = False

[privilege_escalation]
become        = True
become_method = sudo

[ssh_connection]
pipelining = True
ssh_args   = -o ControlMaster=auto -o ControlPersist=60s
```

```yaml
---
# site.yml — applique tout le parc, dans l'ordre des dépendances
- name: Baseline commune
  ansible.builtin.import_playbook: playbooks/baseline.yml

- name: Supervision
  ansible.builtin.import_playbook: playbooks/monitoring.yml

- name: Base de données
  ansible.builtin.import_playbook: playbooks/postgresql.yml

- name: Frontaux
  ansible.builtin.import_playbook: playbooks/nginx.yml
```

```yaml
---
# requirements.yml
collections:
  - name: ansible.posix
    version: ">=1.5.0,<3.0.0"
  - name: community.general
    version: ">=9.0.0,<11.0.0"
  - name: community.crypto
    version: ">=2.16.0,<3.0.0"
  - name: community.postgresql
    version: ">=3.4.0,<4.0.0"
```

```makefile
# Makefile
.PHONY: deps lint check deploy rolling
VERSION ?= 1.0.0

deps:
	ansible-galaxy collection install -r requirements.yml

lint:
	yamllint .
	ansible-lint

check:
	ansible-playbook site.yml --check --diff

deploy:
	ansible-playbook site.yml

rolling:
	ansible-playbook playbooks/rolling.yml -e vitrine_version=$(VERSION)
```

```text
# .gitignore
.vault_pass
*.retry
.cache/
collections/ansible_collections/
```

```yaml
---
# .ansible-lint
profile: production
exclude_paths:
  - collections/
  - .cache/
  - .git/
```

**Les playbooks deviennent des appels de rôles** : `playbooks/baseline.yml`

```yaml
---
- name: Baseline commune du parc
  hosts: all
  become: true
  roles:
    - role: common
```

et `playbooks/nginx.yml`, `playbooks/postgresql.yml`, `playbooks/monitoring.yml`
sur le même modèle (`nginx_vitrine` sur `web`, `postgresql_vitrine` sur
`db` avec le play de vérification sur `lab-web`, `node_exporter` sur
`all`). `playbooks/rolling.yml` est celui de L23.4, avec ses `pre_tasks` /
`post_tasks` et le rôle `nginx_vitrine` limité par tag :

```yaml
---
- name: Rolling update de la vitrine
  hosts: web
  become: true
  serial: 1
  max_fail_percentage: 0
  pre_tasks:
    - name: La version respecte X.Y.Z
      ansible.builtin.assert:
        that: vitrine_version is match('^[0-9]+\.[0-9]+\.[0-9]+$')
        quiet: true
  roles:
    - role: nginx_vitrine
      vars:
        nginx_vitrine_content_only: true
  tasks:
    - name: Recharger avant la vérification
      ansible.builtin.meta: flush_handlers
  post_tasks:
    - name: Santé en HTTPS
      ansible.builtin.uri:
        url: "https://{{ ansible_host }}/"
        validate_certs: false
        return_content: true
      register: sante
      until: sante.status == 200 and vitrine_version in sante.content
      retries: 5
      delay: 2
      delegate_to: localhost
      become: false
```

**Découpage des rôles** (le contenu vient des labs, déplacé tel quel) :

| Rôle | Provenance | `defaults/main.yml` |
|---|---|---|
| `common` | L23.1 sans node_exporter | `common_packages`, `common_timezone`, `common_ssh_allow_groups`, `common_service_user`, `common_service_uid`, `common_service_pubkey` |
| `nginx_vitrine` | L23.2 (+ tâches contenu/vhost taguées `content`, gardées par `nginx_vitrine_content_only`) | `vitrine_server_name`, `vitrine_root`, `vitrine_tls_dir`, `vitrine_version`, `nginx_vhost_dir`, `nginx_user` |
| `postgresql_vitrine` | L23.3 | `vitrine_db_name`, `vitrine_db_user`, `vitrine_db_password`, `vitrine_db_client`, `pg_version`, `pg_listen_addresses` |
| `node_exporter` | L23.5 | inchangé |

Exemple, `roles/common/tasks/main.yml` :

```yaml
---
- name: Prérequis selon la famille d'OS
  ansible.builtin.include_tasks: "prereq_{{ ansible_facts['os_family'] }}.yml"

- name: Compte de service
  ansible.builtin.import_tasks: service_account.yml

- name: Paquets, fuseau, heure, mises à jour
  ansible.builtin.import_tasks: packages.yml

- name: Durcissement sshd
  ansible.builtin.import_tasks: sshd.yml

- name: Pare-feu
  ansible.builtin.include_tasks: "firewall_{{ ansible_facts['os_family'] }}.yml"
```

et `roles/common/defaults/main.yml` :

```yaml
---
common_packages: [htop, vim, curl, tree, acl, chrony]
common_timezone: Europe/Paris
common_ssh_allow_groups: [sudo, wheel]
common_ssh_max_auth_tries: 3
common_service_user: ansible
common_service_uid: 900
common_service_pubkey: "{{ lookup('ansible.builtin.file',
                            '~/.ssh/id_ed25519.pub') }}"
common_monitoring_cidr: "{{ prometheus_host }}/32"
```

Rien de codé en dur : `prometheus_host`, `lab_domain`, `sudo_group`,
`ssh_service_name`, `chrony_service_name`, `nginx_vhost_dir`, `nginx_user`
viennent de `inventory/group_vars/`, et chaque rôle les référence via un
`defaults` qui les cite (ou un `default()` explicite).

**Secrets**

```bash
cd ~/lab23/factura-infra
cp ~/lab23/inventory/group_vars/all/vault.yml inventory/group_vars/all/
cp ~/lab23/inventory/group_vars/db/vault.yml  inventory/group_vars/db/
head -1 inventory/group_vars/*/vault.yml       # $ANSIBLE_VAULT;1.1;AES256
grep -rn 'vault_' inventory/group_vars/*/vars.yml   # références seulement
git grep -i secret                              # rien en clair
```

**README.md** (plan attendu) : Prérequis (`pipx install ansible-core
ansible-lint yamllint`, `make deps`, clé SSH de `mathieu` déployée, mot de
passe du vault dans le gestionnaire d'équipe → `.vault_pass` en 0600) ;
Déploiement (`make lint`, `make check`, `make deploy`, première fois avec
`-K` et `-e ansible_user=mathieu` tant que le compte `ansible` n'existe
pas) ; Rolling update (`make rolling VERSION=2.1.0`, ce qui se passe lot
par lot, comment revenir en arrière : `make rolling VERSION=2.0.0`) ;
tableau des variables ajustables par rôle (copié des `argument_specs`) ;
Molecule : ce que ferait `molecule test` sur `node_exporter` (`create` un
conteneur podman Rocky 9 et un Ubuntu 24.04 avec systemd, `converge`
applique le rôle, `idempotence` rejoue et exige `changed=0`, `verify`
interroge `:9100/metrics`, `destroy`).

**docs/RUNBOOK.md** :

| Symptôme | Diagnostic | Correctif |
|---|---|---|
| `UNREACHABLE` | `ssh -v ansible@<ip>` avec la même clé ; `-vvv` | clé, `known_hosts`, `sshd`, pare-feu, `ansible_host` |
| `Missing sudo password` | `sudo -n true` sur la cible en tant qu'`ansible` | `/etc/sudoers.d/ansible` (rôle `common`), ou `-K` |
| `/usr/bin/python3: not found` | `raw: which python3` | play `raw: apt/dnf install -y python3` avec `gather_facts: false` |
| handler muet | tâche `ok` au lieu de `changed` ? hôte en échec ? `when` sur le handler ? | retirer `changed_when: false`, corriger la tâche en échec, `--force-handlers` en dépannage |
| tâche `changed` à chaque passage | `--check --diff`, `ansible-lint` (`no-changed-when`) | module dédié, `creates`/`changed_when`, `cache_valid_time`, `checksum` |
| `Attempting to decrypt` / `Decryption failed` | `grep vault_password_file ansible.cfg`, `ansible-vault view` | `.vault_pass` depuis le gestionnaire ; `rekey` si mauvais mot de passe |

**Git** :

```bash
git add -A && git commit -m "chore: squelette du dépôt, ansible.cfg, lint"
git commit -m "feat(common): baseline du parc en rôle"
git commit -m "feat(node_exporter): rôle importé de L23.5"
git commit -m "feat(nginx_vitrine): frontal HTTPS templaté"
git commit -m "feat(postgresql_vitrine): base, rôle applicatif, pg_hba"
git commit -m "docs: README, RUNBOOK, Makefile"
git log --oneline
```

**Validation** :

```bash
make lint && make check && make deploy && make deploy   # 2e : changed=0
bash ~/workbook/scripts/check/check_M23_06.sh
```

**`~/lab23/rapports/D23-notes.md`** — les trois décisions à justifier :

1. *Découpage des rôles.* Un rôle par **responsabilité et par cycle de
   vie** : `common` change rarement et s'applique partout ; `nginx_vitrine`
   et `postgresql_vitrine` sont liés à une application et évoluent avec
   elle ; `node_exporter` est réutilisable ailleurs, donc isolé et
   documenté par `argument_specs`. Pas de rôle « web » fourre-tout : le
   jour où la vitrine change de serveur web, on ne réécrit pas la baseline.
2. *`defaults` vs `group_vars`.* Dans `defaults` : les valeurs qui ont un
   sens **quel que soit le parc** (`vitrine_root`, versions, ports,
   `manage_firewall`). Dans `group_vars` : ce qui **décrit le parc**
   (`prometheus_host`, `ansible_host`, `nginx_vhost_dir` par OS, mots de
   passe via vault). Test : « si je clone ce rôle sur un autre projet,
   cette valeur est-elle encore vraie ? » Oui → `defaults`, non →
   `group_vars`.
3. *Rollback du rolling update.* Le playbook s'arrête au premier échec
   (`max_fail_percentage: 0`), donc au pire un frontal est cassé et
   l'autre sert la version précédente. Procédure : retirer le frontal
   cassé du DNS/répartiteur si nécessaire, puis `make rolling
   VERSION=<précédente> ` avec `--limit` sur le frontal cassé : le même
   playbook, la même vérification `uri`, dans l'autre sens. Le journal
   `deploiements.log` donne la version précédente. Ce qui rend ça
   possible : le déploiement est **déclaratif et versionné** — la version
   N-1 est un `-e` de plus, pas une sauvegarde à restaurer. Ce qui ne
   revient pas en arrière tout seul : une migration de base ; c'est
   pourquoi `rolling.yml` ne touche pas à `postgresql_vitrine`.

::: pourquoi
`import_playbook` est **statique** : `site.yml --list-tasks`, `--tags`,
`--limit` traversent tous les playbooks importés, et une erreur de syntaxe
dans l'un d'eux est détectée avant la première tâche. L'ordre importe :
`common` crée le compte `ansible` dont les plays suivants ont besoin, et
`monitoring` avant `postgresql`/`nginx` pour que les frontaux soient
supervisés dès leur mise en service.

Le `Makefile` n'est pas de la décoration : c'est l'interface que la CI du
module 24 appellera (`make lint`, `make check`), et la garantie que
« déployer » est **une** commande identique sur tous les postes. `VERSION
?= 1.0.0` donne un défaut surchargeable (`make rolling VERSION=2.1.0`),
l'équivalent Make du `defaults/main.yml`.

Un dépôt qui passe `make lint && make check` sur un clone frais, avec le
seul `.vault_pass` comme état local, est un dépôt qu'un nouveau membre
peut appliquer le premier jour — c'est le critère.
:::

::: piege
Copier `hosts.yml` et les `group_vars` depuis `~/lab23` est légitime ;
copier `.vault_pass` **dans le dépôt** ne l'est pas : il y est, mais
ignoré par Git (`git check-ignore -v .vault_pass` doit le confirmer). Un
`git add -f .vault_pass` par réflexe et le secret est dans l'historique
pour toujours — la seule réparation est de changer le mot de passe et de
rechiffrer tous les vaults (`rekey`).

`ansible-lint` avec le profil `production` exige des `meta/main.yml`
complets (`platforms`, `min_ansible_version`) et des noms de rôle en
`snake_case` : `nginx-vitrine` serait refusé, d'où `nginx_vitrine`.
:::
