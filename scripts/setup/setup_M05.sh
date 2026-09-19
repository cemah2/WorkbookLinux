#!/usr/bin/env bash
# setup_M05.sh — prépare les jeux de données du module 05 (traitement de texte)
# Idempotent : les données sont générées par un PRNG à graine fixe, donc
# relancer le script réécrit exactement les mêmes fichiers (mêmes chiffres,
# mêmes corrigés). C'est volontaire : ça sert aussi de « reset » après un
# sed -i malheureux.
set -euo pipefail

BASE="$HOME/lab05"

echo "== Préparation du module 05 dans $BASE =="

mkdir -p "$BASE"/{rapports,archives,conf,encodages,bin}

# Le générateur commun : un LCG de Lehmer (MINSTD) écrit à la main.
# On n'utilise PAS rand()/srand() d'awk : mawk (Ubuntu par défaut) et gawk
# ne donnent pas la même suite, les corrigés ne seraient plus reproductibles.
LCG='
function rnd(   ) { seed = (seed * 16807) % 2147483647; return seed / 2147483647 }
function irand(n) { return int(rnd() * n) }
function pick(t, n) { return t[irand(n)] }
'

# ---------------------------------------------------------------------
# 1. access.log nginx (format combined + $request_time)
# ---------------------------------------------------------------------
echo "  -> access.log (7200 lignes)"
awk "$LCG"'
BEGIN {
  seed = 20260918
  n = 7200

  # --- pool dIP -------------------------------------------------------
  # clients ordinaires
  ni = 0
  ip[ni++] = "198.51.100.12"; ip[ni++] = "198.51.100.31"
  ip[ni++] = "198.51.100.47"; ip[ni++] = "198.51.100.88"
  ip[ni++] = "198.51.100.104"; ip[ni++] = "198.51.100.150"
  ip[ni++] = "203.0.113.5";  ip[ni++] = "203.0.113.19"
  ip[ni++] = "203.0.113.42"; ip[ni++] = "203.0.113.77"
  ip[ni++] = "192.0.2.14";   ip[ni++] = "192.0.2.61"
  ip[ni++] = "192.0.2.99";   ip[ni++] = "192.0.2.201"
  ip[ni++] = "198.51.100.12"; ip[ni++] = "203.0.113.5"   # un peu plus actifs
  nip = ni

  # --- agents ---------------------------------------------------------
  na = 0
  ua[na++] = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
  ua[na++] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36"
  ua[na++] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
  ua[na++] = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:129.0) Gecko/20100101 Firefox/129.0"
  ua[na++] = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"
  nua = na

  # --- referers -------------------------------------------------------
  nr = 0
  ref[nr++] = "https://shop.lab.local/"
  ref[nr++] = "https://shop.lab.local/catalogue"
  ref[nr++] = "https://www.google.com/"
  ref[nr++] = "-"
  ref[nr++] = "-"
  nref = nr

  # --- catalogue de pages ---------------------------------------------
  np = 0
  page[np++] = "/"; page[np++] = "/catalogue"; page[np++] = "/catalogue?cat=chaussures"
  page[np++] = "/catalogue?cat=vetements"; page[np++] = "/panier"
  page[np++] = "/compte"; page[np++] = "/recherche?q=veste"
  page[np++] = "/recherche?q=bottes"; page[np++] = "/cgu"
  npage = np

  ns = 0
  stat[ns++] = "/static/css/app.css"; stat[ns++] = "/static/js/app.js"
  stat[ns++] = "/static/js/vendor.js"; stat[ns++] = "/static/img/logo.png"
  stat[ns++] = "/static/img/banniere.jpg"; stat[ns++] = "/favicon.ico"
  nstat = ns

  nk = 0
  atk[nk++] = "/wp-login.php"; atk[nk++] = "/.env"
  atk[nk++] = "/admin/config.php"; atk[nk++] = "/phpmyadmin/index.php"
  atk[nk++] = "/.git/config"; atk[nk++] = "/vendor/phpunit/phpunit/eval-stdin.php"
  natk = nk

  t = 0                       # secondes depuis le 14/09/2026 00:00:00 +0200
  for (i = 0; i < n; i++) {
    # le trafic respire : creux la nuit, pic en fin de journée
    heure = int((t % 86400) / 3600)
    if (heure >= 9 && heure <= 12)      facteur = 0.55
    else if (heure >= 13 && heure <= 17) facteur = 0.50
    else if (heure >= 18 && heure <= 21) facteur = 0.40
    else if (heure >= 22 || heure <= 6)  facteur = 2.30
    else                                 facteur = 0.90
    t += 1 + int((1 + irand(140)) * facteur)
    jour = 14 + int(t / 86400); reste = t % 86400
    hh = int(reste / 3600); mm = int((reste % 3600) / 60); ss = reste % 60
    dt = sprintf("%02d/Sep/2026:%02d:%02d:%02d +0200", jour, hh, mm, ss)

    r = rnd()
    agent = ua[irand(nua)]
    referer = ref[irand(nref)]
    client = ip[irand(nip)]
    meth = "GET"

    if (r < 0.14) {                       # sonde de monitoring
      client = "10.10.10.14"; url = "/health"; code = 200
      octets = 17; rt = 0.001 + irand(4) / 1000
      agent = "kube-probe/1.29"; referer = "-"
    } else if (r < 0.17) {
      client = "10.10.10.14"; url = "/metrics"; code = 200
      octets = 18420 + irand(900); rt = 0.012 + irand(20) / 1000
      agent = "Prometheus/2.53.0"; referer = "-"
    } else if (r < 0.40) {                # assets statiques
      url = stat[irand(nstat)]
      code = (rnd() < 0.30) ? 304 : 200
      octets = (code == 304) ? 0 : 1200 + irand(180000)
      rt = 0.000 + irand(8) / 1000
    } else if (r < 0.62) {                # pages HTML
      url = page[irand(npage)]
      code = 200; octets = 2400 + irand(9000)
      rt = 0.040 + irand(260) / 1000
    } else if (r < 0.84) {                # API
      q = rnd()
      if (q < 0.30)      url = "/api/v1/orders?page=" (1 + irand(9))
      else if (q < 0.48) url = "/api/v1/orders/" (10000 + irand(4000))
      else if (q < 0.64) url = "/api/v1/customers?page=" (1 + irand(4))
      else if (q < 0.80) url = "/api/v1/products?page=" (1 + irand(12))
      else if (q < 0.92) { url = "/api/v1/cart/items"; meth = "POST" }
      else                 url = "/api/v1/reports/export?format=csv"
      s = rnd()
      if (s < 0.90)      code = 200
      else if (s < 0.94) code = 404
      else if (s < 0.97) code = 500
      else if (s < 0.99) code = 502
      else               code = 503
      octets = (code == 200) ? 500 + irand(45000) : 153 + irand(400)
      rt = 0.030 + irand(400) / 1000
      if (url ~ /reports\/export/) rt = 1.200 + irand(5200) / 1000
      if (code >= 500) rt = 0.800 + irand(9000) / 1000
      agent = (rnd() < 0.25) ? "python-requests/2.32.3" : agent
    } else if (r < 0.90) {                # authentification
      url = "/api/v1/auth/login"; meth = "POST"
      code = (rnd() < 0.72) ? 200 : 401
      octets = (code == 200) ? 312 : 173
      rt = 0.150 + irand(600) / 1000
    } else if (r < 0.96) {                # scans et bots
      client = "203.0.113.242"
      url = atk[irand(natk)]
      code = (rnd() < 0.55) ? 404 : 403
      octets = (code == 404) ? 153 : 162
      rt = 0.001 + irand(9) / 1000
      agent = "Mozilla/5.0 (compatible; zgrab/0.x)"
      referer = "-"
    } else if (r < 0.985) {               # crawlers
      client = "66.249.66.1"
      url = page[irand(npage)]
      code = 200; octets = 2400 + irand(9000)
      rt = 0.050 + irand(300) / 1000
      agent = "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
      referer = "-"
    } else {                              # divers 4xx utilisateurs
      url = "/produit/" (1000 + irand(600))
      code = (rnd() < 0.6) ? 404 : 410
      octets = 153; rt = 0.008 + irand(40) / 1000
      meth = (rnd() < 0.1) ? "HEAD" : "GET"
    }

    printf "%s - - [%s] \"%s %s HTTP/1.1\" %d %d \"%s\" \"%s\" %.3f\n",
      client, dt, meth, url, code, octets, referer, agent, rt
  }
}' > "$BASE/access.log"

# une rotation précédente, compressée (les mêmes requêtes, cinq jours plus tôt)
head -n 1200 "$BASE/access.log" \
  | awk '{ sub(/\[[0-9][0-9]\//, "[" sprintf("%02d", substr($4, 2, 2) - 5) "/") }1' \
  | gzip -n -9 > "$BASE/access.log.1.gz"

# ---------------------------------------------------------------------
# 2. Inventaire de serveurs (CSV)
# ---------------------------------------------------------------------
echo "  -> serveurs.csv (60 lignes) + serveurs-piege.csv"
awk "$LCG"'
BEGIN {
  seed = 424242
  OFS = ","
  print "hostname,env,role,os,vcpu,ram_go,disque_go,ip,site,cout_eur"

  nr_ = 0
  role[nr_++] = "web"; role[nr_++] = "api"; role[nr_++] = "db"
  role[nr_++] = "cache"; role[nr_++] = "worker"; role[nr_++] = "proxy"
  nrole = nr_

  ne_ = 0
  env[ne_++] = "prod"; env[ne_++] = "prod"; env[ne_++] = "prod"
  env[ne_++] = "preprod"; env[ne_++] = "dev"; env[ne_++] = "dev"
  nenv = ne_

  no = 0
  os[no++] = "Ubuntu 24.04"; os[no++] = "Ubuntu 24.04"
  os[no++] = "Ubuntu 22.04"; os[no++] = "Rocky 9.4"
  os[no++] = "Debian 12";    os[no++] = "Rocky 8.9"
  nos = no

  nst = 0
  site[nst++] = "paris"; site[nst++] = "paris"; site[nst++] = "lyon"
  site[nst++] = "francfort"
  nsite = nst

  for (i = 1; i <= 60; i++) {
    rl = role[irand(nrole)]
    ev = env[irand(nenv)]
    o  = os[irand(nos)]
    st = site[irand(nsite)]
    cpu = 2 * (1 + irand(8))
    ram = cpu * (2 + irand(3))
    dsk = 40 * (1 + irand(12))
    h = sprintf("%s-%s-%02d", rl, substr(ev, 1, 3), i)
    ipa = sprintf("10.%d.%d.%d", 20 + irand(4), irand(6), 10 + irand(200))
    cout = 12 * cpu + 4 * ram + 0.12 * dsk
    printf "%s,%s,%s,%s,%d,%d,%d,%s,%s,%.2f\n",
      h, ev, rl, o, cpu, ram, dsk, ipa, st, cout
  }
}' > "$BASE/serveurs.csv"

cat > "$BASE/serveurs-piege.csv" <<'CSV'
hostname,proprietaire,env,commentaire,cout_eur
web-pro-01,"Equipe Paiement, Lyon",prod,"migration prevue, Q4",184.00
db-pro-07,"Equipe Data",prod,"replique, ne pas arreter",412.50
api-dev-22,"Equipe Front, Paris",dev,"bac a sable",96.00
CSV

# ---------------------------------------------------------------------
# 3. Export JSON d'API (mêmes serveurs que le CSV, plus des métriques)
# ---------------------------------------------------------------------
echo "  -> api-inventaire.json"
# Généré À PARTIR du CSV : les deux fichiers décrivent forcément les mêmes hôtes.
awk "$LCG"'
BEGIN { FS = ","; seed = 20261005
  print "{"
  print "  \"meta\": {"
  print "    \"generated_at\": \"2026-09-18T06:00:00Z\","
  print "    \"source\": \"cmdb.lab.local/api/v2\","
  print "    \"page\": 1,"
  print "    \"per_page\": 100,"
  print "    \"total\": 60"
  print "  },"
  print "  \"results\": ["
}
NR > 1 {
    h = $1; ev = $2; rl = $3; o = $4
    cpu = $5; ram = $6; dsk = $7; ipa = $8; st = $9
    # au-delà du CSV : métriques et étiquettes
    cpupct = 5 + irand(90) + irand(100) / 100
    mempct = 20 + irand(78) + irand(100) / 100
    dskpct = 10 + irand(88)
    agent = sprintf("1.%d.%d", 6 + irand(4), irand(6))
    actif = (irand(100) < 92) ? "true" : "false"
    split(o, ov, " ")
    printf "    {\n"
    printf "      \"hostname\": \"%s\",\n", h
    printf "      \"env\": \"%s\",\n", ev
    printf "      \"role\": \"%s\",\n", rl
    printf "      \"ip\": \"%s\",\n", ipa
    printf "      \"site\": \"%s\",\n", st
    printf "      \"os\": { \"name\": \"%s\", \"version\": \"%s\" },\n", ov[1], ov[2]
    printf "      \"specs\": { \"vcpu\": %d, \"ram_go\": %d, \"disque_go\": %d },\n",
      cpu, ram, dsk
    printf "      \"metriques\": { \"cpu_pct\": %.2f, \"mem_pct\": %.2f, \"disque_pct\": %d },\n",
      cpupct, mempct, dskpct
    printf "      \"agent\": { \"version\": \"%s\", \"derniere_vue\": \"2026-09-18T0%d:%02d:00Z\" },\n",
      agent, 1 + irand(8), irand(60)
    printf "      \"tags\": ["
    ntag = 1 + irand(3)
    for (k = 0; k < ntag; k++) {
      tg = (k == 0) ? ((ev == "prod") ? "astreinte" : "hors-astreinte") : \
           ((irand(2) == 0) ? "sauvegarde-nuit" : "pci")
      printf "%s\"%s\"", (k ? ", " : ""), tg
    }
    printf "],\n"
    printf "      \"actif\": %s\n", actif
    printf "    }%s\n", (NR < 61) ? "," : ""
}
END { print "  ]"; print "}" }' "$BASE/serveurs.csv" > "$BASE/api-inventaire.json"

# ---------------------------------------------------------------------
# 4. Commandes commerciales (CSV chiffré, pour awk : sommes et moyennes)
# ---------------------------------------------------------------------
echo "  -> commandes.csv (400 lignes)"
awk "$LCG"'
BEGIN {
  seed = 7777
  print "date,region,commercial,produit,quantite,montant_eur"
  nrg = 0
  rg[nrg++] = "nord"; rg[nrg++] = "sud"; rg[nrg++] = "est"
  rg[nrg++] = "ouest"; rg[nrg++] = "idf"; rg[nrg++] = "idf"
  nregion = nrg
  nc = 0
  co[nc++] = "durand"; co[nc++] = "nguyen"; co[nc++] = "lopez"
  co[nc++] = "martin"; co[nc++] = "okoye"; co[nc++] = "bernard"
  ncom = nc
  npd = 0
  pd[npd++] = "licence-std"; pd[npd++] = "licence-pro"
  pd[npd++] = "support-or";  pd[npd++] = "support-argent"
  pd[npd++] = "formation";   pd[npd++] = "migration"
  nprod = npd
  for (i = 1; i <= 400; i++) {
    j = 1 + irand(30)
    m = 6 + irand(3)
    q = 1 + irand(12)
    p = pd[irand(nprod)]
    pu = (p == "migration") ? 2400 : (p == "formation") ? 850 : \
         ((p ~ /^support/) ? 390 : 129)
    printf "2026-%02d-%02d,%s,%s,%s,%d,%.2f\n",
      m, j, rg[irand(nregion)], co[irand(ncom)], p, q, q * pu * (0.9 + irand(21) / 100)
  }
}' > "$BASE/commandes.csv"

# ---------------------------------------------------------------------
# 5. Un /etc/passwd d'exemple (on ne travaille jamais sur le vrai)
# ---------------------------------------------------------------------
echo "  -> passwd.exemple"
cat > "$BASE/passwd.exemple" <<'PASSWD'
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin
sys:x:3:3:sys:/dev:/usr/sbin/nologin
sync:x:4:65534:sync:/bin:/bin/sync
man:x:6:12:man:/var/cache/man:/usr/sbin/nologin
www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
backup:x:34:34:backup:/var/backups:/usr/sbin/nologin
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
systemd-network:x:998:998:systemd Network Management:/:/usr/sbin/nologin
sshd:x:104:65534::/run/sshd:/usr/sbin/nologin
postgres:x:105:112:PostgreSQL administrator,,,:/var/lib/postgresql:/bin/bash
redis:x:106:113::/var/lib/redis:/usr/sbin/nologin
prometheus:x:107:114::/var/lib/prometheus:/usr/sbin/nologin
mathieu:x:1000:1000:Mathieu Teule,,,:/home/mathieu:/bin/bash
sabrina:x:1001:1001:Sabrina Kaci,Bureau 12,,:/home/sabrina:/bin/bash
karim:x:1002:1002:Karim Bouzid,,,:/home/karim:/bin/bash
elodie:x:1003:1003:Elodie Grangier,,,:/home/elodie:/bin/zsh
tom:x:1004:1004:Tom Marchand,,,:/home/tom:/bin/bash
ines:x:1005:1005:Ines Ferreira,,,:/home/ines:/bin/bash
paul:x:1006:1006:Paul Nkemdirim,,,:/home/paul:/bin/sh
julie:x:1007:1007:Julie Sorel,,,:/home/julie:/bin/bash
ancien-stagiaire:x:1008:1008:Compte a supprimer,,,:/home/ancien-stagiaire:/bin/bash
deploy:x:1500:1500:Compte de deploiement CI,,,:/srv/deploy:/bin/bash
jenkins:x:1501:1501:Jenkins agent,,,:/var/lib/jenkins:/bin/bash
sauvegarde:x:1502:1502:Robot de sauvegarde,,,:/srv/sauvegarde:/bin/false
supervision:x:1503:1503:Compte Zabbix,,,:/srv/supervision:/bin/bash
appfactura:x:1600:1600:Service facturation,,,:/srv/factura:/usr/sbin/nologin
appstock:x:1601:1601:Service stock,,,:/srv/stock:/usr/sbin/nologin
appmail:x:1602:1602:Service mail,,,:/srv/mail:/bin/false
PASSWD

# ---------------------------------------------------------------------
# 6. Journal applicatif multi-lignes avec piles d'appel
# ---------------------------------------------------------------------
echo "  -> app.log (journal applicatif + stack traces)"
awk "$LCG"'
function ts(t,   hh, mm, ss, ms) {
  hh = int(t / 3600) % 24; mm = int(t / 60) % 60; ss = t % 60
  ms = irand(1000)
  return sprintf("2026-09-18 %02d:%02d:%02d.%03d", hh, mm, ss, ms)
}
function frame(meth,   cl, p, n) {
  cl = lg[irand(nlg)]; n = split(cl, p, ".")
  printf "\tat %s.%s(%s.java:%d)\n", cl, meth, p[n], 40 + irand(400)
}
BEGIN {
  seed = 31337
  nt = 0
  th[nt++] = "http-nio-8080-exec-1"; th[nt++] = "http-nio-8080-exec-2"
  th[nt++] = "http-nio-8080-exec-3"; th[nt++] = "scheduler-1"
  th[nt++] = "kafka-consumer-0"
  nth = nt

  nl_ = 0
  lg[nl_++] = "fr.lab.factura.web.CommandeController"
  lg[nl_++] = "fr.lab.factura.service.PaiementService"
  lg[nl_++] = "fr.lab.factura.repo.ClientRepository"
  lg[nl_++] = "fr.lab.factura.batch.RelanceJob"
  lg[nl_++] = "org.springframework.web.servlet.DispatcherServlet"
  nlg = nl_

  nm = 0
  msg[nm++] = "commande %d validee pour le client %d"
  msg[nm++] = "appel du service de paiement (montant=%d.%02d EUR)"
  msg[nm++] = "cache client rafraichi, %d entrees"
  msg[nm++] = "relance envoyee a %d clients"
  msg[nm++] = "requete traitee en %d ms"
  nmsg = nm

  t = 6 * 3600
  for (i = 0; i < 1400; i++) {
    t += irand(45)
    stamp = ts(t)
    r = rnd()
    thread = th[irand(nth)]
    logger = lg[irand(nlg)]
    if (r < 0.62)      lvl = "INFO"
    else if (r < 0.80) lvl = "DEBUG"
    else if (r < 0.90) lvl = "WARN"
    else               lvl = "ERROR"

    if (lvl == "ERROR") {
      e = rnd()
      if (e < 0.45) {
        exc = "java.sql.SQLTransientConnectionException"
        det = "HikariPool-1 - Connection is not available, request timed out after 30000ms"
        cause = "java.net.SocketTimeoutException: connect timed out"
      } else if (e < 0.75) {
        exc = "java.lang.NullPointerException"
        det = sprintf("Cannot invoke \"fr.lab.factura.model.Client.getIban()\" because \"client\" is null")
        cause = ""
      } else if (e < 0.92) {
        exc = "fr.lab.factura.error.PaiementRefuseException"
        det = sprintf("paiement refuse par la banque (code=%d)", 51 + irand(5))
        cause = "java.io.IOException: HTTP 502 from https://psp.example.net/v2/charge"
      } else {
        exc = "java.lang.OutOfMemoryError"
        det = "Java heap space"
        cause = ""
      }
      printf "%s %s [%s] %s - echec du traitement de la requete %d\n",
        stamp, lvl, thread, logger, 40000 + irand(9000)
      printf "%s: %s\n", exc, det
      nfr = 4 + irand(5)
      for (f = 0; f < nfr; f++) frame((irand(2) ? "traiter" : "executer"))
      if (cause != "") {
        printf "Caused by: %s\n", cause
        nfr = 2 + irand(3)
        for (f = 0; f < nfr; f++) frame("appeler")
        print "\t... 23 more"
      }
    } else if (lvl == "WARN") {
      w = rnd()
      if (w < 0.4)
        printf "%s %s [%s] %s - pool de connexions a %d%% de sa capacite\n",
          stamp, lvl, thread, logger, 80 + irand(19)
      else if (w < 0.7)
        printf "%s %s [%s] %s - reponse lente du service stock (%d ms)\n",
          stamp, lvl, thread, logger, 1000 + irand(4000)
      else
        printf "%s %s [%s] %s - tentative %d/3 de reconnexion a la base\n",
          stamp, lvl, thread, logger, 1 + irand(3)
    } else {
      m = msg[irand(nmsg)]
      fmt = "%s %s [%s] %s - " m "\n"
      printf fmt, stamp, lvl, thread, logger, 100 + irand(9000), irand(100)
    }
  }
}' > "$BASE/app.log"

# ---------------------------------------------------------------------
# 7. Extrait de journal SSH (façon journalctl -o short-iso)
# ---------------------------------------------------------------------
echo "  -> journal-ssh.txt"
awk "$LCG"'
BEGIN {
  seed = 8642
  nu = 0
  usr[nu++] = "root"; usr[nu++] = "root"; usr[nu++] = "admin"
  usr[nu++] = "mathieu"; usr[nu++] = "postgres"; usr[nu++] = "oracle"
  usr[nu++] = "ubuntu"; usr[nu++] = "test"
  nusr = nu
  ni = 0
  bad[ni++] = "45.155.205.14"; bad[ni++] = "45.155.205.14"
  bad[ni++] = "45.155.205.14"; bad[ni++] = "185.220.101.7"
  bad[ni++] = "185.220.101.7"; bad[ni++] = "141.98.11.62"
  bad[ni++] = "92.63.197.5";   bad[ni++] = "218.92.0.31"
  nbad = ni
  ng = 0
  good[ng++] = "10.10.10.10"; good[ng++] = "10.10.10.14"
  good[ng++] = "198.51.100.12"
  ngood = ng

  t = 0
  for (i = 0; i < 900; i++) {
    t += 1 + irand(180)
    hh = int(t / 3600) % 24; mm = int(t / 60) % 60; ss = t % 60
    d = 17 + int(t / 86400)
    stamp = sprintf("2026-09-%02dT%02d:%02d:%02d+0200 lab-web sshd[%d]:",
      d, hh, mm, ss, 1000 + irand(9000))
    r = rnd()
    if (r < 0.70)
      printf "%s Failed password for %s%s from %s port %d ssh2\n",
        stamp, (irand(4) == 0) ? "invalid user " : "",
        usr[irand(nusr)], bad[irand(nbad)], 30000 + irand(30000)
    else if (r < 0.80)
      printf "%s Invalid user %s from %s port %d\n",
        stamp, usr[irand(nusr)], bad[irand(nbad)], 30000 + irand(30000)
    else if (r < 0.88)
      printf "%s Connection closed by authenticating user %s %s port %d [preauth]\n",
        stamp, usr[irand(nusr)], bad[irand(nbad)], 30000 + irand(30000)
    else if (r < 0.96)
      printf "%s Accepted publickey for mathieu from %s port %d ssh2: ED25519 SHA256:%d\n",
        stamp, good[irand(ngood)], 40000 + irand(20000), 100000 + irand(800000)
    else
      printf "%s pam_unix(sshd:session): session opened for user mathieu(uid=1000) by (uid=0)\n",
        stamp
  }
}' > "$BASE/journal-ssh.txt"

# ---------------------------------------------------------------------
# 8. YAML de services (pour yq)
# ---------------------------------------------------------------------
echo "  -> services.yaml"
cat > "$BASE/services.yaml" <<'YAML'
version: "3.9"
services:
  web:
    image: nginx:1.27-alpine
    replicas: 3
    ports:
      - "80:80"
      - "443:443"
    env:
      TZ: Europe/Paris
      APP_ENV: production
    limits:
      cpu: "1.0"
      memory: 512M
  api:
    image: registry.lab.local/factura/api:2.7.1
    replicas: 4
    ports:
      - "8080:8080"
    env:
      TZ: Europe/Paris
      APP_ENV: production
      DB_HOST: db-pro-07
    limits:
      cpu: "2.0"
      memory: 2048M
  worker:
    image: registry.lab.local/factura/worker:2.7.1
    replicas: 2
    ports: []
    env:
      TZ: Europe/Paris
      APP_ENV: production
    limits:
      cpu: "1.5"
      memory: 1024M
  db:
    image: postgres:16.4
    replicas: 1
    ports:
      - "5432:5432"
    env:
      TZ: Europe/Paris
      POSTGRES_DB: factura
    limits:
      cpu: "4.0"
      memory: 8192M
YAML

# ---------------------------------------------------------------------
# 9. Encodages et fins de ligne
# ---------------------------------------------------------------------
echo "  -> encodages/ (CRLF, latin-1, BOM)"
printf 'client;ville;commentaire\n1042;Orl\xe9ans;r\xe8glement diff\xe9r\xe9\n1043;Ch\xe2teauroux;client fid\xe8le\n1044;Besan\xe7on;\xe0 relancer\n' \
  > "$BASE/encodages/clients-latin1.csv"

printf '#!/usr/bin/env bash\r\nset -euo pipefail\r\n\r\nCIBLE=/srv/factura\r\nVERSION=2.7.1\r\n\r\necho "deploiement de $VERSION vers $CIBLE"\r\nsystemctl --version >/dev/null\r\n' \
  > "$BASE/encodages/deploiement.sh"
chmod +x "$BASE/encodages/deploiement.sh"

printf '\xef\xbb\xbfhostname,role\nweb-pro-01,web\napi-pro-02,api\n' \
  > "$BASE/encodages/export-tableur.csv"

# ---------------------------------------------------------------------
# 10. Deux configurations nginx pour diff / patch
# ---------------------------------------------------------------------
echo "  -> conf/ (diff et patch)"
cat > "$BASE/conf/shop.conf" <<'NGINX'
server {
    listen 80;
    server_name shop.lab.local;

    access_log /var/log/nginx/shop-access.log combined;
    error_log  /var/log/nginx/shop-error.log warn;

    client_max_body_size 8m;
    keepalive_timeout 65;

    location / {
        proxy_pass http://10.10.10.11:8080;
        proxy_set_header Host $host;
        proxy_read_timeout 30s;
    }

    location /static/ {
        root /srv/factura/public;
        expires 7d;
    }
}
NGINX

cat > "$BASE/conf/shop-propose.conf" <<'NGINX'
server {
    listen 80;
    listen 443 ssl http2;
    server_name shop.lab.local;

    ssl_certificate     /etc/ssl/lab/shop.crt;
    ssl_certificate_key /etc/ssl/lab/shop.key;

    access_log /var/log/nginx/shop-access.log combined;
    error_log  /var/log/nginx/shop-error.log warn;

    client_max_body_size 32m;
    keepalive_timeout 65;

    location / {
        proxy_pass http://10.10.10.11:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
    }

    location /static/ {
        root /srv/factura/public;
        expires 30d;
    }
}
NGINX

# ---------------------------------------------------------------------
# 11. Deux listes d'hôtes pour comm / join
# ---------------------------------------------------------------------
echo "  -> listes hosts-*.txt"
awk -F, 'NR > 1 { print $1 }' "$BASE/serveurs.csv" | sort > "$BASE/hosts-cmdb.txt"
# la supervision en connaît 52 sur 60, plus 4 qu'elle est seule à connaître
awk 'NR % 8 != 3' "$BASE/hosts-cmdb.txt" > "$BASE/hosts-supervision.txt"
printf 'vpn-pro-91\nmail-pro-92\nbastion-pro-93\nnas-pro-94\n' \
  >> "$BASE/hosts-supervision.txt"
sort -o "$BASE/hosts-supervision.txt" "$BASE/hosts-supervision.txt"

# ---------------------------------------------------------------------
# 12. Fichier tabulé pour join (coût par site)
# ---------------------------------------------------------------------
cat > "$BASE/sites.csv" <<'CSV'
site,datacenter,pays,contact
francfort,DC-FRA-2,DE,ops-de@lab.local
lyon,DC-LYS-1,FR,ops-fr@lab.local
paris,DC-PAR-3,FR,ops-fr@lab.local
CSV

# ---------------------------------------------------------------------
# 13. Outils d'exploitation utilisés par les Break & Fix (état sain)
# ---------------------------------------------------------------------
echo "  -> bin/ (scripts des Break & Fix, en état de marche)"

cat > "$BASE/bin/rapport-quotidien.sh" <<'SH'
#!/usr/bin/env bash
# rapport-quotidien.sh — répartition des codes HTTP d'une journée.
# Lancé chaque matin par cron. Argument : la date au format du journal.
set -eu

JOUR="${1:-18/Sep/2026}"
SRC="$HOME/lab05/access.log"
OUT="$HOME/lab05/rapports/quotidien.txt"

{
  echo "== Rapport du $JOUR =="
  grep -F "[$JOUR" "$SRC" \
    | awk '{ print $9 }' \
    | sort \
    | uniq -c \
    | sort -rn
} > "$OUT"
SH
chmod +x "$BASE/bin/rapport-quotidien.sh"

cat > "$BASE/bin/livrer.sh" <<'SH'
#!/usr/bin/env bash
# livrer.sh — contrôle la configuration avant de livrer. NE PAS MODIFIER.
set -euo pipefail

. "$HOME/lab05/conf/livraison.env"

if [ "$CIBLE" != "/srv/factura" ]; then
  printf 'cible inconnue : [%s]\n' "$CIBLE" >&2
  exit 2
fi
printf 'livraison de %s vers %s\n' "$VERSION" "$CIBLE"
SH
chmod +x "$BASE/bin/livrer.sh"

printf 'CIBLE=/srv/factura\nVERSION=2.7.1\nRESPONSABLE=mathieu\n' \
  > "$BASE/conf/livraison.env"

cat > "$BASE/bin/top-ip.sh" <<'SH'
#!/usr/bin/env bash
# top-ip.sh — classement des IP clientes les plus bavardes.
set -eu

SRC="${1:-$HOME/lab05/access.log}"

echo "== Top 10 des IP de $(basename "$SRC") =="
cut -d' ' -f1 "$SRC" | sort | uniq -c | sort -rn | head -10
echo "-- total de lignes : $(wc -l < "$SRC")"
SH
chmod +x "$BASE/bin/top-ip.sh"

echo
echo "Prêt. Contenu de $BASE :"
printf '  %-26s %s\n' \
  "access.log"            "$(wc -l < "$BASE/access.log") lignes, nginx combined + request_time" \
  "access.log.1.gz"       "rotation précédente, compressée" \
  "app.log"               "$(wc -l < "$BASE/app.log") lignes, journal applicatif + stack traces" \
  "journal-ssh.txt"       "$(wc -l < "$BASE/journal-ssh.txt") lignes, extrait journalctl -u ssh" \
  "serveurs.csv"          "inventaire CMDB, 60 hôtes" \
  "serveurs-piege.csv"    "le même, avec des virgules dans les champs" \
  "commandes.csv"         "400 lignes de ventes, pour les calculs awk" \
  "api-inventaire.json"   "export de l'API CMDB, pour jq" \
  "services.yaml"         "pile applicative, pour yq" \
  "passwd.exemple"        "copie de travail d'un /etc/passwd" \
  "encodages/"            "CRLF, latin-1, BOM" \
  "conf/"                 "deux versions d'un vhost nginx (diff/patch)" \
  "hosts-cmdb.txt"        "liste triée des hôtes de la CMDB" \
  "hosts-supervision.txt" "liste triée des hôtes supervisés"
echo
echo "Les données sont déterministes : relancer ce script redonne les mêmes"
echo "fichiers, donc les mêmes chiffres que le corrigé."
