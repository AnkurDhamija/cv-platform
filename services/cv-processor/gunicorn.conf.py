"""Production Gunicorn configuration (shared shape across services).

Reads env so the same image behaves correctly in dev and prod without a rebuild.
Designed for a read-only root filesystem + non-root user (Kubernetes).
"""
import multiprocessing
import os

# --- Networking --------------------------------------------------------------
bind = f"0.0.0.0:{os.environ.get('PORT', '8081')}"

# --- Concurrency (I/O-bound service -> threads) ------------------------------
worker_class = "gthread"
workers = int(os.environ.get("WEB_CONCURRENCY", max(2, multiprocessing.cpu_count())))
threads = int(os.environ.get("GUNICORN_THREADS", "4"))

# --- Timeouts / lifecycle ----------------------------------------------------
timeout = int(os.environ.get("GUNICORN_TIMEOUT", "30"))
graceful_timeout = 30
keepalive = 5

# Recycle workers periodically to bound memory growth / leaks.
max_requests = int(os.environ.get("GUNICORN_MAX_REQUESTS", "1000"))
max_requests_jitter = 100

# Heartbeat/temp files must live on a writable tmpfs (root fs is read-only in k8s).
worker_tmp_dir = "/tmp"

# --- Logging (to stdout/stderr for the container log pipeline) ----------------
accesslog = "-"
errorlog = "-"
loglevel = os.environ.get("LOG_LEVEL", "info")
# Trust the ingress/Service in front of us for X-Forwarded-* headers.
forwarded_allow_ips = "*"
