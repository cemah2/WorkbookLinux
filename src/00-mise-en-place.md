# Chapitre 0 — Mise en place du laboratoire

Ce chapitre ne t'apprend pas Linux. Il te donne un laboratoire reproductible,
une méthode de travail et les réflexes qui te serviront pendant les 23 modules
et les 3 projets. Compte une demi-journée pour tout monter, et fais-le
sérieusement : chaque module suppose que ces six VM existent, avec ces noms,
ces IP et ce snapshot `snap-clean`.

---

## 0.1 Comment utiliser ce workbook

### Les livrables

| Livrable | Contenu | Quand l'ouvrir |
|---|---|---|
| PDF **énoncés** | quiz, exercices, labs, break & fix, défis | pendant le travail |
| PDF **corrigés** | réponses + blocs *pourquoi* / *piège* | après avoir cherché |
| **Mémo** | antisèches des `X.2 Rappel express` réunies | en permanence |
| **Scripts** | `setup/`, `check/`, `break/`, `lab/`, `projects/` | sur les VM |

Le PDF des corrigés n'est pas une correction scolaire : c'est là que se
trouve l'explication du mécanisme. Lis-le même quand tu as juste.

### Les trois niveaux

* **★ Exercices guidés** — une commande, un fichier, cinq minutes. Ils
  installent le geste. Tu dois pouvoir les refaire sans réfléchir.
* **★★ Labs** — un scénario d'exploitation en plusieurs étapes (ticket,
  demande d'un dev, audit). Ils installent la méthode. Chaque lab a un
  critère de succès observable et souvent un `check_MXX_YY.sh`.
* **★★★ Break & Fix et Défi** — on te casse une machine ou on te donne un
  cahier des charges. Ils installent l'autonomie. C'est le niveau attendu
  en entretien technique.

### La règle des 20 minutes

Avant d'ouvrir un corrigé : **20 minutes de recherche réelle**. `man`,
`--help`, `/usr/share/doc`, la documentation officielle, un test dans un
répertoire jetable. Pas une vidéo, pas une IA qui te donne la commande.
Au bout de 20 minutes, tu ouvres le corrigé, tu lis le bloc *pourquoi*, tu
refermes, et tu **refais l'exercice sans regarder**. Si tu n'y arrives
toujours pas, note-le dans ton carnet (§0.7) : c'est ça qu'il faudra
réviser, pas ce que tu as réussi.

### Les identifiants

Chaque item porte un identifiant unique, le même dans les deux PDF :

| Format | Exemple | Type |
|---|---|---|
| `Q<mod>.<n>` / `QO<mod>.<n>` | `Q7.3`, `QO7.2` | QCM / question ouverte |
| `E<mod>.<n>` / `L<mod>.<n>` | `E7.12`, `L7.2` | exercice guidé / lab |
| `BF<mod>.<n>` / `D<mod>` | `BF7.1`, `D7` | break & fix / défi |

Cite-les tels quels dans ton carnet, tes commits et tes questions à un
collègue : « je bloque sur L10.3 étape 4 » est plus utile que « le truc LVM ».

### Les scripts

Trois familles, toutes dans `~/workbook/scripts/` sur les VM :

```bash
# prépare l'environnement d'un module (idempotent, relançable)
sudo bash ~/workbook/scripts/setup/setup_M07.sh
# vérifie le RÉSULTAT d'un lab (pas la méthode) : 0 = réussi
bash ~/workbook/scripts/check/check_M07_02.sh
# casse volontairement la machine pour un Break & Fix
sudo bash ~/workbook/scripts/break/break_M07_02.sh
```

Un `check` échoue avec un indice, jamais la solution. Un `break` sauvegarde
ce qu'il casse dans `/root/.breakfix-backup/` et n'affiche que le symptôme.
Tu peux lire le code des `break` **après** avoir résolu la panne, pas avant.

### Le planning

Environ 170 heures de travail. À 12 h par semaine, ça tient en 14 semaines ;
le tableau ci-dessous en prévoit 16 avec de la marge. Pour tenir en 12,
fusionne les semaines 9-10 et 15-16.

| Semaine | Modules / projets | Heures | Jalon |
|---|---|---|---|
| 1 | 01 shell, 02 système de fichiers | 9 | lab monté, carnet ouvert |
| 2 | 03 permissions, 04 utilisateurs et sudo | 10 | premier Break & Fix |
| 3 | 05 traitement de texte, 06 vim et archives | 11 | rapport `access.log` |
| 4 | 07 scripting bash | 7 | dépôt Git perso créé |
| 5 | 08 processus et systemd, 09 paquets | 12 | un service maison durci |
| 6 | 10 stockage et LVM | 8 | disque de VM agrandi à chaud |
| 7 | 11 réseau, 12 SSH | 13 | bastion + `~/.ssh/config` |
| 8 | 13 logs et supervision, 14 planification | 11 | logs centralisés |
| 9 | 15 sécurité | 8 | pare-feu multi-machines |
| 10 | 16 dépannage et incident | 10 | premier post-mortem |
| 11 | P1 « Factura » à la main | 10 | app déployée, documentée |
| 12 | 17 Git, 18 Docker et Compose | 12 | image publiée sur registre |
| 13 | 19 Ansible, 20 OpenTofu / cloud-init | 14 | VM créée par le code |
| 14 | 21 CI/CD Gitea Actions, 22 k3s + observabilité | 14 | pipeline vert |
| 15 | 23 Python pour l'ops | 8 | outil packagé sous timer |
| 16 | P2 « Factura » industrialisée | 12 | `git push` → prod |
| 17 | P3 une semaine d'astreinte | 10 | 5 incidents résolus |

Les heures sont celles des `Temps estimé` des modules. Si tu débordes de
30 %, c'est normal. Si tu débordes de 100 %, tu ne respectes pas la règle
des 20 minutes ou tu lis les corrigés avant de chercher.

---

## 0.2 Pourquoi Ubuntu 24.04 + Rocky 9

Ubuntu Server 24.04 LTS est la distribution de référence du workbook : c'est
celle que tu croiseras le plus souvent dans le cloud, sur les runners de CI,
dans les images Docker et dans les tutoriels — et son support court jusqu'en
2029. Rocky Linux 9 est la reconstruction libre de RHEL 9 : c'est la famille
qu'on trouve dans les grandes entreprises, les banques, l'industrie et les
certifications RHCSA. Les deux se distinguent sur les paquets (`apt`/`dnf`),
le pare-feu (`ufw`/`firewalld`), le contrôle d'accès obligatoire
(AppArmor/SELinux), la configuration réseau (Netplan/NetworkManager) et
quelques chemins. Savoir passer de l'une à l'autre sans hésiter est une
compétence recherchée en soi ; les blocs `::: rhel` des modules te donnent
la variante Rocky à chaque fois que ça diffère. Debian, Alma, Fedora et
SUSE se déduisent de ces deux-là en quelques minutes.

---

## 0.3 Le laboratoire Proxmox

### Topologie

| VM | VMID / IP | Ressources | Rôle |
|---|---|---|---|
| `lab-adm` (Ubuntu 24.04) | 9001 / 10.10.10.10 | 2 vCPU, 2 Go, 20 Go | admin, bastion, Ansible |
| `lab-web` (Ubuntu 24.04) | 9002 / 10.10.10.11 | 2 vCPU, 2 Go, 20 Go | web, reverse proxy, app |
| `lab-db` (Ubuntu 24.04) | 9003 / 10.10.10.12 | 2 vCPU, 2 Go, 30 Go + 2×5 Go | base de données, LVM |
| `lab-rhel` (Rocky 9) | 9004 / 10.10.10.13 | 2 vCPU, 2 Go, 20 Go | dnf, firewalld, SELinux |
| `lab-ops` (Ubuntu 24.04) | 9005 / 10.10.10.14 | 2 vCPU, 4 Go, 40 Go | Docker, CI, monitoring |
| `lab-git` (Ubuntu 24.04) | 9006 / 10.10.10.15 | 1 vCPU, 1 Go, 15 Go | forge Gitea, portfolio |

Total : 11 vCPU (surallocation acceptable), 13 Go de RAM, 155 Go de disque.
Un nœud avec 16 Go de RAM et un SSD suffit ; les VM n'ont pas besoin de
tourner toutes en même temps avant le module 11 — sauf `lab-git`, qui
héberge ton dépôt (§0.8) et reste allumée en permanence.

```
                       Internet
                          |
                    [ ta box / LAN ]  192.168.1.0/24
                          |
   poste Windows / Ubuntu |   192.168.1.50 (vmbr0)
   ------------------------+-----------------------------------
                    | NŒUD PROXMOX VE 8                       |
                    |   vmbr0 : bridge LAN (existant)         |
                    |   vmbr1 : 10.10.10.1/24, isolé, NAT     |
                    |   :2222 --DNAT--> lab-adm:22            |
                    +-----------------+-----------------------+
                                      | vmbr1  10.10.10.0/24
     +-----------+-----------+--------+-+---------+-----------+-----------+
     |           |           |          |         |           |
  lab-adm     lab-web     lab-db     lab-rhel   lab-ops     lab-git
 .10 (9001)  .11 (9002)  .12 (9003) .13 (9004) .14 (9005)  .15 (9006)
 bastion     nginx/app   PostgreSQL Rocky 9    Docker/CI   Gitea
 Ansible                 sdb, sdc   SELinux    k3s/Grafana workbook
```

Le lab est sur un réseau **isolé** : les VM sortent sur internet grâce au
NAT du nœud, mais rien depuis ton LAN n'entre, sauf le port 2222 qui mène
au SSH de `lab-adm`. Toutes les autres VM s'atteignent en rebondissant sur
`lab-adm` (`ProxyJump`, §0.4). C'est volontairement la topologie d'un vrai
bastion. Seule exception, ajoutée au §0.8 : le port 3000 de `lab-git`
(l'interface web de Gitea), publié lui aussi par DNAT.

Dans tout le chapitre, `192.168.1.50` désigne l'IP LAN de ton nœud Proxmox
et `192.168.1.0/24` ton LAN. Remplace-les par les tiens.

### Le bridge `vmbr1` et le NAT

Sur le nœud Proxmox, en root. D'abord, récupère les scripts du lab :

```bash
mkdir -p /root/lab
# depuis ton poste : scp -r scripts/lab root@192.168.1.50:/root/lab/
cp /root/lab/lab/*.sh /root/lab/ && chmod +x /root/lab/*.sh
```

Édite `/root/lab/lab-nat.sh` si ton LAN n'est pas `192.168.1.0/24` ou si ton
bridge externe n'est pas `vmbr0` (variables `LAN_NET` et `WAN_IF` en tête de
fichier). Puis ajoute le bridge à `/etc/network/interfaces`, **à la suite**
de la définition de `vmbr0`, sans toucher à celle-ci :

```ini
auto vmbr1
iface vmbr1 inet static
    address 10.10.10.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    post-up   /root/lab/lab-nat.sh up
    post-down /root/lab/lab-nat.sh down
```

`lab-nat.sh` applique exactement ces règles (et les retire au `down`) :

```bash
sysctl -w net.ipv4.ip_forward=1
# les VM sortent avec l'IP du nœud, sauf vers ton LAN
iptables -t nat -A POSTROUTING -s 10.10.10.0/24 ! -d 192.168.1.0/24 \
  -o vmbr0 -j MASQUERADE
# le port 2222 du nœud mène au SSH de lab-adm
iptables -t nat -A PREROUTING -i vmbr0 -p tcp --dport 2222 \
  -j DNAT --to-destination 10.10.10.10:22
# le port 3000 du nœud mène à l'interface web de Gitea sur lab-git (§0.8)
iptables -t nat -A PREROUTING -i vmbr0 -p tcp --dport 3000 \
  -j DNAT --to-destination 10.10.10.15:3000
# FORWARD : inoffensif si la politique est ACCEPT, indispensable sinon
iptables -A FORWARD -s 10.10.10.0/24 -j ACCEPT
iptables -A FORWARD -d 10.10.10.0/24 -m conntrack \
  --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -d 10.10.10.10 -p tcp --dport 22 -j ACCEPT
iptables -A FORWARD -d 10.10.10.15 -p tcp --dport 3000 -j ACCEPT
```

Rends `ip_forward` persistant et active le bridge :

```bash
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-lab.conf
ifreload -a                      # ou : ifup vmbr1
ip -br addr show vmbr1           # vmbr1  UP  10.10.10.1/24
/root/lab/lab-nat.sh status
```

::: attention
Si le pare-feu Proxmox est activé au niveau *Datacenter* (`Datacenter →
Firewall → Options`), il filtre aussi le trafic transitant par le nœud.
Soit tu le laisses désactivé pour le lab, soit tu ajoutes une règle d'entrée
`tcp/2222` et tu vérifies que le *FORWARD* n'est pas bloqué.
:::

### DNS du lab : `dnsmasq` sur le nœud

Les conventions fixent le DNS des VM à `10.10.10.1`. Le plus simple est un
`dnsmasq` sur le nœud, qui n'écoute que sur `vmbr1`, sert `lab.local` et
relaie le reste vers `9.9.9.9` :

```bash
apt-get install -y dnsmasq
cat > /etc/dnsmasq.d/lab.conf <<'EOF'
interface=vmbr1
bind-interfaces
no-dhcp-interface=vmbr1
domain=lab.local
local=/lab.local/
expand-hosts
addn-hosts=/root/lab/lab.hosts
server=9.9.9.9
EOF
cat > /root/lab/lab.hosts <<'EOF'
10.10.10.10 lab-adm
10.10.10.11 lab-web
10.10.10.12 lab-db
10.10.10.13 lab-rhel
10.10.10.14 lab-ops
10.10.10.15 lab-git
EOF
systemctl restart dnsmasq && systemctl enable dnsmasq
dig +short @10.10.10.1 lab-web.lab.local     # 10.10.10.11
```

Si tu ne veux pas de `dnsmasq`, exporte `LAB_DNS=9.9.9.9` avant de lancer
`make-templates.sh` et `lab-create.sh` : les VM résoudront quand même les
noms courts par `/etc/hosts` (déployé par `bootstrap-lab.sh`).

### Les clés SSH déployées par cloud-init

cloud-init injecte les clés publiques du fichier `/root/lab/lab-keys.pub`
dans le compte `mathieu` de chaque VM. Mets-y **toutes** les clés de tes
postes (Windows et Ubuntu, §0.4), une par ligne :

```bash
cat /root/lab/lab-keys.pub
# ssh-ed25519 AAAA... mathieu@poste-windows
# ssh-ed25519 AAAA... mathieu@poste-ubuntu
```

### Les templates cloud-init

Les images *cloud* officielles (Ubuntu `noble-server-cloudimg-amd64.img`,
Rocky `Rocky-9-GenericCloud-Base`) sont des disques préinstallés de quelques
centaines de Mo, sans mot de passe, configurés au premier démarrage par
cloud-init : utilisateur, clé SSH, IP, nom d'hôte. Un template Proxmox est
une VM gelée dont on clone des copies. Ce que fait `make-templates.sh` pour
chaque image, commande par commande :

```bash
# 1. la VM vide, sans disque, sur le bridge du lab
qm create 9000 --name tpl-ubuntu-2404 --ostype l26 --cpu host \
  --cores 2 --sockets 1 --memory 2048 --scsihw virtio-scsi-pci \
  --net0 virtio,bridge=vmbr1 --agent enabled=1 \
  --serial0 socket --vga serial0
# 2. l'image cloud devient le disque de la VM (apparaît en unused0)
qm disk import 9000 noble-server-cloudimg-amd64.img local-lvm \
  --format raw                  # « qm importdisk » : ancien nom, accepté
# 3. on l'attache en scsi0, lecteur cloud-init en ide2, boot sur scsi0
qm set 9000 --scsi0 local-lvm:vm-9000-disk-0,discard=on,ssd=1 \
  --ide2 local-lvm:cloudinit --boot order=scsi0
# 4. les valeurs cloud-init par défaut (les clones les surchargent)
qm set 9000 --ciuser mathieu --sshkeys /root/lab/lab-keys.pub \
  --ipconfig0 ip=dhcp --nameserver 10.10.10.1 --searchdomain lab.local
# 5. disque système à 20 Go (cloud-init agrandit / au premier boot)
qm resize 9000 scsi0 20G
# 6. gel en template
qm template 9000
```

Le nom du disque importé (`local-lvm:vm-9000-disk-0`) dépend du stockage :
sur un stockage de type répertoire ce serait `local:9000/vm-9000-disk-0.raw`.
Le script le lit dans `qm config 9000` au lieu de le deviner. Le port série
(`--serial0 socket --vga serial0`) te donne une console qui marche avec
`qm terminal 9001` même quand le réseau est cassé : tu en auras besoin au
module 11.

::: astuce
Les images cloud n'embarquent pas `qemu-guest-agent`. Si `libguestfs-tools`
est installé sur le nœud (`apt-get install -y libguestfs-tools`),
`make-templates.sh` l'injecte dans l'image avec `virt-customize`. Sinon
`bootstrap-lab.sh` l'installe au premier démarrage : ça marche aussi, mais
`lab-status.sh` affichera `agent=no` jusque-là.
:::

Lance la construction :

```bash
cd /root/lab && bash make-templates.sh        # ~5 min, télécharge 2 images
qm list | grep tpl-
#   9000 tpl-ubuntu-2404   stopped    2048   20.00 0
#   9010 tpl-rocky-9       stopped    2048   20.00 0
```

Le stockage (`local-lvm`) et le bridge externe (`vmbr0`) sont des variables
de `lab-env.sh` : `LAB_STORAGE=local-zfs bash make-templates.sh` si ton nœud
est en ZFS.

### Clonage des six VM : `lab-create.sh`

Le script lit la table des VM dans `lab-env.sh` et, pour chacune, enchaîne :

```bash
qm clone 9000 9001 --name lab-adm --full 1 --storage local-lvm
qm set 9001 --cores 2 --memory 2048 --onboot 1
qm set 9001 --ipconfig0 ip=10.10.10.10/24,gw=10.10.10.1 \
  --nameserver 10.10.10.1 --searchdomain lab.local \
  --ciuser mathieu --sshkeys /root/lab/lab-keys.pub
qm start 9001
```

avec, en plus, pour les VM qui sortent du standard :

```bash
qm resize 9003 scsi0 30G                  # lab-db : / à 30 Go
qm set 9003 --scsi1 local-lvm:5 --scsi2 local-lvm:5   # sdb, sdc bruts
qm resize 9005 scsi0 40G                  # lab-ops : / à 40 Go
qm set 9005 --memory 4096                 # lab-ops : 4 Go
qm set 9006 --cores 1 --memory 1024       # lab-git : 1 vCPU, 1 Go
```

`--full 1` fait un clone complet, pas un *linked clone* : chaque VM est
indépendante du template, ce qui simplifie snapshots et suppression. Les
disques `scsi1`/`scsi2` de `lab-db` apparaissent en `/dev/sdb` et
`/dev/sdc` dans la VM (contrôleur `virtio-scsi`), vierges : le module 10
les partitionne. `lab-git` est annoncée à 15 Go mais hérite du disque de
20 Go du template : `qm resize` ne sait pas réduire, et ça n'a aucune
importance.

```bash
cd /root/lab && bash lab-create.sh
```

Compte 60 à 90 secondes par VM pour le premier démarrage (cloud-init
agrandit le disque, crée l'utilisateur, régénère les clés d'hôte SSH).
Continue avec §0.4 et §0.5 ; le snapshot vient **après** le bootstrap.

### Le snapshot `snap-clean`

Une fois les six VM bootstrapées (§0.5), pose le snapshot de référence :

```bash
bash lab-create.sh snapshot
# équivaut, pour chaque VM, à :
qm snapshot 9001 snap-clean --vmstate 0 \
  --description "état propre après bootstrap-lab.sh"
```

Le snapshot est pris sans état mémoire (`--vmstate 0`) : au `rollback`, la
VM redémarre proprement. C'est ce qu'on veut pour un état de référence.

### `lab-reset.sh` et `lab-status.sh`

```bash
bash lab-reset.sh                    # rollback des 6 VM sur snap-clean
bash lab-reset.sh lab-db             # une seule
bash lab-reset.sh --snap avant-lab10 lab-db   # un autre snapshot
bash lab-reset.sh --list lab-db      # ses snapshots
bash lab-status.sh                   # statut, agent, ping, ssh, snapshot
```

`lab-reset.sh` arrête la VM si besoin, fait `qm rollback <vmid> <snap>`,
puis `qm start`. `lab-status.sh` vérifie aussi le bridge, la règle NAT et
`ip_forward`, les trois causes de « ma VM n'a pas internet ». Son code
retour est 0 quand tout est vert : tu peux l'appeler depuis un script.

Avant chaque lab destructeur, c'est toi qui poses le snapshot intermédiaire,
depuis le nœud :

```bash
qm snapshot 9003 avant-lab10             # avant le lab
qm rollback 9003 avant-lab10             # si ça tourne mal
qm delsnapshot 9003 avant-lab10          # quand c'est terminé
```

---

## 0.4 Le poste de travail

Tu travailles depuis Windows **et** depuis Ubuntu : les deux postes ont
leur propre clé, les deux clés sont dans `lab-keys.pub`, et la configuration
SSH est la même à un chemin près.

### Depuis Windows

Windows 10 (1809+) et Windows 11 embarquent un client OpenSSH natif : pas
besoin de PuTTY. Dans **Windows Terminal** (PowerShell) :

```powershell
# le client est-il là ?
Get-WindowsCapability -Online | ? Name -like 'OpenSSH.Client*'
# sinon : Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
# clé ed25519 dédiée au lab, protégée par phrase de passe
ssh-keygen -t ed25519 -C "mathieu@poste-windows" `
  -f $env:USERPROFILE\.ssh\id_ed25519_lab
# agent Windows : la phrase de passe n'est demandée qu'une fois
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
ssh-add $env:USERPROFILE\.ssh\id_ed25519_lab
# la clé publique, à coller dans /root/lab/lab-keys.pub du nœud
Get-Content $env:USERPROFILE\.ssh\id_ed25519_lab.pub | Set-Clipboard
```

Le fichier de configuration est `C:\Users\<toi>\.ssh\config` (même syntaxe
que sous Linux, chemins avec `~` acceptés) :

```
Host pve
    HostName 192.168.1.50
    User root

Host lab-adm
    HostName 192.168.1.50
    Port 2222
    User mathieu
    IdentityFile ~/.ssh/id_ed25519_lab
    IdentitiesOnly yes

Host lab-web
    HostName 10.10.10.11
Host lab-db
    HostName 10.10.10.12
Host lab-rhel
    HostName 10.10.10.13
Host lab-ops
    HostName 10.10.10.14
Host lab-git
    HostName 10.10.10.15

Host lab-web lab-db lab-rhel lab-ops lab-git
    User mathieu
    ProxyJump lab-adm
    IdentityFile ~/.ssh/id_ed25519_lab
    IdentitiesOnly yes
```

`lab-adm` est atteint par le port 2222 du nœud (la règle DNAT de §0.3) ;
les cinq autres passent par `lab-adm` avec `ProxyJump`, sans transfert
d'agent. Le module 12 explique pourquoi c'est la bonne façon de faire.

Ensuite : `ssh lab-adm`, puis `ssh lab-db`. Pour **VS Code**, installe
l'extension *Remote - SSH* : elle lit ce fichier, `Ctrl+Maj+P → Remote-SSH:
Connect to Host → lab-adm`, et tu édites les fichiers des VM avec un vrai
éditeur, terminal intégré compris. C'est l'outil de travail recommandé pour
les modules 17 à 22 (YAML, HCL, pipelines).

**WSL2 en option.** Si tu préfères un vrai bash sous Windows :
`wsl --install -d Ubuntu-24.04`, puis suis la section « Depuis Ubuntu »
dans WSL. Attention : WSL a son propre `~/.ssh` ; génère la clé là aussi
ou copie-la, et ajoute-la à `lab-keys.pub`. Ne fais pas les labs eux-mêmes
dans WSL — WSL n'est pas un serveur, il n'a pas de `systemd` complet ni de
réseau réaliste.

### Depuis Ubuntu

```bash
ssh-keygen -t ed25519 -C "mathieu@poste-ubuntu" -f ~/.ssh/id_ed25519_lab
ssh-add ~/.ssh/id_ed25519_lab          # l'agent GNOME est déjà lancé
cat ~/.ssh/id_ed25519_lab.pub          # à ajouter dans lab-keys.pub
```

Même `~/.ssh/config` que ci-dessus (`chmod 600 ~/.ssh/config`). Variante
possible sur Ubuntu uniquement : une route statique vers le lab, qui te
dispense du `ProxyJump` et du port 2222 :

```bash
sudo ip route add 10.10.10.0/24 via 192.168.1.50   # non persistant
```

Ça fonctionne parce que `lab-nat.sh` ne masque pas le trafic à destination
de ton LAN (`! -d 192.168.1.0/24`). Garde quand même la configuration
`ProxyJump` : c'est celle des modules.

### `/etc/hosts` local

Sur le poste Ubuntu (`/etc/hosts`) et Windows
(`C:\Windows\System32\drivers\etc\hosts`, éditeur lancé en administrateur),
ajoute le nœud et, si tu utilises la route statique, les VM :

```
192.168.1.50  pve pve.lab.local
10.10.10.10   lab-adm
10.10.10.11   lab-web
10.10.10.12   lab-db
10.10.10.13   lab-rhel
10.10.10.14   lab-ops
10.10.10.15   lab-git lab-git.lab.local
```

Sans route statique, les entrées `10.10.10.x` ne servent qu'aux modules web
(ouvrir `http://lab-web` dans ton navigateur via un tunnel `ssh -L`, module
12). Ce n'est pas gênant de les mettre dès maintenant. L'entrée `lab-git`
sert dès le §0.8 : c'est le nom que ton navigateur et tes `git clone`
utiliseront.

### Copier les scripts du workbook sur les VM

Le workbook est livré avec `workbook.zip` (les dossiers `scripts/` et
`src/`). Il doit finir dans `~/workbook/` sur **chaque** VM. Le script
`bootstrap-lab.sh` s'en charge s'il trouve `~/workbook.zip` ; il suffit donc
d'envoyer le zip et le script lui-même :

```bash
# depuis ton poste, dans le dossier du workbook
for h in lab-adm lab-web lab-db lab-rhel lab-ops lab-git; do
  scp workbook.zip scripts/lab/bootstrap-lab.sh "$h:~/"
done
```

Sous Windows, `scp` est fourni avec OpenSSH ; en PowerShell la boucle
s'écrit `foreach ($h in 'lab-adm','lab-web','lab-db','lab-rhel','lab-ops',
'lab-git') { scp workbook.zip scripts/lab/bootstrap-lab.sh "${h}:~/" }`.
La première connexion à chaque VM te demande d'accepter sa clé d'hôte :
compare-la avec `qm terminal <vmid>` si tu veux être rigoureux (module
12), réponds `yes` sinon.

Plus tard, quand tu modifieras tes propres scripts, `rsync` vers `lab-adm`
suffira : `rsync -av scripts/ lab-adm:~/workbook/scripts/`.

---

## 0.5 Premier démarrage

### Vérification de bout en bout

Depuis ton poste :

```bash
ssh lab-adm 'hostname; id; ip -br -4 addr show; cat /etc/os-release | head -2'
# lab-adm
# uid=1000(mathieu) gid=1000(mathieu) groups=1000(mathieu),27(sudo)...
# eth0  UP  10.10.10.10/24
# PRETTY_NAME="Ubuntu 24.04.x LTS"
ssh lab-adm 'ping -c1 -W2 9.9.9.9 && curl -sI https://deb.debian.org | head -1'
# 1 packets transmitted, 1 received      <- le NAT marche
# HTTP/2 200                             <- le DNS aussi
ssh lab-rhel 'cat /etc/rocky-release; getenforce'
# Rocky Linux release 9.x (Blue Onyx)
# Enforcing
ssh lab-db 'lsblk -d -o NAME,SIZE'
# sda   30G
# sdb    5G
# sdc    5G
```

Si `ssh lab-adm` échoue : `qm terminal 9001` sur le nœud (`Ctrl+O` pour
sortir) te donne la console série. Là, `cloud-init status --long` et
`journalctl -u cloud-init` disent ce qui a coincé — le plus souvent une clé
publique mal collée dans `lab-keys.pub` ou une VM qui n'a pas fini de booter.

### `bootstrap-lab.sh` sur chaque VM

Le script installe l'outillage commun (`vim curl git tmux htop jq tree
net-tools dnsutils rsync unzip shellcheck`, plus `qemu-guest-agent` et
`chrony`), écrit les six entrées du lab dans `/etc/hosts` (et empêche
cloud-init de les écraser au reboot), règle le fuseau sur `Europe/Paris`,
active un historique bash horodaté, pose un motd qui rappelle le rôle de la
machine, et déballe `~/workbook.zip` dans `~/workbook/`. Sous Rocky il
active EPEL pour `htop` et `ShellCheck`, et remplace `dnsutils` par
`bind-utils`.

```bash
for h in lab-adm lab-web lab-db lab-rhel lab-ops lab-git; do
  echo "== $h"; ssh -t "$h" 'sudo bash ~/bootstrap-lab.sh'
done
```

`-t` force un terminal, nécessaire pour que `sudo` et les couleurs se
comportent normalement. Le script est idempotent : si une VM a raté (dépôt
injoignable, par exemple), relance-le sur elle seule.

Vérifie ensuite ce qui compte :

```bash
ssh lab-web 'date; getent hosts lab-db; shellcheck --version | head -2'
# jeu. 18 sept. 2026 21:04:12 CEST
# 10.10.10.12     lab-db.lab.local lab-db
# ShellCheck - shell script analysis tool
# version: 0.9.0
ssh lab-adm 'ls ~/workbook/scripts'
# break  check  lab  lib  projects  setup
```

Puis, sur le nœud, le snapshot de référence et l'état final :

```bash
bash /root/lab/lab-create.sh snapshot
bash /root/lab/lab-status.sh
# VM        VMID  IP           STATUT   AGENT  PING  SSH  SNAPSHOT
# lab-adm   9001  10.10.10.10  running  yes    yes   yes  yes
# ...
# Lab opérationnel.
```

### Test des scripts `check`

Le module 01 a un script de setup et des scripts de vérification ; c'est le
bon moment pour voir à quoi ils ressemblent, **sans** faire l'exercice :

```bash
ssh lab-adm
bash ~/workbook/scripts/setup/setup_M01.sh
bash ~/workbook/scripts/check/check_M01_01.sh ; echo "code retour : $?"
# == Vérification L1.1 ==
#   [FAIL] ... (indice)
# Résultat : 0 réussis, N échoués
# code retour : 1
```

Un `check` qui échoue avant d'avoir travaillé, c'est normal. S'il plante
avec une erreur bash au lieu d'un `[FAIL]`, c'est que le bootstrap a raté
quelque chose (souvent `jq` ou `shellcheck` absent) : relance-le.

::: check
Le lab est prêt quand : `lab-status.sh` ne signale aucun problème, chaque
VM résout `lab-ops` par `/etc/hosts`, sort sur internet, a l'heure de
Paris, et porte un snapshot `snap-clean`. Note la date dans ton carnet :
c'est le jour 0. Reste le serveur Git (§0.8) : installe-le **avant** de
poser `snap-clean` sur `lab-git`, pour que le rollback ne le supprime pas.
:::

---

## 0.6 Sans Proxmox

Tout le workbook est écrit pour l'infra du §0.3. Si tu n'as pas de nœud
Proxmox, trois solutions, de la plus fidèle à la moins fidèle. Dans tous les
cas, garde les **mêmes noms d'hôtes, les mêmes IP et le même utilisateur**,
sinon les scripts `setup`/`check` et les énoncés ne colleront plus.

### Multipass (Ubuntu, Windows, macOS)

Multipass crée des VM Ubuntu cloud-init en une commande. Il ne sait pas
faire de Rocky : `lab-rhel` passe alors sous Vagrant (ci-dessous) ou tu
sautes les blocs `::: rhel`, ce qui se paie à l'annexe B (RHCSA).

```bash
# un fichier cloud-init minimal par VM, avec ton utilisateur et ta clé
cat > ci-lab.yaml <<'EOF'
users:
  - name: mathieu
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... mathieu@poste
EOF
multipass launch 24.04 -n lab-adm -c 2 -m 2G -d 20G --cloud-init ci-lab.yaml
multipass launch 24.04 -n lab-web -c 2 -m 2G -d 20G --cloud-init ci-lab.yaml
multipass launch 24.04 -n lab-db  -c 2 -m 2G -d 30G --cloud-init ci-lab.yaml
multipass launch 24.04 -n lab-ops -c 2 -m 4G -d 40G --cloud-init ci-lab.yaml
multipass launch 24.04 -n lab-git -c 1 -m 1G -d 15G --cloud-init ci-lab.yaml
multipass list                       # IP attribuées en DHCP
```

Limites : les IP ne sont pas fixes (mets-les dans `/etc/hosts` de chaque VM
après `multipass list`, et refais-le si elles changent), pas de disques
additionnels pour `lab-db` (le module 10 travaille alors sur des fichiers
images montés en *loop*, le corrigé le prévoit), et pas de snapshot pratique
(`multipass snapshot` existe depuis la 1.13 mais reste lent ; `multipass
delete --purge` + relance est souvent plus rapide).

### Vagrant + VirtualBox (Windows, Ubuntu)

La solution la plus proche de Proxmox : IP fixes, disques additionnels,
Rocky disponible, snapshots (`vagrant snapshot save lab-db snap-clean`).

```ruby
# Vagrantfile
Vagrant.configure("2") do |config|
  config.ssh.insert_key = false
  vms = {
    "lab-adm"  => ["bento/ubuntu-24.04", "10.10.10.10", 2048],
    "lab-web"  => ["bento/ubuntu-24.04", "10.10.10.11", 2048],
    "lab-db"   => ["bento/ubuntu-24.04", "10.10.10.12", 2048],
    "lab-rhel" => ["bento/rockylinux-9", "10.10.10.13", 2048],
    "lab-ops"  => ["bento/ubuntu-24.04", "10.10.10.14", 4096],
    "lab-git"  => ["bento/ubuntu-24.04", "10.10.10.15", 1024],
  }
  vms.each do |name, (box, ip, ram)|
    config.vm.define name do |vm|
      vm.vm.box = box
      vm.vm.hostname = name
      vm.vm.network "private_network", ip: ip
      vm.vm.provider "virtualbox" do |vb|
        vb.memory = ram
        vb.cpus = 2
        if name == "lab-db"
          (1..2).each do |i|
            vb.customize ["createhd", "--filename", "#{name}-disk#{i}.vdi",
                          "--size", 5 * 1024]
            vb.customize ["storageattach", :id,
                          "--storagectl", "SATA Controller",
                          "--port", i + 1, "--device", 0, "--type", "hdd",
                          "--medium", "#{name}-disk#{i}.vdi"]
          end
        end
      end
      vm.vm.provision "shell", inline: <<-SH
        useradd -m -s /bin/bash -G sudo,wheel mathieu 2>/dev/null || true
        echo 'mathieu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/mathieu
        install -d -m 700 -o mathieu -g mathieu /home/mathieu/.ssh
        cp /vagrant/lab-keys.pub /home/mathieu/.ssh/authorized_keys
        chown mathieu:mathieu /home/mathieu/.ssh/authorized_keys
        chmod 600 /home/mathieu/.ssh/authorized_keys
      SH
    end
  end
end
```

Le nom du contrôleur SATA dépend de la box (`SATA Controller` pour les box
`bento`) ; vérifie avec `VBoxManage showvminfo`. Sur `lab-rhel`, le groupe
`sudo` n'existe pas : le `useradd -G sudo,wheel` échoue, d'où le `|| true`
suivi du fichier `sudoers.d`. Ensuite `bootstrap-lab.sh` s'applique tel
quel. Le réseau `private_network` est de type *host-only* : tu accèdes
directement aux IP depuis ton poste, sans bastion ; garde le `ProxyJump` de
§0.4 quand même, c'est lui que les modules supposent.

### Docker : pour certains modules seulement

Un conteneur n'est pas une machine : pas de noyau propre, pas de `systemd`
par défaut, pas de disques, pas de pare-feu à soi. Ça suffit pour les
modules **01 à 07** (shell, fichiers, permissions, utilisateurs, texte,
vim, bash) et **09** (paquets), avec une image `ubuntu:24.04` ou
`rockylinux:9` lancée en `--privileged` si tu veux `chattr` et `setcap` :

```bash
docker run -it --name lab-adm -h lab-adm --privileged ubuntu:24.04 bash
```

Ce qui ne marche **pas**, ou mal, en conteneur :

| Module | Ce qui coince |
|---|---|
| 08 (partiel) | pas de `systemd` PID 1, pas de cgroups délégués, OOM killer partagé |
| 10 | pas de périphériques bloc, pas de LVM, `mdadm`, LUKS ni `fstab` |
| 11 (partiel) | pas de Netplan / NetworkManager, `sysctl` réseau et `tcpdump` limités |
| 15 (partiel) | pas de `nftables`/`firewalld` réel, pas de SELinux/AppArmor propre |
| 12, 13, 14 | `sshd`, `journald`, `rsyslog`, `cron` demandent une init : faisable avec une image systemd, pénible |
| 16, 18 à 22 | dépannage système, Docker-in-Docker, k3s : non |

Si Docker est ta seule option, fais les modules 01 à 07 et 09 dedans, puis
loue deux petites VM chez un hébergeur le temps des modules 08, 10 à 16 :
le coût est de l'ordre d'une dizaine d'euros par mois, et c'est un vrai
serveur avec une vraie IP publique, ce qui rend le module 15 plus sérieux.

---

## 0.7 Bonnes habitudes dès maintenant

### Le carnet de bord

Un fichier Markdown par module dans `~/carnet/` sur `lab-adm` (le
bootstrap crée le dossier), versionné (voir ci-dessous). Le modèle complet
est en annexe D ; l'essentiel tient en six lignes par séance :

```markdown
## 2026-09-21 — Module 10 — séance 1 (2 h)
- Fait : E10.1 à E10.9, L10.1.
- Bloqué : L10.2 étape 3, `lvextend` refuse (« insufficient free space »).
  20 min : man lvextend, `vgs` → le VG était plein. Corrigé : ajouté sdc
  au VG. Corrigé lu après coup : même conclusion, mais `pvmove` en plus.
- À revoir : différence `-L +5G` / `-l +100%FREE`.
- Snapshot : avant-lab10 posé sur 9003, supprimé en fin de séance.
```

Ce carnet a trois usages : retrouver ce que tu as fait (les incidents de la
semaine d'astreinte, P3, s'y réfèrent), préparer les entretiens (annexe C),
et mesurer honnêtement ta progression (annexe A). Écris-le au fil de l'eau,
pas à la fin.

### Snapshot avant tout lab destructeur

Chaque `X.1 Mise en place` dit quel snapshot poser. Fais-le **avant** de
lire l'énoncé du Break & Fix, pas quand ça commence à sentir mauvais :

```bash
qm snapshot 9003 avant-lab10        # sur le nœud, 5 secondes
```

Une VM cassée au-delà du réparable n'est pas un échec, c'est `qm rollback`.
Un lab abandonné parce que la VM est cassée et que tu as peur de tout
refaire, ça, c'en est un.

### Jamais root

Tu te connectes toujours en `mathieu` et tu élèves ponctuellement avec
`sudo`. Pas de `sudo -i` pour « aller plus vite », pas de `PermitRootLogin
yes`. Trois raisons : c'est comme ça en production ; `sudo` laisse une trace
dans `/var/log/auth.log` ou le journal (module 13) ; et un `rm -rf` mal tapé
sous ton compte détruit ton `$HOME`, pas la machine. Quand un module te fait
travailler longtemps en root (module 16, réparation en mode `emergency`),
il le dit explicitement.

### Versionner ses scripts dès le module 01

N'attends pas le module 17 pour Git. Dès le premier script du module 01,
sur `lab-adm` :

```bash
git config --global user.name "Mathieu"
git config --global user.email "mathieu@exemple.invalid"
git config --global init.defaultBranch main
mkdir -p ~/devops-workbook && cd ~/devops-workbook
git init && mkdir scripts carnet
git add -A && git commit -m "init"
# à chaque fin de séance :
git add -A && git commit -m "M01: E1.1-E1.8, L1.1 ; carnet"
```

Trois commandes (`git add -A`, `git commit -m`, `git log --oneline`)
suffisent jusqu'au module 17, qui reprendra tout proprement (branches,
revues, hooks). Le dépôt distant, lui, existe dès maintenant : §0.8 monte
un serveur Gitea dans ton LAN et §0.9 y pousse le workbook entier, tes
réponses comprises. Ce dépôt devient le portfolio de l'annexe C : les
scripts des défis, les post-mortem de P3, les rôles Ansible de P2. Ne mets
jamais un secret dedans, même « pour tester » — le module 15 explique
pourquoi un secret commité est un secret grillé.

### Chercher comme un pro

L'ordre de recherche d'un administrateur expérimenté, celui que la règle
des 20 minutes te demande de suivre :

1. **La machine elle-même** : `man 5 sshd_config` (la section compte),
   `commande --help`, `apropos mot`, `/usr/share/doc/<paquet>/`,
   `journalctl -xeu service`, le message d'erreur exact copié dans un
   moteur de recherche **entre guillemets**.
2. **La documentation officielle** du projet (Ubuntu Server Guide, Red Hat
   Documentation, docs Ansible, Kubernetes, Docker) avant les blogs.
3. **Le code ou la conf par défaut** : `/usr/lib/systemd/system/*.service`,
   `/etc/default/`, les exemples dans `/usr/share/doc/*/examples/`.
4. **Les blogs et forums** : Server Fault, les wikis Arch et Gentoo (souvent
   les meilleurs, même sur une autre distribution), Julia Evans.
5. **Une IA**, en dernier, et jamais pour une commande destructrice que tu
   ne comprends pas encore. Demande-lui d'expliquer, pas d'exécuter.

Et à chaque fois : note dans le carnet **où** tu as trouvé la réponse. Au
bout de dix modules, tu sauras d'instinct où chercher, et c'est précisément
ce qu'on évalue en entretien quand on te pose une question dont tu ignores
la réponse.

---

## 0.8 Un serveur Git dans ton LAN

### Pourquoi une forge dès le jour 0

Le §0.7 te fait versionner tes scripts en local sur `lab-adm`. Un dépôt
local, c'est un dépôt qui disparaît avec la VM au premier `qm rollback`
maladroit ou au premier disque qui lâche. Il te faut un **distant** dès le
départ, et pas GitHub : tu vas commiter ton carnet, tes réponses, des
fichiers de conf avec les IP du lab, parfois des erreurs. Tout ça doit
rester chez toi, dans ton LAN, sur une machine que tu administres.

Ce serveur, c'est `lab-git`, la sixième VM de la topologie du §0.3. Elle
héberge **Gitea**, une forge légère (dépôts, *pull requests*, *issues*,
wiki, *releases*, *Actions*) qui tient dans un binaire Go et une base
SQLite. Trois usages :

1. **Sauvegarde continue de ton travail** : tout ce que tu écris pendant
   les 23 modules est poussé à chaque séance ; les VM de lab sont
   jetables, `lab-git` ne l'est pas.
2. **Portfolio** : le dépôt `workbook/linux-devops-workbook` devient, au
   fil des modules, la preuve de ce que tu sais faire (annexe C). Tu le
   mets en miroir sur GitHub quand tu es prêt à le montrer (§0.9).
3. **Base des modules 17 et 21** : le module 17 (Git) peut pousser ses
   dépôts sur cette forge au lieu d'en monter une sur `lab-ops` (son lab
   L17.5 reste valable, c'est le même produit), et le module 21 (CI/CD)
   réutilise ta clé, ton compte et tes réflexes Gitea. Le module 21 garde
   **volontairement** sa propre installation en Docker Compose sur
   `lab-ops` : on y apprend à empiler forge, base PostgreSQL, registre et
   *runner* dans un `compose.yaml`, ce qui n'a rien à voir avec un service
   systemd. Deux Gitea dans le lab, deux façons d'installer le même
   logiciel : c'est une comparaison utile, pas une redondance.

Pourquoi **en binaire et pas en Docker** ? Parce que Docker n'arrive qu'au
module 18 et qu'on ne fait pas tourner en production ce qu'on ne sait pas
dépanner. Un binaire, un utilisateur système, une unité systemd, un
fichier `app.ini` : tout ce dont Gitea a besoin est vu dans les modules 03,
04, 08 et 09. Tu sauras exactement où sont les données, qui écrit quoi et
comment le sauvegarder.

### La VM `lab-git`

Si tu as suivi le §0.3 avec les scripts de cette édition, `lab-create.sh`
l'a déjà clonée et `bootstrap-lab.sh` l'a préparée. Si ton lab date d'une
édition à cinq VM, ajoute-la à la main depuis le nœud, avec les mêmes
commandes que les autres :

```bash
qm clone 9000 9006 --name lab-git --full 1 --storage local-lvm
qm set 9006 --cores 1 --memory 1024 --onboot 1 \
  --description "Workbook Linux/DevOps - lab-git - 10.10.10.15"
qm set 9006 --ipconfig0 ip=10.10.10.15/24,gw=10.10.10.1 \
  --nameserver 10.10.10.1 --searchdomain lab.local \
  --ciuser mathieu --sshkeys /root/lab/lab-keys.pub
qm start 9006
echo '10.10.10.15 lab-git' >> /root/lab/lab.hosts && systemctl restart dnsmasq
```

Puis, sur **chaque** VM existante, relance `sudo bash ~/bootstrap-lab.sh`
(la nouvelle version écrit six entrées dans `/etc/hosts`) ou ajoute la
ligne `10.10.10.15  lab-git.lab.local  lab-git` toi-même. Ajoute aussi le
bloc `Host lab-git` dans le `~/.ssh/config` de tes postes (§0.4) et
l'entrée dans leur fichier `hosts`. Enfin, envoie le zip et bootstrape :

```bash
scp workbook.zip scripts/lab/bootstrap-lab.sh lab-git:~/
ssh -t lab-git 'sudo bash ~/bootstrap-lab.sh'
ssh lab-git 'hostname; free -m | head -2; df -h / | tail -1'
# lab-git
#                total        used        free ...
# Mem:             960         180         520 ...
# /dev/sda1        19G  2.1G   17G  11% /
```

1 vCPU et 1 Go suffisent largement : Gitea consomme 80 à 150 Mo au repos
avec SQLite, et ton dépôt fera quelques dizaines de Mo.

### Installer Gitea : ce que fait `install-gitea.sh`

Le script `~/workbook/scripts/lab/install-gitea.sh` suit à la lettre la
procédure officielle (*Installation from binary*, docs.gitea.com). Lis-le
avant de le lancer : c'est un condensé des modules 04, 08 et 09. Ses
variables sont en tête de fichier :

```bash
GITEA_VERSION="${GITEA_VERSION:-1.27.3}"     # cf. https://dl.gitea.com/gitea/
GITEA_DOMAIN="${GITEA_DOMAIN:-lab-git.lab.local}"
GITEA_HTTP_PORT="${GITEA_HTTP_PORT:-3000}"
GITEA_SSH_PORT="${GITEA_SSH_PORT:-22}"       # le sshd du système, pas Gitea
```

Vérifie la dernière version stable sur `https://dl.gitea.com/gitea/` (les
répertoires `1.x.y` sans `-rc` ni `-dev`) et surcharge-la si besoin.
Étape par étape, voilà ce qu'il exécute.

**1. Paquets.** `git` (Gitea l'appelle pour tout), `git-lfs`, `gnupg` (pour
la signature), `curl`, `xz-utils`.

**2. L'utilisateur système `git`.** C'est lui qui fera tourner Gitea et
que tes clients SSH contacteront (`git@lab-git`). Un compte système : pas
de mot de passe, UID sous 1000, mais **un vrai shell**, parce que le `sshd`
du système va exécuter une commande sous ce compte à chaque `git push` :

```bash
sudo adduser --system --shell /bin/bash --gecos 'Git Version Control' \
  --group --disabled-password --home /home/git git
```

**3. Le binaire, vérifié deux fois.** Un binaire téléchargé sur internet
qu'on va lancer en service, on vérifie son empreinte **et** sa signature.
Gitea publie pour chaque version un fichier `.sha256` et une signature
`.asc` faite par la clé *Teabot* (empreinte
`7C9E 6815 2594 6888 62D6 2AF6 2D9A E806 EC15 92E2`) :

```bash
V=1.27.3; F=gitea-$V-linux-amd64
curl -fsSLO https://dl.gitea.com/gitea/$V/$F
curl -fsSLO https://dl.gitea.com/gitea/$V/$F.sha256
curl -fsSLO https://dl.gitea.com/gitea/$V/$F.asc
sha256sum -c $F.sha256
# gitea-1.27.3-linux-amd64: OK
gpg --keyserver hkps://keys.openpgp.org \
  --recv 7C9E68152594688862D62AF62D9AE806EC1592E2
gpg --verify $F.asc $F
# gpg: Good signature from "Teabot <teabot@gitea.io>"
sudo install -m 755 -o root -g root $F /usr/local/bin/gitea
gitea --version
# Gitea version 1.27.3 built with GNU Make 4.4.1, go1.24.x : ...
```

Le sha256 protège contre un téléchargement tronqué ou un miroir corrompu ;
la signature protège contre un binaire remplacé sur le serveur lui-même.
Si `keys.openpgp.org` est injoignable, le script continue avec le sha256
seul et te le dit. Le binaire va dans `/usr/local/bin` : c'est l'endroit
des logiciels installés hors gestionnaire de paquets (module 02, FHS).

**4. L'arborescence.** Deux racines, avec des droits précis :

```bash
sudo mkdir -p /var/lib/gitea/{custom,data,log}
sudo chown -R git:git /var/lib/gitea/ && sudo chmod -R 750 /var/lib/gitea/
sudo mkdir -p /etc/gitea
sudo chown root:git /etc/gitea && sudo chmod 770 /etc/gitea
```

`/var/lib/gitea` est le *work dir* : la base SQLite (`data/gitea.db`),
les dépôts (`data/gitea-repositories/`), les objets LFS, les journaux, les
personnalisations. `/etc/gitea` contient `app.ini`. Il est en `770` le
temps de l'installation parce que **l'installateur web l'écrit** ; on le
referme après (`750`, `app.ini` en `640`).

**5. Un `app.ini` minimal.** Le script en génère un si le fichier n'existe
pas (jamais écrasé sinon), avec les secrets créés par `gitea generate
secret` et les quatre choix qui comptent :

```ini
[server]
DOMAIN           = lab-git.lab.local
HTTP_PORT        = 3000
ROOT_URL         = http://lab-git.lab.local:3000/
SSH_DOMAIN       = lab-git.lab.local
SSH_PORT         = 22
START_SSH_SERVER = false        ; on utilise le sshd du système
LFS_START_SERVER = true         ; Git LFS : gros fichiers, PDF, images

[database]
DB_TYPE = sqlite3
PATH    = /var/lib/gitea/data/gitea.db

[service]
DISABLE_REGISTRATION = false    ; passera à true après le premier compte

[security]
INSTALL_LOCK = false            ; l'installateur web est autorisé

[actions]
ENABLED = true                  ; les workflows du §0.9 (runner : module 21)
```

`ROOT_URL` est l'adresse que Gitea écrit partout : liens dans l'interface,
URL de clone HTTP, webhooks. Elle doit être **celle que tes navigateurs
utilisent**, d'où un nom (`lab-git.lab.local`) et pas une IP : le jour où
tu ajoutes un reverse proxy, une seule ligne change. `SSH_DOMAIN` sert
aux URL de clone SSH. SQLite est le bon choix ici : une base dans un
fichier, sauvegardée par un simple `gitea dump`, et un utilisateur seul ne
la mettra jamais à genoux. Le module 21 utilisera PostgreSQL, pour
apprendre l'autre configuration.

**6. L'unité systemd**, reprise de `contrib/systemd/gitea.service` du
dépôt officiel, débarrassée des lignes MySQL/PostgreSQL :

```ini
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target

[Service]
RestartSec=2s
Type=simple
User=git
Group=git
WorkingDirectory=/var/lib/gitea/
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=always
Environment=USER=git HOME=/home/git GITEA_WORK_DIR=/var/lib/gitea
#CapabilityBoundingSet=CAP_NET_BIND_SERVICE
#AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
```

Les deux lignes commentées permettraient d'écouter sur le port 80 sans
être root (module 15) ; avec le port 3000, inutile.

**7. Démarrage** : `systemctl daemon-reload`, `enable --now gitea`, puis
un `curl` sur `/api/healthz` jusqu'à obtenir une réponse.

Lance-le :

```bash
ssh lab-git
sudo bash ~/workbook/scripts/lab/install-gitea.sh
# ==> paquets
# ==> création de l'utilisateur système git
# ==> téléchargement de gitea 1.27.3 (linux-amd64)
# ==> vérification sha256
# gitea-1.27.3-linux-amd64: OK
# ==> vérification de la signature GPG (Teabot)
#   signature OK
# Gitea version 1.27.3 built with ...
# ==> arborescence /var/lib/gitea et /etc/gitea
# ==> écriture de /etc/gitea/app.ini (SQLite, LFS, lab-git.lab.local)
# ==> /etc/systemd/system/gitea.service
#
# == Gitea 1.27.3 sur lab-git ==
#    service   : active
#    URL       : http://lab-git.lab.local:3000/
#    données   : /var/lib/gitea   config : /etc/gitea/app.ini
#
# Étape suivante : ouvre l'URL ci-dessus, termine l'installation
# (compte administrateur mathieu), puis :
#   sudo bash install-gitea.sh lock
systemctl status gitea --no-pager | head -5
ss -tlnp | grep 3000
# LISTEN 0 4096 *:3000 *:* users:(("gitea",pid=1874,fd=8))
```

### Premier démarrage : l'installateur web

Il te faut joindre `http://lab-git.lab.local:3000/` depuis ton navigateur.
Trois possibilités, par ordre de simplicité :

* **Tunnel SSH** (marche partout, tout de suite) :
  `ssh -L 3000:10.10.10.15:3000 lab-adm`, puis `http://localhost:3000/`.
  Pour ce premier passage, c'est suffisant.
* **Route statique** sur le poste Ubuntu (§0.4) : `http://lab-git:3000/`
  directement, grâce à l'entrée `hosts`.
* **DNAT du nœud** : la règle `3000 → 10.10.10.15:3000` de `lab-nat.sh`
  (§0.3) publie Gitea sur `http://192.168.1.50:3000/` pour tout ton LAN.
  Voir « Accès depuis le LAN » plus bas pour le nom.

L'écran d'installation reprend les valeurs de `app.ini`. Vérifie sans
rien changer : *Type de base de données* SQLite3, *Chemin* 
`/var/lib/gitea/data/gitea.db`, *Titre du site* « Forge du lab », *Chemin
racine des dépôts* `/var/lib/gitea/data/gitea-repositories`, *Chemin
racine LFS* `/var/lib/gitea/data/lfs`, *Utilisateur d'exécution* `git`,
*Domaine* `lab-git.lab.local`, *Port SSH* 22, *Port d'écoute HTTP* 3000,
*URL de base* `http://lab-git.lab.local:3000/`, *Chemin des journaux*
`/var/lib/gitea/log`. Déplie **Paramètres du compte administrateur** et
crée `mathieu` avec un vrai mot de passe et ton adresse mail (Gitea ne
l'enverra nulle part : pas de serveur SMTP configuré). Valide.

Gitea réécrit `app.ini`, met `INSTALL_LOCK = true`, redémarre en interne
et t'ouvre une session. Referme aussitôt ce qui doit l'être :

```bash
sudo bash ~/workbook/scripts/lab/install-gitea.sh lock
# ==> verrouillage post-installation
#    inscription fermée, /etc/gitea en 750, app.ini en 640
grep -E 'INSTALL_LOCK|DISABLE_REGISTRATION' /etc/gitea/app.ini
# INSTALL_LOCK = true
# DISABLE_REGISTRATION   = true
```

`DISABLE_REGISTRATION = true` : plus personne ne peut se créer un compte
par l'interface. Sur un LAN domestique ce n'est pas paranoïaque, c'est le
réflexe : une forge ouverte à l'inscription est un serveur de dépôts
gratuit pour le premier venu (ou le premier objet connecté compromis).

::: attention
Si l'écran d'installation n'apparaît pas et que tu tombes directement sur
la page d'accueil, c'est qu'un `app.ini` avec `INSTALL_LOCK = true` existe
déjà (installation précédente, snapshot restauré). Le compte admin se crée
alors en ligne de commande :
`sudo -u git gitea admin user create --admin --username mathieu
--password '...' --email mathieu@lab.local --config /etc/gitea/app.ini`.
:::

### Ta clé SSH, l'organisation et le dépôt

Dans l'interface : avatar en haut à droite → *Paramètres* → *Clés SSH /
GPG* → *Ajouter une clé*. Colle la clé publique de ton poste
(`~/.ssh/id_ed25519_lab.pub`, §0.4) puis celle de `lab-adm` (crée-la si
besoin : `ssh lab-adm 'ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
-C mathieu@lab-adm && cat ~/.ssh/id_ed25519.pub'`). Gitea écrit chaque
clé dans `/home/git/.ssh/authorized_keys` avec une option `command=` qui
force l'exécution de `gitea serv` : la clé ne donne **pas** de shell sur
`lab-git`, seulement le droit de parler Git. Vérifie :

```bash
sudo cat /home/git/.ssh/authorized_keys
# # gitea public key
# command="/usr/local/bin/gitea --config=/etc/gitea/app.ini serv key-1",
# no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty,
# no-user-rc,restrict ssh-ed25519 AAAA... mathieu@poste-ubuntu
```

Puis crée l'**organisation** `workbook` (menu `+` → *Nouvelle
organisation*, visibilité *Publique*) et, dedans, le dépôt
`linux-devops-workbook` : *Nouveau dépôt*, propriétaire `workbook`,
**sans** initialiser (ni README, ni `.gitignore`, ni licence : le §0.9
pousse un dépôt complet). Une organisation plutôt qu'un dépôt sous ton
compte : tu y rangeras aussi `factura-infra` (module 17), tes rôles
Ansible (P2) et tout ce qui a vocation à finir dans le portfolio, avec des
équipes et des droits par dépôt le jour où tu travailles à plusieurs.

### Test de clone, depuis le lab et depuis le poste

Depuis `lab-adm`, en SSH (le port 22 système, utilisateur `git`) :

```bash
ssh -T git@lab-git
# Hi there, mathieu! You've successfully authenticated with the key named
# mathieu@lab-adm, but Gitea does not provide shell access.
git clone git@lab-git:workbook/linux-devops-workbook.git /tmp/t
# Cloning into '/tmp/t'...
# warning: You appear to have cloned an empty repository.
rm -rf /tmp/t
```

Depuis ton poste Windows ou Ubuntu, c'est **la même commande** : `git`
appelle `ssh`, qui lit `~/.ssh/config`, trouve le bloc `Host lab-git`
(`HostName 10.10.10.15`, `ProxyJump lab-adm`, `IdentityFile
~/.ssh/id_ed25519_lab`) et l'utilisateur `git` de l'URL prime sur le
`User mathieu` du fichier. Ton clone traverse donc le bastion sans que tu
aies rien à configurer de plus :

```bash
ssh -T git@lab-git          # même message « Hi there, mathieu! »
git clone git@lab-git:workbook/linux-devops-workbook.git
```

L'URL affichée par Gitea est `git@lab-git.lab.local:workbook/...` ; le
nom court `lab-git` marche aussi, parce que c'est lui qui est dans ton
`~/.ssh/config`. Sous Windows, VS Code et Git for Windows utilisent le
même `C:\Users\<toi>\.ssh\config` (si Git for Windows utilise son propre
ssh, force `git config --global core.sshCommand "C:/Windows/System32/
OpenSSH/ssh.exe"` pour qu'il prenne celui de Windows, agent compris).

::: check
`ssh -T git@lab-git` répond « Hi there, mathieu! » depuis `lab-adm` **et**
depuis ton poste ; `sudo -u git gitea doctor check --all --config
/etc/gitea/app.ini` sur `lab-git` ne signale aucune erreur ; `systemctl
is-enabled gitea` répond `enabled`.
:::

### Sauvegarder et restaurer

Une forge qu'on ne sauvegarde pas est un point de défaillance unique
déguisé en sauvegarde. Gitea fournit `gitea dump`, qui produit un zip
autoportant : `gitea-db.sql` (la base), `gitea-repo.zip` (tous les
dépôts), `data/` (LFS, avatars, pièces jointes), `log/`, `custom/` et
`app.ini`. Le script `backup-gitea.sh` l'appelle sous l'utilisateur
`git`, dans `/var/backups/gitea/`, et garde les 7 derniers :

```bash
sudo install -m 755 ~/workbook/scripts/lab/backup-gitea.sh /usr/local/sbin/
sudo install -m 644 ~/workbook/scripts/lab/gitea-backup.{service,timer} \
  /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now gitea-backup.timer
sudo systemctl start gitea-backup.service        # premier dump, tout de suite
# dump : /var/backups/gitea/gitea-dump-20260921-101502.zip (3.1M)
# OK  1 dump(s) dans /var/backups/gitea
systemctl list-timers gitea-backup.timer --no-pager
# NEXT                         LEFT      LAST  PASSED  UNIT
# Tue 2026-09-22 03:31:12 CEST 17h left  -     -       gitea-backup.timer
```

Le timer (`OnCalendar=*-*-* 03:30:00`, `Persistent=true`) rattrape une
exécution manquée si la VM était éteinte à 3 h 30 ; le module 14 détaille
cette syntaxe. Mais un dump **sur la même VM** ne protège que d'une
fausse manipulation, pas d'un disque perdu. Rapatrie-le ailleurs — sur ton
poste, une fois par semaine :

```bash
# depuis ton poste (la lecture demande sudo : le dossier est en 750 git)
ssh lab-git 'sudo cat $(ls -t /var/backups/gitea/*.zip | head -1)' \
  > ~/sauvegardes/gitea-$(date +%F).zip
```

Restauration, sur une VM `lab-git` neuve après `install-gitea.sh` (sans
passer par l'installateur web) :

```bash
sudo systemctl stop gitea
sudo apt install -y sqlite3
cd /tmp && sudo -u git mkdir restore && cd restore
sudo -u git unzip -q /var/backups/gitea/gitea-dump-20260921-101502.zip
sudo cp app.ini /etc/gitea/app.ini && sudo chown root:git /etc/gitea/app.ini
sudo -u git unzip -q gitea-repo.zip -d /var/lib/gitea/data/
sudo -u git cp -a data/. /var/lib/gitea/data/
sudo -u git sqlite3 /var/lib/gitea/data/gitea.db < gitea-db.sql
sudo -u git gitea admin regenerate hooks --config /etc/gitea/app.ini
sudo -u git gitea admin regenerate keys  --config /etc/gitea/app.ini
sudo systemctl start gitea
sudo -u git gitea doctor check --all --config /etc/gitea/app.ini
```

`regenerate hooks` réécrit les hooks `post-receive` de chaque dépôt (ils
contiennent le chemin du binaire), `regenerate keys` reconstruit
`authorized_keys`. Fais cette restauration **une fois pour de vrai**, sur
un clone de `lab-git`, avant d'en avoir besoin : une sauvegarde jamais
restaurée n'est qu'une hypothèse.

### Mettre Gitea à jour

Les versions correctives (1.27.3 → 1.27.4) sortent toutes les quelques
semaines et corrigent régulièrement des failles. Le script est idempotent
et gère la mise à jour : il arrête le service, garde l'ancien binaire en
`/usr/local/bin/gitea.<ancienne-version>` et relance.

```bash
sudo systemctl start gitea-backup.service                  # dump d'abord
GITEA_VERSION=1.27.4 sudo -E bash ~/workbook/scripts/lab/install-gitea.sh
gitea --version
journalctl -u gitea -n 20 --no-pager | grep -i migrat  # migrations SQL
```

Les migrations de base sont automatiques au démarrage et **ne reviennent
pas en arrière** : d'où le dump avant. Pour un saut de version mineure
(1.27 → 1.28), lis les *breaking changes* du *changelog* sur
`github.com/go-gitea/gitea/releases` d'abord ; en cas de problème,
`sudo systemctl stop gitea`, remets l'ancien binaire, restaure le dump.

### Accès depuis le LAN de la maison

Le lab est isolé : sans rien faire, seul un tunnel SSH ou la route
statique du poste Ubuntu atteignent `lab-git`. La règle DNAT de
`lab-nat.sh` (`:3000 → 10.10.10.15:3000`, §0.3) publie l'interface web
sur l'IP LAN du nœud. Pour que `ROOT_URL` reste vrai (les liens que Gitea
génère pointent sur `lab-git.lab.local:3000`), il faut que ce nom se
résolve **vers l'IP du nœud** depuis ton LAN :

* **`hosts` des postes** (§0.4) : la ligne `192.168.1.50  pve pve.lab.local`
  devient `192.168.1.50  pve pve.lab.local lab-git.lab.local`. Avec la
  route statique du poste Ubuntu, laisse `lab-git.lab.local` sur
  `10.10.10.15` : l'accès est direct, sans DNAT.
* **DNS de la box** : la plupart des box (Freebox, Livebox, Bbox…) ont une
  page « DNS local » ou « noms d'hôtes » où tu peux associer
  `lab-git.lab.local` à `192.168.1.50`. Une entrée pour toute la maison,
  téléphone compris.

Le clone en SSH, lui, continue de passer par le bastion (port 2222) : il
n'y a pas de DNAT pour le port 22 de `lab-git`, et c'est voulu — un seul
point d'entrée SSH dans le lab.

**Facultatif : nginx en reverse proxy avec un certificat de la PKI de lab.**
Le module 15 te fait monter une petite autorité de certification pour
`lab.local`. Quand elle existe, tu peux servir Gitea en HTTPS sur le port
443 de `lab-git`, sans toucher à Gitea lui-même. Sur `lab-git` :

```bash
sudo apt install -y nginx
sudo install -m 644 lab-git.lab.local.crt /etc/ssl/certs/
sudo install -m 600 lab-git.lab.local.key /etc/ssl/private/
```

```nginx
# /etc/nginx/sites-available/gitea
server {
    listen 443 ssl;
    server_name lab-git.lab.local;
    ssl_certificate     /etc/ssl/certs/lab-git.lab.local.crt;
    ssl_certificate_key /etc/ssl/private/lab-git.lab.local.key;
    client_max_body_size 512m;          # push LFS, pièces jointes
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
server {
    listen 80;
    server_name lab-git.lab.local;
    return 301 https://$host$request_uri;
}
```

```bash
sudo ln -s /etc/nginx/sites-available/gitea /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

Et dans `app.ini`, trois lignes changent : `HTTP_ADDR = 127.0.0.1` (Gitea
n'est plus joignable que par nginx), `ROOT_URL = https://lab-git.lab.local/`
et, dans `[server]`, `PROTOCOL = http` reste (c'est nginx qui fait le TLS).
`sudo systemctl restart gitea`, remplace la DNAT `3000` par `443` dans
`lab-nat.sh`, importe le certificat de ta CA dans les navigateurs. Tant
que la PKI n'existe pas, reste en HTTP sur 3000 : dans un LAN privé, ce
n'est pas la priorité, et un certificat auto-signé apprendrait surtout à
cliquer sur « accepter le risque ».

### Dépannage

| Symptôme | Où regarder, quoi faire |
|---|---|
| `systemctl status gitea` → `failed`, redémarre en boucle | `journalctl -u gitea -n 50` : erreur de syntaxe `app.ini`, port 3000 déjà pris (`ss -tlnp`), ou `HOME`/`GITEA_WORK_DIR` absents de l'unité |
| `permission denied` dans le journal, page « 500 » | droits : `/var/lib/gitea` doit être à `git:git` en 750, `app.ini` lisible par `git` (`640 root:git`). `sudo chown -R git:git /var/lib/gitea` puis restart |
| `ssh -T git@lab-git` → `Permission denied (publickey)` | la clé n'est pas dans Gitea, ou `authorized_keys` non régénéré : `sudo -u git gitea admin regenerate keys` ; vérifie `/home/git/.ssh` en 700 et le fichier en 600, propriétaire `git` |
| `ssh -T` répond mais `git push` échoue : `gitea: command not found` | le `command=` de `authorized_keys` pointe sur un binaire déplacé : `regenerate keys` ; ou `AcceptEnv`/`PermitUserEnvironment` : rien à changer dans `sshd_config` normalement |
| L'installateur web réapparaît après restart | `INSTALL_LOCK = false` dans `app.ini` (restauré d'un vieux fichier) : passe-le à `true` |
| Liens de l'interface vers une mauvaise adresse | `ROOT_URL` ne correspond pas à l'URL tapée : corrige `app.ini`, restart |
| Doute général | `sudo -u git gitea doctor check --all --config /etc/gitea/app.ini` puis, pour corriger ce qu'il sait corriger, `... doctor check --all --fix` |

`gitea doctor` est ton `fsck` : il vérifie la cohérence base ↔ dépôts sur
disque, les hooks, les clés, les droits. Lance-le après chaque
restauration et chaque mise à jour.

::: astuce
Pose le snapshot `snap-clean` de `lab-git` **après** tout ça
(`qm snapshot 9006 snap-clean`), et sache que sur cette VM tu ne feras
jamais `qm rollback` : elle n'est pas un terrain de jeu, c'est ton
serveur. Les labs destructeurs se font sur les cinq autres.
:::

---

## 0.9 Versionner le workbook lui-même

Le workbook n'est pas seulement trois PDF : c'est un dépôt Git. Les
sources Markdown, les scripts, la chaîne de construction et, surtout,
**tes réponses** vivent dans un seul dépôt, poussé sur `lab-git`. Cette
section le met en place en une demi-heure ; le reste du workbook consiste
à le remplir.

### Le dépôt fourni : `workbook-repo.zip`

À côté des PDF, tu as reçu `workbook-repo.zip`. Il contient un dépôt Git
**déjà initialisé**, avec un premier commit :

```text
linux-devops-workbook/
├── .git/                    l'historique (1 commit : import initial)
├── .gitea/workflows/
│   └── build-pdf.yaml       reconstruit les PDF à chaque push (module 21)
├── .gitignore               build/, *.pdf, secrets…
├── README.md                présentation, structure, comment builder
├── CONTRIBUTING.md          règles de commit et de rangement
├── CONVENTIONS.md           la charte de rédaction des modules
├── Makefile                 make pdf | memo | check-ids | clean | zip-scripts
├── build.py                 Markdown -> LaTeX -> PDF (pandoc + XeLaTeX)
├── src/                     LES SOURCES : ne pas modifier
│   ├── 00-mise-en-place.md, 99-annexes.md, memo.md
│   ├── labs/MXX-slug.md     énoncés
│   └── solutions/MXX-slug.md corrigés
├── scripts/                 setup/ check/ break/ lab/ lib/ projects/
├── tex/  css/               template LaTeX, filtre pandoc, feuille de style
└── reponses/                TON TRAVAIL : un fichier par lab
    ├── README.md            comment ranger
    └── M07/L7.2.md          un exemple
```

Déballe-le sur ton **poste** (pas sur une VM : c'est ton éditeur et ton
navigateur qui vont s'en servir, et VS Code l'ouvrira comme un projet) :

```bash
mkdir -p ~/projets && cd ~/projets
unzip -q ~/Téléchargements/workbook-repo.zip     # crée linux-devops-workbook/
cd linux-devops-workbook
git log --oneline
# 3f2a9c1 chore: import initial du workbook Linux & DevOps
git status
# On branch main
# nothing to commit, working tree clean
```

Sous Windows, même chose dans PowerShell (`Expand-Archive` ou clic
droit), puis Git for Windows ou WSL. Si tu préfères repartir de zéro,
l'équivalent manuel est trois commandes : `git init -b main`, `git add
-A`, `git commit -m "chore: import initial du workbook Linux & DevOps"`.

### Premier push vers `lab-git`

Le dépôt `workbook/linux-devops-workbook` créé au §0.8 est vide : on lui
donne cet historique.

```bash
git config user.name  "Mathieu"
git config user.email "mathieu.teule@outlook.com"     # local au dépôt
git remote add origin git@lab-git:workbook/linux-devops-workbook.git
git push -u origin main
# Enumerating objects: 118, done.
# ...
# To lab-git:workbook/linux-devops-workbook.git
#  * [new branch]      main -> main
# branch 'main' set up to track 'origin/main'.
```

Recharge la page du dépôt dans Gitea : le README s'affiche, l'arborescence
est là, l'onglet *Actions* montre un workflow en attente (normal, voir
plus bas). `-u` mémorise `origin/main` comme branche suivie : ensuite,
`git push` et `git pull` sans argument suffisent.

::: astuce
Le `user.email` est **local** (`git config` sans `--global`) : ce dépôt
finira en public, tu y mets l'adresse que tu veux voir sur GitHub. Le
`--global` du §0.7 (`mathieu@exemple.invalid`) reste pour les dépôts de
lab. Gitea associe les commits à ton compte si l'adresse est déclarée
dans *Paramètres → Compte → Adresses e-mail*.
:::

### Convention de rangement

Trois zones, trois règles, à ne jamais mélanger :

| Zone | Contenu | Qui écrit |
|---|---|---|
| `src/`, `tex/`, `build.py` | les énoncés, corrigés, mémo, chaîne PDF | le workbook (toi seulement pour une coquille) |
| `scripts/` | setup, check, break, lab, projets | le workbook + **tes** scripts de défi dans `scripts/mes/` |
| `reponses/MXX/` | un fichier Markdown par lab, tes scripts, tes rapports | **toi**, et personne d'autre |

**Tes réponses vont dans `reponses/MXX/`, jamais dans `src/`.** Un
fichier par lab, nommé par l'identifiant : `reponses/M07/L7.2.md`,
`reponses/M10/BF10.1.md`, `reponses/M15/D15.md`, et un `E7.md` pour les
exercices guidés d'un module (ils sont trop courts pour un fichier
chacun). Le modèle vide est `reponses/M07/L7.2.md` ; rempli, ça donne :

```markdown
# L7.2 — Rotation des journaux applicatifs

Date : 2026-10-03 · Durée : 1 h 10 · VM : lab-web

## Démarche
1. `ls -la /var/log/factura/` : 14 fichiers, 2,1 Go, aucun compressé.
2. ...

## Résultat
`bash check_M07_02.sh` → 6 réussis, 0 échoué.

## Ce que j'ai appris / à revoir
- `logrotate -d` simule sans agir : à utiliser AVANT `-f`.
- Bloqué 20 min sur `su` dans le bloc logrotate : voir corrigé, *pourquoi*.
```

Les scripts que tu écris pour un défi vont à côté (`reponses/M07/D7/
rotate.sh`) **et**, s'ils ont vocation à resservir, dans `scripts/mes/`.
Le carnet de bord du §0.7 (`~/carnet/` sur `lab-adm`) peut rester où il
est ou rejoindre `reponses/carnet/` : à toi de voir, mais un seul endroit.

Pourquoi cette séparation ? Parce qu'un `git diff --stat src/` doit
toujours être vide (si le workbook sort une correction, tu la récupères
sans conflit) et parce qu'un recruteur qui ouvre `reponses/` voit ton
travail, pas des énoncés copiés.

### Ce qui n'est jamais commité

Le `.gitignore` fourni :

```gitignore
# généré par build.py : PDF, .tex, .aux, .log
build/
*.pdf
*.aux
*.log
*.toc
*.out
__pycache__/
.venv/
# mots de passe, jetons, clés de lab : JAMAIS dans l'historique
reponses/**/secrets*
```

Les PDF sont des **artefacts** : reproductibles depuis les sources en une
commande, lourds (plusieurs Mo par version) et illisibles en `diff`. Les
commiter fait grossir le dépôt à chaque page corrigée ; c'est pour ça que
`build/` est ignoré et que la CI les publie ailleurs. Les secrets : tout
fichier de `reponses/` dont le nom commence par `secrets` est ignoré,
pour que tu aies un endroit où noter un mot de passe de lab sans risquer
de le pousser. Un secret commité puis retiré est toujours dans
l'historique (module 17 : `git filter-repo`) — et sur GitHub, dans les
*forks* et les caches. Ça ne se répare pas, ça se **révoque**.

### Un commit par lab, une branche par module ?

Deux stratégies raisonnables :

* **Un commit par lab, directement sur `main`** : `feat(M07): L7.2
  rotation des journaux`. Simple, linéaire, et `git log --oneline` raconte
  ta progression jour par jour. C'est la recommandation pour les modules
  01 à 16.
* **Une branche par module** (`m17-git`, `m18-docker`), fusionnée par
  *pull request* dans Gitea à la fin du module : tu t'entraînes au *review*
  et aux PR, et tu peux « fermer » un module proprement. C'est la
  recommandation à partir du module 17, qui introduit précisément ce
  workflow — avant, ce serait du cérémonial sans contenu.

Dans les deux cas, **un commit = un lab terminé** (ou un défi, ou un Break
& Fix). Pas un commit « wip » par séance de 20 minutes, pas un commit « M07
fini » de quarante fichiers : le grain d'un commit, c'est l'unité de
travail qu'on peut décrire en une ligne et qu'on voudrait pouvoir annuler
seule.

### Messages de commit : Conventional Commits

Le format `type(portée): sujet`, en minuscules, à l'impératif, sans point
final, sujet ≤ 72 caractères :

```text
feat(M07): L7.2 rotation des journaux applicatifs
feat(M10): D10 script d'extension LVM à chaud
fix(M03): E3.4 corrige le calcul de l'umask
docs(carnet): séance du 2026-10-03
chore(scripts): mes/backup.sh passe shellcheck
```

Types utiles ici : `feat` (un lab, un défi, un livrable), `fix` (une
réponse corrigée après lecture du corrigé), `docs` (carnet, README,
post-mortem), `chore` (outillage, `.gitignore`), `refactor` (un script
réécrit sans changer ce qu'il fait). La portée est le module (`M07`) ou
le projet (`P2`). Le corps du message, après une ligne vide, dit
**pourquoi**, pas quoi (le diff dit quoi) : « corrigé parce que le check
échouait sur les fichiers cachés ». Le module 17 y revient et te fait
ajouter un hook qui refuse les messages hors format.

### Régénérer les PDF

La chaîne est Markdown → pandoc (avec le filtre `tex/divs.lua` pour les
encadrés) → XeLaTeX. Sur ton poste Ubuntu 24.04 ou dans WSL :

```bash
sudo apt update
sudo apt install -y pandoc texlive-xetex texlive-latex-extra \
  texlive-fonts-recommended fonts-dejavu python3
python3 build.py              # les 3 PDF, ~4 min la première fois
# Workbook-Linux-DevOps-3-Memo.pdf: 56 pages, 0 overfull hbox
# Workbook-Linux-DevOps-1-Enonces.pdf: 492 pages, 9 overfull hbox
# Workbook-Linux-DevOps-2-Corriges.pdf: 888 pages, 16 overfull hbox
python3 build.py memo         # un seul volume
ls build/*.pdf
```

Ou avec le `Makefile` : `make pdf` (les trois), `make memo`, `make
check-ids` (vérifie que chaque identifiant d'énoncé a son corrigé, via
`scripts/lib/check_ids.py`), `make clean` (vide `build/`), `make
zip-scripts` (produit `build/workbook-scripts.zip` à copier sur les VM,
§0.4). `texlive-latex-extra` pèse 1 Go avec ses recommandations : c'est
le prix de `tcolorbox`, `titlesec` et `fvextra`. Les « overfull hbox »
sont des lignes de code qui dépassent la marge ; s'il y en a plus d'une
dizaine, une source contient une ligne de plus de 80 colonnes.

### La CI : `.gitea/workflows/build-pdf.yaml`

Le dépôt contient un workflow Gitea Actions qui reconstruit les trois PDF
à chaque push sur `main` et les publie en **artefact** téléchargeable
depuis l'onglet *Actions* :

```yaml
name: build-pdf
on:
  push:
    branches: [main]
    paths: ["src/**", "tex/**", "build.py", ".gitea/workflows/**"]
  workflow_dispatch:

jobs:
  pdf:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Dépendances (pandoc, XeLaTeX, DejaVu)
        run: |
          apt-get update -q
          DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
            pandoc texlive-xetex texlive-latex-extra \
            texlive-fonts-recommended fonts-dejavu python3
      - name: Identifiants énoncés / corrigés
        run: python3 scripts/lib/check_ids.py
      - name: Construction des PDF
        run: python3 build.py
      - uses: actions/upload-artifact@v4
        with:
          name: workbook-pdf
          path: build/Workbook-Linux-DevOps-*.pdf
          retention-days: 30
```

Il **ne tournera pas avant le module 21** : Gitea Actions a besoin d'un
*runner* (`act_runner`) enregistré sur cette instance, et c'est
exactement ce que le module 21 installe sur `lab-ops`. Jusque-là, les
runs restent en attente (*waiting*) dans l'onglet *Actions*, sans
conséquence. Tu peux aussi désactiver Actions sur le dépôt (*Paramètres →
Unités*) et le réactiver plus tard. Quand le runner du module 21 existe,
enregistre-le une seconde fois sur `http://lab-git.lab.local:3000/` (un
`act_runner` peut servir plusieurs instances, ou tu en lances un second),
et le prochain push sur `main` produira les PDF en 6 à 8 minutes — le
temps d'installer TeX Live dans le conteneur ; le module 21 montre comment
construire une image `runner` qui l'embarque déjà.

::: attention
Le `paths:` évite de reconstruire 1 400 pages quand tu ne pousses qu'une
réponse dans `reponses/`. Les jobs tournent en root dans le conteneur du
runner, d'où `apt-get` sans `sudo`.
:::

### Le rendre public : miroir GitHub

Ton Gitea n'est visible que de ton LAN. Pour le portfolio (annexe C), le
dépôt doit être lisible depuis l'extérieur, et le moyen le plus simple est
un **push mirror** : Gitea pousse lui-même chaque commit vers un dépôt
GitHub, qui n'est qu'une copie en lecture. Tu continues à travailler
contre `lab-git` ; GitHub suit.

1. Sur GitHub : nouveau dépôt **vide** `linux-devops-workbook` (public,
   sans README). Puis *Settings → Developer settings → Personal access
   tokens → Fine-grained*, jeton limité à ce dépôt, permission *Contents:
   Read and write*, durée 90 jours.
2. Dans Gitea : dépôt → *Paramètres → Dépôt → Paramètres du miroir →
   Ajouter un miroir de push*. URL
   `https://github.com/<toi>/linux-devops-workbook.git`, nom
   d'utilisateur ton login GitHub, mot de passe le jeton, intervalle
   `8h`, et coche **Synchroniser lors du push**.
3. *Synchroniser maintenant*, puis vérifie sur GitHub.

Avant de rendre quoi que ce soit public, relis `reponses/` avec l'œil
d'un inconnu : pas de mot de passe, pas d'IP publique, pas de nom de
client ni d'employeur, pas de capture d'écran d'un vrai système. Les
corrigés (`src/solutions/`) sont sous licence « usage personnel » du
workbook : si tu rends le dépôt public, **retire-les** du miroir en les
excluant (branche `public` sans `src/solutions/`, poussée à la place de
`main`) ou en gardant le dépôt GitHub privé et en n'ouvrant que le lien à
un recruteur. Le README fourni prévoit les deux cas.

Un jeton GitHub dans les paramètres de Gitea est un secret **stocké
chiffré par `SECRET_KEY` dans la base** : c'est une raison de plus pour
que `app.ini` soit en `640` et le dump de sauvegarde hors de portée. Le
même mécanisme existe vers GitLab ou Codeberg.

### Le README

Le `README.md` livré fait le travail en une page : ce qu'est le dépôt, la
topologie du lab (le tableau du §0.3), comment construire les PDF, où sont
les réponses, la licence. Personnalise deux choses dès maintenant, et
commite-les :

```bash
sed -i 's/^Auteur : .*/Auteur : Mathieu — démarré le 2026-09-21/' README.md
git add README.md
git commit -m "docs(readme): auteur et date de démarrage"
git push
```

Et complète-le à chaque jalon du planning (§0.1) : une ligne « Semaine 4 :
module 07 terminé, D7 dans `reponses/M07/D7/` ». En seize semaines, ce
README devient la table des matières de ton portfolio, sans effort
supplémentaire.

::: check
`git remote -v` montre `origin git@lab-git:workbook/linux-devops-workbook.git`
; `git status` est propre après `python3 build.py` (les PDF sont ignorés) ;
`reponses/M07/L7.2.md` existe et `src/` n'a aucune modification ; le
dépôt est visible dans Gitea avec son README ; ton premier vrai commit
`feat(M01): ...` arrivera à la fin de la première séance du module 01.
:::
