#!/usr/bin/env bash
# setup_M15.sh — prépare le terrain du module 15
#                (nginx, PostgreSQL 16, Redis : services applicatifs)
# À lancer avec sudo, sur lab-web ET sur lab-db (il détecte le hostname).
# Idempotent : relançable sans effet de bord.
#
#   lab-web : nginx (conf d'origine, site default laissé en place), une
#             mini-API HTTP Python en DEUX instances (8001 et 8002) sous
#             systemd, un site statique de démonstration, une page de
#             maintenance, les outils client (curl, psql, redis-cli).
#   lab-db  : PostgreSQL 16 avec une base d'exemple (factura_demo, ~400 000
#             lignes, sans index utile : une requête lente est fournie),
#             Redis 7 en configuration d'origine, un simulateur d'application
#             Redis, des scripts de charge et de verrou.
#
# Il NE configure NI nginx (aucun vhost), NI pg_hba/listen_addresses, NI
# redis.conf : c'est le travail du module.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

HOST="${M15_HOST:-$(hostname -s)}"
LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6 || true)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
BASE="$LAB_HOME/lab15"
BIN=/opt/factura/bin
HAS_SYSTEMD=0; [ -d /run/systemd/system ] && HAS_SYSTEMD=1

echo "== Préparation du module 15 sur $HOST =="
echo "   utilisateur : $LAB_USER   base : $BASE"

pkg_install() {   # pkg_install <paquets...>
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null || true
    apt-get install -y -qq "$@" >/dev/null
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q "$@" >/dev/null
  fi
}

# ---------------------------------------------------------------------
# 0. Commun : compte de service, arborescence, bac à sable
# ---------------------------------------------------------------------
groupadd -f factura
getent passwd factura >/dev/null || \
  useradd -r -g factura -d /srv/factura -s /usr/sbin/nologin factura
install -d -m 0755 /opt/factura "$BIN" /etc/factura /srv/factura
install -d -o factura -g adm -m 0750 /var/log/factura
install -d -o "$LAB_USER" -g "$LAB_USER" "$BASE" "$BASE/conf" \
  "$BASE/rapports" "$BASE/bin" "$BASE/backups"

case "$HOST" in
# =====================================================================
lab-web)
# =====================================================================
pkg_install nginx curl apache2-utils python3 postgresql-client redis-tools \
  jq openssl

# --- 1. la mini-API (deux instances derrière nginx) --------------------
cat > "$BIN/mini-api.py" <<'PYEOF'
#!/usr/bin/env python3
"""mini-api — backend HTTP de démonstration pour le module 15 (nginx).

Options : --port N (défaut 8001). Une instance = un port.

Routes :
  /                  identité de l'instance (texte)
  /api/health        {"status":"ok","instance":port}
  /api/whoami        instance + en-têtes reçus (Host, X-Forwarded-*, ...)
  /api/invoices.json liste JSON (le front l'appelle)
  /api/customers.json
  /api/slow?s=N      attend N secondes (démo 504)
  /api/upload        POST : renvoie la taille reçue (démo 413)
  /api/login         POST ou GET : 200 (démo limit_req)
  /api/metrics       métriques texte (démo allow/deny)
  /api/stream        20 lignes espacées de 0,5 s (démo proxy_buffering)
Toute autre URI : 404 JSON.
"""
import argparse, json, os, signal, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = 8001
COUNT = {"req": 0}
INVOICES = [{"id": i, "customer": f"client-{i % 7}", "amount": 100 + i * 3,
             "status": "paid" if i % 3 else "pending"} for i in range(1, 13)]
CUSTOMERS = [{"id": i, "name": f"client-{i}"} for i in range(7)]


class H(BaseHTTPRequestHandler):
    server_version = "mini-api/1.0"
    protocol_version = "HTTP/1.1"      # keep-alive possible depuis nginx

    def _send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("X-Backend-Instance", str(PORT))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj, indent=1) + "\n")

    def log_message(self, fmt, *args):
        sys.stderr.write("[%s] %s\n" % (PORT, fmt % args))

    def do_GET(self):
        COUNT["req"] += 1
        u = urlparse(self.path)
        q = parse_qs(u.query)
        p = u.path
        if p == "/":
            self._send(200, f"mini-api instance {PORT} : racine du backend\n",
                       "text/plain")
        elif p == "/api/health":
            self._json(200, {"status": "ok", "instance": PORT})
        elif p == "/api/whoami":
            hdr = {k: v for k, v in self.headers.items()
                   if k.lower() in ("host", "x-forwarded-for",
                                    "x-forwarded-proto", "x-real-ip",
                                    "connection", "user-agent",
                                    "x-request-id", "upgrade")}
            self._json(200, {"instance": PORT, "path": self.path,
                             "client": self.client_address[0],
                             "headers": hdr,
                             "http_version": self.request_version})
        elif p == "/api/invoices.json":
            self._json(200, INVOICES)
        elif p == "/api/customers.json":
            self._json(200, CUSTOMERS)
        elif p == "/api/slow":
            s = float(q.get("s", ["5"])[0])
            time.sleep(min(s, 120))
            self._json(200, {"slept": s, "instance": PORT})
        elif p == "/api/login":
            self._json(200, {"login": "ok", "instance": PORT})
        elif p == "/api/metrics":
            body = ("# HELP miniapi_requests_total requêtes reçues\n"
                    "# TYPE miniapi_requests_total counter\n"
                    f'miniapi_requests_total{{instance="{PORT}"}} '
                    f'{COUNT["req"]}\n')
            self._send(200, body, "text/plain; version=0.0.4")
        elif p == "/api/stream" and self.command != "HEAD":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()
            for i in range(20):
                self.wfile.write(f"ligne {i} depuis {PORT}\n".encode())
                self.wfile.flush()
                time.sleep(0.5)
            self.close_connection = True
        else:
            self._json(404, {"error": "route inconnue", "path": p,
                             "instance": PORT})

    do_HEAD = do_GET

    def do_POST(self):
        COUNT["req"] += 1
        p = urlparse(self.path).path
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else b""
        if p == "/api/upload":
            self._json(200, {"received_bytes": len(body), "instance": PORT})
        elif p == "/api/login":
            self._json(200, {"login": "ok", "instance": PORT})
        else:
            self._json(404, {"error": "route inconnue", "path": p})


def main():
    global PORT
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8001)
    ap.add_argument("--bind", default="127.0.0.1")
    a = ap.parse_args()
    PORT = a.port
    srv = ThreadingHTTPServer((a.bind, a.port), H)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    sys.stderr.write(f"[{PORT}] mini-api en écoute sur {a.bind}:{a.port}\n")
    srv.serve_forever()


if __name__ == "__main__":
    main()
PYEOF
chmod 0755 "$BIN/mini-api.py"

# unité modèle : une instance par port (%i)
if [ "$HAS_SYSTEMD" -eq 1 ]; then
  cat > /etc/systemd/system/mini-api@.service <<'EOF'
[Unit]
Description=mini-api (module 15) instance sur le port %i
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=factura
Group=factura
ExecStart=/usr/bin/python3 /opt/factura/bin/mini-api.py --port %i
Restart=on-failure
RestartSec=2
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now mini-api@8001.service mini-api@8002.service \
    >/dev/null 2>&1 || true
  systemctl restart mini-api@8001.service mini-api@8002.service \
    >/dev/null 2>&1 || true
fi

# --- 2. le site statique et la page de maintenance ----------------------
install -d -m 0755 /srv/www/factura-demo/static /srv/www/maintenance \
  /srv/www/factura-demo/docs
cat > /srv/www/factura-demo/index.html <<'EOF'
<!doctype html>
<html lang="fr"><head><meta charset="utf-8">
<title>Factura — démo module 15</title>
<link rel="stylesheet" href="/static/style.css">
</head><body>
<h1>Factura (démo)</h1>
<p id="etat">Chargement…</p>
<table id="factures"><thead><tr><th>#</th><th>Client</th><th>Montant</th>
<th>Statut</th></tr></thead><tbody></tbody></table>
<p class="petit">Instance backend : <span id="instance">?</span></p>
<script src="/static/app.js"></script>
</body></html>
EOF
cat > /srv/www/factura-demo/static/app.js <<'EOF'
(async function () {
  const etat = document.getElementById('etat');
  try {
    const r = await fetch('/api/invoices.json');
    if (!r.ok) throw new Error('HTTP ' + r.status + ' sur /api/invoices.json');
    const rows = await r.json();
    const tb = document.querySelector('#factures tbody');
    rows.forEach(f => {
      const tr = document.createElement('tr');
      tr.innerHTML = `<td>${f.id}</td><td>${f.customer}</td>` +
        `<td>${f.amount} €</td><td>${f.status}</td>`;
      tb.appendChild(tr);
    });
    etat.textContent = rows.length + ' factures';
    const w = await (await fetch('/api/whoami')).json();
    document.getElementById('instance').textContent = w.instance;
  } catch (e) { etat.textContent = 'ERREUR : ' + e.message; }
})();
EOF
cat > /srv/www/factura-demo/static/style.css <<'EOF'
body{font-family:sans-serif;margin:2rem;color:#222}
table{border-collapse:collapse}td,th{border:1px solid #999;padding:.3rem .6rem}
.petit{color:#777;font-size:.8rem}
EOF
cat > /srv/www/factura-demo/static/logo.svg <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
<rect width="64" height="64" fill="#2a6"/><text x="8" y="40" fill="#fff"
font-size="28">F</text></svg>
EOF
cat > /srv/www/factura-demo/docs/index.html <<'EOF'
<!doctype html><meta charset="utf-8"><title>Docs</title>
<h1>Documentation Factura (statique)</h1><p>Servie par nginx.</p>
EOF
cat > /srv/www/maintenance/503.html <<'EOF'
<!doctype html><html lang="fr"><meta charset="utf-8">
<title>Maintenance</title>
<body style="font-family:sans-serif;margin:3rem">
<h1>Maintenance en cours</h1>
<p>Factura revient dans quelques minutes.</p></body></html>
EOF
# un « gros » fichier pour les tests 413 et gzip
head -c 3M /dev/urandom | base64 > /srv/www/factura-demo/static/gros.txt
chown -R root:root /srv/www
find /srv/www -type d -exec chmod 0755 {} +
find /srv/www -type f -exec chmod 0644 {} +

# --- 3. outils de test ----------------------------------------------------
cat > "$BIN/tir.sh" <<'EOF'
#!/usr/bin/env bash
# tir.sh — envoie N requêtes vers une URL et compte les codes HTTP
# usage : tir.sh URL [N] [délai]
set -uo pipefail
URL="${1:?url}"; N="${2:-20}"; D="${3:-0}"
for _ in $(seq "$N"); do
  curl -s -o /dev/null -w '%{http_code}\n' -k "$URL"
  [ "$D" != 0 ] && sleep "$D"
done | sort | uniq -c
EOF
chmod 0755 "$BIN/tir.sh"

cat <<EOF

lab-web prêt.
  mini-api : http://127.0.0.1:8001/api/health et :8002 (systemd
             mini-api@8001 / mini-api@8002, compte factura)
  site     : /srv/www/factura-demo (index + /static + /docs)
  page 503 : /srv/www/maintenance/503.html
  outils   : $BIN/tir.sh URL N ; psql, redis-cli, htpasswd installés
  nginx    : installé, configuration d'origine (site default actif)
Espace de travail : $BASE
EOF
;;

# =====================================================================
lab-db)
# =====================================================================
if command -v apt-get >/dev/null 2>&1; then
  pkg_install postgresql-16 postgresql-client-16 redis-server redis-tools \
    python3 jq curl
else
  dnf -y -q module enable postgresql:16 >/dev/null 2>&1 || true
  pkg_install postgresql-server postgresql-contrib redis python3 jq curl
  [ -f /var/lib/pgsql/data/PG_VERSION ] || postgresql-setup --initdb >/dev/null
fi

# --- 1. PostgreSQL : démarrage et base d'exemple ---------------------------
if [ "$HAS_SYSTEMD" -eq 1 ]; then
  systemctl enable --now postgresql >/dev/null 2>&1 || true
  systemctl start postgresql@16-main.service >/dev/null 2>&1 || true
else
  pg_ctlcluster 16 main start >/dev/null 2>&1 || true
fi
for _ in $(seq 20); do
  sudo -u postgres psql -Atc 'select 1' >/dev/null 2>&1 && break; sleep 1
done
sudo -u postgres psql -Atc 'select 1' >/dev/null 2>&1 || {
  echo "PostgreSQL ne répond pas (pg_lsclusters)" >&2; exit 1; }

PGPASS_APP='Factura-App-2026'
PGPASS_RO='Factura-RO-2026'
umask 027
cat > /etc/factura/db.env <<EOF
# identifiants de la base d'exemple du module 15 (lab uniquement)
PGHOST=10.10.10.12
PGDATABASE=factura_demo
PGUSER=factura_app
PGPASSWORD=$PGPASS_APP
FACTURA_RO_PASSWORD=$PGPASS_RO
EOF
chown root:factura /etc/factura/db.env; chmod 0640 /etc/factura/db.env
umask 022

Q() { sudo -u postgres psql -v ON_ERROR_STOP=1 -Atq "$@"; }

Q -c "DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='factura_app') THEN
    CREATE ROLE factura_app LOGIN PASSWORD '$PGPASS_APP';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='factura_ro') THEN
    CREATE ROLE factura_ro LOGIN PASSWORD '$PGPASS_RO';
  END IF;
END \$\$;"
if [ "$(Q -c "SELECT 1 FROM pg_database WHERE datname='factura_demo'")" != 1 ]
then
  Q -c "CREATE DATABASE factura_demo OWNER factura_app"
fi

# schéma + données : joués en tant que factura_app (propriétaire), une fois
if [ "$(Q -d factura_demo -c \
      "SELECT 1 FROM pg_tables WHERE tablename='invoice_lines'")" != 1 ]; then
  echo "   génération des données (une minute environ)…"
  sudo -u postgres psql -v ON_ERROR_STOP=1 -q -d factura_demo <<'SQL'
SET ROLE factura_app;
CREATE TABLE customers (
  id      serial PRIMARY KEY,
  name    text NOT NULL,
  email   text NOT NULL,
  city    text NOT NULL,
  created timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE invoices (
  id          serial PRIMARY KEY,
  number      text NOT NULL,
  customer_id int  NOT NULL REFERENCES customers(id),
  issued_on   date NOT NULL,
  status      text NOT NULL CHECK (status IN ('draft','sent','paid','error')),
  total_cents bigint NOT NULL DEFAULT 0
);
CREATE TABLE invoice_lines (
  id          bigserial PRIMARY KEY,
  invoice_id  int NOT NULL REFERENCES invoices(id),
  label       text NOT NULL,
  qty         int NOT NULL,
  unit_cents  int NOT NULL
);
INSERT INTO customers (name, email, city)
SELECT 'Client ' || g,
       'client' || g || '@exemple.fr',
       (ARRAY['Lyon','Paris','Nantes','Lille','Brest','Dijon'])[1 + g % 6]
FROM generate_series(1, 5000) g;
INSERT INTO invoices (number, customer_id, issued_on, status, total_cents)
SELECT 'F-2026-' || lpad(g::text, 6, '0'),
       1 + (random() * 4999)::int,
       date '2025-01-01' + (random() * 600)::int,
       (ARRAY['paid','paid','paid','sent','draft'])[1 + (random()*4)::int],
       0
FROM generate_series(1, 100000) g;
INSERT INTO invoice_lines (invoice_id, label, qty, unit_cents)
SELECT 1 + (random() * 99999)::int,
       'Prestation ' || (g % 40),
       1 + (g % 5),
       500 + (random() * 20000)::int
FROM generate_series(1, 300000) g;
UPDATE invoices i SET total_cents = s.t
FROM (SELECT invoice_id, sum(qty * unit_cents) t FROM invoice_lines
      GROUP BY invoice_id) s WHERE s.invoice_id = i.id;
-- Aucun index sur invoices.customer_id, invoice_lines.invoice_id,
-- customers.email : c'est voulu (E15.10, L15.5).
CREATE VIEW v_invoice_totals AS
  SELECT i.id, i.number, c.name AS customer, i.issued_on, i.status,
         i.total_cents / 100.0 AS total_eur
  FROM invoices i JOIN customers c ON c.id = i.customer_id;
RESET ROLE;
GRANT CONNECT ON DATABASE factura_demo TO factura_ro;
GRANT USAGE ON SCHEMA public TO factura_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO factura_ro;
ALTER DEFAULT PRIVILEGES FOR ROLE factura_app IN SCHEMA public
  GRANT SELECT ON TABLES TO factura_ro;
ANALYZE;
SQL
fi

# la requête lente de référence et les scripts d'exploitation
cat > "$BIN/requete-lente.sql" <<'EOF'
-- Écran « factures d'un client » de l'application : lent faute d'index
SELECT i.number, i.issued_on, i.status,
       (SELECT sum(l.qty * l.unit_cents) FROM invoice_lines l
         WHERE l.invoice_id = i.id) / 100.0 AS total_eur
FROM invoices i
WHERE i.customer_id = (SELECT id FROM customers
                       WHERE email = 'client4242@exemple.fr')
ORDER BY i.issued_on DESC;
EOF
cat > "$BIN/charge-sql.sh" <<'EOF'
#!/usr/bin/env bash
# charge-sql.sh — rejoue la requête lente en boucle (N clients en parallèle)
# usage : charge-sql.sh [parallélisme=3] [durée en s=60]
set -uo pipefail
P="${1:-3}"; T="${2:-60}"
export PGPASSWORD="$(grep ^PGPASSWORD= /etc/factura/db.env | cut -d= -f2)"
FIN=$(( $(date +%s) + T ))
for _ in $(seq "$P"); do
  ( while [ "$(date +%s)" -lt "$FIN" ]; do
      psql -h 127.0.0.1 -U factura_app -d factura_demo -Atq \
        -f /opt/factura/bin/requete-lente.sql >/dev/null 2>&1
    done ) &
done
wait
EOF
cat > "$BIN/verrou-demo.sh" <<'EOF'
#!/usr/bin/env bash
# verrou-demo.sh — ouvre une transaction qui verrouille une facture
#                  et ne la termine pas avant N secondes (défaut 300)
set -uo pipefail
N="${1:-300}"
export PGPASSWORD="$(grep ^PGPASSWORD= /etc/factura/db.env | cut -d= -f2)"
psql -h 127.0.0.1 -U factura_app -d factura_demo -q <<SQL
BEGIN;
UPDATE invoices SET status = 'sent' WHERE id = 42;
SELECT pg_sleep($N);
ROLLBACK;
SQL
EOF
chmod 0755 "$BIN"/*.sh
# lecture des identifiants : mathieu est ajouté au groupe factura
usermod -aG factura "$LAB_USER" 2>/dev/null || true

# --- 2. Redis : installé, configuration d'origine, simulateur d'app -------
if [ "$HAS_SYSTEMD" -eq 1 ]; then
  systemctl enable --now redis-server >/dev/null 2>&1 || \
    systemctl enable --now redis >/dev/null 2>&1 || true
fi
cat > "$BIN/redis-app.py" <<'PYEOF'
#!/usr/bin/env python3
"""redis-app — simule l'application Factura côté Redis (module 15).

usage : redis-app.py [--url redis://[:pass@]host:6379/0] [--loop] [-n N]
Sans dépendance : parle RESP directement (pas de module redis nécessaire).

À chaque tour : crée une session (SETEX sess:<id> 1800), incrémente un
compteur (INCR factura:stats:requests), stocke un profil (HSET user:<id>),
pousse un travail dans la file (LPUSH factura:jobs). Sort en 1 avec le
message d'erreur Redis si une écriture est refusée.
"""
import argparse, os, random, socket, sys, time
from urllib.parse import urlparse


def resp(*parts):
    out = b"*%d\r\n" % len(parts)
    for p in parts:
        b = str(p).encode()
        out += b"$%d\r\n%s\r\n" % (len(b), b)
    return out


class R:
    def __init__(self, url):
        u = urlparse(url)
        self.s = socket.create_connection((u.hostname or "127.0.0.1",
                                           u.port or 6379), timeout=5)
        self.f = self.s.makefile("rb")
        if u.password:
            if u.username:
                self.cmd("AUTH", u.username, u.password)
            else:
                self.cmd("AUTH", u.password)
        db = (u.path or "/0").strip("/")
        if db and db != "0":
            self.cmd("SELECT", db)

    def cmd(self, *parts):
        self.s.sendall(resp(*parts))
        return self._read()

    def _read(self):
        line = self.f.readline()
        if not line:
            raise ConnectionError("connexion fermée par Redis")
        t, body = line[:1], line[1:].rstrip(b"\r\n")
        if t == b"+":
            return body.decode()
        if t == b"-":
            raise RuntimeError(body.decode())
        if t == b":":
            return int(body)
        if t == b"$":
            n = int(body)
            if n < 0:
                return None
            d = self.f.read(n + 2)[:-2]
            return d.decode(errors="replace")
        if t == b"*":
            return [self._read() for _ in range(int(body))]
        raise RuntimeError("réponse RESP inconnue : %r" % line)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default=os.environ.get(
        "FACTURA_REDIS_URL", "redis://127.0.0.1:6379/0"))
    ap.add_argument("--loop", action="store_true")
    ap.add_argument("-n", type=int, default=50, help="tours (défaut 50)")
    ap.add_argument("--sleep", type=float, default=0.05)
    a = ap.parse_args()
    try:
        r = R(a.url)
        r.cmd("PING")
    except Exception as e:
        print(f"redis-app: connexion impossible ({e})", file=sys.stderr)
        sys.exit(2)
    i = 0
    while True:
        i += 1
        sid = "%08x" % random.getrandbits(32)
        try:
            r.cmd("SETEX", f"sess:{sid}", 1800, "x" * 512)
            r.cmd("INCR", "factura:stats:requests")
            r.cmd("HSET", f"user:{i % 500}", "name", f"user{i % 500}",
                  "last_seen", int(time.time()))
            r.cmd("LPUSH", "factura:jobs", f'{{"invoice":{i},"sid":"{sid}"}}')
        except RuntimeError as e:
            print(f"redis-app: ECRITURE REFUSEE au tour {i} : {e}",
                  file=sys.stderr)
            sys.exit(1)
        if i % 10 == 0:
            print(f"tour {i} : sessions écrites, file={r.cmd('LLEN', 'factura:jobs')}")
        if not a.loop and i >= a.n:
            break
        time.sleep(a.sleep)
    print("redis-app: terminé sans erreur")


if __name__ == "__main__":
    main()
PYEOF
chmod 0755 "$BIN/redis-app.py"

cat <<EOF

lab-db prêt.
  PostgreSQL 16 : cluster 16/main (pg_lsclusters), base factura_demo
                  (customers 5 000, invoices 100 000, invoice_lines 300 000)
                  rôles factura_app (propriétaire) et factura_ro (lecture)
                  identifiants : /etc/factura/db.env (groupe factura ;
                  reconnecte-toi pour que l'ajout au groupe soit effectif)
  requête lente : $BIN/requete-lente.sql ; charge : $BIN/charge-sql.sh
  verrou        : $BIN/verrou-demo.sh
  Redis 7       : configuration d'origine (127.0.0.1, sans mot de passe)
  simulateur    : $BIN/redis-app.py [--url ...] [--loop]
Rien n'est configuré côté réseau (listen_addresses, pg_hba, bind Redis) :
c'est le module.
Espace de travail : $BASE
EOF
;;

*)
  echo "hostname « $HOST » : ce module se joue sur lab-web et lab-db." >&2
  exit 1 ;;
esac
