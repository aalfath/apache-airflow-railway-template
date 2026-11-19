"""Tiny health endpoint for Airflow components that have none of their own.

Serves GET /health on $PORT. Returns 503 until the component has checked in once
(a job heartbeat for the DAG processor and triggerer, a Celery ping for the worker),
then 200. If the component process exits, the container exits with it.
"""
import os
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROLE = sys.argv[1]
READY = threading.Event()


def check() -> bool:
    if ROLE == "worker":
        cmd = ["celery", "--app", "airflow.providers.celery.executors.celery_executor.app",
               "inspect", "ping", "-d", f"celery@{socket.gethostname()}"]
    else:
        job = {"dag-processor": "DagProcessorJob", "triggerer": "TriggererJob"}[ROLE]
        cmd = ["airflow", "jobs", "check", "--job-type", job, "--local"]
    try:
        return subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60).returncode == 0
    except Exception:
        return False


def poll() -> None:
    time.sleep(15)
    while not READY.is_set():
        if check():
            READY.set()
            print(f"[railway] {ROLE} is healthy", flush=True)
            return
        time.sleep(10)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        ok = READY.is_set()
        self.send_response(200 if ok else 503)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"ok\n" if ok else b"starting\n")

    def log_message(self, *args):
        pass


class Server(ThreadingHTTPServer):
    # Dual-stack: IPv6 and IPv4 on one socket.
    address_family = socket.AF_INET6
    daemon_threads = True

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


threading.Thread(target=poll, daemon=True).start()
Server(("::", int(os.environ.get("PORT", "8080"))), Handler).serve_forever()
