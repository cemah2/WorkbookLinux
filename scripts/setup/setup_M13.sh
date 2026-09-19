#!/usr/bin/env bash
# setup_M13.sh — prépare le terrain du module 13 (réseau Linux avancé)
# À lancer avec sudo sur CHAQUE VM concernée (lab-adm, lab-web, lab-db,
# lab-ops). Le script détecte l'hôte. Idempotent.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
BASE="$LAB_HOME/lab13"
HOSTN="$(hostname -s)"
SAUV=/root/.m13-backup
mkdir -p "$SAUV"

echo "== Préparation du module 13 =="
echo "   hôte        : $HOSTN"
echo "   utilisateur : $LAB_USER"

# ---------------------------------------------------------------------
# 1. Paquets
# ---------------------------------------------------------------------
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  PKGS="iproute2 nftables conntrack tcpdump ethtool iperf3 wireguard-tools \
        bind9-dnsutils python3 mtr-tiny curl netcat-openbsd"
  case "$HOSTN" in
    lab-ops) PKGS="$PKGS unbound bind9 bind9-utils" ;;
    lab-adm) PKGS="$PKGS bind9 bind9-utils" ;;
  esac
  # shellcheck disable=SC2086
  apt-get install -y -qq $PKGS >/dev/null
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y -q iproute nftables conntrack-tools tcpdump ethtool iperf3 \
    wireguard-tools bind-utils python3 mtr curl nmap-ncat >/dev/null
fi

# BIND ne doit pas démarrer tant que la configuration n'est pas écrite :
# sur lab-ops et lab-adm, on l'arrête (il écoute sur "any" par défaut).
if [ "$HOSTN" = lab-ops ] || [ "$HOSTN" = lab-adm ]; then
  systemctl stop named 2>/dev/null || true
  # le résolveur du module 12 occupe 10.10.10.10:53 : le secondaire BIND
  # doit pouvoir le prendre
  if [ "$HOSTN" = lab-adm ] && systemctl is-active -q dnsmasq 2>/dev/null; then
    echo "dnsmasq était actif (module 12)" > "$SAUV/dnsmasq.was-active"
    systemctl disable --now dnsmasq
    echo "   dnsmasq (module 12) arrêté : le port 53 est libre pour BIND"
  fi
fi
if [ "$HOSTN" = lab-ops ]; then
  systemctl stop unbound 2>/dev/null || true
  mkdir -p /etc/bind/zones /var/log/named
  chown bind:bind /var/log/named 2>/dev/null || true
  # adresse de service du résolveur, volatile (L13.4 la rend persistante)
  ip addr show dev ens18 2>/dev/null | grep -q '10\.10\.10\.53/24' \
    || ip addr add 10.10.10.53/24 dev ens18 2>/dev/null || true
  echo "   10.10.10.53/24 posée sur ens18 (volatile)"
fi

# ---------------------------------------------------------------------
# 2. Bac à sable de l'apprenant
# ---------------------------------------------------------------------
mkdir -p "$BASE"/{bin,nft,dns,www/t1,www/t2,rapports,docs,wg}

# --- pages servies par les "conteneurs" -------------------------------
cat > "$BASE/www/index.html" <<'EOF'
<html><body><h1>c1 : servi depuis le netns c1 (172.20.0.11:8000)</h1>
<p>Si tu lis ceci depuis lab-web via 10.10.10.10:8080, le DNAT fonctionne.</p>
</body></html>
EOF
printf '<h1>t1-web (locataire 1)</h1>\n' > "$BASE/www/t1/index.html"
printf '<h1>t2-web (locataire 2)</h1>\n' > "$BASE/www/t2/index.html"

# --- squelette minidocker.sh -----------------------------------------
[ -f "$BASE/bin/minidocker.sh" ] || cat > "$BASE/bin/minidocker.sh" <<'EOF'
#!/usr/bin/env bash
# minidocker.sh — up | down | status
# L13.1 : trois netns (c1, c2, c3) sur un bridge br-lab (172.20.0.1/24),
# NAT de sortie via ens18, publication 10.10.10.10:8080 -> c1:8000.
# Doit être IDEMPOTENT : relancer "up" ne doit rien casser ni dupliquer.
set -euo pipefail
BR=br-lab; NET=172.20.0; WAN=ens18
NFT=/home/mathieu/lab13/nft/minidocker.nft
WWW=/home/mathieu/lab13/www
STATE=/run/minidocker.ipfwd     # valeur d'origine de ip_forward

up() {
  # TODO 1 : bridge $BR, adresse $NET.1/24, up
  # TODO 2 : pour i in 1 2 3 : netns c$i, veth (bout "eth0" dans le netns),
  #          bout hôte "veth-c$i" esclave du bridge, lo up, adresse
  #          $NET.1$i/24, route par défaut via $NET.1
  # TODO 3 : sauvegarder ip_forward dans $STATE, le mettre à 1
  # TODO 4 : nft -f "$NFT"
  # TODO 5 : lancer python3 -m http.server 8000 dans c1 (répertoire $WWW)
  :
}
down() {
  # TODO : tout défaire (netns, bridge, tables nftables, ip_forward)
  :
}
status() {
  # TODO : netns, ports du bridge, fdb, ip_forward, règles nat + compteurs
  :
}
case "${1:-}" in
  up) up ;; down) down ;; status) status ;;
  *) echo "usage: $0 up|down|status" >&2; exit 2 ;;
esac
EOF
chmod 755 "$BASE/bin/minidocker.sh"

# --- squelette nftables ----------------------------------------------
[ -f "$BASE/nft/minidocker.nft" ] || cat > "$BASE/nft/minidocker.nft" <<'EOF'
#!/usr/sbin/nft -f
# minidocker.nft — L13.1
# Idiome rechargeable : déclarer la table vide (créée si absente), la vider,
# puis la définir. Le fichier est appliqué en une seule transaction.
table ip nat {}
table inet filter {}
flush table ip nat
flush table inet filter

table ip nat {
  chain prerouting {
    type nat hook prerouting priority -100; policy accept;
    # TODO : dnat 8080 -> 172.20.0.11:8000 (avec counter)
  }
  chain postrouting {
    type nat hook postrouting priority 100; policy accept;
    # TODO : masquerade pour 172.20.0.0/24 en sortie par ens18 (avec counter)
  }
}

table inet filter {
  chain forward {
    type filter hook forward priority 0; policy drop;
    # TODO : established,related ; invalid ; br-lab -> ens18 ;
    #        trafic DNATé ; log "fwd-drop: " puis drop
  }
}
EOF

[ -f "$BASE/nft/input.nft" ] || cat > "$BASE/nft/input.nft" <<'EOF'
#!/usr/sbin/nft -f
# input.nft — E13.11 : pare-feu stateful minimal pour lab-adm
# Charger avec : sudo nft -c -f input.nft (vérification) puis nft -f
flush ruleset
table inet filter {
  set admin {
    type ipv4_addr
    flags interval
    # TODO : elements = { ... }
  }
  chain input {
    type filter hook input priority 0; policy drop;
    # TODO
  }
}
EOF

# --- squelettes DNS --------------------------------------------------
cat > "$BASE/dns/README.txt" <<'EOF'
Squelettes du lab L13.4. Rien n'est appliqué automatiquement.
  named.conf.options.primary   -> /etc/bind/named.conf.options (lab-ops)
  named.conf.local.primary     -> /etc/bind/named.conf.local   (lab-ops)
  db.lab.local                 -> /etc/bind/zones/db.lab.local (lab-ops)
  db.10.10.10                  -> /etc/bind/zones/db.10.10.10  (lab-ops)
  named.conf.options.secondary -> /etc/bind/named.conf.options (lab-adm)
  named.conf.local.secondary   -> /etc/bind/named.conf.local   (lab-adm)
  unbound-lab.conf             -> /etc/unbound/unbound.conf.d/lab.conf
Valide avant de démarrer : named-checkconf -z, named-checkzone,
unbound-checkconf. Résolveur : 10.10.10.53 ; ns1 : 10.10.10.14 ;
ns2 : 10.10.10.10.
EOF

cat > "$BASE/dns/named.conf.options.primary" <<'EOF'
options {
    directory "/var/cache/bind";
    listen-on { 10.10.10.14; };
    listen-on-v6 { none; };
    recursion no;
    allow-query { any; };
    allow-transfer { none; };
    dnssec-validation no;
    notify explicit;
};
EOF

cat > "$BASE/dns/named.conf.local.primary" <<'EOF'
zone "lab.local" {
    type primary;
    file "/etc/bind/zones/db.lab.local";
    allow-transfer { 10.10.10.10; };
    also-notify { 10.10.10.10; };
};
zone "10.10.10.in-addr.arpa" {
    type primary;
    file "/etc/bind/zones/db.10.10.10";
    allow-transfer { 10.10.10.10; };
    also-notify { 10.10.10.10; };
};
EOF

cat > "$BASE/dns/db.lab.local" <<'EOF'
$TTL 3600
$ORIGIN lab.local.
@       IN  SOA  ns1.lab.local. hostmaster.lab.local. (
            2026091901 ; serial AAAAMMJJnn -- A INCREMENTER a chaque modif
            3600       ; refresh
            900        ; retry
            1209600    ; expire
            300 )      ; TTL negatif
        IN  NS   ns1.lab.local.
        IN  NS   ns2.lab.local.
; TODO : MX, TXT, SRV
ns1     IN  A    10.10.10.14
ns2     IN  A    10.10.10.10
; TODO : A et AAAA (fd00:10:10:10::<octet>) des sept VM, CNAME www, A mail
EOF

cat > "$BASE/dns/db.10.10.10" <<'EOF'
$TTL 3600
$ORIGIN 10.10.10.in-addr.arpa.
@   IN  SOA  ns1.lab.local. hostmaster.lab.local. (
        2026091901 3600 900 1209600 300 )
    IN  NS   ns1.lab.local.
    IN  NS   ns2.lab.local.
; TODO : un PTR par VM (10 -> lab-adm.lab.local. ... 16 -> lab-virt.lab.local.)
EOF

cat > "$BASE/dns/named.conf.options.secondary" <<'EOF'
options {
    directory "/var/cache/bind";
    listen-on { 10.10.10.10; };
    listen-on-v6 { none; };
    recursion no;
    allow-query { any; };
    allow-transfer { none; };
    dnssec-validation no;
};
EOF

cat > "$BASE/dns/named.conf.local.secondary" <<'EOF'
zone "lab.local" {
    type secondary;
    primaries { 10.10.10.14; };
    file "db.lab.local";
};
zone "10.10.10.in-addr.arpa" {
    type secondary;
    primaries { 10.10.10.14; };
    file "db.10.10.10";
};
EOF

cat > "$BASE/dns/unbound-lab.conf" <<'EOF'
# /etc/unbound/unbound.conf.d/lab.conf — résolveur récursif du lab
server:
    interface: 127.0.0.1
    interface: 10.10.10.53
    access-control: 127.0.0.0/8 allow
    access-control: 10.10.10.0/24 allow
    do-ip6: no
    # TODO : prefetch, qname-minimisation, hide-identity, hide-version
    # TODO : domain-insecure pour lab.local et 10.in-addr.arpa
    # TODO : local-zone: "10.in-addr.arpa." nodefault
    # TODO : private-domain / private-address

# TODO : deux stub-zone (lab.local, 10.10.10.in-addr.arpa) vers ns1 puis ns2
EOF

# --- extrait docker network inspect (L13.1 étape 9) -------------------
cat > "$BASE/docs/docker-network-inspect.json" <<'EOF'
[
    {
        "Name": "bridge",
        "Driver": "bridge",
        "IPAM": {
            "Config": [ { "Subnet": "172.17.0.0/16", "Gateway": "172.17.0.1" } ]
        },
        "Containers": {
            "3f1c2a": {
                "Name": "web",
                "MacAddress": "02:42:ac:11:00:02",
                "IPv4Address": "172.17.0.2/16"
            }
        },
        "Options": {
            "com.docker.network.bridge.default_bridge": "true",
            "com.docker.network.bridge.enable_icc": "true",
            "com.docker.network.bridge.enable_ip_masquerade": "true",
            "com.docker.network.bridge.host_binding_ipv4": "0.0.0.0",
            "com.docker.network.bridge.name": "docker0",
            "com.docker.network.driver.mtu": "1500"
        }
    }
]
EOF

# --- gabarits de rapports --------------------------------------------
mk_rapport() { # mk_rapport <fichier> <titre>
  [ -f "$BASE/rapports/$1" ] || printf '# %s\n\n<!-- à compléter -->\n' "$2" \
    > "$BASE/rapports/$1"
}
mk_rapport minidocker.md     "L13.1 — mini-Docker : hairpin, trace, conntrack"
mk_rapport policy-routing.md "L13.2 — policy routing : route asymétrique"
mk_rapport overlay.md        "L13.3 — VXLAN / WireGuard : mesures iperf3"
mk_rapport dns.md            "L13.4 — DNS du lab"
mk_rapport bonding.md        "L13.5 — bonding : bascule observée"
mk_rapport minicloud.md      "D13 — minicloud"

# --- squelette du défi -----------------------------------------------
[ -f "$BASE/bin/minicloud.sh" ] || cat > "$BASE/bin/minicloud.sh" <<'EOF'
#!/usr/bin/env bash
# minicloud.sh — up | down | status | test   (D13)
# Deux locataires (br-t1 10.100.1.0/24, br-t2 10.100.2.0/24), un netns
# routeur "rtr" (10.100.1.1, 10.100.2.1, transit 10.100.0.2/30), double NAT,
# publication par map nftables (8081 -> t1-web, 8082 -> t2-web).
set -euo pipefail
# TODO
case "${1:-}" in
  up|down|status|test) "$1" ;;
  *) echo "usage: $0 up|down|status|test" >&2; exit 2 ;;
esac
EOF
chmod 755 "$BASE/bin/minicloud.sh"

chown -R "$LAB_USER:$LAB_USER" "$BASE"

# ---------------------------------------------------------------------
# 3. Rappels utiles
# ---------------------------------------------------------------------
echo
echo "Préparation terminée : $BASE"
case "$HOSTN" in
  lab-adm)
    if ufw status 2>/dev/null | grep -q 'Status: active'; then
      echo "ATTENTION : ufw est actif, il interférera avec les labs netfilter."
    fi
    echo "Règles nftables présentes : $(nft list tables 2>/dev/null | wc -l) table(s)"
    ;;
  lab-ops)
    echo "Unbound et BIND sont installés mais ARRÊTÉS : configure-les (L13.4)."
    ;;
esac
