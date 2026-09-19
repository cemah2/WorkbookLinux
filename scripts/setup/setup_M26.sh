#!/usr/bin/env bash
# setup_M26.sh — prépare le terrain du module 26 (Kubernetes, observabilité)
# À lancer avec sudo, sur lab-ops (10.10.10.14) uniquement.
# Idempotent : relançable sans effet de bord.
#
# Ce script N'INSTALLE PAS k3s et NE DÉMARRE PAS la pile d'observabilité :
# c'est le travail des labs. Il prépare :
#   - le registre privé authentifié 10.10.10.14:5000 (conteneur Docker)
#   - l'image factura-api (tags 1.0 et 1.1) poussée dans ce registre
#   - /etc/rancher/k3s/registries.yaml (registre en HTTP pour containerd)
#   - helm (binaire) et la complétion
#   - ~/lab26/k8s/        : manifestes SQUELETTES à compléter
#   - ~/lab26/k8s/casse/  : manifestes volontairement faux (L26.3)
#   - ~/lab26/tls/        : certificat auto-signé factura.lab.local
#   - /opt/observabilite/ : compose Prometheus/Alertmanager/Grafana/Loki/
#                           Alloy/blackbox + prometheus.yml pour les 5 VM,
#                           règles, alertmanager.yml, provisioning Grafana
#   - ~/lab26/bin/        : outils (installation node_exporter à distance)
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }

LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }

BASE="$LAB_HOME/lab26"
OBS=/opt/observabilite
REG_IP=10.10.10.14
REG="$REG_IP:5000"
REG_USER=mathieu
REG_PASS=labpass
REG_DIR=/opt/registre

echo "== Préparation du module 26 =="
echo "   utilisateur : $LAB_USER"
echo "   base        : $BASE"

command -v docker >/dev/null 2>&1 || {
  echo "docker est requis sur lab-ops (module Docker)" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || {
  echo "le plugin docker compose est requis" >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq apache2-utils jq curl openssl python3 \
  prometheus-node-exporter bash-completion >/dev/null

mkdir -p "$BASE"/{k8s/casse,tls,bin,rapports,helm,rules}

# ---------------------------------------------------------------------
# 1. Docker : registre 10.10.10.14:5000 déclaré non sécurisé (HTTP)
# ---------------------------------------------------------------------
DJ=/etc/docker/daemon.json
python3 - "$DJ" "$REG" <<'PY'
import json, os, sys
p, reg = sys.argv[1], sys.argv[2]
d = {}
if os.path.exists(p):
    with open(p) as f:
        try:
            d = json.load(f)
        except ValueError:
            d = {}
lst = d.setdefault("insecure-registries", [])
if reg not in lst:
    lst.append(reg)
    with open(p, "w") as f:
        json.dump(d, f, indent=2)
PY
# redémarre le démon uniquement s'il ne connaît pas encore le registre
if ! docker info 2>/dev/null | grep -q "$REG"; then
  systemctl restart docker
  sleep 3
fi

# ---------------------------------------------------------------------
# 2. Registre privé avec authentification htpasswd
# ---------------------------------------------------------------------
mkdir -p "$REG_DIR"/{auth,data}
if [ ! -s "$REG_DIR/auth/htpasswd" ]; then
  htpasswd -Bbn "$REG_USER" "$REG_PASS" > "$REG_DIR/auth/htpasswd"
fi
if ! docker ps -a --format '{{.Names}}' | grep -qx registre-lab; then
  if ss -ltn | grep -q ':5000 '; then
    echo "!! le port 5000 est occupé par autre chose que registre-lab" >&2
    echo "   libère-le (docker ps) puis relance le setup" >&2
    exit 1
  fi
  docker run -d --name registre-lab --restart unless-stopped \
    -p 5000:5000 \
    -v "$REG_DIR/data":/var/lib/registry \
    -v "$REG_DIR/auth":/auth:ro \
    -e REGISTRY_AUTH=htpasswd \
    -e "REGISTRY_AUTH_HTPASSWD_REALM=Registre lab" \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
    registry:2 >/dev/null
else
  docker start registre-lab >/dev/null 2>&1 || true
fi
for i in $(seq 1 20); do
  curl -sf -u "$REG_USER:$REG_PASS" "http://$REG/v2/" >/dev/null && break
  sleep 1
done

# ---------------------------------------------------------------------
# 3. containerd (k3s) : le registre est en HTTP
#    Lu par k3s au démarrage ; k3s n'est pas encore installé, c'est prévu.
# ---------------------------------------------------------------------
mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/registries.yaml <<EOF
mirrors:
  "$REG":
    endpoint:
      - "http://$REG"
EOF

# ---------------------------------------------------------------------
# 4. Application factura-api (image), tags 1.0 et 1.1
# ---------------------------------------------------------------------
APPSRC="$BASE/app"
mkdir -p "$APPSRC"
cat > "$APPSRC/factura-api.py" <<'PYEOF'
#!/usr/bin/env python3
"""factura-api — API de démonstration pour Kubernetes (workbook, module 26).

Variables d'environnement :
  FACTURA_PORT          port d'écoute (défaut 8080)
  DB_HOST / DB_PORT     PostgreSQL à joindre pour être « prêt » (défaut
                        postgres / 5432)
  FACTURA_VERSION       version annoncée (défaut : valeur compilée)
  FACTURA_DELAI_PRET    secondes avant de répondre 200 sur /pret (défaut 0)
  FACTURA_CRASH_APRES   secondes avant de sortir en code 1 (défaut : jamais)
  FACTURA_MEM_MB        Mo alloués et conservés au démarrage (défaut 0)
  FACTURA_TAUX_ERREUR   proportion de 500 sur /factures, 0..1 (défaut 0)

Routes : /  /sante  /pret  /factures  /metrics
"""
import json, os, random, signal, socket, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("FACTURA_PORT", "8080"))
DB_HOST = os.environ.get("DB_HOST", "postgres")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
VERSION = os.environ.get("FACTURA_VERSION", "__VERSION__")
DELAI_PRET = float(os.environ.get("FACTURA_DELAI_PRET", "0"))
CRASH_APRES = float(os.environ.get("FACTURA_CRASH_APRES", "0"))
MEM_MB = int(os.environ.get("FACTURA_MEM_MB", "0"))
TAUX_ERREUR = float(os.environ.get("FACTURA_TAUX_ERREUR", "0"))
HOST = socket.gethostname()
T0 = time.time()
BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]

_lock = threading.Lock()
_compteurs = {}          # (method, path, code) -> n
_hist = {}               # path -> {"buckets": [..], "sum": s, "count": n}
_lest = bytearray(MEM_MB * 1024 * 1024) if MEM_MB else None


def log(msg, **kv):
    champs = " ".join(f'{k}={v}' for k, v in kv.items())
    print(f'ts={time.strftime("%Y-%m-%dT%H:%M:%S")} niveau=info '
          f'msg="{msg}" {champs}', flush=True)


def db_ok():
    try:
        with socket.create_connection((DB_HOST, DB_PORT), timeout=1):
            return True
    except OSError:
        return False


def observer(method, path, code, duree):
    with _lock:
        _compteurs[(method, path, code)] = \
            _compteurs.get((method, path, code), 0) + 1
        h = _hist.setdefault(path, {"b": [0] * len(BUCKETS),
                                    "sum": 0.0, "count": 0})
        for i, b in enumerate(BUCKETS):
            if duree <= b:
                h["b"][i] += 1
        h["sum"] += duree
        h["count"] += 1


def metriques():
    out = ["# HELP factura_http_requests_total Requêtes HTTP traitées.",
           "# TYPE factura_http_requests_total counter"]
    with _lock:
        for (m, p, c), n in sorted(_compteurs.items()):
            out.append(f'factura_http_requests_total{{method="{m}",'
                       f'path="{p}",code="{c}"}} {n}')
        out += ["# HELP factura_http_request_duration_seconds Durée.",
                "# TYPE factura_http_request_duration_seconds histogram"]
        for p, h in sorted(_hist.items()):
            for i, b in enumerate(BUCKETS):
                out.append(f'factura_http_request_duration_seconds_bucket'
                           f'{{path="{p}",le="{b}"}} {h["b"][i]}')
            out.append(f'factura_http_request_duration_seconds_bucket'
                       f'{{path="{p}",le="+Inf"}} {h["count"]}')
            out.append(f'factura_http_request_duration_seconds_sum'
                       f'{{path="{p}"}} {h["sum"]:.6f}')
            out.append(f'factura_http_request_duration_seconds_count'
                       f'{{path="{p}"}} {h["count"]}')
    out += ["# HELP factura_build_info Version de l'application.",
            "# TYPE factura_build_info gauge",
            f'factura_build_info{{version="{VERSION}"}} 1',
            "# HELP factura_db_up 1 si PostgreSQL est joignable.",
            "# TYPE factura_db_up gauge",
            f"factura_db_up {1 if db_ok() else 0}",
            "# HELP factura_uptime_seconds Secondes depuis le démarrage.",
            "# TYPE factura_uptime_seconds gauge",
            f"factura_uptime_seconds {time.time() - T0:.0f}"]
    return "\n".join(out) + "\n"


class H(BaseHTTPRequestHandler):
    server_version = "factura-api/" + VERSION

    def log_message(self, *a):
        pass

    def _rep(self, code, corps, ctype="application/json"):
        data = corps.encode() if isinstance(corps, str) else corps
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        return code

    def do_GET(self):
        t = time.time()
        p = self.path.split("?")[0]
        if p == "/sante":
            code = self._rep(200, '{"statut":"ok"}\n')
        elif p == "/pret":
            if time.time() - T0 < DELAI_PRET:
                code = self._rep(503, '{"pret":false,"raison":"demarrage"}\n')
            elif not db_ok():
                code = self._rep(503, '{"pret":false,"raison":"db"}\n')
            else:
                code = self._rep(200, '{"pret":true}\n')
        elif p == "/metrics":
            code = self._rep(200, metriques(), "text/plain; version=0.0.4")
        elif p == "/factures":
            time.sleep(random.uniform(0.005, 0.08))
            if random.random() < TAUX_ERREUR:
                code = self._rep(500, '{"erreur":"base injoignable"}\n')
            elif not db_ok():
                code = self._rep(503, '{"erreur":"db"}\n')
            else:
                code = self._rep(200, json.dumps(
                    [{"id": i, "montant": 100 * i} for i in range(1, 4)]))
        elif p == "/":
            code = self._rep(200, json.dumps({
                "app": "factura-api", "version": VERSION, "pod": HOST,
                "db_ok": db_ok()}) + "\n")
        else:
            code = self._rep(404, '{"erreur":"route inconnue"}\n')
        d = time.time() - t
        if p != "/metrics":
            observer("GET", p, code, d)
        if p not in ("/sante", "/pret", "/metrics"):
            log("requete", path=p, code=code, duree_ms=f"{d*1000:.1f}")


def main():
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), H)

    def stop(sig, frame):
        log("arret propre", signal=sig)
        threading.Thread(target=srv.shutdown, daemon=True).start()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    if CRASH_APRES > 0:
        def crash():
            time.sleep(CRASH_APRES)
            print("FATAL: erreur interne simulee (FACTURA_CRASH_APRES)",
                  file=sys.stderr, flush=True)
            os._exit(1)
        threading.Thread(target=crash, daemon=True).start()
    log("demarrage", version=VERSION, port=PORT, db=f"{DB_HOST}:{DB_PORT}",
        mem_mb=MEM_MB)
    srv.serve_forever()
    log("termine")


if __name__ == "__main__":
    main()
PYEOF

cat > "$APPSRC/Dockerfile" <<'EOF'
FROM python:3.12-alpine
ARG VERSION=1.0
ENV FACTURA_VERSION=${VERSION} PYTHONUNBUFFERED=1
WORKDIR /app
COPY factura-api.py /app/factura-api.py
RUN sed -i "s/__VERSION__/${VERSION}/" /app/factura-api.py \
 && adduser -D -u 10001 factura
USER 10001
EXPOSE 8080
CMD ["python3", "/app/factura-api.py"]
EOF

echo "$REG_PASS" | docker login "$REG" -u "$REG_USER" --password-stdin \
  >/dev/null 2>&1
for v in 1.0 1.1; do
  if ! curl -sf -u "$REG_USER:$REG_PASS" \
      "http://$REG/v2/factura-api/tags/list" 2>/dev/null \
      | grep -q "\"$v\""; then
    docker build -q --build-arg "VERSION=$v" -t "$REG/factura-api:$v" \
      "$APPSRC" >/dev/null
    docker push -q "$REG/factura-api:$v" >/dev/null
  fi
done
docker logout "$REG" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------
# 5. Helm
# ---------------------------------------------------------------------
if ! command -v helm >/dev/null 2>&1; then
  HELM_URL=https://raw.githubusercontent.com/helm/helm/main/scripts
  curl -fsSL "$HELM_URL/get-helm-3" | bash >/dev/null
fi
helm completion bash > /etc/bash_completion.d/helm 2>/dev/null || true

# ---------------------------------------------------------------------
# 6. Certificat TLS auto-signé pour l'Ingress
# ---------------------------------------------------------------------
if [ ! -s "$BASE/tls/factura.crt" ]; then
  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout "$BASE/tls/factura.key" -out "$BASE/tls/factura.crt" \
    -subj "/CN=factura.lab.local" \
    -addext "subjectAltName=DNS:factura.lab.local" >/dev/null 2>&1
fi

# ---------------------------------------------------------------------
# 7. Manifestes squelettes (~/lab26/k8s/) — à COMPLÉTER dans les labs
# ---------------------------------------------------------------------
K="$BASE/k8s"

cat > "$K/00-namespace.yaml" <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: factura
  labels:
    equipe: compta
EOF

cat > "$K/10-configmap.yaml" <<'EOF'
# ConfigMap de l'API : variables non sensibles.
# À COMPLÉTER : DB_HOST doit pointer vers le Service PostgreSQL.
apiVersion: v1
kind: ConfigMap
metadata:
  name: factura-api-config
  namespace: factura
data:
  DB_HOST: "A_COMPLETER"
  DB_PORT: "5432"
  FACTURA_PORT: "8080"
EOF

cat > "$K/11-secret.yaml" <<'EOF'
# Secret PostgreSQL. Rappel : base64 n'est PAS du chiffrement.
# À COMPLÉTER : encode le mot de passe (echo -n ... | base64) ou utilise
# stringData: pour laisser l'API server encoder.
apiVersion: v1
kind: Secret
metadata:
  name: postgres-auth
  namespace: factura
type: Opaque
data:
  POSTGRES_USER: ZmFjdHVyYQ==
  POSTGRES_PASSWORD: A_COMPLETER
EOF

cat > "$K/20-postgres.yaml" <<'EOF'
# PostgreSQL 16 en StatefulSet + Service headless.
# À COMPLÉTER : le volumeClaimTemplate (1Gi, storageClass local-path),
# la readiness probe (pg_isready) et les variables d'environnement
# tirées du Secret postgres-auth.
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: factura
spec:
  clusterIP: None
  selector:
    app: postgres
  ports:
    - name: pg
      port: 5432
      targetPort: 5432
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: factura
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          ports:
            - containerPort: 5432
              name: pg
          env:
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
            # A_COMPLETER : POSTGRES_USER / POSTGRES_PASSWORD depuis le Secret
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              memory: 512Mi
          volumeMounts:
            - name: donnees
              mountPath: /var/lib/postgresql/data
  # A_COMPLETER : volumeClaimTemplates
EOF

cat > "$K/30-api.yaml" <<'EOF'
# factura-api : Deployment 2 réplicas + Service ClusterIP.
# À COMPLÉTER : image du registre privé, imagePullSecrets, envFrom
# (ConfigMap), probes liveness (/sante) et readiness (/pret), resources.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: factura-api
  namespace: factura
  labels:
    app: factura-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: factura-api
  template:
    metadata:
      labels:
        app: factura-api
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      # A_COMPLETER : imagePullSecrets
      containers:
        - name: api
          image: A_COMPLETER/factura-api:1.0
          ports:
            - containerPort: 8080
              name: http
          # A_COMPLETER : envFrom, probes, resources
---
apiVersion: v1
kind: Service
metadata:
  name: factura-api
  namespace: factura
spec:
  type: ClusterIP
  selector:
    app: factura-api
  ports:
    - name: http
      port: 8080
      targetPort: http
EOF

cat > "$K/40-front.yaml" <<'EOF'
# Frontal nginx : sert / et relaie /api/ vers factura-api.
# La configuration nginx vient d'une ConfigMap montée en volume.
apiVersion: v1
kind: ConfigMap
metadata:
  name: front-config
  namespace: factura
data:
  default.conf: |
    server {
      listen 80;
      location / {
        default_type text/plain;
        return 200 "factura front\n";
      }
      location /api/ {
        proxy_pass http://factura-api:8080/;
        proxy_set_header Host $host;
      }
      location /stub_status {
        stub_status;
        allow 127.0.0.1;
        allow 10.0.0.0/8;
        deny all;
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: front
  namespace: factura
spec:
  replicas: 1
  selector:
    matchLabels:
      app: front
  template:
    metadata:
      labels:
        app: front
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          ports:
            - containerPort: 80
              name: http
          readinessProbe:
            httpGet:
              path: /
              port: http
            periodSeconds: 5
          resources:
            requests:
              cpu: 20m
              memory: 32Mi
            limits:
              memory: 64Mi
          volumeMounts:
            - name: conf
              mountPath: /etc/nginx/conf.d
      volumes:
        - name: conf
          configMap:
            name: front-config
---
apiVersion: v1
kind: Service
metadata:
  name: front
  namespace: factura
spec:
  selector:
    app: front
  ports:
    - name: http
      port: 80
      targetPort: http
EOF

cat > "$K/50-ingress.yaml" <<'EOF'
# Ingress Traefik (fourni par k3s) avec TLS.
# À COMPLÉTER : la section tls (secret factura-tls) et le backend.
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: factura
  namespace: factura
spec:
  ingressClassName: traefik
  rules:
    - host: factura.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: A_COMPLETER
                port:
                  number: 80
EOF

cat > "$K/60-cronjob-sauvegarde.yaml" <<'EOF'
# À COMPLÉTER (E26.7) : CronJob pg_dump toutes les nuits à 02:30.
apiVersion: batch/v1
kind: CronJob
metadata:
  name: sauvegarde-pg
  namespace: factura
spec:
  schedule: "A_COMPLETER"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: pgdump
              image: postgres:16-alpine
              command: ["/bin/sh", "-c"]
              args:
                - A_COMPLETER
EOF

# ---- manifestes cassés pour L26.3 -----------------------------------
C="$K/casse"
cat > "$C/00-namespace.yaml" <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: casse
EOF

cat > "$C/01-pending.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gourmand
  namespace: casse
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gourmand
  template:
    metadata:
      labels:
        app: gourmand
    spec:
      nodeSelector:
        disque: ssd
      containers:
        - name: web
          image: nginx:1.27-alpine
          resources:
            requests:
              cpu: "8"
              memory: 16Gi
EOF

cat > "$C/02-imagepull.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-image
  namespace: casse
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api-image
  template:
    metadata:
      labels:
        app: api-image
    spec:
      containers:
        - name: api
          image: 10.10.10.14:5000/factura-api:1.0
          env:
            - name: DB_HOST
              value: "127.0.0.1"
EOF

cat > "$C/03-crashloop.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-crash
  namespace: casse
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api-crash
  template:
    metadata:
      labels:
        app: api-crash
    spec:
      imagePullSecrets:
        - name: registre-lab
      containers:
        - name: api
          image: 10.10.10.14:5000/factura-api:1.0
          env:
            - name: FACTURA_CRASH_APRES
              value: "3"
            - name: DB_HOST
              value: "127.0.0.1"
EOF

cat > "$C/04-dns.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-dns
  namespace: casse
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api-dns
  template:
    metadata:
      labels:
        app: api-dns
    spec:
      imagePullSecrets:
        - name: registre-lab
      containers:
        - name: api
          image: 10.10.10.14:5000/factura-api:1.0
          env:
            - name: DB_HOST
              value: "postgres"
          readinessProbe:
            httpGet:
              path: /pret
              port: 8080
            periodSeconds: 5
EOF

cat > "$C/05-ingress.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: api-dns
  namespace: casse
spec:
  selector:
    app: api-dns
  ports:
    - port: 8080
      targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: casse
  namespace: casse
spec:
  ingressClassName: traefik
  rules:
    - host: casse.lab.local
      http:
        paths:
          - path: /api
            pathType: Exact
            backend:
              service:
                name: api-dns
                port:
                  number: 8080
EOF

# ---------------------------------------------------------------------
# 8. Pile d'observabilité (/opt/observabilite) — non démarrée
# ---------------------------------------------------------------------
mkdir -p "$OBS"/prometheus/rules "$OBS"/alertmanager "$OBS"/loki \
  "$OBS"/alloy "$OBS"/blackbox "$OBS"/webhook "$OBS"/grafana/dashboards \
  "$OBS"/grafana/provisioning/datasources \
  "$OBS"/grafana/provisioning/dashboards

cat > "$OBS/compose.yaml" <<'EOF'
# Pile d'observabilité du lab (module 26). Démarrage : docker compose up -d
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --storage.tsdb.retention.time=15d
      - --web.enable-lifecycle
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus:/etc/prometheus:ro
      - prometheus-data:/prometheus

  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    restart: unless-stopped
    command:
      - --config.file=/etc/alertmanager/alertmanager.yml
      - --storage.path=/alertmanager
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager:/etc/alertmanager:ro
      - alertmanager-data:/alertmanager

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: labpass
      GF_USERS_ALLOW_SIGN_UP: "false"
    ports:
      - "3000:3000"
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
      - grafana-data:/var/lib/grafana

  loki:
    image: grafana/loki:latest
    container_name: loki
    restart: unless-stopped
    command: -config.file=/etc/loki/loki.yaml
    ports:
      - "3100:3100"
    volumes:
      - ./loki:/etc/loki:ro
      - loki-data:/loki

  alloy:
    image: grafana/alloy:latest
    container_name: alloy
    restart: unless-stopped
    command:
      - run
      - --server.http.listen-addr=0.0.0.0:12345
      - --storage.path=/var/lib/alloy/data
      - /etc/alloy/config.alloy
    ports:
      - "12345:12345"
    volumes:
      - ./alloy:/etc/alloy:ro
      - /var/log:/var/log:ro
      - /etc/machine-id:/etc/machine-id:ro
      - alloy-data:/var/lib/alloy/data

  blackbox:
    image: prom/blackbox-exporter:latest
    container_name: blackbox
    restart: unless-stopped
    command: --config.file=/etc/blackbox/blackbox.yml
    cap_add:
      - NET_RAW
    ports:
      - "9115:9115"
    volumes:
      - ./blackbox:/etc/blackbox:ro

  webhook:
    image: python:3.12-alpine
    container_name: webhook
    restart: unless-stopped
    command: ["python3", "/app/recepteur.py"]
    ports:
      - "9099:9099"
    volumes:
      - ./webhook:/app:ro

volumes:
  prometheus-data:
  alertmanager-data:
  grafana-data:
  loki-data:
  alloy-data:
EOF

cat > "$OBS/prometheus/prometheus.yml" <<'EOF'
# prometheus.yml — lab 22. Rechargement : curl -X POST :9090/-/reload
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    site: lab

rule_files:
  - /etc/prometheus/rules/*.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: node
    static_configs:
      - targets: ["10.10.10.10:9100"]
        labels: {instance: lab-adm, role: admin}
      - targets: ["10.10.10.11:9100"]
        labels: {instance: lab-web, role: web}
      - targets: ["10.10.10.12:9100"]
        labels: {instance: lab-db, role: db}
      - targets: ["10.10.10.13:9100"]
        labels: {instance: lab-rhel, role: rhel}
      - targets: ["10.10.10.14:9100"]
        labels: {instance: lab-ops, role: ops}

  # --- à compléter dans L26.4 : nginx, postgres, blackbox, k8s -----------
EOF

cat > "$OBS/prometheus/rules/00-exemple.yml" <<'EOF'
# Exemple de fichier de règles. Les vraies règles sont écrites en L26.4
# dans lab-enregistrement.yml et lab-alertes.yml (même répertoire).
groups:
  - name: exemple
    rules:
      - alert: PrometheusCibleAbsente
        expr: absent(up{job="prometheus"})
        for: 5m
        labels:
          severity: ticket
        annotations:
          summary: "Prometheus ne se scrape plus lui-même"
EOF

cat > "$OBS/alertmanager/alertmanager.yml" <<'EOF'
# alertmanager.yml — squelette. Routage/inhibition à compléter en L26.4.
global:
  resolve_timeout: 5m

route:
  receiver: ticket
  group_by: ["alertname"]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes: []

receivers:
  - name: ticket
    webhook_configs:
      - url: http://webhook:9099/ticket
        send_resolved: true
  - name: page
    webhook_configs:
      - url: http://webhook:9099/page
        send_resolved: true

inhibit_rules: []
EOF

cat > "$OBS/webhook/recepteur.py" <<'PYEOF'
#!/usr/bin/env python3
"""Récepteur de webhook Alertmanager : affiche chaque notification.
Lecture : docker compose logs -f webhook"""
import json, time
from http.server import BaseHTTPRequestHandler, HTTPServer


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        corps = json.loads(self.rfile.read(n) or b"{}")
        canal = self.path.strip("/") or "inconnu"
        for a in corps.get("alerts", []):
            lab = a.get("labels", {})
            print(f'{time.strftime("%H:%M:%S")} [{canal.upper()}] '
                  f'{a.get("status","?"):8s} {lab.get("alertname","?")} '
                  f'instance={lab.get("instance","-")} '
                  f'severity={lab.get("severity","-")} '
                  f'runbook={a.get("annotations",{}).get("runbook_url","-")}',
                  flush=True)
        self.send_response(200)
        self.end_headers()


HTTPServer(("0.0.0.0", 9099), H).serve_forever()
PYEOF

cat > "$OBS/blackbox/blackbox.yml" <<'EOF'
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_status_codes: []
      follow_redirects: true
      tls_config:
        insecure_skip_verify: true
  icmp:
    prober: icmp
    timeout: 3s
EOF

cat > "$OBS/loki/loki.yaml" <<'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: "2024-01-01"
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://alertmanager:9093
EOF

cat > "$OBS/alloy/config.alloy" <<'EOF'
// Alloy : collecte le journal systemd et /var/log/*.log de lab-ops
// vers Loki. Interface : http://10.10.10.14:12345

loki.source.journal "systeme" {
  path       = "/var/log/journal"
  max_age    = "12h"
  labels     = { job = "systemd-journal", host = "lab-ops" }
  forward_to = [loki.write.local.receiver]
}

local.file_match "fichiers" {
  path_targets = [{
    "__path__" = "/var/log/*.log",
    "job"      = "varlogs",
    "host"     = "lab-ops",
  }]
}

loki.source.file "fichiers" {
  targets    = local.file_match.fichiers.targets
  forward_to = [loki.write.local.receiver]
}

loki.write "local" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
EOF

cat > "$OBS/grafana/provisioning/datasources/sources.yml" <<'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
  - name: Loki
    uid: loki
    type: loki
    access: proxy
    url: http://loki:3100
  - name: Alertmanager
    uid: alertmanager
    type: alertmanager
    access: proxy
    url: http://alertmanager:9093
    jsonData:
      implementation: prometheus
EOF

cat > "$OBS/grafana/provisioning/dashboards/lab.yml" <<'EOF'
apiVersion: 1
providers:
  - name: lab
    folder: Lab
    type: file
    disableDeletion: false
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

cat > "$OBS/grafana/dashboards/noeuds.json" <<'EOF'
{
  "uid": "lab-noeuds",
  "title": "Lab — Nœuds",
  "tags": ["lab", "node_exporter"],
  "timezone": "browser",
  "schemaVersion": 39,
  "version": 1,
  "refresh": "30s",
  "time": {"from": "now-1h", "to": "now"},
  "templating": {
    "list": [
      {
        "name": "instance",
        "type": "query",
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "query": "label_values(node_uname_info, instance)",
        "refresh": 2,
        "includeAll": true,
        "multi": true,
        "current": {"text": "All", "value": "$__all"}
      }
    ]
  },
  "panels": [
    {
      "id": 1,
      "type": "stat",
      "title": "Cibles UP",
      "gridPos": {"x": 0, "y": 0, "w": 6, "h": 4},
      "datasource": {"type": "prometheus", "uid": "prometheus"},
      "targets": [{"refId": "A", "expr": "count(up{job=\"node\"} == 1)"}],
      "fieldConfig": {"defaults": {"thresholds": {"mode": "absolute",
        "steps": [{"color": "red", "value": null},
                  {"color": "green", "value": 5}]}}, "overrides": []}
    },
    {
      "id": 2,
      "type": "timeseries",
      "title": "CPU utilisé (%)",
      "gridPos": {"x": 6, "y": 0, "w": 18, "h": 8},
      "datasource": {"type": "prometheus", "uid": "prometheus"},
      "targets": [{
        "refId": "A",
        "expr": "100 - avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\",instance=~\"$instance\"}[5m])) * 100",
        "legendFormat": "{{instance}}"
      }],
      "fieldConfig": {"defaults": {"unit": "percent", "min": 0, "max": 100,
        "thresholds": {"mode": "absolute", "steps": [
          {"color": "green", "value": null},
          {"color": "orange", "value": 70},
          {"color": "red", "value": 90}]}}, "overrides": []}
    },
    {
      "id": 3,
      "type": "timeseries",
      "title": "Mémoire disponible (%)",
      "gridPos": {"x": 0, "y": 8, "w": 12, "h": 8},
      "datasource": {"type": "prometheus", "uid": "prometheus"},
      "targets": [{
        "refId": "A",
        "expr": "100 * node_memory_MemAvailable_bytes{instance=~\"$instance\"} / node_memory_MemTotal_bytes",
        "legendFormat": "{{instance}}"
      }],
      "fieldConfig": {"defaults": {"unit": "percent", "min": 0, "max": 100},
        "overrides": []}
    },
    {
      "id": 4,
      "type": "timeseries",
      "title": "Disque / utilisé (%)",
      "gridPos": {"x": 12, "y": 8, "w": 12, "h": 8},
      "datasource": {"type": "prometheus", "uid": "prometheus"},
      "targets": [{
        "refId": "A",
        "expr": "100 * (1 - node_filesystem_avail_bytes{mountpoint=\"/\",instance=~\"$instance\"} / node_filesystem_size_bytes{mountpoint=\"/\"})",
        "legendFormat": "{{instance}}"
      }],
      "fieldConfig": {"defaults": {"unit": "percent", "min": 0, "max": 100,
        "thresholds": {"mode": "absolute", "steps": [
          {"color": "green", "value": null},
          {"color": "orange", "value": 80},
          {"color": "red", "value": 90}]}}, "overrides": []}
    }
  ]
}
EOF

# ---------------------------------------------------------------------
# 9. Outils : installation de node_exporter sur les autres VM
# ---------------------------------------------------------------------
cat > "$BASE/bin/installer-node-exporter.sh" <<'EOF'
#!/usr/bin/env bash
# installer-node-exporter.sh — à exécuter AVEC sudo sur chaque VM cible.
# Ubuntu : paquet prometheus-node-exporter. Rocky : binaire officiel +
# unité systemd. Écoute sur :9100 dans les deux cas.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
if command -v apt-get >/dev/null; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    prometheus-node-exporter >/dev/null
  systemctl enable --now prometheus-node-exporter
elif command -v dnf >/dev/null; then
  V=1.9.1
  if [ ! -x /usr/local/bin/node_exporter ]; then
    curl -sSL -o /tmp/ne.tgz "https://github.com/prometheus/node_exporter/\
releases/download/v$V/node_exporter-$V.linux-amd64.tar.gz"
    tar -xzf /tmp/ne.tgz -C /tmp
    install -m 0755 "/tmp/node_exporter-$V.linux-amd64/node_exporter" \
      /usr/local/bin/node_exporter
  fi
  id node_exporter >/dev/null 2>&1 || \
    useradd -r -s /sbin/nologin node_exporter
  cat > /etc/systemd/system/node_exporter.service <<'UNIT'
[Unit]
Description=Prometheus node_exporter
After=network-online.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable --now node_exporter
  if command -v firewall-cmd >/dev/null; then
    firewall-cmd --add-port=9100/tcp --permanent >/dev/null
    firewall-cmd --reload >/dev/null
  fi
fi
ss -ltn | grep -q ':9100 ' && echo "node_exporter écoute sur :9100"
EOF
chmod 0755 "$BASE/bin/installer-node-exporter.sh"

# script de charge HTTP pour alimenter les métriques de l'API
cat > "$BASE/bin/charge-api.sh" <<'EOF'
#!/usr/bin/env bash
# charge-api.sh [url] [durée_s] — envoie des requêtes en continu
set -uo pipefail
URL="${1:-https://factura.lab.local/api/factures}"
DUREE="${2:-120}"
FIN=$(( $(date +%s) + DUREE ))
while [ "$(date +%s)" -lt "$FIN" ]; do
  curl -sk --resolve factura.lab.local:443:10.10.10.14 -o /dev/null "$URL"
  sleep 0.2
done
EOF
chmod 0755 "$BASE/bin/charge-api.sh"

systemctl enable --now prometheus-node-exporter >/dev/null 2>&1 || true

# ---------------------------------------------------------------------
# 10. Droits
# ---------------------------------------------------------------------
chown -R "$LAB_USER:$LAB_USER" "$BASE"
chmod 0600 "$BASE/tls/factura.key"
chown -R "$LAB_USER:$LAB_USER" "$OBS"

cat <<EOF

== Module 26 prêt ==
Registre privé : http://$REG  (utilisateur $REG_USER / $REG_PASS)
Images         : $REG/factura-api:1.0 et :1.1
Manifestes     : $K/  (squelettes à compléter) et $K/casse/
Observabilité  : $OBS (docker compose up -d quand L26.4 le demande)
Helm           : $(helm version --short 2>/dev/null || echo "non installé")
k3s            : NON installé — c'est l'objet de L26.1.
EOF
