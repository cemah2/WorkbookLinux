# Module 24 — Corrigé

## 24.3 Quiz — QCM

**Q24.1** — *`tofu apply` relancé sans changement affiche `0 to add, 0 to
change, 0 to destroy`. Nom de la propriété ?*

**Réponse : b) l'idempotence**

::: pourquoi
Un outil déclaratif compare trois choses à chaque `plan` : le **code** (l'état
voulu), l'**état** (ce qu'il a créé la dernière fois) et la **réalité** (ce que
l'API répond au rafraîchissement). Quand les trois coïncident, le diff est
vide et l'apply ne fait rien : c'est la définition opérationnelle de
l'idempotence. Elle n'est pas magique : elle tient parce que chaque ressource
a une identité dans l'état (`lab["lab2-web"]` ↔ VMID 9102) et que le provider
sait relire chaque attribut. Dès qu'un attribut n'est pas relu correctement
(bug de provider, valeur calculée côté Proxmox), le plan n'est plus vide sans
que rien n'ait changé : on parle alors de *drift permanent*, et on le traite
avec une valeur explicite ou `ignore_changes` (L24.2, étape 3).
:::

::: piege
Le drift (a) est l'inverse : la réalité a bougé, le plan n'est pas vide.
L'immutabilité (c) est une stratégie (remplacer plutôt que modifier), pas une
propriété du plan. La « convergence » (d) est le vocabulaire Ansible pour la
même idée, mais Ansible n'a pas d'état : il converge en relisant la machine
à chaque tâche.
:::

---

**Q24.2** — *RAM augmentée à la main dans Proxmox, `memory` déclaré à 2048.*

**Réponse : b) `~ update in-place` qui ramène la mémoire à 2048**

::: pourquoi
`tofu plan` commence par un **refresh** : il interroge l'API pour chaque
ressource de l'état et met à jour la copie en mémoire (section `Note: Objects
have changed outside of OpenTofu`). Il compare ensuite cette réalité au code :
`memory.dedicated = 3072 -> 2048`. L'attribut `memory` n'est pas marqué
« forces replacement » chez bpg/proxmox (Proxmox sait changer la RAM d'une
VM par `qm set --memory`), donc le symbole est `~` et non `-/+`. Le code est
la source de vérité : l'apply ramène la VM à 2048. Si la modification
manuelle était volontaire, la bonne réponse est de **changer le code** (ou
`apply -refresh-only` pour accepter la réalité, L24.3).
:::

::: piege
« Proxmox a la priorité » (a) est exactement l'inverse du modèle déclaratif.
L'erreur `state lock` (d) n'a rien à voir : elle signale un autre `apply` en
cours ou un verrou orphelin.
:::

---

**Q24.3** — *Quelle ligne indique la cause de la recréation ?*

**Réponse : c) `~ vm_id = 9100 -> 9200 # forces replacement`**

::: pourquoi
Un plan a trois niveaux de lecture. `must be replaced` et `-/+` (a, d) disent
**ce qui** va se passer : destruction puis création. `~ id = "9102" ->
(known after apply)` (b) est une **conséquence** : la nouvelle instance
recevra un nouvel identifiant, inconnu tant qu'elle n'existe pas. Seule la
ligne annotée `# forces replacement` désigne l'**attribut responsable** :
ici `clone.vm_id`, que le provider déclare `ForceNew` parce que Proxmox ne
sait pas « re-cloner » une VM existante depuis un autre template. En revue de
plan, c'est cette annotation qu'on cherche en premier : elle dit si la
recréation est légitime (changement de template) ou accidentelle (faute de
frappe, renommage de ressource sans bloc `moved`).
:::

---

**Q24.4** — *User-data commençant par `# cloud-config` avec une espace.*

**Réponse : b) il l'ignore avec un avertissement `Unhandled non-multipart
userdata`**

::: pourquoi
cloud-init n'analyse pas le YAML « à l'aveugle » : il lit la **première
ligne** pour choisir le gestionnaire (`#cloud-config` → YAML de configuration,
`#!` → script, `#include` → URL, `#cloud-config-archive`…). `# cloud-config`
ne correspond à aucun en-tête connu : le contenu est classé
`text/x-not-multipart`, journalisé dans `/var/log/cloud-init.log` avec
`Unhandled non-multipart (text/x-not-multipart) userdata`, et **rien n'est
appliqué**. La VM démarre pourtant normalement, avec le hostname de l'image
et sans utilisateur : le symptôme ressemble à « pas de datasource » alors que
le datasource a bien été trouvé. `cloud-init schema --config-file` attrape
cette erreur avant le déploiement (E24.7).
:::

---

**Q24.5** — *`--cicustom user=` sur une VM qui avait `--ciuser`/`--sshkeys`.*

**Réponse : c) seul le snippet est appliqué ; `--ciuser`/`--sshkeys` sont
ignorés**

::: pourquoi
Proxmox génère trois fichiers dans l'ISO `cidata` : `user-data`,
`meta-data`, `network-config` (plus `vendor-data`). `- -cicustom user=...`
dit « pour le fichier `user-data`, prends ce snippet **au lieu** de ce que tu
aurais généré ». Les options `--ciuser`, `--cipassword`, `--sshkeys` ne
servent qu'à fabriquer le `user-data` généré : elles n'ont plus aucun effet.
Seul `vendor=` est **fusionné** par cloud-init avec le user-data (c'est
l'usage de `vendor-agent.yaml` fourni par le setup). `--ipconfig0` continue de
fonctionner car il alimente `network-config`, un fichier distinct. La preuve
se fait avec `qm cloudinit dump 9110 user` avant/après (L24.1, étape 3).
:::

---

**Q24.6** — *`count = 3`, on retire le premier élément de `var.names`.*

**Réponse : c) 2 to add, 3 to destroy : les index se décalent**

::: pourquoi
Avec `count`, l'identité d'une instance est son **index** : `lab[0]`,
`lab[1]`, `lab[2]`. Après suppression de `adm`, la liste vaut
`["web", "db"]` : `lab[0]` doit maintenant s'appeler `web` (il s'appelait
`adm`), `lab[1]` doit s'appeler `db`, et `lab[2]` n'a plus de définition.
Pour un `local_file` dont le nom est dans `filename` (E24.6), chaque
« renommage » est un `-/+` : le plan résume `2 to add, 0 to change,
3 to destroy`. La proposition d) annonce trois créations : il n'y a plus que deux éléments dans la liste, donc `lab[2]` n'est pas recréé. `for_each` indexe par clé : retirer `"adm"` donne
`1 to destroy` et rien d'autre.
:::

::: piege
Sur une vraie VM bpg/proxmox, la gravité dépend des attributs qui glissent :
un `name` seul se change sur place (`~`), mais un `vm_id` ou une IP dérivés
de l'index forcent la recréation. Dans les deux cas le plan touche **toutes**
les VM situées après celle retirée, et c'est le problème : on voulait en
supprimer une.
:::

---

**Q24.7** — *`variable "token" { sensitive = true }` et `output "t" { value =
var.token }`.*

**Réponses : a), b) et d)**

::: pourquoi
Trois faits vérifiables en E24.15 :

* sans `sensitive = true` sur l'**output**, `tofu plan` (et `validate`)
  s'arrête sur `Error: Output refers to sensitive values` : OpenTofu exige
  que tu confirmes l'intention d'exporter un secret (proposition a) ;
* une fois l'output marqué `sensitive`, `tofu output` affiche
  `t = <sensitive>`, mais `tofu output -raw t` **imprime la valeur** : le
  marquage protège l'affichage par défaut, pas l'accès (proposition b) ;
* la valeur est écrite **en clair** dans le tfstate (`resources[].instances[]
  .attributes` et `outputs.t.value`), comme toute valeur d'attribut
  (proposition d).

La seule proposition fausse est c) :
rien n'est chiffré ni omis dans l'état. Retiens surtout b) et d), qui sont celles qui comptent pour la sécurité;
a) décrit fidèlement le message d'erreur.
:::

::: piege
`sensitive` est un attribut d'**affichage**. Le secret vit dans l'état, dans
`plan.bin` (`tofu show plan.bin` l'affiche masqué, `tofu show -json plan.bin`
le donne en clair) et dans tout log de CI qui exécute `tofu output -raw`.
D'où : état chiffré ou sur un bucket privé, token à faible privilège, rotation
(QO24.6, BF24.3).
:::

---

**Q24.8** — *Faire oublier une ressource sans la détruire.*

**Réponse : b) `tofu state rm adr`**

::: pourquoi
L'état est la seule mémoire d'OpenTofu. `state rm` supprime l'entrée : au
prochain plan, la ressource n'existe plus « pour lui », mais l'objet Proxmox
est intact. Si le code la déclare encore, le plan propose de la **créer** (et
Proxmox refusera si le VMID est pris) ; si le code ne la déclare plus, plus
rien ne se passe. C'est l'outil de BF24.1 (l'état pointe vers une VM qui
n'est plus la nôtre) et du transfert d'une ressource vers un autre projet
(`state rm` ici, `import` là-bas). L'équivalent déclaratif depuis
OpenTofu 1.7 est le bloc `removed { from = adr  lifecycle { destroy = false
} }`, relisible en PR.
:::

::: piege
`destroy -target` (a) détruit. `-replace` (c) et `taint` (d) marquent la
ressource pour **destruction puis recréation** au prochain apply — l'inverse
de ce qu'on cherche.
:::

---

**Q24.9** — *Clone démarré sans IP ni utilisateur, `ipconfig0` présent mais pas
d'`ide2`.*

**Réponse : b) il manque le lecteur cloud-init : rien ne transporte les données
vers la VM**

::: pourquoi
Sur Proxmox, `--ipconfig0`, `--ciuser`, `--sshkeys`, `--cicustom` ne sont que
des **options de configuration** stockées dans `/etc/pve/qemu-server/9110.conf`.
Elles ne servent à rien tant qu'un lecteur `cloudinit` (`ide2:
local-lvm:cloudinit`) n'est pas attaché : c'est lui que Proxmox régénère au démarrage sous forme d'ISO étiquetée `cidata`, et c'est cette ISO que le
datasource NoCloud cherche au démarrage. Sans elle, ds-identify ne trouve
aucun datasource et cloud-init ne configure rien : la VM garde le hostname
`ubuntu` de l'image, pas de réseau statique, pas d'utilisateur. C'est
exactement BF24.4. `--full 1` (c) ne touche pas au cloud-init ; l'image
Ubuntu (d) accepte parfaitement une IP statique via `network-config`.
:::

---

**Q24.10** — *Backend S3 avec `use_lockfile = true`, apply coupé brutalement.*

**Réponse : b) `Error acquiring the state lock` ; on vérifie que personne ne
travaille, puis `tofu force-unlock <ID>`**

::: pourquoi
Avec `use_lockfile`, le verrou est un **objet** `lab2/terraform.tfstate.tflock`
posé dans le bucket avec une écriture conditionnelle (`If-None-Match`), qui
contient l'ID du verrou, qui l'a pris, quand et pour quelle opération. Un
processus tué ne passe jamais par la libération : l'objet reste. Au lancement
suivant, l'erreur affiche ce bloc `Lock Info` ; l'ID qu'il contient est celui
que `tofu force-unlock` exige, précisément pour t'obliger à lire qui détient
le verrou avant de le casser. Il n'y a **pas d'expiration** (c) : un verrou
sans TTL est le comportement voulu, mieux vaut un blocage qu'un état écrasé
par deux applies concurrents. L'état lui-même (a) n'est pas perdu : au pire
le dernier apply est partiellement appliqué, et un `plan` le montrera.
:::

---

**Q24.11** — *Changements possibles sans recréer la VM avec bpg/proxmox.*

**Réponses : a) et c)**

::: pourquoi
Le provider marque `ForceNew` uniquement ce que l'API Proxmox ne sait pas
changer sur un objet existant. `memory.dedicated` (a) se traduit par
`PUT /nodes/pve/qemu/<id>/config` avec `memory=2048` : mise à jour sur place,
la VM redémarre si nécessaire (le provider gère le `reboot`). Agrandir un
disque (c) est un `PUT .../resize` : Proxmox ne sait qu'**agrandir**, jamais
rétrécir, donc 20 → 30 est un `~` alors que 30 → 20 est refusé par le plan.
Changer `clone.vm_id` (b) demanderait de recloner : ForceNew. Changer `vm_id`
(d) revient à créer une autre VM : Proxmox n'a pas d'opération « renuméroter ».
:::

---

**Q24.12** — *Identifiant pour `tofu import` d'une VM.*

**Réponse : c) `pve/9004`**

::: pourquoi
Un VMID n'est unique que dans un cluster, mais le provider doit savoir sur
**quel nœud** appeler l'API (`/nodes/<node>/qemu/<vmid>`). L'identifiant
d'import bpg est donc `<node_name>/<vm_id>`, documenté comme
`first-node/4321`. Le nom (b) n'est pas un identifiant : deux VM peuvent
porter le même. `qemu/9004` (d) n'existe pas. Après import, `tofu state show
proxmox_virtual_environment_vm.rhel` montre `id = "9004"` et `node_name =
"pve"` : l'état stocke les deux champs séparément.
:::

---

**Q24.13** — *`templatefile("inv.tftpl", { vms = local.ips })` avec un
`%{ for }`.*

**Réponse : a) nulle part : c'est correct**

::: pourquoi
`templatefile(chemin, vars)` lit un fichier depuis le disque (chemin relatif
au répertoire courant, `path.module` étant la convention pour rester
portable, mais rien n'oblige) et l'évalue avec les variables de la map. La
syntaxe de template accepte l'interpolation `${...}` et les **directives**
`%{ for k, v in vms }` … `%{ endfor }`, `%{ if }` … `%{ endif }`. Les noms de
variables d'un template sont libres : `ansible_host` n'est un mot réservé
nulle part. Seule finesse, qui ne fait pas échouer mais donne un fichier faux : dans un **fichier** de template, `\n` n'est **pas** une séquence d'échappement (elle ne l' est que dans une chaîne HCL entre guillemets); il sort tel quel, antislash et `n`, et tout l'inventaire tient sur une ligne. On écrit un vrai retour à la ligne
dans le fichier, et les marqueurs `~` (`%{ for ~}`) avalent les blancs
autour des directives (L24.4, étape 5).
:::

---

**Q24.14** — *Premier boot de 4 minutes, des dizaines de lignes `apt`.*

**Réponse : b) `--ciupgrade` vaut 1 par défaut : upgrade complet au premier
boot**

::: pourquoi
Depuis Proxmox VE 8, l'option cloud-init `ciupgrade` existe et vaut **1**
par défaut : Proxmox ajoute `package_upgrade: true` au user-data généré, et
cloud-init fait un `apt-get dist-upgrade` complet au premier démarrage. Sur
une image cloud vieille de quelques semaines, c'est plusieurs dizaines de
paquets et plusieurs minutes, avec un boot qui « pend » sur le réseau apt.
`make-template.sh` pose `--ciupgrade 0` sur le template pour cette raison :
les mises à jour se font ensuite par Ansible, de façon contrôlée.
`package_update: true` (a) ne fait qu'un `apt-get update` : quelques
secondes. Un miroir injoignable (c) donnerait des timeouts, pas des dizaines
de lignes d'installation.
:::

---

**Q24.15** — *Attendre qu'une VM soit joignable avant de générer l'inventaire.*

**Réponse : b) le graphe de dépendances implicite dès que `content` référence
un attribut de la VM**

::: pourquoi
OpenTofu construit un graphe orienté : toute **référence** à un attribut
d'une ressource (`proxmox_virtual_environment_vm.lab["x"].ipv4_addresses`,
ou même `.name`) crée une arête, et la ressource référencée est créée
d'abord. Si `content` est calculé depuis ces attributs, `local_file`
attend la fin de la création de la VM — et, avec `agent { enabled = true }`,
« fin de la création » signifie « l'agent QEMU a répondu », donc la VM est
démarrée et joignable. `depends_on` (a) n'est nécessaire que si le contenu
ne référence **rien** de la VM (par exemple des IP calculées depuis
`var.vms` uniquement) ; c'est précisément le piège de L24.4 étape 5, résolu
en faisant sortir l'IP du module depuis un attribut de la ressource.
`sleep 60` (c) est un aveu d'échec.
:::

---

**Q24.16** — *Terraform ou Ansible pour installer nginx sur 100 VM ?*

**Réponse : b) Ansible : Terraform provisionne, Ansible configure ; les
provisioners sont un dernier recours documenté comme tel**

::: pourquoi
Terraform raisonne en **ressources d'API** : une VM, un disque, un
enregistrement DNS ont un état lisible et comparable. « nginx installé et
configuré » n'est pas une ressource d'API : Terraform ne peut ni le relire
ni le diff-er. Les `provisioner "remote-exec"` s'exécutent une fois à la
création, ne sont pas idempotents, ne se rejouent pas si le script change,
et la documentation HashiCorp elle-même les classe en *last resort*. Ansible
fait l'inverse : pas d'état, mais chaque module relit la machine et converge.
L'enchaînement propre est celui de L24.4 : outputs → inventaire → playbook.
L'argument « Terraform a un état » (d) est vrai et hors sujet : l'état ne
décrit pas l'intérieur des VM.
:::

---

## 24.4 Quiz — questions ouvertes

**QO24.1** — *Rôle du fichier d'état : pourquoi, contenu, applies concurrents,
git.*

**Réponse attendue.**

1. **Pourquoi un état ?** L'API ne connaît pas le lien entre le code et la
   réalité. Elle sait qu'il existe une VM 9102 nommée `lab2-web`, pas que
   cette VM *est* `proxmox_virtual_environment_vm.lab["lab2-web"]`. L'état
   stocke cette correspondance (adresse → identifiant réel). Il évite aussi
   d'énumérer tout le cloud à chaque plan (coût, quotas), il mémorise des
   attributs que l'API ne relit pas (mots de passe initiaux, valeurs
   `sensitive`) et il porte les **dépendances** enregistrées, nécessaires pour
   détruire dans le bon ordre même quand le code a disparu.
2. **Contenu** : un JSON avec `version`, `terraform_version`, `serial`
   (compteur incrémenté à chaque écriture), `lineage` (UUID de naissance de
   l'état), `outputs` et `resources[]`, chacune avec `mode`, `type`, `name`,
   `provider`, et `instances[]` contenant `attributes` **en clair** (clés SSH,
   mots de passe cloud-init, tokens passés en attribut) et `dependencies`.
3. **Deux applies sans verrou** : chacun lit le même état (serial N), calcule
   son plan, applique, puis écrit « son » état. Le second écrase le premier :
   les ressources créées par le premier sont **orphelines** (existent, mais
   plus dans aucun état) et le prochain plan veut les recréer, ce que Proxmox
   refuse (VMID pris) ou accepte en doublon. D'où le verrou, et le refus
   d'écrire si le `serial` distant a avancé.
4. **Jamais dans git** : il contient des secrets ; il change à chaque apply
   (conflits de merge impossibles à résoudre sur un JSON généré) ; un état
   committé n'est plus « le » dernier dès que quelqu'un applique sans pusher.
   Un backend distant versionné, verrouillé et à accès restreint remplace git
   pour ce fichier précis.

::: pourquoi
Le point que les candidats ratent le plus souvent est le premier : « pourquoi
ne pas tout relire ? ». La réponse tient en un mot, l'**identité**. Deux
ressources peuvent être identiques attribut pour attribut ; seul l'état sait
laquelle appartient à quel bloc de code. C'est aussi pourquoi `state rm`
« oublie » sans détruire et pourquoi `import` « adopte » sans créer : on
manipule la table de correspondance, pas la réalité. Le `lineage` sert de
garde-fou : `tofu state push` refuse un état dont le `lineage` diffère,
signe qu'on essaie d'écraser l'état d'un autre projet.
:::

---

**QO24.2** — *Entre `qm clone` et `ssh mathieu@10.10.10.110`.*

**Réponse attendue.**

1. `qm clone 9100 9110 --full 1` copie le disque `scsi0` (raw sur
   `local-lvm`) et la configuration, y compris les options cloud-init du
   template (`ciuser`, `sshkeys`, `ipconfig0`, `ide2: cloudinit`).
2. `qm set 9110 --ipconfig0 ip=10.10.10.110/24,gw=10.10.10.1` modifie la
   configuration (changement en attente, `qm cloudinit pending`) ; au `qm start`, Proxmox **régénère** l'ISO `cidata` du lecteur
   `ide2` : trois fichiers `user-data` (YAML `#cloud-config` avec `users`,
   `ssh_authorized_keys`, `hostname`), `meta-data` (`instance-id: <sha1 de la
   config cloud-init>`, `local-hostname`) et `network-config` (format réseau cloud-init v1 avec
   l'IP statique).
3. Au boot, le générateur systemd de cloud-init lance `ds-identify`, qui
   cherche un support étiqueté `cidata`/`CIDATA` : trouvé sur `/dev/sr0`, le
   datasource **NoCloud** est retenu et `cloud-init.target` est activé.
4. Étape `init-local` (avant le réseau) : lecture de `network-config`, écriture
   de `/etc/netplan/50-cloud-init.yaml`, application ; le hostname est posé.
5. Étape `init` (réseau up) : cloud-init compare l'`instance-id` reçu à celui
   de `/var/lib/cloud/instance` (absent au premier boot) → c'est une
   **nouvelle instance** : les modules **per-instance** s'exécutent (`users-groups`
   crée `mathieu` avec la clé, `ssh` génère les clés d'hôte, `write_files`); `growpart` et
   `resizefs` (per- always) agrandissent `/`.
6. Étapes `config` puis `final` : `package_update`, `packages`, `runcmd`
   (qemu-guest-agent activé), `final_message`. `cloud-init status` passe à
   `done`.
7. sshd écoute, la clé est dans `~mathieu/.ssh/authorized_keys` : le `ssh`
   réussit. Typiquement 40 à 90 s après `qm start` sans `ciupgrade`.

**Au redémarrage** : même `instance-id` (la config n'a pas changé) → les
modules per-instance sont **sautés** (sémaphores dans
`/var/lib/cloud/instance/sem/`), seuls les modules **per-always** (dits « per-boot » : `growpart`,
`resizefs`, `update_hostname`, réseau) rejouent. Un
`qm set --sshkeys` change le hash, donc l'`instance-id` : au boot suivant,
cloud-init voit une nouvelle instance et redéploie users et clés (E24.11).

::: pourquoi
Toute la logique de cloud-init repose sur ce couple **datasource +
instance-id**. Le datasource dit *d'où* viennent les données (NoCloud : un
disque ; sur AWS : l'endpoint 169.254.169.254) ; l'instance-id dit *si* la
machine est nouvelle. Proxmox n'invente pas un UUID aléatoire : il dérive
l'instance-id de la configuration cloud-init, ce qui rend le rejeu
prévisible — change ce que cloud-init doit appliquer, et il l'applique ;
change autre chose (RAM, disque) et il ne touche à rien. Cette propriété est
ce qui rend le clonage de template idempotent au sens des VM « cattle ».
:::

---

**QO24.3** — *`count` vs `for_each`.*

**Réponse attendue.**

| Critère | `count` | `for_each` |
|---|---|---|
| Indexation | entier `[0]`, `[1]` | clé `["lab2-web"]` |
| Suppression au milieu | décale les suivants (Q24.6) | touche la seule clé retirée |
| Accès | `count.index` | `each.key`, `each.value` |
| Contrainte au plan | nombre connu | **clés** connues, map ou set de chaînes |

`for_each` exige que les clés soient connues avant apply : `for_each =
toset([random_pet.x.id])` échoue (`The "for_each" set includes values derived
from resource attributes that cannot be determined until apply`). Les valeurs
peuvent être inconnues, pas les clés.

`count` reste le bon choix pour l'**activation conditionnelle** (`count =
var.user_data == null ? 0 : 1`, utilisé dans le module `vm-ubuntu`) et pour
N copies strictement interchangeables sans identité (workers numérotés qu'on
ne retire jamais au milieu).

**Migration sans recréation** (BF24.2) : un bloc `moved` par instance,
`from = adr[0]`, `to = adr["clé"]`, commité avec le changement de code. Le
plan affiche `adr[0] has moved to adr["clé"]` et `0 to add, 0 to destroy`.
Une fois appliqué, les blocs `moved` peuvent rester (inoffensifs) ou être
retirés à la PR suivante. `tofu state mv` fait la même chose hors code.

::: pourquoi
Le cœur du problème est l'**identité** dans l'état : une instance est repérée
par son adresse complète, `type.nom[index]`. Changer l'index, c'est changer
l'adresse ; pour OpenTofu, une adresse qui disparaît est une ressource à
détruire et une adresse qui apparaît est une ressource à créer. `moved`
déclare explicitement « ce sont les mêmes objets » et le plan réécrit les
adresses au lieu de recréer. `for_each` évite le problème en amont : l'adresse
porte un nom qui a un sens métier, stable dans le temps.
:::

---

**QO24.4** — *VM supprimée à la main, VMID réutilisé par un collègue.*

**Réponse attendue.**

`tofu plan` rafraîchit `lab["lab2-ops"]` en appelant
`GET /nodes/pve/qemu/9105/config` : l'API répond, puisqu'une VM 9105 existe.
Le provider identifie une VM **par son VMID et son nœud**, pas par son nom ni
par un UUID interne ; il ne peut donc pas savoir que ce 9105 n'est pas celui
qu'il a créé. Il relit ses attributs (`name = "sandbox-julien"`, autre RAM,
autre IP, autre disque) et le plan propose de les **ramener au code** :
`~ name = "sandbox-julien" -> "lab2-ops"`, `~ memory`, `~ initialization`,
éventuellement un `-/+` si un attribut ForceNew diffère (disque, clone).
Appliquer, c'est reconfigurer, voire détruire, la VM du collègue.

Procédure :

```bash
tofu state pull > ~/lab24/backup-$(date +%s).json     # filet
tofu state rm 'proxmox_virtual_environment_vm.lab["lab2-ops"]'  # oublier 9105
# donner à lab2-ops un VMID libre : terraform.tfvars, vm_id = 9106
tofu plan          # attendu : exactement 1 to add (lab2-ops sur 9106)
tofu apply
```

Rien n'a touché `sandbox-julien`. En prévention : réserver la plage 9100–9199
au code (option datacenter `next-id` de Proxmox pour que l'auto-attribution
reste hors plage, pool `lab2` avec ACL, tag `tofu`), et faire de « supprimer
une VM gérée » un `tofu destroy -target` plutôt qu'un clic.

::: pourquoi
Un provider ne peut vérifier l'identité d'une ressource qu'avec ce que l'API
lui rend. Certains clouds donnent un identifiant opaque unique (l'ID d'une
instance EC2 n'est jamais réutilisé) : la suppression manuelle se voit
immédiatement (`404` → `+ create`). Proxmox utilise des entiers réutilisables :
la suppression + réutilisation est **invisible** pour l'outil. C'est un cas
d'école de drift trompeur, et la seule protection est organisationnelle
(plages réservées, droits) plus le réflexe de **lire le plan** avant
d'appliquer : « pourquoi veut-il renommer une VM ? » suffit à arrêter
l'incident.
:::

---

**QO24.5** — *Immutable infrastructure et patching.*

**Réponse attendue.**

Avec une infra **mutable**, patcher = se connecter à chaque VM et la
modifier (apt upgrade, Ansible). Avec une infra **immutable**, on ne modifie
jamais une VM en place : on construit une nouvelle image, on remplace les VM,
on jette les anciennes.

* **Packer** construit l'image : à partir de `9100`, il installe agent,
  durcissement, paquets, patches du jour, et produit un template `9200`
  daté (`ubuntu-2404-20260919`). Le build est du code, versionné, testable.
* **Terraform** déploie : changer `template_id = 9200` dans les variables
  est un `clone.vm_id` → `-/+` sur toutes les VM. `create_before_destroy` et
  un déploiement par vagues limitent l'interruption.
* **cloud-init** ne pose plus que l'identité (hostname, clé, IP) : le premier
  boot dure 20 s au lieu de 4 min, et il n'y a plus de « premier boot qui
  échoue à moitié ».

**Avantages** : rollback = repointer vers le template précédent ; chaque VM
est reproductible à l'identique ; plus de dérive accumulée par des années de
patches ; l'audit se fait sur l'image, pas sur 100 machines.

**Coûts** : les **données** doivent vivre hors de la VM (disque `scsi1`
séparé, base gérée, stockage objet), sinon `-/+` les détruit ; le temps de
build d'image (10–20 min) s'ajoute avant tout correctif urgent ; les
adresses/identités doivent survivre au remplacement (IP fixes portées par le
code, enregistrements DNS, clés d'hôte SSH régénérées → `known_hosts` à
gérer) ; et les équipes doivent accepter de ne plus « corriger vite fait en
SSH ».

::: pourquoi
L'immutabilité déplace la complexité de l'exploitation vers la fabrication.
Elle n'a de sens que si les trois outils tiennent leur rôle : Packer sait
produire une image identique à la demande, Terraform sait remplacer sans
casser l'identité réseau, cloud-init reste minimal. Le test qui révèle une
infra « faussement immutable » : `tofu apply -replace` sur une VM de prod —
si quelqu'un panique, c'est qu'il y a des données ou de la configuration
manuelle dedans (L24.2, étape 6).
:::

---

**QO24.6** — *Pourquoi `sensitive = true` ne protège pas un secret.*

**Réponse attendue.**

`sensitive = true` est un **marqueur de propagation** : toute valeur dérivée
(interpolation, `templatefile`, output) hérite du marquage, et OpenTofu
remplace la valeur par `(sensitive value)` dans les sorties `plan`, `apply`,
`show` et `output`. Il oblige aussi à marquer les outputs qui l'exposent.
C'est tout.

Le secret finit quand même :

* dans le **tfstate** (attributs et outputs en clair, y compris dans les
  anciennes versions d'un bucket versionné) ;
* dans **`plan.bin`** (`tofu show -json plan.bin` le donne en clair) ;
* dans les **logs CI** dès qu'un job fait `tofu output -raw`, `show -json`,
  ou `TF_LOG=DEBUG` (les requêtes HTTP sont journalisées avec en-têtes) ;
* dans un fichier généré (`local_file`) si le contenu l'inclut ;
* dans l'historique **git** si un `.tfvars` ou un `default` a été commité.

Trois mesures pour un token Proxmox :

1. **jamais en HCL ni en tfvars** : le provider bpg lit
   `PROXMOX_VE_API_TOKEN` ; en CI, variable masquée du runner, en local
   `.env` en `0600` hors git ;
2. **moindre privilège et rotation** : rôle `TofuLab` limité aux privilèges
   VM/Datastore, un token par usage (`tofu`, `ci`), `pveum user token remove`
   + `add` à chaque fuite ou départ ;
3. **protéger l'état** : backend distant privé (bucket dédié, utilisateur
   `tofu` limité, TLS), chiffrement OpenTofu `terraform { encryption {} }`,
   et ne jamais mettre le token en attribut de ressource ou en output.

::: pourquoi
La confusion vient du mot : « sensitive » évoque un chiffrement, alors que
c'est un attribut de **présentation**. OpenTofu ne peut pas chiffrer
sélectivement des valeurs dans l'état sans casser le modèle (le provider a
besoin des valeurs en clair pour comparer). Le seul chiffrement réel est
celui de l'état entier (`encryption {}` chez OpenTofu, backend chiffré côté
serveur). La question d'entretien derrière : « où est ton secret à chaque
étape du pipeline ? » — si la réponse contient « dans un fichier lisible par
le runner », il y a un problème.
:::

---

**QO24.7** — *Grille de revue d'une PR avec plan joint.*

**Réponse attendue.**

**Avant de lire le code, lire le plan :**

1. la **ligne de résumé** `Plan: X to add, Y to change, Z to destroy` :
   tout `destroy` non annoncé dans la description de la PR bloque ;
2. les symboles : `-/+` et `+/-` → chercher la ligne `# forces replacement`
   et vérifier qu'elle est voulue ; `-` seul → qu'est-ce qui est perdu
   (disque, données) ? `~` → l'attribut est-il celui que la PR prétend
   changer ? ;
3. les **adresses** touchées : un changement sur `lab2-web` dans une PR
   « ajoute lab2-ops » est suspect (drift capturé au passage, ou effet de
   bord d'une variable partagée) ;
4. `has moved to` → les blocs `moved` sont bien dans le diff ;
5. `(known after apply)` sur un attribut qui devrait être stable (IP, VMID) ;
6. la section `Objects have changed outside of OpenTofu` : du drift à
   traiter dans une autre PR ;
7. `(sensitive value)` dans un output nouveau : pourquoi ?

**Ensuite le code** : `fmt`/`validate`/`tflint` verts, variables typées avec
`validation`, pas de valeur en dur qui devrait être une variable, pas de
secret, `README` du module à jour, version de provider épinglée.

**Mécanisme CI** : le job `plan` s'exécute sur le **merge commit** (pas sur la
branche seule), produit `plan.bin` **et** `plan.txt`, publie le texte en
commentaire de PR et stocke `plan.bin` comme artefact. Le job `apply`, lancé
après merge/approbation, n'accepte **que ce `plan.bin`** (`tofu apply
plan.bin`) : si l'état ou le code ont bougé entre-temps, OpenTofu refuse
(`Saved plan is stale`) et on replanifie. Un `apply` sans plan sauvegardé en
CI est un apply qu'aucun humain n'a lu.

::: pourquoi
Le plan est le seul artefact qui dit ce qui va **réellement** se passer :
le code décrit une intention, l'état un passé, le plan la différence. Le
plan sauvegardé (`-out`) est plus qu'un fichier : il embarque le `serial` de
l'état et les valeurs lues, donc il est **invalidé** dès que l'un ou l'autre
change. C'est ce qui rend « le plan joint est celui appliqué » vérifiable
mécaniquement, et non par confiance.
:::

---

**QO24.8** — *Diagnostic : cloud-init « n'a rien fait ».*

**Réponse attendue.**

**Côté Proxmox (sans entrer dans la VM)** :

```bash
qm config 9110 | grep -E '^(ide2|cicustom|ciuser|sshkeys|ipconfig0|template)'
qm cloudinit dump 9110 user      # user-data généré par Proxmox / le snippet
qm cloudinit dump 9110 network
qm cloudinit dump 9110 meta      # instance-id
qm cloudinit pending 9110        # options modifiées non encore régénérées
```

Ce qu'on cherche, dans l'ordre : (1) un lecteur `cloudinit` présent (sinon
BF24.4) ; (2) un `cicustom` qui pointe vers un snippet **existant** sur un
stockage qui accepte `snippets` (`pvesm status`, `ls /var/lib/vz/snippets`) ;
(3) le user-data dumpé commence par `#cloud-config` et contient bien `users`
et la clé ; (4) `ipconfig0` cohérent avec `vmbr1`.

**Côté VM** (console série `qm terminal 9110`, ou SSH si possible) :

```bash
cloud-init status --long      # done / error / disabled + détail
cloud-id                      # nocloud, none...
cloud-init query platform     # ou : cat /run/cloud-init/ds-identify.log
cloud-init query userdata | head
sudo grep -iE 'warn|error|Traceback|Unhandled' /var/log/cloud-init.log
sudo tail -50 /var/log/cloud-init-output.log
ls /var/lib/cloud/instance/sem/
```

**Le test qui tranche** : `cloud-init query platform` (ou `cloud-id`).

* Réponse `none` / `status: disabled` avec `Cloud-init disabled by
  cloud-init-generator` → **pas de datasource** : ds-identify n'a rien trouvé,
  le problème est côté Proxmox (lecteur absent, ISO non régénérée) ;
* réponse `nocloud` mais `status: done` sans utilisateur, et dans le log
  `Unhandled non-multipart` ou `Failed loading yaml blob` → **user-data
  invalide** : le transport fonctionne, le contenu est rejeté ;
* `status: error` → un module a échoué (`runcmd` en erreur, paquet
  introuvable) : le détail est dans `cloud-init-output.log`.

Rejeu après correctif : si le correctif change l'`instance-id` (nouveau
snippet, nouvelles clés), un simple reboot suffit ; sinon `sudo cloud-init
clean --logs && sudo reboot` force un « premier boot ».

::: pourquoi
Les trois pannes ont le même symptôme (VM démarrée, rien d'appliqué) mais
trois causes de nature différente : **transport** (le disque), **contenu**
(le YAML), **exécution** (un module). Chaque étage a son témoin : ds-identify
pour le transport, le premier parse dans `cloud-init.log` pour le contenu,
`cloud-init-output.log` pour l'exécution. Commencer par le nœud plutôt que
par la VM est plus rapide (pas besoin d'accès) et évite l'erreur classique :
chercher un bug YAML alors que l'ISO n'a jamais été montée.
:::

---

## 24.5 Exercices guidés

**E24.1** — *Installer OpenTofu, `TF_LOG=DEBUG`, `tofu -help plan` et les cinq
options.*

```bash
tofu version
# OpenTofu v1.10.x
# on linux_amd64
TF_LOG=DEBUG tofu version 2>&1 | head -5
# [DEBUG] ... lignes de trace (chargement CLI, plugins) avant la version
tofu -help plan | grep -E -- '-(out|replace|refresh-only|target|var)( |=)'
```

Contenu attendu dans `~/lab24/notes.md` :

```text
-out=p        écrit le plan dans un fichier ; apply p exécute CE plan-là
-replace=adr  force destroy+create de la ressource (immutable, remplace taint)
-refresh-only ne propose que la mise à jour de l'état d'après la réalité
-target=adr   limite le plan à adr et ses dépendances (dépannage seulement)
-var 'k=v'    surcharge une variable, priorité maximale
```

::: pourquoi
`TF_LOG` accepte `TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR` et `TF_LOG_PATH`
redirige vers un fichier ; `TF_LOG_PROVIDER` limite au provider. En `DEBUG`,
les requêtes HTTP vers Proxmox sont tracées avec leurs en-têtes : c'est
l'outil de diagnostic quand un `apply` « pend » (timeout agent) ou renvoie
`403`, et c'est aussi pourquoi on ne l'active jamais en CI sans réfléchir
(le token apparaît dans les en-têtes). Les cinq options sont celles qu'on
utilise en exploitation ; les autres (`-parallelism`, `-lock-timeout`,
`-input=false`) servent surtout en pipeline.
:::

---

**E24.2** — *`hello.txt` avec un nom d'animal aléatoire ; `init`, `plan`,
`apply` ; observer les fichiers produits.*

`~/lab24/e02/main.tf` (le `versions.tf` est posé par le setup) :

```hcl
resource "random_pet" "nom" {
  length = 2
}

resource "local_file" "hello" {
  filename        = "${path.module}/hello.txt"
  content         = "Bonjour, je suis ${random_pet.nom.id}\n"
  file_permission = "0644"
}
```

```bash
cd ~/lab24/e02
tofu init
# Initializing provider plugins...
# - Finding hashicorp/local versions matching "~> 2.5"...
# - Installing hashicorp/local v2.5.x...
# OpenTofu has created a lock file .terraform.lock.hcl ...
tofu plan
# Plan: 2 to add, 0 to change, 0 to destroy.
tofu apply -auto-approve
cat hello.txt            # Bonjour, je suis famous-koala
```

Observations :

```bash
cat .terraform.lock.hcl
# provider "registry.opentofu.org/hashicorp/local" {
#   version     = "2.5.x"
#   constraints = "~> 2.5"
#   hashes = [ "h1:...", "zh:...", ... ]
# }
du -sh .terraform                # ~ 25M : les binaires des deux providers
tofu state list
# local_file.hello
# random_pet.nom
tofu state show random_pet.nom
# resource "random_pet" "nom" {
#     id        = "famous-koala"
#     length    = 2
#     separator = "-"
# }
```

::: pourquoi
`init` fait trois choses : résoudre les contraintes de version de
`required_providers`, télécharger les binaires dans `.terraform/providers/`
et **figer** les versions et leurs empreintes dans `.terraform.lock.hcl`.
Ce fichier de verrou **se commite** : il garantit que la CI et les collègues
utilisent exactement les mêmes providers (une contrainte `~> 2.5` autorise
2.5.0 à 2.99, le verrou fixe 2.5.2). `.terraform/` ne se commite pas
(binaires, cache de modules). `random_pet` est un cas d'école d'état : sa
valeur n'existe **nulle part ailleurs** que dans le tfstate ; perdre l'état,
c'est perdre le nom. `local_file` dépend de `random_pet` par la référence
dans `content`, d'où l'ordre de création.
:::

---

**E24.3** — *Variable `longueur` validée, `-var`, `terraform.tfvars`,
`TF_VAR_longueur`.*

Ajout dans `~/lab24/e02/variables.tf` :

```hcl
variable "longueur" {
  description = "Nombre de mots du nom d'animal"
  type        = number
  default     = 2

  validation {
    condition     = var.longueur >= 1 && var.longueur <= 4
    error_message = "longueur doit être comprise entre 1 et 4."
  }
}
```

et dans `main.tf` : `length = var.longueur`.

```bash
tofu plan -var longueur=9
# Error: Invalid value for variable
#   on variables.tf line 1:
#    1: variable "longueur" {
#     ├────────────────
#     │ var.longueur is 9
# longueur doit être comprise entre 1 et 4.
# This was checked by the validation rule at variables.tf:6,3-13.

printf 'longueur = 1\n' > terraform.tfvars
tofu plan | grep -E '^\s*[~+-].*length'      #  ~ length = 2 -> 1  (-/+)
TF_VAR_longueur=3 tofu plan | grep length     #  toujours 1 : tfvars gagne
TF_VAR_longueur=3 tofu plan -var longueur=4 | grep length   # 4 : -var gagne
rm terraform.tfvars
TF_VAR_longueur=3 tofu plan | grep length     #  3 : l'env gagne sur default
```

Ordre observé, du plus faible au plus fort : `default` < `TF_VAR_x` <
`terraform.tfvars` < `*.auto.tfvars` < `-var-file` / `-var` (dans l'ordre de
la ligne de commande, le dernier gagne).

::: pourquoi
La `validation` s'évalue au moment où la variable est résolue, avant tout
appel d'API : c'est le contrôle le moins cher qui existe, et il transforme
une erreur de provider obscure (« Proxmox a refusé vm_id=91020 ») en message
métier. Note que `length` est `ForceNew` pour `random_pet` : le changement
recrée l'animal, donc change `hello.txt` (`-/+` en cascade, voir E24.14). La
précédence répond à un besoin précis : `default` documente, `tfvars` porte
la configuration d'un environnement, `TF_VAR_` sert aux secrets et à la CI,
`-var` au test ponctuel. Le piège classique n'est pas `-var` (il gagne
toujours) mais un `*.auto.tfvars` oublié dans le répertoire, chargé
automatiquement et qui écrase `terraform.tfvars` et `TF_VAR_` sans qu'aucune
commande ne le mentionne.
:::

---

**E24.4** — *`tofu console` : noms triés, IP par `cidrhost`, map nom → ip,
chaîne jointe ; reporter dans `locals` et `output`.*

```bash
cd ~/lab24/e04 && tofu init >/dev/null && tofu console
> sort(keys(var.vms))
tolist(["lab2-adm", "lab2-db", "lab2-ops", "lab2-rhel", "lab2-web"])
> [for k, v in var.vms : cidrhost("10.10.10.0/24", v.host)]
["10.10.10.101", "10.10.10.103", "10.10.10.105", "10.10.10.104", "10.10.10.102"]
> { for k, v in var.vms : k => cidrhost("10.10.10.0/24", v.host) }
{ "lab2-adm" = "10.10.10.101"  "lab2-db" = "10.10.10.103" ... }
> join(",", sort(keys(var.vms)))
"lab2-adm,lab2-db,lab2-ops,lab2-rhel,lab2-web"
```

`~/lab24/e04/main.tf` :

```hcl
locals {
  noms  = sort(keys(var.vms))
  ips   = { for k, v in var.vms : k => cidrhost("10.10.10.0/24", v.host) }
  liste = [for k in local.noms : local.ips[k]]
  csv   = join(",", local.noms)
}

output "noms" { value = local.noms }
output "ips_liste" { value = local.liste }
output "ips" { value = local.ips }
output "csv" { value = local.csv }
```

::: pourquoi
Une map HCL est itérée dans l'ordre **lexicographique de ses clés**, quel que
soit l'ordre d'écriture dans le tfvars : `keys()` est déjà trié, `sort()` le
rend explicite pour le lecteur. `cidrhost(prefix, n)` calcule la n-ième
adresse du réseau et échoue si `n` dépasse la taille : c'est une validation
gratuite de la cohérence réseau, et la raison pour laquelle le lab stocke un
**octet** (`host = 102`) plutôt qu'une IP en chaîne. `tofu console` charge
les variables et l'état courant : on y teste une expression avant de la
mettre dans `locals`, ce qui évite le cycle plan/erreur/correction.
:::

---

**E24.5** — *`hosts.tftpl` et `local_file` générant `hosts.lab2` ; idempotence ;
modification du template.*

`~/lab24/e04/templates/hosts.tftpl` :

```text
# généré par OpenTofu (e04) — ne pas éditer
%{ for nom in noms ~}
${ips[nom]} ${nom} ${nom}.lab.local
%{ endfor ~}
```

Ajout dans `main.tf` :

```hcl
locals {
  # tri par IP : on trie les noms selon la valeur numérique du dernier octet
  noms_par_ip = [
    for h in sort([for k, v in var.vms : format("%03d %s", v.host, k)]) :
    split(" ", h)[1]
  ]
}

resource "local_file" "hosts" {
  filename        = "${path.module}/hosts.lab2"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/hosts.tftpl", {
    noms = local.noms_par_ip
    ips  = local.ips
  })
}
```

```bash
tofu apply -auto-approve && cat hosts.lab2
# 10.10.10.101 lab2-adm lab2-adm.lab.local
# 10.10.10.102 lab2-web lab2-web.lab.local
# ...
tofu apply -auto-approve      # No changes. Your infrastructure matches...
sed -i 's/ne pas éditer/genere, ne pas editer/' templates/hosts.tftpl
tofu plan
#   # local_file.hosts must be replaced
# -/+ resource "local_file" "hosts" {
#       ~ content = <<-EOT # forces replacement
```

**Réponse** : le résultat observable est « une seule ressource
touchée, le fichier réécrit », mais le symbole est `-/+`, pas `~`. Chez
`hashicorp/local`, **tous** les arguments de `local_file` (`content`,
`filename`, `file_permission`…) sont déclarés `RequiresReplace` : le provider
n'implémente pas de mise à jour, il supprime et réécrit. Pour un fichier
local c'est sans conséquence ; pour une VM ce serait une catastrophe, et c'est
exactement ce que le plan doit t'apprendre à distinguer.

::: pourquoi
`sort()` trie des **chaînes** : `"10.10.10.101"` passerait avant
`"10.10.10.99"`. D'où le tri sur `format("%03d", host)` (zéro-padding) puis
l'extraction du nom. Les marqueurs `~` dans `%{ for ~}` avalent le saut de
ligne qui suit la directive, sinon chaque itération produirait une ligne
vide. L'idempotence du second apply tient à ce que `content` est recalculé
à l'identique et comparé à l'état : `local_file` stocke aussi un hash
(`content_md5`, `content_sha256`) qui permet de détecter une modification
manuelle du fichier au refresh — teste `echo x » hosts.lab2 && tofu plan`.
:::

---

**E24.6** — *`count` sur `["adm","web","db"]`, retrait du premier, puis
`for_each`.*

`~/lab24/e06/main.tf`, version `count` :

```hcl
variable "noms" {
  type    = list(string)
  default = ["adm", "web", "db"]
}

resource "local_file" "vm" {
  count           = length(var.noms)
  filename        = "${path.module}/vm-${var.noms[count.index]}.txt"
  content         = "VM ${var.noms[count.index]}\n"
  file_permission = "0644"
}
```

```bash
cd ~/lab24/e06 && tofu init >/dev/null && tofu apply -auto-approve
# après retrait de "adm" dans default :
tofu plan
#   # local_file.vm[0] must be replaced        (vm-adm.txt -> vm-web.txt)
#   # local_file.vm[1] must be replaced        (vm-web.txt -> vm-db.txt)
#   # local_file.vm[2] will be destroyed       (vm-db.txt)
# Plan: 2 to add, 0 to change, 3 to destroy.
```

Version `for_each` (remets `"adm"` d'abord, applique, puis retire) :

```hcl
resource "local_file" "vm" {
  for_each        = toset(var.noms)
  filename        = "${path.module}/vm-${each.key}.txt"
  content         = "VM ${each.key}\n"
  file_permission = "0644"
}
```

Passer de `count` à `for_each` avec les fichiers déjà créés demande les
blocs `moved` (sinon 3 destroy / 3 add) :

```hcl
moved {
  from = local_file.vm[0]
  to   = local_file.vm["adm"]
}
moved {
  from = local_file.vm[1]
  to   = local_file.vm["web"]
}
moved {
  from = local_file.vm[2]
  to   = local_file.vm["db"]
}
```

```bash
tofu apply -auto-approve      # 0 to add : "local_file.vm[0] has moved to ..."
# retrait de "adm" :
tofu plan
#   # local_file.vm["adm"] will be destroyed
# Plan: 0 to add, 0 to change, 1 to destroy.
```

::: pourquoi
Le décalage de `count` n'est pas un bug : l'index **est** l'identité, et
OpenTofu fait exactement ce qu'on lui demande (« l'instance 0 doit
maintenant s'appeler web »). `toset()` est nécessaire parce que `for_each`
refuse une `list` : une liste peut contenir des doublons, un set non, et les
clés d'état doivent être uniques. Avec un `map`, `each.value` porte les
attributs (c'est le modèle de L24.2) ; avec un set, `each.key` et
`each.value` sont identiques.
:::

---

**E24.7** — *`ci-test.yaml`, validation, en-tête cassé, YAML syntaxique.*

`~/lab24/cloud-init/ci-test.yaml` :

```yaml
#cloud-config
hostname: ci-test
fqdn: ci-test.lab.local
manage_etc_hosts: true
users:
  - name: mathieu
    groups: [sudo]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: true
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... mathieu@lab-adm
package_update: true
packages:
  - qemu-guest-agent
  - htop
write_files:
  - path: /etc/lab24-marker
    permissions: "0644"
    content: |
      ci-test provisionne par cloud-init
runcmd:
  - systemctl enable --now qemu-guest-agent
```

```bash
cd ~/lab24/cloud-init
KEY=$(cat ~/.ssh/id_ed25519.pub)
sed -i "s|ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... mathieu@lab-adm|$KEY|" \
  ci-test.yaml
cloud-init schema --config-file ci-test.yaml
# Valid schema ci-test.yaml

sed -i '1s/.*/#cloud config/' ci-test.yaml
cloud-init schema --config-file ci-test.yaml
# Error: Cloud config schema errors: format-l1.c1: Unrecognized user-data
# header in ci-test.yaml: "#cloud config".
# Expected first line to be one of: #!, #cloud-boothook, #cloud-config,
# #cloud-config-archive, #cloud-config-jsonp, #include, #include-once,
# #part-handler
sed -i '1s/.*/#cloud-config/' ci-test.yaml

python3 -c 'import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); \
print(sorted(d))' ci-test.yaml
# ['fqdn', 'hostname', 'manage_etc_hosts', 'package_update', 'packages',
#  'runcmd', 'users', 'write_files']
```

::: pourquoi
Deux validations différentes : PyYAML vérifie la **syntaxe** (indentation,
deux-points, listes), `cloud-init schema` vérifie en plus l'**en-tête** et le
**schéma** (clé inconnue, type faux : `packages: qemu-guest-agent` sans liste
est refusé, `permissions: 0644` sans guillemets est un entier octal et non une
chaîne). L'en-tête est hors YAML : pour PyYAML, `#cloud config` est un
commentaire parfaitement valide, d'où l'intérêt de faire les deux. Points
sensibles du fichier : `lock_passwd: true` (pas de mot de passe, clé
uniquement), `sudo` en chaîne, `write_files` avant `runcmd` dans l'ordre
d'exécution (le marqueur existe quand `runcmd` tourne), et `manage_etc_hosts`
pour que `hostname -f` résolve sans DNS.
:::

::: piege
Sans `groups: [sudo]` l'utilisateur est créé sans droits ; sans
`shell: /bin/bash` il a `/bin/sh`. Et surtout : dès qu'on déclare `users:`,
l'utilisateur par défaut `ubuntu` de l'image **n'est plus créé** — c'est
voulu ici, mais c'est une surprise classique.
:::

---

**E24.8** — *Utilisateur `terraform@pve`, rôle `TofuLab`, ACL, token, test
`curl`.*

Sur le nœud (`ssh root@10.10.10.1`) :

```bash
pveum user add terraform@pve --comment "OpenTofu (module 24)"
pveum role add TofuLab -privs "Datastore.Allocate \
Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit \
Pool.Allocate SDN.Use Sys.Audit Sys.Console Sys.Modify \
VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit \
VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory \
VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt \
VM.Snapshot VM.Snapshot.Rollback"
pveum aclmod / -user terraform@pve -role TofuLab
pveum user token add terraform@pve tofu -privsep 0
# +--------------+--------------------------------------+
# | key          | value                                |
# +==============+======================================+
# | full-tokenid | terraform@pve!tofu                   |
# | info         | {"privsep":"0"}                      |
# | value        | 3f2c9d1e-....-....-....-............ |
# +--------------+--------------------------------------+
```

Pourquoi ces privilèges : `VM.Allocate`/`VM.Clone` pour créer et cloner,
`VM.Config.*` pour chaque famille d'attributs (`Cloudinit` pour
`initialization`, `Disk` pour `disk`, `Options` pour `agent`, `tags`,
`on_boot`), `VM.PowerMgmt` pour start/stop, `VM.Audit`/`VM.Monitor` pour
relire et interroger l'agent, `VM.Snapshot*` pour E24.12, `Datastore.*` pour
allouer les disques et **poser des snippets** (`AllocateTemplate`),
`Sys.Audit`/`Sys.Modify` pour lire les nœuds et le stockage, `SDN.Use` pour
attacher `vmbr1`, `Pool.Allocate` si tu utilises `pool_id`.

Sur `lab-adm` :

```bash
cp ~/lab24/.env.example ~/lab24/.env && chmod 600 ~/lab24/.env
# remplacer la valeur de PROXMOX_VE_API_TOKEN par terraform@pve!tofu=<uuid>
set -a; . ~/lab24/.env; set +a
curl -sk -H "Authorization: PVEAPIToken=$PROXMOX_VE_API_TOKEN" \
  https://10.10.10.1:8006/api2/json/version | jq .data.version
# "8.2.4"
curl -sk -H "Authorization: PVEAPIToken=$PROXMOX_VE_API_TOKEN" \
  https://10.10.10.1:8006/api2/json/nodes/pve/qemu \
  | jq -r '.data[] | [.vmid, .name, .status] | @tsv' | sort -n
curl -sk -o /dev/null -w '%{http_code}\n' \
  https://10.10.10.1:8006/api2/json/nodes/pve/qemu       # 401
```

::: pourquoi
Un **token** est une identité dérivée d'un utilisateur : avec `-privsep 0`
il hérite de tous les droits de `terraform@pve` ; avec `-privsep 1` il faut
lui donner ses propres ACL (plus sûr, plus verbeux). La **valeur** n'est
affichée qu'une fois ; perdue, on la régénère (rotation, BF24.3). L'API
authentifie soit par ticket de session (cookie + CSRF, ce que fait
l'interface web), soit par cet en-tête `PVEAPIToken=user@realm!nom=uuid`,
sans expiration ni CSRF : idéal pour un outil, redoutable si le token fuit.
`-k`/`insecure = true` accepte le certificat auto-signé du nœud ; en
production on pose un certificat valide et on retire l'option. `401`
signifie « pas authentifié » ; un `403` signifierait « token valide mais
privilège manquant » et la réponse nomme le privilège (`Permission check
failed (/vms/9102, VM.Config.Disk)`), ce qui rend l'ajustement du rôle
trivial.
:::

---

**E24.9** — *Exécuter `make-template.sh`, vérifier `qm config 9100`, expliquer
`--serial0 socket --vga serial0` et `--cpu x86-64-v2-AES`.*

```bash
scp ~/lab24/proxmox/make-template.sh root@10.10.10.1:/root/
ssh root@10.10.10.1 'mkdir -p /root/keys'
scp ~/.ssh/id_ed25519.pub root@10.10.10.1:/root/keys/mathieu.pub
ssh root@10.10.10.1 bash /root/make-template.sh
ssh root@10.10.10.1 qm config 9100
# agent: 1
# boot: order=scsi0
# cipassword: ...        (absent)
# ciupgrade: 0
# ciuser: mathieu
# cores: 1
# cpu: x86-64-v2-AES
# ide2: local-lvm:vm-9100-cloudinit,media=cdrom
# ipconfig0: ip=dhcp
# memory: 1024
# name: ubuntu-2404-tpl
# net0: virtio=BC:24:11:xx:xx:xx,bridge=vmbr1
# ostype: l26
# scsi0: local-lvm:base-9100-disk-0,discard=on,iothread=1,size=20G
# scsihw: virtio-scsi-single
# serial0: socket
# sshkeys: ssh-ed25519%20AAAA...
# template: 1
# vga: serial0
```

Le script en clair : téléchargement de l'image officielle ; `virt-customize`
installe `qemu-guest-agent` **hors ligne** dans l'image et vide
`/etc/machine-id` (sinon tous les clones partagent le même identifiant :
même bail DHCP, mêmes identifiants systemd-journal) ; `qm create` avec
`--agent enabled=1` ; `qm disk import` transforme le qcow2 en volume
`local-lvm` ; `qm set --scsi0` l'attache avec `discard`/`iothread` ; `--ide2
local-lvm:cloudinit` crée le lecteur NoCloud ; `--boot order=scsi0` ; les
options `ci*` posent des valeurs par défaut héritées par chaque clone ;
`qm disk resize` porte le disque à 20 Go (cloud-init `growpart` étendra `/`
au premier boot) ; `qm template` convertit le disque en `base-9100-disk-0`,
image de base en lecture seule pour les clones liés.

::: pourquoi
**`--serial0 socket --vga serial0`** : les images cloud sont construites
pour des hyperviseurs sans écran ; leur GRUB passe `console=tty1
console=ttyS0` au noyau et le login s'affiche sur le port série. Sans port
série, tu n'as ni journal de boot ni console de secours (`qm terminal 9100`),
et cloud-init lui-même écrit sur ttyS0. `vga serial0` fait suivre la console
Proxmox (interface web) sur ce port.

**`--cpu x86-64-v2-AES`** : le type par défaut `kvm64` expose un jeu
d'instructions de 2007 (pas de SSE4.2, pas d'AES-NI). Rocky/RHEL 9 exige
x86-64-v2 pour démarrer ; MongoDB, certaines JVM et le chiffrement TLS
sont bien plus lents sans AES-NI. `x86-64-v2-AES` est le compromis Proxmox
recommandé : moderne, mais assez générique pour migrer entre hôtes de
générations différentes, contrairement à `host`.
:::

---

**E24.10** — *Cloner en 9110, adresser, démarrer, attendre l'agent, obtenir
l'IP, SSH, chronométrer.*

Sur le nœud :

```bash
qm clone 9100 9110 --name ci-test --full 1
qm set 9110 --ipconfig0 ip=10.10.10.110/24,gw=10.10.10.1 --memory 2048
date +%s > /tmp/t0; qm start 9110
until qm agent 9110 ping >/dev/null 2>&1; do sleep 2; done
echo "agent après $(( $(date +%s) - $(cat /tmp/t0) )) s"
qm guest cmd 9110 network-get-interfaces \
  | jq -r '.[] | select(.name != "lo") | .["ip-addresses"][]
           | select(.["ip-address-type"] == "ipv4") | .["ip-address"]'
# 10.10.10.110
# variante API :
pvesh get /nodes/pve/qemu/9110/agent/network-get-interfaces --output-format json
```

Depuis `lab-adm` :

```bash
t0=$(date +%s)
until ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=accept-new \
      mathieu@10.10.10.110 true 2>/dev/null; do sleep 2; done
echo "ssh ok après $(( $(date +%s) - t0 )) s"     # typiquement 40-70 s
ssh mathieu@10.10.10.110 'hostname; cloud-init status'
# ci-test
# status: done
```

::: pourquoi
L'agent répond dès que `qemu-guest-agent.service` démarre, c'est-à-dire
après l'étape `init` de cloud-init (réseau configuré, utilisateur créé) mais
souvent **avant** la fin de `final` (`runcmd`, paquets). C'est pourquoi le
provider bpg utilise l'agent comme signal « VM prête » et pourquoi
`ipv4_addresses` vient de lui et non de la configuration : c'est l'adresse
**réellement** portée par l'interface, y compris en DHCP. `qm guest cmd`
parle au socket virtio-serial de l'agent, sans réseau : c'est la seule voie
de diagnostic quand le réseau de la VM est cassé. Le temps mesuré se
décompose en ~10 s de BIOS/GRUB/noyau, ~15 s de cloud-init init-local + init,
puis les paquets ; sans `package_update` il tombe sous 30 s.
:::

---

**E24.11** — *Datasource, instance-id, user-data reçu, durée du premier boot,
modules per-instance ; remplacer la clé et redémarrer.*

Sur `ci-test` :

```bash
cloud-id                                     # nocloud
cloud-init query platform                    # nocloud
cloud-init query instance_id                 # ex. 7b0f1e0a5c...  (sha1 Proxmox)
sudo cat /var/lib/cloud/data/instance-id     # idem
cloud-init query userdata | head -3     # #cloud-config généré par Proxmox
sudo cloud-init analyze show | tail -8
# Finished stage: (modules-final) 21.4 seconds
# Total Time: 38.9 seconds
# 1 boot records analyzed
ls /var/lib/cloud/instance/sem/
# config_apt_configure  config_set_hostname  config_ssh  config_users_groups
# config_write_files  config_scripts_user ...   (pas de growpart : per-always)
```

Sur le nœud, changement de clé puis redémarrage :

```bash
ssh-keygen -t ed25519 -N '' -f /root/keys/test2 -C test2
qm set 9110 --sshkeys /root/keys/test2.pub
qm cloudinit dump 9110 meta | grep instance-id     # a changé
qm reboot 9110
```

Sur `ci-test` après reboot : `cloud-init query instance_id` donne la
**nouvelle** valeur, `/var/lib/cloud/instances/` contient deux répertoires,
et `~mathieu/.ssh/authorized_keys` contient la clé `test2` : la nouvelle clé est déployée, `ssh -i /root/keys/test2` depuis le nœud réussit. Constate aussi si l'ancienne clé est toujours présente : cloud-init **ajoute** les clés déclarées au fichier existant, il ne purge pas celles qu'il n'a plus dans son user-data (à vérifier sur ta VM).
Remets ta clé (`qm set 9110 --sshkeys /root/keys/mathieu.pub`, reboot) avant
L24.1.

::: pourquoi
`cloud-init analyze show` lit `/var/log/cloud-init.log` et découpe le boot
en quatre étapes (`init-local`, `init-network`, `modules-config`,
`modules-final`) : c'est la première chose à regarder quand on veut réduire
le temps de premier boot (les paquets dominent). Les sémaphores dans
`instance/sem/` sont le mécanisme concret du « per-instance » : un fichier
par module, sous le répertoire de **l'instance courante** ; nouvelle
instance → nouveau répertoire vide → tous les modules rejouent. La preuve
par `--sshkeys` est celle qu'on demande en entretien : elle montre que
Proxmox calcule l'instance-id depuis la configuration cloud-init (`qm
cloudinit dump meta`), pas depuis le VMID.
:::

---

**E24.12** — *Script `pve.sh` : `list`, `snap`, `rollback`, `resize`,
`destroy` via l'API, attente des UPID.*

`~/lab24/bin/pve.sh` :

```bash
#!/usr/bin/env bash
# pve.sh — pilote Proxmox via l'API (token dans ~/lab24/.env)
# usage : pve.sh list | snap <vmid> <nom> | rollback <vmid> <nom>
#         | resize <vmid> +5G | destroy <vmid>
set -euo pipefail

ENV_FILE="${ENV_FILE:-$HOME/lab24/.env}"
[ -r "$ENV_FILE" ] || { echo "fichier $ENV_FILE illisible" >&2; exit 2; }
set -a; . "$ENV_FILE"; set +a
: "${PROXMOX_VE_ENDPOINT:?}" "${PROXMOX_VE_API_TOKEN:?}" "${PVE_NODE:=pve}"
API="${PROXMOX_VE_ENDPOINT%/}/api2/json"
AUTH="Authorization: PVEAPIToken=$PROXMOX_VE_API_TOKEN"

api() {   # api <méthode> <chemin> [param=valeur ...]  -> .data en JSON
  local m=$1 p=$2; shift 2
  local args=()
  for kv in "$@"; do args+=(--data-urlencode "$kv"); done
  curl -sk -f -X "$m" -H "$AUTH" "${args[@]}" "$API$p" \
    || { echo "API $m $p a échoué" >&2; return 1; }
}

attendre() {   # attendre <upid> : bloque jusqu'à stopped, échoue si != OK
  local upid=$1 st
  [ -n "$upid" ] && [ "$upid" != "null" ] || return 0
  while :; do
    st=$(api GET "/nodes/$PVE_NODE/tasks/$upid/status")
    [ "$(jq -r .data.status <<<"$st")" = "stopped" ] && break
    sleep 1
  done
  [ "$(jq -r .data.exitstatus <<<"$st")" = "OK" ] \
    || { echo "tâche $upid : $(jq -r .data.exitstatus <<<"$st")" >&2
         return 1; }
}

vm=/nodes/$PVE_NODE/qemu
cmd=${1:-}; shift || true
case "$cmd" in
  list)
    api GET "$vm" | jq -r '.data[] | [.vmid, .name, .status] | @tsv' \
      | sort -n ;;
  snap)
    attendre "$(api POST "$vm/$1/snapshot" "snapname=$2" | jq -r .data)" ;;
  rollback)
    attendre "$(api POST "$vm/$1/snapshot/$2/rollback" | jq -r .data)" ;;
  resize)
    api PUT "$vm/$1/resize" "disk=scsi0" "size=$2" >/dev/null ;;
  destroy)
    st=$(api GET "$vm/$1/status/current" | jq -r .data.status)
    [ "$st" = "stopped" ] \
      || attendre "$(api POST "$vm/$1/status/stop" | jq -r .data)"
    attendre "$(api DELETE "$vm/$1" "purge=1" "destroy-unreferenced-disks=1" \
               | jq -r .data)" ;;
  *) sed -n '2,4p' "$0" >&2; exit 2 ;;
esac
```

Démonstration :

```bash
chmod +x ~/lab24/bin/pve.sh
~/lab24/bin/pve.sh list | grep 9110
~/lab24/bin/pve.sh snap 9110 avant-modif
ssh mathieu@10.10.10.110 'sudo apt-get install -y sl >/dev/null; which sl'
~/lab24/bin/pve.sh rollback 9110 avant-modif
ssh root@10.10.10.1 qm start 9110      # le rollback arrête la VM
until ssh -o ConnectTimeout=2 mathieu@10.10.10.110 true 2>/dev/null; do
  sleep 2; done
ssh mathieu@10.10.10.110 'which sl || echo "sl absent : rollback OK"'
```

::: pourquoi
L'API Proxmox est **asynchrone** pour tout ce qui dure : `POST .../snapshot`,
`.../rollback`, `.../status/stop`, `DELETE` répondent immédiatement avec un
**UPID** (`UPID:pve:000A1B2C:...:qmsnapshot:9110:terraform@pve!tofu:`) et la
tâche continue côté nœud. Enchaîner `stop` puis `destroy` sans attendre
renvoie `VM is running` ; d'où `attendre()`, qui lit
`/nodes/<n>/tasks/<upid>/status` jusqu'à `stopped` et vérifie `exitstatus:
OK`. `resize` est synchrone (pas d'UPID), `snapshot` en crée un. Le provider
bpg fait exactement cela en interne, ce qui explique pourquoi un apply
« attend » : il attend des UPID. `--data-urlencode` protège le `+` de `+5G`
et les `:` de l'UPID ; `-f` transforme un `4xx`/`5xx` en échec de script
(avec `set -e`, on s'arrête au premier appel raté).
:::

---

**E24.13** — *`data "proxmox_virtual_environment_nodes"`, `tofu providers`,
`tofu providers lock`.*

`~/lab24/e13/main.tf` :

```hcl
provider "proxmox" {
  insecure = true # endpoint/token : PROXMOX_VE_ENDPOINT / _API_TOKEN
}

data "proxmox_virtual_environment_nodes" "all" {}

output "noeuds" {
  value = data.proxmox_virtual_environment_nodes.all.names
}
```

```bash
cd ~/lab24/e13 && set -a && . ~/lab24/.env && set +a
tofu init && tofu apply -auto-approve
# Outputs:
# noeuds = tolist(["pve"])
tofu providers
# Providers required by configuration:
# .
# └── provider[registry.opentofu.org/bpg/proxmox] ~> 0.7
tofu providers lock -platform=linux_amd64 -platform=darwin_arm64
# - Obtained bpg/proxmox checksums for darwin_arm64; ...
# - Obtained bpg/proxmox checksums for linux_amd64; ...
git diff .terraform.lock.hcl     # hashes h1: supplémentaires
```

::: pourquoi
Un bloc `data` **lit** sans créer : il est rafraîchi à chaque plan et n'a
pas d'entrée « managed » dans l'état. C'est le test de connexion le plus
propre qui soit (pas de `curl`, mêmes variables d'environnement que les
vraies ressources). `tofu providers` montre l'adresse complète
`registry.opentofu.org/bpg/proxmox` : OpenTofu a son propre registre, miroir
des mêmes providers. Le fichier de verrou contient des empreintes `h1:` par
plateforme ; un `init` sur une plateforme absente du verrou échoue en CI
avec `-lockfile=readonly` ou modifie le fichier silencieusement sans.
`providers lock -platform` pré-calcule les empreintes pour Linux (runner) et
macOS (poste) afin que tout le monde travaille avec le même verrou.
:::

---

**E24.14** — *`prevent_destroy`, puis `-replace` sur `random_pet`.*

```hcl
resource "local_file" "hello" {
  # ...
  lifecycle {
    prevent_destroy = true
  }
}
```

```bash
cd ~/lab24/e02 && tofu destroy
# Error: Instance cannot be destroyed
#   on main.tf line 6:
#    6: resource "local_file" "hello" {
# Resource local_file.hello has lifecycle.prevent_destroy set, but the plan
# calls for this resource to be destroyed. To avoid this error and continue
# with the plan, either disable lifecycle.prevent_destroy or reduce the scope
# of the plan using the -target option.
```

Après retrait du bloc :

```bash
tofu apply -replace=random_pet.nom
#   # random_pet.nom will be replaced, as requested
# -/+ resource "random_pet" "nom" {
#       ~ id = "famous-koala" -> (known after apply)
#   # local_file.hello must be replaced
# -/+ resource "local_file" "hello" {
#       ~ content = "Bonjour, je suis famous-koala\n" -> (known after apply)
#         # forces replacement
# Plan: 2 to add, 0 to change, 2 to destroy.
```

Deux ressources : l'animal parce qu'on l'a demandé, le fichier parce que son
`content` dépend de `random_pet.nom.id`, valeur inconnue avant recréation, et
que `content` force le remplacement chez `local_file`.

::: pourquoi
`prevent_destroy` est vérifié au **plan** : toute opération qui détruirait
l'instance (destroy, `-replace`, changement d'attribut ForceNew, retrait du
bloc de code) est refusée avec ce message. C'est une ceinture pour la base
de données ou la VM importée `rhel` (L24.3, D24), pas une sécurité absolue :
retirer la ligne suffit, et c'est visible en PR — c'est le but. La cascade
de `-replace` illustre le graphe : OpenTofu ne recrée pas « ce qu'on lui
dit », il recrée ce qu'on lui dit **plus tout ce qui en dépend par un
attribut ForceNew**. Avant un `-replace` sur une VM, `tofu graph` ou la
lecture du plan dit combien de ressources suivront.
:::

---

**E24.15** — *Variable `secret` sensible dans un fichier et un output.*

```hcl
variable "secret" {
  type      = string
  sensitive = true
  default   = "s3cr3t-lab24"
}

resource "local_file" "hello" {
  filename        = "${path.module}/hello.txt"
  content         = "Bonjour, je suis ${random_pet.nom.id} / ${var.secret}\n"
  file_permission = "0600"
}

output "secret" {
  value = var.secret
}
```

```bash
tofu plan
# Error: Output refers to sensitive values
#   on main.tf line 22:
#   22: output "secret" {
# To reduce the risk of accidentally exporting sensitive data that was
# intended to be only internal, OpenTofu requires that any root module output
# containing sensitive data be explicitly marked as sensitive, to confirm
# your intent.
```

Avec `sensitive = true` dans l'output :

```bash
tofu apply -auto-approve
#   # local_file.hello must be replaced
#       ~ content = (sensitive value) # forces replacement
# Outputs:
# secret = <sensitive>
tofu output                    # secret = <sensitive>
tofu output -raw secret        # s3cr3t-lab24
tofu show -json | jq '.values.root_module.resources[].values'
# { "content": "Bonjour, je suis famous-koala / s3cr3t-lab24\n", ... }
grep -c s3cr3t terraform.tfstate     # 2 : attribut + output
```

**Conclusion** : `sensitive` protège l'**affichage** dans le terminal, rien
d'autre — ni l'état, ni `show -json`, ni `output -raw`, ni le fichier
généré.

::: pourquoi
Le marquage se propage par les expressions : `content` devient sensible parce
qu'il contient `var.secret`, le fichier `hello.txt` contient le secret en
clair (permission `0600`, au moins). `show -json` est conçu pour les outils
(tflint, OPA, scripts) et donne tout, avec un tableau `sensitive_values`
séparé qui dit **quoi** masquer — à l'appelant de le faire. La bonne
pratique découle de là : ne jamais mettre un secret dans un attribut si
l'API ne l'exige pas ; quand elle l'exige (mot de passe initial d'une base),
protéger l'état comme le secret lui-même.
:::

---

**E24.16** — *Renommer `random_pet.nom` en `random_pet.animal` : plan, bloc
`moved`, `state mv`.*

```bash
sed -i 's/random_pet" "nom"/random_pet" "animal"/' main.tf
sed -i 's/random_pet\.nom/random_pet.animal/' main.tf
tofu plan
#   # random_pet.animal will be created
#   # random_pet.nom will be destroyed
#   # (because random_pet.nom is not in configuration)
#   # local_file.hello must be replaced
# Plan: 2 to add, 0 to change, 2 to destroy.
```

Il veut détruire l'ancien, créer un nouvel animal (nouveau nom aléatoire) et
réécrire le fichier. Méthode déclarative :

```hcl
moved {
  from = random_pet.nom
  to   = random_pet.animal
}
```

```bash
tofu plan
#   # random_pet.nom has moved to random_pet.animal
# Plan: 0 to add, 0 to change, 0 to destroy.
tofu apply -auto-approve
```

Méthode impérative (après avoir retiré le bloc `moved` et remis `nom` dans
le code et l'état pour rejouer) :

```bash
tofu state mv random_pet.nom random_pet.animal
# Move "random_pet.nom" to "random_pet.animal"
# Successfully moved 1 object(s).
tofu plan          # No changes.
```

**Comparaison** : `moved` est dans le **diff de la PR**, relu, rejoué
automatiquement dans tous les environnements qui utilisent ce code
(workspaces, autres racines), et n'exige pas d'accès à l'état pour le
reviewer. `state mv` est une opération manuelle sur un état précis, invisible
dans git, à refaire à la main par environnement, et sujette à la faute de
frappe sans filet (pas de plan avant). En équipe : `moved` par défaut,
`state mv` pour les cas que `moved` ne couvre pas (déplacement entre deux
états différents, ressource d'un autre type).

::: pourquoi
Un renommage est, pour l'état, une disparition plus une apparition : rien
dans le nom `random_pet.animal` ne dit qu'il désigne le même objet que
`random_pet.nom`. Le bloc `moved` fournit ce lien et le plan applique le
déplacement **avant** de calculer le diff. Il fonctionne aussi pour changer
d'index (`count` → `for_each`, E24.6, BF24.2), entrer dans un module
(L24.4) ou en sortir. Il ne fonctionne pas pour changer de **type** de
ressource ni pour changer d'état distant.
:::

---

## 24.6 Labs

### **L24.1** — *Template cloud-init et VM sur mesure avec `qm` et un snippet*

*Remplacer une VM « modèle » maintenue à la main par le template 9100 et un
user-data versionné ; VM `ci-test` 9110 avec docker, snapshot, resize,
script `ci-vm.sh`.*

**Étape 1 — template et snippets.** Sur le nœud :

```bash
qm config 9100 | grep -E '^(template|agent|ide2):'
pvesm status                       # local doit être « active »
pvesm set local --content iso,vztmpl,backup,snippets
ls -d /var/lib/vz/snippets         # créé par pvesm set
```

**Étape 2 — le user-data.** `~/lab24/cloud-init/ci-test.yaml` complété :

```yaml
#cloud-config
hostname: ci-test
fqdn: ci-test.lab.local
manage_etc_hosts: true
users:
  - name: mathieu
    groups: [sudo, docker]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: true
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... mathieu@lab-adm
package_update: true
packages:
  - qemu-guest-agent
  - htop
  - docker.io
write_files:
  - path: /etc/lab24-marker
    permissions: "0644"
    content: |
      ci-test provisionne par cloud-init
runcmd:
  - systemctl enable --now qemu-guest-agent
  - usermod -aG docker mathieu
final_message: "cloud-init termine en $UPTIME s (version $VERSION)"
```

```bash
cd ~/lab24/cloud-init
cloud-init schema --config-file ci-test.yaml        # Valid schema
scp ci-test.yaml root@10.10.10.1:/var/lib/vz/snippets/
```

**Étape 3 — clone et comparaison.** Sur le nœud :

```bash
qm clone 9100 9110 --name ci-test --full 1
qm cloudinit dump 9110 user > /tmp/ud-avant.yaml     # généré par Proxmox
qm set 9110 --cicustom user=local:snippets/ci-test.yaml \
  --ipconfig0 ip=10.10.10.110/24,gw=10.10.10.1 \
  --nameserver 10.10.10.1 --searchdomain lab.local --memory 2048
qm cloudinit dump 9110 user > /tmp/ud-apres.yaml     # = ton snippet
diff /tmp/ud-avant.yaml /tmp/ud-apres.yaml | head
```

Avant : un `#cloud-config` généré (`hostname: ci-test`, `user: mathieu`,
`ssh_authorized_keys`, `package_upgrade: false`, `manage_etc_hosts: true`).
Après : ton fichier, octet pour octet.

**Étape 4 — démarrage et vérification.**

```bash
qm start 9110
until qm agent 9110 ping >/dev/null 2>&1; do sleep 2; done
```

```bash
ssh mathieu@10.10.10.110 'hostname -f; id -nG; docker version --format \
  "{{.Server.Version}}"; cat /etc/lab24-marker; cloud-init status --long'
# ci-test.lab.local
# mathieu sudo docker
# 24.0.7
# ci-test provisionne par cloud-init
# status: done
# boot_status_code: enabled-by-generator
# last_update: ...
# detail: DataSourceNoCloud [seed=/dev/sr0][dsmode=net]
```

**Étape 5 — snapshot et retour.**

```bash
qm snapshot 9110 avant-test --description "L24.1 étape 5"
ssh mathieu@10.10.10.110 'sudo apt-get install -y cowsay >/dev/null
  which cowsay'
qm rollback 9110 avant-test && qm start 9110
until qm agent 9110 ping >/dev/null 2>&1; do sleep 2; done
ssh mathieu@10.10.10.110 'which cowsay || echo cowsay absent'
```

**Étape 6 — disque.**

```bash
ssh mathieu@10.10.10.110 'df -h / | tail -1'        # 20G
qm disk resize 9110 scsi0 +5G
qm reboot 9110
until qm agent 9110 ping >/dev/null 2>&1; do sleep 2; done
ssh mathieu@10.10.10.110 'lsblk /dev/sda; df -h / | tail -1'   # 25G
```

**Étape 7 — `ci-vm.sh`.** `~/lab24/bin/ci-vm.sh` :

```bash
#!/usr/bin/env bash
# ci-vm.sh <vmid> <nom> <ip> — clone 9100 avec le snippet ci-test.yaml
set -euo pipefail
[ $# -eq 3 ] || { echo "usage: $0 <vmid> <nom> <ip>" >&2; exit 2; }
VMID=$1 NOM=$2 IP=$3
NODE=${NODE:-root@10.10.10.1}
TPL=${TPL:-9100}
SNIPPET=${SNIPPET:-local:snippets/ci-test.yaml}
TIMEOUT=${TIMEOUT:-180}

pve() { ssh -o BatchMode=yes "$NODE" "$@"; }

pve qm status "$VMID" >/dev/null 2>&1 \
  && { echo "VMID $VMID déjà utilisé" >&2; exit 1; }

echo "== clone $TPL -> $VMID ($NOM)"
pve qm clone "$TPL" "$VMID" --name "$NOM" --full 1
pve qm set "$VMID" --cicustom "user=$SNIPPET" \
  --ipconfig0 "ip=$IP/24,gw=10.10.10.1" \
  --nameserver 10.10.10.1 --searchdomain lab.local --memory 2048
pve qm start "$VMID"

echo "== attente de l'agent (max ${TIMEOUT}s)"
t0=$(date +%s)
until pve qm agent "$VMID" ping >/dev/null 2>&1; do
  if [ $(( $(date +%s) - t0 )) -ge "$TIMEOUT" ]; then
    echo "agent muet après ${TIMEOUT}s (qemu-guest-agent absent ?)" >&2
    exit 3
  fi
  sleep 3
done
echo "== agent OK après $(( $(date +%s) - t0 ))s, test ssh"
until ssh -o BatchMode=yes -o ConnectTimeout=3 \
      -o StrictHostKeyChecking=accept-new "mathieu@$IP" true 2>/dev/null; do
  [ $(( $(date +%s) - t0 )) -ge "$TIMEOUT" ] \
    && { echo "ssh injoignable après ${TIMEOUT}s" >&2; exit 4; }
  sleep 3
done
ssh "mathieu@$IP" 'hostname; cat /etc/lab24-marker'
echo "== $NOM ($VMID) prêt en $(( $(date +%s) - t0 ))s"
```

```bash
chmod +x ~/lab24/bin/ci-vm.sh
~/lab24/bin/ci-vm.sh 9111 ci-test2 10.10.10.111
bash ~/workbook/scripts/check/check_M24_01.sh
```

::: pourquoi
Le snippet remplace la VM « modèle » par deux artefacts versionnables : une
image officielle (reproductible, datée) et un YAML de 25 lignes (diff-able,
relu en PR). Le hostname du snippet (`ci-test`) est identique pour 9110 et
9111 : c'est la limite de `--cicustom user=` avec un fichier fixe, que
L24.4/D24 lèvent en générant un snippet **par VM** avec `templatefile`.
Le `rollback` restaure le disque et la configuration au moment du snapshot,
mais Proxmox arrête la VM pour le faire (pas de snapshot RAM sans
`--vmstate`), d'où le `qm start` derrière. Le `resize` ne touche que le
volume : c'est cloud-init (`growpart` puis `resizefs`, modules **per-always**)
qui agrandit la partition et le système de fichiers au boot suivant — sans
reboot, `sudo growpart /dev/sda 1 && sudo resize2fs /dev/sda1` fait la même
chose. `ci-vm.sh` code en dur ce que L24.2 va décrire : c'est volontaire,
pour mesurer ensuite ce que l'outil déclaratif apporte (idempotence, état,
plan).
:::

::: piege
`--cicustom` exige que le stockage expose le type `snippets` **et** que le
fichier existe au moment du `qm start` : sinon la VM démarre sans user-data,
sans message. Après modification du snippet sur le nœud, Proxmox ne régénère
l'ISO qu'au prochain démarrage (ou `qm cloudinit update`), et cloud-init ne rejoue que si
l'`instance-id` change (le hash inclut le contenu du `cicustom`, donc oui).
:::

---

### **L24.2** — *Le lab en code : cinq VM avec OpenTofu et `for_each`*

*Cinq VM `lab2` (9101–9105, 10.10.10.101–105) depuis un seul `tofu apply`,
une map de variables, un plan lisible.*

**Étape 1 — versions et provider.** `~/lab24/02-lab2/versions.tf` (posé par
le setup) :

```hcl
terraform {
  required_version = ">= 1.6"
  required_providers {
    proxmox = { source = "bpg/proxmox", version = "~> 0.7" }
  }
}
```

`providers.tf` :

```hcl
# endpoint et token viennent de PROXMOX_VE_ENDPOINT / PROXMOX_VE_API_TOKEN
provider "proxmox" {
  insecure = true
}
```

**Étape 2 — une VM.** `main.tf`, première version :

```hcl
variable "node_name" {
  type    = string
  default = "pve"
}

variable "ssh_pubkey" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

resource "proxmox_virtual_environment_vm" "web" {
  name            = "lab2-web"
  node_name       = var.node_name
  vm_id           = 9102
  tags            = ["lab2", "tofu"]
  on_boot         = true
  stop_on_destroy = true
  scsi_hardware   = "virtio-scsi-single" # comme le template (iothread)

  clone {
    vm_id = 9100
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 20
    discard      = "on"
    iothread     = true
    file_format  = "raw"
  }

  network_device {
    bridge = "vmbr1"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  vga {
    type = "serial0"
  }

  initialization {
    datastore_id = "local-lvm"
    interface    = "ide2"

    dns {
      domain  = "lab.local"
      servers = ["10.10.10.1"]
    }

    ip_config {
      ipv4 {
        address = "10.10.10.102/24"
        gateway = "10.10.10.1"
      }
    }

    user_account {
      username = "mathieu"
      keys     = [trimspace(file(pathexpand(var.ssh_pubkey)))]
    }
  }
}
```

```bash
cd ~/lab24/02-lab2 && set -a && . ~/lab24/.env && set +a
tofu init && tofu fmt && tofu validate   # Success! The configuration is valid.
tofu plan -out plan.bin | tee plan.txt
```

Ce qu'on note dans `notes.md` en lisant le plan :

```text
(known after apply) : id, ipv4_addresses, ipv6_addresses, mac_addresses,
  network_interface_names, disk.path_in_datastore,
  network_device.mac_address, initialization.*_file_id et .type ;
  connus : vm_id (fixé), clone.vm_id, initialization.interface = "ide2",
  started = true (défaut).
agent.timeout = "15m" (valeur par défaut affichée dans le plan).
Plan: 1 to add, 0 to change, 0 to destroy.
```

**Étape 3 — apply, SSH, plan vide.**

```bash
time tofu apply plan.bin          # ~ 60-120 s, dominé par l'attente agent
ssh -o StrictHostKeyChecking=accept-new mathieu@10.10.10.102 hostname
# lab2-web
tofu plan
# No changes. Your infrastructure matches the configuration.
```

Si le plan n'est pas vide, les dérives classiques avec un clone :
`cpu.type` (si tu ne l'avais pas déclaré, le provider compare `qemu64`
implicite à `x86-64-v2-AES` hérité du template), `scsi_hardware` (défaut `virtio-scsi-pci` chez bpg, alors que le template est en `virtio-scsi-single`, seul contrôleur où `iothread` agit), `operating_system.type`,
`vga`, `serial_device`, `disk.file_format`. Le remède est de **déclarer la
valeur réelle** (comme ci-dessus) ; `ignore_changes` reste pour les
attributs que Proxmox recalcule seul (`network_device[0].mac_address` si
généré).

**Étape 4 — généralisation.** `variables.tf` :

```hcl
variable "node_name" {
  type    = string
  default = "pve"
}

variable "ssh_pubkey" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "template_id" {
  type    = number
  default = 9100
}

variable "vms" {
  description = "Parc lab2 : nom => paramètres"
  type = map(object({
    vm_id  = number
    host   = number
    cores  = optional(number, 2)
    memory = optional(number, 2048)
    disk   = optional(number, 20)
    tags   = optional(list(string), [])
  }))

  validation {
    condition = alltrue([
      for v in var.vms : v.vm_id >= 9100 && v.vm_id <= 9199
    ])
    error_message = "vm_id doit être dans la plage 9100-9199 du module 24."
  }

  validation {
    condition = alltrue([
      for v in var.vms : v.host >= 100 && v.host <= 129
    ])
    error_message = "host (dernier octet) doit être entre 100 et 129."
  }

  validation {
    condition = (
      length(distinct([for v in var.vms : v.vm_id])) == length(var.vms)
    )
    error_message = "deux VM partagent le même vm_id."
  }
}
```

`main.tf`, version finale :

```hcl
locals {
  reseau = "10.10.10.0/24"
  gw     = "10.10.10.1"
  ips    = { for k, v in var.vms : k => cidrhost(local.reseau, v.host) }
}

moved {
  from = proxmox_virtual_environment_vm.web
  to   = proxmox_virtual_environment_vm.lab["lab2-web"]
}

resource "proxmox_virtual_environment_vm" "lab" {
  for_each = var.vms

  name            = each.key
  node_name       = var.node_name
  vm_id           = each.value.vm_id
  tags            = sort(concat(["lab2", "tofu"], each.value.tags))
  on_boot         = true
  stop_on_destroy = true
  scsi_hardware   = "virtio-scsi-single" # comme le template (iothread)

  clone {
    vm_id = var.template_id
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk
    discard      = "on"
    iothread     = true
    file_format  = "raw"
  }

  network_device {
    bridge = "vmbr1"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  vga {
    type = "serial0"
  }

  initialization {
    datastore_id = "local-lvm"
    interface    = "ide2"

    dns {
      domain  = "lab.local"
      servers = [local.gw]
    }

    ip_config {
      ipv4 {
        address = "${local.ips[each.key]}/24"
        gateway = local.gw
      }
    }

    user_account {
      username = "mathieu"
      keys     = [trimspace(file(pathexpand(var.ssh_pubkey)))]
    }
  }
}
```

`terraform.tfvars` (copie de l'exemple) :

```hcl
vms = {
  lab2-adm  = { vm_id = 9101, host = 101 }
  lab2-web  = { vm_id = 9102, host = 102 }
  lab2-db   = { vm_id = 9103, host = 103, disk = 30 }
  lab2-rhel = { vm_id = 9104, host = 104 }
  lab2-ops  = { vm_id = 9105, host = 105, memory = 4096 }
}
```

```bash
tofu fmt && tofu validate && tofu plan
#   # proxmox_virtual_environment_vm.web has moved to
#   #   proxmox_virtual_environment_vm.lab["lab2-web"]
#   # proxmox_virtual_environment_vm.lab["lab2-adm"] will be created
#   ...
# Plan: 4 to add, 0 to change, 0 to destroy.
tofu apply -auto-approve
```

**Étape 5 — outputs.** `outputs.tf` :

```hcl
output "ips" {
  description = "nom => IP"
  value       = local.ips
}

output "vm_ids" {
  value = { for k, vm in proxmox_virtual_environment_vm.lab : k => vm.vm_id }
}

output "ssh" {
  value = { for k, ip in local.ips : k => "ssh mathieu@${ip}" }
}
```

```bash
tofu apply -auto-approve >/dev/null && tofu output -json ips | jq
# { "lab2-adm": "10.10.10.101", "lab2-db": "10.10.10.103", ... }
```

**Étape 6 — idempotence et cattle.**

```bash
tofu plan                                   # No changes.
ssh mathieu@10.10.10.103 'echo donnees > ~/important.txt'
time tofu apply -replace='proxmox_virtual_environment_vm.lab["lab2-db"]' \
  -auto-approve                             # ~ 90-150 s (30 Go à cloner)
ssh -o StrictHostKeyChecking=no mathieu@10.10.10.103 'ls ~/important.txt'
# ls: cannot access '/home/mathieu/important.txt': No such file or directory
```

Les données sont **perdues** : `-/+` détruit le disque et reclone depuis le
template. Attention aussi aux clés d'hôte SSH régénérées (`ssh-keygen -R
10.10.10.103` sur `lab-adm`).

**Étape 7 — mise à jour sur place.**

```bash
sed -i 's/memory = 4096/memory = 3072/' terraform.tfvars
tofu plan
#   ~ resource "proxmox_virtual_environment_vm" "lab" {
#       ~ memory {
#           ~ dedicated = 4096 -> 3072
# Plan: 0 to add, 1 to change, 0 to destroy.
tofu apply -auto-approve
ssh root@10.10.10.1 'qm config 9105 | grep ^memory'     # memory: 3072
bash ~/workbook/scripts/check/check_M24_02.sh
```

::: pourquoi
Le passage `web` → `lab["lab2-web"]` illustre la méthode de refactoring
sûre : on commence par une ressource concrète pour découvrir les attributs
qui dérivent, puis on généralise avec `for_each` et un `moved`, sans jamais
recréer ce qui existe. La variable `vms` porte trois idées : `optional()`
avec valeur par défaut évite de répéter `cores`/`memory` sur chaque VM ;
les `validation` traduisent une politique (plage réservée) en erreur avant
tout appel d'API ; l'IP est **calculée** depuis un octet, donc impossible à
saisir hors réseau. `agent { enabled = true }` fait plus qu'attendre : le
provider s'en sert pour lire `ipv4_addresses` et pour faire un arrêt propre
(`shutdown` via l'agent) — `stop_on_destroy = true` court-circuite cette
attente au destroy, utile en lab. Le `-replace` sur `lab2-db` est le test
« cattle » : si tu as hésité, c'est que la VM porte des données qui
devraient être ailleurs (disque `scsi1` séparé, D24).
:::

::: piege
Trois causes d'apply qui « pend » 15 minutes puis échoue : template sans
`qemu-guest-agent` (l'agent ne répond jamais), `agent.enabled = true` mais
`--agent enabled=1` absent de la configuration Proxmox (le socket n'existe
pas), ou réseau `vmbr1` sans passerelle (cloud-init bloque sur
`package_update`). Et une cause de `403` : privilège `VM.Config.Cloudinit`
absent du rôle.
:::

---

### **L24.3** — *État distant, verrou, import et drift*

*MinIO sur `lab-ops` comme backend S3 verrouillé, migration d'état, import de
`lab-rhel`, drift, workspaces, lecture de l'état.*

**Étape 1 — MinIO.** Sur `lab-ops` :

```bash
sudo mkdir -p /srv/minio && sudo chown 1000:1000 /srv/minio
docker run -d --name minio --restart unless-stopped \
  -p 9000:9000 -p 9001:9001 -v /srv/minio:/data \
  -e MINIO_ROOT_USER=admin -e MINIO_ROOT_PASSWORD='Adm1n-lab24!' \
  quay.io/minio/minio server /data --console-address ':9001'
# client mc, sans installation : conteneur en réseau hôte
mc() { docker run --rm -i --network host -v "$HOME/.mc:/root/.mc" \
       -v "$PWD:/w" -w /w --entrypoint mc quay.io/minio/mc "$@"; }
mc alias set ops http://127.0.0.1:9000 admin 'Adm1n-lab24!'
mc mb ops/tfstate
mc version enable ops/tfstate
mc admin user add ops tofu 'Tofu-lab24-secret'
scp mathieu@10.10.10.10:lab24/03-remote/policy-tfstate.json .
mc admin policy create ops tfstate-rw policy-tfstate.json
mc admin policy attach ops tfstate-rw --user tofu
```

**Étape 2 — backend et migration.** `~/lab24/02-lab2/backend.tf` :

```hcl
terraform {
  backend "s3" {
    bucket = "tfstate"
    key    = "lab2/terraform.tfstate"
    region = "us-east-1" # arbitraire hors AWS, mais obligatoire

    endpoints = {
      s3 = "http://10.10.10.14:9000"
    }
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_lockfile                = true # verrou natif S3 (OpenTofu >= 1.10)
  }
}
```

`.env` : `AWS_ACCESS_KEY_ID=tofu` et `AWS_SECRET_ACCESS_KEY=Tofu-lab24-secret`.

```bash
set -a && . ~/lab24/.env && set +a
tofu init -migrate-state
# Do you want to copy existing state to the new backend? yes
# Successfully configured the backend "s3"! ...
ls -la terraform.tfstate*     # .backup reste ; terraform.tfstate vide ou absent
rm -f terraform.tfstate terraform.tfstate.backup
tofu state list | wc -l              # 5
```

Côté MinIO (`lab-ops`) : `mc ls --versions ops/tfstate/lab2/` montre
`terraform.tfstate` avec une version.

**Étape 3 — verrou.** Terminal 1 :

```bash
sed -i 's/memory = 3072/memory = 4096/' terraform.tfvars
tofu apply            # s'arrête sur « Enter a value: » — ne rien taper
```

Terminal 2 :

```bash
tofu plan
# Error: Error acquiring the state lock
# Error message: operation error S3: PutObject, ... PreconditionFailed:
#   At least one of the pre-conditions you specified did not hold
# Lock Info:
#   ID:        7c1c8a3e-4d5b-4e6f-9a1b-2c3d4e5f6a7b
#   Path:      tfstate/lab2/terraform.tfstate
#   Operation: OperationTypeApply
#   Who:       mathieu@lab-adm
#   Version:   1.10.x
#   Created:   2026-09-19 14:02:11 UTC
```

Terminal 1 : `yes` (ou `no`), le verrou est libéré. Verrou orphelin simulé :

```bash
tofu apply &                 # attend la confirmation en arrière-plan
sleep 5; kill -9 %1          # meurt sans libérer
tofu plan 2>&1 | grep -A1 'ID:'   # nouvel ID : celui du verrou orphelin
tofu force-unlock <ID-lu-ci-dessus>
# Do you really want to force-unlock? yes
# OpenTofu state has been successfully unlocked!
```

**Étape 4 — import de `lab-rhel`.** `imports.tf` :

```hcl
import {
  to = proxmox_virtual_environment_vm.rhel
  id = "pve/9004"
}
```

```bash
tofu plan -generate-config-out=rhel.tf
# Plan: 1 to import, 0 to add, 1 to change, 0 to destroy.
```

`rhel.tf` généré contient tous les attributs lus (`acpi`, `bios`,
`boot_order`, `disk { … }`, `network_device { mac_address = … }`,
`initialization { … }` vide, `started`, `vga`, etc.). Nettoyé jusqu'au plan
sans modification :

```hcl
# VM créée à la main avant le module 24 : adoptée, pas reconstruite.
resource "proxmox_virtual_environment_vm" "rhel" {
  name      = "lab-rhel"
  node_name = "pve"
  vm_id     = 9004
  tags      = ["lab"]
  on_boot   = true

  cpu {
    cores = 2
    type  = "x86-64-v2-AES" # valeur lue par generate-config
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 20
    file_format  = "raw"
  }

  network_device {
    bridge = "vmbr1"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    prevent_destroy = true
    # attributs posés par l'installation manuelle, non gérés ici :
    # l'adresse MAC est celle attribuée à la création, le bloc
    # initialization est vide car la VM n'a pas de lecteur cloud-init.
    ignore_changes = [
      network_device[0].mac_address,
      initialization,
      boot_order,
      vga,
      scsi_hardware,
    ]
  }
}
```

```bash
tofu plan
# Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.
tofu apply -auto-approve
tofu state show proxmox_virtual_environment_vm.rhel | head -20
```

Une fois importé, le bloc `import` peut rester (il est ignoré quand la
ressource est déjà dans l'état) ou être supprimé à la PR suivante.

**Étape 5 — drift.**

```bash
ssh root@10.10.10.1 qm set 9105 --memory 3072
tofu plan
# Note: Objects have changed outside of OpenTofu
#   ~ resource "proxmox_virtual_environment_vm" "lab" {  ["lab2-ops"]
#       ~ memory { ~ dedicated = 4096 -> 3072 }
# ...
#   ~ memory { ~ dedicated = 3072 -> 4096 }
# Plan: 0 to add, 1 to change, 0 to destroy.
tofu plan -refresh-only
# This is a refresh-only plan, so OpenTofu will not take any actions to
# undo these. ...                   (pas de ligne « Plan: » : état seul)
```

Option 1, revenir au code : `tofu apply -auto-approve` → Proxmox repasse à
4096, plan vide. Option 2, accepter la réalité : refais `qm set 9105 --memory
3072`, puis :

```bash
tofu apply -refresh-only -auto-approve    # l'état dit 3072, le code 4096
tofu plan                                 # ~ 3072 -> 4096 : le code doit suivre
sed -i 's/memory = 4096/memory = 3072/' terraform.tfvars
tofu plan                                 # No changes.
```

**Étape 6 — workspaces.**

```bash
tofu workspace new recette
tofu plan | tail -1
# Plan: 1 to import, 5 to add, 0 to change, 0 to destroy.
```

Sur MinIO : `mc ls ops/tfstate/env:/recette/lab2/` (la clé devient
`env:/recette/lab2/terraform.tfstate` après le premier apply). Retour :
`tofu workspace select default`. Dans `notes.md` : les workspaces partagent
**le même backend, les mêmes identifiants, le même code et la même plage de
VMID** ; ils ne séparent ni les droits, ni le blast radius, ni la revue —
un `apply` dans le mauvais workspace crée ou détruit de la prod. Prod et
recette = deux racines (ou deux dépôts), deux clés d'état, deux tokens.

**Étape 7 — lecture de l'état.**

```bash
tofu state pull \
  | jq '.resources[] | {type, name, instances: (.instances | length)}'
# { "type": "proxmox_virtual_environment_vm", "name": "lab", "instances": 5 }
# { "type": "proxmox_virtual_environment_vm", "name": "rhel", "instances": 1 }
tofu state pull | jq '{serial, lineage}'
tofu state pull | grep -c "$(cut -d' ' -f2 ~/.ssh/id_ed25519.pub)"     # 5
bash ~/workbook/scripts/check/check_M24_03.sh
```

Ta clé publique est dans chaque instance (`initialization[].user_account[]
.keys`). Ce n'est pas un secret, mais l'état contiendrait de la même façon
un `password` cloud-init ou un mot de passe de base de données : le bucket
doit être **privé**, réservé à l'utilisateur `tofu`, versionné (retour
arrière) et idéalement servi en TLS.

::: pourquoi
`-migrate-state` copie l'état local vers le backend puis le vide ; le
`lineage` est conservé, donc le backend accepte ensuite les pushes de ce
seul projet. Les `skip_*` désactivent les appels propres à AWS (STS,
métadonnées EC2, validation de région) que MinIO n'implémente pas ;
`skip_s3_checksum` évite l'en-tête de checksum SDK v2 que MinIO rejette
selon les versions. Le verrou `use_lockfile` remplace l'ancienne table
DynamoDB : un objet `.tflock` écrit avec `If-None-Match: *`, donc atomique
côté S3. L'import avec `-generate-config-out` évite de deviner le schéma,
mais il génère **tout**, y compris des attributs calculés : le travail
consiste à ne garder que ce qu'on veut réellement gérer, et
`ignore_changes` documente le reste. Le drift a deux réponses légitimes ;
la seule illégitime est de laisser le plan non vide.
:::

::: piege
Un `terraform.tfstate` local non vide **après** migration signifie que
`init` a été relancé sans backend (fichier `backend.tf` absent au moment du
`init`) : deux états divergent silencieusement. Autre piège : `force-unlock`
avec un verrou légitime détenu par un collègue → deux applies concurrents,
c'est-à-dire l'incident que le verrou devait empêcher. D'où la règle :
on lit `Who` et `Created`, on appelle, puis on déverrouille.
:::

---

### **L24.4** — *Module `vm-ubuntu`, versionnage et inventaire Ansible généré*

*Extraire un module, migrer `lab2` dedans sans recréation, snippet par VM,
version par tag git, inventaire Ansible généré, qualité (`fmt`, `validate`,
pre-commit, `tofu test`).*

**Étape 1 — le module.** `~/lab24/modules/vm-ubuntu/versions.tf` :

```hcl
terraform {
  required_version = ">= 1.6"
  required_providers {
    proxmox = { source = "bpg/proxmox", version = "~> 0.7" }
  }
}
```

`variables.tf` :

```hcl
variable "name" {
  type = string
}

variable "vm_id" {
  type = number
}

variable "ip" {
  description = "adresse IPv4 sans masque"
  type        = string
}

variable "cidr_bits" {
  type    = number
  default = 24
}

variable "gateway" {
  type    = string
  default = "10.10.10.1"
}

variable "dns_servers" {
  type    = list(string)
  default = ["10.10.10.1"]
}

variable "domain" {
  type    = string
  default = "lab.local"
}

variable "node_name" {
  type    = string
  default = "pve"
}

variable "template_id" {
  type    = number
  default = 9100
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 2048
}

variable "disk_gb" {
  type    = number
  default = 20
}

variable "datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "bridge" {
  type    = string
  default = "vmbr1"
}

variable "ssh_keys" {
  description = "clés publiques autorisées pour l'utilisateur mathieu"
  type        = list(string)
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "user_data" {
  description = "user-data #cloud-config complet ; null = user_account"
  type        = string
  default     = null

  validation {
    condition = (
      var.user_data == null || startswith(var.user_data, "#cloud-config")
    )
    error_message = "user_data doit commencer par #cloud-config."
  }
}

variable "snippets_datastore" {
  type    = string
  default = "local"
}
```

`main.tf` :

```hcl
locals {
  avec_snippet = var.user_data != null
}

# Snippet posé sur le nœud (via SSH) seulement si un user_data est fourni.
resource "proxmox_virtual_environment_file" "user_data" {
  count = local.avec_snippet ? 1 : 0

  content_type = "snippets"
  datastore_id = var.snippets_datastore
  node_name    = var.node_name

  source_raw {
    data      = var.user_data
    file_name = "${var.name}-user-data.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name            = var.name
  node_name       = var.node_name
  vm_id           = var.vm_id
  tags            = sort(var.tags)
  on_boot         = true
  stop_on_destroy = true
  scsi_hardware   = "virtio-scsi-single" # comme le template (iothread)

  clone {
    vm_id = var.template_id
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_gb
    discard      = "on"
    iothread     = true
    file_format  = "raw"
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  vga {
    type = "serial0"
  }

  initialization {
    datastore_id = var.datastore_id
    interface    = "ide2"

    dns {
      domain  = var.domain
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${var.ip}/${var.cidr_bits}"
        gateway = var.gateway
      }
    }

    # user_account et user_data_file_id sont exclusifs chez bpg :
    # avec un snippet, c'est le snippet qui doit créer l'utilisateur.
    dynamic "user_account" {
      for_each = local.avec_snippet ? [] : [1]
      content {
        username = "mathieu"
        keys     = var.ssh_keys
      }
    }

    user_data_file_id = (
      local.avec_snippet
      ? proxmox_virtual_environment_file.user_data[0].id
      : null
    )
  }
}
```

`outputs.tf` :

```hcl
output "vm_id" {
  value = proxmox_virtual_environment_vm.this.vm_id
}

output "name" {
  value = proxmox_virtual_environment_vm.this.name
}

locals {
  init = proxmox_virtual_environment_vm.this.initialization[0]
  cidr = local.init.ip_config[0].ipv4[0].address
}

output "ip" {
  # lue sur la ressource (et non sur var.ip) pour que tout consommateur
  # de cet output dépende de la VM créée, pas seulement de la variable
  value = split("/", local.cidr)[0]
}
```

`README.md` :

```markdown
# Module vm-ubuntu

Clone du template cloud-init Ubuntu 24.04 (`template_id`, 9100 par défaut)
sur un nœud Proxmox, avec IP statique, DNS, clé SSH et agent QEMU.

Entrées obligatoires : `name`, `vm_id`, `ip`, `ssh_keys`.
Optionnelles : `cores`, `memory`, `disk_gb`, `tags`, `template_id`,
`node_name`, `datastore_id`, `bridge`, `user_data`.

`user_data` (texte `#cloud-config`) est posé comme snippet sur le nœud et
remplace le user-data généré : il doit alors créer lui-même l'utilisateur.
Le provider a besoin du bloc `ssh {}` pour poser un snippet.
Changer `user_data` **recrée** la VM (per-instance).

Sorties : `vm_id`, `name`, `ip`.
```

**Étape 2 — migration de `lab2` dans le module.** `~/lab24/04-modules/` :
`versions.tf` (idem 02-lab2), `backend.tf` (copie exacte de L24.3 : même
bucket, même clé), `variables.tf` (`vms`, `node_name`, `ssh_pubkey`,
`template_id` comme en L24.2), `rhel.tf` (copie), `providers.tf` :

```hcl
provider "proxmox" {
  insecure = true

  ssh {
    agent    = true
    username = "root"

    node {
      name    = "pve"
      address = "10.10.10.1"
    }
  }
}
```

`main.tf` :

```hcl
locals {
  ips      = { for k, v in var.vms : k => cidrhost("10.10.10.0/24", v.host) }
  ssh_keys = [trimspace(file(pathexpand(var.ssh_pubkey)))]
}

module "vm" {
  source   = "../modules/vm-ubuntu"
  for_each = var.vms

  name        = each.key
  vm_id       = each.value.vm_id
  ip          = local.ips[each.key]
  node_name   = var.node_name
  template_id = var.template_id
  cores       = each.value.cores
  memory      = each.value.memory
  disk_gb     = each.value.disk
  tags        = concat(["lab2", "tofu"], each.value.tags)
  ssh_keys    = local.ssh_keys
}
```

Génération des `moved` :

```bash
cd ~/lab24/04-modules
for n in lab2-adm lab2-web lab2-db lab2-rhel lab2-ops; do
  printf 'moved {\n  from = proxmox_virtual_environment_vm.lab["%s"]\n' "$n"
  printf '  to   = module.vm["%s"].proxmox_virtual_environment_vm.this\n' "$n"
  printf '}\n\n'
done > moved.tf
cp ../02-lab2/terraform.tfvars .
tofu init && tofu fmt && tofu validate && tofu plan
#   # proxmox_virtual_environment_vm.lab["lab2-adm"] has moved to
#   #   module.vm["lab2-adm"].proxmox_virtual_environment_vm.this
#   ... (x5)
# Plan: 0 to add, 0 to change, 0 to destroy.
tofu apply -auto-approve
tofu state list | grep -c '^module.vm\['     # 5
```

`02-lab2/` ne doit plus être utilisé après ça (même état, code obsolète) :
un `README` ou un `mv 02-lab2 02-lab2.archive` évite l'accident.

**Étape 3 — snippet pour `lab2-ops`.** Dans `variables.tf`, ajoute
`user_data = optional(string)` à l'objet `vms` ; dans `main.tf`,
`user_data = each.value.user_data`. `terraform.tfvars` :

```hcl
vms = {
  lab2-adm  = { vm_id = 9101, host = 101 }
  lab2-web  = { vm_id = 9102, host = 102 }
  lab2-db   = { vm_id = 9103, host = 103, disk = 30 }
  lab2-rhel = { vm_id = 9104, host = 104 }
  lab2-ops = {
    vm_id     = 9105
    host      = 105
    memory    = 4096
    user_data = <<-EOT
      #cloud-config
      hostname: lab2-ops
      fqdn: lab2-ops.lab.local
      manage_etc_hosts: true
      users:
        - name: mathieu
          groups: [sudo, docker]
          shell: /bin/bash
          sudo: "ALL=(ALL) NOPASSWD:ALL"
          lock_passwd: true
          ssh_authorized_keys:
            - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... mathieu@lab-adm
      packages: [qemu-guest-agent, docker.io]
      runcmd:
        - systemctl enable --now qemu-guest-agent
    EOT
  }
}
```

```bash
ssh-add -l >/dev/null || ssh-add ~/.ssh/id_ed25519     # agent pour le provider
ssh root@10.10.10.1 true                       # clé root déjà posée
tofu plan
#   # module.vm["lab2-ops"].proxmox_virtual_environment_file.user_data[0]
#   #   will be created
#   # module.vm["lab2-ops"].proxmox_virtual_environment_vm.this must be replaced
# -/+ resource "proxmox_virtual_environment_vm" "this" {
#       ~ initialization {
#           - user_account { ... }
#           + user_data_file_id = (known after apply) # forces replacement
# Plan: 2 to add, 0 to change, 1 to destroy.
tofu apply -auto-approve
ssh mathieu@10.10.10.105 'docker version --format {{.Server.Version}}'
```

C'est une **recréation** parce que le provider déclare `user_data_file_id`
`ForceNew` : cloud-init n'applique un nouveau user-data qu'à une nouvelle
instance ; modifier l'attribut sur une VM existante ne changerait rien dans
la VM, et l'état mentirait. Le provider préfère recloner pour que « ce qui
est déclaré » soit « ce qui est appliqué ».

**Étape 4 — versionnage du module.**

```bash
cd ~/lab24 && git init -q && git add -A && git commit -qm "module vm-ubuntu"
git tag v0.1.0
cd 04-modules
SRC='git::file:///home/mathieu/lab24//modules/vm-ubuntu?ref=v0.1.0'
sed -i "s|source   = \"../modules/vm-ubuntu\"|source   = \"$SRC\"|" main.tf
tofu init -upgrade   # Downloading git::file:///home/mathieu/lab24?ref=v0.1.0...
tofu plan | tail -1        # No changes.
# une valeur par défaut que la racine ne surcharge pas (memory l'est)
sed -i 's/default = "lab.local"/default = "lab2.local"/' \
  ../modules/vm-ubuntu/variables.tf
git -C ~/lab24 commit -qam "domaine lab2.local par défaut"
tofu init -upgrade && tofu plan | tail -1     # toujours No changes : ref=v0.1.0
git -C ~/lab24 revert -q --no-edit HEAD       # on annule (nouveau commit)
```

**Étape 5 — inventaire.** Ajoute `local` aux `required_providers` de
`04-modules/versions.tf`. `templates/inventory.tftpl` :

```text
# généré par OpenTofu (04-modules) — ne pas éditer
[lab2]
%{ for name in sort(keys(vms)) ~}
${name} ansible_host=${vms[name]}
%{ endfor ~}

[docker]
%{ for name in docker ~}
${name}
%{ endfor ~}

[lab2:vars]
ansible_user=mathieu
```

`inventory.tf` :

```hcl
locals {
  ips_reelles = { for k, m in module.vm : k => m.ip }
  docker      = [for k, v in var.vms : k if v.user_data != null]
}

resource "local_file" "inventory" {
  filename        = "${path.module}/../ansible/inventory.ini"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/inventory.tftpl", {
    vms    = local.ips_reelles
    docker = local.docker
  })
}
```

`outputs.tf` :

```hcl
output "ips" {
  value = local.ips_reelles
}

output "vm_ids" {
  value = { for k, m in module.vm : k => m.vm_id }
}

output "ssh" {
  value = { for k, ip in local.ips_reelles : k => "ssh mathieu@${ip}" }
}
```

```bash
tofu init && tofu apply -auto-approve
cat ~/lab24/ansible/inventory.ini
tofu plan | tail -1        # No changes.
```

Le fichier ne bouge que si `content` change, c'est-à-dire si les outputs du
module changent ; et parce que `m.ip` vient d'un **attribut de la ressource
VM**, le fichier est écrit après la création des VM.

**Étape 6 — Ansible.**

```bash
cd ~/lab24/ansible
ansible -i inventory.ini lab2 -m ping        # 5 x "pong"
ansible-playbook -i inventory.ini base.yml   # changed sur 5, puis
ansible-playbook -i inventory.ini base.yml | grep -c 'changed=0'   # 5
```

**Étape 7 — qualité.**

```bash
cd ~/lab24 && tofu fmt -check -recursive && echo FMT-OK
for d in 02-lab2 04-modules modules/vm-ubuntu; do
  (cd "$d" && tofu init -backend=false >/dev/null && tofu validate)
done
```

`~/lab24/.pre-commit-config.yaml` :

```yaml
repos:
  - repo: local
    hooks:
      - id: tofu-fmt
        name: tofu fmt -check
        entry: tofu fmt -check -recursive
        language: system
        pass_filenames: false
        files: \.tf$
      - id: tofu-validate
        name: tofu validate
        entry: >-
          bash -c 'for d in 02-lab2 04-modules modules/vm-ubuntu; do
          (cd "$d" && tofu init -backend=false >/dev/null && tofu validate)
          || exit 1; done'
        language: system
        pass_filenames: false
        files: \.tf$
```

`~/lab24/04-modules/tests/vms.tftest.hcl` :

```hcl
run "parc_lab2" {
  command = plan

  assert {
    condition     = length(output.vm_ids) == 5
    error_message = "le parc lab2 doit compter exactement 5 VM"
  }

  assert {
    condition = alltrue([
      for ip in values(output.ips) : cidrhost("${ip}/24", 0) == "10.10.10.0"
    ])
    error_message = "toutes les IP doivent appartenir à 10.10.10.0/24"
  }
}
```

```bash
cd ~/lab24/04-modules && tofu test
# tests/vms.tftest.hcl... pass
#   run "parc_lab2"... pass
#
# Success! 1 passed, 0 failed.
pip install --user pre-commit && pre-commit install && pre-commit run -a
bash ~/workbook/scripts/check/check_M24_04.sh
```

::: pourquoi
Un module est un **contrat** : ses variables sont l'API, ses outputs la
valeur rendue, son `README` la documentation ; tout le reste est un détail
d'implémentation que les trois équipes n'ont pas à lire. La migration
`lab` → `module.vm` par `moved` prouve qu'un refactoring de structure ne
coûte aucune VM. La source `git::…?ref=v0.1.0` rend la version
**explicite** : un module qui change sous les pieds de ses consommateurs est
la première cause de « ça marchait hier » ; avec un tag, chaque racine
choisit quand monter de version, et `tofu init -upgrade` est le seul moment
où le code du module change. L'output `ip` calculé depuis la ressource
plutôt que depuis la variable est le détail qui rend le graphe correct
(Q24.15). `tofu test` en mode `plan` ne crée rien mais exige un provider
configuré : c'est un test de **contrat** (nombre d'instances, invariants
réseau), pas un test d'intégration.
:::

::: piege
`user_data` avec `user_account` en même temps : le provider refuse
(`conflicts with`). Sans le bloc `ssh {}` : `proxmox_virtual_environment_file`
échoue avec « failed to open SSH client » — le token API ne suffit pas, les
snippets sont écrits par SFTP/SSH sur le nœud (`/var/lib/vz/snippets`).
Dans le `tftpl`, un `%{ for }` sans `~` produit des lignes vides et Ansible
les tolère, mais `diff` en PR devient illisible.
:::

---

## 24.7 Break & Fix

### **BF24.1** — *« Le plan veut reconfigurer une VM qui n'est pas à nous »*

*`tofu plan` veut renommer/reconfigurer `lab2-ops` ; en réalité le VMID
9105 est maintenant `sandbox-julien`. Interdit : appliquer, détruire la VM
de Julien, éditer l'état à la main, restaurer une sauvegarde à l'aveugle.*

**Diagnostic.**

```bash
cd ~/lab24/04-modules && set -a && . ~/lab24/.env && set +a
tofu state pull > ~/lab24/backup-$(date +%s).json
tofu plan -no-color | tee plan.txt | grep -E '^\s*(#|~|-/\+|\+/-)' 
#   # module.vm["lab2-ops"].proxmox_virtual_environment_vm.this
#   #   will be updated in-place
#   ~ name = "sandbox-julien" -> "lab2-ops"
#   ~ memory { ~ dedicated = 1536 -> 4096 }
#   ~ initialization { ~ ip_config { ~ ipv4 {
#       ~ address = "10.10.10.125/24" -> "10.10.10.105/24"
#   ~ tags = ["julien"] -> ["lab2", "tofu"]
```

Ce qu'on lit : OpenTofu n'annonce **pas** une création (il aurait dit
`will be created` si la VM avait disparu) mais une **mise à jour** : il a
donc trouvé une VM 9105 et l'a rafraîchie. Confirmation côté Proxmox :

```bash
ssh root@10.10.10.1 'qm config 9105 | grep -E "^(name|memory|ipconfig0|tags)"'
# name: sandbox-julien
ssh root@10.10.10.1 'grep -hE ":(qmdestroy:9105|qmclone:9100):" \
  /var/log/pve/tasks/index | tail -3'
# ...:qmdestroy:9105:terraform@pve!tofu:   (la nôtre, détruite à la main)
# ...:qmclone:9100:terraform@pve!tofu:     (clone de Julien ; l'UPID porte
#                                           le VMID source, pas 9105)
tofu state show 'module.vm["lab2-ops"].proxmox_virtual_environment_vm.this' \
  | grep -E '^\s*(id|name|vm_id)'
```

**Cause racine.** Le provider identifie une VM par `node/vmid` (Q24.12). La
VM `lab2-ops` a été détruite à la main (`qmdestroy` dans le journal des
tâches), puis Julien a cloné le template sur le premier VMID libre — 9105.
Pour OpenTofu, `module.vm["lab2-ops"]` **est** 9105 ; il lit ses attributs
et propose de les ramener à la configuration. Il n'existe aucun identifiant
secondaire (UUID) dans l'API Proxmox qui lui permettrait de voir que ce n'est
plus « sa » VM.

**Correctif.**

```bash
# 1. faire oublier 9105 à l'état, sans toucher à Proxmox
tofu state rm 'module.vm["lab2-ops"].proxmox_virtual_environment_vm.this'
# Removed module.vm["lab2-ops"].proxmox_virtual_environment_vm.this
# Successfully removed 1 resource instance(s).
# (si un snippet existe pour lab2-ops, le garder : il est encore sur le nœud)
# 2. donner à lab2-ops un VMID libre
ssh root@10.10.10.1 \
  'pvesh get /cluster/resources --type vm --output-format json' \
  | jq -r '.[].vmid' | grep -E '^91[0-9]{2}$' | sort -n   # 9101-9105, 9110...
sed -i 's/vm_id = 9105/vm_id = 9106/' terraform.tfvars
# 3. vérifier
tofu plan | tail -1
# Plan: 1 to add, 0 to change, 0 to destroy.
tofu apply -auto-approve
ssh root@10.10.10.1 'qm config 9105 | grep ^name'     # sandbox-julien, intacte
```

Si l'inventaire Ansible est généré (L24.4), il est réécrit (même IP
10.10.10.105 : le plan montre `local_file.inventory` inchangé, ou `-/+` si
tu changes l'IP).

**Prévention.**

1. Réserver la plage au code : option datacenter `next-id` de Proxmox
   (`pvesh set /cluster/options --next-id lower=100,upper=9099`), pour que
   l'interface et `qm create` sans VMID n'attribuent jamais un 91xx ;
2. droits : Julien n'a pas `VM.Allocate` sur `/`, seulement sur un pool
   `sandbox` ; les VM du code vont dans un pool `lab2` (`pool_id` dans la
   ressource) ;
3. convention visible : tag `tofu` + description « géré par OpenTofu, voir
   dépôt X » (`description = "..."` dans la ressource) ;
4. règle d'exploitation : une VM gérée se supprime par `tofu destroy
   -target`, jamais par l'interface, et un `tofu plan` en CI de nuit qui
   alerte dès qu'il n'est pas vide (détection de drift).

::: pourquoi
C'est le drift le plus dangereux parce qu'il est **plausible** : le plan
ressemble à une correction de dérive ordinaire (« quelqu'un a changé la
RAM »), et un apply automatique l'aurait exécuté. La ligne qui doit alerter
est `~ name = "sandbox-julien" -> "lab2-ops"` : un nom qui change n'est
jamais un drift innocent. `state rm` est le bon outil parce qu'il ne touche
qu'à la table de correspondance ; l'alternative déclarative `removed { from
= …  lifecycle { destroy = false } }` ne convient pas ici car l'adresse
reste déclarée dans le code (on veut la recréer ailleurs), et OpenTofu
refuse un `removed` sur une adresse encore configurée.
:::

---

### **BF24.2** — *« Le refactoring veut tout détruire »*

*`02-lab2/main.tf` passé de `count` à `for_each` ; le plan annonce 5 to
add, 5 to destroy. Interdit : appliquer, revenir à `count`, `state rm` +
`import`.*

**Diagnostic.**

```bash
cd ~/lab24/02-lab2 && set -a && . ~/lab24/.env && set +a
tofu state pull > ~/lab24/backup-$(date +%s).json
tofu state list
# proxmox_virtual_environment_vm.lab[0]
# proxmox_virtual_environment_vm.lab[1]
# ...
# proxmox_virtual_environment_vm.lab[4]
grep -n 'for_each\|count' main.tf          # for_each = var.vms
tofu plan -no-color | grep -E 'will be (created|destroyed)'
#   # proxmox_virtual_environment_vm.lab["lab2-adm"] will be created
#   # proxmox_virtual_environment_vm.lab[0] will be destroyed
#   # (because resource does not use count)
```

Le message `(because resource does not use count)` est explicite : les
instances de l'état sont indexées par entier, le code indexe par clé, et
aucune correspondance n'est déclarée. Pour retrouver **qui est qui** :

```bash
for i in 0 1 2 3 4; do
  printf '%s -> ' "$i"
  tofu state show "proxmox_virtual_environment_vm.lab[$i]" \
    | awk '/^ *name /{print $3}'
done
# 0 -> "lab2-adm"  1 -> "lab2-db"  2 -> "lab2-ops"  3 -> "lab2-rhel"
# 4 -> "lab2-web"
```

**Cause racine.** Le collègue a changé l'**adresse** de chaque instance
(`lab[0]` → `lab["lab2-adm"]`) sans dire à OpenTofu que ce sont les mêmes
objets. Pour lui, cinq adresses disparaissent (destroy) et cinq apparaissent
(create). Le `-/+` n'apparaît même pas : ce ne sont pas des remplacements,
mais deux opérations indépendantes.

**Correctif** : un fichier `moved.tf` **dans la PR** :

```hcl
moved {
  from = proxmox_virtual_environment_vm.lab[0]
  to   = proxmox_virtual_environment_vm.lab["lab2-adm"]
}

moved {
  from = proxmox_virtual_environment_vm.lab[1]
  to   = proxmox_virtual_environment_vm.lab["lab2-db"]
}

moved {
  from = proxmox_virtual_environment_vm.lab[2]
  to   = proxmox_virtual_environment_vm.lab["lab2-ops"]
}

moved {
  from = proxmox_virtual_environment_vm.lab[3]
  to   = proxmox_virtual_environment_vm.lab["lab2-rhel"]
}

moved {
  from = proxmox_virtual_environment_vm.lab[4]
  to   = proxmox_virtual_environment_vm.lab["lab2-web"]
}
```

```bash
tofu plan
#   # proxmox_virtual_environment_vm.lab[0] has moved to
#   #   proxmox_virtual_environment_vm.lab["lab2-adm"]
#   ... (x5)
# Plan: 0 to add, 0 to change, 0 to destroy.
tofu apply -auto-approve       # écrit les nouvelles adresses dans l'état
tofu state list                # lab["lab2-adm"] ... lab["lab2-web"]
```

Après merge et apply partout, les blocs `moved` peuvent être supprimés dans
une PR ultérieure (OpenTofu tolère leur présence indéfiniment).

Variante si tu as déjà fait L24.4 (état en `module.vm[…]`) : le script de
panne réindexe alors les appels de module, `module.vm[0]` … `module.vm[4]`,
et les blocs `moved` s'écrivent `from = module.vm[0]`,
`to = module.vm["lab2-adm"]` — un `moved` sur un module déplace toutes
ses ressources d'un coup.

**Pourquoi `moved` plutôt que `state mv` en équipe.** `tofu state mv`
produirait le même résultat en cinq commandes… sur **cet** état, maintenant,
depuis **ton** poste, sans trace dans git. Le reviewer ne peut pas vérifier
que la correspondance index → clé est la bonne (`lab[2]` est-il vraiment
`lab2-ops` ?) ; un collègue qui applique le même code sur un autre état
(workspace `recette`, second nœud) retombe sur 5/5 ; et si la CI applique
avant que tu aies fait le `state mv`, elle détruit. Le bloc `moved` est
relu dans le diff, voyage avec le code, s'applique partout, et le plan qui
en résulte (`0 to add`) est joint à la PR comme preuve.

**Prévention** : `for_each` dès le départ pour toute ressource à identité
(le module 24 le fait depuis L24.2) ; en revue, tout plan avec un
`to destroy` non nul sur un refactoring est un `Request changes` ; en CI,
un job `plan` qui échoue si `to destroy > 0` sans label `destroy-ok` sur la
PR.

::: pourquoi
Ce Break & Fix est la version « réelle » de E24.6 et E24.16. La sortie du
plan contient toujours la raison entre parenthèses : `(because resource
does not use count)`, `(because key ["x"] is not in for_each map)`,
`(because random_pet.nom is not in configuration)`. Lire cette parenthèse
avant de paniquer distingue un refactoring mal déclaré d'une vraie
suppression. Le mapping index → nom se lit dans l'état (attribut `name`),
jamais deviné : `count` a créé les instances dans l'ordre de la liste
d'origine, qui peut ne pas être l'ordre alphabétique.
:::

---

### **BF24.3** — *« Le token est dans le pipeline »*

*Token Proxmox en clair dans les logs CI (`tofu apply` affiche les outputs)
et dans un fichier committé. Interdit : supprimer l'output et fermer
l'incident, garder le token actuel.*

**Diagnostic : lister toutes les fuites.**

```bash
cd ~/lab24 && set -a && . ~/lab24/.env && set +a
OLD=${PROXMOX_VE_API_TOKEN#*=}                     # l'uuid seul
grep -rl --exclude-dir=.terraform "$OLD" ~/lab24 2>/dev/null
# /home/mathieu/lab24/.env                           (normal, 0600, hors git)
# /home/mathieu/lab24/02-lab2/debug.tf               1. code : default en clair
# /home/mathieu/lab24/02-lab2/ci-job-42.log          2. log CI : output affiché
# /home/mathieu/lab24/02-lab2/plan.txt               3. plan lisible commité ?
git -C ~/lab24 log --all -p -S "$OLD" --oneline | grep -E '^[0-9a-f]{7}'
# 4. historique git : commit "debug : expose le token"
cd 02-lab2 && tofu state pull | grep -c "$OLD"
# 5. état distant : outputs.debug_token + versions précédentes du bucket
git -C ~/lab24 ls-files | grep -E 'debug\.tf|\.log$|plan\.txt'   # committé ?
cat debug.tf
# variable "api_token" {
#   type    = string
#   default = "terraform@pve!tofu=3f2c9d1e-..."
# }
# output "debug_token" { value = var.api_token }
```

Au moins cinq endroits : le fichier `.tf` (`default`), le log du job, le
`plan.txt`, **l'historique git** (un `git rm` retire le fichier du prochain
commit, pas des commits précédents), et **l'état** (l'output est stocké en
clair, et MinIO garde les versions antérieures de l'objet).

**Cause racine.** Un secret a été promu en variable **avec valeur par
défaut** et exposé en output « pour le debug ». `tofu apply` affiche les
outputs en fin d'exécution, la CI les journalise, le state les persiste. Ni
`sensitive` ni `.gitignore` n'étaient là pour empêcher quoi que ce soit.

**Correctif.**

```bash
# 1. le code : plus de variable, plus d'output. Le provider lit l'environnement.
git -C ~/lab24 rm -q 02-lab2/debug.tf 02-lab2/ci-job-42.log 02-lab2/plan.txt \
  2>/dev/null || rm -f debug.tf ci-job-42.log plan.txt
tofu plan
#   Changes to Outputs:
#   - debug_token = "terraform@pve!tofu=3f2c9d1e-..." -> null
# You can apply this plan to save these new output values to the OpenTofu
# state, without changing any real infrastructure.
tofu apply -auto-approve          # retire l'output de l'état courant
# 2. rotation du token sur le nœud (l'ancien devient inerte partout)
ssh root@10.10.10.1 'pveum user token remove terraform@pve tofu; \
  pveum user token add terraform@pve tofu -privsep 0 --output-format json' \
  | jq -r .value
# 3. nouveau token dans .env (et dans la variable masquée du CI)
NEW='terraform@pve!tofu=<nouveau>'
sed -i "s|^PROXMOX_VE_API_TOKEN=.*|PROXMOX_VE_API_TOKEN=$NEW|" ~/lab24/.env
set -a && . ~/lab24/.env && set +a
# 4. vérifications
tofu state pull | grep -c "$OLD"               # 0
tofu plan | tail -1                            # No changes.
curl -sk -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: PVEAPIToken=terraform@pve!tofu=$OLD" \
  https://10.10.10.1:8006/api2/json/version     # 401 : l'ancien est mort
# 5. historique git : réécrire (dépôt local, pas encore partagé) ...
git -C ~/lab24 filter-repo --replace-text <(echo "$OLD==>REDACTED") --force
# ... ou, si le dépôt est déjà poussé : considérer l'historique compromis,
# la rotation (étape 2) est ce qui rend la fuite inoffensive.
# 6. anciennes versions de l'état sur MinIO : les purger (mc rm --versions)
#    ou accepter qu'elles contiennent un token révoqué.
```

Pour que le token ne **puisse** plus apparaître, garde la règle : aucune
variable `api_token` dans le code (le provider lit
`PROXMOX_VE_API_TOKEN`), donc ni output ni `templatefile` ne peuvent la
référencer. Si un jour une variable secrète est inévitable : `sensitive =
true`, **jamais** de `default`, valeur par `TF_VAR_` uniquement.

**Prévention** : hook pre-commit `gitleaks` (ou `detect-secrets`) + refus de
`*.tfvars`/`.env` ; en CI, `tofu apply plan.bin -no-color` avec les outputs
masqués (`tofu output` interdit dans les jobs) et variables de runner
« masked/protected » ; revue de PR qui bloque tout `output` sans
justification ; token par usage (CI ≠ poste) pour que la rotation d'un seul
n'arrête pas tout ; audit périodique `tofu state pull | grep -c token`.

::: pourquoi
Un secret suit le chemin des **données** de l'outil : code → variables →
plan → état → outputs → logs. Chaque étape le copie. Le supprimer « à la
source » ne rappelle pas les copies, et deux d'entre elles (git, versions de
l'état) sont conçues pour ne rien oublier. La seule remédiation complète
est donc la **révocation** : après rotation, toutes les copies deviennent
des chaînes inertes, et le nettoyage n'est plus qu'une question d'hygiène.
C'est pourquoi la consigne interdisait de garder le token actuel, et c'est la
réponse attendue en entretien : « la première action sur une fuite de
secret est de le révoquer, pas de le cacher ».
:::

---

### **BF24.4** — *« La VM démarre mais cloud-init n'a rien fait »*

*`bf-ci` (9120) clonée à la main, `ipconfig0` correct, prompt `ubuntu
login:`, pas d'IP, pas d'utilisateur. Interdit : réinstaller, rescue,
détruire.*

**Diagnostic depuis le nœud (deux commandes).**

```bash
ssh root@10.10.10.1
qm config 9120 | grep -E '^(ide2|cicustom|ciuser|sshkeys|ipconfig0|scsi0)'
# ipconfig0: ip=10.10.10.120/24,gw=10.10.10.1
# scsi0: local-lvm:vm-9120-disk-0,discard=on,iothread=1,size=20G
# sshkeys: ssh-ed25519%20AAAA...
#          -> aucune ligne « ide2: local-lvm:vm-9120-cloudinit »
qm cloudinit dump 9120 user | head -3
# #cloud-config
# hostname: bf-ci
# ...   -> Proxmox sait générer le user-data, mais rien ne le transporte
```

Confirmation optionnelle par la console série (`qm terminal 9120`) : le
prompt `ubuntu login:` (hostname de l'image, pas `bf-ci`) et, dans le journal
de boot, `cloud-init: ... ds-identify ... No ds found` puis `Cloud-init
disabled by cloud-init-generator`.

**Cause racine.** Le collègue a cloné puis a supprimé — ou n'a jamais eu —
le lecteur cloud-init (`qm set 9120 --delete ide2`, ou clone d'un template
sans `ide2`). Les options `ipconfig0`/`sshkeys` sont stockées dans la
configuration, mais l'ISO `cidata` qui les porte n'existe pas : au boot,
ds-identify ne trouve aucun support étiqueté `cidata`, aucun datasource
n'est retenu.

**Correctif.**

```bash
qm set 9120 --ide2 local-lvm:cloudinit
# update VM 9120: -ide2 local-lvm:cloudinit
#   ... generating cloud-init ISO
qm config 9120 | grep ^ide2      # ide2: local-lvm:vm-9120-cloudinit,media=cdrom
qm cloudinit pending 9120        # rien : ISO à jour
qm stop 9120 && qm start 9120
until qm agent 9120 ping >/dev/null 2>&1; do sleep 2; done
```

Preuve, depuis `lab-adm` :

```bash
ssh -o StrictHostKeyChecking=accept-new mathieu@10.10.10.120 \
  'hostname; cloud-init status --long; cloud-init query ds | head -5'
# bf-ci
# status: done
# boot_status_code: enabled-by-generator
# detail: DataSourceNoCloud [seed=/dev/sr0][dsmode=net]
# {
#   "_doc": "EXPERIMENTAL: The structure and format of content scoped...",
#   "meta_data": {
#     "instance_id": "4d1f0c…",
#     "local_hostname": "bf-ci"
```

**Pourquoi cloud-init « s'est lancé » au premier boot, et pourquoi le second
boot suffit sans `cloud-init clean`.** cloud-init est installé et activé
dans l'image ; à chaque démarrage, son générateur systemd exécute
`ds-identify`, qui cherche un datasource. Au premier boot, il n'a rien
trouvé : avec la politique par défaut (`notfound=disabled`), il a
**désactivé** cloud-init pour ce boot (`Cloud-init disabled by
cloud-init-generator`), sans écrire `/var/lib/cloud/instance` ni aucun
sémaphore — la VM a démarré avec le hostname de l'image
brute (`ubuntu`) et aucun compte utilisateur (c'est cloud-init qui crée même `ubuntu`). Au second boot, le lecteur est là :
ds-identify trouve `cidata`, retient NoCloud, et cloud-init voit une
instance dont l'`instance-id` n'a jamais été enregistré : c'est un premier
boot au sens de cloud-init, tous les modules per-instance s'exécutent.
`cloud-init clean` ne sert que lorsqu'une instance **a déjà été
enregistrée** avec le même `instance-id` (par exemple pour rejouer un
user-data corrigé sans changer la configuration Proxmox).

**Prévention** : ne cloner que depuis le template 9100 (qui porte `ide2`) ;
un test dans `ci-vm.sh`/le module qui vérifie `qm config | grep cloudinit`
avant `qm start` ; en OpenTofu, `initialization {}` crée le lecteur
systématiquement ; `--serial0 socket` sur le template, pour que la console
série montre le journal de boot et `ds-identify` en cas de doute.

::: pourquoi
Le datasource NoCloud est passif : il attend un support **étiqueté**
`cidata`. Proxmox fabrique ce support à la volée dans le volume
`vm-<id>-cloudinit` au démarrage (ou par `qm cloudinit update`), et
seulement si un lecteur existe pour le recevoir. La séparation « options
dans la configuration » / « lecteur qui les transporte » est la clé du
diagnostic : `qm config` dit s'il y a un transport, `qm cloudinit dump` dit
ce qu'il transporterait. Le raisonnement sur l'`instance-id` explique aussi
le cas inverse, plus fourbe : un lecteur présent mais une VM déjà
initialisée avec le **même** instance-id (clone d'une VM déjà bootée au lieu
du template) — là, seul `cloud-init clean` ou un changement de configuration
force le rejeu.
:::

---

## 24.8 Défi du module

**D24** — *`lab2` reconstruit de zéro, prêt pour Ansible, en une commande
(`make deploy`) ; `rhel` protégée survit ; module `v1.0.0` avec user-data par
VM ; second disque sur `lab2-db` ; tests ; Ansible idempotent ; pre-commit ;
rapport.*

**1. Destruction sans toucher à `rhel`.** `prevent_destroy` sur
`proxmox_virtual_environment_vm.rhel` fait échouer `tofu destroy` entier
(`Instance cannot be destroyed`). On limite la portée :

```bash
cd ~/lab24/04-modules && set -a && . ~/lab24/.env && set +a
tofu destroy -target='module.vm' -target='local_file.inventory'
# Plan: 0 to add, 0 to change, 7 to destroy.   (5 VM + 1 snippet + inventaire)
```

`-target=module.vm` couvre toutes les instances du module (VM et snippets).
`rhel` reste dans l'état et dans Proxmox. Documenté dans le `README` et dans
la cible `destroy` du Makefile.

**2. Makefile** (`~/lab24/04-modules/Makefile`, indentation par
tabulations) :

```makefile
SHELL       := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
ENV_FILE    ?= $(HOME)/lab24/.env
INVENTORY   := $(HOME)/lab24/ansible/inventory.ini
PLAYBOOK    := $(HOME)/lab24/ansible/base.yml

# charge .env pour chaque recette (seule source d'identifiants)
define load_env
set -a; . $(ENV_FILE); set +a;
endef

.PHONY: fmt validate test plan apply inventory configure deploy destroy init

init:
	$(load_env) tofu init -input=false >/dev/null

fmt:
	tofu fmt -check -recursive ..

validate: init
	$(load_env) tofu validate

test: init
	$(load_env) tofu test

plan: fmt validate
	$(load_env) tofu plan -input=false -out plan.bin
	tofu show -no-color plan.bin > plan.txt

apply:
	@test -f plan.bin || { echo "pas de plan.bin : make plan" >&2; exit 1; }
	$(load_env) tofu apply -input=false plan.bin
	rm -f plan.bin

inventory: init
	$(load_env) tofu output -json ips >/dev/null
	@test -s $(INVENTORY) && echo "inventaire : $(INVENTORY)"

configure: inventory
	ansible -i $(INVENTORY) lab2 -m ping
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK)

deploy:
	@t0=$$(date +%s); \
	$(MAKE) plan apply inventory configure; \
	echo "deploy complet en $$(( $$(date +%s) - t0 )) s"

destroy: init
	$(load_env) tofu destroy -target='module.vm' \
	  -target='local_file.inventory' -auto-approve
```

**3. Module `v1.0.0` : user-data par VM.** `modules/vm-ubuntu/variables.tf`
gagne :

```hcl
variable "packages" {
  type    = list(string)
  default = ["htop"]
}

variable "extra_disks" {
  description = "tailles (Go) des disques supplémentaires scsi1, scsi2..."
  type        = list(number)
  default     = []
}
```

`modules/vm-ubuntu/templates/user-data.tftpl` :

```yaml
#cloud-config
hostname: ${hostname}
fqdn: ${fqdn}
manage_etc_hosts: true
users:
  - name: mathieu
    groups: [sudo${contains(packages, "docker.io") ? ", docker" : ""}]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: true
    ssh_authorized_keys:
%{ for k in ssh_keys ~}
      - ${k}
%{ endfor ~}
package_update: true
packages:
  - qemu-guest-agent
%{ for p in packages ~}
  - ${p}
%{ endfor ~}
runcmd:
  - systemctl enable --now qemu-guest-agent
final_message: "${hostname} pret en $UPTIME s"
```

`modules/vm-ubuntu/main.tf`, changements :

```hcl
locals {
  user_data = coalesce(var.user_data, templatefile(
    "${path.module}/templates/user-data.tftpl", {
      hostname = var.name
      fqdn     = "${var.name}.${var.domain}"
      ssh_keys = var.ssh_keys
      packages = var.packages
  }))
}

resource "proxmox_virtual_environment_file" "user_data" {
  content_type = "snippets"
  datastore_id = var.snippets_datastore
  node_name    = var.node_name

  source_raw {
    data      = local.user_data
    file_name = "${var.name}-user-data.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  # ... inchangé ...

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_gb
    discard      = "on"
    iothread     = true
    file_format  = "raw"
  }

  dynamic "disk" {
    for_each = var.extra_disks
    content {
      datastore_id = var.datastore_id
      interface    = "scsi${disk.key + 1}"
      size         = disk.value
      discard      = "on"
      iothread     = true
      file_format  = "raw"
    }
  }

  initialization {
    datastore_id = var.datastore_id
    interface    = "ide2"
    dns {
      domain  = var.domain
      servers = var.dns_servers
    }
    ip_config {
      ipv4 {
        address = "${var.ip}/${var.cidr_bits}"
        gateway = var.gateway
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.user_data.id
  }
}
```

Le `count` conditionnel et le `dynamic "user_account"` disparaissent : un
snippet **toujours** posé, généré ou fourni. Comme `user_data_file_id`
force le remplacement, passer de v0.1.0 à v1.0.0 **recrée les cinq VM** :
c'est attendu (et documenté dans le CHANGELOG) ; le `make destroy` du
point 1 rend la question sans objet pour le formateur.

Dans `04-modules/variables.tf`, `vms` gagne `packages = optional(list(string),
["htop"])` et `extra_disks = optional(list(number), [])` ; `terraform.tfvars` :

```hcl
vms = {
  lab2-adm = { vm_id = 9101, host = 101 }
  lab2-web = { vm_id = 9102, host = 102 }
  lab2-db = {
    vm_id       = 9103
    host        = 103
    disk        = 30
    packages    = ["postgresql"]
    extra_disks = [5]
  }
  lab2-rhel = { vm_id = 9104, host = 104 }
  lab2-ops = {
    vm_id    = 9105
    host     = 105
    memory   = 4096
    packages = ["docker.io"]
  }
}
```

et `main.tf` passe `packages` et `extra_disks` au module ; `source =
"git::file:///home/mathieu/lab24//modules/vm-ubuntu?ref=v1.0.0"`. Dans
`inventory.tf`, le groupe `[docker]` se calcule désormais sur les paquets :
`docker = [for k, v in var.vms : k if contains(v.packages, "docker.io")]`.

```bash
cd ~/lab24 && git add -A && git commit -qm "vm-ubuntu v1.0.0"
git tag v1.0.0 && cd 04-modules && tofu init -upgrade
```

**4. `lab2-db` et `scsi1`** : `extra_disks = [5]` ci-dessus produit
`disk { interface = "scsi1" size = 5 }`. Vérification après apply :
`ssh mathieu@10.10.10.103 lsblk` montre `sdb 5G`, non formaté (le module 11
LVM s'en charge, ou Ansible).

**5. Test** `tests/deploy.tftest.hcl` :

```hcl
run "deploiement_lab2" {
  command = plan

  assert {
    condition     = length(var.vms) == 5
    error_message = "lab2 = 5 VM"
  }

  assert {
    condition = alltrue([
      for k, v in var.vms : v.vm_id >= 9101 && v.vm_id <= 9105
    ])
    error_message = "VMID attendus dans 9101-9105"
  }

  assert {
    condition = alltrue([
      for ip in values(output.ips) : cidrhost("${ip}/24", 0) == "10.10.10.0"
    ])
    error_message = "IP hors 10.10.10.0/24"
  }

  assert {
    condition     = length(var.vms["lab2-db"].extra_disks) == 1
    error_message = "lab2-db doit déclarer un disque supplémentaire"
  }
}
```

**6. Ansible.** `~/lab24/ansible/base.yml` enrichi (en plus du contenu
fourni) :

```yaml
    - name: /etc/hosts complet du parc lab2
      ansible.builtin.blockinfile:
        path: /etc/hosts
        marker: "# {mark} LAB2 (genere par Ansible)"
        block: |
          {% for h in groups['lab2'] | sort %}
          {{ hostvars[h].ansible_host }} {{ h }} {{ h }}.lab.local
          {% endfor %}

    - name: Paquets par rôle
      ansible.builtin.apt:
        name: "{{ paquets_role | default([]) }}"
        state: present
      when: paquets_role is defined
```

avec, dans l'inventaire généré, un `[docker:vars]` … ou plus simplement
des `group_vars/docker.yml` (`paquets_role: [docker.io]`) et
`group_vars/db.yml` si tu ajoutes un groupe `[db]` au template. Second
passage : `ansible-playbook ... | grep -c 'changed=0'` → 5.

**7. Hygiène.** `.pre-commit-config.yaml` gagne :

```yaml
      - id: no-state-no-env
        name: refuse tfstate et .env
        entry: >-
          bash -c 'f=$(git diff --cached --name-only
          | grep -E "(^|/)(\.env|.*\.tfstate(\.backup)?)$" || true);
          [ -z "$f" ] || { echo "interdit : $f"; exit 1; }'
        language: system
        pass_filenames: false
        always_run: true
```

`.gitignore` : celui du setup, plus `plan.bin`, `plan.txt`, `.terraform/`,
`ansible/inventory.ini`, `*.retry`. `README.md` :

```markdown
# lab2 en code (module 24)

image cloud --(make-template.sh)--> 9100 --(module vm-ubuntu, snippet)--> VM
   --(local_file.inventory)--> ansible/inventory.ini --(base.yml)--> prêt

* `make deploy` : fmt, validate, plan (plan.txt), apply, inventaire, Ansible
* `make destroy` : détruit module.vm ; `rhel` (prevent_destroy) survit
* identifiants : uniquement `~/lab24/.env` (0600), jamais dans le dépôt

## Rotation du token
1. `pveum user token remove terraform@pve tofu`
2. `pveum user token add terraform@pve tofu -privsep 0` → nouvelle valeur
3. mettre à jour `.env` (et la variable masquée du CI)
4. `tofu plan` doit être vide ; l'ancien token répond 401
```

**8. Livrable** : `git tag v1.0.0`, `plan.txt` de la reconstruction
(`Plan: 11 to add, 0 to change, 0 to destroy.` : 5 VM, 5 snippets, 1
inventaire), et `~/lab24/rapports/d24.md`, dont le contenu attendu :

```markdown
# D24 — rapport

Durée `make deploy` (parc vide) : 7 min 40 s (plan 15 s, apply 5 min 50 s
dont 5 clones + attente agent, Ansible 1 min 30 s).

Idempotent : plan (vide au 2e passage), apply (rien), inventory (fichier
inchangé), configure (changed=0). Non idempotent : deploy en lui-même n'est
que la somme ; destroy suivi de deploy recrée des clés d'hôte SSH
(known_hosts à purger) ; le user-data ne rejoue jamais sur une VM existante
(changement = recréation).

Risques prod :
1. État : un seul MinIO sur lab-ops, sans TLS ni sauvegarde -> S3 répliqué
   ou backend managé, TLS, chiffrement OpenTofu, sauvegarde du bucket.
2. Token : un token unique privsep 0 en .env -> un token par usage (CI, poste),
   privsep 1 avec ACL sur le pool lab2, rotation trimestrielle, gitleaks.
3. Template 9100 fabriqué à la main -> Packer (pkr.hcl versionné, template
   daté), template_id dans le tfvars, test de boot en CI avant promotion.
```

```bash
bash ~/workbook/scripts/check/check_M24_05.sh
```

::: pourquoi
Le défi assemble ce que chaque lab a introduit et le rend **opérable par
quelqu'un d'autre** : le `Makefile` transforme sept commandes et trois
sources de variables en une interface (`make deploy`), la cible `apply` qui
n'accepte que `plan.bin` impose la revue de plan par construction, et
`.env` comme seule source d'identifiants rend la rotation triviale. Le
snippet par VM généré par `templatefile` corrige la limite de L24.1 (un
hostname en dur) et réunit identité et paquets de base dans un seul
artefact revu en PR ; le prix, la recréation à chaque changement de
userdata, est exactement le modèle immutable de QO24.5. `extra_disks` en
`dynamic "disk"` montre le bon usage de `dynamic` : un nombre variable de
blocs **identiques**, pas de la logique. Enfin, `-target` pour contourner
`prevent_destroy` est la seule voie documentée ; toute autre (retirer la
ligne, `state rm`) supprime la protection elle-même.
:::

::: piege
`make` et les tabulations : une recette indentée avec des espaces échoue
avec `missing separator`. `$$` est nécessaire dans les recettes pour
obtenir un `$` shell. `-target` affiche un avertissement (`Resource
targeting is in effect`) : c'est normal ici, mais un `apply -target` en
routine est un signe que le code est mal découpé. Et `tofu test` en mode
`plan` ne détecte pas une IP en double : ajoute l'assertion
`length(distinct(values(output.ips))) == 5` si tu veux la couvrir.
:::
