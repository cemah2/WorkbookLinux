# Mémo Linux & DevOps

Aide-mémoire du workbook. Une section par module, des commandes prêtes à
copier, les erreurs qui coûtent cher, les one-liners à connaître par cœur.
Référence : Ubuntu 24.04 ; variantes Rocky 9 en ligne (`apt` / `dnf`).

| VM | IP | Rôle |
|---|---|---|
| `lab-adm` (9001) | 10.10.10.10 | bastion, contrôle Ansible |
| `lab-web` (9002) | 10.10.10.11 | nginx, reverse proxy, app |
| `lab-db` (9003) | 10.10.10.12 | PostgreSQL, disques `/dev/sdb` `/dev/sdc` |
| `lab-rhel` (9004) | 10.10.10.13 | Rocky 9 : dnf, firewalld, SELinux |
| `lab-ops` (9005) | 10.10.10.14 | Docker, runner CI, Prometheus, registre |
| `lab-git` (9006) | 10.10.10.15 | Gitea (binaire + SQLite), dépôt du workbook |

Utilisateur `mathieu` partout, réseau `10.10.10.0/24`, passerelle et DNS
`10.10.10.1`, domaine `lab.local`, snapshot propre `snap-clean`.

---

## 01 · Shell

### Raccourcis readline

| Commande | Effet |
|---|---|
| `Ctrl-A` / `Ctrl-E` | début / fin de ligne |
| `Ctrl-W` / `Alt-Backspace` | efface le mot avant le curseur |
| `Ctrl-U` / `Ctrl-K` | coupe avant / après le curseur |
| `Ctrl-Y` | recolle ce qui vient d'être coupé |
| `Ctrl-R` (puis `Ctrl-R`) | recherche arrière dans l'historique |
| `Ctrl-G` | abandonne la recherche sans exécuter |
| `Alt-.` | insère le dernier argument de la commande précédente |
| `Ctrl-L` | efface l'écran, garde la ligne en cours |
| `Ctrl-Z` / `fg` | suspend / reprend le processus au premier plan |
| `Ctrl-D` | fin de fichier sur stdin, ferme le shell |

### Historique

| Commande | Effet |
|---|---|
| `!!` / `!$` / `!*` | dernière commande / son dernier argument / tous |
| `!nginx` / `!?nginx?` | dernière commande commençant par / contenant |
| `sudo !!` | rejoue la dernière commande avec sudo |
| `^ancien^nouveau` | rejoue la dernière commande en remplaçant |
| `fc -l` / `fc` | liste / rouvre la dernière commande dans `$EDITOR` |
| `history \| tail -20` | 20 dernières entrées |
| ` cmd` (espace devant) | non enregistrée si `HISTCONTROL=ignoreboth` |
| `HISTTIMEFORMAT='%F %T '` | horodate l'historique |
| `shopt -s histappend` | ajoute au fichier au lieu d'écraser |

### Expansions, dans l'ordre

```text
1 accolades {a,b} {1..5}  2 tilde ~  3 $VAR $(( )) $( )
4 découpage sur $IFS (non quoté)  5 globbing * ? [a-z]
6 suppression des quotes
```

| Commande | Effet |
|---|---|
| `cp f.conf{,.bak}` | copie `f.conf` en `f.conf.bak` |
| `mkdir -p app/{bin,etc,log}` | trois répertoires d'un coup |
| `echo {01..10}` | `01 02 ... 10` (zéros conservés) |
| `echo "$v"` / `echo '$v'` | valeur / littéral `$v` |
| `echo "*"` | l'étoile, jamais globbée entre guillemets |
| `printf '%s\n' "$@"` | un argument par ligne, sans surprise |
| `shopt -s nullglob` | un glob sans résultat devient vide |
| `set -f` / `set +f` | désactive / réactive le globbing |

### Variables et environnement

| Commande | Effet |
|---|---|
| `APP=x` / `export APP` | variable de shell / d'environnement |
| `export -n APP` | retire l'export sans détruire la variable |
| `unset APP` | supprime la variable |
| `env \| sort` | ce que verront les processus fils |
| `declare -p APP` | type, valeur, attributs |
| `readonly VAR=x` | constante |
| `type -a python3` | alias, fonction, builtin, fichiers : tout |
| `command -v systemctl` | chemin, scriptable, POSIX |
| `hash -r` | vide le cache des chemins |
| `alias ll='ls -alF'` / `unalias ll` | crée / retire un alias |
| `\ls` ou `command ls` | contourne un alias |
| `echo $$` / `echo $?` | PID du shell / code de la dernière commande |
| `set -o` / `shopt` | options du shell |

### Fichiers de démarrage

| Commande | Effet |
|---|---|
| `bash -l` | shell login : `/etc/profile`, `~/.bash_profile` ou `~/.profile` |
| `bash` | interactif non-login : `/etc/bash.bashrc`, `~/.bashrc` |
| `ssh h cmd` / cron | non interactif : rien, sauf `$BASH_ENV` |
| `echo $-` | contient `i` si interactif, `l` si login |
| `source ~/.bashrc` | recharge sans se déconnecter |

### Redirections de base

| Commande | Effet |
|---|---|
| `cmd > f` / `cmd >> f` | stdout écrase / ajoute |
| `cmd 2> f` | stderr vers `f` |
| `cmd > f 2>&1` | les deux vers `f` (l'ordre compte) |
| `cmd &> f` | idem, raccourci bash |
| `cmd 2>&1 \| tee -a f` | écran et fichier |
| `cmd > /dev/null 2>&1` | silence complet |
| `cmd < f` | `f` sur stdin |
| `cmd <<< "$v"` | chaîne sur stdin |

### Navigation et documentation

| Commande | Effet |
|---|---|
| `cd -` | répertoire précédent |
| `pushd /etc/nginx` / `popd` / `dirs -v` | pile de répertoires |
| `CDPATH=.:/etc:/var/log` | `cd sites-enabled` depuis n'importe où |
| `man 5 crontab` | section 5 = formats ; 1 = commandes ; 8 = admin |
| `man -k socket` / `apropos` | cherche dans les descriptions |
| `/motif` puis `n` dans `man` | recherche dans le pager |
| `cmd --help` / `help cd` | aide courte / aide d'un builtin |
| `whatis ls` | description en une ligne |
| `ls /usr/share/doc/nginx/` | README, exemples livrés par le paquet |
| `tldr tar` | exemples courts (`apt install tldr`) |

::: piege
* `n=5; echo {1..$n}` : les accolades passent avant `$n`, ça n'itère pas.
* `rm $f` avec un espace dans le nom : découpage en deux arguments.
* Créer `~/.bash_profile` coupe le pont `~/.profile` → `~/.bashrc` d'Ubuntu.
* Un `.bashrc` commence par `case $- in *i*) ;; *) return;; esac` : tout ce
  qui suit n'existe pas pour cron ni pour `ssh h cmd`.
* `which` ne voit ni alias ni fonctions : `type` ou `command -v` en script.
* `2>&1 > f` envoie stderr au terminal, pas dans `f`.
:::

::: astuce
* `sudo !!` — rejoue la commande oubliée sans sudo.
* `cp /etc/nginx/nginx.conf{,.$(date +%F)}` — sauvegarde datée en un coup.
* `Alt-.` — reprend le dernier argument, cinq fois plus vite que la souris.
:::

---

## 02 · Système de fichiers et FHS

### Où ranger quoi

| Commande | Effet |
|---|---|
| `/etc` | configuration statique, éditable |
| `/usr` | code installé par les paquets, lecture seule en principe |
| `/usr/local` | ce que tu compiles ou installes toi-même |
| `/opt/<produit>` | logiciel tiers auto-contenu |
| `/var/lib`, `/var/log`, `/var/cache` | état persistant, journaux, caches |
| `/srv` | données servies (web, ftp) |
| `/run` | pid, sockets, verrous (tmpfs, vidé au boot) |
| `/tmp` | temporaire, nettoyé ; `/var/tmp` survit au reboot |
| `/proc`, `/sys`, `/dev` | noyau : processus, matériel, périphériques |
| `/boot` | noyaux, initramfs, GRUB |

### Inodes, liens, types

| Commande | Effet |
|---|---|
| `stat f` | inode, liens, blocs, atime/mtime/ctime |
| `stat -c '%i %h %s %U:%G %a' f` | inode, liens, taille, propriétaire, mode |
| `ls -li` | numéro d'inode en première colonne |
| `df -i /var` | inodes utilisés / libres |
| `ln cible lien` | lien physique : même inode, même FS |
| `ln -s /chemin/cible lien` | lien symbolique : un chemin dans un fichier |
| `ln -sfn nouveau lien` | remplace un lien sans passer par un `rm` |
| `readlink -f lien` | chemin résolu, absolu |
| `find . -xtype l` | liens symboliques cassés |
| `file -- rapport.pdf` | type réel, par le contenu |
| `lsof +L1` | fichiers supprimés encore ouverts (nlink = 0) |

### Espace disque

| Commande | Effet |
|---|---|
| `df -h` / `df -hT` | occupation par FS / avec le type |
| `du -sh rép` | blocs réellement alloués |
| `du -xh --max-depth=1 / \| sort -h` | classement, sans changer de FS |
| `du -sh --apparent-size f` | taille déclarée (fichiers creux) |
| `ncdu -x /` | exploration interactive |
| `find / -xdev -size +500M -type f` | gros fichiers, même FS |
| `truncate -s 0 gros.log` | vide sans supprimer (garde l'inode ouvert) |
| `: > /proc/PID/fd/N` | vide un fichier supprimé encore ouvert |
| `tune2fs -m 1 /dev/sdb1` | réserve root 5 % → 1 % (ext4) |

### find

| Commande | Effet |
|---|---|
| `find /var/log -name '*.log' -size +100M` | par nom et taille |
| `find . -iname '*.jpg' -mtime -1` | modifié il y a moins de 24 h |
| `find . -mmin -15` | moins de 15 minutes |
| `find . -newer /tmp/repere` | plus récent que ce fichier |
| `find /home -user mathieu -group www-data` | par propriétaire |
| `find . -maxdepth 2 -type d` | profondeur limitée |
| `find . -path '*/node_modules' -prune -o -type f -print` | exclut un arbre |
| `find . -name '*.tmp' -delete` | supprime (test avec `-print` avant) |
| `find . -name '*.log' -exec gzip {} +` | regroupe les fichiers, rapide |
| `find . -type f -print0 \| xargs -0 -r sha256sum` | noms à espaces sûrs |
| `find / -perm -4000 -type f 2>/dev/null` | binaires SUID |
| `find /etc -mmin -60 -type f` | ce qui a changé dans la dernière heure |
| `find . -empty -type d -delete` | répertoires vides |
| `-mtime +7` / `-7` | plus / moins de 7 jours (tranches de 24 h) |
| `-a`, `-o`, `!`, `\( \)` | et, ou, non, groupement |

### /proc, /sys, montages

| Commande | Effet |
|---|---|
| `cat /proc/loadavg /proc/meminfo` | charge, mémoire |
| `cat /proc/mounts` | ce que le noyau a vraiment monté |
| `ls -l /proc/PID/fd` | descripteurs ouverts |
| `readlink /proc/PID/cwd /proc/PID/exe` | répertoire courant, binaire |
| `tr '\0' ' ' < /proc/PID/cmdline` | ligne de commande |
| `cat /sys/block/sda/queue/rotational` | 1 = disque mécanique |
| `echo 1 \| sudo tee /sys/block/sda/device/rescan` | relit la taille du disque |
| `findmnt` / `findmnt -T /var/log` | arbre des montages / montage d'un chemin |
| `findmnt -t tmpfs` | uniquement les tmpfs |
| `mount --bind /srv/data /var/www/data` | même contenu à deux endroits |
| `mount -o remount,ro /srv` | passe en lecture seule |

::: rhel
Rocky 9 : XFS par défaut (`xfs_info /point`, `xfs_growfs`, jamais de
réduction), inodes alloués dynamiquement, `tune2fs` sans effet.
:::

::: piege
* `find . -delete -name '*.tmp'` efface tout : `-delete` en dernier.
* `df` plein et `du` bas : fichier supprimé tenu ouvert, `lsof +L1`.
* `No space left` avec `df` à 60 % : inodes épuisés, `df -i`.
* `rm gros.log` sur un fichier ouvert ne libère rien : `truncate -s 0`.
* Un lien symbolique relatif est résolu depuis le répertoire du lien.
* `/var/run` et `/var/lock` sont des liens vers `/run` : écris `/run`.
:::

::: astuce
* `du -xh --max-depth=1 / | sort -h | tail` — le disque plein en 5 s.
* `find /var/log -name '*.gz' -mtime +30 -delete` — ménage des rotations.
* `findmnt --verify` — valide `fstab` avant un reboot.
:::

---

## 03 · Permissions

### Lire et poser des droits

| Commande | Effet |
|---|---|
| `ls -l` / `ls -ld rép` | droits d'un fichier / du répertoire lui-même |
| `stat -c '%A %a %U:%G %n' f` | symbolique, octal, propriétaire |
| `chmod 640 f` | `rw- r-- ---` |
| `chmod u+x,g-w,o= f` | ajoute, retire, vide |
| `chmod a+r f` | `a` = ugo |
| `chmod g=u f` | copie les droits de u sur g |
| `chmod -R u=rwX,go=rX arbo/` | `X` : x seulement sur rép et déjà-x |
| `find arbo -type d -exec chmod 755 {} +` | répertoires seuls |
| `find arbo -type f -exec chmod 644 {} +` | fichiers seuls |
| `chown mathieu:factura f` | propriétaire et groupe |
| `chown -R --from=www-data mathieu /srv` | seulement ce qui appartient à |
| `chgrp -R factura /srv/factura` | groupe seul |
| `chown --reference=modele f` | copie propriétaire d'un autre fichier |
| `install -m 0750 -o factura -g factura -d /var/lib/factura` | crée avec droits |

### r/w/x : fichier contre répertoire

| Commande | Effet |
|---|---|
| `r` sur un rép | lister les noms |
| `w` sur un rép | créer, supprimer, renommer des entrées |
| `x` sur un rép | traverser, accéder à un nom connu |
| `chmod 711 ~` | pas de listing, accès par nom exact |
| `chmod 1777 /partage` | tout le monde écrit, seul le propriétaire efface |
| supprimer un fichier | dépend du `w` du répertoire parent |

### umask et bits spéciaux

| Commande | Effet |
|---|---|
| `umask` / `umask -S` | valeur courante, octale / symbolique |
| `umask 027` | fichiers 640, répertoires 750 |
| `umask 077` | fichiers 600, répertoires 700 |
| `UMASK 027` dans `/etc/login.defs` | défaut des sessions login |
| `UMask=0027` dans `[Service]` | umask d'un service systemd |
| `chmod 4755 bin` | SUID : s'exécute avec l'UID du propriétaire |
| `chmod 2775 rép` | SGID : les nouveaux fichiers héritent du groupe |
| `chmod 1777 rép` | sticky : seul le propriétaire supprime |
| `chmod g+s rép` | SGID en symbolique |
| `find / -perm -4000 -type f 2>/dev/null` | inventaire des SUID |
| `find / -perm -2000 -type f 2>/dev/null` | inventaire des SGID |
| `find / -perm -o+w ! -type l 2>/dev/null` | fichiers world-writable |

`s` minuscule = bit spécial + x ; `S` ou `T` majuscule = bit spécial sans x
(presque toujours une erreur).

### ACL, attributs, capabilities

| Commande | Effet |
|---|---|
| `getfacl f` | ACL complète, `#effective:` si masque limitant |
| `setfacl -m u:webdev:rX /srv/factura` | droits à un utilisateur |
| `setfacl -m g:factura:rwx rép` | à un groupe |
| `setfacl -x u:webdev f` | retire une entrée |
| `setfacl -b f` | retire toutes les ACL étendues |
| `setfacl -d -m g:webdev:rX /srv/data` | ACL par défaut, héritée |
| `setfacl -R -m g:webdev:rX /srv/data` | récursif sur l'existant |
| `setfacl -m m::rw f` | modifie le masque |
| `getfacl -R /srv > acl.bak` / `setfacl --restore=acl.bak` | sauvegarde |
| `chattr +i f` / `chattr -i f` | immuable, même pour root |
| `chattr +a f` | append-only |
| `lsattr f` | attributs |
| `getcap /usr/bin/ping` | capabilities d'un binaire |
| `setcap cap_net_bind_service=+ep /opt/app/api` | port < 1024 sans root |
| `setcap -r /opt/app/api` | retire |
| `capsh --print` | capabilities du processus courant |

### Démarche « permission denied »

| Commande | Effet |
|---|---|
| `namei -l /srv/factura/exports/r.csv` | droits de chaque composant |
| `id mathieu` | groupes réels |
| `sudo -u www-data stat f` | tester en tant que l'utilisateur |
| `sudo -u www-data test -r f && echo ok` | test lecture |
| `getenforce` / `aa-status` | écarter SELinux / AppArmor |
| `ls -l /dev/log ; ls -ld /run/x` | sockets et répertoires runtime |

::: piege
* `chmod -R 755` rend tous les fichiers exécutables : utilise `X`.
* Neuf fois sur dix, c'est un `x` manquant sur un répertoire parent.
* Le propriétaire n'est jamais « other » : `chmod 007 f` bloque le
  propriétaire alors que les autres lisent.
* Un service systemd n'hérite pas du umask de ton shell (`UMask=`).
* `chattr +i` sur `/etc/resolv.conf` bloque aussi les mises à jour de paquets.
* Le masque ACL plafonne : `u:webdev:rwx` avec `mask::r--` donne `r--`.
:::

::: astuce
* `namei -l chemin` — la permission manquante en un coup d'œil.
* `chmod -R u=rwX,go=rX /var/www/site` — récursif propre.
* `setfacl -d -m g:dev:rwX /srv/partage` — plus jamais de fichier 644 perdu.
:::

---

## 04 · Utilisateurs, groupes, sudo

### Comptes

| Commande | Effet |
|---|---|
| `adduser sophie` | interactif Debian : home, skel, mot de passe |
| `useradd -m -s /bin/bash -c "Sophie P." sophie` | bas niveau, `-m` = home |
| `useradd -r -s /usr/sbin/nologin -d /var/lib/x x` | compte de service |
| `useradd -m -G sudo,docker -u 1500 sophie` | groupes et UID imposés |
| `usermod -aG deploy sophie` | ajoute un groupe secondaire |
| `usermod -G deploy sophie` | remplace tous les secondaires (danger) |
| `usermod -l nouveau -d /home/nouveau -m ancien` | renomme et déplace |
| `usermod -s /usr/sbin/nologin sophie` | change le shell |
| `usermod -L` / `-U sophie` | verrouille / déverrouille |
| `userdel -r sophie` | supprime compte, home, spool |
| `groupadd -g 1500 factura` / `groupdel` | groupes |
| `gpasswd -a sophie factura` / `-d` / `-A` | membre, retrait, admin |
| `groupmod -n nouveau ancien` | renomme un groupe |
| `deluser sophie factura` | retire d'un groupe (Debian) |
| `getent passwd sophie` / `getent group factura` | via NSS (LDAP compris) |
| `id sophie` / `id -nG` | identité, groupes |
| `groups sophie` | groupes |
| `newgrp deploy` / `sg deploy -c cmd` | groupe primaire dans un sous-shell |
| `who` / `w` / `last` / `lastlog` | sessions, dernières connexions |
| `pkill -KILL -u sophie` | éjecte un utilisateur |
| `vipw` / `vigr` | édite passwd/group avec verrou |
| `pwck` / `grpck` | vérifie la cohérence des fichiers |

### Mots de passe et cycle de vie

| Commande | Effet |
|---|---|
| `passwd sophie` | change le mot de passe |
| `passwd -S sophie` | `P` défini, `L` verrouillé, `NP` vide |
| `passwd -l` / `-u sophie` | verrouille / déverrouille (`!` dans shadow) |
| `passwd -e sophie` ou `chage -d 0 sophie` | changement forcé à la connexion |
| `chage -l sophie` | toutes les dates en clair |
| `chage -M 90 -m 1 -W 14 -I 7 sophie` | maxi, mini, avertissement, inactivité |
| `chage -E 2026-12-31 sophie` | expiration du compte |
| `chage -E -1 sophie` | retire l'expiration |
| `echo 'sophie:MdP' \| chpasswd` | non interactif, en masse |
| `openssl passwd -6 'MdP'` | hachage SHA-512 pour Ansible / useradd -p |
| `awk -F: '($2==""){print $1}' /etc/shadow` | mots de passe vides |
| `awk -F: '($3==0){print $1}' /etc/passwd` | comptes UID 0 |
| `awk -F: '$3>=1000 && $7!~/nologin/' /etc/passwd` | humains avec shell |
| `faillock --user karim` / `--reset` | compteur d'échecs PAM |

`/etc/shadow` champ 2 : `$y$` yescrypt (Ubuntu), `$6$` SHA-512 (Rocky),
`!` verrouillé, `*` jamais défini, vide = sans mot de passe.

### sudo

| Commande | Effet |
|---|---|
| `sudo visudo` | édite `/etc/sudoers` avec validation |
| `sudo visudo -f /etc/sudoers.d/60-deploy` | fragment (0440, sans `.` ni `~`) |
| `sudo visudo -c` | valide tout |
| `sudo -l` / `sudo -l -U karim` | ce que je / karim peut faire |
| `sudo -u www-data -- cmd` | en tant que www-data |
| `sudo -i` / `sudo -s` | shell login root / shell root, ton env |
| `sudo -k` / `sudo -v` | oublie / prolonge le ticket |
| `sudo -n true` | teste sans prompt (scripts, Ansible) |
| `sudo -E cmd` | conserve l'environnement (si autorisé) |
| `journalctl _COMM=sudo` | traces sudo |

```text
karim  ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx
%deploy ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload nginx, \
                            /usr/bin/journalctl -u nginx *
Defaults timestamp_timeout=5, logfile=/var/log/sudo.log
Defaults:karim !authenticate
```

### PAM, limites, NSS

| Commande | Effet |
|---|---|
| `/etc/pam.d/<service>` | `auth`, `account`, `password`, `session` |
| `pam_faillock.so deny=5 unlock_time=600` | verrou après 5 échecs |
| `pam_pwquality.so minlen=12` | qualité des mots de passe |
| `pam_limits.so` + `/etc/security/limits.conf` | `nofile`, `nproc` |
| `ulimit -n` / `ulimit -u` | limites de la session |
| `cat /etc/nsswitch.conf` | ordre des sources `files systemd sss` |
| `getent passwd \| wc -l` | tous les comptes vus par le système |

::: rhel
Rocky : groupe admin `wheel` (`usermod -aG wheel x`), `adduser` est un lien
vers `useradd` (non interactif), `authselect` gère PAM.
:::

::: piege
* `usermod -G` sans `-a` retire l'utilisateur de tous ses autres groupes.
* Un nouveau groupe n'est visible qu'après reconnexion (`newgrp`, `exec su -`).
* `sudo vim`, `less`, `find`, `awk`, `tar` : c'est un shell root délégué.
* Un fichier `/etc/sudoers.d/` avec un `.` dans le nom est ignoré en silence.
* `passwd -l` ne bloque pas la clé SSH ; `chage -E` bloque tout.
* `/etc/skel` ne s'applique qu'à la création avec `-m`.
:::

::: astuce
* `sudo -l -U karim` — audite un compte sans se connecter dedans.
* `getent passwd sophie` — la seule réponse qui compte avec LDAP/SSSD.
* `awk -F: '$3>=1000{print $1}' /etc/passwd` — les humains.
:::

---

## 05 · Traitement de texte

### Flux et pipelines

| Commande | Effet |
|---|---|
| `cmd > f 2>&1` | stdout et stderr dans `f` |
| `cmd 2>&1 \| tee -a f` | écran et fichier |
| `echo msg >&2` | écrit sur stderr |
| `exec 3> f ; echo x >&3 ; exec 3>&-` | descripteur durable |
| `cat <<'EOF' ... EOF` | here-doc quoté : rien n'est développé |
| `cat <<-EOF` | retire les tabulations de tête |
| `diff <(sort a) <(sort b)` | substitution de processus |
| `cmd \| tee >(gzip > copie.gz) > sortie` | dérivation d'un flux |
| `set -o pipefail` | le pipeline renvoie le pire code |
| `echo "${PIPESTATUS[@]}"` | codes de chaque maillon |
| `xargs -n 1 -P 4 cmd` | 1 argument par appel, 4 en parallèle |
| `xargs -I{} mv {} {}.old` | placeholder |
| `find . -print0 \| xargs -0 -r cmd` | noms à espaces, rien si vide |
| `yes \| cmd` / `cmd < /dev/null` | répond oui / ferme stdin |

### Découper, recomposer

| Commande | Effet |
|---|---|
| `cut -d: -f1,7 /etc/passwd` | champs par délimiteur mono-caractère |
| `cut -c5-12 f` | colonnes de caractères |
| `paste -d, a b` | colle ligne à ligne |
| `join -t, -1 2 -2 1 a b` | jointure sur fichiers triés |
| `tr 'a-z' 'A-Z'` / `tr -d '\r'` / `tr -s ' '` | traduit, supprime, compresse |
| `column -t -s,` | aligne en colonnes |
| `nl -ba f` / `tac f` / `rev f` | numérote, inverse lignes, inverse chars |
| `split -l 2000 -d f part-` | découpe |
| `wc -l` / `-w` / `-c` / `-L` | lignes, mots, octets, ligne max |
| `head -n 20` / `tail -n +2` | 20 premières / à partir de la 2e |
| `tail -F f` | suit malgré la rotation |
| `fold -w 70 -s f` | replie à 70 colonnes |
| `shuf -n 5 f` | 5 lignes au hasard |
| `seq 1 5` / `seq -w 1 10` | séquence, avec zéros |

### Trier, dédoublonner, comparer

| Commande | Effet |
|---|---|
| `sort -t, -k3,3 -k10,10nr f` | 3e champ asc, puis 10e numérique desc |
| `sort -k2,2 f` | champ 2 seul (`-k2` = jusqu'à la fin) |
| `sort -h` / `sort -V` | tailles humaines / versions |
| `sort -u` / `sort -s` | dédoublonne sur la clé / stable |
| `sort -R f` | mélange |
| `uniq -c` / `-d` / `-u` | compte, doublons seuls, uniques seuls |
| `sort \| uniq -c \| sort -rn \| head` | le top N canonique |
| `comm -12 a b` / `comm -23 a b` | communs / dans a seulement (triés) |
| `diff -u ancien nouveau` | diff unifié |
| `diff -r rep1 rep2` / `diff -q` | récursif / noms seuls |
| `patch -p0 < p.patch` / `patch -R -p0` | applique / annule |
| `cmp a b` | premier octet différent |

### grep

| Commande | Effet |
|---|---|
| `grep -E 'a\|b' f` | regex étendue |
| `grep -P '\d{3}' f` | PCRE |
| `grep -v '^#' f \| grep -v '^$'` | sans commentaires ni lignes vides |
| `grep -i` / `-w` / `-x` | casse, mot entier, ligne entière |
| `grep -o 'user=[^ ]*' f` | seulement la partie qui matche |
| `grep -c motif f` | nombre de lignes |
| `grep -rn motif /etc` | récursif avec numéros |
| `grep -rl motif /etc` / `-L` | fichiers avec / sans |
| `grep -A2 -B2 motif f` / `-C3` | contexte |
| `grep -F 'a.b' f` | motif littéral |
| `grep -q motif f && echo oui` | silencieux, pour un `if` |
| `grep --include='*.conf' -r x /etc` | filtre de noms |
| `grep -m1 motif f` | s'arrête au premier |
| `zgrep motif f.gz` | dans une archive gzip |

### sed

| Commande | Effet |
|---|---|
| `sed 's/a/b/' f` / `s/a/b/g` / `s/a/b/2` | 1re, toutes, 2e occurrence |
| `sed -E 's#(/orders)/[0-9]+#\1/:id#g'` | groupes, séparateur libre |
| `sed -n '/ERROR/p' f` | imprime seulement (= grep) |
| `sed '5d'` / `'2,10d'` / `'/^#/d'` / `'/^$/d'` | supprime |
| `sed -n '/^\[web\]/,/^\[/p' f` | plage entre deux motifs |
| `sed -n '10,20p;20q' f` | lignes 10-20, sort tôt |
| `sed '3a texte'` / `'3i texte'` / `'3c texte'` | ajoute, insère, remplace |
| `sed -i.bak 's/8m/32m/' f` | en place avec sauvegarde |
| `sed -i '/^#/!s/x/y/' f` | sauf sur les commentaires |
| `sed 's/.*/"&"/' f` | `&` = tout le match |
| `sed '$d' f` / `sed '1!G;h;$!d'` | dernière ligne / inverse (tac) |
| `sed -i 's/\r$//' f` | dos2unix |
| `sed -i '1s/^\xEF\xBB\xBF//' f` | retire un BOM |

### awk

| Commande | Effet |
|---|---|
| `awk '{print $1, $NF}' f` | premier et dernier champ |
| `awk -F: '$3>=1000{print $1}' /etc/passwd` | filtre + champ |
| `awk 'NR>1' f` / `awk 'NR==5'` | saute l'en-tête / ligne 5 |
| `awk 'NF' f` | lignes non vides |
| `awk '{s+=$3} END{print s}' f` | somme |
| `awk '{a[$1]++} END{for(k in a)print k,a[k]}' f` | compte par clé |
| `awk -F, -v s=200 '$10>s{n++} END{print n+0}' f` | seuil externe |
| `awk 'NR==FNR{m[$1]=$2;next}{print $0,m[$1]}' t f` | jointure en mémoire |
| `awk '{printf "%-10s %8.2f\n",$1,$2}' f` | format |
| `awk 'length>80' f` | lignes trop longues |
| `awk '!seen[$0]++' f` | dédoublonne sans trier |
| `awk -F'[;,]' ...` | plusieurs séparateurs (regex) |
| `awk 'BEGIN{OFS=","}{$1=$1;print}' f` | réécrit avec un autre séparateur |
| `awk '/deb/,/fin/' f` | plage entre motifs |

### JSON, YAML, encodages

| Commande | Effet |
|---|---|
| `jq . f.json` | reformate |
| `jq -r '.results[] \| select(.env=="prod") \| .hostname' f` | filtre |
| `jq '[.results[].specs.ram_go] \| add' f` | somme |
| `jq -r '.results[] \| [.hostname,.ip] \| @csv' f` | CSV |
| `jq -r '.[] \| "\(.name) \(.ip)"' f` | interpolation |
| `jq 'keys' f` / `jq 'length' f` | clés / taille |
| `jq -c '.' f` | une ligne par objet |
| `yq -r '.services \| keys[]' f.yaml` | YAML avec `yq` |
| `yq -o json f.yaml` | conversion |
| `python3 -m json.tool f.json` | sans jq |
| `file -i f` | encodage |
| `iconv -f ISO-8859-1 -t UTF-8 f > f.utf8` | conversion |
| `base64 -w0 f` / `base64 -d` | encode / décode |
| `od -c f \| head` / `xxd f \| head` | octets |

::: piege
* `sort -k2` trie du champ 2 jusqu'à la fin de ligne : `-k2,2`.
* `uniq` sans `sort` devant ne dédoublonne que les lignes adjacentes.
* `sed -i` sans suffixe ne sauvegarde rien : `-i.bak` sur la prod.
* `.*"` est gourmand : il va jusqu'au dernier guillemet.
* `for (k in tab)` en awk : ordre indéfini, repasse par `sort`.
* `cut` ne comprend pas le CSV quoté : `awk` ou `python3 -c` avec `csv`.
* `grep` en BRE : `+ ? { } ( ) |` doivent être échappés, ou `-E`.
:::

::: astuce
* `awk '{print $1}' access.log | sort | uniq -c | sort -rn | head` — top IP.
* `grep -rn --include='*.conf' 'listen' /etc/nginx` — où c'est configuré.
* `jq -r '.[] | select(.status!="ok") | .name' rapport.json` — les KO.
:::

---

## 06 · Vim, archives, transferts

### Vim : survie et déplacements

| Commande | Effet |
|---|---|
| `Esc` | mode normal |
| `i` `a` `I` `A` `o` `O` | insérer avant, après, début, fin, ligne dessous, dessus |
| `:w` `:q` `:wq` `:x` `ZZ` | écrire, quitter, les deux |
| `:q!` `ZQ` | quitter sans écrire |
| `u` / `Ctrl-R` | annuler / refaire |
| `w` `b` `e` / `0` `^` `$` | mots / début, premier non-blanc, fin |
| `gg` `G` `:42` `42G` | début, fin, ligne 42 |
| `Ctrl-F` `Ctrl-B` `Ctrl-D` `Ctrl-U` | page, demi-page |
| `%` | parenthèse appariée |
| `/motif` `?motif` `n` `N` `*` | recherche, suivant, mot sous le curseur |
| `f;` `t;` `;` `,` | jusqu'au caractère, répéter |
| `ma` puis `` `a `` | marque et retour |
| `Ctrl-O` `Ctrl-I` | recule / avance dans les sauts |
| `Ctrl-G` | position dans le fichier |

### Opérateurs, objets, visuel, ex

| Commande | Effet |
|---|---|
| `dd` `yy` `cc` / `3dd` | ligne : supprime, copie, change / 3 lignes |
| `dw` `d$` `d0` `dG` `dgg` | jusqu'au mot, fin, début, fin/début fichier |
| `daw` `ciw` `ci"` `ya{` `dap` | objets : mot, guillemets, bloc, paragraphe |
| `p` `P` / `"ayy` `"ap` | coller après/avant / registre `a` |
| `>>` `<<` / `>ip` | indenter |
| `.` / `5.` | rejoue la dernière modification |
| `xp` / `ddp` | échange deux caractères / deux lignes |
| `J` | joint la ligne suivante |
| `~` `gUiw` `guiw` | casse |
| `v` `V` `Ctrl-V` | visuel caractère, ligne, bloc |
| `Ctrl-V 30j I # Esc` | commente 30 lignes |
| `Ctrl-V 30j l x` | décommente |
| `:%s/x/y/g` / `:%s/x/y/gc` | remplace partout / avec confirmation |
| `:10,42s/x/y/` / `:'<,'>s/x/y/` | plage / sélection |
| `:%s#/opt/#/srv/#g` | autre délimiteur |
| `:g/motif/d` / `:v/motif/d` | supprime avec / sans le motif |
| `:g/^$/d` / `:sort u` | lignes vides / trie et dédoublonne |
| `:g/motif/normal A;` | commande normale sur chaque ligne |
| `:r fichier` / `:r !cmd` | insère un fichier / une sortie |
| `:e f` / `:e!` | ouvre / recharge en jetant |
| `:ls` `:bn` `:bp` / `:sp` `:vs` `Ctrl-W w` | tampons / fenêtres |
| `:set paste` / `:set nopaste` | collage sans escalier |
| `:set nu` / `:set list` | numéros / caractères invisibles |
| `:noh` | efface le surlignage |
| `:w !sudo tee % > /dev/null` | écrit un fichier root sans sudo |
| `vim -r f` / `vim -r` | récupère depuis le swap / liste |
| `vim +42 f` / `vim +/motif f` | ouvre à la ligne / au motif |
| `vimdiff a b` / `vim -d a b` | diff interactif |

```vim
" ~/.vimrc minimal de serveur
syntax on
set number hlsearch incsearch ignorecase smartcase
set expandtab tabstop=2 shiftwidth=2
set list listchars=tab:»·,trail:·
set undofile undodir=~/.vim/undo//
```

### tar et compression

| Commande | Effet |
|---|---|
| `tar -czf x.tgz -C /srv factura` | crée, chemins relatifs à `/srv` |
| `tar -xzf x.tgz -C /dest` | extrait dans `/dest` |
| `tar -tzf x.tgz` | liste |
| `tar -xzf x.tgz --strip-components=1` | retire un niveau de chemin |
| `tar -czf x.tgz --exclude='*.log' --exclude=cache rep` | exclusions |
| `tar -cJf x.txz rep` / `--zstd` | xz / zstd |
| `tar -cpf - rep \| ssh h 'tar -xpf - -C /srv'` | transfert direct |
| `tar --one-file-system -czf x.tgz /` | ne franchit pas les montages |
| `tar -xzf x.tgz chemin/precis` | extrait un seul membre |
| `tar -rf x.tar nouveau` | ajoute à une archive non compressée |
| `gzip -9 f` / `gunzip f.gz` / `gzip -dc f.gz` | compresse, décompresse, flux |
| `zstd -19 -T0 f` / `zstd -dc f.zst` | zstd multi-thread |
| `xz -T0 f` / `unxz f.xz` | xz |
| `zcat`, `zless`, `zgrep` | lecture directe |
| `zip -r x.zip rep` / `unzip -l x.zip` / `unzip x.zip -d rep` | zip |
| `gzip -t f.gz` / `zstd -t f.zst` | teste l'intégrité |
| `pg_dump factura \| zstd -19 -T0 > dump.sql.zst` | rien en clair sur disque |

### rsync, scp, sftp, intégrité

| Commande | Effet |
|---|---|
| `rsync -aP src/ dest/` | archive + progression, reprise |
| `rsync -avz --delete src/ h:/dest/` | miroir (efface à la destination) |
| `rsync -an --delete src/ dest/` | simulation, à faire avant `--delete` |
| `rsync -a --exclude='*.log' --exclude=.git src/ dest/` | exclusions |
| `rsync -a --link-dest=../hier src/ aujourdhui/` | incrémental à liens durs |
| `rsync -a -e 'ssh -p 2222' src/ h:/dest/` | port SSH |
| `rsync -a --bwlimit=5000 src/ h:/dest/` | limite en Kio/s |
| `rsync -a --rsync-path='sudo rsync' src/ h:/etc/` | root à distance |
| `rsync -a --info=progress2 src/ dest/` | progression globale |
| `scp -r rep h:/dest/` / `scp h:/f .` | copie ponctuelle |
| `sftp h` puis `get`, `put`, `ls` | interactif |
| `split -b 500M a.tar.zst a.part.` / `cat a.part.* > a.tar.zst` | découpe |
| `sha256sum f > f.sha256` / `sha256sum -c f.sha256` | empreinte, vérification |
| `md5sum f` | héritage, jamais pour la sécurité |

`rsync -a /src /dst/` copie le répertoire ; `rsync -a /src/ /dst/` copie
son contenu. Le slash final change tout.

::: piege
* `Ctrl-V ... I # Esc` : sans le `Esc` final, une seule ligne est modifiée.
* Collage souris sans `:set paste` : indentation en escalier.
* `tar -czf x.tgz /srv/factura` stocke `srv/factura/...` : utilise `-C`.
* `tar -xf` d'une archive inconnue peut écraser : `-t` d'abord.
* `rsync --delete` sans `-n` avant : la destination est nettoyée sans retour.
* `scp` ne reprend pas un transfert coupé : `rsync -aP`.
* `.fichier.swp` restant : `vim -r`, puis supprime le swap.
:::

::: astuce
* `:%s/\s\+$//e` — supprime les espaces en fin de ligne.
* `rsync -aP --delete -n src/ dest/ | head` — voir ce qui va bouger.
* `tar -cf - -C /srv factura | ssh lab-db 'tar -xf - -C /srv'` — sans fichier.
:::

---

## 07 · Scripting Bash

### Squelette

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
usage() { echo "usage: ${0##*/} -e ENV [-n]" >&2; exit 2; }
TRAVAIL=$(mktemp -d); trap 'rm -rf -- "$TRAVAIL"' EXIT
log() { printf '%(%F %T)T %s\n' -1 "$*" >&2; }
while getopts ':e:nh' o; do case $o in
  e) ENV=$OPTARG ;; n) DRY=1 ;; *) usage ;; esac; done
shift $((OPTIND-1)); : "${ENV:?-e obligatoire}"
```

### Variables et substitutions

| Commande | Effet |
|---|---|
| `"$@"` / `"$*"` | un mot par argument / un seul mot |
| `$#` / `$?` / `$$` / `$!` | nombre d'args, code, PID shell, PID dernier bg |
| `${v:-def}` / `${v:=def}` | défaut sans / avec affectation |
| `${v:?msg}` | sort si vide, avec message |
| `${v:+x}` | `x` si non vide |
| `${#v}` / `${#arr[@]}` | longueur / nombre d'éléments |
| `${v##*/}` / `${v%/*}` | basename / dirname |
| `${v%.*}` / `${v##*.}` | sans extension / extension |
| `${v/a/b}` / `${v//a/b}` | remplace 1re / toutes |
| `${v:3:5}` | sous-chaîne |
| `${v^^}` / `${v,,}` | majuscules / minuscules |
| `${!prefixe@}` | variables commençant par |
| `arr=(a b c)` ; `arr+=(d)` ; `"${arr[@]}"` | tableau |
| `declare -A m ; m[k]=v ; "${!m[@]}"` | associatif, clés |
| `read -r -a champs <<< "$ligne"` | découpe en tableau |
| `mapfile -t lignes < f` | fichier en tableau |
| `printf -v var '%05d' 42` | formate dans une variable |
| `$(( a * b ))` / `(( i++ ))` | arithmétique |
| `local v ; v=$(cmd)` | déclarer puis affecter (garde `$?`) |

### Tests

| Commande | Effet |
|---|---|
| `[[ $n == web-* ]]` | motif glob |
| `[[ $ip =~ ^10\.10\.10\.[0-9]+$ ]]` | regex, `${BASH_REMATCH[1]}` |
| `[[ -z $v ]]` / `[[ -n $v ]]` | vide / non vide |
| `[[ -f f ]]` `-d` `-e` `-s` `-r` `-w` `-x` `-L` | fichier, rép, existe, non vide, droits, lien |
| `[[ a -nt b ]]` | a plus récent que b |
| `[[ $a == "$b" ]]` / `[[ $a != "$b" ]]` | chaînes |
| `(( n > 10 && n < 100 ))` | entiers |
| `[ "$a" = "$b" ]` / `[ "$n" -eq 3 ]` | POSIX, quoting obligatoire |
| `if cmd; then` | le code de retour est le test |
| `cmd && ok \|\| ko` | attention : `ko` tourne aussi si `ok` échoue |
| `case $1 in -h\|--help) ;; *) ;; esac` | aiguillage |

### Boucles et lecture

| Commande | Effet |
|---|---|
| `for f in "$REP"/*.log; do` | glob, jamais `$(ls)` |
| `for ((i=0;i<10;i++)); do` | style C |
| `for i in {1..5}; do` | séquence |
| `while IFS= read -r ligne; do ...; done < f` | ligne à ligne |
| `while IFS=: read -r u _ uid _; do` | champs |
| `while read -r -d '' f; do ...; done < <(find . -print0)` | noms sûrs |
| `done < <(cmd)` plutôt que `cmd \| while` | garde les variables |
| `until cmd; do sleep 1; done` | attend |
| `break` / `continue` / `break 2` | contrôle |
| `select opt in a b; do ...; done` | menu |

### Fonctions, robustesse, verrous

| Commande | Effet |
|---|---|
| `f() { local x=$1; ...; return 0; }` | résultat sur stdout, code par `return` |
| `res=$(f arg) \|\| rc=$?` | capture et code |
| `set -e` / `set -u` / `set -o pipefail` | sortie sur erreur, var non définie, pipe |
| `set -x` / `set +x` | trace |
| `trap 'rm -rf -- "$T"' EXIT` | nettoyage garanti |
| `trap 'echo "ligne $LINENO: $BASH_COMMAND" >&2' ERR` | localise l'erreur |
| `trap 'exit 130' INT` | Ctrl-C |
| `exec 9>/run/lock/x.lock; flock -n 9 \|\| exit 9` | une seule instance |
| `flock -n /run/lock/x.lock cmd` | idem en une ligne |
| `mktemp` / `mktemp -d` | fichier / répertoire temporaire sûr |
| `timeout 30 cmd` | tue après 30 s |
| `cmd \|\| true` | tolère un échec sous `set -e` |
| `: "${VAR:?}"` | exige une variable |
| `exit 0..255` | 1 générique, 2 usage, 126/127, 128+n signal |

### Débogage et qualité

| Commande | Effet |
|---|---|
| `bash -n s.sh` | syntaxe seule |
| `bash -x s.sh` | trace complète |
| `PS4='+ ${BASH_SOURCE##*/}:$LINENO: '` | trace lisible |
| `shellcheck -x s.sh` | analyse statique (`apt install shellcheck`) |
| `shfmt -i 2 -w s.sh` | formatage |
| `bash -c 'set -u; echo $x'` | test rapide d'un comportement |
| `getopts` / `getopt` | options courtes / longues |
| `caller` / `${FUNCNAME[@]}` | pile d'appels |

::: piege
* `$var` non quoté : découpage et globbing. `"$var"` partout.
* `for f in $(ls)` casse sur les espaces : glob ou `find -print0`.
* `cd $rep` sans test : la suite s'exécute ailleurs. `cd -- "$rep" || exit`.
* `rm -rf "$dir/"` avec `dir` vide = `rm -rf /`. `${dir:?}`.
* `local v=$(cmd)` masque le code de `cmd`.
* `set -e` est ignoré dans `if`, `&&`, `||`, et dans les fonctions en condition.
* `cmd | while read` : les variables modifiées sont perdues (sous-shell).
:::

::: astuce
* `set -euo pipefail` + `trap ... EXIT` + `mktemp` : les trois lignes de base.
* `shellcheck s.sh` avant tout commit, non négociable.
* `while IFS= read -r l; do ...; done < f` — la seule lecture correcte.
:::

---

## 08 · Processus et systemd

### Observer

| Commande | Effet |
|---|---|
| `ps aux` / `ps -ef` | tous, format BSD / UNIX |
| `ps -eo pid,ppid,user,stat,ni,rss,etimes,args --sort=-rss \| head` | top RAM |
| `ps -eo pid,stat,wchan:20,args \| awk '$2 ~ /D/'` | processus bloqués en E/S |
| `ps -o pid,ppid,stat,args -p 1234` | un processus |
| `ps -u factura -o pid,args` | par utilisateur |
| `pstree -paus 1234` | ascendance |
| `pgrep -a -f 'factura-api'` | recherche par ligne complète |
| `top -o %MEM` / `htop` | interactif |
| `top -b -n1 \| head -20` | instantané scriptable |
| `cat /proc/1234/status` | état, RSS, threads |
| `cat /proc/1234/limits` | limites effectives |
| `ls /proc/1234/fd \| wc -l` | descripteurs ouverts |
| `cat /proc/1234/oom_score_adj` | priorité OOM (-1000 = jamais) |
| `lsof -p 1234` | fichiers et sockets ouverts |

États `ps` : `R` tourne, `S` dort, `D` E/S ininterruptible (ne se tue pas),
`Z` zombie (tuer le père), `T` stoppé.

### Signaux et jobs

| Commande | Effet |
|---|---|
| `kill 1234` / `kill -TERM 1234` | demande d'arrêt (15) |
| `kill -HUP 1234` | recharge la conf (convention) |
| `kill -9 1234` / `kill -KILL` | dernier recours |
| `kill -STOP` / `kill -CONT` | gèle / reprend |
| `kill -l` | liste des signaux |
| `pkill -f 'factura-api'` / `pkill -u factura` | par motif / utilisateur |
| `killall nom` | par nom exact de binaire |
| `kill %1` | par job |
| `cmd &` / `jobs -l` / `fg %1` / `bg %1` | arrière-plan |
| `nohup cmd &` | survit au HUP, sortie dans `nohup.out` |
| `setsid cmd` / `disown -h %1` | nouvelle session / détache |
| `tmux new -s x` / `Ctrl-b d` / `tmux attach -t x` | multiplexeur |
| `systemd-run --unit=migration /chemin/script.sh` | service transitoire |
| `nice -n 10 cmd` / `renice -n 5 -p 1234` | priorité (-20 à 19) |
| `ionice -c3 -p 1234` | classe E/S idle |
| `ulimit -n` / `ulimit -Sn 4096` | limites |
| `wait $!` | attend un job |

### systemctl

| Commande | Effet |
|---|---|
| `systemctl status nginx` | état, PID, dernières lignes |
| `systemctl start\|stop\|restart\|reload nginx` | actions |
| `systemctl reload-or-restart nginx` | reload si supporté |
| `systemctl enable --now nginx` / `disable --now` | boot + maintenant |
| `systemctl is-active nginx` / `is-enabled` / `is-failed` | scriptable |
| `systemctl mask nginx` / `unmask` | rend le start impossible |
| `systemctl cat nginx` | unité + drop-ins appliqués |
| `systemctl edit nginx` | crée `override.conf` |
| `systemctl edit --full nginx` | copie complète dans `/etc/systemd/system` |
| `systemctl revert nginx` | supprime les overrides |
| `systemctl show -p MainPID,Restart,NRestarts nginx` | valeurs effectives |
| `systemctl daemon-reload` | après édition manuelle |
| `systemctl list-units --type=service --state=failed` | en échec |
| `systemctl --failed` | idem, court |
| `systemctl reset-failed nginx` | efface l'état failed |
| `systemctl list-unit-files --state=enabled` | activés au boot |
| `systemctl list-dependencies --reverse nginx` | qui dépend de |
| `systemctl list-timers` / `list-sockets` | timers, sockets |
| `systemctl kill -s HUP nginx` | signal au cgroup |
| `systemctl set-property nginx MemoryMax=512M` | limite à chaud |
| `systemctl isolate rescue.target` | mode secours |
| `systemctl get-default` / `set-default multi-user.target` | cible par défaut |
| `systemd-analyze verify x.service` | valide une unité |
| `systemd-analyze security x.service` | score de durcissement |
| `systemd-analyze blame` / `critical-chain` | temps de boot |
| `systemd-cgls` / `systemd-cgtop` | arbre et top des cgroups |
| `journalctl -u nginx -n 50 --no-pager` | journal de l'unité |
| `systemctl --user status` | unités de l'utilisateur |
| `loginctl enable-linger mathieu` | unités user sans session |

### Unité minimale

```ini
# /etc/systemd/system/factura-api.service
[Unit]
Description=API Factura
After=network-online.target postgresql.service
Wants=network-online.target
[Service]
Type=exec
User=factura
WorkingDirectory=/opt/factura
EnvironmentFile=-/etc/factura/env
ExecStart=/opt/factura/bin/api --port 8099
Restart=on-failure
RestartSec=5
ProtectSystem=strict
ReadWritePaths=/var/lib/factura
[Install]
WantedBy=multi-user.target
```

| Directive | Effet |
|---|---|
| `Wants=` / `Requires=` / `BindsTo=` | souhaite / exige / suit |
| `After=` / `Before=` | ordre seulement |
| `Type=simple\|exec\|forking\|oneshot\|notify` | quand « démarré » |
| `RemainAfterExit=yes` | oneshot considéré actif |
| `Restart=on-failure\|always` + `RestartSec=` | relance |
| `StartLimitIntervalSec=` / `StartLimitBurst=` | anti-boucle |
| `TimeoutStartSec=` / `TimeoutStopSec=` | délais |
| `ExecReload=/bin/kill -HUP $MAINPID` | reload |
| `RuntimeDirectory=factura` | crée `/run/factura` |
| `StateDirectory=` / `LogsDirectory=` | `/var/lib/x`, `/var/log/x` |
| `MemoryMax=` / `CPUQuota=50%` | limites cgroup |
| `NoNewPrivileges=yes` / `PrivateTmp=yes` | durcissement |
| `LimitNOFILE=65536` | ulimit du service |

Codes de `systemctl status` : `203/EXEC` binaire absent, `200/CHDIR`
répertoire absent, `217/USER` utilisateur inconnu, `226/NAMESPACE`
isolation impossible.

::: piege
* `Requires=` sans `After=` lance les deux en parallèle.
* `Type=simple` ne détecte même pas un binaire absent : `Type=exec`.
* Édition dans `/usr/lib/systemd/system` : écrasée à la mise à jour.
  Toujours `systemctl edit` ou `/etc/systemd/system/`.
* Oublier `daemon-reload` : l'ancienne unité tourne encore.
* `kill -9` d'abord : pas de ménage, fichiers de verrou, données perdues.
* `start request repeated too quickly` = `StartLimitBurst`, pas l'appli.
* Un `D` ne se tue pas ; le problème est le stockage, pas le processus.
:::

::: astuce
* `systemctl cat nginx` — la vérité sur ce qui est appliqué.
* `journalctl -u x -b --no-pager | tail -50` — le crash en clair.
* `systemd-run --unit=long -p Type=oneshot ./script.sh` — jamais nohup.
:::

---

## 09 · Paquets

### apt (clavier) et apt-get (scripts)

| Commande | Effet |
|---|---|
| `apt update` | rafraîchit les index, n'installe rien |
| `apt upgrade` | met à jour sans jamais supprimer |
| `apt full-upgrade` | met à jour, supprime si nécessaire |
| `apt install nginx` / `dnf install nginx` | installe |
| `apt install nginx=1.24.0-2ubuntu7` | version précise |
| `apt install -t noble-backports pkg` | depuis une suite |
| `apt install --no-install-recommends pkg` | sans les recommandés |
| `apt remove pkg` / `apt purge pkg` | retire / retire aussi la conf |
| `apt autoremove --purge` | dépendances orphelines |
| `apt-mark hold pkg` / `unhold` / `showhold` | gèle une version |
| `apt-mark manual pkg` / `auto` | protège de l'autoremove |
| `apt list --upgradable` / `--installed` | listes |
| `apt show pkg` / `apt policy pkg` | fiche / versions et priorités |
| `apt search motif` / `apt-cache search` | recherche |
| `apt-cache depends pkg` / `rdepends pkg` | dépendances / inverses |
| `apt download pkg` | récupère le `.deb` |
| `apt-get -s install pkg` | simulation |
| `apt-get install -y -o Dpkg::Options::=--force-confold pkg` | garde ta conf |
| `DEBIAN_FRONTEND=noninteractive apt-get -y upgrade` | sans question |
| `apt-get clean` / `autoclean` | vide `/var/cache/apt/archives` |
| `apt changelog pkg` | journal des versions |
| `apt-file search /usr/bin/x` | quel paquet fournit (non installé) |
| `unattended-upgrades --dry-run -d` | teste les MAJ automatiques |
| `cat /var/log/apt/history.log` | ce qui a été installé quand |

### dpkg

| Commande | Effet |
|---|---|
| `dpkg -i f.deb` | installe sans résoudre les dépendances |
| `apt install ./f.deb` | installe **et** résout |
| `dpkg -l 'nginx*'` | liste avec état (`ii`, `rc`, `iU`, `iF`, `hi`) |
| `dpkg -L pkg` / `rpm -ql pkg` | fichiers livrés |
| `dpkg -S /chemin` / `rpm -qf /chemin` | quel paquet installé fournit |
| `dpkg -s pkg` / `rpm -qi pkg` | fiche, conffiles |
| `dpkg -V pkg` / `rpm -V pkg` | fichiers modifiés depuis l'installation |
| `dpkg --configure -a` | reprend une installation interrompue |
| `dpkg -r pkg` / `dpkg -P pkg` | retire / purge |
| `dpkg -c f.deb` / `dpkg -I f.deb` | contenu / métadonnées d'un `.deb` |
| `dpkg-query -W -f '${Package} ${Version}\n'` | scriptable |
| `dpkg-reconfigure tzdata` | rejoue la configuration |
| `dpkg --get-selections > pk.txt` / `--set-selections` | export / import |
| `find /etc -name '*.dpkg-*' -o -name '*.ucf-*'` | confs en attente |

### Sources, clés, épinglage

```ini
# /etc/apt/sources.list.d/docker.sources
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Signed-By: /etc/apt/keyrings/docker.gpg
```

| Commande | Effet |
|---|---|
| `install -m 0755 -d /etc/apt/keyrings` | répertoire des clés |
| `curl -fsSL URL/gpg \| gpg --dearmor -o /etc/apt/keyrings/x.gpg` | clé |
| `apt-cache policy` | priorités par dépôt |
| `apt-cache policy nginx` | versions candidates |
| `/etc/apt/preferences.d/50-x.pref` | `Package:`, `Pin:`, `Pin-Priority:` |
| `Pin-Priority: 1001` | autorise la rétrogradation |
| `Pin-Priority: -1` | jamais installé |
| `add-apt-repository ppa:x/y` | PPA (Ubuntu) |
| `apt-add-repository --remove ppa:x/y` | retire |

Priorités : `100` installé / backports, `500` dépôt, `990` cible `-t`,
`>1000` rétrograde. `apt-key` est supprimé : `Signed-By` uniquement.

### RHEL / Rocky

| Commande | Effet |
|---|---|
| `dnf check-update` / `dnf upgrade` | vérifie / met à jour |
| `dnf install pkg` / `remove` / `autoremove` | gestion |
| `dnf info pkg` / `dnf provides /usr/bin/x` | fiche / quel paquet fournit |
| `dnf repolist` / `dnf config-manager --set-enabled crb` | dépôts |
| `dnf history` / `history info 42` / `history undo 42` | transactions |
| `dnf versionlock add pkg` | gel (`python3-dnf-plugin-versionlock`) |
| `dnf module list nodejs` / `module enable nodejs:20` / `module reset` | flux |
| `dnf downgrade pkg` | rétrograde |
| `dnf clean all` / `dnf makecache` | cache |
| `dnf install epel-release` | dépôt EPEL |
| `rpm -qa \| sort` / `rpm -qa --last` | inventaire / par date |
| `rpm -q --changelog pkg` | changelog |
| `rpm2cpio f.rpm \| cpio -idmv` | extrait sans installer |

### Langages et alternatives

| Commande | Effet |
|---|---|
| `update-alternatives --display editor` | état |
| `update-alternatives --config editor` | choix interactif |
| `update-alternatives --set editor /usr/bin/vim.basic` | choix direct |
| `python3 -m venv .venv && . .venv/bin/activate` | environnement isolé |
| `pipx install ansible-core` | outil CLI Python isolé |
| `apt install python3-requests` | bibliothèque système |
| `snap list` / `snap refresh` / `snap remove` | snaps |
| `needrestart` / `checkrestart` | services à redémarrer après MAJ |
| `ls /var/run/reboot-required*` | reboot demandé (noyau) |

::: piege
* `dpkg was interrupted` : `dpkg --configure -a`, puis `apt -f install`.
* Répondre `Y` à un conffile écrase ta conf (elle part en `.dpkg-old`).
* Une clé dans `/etc/apt/trusted.gpg.d/` authentifie tous les dépôts.
* `pip install` en root casse les paquets système (`externally-managed`).
* `apt upgrade` laisse un paquet `kept back` : c'est voulu, pas une erreur.
* Un flux dnf activé masque les autres : `No match for argument`.
:::

::: astuce
* `apt policy pkg` — d'où viendra la version, et pourquoi.
* `dpkg -S $(command -v x)` — quel paquet a livré ce binaire.
* `dnf history undo last` — l'annulation que Debian n'a pas.
:::

---

## 10 · Stockage et LVM

### Identifier

| Commande | Effet |
|---|---|
| `lsblk -f` | arbre, FS, UUID, points de montage |
| `lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,UUID` | colonnes choisies |
| `blkid /dev/sdb1` | UUID et type |
| `ls -l /dev/disk/by-uuid/` / `by-id/` / `by-path/` | noms stables |
| `fdisk -l /dev/sdb` / `parted -l` | tables de partitions |
| `sgdisk -p /dev/sdb` | GPT détaillé |
| `cat /proc/partitions` | vu du noyau |
| `smartctl -a /dev/sda` | santé (`apt install smartmontools`) |
| `nvme list` / `nvme smart-log /dev/nvme0` | NVMe |
| `udevadm info -q all -n /dev/sdb` | propriétés udev |
| `echo 1 \| sudo tee /sys/class/block/sdb/device/rescan` | disque agrandi |
| `echo '- - -' \| sudo tee /sys/class/scsi_host/host0/scan` | nouveau disque |

### Partitionner et formater

| Commande | Effet |
|---|---|
| `parted -s /dev/sdb mklabel gpt` | table GPT |
| `parted -s -a optimal /dev/sdb mkpart p 1MiB 100%` | une partition alignée |
| `parted -s /dev/sdb set 1 lvm on` | drapeau LVM |
| `sgdisk -n 1:0:0 -t 1:8e00 /dev/sdc` | idem en une ligne |
| `sgdisk -Z /dev/sdb` / `wipefs -a /dev/sdb` | efface les signatures |
| `partprobe /dev/sdb` | relit la table |
| `growpart /dev/sda 2` | agrandit la partition 2 (cloud-utils) |
| `mkfs.ext4 -L donnees -m 1 /dev/sdb1` | ext4, 1 % réservé |
| `mkfs.xfs -L pgdata /dev/sdc1` | XFS |
| `mkfs.ext4 -F` / `mkfs.xfs -f` | force si signature présente |
| `tune2fs -l /dev/sdb1` | paramètres ext4 |
| `tune2fs -m 1 -c -1 -i 0 /dev/sdb1` | réserve, compteurs de fsck |
| `tune2fs -L nouveau /dev/sdb1` / `xfs_admin -L x /dev/sdc1` | étiquette |
| `xfs_info /point` | paramètres XFS (sur le montage) |
| `e2fsck -f /dev/sdb1` / `xfs_repair /dev/sdc1` | réparation, démonté |
| `resize2fs /dev/vg/lv` / `xfs_growfs /point` | agrandit le FS |

Types GPT : `8300` Linux, `8e00` LVM, `8200` swap, `8309` LUKS, `fd00` RAID.

### Monter

| Commande | Effet |
|---|---|
| `mount -o noatime /dev/sdb1 /srv/data` | monte |
| `mount -o remount,ro /srv/data` | passe en lecture seule |
| `mount -a` | monte tout `fstab` |
| `umount /srv/data` / `umount -l` | démonte / paresseux |
| `findmnt /srv/data` / `findmnt --verify` | état / valide fstab |
| `fuser -vm /srv/data` / `lsof +f -- /srv/data` | qui bloque |
| `fuser -km /srv/data` | tue les coupables |
| `systemctl daemon-reload` | après édition de fstab |
| `systemctl list-units -t mount` | montages vus par systemd |
| `mount -t nfs 10.10.10.12:/export /mnt` | NFS |
| `mount -o loop image.iso /mnt` | image |
| `mount -t tmpfs -o size=512m tmpfs /mnt/ram` | tmpfs |

```text
# /etc/fstab
UUID=8f3c-...  /srv/factura/db  ext4  defaults,noatime,nofail  0 2
/dev/vg_data/lv_sauv  /srv/sauv  xfs   defaults,nofail        0 0
/swapfile             none       swap  sw                      0 0
10.10.10.12:/export   /mnt/nfs   nfs   _netdev,nofail          0 0
```

Options : `nodev,nosuid,noexec` durcissement, `nofail` ne bloque pas le
boot, `x-systemd.automount` à la demande, `_netdev` attend le réseau.

### LVM

| Commande | Effet |
|---|---|
| `pvcreate /dev/sdb1 /dev/sdc1` | volumes physiques |
| `vgcreate vg_data /dev/sdb1` | groupe |
| `lvcreate -L 3G -n lv_pgdata vg_data` | volume logique, taille |
| `lvcreate -l 100%FREE -n lv_sauv vg_data` | tout le reste |
| `vgextend vg_data /dev/sdc1` | ajoute un disque |
| `lvextend -L +2G -r /dev/vg_data/lv_pgdata` | agrandit LV **et** FS |
| `lvextend -l +100%FREE -r /dev/vg_data/lv_pgdata` | tout le libre |
| `pvresize /dev/sdb1` | après agrandissement de la partition |
| `pvmove /dev/sdb1` | vide un PV à chaud |
| `vgreduce vg_data /dev/sdb1 && pvremove /dev/sdb1` | retire un disque |
| `lvremove /dev/vg_data/lv_x` / `vgremove` / `pvremove` | suppression |
| `pvs` / `vgs` / `lvs` / `lvs -o +devices` | état |
| `pvdisplay` / `vgdisplay` / `lvdisplay` | détail |
| `lvrename vg_data ancien nouveau` | renomme |
| `vgchange -ay` / `vgscan` / `pvscan` | active, redécouvre |
| `lvcreate -s -L 1G -n snap_pg /dev/vg_data/lv_pgdata` | snapshot |
| `mount -o ro,nouuid /dev/vg_data/snap_pg /mnt` | monte (XFS: `nouuid`) |
| `lvconvert --merge /dev/vg_data/snap_pg` | restaure l'origine |
| `lvs -o lv_name,attr,origin,data_percent` | remplissage des snapshots |
| `lvcreate -L 10G -T vg_data/pool` | thin pool |
| `lvcreate -V 20G -T vg_data/pool -n lv_thin` | volume thin |
| `vgcfgbackup` / `vgcfgrestore -l vg_data` | métadonnées |

Réduire ext4 : démonter, `e2fsck -f`, `resize2fs` à la taille cible, puis
`lvreduce -L` à la même taille (`lvreduce -r` enchaîne). XFS ne se réduit pas.

### RAID, swap, chiffrement, performance

| Commande | Effet |
|---|---|
| `mdadm --create /dev/md0 -l 1 -n 2 /dev/sdb1 /dev/sdc1` | RAID 1 |
| `cat /proc/mdstat` | `[UU]` sain, `[U_]` dégradé |
| `mdadm --detail /dev/md0` | détail |
| `mdadm --detail --scan >> /etc/mdadm/mdadm.conf` | persistance |
| `update-initramfs -u` / `dracut -f` | assemblage au boot |
| `mdadm /dev/md0 --fail /dev/sdb1 --remove /dev/sdb1` | retire un disque |
| `mdadm /dev/md0 --add /dev/sdd1` | remplace |
| `fallocate -l 2G /swapfile && chmod 600 /swapfile` | fichier de swap |
| `mkswap /swapfile && swapon /swapfile` | active |
| `swapon --show` / `swapoff -a` | état / désactive |
| `sysctl vm.swappiness=10` | agressivité du swap |
| `cryptsetup luksFormat /dev/sdc1` / `luksOpen /dev/sdc1 secret` | LUKS |
| `cryptsetup luksClose secret` / `/etc/crypttab` | ferme / persistance |
| `iostat -xz 2` | `await`, `%util`, IOPS |
| `dd if=/dev/zero of=/srv/t bs=1M count=1024 oflag=direct` | débit séquentiel |
| `fio --name=rr --rw=randread --bs=4k --direct=1 --size=1G --runtime=30` | IOPS |
| `fstrim -av` / `systemctl enable fstrim.timer` | TRIM SSD |
| `hdparm -tT /dev/sda` | lecture brute |

::: piege
* `/dev/sdX` dans `fstab` : l'ordre change au boot. `UUID=` ou `/dev/vg/lv`.
* `fstab` sans `nofail` sur un disque secondaire = boot en mode secours.
* `lvextend -l 100%FREE` échoue ; c'est `+100%FREE`.
* `lvreduce` avant `resize2fs` coupe la fin des données.
* Snapshot LVM plein = invalide, l'origine continue sans lui.
* `e2fsck` sur un FS monté en écriture corrompt.
* `%util` 100 % sur un NVMe ne dit rien : regarde `await`.
:::

::: astuce
* `findmnt --verify && mount -a` — avant tout reboot après `fstab`.
* `lvextend -r -L +5G /dev/vg/lv` — LV et FS en une commande.
* `lsblk -f` — la seule vue qui répond à « c'est quoi ce disque ».
:::

---

## 11 · Réseau

### iproute2

| Commande | Effet |
|---|---|
| `ip -br a` / `ip -4 -br a` | une ligne par interface |
| `ip a show dev ens18` | détail |
| `ip -br link` / `ip -s link show ens18` | état lien / compteurs, drops |
| `ip link set dev ens18 up\|down` | monte / descend |
| `ip link set dev ens18 mtu 1450` | MTU |
| `ip a add 10.10.20.10/24 dev ens18` / `ip a del` | adresse volatile |
| `ip r` / `ip -6 r` | routes |
| `ip r add 10.10.20.0/24 via 10.10.10.1` / `ip r del` | route volatile |
| `ip r add default via 10.10.10.1` | passerelle |
| `ip route get 9.9.9.9` | quelle route, quelle source |
| `ip r show table all` / `ip rule` | tables multiples |
| `ip neigh` / `ip neigh flush dev ens18` | ARP |
| `ip -c a` | couleurs |
| `ip link add link ens18 name ens18.20 type vlan id 20` | VLAN |
| `ethtool ens18` / `ethtool -S ens18` | vitesse, duplex, stats |
| `hostname -I` / `hostnamectl` | IP / nom d'hôte |
| `hostnamectl set-hostname lab-web` | renomme |

### Configuration persistante

```yaml
# /etc/netplan/01-lab.yaml   (chmod 600)
network:
  version: 2
  ethernets:
    ens18:
      addresses: [10.10.10.11/24]
      routes: [{to: default, via: 10.10.10.1}]
      nameservers:
        addresses: [10.10.10.1]
        search: [lab.local]
```

| Commande | Effet |
|---|---|
| `netplan try` | applique, rollback en 120 s sans confirmation |
| `netplan apply` | applique |
| `netplan get` / `netplan status` | conf effective |
| `nmcli con show` / `nmcli dev status` | NetworkManager (Rocky) |
| `nmcli con mod ens18 ipv4.addresses 10.10.10.13/24 ipv4.method manual` | IP |
| `nmcli con mod ens18 ipv4.gateway 10.10.10.1 ipv4.dns 10.10.10.1` | route, DNS |
| `nmcli con up ens18` | applique |
| `networkctl status` | systemd-networkd |

### DNS

| Commande | Effet |
|---|---|
| `getent hosts www.lab.local` | toute la chaîne NSS (`/etc/hosts` inclus) |
| `dig www.lab.local` / `dig +short` | DNS seul / réponse nue |
| `dig @10.10.10.1 A lab-web.lab.local` | serveur précis |
| `dig AAAA x` / `MX` / `TXT` / `NS` / `SOA` | types |
| `dig -x 10.10.10.11` | inverse |
| `dig +trace x` | depuis la racine |
| `dig +norecurse @ns x` | sans récursion |
| `resolvectl status` | vrais serveurs, domaines de recherche |
| `resolvectl query x` / `resolvectl flush-caches` | via le stub / purge |
| `resolvectl dns ens18 10.10.10.1` | serveur volatile |
| `nslookup x` / `host x` | alternatives |
| `cat /etc/nsswitch.conf \| grep hosts` | ordre `files dns` |
| `cat /etc/hosts` | résolution locale, gagne toujours |

`dig` status : `NOERROR`, `NXDOMAIN` (n'existe pas), `SERVFAIL` (amont),
`REFUSED`. Aucune ligne = timeout. `/etc/resolv.conf` = `127.0.0.53`, le stub.

### Sockets et tests

| Commande | Effet |
|---|---|
| `ss -tulpn` | en écoute, TCP+UDP, processus |
| `ss -tanp` / `ss -s` | toutes les TCP / résumé par état |
| `ss -t state established` / `state time-wait` | par état |
| `ss -tn 'dport = :443'` / `ss -tp dst 10.10.10.12` | filtres |
| `ss -K dst 10.10.10.99` | ferme des connexions |
| `lsof -i :8099` / `lsof -i -P -n` | qui ouvre ce port / tout |
| `ping -c 3 10.10.10.11` / `ping -I 10.10.20.10 x` | ICMP, source |
| `ping -M do -s 1472 -c 2 x` | test MTU sans fragmentation |
| `traceroute -n x` / `-I` / `-T -p 443` | UDP / ICMP / TCP |
| `mtr -rwc 20 9.9.9.9` | rapport traceroute + pertes |
| `nc -zv 10.10.10.11 80` | port ouvert ? refusé / timeout |
| `nc -zvu 10.10.10.1 53` | UDP |
| `nc -l 9000` / `echo x \| nc h 9000` | serveur / client de test |
| `curl -sS -o /dev/null -w '%{http_code} %{time_total}\n' URL` | code et temps |
| `curl -I URL` / `curl -v URL` / `curl -4 URL` | en-têtes / verbeux / IPv4 |
| `curl --resolve www.lab.local:443:10.10.10.11 https://www.lab.local/` | vhost |
| `curl -H 'Host: app.lab.local' http://10.10.10.11/` | Host forcé |
| `curl -k` / `curl --cacert ca.crt` | TLS non vérifié / CA |
| `wget -qO- URL` | alternative |
| `arping -I ens18 10.10.10.11` | ARP direct |
| `nmap -sT -p 1-1024 10.10.10.11` | scan (sur ton lab) |
| `iperf3 -s` / `iperf3 -c 10.10.10.11` | débit |

Codes `curl` : 6 non résolu, 7 connexion refusée, 28 timeout, 35 TLS,
60 certificat non vérifiable.

### Capture

| Commande | Effet |
|---|---|
| `tcpdump -i ens18 -nn -c 20 'host 10.10.10.11 and tcp port 80'` | de base |
| `tcpdump -i any -nn port 53` | DNS |
| `tcpdump -i ens18 -nn 'tcp[tcpflags] & tcp-syn != 0'` | SYN seuls |
| `tcpdump -i ens18 -nn icmp` | ICMP |
| `tcpdump -i ens18 -w f.pcap` / `tcpdump -r f.pcap` | écrit / relit |
| `tcpdump -i ens18 -nn -A port 80` | payload ASCII |
| `tcpdump -i ens18 -nn 'net 10.10.10.0/24 and not port 22'` | exclut SSH |
| `tshark -i ens18 -Y 'http.request'` | Wireshark CLI |

Flags : `[S]` SYN, `[S.]` SYN-ACK, `[.]` ACK, `[P.]` données, `[F.]` FIN,
`[R]` RESET.

### sysctl réseau

| Commande | Effet |
|---|---|
| `sysctl net.ipv4.ip_forward` / `sysctl -w ...=1` | lit / écrit (volatile) |
| `/etc/sysctl.d/90-x.conf` + `sysctl --system` | persistant |
| `net.core.somaxconn=4096` | file d'accept |
| `net.ipv4.ip_local_port_range="32768 60999"` | ports éphémères |
| `net.ipv4.tcp_syncookies=1` | anti SYN flood |
| `net.ipv4.ip_unprivileged_port_start=80` | ports bas sans root |
| `net.ipv6.conf.all.disable_ipv6=1` | dernier recours, pas un réflexe |

::: piege
* `ip a add` / `ip r add` ne survivent pas au reboot : netplan / nmcli.
* `netplan apply` par SSH sur une erreur = session perdue : `netplan try`.
* `127.0.0.1:443` n'est pas `0.0.0.0:443` : le service n'écoute pas dehors.
* Deux routes par défaut à la même métrique : comportement aléatoire.
* AAAA avant A : `curl` échoue en v6 alors que v4 marche. `curl -4`.
* Connexion qui s'établit puis gèle sur du volume : MTU / PMTUD filtré.
* `dig` ignore `/etc/hosts` ; `getent hosts` non.
:::

::: astuce
* `ss -tulpn | grep :443` — qui écoute et sur quelle adresse.
* `ip route get 9.9.9.9` — la route et l'IP source, en une ligne.
* `curl -sS -o /dev/null -w '%{http_code}\n' URL` — le smoke test universel.
:::

---

## 12 · SSH

### Client et clés

| Commande | Effet |
|---|---|
| `ssh-keygen -t ed25519 -C "mathieu@pc"` | paire moderne |
| `ssh-keygen -t rsa -b 4096 -a 100` | RSA si ed25519 impossible |
| `ssh-keygen -l -f cle.pub` | empreinte SHA256 |
| `ssh-keygen -p -f ~/.ssh/id_ed25519` | change la passphrase |
| `ssh-keygen -y -f ~/.ssh/id_ed25519 > id.pub` | régénère la publique |
| `ssh-copy-id -i ~/.ssh/id_ed25519.pub mathieu@10.10.10.11` | dépose la clé |
| `ssh -i cle -p 2222 user@h` | clé et port explicites |
| `ssh -v` / `-vvv user@h` | diagnostic client |
| `ssh -G lab-db` | configuration effective, sans connexion |
| `ssh -o StrictHostKeyChecking=accept-new h` | accepte un hôte inconnu |
| `ssh -o BatchMode=yes h true` | jamais de prompt (scripts) |
| `ssh -o ConnectTimeout=5 h` | délai |
| `ssh -J lab-adm lab-db` | rebond (ProxyJump) |
| `ssh -t h 'sudo journalctl -u nginx'` | TTY forcé (sudo, pagers) |
| `ssh -n h uptime` | stdin fermé, obligatoire en boucle |
| `ssh h 'bash -s' < script.sh` | script local à distance |
| `ssh h 'cmd' ; echo $?` | code de la commande distante (255 = ssh) |
| `ssh -O check h` / `ssh -O exit h` | maître de multiplexage |
| `ssh-keygen -R lab-web` / `ssh-keygen -F lab-web` | supprime / cherche known_hosts |
| `ssh-keyscan -t ed25519 10.10.10.11 >> ~/.ssh/known_hosts` | pré-provisionne |
| `eval "$(ssh-agent -s)"` / `ssh-add -t 3600 cle` | agent, 1 h |
| `ssh-add -l` / `ssh-add -D` | listé / purgé |
| `sftp h` / `scp f h:/tmp/` | transferts ponctuels |
| `sshfs h:/srv /mnt/srv` / `fusermount -u /mnt/srv` | montage distant |

```text
# ~/.ssh/config
Host lab-*
  User mathieu
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ServerAliveInterval 30
  ControlMaster auto
  ControlPath ~/.ssh/cm/%C
  ControlPersist 10m
Host lab-db
  HostName 10.10.10.12
  ProxyJump lab-adm
```

Le premier mot-clé rencontré gagne : du plus précis au plus général.

### Tunnels

| Commande | Effet |
|---|---|
| `ssh -L 15432:10.10.10.12:5432 lab-adm` | port local → distant |
| `ssh -R 8080:127.0.0.1:3000 lab-ops` | port distant → local |
| `ssh -D 1080 lab-adm` | proxy SOCKS5 |
| `ssh -fN -o ExitOnForwardFailure=yes -L ... h` | arrière-plan, échec visible |
| `ssh -L 0.0.0.0:8443:10.10.10.11:443 h` | tunnel écoutant partout |
| `AllowTcpForwarding` / `GatewayPorts` (serveur) | autorisent `-L`/`-R` |

### Serveur

| Commande | Effet |
|---|---|
| `sshd -t` | valide la conf avant reload |
| `sshd -T` / `sshd -T -C user=x,host=y,addr=z` | conf effective / avec Match |
| `systemctl reload ssh` / `sshd` (Rocky) | relit sans couper |
| `journalctl -u ssh -f` / `-u sshd` | journal (cause des refus) |
| `ls /etc/ssh/sshd_config.d/` | fragments inclus en tête |
| `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` | empreinte de l'hôte |
| `rm /etc/ssh/ssh_host_* && ssh-keygen -A` | régénère les clés d'hôte (clone) |
| `chmod 700 ~/.ssh ; chmod 600 ~/.ssh/authorized_keys` | droits exigés |
| `who` / `ss -tnp \| grep :22` | sessions |

```text
# /etc/ssh/sshd_config.d/10-durci.conf
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
AllowGroups sshusers
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Clé restreinte dans `authorized_keys` :
`from="10.10.10.14",command="/opt/deploy.sh",no-pty,no-port-forwarding ssh-ed25519 AAAA...`

::: piege
* `Permission denied (publickey)` : la cause est dans `journalctl -u ssh`
  côté serveur (droits de `~`, `.ssh`, `authorized_keys`).
* `50-cloud-init.conf` contient `PasswordAuthentication yes` et gagne.
* `ForwardAgent yes` : root de la machine distante utilise ta clé.
* Tunnel sans `ExitOnForwardFailure` : port pris, tunnel absent, silence.
* `sshd -t` oublié avant reload : la conf est invalide, les nouvelles
  connexions échouent, la session courante survit — ne la ferme pas.
* Une VM clonée garde les mêmes clés d'hôte : régénère-les.
:::

::: astuce
* `ssh -G h | grep -i identityfile` — quelle clé sera tentée.
* `ssh -J lab-adm lab-db` — rebond sans agent forwarding.
* `sshd -t && systemctl reload ssh` — le réflexe qui sauve la session.
:::

---

## 13 · Journalisation et supervision

### journalctl

| Commande | Effet |
|---|---|
| `journalctl -u nginx.service -f` | une unité, en continu |
| `journalctl -u nginx -n 50 --no-pager` | 50 dernières lignes, scriptable |
| `journalctl --since -1h` / `--since yesterday` | fenêtre relative |
| `journalctl --since "2026-09-18 14:00" --until "14:30"` | fenêtre absolue |
| `journalctl -p err` / `-p 3..4` | `err` et plus grave / intervalle |
| `journalctl -b` / `-b -1` / `--list-boots` | boot courant / précédent / liste |
| `journalctl -k` | noyau seulement (= `dmesg`) |
| `journalctl _PID=1234` / `_UID=1000` / `_COMM=sshd` | champs indexés |
| `journalctl _TRANSPORT=stdout` | ce que les services écrivent sur stdout |
| `journalctl -t CRON` / `-t factura-sauv` | par étiquette syslog |
| `journalctl -g 'refused\|denied'` | filtre regex sur le message |
| `journalctl -o short-iso` / `-o cat` / `-o json` | formats |
| `journalctl -o json -u nginx \| jq -r .MESSAGE` | champ précis |
| `journalctl --disk-usage` | taille occupée |
| `journalctl --vacuum-size=200M` / `--vacuum-time=14d` | purge les archives |
| `journalctl --verify` / `--rotate` / `--flush` | intégrité / rotation / run→var |
| `journalctl -u ssh --since today -p warning` | combinaison typique |
| `logger -t appli -p local0.err "message"` | écrit dans le journal |
| `systemd-cat -t appli cmd` | stdout d'une commande dans le journal |

```ini
# /etc/systemd/journald.conf.d/10-lab.conf
[Journal]
Storage=persistent
SystemMaxUse=1G
SystemKeepFree=2G
MaxRetentionSec=30day
RateLimitIntervalSec=30s
RateLimitBurst=10000
ForwardToSyslog=yes
```

`mkdir -p /var/log/journal && systemctl restart systemd-journald` si le
journal est volatile (`Storage=auto` sans le répertoire).

### rsyslog

| Commande | Effet |
|---|---|
| `rsyslogd -N1` | valide la configuration |
| `systemctl restart rsyslog` | relit `/etc/rsyslog.conf`, `/etc/rsyslog.d/*.conf` |
| `logger -p daemon.err test` puis `tail /var/log/syslog` | test de bout en bout |
| `tail -f /var/log/auth.log` / `/var/log/messages` (Rocky) | fichiers plats |

```text
# /etc/rsyslog.d/10-factura.conf
:programname, isequal, "factura"   /var/log/factura/app.log
:programname, isequal, "factura"   stop
local0.*                            @@10.10.10.14:10514
```

`@` UDP, `@@` TCP. `daemon.err` = err et plus grave, `daemon.=err` = err
seul, `*.*;auth,authpriv.none` = tout sauf auth. `stop` court-circuite.
Réception : `module(load="imtcp") input(type="imtcp" port="10514")`.

### logrotate

| Commande | Effet |
|---|---|
| `logrotate -d /etc/logrotate.d/factura` | simulation verbeuse |
| `logrotate -f /etc/logrotate.d/factura` | force la rotation |
| `cat /var/lib/logrotate/status` | dernière rotation par fichier |
| `ls -l /etc/logrotate.d/` | doit être `0644 root:root` |
| `systemctl list-timers logrotate.timer` | déclenché par un timer, pas cron |

```text
/var/log/factura/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 factura adm
    sharedscripts
    postrotate
        systemctl kill -s HUP factura.service
    endscript
}
```

### Métriques de base

| Commande | Effet |
|---|---|
| `uptime` / `cat /proc/loadavg` | charge 1/5/15 min (R + D) |
| `free -h` | ne lire que `available` |
| `vmstat 1 5` | `r b` / `si so` / `us sy id wa st` |
| `mpstat -P ALL 1 3` | par cœur, `%steal` |
| `iostat -xz 1 3` | `await`, `%util`, `aqu-sz` par disque |
| `sar -n DEV 1 3` / `sar -q 1 3` | réseau / file d'attente CPU |
| `sar -f /var/log/sysstat/sa18 -s 09:00 -e 10:00` | historique (sysstat) |
| `pidstat 1 3` / `pidstat -d 1` | CPU / E/S par processus |
| `cat /proc/pressure/{cpu,memory,io}` | PSI : temps perdu à attendre |
| `nproc` | nombre de cœurs, à comparer à la charge |
| `dmesg -T \| tail -40` | OOM, erreurs disque, liens réseau |

::: rhel
Rocky 9 : `/var/log/messages` et `/var/log/secure` à la place de `syslog`
et `auth.log` ; `dnf install -y sysstat` puis `systemctl enable --now
sysstat`.
:::

::: piege
* `logrotate` ignore en silence un fichier de conf non `0644 root:root`.
* `copytruncate` perd les lignes écrites entre la copie et le truncate :
  préfère `create` + signal HUP quand le démon le supporte.
* `journalctl --vacuum-*` ne touche pas au fichier actif : `--rotate`
  d'abord.
* `Suppressed N messages` dans le journal : le limiteur journald frappe,
  monte `RateLimitBurst` pour le service ou fais-le moins bavard.
* `swap used` élevé sans `si/so` : rien à corriger.
:::

::: astuce
* `journalctl -p err -b --no-pager | tail -30` — les erreurs depuis le boot.
* `logger -t test -p local0.info ok && journalctl -t test -n1` — chaîne OK ?
* `vmstat 1 | awk 'NR>2 && $16>20'` — les secondes où `wa` explose.
:::

---

## 14 · Cron et timers

### crontab

| Commande | Effet |
|---|---|
| `crontab -e` / `crontab -l` / `crontab -r` | édite / liste / supprime tout |
| `crontab -u factura -l` | crontab d'un autre compte |
| `sudo ls /var/spool/cron/crontabs/` | où elles vivent (Rocky : `/var/spool/cron/`) |
| `cat /etc/crontab` / `ls /etc/cron.d/` | crontabs système, champ utilisateur |
| `run-parts --test /etc/cron.daily` | ce qui sera exécuté (pas de `.` dans le nom) |
| `journalctl -u cron -f` / `-t CRON` | exécutions (Rocky : `crond`) |
| `grep CRON /var/log/syslog \| tail` | idem, fichier plat |
| `cat /etc/cron.allow /etc/cron.deny` | qui a le droit |
| `systemctl status cron` | le démon tourne ? |
| `date` / `timedatectl` | fuseau réellement utilisé par cron |

```text
# m h dom mon dow  commande
MAILTO=""
PATH=/usr/local/bin:/usr/bin:/bin
0 2 * * *   /opt/factura/bin/sauv.sh >> /var/log/factura/sauv.log 2>&1
*/5 * * * * flock -n /run/lock/sync.lock /opt/factura/bin/sync.sh
0 9 * * 1-5 /opt/factura/bin/rapport.sh 2>&1 | logger -t rapport
@reboot     /opt/factura/bin/warmup.sh
```

| Écriture | Sens |
|---|---|
| `*/5` | 0, 5, 10… |
| `9-17/2` | 9, 11, 13, 15, 17 |
| `0 0 1,15 * 3` | le 1er, le 15 **ou** mercredi (OU, pas ET) |
| `@daily` `@hourly` `@weekly` `@monthly` `@reboot` | raccourcis |
| `\%` | le `%` doit être échappé dans une crontab |

Reproduire l'environnement de cron :

```bash
env -i PATH=/usr/bin:/bin HOME="$HOME" SHELL=/bin/sh \
  /bin/sh -c '/opt/factura/bin/sauv.sh'
```

### Timers systemd

| Commande | Effet |
|---|---|
| `systemctl list-timers --all` | prochaine et dernière exécution |
| `systemctl enable --now factura-sauv.timer` | active le **timer** |
| `systemctl start factura-sauv.service` | exécution immédiate à la main |
| `systemctl status factura-sauv.service` | dernier résultat, code de sortie |
| `journalctl -u factura-sauv.service --since today` | journal du job |
| `systemd-analyze calendar --iterations=3 "Mon..Fri 09:00"` | teste `OnCalendar` |
| `systemd-analyze calendar "*-*~01 23:00:00"` | dernier jour du mois |
| `systemd-analyze verify /etc/systemd/system/x.timer` | valide l'unité |
| `systemd-run --on-active=90 --unit=ponctuel /opt/x.sh` | `at` version systemd |
| `systemd-run --on-calendar="*-*-* 03:00" --unit=x /opt/x.sh` | timer transitoire |
| `systemctl daemon-reload` | après toute édition d'unité |
| `systemctl edit factura-sauv.service` | surcharge (drop-in) |
| `systemctl --user list-timers` | timers de l'utilisateur |

```ini
# /etc/systemd/system/factura-sauv.service
[Unit]
Description=Sauvegarde Factura
After=network-online.target
[Service]
Type=oneshot
User=factura
ExecStart=/opt/factura/bin/sauv.sh
TimeoutStartSec=30min
MemoryMax=512M
```

```ini
# /etc/systemd/system/factura-sauv.timer
[Unit]
Description=Sauvegarde Factura, chaque nuit
[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
RandomizedDelaySec=10min
[Install]
WantedBy=timers.target
```

`OnCalendar` : `Mon..Fri *-*-* 09:00:00`, `*:0/15` (toutes les 15 min),
`hourly`, `daily`, `weekly`. `OnBootSec=5min` + `OnUnitActiveSec=1h` pour un
intervalle. `AccuracySec=1s` si l'heure exacte compte (défaut 1 min).

::: piege
* `%` non échappé dans une crontab : la commande s'arrête là.
* `\` en fin de ligne : cron ne connaît pas la continuation.
* `purge-tmp.sh` dans `cron.daily` n'est jamais lancé (`run-parts`).
* `PATH` de cron = `/usr/bin:/bin` : chemins absolus ou `PATH=` en tête.
* `> /dev/null 2>&1` sur un job de prod détruit la seule trace d'échec.
* `systemctl enable x.service` au lieu de `x.timer` : rien ne se lance.
* `crontab -r` est à une touche de `crontab -e` et ne demande rien.
:::

::: astuce
* `systemd-analyze calendar --iterations=5 "..."` — avant d'écrire le timer.
* `flock -n /run/lock/x.lock cmd` — jamais deux instances.
* `systemctl list-timers --all | grep -v n/a` — les timers qui ont déjà tourné.
:::

---

## 15 · Sécurité

### ufw (Ubuntu)

| Commande | Effet |
|---|---|
| `ufw default deny incoming` / `allow outgoing` | politiques |
| `ufw allow from 10.10.10.10 to any port 22 proto tcp` | SSH depuis le bastion |
| `ufw allow 80,443/tcp` | ports multiples |
| `ufw allow 'Nginx Full'` / `ufw app list` | profils applicatifs |
| `ufw limit 22/tcp` | 6 connexions / 30 s par IP |
| `ufw status numbered` / `ufw status verbose` | règles numérotées / politiques |
| `ufw insert 1 deny from 10.0.0.0/8` | en tête |
| `ufw delete 4` / `ufw delete allow 80/tcp` | supprime |
| `ufw logging medium` / `tail -f /var/log/ufw.log` | journal |
| `ufw enable` / `ufw disable` / `ufw reset` | active / coupe / efface tout |
| `ufw --dry-run allow 443` | montre les règles iptables générées |

### nftables

| Commande | Effet |
|---|---|
| `nft list ruleset` | ce que le noyau applique (vaut pour ufw, Docker, firewalld) |
| `nft list table inet filter` | une table |
| `nft -c -f /etc/nftables.conf` | vérifie sans charger |
| `nft -f /etc/nftables.conf` | charge |
| `nft flush ruleset` | tout efface (session SSH comprise si input drop) |
| `nft add rule inet filter input tcp dport 8080 accept` | règle volatile |
| `nft -a list chain inet filter input` | avec handles |
| `nft delete rule inet filter input handle 12` | supprime par handle |
| `systemctl enable --now nftables` | persistance |
| `nft list ruleset > /etc/nftables.conf` | fige l'état courant |

```text
# /etc/nftables.conf
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    iif lo accept
    ct state established,related accept
    ip saddr 10.10.10.10 tcp dport 22 accept
    tcp dport { 80, 443 } accept
    icmp type echo-request limit rate 5/second accept
  }
}
```

### firewalld (Rocky)

| Commande | Effet |
|---|---|
| `firewall-cmd --state` / `--get-active-zones` | état / zones actives |
| `firewall-cmd --list-all` / `--zone=internal --list-all` | contenu |
| `firewall-cmd --add-service=https` | runtime seulement |
| `firewall-cmd --permanent --add-service=https && firewall-cmd --reload` | persistant |
| `firewall-cmd --permanent --add-port=8080/tcp` | port |
| `firewall-cmd --runtime-to-permanent` | fige les essais |
| `firewall-cmd --permanent --zone=internal --add-source=10.10.10.11/32` | source → zone |
| `firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=10.10.10.11 port port=5432 protocol=tcp accept'` | règle fine |
| `firewall-cmd --get-services` / `--info-service=https` | catalogue |
| `firewall-cmd --permanent --remove-service=cockpit` | retire |

### fail2ban

| Commande | Effet |
|---|---|
| `fail2ban-client status` / `status sshd` | prisons / bannis |
| `fail2ban-client set sshd unbanip 10.10.10.10` | débannit |
| `fail2ban-client set sshd banip 203.0.113.5` | bannit à la main |
| `fail2ban-regex /var/log/auth.log /etc/fail2ban/filter.d/sshd.conf` | teste un filtre |
| `fail2ban-client -t` | valide la conf |
| `tail -f /var/log/fail2ban.log` | actions |

```ini
# /etc/fail2ban/jail.local
[DEFAULT]
ignoreip = 127.0.0.1/8 10.10.10.10
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd
[sshd]
enabled = true
```

### SELinux (Rocky) et AppArmor (Ubuntu)

| Commande | Effet |
|---|---|
| `getenforce` / `sestatus` | mode |
| `setenforce 0` / `setenforce 1` | permissif / enforcing, volatile |
| `/etc/selinux/config` : `SELINUX=enforcing` | persistant |
| `ls -Z /var/www` / `ps -eZ \| grep nginx` | contextes |
| `restorecon -Rv /var/www` | réapplique le contexte attendu |
| `semanage fcontext -a -t httpd_sys_content_t "/srv/web(/.*)?"` | change l'attendu |
| `semanage port -a -t http_port_t -p tcp 8088` | port autorisé |
| `semanage port -l \| grep http` | ports connus |
| `getsebool -a \| grep httpd` / `setsebool -P httpd_can_network_connect on` | booléens |
| `ausearch -m AVC -ts recent` / `\| audit2why` | refus / explication |
| `ausearch -m AVC -ts recent \| audit2allow -M monmod` | module (à relire) |
| `aa-status` | profils AppArmor, mode |
| `aa-complain /etc/apparmor.d/usr.sbin.nginx` / `aa-enforce` | observation / actif |
| `apparmor_parser -r /etc/apparmor.d/usr.sbin.nginx` | recharge un profil |
| `journalctl -k \| grep 'apparmor="DENIED"'` | refus |
| `aa-logprof` | propose des règles à partir des refus |

### Audit, durcissement, TLS

| Commande | Effet |
|---|---|
| `ss -tulpn` | qui écoute, sur quelle adresse |
| `systemctl list-units --type=service --state=running` | ce qui tourne |
| `find / -xdev -perm -4000 -type f 2>/dev/null` | SUID |
| `awk -F: '($3==0){print $1}' /etc/passwd` | comptes UID 0 |
| `awk -F: '($2==""){print $1}' /etc/shadow` | mots de passe vides |
| `lastb \| head` / `last -n 20` | échecs / connexions |
| `sysctl --system` / `sysctl -a \| grep rp_filter` | applique / vérifie |
| `apt install unattended-upgrades` / `dnf install dnf-automatic` | MAJ auto |
| `lynis audit system` | audit rapide |
| `ausearch -k passwd` / `auditctl -w /etc/passwd -p wa -k passwd` | auditd |
| `openssl x509 -in srv.crt -noout -subject -issuer -dates` | certificat |
| `openssl x509 -in srv.crt -noout -ext subjectAltName` | SAN |
| `openssl x509 -in srv.crt -noout -checkend 2592000` | expire sous 30 j ? |
| `openssl verify -CAfile ca.crt srv.crt` | chaîne |
| `openssl s_client -connect 10.10.10.11:443 -servername app.lab.local </dev/null` | serveur |
| `openssl rsa -in srv.key -noout -modulus \| sha256sum` | clé = cert ? |
| `openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout k.pem -out c.pem -days 365 -subj /CN=app.lab.local` | auto-signé |
| `certbot --nginx -d www.example.org` | Let's Encrypt |

```ini
# /etc/sysctl.d/99-durcissement.conf
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.tcp_syncookies = 1
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
fs.protected_symlinks = 1
```

::: piege
* `ufw allow` ajouté après un `deny` large : jamais atteint (premier match).
* Docker publie ses ports avant ufw : seule `DOCKER-USER` est respectée.
* `firewall-cmd --add-port` sans `--permanent` : perdu au reboot ; avec
  `--permanent` sans `--reload` : pas actif.
* `mv` garde le contexte SELinux d'origine, `cp` prend celui de la cible.
* `setenforce 0` « pour voir » : note-le, remets `1` avant de partir.
* fail2ban sans `ignoreip` : tu te bannis en testant.
* Secret poussé dans Git puis supprimé : il reste dans l'historique, rotation.
:::

::: astuce
* `nft list ruleset` — la vérité du noyau, quel que soit le frontal.
* `ausearch -m AVC -ts recent | audit2why` — SELinux expliqué en une ligne.
* `openssl x509 -in c.pem -noout -checkend 604800 || echo RENOUVELER` — 7 j.
:::

---

## 16 · Dépannage et performance

### Les 60 premières secondes

```bash
uptime                  # tendance des 3 charges
dmesg -T | tail -40     # OOM, I/O error, link down, MCE
vmstat 1 5              # r b / si so / us sy id wa st
mpstat -P ALL 1 3       # un cœur ou tous ? %steal ?
pidstat 1 3             # qui consomme
iostat -xz 1 3          # await, %util
free -m                 # available
sar -n DEV 1 3          # débit réseau
ss -s                   # sockets, time-wait
top -b -n1 | head -20   # vue d'ensemble
```

### CPU et processus

| Commande | Effet |
|---|---|
| `top -o %CPU` / `top -o RES` / `htop` | classement CPU / mémoire |
| `ps -eo pid,ppid,stat,pcpu,pmem,etime,cmd --sort=-pcpu \| head` | top ps |
| `ps -eo pid,stat,wchan:20,cmd \| awk '$2 ~ /D/'` | processus bloqués en E/S |
| `ps -eo pid,ppid,stat,cmd \| awk '$3 ~ /Z/'` | zombies (tuer le parent) |
| `pidstat -u -p PID 1` / `pidstat -t -p PID 1` | par processus / par thread |
| `perf top` / `perf top -p PID` | où passe le CPU, coût faible |
| `perf record -g -p PID -- sleep 10 && perf report` | profil |
| `strace -p PID -f -T -e trace=network` | appels système (coûteux, bref) |
| `strace -c -p PID` | compteurs d'appels |
| `strace -o t.txt -f ./cmd` | trace un lancement |
| `ltrace -p PID` | appels de bibliothèque |
| `lsof -p PID` / `ls -l /proc/PID/fd \| wc -l` | fichiers ouverts |
| `cat /proc/PID/status \| grep -E 'State\|VmRSS\|Threads'` | état, RSS |
| `cat /proc/PID/limits` | limites réelles (nofile, nproc) |
| `cat /proc/PID/stack` | pile noyau (root) |
| `tr '\0' '\n' < /proc/PID/environ` | environnement réel |
| `gdb -p PID -batch -ex 'thread apply all bt'` | piles utilisateur |
| `nice -n 10 cmd` / `renice -n 5 -p PID` / `ionice -c3 -p PID` | priorités |
| `taskset -cp PID` / `taskset -c 0,1 cmd` | affinité CPU |
| `ulimit -n` / `prlimit --pid PID --nofile=65536:65536` | limite fd |

### Mémoire

| Commande | Effet |
|---|---|
| `free -m` | `available`, `swap used` |
| `vmstat 1` | `si`/`so` non nuls en continu = thrash |
| `dmesg -T \| grep -i -E 'oom\|killed process'` | victimes de l'OOM killer |
| `journalctl -k -g oom` | idem via le journal |
| `ps -eo pid,rss,cmd --sort=-rss \| head` | plus gros RSS |
| `smem -rk \| head` / `pmap -x PID \| tail -1` | PSS / cartographie |
| `cat /proc/PID/oom_score` / `echo -1000 > /proc/PID/oom_score_adj` | protège |
| `grep -E 'MemAvailable\|Dirty\|Committed_AS' /proc/meminfo` | détails |
| `sysctl vm.swappiness vm.overcommit_memory vm.dirty_ratio` | réglages |
| `echo 3 > /proc/sys/vm/drop_caches` | vide le cache (diagnostic seulement) |
| `systemctl show factura -p MemoryCurrent -p MemoryMax` | cgroup du service |
| `systemd-cgtop` | consommation par cgroup |

### Disque et E/S

| Commande | Effet |
|---|---|
| `iostat -xz 1` | `r/s w/s rkB/s wkB/s await aqu-sz %util` |
| `iotop -oPa` | processus qui écrivent |
| `pidstat -d 1` | E/S par processus |
| `df -h` / `df -i` / `du -xh --max-depth=1 / \| sort -h` | plein ? inodes ? où ? |
| `lsof +L1` | supprimés encore ouverts |
| `lsof /var/log` / `fuser -vm /srv` | qui tient ce chemin |
| `smartctl -a /dev/sda` | santé physique |
| `dmesg -T \| grep -i -E 'I/O error\|reset\|remount'` | erreurs disque |
| `cat /sys/block/sda/queue/scheduler` | ordonnanceur |
| `fstrim -v /` | TRIM |
| `blktrace -d /dev/sda -o - \| blkparse -i -` | trace bloc |

### Réseau et services

| Commande | Effet |
|---|---|
| `ss -tulpn` / `ss -s` / `ss -tan state time-wait \| wc -l` | ports / résumé / TIME-WAIT |
| `ss -ti dst 10.10.10.12` | RTT, retransmissions par connexion |
| `ip -s link show ens18` | drops, erreurs |
| `nstat -az \| grep -i -E 'retrans\|listendrop\|overflow'` | compteurs TCP |
| `sar -n EDEV 1 3` / `sar -n TCP,ETCP 1 3` | erreurs / retransmissions |
| `curl -sS -o /dev/null -w '%{time_connect} %{time_starttransfer}\n' URL` | où est la latence |
| `systemctl status x` / `systemctl reset-failed x` | état / réarme le compteur |
| `systemctl show x -p NRestarts -p ExecMainStatus -p Result` | échecs |
| `systemd-analyze blame` / `critical-chain` | boot lent |
| `nginx -t` / `sshd -t` / `named-checkconf` / `apachectl -t` | valide avant reload |
| `sudo -u postgres psql -c 'select 1'` | test applicatif direct |

::: piege
* Charge à 40 avec CPU à 2 % : processus en `D`, c'est le stockage.
* Redémarrer le service avant de collecter : les preuves sont détruites
  (`journalctl`, `ps`, `ss`, `/proc/PID` d'abord).
* `strace` sur un serveur chargé multiplie la latence : quelques secondes.
* `start request repeated too quickly` : `StartLimitBurst`, pas l'appli ;
  `systemctl reset-failed` puis lis le vrai message au-dessus.
* Un `sysctl` copié d'un blog sans mesure avant/après : machine divergente.
* `free` bas n'est pas un problème, `available` bas oui.
:::

::: astuce
* `dmesg -T | tail -40` — la première commande, toujours.
* `ps -eo pid,stat,wchan:20,cmd | awk '$2 ~ /D/'` — qui attend le disque.
* `journalctl -u x -n 100 --no-pager | grep -v -i info` — le signal, pas le bruit.
:::

---

## 17 · Git

### Configuration et démarrage

| Commande | Effet |
|---|---|
| `git config --global user.name "Mathieu"` / `user.email` | identité |
| `git config --global init.defaultBranch main` | branche par défaut |
| `git config --global pull.rebase true` | `pull` = fetch + rebase |
| `git config --global push.autoSetupRemote true` | plus besoin de `-u` |
| `git config --global fetch.prune true` | nettoie `origin/*` |
| `git config --global rerere.enabled true` | rejoue les résolutions |
| `git config --global core.excludesFile ~/.gitignore_global` | ignore perso |
| `git config --list --show-origin` | d'où vient chaque valeur |
| `git init` / `git clone --depth 1 URL` | crée / clone superficiel |
| `git clone -b v1.2.0 URL` | à un tag |
| `git remote -v` / `git remote set-url origin URL` | distants |

### Cycle quotidien

| Commande | Effet |
|---|---|
| `git status -sb` | court, avec ahead/behind |
| `git add -p` / `git add -A` | par morceaux / tout |
| `git restore --staged f` / `git restore f` | désindexe / annule le fichier |
| `git commit -m "feat(api): ..."` / `-am` | commit / avec fichiers suivis |
| `git commit --amend --no-edit` | corrige le dernier (non poussé) |
| `git diff` / `--staged` / `HEAD` / `A...B` | wd↔index / index↔HEAD / wd↔HEAD / apport de B |
| `git diff --stat` / `--name-only` / `--check` | résumé / noms / marqueurs oubliés |
| `git log --oneline --graph --decorate --all` | l'arbre |
| `git log -p -S'mot' -- fichier` | pickaxe |
| `git log --since=2.weeks --author=mathieu` | filtres |
| `git log --all --oneline -- chemin/supprimé` | fichier supprimé |
| `git show HEAD~2:chemin/f` | fichier à une révision |
| `git blame -L 12,18 f` | qui a écrit quoi |
| `git stash push -u -m msg` / `pop` / `list` / `drop` | mise de côté |
| `git check-ignore -v f` | quelle règle ignore |
| `git rm --cached f` | arrête de suivre sans supprimer |

### Branches, fusion, rebase

| Commande | Effet |
|---|---|
| `git switch -c feature/x` / `git switch main` | crée / change |
| `git branch -a` / `-vv` / `-d x` / `-D x` | liste / suivi / supprime / force |
| `git merge --no-ff feature/x` | commit de merge explicite |
| `git merge --abort` / `git rebase --abort` | annule |
| `git rebase main` / `git rebase -i HEAD~3` | rejoue / réécrit |
| `git rebase --continue` | après résolution |
| `git cherry-pick <sha>` | recopie un commit |
| `git rerere` | automatique si activé |
| `git tag -a v1.2.0 -m "..."` / `git tag -l` / `git push origin v1.2.0` | tags |
| `git describe --tags` | version courante |

### Distants

| Commande | Effet |
|---|---|
| `git fetch --all --prune` | met à jour `origin/*`, rien d'autre |
| `git pull --rebase` | fetch + rebase |
| `git push -u origin feature/x` | pousse et mémorise |
| `git push --force-with-lease` | force sûr |
| `git push origin --delete feature/x` | supprime à distance |
| `git push --tags` | tous les tags |
| `git ls-remote origin` | refs distantes sans cloner |

### Réparer

| Commande | Effet |
|---|---|
| `git reset --soft HEAD~1` | défait le commit, garde l'index |
| `git reset --mixed HEAD~1` | défait commit et index, garde les fichiers |
| `git reset --hard HEAD~1` | tout perd (non poussé seulement) |
| `git revert <sha>` | commit inverse, sûr sur un historique partagé |
| `git reflog` / `git branch sauvetage HEAD@{3}` | retrouve un commit perdu |
| `git restore --source=v1.0.0 f` | fichier d'une version |
| `git clean -ndx` / `git clean -fdx` | liste / supprime non suivis + ignorés |
| `git bisect start HEAD v1.0.0 && git bisect run ./test.sh` | commit fautif |
| `git filter-repo --invert-paths --path .env` | purge (après rotation) |
| `git fsck --lost-found` | objets orphelins |

```gitignore
.terraform/
*.tfstate
*.tfstate.backup
.env
/logs/*
!/logs/.gitkeep
```

::: piege
* Un fichier déjà suivi n'est jamais ignoré : `git rm --cached` d'abord.
* Pendant un rebase, `HEAD` est la branche de base, « autre » ton commit.
* `git push --force` écrase les autres ; `--force-with-lease` seulement toi.
* `reset --hard` et `checkout -- f` détruisent sans passer par le reflog
  pour les fichiers non commités.
* `git pull` sans `--rebase` crée des merges parasites.
* `*.tfstate` commité = mots de passe en clair dans l'historique.
:::

::: astuce
* `git log --oneline --graph --all -20` — l'état du dépôt en 3 s.
* `git add -p` — des commits propres sans effort.
* `git reflog` — rien n'est perdu pendant 90 jours.
:::

---

## 18 · Docker et Compose

### Images

| Commande | Effet |
|---|---|
| `docker pull nginx:1.28-alpine` / `nginx@sha256:...` | par tag / par digest |
| `docker images` / `docker image ls --digests` | liste |
| `docker build -t factura-api:1.0 .` | construit (BuildKit) |
| `docker build --target builder --build-arg VER=1.0 --no-cache -t x .` | options |
| `docker buildx build --platform linux/amd64,linux/arm64 -t x --push .` | multi-arch |
| `docker history x` / `docker image inspect x --format '{{.Config.User}}'` | couches / méta |
| `docker tag factura-api:1.0 10.10.10.14:5000/factura-api:1.0` | retag |
| `docker push 10.10.10.14:5000/factura-api:1.0` | pousse |
| `docker login 10.10.10.14:5000` | authentifie |
| `docker save x \| gzip > x.tgz` / `docker load < x.tgz` | export / import |
| `docker rmi x` / `docker image prune -a` | supprime |
| `trivy image --severity HIGH,CRITICAL --ignore-unfixed x` | scan |
| `dive x` | inspecte les couches |

### Conteneurs

| Commande | Effet |
|---|---|
| `docker run -d --name web -p 8080:80 --restart unless-stopped nginx:1.28-alpine` | lance |
| `docker run --rm -it alpine:3.20 sh` | jetable, interactif |
| `docker run -d --init --user 10001:10001 --read-only --tmpfs /tmp x` | durci |
| `docker run --memory 256m --cpus 0.5 --cap-drop ALL x` | limité |
| `docker run -e CLE=val --env-file app.env x` | variables |
| `docker run -v pg-data:/var/lib/postgresql/data x` | volume nommé |
| `docker run -v /srv/conf:/etc/app:ro x` | bind mount lecture seule |
| `docker run -p 127.0.0.1:8080:80 x` | publié sur lo seulement |
| `docker ps -a` / `docker ps --filter status=exited` | liste |
| `docker logs -f --tail 100 --since 10m web` | journal |
| `docker exec -it web sh` / `docker exec -u 0 web id` | shell / en root |
| `docker stop web` / `docker kill -s HUP web` / `docker restart web` | signaux |
| `docker inspect web --format '{{.State.Status}} {{.State.ExitCode}}'` | état |
| `docker inspect web --format '{{.State.OOMKilled}}'` | tué par OOM ? |
| `docker inspect web --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'` | IP |
| `docker stats --no-stream` / `docker top web` | ressources / processus |
| `docker cp web:/etc/nginx/nginx.conf .` | copie |
| `docker events --since 15m` | événements du démon |
| `docker rm -f web` / `docker container prune` | supprime |
| `docker run --rm -it --pid container:app --network container:app busybox sh` | debug sans shell |

### Volumes, réseau, système

| Commande | Effet |
|---|---|
| `docker volume ls` / `create` / `inspect pg-data` / `rm` | volumes |
| `docker run --rm -v pg-data:/from:ro -v "$PWD":/to alpine tar czf /to/pg.tgz -C /from .` | sauvegarde |
| `docker network create factura-net` | réseau avec DNS intégré |
| `docker network ls` / `inspect factura-net` / `connect factura-net web` | réseaux |
| `docker system df -v` | occupation |
| `docker system prune -a --volumes` | tout nettoie (destructeur) |
| `journalctl -u docker -f` | démon |
| `cat /etc/docker/daemon.json && systemctl restart docker` | conf démon |
| `docker context ls` / `DOCKER_HOST=ssh://mathieu@10.10.10.14 docker ps` | à distance |

```dockerfile
FROM python:3.12-slim-bookworm
RUN useradd -r -u 10001 app
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY --chown=app:app . .
USER app
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s \
  CMD curl -sf localhost:8000/sante
ENTRYPOINT ["python3", "app.py"]
```

### Compose

| Commande | Effet |
|---|---|
| `docker compose up -d --build` | démarre, reconstruit |
| `docker compose ps` / `logs -f app` / `top` | état / journal |
| `docker compose exec app sh` | shell |
| `docker compose config` | fichier fusionné, interpolé |
| `docker compose pull && docker compose up -d` | mise à jour |
| `docker compose restart app` / `stop` / `start` | un service |
| `docker compose down` / `down -v` | arrête / et supprime les volumes |
| `docker compose -f compose.yaml -f compose.prod.yaml up -d` | surcharge |
| `docker compose --profile debug up -d` | profils |
| `docker compose run --rm app python manage.py migrate` | tâche ponctuelle |

```yaml
# compose.yaml
name: factura
services:
  app:
    build: .
    image: 10.10.10.14:5000/factura-api:1.0
    ports: ["127.0.0.1:8000:8000"]
    env_file: app.env
    depends_on:
      db: {condition: service_healthy}
    restart: unless-stopped
  db:
    image: postgres:16
    environment: {POSTGRES_PASSWORD: "${PG_PASS}"}
    volumes: [pg-data:/var/lib/postgresql/data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
volumes:
  pg-data: {}
```

::: rhel
Rocky 9 : dépôt `download.docker.com/linux/centos/docker-ce.repo` ou Podman
(`podman-docker`, rootless) ; bind mount avec SELinux : suffixe `:Z`.
:::

::: piege
* `latest` n'est pas « la dernière » : seul le digest est immuable.
* `EXPOSE` ne publie rien ; `-p` si.
* `CMD ["sh","-c","..."]` ou forme shell : `sh` est PID 1, `stop` attend 10 s
  puis SIGKILL (137). Forme exec ou `--init`.
* Bridge par défaut sans DNS : crée un réseau nommé.
* `-p` contourne ufw : seule la chaîne `DOCKER-USER` est respectée.
* `.env` interpole le fichier compose ; `env_file:` entre dans le conteneur.
* `depends_on` sans `condition: service_healthy` = ordre, pas disponibilité.
* `docker system prune -a --volumes` efface les données.
:::

::: astuce
* `docker compose config` — ce que compose a vraiment compris.
* `docker inspect x --format '{{.State.OOMKilled}} {{.State.ExitCode}}'` — 137 ?
* `docker run --rm -it --pid container:app busybox sh` — shell dans un distroless.
:::

---

## 19 · Ansible

### Inventaire et ad hoc

| Commande | Effet |
|---|---|
| `ansible-inventory --graph` / `--list` / `--host lab-db` | arbre / JSON / variables |
| `ansible all -m ansible.builtin.ping` | connectivité + Python |
| `ansible web -m ansible.builtin.command -a uptime` | sans shell |
| `ansible web -m ansible.builtin.shell -a 'ss -tlnp \| grep 443'` | avec shell |
| `ansible db -m ansible.builtin.setup -a 'filter=ansible_distribution*'` | facts |
| `ansible all -b -K -m ansible.builtin.apt -a 'name=htop state=present'` | sudo |
| `ansible all --limit 'web:!lab-rhel' -m ping` | motif |
| `ansible all -m ansible.builtin.copy -a 'src=f dest=/tmp/f mode=0644'` | copie |
| `ansible-doc ansible.builtin.lineinfile` / `ansible-doc -l \| grep ufw` | doc |
| `ansible-config dump --only-changed` | conf effective |
| `ansible --version` | version, `config file` utilisé |

```ini
# ansible.cfg
[defaults]
inventory = inventory/hosts.yml
remote_user = mathieu
interpreter_python = auto_silent
callback_result_format = yaml
vault_password_file = .vault_pass
[privilege_escalation]
become = True
[ssh_connection]
pipelining = True
```

```yaml
# inventory/hosts.yml
all:
  children:
    web:
      hosts:
        lab-web: {ansible_host: 10.10.10.11}
        lab-rhel: {ansible_host: 10.10.10.13}
    db:
      hosts:
        lab-db: {ansible_host: 10.10.10.12}
```

### Playbooks

| Commande | Effet |
|---|---|
| `ansible-playbook site.yml --syntax-check` | syntaxe |
| `ansible-playbook site.yml --check --diff` | simulation + diff |
| `ansible-playbook site.yml --limit lab-web -t paquets` | cible, tags |
| `ansible-playbook site.yml --skip-tags tls` | exclut |
| `ansible-playbook site.yml --list-tasks --list-hosts --list-tags` | inventaire du play |
| `ansible-playbook site.yml --start-at-task 'Déployer' --step` | reprise, pas à pas |
| `ansible-playbook site.yml -e app_version=2.1.0 -e @vars/prod.yml` | extra vars |
| `ansible-playbook site.yml -vvv` | SSH visible |
| `ansible-playbook site.yml -K` / `--ask-vault-pass` | mots de passe |
| `ANSIBLE_STDOUT_CALLBACK=yaml ansible-playbook ...` | sortie lisible |
| `ansible-lint site.yml` / `yamllint .` | qualité |
| `ansible-galaxy collection install -r requirements.yml` | collections |
| `ansible-galaxy role init roles/nginx` | squelette de rôle |
| `ansible-pull -U URL site.yml` | mode pull |

```yaml
# site.yml
- name: Baseline web
  hosts: web
  become: true
  vars: {http_port: 80}
  tasks:
    - name: Installer nginx
      ansible.builtin.package: {name: nginx, state: present}
    - name: Déployer le vhost
      ansible.builtin.template:
        src: vhost.conf.j2
        dest: /etc/nginx/sites-available/vitrine.conf
        mode: "0644"
      notify: Reload nginx
  handlers:
    - name: Reload nginx
      ansible.builtin.service: {name: nginx, state: reloaded}
```

### Vault et débogage

| Commande | Effet |
|---|---|
| `ansible-vault create group_vars/all/vault.yml` | fichier chiffré |
| `ansible-vault edit` / `view` / `encrypt` / `decrypt` / `rekey f` | gestion |
| `ansible-vault encrypt_string --name vault_pg_pass 'S3cret'` | valeur inline |
| `ansible localhost -m debug -a "msg={{ lookup('file','x') }}"` | teste une expression |
| `ansible lab-db -m debug -a 'var=hostvars[inventory_hostname]'` | toutes les variables |
| `ansible all -m setup --tree /tmp/facts` | facts sur disque |
| `ssh -v mathieu@10.10.10.11` | quand `UNREACHABLE` |
| `sudo -n true` sur la cible | quand `Missing sudo password` |

Précédence (croissante) : `defaults/` du rôle < `group_vars/all` <
`group_vars/*` < `host_vars` < `vars:` du play < `vars/` du rôle <
`set_fact` < `-e`. Modules : `command` sans shell, `creates:`/`changed_when:`
obligatoires ; `lineinfile` avec `regexp:` ; `template` dès deux lignes ;
`systemd_service` avec `state: reloaded` en handler, jamais `restarted` en
tâche.

::: piege
* `{{ }}` en début de valeur YAML : entre guillemets, sinon erreur de parse.
* `when:` sans `{{ }}` ; `loop:` avec.
* Un handler ne tourne qu'en fin de play et pas pour un hôte en échec :
  `meta: flush_handlers` ou `--force-handlers`.
* `--check` n'exécute pas `command` : un `register` vide fait planter la
  tâche suivante, c'est normal.
* Secret affiché par `-v` : `no_log: true`.
* `apt: update_cache` sans `cache_valid_time` = `changed` à chaque run.
:::

::: astuce
* `ansible-playbook site.yml --check --diff --limit lab-web` — avant chaque apply.
* `ansible-inventory --host lab-db` — les variables telles que résolues.
* `ansible all -m ping -o` — une ligne par hôte.
:::

---

## 20 · OpenTofu, cloud-init, Proxmox

### OpenTofu / Terraform

| Commande | Effet |
|---|---|
| `tofu init` / `tofu init -upgrade` / `-migrate-state` | providers, backend |
| `tofu fmt -recursive` / `tofu validate` | mise en forme / syntaxe |
| `tofu plan -out plan.tfplan` | diff code ↔ état ↔ réalité |
| `tofu apply plan.tfplan` / `tofu apply -auto-approve` | exécute |
| `tofu apply -target=proxmox_virtual_environment_vm.lab["web"]` | ciblé |
| `tofu apply -replace=adr` | recrée |
| `tofu apply -refresh-only` | accepte le drift dans l'état |
| `tofu destroy` / `-target=adr` | détruit |
| `tofu show` / `tofu show -json plan.tfplan \| jq` | état / plan lisible |
| `tofu state list` / `state show adr` | inventaire de l'état |
| `tofu state mv a b` / `state rm adr` | renomme / oublie |
| `tofu import adr pve/9004` | adopte une VM existante (bpg) |
| `tofu output -json` / `tofu output ips` | sorties |
| `tofu console` | teste `cidrhost("10.10.10.0/24", 20)` |
| `tofu workspace new recette` / `list` / `select` | états parallèles |
| `tofu providers lock -platform=linux_amd64` | verrou |
| `tofu force-unlock ID` | verrou orphelin |
| `TF_LOG=DEBUG tofu plan` | debug |
| `export PROXMOX_VE_ENDPOINT=https://10.10.10.1:8006/` | provider bpg |
| `export PROXMOX_VE_API_TOKEN='terraform@pve!tofu=<uuid>'` | token |

```hcl
# main.tf
terraform {
  required_providers {
    proxmox = { source = "bpg/proxmox", version = "~> 0.7" }
  }
}
provider "proxmox" { insecure = true }
resource "proxmox_virtual_environment_vm" "web" {
  name      = "lab2-web"
  vm_id     = 9110
  node_name = "pve"
  clone { vm_id = 9100 }
  initialization {
    ip_config { ipv4 { address = "10.10.10.110/24"
                       gateway = "10.10.10.1" } }
    user_account { username = "mathieu"
                   keys = [file("~/.ssh/id_ed25519.pub")] }
  }
}
output "ip" { value = "10.10.10.110" }
```

Plan : `+` créer, `~` modifier, `-` détruire, `-/+` remplacer,
`# forces replacement` désigne l'attribut. `for_each` (clé stable) plutôt
que `count` (index). Variables : `-var` > `*.auto.tfvars` >
`terraform.tfvars` > `TF_VAR_x` > `default`.

### cloud-init

| Commande | Effet |
|---|---|
| `cloud-init status --long` | `done` / `running` / `error` |
| `cloud-init schema --config-file user.yaml` | valide avant usage |
| `cloud-init query userdata` / `cloud-init query -a` | ce que la VM a reçu |
| `cat /var/log/cloud-init.log /var/log/cloud-init-output.log` | traces |
| `cloud-init clean --logs && reboot` | rejoue comme un premier boot |
| `cat /var/lib/cloud/data/instance-id` | identité courante |
| `ls /var/lib/cloud/instances/` | instances vues |
| `cloud-init analyze show` | durée par module |

```yaml
#cloud-config
hostname: lab2-web
fqdn: lab2-web.lab.local
manage_etc_hosts: true
users:
  - name: mathieu
    groups: [sudo]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: true
    ssh_authorized_keys: [ssh-ed25519 AAAAC3... mathieu@lab-adm]
package_update: true
packages: [qemu-guest-agent]
runcmd:
  - systemctl enable --now qemu-guest-agent
```

### Template Proxmox

```bash
wget -q https://cloud-images.ubuntu.com/noble/current/\
noble-server-cloudimg-amd64.img
qm create 9100 --name ubuntu-2404-tpl --memory 1024 --cores 1 \
  --net0 virtio,bridge=vmbr1 --scsihw virtio-scsi-single \
  --agent enabled=1 --serial0 socket --vga serial0
qm disk import 9100 noble-server-cloudimg-amd64.img local-lvm
qm set 9100 --scsi0 local-lvm:vm-9100-disk-0,discard=on
qm set 9100 --ide2 local-lvm:cloudinit --boot order=scsi0
qm set 9100 --ciuser mathieu --sshkeys /root/keys/mathieu.pub \
  --ipconfig0 ip=dhcp
qm disk resize 9100 scsi0 20G
qm template 9100
```

::: piege
* L'état contient les valeurs `sensitive` en clair : backend distant,
  verrou, jamais dans Git.
* `count` : retirer l'élément 0 recrée tout. `for_each`.
* `--cicustom user=` remplace tout le user-data : `--ciuser`, `--sshkeys`
  sont ignorés.
* Le per-instance (users, runcmd) ne rejoue que si `instance-id` change.
* Template cloné avec les mêmes clés SSH d'hôte : `ssh-keygen -A` ou
  `cloud-init clean`.
* `tofu apply` sans `plan -out` : ce qui s'applique n'est pas ce qu'on a lu.
:::

::: astuce
* `tofu plan -out p && tofu show -json p | jq '.resource_changes[].change.actions'`.
* `cloud-init schema --config-file f.yaml` — avant de cloner dix VM.
* `qm cloudinit dump 9110 user` — ce que Proxmox a vraiment généré.
:::

---

## 21 · CI/CD

### Runner et forge (Gitea)

| Commande | Effet |
|---|---|
| `act_runner generate-config > config.yaml` | conf par défaut |
| `act_runner register --no-interactive --instance http://10.10.10.14:3000 --token T --name runner-ops --labels "ubuntu-latest:docker://docker.gitea.com/runner-images:ubuntu-latest,lab-shell:host"` | enregistre |
| `act_runner daemon --config config.yaml` | démarre (ou `systemctl start act_runner`) |
| `gitea actions generate-runner-token` | jeton d'enregistrement |
| `journalctl -u act_runner -f` | ce que le runner reçoit |
| `docker ps --filter name=GITEA-ACTIONS` | jobs en cours |
| `yamllint -d '{rules: {truthy: {allowed-values: ["true","false","on"]}}}' .gitea/workflows/` | valide |
| `act -l` / `act push -j test` | exécute un workflow en local (`act`) |
| `curl -s http://10.10.10.14:3000/api/v1/repos/mathieu/factura/actions/runs` | API |
| `git tag -a v1.4.2 -m "release" && git push origin v1.4.2` | déclenche la release |

```yaml
# .gitea/workflows/ci.yaml
name: ci
on:
  push: {branches: [main], tags: ["v*"]}
  pull_request:
env:
  IMAGE: 10.10.10.14:5000/factura
jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - run: pip install -r requirements.txt && pytest -q
  build:
    needs: test
    if: gitea.ref == 'refs/heads/main'
    runs-on: lab-shell
    env: {REG_PASS: "${{ secrets.REG_PASS }}"}
    steps:
      - uses: actions/checkout@v4
      - run: |
          SHA=${GITHUB_SHA::12}
          docker build -t "$IMAGE:$SHA" .
          echo "$REG_PASS" | docker login 10.10.10.14:5000 \
            -u ci --password-stdin
          docker push "$IMAGE:$SHA"
```

### Pipeline applicatif de référence

```text
lint + test -> build :SHA -> trivy -> push -> deploy -> smoke
                                                     |-> rollback
```

| Étape | Commande type |
|---|---|
| lint | `shellcheck *.sh`, `yamllint .`, `ansible-lint`, `tofu fmt -check` |
| test | `pytest -q --junitxml=rapport.xml` |
| build | `docker build -t "$IMAGE:${GITHUB_SHA::12}" .` |
| scan | `trivy image --exit-code 1 --severity CRITICAL "$IMAGE:$SHA"` |
| push | `docker push "$IMAGE:$SHA"` |
| promotion | `docker tag "$IMAGE:$SHA" "$IMAGE:v1.4.2" && docker push ...` |
| deploy | `ssh -i ~/.ssh/deploy deploy@10.10.10.11 "/opt/deploy.sh $SHA"` |
| smoke | `curl -sf http://10.10.10.11/version \| grep -q "$SHA"` |
| rollback | `/opt/deploy.sh <SHA précédent>` (image déjà tirée) |

Clé de déploiement restreinte, côté serveur :
`from="10.10.10.14",command="/opt/deploy.sh",no-pty ssh-ed25519 AAAA...`.

### Syntaxe et diagnostic

| Symptôme | Réflexe |
|---|---|
| aucun run | YAML invalide, ou `on:` ne couvre pas l'événement |
| `waiting` sans fin | aucun runner avec le label `runs-on` |
| `permission denied` docker.sock | `container.docker_host` du runner |
| artefact introuvable | job producteur sauté, `path` faux |
| vert en CI, cassé en prod | image différente, variable absente, `latest` |
| secret dans le journal | `set -x`, `curl -v`, secret dans `run:` au lieu d'`env:` |
| job dépendant sauté | le parent a échoué ; `if: always()` pour forcer |

Contexte : `${{ gitea.sha }}`, `gitea.ref`, `gitea.event_name`,
`gitea.actor`, `secrets.X`, `needs.job.outputs.x`, `hashFiles('**/*.txt')`,
`failure()`, `always()`. Dans `run:` : `$GITHUB_SHA`, `$GITHUB_REF_NAME`,
`echo "x=1" >> "$GITHUB_OUTPUT"`, `echo "V=1" >> "$GITHUB_ENV"`.

::: piege
* `${{ secrets.X }}` dans `run:` est substitué avant le shell : `env:`.
* `runs-on: ubuntu-latest` ne veut rien dire sans label correspondant.
* Un secret encodé (`base64`, découpé) traverse le masquage.
* `latest` déployé : impossible à reproduire ni à annuler.
* Rebuild « pour la prod » : ce n'est plus l'image testée.
* Cache ≠ garantie : un cache corrompu se supprime, pas se débogue.
:::

::: astuce
* `docker build -t "$IMAGE:${GITHUB_SHA::12}"` — un tag par commit, toujours.
* `curl -sf URL/version | grep -q "$SHA"` — le smoke test qui prouve la version.
* `act -l` — liste les jobs sans pousser.
:::

---

## 22 · Kubernetes et observabilité

### kubectl

| Commande | Effet |
|---|---|
| `export KUBECONFIG=~/.kube/config` | (k3s : `/etc/rancher/k3s/k3s.yaml`) |
| `kubectl config get-contexts` / `use-context x` | contextes |
| `kubectl config set-context --current --namespace=factura` | namespace par défaut |
| `kubectl get nodes -o wide` / `get all -n factura` / `get all -A` | vue |
| `kubectl get pods -o wide` / `-o yaml` / `-w` | détail / suivi |
| `kubectl get pods -l app=api -o jsonpath='{.items[*].status.podIP}'` | extraction |
| `kubectl describe pod NOM` | Events en bas |
| `kubectl get events -A --sort-by=.lastTimestamp \| tail -20` | tout événement |
| `kubectl logs NOM -c cont --previous --tail=100 -f` | journal, avant crash |
| `kubectl logs deploy/api --all-containers` / `-l app=api` | par sélecteur |
| `kubectl exec -it NOM -- sh` | shell |
| `kubectl port-forward svc/front 8080:80` | accès local |
| `kubectl apply -f dossier/` / `kubectl diff -f x.yaml` / `delete -f` | déclaratif |
| `kubectl apply -k overlays/prod` | kustomize |
| `kubectl create deploy web --image=nginx:1.27 --dry-run=client -o yaml` | squelette |
| `kubectl explain deployment.spec.strategy` | doc des champs |
| `kubectl scale deploy api --replicas=3` | échelle |
| `kubectl set image deploy/api api=10.10.10.14:5000/factura-api:1.1` | nouvelle image |
| `kubectl rollout status` / `history` / `undo --to-revision=1` / `restart deploy/api` | déploiements |
| `kubectl top node` / `top pod --containers` | consommation (metrics-server) |
| `kubectl run -it --rm dbg --image=busybox:1.36 --restart=Never -- sh` | pod jetable |
| `kubectl get endpoints api` | le Service voit des pods ? |
| `kubectl auth can-i delete pods --as=system:serviceaccount:factura:default` | RBAC |
| `kubectl cordon NODE` / `drain NODE --ignore-daemonsets` / `uncordon` | maintenance |
| `kubectl create secret generic pg --from-literal=pass=S3cret` | secret |
| `kubectl get secret pg -o jsonpath='{.data.pass}' \| base64 -d` | le lire |
| `kubectl create configmap app --from-file=app.conf` | configmap |
| `kubectl label pod NOM env=prod` / `annotate` | métadonnées |
| `kubectl api-resources` / `kubectl get crd` | catalogue |
| `helm upgrade --install NOM chart -n ns --create-namespace -f values.yaml` | Helm |
| `helm list -A` / `history NOM` / `rollback NOM 1` / `template NOM chart` | Helm |
| `curl -sfL https://get.k3s.io \| sh -` / `journalctl -u k3s -f` | k3s |
| `sudo k3s crictl ps` / `sudo k3s ctr images ls` | runtime |

```yaml
# deploy.yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: api, namespace: factura}
spec:
  replicas: 2
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec:
      containers:
        - name: api
          image: 10.10.10.14:5000/factura-api:1.0
          ports: [{containerPort: 8000}]
          resources:
            requests: {cpu: 100m, memory: 128Mi}
            limits: {memory: 256Mi}
          readinessProbe:
            httpGet: {path: /sante, port: 8000}
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata: {name: api, namespace: factura}
spec:
  selector: {app: api}
  ports: [{port: 80, targetPort: 8000}]
```

| Symptôme | Cause typique |
|---|---|
| `Pending` | requests trop gros, PVC non lié, quota, nodeSelector |
| `ImagePullBackOff` | tag faux, secret absent, registre HTTP non déclaré |
| `CrashLoopBackOff` | `logs --previous` : config manquante, app en erreur |
| `OOMKilled` / 137 | limite mémoire < besoin |
| `0/1 READY` | readiness : port, chemin, dépendance |
| Service muet | `get endpoints` vide : selector ≠ labels |
| Ingress 404 / 5xx | Host/path ne matche pas / aucun endpoint prêt |

### Prometheus, Alertmanager, Grafana, Loki

| Commande | Effet |
|---|---|
| `promtool check config prometheus.yml` / `check rules r.yml` | valide |
| `curl -X POST localhost:9090/-/reload` | recharge (`--web.enable-lifecycle`) |
| `curl -s localhost:9090/api/v1/targets \| jq '.data.activeTargets[].health'` | cibles |
| `curl -s 'localhost:9090/api/v1/query?query=up' \| jq` | requête API |
| `curl -s 10.10.10.11:9100/metrics \| grep node_load1` | exporter brut |
| `promtool query instant http://localhost:9090 'up == 0'` | requête CLI |
| `promtool test rules tests.yml` | tests unitaires de règles |
| `amtool check-config alertmanager.yml` | valide |
| `amtool alert query` / `amtool silence add alertname=X --duration=2h --comment=m` | alertes / silence |
| `curl -s localhost:9093/api/v2/alerts \| jq '.[].labels.alertname'` | alertes actives |
| `grafana-cli plugins install x` / `/etc/grafana/provisioning/` | Grafana |
| `logcli query '{host="lab-web"} \|= "error"' --since=1h` | Loki |

```yaml
# prometheus.yml
global: {scrape_interval: 15s, evaluation_interval: 15s}
rule_files: [/etc/prometheus/rules/*.yml]
alerting:
  alertmanagers: [{static_configs: [{targets: [localhost:9093]}]}]
scrape_configs:
  - job_name: node
    static_configs:
      - targets: ["10.10.10.11:9100", "10.10.10.12:9100"]
```

```yaml
# rules/base.yml
groups:
  - name: base
    rules:
      - alert: InstanceDown
        expr: up == 0
        for: 2m
        labels: {severity: page}
        annotations:
          summary: "{{ $labels.instance }} ne répond plus"
      - alert: DiskFull24h
        expr: >
          predict_linear(
          node_filesystem_avail_bytes{mountpoint="/"}[6h], 86400) < 0
        for: 30m
        labels: {severity: ticket}
```

| PromQL | Sens |
|---|---|
| `rate(http_requests_total[5m])` | req/s, fenêtre ≥ 4 × scrape |
| `sum by (instance) (rate(node_cpu_seconds_total{mode!="idle"}[5m]))` | CPU par hôte |
| `1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes` | RAM utilisée |
| `histogram_quantile(0.95, sum by (le) (rate(h_bucket[5m])))` | p95 |
| `sum(rate(x_total{code=~"5.."}[5m])) / sum(rate(x_total[5m]))` | taux d'erreur |
| `increase(c[1h])` / `changes(v[1h])` / `absent(up{job="node"})` | total / instabilité / absence |
| `topk(3, v)` / `v offset 1d` / `avg_over_time(v[1h])` | classement / hier / lissage |
| `{job="systemd-journal", host="lab-web"} \|= "error" \| logfmt` | LogQL |

Alertmanager : `route` → `receiver`, `group_by`, `group_wait: 30s`,
`group_interval: 5m`, `repeat_interval: 4h`, `inhibit_rules`. Budget
d'erreur : 99,9 % sur 30 j = 43,2 min. Node Exporter Full = dashboard 1860.

::: piege
* Secret Kubernetes = base64, pas chiffré : RBAC et chiffrement etcd.
* Liveness trop agressive : restart en boucle d'une app saine mais lente ;
  `startupProbe` d'abord.
* Limite CPU = throttling, limite mémoire = OOMKilled : pose surtout des
  `requests`.
* `rate` sur une gauge ou `irate` en alerte : valeurs absurdes.
* Comparaison PromQL (`> 0.9`) filtre les séries, ne rend pas un booléen.
* Une alerte sans `for:` ni runbook = bruit ; on alerte sur le symptôme.
:::

::: astuce
* `kubectl get events -A --sort-by=.lastTimestamp | tail -20` — toujours d'abord.
* `kubectl logs POD --previous` — la vraie cause d'un CrashLoopBackOff.
* `promtool check config && curl -X POST :9090/-/reload` — reload sans risque.
:::

---

## 23 · Python pour l'ops

### Installation, venv, outils

| Commande | Effet |
|---|---|
| `python3 --version` / `python3 -m sysconfig` | version, chemins |
| `python3 -m venv ~/lab23/venv` | crée un venv (paquet `python3-venv`) |
| `source venv/bin/activate` / `deactivate` | active (modifie `PATH`) / quitte |
| `venv/bin/python script.py` | **sans activer** : chemin absolu (timers) |
| `venv/bin/pip install -r requirements.txt` | dépendances du projet |
| `pip freeze > requirements.txt` | fige les versions exactes |
| `pip install "requests>=2.32,<3"` | borne large (requirements.in) |
| `pip list --outdated` / `pip show requests` | état / version installée |
| `python3 -m pip ...` / `python3 -m pytest` | le module du **bon** interpréteur |
| `pipx install ruff` / `pipx install .` | outil CLI isolé dans son venv |
| `pipx run ruff check .` | exécute sans installer |
| `pip install .` / `pip install -e .` | installe le projet / en mode éditable |
| `python3 -m json.tool f.json` | pretty-print JSON |
| `python3 -m http.server 8000` | serveur de fichiers jetable |
| `python3 -c 'import yaml; print(yaml.__file__)'` | d'où vient un module |
| `python3 -X importtime script.py` | temps d'import |

Jamais `sudo pip install` sur un serveur : conflit avec les paquets `apt`
(`externally-managed-environment`). Système = apt, projet = venv, outil =
pipx.

```text
projet/                    # structure minimale
  pyproject.toml           # name, deps, [project.scripts]
  src/monoutil/{__init__,cli}.py
  tests/test_cli.py
  requirements.txt         # pip freeze, versions exactes
```

### Le langage, le strict nécessaire

```python
nom: str = "lab-web"; n = 3; ok = True; x = None
hotes = ["a", "b"]; conf = {"port": 22}; vus = set()
print(f"{nom}:{n:>4} {conf['port']!r} {n/7:.2f}")
hotes[-1], hotes[1:], hotes[::-1]          # slicing
[h.upper() for h in hotes if h != "a"]     # compréhension
{h: len(h) for h in hotes}                 # dict compréhension
for i, h in enumerate(hotes, 1): ...
for a, b in zip(hotes, [1, 2]): ...
```

```python
from dataclasses import dataclass, field

@dataclass(frozen=True)
class Machine:
    nom: str
    vmid: int
    tags: tuple[str, ...] = field(default_factory=tuple)

def ajouter(x: str, liste: list[str] | None = None) -> list[str]:
    liste = [] if liste is None else liste   # jamais liste=[]
    liste.append(x); return liste
```

```python
try:
    r = faire()
except FileNotFoundError:
    log.warning("absent")
except (OSError, ValueError) as exc:  # jamais « except: »
    log.error("échec : %s", exc); return 1
else:
    ...                          # si aucune exception
finally:
    nettoyer()                   # toujours
raise RuntimeError("msg") from exc   # chaîne la cause

if __name__ == "__main__":
    sys.exit(main())
```

### Bibliothèque standard côté ops

| Appel | Effet |
|---|---|
| `Path("/etc")/"hosts"` `.read_text()` `.exists()` | `pathlib` |
| `p.glob("*.log")` / `p.rglob("*.py")` / `p.stat().st_size` | listing |
| `p.parent` / `p.name` / `p.suffix` / `p.stem` | dirname, basename… |
| `shutil.copy2` / `move` / `rmtree` / `which` / `disk_usage` | fichiers |
| `subprocess.run(argv, capture_output=True, text=True, check=True, timeout=30)` | commande |
| `os.environ.get("X", "def")` / `os.getpid()` / `os.replace(a, b)` | env, rename atomique |
| `json.load(f)` / `json.dumps(d, indent=2, ensure_ascii=False)` | JSON |
| `csv.DictReader(f, delimiter=";")` / `csv.writer(f)` | CSV |
| `re.compile(r"^(?P<ip>\S+) ")` `.match(s)["ip"]` | regex nommée |
| `datetime.now(UTC)` / `.astimezone(ZoneInfo("Europe/Paris"))` | dates **aware** |
| `datetime.strptime(s, "%d/%b/%Y:%H:%M:%S %z")` / `.isoformat()` | parse / ISO |
| `time.monotonic()` | durées (jamais `time.time()`) |
| `socket.create_connection((h, p), timeout=3)` | test TCP |
| `ipaddress.ip_interface("10.10.10.11/24").ip` / `.network` | adresses |
| `hashlib.sha256(b).hexdigest()` / `hashlib.file_digest(f, "sha256")` | empreintes |
| `tempfile.mkstemp(dir=cible.parent)` / `TemporaryDirectory()` | temporaires |
| `tomllib.load(open(p, "rb"))` / `configparser.ConfigParser().read(p)` | TOML, INI |
| `signal.signal(signal.SIGTERM, handler)` | arrêt propre |
| `sys.argv` / `sys.stdin` / `sys.exit(2)` / `sys.stderr` | flux, codes |

```python
p = subprocess.run(["tar", "-czf", dest, "--", *fichiers],
                   capture_output=True, text=True, check=True,
                   timeout=300)           # liste, JAMAIS shell=True
print(p.stdout); p.returncode
# échec -> subprocess.CalledProcessError (.returncode, .stderr)
# absent -> FileNotFoundError ; lent -> subprocess.TimeoutExpired
```

```python
import logging, sys
from logging.handlers import SysLogHandler
log = logging.getLogger("outil")
logging.basicConfig(level=logging.INFO, stream=sys.stderr,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log.addHandler(SysLogHandler(address="/dev/log"))   # -> journald
log.info("hôte %s ok", h)      # %s, pas f-string : formaté si émis
log.exception("échec")         # dans un except : ajoute la trace
```

```python
p = argparse.ArgumentParser(description="...")
p.add_argument("fichier")
p.add_argument("--top", type=int, default=10)
p.add_argument("-n", "--dry-run", action="store_true")
sub = p.add_subparsers(dest="cmd", required=True)
sub.add_parser("list")
sub.add_parser("add").add_argument("nom")
args = p.parse_args()       # -h généré ; mauvais usage -> code 2
```

### Fichiers et flux

```python
with open(p, encoding="utf-8") as f:     # encodage TOUJOURS explicite
    for ligne in f:                       # flux : RAM constante
        ...
open(p, encoding="utf-8", errors="replace")   # tolérant
open(p, encoding="utf-8-sig")             # mange le BOM d'Excel
open(p, encoding="latin-1")               # vieux exports
gzip.open(p, "rt", encoding="utf-8")      # .gz en texte
for ligne in sys.stdin: ...               # s'insère dans un pipe
```

```python
fd, tmp = tempfile.mkstemp(dir=cible.parent)   # même FS que la cible
with os.fdopen(fd, "w", encoding="utf-8") as f:
    f.write(texte); f.flush(); os.fsync(f.fileno())
os.replace(tmp, cible)   # rename atomique : jamais à moitié écrit
```

### Réseau et API

```python
import requests
s = requests.Session(); s.headers["Authorization"] = f"token {tok}"
r = s.get(url, params={"q": "x"}, timeout=(3.05, 10))
r.raise_for_status()           # 4xx/5xx -> HTTPError, sinon faux OK
data = r.json()
s.post(url, json={"title": "t"}, timeout=10)
# retries : HTTPAdapter(max_retries=Retry(total=3, backoff_factor=0.5,
#   status_forcelist=[502, 503, 504])) monté sur "https://"
# except requests.RequestException (hérite d'OSError)
```

| API | Appel |
|---|---|
| Proxmox | `PVEAPIToken=user@pve!id=uuid` ; `GET /api2/json/cluster/resources?type=vm` |
| Proxmox | `GET /api2/json/nodes/pve/qemu/9002/config` (`ipconfig0`, `tags`) |
| `pvesh` | `pvesh get /cluster/resources --type vm --output-format json` |
| Gitea | `Authorization: token X` ; `GET /api/v1/repos/search?q=factura` |
| Gitea | `POST /api/v1/repos/{owner}/{repo}/issues` `json={"title": ...}` |
| Prometheus | `GET /api/v1/query?query=up` → `data.result[].value[1]` |
| Docker | socket `/var/run/docker.sock`, HTTP `GET /containers/json` |
| YAML | `yaml.safe_load(f)` / `yaml.safe_dump(d, sort_keys=False)` |
| PostgreSQL | `psycopg.connect(dsn).execute("SELECT ...").fetchall()` |

### Qualité, tests, packaging

| Commande | Effet |
|---|---|
| `ruff check --fix .` / `ruff format .` | lint + format (remplace flake8, black, isort) |
| `mypy src/` | vérifie les annotations |
| `pytest -q` / `-x` / `-k nom` / `-v` / `--lf` | tests |
| `pytest --cov=src` (`pytest-cov`) | couverture |
| `pre-commit install` / `pre-commit run -a` | hooks git |
| `python3 -m build` | sdist + wheel dans `dist/` |
| `pip install .` puis `venv/bin/monoutil` | via `[project.scripts]` |

```python
def test_selection(tmp_path, monkeypatch, caplog):
    (tmp_path / "a.log").write_text("ERROR x\n")
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setattr(subprocess, "run",
        lambda *a, **k: subprocess.CompletedProcess(a, 0, "ok", ""))
    with pytest.raises(ValueError):
        parser("bidon")
    assert "absent" in caplog.text     # logging -> caplog, pas capsys
@pytest.mark.parametrize("v,att", [(0, "a"), (1, "b")])
```

```ini
# /etc/systemd/system/outil.service
[Service]
Type=oneshot
ExecStart=/opt/factura/venv/bin/outil --config /etc/factura/outil.yaml
WorkingDirectory=/opt/factura
Environment=PYTHONUNBUFFERED=1 LANG=C.UTF-8
StandardError=journal
SyslogIdentifier=outil
SuccessExitStatus=1 2    # un code verdict n'est pas une panne
```

### Quand quoi

| Situation | Outil |
|---|---|
| Enchaîner des commandes, < 100 lignes, sans état | bash |
| JSON/YAML/API, structures de données, tests unitaires | Python |
| Décrire un état sur N machines, idempotence, `--check` | Ansible |
| Plus d'un `jq`, ou > 2 tableaux associatifs corrélés | Python |
| Long-running, réseau, retries, parallélisme | Python |
| Un `tar \| ssh` ou un `for` sur `ls` | bash, sans hésiter |

::: piege
* `subprocess.run("cmd " + fichier, shell=True)` : espace, `;`, `$` dans
  le nom = commande cassée ou injection. Liste d'arguments, point.
* Oublier `check=True` : la commande échoue, le script continue et dit OK.
* `except:` ou `except Exception: pass` : masque l'erreur réseau, attrape
  aussi `SystemExit` et `KeyboardInterrupt`.
* `def f(x, acc=[])` : la liste est partagée entre tous les appels.
* `open(p)` sans `encoding=` : dépend de la locale, donc du timer.
* `print` pour journaliser : stdout bufferisé, mélangé au résultat.
* Chemin relatif dans un timer : `WorkingDirectory` ou `Path(__file__)`.
* `pip install` sans version : le déploiement de mars ≠ celui d'avril.
* `#!/usr/bin/env python3` sous systemd = le python **système**, sans les
  paquets du venv : `ExecStart=/chemin/venv/bin/python`.
* `liste[-0:]` = toute la liste ; `time.time()` pour une durée ; `datetime`
  naïf comparé à un aware ; YAML lit `true`/`no`/`1.0` comme non-chaînes.
* Descripteurs jamais fermés (`open()` sans `with`) : `Too many open files`.
:::

::: astuce
* `python3 -m venv v && v/bin/pip install -r requirements.txt` : deux
  lignes, reproductibles, sans activer.
* `python3 -m json.tool`, `python3 -m http.server`, `python3 -m calendar` :
  des outils gratuits.
* `python3 -X dev script.py` : avertit sur les fichiers non fermés.
* `ruff check --select ALL --statistics .` pour voir ce que tu ignores.
* `ls -l /proc/PID/fd | wc -l` : combien de fichiers ouverts, en direct.
:::

---

## Proxmox (qm / pvesh)

| Commande | Effet |
|---|---|
| `qm list` / `pct list` | VM / conteneurs LXC |
| `qm status 9002` / `qm config 9002` | état / configuration |
| `qm start 9002` / `qm shutdown 9002 --timeout 60` / `qm stop 9002` | propre / brutal |
| `qm reboot 9002` / `qm reset 9002` | redémarre / reset matériel |
| `qm snapshot 9002 avant-lab18 --description "avant Docker"` | snapshot |
| `qm listsnapshot 9002` / `qm rollback 9002 snap-clean` / `qm delsnapshot 9002 x` | gestion |
| `qm clone 9100 9110 --name ci-test --full 1` | clone complet |
| `qm template 9100` | transforme en template (irréversible) |
| `qm set 9110 --memory 2048 --cores 2` | ressources |
| `qm set 9110 --ipconfig0 ip=10.10.10.110/24,gw=10.10.10.1` | cloud-init réseau |
| `qm set 9110 --sshkeys /root/keys/mathieu.pub --ciuser mathieu` | cloud-init identité |
| `qm set 9110 --cicustom user=local:snippets/ci.yaml` | user-data perso |
| `qm cloudinit dump 9110 user` | user-data généré |
| `qm cloudinit update 9110` | régénère l'ISO cidata |
| `qm disk resize 9110 scsi0 +5G` | agrandit (jamais réduit) |
| `qm set 9003 --scsi1 local-lvm:5` | ajoute un disque de 5 Go |
| `qm disk import 9100 image.img local-lvm` | importe une image cloud |
| `qm agent 9110 ping` / `qm guest exec 9110 -- hostname` | agent QEMU |
| `qm guest cmd 9110 network-get-interfaces` | IP via l'agent |
| `qm terminal 9110` / `qm monitor 9110` | console série / moniteur QEMU |
| `qm unlock 9110` | verrou après tâche interrompue |
| `qm destroy 9110 --purge` | détruit, disques compris |
| `qm migrate 9110 pve2 --online` | migration |
| `pvesh get /nodes/pve/qemu --output-format json \| jq` | liste par API |
| `pvesh get /nodes/pve/qemu/9110/status/current` | état |
| `pvesh create /nodes/pve/qemu/9100/clone --newid 9111 --name t --full 1` | clone |
| `pvesh set /nodes/pve/qemu/9111/config --memory 1024` | modifie |
| `pvesh create /nodes/pve/qemu/9111/status/start` | démarre |
| `pvesh delete /nodes/pve/qemu/9111 --purge 1` | supprime |
| `pvesh get /nodes/pve/tasks --limit 10` | tâches (UPID) |
| `pvesh get /nodes/pve/storage` / `pvesm status` | stockages |
| `pveum user token add terraform@pve tofu --privsep 0` | token API |
| `pveum acl modify / --users terraform@pve --roles PVEVMAdmin` | droits |
| `cat /etc/pve/qemu-server/9110.conf` | fichier de conf brut |
| `ls /var/lib/vz/snippets/` | snippets (activer `snippets` sur `local`) |

Depuis `lab-adm` :

```bash
curl -sk -H 'Authorization: PVEAPIToken=terraform@pve!tofu=<uuid>' \
  https://10.10.10.1:8006/api2/json/nodes/pve/qemu | jq '.data[].name'
```

::: piege
* `qm rollback` détruit l'état courant : snapshot avant, pas après.
* Snapshot avec RAM sur une VM active = long ; sans RAM = comme un reboot.
* Clone lié (`--full 0`) dépend du template : impossible de le supprimer.
* `qm set --cicustom` sans le contenu `snippets` activé sur le stockage.
* Une VM `locked` après une tâche coupée : `qm unlock`, puis vérifie.
:::

::: astuce
* `qm snapshot 9002 avant-labXX && ...` — le réflexe avant tout lab destructeur.
* `qm guest exec 9110 -- cloud-init status` — sans SSH.
* `pvesh get /cluster/resources --type vm` — toutes les VM, tous les nœuds.
:::

---

## Diagnostic : la checklist des 60 secondes

```bash
uptime ; nproc                         # charge vs cœurs, tendance
dmesg -T | tail -40                    # OOM, I/O error, link, MCE
journalctl -p err -b --no-pager | tail -30
vmstat 1 5                             # b, si/so, wa, st
mpstat -P ALL 1 3                      # un cœur ? %steal ?
pidstat 1 3                            # qui
iostat -xz 1 3                         # await, %util
free -m                                # available
df -h ; df -i                          # plein ? inodes ?
sar -n DEV 1 3 ; ss -s                 # réseau, sockets
ss -tulpn                              # qui écoute, où
systemctl --failed                     # unités en échec
top -b -n1 | head -20
```

| Question | Commande qui tranche |
|---|---|
| Ça monte ou ça descend ? | `uptime` (1 / 5 / 15) |
| CPU ou disque ? | `vmstat` : `wa` haut et `b` > 0 = disque |
| Mémoire ? | `free -m` `available` ; `vmstat` `si/so` |
| L'hyperviseur ? | `mpstat` `%steal` |
| Qui ? | `pidstat 1`, `top -o %CPU`, `iotop -oPa` |
| Bloqué ? | `ps -eo pid,stat,wchan:20,cmd \| awk '$2 ~ /D/'` |
| Disque plein ? | `df -h` / `df -i` / `du -xh --max-depth=1 /` / `lsof +L1` |
| Le service ? | `systemctl status x`, `journalctl -u x -n 100` |
| Il écoute ? | `ss -tulpn \| grep :PORT` (`0.0.0.0` vs `127.0.0.1`) |
| Il répond ? | `curl -sS -o /dev/null -w '%{http_code}\n' URL` |
| Le pare-feu ? | `nft list ruleset`, `ufw status numbered` |
| Le DNS ? | `getent hosts x`, `dig x`, `resolvectl status` |
| La route ? | `ip route get 10.10.10.12`, `ping`, `traceroute -n` |
| Qu'est-ce qui a changé ? | `find /etc -mmin -120`, `journalctl --since -2h`, `last`, Git |
| Depuis quand ? | `journalctl -u x --since yesterday -p warning` |
| Certificat ? | `openssl s_client -connect h:443 </dev/null 2>/dev/null \| openssl x509 -noout -dates` |

Règles : une modification à la fois, tout noter (heure, commande, résultat),
collecter avant de redémarrer, remettre en place ce qui n'a pas aidé.

---

## Codes, signaux, ports, permissions

### Signaux

| Signal | Sens |
|---|---|
| 1 `HUP` | recharge la conf (démons), fin de terminal |
| 2 `INT` | `Ctrl-C` |
| 3 `QUIT` | `Ctrl-\`, core dump |
| 9 `KILL` | non interceptable, pas de nettoyage |
| 15 `TERM` | arrêt propre, défaut de `kill` |
| 18 `CONT` / 19 `STOP` | reprend / gèle (non interceptable) |
| 20 `TSTP` | `Ctrl-Z` |
| 10 `USR1` / 12 `USR2` | réservés à l'application (nginx : réouvre les logs) |
| 13 `PIPE` | écriture dans un tube fermé |
| 14 `ALRM` | minuteur |
| 17 `CHLD` | un fils s'est terminé |

`kill -l`, `kill -TERM PID`, `kill -9 PID` en dernier recours, `pkill -HUP -x nginx`,
`systemctl kill -s HUP x`.

### Codes de sortie

| Code | Sens |
|---|---|
| 0 | succès |
| 1 | erreur générale |
| 2 | mauvais usage d'un builtin, `grep` sans résultat = 1, erreur = 2 |
| 126 | trouvé mais non exécutable |
| 127 | commande introuvable |
| 128+n | tué par le signal n : 130 `INT`, 137 `KILL`/OOM, 143 `TERM`, 139 `SEGV` |
| 255 | erreur ssh (pas la commande distante) |
| curl 6 / 7 / 28 / 35 / 60 | résolution / refus / timeout / TLS / certificat |
| ansible 0 / 2 / 4 | ok / tâche échouée / hôte injoignable |
| docker 125 | erreur du démon |
| apt 100 | échec d'installation |

### Ports standards

| Port | Service |
|---|---|
| 22 | SSH |
| 25 / 465 / 587 | SMTP / SMTPS / submission |
| 53 | DNS (TCP et UDP) |
| 67 / 68 | DHCP |
| 80 / 443 | HTTP / HTTPS |
| 110 / 143 / 993 / 995 | POP3 / IMAP / IMAPS / POP3S |
| 123 | NTP |
| 161 / 162 | SNMP / traps |
| 389 / 636 | LDAP / LDAPS |
| 514 / 10514 | syslog UDP / TCP (lab) |
| 2375 / 2376 | Docker API (clair / TLS) |
| 3000 | Gitea, Grafana |
| 3306 / 5432 | MySQL / PostgreSQL |
| 5000 | registre Docker |
| 6379 | Redis |
| 6443 | Kubernetes API |
| 8006 | Proxmox |
| 9090 / 9093 / 9100 | Prometheus / Alertmanager / node_exporter |
| 3100 | Loki |
| 10250 | kubelet |
| 30000–32767 | NodePort |
| 32768–60999 | ports éphémères Linux |

### Permissions

| Octal | Symbolique | Usage |
|---|---|---|
| 400 | `r--------` | clé privée (`-` = illisible) |
| 600 | `rw-------` | `id_ed25519`, `authorized_keys`, `.vault_pass` |
| 640 | `rw-r-----` | journaux applicatifs, `shadow` (root:shadow) |
| 644 | `rw-r--r--` | fichiers de conf, `logrotate.d/*` |
| 700 | `rwx------` | `~/.ssh`, `/root` |
| 750 | `rwxr-x---` | répertoire d'équipe |
| 755 | `rwxr-xr-x` | scripts, répertoires publics |
| 1777 | `rwxrwxrwt` | `/tmp` (sticky) |
| 2775 | `rwxrwsr-x` | répertoire partagé setgid |
| 4755 | `rwsr-xr-x` | SUID (`passwd`, `sudo`) |

`umask 022` → 755 / 644 ; `umask 027` → 750 / 640 ; `umask 077` → 700 / 600.

### Sévérités syslog

| Code | Nom | Sens |
|---|---|---|
| 0 | `emerg` | système inutilisable |
| 1 | `alert` | action immédiate |
| 2 | `crit` | critique |
| 3 | `err` | erreur |
| 4 | `warning` | anomalie sans échec |
| 5 | `notice` | normal mais notable |
| 6 | `info` | nominal |
| 7 | `debug` | trace |

Facilités : 0 `kern`, 1 `user`, 3 `daemon`, 4 `auth`, 9 `cron`,
10 `authpriv`, 16–23 `local0`–`local7`. `journalctl -p 3` = `err` et plus.

### Codes HTTP

| Code | Sens |
|---|---|
| 200 / 201 / 204 | OK / créé / sans contenu |
| 301 / 302 / 304 | redirection permanente / temporaire / non modifié |
| 400 / 401 / 403 / 404 | requête invalide / non authentifié / interdit / absent |
| 405 / 408 / 413 / 429 | méthode / timeout client / trop gros / trop de requêtes |
| 500 | erreur applicative |
| 502 | proxy : backend injoignable ou réponse invalide |
| 503 | service indisponible, maintenance, surcharge |
| 504 | proxy : backend trop lent |

### États TCP

| État | Sens |
|---|---|
| `LISTEN` | port en écoute |
| `SYN-SENT` / `SYN-RECV` | ouverture en cours (client / serveur) |
| `ESTAB` | connexion établie |
| `FIN-WAIT-1/2` | fermeture locale en cours |
| `CLOSE-WAIT` | le distant a fermé, l'application locale n'a pas encore fermé (fuite) |
| `LAST-ACK` | fermeture passive presque finie |
| `TIME-WAIT` | attente 2×MSL après fermeture active, normal côté client |
| `CLOSED` | rien |

Beaucoup de `CLOSE-WAIT` = l'application ne ferme pas ses sockets ;
beaucoup de `TIME-WAIT` = normal sur un client ou un proxy actif
(`ss -tan state time-wait | wc -l`).
