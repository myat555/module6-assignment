"""Inventory Service - a tiny HTTP server (stdlib only).

Endpoints:
  GET /items   -> inventory list plus the name of the Pod that served it
  GET /healthz -> liveness (always 200 while the process is up)
  GET /ready   -> readiness: 200 normally, 503 if the file /tmp/unready exists

Readiness is toggled from outside the Pod with:
  kubectl exec <pod> -- touch /tmp/unready   # fail readiness
  kubectl exec <pod> -- rm /tmp/unready      # restore readiness
"""
import json
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

POD_NAME = os.environ.get("POD_NAME", socket.gethostname())
POD_IP = os.environ.get("POD_IP", "unknown")
UNREADY_FLAG = "/tmp/unready"
PORT = int(os.environ.get("PORT", "8080"))

INVENTORY = [
    {"sku": "A-100", "name": "widget", "qty": 42},
    {"sku": "B-200", "name": "gadget", "qty": 7},
    {"sku": "C-300", "name": "doohickey", "qty": 0},
]


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/items":
            self._send(200, {"served_by": POD_NAME, "pod_ip": POD_IP, "items": INVENTORY})
        elif self.path == "/healthz":
            self._send(200, {"status": "alive", "pod": POD_NAME})
        elif self.path == "/ready":
            if os.path.exists(UNREADY_FLAG):
                self._send(503, {"status": "not-ready", "pod": POD_NAME})
            else:
                self._send(200, {"status": "ready", "pod": POD_NAME})
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        # Skip probe noise so the Pod log only shows real traffic.
        if "/ready" in self.path or "/healthz" in self.path:
            return
        print(f"[{POD_NAME}] {self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    print(f"Inventory Service starting on :{PORT} as {POD_NAME} ({POD_IP})", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
