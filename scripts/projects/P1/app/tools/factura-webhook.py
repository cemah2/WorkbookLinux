#!/usr/bin/env python3
"""Factura — récepteur de webhook d'alerte local (projet A du workbook).

Un serveur HTTP minimal qui accepte des POST et écrit chaque alerte reçue,
horodatée, dans un journal. Il joue le rôle d'un Slack/Teams/PagerDuty de
lab : la supervision (PA.8) envoie ses alertes ici.

  FACTURA_WEBHOOK_BIND  adresse d'écoute (défaut : 127.0.0.1)
  FACTURA_WEBHOOK_PORT  port (défaut : 9999)
  FACTURA_WEBHOOK_LOG   journal (défaut : /var/log/factura/webhook.log)

Test : curl -s -X POST -H 'Content-Type: application/json' \
         -d '{"source":"test","message":"bonjour"}' http://127.0.0.1:9999/
"""
import json
import os
import sys
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer

BIND = os.environ.get("FACTURA_WEBHOOK_BIND", "127.0.0.1")
PORT = int(os.environ.get("FACTURA_WEBHOOK_PORT", "9999"))
LOG = os.environ.get("FACTURA_WEBHOOK_LOG", "/var/log/factura/webhook.log")


class Handler(BaseHTTPRequestHandler):
    server_version = "factura-webhook/1.0"

    def log_message(self, fmt, *args):  # journal d'accès sur stderr
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"factura-webhook ok\n")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length).decode("utf-8", "replace")
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            payload = {"raw": raw}
        line = "%s %s %s\n" % (
            datetime.now().astimezone().isoformat(timespec="seconds"),
            self.client_address[0],
            json.dumps(payload, ensure_ascii=False))
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(line)
        self.send_response(202)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"accepted": true}\n')


if __name__ == "__main__":
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    srv = HTTPServer((BIND, PORT), Handler)
    sys.stderr.write("factura-webhook en ecoute sur %s:%d, journal %s\n"
                     % (BIND, PORT, LOG))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
