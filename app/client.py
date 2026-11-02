"""Inventory client - calls the Inventory Service by its Kubernetes Service name.

It never uses Pod IPs: the only address it knows is INVENTORY_URL, which
defaults to the cluster DNS name of the Service.
"""
import json
import os
import time
import urllib.request
from datetime import datetime

URL = os.environ.get("INVENTORY_URL", "http://inventory-service:80/items")
INTERVAL = float(os.environ.get("INTERVAL_SECONDS", "1"))

print(f"client starting, target={URL}", flush=True)
while True:
    ts = datetime.now().strftime("%H:%M:%S")
    try:
        # A fresh connection per request lets kube-proxy pick a backend each time.
        with urllib.request.urlopen(URL, timeout=2) as resp:
            body = json.load(resp)
        print(f"{ts} OK  served_by={body['served_by']} pod_ip={body['pod_ip']}", flush=True)
    except Exception as exc:
        print(f"{ts} ERR {exc}", flush=True)
    time.sleep(INTERVAL)
